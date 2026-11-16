--!strict
-- The shared scenery pieces (look build plan §B4): the town and the plots both use them. Server only. Moved from
-- PlotBuilder by the look overhaul's Foundation, look unchanged; T2 owns the implementation and rebuilds each piece
-- to the contract below (the signatures and the part counts are frozen).
-- `at` is a CFrame on the ground where the piece stands.
--   Props.tree(parent, at, scale, blossom?): Model   <= 7 parts (voxel: 5-7 studded cubes on a Trunk block;
--                                                    blossom = pink leaves, at most 1 tree in 6)
--   Props.bush(parent, at): BasePart                 exactly 1 part (one studded cube)
--   Props.lamp(parent, at, height): Model            <= 3 parts; its head is a NightLights "Lamp"
--   Props.bench(parent, at): Model                   <= 3 parts
--   Props.fence(parent, a, b): Model                 posts every 14 studs + 2 rails: <= 2 + floor(length / 14) + 1
--   Props.planter(parent, at, size): Model           <= 2 parts
-- STUB (T2): tree (5 parts, round), bush (4 parts), bench (4 parts) and fence (posts every 10) are still today's
-- candy pieces, so their part counts are over the contract until T2 lands.

local Shared = game:GetService("ReplicatedStorage").Shared
local Palette = require(Shared.Palette)
local NightLights = require(script.Parent.NightLights)
local Parts = require(script.Parent.Parts)
local Studs = require(script.Parent.Studs)

local part, soft, ball, cylinder = Parts.part, Parts.soft, Parts.ball, Parts.cylinder
local lighten = Parts.lighten

local Props = {}

local WHITE = Palette.White
local CANDY = Palette.Candy
local WORLD = Palette.World

local COLORS = {
	Trunk = WORLD.Trunk,
	Bush = WORLD.GrassDark,
	LampPost = CANDY.Purple,
	LampGlow = WORLD.Lamp,
	Bench = CANDY.Blue,
	Fence = WORLD.Fence,
}
-- Tree crowns, biggest ball first. Some trees are pink blossom trees.
local LEAVES =
	{ WORLD.Leaves, WORLD.LeavesLight, WORLD.Leaves:Lerp(WORLD.LeavesLight, 0.5), lighten(WORLD.LeavesLight, 0.2) }
local BLOSSOM = { lighten(CANDY.Pink, 0.2), lighten(CANDY.Pink, 0.45), CANDY.Pink, lighten(CANDY.Pink, 0.6) }
local FLOWERS = { CANDY.Pink, CANDY.Yellow, WHITE, CANDY.Purple, CANDY.Red, CANDY.Orange }

-- A round, layered toy tree: a trunk and four stacked balls. `blossom` makes it a pink blossom tree.
function Props.tree(parent: Instance, at: CFrame, scale: number, blossom: boolean?): Model
	local crown = if blossom then BLOSSOM else LEAVES
	local model = Instance.new("Model")
	model.Name = "Tree"
	cylinder(model, "Trunk", 6 * scale, 1.4 * scale, at * CFrame.new(0, 3 * scale, 0), COLORS.Trunk)
	soft(ball(model, "Leaves", 7 * scale, at * CFrame.new(0, 7 * scale, 0), crown[1]))
	soft(ball(model, "Leaves", 5.5 * scale, at * CFrame.new(1.8 * scale, 8.8 * scale, 0.6 * scale), crown[2]))
	soft(ball(model, "Leaves", 5 * scale, at * CFrame.new(-1.6 * scale, 8.4 * scale, -1 * scale), crown[3]))
	soft(ball(model, "Leaves", 4 * scale, at * CFrame.new(0.2 * scale, 10.6 * scale, -0.2 * scale), crown[4]))
	model.Parent = parent
	return model
end

-- STUB (T2): the contract is exactly ONE studded cube. Until T2 lands this is today's round bush (4 parts); its
-- flowers take the next colour in turn.
local bushes = 0
function Props.bush(parent: Instance, at: CFrame): BasePart
	bushes += 1
	local flower = FLOWERS[bushes % #FLOWERS + 1]
	local model = Instance.new("Model")
	model.Name = "Bush"
	local leaves = soft(ball(model, "Leaves", 2.8, at * CFrame.new(0, 0.9, 0), COLORS.Bush))
	soft(ball(model, "Flower", 0.7, at * CFrame.new(0.6, 2.2, -0.4), flower))
	soft(ball(model, "Flower", 0.6, at * CFrame.new(-0.7, 2.0, 0.3), flower))
	soft(ball(model, "Flower", 0.6, at * CFrame.new(0.1, 2.25, 0.8), flower))
	model.Parent = parent
	return leaves
end

function Props.lamp(parent: Instance, at: CFrame, height: number): Model
	local model = Instance.new("Model")
	model.Name = "Lamp"
	cylinder(model, "Post", height, 0.5, at * CFrame.new(0, height / 2, 0), COLORS.LampPost)
	cylinder(model, "Cap", 0.3, 1.6, at * CFrame.new(0, height + 1.05, 0), COLORS.LampPost)
	local head = soft(ball(model, "Glow", 1.4, at * CFrame.new(0, height + 0.3, 0), COLORS.LampGlow))
	NightLights.light(head, 18)
	model.Parent = parent
	return model
end

function Props.bench(parent: Instance, at: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Bench"
	part(model, "Seat", Vector3.new(5, 0.4, 1.6), at * CFrame.new(0, 1.4, 0), COLORS.Bench)
	part(model, "Back", Vector3.new(5, 1.4, 0.3), at * CFrame.new(0, 2.3, 0.7), COLORS.Bench)
	part(model, "Leg", Vector3.new(0.4, 1.2, 1.4), at * CFrame.new(-2.1, 0.6, 0), WHITE)
	part(model, "Leg", Vector3.new(0.4, 1.2, 1.4), at * CFrame.new(2.1, 0.6, 0), WHITE)
	model.Parent = parent
	return model
end

-- Posts every <= 10 studs and two rails, from a to b (CFrames on the ground).
-- STUB (T2): the contract is posts every 14 studs (<= 2 + floor(length / 14) + 1 parts).
function Props.fence(parent: Instance, a: CFrame, b: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Fence"
	local from, to = a.Position, b.Position
	local length = (to - from).Magnitude
	local segments = math.max(1, math.ceil(length / 10))
	for i = 0, segments do
		local p = from:Lerp(to, i / segments)
		part(model, "FencePost", Vector3.new(0.8, 3, 0.8), a.Rotation + p + Vector3.new(0, 1.5, 0), COLORS.Fence)
	end
	local middle = (from + to) / 2
	for _, y in { 1.1, 2.3 } do
		local cf = CFrame.lookAt(middle + Vector3.new(0, y, 0), to + Vector3.new(0, y, 0))
		part(model, "FenceRail", Vector3.new(0.3, 0.35, length), cf, COLORS.Fence)
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

return Props
