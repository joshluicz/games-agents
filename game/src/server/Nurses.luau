--!strict
-- Nurses you own: the roster's workers on your plot, their jobs, specialties, XP and team bonuses, the nurse tray, the
-- Nurse Journal, and THE only door a nurse enters or leaves a save by (grant / take / give). Depth-update design §2
-- and §7; Progression v2 build plan §B3/§B4/§B8 (memory-20261116-012/-013/-017/-019). Server only. OWNER: T1.
--
--   Nurses.start()                              wires SetJob; spawns the working nurses on PlotAssigned and follows
--                                               every save change (a hire, a level, a job, a sale, a rebirth);
--                                               removes them on PlotReleased (before Plots clears the plot)
--   Nurses.rosterCap(p): number                 Logic/Nurse.rosterCap(the save's Rebirth.Count): 3, +1 a rebirth, max 8
--   Nurses.working(p): { NurseId }              Logic/Nurse.working: the nurses that work (not "Rest", known, by
--                                               NurseId, at most the roster cap). Every one of them works on the plot
--   Nurses.setJob(p, nurseId, job): (ok, message)
--                                               the SetJob remote's rules (§B3, Logic/Nurse.setJob): owned, a Data/Jobs
--                                               id (never "Rest"), open at your hospital level ("🏥 Lv 2 first!"), a
--                                               resting nurse only while fewer than the roster cap work. Saves Job ("" =
--                                               its Role) in ONE update; NurseNews Job (and Resting On = false)
--   THE one place a nurse joins or leaves a save (each in ONE PlayerData.update, no yield between check and change):
--   Nurses.grant(p, nurseId, price, source?): (ok, message)
--                                               source "Belt" (default) | "Agency" | "Gift" | "Admin". canAdd (roster
--                                               room, or the level cap for a copy), the charge, Logic/Nurse.hire (new,
--                                               or +1 level), NurseIndex "Hired", any journal set due and, for a Gift,
--                                               its Rebirth.Pending removal. Then NurseNews Hired, Celebrate NewNurse /
--                                               NurseLevel (a copy reaching Lv 5 or 10) / JournalSet, the Hired (and
--                                               LevelUp) signals. A rebirth-only nurse (Source) only comes as a Gift or
--                                               from an Admin
--   Nurses.take(p, nurseId, cash, reason): (ok, message, entry?)
--                                               reason "Sold" (the Agency) | "Market". The entry leaves and the cash
--                                               comes in. Refuses a listed nurse unless reason == "Market" (which also
--                                               clears the listed lock) and a rebirth-only one. Then NurseNews Sold /
--                                               Gone, the Removed signal, and the worker poofs off the plot. `entry` is a
--                                               copy of what left (the Market gives it to the buyer)
--   Nurses.give(p, nurseId, entry, price): (ok, message)
--                                               the Market's buyer side and its undo: the charge and the seller's exact
--                                               Level / XP / Copies (Job ""), "Hired" and any set due. Refuses a nurse you
--                                               own ("You have one!"), a full roster, a level above your cap ("🏢 R3
--                                               first!") and a rebirth-only one. Then NurseNews Bought, Celebrate
--                                               NewNurse, the Hired signal. Giving a nurse back to the player it was
--                                               taken from with reason "Market" in the same frame (the Market's undo,
--                                               §B3.2 step 12) restores the exact entry, Job included, with no roster
--                                               check (nothing is ever lost) and no news
--   Nurses.setListed(p, nurseId, listingId?) · Nurses.isListed(p, nurseId): boolean
--                                               the Market's in-memory lock (nil clears it; NurseNews Listed On/Off).
--                                               Cleared on PlayerRemoving
--   Nurses.onCure(owner, info: { Wing?, Urgent?, Dept? })
--                                               +XP for every working nurse (Config.NurseXP: PerCure, +Specialty when
--                                               the cure was in its department, x Fast Learners), in ONE update. Each
--                                               level-up: NurseNews Level and the LevelUp signal; reaching Lv 5 or 10
--                                               (an ability upgrade): Celebrate NurseLevel
--   Nurses.team(plot): TeamEffects              the team bonuses (Logic/Jobs.teamEffects over the working nurses'
--                                               specialties); plot attributes TeamBonus ("Reception:2,Hydro:3"),
--                                               TeamCash, TeamRecover, TeamUrgent, TeamMake ("Bath=0.8,Cocoa=0.8")
--   Nurses.reception(plot): { Arrive, Triage }  the best Receptionist's arrival factor (1 = none) and whether one is on
--                                               duty (routing is instant); plot attributes Reception, Triage
--   Nurses.medic(plot): { Patience }            how much slower 🚑/🚁 patients drain (the best Medic; 1 = none); plot
--                                               attribute MedicPatience
--   Nurses.cheer(plot): Types.Cheer             the best working Cheerer's multipliers ({ 1, 1 } when none); plot
--                                               attributes CheerPatience and CheerTip
--   Porters (Patients drives the patient; Nurses drives the porter):
--   Nurses.claimPorter(plot): NurseId?          a free Porter (at home, rested): it stands still for you until released
--   Nurses.escort(plot, nurseId, to: CFrame): boolean   yields while the claimed porter hops to `to` on its floor
--                                               (Lift.carry moves it between floors); false if it isn't a claimed porter
--                                               any more (sold, re-jobbed, the owner left)
--   Nurses.releasePorter(plot, nurseId)         it rests Every seconds (Logic/Nurse.stats Porter), rides the lift down
--                                               if it is upstairs and goes home. A claim left for 60 s is let go
--   Nurses.addToTray(plot, itemId): boolean     one item into the nurse tray (Abilities: Fresh Brew), the Maker rules
--   Nurses.trayItems(plot) · Nurses.takeFromTray(plot, itemId) · Nurses.markSeen(nurseId, players?) ·
--   Nurses.healed(plot, nurseId, items)         as v3 (healed: a Healer's or a Medic's delivery landed)
--   Nurses.adminLevels(p) (+1 level each, to the cap) · Nurses.adminGive(p, nurseId) (= grant, price 0, "Admin")
--   Signals: Nurses.Heal (plot, nurseId, target: "Front" | "Urgent") · Nurses.Hired (p, nurseId, level) ·
--            Nurses.LevelUp (p, nurseId, level) · Nurses.Removed (p, nurseId)
--   Nurses.Pure                                 the pure helpers below (tests/NurseServer.spec, tests/NurseWork.spec)
--
-- The workers (plot.Model.Nurses.Nurse_<NurseId>, from NurseBuilder; tag CreatureMotion; attributes NurseId, Role (its
-- Data Role), Job (the job it works now: Logic/Jobs.effective), Specialty, Ability, Rarity, Level, Task, Station;
-- Server/Abilities adds AbilityReadyAt, AbilityCooldown, AbilityAt). Resting nurses get no model. They hop by the
-- creature-motion contract (NurseBuilder.hop): the server sets the hop attributes and writes Root.CFrame once per
-- landing, never every frame. One thread per nurse. A job worked in the nurse's own department (its Specialty, or
-- "Any") is +40% (Config.Nurses.SpecialtyBoost); Double Shift (the tree) makes every job's seconds / 1.25.
--   Maker        makes what the line still needs (QueueNeeds, front first), minus what's already in the tray, being
--                made by another Maker or carried by the owner, and only what this plot's stations make (never a
--                medicine): it hops to that station, works for its Every seconds, and puts the item in the tray
--   Healer       stands behind the Counter; at most every Every seconds, when the tray holds an item the front patient
--                still needs (FrontNeeds), fires Heal (target "Front")
--   Cheerer      stands beside the line and cheers while patients wait (CheerPatience, CheerTip: the best one)
--   Receptionist stands at the Counter's other side and greets the line ("Greeting"): patients come sooner and, from
--                Lv 3, go straight to the right floor (Reception, Triage)
--   Medic        waits at the ambulance bay; while a 🚑/🚁 patient waits in line it goes to it ("Treating") and fires
--                Heal (target "Urgent") when the tray holds what it needs (MedicPatience: they wait longer)
--   Porter       idles by the ground landing until Patients claims it to ride a patient upstairs ("Escorting")
-- Nurses work only while the owner is in the server (their plot is released when they leave): no offline income.
-- Never requires Treatment, Patients, Abilities, Agency, Market or Rebirth (some of them require this): it reads the
-- plot's FrontNeeds / QueueNeeds and the patients' attributes. It requires Lift (porters ride).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)
local JobsLogic = require(Shared.Logic.Jobs)
local NurseLogic = require(Shared.Logic.Nurse)
local RebirthLogic = require(Shared.Logic.Rebirth)
local RecipeLogic = require(Shared.Logic.Recipe)
local DecorData = require(Shared.Data.Decor)
local DeptData = require(Shared.Data.Departments)
local ItemsData = require(Shared.Data.Items)
local JobsData = require(Shared.Data.Jobs)
local NursesData = require(Shared.Data.Nurses)
local PerksData = require(Shared.Data.Perks)
local Rarities = require(Shared.Data.Rarities)
local TreeData = require(Shared.Data.Tree)
local Book = require(script.Parent.Book)
local CreatureBuilder = require(script.Parent.CreatureBuilder)
local Levels = require(script.Parent.Levels)
local Lift = require(script.Parent.Lift)
local NurseBuilder = require(script.Parent.NurseBuilder)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)

type Plot = Types.Plot
type Entry = Types.NurseEntry

local Nurses = {}

Nurses.Heal = Signal.new()
Nurses.Hired = Signal.new()
Nurses.LevelUp = Signal.new()
Nurses.Removed = Signal.new()

------------------------------------------------------------------------------------------------------------------
-- Tuning (feel only; the rules' numbers are in Config.Nurses, Config.NurseXP and Config.Roster)
------------------------------------------------------------------------------------------------------------------

local MOTION_TAG = "CreatureMotion"
local FOLDER_NAME = "Nurses"
local TRAY_ATTRIBUTE = "NurseTray"
local TRAY_GUI = "NurseTrayGui"
local HOP_LENGTH = 3
local HOP_SECONDS = 0.32
local HOP_HEIGHT = 0.8
local SPOT_SPACING = 2.6 -- studs between nurses of the same job standing side by side
local LOOK_SECONDS = 0.5 -- an idle nurse looks for work this often
local HEAL_WAIT = 2 -- seconds a Healer or Medic waits for the delivery before it tries again
local RETRY_SECONDS = 2
local CLAIM_MAX = 60 -- seconds a porter stays claimed before it lets go by itself (a lost release)
local UPSTAIRS = 4 -- studs above the ground: a porter this high is on an upper floor
local SET_JOB_COOLDOWN = 0.35 -- seconds per player (§B3)
local MAX_CASH = 1e15 -- as Economy: far below 2^53
local NEAR_STUDS = 16 -- the tray billboard stops growing on screen closer than this
local TAKE_REASONS: { [string]: boolean } = { Sold = true, Market = true }
local SOURCES: { [string]: boolean } = { Belt = true, Agency = true, Gift = true, Admin = true }

local rng = Random.new()

------------------------------------------------------------------------------------------------------------------
-- Pure helpers (no Roblox services; the only upvalue is NurseLogic, which the specs inject: a Lune harness loads
-- this block on its own)
------------------------------------------------------------------------------------------------------------------

-- PURE-BEGIN
local Pure = {}

Pure.REST = "Rest"

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

-- The index of the oldest tray item the line doesn't need (copies beyond what the line needs count), or nil.
function Pure.spare(tray: { string }, needs: { string }): number?
	local counts: { [string]: number } = {}
	for _, item in needs do
		counts[item] = (counts[item] or 0) + 1
	end
	for index, item in tray do
		local left = counts[item]
		if left and left > 0 then
			counts[item] = left - 1
		else
			return index
		end
	end
	return nil
end

-- One more item in the tray: added while there's room; a full tray swaps out the oldest item nobody needs. A tray full
-- of needed items refuses. Returns (a new tray, added).
function Pure.trayAdd(tray: { string }, item: string, max: number, needs: { string }): ({ string }, boolean)
	local out = table.clone(tray)
	if #out < max then
		table.insert(out, item)
		return out, true
	end
	local index = Pure.spare(out, needs)
	if index then
		table.remove(out, index)
		table.insert(out, item)
		return out, true
	end
	return out, false
end

-- One `item` out of the tray (the oldest copy). Returns (a new tray, taken).
function Pure.trayTake(tray: { string }, item: string): ({ string }, boolean)
	local out = table.clone(tray)
	local index = table.find(out, item)
	if not index then
		return out, false
	end
	table.remove(out, index)
	return out, true
end

-- What a Maker makes next: the first item the line needs (front first) that `have` doesn't already cover (the tray,
-- what other Makers are making, what the owner carries) and that `canMake` has. nil when nothing is missing, or when
-- the tray is full of items the line needs.
function Pure.pickMake(
	needs: { string },
	have: { string },
	canMake: { [string]: boolean },
	tray: { string },
	max: number
): string?
	if #tray >= max and Pure.spare(tray, needs) == nil then
		return nil
	end
	for _, item in Pure.without(needs, have) do
		if canMake[item] then
			return item
		end
	end
	return nil
end

-- A Healer (or a Medic) can help: the tray holds something the patient still needs.
function Pure.canHeal(frontNeeds: { string }, tray: { string }): boolean
	for _, item in frontNeeds do
		if table.find(tray, item) then
			return true
		end
	end
	return false
end

-- A nurse's level from its save entry (1..max; junk -> 1).
function Pure.level(entry: any, max: number): number
	local level = if type(entry) == "table" then entry.Level else nil
	if type(level) ~= "number" or level ~= level then
		return 1
	end
	return math.clamp(math.floor(level), 1, max)
end

-- 12345 -> "12,345"
function Pure.cash(n: number): string
	local text = tostring(math.floor(math.abs(n)))
	local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (if n < 0 then "-" else "") .. out
end

-- A whole, finite amount of cash >= 0 (rounded), or nil for junk.
function Pure.amount(value: any): number?
	if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
		return nil
	end
	return math.floor(value + 0.5)
end

-- A specialty counts in a department: its own, or "Any" (every department).
function Pure.matches(specialty: any, dept: any): boolean
	return type(dept) == "string" and dept ~= "" and (specialty == dept or specialty == "Any")
end

-- A job's seconds with Double Shift (the tree capstone: every nurse works `factor` x faster), never under `min`.
function Pure.shift(every: number, factor: any, min: number): number
	local f = if type(factor) == "number" and factor == factor and factor >= 1 and factor < math.huge then factor else 1
	return math.max(min, every / f)
end

-- XP one working nurse gets from one cure: PerCure, + Specialty when the cure was in one of `depts` (the patient's
-- department, where it recovered) for this nurse's specialty, x `factor` (Fast Learners). A whole number >= 0.
function Pure.cureXP(xp: any, specialty: any, depts: { any }, factor: any): number
	local s = if type(xp) == "table" then xp else {}
	local per = if type(s.PerCure) == "number" and s.PerCure == s.PerCure then s.PerCure else 1
	local bonus = if type(s.Specialty) == "number" and s.Specialty == s.Specialty then s.Specialty else 0
	local match = false
	for _, dept in depts do
		if Pure.matches(specialty, dept) then
			match = true
			break
		end
	end
	local f = if type(factor) == "number" and factor == factor and factor >= 1 and factor < math.huge then factor else 1
	return math.max(0, math.floor((per + (if match then bonus else 0)) * f + 1e-9))
end

-- Resting nurses to wake now (build plan §E2: a sale or a rebirth made room): known resting ids by NurseId, as many
-- as the roster cap has free working places. Every entry that isn't "Rest" holds a place (as Logic/Nurse.setJob
-- counts them); unknown ids never wake.
function Pure.toWake(nurses: any, cap: number, isKnown: (string) -> boolean): { string }
	local out: { string } = {}
	if type(nurses) ~= "table" then
		return out
	end
	local working = 0
	local resting: { string } = {}
	for nurseId, entry in nurses do
		if type(entry) == "table" then
			if entry.Job ~= Pure.REST then
				working += 1
			elseif type(nurseId) == "string" and isKnown(nurseId) then
				table.insert(resting, nurseId)
			end
		end
	end
	table.sort(resting)
	local room = math.max(0, math.floor(cap) - working)
	for index = 1, math.min(room, #resting) do
		out[index] = resting[index]
	end
	return out
end

-- The team chips: "Reception:2,Hydro:3", in department order, only teams of 2+ whose department has a bonus.
function Pure.teamLine(counts: { [string]: number }, departments: any): string
	local parts: { string } = {}
	local order = if type(departments) == "table" and type(departments.Order) == "table" then departments.Order else {}
	for _, id in order do
		local dept = rawget(departments, id)
		local n = counts[id] or 0
		if type(dept) == "table" and n >= 2 and (dept.Team2 ~= nil or dept.Team3 ~= nil) then
			table.insert(parts, id .. ":" .. math.floor(n))
		end
	end
	return table.concat(parts, ",")
end

-- The hold factors per station: "Bath=0.8,Cocoa=0.8" (sorted, at most 2 decimals), "" when none.
function Pure.makeLine(make: { [string]: number }): string
	local ids: { string } = {}
	for stationId, factor in make do
		if type(stationId) == "string" and type(factor) == "number" and factor ~= 1 then
			table.insert(ids, stationId)
		end
	end
	table.sort(ids)
	local parts: { string } = {}
	for _, stationId in ids do
		local rounded = math.floor(make[stationId] * 100 + 0.5) / 100
		table.insert(parts, stationId .. "=" .. tostring(rounded))
	end
	return table.concat(parts, ",")
end

-- Every item the waiting 🚑/🚁 patients still need, front first: `patients` = { { Urgent, State, Queue, Missing } }.
function Pure.urgentNeeds(patients: { any }): { string }
	local list: { any } = {}
	for _, p in patients do
		if
			type(p) == "table"
			and type(p.Urgent) == "string"
			and p.Urgent ~= ""
			and p.State == "Waiting"
			and type(p.Queue) == "number"
			and p.Queue >= 1
		then
			table.insert(list, p)
		end
	end
	table.sort(list, function(a, b)
		return a.Queue < b.Queue
	end)
	local out: { string } = {}
	for _, p in list do
		for _, item in (if type(p.Missing) == "table" then p.Missing else {}) do
			table.insert(out, item)
		end
	end
	return out
end

-- take's checks (§B8): you own it, it isn't rebirth-only, and it isn't listed unless the Market is the one taking it.
function Pure.canTake(
	nurses: any,
	nurseId: string,
	reason: string,
	onMarket: boolean,
	rebirthOnly: boolean
): (boolean, string)
	if type(nurses) ~= "table" or type(nurses[nurseId]) ~= "table" then
		return false, "Hire it first!"
	end
	if rebirthOnly then
		return false, "This one stays with you!"
	end
	if onMarket and reason ~= "Market" then
		return false, "Unlist it first"
	end
	return true, ""
end

-- The entry a give adds: the exact Level, XP and Copies (whole, sane: Level >= 1, 0 <= XP < xpToNext(Level), Copies
-- >= 1) and Job "" (it works its Role for the new owner), or its own Job when `keepJob` (the Market's undo).
function Pure.giveEntry(entry: any, keepJob: boolean): Entry
	local e = if type(entry) == "table" then entry else {}
	local function whole(value: any, fallback: number): number
		if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
			return fallback
		end
		return math.floor(value)
	end
	local level = math.max(1, whole(e.Level, 1))
	local xp = math.clamp(whole(e.XP, 0), 0, NurseLogic.xpToNext(level) - 1)
	local job = if keepJob and type(e.Job) == "string" then e.Job else ""
	return { Level = level, XP = xp, Copies = math.max(1, whole(e.Copies, 1)), Job = job }
end

-- give's checks (§B8, §B3.2 step 6): new to you ("You have one!"), not rebirth-only, roster room (skipped when
-- `restoring`: the Market's undo puts back what it took), a level your cap allows, and the cash for `price`.
function Pure.canGive(
	data: any,
	nurseId: string,
	entry: any,
	price: number,
	cfg: any,
	isKnown: (string) -> boolean,
	rebirthOnly: boolean,
	undo: boolean
): (boolean, string)
	if type(data) ~= "table" or type(entry) ~= "table" then
		return false, "Oops! Try again."
	end
	local nurses = if type(data.Nurses) == "table" then data.Nurses else {}
	if type(nurses[nurseId]) == "table" then
		return false, "You have one!"
	end
	if rebirthOnly then
		return false, "This one stays with you!"
	end
	local rebirths = 0
	if
		type(data.Rebirth) == "table"
		and type(data.Rebirth.Count) == "number"
		and data.Rebirth.Count == data.Rebirth.Count
	then
		rebirths = math.max(0, math.floor(data.Rebirth.Count))
	end
	if not undo and NurseLogic.owned(nurses, isKnown) >= NurseLogic.rosterCap(rebirths, cfg) then
		return false, "Roster full: sell or list one"
	end
	if Pure.giveEntry(entry, false).Level > NurseLogic.levelCap(rebirths, cfg) then
		local at = if type(cfg) == "table" and type(cfg.Nurses) == "table" then cfg.Nurses.LevelCapRebirths else nil
		return false, "🏢 R" .. tostring(if type(at) == "number" then at else 3) .. " first!"
	end
	if type(data.Cash) ~= "number" or data.Cash < price then
		return false, "Need 💰" .. Pure.cash(price)
	end
	return true, ""
end

-- Who levelled to what: the ability got stronger when the level crossed one of `upgradeLevels` (Lv 5, Lv 10).
function Pure.abilityUp(from: number, to: number, upgradeLevels: any): boolean
	if type(upgradeLevels) ~= "table" then
		return false
	end
	for _, at in upgradeLevels do
		if type(at) == "number" and from < at and to >= at then
			return true
		end
	end
	return false
end
-- PURE-END

Nurses.Pure = Pure

------------------------------------------------------------------------------------------------------------------
-- Types and state
------------------------------------------------------------------------------------------------------------------

type Worker = {
	NurseId: string,
	Role: string, -- its Data Role
	Job: string, -- the job it works now (Logic/Jobs.effective)
	Specialty: string,
	Rarity: string,
	Level: number,
	Model: Model,
	Pivot: CFrame, -- where it rests between hops (Root.CFrame)
	Index: number, -- its place among the nurses of its job on this plot (where it stands)
	Alive: boolean,
	Thread: thread?,
	Making: string?, -- a Maker's item in progress (other Makers don't make it too)
	Healed: boolean, -- a Healer's or Medic's delivery landed (Nurses.healed)
	-- Porters
	Claimed: boolean, -- Patients holds it (claimPorter .. releasePorter): its own loop stands still
	ClaimedAt: number,
	Busy: boolean, -- an escort walk is hopping it (on Patients' thread): its own loop waits
	Escort: number, -- the escort walk's token: a release or a newer escort stops the older walk
	Free: boolean, -- at home and still: claimable
	RestUntil: number, -- os.clock(): resting after a trip
	Retask: boolean, -- its job changed while claimed: change it on release
}

type Work = {
	Plot: Plot,
	Owner: Player,
	Folder: Folder,
	Ray: RaycastParams,
	Workers: { [string]: Worker },
	Shift: number, -- Double Shift: every job's seconds / this
	Cheer: Types.Cheer,
	Reception: { Arrive: number, Triage: boolean },
	Medic: { Patience: number },
	Team: Types.TeamEffects,
}

local works: { [Plot]: Work } = {}
local trayLabels: { [Plot]: TextLabel } = {}
local failures: { [string]: number } = {}
local listed: { [Player]: { [string]: number } } = {} -- the Market's lock: NurseId -> listing id
local restoring: { [Player]: { [string]: Entry } } = {} -- a Market take this frame: its undo puts this back
local lastSetJob: { [Player]: number } = {}
local wakeQueued: { [Player]: boolean } = {}

local function report(label: string, err: any)
	local count = (failures[label] or 0) + 1
	failures[label] = count
	if count <= 3 then
		warn("[Nurses] " .. label .. " failed: " .. tostring(err))
	end
end

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

-- rawget: Data maps answer `.Order` through their metatable, so a plain index would accept the id "Order".
local function nurseOf(nurseId: any): any
	if type(nurseId) ~= "string" then
		return nil
	end
	local nurse = rawget(NursesData :: any, nurseId)
	return if type(nurse) == "table" then nurse else nil
end

local function knownNurse(nurseId: string): boolean
	return nurseOf(nurseId) ~= nil
end

local function jobOf(jobId: any): any
	if type(jobId) ~= "string" then
		return nil
	end
	local job = rawget(JobsData :: any, jobId)
	return if type(job) == "table" then job else nil
end

local function knownDecor(decorId: any): boolean
	return type(decorId) == "string" and type(rawget(DecorData :: any, decorId)) == "table"
end

local function itemOf(itemId: any): any
	if type(itemId) ~= "string" then
		return nil
	end
	local item = rawget(ItemsData :: any, itemId)
	return if type(item) == "table" then item else nil
end

local function itemIcon(itemId: string): string
	local item = itemOf(itemId)
	return if item then item.Icon else "❔"
end

-- The highest level any nurse can have (Lv 15 from R3): workers only clamp junk with it.
local function maxLevel(): number
	return NurseLogic.levelCap(Config.Nurses.LevelCapRebirths, Config)
end

local function rebirthsOf(data: any): number
	local rebirth = if type(data) == "table" then data.Rebirth else nil
	return if type(rebirth) == "table" and type(rebirth.Count) == "number" then rebirth.Count else 0
end

local function capOf(data: any): number
	return NurseLogic.rosterCap(rebirthsOf(data), Config)
end

local function hospitalLevel(data: any): number
	local level = if type(data) == "table" then data.Level else nil
	if type(level) ~= "number" or level ~= level then
		return 1
	end
	return math.max(1, math.floor(level))
end

local function effectsOf(data: any): any
	local ok, effects = pcall(RebirthLogic.effects, data, Config, PerksData, TreeData)
	return if ok and type(effects) == "table" then effects else {}
end

-- The plot a caller means: the Plots table, or (leniently) its Model.
local function plotOf(value: any): Plot?
	if type(value) == "table" and typeof(value.Model) == "Instance" then
		return value
	end
	if typeof(value) == "Instance" then
		return Plots.fromInstance(value)
	end
	return nil
end

local function attributeList(model: Model, name: string): { string }
	return RecipeLogic.split(model:GetAttribute(name))
end

local function setAttribute(instance: Instance, name: string, value: any)
	if instance:GetAttribute(name) ~= value then
		instance:SetAttribute(name, value)
	end
end

local function fire(remote: RemoteEvent, player: Player, payload: any)
	if player.Parent == Players then
		remote:FireClient(player, payload)
	end
end

local function news(player: Player, payload: Types.NurseNews)
	fire(Remotes.NurseNews, player, payload)
end

------------------------------------------------------------------------------------------------------------------
-- The nurse tray (the plot's NurseTray attribute is the only copy)
------------------------------------------------------------------------------------------------------------------

local function trayGui(plot: Plot): TextLabel?
	local existing = trayLabels[plot]
	if existing and existing.Parent then
		return existing
	end
	local counter = plot.Counter
	if not counter or not counter.Parent then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = TRAY_GUI
	gui.Size = UDim2.fromScale(5, 1.5) -- studs
	gui.StudsOffsetWorldSpace =
		counter.CFrame:VectorToWorldSpace(Vector3.new(counter.Size.X / 2 - 2.4, counter.Size.Y / 2 + 1.5, 0))
	gui.DistanceLowerLimit = NEAR_STUDS
	gui.MaxDistance = 110
	gui.LightInfluence = 0
	gui.Enabled = false
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.Size = UDim2.fromScale(1, 1)
	pill.BackgroundColor3 = Palette.White
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = pill
	Palette.outlineShape(pill, 2)
	local label = Instance.new("TextLabel")
	label.Name = "Items"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.9, 0.8)
	label.Position = UDim2.fromScale(0.05, 0.1)
	label.TextScaled = true
	label.Font = Palette.BodyFont
	label.TextColor3 = Palette.Ink
	label.Text = ""
	label.Parent = pill
	pill.Parent = gui
	gui.Parent = counter
	trayLabels[plot] = label
	return label
end

local function showTray(plot: Plot)
	local items = attributeList(plot.Model, TRAY_ATTRIBUTE)
	local label = trayGui(plot)
	if not label then
		return
	end
	local icons: { string } = {}
	for _, itemId in items do
		table.insert(icons, itemIcon(itemId))
	end
	label.Text = "🧺 " .. table.concat(icons, "")
	local gui = label:FindFirstAncestorWhichIsA("BillboardGui")
	if gui then
		gui.Enabled = #items > 0
	end
end

local function writeTray(plot: Plot, items: { string })
	local cut = table.move(items, 1, math.min(#items, Config.Nurses.TrayMax), 1, {})
	setAttribute(plot.Model, TRAY_ATTRIBUTE, RecipeLogic.join(cut))
end

function Nurses.trayItems(plotArg: Plot): { string }
	local plot = plotOf(plotArg)
	if not plot then
		return {}
	end
	return attributeList(plot.Model, TRAY_ATTRIBUTE)
end

function Nurses.takeFromTray(plotArg: Plot, itemId: string): boolean
	local plot = plotOf(plotArg)
	if not plot or type(itemId) ~= "string" then
		return false
	end
	local tray, taken = Pure.trayTake(attributeList(plot.Model, TRAY_ATTRIBUTE), itemId)
	if taken then
		writeTray(plot, tray)
	end
	return taken
end

function Nurses.addToTray(plotArg: Plot, itemId: string): boolean
	local plot = plotOf(plotArg)
	local item = itemOf(itemId)
	if not plot or not item or item.Medicine ~= nil then
		return false
	end
	local tray, added = Pure.trayAdd(
		attributeList(plot.Model, TRAY_ATTRIBUTE),
		itemId,
		Config.Nurses.TrayMax,
		attributeList(plot.Model, "QueueNeeds")
	)
	if added then
		writeTray(plot, tray)
	end
	return added
end

------------------------------------------------------------------------------------------------------------------
-- Where nurses stand
------------------------------------------------------------------------------------------------------------------

local function flat(direction: Vector3): Vector3
	local d = Vector3.new(direction.X, 0, direction.Z)
	return if d.Magnitude > 1e-3 then d.Unit else Vector3.zAxis
end

-- The floor (plot Ground or a room floor) under a point.
local function groundAt(work: Work, position: Vector3): Vector3
	local baseY = work.Plot.Model:GetPivot().Y
	local hit = Workspace:Raycast(Vector3.new(position.X, baseY + 3, position.Z), Vector3.new(0, -8, 0), work.Ray)
	return Vector3.new(position.X, if hit then hit.Position.Y else baseY, position.Z)
end

-- A spot by the Counter, in counter-local x/z (the Counter's -Z side is the line's side), facing `face`.
local function byCounter(work: Work, x: number, z: number, face: Vector3): CFrame
	local counter = work.Plot.Counter
	local point = (counter.CFrame * CFrame.new(x, -counter.Size.Y / 2, z)).Position
	local ground = groundAt(work, point)
	return CFrame.lookAt(ground, ground + flat(face))
end

-- A spot beside a marker CFrame (dx to its right, dz behind it), on the ground, facing the marker's way.
local function byMarker(work: Work, marker: CFrame, dx: number, dz: number): CFrame
	local point = (marker * CFrame.new(dx, 0, dz)).Position
	local ground = groundAt(work, point)
	return CFrame.lookAt(ground, ground + flat(marker.LookVector))
end

-- Healers stand behind the Counter on the right, looking at the line; idle Makers on the left.
local function healerSpot(work: Work, index: number): CFrame
	local counter = work.Plot.Counter
	local x = counter.Size.X / 2 - 1.6 - (index - 1) * SPOT_SPACING
	return byCounter(work, x, counter.Size.Z / 2 + 1.9, counter.CFrame.LookVector)
end

local function makerHome(work: Work, index: number): CFrame
	local counter = work.Plot.Counter
	local x = -(counter.Size.X / 2 - 1.6) + (index - 1) * SPOT_SPACING
	return byCounter(work, x, counter.Size.Z / 2 + 1.9, counter.CFrame.LookVector)
end

-- Cheerers stand beside the front of the line (the Counter's left), facing it.
local function cheerSpot(work: Work, index: number): CFrame
	local counter = work.Plot.Counter
	local x = -(counter.Size.X / 2 + 2) - (index - 1) * SPOT_SPACING
	return byCounter(work, x, -(counter.Size.Z / 2 + 1.5), counter.CFrame.RightVector)
end

-- Receptionists stand at the Counter's right end, on the line's side, facing the line (clear of the queue lane).
local function receptionSpot(work: Work, index: number): CFrame
	local counter = work.Plot.Counter
	local x = counter.Size.X / 2 + 3.2 + (index - 1) * SPOT_SPACING
	return byCounter(work, x, -(counter.Size.Z / 2 + 1.5), -counter.CFrame.RightVector)
end

-- A Medic helping a 🚑/🚁 patient stands just right of the front of the line, facing it.
local function medicTreatSpot(work: Work, index: number): CFrame
	local counter = work.Plot.Counter
	local x = 3.9 + (index - 1) * 2.2
	return byCounter(work, x, -(counter.Size.Z / 2 + 2.2), -counter.CFrame.RightVector)
end

-- In front of a station, a little to one side (the player making stands in the middle), facing it.
local function stationSpot(work: Work, station: BasePart, index: number): CFrame
	local side = if index % 2 == 1 then 1 else -1
	local cf = station.CFrame
	local point = (cf * CFrame.new(side * 1.3, -station.Size.Y / 2, -(station.Size.Z / 2 + 1.5))).Position
	local ground = groundAt(work, point)
	return CFrame.lookAt(ground, ground - flat(cf.LookVector))
end

-- A marker under the plot's Building (by name, anywhere below it): a Part's or a Model's CFrame.
local function buildingMarker(work: Work, path: { string }): CFrame?
	local node: Instance? = work.Plot.Model:FindFirstChild("Building")
	for _, name in path do
		if not node then
			return nil
		end
		node = node:FindFirstChild(name, true)
	end
	if node and node:IsA("BasePart") then
		return node.CFrame
	elseif node and node:IsA("Model") then
		return node:GetPivot()
	end
	return nil
end

-- Medics wait at the ambulance bay (beside its StretcherSpot; T6 builds it from Lv 2). Before there is one, at the
-- far left end behind the Counter.
local function medicHome(work: Work, index: number): CFrame
	local marker = buildingMarker(work, { "AmbulanceBay", "StretcherSpot" })
		or buildingMarker(work, { "AmbulanceBay", "BayFloor" })
	if marker then
		return byMarker(work, marker, 2.4 + (index - 1) * 2.2, 0)
	end
	local counter = work.Plot.Counter
	local x = -(counter.Size.X / 2 + 2.4) - (index - 1) * 2.2
	return byCounter(work, x, counter.Size.Z / 2 + 1.9, counter.CFrame.LookVector)
end

local function landing(work: Work, floor: number): CFrame?
	local ok, cf = pcall(Lift.landing, work.Plot, floor)
	return if ok and typeof(cf) == "CFrame" then cf else nil
end

-- Porters idle beside the ground landing of the lift (T6's Building.Landing_0); before there is one, at the right end
-- behind the Counter.
local function porterHome(work: Work, index: number): CFrame
	local marker = landing(work, 0)
	if marker then
		return byMarker(work, marker, 2.6 + (index - 1) * 2.2, 1.2)
	end
	local counter = work.Plot.Counter
	local x = counter.Size.X / 2 + 2.4 + (index - 1) * 2.2
	return byCounter(work, x, counter.Size.Z / 2 + 1.9, counter.CFrame.LookVector)
end

local function homeFor(work: Work, job: string, index: number): CFrame
	if job == "Healer" then
		return healerSpot(work, index)
	elseif job == "Cheerer" then
		return cheerSpot(work, index)
	elseif job == "Receptionist" then
		return receptionSpot(work, index)
	elseif job == "Medic" then
		return medicHome(work, index)
	elseif job == "Porter" then
		return porterHome(work, index)
	end
	return makerHome(work, index)
end

-- Station_<id> is a Part by contract; a kit room may use a Model (its main part).
local function stationPart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

-- Every item this plot's stations make (never a medicine: the 💊 Pharmacy needs two carried ingredients), with the
-- station part and id.
local function stationsOf(plot: Plot): { [string]: { Part: BasePart, Station: string } }
	local found: { [string]: { Part: BasePart, Station: string } } = {}
	local rooms = plot.Model:FindFirstChild("Rooms")
	if not rooms then
		return found
	end
	for _, descendant in rooms:GetDescendants() do
		local stationId = string.match(descendant.Name, "^Station_(%w+)$")
		if stationId then
			local part = stationPart(descendant)
			for _, itemId in ItemsData.Order do
				local item = itemOf(itemId)
				if part and item and item.Medicine == nil and item.Station == stationId and not found[itemId] then
					found[itemId] = { Part = part, Station = stationId }
				end
			end
		end
	end
	return found
end

------------------------------------------------------------------------------------------------------------------
-- Moving (the creature-motion contract via NurseBuilder.hop)
------------------------------------------------------------------------------------------------------------------

local function hopTo(w: Worker, to: CFrame, height: number, seconds: number, spin: number?): boolean
	if not w.Alive then
		return false
	end
	local ok = NurseBuilder.hop(w.Model, w.Pivot, to, height, seconds, spin)
	if ok then
		w.Pivot = to
	end
	return ok and w.Alive
end

local function far(a: CFrame, b: CFrame): boolean
	local delta = Vector3.new(a.X - b.X, 0, a.Z - b.Z)
	return delta.Magnitude > 0.4 or math.abs(a.Y - b.Y) > 0.6 or a.LookVector:Dot(b.LookVector) < 0.95
end

-- Hops to `target` a few studs at a time, facing where it goes, and lands facing the target's way. `level` true: each
-- hop keeps the current height (a porter on a ward floor); false: each hop lands on the ground under it. `still`
-- (optional) is asked before every hop: false stops the walk (an escort whose claim ended).
local function walkTo(work: Work, w: Worker, target: CFrame, level: boolean?, still: (() -> boolean)?): boolean
	for _ = 1, 60 do
		if not w.Alive or (still ~= nil and not still()) then
			return false
		end
		local from = w.Pivot.Position
		local delta = Vector3.new(target.X - from.X, 0, target.Z - from.Z)
		local distance = delta.Magnitude
		if distance <= HOP_LENGTH then
			if not far(w.Pivot, target) then
				return true
			end
			local seconds = HOP_SECONDS * math.sqrt(math.max(distance, 0.6) / HOP_LENGTH)
			return hopTo(w, target, if distance < 0.4 then 0.3 else HOP_HEIGHT, seconds)
		end
		local direction = delta / distance
		local step = from + direction * HOP_LENGTH
		local landingAt = if level then step else groundAt(work, step)
		if not hopTo(w, CFrame.lookAt(landingAt, landingAt + direction), HOP_HEIGHT, HOP_SECONDS) then
			return false
		end
	end
	return w.Alive
end

local function goTo(work: Work, w: Worker, target: CFrame): boolean
	if not far(w.Pivot, target) then
		return w.Alive
	end
	NurseBuilder.setTask(w.Model, "Walking")
	return walkTo(work, w, target)
end

local function sleep(w: Worker, seconds: number): boolean
	local untilAt = os.clock() + seconds
	while w.Alive do
		local left = untilAt - os.clock()
		if left <= 0 then
			break
		end
		task.wait(math.min(left, LOOK_SECONDS))
	end
	return w.Alive
end

local function idleHop(w: Worker): boolean
	return hopTo(w, w.Pivot, 0.45, 0.3)
end

local function spinHop(w: Worker, height: number): boolean
	return hopTo(w, w.Pivot, height, 0.5, math.pi * 2)
end

-- The server's truth for where the model stands (Lift.carry PivotTo's riders between floors).
local function resync(w: Worker)
	local root = w.Model.PrimaryPart
	if root and root.Parent then
		w.Pivot = root.CFrame
	end
end

------------------------------------------------------------------------------------------------------------------
-- The six jobs
------------------------------------------------------------------------------------------------------------------

-- Stats for the job a worker works now, with its specialty (the department it works in; a Maker's is its station's).
local function statsFor(w: Worker, stationId: string?): NurseLogic.Stats
	local dept = JobsLogic.department(w.Job, stationId, JobsData, DeptData.Stations)
	return NurseLogic.stats(w.Job, w.Rarity, w.Level, Config, Pure.matches(w.Specialty, dept))
end

local function everyFor(work: Work, w: Worker, stationId: string?): number
	local stats = statsFor(w, stationId)
	return Pure.shift(stats.Every or 10, work.Shift, Config.Nurses.MinSeconds)
end

local function deposit(work: Work, item: string)
	local plot = work.Plot
	local tray, added = Pure.trayAdd(
		attributeList(plot.Model, TRAY_ATTRIBUTE),
		item,
		Config.Nurses.TrayMax,
		attributeList(plot.Model, "QueueNeeds")
	)
	if added then
		writeTray(plot, tray)
	end
end

local function nextItem(work: Work, w: Worker): (string?, { [string]: { Part: BasePart, Station: string } })
	local plot = work.Plot
	local tray = attributeList(plot.Model, TRAY_ATTRIBUTE)
	local have = table.clone(tray)
	for _, other in work.Workers do
		if other ~= w and other.Making then
			table.insert(have, other.Making)
		end
	end
	for _, carried in RecipeLogic.split(work.Owner:GetAttribute("Carry")) do
		table.insert(have, carried)
	end
	local stations = stationsOf(plot)
	local canMake: { [string]: boolean } = {}
	for itemId in stations do
		canMake[itemId] = true
	end
	local needs = attributeList(plot.Model, "QueueNeeds")
	return Pure.pickMake(needs, have, canMake, tray, Config.Nurses.TrayMax), stations
end

-- Waits while Patients holds a claimed porter, and until its last escort hop has landed (any job: a claim can outlive
-- a job change until it's released). One mover per nurse, always.
local function holdWhileClaimed(w: Worker): boolean
	while w.Alive and (w.Claimed or w.Busy) do
		w.Free = false
		if os.clock() - w.ClaimedAt > CLAIM_MAX then
			w.Claimed = false -- a lost release: let go by itself
			w.Busy = false
			w.Escort += 1
			resync(w)
			break
		end
		task.wait(0.2)
	end
	return w.Alive
end

local function makerLoop(work: Work, w: Worker)
	local nextIdle = os.clock() + rng:NextNumber(3, 6)
	if not goTo(work, w, makerHome(work, w.Index)) then
		return
	end
	NurseBuilder.setTask(w.Model, "Idle")
	while w.Alive do
		local item, stations = nextItem(work, w)
		local where = if item then stations[item] else nil
		if item and where then
			w.Making = item
			setAttribute(w.Model, "Station", where.Station)
			if not goTo(work, w, stationSpot(work, where.Part, w.Index)) then
				return
			end
			NurseBuilder.setTask(w.Model, "Making", itemIcon(item))
			if not sleep(w, everyFor(work, w, where.Station)) then
				return
			end
			deposit(work, item)
			w.Making = nil
			setAttribute(w.Model, "Station", "")
			NurseBuilder.setTask(w.Model, "Idle")
			if not hopTo(w, w.Pivot, 0.7, 0.35) then -- a proud little bounce
				return
			end
			nextIdle = os.clock() + rng:NextNumber(4, 7)
		elseif os.clock() >= nextIdle then
			nextIdle = os.clock() + rng:NextNumber(4, 7)
			if not idleHop(w) then
				return
			end
		else
			task.wait(LOOK_SECONDS)
		end
	end
end

-- Fires Heal and waits a moment for Treatment's delivery (Nurses.healed). True when it landed.
local function heal(work: Work, w: Worker, target: string): boolean
	w.Healed = false
	Nurses.Heal:Fire(work.Plot, w.NurseId, target)
	local waitUntil = os.clock() + HEAL_WAIT
	while w.Alive and not w.Healed and os.clock() < waitUntil do
		task.wait(0.1)
	end
	local landed = w.Healed
	w.Healed = false
	return landed
end

local function healerLoop(work: Work, w: Worker)
	local nextAt = os.clock() + everyFor(work, w) * rng:NextNumber(0.25, 0.6) -- staggered: two Healers don't race
	local nextIdle = os.clock() + rng:NextNumber(3, 6)
	while w.Alive do
		if not goTo(work, w, healerSpot(work, w.Index)) then
			return
		end
		local now = os.clock()
		local front = attributeList(work.Plot.Model, "FrontNeeds")
		if now >= nextAt and Pure.canHeal(front, attributeList(work.Plot.Model, TRAY_ATTRIBUTE)) then
			NurseBuilder.setTask(w.Model, "Healing")
			local landed = heal(work, w, "Front")
			if not w.Alive then
				return
			end
			if landed then
				nextAt = os.clock() + everyFor(work, w)
				if not spinHop(w, 1.1) then -- a happy spin
					return
				end
			else
				nextAt = os.clock() + RETRY_SECONDS
			end
			NurseBuilder.setTask(w.Model, "Idle")
		elseif now >= nextIdle then
			nextIdle = now + rng:NextNumber(4, 7)
			if not idleHop(w) then
				return
			end
		else
			task.wait(LOOK_SECONDS)
		end
	end
end

local function lineBusy(work: Work): boolean
	local model = work.Plot.Model
	return (model:GetAttribute("QueueNeeds") or "") ~= "" or (model:GetAttribute("FrontNeeds") or "") ~= ""
end

local function cheererLoop(work: Work, w: Worker)
	local nextCheer = os.clock() + rng:NextNumber(1, 3)
	while w.Alive do
		if not goTo(work, w, cheerSpot(work, w.Index)) then
			return
		end
		local busy = lineBusy(work)
		NurseBuilder.setTask(w.Model, if busy then "Cheering" else "Idle")
		if os.clock() >= nextCheer then
			nextCheer = os.clock() + (if busy then rng:NextNumber(2.5, 4) else rng:NextNumber(5, 8))
			local ok = if busy then spinHop(w, 1) else idleHop(w)
			if not ok then
				return
			end
		else
			task.wait(LOOK_SECONDS)
		end
	end
end

-- Greets the line from the Counter's other side: a little wave-hop now and then while patients wait.
local function receptionistLoop(work: Work, w: Worker)
	local nextWave = os.clock() + rng:NextNumber(1, 3)
	while w.Alive do
		if not goTo(work, w, receptionSpot(work, w.Index)) then
			return
		end
		local busy = lineBusy(work)
		NurseBuilder.setTask(w.Model, if busy then "Greeting" else "Idle")
		if os.clock() >= nextWave then
			nextWave = os.clock() + (if busy then rng:NextNumber(3, 5) else rng:NextNumber(6, 9))
			if not hopTo(w, w.Pivot, if busy then 0.7 else 0.45, 0.35) then
				return
			end
		else
			task.wait(LOOK_SECONDS)
		end
	end
end

-- The waiting 🚑/🚁 patients at this plot and what they still need (the patients' attributes, set by Patients).
local function urgentNeeds(work: Work): ({ string }, boolean)
	local folder = work.Plot.Model:FindFirstChild("Patients")
	local list: { any } = {}
	if folder then
		for _, child in folder:GetChildren() do
			local urgent = child:GetAttribute("Urgent")
			if type(urgent) == "string" and urgent ~= "" then
				local recipe = RecipeLogic.split(child:GetAttribute("Recipe"))
				local done = RecipeLogic.decode(child:GetAttribute("RecipeDone"), #recipe)
				table.insert(list, {
					Urgent = urgent,
					State = child:GetAttribute("State"),
					Queue = child:GetAttribute("QueueIndex"),
					Missing = RecipeLogic.missing(recipe, done),
				})
			end
		end
	end
	local needs = Pure.urgentNeeds(list)
	local waiting = false
	for _, p in list do
		if p.State == "Waiting" and type(p.Queue) == "number" and p.Queue >= 1 then
			waiting = true
		end
	end
	return needs, waiting
end

local function medicLoop(work: Work, w: Worker)
	local nextAt = os.clock() + everyFor(work, w) * rng:NextNumber(0.25, 0.6)
	local nextIdle = os.clock() + rng:NextNumber(3, 6)
	while w.Alive do
		local needs, waiting = urgentNeeds(work)
		if waiting then
			if not goTo(work, w, medicTreatSpot(work, w.Index)) then
				return
			end
			local now = os.clock()
			if now >= nextAt and Pure.canHeal(needs, attributeList(work.Plot.Model, TRAY_ATTRIBUTE)) then
				NurseBuilder.setTask(w.Model, "Treating")
				local landed = heal(work, w, "Urgent")
				if not w.Alive then
					return
				end
				if landed then
					nextAt = os.clock() + everyFor(work, w)
					if not spinHop(w, 1.1) then
						return
					end
				else
					nextAt = os.clock() + RETRY_SECONDS
				end
			else
				NurseBuilder.setTask(w.Model, "Treating")
				task.wait(LOOK_SECONDS)
			end
		else
			if not goTo(work, w, medicHome(work, w.Index)) then
				return
			end
			NurseBuilder.setTask(w.Model, "Idle")
			if os.clock() >= nextIdle then
				nextIdle = os.clock() + rng:NextNumber(5, 8)
				if not idleHop(w) then
					return
				end
			else
				task.wait(LOOK_SECONDS)
			end
		end
	end
end

local function upstairs(work: Work, w: Worker): boolean
	return w.Pivot.Y - groundAt(work, w.Pivot.Position).Y > UPSTAIRS
end

-- A porter left upstairs after a trip rides the lift back down: it hops to the nearest floor's landing and
-- Lift.carry takes it to the ground. No lift (or the ride fails): a poof, and it pops in at home.
local function rideDown(work: Work, w: Worker): boolean
	local building = work.Plot.Model:FindFirstChild("Building")
	local floors = if building then building:GetAttribute("Floors") else nil
	local best: CFrame? = nil
	if type(floors) == "number" then
		for floor = 1, math.clamp(math.floor(floors), 0, 8) do
			local at = landing(work, floor)
			if at and (best == nil or math.abs(at.Y - w.Pivot.Y) < math.abs(best.Y - w.Pivot.Y)) then
				best = at
			end
		end
	end
	local rode = false
	if best then
		NurseBuilder.setTask(w.Model, "Walking")
		if not walkTo(work, w, best, true) then
			return false
		end
		local ok, carried = pcall(Lift.carry, work.Plot, { w.Model }, 0)
		if not w.Alive then
			return false
		end
		rode = ok and carried == true
		resync(w)
	end
	if not rode or upstairs(work, w) then
		pcall(CreatureBuilder.effectAt, w.Pivot.Position + Vector3.new(0, 1.5, 0), "Pop")
		local home = porterHome(work, w.Index)
		w.Model:PivotTo(home)
		w.Pivot = home
		NurseBuilder.popIn(w.Model)
	end
	return w.Alive
end

local function porterLoop(work: Work, w: Worker)
	local nextIdle = os.clock() + rng:NextNumber(3, 6)
	while w.Alive do
		if w.Claimed or w.Busy then
			if not holdWhileClaimed(w) then
				return
			end
		elseif upstairs(work, w) then
			w.Free = false
			if not rideDown(work, w) then
				return
			end
		else
			local home = porterHome(work, w.Index)
			if far(w.Pivot, home) then
				w.Free = false
				if not goTo(work, w, home) then
					return
				end
			end
			NurseBuilder.setTask(w.Model, "Idle")
			if os.clock() >= nextIdle then
				nextIdle = os.clock() + rng:NextNumber(5, 8)
				w.Free = false -- never claimed mid-hop
				if not idleHop(w) then
					return
				end
			else
				w.Free = true
				task.wait(LOOK_SECONDS)
			end
		end
	end
end

local LOOPS: { [string]: (Work, Worker) -> () } = {
	Maker = makerLoop,
	Healer = healerLoop,
	Cheerer = cheererLoop,
	Receptionist = receptionistLoop,
	Medic = medicLoop,
	Porter = porterLoop,
}

-- Every loop starts by waiting out a claim (a porter re-jobbed while it was escorting keeps still until released).
local function run(work: Work, w: Worker)
	local loop = LOOPS[w.Job] or makerLoop
	w.Thread = task.spawn(function()
		local fine, err = pcall(function()
			if holdWhileClaimed(w) then
				loop(work, w)
			end
		end)
		if not fine and w.Alive then
			report("a " .. w.Job .. "'s work", err)
		end
	end)
end

------------------------------------------------------------------------------------------------------------------
-- Workers on a plot
------------------------------------------------------------------------------------------------------------------

-- Cheer, Reception, Medic and the team bonuses from the nurses at work, on the plot's attributes too (§B4).
local function refreshPlot(work: Work, wanted: { string })
	local cheers, desks, medics = {}, {}, {}
	for _, w in work.Workers do
		if w.Job == "Cheerer" then
			table.insert(cheers, statsFor(w))
		elseif w.Job == "Receptionist" then
			table.insert(desks, statsFor(w))
		elseif w.Job == "Medic" then
			table.insert(medics, statsFor(w))
		end
	end
	local best = NurseLogic.bestCheer(cheers)
	work.Cheer = { Patience = best.Patience, Tip = best.Tip }
	work.Reception = { Arrive = NurseLogic.best(desks, "Arrive"), Triage = #desks > 0 }
	work.Medic = { Patience = NurseLogic.best(medics, "Urgent") }

	local specialties: { string } = {}
	for _, nurseId in wanted do
		local nurse = nurseOf(nurseId)
		if nurse and type(nurse.Specialty) == "string" then
			table.insert(specialties, nurse.Specialty)
		end
	end
	local counts = JobsLogic.teams(specialties, DeptData)
	work.Team = JobsLogic.teamEffects(counts, DeptData)

	local model = work.Plot.Model
	setAttribute(model, "CheerPatience", best.Patience)
	setAttribute(model, "CheerTip", best.Tip)
	setAttribute(model, "Reception", work.Reception.Arrive)
	setAttribute(model, "Triage", work.Reception.Triage)
	setAttribute(model, "MedicPatience", work.Medic.Patience)
	setAttribute(model, "TeamBonus", Pure.teamLine(counts, DeptData))
	setAttribute(model, "TeamCash", work.Team.Cash)
	setAttribute(model, "TeamRecover", work.Team.Recover)
	setAttribute(model, "TeamUrgent", work.Team.Urgent)
	setAttribute(model, "TeamMake", Pure.makeLine(work.Team.Make))
end

local function removeWorker(work: Work, w: Worker, puff: boolean)
	w.Alive = false
	work.Workers[w.NurseId] = nil
	local thread = w.Thread
	w.Thread = nil
	if thread and thread ~= coroutine.running() and coroutine.status(thread) ~= "dead" then
		pcall(task.cancel, thread)
	end
	if puff and w.Model.Parent then
		pcall(CreatureBuilder.effectAt, w.Pivot.Position + Vector3.new(0, 1.5, 0), "Pop")
	end
	w.Model:Destroy()
end

local function newWorker(nurseId: string, nurse: any, job: string, level: number, index: number, model: Model): Worker
	return {
		NurseId = nurseId,
		Role = nurse.Role,
		Job = job,
		Specialty = if type(nurse.Specialty) == "string" then nurse.Specialty else "",
		Rarity = nurse.Rarity,
		Level = level,
		Model = model,
		Pivot = CFrame.identity,
		Index = index,
		Alive = true,
		Thread = nil,
		Making = nil,
		Healed = false,
		Claimed = false,
		ClaimedAt = 0,
		Busy = false,
		Escort = 0,
		Free = false,
		RestUntil = 0,
		Retask = false,
	}
end

local function dressModel(model: Model, job: string, level: number)
	model:SetAttribute("Level", level)
	model:SetAttribute("Station", "")
	NurseBuilder.setJob(model, job)
	NurseBuilder.setTask(model, "Idle")
end

local function addWorker(work: Work, nurseId: string, job: string, level: number, index: number)
	local nurse = nurseOf(nurseId)
	if not nurse then
		return
	end
	local ok, model = pcall(NurseBuilder.build, nurseId)
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		report("NurseBuilder.build " .. nurseId, model)
		return
	end
	local start = homeFor(work, job, index)
	model:PivotTo(start)
	model:SetAttribute("Specialty", if type(nurse.Specialty) == "string" then nurse.Specialty else "")
	dressModel(model, job, level)
	local dressed, err = pcall(NurseBuilder.addAbility, model, nurse.Ability)
	if not dressed then
		report("NurseBuilder.addAbility", err)
	end
	CollectionService:AddTag(model, MOTION_TAG)
	model.Parent = work.Folder
	NurseBuilder.popIn(model)

	local w = newWorker(nurseId, nurse, job, level, index, model)
	w.Pivot = start
	work.Workers[nurseId] = w
	run(work, w)
end

-- The same nurse (and model, where it stands) starts another job: the old worker record stops, a new one starts.
local function retask(work: Work, old: Worker, job: string, index: number)
	local nurse = nurseOf(old.NurseId)
	if not nurse then
		return
	end
	old.Alive = false
	local thread = old.Thread
	old.Thread = nil
	if thread and thread ~= coroutine.running() and coroutine.status(thread) ~= "dead" then
		pcall(task.cancel, thread)
	end
	local w = newWorker(old.NurseId, nurse, job, old.Level, index, old.Model)
	w.Pivot = old.Pivot
	dressModel(w.Model, job, old.Level)
	work.Workers[old.NurseId] = w
	run(work, w)
end

-- Makes the plot's nurses match the owner's save: the working nurses (Logic/Nurse.working: not resting, known, by
-- NurseId, at most the roster cap), each at its level and on its effective job (Logic/Jobs.effective: a job not open
-- at this hospital level is worked as the Role). Idempotent and cheap (it diffs), so it runs after every change.
local function sync(owner: Player)
	local plot = Plots.getPlot(owner)
	local work = if plot then works[plot] else nil
	local data = PlayerData.get(owner)
	if not work or work.Owner ~= owner or not data then
		return
	end
	local wanted = NurseLogic.working(data.Nurses, capOf(data), knownNurse)
	local keep: { [string]: boolean } = {}
	for _, nurseId in wanted do
		keep[nurseId] = true
	end
	for nurseId, w in table.clone(work.Workers) do
		if not keep[nurseId] then
			removeWorker(work, w, true)
		end
	end
	work.Shift = effectsOf(data).DoubleShift or 1
	local level = hospitalLevel(data)
	local perJob: { [string]: number } = {}
	for _, nurseId in wanted do
		local nurse = nurseOf(nurseId)
		local entry = data.Nurses[nurseId]
		local job = JobsLogic.effective(entry.Job, nurse.Role, level, JobsData)
		local index = (perJob[job] or 0) + 1
		perJob[job] = index
		local nurseLevel = Pure.level(entry, maxLevel())
		local w = work.Workers[nurseId]
		if w then
			if w.Level ~= nurseLevel then
				w.Level = nurseLevel
				w.Model:SetAttribute("Level", nurseLevel)
			end
			if w.Job ~= job then
				if w.Claimed then
					w.Retask = true -- Patients is using it as a porter: change it once released
				else
					retask(work, w, job, index)
				end
			else
				w.Index = index
			end
		else
			addWorker(work, nurseId, job, nurseLevel, index)
		end
	end
	refreshPlot(work, wanted)
end

local function ensureFolder(plot: Plot): Folder
	local existing = plot.Model:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = plot.Model
	return folder
end

local function neutralTeam(): Types.TeamEffects
	return { Cash = 1, Urgent = 1, Recover = 1, Make = {} }
end

local function resetPlot(plot: Plot)
	local model = plot.Model
	setAttribute(model, TRAY_ATTRIBUTE, "")
	setAttribute(model, "CheerPatience", 1)
	setAttribute(model, "CheerTip", 1)
	setAttribute(model, "Reception", 1)
	setAttribute(model, "Triage", false)
	setAttribute(model, "MedicPatience", 1)
	setAttribute(model, "TeamBonus", "")
	setAttribute(model, "TeamCash", 1)
	setAttribute(model, "TeamRecover", 1)
	setAttribute(model, "TeamUrgent", 1)
	setAttribute(model, "TeamMake", "")
end

-- Never yields: it runs inside Plots.PlotReleased, before Plots clears the plot.
local function deactivate(plot: Plot)
	local work = works[plot]
	works[plot] = nil
	if work then
		for _, w in table.clone(work.Workers) do
			removeWorker(work, w, false)
		end
	end
	local folder = plot.Model:FindFirstChild(FOLDER_NAME)
	if folder then
		folder:ClearAllChildren()
	end
	resetPlot(plot)
end

local function activate(owner: Player, plot: Plot)
	local current = works[plot]
	if current and current.Owner ~= owner then
		deactivate(plot)
		current = nil
	end
	if not current then
		local ray = RaycastParams.new()
		ray.FilterType = Enum.RaycastFilterType.Include
		local include: { Instance } = {}
		for _, name in { "Ground", "Rooms" } do
			local found = plot.Model:FindFirstChild(name)
			if found then
				table.insert(include, found)
			end
		end
		ray.FilterDescendantsInstances = include
		resetPlot(plot)
		works[plot] = {
			Plot = plot,
			Owner = owner,
			Folder = ensureFolder(plot),
			Ray = ray,
			Workers = {},
			Shift = 1,
			Cheer = { Patience = 1, Tip = 1 },
			Reception = { Arrive = 1, Triage = false },
			Medic = { Patience = 1 },
			Team = neutralTeam(),
		}
	end
	sync(owner)
end

local function workOf(plotArg: any): Work?
	local plot = plotOf(plotArg)
	return if plot then works[plot] else nil
end

------------------------------------------------------------------------------------------------------------------
-- The Journal
------------------------------------------------------------------------------------------------------------------

-- Grants every complete journal group's reward not yet given into `data` (mutates it): cash, the decor and
-- JournalSets. Returns the rarities granted. Call it inside PlayerData.update.
local function grantSets(data: Types.Data): { string }
	local granted: { string } = {}
	for _, rarity in NurseLogic.setsDue(data.NurseIndex, NursesData, Rarities, data.JournalSets) do
		local info = rawget(Rarities :: any, rarity)
		if type(info) == "table" and data.JournalSets[rarity] ~= true then
			data.JournalSets[rarity] = true
			local cash = info.Journal.Cash
			if type(cash) == "number" and cash == cash and cash > 0 then
				data.Cash = math.min(MAX_CASH, data.Cash + math.floor(cash))
			end
			if knownDecor(info.Journal.Decor) then
				data.Decor.Owned[info.Journal.Decor] = true
			end
			table.insert(granted, rarity)
		end
	end
	return granted
end

local function celebrateSet(player: Player, rarity: string)
	local info = rawget(Rarities :: any, rarity)
	if type(info) ~= "table" then
		return
	end
	fire(Remotes.Celebrate, player, {
		Kind = "JournalSet",
		Title = info.Name .. " set done!",
		Icon = info.Icon,
		Rarity = rarity,
		Cash = info.Journal.Cash,
		Decor = info.Journal.Decor,
	})
	if knownDecor(info.Journal.Decor) then
		local ok, err = pcall(Book.placeReward, player, info.Journal.Decor)
		if not ok then
			report("Book.placeReward", err)
		end
	end
end

local function celebrateNew(player: Player, nurseId: string, level: number)
	local nurse = nurseOf(nurseId)
	fire(Remotes.Celebrate, player, {
		Kind = "NewNurse",
		Title = nurse.Name,
		Icon = nurse.Icon,
		Rarity = nurse.Rarity,
		NurseId = nurseId,
		Level = level,
	})
end

type LevelUp = { NurseId: string, From: number, To: number }

-- After the update that levelled them: NurseNews Level for each, the LevelUp signal, and Celebrate NurseLevel when an
-- ability got stronger (Lv 5, Lv 10).
local function announceLevels(player: Player, ups: { LevelUp }, newsToo: boolean)
	for _, up in ups do
		local nurse = nurseOf(up.NurseId)
		local stronger = Pure.abilityUp(up.From, up.To, Config.Abilities.UpgradeLevels)
		if newsToo then
			news(player, { Kind = "Level", NurseId = up.NurseId, Level = up.To, Ability = stronger })
		end
		Nurses.LevelUp:Fire(player, up.NurseId, up.To)
		if stronger and nurse then
			fire(Remotes.Celebrate, player, {
				Kind = "NurseLevel",
				Title = nurse.Name,
				Icon = nurse.Icon,
				Rarity = nurse.Rarity,
				NurseId = up.NurseId,
				Level = up.To,
				Ability = true,
			})
		end
	end
end

function Nurses.markSeen(nurseId: string, players: { Player }?)
	if not knownNurse(nurseId) then
		return
	end
	local list = if type(players) == "table" then players else Players:GetPlayers()
	for _, player in list do
		if isPlayer(player) and player.Parent == Players then
			local data = PlayerData.get(player)
			if data and data.NurseIndex[nurseId] == nil then
				local changed = false
				local saved = PlayerData.update(player, function(d)
					changed = NurseLogic.mark(d.NurseIndex, nurseId, "Seen")
				end)
				if saved and changed then
					news(player, { Kind = "Seen", NurseId = nurseId })
				end
			end
		end
	end
end

------------------------------------------------------------------------------------------------------------------
-- The roster
------------------------------------------------------------------------------------------------------------------

function Nurses.rosterCap(player: Player): number
	local data = if isPlayer(player) then PlayerData.get(player) else nil
	return capOf(data)
end

function Nurses.working(player: Player): { string }
	local data = if isPlayer(player) then PlayerData.get(player) else nil
	if not data then
		return {}
	end
	return NurseLogic.working(data.Nurses, capOf(data), knownNurse)
end

-- A sale or a rebirth made room: the first resting nurses (by NurseId) go back to work, in one update just after the
-- change that made room (deferred: never inside someone else's update).
local function queueWake(player: Player, data: any)
	if wakeQueued[player] or type(data) ~= "table" or #Pure.toWake(data.Nurses, capOf(data), knownNurse) == 0 then
		return
	end
	wakeQueued[player] = true
	task.defer(function()
		wakeQueued[player] = nil
		local woke: { string } = {}
		PlayerData.update(player, function(d)
			woke = Pure.toWake(d.Nurses, capOf(d), knownNurse)
			for _, nurseId in woke do
				d.Nurses[nurseId].Job = ""
			end
		end)
		for _, nurseId in woke do
			news(player, { Kind = "Resting", NurseId = nurseId, On = false })
		end
	end)
end

------------------------------------------------------------------------------------------------------------------
-- In and out of a save: grant, take, give (each ONE update, no yield between the check and the change)
------------------------------------------------------------------------------------------------------------------

function Nurses.grant(player: Player, nurseId: string, price: number, source: string?): (boolean, string)
	local from = if source == nil then "Belt" else source
	local cost = Pure.amount(price)
	if not isPlayer(player) or not knownNurse(nurseId) or not cost or type(from) ~= "string" or not SOURCES[from] then
		return false, Remotes.OOPS
	end
	-- A rebirth-only nurse never rides the belt or stocks the Agency: it only comes as a rebirth's gift (or an admin's).
	if NurseLogic.isRebirthOnly(NursesData, nurseId) and from ~= "Gift" and from ~= "Admin" then
		return false, Remotes.OOPS
	end
	local data = PlayerData.get(player)
	if not data then
		return false, Remotes.OOPS
	end
	local canAdd, why = NurseLogic.canAdd(data, nurseId, Config, knownNurse)
	if not canAdd then
		return false, why
	end
	if data.Cash < cost then
		return false, "Need 💰" .. Pure.cash(cost)
	end

	local level, before, isNew = 1, 1, false
	local sets: { string } = {}
	local added = false
	-- The checks again, the charge, the copy, the journal mark, a Gift's Pending removal and any set reward: ONE
	-- update, no yield inside.
	local saved = PlayerData.update(player, function(d)
		if not NurseLogic.canAdd(d, nurseId, Config, knownNurse) or d.Cash < cost then
			return
		end
		d.Cash -= cost
		local cap = NurseLogic.levelCap(rebirthsOf(d), Config)
		local old = d.Nurses[nurseId]
		before = Pure.level(old, maxLevel())
		local entry, new = NurseLogic.hire(old, cap, Config)
		d.Nurses[nurseId] = entry
		level, isNew = entry.Level, new
		NurseLogic.mark(d.NurseIndex, nurseId, "Hired")
		if from == "Gift" then
			local index = table.find(d.Rebirth.Pending, nurseId)
			if index then
				table.remove(d.Rebirth.Pending, index)
			end
		end
		sets = grantSets(d)
		added = true
	end)
	if not saved or not added then
		return false, Remotes.OOPS -- the save is closing (they're leaving), or it changed: nothing changed
	end

	local nurse = nurseOf(nurseId)
	news(player, { Kind = "Hired", NurseId = nurseId, Level = level, New = isNew })
	if isNew then
		celebrateNew(player, nurseId, level)
	elseif level > before then
		announceLevels(player, { { NurseId = nurseId, From = before, To = level } }, false)
	end
	for _, rarity in sets do
		celebrateSet(player, rarity)
	end
	Nurses.Hired:Fire(player, nurseId, level)
	sync(player)
	if isNew then
		return true, "🎉 Hired " .. nurse.Name .. "!"
	end
	return true, "⬆️ " .. nurse.Name .. " Lv " .. level .. "!"
end

function Nurses.take(player: Player, nurseId: string, cash: number, reason: string): (boolean, string, any)
	local amount = Pure.amount(cash)
	if not isPlayer(player) or not knownNurse(nurseId) or not amount or type(reason) ~= "string" then
		return false, Remotes.OOPS, nil
	end
	if not TAKE_REASONS[reason] then
		return false, Remotes.OOPS, nil
	end
	local data = PlayerData.get(player)
	if not data then
		return false, Remotes.OOPS, nil
	end
	local rebirthOnly = NurseLogic.isRebirthOnly(NursesData, nurseId)
	local ok, why = Pure.canTake(data.Nurses, nurseId, reason, Nurses.isListed(player, nurseId), rebirthOnly)
	if not ok then
		return false, why, nil
	end
	local removed: Entry? = nil
	local saved = PlayerData.update(player, function(d)
		if not Pure.canTake(d.Nurses, nurseId, reason, Nurses.isListed(player, nurseId), rebirthOnly) then
			return
		end
		removed = Pure.giveEntry(d.Nurses[nurseId], true)
		d.Nurses[nurseId] = nil
		d.Cash = math.min(MAX_CASH, d.Cash + amount)
	end)
	local entry = removed
	if not saved or not entry then
		return false, Remotes.OOPS, nil
	end
	if reason == "Market" then
		local map = listed[player]
		if map then
			map[nurseId] = nil
		end
		-- The Market's undo (give back to this player in this same frame) restores exactly this.
		local tokens = restoring[player] or {}
		restoring[player] = tokens
		tokens[nurseId] = table.clone(entry)
		task.defer(function()
			local current = restoring[player]
			if current then
				current[nurseId] = nil
				if next(current) == nil then
					restoring[player] = nil
				end
			end
		end)
	end
	news(player, {
		Kind = if reason == "Market" then "Gone" else "Sold",
		NurseId = nurseId,
		Cash = amount,
		Price = if reason == "Market" then amount else nil,
	})
	Nurses.Removed:Fire(player, nurseId)
	sync(player) -- the worker poofs off the plot
	return true, "💰 +" .. Pure.cash(amount), table.clone(entry)
end

function Nurses.give(player: Player, nurseId: string, entry: any, price: number): (boolean, string)
	local cost = Pure.amount(price)
	if not isPlayer(player) or not knownNurse(nurseId) or type(entry) ~= "table" or not cost then
		return false, Remotes.OOPS
	end
	local data = PlayerData.get(player)
	if not data then
		return false, Remotes.OOPS
	end
	local tokens = restoring[player]
	local undo = if tokens then tokens[nurseId] else nil
	local rebirthOnly = NurseLogic.isRebirthOnly(NursesData, nurseId)
	local source = if undo then undo else entry
	local ok, why = Pure.canGive(data, nurseId, source, cost, Config, knownNurse, rebirthOnly, undo ~= nil)
	if not ok then
		return false, why
	end
	local level = 1
	local sets: { string } = {}
	local added = false
	local saved = PlayerData.update(player, function(d)
		if not Pure.canGive(d, nurseId, source, cost, Config, knownNurse, rebirthOnly, undo ~= nil) then
			return
		end
		d.Cash -= cost
		local given = Pure.giveEntry(source, undo ~= nil)
		d.Nurses[nurseId] = given
		level = given.Level
		NurseLogic.mark(d.NurseIndex, nurseId, "Hired")
		sets = grantSets(d)
		added = true
	end)
	if not saved or not added then
		return false, Remotes.OOPS
	end
	if undo and tokens then
		tokens[nurseId] = nil -- one undo per take
		for _, rarity in sets do
			celebrateSet(player, rarity)
		end
		sync(player)
		return true, ""
	end
	local nurse = nurseOf(nurseId)
	news(player, { Kind = "Bought", NurseId = nurseId, Price = cost, Level = level })
	celebrateNew(player, nurseId, level)
	for _, rarity in sets do
		celebrateSet(player, rarity)
	end
	Nurses.Hired:Fire(player, nurseId, level)
	sync(player)
	return true, "🎉 " .. nurse.Name .. "!"
end

function Nurses.setListed(player: Player, nurseId: string, listingId: number?)
	if not isPlayer(player) or type(nurseId) ~= "string" then
		return
	end
	local map = listed[player]
	if listingId == nil then
		if map and map[nurseId] ~= nil then
			map[nurseId] = nil
			news(player, { Kind = "Listed", NurseId = nurseId, On = false })
		end
		return
	end
	if type(listingId) ~= "number" or listingId ~= listingId then
		return
	end
	local data = PlayerData.get(player)
	if not data or type(data.Nurses[nurseId]) ~= "table" then
		return
	end
	if not map then
		map = {}
		listed[player] = map
	end
	local was = map[nurseId]
	map[nurseId] = listingId
	if was == nil then
		news(player, { Kind = "Listed", NurseId = nurseId, On = true })
	end
end

function Nurses.isListed(player: Player, nurseId: string): boolean
	local map = listed[player]
	return map ~= nil and type(nurseId) == "string" and map[nurseId] ~= nil
end

------------------------------------------------------------------------------------------------------------------
-- Jobs (SetJob)
------------------------------------------------------------------------------------------------------------------

function Nurses.setJob(player: Player, nurseId: string, job: string): (boolean, string)
	if not isPlayer(player) or type(nurseId) ~= "string" or type(job) ~= "string" then
		return false, Remotes.OOPS
	end
	local nurse = nurseOf(nurseId)
	local info = jobOf(job)
	if not nurse or not info then
		return false, Remotes.OOPS
	end
	local data = PlayerData.get(player)
	if not data then
		return false, Remotes.OOPS
	end
	local ok, why, out =
		NurseLogic.setJob(data.Nurses, nurseId, job, hospitalLevel(data), capOf(data), JobsData, nurse.Role)
	if not ok then
		return false, why
	end
	local message = info.Icon .. " " .. info.Name .. "!"
	local before = data.Nurses[nurseId]
	if out[nurseId].Job == before.Job then
		return true, message -- nothing changes: no save write
	end
	local wasResting = before.Job == Pure.REST
	local changed = false
	PlayerData.update(player, function(d)
		local fine, _, next =
			NurseLogic.setJob(d.Nurses, nurseId, job, hospitalLevel(d), capOf(d), JobsData, nurse.Role)
		if fine then
			d.Nurses[nurseId] = next[nurseId]
			changed = true
		end
	end)
	if not changed then
		return false, Remotes.OOPS
	end
	news(player, { Kind = "Job", NurseId = nurseId, Job = job })
	if wasResting then
		news(player, { Kind = "Resting", NurseId = nurseId, On = false })
	end
	return true, message
end

local function onSetJob(player: Player, nurseId: any, job: any): (boolean, string)
	if type(nurseId) ~= "string" or type(job) ~= "string" or #nurseId > 40 or #job > 20 then
		return false, Remotes.OOPS
	end
	local now = os.clock()
	local last = lastSetJob[player]
	if last and now - last < SET_JOB_COOLDOWN then
		return false, Remotes.TOO_FAST
	end
	lastSetJob[player] = now
	return Nurses.setJob(player, nurseId, job)
end

------------------------------------------------------------------------------------------------------------------
-- XP
------------------------------------------------------------------------------------------------------------------

function Nurses.onCure(owner: Player, info: any)
	if not isPlayer(owner) then
		return
	end
	local data = PlayerData.get(owner)
	if not data or #NurseLogic.working(data.Nurses, capOf(data), knownNurse) == 0 then
		return
	end
	local cure = if type(info) == "table" then info else {}
	local wing = if type(cure.Wing) == "string" then cure.Wing else nil
	local urgent = if type(cure.Urgent) == "string" then cure.Urgent else nil
	local depts = {
		JobsLogic.patientDepartment(wing, urgent, DeptData.Wings),
		if type(cure.Dept) == "string" then cure.Dept else "",
	}
	local factor = effectsOf(data).XP or 1
	local ups: { LevelUp } = {}
	PlayerData.update(owner, function(d)
		local cap = NurseLogic.levelCap(rebirthsOf(d), Config)
		for _, nurseId in NurseLogic.working(d.Nurses, capOf(d), knownNurse) do
			local entry = d.Nurses[nurseId]
			local nurse = nurseOf(nurseId)
			local xp = Pure.cureXP(Config.NurseXP, nurse.Specialty, depts, factor)
			local from = Pure.level(entry, maxLevel())
			local out, gained = NurseLogic.addXP(entry, xp, cap)
			d.Nurses[nurseId] = out
			if gained > 0 then
				table.insert(ups, { NurseId = nurseId, From = from, To = out.Level })
			end
		end
	end)
	announceLevels(owner, ups, true)
end

------------------------------------------------------------------------------------------------------------------
-- The plot's numbers (Patients, Stations, Treatment, Cure read them)
------------------------------------------------------------------------------------------------------------------

function Nurses.team(plotArg: any): Types.TeamEffects
	local work = workOf(plotArg)
	if not work then
		return neutralTeam()
	end
	local t = work.Team
	return { Cash = t.Cash, Urgent = t.Urgent, Recover = t.Recover, Make = table.clone(t.Make) }
end

function Nurses.reception(plotArg: any): { Arrive: number, Triage: boolean }
	local work = workOf(plotArg)
	if not work then
		return { Arrive = 1, Triage = false }
	end
	return { Arrive = work.Reception.Arrive, Triage = work.Reception.Triage }
end

function Nurses.medic(plotArg: any): { Patience: number }
	local work = workOf(plotArg)
	if not work then
		return { Patience = 1 }
	end
	return { Patience = work.Medic.Patience }
end

function Nurses.cheer(plotArg: Plot): Types.Cheer
	local work = workOf(plotArg)
	if not work then
		return { Patience = 1, Tip = 1 }
	end
	return { Patience = work.Cheer.Patience, Tip = work.Cheer.Tip }
end

function Nurses.healed(plotArg: Plot, nurseId: string, _items: { string })
	local work = workOf(plotArg)
	local w = if work and type(nurseId) == "string" then work.Workers[nurseId] else nil
	if w and (w.Job == "Healer" or w.Job == "Medic") then
		w.Healed = true -- its loop plays the happy spin (one mover per nurse)
	end
end

------------------------------------------------------------------------------------------------------------------
-- Porters
------------------------------------------------------------------------------------------------------------------

function Nurses.claimPorter(plotArg: any): string?
	local work = workOf(plotArg)
	if not work then
		return nil
	end
	local ids: { string } = {}
	for nurseId, w in work.Workers do
		if w.Alive and w.Job == "Porter" and w.Free and not w.Claimed and not w.Busy and os.clock() >= w.RestUntil then
			table.insert(ids, nurseId)
		end
	end
	table.sort(ids)
	local nurseId = ids[1]
	if not nurseId then
		return nil
	end
	local w = work.Workers[nurseId]
	w.Claimed = true
	w.ClaimedAt = os.clock()
	w.Free = false
	return nurseId
end

function Nurses.escort(plotArg: any, nurseId: string, to: CFrame): boolean
	local work = workOf(plotArg)
	local w = if work and type(nurseId) == "string" then work.Workers[nurseId] else nil
	if not work or not w or not w.Alive or not w.Claimed or typeof(to) ~= "CFrame" then
		return false
	end
	w.Escort += 1
	local token = w.Escort
	w.ClaimedAt = os.clock()
	w.Busy = true
	resync(w)
	NurseBuilder.setTask(w.Model, "Escorting")
	-- Patients may give up waiting (a timeout) and release it mid-walk: the walk then stops at its next hop.
	local walked, arrived = pcall(walkTo, work, w, to, true, function(): boolean
		return w.Claimed and w.Escort == token
	end)
	if w.Escort == token then
		w.Busy = false
	end
	if not walked then
		report("an escort", arrived)
		return false
	end
	w.ClaimedAt = os.clock()
	return arrived == true and w.Alive and w.Claimed and work.Workers[nurseId] == w
end

function Nurses.releasePorter(plotArg: any, nurseId: string)
	local work = workOf(plotArg)
	local w = if work and type(nurseId) == "string" then work.Workers[nurseId] else nil
	if not work or not w or not w.Claimed then
		return
	end
	w.Claimed = false -- a walk still hopping stops at its next hop; the loop waits for it to land (Busy)
	if not w.Busy then
		resync(w)
	end
	w.RestUntil = os.clock() + everyFor(work, w)
	NurseBuilder.setTask(w.Model, "Idle")
	if w.Retask then
		w.Retask = false
		sync(work.Owner)
	end
end

------------------------------------------------------------------------------------------------------------------
-- Admin hooks
------------------------------------------------------------------------------------------------------------------

-- Admin "NurseLevels": +1 level for every nurse you own (each to its cap), keeping its partial XP.
function Nurses.adminLevels(player: Player): (boolean, string)
	if not isPlayer(player) or not PlayerData.get(player) then
		return false, Remotes.OOPS
	end
	local ups: { LevelUp } = {}
	PlayerData.update(player, function(d)
		local cap = NurseLogic.levelCap(rebirthsOf(d), Config)
		for nurseId, entry in d.Nurses do
			if knownNurse(nurseId) and type(entry) == "table" then
				local from = Pure.level(entry, maxLevel())
				if from < cap then
					local out, gained = NurseLogic.addXP(entry, NurseLogic.xpToNext(from), cap)
					d.Nurses[nurseId] = out
					if gained > 0 then
						table.insert(ups, { NurseId = nurseId, From = from, To = out.Level })
					end
				end
			end
		end
	end)
	announceLevels(player, ups, true)
	if #ups == 0 then
		return false, "Max level!"
	end
	return true, "⬆️ Nurses +1 level!"
end

-- Admin "GiveNurse": a free grant (the roster rules apply)
function Nurses.adminGive(player: Player, nurseId: string): (boolean, string)
	return Nurses.grant(player, nurseId, 0, "Admin")
end

------------------------------------------------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------------------------------------------------

function Nurses.start()
	for _, plot in Plots.all() do
		ensureFolder(plot)
		resetPlot(plot)
		plot.Model:GetAttributeChangedSignal(TRAY_ATTRIBUTE):Connect(function()
			showTray(plot)
		end)
	end

	Remotes.serve("SetJob", onSetJob)

	Plots.PlotAssigned:Connect(function(owner: Player, plot: Plot)
		activate(owner, plot)
	end)
	Plots.PlotReleased:Connect(function(_owner: Player, plot: Plot)
		deactivate(plot)
	end)
	-- Any save change (a hire, a level-up, a copy, a job, a sale, a rebirth): the plot's nurses follow (sync diffs),
	-- and room made by a sale or a rebirth wakes a resting nurse.
	PlayerData.Changed:Connect(function(player: Player, data: any)
		sync(player)
		queueWake(player, data)
	end)
	Levels.LevelChanged:Connect(function(player: Player)
		sync(player)
	end)

	-- A complete journal group whose reward is missing gets it now (quietly). Idempotent.
	local function repair(player: Player, data: Types.Data)
		if #NurseLogic.setsDue(data.NurseIndex, NursesData, Rarities, data.JournalSets) > 0 then
			PlayerData.update(player, function(d)
				grantSets(d)
			end)
		end
		queueWake(player, data)
	end
	PlayerData.Loaded:Connect(repair)

	Players.PlayerRemoving:Connect(function(player: Player)
		listed[player] = nil -- a seller who leaves takes their listings (the Market drops them too)
		restoring[player] = nil
		lastSetJob[player] = nil
		wakeQueued[player] = nil
	end)

	for _, plot in Plots.all() do
		local owner = plot.Owner
		if owner then
			activate(owner, plot) -- plots handed out before Nurses started
		end
	end
	for _, player in Players:GetPlayers() do
		local data = PlayerData.get(player)
		if data then
			task.spawn(repair, player, data)
		end
	end
end

return Nurses
