--!strict
-- Guide (build plan Task 6): the two client helpers that live in the world instead of on the HUD.
--   init(ctx)
--
-- 1. The first-cures arrow. While you've cured fewer than GUIDE_UNTIL_CURED patients, a glowing arc with a dark
--    outline runs from you to where to go next, with a bouncing candy map pin over it (a disc in the target's
--    colour, a thick dark outline, a white middle with the icon). The bounce stops while Hud.calm():
--      the front patient waits and you don't carry its treatment  -> the matching Station_* (its icon, its colour)
--      you carry the right item (any item in the plot's FrontNeeds) -> the Counter (the patient's ailment icon)
--    Only on your own plot. It is all local (a client-only Part, Beam and BillboardGui), survives respawn, and
--    removes itself for good once you reach the goal. It looks again every STEP_SECONDS while it shows (you walk,
--    the patient hops); with nothing to show it rests (the pin's bounce paused) until something it reads changes
--    (your plot, what you carry, your cures, the snapshot, the plot's FrontStation/FrontNeeds) or IDLE_SECONDS pass. A player
--    in the first-session tutorial keeps it through
--    the tutorial's step 6 (Snapshot.Tutorial) instead, and UI/Tutorial steers it (Guide.setSteer):
--      Guide.setSteer(fn?)   fn(plot) returns nil (the usual arrow: station, then Counter), false (no arrow now),
--                            or { Part: BasePart, Icon: string, Color: Color3, Height: number? } (point there;
--                            Height = the world Y of the pin's foot, default just above the part)
-- 2. Station hold time. Every station prompt's HoldDuration is set locally from Snapshot.MakeSeconds[StationId] (the
--    server's own hold time with every boost), or Logic/Prices.makeSeconds(Snapshot.Upgrades.Speed) without it, so the
--    ring matches your Faster Hands level and boosts. The server
--    sets the slowest time (Speed 0) and times each hold against the MAKER's own level (Stations), so this only
--    makes the ring honest. Prompts are found by the `StationPrompt` tag (Stations.PROMPT_TAG; Stations tags every
--    one it makes), so nothing here listens to every part added to the town.
--
-- Reading patients (all set by the server's Patients module, read-only here): the plot's FrontStation attribute
-- (the StationId of the front patient's first missing item while it waits, "" otherwise) and FrontNeeds (every
-- item it still needs, comma-joined), and on each patient Model in
-- Plot_<n>.Patients: PatientId, Ailment, QueueIndex (1 = front) and State ("Waiting" = can be treated). Without
-- them it falls back to the model's name as the PatientId and the patient standing nearest QueueStart.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local Prices = require(Shared:WaitForChild("Logic"):WaitForChild("Prices"))
local TutorialLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Tutorial"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Guide = {}

export type Steer = { Part: BasePart, Icon: string, Color: Color3, Height: number? }
local steerFn: ((plot: Instance) -> any)? = nil

function Guide.setSteer(fn: ((plot: Instance) -> any)?)
	steerFn = fn
end

local GUIDE_UNTIL_CURED = 3
local STEP_SECONDS = 0.2
local IDLE_SECONDS = 1 -- with nothing to show, look again after this at the latest
local NEAR_STUDS = 8 -- closer than this, the arc hides (you're there) but the bubble stays
local FRONT_STUDS = 8 -- fallback: a patient this close to QueueStart counts as the front one
local UP = CFrame.Angles(0, 0, math.pi / 2) -- turns an Attachment's axis (X) to point up, so the arc bows upward
local REST_OFFSET = Vector3.new(0, 3, 0) -- the pin's height over the target
local BOUNCE_OFFSET = Vector3.new(0, 3.8, 0)
local ARC_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.85),
	NumberSequenceKeypoint.new(0.25, 0.3),
	NumberSequenceKeypoint.new(1, 0.05),
})

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

local function startHoldTimes(ctx: Types.Ctx)
	local seconds = Prices.makeSeconds(0, ctx.Config)
	-- Playtime branch: the server's own number per station (Snapshot.MakeSeconds: Faster Hands and every MakeSpeed
	-- boost), so the ring matches what Stations times. Without it, Faster Hands alone as before.
	local perStation: { [string]: number } = {}
	local prompts: { [ProximityPrompt]: boolean } = setmetatable({}, { __mode = "k" }) :: any

	local function apply(prompt: ProximityPrompt)
		local stationId = prompt:GetAttribute("StationId")
		local wanted = if type(stationId) == "string" then perStation[stationId] or seconds else seconds
		if math.abs(prompt.HoldDuration - wanted) > 0.001 then
			prompt.HoldDuration = wanted
		end
	end

	local function track(instance: Instance)
		if not instance:IsA("ProximityPrompt") or prompts[instance] then
			return
		end
		prompts[instance] = true
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

local function startArrow(ctx: Types.Ctx)
	local data = ctx.Data :: any
	local player = ctx.Player

	local function done(): boolean
		local state = ctx.State
		local step = state.Tutorial
		if type(step) == "number" and step <= 0 then
			return false -- the client's default snapshot: the server's says whether the tutorial needs the arrow
		end
		if TutorialLogic.active(step) then
			return step >= TutorialLogic.SHOP -- the tutorial uses it through step 6
		end
		local attribute = player:GetAttribute("Cured")
		if type(attribute) == "number" and attribute >= GUIDE_UNTIL_CURED then
			return true
		end
		return (state.Cured or 0) >= GUIDE_UNTIL_CURED
	end
	if done() then
		return
	end

	-- Client-only pieces: a marker Part with the arc's end and the bubble.
	local marker = Instance.new("Part")
	marker.Name = "ClinicGuide"
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.CastShadow = false
	marker.Transparency = 1
	marker.Size = Vector3.one * 0.2
	local target = Instance.new("Attachment")
	target.Name = "End"
	target.CFrame = UP
	target.Parent = marker

	-- The arc: a saturated beam in the target's colour, over a wider dark one that reads as its outline.
	local function arcBeam(name: string, width0: number, width1: number, emission: number): Beam
		local arc = Instance.new("Beam")
		arc.Name = name
		arc.Attachment1 = target
		arc.FaceCamera = true
		arc.Segments = 24
		arc.Width0 = width0
		arc.Width1 = width1
		arc.CurveSize0 = 5
		arc.CurveSize1 = -5
		arc.LightEmission = emission
		arc.LightInfluence = 0
		arc.Transparency = ARC_FADE
		arc.Enabled = false
		arc.Parent = marker
		return arc
	end
	local edge = arcBeam("ArcOutline", 0.8, 1.75, 0)
	edge.Color = ColorSequence.new(Theme.Colors.Outline)
	local beam = arcBeam("Arc", 0.5, 1.3, 0.3)
	pcall(function()
		beam.ZOffset = 0.1 -- draw the colour in front of its outline
	end)
	local function setArc(on: boolean)
		beam.Enabled = on
		edge.Enabled = on
	end

	local bubble = Instance.new("BillboardGui")
	bubble.Name = "Bubble"
	bubble.Adornee = marker
	bubble.AlwaysOnTop = true
	bubble.LightInfluence = 0
	bubble.MaxDistance = 250
	bubble.Size = UDim2.fromOffset(84, 118)
	bubble.StudsOffset = REST_OFFSET
	bubble.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	bubble.Enabled = false
	bubble.Parent = marker
	-- The pin: a round disc on a point. It pops from its tip (AnchorPoint at the bottom).
	local pin = Instance.new("Frame")
	pin.Name = "Pin"
	pin.AnchorPoint = Vector2.new(0.5, 1)
	pin.Position = UDim2.fromScale(0.5, 1)
	pin.Size = UDim2.fromScale(1, 1)
	pin.BackgroundTransparency = 1
	pin.Parent = bubble
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = pin
	-- The point: a square turned 45° whose lower sides just touch the disc, so the two read as one pin shape.
	local down = Instance.new("Frame")
	down.Name = "Down"
	down.AnchorPoint = Vector2.new(0.5, 0.5)
	down.Position = UDim2.new(0.5, 0, 0, 79)
	down.Size = UDim2.fromOffset(38, 38)
	down.Rotation = 45
	down.BorderSizePixel = 0
	down.ZIndex = 1
	Kit.corner(down, 6)
	Kit.stroke(down, Theme.Colors.Outline, Theme.Size.StrokeLarge)
	down.Parent = pin
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0.5, 0)
	disc.Position = UDim2.new(0.5, 0, 0, 14)
	disc.Size = UDim2.fromOffset(76, 76)
	disc.BorderSizePixel = 0
	disc.ZIndex = 2
	Kit.corner(disc, 38)
	Kit.stroke(disc, Theme.Colors.Outline, Theme.Size.StrokeLarge)
	Palette.candyGradient(disc)
	disc.Parent = pin
	local middle = Instance.new("Frame")
	middle.Name = "Middle"
	middle.AnchorPoint = Vector2.new(0.5, 0.5)
	middle.Position = UDim2.fromScale(0.5, 0.5)
	middle.Size = UDim2.fromScale(0.7, 0.7)
	middle.BackgroundColor3 = Palette.White
	middle.BorderSizePixel = 0
	Kit.corner(middle, 27)
	Kit.stroke(middle, Theme.Colors.Outline, Theme.Size.Stroke)
	middle.Parent = disc
	local icon = Kit.label({
		Name = "Icon",
		Text = "",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.78, 0.78),
		Parent = middle,
	})
	local function paintPin(color: Color3)
		local fill = Kit.lighten(color, 0.08)
		disc.BackgroundColor3 = fill
		down.BackgroundColor3 = Kit.shade(fill, 0.13) -- matches the bottom of the disc's gradient
	end
	paintPin(Theme.Colors.Primary)
	marker.Parent = Workspace

	-- The bob follows the calm setting live: it stops (and rests) as soon as Hud.calm() turns on. It only plays
	-- while the pin shows (a hidden pin's endless tween would still run every frame).
	local bounce: Tween? = nil
	local function playBounce()
		local current = bounce
		if current then
			if bubble.Enabled then
				if current.PlaybackState ~= Enum.PlaybackState.Playing then
					current:Play()
				end
			elseif current.PlaybackState == Enum.PlaybackState.Playing then
				current:Pause()
			end
		end
	end
	local function syncBounce()
		local still = Hud.calm()
		if still and bounce then
			bounce:Cancel()
			bounce = nil
			bubble.StudsOffset = REST_OFFSET
		elseif not still and not bounce then
			bubble.StudsOffset = REST_OFFSET
			bounce = TweenService:Create(
				bubble,
				TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ StudsOffset = BOUNCE_OFFSET }
			)
			playBounce()
		end
	end
	syncBounce()
	local calmConnection = player:GetAttributeChangedSignal("ReduceEffects"):Connect(syncBounce)

	-- The arc starts at you; a new character gets a new start.
	local start: Attachment? = nil
	local function onCharacter(character: Model)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root and root:IsA("BasePart") and marker.Parent then
			local attachment = Instance.new("Attachment")
			attachment.Name = "ClinicGuideStart"
			attachment.CFrame = UP
			attachment.Parent = root
			start = attachment
			beam.Attachment0 = attachment
			edge.Attachment0 = attachment
		end
	end
	local characterConnection = player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	local shownKey = ""
	local function hide()
		setArc(false)
		bubble.Enabled = false
		shownKey = ""
		playBounce()
	end

	local function show(part: BasePart, iconText: string, color: Color3, height: number?)
		local key = part:GetFullName() .. iconText
		local position = part.Position
		marker.CFrame = CFrame.new(position.X, height or (position.Y + part.Size.Y / 2 + 0.3), position.Z)
		if key ~= shownKey then
			shownKey = key
			icon.Text = iconText
			paintPin(color)
			beam.Color = ColorSequence.new(color)
			if Hud.calm() then
				pop.Scale = 1
			else
				pop.Scale = 0.5
				TweenService:Create(pop, Theme.Tween.Bump, { Scale = 1 }):Play()
			end
		end
		bubble.Enabled = true
		playBounce()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local near = root ~= nil and root:IsA("BasePart") and (root.Position - part.Position).Magnitude < NEAR_STUDS
		setArc(start ~= nil and start.Parent ~= nil and not near)
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
		-- The tutorial's say first: no arrow right now, or a target of its own.
		local steer = steerFn
		if steer then
			local steerOk, wanted = pcall(steer, plot)
			if steerOk and wanted == false then
				hide()
				return
			elseif steerOk and type(wanted) == "table" then
				local part = wanted.Part
				if typeof(part) == "Instance" and part:IsA("BasePart") then
					show(
						part,
						if type(wanted.Icon) == "string" then wanted.Icon else "👀",
						if typeof(wanted.Color) == "Color3" then wanted.Color else Theme.Colors.Primary,
						if type(wanted.Height) == "number" then wanted.Height else nil
					)
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
		-- Carrying any item the front patient still needs (FrontNeeds: a later recipe item counts too, Treat takes it)
		-- means the Counter is next.
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
				show(counter, if ailment then ailment.Icon else "😊", Theme.Colors.Good)
				return
			end
		else
			local part = stationPart(plot, stationId)
			if part then
				show(part, station.Icon, station.Color)
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
	for _, name in { "PlotIndex", "Carry", "Cured" } do
		table.insert(wakers, player:GetAttributeChangedSignal(name):Connect(wake))
	end
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
			if bubble.Enabled then
				task.wait(STEP_SECONDS)
			else
				idle(IDLE_SECONDS)
			end
		end
		-- Goal reached: clean up for good.
		characterConnection:Disconnect()
		calmConnection:Disconnect()
		for _, connection in wakers do
			connection:Disconnect()
		end
		stopState()
		for _, connection in plotConnections do
			connection:Disconnect()
		end
		if bounce then
			bounce:Cancel()
		end
		if start then
			start:Destroy()
		end
		marker:Destroy()
	end)
end

function Guide.init(ctx: Types.Ctx)
	startHoldTimes(ctx)
	startArrow(ctx)
end

return Guide
