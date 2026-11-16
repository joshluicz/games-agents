--!strict
-- CreatureProps: the props, particles and face extras a sick creature acts with (Data/AilmentActing). Client only, a
-- library (not inited): Feel/CreatureActing builds a kit for each patient and drives it.
--   CreatureProps.build(model, acting): Kit?       props + emitters + face extras, sized to the creature (nil if the
--                                                  model isn't a CreatureBuilder creature: no Core)
--   CreatureProps.remove(kit, poof)                the props pop off (a sparkle when poof), the face and colours
--                                                  go back to the server's; the kit's emitters stay for the joy burst
--   CreatureProps.burst(kit, name, count)          Emit() from a named emitter (Bubbles, Achoo, Joy, Poof...)
--   CreatureProps.setFace(kit, name?)              an extra mouth (Hic | Achoo | Ooh | Chatter) over the sick "o"
--   CreatureProps.setSquint(kit, on)               eyes squeezed shut (> <)
--   CreatureProps.setAlert(kit, on, lift)          the "!" beside its head, lifted `lift` studs (a bounce)
--   CreatureProps.animate(kit, now, beat?, calm)   the props' own motion: orbiting stars, a honey drip, the tear,
--                                                  chattering teeth (beat = seconds into the current beat)
--
-- Everything made here exists on this client only (nothing replicates), never collides, and hangs on the creature's
-- Core or a paw with its own Weld/Motor6D, so it follows the body's acting. Sizes are in units (CreatureBuilder: Scale 1
-- is about 3 units tall) times the creature's BuildScale. Sockets and joints: CreatureBuilder's header.
-- Rated Minimal: tissues, plasters, a scarf, honey, a little mask. Nothing gross, scary or medical-needle-ish.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Palette = require(Shared:WaitForChild("Palette"))

local Candy = Palette.Candy

local CreatureProps = {}

type Acting = {
	Motion: string,
	Every: { number },
	Props: { string },
	Burst: string?,
	Ambient: string?,
	Face: string?,
	Squint: boolean?,
	Cheeks: string?,
	Glow: number?,
}

export type Kit = {
	Model: Model,
	Core: BasePart,
	Unit: number, -- studs per unit (the creature's BuildScale)
	Folder: Folder, -- every prop part lives here
	Parts: { BasePart },
	Motors: { [string]: Motor6D }, -- props that move: Glass, Tear, Drip
	Emitters: { [string]: ParticleEmitter }, -- bursts and ambients by name
	Stars: { Attachment }, -- the dizzy stars' orbit points
	StarCentre: Vector3, -- relative to Core
	StarRadius: number,
	Faces: { [string]: Frame }, -- extra mouths
	Face: string?, -- the extra mouth showing now
	Squints: { SurfaceGui },
	Squinting: boolean,
	Eyes: { BasePart },
	Alert: BillboardGui?,
	AlertBase: Vector3,
	Restore: { () -> () }, -- undo the cheek tint, the dimmed glow...
	Holds: { [string]: boolean }, -- "R" / "L": a paw holding something (CreatureActing waves the other)
	Live: boolean, -- props on
}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds" -- a four-point twinkle
local SMOKE = "rbxasset://textures/particles/smoke_main.dds" -- a soft puff
local RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds" -- a soft thin ring: a bubble
local SOFT_DOT = "rbxasset://textures/particles/explosion01_implosion_main.dds" -- a soft round dot

local WHITE = Palette.White
local INK = Palette.Ink
local EYE = Palette.Outline
local PLASTER = Color3.fromRGB(255, 246, 232) -- a cartoon plaster: creamy white with a pink pad
local PLASTER_PAD = Color3.fromRGB(255, 176, 196)
local TISSUE = Color3.fromRGB(250, 252, 255)
local RED_NOSE = Color3.fromRGB(255, 104, 136)
local MASK = Color3.fromRGB(190, 232, 255)
local GLASS = Color3.fromRGB(214, 246, 255)
local WATER = Color3.fromRGB(110, 200, 255)
local CORK = Color3.fromRGB(201, 145, 92)
local HONEY = Color3.fromRGB(255, 178, 30)
local MUD = Color3.fromRGB(122, 74, 42)
local SCARF = Candy.Red
local ICE = Color3.fromRGB(236, 252, 255)
local MUFF = Color3.fromRGB(255, 140, 198)
local TEAR = Color3.fromRGB(143, 216, 255)
local MOTE = Color3.fromRGB(185, 168, 216)

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Candy.Pink),
	ColorSequenceKeypoint.new(0.25, Candy.Yellow),
	ColorSequenceKeypoint.new(0.5, Candy.Lime),
	ColorSequenceKeypoint.new(0.75, Candy.Cyan),
	ColorSequenceKeypoint.new(1, Candy.Purple),
})

------------------------------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------------------------------

local function socketCf(kit: Kit, name: string, fallback: CFrame): CFrame
	local socket = kit.Core:FindFirstChild(name)
	if socket and socket:IsA("Attachment") then
		return socket.CFrame
	end
	return fallback
end

local function makePart(kit: Kit, name: string, shape: string, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size * kit.Unit
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	if shape == "Ball" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	elseif shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	end
	table.insert(kit.Parts, p)
	return p
end

-- Hangs `p` on `holder` at `cf` (relative to the holder). A named motor can be animated through its Transform.
local function hang(kit: Kit, p: BasePart, holder: BasePart, cf: CFrame, motor: string?)
	p.CFrame = holder.CFrame * cf
	local joint: JointInstance = if motor then Instance.new("Motor6D") else Instance.new("Weld")
	joint.Part0 = holder
	joint.Part1 = p
	joint.C0 = cf
	joint.Parent = p
	p.Parent = kit.Folder
	if motor then
		kit.Motors[motor] = joint :: Motor6D
	end
end

-- Units to studs, for an offset.
local function at(kit: Kit, x: number, y: number, z: number): CFrame
	local u = kit.Unit
	return CFrame.new(x * u, y * u, z * u)
end

-- Where a paw holds something: the HandSocket of an arm (a wing or flipper holds it in front of the belly instead).
-- `upright` undoes the paw's resting lift (CreatureActing holds that paw forward by HOLD_PITCH).
local HOLD_PITCH = 0.55
CreatureProps.HOLD_PITCH = HOLD_PITCH
local function paw(kit: Kit, side: string): (BasePart, CFrame)
	local motor = kit.Core:FindFirstChild("Arm" .. side .. "Joint")
	if motor and motor:IsA("Motor6D") then
		local arm = motor.Part1
		local hand = arm and arm:FindFirstChild("HandSocket")
		if arm and arm.Name == "Arm" and hand and hand:IsA("Attachment") then
			kit.Holds[side] = true
			return arm, hand.CFrame * CFrame.Angles(-HOLD_PITCH, 0, 0)
		end
	end
	local x = if side == "R" then 0.5 else -0.5
	local belly = socketCf(kit, "BellySocket", at(kit, 0, 0.9, -1.2))
	return kit.Core, belly * at(kit, x, 0.15, -0.3)
end

local function emitter(kit: Kit, name: string, parent: Attachment, texture: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = texture
	e.Rate = 0
	e.Enabled = false
	e.LockedToPart = false
	e.Parent = parent
	kit.Emitters[name] = e
	return e
end

local function size(kit: Kit, from: number, to: number): NumberSequence
	local u = kit.Unit
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, from * u), NumberSequenceKeypoint.new(1, to * u) })
end

local function fade(from: number, to: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, from), NumberSequenceKeypoint.new(1, to) })
end

-- An Attachment on Core at a socket (for emitters).
local function point(kit: Kit, name: string, cf: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.Name = "Act" .. name
	a.CFrame = cf
	a.Parent = kit.Core
	return a
end

------------------------------------------------------------------------------------------------------------------
-- The props (AilmentActing.Vocabulary.Props)
------------------------------------------------------------------------------------------------------------------

local PROPS: { [string]: (kit: Kit) -> () } = {}

PROPS.WaterGlass = function(kit)
	local holder, cf = paw(kit, "R")
	local upright = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder's axis is X: stand it up
	local glass = makePart(kit, "Glass", "Cylinder", Vector3.new(0.62, 0.42, 0.42), GLASS)
	glass.Transparency = 0.45
	glass.Reflectance = 0.2
	hang(kit, glass, holder, cf * at(kit, 0, 0.12, -0.14) * upright, "Glass")
	local water = makePart(kit, "Water", "Cylinder", Vector3.new(0.4, 0.36, 0.36), WATER)
	water.Transparency = 0.15
	hang(kit, water, glass, CFrame.new(-0.1 * kit.Unit, 0, 0))
end

PROPS.Tissue = function(kit)
	local holder, cf = paw(kit, "R")
	local tissue = makePart(kit, "Tissue", "Ball", Vector3.new(0.5, 0.6, 0.12), TISSUE)
	hang(kit, tissue, holder, cf * at(kit, 0, 0.2, -0.16) * CFrame.Angles(0, 0, 0.2))
	local tuft = makePart(kit, "TissueTuft", "Ball", Vector3.new(0.44, 0.26, 0.22), TISSUE)
	hang(kit, tuft, tissue, at(kit, 0.02, 0.28, 0))
end

PROPS.RedNose = function(kit)
	local nose = makePart(kit, "RedNose", "Ball", Vector3.new(0.3, 0.24, 0.22), RED_NOSE)
	hang(kit, nose, kit.Core, socketCf(kit, "NoseSocket", at(kit, 0, 1.6, -1.3)) * at(kit, 0, 0, -0.06))
end

PROPS.Mask = function(kit)
	local mask = makePart(kit, "Mask", "Ball", Vector3.new(0.98, 0.62, 0.22), MASK)
	hang(kit, mask, kit.Core, socketCf(kit, "FaceSocket", at(kit, 0, 1.1, -1.3)) * at(kit, 0, 0.04, -0.05))
	for _, side in { -1, 1 } do -- the ear loops, as two soft white bands toward the sides
		local loop = makePart(kit, "MaskLoop", "Ball", Vector3.new(0.42, 0.07, 0.07), WHITE)
		hang(kit, loop, mask, at(kit, side * 0.62, 0.06, 0.1) * CFrame.Angles(0, -side * 0.6, 0))
	end
end

PROPS.Bandage = function(kit)
	local brow = socketCf(kit, "BrowSocket", at(kit, 0, 2.3, -0.9))
	local body = kit.Model:FindFirstChild("Body")
	local skin = if body and body:IsA("BasePart") then body.Color:Lerp(WHITE, 0.25) else WHITE
	local bump = makePart(kit, "Bump", "Ball", Vector3.new(0.46, 0.38, 0.26), skin) -- a soft cartoon bump
	hang(kit, bump, kit.Core, brow * at(kit, 0, 0, 0.03))
	for _, turn in { 0.7, -0.7 } do
		local strip = makePart(kit, "Bandage", "Ball", Vector3.new(0.82, 0.22, 0.06), PLASTER)
		hang(kit, strip, kit.Core, brow * at(kit, 0, 0, -0.12) * CFrame.Angles(0, 0, turn))
	end
	local pad = makePart(kit, "BandagePad", "Ball", Vector3.new(0.2, 0.2, 0.08), PLASTER_PAD)
	hang(kit, pad, kit.Core, brow * at(kit, 0, 0, -0.14))
end

PROPS.DizzyStars = function(kit)
	local head = socketCf(kit, "HeadSocket", at(kit, 0, 2.8, 0))
	local radius = kit.Model:GetAttribute("HeadRadius")
	kit.StarCentre = head.Position + Vector3.new(0, 0.3 * kit.Unit, 0)
	kit.StarRadius = if type(radius) == "number" then radius * 0.8 else 1.1 * kit.Unit
	for i = 1, 3 do
		local a = Instance.new("Attachment")
		a.Name = "ActStar"
		a.Position = kit.StarCentre
			+ Vector3.new(math.cos(i * 2.1) * kit.StarRadius, 0, math.sin(i * 2.1) * kit.StarRadius)
		a.Parent = kit.Core
		local gui = Instance.new("BillboardGui")
		gui.Name = "Star"
		gui.Size = UDim2.fromScale(0.55 * kit.Unit, 0.55 * kit.Unit) -- studs
		gui.LightInfluence = 0
		gui.MaxDistance = 80
		gui.Parent = a
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Palette.BodyFont
		label.TextScaled = true
		label.Text = "⭐"
		label.Parent = gui
		table.insert(kit.Stars, a)
	end
end

PROPS.CheekPlaster = function(kit)
	local cheek = socketCf(kit, "CheekLSocket", at(kit, -0.9, 1.1, -1.1))
	local plaster = makePart(kit, "Plaster", "Ball", Vector3.new(0.64, 0.26, 0.06), PLASTER)
	hang(kit, plaster, kit.Core, cheek * at(kit, 0, 0, -0.02) * CFrame.Angles(0, 0, -0.4))
	local pad = makePart(kit, "PlasterPad", "Ball", Vector3.new(0.22, 0.2, 0.07), PLASTER_PAD)
	hang(kit, pad, plaster, CFrame.new())
end

PROPS.Tear = function(kit) -- one soft tear, shown only while it rolls (CreatureProps.animate)
	local eye = socketCf(kit, "EyeLSocket", at(kit, -0.5, 1.5, -1.3))
	local tear = makePart(kit, "Tear", "Ball", Vector3.new(0.14, 0.2, 0.1), TEAR)
	tear.Transparency = 1
	tear.Reflectance = 0.2
	hang(kit, tear, kit.Core, eye * at(kit, 0.12, -0.34, 0.02), "Tear")
end

PROPS.EmptyJar = function(kit)
	local holder, cf = paw(kit, "R")
	local upright = CFrame.Angles(0, 0, math.pi / 2)
	local jar = makePart(kit, "Jar", "Cylinder", Vector3.new(0.6, 0.5, 0.5), GLASS)
	jar.Transparency = 0.5
	jar.Reflectance = 0.25
	hang(kit, jar, holder, cf * at(kit, 0, 0.16, -0.16) * upright)
	local cork = makePart(kit, "Cork", "Cylinder", Vector3.new(0.14, 0.36, 0.36), CORK)
	hang(kit, cork, jar, CFrame.new(0.36 * kit.Unit, 0, 0))
end

PROPS.Honey = function(kit)
	local top = socketCf(kit, "HeadSocket", at(kit, 0, 2.8, 0))
	local brow = socketCf(kit, "BrowSocket", at(kit, 0, 2.3, -0.9))
	local blob = makePart(kit, "Honey", "Ball", Vector3.new(0.98, 0.42, 0.86), HONEY)
	blob.Reflectance = 0.15
	hang(kit, blob, kit.Core, top * at(kit, 0, 0.02, -0.12))
	for _, side in { -1, 1 } do -- two drips running from the blob down the forehead
		local drip = makePart(kit, "HoneyDrip", "Ball", Vector3.new(0.22, 0.56, 0.16), HONEY)
		drip.Reflectance = 0.15
		hang(kit, drip, kit.Core, brow * at(kit, side * 0.28, 0.34, 0.03))
	end
	local drop = makePart(kit, "HoneyDrop", "Ball", Vector3.new(0.16, 0.2, 0.16), HONEY)
	drop.Reflectance = 0.15
	hang(kit, drop, kit.Core, brow * at(kit, 0.28, 0.04, -0.02), "Drip")
end

PROPS.MudSpots = function(kit)
	local belly = socketCf(kit, "BellySocket", at(kit, 0, 0.9, -1.2))
	local cheek = socketCf(kit, "CheekRSocket", at(kit, 0.9, 1.1, -1.1))
	local top = socketCf(kit, "HeadSocket", at(kit, 0, 2.8, 0))
	local spots = {
		{ belly * at(kit, -0.3, 0.12, 0.02), Vector3.new(0.5, 0.38, 0.08) },
		{ belly * at(kit, 0.32, -0.2, 0.02), Vector3.new(0.34, 0.28, 0.08) },
		{ cheek * at(kit, 0.14, 0.14, 0.01), Vector3.new(0.26, 0.22, 0.06) },
		{ top * at(kit, 0.28, -0.04, 0.1), Vector3.new(0.5, 0.14, 0.42) },
	}
	for _, spot in spots do
		local splat = makePart(kit, "Mud", "Ball", spot[2] :: Vector3, MUD)
		hang(kit, splat, kit.Core, spot[1] :: CFrame)
	end
end

PROPS.Scarf = function(kit)
	local neck = socketCf(kit, "NeckSocket", at(kit, 0, 1, 0))
	local neckSize = kit.Model:GetAttribute("NeckSize")
	local span = if typeof(neckSize) == "Vector3" then neckSize else Vector3.new(2.4, 0, 2.2) * kit.Unit
	local u = kit.Unit
	local band = makePart(kit, "Scarf", "Ball", Vector3.new(1, 0.5, 1), SCARF)
	band.Size = Vector3.new(span.X + 0.3 * u, 0.5 * u, span.Z + 0.3 * u)
	hang(kit, band, kit.Core, neck)
	local tail = makePart(kit, "ScarfTail", "Ball", Vector3.new(0.4, 0.95, 0.14), SCARF)
	hang(kit, tail, band, CFrame.new(0.34 * u, -0.42 * u, -span.Z / 2 - 0.12 * u) * CFrame.Angles(0, 0, 0.18))
	local stripe = makePart(kit, "ScarfStripe", "Ball", Vector3.new(0.42, 0.14, 0.16), WHITE)
	hang(kit, stripe, tail, CFrame.new(0, -0.22 * u, 0))
end

PROPS.IceNose = function(kit)
	local nose = socketCf(kit, "NoseSocket", at(kit, 0, 1.6, -1.3))
	local ice = makePart(kit, "IceNose", "Ball", Vector3.new(0.46, 0.38, 0.34), ICE)
	ice.Transparency = 0.1
	ice.Reflectance = 0.3
	hang(kit, ice, kit.Core, nose * at(kit, 0, 0, -0.05))
	local drop = makePart(kit, "IceDrop", "Ball", Vector3.new(0.12, 0.2, 0.12), ICE)
	drop.Transparency = 0.2
	hang(kit, drop, ice, at(kit, 0.04, -0.2, -0.04))
end

PROPS.Earmuffs = function(kit)
	for _, side in { "R", "L" } do
		local x = if side == "R" then 1.4 else -1.4
		local ear = socketCf(kit, "Ear" .. side .. "Socket", at(kit, x, 1.9, 0))
		local muff = makePart(kit, "Earmuff", "Ball", Vector3.new(0.6, 0.66, 0.36), MUFF)
		hang(kit, muff, kit.Core, ear * at(kit, 0, 0, -0.06))
	end
end

------------------------------------------------------------------------------------------------------------------
-- Particles (AilmentActing.Vocabulary.Bursts and Ambients), and the joy and poof bursts
------------------------------------------------------------------------------------------------------------------

local function addEmitters(kit: Kit, acting: Acting)
	local face = point(kit, "Face", socketCf(kit, "FaceSocket", at(kit, 0, 1.1, -1.3)))
	local nose = point(kit, "Nose", socketCf(kit, "NoseSocket", at(kit, 0, 1.6, -1.3)))
	local head = point(kit, "Head", socketCf(kit, "HeadSocket", at(kit, 0, 2.8, 0)))
	local belly = point(kit, "Belly", socketCf(kit, "BellySocket", at(kit, 0, 0.9, -1.2)))
	local middle = point(kit, "Middle", at(kit, 0, 1.4, 0))

	local burst = acting.Burst
	if burst == "Bubbles" then
		local e = emitter(kit, "Bubbles", face, RING)
		e.Color = ColorSequence.new(Candy.Cyan, Candy.Pink)
		e.LightEmission = 0.3
		e.Size = size(kit, 0.22, 0.42)
		e.Transparency = fade(0.05, 1)
		e.Lifetime = NumberRange.new(0.8, 1.2)
		e.Speed = NumberRange.new(1.2 * kit.Unit, 2 * kit.Unit)
		e.SpreadAngle = Vector2.new(25, 25)
		e.Acceleration = Vector3.new(0, 2, 0)
		e.Drag = 1.5
		local spout = kit.Core:FindFirstChild("SpoutSocket")
		if spout and spout:IsA("Attachment") then -- a teapot hiccups steam too
			local steam = emitter(kit, "Steam", spout, SMOKE)
			steam.Color = ColorSequence.new(WHITE)
			steam.Size = size(kit, 0.2, 0.6)
			steam.Transparency = fade(0.3, 1)
			steam.Lifetime = NumberRange.new(0.6, 0.9)
			steam.Speed = NumberRange.new(1 * kit.Unit, 1.6 * kit.Unit)
			steam.EmissionDirection = Enum.NormalId.Top
			steam.SpreadAngle = Vector2.new(15, 15)
		end
	elseif burst == "Achoo" then
		local e = emitter(kit, "Achoo", nose, SMOKE)
		e.Color = ColorSequence.new(WHITE, Color3.fromRGB(255, 228, 240))
		e.Size = size(kit, 0.35, 1.1)
		e.Transparency = fade(0.15, 1)
		e.Lifetime = NumberRange.new(0.5, 0.8)
		e.Speed = NumberRange.new(5 * kit.Unit, 8 * kit.Unit)
		e.SpreadAngle = Vector2.new(25, 25)
		e.Drag = 5
		e.Rotation = NumberRange.new(0, 360)
	elseif burst == "CoughPuff" then
		local e = emitter(kit, "CoughPuff", face, SMOKE)
		e.Color = ColorSequence.new(Color3.fromRGB(236, 230, 255))
		e.Size = size(kit, 0.22, 0.6)
		e.Transparency = fade(0.3, 1)
		e.Lifetime = NumberRange.new(0.45, 0.7)
		e.Speed = NumberRange.new(2 * kit.Unit, 3.5 * kit.Unit)
		e.SpreadAngle = Vector2.new(20, 20)
		e.Drag = 3
	elseif burst == "Mud" then
		local e = emitter(kit, "Mud", belly, SOFT_DOT)
		e.Color = ColorSequence.new(MUD)
		e.LightEmission = 0
		e.LightInfluence = 1
		e.Size = size(kit, 0.16, 0.1)
		e.Transparency = fade(0, 0.3)
		e.Lifetime = NumberRange.new(0.45, 0.7)
		e.Speed = NumberRange.new(4 * kit.Unit, 6 * kit.Unit)
		e.SpreadAngle = Vector2.new(100, 60)
		e.Acceleration = Vector3.new(0, -18, 0)
	elseif burst == "Breath" then
		local e = emitter(kit, "Breath", face, SMOKE)
		e.Color = ColorSequence.new(WHITE)
		e.Size = size(kit, 0.18, 0.55)
		e.Transparency = fade(0.35, 1)
		e.Lifetime = NumberRange.new(0.9, 1.3)
		e.Speed = NumberRange.new(0.8 * kit.Unit, 1.4 * kit.Unit)
		e.SpreadAngle = Vector2.new(15, 15)
		e.Acceleration = Vector3.new(0, 0.6, 0)
		e.Drag = 1
	elseif burst == "Frost" then
		local e = emitter(kit, "Frost", nose, SPARKLE)
		e.Color = ColorSequence.new(WHITE, Candy.Cyan)
		e.LightEmission = 0.6
		e.Size = size(kit, 0.2, 0)
		e.Lifetime = NumberRange.new(0.6, 1)
		e.Speed = NumberRange.new(1 * kit.Unit, 2 * kit.Unit)
		e.SpreadAngle = Vector2.new(180, 180)
		e.RotSpeed = NumberRange.new(-90, 90)
	end

	local ambient = acting.Ambient
	if ambient == "Motes" or burst == "Motes" then -- a lost glow drifting away as dim grey-lilac motes
		local e = emitter(kit, "Motes", head, SOFT_DOT)
		e.Color = ColorSequence.new(MOTE)
		e.LightEmission = 0.3
		e.Size = size(kit, 0.12, 0.04)
		e.Transparency = fade(0.2, 1)
		e.Lifetime = NumberRange.new(1.6, 2.4)
		e.Speed = NumberRange.new(0.3 * kit.Unit, 0.6 * kit.Unit)
		e.SpreadAngle = Vector2.new(70, 70)
		e.Acceleration = Vector3.new(0, -0.6, 0)
	end
	if ambient == "Snowflakes" then
		local e = emitter(kit, "Snowflakes", nose, SPARKLE)
		e.Color = ColorSequence.new(WHITE, Candy.Cyan)
		e.LightEmission = 0.5
		e.Size = size(kit, 0.12, 0.04)
		e.Lifetime = NumberRange.new(1, 1.6)
		e.Speed = NumberRange.new(0.2 * kit.Unit, 0.5 * kit.Unit)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0, -0.8, 0)
	end

	local joy = emitter(kit, "Joy", middle, SPARKLE) -- the cure: candy sparkles
	joy.Color = RAINBOW
	joy.LightEmission = 0.6
	joy.Size = size(kit, 0.32, 0)
	joy.Lifetime = NumberRange.new(0.6, 1)
	joy.Speed = NumberRange.new(4, 7)
	joy.SpreadAngle = Vector2.new(180, 180)
	joy.Acceleration = Vector3.new(0, -4, 0)
	joy.RotSpeed = NumberRange.new(-120, 120)
	local poof = emitter(kit, "Poof", middle, SPARKLE) -- the props popping off
	poof.Color = ColorSequence.new(WHITE, Candy.Pink)
	poof.LightEmission = 0.5
	poof.Size = size(kit, 0.26, 0)
	poof.Lifetime = NumberRange.new(0.4, 0.7)
	poof.Speed = NumberRange.new(3, 5)
	poof.SpreadAngle = Vector2.new(180, 180)
end

------------------------------------------------------------------------------------------------------------------
-- The face extras: extra mouths over the sick "o", squeezed-shut eyes, warmer or colder cheeks, a dimmed glow
------------------------------------------------------------------------------------------------------------------

local function mouthFrame(gui: Instance, name: string, w: number, h: number, color: Color3): Frame
	local f = Instance.new("Frame")
	f.Name = "Act" .. name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(w, h)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = 5
	f.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	f.Parent = gui
	return f
end

local function addFace(kit: Kit)
	local mouth = kit.Model:FindFirstChild("Mouth")
	local gui = mouth and mouth:FindFirstChild("MouthGui")
	if gui then
		-- Each one covers the server's small sick "o" completely, so it can simply be drawn on top.
		kit.Faces.Hic = mouthFrame(gui, "Hic", 0.22, 0.48, INK)
		kit.Faces.Ooh = mouthFrame(gui, "Ooh", 0.27, 0.58, INK)
		kit.Faces.Achoo = mouthFrame(gui, "Achoo", 0.38, 0.88, INK)
		local teeth = mouthFrame(gui, "Chatter", 0.46, 0.52, WHITE)
		local round = teeth:FindFirstChildOfClass("UICorner")
		if round then
			round.CornerRadius = UDim.new(0.3, 0)
		end
		local stroke = Instance.new("UIStroke")
		stroke.Color = INK
		stroke.Thickness = 4
		stroke.Parent = teeth
		local line = Instance.new("Frame")
		line.Name = "Line"
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.fromScale(0.5, 0.5)
		line.Size = UDim2.fromScale(0.9, 0.12)
		line.BackgroundColor3 = INK
		line.BorderSizePixel = 0
		line.ZIndex = 6
		line.Parent = teeth
		kit.Faces.Chatter = teeth
	end

	for _, child in kit.Model:GetChildren() do
		if child:IsA("BasePart") then
			if child.Name == "Eye" or child.Name == "EyeShine" or child.Name == "EyeTint" then
				table.insert(kit.Eyes, child)
			elseif child.Name == "Lid" then
				-- A squeezed-shut eye: ">" on your left, "<" on your right (> <).
				local right = kit.Core.CFrame:PointToObjectSpace(child.Position).X > 0
				local gui2 = Instance.new("SurfaceGui")
				gui2.Name = "ActSquint"
				gui2.Face = Enum.NormalId.Front
				gui2.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
				gui2.PixelsPerStud = 100
				gui2.LightInfluence = 0.4
				gui2.MaxDistance = 70
				gui2.Enabled = false
				gui2.Parent = child
				local sign = if right then 1 else -1
				for _, half in { -1, 1 } do
					local bar = Instance.new("Frame")
					bar.AnchorPoint = Vector2.new(0.5, 0.5)
					bar.Position = UDim2.fromScale(0.5, 0.42 + half * 0.14)
					bar.Size = UDim2.fromScale(0.56, 0.16)
					bar.Rotation = -half * sign * 22
					bar.BackgroundColor3 = EYE
					bar.BorderSizePixel = 0
					local corner = Instance.new("UICorner")
					corner.CornerRadius = UDim.new(0.5, 0)
					corner.Parent = bar
					bar.Parent = gui2
				end
				table.insert(kit.Squints, gui2)
			end
		end
	end
end

local function tintCheeks(kit: Kit, hexColor: string)
	local ok, color = pcall(Color3.fromHex, hexColor)
	if not ok then
		return
	end
	for _, child in kit.Model:GetChildren() do
		if child:IsA("BasePart") and child.Name == "Cheek" then
			local before = child.Color
			child.Color = before:Lerp(color, 0.85)
			table.insert(kit.Restore, function()
				child.Color = before
			end)
		end
	end
end

-- A night creature's glow, dimmed while it's ill (its glow is what's lost); its Neon tips go dull too.
local function dimGlow(kit: Kit, amount: number)
	local root = kit.Model.PrimaryPart
	local fx = root and root:FindFirstChild("FX")
	local light = fx and fx:FindFirstChild("NightGlow")
	if light and light:IsA("PointLight") then
		local before = light.Brightness
		light.Brightness = before * amount
		table.insert(kit.Restore, function()
			light.Brightness = before
		end)
	end
	local halo = kit.Model:FindFirstChild("NightHalo")
	if halo and halo:IsA("Highlight") then
		local fill, outline = halo.FillTransparency, halo.OutlineTransparency
		halo.FillTransparency = 1 - (1 - fill) * amount
		halo.OutlineTransparency = 1 - (1 - outline) * amount
		table.insert(kit.Restore, function()
			halo.FillTransparency = fill
			halo.OutlineTransparency = outline
		end)
	end
	for _, child in kit.Model:GetChildren() do
		if child:IsA("BasePart") and child.Material == Enum.Material.Neon then
			child.Material = Enum.Material.SmoothPlastic
			table.insert(kit.Restore, function()
				child.Material = Enum.Material.Neon
			end)
		end
	end
end

local function addAlert(kit: Kit)
	local radius = kit.Model:GetAttribute("HeadRadius")
	local r = if type(radius) == "number" then radius else 1.4 * kit.Unit
	local head = socketCf(kit, "HeadSocket", at(kit, 0, 2.8, 0))
	-- Beside its head on its left (your right), the side it waves from.
	kit.AlertBase = Vector3.new(-(r + 0.55 * kit.Unit), head.Position.Y - 0.25 * kit.Unit, 0)
	local a = Instance.new("Attachment")
	a.Name = "ActAlert"
	a.Position = kit.AlertBase
	a.Parent = kit.Core
	local gui = Instance.new("BillboardGui")
	gui.Name = "Alert"
	gui.Size = UDim2.fromScale(1.5, 1.5) -- studs
	gui.LightInfluence = 0
	gui.MaxDistance = 70
	gui.Enabled = false
	gui.Parent = a
	local disc = Instance.new("Frame")
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromScale(0.82, 0.82)
	disc.BackgroundColor3 = Candy.Red
	disc.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = disc
	Palette.outlineShape(disc, 3)
	disc.Parent = gui
	local mark = Instance.new("TextLabel")
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, 0.54)
	mark.Size = UDim2.fromScale(0.8, 0.8)
	mark.BackgroundTransparency = 1
	mark.Font = Palette.DisplayFont
	mark.TextScaled = true
	mark.TextColor3 = WHITE
	mark.Text = "!"
	Palette.outlineText(mark)
	mark.Parent = disc
	kit.Alert = gui
end

------------------------------------------------------------------------------------------------------------------
-- API
------------------------------------------------------------------------------------------------------------------

function CreatureProps.build(model: Model, acting: Acting): Kit?
	local core = model:FindFirstChild("Core")
	if not (core and core:IsA("BasePart")) then
		return nil
	end
	local unit = model:GetAttribute("BuildScale")
	local folder = Instance.new("Folder")
	folder.Name = "ActingProps"
	folder.Parent = model
	local kit: Kit = {
		Model = model,
		Core = core,
		Unit = if type(unit) == "number" and unit > 0 then unit else 1.6,
		Folder = folder,
		Parts = {},
		Motors = {},
		Emitters = {},
		Stars = {},
		StarCentre = Vector3.zero,
		StarRadius = 1,
		Faces = {},
		Face = nil,
		Squints = {},
		Squinting = false,
		Eyes = {},
		Alert = nil,
		AlertBase = Vector3.zero,
		Restore = {},
		Holds = {},
		Live = true,
	}
	for _, name in acting.Props do
		local builder = PROPS[name]
		if builder then
			local ok, err = pcall(builder, kit)
			if not ok then
				warn("[CreatureProps] " .. name .. ": " .. tostring(err))
			end
		end
	end
	addEmitters(kit, acting)
	addFace(kit)
	addAlert(kit)
	if acting.Cheeks then
		tintCheeks(kit, acting.Cheeks)
	end
	if acting.Glow and acting.Glow < 1 then
		dimGlow(kit, acting.Glow)
	end
	return kit
end

function CreatureProps.has(name: string): boolean
	return PROPS[name] ~= nil
end

function CreatureProps.burst(kit: Kit, name: string, count: number)
	local e = kit.Emitters[name]
	if e and count > 0 then
		e:Emit(count)
	end
end

function CreatureProps.ambient(kit: Kit, on: boolean, calm: boolean)
	for _, name in { "Motes", "Snowflakes" } do
		local e = kit.Emitters[name]
		if e then
			e.Rate = if calm then 0.6 else 1.4
			e.Enabled = on
		end
	end
end

function CreatureProps.setFace(kit: Kit, name: string?)
	if kit.Face == name then
		return
	end
	local current = kit.Face
	local old = if current then kit.Faces[current] else nil
	if old then
		old.Visible = false
	end
	local new = if name then kit.Faces[name] else nil
	if new then
		new.Visible = true
	end
	kit.Face = name
end

function CreatureProps.setSquint(kit: Kit, on: boolean)
	if kit.Squinting == on then
		return
	end
	kit.Squinting = on
	for _, eye in kit.Eyes do
		eye.LocalTransparencyModifier = if on then 1 else 0
	end
	for _, gui in kit.Squints do
		gui.Enabled = on
	end
end

function CreatureProps.setAlert(kit: Kit, on: boolean, lift: number)
	local gui = kit.Alert
	if not gui then
		return
	end
	if gui.Enabled ~= on then
		gui.Enabled = on
	end
	local holder = gui.Parent
	if on and holder and holder:IsA("Attachment") then
		holder.Position = kit.AlertBase + Vector3.new(0, lift, 0)
	end
end

-- The props' own motion. `beat` = seconds into the current beat (nil between beats).
function CreatureProps.animate(kit: Kit, now: number, beat: number?, calm: boolean)
	if not kit.Live then
		return
	end
	local u = kit.Unit
	if #kit.Stars > 0 then
		local spin = if calm then 0 else now * 1.6
		for i, a in kit.Stars do
			local angle = spin + i * (math.pi * 2 / 3)
			local bob = if calm then 0 else math.sin(now * 3 + i) * 0.08 * u
			a.Position = kit.StarCentre
				+ Vector3.new(math.cos(angle) * kit.StarRadius, bob, math.sin(angle) * kit.StarRadius * 0.6)
		end
	end
	local drip = kit.Motors.Drip
	if drip then -- a honey drop slides slowly down and is gone, then another
		local t = (now % 2.6) / 2.6
		drip.Transform = CFrame.new(0, -0.45 * u * t * t, 0)
		local part = drip.Part1
		if part then
			part.Transparency = if t > 0.85 then (t - 0.85) / 0.15 else 0
		end
	end
	local tear = kit.Motors.Tear
	if tear then -- rolls down the cheek during a sniffle beat, from 0.1 s to 1 s
		local part = tear.Part1
		local t = if beat then (beat - 0.1) / 0.9 else -1
		if part then
			if t >= 0 and t <= 1 then
				tear.Transform = CFrame.new(0, -0.42 * u * t, 0)
				part.Transparency = if t > 0.75 then (t - 0.75) / 0.25 else 0.1
			elseif part.Transparency ~= 1 then
				part.Transparency = 1
			end
		end
	end
	local teeth = kit.Faces.Chatter
	if teeth and teeth.Visible then
		local shake = if calm then 0 else math.sin(now * 40) * 0.03
		teeth.Position = UDim2.fromScale(0.5 + shake, 0.5)
	end
end

function CreatureProps.remove(kit: Kit, poof: boolean)
	if not kit.Live then
		return
	end
	kit.Live = false
	if poof then
		CreatureProps.burst(kit, "Poof", 16)
	end
	CreatureProps.setFace(kit, nil)
	CreatureProps.setSquint(kit, false)
	CreatureProps.setAlert(kit, false, 0)
	CreatureProps.ambient(kit, false, false)
	for _, undo in kit.Restore do
		pcall(undo)
	end
	table.clear(kit.Restore)
	kit.Folder:Destroy()
	for _, a in kit.Stars do
		a:Destroy()
	end
	table.clear(kit.Stars)
	table.clear(kit.Motors)
end

return CreatureProps
