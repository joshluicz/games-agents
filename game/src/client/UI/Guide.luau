--!strict
-- Guide (build plan Task 6; look overhaul T8; the Real Clinic, Task 8): the two client helpers that live in the world
-- instead of on the HUD.
--   init(ctx)
--   Guide.visit(plot, data, carried): Visit   what the doctor should do next at that clinic (below; UI/Tutorial
--                                             reads it for its words)
--
-- 1. The first-patients guide. Until you've treated Config.Tutorial.ArrowsUntilCures patients (3; after a tutorial
--    Skip too, memory-20261117-003), it points where to go next, drawn by UI/Wayfinder (look build plan §B9): the
--    floor beam from your hips, the floor chevrons, the one glowing Highlight, the candy pin and, on touch, the hand by
--    the prompt. What it points at (the Real Clinic visit, design §5):
--      you carry something a bay patient still needs          -> that patient's ExamBay_<id> (the beam ends at its
--                                                                DoctorSpot; the item's icon, the tap hand: Treat)
--      else the FRONT bay patient (the one who has waited      -> its bay (🩺, the tap hand: Examine)
--      longest for the doctor, Logic/Visit.front) isn't
--      examined yet
--      else its first missing plan step                        -> that step's Station_<id> (the supply shelf, the
--                                                                dispensary's Station_Remedy, the Bath Room...; its
--                                                                icon, its colour, the hold hand)
--    Only on your own plot. Everything is client-only, survives respawn (Wayfinder.attach on CharacterAdded), and goes
--    for good once you reach the goal (Wayfinder.destroy: nothing loops after that). It looks again every
--    STEP_SECONDS while it shows (you walk, the patient moves); with nothing to show it rests until something it reads
--    changes (your plot, what you carry, your treated count, the snapshot, a patient arriving, leaving or changing
--    State / Bay / Case / PlanDone, Reduce Motion or the calm toggle) or IDLE_SECONDS pass. A player in the
--    first-session tutorial keeps it through the tutorial's step 6 (Snapshot.Tutorial) instead, and UI/Tutorial
--    steers it. A Replay (the tutorial running again) brings it back, even for a player who is long past 3.
--      Guide.setSteer(fn?)   fn(plot) returns nil (the usual target, above), false (nothing now), or a Steer (point
--                            there):
--      Steer = { Part: BasePart, Target: Instance?, Icon: string, Color: Color3, Height: number?, Beam: boolean?,
--                Glow: boolean?, Hand: ("Hold" | "Tap")?, Base: Vector3? }
--        Part    the pin's anchor (Height = the world Y of the pin's foot, default just above the part)
--        Target  what glows and where the beam ends (default Part): a patient Model, say
--        Beam / Glow / Hand / Base   as Wayfinder.Spec (Beam false: pin and glow only)
-- 2. Station hold time. Every station prompt's HoldDuration is set locally from Snapshot.MakeSeconds[StationId] (the
--    server's own hold time with every boost), or Logic/Prices.makeSeconds(Snapshot.Upgrades.Speed) without it, so the
--    ring matches your Faster Hands level and boosts. The server
--    sets the slowest time (Speed 0) and times each hold against the MAKER's own level (Stations), so this only
--    makes the ring honest. Prompts are found by the `StationPrompt` tag (Stations.PROMPT_TAG; Stations tags every
--    one it makes), so nothing here listens to every part added to the town.
--    Progression v2 (build plan §B8 Stations): each prompt's hold also follows ITS plot's attributes, the way the
--    server times it: the team bonus TeamMake ("Plaster=0.8,Cocoa=0.8") for that station, and an ability rush while
--    MakeRushUntil is ahead (x MakeRushFactor: Busy Paws 0.5, Time Bubble 0 = the shortest hold,
--    Config.BoostMinMakeSeconds), back to normal by itself when the rush ends (one timer per plot, no polling). The
--    dispensary (a Dispense station: Station_Remedy) keeps the server's own hold unless the Snapshot names one for it
--    (MakeSeconds.Remedy): Faster Hands is for supplies. The pure rules are the HOLD block (tests/Juice).
--
-- Reading patients (all set by the server's Patients module, read-only here), on each patient Model in
-- Plot_<n>.Patients: Bay (the exam bay it sits in, "" or nil before), State ("AtBay" and "Planned" wait for the
-- doctor; "Examining" and "Treating" have a session open), Case (set only by the exam), Plan (its ItemIds,
-- comma-joined) and PlanDone ("10": a "1" per step given), and QueueIndex (the server's front order among the bay
-- patients who need the doctor: 1 = the front, 0 = not now; a Since attribute, when a server sends one, wins; with
-- neither, the bays' order). Bays are `ExamBay_<id>` Models (with a DoctorSpot) in the plot's Building or Rooms;
-- stations are `Station_<id>` parts there.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Prices = require(Shared:WaitForChild("Logic"):WaitForChild("Prices"))
local TutorialLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Tutorial"))
local Visit = require(Shared:WaitForChild("Logic"):WaitForChild("Visit"))
local Theme = require(script.Parent.Theme)
local Wayfinder = require(script.Parent.Wayfinder)

local Guide = {}

export type Steer = {
	Part: BasePart,
	Target: Instance?,
	Icon: string,
	Color: Color3,
	Height: number?,
	Beam: boolean?,
	Glow: boolean?,
	Hand: ("Hold" | "Tap")?,
	Base: Vector3?,
}
local steerFn: ((plot: Instance) -> any)? = nil

function Guide.setSteer(fn: ((plot: Instance) -> any)?)
	steerFn = fn
end

local DEFAULT_UNTIL_CURED = 3 -- Config.Tutorial.ArrowsUntilCures when it's missing
local STEP_SECONDS = 0.2
local IDLE_SECONDS = 1 -- with nothing to show, look again after this at the latest
-- The patient attributes the guide reads (a change wakes it).
local PATIENT_ATTRIBUTES = { "State", "Bay", "Case", "Plan", "PlanDone", "QueueIndex" }

local function splitCarry(raw: any): { string }
	local items = {}
	if type(raw) == "string" then
		for id in string.gmatch(raw, "[^,]+") do
			table.insert(items, id)
		end
	end
	return items
end

------------------------------------------------------------------------------------------------------------------
-- Station hold time
------------------------------------------------------------------------------------------------------------------

local PROMPT_TAG = "StationPrompt" -- Stations.PROMPT_TAG (a server module, so not required here)

-- Progression v2 (build plan §B8 Stations, §C T8): the plot's own hold factors on top of your boosts. Pure (a scratch
-- harness, tests/Juice, loads the block between the markers on its own).
-- BEGIN HOLD
local Hold = {}

local function finiteNumber(value: any): number?
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return nil
end

-- The plot's TeamMake attribute ("Bath=0.8,Cocoa=0.8", Server/Nurses) as { [StationId]: factor }; only factors in
-- (0, 1] count (a team only ever shortens a hold), junk is skipped.
function Hold.teamMake(raw: any): { [string]: number }
	local out: { [string]: number } = {}
	if type(raw) ~= "string" then
		return out
	end
	for pair in string.gmatch(raw, "[^,]+") do
		local id, value = string.match(pair, "^%s*([%w_]+)%s*=%s*([%d%.]+)%s*$")
		local factor = if id then finiteNumber(tonumber(value)) else nil
		if id and factor and factor > 0 and factor <= 1 then
			out[id] = factor
		end
	end
	return out
end

-- A station's hold at a plot: `base` (your own: Snapshot.MakeSeconds) x the plot's team factor for that station x
-- an ability rush while it runs (MakeRushUntil > now: x MakeRushFactor, Busy Paws 0.5; 0 = Time Bubble, the
-- shortest hold), never below `floor` (Config.BoostMinMakeSeconds), never above `base`.
function Hold.seconds(
	base: number,
	stationId: string?,
	team: { [string]: number },
	rushUntil: any,
	rushFactor: any,
	now: number,
	floor: number
): number
	local seconds = math.max(finiteNumber(base) or 0, 0)
	local minimum = math.max(finiteNumber(floor) or 0, 0)
	if stationId and team[stationId] then
		seconds *= team[stationId]
	end
	local untilTime, factor = finiteNumber(rushUntil), finiteNumber(rushFactor)
	if untilTime and untilTime > (finiteNumber(now) or 0) and factor and factor >= 0 and factor < 1 then
		seconds = if factor == 0 then minimum else seconds * factor
	end
	return math.min(math.max(seconds, minimum), math.max(finiteNumber(base) or 0, minimum))
end
-- END HOLD

local function startHoldTimes(ctx: Types.Ctx)
	local seconds = Prices.makeSeconds(0, ctx.Config)
	-- Playtime branch: the server's own number per station (Snapshot.MakeSeconds: Faster Hands and every MakeSpeed
	-- boost), so the ring matches what Stations times. Without it, Faster Hands alone as before.
	local perStation: { [string]: number } = {}
	local floor = if type(ctx.Config.BoostMinMakeSeconds) == "number" then ctx.Config.BoostMinMakeSeconds else 0.3
	local prompts: { [ProximityPrompt]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local plotOf: { [ProximityPrompt]: Instance } = setmetatable({}, { __mode = "k" }) :: any
	local watchedPlots: { [Instance]: boolean } = {}
	local rushTimers: { [Instance]: thread } = {}

	-- The clinic plot a prompt sits on: the nearest ancestor Model with an OwnerUserId attribute.
	local function findPlot(prompt: Instance): Instance?
		local node = prompt.Parent
		while node and node ~= Workspace do
			if node:IsA("Model") and node:GetAttribute("OwnerUserId") ~= nil then
				return node
			end
			node = node.Parent
		end
		return nil
	end

	local stations = (ctx.Data :: any).Stations
	local function apply(prompt: ProximityPrompt)
		local stationId = prompt:GetAttribute("StationId")
		local id = if type(stationId) == "string" then stationId else nil
		-- The dispensary (Dispense): the server's own hold, unless the Snapshot names one for it.
		local station = if id and type(stations) == "table" then rawget(stations, id) else nil
		if type(station) == "table" and station.Dispense == true and not (id and perStation[id]) then
			return
		end
		local base = if id then perStation[id] or seconds else seconds
		local plot = plotOf[prompt]
		local wanted = base
		if plot then
			wanted = Hold.seconds(
				base,
				id,
				Hold.teamMake(plot:GetAttribute("TeamMake")),
				plot:GetAttribute("MakeRushUntil"),
				plot:GetAttribute("MakeRushFactor"),
				Workspace:GetServerTimeNow(),
				floor
			)
		end
		if math.abs(prompt.HoldDuration - wanted) > 0.001 then
			prompt.HoldDuration = wanted
		end
	end

	local function applyPlot(plot: Instance)
		for prompt in prompts do
			if plotOf[prompt] == plot then
				apply(prompt)
			end
		end
	end

	-- A rush ends at MakeRushUntil: put the plot's holds back then (one timer per plot, no polling).
	local function scheduleRushEnd(plot: Instance)
		local old = rushTimers[plot]
		if old then
			pcall(task.cancel, old)
			rushTimers[plot] = nil
		end
		local untilTime = plot:GetAttribute("MakeRushUntil")
		local left = if type(untilTime) == "number" then untilTime - Workspace:GetServerTimeNow() else 0
		if left > 0 and left < 600 then
			rushTimers[plot] = task.delay(left + 0.05, function()
				rushTimers[plot] = nil
				applyPlot(plot)
			end)
		end
	end

	local function watchPlot(plot: Instance)
		if watchedPlots[plot] then
			return
		end
		watchedPlots[plot] = true
		for _, attribute in { "TeamMake", "MakeRushUntil", "MakeRushFactor" } do
			plot:GetAttributeChangedSignal(attribute):Connect(function()
				applyPlot(plot)
				if attribute ~= "TeamMake" then
					scheduleRushEnd(plot)
				end
			end)
		end
		scheduleRushEnd(plot)
	end

	local function track(instance: Instance)
		if not instance:IsA("ProximityPrompt") or prompts[instance] then
			return
		end
		prompts[instance] = true
		local plot = findPlot(instance)
		if plot then
			plotOf[instance] = plot
			watchPlot(plot)
		end
		apply(instance)
		-- If the server changes it, put ours back: it follows your own Faster Hands level.
		instance:GetPropertyChangedSignal("HoldDuration"):Connect(function()
			apply(instance)
		end)
	end

	ctx.onState(function(state: Types.Snapshot)
		local level = (state.Upgrades or {}).Speed or 0
		seconds = Prices.makeSeconds(level, ctx.Config)
		local fromServer: { [string]: number } = {}
		if type(state.MakeSeconds) == "table" then
			for stationId, value in state.MakeSeconds do
				if type(stationId) == "string" and type(value) == "number" and value > 0 and value < 60 then
					fromServer[stationId] = value
				end
			end
		end
		perStation = fromServer
		for prompt in prompts do
			apply(prompt)
		end
	end)

	-- Tagged prompts (they also arrive later through streaming and new rooms).
	CollectionService:GetInstanceAddedSignal(PROMPT_TAG):Connect(track)
	for _, tagged in CollectionService:GetTagged(PROMPT_TAG) do
		track(tagged)
	end
end

------------------------------------------------------------------------------------------------------------------
-- The arrow
------------------------------------------------------------------------------------------------------------------

-- PURE-BEGIN
-- Reading a patient's visit from its attributes (no Roblox types): the HOLD block's neighbour, kept pure so the
-- rules read plainly. Each row is { Id: number, Bay: string, State: string?, Since: number?, Rank: number?, Plan:
-- string?, PlanDone: string?, Case: string? } (the patient's attributes, Rank = its QueueIndex: the server's front
-- order, 1 = the front, 0 = it doesn't need the doctor now; Id is the caller's own index).
local Pure = {}

-- Bay patients waiting for the doctor. A State the guide doesn't know (or none) counts as waiting, so a newer
-- server never hides the guide; "Examining"/"Treating" (a session is open) and every walking or leaving state don't.
Pure.WAITS = { AtBay = true, Planned = true } :: { [string]: boolean }
Pure.MOVES = {
	Arriving = true,
	Waiting = true, -- the waiting room
	ToBay = true,
	Examining = true,
	Treating = true,
	Done = true,
	ToWard = true,
	Recovering = true,
	Leaving = true,
	Sad = true,
} :: { [string]: boolean }

function Pure.needsDoctor(row: any): boolean
	if type(row) ~= "table" or type(row.Bay) ~= "string" or row.Bay == "" then
		return false
	end
	if type(row.Rank) == "number" and row.Rank <= 0 then
		return false -- the server says it doesn't need the doctor now (QueueIndex 0: a nurse is on it, say)
	end
	local state = row.State
	if type(state) ~= "string" or Pure.WAITS[state] then
		return true
	end
	return not Pure.MOVES[state]
end

-- "Plaster,Ice" -> { "Plaster", "Ice" }; anything else -> {}.
function Pure.split(text: any): { string }
	local out: { string } = {}
	if type(text) == "string" then
		for id in string.gmatch(text, "[^,%s]+") do
			table.insert(out, id)
		end
	end
	return out
end

-- The plan steps still to give, in order ("1" in PlanDone = given).
function Pure.missing(plan: any, planDone: any): { string }
	local out: { string } = {}
	local done = if type(planDone) == "string" then planDone else ""
	for index, itemId in Pure.split(plan) do
		if string.sub(done, index, index) ~= "1" then
			table.insert(out, itemId)
		end
	end
	return out
end

-- Examined: its case is known (Case), or it already has a plan.
function Pure.examined(row: any): boolean
	return type(row) == "table"
		and ((type(row.Case) == "string" and row.Case ~= "") or (type(row.Plan) == "string" and row.Plan ~= ""))
end

-- A bay id's sort key, so ties (or a server without Since) go by the bays' order: "1".."6", then "W1", "X".
function Pure.bayOrder(bay: any): number
	local n = if type(bay) == "string" then tonumber(bay) else nil
	if n then
		return n
	end
	return 100 + (if type(bay) == "string" then string.byte(bay, 1) or 0 else 0)
end

-- Who the doctor goes to next, and why: (rowId, "Treat" | "Examine" | "Fetch", itemId?).
--   · "Treat": you carry an item a waiting, examined patient still needs (the longest-waiting such one); itemId =
--     that item.
--   · Else the front patient (Logic/Visit.front: the longest-waiting one that needs the doctor): "Examine" before
--     its exam, else "Fetch" its first missing step (itemId).
-- nil when nobody needs the doctor. `front` is Logic/Visit.front.
function Pure.next(rows: { any }, carried: { string }, front: (rows: { any }) -> number?): (number?, string?, string?)
	local function since(row: any): number
		local value = row.Since
		if type(value) == "number" and value == value then
			return value
		end
		local rank = row.Rank
		if type(rank) == "number" and rank > 0 then
			return 1e9 + rank -- the server's own front order (QueueIndex: 1 = the front)
		end
		return 1e12 + Pure.bayOrder(row.Bay) -- neither: after anyone who has one, in the bays' order
	end
	local waiting = {}
	local carrying = {}
	local carryItem: { [number]: string } = {}
	for _, row in rows do
		if Pure.needsDoctor(row) then
			table.insert(waiting, { Id = row.Id, Since = since(row), NeedsDoctor = true })
			if Pure.examined(row) then
				for _, itemId in Pure.missing(row.Plan, row.PlanDone) do
					if table.find(carried, itemId) then
						table.insert(carrying, { Id = row.Id, Since = since(row), NeedsDoctor = true })
						carryItem[row.Id] = itemId
						break
					end
				end
			end
		end
	end
	local treat = front(carrying)
	if treat then
		return treat, "Treat", carryItem[treat]
	end
	local id = front(waiting)
	if not id then
		return nil, nil, nil
	end
	for _, row in rows do
		if row.Id == id then
			if not Pure.examined(row) then
				return id, "Examine", nil
			end
			local missing = Pure.missing(row.Plan, row.PlanDone)
			return id, "Fetch", missing[1]
		end
	end
	return nil, nil, nil
end
-- PURE-END
Guide.Pure = Pure

export type Visit = {
	Patient: Model?, -- the bay patient to go to; nil = nobody needs the doctor
	Bay: string?, -- its bay id ("1")
	BayModel: Instance?, -- ExamBay_<Bay>
	Spot: Instance?, -- its DoctorSpot (where the doctor stands; the BayPrompt)
	Do: ("Treat" | "Examine" | "Fetch")?,
	Item: string?, -- Treat: the carried item it needs; Fetch: its first missing step
	Station: string?, -- Fetch: the StationId of that step
	Case: string?, -- its case, once examined
}

local function findIn(plot: Instance, name: string): Instance?
	for _, holder in { "Building", "Rooms" } do
		local folder = plot:FindFirstChild(holder)
		local found = folder and folder:FindFirstChild(name, true)
		if found then
			return found
		end
	end
	return nil
end

local function stationPart(plot: Instance, stationId: string): BasePart?
	local found = findIn(plot, "Station_" .. stationId)
	if found and found:IsA("BasePart") then
		return found
	elseif found and found:IsA("Model") then -- a kit station built as a Model
		local main = found.PrimaryPart or found:FindFirstChildWhichIsA("BasePart", true)
		if main then
			return main
		end
	end
	return nil
end

-- What the doctor should do next at `plot` (see Pure.next): read off the patient models.
function Guide.visit(plot: Instance, data: any, carried: { string }): Visit
	local folder = plot:FindFirstChild("Patients")
	local models: { Model } = {}
	local rows = {}
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				table.insert(models, child)
				local row = { Id = #models }
				for _, name in PATIENT_ATTRIBUTES do
					row[name] = child:GetAttribute(name)
				end
				row.Since = child:GetAttribute("Since")
				row.Rank = child:GetAttribute("QueueIndex")
				table.insert(rows, row)
			end
		end
	end
	local id, todo, itemId = Pure.next(rows, carried, Visit.front)
	local patient = if id then models[id] else nil
	if not patient then
		return {}
	end
	local bay = patient:GetAttribute("Bay")
	local bayId = if type(bay) == "string" and bay ~= "" then bay else nil
	local bayModel = if bayId then findIn(plot, "ExamBay_" .. bayId) else nil
	local spot = if bayModel then bayModel:FindFirstChild("DoctorSpot", true) else nil
	local item = if itemId
			and type(data) == "table"
			and type(data.Items) == "table"
		then rawget(data.Items, itemId)
		else nil
	local case = patient:GetAttribute("Case")
	return {
		Patient = patient,
		Bay = bayId,
		BayModel = bayModel,
		Spot = spot,
		Do = todo :: any,
		Item = itemId,
		Station = if todo == "Fetch" and type(item) == "table" then item.Station else nil,
		Case = if type(case) == "string" and case ~= "" then case else nil,
	}
end

-- Where the beam ends for a bay: on the floor under its DoctorSpot (nil: Wayfinder works it out).
local function spotBase(spot: Instance?): Vector3?
	if spot and spot:IsA("BasePart") then
		return Vector3.new(spot.Position.X, spot.Position.Y - spot.Size.Y / 2, spot.Position.Z)
	elseif spot and spot:IsA("Attachment") then
		return spot.WorldPosition
	end
	return nil
end
Guide.spotBase = spotBase

-- A station's glowing target (a kit Model station glows whole) and its part (the pin's anchor).
local function stationTarget(plot: Instance, stationId: string): (Instance?, BasePart?)
	local part = stationPart(plot, stationId)
	if not part then
		return nil, nil
	end
	local model = part.Parent
	if model and model:IsA("Model") and model.Name == "Station_" .. stationId then
		return model, part
	end
	return part, part
end

-- A Steer table (from UI/Tutorial) as a Wayfinder spec; nil when it has no part.
local function specOf(wanted: any): Wayfinder.Spec?
	local part = wanted.Part
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return nil
	end
	local target = wanted.Target
	return {
		Target = if typeof(target) == "Instance" then target else part,
		Base = if typeof(wanted.Base) == "Vector3" then wanted.Base else nil,
		Icon = if type(wanted.Icon) == "string" then wanted.Icon else "👀",
		Color = if typeof(wanted.Color) == "Color3" then wanted.Color else Theme.Colors.Primary,
		Beam = if type(wanted.Beam) == "boolean" then wanted.Beam else nil,
		Glow = if type(wanted.Glow) == "boolean" then wanted.Glow else nil,
		Hand = if wanted.Hand == "Hold" or wanted.Hand == "Tap" then wanted.Hand else nil,
		Height = if type(wanted.Height) == "number" then wanted.Height else nil,
	}
end

local function startGuide(ctx: Types.Ctx)
	local data = ctx.Data :: any
	local player = ctx.Player
	local tuning = (ctx.Config :: any).Tutorial
	local untilCures = if type(tuning) == "table" and type(tuning.ArrowsUntilCures) == "number"
		then tuning.ArrowsUntilCures
		else DEFAULT_UNTIL_CURED

	local function done(): boolean
		local state = ctx.State
		local step = state.Tutorial
		if type(step) == "number" and step <= 0 then
			return false -- the client's default snapshot: the server's says whether the tutorial needs the guide
		end
		if TutorialLogic.active(step) then
			return step >= TutorialLogic.SHOP -- the tutorial uses it through step 6
		end
		local attribute = player:GetAttribute("Cured")
		if type(attribute) == "number" and attribute >= untilCures then
			return true
		end
		return (state.Cured or 0) >= untilCures
	end

	local running = false

	local function run()
		running = true
		local showing = false

		local function hide()
			if showing then
				showing = false
				Wayfinder.hide()
			end
		end

		local function show(spec: Wayfinder.Spec)
			showing = true
			Wayfinder.show(spec)
		end

		-- The beam starts at you; a new character gets a new start.
		local characterConnection = player.CharacterAdded:Connect(function(character: Model)
			Wayfinder.attach(character)
		end)
		if player.Character then
			Wayfinder.attach(player.Character)
		end

		local function step()
			local plotIndex = player:GetAttribute("PlotIndex")
			local clinics = Workspace:FindFirstChild("Clinics")
			local plot = if type(plotIndex) == "number" and clinics
				then clinics:FindFirstChild("Plot_" .. plotIndex)
				else nil
			if not plot then
				hide()
				return
			end
			-- The tutorial's say first: nothing right now, or a target of its own.
			local steer = steerFn
			if steer then
				local steerOk, wanted = pcall(steer, plot)
				if steerOk and wanted == false then
					hide()
					return
				elseif steerOk and type(wanted) == "table" then
					local spec = specOf(wanted)
					if spec then
						show(spec)
					else
						hide()
					end
					return
				end
			end
			-- The visit's next beat (Guide.visit): a bay to Examine or Treat at, or the station of the front patient's
			-- first missing step.
			local visit = Guide.visit(plot, data, splitCarry(player:GetAttribute("Carry")))
			if visit.Do == "Examine" or visit.Do == "Treat" then
				local target = visit.BayModel or visit.Patient
				if target then
					local item = if visit.Item then rawget(data.Items, visit.Item) else nil
					show({
						Target = target,
						Base = spotBase(visit.Spot),
						Icon = if visit.Do == "Examine" then "🩺" elseif item then item.Icon else "😊",
						Color = Theme.Colors.Collect,
						Hand = "Tap",
					})
					return
				end
			elseif visit.Do == "Fetch" and visit.Station then
				local station = rawget(data.Stations, visit.Station)
				local target = if station then stationTarget(plot, visit.Station) else nil
				if station and target then
					show({ Target = target, Icon = station.Icon, Color = station.Color, Hand = "Hold" })
					return
				end
			end
			hide()
		end

		-- Resting with nothing to show: the loop sleeps until something it reads changes (or IDLE_SECONDS pass).
		local waiting: thread? = nil
		local function wake()
			local thread = waiting
			if thread then
				waiting = nil
				task.spawn(thread)
			end
		end
		local function idle(seconds: number)
			waiting = coroutine.running()
			local timer = task.delay(seconds, wake)
			coroutine.yield()
			waiting = nil
			pcall(task.cancel, timer) -- woken early: the timer mustn't wake a later rest (fails harmlessly if it ran)
		end
		local wakers: { RBXScriptConnection } = {}
		for _, name in { "PlotIndex", "Carry", "Cured", "ReduceEffects" } do
			table.insert(wakers, player:GetAttributeChangedSignal(name):Connect(wake))
		end
		table.insert(wakers, GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(wake))
		local stopState = ctx.onState(function()
			wake()
		end)
		local watchedPlot: Instance? = nil
		local plotConnections: { RBXScriptConnection } = {}
		local function watchPlot()
			local plotIndex = player:GetAttribute("PlotIndex")
			local clinics = Workspace:FindFirstChild("Clinics")
			local plot = if type(plotIndex) == "number" and clinics
				then clinics:FindFirstChild("Plot_" .. plotIndex)
				else nil
			if plot ~= watchedPlot then
				watchedPlot = plot
				for _, connection in plotConnections do
					connection:Disconnect()
				end
				table.clear(plotConnections)
				local folder = if plot then plot:FindFirstChild("Patients") else nil
				if folder then
					-- A patient arriving, leaving or moving on (its State, Bay, Case, Plan, PlanDone) wakes it.
					local function follow(child: Instance)
						for _, name in PATIENT_ATTRIBUTES do
							table.insert(plotConnections, child:GetAttributeChangedSignal(name):Connect(wake))
						end
					end
					table.insert(
						plotConnections,
						folder.ChildAdded:Connect(function(child: Instance)
							follow(child)
							wake()
						end)
					)
					table.insert(plotConnections, folder.ChildRemoved:Connect(wake))
					for _, child in folder:GetChildren() do
						follow(child)
					end
				else
					watchedPlot = nil -- no Patients folder yet: look again next time
				end
			end
		end

		task.spawn(function()
			while not done() do
				local ok, err = pcall(function()
					watchPlot()
					step()
				end)
				if not ok then
					warn("[Guide] " .. tostring(err))
					hide()
				end
				if showing then
					task.wait(STEP_SECONDS)
				else
					idle(IDLE_SECONDS)
				end
			end
			-- Goal reached: clean up for good (Wayfinder deletes the Highlight and everything it made).
			characterConnection:Disconnect()
			for _, connection in wakers do
				connection:Disconnect()
			end
			stopState()
			for _, connection in plotConnections do
				connection:Disconnect()
			end
			Wayfinder.destroy()
			running = false
		end)
	end

	-- It starts now, and again whenever the guide is needed once more (a Replay sends the tutorial back to card 1).
	ctx.onState(function()
		if not running and not done() then
			run()
		end
	end)
end

function Guide.init(ctx: Types.Ctx)
	startHoldTimes(ctx)
	startGuide(ctx)
end

return Guide
