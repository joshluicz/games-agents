--!strict
-- Builds the decor you place in a room's decor slots (build plan Task 7). Server only.
--   DecorBuilder.build(decorId): Model     a fresh Model, never parented; Plots places and anchors it
--   DecorBuilder.KINDS: { string }         every Look.Kind with a placeholder recipe
--   DecorBuilder.BOB_TAG                   the tag on a sub-Model that sways on clients (Feel/Atmosphere)
--
-- Contract (Data/Decor header): a decor Model fits a 4 x 4 stud footprint and pivots at its BOTTOM CENTRE, with its
-- front facing local -Z (the street side of the room it sits in). Plots pivots it onto the DecorSlot's floor point.
--
-- The brother's models win: ServerStorage.ClinicKit.Decor.<DecorId> (a Model, or a single Part) is cloned instead of
-- the placeholder. Only its pivot ORIENTATION matters (point its front at -Z): the position is moved to the bottom
-- centre of its bounding box, so it never sinks into the floor. Scripts inside a kit decor model are removed, because
-- decor is visual only and Toolbox models can hide scripts.
--
-- Placeholder recipes come from Data/Decor `Look`: Kind picks the shape, Color and Accent colour it, and Glow = true
-- tags the bulb with PlotBuilder.NIGHT_LIGHT_TAG (Neon plus a PointLight, on only at night). Rounded and toy-like in
-- the candy-pop look (memory-20261116-007): SmoothPlastic everywhere, Glass only for the see-through bowl and globe,
-- and Look colours pushed to full saturation by `candy()` (Data/Decor's hexes are soft pastels). Every recipe stays
-- at or under MAX_PARTS (25): a plot has 10 decor slots, so decor can add up to 250 parts to a Lv 5 plot's ~389
-- (docs/plan/2026-11-16-perf-budget.md). A piece over it, kit models too, warns once per DecorId with its count.
-- Water, steam and snow are slow ParticleEmitters.
--
-- Idle motion: a sub-Model tagged BOB_TAG sways on each client (Feel/Atmosphere), so nothing moves on the server and
-- nothing replicates per frame. Its attributes:
--   BobRest  CFrame   its rest pivot, relative to the decor Model's pivot
--   BobHeight number  studs of up-and-down
--   BobSway  number   radians of side-to-side tilt
--   BobSpin  number   radians of turning
--   BobSpeed number   cycles per second

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Decor = require(ReplicatedStorage.Shared.Data.Decor)
local Palette = require(ReplicatedStorage.Shared.Palette)
local PlotBuilder = require(script.Parent.PlotBuilder)

local DecorBuilder = {}

DecorBuilder.BOB_TAG = "ClinicDecorBob"

local NIGHT_LIGHT_TAG: string = PlotBuilder.NIGHT_LIGHT_TAG

-- Built-in particle textures (checked in the Player's content folder, 2026-11-16).
local TEXTURE = {
	SoftDot = "rbxasset://textures/particles/explosion01_implosion_main.dds", -- a soft round glow
	Ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds", -- a thin ring: bubbles
	Puff = "rbxasset://textures/particles/smoke_main.dds", -- a soft cloud: steam
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
}

-- Candy pop (shared/Palette): the fixed colours every recipe shares.
local COLORS = {
	Wood = Palette.World.Wood,
	WoodDark = Palette.World.WoodDark,
	Stone = Color3.fromRGB(246, 242, 255), -- a lilac-white, so the fountain reads as toy, not rock
	Soil = Palette.World.Trunk,
	Eye = Palette.Outline,
	White = Palette.White,
	Cheek = Palette.Candy.Pink:Lerp(Palette.White, 0.35),
	Heart = Palette.Candy.Red,
	Orange = Palette.Candy.Orange,
	Leaf = Palette.World.Leaves,
	Sunny = Palette.Candy.Yellow,
	Water = Palette.World.Water,
	Warm = Palette.World.Lamp,
	Snow = Palette.White,
	Teddy = Palette.Candy.Purple:Lerp(Palette.White, 0.4), -- a lilac teddy, so it stands out on an orange shelf
}

-- A few decor items get a little extra on top of their Kind recipe.
local FLOURISH: { [string]: string } = {
	HeartRug = "Heart",
	MoonLantern = "Moon",
	CometLantern = "Comet",
}

------------------------------------------------------------------------------------------------------------------
-- Part helpers. Positions are model-local: y = 0 is the floor, -Z is the front.
------------------------------------------------------------------------------------------------------------------

type Look = { Kind: string, Color: string, Accent: string, Glow: boolean? }

type Opts = {
	Solid: boolean?, -- players bump into it (default: walk-through detail)
	Material: Enum.Material?,
	Transparency: number?,
}

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- turns a Cylinder's X axis to point up
local FACING = CFrame.Angles(0, math.rad(90), 0) -- turns a Cylinder's X axis to point at the front (-Z)

local function lighten(color: Color3, amount: number): Color3
	return color:Lerp(COLORS.White, amount)
end

-- Pushes a Look colour to candy saturation, keeping its hue. Near-whites stay white (snow globes, white arches).
local function candy(color: Color3): Color3
	local h, s, v = color:ToHSV()
	if s < 0.12 then
		return color
	end
	return Color3.fromHSV(h, math.min(1, s * 1.25 + 0.2), math.max(v, 0.92))
end

local function darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, opts: Opts?): Part
	local solid = opts ~= nil and opts.Solid == true
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = if opts and opts.Material then opts.Material else Enum.Material.SmoothPlastic
	p.Transparency = if opts and opts.Transparency then opts.Transparency else 0
	p.Anchored = true
	p.CanCollide = solid
	p.CanQuery = solid -- the camera passes through little details
	p.CanTouch = false
	p.CastShadow = math.max(size.X, size.Y, size.Z) >= 0.8
	p.Parent = parent
	return p
end

local function block(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, opts: Opts?): Part
	return newPart(parent, name, size, cf, color, opts)
end

local function ball(parent: Instance, name: string, diameter: number, at: Vector3, color: Color3, opts: Opts?): Part
	local p = newPart(parent, name, Vector3.one * diameter, CFrame.new(at), color, opts)
	p.Shape = Enum.PartType.Ball
	return p
end

-- An upright cylinder (a disc when it's short) centred at `at`.
local function cylinder(
	parent: Instance,
	name: string,
	height: number,
	diameter: number,
	at: Vector3,
	color: Color3,
	opts: Opts?
): Part
	local p = newPart(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(at) * UPRIGHT, color, opts)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A cylinder along any CFrame's X axis (spouts, rails, strings).
local function rod(parent: Instance, name: string, length: number, diameter: number, cf: CFrame, color: Color3): Part
	local p = newPart(parent, name, Vector3.new(length, diameter, diameter), cf, color)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A rod from a to b. Built with fromMatrix, not lookAt, so a straight-up rod doesn't give a NaN frame.
local function rodBetween(parent: Instance, name: string, a: Vector3, b: Vector3, diameter: number, color: Color3): Part
	local along = (b - a).Unit
	local helper = if math.abs(along.Y) > 0.99 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	local back = along:Cross(helper).Unit
	local up = back:Cross(along).Unit
	local cf = CFrame.fromMatrix((a + b) / 2, along, up, back)
	return rod(parent, name, (b - a).Magnitude, diameter, cf, color)
end

-- A flat disc facing the front (-Z), for cheeks and clover leaves.
local function badge(parent: Instance, name: string, diameter: number, at: Vector3, color: Color3): Part
	local p = newPart(parent, name, Vector3.new(0.06, diameter, diameter), CFrame.new(at) * FACING, color)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- An ellipsoid: a Part with a sphere mesh stretched to its size (leaves, balloons, bodies).
local function egg(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, opts: Opts?): Part
	local p = newPart(parent, name, size, cf, color, opts)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function glow(p: BasePart, color: Color3, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 1.2
	light.Range = range
	light.Shadows = false
	light.Enabled = false -- PlotBuilder turns it on at night
	light.Parent = p
	p:AddTag(NIGHT_LIGHT_TAG)
end

-- An upright Attachment on `part` at the model-local point `at` (so EmissionDirection Top is always up, even on a
-- cylinder whose own axes are turned).
local function emitterAt(part: BasePart, at: Vector3, name: string): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = part.CFrame:ToObjectSpace(CFrame.new(at))
	attachment.Parent = part
	return attachment
end

local function particles(attachment: Attachment, props: { [string]: any }): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.LightInfluence = 0.5
	emitter.LockedToPart = false
	for key, value in props do
		(emitter :: any)[key] = value
	end
	emitter.Parent = attachment
	return emitter
end

local function fade(from: number, to: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, from),
		NumberSequenceKeypoint.new(0.75, from + (to - from) * 0.5),
		NumberSequenceKeypoint.new(1, to),
	})
end

-- A sub-Model that sways on clients. `pivot` is model-local (the decor model's pivot is the origin while building).
local function bobGroup(
	model: Model,
	name: string,
	pivot: CFrame,
	motion: { Height: number?, Sway: number?, Spin: number?, Speed: number }
): Model
	local group = Instance.new("Model")
	group.Name = name
	group:SetAttribute("BobRest", pivot)
	group:SetAttribute("BobHeight", motion.Height or 0)
	group:SetAttribute("BobSway", motion.Sway or 0)
	group:SetAttribute("BobSpin", motion.Spin or 0)
	group:SetAttribute("BobSpeed", motion.Speed)
	group:AddTag(DecorBuilder.BOB_TAG)
	group.Parent = model
	return group
end

-- Call once the group has parts: a PrimaryPart keeps its pivot glued to its parts however the decor is moved.
local function finishBob(group: Model, pivot: CFrame)
	local first = group:FindFirstChildWhichIsA("BasePart")
	if first then
		group.PrimaryPart = first
		first.PivotOffset = first.CFrame:ToObjectSpace(pivot)
	end
end

------------------------------------------------------------------------------------------------------------------
-- Recipes, one per Look.Kind
------------------------------------------------------------------------------------------------------------------

type Recipe = (model: Model, color: Color3, accent: Color3, look: Look, flourish: string?) -> ()

local RECIPES: { [string]: Recipe } = {}

-- A round, layered rug. The Heart Rug gets a heart; the others a little flower of dots.
RECIPES.Rug = function(model, color, accent, _look, flourish)
	cylinder(model, "Base", 0.1, 3.9, Vector3.new(0, 0.05, 0), color)
	cylinder(model, "Ring", 0.11, 3.2, Vector3.new(0, 0.055, 0), accent)
	cylinder(model, "Inner", 0.12, 2.5, Vector3.new(0, 0.06, 0), lighten(accent, 0.55))
	if flourish == "Heart" then
		-- Two discs and a turned square make a heart, pointing at the front.
		cylinder(model, "HeartLeft", 0.14, 0.95, Vector3.new(-0.32, 0.07, 0.18), color)
		cylinder(model, "HeartRight", 0.14, 0.95, Vector3.new(0.32, 0.07, 0.18), color)
		block(
			model,
			"HeartPoint",
			Vector3.new(0.95, 0.14, 0.95),
			CFrame.new(0, 0.07, -0.18) * CFrame.Angles(0, math.rad(45), 0),
			color
		)
	else
		cylinder(model, "Centre", 0.14, 0.8, Vector3.new(0, 0.07, 0), color)
		for i = 1, 5 do
			local a = math.rad(i * 72)
			cylinder(model, "Petal", 0.13, 0.5, Vector3.new(math.cos(a) * 0.75, 0.065, math.sin(a) * 0.75), accent)
		end
	end
end

-- A terracotta pot with a fluffy fern.
RECIPES.Plant = function(model, color, accent)
	cylinder(model, "Pot", 1.4, 1.6, Vector3.new(0, 0.7, 0), accent, { Solid = true })
	cylinder(model, "Rim", 0.3, 1.9, Vector3.new(0, 1.45, 0), darken(accent, 0.08), { Solid = true })
	cylinder(model, "Soil", 0.08, 1.55, Vector3.new(0, 1.58, 0), COLORS.Soil)
	local base = CFrame.new(0, 1.6, 0)
	for i = 1, 6 do
		local frond = base
			* CFrame.Angles(0, math.rad(i * 60 + 15), 0)
			* CFrame.Angles(math.rad(38), 0, 0)
			* CFrame.new(0, 0, -1.05)
		egg(model, "Frond", Vector3.new(0.6, 0.18, 2.3), frond, if i % 2 == 0 then color else lighten(color, 0.18))
	end
	for i = 1, 3 do
		local frond = base
			* CFrame.Angles(0, math.rad(i * 120), 0)
			* CFrame.Angles(math.rad(68), 0, 0)
			* CFrame.new(0, 0, -0.95)
		egg(model, "Sprout", Vector3.new(0.5, 0.16, 1.9), frond, darken(color, 0.06))
	end
end

-- A bubble lamp: a round bulb on a slim pole, with two little bubbles.
RECIPES.Lamp = function(model, color, accent, look)
	cylinder(model, "Base", 0.3, 1.6, Vector3.new(0, 0.15, 0), accent, { Solid = true })
	cylinder(model, "Pole", 3.0, 0.25, Vector3.new(0, 1.8, 0), accent, { Solid = true })
	cylinder(model, "Collar", 0.3, 0.75, Vector3.new(0, 3.35, 0), darken(accent, 0.1))
	local bulb = ball(model, "Bulb", 1.8, Vector3.new(0, 4.25, 0), color)
	local bubbly = { Transparency = 0.25 }
	ball(model, "Bubble", 0.55, Vector3.new(0.85, 5.0, -0.2), lighten(accent, 0.4), bubbly)
	ball(model, "Bubble", 0.38, Vector3.new(-0.7, 5.3, 0.25), lighten(accent, 0.4), bubbly)
	ball(model, "Shine", 0.35, Vector3.new(-0.42, 4.65, -0.62), COLORS.White)
	if look.Glow then
		glow(bulb, lighten(color, 0.2), 12)
	end
end

-- Three balloons tied to a little gift box. The balloons sway (BOB_TAG) around the knot.
RECIPES.Balloons = function(model, color, accent)
	block(model, "Box", Vector3.new(1, 0.8, 1), CFrame.new(0, 0.4, 0), accent, { Solid = true })
	block(model, "RibbonX", Vector3.new(1.04, 0.81, 0.2), CFrame.new(0, 0.405, 0), color)
	block(model, "RibbonZ", Vector3.new(0.2, 0.81, 1.04), CFrame.new(0, 0.405, 0), color)

	local knot = Vector3.new(0, 0.85, 0)
	local pivot = CFrame.new(knot)
	local group = bobGroup(model, "Balloons", pivot, { Sway = 0.07, Spin = 0.12, Speed = 0.35 })
	local balloons = {
		{ At = Vector3.new(-0.75, 5.0, 0.2), Color = color },
		{ At = Vector3.new(0.8, 5.5, -0.15), Color = accent },
		{ At = Vector3.new(0.05, 6.5, 0.3), Color = COLORS.Sunny },
	}
	for i, b in balloons do
		egg(group, "Balloon" .. i, Vector3.new(1.4, 1.75, 1.4), CFrame.new(b.At), b.Color)
		egg(
			group,
			"Shine" .. i,
			Vector3.new(0.3, 0.45, 0.2),
			CFrame.new(b.At + Vector3.new(-0.32, 0.4, -0.6)),
			COLORS.White
		)
		local tie = b.At - Vector3.new(0, 0.95, 0)
		ball(group, "Knot" .. i, 0.25, tie, b.Color)
		rodBetween(group, "String" .. i, knot, tie, 0.06, COLORS.White)
	end
	finishBob(group, pivot)
end

-- A little bookcase of toys: a ball, stacked blocks, a teddy and books.
RECIPES.Shelf = function(model, color, accent)
	local z = 0.3 -- pushed back a little, so the toys face the room
	local solid = { Solid = true }
	block(model, "SideLeft", Vector3.new(0.25, 4, 1.2), CFrame.new(-1.68, 2, z), color, solid)
	block(model, "SideRight", Vector3.new(0.25, 4, 1.2), CFrame.new(1.68, 2, z), color, solid)
	block(model, "Back", Vector3.new(3.2, 4, 0.12), CFrame.new(0, 2, z + 0.55), lighten(color, 0.55))
	for i, y in { 0.1, 1.45, 2.8 } do
		block(model, "Shelf" .. i, Vector3.new(3.15, 0.2, 1.1), CFrame.new(0, y, z), color)
	end
	block(model, "Top", Vector3.new(3.8, 0.25, 1.35), CFrame.new(0, 4.1, z), darken(color, 0.05), solid)

	-- Bottom shelf: a ball and two blocks
	ball(model, "ToyBall", 0.8, Vector3.new(-0.85, 0.6, z - 0.1), accent)
	block(model, "ToyBlock", Vector3.new(0.6, 0.6, 0.6), CFrame.new(0.75, 0.5, z), COLORS.Heart)
	block(
		model,
		"ToyBlock",
		Vector3.new(0.5, 0.5, 0.5),
		CFrame.new(0.72, 1.05, z) * CFrame.Angles(0, math.rad(20), 0),
		COLORS.Water
	)
	-- Middle shelf: a teddy
	local teddy = COLORS.Teddy
	ball(model, "TeddyBody", 0.8, Vector3.new(-0.5, 1.95, z - 0.05), teddy)
	ball(model, "TeddyHead", 0.62, Vector3.new(-0.5, 2.5, z - 0.1), teddy)
	ball(model, "TeddyEar", 0.24, Vector3.new(-0.73, 2.75, z - 0.05), teddy)
	ball(model, "TeddyEar", 0.24, Vector3.new(-0.27, 2.75, z - 0.05), teddy)
	ball(model, "Star", 0.5, Vector3.new(0.75, 1.8, z), accent)
	-- Top shelf: books
	local books = { COLORS.Heart, COLORS.Leaf, accent }
	for i, bookColor in books do
		block(
			model,
			"Book",
			Vector3.new(0.25, 0.85 - i * 0.05, 0.65),
			CFrame.new(0.3 + i * 0.3, 3.32 - i * 0.025, z),
			bookColor
		)
	end
end

-- A round fish bowl on a little stand, with a fish that swims round and bubbles that rise.
RECIPES.Bowl = function(model, color, accent)
	local solid = { Solid = true }
	cylinder(model, "Foot", 0.2, 1.4, Vector3.new(0, 0.1, 0), COLORS.Wood, solid)
	cylinder(model, "Leg", 1.5, 0.5, Vector3.new(0, 0.95, 0), COLORS.Wood, solid)
	cylinder(model, "Plate", 0.15, 1.5, Vector3.new(0, 1.75, 0), COLORS.Wood, solid)
	ball(
		model,
		"Glass",
		2.5,
		Vector3.new(0, 3.05, 0),
		color,
		{ Solid = true, Material = Enum.Material.Glass, Transparency = 0.6 }
	)
	local water = ball(model, "Water", 2.2, Vector3.new(0, 2.95, 0), COLORS.Water, { Transparency = 0.55 })
	ball(model, "Pebble", 0.35, Vector3.new(-0.35, 2.02, 0.2), COLORS.Heart)
	ball(model, "Pebble", 0.3, Vector3.new(0.3, 2.0, 0.3), COLORS.Sunny)

	local pivot = CFrame.new(0, 3.0, 0)
	local fish = bobGroup(model, "Fish", pivot, { Height = 0.12, Spin = 0.6, Speed = 0.2 })
	local at = Vector3.new(0.05, 3.0, -0.35)
	egg(fish, "Body", Vector3.new(0.8, 0.5, 0.35), CFrame.new(at), accent)
	egg(fish, "Tail", Vector3.new(0.3, 0.5, 0.1), CFrame.new(at + Vector3.new(0.5, 0, 0)), darken(accent, 0.1))
	ball(fish, "Eye", 0.11, at + Vector3.new(-0.25, 0.07, -0.15), COLORS.Eye)
	finishBob(fish, pivot)

	local bubbles = emitterAt(water, Vector3.new(-0.2, 2.75, -0.55), "Bubbles")
	particles(bubbles, {
		Texture = TEXTURE.Ring,
		Color = ColorSequence.new(COLORS.White),
		Size = NumberSequence.new(0.12, 0.2),
		Transparency = fade(0.2, 1),
		Lifetime = NumberRange.new(1.2, 1.6),
		Rate = 1.2,
		Speed = NumberRange.new(0.5, 0.8),
		SpreadAngle = Vector2.new(10, 10),
		EmissionDirection = Enum.NormalId.Top,
		LightEmission = 0.2,
	})
end

-- A garden arch of flowers, wide enough to walk under.
RECIPES.Arch = function(model, color, accent)
	local solid = { Solid = true }
	local postX, top, radius = 1.65, 4, 1.65
	block(model, "PostLeft", Vector3.new(0.35, top, 0.35), CFrame.new(-postX, top / 2, 0), color, solid)
	block(model, "PostRight", Vector3.new(0.35, top, 0.35), CFrame.new(postX, top / 2, 0), color, solid)
	local segments = 6
	for i = 1, segments do
		local a = math.pi * (i - 0.5) / segments
		local at = Vector3.new(math.cos(a) * radius, top + math.sin(a) * radius, 0)
		block(
			model,
			"Arc",
			Vector3.new(0.35, radius * math.pi / segments + 0.12, 0.35),
			CFrame.new(at) * CFrame.Angles(0, 0, a),
			color
		)
	end
	local flowers = { accent, COLORS.Sunny, lighten(accent, 0.4) }
	for i = 1, 5 do
		local a = math.pi * (i - 0.5) / 5
		local at = Vector3.new(math.cos(a) * radius, top + math.sin(a) * radius, -0.22)
		ball(model, "Flower", 0.6, at, flowers[(i - 1) % #flowers + 1])
	end
	for i, y in { 1.4, 2.9 } do
		ball(model, "Flower", 0.55, Vector3.new(-postX - 0.05, y, -0.22), flowers[i])
		ball(model, "Flower", 0.55, Vector3.new(postX + 0.05, y + 0.4, -0.22), flowers[i + 1])
	end
	egg(
		model,
		"Leaf",
		Vector3.new(0.7, 0.35, 0.2),
		CFrame.new(-1.0, 5.35, -0.2) * CFrame.Angles(0, 0, 0.6),
		COLORS.Leaf
	)
	egg(
		model,
		"Leaf",
		Vector3.new(0.7, 0.35, 0.2),
		CFrame.new(1.0, 5.35, -0.2) * CFrame.Angles(0, 0, -0.6),
		COLORS.Leaf
	)
	egg(model, "Leaf", Vector3.new(0.35, 0.7, 0.2), CFrame.new(-postX + 0.25, 2.1, -0.22), COLORS.Leaf)
end

-- A friendship bench with cushions and a heart on the back.
RECIPES.Bench = function(model, color, accent)
	local solid = { Solid = true }
	block(model, "Seat", Vector3.new(3.6, 0.35, 1.3), CFrame.new(0, 1.2, 0), color, solid)
	for _, x in { -1.45, 1.45 } do
		for _, z in { -0.45, 0.45 } do
			cylinder(model, "Leg", 1.05, 0.3, Vector3.new(x, 0.52, z), accent, solid)
		end
	end
	block(
		model,
		"Back",
		Vector3.new(3.6, 1.4, 0.25),
		CFrame.new(0, 2.15, 0.62) * CFrame.Angles(math.rad(-8), 0, 0),
		color,
		solid
	)
	rod(model, "Rail", 3.75, 0.35, CFrame.new(0, 2.9, 0.72), accent)
	block(model, "ArmLeft", Vector3.new(0.25, 0.6, 1.2), CFrame.new(-1.85, 1.65, 0), accent)
	block(model, "ArmRight", Vector3.new(0.25, 0.6, 1.2), CFrame.new(1.85, 1.65, 0), accent)
	egg(model, "Cushion", Vector3.new(1.45, 0.35, 1.0), CFrame.new(-0.82, 1.48, -0.05), lighten(color, 0.45))
	egg(model, "Cushion", Vector3.new(1.45, 0.35, 1.0), CFrame.new(0.82, 1.48, -0.05), lighten(color, 0.45))
	-- The heart, on the front of the backrest
	local heartZ = 0.45
	ball(model, "HeartLeft", 0.45, Vector3.new(-0.16, 2.33, heartZ), COLORS.Heart)
	ball(model, "HeartRight", 0.45, Vector3.new(0.16, 2.33, heartZ), COLORS.Heart)
	block(
		model,
		"HeartPoint",
		Vector3.new(0.42, 0.42, 0.3),
		CFrame.new(0, 2.15, heartZ) * CFrame.Angles(0, 0, math.rad(45)),
		COLORS.Heart
	)
end

-- A round stone fountain with a gentle spray and a rubber duck bobbing in the basin.
RECIPES.Fountain = function(model, color, accent)
	local solid = { Solid = true }
	cylinder(model, "Basin", 0.9, 3.8, Vector3.new(0, 0.45, 0), COLORS.Stone, solid)
	cylinder(model, "Rim", 0.18, 3.95, Vector3.new(0, 0.96, 0), accent, solid)
	cylinder(model, "Water", 0.1, 3.35, Vector3.new(0, 0.97, 0), color, { Transparency = 0.15 })
	cylinder(model, "Pillar", 1.6, 0.5, Vector3.new(0, 1.8, 0), COLORS.Stone, solid)
	cylinder(model, "Bowl", 0.3, 1.4, Vector3.new(0, 2.6, 0), COLORS.Stone)
	local topWater = cylinder(model, "TopWater", 0.08, 1.15, Vector3.new(0, 2.73, 0), color, { Transparency = 0.15 })

	local spray = emitterAt(topWater, Vector3.new(0, 2.8, 0), "Spray")
	particles(spray, {
		Texture = TEXTURE.SoftDot,
		Color = ColorSequence.new(lighten(color, 0.5)),
		Size = NumberSequence.new(0.22, 0.1),
		Transparency = fade(0.15, 1),
		Lifetime = NumberRange.new(0.8, 1.0),
		Rate = 14,
		Speed = NumberRange.new(3, 3.8),
		SpreadAngle = Vector2.new(14, 14),
		Acceleration = Vector3.new(0, -10, 0),
		EmissionDirection = Enum.NormalId.Top,
		LightEmission = 0.3,
	})

	local pivot = CFrame.new(0.95, 1.02, -0.4)
	local duck = bobGroup(model, "Duck", pivot, { Height = 0.07, Sway = 0.07, Speed = 0.45 })
	egg(duck, "Body", Vector3.new(0.85, 0.6, 1.05), CFrame.new(0.95, 1.2, -0.35), accent)
	ball(duck, "Head", 0.55, Vector3.new(0.95, 1.65, -0.72), accent)
	block(duck, "Beak", Vector3.new(0.3, 0.12, 0.25), CFrame.new(0.95, 1.6, -1.04), COLORS.Orange)
	ball(duck, "Eye", 0.1, Vector3.new(0.8, 1.73, -0.95), COLORS.Eye)
	ball(duck, "Eye", 0.1, Vector3.new(1.1, 1.73, -0.95), COLORS.Eye)
	finishBob(duck, pivot)
end

-- A snow globe with a tiny snowman inside; its base glows at night.
RECIPES.Globe = function(model, color, accent, look)
	local solid = { Solid = true }
	cylinder(model, "Foot", 0.2, 2.4, Vector3.new(0, 0.1, 0), darken(accent, 0.12), solid)
	cylinder(model, "Base", 0.7, 2.2, Vector3.new(0, 0.55, 0), accent, solid)
	local core = cylinder(model, "Light", 0.12, 1.8, Vector3.new(0, 0.96, 0), COLORS.Warm)
	local glass = ball(
		model,
		"Glass",
		2.6,
		Vector3.new(0, 2.15, 0),
		color,
		{ Solid = true, Material = Enum.Material.Glass, Transparency = 0.65 }
	)
	egg(model, "SnowMound", Vector3.new(1.9, 0.6, 1.9), CFrame.new(0, 1.05, 0), COLORS.Snow)
	ball(model, "SnowmanBody", 0.75, Vector3.new(0, 1.55, 0), COLORS.Snow)
	ball(model, "SnowmanHead", 0.52, Vector3.new(0, 2.08, 0), COLORS.Snow)
	ball(model, "Eye", 0.08, Vector3.new(-0.09, 2.15, -0.23), COLORS.Eye)
	ball(model, "Eye", 0.08, Vector3.new(0.09, 2.15, -0.23), COLORS.Eye)
	block(model, "Nose", Vector3.new(0.08, 0.08, 0.22), CFrame.new(0, 2.06, -0.32), COLORS.Orange)
	cylinder(model, "Hat", 0.3, 0.32, Vector3.new(0, 2.43, 0), accent)

	local flakes = emitterAt(glass, Vector3.new(0, 2.7, 0), "Flakes")
	particles(flakes, {
		Texture = TEXTURE.SoftDot,
		Color = ColorSequence.new(COLORS.White),
		Size = NumberSequence.new(0.09),
		Transparency = fade(0.1, 1),
		Lifetime = NumberRange.new(2, 2.6),
		Rate = 5,
		Speed = NumberRange.new(0.15, 0.35),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -0.35, 0),
		LightEmission = 0.4,
	})
	if look.Glow then
		glow(core, lighten(color, 0.3):Lerp(COLORS.Warm, 0.6), 12)
	end
end

-- A paper lantern hanging from a little hooked post; it sways gently. Moon and Comet get a topper.
RECIPES.Lantern = function(model, color, accent, look, flourish)
	local postX, postZ = -1.0, 0.35
	local wood = COLORS.WoodDark
	cylinder(model, "Foot", 0.25, 1.2, Vector3.new(postX, 0.125, postZ), wood, { Solid = true })
	cylinder(model, "Post", 4.8, 0.25, Vector3.new(postX, 2.5, postZ), wood, { Solid = true })
	block(model, "Arm", Vector3.new(1.35, 0.18, 0.18), CFrame.new(postX + 0.6, 4.8, postZ), wood)

	local hookX = postX + 1.15
	local pivot = CFrame.new(hookX, 4.72, postZ)
	local group = bobGroup(model, "Lantern", pivot, { Sway = 0.06, Speed = 0.3 })
	rodBetween(group, "Cord", Vector3.new(hookX, 4.72, postZ), Vector3.new(hookX, 4.35, postZ), 0.07, wood)
	cylinder(group, "Cap", 0.22, 0.75, Vector3.new(hookX, 4.25, postZ), darken(color, 0.25))
	local body = egg(group, "Body", Vector3.new(1.25, 1.5, 1.25), CFrame.new(hookX, 3.4, postZ), color)
	cylinder(group, "Band", 0.12, 1.28, Vector3.new(hookX, 3.4, postZ), accent)
	cylinder(group, "Bottom", 0.2, 0.6, Vector3.new(hookX, 2.6, postZ), darken(color, 0.25))
	egg(group, "Tassel", Vector3.new(0.2, 0.5, 0.2), CFrame.new(hookX, 2.25, postZ), accent)
	finishBob(group, pivot)
	if look.Glow then
		glow(body, accent:Lerp(COLORS.Warm, 0.4), 12)
	end

	local topY = 5.15
	if flourish == "Moon" then
		ball(model, "Moon", 0.62, Vector3.new(postX, topY, postZ), accent)
		ball(model, "MoonShade", 0.5, Vector3.new(postX + 0.2, topY + 0.1, postZ - 0.12), darken(color, 0.1))
	elseif flourish == "Comet" then
		local star = ball(model, "Comet", 0.6, Vector3.new(postX, topY, postZ), color)
		ball(model, "Tail", 0.42, Vector3.new(postX + 0.38, topY - 0.25, postZ + 0.1), accent)
		ball(model, "Tail", 0.28, Vector3.new(postX + 0.68, topY - 0.45, postZ + 0.18), lighten(accent, 0.3))
		local twinkle = emitterAt(star, star.CFrame.Position, "Twinkle")
		particles(twinkle, {
			Texture = TEXTURE.Sparkle,
			Color = ColorSequence.new(lighten(color, 0.4)),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0.45),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Lifetime = NumberRange.new(1.2, 1.6),
			Rate = 1.5,
			Speed = NumberRange.new(0.2, 0.5),
			SpreadAngle = Vector2.new(180, 180),
			LightEmission = 0.6,
		})
	else
		ball(model, "Knob", 0.4, Vector3.new(postX, topY - 0.15, postZ), accent)
	end
end

-- A happy little mascot on a pedestal (the Shy Sprout's thank-you). It bounces softly.
RECIPES.Statue = function(model, color, accent)
	cylinder(model, "Pedestal", 0.8, 2.4, Vector3.new(0, 0.4, 0), accent, { Solid = true })
	cylinder(model, "Trim", 0.15, 2.6, Vector3.new(0, 0.86, 0), darken(accent, 0.08), { Solid = true })

	local pivot = CFrame.new(0, 0.93, 0)
	local body = bobGroup(model, "Mascot", pivot, { Height = 0.12, Speed = 0.5 })
	egg(body, "Body", Vector3.new(1.8, 1.9, 1.7), CFrame.new(0, 1.9, 0), color, { Solid = true })
	ball(body, "Eye", 0.32, Vector3.new(-0.33, 2.1, -0.74), COLORS.Eye)
	ball(body, "Eye", 0.32, Vector3.new(0.33, 2.1, -0.74), COLORS.Eye)
	ball(body, "Twinkle", 0.1, Vector3.new(-0.28, 2.18, -0.88), COLORS.White)
	ball(body, "Twinkle", 0.1, Vector3.new(0.38, 2.18, -0.88), COLORS.White)
	badge(body, "Cheek", 0.32, Vector3.new(-0.56, 1.88, -0.67), COLORS.Cheek)
	badge(body, "Cheek", 0.32, Vector3.new(0.56, 1.88, -0.67), COLORS.Cheek)
	egg(body, "Smile", Vector3.new(0.26, 0.1, 0.1), CFrame.new(0, 1.82, -0.84), COLORS.Eye)
	cylinder(body, "Stem", 0.5, 0.12, Vector3.new(0, 3.05, 0), darken(color, 0.25))
	egg(
		body,
		"Leaf",
		Vector3.new(0.75, 0.12, 0.38),
		CFrame.new(-0.32, 3.3, 0) * CFrame.Angles(0, 0, 0.5),
		lighten(color, 0.15)
	)
	egg(
		body,
		"Leaf",
		Vector3.new(0.75, 0.12, 0.38),
		CFrame.new(0.32, 3.3, 0) * CFrame.Angles(0, 0, -0.5),
		lighten(color, 0.15)
	)
	finishBob(body, pivot)
end

-- A round teapot with a four-leaf clover, on a little table, letting off a wisp of steam.
RECIPES.Kettle = function(model, color, accent)
	local solid = { Solid = true }
	cylinder(model, "Foot", 0.15, 1.2, Vector3.new(0, 0.075, 0), COLORS.Wood, solid)
	cylinder(model, "Leg", 1.45, 0.3, Vector3.new(0, 0.85, 0), COLORS.Wood, solid)
	cylinder(model, "Table", 0.2, 2.3, Vector3.new(0, 1.65, 0), COLORS.Wood, solid)

	egg(model, "Body", Vector3.new(1.7, 1.3, 1.5), CFrame.new(0, 2.4, 0), color)
	cylinder(model, "Lid", 0.2, 0.9, Vector3.new(0, 3.05, 0), darken(color, 0.1))
	ball(model, "Knob", 0.32, Vector3.new(0, 3.25, 0), accent)
	local spout = rod(model, "Spout", 0.85, 0.26, CFrame.new(-1.0, 2.65, 0) * CFrame.Angles(0, 0, math.rad(-45)), color)
	block(model, "HandleTop", Vector3.new(0.45, 0.16, 0.2), CFrame.new(0.95, 2.85, 0), darken(color, 0.1))
	block(model, "HandleSide", Vector3.new(0.16, 0.75, 0.2), CFrame.new(1.12, 2.5, 0), darken(color, 0.1))
	block(model, "HandleBottom", Vector3.new(0.4, 0.16, 0.2), CFrame.new(0.92, 2.15, 0), darken(color, 0.1))
	-- The lucky clover, on the front
	for _, offset in
		{ Vector2.new(-0.14, 0.14), Vector2.new(0.14, 0.14), Vector2.new(-0.14, -0.14), Vector2.new(0.14, -0.14) }
	do
		badge(model, "Clover", 0.3, Vector3.new(offset.X, 2.45 + offset.Y, -0.74), accent)
	end
	block(
		model,
		"CloverStem",
		Vector3.new(0.05, 0.3, 0.05),
		CFrame.new(0.05, 2.17, -0.73) * CFrame.Angles(0, 0, 0.3),
		darken(accent, 0.2)
	)

	local steam = emitterAt(spout, spout.CFrame * Vector3.new(-0.45, 0, 0), "Steam") -- the spout's tip
	particles(steam, {
		Texture = TEXTURE.Puff,
		Color = ColorSequence.new(COLORS.White),
		Size = NumberSequence.new(0.3, 0.9),
		Transparency = fade(0.55, 1),
		Lifetime = NumberRange.new(1.6, 2.2),
		Rate = 1.2,
		Speed = NumberRange.new(0.5, 0.8),
		SpreadAngle = Vector2.new(15, 15),
		Acceleration = Vector3.new(0, 0.4, 0),
		EmissionDirection = Enum.NormalId.Top,
		RotSpeed = NumberRange.new(-20, 20),
	})
end

-- Anything else: a wrapped gift with a bow.
local function giftBox(model: Model, color: Color3, accent: Color3)
	block(model, "Box", Vector3.new(1.8, 1.6, 1.8), CFrame.new(0, 0.8, 0), color, { Solid = true })
	block(model, "RibbonX", Vector3.new(1.84, 1.61, 0.3), CFrame.new(0, 0.805, 0), accent)
	block(model, "RibbonZ", Vector3.new(0.3, 1.61, 1.84), CFrame.new(0, 0.805, 0), accent)
	egg(model, "Bow", Vector3.new(0.7, 0.45, 0.3), CFrame.new(-0.3, 1.75, 0) * CFrame.Angles(0, 0, 0.5), accent)
	egg(model, "Bow", Vector3.new(0.7, 0.45, 0.3), CFrame.new(0.3, 1.75, 0) * CFrame.Angles(0, 0, -0.5), accent)
end

DecorBuilder.KINDS = table.freeze({
	"Rug",
	"Plant",
	"Lamp",
	"Balloons",
	"Shelf",
	"Bowl",
	"Arch",
	"Bench",
	"Fountain",
	"Globe",
	"Lantern",
	"Statue",
	"Kettle",
})

------------------------------------------------------------------------------------------------------------------
-- Building
------------------------------------------------------------------------------------------------------------------

local function hexColor(hex: any, fallback: Color3): Color3
	if type(hex) ~= "string" then
		return fallback
	end
	local ok, color = pcall(Color3.fromHex, hex)
	return if ok then color else fallback
end

local function placeholder(decorId: string): Model
	local entry = Decor[decorId]
	local look: Look = if entry then entry.Look else { Kind = "Gift", Color = "#FFB7D5", Accent = "#FFFFFF" }
	local color = candy(hexColor(look.Color, Palette.Candy.Pink))
	local accent = candy(hexColor(look.Accent, COLORS.White))

	local model = Instance.new("Model")
	model.Name = decorId
	model:SetAttribute("Kind", look.Kind)
	local recipe = RECIPES[look.Kind]
	if recipe then
		recipe(model, color, accent, look, FLOURISH[decorId])
	else
		giftBox(model, color, accent)
	end
	model.WorldPivot = CFrame.identity -- the bottom centre
	return model
end

-- The brother's model, cloned, scrubbed of scripts, and pivoted at its bottom centre (keeping his facing).
local function fromKit(decorId: string): Model?
	local kit = ServerStorage:FindFirstChild("ClinicKit")
	local folder = kit and kit:FindFirstChild("Decor")
	local source = folder and folder:FindFirstChild(decorId)
	if not source then
		return nil
	end

	local model: Model
	if source:IsA("Model") then
		model = source:Clone()
	elseif source:IsA("BasePart") then
		model = Instance.new("Model")
		local part = source:Clone()
		part.Parent = model
		model.WorldPivot = part.CFrame
	else
		warn("[DecorBuilder] ClinicKit.Decor." .. decorId .. " must be a Model or a Part; using the placeholder")
		return nil
	end
	model.Name = decorId

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			warn("[DecorBuilder] Removed a script from ClinicKit.Decor." .. decorId .. " (decor is visual only)")
			descendant:Destroy()
		elseif descendant:IsA("Highlight") then
			descendant:Destroy() -- the perf budget: at most one Highlight in the world
		elseif descendant:IsA("Light") then
			descendant.Shadows = false -- the perf budget: no shadow-casting lights
		end
	end
	if not model:FindFirstChildWhichIsA("BasePart", true) then
		warn("[DecorBuilder] ClinicKit.Decor." .. decorId .. " has no parts; using the placeholder")
		model:Destroy()
		return nil
	end

	local box, size = model:GetBoundingBox() -- oriented like the model's pivot
	model.PrimaryPart = nil
	model.WorldPivot = box * CFrame.new(0, -size.Y / 2, 0)
	if math.max(size.X, size.Z) > 4.5 then
		warn(
			string.format(
				"[DecorBuilder] ClinicKit.Decor.%s is %.1f x %.1f studs; slots are 4 x 4",
				decorId,
				size.X,
				size.Z
			)
		)
	end
	return model
end

local templates: { [string]: Model } = {}
local MAX_PARTS = 25 -- per decor piece (the perf budget)
local checkedParts: { [string]: boolean } = {}

local function countParts(model: Model): number
	local parts = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts += 1
		end
	end
	return parts
end

function DecorBuilder.build(decorId: string): Model
	local kitModel = fromKit(decorId)
	local model: Model
	if kitModel then
		model = kitModel
	else
		local template = templates[decorId]
		if not template then
			template = placeholder(decorId)
			templates[decorId] = template
		end
		model = template:Clone()
	end
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("DecorId", decorId)
	if not checkedParts[decorId] then
		checkedParts[decorId] = true -- once per DecorId (a kit model swapped in mid-session isn't re-checked)
		local parts = countParts(model)
		if parts > MAX_PARTS then
			warn(("[DecorBuilder] %s has %d parts (budget %d per piece)"):format(decorId, parts, MAX_PARTS))
		end
	end
	return model
end

function DecorBuilder.start() end

return DecorBuilder
