--!strict
-- Builds a patient creature (build plan Task 1, §B1 kit overrides). Server only; Patients is the caller.
--   CreatureBuilder.build(patientId, variant?): Model
--     An original placeholder made from the patient's `Look` (Data/Patients, or Data/Regulars for a regular,
--     who uses their own id): a chunky round body, big shiny eyes, rosy cheeks, ears, a hat and an extra
--     (wings, tail...). Under 40 parts. ServerStorage.Creatures.<PatientId> (a Model, or one MeshPart) replaces
--     the placeholder look; its pivot's LookVector must be the creature's face.
--     Candy pop (memory-20261116-007): saturated SmoothPlastic bodies, dark eyes with white shine. Night patients
--     glow in a rich version of their body colour (PointLight, a Highlight rim, a little Neon on their tips).
--     Sparkly gets rainbow bits and rainbow glitter; Frosty an icy cyan tint and frost sparkles.
--   CreatureBuilder.badge(model): Badge?             the ailment badge (IconGui) and speech bubble (BubbleGui)
--   CreatureBuilder.setRing(badge, fraction, colour) the badge's ring: 0..1, filling clockwise from 12 o'clock
--   CreatureBuilder.setMood(model, mood)             "Sick" (little o mouth) | "Happy" | "Sad" | "Sleep"
--   CreatureBuilder.setEffect(model, name, on)       FX children: "Heal", "HealLight" (and the variant ones)
--   CreatureBuilder.effectAt(position, kind)         a one-off burst that outlives the creature:
--                                                    "Cure" | "Puff" (sad) | "Pop" (leaving)
--
-- Model layout (Patients relies on it):
--   PrimaryPart `Root`: an invisible anchored part at the bottom centre. The pivot IS Root.CFrame, and its
--   LookVector is where the face looks. Every other part is welded to Root (unanchored, massless, no collision,
--   no queries, CollisionGroup "Patients"), so moving Root moves the whole creature with one replicated CFrame.
--   Root.IconAnchor (Attachment above the head) holds the BillboardGuis IconGui and BubbleGui. The badge is
--   chunky and outlined like the top games' billboards: a dark rim, the patience ring, the station's candy ring
--   and a white disc with the ailment, plus corner chips (what it needs, Today's Visitor ⭐, the variant).
--   Root.FX (Attachment at the body's middle) holds the lights and particle emitters.
--   Model:GetScale() is the creature's own size (Look.Scale); Patients scales relative to it.
-- Rated Minimal: soft, round and friendly. Nothing sharp, scary or gross.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Ailments = require(Shared.Data.Ailments)
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
}

type Ellipsoid = { C: Vector3, R: Vector3 } -- centre and semi-axes

type Shape = {
	Body: Ellipsoid, -- the main body; the face sits on its front (-Z)
	Head: Ellipsoid?, -- where ears and hats sit, when it isn't the body
	FaceY: number, -- eye line
	EyeX: number, -- eye distance from the middle
	FrontZ: number?, -- flat-fronted bodies (Box): the face plane
	Feet: boolean,
}

type Build = {
	Model: Model,
	Tint: { BasePart }, -- coloured parts that Frosty and Sparkly tint (eyes, cheeks and face guis stay)
	Body: Color3,
	Accent: Color3,
	Night: boolean,
}

local COLLISION_GROUP = "Patients"
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local WHITE = Palette.White
local BLACK = Color3.new(0, 0, 0)
local EYE = Palette.Outline -- deep plum-navy, never pure black
local MOUTH = Palette.Ink
local CHEEK = Color3.fromRGB(255, 112, 172)
local LEAF = Candy.Lime
local STEM = Color3.fromRGB(46, 178, 64)
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

-- Big parts keep their own colour on a Sparkly creature; the small bits (ears, tops, wings, tails) go rainbow.
local BIG_PARTS = { Body = true, Head = true, Belly = true, BellyTop = true, Crust = true }

local DEFAULT_LOOK: Look = {
	Shape = "Ball",
	Body = "#FF6EC0",
	Accent = "#FFD6EC",
	Ears = "Round",
	Top = "None",
	Extra = "None",
	Scale = 1,
}

-- Unit sizes: Scale 1 is about 3 studs tall. y = 0 is the ground under the creature; the face looks at -Z.
local SHAPES: { [string]: Shape } = {
	Ball = {
		Body = { C = Vector3.new(0, 1.38, 0), R = Vector3.new(1.45, 1.38, 1.35) },
		FaceY = 1.62,
		EyeX = 0.58,
		Feet = true,
	},
	Bean = {
		Body = { C = Vector3.new(0, 1.5, 0), R = Vector3.new(1.18, 1.5, 1.1) },
		FaceY = 1.95,
		EyeX = 0.48,
		Feet = true,
	},
	Blob = {
		Body = { C = Vector3.new(0, 1.15, 0), R = Vector3.new(1.65, 1.15, 1.45) },
		FaceY = 1.36,
		EyeX = 0.62,
		Feet = true,
	},
	Box = {
		Body = { C = Vector3.new(0, 1.1, 0), R = Vector3.new(1.3, 1.1, 0.85) },
		FaceY = 1.5,
		EyeX = 0.52,
		FrontZ = -0.94,
		Feet = true,
	},
	Drop = {
		Body = { C = Vector3.new(0, 1.1, 0), R = Vector3.new(1.42, 1.1, 1.3) },
		Head = { C = Vector3.new(0, 2.0, 0.05), R = Vector3.new(0.95, 0.95, 0.9) },
		FaceY = 1.55,
		EyeX = 0.5,
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

-- y of the top surface of an ellipsoid at x.
local function topOf(e: Ellipsoid, x: number): number
	local nx = (x - e.C.X) / e.R.X
	return e.C.Y + e.R.Y * math.sqrt(math.max(1 - nx * nx, 0))
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

------------------------------------------------------------------------------------------------------------------
-- The placeholder creature
------------------------------------------------------------------------------------------------------------------

-- The body. Returns the belly patch (it shapes where the face sits) and the head used for ears and hats.
local function buildBody(b: Build, look: Look, shape: Shape): (Ellipsoid?, Ellipsoid?, number?)
	if look.Shape == "Box" then
		-- A slice of toast: a crust-coloured block with a soft bread front, and a loaf dome with a Crust top.
		block(b, "Body", Vector3.new(2.6, 2.2, 1.7), CFrame.new(0, 1.1, 0), b.Body, true)
		block(b, "Belly", Vector3.new(2.2, 1.8, 0.12), CFrame.new(0, 1.0, -0.87), b.Accent, true)
		if look.Top == "Crust" then
			local alongZ = CFrame.Angles(0, math.pi / 2, 0)
			cylinder(b, "Crust", 1.7, 2.6, CFrame.new(0, 1.55, 0) * alongZ, b.Body, true)
			cylinder(b, "BellyTop", 0.12, 2.2, CFrame.new(0, 1.55, -0.87) * alongZ, b.Accent, true)
			return nil, { C = Vector3.new(0, 1.55, 0), R = Vector3.new(1.3, 1.3, 0.85) }, nil
		end
		return nil, nil, 2.2 -- flat top
	end

	local body = shape.Body
	ball(b, "Body", body.R * 2, CFrame.new(body.C), b.Body, true)
	local head = shape.Head
	if head then
		ball(b, "Head", head.R * 2, CFrame.new(head.C), b.Body, true)
		if look.Ears == "None" and look.Top == "None" then
			-- a soft little drop tip (a glowing wisp at night)
			local tipY = head.C.Y + head.R.Y - 0.12
			local tip = ball(b, "Tip", Vector3.one * 0.8, CFrame.new(0, tipY, head.C.Z + 0.08), b.Body, true)
			if b.Night then
				tip.Material = Enum.Material.Neon
			end
		end
	end

	local bellyY = body.C.Y - 0.38 * body.R.Y
	local bodyFront = frontOf(body, 0, bellyY) or (body.C.Z - body.R.Z)
	local belly: Ellipsoid = {
		C = Vector3.new(0, bellyY, bodyFront + 0.13),
		R = Vector3.new(body.R.X * 0.58, body.R.Y * 0.5, 0.26),
	}
	ball(b, "Belly", belly.R * 2, CFrame.new(belly.C), b.Accent, true)
	return belly, head or body, nil
end

local function buildFace(b: Build, shape: Shape, faceZ: (number, number) -> number)
	local curve = if shape.FrontZ then 0 else 1 -- flat faces don't turn their eyes outward
	for _, side in { -1, 1 } do
		local x = side * shape.EyeX
		local y = shape.FaceY
		local eye = CFrame.new(x, y, faceZ(x, y) + 0.06) * CFrame.Angles(0, -side * 0.3 * curve, 0)
		-- Big dark eyes with two white glints in the same corner of both: the "alive and friendly" look.
		ball(b, "Eye", Vector3.new(0.64, 0.8, 0.36), eye, EYE, false)
		ball(b, "EyeShine", Vector3.new(0.26, 0.26, 0.1), eye * CFrame.new(0.13, 0.19, -0.16), WHITE, false)
		ball(b, "EyeShine", Vector3.new(0.12, 0.12, 0.06), eye * CFrame.new(-0.11, -0.17, -0.15), WHITE, false)

		-- Closed, contented eyes for sleeping in bed (shown by setMood "Sleep").
		local lid = block(b, "Lid", Vector3.new(0.7, 0.52, 0.04), eye * CFrame.new(0, -0.02, -0.19), WHITE, false)
		lid.Transparency = 1
		lid.CastShadow = false
		local lidGui = surface(lid, "LidGui")
		lidGui.Enabled = false
		arc(lidGui, "Closed", true, UDim2.fromScale(0.5, 0.18), UDim2.fromScale(0.62, 0.82), 7, EYE).Visible = true

		local cx = side * (shape.EyeX + 0.42)
		local cy = y - 0.4
		local cheekCf = CFrame.new(cx, cy, faceZ(cx, cy) + 0.04) * CFrame.Angles(0, -side * 0.55 * curve, 0)
		local cheek = ball(b, "Cheek", Vector3.new(0.5, 0.3, 0.14), cheekCf, CHEEK, false)
		cheek.Transparency = 0.15
	end

	local mouthY = shape.FaceY - 0.5
	local mouth =
		block(b, "Mouth", Vector3.new(0.62, 0.42, 0.04), CFrame.new(0, mouthY, faceZ(0, mouthY) - 0.015), WHITE, false)
	mouth.Transparency = 1
	mouth.CastShadow = false
	local gui = surface(mouth, "MouthGui")
	local sick = Instance.new("Frame") -- a small worried "o"
	sick.Name = "Sick"
	sick.AnchorPoint = Vector2.new(0.5, 0.5)
	sick.Position = UDim2.fromScale(0.5, 0.5)
	sick.Size = UDim2.fromScale(0.24, 0.46)
	sick.BackgroundColor3 = MOUTH
	sick.BorderSizePixel = 0
	corner(sick)
	sick.Parent = gui
	arc(gui, "Happy", true, UDim2.fromScale(0.5, 0.15), UDim2.fromScale(0.52, 0.77), 6, MOUTH)
	arc(gui, "Sad", false, UDim2.fromScale(0.5, 0.98), UDim2.fromScale(0.46, 0.68), 6, MOUTH)
end

local function buildFeet(b: Build, shape: Shape)
	if not shape.Feet then
		return
	end
	local body = shape.Body
	for _, side in { -1, 1 } do
		local cf = CFrame.new(side * 0.55 * body.R.X, 0.2, body.C.Z - body.R.Z * 0.7)
		ball(b, "Foot", Vector3.new(0.72, 0.42, 0.95), cf, darken(b.Body, 0.12), true)
	end
end

local function buildEars(b: Build, look: Look, head: Ellipsoid?, flatTop: number?)
	local kind = look.Ears
	if kind == "None" then
		return
	end
	local half = if head then head.R.X else 1.2
	local function headTop(x: number): number
		return if head then topOf(head, x) else (flatTop or 2.2)
	end
	for _, side in { -1, 1 } do
		if kind == "Round" then
			local x = side * half * 0.62
			local y = headTop(x) - 0.08
			ball(b, "Ear", Vector3.one * 0.85, CFrame.new(x, y, 0.05), b.Body, true)
			ball(b, "EarInner", Vector3.new(0.48, 0.48, 0.16), CFrame.new(x, y, -0.32), b.Accent, true)
		elseif kind == "Floppy" then
			local midY = if head then head.C.Y + head.R.Y * 0.2 else (flatTop or 2.2) - 0.6
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

local function buildTop(b: Build, look: Look, top: number)
	local kind = look.Top
	if kind == "Leaf" then
		local up = CFrame.Angles(0, 0, math.pi / 2)
		cylinder(b, "Stem", 0.5, 0.14, CFrame.new(0, top + 0.18, 0.05) * up, STEM, false)
		ball(
			b,
			"Leaf",
			Vector3.new(1.05, 0.14, 0.52),
			CFrame.new(0.42, top + 0.42, 0.05) * CFrame.Angles(0, 0, 0.45),
			LEAF,
			false
		)
		ball(
			b,
			"Leaf",
			Vector3.new(0.78, 0.12, 0.4),
			CFrame.new(-0.32, top + 0.36, 0.05) * CFrame.Angles(0, 0, -0.5),
			LEAF,
			false
		)
	elseif kind == "Bow" then
		for _, side in { -1, 1 } do
			local cf = CFrame.new(side * 0.36, top + 0.12, 0) * CFrame.Angles(0, 0, side * 0.3)
			ball(b, "Bow", Vector3.new(0.75, 0.55, 0.3), cf, b.Accent, true)
		end
		ball(b, "BowKnot", Vector3.one * 0.34, CFrame.new(0, top + 0.12, -0.04), darken(b.Accent, 0.08), true)
	elseif kind == "Cloud" then
		local puff = lighten(b.Body, 0.55)
		ball(b, "Puff", Vector3.one * 1.15, CFrame.new(0, top + 0.22, 0.05), puff, true)
		ball(b, "Puff", Vector3.one * 0.9, CFrame.new(0.58, top + 0.02, 0.1), puff, true)
		ball(b, "Puff", Vector3.one * 0.9, CFrame.new(-0.58, top + 0.02, 0.1), puff, true)
		ball(b, "Puff", Vector3.one * 0.75, CFrame.new(0.12, top + 0.5, 0.45), puff, true)
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
		if look.Shape ~= "Box" then -- the Box builds its own loaf top
			ball(b, "Crust", Vector3.new(1.8, 0.6, 1.6), CFrame.new(0, top - 0.05, 0.05), darken(b.Body, 0.15), true)
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

local function buildExtra(b: Build, look: Look, shape: Shape)
	local kind = look.Extra
	local body = shape.Body
	local a, cy, c = body.R.X, body.C.Y, body.R.Z
	if kind == "Wings" or kind == "Flippers" then
		for _, side in { -1, 1 } do
			if kind == "Wings" then
				local cf = CFrame.new(side * (a + 0.32), cy + 0.25 * body.R.Y, 0.35)
					* CFrame.Angles(0, -side * 0.55, 0)
					* CFrame.Angles(0, 0, side * 0.4)
				local wing = ball(b, "Wing", Vector3.new(1.5, 0.95, 0.18), cf, b.Accent, true)
				wing.Transparency = 0.12
			else
				local cf = CFrame.new(side * (a + 0.02), cy - 0.05, 0.05) * CFrame.Angles(0, 0, side * 0.45)
				ball(b, "Flipper", Vector3.new(0.32, 1.15, 0.7), cf, darken(b.Body, 0.15), true)
			end
		end
	elseif kind == "Tail" then
		ball(b, "Tail", Vector3.one * 0.62, CFrame.new(0, 0.62, c + 0.12), b.Body, true)
		ball(b, "Tail", Vector3.one * 0.5, CFrame.new(0, 0.98, c + 0.46), b.Body, true)
		local tip = ball(b, "TailTip", Vector3.one * 0.44, CFrame.new(0, 1.36, c + 0.6), b.Accent, true)
		if b.Night then
			tip.Material = Enum.Material.Neon -- a glowing tail tip at night
		end
	elseif kind == "Spout" then
		local pot = darken(b.Body, 0.05)
		local spout = CFrame.new(a + 0.28, cy + 0.05, 0) * CFrame.Angles(0, 0, 0.75)
		cylinder(b, "Spout", 1.0, 0.42, spout, pot, true)
		ball(b, "SpoutTip", Vector3.one * 0.44, spout * CFrame.new(0.5, 0, 0), pot, true)
		ball(b, "Handle", Vector3.new(0.3, 1.0, 0.55), CFrame.new(-(a + 0.12), cy + 0.08, 0), pot, true)
	end
end

local function placeholder(look: Look, night: boolean): (Model, { BasePart })
	local model = Instance.new("Model")
	local b: Build = {
		Model = model,
		Tint = {},
		Body = hex(look.Body, Candy.Pink),
		Accent = hex(look.Accent, WHITE),
		Night = night,
	}
	local shape = SHAPES[look.Shape] or SHAPES.Ball

	local belly, head, flatTop = buildBody(b, look, shape)
	local function faceZ(x: number, y: number): number
		if shape.FrontZ then
			return shape.FrontZ
		end
		local z = frontOf(shape.Body, x, y) or (shape.Body.C.Z - shape.Body.R.Z * 0.3)
		local bellyZ = if belly then frontOf(belly, x, y) else nil
		if bellyZ and bellyZ < z then
			z = bellyZ
		end
		return z
	end
	buildFace(b, shape, faceZ)
	buildFeet(b, shape)
	buildEars(b, look, head, flatTop)
	local top = if head then topOf(head, 0) else (flatTop or 2.2)
	buildTop(b, look, top)
	buildExtra(b, look, shape)

	local scale = if type(look.Scale) == "number" then math.clamp(look.Scale, 0.5, 2) else 1
	if scale ~= 1 then
		model:ScaleTo(scale) -- every part is still anchored, so this is a plain resize around the origin
	end
	return model, b.Tint
end

------------------------------------------------------------------------------------------------------------------
-- The brother's model (ServerStorage.Creatures.<PatientId>)
------------------------------------------------------------------------------------------------------------------

local function fromKit(patientId: string, look: Look): (Model?, { BasePart }?)
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
	if size.Y < 1 or size.Y > 9 then -- far off the placeholder size: bring it near 3 studs tall
		model:ScaleTo(model:GetScale() * (3 * look.Scale / math.max(size.Y, 0.05)))
	end
	return model, tint
end

------------------------------------------------------------------------------------------------------------------
-- Root, welds, effects and the badge
------------------------------------------------------------------------------------------------------------------

local function addRoot(model: Model): (Part, number, number)
	model:PivotTo(CFrame.identity)
	local box, size = model:GetBoundingBox()
	local bottom = box.Y - size.Y / 2
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one * 0.2
	root.CFrame = CFrame.new(box.X, bottom, box.Z)
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

local function weldAll(model: Model, root: BasePart)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = descendant
			weld.Parent = descendant
			descendant.Anchored = false
			descendant.Massless = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CollisionGroup = COLLISION_GROUP
		end
	end
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

	local kitModel, kitTint = fromKit(patientId, look)
	local model: Model, tint: { BasePart }
	if kitModel and kitTint then
		model, tint = kitModel, kitTint
	else
		model, tint = placeholder(look, night)
	end
	applyVariant(tint, variant, kitModel ~= nil)

	local root, height, middle = addRoot(model)
	weldAll(model, root)
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

-- "Sick" (worried little o) | "Happy" (smile) | "Sad" (frown) | "Sleep" (eyes closed, smiling).
-- A kit model without these face parts just ignores it.
function CreatureBuilder.setMood(model: Model, mood: string)
	local sleeping = mood == "Sleep"
	local mouthShape = if sleeping then "Happy" else mood
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			if child.Name == "Eye" or child.Name == "EyeShine" then
				child.Transparency = if sleeping then 1 else 0
			elseif child.Name == "Lid" then
				local gui = child:FindFirstChild("LidGui")
				if gui and gui:IsA("SurfaceGui") then
					gui.Enabled = sleeping
				end
			elseif child.Name == "Mouth" then
				local gui = child:FindFirstChild("MouthGui")
				if gui then
					for _, face in gui:GetChildren() do
						if face:IsA("GuiObject") then
							face.Visible = face.Name == mouthShape
						end
					end
				end
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
