--!strict
-- Patients: the line of creatures at every clinic, the Treat prompt on the Counter, beds and the cure
-- (build plan §B5 "Patients", Task 1). Server only. API: Patients.start().
-- For the 🛠️ Admin panel only (Server/Admin checks the caller is an admin):
--   Patients.sendNext(owner, patientId): (ok, message)   that Data/Patients patient comes next at the owner's clinic
--       (before the usual pick and whatever the tutorial's plan says) once there's room in line; up to
--       Config.MaxQueue picks wait their turn. Refused when no station on the plot can treat it.
--   Patients.reopen(owner): boolean   empties the owner's clinic and opens it again, as on a fresh join (a patient
--       already treated is cured on the spot first, exactly as when an owner leaves)
--   Progression v2 (build plan §B8; STUB (T7) until T7 lands them):
--   Patients.adminAmbulance(owner): (ok, message)    an ambulance now (Lv 2+)
--   Patients.adminHelicopter(owner): (ok, message)   an air ambulance now (Lv 5; no R2 needed)
--   FOUNDATION: until T7 lands the Sunny/Sky rules, a patient whose wing needs rebirths or a helicopter (Data/Wings
--   Rebirths / Only) never comes, so nothing changes for anyone before T7.
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
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Palette = require(Shared.Palette)
local Prices = require(Shared.Logic.Prices)
local Recipe = require(Shared.Logic.Recipe)
local AilmentsData = require(Shared.Data.Ailments)
local ItemsData = require(Shared.Data.Items)
local PatientsData = require(Shared.Data.Patients)
local RegularsData = require(Shared.Data.Regulars)
local StationsData = require(Shared.Data.Stations)
local WingsData = require(Shared.Data.Wings)

local Carry = require(script.Parent.Carry)
local CreatureBuilder = require(script.Parent.CreatureBuilder)
local Cure = require(script.Parent.Cure)
local Daily = require(script.Parent.Daily)
local Levels = require(script.Parent.Levels)
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
}

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
}

local active: { [Plot]: PlotState } = {}
local prompts: { [Plot]: ProximityPrompt } = {}
local lastTreat: { [Player]: number } = {}
local rng = Random.new()

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
local Pure = {}

-- What one treat gives: the recipe slots the helper's own items fill, then the ones the nurse tray fills (each in
-- recipe order; each item used once). Carry first, so a kid's own making always counts.
function Pure.plan(
	recipe: { string },
	done: { boolean },
	carried: { string },
	tray: { string }
): ({ number }, { number })
	local fromCarry = Recipe.match(recipe, done, carried)
	local fromTray = Recipe.match(recipe, Recipe.apply(done, fromCarry), tray)
	return fromCarry, fromTray
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
	local standHalf, standBack = 11, 1
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

-- Hops along a path of points, a few studs per hop, turning to face where it's going.
local function walk(p: Patient, points: { Vector3 }): boolean
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
			local landing = groundAt(state, from + direction * stepLength)
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

-- The front patient, when it's standing at the Counter waiting to be treated (not mid-mini-game).
local function waitingFront(state: PlotState): Patient?
	local front = state.Queue[1]
	if front and front.State == "Queue" and front.Arrived and not front.Session then
		return front
	end
	return nil
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
	local front = waitingFront(state)
	local waiting = front ~= nil
	local item, station, icon, needs = "", "", "", ""
	if front then
		item, station, icon = front.Item, front.Station, front.AilmentIcon
		needs = Recipe.join(Pure.needs(front.Recipe, front.Done, nil))
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
			setState(behind, "Arriving")
		end
	end
	if state.Active then
		state.NextSpawn = math.max(state.NextSpawn, os.clock() + REFILL_SECONDS)
		refreshFront(state)
	end
end

-- The free bed nearest the Counter: Bed_<n> parts in the rooms, and the extra beds of the hospital level's
-- Building (Server/Levels builds it; its Beds count includes the Stand's own bed).
local function freeBed(state: PlotState): BasePart?
	local counter = state.Plot.Counter.Position
	local best: BasePart?, bestDistance = nil, math.huge
	for _, holderName in { "Rooms", "Building" } do
		local holder = state.Plot.Model:FindFirstChild(holderName)
		if holder then
			for _, descendant in holder:GetDescendants() do
				if
					descendant:IsA("BasePart")
					and string.match(descendant.Name, "^Bed_%d+$")
					and not state.Beds[descendant]
				then
					local distance = (descendant.Position - counter).Magnitude
					if distance < bestDistance then
						best, bestDistance = descendant, distance
					end
				end
			end
		end
	end
	return best
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

local function removePatient(p: Patient)
	if p.State == "Gone" then
		return
	end
	dropSession(p, true)
	local state = p.Plot
	removeFromQueue(state, p)
	releaseBed(state, p)
	p.State = "Gone"
	state.All[p] = nil
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
	local owner = p.Plot.Owner
	local helper = owner
	local treatedBy = p.Helper
	if treatedBy and treatedBy.Parent == Players then
		helper = treatedBy -- if the helper has left, the owner gets the cure
	end
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

local function leave(p: Patient)
	local state = p.Plot
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

local function treatAndRecover(p: Patient)
	local state = p.Plot
	setState(p, "Treated")
	if not hop(p, p.Pivot, p.HopHeight * 0.9, 0.3) then -- a happy little bounce
		return
	end

	local bed = p.Bed
	if bed then
		if not walk(p, bedRoute(state, p.Pivot.Position, bedFoot(bed))) then
			return
		end
		if bed.Parent then
			if not hop(p, bedPose(bed, true, p.BaseScale), 1.8, 0.5) then -- flop into bed
				return
			end
			p.InBed = true
		end
	end

	-- Rest: eyes closed, pink sparkles, the ring fills up.
	p.State = "Recovering"
	setState(p, "Recovering")
	CreatureBuilder.setMood(p.Model, "Sleep")
	p.Badge.Icon.Text = ICON_SLEEP
	CreatureBuilder.setEffect(p.Model, "Heal", true)
	CreatureBuilder.setEffect(p.Model, "HealLight", true)
	local started = os.clock()
	while true do
		local done = (os.clock() - started) / Config.RecoverSeconds
		showRing(p, done, RING_HEAL)
		if done >= 1 then
			break
		end
		if not sleep(p, TICK) then
			return
		end
	end
	CreatureBuilder.setEffect(p.Model, "Heal", false)
	CreatureBuilder.setEffect(p.Model, "HealLight", false)

	-- Cured!
	p.State = "Cured"
	setState(p, "Cured")
	resolveCure(p)
	CreatureBuilder.setMood(p.Model, "Happy")
	p.Badge.Icon.Text = ICON_CURED
	CreatureBuilder.effectAt(p.Root.Position + Vector3.new(0, 1.6 * p.BaseScale, 0), "Cure")
	if bed and p.InBed then
		if not hop(p, bedPose(bed, false, p.BaseScale), 2.6, 0.6, math.pi * 2) then -- spin up on the bed
			return
		end
		releaseBed(state, p)
		local foot = groundAt(state, bedFoot(bed))
		local away = bed.CFrame.LookVector * Vector3.new(1, 0, 1)
		local facing = if away.Magnitude > 0.01 then CFrame.lookAt(foot, foot + away) else CFrame.new(foot)
		if not hop(p, facing, 1.8, 0.45) then
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
				setState(p, "Arriving")
				refreshFront(state)
			end
			if not stepToward(p, spot) then
				return false
			end
		else
			if not p.Arrived then
				p.Arrived = true
				setState(p, "Waiting")
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
	scaleTo(p, p.BaseScale, 0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out) -- pop in
	if not hop(p, p.Pivot, p.HopHeight * 1.2, 0.45) then
		return
	end
	if not waitInLine(p) then
		return
	end
	if p.State == "Treated" then
		treatAndRecover(p)
	elseif p.State == "Sad" then
		sadLeave(p)
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

local function rollVariant(): string?
	if rng:NextNumber() < Config.SparklyChance then
		return "Sparkly"
	end
	if Workspace:GetAttribute("IsWinter") == true and rng:NextNumber() < Config.FrostyChance then
		return "Frosty"
	end
	return nil
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

local function spawnPatient(
	state: PlotState,
	patientId: string,
	regular: string?,
	visitor: boolean,
	variant: string?,
	cap: number
)
	local entry = PatientsData[patientId]
	local regularEntry = if regular then RegularsData[regular] else nil
	local ailmentId = if regularEntry then regularEntry.Ailment elseif entry then entry.Ailment else nil
	local ailment = if ailmentId then AilmentsData[ailmentId] else nil
	local station = if ailment then StationsData[ailment.Station] else nil
	local recipe = recipeOf(patientId, regular, cap)
	if not (ailment and station and ItemsData[station.Item] and recipe) then
		return
	end

	local ok, built = pcall(CreatureBuilder.build, patientId, variant)
	if not ok or typeof(built) ~= "Instance" or not built:IsA("Model") then
		report("CreatureBuilder.build", built)
		return
	end
	local model: Model = built
	local root = model.PrimaryPart
	local badge = CreatureBuilder.badge(model)
	if not root or not badge then
		model:Destroy()
		return
	end

	-- Night patients, and Night-wing regulars (they only visit at night): glow, pay 2x, count for night goals.
	local night = (entry ~= nil and entry.Night == true) or (regularEntry ~= nil and regularEntry.Wing == "Night")
	local patience = patienceFor(state.Owner, regular ~= nil or visitor)
	local rhythm = rng:NextNumber(0.9, 1.12) -- every creature hops to its own beat
	local start = markerGround(state.Plot.Spawn)
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
	}

	CreatureBuilder.setMood(model, "Sick")
	showRing(p, 1, RING_CALM)
	badge.Star.Visible = visitor
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
	-- PivotTo, not root.CFrame: the model isn't in Workspace yet, so its welds aren't live and the body would stay
	-- behind at the origin (each weld then locks in that gap when the model is parented in).
	model:PivotTo(start)
	model:ScaleTo(p.BaseScale * 0.15) -- pops in from tiny
	model.Parent = state.Plot.Model:FindFirstChild("Patients") or state.Plot.Model

	state.All[p] = true
	table.insert(state.Queue, p)
	model:SetAttribute("QueueIndex", #state.Queue)
	state.Spawned += 1
	state.LastPatient = patientId
	local thread = coroutine.create(run)
	p.Thread = thread
	task.spawn(thread, p)
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
	local isNight = Workspace:GetAttribute("IsNight") == true

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
		-- STUB (T7): Progression v2's wings wait for T7's rules (Sunny from R1, Sky by helicopter only)
		local wing = rawget(WingsData :: any, entry.Wing)
		if type(wing) == "table" and (wing.Rebirths ~= nil or wing.Only ~= nil) then
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
				spawnPatient(state, visitor, nil, true, rollVariant(), cap)
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
	spawnPatient(state, chosen, nil, false, rollVariant(), cap)
end

------------------------------------------------------------------------------------------------------------------
-- The clinic's heartbeat: patience and arrivals
------------------------------------------------------------------------------------------------------------------

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
	local outOfPatience: { Patient } = {}
	-- A Cheerer on duty (Server/Nurses keeps the plot's CheerPatience) makes everyone's patience last longer.
	local cheer = Pure.cheer(state.Plot.Model:GetAttribute("CheerPatience"), MAX_CHEER_PATIENCE)
	for index, p in state.Queue do
		if p.State == "Queue" and p.Arrived and not p.Claimed and not p.Session then -- paused mid-mini-game
			local rate = (if index == 1 then 1 else QUEUE_PATIENCE_RATE) / cheer
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
	tickPatience(state, dt)
	local cap = tutorialAsk("queueCap", nil, state.Owner)
	-- The hospital level's line, never longer than Config.MaxQueue (3: one being treated + 2 waiting, on the lane's
	-- three numbered spots). A higher level refills it sooner (spawnSeconds), it doesn't make it longer.
	local levelCap = math.min(Config.MaxQueue, levelAsk("queueCap", state.Owner, Config.MaxQueue))
	local maxQueue = if type(cap) == "number" then math.min(cap, levelCap) else levelCap
	if now >= state.NextSpawn and #state.Queue < maxQueue then
		local forced = table.remove(state.Forced, 1)
		-- A higher hospital level gets patients faster (Data/Levels SpawnSeconds, Lv 1 = Config.SpawnEverySeconds):
		-- the level's throughput. The line itself never grows past Config.MaxQueue (maxQueue above).
		local every = levelAsk("spawnSeconds", state.Owner, Config.SpawnEverySeconds)
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

local function beginTreatment(state: PlotState, p: Patient, helper: Player)
	p.Helper = helper
	p.PatienceLeft = math.clamp(p.Patience / p.PatienceMax, 0, 1)
	p.State = "Treated"
	local bed = freeBed(state)
	if bed then
		state.Beds[bed] = p
		p.Bed = bed
		removeFromQueue(state, p) -- off to bed: the line moves up now
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
end

-- Recipe items were given (a mini-game settled, or a Healer delivered): tick them off and refill some patience,
-- then off to bed when the recipe is complete, or back in line for the rest. Never yields. True = complete.
local function giveItems(state: PlotState, p: Patient, indices: { number }, helper: Player): boolean
	p.Done = Recipe.apply(p.Done, indices)
	p.Patience = Pure.refill(p.Patience, p.PatienceMax, ITEM_PATIENCE, #indices)
	showRecipe(p)
	if Recipe.complete(p.Recipe, p.Done) then
		beginTreatment(state, p, helper)
		return true
	end
	local fraction = p.Patience / p.PatienceMax
	showRing(p, fraction, ringColor(fraction))
	p.NextIdle = 0 -- a happy little hop straight away (its own thread does it)
	setState(p, if p.Arrived then "Waiting" else "Arriving")
	refreshFront(state)
	return false
end

-- Treatment settled the session on `p` (the player's report, the timeout, or the helper leaving).
local function settleTreat(p: Patient, sessionId: number, tip: number): boolean
	if p.Session ~= sessionId then
		return false -- dropped already (the patient went away)
	end
	local helper = p.SessionHelper
	local indices = p.SessionIndices or {}
	p.Session = nil
	p.SessionHelper = nil
	p.SessionIndices = nil
	p.SessionCarried = nil
	if not alive(p) or p.State ~= "Queue" then
		return false
	end
	p.TipPaid += math.max(0, tip)
	local state = p.Plot
	return giveItems(state, p, indices, helper or state.Owner)
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
	local p = state.Queue[1]
	if not p or p.State ~= "Queue" or not p.Arrived or p.Claimed or p.Session then
		return
	end
	if Treatment.busy(player) then
		return -- one mini-game at a time
	end

	-- What fits: the helper's own items first, then the nurse tray's.
	local carried = carrying(player)
	local fromCarry, fromTray = Pure.plan(p.Recipe, p.Done, carried, trayItems(plot))
	if #fromCarry == 0 and #fromTray == 0 then
		refuse(p, player, #carried == 0)
		return
	end

	-- Take them: they're spent now (the mini-game can't fail).
	p.Claimed = true
	local given: { number } = {}
	local taken: { string } = {}
	for _, index in fromCarry do
		local itemId = p.Recipe[index]
		if takeItem(player, itemId) then
			table.insert(given, index)
			table.insert(taken, itemId)
		end
	end
	for _, index in fromTray do
		if takeFromTray(plot, p.Recipe[index]) then
			table.insert(given, index)
		end
	end
	p.Claimed = false
	table.sort(given)
	local function keepYourItems()
		for _, itemId in taken do
			giveBack(player, itemId)
		end
	end
	if #given == 0 or not (alive(p) and p.State == "Queue" and state.Queue[1] == p and not p.Session) then
		keepYourItems() -- the patient moved on while we checked
		return
	end

	local items: { string } = {}
	for _, index in given do
		table.insert(items, p.Recipe[index])
	end
	local sessionId: number? = nil
	local spec: Treatment.Spec = {
		Plot = plot,
		PatientId = p.PatientId,
		Items = items,
		Position = p.Root.Position + Vector3.new(0, 3 * p.BaseScale, 0),
		Counter = plot.Counter.Position,
		TipSoFar = p.TipPaid,
		Settle = function(_ratings: { Types.Rating }, tip: number): boolean
			local id = sessionId
			return id ~= nil and settleTreat(p, id, tip)
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

-- A Healer nurse is ready (Nurses.Heal via Treatment.onHeal): the front patient gets what the nurse tray holds for
-- it, rated OK, with no tip and no combo change (players still beat nurses with Perfects). The owner is the
-- helper, so the cure is theirs. Returns the items given (Treatment then tells Nurses.healed).
local function healFront(plotArg: any, _nurseId: string): { string }
	local plot: Plot? = if typeof(plotArg) == "Instance" then Plots.fromInstance(plotArg) else plotArg
	if not plot then
		return {}
	end
	local state = active[plot]
	if not state or not state.Active or state.Owner.Parent ~= Players then
		return {}
	end
	local p = waitingFront(state)
	if not p or p.Claimed then
		return {}
	end
	local given: { number } = {}
	local items: { string } = {}
	for _, index in Recipe.match(p.Recipe, p.Done, trayItems(plot)) do
		local itemId = p.Recipe[index]
		if takeFromTray(plot, itemId) then
			table.insert(given, index)
			table.insert(items, itemId)
		end
	end
	if #given > 0 then
		giveItems(state, p, given, state.Owner)
	end
	return items
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

-- STUB (T7): an ambulance now (Lv 2+)
function Patients.adminAmbulance(_owner: Player): (boolean, string)
	return false, Remotes.SOON
end

-- STUB (T7): an air ambulance now (Lv 5; no R2 needed)
function Patients.adminHelicopter(_owner: Player): (boolean, string)
	return false, Remotes.SOON
end

function Patients.start()
	for _, plot in Plots.all() do
		ensurePrompt(plot)
	end
	Treatment.onHeal(healFront)
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
