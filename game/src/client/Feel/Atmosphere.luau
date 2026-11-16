--!strict
-- Atmosphere (build plan Task 7). Client only and purely visual.
--   Snow       soft flakes around your camera while Workspace.IsWinter is true
--   Fireflies  a few warm, slowly blinking lights around you at night (Workspace.IsNight)
--   Decor sway placed decor with a DecorBuilder.BOB_TAG sub-model (balloons, lanterns, the duck, the mascot) sways
--              gently, here on each client, so nothing moves on the server or replicates per frame
--   Day/night  a soft little tune when night falls and when morning comes
--   Toggle     a ✨ button (right edge, half way down) switches calm effects on and off
--
-- Comfort settings are player attributes set on THIS client only (they never replicate; the server never sets them):
--   ReduceEffects: boolean   true = calm effects. Starts from the device's Reduced Motion setting. Every Feel module
--                            reads it; UI modules may honour it too.
--   MusicMuted: boolean      owned by Music.client (its 🎵 button sits just left of the ✨ one)
-- Other modules can switch them over the bus: ctx.fire("SetReduceEffects", on) / ctx.fire("SetMusicMuted", on).
-- Roblox has no client-side storage, so both reset when you rejoin.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))

local Atmosphere = {}

local BOB_TAG = "ClinicDecorBob" -- DecorBuilder.BOB_TAG (a server module, so not required here)
local SOFT_DOT = "rbxasset://textures/particles/explosion01_implosion_main.dds" -- a soft round glow (built in)

local SNOW = {
	Rate = 60,
	CalmRate = 18,
	Area = Vector3.new(110, 1, 110), -- the cloud of flakes, centred a little ahead of the camera
	Height = 30, -- studs above the camera
	Ahead = 25,
}
local FIREFLIES = {
	Rate = 5,
	CalmRate = 2,
	Area = Vector3.new(70, 7, 70), -- around your character, from the ground up
}
local SWAY_DISTANCE = 140 -- decor further than this from the camera rests still
local TOGGLE_SIZE = 60
-- The comfort pair (🎵 ✨) sits side by side on the right edge, half way down: clear of the Hud's top-right chips
-- and above the phone jump button. Music.client uses the same numbers.
local TOGGLE_Y = 0.5

local player = Players.LocalPlayer
local ctx: Types.Ctx

------------------------------------------------------------------------------------------------------------------
-- Comfort settings
------------------------------------------------------------------------------------------------------------------

local function calm(): boolean
	local value = player:GetAttribute("ReduceEffects")
	if value == nil then
		return Kit.reducedMotion()
	end
	return value == true
end

local function setCalm(on: boolean)
	player:SetAttribute("ReduceEffects", on)
end

------------------------------------------------------------------------------------------------------------------
-- Snow and fireflies: two invisible client-only emitter parts that follow the camera
------------------------------------------------------------------------------------------------------------------

local folder: Folder? = nil

local function effectsFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "ClientAtmosphere"
	created.Parent = Workspace
	folder = created
	return created
end

local function emitterPart(name: string, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = effectsFolder()
	return part
end

local function makeSnow(): (Part, ParticleEmitter)
	local part = emitterPart("Snow", SNOW.Area)
	local snow = Instance.new("ParticleEmitter")
	snow.Name = "Flakes"
	snow.Texture = SOFT_DOT
	snow.Color = ColorSequence.new(Color3.fromRGB(240, 248, 255))
	snow.LightEmission = 0.2
	snow.LightInfluence = 0.7
	snow.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.32, 0.1),
		NumberSequenceKeypoint.new(1, 0.26, 0.08),
	})
	snow.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.08, 0.15),
		NumberSequenceKeypoint.new(0.88, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	snow.Lifetime = NumberRange.new(9, 11)
	snow.Speed = NumberRange.new(3.5, 5)
	snow.EmissionDirection = Enum.NormalId.Bottom
	snow.SpreadAngle = Vector2.new(12, 12)
	snow.Acceleration = Vector3.new(0.7, -0.4, 0.3) -- a little drift, like a breeze
	snow.Shape = Enum.ParticleEmitterShape.Box
	snow.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	snow.Rotation = NumberRange.new(0, 360)
	snow.RotSpeed = NumberRange.new(-30, 30)
	snow.Rate = 0
	snow.Enabled = false
	snow.Parent = part
	return part, snow
end

local function makeFireflies(): (Part, ParticleEmitter)
	local part = emitterPart("Fireflies", FIREFLIES.Area)
	local flies = Instance.new("ParticleEmitter")
	flies.Name = "Fireflies"
	flies.Texture = SOFT_DOT
	flies.Color = ColorSequence.new(Color3.fromRGB(255, 236, 140), Color3.fromRGB(210, 255, 150))
	flies.LightEmission = 1
	flies.LightInfluence = 0
	flies.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.15, 0.32),
		NumberSequenceKeypoint.new(0.85, 0.32),
		NumberSequenceKeypoint.new(1, 0),
	})
	-- One slow glow and fade over a 5-8 s life: far below any flashing rate.
	flies.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.15),
		NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(0.8, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	flies.Lifetime = NumberRange.new(5, 8)
	flies.Speed = NumberRange.new(0.2, 0.6)
	flies.SpreadAngle = Vector2.new(180, 180)
	flies.Acceleration = Vector3.new(0, 0.06, 0)
	flies.Drag = 0.4
	flies.Shape = Enum.ParticleEmitterShape.Box
	flies.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	flies.Rate = 0
	flies.Enabled = false
	flies.Parent = part
	return part, flies
end

local snowPart: Part, snow: ParticleEmitter
local fireflyPart: Part, fireflies: ParticleEmitter

local function refreshWeather()
	local quiet = calm()
	local winter = Workspace:GetAttribute("IsWinter") == true
	local night = Workspace:GetAttribute("IsNight") == true
	snow.Rate = if quiet then SNOW.CalmRate else SNOW.Rate
	snow.Enabled = winter
	fireflies.Rate = if quiet then FIREFLIES.CalmRate else FIREFLIES.Rate
	fireflies.Enabled = night
end

local function followCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if snow.Enabled then
		local cf = camera.CFrame
		local flat = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
		local ahead = if flat.Magnitude > 0.01 then flat.Unit * SNOW.Ahead else Vector3.zero
		snowPart.CFrame = CFrame.new(cf.Position + ahead + Vector3.new(0, SNOW.Height, 0))
	end
	if fireflies.Enabled then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local centre = if root and root:IsA("BasePart") then root.Position else camera.Focus.Position
		-- The root is about 3 studs up: the box then spans the ground to head height and a bit.
		fireflyPart.CFrame = CFrame.new(centre + Vector3.new(0, FIREFLIES.Area.Y / 2 - 3, 0))
	end
end

------------------------------------------------------------------------------------------------------------------
-- Decor sway
------------------------------------------------------------------------------------------------------------------

type Swayer = {
	Group: Model,
	Outer: Model, -- the decor Model; its pivot never moves on the client
	Rest: CFrame, -- the group's rest pivot relative to Outer's pivot
	Height: number,
	Sway: number,
	Spin: number,
	Speed: number,
	Phase: number,
	Resting: boolean,
}

local swayers: { [Model]: Swayer } = {}

local function numberAttribute(group: Instance, name: string): number
	local value = group:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function addSwayer(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local outer = instance.Parent
	local restPivot = instance:GetAttribute("BobRest")
	if not (outer and outer:IsA("Model") and typeof(restPivot) == "CFrame") then
		return
	end
	swayers[instance] = {
		Group = instance,
		Outer = outer,
		Rest = restPivot,
		Height = numberAttribute(instance, "BobHeight"),
		Sway = numberAttribute(instance, "BobSway"),
		Spin = numberAttribute(instance, "BobSpin"),
		Speed = math.max(numberAttribute(instance, "BobSpeed"), 0.05),
		Phase = math.random() * math.pi * 2,
		Resting = false,
	}
end

local function rest(swayer: Swayer)
	if not swayer.Resting then
		swayer.Resting = true
		swayer.Group:PivotTo(swayer.Outer:GetPivot() * swayer.Rest)
	end
end

local function sway(now: number)
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local still = calm()
	for group, swayer in swayers do
		if not group.Parent or not swayer.Outer.Parent then
			swayers[group] = nil
			continue
		end
		local base = swayer.Outer:GetPivot() * swayer.Rest
		if still or (base.Position - eye).Magnitude > SWAY_DISTANCE then
			rest(swayer)
			continue
		end
		swayer.Resting = false
		local t = now * swayer.Speed * math.pi * 2 + swayer.Phase
		group:PivotTo(
			base
				* CFrame.new(0, swayer.Height * math.sin(t), 0)
				* CFrame.Angles(0, swayer.Spin * math.sin(t * 0.5), swayer.Sway * math.sin(t))
		)
	end
end

local function watchDecor()
	for _, instance in CollectionService:GetTagged(BOB_TAG) do
		addSwayer(instance)
	end
	CollectionService:GetInstanceAddedSignal(BOB_TAG):Connect(function(instance)
		-- Streaming can deliver the group a moment before its parts and parent are in place.
		task.defer(addSwayer, instance)
	end)
	CollectionService:GetInstanceRemovedSignal(BOB_TAG):Connect(function(instance)
		if instance:IsA("Model") then
			swayers[instance] = nil
		end
	end)
end

------------------------------------------------------------------------------------------------------------------
-- The calm-effects toggle (✨ = full effects, 💤 = calm)
------------------------------------------------------------------------------------------------------------------

local function makeToggle()
	local gui = Kit.screen("EffectsToggle", Theme.DisplayOrder.Hud)
	local button = Kit.iconButton({
		Name = "Effects",
		Icon = "✨",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -Theme.Size.Margin, TOGGLE_Y, 0),
		Size = UDim2.fromOffset(TOGGLE_SIZE, TOGGLE_SIZE),
		Parent = gui,
	})
	local icon = button:FindFirstChild("Icon") :: TextLabel?
	local function show()
		local quiet = calm()
		if icon then
			icon.Text = if quiet then "💤" else "✨"
		end
		button.BackgroundColor3 = if quiet then Theme.Colors.Quiet else Theme.Colors.Card
		button:SetAttribute("KitColor", button.BackgroundColor3)
	end
	button.Activated:Connect(function()
		local quiet = not calm()
		setCalm(quiet)
		ctx.toast(if quiet then "💤 Calm effects" else "✨ Full effects")
	end)
	player:GetAttributeChangedSignal("ReduceEffects"):Connect(show)
	show()
end

------------------------------------------------------------------------------------------------------------------

function Atmosphere.init(context: Types.Ctx)
	ctx = context

	if player:GetAttribute("ReduceEffects") == nil then
		setCalm(Kit.reducedMotion())
	end
	-- Follow the device setting if it changes mid-game.
	pcall(function()
		GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
			setCalm(Kit.reducedMotion())
		end)
	end)
	ctx.on("SetReduceEffects", function(on: any)
		if type(on) == "boolean" then
			setCalm(on)
		end
	end)
	ctx.on("SetMusicMuted", function(on: any)
		if type(on) == "boolean" then
			player:SetAttribute("MusicMuted", on)
		end
	end)

	snowPart, snow = makeSnow()
	fireflyPart, fireflies = makeFireflies()
	refreshWeather()
	Workspace:GetAttributeChangedSignal("IsWinter"):Connect(refreshWeather)
	player:GetAttributeChangedSignal("ReduceEffects"):Connect(refreshWeather)

	local wasNight = Workspace:GetAttribute("IsNight") == true
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(function()
		refreshWeather()
		local night = Workspace:GetAttribute("IsNight") == true
		if night ~= wasNight then
			ctx.fire("Sound", if night then "Night" else "Morning")
		end
		wasNight = night
	end)

	watchDecor()
	RunService.RenderStepped:Connect(function()
		followCamera()
		sway(os.clock())
	end)

	makeToggle()
end

return Atmosphere
