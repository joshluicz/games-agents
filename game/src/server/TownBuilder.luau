--!strict
-- The town round the plots (look build plan §B4/§B5). Server only. Moved from PlotBuilder by the look overhaul's
-- Foundation; T2 owns it and rebuilds it to §B5 (the dark smooth road, the row-2 plaza, the studded checker lawns,
-- voxel trees, floating text on the arches).
--   TownBuilder.build(count): Model        Workspace.ClinicTown for `count` plots (NOT parented: PlotBuilder does)
--   TownBuilder.spawn(): SpawnLocation     TownSpawn at Config.Town.Origin + Config.Town.SpawnOffset (a kit one,
--                                          already in Workspace, is kept)
-- It never requires PlotBuilder (PlotBuilder requires this). The street's half width, the plot gap and the lawn's
-- height are repeated from PlotBuilder: tests/TownLayout.spec checks the two files agree.
--
-- STUB (T2): everything in `build` is still the candy town, laid out for the old belt. The Nurse Belt now runs down
-- the road's centre line (Config.Belt.Offset z = 0, memory-20261117-001 #3), so until T2 lands the old plaza disc,
-- its planters, the two benches at x = +-15 and the centre dashes sit in the belt's lane (Config.Town.BeltClear).
-- Only the spawn has moved already (Config.Town.SpawnOffset / SpawnSize).

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local Parts = require(script.Parent.World.Parts)
local Props = require(script.Parent.World.Props)

local part, soft, ball, cylinder, paint = Parts.part, Parts.soft, Parts.ball, Parts.cylinder, Parts.paint
local candyLabel, candyBoard = Parts.candyLabel, Parts.candyBoard
local darken = Parts.darken

local TownBuilder = {}

local STREET_HALF_WIDTH = 18
local PLOT_GAP = 8
local BASE_TOP = 0.3 -- the town lawn's top, just above a default baseplate at y = 0

local WHITE = Palette.White
local CANDY = Palette.Candy
local WORLD = Palette.World

local COLORS = {
	TownLawn = WORLD.GrassDark,
	Lawn = WORLD.Grass,
	Street = WORLD.Street,
	StreetLine = WORLD.StreetLine,
	Curb = WHITE,
	PlazaRing = CANDY.Pink,
	Plaza = WORLD.Path,
	Spawn = CANDY.Yellow,
}
local PLANTERS = { CANDY.Pink, CANDY.Blue, CANDY.Yellow, CANDY.Purple }

function TownBuilder.build(count: number): Model
	local origin = Config.Town.Origin
	local size = Config.Town.PlotSize
	local perRow = math.ceil(count / 2)
	local width = perRow * (size + PLOT_GAP) + 40
	local depth = 2 * (STREET_HALF_WIDTH + size) + 40
	local h = STREET_HALF_WIDTH
	local ground = CFrame.new(origin + Vector3.new(0, BASE_TOP, 0))

	local town = Instance.new("Model")
	town.Name = "ClinicTown"

	part(town, "TownLawn", Vector3.new(width, 2, depth), ground * CFrame.new(0, -1, 0), COLORS.TownLawn)
	part(town, "Street", Vector3.new(width, 0.2, h * 2), ground * CFrame.new(0, 0.1, 0), COLORS.Street)
	for _, side in { -1, 1 } do
		part(town, "Curb", Vector3.new(width, 0.4, 0.8), ground * CFrame.new(0, 0.2, side * (h - 0.4)), COLORS.Curb)
	end
	-- The plaza: a candy-pink ring round a cream disc.
	local plazaRadius = h - 1
	cylinder(town, "Plaza", 0.2, plazaRadius * 2, ground * CFrame.new(0, 0.3, 0), COLORS.PlazaRing)
	cylinder(town, "PlazaInner", 0.25, plazaRadius * 2 - 4, ground * CFrame.new(0, 0.325, 0), COLORS.Plaza)

	-- Road paint: a white zebra crossing in front of each pair of facing gates (the middle pair opens onto the
	-- plaza), and white dashes down the middle of the street.
	local crossings: { number } = {}
	for column = 1, perRow do
		local x = (column - (perRow + 1) / 2) * (size + PLOT_GAP)
		if math.abs(x) > plazaRadius + 4 then
			table.insert(crossings, x)
			for z = -(h - 4), h - 4, 4 do
				paint(
					part(town, "Crossing", Vector3.new(8, 0.05, 2), ground * CFrame.new(x, 0.235, z), COLORS.StreetLine)
				)
			end
		end
	end
	local function nearCrossing(x: number): boolean
		for _, crossingX in crossings do
			if math.abs(x - crossingX) < 7 then
				return true
			end
		end
		return false
	end
	for _, side in { -1, 1 } do
		local x = plazaRadius + 4
		while x < width / 2 - 3 do
			if not nearCrossing(side * x) then
				paint(
					part(
						town,
						"RoadLine",
						Vector3.new(4, 0.05, 0.6),
						ground * CFrame.new(side * x, 0.235, 0),
						COLORS.StreetLine
					)
				)
			end
			x += 8
		end
	end

	-- Plaza: round candy planters with little trees beside the spawn, benches facing it. The planters sit 5 studs
	-- either side of the centre line, so the Nurse Belt (Config.Belt: 11 studs off it, 3.4 each side) runs past them.
	for i, corner in { Vector2.new(1, 1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(-1, -1) } do
		local at = ground * CFrame.new(corner.X * 10.5, 0.4, corner.Y * 5)
		cylinder(town, "Planter", 1.2, 4, at * CFrame.new(0, 0.6, 0), PLANTERS[i])
		soft(cylinder(town, "PlanterGrass", 0.1, 3.4, at * CFrame.new(0, 1.22, 0), COLORS.Lawn))
		Props.tree(town, at * CFrame.new(0, 1.2, 0), 0.55, i % 2 == 0)
	end
	for _, side in { -1, 1 } do
		local at = ground * CFrame.new(side * 15, 0.4, 0)
		Props.bench(town, CFrame.lookAt(at.Position, ground.Position + Vector3.new(0, 0.4, 0))) -- sits facing the spawn
		Props.lamp(town, ground * CFrame.new(side * 15, 0.4, 4.5), 8)
	end

	-- Street lamps between the plots, and trees in the gaps between plots.
	for column = 0, perRow do
		local x = (column - perRow / 2) * (size + PLOT_GAP)
		for _, side in { -1, 1 } do
			if math.abs(x) > 1 then
				Props.lamp(town, ground * CFrame.new(x, 0.4, side * (h - 1.6)), 8)
			end
			Props.tree(town, ground * CFrame.new(x, 0, side * (h + size / 2)), 1.1, column % 2 == 0)
		end
	end

	-- Welcome arches at both ends of the street (the clinic's motto, design §5.1): white posts with candy balls on
	-- top and a glossy pink board.
	for _, side in { -1, 1 } do
		local x = side * (width / 2 - 5)
		for _, zSide in { -1, 1 } do
			part(town, "ArchPost", Vector3.new(1.6, 12, 1.6), ground * CFrame.new(x, 6, zSide * (h - 2)), WHITE)
			soft(ball(town, "ArchCap", 1.8, ground * CFrame.new(x, 14.9, zSide * (h - 2)), CANDY.Yellow))
		end
		local beam = part(
			town,
			"ArchBeam",
			Vector3.new(1.4, 3.4, h * 2 - 2),
			ground * CFrame.new(x, 12.4, 0),
			darken(CANDY.Pink, 0.15)
		)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "WelcomeGui"
		gui.Face = if side < 0 then Enum.NormalId.Right else Enum.NormalId.Left -- faces the town centre
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		candyBoard(gui, CANDY.Pink, 6, 16, 4)
		candyLabel(
			gui,
			"Motto",
			"Everyone welcome. Even the weird ones.",
			UDim2.fromScale(0.94, 0.7),
			UDim2.fromScale(0.03, 0.15),
			4
		)
		gui.Parent = beam
	end

	return town
end

function TownBuilder.spawn(): SpawnLocation
	local existing = Workspace:FindFirstChild("TownSpawn")
	if existing and existing:IsA("SpawnLocation") then
		return existing -- the brother placed one: keep it
	end
	local side = Config.Town.SpawnSize
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "TownSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(side, 1, side)
	-- Facing -z: toward the belt on the road's centre line.
	spawn.CFrame = CFrame.new(Config.Town.Origin + Config.Town.SpawnOffset + Vector3.new(0, BASE_TOP, 0))
	spawn.Color = COLORS.Spawn
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.Duration = 0 -- no force field bubble
	spawn.Parent = Workspace
	return spawn
end

return TownBuilder
