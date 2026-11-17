--!strict
-- Patients: the line of creatures at every clinic, the Treat prompt on the Counter, beds and the cure
-- (build plan §B5 "Patients", Task 1). Server only. API: Patients.start().
-- For the 🛠️ Admin panel only (Server/Admin checks the caller is an admin):
--   Patients.sendNext(owner, patientId): (ok, message)   that Data/Patients patient comes next at the owner's clinic
--       (before the usual pick and whatever the tutorial's plan says) once there's room in line; up to
--       Config.MaxQueue picks wait their turn. Refused when no station on the plot can treat it.
--   Patients.reopen(owner): boolean   empties the owner's clinic and opens it again, as on a fresh join (a patient
--       already treated is cured on the spot first, exactly as when an owner leaves)
--   Progression v2 (build plan §B8, §C T7; OWNER: T7):
--   Patients.adminAmbulance(owner): (ok, message)    an ambulance as soon as the line has room (Lv 2+)
--   Patients.adminHelicopter(owner): (ok, message)   an air ambulance as soon as the line has room (Lv 5; no R2)
--
-- Progression v2: Hospital v2's patients (design §6; build plan §B3/§B4/§C T7, §E6-E8, §E11). In short:
--   · 🚑 A&E (Lv 2+). About every Config.AE.EverySeconds (±Jitter, x (1 - 0.1 x A&E Speed), / Siren Pro; the first
--     FirstSeconds after the clinic reaches Lv 2), only while the owner stands at their clinic, is done with the
--     tutorial, the line has room (Config.MaxQueue still holds) and no other 🚑/🚁 patient waits: the parked
--     Ambulance's ArriveAt is set (Feel/HospitalFX flashes it) and an urgent patient pops out at its StretcherSpot
--     and goes to the FRONT of the line (behind anyone already being treated). Urgent = "AE", a 2-3 item recipe
--     (Logic/Hospital.urgentRecipe; an item no station here makes is left out), patience x AE.PatienceMultiplier x
--     (1 + 0.15 x A&E Speed), draining slower with the A&E team (TeamUrgent) and a Medic (Nurses.medic); it pays
--     x3 + 2 ⭐ (Cure). A 🚑 chip and an orange rim on its badge (CreatureBuilder.setUrgent).
--   · 🚁 Air ambulance (Lv 5 builds the helipad; it flies only from R2, §E11). Every Config.VIP.EverySeconds
--     (±Jitter): HeliSpot's ArriveAt is set (HospitalFX flies a client-only helicopter in), and HELI_LAND_SECONDS
--     later a Sky-wing patient steps out on the roof, rides the lift down (Lift.carry) and joins the line at the
--     front. Urgent = "VIP": x4 + 3 ⭐. Sky-wing patients come no other way.
--   · After the recipe is complete: its department (Logic/Hospital.route: 🛁 Hydro for a Bath-wing patient once
--     Hydro is open, else 🛏️ Wards; the badge's chip from Lv 3, CreatureBuilder.setDept). Where it rests
--     (Pure.destination): a Hydro patient takes a free hot-tub spot first; otherwise a free bed on the ground (the
--     Stand's, a room's), else a ward bed upstairs, else it rests in place at the front of the line, as before. From
--     Lv 3, when it really goes to its department's floor (Pure.routed: a Hydro patient to a tub, a Wards patient up
--     to a ward bed), the helper picks the floor (Treatment.waitTriage, at most Config.Triage.Seconds: a right pick
--     is +10%; a wrong one says "Oops, not this floor!" and it goes the right way anyway; no pick: it goes by itself)
--     while it stands aside and the line moves up. A Receptionist on duty (Nurses.reception) sends it at once, with
--     the bonus; so does Simple mode (no timed decision). A ground bed: no question, no bonus.
--   · Upstairs (a ward bed or the tub): it waits at the ground landing ("ToLift") for a Porter (Nurses.claimPorter,
--     who walks over: Nurses.escort) or, only when someone who can work here stands near the landing, a player
--     (Lift.waitEscort: the landing's EscortPrompt, Config.Lift.EscortWait s); either rides with it (Escorted: +20%
--     cash, rest x0.5); nobody: it rides alone. Then its turn on the lift (held for the ride only). Lift.carry moves
--     everyone with one PivotTo each at the far landing (one ride at a time per plot). After the cure it rides down.
--   · 🛁 Hydro: in a tub spot it is "Soaking" (+25% cash, rest x0.5) and the tub's SoakPrompt opens ONE 🫧 Scrub game
--     for it (Treatment.open Kind "Soak": a tip only, sharing the patient's TipCapPerCure). It soaks a little longer
--     (SOAK_LINGER) after its cure while nobody has played it, so the game can be reached.
--   · Rest seconds (Logic/Hospital.recover): Config.RecoverSeconds x escort x tub x (1 - 0.2 x Ward Comfort) x
--     TeamRecover. The cure's Extra (Logic/Pay, at most Pay.MAX_EXTRA): escort x tub x right triage x TeamCash x
--     (1 + 0.05 x Ward Comfort).
--   · 👯 Twin Counters (the owner's capstone, §E6): the Treat prompt serves the first of the TWO front patients whose
--     missing items you carry (else the first the nurse tray fits); Healers may serve #2 too; FrontNeeds covers both.
--     Still one mini-game card at a time per player.
--   · Medicines (Lv 4 Pharmacy): a carried medicine fills every missing slot its two ingredients cover, as ONE 🧪
--     Pour game (Logic/Recipe.match with Data/Items).
--   · Abilities (Abilities.Fired): RefillFront (the front waiting patient's patience full), RefillLine (everyone
--     waiting), PauseLine (no patience drains; also Abilities.patiencePaused), CureLine (Miracle: every waiting
--     patient cures on the spot through the usual Cure.resolve, the owner as helper, no tip). Medics (Nurses.Heal
--     target "Urgent") give the 🚑/🚁 patient tray items, rated OK.
--   · Perks and unlocks: 🚪 Busy Doors and a Receptionist shorten the arrival seconds (Logic/Hospital.arrival); 🦉
--     Night Owl brings night patients for Config.NightOwl of a night after morning; 🌻 Sunny-wing patients come from
--     R1 (Data/Wings Rebirths), using whatever stations you have; 🌟 Golden patients (Data/Variants, from R3) at
--     Config.GoldenChance with a gold sheen (CreatureBuilder.setEffect "Golden").
--   · Studio test switch: workspace:SetAttribute("ForceGoldenPatient", true): every new patient at an R3+ clinic is
--     Golden. A live server ignores it.
--   · Kids' rules: none of it is ever needed to cure (no fail states), and nothing counts down on screen.
--   Patient attributes (§B4): Urgent ("" | "AE" | "VIP"), Dept ("Wards" | "Hydro"), Escorted, and State gains
--   "Triage", "ToLift", "Riding", "Soaking".
--
-- A visit, step by step:
--   1. Arrive. Each owned plot gets a patient every few seconds (the owner's hospital level: Levels.spawnSeconds,
--      13 s at Lv 1 down to 8 s at Lv 5) while fewer than Config.MaxQueue (3: the one being treated + 2 waiting)
--      are in line; no level makes the line longer (Levels.queueCap is capped by it), a higher level only refills
--      it sooner. Who comes, in order: a regular whose story beat is due
--      (Story.dueRegular, with a speech bubble from Story.bubble), Today's Visitor (Daily.visitorFor, a ⭐ on the
--      badge), otherwise a patient whose ailment's station is on the plot. Night patients only come at night (and
--      are likelier then), Winter patients need the Winter Wing, and new Book pages are likelier. Variants: Sparkly
--      at Config.SparklyChance, Frosty at Config.FrostyChance while Workspace.IsWinter (never on regulars).
--      Regulars and the visitor wait longer (GuestPatienceMultiplier). Night-wing regulars count as night patients
--      (glow, ctx.Night).
--      Recipes (depth update §1): each patient needs its ailment's Recipe (a regular: its own), cut to the owner's
--      level (Levels.recipeCap via Logic/Recipe.effective; always 1 item while the owner is in the tutorial). Only
--      patients whose recipe the plot's stations can make come (Recipe.makeable).
--   2. Wait in line in front of the Counter, on the plot's QueueLane (each place from PlotBuilder.queueSpot).
--      Patience (Prices.patience with the owner's Comfy Chairs level, times the owner's Patience boosts from
--      Server/Boosts) drains while a patient stands in line: full speed at the front, slower behind, and slower
--      still with a Cheerer on duty (the plot's CheerPatience divides the drain). When it runs out the patient
--      leaves with a sad puff (a regular: Story.left, so they come back later). No penalty, ever.
--   3. Treat. The `TreatPrompt` on the Counter treats the front patient: Plots.canWork, then the recipe items it
--      still needs that the helper carries (Recipe.match on Carry first, then the plot's nurse tray via
--      Nurses.takeFromTray). None: a head-shake and a toast with the next missing item's station icon. Otherwise
--      they're taken (spent now), the patient is "Treating" (patience paused, nobody else can treat it) and
--      Server/Treatment runs the mini-games (TreatStart -> TreatResult or its timeout). When it settles, the items
--      count as given, each adds Config.Treat.ItemPatience of its patience back and the badge ticks them off. The
--      recipe complete: on to 4. Not yet: back to waiting for the rest (a tray of 1 gives one item per trip).
--      Healer nurses (Nurses.Heal via Treatment.onHeal) give the front patient what the nurse tray holds for it
--      the same way, rated OK, with no tip and no combo.
--   4. Recover. The patient hops to a free Bed_<n> on the plot (under Rooms or the level's Building, nearest the
--      Counter first). With every bed taken it rests in place at the front of the line, so the line waits: more
--      beds = a faster clinic. After Config.RecoverSeconds: Cure.resolve(ctx), a happy spin, and it hops out.
--   5. Cleanup. Plots.PlotReleased (the owner left) removes every patient on that plot right away, before
--      Plots clears the plot. A patient already treated (its items spent) is cured on the spot first, so a helper
--      never loses their work; one mid-mini-game is cured too if those items finish its recipe, otherwise the
--      helper gets their carried items back (Treatment.drop closes the session). Nothing on the plot errors, and
--      the plot is clean for the next owner.
--
-- The first-session tutorial (Server/Tutorial, by the OWNER's step). Nothing here changes for an owner who's done.
--   · Who comes (Tutorial.spawnPlan): nobody during the welcome; then one easy first patient (a Starter patient
--     needing the 🧪 Remedy); then one Starter patient needing 🩹; then the usual pool. Never a regular or Today's
--     Visitor until the tutorial is done. No variants on the two tutorial patients.
--   · One at a time in line through step 6 (Tutorial.queueCap). A spawn that's held back doesn't use up the timer,
--     so the first patient comes the moment step 2 starts.
--   · Patience never runs out in steps 1-6 (Tutorial.calm): the ring stays full.
--   · Hooks: Tutorial.onFrontArrived when a patient reaches the front of the line, Tutorial.onTreated when its
--     recipe is complete (after the mini-game).
--   · Recipes stay 1 item for the owner's whole tutorial, whatever their level.
--
-- Movement: no Humanoids, no physics. A creature is one anchored Root with its parts welded on
-- (CreatureBuilder). The server never moves a creature every frame (build plan §B4, the creature motion contract):
-- each hop, shake, droop and grow/shrink sets attributes once (CreatureBuilder.hop/shake/tilt/scale) and every
-- client draws the in-between (Feel/CreatureMotion). The server writes the end pose once as each one lands
-- (Root.CFrame = the hop's end; Model:ScaleTo the end scale), so late joiners and its own checks see the right
-- place. Each patient has one thread for its whole visit; the prompt and the patience tick only change its State.
--
-- For the client (read-only, the server sets them):
--   patient Model (in Plot.Patients): attributes PatientId, Kind ("Patient"|"Regular"|"Visitor"), Regular
--     (RegularId or nil), Ailment, Variant (nil = none), Night, QueueIndex (1 = front, 0 = out),
--     State ("Arriving"|"Waiting"|"Treating"|"Treated"|"Recovering"|"Cured"|"Sad"), PatienceFraction (0..1 in 0.05
--     steps, set only when it changes: Feel/CreatureActing makes a patient wave, then bounce with a "!", as it runs
--     low), Recipe (the effective recipe, comma-joined ItemIds), RecipeDone ("1" given / "0" not, one per item),
--     Item and Station (the FIRST item still missing and its station; they keep their last value once complete).
--     The badge shows the recipe (CreatureBuilder.setRecipe after every change).
--   plot Model: attributes FrontItem and FrontStation, the ItemId / StationId the front patient needs first while
--     it waits to be treated ("" otherwise; the Guide arrow follows these), FrontNeeds (every item that patient
--     still needs, comma-joined) and QueueNeeds (every missing item of everyone in line, front first, duplicates
--     kept; items in a mini-game right now don't count). Nurse Makers read these.
--   Counter.TreatAttachment.TreatPrompt: enabled only while a front patient waits; ObjectText = its ailment icon.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Palette = require(Shared.Palette)
local Hospital = require(Shared.Logic.Hospital)
local Pay = require(Shared.Logic.Pay)
local Prices = require(Shared.Logic.Prices)
local Recipe = require(Shared.Logic.Recipe)
local RebirthLogic = require(Shared.Logic.Rebirth)
local AilmentsData = require(Shared.Data.Ailments)
local ItemsData = require(Shared.Data.Items)
local LevelsData = require(Shared.Data.Levels)
local PatientsData = require(Shared.Data.Patients)
local PerksData = require(Shared.Data.Perks)
local RegularsData = require(Shared.Data.Regulars)
local StationsData = require(Shared.Data.Stations)
local TreeData = require(Shared.Data.Tree)
local VariantsData = require(Shared.Data.Variants)
local WingsData = require(Shared.Data.Wings)

local Abilities = require(script.Parent.Abilities)
local Carry = require(script.Parent.Carry)
local CreatureBuilder = require(script.Parent.CreatureBuilder)
local Cure = require(script.Parent.Cure)
local Daily = require(script.Parent.Daily)
local Levels = require(script.Parent.Levels)
local Lift = require(script.Parent.Lift)
local Nurses = require(script.Parent.Nurses)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)
local PlotBuilder = require(script.Parent.PlotBuilder) -- queueSpot: shared with the queue lane's numbered spots
local Story = require(script.Parent.Story)
local Treatment = require(script.Parent.Treatment)
local Tutorial = require(script.Parent.Tutorial)
local Boosts = require(script.Parent.Boosts) -- playtime branch: the owner's Patience boosts

type Plot = Types.Plot
type Badge = CreatureBuilder.Badge

local Patients = {}

------------------------------------------------------------------------------------------------------------------
-- Tuning
------------------------------------------------------------------------------------------------------------------

-- Optional Config keys (these defaults apply until Config has them).
local Tuning = Config :: any
local QUEUE_PATIENCE_RATE: number = tonumber(Tuning.QueuePatienceRate) or 0.5 -- drain behind the front
local GUEST_PATIENCE: number = tonumber(Tuning.GuestPatienceMultiplier) or 1.5 -- regulars and Today's Visitor
local FIRST_PATIENT_SECONDS: number = tonumber(Tuning.FirstPatientSeconds) or 2 -- after you get your plot

local TICK = 0.2 -- patience, spawning and the recovery ring update this often
local REFILL_SECONDS = 2 -- a freed place in line is refilled no sooner than this
local NIGHT_WEIGHT = 3 -- night patients are this much likelier at night
local NEW_PAGE_WEIGHT = 2.5 -- patients not yet in the owner's Book are likelier
local REPEAT_WEIGHT = 0.35 -- the same patient twice in a row is less likely
-- The tutorial's two patients: a Starter-wing day patient whose ailment this station treats.
local TUTORIAL_STATION: { [string]: string } = { First = "Remedy", Second = "Plaster" }
local TUTORIAL_WING = "Starter"

local PROMPT_DISTANCE = 10
local DISTANCE_SLACK = 6 -- lag allowance on the server's own distance check
local TREAT_COOLDOWN = 0.3 -- per player
local MAX_CHEER_PATIENCE = 3 -- a sanity cap on the plot's CheerPatience (Cheerers give at most ~1.5)
local MAX_CHEER_TIP = 3 -- and on its CheerTip (the cure's cash, Logic/Pay)
local ITEM_PATIENCE = Config.Treat.ItemPatience -- each recipe item given refills this share of the patience

-- Feel
local HOP_LENGTH = 3.6
local HOP_SECONDS = 0.3
local HOP_HEIGHT = 0.9
local LEAN = 0.14 -- radians forward at the top of a hop
local RING_STEPS = 48 -- the ring moves in 7.5 degree steps, so it replicates a few times a second at most
local PATIENCE_STEPS = 20 -- the PatienceFraction attribute moves in 0.05 steps (about 20 changes in a whole wait)

-- The patience ring, candy pop (memory-20261116-007): bright green, then yellow, then red; pink while healing.
local RING_CALM = Palette.Candy.Lime
local RING_HURRY = Palette.Candy.Yellow
local RING_LOW = Palette.Candy.Red
local RING_HEAL = Palette.Candy.Pink

local ICON_TREATED = "💗"
local ICON_SLEEP = "💤"
local ICON_CURED = "🥰"
local ICON_SAD = "😔"
local ICON_SOAK = "🫧"

-- Progression v2: Hospital v2 (every rule's number is in Config: AE, VIP, Triage, Escort, Hydro, Lift, WardComfort,
-- AESpeed, GoldenChance; these are feel and safety only)
local AE_LEVEL = 2 -- Data/Departments.AE.Opens: ambulances come from this hospital level
local HELI_LEVEL = 5 -- Data/Departments.Roof.Opens: the helipad
local HELI_LAND_SECONDS = 3.5 -- the helicopter lands first (Feel/HospitalFX: HELI_IN 3.2 s), then out steps its VIP
local PLOT_MARGIN = 6 -- studs past the plot's edge that still count as the owner being at their clinic
local POLL = 0.1 -- waiting on another system (the lift, a porter) looks this often
local PORTER_SECONDS = 15 -- the most a patient waits for a Porter to walk over
local CARRY_SECONDS = 8 -- the most a lift ride may take before the patient is put there anyway
local ESCORT_SLACK = 2 -- seconds on top of Config.Lift.EscortWait before giving up on Lift.waitEscort
local TRIAGE_STEP = 2.5 -- studs a patient steps aside while its floor is picked (the next one takes its place)
local ESCORT_NEAR = 24 -- studs from the ground landing a worker must be for an upstairs patient to wait for an escort
local SOAK_LINGER = 6 -- a Hydro patient soaks this much longer after its cure while its 🫧 game is unplayed
local SOAK_DISTANCE = 14 -- studs from the SoakPrompt the server accepts (its own check, beside the prompt's)
local MAX_SLOWER = 4 -- a sanity cap on how much slower an urgent patient's patience may drain
local MAX_FORCED_URGENT = 3 -- admin calls waiting at once

------------------------------------------------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------------------------------------------------

type ScaleAnim = {
	From: number,
	To: number,
	Start: number,
	Seconds: number,
	Style: Enum.EasingStyle,
	Direction: Enum.EasingDirection,
}

-- Walkways in plot-local space (x right as you face the street, -z toward the street).
type Nav = {
	Pivot: CFrame,
	LaneZ: number, -- the front of the line: sideways moves happen along this z
	SideStep: number, -- |x| that clears the Counter
	StandHalf: number, -- the Stand's half width
	StandBack: number, -- z of the Stand's back edge
	BackZ: number, -- the lane behind the Stand
	Left: number, -- |x| of the walkway between the Stand and the rooms on each side
	Right: number,
}

type PlotState = {
	Plot: Plot,
	Owner: Player,
	Active: boolean,
	Queue: { Patient }, -- in line, front first (a patient resting in place stays at the front)
	All: { [Patient]: boolean },
	Beds: { [BasePart]: Patient },
	Nav: Nav,
	Ray: RaycastParams,
	Prompt: ProximityPrompt,
	NextSpawn: number,
	Spawned: number,
	LastPatient: string?,
	FrontItem: string,
	FrontNeeds: string,
	QueueNeeds: string,
	Loop: thread?,
	SecondSpawned: boolean, -- the tutorial's 🩹 patient came this session
	Forced: { string }, -- the admin panel's picks (Patients.sendNext), first come first
	-- Progression v2
	FloorRay: RaycastParams, -- the building's slabs and the plot's Ground (standing on a floor)
	Level: number, -- the owner's hospital level (refreshed every tick)
	Rebirths: number, -- the owner's Rebirth.Count (refreshed every tick)
	Effects: Effects, -- the owner's perks + tree that patients use (refreshed every tick)
	Team: { Cash: number, Recover: number, Urgent: number }, -- Nurses.team (refreshed every tick)
	Medic: number, -- Nurses.medic(plot).Patience (refreshed every tick)
	Receptionist: { Arrive: number, Triage: boolean }, -- Nurses.reception (refreshed every tick)
	NextAE: number, -- os.clock() of the next ambulance
	NextVIP: number, -- os.clock() of the next air ambulance
	ForceUrgent: { string }, -- the admin panel's calls ("AE" | "VIP"), first come first
	Incoming: number, -- urgent patients on their way to the line (a VIP on the roof or in the lift)
	PausedUntil: number, -- os.clock(): a Calm Song pauses every patience ring until then
	LiftBusy: boolean, -- one ride at a time on this plot's lift
}

-- The owner's perks and tree as patients use them (Logic/Rebirth.effects, cleaned)
type Effects = { Arrive: number, SirenPro: number, NightOwl: boolean, TwinCounters: boolean }

type Patient = {
	Plot: PlotState,
	PatientId: string,
	Regular: string?,
	Visitor: boolean,
	Variant: string?,
	Night: boolean,
	AilmentIcon: string,
	Station: string, -- the first missing item's station
	Item: string, -- the first missing item
	Recipe: { string }, -- the effective recipe (cut by the owner's level)
	Done: { boolean }, -- one per recipe item: given
	TipPaid: number, -- mini-game tip cash paid on this patient so far (capped per cure)
	Session: number?, -- an open Treatment session on it ("Treating")
	SessionHelper: Player?,
	SessionIndices: { number }?, -- the recipe slots that session gives
	SessionCarried: { string }?, -- what it took from the helper's own tray (given back if the session is dropped)
	Model: Model,
	Root: BasePart,
	Badge: Badge,
	BaseScale: number,
	HopHeight: number,
	HopSeconds: number,
	-- "Queue" | "Treated" | "Recovering" | "Cured" | "Sad" | "Gone"
	State: string,
	Arrived: boolean, -- standing in its place in line
	Claimed: boolean, -- a Treat is being checked right now
	Patience: number,
	PatienceMax: number,
	PatienceLeft: number, -- 0..1, frozen when treated (Cure ctx)
	PatienceShown: number, -- the PatienceFraction attribute
	RingStep: number,
	RingColor: Color3?,
	NextIdle: number,
	Helper: Player?,
	Bed: BasePart?,
	InBed: boolean,
	Pivot: CFrame, -- where the creature rests between hops (its bottom centre)
	ScaleAnim: ScaleAnim?, -- the grow/shrink the clients are drawing (so the next one starts where it is)
	Tilt: number,
	Thread: thread?,
	-- Progression v2
	Wing: string, -- its Book wing (Data/Wings)
	Urgent: string, -- "" | "AE" | "VIP"
	Incoming: boolean, -- a VIP not in the line yet (on the roof, or riding down)
	ArriveFloor: number, -- a VIP: the roof's floor number
	Dept: string, -- where it recovers: "Wards" | "Hydro" (Logic/Hospital.route)
	SpotKind: string, -- "Ground" | "Upstairs" | "Tub" | "Place" (its Bed, or none: it rests where it stands)
	Floor: number, -- its spot's floor (0 = the ground)
	Upstairs: boolean, -- standing on a floor above the ground right now
	Escorted: boolean, -- rode the lift with a Porter or a player (+20% cash, rest x0.5)
	Porter: string?, -- the Porter claimed for it (released when it's done or gone)
	HasLift: boolean, -- it holds this plot's lift turn
	Triage: { Helper: Player, Session: number, Options: { string }, Right: string }?, -- a floor pick to wait for
	TriageBonus: boolean, -- a right pick (or a Receptionist): +10%
	RecoverIn: string, -- the department it recovered in, for nurse XP: "Reception" | "Wards" | "Hydro"
	Soaking: boolean, -- in a hot-tub spot (its 🫧 game can be played)
	SoakDone: boolean, -- its 🫧 game was played
	SoakSession: number?, -- the open Soak session on it
}

-- An urgent patient's arrival (spawnPatient)
type UrgentSpawn = { Kind: string, Recipe: { string }, Start: CFrame, Air: boolean, Floor: number }

-- What one treat would give one front patient (onTreat; Pure.plan)
type TreatPlan = {
	Carry: number,
	Tray: number,
	CarryIdx: { number },
	TrayIdx: { number },
	CarryUsed: { string },
	TrayUsed: { string },
}

local active: { [Plot]: PlotState } = {}
local prompts: { [Plot]: ProximityPrompt } = {}
local lastTreat: { [Player]: number } = {}
local rng = Random.new()
local nightEndedAt = -math.huge -- os.clock() the last in-game night ended (🦉 Night Owl)
local soakWired: { [ProximityPrompt]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local NEUTRAL_EFFECTS: Effects = { Arrive = 1, SirenPro = 1, NightOwl = false, TwinCounters = false }

local deactivate: (plot: Plot) -> () -- defined further down

------------------------------------------------------------------------------------------------------------------
-- Safety: other systems are called through pcall, so a bug elsewhere never breaks a patient
------------------------------------------------------------------------------------------------------------------

local failures: { [string]: number } = {}
local function report(label: string, err: any)
	local count = (failures[label] or 0) + 1
	failures[label] = count
	if count <= 3 then
		warn("[Patients] " .. label .. " failed: " .. tostring(err))
	end
end

local function carrying(player: Player): { string }
	local ok, items = pcall(Carry.items, player)
	if not ok then
		report("Carry.items", items)
		return {}
	end
	return if type(items) == "table" then items else {}
end

local function takeItem(player: Player, itemId: string): boolean
	local ok, taken = pcall(Carry.take, player, itemId)
	if not ok then
		report("Carry.take", taken)
		return false
	end
	return taken == true
end

local function giveBack(player: Player, itemId: string)
	local ok, err = pcall(Carry.add, player, itemId)
	if not ok then
		report("Carry.add", err)
	end
end

local function trayItems(plot: Plot): { string }
	local ok, items = pcall(Nurses.trayItems, plot)
	if not ok then
		report("Nurses.trayItems", items)
		return {}
	end
	return if type(items) == "table" then items else {}
end

local function takeFromTray(plot: Plot, itemId: string): boolean
	local ok, taken = pcall(Nurses.takeFromTray, plot, itemId)
	if not ok then
		report("Nurses.takeFromTray", taken)
		return false
	end
	return taken == true
end

-- Asks Server/Levels for one of the owner's numbers (queueCap, recipeCap); `fallback` on a bug.
local function levelAsk(name: string, owner: Player, fallback: number): number
	local fn = (Levels :: any)[name]
	local ok, value = pcall(fn, owner)
	if not ok then
		report("Levels." .. name, value)
		return fallback
	end
	return if type(value) == "number" and value == value and value >= 1 then math.floor(value) else fallback
end

-- Calls a Server/Tutorial hook; a tutorial bug never breaks a patient.
local function tutorialHook(name: string, ...: any)
	local fn = (Tutorial :: any)[name]
	local ok, err = pcall(fn, ...)
	if not ok then
		report("Tutorial." .. name, err)
	end
end

-- Asks Server/Tutorial something; on a tutorial bug the answer is `fallback` (the normal game).
local function tutorialAsk(name: string, fallback: any, ...: any): any
	local fn = (Tutorial :: any)[name]
	local ok, answer = pcall(fn, ...)
	if not ok then
		report("Tutorial." .. name, answer)
		return fallback
	end
	return answer
end

local function cancel(thread: thread?)
	if thread and thread ~= coroutine.running() and coroutine.status(thread) == "suspended" then
		task.cancel(thread)
	end
end

-- Runs fn(...) on its own thread and waits for it at most `timeout` seconds, so a bug elsewhere (a porter that never
-- arrives, a ride that never ends) never holds a patient, or this plot's lift, forever. Returns (finished, result).
local function within(timeout: number, label: string, fn: any, ...: any): (boolean, any)
	local args = table.pack(...)
	local finished, result = false, nil
	task.spawn(function()
		local ok, value = pcall(fn, table.unpack(args, 1, args.n))
		if ok then
			result = value
		else
			report(label, value)
		end
		finished = true
	end)
	local deadline = os.clock() + timeout
	while not finished and os.clock() < deadline do
		task.wait(POLL)
	end
	return finished, result
end

-- A number from another system: finite and clamped, junk -> `fallback`.
local function clampNumber(value: any, low: number, high: number, fallback: number): number
	if type(value) ~= "number" or value ~= value then
		return fallback
	end
	return math.clamp(value, low, high)
end

-- That floor's landing in front of the lift door (Lift.landing; nil without a lift).
local function landingOf(plot: Plot, floor: number): CFrame?
	local ok, cf = pcall(Lift.landing, plot, floor)
	if not ok then
		report("Lift.landing", cf)
		return nil
	end
	return if typeof(cf) == "CFrame" then cf else nil
end

-- The plot's team bonuses (Nurses.team): factors, 1 = none.
local function teamOf(plot: Plot): { Cash: number, Recover: number, Urgent: number }
	local ok, team = pcall(Nurses.team, plot)
	if not ok then
		report("Nurses.team", team)
	end
	local t: any = if ok and type(team) == "table" then team else {}
	return {
		Cash = clampNumber(t.Cash, 1, Pay.MAX_EXTRA, 1),
		Recover = clampNumber(t.Recover, 0.05, 1, 1),
		Urgent = clampNumber(t.Urgent, 1, MAX_SLOWER, 1),
	}
end

-- The best Receptionist on duty (Nurses.reception): patients come Arrive x as often; Triage = it sends them at once.
local function receptionOf(plot: Plot): { Arrive: number, Triage: boolean }
	local ok, reception = pcall(Nurses.reception, plot)
	if not ok then
		report("Nurses.reception", reception)
	end
	local r: any = if ok and type(reception) == "table" then reception else {}
	return { Arrive = clampNumber(r.Arrive, 0.2, 1, 1), Triage = r.Triage == true }
end

-- The best Medic on duty (Nurses.medic): urgent patients' patience drains this much slower (1 = none).
local function medicOf(plot: Plot): number
	local ok, medic = pcall(Nurses.medic, plot)
	if not ok then
		report("Nurses.medic", medic)
	end
	return clampNumber(if ok and type(medic) == "table" then (medic :: any).Patience else nil, 1, MAX_SLOWER, 1)
end

-- A Calm Song is pausing every patience ring at this plot (Abilities.patiencePaused).
local function abilityPaused(plot: Plot): boolean
	local ok, paused = pcall(Abilities.patiencePaused, plot)
	if not ok then
		report("Abilities.patiencePaused", paused)
		return false
	end
	return paused == true
end

-- The owner's perks and tree, as patients use them (Logic/Rebirth.effects on the live save).
local function effectsOf(owner: Player): Effects
	local data = PlayerData.get(owner)
	if not data then
		return NEUTRAL_EFFECTS
	end
	local ok, effects = pcall(RebirthLogic.effects, data, Config, PerksData, TreeData)
	if not ok or type(effects) ~= "table" then
		if not ok then
			report("Rebirth.effects", effects)
		end
		return NEUTRAL_EFFECTS
	end
	local e: any = effects
	return {
		Arrive = clampNumber(e.Arrive, 0.2, 1, 1),
		SirenPro = clampNumber(e.SirenPro, 1, 4, 1),
		NightOwl = e.NightOwl == true,
		TwinCounters = e.TwinCounters == true,
	}
end

-- The owner's rebirths (Data.Rebirth.Count; 0 before any).
local function rebirthsOf(owner: Player): number
	local data = PlayerData.get(owner)
	local rebirth = if data then (data :: any).Rebirth else nil
	return math.floor(clampNumber(if type(rebirth) == "table" then rebirth.Count else nil, 0, 1e6, 0))
end

local function alive(p: Patient): boolean
	return p.State ~= "Gone" and p.Plot.Active
end

local function sleep(p: Patient, seconds: number): boolean
	task.wait(seconds)
	return alive(p)
end

------------------------------------------------------------------------------------------------------------------
-- Pure helpers for recipes at the Counter (no Roblox services; a scratch Lune harness loads this block on its own,
-- with Logic/Recipe as `Recipe`)
------------------------------------------------------------------------------------------------------------------

-- PURE-BEGIN
-- (Progression v2 additions use `Hospital` = Logic/Hospital as well; a harness passes both.)
local Pure = {}

-- What one treat gives: the recipe slots the helper's own items fill, then the ones the nurse tray fills (each in
-- recipe order; each item used once). Carry first, so a kid's own making always counts. With `medicines`
-- (Data/Items), a carried medicine fills every missing slot its two ingredients cover (Logic/Recipe.match).
-- Also returns the items each side spends (one mini-game each: a medicine is one game for two slots).
function Pure.plan(
	recipe: { string },
	done: { boolean },
	carried: { string },
	tray: { string },
	medicines: any?
): ({ number }, { number }, { string }, { string })
	local fromCarry, carryUsed = Recipe.match(recipe, done, carried, medicines)
	local fromTray, trayUsed = Recipe.match(recipe, Recipe.apply(done, fromCarry), tray, medicines)
	return fromCarry, fromTray, carryUsed, trayUsed
end

-- 👯 Twin Counters: which of the front patients a treat serves, from each one's plan ({ Carry = slots the helper's
-- items fill, Tray = slots the nurse tray fills }, in line order): the first whose missing items you carry, else
-- the first the tray fits; nil = nothing fits anyone.
function Pure.pickTwin(plans: { { Carry: number, Tray: number } }): number?
	for index, plan in plans do
		if plan.Carry > 0 then
			return index
		end
	end
	for index, plan in plans do
		if plan.Tray > 0 then
			return index
		end
	end
	return nil
end

-- Where an urgent patient joins the line: in front of the first patient still waiting to be treated, so whoever is
-- mid-mini-game or resting at the front keeps its place. `busy` = one flag per place in line, front first.
function Pure.urgentPlace(busy: { boolean }): number
	for index, isBusy in busy do
		if not isBusy then
			return index
		end
	end
	return #busy + 1
end

-- Where a treated patient rests: "Tub" (a hot-tub spot), "Ground" (a bed on the ground: the Stand's, a room's),
-- "Upstairs" (a ward bed up the lift) or "Place" (where it stands: the line waits, as before). A Hydro patient takes
-- a free tub first; nobody else uses a tub.
function Pure.destination(dept: string, free: { Tub: boolean?, Ground: boolean?, Upstairs: boolean? }): string
	if dept == "Hydro" and free.Tub then
		return "Tub"
	elseif free.Ground then
		return "Ground"
	elseif free.Upstairs then
		return "Upstairs"
	end
	return "Place"
end

-- The patient really goes to its department's own floor: a Hydro patient into a 🛁 tub spot, a Wards patient up to a
-- ward bed. Only then is "Which floor?" a true question (a ground bed, or a Hydro patient in a ward bed because the
-- tubs are full, would make the right answer look wrong).
function Pure.routed(dept: string?, kind: string?): boolean
	return (dept == "Hydro" and kind == "Tub") or (dept == "Wards" and kind == "Upstairs")
end

-- The floor pick once the recipe is complete. "None": fewer than two places to send it (below Lv 3), it isn't going
-- to its department's floor (`routed` false: no question, no bonus), or nobody to ask (a nurse finished it);
-- "Instant": a Receptionist sends it at once, with the bonus, and so does Simple mode (`simple`: no timed decision for
-- the youngest players); "Ask": the helper picks.
function Pure.triageMode(
	options: { string }?,
	receptionist: boolean,
	byPlayer: boolean,
	routed: boolean?,
	simple: boolean?
): string
	if type(options) ~= "table" or #options < 2 then
		return "None"
	elseif receptionist then
		return "Instant"
	elseif routed == false then
		return "None"
	elseif simple == true and byPlayer then
		return "Instant"
	elseif byPlayer then
		return "Ask"
	end
	return "None"
end

-- A pick earns the bonus only when it's the right floor ("" = no pick in time: no bonus).
function Pure.triageBonus(pick: any, right: string): boolean
	return type(pick) == "string" and pick ~= "" and pick == right
end

local function factor(value: any): number
	return if type(value) == "number" and value == value and value > 0 and value < math.huge then value else 1
end

local function comfortLevel(value: any): number
	return if type(value) == "number" and value == value then math.clamp(math.floor(value), 0, 10) else 0
end

-- A Config bonus fraction (0.2 = +20%): finite and in 0..1, junk -> 0.
local function bonus(value: any): number
	return if type(value) == "number" and value == value then math.clamp(value, 0, 1) else 0
end

-- The cure's situational cash factor (CureCtx.Extra): Escort/Porter x the hot tub x a right triage x the team's cash
-- x Ward Comfort. `cfg` = Config (Escort, Hydro, Triage, WardComfort). Clamped to 1..maxExtra.
function Pure.extra(
	f: { Escorted: boolean?, Soaked: boolean?, Triage: boolean?, Team: number?, Comfort: number? },
	cfg: any,
	maxExtra: number
): number
	local value = 1
	if f.Escorted then
		value *= 1 + bonus(cfg.Escort and cfg.Escort.CashBonus)
	end
	if f.Soaked then
		value *= 1 + bonus(cfg.Hydro and cfg.Hydro.CashBonus)
	end
	if f.Triage then
		value *= 1 + bonus(cfg.Triage and cfg.Triage.RightBonus)
	end
	value *= math.max(1, factor(f.Team))
	local perLevel = cfg.WardComfort and cfg.WardComfort.CashPerLevel
	if type(perLevel) == "number" and perLevel > 0 then
		value *= 1 + perLevel * comfortLevel(f.Comfort)
	end
	return math.clamp(value, 1, math.max(1, maxExtra))
end

-- Rest seconds (Logic/Hospital.recover, never under 0.5 s): base x the escort's RecoverFactor x the hot tub's x
-- (1 - RecoverPerLevel x Ward Comfort) x the team's Recover factor.
function Pure.rest(
	base: number,
	f: { Escorted: boolean?, Soaked: boolean?, Comfort: number?, Team: number? },
	cfg: any
): number
	local perLevel = cfg.WardComfort and cfg.WardComfort.RecoverPerLevel
	local comfort = 1 - (if type(perLevel) == "number" then perLevel else 0) * comfortLevel(f.Comfort)
	return Hospital.recover(base, {
		if f.Escorted then factor(cfg.Escort and cfg.Escort.RecoverFactor) else 1,
		if f.Soaked then factor(cfg.Hydro and cfg.Hydro.RecoverFactor) else 1,
		math.max(comfort, 0.05),
		math.min(factor(f.Team), 1),
	})
end

-- An urgent patient's recipe at this clinic (`makes` = { [ItemId]: true }): Logic/Hospital.urgentRecipe, or, when an
-- item of it is made by no station here (the Sky wing's ☕ without a Winter Wing), the same with those items left
-- out (its first, own-station item must stay). nil when nothing can be made of it.
function Pure.urgentFor(recipe: { string }, makes: { [string]: boolean }, cap: number, minItems: number): { string }?
	local direct = Hospital.urgentRecipe(recipe, makes, cap, minItems)
	if direct then
		return direct
	end
	local kept: { string } = {}
	for _, item in recipe do
		if makes[item] == true then
			table.insert(kept, item)
		end
	end
	if #kept == 0 or kept[1] ~= recipe[1] then
		return nil
	end
	return Hospital.urgentRecipe(kept, makes, cap, minItems)
end

-- An urgent patient's patience: base x AE.PatienceMultiplier, and for a 🚑 x (1 + AESpeed.PatiencePerLevel x the
-- owner's A&E Speed level). Never less than 1 s.
function Pure.urgentPatience(base: number, urgent: string, aeSpeed: number, cfg: any): number
	local multiplier = cfg.AE and cfg.AE.PatienceMultiplier
	local value = factor(base) * (if type(multiplier) == "number" and multiplier > 0 then multiplier else 1)
	local perLevel = cfg.AESpeed and cfg.AESpeed.PatiencePerLevel
	if urgent == "AE" and type(perLevel) == "number" then
		value *= 1 + perLevel * comfortLevel(aeSpeed)
	end
	return math.max(1, value)
end

-- Seconds to the next ambulance: AE.EverySeconds +-Jitter (`roll` in [0, 1)), x (1 - SoonerPerLevel x A&E Speed),
-- / Siren Pro (Logic/Hospital.arrival: never under 1 s).
function Pure.aeSeconds(cfg: any, roll: number, aeSpeed: number, sirenPro: number): number
	local ae = cfg.AE or {}
	local jitter = math.clamp(if type(ae.Jitter) == "number" then ae.Jitter else 0, 0, 0.9)
	local base = factor(ae.EverySeconds) * (1 - jitter + 2 * jitter * math.clamp(roll, 0, 1))
	local perLevel = cfg.AESpeed and cfg.AESpeed.SoonerPerLevel
	local sooner = 1 - (if type(perLevel) == "number" then perLevel else 0) * comfortLevel(aeSpeed)
	return Hospital.arrival(base, { math.max(sooner, 0.1), 1 / math.max(factor(sirenPro), 1) })
end

-- Seconds to the next air ambulance: VIP.EverySeconds +-Jitter.
function Pure.vipSeconds(cfg: any, roll: number): number
	local vip = cfg.VIP or {}
	local jitter = math.clamp(if type(vip.Jitter) == "number" then vip.Jitter else 0, 0, 0.9)
	return Hospital.arrival(factor(vip.EverySeconds) * (1 - jitter + 2 * jitter * math.clamp(roll, 0, 1)), {})
end

-- How much slower an urgent patient's patience drains: the A&E team's Urgent factor x the best Medic's Patience
-- factor (1 = normal; junk or below 1 counts as 1; at most `max`).
function Pure.slower(team: any, medic: any, max: number): number
	return math.clamp(math.max(1, factor(team)) * math.max(1, factor(medic)), 1, max)
end

-- A new patient's variant: 🌟 Golden first (an owner with `goldenRebirths` rebirths: Config.GoldenChance, or always
-- with the Studio switch `force`), then ✨ Sparkly, then 🧊 Frosty in winter. `rolls` = three numbers in [0, 1).
function Pure.variant(
	rebirths: number,
	rolls: { number },
	winter: boolean,
	force: boolean,
	cfg: any,
	goldenRebirths: number
): string?
	if rebirths >= goldenRebirths and (force or (rolls[1] or 1) < (cfg.GoldenChance or 0)) then
		return "Golden"
	end
	if (rolls[2] or 1) < (cfg.SparklyChance or 0) then
		return "Sparkly"
	end
	if winter and (rolls[3] or 1) < (cfg.FrostyChance or 0) then
		return "Frosty"
	end
	return nil
end

-- May a patient of this wing (a Data/Wings row) come to a clinic whose owner has `rebirths`? By the usual line: only
-- wings without `Only`, once Rebirths are reached (🌻 Sunny from R1). By air (`byAir`): only "Helicopter" wings (🚁
-- Sky; the helicopter itself only flies from R2).
function Pure.wingOpen(wing: any, rebirths: number, byAir: boolean): boolean
	local only = if type(wing) == "table" then wing.Only else nil
	if byAir then
		return only == "Helicopter"
	end
	local need = if type(wing) == "table" and type(wing.Rebirths) == "number" then wing.Rebirths else 0
	return only == nil and rebirths >= need
end

-- The first recipe slot still missing, or nil when the recipe is complete.
function Pure.firstMissing(recipe: { string }, done: { boolean }): number?
	for index in recipe do
		if not done[index] then
			return index
		end
	end
	return nil
end

-- A patient's recipe: the data's list (an ailment's, or a regular's own) cut to `cap`; `fallback` (the ailment's
-- station item) when the data has none. Never empty.
function Pure.recipeFor(full: any, fallback: string, cap: number): { string }
	local list: { string } = {}
	if type(full) == "table" then
		for _, itemId in full do
			if type(itemId) == "string" then
				table.insert(list, itemId)
			end
		end
	end
	if #list == 0 or list[1] ~= fallback then
		list = { fallback } -- item 1 is always the ailment's own station item (Data/Ailments asserts it)
	end
	return Recipe.effective(list, cap)
end

-- What a patient still needs, not counting the slots in a mini-game right now (`inFlight`).
function Pure.needs(recipe: { string }, done: { boolean }, inFlight: { number }?): { string }
	return Recipe.missing(recipe, if inFlight then Recipe.apply(done, inFlight) else done)
end

-- Patience after `count` recipe items were given: each refills `share` of the most it can hold.
function Pure.refill(patience: number, max: number, share: number, count: number): number
	return math.clamp(patience + max * math.max(share, 0) * math.max(count, 0), 0, max)
end

-- The plot's CheerPatience attribute as a safe divisor for the patience drain (1 = no Cheerer; junk -> 1).
function Pure.cheer(value: any, max: number): number
	if type(value) ~= "number" or value ~= value or value < 1 then
		return 1
	end
	return math.min(value, max)
end
-- PURE-END

------------------------------------------------------------------------------------------------------------------
-- Where things are
------------------------------------------------------------------------------------------------------------------

local function makeNav(plot: Plot): Nav
	local pivot = plot.Model:GetPivot()
	local function localOf(part: BasePart): Vector3
		return pivot:PointToObjectSpace(part.Position)
	end
	local counter = plot.Counter
	local standHalf, standBack = 15, 1 -- PlotBuilder.SLOTS.Stand (x ±15, z -13..1), for a plot with no RoomSlot_Stand
	local slots = plot.Model:FindFirstChild("Slots")
	local stand = slots and slots:FindFirstChild("RoomSlot_Stand")
	if stand and stand:IsA("BasePart") then
		local c = localOf(stand)
		standHalf = math.abs(c.X) + stand.Size.X / 2
		standBack = c.Z + stand.Size.Z / 2
	end
	-- The walkway on each side runs halfway between the Stand and the nearest room slot beside it.
	local left, right = standHalf + 1.6, standHalf + 1.6
	if slots then
		for _, slot in slots:GetChildren() do
			if slot:IsA("BasePart") and slot ~= stand then
				local c = localOf(slot)
				local inner = math.abs(c.X) - slot.Size.X / 2
				if inner > standHalf and inner - standHalf < 6 then
					local middle = (standHalf + inner) / 2
					if c.X < 0 then
						left = math.min(left, middle)
					else
						right = math.min(right, middle)
					end
				end
			end
		end
	end
	return {
		Pivot = pivot,
		LaneZ = localOf(plot.QueueStart).Z,
		SideStep = math.abs(localOf(counter).X) + counter.Size.X / 2 + 1.6,
		StandHalf = standHalf,
		StandBack = standBack,
		BackZ = standBack + 3,
		Left = left,
		Right = right,
	}
end

local function toWorld(nav: Nav, x: number, z: number): Vector3
	return nav.Pivot * Vector3.new(x, 0, z)
end

-- The ground (plot Ground or a room floor) under a point.
local function groundAt(state: PlotState, position: Vector3): Vector3
	local baseY = state.Nav.Pivot.Y
	local hit = Workspace:Raycast(Vector3.new(position.X, baseY + 10, position.Z), Vector3.new(0, -24, 0), state.Ray)
	return Vector3.new(position.X, if hit then hit.Position.Y else baseY, position.Z)
end

-- Markers are 2x1x2 and rest on the ground: their bottom face is the ground, facing as they face.
local function markerGround(marker: BasePart): CFrame
	return marker.CFrame * CFrame.new(0, -marker.Size.Y / 2, 0)
end

-- Place `index` in line (1 = the front): straight back from QueueStart, Config.QueueSpacing apart, turning sideways
-- past Config.QueueDepth. PlotBuilder.queueSpot works it out, and paints the queue lane's numbered spots from the
-- same function, so the pavement always lines up with where patients stand.
local function queueSpot(plot: Plot, index: number): CFrame
	return PlotBuilder.queueSpot(plot.QueueStart, plot.Spawn, index)
end

-- On the floor just past the foot of a bed (Bed_<n> is the mattress; its pillow end is +Z).
local function bedFoot(bed: BasePart): Vector3
	return (bed.CFrame * CFrame.new(0, 0, -bed.Size.Z / 2 - 1.6)).Position
end

-- On the mattress, facing the foot of the bed. Lying = leaning back onto the pillow.
local function bedPose(bed: BasePart, lying: boolean, scale: number): CFrame
	local top = bed.CFrame * CFrame.new(0, bed.Size.Y / 2, -0.35)
	if lying then
		return top * CFrame.new(0, 0.35 * scale, 0) * CFrame.Angles(math.rad(58), 0, 0)
	end
	return top
end

-- From the front of the line to the foot of a bed, round the Counter and the rooms.
local function bedRoute(state: PlotState, from: Vector3, foot: Vector3): { Vector3 }
	local nav = state.Nav
	local here = nav.Pivot:PointToObjectSpace(from)
	local target = nav.Pivot:PointToObjectSpace(foot)
	local side = if target.X < 0 then -1 else 1
	local x: number
	if target.Z > nav.StandBack or math.abs(target.X) > nav.StandHalf then
		x = side * (if side < 0 then nav.Left else nav.Right) -- a bed in another room: take the walkway
	else
		x = side * math.max(math.abs(target.X), nav.SideStep) -- a bed in the Stand: just round the Counter
	end
	return { toWorld(nav, x, here.Z), toWorld(nav, x, target.Z), foot }
end

-- From anywhere on the plot out through PatientExit, keeping clear of the line (which sits at x = 0).
local function exitRoute(state: PlotState, from: Vector3): { Vector3 }
	local nav = state.Nav
	local here = nav.Pivot:PointToObjectSpace(from)
	local points: { Vector3 } = {}
	local function add(x: number, z: number)
		table.insert(points, toWorld(nav, x, z))
	end
	if here.Z > nav.StandBack then
		-- Behind the Stand: along the back lane to the right walkway, then down it.
		local x = math.clamp(here.X, -nav.Left, nav.Right)
		add(x, here.Z)
		add(x, nav.BackZ)
		add(nav.Right, nav.BackZ)
		add(nav.Right, nav.LaneZ)
	elseif here.X >= -0.5 then
		local x = if math.abs(here.X) <= nav.StandHalf then math.max(here.X, nav.SideStep) else nav.Right
		add(x, here.Z)
		add(x, nav.LaneZ)
	else
		-- Left of the line: round the back of the Stand rather than through the line.
		add(-nav.Left, here.Z)
		add(-nav.Left, nav.BackZ)
		add(nav.Right, nav.BackZ)
		add(nav.Right, nav.LaneZ)
	end
	table.insert(points, markerGround(state.Plot.Exit).Position)
	return points
end

-- Progression v2: the floor a part of the building is on: the nearest "Floor" attribute (a ward bed's Floor = 1, a
-- tub spot's Floor = 2) or Floor_<n> Model above it (PlotBuilder §B4); 0 = the ground.
local function floorOf(part: Instance, stop: Instance): number
	local current: Instance? = part
	while current and current ~= stop do
		local value = current:GetAttribute("Floor")
		if type(value) == "number" and value == value then
			return math.clamp(math.floor(value), 0, 10)
		end
		local named = string.match(current.Name, "^Floor_(%d+)$")
		if named then
			return math.clamp(tonumber(named) or 0, 0, 10)
		end
		current = current.Parent
	end
	return 0
end

-- The floor surface under a point: the building's slabs and the plot's Ground (a short ray down; the walls above
-- the ground storey are ray-ignored). The point itself when nothing is there.
local function floorAt(state: PlotState, position: Vector3): Vector3
	local include: { Instance } = {}
	for _, name in { "Building", "Ground" } do
		local found = state.Plot.Model:FindFirstChild(name)
		if found then
			table.insert(include, found)
		end
	end
	state.FloorRay.FilterDescendantsInstances = include
	local hit = Workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -8, 0), state.FloorRay)
	return if hit then Vector3.new(position.X, hit.Position.Y, position.Z) else position
end

-- A resting pivot standing on the floor at `cf` (a lift landing, a spot), facing the way it faces.
local function standAt(state: PlotState, cf: CFrame): CFrame
	local at = floorAt(state, cf.Position)
	local look = cf.LookVector * Vector3.new(1, 0, 1)
	return if look.Magnitude > 0.01 then CFrame.lookAt(at, at + look.Unit) else CFrame.new(at)
end

-- The free places to rest, nearest the Counter first: a bed on the ground, a ward bed upstairs (only with a lift to
-- that floor) and a hot-tub spot (Building.Hydro.HotTub.TubSpot_<n>, at most Config.Hydro.Spots; also by lift).
type Spots = { Ground: BasePart?, Upstairs: BasePart?, Tub: BasePart? }
local function freeSpots(state: PlotState): Spots
	local plot = state.Plot
	local counter = plot.Counter.Position
	local spots: Spots = { Ground = nil, Upstairs = nil, Tub = nil }
	local groundBest, upBest = math.huge, math.huge
	local hasLift = landingOf(plot, 0) ~= nil
	local reachable: { [number]: boolean } = {}
	local function canReach(floor: number): boolean
		if reachable[floor] == nil then
			reachable[floor] = hasLift and landingOf(plot, floor) ~= nil
		end
		return reachable[floor]
	end
	local tubSpots = math.max(0, math.floor(tonumber(Config.Hydro.Spots) or 2))
	-- A theme change or a level-up rebuilds the Building, and its TubSpot parts are new ones (ward beds move across,
	-- tub spots don't): a patient soaking on the old TubSpot_1 still holds TubSpot_1, so go by name for those.
	local tubsHeld: { [string]: boolean } = {}
	for spot in state.Beds do
		if string.match(spot.Name, "^TubSpot_%d+$") then
			tubsHeld[spot.Name] = true
		end
	end
	for _, holderName in { "Rooms", "Building" } do
		local holder = plot.Model:FindFirstChild(holderName)
		if holder then
			for _, descendant in holder:GetDescendants() do
				if descendant:IsA("BasePart") and not state.Beds[descendant] then
					if string.match(descendant.Name, "^Bed_%d+$") then
						local floor = floorOf(descendant, plot.Model)
						local distance = (descendant.Position - counter).Magnitude
						if floor == 0 then
							if distance < groundBest then
								spots.Ground, groundBest = descendant, distance
							end
						elseif distance < upBest and canReach(floor) then
							spots.Upstairs, upBest = descendant, distance
						end
					elseif holderName == "Building" and not spots.Tub then
						local n = tonumber(string.match(descendant.Name, "^TubSpot_(%d+)$"))
						local floor = if n then floorOf(descendant, plot.Model) else 0
						if
							n
							and n <= tubSpots
							and not tubsHeld[descendant.Name]
							and (floor == 0 or canReach(floor))
						then
							spots.Tub = descendant
						end
					end
				end
			end
		end
	end
	return spots
end

-- The owner stands at their clinic (their plot, any floor, give or take PLOT_MARGIN).
local function ownerAtClinic(state: PlotState): boolean
	local character = state.Owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	local here = state.Nav.Pivot:PointToObjectSpace(root.Position)
	local half = Config.Town.PlotSize / 2 + PLOT_MARGIN
	return math.abs(here.X) <= half and math.abs(here.Z) <= half
end

-- A named marker anywhere in the plot's Building (StretcherSpot, HeliSpot, ...), or nil.
local function buildingPart(state: PlotState, name: string): BasePart?
	local building = state.Plot.Model:FindFirstChild("Building")
	local found = building and building:FindFirstChild(name, true)
	return if found and found:IsA("BasePart") then found else nil
end

local function stationsOnPlot(plot: Plot): { [string]: boolean }
	local found: { [string]: boolean } = {}
	local rooms = plot.Model:FindFirstChild("Rooms")
	if rooms then
		for _, descendant in rooms:GetDescendants() do
			-- A Station_<id> is a Part by contract; a kit room may use a Model (Stations wires those too).
			if descendant:IsA("BasePart") or descendant:IsA("Model") then
				local stationId = string.match(descendant.Name, "^Station_(%w+)$")
				if stationId and rawget(StationsData :: any, stationId) then
					found[stationId] = true
				end
			end
		end
	end
	return found
end

------------------------------------------------------------------------------------------------------------------
-- The animator: attributes the clients draw (Feel/CreatureMotion); the server only writes where each one ends
------------------------------------------------------------------------------------------------------------------

-- The creature's scale right now, as the clients draw it (so a new grow/shrink starts from where the last one is).
local function currentScale(p: Patient): number
	local anim = p.ScaleAnim
	if not anim then
		return p.Model:GetScale()
	end
	local t = (os.clock() - anim.Start) / anim.Seconds
	if t >= 1 then
		return anim.To
	end
	return anim.From + (anim.To - anim.From) * TweenService:GetValue(math.max(t, 0), anim.Style, anim.Direction)
end

-- One hop to `to` (a resting pivot). Yields until it lands; false if the patient is gone by then.
local function hop(p: Patient, to: CFrame, height: number, seconds: number, spin: number?): boolean
	if not alive(p) then
		return false
	end
	local duration = math.max(seconds, 0.15)
	CreatureBuilder.hop(p.Model, p.Pivot, to, duration, height, spin or 0, if spin then 0 else LEAN)
	task.wait(duration)
	if not alive(p) then
		return false
	end
	p.Pivot = to
	p.Root.CFrame = to -- the end pose, once: late joiners and the server's own checks see it here
	return true
end

-- Grows or shrinks to `target` over `seconds` (the clients draw it); the end scale is set here once it's over.
local function scaleTo(
	p: Patient,
	target: number,
	seconds: number,
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection
)
	local anim: ScaleAnim = {
		From = math.max(currentScale(p), 0.02),
		To = math.max(target, 0.02),
		Start = os.clock(),
		Seconds = math.max(seconds, 0.05),
		Style = style,
		Direction = direction,
	}
	p.ScaleAnim = anim
	CreatureBuilder.scale(p.Model, anim.From, anim.To, anim.Seconds, style.Name, direction.Name)
	task.delay(anim.Seconds, function()
		if p.ScaleAnim == anim then
			p.ScaleAnim = nil
			if p.State ~= "Gone" then
				p.Model:ScaleTo(anim.To)
			end
		end
	end)
end

-- A droop over everything else (the clients draw it); 0 = upright.
local function setTilt(p: Patient, radians: number)
	p.Tilt = radians
	CreatureBuilder.tilt(p.Model, radians)
end

-- Hops along a path of points, a few studs per hop, turning to face where it's going. On a floor above the ground
-- (`floorY`, the slab's height: Progression v2) every hop lands at that height instead of on the plot's ground.
local function walk(p: Patient, points: { Vector3 }, floorY: number?): boolean
	local state = p.Plot
	for _, point in points do
		while true do
			local from = p.Pivot.Position
			local delta = Vector3.new(point.X - from.X, 0, point.Z - from.Z)
			local distance = delta.Magnitude
			if distance < 0.05 then
				break
			end
			local stepLength = distance / math.ceil(distance / HOP_LENGTH)
			local direction = delta / distance
			local ahead = from + direction * stepLength
			local landing = if floorY then Vector3.new(ahead.X, floorY, ahead.Z) else groundAt(state, ahead)
			local seconds = p.HopSeconds * math.sqrt(stepLength / HOP_LENGTH)
			if not hop(p, CFrame.lookAt(landing, landing + direction), p.HopHeight, seconds) then
				return false
			end
		end
	end
	return true
end

-- One hop toward a place in line, landing on it (and facing the counter) when it's close.
local function stepToward(p: Patient, spot: CFrame): boolean
	local from = p.Pivot.Position
	local delta = Vector3.new(spot.X - from.X, 0, spot.Z - from.Z)
	local distance = delta.Magnitude
	if distance <= HOP_LENGTH then
		local seconds = p.HopSeconds * math.sqrt(math.max(distance, 0.6) / HOP_LENGTH)
		return hop(p, spot, p.HopHeight, seconds)
	end
	local direction = delta / distance
	local landing = groundAt(p.Plot, from + direction * HOP_LENGTH)
	return hop(p, CFrame.lookAt(landing, landing + direction), p.HopHeight, p.HopSeconds)
end

------------------------------------------------------------------------------------------------------------------
-- Badge, attributes and the front of the line
------------------------------------------------------------------------------------------------------------------

local function setState(p: Patient, state: string)
	p.Model:SetAttribute("State", state)
end

-- The State a patient in line shows: "Treating" while its mini-game is open (with Twin Counters the line can move
-- under a patient mid-game), else "Waiting" at its place or "Arriving" on its way there.
local function lineState(p: Patient): string
	if p.Session then
		return "Treating"
	end
	return if p.Arrived then "Waiting" else "Arriving"
end

local function ringColor(fraction: number): Color3
	if fraction > 0.5 then
		return RING_CALM
	elseif fraction > 0.25 then
		return RING_HURRY
	end
	return RING_LOW
end

-- The PatienceFraction attribute for the client's acting (Feel/CreatureActing), only when its 0.05 step changes.
local function showPatience(p: Patient, fraction: number)
	local shown = math.ceil(math.clamp(fraction, 0, 1) * PATIENCE_STEPS) / PATIENCE_STEPS
	if shown ~= p.PatienceShown then
		p.PatienceShown = shown
		p.Model:SetAttribute("PatienceFraction", shown)
	end
end

local function showRing(p: Patient, fraction: number, color: Color3)
	local stepIndex = math.floor(math.clamp(fraction, 0, 1) * RING_STEPS + 0.5)
	if stepIndex == p.RingStep and color == p.RingColor then
		return
	end
	p.RingStep = stepIndex
	p.RingColor = color
	CreatureBuilder.setRing(p.Badge, stepIndex / RING_STEPS, color)
end

-- The recipe on the model (Recipe, RecipeDone, Item and Station = the first missing item) and on the badge.
local function showRecipe(p: Patient)
	local first = Pure.firstMissing(p.Recipe, p.Done)
	if first then
		local itemId = p.Recipe[first]
		local item = rawget(ItemsData :: any, itemId)
		p.Item = itemId
		p.Station = if item then item.Station else p.Station
		p.Model:SetAttribute("Item", p.Item)
		p.Model:SetAttribute("Station", p.Station)
	end
	p.Model:SetAttribute("Recipe", Recipe.join(p.Recipe))
	p.Model:SetAttribute("RecipeDone", Recipe.encode(p.Done))
	local ok, err = pcall(CreatureBuilder.setRecipe, p.Badge, p.Recipe, p.Done)
	if not ok then
		report("CreatureBuilder.setRecipe", err)
	end
end

-- Ready to be treated: standing at its place in line, not mid-mini-game.
local function ready(p: Patient): boolean
	return p.State == "Queue" and p.Arrived and not p.Session and not p.Claimed
end

-- The patients a treat (or a Healer) may serve, front first: the front one, or with 👯 Twin Counters (the owner's
-- capstone) the first TWO places in line, each only while it's ready.
local function frontCandidates(state: PlotState): { Patient }
	local places = if state.Effects.TwinCounters then 2 else 1
	local out: { Patient } = {}
	for index = 1, math.min(places, #state.Queue) do
		local p = state.Queue[index]
		if ready(p) then
			table.insert(out, p)
		end
	end
	return out
end

local function setPlotAttribute(state: PlotState, name: string, value: string)
	if state.Plot.Model:GetAttribute(name) ~= value then
		state.Plot.Model:SetAttribute(name, value)
	end
end

-- The prompt, its icon and the plot's FrontItem / FrontStation / FrontNeeds / QueueNeeds attributes follow the
-- line. Cheap (a handful of patients), so the clinic tick calls it every TICK too.
local function refreshFront(state: PlotState)
	if active[state.Plot] ~= state then
		return
	end
	local candidates = frontCandidates(state)
	local front = candidates[1]
	local waiting = front ~= nil
	local item, station, icon, needs = "", "", "", ""
	if front then
		item, station, icon = front.Item, front.Station, front.AilmentIcon
		-- FrontNeeds covers every patient the Counter may serve (both with Twin Counters), front first.
		local all: { string } = {}
		for _, candidate in candidates do
			for _, itemId in Pure.needs(candidate.Recipe, candidate.Done, nil) do
				table.insert(all, itemId)
			end
		end
		needs = Recipe.join(all)
	end
	local prompt = state.Prompt
	if prompt.Enabled ~= waiting then
		prompt.Enabled = waiting
	end
	if prompt.ObjectText ~= icon then
		prompt.ObjectText = icon
	end
	if state.FrontItem ~= item then
		state.FrontItem = item
		setPlotAttribute(state, "FrontItem", item)
		setPlotAttribute(state, "FrontStation", station)
	end
	if state.FrontNeeds ~= needs then
		state.FrontNeeds = needs
		setPlotAttribute(state, "FrontNeeds", needs)
	end
	local queued: { string } = {}
	for _, p in state.Queue do
		if p.State == "Queue" then
			for _, itemId in Pure.needs(p.Recipe, p.Done, p.SessionIndices) do
				table.insert(queued, itemId)
			end
		end
	end
	local queueNeeds = Recipe.join(queued)
	if state.QueueNeeds ~= queueNeeds then
		state.QueueNeeds = queueNeeds
		setPlotAttribute(state, "QueueNeeds", queueNeeds)
	end
end

local function removeFromQueue(state: PlotState, p: Patient)
	local index = table.find(state.Queue, p)
	if not index then
		return
	end
	table.remove(state.Queue, index)
	p.Model:SetAttribute("QueueIndex", 0)
	for i = index, #state.Queue do
		local behind = state.Queue[i]
		behind.Model:SetAttribute("QueueIndex", i)
		if behind.State == "Queue" and behind.Arrived then
			-- Its place moved up: it has to hop there before it can be treated (and patience pauses meanwhile).
			behind.Arrived = false
			setState(behind, lineState(behind))
		end
	end
	if state.Active then
		state.NextSpawn = math.max(state.NextSpawn, os.clock() + REFILL_SECONDS)
		refreshFront(state)
	end
end

-- Progression v2: an urgent patient joins the line at the front, behind anyone mid-mini-game or resting there
-- (Pure.urgentPlace). Everyone behind it moves back a place (and hops there before it can be treated).
local function insertUrgent(state: PlotState, p: Patient)
	local busy: { boolean } = {}
	for index, other in state.Queue do
		busy[index] = other.State ~= "Queue" or other.Session ~= nil or other.Claimed
	end
	local index = math.clamp(Pure.urgentPlace(busy), 1, #state.Queue + 1)
	table.insert(state.Queue, index, p)
	p.Model:SetAttribute("QueueIndex", index)
	for i = index + 1, #state.Queue do
		local behind = state.Queue[i]
		behind.Model:SetAttribute("QueueIndex", i)
		if behind.State == "Queue" and behind.Arrived then
			behind.Arrived = false
			setState(behind, lineState(behind))
		end
	end
	refreshFront(state)
end

local function releaseBed(state: PlotState, p: Patient)
	local bed = p.Bed
	if bed and state.Beds[bed] == p then
		state.Beds[bed] = nil
	end
end

-- Closes a patient's open mini-game session without settling it (the patient is going away). The helper's own
-- items come back to their tray when `giveItemsBack` (the nurse tray's are spent: they're free and nurse-made).
local function dropSession(p: Patient, giveItemsBack: boolean)
	local id = p.Session
	if not id then
		return
	end
	local helper, carried = p.SessionHelper, p.SessionCarried
	p.Session = nil
	p.SessionHelper = nil
	p.SessionIndices = nil
	p.SessionCarried = nil
	local ok, err = pcall(Treatment.drop, id)
	if not ok then
		report("Treatment.drop", err)
	end
	if giveItemsBack and helper and carried then
		for _, itemId in carried do
			giveBack(helper, itemId)
		end
	end
end

-- Progression v2: its open 🫧 Soak session closes without settling.
local function dropSoak(p: Patient)
	local id = p.SoakSession
	if not id then
		return
	end
	p.SoakSession = nil
	local ok, err = pcall(Treatment.drop, id)
	if not ok then
		report("Treatment.drop", err)
	end
end

-- Progression v2: the Porter it claimed goes back to work.
local function releasePorter(p: Patient)
	local porter = p.Porter
	if not porter then
		return
	end
	p.Porter = nil
	local ok, err = pcall(Nurses.releasePorter, p.Plot.Plot, porter)
	if not ok then
		report("Nurses.releasePorter", err)
	end
end

-- Progression v2: its turn on the lift is over.
local function liftDone(p: Patient)
	if p.HasLift then
		p.HasLift = false
		p.Plot.LiftBusy = false
	end
end

local refreshSoak: (state: PlotState) -> () -- defined further down

local function removePatient(p: Patient)
	if p.State == "Gone" then
		return
	end
	dropSession(p, true)
	dropSoak(p)
	releasePorter(p)
	liftDone(p)
	local state = p.Plot
	if p.Incoming then
		p.Incoming = false
		state.Incoming = math.max(0, state.Incoming - 1)
	end
	removeFromQueue(state, p)
	releaseBed(state, p)
	local wasSoaking = p.Soaking
	p.Soaking = false
	p.State = "Gone"
	state.All[p] = nil
	if wasSoaking and state.Active then
		refreshSoak(state)
	end
	local thread = p.Thread
	p.Thread = nil
	cancel(thread)
	p.Model:Destroy()
end

------------------------------------------------------------------------------------------------------------------
-- A patient's visit (runs on the patient's own thread)
------------------------------------------------------------------------------------------------------------------

-- Hands the cure to Cure.resolve on its own thread. The helper is whoever treated it, or the owner if they've
-- left; Cure.resolve skips whichever of the two is gone.
local function payCure(p: Patient)
	local state = p.Plot
	local owner = state.Owner
	local helper = owner
	local treatedBy = p.Helper
	if treatedBy and treatedBy.Parent == Players then
		helper = treatedBy -- if the helper has left, the owner gets the cure
	end
	-- Progression v2: what Patients knows about this cure (Pure.extra), for Logic/Pay via Cure.
	local data = PlayerData.get(owner)
	local comfort = if data then data.Upgrades.WardComfort or 0 else 0
	local extra = Pure.extra({
		Escorted = p.Escorted,
		Soaked = p.SpotKind == "Tub",
		Triage = p.TriageBonus,
		Team = teamOf(state.Plot).Cash,
		Comfort = comfort,
	}, Config, Pay.MAX_EXTRA)
	local ctx: Types.CureCtx = {
		Helper = helper,
		Owner = owner,
		PatientId = p.PatientId,
		Variant = p.Variant,
		Night = p.Night,
		Regular = p.Regular,
		Visitor = p.Visitor,
		PatienceLeft = p.PatienceLeft,
		Position = p.Root.Position + Vector3.new(0, 2.5 * p.BaseScale, 0),
		Items = #p.Recipe, -- a longer recipe pays more
		Cheer = Pure.cheer(p.Plot.Plot.Model:GetAttribute("CheerTip"), MAX_CHEER_TIP), -- the plot's Cheerer
		Urgent = if p.Urgent ~= "" then p.Urgent else nil, -- 🚑 x3 + 2 ⭐ · 🚁 x4 + 3 ⭐
		Extra = extra,
		Plot = state.Plot, -- Cure asks Abilities (Double Dose, Star Burst) about this plot
		Dept = p.RecoverIn, -- where it recovered (nurse XP specialty)
		Wing = p.Wing,
		Escorted = if p.Escorted then true else nil, -- for the Cured payload (Feel/CureFX's "+20% 🛗")
		Soaked = if p.SpotKind == "Tub" then true else nil, -- "+25% 🛁"
	}
	-- Its own thread: a patient thread cancelled mid-visit can never cut a reward in half.
	task.spawn(function()
		local ok, err = pcall(Cure.resolve, ctx)
		if not ok then
			report("Cure.resolve", err)
		end
	end)
end

local function resolveCure(p: Patient)
	if not alive(p) or p.Plot.Owner.Parent ~= Players then
		return
	end
	payCure(p)
end

-- The clinic is closing (its owner left) while this patient was treated and resting: its treatment was already
-- spent, so the cure lands now instead of being lost. A helper still in the server gets their cash, Book stamp
-- and goal progress; the owner's part lands too while their save is still open.
local function settleEarly(p: Patient)
	if p.State ~= "Treated" and p.State ~= "Recovering" then
		return
	end
	p.State = "Cured"
	payCure(p)
end

------------------------------------------------------------------------------------------------------------------
-- Progression v2: the lift (Server/Lift) and the floors above the ground
------------------------------------------------------------------------------------------------------------------

-- Waits for this plot's lift (one ride at a time), then holds it. False if the patient is gone meanwhile.
local function liftTurn(p: Patient): boolean
	local state = p.Plot
	while state.LiftBusy and alive(p) do
		task.wait(POLL)
	end
	if not alive(p) then
		return false
	end
	state.LiftBusy = true
	p.HasLift = true
	return true
end

-- Rides the lift to `floor` with `others` (its escort: a Porter's model or a player's character). Lift.carry moves
-- each one with ONE PivotTo at that landing when the ride ends (the car moves only on clients); then the patient
-- stands at `to`. A ride that fails or never ends still puts it there, with a soft pop, so it never gets stuck.
local function ride(p: Patient, floor: number, to: CFrame, others: { Model }): boolean
	setState(p, "Riding")
	local models: { Model } = { p.Model }
	for _, model in others do
		table.insert(models, model)
	end
	local finished, carried = within(CARRY_SECONDS, "Lift.carry", Lift.carry, p.Plot.Plot, models, floor)
	if not alive(p) then
		return false
	end
	if not (finished and carried == true) then
		CreatureBuilder.effectAt(to.Position + Vector3.new(0, 1.5 * p.BaseScale, 0), "Pop")
	end
	p.Pivot = to
	p.Root.CFrame = to -- its resting pose on that floor, once
	p.Upstairs = floor > 0
	return true
end

-- A Porter's model on the plot (Nurses builds Plot.Nurses.Nurse_<NurseId>).
local function porterModel(plot: Plot, nurseId: string): Model?
	local folder = plot.Model:FindFirstChild("Nurses")
	local model = folder and folder:FindFirstChild("Nurse_" .. nurseId)
	return if model and model:IsA("Model") then model else nil
end

-- A model stands within `studs` of `at` (a landing point): across the ground, and not a whole storey above or below.
local function modelNear(model: Model, at: Vector3, studs: number): boolean
	if not model:IsDescendantOf(Workspace) then
		return false
	end
	local offset = model:GetPivot().Position - at
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= studs and math.abs(offset.Y) <= 6
end

-- Someone who can work this plot (Plots.canWork) stands near `at`: only then is an escort worth waiting for.
local function workerNear(plot: Plot, at: Vector3, studs: number): boolean
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character and modelNear(character, at, studs) and Plots.canWork(player, plot) then
			return true
		end
	end
	return false
end

-- Up the lift to `floor` for its rest (a ward bed or the hot tub). At the ground landing it waits ("ToLift") for a
-- free Porter (Nurses.claimPorter; the porter walks over: Nurses.escort) or, with none, a player who can work here
-- (Lift.waitEscort: the landing's EscortPrompt for Config.Lift.EscortWait s). Whoever comes rides with it (Escorted:
-- +20% cash, rest x0.5); nobody: it rides alone (escort is a bonus, never a chore: §E7). True = it stands at that
-- floor's landing.
local function goUp(p: Patient, floor: number): boolean
	local state = p.Plot
	local plot = state.Plot
	local ground, above = landingOf(plot, 0), landingOf(plot, floor)
	if not (ground and above) then
		return false
	end
	local groundStand = standAt(state, ground)
	if not walk(p, bedRoute(state, p.Pivot.Position, groundStand.Position)) then
		return false
	end
	-- Its escort first, then the lift: the lift is held only for the ride itself (§E7: the escort is a bonus that
	-- never slows anything; cured patients riding down and the next one up don't queue behind an escort wait).
	setState(p, "ToLift")
	local others: { Model } = {}
	local okPorter, porter = pcall(Nurses.claimPorter, plot)
	if not okPorter then
		report("Nurses.claimPorter", porter)
	elseif type(porter) == "string" then
		p.Porter = porter
		local finished, arrived = within(PORTER_SECONDS, "Nurses.escort", Nurses.escort, plot, porter, ground)
		if not alive(p) then
			return false
		end
		local model = if finished and arrived == true then porterModel(plot, porter) else nil
		if model then
			table.insert(others, model)
		else
			releasePorter(p) -- it couldn't come: the patient asks a player instead
		end
	end
	-- A player's escort is only waited for when someone who can work here stands near the ground landing; nobody
	-- near (the usual case: the kid is at the Counter): it rides at once.
	if #others == 0 and workerNear(plot, ground.Position, ESCORT_NEAR) then
		local seconds = math.clamp(tonumber(Config.Lift.EscortWait) or 6, 0, 30)
		local finished, rider = within(seconds + ESCORT_SLACK, "Lift.waitEscort", Lift.waitEscort, plot, seconds)
		if not alive(p) then
			return false
		end
		if
			finished
			and typeof(rider) == "Instance"
			and rider:IsA("Player")
			and rider.Parent == Players
			and Plots.canWork(rider, plot)
		then
			local character = rider.Character
			if character then
				table.insert(others, character)
			end
		end
	end
	if not liftTurn(p) then
		return false
	end
	-- A player who walked off while the lift was busy stays behind (never pulled up from afar); a porter waits by it.
	for index = #others, 1, -1 do
		local model = others[index]
		if Players:GetPlayerFromCharacter(model) and not modelNear(model, ground.Position, ESCORT_NEAR) then
			table.remove(others, index)
		end
	end
	p.Escorted = #others > 0
	p.Model:SetAttribute("Escorted", p.Escorted)
	local rode = ride(p, floor, standAt(state, above), others)
	liftDone(p)
	return rode
end

-- Back down after the cure: to this floor's landing, then the lift (alone) to the ground. False = there's no lift
-- (the caller pops it away where it is).
local function goDown(p: Patient): boolean
	local state = p.Plot
	local here, ground = landingOf(state.Plot, p.Floor), landingOf(state.Plot, 0)
	if not (here and ground) then
		return false
	end
	local hereStand = standAt(state, here)
	if not walk(p, { hereStand.Position }, hereStand.Y) then
		return false
	end
	if not liftTurn(p) then
		return false
	end
	local rode = ride(p, 0, standAt(state, ground), {})
	liftDone(p)
	return rode
end

-- Gone with a soft pop where it stands (no way down: the building changed under it).
local function popAway(p: Patient)
	p.Badge.Gui.Enabled = false
	CreatureBuilder.effectAt(p.Root.Position + Vector3.new(0, 1.5 * p.BaseScale, 0), "Pop")
	scaleTo(p, p.BaseScale * 0.05, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	if not hop(p, p.Pivot, 0.5, 0.35) then
		return
	end
	removePatient(p)
end

local function leave(p: Patient)
	local state = p.Plot
	if p.Upstairs then
		if not goDown(p) then
			if alive(p) then
				popAway(p)
			end
			return
		end
	end
	if not walk(p, exitRoute(state, p.Pivot.Position)) then
		return
	end
	local exit = markerGround(state.Plot.Exit)
	p.Badge.Gui.Enabled = false
	CreatureBuilder.effectAt(p.Root.Position + Vector3.new(0, 1.5 * p.BaseScale, 0), "Pop")
	scaleTo(p, p.BaseScale * 0.05, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	if not hop(p, exit * CFrame.new(0, 0, -2), p.HopHeight, 0.35) then
		return
	end
	removePatient(p)
end

-- Patience ran out: droop, a soft sad puff, and gone. No penalty.
local function sadLeave(p: Patient)
	setState(p, "Sad")
	p.Badge.Icon.Text = ICON_SAD
	p.Badge.Need.Visible = false
	pcall(CreatureBuilder.setRecipe, p.Badge, {}, {}) -- the recipe chips go with the Need chip
	p.Badge.Bubble.Enabled = false
	showRing(p, 0, RING_LOW)
	CreatureBuilder.setMood(p.Model, "Sad")
	setTilt(p, -0.22)
	if not sleep(p, 0.8) then
		return
	end
	CreatureBuilder.effectAt(p.Root.Position + Vector3.new(0, 1.4 * p.BaseScale, 0), "Puff")
	p.Badge.Gui.Enabled = false
	scaleTo(p, p.BaseScale * 0.05, 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	if not hop(p, p.Pivot, 0.5, 0.4) then
		return
	end
	removePatient(p)
end

-- Progression v2: the floor pick (Lv 3+, no Receptionist on duty): Treatment.waitTriage waits for the helper's pick
-- (at most Config.Triage.Seconds). It always goes the right way; a right pick is +10% (Pure.triageBonus).
local function triage(p: Patient)
	local ask = p.Triage
	if not ask then
		return
	end
	p.Triage = nil
	setState(p, "Triage")
	local ok, pick = pcall(Treatment.waitTriage, ask.Helper, ask.Session, ask.Options, ask.Right)
	if not ok then
		report("Treatment.waitTriage", pick)
		return
	end
	if Pure.triageBonus(pick, ask.Right) then
		p.TriageBonus = true
	end
end

-- A point `studs` short of `target` on the way from `from` (where a patient stops before hopping into a tub).
local function shortOf(target: Vector3, from: Vector3, studs: number): Vector3
	local delta = Vector3.new(from.X - target.X, 0, from.Z - target.Z)
	if delta.Magnitude < 0.05 then
		return target
	end
	return target + delta.Unit * math.min(studs, delta.Magnitude)
end

-- The rest, wherever it is: eyes closed (in the tub, a happy soak), pink sparkles, the ring fills up. Seconds from
-- Pure.rest (escort, tub, Ward Comfort, the team). False = the patient is gone.
local function rest(p: Patient): boolean
	local state = p.Plot
	p.State = "Recovering"
	setState(p, if p.Soaking then "Soaking" else "Recovering")
	CreatureBuilder.setMood(p.Model, if p.Soaking then "Happy" else "Sleep")
	p.Badge.Icon.Text = if p.Soaking then ICON_SOAK else ICON_SLEEP
	CreatureBuilder.setEffect(p.Model, "Heal", true)
	CreatureBuilder.setEffect(p.Model, "HealLight", true)
	local data = PlayerData.get(state.Owner)
	local seconds = Pure.rest(Config.RecoverSeconds, {
		Escorted = p.Escorted,
		Soaked = p.SpotKind == "Tub",
		Comfort = if data then data.Upgrades.WardComfort or 0 else 0,
		Team = state.Team.Recover,
	}, Config)
	local started = os.clock()
	while true do
		local done = (os.clock() - started) / seconds
		showRing(p, done, RING_HEAL)
		if done >= 1 then
			break
		end
		if not sleep(p, TICK) then
			return false
		end
	end
	CreatureBuilder.setEffect(p.Model, "Heal", false)
	CreatureBuilder.setEffect(p.Model, "HealLight", false)
	return true
end

local function treatAndRecover(p: Patient)
	local state = p.Plot
	setState(p, "Treated")
	if not hop(p, p.Pivot, p.HopHeight * 0.9, 0.3) then -- a happy little bounce
		return
	end
	if p.Triage and p.Bed then
		-- Lv 3+: which floor? It only asks when it goes to its department's floor, so it has a spot to go to: the line
		-- moves up now, and it steps aside for the next patient while the helper picks.
		removeFromQueue(state, p)
		if not hop(p, p.Pivot * CFrame.new(TRIAGE_STEP, 0, 0), p.HopHeight * 0.6, 0.3) then
			return
		end
	end
	triage(p)
	if not alive(p) then
		return
	end
	setState(p, "Treated")

	local bed = p.Bed
	local kind = p.SpotKind
	if bed then
		removeFromQueue(state, p) -- off to rest: the line moves up now
		if (kind == "Upstairs" or kind == "Tub") and p.Floor > 0 then
			local up = goUp(p, p.Floor)
			if not alive(p) then
				return
			end
			if not up then
				-- No way up after all (the building changed): it rests where it stands.
				releaseBed(state, p)
				p.Bed, bed, kind = nil, nil, "Place"
				p.SpotKind = "Place"
			end
		end
	end
	local floorY = if p.Upstairs then p.Pivot.Y else nil
	local approach = p.Pivot.Position -- where it stood before hopping into a tub (it hops back out to here)
	if bed then
		local target = if kind == "Tub" then shortOf(bed.Position, p.Pivot.Position, 3) else bedFoot(bed)
		approach = target
		local route = if floorY then { target } else bedRoute(state, p.Pivot.Position, target)
		local porter = p.Porter
		if porter then
			-- Its Porter walks to the bed with it, then goes back to work.
			task.spawn(function()
				within(PORTER_SECONDS, "Nurses.escort", Nurses.escort, state.Plot, porter, CFrame.new(target))
				if p.Porter == porter then
					releasePorter(p)
				end
			end)
		end
		if not walk(p, route, floorY) then
			return
		end
		if bed.Parent then
			if kind == "Tub" then
				-- In it goes: a splash into the bubbles (standing on the tub's floor, the water up to its middle).
				if not hop(p, standAt(state, bed.CFrame), 1.8, 0.5) then
					return
				end
				p.Soaking = true
				refreshSoak(state)
			else
				if not hop(p, bedPose(bed, true, p.BaseScale), 1.8, 0.5) then -- flop into bed
					return
				end
			end
			p.InBed = true
		end
	end
	p.RecoverIn = if p.Soaking then "Hydro" elseif kind == "Upstairs" then "Wards" else "Reception"

	if not rest(p) then
		return
	end

	-- Cured!
	p.State = "Cured"
	setState(p, "Cured")
	resolveCure(p)
	CreatureBuilder.setMood(p.Model, "Happy")
	p.Badge.Icon.Text = ICON_CURED
	CreatureBuilder.effectAt(p.Root.Position + Vector3.new(0, 1.6 * p.BaseScale, 0), "Cure")
	if p.Soaking then
		-- A little longer in the bubbles while nobody has played its 🫧 game (and until a game on it ends).
		local untilAt = os.clock() + SOAK_LINGER
		while p.SoakSession ~= nil or (not p.SoakDone and os.clock() < untilAt) do
			if not sleep(p, TICK) then
				return
			end
		end
		p.Soaking = false
		refreshSoak(state)
	end
	if bed and p.InBed then
		local away: CFrame
		if kind == "Tub" then
			if not hop(p, p.Pivot, 2.6, 0.6, math.pi * 2) then -- a happy spin in the tub
				return
			end
			local out = Vector3.new(approach.X, floorY or groundAt(state, approach).Y, approach.Z)
			local look = (out - p.Pivot.Position) * Vector3.new(1, 0, 1)
			away = if look.Magnitude > 0.01 then CFrame.lookAt(out, out + look.Unit) else CFrame.new(out)
		else
			if not hop(p, bedPose(bed, false, p.BaseScale), 2.6, 0.6, math.pi * 2) then -- spin up on the bed
				return
			end
			local foot = bedFoot(bed)
			local at = Vector3.new(foot.X, floorY or groundAt(state, foot).Y, foot.Z)
			local look = bed.CFrame.LookVector * Vector3.new(1, 0, 1)
			away = if look.Magnitude > 0.01 then CFrame.lookAt(at, at + look) else CFrame.new(at)
		end
		releaseBed(state, p)
		if not hop(p, away, 1.8, 0.45) then
			return
		end
	else
		releaseBed(state, p)
		if not hop(p, p.Pivot, 2.6, 0.6, math.pi * 2) then -- a happy spin where it stands
			return
		end
	end
	removeFromQueue(state, p) -- if it rested at the front of the line, the line moves on now
	leave(p)
end

-- Progression v2: 💫 Miracle (Abilities CureLine): cured right where it waits, through the usual Cure.resolve (the
-- owner is the helper; no mini-game, so no tip), then a happy spin, and off it goes.
local function curedOnSpot(p: Patient)
	setState(p, "Cured")
	resolveCure(p)
	CreatureBuilder.setMood(p.Model, "Happy")
	p.Badge.Icon.Text = ICON_CURED
	p.Badge.Need.Visible = false
	CreatureBuilder.effectAt(p.Root.Position + Vector3.new(0, 1.6 * p.BaseScale, 0), "Cure")
	if not hop(p, p.Pivot, 2.6, 0.6, math.pi * 2) then
		return
	end
	leave(p)
end

-- Progression v2: a 🚁 VIP from the helipad steps out on the roof, rides the lift down, rounds the Stand to the
-- queue lane and joins the line at the front (Pure.urgentPlace). Without a helipad or a lift it came in by the gate
-- like anyone else, and just joins.
local function flyIn(p: Patient): boolean
	local state = p.Plot
	if p.Upstairs then
		local roof, ground = landingOf(state.Plot, p.ArriveFloor), landingOf(state.Plot, 0)
		if roof and ground then
			local roofStand = standAt(state, roof)
			if not walk(p, { roofStand.Position }, roofStand.Y) then
				return false
			end
			p.Floor = p.ArriveFloor
			if not liftTurn(p) then
				return false
			end
			local rode = ride(p, 0, standAt(state, ground), {})
			liftDone(p)
			if not rode then
				return false
			end
			local route = exitRoute(state, p.Pivot.Position)
			table.remove(route) -- not out of the gate: just to the lane
			if not walk(p, route) then
				return false
			end
		else
			-- The lift went away under it: a pop, and in by the gate.
			local gate = markerGround(state.Plot.Spawn)
			CreatureBuilder.effectAt(gate.Position + Vector3.new(0, 1.5 * p.BaseScale, 0), "Pop")
			p.Pivot = gate
			p.Root.CFrame = gate
			p.Upstairs = false
		end
	end
	setState(p, "Arriving")
	p.Incoming = false
	state.Incoming = math.max(0, state.Incoming - 1)
	insertUrgent(state, p)
	return alive(p)
end

-- Hop to its place in line, then wait there (with little idle hops) until treated or out of patience.
local function waitInLine(p: Patient): boolean
	local state = p.Plot
	while p.State == "Queue" do
		local index = table.find(state.Queue, p)
		if not index then
			return alive(p)
		end
		local spot = queueSpot(state.Plot, index)
		local gap = Vector3.new(spot.X - p.Pivot.X, 0, spot.Z - p.Pivot.Z).Magnitude
		if gap > 0.25 then
			if p.Arrived then
				p.Arrived = false
				setState(p, lineState(p))
				refreshFront(state)
			end
			if not stepToward(p, spot) then
				return false
			end
		else
			if not p.Arrived then
				p.Arrived = true
				setState(p, lineState(p))
				refreshFront(state)
				if state.Queue[1] == p then
					tutorialHook("onFrontArrived", state.Owner)
				end
			end
			local now = os.clock()
			if now >= p.NextIdle and not p.Session then -- stands still for its mini-game
				local low = p.Patience / p.PatienceMax < 0.3 -- impatient: bouncier
				p.NextIdle = now + (if low then rng:NextNumber(0.8, 1.4) else rng:NextNumber(2.5, 4.5))
				if not hop(p, p.Pivot, if low then 0.35 else 0.5, 0.3) then
					return false
				end
			elseif not sleep(p, 0.1) then
				return false
			end
		end
	end
	return alive(p)
end

local function visit(p: Patient)
	if p.Incoming then
		-- 🚁 The helicopter lands first (Feel/HospitalFX flies it in from HeliSpot's ArriveAt); then out it steps.
		if not sleep(p, HELI_LAND_SECONDS) then
			return
		end
		p.Badge.Gui.Enabled = true
	end
	scaleTo(p, p.BaseScale, 0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out) -- pop in
	if not hop(p, p.Pivot, p.HopHeight * 1.2, 0.45) then
		return
	end
	if p.Incoming and not flyIn(p) then
		return
	end
	if not waitInLine(p) then
		return
	end
	if p.State == "Treated" then
		treatAndRecover(p)
	elseif p.State == "Sad" then
		sadLeave(p)
	elseif p.State == "Cured" then
		curedOnSpot(p) -- a 💫 Miracle cured it in line
	end
end

local function run(p: Patient)
	local ok, err = pcall(visit, p)
	if not ok then
		report("patient visit", err)
		removePatient(p)
	end
end

------------------------------------------------------------------------------------------------------------------
-- Who comes next
------------------------------------------------------------------------------------------------------------------

-- Sparkly, Frosty in winter and (Progression v2) 🌟 Golden at an R3+ clinic (Pure.variant). The Studio test switch
-- workspace:SetAttribute("ForceGoldenPatient", true) makes every new patient at an R3+ clinic Golden; a live server
-- ignores it.
local function rollVariant(state: PlotState): string?
	local force = RunService:IsStudio() and Workspace:GetAttribute("ForceGoldenPatient") == true
	local golden = rawget(VariantsData :: any, "Golden")
	local goldenRebirths = if type(golden) == "table" and type(golden.Rebirths) == "number"
		then golden.Rebirths
		else math.huge
	return Pure.variant(
		state.Rebirths,
		{ rng:NextNumber(), rng:NextNumber(), rng:NextNumber() },
		Workspace:GetAttribute("IsWinter") == true,
		force,
		Config,
		goldenRebirths
	)
end

-- Night patients come at night; with 🦉 Night Owl (the owner's perk) for Config.NightOwl of a night after morning.
local function nightOpen(state: PlotState): boolean
	if Workspace:GetAttribute("IsNight") == true then
		return true
	end
	return state.Effects.NightOwl and Hospital.nightOwl(nightEndedAt, os.clock(), Config)
end

local function patienceFor(owner: Player, guest: boolean): number
	local data = PlayerData.get(owner)
	local chairs = if data then data.Upgrades.Chairs or 0 else 0
	local ok, seconds = pcall(Prices.patience, chairs, Config)
	local base = if ok and type(seconds) == "number" and seconds > 0 then seconds else Config.PatienceSeconds
	-- >>> playtime branch: the owner's Patience boosts (badge tiers, Server/Boosts)
	local boostOk, boost = pcall(Boosts.multiplier, owner, "Patience")
	if boostOk and type(boost) == "number" and boost >= 1 and boost < math.huge then
		base *= boost
	end
	-- <<< playtime branch
	return base * (if guest then GUEST_PATIENCE else 1)
end

-- The effective recipe a patient (or a regular) would need at this clinic: its ailment's Recipe, or the regular's
-- own, cut to `cap` items. nil when its ailment is unknown.
local function recipeOf(patientId: string, regular: string?, cap: number): { string }?
	local entry = rawget(PatientsData :: any, patientId)
	local regularEntry = if regular then rawget(RegularsData :: any, regular) else nil
	local ailmentId = if regularEntry then regularEntry.Ailment elseif entry then entry.Ailment else nil
	local ailment = if type(ailmentId) == "string" then rawget(AilmentsData :: any, ailmentId) else nil
	local station = if ailment then rawget(StationsData :: any, ailment.Station) else nil
	if not (ailment and station and rawget(ItemsData :: any, station.Item)) then
		return nil
	end
	local full = if regularEntry then regularEntry.Recipe else ailment.Recipe
	return Pure.recipeFor(full, station.Item, cap)
end

-- What the owner's clinic can make: { [ItemId]: true } for every station on the plot.
local function itemsMadeOn(stations: { [string]: boolean }): { [string]: boolean }
	local items: { [string]: boolean } = {}
	for stationId in stations do
		local station = rawget(StationsData :: any, stationId)
		if station then
			items[station.Item] = true
		end
	end
	return items
end

-- How many items recipes have at this owner's clinic: their hospital level's cap, and 1 all through the tutorial.
local function recipeCapFor(owner: Player): number
	if tutorialAsk("active", false, owner) then
		return 1
	end
	return levelAsk("recipeCap", owner, 1)
end

-- True when the patient came. `urgent` (Progression v2): a 🚑/🚁 patient, with its own recipe and arrival spot.
local function spawnPatient(
	state: PlotState,
	patientId: string,
	regular: string?,
	visitor: boolean,
	variant: string?,
	cap: number,
	urgent: UrgentSpawn?
): boolean
	local entry = PatientsData[patientId]
	local regularEntry = if regular then RegularsData[regular] else nil
	local ailmentId = if regularEntry then regularEntry.Ailment elseif entry then entry.Ailment else nil
	local ailment = if ailmentId then AilmentsData[ailmentId] else nil
	local station = if ailment then StationsData[ailment.Station] else nil
	local recipe = if urgent then urgent.Recipe else recipeOf(patientId, regular, cap)
	if not (ailment and station and ItemsData[station.Item] and recipe and #recipe > 0) then
		return false
	end

	local ok, built = pcall(CreatureBuilder.build, patientId, variant)
	if not ok or typeof(built) ~= "Instance" or not built:IsA("Model") then
		report("CreatureBuilder.build", built)
		return false
	end
	local model: Model = built
	local root = model.PrimaryPart
	local badge = CreatureBuilder.badge(model)
	if not root or not badge then
		model:Destroy()
		return false
	end

	-- Night patients, and Night-wing regulars (they only visit at night): glow, pay 2x, count for night goals.
	local night = (entry ~= nil and entry.Night == true) or (regularEntry ~= nil and regularEntry.Wing == "Night")
	local patience = patienceFor(state.Owner, regular ~= nil or visitor)
	local urgentKind = if urgent then urgent.Kind else ""
	if urgent then
		local data = PlayerData.get(state.Owner)
		patience = Pure.urgentPatience(patience, urgentKind, if data then data.Upgrades.AESpeed or 0 else 0, Config)
	end
	local wing = if regularEntry then regularEntry.Wing elseif entry then entry.Wing else "Starter"
	local air = urgent ~= nil and urgent.Air
	local rhythm = rng:NextNumber(0.9, 1.12) -- every creature hops to its own beat
	local start = if urgent then urgent.Start else markerGround(state.Plot.Spawn)
	local p: Patient = {
		Plot = state,
		PatientId = patientId,
		Regular = regular,
		Visitor = visitor,
		Variant = variant,
		Night = night,
		AilmentIcon = ailment.Icon,
		Station = ailment.Station,
		Item = station.Item,
		Recipe = recipe,
		Done = Recipe.newDone(recipe),
		TipPaid = 0,
		Session = nil,
		SessionHelper = nil,
		SessionIndices = nil,
		SessionCarried = nil,
		Model = model,
		Root = root,
		Badge = badge,
		BaseScale = model:GetScale(),
		HopHeight = HOP_HEIGHT * (if night then 1.35 else 1), -- night patients float a little
		HopSeconds = HOP_SECONDS * rhythm * (if night then 1.15 else 1),
		State = "Queue",
		Arrived = false,
		Claimed = false,
		Patience = patience,
		PatienceMax = patience,
		PatienceLeft = 1,
		PatienceShown = 1,
		RingStep = -1,
		RingColor = nil,
		NextIdle = 0,
		Helper = nil,
		Bed = nil,
		InBed = false,
		Pivot = start,
		ScaleAnim = nil,
		Tilt = 0,
		Thread = nil,
		Wing = wing,
		Urgent = urgentKind,
		Incoming = air,
		ArriveFloor = if urgent then urgent.Floor else 0,
		Dept = Hospital.route(wing, urgentKind, state.Level, LevelsData),
		SpotKind = "Place",
		Floor = 0,
		Upstairs = air and urgent ~= nil and urgent.Floor > 0,
		Escorted = false,
		Porter = nil,
		HasLift = false,
		Triage = nil,
		TriageBonus = false,
		RecoverIn = "Reception",
		Soaking = false,
		SoakDone = false,
		SoakSession = nil,
	}

	CreatureBuilder.setMood(model, "Sick")
	showRing(p, 1, RING_CALM)
	badge.Star.Visible = visitor
	-- Progression v2: the 🚑/🚁 chip and rim, the department chip once there's a floor to pick (Lv 3+), the 🌟 sheen.
	local okBadge, badgeErr = pcall(function()
		CreatureBuilder.setUrgent(badge, urgentKind)
		CreatureBuilder.setDept(badge, if Hospital.triageOptions(state.Level, LevelsData) then p.Dept else nil)
		if variant == "Golden" then
			CreatureBuilder.setEffect(model, "Golden", true)
		end
	end)
	if not okBadge then
		report("the v2 badge", badgeErr)
	end
	if regular then
		local okBeat, beat = pcall(Story.bubble, state.Owner, regular)
		if okBeat and type(beat) == "table" and type(beat.Emote) == "string" then
			local text = if type(beat.Bubble) == "string" then beat.Bubble else ""
			badge.BubbleEmote.Text = beat.Emote
			badge.BubbleText.Text = text
			badge.BubbleText.Visible = text ~= ""
			badge.Bubble.Enabled = true
		elseif not okBeat then
			report("Story.bubble", beat)
		end
	end

	model.Name = "Patient_" .. patientId
	model:SetAttribute("Kind", if regular then "Regular" elseif visitor then "Visitor" else "Patient")
	model:SetAttribute("Regular", regular) -- Story looks for its regular on the plot by this (or PatientId)
	model:SetAttribute("Ailment", ailmentId)
	showRecipe(p) -- Recipe, RecipeDone, Item, Station and the badge
	model:SetAttribute("Variant", variant)
	model:SetAttribute("Night", night)
	model:SetAttribute("State", "Arriving")
	model:SetAttribute("PatienceFraction", 1)
	model:SetAttribute("Urgent", urgentKind) -- Progression v2 (§B4): "" | "AE" | "VIP"
	model:SetAttribute("Dept", p.Dept) -- where it will recover: "Wards" | "Hydro"
	model:SetAttribute("Escorted", false)
	-- PivotTo, not root.CFrame: the model isn't in Workspace yet, so its welds aren't live and the body would stay
	-- behind at the origin (each weld then locks in that gap when the model is parented in).
	model:PivotTo(start)
	model:ScaleTo(p.BaseScale * 0.15) -- pops in from tiny
	if air then
		badge.Gui.Enabled = false -- shown when it steps out of the helicopter (visit)
	end
	model.Parent = state.Plot.Model:FindFirstChild("Patients") or state.Plot.Model

	state.All[p] = true
	if air then
		-- A 🚁 VIP isn't in the line until it reaches the ground, but its place is kept (Config.MaxQueue holds).
		state.Incoming += 1
		model:SetAttribute("QueueIndex", 0)
	elseif urgent then
		insertUrgent(state, p) -- a 🚑 patient goes to the front
	else
		table.insert(state.Queue, p)
		model:SetAttribute("QueueIndex", #state.Queue)
	end
	state.Spawned += 1
	state.LastPatient = patientId
	local thread = coroutine.create(run)
	p.Thread = thread
	task.spawn(thread, p)
	return true
end

local function hasGuest(state: PlotState, regular: string?, visitor: boolean): boolean
	for p in state.All do
		if (regular ~= nil and p.Regular == regular) or (visitor and p.Visitor) then
			return true
		end
	end
	return false
end

-- The tutorial's patient for `plan` ("First" | "Second"): a Starter-wing day patient whose ailment the plan's
-- station treats, when that station is on the plot. A new Book page first. nil = there's none here.
local function tutorialPatient(plan: string, stations: { [string]: boolean }, data: Types.Data): string?
	local stationId = TUTORIAL_STATION[plan]
	if not stationId or not stations[stationId] then
		return nil
	end
	local fresh: { string }, seen: { string } = {}, {}
	for _, patientId in PatientsData.Order do
		local entry = PatientsData[patientId]
		local ailment = AilmentsData[entry.Ailment]
		if entry.Wing == TUTORIAL_WING and not entry.Night and ailment and ailment.Station == stationId then
			local page = data.Book[patientId]
			table.insert(if page and page.Cured > 0 then seen else fresh, patientId)
		end
	end
	local pick = if #fresh > 0 then fresh else seen
	if #pick == 0 then
		return nil
	end
	return pick[rng:NextInteger(1, #pick)]
end

-- `plan` is the owner's Tutorial.spawnPlan: "First" | "Second" | "Any" | "Normal" (never "Wait" here).
local function trySpawn(state: PlotState, plan: string)
	local owner = state.Owner
	local data = PlayerData.get(owner)
	if not data then
		return
	end
	local stations = stationsOnPlot(state.Plot)
	local makes = itemsMadeOn(stations)
	local isNight = nightOpen(state) -- night patients (and 🦉 Night Owl's after morning)

	-- 0. The tutorial's own two patients (no variant: nothing to explain yet). One item, always.
	if plan == "First" or plan == "Second" then
		local patientId = tutorialPatient(plan, stations, data)
		if plan == "Second" then
			state.SecondSpawned = true -- (a clinic without the 🩹 station skips it: the usual pool, below)
		end
		if patientId then
			spawnPatient(state, patientId, nil, false, nil, 1)
			return
		end
	end
	local guests = plan == "Normal" -- regulars and Today's Visitor wait until the tutorial is done
	local cap = recipeCapFor(owner)

	local function treatable(ailmentId: string): boolean
		local ailment = AilmentsData[ailmentId]
		return ailment ~= nil and stations[ailment.Station] == true
	end
	-- Every item of the recipe it would need here can be made at this clinic.
	local function makeable(patientId: string, regular: string?): boolean
		local recipe = recipeOf(patientId, regular, cap)
		return recipe ~= nil and Recipe.makeable(recipe, makes)
	end
	local function eligible(patientId: string): boolean
		local entry = PatientsData[patientId]
		if not entry or not treatable(entry.Ailment) or not makeable(patientId, nil) then
			return false
		end
		-- Progression v2: 🌻 Sunny from R1 (with whatever stations you have); 🚁 Sky only by air ambulance.
		if not Pure.wingOpen(rawget(WingsData :: any, entry.Wing), state.Rebirths, false) then
			return false
		end
		if entry.Night and not isNight then
			return false
		end
		return entry.Wing ~= "Winter" or data.Rooms.WinterWing == true
	end

	-- 1. A regular whose story beat is due (never the very first patient: that one teaches the loop). Story
	--    reserves whoever it names, so it's only asked when there's room in line, and whoever it names comes.
	--    Story also keeps one regular per plot and the gap between them.
	if guests and state.Spawned >= 1 then
		local ok, regular = pcall(Story.dueRegular, owner)
		if not ok then
			report("Story.dueRegular", regular)
		elseif type(regular) == "string" then
			local entry = RegularsData[regular]
			if not (entry and treatable(entry.Ailment) and makeable(entry.Patient, regular)) then
				report("regular " .. regular, "named by Story but can't be treated here")
			elseif not hasGuest(state, regular, false) then -- (Story never names one who's already here)
				spawnPatient(state, entry.Patient, regular, false, nil, cap)
				return
			end
		end
	end

	-- 2. Today's Visitor. Only asked for when it can be treated here, so it's never handed out and wasted.
	if guests and state.Spawned >= 2 and not hasGuest(state, nil, true) then
		local todays = Workspace:GetAttribute("TodaysVisitor")
		if type(todays) == "string" and todays ~= "" and eligible(todays) then
			local ok, visitor = pcall(Daily.visitorFor, owner)
			if not ok then
				report("Daily.visitorFor", visitor)
			elseif type(visitor) == "string" and eligible(visitor) then
				spawnPatient(state, visitor, nil, true, rollVariant(state), cap)
				return
			end
		end
	end

	-- 3. Anyone treatable here, weighted toward night patients at night and toward new Book pages.
	local pool: { { Id: string, Weight: number } } = {}
	local total = 0
	for _, patientId in PatientsData.Order do
		if eligible(patientId) then
			local entry = PatientsData[patientId]
			local weight = if entry.Night then NIGHT_WEIGHT else 1
			local page = data.Book[patientId]
			if not page or page.Cured <= 0 then
				weight *= NEW_PAGE_WEIGHT
			end
			if patientId == state.LastPatient then
				weight *= REPEAT_WEIGHT
			end
			total += weight
			table.insert(pool, { Id = patientId, Weight = weight })
		end
	end
	if total <= 0 then
		return
	end
	local roll = rng:NextNumber() * total
	local chosen = pool[#pool].Id
	for _, option in pool do
		roll -= option.Weight
		if roll <= 0 then
			chosen = option.Id
			break
		end
	end
	spawnPatient(state, chosen, nil, false, rollVariant(state), cap)
end

------------------------------------------------------------------------------------------------------------------
-- Progression v2: urgent patients (🚑 A&E from Lv 2, 🚁 the air ambulance from R2 at Lv 5)
------------------------------------------------------------------------------------------------------------------

-- A 🚑/🚁 patient waits here already (in line, or on its way to it): only one at a time comes by itself.
local function urgentWaiting(state: PlotState): boolean
	for p in state.All do
		if p.Urgent ~= "" and (p.Incoming or p.State == "Queue") then
			return true
		end
	end
	return false
end

-- Calls an urgent patient: "AE" (an ambulance: it pops out at the parked Ambulance's StretcherSpot) or "VIP" (the
-- air ambulance: it steps out at HeliSpot on the roof). The pick: any patient whose ailment this clinic treats and
-- whose wing may come by that way (Pure.wingOpen; 🚁 brings only the Sky wing), with an urgent recipe this clinic can
-- make (Pure.urgentFor). Sets ArriveAt on the Ambulance / HeliSpot for Feel/HospitalFX. True = it came.
local function callUrgent(state: PlotState, kind: string): boolean
	local owner = state.Owner
	local data = PlayerData.get(owner)
	if not data then
		return false
	end
	local stations = stationsOnPlot(state.Plot)
	local makes = itemsMadeOn(stations)
	local cap = recipeCapFor(owner)
	local minItems = math.max(1, math.floor(tonumber(Config.AE.MinItems) or 2))
	local byAir = kind == "VIP"
	local night = nightOpen(state)
	local pool: { { Id: string, Recipe: { string } } } = {}
	for _, patientId in PatientsData.Order do
		local entry = PatientsData[patientId]
		local ailment = AilmentsData[entry.Ailment]
		if
			ailment
			and stations[ailment.Station] == true
			and Pure.wingOpen(rawget(WingsData :: any, entry.Wing), state.Rebirths, byAir)
			and (byAir or not entry.Night or night)
			and (entry.Wing ~= "Winter" or data.Rooms.WinterWing == true)
		then
			local recipe = Pure.urgentFor(ailment.Recipe, makes, cap, minItems)
			if recipe then
				table.insert(pool, { Id = patientId, Recipe = recipe })
			end
		end
	end
	if #pool == 0 then
		return false
	end
	local choice = pool[rng:NextInteger(1, #pool)]
	local start = markerGround(state.Plot.Spawn) -- no bay or helipad (a kit building): in by the gate
	local floor = 0
	local serverNow = Workspace:GetServerTimeNow()
	if kind == "AE" then
		local stretcher = buildingPart(state, "StretcherSpot")
		if stretcher then
			start = standAt(state, stretcher.CFrame)
		end
		local building = state.Plot.Model:FindFirstChild("Building")
		local ambulance = building and building:FindFirstChild("Ambulance", true)
		if ambulance then
			ambulance:SetAttribute("ArriveAt", serverNow) -- Feel/HospitalFX: lights and a siren
		end
	else
		local heli = buildingPart(state, "HeliSpot")
		if heli then
			heli:SetAttribute("ArriveAt", serverNow) -- Feel/HospitalFX: the helicopter flies in and lands
			local roof = floorOf(heli, state.Plot.Model)
			if roof == 0 then
				roof = Hospital.floors(state.Level, LevelsData) -- the roof is the top floor (Data/Levels Floors)
			end
			if roof > 0 and landingOf(state.Plot, roof) and landingOf(state.Plot, 0) then
				start, floor = standAt(state, heli.CFrame), roof
			end
		end
	end
	return spawnPatient(state, choice.Id, nil, false, rollVariant(state), cap, {
		Kind = kind,
		Recipe = choice.Recipe,
		Start = start,
		Air = byAir,
		Floor = floor,
	})
end

-- The ambulance and helicopter timers. Each comes about every so often (Pure.aeSeconds / Pure.vipSeconds; the first
-- ambulance Config.AE.FirstSeconds after the clinic reaches Lv 2), only while the owner stands at their clinic, is
-- done with the tutorial, the line has room and no other 🚑/🚁 patient waits. An admin's call comes as soon as the
-- line has room.
local function tickUrgent(state: PlotState, now: number, maxQueue: number)
	local room = #state.Queue + state.Incoming < maxQueue
	local forced = state.ForceUrgent[1]
	if forced then
		if room then
			table.remove(state.ForceUrgent, 1)
			callUrgent(state, forced)
		end
		return
	end
	local aeOpen = state.Level >= AE_LEVEL
	local vipOpen = state.Level >= HELI_LEVEL and RebirthLogic.has(state.Rebirths, "Helicopter")
	if not aeOpen then
		state.NextAE = now + Config.AE.FirstSeconds
	end
	if not vipOpen then
		state.NextVIP = now + Pure.vipSeconds(Config, rng:NextNumber())
	end
	if not room or not (aeOpen or vipOpen) then
		return
	end
	if tutorialAsk("active", false, state.Owner) or urgentWaiting(state) or not ownerAtClinic(state) then
		return
	end
	if aeOpen and now >= state.NextAE then
		local data = PlayerData.get(state.Owner)
		local aeSpeed = if data then data.Upgrades.AESpeed or 0 else 0
		state.NextAE = now + Pure.aeSeconds(Config, rng:NextNumber(), aeSpeed, state.Effects.SirenPro)
		callUrgent(state, "AE")
	elseif vipOpen and now >= state.NextVIP then
		state.NextVIP = now + Pure.vipSeconds(Config, rng:NextNumber())
		callUrgent(state, "VIP")
	end
end

------------------------------------------------------------------------------------------------------------------
-- The clinic's heartbeat: patience and arrivals
------------------------------------------------------------------------------------------------------------------

-- Progression v2: what the plot's patients use from the owner's save and the nurses, once a tick.
local function refreshPlot(state: PlotState)
	local owner = state.Owner
	state.Level = levelAsk("level", owner, 1)
	state.Rebirths = rebirthsOf(owner)
	state.Effects = effectsOf(owner)
	state.Team = teamOf(state.Plot)
	state.Medic = medicOf(state.Plot)
	state.Receptionist = receptionOf(state.Plot)
end

local function makeSad(state: PlotState, p: Patient)
	if p.State ~= "Queue" then
		return
	end
	p.State = "Sad"
	removeFromQueue(state, p)
	local regular = p.Regular
	local storyLeft = (Story :: any).left -- a regular who leaves uncured comes back later (Story's extra)
	if regular and type(storyLeft) == "function" then
		local ok, err = pcall(storyLeft, state.Owner, regular)
		if not ok then
			report("Story.left", err)
		end
	end
end

local function tickPatience(state: PlotState, dt: number)
	if tutorialAsk("calm", false, state.Owner) then
		return -- the tutorial's steps 1-6: nobody runs out of patience, so the ring stays full
	end
	if state.PausedUntil > os.clock() or abilityPaused(state.Plot) then
		return -- 🎵 a Calm Song (Abilities PauseLine): every patience ring holds still
	end
	local outOfPatience: { Patient } = {}
	-- A Cheerer on duty (Server/Nurses keeps the plot's CheerPatience) makes everyone's patience last longer.
	local cheer = Pure.cheer(state.Plot.Model:GetAttribute("CheerPatience"), MAX_CHEER_PATIENCE)
	-- 🚑/🚁 patients drain slower with the A&E team and a Medic on duty (Progression v2).
	local slower = Pure.slower(state.Team.Urgent, state.Medic, MAX_SLOWER)
	for index, p in state.Queue do
		if p.State == "Queue" and p.Arrived and not p.Claimed and not p.Session then -- paused mid-mini-game
			local rate = (if index == 1 then 1 else QUEUE_PATIENCE_RATE)
				/ cheer
				/ (if p.Urgent ~= "" then slower else 1)
			p.Patience = math.max(p.Patience - dt * rate, 0)
			local fraction = p.Patience / p.PatienceMax
			showRing(p, fraction, ringColor(fraction))
			showPatience(p, fraction)
			if p.Patience <= 0 then
				table.insert(outOfPatience, p)
			end
		end
	end
	for _, p in outOfPatience do
		makeSad(state, p)
	end
end

local function tick(state: PlotState, now: number, dt: number)
	refreshPlot(state)
	tickPatience(state, dt)
	local cap = tutorialAsk("queueCap", nil, state.Owner)
	-- The hospital level's line, never longer than Config.MaxQueue (3: one being treated + 2 waiting, on the lane's
	-- three numbered spots). A higher level refills it sooner (spawnSeconds), it doesn't make it longer. A 🚁 VIP on
	-- its way down keeps its place (state.Incoming).
	local levelCap = math.min(Config.MaxQueue, levelAsk("queueCap", state.Owner, Config.MaxQueue))
	local maxQueue = if type(cap) == "number" then math.min(cap, levelCap) else levelCap
	tickUrgent(state, now, maxQueue)
	if now >= state.NextSpawn and #state.Queue + state.Incoming < maxQueue then
		local forced = table.remove(state.Forced, 1)
		-- A higher hospital level gets patients faster (Data/Levels SpawnSeconds, Lv 1 = Config.SpawnEverySeconds):
		-- the level's throughput. The line itself never grows past Config.MaxQueue (maxQueue above). Progression v2:
		-- 🚪 Busy Doors and a Receptionist on duty make them come sooner still (Logic/Hospital.arrival).
		local every = Hospital.arrival(
			levelAsk("spawnSeconds", state.Owner, Config.SpawnEverySeconds),
			{ state.Effects.Arrive, state.Receptionist.Arrive }
		)
		if forced then
			-- An admin's pick (Patients.sendNext) comes first; more picks follow REFILL_SECONDS apart.
			state.NextSpawn = now + (if #state.Forced > 0 then REFILL_SECONDS else every * rng:NextNumber(0.85, 1.15))
			spawnPatient(state, forced, nil, false, nil, recipeCapFor(state.Owner))
		else
			local plan = tutorialAsk("spawnPlan", "Normal", state.Owner, next(state.All) == nil, state.SecondSpawned)
			-- A spawn the tutorial holds back keeps its turn, so the patient comes the moment the tutorial is ready.
			if plan ~= "Wait" then
				state.NextSpawn = now + every * rng:NextNumber(0.85, 1.15)
				trySpawn(state, if type(plan) == "string" then plan else "Normal")
			end
		end
	end
	refreshFront(state)
end

local function plotLoop(state: PlotState)
	local last = os.clock()
	while state.Active do
		task.wait(TICK)
		if not state.Active then
			return
		end
		if state.Owner.Parent ~= Players then
			deactivate(state.Plot) -- belt and braces: PlotReleased normally does this first
			return
		end
		local now = os.clock()
		local ok, err = pcall(tick, state, now, math.min(now - last, 1))
		last = now
		if not ok then
			report("clinic tick", err)
		end
	end
end

------------------------------------------------------------------------------------------------------------------
-- Treating at the Counter
------------------------------------------------------------------------------------------------------------------

local function nearCounter(player: Player, state: PlotState): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	local holder = state.Prompt.Parent
	local at = if holder and holder:IsA("Attachment") then holder.WorldPosition else state.Plot.Counter.Position
	return (root.Position - at).Magnitude <= PROMPT_DISTANCE + DISTANCE_SLACK
end

-- The recipe is complete. Progression v2: where it goes (Logic/Hospital.route at today's level) and where it rests
-- (Pure.destination), reserved now so two patients never take one spot; then the floor pick (Pure.triageMode): a
-- Receptionist sends it at once with the bonus, or the helper whose session (`session`) finished it picks
-- (Treatment.waitTriage; the TriageAsk goes back to Treatment for the client's buttons). It stays at its place in
-- line until it walks off (treatAndRecover), so the line waits for the pick.
local function beginTreatment(state: PlotState, p: Patient, helper: Player, session: number?): Treatment.TriageAsk?
	p.Helper = helper
	p.PatienceLeft = math.clamp(p.Patience / p.PatienceMax, 0, 1)
	p.State = "Treated"
	p.Dept = Hospital.route(p.Wing, p.Urgent, state.Level, LevelsData)
	p.Model:SetAttribute("Dept", p.Dept)
	local spots = freeSpots(state)
	local kind = Pure.destination(p.Dept, {
		Tub = spots.Tub ~= nil,
		Ground = spots.Ground ~= nil,
		Upstairs = spots.Upstairs ~= nil,
	})
	local spot = if kind == "Tub" then spots.Tub elseif kind == "Ground" then spots.Ground else spots.Upstairs
	if kind ~= "Place" and spot then
		state.Beds[spot] = p
		p.Bed = spot
		p.SpotKind = kind
		p.Floor = floorOf(spot, state.Plot.Model)
	else
		p.SpotKind = "Place" -- every spot taken: it rests where it stands, as before
	end
	local options = Hospital.triageOptions(state.Level, LevelsData)
	local okSimple, simple = pcall(Treatment.simple, helper)
	local mode = Pure.triageMode(
		options,
		state.Receptionist.Triage,
		session ~= nil,
		Pure.routed(p.Dept, p.SpotKind),
		okSimple and simple == true
	)
	local ask: Treatment.TriageAsk? = nil
	if mode == "Instant" then
		p.TriageBonus = true -- a Receptionist sent it the right way
	elseif mode == "Ask" and options and session then
		p.Triage = { Helper = helper, Session = session, Options = options, Right = p.Dept }
		ask = { Options = table.clone(options), Right = p.Dept }
	end
	-- Instant feedback; the patient's own thread picks up the walk to bed after its current hop.
	setState(p, "Treated")
	p.Badge.Icon.Text = ICON_TREATED
	p.Badge.Need.Visible = false
	p.Badge.Bubble.Enabled = false
	showRing(p, 0, RING_HEAL)
	CreatureBuilder.setMood(p.Model, "Happy")
	refreshFront(state)
	tutorialHook("onTreated", state.Owner)
	return ask
end

-- Recipe items were given (a mini-game settled, or a nurse delivered): tick them off and refill some patience,
-- then off to bed when the recipe is complete, or back in line for the rest. Never yields. True = complete (and the
-- floor pick to ask, when the helper's session `session` finished it).
local function giveItems(
	state: PlotState,
	p: Patient,
	indices: { number },
	helper: Player,
	session: number?
): (boolean, Treatment.TriageAsk?)
	p.Done = Recipe.apply(p.Done, indices)
	p.Patience = Pure.refill(p.Patience, p.PatienceMax, ITEM_PATIENCE, #indices)
	showRecipe(p)
	if Recipe.complete(p.Recipe, p.Done) then
		return true, beginTreatment(state, p, helper, session)
	end
	local fraction = p.Patience / p.PatienceMax
	showRing(p, fraction, ringColor(fraction))
	p.NextIdle = 0 -- a happy little hop straight away (its own thread does it)
	setState(p, lineState(p))
	refreshFront(state)
	return false, nil
end

-- Treatment settled the session on `p` (the player's report, the timeout, or the helper leaving).
local function settleTreat(p: Patient, sessionId: number, tip: number): (boolean, Treatment.TriageAsk?)
	if p.Session ~= sessionId then
		return false, nil -- dropped already (the patient went away)
	end
	local helper = p.SessionHelper
	local indices = p.SessionIndices or {}
	p.Session = nil
	p.SessionHelper = nil
	p.SessionIndices = nil
	p.SessionCarried = nil
	if not alive(p) or p.State ~= "Queue" then
		return false, nil
	end
	p.TipPaid += math.max(0, tip)
	local state = p.Plot
	return giveItems(state, p, indices, helper or state.Owner, sessionId)
end

-- Nothing in hand (or in the nurse tray) fits: a head-shake, and the station that makes the next missing item.
local function refuse(p: Patient, player: Player, emptyHanded: boolean)
	CreatureBuilder.shake(p.Model) -- drawn on the clients
	local station = rawget(StationsData :: any, p.Station)
	local stationIcon = if station then station.Icon else "❔"
	local hint = if emptyHanded then "Make " .. stationIcon .. " first!" else "Oops! This one needs " .. stationIcon
	Remotes.toast(player, hint)
end

local function onTreat(plot: Plot, player: Player)
	local state = active[plot]
	if not state or not state.Active then
		return
	end
	local now = os.clock()
	if now - (lastTreat[player] or 0) < TREAT_COOLDOWN then
		return
	end
	lastTreat[player] = now
	if not Plots.canWork(player, plot) then
		Remotes.toast(player, "🔒 Ask the owner to open up!")
		return
	end
	if not nearCounter(player, state) then
		return
	end
	local candidates = frontCandidates(state) -- the front patient (both front ones with 👯 Twin Counters)
	if #candidates == 0 then
		return
	end
	if Treatment.busy(player) then
		return -- one mini-game at a time
	end

	-- What fits: the helper's own items first, then the nurse tray's. A carried medicine fills every slot its two
	-- ingredients cover, as one game (Pure.plan with Data/Items). Twin Counters: the first of the two front
	-- patients whose missing items you carry, else the first the tray fits (Pure.pickTwin).
	local carried = carrying(player)
	local tray = trayItems(plot)
	local plans: { TreatPlan } = {}
	for index, candidate in candidates do
		local fromCarry, fromTray, carryUsed, trayUsed =
			Pure.plan(candidate.Recipe, candidate.Done, carried, tray, ItemsData)
		plans[index] = {
			Carry = #fromCarry,
			Tray = #fromTray,
			CarryIdx = fromCarry,
			TrayIdx = fromTray,
			CarryUsed = carryUsed,
			TrayUsed = trayUsed,
		}
	end
	local pick = Pure.pickTwin(plans)
	if not pick then
		refuse(candidates[1], player, #carried == 0)
		return
	end
	local p = candidates[pick]
	local plan = plans[pick]

	-- Take them: they're spent now (the mini-game can't fail). Nothing yields between the check and the take.
	p.Claimed = true
	local taken: { string } = {}
	local fromTrayTaken: { string } = {}
	local tookAll = true
	for _, itemId in plan.CarryUsed do
		if takeItem(player, itemId) then
			table.insert(taken, itemId)
		else
			tookAll = false
			break
		end
	end
	if tookAll then
		for _, itemId in plan.TrayUsed do
			if takeFromTray(plot, itemId) then
				table.insert(fromTrayTaken, itemId)
			else
				tookAll = false
				break
			end
		end
	end
	p.Claimed = false
	local function keepYourItems()
		for _, itemId in taken do
			giveBack(player, itemId)
		end
	end
	if not tookAll or not (alive(p) and p.State == "Queue" and table.find(state.Queue, p) and not p.Session) then
		keepYourItems() -- the patient moved on while we checked
		return
	end

	local given: { number } = table.clone(plan.CarryIdx)
	for _, index in plan.TrayIdx do
		table.insert(given, index)
	end
	table.sort(given)
	local items: { string } = table.clone(taken) -- one mini-game per item given (a medicine is one 🧪 Pour)
	local medicines: { string } = {}
	for _, itemId in fromTrayTaken do
		table.insert(items, itemId)
	end
	for _, itemId in items do
		local row = rawget(ItemsData :: any, itemId)
		if type(row) == "table" and row.Medicine ~= nil then
			table.insert(medicines, itemId)
		end
	end
	local sessionId: number? = nil
	local spec: Treatment.Spec = {
		Plot = plot,
		PatientId = p.PatientId,
		Kind = "Treat",
		Items = items,
		Medicines = medicines,
		Position = p.Root.Position + Vector3.new(0, 3 * p.BaseScale, 0),
		Counter = plot.Counter.Position,
		TipSoFar = p.TipPaid,
		Settle = function(_ratings: { Types.Rating }, tip: number): (boolean, Treatment.TriageAsk?)
			local id = sessionId
			if id == nil then
				return false, nil
			end
			return settleTreat(p, id, tip)
		end,
	}
	local ok, opened = pcall(Treatment.open, player, spec)
	if not ok or type(opened) ~= "number" then
		if not ok then
			report("Treatment.open", opened)
		end
		keepYourItems()
		return
	end
	sessionId = opened
	p.Session = opened
	p.SessionHelper = player
	p.SessionIndices = given
	p.SessionCarried = taken
	setState(p, "Treating")
	refreshFront(state)
end

-- A nurse is ready (Nurses.Heal via Treatment.onHeal): a Healer (target "Front") serves the front patient (or #2
-- with Twin Counters), a Medic (target "Urgent", Progression v2) the 🚑/🚁 patient waiting anywhere in line. It gets
-- what the nurse tray holds for it (a medicine fills both its slots), rated OK, with no tip and no combo change
-- (players still beat nurses with Perfects). The owner is the helper, so the cure is theirs; nobody is asked to
-- triage (a Receptionist still sends it with the bonus). Returns the items given (Treatment then tells
-- Nurses.healed).
local function healFront(plotArg: any, _nurseId: string, target: string?): { string }
	local plot: Plot? = if typeof(plotArg) == "Instance" then Plots.fromInstance(plotArg) else plotArg
	if not plot then
		return {}
	end
	local state = active[plot]
	if not state or not state.Active or state.Owner.Parent ~= Players then
		return {}
	end
	local candidates: { Patient } = {}
	if target == "Urgent" then
		for _, p in state.Queue do
			if p.Urgent ~= "" and ready(p) then
				table.insert(candidates, p)
			end
		end
	else
		candidates = frontCandidates(state)
	end
	local tray = trayItems(plot)
	for _, p in candidates do
		local indices, used = Recipe.match(p.Recipe, p.Done, tray, ItemsData)
		if #indices > 0 then
			local items: { string } = {}
			for _, itemId in used do
				if not takeFromTray(plot, itemId) then
					return {} -- the tray changed under us (never, without a yield): nothing is given
				end
				table.insert(items, itemId)
			end
			giveItems(state, p, indices, state.Owner, nil)
			return items
		end
	end
	return {}
end

-- The clinic is closing mid-mini-game: if the items in it finish the recipe, the patient counts as treated (so
-- settleEarly cures it now); otherwise a helper who is staying gets their own items back (never the owner: the
-- clinic closes because they're leaving). Either way the session closes.
local function closeSessionEarly(p: Patient)
	local indices = p.SessionIndices
	if not p.Session or not indices then
		return
	end
	local done = Recipe.apply(p.Done, indices)
	if p.State == "Queue" and Recipe.complete(p.Recipe, done) then
		p.Done = done
		p.Helper = p.SessionHelper
		p.PatienceLeft = math.clamp(p.Patience / p.PatienceMax, 0, 1)
		p.State = "Treated"
		dropSession(p, false)
	else
		local helper = p.SessionHelper
		dropSession(p, helper ~= nil and helper ~= p.Plot.Owner and helper.Parent == Players)
	end
end

------------------------------------------------------------------------------------------------------------------
-- Progression v2: the Hydro hot tub's 🫧 game, and abilities acting on the line
------------------------------------------------------------------------------------------------------------------

-- The plot's hot-tub prompt (PlotBuilder builds Building...HotTub.SoakPrompt, disabled), or nil below Lv 3.
local function soakPrompt(state: PlotState): ProximityPrompt?
	local building = state.Plot.Model:FindFirstChild("Building")
	local tub = building and building:FindFirstChild("HotTub", true)
	local prompt = tub and tub:FindFirstChild("SoakPrompt", true)
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
end

-- A soaking patient whose 🫧 game nobody has played yet (and nobody is playing).
local function soakTarget(state: PlotState): Patient?
	for p in state.All do
		if p.Soaking and not p.SoakDone and not p.SoakSession and p.State ~= "Gone" then
			return p
		end
	end
	return nil
end

-- 🫧 The SoakPrompt: ONE Scrub game for a soaking patient (Treatment.open Kind "Soak"): a tip only, sharing the
-- patient's TipCapPerCure. Same rules as the Counter: someone who can work here, close by, one game at a time.
local function onSoak(prompt: ProximityPrompt, player: Player)
	local plot = Plots.fromInstance(prompt)
	local state = if plot then active[plot] else nil
	if not state or not state.Active then
		return
	end
	local now = os.clock()
	if now - (lastTreat[player] or 0) < TREAT_COOLDOWN then
		return
	end
	lastTreat[player] = now
	if not Plots.canWork(player, state.Plot) then
		Remotes.toast(player, "🔒 Ask the owner to open up!")
		return
	end
	if Treatment.busy(player) then
		return -- one mini-game at a time
	end
	local holder = prompt.Parent
	local at: Vector3? = if holder and holder:IsA("Attachment")
		then holder.WorldPosition
		elseif holder and holder:IsA("BasePart") then holder.Position
		else nil
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if
		not (at and root and root:IsA("BasePart"))
		or (root.Position - at).Magnitude > SOAK_DISTANCE + DISTANCE_SLACK
	then
		return
	end
	local p = soakTarget(state)
	if not p then
		return
	end
	local sessionId: number? = nil
	local spec: Treatment.Spec = {
		Plot = state.Plot,
		PatientId = p.PatientId,
		Kind = "Soak",
		Items = {},
		Position = p.Root.Position + Vector3.new(0, 3 * p.BaseScale, 0),
		Counter = p.Root.Position, -- a report from far from the tub is rated all OK, as at the Counter
		TipSoFar = p.TipPaid,
		Settle = function(_ratings: { Types.Rating }, tip: number): (boolean, Treatment.TriageAsk?)
			if sessionId ~= nil and p.SoakSession == sessionId then
				p.SoakSession = nil
				p.SoakDone = true
				p.TipPaid += math.max(0, tip)
				if state.Active then
					refreshSoak(state)
				end
			end
			return false, nil -- a soak never changes the recipe
		end,
	}
	local ok, opened = pcall(Treatment.open, player, spec)
	if not ok or type(opened) ~= "number" then
		if not ok then
			report("Treatment.open (Soak)", opened)
		end
		return
	end
	sessionId = opened
	p.SoakSession = opened
	refreshSoak(state)
end

-- The 🫧 prompt is on while a patient soaks whose game is unplayed (wired the first time it's seen).
refreshSoak = function(state: PlotState)
	local prompt = soakPrompt(state)
	if not prompt then
		return
	end
	if not soakWired[prompt] then
		soakWired[prompt] = true
		prompt.Triggered:Connect(function(player: Player)
			onSoak(prompt, player)
		end)
	end
	local on = state.Active and soakTarget(state) ~= nil
	if prompt.Enabled ~= on then
		prompt.Enabled = on
	end
end

local function refill(p: Patient)
	p.Patience = p.PatienceMax
	showRing(p, 1, RING_CALM)
	showPatience(p, 1)
end

-- 💫 Miracle: cured on the spot (the patient's own thread plays it out: curedOnSpot). Only a patient in line, not
-- mid-mini-game.
local function cureOnSpot(state: PlotState, p: Patient)
	if p.State ~= "Queue" or p.Session or p.Claimed then
		return
	end
	p.Done = table.create(#p.Recipe, true)
	p.Helper = state.Owner
	p.PatienceLeft = math.clamp(p.Patience / p.PatienceMax, 0, 1)
	p.RecoverIn = "Reception"
	p.State = "Cured"
	showRecipe(p)
	removeFromQueue(state, p)
end

-- Abilities.Fired (plot, nurseId, abilityId, kind, value): the kinds that act on the line (build plan §B8).
--   RefillFront  the front waiting patient's patience is full again (🤗 Warm Hug)
--   RefillLine   everyone waiting (🌈 Rainbow Cheer)
--   PauseLine    no patience drains for `value` seconds (🎵 Calm Song; Abilities.patiencePaused too)
--   CureLine     every patient waiting (not being treated) is cured on the spot, owner as helper, no tip (💫 Miracle)
local function onAbility(plotArg: any, _nurseId: any, _abilityId: any, kind: any, value: any)
	local plot: Plot? = if typeof(plotArg) == "Instance"
		then Plots.fromInstance(plotArg)
		elseif type(plotArg) == "table" then plotArg
		else nil
	local state = if plot then active[plot] else nil
	if not state or not state.Active or state.Owner.Parent ~= Players then
		return
	end
	if kind == "RefillFront" then
		for _, p in state.Queue do
			if p.State == "Queue" and not p.Session then
				refill(p)
				break
			end
		end
	elseif kind == "RefillLine" then
		for _, p in state.Queue do
			if p.State == "Queue" then
				refill(p)
			end
		end
	elseif kind == "PauseLine" then
		state.PausedUntil = math.max(state.PausedUntil, os.clock() + clampNumber(value, 0, 60, 0))
	elseif kind == "CureLine" then
		local waiting: { Patient } = {}
		for _, p in state.Queue do
			if p.State == "Queue" and not p.Session and not p.Claimed then
				table.insert(waiting, p)
			end
		end
		for _, p in waiting do
			cureOnSpot(state, p)
		end
		refreshFront(state)
	end
end

local function ensurePrompt(plot: Plot): ProximityPrompt
	local existing = prompts[plot]
	if existing and existing.Parent then
		return existing
	end
	local counter = plot.Counter
	local holder = Instance.new("Attachment")
	holder.Name = "TreatAttachment"
	holder.Position = Vector3.new(0, counter.Size.Y / 2 + 1.2, 0)
	holder.Parent = counter

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TreatPrompt"
	prompt.ActionText = "Treat"
	prompt.ObjectText = ""
	prompt.HoldDuration = 0 -- a tap: no precision timing
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Enabled = false
	prompt:AddTag("TreatPrompt") -- UI/PromptFilter finds it by this tag (it never scans the whole town)
	prompt.Parent = holder
	prompt.Triggered:Connect(function(player: Player)
		onTreat(plot, player)
	end)
	prompts[plot] = prompt
	return prompt
end

------------------------------------------------------------------------------------------------------------------
-- Plots opening and closing
------------------------------------------------------------------------------------------------------------------

local function activate(owner: Player, plot: Plot)
	local current = active[plot]
	if current then
		if current.Owner == owner then
			return
		end
		deactivate(plot)
	end

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
	-- Standing on a floor (Progression v2): only what you can stand on (the slabs and the Ground; markers, glass and
	-- the walls above the ground storey don't collide).
	local floorRay = RaycastParams.new()
	floorRay.FilterType = Enum.RaycastFilterType.Include
	floorRay.RespectCanCollide = true

	local now = os.clock()
	local state: PlotState = {
		Plot = plot,
		Owner = owner,
		Active = true,
		Queue = {},
		All = {},
		Beds = {},
		Nav = makeNav(plot),
		Ray = ray,
		Prompt = ensurePrompt(plot),
		NextSpawn = os.clock() + FIRST_PATIENT_SECONDS,
		Spawned = 0,
		LastPatient = nil,
		FrontItem = "",
		FrontNeeds = "",
		QueueNeeds = "",
		Loop = nil,
		SecondSpawned = false,
		Forced = {},
		FloorRay = floorRay,
		Level = levelAsk("level", owner, 1),
		Rebirths = rebirthsOf(owner),
		Effects = effectsOf(owner),
		Team = { Cash = 1, Recover = 1, Urgent = 1 },
		Medic = 1,
		Receptionist = { Arrive = 1, Triage = false },
		NextAE = now + Config.AE.FirstSeconds,
		NextVIP = now + Pure.vipSeconds(Config, rng:NextNumber()),
		ForceUrgent = {},
		Incoming = 0,
		PausedUntil = 0,
		LiftBusy = false,
	}
	active[plot] = state
	plot.Model:SetAttribute("FrontItem", "")
	plot.Model:SetAttribute("FrontStation", "")
	plot.Model:SetAttribute("FrontNeeds", "")
	plot.Model:SetAttribute("QueueNeeds", "")
	refreshFront(state)
	local loop = coroutine.create(plotLoop)
	state.Loop = loop
	task.spawn(loop, state)
end

-- Never yields: it runs inside Plots.PlotReleased, before Plots clears the plot.
deactivate = function(plot: Plot)
	local state = active[plot]
	if not state then
		return
	end
	active[plot] = nil
	state.Active = false
	local loop = state.Loop
	state.Loop = nil
	cancel(loop)
	local everyone: { Patient } = {}
	for p in state.All do
		table.insert(everyone, p)
	end
	for _, p in everyone do
		local closed, closeErr = pcall(closeSessionEarly, p)
		if not closed then
			report("close a mini-game early", closeErr)
		end
		local ok, err = pcall(settleEarly, p)
		if not ok then
			report("settle a cure early", err)
		end
		removePatient(p)
	end
	table.clear(state.Queue)
	table.clear(state.Beds)
	table.clear(state.ForceUrgent)
	state.Incoming = 0
	state.LiftBusy = false
	local tubPrompt = soakPrompt(state)
	if tubPrompt then
		tubPrompt.Enabled = false
	end
	state.Prompt.Enabled = false
	state.Prompt.ObjectText = ""
	plot.Model:SetAttribute("FrontItem", "")
	plot.Model:SetAttribute("FrontStation", "")
	plot.Model:SetAttribute("FrontNeeds", "")
	plot.Model:SetAttribute("QueueNeeds", "")
end

------------------------------------------------------------------------------------------------------------------
-- The 🛠️ Admin panel (Server/Admin checks the caller is an admin; nothing else calls these)
------------------------------------------------------------------------------------------------------------------

function Patients.sendNext(owner: Player, patientId: string): (boolean, string)
	local plot = Plots.getPlot(owner)
	local state = if plot then active[plot] else nil
	if not state then
		return false, "🏠 No clinic yet!"
	end
	local entry = if type(patientId) == "string" then rawget(PatientsData :: any, patientId) else nil
	local ailment = if entry then AilmentsData[entry.Ailment] else nil
	local station = if ailment then StationsData[ailment.Station] else nil
	if not (entry and ailment and station) then
		return false, Remotes.OOPS
	end
	local stations = stationsOnPlot(state.Plot)
	if not stations[ailment.Station] then
		return false, "🔒 Needs " .. station.Icon .. " first!"
	end
	-- Its whole recipe at this clinic's level (a 2-3 item recipe can need another room's station).
	local recipe = recipeOf(patientId, nil, recipeCapFor(owner))
	if not (recipe and Recipe.makeable(recipe, itemsMadeOn(stations))) then
		return false, "🔒 Needs another room first!"
	end
	if #state.Forced >= Config.MaxQueue then
		return false, "⏳ Line is full!"
	end
	table.insert(state.Forced, patientId)
	state.NextSpawn = math.min(state.NextSpawn, os.clock())
	return true, ailment.Icon .. " " .. entry.Name .. " is next!"
end

function Patients.reopen(owner: Player): boolean
	local plot = Plots.getPlot(owner)
	if not plot or not active[plot] or plot.Owner ~= owner then
		return false
	end
	deactivate(plot)
	activate(owner, plot)
	return true
end

-- An admin's urgent call: it comes as soon as the line has room (no timer, no tutorial or presence rule).
local function adminCall(owner: Player, kind: string, minLevel: number, icon: string): (boolean, string)
	local plot = Plots.getPlot(owner)
	local state = if plot then active[plot] else nil
	if not state then
		return false, "🏠 No clinic yet!"
	end
	if levelAsk("level", owner, 1) < minLevel then
		return false, "🏥 Lv " .. minLevel .. " first!"
	end
	if #state.ForceUrgent >= MAX_FORCED_URGENT then
		return false, "⏳ Line is full!"
	end
	table.insert(state.ForceUrgent, kind)
	return true, icon .. " On the way!"
end

-- 🚑 An ambulance as soon as the line has room (Lv 2+).
function Patients.adminAmbulance(owner: Player): (boolean, string)
	return adminCall(owner, "AE", AE_LEVEL, "🚑")
end

-- 🚁 An air ambulance as soon as the line has room (Lv 5; no R2 needed).
function Patients.adminHelicopter(owner: Player): (boolean, string)
	return adminCall(owner, "VIP", HELI_LEVEL, "🚁")
end

function Patients.start()
	for _, plot in Plots.all() do
		ensurePrompt(plot)
	end
	Treatment.onHeal(healFront)
	Abilities.Fired:Connect(onAbility)
	-- 🦉 Night Owl: when the in-game night ends (IsNight true -> false)
	local wasNight = Workspace:GetAttribute("IsNight") == true
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(function()
		local isNight = Workspace:GetAttribute("IsNight") == true
		if wasNight and not isNight then
			nightEndedAt = os.clock()
		end
		wasNight = isNight
	end)
	Plots.PlotAssigned:Connect(function(owner: Player, plot: Plot)
		activate(owner, plot)
	end)
	Plots.PlotReleased:Connect(function(_owner: Player, plot: Plot)
		deactivate(plot)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastTreat[player] = nil
	end)
	for _, plot in Plots.all() do
		local owner = plot.Owner
		if owner then
			activate(owner, plot) -- plots handed out before Patients started
		end
	end
end

return Patients
