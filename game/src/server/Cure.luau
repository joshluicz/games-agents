--!strict
-- The one place a finished visit lands (build plan §B5; the code keeps its old name, "cure", internally: the Cured
-- remote, the Cured save field and count, the leaderboard ids). Server only. Patients calls it once per patient whose
-- plan is done, after any ward stay; nothing else pays for a visit. OWNER: T7 (Progression v2); the Real Clinic
-- (Task 5) only drops the old hot tub's bonus flag.
--   Cure.resolve(ctx: Types.CureCtx): Result?
--
-- In order (each step is guarded, so a broken system downstream never stops the payout before it):
--   1. Pay.reward                 cash and stars for this visit (the owner's Tip Jar counts: it's their clinic; so
--                                 do the plan's length and the plot's Cheerer, ctx.Items and ctx.Cheer). Boosts
--                                 (Server/Boosts): the helper's Cash and Tips boosts (they earn the cash) and the
--                                 owner's Stars boost (they earn the stars), scoped to night and the patient's wing.
--                                 Every factor multiplies once, in Logic/Pay, with one rounding at the end.
--                                 Progression v2 (build plan §B8): ctx.Urgent ("AE" x3 + 2 ⭐ · "VIP" x4 + 3 ⭐), the
--                                 owner's Night Clinic level (night cures), the Golden variant (x5, Pay), ctx.Extra
--                                 (Patients' escort / triage / team / Ward Comfort factor) x the plot's
--                                 banked Double Dose, and + the banked Star Burst stars: Abilities.consumeCure(ctx.Plot)
--                                 is asked ONCE per cure (x1 and +0 when nothing is banked)
--   2. Economy.addCash(helper)    the helper earns the cash (and their Cured count goes up, and this UTC week's
--                                 count for the weekly leaderboard: Logic/Leaderboard.addWeekCure), then
--                                 Badges.onCure counts the cure for the badges (Server/Badges)
--   3. Progress.addStars(owner)   the clinic's owner earns the Clinic Stars (design §5.9: friends' cures count)
--   4. Book.stamp(helper)         the helper's Patient Book
--   5. Daily.onCure(helper, ctx)  the helper's daily goals
--   6. Story.onCure(owner, regular)   only when the patient is a regular
--   7. DayReport.record           the helper's report gets the cure, any new page and the cash step 2 paid; the
--                                 owner's report gets the stars (and the cure too, when a friend did it)
--   8. the Cured remote           to the helper, and to the owner if different. Each payload says what THAT
--                                 player got: the owner of a friend's cure sees Cash 0, a helper on someone
--                                 else's plot sees Stars 0, and NewPage is the helper's.
--   9. Nurses.onCure(owner, { Wing, Urgent, Dept })   XP for every nurse working at the owner's clinic (Progression
--                                 v2; T1 adds the specialty XP from Dept, the department it recovered in)
--  10. Tutorial.onCured(owner)    a cure at the owner's clinic moves their first-session tutorial on (if they're in
--                                 it), after everything above has landed
-- Either player may have left while the patient recovered: their part is skipped and the other still lands.
-- Returns what the cure paid ({ Cash, Stars, NewPage }) or nil when the ctx was rejected.
-- Requires Abilities and Nurses (never the other way round: build plan §B10).

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
local Abilities = require(script.Parent.Abilities)
local Nurses = require(script.Parent.Nurses)
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

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- A short id-like string (a WingId or DeptId), or nil.
local function shortId(value: any): string?
	return if type(value) == "string" and #value > 0 and #value <= 20 then value else nil
end

-- What the plot's banked abilities add to this cure (Double Dose: x Cash; Star Burst: + Stars), spending them.
-- Asked once per cure; junk answers count as nothing banked.
local function banked(plot: Types.Plot?): (number, number)
	if plot == nil then
		return 1, 0
	end
	local ok, got = pcall(Abilities.consumeCure, plot)
	if not ok then
		warn("[Cure] Abilities.consumeCure failed: " .. tostring(got))
		return 1, 0
	end
	if type(got) ~= "table" then
		return 1, 0
	end
	local cash = if finite(got.Cash) then math.clamp(got.Cash, 1, Pay.MAX_EXTRA) else 1
	local stars = if finite(got.Stars) then math.clamp(math.floor(got.Stars), 0, Pay.MAX_BONUS_STARS) else 0
	return cash, stars
end

-- The urgent patient's extra Stars (Config.AE.Stars / Config.VIP.Stars).
local function urgentStars(urgent: string?): number
	local row = if urgent == "AE" then Config.AE elseif urgent == "VIP" then Config.VIP else nil
	local stars = if type(row) == "table" then row.Stars else nil
	return if finite(stars) then math.clamp(math.floor(stars), 0, Pay.MAX_BONUS_STARS) else 0
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
	local extra = ctx.Extra
	local plot = ctx.Plot
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
		-- Progression v2
		Urgent = if ctx.Urgent == "AE" or ctx.Urgent == "VIP" then ctx.Urgent else nil,
		Extra = if finite(extra) then math.clamp(extra, 1, Pay.MAX_EXTRA) else 1,
		Plot = if type(plot) == "table" and typeof(plot.Model) == "Instance" then plot else nil,
		Dept = shortId(ctx.Dept),
		Wing = shortId(ctx.Wing),
		-- Already paid inside Extra; carried on so the Cured payload's ↕️ bonus line shows. (The old hot tub's bonus
		-- flag is gone: the Bath Room's bath is a plan step now.)
		Escorted = ctx.Escorted == true,
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
	-- Progression v2: the plot's banked Double Dose / Star Burst (spent once, here), the urgent stars, Night Clinic.
	local doubleDose, starBurst = banked(cure.Plot)
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
		Urgent = cure.Urgent,
		NightClinic = if ownerHere then Economy.level(owner, "NightClinic") else 0,
		Extra = (cure.Extra or 1) * doubleDose, -- Pay caps it at Pay.MAX_EXTRA
		BonusStars = urgentStars(cure.Urgent) + starBurst,
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

	-- 7. Day Reports (the helper's carries the cash step 2 paid them; the owner's, when someone else helped, none)
	if helperHere then
		local helperStars = if sameHelper then reward.Stars else 0
		safely("DayReport.record", DayReport.record, helper, cure, newPage, helperStars, reward.Cash)
	end
	if ownerHere and not sameHelper then
		safely("DayReport.record", DayReport.record, owner, cure, false, reward.Stars, 0)
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
			-- Progression v2: always sent ("" / false = no), so Feel/CureFX never looks the patient model up.
			Urgent = if cure.Urgent == "AE" or cure.Urgent == "VIP" then cure.Urgent else "",
			Escorted = cure.Escorted == true,
		}
	end
	if helperHere then
		Remotes.Cured:FireClient(helper, info(reward.Cash, if sameHelper then reward.Stars else 0, newPage))
	end
	if ownerHere and not sameHelper then
		Remotes.Cured:FireClient(owner, info(0, reward.Stars, false))
	end

	-- 9. Nurse XP at the owner's clinic (Progression v2)
	if ownerHere then
		safely("Nurses.onCure", Nurses.onCure, owner, { Wing = cure.Wing, Urgent = cure.Urgent, Dept = cure.Dept })
	end

	-- 10. The owner's first-session tutorial
	if ownerHere then
		safely("Tutorial.onCured", Tutorial.onCured, owner)
	end

	return { Cash = reward.Cash, Stars = reward.Stars, NewPage = newPage }
end

function Cure.start() end

return Cure
