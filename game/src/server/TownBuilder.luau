--!strict
-- The town round the plots (look build plan §B4/§B5; art-direction §2, §4.1, §4.4). Server only. OWNER: T2. Moved
-- from PlotBuilder by the look overhaul's Foundation and rebuilt to the studs look:
--   · the Lawn: one studded GrassA slab with GrassB checker tiles (LawnTile: thin studded parts, 0.2 tall, their tops
--     0.05 above the lawn, on whole studs) wherever the lawn shows: Config.Look.CheckerStuds (4) cells within 20 studs
--     of the street, CheckerFarStuds (10) elsewhere, the plot gaps' far parts too (the 140-stud plots make those gaps
--     120 studs deep: 4-stud cells there would cost hundreds more parts; with 8-stud ones the town built 626 parts,
--     with 10-stud ones 510). When Config.Look.CheckerTexture is set, ONE checker Texture on the lawn's top replaces
--     the tiles (§B2);
--   · the Street: dark (World.Road) and smooth, with warm RoadLine edge lines and zebra crossings at the outer gate
--     pairs; NO centre dashes (the road's centre line belongs to the Nurse Belt, memory-20261117-001 #3); Slate curbs;
--   · the plaza on the street's row-2 half (Config.Town.Plaza): a plank pad with benches, planters and lamps inside
--     its rectangle, clear of the spawn, the kiosks, the odds sign and the row-2 middle gate's mouth (no pink ring);
--   · voxel trees (World/Props.tree) in the plot gaps, the ends and behind the plots, in three greens, at most one
--     blossom tree in six; dark street lamps between the plots (x +-74, +-222; z +-16.4);
--   · the welcome arches at both ends (x +-237): wooden posts, a dark beam, the motto in floating outlined letters.
-- With 140-stud plots (Config.Town.PlotSize; the bigger, open clinic, simple-start design §4) 8 apart, the plot
-- columns stand at x -148 / 0 / 148, the rows at |z| 18..158 and the street runs x -242..242. Everything here is laid
-- out from Config.Town.PlotSize, so those numbers follow it.
-- Nothing solid stands in the belt's lane (|z| <= Config.Town.BeltClear, x -221.5..221.5): only flat road paint
-- (tests/TownWorld.spec builds the real town and checks it, with the parts budget Config.Look.TownParts).
--   TownBuilder.build(count): Model        Workspace.ClinicTown for `count` plots (NOT parented: PlotBuilder does)
--   TownBuilder.spawn(): SpawnLocation     TownSpawn at Config.Town.Origin + Config.Town.SpawnOffset, studded, facing -z
--                                          (toward the belt); a kit one, already in Workspace, is kept
--   TownBuilder.Pure                       plotRects, lawnRegions, checker: where the lawn shows and its tiles
-- It never requires PlotBuilder (PlotBuilder requires this). The street's half width, the plot gap and the lawn's
-- height are repeated from PlotBuilder: tests/TownLayout.spec checks the two files agree. The part names Lawn and
-- Street are read by Server/BoardBuilder (the Hall of Fame garden's frame) and Server/NurseBelt (the street's top).

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local Parts = require(script.Parent.World.Parts)
local Props = require(script.Parent.World.Props)
local Studs = require(script.Parent.World.Studs)

local part, paint = Parts.part, Parts.paint

local TownBuilder = {}

local STREET_HALF_WIDTH = 18
local PLOT_GAP = 8
local BASE_TOP = 0.3 -- the town lawn's top, just above a default baseplate at y = 0

local NEAR_STUDS = 20 -- the lawn this close to the street gets the small checker cells
local WORLD = Palette.World
local ACCENT = Palette.Accent

-- PURE-BEGIN
-- Numbers only (no Roblox types): tests/TownWorld.spec loads this block on its own.
local Pure = {}

type Rect = { X0: number, X1: number, Z0: number, Z1: number }
-- A lawn region in (x, u) space, u = |z| (studs out from the street's centre line) on one side (Side = -1 for row 1,
-- +1 for row 2). Its checker counts cells from (AX, AU), so the bands of one gap line up.
type Region = {
	X0: number,
	X1: number,
	U0: number,
	U1: number,
	Side: number,
	Cell: number,
	AX: number,
	AU: number,
}

-- The plots' footprints (studs from Origin): row 1 (plots 1..ceil(count / 2)) at -z, row 2 at +z, as PlotBuilder lays
-- them out.
function Pure.plotRects(count: number, size: number, half: number, gap: number): { Rect }
	local perRow = math.ceil(count / 2)
	local out: { Rect } = {}
	for index = 1, count do
		local row = if index <= perRow then 1 else 2
		local column = if row == 1 then index else index - perRow
		local x = (column - (perRow + 1) / 2) * (size + gap)
		local near, far = half, half + size
		table.insert(out, {
			X0 = x - size / 2,
			X1 = x + size / 2,
			Z0 = if row == 1 then -far else near,
			Z1 = if row == 1 then -near else far,
		})
	end
	return out
end

-- Where the town lawn shows (not under the street or a plot), each region with its checker cell: `nearCell` within
-- `near` studs of the street, `farCell` elsewhere (the gaps between plots past that, the town's ends past the plots,
-- and the strip behind them).
function Pure.lawnRegions(
	count: number,
	size: number,
	half: number,
	gap: number,
	near: number,
	nearCell: number,
	farCell: number
): { Region }
	local perRow = math.ceil(count / 2)
	local xEdge = (perRow * (size + gap) + 40) / 2
	local uEdge = half + size + 20
	local plotFar = half + size
	local nearEdge = math.min(half + near, plotFar)
	local plots = Pure.plotRects(count, size, half, gap)
	local regions: { Region } = {}
	for _, side in { -1, 1 } do
		local spans: { { number } } = {}
		for _, r in plots do
			if (r.Z0 + r.Z1) * side > 0 then
				table.insert(spans, { r.X0, r.X1 })
			end
		end
		table.sort(spans, function(a, b)
			return a[1] < b[1]
		end)
		local free: { { number } } = {}
		local cursor = -xEdge
		for _, span in spans do
			if span[1] > cursor then
				table.insert(free, { cursor, span[1] })
			end
			cursor = math.max(cursor, span[2])
		end
		if cursor < xEdge then
			table.insert(free, { cursor, xEdge })
		end
		local function add(x0: number, x1: number, u0: number, u1: number, cell: number, ax: number, au: number)
			if x1 - x0 > 1e-6 and u1 - u0 > 1e-6 then
				table.insert(
					regions,
					{ X0 = x0, X1 = x1, U0 = u0, U1 = u1, Side = side, Cell = cell, AX = ax, AU = au }
				)
			end
		end
		for _, span in free do
			add(span[1], span[2], half, nearEdge, nearCell, span[1], half)
			add(span[1], span[2], nearEdge, plotFar, farCell, span[1], half)
		end
		add(-xEdge, xEdge, plotFar, uEdge, farCell, -xEdge, plotFar)
	end
	return regions
end

-- The GrassB tiles: a checker over each region (a cell is a tile when (i + j) is odd, counted from the region's
-- anchor), each tile clipped to its region and dropped when thinner than a stud. Rects in (x, z), studs from Origin.
function Pure.checker(regions: { Region }): { Rect }
	local tiles: { Rect } = {}
	for _, r in regions do
		local cell = r.Cell
		local i0 = math.floor((r.X0 - r.AX) / cell + 1e-6)
		local i1 = math.ceil((r.X1 - r.AX) / cell - 1e-6) - 1
		local j0 = math.floor((r.U0 - r.AU) / cell + 1e-6)
		local j1 = math.ceil((r.U1 - r.AU) / cell - 1e-6) - 1
		for i = i0, i1 do
			for j = j0, j1 do
				if (i + j) % 2 == 1 then
					local x0 = math.max(r.X0, r.AX + i * cell)
					local x1 = math.min(r.X1, r.AX + (i + 1) * cell)
					local u0 = math.max(r.U0, r.AU + j * cell)
					local u1 = math.min(r.U1, r.AU + (j + 1) * cell)
					if x1 - x0 >= 1 and u1 - u0 >= 1 then
						table.insert(tiles, {
							X0 = x0,
							X1 = x1,
							Z0 = if r.Side > 0 then u0 else -u1,
							Z1 = if r.Side > 0 then u1 else -u0,
						})
					end
				end
			end
		end
	end
	return tiles
end

-- Every n-th tree is a blossom tree (art-direction §4.2: at most 1 in 6).
function Pure.blossom(index: number, every: number): boolean
	return every > 0 and index % every == 0
end
-- PURE-END

TownBuilder.Pure = Pure

local BLOSSOM_EVERY = 6

-- The checker: GrassB tiles over the shown lawn, or one Texture when Config.Look.CheckerTexture is set.
local function buildChecker(town: Model, lawn: BasePart, ground: CFrame, count: number)
	local look = Config.Look
	local texture = if type(look.CheckerTexture) == "string" then look.CheckerTexture else ""
	if texture ~= "" then
		local checker = Instance.new("Texture")
		checker.Name = "Checker"
		checker.Texture = texture
		checker.Face = Enum.NormalId.Top
		checker.StudsPerTileU = 2 * look.CheckerStuds
		checker.StudsPerTileV = 2 * look.CheckerStuds
		checker.Transparency = 0.85
		checker.Parent = lawn
		return
	end
	local regions = Pure.lawnRegions(
		count,
		Config.Town.PlotSize,
		STREET_HALF_WIDTH,
		PLOT_GAP,
		NEAR_STUDS,
		look.CheckerStuds,
		look.CheckerFarStuds
	)
	for _, tile in Pure.checker(regions) do
		local width, length = tile.X1 - tile.X0, tile.Z1 - tile.Z0
		local at = ground * CFrame.new((tile.X0 + tile.X1) / 2, -0.05, (tile.Z0 + tile.Z1) / 2)
		local p = part(town, "LawnTile", Vector3.new(width, 0.2, length), at, WORLD.GrassB)
		p.CanCollide = false -- the lawn under it is the floor; a tile never trips anyone
		p.CanQuery = false
		p.CanTouch = false
		Studs.apply(p)
	end
end

-- Road paint: flat, walk-through, shadowless, just above the street's top.
local PAINT_Y = 0.235
local function roadPaint(town: Model, name: string, x0: number, x1: number, z: number, depth: number, ground: CFrame)
	paint(
		part(
			town,
			name,
			Vector3.new(x1 - x0, 0.05, depth),
			ground * CFrame.new((x0 + x1) / 2, PAINT_Y, z),
			WORLD.RoadLine
		)
	)
end

-- The welcome arches at both ends of the street (the clinic's motto, design §5.1): two wooden posts with studded
-- yellow caps, a dark beam, and the motto floating on both of its faces (art-direction §4.4: no board).
local MOTTO = "Everyone welcome. Even the weird ones."
local function buildArch(town: Model, ground: CFrame, x: number, h: number, side: number)
	for _, zSide in { -1, 1 } do
		part(
			town,
			"ArchPost",
			Vector3.new(2, 14, 2),
			ground * CFrame.new(x, 7, zSide * (h - 2)),
			WORLD.Beam,
			Enum.Material.Wood
		)
		local cap =
			part(town, "ArchCap", Vector3.new(2, 2, 2), ground * CFrame.new(x, 15, zSide * (h - 2)), ACCENT.Yellow)
		Studs.apply(cap)
	end
	local beam = part(town, "ArchBeam", Vector3.new(1.4, 3.4, h * 2 - 2), ground * CFrame.new(x, 12.4, 0), WORLD.Roof)
	-- Both faces: the inner one (toward the town's centre) and the outer one (toward the Hall of Fame or the fields).
	local inner = if side < 0 then Enum.NormalId.Right else Enum.NormalId.Left
	local outer = if side < 0 then Enum.NormalId.Left else Enum.NormalId.Right
	for _, face in { inner, outer } do
		local gui = Parts.surface(beam, if face == inner then "WelcomeGui" else "WelcomeGuiBack", face, 30, 320, 0)
		Parts.floatText(gui, MOTTO, {
			Shadow = true,
			Size = UDim2.fromScale(0.94, 0.78),
			Position = UDim2.fromScale(0.03, 0.11),
		})
	end
end

-- The plaza: a plank pad on the street's row-2 half, with benches facing the belt, planters and lamps, all inside its
-- rectangle and clear of the spawn, the kiosks (Config.Agency/Market.Offset), the odds sign (Config.Belt.SignOffset)
-- and the row-2 middle gate's mouth (|x| <= 3, z 15..18).
local function buildPlaza(town: Model, ground: CFrame, streetTop: number)
	local plaza = Config.Town.Plaza
	local pad = part(
		town,
		"Plaza",
		Vector3.new(plaza.X1 - plaza.X0, 0.15, plaza.Z1 - plaza.Z0),
		ground * CFrame.new((plaza.X0 + plaza.X1) / 2, streetTop + 0.075, (plaza.Z0 + plaza.Z1) / 2),
		WORLD.Plank,
		Enum.Material.WoodPlanks
	)
	pad.CastShadow = false
	local top = streetTop + 0.15
	local function at(x: number, z: number): CFrame
		return ground * CFrame.new(x, top, z)
	end
	-- A bench's LookVector is -z as built: its sitters watch the belt go by. Nothing stands between the odds sign and
	-- the spawn (the sign faces it across the Market's front).
	for _, x in { 19.5, 25.5 } do
		Props.bench(town, at(x, 15))
	end
	Props.planter(town, at(23, 7.5), Vector3.new(6, 1, 2))
	Props.planter(town, at(-28, 11), Vector3.new(2, 1, 6))
	for _, x in { -28.5, 29 } do
		for _, z in { 6.5, 16 } do
			Props.lamp(town, at(x, z), 7)
		end
	end
end

function TownBuilder.build(count: number): Model
	local origin = Config.Town.Origin
	local size = Config.Town.PlotSize
	local perRow = math.ceil(count / 2)
	local width = perRow * (size + PLOT_GAP) + 40
	local depth = 2 * (STREET_HALF_WIDTH + size) + 40
	local h = STREET_HALF_WIDTH
	local ground = CFrame.new(origin + Vector3.new(0, BASE_TOP, 0))
	local streetTop = 0.2 -- above the lawn's top

	local town = Instance.new("Model")
	town.Name = "ClinicTown"

	-- The lawn: studded GrassA, the checker on top.
	local lawn = part(town, "Lawn", Vector3.new(width, 2, depth), ground * CFrame.new(0, -1, 0), WORLD.GrassA)
	Studs.apply(lawn)
	buildChecker(town, lawn, ground, count)

	-- The street: dark and smooth, between two Slate curbs.
	local street =
		part(town, "Street", Vector3.new(width, streetTop, h * 2), ground * CFrame.new(0, streetTop / 2, 0), WORLD.Road)
	Studs.smooth(street)
	for _, side in { -1, 1 } do
		part(
			town,
			"Curb",
			Vector3.new(width, 0.4, 0.8),
			ground * CFrame.new(0, 0.2, side * (h - 0.4)),
			WORLD.Curb,
			Enum.Material.Slate
		)
	end

	-- Zebra crossings in front of each outer pair of facing gates (the middle row-2 gate opens onto the plaza). No
	-- stripe under the belt's bed (|z| <= BeltClear): the conveyor covers it.
	local plaza = Config.Town.Plaza
	local crossings: { number } = {}
	for column = 1, perRow do
		local x = (column - (perRow + 1) / 2) * (size + PLOT_GAP)
		if math.abs(x) > plaza.X1 + 4 then
			table.insert(crossings, x)
			for z = -(h - 4), h - 4, 4 do
				if math.abs(z) - 1 > Config.Town.BeltClear then
					roadPaint(town, "Crossing", x - 4, x + 4, z, 2, ground)
				end
			end
		end
	end

	-- The edge lines: one warm line along each side, broken at the crossings, the plaza and the arches. The centre is
	-- the belt's: no dashes there.
	local lineEnd = width / 2 - 7 -- clear of the welcome arches' posts
	local lineU = h - 2.8
	for _, side in { -1, 1 } do
		local cuts: { { number } } = {}
		for _, x in crossings do
			table.insert(cuts, { x - 4.5, x + 4.5 })
		end
		if side > 0 then
			table.insert(cuts, { plaza.X0 - 1, plaza.X1 + 1 })
		end
		table.sort(cuts, function(a, b)
			return a[1] < b[1]
		end)
		local cursor = -lineEnd
		for _, cut in cuts do
			if cut[1] > cursor + 1 then
				roadPaint(town, "RoadLine", cursor, cut[1], side * lineU, 0.6, ground)
			end
			cursor = math.max(cursor, cut[2])
		end
		if lineEnd > cursor + 1 then
			roadPaint(town, "RoadLine", cursor, lineEnd, side * lineU, 0.6, ground)
		end
	end

	buildPlaza(town, ground, streetTop)

	-- Street lamps between the plots (x +-74 and +-222 with 6 plots of 140), on the road by each curb.
	for column = 0, perRow do
		local x = (column - perRow / 2) * (size + PLOT_GAP)
		if math.abs(x) > 1 then
			for _, side in { -1, 1 } do
				Props.lamp(town, ground * CFrame.new(x, streetTop, side * (h - 1.6)), 8)
			end
		end
	end

	-- Voxel trees: in the gaps between plots and at the ends (beside the street lamps), at the far ends, and along
	-- the strip behind the plots. Every sixth one is a blossom tree.
	local trees = 0
	local function plant(x: number, z: number, scale: number)
		trees += 1
		Props.tree(town, ground * CFrame.new(x, 0, z), scale, Pure.blossom(trees, BLOSSOM_EVERY))
	end
	local back = h + size + 10
	local endX = width / 2 - 12
	for _, side in { -1, 1 } do
		for column = 0, perRow do
			local x = (column - perRow / 2) * (size + PLOT_GAP)
			if math.abs(x) > 1 then
				plant(x, side * (h + size / 2), 1.1)
			end
		end
		for _, xSide in { -1, 1 } do
			plant(xSide * endX, side * (h + size - 8), 1.2)
		end
		local step = (width - 34) / 6
		for k = 0, 6 do
			plant(-width / 2 + 17 + k * step, side * back, if k % 2 == 0 then 1.2 else 1)
		end
	end

	-- The welcome arches at both ends of the street.
	for _, side in { -1, 1 } do
		buildArch(town, ground, side * (width / 2 - 5), h, side)
	end

	return town
end

function TownBuilder.spawn(): SpawnLocation
	local existing = Workspace:FindFirstChild("TownSpawn")
	if existing and existing:IsA("SpawnLocation") then
		-- The brother placed one: keep it, unless it stands on the belt's lane (the old spot was the road's centre
		-- line, where the conveyor runs now). Then it moves to the plaza, keeping its height and its turn.
		local lane = Config.Town.BeltClear + existing.Size.Z / 2
		if math.abs(existing.Position.Z - Config.Town.Origin.Z) <= lane then
			local to = Config.Town.Origin + Config.Town.SpawnOffset
			warn("[TownBuilder] TownSpawn stood on the belt's lane: moved to the plaza. Save it there in the place.")
			existing.CFrame = existing.CFrame.Rotation + Vector3.new(to.X, existing.Position.Y, to.Z)
		end
		return existing
	end
	local side = Config.Town.SpawnSize
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "TownSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(side, 1, side)
	-- Facing -z: toward the belt on the road's centre line.
	spawn.CFrame = CFrame.new(Config.Town.Origin + Config.Town.SpawnOffset + Vector3.new(0, BASE_TOP, 0))
	spawn.Color = ACCENT.Yellow
	Studs.apply(spawn)
	spawn.Neutral = true
	spawn.Duration = 0 -- no force field bubble
	spawn.Parent = Workspace
	return spawn
end

return TownBuilder
