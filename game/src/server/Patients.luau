--!strict
-- Patients: the line of creatures at every clinic, the Treat prompt on the Counter, beds and the cure
-- (build plan §B5 "Patients", Task 1). Server only. API: Patients.start().
-- For the 🛠️ Admin panel only (Server/Admin checks the caller is an admin):
--   Patients.sendNext(owner, patientId): (ok, message)   that Data/Patients patient comes next at the owner's clinic
--       (before the usual pick and whatever the tutorial's plan says) once there's room in line; up to
--       Config.MaxQueue picks wait their turn. Refused when no station on the plot can treat it.
--   Patients.reopen(owner): boolean   empties the owner's clinic and opens it again, as on a fresh join (a patient
--       already treated is cured on the spot first, exactly as when an owner leaves)
--
-- A visit, step by step:
--   1. Arrive. Each owned plot gets a patient every Config.SpawnEverySeconds while fewer than Config.MaxQueue
--      are there. Who comes, in order: a regular whose story beat is due (Story.dueRegular, with a speech
--      bubble from Story.bubble), Today's Visitor (Daily.visitorFor, a ⭐ on the badge), otherwise a patient
--      whose ailment's station is on the plot. Night patients only come at night (and are likelier then), Winter
--      patients need the Winter Wing, and new Book pages are likelier. Variants: Sparkly at Config.SparklyChance,
--      Frosty at Config.FrostyChance while Workspace.IsWinter (never on regulars). Regulars and the visitor
--      wait longer (GuestPatienceMultiplier). Night-wing regulars count as night patients (glow, ctx.Night).
--   2. Wait in line in front of the Counter. Patience (Prices.patience with the owner's Comfy Chairs level)
--      drains while a patient stands in line: full speed at the front, slower behind. When it runs out the
--      patient leaves with a sad puff (a regular: Story.left, so they come back later). No penalty, ever.
--   3. Treat. The `TreatPrompt` on the Counter treats the front patient: Plots.canWork, then Carry.take(the
--      item its ailment needs). A wrong (or no) item gets a head-shake and a toast with the right station icon.
--   4. Recover. The patient hops to a free Bed_<n> on the plot (nearest the Counter first). With every bed
--      taken it rests in place at the front of the line, so the line waits: more beds = a faster clinic.
--      After Config.RecoverSeconds: Cure.resolve(ctx), a happy spin, and it hops out of the gate.
--   5. Cleanup. Plots.PlotReleased (the owner left) removes every patient on that plot right away, before
--      Plots clears the plot. A patient already treated (its item spent) is cured on the spot first, so a helper
--      never loses their work. Nothing on the plot errors, and the plot is clean for the next owner.
--
-- The first-session tutorial (Server/Tutorial, by the OWNER's step). Nothing here changes for an owner who's done.
--   · Who comes (Tutorial.spawnPlan): nobody during the welcome; then one easy first patient (a Starter patient
--     needing the 🧪 Remedy); then one Starter patient needing 🩹; then the usual pool. Never a regular or Today's
--     Visitor until the tutorial is done. No variants on the two tutorial patients.
--   · One at a time in line through step 6 (Tutorial.queueCap). A spawn that's held back doesn't use up the timer,
--     so the first patient comes the moment step 2 starts.
--   · Patience never runs out in steps 1-6 (Tutorial.calm): the ring stays full.
--   · Hooks: Tutorial.onFrontArrived when a patient reaches the front of the line, Tutorial.onTreated on a treat.
--
-- Movement: no Humanoids, no physics. A creature is one anchored Root with its parts welded on
-- (CreatureBuilder). Hops are tweens: TweenService:GetValue easing, stepped on one Heartbeat connection that
-- writes Root.CFrame (one replicated CFrame per moving creature; nothing while they stand still). Each patient
-- has one thread for its whole visit; the prompt and the patience tick only change its State.
--
-- For the client (read-only, the server sets them):
--   patient Model (in Plot.Patients): attributes PatientId, Kind ("Patient"|"Regular"|"Visitor"), Regular
--     (RegularId or nil), Ailment, Station, Item, Variant (nil = none), Night, QueueIndex (1 = front, 0 = out),
--     State ("Arriving"|"Waiting"|"Treated"|"Recovering"|"Cured"|"Sad"), PatienceFraction (0..1 in 0.05 steps, set
--     only when it changes: Feel/CreatureActing makes a patient wave, then bounce with a "!", as it runs low)
--   plot Model: attributes FrontItem and FrontStation, the ItemId / StationId the front patient needs while it
--     waits to be treated ("" otherwise). The Guide arrow can follow these.
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
local Prices = require(Shared.Logic.Prices)
local AilmentsData = require(Shared.Data.Ailments)
local ItemsData = require(Shared.Data.Items)
local PatientsData = require(Shared.Data.Patients)
local RegularsData = require(Shared.Data.Regulars)
local StationsData = require(Shared.Data.Stations)

local Carry = require(script.Parent.Carry)
local CreatureBuilder = require(script.Parent.CreatureBuilder)
local Cure = require(script.Parent.Cure)
local Daily = require(script.Parent.Daily)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)
local Story = require(script.Parent.Story)
local Tutorial = require(script.Parent.Tutorial)

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

-- Feel
local HOP_LENGTH = 3.6
local HOP_SECONDS = 0.3
local HOP_HEIGHT = 0.9
local LEAN = 0.14 -- radians forward at the top of a hop
local SHAKE_SECONDS = 0.55
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

type Anim = {
	From: CFrame,
	To: CFrame,
	Height: number,
	Start: number,
	Seconds: number,
	Spin: number,
	Lean: number,
}

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
	Station: string,
	Item: string,
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
	Anim: Anim?,
	ScaleAnim: ScaleAnim?,
	ShakeAt: number?,
	Tilt: number,
	Thread: thread?,
}

local active: { [Plot]: PlotState } = {}
local prompts: { [Plot]: ProximityPrompt } = {}
local animating: { [Patient]: boolean } = {}
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

-- Place `index` in line (1 = the front). The line grows away from the counter, Config.QueueSpacing apart. Once it
-- is Config.QueueDepth studs long it turns sideways (away from where patients arrive), so big creatures spaced
-- out still fit on the plot's path instead of spilling into the street.
local function queueSpot(plot: Plot, index: number): CFrame
	local start = markerGround(plot.QueueStart)
	local spacing = Config.QueueSpacing
	local straight = math.max(1, math.floor(Config.QueueDepth / spacing) + 1)
	if index <= straight then
		return start * CFrame.new(0, 0, (index - 1) * spacing)
	end
	local spawnMarker = plot.Spawn
	local arriveX = if spawnMarker then start:PointToObjectSpace(spawnMarker.Position).X else 0
	local side = if arriveX > 0 then -1 else 1
	return start * CFrame.new(side * (index - straight) * spacing, 0, (straight - 1) * spacing)
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
-- The animator: one Heartbeat steps every moving creature
------------------------------------------------------------------------------------------------------------------

local function render(p: Patient, now: number): boolean
	local busy = false
	local cf = p.Pivot
	local anim = p.Anim
	if anim then
		local t = (now - anim.Start) / anim.Seconds
		if t >= 1 then
			p.Pivot = anim.To
			p.Anim = nil
			cf = anim.To
		else
			busy = true
			local eased = TweenService:GetValue(t, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			local arc = 4 * t * (1 - t) -- 0 -> 1 -> 0: the bob of the hop
			cf = anim.From:Lerp(anim.To, eased)
				* CFrame.new(0, anim.Height * arc, 0)
				* CFrame.Angles(-anim.Lean * arc, anim.Spin * eased, 0)
		end
	end
	local shakeAt = p.ShakeAt
	if shakeAt then
		local t = (now - shakeAt) / SHAKE_SECONDS
		if t >= 1 then
			p.ShakeAt = nil
		else
			busy = true
			cf *= CFrame.Angles(0, math.sin(t * math.pi * 6) * 0.42 * (1 - t), 0) -- a "no, not that" head-shake
		end
	end
	if p.Tilt ~= 0 then
		cf *= CFrame.Angles(p.Tilt, 0, 0)
	end
	local scale = p.ScaleAnim
	if scale then
		local t = (now - scale.Start) / scale.Seconds
		local value = scale.To
		if t >= 1 then
			p.ScaleAnim = nil
		else
			busy = true
			value = scale.From + (scale.To - scale.From) * TweenService:GetValue(t, scale.Style, scale.Direction)
		end
		p.Model:ScaleTo(math.max(value, 0.02))
	end
	p.Root.CFrame = cf
	return busy
end

local function step()
	local now = os.clock()
	for p in animating do
		if p.State == "Gone" then
			animating[p] = nil
		else
			local ok, busy = pcall(render, p, now)
			if not ok then
				report("render", busy)
				animating[p] = nil
			elseif not busy then
				animating[p] = nil
			end
		end
	end
end

-- One hop to `to` (a resting pivot). Yields until it lands; false if the patient is gone by then.
local function hop(p: Patient, to: CFrame, height: number, seconds: number, spin: number?): boolean
	if not alive(p) then
		return false
	end
	local anim: Anim = {
		From = p.Pivot,
		To = to,
		Height = height,
		Start = os.clock(),
		Seconds = math.max(seconds, 0.15),
		Spin = spin or 0,
		Lean = if spin then 0 else LEAN,
	}
	p.Anim = anim
	animating[p] = true
	task.wait(anim.Seconds)
	if not alive(p) then
		return false
	end
	if p.Anim == anim then
		p.Anim = nil
	end
	p.Pivot = to
	animating[p] = true -- draw the landing pose (and any overlay still playing)
	return true
end

local function scaleTo(
	p: Patient,
	target: number,
	seconds: number,
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection
)
	p.ScaleAnim = {
		From = p.Model:GetScale(),
		To = target,
		Start = os.clock(),
		Seconds = seconds,
		Style = style,
		Direction = direction,
	}
	animating[p] = true
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

-- The prompt, its icon and the FrontItem attribute follow the patient at the front of the line.
local function refreshFront(state: PlotState)
	if active[state.Plot] ~= state then
		return
	end
	local front = state.Queue[1]
	local waiting = front ~= nil and front.State == "Queue" and front.Arrived
	local item, station, icon = "", "", ""
	if front and waiting then
		item, station, icon = front.Item, front.Station, front.AilmentIcon
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
		state.Plot.Model:SetAttribute("FrontItem", item)
		state.Plot.Model:SetAttribute("FrontStation", station)
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

local function freeBed(state: PlotState): BasePart?
	local rooms = state.Plot.Model:FindFirstChild("Rooms")
	if not rooms then
		return nil
	end
	local counter = state.Plot.Counter.Position
	local best: BasePart?, bestDistance = nil, math.huge
	for _, descendant in rooms:GetDescendants() do
		if descendant:IsA("BasePart") and string.match(descendant.Name, "^Bed_%d+$") and not state.Beds[descendant] then
			local distance = (descendant.Position - counter).Magnitude
			if distance < bestDistance then
				best, bestDistance = descendant, distance
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

local function removePatient(p: Patient)
	if p.State == "Gone" then
		return
	end
	local state = p.Plot
	removeFromQueue(state, p)
	releaseBed(state, p)
	p.State = "Gone"
	animating[p] = nil
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
	p.Badge.Bubble.Enabled = false
	showRing(p, 0, RING_LOW)
	CreatureBuilder.setMood(p.Model, "Sad")
	p.Tilt = -0.22
	animating[p] = true
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
			if now >= p.NextIdle then
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
	return base * (if guest then GUEST_PATIENCE else 1)
end

local function spawnPatient(state: PlotState, patientId: string, regular: string?, visitor: boolean, variant: string?)
	local entry = PatientsData[patientId]
	local regularEntry = if regular then RegularsData[regular] else nil
	local ailmentId = if regularEntry then regularEntry.Ailment elseif entry then entry.Ailment else nil
	local ailment = if ailmentId then AilmentsData[ailmentId] else nil
	local station = if ailment then StationsData[ailment.Station] else nil
	if not (ailment and station and ItemsData[station.Item]) then
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
		Anim = nil,
		ScaleAnim = nil,
		ShakeAt = nil,
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
	model:SetAttribute("Station", ailment.Station)
	model:SetAttribute("Item", station.Item)
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
	local isNight = Workspace:GetAttribute("IsNight") == true

	-- 0. The tutorial's own two patients (no variant: nothing to explain yet).
	if plan == "First" or plan == "Second" then
		local patientId = tutorialPatient(plan, stations, data)
		if plan == "Second" then
			state.SecondSpawned = true -- (a clinic without the 🩹 station skips it: the usual pool, below)
		end
		if patientId then
			spawnPatient(state, patientId, nil, false, nil)
			return
		end
	end
	local guests = plan == "Normal" -- regulars and Today's Visitor wait until the tutorial is done

	local function treatable(ailmentId: string): boolean
		local ailment = AilmentsData[ailmentId]
		return ailment ~= nil and stations[ailment.Station] == true
	end
	local function eligible(patientId: string): boolean
		local entry = PatientsData[patientId]
		if not entry or not treatable(entry.Ailment) then
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
			if not (entry and treatable(entry.Ailment)) then
				report("regular " .. regular, "named by Story but can't be treated here")
			elseif not hasGuest(state, regular, false) then -- (Story never names one who's already here)
				spawnPatient(state, entry.Patient, regular, false, nil)
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
				spawnPatient(state, visitor, nil, true, rollVariant())
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
	spawnPatient(state, chosen, nil, false, rollVariant())
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
	for index, p in state.Queue do
		if p.State == "Queue" and p.Arrived and not p.Claimed then
			local rate = if index == 1 then 1 else QUEUE_PATIENCE_RATE
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
	local maxQueue = if type(cap) == "number" then math.min(cap, Config.MaxQueue) else Config.MaxQueue
	if now >= state.NextSpawn and #state.Queue < maxQueue then
		local forced = table.remove(state.Forced, 1)
		if forced then
			-- An admin's pick (Patients.sendNext) comes first; more picks follow REFILL_SECONDS apart.
			state.NextSpawn = now
				+ (if #state.Forced > 0 then REFILL_SECONDS else Config.SpawnEverySeconds * rng:NextNumber(0.85, 1.15))
			spawnPatient(state, forced, nil, false, nil)
		else
			local plan = tutorialAsk("spawnPlan", "Normal", state.Owner, next(state.All) == nil, state.SecondSpawned)
			-- A spawn the tutorial holds back keeps its turn, so the patient comes the moment the tutorial is ready.
			if plan ~= "Wait" then
				state.NextSpawn = now + Config.SpawnEverySeconds * rng:NextNumber(0.85, 1.15)
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
	if not p or p.State ~= "Queue" or not p.Arrived or p.Claimed then
		return
	end

	p.Claimed = true
	local taken = takeItem(player, p.Item)
	p.Claimed = false
	if not taken then
		p.ShakeAt = os.clock()
		animating[p] = true
		local stationIcon = StationsData[p.Station].Icon
		local hint = if #carrying(player) == 0
			then "Make " .. stationIcon .. " first!"
			else "Oops! This one needs " .. stationIcon
		Remotes.toast(player, hint)
		return
	end
	if not (alive(p) and p.State == "Queue" and state.Queue[1] == p) then
		giveBack(player, p.Item) -- the patient moved on while we checked: keep your item
		return
	end
	beginTreatment(state, p, player)
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
		Loop = nil,
		SecondSpawned = false,
		Forced = {},
	}
	active[plot] = state
	plot.Model:SetAttribute("FrontItem", "")
	plot.Model:SetAttribute("FrontStation", "")
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
	if not stationsOnPlot(state.Plot)[ailment.Station] then
		return false, "🔒 Needs " .. station.Icon .. " first!"
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

function Patients.start()
	for _, plot in Plots.all() do
		ensurePrompt(plot)
	end
	RunService.Heartbeat:Connect(step)
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
