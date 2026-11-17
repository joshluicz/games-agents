--!strict
-- Patients: the visit at every clinic (Real Clinic build plan, Task 4 and contract C6; design §5, §6 and §15).
-- Server only. API: Patients.start(), the visit API below (C6) and the Admin hooks.
-- A visit: front doors -> reception -> a waiting-room seat -> an exam bay -> EXAMINE -> TREAT (supplies) and the
-- medicines from the dispensary -> home, or first a ward bed upstairs.
--
-- The visit, step by step:
--   1. Arrive. Each owned plot gets a patient every few seconds (Levels.spawnSeconds, 13 s at Lv 1 down to 8 s at
--      Lv 5; sooner with 🚪 Busy Doors and a Receptionist: Logic/Hospital.arrival) while fewer than the level's line
--      (Levels.queueCap, never past Config.MaxQueue = 3) are in the waiting room. Patients in a bay don't count: the
--      open bays are the level's throughput. It walks in from the gate (PatientSpawn) through the front doors
--      (Logic/Building.DOORS.Front), stops at reception (RECEPTION.Stop), then sits on a free WaitSeat_<n> with its
--      symptom bubble ("😷 cough cough") over it, even when a bay stands free (Joshua, 2026-11-17); every seat taken:
--      it waits standing.
--      Who comes, in order: a regular whose story beat is due (Story.dueRegular; their own fixed Case), Today's
--      Visitor (Daily.visitorFor, a ⭐ on the badge), otherwise any species that may come here, weighted toward night
--      patients at night and new Book pages. Its CASE is rolled each visit from its wing's pool (Data/Cases.POOLS,
--      Pure.pickCase) cut to what this clinic can treat (Pure.eligible: Logic/Visit.canTreat with the open
--      Station_<id> parts, a usable bay of the case's kind and its exam tool unlocked). A case that needs an item no
--      open station makes is never picked (Review Focus 1), for anyone: the usual pool, regulars, Today's Visitor,
--      night patients, ambulances and the helicopter. A species comes only when its pool has such a case; Bath-wing
--      patients also need the Bath Room and Winter-wing ones the Winter Wing, as they always did (Pure.wingRoom). The
--      plan is the case's Plan cut to the level (Logic/Visit.plan with Levels.recipeCap; 1 step through the
--      tutorial). Variants: Sparkly, Frosty in winter, 🌟 Golden from R3 (Pure.variant). Night patients only at
--      night (and in 🦉 Night Owl's morning); 🌻 Sunny from R1; 🚁 Sky only by air ambulance (Pure.wingOpen).
--   2. To a bay: THE PLAYER SENDS IT (simple-start design §2; memory-20261117-006, Joshua: "you do it"). A walk-in
--      stays on its seat until it is sent. While it waits it carries a "Send" prompt (SendPrompt, on the patient
--      itself; anyone who may work the clinic, Plots.canWork). One press sends it to the nearest free bay that fits
--      it (Logic/Routing.pickBay: an X-ray case only the X-ray bay, every other case only an exam bay; a usable bay
--      is an ExamBay_<id> under the Building or Rooms whose Logic/Building.bayOpen holds) through U.callToBay; no
--      free bay: the toast "All bays are busy!". From Lv 3, with the X-ray bay open (Logic/Routing.needsChoice), the
--      prompt opens a two-button card on the client instead ("🩺 Exam bay" / "📸 X-ray": UI/SendCard) and the pick
--      comes by the SendPatient RemoteEvent (U.onSendRemote checks everything); a wrong pick is a gentle toast and
--      the patient stays seated, no penalty. The tick sends nobody by itself, except (U.autoCall): a 🚑/🚁 patient
--      (at once, straight from its door), a patient that was sent before and whose bay closed under it, and, with a
--      Receptionist on duty (Nurses.reception), each walk-in that has sat K.RECEPTION_SECONDS, one at a time
--      K.RECEPTION_GAP apart (U.receptionSend). Sent, it gets up, walks there (Logic/Building.path: round the walls
--      and through open doors, never a shut one) and sits on the bay's Bed.
--   3. Examine. The bay's BayPrompt (on its DoctorSpot, tag TreatPrompt) says "Examine": Treatment.open Kind "Exam"
--      with Tools (Logic/Visit.examTools: 3 unlocked tools, the right one among them), Answer, Glow
--      (Logic/Visit.glow: the player's first Config.Visit.ExamsGlow exams by their own saved count Stats.Exams, never
--      the patients treated, so a save from before the Real Clinic gets the glow too; always in Simple mode and
--      through the player's tutorial) and Case. Its settle, whatever the ratings, reveals the case (examine): Case, Plan and PlanDone
--      are set and the plan shows on the badge. Patience pauses while it plays.
--   4. Treat. The prompt now says "Treat". The plan steps the helper carries (Logic/Recipe.match on Carry, then the
--      plot's nurse tray) are taken: they're spent now. Medicines are handed over at once, with no game; supplies open
--      ONE Treat session with their games (Treatment.open Kind "Treat", Items = the supplies, one game each). When it
--      settles the steps count as given. Each step given (and the exam) refills Config.Treat.ItemPatience of the
--      patience. Nothing in hand fits: a head-shake and a toast naming what's needed.
--   5. Done. The plan complete: a happy bounce, then Logic/Visit.stayWard. No stay (no Stay, or below its ward's
--      level): it pays (Cure.resolve: cash to the helper, stars to the owner) on the bed, gets up (the bay frees as
--      it stands) and walks out of the front doors to PatientExit. A Stay case first rests in a ward bed upstairs
--      (Floor_<n>.BedSpot_<k>.Bed_<k> whose Ward is its own; the other ward's when its own is full; straight home
--      when every bed is taken, Pure.destination; a chills patient no ward takes rests in the Winter Wing's own
--      Bed_1 on the ground floor instead, with no lift: restInRoom). From Lv 3 the helper whose game finished the
--      plan picks the ward first ("Injury Ward or Rest Ward?": Treatment.waitTriage; right +10%; a Receptionist or
--      Simple mode sends it at once with the bonus; a plan a handed-over medicine completes asks too, through a
--      no-game handover session).
--      It waits at the ground landing for a Porter or, when a worker stands near, a player's escort (Lift.waitEscort;
--      +20% cash, rest x0.5), rides the lift (Lift.carry), rests (Pure.rest: Config.RecoverSeconds x escort x Ward
--      Comfort x the team), pays, rides down and walks out.
--   6. Patience (Logic/Visit.PATIENCE): it drains at x0.5 in the waiting room and x1 on a bay bed waiting for the
--      doctor (sitting down on the bay bed fills it up again first: Config.Visit.BayRefill), never while walking or
--      during a game; slower with a Cheerer (the plot's CheerPatience) and, for 🚑/🚁
--      patients, with the A&E team and a Medic. Running out is a sad puff where it sits, never a penalty (a regular:
--      Story.left, so they come back later).
-- Several bays run at once. "The front patient" (what nurses, abilities, the guide pin and the tutorial point at) is
-- the bay patient who has waited longest for the doctor (Logic/Visit.front; Pure.frontOrder).
--
-- Rebuilds and leavers (Review Focus 2 and 4):
--   · A level-up, a theme or a room rebuilds the Building: patients walk and sit by Logic/Building's numbers, which
--     every rebuild keeps, so nobody floats; the prompts move to the new DoctorSpots. When the bays OPEN by the
--     numbers change (a lower PreviewLevel, a room the save no longer owns), Pure.reseat keeps everyone in its bay or
--     seat, sends a patient whose bay closed back to a seat (its exam and plan kept; a game on it is dropped and its
--     items go back) and sends one with no seat home, never sad.
--   · A helper who leaves mid-game: Treatment settles it all OK, so the bay patient keeps what was done (an exam
--     still reveals the case) and waits for the next doctor.
--   · The owner leaves (Plots.PlotReleased): every patient goes home at once (State "Leaving"). One whose plan is
--     complete, or completes with the steps in its open game, is paid first (Pure.closing), so a helper never loses
--     their work; a helper who stays gets back the items of a game that didn't finish it.
--
-- Hospital extras (Progression v2, kept):
--   · 🚑 A&E (Lv 2+). About every Config.AE.EverySeconds (Pure.aeSeconds; the first Config.AE.FirstSeconds after
--     Lv 2), only while the owner stands at their clinic, is done with the tutorial, the waiting room has room and no
--     other 🚑/🚁 patient's visit is under way: the parked Ambulance's ArriveAt is set (Feel/HospitalFX) and an urgent
--     patient steps out at its StretcherSpot and walks in through the A&E door. Its plan has at least
--     Config.AE.MinItems steps (Pure.urgentFor: Logic/Hospital.urgentRecipe, padded with a 🧊 Ice pack), patience x
--     AE.PatienceMultiplier x (1 + 0.15 x A&E Speed); it pays x3 + 2 ⭐ (Cure) and takes the next free bay before
--     anyone else.
--   · 🚁 Air ambulance (Lv 5, from R2): HeliSpot's ArriveAt is set; HELI_LAND_SECONDS later a Sky-wing patient (a
--     broken leg) steps out on the roof, rides the lift down and takes the X-ray bay first. x4 + 3 ⭐.
--   · Abilities (Abilities.Fired): RefillFront (the front patient's patience full), RefillLine (everyone waiting or
--     in a bay), PauseLine (no patience drains; also Abilities.patiencePaused). 💫 Miracle (CureLine) is
--     Server/Abilities' own: it calls Patients.finishVisit for every bay patient not mid-game (the owner as helper, no
--     tip), so each one's whole visit is done on the spot.
--   · Nurses (Treatment.onHeal -> healFront): a Healer (target "Front": the front patient; the two front ones with 👯
--     Twin Counters) or a Medic (target "Urgent": a 🚑/🚁 bay patient) examines a patient who needs it (no game, no
--     tip; the case is revealed) or else hands over what the nurse tray holds for it, rated OK. The tray never holds a
--     medicine, so a medicine step always needs the player (design §15 #1). Returns what it handed over, or the exam
--     tool's id for an exam (Treatment then tells Nurses.healed).
--   · Studio test switch: workspace:SetAttribute("ForceGoldenPatient", true): every new patient at an R3+ clinic is
--     Golden. A live server ignores it.
--
-- The first-session tutorial (Server/Tutorial, by the OWNER's step). Nothing here changes for an owner who's done.
--   · Who comes (Tutorial.spawnPlan): nobody during the welcome; then a Starter patient with the first Lv 1 case
--     treated at the 💊 dispensary (a cough); then one with the first Lv 1 case treated with a 🩹 plaster (a cut
--     knee); then the usual pool. No regulars, no Today's Visitor and no variants until it's done.
--   · One patient at a time through step 6 (Tutorial.queueCap counts every patient whose plan isn't done yet).
--     Patience never runs out in steps 1-6 (Tutorial.calm). Plans stay 1 step.
--   · Hooks: Tutorial.onFrontArrived(owner) when a patient sits on a bay bed, Tutorial.onExamined(owner, player?)
--     when an exam reveals a case (a player's, or a nurse's: player nil), Tutorial.onTreated(owner) when a plan is
--     complete. A hook Server/Tutorial doesn't have is skipped.
--
-- The visit API (contract C6; Treatment, Stations, Nurses and Abilities call these). `plot` is the Plot table or any
-- Instance in the plot (Plots.fromInstance); `patientId` is a patient's VisitId (a number for this visit).
--   Patients.bayView(plot): { { Bay, PatientId: number, Stage: "Exam" | "Treat", Needs: { ItemId }, Since } }
--       the patients sitting on a bay bed whose plan isn't done, the longest-waiting first. Needs = the steps still
--       missing and not in a game right now ({} before the exam); Since = os.clock() it sat on the bed
--   Patients.neededMedicines(plot): { ItemId }   the medicine steps those patients still need, oldest first,
--       distinct, at most Config.Dispensary.Options: what the dispensary offers
--   Patients.examine(plot, patientId, helper?): CaseId?   reveals that bay patient's case, no game (idempotent: an
--       examined one just answers its case). nil when it isn't sitting on a bay bed
--   Patients.give(plot, patientId, items, helper?): { number }   those items count as given (the caller took them
--       already; no game): the plan slots they filled. {} before the exam
--   Patients.finishVisit(plot, patientId, helper?): boolean   abilities only: the whole visit is done on the spot
--       (the exam and every step, medicines included), paid with no tip, and home
-- For the 🛠️ Admin panel only (Server/Admin checks the caller is an admin):
--   Patients.sendNext(owner, patientId): (ok, message)   that species comes next (before the usual pick and the
--       tutorial's plan) once the waiting room has room; up to Config.MaxQueue picks wait. Refused when no case of its
--       wing's pool can be treated here
--   Patients.reopen(owner): boolean   empties the owner's clinic and opens it again, as on a fresh join (a patient
--       whose plan is complete is paid on the spot first, exactly as when an owner leaves)
--   Patients.adminAmbulance(owner) / Patients.adminHelicopter(owner): (ok, message)   an urgent patient as soon as
--       the waiting room has room (Lv 2+ / Lv 5; no R2 needed)
--
-- For the clients (read-only, the server sets them):
--   patient Model (in Plot.Patients): PatientId (the species), VisitId, Kind ("Patient" | "Regular" | "Visitor"),
--     Regular, Variant, Night, Urgent ("" | "AE" | "VIP"), Escorted, Dept (the ward it will rest in; "" = none or not
--     examined yet), Symptom (its bubble, e.g. "😷 cough cough"), Acting (the CaseId the creature acts out from the
--     start, for Feel/CreatureActing; the case is REVEALED by Case), Tool (the right exam tool), Case ("" until the
--     exam), Plan (comma-joined ItemIds, "" until the exam), PlanDone ("1" given / "0" not, one per step), Item and
--     Station (its first missing step and that step's station; "" before the exam), Bay ("" or its bay's id), Since
--     (the server time it sat on its bay bed; nil off a bed), QueueIndex (1 = the front patient, 2 = the next who
--     needs the doctor, ...; 0 = everyone else), PatienceFraction (0..1 in 0.05 steps, only on change), State:
--       "Arriving" (walking in) · "Waiting" (in the waiting room) · "ToBay" · "AtBay" (on a bay bed, waiting for its
--       exam) · "Examining" · "Planned" (examined, waiting for the next step) · "Treating" (a supply game) · "ToWard"
--       (the ward pick, the lift and the walk to a ward bed) · "Recovering" (in a ward bed) · "Done" (it paid) ·
--       "Leaving" · "Sad"
--     The badge shows the symptom icon, then after the exam the case icon and the plan's chips.
--   plot Model: FrontBay (the front patient's bay; "" = none), FrontStage ("Exam" | "Treat" | ""), FrontItem and
--     FrontStation (its first missing step and that step's station; "" before its exam), FrontNeeds (every step it
--     still needs, comma-joined; with 👯 Twin Counters the two front patients'), QueueNeeds (every missing step of every
--     examined bay patient, oldest first, duplicates kept; steps in a game right now don't count). Nurse Makers and the
--     Guide read these.
--   ExamBay_<id>.DoctorSpot.BayPromptAt.BayPrompt (tag TreatPrompt, attribute Bay): enabled only while a patient sits
--     on that bay's bed needing the doctor and nobody is playing with it; ActionText "Examine" or "Treat"; ObjectText
--     its symptom or case icon.
--   patient Model: <Root>.SendPromptAt.SendPrompt (tag TreatPrompt, attributes VisitId and Choice): enabled only
--     while that patient waits in the waiting room to be sent; ActionText "Send"; ObjectText its symptom. Choice =
--     true: the client opens the two-button card and fires the SendPatient remote (VisitId, "Exam" | "XRay");
--     false: the press itself sends it.
--
-- Movement: no Humanoids, no physics. A creature is one anchored Root with its parts welded on (CreatureBuilder).
-- The server never moves a creature every frame (the creature motion contract): each hop, shake, droop and
-- grow/shrink sets attributes once and every client draws the in-between (Feel/CreatureMotion); the server writes
-- the end pose once as each one lands. Each patient has one thread for its whole visit; the prompts, the nurses and
-- the clinic tick only change its record (its Phase, its Bay), and the thread acts on that.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Palette = require(Shared.Palette)
local Building = require(Shared.Logic.Building)
local Hospital = require(Shared.Logic.Hospital)
local Pay = require(Shared.Logic.Pay)
local Prices = require(Shared.Logic.Prices)
local Recipe = require(Shared.Logic.Recipe)
local RebirthLogic = require(Shared.Logic.Rebirth)
local Visit = require(Shared.Logic.Visit)
local Cases = require(Shared.Data.Cases)
local Items = require(Shared.Data.Items)
local LevelsData = require(Shared.Data.Levels)
local PatientsData = require(Shared.Data.Patients)
local PerksData = require(Shared.Data.Perks)
local RegularsData = require(Shared.Data.Regulars)
local Tools = require(Shared.Data.Tools)
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
local Story = require(script.Parent.Story)
local Treatment = require(script.Parent.Treatment)
local Tutorial = require(script.Parent.Tutorial)
local Boosts = require(script.Parent.Boosts) -- the owner's Patience boosts

type Plot = Types.Plot
type Badge = CreatureBuilder.Badge
type Point = Building.Point
type BayInfo = Building.Bay

local Patients = {}

------------------------------------------------------------------------------------------------------------------
-- Tuning
------------------------------------------------------------------------------------------------------------------

-- Luau allows a chunk 200 local registers, and this module has more top-level names than that. So the tuning
-- constants live in K and the small helpers in U: two locals instead of about a hundred. A new constant or helper
-- goes in one of them, never in a new top-level local (tests/Compile.spec compiles every src file to check).
local K = {}
local U = {}

-- Optional Config keys (these defaults apply until Config has them).
local Tuning = Config :: any
K.GUEST_PATIENCE = tonumber(Tuning.GuestPatienceMultiplier) or 1.5 -- regulars and Today's Visitor
K.FIRST_PATIENT_SECONDS = tonumber(Tuning.FirstPatientSeconds) or 2 -- after you get your plot
K.DISPENSARY_OPTIONS = math.max(1, math.floor(tonumber(Tuning.Dispensary and Tuning.Dispensary.Options) or 3))

K.TICK = 0.2 -- patience, spawning, bays and the recovery ring update this often
K.REFILL_SECONDS = 2 -- a freed place in the waiting room is refilled no sooner than this
K.NIGHT_WEIGHT = 3 -- night patients are this much likelier at night
K.NEW_PAGE_WEIGHT = 2.5 -- patients not yet in the owner's Book are likelier
K.REPEAT_WEIGHT = 0.35 -- the same patient twice in a row is less likely
-- The tutorial's two patients: a Starter-wing day patient with the first Lv 1 case whose plan starts at this station.
K.TUTORIAL_STATION = { First = "Remedy", Second = "Plaster" } :: { [string]: string }
K.TUTORIAL_WING = "Starter"

K.PROMPT_DISTANCE = 8 -- a bay's prompt reaches this far (the next bay's DoctorSpot is 6.5 away; the nearest shows)
K.PROMPT_HEIGHT = 2.6 -- studs above the floor
K.DISTANCE_SLACK = 6 -- lag allowance on the server's own distance check
K.TREAT_COOLDOWN = 0.3 -- per player
K.MAX_CHEER_PATIENCE = 3 -- a sanity cap on the plot's CheerPatience (Cheerers give at most ~1.5)
K.MAX_CHEER_TIP = 3 -- and on its CheerTip (the visit's cash, Logic/Pay)
K.ITEM_PATIENCE = Config.Treat.ItemPatience -- each plan step given (and the exam) refills this share of the patience
-- ... and sitting down on a bay bed refills this share (the waiting room's wait is forgotten)
K.BAY_REFILL = math.clamp(tonumber(Config.Visit and (Config.Visit :: any).BayRefill) or 1, 0, 1)
K.ROOM_BED_FOOT = 1.6 -- a room bed's foot spot: this far past the mattress (as a ward bed's)
K.CHECK_IN_SECONDS = 0.6 -- a patient stands at reception this long before it sits down
-- ... and sits in the waiting room at least this long before a Receptionist sends it (the player may send it as
-- soon as it has settled: Config.Visit.SeatSeconds)
K.SEAT_SECONDS = math.max(tonumber(Config.Visit and (Config.Visit :: any).SeatSeconds) or 3, 0)
-- Sending (Logic/Routing, in K: the local limit). A Receptionist on duty sends a walk-in that has sat this long (never
-- sooner than SEAT_SECONDS), one at a time this far apart.
K.Routing = require(Shared.Logic.Routing)
K.RECEPTION_SECONDS = math.max(
	tonumber(Config.Visit and (Config.Visit :: any).ReceptionSeconds) or K.Routing.RECEPTION_WAIT,
	K.SEAT_SECONDS
)
K.RECEPTION_GAP = math.max(tonumber(Config.Visit and (Config.Visit :: any).ReceptionGap) or K.Routing.RECEPTION_GAP, 0)
K.SEND_COOLDOWN = 0.3 -- per player, the Send prompt and the SendPatient remote alike
K.SEND_REMOTE = "SendPatient" -- its name for the rate limit (Remotes.allow)
K.URGENT_HEAD = 1e6 -- seconds an urgent patient counts as having waited already: it takes the next free bay
K.LAYOUT_SECONDS = 3 -- the bays, stations and ward beds are looked up again at least this often
K.RAY_UP = 3.5 -- the floor under a point is found with a ray from this far above that floor's slab

-- Feel
K.HOP_LENGTH = 3.6
K.HOP_SECONDS = 0.3
K.HOP_HEIGHT = 0.9
K.LEAN = 0.14 -- radians forward at the top of a hop
K.SIT_HEIGHT = 1.8 -- a hop onto (or off) a seat or a bed
K.CreatureSize = require(Shared.Logic.CreatureSize) -- how a sitter fits a seat (seatFit; in K: the local limit)
K.SEAT_BACK = 0.6 -- a chair back's thickness (HospitalBuilder Pure.SEAT.Back; tests/Sit.spec keeps them equal)
K.SIT_SECONDS = 0.45
K.RING_STEPS = 48 -- the ring moves in 7.5 degree steps, so it replicates a few times a second at most
K.PATIENCE_STEPS = 20 -- the PatienceFraction attribute moves in 0.05 steps (about 20 changes in a whole wait)

-- The patience ring, candy pop (memory-20261116-007): bright green, then yellow, then red; pink while healing.
K.RING_CALM = Palette.Candy.Lime
K.RING_HURRY = Palette.Candy.Yellow
K.RING_LOW = Palette.Candy.Red
K.RING_HEAL = Palette.Candy.Pink

K.ICON_TREATED = "💗"
K.ICON_SLEEP = "💤"
K.ICON_HAPPY = "🥰"
K.ICON_SAD = "😔"
K.ICON_UNKNOWN = "❔"

-- Progression v2: Hospital v2 (every rule's number is in Config: AE, VIP, Triage, Escort, Lift, WardComfort,
-- AESpeed, GoldenChance; these are feel and safety only)
K.AE_LEVEL = 2 -- Data/Departments.AE.Opens: ambulances come from this hospital level
K.HELI_LEVEL = 5 -- Data/Departments.Roof.Opens: the helipad
K.HELI_LAND_SECONDS = 3.5 -- the helicopter lands first (Feel/HospitalFX: HELI_IN 3.2 s), then out steps its VIP
K.PLOT_MARGIN = 6 -- studs past the plot's edge that still count as the owner being at their clinic
K.POLL = 0.1 -- waiting on another system (the lift, a porter) looks this often
K.PORTER_SECONDS = 15 -- the most a patient waits for a Porter to walk over
K.CARRY_SECONDS = 8 -- the most a lift ride may take before the patient is put there anyway
K.ESCORT_SLACK = 2 -- seconds on top of Config.Lift.EscortWait before giving up on Lift.waitEscort
K.ESCORT_NEAR = 24 -- studs from the ground landing a worker must be for a patient to wait for an escort
K.MAX_SLOWER = 4 -- a sanity cap on how much slower an urgent patient's patience may drain
K.MAX_FORCED_URGENT = 3 -- admin calls waiting at once

K.LANDING = { X = Building.LANDING.X, Z = Building.LANDING.Z } :: Point -- in front of the lift, on every floor

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

-- One exam bay as built: its numbers (Logic/Building.BAYS), its ExamBay_<id> Model and the parts in it.
type BaySpot = { Id: string, Kind: string, Info: BayInfo, Model: Model, Bed: BasePart?, Spot: BasePart? }
-- One functional ward bed upstairs (Floor_<n>.BedSpot_<k>.Bed_<k>), keyed "<floor>:<k>".
-- (Room: a bought room's own recovery bed on the ground floor, e.g. the Winter Wing's Bed_1; Ward is then "Room")
type WardBed = { Key: string, Part: BasePart, Floor: number, X: number, Ward: string, Room: string? }
-- What the plot's Building and Rooms hold, looked up when they change (scanLayout).
type Layout = {
	Building: Instance?,
	Key: string,
	At: number,
	Seats: { [number]: BasePart }, -- WaitSeat_<n> markers found (a seat without one sits by the numbers)
	Bays: { [string]: BaySpot },
	Stations: { [string]: boolean }, -- StationId -> open (Station_<id> with Open ~= false)
	Beds: { [string]: WardBed },
	RoomBeds: { [string]: WardBed }, -- RoomId -> that room's own recovery bed (Rooms.Room_<id> ... Bed_1)
}

-- The owner's perks and tree as patients use them (Logic/Rebirth.effects, cleaned)
type Effects = { Arrive: number, SirenPro: number, NightOwl: boolean, TwinCounters: boolean }

type PlotState = {
	Plot: Plot,
	Owner: Player,
	Active: boolean,
	Pivot: CFrame, -- the plot's ground-top centre, facing the street
	FloorRay: RaycastParams, -- what a patient stands on: the Building, the Ground and the Rooms (solid parts only)
	All: { [Patient]: boolean },
	ById: { [number]: Patient },
	Seats: { [number]: Patient }, -- seat number -> who sits there (or is walking to it)
	BayOf: { [string]: Patient }, -- bay id -> who has it (walking there, on its bed, or getting up)
	Beds: { [string]: Patient }, -- ward bed key -> who rests there (or is on its way)
	Layout: Layout,
	OpenKey: string, -- the bays open by the numbers (a change re-seats everyone: Pure.reseat)
	Prompts: { [string]: ProximityPrompt }, -- bay id -> its BayPrompt
	Rooms: { [string]: boolean }, -- the rooms the owner's save owns (refreshed every tick)
	NextSpawn: number,
	Spawned: number,
	LastPatient: string?,
	Loop: thread?,
	SecondSpawned: boolean, -- the tutorial's 🩹 patient came this session
	Forced: { string }, -- the admin panel's picks (Patients.sendNext), first come first
	Level: number, -- the owner's hospital level (refreshed every tick)
	Rebirths: number, -- the owner's Rebirth.Count (refreshed every tick)
	Effects: Effects, -- the owner's perks + tree that patients use (refreshed every tick)
	Team: { Cash: number, Recover: number, Urgent: number }, -- Nurses.team (refreshed every tick)
	Medic: number, -- Nurses.medic(plot).Patience (refreshed every tick)
	Receptionist: { Arrive: number, Triage: boolean }, -- Nurses.reception (refreshed every tick)
	NextAE: number, -- os.clock() of the next ambulance
	NextVIP: number, -- os.clock() of the next air ambulance
	ForceUrgent: { string }, -- the admin panel's calls ("AE" | "VIP"), first come first
	PausedUntil: number, -- os.clock(): a Calm Song pauses every patience ring until then
	LiftBusy: boolean, -- one ride at a time on this plot's lift
	LastSent: number, -- os.clock() a Receptionist last sent a patient (the next one RECEPTION_GAP later)
}

type Patient = {
	Id: number, -- its VisitId: this visit's own number (the C6 API's patientId)
	Plot: PlotState,
	PatientId: string, -- the species (Data/Patients; a regular's creature id)
	Regular: string?,
	Visitor: boolean,
	Variant: string?,
	Night: boolean,
	Wing: string, -- its Book wing (Data/Wings)
	CaseId: string, -- rolled when it came; revealed by the exam
	Case: any, -- its Data/Cases row
	Symptom: string, -- the bubble
	Icon: string, -- the prompt's and the badge's icon: the symptom's, then the case's
	Examined: boolean,
	Plan: { string }, -- the effective plan (cut by the owner's level; an urgent one padded)
	Done: { boolean }, -- one per step: given
	Item: string, -- the first missing step (after the exam)
	Station: string, -- and its station
	TipPaid: number, -- mini-game tip cash paid on this visit so far (capped per visit)
	Session: number?, -- an open Treatment session on it
	SessionHelper: Player?,
	SessionKind: string?, -- "Exam" | "Treat"
	SessionIndices: { number }?, -- the plan slots a Treat session gives
	SessionCarried: { string }?, -- what it took from the helper's own hands (given back if the session is dropped)
	Model: Model,
	Root: BasePart,
	Badge: Badge,
	BaseScale: number,
	HopHeight: number,
	HopSeconds: number,
	-- Where the visit is (the patient's own thread acts on it): "Arriving" | "Seated" | "ToBay" | "Bay" | "Requeue"
	-- (its bay closed: back to a seat) | "Done" (the plan is complete) | "OnSpot" (an ability finished it) |
	-- "GoHome" (no seat after a rebuild: home, never sad) | "Leaving" | "Sad" | "Gone"
	Phase: string,
	CheckedIn: boolean, -- past reception (or in by the A&E door, or down from the roof): it may take a bay
	Since: number, -- os.clock() it checked in (urgent: URGENT_HEAD earlier): who takes the next bay
	-- os.clock() it first settled in the waiting room (sat down, or stood with every seat taken); nil = not yet. A
	-- bay may call it K.SEAT_SECONDS later (Pure.mayCall). Kept all visit: one whose bay closed needn't sit again
	SeatedAt: number?,
	BaySince: number, -- os.clock() it sat on its bay bed: who is the front patient
	Sent: boolean, -- it was sent to a bay once (a player, a Receptionist): if that bay closes, the tick re-sends it
	Send: ProximityPrompt?, -- its own "Send" prompt (on while it waits to be sent)
	Seat: number?,
	OnSeat: boolean,
	Bay: string?,
	OnBed: boolean,
	QueueIndex: number,
	Claimed: boolean, -- a Treat is being checked right now
	Patience: number,
	PatienceMax: number,
	PatienceLeft: number, -- 0..1, frozen when the plan is complete (Cure ctx)
	PatienceShown: number, -- the PatienceFraction attribute
	RingStep: number,
	RingColor: Color3?,
	NextIdle: number,
	Helper: Player?,
	Paid: boolean,
	Pivot: CFrame, -- where the creature rests between hops (its bottom centre)
	ScaleAnim: ScaleAnim?, -- the grow/shrink the clients are drawing (so the next one starts where it is)
	Thread: thread?,
	Urgent: string, -- "" | "AE" | "VIP"
	Incoming: boolean, -- a VIP still in the helicopter
	ArriveFloor: number, -- a VIP: the roof's floor number
	Ward: string?, -- the ward it stays in (Logic/Visit.stayWard); nil = home
	WardBed: WardBed?, -- the bed reserved for it
	-- "Home" | "Wards" | "Rest": where it really rests (Pure.destination); "Room": its room's own bed (restInRoom)
	SpotKind: string,
	Floor: number, -- the floor it is on (0 = the ground)
	Upstairs: boolean, -- standing on a floor above the ground right now
	InBed: boolean, -- lying in its ward bed
	Escorted: boolean, -- rode the lift with a Porter or a player (+20% cash, rest x0.5)
	Porter: string?, -- the Porter claimed for it (released when it's done or gone)
	HasLift: boolean, -- it holds this plot's lift turn
	Triage: { Helper: Player, Session: number, Options: { string }, Right: string }?, -- a ward pick to wait for
	TriageBonus: boolean, -- a right pick (or a Receptionist): +10%
	RecoverIn: string, -- the department it was treated in, for nurse XP: "Reception" | "Wards" | "Rest" | "Hydro"
}

-- An urgent patient's arrival (spawnPatient)
type UrgentSpawn = { Kind: string, Plan: { string }, Start: CFrame, Air: boolean, Floor: number }

local active: { [Plot]: PlotState } = {}
local lastTreat: { [Player]: number } = {}
local rng = Random.new()
local nightEndedAt = -math.huge -- os.clock() the last in-game night ended (🦉 Night Owl)
local promptWired: { [ProximityPrompt]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local NEUTRAL_EFFECTS: Effects = { Arrive = 1, SirenPro = 1, NightOwl = false, TwinCounters = false }
local lastVisitId = 0

local deactivate: (plot: Plot) -> () -- defined further down
local onBayPrompt: (plot: Plot, bayId: string, player: Player) -> () -- defined further down

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

function U.carrying(player: Player): { string }
	local ok, items = pcall(Carry.items, player)
	if not ok then
		report("Carry.items", items)
		return {}
	end
	return if type(items) == "table" then items else {}
end

function U.takeItem(player: Player, itemId: string): boolean
	local ok, taken = pcall(Carry.take, player, itemId)
	if not ok then
		report("Carry.take", taken)
		return false
	end
	return taken == true
end

function U.giveBack(player: Player, itemId: string)
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

-- Asks Server/Levels for one of the owner's numbers (level, queueCap, recipeCap, spawnSeconds); `fallback` on a bug.
function U.levelAsk(name: string, owner: Player, fallback: number): number
	local fn = (Levels :: any)[name]
	local ok, value = pcall(fn, owner)
	if not ok then
		report("Levels." .. name, value)
		return fallback
	end
	return if type(value) == "number" and value == value and value >= 1 then math.floor(value) else fallback
end

-- Calls a Server/Tutorial hook; a tutorial bug never breaks a patient, and a hook it doesn't have is skipped.
function U.tutorialHook(name: string, ...: any)
	local fn = (Tutorial :: any)[name]
	if type(fn) ~= "function" then
		return
	end
	local ok, err = pcall(fn, ...)
	if not ok then
		report("Tutorial." .. name, err)
	end
end

-- Asks Server/Tutorial something; on a tutorial bug the answer is `fallback` (the normal game).
function U.tutorialAsk(name: string, fallback: any, ...: any): any
	local fn = (Tutorial :: any)[name]
	if type(fn) ~= "function" then
		return fallback
	end
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
		task.wait(K.POLL)
	end
	return finished, result
end

-- A number from another system: finite and clamped, junk -> `fallback`.
function U.clampNumber(value: any, low: number, high: number, fallback: number): number
	if type(value) ~= "number" or value ~= value then
		return fallback
	end
	return math.clamp(value, low, high)
end

-- That floor's landing in front of the lift door (Lift.landing; nil without a lift).
function U.landingOf(plot: Plot, floor: number): CFrame?
	local ok, cf = pcall(Lift.landing, plot, floor)
	if not ok then
		report("Lift.landing", cf)
		return nil
	end
	return if typeof(cf) == "CFrame" then cf else nil
end

-- The plot's team bonuses (Nurses.team): factors, 1 = none.
function U.teamOf(plot: Plot): { Cash: number, Recover: number, Urgent: number }
	local ok, team = pcall(Nurses.team, plot)
	if not ok then
		report("Nurses.team", team)
	end
	local t: any = if ok and type(team) == "table" then team else {}
	return {
		Cash = U.clampNumber(t.Cash, 1, Pay.MAX_EXTRA, 1),
		Recover = U.clampNumber(t.Recover, 0.05, 1, 1),
		Urgent = U.clampNumber(t.Urgent, 1, K.MAX_SLOWER, 1),
	}
end

-- The best Receptionist on duty (Nurses.reception): patients come Arrive x as often; Triage = it sends them at once.
function U.receptionOf(plot: Plot): { Arrive: number, Triage: boolean }
	local ok, reception = pcall(Nurses.reception, plot)
	if not ok then
		report("Nurses.reception", reception)
	end
	local r: any = if ok and type(reception) == "table" then reception else {}
	return { Arrive = U.clampNumber(r.Arrive, 0.2, 1, 1), Triage = r.Triage == true }
end

-- The best Medic on duty (Nurses.medic): urgent patients' patience drains this much slower (1 = none).
function U.medicOf(plot: Plot): number
	local ok, medic = pcall(Nurses.medic, plot)
	if not ok then
		report("Nurses.medic", medic)
	end
	return U.clampNumber(if ok and type(medic) == "table" then (medic :: any).Patience else nil, 1, K.MAX_SLOWER, 1)
end

-- A Calm Song is pausing every patience ring at this plot (Abilities.patiencePaused).
function U.abilityPaused(plot: Plot): boolean
	local ok, paused = pcall(Abilities.patiencePaused, plot)
	if not ok then
		report("Abilities.patiencePaused", paused)
		return false
	end
	return paused == true
end

-- The owner's perks and tree, as patients use them (Logic/Rebirth.effects on the live save).
function U.effectsOf(owner: Player): Effects
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
		Arrive = U.clampNumber(e.Arrive, 0.2, 1, 1),
		SirenPro = U.clampNumber(e.SirenPro, 1, 4, 1),
		NightOwl = e.NightOwl == true,
		TwinCounters = e.TwinCounters == true,
	}
end

-- The owner's rebirths (Data.Rebirth.Count; 0 before any).
function U.rebirthsOf(owner: Player): number
	local data = PlayerData.get(owner)
	local rebirth = if data then (data :: any).Rebirth else nil
	return math.floor(U.clampNumber(if type(rebirth) == "table" then rebirth.Count else nil, 0, 1e6, 0))
end

-- The rooms the owner's save owns ({ [RoomId]: true }).
function U.roomsOf(owner: Player): { [string]: boolean }
	local data = PlayerData.get(owner)
	local out: { [string]: boolean } = {}
	local rooms = if data then (data :: any).Rooms else nil
	if type(rooms) == "table" then
		for roomId, owned in rooms do
			if type(roomId) == "string" and owned == true then
				out[roomId] = true
			end
		end
	end
	return out
end

local function alive(p: Patient): boolean
	return p.Phase ~= "Gone" and p.Plot.Active
end

local function sleep(p: Patient, seconds: number): boolean
	task.wait(seconds)
	return alive(p)
end

------------------------------------------------------------------------------------------------------------------
-- Pure rules (no Roblox services; tests/HospitalPatients.spec and tests/ServerPure.spec load this block on its own
-- with Recipe = Logic/Recipe, Hospital = Logic/Hospital, Visit = Logic/Visit, Cases = Data/Cases, Items = Data/Items
-- and Tools = Data/Tools)
------------------------------------------------------------------------------------------------------------------

-- PURE-BEGIN
local Pure = {}

-- What one Treat at a bay takes: the plan slots the helper's own items fill, then the ones the nurse tray fills (each
-- in plan order; each item fills one slot). Carry first, so a kid's own fetching always counts.
function Pure.plan(plan: { string }, done: { boolean }, carried: { string }, tray: { string }): ({ number }, { number })
	local fromCarry = Recipe.match(plan, done, carried)
	local fromTray = Recipe.match(plan, Recipe.apply(done, fromCarry), tray)
	return fromCarry, fromTray
end

-- Those plan slots split by what they hold, each in plan order: medicines (handed over at once, no game) and
-- supplies (one game each).
function Pure.split(plan: { string }, indices: { number }): ({ number }, { number })
	local medicines: { number }, supplies: { number } = {}, {}
	local sorted = table.clone(indices)
	table.sort(sorted)
	for _, index in sorted do
		local item = rawget(Items :: any, plan[index] or "")
		if type(item) == "table" and item.Kind == "Medicine" then
			table.insert(medicines, index)
		else
			table.insert(supplies, index)
		end
	end
	return medicines, supplies
end

-- The items at those plan slots, in that order.
function Pure.itemsAt(plan: { string }, indices: { number }): { string }
	local out: { string } = {}
	for _, index in indices do
		local item = plan[index]
		if type(item) == "string" then
			table.insert(out, item)
		end
	end
	return out
end

-- Can this clinic treat that case right now? plotState = { Level, Rooms ({ [RoomId]: boolean }: the rooms owned),
-- Stations ({ [StationId]: boolean }: the open stations), Bays ({ Exam: boolean?, XRay: boolean? }: a usable bay of
-- that kind) }. Its level, its room and every plan step's station (Logic/Visit.canTreat), its exam tool in use at
-- the level (the X-ray from Lv 3), and a bay of its kind (an X-ray case needs the X-ray bay).
function Pure.eligible(case: any, plotState: any): boolean
	if type(case) ~= "table" or type(plotState) ~= "table" then
		return false
	end
	local stations = if type(plotState.Stations) == "table" then plotState.Stations else {}
	local rooms = if type(plotState.Rooms) == "table" then plotState.Rooms else {}
	local level = if type(plotState.Level) == "number" then plotState.Level else 1
	local function open(stationId: string): boolean
		return stations[stationId] == true
	end
	if not Visit.canTreat(case, level, rooms, open, Items) then
		return false
	end
	local tool = rawget(Tools :: any, case.Tool)
	if type(tool) ~= "table" or level < (if type(tool.Level) == "number" then tool.Level else 1) then
		return false
	end
	local kind = if case.Tool == Visit.XRAY then "XRay" else "Exam"
	return type(plotState.Bays) == "table" and plotState.Bays[kind] == true
end

-- A wing's case pool (Data/Cases.POOLS; a wing without one uses the Starter pool).
function Pure.poolFor(wing: any): { string }
	local pools: any = Cases.POOLS
	local pool = if type(wing) == "string" then pools[wing] else nil
	return if type(pool) == "table" then pool else pools.Starter
end

-- The case a patient of that wing brings to this clinic: rolled from its pool, cut to what the clinic can treat
-- (Logic/Visit.rollCase with Pure.eligible). nil = none of its cases can be treated here (it doesn't come).
function Pure.pickCase(wing: any, plotState: any, roll: number): string?
	return Visit.rollCase(Pure.poolFor(wing), function(caseId: string): boolean
		return Pure.eligible(rawget(Cases :: any, caseId), plotState)
	end, roll)
end

-- Bath-wing patients need the Bath Room and Winter-wing ones the Winter Wing, as they always did (their own case is
-- treated in that room). Every other wing: true.
Pure.WING_ROOMS = { Bath = "BathRoom", Winter = "WinterWing" }
function Pure.wingRoom(wing: any, rooms: any): boolean
	local need = if type(wing) == "string" then Pure.WING_ROOMS[wing] else nil
	return need == nil or (type(rooms) == "table" and rooms[need] == true)
end

-- What the open stations make: { [ItemId]: true } (every medicine when the dispensary is open).
function Pure.makes(stations: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(stations) ~= "table" then
		return out
	end
	for _, itemId in Items.Order do
		local item = rawget(Items :: any, itemId)
		if type(item) == "table" and stations[item.Station] == true then
			out[itemId] = true
		end
	end
	return out
end

-- The tutorial patient's case: the first Lv 1 case (Data/Cases.ORDER) with no room and no ward stay whose plan
-- starts at `stationId` and that this clinic can treat (Remedy: a cough; Plaster: a cut knee). nil = none here.
function Pure.tutorialCase(stationId: string, plotState: any): string?
	for _, caseId in Cases.ORDER do
		local case: any = rawget(Cases :: any, caseId)
		local first = if type(case) == "table" then rawget(Items :: any, case.Plan[1] or "") else nil
		if
			type(first) == "table"
			and first.Station == stationId
			and (case.Level or 1) <= 1
			and case.Room == nil
			and case.Stay == nil
			and Pure.eligible(case, plotState)
		then
			return caseId
		end
	end
	return nil
end

-- A player's exams so far: the saved counter Stats.Exams (Pure.EXAMS_STAT). It is the exam's OWN count, never the
-- patients treated: a save from before the Real Clinic has treated plenty and examined nobody, so its first exams
-- glow too. Junk -> 0.
Pure.EXAMS_STAT = "Exams"
function Pure.examsDone(data: any): number
	local stats = if type(data) == "table" then data.Stats else nil
	local value = if type(stats) == "table" then stats[Pure.EXAMS_STAT] else nil
	return if type(value) == "number" and value == value and value > 0 then math.floor(value) else 0
end

-- The exam card: Logic/Visit.examTools over the tools in use at the level, and whether the right one glows
-- (Logic/Visit.glow: a player's first exams by their saved count, and always in Simple mode).
function Pure.examCard(
	case: any,
	level: number,
	examsDone: number,
	simple: boolean,
	roll: number,
	cfg: any
): ({ string }, boolean)
	local answer = if type(case) == "table" and type(case.Tool) == "string" then case.Tool else ""
	return Visit.examTools(answer, Visit.unlocked(level, Tools), roll), Visit.glow(examsDone, simple, cfg)
end

-- The symptom bubble's emoji and words ("😷 cough cough" -> "😷", "cough cough").
function Pure.bubbleParts(text: any): (string, string)
	if type(text) ~= "string" then
		return "", ""
	end
	local emote, words = string.match(text, "^(%S+)%s+(.+)$")
	if emote and words then
		return emote, words
	end
	return text, ""
end

-- Which waiting patient each free bay takes, the bays in order: Logic/Visit.nextForBay for that bay's Kind. `free` =
-- { { Id, Kind } } (the usable empty bays, in Logic/Building.BAYS order), `waiting` = { { Id, Since, Tool } }.
-- Returns { { Bay, Patient } }; each patient takes at most one bay.
function Pure.assign(free: { { Id: string, Kind: string } }, waiting: { any }): { { Bay: string, Patient: number } }
	local left = table.clone(waiting)
	local out: { { Bay: string, Patient: number } } = {}
	for _, bay in free do
		local id = Visit.nextForBay(left, bay.Kind :: any)
		if id then
			table.insert(out, { Bay = bay.Id, Patient = id })
			for index, row in left do
				if row.Id == id then
					table.remove(left, index)
					break
				end
			end
		end
	end
	return out
end

-- Whether a bay may call this patient now (Joshua, 2026-11-17: "when the patient first arrives, he should sit down
-- at the chair"). A 🚑/🚁 patient (`urgent`) always: it goes straight to its bay. Anyone else only once it has
-- settled in the waiting room (`seatedAt`: os.clock() it sat down, or stood with every seat taken; nil = not yet)
-- at least `seconds` ago (Config.Visit.SeatSeconds), even with a bay free. Settled once counts for the whole visit,
-- so a patient whose bay closed may take the next free bay at once.
function Pure.mayCall(now: number, seatedAt: number?, urgent: boolean, seconds: number): boolean
	if urgent == true then
		return true
	end
	if type(now) ~= "number" or type(seatedAt) ~= "number" then
		return false
	end
	local wait = if type(seconds) == "number" and seconds == seconds then math.max(seconds, 0) else 0
	return now - seatedAt >= wait
end

-- The bay patients who need the doctor, the front first (Logic/Visit.front, then the next, ...). rows = { { Id,
-- Since, NeedsDoctor } }.
function Pure.frontOrder(rows: { any }): { number }
	local left = table.clone(rows)
	local out: { number } = {}
	while true do
		local id = Visit.front(left)
		if not id then
			break
		end
		table.insert(out, id)
		for index, row in left do
			if row.Id == id then
				table.remove(left, index)
				break
			end
		end
	end
	return out
end

-- Who sits where after the bays open by the numbers changed (Review Focus 2: a rebuilt Building, a lower level, a
-- room the save no longer owns). `list` = { { Id, Seat: number?, Bay: string? } } in waiting order (a patient walking
-- in has neither and isn't listed), `seats` = the seat numbers there are ({ [number]: boolean }), `bays` = the bays
-- open now ({ [BayId]: boolean }). Each keeps its bay or seat while it's still there; one whose bay closed (or whose
-- seat is gone) takes the lowest free seat; with none free it goes home ("Leave": no penalty, never sad). Returns
-- { [Id]: { Seat: number?, Bay: string?, Leave: boolean } } for everyone listed.
function Pure.reseat(list: { any }, seats: { [number]: boolean }, bays: { [string]: boolean }): { [number]: any }
	local out: { [number]: any } = {}
	local taken: { [number]: boolean } = {}
	local homeless: { any } = {}
	for _, row in list do
		if type(row.Bay) == "string" and bays[row.Bay] == true then
			out[row.Id] = { Bay = row.Bay, Seat = nil, Leave = false }
		elseif type(row.Seat) == "number" and seats[row.Seat] == true and not taken[row.Seat] then
			taken[row.Seat] = true
			out[row.Id] = { Seat = row.Seat, Bay = nil, Leave = false }
		else
			table.insert(homeless, row)
		end
	end
	local free: { number } = {}
	for seat, there in seats do
		if there == true and not taken[seat] then
			table.insert(free, seat)
		end
	end
	table.sort(free)
	for _, row in homeless do
		local seat = table.remove(free, 1)
		out[row.Id] = if seat
			then { Seat = seat, Bay = nil, Leave = false }
			else { Seat = nil, Bay = nil, Leave = true }
	end
	return out
end

-- The owner left (Review Focus 4): everyone goes home now. A patient whose plan is complete, or completes with the
-- slots in its open game (InFlight), is paid first ("Pay"): the helper never loses their work. Everyone else just goes
-- ("Leave"), never sad. list = { { Id, Plan, Done, InFlight: { number }?, Paid: boolean? } }.
function Pure.closing(list: { any }): { [number]: string }
	local out: { [number]: string } = {}
	for _, row in list do
		local plan = if type(row.Plan) == "table" then row.Plan else {}
		local done = if type(row.Done) == "table" then row.Done else {}
		if type(row.InFlight) == "table" then
			done = Recipe.apply(done, row.InFlight)
		end
		local complete = #plan > 0 and Recipe.complete(plan, done)
		out[row.Id] = if complete and row.Paid ~= true then "Pay" else "Leave"
	end
	return out
end

-- Where a patient who stays rests (`ward` = Logic/Visit.stayWard): a free bed in its own ward, else a free bed in the
-- other ward, else "Home" (every bed taken: it goes home now, no penalty). free = { Wards: boolean?, Rest: boolean? }.
function Pure.destination(ward: string?, free: any): string
	if ward ~= "Wards" and ward ~= "Rest" then
		return "Home"
	end
	local spots = if type(free) == "table" then free else {}
	if spots[ward] then
		return ward :: string
	end
	local other = if ward == "Wards" then "Rest" else "Wards"
	if spots[other] then
		return other
	end
	return "Home"
end

-- After the plan: "Home" now, or the ward it rests in first (Logic/Visit.stayWard at that level, then
-- Pure.destination with the free beds).
function Pure.afterPlan(case: any, level: number, free: any): string
	return Pure.destination(Visit.stayWard(case, level), free)
end

-- It really rests in its own ward. Only then is "Which ward?" a true question (one in the other ward because its own
-- is full would make the right answer look wrong).
function Pure.routed(ward: string?, kind: string?): boolean
	return (ward == "Wards" or ward == "Rest") and kind == ward
end

-- The ward pick once the plan is complete. "None": fewer than two wards open (below Lv 3), it isn't going to its own
-- ward (`routed` false: no question, no bonus), or nobody to ask (a nurse or a handed-over medicine finished it);
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

-- A pick earns the bonus only when it's the right ward ("" = no pick in time: no bonus).
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

-- The visit's situational cash factor (CureCtx.Extra): Escort/Porter x a right ward pick x the team's cash x Ward
-- Comfort. `cfg` = Config (Escort, Triage, WardComfort). Clamped to 1..maxExtra.
function Pure.extra(
	f: { Escorted: boolean?, Triage: boolean?, Team: number?, Comfort: number? },
	cfg: any,
	maxExtra: number
): number
	local value = 1
	if f.Escorted then
		value *= 1 + bonus(cfg.Escort and cfg.Escort.CashBonus)
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

-- Rest seconds in a ward bed (Logic/Hospital.recover, never under 0.5 s): base x the escort's RecoverFactor x
-- (1 - RecoverPerLevel x Ward Comfort) x the team's Recover factor.
function Pure.rest(base: number, f: { Escorted: boolean?, Comfort: number?, Team: number? }, cfg: any): number
	local perLevel = cfg.WardComfort and cfg.WardComfort.RecoverPerLevel
	local comfort = 1 - (if type(perLevel) == "number" then perLevel else 0) * comfortLevel(f.Comfort)
	return Hospital.recover(base, {
		if f.Escorted then factor(cfg.Escort and cfg.Escort.RecoverFactor) else 1,
		math.max(comfort, 0.05),
		math.min(factor(f.Team), 1),
	})
end

-- An urgent patient's plan at this clinic (`makes` = { [ItemId]: true }): Logic/Hospital.urgentRecipe (at least
-- minItems steps, a one-step plan padded with a 🧊 Ice pack), or, when a step of it is made by no station here, the
-- same with those steps left out (its first step must stay). nil when nothing can be made of it.
function Pure.urgentFor(plan: { string }, makes: { [string]: boolean }, cap: number, minItems: number): { string }?
	local direct = Hospital.urgentRecipe(plan, makes, cap, minItems)
	if direct then
		return direct
	end
	local kept: { string } = {}
	for _, item in plan do
		if makes[item] == true then
			table.insert(kept, item)
		end
	end
	if #kept == 0 or kept[1] ~= plan[1] then
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

-- May a patient of this wing (a Data/Wings row) come to a clinic whose owner has `rebirths`? By the front doors:
-- only wings without `Only`, once Rebirths are reached (🌻 Sunny from R1). By air (`byAir`): only "Helicopter" wings
-- (🚁 Sky; the helicopter itself only flies from R2).
function Pure.wingOpen(wing: any, rebirths: number, byAir: boolean): boolean
	local only = if type(wing) == "table" then wing.Only else nil
	if byAir then
		return only == "Helicopter"
	end
	local need = if type(wing) == "table" and type(wing.Rebirths) == "number" then wing.Rebirths else 0
	return only == nil and rebirths >= need
end

-- The first plan slot still missing, or nil when the plan is complete.
function Pure.firstMissing(plan: { string }, done: { boolean }): number?
	for index in plan do
		if not done[index] then
			return index
		end
	end
	return nil
end

-- What a patient still needs, not counting the slots in a game right now (`inFlight`).
function Pure.needs(plan: { string }, done: { boolean }, inFlight: { number }?): { string }
	return Recipe.missing(plan, if inFlight then Recipe.apply(done, inFlight) else done)
end

-- The dispensary's options: the medicine steps the bay patients still need (`rows` oldest first, each with Needs),
-- distinct, at most `max`.
function Pure.medicines(rows: { any }, max: number): { string }
	local out: { string } = {}
	for _, row in rows do
		for _, itemId in (if type(row.Needs) == "table" then row.Needs else {}) do
			local item = rawget(Items :: any, itemId)
			if #out < max and type(item) == "table" and item.Kind == "Medicine" and not table.find(out, itemId) then
				table.insert(out, itemId)
			end
		end
	end
	return out
end

-- Patience after `count` steps were given: each refills `share` of the most it can hold.
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
-- Where things are: plot-local numbers (Logic/Building) <-> the world
------------------------------------------------------------------------------------------------------------------

-- A plot-local point on a floor, at that floor's nominal height.
function U.worldAt(state: PlotState, x: number, z: number, floor: number?): Vector3
	return state.Pivot * Vector3.new(x, Building.slabTop(floor or 0), z)
end

function U.localOf(state: PlotState, position: Vector3): Point
	local here = state.Pivot:PointToObjectSpace(position)
	return { X = here.X, Z = here.Z }
end

-- The surface under a world point on that floor: a short ray down onto the tiles, a slab, the pad, or the top of a
-- seat or a bed (solid parts only); the floor's nominal height when nothing is there.
local function surface(state: PlotState, position: Vector3, floor: number?): Vector3
	local nominal = state.Pivot.Position.Y + Building.slabTop(floor or 0)
	local from = Vector3.new(position.X, nominal + K.RAY_UP, position.Z)
	local hit = Workspace:Raycast(from, Vector3.new(0, -K.RAY_UP * 2, 0), state.FloorRay)
	return Vector3.new(position.X, if hit then hit.Position.Y else nominal, position.Z)
end

-- A plot-local direction as a world one.
local function worldDir(state: PlotState, dx: number, dz: number): Vector3
	return state.Pivot:VectorToWorldSpace(Vector3.new(dx, 0, dz))
end

-- Standing at `at`, facing along `dir` (level).
local function facing(at: Vector3, dir: Vector3): CFrame
	local flat = dir * Vector3.new(1, 0, 1)
	return if flat.Magnitude > 0.01 then CFrame.lookAt(at, at + flat.Unit) else CFrame.new(at)
end

-- Markers are 2x1x2 and rest on what they mark: their bottom face is that surface, facing as they face.
function U.markerGround(marker: BasePart): CFrame
	return marker.CFrame * CFrame.new(0, -marker.Size.Y / 2, 0)
end

-- A resting pivot standing on floor `floor` at `cf` (a lift landing, a spot), facing the way it faces.
function U.standAt(state: PlotState, cf: CFrame, floor: number): CFrame
	return facing(surface(state, cf.Position, floor), cf.LookVector)
end

-- The floor a part of the building is on: the nearest "Floor" attribute or Floor_<n> Model above it; 0 = the ground.
function U.floorOf(part: Instance, stop: Instance): number
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

-- A named marker anywhere in the plot's Building (StretcherSpot, HeliSpot, ...), or nil.
function U.buildingPart(state: PlotState, name: string): BasePart?
	local building = state.Plot.Model:FindFirstChild("Building")
	local found = building and building:FindFirstChild(name, true)
	return if found and found:IsA("BasePart") then found else nil
end

-- The owner stands at their clinic (their plot, any floor, give or take PLOT_MARGIN).
function U.ownerAtClinic(state: PlotState): boolean
	local character = state.Owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	local here = state.Pivot:PointToObjectSpace(root.Position)
	local half = Config.Town.PlotSize / 2 + K.PLOT_MARGIN
	return math.abs(here.X) <= half and math.abs(here.Z) <= half
end

-- The names of the plot's room models (a bought or lost room changes it).
function U.roomsKey(state: PlotState): string
	local rooms = state.Plot.Model:FindFirstChild("Rooms")
	if not rooms then
		return ""
	end
	local names: { string } = {}
	for _, child in rooms:GetChildren() do
		table.insert(names, child.Name)
	end
	table.sort(names)
	return table.concat(names, ",")
end

-- Looks up the seats' markers, the exam bays, the open stations and the ward beds in the plot's Building and Rooms.
local function scanLayout(state: PlotState, building: Instance?, key: string, now: number): Layout
	local model = state.Plot.Model
	local rooms = model:FindFirstChild("Rooms")
	local layout: Layout =
		{ Building = building, Key = key, At = now, Seats = {}, Bays = {}, Stations = {}, Beds = {}, RoomBeds = {} }
	-- A bought room's own recovery bed (the Winter Wing's Bed_1): its case's patients rest there (restInRoom).
	if rooms then
		for _, room in rooms:GetChildren() do
			local roomId = string.match(room.Name, "^Room_(%w+)$")
			local bed = if roomId then room:FindFirstChild("Bed_1", true) else nil
			if roomId and bed and bed:IsA("BasePart") then
				layout.RoomBeds[roomId] =
					{ Key = "Room:" .. roomId, Part = bed, Floor = 0, X = 0, Ward = "Room", Room = roomId }
			end
		end
	end
	if building then
		for index in Building.SEATS do
			local marker = building:FindFirstChild("WaitSeat_" .. index, true)
			if marker and marker:IsA("BasePart") then
				layout.Seats[index] = marker
			end
		end
	end
	for _, info in Building.BAYS do
		local name = "ExamBay_" .. info.Id
		local found = (building and building:FindFirstChild(name, true)) or (rooms and rooms:FindFirstChild(name, true))
		if found and found:IsA("Model") and found:GetAttribute("Open") ~= false then
			local bed = found:FindFirstChild("Bed")
			local spot = found:FindFirstChild("DoctorSpot")
			layout.Bays[info.Id] = {
				Id = info.Id,
				Kind = info.Kind,
				Info = info,
				Model = found,
				Bed = if bed and bed:IsA("BasePart") then bed else nil,
				Spot = if spot and spot:IsA("BasePart") then spot else nil,
			}
		end
	end
	-- The stations: a Station_<id> Part by contract (a kit room may use a Model), open unless it says Open = false.
	local inBuilding = false
	for _, holder in { building, rooms } do
		if holder then
			for _, descendant in holder:GetDescendants() do
				if descendant:IsA("BasePart") or descendant:IsA("Model") then
					local stationId = string.match(descendant.Name, "^Station_(%w+)$")
					if stationId and descendant:GetAttribute("Open") ~= false then
						layout.Stations[stationId] = true
						inBuilding = inBuilding or holder == building
					end
				end
			end
		end
	end
	if not inBuilding then
		-- A Building without Station_ parts (a kit one, or one still being built): its stations by the numbers.
		for stationId in Building.STATIONS do
			if Building.stationOpen(stationId, state.Level) then
				layout.Stations[stationId] = true
			end
		end
	end
	if building then
		for floor, list in Building.WARD_BEDS do
			local floorModel = building:FindFirstChild("Floor_" .. floor, true)
			for index, spot in list do
				local holder = floorModel and floorModel:FindFirstChild("BedSpot_" .. index, true)
				local bed = holder and holder:FindFirstChild("Bed_" .. index, true)
				if bed and bed:IsA("BasePart") then
					local ward = bed:GetAttribute("Ward")
					local bedKey = floor .. ":" .. index
					layout.Beds[bedKey] = {
						Key = bedKey,
						Part = bed,
						Floor = floor,
						X = spot.X,
						Ward = if ward == "Wards" or ward == "Rest" then ward else spot.Ward,
					}
				end
			end
		end
	end
	return layout
end

-- A bay a patient may be sent to now: built (its Model is there) and open by the numbers (level and rooms).
local function bayUsable(state: PlotState, bayId: string): boolean
	local spot = state.Layout.Bays[bayId]
	return spot ~= nil and spot.Model.Parent ~= nil and Building.bayOpen(spot.Info, state.Level, state.Rooms)
end

-- The places a patient can be sent to, for Logic/Routing: every usable bay in Logic/Building.BAYS order, Free = empty.
function U.places(state: PlotState): { { Id: string, Kind: string, X: number, Z: number, Free: boolean } }
	local out = {}
	for _, info in Building.BAYS do
		if bayUsable(state, info.Id) then
			table.insert(
				out,
				{ Id = info.Id, Kind = info.Kind, X = info.X, Z = info.Z, Free = state.BayOf[info.Id] == nil }
			)
		end
	end
	return out
end

-- A patient's own "Send" prompt, made once as it comes (off until it waits to be sent: refreshPrompts). Tagged
-- TreatPrompt, so UI/PromptFilter shows it only to those who may work this clinic; the server checks again
-- (U.onSendPrompt).
function U.sendPrompt(state: PlotState, p: Patient): ProximityPrompt
	local attachment = Instance.new("Attachment")
	attachment.Name = "SendPromptAt"
	attachment.Parent = p.Root
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SendPrompt"
	prompt.ActionText = K.Routing.TEXT.Action
	prompt.ObjectText = p.Symptom
	prompt.HoldDuration = 0 -- a tap: no precision timing
	prompt.MaxActivationDistance = K.PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Enabled = false
	prompt:SetAttribute("VisitId", p.Id)
	prompt:SetAttribute("Choice", false)
	prompt:AddTag("TreatPrompt")
	prompt.Parent = attachment
	local plot, visitId = state.Plot, p.Id
	prompt.Triggered:Connect(function(player: Player)
		U.onSendPrompt(plot, visitId, player)
	end)
	return prompt
end

-- What this clinic can treat right now (Pure.eligible's plotState).
local function plotView(state: PlotState): any
	local bays = { Exam = false, XRay = false }
	for bayId, spot in state.Layout.Bays do
		if bayUsable(state, bayId) then
			(bays :: any)[spot.Kind] = true
		end
	end
	return { Level = state.Level, Rooms = state.Rooms, Stations = state.Layout.Stations, Bays = bays }
end

-- How this creature sits (Logic/CreatureSize.seatFit's fit, in studs from its pivot at its size now): Hip = its
-- Body's bottom, Body = how far its Body and Head reach back, Reach = how far any part but its tail reaches back (the
-- client curls the tail up). A kit model with no Body: its whole box, sitting on its bottom.
function U.sitFit(p: Patient): { Hip: number, Body: number, Reach: number }
	local fit = { Hip = 0, Body = 0, Reach = 0 }
	local root = p.Root
	local found = false
	local core = p.Model:FindFirstChild("Core")
	local curls = core ~= nil and core:FindFirstChild("TailJoint") ~= nil -- a tail on its joint: the client curls it
	for _, part in p.Model:GetDescendants() do
		if not part:IsA("BasePart") or part == root or part.Name == "Core" or part.Transparency >= 1 then
			continue
		end
		local rel = root.CFrame:ToObjectSpace(part.CFrame)
		local _, y, z, _, _, _, r10, r11, r12, r20, r21, r22 = rel:GetComponents()
		local size = part.Size
		local back = z + (math.abs(r20) * size.X + math.abs(r21) * size.Y + math.abs(r22) * size.Z) / 2
		if part.Name == "Body" or part.Name == "Head" then
			fit.Body = math.max(fit.Body, back)
			if part.Name == "Body" then
				fit.Hip = y - (math.abs(r10) * size.X + math.abs(r11) * size.Y + math.abs(r12) * size.Z) / 2
				found = true
			end
		end
		if not (curls and (part.Name == "Tail" or part.Name == "TailTip")) then
			fit.Reach = math.max(fit.Reach, back)
		end
	end
	if not found then
		fit.Body = fit.Reach
	end
	return fit
end

-- A seat's pose for patient `p`: sitting on the seat (its WaitSeat_<n> marker, else the seat's top under its numbers)
-- facing out of it into the room, its bottom on the seat top and its back against the chair back
-- (Logic/CreatureSize.seatFit: a big creature sits further forward, so it never pokes through the back or the wall).
function U.seatPose(state: PlotState, index: number, p: Patient): CFrame
	local seat = Building.SEATS[index]
	local dx, dz = Building.facing(seat.Face)
	local marker = state.Layout.Seats[index]
	local at = if marker and marker.Parent
		then U.markerGround(marker).Position
		else surface(state, U.worldAt(state, seat.X, seat.Z, 0), 0)
	local half = Building.SEAT_SIZE / 2
	local forward, drop = K.CreatureSize.seatFit(U.sitFit(p), { Cushion = half - K.SEAT_BACK, Wall = half })
	return facing(at, worldDir(state, dx, dz)) * CFrame.new(0, -drop, -forward)
end

-- On its seat or not: OnSeat and the model's Seated attribute together (Feel/CreatureActing settles it into the sit
-- while it's set: a little recline, its tail curled up). Every way off a seat comes through here.
function U.setSeated(p: Patient, on: boolean)
	p.OnSeat = on
	p.Model:SetAttribute("Seated", if on then true else nil)
end

-- On a bay bed (the Bed's top), facing its foot (the DoctorSpot).
function U.bayPose(state: PlotState, info: BayInfo): CFrame
	local dx, dz = Building.facing(info.Face)
	local centre = U.worldAt(state, info.X, info.Z, 0)
	local spot = state.Layout.Bays[info.Id]
	local bed = spot and spot.Bed
	local at = if bed and bed.Parent
		then Vector3.new(centre.X, bed.Position.Y + bed.Size.Y / 2, centre.Z)
		else surface(state, centre, 0)
	return facing(at, worldDir(state, dx, dz))
end

-- The bay's DoctorSpot in the world (where the doctor stands and the prompt is).
function U.spotWorld(state: PlotState, bayId: string): Vector3
	local spot = state.Layout.Bays[bayId]
	local part = spot and spot.Spot
	if part and part.Parent then
		return part.Position
	end
	local info = Building.bay(bayId)
	local point = if info then Building.doctorSpot(info) else { X = 0, Z = 0 }
	return U.worldAt(state, point.X, point.Z, 0) + Vector3.new(0, 1, 0)
end

-- In a ward bed (the Bed's top), facing its foot (+z: the pillow is against the tower's street wall). Lying =
-- leaning back onto the pillow.
function U.wardPose(state: PlotState, bed: WardBed, lying: boolean, scale: number): CFrame
	local centre = U.worldAt(state, bed.X, Building.BED_Z, bed.Floor)
	local part = bed.Part
	local at = if part.Parent
		then Vector3.new(part.Position.X, part.Position.Y + part.Size.Y / 2, part.Position.Z)
		else surface(state, centre, bed.Floor)
	local cf = facing(at, worldDir(state, 0, 1))
	if lying then
		return cf * CFrame.new(0, 0.35 * scale, 0) * CFrame.Angles(math.rad(58), 0, 0)
	end
	return cf
end

-- The free ward beds the lift reaches at this level: one of each ward (the lowest floor, then the lowest number).
function U.freeBeds(state: PlotState): { [string]: WardBed }
	local out: { [string]: WardBed } = {}
	local plot = state.Plot
	if U.landingOf(plot, 0) == nil then
		return out
	end
	local reach: { [number]: boolean } = {}
	local open = Building.floors(state.Level)
	for bedKey, bed in state.Layout.Beds do
		if state.Beds[bedKey] == nil and bed.Part.Parent and bed.Floor <= open then
			if reach[bed.Floor] == nil then
				reach[bed.Floor] = U.landingOf(plot, bed.Floor) ~= nil
			end
			local best = out[bed.Ward]
			if
				reach[bed.Floor]
				and (best == nil or bed.Floor < best.Floor or (bed.Floor == best.Floor and bedKey < best.Key))
			then
				out[bed.Ward] = bed
			end
		end
	end
	return out
end

-- The free recovery bed of a bought room (`roomId` = a case's Room): the Winter Wing's own bed, for its chills
-- patients. nil when the room isn't owned, has no bed, or its bed is taken.
function U.freeRoomBed(state: PlotState, roomId: string?): WardBed?
	if not roomId or state.Rooms[roomId] ~= true then
		return nil
	end
	local bed = state.Layout.RoomBeds[roomId]
	if bed and bed.Part.Parent and state.Beds[bed.Key] == nil then
		return bed
	end
	return nil
end

-- In a room's own bed (the Bed's top). Its pillow end is +z (the room's back), so it faces its foot, -z. Lying =
-- leaning back onto the pillow.
function U.roomBedPose(state: PlotState, bed: WardBed, lying: boolean, scale: number): CFrame
	local part = bed.Part
	local at = Vector3.new(part.Position.X, part.Position.Y + part.Size.Y / 2, part.Position.Z)
	local cf = facing(at, worldDir(state, 0, -1))
	if lying then
		return cf * CFrame.new(0, 0.35 * scale, 0) * CFrame.Angles(math.rad(58), 0, 0)
	end
	return cf
end

------------------------------------------------------------------------------------------------------------------
-- The animator: attributes the clients draw (Feel/CreatureMotion); the server only writes where each one ends
------------------------------------------------------------------------------------------------------------------

-- The creature's scale right now, as the clients draw it (so a new grow/shrink starts from where the last one is).
function U.currentScale(p: Patient): number
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
	CreatureBuilder.hop(p.Model, p.Pivot, to, duration, height, spin or 0, if spin then 0 else K.LEAN)
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
		From = math.max(U.currentScale(p), 0.02),
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
			if p.Phase ~= "Gone" then
				p.Model:ScaleTo(anim.To)
			end
		end
	end)
end

-- Hops along world points on floor `floor`, a few studs per hop, each landing on that floor, turning to face where
-- it's going.
local function walk(p: Patient, points: { Vector3 }, floor: number?): boolean
	local state = p.Plot
	for _, point in points do
		while true do
			local from = p.Pivot.Position
			local delta = Vector3.new(point.X - from.X, 0, point.Z - from.Z)
			local distance = delta.Magnitude
			if distance < 0.05 then
				break
			end
			local stepLength = distance / math.ceil(distance / K.HOP_LENGTH)
			local direction = delta / distance
			local landing = surface(state, from + direction * stepLength, floor)
			local seconds = p.HopSeconds * math.sqrt(stepLength / K.HOP_LENGTH)
			if not hop(p, CFrame.lookAt(landing, landing + direction), p.HopHeight, seconds) then
				return false
			end
		end
	end
	return true
end

-- Walks to a plot-local point on its floor, round the walls and through open doors (Logic/Building.path at the
-- clinic's level). Straight there when the Building finds no way (a kit building, a shut door): never stuck.
local function walkTo(p: Patient, to: Point, floor: number?): boolean
	local state = p.Plot
	local k = floor or 0
	local ok, path = pcall(Building.path, U.localOf(state, p.Pivot.Position), to, state.Level, k)
	if not ok then
		report("Building.path", path)
	end
	local points: { Point } = if ok and type(path) == "table" then path else { to }
	local world: { Vector3 } = {}
	for _, point in points do
		table.insert(world, U.worldAt(state, point.X, point.Z, k))
	end
	return walk(p, world, k)
end

-- A droop over everything else (the clients draw it); 0 = upright.
local function setTilt(p: Patient, radians: number)
	CreatureBuilder.tilt(p.Model, radians)
end

------------------------------------------------------------------------------------------------------------------
-- Badge, attributes, the front patient and the bay prompts
------------------------------------------------------------------------------------------------------------------

local function setState(p: Patient, state: string)
	p.Model:SetAttribute("State", state)
end

-- The State a patient on a bay bed shows.
local function bayState(p: Patient): string
	if p.Session then
		return if p.SessionKind == "Exam" then "Examining" else "Treating"
	end
	return if p.Examined then "Planned" else "AtBay"
end

local function ringColor(fraction: number): Color3
	if fraction > 0.5 then
		return K.RING_CALM
	elseif fraction > 0.25 then
		return K.RING_HURRY
	end
	return K.RING_LOW
end

-- The PatienceFraction attribute for the client's acting (Feel/CreatureActing), only when its 0.05 step changes.
local function showPatience(p: Patient, fraction: number)
	local shown = math.ceil(math.clamp(fraction, 0, 1) * K.PATIENCE_STEPS) / K.PATIENCE_STEPS
	if shown ~= p.PatienceShown then
		p.PatienceShown = shown
		p.Model:SetAttribute("PatienceFraction", shown)
	end
end

local function showRing(p: Patient, fraction: number, color: Color3)
	local stepIndex = math.floor(math.clamp(fraction, 0, 1) * K.RING_STEPS + 0.5)
	if stepIndex == p.RingStep and color == p.RingColor then
		return
	end
	p.RingStep = stepIndex
	p.RingColor = color
	CreatureBuilder.setRing(p.Badge, stepIndex / K.RING_STEPS, color)
end

-- The plan on the model (Plan, PlanDone, Item and Station = the first missing step) and on the badge, once examined.
local function showPlan(p: Patient)
	if not p.Examined then
		return
	end
	local first = Pure.firstMissing(p.Plan, p.Done)
	if first then
		local itemId = p.Plan[first]
		local item = rawget(Items :: any, itemId)
		p.Item = itemId
		p.Station = if type(item) == "table" then item.Station else ""
	end
	p.Model:SetAttribute("Item", p.Item)
	p.Model:SetAttribute("Station", p.Station)
	p.Model:SetAttribute("Plan", Recipe.join(p.Plan))
	p.Model:SetAttribute("PlanDone", Recipe.encode(p.Done))
	local ok, err = pcall(CreatureBuilder.setRecipe, p.Badge, p.Plan, p.Done)
	if not ok then
		report("CreatureBuilder.setRecipe", err)
	end
end

-- The speech bubble over a patient: its symptom, or a regular's story line while it walks in.
local function showBubble(p: Patient, emote: string, text: string)
	local badge = p.Badge
	badge.BubbleEmote.Text = emote
	badge.BubbleText.Text = text
	badge.BubbleText.Visible = text ~= ""
	badge.Bubble.Enabled = true
end

local function showSymptom(p: Patient)
	local emote, words = Pure.bubbleParts(p.Symptom)
	showBubble(p, emote, words)
end

-- On a bay bed and ready for the doctor: not mid-game, not being checked, the plan not done.
local function needsDoctor(p: Patient): boolean
	return p.Phase == "Bay" and p.OnBed and not p.Session and not p.Claimed
end

-- The patients sitting on a bay bed, the longest there first.
local function bayPatients(state: PlotState): { Patient }
	local out: { Patient } = {}
	for p in state.All do
		if p.Phase == "Bay" and p.OnBed then
			table.insert(out, p)
		end
	end
	table.sort(out, function(a: Patient, b: Patient): boolean
		if a.BaySince ~= b.BaySince then
			return a.BaySince < b.BaySince
		end
		return a.Id < b.Id
	end)
	return out
end

-- The bay patients who need the doctor, the front first (Pure.frontOrder).
local function frontList(state: PlotState): { Patient }
	local rows: { any } = {}
	for _, p in bayPatients(state) do
		table.insert(rows, { Id = p.Id, Since = p.BaySince, NeedsDoctor = needsDoctor(p) })
	end
	local out: { Patient } = {}
	for _, id in Pure.frontOrder(rows) do
		local p = state.ById[id]
		if p then
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

-- Each bay's prompt follows its patient: on while it needs the doctor, "Examine" or "Treat", its icon.
local function refreshPrompts(state: PlotState)
	for bayId, prompt in state.Prompts do
		local p = state.BayOf[bayId]
		local on = state.Active and p ~= nil and needsDoctor(p)
		if prompt.Enabled ~= on then
			prompt.Enabled = on
		end
		local action = if p and p.Examined then "Treat" else "Examine"
		if prompt.ActionText ~= action then
			prompt.ActionText = action
		end
		local icon = if p and on then p.Icon else ""
		if prompt.ObjectText ~= icon then
			prompt.ObjectText = icon
		end
	end
	-- Each waiting patient's own "Send" prompt: on while it waits to be sent (Logic/Routing.waiting). Choice = the
	-- client opens the two-button card first (Lv 3+, both kinds of place open).
	local choice = K.Routing.needsChoice(state.Level, U.places(state))
	for p in state.All do
		local prompt = p.Send
		if prompt then
			local on = state.Active and K.Routing.waiting(p.Phase, p.Bay, p.Urgent)
			if prompt.Enabled ~= on then
				prompt.Enabled = on
			end
			if prompt:GetAttribute("Choice") ~= choice then
				prompt:SetAttribute("Choice", choice)
			end
		end
	end
end

-- QueueIndex on every patient, the plot's Front* / QueueNeeds attributes and the prompts follow the clinic. Cheap (a
-- handful of patients), so the clinic tick calls it every TICK too.
local function refreshFront(state: PlotState)
	if active[state.Plot] ~= state then
		return
	end
	local order = frontList(state)
	local rank: { [Patient]: number } = {}
	for index, p in order do
		rank[p] = index
	end
	for p in state.All do
		local index = rank[p] or 0
		if p.QueueIndex ~= index then
			p.QueueIndex = index
			p.Model:SetAttribute("QueueIndex", index)
		end
	end
	local front = order[1]
	local bay, stage, item, station, needs = "", "", "", "", ""
	if front then
		bay = front.Bay or ""
		stage = if front.Examined then "Treat" else "Exam"
		if front.Examined then
			item, station = front.Item, front.Station
		end
		local all: { string } = {}
		local places = if state.Effects.TwinCounters then 2 else 1
		for index = 1, math.min(places, #order) do
			local p = order[index]
			if p.Examined then
				for _, itemId in Pure.needs(p.Plan, p.Done, nil) do
					table.insert(all, itemId)
				end
			end
		end
		needs = Recipe.join(all)
	end
	setPlotAttribute(state, "FrontBay", bay)
	setPlotAttribute(state, "FrontStage", stage)
	setPlotAttribute(state, "FrontItem", item)
	setPlotAttribute(state, "FrontStation", station)
	setPlotAttribute(state, "FrontNeeds", needs)
	local queued: { string } = {}
	for _, p in bayPatients(state) do
		if p.Examined then
			for _, itemId in Pure.needs(p.Plan, p.Done, p.SessionIndices) do
				table.insert(queued, itemId)
			end
		end
	end
	setPlotAttribute(state, "QueueNeeds", Recipe.join(queued))
	refreshPrompts(state)
end

-- One BayPrompt on each built bay's DoctorSpot (its Bed when it has none), made the first time it's seen and wired
-- once. A rebuilt Building brings new DoctorSpots, so new prompts.
local function ensurePrompts(state: PlotState)
	local fresh: { [string]: ProximityPrompt } = {}
	for bayId, spot in state.Layout.Bays do
		local holder: BasePart? = spot.Spot or spot.Bed
		if holder then
			local found = holder:FindFirstChild("BayPromptAt")
			local attachment: Attachment
			if found and found:IsA("Attachment") then
				attachment = found
			else
				attachment = Instance.new("Attachment")
				attachment.Name = "BayPromptAt"
				attachment.Position = Vector3.new(0, K.PROMPT_HEIGHT - holder.Size.Y / 2, 0)
				attachment.Parent = holder
			end
			local existing = attachment:FindFirstChild("BayPrompt")
			local prompt: ProximityPrompt
			if existing and existing:IsA("ProximityPrompt") then
				prompt = existing
			else
				prompt = Instance.new("ProximityPrompt")
				prompt.Name = "BayPrompt"
				prompt.ActionText = "Examine"
				prompt.ObjectText = ""
				prompt.HoldDuration = 0 -- a tap: no precision timing
				prompt.MaxActivationDistance = K.PROMPT_DISTANCE
				prompt.RequiresLineOfSight = false
				prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
				prompt.Enabled = false
				prompt:SetAttribute("Bay", bayId)
				prompt:AddTag("TreatPrompt") -- UI/PromptFilter finds it by this tag (it never scans the whole town)
				prompt.Parent = attachment
			end
			if not promptWired[prompt] then
				promptWired[prompt] = true
				local plot = state.Plot
				prompt.Triggered:Connect(function(player: Player)
					onBayPrompt(plot, bayId, player)
				end)
			end
			fresh[bayId] = prompt
		end
	end
	for bayId, prompt in state.Prompts do
		if fresh[bayId] ~= prompt and prompt.Parent then
			prompt.Enabled = false
		end
	end
	state.Prompts = fresh
end

------------------------------------------------------------------------------------------------------------------
-- Seats, bays, beds and going away
------------------------------------------------------------------------------------------------------------------

-- Its seat: the one it has, else the lowest free one (nil = all taken: it waits standing).
local function takeSeat(state: PlotState, p: Patient): number?
	if p.Seat then
		return p.Seat
	end
	for index in Building.SEATS do
		if state.Seats[index] == nil then
			state.Seats[index] = p
			p.Seat = index
			return index
		end
	end
	return nil
end

local function freeSeat(p: Patient)
	local seat = p.Seat
	if seat and p.Plot.Seats[seat] == p then
		p.Plot.Seats[seat] = nil
	end
	p.Seat = nil
	U.setSeated(p, false)
end

local function freeBay(p: Patient)
	local bayId = p.Bay
	if bayId and p.Plot.BayOf[bayId] == p then
		p.Plot.BayOf[bayId] = nil
	end
	p.Bay = nil
	p.OnBed = false
	p.Model:SetAttribute("Bay", "")
	p.Model:SetAttribute("Since", nil)
end

local function releaseBed(p: Patient)
	local bed = p.WardBed
	if bed and p.Plot.Beds[bed.Key] == p then
		p.Plot.Beds[bed.Key] = nil
	end
	p.WardBed = nil
end

-- Closes a patient's open game without settling it (the patient is going away, or its bay closed). The helper's own
-- items come back to their hands when `giveItemsBack` (the nurse tray's are spent: they're free and nurse-made).
local function dropSession(p: Patient, giveItemsBack: boolean)
	local id = p.Session
	if not id then
		return
	end
	local helper, carried = p.SessionHelper, p.SessionCarried
	p.Session = nil
	p.SessionHelper = nil
	p.SessionKind = nil
	p.SessionIndices = nil
	p.SessionCarried = nil
	local ok, err = pcall(Treatment.drop, id)
	if not ok then
		report("Treatment.drop", err)
	end
	if giveItemsBack and helper and carried then
		for _, itemId in carried do
			U.giveBack(helper, itemId)
		end
	end
end

-- The Porter it claimed goes back to work.
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

-- Its turn on the lift is over.
local function liftDone(p: Patient)
	if p.HasLift then
		p.HasLift = false
		p.Plot.LiftBusy = false
	end
end

local function removePatient(p: Patient)
	if p.Phase == "Gone" then
		return
	end
	dropSession(p, true)
	releasePorter(p)
	liftDone(p)
	local state = p.Plot
	freeSeat(p)
	freeBay(p)
	releaseBed(p)
	p.Phase = "Gone"
	state.All[p] = nil
	state.ById[p.Id] = nil
	if state.Active then
		refreshFront(state)
	end
	local thread = p.Thread
	p.Thread = nil
	cancel(thread)
	p.Model:Destroy()
end

------------------------------------------------------------------------------------------------------------------
-- Paying (Cure.resolve)
------------------------------------------------------------------------------------------------------------------

-- Hands the visit to Cure.resolve on its own thread, once. The helper is whoever finished it, or the owner if
-- they've left; Cure.resolve skips whichever of the two is gone.
local function payVisit(p: Patient)
	if p.Paid then
		return
	end
	p.Paid = true
	local state = p.Plot
	local owner = state.Owner
	local helper = owner
	local treatedBy = p.Helper
	if treatedBy and treatedBy.Parent == Players then
		helper = treatedBy
	end
	local data = PlayerData.get(owner)
	local comfort = if data then data.Upgrades.WardComfort or 0 else 0
	local extra = Pure.extra({
		Escorted = p.Escorted,
		Triage = p.TriageBonus,
		Team = U.teamOf(state.Plot).Cash,
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
		Items = #p.Plan, -- a longer plan pays more
		Cheer = Pure.cheer(state.Plot.Model:GetAttribute("CheerTip"), K.MAX_CHEER_TIP), -- the plot's Cheerer
		Urgent = if p.Urgent ~= "" then p.Urgent else nil, -- 🚑 x3 + 2 ⭐ · 🚁 x4 + 3 ⭐
		Extra = extra,
		Plot = state.Plot, -- Cure asks Abilities (Double Dose, Star Burst) about this plot
		Dept = p.RecoverIn, -- nurse XP specialty
		Wing = p.Wing,
		Escorted = if p.Escorted then true else nil, -- for the Cured payload (Feel/CureFX's "+20% ↕️")
	}
	-- Its own thread: a patient thread cancelled mid-visit can never cut a reward in half.
	task.spawn(function()
		local ok, err = pcall(Cure.resolve, ctx)
		if not ok then
			report("Cure.resolve", err)
		end
	end)
end

-- It pays (only while the owner is still here: the closing clinic pays its own way, Pure.closing), a happy face,
-- and a spin where it is.
local function payAndSpin(p: Patient): boolean
	setState(p, "Done")
	if alive(p) and p.Plot.Owner.Parent == Players then
		payVisit(p)
	end
	CreatureBuilder.setMood(p.Model, "Happy")
	p.Badge.Icon.Text = K.ICON_HAPPY
	p.Badge.Need.Visible = false
	CreatureBuilder.effectAt(p.Root.Position + Vector3.new(0, 1.6 * p.BaseScale, 0), "Cure")
	return hop(p, p.Pivot, 2.6, 0.6, math.pi * 2)
end

------------------------------------------------------------------------------------------------------------------
-- The lift (Server/Lift) and the floors above the ground
------------------------------------------------------------------------------------------------------------------

-- Waits for this plot's lift (one ride at a time), then holds it. False if the patient is gone meanwhile.
local function liftTurn(p: Patient): boolean
	local state = p.Plot
	while state.LiftBusy and alive(p) do
		task.wait(K.POLL)
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
	local models: { Model } = { p.Model }
	for _, model in others do
		table.insert(models, model)
	end
	local finished, carried = within(K.CARRY_SECONDS, "Lift.carry", Lift.carry, p.Plot.Plot, models, floor)
	if not alive(p) then
		return false
	end
	if not (finished and carried == true) then
		CreatureBuilder.effectAt(to.Position + Vector3.new(0, 1.5 * p.BaseScale, 0), "Pop")
	end
	p.Pivot = to
	p.Root.CFrame = to -- its resting pose on that floor, once
	p.Floor = floor
	p.Upstairs = floor > 0
	return true
end

-- A Porter's model on the plot (Nurses builds Plot.Nurses.Nurse_<NurseId>).
function U.porterModel(plot: Plot, nurseId: string): Model?
	local folder = plot.Model:FindFirstChild("Nurses")
	local model = folder and folder:FindFirstChild("Nurse_" .. nurseId)
	return if model and model:IsA("Model") then model else nil
end

-- A model stands within `studs` of `at` (a landing point): across the ground, and not a whole storey above or below.
function U.modelNear(model: Model, at: Vector3, studs: number): boolean
	if not model:IsDescendantOf(Workspace) then
		return false
	end
	local offset = model:GetPivot().Position - at
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= studs and math.abs(offset.Y) <= 6
end

-- Someone who can work this plot (Plots.canWork) stands near `at`: only then is an escort worth waiting for.
function U.workerNear(plot: Plot, at: Vector3, studs: number): boolean
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character and U.modelNear(character, at, studs) and Plots.canWork(player, plot) then
			return true
		end
	end
	return false
end

-- Up the lift to `floor` for its rest. At the ground landing it waits for a free Porter (Nurses.claimPorter; the
-- porter walks over: Nurses.escort) or, with none, a player who can work here (Lift.waitEscort: the landing's
-- EscortPrompt for Config.Lift.EscortWait s). Whoever comes rides with it (Escorted: +20% cash, rest x0.5); nobody: it
-- rides alone (an escort is a bonus, never a chore). True = it stands at that floor's landing.
local function goUp(p: Patient, floor: number): boolean
	local state = p.Plot
	local plot = state.Plot
	local ground, above = U.landingOf(plot, 0), U.landingOf(plot, floor)
	if not (ground and above) then
		return false
	end
	if not walkTo(p, K.LANDING, 0) then
		return false
	end
	if not hop(p, U.standAt(state, ground, 0), p.HopHeight, p.HopSeconds) then
		return false
	end
	-- Its escort first, then the lift: the lift is held only for the ride itself.
	local others: { Model } = {}
	local okPorter, porter = pcall(Nurses.claimPorter, plot)
	if not okPorter then
		report("Nurses.claimPorter", porter)
	elseif type(porter) == "string" then
		p.Porter = porter
		local finished, arrived = within(K.PORTER_SECONDS, "Nurses.escort", Nurses.escort, plot, porter, ground)
		if not alive(p) then
			return false
		end
		local model = if finished and arrived == true then U.porterModel(plot, porter) else nil
		if model then
			table.insert(others, model)
		else
			releasePorter(p) -- it couldn't come: the patient asks a player instead
		end
	end
	-- A player's escort is only waited for when someone who can work here stands near the ground landing.
	if #others == 0 and U.workerNear(plot, ground.Position, K.ESCORT_NEAR) then
		local seconds = math.clamp(tonumber(Config.Lift.EscortWait) or 6, 0, 30)
		local finished, rider = within(seconds + K.ESCORT_SLACK, "Lift.waitEscort", Lift.waitEscort, plot, seconds)
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
		if Players:GetPlayerFromCharacter(model) and not U.modelNear(model, ground.Position, K.ESCORT_NEAR) then
			table.remove(others, index)
		end
	end
	p.Escorted = #others > 0
	p.Model:SetAttribute("Escorted", p.Escorted)
	local rode = ride(p, floor, U.standAt(state, above, floor), others)
	liftDone(p)
	return rode
end

-- Back down: to this floor's landing, then the lift (alone) to the ground. False = there's no lift (the caller pops
-- it away where it is).
local function goDown(p: Patient): boolean
	local state = p.Plot
	local here, ground = U.landingOf(state.Plot, p.Floor), U.landingOf(state.Plot, 0)
	if not (here and ground) then
		return false
	end
	if not walkTo(p, K.LANDING, p.Floor) then
		return false
	end
	if not hop(p, U.standAt(state, here, p.Floor), p.HopHeight, p.HopSeconds) then
		return false
	end
	if not liftTurn(p) then
		return false
	end
	local rode = ride(p, 0, U.standAt(state, ground, 0), {})
	liftDone(p)
	return rode
end

-- Gone with a soft pop where it stands (no way down: the building changed under it).
local function popAway(p: Patient)
	p.Badge.Gui.Enabled = false
	p.Badge.Bubble.Enabled = false
	CreatureBuilder.effectAt(p.Root.Position + Vector3.new(0, 1.5 * p.BaseScale, 0), "Pop")
	scaleTo(p, p.BaseScale * 0.05, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	if not hop(p, p.Pivot, 0.5, 0.35) then
		return
	end
	removePatient(p)
end

------------------------------------------------------------------------------------------------------------------
-- A patient's visit (runs on the patient's own thread)
------------------------------------------------------------------------------------------------------------------

-- Off its seat (to the seat's front) and off its bay bed (to the DoctorSpot): the seat and the bay free as it stands.
-- A seat or a bay it is only on its way to stays its own.
local function getUp(p: Patient): boolean
	local state = p.Plot
	local seat = p.Seat
	if p.OnSeat and seat then
		local info = Building.SEATS[seat]
		local front = Building.seatFront(info)
		local dx, dz = Building.facing(info.Face)
		U.setSeated(p, false)
		local at = surface(state, U.worldAt(state, front.X, front.Z, 0), 0)
		if not hop(p, facing(at, worldDir(state, dx, dz)), K.SIT_HEIGHT, K.SIT_SECONDS) then
			return false
		end
		freeSeat(p)
	end
	local bayId = p.Bay
	local info = if bayId then Building.bay(bayId) else nil
	if p.OnBed and bayId then
		if info then
			local spot = Building.doctorSpot(info)
			local dx, dz = Building.facing(info.Face)
			p.OnBed = false
			local at = surface(state, U.worldAt(state, spot.X, spot.Z, 0), 0)
			if not hop(p, facing(at, worldDir(state, dx, dz)), K.SIT_HEIGHT, K.SIT_SECONDS) then
				return false
			end
		end
		freeBay(p)
		if state.Active then
			refreshFront(state)
		end
	end
	return alive(p)
end

-- Out of the front doors to PatientExit, then a pop (down the lift first if it's upstairs).
local function leave(p: Patient)
	local state = p.Plot
	p.Phase = "Leaving"
	setState(p, "Leaving")
	if not getUp(p) then
		return
	end
	freeSeat(p) -- a seat or a bay it was only on its way to
	if p.Bay then
		freeBay(p)
		refreshFront(state)
	end
	if p.Upstairs then
		if not goDown(p) then
			if alive(p) then
				popAway(p)
			end
			return
		end
	end
	local inside, outside = Building.doorPoints("Front")
	if inside and outside then
		if not walkTo(p, inside, 0) or not walkTo(p, outside, 0) then
			return
		end
	end
	local exit = U.markerGround(state.Plot.Exit)
	if not walk(p, { exit.Position }, 0) then
		return
	end
	p.Badge.Gui.Enabled = false
	p.Badge.Bubble.Enabled = false
	CreatureBuilder.effectAt(p.Root.Position + Vector3.new(0, 1.5 * p.BaseScale, 0), "Pop")
	scaleTo(p, p.BaseScale * 0.05, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	if not hop(p, exit * CFrame.new(0, 0, -2), p.HopHeight, 0.35) then
		return
	end
	removePatient(p)
end

-- Patience ran out: droop, a soft sad puff where it sits, and gone. No penalty.
local function sadLeave(p: Patient)
	setState(p, "Sad")
	p.Badge.Icon.Text = K.ICON_SAD
	p.Badge.Need.Visible = false
	pcall(CreatureBuilder.setRecipe, p.Badge, {}, {}) -- the plan's chips go with the Need chip
	p.Badge.Bubble.Enabled = false
	showRing(p, 0, K.RING_LOW)
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

-- The ward pick (Lv 3+, no Receptionist on duty): Treatment.waitTriage waits for the helper's pick (at most
-- Config.Triage.Seconds). It always goes the right way; a right pick is +10% (Pure.triageBonus).
local function triage(p: Patient)
	local ask = p.Triage
	if not ask then
		return
	end
	p.Triage = nil
	local ok, pick = pcall(Treatment.waitTriage, ask.Helper, ask.Session, ask.Options, ask.Right)
	if not ok then
		report("Treatment.waitTriage", pick)
		return
	end
	if Pure.triageBonus(pick, ask.Right) then
		p.TriageBonus = true
	end
end

-- The rest in a ward bed: eyes closed, pink sparkles, the ring fills up. Seconds from Pure.rest (escort, Ward
-- Comfort, the team). False = the patient is gone.
local function rest(p: Patient): boolean
	local state = p.Plot
	setState(p, "Recovering")
	CreatureBuilder.setMood(p.Model, "Sleep")
	p.Badge.Icon.Text = K.ICON_SLEEP
	CreatureBuilder.setEffect(p.Model, "Heal", true)
	CreatureBuilder.setEffect(p.Model, "HealLight", true)
	local data = PlayerData.get(state.Owner)
	local seconds = Pure.rest(Config.RecoverSeconds, {
		Escorted = p.Escorted,
		Comfort = if data then data.Upgrades.WardComfort or 0 else 0,
		Team = state.Team.Recover,
	}, Config)
	local started = os.clock()
	while true do
		local done = (os.clock() - started) / seconds
		showRing(p, done, K.RING_HEAL)
		if done >= 1 then
			break
		end
		if not sleep(p, K.TICK) then
			return false
		end
	end
	CreatureBuilder.setEffect(p.Model, "Heal", false)
	CreatureBuilder.setEffect(p.Model, "HealLight", false)
	return true
end

-- In: from the gate through the front doors to reception (a 🚑 patient from its stretcher through the A&E door; a 🚁
-- one from the roof down the lift). Then it is checked in.
local function arrive(p: Patient): boolean
	local state = p.Plot
	if p.Incoming then
		-- 🚁 The helicopter lands first (Feel/HospitalFX flies it in from HeliSpot's ArriveAt); then out it steps.
		if not sleep(p, K.HELI_LAND_SECONDS) then
			return false
		end
		p.Incoming = false
		p.Badge.Gui.Enabled = true
	end
	scaleTo(p, p.BaseScale, 0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out) -- pop in
	if not hop(p, p.Pivot, p.HopHeight * 1.2, 0.45) then
		return false
	end
	local inside = false -- in the building already (down the lift from the roof)
	if p.Upstairs then
		local roof, ground = U.landingOf(state.Plot, p.ArriveFloor), U.landingOf(state.Plot, 0)
		if roof and ground then
			p.Floor = p.ArriveFloor
			if not walkTo(p, K.LANDING, p.Floor) then
				return false
			end
			if not hop(p, U.standAt(state, roof, p.Floor), p.HopHeight, p.HopSeconds) or not liftTurn(p) then
				return false
			end
			inside = ride(p, 0, U.standAt(state, ground, 0), {})
			liftDone(p)
			if not alive(p) then
				return false
			end
		end
		if not inside then
			-- The lift went away under it: a pop, and in by the gate.
			local gate = U.markerGround(state.Plot.Spawn)
			CreatureBuilder.effectAt(gate.Position + Vector3.new(0, 1.5 * p.BaseScale, 0), "Pop")
			p.Pivot = gate
			p.Root.CFrame = gate
			p.Floor = 0
			p.Upstairs = false
		end
		if p.Regular == nil then
			showSymptom(p)
		end
	end
	if not inside then
		-- In through the front doors (a 🚑 patient through the A&E door by its stretcher, once that door is open).
		local door = "Front"
		if p.Urgent == "AE" and state.Level >= K.AE_LEVEL then
			local here = U.localOf(state, p.Pivot.Position)
			local _, aeOut = Building.doorPoints("AE")
			local _, frontOut = Building.doorPoints("Front")
			if aeOut and frontOut then
				local toAE = (here.X - aeOut.X) ^ 2 + (here.Z - aeOut.Z) ^ 2
				local toFront = (here.X - frontOut.X) ^ 2 + (here.Z - frontOut.Z) ^ 2
				door = if toAE < toFront then "AE" else "Front"
			end
		end
		local doorIn, doorOut = Building.doorPoints(door)
		if doorIn and doorOut then
			if not walkTo(p, doorOut, 0) or not walkTo(p, doorIn, 0) then
				return false
			end
		end
		if p.Urgent == "" then
			-- Reception: a stop in front of the desk, facing it, then off to the waiting room.
			if not walkTo(p, Building.RECEPTION.Stop, 0) then
				return false
			end
			if not hop(p, facing(p.Pivot.Position, worldDir(state, 0, 1)), p.HopHeight * 0.5, p.HopSeconds) then
				return false
			end
			if not sleep(p, K.CHECK_IN_SECONDS) then
				return false
			end
		end
	end
	p.CheckedIn = true
	p.Since = os.clock() - (if p.Urgent ~= "" then K.URGENT_HEAD else 0)
	return alive(p)
end

-- To its seat (Joshua, 2026-11-17: "when the patient first arrives, he should sit down at the chair"): a walk-in
-- sits down first, even with a bay free, and stays there until it is sent (the player's Send, or a Receptionist:
-- U.send; patience drains at the waiting room's rate meanwhile). The free bays are handed out here and now to the
-- few the tick may call by itself (U.autoCall, the longest wait first), so a 🚑 patient goes from the A&E door
-- straight to its bay and a 🚁 one from the lift to the X-ray bay, and one that was sent before and whose bay closed
-- takes another free bay without sitting again; it gets up first. No free seat: it waits standing where it is
-- (settled from then on, and it can be sent from there).
local assignBays: (state: PlotState) -> ()
local function findSeat(p: Patient): boolean
	local state = p.Plot
	if p.Phase == "Requeue" then
		if not getUp(p) then
			return false
		end
		p.Phase = "Arriving"
	end
	if p.Bay == nil and p.CheckedIn then
		assignBays(state)
	end
	if p.Bay then
		p.Phase = "ToBay"
		return true
	end
	if not p.OnSeat then
		setState(p, "Arriving")
	end
	local seat = takeSeat(state, p)
	if p.OnSeat and seat then
		seat = nil -- sitting on its seat already
	end
	if seat then
		if not walkTo(p, Building.seatFront(Building.SEATS[seat]), 0) then
			return false
		end
		if p.Phase ~= "Arriving" then
			return alive(p) -- gone home meanwhile
		end
		if p.Bay then
			p.Phase = "ToBay"
			return true
		end
		if not hop(p, U.seatPose(state, seat, p), K.SIT_HEIGHT, K.SIT_SECONDS) then
			return false
		end
		U.setSeated(p, true) -- it sits still now: no idle hops on a seat (waitSeated)
	end
	if p.Phase ~= "Arriving" then
		return alive(p)
	end
	p.Phase = "Seated"
	if p.SeatedAt == nil then
		p.SeatedAt = os.clock() -- settled: it can be sent from now (a Receptionist RECEPTION_SECONDS later)
	end
	setState(p, "Waiting")
	if p.Regular and not p.Examined then
		showSymptom(p) -- it said hello on the way in; now its symptom
	end
	refreshFront(state)
	return alive(p)
end

-- In the waiting room until a bay is its, or it goes. On a seat it sits still (it may sit a long while: no hops, no
-- drift; the client breathes and acts its ailment); one standing (every seat taken) hops a little now and then.
local function waitSeated(p: Patient): boolean
	while alive(p) and p.Phase == "Seated" do
		if p.Bay then
			p.Phase = "ToBay"
			break
		end
		local now = os.clock()
		if now >= p.NextIdle and not p.OnSeat then
			local low = p.Patience / p.PatienceMax < 0.3 -- impatient: bouncier
			p.NextIdle = now + (if low then rng:NextNumber(0.8, 1.4) else rng:NextNumber(2.5, 4.5))
			if not hop(p, p.Pivot, if low then 0.35 else 0.5, 0.3) then
				return false
			end
		elseif not sleep(p, 0.1) then
			return false
		end
	end
	return alive(p)
end

-- To its bay: up, along the corridors to the DoctorSpot, onto the bed.
local function goToBay(p: Patient): boolean
	local state = p.Plot
	local bayId = p.Bay
	local info = if bayId then Building.bay(bayId) else nil
	if not (bayId and info) then
		freeBay(p)
		p.Phase = "Arriving"
		return alive(p)
	end
	p.Model:SetAttribute("Bay", bayId)
	setState(p, "ToBay")
	if not getUp(p) then
		return false
	end
	freeSeat(p) -- (a seat it was still walking to)
	state.NextSpawn = math.max(state.NextSpawn, os.clock() + K.REFILL_SECONDS)
	refreshFront(state)
	if not walkTo(p, Building.doctorSpot(info), 0) then
		return false
	end
	if p.Phase ~= "ToBay" then
		return alive(p) -- sent home meanwhile
	end
	if p.Bay ~= bayId or state.BayOf[bayId] ~= p or not bayUsable(state, bayId) then
		freeBay(p) -- its bay went: back to a seat
		p.Phase = "Arriving"
		return alive(p)
	end
	if not hop(p, U.bayPose(state, info), K.SIT_HEIGHT, K.SIT_SECONDS) then
		return false
	end
	p.OnBed = true
	p.BaySince = os.clock()
	-- On the bed at last: the wait in the waiting room is forgotten (Config.Visit.BayRefill of its patience back).
	p.Patience = Pure.refill(p.Patience, p.PatienceMax, K.BAY_REFILL, 1)
	local fraction = p.Patience / p.PatienceMax
	showRing(p, fraction, ringColor(fraction))
	showPatience(p, fraction)
	p.Model:SetAttribute("Since", Workspace:GetServerTimeNow()) -- the clients' copy of the front order (UI/Guide)
	p.Phase = "Bay"
	setState(p, bayState(p))
	refreshFront(state)
	U.tutorialHook("onFrontArrived", state.Owner)
	return alive(p)
end

-- On the bay bed (a little hop now and then, still while a game plays) until its plan is done or it goes.
local function waitAtBay(p: Patient): boolean
	while alive(p) and p.Phase == "Bay" do
		local now = os.clock()
		if now >= p.NextIdle and not p.Session then
			local low = p.Patience / p.PatienceMax < 0.3
			p.NextIdle = now + (if low then rng:NextNumber(0.8, 1.4) else rng:NextNumber(3, 5))
			if not hop(p, p.Pivot, if low then 0.35 else 0.4, 0.3) then
				return false
			end
		elseif not sleep(p, 0.1) then
			return false
		end
	end
	return alive(p)
end

-- A rest in a bought room's own bed (the Winter Wing's, for a chills patient no ward takes): up from the bay, over to
-- the bed's foot, a nap (the same rest as a ward bed's, no lift and no escort), then it pays and goes home. A bed that
-- went away meanwhile (the room was lost): it pays where it stands.
local function restInRoom(p: Patient, reserved: WardBed)
	local state = p.Plot
	setState(p, "ToWard")
	if not getUp(p) then -- the bay frees as it stands
		return
	end
	local roomId = reserved.Room or ""
	local bed = state.Layout.RoomBeds[roomId] or reserved -- (a rebuilt room has a new bed part in the same place)
	if bed.Part.Parent and state.Rooms[roomId] == true then
		local at = U.localOf(state, bed.Part.Position)
		local foot: Point = { X = at.X, Z = at.Z - bed.Part.Size.Z / 2 - K.ROOM_BED_FOOT }
		if not walkTo(p, foot, 0) then
			return
		end
		bed = state.Layout.RoomBeds[roomId] or bed
		if bed.Part.Parent then
			if not hop(p, U.roomBedPose(state, bed, true, p.BaseScale), 1.8, 0.5) then -- flop into bed
				return
			end
			p.InBed = true
		end
		if not rest(p) then
			return
		end
		if p.InBed and bed.Part.Parent then
			if not hop(p, U.roomBedPose(state, bed, false, p.BaseScale), 1.2, 0.4) then -- sit up
				return
			end
		end
		if not payAndSpin(p) then
			return
		end
		if p.InBed then
			p.InBed = false
			local stand = surface(state, U.worldAt(state, foot.X, foot.Z, 0), 0)
			if not hop(p, facing(stand, worldDir(state, 0, -1)), 1.8, 0.45) then
				return
			end
		end
		releaseBed(p)
		leave(p)
		return
	end
	releaseBed(p)
	p.SpotKind = "Home"
	if not payAndSpin(p) then
		return
	end
	leave(p)
end

-- The plan is complete: a happy bounce, then home (it pays on the bed) or a ward bed first (or its room's own bed).
local function afterPlan(p: Patient)
	local state = p.Plot
	if not hop(p, p.Pivot, p.HopHeight * 0.9, 0.3) then -- a happy little bounce
		return
	end
	local bed = p.WardBed
	if bed and bed.Room then
		restInRoom(p, bed)
		return
	end
	if bed then
		setState(p, "ToWard")
		if not getUp(p) then -- the bay frees as it stands
			return
		end
		triage(p)
		if not alive(p) then
			return
		end
		local up = goUp(p, bed.Floor)
		if not alive(p) then
			return
		end
		if up then
			setState(p, "ToWard")
			local foot: Point = { X = bed.X, Z = Building.BED_FOOT_Z }
			local porter = p.Porter
			if porter then
				-- Its Porter walks to the bed with it, then goes back to work.
				local target = CFrame.new(U.worldAt(state, foot.X, foot.Z, bed.Floor))
				task.spawn(function()
					within(K.PORTER_SECONDS, "Nurses.escort", Nurses.escort, state.Plot, porter, target)
					if p.Porter == porter then
						releasePorter(p)
					end
				end)
			end
			if not walkTo(p, foot, bed.Floor) then
				return
			end
			bed = state.Layout.Beds[bed.Key] or bed -- (a rebuilt Building has new bed parts in the same places)
			if bed.Part.Parent then
				if not hop(p, U.wardPose(state, bed, true, p.BaseScale), 1.8, 0.5) then -- flop into bed
					return
				end
				p.InBed = true
			end
			if not rest(p) then
				return
			end
			if p.InBed then
				if not hop(p, U.wardPose(state, bed, false, p.BaseScale), 1.2, 0.4) then -- sit up
					return
				end
			end
			if not payAndSpin(p) then
				return
			end
			if p.InBed then
				p.InBed = false
				local at = surface(state, U.worldAt(state, foot.X, foot.Z, bed.Floor), bed.Floor)
				if not hop(p, facing(at, worldDir(state, 0, 1)), 1.8, 0.45) then
					return
				end
			end
			releaseBed(p)
			leave(p)
			return
		end
		-- No way up after all (the building changed): home now.
		releaseBed(p)
		p.SpotKind = "Home"
	end
	if not payAndSpin(p) then
		return
	end
	leave(p)
end

-- An ability finished the whole visit (💫 Miracle): it pays on the spot, a happy spin, and off it goes.
local function finishedOnSpot(p: Patient)
	CreatureBuilder.effectAt(p.Root.Position + Vector3.new(0, 1.6 * p.BaseScale, 0), "Cure")
	if not payAndSpin(p) then
		return
	end
	leave(p)
end

local function visit(p: Patient)
	if not arrive(p) then
		return
	end
	while alive(p) do
		local phase = p.Phase
		local ok: boolean
		if phase == "Arriving" or phase == "Requeue" then
			ok = findSeat(p)
		elseif phase == "Seated" then
			ok = waitSeated(p)
		elseif phase == "ToBay" then
			ok = goToBay(p)
		elseif phase == "Bay" then
			ok = waitAtBay(p)
		elseif phase == "Done" then
			afterPlan(p)
			return
		elseif phase == "OnSpot" then
			finishedOnSpot(p)
			return
		elseif phase == "Sad" then
			sadLeave(p)
			return
		else -- "GoHome" (no seat after a rebuild), or anything else: home, never sad
			leave(p)
			return
		end
		if not ok then
			return
		end
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
-- The exam, the plan and the steps (the bay's prompt, the nurses, the C6 API)
------------------------------------------------------------------------------------------------------------------

-- The plan is complete. Where it goes after (Logic/Visit.stayWard and a free ward bed, Pure.destination), reserved
-- now so two patients never take one bed; then the ward pick (Pure.triageMode): a Receptionist sends it at once with
-- the bonus, so does Simple mode for a player who finished it (`byPlayer`), or the helper whose game (`session`)
-- finished it picks (Treatment.waitTriage; the TriageAsk goes back to Treatment for the client's buttons). A plan a
-- handed-over medicine finishes comes here from its handover session (treatAt), so it asks too; with no session (a
-- nurse, the C6 give, a handover that couldn't open one) it goes by itself. Never yields; the patient's own thread
-- does the rest (afterPlan).
local function finishPlan(
	state: PlotState,
	p: Patient,
	helper: Player,
	session: number?,
	byPlayer: boolean
): Treatment.TriageAsk?
	p.Helper = helper
	p.PatienceLeft = math.clamp(p.Patience / p.PatienceMax, 0, 1)
	p.Phase = "Done"
	p.Ward = Visit.stayWard(p.Case, state.Level)
	p.Model:SetAttribute("Dept", p.Ward or "")
	local ask: Treatment.TriageAsk? = nil
	p.SpotKind = "Home"
	if p.Ward then
		local free = U.freeBeds(state)
		local kind = Pure.destination(p.Ward, { Wards = free.Wards ~= nil, Rest = free.Rest ~= nil })
		local bed = free[kind]
		if bed then
			state.Beds[bed.Key] = p
			p.WardBed = bed
			p.SpotKind = kind
		end
		local options = Hospital.triageOptions(state.Level, LevelsData)
		local okSimple, simple = pcall(Treatment.simple, helper)
		local mode = Pure.triageMode(
			options,
			state.Receptionist.Triage,
			byPlayer,
			Pure.routed(p.Ward, p.SpotKind),
			okSimple and simple == true
		)
		if mode == "Instant" then
			p.TriageBonus = true -- a Receptionist sent it the right way
		elseif mode == "Ask" and options and session then
			p.Triage = { Helper = helper, Session = session, Options = options, Right = p.Ward :: string }
			ask = { Options = table.clone(options), Right = p.Ward :: string }
		end
	end
	if p.WardBed == nil then
		-- No ward takes it (below its ward's level, not a Stay case, or every ward bed taken): a patient of a bought
		-- room's own case rests in that room's bed when it is free (a chills patient in the Winter Wing's bed).
		local roomBed = U.freeRoomBed(state, p.Case.Room)
		if roomBed then
			state.Beds[roomBed.Key] = p
			p.WardBed = roomBed
			p.SpotKind = "Room"
		end
	end
	p.RecoverIn = if p.SpotKind == "Wards" or p.SpotKind == "Rest"
		then p.SpotKind
		elseif p.Case.Room == "BathRoom" then "Hydro"
		else "Reception"
	-- Instant feedback; the patient's own thread gets up after its current hop (and pays first when it goes home).
	setState(p, if p.WardBed then "ToWard" else "Done")
	p.Badge.Icon.Text = K.ICON_TREATED
	p.Badge.Need.Visible = false
	p.Badge.Bubble.Enabled = false
	showRing(p, 0, K.RING_HEAL)
	CreatureBuilder.setMood(p.Model, "Happy")
	refreshFront(state)
	U.tutorialHook("onTreated", state.Owner)
	return ask
end

-- Plan steps were given (a game settled, a medicine handed over, a nurse delivered): tick them off and refill some
-- patience, then finishPlan when the plan is complete. Never yields. True = complete (and the ward pick to ask, when
-- the helper's game `session` finished it). `byPlayer`: a player gave them (default: when it was a game).
local function giveItems(
	state: PlotState,
	p: Patient,
	indices: { number },
	helper: Player,
	session: number?,
	byPlayer: boolean?
): (boolean, Treatment.TriageAsk?)
	if #indices == 0 then
		return false, nil
	end
	p.Done = Recipe.apply(p.Done, indices)
	p.Patience = Pure.refill(p.Patience, p.PatienceMax, K.ITEM_PATIENCE, #indices)
	showPlan(p)
	if Recipe.complete(p.Plan, p.Done) then
		local player = if byPlayer == nil then session ~= nil else byPlayer
		return true, finishPlan(state, p, helper, session, player)
	end
	local fraction = p.Patience / p.PatienceMax
	showRing(p, fraction, ringColor(fraction))
	p.NextIdle = 0 -- a happy little hop straight away (its own thread does it)
	setState(p, bayState(p))
	refreshFront(state)
	return false, nil
end

-- The exam: the case is revealed (Case, Plan, PlanDone, the badge's plan and icon; the bubble goes), a little
-- patience back, the ward chip from Lv 3, and Tutorial.onExamined. Idempotent. `helper` = the player who examined
-- (nil: a nurse).
local function examineNow(p: Patient, helper: Player?): string
	if p.Examined then
		return p.CaseId
	end
	local state = p.Plot
	p.Examined = true
	p.Icon = if type(p.Case.Icon) == "string" then p.Case.Icon else K.ICON_UNKNOWN
	p.Badge.Icon.Text = p.Icon
	p.Badge.Bubble.Enabled = false
	p.Model:SetAttribute("Case", p.CaseId)
	p.Patience = Pure.refill(p.Patience, p.PatienceMax, K.ITEM_PATIENCE, 1)
	local fraction = p.Patience / p.PatienceMax
	showRing(p, fraction, ringColor(fraction))
	showPatience(p, fraction)
	showPlan(p)
	local ward = Visit.stayWard(p.Case, state.Level)
	p.Model:SetAttribute("Dept", ward or "")
	local okChip, chipErr = pcall(
		CreatureBuilder.setDept,
		p.Badge,
		if ward and Hospital.triageOptions(state.Level, LevelsData) then ward else nil
	)
	if not okChip then
		report("CreatureBuilder.setDept", chipErr)
	end
	if p.Phase == "Bay" and not p.Session then
		setState(p, bayState(p))
	end
	refreshFront(state)
	U.tutorialHook("onExamined", state.Owner, helper) -- by anyone, a nurse included (`helper` nil)
	return p.CaseId
end

-- One more exam for this player's glow (Stats.Exams), counted only while it still matters: once the glow is over
-- the save isn't written again.
local function countExam(player: Player)
	local limit = tonumber(Config.Visit and Config.Visit.ExamsGlow) or Visit.EXAMS_GLOW
	if Pure.examsDone(PlayerData.get(player)) >= limit then
		return
	end
	local ok, err = pcall(PlayerData.update, player, function(d: Types.Data)
		d.Stats[Pure.EXAMS_STAT] = Pure.examsDone(d) + 1
	end)
	if not ok then
		report("PlayerData.update (Exams)", err)
	end
end

-- Treatment settled the exam game on `p` (the player's report, the timeout, or the helper leaving): whatever the
-- ratings, the case is revealed.
local function settleExam(p: Patient, sessionId: number, tip: number): (boolean, Treatment.TriageAsk?)
	if p.Session ~= sessionId then
		return false, nil -- dropped already
	end
	local helper = p.SessionHelper
	p.Session = nil
	p.SessionHelper = nil
	p.SessionKind = nil
	p.SessionIndices = nil
	p.SessionCarried = nil
	if not alive(p) or p.Phase ~= "Bay" then
		return false, nil
	end
	p.TipPaid += math.max(0, tip)
	if helper then
		countExam(helper)
	end
	examineNow(p, helper)
	return false, nil
end

-- Treatment settled a supply game on `p`.
local function settleTreat(p: Patient, sessionId: number, tip: number): (boolean, Treatment.TriageAsk?)
	if p.Session ~= sessionId then
		return false, nil -- dropped already (the patient went away)
	end
	local helper = p.SessionHelper
	local indices = p.SessionIndices or {}
	p.Session = nil
	p.SessionHelper = nil
	p.SessionKind = nil
	p.SessionIndices = nil
	p.SessionCarried = nil
	if not alive(p) or p.Phase ~= "Bay" then
		return false, nil
	end
	p.TipPaid += math.max(0, tip)
	local state = p.Plot
	return giveItems(state, p, indices, helper or state.Owner, sessionId)
end

-- Above the patient (where the client's rating pops and coins go).
local function above(p: Patient): Vector3
	return p.Root.Position + Vector3.new(0, 3 * p.BaseScale, 0)
end

-- "Examine": the exam card (Pure.examCard) as an Exam session.
local function examAt(state: PlotState, p: Patient, player: Player)
	local data = PlayerData.get(player)
	local okSimple, simple = pcall(Treatment.simple, player)
	-- The glow: the player's own first exams (Stats.Exams), Simple mode, and all through their tutorial (a Replay too).
	local teaching = U.tutorialAsk("active", false, player) == true
	local tools, glow = Pure.examCard(
		p.Case,
		state.Level,
		Pure.examsDone(data),
		teaching or (okSimple and simple == true),
		rng:NextNumber(),
		Config
	)
	local sessionId: number? = nil
	local spec: Treatment.Spec = {
		Plot = state.Plot,
		PatientId = p.PatientId,
		Key = p.Id, -- one session per patient (Review Focus 3)
		Kind = "Exam",
		Items = {},
		Tools = tools,
		Answer = p.Case.Tool,
		Glow = glow,
		Case = p.CaseId,
		Symptom = p.Symptom,
		Plan = p.Plan,
		Position = above(p),
		Counter = U.spotWorld(state, p.Bay or ""), -- a report from farther than Config.Treat.Distance is all OK
		TipSoFar = p.TipPaid,
		Settle = function(_ratings: { Types.Rating }, tip: number): (boolean, Treatment.TriageAsk?)
			local id = sessionId
			if id == nil then
				return false, nil
			end
			return settleExam(p, id, tip)
		end,
	}
	local ok, opened = pcall(Treatment.open, player, spec)
	if not ok or type(opened) ~= "number" then
		if not ok then
			report("Treatment.open (Exam)", opened)
		end
		return
	end
	sessionId = opened
	p.Session = opened
	p.SessionHelper = player
	p.SessionKind = "Exam"
	p.SessionIndices = nil
	p.SessionCarried = nil
	setState(p, "Examining")
	refreshFront(state)
end

-- Nothing in hand (or in the nurse tray) fits: a head-shake, and what the next missing step is.
local function refuse(p: Patient, player: Player, emptyHanded: boolean)
	CreatureBuilder.shake(p.Model) -- drawn on the clients
	local item = rawget(Items :: any, p.Item)
	local icon = if type(item) == "table" then item.Icon else K.ICON_UNKNOWN
	local hint: string
	if not emptyHanded then
		hint = "Oops! This one needs " .. icon
	elseif type(item) == "table" and item.Kind == "Medicine" then
		hint = "Get " .. icon .. " at the 💊 dispensary!"
	else
		hint = "Get " .. icon .. " first!"
	end
	Remotes.toast(player, hint)
end

-- Whether completing `p`'s plan now would ask `helper` for its ward (the same rule finishPlan applies: a patient who
-- stays, two wards open, no Receptionist, a free bed in its own ward, not Simple mode).
local function asksWard(state: PlotState, p: Patient, helper: Player): boolean
	local ward = Visit.stayWard(p.Case, state.Level)
	if not ward then
		return false
	end
	local free = U.freeBeds(state)
	local kind = Pure.destination(ward, { Wards = free.Wards ~= nil, Rest = free.Rest ~= nil })
	local okSimple, simple = pcall(Treatment.simple, helper)
	return Pure.triageMode(
		Hospital.triageOptions(state.Level, LevelsData),
		state.Receptionist.Triage,
		true,
		Pure.routed(ward, kind),
		okSimple and simple == true
	) == "Ask"
end

-- "Treat": the plan steps the helper carries, then the nurse tray's, are taken. Medicines are handed over at once
-- (no game); supplies open one Treat session (one game each). Medicines that complete the plan of a patient whose
-- ward the helper picks go through a handover session: no game either, it only carries "Injury Ward or Rest Ward?"
-- to the player (Treatment, spec.Handover), so a fever asks as a broken leg does.
local function treatAt(state: PlotState, p: Patient, player: Player)
	local plot = state.Plot
	local carried = U.carrying(player)
	local fromCarry, fromTray = Pure.plan(p.Plan, p.Done, carried, trayItems(plot))
	if #fromCarry + #fromTray == 0 then
		refuse(p, player, #carried == 0)
		return
	end
	-- Take them: they're spent now (the games can't fail). Nothing yields between the check and the take.
	p.Claimed = true
	local takenCarry: { number } = {}
	local takenTray: { number } = {}
	local tookAll = true
	for _, index in fromCarry do
		if U.takeItem(player, p.Plan[index]) then
			table.insert(takenCarry, index)
		else
			tookAll = false
			break
		end
	end
	if tookAll then
		for _, index in fromTray do
			if takeFromTray(plot, p.Plan[index]) then
				table.insert(takenTray, index)
			else
				tookAll = false
				break
			end
		end
	end
	p.Claimed = false
	if not tookAll or not (alive(p) and needsDoctor(p) and p.Bay and state.BayOf[p.Bay] == p) then
		for _, index in takenCarry do
			U.giveBack(player, p.Plan[index]) -- the patient moved on while we checked
		end
		return
	end
	local given: { number } = table.clone(takenCarry)
	for _, index in takenTray do
		table.insert(given, index)
	end
	local medicines, supplies = Pure.split(p.Plan, given)
	-- Medicines only, and they complete the plan of a patient whose ward is this player's to pick: a handover
	-- session (no game) carries the pick. Otherwise they are simply handed over.
	local handover = #supplies == 0
		and Recipe.complete(p.Plan, Recipe.apply(p.Done, medicines))
		and asksWard(state, p, player)
	if #supplies == 0 and not handover then
		giveItems(state, p, medicines, player, nil, true) -- handed over: no game
		return
	end
	if #medicines > 0 and not handover then
		giveItems(state, p, medicines, player, nil, true) -- (the supplies are still missing: never complete here)
	end
	local inSession = if handover then medicines else supplies
	local fromHands: { string } = {}
	for _, index in inSession do
		if table.find(takenCarry, index) then
			table.insert(fromHands, p.Plan[index])
		end
	end
	local sessionId: number? = nil
	local spec: Treatment.Spec = {
		Plot = plot,
		PatientId = p.PatientId,
		Key = p.Id,
		Kind = "Treat",
		Items = if handover then {} else Pure.itemsAt(p.Plan, supplies),
		Handover = handover,
		Case = p.CaseId,
		Position = above(p),
		Counter = U.spotWorld(state, p.Bay or ""),
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
			report("Treatment.open (Treat)", opened)
		end
		if handover then
			giveItems(state, p, medicines, player, nil, true) -- no session to ask from: it goes by itself
			return
		end
		for _, itemId in fromHands do
			U.giveBack(player, itemId)
		end
		return
	end
	sessionId = opened
	p.Session = opened
	p.SessionHelper = player
	p.SessionKind = "Treat"
	p.SessionIndices = inSession
	p.SessionCarried = fromHands
	setState(p, "Treating")
	refreshFront(state)
end

-- The player is within reach of that bay's DoctorSpot.
local function nearBay(player: Player, state: PlotState, bayId: string): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	return (root.Position - U.spotWorld(state, bayId)).Magnitude <= K.PROMPT_DISTANCE + K.DISTANCE_SLACK
end

onBayPrompt = function(plot: Plot, bayId: string, player: Player)
	local state = active[plot]
	if not state or not state.Active then
		return
	end
	local now = os.clock()
	if now - (lastTreat[player] or 0) < K.TREAT_COOLDOWN then
		return
	end
	lastTreat[player] = now
	if not Plots.canWork(player, plot) then
		Remotes.toast(player, "🔒 Ask the owner to open up!")
		return
	end
	local p = state.BayOf[bayId]
	if not p or not needsDoctor(p) or not nearBay(player, state, bayId) then
		return
	end
	if Treatment.busy(player) then
		return -- one game at a time
	end
	if p.Examined then
		treatAt(state, p, player)
	else
		examAt(state, p, player)
	end
end

-- 💫 The whole visit done on the spot (Abilities): examined, every step given, the owner (or `helper`) as helper.
local function finishOnSpot(state: PlotState, p: Patient, helper: Player?): boolean
	if p.Phase ~= "Bay" or p.Session or p.Claimed then
		return false
	end
	if not p.Examined then
		examineNow(p, nil)
	end
	p.Done = table.create(#p.Plan, true)
	p.Helper = if helper and helper.Parent == Players then helper else state.Owner
	p.PatienceLeft = math.clamp(p.Patience / p.PatienceMax, 0, 1)
	p.RecoverIn = if p.Case.Room == "BathRoom" then "Hydro" else "Reception"
	p.Phase = "OnSpot"
	showPlan(p)
	p.Badge.Bubble.Enabled = false
	refreshFront(state)
	return true
end

-- A nurse is ready (Nurses.Heal via Treatment.onHeal): a Healer (target "Front") serves the front patient (and the
-- next with 👯 Twin Counters), a Medic (target "Urgent") a 🚑/🚁 bay patient. It examines one who needs it (no game,
-- no tip), or hands over what the nurse tray holds for it, rated OK, with no tip and no combo change. The owner is the
-- helper, so the visit is theirs; nobody is asked the ward (a Receptionist still sends it with the bonus). Returns what
-- it handed over, or { the exam tool } for an exam ({} = nothing to do: Treatment then doesn't tell Nurses.healed).
local function healFront(plotArg: any, _nurseId: string, target: string?): { string }
	local plot: Plot? = if typeof(plotArg) == "Instance" then Plots.fromInstance(plotArg) else plotArg
	if not plot then
		return {}
	end
	local state = active[plot]
	if not state or not state.Active or state.Owner.Parent ~= Players then
		return {}
	end
	local order = frontList(state)
	local candidates: { Patient } = {}
	if target == "Urgent" then
		for _, p in order do
			if p.Urgent ~= "" then
				table.insert(candidates, p)
			end
		end
	else
		for index = 1, math.min(if state.Effects.TwinCounters then 2 else 1, #order) do
			table.insert(candidates, order[index])
		end
	end
	local tray = trayItems(plot)
	for _, p in candidates do
		if not p.Examined then
			examineNow(p, nil)
			return { p.Case.Tool }
		end
		local indices = Recipe.match(p.Plan, p.Done, tray)
		if #indices > 0 then
			local items: { string } = {}
			for _, index in indices do
				local itemId = p.Plan[index]
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

------------------------------------------------------------------------------------------------------------------
-- Who comes next
------------------------------------------------------------------------------------------------------------------

-- Sparkly, Frosty in winter and 🌟 Golden at an R3+ clinic (Pure.variant). The Studio test switch
-- workspace:SetAttribute("ForceGoldenPatient", true) makes every new patient at an R3+ clinic Golden; a live server
-- ignores it.
function U.rollVariant(state: PlotState): string?
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
function U.nightOpen(state: PlotState): boolean
	if Workspace:GetAttribute("IsNight") == true then
		return true
	end
	return state.Effects.NightOwl and Hospital.nightOwl(nightEndedAt, os.clock(), Config)
end

function U.patienceFor(owner: Player, guest: boolean): number
	local data = PlayerData.get(owner)
	local chairs = if data then data.Upgrades.Chairs or 0 else 0
	local ok, seconds = pcall(Prices.patience, chairs, Config)
	local base = if ok and type(seconds) == "number" and seconds > 0 then seconds else Config.PatienceSeconds
	local boostOk, boost = pcall(Boosts.multiplier, owner, "Patience")
	if boostOk and type(boost) == "number" and boost >= 1 and boost < math.huge then
		base *= boost
	end
	return base * (if guest then K.GUEST_PATIENCE else 1)
end

-- How many plan steps this owner's patients have: their hospital level's cap, and 1 all through the tutorial.
function U.recipeCapFor(owner: Player): number
	if U.tutorialAsk("active", false, owner) then
		return 1
	end
	return U.levelAsk("recipeCap", owner, 1)
end

-- May a patient of this species come here by this way (its wing open, night, its wing's room)? Its case is a separate
-- question (Pure.pickCase).
function U.speciesOpen(state: PlotState, entry: any, byAir: boolean, night: boolean): boolean
	if type(entry) ~= "table" then
		return false
	end
	if not Pure.wingOpen(rawget(WingsData :: any, entry.Wing), state.Rebirths, byAir) then
		return false
	end
	if entry.Night and not night and not byAir then
		return false
	end
	return Pure.wingRoom(entry.Wing, state.Rooms)
end

-- In the waiting room (walking in, sitting, or getting back to a seat).
function U.waitingCount(state: PlotState): number
	local count = 0
	for p in state.All do
		if p.Phase == "Arriving" or p.Phase == "Seated" or p.Phase == "Requeue" then
			count += 1
		end
	end
	return count
end

-- Every patient whose plan isn't done yet (the tutorial's one-at-a-time).
function U.activeCount(state: PlotState): number
	local count = 0
	for p in state.All do
		local phase = p.Phase
		if phase == "Arriving" or phase == "Seated" or phase == "Requeue" or phase == "ToBay" or phase == "Bay" then
			count += 1
		end
	end
	return count
end

-- True when the patient came. `urgent`: a 🚑/🚁 patient, with its own plan and arrival spot.
local function spawnPatient(
	state: PlotState,
	patientId: string,
	regular: string?,
	visitor: boolean,
	variant: string?,
	cap: number,
	caseId: string,
	urgent: UrgentSpawn?
): boolean
	local entry: any = rawget(PatientsData :: any, patientId)
	local regularEntry: any = if regular then rawget(RegularsData :: any, regular) else nil
	local case: any = rawget(Cases :: any, caseId)
	if type(case) ~= "table" or (entry == nil and regularEntry == nil) then
		return false
	end
	local plan = if urgent then table.clone(urgent.Plan) else Visit.plan(case, cap)
	if #plan == 0 then
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
	local patience = U.patienceFor(state.Owner, regular ~= nil or visitor)
	local urgentKind = if urgent then urgent.Kind else ""
	if urgent then
		local data = PlayerData.get(state.Owner)
		patience = Pure.urgentPatience(patience, urgentKind, if data then data.Upgrades.AESpeed or 0 else 0, Config)
	end
	local wing = if regularEntry then regularEntry.Wing elseif entry then entry.Wing else "Starter"
	local air = urgent ~= nil and urgent.Air
	local rhythm = rng:NextNumber(0.9, 1.12) -- every creature hops to its own beat
	local start = if urgent then urgent.Start else U.markerGround(state.Plot.Spawn)
	local symptom = if type(case.Bubble) == "string" then case.Bubble else ""
	local emote = Pure.bubbleParts(symptom)
	lastVisitId += 1
	local p: Patient = {
		Id = lastVisitId,
		Plot = state,
		PatientId = patientId,
		Regular = regular,
		Visitor = visitor,
		Variant = variant,
		Night = night,
		Wing = if type(wing) == "string" then wing else "Starter",
		CaseId = caseId,
		Case = case,
		Symptom = symptom,
		Icon = if emote ~= "" then emote else K.ICON_UNKNOWN,
		Examined = false,
		Plan = plan,
		Done = Recipe.newDone(plan),
		Item = "",
		Station = "",
		TipPaid = 0,
		Session = nil,
		SessionHelper = nil,
		SessionKind = nil,
		SessionIndices = nil,
		SessionCarried = nil,
		Model = model,
		Root = root,
		Badge = badge,
		BaseScale = model:GetScale(),
		HopHeight = K.HOP_HEIGHT * (if night then 1.35 else 1), -- night patients float a little
		HopSeconds = K.HOP_SECONDS * rhythm * (if night then 1.15 else 1),
		Phase = "Arriving",
		CheckedIn = false,
		Since = math.huge,
		SeatedAt = nil,
		BaySince = math.huge,
		Sent = false,
		Send = nil,
		Seat = nil,
		OnSeat = false,
		Bay = nil,
		OnBed = false,
		QueueIndex = 0,
		Claimed = false,
		Patience = patience,
		PatienceMax = patience,
		PatienceLeft = 1,
		PatienceShown = 1,
		RingStep = -1,
		RingColor = nil,
		NextIdle = 0,
		Helper = nil,
		Paid = false,
		Pivot = start,
		ScaleAnim = nil,
		Thread = nil,
		Urgent = urgentKind,
		Incoming = air,
		ArriveFloor = if urgent then urgent.Floor else 0,
		Ward = nil,
		WardBed = nil,
		SpotKind = "Home",
		Floor = if air and urgent and urgent.Floor > 0 then urgent.Floor else 0,
		Upstairs = air and urgent ~= nil and urgent.Floor > 0,
		InBed = false,
		Escorted = false,
		Porter = nil,
		HasLift = false,
		Triage = nil,
		TriageBonus = false,
		RecoverIn = "Reception",
	}

	CreatureBuilder.setMood(model, "Sick")
	showRing(p, 1, K.RING_CALM)
	badge.Icon.Text = p.Icon
	badge.Star.Visible = visitor
	local okBadge, badgeErr = pcall(function()
		CreatureBuilder.setRecipe(badge, {}, {}) -- the plan shows after the exam
		CreatureBuilder.setUrgent(badge, urgentKind)
		CreatureBuilder.setDept(badge, nil)
		if variant == "Golden" then
			CreatureBuilder.setEffect(model, "Golden", true)
		end
	end)
	if not okBadge then
		report("the badge", badgeErr)
	end
	local told = false
	if regular then
		local okBeat, beat = pcall(Story.bubble, state.Owner, regular)
		if okBeat and type(beat) == "table" and type(beat.Emote) == "string" then
			showBubble(p, beat.Emote, if type(beat.Bubble) == "string" then beat.Bubble else "")
			told = true
		elseif not okBeat then
			report("Story.bubble", beat)
		end
	end
	if not told then
		showSymptom(p)
	end

	model.Name = "Patient_" .. patientId
	model:SetAttribute("Kind", if regular then "Regular" elseif visitor then "Visitor" else "Patient")
	model:SetAttribute("Regular", regular) -- Story looks for its regular on the plot by this (or PatientId)
	model:SetAttribute("VisitId", p.Id)
	model:SetAttribute("Variant", variant)
	model:SetAttribute("Night", night)
	model:SetAttribute("State", "Arriving")
	model:SetAttribute("PatienceFraction", 1)
	model:SetAttribute("Urgent", urgentKind) -- "" | "AE" | "VIP"
	model:SetAttribute("Dept", "") -- the ward it will rest in, once examined
	model:SetAttribute("Escorted", false)
	model:SetAttribute("Symptom", symptom)
	model:SetAttribute("Acting", caseId) -- what the creature acts out (the case itself is revealed by Case)
	model:SetAttribute("Tool", case.Tool)
	model:SetAttribute("Case", "")
	model:SetAttribute("Plan", "")
	model:SetAttribute("PlanDone", "")
	model:SetAttribute("Item", "")
	model:SetAttribute("Station", "")
	model:SetAttribute("Bay", "")
	model:SetAttribute("QueueIndex", 0)
	if urgentKind == "" then
		p.Send = U.sendPrompt(state, p) -- a walk-in is sent by hand; a 🚑/🚁 patient goes straight to a bay
	end
	-- PivotTo, not root.CFrame: the model isn't in Workspace yet, so its welds aren't live and the body would stay
	-- behind at the origin (each weld then locks in that gap when the model is parented in).
	model:PivotTo(start)
	model:ScaleTo(p.BaseScale * 0.15) -- pops in from tiny
	if air then
		badge.Gui.Enabled = false -- shown when it steps out of the helicopter (arrive)
		badge.Bubble.Enabled = false
	end
	model.Parent = state.Plot.Model:FindFirstChild("Patients") or state.Plot.Model

	state.All[p] = true
	state.ById[p.Id] = p
	state.Spawned += 1
	state.LastPatient = patientId
	local thread = coroutine.create(run)
	p.Thread = thread
	task.spawn(thread, p)
	return true
end

function U.hasGuest(state: PlotState, regular: string?, visitor: boolean): boolean
	for p in state.All do
		if (regular ~= nil and p.Regular == regular) or (visitor and p.Visitor) then
			return true
		end
	end
	return false
end

-- The tutorial's patient: a Starter-wing day species, a new Book page first. nil = there's none.
function U.tutorialSpecies(data: Types.Data): string?
	local fresh: { string }, seen: { string } = {}, {}
	for _, patientId in PatientsData.Order do
		local entry: any = PatientsData[patientId]
		if entry.Wing == K.TUTORIAL_WING and not entry.Night then
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
	local view = plotView(state)
	local isNight = U.nightOpen(state) -- night patients (and 🦉 Night Owl's after morning)

	-- 0. The tutorial's own two patients (no variant: nothing to explain yet). One step, always.
	if plan == "First" or plan == "Second" then
		if plan == "Second" then
			state.SecondSpawned = true -- (a clinic that can't treat its case skips it: the usual pool, below)
		end
		local caseId = Pure.tutorialCase(K.TUTORIAL_STATION[plan], view)
		local patientId = if caseId then U.tutorialSpecies(data) else nil
		if caseId and patientId then
			spawnPatient(state, patientId, nil, false, nil, 1, caseId)
			return
		end
	end
	local guests = plan == "Normal" -- regulars and Today's Visitor wait until the tutorial is done
	local cap = U.recipeCapFor(owner)

	-- A species that may come now, and the case it brings (nil = it can't come).
	local function caseFor(patientId: string): string?
		local entry: any = rawget(PatientsData :: any, patientId)
		if not U.speciesOpen(state, entry, false, isNight) then
			return nil
		end
		return Pure.pickCase(entry.Wing, view, rng:NextNumber())
	end

	-- 1. A regular whose story beat is due (never the very first patient: that one teaches the loop). Story reserves
	--    whoever it names, so it's only asked when there's room, and whoever it names comes. Their own case.
	if guests and state.Spawned >= 1 then
		local ok, regular = pcall(Story.dueRegular, owner)
		if not ok then
			report("Story.dueRegular", regular)
		elseif type(regular) == "string" then
			local entry: any = rawget(RegularsData :: any, regular)
			local caseId = if type(entry) == "table" then entry.Case else nil
			if type(entry) == "table" and type(caseId) ~= "string" then
				caseId = Pure.pickCase(entry.Wing, view, rng:NextNumber()) -- (a regular row without its own case)
			end
			if
				not (
					type(entry) == "table"
					and type(caseId) == "string"
					and Pure.eligible(rawget(Cases :: any, caseId), view)
				)
			then
				report("regular " .. regular, "named by Story but its case can't be treated here")
			elseif not U.hasGuest(state, regular, false) then -- (Story never names one who's already here)
				spawnPatient(state, entry.Patient, regular, false, nil, cap, caseId :: string)
				return
			end
		end
	end

	-- 2. Today's Visitor. Only asked for when it can be treated here, so it's never handed out and wasted.
	if guests and state.Spawned >= 2 and not U.hasGuest(state, nil, true) then
		local todays = Workspace:GetAttribute("TodaysVisitor")
		if type(todays) == "string" and todays ~= "" and caseFor(todays) then
			local ok, visitor = pcall(Daily.visitorFor, owner)
			if not ok then
				report("Daily.visitorFor", visitor)
			elseif type(visitor) == "string" then
				local caseId = caseFor(visitor)
				if caseId then
					spawnPatient(state, visitor, nil, true, U.rollVariant(state), cap, caseId)
					return
				end
			end
		end
	end

	-- 3. Any species that may come, weighted toward night patients at night and toward new Book pages.
	local pool: { { Id: string, Weight: number } } = {}
	local total = 0
	for _, patientId in PatientsData.Order do
		local entry: any = PatientsData[patientId]
		if U.speciesOpen(state, entry, false, isNight) and Pure.pickCase(entry.Wing, view, 0) ~= nil then
			local weight = if entry.Night then K.NIGHT_WEIGHT else 1
			local page = data.Book[patientId]
			if not page or page.Cured <= 0 then
				weight *= K.NEW_PAGE_WEIGHT
			end
			if patientId == state.LastPatient then
				weight *= K.REPEAT_WEIGHT
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
	local caseId = caseFor(chosen)
	if caseId then
		spawnPatient(state, chosen, nil, false, U.rollVariant(state), cap, caseId)
	end
end

------------------------------------------------------------------------------------------------------------------
-- Urgent patients (🚑 A&E from Lv 2, 🚁 the air ambulance from R2 at Lv 5)
------------------------------------------------------------------------------------------------------------------

-- A 🚑/🚁 patient's visit is under way here already: only one at a time comes by itself.
function U.urgentWaiting(state: PlotState): boolean
	for p in state.All do
		local phase = p.Phase
		if
			p.Urgent ~= ""
			and (phase == "Arriving" or phase == "Seated" or phase == "Requeue" or phase == "ToBay" or phase == "Bay")
		then
			return true
		end
	end
	return false
end

-- Calls an urgent patient: "AE" (an ambulance: it steps out at the parked Ambulance's StretcherSpot) or "VIP" (the
-- air ambulance: it steps out at HeliSpot on the roof). The pick: any species that may come by that way
-- (Pure.wingOpen; 🚁 brings only the Sky wing) with a case this clinic can treat and an urgent plan it can make
-- (Pure.urgentFor). Sets ArriveAt on the Ambulance / HeliSpot for Feel/HospitalFX. True = it came.
local function callUrgent(state: PlotState, kind: string): boolean
	local owner = state.Owner
	if not PlayerData.get(owner) then
		return false
	end
	local view = plotView(state)
	local makes = Pure.makes(view.Stations)
	local cap = U.recipeCapFor(owner)
	local minItems = math.max(1, math.floor(tonumber(Config.AE.MinItems) or 2))
	local byAir = kind == "VIP"
	local night = U.nightOpen(state)
	local pool: { { Id: string, Case: string, Plan: { string } } } = {}
	for _, patientId in PatientsData.Order do
		local entry: any = PatientsData[patientId]
		if U.speciesOpen(state, entry, byAir, night) then
			local caseId = Pure.pickCase(entry.Wing, view, rng:NextNumber())
			local case: any = if caseId then rawget(Cases :: any, caseId) else nil
			local plan = if case then Pure.urgentFor(case.Plan, makes, cap, minItems) else nil
			if caseId and plan then
				table.insert(pool, { Id = patientId, Case = caseId, Plan = plan })
			end
		end
	end
	if #pool == 0 then
		return false
	end
	local choice = pool[rng:NextInteger(1, #pool)]
	local start = U.markerGround(state.Plot.Spawn) -- no bay or helipad (a kit building): in by the gate
	local floor = 0
	local serverNow = Workspace:GetServerTimeNow()
	if kind == "AE" then
		local stretcher = U.buildingPart(state, "StretcherSpot")
		if stretcher then
			start = U.standAt(state, stretcher.CFrame, 0)
		end
		local building = state.Plot.Model:FindFirstChild("Building")
		local ambulance = building and building:FindFirstChild("Ambulance", true)
		if ambulance then
			ambulance:SetAttribute("ArriveAt", serverNow) -- Feel/HospitalFX: lights and a siren
		end
	else
		local heli = U.buildingPart(state, "HeliSpot")
		if heli then
			heli:SetAttribute("ArriveAt", serverNow) -- Feel/HospitalFX: the helicopter flies in and lands
			local roof = U.floorOf(heli, state.Plot.Model)
			if roof == 0 then
				roof = Hospital.floors(state.Level, LevelsData) -- the roof is the top floor (Data/Levels Floors)
			end
			if roof > 0 and U.landingOf(state.Plot, roof) and U.landingOf(state.Plot, 0) then
				start, floor = U.standAt(state, heli.CFrame, roof), roof
			end
		end
	end
	return spawnPatient(state, choice.Id, nil, false, U.rollVariant(state), cap, choice.Case, {
		Kind = kind,
		Plan = choice.Plan,
		Start = start,
		Air = byAir,
		Floor = floor,
	})
end

-- The ambulance and helicopter timers. Each comes about every so often (Pure.aeSeconds / Pure.vipSeconds; the first
-- ambulance Config.AE.FirstSeconds after the clinic reaches Lv 2), only while the owner stands at their clinic, is
-- done with the tutorial, the waiting room has room and no other 🚑/🚁 patient's visit is under way. An admin's call
-- comes as soon as there's room.
local function tickUrgent(state: PlotState, now: number, room: boolean)
	local forced = state.ForceUrgent[1]
	if forced then
		if room then
			table.remove(state.ForceUrgent, 1)
			callUrgent(state, forced)
		end
		return
	end
	local aeOpen = state.Level >= K.AE_LEVEL
	local vipOpen = state.Level >= K.HELI_LEVEL and RebirthLogic.has(state.Rebirths, "Helicopter")
	if not aeOpen then
		state.NextAE = now + Config.AE.FirstSeconds
	end
	if not vipOpen then
		state.NextVIP = now + Pure.vipSeconds(Config, rng:NextNumber())
	end
	if not room or not (aeOpen or vipOpen) then
		return
	end
	if U.tutorialAsk("active", false, state.Owner) or U.urgentWaiting(state) or not U.ownerAtClinic(state) then
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
-- The clinic's heartbeat: the layout, bays, patience and arrivals
------------------------------------------------------------------------------------------------------------------

-- What the plot's patients use from the owner's save and the nurses, once a tick.
local function refreshPlot(state: PlotState)
	local owner = state.Owner
	state.Level = U.levelAsk("level", owner, 1)
	state.Rebirths = U.rebirthsOf(owner)
	state.Effects = U.effectsOf(owner)
	state.Team = U.teamOf(state.Plot)
	state.Medic = U.medicOf(state.Plot)
	state.Receptionist = U.receptionOf(state.Plot)
	state.Rooms = U.roomsOf(owner)
end

-- What a patient may stand on: the Building, the Ground and the Rooms (solid parts only).
local function updateFloorRay(state: PlotState)
	local include: { Instance } = {}
	for _, name in { "Building", "Ground", "Rooms" } do
		local found = state.Plot.Model:FindFirstChild(name)
		if found then
			table.insert(include, found)
		end
	end
	state.FloorRay.FilterDescendantsInstances = include
end

-- Home now, never sad (no seat after a rebuild): its game is dropped and its items go back; a regular comes back
-- another time (Story.left).
local function goHome(state: PlotState, p: Patient)
	dropSession(p, true)
	p.Phase = "GoHome"
	local regular = p.Regular
	local storyLeft = (Story :: any).left
	if regular and type(storyLeft) == "function" then
		local ok, err = pcall(storyLeft, state.Owner, regular)
		if not ok then
			report("Story.left", err)
		end
	end
end

-- The bays open by the numbers changed: everyone keeps its bay or seat, or moves (Pure.reseat).
local function reseatAll(state: PlotState)
	local list: { any } = {}
	for p in state.All do
		if
			(p.Bay or p.Seat)
			and (p.Phase == "Seated" or p.Phase == "ToBay" or p.Phase == "Bay" or p.Phase == "Arriving")
		then
			table.insert(list, { Id = p.Id, Seat = p.Seat, Bay = p.Bay, Since = p.Since })
		end
	end
	table.sort(list, function(a: any, b: any): boolean
		if a.Since ~= b.Since then
			return a.Since < b.Since
		end
		return a.Id < b.Id
	end)
	local seats: { [number]: boolean } = {}
	for index in Building.SEATS do
		seats[index] = true
	end
	local bays: { [string]: boolean } = {}
	for _, info in Building.openBays(state.Level, state.Rooms) do
		bays[info.Id] = true
	end
	for id, where in Pure.reseat(list, seats, bays) do
		local p = state.ById[id]
		if p then
			if where.Leave then
				goHome(state, p)
			elseif p.Bay and where.Bay ~= p.Bay then
				-- Its bay closed: back to a seat, its exam and plan kept (a game on it is dropped, its items go back).
				dropSession(p, true)
				if not p.OnBed then
					freeBay(p)
				end
				if where.Seat and state.Seats[where.Seat] == nil then
					state.Seats[where.Seat] = p
					p.Seat = where.Seat
				end
				if p.Phase == "Bay" then
					p.Phase = "Requeue"
				end
			elseif where.Seat and where.Seat ~= p.Seat and not p.OnSeat then
				freeSeat(p)
				state.Seats[where.Seat] = p
				p.Seat = where.Seat
			end
		end
	end
end

-- The Building, the Rooms or the level changed (or LAYOUT_SECONDS passed): look the bays, stations and beds up again
-- and put the prompts on the bays as they are now. When the bays OPEN by the numbers change, re-seat everyone.
local function refreshLayout(state: PlotState, now: number)
	local building = state.Plot.Model:FindFirstChild("Building")
	local key = U.roomsKey(state) .. "|" .. state.Level
	local layout = state.Layout
	if building ~= layout.Building or key ~= layout.Key or now - layout.At >= K.LAYOUT_SECONDS then
		state.Layout = scanLayout(state, building, key, now)
		updateFloorRay(state)
		ensurePrompts(state)
	end
	local open: { string } = {}
	for _, info in Building.openBays(state.Level, state.Rooms) do
		table.insert(open, info.Id)
	end
	local openKey = table.concat(open, ",")
	if openKey ~= state.OpenKey then
		local first = state.OpenKey == ""
		state.OpenKey = openKey
		if not first then
			reseatAll(state)
		end
	end
end

-- Whether a bay may take this patient now: checked in and waiting (on its seat, standing in the waiting room, or
-- still walking there), with no bay yet, and settled in the waiting room once (Pure.mayCall: SeatedAt; a 🚑/🚁 one at
-- once). WHO sends it is the caller's rule: a player's Send (U.send), a Receptionist (U.receptionSend) or the tick's
-- own short list (U.autoCall).
function U.canCall(p: Patient, now: number): boolean
	return p.Bay == nil
		and (p.Phase == "Seated" or (p.Phase == "Arriving" and p.CheckedIn))
		and Pure.mayCall(now, p.SeatedAt, p.Urgent ~= "", 0)
end

-- The only patients the tick calls to a bay by itself (Logic/Routing.auto): a 🚑/🚁 one, and one that was sent before
-- (its bay closed under it). A walk-in nobody has sent yet stays on its seat.
function U.autoCall(p: Patient, now: number): boolean
	return K.Routing.auto(p.Urgent, p.Sent) and U.canCall(p, now)
end

-- THE step from the waiting room to a bay: calls patient `p` to bay `bayId`. Its callers: a player's Send (U.send),
-- a Receptionist (U.receptionSend) and the tick's own short list (assignBays). It checks everything itself (any
-- input: false = nothing changed). The
-- patient is this plot's and U.canCall holds; the bay is built, open and empty (bayUsable) and fits its case
-- (Logic/Visit.nextForBay: an X-ray case only the X-ray bay, every other case only an exam bay). Never yields: the
-- patient's own thread gets it up and walks it there (waitSeated -> goToBay; one still walking to its seat turns
-- round at the seat's front: findSeat).
function U.callToBay(state: PlotState, p: Patient, bayId: string): boolean
	if type(p) ~= "table" or p.Plot ~= state or state.ById[p.Id] ~= p or type(bayId) ~= "string" then
		return false
	end
	local info = Building.bay(bayId)
	if not info or state.BayOf[bayId] ~= nil or not bayUsable(state, bayId) or not U.canCall(p, os.clock()) then
		return false
	end
	if Visit.nextForBay({ { Id = p.Id, Since = p.Since, Tool = p.Case.Tool } }, info.Kind :: any) ~= p.Id then
		return false
	end
	p.Bay = bayId
	p.Sent = true
	state.BayOf[bayId] = p
	p.Model:SetAttribute("Bay", bayId)
	if p.Phase == "Seated" then
		p.Phase = "ToBay"
	end
	return true
end

-- Sends waiting patient `p` to the nearest free place that fits it (Logic/Routing.pickBay, from where it sits; through
-- the tutorial's one-at-a-time steps the first in order, so the first patient takes bay 1). `choice`: the player's
-- pick on the two-button card ("Exam" | "XRay"), nil for a plain press or a Receptionist. Returns (sent, toast?): a
-- wrong pick or no free place sends nobody and changes nothing (no penalty: it stays seated).
function U.send(state: PlotState, p: Patient, choice: string?): (boolean, string?)
	if not K.Routing.waiting(p.Phase, p.Bay, p.Urgent) then
		return false, nil
	end
	local kind = K.Routing.kindFor(p.Case.Tool)
	if choice ~= nil then
		local right, correction = K.Routing.check(choice, kind)
		if not right then
			return false, correction
		end
	end
	local from: Point? = nil
	if U.tutorialAsk("queueCap", nil, state.Owner) == nil then
		from = U.localOf(state, p.Pivot.Position)
	end
	local bayId = K.Routing.pickBay(U.places(state), kind, from)
	if not bayId or not U.callToBay(state, p, bayId) then
		return false, K.Routing.TEXT.Busy
	end
	return true, nil
end

U.lastSend = {} :: { [Player]: number } -- os.clock() of each player's last press (cleared when they leave)

-- A worker's press, from the Send prompt or the SendPatient remote: one every SEND_COOLDOWN per player; the player may
-- work this clinic (Plots.canWork: the owner, a friend, or anyone with OpenHelpers), the patient is this clinic's and
-- still waiting to be sent, and the player stands by it. Returns the patient, or nil (with a toast where it helps).
function U.mayPress(player: Player, state: PlotState?, visitId: any): Patient?
	if not state or not state.Active or type(visitId) ~= "number" then
		return nil
	end
	local now = os.clock()
	if now - (U.lastSend[player] or 0) < K.SEND_COOLDOWN then
		return nil
	end
	U.lastSend[player] = now
	if not Plots.canWork(player, state.Plot) then
		Remotes.toast(player, "🔒 Ask the owner to open up!")
		return nil
	end
	local p = state.ById[visitId]
	if not p or not K.Routing.waiting(p.Phase, p.Bay, p.Urgent) then
		return nil
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	if (root.Position - p.Pivot.Position).Magnitude > K.PROMPT_DISTANCE + K.DISTANCE_SLACK then
		return nil
	end
	return p
end

-- The Send prompt was pressed. With one kind of place it sends the patient now; with two (Lv 3+) the client's card
-- asks which place first and the pick comes by the SendPatient remote, so this press does nothing.
function U.onSendPrompt(plot: Plot, visitId: number, player: Player)
	local state = active[plot]
	if not state or K.Routing.needsChoice(state.Level, U.places(state)) then
		return
	end
	local p = U.mayPress(player, state, visitId)
	if p then
		local _, message = U.send(state, p, nil)
		if message then
			Remotes.toast(player, message)
		end
		refreshFront(state)
	end
end

-- The SendPatient RemoteEvent (client -> server; UI/SendCard): (visitId, choice). Nothing the client says is trusted:
-- the rate limit (Remotes.allow), the types (a whole number and one of the two strings), then U.mayPress (the player
-- may work the clinic that patient is at, it is still waiting, the player stands by it) and Logic/Routing.check.
function U.onSendRemote(player: Player, visitId: any, choice: any)
	if not Remotes.allow(player, K.SEND_REMOTE) then
		return
	end
	if type(visitId) ~= "number" or visitId ~= visitId or visitId % 1 ~= 0 or not K.Routing.isChoice(choice) then
		return
	end
	local state: PlotState? = nil
	for _, candidate in active do
		if candidate.ById[visitId] then
			state = candidate
			break
		end
	end
	local p = U.mayPress(player, state, visitId)
	if state and p then
		local _, message = U.send(state, p, choice)
		if message then
			Remotes.toast(player, message)
		end
		refreshFront(state)
	end
end

-- "Nurses help later": with a Receptionist on duty (Nurses.reception), each walk-in that has sat RECEPTION_SECONDS is
-- sent to the right kind of place, the longest wait first, one at a time RECEPTION_GAP apart
-- (Logic/Routing.receptionistReady). One with no free place waits; the next may go. No Receptionist: nobody.
function U.receptionSend(state: PlotState, now: number)
	if not state.Receptionist.Triage then
		return
	end
	local ready: { Patient } = {}
	for p in state.All do
		if
			K.Routing.waiting(p.Phase, p.Bay, p.Urgent)
			and K.Routing.receptionistReady(p.SeatedAt, now, state.LastSent, K.RECEPTION_SECONDS, K.RECEPTION_GAP)
		then
			table.insert(ready, p)
		end
	end
	table.sort(ready, function(a: Patient, b: Patient): boolean
		if a.Since ~= b.Since then
			return a.Since < b.Since
		end
		return a.Id < b.Id
	end)
	for _, p in ready do
		if U.send(state, p, nil) then
			state.LastSent = now
			return
		end
	end
end

-- The tick's own call (every tick, and as a patient checks in), only for those U.autoCall allows (a 🚑/🚁 patient; one
-- sent before whose bay closed): each usable empty bay calls the one who has waited longest and fits it (Pure.assign),
-- through U.callToBay. Walk-ins wait for the player's Send (or a Receptionist).
assignBays = function(state: PlotState)
	local free: { { Id: string, Kind: string } } = {}
	for _, info in Building.BAYS do
		if state.BayOf[info.Id] == nil and bayUsable(state, info.Id) then
			table.insert(free, { Id = info.Id, Kind = info.Kind })
		end
	end
	if #free == 0 then
		return
	end
	local now = os.clock()
	local waiting: { any } = {}
	for p in state.All do
		if U.autoCall(p, now) then
			table.insert(waiting, { Id = p.Id, Since = p.Since, Tool = p.Case.Tool })
		end
	end
	if #waiting == 0 then
		return
	end
	for _, pick in Pure.assign(free, waiting) do
		local p = state.ById[pick.Patient]
		if p then
			U.callToBay(state, p, pick.Bay)
		end
	end
end

local function makeSad(state: PlotState, p: Patient)
	if p.Phase ~= "Seated" and p.Phase ~= "Bay" then
		return
	end
	p.Phase = "Sad"
	freeSeat(p) -- the seat and the bay are free for the next one at once; it puffs away where it sits
	freeBay(p)
	local regular = p.Regular
	local storyLeft = (Story :: any).left -- a regular who leaves untreated comes back later (Story's extra)
	if regular and type(storyLeft) == "function" then
		local ok, err = pcall(storyLeft, state.Owner, regular)
		if not ok then
			report("Story.left", err)
		end
	end
	refreshFront(state)
end

local function tickPatience(state: PlotState, dt: number)
	if U.tutorialAsk("calm", false, state.Owner) then
		return -- the tutorial's steps 1-6: nobody runs out of patience, so the ring stays full
	end
	if state.PausedUntil > os.clock() or U.abilityPaused(state.Plot) then
		return -- 🎵 a Calm Song (Abilities PauseLine): every patience ring holds still
	end
	local outOfPatience: { Patient } = {}
	-- A Cheerer on duty (Server/Nurses keeps the plot's CheerPatience) makes everyone's patience last longer.
	local cheer = Pure.cheer(state.Plot.Model:GetAttribute("CheerPatience"), K.MAX_CHEER_PATIENCE)
	-- 🚑/🚁 patients drain slower with the A&E team and a Medic on duty.
	local slower = Pure.slower(state.Team.Urgent, state.Medic, K.MAX_SLOWER)
	for p in state.All do
		local rate: number? = nil
		if p.Phase == "Seated" then
			rate = Visit.PATIENCE.Waiting
		elseif needsDoctor(p) then
			rate = Visit.PATIENCE.Bay
		end
		if rate then
			local drain = rate / cheer / (if p.Urgent ~= "" then slower else 1)
			p.Patience = math.max(p.Patience - dt * drain, 0)
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
	refreshLayout(state, now)
	tickPatience(state, dt)
	assignBays(state)
	U.receptionSend(state, now)
	-- The waiting room holds the level's line (never past Config.MaxQueue); the tutorial's cap counts everyone whose
	-- plan isn't done (one at a time). A higher level refills it sooner (spawnSeconds) and opens more bays.
	local tutorialCap = U.tutorialAsk("queueCap", nil, state.Owner)
	local levelCap = math.min(Config.MaxQueue, U.levelAsk("queueCap", state.Owner, Config.MaxQueue))
	local room = U.waitingCount(state) < levelCap
		and (type(tutorialCap) ~= "number" or U.activeCount(state) < tutorialCap)
	tickUrgent(state, now, room)
	if now >= state.NextSpawn and room then
		local forced = table.remove(state.Forced, 1)
		local every = Hospital.arrival(
			U.levelAsk("spawnSeconds", state.Owner, Config.SpawnEverySeconds),
			{ state.Effects.Arrive, state.Receptionist.Arrive }
		)
		if forced then
			-- An admin's pick (Patients.sendNext) comes first; more picks follow REFILL_SECONDS apart.
			state.NextSpawn = now + (if #state.Forced > 0 then K.REFILL_SECONDS else every * rng:NextNumber(0.85, 1.15))
			local entry: any = rawget(PatientsData :: any, forced)
			local caseId = if entry then Pure.pickCase(entry.Wing, plotView(state), rng:NextNumber()) else nil
			if caseId then
				spawnPatient(state, forced, nil, false, nil, U.recipeCapFor(state.Owner), caseId)
			end
		else
			local plan = U.tutorialAsk("spawnPlan", "Normal", state.Owner, next(state.All) == nil, state.SecondSpawned)
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
		task.wait(K.TICK)
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
-- Abilities acting on the clinic
------------------------------------------------------------------------------------------------------------------

local function refill(p: Patient)
	p.Patience = p.PatienceMax
	showRing(p, 1, K.RING_CALM)
	showPatience(p, 1)
end

-- Abilities.Fired (plot, nurseId, abilityId, kind, value): the kinds that act on the patients.
--   RefillFront  the front patient's patience is full again (🤗 Warm Hug; with nobody in a bay, the longest waiting)
--   RefillLine   everyone waiting or in a bay (🌈 Rainbow Cheer)
--   PauseLine    no patience drains for `value` seconds (🎵 Calm Song; Abilities.patiencePaused too)
-- (CureLine, 💫 Miracle, is Server/Abilities' own: it calls Patients.finishVisit for each bay patient, then fires.)
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
		local front = frontList(state)[1]
		if not front then
			local best: Patient? = nil
			for p in state.All do
				if p.Phase == "Seated" and (best == nil or p.Since < best.Since) then
					best = p
				end
			end
			front = best
		end
		if front then
			refill(front)
		end
	elseif kind == "RefillLine" then
		for p in state.All do
			local phase = p.Phase
			if phase == "Arriving" or phase == "Seated" or phase == "ToBay" or phase == "Bay" or phase == "Requeue" then
				refill(p)
			end
		end
	elseif kind == "PauseLine" then
		state.PausedUntil = math.max(state.PausedUntil, os.clock() + U.clampNumber(value, 0, 60, 0))
	end
end

------------------------------------------------------------------------------------------------------------------
-- Plots opening and closing
------------------------------------------------------------------------------------------------------------------

local FRONT_ATTRIBUTES = { "FrontBay", "FrontStage", "FrontItem", "FrontStation", "FrontNeeds", "QueueNeeds" }

local function activate(owner: Player, plot: Plot)
	local current = active[plot]
	if current then
		if current.Owner == owner then
			return
		end
		deactivate(plot)
	end

	-- Standing on a floor: only what you can stand on (markers, glass and the walls above the ground storey don't
	-- collide).
	local floorRay = RaycastParams.new()
	floorRay.FilterType = Enum.RaycastFilterType.Include
	floorRay.RespectCanCollide = true

	local now = os.clock()
	local state: PlotState = {
		Plot = plot,
		Owner = owner,
		Active = true,
		Pivot = plot.Model:GetPivot(),
		FloorRay = floorRay,
		All = {},
		ById = {},
		Seats = {},
		BayOf = {},
		Beds = {},
		Layout = {
			Building = nil,
			Key = "",
			At = -math.huge,
			Seats = {},
			Bays = {},
			Stations = {},
			Beds = {},
			RoomBeds = {},
		},
		OpenKey = "",
		Prompts = {},
		Rooms = U.roomsOf(owner),
		NextSpawn = now + K.FIRST_PATIENT_SECONDS,
		Spawned = 0,
		LastPatient = nil,
		Loop = nil,
		SecondSpawned = false,
		Forced = {},
		Level = U.levelAsk("level", owner, 1),
		Rebirths = U.rebirthsOf(owner),
		Effects = U.effectsOf(owner),
		Team = { Cash = 1, Recover = 1, Urgent = 1 },
		Medic = 1,
		Receptionist = { Arrive = 1, Triage = false },
		NextAE = now + Config.AE.FirstSeconds,
		NextVIP = now + Pure.vipSeconds(Config, rng:NextNumber()),
		ForceUrgent = {},
		PausedUntil = 0,
		LiftBusy = false,
		LastSent = -math.huge,
	}
	active[plot] = state
	for _, name in FRONT_ATTRIBUTES do
		plot.Model:SetAttribute(name, "")
	end
	local ok, err = pcall(refreshLayout, state, now)
	if not ok then
		report("the clinic's layout", err)
	end
	refreshFront(state)
	local loop = coroutine.create(plotLoop)
	state.Loop = loop
	task.spawn(loop, state)
end

-- Never yields: it runs inside Plots.PlotReleased, before Plots clears the plot. Everyone goes home now (Pure.closing:
-- a patient whose plan is complete, or completes with its open game's steps, is paid first).
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
	local rows: { any } = {}
	for p in state.All do
		table.insert(everyone, p)
		table.insert(rows, {
			Id = p.Id,
			Plan = p.Plan,
			Done = p.Done,
			InFlight = if p.SessionKind == "Treat" then p.SessionIndices else nil,
			Paid = p.Paid,
		})
	end
	local verdicts = Pure.closing(rows)
	for _, p in everyone do
		local ok, err = pcall(function()
			if verdicts[p.Id] == "Pay" then
				if p.Session and p.SessionKind == "Treat" and p.SessionIndices then
					p.Done = Recipe.apply(p.Done, p.SessionIndices)
					p.Helper = p.SessionHelper or p.Helper
				end
				dropSession(p, false)
				p.PatienceLeft = math.clamp(p.Patience / p.PatienceMax, 0, 1)
				payVisit(p)
			else
				-- A helper who is staying gets their own items back (never the owner: the clinic closes because they
				-- are leaving).
				local helper = p.SessionHelper
				dropSession(p, helper ~= nil and helper ~= state.Owner and helper.Parent == Players)
			end
			p.Model:SetAttribute("State", "Leaving")
		end)
		if not ok then
			report("closing a visit", err)
		end
		removePatient(p)
	end
	table.clear(state.Seats)
	table.clear(state.BayOf)
	table.clear(state.Beds)
	table.clear(state.ForceUrgent)
	state.LiftBusy = false
	for _, prompt in state.Prompts do
		prompt.Enabled = false
		prompt.ObjectText = ""
	end
	for _, name in FRONT_ATTRIBUTES do
		plot.Model:SetAttribute(name, "")
	end
end

------------------------------------------------------------------------------------------------------------------
-- The visit API (contract C6)
------------------------------------------------------------------------------------------------------------------

local function stateOf(plotArg: any): PlotState?
	local plot: Plot? = if typeof(plotArg) == "Instance"
		then Plots.fromInstance(plotArg)
		elseif type(plotArg) == "table" then plotArg
		else nil
	local state = if plot then active[plot] else nil
	return if state and state.Active then state else nil
end

local function patientOf(state: PlotState, patientId: any): Patient?
	return if type(patientId) == "number" then state.ById[patientId] else nil
end

function Patients.bayView(
	plotArg: any
): { { Bay: string, PatientId: number, Stage: string, Needs: { string }, Since: number } }
	local out: { { Bay: string, PatientId: number, Stage: string, Needs: { string }, Since: number } } = {}
	local state = stateOf(plotArg)
	if not state then
		return out
	end
	for _, p in bayPatients(state) do
		table.insert(out, {
			Bay = p.Bay or "",
			PatientId = p.Id,
			Stage = if p.Examined then "Treat" else "Exam",
			Needs = if p.Examined then Pure.needs(p.Plan, p.Done, p.SessionIndices) else {},
			Since = p.BaySince,
		})
	end
	return out
end

function Patients.neededMedicines(plotArg: any): { string }
	return Pure.medicines(Patients.bayView(plotArg), K.DISPENSARY_OPTIONS)
end

function Patients.examine(plotArg: any, patientId: number, helper: Player?): string?
	local state = stateOf(plotArg)
	local p = if state then patientOf(state, patientId) else nil
	if not p or p.Phase ~= "Bay" or not p.OnBed then
		return if p and p.Examined then p.CaseId else nil
	end
	return examineNow(p, if typeof(helper) == "Instance" and helper:IsA("Player") then helper else nil)
end

function Patients.give(plotArg: any, patientId: number, items: { string }, helper: Player?): { number }
	local state = stateOf(plotArg)
	local p = if state then patientOf(state, patientId) else nil
	if not (state and p) or p.Phase ~= "Bay" or not p.OnBed or not p.Examined or type(items) ~= "table" then
		return {}
	end
	local have: { string } = {}
	for _, itemId in items do
		if type(itemId) == "string" then
			table.insert(have, itemId)
		end
	end
	local indices =
		Recipe.match(p.Plan, if p.SessionIndices then Recipe.apply(p.Done, p.SessionIndices) else p.Done, have)
	local player = if typeof(helper) == "Instance" and helper:IsA("Player") then helper else nil
	giveItems(state, p, indices, player or state.Owner, nil, player ~= nil)
	return indices
end

function Patients.finishVisit(plotArg: any, patientId: number, helper: Player?): boolean
	local state = stateOf(plotArg)
	local p = if state then patientOf(state, patientId) else nil
	if not (state and p) then
		return false
	end
	local ok = finishOnSpot(state, p, if typeof(helper) == "Instance" and helper:IsA("Player") then helper else nil)
	if ok then
		refreshFront(state)
	end
	return ok
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
	local entry: any = if type(patientId) == "string" then rawget(PatientsData :: any, patientId) else nil
	if type(entry) ~= "table" then
		return false, Remotes.OOPS
	end
	if Pure.pickCase(entry.Wing, plotView(state), 0) == nil then
		return false, "🔒 Needs another room first!"
	end
	if #state.Forced >= Config.MaxQueue then
		return false, "⏳ Waiting room is full!"
	end
	table.insert(state.Forced, patientId)
	state.NextSpawn = math.min(state.NextSpawn, os.clock())
	local wing: any = rawget(WingsData :: any, entry.Wing)
	local icon = if type(wing) == "table" and type(wing.Icon) == "string" then wing.Icon else "🐾"
	return true, icon .. " " .. tostring(entry.Name) .. " is next!"
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

-- An admin's urgent call: it comes as soon as the waiting room has room (no timer, no tutorial or presence rule).
local function adminCall(owner: Player, kind: string, minLevel: number, icon: string): (boolean, string)
	local plot = Plots.getPlot(owner)
	local state = if plot then active[plot] else nil
	if not state then
		return false, "🏠 No clinic yet!"
	end
	if U.levelAsk("level", owner, 1) < minLevel then
		return false, "🏥 Lv " .. minLevel .. " first!"
	end
	if #state.ForceUrgent >= K.MAX_FORCED_URGENT then
		return false, "⏳ Waiting room is full!"
	end
	table.insert(state.ForceUrgent, kind)
	return true, icon .. " On the way!"
end

-- 🚑 An ambulance as soon as the waiting room has room (Lv 2+).
function Patients.adminAmbulance(owner: Player): (boolean, string)
	return adminCall(owner, "AE", K.AE_LEVEL, "🚑")
end

-- 🚁 An air ambulance as soon as the waiting room has room (Lv 5; no R2 needed).
function Patients.adminHelicopter(owner: Player): (boolean, string)
	return adminCall(owner, "VIP", K.HELI_LEVEL, "🚁")
end

function Patients.start()
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
	Remotes.SendPatient.OnServerEvent:Connect(function(player: Player, visitId: any, choice: any)
		local ok, err = pcall(U.onSendRemote, player, visitId, choice)
		if not ok then
			report("SendPatient", err)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastTreat[player] = nil
		U.lastSend[player] = nil
	end)
	for _, plot in Plots.all() do
		local owner = plot.Owner
		if owner then
			activate(owner, plot) -- plots handed out before Patients started
		end
	end
end

return Patients
