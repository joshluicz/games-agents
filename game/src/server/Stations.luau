--!strict
-- Hold-to-make treatment stations (build plan §B5, Task 2). Server only.
--
-- Every `Station_<StationId>` part in every placed room (Plots.observeRooms: the Stand at boot, bought rooms
-- later) gets a ProximityPrompt `MakePrompt`: ActionText "Make", ObjectText the station's icon. Holding it puts
-- that station's item (Data/Stations .Item) in your tray (Carry.add), with a sparkle burst, and tells
-- Daily.onMake. Only people who may work the clinic (Plots.canWork) can make, and only while it has an owner:
-- a free plot's prompts are switched off.
--
-- Hold time, checked on the server (the old Kitchen pattern). A prompt's hold runs on the client, so the server
-- times it itself: PromptButtonHoldBegan starts a hold (one at a time per player), and Triggered only counts
-- when at least Prices.makeSeconds(<the maker's Faster Hands level>) has passed, less a small lag allowance.
-- A trigger with no hold, a hold on another prompt, a hold that's too short or stale, or a maker who's too far
-- away is ignored. Speed is the MAKER's own upgrade, so a friend helping keeps their own hands.
--
-- Hold time on screen. A server-set HoldDuration replicates to everyone, but each player's Speed differs. So the
-- server sets the SLOWEST time (Speed 0), which is never too short for anyone, and never changes it. Each client
-- shortens its own copy to Prices.makeSeconds(State.Upgrades.Speed) (Task 6). To find them, every MakePrompt is
-- tagged `StationPrompt` (CollectionService; use GetInstanceAddedSignal too, for streaming and new rooms) and
-- carries the attributes `StationId` and `ItemId`.
--
-- A full tray never blocks the clinic. Treatments are free, so making something with a full tray swaps out the
-- oldest item that's different ("🔄 🧪 ➜ 🩹"): a kid holding the wrong thing just makes the right one. Only a
-- tray already full of this very item refuses ("Tray full!"), since a swap would change nothing.
--
-- Feedback is immediate: a refusal (a locked clinic, a tray full of this item) toasts when the hold BEGINS, so
-- nobody holds for nothing. Toasts are short (≤ 6 words, icon first) and the same toast is sent at most once
-- every 1.5 s per player.
--
-- After every make, Tutorial.onMade(player, itemId, plot): the first-session tutorial moves on when a new
-- player makes what their first patient needs at their own clinic.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Palette = require(Shared.Palette)
local ItemData = require(Shared.Data.Items)
local StationData = require(Shared.Data.Stations)
local Prices = require(Shared.Logic.Prices)
local Carry = require(script.Parent.Carry)
local Daily = require(script.Parent.Daily)
local Economy = require(script.Parent.Economy)
local Plots = require(script.Parent.Plots)
local Tutorial = require(script.Parent.Tutorial)

type Plot = Types.Plot

local Stations = {}

Stations.PROMPT_NAME = "MakePrompt"
Stations.PROMPT_TAG = "StationPrompt"

local ACTION_TEXT = "Make"
local ACTIVATION_DISTANCE = 10
local DISTANCE_SLACK = 8 -- studs of movement and lag allowed beyond the activation distance
local LAG_ALLOWANCE = 0.25 -- seconds: hold begin/trigger can arrive this much closer together than the hold time
local STALE_AFTER = 8 -- seconds past the hold time: a hold this old is not a real hold
local TOAST_COOLDOWN = 1.5

local TRAY_FULL = "🙌 Tray full! Treat a patient."
local NOT_YOURS = "🔒 Not your clinic!"
local HOLD_LONGER = "✋ Hold a little longer!"
local SWAP_ICON = "🔄"
local SWAP_ARROW = "➜"

-- Told: the refusal already toasted when this hold began (not repeated when it completes).
type Hold = { Prompt: ProximityPrompt, Started: number, Ended: number?, Told: string? }

local holds: { [Player]: Hold } = {}
local lastToast: { [Player]: { [string]: number } } = {}
local prompts: { [ProximityPrompt]: Plot } = {}
local wired: { [BasePart]: boolean } = {}

------------------------------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------------------------------

local function toast(player: Player, text: string)
	local now = os.clock()
	local sent = lastToast[player]
	if not sent then
		sent = {}
		lastToast[player] = sent
	end
	if sent[text] and now - sent[text] < TOAST_COOLDOWN then
		return
	end
	sent[text] = now
	Remotes.toast(player, text)
end

-- The item a full tray gives up to make room for `itemId`: the oldest one that's different. nil when the tray
-- has room, or holds nothing but `itemId` (swapping would change nothing).
local function swapOut(player: Player, itemId: string): string?
	if not Carry.isFull(player) then
		return nil
	end
	for _, carried in Carry.items(player) do
		if carried ~= itemId then
			return carried
		end
	end
	return nil
end

-- Why this player can't make `itemId` here right now, or nil if they can.
local function refusal(player: Player, plot: Plot, itemId: string): string?
	if not plot.Owner or not Plots.canWork(player, plot) then
		return NOT_YOURS
	end
	if Carry.isFull(player) and swapOut(player, itemId) == nil then
		return TRAY_FULL -- full of this very item already
	end
	return nil
end

local function iconOf(itemId: string): string
	local item = rawget(ItemData :: any, itemId)
	return if item then item.Icon else "❔"
end

-- The maker is alive and standing near the station (the prompt's own range, plus some slack).
local function isNear(player: Player, part: BasePart): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) then
		return false
	end
	return (root.Position - part.Position).Magnitude <= ACTIVATION_DISTANCE + DISTANCE_SLACK
end

local function makeSeconds(player: Player): number
	return Prices.makeSeconds(Economy.level(player, "Speed"), Config)
end

-- A Station_<id> is a Part by contract; a kit might use a Model, so fall back to its main part.
local function stationPart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

-- Candy pop (memory-20261116-007): sparkles in the station's own full colour that turn candy yellow as they fall.
local function sparkleEmitter(part: BasePart, color: Color3): ParticleEmitter
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "MakeSparkles"
	sparkles.Enabled = false
	sparkles.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(0.55, color),
		ColorSequenceKeypoint.new(1, Palette.Candy.Yellow),
	})
	sparkles.LightEmission = 0.35 -- mostly normal blending, so the colour stays saturated in daylight
	sparkles.LightInfluence = 0
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.6, 0.42),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Transparency = NumberSequence.new(0, 0.3)
	sparkles.Lifetime = NumberRange.new(0.5, 0.9)
	sparkles.Speed = NumberRange.new(4, 8)
	sparkles.SpreadAngle = Vector2.new(60, 60)
	sparkles.Acceleration = Vector3.new(0, -6, 0)
	sparkles.Rotation = NumberRange.new(0, 360)
	sparkles.RotSpeed = NumberRange.new(-90, 90)
	sparkles.EmissionDirection = Enum.NormalId.Top
	sparkles.Parent = part
	return sparkles
end

------------------------------------------------------------------------------------------------------------------
-- Wiring one station
------------------------------------------------------------------------------------------------------------------

local function wireStation(plot: Plot, part: BasePart, stationId: string)
	local station = StationData[stationId]
	if not station or wired[part] then
		return
	end
	wired[part] = true
	local itemId = station.Item

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = Stations.PROMPT_NAME
	prompt.ActionText = ACTION_TEXT
	prompt.ObjectText = station.Icon
	prompt.HoldDuration = Prices.makeSeconds(0, Config) -- the slowest; clients shorten their own copy
	prompt.MaxActivationDistance = ACTIVATION_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Enabled = plot.Owner ~= nil
	prompt:SetAttribute("StationId", stationId)
	prompt:SetAttribute("ItemId", itemId)
	CollectionService:AddTag(prompt, Stations.PROMPT_TAG)

	local sparkles = sparkleEmitter(part, station.Color)

	prompt.PromptButtonHoldBegan:Connect(function(player: Player)
		local why = refusal(player, plot, itemId)
		holds[player] = { Prompt = prompt, Started = os.clock(), Ended = nil, Told = why }
		if why then
			toast(player, why) -- say it now, not after a hold that can't work
		end
	end)

	prompt.PromptButtonHoldEnded:Connect(function(player: Player)
		local hold = holds[player]
		if hold and hold.Prompt == prompt and not hold.Ended then
			hold.Ended = os.clock()
		end
	end)

	prompt.Triggered:Connect(function(player: Player)
		local hold = holds[player]
		holds[player] = nil
		if not hold or hold.Prompt ~= prompt then
			return -- no hold on THIS prompt: a spoofed or overlapping trigger
		end
		local now = os.clock()
		local needed = makeSeconds(player)
		if now - hold.Started > needed + STALE_AFTER then
			return
		end
		if (hold.Ended or now) - hold.Started + LAG_ALLOWANCE < needed then
			toast(player, HOLD_LONGER)
			return
		end
		if not isNear(player, part) then
			return
		end
		local why = refusal(player, plot, itemId)
		if why then
			if why ~= hold.Told then
				toast(player, why)
			end
			return
		end
		-- A full tray swaps its oldest different item for this one (treatments are free, so nothing is lost).
		local swapped = swapOut(player, itemId)
		if swapped then
			Carry.take(player, swapped)
		end
		if not Carry.add(player, itemId) then
			if swapped then
				Carry.add(player, swapped) -- couldn't make it after all: put the old one back
			end
			toast(player, TRAY_FULL)
			return
		end
		if swapped then
			toast(player, SWAP_ICON .. " " .. iconOf(swapped) .. " " .. SWAP_ARROW .. " " .. iconOf(itemId))
		end

		-- Emit() on the server never reaches players, so switch the emitter on for a moment instead (the
		-- Enabled change replicates and each client makes the burst itself).
		sparkles.Rate = 90
		sparkles.Enabled = true
		task.delay(0.16, function()
			sparkles.Enabled = false
		end)
		local ok, err = pcall(Daily.onMake, player, itemId)
		if not ok then
			warn("[Stations] Daily.onMake failed:", err)
		end
		local tutorialOk, tutorialErr = pcall(Tutorial.onMade, player, itemId, plot)
		if not tutorialOk then
			warn("[Stations] Tutorial.onMade failed:", tutorialErr)
		end
	end)

	prompt.Destroying:Once(function()
		prompts[prompt] = nil
		wired[part] = nil
	end)
	prompts[prompt] = plot
	prompt.Parent = part -- parent last: it replicates once, fully set up
end

local function wireRoom(plot: Plot, roomModel: Model)
	for _, descendant in roomModel:GetDescendants() do
		local stationId = string.match(descendant.Name, "^Station_(%w+)$")
		if stationId then
			if not StationData[stationId] then
				warn("[Stations] Unknown station", descendant:GetFullName())
				continue
			end
			local part = stationPart(descendant)
			if part then
				wireStation(plot, part, stationId)
			else
				warn("[Stations] No part to hold the prompt in", descendant:GetFullName())
			end
		end
	end
end

local function setPlotOpen(plot: Plot, open: boolean)
	for prompt, owner in prompts do
		if owner == plot then
			prompt.Enabled = open
		end
	end
end

------------------------------------------------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------------------------------------------------

-- 🗑️ Throw away: a second Counter prompt (its own key, so it shows beside Treat) that empties your hands, so a
-- wrong or unneeded item can never leave a player stuck. Free, no confirm: treatments cost nothing to make.
local BIN_TEXT = "🗑️ Hands empty!"
local function wireBin(plot: Plot)
	local counter = plot.Counter
	if not counter or counter:FindFirstChild("BinAttachment") then
		return
	end
	local holder = Instance.new("Attachment")
	holder.Name = "BinAttachment"
	holder.Position = Vector3.new(0, counter.Size.Y / 2 + 1.2, 0)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BinPrompt"
	prompt.ActionText = "Throw away"
	prompt.ObjectText = "🗑️"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = ACTIVATION_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.Q
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.UIOffset = Vector2.new(0, 72) -- sits just under the Treat prompt
	prompt.Parent = holder
	prompt.Triggered:Connect(function(player: Player)
		if #Carry.items(player) == 0 then
			toast(player, BIN_TEXT)
			return
		end
		if not isNear(player, counter) then
			return
		end
		Carry.clear(player)
		toast(player, "🗑️ Tray emptied!")
	end)
	holder.Parent = counter
end

function Stations.start()
	Plots.observeRooms(function(plot: Plot, _roomId: string, roomModel: Model)
		wireRoom(plot, roomModel)
	end)
	for _, plot in Plots.all() do
		wireBin(plot)
	end

	-- PlotReleased runs before the plot is cleared; the Stand stays, so switch its prompts off.
	Plots.PlotReleased:Connect(function(_player: Player, plot: Plot)
		setPlotOpen(plot, false)
	end)
	Plots.PlotAssigned:Connect(function(_player: Player, plot: Plot)
		setPlotOpen(plot, true)
	end)

	Players.PlayerRemoving:Connect(function(player)
		holds[player] = nil
		lastToast[player] = nil
	end)
end

return Stations
