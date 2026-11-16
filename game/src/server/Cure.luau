--!strict
-- The one place a cure lands (build plan §B5). Server only. Patients calls it once per cured patient, after the
-- patient has recovered; nothing else pays for a cure.
--   Cure.resolve(ctx: Types.CureCtx): Result?
--
-- In order (each step is guarded, so a broken system downstream never stops the payout before it):
--   1. Pay.reward                 cash and stars for this cure (the owner's Tip Jar counts: it's their clinic; so
--                                 do the recipe's length and the plot's Cheerer, ctx.Items and ctx.Cheer). Boosts
--                                 (Server/Boosts): the helper's Cash and Tips boosts (they earn the cash) and the
--                                 owner's Stars boost (they earn the stars), scoped to night and the patient's wing.
--                                 Every factor multiplies once, in Logic/Pay, with one rounding at the end
--   2. Economy.addCash(helper)    the helper earns the cash (and their Cured count goes up, and this UTC week's
--                                 count for the weekly leaderboard: Logic/Leaderboard.addWeekCure), then
--                                 Badges.onCure counts the cure for the badges (Server/Badges)
--   3. Progress.addStars(owner)   the clinic's owner earns the Clinic Stars (design §5.9: friends' cures count)
--   4. Book.stamp(helper)         the helper's Patient Book
--   5. Daily.onCure(helper, ctx)  the helper's daily goals
--   6. Story.onCure(owner, regular)   only when the patient is a regular
--   7. DayReport.record           the helper's report gets the cure and any new page; the owner's report gets the
--                                 stars (and the cure too, when a friend did it)
--   8. the Cured remote           to the helper, and to the owner if different. Each payload says what THAT
--                                 player got: the owner of a friend's cure sees Cash 0, a helper on someone
--                                 else's plot sees Stars 0, and NewPage is the helper's.
--   9. Tutorial.onCured(owner)    a cure at the owner's clinic moves their first-session tutorial on (if they're in
--                                 it), after everything above has landed
-- Either player may have left while the patient recovered: their part is skipped and the other still lands.
-- Returns what the cure paid ({ Cash, Stars, NewPage }) or nil when the ctx was rejected.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Patients = require(Shared.Data.Patients)
local Regulars = require(Shared.Data.Regulars)
local Variants = require(Shared.Data.Variants)
local Pay = require(Shared.Logic.Pay)
local Leaderboard = require(Shared.Logic.Leaderboard)
local PlayerData = require(script.Parent.PlayerData)
local Economy = require(script.Parent.Economy)
local Progress = require(script.Parent.Progress)
local Book = require(script.Parent.Book)
local Daily = require(script.Parent.Daily)
local Story = require(script.Parent.Story)
local DayReport = require(script.Parent.DayReport)
local Tutorial = require(script.Parent.Tutorial)
local Boosts = require(script.Parent.Boosts) -- playtime branch: boosts on pay
local Badges = require(script.Parent.Badges) -- playtime branch: badge counters

export type Result = { Cash: number, Stars: number, NewPage: boolean }

local Cure = {}

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function present(player: Player?): boolean
	return player ~= nil and player.Parent == Players
end

-- Runs one downstream step; a step that errors is reported and skipped.
local function safely(label: string, fn: (...any) -> ...any, ...: any): (boolean, ...any)
	local results = table.pack(pcall(fn, ...))
	if not results[1] then
		warn("[Cure] " .. label .. " failed: " .. tostring(results[2]))
		return false
	end
	return table.unpack(results, 1, results.n)
end

local function knownCreature(id: any): boolean
	return type(id) == "string" and (rawget(Patients :: any, id) ~= nil or rawget(Regulars :: any, id) ~= nil)
end

-- A clean copy of the ctx: every field the right type, unknown ids dropped. nil if it can't be a cure.
local function sanitize(ctx: any): Types.CureCtx?
	if type(ctx) ~= "table" or not isPlayer(ctx.Helper) or not isPlayer(ctx.Owner) then
		return nil
	end
	if not knownCreature(ctx.PatientId) then
		return nil
	end
	local variant = ctx.Variant
	local regular = ctx.Regular
	local patience = ctx.PatienceLeft
	if type(patience) ~= "number" or patience ~= patience then
		patience = 0
	end
	local items = ctx.Items
	local cheer = ctx.Cheer
	return {
		Helper = ctx.Helper,
		Owner = ctx.Owner,
		PatientId = ctx.PatientId,
		Variant = if type(variant) == "string" and rawget(Variants :: any, variant) then variant else nil,
		Night = ctx.Night == true,
		Regular = if type(regular) == "string" and rawget(Regulars :: any, regular) then regular else nil,
		Visitor = ctx.Visitor == true,
		PatienceLeft = math.clamp(patience, 0, 1),
		Position = if typeof(ctx.Position) == "Vector3" then ctx.Position else Vector3.zero,
		Items = if type(items) == "number" and items == items
			then math.clamp(math.floor(items), 1, Pay.MAX_ITEMS)
			else 1,
		Cheer = if type(cheer) == "number" and cheer == cheer then math.clamp(cheer, 1, Pay.MAX_CHEER) else 1,
	}
end

function Cure.resolve(ctx: Types.CureCtx): Result?
	local cure = sanitize(ctx)
	if not cure then
		warn("[Cure] resolve ignored a bad ctx for", if type(ctx) == "table" then ctx.PatientId else ctx)
		return nil
	end
	local helper, owner = cure.Helper, cure.Owner
	local helperHere, ownerHere = present(helper), present(owner)
	if not helperHere and not ownerHere then
		return nil
	end
	local sameHelper = helper == owner

	-- 1. Pay
	-- >>> playtime branch: boosts (Server/Boosts). Helper: Cash and Tips; owner: Stars.
	local cashBoost, tipsBoost, starsBoost = 1, 0, 1
	safely("Boosts", function()
		local scopes = Boosts.cureScopes(cure)
		cashBoost = if helperHere then Boosts.multiplier(helper, "Cash", scopes) else 1
		tipsBoost = if helperHere then Boosts.percent(helper, "Tips", scopes) / 100 else 0
		starsBoost = if ownerHere then Boosts.multiplier(owner, "Stars", scopes) else 1
	end)
	-- <<< playtime branch
	local reward = Pay.reward({
		BasePay = Config.BasePay,
		Tips = if ownerHere then Economy.level(owner, "Tips") else 0,
		PatienceLeft = cure.PatienceLeft,
		Night = cure.Night,
		Variant = cure.Variant,
		Visitor = cure.Visitor,
		Regular = cure.Regular ~= nil,
		Items = cure.Items,
		Cheer = cure.Cheer,
		Cfg = Config,
		CashBoost = cashBoost, -- playtime branch
		TipsBoost = tipsBoost, -- playtime branch
		StarsBoost = starsBoost, -- playtime branch
	})

	-- 2. The helper's cash and Cured count
	if helperHere then
		safely("Economy.addCash", Economy.addCash, helper, reward.Cash)
		local week = Leaderboard.week(os.time())
		PlayerData.update(helper, function(d)
			d.Cured += 1
			Leaderboard.addWeekCure(d.WeekCures, week)
		end)
	end
	safely("Badges.onCure", Badges.onCure, cure) -- playtime branch: badge counters (helper and owner)

	-- 3. The owner's Clinic Stars
	if ownerHere then
		safely("Progress.addStars", Progress.addStars, owner, reward.Stars)
	end

	-- 4. The helper's Patient Book
	local newPage = false
	if helperHere then
		local ok, page = safely("Book.stamp", Book.stamp, helper, cure.PatientId, cure.Variant)
		newPage = ok and page == true
	end

	-- 5. The helper's daily goals
	if helperHere then
		safely("Daily.onCure", Daily.onCure, helper, cure)
	end

	-- 6. A regular's story moves on at the owner's clinic
	if ownerHere and cure.Regular then
		safely("Story.onCure", Story.onCure, owner, cure.Regular)
	end

	-- 7. Day Reports
	if helperHere then
		safely("DayReport.record", DayReport.record, helper, cure, newPage, if sameHelper then reward.Stars else 0)
	end
	if ownerHere and not sameHelper then
		safely("DayReport.record", DayReport.record, owner, cure, false, reward.Stars)
	end

	-- 8. Tell the players (CureFX plays the sparkle and "+cash" pop from Position)
	local function info(cash: number, stars: number, page: boolean): Types.CuredInfo
		return {
			PatientId = cure.PatientId,
			Variant = cure.Variant,
			Cash = cash,
			Stars = stars,
			NewPage = page,
			Position = cure.Position,
			Helper = helper.UserId,
		}
	end
	if helperHere then
		Remotes.Cured:FireClient(helper, info(reward.Cash, if sameHelper then reward.Stars else 0, newPage))
	end
	if ownerHere and not sameHelper then
		Remotes.Cured:FireClient(owner, info(0, reward.Stars, false))
	end

	-- 9. The owner's first-session tutorial
	if ownerHere then
		safely("Tutorial.onCured", Tutorial.onCured, owner)
	end

	return { Cash = reward.Cash, Stars = reward.Stars, NewPage = newPage }
end

function Cure.start() end

return Cure
