--!strict
-- Boosts (game/README.md "Boosts"): how much stronger a player's cures, treatments and patients are. Server only; the
-- rules are Logic/Boosts (Lune-tested). Everything is earned in play: nothing here is paid or random.
--
--   Boosts.multiplier(p, kind, scopes?): number   1 + percent/100 (kind "Cash" | "Stars" | "MakeSpeed" | "Patience" |
--                                                 "Tips"; scopes e.g. { Night = true, Starter = true, Remedy = true }).
--                                                 Progression v2: "Cash" and "Stars" are then x Logic/Rebirth.multiplier
--                                                 (+25% a rebirth, added, up to 20); the other kinds take no rebirth part
--   Boosts.percent(p, kind, scopes?): number      the percent: permanent (capped by Config.BoostCaps) + the branch
--                                                 (the tree and perks, Logic/Rebirth.effects, capped by
--                                                 Config.BranchCaps) + timed. No rebirth part (it multiplies)
--   Boosts.addTimed(p, boostId, seconds?): boolean   starts or EXTENDS a Data/Boosts timed boost (default: its own
--                                                 Minutes), up to Config.BoostMaxMinutes; never stacks
--   Boosts.list(p): Types.BoostList               the Snapshot's Boosts: timed ones running, permanent percents, the
--                                                 capped Branch percents and the Rebirth multipliers { Cash, Stars }
--   Boosts.makeSeconds(p, stationId): number      the hold time at that station: Faster Hands (the 💊 Pharmacy:
--                                                 Config.Pharmacy.HoldSeconds, x Tier2Factor from R2), then MakeSpeed
--   Boosts.cureScopes(cure): Scopes               the scopes a cure counts for: "Night", and its wing
--   Boosts.hook(pending, flush)                   Server/Playtime: the active seconds counted but not saved yet,
--                                                 and a way to save them (timed boosts tick with those seconds)
--
-- Permanent boosts come from the save: the Doctor rank rewarded (Data/Playtime.Ranks[Rank].Cash) and every badge's
-- tier (Logic/Badges.effects). Their total per kind is capped (Config.BoostCaps). Timed boosts (Data.Boosts) tick only
-- with active play: Server/Playtime takes its seconds off when it saves them, and until then they're taken off here
-- on the fly, so a boost ends on time without a save every second.

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local BoostData = require(Shared.Data.Boosts)
local BadgeData = require(Shared.Data.Badges)
local PlaytimeData = require(Shared.Data.Playtime)
local PatientsData = require(Shared.Data.Patients)
local RegularsData = require(Shared.Data.Regulars)
local BoostsLogic = require(Shared.Logic.Boosts)
local BadgesLogic = require(Shared.Logic.Badges)
local RebirthLogic = require(Shared.Logic.Rebirth)
local PerksData = require(Shared.Data.Perks)
local TreeData = require(Shared.Data.Tree)
local Prices = require(Shared.Logic.Prices)
local PlayerData = require(script.Parent.PlayerData)
local Economy = require(script.Parent.Economy)

local Boosts = {}

local pendingFn: ((Player) -> number)? = nil
local flushFn: ((Player) -> ())? = nil

function Boosts.hook(pending: (Player) -> number, flush: (Player) -> ())
	pendingFn = pending
	flushFn = flush
end

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function pending(player: Player): number
	local fn = pendingFn
	if not fn then
		return 0
	end
	local ok, seconds = pcall(fn, player)
	return if ok and type(seconds) == "number" and seconds == seconds and seconds > 0 then seconds else 0
end

-- The timed boosts running right now (the saved seconds less the active seconds not saved yet).
local function liveTimed(player: Player, data: Types.Data): { [string]: number }
	return BoostsLogic.tick(data.Boosts, pending(player))
end

local function effects(data: Types.Data): { BoostsLogic.Effect }
	local list = BadgesLogic.effects(data.Badges, BadgeData.List)
	local rank = PlaytimeData.Ranks[data.Playtime.Rank]
	if rank and rank.Cash > 0 then
		table.insert(list, { Kind = "Cash", Percent = rank.Cash })
	end
	return list
end

-- The branch source: the tree's and the perks' percents (Logic/Rebirth.effects), everywhere.
local function branch(data: Types.Data): BoostsLogic.Branch
	local fx = RebirthLogic.effects(data, Config, PerksData, TreeData)
	return { Cash = fx.Cash, Stars = fx.Stars, Tips = fx.Tips, MakeSpeed = fx.MakeSpeed, Patience = fx.Patience }
end

function Boosts.percent(player: Player, kind: string, scopes: BoostsLogic.Scopes?): number
	local data = if isPlayer(player) then PlayerData.get(player) else nil
	if not data or type(kind) ~= "string" then
		return 0
	end
	return BoostsLogic.percent(
		effects(data),
		liveTimed(player, data),
		BoostData,
		kind,
		scopes,
		Config.BoostCaps,
		branch(data),
		Config.BranchCaps
	)
end

function Boosts.multiplier(player: Player, kind: string, scopes: BoostsLogic.Scopes?): number
	local base = 1 + Boosts.percent(player, kind, scopes) / 100
	if kind ~= "Cash" and kind ~= "Stars" then
		return base
	end
	local data = if isPlayer(player) then PlayerData.get(player) else nil
	local count = if data then data.Rebirth.Count else 0
	return base * RebirthLogic.multiplier(count, Config, kind)
end

function Boosts.addTimed(player: Player, boostId: string, seconds: number?): boolean
	local def = if type(boostId) == "string" then rawget(BoostData :: any, boostId) else nil
	if not isPlayer(player) or type(def) ~= "table" or not PlayerData.get(player) then
		return false
	end
	-- Save the active seconds counted so far first: they ran before this boost and must not eat into it.
	local flush = flushFn
	if flush then
		pcall(flush, player)
	end
	local add = if type(seconds) == "number" and seconds > 0 then seconds else def.Minutes * 60
	return PlayerData.update(player, function(d)
		d.Boosts = BoostsLogic.extend(d.Boosts, BoostData, boostId, add, Config.BoostMaxMinutes * 60)
	end)
end

function Boosts.list(player: Player): Types.BoostList
	local data = if isPlayer(player) then PlayerData.get(player) else nil
	local out: Types.BoostList = { Timed = {}, Permanent = {}, Branch = {}, Rebirth = { Cash = 1, Stars = 1 } }
	if not data then
		return out
	end
	for _, id in BoostData.Order do
		local left = data.Boosts[id]
		if type(left) == "number" and left > 0 then
			table.insert(out.Timed, { Id = id, Left = left })
		end
	end
	out.Permanent = BoostsLogic.summary(effects(data), Config.BoostCaps)
	out.Branch = BoostsLogic.branchSummary(branch(data), Config.BranchCaps)
	out.Rebirth = {
		Cash = RebirthLogic.multiplier(data.Rebirth.Count, Config, "Cash"),
		Stars = RebirthLogic.multiplier(data.Rebirth.Count, Config, "Stars"),
	}
	return out
end

function Boosts.makeSeconds(player: Player, stationId: string): number
	local base = Prices.makeSeconds(Economy.level(player, "Speed"), Config)
	if stationId == "Pharmacy" then
		-- The 💊 Pharmacy has its own hold (§B8): Config.Pharmacy.HoldSeconds, x Tier2Factor from the maker's R2
		-- (the Pharmacy2 unlock). Stations and the Snapshot's MakeSeconds (UI/Guide's ring) both come through here.
		local data = PlayerData.get(player)
		local count = if data
				and type(data.Rebirth) == "table"
				and type(data.Rebirth.Count) == "number"
			then data.Rebirth.Count
			else 0
		base = Config.Pharmacy.HoldSeconds
			* (if RebirthLogic.has(count, "Pharmacy2") then Config.Pharmacy.Tier2Factor else 1)
	end
	local percent = Boosts.percent(player, "MakeSpeed", { [stationId] = true })
	return BoostsLogic.makeSeconds(base, percent, Config.BoostMinMakeSeconds)
end

function Boosts.cureScopes(cure: Types.CureCtx): BoostsLogic.Scopes
	local scopes: BoostsLogic.Scopes = {}
	if cure.Night then
		scopes.Night = true
	end
	local regular = if type(cure.Regular) == "string" then rawget(RegularsData :: any, cure.Regular) else nil
	local patient = rawget(PatientsData :: any, cure.PatientId) or rawget(RegularsData :: any, cure.PatientId)
	local row: any = regular or patient
	if type(row) == "table" and type(row.Wing) == "string" then
		scopes[row.Wing] = true
	end
	return scopes
end

function Boosts.start() end

return Boosts
