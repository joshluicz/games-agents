--!strict
-- Achievement badges in six tiers, Bronze to Mythic (game/README.md "Badges"). Server only; the rules are
-- Logic/Badges (Lune-tested) and the list is Data/Badges.
--
--   Badges.add(p, counts)             adds { [counter]: n } to the player's Data.Stats (e.g. { ["Made:Remedy"] = 1 })
--   Badges.onCure(cure)               Cure calls it once per cure: the helper's Cures, its wing and night counters,
--                                     a friend helped (helper ~= owner: the helper's Friendly); the owner's Visitors
--   Badges.onMade(p, stationId)       Stations calls it after a treatment is made: "Made:<StationId>"
--   Badges.onHeart(p)                 Visits calls it when p sends a heart: Friendly
--   Badges.maxAll(p): boolean         the 🛠️ Admin panel only: every badge to its top tier, with its rewards
--   Badges.awardRoblox(p, key)        a Roblox badge by its Config.Badges key (0 = not created: skipped), in a pcall,
--                                     once per session; Server/Playtime uses it for the Doctor ranks
--
-- Levelling up: after any change to a player's save (PlayerData.Changed, coalesced to once per frame) every badge's
-- stat is checked against its thresholds (derived stats included: play hours, story beats, rooms and decor). A
-- badge past its saved tier (Data.Badges) moves up, and the tiers passed pay their Cash and Stars once
-- (Economy.addCash, Progress.addStars), with one toast. Tiers never go down. The boosts the tiers give are read
-- by Server/Boosts from Data.Badges.
-- Seeding: a save from before badges (Data.Stats without "Seeded") gets its counters worked out once from what it
-- already has (Logic/Badges.seed: Cured, the Patient Book, Today's Visitor), so existing players start with credit.
-- Roblox badges: only Gold 🏥 Healer here (and the Doctor ranks in Server/Playtime), so there are only a few to make.

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local BadgeData = require(Shared.Data.Badges)
local PatientsData = require(Shared.Data.Patients)
local RegularsData = require(Shared.Data.Regulars)
local AilmentsData = require(Shared.Data.Ailments)
local BadgesLogic = require(Shared.Logic.Badges)
local PlayerData = require(script.Parent.PlayerData)
local Economy = require(script.Parent.Economy)
local Progress = require(script.Parent.Progress)

local Badges = {}

local GOLD = 3
local MAX_KEY_LENGTH = 40

local DEFS = BadgeData.List :: { BadgesLogic.Def }
local TIERS = BadgeData.Tiers :: { BadgesLogic.Tier }

local queued: { [Player]: boolean } = {}
local robloxDone: { [Player]: { [number]: boolean } } = {}

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function present(player: any): boolean
	return isPlayer(player) and player.Parent == Players
end

local function defOf(id: string): BadgesLogic.Def?
	for _, def in DEFS do
		if def.Id == id then
			return def
		end
	end
	return nil
end

-- Every creature id (patients and regulars) -> its wing, the station that treats it, and whether it's a night one.
local function creatures(): { [string]: BadgesLogic.Creature }
	local out: { [string]: BadgesLogic.Creature } = {}
	local function add(id: string, row: any, night: boolean)
		local ailment = rawget(AilmentsData :: any, row.Ailment)
		out[id] = { Wing = row.Wing, Station = if ailment then ailment.Station else nil, Night = night }
	end
	for _, id in PatientsData.Order do
		local row = PatientsData[id]
		add(id, row, row.Night == true)
	end
	for _, id in RegularsData.Order do
		local row = RegularsData[id]
		add(id, row, row.Wing == "Night")
	end
	return out
end

local CREATURES = creatures()

------------------------------------------------------------------------------------------------------------------
-- Roblox badges
------------------------------------------------------------------------------------------------------------------

function Badges.awardRoblox(player: Player, key: string)
	local badgeId = (Config.Badges :: any)[key]
	if not present(player) or type(badgeId) ~= "number" or badgeId <= 0 then
		return -- not created in Creator Hub yet (Config.Badges = 0)
	end
	local done = robloxDone[player]
	if not done then
		done = {}
		robloxDone[player] = done
	end
	if done[badgeId] then
		return
	end
	done[badgeId] = true
	task.spawn(function()
		local okHas, has = pcall(function()
			return BadgeService:UserHasBadgeAsync(player.UserId, badgeId)
		end)
		if okHas and has == true then
			return
		end
		local ok, err = pcall(function()
			return BadgeService:AwardBadge(player.UserId, badgeId)
		end)
		if not ok then
			done[badgeId] = nil -- try again next time
			warn(("[Badges] Could not award Roblox badge %s (%d): %s"):format(key, badgeId, tostring(err)))
		end
	end)
end

------------------------------------------------------------------------------------------------------------------
-- Levelling up
------------------------------------------------------------------------------------------------------------------

local function check(player: Player)
	local data = PlayerData.get(player)
	if not data or not present(player) then
		return
	end
	local ups = BadgesLogic.ups(data.Badges, data, DEFS)
	if #ups == 0 then
		return
	end
	local saved = PlayerData.update(player, function(d)
		for _, up in ups do
			d.Badges[up.Id] = up.To
		end
	end)
	if not saved then
		return
	end
	local cash, stars = 0, 0
	for _, up in ups do
		local reward = BadgesLogic.reward(up.From, up.To, TIERS)
		cash += reward.Cash
		stars += reward.Stars
	end
	if cash > 0 then
		Economy.addCash(player, cash)
	end
	if stars > 0 then
		Progress.addStars(player, stars)
	end
	local first = ups[1]
	local def = defOf(first.Id)
	local tier = TIERS[first.To]
	if #ups == 1 and def and tier then
		Remotes.news(player, tier.Icon .. " " .. tier.Name .. " " .. def.Name .. "! 💰" .. cash .. " ⭐" .. stars)
	else
		Remotes.news(player, "🏅 " .. #ups .. " badges up! 💰" .. cash .. " ⭐" .. stars)
	end
	if (data.Badges.Healer or 0) >= GOLD then
		Badges.awardRoblox(player, "HealerGold")
	end
end

-- Many changes land in one frame (a cure is several updates): check once, after them.
local function queueCheck(player: Player)
	if queued[player] then
		return
	end
	queued[player] = true
	task.defer(function()
		queued[player] = nil
		local ok, err = pcall(check, player)
		if not ok then
			warn("[Badges] Check failed:", err)
		end
	end)
end

local function seed(player: Player, data: Types.Data)
	if data.Stats[BadgesLogic.SEEDED] == 1 then
		return
	end
	local seeded = BadgesLogic.seed(data, CREATURES)
	PlayerData.update(player, function(d)
		for key, value in seeded do
			d.Stats[key] = math.max(d.Stats[key] or 0, value)
		end
	end)
end

------------------------------------------------------------------------------------------------------------------
-- Counting
------------------------------------------------------------------------------------------------------------------

function Badges.add(player: Player, counts: { [string]: number }): boolean
	if not present(player) or type(counts) ~= "table" then
		return false
	end
	local clean: { [string]: number } = {}
	for key, n in counts do
		if type(key) == "string" and #key <= MAX_KEY_LENGTH and type(n) == "number" and n >= 1 and n < math.huge then
			clean[key] = n
		end
	end
	if next(clean) == nil or not PlayerData.get(player) then
		return false
	end
	return PlayerData.update(player, function(d)
		d.Stats = BadgesLogic.add(d.Stats, clean)
	end)
end

function Badges.onCure(cure: Types.CureCtx)
	if type(cure) ~= "table" then
		return
	end
	local helper, owner = cure.Helper, cure.Owner
	local info = CREATURES[if type(cure.Regular) == "string" then cure.Regular else cure.PatientId]
	if present(helper) then
		local counts: { [string]: number } = { Cures = 1 }
		if info then
			counts["Cures:" .. info.Wing] = 1
		end
		if cure.Night then
			counts.NightCures = 1
		end
		if owner ~= helper then
			counts.Friendly = 1 -- helped a friend's clinic
		end
		Badges.add(helper, counts)
	end
	if cure.Visitor and present(owner) then
		Badges.add(owner, { Visitors = 1 })
	end
end

function Badges.onMade(player: Player, stationId: string)
	if type(stationId) == "string" then
		Badges.add(player, { ["Made:" .. stationId] = 1 })
	end
end

function Badges.onHeart(player: Player)
	Badges.add(player, { Friendly = 1 })
end

function Badges.maxAll(player: Player): boolean
	local data = if present(player) then PlayerData.get(player) else nil
	if not data then
		return false
	end
	local ups = BadgesLogic.ups(data.Badges, data, DEFS, true)
	local saved = PlayerData.update(player, function(d)
		d.Stats = BadgesLogic.maxed(d.Stats, DEFS)
		for _, up in ups do
			d.Badges[up.Id] = up.To
		end
	end)
	if not saved then
		return false
	end
	local cash, stars = 0, 0
	for _, up in ups do
		local reward = BadgesLogic.reward(up.From, up.To, TIERS)
		cash += reward.Cash
		stars += reward.Stars
	end
	if cash > 0 then
		Economy.addCash(player, cash)
	end
	if stars > 0 then
		Progress.addStars(player, stars)
	end
	Badges.awardRoblox(player, "HealerGold")
	return true
end

function Badges.start()
	PlayerData.Loaded:Connect(function(player: Player, data: Types.Data)
		seed(player, data)
		queueCheck(player)
		if (data.Badges.Healer or 0) >= GOLD then
			Badges.awardRoblox(player, "HealerGold") -- a badge created after they got there
		end
	end)
	PlayerData.Changed:Connect(function(player: Player)
		queueCheck(player)
	end)
	for _, player in Players:GetPlayers() do
		local data = PlayerData.get(player)
		if data then
			seed(player, data) -- loaded before we were listening
			queueCheck(player)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		queued[player] = nil
		robloxDone[player] = nil
	end)
end

return Badges
