--!nocheck
-- The town world (look build plan §B5 and §D T2; art-direction §2.4, §4.1, §4.4): the REAL PlotBuilder.buildTown
-- (and through it TownBuilder and World/*) and the real BoardBuilder under tests/worldmock, plus the pure blocks of
-- TownBuilder, NurseBelt and BeltView, World/Props' part contract, the kiosk shell, and the UI rules on BeltView.
-- x and z are studs from Config.Town.Origin; row 2's plots are at +z. tests/TownLayout.spec keeps the Config
-- numbers honest; this spec checks the BUILT town against the same rules.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local World = require("./worldmock")
local Config = require("./config")
local Look = require("./look")
local UiRules = require("./uirules")
local BeltLogic = require("../src/shared/Logic/Belt")
local NurseLogic = require("../src/shared/Logic/Nurse")
local TutorialLogic = require("../src/shared/Logic/Tutorial")
local Rarities = require("../src/shared/Data/Rarities")

local Enum = World.roblox.Enum
local Vector3 = World.roblox.Vector3
local CFrame = World.roblox.CFrame

local ORIGIN = Vector3.new(Config.Town.Origin.X, Config.Town.Origin.Y, Config.Town.Origin.Z)
local BASE_TOP = 0.3 -- TownBuilder's lawn top above the origin (TownLayout.spec checks it matches PlotBuilder)
local STREET_TOP = BASE_TOP + 0.2
-- World positions are float32 (Roblox Vector3): compare them to about a thousandth of a stud.
local TOL = 1e-3
-- PlotBuilder's town: 80-stud plots 8 apart (PLOT_GAP), so the columns stand PITCH (88) apart and the street (and the
-- lawn) runs x -STREET_END..STREET_END (152). The belt runs x -135..135 (Config.Belt); its lane reaches its end rollers.
local PITCH = Config.Town.PlotSize + 8
local STREET_END = (math.ceil(Config.Town.Plots / 2) * PITCH + 40) / 2
local LANE = { X0 = -136.5, X1 = 136.5, Z0 = -Config.Town.BeltClear, Z1 = Config.Town.BeltClear }

local function pureBlock(path: string, env: { [string]: any }?): any
	local text = fs.readFile(World.find(path))
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to and to > from, path .. ": no PURE block")
	return luau.load(
		string.sub(text, from, to - 1) .. "\nreturn Pure\n",
		{ debugName = path .. " (pure)", environment = env or {}, injectGlobals = true }
	)()
end

local function words(text: string): number
	local n = 0
	for _ in string.gmatch(text, "%S+") do
		n += 1
	end
	return n
end

-- A part's footprint and height range, studs from the origin.
local function extent(world, part)
	local lo, hi = world.box(part)
	return {
		X0 = lo.X - ORIGIN.X,
		X1 = hi.X - ORIGIN.X,
		Z0 = lo.Z - ORIGIN.Z,
		Z1 = hi.Z - ORIGIN.Z,
		Y0 = lo.Y - ORIGIN.Y,
		Y1 = hi.Y - ORIGIN.Y,
	}
end

local function overlaps(a, b, margin: number?): boolean
	local m = margin or 0
	return a.X0 < b.X1 + m and a.X1 > b.X0 - m and a.Z0 < b.Z1 + m and a.Z1 > b.Z0 - m
end

local function isWhole(n: number): boolean
	return math.abs(n - math.floor(n + 0.5)) < 1e-6
end

-- A night lamp's head is Neon after dark and may be bright by day (World.Lamp); everything else keeps every channel at
-- 245 or under (art-direction §4.1; the Foundation notes: "no channel above 245", Yellow has R = 245). A see-through
-- part (a sign's carrier, a marker) shows no colour.
local function bleached(part): boolean
	if part.Transparency >= 1 or part:GetAttribute("NightKind") == "Lamp" then
		return false
	end
	return Look.maxChannel(part.Color) > 245
end

local function buildTown(variant: boolean?, texture: string?)
	local world = World.new()
	if variant then
		world.setVariant(true)
	end
	if texture then
		world.load("src/shared/Config.luau").Look.CheckerTexture = texture
	end
	local PlotBuilder = world.load("src/server/PlotBuilder.luau")
	local plots = PlotBuilder.buildTown()
	return world, world.Workspace:FindFirstChild("ClinicTown"), world.Workspace:FindFirstChild("TownSpawn"), plots
end

------------------------------------------------------------------------------------------------------------------
-- TownBuilder.Pure: where the lawn shows, and its checker
------------------------------------------------------------------------------------------------------------------

T.describe("TownBuilder.Pure: the lawn's regions and the checker", function()
	local Pure = pureBlock("src/server/TownBuilder.luau")
	local size, half, gap = Config.Town.PlotSize, 18, 8
	local look = Config.Look
	local regions = Pure.lawnRegions(Config.Town.Plots, size, half, gap, 20, look.CheckerStuds, look.CheckerFarStuds)
	local plots = Pure.plotRects(Config.Town.Plots, size, half, gap)
	local tiles = Pure.checker(regions)

	test("the plots are where PlotBuilder puts them: x -88 / 0 / 88, rows at z 18..98 either side", function()
		expect(#plots).toBe(6)
		local xs = {}
		for _, r in plots do
			table.insert(xs, (r.X0 + r.X1) / 2)
			expect(r.X1 - r.X0).toBe(size)
			expect(math.abs((r.Z0 + r.Z1) / 2)).toBe(half + size / 2)
		end
		expect(xs).toEqual({ -88, 0, 88, -88, 0, 88 })
	end)

	test("the regions never reach the street or a plot, and stay on the lawn", function()
		for _, r in regions do
			expect(r.U0 >= half - 1e-6).toBe(true)
			expect(r.U1 <= half + size + 20 + 1e-6).toBe(true)
			expect(r.X0 >= -STREET_END - 1e-6 and r.X1 <= STREET_END + 1e-6).toBe(true)
			local rect = {
				X0 = r.X0,
				X1 = r.X1,
				Z0 = if r.Side > 0 then r.U0 else -r.U1,
				Z1 = if r.Side > 0 then r.U1 else -r.U0,
			}
			for _, p in plots do
				if overlaps(rect, p, -1e-6) then
					error(string.format("a lawn region at x %.1f..%.1f overlaps a plot", r.X0, r.X1))
				end
			end
		end
	end)

	test("4-stud cells within 20 studs of the street and in the plot gaps, 8-stud cells elsewhere", function()
		local sawGap, sawFar = false, false
		for _, r in regions do
			local inner = r.X0 > -STREET_END + 1e-6 and r.X1 < STREET_END - 1e-6
			if r.U1 <= half + 20 + 1e-6 or (inner and r.U1 <= half + size + 1e-6) then
				expect(r.Cell).toBe(look.CheckerStuds)
				sawGap = sawGap or inner
			else
				expect(r.Cell).toBe(look.CheckerFarStuds)
				sawFar = true
			end
		end
		expect(sawGap and sawFar).toBe(true)
	end)

	test(
		"every tile is inside its lawn, on whole studs, even-sized (both stud modes line up), none overlapping",
		function()
			for i, t in tiles do
				for _, n in { t.X0, t.X1, t.Z0, t.Z1 } do
					expect(isWhole(n)).toBe(true)
				end
				expect((t.X1 - t.X0) % 2).toBe(0)
				expect((t.Z1 - t.Z0) % 2).toBe(0)
				expect(math.abs(t.Z0) >= half - 1e-6 and math.abs(t.Z1) >= half - 1e-6).toBe(true)
				for _, p in plots do
					expect(overlaps(t, p, -1e-6)).toBe(false)
				end
				for j = i + 1, #tiles do
					if overlaps(t, tiles[j], -1e-6) then
						error("two checker tiles overlap")
					end
				end
			end
			print(string.format("    [town] %d checker tiles over %d lawn regions", #tiles, #regions))
		end
	)

	test("a checker, not stripes: no two tiles of one cell size share a whole edge side by side", function()
		local edges = {}
		for _, t in tiles do
			local key = string.format("%d|%d|%d", t.X1, t.Z0, t.Z1)
			edges[key] = true
		end
		for _, t in tiles do
			if edges[string.format("%d|%d|%d", t.X0, t.Z0, t.Z1)] then
				error(string.format("tiles meet edge to edge at x %d, z %d..%d", t.X0, t.Z0, t.Z1))
			end
		end
	end)

	test("blossom: every sixth tree, so never more than 1 in 6", function()
		local count = 0
		for n = 1, 120 do
			if Pure.blossom(n, 6) then
				count += 1
			end
			expect(count <= n / 6).toBe(true)
		end
		expect(count).toBe(20)
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- The built town (Surface mode: no CureStuds variant yet)
------------------------------------------------------------------------------------------------------------------

T.describe("The built town (Surface mode)", function()
	local world, town, spawn, plots = buildTown()
	local parts = world.parts(town)

	test("ClinicTown and TownSpawn are built", function()
		expect(town ~= nil).toBe(true)
		expect(spawn ~= nil and spawn.ClassName == "SpawnLocation").toBe(true)
	end)

	test(
		"nothing of the town stands on a plot (its ground, as PlotBuilder built it), only the flat lawn under it",
		function()
			expect(#plots).toBe(Config.Town.Plots)
			local grounds = {}
			for _, plot in plots do
				local box
				for _, p in world.parts(plot:FindFirstChild("Ground")) do
					local e = extent(world, p)
					box = if box
						then {
							X0 = math.min(box.X0, e.X0),
							X1 = math.max(box.X1, e.X1),
							Z0 = math.min(box.Z0, e.Z0),
							Z1 = math.max(box.Z1, e.Z1),
						}
						else e
				end
				expect(math.abs(box.X1 - box.X0 - Config.Town.PlotSize) < TOL).toBe(true)
				table.insert(grounds, box)
			end
			for _, p in parts do
				local e = extent(world, p)
				if e.Y1 > STREET_TOP + 0.3 then
					for index, box in grounds do
						if overlaps(e, box, -TOL) then
							error(string.format("%s stands on Plot_%d at x %.1f, z %.1f", p.Name, index, e.X0, e.Z0))
						end
					end
				end
			end
		end
	)

	test("ClinicTown stays inside Config.Look.TownParts", function()
		print(string.format("    [parts] ClinicTown: %d / %d", #parts, Config.Look.TownParts))
		expect(#parts <= Config.Look.TownParts).toBe(true)
	end)

	test("the Lawn and every LawnTile are studded; the tiles are GrassB on the GrassA lawn", function()
		local lawn = town:FindFirstChild("Lawn")
		expect(lawn ~= nil).toBe(true)
		expect(lawn:GetAttribute("Studded")).toBe(true)
		expect(lawn.Material).toBe(Enum.Material.Plastic)
		expect(lawn.TopSurface).toBe(Enum.SurfaceType.Studs)
		expect(lawn.Color).toEqual(world.load("src/shared/Palette.luau").World.GrassA)
		local tiles = 0
		for _, p in parts do
			if p.Name == "LawnTile" then
				tiles += 1
				expect(p:GetAttribute("Studded")).toBe(true)
				expect(p.TopSurface).toBe(Enum.SurfaceType.Studs)
				expect(p.Color).toEqual(world.load("src/shared/Palette.luau").World.GrassB)
				local e = extent(world, p)
				expect(math.abs(e.Y1 - (BASE_TOP + 0.05)) < 1e-4).toBe(true) -- 0.05 above the lawn
				expect(math.abs(p.Size.Y - 0.2) < 1e-6).toBe(true)
			end
		end
		expect(tiles > 100).toBe(true)
		expect(town:FindFirstChild("TownLawn")).toBeNil() -- renamed with BoardBuilder (the Foundation notes)
	end)

	test("the Street is dark and smooth (V <= 0.35); the curbs are Slate", function()
		local street = town:FindFirstChild("Street")
		expect(street.Material).toBe(Enum.Material.SmoothPlastic)
		expect(street:GetAttribute("Studded")).toBeNil()
		local _, _, v = Look.hsv(street.Color)
		expect(Look.round(v) <= 0.35).toBe(true)
		local curbs = 0
		for _, p in parts do
			if p.Name == "Curb" then
				curbs += 1
				expect(p.Material).toBe(Enum.Material.Slate)
			end
		end
		expect(curbs).toBe(2)
	end)

	test("no Texture or Decal anywhere while CheckerTexture is empty", function()
		expect(Config.Look.CheckerTexture).toBe("")
		for _, d in town:GetDescendants() do
			if d.ClassName == "Texture" or d.ClassName == "Decal" then
				error("a " .. d.ClassName .. " in the town")
			end
		end
	end)

	test("no colour above 245 in any channel (night lamps aside); no pink plaza ring", function()
		for _, p in parts do
			if bleached(p) then
				error(p.Name .. " is bleached")
			end
		end
		expect(bleached(spawn)).toBe(false)
		expect(town:FindFirstChild("PlazaInner")).toBeNil()
	end)

	test("nothing in the belt's lane but flat road paint (under 0.3 above the street)", function()
		for _, p in parts do
			local e = extent(world, p)
			if overlaps(e, LANE) and e.Y1 > STREET_TOP + 0.3 then
				error(string.format("%s stands in the belt's lane at x %.1f, z %.1f", p.Name, e.X0, e.Z0))
			end
		end
	end)

	test("no centre dashes: road lines run along the curbs only; crossings stay out from under the belt", function()
		local lines, crossings = 0, 0
		for _, p in parts do
			if p.Name == "RoadLine" or p.Name == "Crossing" then
				local e = extent(world, p)
				expect(e.Z0 > LANE.Z1 or e.Z1 < LANE.Z0).toBe(true)
				expect(e.Y1 - STREET_TOP < 0.1).toBe(true)
				expect(p.CanCollide).toBe(false)
				if p.Name == "RoadLine" then
					lines += 1
					expect(math.abs((e.Z0 + e.Z1) / 2) > 12).toBe(true)
				else
					crossings += 1
					expect(math.abs(math.abs((e.X0 + e.X1) / 2) - PITCH) < TOL).toBe(true) -- the crossings at x +-88
				end
			end
		end
		expect(lines >= 2).toBe(true)
		expect(crossings > 0).toBe(true)
	end)

	test("TownSpawn: an 8 x 8 studded pad at SpawnOffset, facing -z (the belt), clear of everything", function()
		local at = spawn.CFrame.Position
		expect(at.X - ORIGIN.X).toBe(Config.Town.SpawnOffset.X)
		expect(at.Z - ORIGIN.Z).toBe(Config.Town.SpawnOffset.Z)
		expect(math.abs(at.Y - ORIGIN.Y - BASE_TOP) < 1e-6).toBe(true)
		expect(spawn.Size.X).toBe(Config.Town.SpawnSize)
		expect(spawn.Size.Z).toBe(Config.Town.SpawnSize)
		expect(spawn:GetAttribute("Studded")).toBe(true)
		local look = spawn.CFrame.LookVector
		expect(math.abs(look.Z + 1) < 1e-6).toBe(true)
		local pad = extent(world, spawn)
		for _, p in parts do
			local e = extent(world, p)
			if overlaps(e, pad, 1) and e.Y1 > pad.Y1 then
				error(p.Name .. " stands on or beside the spawn pad")
			end
		end
	end)

	test(
		"the plaza: a plank pad on the row-2 half; everything on it stays inside it and clear of the kiosks, the sign and the middle gate",
		function()
			local plaza = Config.Town.Plaza
			local pad = town:FindFirstChild("Plaza")
			expect(pad.Material).toBe(Enum.Material.WoodPlanks)
			local e = extent(world, pad)
			expect(math.abs(e.X0 - plaza.X0) < TOL and math.abs(e.X1 - plaza.X1) < TOL).toBe(true)
			expect(math.abs(e.Z0 - plaza.Z0) < TOL and math.abs(e.Z1 - plaza.Z1) < TOL).toBe(true)
			-- the kiosks (7 x 4.5 turned to face the spawn) and the odds sign (Pure.SIGN wide, along z)
			local function facing(x, z, width, depth)
				local fx, fz = Config.Town.SpawnOffset.X - x, Config.Town.SpawnOffset.Z - z
				local l = math.sqrt(fx * fx + fz * fz)
				fx, fz = fx / l, fz / l
				local hx = math.abs(fx) * depth / 2 + math.abs(fz) * width / 2
				local hz = math.abs(fz) * depth / 2 + math.abs(fx) * width / 2
				return { X0 = x - hx, X1 = x + hx, Z0 = z - hz, Z1 = z + hz }
			end
			local keep = {
				Agency = facing(Config.Agency.Offset.X, Config.Agency.Offset.Z, 7, 4.5),
				Market = facing(Config.Market.Offset.X, Config.Market.Offset.Z, 7, 4.5),
				Sign = facing(Config.Belt.SignOffset.X, Config.Belt.SignOffset.Z, 9.2, 2),
				Mouth = { X0 = -3, X1 = 3, Z0 = 15, Z1 = 18 },
			}
			for _, p in parts do
				local b = extent(world, p)
				if b.Y1 > STREET_TOP + 0.3 and b.Z1 > 0 and b.Z0 < 18 and math.abs(b.X0 + b.X1) / 2 <= plaza.X1 + 1 then
					local name = p.Name
					if b.X0 < plaza.X0 - TOL or b.X1 > plaza.X1 + TOL or b.Z0 < plaza.Z0 - TOL then
						error(name .. " sticks out of the plaza")
					end
					for what, box in keep do
						if overlaps(b, box, 1) then
							error(name .. " is within a stud of the " .. what)
						end
					end
				end
			end
		end
	)

	test("trees: voxel (a Wood trunk and 5 studded cubes, <= 7 parts), three greens, blossom at most 1 in 6", function()
		local Palette = world.load("src/shared/Palette.luau")
		local greens = { Palette.World.LeavesA, Palette.World.LeavesB, Palette.World.LeavesC }
		local trees, blossoms = 0, 0
		local used = {}
		for _, d in town:GetDescendants() do
			if d.ClassName == "Model" and d.Name == "Tree" then
				trees += 1
				local list = world.parts(d)
				expect(#list <= 7).toBe(true)
				local cubes = 0
				for _, p in list do
					if p.Name == "Trunk" then
						expect(p.Material).toBe(Enum.Material.Wood)
					else
						cubes += 1
						expect(p:GetAttribute("Studded")).toBe(true)
						expect(p.Size.X == p.Size.Y and p.Size.Y == p.Size.Z).toBe(true) -- cubes
						expect(isWhole(p.Size.X)).toBe(true)
						for index, green in greens do
							if p.Color == green then
								used[index] = true
							end
						end
					end
				end
				expect(cubes >= 5).toBe(true)
				if d:GetAttribute("Blossom") then
					blossoms += 1
				end
			end
		end
		print(string.format("    [town] %d trees, %d blossom", trees, blossoms))
		expect(trees >= 12).toBe(true)
		expect(blossoms >= 1 and blossoms * 6 <= trees).toBe(true)
		expect(used[1] and used[2] and used[3]).toBe(true)
	end)

	test("every studded part is whole studs in X and Z (the alignment rule)", function()
		for _, p in parts do
			if p:GetAttribute("Studded") == true then
				if not (isWhole(p.Size.X) and isWhole(p.Size.Z)) then
					error(string.format("%s is %.2f x %.2f", p.Name, p.Size.X, p.Size.Z))
				end
			end
		end
	end)

	test("the street lamps (x +-44, z +-16.4) are dark posts with NightLights heads", function()
		local found = 0
		for _, d in town:GetDescendants() do
			if d.ClassName == "Model" and d.Name == "Lamp" then
				local head = d:FindFirstChild("Glow")
				expect(head ~= nil and head:GetAttribute("NightKind") == "Lamp").toBe(true)
				local e = extent(world, d:FindFirstChild("Post"))
				local x, z = (e.X0 + e.X1) / 2, (e.Z0 + e.Z1) / 2
				if math.abs(math.abs(x) - PITCH / 2) < TOL and math.abs(math.abs(z) - 16.4) < TOL then
					found += 1
				end
			end
		end
		expect(found).toBe(4)
	end)

	test("the welcome arches float the motto on both faces of the beam: outlined text, no board", function()
		local guis = 0
		for _, p in parts do
			if p.Name == "ArchBeam" then
				local e = extent(world, p)
				expect(math.abs(math.abs((e.X0 + e.X1) / 2) - (STREET_END - 5)) < TOL).toBe(true) -- the arches at x +-147
				for _, gui in p:GetChildren() do
					if gui.ClassName == "SurfaceGui" then
						guis += 1
						expect(gui.LightInfluence).toBe(0)
						local texts = 0
						for _, d in gui:GetDescendants() do
							if d.ClassName == "Frame" then
								error("a board (" .. d.Name .. ") behind the motto")
							elseif d.ClassName == "TextLabel" then
								texts += 1
								expect(d.BackgroundTransparency).toBe(1)
							end
						end
						expect(texts >= 1).toBe(true)
					end
				end
			end
		end
		expect(guis).toBe(4)
	end)
end)

T.describe("The built town (Variant mode: CureStuds exists)", function()
	local world, town = buildTown(true)

	test("the lawn, its tiles and the trees wear the variant on every face", function()
		local lawn = town:FindFirstChild("Lawn")
		expect(lawn.MaterialVariant).toBe(Config.Look.StudsVariant)
		expect(lawn.TopSurface).toBe(Enum.SurfaceType.Smooth)
		local studded = 0
		for _, p in world.parts(town) do
			if p:GetAttribute("Studded") == true then
				studded += 1
				expect(p.MaterialVariant).toBe(Config.Look.StudsVariant)
			end
		end
		expect(studded > 100).toBe(true)
	end)
end)

T.describe("The built town with a checker image (Config.Look.CheckerTexture)", function()
	local _, town = buildTown(false, "rbxassetid://1")

	test("one Texture on the lawn's top replaces the tiles", function()
		local lawn = town:FindFirstChild("Lawn")
		local textures = {}
		for _, d in town:GetDescendants() do
			if d.ClassName == "Texture" then
				table.insert(textures, d)
			end
			expect(d.Name ~= "LawnTile").toBe(true)
		end
		expect(#textures).toBe(1)
		expect(textures[1].Parent).toBe(lawn)
		expect(textures[1].Face).toBe(Enum.NormalId.Top)
		expect(textures[1].StudsPerTileU).toBe(2 * Config.Look.CheckerStuds)
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- World/Props: the part contract (look build plan §B4)
------------------------------------------------------------------------------------------------------------------

T.describe("World/Props: the shared scenery pieces", function()
	local world = World.new()
	local Props = world.load("src/server/World/Props.luau")
	local Palette = world.load("src/shared/Palette.luau")
	local function holder()
		local folder = world.new("Folder")
		folder.Parent = world.Workspace
		return folder
	end
	local at = CFrame.new(10, 0, 20)

	test("tree: <= 7 parts at every scale, a blossom has pink leaves", function()
		for _, scale in { 0.55, 1, 1.1, 1.35 } do
			local tree = Props.tree(holder(), at, scale)
			expect(#world.parts(tree) <= 7).toBe(true)
		end
		local blossom = Props.tree(holder(), at, 1, true)
		local pink = false
		for _, p in world.parts(blossom) do
			if p.Name == "Leaves" and p.Color == Palette.Accent.Pink then
				pink = true
			end
		end
		expect(pink).toBe(true)
		expect(blossom:GetAttribute("Blossom")).toBe(true)
	end)

	test("bush: exactly one studded cube, returned", function()
		local folder = holder()
		local bush = Props.bush(folder, at)
		expect(bush:IsA("BasePart")).toBe(true)
		expect(#world.parts(folder)).toBe(1)
		expect(bush:GetAttribute("Studded")).toBe(true)
		expect(bush.Size.X == bush.Size.Y and bush.Size.Y == bush.Size.Z).toBe(true)
	end)

	test("lamp, bench, planter: <= 3, 3, 2 parts; the lamp's head is a NightLights Lamp", function()
		local lamp = Props.lamp(holder(), at, 8)
		expect(#world.parts(lamp) <= 3).toBe(true)
		expect(lamp:FindFirstChild("Glow"):GetAttribute("NightKind")).toBe("Lamp")
		expect(#world.parts(Props.bench(holder(), at)) <= 3).toBe(true)
		expect(#world.parts(Props.planter(holder(), at, Vector3.new(4, 1, 2))) <= 2).toBe(true)
	end)

	test("fence: posts at least 14 studs apart and 2 rails, <= 2 + floor(length / 14) + 1 parts", function()
		for _, length in { 10, 14, 28.4, 34.6, 69.2, 100 } do
			local fence = Props.fence(holder(), CFrame.new(0, 0, 0), CFrame.new(length, 0, 0))
			local n = #world.parts(fence)
			if n > 2 + math.floor(length / 14) + 1 then
				error(string.format("a %.1f-stud fence has %d parts", length, n))
			end
			local rails = 0
			for _, p in world.parts(fence) do
				if p.Name == "FenceRail" then
					rails += 1
				end
			end
			expect(rails).toBe(2)
		end
	end)

	test("kiosk: <= 24 parts (the caller adds its prompt), studded accent walls, a dark roof, floating name", function()
		local kiosk = Props.kiosk(holder(), at, {
			Name = "TestKiosk",
			Title = "🏢 AGENCY",
			Lines = { "🔄 New nurses every 5 min" },
			Accent = Palette.Accent.Cyan,
		})
		local list = world.parts(kiosk.Model)
		expect(#list <= 24).toBe(true)
		local walls, roof = 0, false
		for _, p in list do
			if string.sub(p.Name, 1, 4) == "Wall" then
				walls += 1
				expect(p:GetAttribute("Studded")).toBe(true)
				expect(p.Color).toEqual(Palette.Accent.Cyan)
				expect(isWhole(p.Size.X) and isWhole(p.Size.Z)).toBe(true)
			elseif p.Name == "Roof" then
				roof = p.Color == Palette.World.Roof
			end
			expect(bleached(p)).toBe(false)
		end
		expect(walls).toBe(3)
		expect(roof).toBe(true)
		expect(kiosk.Counter.Parent).toBe(kiosk.Model)
		local gui = kiosk.Front:FindFirstChild("KioskGui")
		local texts = {}
		for _, d in gui:GetDescendants() do
			expect(d.ClassName ~= "Frame").toBe(true) -- no board
			if d.ClassName == "TextLabel" and d.Name == "Text" then
				table.insert(texts, d.Text)
				expect(d.BackgroundTransparency).toBe(1)
			end
		end
		expect(table.find(texts, "🏢 AGENCY") ~= nil).toBe(true)
		expect(table.find(texts, "🔄 New nurses every 5 min") ~= nil).toBe(true)
		-- 7 x 4.5 footprint (tests/TownLayout.spec's KIOSK_WIDTH / KIOSK_DEPTH)
		local base = kiosk.Model:FindFirstChild("Base")
		expect({ base.Size.X, base.Size.Z }).toEqual({ 7, 4.5 })
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- The Hall of Fame garden (Server/BoardBuilder), on the built town
------------------------------------------------------------------------------------------------------------------

T.describe("The Hall of Fame garden (BoardBuilder)", function()
	local world = buildTown()
	local BoardBuilder = world.load("src/server/BoardBuilder.luau")
	local Palette = world.load("src/shared/Palette.luau")
	local ids = Config.Leaderboards.WorldBoards
	local gantry = BoardBuilder.build(ids)
	local model = gantry.Model

	test("it stays past the street's west end (x < -152), off the street", function()
		for _, p in world.parts(model) do
			local e = extent(world, p)
			if e.X1 > -STREET_END + TOL then
				error(p.Name .. " reaches the street")
			end
		end
	end)

	test("its lawn is studded, with a GrassB checker; no colour above 245 (lamps aside); no Texture", function()
		local garden = model:FindFirstChild("Garden")
		local lawn = garden:FindFirstChild("Lawn")
		expect(lawn:GetAttribute("Studded")).toBe(true)
		local tiles = 0
		for _, p in world.parts(model) do
			if p.Name == "LawnTile" then
				tiles += 1
				expect(p:GetAttribute("Studded")).toBe(true)
			end
			if bleached(p) then
				error(p.Name .. " is bleached")
			end
		end
		expect(tiles > 0).toBe(true)
		for _, d in model:GetDescendants() do
			expect(d.ClassName ~= "Texture" and d.ClassName ~= "Decal").toBe(true)
		end
	end)

	test("each board: a navy plate under a floating title, on both faces; the rows render", function()
		for _, id in ids do
			local board = model:FindFirstChild("Board_" .. id)
			expect(board ~= nil).toBe(true)
			expect(board:GetAttribute("BoardId")).toBe(id)
			for _, guiName in { "BoardGui", "BoardGuiBack" } do
				local gui = board:FindFirstChild(guiName)
				expect(gui.LightInfluence).toBe(0)
				local plate = gui:FindFirstChild("Plate")
				expect(plate.BackgroundColor3).toEqual(Palette.Navy)
				local title = gui:FindFirstChild("Text")
				expect(title.BackgroundTransparency).toBe(1)
				expect(
					string.find(title.Text, "Most", 1, true) ~= nil or string.find(title.Text, "Week", 1, true) ~= nil
				).toBe(true)
			end
		end
		gantry.render(ids[1], { Status = "Live", Rows = { { Name = "Pip", User = "pip", Value = 42 } } })
		local rows = model:FindFirstChild("Board_" .. ids[1]).BoardGui.Plate.Rows
		expect(rows.Row1.Visible).toBe(true)
		expect(rows.Row1:FindFirstChild("Name").Text).toBe("Pip")
		expect(rows.Row1:FindFirstChild("Value").TextColor3).toEqual(Palette.Gold)
		expect(rows.Row2.Visible).toBe(false)
		gantry.render(ids[1], { Status = "Offline", Rows = {} })
		expect(rows.Row1.Visible).toBe(false)
	end)

	test("the lamps and the title's lights are World/NightLights lamps (the tag from World/NightLights)", function()
		local NightLights = world.load("src/server/World/NightLights.luau")
		local lit = 0
		for _, tagged in world.tagged(NightLights.TAG) do
			if tagged:IsDescendantOf(model) then
				lit += 1
			end
		end
		expect(lit >= 4).toBe(true)
		local text = fs.readFile(World.find("src/server/BoardBuilder.luau"))
		expect(string.find(text, "require(script.Parent.PlotBuilder", 1, true)).toBeNil()
	end)

	test("the '🏆 Hall of Fame' title floats in gold, no board", function()
		local sign = model:FindFirstChild("TitleSign")
		expect(sign.Transparency).toBe(1)
		local label = sign.TitleGui:FindFirstChild("Text")
		expect(label.Text).toBe("🏆 Hall of Fame")
		expect(label.TextColor3).toEqual(Palette.Gold)
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- The Nurse Belt (Server/NurseBelt's pure block) and BeltView
------------------------------------------------------------------------------------------------------------------

T.describe("NurseBelt.Pure: the sign and the riders on a centre-line belt", function()
	local BP = pureBlock("src/server/NurseBelt.luau", { BeltLogic = BeltLogic })

	test("riders on the centre line face the plaza (+z, TownSpawn's side)", function()
		local sx, sz = 120, 0
		local x, z = BP.riderFacing(-1, 0, sx, sz, Config.Town.SpawnOffset.X, Config.Town.SpawnOffset.Z)
		expect(math.abs(x) < 1e-9 and math.abs(z - 1) < 1e-9).toBe(true)
		-- a spawn on the belt's own line leaves them facing back up the belt
		local bx, bz = BP.riderFacing(-1, 0, sx, sz, 0, 0.5)
		expect({ bx, bz }).toEqual({ 1, -0 })
	end)

	test("the odds sign faces TownSpawn from SignOffset (+x) and fits the plaza (<= 9.2 wide)", function()
		local fx, fz = BP.toward(
			Config.Belt.SignOffset.X,
			Config.Belt.SignOffset.Z,
			Config.Town.SpawnOffset.X,
			Config.Town.SpawnOffset.Z,
			1,
			0
		)
		expect(math.abs(fx - 1) < 1e-9 and math.abs(fz) < 1e-9).toBe(true)
		local plaza = Config.Town.Plaza
		local signZ = Config.Belt.SignOffset.Z
		local widest = 2 * math.min(signZ - (plaza.Z0 + 1), (plaza.Z1 - 1) - signZ)
		expect(BP.SIGN.Width <= widest).toBe(true)
		expect(BP.SIGN.Bottom + BP.SIGN.Height + BP.SIGN.Title < 14).toBe(true) -- a short plate kids can read
	end)

	test("the sign's source: a navy plate, the floating title, the odds prompt; no candy board", function()
		local text = fs.readFile(World.find("src/server/NurseBelt.luau"))
		expect(string.find(text, "Parts.navyPlate(", 1, true) ~= nil).toBe(true)
		expect(string.find(text, '"🎲 NURSE ODDS"', 1, true) ~= nil).toBe(true)
		expect(string.find(text, '"🎲 See odds"', 1, true) ~= nil).toBe(true)
		expect(string.find(text, "CANDY", 1, true)).toBeNil()
		expect(string.find(text, "Pure.gateLines(Config)", 1, true) ~= nil).toBe(true)
	end)
end)

T.describe("BeltView: the odds popup and the UI rules", function()
	local VP = pureBlock("src/client/UI/BeltView.luau", {
		BeltLogic = BeltLogic,
		NurseLogic = NurseLogic,
		TutorialLogic = TutorialLogic,
	})
	local order = Rarities.Order
	local infos = {}
	for _, rarity in order do
		infos[rarity] = Rarities[rarity]
	end

	test("the popup's rows: every odd the belt rolls, day and Night Rush, the word and the number", function()
		for _, night in { false, true } do
			for _, golden in { false, true } do
				local rows = VP.popupRows(Config, order, infos, night, golden)
				local first = string.sub(rows[1].Name, -#(if night then "🌙" else "☀️"))
				expect(first).toBe(if night then "🌙" else "☀️") -- now's block first
				for _, block in { { "☀️", false }, { "🌙", true } } do
					local odds = BeltLogic.odds(Config, block[2], golden)
					local total, seen = 0, 0
					for _, row in rows do
						if string.sub(row.Name, -#block[1]) == block[1] then
							seen += 1
							total += row.Percent
							local rarity = string.match(row.Name, "^(%S+)")
							expect(odds[rarity]).toBe(row.Percent)
							expect(row.Percent > 0).toBe(true)
						end
					end
					expect(math.abs(total - 100) < 1e-6).toBe(true)
					local can = 0
					for _, rarity in order do
						if (odds[rarity] or 0) > 0 then
							can += 1
						end
					end
					expect(seen).toBe(can)
				end
			end
		end
	end)

	test("the popup's notes: 6 words or fewer; the Golden Hour odd, the gates and the pity", function()
		local notes = VP.popupNotes(Config, order, false, false, 7)
		for _, note in notes do
			expect(words(note) <= 6).toBe(true)
		end
		expect(table.find(notes, "👑 Golden Hour: Secret 1%") ~= nil).toBe(true)
		expect(table.find(notes, "🏥 Epic+ from Lv 3") ~= nil).toBe(true)
		expect(table.find(notes, "🏢 Mythic/Secret from R1") ~= nil).toBe(true)
		expect(table.find(notes, "🎁 Rare+ in 7") ~= nil).toBe(true)
		local golden = VP.popupNotes(Config, order, true, true, 0)
		expect(golden[1]).toBe("👑 Golden Hour now!")
		expect(table.find(golden, "🎁 Rare+ next!") ~= nil).toBe(true)
	end)

	test("BeltView follows the UI rules (no text under 18, Kit.textLimit, token corners, no header colour)", function()
		local violations = UiRules.check({ "src/client/UI/BeltView.luau" })
		if #violations > 0 then
			error("\n" .. UiRules.format(violations))
		end
	end)

	test(
		"the floating 🎲 chip is gone; the card's Quiet '🎲 Odds' and the sign's prompt open Hud.oddsPopup",
		function()
			local text = fs.readFile(World.find("src/client/UI/BeltView.luau"))
			expect(string.find(text, 'Name = "BeltOddsChip"', 1, true)).toBeNil()
			expect(string.find(text, "Hud.oddsPopup(", 1, true) ~= nil).toBe(true)
			expect(string.find(text, 'Kind = "Quiet"', 1, true) ~= nil).toBe(true)
			expect(string.find(text, '"🎲 Odds"', 1, true) ~= nil).toBe(true)
			expect(string.find(text, "PromptTriggered", 1, true) ~= nil).toBe(true)
			expect(string.find(text, "Hud.modal(", 1, true)).toBeNil() -- no odds popup of its own
		end
	)
end)

------------------------------------------------------------------------------------------------------------------
-- The kiosks (Server/Agency, Server/Market): their builders only
------------------------------------------------------------------------------------------------------------------

T.describe("The Agency and Market kiosks", function()
	for _, case in
		{
			{ Path = "src/server/Agency.luau", Title = '"🏢 AGENCY"', Prompt = 'prompt.ActionText = "Agency"' },
			{ Path = "src/server/Market.luau", Title = '"🏷️ MARKET"', Prompt = 'prompt.ActionText = "Market"' },
		}
	do
		test(
			case.Path .. ": the shared kiosk shell, its floating name, the prompt unchanged, facing TownSpawn",
			function()
				local text = fs.readFile(World.find(case.Path))
				expect(string.find(text, "Props.kiosk(", 1, true) ~= nil).toBe(true)
				expect(string.find(text, case.Title, 1, true) ~= nil).toBe(true)
				expect(string.find(text, case.Prompt, 1, true) ~= nil).toBe(true)
				expect(string.find(text, 'Workspace:FindFirstChild("TownSpawn")', 1, true) ~= nil).toBe(true)
				expect(string.find(text, "local width, depth = 7, 4.5", 1, true) ~= nil).toBe(true)
				expect(string.find(text, "Awning", 1, true)).toBeNil()
				expect(string.find(text, "Palette.Candy", 1, true)).toBeNil()
			end
		)
	end
end)
