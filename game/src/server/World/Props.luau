--!strict
-- The shared scenery pieces (look build plan §B4/§B5; art-direction §2.4, §4.1): the town, the plots and the Hall of
-- Fame all use them, so they read as one family. Server only. OWNER: T2 (the signatures and the part counts are
-- contract; the bodies are T2's).
-- `at` is a CFrame on the ground where the piece stands (its LookVector is the piece's front).
--   Props.tree(parent, at, scale, blossom?): Model   6 parts: a Trunk block (Wood) and 5 studded voxel cubes of 4, 3, 3,
--                                                    3 and 2 studs (x scale, whole studs) in LeavesA / LeavesB /
--                                                    LeavesC; blossom = pink leaves (the CALLER keeps blossoms to at
--                                                    most 1 tree in 6: art-direction §4.2; the Model's attribute
--                                                    Blossom says which). Leaves are walk-through
--   Props.bush(parent, at): BasePart                 exactly 1 part: one studded cube in LeavesB, walk-through
--   Props.lamp(parent, at, height): Model            3 parts: a dark square post, a dark cap and a head that is a
--                                                    NightLights "Lamp" (Neon and lit at night only)
--   Props.bench(parent, at): Model                   3 parts: a plank seat and back on one dark base; whoever sits on
--                                                    it faces along `at`'s LookVector
--   Props.fence(parent, a, b): Model                 floor(length / 14) + 1 warm-white posts (so at least 14 studs
--                                                    apart) + 2 rails, from a to b: <= 2 + floor(length / 14) + 1 parts
--   Props.planter(parent, at, size): Model           2 parts: a plank box and a studded bed of leaves on top
--   Props.kiosk(parent, at, spec): Kiosk             the town's kiosk shell (Server/Agency and Server/Market build
--                                                    theirs with it, so the two match): studded walls in spec.Accent, a
--                                                    dark flat roof with a warm-white edge (no striped awning), a
--                                                    counter, and the name in floating outlined letters over the roof.
--                                                    spec = { Name, Title, Lines?, Accent, Size? (Vector2 width x depth,
--                                                    default 7 x 4.5) }. 9 parts. Returns { Model, Counter,
--                                                    Front (the floating text's part) }. The caller adds its prompt
-- No Texture, Decal, Highlight or shadow-casting light anywhere (the perf budget). Studded parts go through
-- World/Studs (whole-stud sizes: Studs.Pure.whole); smooth ones are SmoothPlastic, Wood, WoodPlanks or Slate. No colour
-- is lightened toward white (art-direction §4.1): every colour is a Palette.World or Palette.Accent value.

local Shared = game:GetService("ReplicatedStorage").Shared
local Palette = require(Shared.Palette)
local NightLights = require(script.Parent.NightLights)
local Parts = require(script.Parent.Parts)
local Studs = require(script.Parent.Studs)

local part, soft = Parts.part, Parts.soft
local darken = Parts.darken
local whole = Studs.Pure.whole

local Props = {}

local WORLD = Palette.World
local ACCENT = Palette.Accent

local COLORS = {
	Trunk = WORLD.Trunk,
	Bush = WORLD.LeavesB,
	LampPost = WORLD.Roof,
	LampGlow = WORLD.Lamp,
	BenchSeat = WORLD.Plank,
	BenchBase = WORLD.Roof,
	Fence = WORLD.Fence,
	KioskBase = WORLD.Plank,
	KioskRoof = WORLD.Roof,
	KioskTrim = WORLD.Trim,
}

-- The voxel crown, biggest cube first: { size (studs at scale 1), x, y above the trunk's top, z, leaf colour }.
type Cube = { Size: number, X: number, Y: number, Z: number, Leaf: number }
local CROWN: { Cube } = {
	{ Size = 4, X = 0, Y = 2, Z = 0, Leaf = 1 },
	{ Size = 3, X = 1.5, Y = 1.5, Z = 1.5, Leaf = 2 },
	{ Size = 3, X = -1.5, Y = 2.5, Z = -1, Leaf = 2 },
	{ Size = 3, X = 0.5, Y = 4.5, Z = -0.5, Leaf = 3 },
	{ Size = 2, X = -0.5, Y = 6, Z = 1, Leaf = 3 },
}
local TRUNK = { Width = 2, Height = 4 } -- at scale 1
local LEAVES = { WORLD.LeavesA, WORLD.LeavesB, WORLD.LeavesC }
local BLOSSOM = { ACCENT.Pink, darken(ACCENT.Pink, 0.15), darken(ACCENT.Pink, 0.3) }

-- A voxel tree: a trunk block and five studded leaf cubes. `blossom` makes it a pink blossom tree.
function Props.tree(parent: Instance, at: CFrame, scale: number, blossom: boolean?): Model
	local s = if type(scale) == "number" and scale > 0 then scale else 1
	local leaves = if blossom then BLOSSOM else LEAVES
	local model = Instance.new("Model")
	model.Name = "Tree"
	local trunkWidth = whole(TRUNK.Width * s)
	local trunkHeight = math.max(2, math.floor(TRUNK.Height * s + 0.5))
	part(
		model,
		"Trunk",
		Vector3.new(trunkWidth, trunkHeight, trunkWidth),
		at * CFrame.new(0, trunkHeight / 2, 0),
		COLORS.Trunk,
		Enum.Material.Wood
	)
	for _, cube in CROWN do
		local side = whole(cube.Size * s)
		local leaf = part(
			model,
			"Leaves",
			Vector3.new(side, side, side),
			at * CFrame.new(cube.X * s, trunkHeight + cube.Y * s, cube.Z * s),
			leaves[cube.Leaf]
		)
		Studs.apply(soft(leaf) :: BasePart)
	end
	model:SetAttribute("Blossom", blossom == true)
	model.Parent = parent
	return model
end

-- One studded cube, its bottom on the ground. Walk-through and ray-ignored, like the old round bushes.
function Props.bush(parent: Instance, at: CFrame): BasePart
	local side = 3
	local bush = part(parent, "Bush", Vector3.new(side, side, side), at * CFrame.new(0, side / 2, 0), COLORS.Bush)
	soft(bush)
	Studs.apply(bush)
	return bush
end

-- A street lamp: a dark square post, a dark cap, and a head that glows at night (NightLights "Lamp").
function Props.lamp(parent: Instance, at: CFrame, height: number): Model
	local model = Instance.new("Model")
	model.Name = "Lamp"
	part(model, "Post", Vector3.new(0.6, height, 0.6), at * CFrame.new(0, height / 2, 0), COLORS.LampPost)
	soft(part(model, "Cap", Vector3.new(1.6, 0.4, 1.6), at * CFrame.new(0, height + 1.4, 0), COLORS.LampPost))
	local head =
		soft(part(model, "Glow", Vector3.new(1.2, 1.2, 1.2), at * CFrame.new(0, height + 0.6, 0), COLORS.LampGlow))
	head.CastShadow = false
	NightLights.light(head, 18)
	model.Parent = parent
	return model
end

-- A bench: a plank seat and back on one dark base. The back is behind (+z), so a sitter faces -z (the LookVector).
function Props.bench(parent: Instance, at: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Bench"
	part(
		model,
		"Seat",
		Vector3.new(5, 0.4, 1.6),
		at * CFrame.new(0, 1.4, 0),
		COLORS.BenchSeat,
		Enum.Material.WoodPlanks
	)
	part(
		model,
		"Back",
		Vector3.new(5, 1.4, 0.3),
		at * CFrame.new(0, 2.3, 0.7),
		COLORS.BenchSeat,
		Enum.Material.WoodPlanks
	)
	part(model, "Base", Vector3.new(4, 1.2, 1.2), at * CFrame.new(0, 0.6, 0), COLORS.BenchBase)
	model.Parent = parent
	return model
end

-- floor(length / 14) + 1 posts, evenly spaced from a to b (so at least 14 studs apart; a piece shorter than 14 has
-- one post in its middle), and two rails (CFrames on the ground).
local FENCE_STEP = 14
function Props.fence(parent: Instance, a: CFrame, b: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Fence"
	local from, to = a.Position, b.Position
	local length = (to - from).Magnitude
	local posts = math.floor(length / FENCE_STEP + 1e-6) + 1
	for i = 0, posts - 1 do
		local p = if posts == 1 then from:Lerp(to, 0.5) else from:Lerp(to, i / (posts - 1))
		part(model, "FencePost", Vector3.new(0.8, 3, 0.8), a.Rotation + p + Vector3.new(0, 1.5, 0), COLORS.Fence)
	end
	local middle = (from + to) / 2
	for _, y in { 1.1, 2.3 } do
		local cf = if length > 1e-3
			then CFrame.lookAt(middle + Vector3.new(0, y, 0), to + Vector3.new(0, y, 0))
			else a.Rotation + middle + Vector3.new(0, y, 0)
		part(model, "FenceRail", Vector3.new(0.3, 0.35, math.max(length, 0.1)), cf, COLORS.Fence)
	end
	model.Parent = parent
	return model
end

-- A planter: a box in the plank colour with a studded bed of leaves on top. `size` is the box (x, y, z).
function Props.planter(parent: Instance, at: CFrame, size: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Planter"
	part(model, "Box", size, at * CFrame.new(0, size.Y / 2, 0), WORLD.PlankAlt, Enum.Material.WoodPlanks)
	local greens = soft(
		part(
			model,
			"Greens",
			Vector3.new(math.max(size.X - 1, 1), 1, math.max(size.Z - 1, 1)),
			at * CFrame.new(0, size.Y + 0.5, 0),
			WORLD.LeavesA
		)
	)
	Studs.apply(greens)
	model.Parent = parent
	return model
end

------------------------------------------------------------------------------------------------------------------
-- The kiosk shell (Server/Agency and Server/Market)
------------------------------------------------------------------------------------------------------------------

export type KioskSpec = {
	Name: string, -- the Model's name (NurseAgency, PlayerMarket)
	Title: string, -- the floating name over the roof ("🏢 AGENCY")
	Lines: { string }?, -- up to two short floating lines under it (each 6 words or fewer)
	Accent: Color3, -- the walls (studded) and the counter's body
	Size: Vector2?, -- width x depth (studs), default 7 x 4.5
}
export type Kiosk = { Model: Model, Counter: BasePart, Front: BasePart }

local KIOSK_SIZE = Vector2.new(7, 4.5)
local KIOSK_WALL = 6 -- the walls' height above the base
local KIOSK_TEXT_PIXELS = 40

-- `at` is the ground under its middle, its LookVector the counter's front (toward the spawn).
function Props.kiosk(parent: Instance?, at: CFrame, spec: KioskSpec): Kiosk
	local size = spec.Size or KIOSK_SIZE
	local width, depth = size.X, size.Y
	local accent = spec.Accent
	local model = Instance.new("Model")
	model.Name = spec.Name

	local base = part(model, "Base", Vector3.new(width, 0.4, depth), at * CFrame.new(0, 0.2, 0), COLORS.KioskBase)
	base.Material = Enum.Material.WoodPlanks
	model.PrimaryPart = base

	-- Studded walls in the accent: the back and two sides (the front stays open over the counter). Whole-stud sizes
	-- (the alignment rule); each side runs into the back wall.
	local wallY = 0.4 + KIOSK_WALL / 2
	local back =
		part(model, "WallBack", Vector3.new(width, KIOSK_WALL, 1), at * CFrame.new(0, wallY, depth / 2 - 0.5), accent)
	Studs.apply(back)
	local sideLength = whole(depth - 0.5)
	for _, side in { -1, 1 } do
		local wall = part(
			model,
			"WallSide",
			Vector3.new(1, KIOSK_WALL, sideLength),
			at * CFrame.new(side * (width / 2 - 0.5), wallY, -depth / 2 + sideLength / 2),
			accent
		)
		Studs.apply(wall)
	end

	-- The counter: a smooth body in the accent, a studded warm-white top (prop tops are studded, §B4).
	local counter = part(
		model,
		"Counter",
		Vector3.new(width - 2, 2.6, 1.2),
		at * CFrame.new(0, 0.4 + 1.3, -(depth / 2 - 0.9)),
		darken(accent, 0.12)
	)
	local top = soft(
		part(
			model,
			"CounterTop",
			Vector3.new(width - 1, 0.4, 2),
			at * CFrame.new(0, 0.4 + 2.6 + 0.2, -(depth / 2 - 1)),
			COLORS.KioskTrim
		)
	)
	Studs.apply(top)

	-- The roof: a dark flat slab with a warm-white edge band (no striped awning).
	local roofY = 0.4 + KIOSK_WALL + 0.3
	part(model, "Roof", Vector3.new(width + 1, 0.6, depth + 1), at * CFrame.new(0, roofY, 0), COLORS.KioskRoof)
	soft(
		part(
			model,
			"RoofTrim",
			Vector3.new(width + 1.1, 0.3, depth + 1.1),
			at * CFrame.new(0, roofY - 0.45, 0),
			COLORS.KioskTrim
		)
	)

	-- The name floats over the roof in outlined letters (art-direction §4.4: no board), facing the front.
	local lines = spec.Lines or {}
	local textHeight = 2.2 + 0.9 * math.min(#lines, 2)
	local front = soft(
		part(
			model,
			"FrontText",
			Vector3.new(width + 2, textHeight, 0.2),
			at * CFrame.new(0, roofY + 0.3 + textHeight / 2, -(depth / 2) + 0.4),
			COLORS.KioskTrim
		)
	)
	front.Transparency = 1
	front.CastShadow = false
	local gui = Parts.surface(front, "KioskGui", Enum.NormalId.Front, KIOSK_TEXT_PIXELS, 160, 0)
	local titleShare = 2.2 / textHeight
	Parts.floatText(gui, spec.Title, {
		Shadow = true,
		Size = UDim2.fromScale(1, titleShare),
		Position = UDim2.fromScale(0, 0),
	})
	for index = 1, math.min(#lines, 2) do
		local share = 0.9 / textHeight
		Parts.floatText(gui, lines[index], {
			Gold = true,
			Size = UDim2.fromScale(0.92, share * 0.9),
			Position = UDim2.fromScale(0.04, titleShare + share * (index - 1)),
		})
	end

	model.WorldPivot = at
	if parent then
		model.Parent = parent
	end
	return { Model = model, Counter = counter, Front = front }
end

return Props
