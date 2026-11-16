--!strict
-- Builds a patient creature (build plan Task 1, §B1 kit overrides). Server only; Patients is the caller.
--   CreatureBuilder.build(patientId, variant?): Model
--     An original placeholder made from the patient's `Look` (Data/Patients, or Data/Regulars for a regular,
--     who uses their own id): a chunky round toy with a glossy shine, big shiny eyes (two glints and a soft coloured
--     glow at the bottom), brows, rosy cheeks, a mouth that can be sick, happy or sad, little arms, ears, a hat, an
--     extra (wings, tail...) and the species' own Bits (a bell, glasses, a cherry...). Under 40 parts, so with the
--     client's ailment props (Feel/CreatureActing) a creature stays under 45. ServerStorage.Creatures.<PatientId>
--     (a Model, or one MeshPart) replaces the placeholder look; its pivot's LookVector must be the creature's face.
--     Size (Logic/CreatureSize): the species' Look.Scale x Config.CreatureSize x a per-patient wobble (±8%).
--     Candy pop (memory-20261116-007): saturated SmoothPlastic bodies, dark eyes with white shine. Night patients
--     glow in a rich version of their body colour (PointLight, a Highlight rim, a little Neon on their tips).
--     Sparkly gets rainbow bits and rainbow glitter; Frosty an icy cyan tint and frost sparkles.
--   CreatureBuilder.badge(model): Badge?             the ailment badge (IconGui) and speech bubble (BubbleGui)
--   CreatureBuilder.setRing(badge, fraction, colour) the badge's ring: 0..1, filling clockwise from 12 o'clock
--   CreatureBuilder.setMood(model, mood)             "Sick" (little o mouth, worried brows) | "Happy" | "Sad" | "Sleep"
--   CreatureBuilder.setEffect(model, name, on)       FX children: "Heal", "HealLight" (and the variant ones)
--   CreatureBuilder.effectAt(position, kind)         a one-off burst that outlives the creature:
--                                                    "Cure" | "Puff" (sad) | "Pop" (leaving)
--
-- Model layout (Patients and Feel/CreatureActing rely on it):
--   PrimaryPart `Root`: an invisible anchored part at the bottom centre of the body. The pivot IS Root.CFrame, and
--   its LookVector is where the face looks. Moving Root moves the whole creature with one replicated CFrame.
--   `Core`: an invisible part on Root, joined by the Motor6D Root.PoseJoint (C0 = C1 = identity). Every visible part
--   is welded to Core (unanchored, massless, no collision, no queries, CollisionGroup "Patients"), so each client can
--   lean, bob and shake the body by setting PoseJoint.Transform locally (never replicated) while the server moves
--   Root. The arms (or wings or flippers) hang on Motor6Ds Core.ArmRJoint / Core.ArmLJoint at the shoulder, and a
--   tail on Core.TailJoint, so a client can wave and wag them the same way. R is the creature's own right (+X; on
--   your left as it faces you). Each arm part has a HandSocket Attachment at its paw.
--   Sockets: Attachments on Core where the client's props go (in studs, scaled with the creature): FaceSocket (the
--   mouth), NoseSocket, EyeRSocket/EyeLSocket, CheekRSocket/CheekLSocket, BrowSocket (the forehead), HeadSocket (top
--   of the head), EarRSocket/EarLSocket (the head's sides), NeckSocket (the body's middle just under the mouth),
--   BellySocket, BackSocket and, on a teapot, SpoutSocket. Each one's front (-Z) faces out of the surface.
--   Model attributes: PatientId, BuildScale (studs per unit at full size; Scale 1 is about 3 units tall), HeadRadius
--   and NeckSize (studs: Vector3 width, 0, depth of the body at NeckSocket), Brows ("Grumpy" for a grumpy species).
--   Tag "ClinicCreature" (CollectionService), so clients find every creature as it streams in.
--   Root.IconAnchor (Attachment above the head) holds the BillboardGuis IconGui and BubbleGui. The badge is
--   chunky and outlined like the top games' billboards: a dark rim, the patience ring, the station's candy ring
--   and a white disc with the ailment, plus corner chips (what it needs, Today's Visitor ⭐, the variant).
--   Both are sized in studs, so they shrink with distance like real objects, but never grow past their size at
--   NEAR_STUDS (BillboardGui.DistanceLowerLimit): standing right next to a patient, its badge stays a small part
--   of the screen (first-session declutter, docs/plan/2026-11-16-first-session-design.md §A2).
--   Root.FX (Attachment at the body's middle) holds the lights and particle emitters.
--   Model:GetScale() is the creature's own size (BuildScale); Patients scales relative to it.
--   Face parts (setMood relies on the names): Eye, EyeShine, EyeTint, Lid (LidGui: closed eyes), Brow (BrowGui:
--   Worried | Grumpy | Happy | Sad) and Mouth (MouthGui: Sick | Happy | Sad | Smile).
-- Rated Minimal: soft, round and friendly. Nothing sharp, scary or gross.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Ailments = require(Shared.Data.Ailments)
local CreatureSize = require(Shared.Logic.CreatureSize)
local Items = require(Shared.Data.Items)
local Palette = require(Shared.Palette)
local PatientsData = require(Shared.Data.Patients)
local Regulars = require(Shared.Data.Regulars)
local Stations = require(Shared.Data.Stations)
local Variants = require(Shared.Data.Variants)

local Candy = Palette.Candy

local CreatureBuilder = {}

export type Badge = {
	Gui: BillboardGui,
	Icon: TextLabel, -- the big emoji: the ailment, then 💗 / 💤 / 🥰 / 😔
	Need: Frame, -- the little chip with the item it needs
	Star: Frame, -- Today's Visitor ⭐
	Sticker: Frame, -- the variant sticker (✨ / 🧊)
	FillLeft: Frame,
	FillRight: Frame,
	GradLeft: UIGradient,
	GradRight: UIGradient,
	Bubble: BillboardGui, -- a regular's speech bubble (disabled until shown)
	BubbleEmote: TextLabel,
	BubbleText: TextLabel,
}

type Look = {
	Shape: string,
	Body: string,
	Accent: string,
	Ears: string,
	Top: string,
	Extra: string,
	Scale: number,
	Bits: { string }?,
}

type Ellipsoid = { C: Vector3, R: Vector3 } -- centre and semi-axes

type Shape = {
	Body: Ellipsoid, -- the main body; the face sits on its front (-Z)
	Head: Ellipsoid?, -- where ears and hats sit, when it isn't the body
	FaceY: number, -- eye line
	EyeX: number, -- eye distance from the middle
	Eye: number, -- eye (and face) size
	FrontZ: number?, -- flat-fronted bodies (Box): the face plane
	Feet: boolean,
}

type Build = {
	Model: Model,
	Look: Look,
	Shape: Shape,
	Tint: { BasePart }, -- coloured parts that Frosty and Sparkly tint (eyes, cheeks and face guis stay)
	Body: Color3,
	Accent: Color3,
	Night: boolean,
	Bits: { [string]: boolean },
	Anchor: BasePart?, -- the Body part: the sockets ride on it until Core exists
	Head: Ellipsoid, -- where ears, hats and the forehead sit (the body when there's no separate head)
	FlatTop: number?, -- a flat-topped body (a Box without its Crust): the top's height
	Top: number, -- y of the top of the head
	Belly: Ellipsoid?,
	MouthY: number,
	NeckSize: Vector3, -- unit: the body's width and depth at NeckSocket
	Rides: { [BasePart]: string }, -- a part that moves with an arm or the tail: that joint's key
	Joints: { [string]: BasePart }, -- "ArmR" | "ArmL" | "Tail": the part its Motor6D drives
}

type Rig = { Rides: { [BasePart]: string }, Joints: { [string]: BasePart } }

local COLLISION_GROUP = "Patients"
local CREATURE_TAG = "ClinicCreature" -- Feel/CreatureActing finds creatures by it
local ROOT_SIZE = 0.2 -- Root and Core (Feel/CreatureActing reads Root.Size / ROOT_SIZE as the pop-in scale)
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local WHITE = Palette.White
local BLACK = Color3.new(0, 0, 0)
local EYE = Palette.Outline -- deep plum-navy, never pure black
local MOUTH = Palette.Ink
local TONGUE = Color3.fromRGB(255, 120, 150)
local CHEEK = Color3.fromRGB(255, 112, 172)
local LEAF = Candy.Lime
local STEM = Color3.fromRGB(46, 178, 64)
local NOSE_DARK = Color3.fromRGB(82, 52, 44) -- a pup's nose: warm cocoa, not black
local NOSE_PINK = Color3.fromRGB(255, 136, 178)
local PAW_PINK = Color3.fromRGB(255, 170, 196)
local CHERRY = Color3.fromRGB(255, 50, 86)
local BUTTER = Color3.fromRGB(255, 240, 150)
local SYRUP = Color3.fromRGB(255, 92, 170)
local GLASS_RIM = Color3.fromRGB(96, 58, 170)
local ICE = Color3.fromRGB(112, 226, 255) -- Frosty: icy cyan
local HEAL = Candy.Pink
local HEAL_LIGHT = Color3.fromRGB(255, 200, 236)
local SAD_PUFF = Color3.fromRGB(140, 132, 255) -- a soft periwinkle puff: sad, never scary
local RING_START = Candy.Lime -- the patience ring starts full and green
local TRACK = Color3.fromRGB(236, 232, 250) -- the empty part of the patience ring
local DEFAULT_STATION = Candy.Pink
local BUBBLE = Candy.Purple -- a regular's speech bubble (white outlined text reads best on it)
local STICKER_RING: { [string]: Color3 } = { Sparkly = Candy.Pink, Frosty = Candy.Cyan }

-- Rainbow glitter for Sparkly, and the colours a cure bursts into.
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Candy.Pink),
	ColorSequenceKeypoint.new(0.2, Candy.Orange),
	ColorSequenceKeypoint.new(0.4, Candy.Yellow),
	ColorSequenceKeypoint.new(0.6, Candy.Lime),
	ColorSequenceKeypoint.new(0.8, Candy.Cyan),
	ColorSequenceKeypoint.new(1, Candy.Purple),
})
local CONFETTI = { Candy.Pink, Candy.Yellow, Candy.Cyan, Candy.Lime, Candy.Purple }

-- The badge: the IconGui is BADGE_STUDS square, and the round badge fills BADGE_FACE of it, so the corner chips and
-- the outlines stay inside the gui.
local BADGE_STUDS = 3.8
local BADGE_FACE = 0.8
-- Closer than this, the badge and the speech bubble stop growing on screen (about a fifth of its height at most).
local NEAR_STUDS = 16

-- Big parts keep their own colour on a Sparkly creature; the small bits (ears, tops, wings, tails) go rainbow.
local BIG_PARTS = { Body = true, Head = true, Belly = true, BellyTop = true, Crust = true, Puddle = true, Arm = true }

local DEFAULT_LOOK: Look = {
	Shape = "Ball",
	Body = "#FF6EC0",
	Accent = "#FFD6EC",
	Ears = "Round",
	Top = "None",
	Extra = "None",
	Scale = 1,
}

-- Unit sizes: Scale 1 is about 3 units tall. y = 0 is the ground under the creature; the face looks at -Z.
-- Kawaii proportions: one big round head-body, the eyes a little below its middle-top, a small mouth under them.
local SHAPES: { [string]: Shape } = {
	Ball = {
		Body = { C = Vector3.new(0, 1.36, 0), R = Vector3.new(1.46, 1.36, 1.34) },
		FaceY = 1.5,
		EyeX = 0.56,
		Eye = 1,
		Feet = true,
	},
	Bean = {
		Body = { C = Vector3.new(0, 1.52, 0), R = Vector3.new(1.2, 1.52, 1.1) },
		FaceY = 1.88,
		EyeX = 0.46,
		Eye = 0.92,
		Feet = true,
	},
	Blob = {
		Body = { C = Vector3.new(0, 1.12, 0), R = Vector3.new(1.66, 1.12, 1.45) },
		FaceY = 1.3,
		EyeX = 0.6,
		Eye = 1,
		Feet = true,
	},
	Box = {
		Body = { C = Vector3.new(0, 1.1, 0), R = Vector3.new(1.3, 1.1, 0.85) },
		FaceY = 1.42,
		EyeX = 0.5,
		Eye = 0.95,
		FrontZ = -0.94,
		Feet = true,
	},
	Drop = {
		Body = { C = Vector3.new(0, 1.12, 0), R = Vector3.new(1.42, 1.12, 1.3) },
		Head = { C = Vector3.new(0, 1.86, 0.05), R = Vector3.new(1.04, 1.04, 0.98) },
		FaceY = 1.5,
		EyeX = 0.5,
		Eye = 0.95,
		Feet = false,
	},
}

-- A hard step at the middle: one half opaque, the other clear. Rotating it sweeps the ring and draws arcs.
local HALF = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.501, 1),
	NumberSequenceKeypoint.new(1, 1),
})

local badges: { [Model]: Badge } = setmetatable({}, { __mode = "k" }) :: any
local warnedKit: { [string]: boolean } = {}
local rng = Random.new()

------------------------------------------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------------------------------------------

local function hex(value: string?, fallback: Color3): Color3
	if type(value) == "string" then
		local ok, color = pcall(Color3.fromHex, value)
		if ok then
			return color
		end
	end
	return fallback
end

local function darken(color: Color3, amount: number): Color3
	return color:Lerp(BLACK, amount)
end

local function lighten(color: Color3, amount: number): Color3
	return color:Lerp(WHITE, amount)
end

local function setup(p: BasePart, b: Build, name: string, size: Vector3, cf: CFrame, color: Color3, tint: boolean)
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Parent = b.Model
	if tint then
		table.insert(b.Tint, p)
	end
end

local function block(b: Build, name: string, size: Vector3, cf: CFrame, color: Color3, tint: boolean): Part
	local p = Instance.new("Part")
	setup(p, b, name, size, cf, color, tint)
	return p
end

-- An ellipsoid: a Part with a sphere mesh stretched to its size.
local function ball(b: Build, name: string, size: Vector3, cf: CFrame, color: Color3, tint: boolean): Part
	local p = block(b, name, size, cf, color, tint)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- A cylinder along the part's own X axis.
local function cylinder(
	b: Build,
	name: string,
	length: number,
	diameter: number,
	cf: CFrame,
	color: Color3,
	tint: boolean
): Part
	local p = block(b, name, Vector3.new(length, diameter, diameter), cf, color, tint)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function wedge(b: Build, name: string, size: Vector3, cf: CFrame, color: Color3, tint: boolean): WedgePart
	local p = Instance.new("WedgePart")
	setup(p, b, name, size, cf, color, tint)
	return p
end

-- A transparent plate that only carries a drawn SurfaceGui (brows, mouth, closed eyes, glasses).
local function plate(b: Build, name: string, size: Vector3, cf: CFrame): Part
	local p = block(b, name, size, cf, WHITE, false)
	p.Transparency = 1
	p.CastShadow = false
	return p
end

-- z of the front (-Z) surface of an ellipsoid at (x, y), or nil outside it.
local function frontOf(e: Ellipsoid, x: number, y: number): number?
	local nx = (x - e.C.X) / e.R.X
	local ny = (y - e.C.Y) / e.R.Y
	local inside = 1 - nx * nx - ny * ny
	if inside <= 0 then
		return nil
	end
	return e.C.Z - e.R.Z * math.sqrt(inside)
end

-- z of the back (+Z) surface of an ellipsoid at (x, y) (its middle when outside it).
local function backOf(e: Ellipsoid, x: number, y: number): number
	local nx = (x - e.C.X) / e.R.X
	local ny = (y - e.C.Y) / e.R.Y
	return e.C.Z + e.R.Z * math.sqrt(math.max(1 - nx * nx - ny * ny, 0))
end

-- y of the top surface of an ellipsoid at x.
local function topOf(e: Ellipsoid, x: number): number
	local nx = (x - e.C.X) / e.R.X
	return e.C.Y + e.R.Y * math.sqrt(math.max(1 - nx * nx, 0))
end

-- Half the width (x) and half the depth (z) of an ellipsoid's slice at height y.
local function halfWidth(e: Ellipsoid, y: number): number
	local ny = (y - e.C.Y) / e.R.Y
	return e.R.X * math.sqrt(math.max(1 - ny * ny, 0))
end

local function halfDepth(e: Ellipsoid, y: number): number
	local ny = (y - e.C.Y) / e.R.Y
	return e.R.Z * math.sqrt(math.max(1 - ny * ny, 0))
end

local function normalOf(e: Ellipsoid, p: Vector3): Vector3
	local d = p - e.C
	local n = Vector3.new(d.X / (e.R.X * e.R.X), d.Y / (e.R.Y * e.R.Y), d.Z / (e.R.Z * e.R.Z))
	return if n.Magnitude > 1e-6 then n.Unit else Vector3.new(0, 0, -1)
end

-- The point on an ellipsoid's surface in direction `dir` from its centre, and the outward normal there.
local function surfaceAt(e: Ellipsoid, dir: Vector3): (Vector3, Vector3)
	local d = dir.Unit
	local t = 1 / math.sqrt((d.X / e.R.X) ^ 2 + (d.Y / e.R.Y) ^ 2 + (d.Z / e.R.Z) ^ 2)
	local p = e.C + d * t
	return p, normalOf(e, p)
end

-- A CFrame at a surface point, lifted `lift` along the normal, whose front (-Z) faces out: flat bits lie on it.
local function facing(p: Vector3, n: Vector3, lift: number): CFrame
	local at = p + n * lift
	local up = if math.abs(n.Y) > 0.95 then Vector3.new(0, 0, -1) else Vector3.new(0, 1, 0)
	return CFrame.lookAt(at, at + n, up)
end

-- The front-most surface point of the face at (x, y) and its outward normal: the body, the belly or a Drop's head.
local function faceAt(b: Build, x: number, y: number): (Vector3, Vector3)
	local shape = b.Shape
	local frontZ = shape.FrontZ
	if frontZ then
		return Vector3.new(x, y, frontZ), Vector3.new(0, 0, -1)
	end
	local best: Ellipsoid? = nil
	local bestZ = math.huge
	for _, e in { shape.Body, shape.Head or shape.Body, b.Belly or shape.Body } do
		local z = frontOf(e, x, y)
		if z and z < bestZ then
			best, bestZ = e, z
		end
	end
	if not best then
		return Vector3.new(x, y, shape.Body.C.Z - shape.Body.R.Z * 0.3), Vector3.new(0, 0, -1)
	end
	local p = Vector3.new(x, y, bestZ)
	return p, normalOf(best, p)
end

local function corner(gui: GuiObject, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(radius or 0.5, 0)
	c.Parent = gui
end

local function surface(part: BasePart, name: string): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.LightInfluence = 0.4
	gui.MaxDistance = 70
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = part
	return gui
end

-- Half a ring drawn with a stroke: smile = the bottom half (a smile, or a closed happy eye), else the top half.
local function arc(
	parent: Instance,
	name: string,
	smile: boolean,
	position: UDim2,
	size: UDim2,
	thickness: number,
	color: Color3
): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = position
	f.Size = size
	f.BackgroundTransparency = 1
	f.Visible = false
	corner(f)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = f
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = HALF
	gradient.Rotation = if smile then -90 else 90
	gradient.Parent = stroke
	f.Parent = parent
	return f
end

-- A filled rounded shape on a SurfaceGui (a mouth, a brow, a tongue).
local function dab(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = position
	f.Size = size
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z
	corner(f)
	f.Parent = parent
	return f
end

-- An Attachment for the client's props (see the header). It rides on the Body part until Core exists.
local function socket(b: Build, name: string, cf: CFrame)
	local anchor = b.Anchor
	if not anchor then
		return
	end
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = anchor.CFrame:Inverse() * cf
	a.Parent = anchor
end

-- An arm, wing, flipper or tail: `main` will hang on a Motor6D from Core at `pivot` (unit space).
local function joint(b: Build, key: string, main: BasePart, pivot: CFrame)
	b.Joints[key] = main
	b.Rides[main] = key
	local a = Instance.new("Attachment")
	a.Name = "JointPivot"
	a.CFrame = main.CFrame:Inverse() * pivot
	a.Parent = main
end

local function ride(b: Build, key: string, part: BasePart)
	b.Rides[part] = key
end

-- A limb on one side (1 = the creature's right): its joint, and a HandSocket at its tip that stands upright while the
-- limb hangs at rest.
local function limb(b: Build, side: number, part: BasePart, shoulder: CFrame, tip: Vector3, tilt: number)
	joint(b, if side > 0 then "ArmR" else "ArmL", part, shoulder)
	local hand = Instance.new("Attachment")
	hand.Name = "HandSocket"
	hand.CFrame = CFrame.new(tip) * CFrame.Angles(0, 0, -tilt)
	hand.Parent = part
end

------------------------------------------------------------------------------------------------------------------
-- The placeholder creature
------------------------------------------------------------------------------------------------------------------

-- The body, its belly patch and a glossy shine. Sets b.Head, b.Top and b.FlatTop for ears and hats.
local function buildBody(b: Build)
	local look, shape = b.Look, b.Shape
	if look.Shape == "Box" then
		-- A slice of toast: a crust-coloured block with a soft bread front, and a loaf dome with a Crust top.
		b.Anchor = block(b, "Body", Vector3.new(2.6, 2.2, 1.7), CFrame.new(0, 1.1, 0), b.Body, true)
		block(b, "Belly", Vector3.new(2.2, 1.8, 0.12), CFrame.new(0, 1.0, -0.87), b.Accent, true)
		if look.Top == "Crust" then
			local alongZ = CFrame.Angles(0, math.pi / 2, 0)
			cylinder(b, "Crust", 1.7, 2.6, CFrame.new(0, 1.55, 0) * alongZ, b.Body, true)
			cylinder(b, "BellyTop", 0.12, 2.2, CFrame.new(0, 1.55, -0.87) * alongZ, b.Accent, true)
			b.Head = { C = Vector3.new(0, 1.55, 0), R = Vector3.new(1.3, 1.3, 0.85) }
			b.Top = 2.85
		else
			b.Head = shape.Body
			b.FlatTop = 2.2
			b.Top = 2.2
		end
		return
	end

	local body = shape.Body
	b.Anchor = ball(b, "Body", body.R * 2, CFrame.new(body.C), b.Body, true)
	local head = shape.Head
	if head then
		ball(b, "Head", head.R * 2, CFrame.new(head.C), b.Body, true)
		if look.Ears == "None" and look.Top == "None" and not b.Bits.Cherry then
			-- a soft little curl on top (a glowing wisp at night)
			local tipY = head.C.Y + head.R.Y - 0.12
			local tip = ball(b, "Tip", Vector3.one * 0.8, CFrame.new(0, tipY, head.C.Z + 0.08), b.Body, true)
			if b.Night then
				tip.Material = Enum.Material.Neon
			end
		end
	end
	b.Head = head or body
	b.Top = topOf(b.Head, 0)

	local bellyY = body.C.Y - 0.38 * body.R.Y
	local bodyFront = frontOf(body, 0, bellyY) or (body.C.Z - body.R.Z)
	local belly: Ellipsoid = {
		C = Vector3.new(0, bellyY, bodyFront + 0.13),
		R = Vector3.new(body.R.X * 0.58, body.R.Y * 0.5, 0.26),
	}
	ball(b, "Belly", belly.R * 2, CFrame.new(belly.C), b.Accent, true)
	b.Belly = belly

	-- A glossy candy shine high on the side the light comes from (the creature's right, your left).
	local shineOn = b.Head
	local p, n = surfaceAt(shineOn, Vector3.new(0.74, 0.56, -0.38))
	local size = Vector3.new(0.56, 0.3, 0.06) * (shineOn.R.X / 1.45)
	local shine = ball(b, "Shine", size, facing(p, n, 0.015) * CFrame.Angles(0, 0, -0.55), WHITE, false)
	shine.Transparency = 0.4
	shine.CastShadow = false
end

-- The brows' drawings: one bar or arch per mood. side = which eye (1 = the creature's right, on your left).
local function browGui(brow: BasePart, side: number, color: Color3, default: string)
	local gui = surface(brow, "BrowGui")
	-- Rotation is clockwise as you look at it. The inner end of the creature's right brow is on your right.
	local function bar(name: string, degrees: number, y: number)
		local f = dab(gui, name, UDim2.fromScale(0.5, y), UDim2.fromScale(0.74, 0.3), color, 1)
		f.Rotation = degrees
		f.Visible = name == default
	end
	bar("Worried", -side * 14, 0.55) -- inner ends up
	bar("Grumpy", side * 20, 0.62) -- inner ends down
	bar("Sad", -side * 26, 0.62)
	arc(gui, "Happy", false, UDim2.fromScale(0.5, 0.78), UDim2.fromScale(0.62, 0.9), 5, color).Visible = default
		== "Happy"
end

local function buildFace(b: Build)
	local shape = b.Shape
	local es = shape.Eye
	local curve = if shape.FrontZ then 0 else 1 -- flat faces don't turn their eyes outward
	local tintColor = EYE:Lerp(Color3.fromHSV((b.Body:ToHSV()), 0.7, 1), 0.45)
	local browColor = darken(b.Body, 0.55):Lerp(EYE, 0.35)
	local brows = if b.Bits.GrumpyBrows then "Grumpy" else "Worried"
	local hasNose = b.Bits.Nose or b.Bits.PinkNose or b.Bits.Beak
	for _, side in { -1, 1 } do
		local x = side * shape.EyeX
		local y = shape.FaceY
		local front = faceAt(b, x, y)
		local eye = CFrame.new(x, y, front.Z + 0.06 * es) * CFrame.Angles(0, -side * 0.3 * curve, 0)
		-- Big dark eyes, a soft glow of colour at the bottom and two white glints in the same corner of both: the
		-- "alive and friendly" look.
		ball(b, "Eye", Vector3.new(0.62, 0.8, 0.34) * es, eye, EYE, false)
		ball(
			b,
			"EyeTint",
			Vector3.new(0.42, 0.26, 0.08) * es,
			eye * CFrame.new(0, -0.21 * es, -0.13 * es),
			tintColor,
			false
		)
		ball(
			b,
			"EyeShine",
			Vector3.new(0.26, 0.26, 0.1) * es,
			eye * CFrame.new(0.13 * es, 0.19 * es, -0.15 * es),
			WHITE,
			false
		)
		ball(
			b,
			"EyeShine",
			Vector3.new(0.12, 0.12, 0.06) * es,
			eye * CFrame.new(-0.11 * es, -0.1 * es, -0.16 * es),
			WHITE,
			false
		)

		-- Closed, contented eyes for sleeping in bed (shown by setMood "Sleep").
		local lid = plate(b, "Lid", Vector3.new(0.7, 0.52, 0.04) * es, eye * CFrame.new(0, -0.02, -0.19 * es))
		local lidGui = surface(lid, "LidGui")
		lidGui.Enabled = false
		arc(lidGui, "Closed", true, UDim2.fromScale(0.5, 0.18), UDim2.fromScale(0.62, 0.82), 7, EYE).Visible = true

		-- Brows sit on the surface above each eye, so they read from the side too.
		local bp, bn = faceAt(b, side * (shape.EyeX + 0.03), y + 0.5 * es)
		local brow = plate(b, "Brow", Vector3.new(0.62, 0.3, 0.03) * es, facing(bp, bn, 0.025))
		browGui(brow, side, browColor, brows)

		local cp, cn = faceAt(b, side * (shape.EyeX + 0.42 * es), y - 0.38 * es)
		local blush = b.Bits.Blush == true
		local cheekSize = (if blush then Vector3.new(0.64, 0.38, 0.12) else Vector3.new(0.5, 0.3, 0.12)) * es
		local cheek = ball(b, "Cheek", cheekSize, facing(cp, cn, 0), CHEEK, false)
		cheek.Transparency = if blush then 0.05 else 0.15
		cheek.CastShadow = false

		local tag = if side > 0 then "R" else "L"
		socket(b, "Eye" .. tag .. "Socket", eye * CFrame.new(0, 0, -0.18 * es))
		socket(b, "Cheek" .. tag .. "Socket", facing(cp, cn, 0.03))
	end

	-- The mouth: drawn shapes on a see-through plate (setMood picks one). A nose or beak pushes it down a little.
	local mouthY = shape.FaceY - (if hasNose then 0.58 else 0.46) * es
	local mp, mn = faceAt(b, 0, mouthY)
	local mouthCf = facing(mp, mn, 0.015)
	local mouth = plate(b, "Mouth", Vector3.new(0.8, 0.5, 0.04) * es, mouthCf)
	local gui = surface(mouth, "MouthGui")
	dab(gui, "Sick", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.17, 0.42), MOUTH, 1) -- a small worried "o"
	-- Happy: a wide open smile with a little tongue (the lower half of a circle; the box clips the top half).
	local happy = Instance.new("Frame")
	happy.Name = "Happy"
	happy.AnchorPoint = Vector2.new(0.5, 0)
	happy.Position = UDim2.fromScale(0.5, 0.2)
	happy.Size = UDim2.fromScale(0.5, 0.75)
	happy.BackgroundTransparency = 1
	happy.ClipsDescendants = true
	happy.Visible = false
	happy.Parent = gui
	local open = dab(happy, "Open", UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 1), MOUTH, 1)
	open.SizeConstraint = Enum.SizeConstraint.RelativeXX
	local tongue = dab(open, "Tongue", UDim2.fromScale(0.5, 0.75), UDim2.fromScale(0.36, 0.36), TONGUE, 2)
	tongue.SizeConstraint = Enum.SizeConstraint.RelativeXX
	arc(gui, "Sad", false, UDim2.fromScale(0.5, 0.95), UDim2.fromScale(0.42, 0.66), 6, MOUTH)
	arc(gui, "Smile", true, UDim2.fromScale(0.5, 0.2), UDim2.fromScale(0.4, 0.6), 6, MOUTH) -- a closed, sleepy smile
	b.MouthY = mouthY

	socket(b, "FaceSocket", mouthCf)
	local np, nn = faceAt(b, 0, shape.FaceY - 0.22 * es)
	socket(b, "NoseSocket", facing(np, nn, if hasNose then 0.16 else 0.04))
end

local function buildFeet(b: Build)
	local shape = b.Shape
	if not shape.Feet then
		return
	end
	local body = shape.Body
	local color = if b.Bits.OrangeFeet then Candy.Orange else darken(b.Body, 0.14)
	for _, side in { -1, 1 } do
		local cf = CFrame.new(side * 0.52 * body.R.X, 0.2, body.C.Z - body.R.Z * 0.66)
		ball(b, "Foot", Vector3.new(0.76, 0.42, 0.92), cf, color, true)
		if b.Bits.Toes then
			for _, toe in { -1, 1 } do
				local toeCf = cf * CFrame.new(toe * 0.18, 0.05, -0.38)
				ball(b, "Toe", Vector3.new(0.26, 0.2, 0.26), toeCf, lighten(color, 0.3), true)
			end
		end
	end
end

-- Little round arms at the front of the sides, hanging from the shoulder (unless wings or flippers are its arms).
local function buildArms(b: Build)
	local look = b.Look
	if look.Extra == "Wings" or look.Extra == "Flippers" then
		return
	end
	local body = b.Shape.Body
	local color = if b.Bits.PinkPaws then PAW_PINK else darken(b.Body, 0.06)
	local y, x, z
	if look.Shape == "Box" then
		y, x, z = 0.95, 1.3, -0.25
	else
		y = body.C.Y - 0.14 * body.R.Y
		z = body.C.Z - 0.3 * body.R.Z
		local ny = (y - body.C.Y) / body.R.Y
		x = body.R.X * math.sqrt(math.max(1 - ny * ny - 0.09, 0)) - 0.1
	end
	for _, side in { -1, 1 } do
		local shoulder = CFrame.new(side * x, y, z)
		local tilt = side * 0.5
		local cf = shoulder * CFrame.Angles(0, 0, tilt) * CFrame.new(0, -0.3, 0)
		local arm = ball(b, "Arm", Vector3.new(0.46, 0.74, 0.46), cf, color, true)
		limb(b, side, arm, shoulder, Vector3.new(0, -0.32, -0.04), tilt)
	end
end

local function buildEars(b: Build)
	local kind = b.Look.Ears
	if kind == "None" then
		return
	end
	local head = if b.FlatTop then nil else b.Head
	local flatTop = b.FlatTop or 2.2
	local half = if head then head.R.X else 1.2
	local function headTop(x: number): number
		return if head then topOf(head, x) else flatTop
	end
	for _, side in { -1, 1 } do
		if kind == "Round" then
			local x = side * half * 0.62
			local y = headTop(x) - 0.08
			ball(b, "Ear", Vector3.one * 0.85, CFrame.new(x, y, 0.05), b.Body, true)
			ball(b, "EarInner", Vector3.new(0.48, 0.48, 0.16), CFrame.new(x, y, -0.32), b.Accent, true)
		elseif kind == "Floppy" then
			local midY = if head then head.C.Y + head.R.Y * 0.2 else flatTop - 0.6
			local cf = CFrame.new(side * half * 0.93, midY, 0) * CFrame.Angles(0, 0, side * 0.32)
			ball(b, "Ear", Vector3.new(0.55, 1.35, 0.85), cf, darken(b.Accent, 0.06), true)
		elseif kind == "Pointy" then
			-- A right-angled wedge turned so its right angle points up: a soft, wide kitty ear.
			local x = side * half * 0.6
			local y = headTop(x) - 0.14
			local turn = CFrame.Angles(0, 0, math.rad(135) - side * 0.22) * CFrame.Angles(0, math.pi / 2, 0)
			wedge(b, "Ear", Vector3.new(0.3, 0.72, 0.72), CFrame.new(x, y, 0.05) * turn, b.Body, true)
			local inner = CFrame.new(x, y + 0.06, -0.12) * turn
			wedge(b, "EarInner", Vector3.new(0.1, 0.44, 0.44), inner, lighten(b.Accent, 0.1), true)
		elseif kind == "Long" then
			local x = side * half * 0.38
			local cf = CFrame.new(x, headTop(x) + 0.62, 0.05) * CFrame.Angles(0, 0, -side * 0.16)
			ball(b, "Ear", Vector3.new(0.52, 1.65, 0.38), cf, b.Body, true)
			ball(b, "EarInner", Vector3.new(0.27, 1.2, 0.1), cf * CFrame.new(0, 0.02, -0.17), b.Accent, true)
		elseif kind == "Tufts" then
			local x = side * half * 0.66
			local cf = CFrame.new(x, headTop(x) + 0.1, 0.05) * CFrame.Angles(0, 0, -side * 0.6)
			ball(b, "Ear", Vector3.new(0.42, 0.9, 0.36), cf, darken(b.Body, 0.12), true)
		end
	end
end

local function buildTop(b: Build)
	local kind = b.Look.Top
	local top = b.Top
	if kind == "Leaf" then
		local up = CFrame.Angles(0, 0, math.pi / 2)
		cylinder(b, "Stem", 0.5, 0.14, CFrame.new(0, top + 0.18, 0.05) * up, STEM, false)
		local right = CFrame.new(0.42, top + 0.42, 0.05) * CFrame.Angles(0, 0, 0.45)
		ball(b, "Leaf", Vector3.new(1.05, 0.14, 0.52), right, LEAF, false)
		local left = CFrame.new(-0.32, top + 0.36, 0.05) * CFrame.Angles(0, 0, -0.5)
		ball(b, "Leaf", Vector3.new(0.78, 0.12, 0.4), left, LEAF, false)
	elseif kind == "Bow" then
		for _, side in { -1, 1 } do
			local cf = CFrame.new(side * 0.36, top + 0.12, 0) * CFrame.Angles(0, 0, side * 0.3)
			ball(b, "Bow", Vector3.new(0.75, 0.55, 0.3), cf, b.Accent, true)
		end
		ball(b, "BowKnot", Vector3.one * 0.34, CFrame.new(0, top + 0.12, -0.04), darken(b.Accent, 0.08), true)
	elseif kind == "Cloud" then
		-- A big soft cloud of wool: five puffs, the middle one tallest.
		local puff = lighten(b.Body, 0.62)
		ball(b, "Puff", Vector3.one * 1.2, CFrame.new(0, top + 0.24, 0.05), puff, true)
		ball(b, "Puff", Vector3.one * 0.92, CFrame.new(0.62, top + 0.02, 0.1), puff, true)
		ball(b, "Puff", Vector3.one * 0.92, CFrame.new(-0.62, top + 0.02, 0.1), puff, true)
		ball(b, "Puff", Vector3.one * 0.8, CFrame.new(0.22, top + 0.5, 0.45), puff, true)
		ball(b, "Puff", Vector3.one * 0.72, CFrame.new(-0.3, top + 0.12, -0.38), puff, true)
	elseif kind == "Antennae" then
		for _, side in { -1, 1 } do
			local base = CFrame.new(side * 0.3, top - 0.05, 0.05) * CFrame.Angles(0, 0, -side * 0.35)
			local stalk = base * CFrame.new(0, 0.45, 0) * CFrame.Angles(0, 0, math.pi / 2)
			cylinder(b, "Antenna", 0.9, 0.1, stalk, darken(b.Body, 0.2), true)
			local tip = ball(b, "AntennaTip", Vector3.one * 0.34, base * CFrame.new(0, 0.92, 0), b.Accent, true)
			if b.Night then
				tip.Material = Enum.Material.Neon -- glowing tips at night
			end
		end
	elseif kind == "Crust" then
		if b.Look.Shape ~= "Box" then -- the Box builds its own loaf top
			local cf = CFrame.new(0, top - 0.05, 0.05)
			ball(b, "Crust", Vector3.new(1.8, 0.6, 1.6), cf, darken(b.Body, 0.15), true)
		end
	elseif kind == "Pleat" then
		-- A dumpling wrapper cap, pinched at the top.
		local wrap = b.Accent
		ball(b, "Wrap", Vector3.new(2.0, 0.75, 1.85), CFrame.new(0, top - 0.15, 0.05), wrap, true)
		for _, side in { -1, 1 } do
			local cf = CFrame.new(side * 0.36, top + 0.08, 0.05) * CFrame.Angles(0, 0, -side * 0.45)
			ball(b, "Pleat", Vector3.new(0.26, 0.6, 0.9), cf, darken(wrap, 0.07), true)
		end
		ball(b, "Knot", Vector3.new(0.55, 0.5, 0.55), CFrame.new(0, top + 0.3, 0.05), wrap, true)
	elseif kind == "Scoop" then
		ball(b, "Scoop", Vector3.one * 1.7, CFrame.new(0, top + 0.5, 0.05), b.Accent, true)
		for i = 0, 2 do
			local a = i * (math.pi * 2 / 3) + 0.4
			local cf = CFrame.new(math.cos(a) * 0.78, top + 0.1, 0.05 + math.sin(a) * 0.7)
			ball(b, "Snow", Vector3.one * 0.6, cf, b.Accent, true)
		end
	elseif kind == "Star" then
		-- A soft, rounded star (no sharp points). It glows (Neon) on a night creature.
		local centre = CFrame.new(0, top + 0.78, 0.05)
		local star = if b.Night then b.Body else lighten(b.Body, 0.2)
		local parts = { ball(b, "Star", Vector3.new(0.62, 0.62, 0.3), centre, star, true) }
		for i = 0, 4 do
			local ray = centre * CFrame.Angles(0, 0, i * math.rad(72)) * CFrame.new(0, 0.42, 0)
			table.insert(parts, ball(b, "StarRay", Vector3.new(0.4, 0.88, 0.24), ray, star, true))
		end
		if b.Night then
			for _, part in parts do
				part.Material = Enum.Material.Neon
			end
		end
	elseif kind == "Lid" then
		local up = CFrame.Angles(0, 0, math.pi / 2)
		cylinder(b, "Lid", 0.24, 1.5, CFrame.new(0, top + 0.02, 0.05) * up, b.Accent, true)
		ball(b, "Knob", Vector3.one * 0.42, CFrame.new(0, top + 0.32, 0.05), b.Accent, true)
	end
end

local function buildExtra(b: Build)
	local kind = b.Look.Extra
	local body = b.Shape.Body
	local a, cy = body.R.X, body.C.Y
	if kind == "Wings" and b.Bits.MothWings then
		-- Big moth wings spread up and out from the upper back (they're its arms too: they flap).
		local y = cy + 0.3 * body.R.Y
		for _, side in { -1, 1 } do
			local shoulder = CFrame.new(side * halfWidth(body, y) * 0.5, y, body.C.Z + 0.72 * body.R.Z)
			local cf = shoulder
				* CFrame.Angles(0, -side * 0.3, 0) -- swept back a little
				* CFrame.Angles(0, 0, side * 0.5)
				* CFrame.new(side * 0.78, 0.1, 0)
			local wing = ball(b, "Wing", Vector3.new(1.6, 1.15, 0.14), cf, lighten(b.Body, 0.3), true)
			limb(b, side, wing, shoulder, Vector3.new(side * 0.7, 0, 0), side * 0.5)
			if b.Bits.WingSpots then
				local spot = ball(
					b,
					"WingSpot",
					Vector3.new(0.6, 0.46, 0.18),
					cf * CFrame.new(side * 0.2, 0.05, 0),
					b.Accent,
					true
				)
				ride(b, if side > 0 then "ArmR" else "ArmL", spot)
			end
		end
	elseif kind == "Wings" then
		-- Folded wings at the sides, like an owl's (its arms: they flap and wave).
		local y = cy + 0.1 * body.R.Y
		for _, side in { -1, 1 } do
			local shoulder = CFrame.new(side * (halfWidth(body, y) - 0.12), y, body.C.Z + 0.15)
			local tilt = side * 0.28
			local cf = shoulder * CFrame.Angles(0, 0, tilt) * CFrame.new(side * 0.08, -0.5, 0)
			local wing = ball(b, "Wing", Vector3.new(0.34, 1.3, 1.0), cf, b.Accent, true)
			limb(b, side, wing, shoulder, Vector3.new(0, -0.55, -0.1), tilt)
			if b.Bits.WingSpots then
				local spot = ball(
					b,
					"WingSpot",
					Vector3.new(0.38, 0.5, 0.5),
					cf * CFrame.new(0, -0.1, 0),
					darken(b.Accent, 0.1),
					true
				)
				ride(b, if side > 0 then "ArmR" else "ArmL", spot)
			end
		end
	elseif kind == "Flippers" then
		local y = cy + 0.02
		for _, side in { -1, 1 } do
			local shoulder = CFrame.new(side * (halfWidth(body, y) - 0.06), y, body.C.Z)
			local tilt = side * 0.42
			local cf = shoulder * CFrame.Angles(0, 0, tilt) * CFrame.new(0, -0.5, 0)
			local flipper = ball(b, "Flipper", Vector3.new(0.3, 1.15, 0.66), cf, darken(b.Body, 0.15), true)
			limb(b, side, flipper, shoulder, Vector3.new(0, -0.5, -0.05), tilt)
		end
	elseif kind == "Tail" then
		local backZ = if b.Look.Shape == "Box" then body.C.Z + body.R.Z else backOf(body, 0, 0.62)
		if b.Bits.Trail then
			-- A comet's trail: soft balls streaming back and up, paler as they go (glowing at night).
			local sizes = { 0.86, 0.7, 0.54, 0.4 }
			for i, d in sizes do
				local cf = CFrame.new(0, 0.95 + i * 0.24, backZ - 0.1 + i * 0.42)
				local color = b.Accent:Lerp(WHITE, (i - 1) * 0.2)
				local part = ball(b, if i == #sizes then "TailTip" else "Tail", Vector3.one * d, cf, color, true)
				if b.Night and i >= 3 then
					part.Material = Enum.Material.Neon
				end
				if i == 1 then
					joint(b, "Tail", part, CFrame.new(0, 1.0, backZ - 0.1))
				else
					ride(b, "Tail", part)
				end
			end
		else
			local first = ball(b, "Tail", Vector3.one * 0.62, CFrame.new(0, 0.62, backZ + 0.18), b.Body, true)
			joint(b, "Tail", first, CFrame.new(0, 0.62, backZ - 0.05))
			ride(b, "Tail", ball(b, "Tail", Vector3.one * 0.5, CFrame.new(0, 0.98, backZ + 0.5), b.Body, true))
			local tip = ball(b, "TailTip", Vector3.one * 0.44, CFrame.new(0, 1.36, backZ + 0.66), b.Accent, true)
			ride(b, "Tail", tip)
			if b.Night then
				tip.Material = Enum.Material.Neon -- a glowing tail tip at night
			end
		end
	elseif kind == "Spout" then
		local pot = darken(b.Body, 0.05)
		local spout = CFrame.new(a + 0.28, cy + 0.05, 0) * CFrame.Angles(0, 0, 0.75)
		cylinder(b, "Spout", 1.0, 0.42, spout, pot, true)
		ball(b, "SpoutTip", Vector3.one * 0.44, spout * CFrame.new(0.5, 0, 0), pot, true)
		ball(b, "Handle", Vector3.new(0.3, 1.0, 0.55), CFrame.new(-(a + 0.12), cy + 0.08, 0), pot, true)
		socket(b, "SpoutSocket", spout * CFrame.new(0.62, 0, 0) * CFrame.Angles(0, 0, -0.75))
	end
end

-- The species' own little accessories (Look.Bits). Each one is a few parts at most.
local BITS: { [string]: (b: Build) -> () } = {
	Spots = function(b: Build) -- frog freckles on the sides
		local body = b.Shape.Body
		for _, dir in { Vector3.new(0.95, 0.35, 0.25), Vector3.new(-0.9, 0.55, 0.3), Vector3.new(0.8, -0.05, 0.55) } do
			local p, n = surfaceAt(body, dir)
			ball(b, "Spot", Vector3.new(0.46, 0.4, 0.08), facing(p, n, 0), darken(b.Body, 0.2), true)
		end
	end,
	Bell = function(b: Build) -- a little golden bell with a ribbon bow, under the chin
		local p, n = faceAt(b, 0, b.MouthY - 0.36)
		local bell = ball(b, "Bell", Vector3.one * 0.44, facing(p, n, 0.14), Candy.Yellow, true)
		bell.Reflectance = 0.1
		ball(b, "BellSlit", Vector3.new(0.26, 0.07, 0.08), bell.CFrame * CFrame.new(0, -0.1, -0.18), EYE, false)
		ball(b, "BellBow", Vector3.new(0.56, 0.2, 0.14), bell.CFrame * CFrame.new(0, 0.25, 0.02), b.Accent, true)
	end,
	Nose = function(b: Build)
		local p, n = faceAt(b, 0, b.Shape.FaceY - 0.22 * b.Shape.Eye)
		local nose = ball(b, "Nose", Vector3.new(0.34, 0.25, 0.24), facing(p, n, 0.05), NOSE_DARK, false)
		ball(b, "NoseShine", Vector3.new(0.1, 0.06, 0.04), nose.CFrame * CFrame.new(0.06, 0.05, -0.11), WHITE, false)
	end,
	PinkNose = function(b: Build) -- a big soft pink nose (a mole's best feature)
		local p, n = faceAt(b, 0, b.Shape.FaceY - 0.22 * b.Shape.Eye)
		local nose = ball(b, "Nose", Vector3.new(0.48, 0.36, 0.34), facing(p, n, 0.08), NOSE_PINK, false)
		ball(b, "NoseShine", Vector3.new(0.13, 0.08, 0.05), nose.CFrame * CFrame.new(0.09, 0.07, -0.16), WHITE, false)
	end,
	Beak = function(b: Build)
		local p, n = faceAt(b, 0, b.Shape.FaceY - 0.22 * b.Shape.Eye)
		ball(
			b,
			"Beak",
			Vector3.new(0.42, 0.26, 0.44),
			facing(p, n, 0.1) * CFrame.Angles(-0.25, 0, 0),
			Candy.Orange,
			true
		)
	end,
	Butter = function(b: Build) -- a pat of butter on top of the toast
		local cf = CFrame.new(0.12, b.Top + 0.06, 0.05) * CFrame.Angles(0, 0.35, 0)
		ball(b, "Butter", Vector3.new(0.9, 0.26, 0.72), cf, BUTTER, true)
	end,
	Cherry = function(b: Build) -- a jelly's cherry, on its forehead in front of the ears
		local p, n = surfaceAt(b.Head, Vector3.new(0, 0.82, -0.58))
		local cherry = ball(b, "Cherry", Vector3.one * 0.5, CFrame.new(p + n * 0.2), CHERRY, true)
		local stem = cherry.CFrame * CFrame.new(0.06, 0.38, 0.02) * CFrame.Angles(0, 0, math.pi / 2 - 0.3)
		cylinder(b, "CherryStem", 0.42, 0.07, stem, STEM, false)
		ball(b, "CherryShine", Vector3.new(0.13, 0.1, 0.05), cherry.CFrame * CFrame.new(0.1, 0.1, -0.22), WHITE, false)
	end,
	CottonTail = function(b: Build)
		local body = b.Shape.Body
		local cf = CFrame.new(0, 0.5, backOf(body, 0, 0.5) + 0.12)
		ball(b, "CottonTail", Vector3.one * 0.6, cf, lighten(b.Accent, 0.6), true)
	end,
	Whiskers = function(b: Build) -- two soft whiskers each side
		local shape = b.Shape
		for _, side in { -1, 1 } do
			for _, k in { -1, 1 } do
				local p = faceAt(b, side * (shape.EyeX + 0.36), shape.FaceY - 0.34 + k * 0.08)
				local cf = CFrame.new(p + Vector3.new(side * 0.26, 0, -0.04))
					* CFrame.Angles(0, side * 0.35, k * side * 0.18)
				cylinder(b, "Whisker", 0.62, 0.05, cf, darken(b.Body, 0.5), false)
			end
		end
	end,
	Puddle = function(b: Build) -- a slime's little puddle around its base
		local body = b.Shape.Body
		local size = Vector3.new(body.R.X * 2 + 0.5, 0.2, body.R.Z * 2 + 0.45)
		local puddle = ball(b, "Puddle", size, CFrame.new(0, 0.1, body.C.Z), lighten(b.Body, 0.1), true)
		puddle.Transparency = 0.1
	end,
	Glasses = function(b: Build) -- round specs, drawn on a see-through plate just in front of the eyes
		local shape = b.Shape
		local es = shape.Eye
		local y = shape.FaceY
		local eyeFront = faceAt(b, shape.EyeX, y).Z + 0.06 * es - 0.17 * es
		local z = math.min(faceAt(b, 0, y).Z, eyeFront) - 0.06
		local width = 2 * (shape.EyeX + 0.42 * es)
		local height = 0.95 * es
		local specs = plate(b, "Glasses", Vector3.new(width, height, 0.03), CFrame.new(0, y, z))
		local gui = surface(specs, "GlassesGui")
		local d = 0.8 * es
		for _, side in { -1, 1 } do
			local lens = dab(
				gui,
				"Lens",
				UDim2.fromScale(0.5 + side * shape.EyeX / width, 0.5),
				UDim2.fromScale(d / width, d / height),
				Candy.Cyan,
				1
			)
			lens.BackgroundTransparency = 0.8
			local rim = Instance.new("UIStroke")
			rim.Color = GLASS_RIM
			rim.Thickness = 7
			rim.Parent = lens
		end
		local gap = 2 * shape.EyeX - d
		dab(gui, "Bridge", UDim2.fromScale(0.5, 0.42), UDim2.fromScale(gap / width + 0.04, 0.07), GLASS_RIM, 1)
	end,
	Syrup = function(b: Build) -- snow-cone syrup on the scoop: a pink splash and a blue one
		local scoop: Ellipsoid = { C = Vector3.new(0, b.Top + 0.5, 0.05), R = Vector3.one * 0.85 }
		for _, spec in { { Vector3.new(-0.35, 0.8, -0.5), SYRUP }, { Vector3.new(0.5, 0.7, -0.3), Candy.Cyan } } do
			local p, n = surfaceAt(scoop, spec[1] :: Vector3)
			ball(b, "Syrup", Vector3.new(0.78, 0.62, 0.1), facing(p, n, 0), spec[2] :: Color3, false)
		end
	end,
	EyeRings = function(b: Build) -- an owl's pale face discs around the eyes
		local shape = b.Shape
		for _, side in { -1, 1 } do
			local p, n = faceAt(b, side * shape.EyeX, shape.FaceY)
			local cf = facing(p, n, 0.01)
			ball(b, "EyeRing", Vector3.new(0.94, 1.08, 0.08) * shape.Eye, cf, lighten(b.Body, 0.62), true)
		end
	end,
	Hem = function(b: Build) -- a ghost's soft scalloped hem
		local body = b.Shape.Body
		local y = 0.31
		local rx, rz = halfWidth(body, y) * 0.92, halfDepth(body, y) * 0.92
		for i = 0, 5 do
			local a = i * (math.pi / 3) + math.pi / 6
			local cf = CFrame.new(math.cos(a) * rx, y, body.C.Z + math.sin(a) * rz)
			ball(b, "Hem", Vector3.one * 0.62, cf, b.Body, true)
		end
	end,
	Fluff = function(b: Build) -- a moth's fluffy ruff: three soft puffs across its chest, under the chin
		local y = b.MouthY - 0.42
		local fluff = lighten(b.Accent, 0.6)
		for _, x in { -0.42, 0, 0.42 } do
			local p, n = faceAt(b, x, y - math.abs(x) * 0.2)
			local size = if x == 0 then Vector3.new(0.7, 0.56, 0.42) else Vector3.new(0.6, 0.5, 0.4)
			ball(b, "Fluff", size, facing(p, n, 0.04), fluff, true)
		end
	end,
	Daisy = function(b: Build) -- a daisy tucked on the side of its head
		local p, n = surfaceAt(b.Head, Vector3.new(0.7, 0.85, -0.15))
		local cf = facing(p, n, 0.04)
		for i = 0, 2 do
			ball(b, "Petal", Vector3.new(0.66, 0.2, 0.08), cf * CFrame.Angles(0, 0, i * math.pi / 3), WHITE, false)
		end
		ball(b, "FlowerMiddle", Vector3.new(0.26, 0.26, 0.12), cf * CFrame.new(0, 0, -0.03), Candy.Yellow, false)
	end,
	Dots = function(b: Build) -- a teapot's polka dots
		local body = b.Shape.Body
		local dirs = {
			Vector3.new(0.65, -0.6, -0.45),
			Vector3.new(-0.65, -0.6, -0.45),
			Vector3.new(0.55, 0.5, 0.65),
			Vector3.new(-0.6, 0.15, 0.8),
		}
		for _, dir in dirs do
			local p, n = surfaceAt(body, dir)
			ball(b, "Dot", Vector3.new(0.42, 0.42, 0.07), facing(p, n, 0), WHITE, false)
		end
	end,
}

-- Bits handled inside the builders above (they change a part rather than add one).
local BUILT_IN = { Toes = true, PinkPaws = true, OrangeFeet = true, MothWings = true, WingSpots = true, Trail = true }
local EXTRA_FACE = { Blush = true, GrumpyBrows = true }

local function buildBits(b: Build)
	for _, name in b.Look.Bits or {} do
		local builder = BITS[name]
		if builder then
			builder(b)
		elseif not (BUILT_IN[name] or EXTRA_FACE[name]) then
			warn("[CreatureBuilder] unknown Look.Bits entry " .. tostring(name))
		end
	end
end

-- Where the client's props go (see the header): the head, the neck, the belly and the back.
local function buildSockets(b: Build)
	local shape = b.Shape
	local head = b.Head
	local body = shape.Body
	socket(b, "HeadSocket", CFrame.new(0, b.Top, head.C.Z))
	local foreheadY = math.min(shape.FaceY + 0.92 * shape.Eye, b.Top - 0.3)
	local fp, fn = faceAt(b, 0, foreheadY)
	socket(b, "BrowSocket", facing(fp, fn, 0.02))
	for _, side in { -1, 1 } do
		local tag = if side > 0 then "R" else "L"
		if shape.FrontZ then
			socket(
				b,
				"Ear" .. tag .. "Socket",
				facing(Vector3.new(side * 1.3, head.C.Y, 0), Vector3.new(side, 0, 0), 0)
			)
		else
			local p, n = surfaceAt(head, Vector3.new(side, 0.2, 0.05))
			socket(b, "Ear" .. tag .. "Socket", facing(p, n, 0))
		end
	end
	local neckY = b.MouthY - 0.34
	socket(b, "NeckSocket", CFrame.new(0, neckY, body.C.Z))
	b.NeckSize = if shape.FrontZ
		then Vector3.new(2.6, 0, 1.7)
		else Vector3.new(2 * halfWidth(body, neckY), 0, 2 * halfDepth(body, neckY))
	local belly = b.Belly
	if belly then
		socket(b, "BellySocket", facing(belly.C - Vector3.new(0, 0, belly.R.Z), Vector3.new(0, 0, -1), 0))
	else
		socket(b, "BellySocket", facing(Vector3.new(0, 0.75, -0.93), Vector3.new(0, 0, -1), 0))
	end
	local backY = body.C.Y
	local backZ = if shape.FrontZ then body.C.Z + body.R.Z else backOf(body, 0, backY)
	socket(b, "BackSocket", facing(Vector3.new(0, backY, backZ), Vector3.new(0, 0, 1), 0))
end

local function placeholder(look: Look, night: boolean, scale: number): (Model, { BasePart }, Rig)
	local model = Instance.new("Model")
	model.WorldPivot = CFrame.identity -- so ScaleTo scales around the unit origin (the ground under the body)
	local bits: { [string]: boolean } = {}
	for _, name in look.Bits or {} do
		bits[name] = true
	end
	local shape = SHAPES[look.Shape] or SHAPES.Ball
	local b: Build = {
		Model = model,
		Look = look,
		Shape = shape,
		Tint = {},
		Body = hex(look.Body, Candy.Pink),
		Accent = hex(look.Accent, WHITE),
		Night = night,
		Bits = bits,
		Anchor = nil,
		Head = shape.Body,
		FlatTop = nil,
		Top = 2.2,
		Belly = nil,
		MouthY = shape.FaceY - 0.46,
		NeckSize = Vector3.new(2, 0, 2),
		Rides = {},
		Joints = {},
	}

	buildBody(b)
	buildFace(b)
	buildFeet(b)
	buildArms(b)
	buildEars(b)
	buildTop(b)
	buildExtra(b)
	buildBits(b)
	buildSockets(b)
	if bits.GrumpyBrows then
		model:SetAttribute("Brows", "Grumpy")
	end

	if scale ~= 1 then
		model:ScaleTo(scale) -- every part is still anchored, so this is a plain resize around the origin
	end
	model:SetAttribute("BuildScale", scale)
	model:SetAttribute("HeadRadius", b.Head.R.X * scale)
	model:SetAttribute("NeckSize", b.NeckSize * scale)
	return model, b.Tint, { Rides = b.Rides, Joints = b.Joints }
end

------------------------------------------------------------------------------------------------------------------
-- The brother's model (ServerStorage.Creatures.<PatientId>)
------------------------------------------------------------------------------------------------------------------

local function fromKit(patientId: string, scale: number, jitter: number): (Model?, { BasePart }?)
	local folder = ServerStorage:FindFirstChild("Creatures")
	local template = folder and folder:FindFirstChild(patientId)
	if not template then
		return nil, nil
	end
	local model: Model
	if template:IsA("Model") then
		model = template:Clone()
	elseif template:IsA("BasePart") then
		model = Instance.new("Model")
		template:Clone().Parent = model
	else
		if not warnedKit[patientId] then
			warnedKit[patientId] = true
			warn("[CreatureBuilder] Creatures." .. patientId .. " must be a Model or a MeshPart; using the placeholder")
		end
		return nil, nil
	end

	-- Patients move by tweens, so nothing in the model may act on its own: no scripts, no Humanoids.
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") or descendant:IsA("Humanoid") then
			descendant:Destroy()
		end
	end
	local tint: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			table.insert(tint, descendant)
		end
	end
	if #tint == 0 then
		model:Destroy()
		return nil, nil
	end

	model:PivotTo(CFrame.identity)
	local _, size = model:GetBoundingBox()
	if size.Y < 1 or size.Y > 9 then -- far off the placeholder size: bring it near 3 units tall
		model:ScaleTo(model:GetScale() * (3 * scale / math.max(size.Y, 0.05)))
	elseif jitter ~= 1 then
		model:ScaleTo(model:GetScale() * jitter) -- its own size, give or take this patient's wobble
	end
	return model, tint
end

------------------------------------------------------------------------------------------------------------------
-- Root, Core, joints, sockets, effects and the badge
------------------------------------------------------------------------------------------------------------------

-- Root at the bottom centre: of the body (a placeholder is built round x = z = 0) or of the bounding box (a kit).
local function addRoot(model: Model, centred: boolean): (Part, number, number)
	model:PivotTo(CFrame.identity)
	local box, size = model:GetBoundingBox()
	local bottom = box.Y - size.Y / 2
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one * ROOT_SIZE
	root.CFrame = if centred then CFrame.new(0, bottom, 0) else CFrame.new(box.X, bottom, box.Z)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Massless = true
	root.CollisionGroup = COLLISION_GROUP
	root.Parent = model
	model.PrimaryPart = root
	model:PivotTo(CFrame.identity) -- the bottom centre is now the origin
	return root, size.Y, size.Y * 0.5
end

-- Core on Root (PoseJoint), the limbs on their Motor6Ds, everything else welded on, and the sockets moved onto Core.
local function rig(model: Model, root: BasePart, info: Rig?): Part
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Size = Vector3.one * ROOT_SIZE
	core.CFrame = root.CFrame
	core.Transparency = 1
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.CastShadow = false
	core.Massless = true
	core.CollisionGroup = COLLISION_GROUP
	core.Parent = model

	local pose = Instance.new("Motor6D")
	pose.Name = "PoseJoint"
	pose.Part0 = root
	pose.Part1 = core
	pose.Parent = root

	local joints: { [string]: BasePart } = if info then info.Joints else {}
	local rides: { [BasePart]: string } = if info then info.Rides else {}
	for key, main in joints do
		local pivot = main:FindFirstChild("JointPivot")
		if pivot and pivot:IsA("Attachment") then
			local motor = Instance.new("Motor6D")
			motor.Name = key .. "Joint"
			motor.Part0 = core
			motor.Part1 = main
			motor.C0 = core.CFrame:Inverse() * (main.CFrame * pivot.CFrame)
			motor.C1 = pivot.CFrame
			motor.Parent = core
			pivot:Destroy()
		end
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= root then
			if descendant ~= core then
				local key = rides[descendant]
				local holder = if key then joints[key] else nil
				if holder ~= descendant then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = holder or core
					weld.Part1 = descendant
					weld.Parent = descendant
				end
			end
			descendant.Anchored = false
			descendant.Massless = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CollisionGroup = COLLISION_GROUP
		end
	end

	local body = model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		for _, child in body:GetChildren() do
			if child:IsA("Attachment") and string.sub(child.Name, -6) == "Socket" then
				local world = body.CFrame * child.CFrame
				child.Parent = core
				child.CFrame = core.CFrame:Inverse() * world
			end
		end
	end
	return core
end

-- A kit model has no sockets of its own: guess them from its bounding box (Root at the bottom centre).
local function kitSockets(model: Model, core: BasePart, height: number)
	local _, size = model:GetBoundingBox()
	local w, h, d = size.X, height, size.Z
	local function put(name: string, position: Vector3, normal: Vector3)
		local a = Instance.new("Attachment")
		a.Name = name
		a.CFrame = facing(position, normal, 0)
		a.Parent = core
	end
	local front = Vector3.new(0, 0, -1)
	put("FaceSocket", Vector3.new(0, 0.5 * h, -d / 2), front)
	put("NoseSocket", Vector3.new(0, 0.56 * h, -d / 2), front)
	put("BrowSocket", Vector3.new(0, 0.8 * h, -0.4 * d), Vector3.new(0, 0.5, -1).Unit)
	put("HeadSocket", Vector3.new(0, h, 0), Vector3.new(0, 1, 0))
	put("NeckSocket", Vector3.new(0, 0.42 * h, 0), front)
	put("BellySocket", Vector3.new(0, 0.3 * h, -d / 2), front)
	put("BackSocket", Vector3.new(0, 0.45 * h, d / 2), Vector3.new(0, 0, 1))
	for _, side in { -1, 1 } do
		local tag = if side > 0 then "R" else "L"
		put("Eye" .. tag .. "Socket", Vector3.new(side * 0.18 * w, 0.62 * h, -d / 2), front)
		put(
			"Cheek" .. tag .. "Socket",
			Vector3.new(side * 0.3 * w, 0.5 * h, -0.45 * d),
			Vector3.new(side * 0.4, 0, -1).Unit
		)
		put("Ear" .. tag .. "Socket", Vector3.new(side * w / 2, 0.75 * h, 0), Vector3.new(side, 0, 0))
	end
	model:SetAttribute("BuildScale", h / 3)
	model:SetAttribute("HeadRadius", w * 0.35)
	model:SetAttribute("NeckSize", Vector3.new(w * 0.8, 0, d * 0.8))
end

local function sparkleEmitter(name: string, colors: ColorSequence, size: number, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = SPARKLE_TEXTURE
	e.Color = colors
	e.LightEmission = 0.5 -- half additive: bright, but the candy colour still shows in daylight
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.6) })
	e.Rate = rate
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new(1.5, 3)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 2
	e.RotSpeed = NumberRange.new(-90, 90)
	return e
end

-- A night creature's own glow: its body colour made rich (saturated, full brightness). A white-ish body glows lilac.
local function glowOf(body: Color3): Color3
	local h, s = Color3.toHSV(body)
	if s < 0.12 then
		return Color3.fromRGB(190, 140, 255)
	end
	return Color3.fromHSV(h, math.max(s, 0.72), 1)
end

local function addEffects(model: Model, root: Part, middle: number, night: boolean, variant: string?, body: Color3)
	local fx = Instance.new("Attachment")
	fx.Name = "FX"
	fx.Position = Vector3.new(0, middle, 0)
	fx.Parent = root

	if night then
		-- Spooky-cute: a rich glow in the creature's own colour, never scary.
		local color = glowOf(body)
		local glow = Instance.new("PointLight")
		glow.Name = "NightGlow"
		glow.Color = color
		glow.Brightness = 1.5
		glow.Range = 11
		glow.Shadows = false
		glow.Parent = fx
		local halo = Instance.new("Highlight") -- one per night creature only (Roblox shows 31 at most)
		halo.Name = "NightHalo"
		halo.FillColor = color
		halo.FillTransparency = 0.8 -- a light wash, so the face still reads
		halo.OutlineColor = color
		halo.OutlineTransparency = 0.1 -- a bright rim
		halo.DepthMode = Enum.HighlightDepthMode.Occluded
		halo.Parent = model
	end

	local healLight = Instance.new("PointLight")
	healLight.Name = "HealLight"
	healLight.Color = HEAL
	healLight.Brightness = 1.6
	healLight.Range = 9
	healLight.Shadows = false
	healLight.Enabled = false
	healLight.Parent = fx

	local heal = sparkleEmitter("Heal", ColorSequence.new(HEAL, HEAL_LIGHT), 0.38, 9)
	heal.EmissionDirection = Enum.NormalId.Top
	heal.SpreadAngle = Vector2.new(45, 45)
	heal.Speed = NumberRange.new(1, 2)
	heal.Acceleration = Vector3.new(0, 1, 0)
	heal.Lifetime = NumberRange.new(1, 1.6)
	heal.Enabled = false
	heal.Parent = fx

	if variant == "Sparkly" then
		-- Rainbow glitter: each speck runs through the candy colours, so the cloud is every colour at once.
		local glitter = sparkleEmitter("Sparkle", RAINBOW, 0.46, 10)
		glitter.LightEmission = 0.7
		glitter.Parent = fx
	elseif variant == "Frosty" then
		local frost = sparkleEmitter("Frost", ColorSequence.new(WHITE, Candy.Cyan), 0.34, 7)
		frost.Speed = NumberRange.new(0.5, 1.2)
		frost.Acceleration = Vector3.new(0, -1.5, 0)
		frost.Lifetime = NumberRange.new(1, 1.8)
		frost.LightEmission = 0.6
		frost.Parent = fx
	end
end

-- Sparkly: the big parts get brighter and a little more saturated; the small bits (ears, tops, wings, tails, feet)
-- take a rainbow colour by height, red-pink on top down to violet at the feet, like a holo sticker. A kit model's
-- parts aren't named like ours, so all of them count as big.
local function rainbowTint(tint: { BasePart }, kit: boolean)
	local low, high = math.huge, -math.huge
	for _, part in tint do
		low = math.min(low, part.Position.Y)
		high = math.max(high, part.Position.Y)
	end
	local span = math.max(high - low, 0.01)
	for _, part in tint do
		if kit or BIG_PARTS[part.Name] then
			local h, s, v = Color3.toHSV(part.Color)
			part.Color = Color3.fromHSV(h, math.min(s + 0.1, 1), math.min(v + 0.1, 1))
		else
			local t = (part.Position.Y - low) / span -- 0 at the bottom, 1 at the top
			part.Color = part.Color:Lerp(Color3.fromHSV((1 - t) * 0.78, 0.72, 1), 0.6)
		end
		part.Reflectance = 0.05
	end
end

local function applyVariant(tint: { BasePart }, variant: string?, kit: boolean)
	if variant == "Frosty" then
		for _, part in tint do
			part.Color = part.Color:Lerp(ICE, 0.45)
			part.Reflectance = 0.1
		end
	elseif variant == "Sparkly" then
		rainbowTint(tint, kit)
	end
end

local function circle(parent: Instance, name: string, size: number, position: UDim2, color: Color3, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = position
	f.Size = UDim2.fromScale(size, size)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z
	corner(f)
	f.Parent = parent
	return f
end

local function emoji(parent: Instance, name: string, text: string, size: number, z: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, 0.52)
	l.Size = UDim2.fromScale(size, size)
	l.BackgroundTransparency = 1
	l.Font = Palette.BodyFont
	l.TextScaled = true
	l.TextColor3 = Palette.Ink
	l.Text = text
	l.ZIndex = z
	l.Parent = parent
	return l
end

-- A plain see-through frame centred in its parent, `size` of it.
local function holder(parent: Instance, name: string, size: number, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(size, size)
	f.BackgroundTransparency = 1
	f.ZIndex = z
	f.Parent = parent
	return f
end

-- A corner chip: a candy ring with a thick dark outline, a white middle and an emoji in it.
local function chip(parent: Instance, name: string, size: number, position: UDim2, ring: Color3, icon: string): Frame
	local root = circle(parent, name, size, position, ring, 7)
	Palette.outlineShape(root, 3)
	local inner = circle(root, "Inner", 0.74, UDim2.fromScale(0.5, 0.5), WHITE, 1)
	emoji(inner, name .. "Icon", icon, 0.8, 2)
	return root
end

-- One half of the ring: a clip frame showing half of a full circle whose gradient decides how much shows.
local function ringHalf(parent: Instance, name: string, right: boolean): (Frame, UIGradient)
	local clip = Instance.new("Frame")
	clip.Name = name
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.Position = UDim2.fromScale(if right then 0.5 else 0, 0)
	clip.Size = UDim2.fromScale(0.5, 1)
	clip.ZIndex = 2
	clip.Parent = parent
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = RING_START
	fill.Position = UDim2.fromScale(if right then -1 else 0, 0)
	fill.Size = UDim2.fromScale(2, 1)
	fill.ZIndex = 2
	corner(fill)
	fill.Parent = clip
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = HALF
	gradient.Parent = fill
	return fill, gradient
end

local function makeBadge(
	anchor: Attachment,
	ailmentIcon: string,
	itemIcon: string,
	ring: Color3,
	sticker: string?,
	stickerRing: Color3
): Badge
	local centre = UDim2.fromScale(0.5, 0.5)
	local gui = Instance.new("BillboardGui")
	gui.Name = "IconGui"
	gui.Size = UDim2.fromScale(BADGE_STUDS, BADGE_STUDS) -- studs: big enough to read on a phone from the counter
	gui.StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 75
	gui.DistanceLowerLimit = NEAR_STUDS
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- From the outside in: a thick dark rim, the patience ring, the station's candy ring, then a white disc with the
	-- ailment. The rim is a dark circle rather than a stroke, so it stays chunky at every distance.
	local face = holder(gui, "Face", BADGE_FACE, 1)
	circle(face, "Outline", 1, centre, Palette.Outline, 1)
	circle(face, "Track", 0.9, centre, TRACK, 2)
	local ringFrame = holder(face, "Ring", 0.9, 3)
	local fillLeft, gradLeft = ringHalf(ringFrame, "RingLeft", false)
	local fillRight, gradRight = ringHalf(ringFrame, "RingRight", true)
	local stationRing = circle(face, "StationRing", 0.76, centre, ring, 4) -- the treating station's colour
	Palette.outlineShape(stationRing, 2.5)
	local disc = circle(face, "Disc", 0.6, centre, WHITE, 5)
	Palette.outlineShape(disc, 2)
	local icon = emoji(face, "Icon", ailmentIcon, 0.5, 6)

	local need = chip(face, "Need", 0.4, UDim2.fromScale(0.86, 0.86), ring, itemIcon)
	local star = chip(face, "Star", 0.44, UDim2.fromScale(0.14, 0.14), Candy.Yellow, "⭐")
	star.Visible = false
	local stickerFrame = chip(face, "Sticker", 0.4, UDim2.fromScale(0.86, 0.14), stickerRing, sticker or "")
	stickerFrame.Visible = sticker ~= nil
	gui.Parent = anchor

	-- A regular's speech bubble: an emote and 6 words or fewer, in chunky outlined letters on a candy bubble with a
	-- dark outline and a dark lip underneath. Inset from the gui's edge so the outlines always show whole.
	local bubble = Instance.new("BillboardGui")
	bubble.Name = "BubbleGui"
	bubble.Size = UDim2.fromScale(8, 2.6)
	bubble.StudsOffsetWorldSpace = Vector3.new(0, 4.6, 0)
	bubble.LightInfluence = 0
	bubble.MaxDistance = 60
	bubble.DistanceLowerLimit = NEAR_STUDS
	bubble.Enabled = false
	bubble.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0)
	shadow.Position = UDim2.fromScale(0.5, 0.1)
	shadow.Size = UDim2.fromScale(0.96, 0.68)
	shadow.BackgroundColor3 = Palette.Outline
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 1
	corner(shadow, 0.45)
	shadow.Parent = bubble
	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.fromScale(0.5, 0.76)
	tail.Size = UDim2.fromScale(0.07, 0.215) -- a square: 0.56 x 0.56 studs
	tail.Rotation = 45
	tail.BackgroundColor3 = BUBBLE
	tail.BorderSizePixel = 0
	tail.ZIndex = 2
	Palette.outlineShape(tail, 3)
	tail.Parent = bubble
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.Position = UDim2.fromScale(0.5, 0.04)
	body.Size = UDim2.fromScale(0.96, 0.68)
	body.BackgroundColor3 = BUBBLE
	body.BorderSizePixel = 0
	body.ZIndex = 3
	corner(body, 0.45)
	Palette.outlineShape(body, 3)
	body.Parent = bubble
	local emote = emoji(body, "Emote", "", 0.8, 4)
	emote.SizeConstraint = Enum.SizeConstraint.RelativeYY
	emote.AnchorPoint = Vector2.new(0, 0.5)
	emote.Position = UDim2.fromScale(0.03, 0.5)
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.AnchorPoint = Vector2.new(0, 0.5)
	text.Position = UDim2.fromScale(0.25, 0.5)
	text.Size = UDim2.fromScale(0.71, 0.72)
	text.BackgroundTransparency = 1
	text.Font = Palette.DisplayFont
	text.TextScaled = true
	text.TextWrapped = true
	text.TextColor3 = WHITE
	text.Text = ""
	text.ZIndex = 4
	Palette.outlineText(text)
	text.Parent = body
	bubble.Parent = anchor

	local badge: Badge = {
		Gui = gui,
		Icon = icon,
		Need = need,
		Star = star,
		Sticker = stickerFrame,
		FillLeft = fillLeft,
		FillRight = fillRight,
		GradLeft = gradLeft,
		GradRight = gradRight,
		Bubble = bubble,
		BubbleEmote = emote,
		BubbleText = text,
	}
	return badge
end

------------------------------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------------------------------

function CreatureBuilder.build(patientId: string, variant: string?): Model
	local entry = PatientsData[patientId]
	local regular = Regulars[patientId]
	local look: Look = if entry then entry.Look elseif regular then regular.Look else DEFAULT_LOOK
	local ailmentId = if entry then entry.Ailment elseif regular then regular.Ailment else ""
	-- Night patients glow; so do Night-wing regulars (they only visit at night).
	local night = (entry ~= nil and entry.Night == true) or (regular ~= nil and regular.Wing == "Night")
	local ailment = Ailments[ailmentId]
	local station = if ailment then Stations[ailment.Station] else nil
	local item = if station then Items[station.Item] else nil
	local variantData = if variant then Variants[variant] else nil
	-- Its size: the species' own, player-sized, give or take this patient's wobble (Logic/CreatureSize).
	local roll = rng:NextNumber()
	local scale = CreatureSize.scale(look.Scale, Config, roll)

	local kitModel, kitTint = fromKit(patientId, scale, CreatureSize.jitter(roll, Config))
	local model: Model, tint: { BasePart }, info: Rig?
	if kitModel and kitTint then
		model, tint = kitModel, kitTint
	else
		model, tint, info = placeholder(look, night, scale)
	end
	applyVariant(tint, variant, kitModel ~= nil)

	local root, height, middle = addRoot(model, info ~= nil)
	local core = rig(model, root, info)
	if not info then
		kitSockets(model, core, height)
	end
	addEffects(model, root, middle, night, variant, hex(look.Body, WHITE))

	local anchor = Instance.new("Attachment")
	anchor.Name = "IconAnchor"
	anchor.Position = Vector3.new(0, height + 0.25, 0)
	anchor.Parent = root
	badges[model] = makeBadge(
		anchor,
		if ailment then ailment.Icon else "❔",
		if item then item.Icon else "",
		if station then station.Color else DEFAULT_STATION,
		if variantData then variantData.Icon else nil,
		if variant then STICKER_RING[variant] or WHITE else WHITE
	)

	model.Name = patientId
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- streams in whole, never half a creature
	model:SetAttribute("PatientId", patientId)
	model:AddTag(CREATURE_TAG)
	return model
end

function CreatureBuilder.badge(model: Model): Badge?
	return badges[model]
end

-- The ring around the badge: `fraction` of a full circle, clockwise from 12 o'clock.
function CreatureBuilder.setRing(badge: Badge, fraction: number, color: Color3)
	local degrees = math.clamp(fraction, 0, 1) * 360
	badge.GradRight.Rotation = math.clamp(degrees, 0, 180)
	badge.GradLeft.Rotation = math.clamp(degrees, 180, 360)
	badge.FillRight.BackgroundColor3 = color
	badge.FillLeft.BackgroundColor3 = color
end

-- Shows the one drawing in `gui` named `shape` and hides its other drawings.
local function showOnly(part: Instance, guiName: string, shape: string)
	local gui = part:FindFirstChild(guiName)
	if gui then
		for _, face in gui:GetChildren() do
			if face:IsA("GuiObject") then
				face.Visible = face.Name == shape
			end
		end
	end
end

-- "Sick" (worried little o, worried brows) | "Happy" (open smile, raised brows) | "Sad" (frown, sad brows) |
-- "Sleep" (eyes closed, smiling). A grumpy species (attribute Brows = "Grumpy") frowns its brows while sick.
-- A kit model without these face parts just ignores it.
function CreatureBuilder.setMood(model: Model, mood: string)
	local sleeping = mood == "Sleep"
	local mouthShape = if sleeping then "Smile" else mood
	local browShape = "Happy"
	if mood == "Sick" then
		browShape = if model:GetAttribute("Brows") == "Grumpy" then "Grumpy" else "Worried"
	elseif mood == "Sad" then
		browShape = "Sad"
	end
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			local name = child.Name
			if name == "Eye" or name == "EyeShine" or name == "EyeTint" then
				child.Transparency = if sleeping then 1 else 0
			elseif name == "Lid" then
				local gui = child:FindFirstChild("LidGui")
				if gui and gui:IsA("SurfaceGui") then
					gui.Enabled = sleeping
				end
			elseif name == "Mouth" then
				showOnly(child, "MouthGui", mouthShape)
			elseif name == "Brow" then
				showOnly(child, "BrowGui", browShape)
			end
		end
	end
end

-- Turns a light or emitter under Root.FX on or off (e.g. "Heal" and "HealLight" while recovering).
function CreatureBuilder.setEffect(model: Model, name: string, on: boolean)
	local root = model.PrimaryPart
	local fx = root and root:FindFirstChild("FX")
	local effect = fx and fx:FindFirstChild(name)
	if effect and (effect:IsA("ParticleEmitter") or effect:IsA("Light")) then
		effect.Enabled = on
	end
end

-- A short burst at a spot, on its own Attachment in Terrain so it plays out after the creature is gone.
-- Emitters are switched on briefly instead of Emit(), which doesn't replicate from the server.
function CreatureBuilder.effectAt(position: Vector3, kind: string)
	local emitters: { ParticleEmitter } = {}
	if kind == "Puff" then
		local puff = Instance.new("ParticleEmitter")
		puff.Name = "Puff"
		puff.Texture = SMOKE_TEXTURE
		puff.Color = ColorSequence.new(SAD_PUFF, Color3.fromRGB(214, 222, 255))
		puff.LightEmission = 0.15
		puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 2.4) })
		puff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		puff.Rate = 70
		puff.Lifetime = NumberRange.new(0.7, 1)
		puff.Speed = NumberRange.new(2, 4)
		puff.SpreadAngle = Vector2.new(180, 180)
		puff.Drag = 4
		puff.Rotation = NumberRange.new(0, 360)
		puff.RotSpeed = NumberRange.new(-60, 60)
		table.insert(emitters, puff)
	elseif kind == "Cure" then
		-- Candy confetti: one emitter per colour, so every speck keeps its own colour.
		for _, color in CONFETTI do
			local confetti = sparkleEmitter("Cure", ColorSequence.new(color, lighten(color, 0.35)), 0.6, 26)
			confetti.EmissionDirection = Enum.NormalId.Top
			confetti.SpreadAngle = Vector2.new(70, 70)
			confetti.Speed = NumberRange.new(7, 11)
			confetti.Acceleration = Vector3.new(0, -10, 0)
			confetti.Lifetime = NumberRange.new(0.5, 0.9)
			table.insert(emitters, confetti)
		end
	else -- "Pop"
		local pop = sparkleEmitter("Pop", ColorSequence.new(Candy.Yellow, Candy.Pink), 0.45, 90)
		pop.Speed = NumberRange.new(5, 8)
		pop.Drag = 4
		pop.Lifetime = NumberRange.new(0.35, 0.6)
		table.insert(emitters, pop)
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "PatientFX"
	attachment.Parent = Workspace.Terrain
	attachment.WorldPosition = position
	for _, emitter in emitters do
		emitter.Parent = attachment
	end
	task.delay(0.18, function()
		for _, emitter in emitters do
			emitter.Enabled = false
		end
	end)
	task.delay(2.5, function()
		attachment:Destroy()
	end)
end

function CreatureBuilder.start() end

return CreatureBuilder
