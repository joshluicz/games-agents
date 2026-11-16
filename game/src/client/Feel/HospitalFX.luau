--!strict
-- Hospital v2's effects on this client (Progression v2 build plan §B4 "Motion", §C T8). OWNER: T8. Client only:
-- nothing here changes game state, and the server writes one attribute per event, never a per-frame CFrame.
--   init(ctx)
--
-- What it draws (each one only near you, and every motion honours Kit.reducedMotion()):
--   🚑 the ambulance   A plot's parked Ambulance (inside its Building, T6) gets a new ArriveAt when an A&E patient
--                      pulls up (T7): two roof lights flash red and blue over it for FLASH_SECONDS with a soft glow,
--                      and a gentle toy siren plays within earshot. Calm: the lights glow softly in turn, slowly,
--                      and there is no siren.
--   🚁 the helicopter  A plot's HeliSpot (on the roof, T6) gets a new ArriveAt for an air-ambulance VIP (T7): a
--                      client-only helicopter (12 parts, no scripts, no collisions, no shadows) flies down onto
--                      the pad (one tween), rests while its rotor turns, then flies away (one tween) and is gone.
--                      Calm: it fades in on the pad, rests with its rotor still, and fades away.
--   ✨ abilities       A nurse whose AbilityAt changes (T1: its ability fired) sparkles and its ability's icon floats
--                      up (Data/Abilities), with a soft "Ability" chime within earshot. Calm: the icon only (it fades
--                      where it is), no sparkles. Each working nurse within RING_STUDS (40) also wears its cooldown
--                      ring over its head: Kit.ring filled from AbilityReadyAt / AbilityCooldown (beads, never
--                      seconds), in T1's BillboardGui "AbilityRing" when the nurse has one (a "RingFX" frame is added
--                      inside it), else in this module's own "AbilityRingFX". Rings update 4 times a second, and only
--                      while a nurse is that close; past it they go.
--   🛗 the lift        Someone else's ride (the Lift model's RideAt, with Rider = their UserId; T6) dings at that lift
--                      when you're within earshot. Your own ride's ding is UI/LiftPanel's.
--   🏗️ the grow-in     A Building rebuilt with a fresh GrewAt (a level-up) fades its new pieces in from the ground up;
--                      one rebuilt in a new Theme (a rebirth, or a theme picked in the Branch panel) fades all of it in
--                      the same way. A sparkle at its top and a chime. Calm: it just appears. Never on joining.
-- Everything is event-driven: attribute signals on each plot's building pieces and each nurse; the only loops run
-- while an effect plays (a flash, a flight, a grow-in) or a nurse with a ring is near you, and they stop by
-- themselves. Found by name inside each plot's Building (rebuilt only on a level-up or a theme change) and by the
-- CreatureMotion tag for nurses, never by watching the whole town.
-- The pure rules (freshness, the flash, the flight, the grow-in, earshot) are the PURE block (tests/Juice).
-- Bus events fired: "Sound" (Siren, Heli, Ability, Ding, Sparkle).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))

local HospitalFX = {}

------------------------------------------------------------------------------------------------------------------
-- Pure rules (no Roblox APIs between the markers)
------------------------------------------------------------------------------------------------------------------
-- BEGIN PURE
local Pure = {}

Pure.FLASH_SECONDS = 6 -- the ambulance's lights
Pure.HELI_IN = 3.2 -- the helicopter's flight down onto the pad
Pure.HELI_STAY = 6 -- resting on the pad, rotor turning
Pure.HELI_OUT = 3 -- its flight away
Pure.HELI_HEIGHT = 42 -- studs above the pad it comes from and goes to
Pure.GROW_SECONDS = 0.7 -- one piece fading in
Pure.GROW_SPREAD = 0.9 -- the last (highest) piece starts this long after the first

local function finite(value: any): number?
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return nil
end

-- A server time `at` (an attribute) is a fresh event at `now`: no more than a second ahead (clock skew) and no older
-- than `window` seconds. A late joiner sees old values: they show nothing.
function Pure.fresh(at: any, now: number, window: number): boolean
	local when = finite(at)
	if when == nil or when <= 0 then
		return false
	end
	local age = (finite(now) or 0) - when
	return age >= -1 and age <= math.max(finite(window) or 0, 0)
end

-- The ambulance's lights `t` seconds into a flash: which light is on (1 = red, 2 = blue) and how bright (0..1).
-- Busy and bright normally (four swaps a second); calm: a slow, soft swap (under one a second, half bright).
function Pure.flash(t: number, calm: boolean): (number, number)
	local period = if calm then 1.4 else 0.5
	local phase = ((finite(t) or 0) % period) / period
	return (if phase < 0.5 then 1 else 2), (if calm then 0.5 else 1)
end

-- The helicopter `elapsed` seconds after ArriveAt: its phase ("In" | "Stay" | "Out" | "Done") and the seconds left
-- in that phase (so a late look joins the flight where it is: past "In" it simply sits on the pad).
function Pure.heli(elapsed: number): (string, number)
	local t = math.max(finite(elapsed) or 0, 0)
	if t < Pure.HELI_IN then
		return "In", Pure.HELI_IN - t
	end
	t -= Pure.HELI_IN
	if t < Pure.HELI_STAY then
		return "Stay", Pure.HELI_STAY - t
	end
	t -= Pure.HELI_STAY
	if t < Pure.HELI_OUT then
		return "Out", Pure.HELI_OUT - t
	end
	return "Done", 0
end

-- The grow-in: how long a piece at `height` waits (the lowest at once, the highest GROW_SPREAD later) ...
function Pure.growDelay(height: number, low: number, high: number): number
	local span = (finite(high) or 0) - (finite(low) or 0)
	if span <= 0 then
		return 0
	end
	return math.clamp(((finite(height) or 0) - (finite(low) or 0)) / span, 0, 1) * Pure.GROW_SPREAD
end

-- ... and how far it has faded in (0 = invisible, 1 = as built) `t` seconds into the grow-in.
function Pure.growAlpha(t: number, delay: number): number
	local into = (finite(t) or 0) - (finite(delay) or 0)
	if into <= 0 then
		return 0
	end
	local x = math.clamp(into / Pure.GROW_SECONDS, 0, 1)
	return 1 - (1 - x) ^ 3
end

-- How loud something `distance` studs away is (0..1): full up close, softer with distance, silent past `reach`.
function Pure.earshot(distance: number, reach: number): number
	local d, r = finite(distance) or math.huge, finite(reach) or 0
	if r <= 0 or d > r then
		return 0
	end
	if d <= 12 then
		return 1
	end
	return math.clamp(1 - 0.75 * (d - 12) / math.max(r - 12, 1), 0.25, 1)
end
-- END PURE
HospitalFX.Pure = Pure

------------------------------------------------------------------------------------------------------------------
-- Tuning (studs, seconds)
------------------------------------------------------------------------------------------------------------------
local SEE_STUDS = 220 -- effects further from you than this don't play
local SIREN_STUDS = 90
local HELI_STUDS = 120
local ABILITY_STUDS = 60
local ABILITY_SOUND_STUDS = 40
local DING_STUDS = 50
local RING_STUDS = 40 -- build plan §C T1: the ring only within 40 studs
local RING_STEP = 0.25 -- ring updates while one is near
local RING_IDLE = 1 -- distance checks while none is near
local GROW_MAX_PARTS = 220
local FRESH_ARRIVE = 10
local FRESH_ABILITY = 3
local FRESH_RIDE = 4
local FRESH_GROW = 6
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local MOTION_TAG = "CreatureMotion" -- Server/Nurses tags every worker (and Feel/CreatureMotion draws it)

local RED = Color3.fromRGB(255, 70, 90)
local BLUE = Color3.fromRGB(70, 150, 255)

local player = Players.LocalPlayer
local ctx: Types.Ctx

local function calm(): boolean
	return Kit.reducedMotion()
end

local function sound(name: string, volume: number?)
	if ctx and (volume == nil or volume > 0) then
		ctx.fire("Sound", name, volume)
	end
end

-- Where "you" are: your character, else the camera.
local function listener(): Vector3
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.Position else Vector3.zero
end

local function distanceTo(position: Vector3): number
	return (position - listener()).Magnitude
end

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function pivotOf(instance: Instance): CFrame?
	if instance:IsA("BasePart") then
		return instance.CFrame
	elseif instance:IsA("Model") then
		local ok, pivot = pcall(instance.GetPivot, instance)
		return if ok then pivot else nil
	end
	return nil
end

-- A throwaway Attachment in Terrain at a world position (removed after `lifetime`).
local function anchorAt(position: Vector3, lifetime: number): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = "HospitalFX"
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain
	task.delay(lifetime, function()
		attachment:Destroy()
	end)
	return attachment
end

-- Sparkles burst from a world position (nothing when calm).
local function sparkles(position: Vector3, color: Color3, count: number)
	if calm() then
		return
	end
	local attachment = anchorAt(position, 2.5)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE_TEXTURE
	emitter.Color = ColorSequence.new(color, Palette.White)
	emitter.LightEmission = 0.7
	emitter.Lifetime = NumberRange.new(0.5, 1)
	emitter.Speed = NumberRange.new(4, 9)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(count)
end

------------------------------------------------------------------------------------------------------------------
-- 🚑 The ambulance
------------------------------------------------------------------------------------------------------------------

local flashing: { [Instance]: boolean } = {}

local function flashAmbulance(ambulance: Instance)
	if flashing[ambulance] then
		return
	end
	local pivot = pivotOf(ambulance)
	if not pivot or distanceTo(pivot.Position) > SEE_STUDS then
		return
	end
	local top = pivot.Position
	if ambulance:IsA("Model") then
		local ok, box, size = pcall(ambulance.GetBoundingBox, ambulance)
		if ok then
			top = (box :: CFrame).Position + Vector3.new(0, (size :: Vector3).Y / 2 + 0.6, 0)
		end
	end
	flashing[ambulance] = true
	local quiet = calm()
	local attachment = anchorAt(top, Pure.FLASH_SECONDS + 0.5)
	local glow = Instance.new("PointLight")
	glow.Range = 14
	glow.Shadows = false
	glow.Brightness = 0
	glow.Parent = attachment
	local gui = Instance.new("BillboardGui")
	gui.Name = "SirenLights"
	gui.Size = UDim2.fromScale(3.4, 1.1)
	gui.LightInfluence = 0
	gui.MaxDistance = SEE_STUDS
	gui.Parent = attachment
	local lights: { Frame } = {}
	for index = 1, 2 do
		local light = Instance.new("Frame")
		light.Name = if index == 1 then "Red" else "Blue"
		light.AnchorPoint = Vector2.new(0.5, 0.5)
		light.Position = UDim2.fromScale(if index == 1 then 0.27 else 0.73, 0.5)
		light.Size = UDim2.fromScale(0.42, 1)
		light.BackgroundColor3 = if index == 1 then RED else BLUE
		light.BorderSizePixel = 0
		Kit.corner(light, Theme.Radius.Round)
		Kit.stroke(light, Theme.Colors.Outline, 2)
		light.Parent = gui
		lights[index] = light
	end
	if not quiet then
		sound("Siren", Pure.earshot(distanceTo(top), SIREN_STUDS))
	end
	task.spawn(function()
		local started = os.clock()
		local shown = -1
		while os.clock() - started < Pure.FLASH_SECONDS and attachment.Parent do
			local on, bright = Pure.flash(os.clock() - started, quiet)
			if on ~= shown then
				shown = on
				for index, light in lights do
					light.BackgroundTransparency = if index == on then 1 - bright else 0.75
				end
				glow.Color = if on == 1 then RED else BLUE
				glow.Brightness = 2.5 * bright
			end
			task.wait(if quiet then 0.35 else 0.12)
		end
		attachment:Destroy()
		flashing[ambulance] = nil
	end)
end

------------------------------------------------------------------------------------------------------------------
-- 🚁 The helicopter (client-only, 12 parts)
------------------------------------------------------------------------------------------------------------------

local flying: { [Instance]: boolean } = {}

type Heli = { Model: Model, Body: BasePart, Rotor: Weld, Parts: { BasePart }, Lift: number }

-- An original toy air ambulance: a round mint body with a sky-blue window, a white stripe, a pink tail, skids and a
-- rotor (12 parts). No cross on it at all (a red cross on white is a protected emblem; the clinic's own sign is a
-- white cross on its accent colour).
local function buildHeli(): Heli
	local model = Instance.new("Model")
	model.Name = "AirAmbulanceFX"
	local parts: { BasePart } = {}
	local function part(name: string, shape: Enum.PartType?, size: Vector3, color: Color3, offset: CFrame): BasePart
		local p = Instance.new("Part")
		p.Name = name
		if shape then
			p.Shape = shape
		end
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		p.Anchored = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CFrame = offset
		p.Parent = model
		table.insert(parts, p)
		return p
	end
	local mint = Palette.Candy.Mint
	local body = part("Body", Enum.PartType.Ball, Vector3.new(5, 5, 5), mint, CFrame.new())
	body.Anchored = true
	part("Window", Enum.PartType.Ball, Vector3.new(3, 3, 3), Color3.fromRGB(190, 232, 255), CFrame.new(0, 0.5, -1.6))
	part("Stripe", nil, Vector3.new(5.1, 0.7, 3.2), Palette.White, CFrame.new(0, -0.6, 0.2))
	part("Tail", nil, Vector3.new(0.9, 0.9, 5), Theme.Colors.Pink, CFrame.new(0, 0.5, 4.6))
	part("Fin", nil, Vector3.new(0.3, 2, 1.3), Theme.Colors.Pink, CFrame.new(0, 1.3, 6.8))
	part("TailRotor", nil, Vector3.new(0.2, 1.8, 0.35), Palette.White, CFrame.new(0.3, 1.3, 6.9))
	part(
		"Mast",
		Enum.PartType.Cylinder,
		Vector3.new(0.9, 0.7, 0.7),
		Palette.White,
		CFrame.new(0, 2.8, 0) * CFrame.Angles(0, 0, math.pi / 2)
	)
	part("SkidL", nil, Vector3.new(0.35, 0.35, 5), Palette.White, CFrame.new(-1.7, -3.1, 0))
	part("SkidR", nil, Vector3.new(0.35, 0.35, 5), Palette.White, CFrame.new(1.7, -3.1, 0))
	part("StrutL", nil, Vector3.new(0.3, 1.2, 0.3), Palette.White, CFrame.new(-1.4, -2.4, 0))
	part("StrutR", nil, Vector3.new(0.3, 1.2, 0.3), Palette.White, CFrame.new(1.4, -2.4, 0))
	local blades = part("Blades", nil, Vector3.new(11, 0.18, 0.7), Palette.White, CFrame.new(0, 3.3, 0))
	for _, p in parts do
		if p ~= body then
			local weld = if p == blades then Instance.new("Weld") else Instance.new("WeldConstraint")
			if weld:IsA("Weld") then
				weld.Part0 = body
				weld.Part1 = p
				weld.C0 = CFrame.new(0, 3.3, 0)
			elseif weld:IsA("WeldConstraint") then
				weld.Part0 = body
				weld.Part1 = p
			end
			weld.Parent = p
		end
	end
	model.PrimaryPart = body
	-- the skids' bottom sits 3.3 studs under the body's centre
	return {
		Model = model,
		Body = body,
		Rotor = blades:FindFirstChildOfClass("Weld") :: Weld,
		Parts = parts,
		Lift = 3.3,
	}
end

local function setHeliFade(heli: Heli, transparency: number, info: TweenInfo?)
	for _, p in heli.Parts do
		local goal = if p.Name == "Window" then math.max(transparency, 0.2) else transparency
		if info then
			TweenService:Create(p, info, { Transparency = goal }):Play()
		else
			p.Transparency = goal
		end
	end
end

local function flyHeli(spot: BasePart, arriveAt: number)
	if flying[spot] then
		return
	end
	local padTop = spot.Position + Vector3.new(0, spot.Size.Y / 2, 0)
	if distanceTo(padTop) > SEE_STUDS then
		return
	end
	local phase, left = Pure.heli(now() - arriveAt)
	if phase == "Done" or phase == "Out" then
		return
	end
	flying[spot] = true
	local heli = buildHeli()
	local look = spot.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local forward = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local landed = CFrame.lookAt(padTop + Vector3.new(0, heli.Lift, 0), padTop + Vector3.new(0, heli.Lift, 0) + forward)
	local above = landed * CFrame.new(0, Pure.HELI_HEIGHT, 30) -- comes in from behind and above
	local away = landed * CFrame.new(0, Pure.HELI_HEIGHT + 4, -40) -- leaves ahead and up
	local quiet = calm()
	local alive = true
	-- The rotor turns only while the helicopter is here (one Weld write a frame; still when calm).
	local spin: RBXScriptConnection? = nil
	if not quiet then
		local angle = 0
		spin = RunService.Heartbeat:Connect(function(dt: number)
			angle = (angle + dt * 14) % (math.pi * 2)
			heli.Rotor.C0 = CFrame.new(0, 3.3, 0) * CFrame.Angles(0, angle, 0)
		end)
	end
	local function finish()
		if not alive then
			return
		end
		alive = false
		if spin then
			spin:Disconnect()
		end
		heli.Model:Destroy()
		flying[spot] = nil
	end
	heli.Model.AncestryChanged:Connect(function()
		if not heli.Model.Parent then
			finish()
		end
	end)

	local volume = Pure.earshot(distanceTo(padTop), HELI_STUDS)
	task.spawn(function()
		if phase == "In" and not quiet then
			-- PivotTo before it's parented, so every welded part starts in place with the body.
			heli.Model:PivotTo(above:Lerp(landed, 1 - left / Pure.HELI_IN))
			heli.Model.Parent = Workspace
			sound("Heli", volume)
			local down =
				TweenService:Create(heli.Body, TweenInfo.new(left, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					CFrame = landed,
				})
			down:Play()
			task.wait(left)
			left = Pure.HELI_STAY
		else
			heli.Model:PivotTo(landed)
			setHeliFade(heli, 1)
			heli.Model.Parent = Workspace
			setHeliFade(heli, 0, TweenInfo.new(0.6))
			if phase == "In" then
				left += Pure.HELI_STAY
			end
		end
		if not alive then
			return
		end
		task.wait(left)
		if not alive then
			return
		end
		if quiet then
			setHeliFade(heli, 1, TweenInfo.new(0.6))
			task.wait(0.65)
		else
			sound("Heli", volume)
			local up = TweenService:Create(
				heli.Body,
				TweenInfo.new(Pure.HELI_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{
					CFrame = away,
				}
			)
			up:Play()
			task.wait(Pure.HELI_OUT * 0.7)
			setHeliFade(heli, 1, TweenInfo.new(Pure.HELI_OUT * 0.3))
			task.wait(Pure.HELI_OUT * 0.3 + 0.05)
		end
		finish()
	end)
end

------------------------------------------------------------------------------------------------------------------
-- 🛗 The lift: someone else's ride dings
------------------------------------------------------------------------------------------------------------------

local function onRide(lift: Instance)
	local at = lift:GetAttribute("RideAt")
	if not Pure.fresh(at, now(), FRESH_RIDE) then
		return
	end
	local rider = lift:GetAttribute("Rider")
	if type(rider) == "number" and rider == player.UserId then
		return -- UI/LiftPanel dings your own ride
	end
	local pivot = pivotOf(lift)
	if pivot then
		sound("Ding", Pure.earshot(distanceTo(pivot.Position), DING_STUDS))
	end
end

------------------------------------------------------------------------------------------------------------------
-- 🏗️ The grow-in
------------------------------------------------------------------------------------------------------------------

local lastTheme: { [Instance]: string } = {} -- plot -> the theme last seen built there

local function growIn(building: Model, onlyNew: boolean)
	local level = building:GetAttribute("Level")
	local parts: { BasePart } = {}
	local low, high = math.huge, -math.huge
	for _, descendant in building:GetDescendants() do
		if #parts >= GROW_MAX_PARTS then
			break
		end
		if descendant:IsA("BasePart") and descendant.Transparency < 0.98 then
			local include = true
			if onlyNew then
				-- A level-up: only the pieces that came with this level (their Since, or an ancestor's).
				include = false
				local node: Instance? = descendant
				while node and node ~= building do
					local since = node:GetAttribute("Since")
					if since ~= nil then
						include = since == level
						break
					end
					node = node.Parent
				end
			end
			if include then
				table.insert(parts, descendant)
				low = math.min(low, descendant.Position.Y)
				high = math.max(high, descendant.Position.Y)
			end
		end
	end
	if #parts == 0 then
		return
	end
	local original: { [BasePart]: number } = {}
	local delays: { [BasePart]: number } = {}
	for _, p in parts do
		original[p] = p.Transparency
		delays[p] = Pure.growDelay(p.Position.Y, low, high)
		p.Transparency = 1
	end
	local started = os.clock()
	local total = Pure.GROW_SECONDS + Pure.GROW_SPREAD
	local shown: { [BasePart]: number } = {}
	local connection: RBXScriptConnection? = nil
	local function restore()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		for _, p in parts do
			if p.Parent then
				p.Transparency = original[p]
			end
		end
	end
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - started
		if t >= total or not building.Parent then
			restore()
			return
		end
		for _, p in parts do
			-- Steps of a tenth: a part is written at most ten times.
			local alpha = math.floor(Pure.growAlpha(t, delays[p]) * 10) / 10
			if shown[p] ~= alpha then
				shown[p] = alpha
				p.Transparency = 1 + (original[p] - 1) * alpha
			end
		end
	end)
	local top = Vector3.new(0, high + 2, 0)
	local pivot = pivotOf(building)
	if pivot then
		top = Vector3.new(pivot.Position.X, high + 2, pivot.Position.Z)
	end
	task.delay(Pure.GROW_SPREAD, function()
		sparkles(top, Theme.Colors.Cash, 24)
		sound("Sparkle", Pure.earshot(distanceTo(top), 80))
	end)
end

local function onBuilding(plot: Instance, building: Model)
	local theme = building:GetAttribute("Theme")
	if type(theme) ~= "string" then
		theme = plot:GetAttribute("Theme")
	end
	local themeId = if type(theme) == "string" then theme else ""
	local before = lastTheme[plot]
	lastTheme[plot] = themeId
	local grew = Pure.fresh(building:GetAttribute("GrewAt"), now(), FRESH_GROW)
	local newTheme = before ~= nil and before ~= themeId
	if not (grew or newTheme) or calm() then
		return
	end
	local pivot = pivotOf(building)
	if pivot and distanceTo(pivot.Position) > SEE_STUDS then
		return
	end
	-- Give the new pieces a moment to arrive (the server builds them all at once; they replicate in a burst).
	task.delay(0.25, function()
		if building.Parent and not calm() then
			growIn(building, grew and not newTheme)
		end
	end)
end

------------------------------------------------------------------------------------------------------------------
-- Each plot's building: its ambulance, helipad and lift
------------------------------------------------------------------------------------------------------------------

local watched: { [Instance]: { RBXScriptConnection } } = {}

local function forget(instance: Instance)
	local connections = watched[instance]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
		watched[instance] = nil
	end
end

local function watchPiece(instance: Instance)
	if watched[instance] then
		return
	end
	local name = instance.Name
	local connections: { RBXScriptConnection } = {}
	if name == "Ambulance" then
		table.insert(
			connections,
			instance:GetAttributeChangedSignal("ArriveAt"):Connect(function()
				if Pure.fresh(instance:GetAttribute("ArriveAt"), now(), FRESH_ARRIVE) then
					flashAmbulance(instance)
				end
			end)
		)
	elseif name == "HeliSpot" and instance:IsA("BasePart") then
		table.insert(
			connections,
			instance:GetAttributeChangedSignal("ArriveAt"):Connect(function()
				local at = instance:GetAttribute("ArriveAt")
				if Pure.fresh(at, now(), Pure.HELI_IN + Pure.HELI_STAY) then
					flyHeli(instance, at :: number)
				end
			end)
		)
	elseif name == "Lift" and instance:IsA("Model") then
		table.insert(
			connections,
			instance:GetAttributeChangedSignal("RideAt"):Connect(function()
				onRide(instance)
			end)
		)
	else
		return
	end
	watched[instance] = connections
	table.insert(
		connections,
		instance.AncestryChanged:Connect(function()
			if not instance:IsDescendantOf(Workspace) then
				forget(instance)
			end
		end)
	)
end

local PIECES = { Ambulance = true, HeliSpot = true, Lift = true }

local function watchBuilding(plot: Instance, building: Instance)
	if building.Name ~= "Building" or not building:IsA("Model") or watched[building] then
		return
	end
	local connections: { RBXScriptConnection } = {}
	watched[building] = connections
	table.insert(
		connections,
		building.DescendantAdded:Connect(function(descendant: Instance)
			if PIECES[descendant.Name] then
				task.defer(watchPiece, descendant)
			end
		end)
	)
	table.insert(
		connections,
		building.AncestryChanged:Connect(function()
			if not building:IsDescendantOf(Workspace) then
				forget(building)
			end
		end)
	)
	for _, descendant in building:GetDescendants() do
		if PIECES[descendant.Name] then
			watchPiece(descendant)
		end
	end
	onBuilding(plot, building)
end

local function watchPlot(plot: Instance)
	if not plot:IsA("Model") then
		return
	end
	plot.ChildAdded:Connect(function(child: Instance)
		task.defer(watchBuilding, plot, child)
	end)
	local building = plot:FindFirstChild("Building")
	if building then
		watchBuilding(plot, building)
	end
end

------------------------------------------------------------------------------------------------------------------
-- ✨ Nurses: ability sparkles and cooldown rings
------------------------------------------------------------------------------------------------------------------

type Nurse = {
	Model: Model,
	Connections: { RBXScriptConnection },
	Ring: ((number) -> ())?,
	RingGui: Instance?, -- what to remove when it leaves RING_STUDS (ours, or our frame inside T1's)
}

local nurses: { [Model]: Nurse } = {}
local ringLoop = false

local function abilityOf(model: Model): any
	local id = model:GetAttribute("Ability")
	if type(id) ~= "string" or id == "" then
		return nil
	end
	local row = rawget(ctx.Data.Abilities :: any, id)
	return if type(row) == "table" then row else nil
end

local function rootOf(model: Model): BasePart?
	local root = model.PrimaryPart or model:FindFirstChild("Root")
	return if root and root:IsA("BasePart") then root else nil
end

local function onAbility(model: Model)
	if not Pure.fresh(model:GetAttribute("AbilityAt"), now(), FRESH_ABILITY) then
		return
	end
	local root = rootOf(model)
	if not root or distanceTo(root.Position) > ABILITY_STUDS then
		return
	end
	local ability = abilityOf(model)
	local height = 4
	local ok, size = pcall(model.GetExtentsSize, model)
	if ok then
		height = (size :: Vector3).Y
	end
	local position = root.Position + Vector3.new(0, height + 0.5, 0)
	local rarity = model:GetAttribute("Rarity")
	sparkles(position, Kit.rarityColor(if type(rarity) == "string" then rarity else "Common"), 18)
	sound("Ability", Pure.earshot(distanceTo(position), ABILITY_SOUND_STUDS))
	-- The ability's icon floats up and fades (calm: it fades where it is).
	local quiet = calm()
	local attachment = anchorAt(position, 1.8)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(2.4, 2.4)
	gui.LightInfluence = 0
	gui.MaxDistance = ABILITY_STUDS
	gui.Parent = attachment
	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(1, 1)
	icon.TextScaled = true
	icon.Font = Theme.Font
	icon.Text = if ability then ability.Icon else "✨"
	icon.Parent = gui
	local fade = TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(icon, fade, { TextTransparency = 1 }):Play()
	if not quiet then
		TweenService:Create(gui, fade, { StudsOffsetWorldSpace = Vector3.new(0, 3, 0) }):Play()
	end
end

-- The cooldown ring over a nurse's head: inside T1's "AbilityRing" BillboardGui when it has one, else our own.
local function addRing(entry: Nurse)
	local model = entry.Model
	local ability = abilityOf(model)
	local root = rootOf(model)
	if not ability or not root then
		return
	end
	local rarity = model:GetAttribute("Rarity")
	local color = Kit.rarityColor(if type(rarity) == "string" then rarity else "Common")
	local holder: GuiObject
	local theirs = model:FindFirstChild("AbilityRing", true)
	if theirs and theirs:IsA("BillboardGui") then
		-- T1's billboard keeps its white disc and the ability icon; its coarse 8-step Fill disc (the server's ring
		-- for clients without this module) hides on this client, under our smooth RingFX.
		local disc = theirs:FindFirstChild("Ring")
		local fill = disc and disc:FindFirstChild("Fill")
		if fill and fill:IsA("GuiObject") then
			fill.Visible = false
		end
		local frame = Instance.new("Frame")
		frame.Name = "RingFX"
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.fromScale(1, 1)
		frame.Parent = theirs
		holder = frame
		entry.RingGui = frame
	else
		local height = 4
		local ok, size = pcall(model.GetExtentsSize, model)
		if ok then
			height = (size :: Vector3).Y
		end
		local gui = Instance.new("BillboardGui")
		gui.Name = "AbilityRingFX"
		gui.Size = UDim2.fromScale(1.8, 1.8)
		gui.StudsOffsetWorldSpace = Vector3.new(0, height + 1.2, 0)
		gui.LightInfluence = 0
		gui.MaxDistance = RING_STUDS
		gui.Adornee = root
		gui.Parent = model
		-- A white badge with the ability's icon, the beads round its edge.
		local badge = Instance.new("Frame")
		badge.Name = "Badge"
		badge.BackgroundColor3 = Theme.Colors.Paper
		badge.BackgroundTransparency = 0.1
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.fromScale(0.5, 0.5)
		badge.Size = UDim2.fromScale(0.62, 0.62)
		Kit.corner(badge, Theme.Radius.Round)
		Kit.stroke(badge, Theme.Colors.Outline, 1.5)
		badge.Parent = gui
		local icon = Instance.new("TextLabel")
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromScale(0.8, 0.8)
		icon.TextScaled = true
		icon.Font = Theme.Font
		icon.Text = ability.Icon
		icon.Parent = badge
		local frame = Instance.new("Frame")
		frame.Name = "RingFX"
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.fromScale(1, 1)
		frame.Parent = gui
		holder = frame
		entry.RingGui = gui
	end
	entry.Ring = Kit.ring(holder, color)
end

local function dropRing(entry: Nurse)
	if entry.RingGui then
		entry.RingGui:Destroy()
	end
	entry.RingGui = nil
	entry.Ring = nil
end

-- One loop while any ability nurse exists: rings for the ones near you (4 updates a second), a slow distance check
-- otherwise. It ends when no nurse is left.
local function runRings()
	if ringLoop then
		return
	end
	ringLoop = true
	task.spawn(function()
		while next(nurses) ~= nil do
			local here = listener()
			local near = false
			local clock = now()
			for model, entry in nurses do
				local root = rootOf(model)
				local close = root ~= nil and (root.Position - here).Magnitude <= RING_STUDS and abilityOf(model) ~= nil
				if close then
					near = true
					if not entry.Ring then
						addRing(entry)
					end
					local setter = entry.Ring
					if setter then
						setter(
							Kit.Juice.ringFraction(
								model:GetAttribute("AbilityReadyAt"),
								model:GetAttribute("AbilityCooldown"),
								clock
							)
						)
					end
				elseif entry.Ring then
					dropRing(entry)
				end
			end
			task.wait(if near then RING_STEP else RING_IDLE)
		end
		ringLoop = false
	end)
end

local function untrackNurse(model: Instance)
	local entry = nurses[model :: Model]
	if not entry then
		return
	end
	nurses[model :: Model] = nil
	for _, connection in entry.Connections do
		connection:Disconnect()
	end
	dropRing(entry)
end

local function trackNurse(instance: Instance)
	if not instance:IsA("Model") or nurses[instance] or instance:GetAttribute("NurseId") == nil then
		return
	end
	-- Belt riders are nurses too, but only workers on a plot carry an Ability (T1): wait for it.
	local model = instance
	local entry: Nurse = { Model = model, Connections = {}, Ring = nil, RingGui = nil }
	nurses[model] = entry
	table.insert(
		entry.Connections,
		model:GetAttributeChangedSignal("AbilityAt"):Connect(function()
			onAbility(model)
		end)
	)
	table.insert(
		entry.Connections,
		model:GetAttributeChangedSignal("Ability"):Connect(function()
			dropRing(entry) -- a new ability: the next pass draws its ring afresh
		end)
	)
	table.insert(
		entry.Connections,
		model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(Workspace) then
				untrackNurse(model)
			end
		end)
	)
	runRings()
end

------------------------------------------------------------------------------------------------------------------

function HospitalFX.init(context: Types.Ctx)
	ctx = context
	CollectionService:GetInstanceAddedSignal(MOTION_TAG):Connect(function(instance: Instance)
		task.defer(trackNurse, instance)
	end)
	CollectionService:GetInstanceRemovedSignal(MOTION_TAG):Connect(untrackNurse)
	for _, instance in CollectionService:GetTagged(MOTION_TAG) do
		trackNurse(instance)
	end
	task.spawn(function()
		local clinics = Workspace:WaitForChild("Clinics", 60)
		if not clinics then
			return
		end
		clinics.ChildAdded:Connect(watchPlot)
		for _, plot in clinics:GetChildren() do
			watchPlot(plot)
		end
	end)
end

return HospitalFX
