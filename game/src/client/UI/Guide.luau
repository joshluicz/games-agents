--!strict
-- Guide (build plan Task 6; look overhaul T8): the two client helpers that live in the world instead of on the HUD.
--   init(ctx)
--
-- 1. The first-cures guide. Until you've cured Config.Tutorial.ArrowsUntilCures patients (3; after a tutorial Skip
--    too, memory-20261117-003), it points where to go next, drawn by UI/Wayfinder (look build plan §B9): the floor
--    beam from your hips, the floor chevrons, the one glowing Highlight, the candy pin and, on touch, the hand by the
--    prompt. Its old overhead arc is gone. What it points at:
--      the front patient waits and you don't carry its treatment  -> the matching Station_* (its icon, its colour,
--                                                                   the hold hand)
--      you carry the right item (any item in the plot's FrontNeeds) -> the Counter (the patient's ailment icon, the
--                                                                   tap hand)
--    Only on your own plot. Everything is client-only, survives respawn (Wayfinder.attach on CharacterAdded), and goes
--    for good once you reach the goal (Wayfinder.destroy: nothing loops after that). It looks again every
--    STEP_SECONDS while it shows (you walk, the patient hops); with nothing to show it rests until something it reads
--    changes (your plot, what you carry, your cures, the snapshot, the plot's FrontStation/FrontNeeds, Reduce Motion
--    or the calm toggle) or IDLE_SECONDS pass. A player in the first-session tutorial keeps it through the tutorial's
--    step 6 (Snapshot.Tutorial) instead, and UI/Tutorial steers it. A Replay (the tutorial running again) brings it
--    back, even for a player who is long past 3 cures.
--      Guide.setSteer(fn?)   fn(plot) returns nil (the usual target: station, then Counter), false (nothing now), or
--                            a Steer (point there):
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
--    server times it: the team bonus TeamMake ("Bath=0.8,Cocoa=0.8") for that station, and an ability rush while
--    MakeRushUntil is ahead (x MakeRushFactor: Busy Paws 0.5, Time Bubble 0 = the shortest hold,
--    Config.BoostMinMakeSeconds), back to normal by itself when the rush ends (one timer per plot, no polling). The
--    💊 Pharmacy holds for the Snapshot's MakeSeconds.Pharmacy (Server/Boosts: Config.Pharmacy.HoldSeconds, x
--    Tier2Factor from R2, then MakeSpeed) instead of Faster Hands' time; before the first snapshot, its base hold
--    (Hold.pharmacy). The pure rules are the HOLD block, tests/Juice.
--
-- Reading patients (all set by the server's Patients module, read-only here): the plot's FrontStation attribute
-- (the StationId of the front patient's first missing item while it waits, "" otherwise) and FrontNeeds (every
-- item it still needs, comma-joined), and on each patient Model in
-- Plot_<n>.Patients: PatientId, Ailment, QueueIndex (1 = front) and State ("Waiting" = can be treated). Without
-- them it falls back to the model's name as the PatientId and the patient standing nearest QueueStart.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Prices = require(Shared:WaitForChild("Logic"):WaitForChild("Prices"))
local TutorialLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Tutorial"))
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
local FRONT_STUDS = 8 -- fallback: a patient this close to QueueStart counts as the front one

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

-- The 💊 Pharmacy's own base hold (Config.Pharmacy: HoldSeconds, x Tier2Factor from R2), not Faster Hands'.
function Hold.pharmacy(cfg: any, rebirths: any): number
	local pharmacy = if type(cfg) == "table" and type(cfg.Pharmacy) == "table" then cfg.Pharmacy else {}
	local base = finiteNumber(pharmacy.HoldSeconds) or 3
	local tier2 = finiteNumber(pharmacy.Tier2Factor) or 1
	local count = finiteNumber(rebirths) or 0
	return if count >= 2 and tier2 > 0 and tier2 <= 1 then base * tier2 else base
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
	local rebirths = 0
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

	local function apply(prompt: ProximityPrompt)
		local stationId = prompt:GetAttribute("StationId")
		local id = if type(stationId) == "string" then stationId else nil
		-- The 💊 Pharmacy: the Snapshot's own number (Server/Boosts.makeSeconds: its hold, x Tier2Factor from R2,
		-- then MakeSpeed), else its base hold before the first snapshot.
		local base = if id == "Pharmacy"
			then perStation.Pharmacy or Hold.pharmacy(ctx.Config, rebirths)
			elseif id then perStation[id] or seconds
			else seconds
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
		local rebirth = (state :: any).Rebirth
		rebirths = if type(rebirth) == "table" and type(rebirth.Count) == "number" then rebirth.Count else 0
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

-- The patient at the front of the line who is waiting to be treated (QueueIndex 1, State "Waiting"), or, for
-- models without those attributes, the one standing nearest QueueStart.
local function frontPatient(plot: Instance): Model?
	local folder = plot:FindFirstChild("Patients")
	if not folder then
		return nil
	end
	local queueStart = plot:FindFirstChild("QueueStart")
	local best: Model? = nil
	local bestDistance = math.huge
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			local queueIndex = child:GetAttribute("QueueIndex")
			local state = child:GetAttribute("State")
			local busy = type(state) == "string" and state ~= "Waiting"
			if type(queueIndex) == "number" then
				if queueIndex == 1 and not busy then
					return child
				end
			elseif not busy and queueStart and queueStart:IsA("BasePart") then
				local distance = (child:GetPivot().Position - queueStart.Position).Magnitude
				if distance < FRONT_STUDS and distance < bestDistance then
					best, bestDistance = child, distance
				end
			end
		end
	end
	return best
end

local function ailmentOf(data: any, patient: Model): string?
	local ailment = patient:GetAttribute("Ailment")
	if type(ailment) == "string" and rawget(data.Ailments, ailment) then
		return ailment
	end
	local id = patient:GetAttribute("PatientId")
	local patientId = if type(id) == "string" then id else patient.Name
	local entry = rawget(data.Patients, patientId) or rawget(data.Regulars, patientId)
	return if type(entry) == "table" then entry.Ailment else nil
end

local function stationPart(plot: Instance, stationId: string): BasePart?
	local rooms = plot:FindFirstChild("Rooms")
	if not rooms then
		return nil
	end
	for _, room in rooms:GetChildren() do
		local found = room:FindFirstChild("Station_" .. stationId, true)
		if found and found:IsA("BasePart") then
			return found
		elseif found and found:IsA("Model") then -- a kit station built as a Model
			local main = found.PrimaryPart or found:FindFirstChildWhichIsA("BasePart", true)
			if main then
				return main
			end
		end
	end
	return nil
end

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
			-- What the front patient needs. Patients publishes it on the plot (FrontStation, "" when nobody waits);
			-- the patient models are the fallback.
			local patient = frontPatient(plot)
			local ailmentId = patient and ailmentOf(data, patient)
			local ailment = ailmentId and rawget(data.Ailments, ailmentId)
			local frontStation = plot:GetAttribute("FrontStation")
			local stationId: string? = if type(frontStation) == "string"
				then (if frontStation ~= "" then frontStation else nil)
				else ailment and ailment.Station
			local station = stationId and rawget(data.Stations, stationId)
			if not stationId or not station then
				hide()
				return
			end
			-- Carrying any item the front patient still needs (FrontNeeds: a later recipe item counts too, Treat takes
			-- it) means the Counter is next.
			local carried = splitCarry(player:GetAttribute("Carry"))
			local carrying = table.find(carried, station.Item) ~= nil
			local frontNeeds = plot:GetAttribute("FrontNeeds")
			if not carrying and type(frontNeeds) == "string" then
				for itemId in string.gmatch(frontNeeds, "[^,]+") do
					if table.find(carried, itemId) then
						carrying = true
						break
					end
				end
			end
			if carrying then
				local counter = plot:FindFirstChild("Counter")
				if counter and counter:IsA("BasePart") then
					show({
						Target = counter,
						Icon = if ailment then ailment.Icon else "😊",
						Color = Theme.Colors.Collect,
						Hand = "Tap",
					})
					return
				end
			else
				local target = stationTarget(plot, stationId)
				if target then
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
				if plot then
					for _, name in { "FrontStation", "FrontNeeds" } do
						table.insert(plotConnections, plot:GetAttributeChangedSignal(name):Connect(wake))
					end
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
