--!strict
-- Nurse signature abilities: cooldowns, triggers and effects (Progression v2 build plan §B5/§B8/§C T1; design §7,
-- memory-20261116-017). Server only. OWNER: T1. The rules are Logic/Abilities (Lune-tested); the content is
-- Data/Abilities; the state machine is the Pure block below (tests/NurseWork.spec).
--
-- Every ability fires BY ITSELF, only when it would help (Logic/Abilities.useful; build plan §E3: no button to learn).
-- "Banked" ones (Quick Plaster, Quick Soap, Golden Touch, Double Dose, Star Burst) light up when ready and wait: the
-- next matching treat or cure spends them, and their cooldown starts then. Cooldowns run in real seconds from the
-- moment an ability fired (Miracle: once per in-game day, until the next morning). Kids see a filling ring, never
-- seconds (red line 3). Nothing fires while the owner is away (their plot and its nurses are gone) or in the tutorial.
-- The state is kept by the owner's UserId for this server's life, so leaving and rejoining never recharges anything.
--
--   Abilities.start()                        one loop (every 0.5 s) over the plots whose owner is in the server and
--                                            done with the tutorial; the in-game day count (IsNight true -> false)
--   Abilities.Fired: Signal (plot, nurseId, abilityId, kind, value)
--                                            after an ability fires (a banked one: when charges are spent, value = how
--                                            many). Patients does RefillFront (the front bay patient: Visit.front),
--                                            RefillLine and PauseLine (everyone waiting: the seats and the bays);
--                                            Abilities itself does TrayItem (Nurses.addToTray: supplies only),
--                                            FastMake and InstantMake (the plot's MakeRushUntil / MakeRushFactor),
--                                            PauseLine's PatiencePausedUntil, Recharge (every OTHER ability at the plot
--                                            ready now; never a once-a-day one) and CureLine: 💫 Miracle finishes the
--                                            whole visit of every bay patient waiting for the doctor (not one in a
--                                            mini-game), medicine steps included (design §15 #1), through
--                                            Patients.finishVisit(plotModel, patientId, owner) (contract C6); its
--                                            Fired value is how many it finished, sent after they are
--   Abilities.consumePerfects(plot, games: { GameId }): { boolean }
--                                            Treatment asks at TreatStart (any helper at the plot): which games a
--                                            banked AutoPerfect makes PERFECT (a charge for that very game first, then
--                                            Golden Touch's any-game ones: Logic/Abilities.autoGames). Spends them.
--                                            Quick Plaster's game is "Plaster", Quick Soap's "Bath" (GameIds)
--   Abilities.consumeCure(plot): { Cash: number, Stars: number }
--                                            Cure asks once per treated patient: x2 Cash with a banked Double Dose (one
--                                            charge), + Stars with a banked Star Burst. x1 and +0 when none is banked
--   Abilities.patiencePaused(plot): boolean  Calm Song is pausing every waiting patient's patience
--   Abilities.makeFactor(plot): number       station holds x this: 1, 0.5 (Busy Paws) or 0 (Time Bubble: the shortest
--                                            hold); the strongest one running wins
--   Abilities.adminCharge(p): (ok, message)  Admin "ChargeAbilities": every ability at the player's clinic ready now
--                                            (Miracle too)
--   Abilities.Pure                           the state machine's pure helpers
--
-- On each working nurse's model (plot.Model.Nurses.Nurse_<NurseId>), written only when they change: AbilityReadyAt
-- (server time; <= now = ready), AbilityCooldown (seconds: the ring's length), AbilityCharges (banked charges left)
-- and AbilityAt (server time it last fired or spent a charge: clients play the sparkle). The ring billboard
-- (NurseBuilder.setAbility) fills in RING_STEPS steps per cooldown, never every frame. Plot attributes:
-- PatiencePausedUntil, MakeRushUntil (server times), MakeRushFactor.
-- The usefulness view (Logic/Abilities.useful) comes from Nurses.bays (the bay patients, front first, from
-- Patients.bayView) and the waiting room's patients (State "Waiting", their PatienceFraction).
-- Requires Nurses, PlayerData and Plots (and the NurseBuilder library); never Treatment, Cure or Stations (they require
-- this). Patients requires this module too, so Miracle requires it LAZILY (at fire time, never while loading).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)
local AbilitiesLogic = require(Shared.Logic.Abilities)
local RebirthLogic = require(Shared.Logic.Rebirth)
local RecipeLogic = require(Shared.Logic.Recipe)
local TutorialLogic = require(Shared.Logic.Tutorial)
local AbilitiesData = require(Shared.Data.Abilities)
local ItemsData = require(Shared.Data.Items)
local NursesData = require(Shared.Data.Nurses)
local PerksData = require(Shared.Data.Perks)
local TreeData = require(Shared.Data.Tree)
local NurseBuilder = require(script.Parent.NurseBuilder)
local Nurses = require(script.Parent.Nurses)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)

type Plot = Types.Plot
type Row = Nurses.Row

local Abilities = {}

Abilities.Fired = Signal.new()

------------------------------------------------------------------------------------------------------------------
-- Tuning (the design's numbers; the per-ability ones are in Data/Abilities and Config.Abilities)
------------------------------------------------------------------------------------------------------------------

local TICK = 0.5 -- seconds between looks at every plot
local RING_STEPS = 8 -- the ring fills in this many steps per cooldown (a server write each)
local NEAR_STATION = Config.Abilities.NearStation -- studs: Time Bubble needs the owner this close to a station
local FAST_MAKE = Config.Abilities.FastMake -- Busy Paws: station holds x this ("FastMake station holds x0.5")
local INSTANT_MAKE = 0 -- Time Bubble: the shortest hold (Stations clamps it to Config.BoostMinMakeSeconds)
local CASH_NEXT = Config.Abilities.CashNext -- Double Dose: a cure pays x this (design §7: "a cure pays x2")
local MAX_GAMES = 8 -- a treat session has at most this many games (more is junk)
local PRUNE_SECONDS = 60 -- how often the clinics of owners who left drop the slots a fresh one would equal

------------------------------------------------------------------------------------------------------------------
-- Pure helpers (no Roblox services, no upvalues: a Lune harness loads this block on its own)
------------------------------------------------------------------------------------------------------------------

-- PURE-BEGIN
local Pure = {}

Pure.LOW = 0.5 -- "under 50% patience" (Logic/Abilities.LOW; the spec checks they match)

export type Slot = {
	AbilityId: string,
	Kind: string,
	Daily: boolean,
	ReadyAt: number, -- server time: ready (or bankable) from then (a daily one: the next morning, for the ring)
	Cooldown: number, -- seconds: the current cooldown's length (the ring's)
	FiredAt: number, -- server time the cooldown started (0 = never)
	UsedAt: number, -- server time it last fired or spent a charge (the sparkle; 0 = never)
	Charges: number, -- banked charges left (0 = none banked)
	Day: number, -- a daily one: the in-game day it fired (-1 = never)
}
export type Rush = { Factor: number, Until: number }

-- A nurse's ability the first time this clinic sees it: ready now.
function Pure.newSlot(abilityId: string, kind: string, daily: boolean, cooldown: number, now: number): Slot
	return {
		AbilityId = abilityId,
		Kind = kind,
		Daily = daily,
		ReadyAt = now,
		Cooldown = math.max(1, cooldown),
		FiredAt = 0,
		UsedAt = 0,
		Charges = 0,
		Day = -1,
	}
end

-- Ready to fire (or to bank): a daily one that hasn't fired this in-game day; any other once its cooldown ran out.
function Pure.ready(slot: Slot, now: number, day: number): boolean
	if slot.Daily then
		return slot.Day ~= day
	end
	return slot.ReadyAt <= now
end

-- How many charges a banked kind holds: AutoPerfect Value games, CashNext Value cures, StarsNext one cure (+Value ⭐).
function Pure.charges(kind: string, value: number): number
	if kind == "StarsNext" then
		return 1
	end
	return math.max(1, math.floor(if type(value) == "number" and value == value then value else 1))
end

-- The cooldown starts (a fire, or the last banked charge spent). A daily one waits for the next in-game morning
-- (`morning`: the server-time estimate for its ring); every other one for `cooldown` seconds.
function Pure.startCooldown(slot: Slot, cooldown: number, now: number, day: number, morning: number?)
	slot.FiredAt = now
	slot.UsedAt = now
	slot.Charges = 0
	if slot.Daily then
		slot.Day = day
		local at = if type(morning) == "number" and morning > now then morning else now + math.max(1, cooldown)
		slot.ReadyAt = at
		slot.Cooldown = math.max(1, at - now)
	else
		slot.Cooldown = math.max(1, cooldown)
		slot.ReadyAt = now + slot.Cooldown
	end
end

-- Spends up to `n` banked charges; the last one starts the cooldown. Returns how many were spent.
function Pure.spend(slot: Slot, n: number, cooldown: number, now: number, day: number, morning: number?): number
	local used = math.clamp(math.floor(n), 0, slot.Charges)
	if used <= 0 then
		return 0
	end
	slot.Charges -= used
	slot.UsedAt = now
	if slot.Charges == 0 then
		Pure.startCooldown(slot, cooldown, now, day, morning)
	end
	return used
end

-- The ring: 1 when ready or banked; else how much of the cooldown has passed, below 1 until it really is ready.
function Pure.fraction(slot: Slot, now: number, day: number): number
	if slot.Charges > 0 or Pure.ready(slot, now, day) then
		return 1
	end
	if slot.Cooldown <= 0 then
		return 0.99
	end
	return math.clamp(1 - (slot.ReadyAt - now) / slot.Cooldown, 0, 0.99)
end

-- A fraction in `steps` steps (rounded down), so the ring is written a few times per cooldown, not every tick.
function Pure.quantize(fraction: number, steps: number): number
	return math.floor(math.clamp(fraction, 0, 1) * steps + 1e-9) / steps
end

-- OTHER abilities at the clinic cooling down (not ready and nothing banked).
function Pure.cooling(slots: { [string]: Slot }, except: string, now: number, day: number): number
	local n = 0
	for nurseId, slot in slots do
		if nurseId ~= except and slot.Charges == 0 and not Pure.ready(slot, now, day) then
			n += 1
		end
	end
	return n
end

-- An owner who left: drops every slot a fresh one would equal (ready now, nothing banked), so the memory a server
-- keeps per UserId stays bounded. A slot still cooling down, banked, or a once-a-day one used today stays, so a
-- rejoin can never recharge anything. Returns true when no slot is left (the whole clinic can go).
function Pure.prune(slots: { [string]: Slot }, now: number, day: number): boolean
	for nurseId, slot in slots do
		if slot.Charges == 0 and Pure.ready(slot, now, day) then
			slots[nurseId] = nil
		end
	end
	return next(slots) == nil
end

-- Team Spirit: every OTHER ability is ready now (never a once-a-day one: Miracle stays once a day).
function Pure.recharge(slots: { [string]: Slot }, except: string, now: number)
	for nurseId, slot in slots do
		if nurseId ~= except and not slot.Daily and slot.ReadyAt > now then
			slot.ReadyAt = now
		end
	end
end

-- `list` without one copy of each item in `take` (a multiset difference), order kept.
function Pure.without(list: { string }, take: { string }): { string }
	local counts: { [string]: number } = {}
	for _, item in take do
		counts[item] = (counts[item] or 0) + 1
	end
	local out: { string } = {}
	for _, item in list do
		local left = counts[item]
		if left and left > 0 then
			counts[item] = left - 1
		else
			table.insert(out, item)
		end
	end
	return out
end

-- What the bay patients still need that no hand or tray holds (front first).
function Pure.missing(needs: { string }, tray: { string }, carry: { string }): { string }
	return Pure.without(Pure.without(needs, tray), carry)
end

-- Every step the bay patients still need, front first, duplicates kept. `bays` = Nurses.bays (front first).
function Pure.needs(bays: { any }): { string }
	local out: { string } = {}
	for _, row in bays do
		if type(row) == "table" and type(row.Needs) == "table" then
			for _, item in row.Needs do
				if type(item) == "string" then
					table.insert(out, item)
				end
			end
		end
	end
	return out
end

-- Who 💫 Miracle finishes: every bay patient waiting for the doctor (never one in a mini-game), front first.
function Pure.targets(bays: { any }): { number }
	local out: { number } = {}
	for _, row in bays do
		if type(row) == "table" and row.NeedsDoctor == true and type(row.PatientId) == "number" then
			table.insert(out, row.PatientId)
		end
	end
	return out
end

local function fraction(value: any): number
	return if type(value) == "number" and value == value then math.clamp(value, 0, 1) else 1
end

-- The usefulness view (Logic/Abilities.useful) from what the plot shows. `bays` = Nurses.bays (the bay patients,
-- front first: { PatientId, Needs, NeedsDoctor, Patience }); `seats` = the patience (0..1) of every patient waiting
-- in the waiting room; `isSupply(itemId)` says what a tray can hold.
function Pure.view(
	bays: { any },
	seats: { any },
	tray: { string },
	carry: { string },
	trayMax: number,
	nearStation: boolean,
	onCooldown: number,
	isSupply: (string) -> boolean
): any
	local front: any = nil
	local low, waiting = 0, 0
	for _, row in bays do
		if type(row) == "table" and row.NeedsDoctor == true then
			waiting += 1
			front = front or row
			if fraction(row.Patience) < Pure.LOW then
				low += 1
			end
		end
	end
	for _, patience in seats do
		if fraction(patience) < Pure.LOW then
			low += 1
		end
	end
	local missing = Pure.missing(Pure.needs(bays), tray, carry)
	local supplies = 0
	for _, item in missing do
		if isSupply(item) then
			supplies += 1
		end
	end
	return {
		FrontPatience = if front then fraction(front.Patience) else nil,
		LowCount = low,
		Waiting = waiting,
		Missing = #missing,
		Supplies = supplies,
		TrayRoom = math.max(0, trayMax - #tray),
		NearStation = nearStation,
		OnCooldown = onCooldown,
	}
end

-- Fresh Supplies's items: the missing SUPPLIES (front first; a medicine is the player's to dispense), at most `count` and
-- the tray's free places.
function Pure.brew(
	needs: { string },
	tray: { string },
	carry: { string },
	count: number,
	room: number,
	isSupply: (string) -> boolean
): { string }
	local out: { string } = {}
	local limit = math.min(math.max(0, math.floor(count)), math.max(0, math.floor(room)))
	for _, item in Pure.missing(needs, tray, carry) do
		if #out >= limit then
			break
		end
		if isSupply(item) then
			table.insert(out, item)
		end
	end
	return out
end

-- A station rush: the same factor running longer keeps the later end.
function Pure.addRush(rushes: { Rush }, factor: number, untilAt: number)
	for _, rush in rushes do
		if rush.Factor == factor then
			rush.Until = math.max(rush.Until, untilAt)
			return
		end
	end
	table.insert(rushes, { Factor = factor, Until = untilAt })
end

-- The rush now: the strongest (smallest) factor still running and its end; 1 and 0 when none. Drops ended ones.
function Pure.rush(rushes: { Rush }, now: number): (number, number)
	local factor, untilAt = 1, 0
	for index = #rushes, 1, -1 do
		local rush = rushes[index]
		if rush.Until <= now then
			table.remove(rushes, index)
		elseif rush.Factor < factor or (rush.Factor == factor and rush.Until > untilAt) then
			factor, untilAt = rush.Factor, rush.Until
		end
	end
	return factor, untilAt
end

-- When the next in-game morning comes (server time): the end of this night, or the end of this day plus a night.
function Pure.nextMorning(isNight: any, phaseEndsAt: any, nightSeconds: number): number?
	if type(phaseEndsAt) ~= "number" or phaseEndsAt ~= phaseEndsAt then
		return nil
	end
	return if isNight == true then phaseEndsAt else phaseEndsAt + nightSeconds
end

-- A list of game ids a client-facing session could have (strings, at most `max`), or nil for junk.
function Pure.games(games: any, max: number): { string }?
	if type(games) ~= "table" or #games > max then
		return nil
	end
	local out: { string } = {}
	for index, gameId in ipairs(games) do
		if type(gameId) ~= "string" then
			return nil
		end
		out[index] = gameId
	end
	return out
end
-- PURE-END

Abilities.Pure = Pure

------------------------------------------------------------------------------------------------------------------
-- State (by the owner's UserId, for this server's life)
------------------------------------------------------------------------------------------------------------------

type Clinic = {
	Slots: { [string]: Slot },
	Rush: { Rush },
	PausedUntil: number,
	Shown: { [string]: number }, -- the ring step last written per nurse
	Models: { [string]: Model }, -- the model it was written on (a rebuilt nurse gets everything again)
}

local clinics: { [number]: Clinic } = {}
local day = 0 -- in-game days since this server started (Miracle)
local failures: { [string]: number } = {}

local function report(label: string, err: any)
	local count = (failures[label] or 0) + 1
	failures[label] = count
	if count <= 3 then
		warn("[Abilities] " .. label .. " failed: " .. tostring(err))
	end
end

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function setAttribute(instance: Instance, name: string, value: any)
	if instance:GetAttribute(name) ~= value then
		instance:SetAttribute(name, value)
	end
end

local function clinicOf(owner: Player): Clinic
	local clinic = clinics[owner.UserId]
	if not clinic then
		clinic = { Slots = {}, Rush = {}, PausedUntil = 0, Shown = {}, Models = {} }
		clinics[owner.UserId] = clinic
	end
	return clinic
end

-- The plot a caller means (the Plots table, or leniently its Model) and its owner while they're in the server.
local function resolve(value: any): (Plot?, Player?)
	local plot: Plot? = nil
	if type(value) == "table" and typeof(value.Model) == "Instance" then
		plot = value
	elseif typeof(value) == "Instance" then
		plot = Plots.fromInstance(value)
	end
	local owner = if plot then plot.Owner else nil
	if not owner or owner.Parent ~= Players then
		return plot, nil
	end
	return plot, owner
end

local function tutorialDone(data: any): boolean
	return type(data) == "table" and type(data.Tutorial) == "number" and data.Tutorial >= TutorialLogic.DONE
end

local function secondWindOf(data: any): boolean
	local ok, effects = pcall(RebirthLogic.effects, data, Config, PerksData, TreeData)
	return ok and type(effects) == "table" and type(effects.Recharge) == "number" and effects.Recharge < 1
end

local function morning(): number?
	return Pure.nextMorning(
		Workspace:GetAttribute("IsNight"),
		Workspace:GetAttribute("PhaseEndsAt"),
		Config.NightSeconds
	)
end

-- This nurse's ability at its level now (nil: unknown nurse or ability).
local function strengthOf(nurseId: string, data: any, secondWind: boolean): AbilitiesLogic.Strength?
	local nurse = rawget(NursesData :: any, nurseId)
	if type(nurse) ~= "table" then
		return nil
	end
	local entry = if type(data) == "table" and type(data.Nurses) == "table" then data.Nurses[nurseId] else nil
	local level = if type(entry) == "table" and type(entry.Level) == "number" then entry.Level else 1
	return AbilitiesLogic.strength(nurse.Ability, level, AbilitiesData, Config, secondWind)
end

-- The cooldown to start for a slot: its nurse's strength now, or (the nurse just left) the ability's base.
local function cooldownOf(slot: Slot, nurseId: string, data: any, secondWind: boolean): number
	local strength = strengthOf(nurseId, data, secondWind)
	if strength then
		return strength.Cooldown
	end
	local def = rawget(AbilitiesData :: any, slot.AbilityId)
	return if type(def) == "table" and type(def.Cooldown) == "number" then def.Cooldown else 60
end

local function modelOf(plot: Plot, nurseId: string): Model?
	local folder = plot.Model:FindFirstChild("Nurses")
	local model = folder and folder:FindFirstChild("Nurse_" .. nurseId)
	return if model and model:IsA("Model") then model else nil
end

local function sortedIds(map: { [string]: any }): { string }
	local ids: { string } = {}
	for id in map do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

------------------------------------------------------------------------------------------------------------------
-- Showing it (attributes on the nurse, the ring)
------------------------------------------------------------------------------------------------------------------

local function show(plot: Plot, clinic: Clinic, nurseId: string, slot: Slot, at: number)
	local model = modelOf(plot, nurseId)
	if not model then
		return
	end
	setAttribute(model, "AbilityReadyAt", slot.ReadyAt)
	setAttribute(model, "AbilityCooldown", slot.Cooldown)
	setAttribute(model, "AbilityCharges", slot.Charges)
	if slot.UsedAt > 0 then
		setAttribute(model, "AbilityAt", slot.UsedAt)
	end
	local step = Pure.quantize(Pure.fraction(slot, at, day), RING_STEPS)
	if clinic.Shown[nurseId] ~= step or clinic.Models[nurseId] ~= model then
		clinic.Shown[nurseId] = step
		clinic.Models[nurseId] = model
		local ok, err = pcall(NurseBuilder.setAbility, model, step)
		if not ok then
			report("NurseBuilder.setAbility", err)
		end
	end
end

local function showPlot(plot: Plot, clinic: Clinic, at: number)
	local factor, untilAt = Pure.rush(clinic.Rush, at)
	setAttribute(plot.Model, "MakeRushFactor", factor)
	setAttribute(plot.Model, "MakeRushUntil", untilAt)
	setAttribute(plot.Model, "PatiencePausedUntil", clinic.PausedUntil)
end

------------------------------------------------------------------------------------------------------------------
-- What the plot looks like right now (for Logic/Abilities.useful)
------------------------------------------------------------------------------------------------------------------

-- The patience (0..1) of every patient waiting in the waiting room (State "Waiting", Server/Patients).
local function seatsOf(plot: Plot): { any }
	local folder = plot.Model:FindFirstChild("Patients")
	local list: { any } = {}
	if folder then
		for _, child in folder:GetChildren() do
			if child:GetAttribute("State") == "Waiting" then
				table.insert(list, child:GetAttribute("PatienceFraction"))
			end
		end
	end
	return list
end

-- The bay patients, front first (Nurses.bays: Patients.bayView with each one's patience).
local function baysOf(plot: Plot): { Row }
	local ok, rows = pcall(Nurses.bays, plot)
	if not ok then
		report("Nurses.bays", rows)
		return {}
	end
	return if type(rows) == "table" then rows else {}
end

-- A tray may hold it: a supply (Data/Items Kind "Supply"), never a medicine (the player dispenses those).
local function isSupply(itemId: string): boolean
	return Nurses.Pure.isSupply(ItemsData, itemId)
end

local function trayOf(plot: Plot): { string }
	local ok, tray = pcall(Nurses.trayItems, plot)
	return if ok and type(tray) == "table" then tray else {}
end

local function carryOf(owner: Player): { string }
	return RecipeLogic.split(owner:GetAttribute("Carry"))
end

-- Every station id an item comes from (the supply stations and the dispensary), each once.
local STATION_IDS: { string } = {}
for _, itemId in ItemsData.Order do
	local item = rawget(ItemsData :: any, itemId)
	if type(item) == "table" and type(item.Station) == "string" and not table.find(STATION_IDS, item.Station) then
		table.insert(STATION_IDS, item.Station)
	end
end

-- The owner stands within NEAR_STATION studs of one of this plot's OPEN stations (Station_<id> under the Building or
-- the Rooms whose Open isn't false: the supply shelf, the Cast Table, the dispensary, the bought rooms').
local function nearStation(plot: Plot, owner: Player): boolean
	local character = owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	for _, name in { "Building", "Rooms" } do
		local holder = plot.Model:FindFirstChild(name)
		if holder then
			for _, stationId in STATION_IDS do
				local station = holder:FindFirstChild("Station_" .. stationId, true)
				local part = if station and station:IsA("Model")
					then station.PrimaryPart or station:FindFirstChildWhichIsA("BasePart", true)
					else station
				if
					station
					and part
					and part:IsA("BasePart")
					and station:GetAttribute("Open") ~= false
					and (part.Position - root.Position).Magnitude <= NEAR_STATION
				then
					return true
				end
			end
		end
	end
	return false
end

local patientsModule: any = nil

-- Server/Patients, once it can be had. Patients requires this module (Patients -> Treatment -> Abilities), so it is
-- required only here, at fire time, never while either module loads.
local function patientsApi(): any
	if patientsModule == nil then
		local ok, module = pcall(function(): any
			local holder = script.Parent:FindFirstChild("Patients")
			return if holder and holder:IsA("ModuleScript") then require(holder :: any) else nil
		end)
		if ok and type(module) == "table" then
			patientsModule = module
		end
	end
	return patientsModule
end

-- 💫 Miracle: every bay patient waiting for the doctor has its whole visit finished (Patients.finishVisit, the owner
-- as helper), medicine steps included. Returns how many.
local function finishVisits(plot: Plot, owner: Player): number
	local api = patientsApi()
	if not api or type(api.finishVisit) ~= "function" then
		report("Patients.finishVisit", "not there")
		return 0
	end
	local done = 0
	for _, patientId in Pure.targets(baysOf(plot)) do
		local ok, err = pcall(api.finishVisit, plot.Model, patientId, owner)
		if ok then
			done += 1
		else
			report("Patients.finishVisit", err)
		end
	end
	return done
end

------------------------------------------------------------------------------------------------------------------
-- Firing
------------------------------------------------------------------------------------------------------------------

local function fire(plot: Plot, owner: Player, clinic: Clinic, nurseId: string, slot: Slot, strength: any, at: number)
	Pure.startCooldown(slot, strength.Cooldown, at, day, morning())
	local kind: string = strength.Kind
	local value: number = strength.Value
	local seconds: number = strength.Seconds or value
	if kind == "TrayItem" then
		local tray = trayOf(plot)
		local needs = Pure.needs(baysOf(plot))
		local items = Pure.brew(needs, tray, carryOf(owner), value, Config.Nurses.TrayMax - #tray, isSupply)
		for _, itemId in items do
			local ok, err = pcall(Nurses.addToTray, plot, itemId)
			if not ok then
				report("Nurses.addToTray", err)
			end
		end
	elseif kind == "FastMake" then
		Pure.addRush(clinic.Rush, FAST_MAKE, at + seconds)
	elseif kind == "InstantMake" then
		Pure.addRush(clinic.Rush, INSTANT_MAKE, at + seconds)
	elseif kind == "PauseLine" then
		clinic.PausedUntil = math.max(clinic.PausedUntil, at + seconds)
	elseif kind == "Recharge" then
		Pure.recharge(clinic.Slots, nurseId, at)
	elseif kind == "CureLine" then
		value = finishVisits(plot, owner) -- before Fired: a listener finds those visits already finished
	end
	showPlot(plot, clinic, at)
	Abilities.Fired:Fire(plot, nurseId, slot.AbilityId, kind, value)
end

local function tick(plot: Plot)
	local _, owner = resolve(plot)
	if not owner then
		return
	end
	local data = PlayerData.get(owner)
	if not data or not tutorialDone(data) then
		return
	end
	local clinic = clinicOf(owner)
	local at = now()
	local ids = Nurses.working(owner)
	local keep: { [string]: boolean } = {}
	for _, nurseId in ids do
		keep[nurseId] = true
	end
	for nurseId in table.clone(clinic.Slots) do
		if not keep[nurseId] then
			clinic.Slots[nurseId] = nil -- sold, resting or gone: a nurse that comes back starts ready
			clinic.Shown[nurseId] = nil
			clinic.Models[nurseId] = nil
		end
	end
	local secondWind = secondWindOf(data)
	local base: any = nil -- the plot's view, built once per tick (again after a fire changes the plot)
	for _, nurseId in ids do
		local strength = strengthOf(nurseId, data, secondWind)
		if strength then
			local nurse = rawget(NursesData :: any, nurseId)
			local slot = clinic.Slots[nurseId]
			if not slot or slot.AbilityId ~= nurse.Ability then
				slot = Pure.newSlot(nurse.Ability, strength.Kind, strength.Daily, strength.Cooldown, at)
				clinic.Slots[nurseId] = slot
			end
			if slot.Charges == 0 and Pure.ready(slot, at, day) then
				if AbilitiesLogic.BANKED[strength.Kind] then
					slot.Charges = Pure.charges(strength.Kind, strength.Value)
				else
					if not base then
						base = Pure.view(
							baysOf(plot),
							seatsOf(plot),
							trayOf(plot),
							carryOf(owner),
							Config.Nurses.TrayMax,
							false,
							0,
							isSupply
						)
					end
					local view = table.clone(base)
					view.OnCooldown = Pure.cooling(clinic.Slots, nurseId, at, day)
					if strength.Kind == "InstantMake" then
						view.NearStation = nearStation(plot, owner)
					end
					if AbilitiesLogic.useful(strength.Kind, view) then
						fire(plot, owner, clinic, nurseId, slot, strength, at)
						base = nil
					end
				end
			end
			show(plot, clinic, nurseId, slot, at)
		end
	end
	showPlot(plot, clinic, at)
end

------------------------------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------------------------------

function Abilities.consumePerfects(plotArg: any, games: { string }): { boolean }
	local flags: { boolean } = {}
	local list = Pure.games(games, MAX_GAMES)
	if not list then
		return flags
	end
	for index in list do
		flags[index] = false
	end
	local plot, owner = resolve(plotArg)
	local data = if owner then PlayerData.get(owner) else nil
	local clinic = if owner then clinics[owner.UserId] else nil
	if not plot or not owner or not clinic or not tutorialDone(data) then
		return flags
	end
	local charges: { AbilitiesLogic.Charge } = {}
	local who: { string } = {}
	for _, nurseId in sortedIds(clinic.Slots) do
		local slot = clinic.Slots[nurseId]
		if slot.Kind == "AutoPerfect" and slot.Charges > 0 then
			local def = rawget(AbilitiesData :: any, slot.AbilityId)
			local gameId = if type(def) == "table" and type(def.Game) == "string" then def.Game else nil
			table.insert(charges, { Game = gameId, Count = slot.Charges })
			table.insert(who, nurseId)
		end
	end
	if #charges == 0 then
		return flags
	end
	local out, left = AbilitiesLogic.autoGames(list, charges)
	local at = now()
	local secondWind = secondWindOf(data)
	for index, nurseId in who do
		local slot = clinic.Slots[nurseId]
		local remaining = if type(left[index]) == "table" then left[index].Count else slot.Charges
		local used =
			Pure.spend(slot, slot.Charges - remaining, cooldownOf(slot, nurseId, data, secondWind), at, day, morning())
		if used > 0 then
			show(plot, clinic, nurseId, slot, at)
			Abilities.Fired:Fire(plot, nurseId, slot.AbilityId, "AutoPerfect", used)
		end
	end
	return out
end

function Abilities.consumeCure(plotArg: any): { Cash: number, Stars: number }
	local result = { Cash = 1, Stars = 0 }
	local plot, owner = resolve(plotArg)
	local data = if owner then PlayerData.get(owner) else nil
	local clinic = if owner then clinics[owner.UserId] else nil
	if not plot or not owner or not clinic or not tutorialDone(data) then
		return result
	end
	local at = now()
	local secondWind = secondWindOf(data)
	local doubled = false
	for _, nurseId in sortedIds(clinic.Slots) do
		local slot = clinic.Slots[nurseId]
		local spent = 0
		if slot.Kind == "CashNext" and slot.Charges > 0 and not doubled then
			spent = Pure.spend(slot, 1, cooldownOf(slot, nurseId, data, secondWind), at, day, morning())
			if spent > 0 then
				doubled = true
				result.Cash = CASH_NEXT
			end
		elseif slot.Kind == "StarsNext" and slot.Charges > 0 then
			local strength = strengthOf(nurseId, data, secondWind)
			spent = Pure.spend(slot, 1, cooldownOf(slot, nurseId, data, secondWind), at, day, morning())
			if spent > 0 and strength then
				result.Stars += math.max(0, math.floor(strength.Value))
			end
		end
		if spent > 0 then
			show(plot, clinic, nurseId, slot, at)
			Abilities.Fired:Fire(plot, nurseId, slot.AbilityId, slot.Kind, spent)
		end
	end
	return result
end

function Abilities.patiencePaused(plotArg: any): boolean
	local _, owner = resolve(plotArg)
	local clinic = if owner then clinics[owner.UserId] else nil
	return clinic ~= nil and clinic.PausedUntil > now()
end

function Abilities.makeFactor(plotArg: any): number
	local _, owner = resolve(plotArg)
	local clinic = if owner then clinics[owner.UserId] else nil
	if not clinic then
		return 1
	end
	local factor = Pure.rush(clinic.Rush, now())
	return factor
end

function Abilities.adminCharge(player: Player): (boolean, string)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, Remotes.OOPS
	end
	local plot = Plots.getPlot(player)
	if not plot then
		return false, "No clinic yet!"
	end
	local clinic = clinicOf(player)
	local at = now()
	for nurseId, slot in clinic.Slots do
		slot.ReadyAt = math.min(slot.ReadyAt, at)
		slot.Day = -1
		show(plot, clinic, nurseId, slot, at)
	end
	return true, "✨ Abilities ready!"
end

------------------------------------------------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------------------------------------------------

local function resetPlot(plot: Plot)
	setAttribute(plot.Model, "MakeRushFactor", 1)
	setAttribute(plot.Model, "MakeRushUntil", 0)
	setAttribute(plot.Model, "PatiencePausedUntil", 0)
end

function Abilities.start()
	for _, plot in Plots.all() do
		resetPlot(plot)
	end
	-- The plot's running effects end with it (its nurses are gone); the cooldowns stay with the owner's UserId, but
	-- only the ones still running (Pure.prune), so a long-running server's memory stays bounded.
	Plots.PlotReleased:Connect(function(owner: Player, plot: Plot)
		local userId = if typeof(owner) == "Instance" then owner.UserId else nil
		local clinic = if userId then clinics[userId] else nil
		if clinic and userId then
			clinic.Rush = {}
			clinic.PausedUntil = 0
			clinic.Shown = {}
			clinic.Models = {}
			if Pure.prune(clinic.Slots, now(), day) then
				clinics[userId] = nil
			end
		end
		resetPlot(plot)
	end)

	-- Owners who left: their cooldowns run out by themselves; drop each slot once it equals a fresh one, and the
	-- clinic once nothing is left (a rejoin before then still finds every cooldown where it was).
	local function pruneAway()
		local here: { [number]: boolean } = {}
		for _, plot in Plots.all() do
			local owner = plot.Owner
			if owner then
				here[owner.UserId] = true
			end
		end
		local at = now()
		for userId, clinic in clinics do
			if not here[userId] and Pure.prune(clinic.Slots, at, day) then
				clinics[userId] = nil
			end
		end
	end

	-- Miracle: a new in-game day starts each morning (IsNight true -> false).
	local wasNight = Workspace:GetAttribute("IsNight") == true
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(function()
		local isNight = Workspace:GetAttribute("IsNight") == true
		if wasNight and not isNight then
			day += 1
			local at = now()
			for _, clinic in clinics do
				for _, slot in clinic.Slots do
					if slot.Daily and slot.Day ~= day and slot.ReadyAt > at then
						slot.ReadyAt = at
					end
				end
			end
		end
		wasNight = isNight
	end)

	task.spawn(function()
		local lastPrune = os.clock()
		while true do
			task.wait(TICK)
			for _, plot in Plots.all() do
				local ok, err = pcall(tick, plot)
				if not ok then
					report("a tick", err)
				end
			end
			if os.clock() - lastPrune >= PRUNE_SECONDS then
				lastPrune = os.clock()
				local ok, err = pcall(pruneAway)
				if not ok then
					report("the prune", err)
				end
			end
		end
	end)
end

return Abilities
