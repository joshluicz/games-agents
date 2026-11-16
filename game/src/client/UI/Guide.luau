--!strict
-- Guide (build plan Task 6): the two client helpers that live in the world instead of on the HUD.
--   init(ctx)
--
-- 1. The first-cures arrow. While you've cured fewer than GUIDE_UNTIL_CURED patients, a glowing arc runs from
--    you to where to go next, with a bouncing bubble over it:
--      the front patient waits and you don't carry its treatment  -> the matching Station_* (its icon, its colour)
--      you carry the right item                                    -> the Counter (the patient's ailment icon)
--    Only on your own plot. It is all local (a client-only Part, Beam and BillboardGui), survives respawn, and
--    removes itself for good once you reach the goal.
-- 2. Station hold time. Every station prompt's HoldDuration is set locally from
--    Logic/Prices.makeSeconds(Snapshot.Upgrades.Speed), so the ring matches your Faster Hands level. The server
--    sets the slowest time (Speed 0) and times each hold against the MAKER's own level (Stations), so this only
--    makes the ring honest. Prompts are found by the `StationPrompt` tag (Stations.PROMPT_TAG), with any prompt
--    under a `Station_*` part inside Workspace.Clinics as a fallback.
--
-- Reading patients (all set by the server's Patients module, read-only here): the plot's FrontStation attribute
-- (the StationId the front patient needs while it waits, "" otherwise), and on each patient Model in
-- Plot_<n>.Patients: PatientId, Ailment, QueueIndex (1 = front) and State ("Waiting" = can be treated). Without
-- them it falls back to the model's name as the PatientId and the patient standing nearest QueueStart.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Prices = require(Shared:WaitForChild("Logic"):WaitForChild("Prices"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Guide = {}

local GUIDE_UNTIL_CURED = 3
local STEP_SECONDS = 0.2
local NEAR_STUDS = 8 -- closer than this, the arc hides (you're there) but the bubble stays
local FRONT_STUDS = 8 -- fallback: a patient this close to QueueStart counts as the front one
local UP = CFrame.Angles(0, 0, math.pi / 2) -- turns an Attachment's axis (X) to point up, so the arc bows upward

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

local function isStationPrompt(prompt: ProximityPrompt): boolean
	if CollectionService:HasTag(prompt, PROMPT_TAG) then
		return true
	end
	local node: Instance? = prompt.Parent
	for _ = 1, 3 do
		if not node then
			return false
		end
		if string.sub(node.Name, 1, 8) == "Station_" then
			return true
		end
		node = node.Parent
	end
	return false
end

local function startHoldTimes(ctx: Types.Ctx)
	local seconds = Prices.makeSeconds(0, ctx.Config)
	local prompts: { [ProximityPrompt]: boolean } = setmetatable({}, { __mode = "k" }) :: any

	local function apply(prompt: ProximityPrompt)
		if math.abs(prompt.HoldDuration - seconds) > 0.001 then
			prompt.HoldDuration = seconds
		end
	end

	local function track(instance: Instance)
		if not instance:IsA("ProximityPrompt") or prompts[instance] or not isStationPrompt(instance) then
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
		local wanted = Prices.makeSeconds(level, ctx.Config)
		if wanted ~= seconds then
			seconds = wanted
			for prompt in prompts do
				apply(prompt)
			end
		end
	end)

	-- Tagged prompts (they also arrive later through streaming and new rooms) ...
	CollectionService:GetInstanceAddedSignal(PROMPT_TAG):Connect(track)
	for _, tagged in CollectionService:GetTagged(PROMPT_TAG) do
		track(tagged)
	end
	-- ... and, as a fallback, any prompt under a Station_* part in the town.
	task.spawn(function()
		local clinics = Workspace:WaitForChild("Clinics")
		clinics.DescendantAdded:Connect(track)
		for _, descendant in clinics:GetDescendants() do
			track(descendant)
		end
	end)
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
	local initial = ctx.State

	local function done(): boolean
		local attribute = player:GetAttribute("Cured")
		if type(attribute) == "number" and attribute >= GUIDE_UNTIL_CURED then
			return true
		end
		return ctx.State ~= initial and (ctx.State.Cured or 0) >= GUIDE_UNTIL_CURED
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

	local beam = Instance.new("Beam")
	beam.Name = "Arc"
	beam.Attachment1 = target
	beam.FaceCamera = true
	beam.Segments = 24
	beam.Width0 = 0.5
	beam.Width1 = 1.3
	beam.CurveSize0 = 5
	beam.CurveSize1 = -5
	beam.LightEmission = 0.7
	beam.LightInfluence = 0
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85),
		NumberSequenceKeypoint.new(0.25, 0.3),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	beam.Enabled = false
	beam.Parent = marker

	local bubble = Instance.new("BillboardGui")
	bubble.Name = "Bubble"
	bubble.Adornee = marker
	bubble.AlwaysOnTop = true
	bubble.LightInfluence = 0
	bubble.MaxDistance = 250
	bubble.Size = UDim2.fromOffset(84, 118)
	bubble.StudsOffset = Vector3.new(0, 3, 0)
	bubble.Enabled = false
	bubble.Parent = marker
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0.5, 0)
	disc.Position = UDim2.fromScale(0.5, 0)
	disc.Size = UDim2.fromOffset(76, 76)
	disc.BackgroundColor3 = Theme.Colors.Card
	disc.BorderSizePixel = 0
	Kit.corner(disc, 38)
	local discStroke = Kit.stroke(disc, Theme.Colors.Primary, 5)
	disc.Parent = bubble
	local icon = Kit.label({
		Name = "Icon",
		Text = "",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.7),
		Parent = disc,
	})
	Kit.label({
		Name = "Down",
		Text = "👇",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(40, 40),
		Parent = bubble,
	})
	marker.Parent = Workspace

	local bounce: Tween? = nil
	if not Hud.calm() then
		bounce = TweenService:Create(
			bubble,
			TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ StudsOffset = Vector3.new(0, 3.8, 0) }
		)
		bounce:Play()
	end

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
		end
	end
	local characterConnection = player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	local shownKey = ""
	local function hide()
		beam.Enabled = false
		bubble.Enabled = false
		shownKey = ""
	end

	local function show(part: BasePart, iconText: string, color: Color3)
		local key = part:GetFullName() .. iconText
		marker.CFrame = CFrame.new(part.Position + Vector3.new(0, part.Size.Y / 2 + 0.3, 0))
		if key ~= shownKey then
			shownKey = key
			icon.Text = iconText
			discStroke.Color = color
			beam.Color = ColorSequence.new(color)
			local scale = disc:FindFirstChild("Pop") :: UIScale?
			if not scale then
				local created = Instance.new("UIScale")
				created.Name = "Pop"
				created.Parent = disc
				scale = created
			end
			if scale and not Hud.calm() then
				scale.Scale = 0.5
				TweenService:Create(scale, Theme.Tween.PopIn, { Scale = 1 }):Play()
			end
		end
		bubble.Enabled = true
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local near = root ~= nil and root:IsA("BasePart") and (root.Position - part.Position).Magnitude < NEAR_STUDS
		beam.Enabled = start ~= nil and start.Parent ~= nil and not near
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
		local carrying = table.find(splitCarry(player:GetAttribute("Carry")), station.Item) ~= nil
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

	task.spawn(function()
		while not done() do
			local ok, err = pcall(step)
			if not ok then
				warn("[Guide] " .. tostring(err))
				hide()
			end
			task.wait(STEP_SECONDS)
		end
		-- Goal reached: clean up for good.
		characterConnection:Disconnect()
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
