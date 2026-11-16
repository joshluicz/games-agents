--!strict
-- Builds a patient creature (build plan Task 1, §B1 kit overrides). Server only; Patients is the caller.
--   CreatureBuilder.build(patientId, variant?): Model
--     An original placeholder made from the patient's `Look` (Data/Patients, or Data/Regulars for a regular,
--     who uses their own id): a chunky round body, big shiny eyes, rosy cheeks, ears, a hat and an extra
--     (wings, tail...). Under 40 parts. ServerStorage.Creatures.<PatientId> (a Model, or one MeshPart) replaces
--     the placeholder look; its pivot's LookVector must be the creature's face.
--     Night patients glow (PointLight plus a soft Highlight), Sparkly sparkles, Frosty gets an icy tint.
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
--   Root.IconAnchor (Attachment above the head) holds the BillboardGuis IconGui and BubbleGui.
--   Root.FX (Attachment at the body's middle) holds the lights and particle emitters.
--   Model:GetScale() is the creature's own size (Look.Scale); Patients scales relative to it.
-- Rated Minimal: soft, round and friendly. Nothing sharp, scary or gross.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Ailments = require(Shared.Data.Ailments)
local Items = require(Shared.Data.Items)
local PatientsData = require(Shared.Data.Patients)
local Regulars = require(Shared.Data.Regulars)
local Stations = require(Shared.Data.Stations)
local Variants = require(Shared.Data.Variants)

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

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local INK = Color3.fromRGB(46, 36, 66) -- eyes: soft plum-navy, never pure black
local MOUTH = Color3.fromRGB(96, 50, 66)
local CHEEK = Color3.fromRGB(255, 158, 184)
local LEAF = Color3.fromRGB(116, 198, 83)
local STEM = Color3.fromRGB(94, 170, 66)
local ICE = Color3.fromRGB(205, 238, 255)
local GOLD = Color3.fromRGB(255, 226, 138)
local STAR_GOLD = Color3.fromRGB(255, 213, 79)
local NIGHT_GLOW = Color3.fromRGB(228, 216, 255)
local HEAL_PINK = Color3.fromRGB(255, 184, 220)
local RING_START = Color3.fromRGB(126, 214, 155)
local DEFAULT_STATION = Color3.fromRGB(255, 170, 200)

local DEFAULT_LOOK: Look = {
	Shape = "Ball",
	Body = "#FFC8DC",
	Accent = "#FFF3F8",
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
			-- a soft little drop tip
			local tipY = head.C.Y + head.R.Y - 0.12
			ball(b, "Tip", Vector3.one * 0.8, CFrame.new(0, tipY, head.C.Z + 0.08), b.Body, true)
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
		ball(b, "Eye", Vector3.new(0.6, 0.74, 0.36), eye, INK, false)
		-- Two glints in the same corner of both eyes: the "alive and friendly" look.
		ball(b, "EyeShine", Vector3.new(0.22, 0.22, 0.1), eye * CFrame.new(0.12, 0.17, -0.16), WHITE, false)
		ball(b, "EyeShine", Vector3.new(0.11, 0.11, 0.06), eye * CFrame.new(-0.1, -0.15, -0.15), WHITE, false)

		-- Closed, contented eyes for sleeping in bed (shown by setMood "Sleep").
		local lid = block(b, "Lid", Vector3.new(0.66, 0.5, 0.04), eye * CFrame.new(0, -0.02, -0.19), WHITE, false)
		lid.Transparency = 1
		lid.CastShadow = false
		local lidGui = surface(lid, "LidGui")
		lidGui.Enabled = false
		arc(lidGui, "Closed", true, UDim2.fromScale(0.5, 0.18), UDim2.fromScale(0.62, 0.82), 6, INK).Visible = true

		local cx = side * (shape.EyeX + 0.42)
		local cy = y - 0.4
		local cheekCf = CFrame.new(cx, cy, faceZ(cx, cy) + 0.04) * CFrame.Angles(0, -side * 0.55 * curve, 0)
		local cheek = ball(b, "Cheek", Vector3.new(0.5, 0.3, 0.14), cheekCf, CHEEK, false)
		cheek.Transparency = 0.1
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
	arc(gui, "Happy", true, UDim2.fromScale(0.5, 0.15), UDim2.fromScale(0.52, 0.77), 5, MOUTH)
	arc(gui, "Sad", false, UDim2.fromScale(0.5, 0.98), UDim2.fromScale(0.46, 0.68), 5, MOUTH)
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
		-- A soft, rounded star (no sharp points).
		local centre = CFrame.new(0, top + 0.78, 0.05)
		local star = lighten(b.Body, 0.2)
		ball(b, "Star", Vector3.new(0.62, 0.62, 0.3), centre, star, true)
		for i = 0, 4 do
			local ray = centre * CFrame.Angles(0, 0, i * math.rad(72)) * CFrame.new(0, 0.42, 0)
			ball(b, "StarRay", Vector3.new(0.4, 0.88, 0.24), ray, star, true)
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
		ball(b, "TailTip", Vector3.one * 0.44, CFrame.new(0, 1.36, c + 0.6), b.Accent, true)
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
		Body = hex(look.Body, Color3.fromRGB(255, 200, 220)),
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
	e.LightEmission = 0.9
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

local function addEffects(model: Model, root: Part, middle: number, night: boolean, variant: string?, body: Color3)
	local fx = Instance.new("Attachment")
	fx.Name = "FX"
	fx.Position = Vector3.new(0, middle, 0)
	fx.Parent = root

	if night then
		-- Spooky-cute: a soft lavender glow, never scary.
		local glow = Instance.new("PointLight")
		glow.Name = "NightGlow"
		glow.Color = NIGHT_GLOW
		glow.Brightness = 1.2
		glow.Range = 10
		glow.Shadows = false
		glow.Parent = fx
		local halo = Instance.new("Highlight")
		halo.Name = "NightHalo"
		halo.FillColor = lighten(body, 0.6)
		halo.FillTransparency = 0.82
		halo.OutlineColor = NIGHT_GLOW
		halo.OutlineTransparency = 0.4
		halo.DepthMode = Enum.HighlightDepthMode.Occluded
		halo.Parent = model
	end

	local healLight = Instance.new("PointLight")
	healLight.Name = "HealLight"
	healLight.Color = HEAL_PINK
	healLight.Brightness = 1.6
	healLight.Range = 9
	healLight.Shadows = false
	healLight.Enabled = false
	healLight.Parent = fx

	local heal = sparkleEmitter("Heal", ColorSequence.new(HEAL_PINK, WHITE), 0.35, 8)
	heal.EmissionDirection = Enum.NormalId.Top
	heal.SpreadAngle = Vector2.new(45, 45)
	heal.Speed = NumberRange.new(1, 2)
	heal.Acceleration = Vector3.new(0, 1, 0)
	heal.Lifetime = NumberRange.new(1, 1.6)
	heal.Enabled = false
	heal.Parent = fx

	if variant == "Sparkly" then
		local colors = ColorSequence.new({
			ColorSequenceKeypoint.new(0, GOLD),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 190, 230)),
			ColorSequenceKeypoint.new(1, WHITE),
		})
		sparkleEmitter("Sparkle", colors, 0.4, 6).Parent = fx
	elseif variant == "Frosty" then
		local frost = sparkleEmitter("Frost", ColorSequence.new(WHITE, ICE), 0.3, 5)
		frost.Speed = NumberRange.new(0.5, 1.2)
		frost.Acceleration = Vector3.new(0, -1.5, 0)
		frost.Lifetime = NumberRange.new(1, 1.8)
		frost.LightEmission = 0.5
		frost.Parent = fx
	end
end

local function applyVariant(tint: { BasePart }, variant: string?)
	if variant == "Frosty" then
		for _, part in tint do
			part.Color = part.Color:Lerp(ICE, 0.5)
			part.Reflectance = 0.12
		end
	elseif variant == "Sparkly" then
		for _, part in tint do
			part.Color = part.Color:Lerp(GOLD, 0.18)
			part.Reflectance = 0.06
		end
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
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = INK
	l.Text = text
	l.ZIndex = z
	l.Parent = parent
	return l
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

local function makeBadge(anchor: Attachment, ailmentIcon: string, itemIcon: string, ring: Color3, sticker: string?)
	local centre = UDim2.fromScale(0.5, 0.5)
	local gui = Instance.new("BillboardGui")
	gui.Name = "IconGui"
	gui.Size = UDim2.fromScale(3, 3) -- studs: big enough to read on a phone from behind the counter
	gui.StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 75
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local track = circle(gui, "Track", 1, centre, WHITE, 1)
	track.BackgroundTransparency = 0.25
	local fillLeft, gradLeft = ringHalf(gui, "RingLeft", false)
	local fillRight, gradRight = ringHalf(gui, "RingRight", true)
	circle(gui, "StationRing", 0.84, centre, ring, 3) -- the treating station's colour, like its own badge
	circle(gui, "Disc", 0.74, centre, WHITE, 4)
	local icon = emoji(gui, "Icon", ailmentIcon, 0.56, 5)

	local need = circle(gui, "Need", 0.44, UDim2.fromScale(0.85, 0.85), ring, 6)
	local needInner = circle(need, "Inner", 0.8, centre, WHITE, 7)
	emoji(needInner, "NeedIcon", itemIcon, 0.74, 8)

	local star = circle(gui, "Star", 0.42, UDim2.fromScale(0.15, 0.15), STAR_GOLD, 6)
	emoji(star, "StarIcon", "⭐", 0.72, 7)
	star.Visible = false

	local stickerFrame = circle(gui, "Sticker", 0.42, UDim2.fromScale(0.85, 0.15), WHITE, 6)
	emoji(stickerFrame, "StickerIcon", sticker or "", 0.72, 7)
	stickerFrame.Visible = sticker ~= nil
	gui.Parent = anchor

	-- A regular's speech bubble: an emote and 6 words or fewer.
	local bubble = Instance.new("BillboardGui")
	bubble.Name = "BubbleGui"
	bubble.Size = UDim2.fromScale(8, 2.4)
	bubble.StudsOffsetWorldSpace = Vector3.new(0, 4.4, 0)
	bubble.LightInfluence = 0
	bubble.MaxDistance = 60
	bubble.Enabled = false
	bubble.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.Position = UDim2.fromScale(0.01, 0.05)
	shadow.Size = UDim2.fromScale(1, 0.8)
	shadow.BackgroundColor3 = INK
	shadow.BackgroundTransparency = 0.85
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 1
	corner(shadow, 0.45)
	shadow.Parent = bubble
	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.fromScale(0.5, 0.8)
	tail.Size = UDim2.fromScale(0.075, 0.25) -- a square: 0.6 x 0.6 studs
	tail.Rotation = 45
	tail.BackgroundColor3 = WHITE
	tail.BorderSizePixel = 0
	tail.ZIndex = 2
	tail.Parent = bubble
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.fromScale(1, 0.8)
	body.BackgroundColor3 = WHITE
	body.BorderSizePixel = 0
	body.ZIndex = 3
	corner(body, 0.45)
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
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextWrapped = true
	text.TextColor3 = INK
	text.Text = ""
	text.ZIndex = 4
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
	applyVariant(tint, variant)

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
		if variantData then variantData.Icon else nil
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
	local emitter: ParticleEmitter
	if kind == "Puff" then
		emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Puff"
		emitter.Texture = SMOKE_TEXTURE
		emitter.Color = ColorSequence.new(Color3.fromRGB(216, 210, 232), WHITE)
		emitter.LightEmission = 0.15
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 2.4) })
		emitter.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
		emitter.Rate = 70
		emitter.Lifetime = NumberRange.new(0.7, 1)
		emitter.Speed = NumberRange.new(2, 4)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Drag = 4
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-60, 60)
	elseif kind == "Cure" then
		local colors = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 150, 200)),
			ColorSequenceKeypoint.new(0.5, GOLD),
			ColorSequenceKeypoint.new(1, WHITE),
		})
		emitter = sparkleEmitter("Cure", colors, 0.6, 120)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.SpreadAngle = Vector2.new(70, 70)
		emitter.Speed = NumberRange.new(7, 11)
		emitter.Acceleration = Vector3.new(0, -10, 0)
		emitter.Lifetime = NumberRange.new(0.5, 0.9)
	else -- "Pop"
		emitter = sparkleEmitter("Pop", ColorSequence.new(WHITE, Color3.fromRGB(255, 220, 240)), 0.45, 90)
		emitter.Speed = NumberRange.new(5, 8)
		emitter.Drag = 4
		emitter.Lifetime = NumberRange.new(0.35, 0.6)
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "PatientFX"
	attachment.Parent = Workspace.Terrain
	attachment.WorldPosition = position
	emitter.Parent = attachment
	task.delay(0.18, function()
		emitter.Enabled = false
	end)
	task.delay(2.5, function()
		attachment:Destroy()
	end)
end

function CreatureBuilder.start() end

return CreatureBuilder
