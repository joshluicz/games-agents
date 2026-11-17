--!nocheck
-- The town's layout numbers (look build plan §B2/§B5), checked on the shipped Config: the belt alone on the road's
-- centre line, the spawn plaza on the street's row-2 half, the kiosks and the odds sign beside it. T2's
-- TownWorld.spec checks the BUILT town against the same rules; this spec keeps the numbers themselves honest.
-- x and z are studs from Config.Town.Origin; row 2's plots are at +z.

local fs = require("@lune/fs")

local T = require("./expect")
local expect, test = T.expect, T.test

local Config = require("./config")
local Belt = require("../src/shared/Logic/Belt")

local function source(path: string): string
	for _, prefix in { "", "game/", "../" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("can't find " .. path)
end

local function numberIn(text: string, name: string): number
	local value = tonumber(string.match(text, "local " .. name .. " = ([%d%.]+)"))
	assert(value, "no " .. name)
	return value :: number
end

local PLOT_BUILDER = source("src/server/PlotBuilder.luau")
local TOWN_BUILDER = source("src/server/TownBuilder.luau")

local Town = Config.Town
local HALF = numberIn(PLOT_BUILDER, "STREET_HALF_WIDTH") -- 18
local GAP = numberIn(PLOT_BUILDER, "PLOT_GAP") -- 8
local PER_ROW = math.ceil(Town.Plots / 2)
local STREET_END = (PER_ROW * (Town.PlotSize + GAP) + 40) / 2 -- 242 (140-stud plots, 8 apart: the bigger building)
local CURB_INNER = HALF - 0.8 -- the curbs are z 17.2..18
local KIOSK_WIDTH, KIOSK_DEPTH = 7, 4.5 -- Server/Agency and Server/Market: `local width, depth = 7, 4.5`

type Box = { X0: number, X1: number, Z0: number, Z1: number }

local function box(x0, x1, z0, z1): Box
	return { X0 = x0, X1 = x1, Z0 = z0, Z1 = z1 }
end

-- How far apart two boxes are (0 when they touch or overlap).
local function gap(a: Box, b: Box): number
	local dx = math.max(0, a.X0 - b.X1, b.X0 - a.X1)
	local dz = math.max(0, a.Z0 - b.Z1, b.Z0 - a.Z1)
	return math.sqrt(dx * dx + dz * dz)
end

-- The bounding box of a `width` x `depth` footprint at (x, z) turned to face (tx, tz), as the kiosks do.
local function facing(x: number, z: number, width: number, depth: number, tx: number, tz: number): Box
	local fx, fz = tx - x, tz - z
	local length = math.sqrt(fx * fx + fz * fz)
	fx, fz = fx / length, fz / length
	-- its depth runs along the facing direction, its width across it
	local halfX = math.abs(fx) * depth / 2 + math.abs(fz) * width / 2
	local halfZ = math.abs(fz) * depth / 2 + math.abs(fx) * width / 2
	return box(x - halfX, x + halfX, z - halfZ, z + halfZ)
end

local spawnBox = box(
	Town.SpawnOffset.X - Town.SpawnSize / 2,
	Town.SpawnOffset.X + Town.SpawnSize / 2,
	Town.SpawnOffset.Z - Town.SpawnSize / 2,
	Town.SpawnOffset.Z + Town.SpawnSize / 2
)
local BELT_END = Config.Belt.Offset.X + 1.5 -- the belt (x -220..220) and its end rollers
local laneBox = box(-BELT_END, BELT_END, -Town.BeltClear, Town.BeltClear)
local plaza = Town.Plaza
local agency = facing(
	Config.Agency.Offset.X,
	Config.Agency.Offset.Z,
	KIOSK_WIDTH,
	KIOSK_DEPTH,
	Town.SpawnOffset.X,
	Town.SpawnOffset.Z
)
local market = facing(
	Config.Market.Offset.X,
	Config.Market.Offset.Z,
	KIOSK_WIDTH,
	KIOSK_DEPTH,
	Town.SpawnOffset.X,
	Town.SpawnOffset.Z
)

T.describe("Town layout: the shipped numbers (look build plan §B2)", function()
	test("Config matches the plan exactly", function()
		-- the bigger, open building (simple-start design §4): the plots grew 110 -> 140 for the 96 x 66 clinic, the
		-- street 394 -> 484, and the belt with it (180/360 -> 220/440; the ride takes the same 133 s, so the cadence
		-- and the time each nurse is on offer did not change)
		expect(Town.PlotSize).toBe(140)
		expect({ Config.Belt.Offset.X, Config.Belt.Offset.Y, Config.Belt.Offset.Z }).toEqual({ 220, 0, 0 })
		expect(Config.Belt.Length).toBe(440)
		expect(Config.Belt.RideSeconds).toBe(133)
		expect(Config.Belt.Length / Config.Belt.RideSeconds <= 4).toBe(true) -- a calm ride (Belt.spec)
		expect({ Config.Belt.SignOffset.X, Config.Belt.SignOffset.Z }).toEqual({ -24, 11 })
		expect({ Town.SpawnOffset.X, Town.SpawnOffset.Y, Town.SpawnOffset.Z }).toEqual({ 0, 0, 11 })
		expect(Town.SpawnSize).toBe(8)
		expect(Town.Plaza).toEqual({ X0 = -30, X1 = 30, Z0 = 5.4, Z1 = 17 })
		expect(Town.BeltClear).toBe(4.4)
		expect({ Config.Agency.Offset.X, Config.Agency.Offset.Z }).toEqual({ 13, 12 })
		expect({ Config.Market.Offset.X, Config.Market.Offset.Z }).toEqual({ -13, 12 })
	end)

	test("the street: z -18..18, x -242..242; PlotBuilder and TownBuilder agree on its numbers", function()
		expect(HALF).toBe(18)
		expect(STREET_END).toBe(242)
		for _, name in { "STREET_HALF_WIDTH", "PLOT_GAP", "BASE_TOP" } do
			expect(numberIn(TOWN_BUILDER, name)).toBe(numberIn(PLOT_BUILDER, name))
		end
	end)

	test("requires never loop: TownBuilder and HospitalBuilder never require PlotBuilder", function()
		for _, path in { "src/server/TownBuilder.luau", "src/server/HospitalBuilder.luau" } do
			expect(string.find(source(path), "require(script.Parent.PlotBuilder", 1, true)).toBeNil()
		end
		for _, name in { "Parts", "Props", "NightLights", "Studs" } do
			local text = source("src/server/World/" .. name .. ".luau")
			expect(string.find(text, "PlotBuilder)", 1, true)).toBeNil()
			expect(string.find(text, "TownBuilder)", 1, true)).toBeNil()
			expect(string.find(text, "HospitalBuilder)", 1, true)).toBeNil()
		end
	end)
end)

T.describe("Town layout: the belt's lane", function()
	local sx, sz, ex, ez = Belt.path(Config)

	test("the belt runs along the road's centre line, x 220 to -220, inside its lane", function()
		expect(math.abs(sz) < 1e-6 and math.abs(ez) < 1e-6).toBe(true)
		expect(sx).toBe(220)
		expect(ex).toBeCloseTo(-220, 6)
		-- it runs most of the street, and passes every plot's gate (the columns at x -148 / 0 / 148)
		expect(Config.Belt.Length >= 0.8 * 2 * STREET_END).toBe(true)
		expect(sx > Town.PlotSize + GAP and ex < -(Town.PlotSize + GAP)).toBe(true)
		expect(math.max(sx, ex) <= laneBox.X1 and math.min(sx, ex) >= laneBox.X0).toBe(true)
		-- its bed is +-3.3 (NurseBelt: BELT_WIDTH 5 + 1.6); the lane leaves it a stud each side
		expect(Town.BeltClear - 3.3 >= 1).toBe(true)
		-- the lane ends inside the welcome arches (their posts at x = +-237) and the Hall of Fame (x < -242)
		expect(laneBox.X1 < STREET_END - 5 - 0.8).toBe(true)
		expect(laneBox.X0 > -STREET_END).toBe(true)
	end)

	test("a lane stays free along each curb, either side of the belt", function()
		expect(CURB_INNER - Town.BeltClear >= 2).toBe(true)
	end)

	test("every plot's gate is still within hire reach of a rider on the centre line", function()
		for column = 1, PER_ROW do
			local x = (column - (PER_ROW + 1) / 2) * (Town.PlotSize + GAP)
			for _, side in { -1, 1 } do
				-- the gate in the plot's front fence (plot-local z = -(PlotSize / 2 - 0.4): -69.6)
				local gateZ = side * (HALF + 0.4)
				expect(Belt.distanceToPath(Config, x, gateZ) <= Config.Belt.HireDistance - 5).toBe(true)
			end
		end
	end)
end)

T.describe("Town layout: the plaza, the spawn, the kiosks and the sign", function()
	test("the plaza is the street's row-2 half: off the belt's lane, inside the curb", function()
		expect(plaza.Z0 >= Town.BeltClear + 1).toBe(true)
		expect(plaza.Z1 <= CURB_INNER).toBe(true)
		expect(plaza.Z0 > 0).toBe(true) -- row 2's side
		expect(plaza.X0 == -plaza.X1).toBe(true)
		expect(plaza.X1 <= STREET_END).toBe(true)
	end)

	test("TownSpawn: an 8 x 8 pad at (0, 11), inside the plaza, 2 studs off the belt's lane", function()
		expect(spawnBox).toEqual(box(-4, 4, 7, 15))
		expect(gap(spawnBox, laneBox) >= 2).toBe(true)
		expect(spawnBox.X0 >= plaza.X0 and spawnBox.X1 <= plaza.X1).toBe(true)
		expect(spawnBox.Z0 >= plaza.Z0 and spawnBox.Z1 <= plaza.Z1).toBe(true)
	end)

	test(
		"the kiosks (7 x 4.5, turned to face TownSpawn): 1 stud from the spawn, the lane, each other and the plaza's edge",
		function()
			for name, kiosk in { Agency = agency, Market = market } do
				if gap(kiosk, spawnBox) < 1 then
					error(name .. " is within a stud of the spawn")
				end
				if gap(kiosk, laneBox) < 1 then
					error(name .. " is within a stud of the belt's lane")
				end
				expect(kiosk.X0 >= plaza.X0 + 1 and kiosk.X1 <= plaza.X1 - 1).toBe(true)
				expect(kiosk.Z0 >= plaza.Z0 + 1 and kiosk.Z1 <= plaza.Z1 - 1).toBe(true)
			end
			expect(gap(agency, market) >= 1).toBe(true)
			-- one each side of the spawn
			expect(Config.Agency.Offset.X > spawnBox.X1 and Config.Market.Offset.X < spawnBox.X0).toBe(true)
		end
	)

	test("nothing solid in the row-2 middle gate's mouth (|x| <= 3, z 15..18)", function()
		local mouth = box(-3, 3, 15, 18)
		expect(gap(agency, mouth) > 0).toBe(true)
		expect(gap(market, mouth) > 0).toBe(true)
		local signX, signZ = Config.Belt.SignOffset.X, Config.Belt.SignOffset.Z
		expect(gap(box(signX, signX, signZ, signZ), mouth) > 0).toBe(true)
		-- the spawn pad is flat ground (you stand on it); it may reach the mouth's line but not past the curb
		expect(spawnBox.Z1 <= CURB_INNER).toBe(true)
	end)

	test(
		"the odds sign: at the plaza's west end, beside the Market, clear of everything; how wide it may be",
		function()
			local signX, signZ = Config.Belt.SignOffset.X, Config.Belt.SignOffset.Z
			local at = box(signX, signX, signZ, signZ)
			expect(signX >= plaza.X0 + 1 and signX <= plaza.X1 - 1).toBe(true)
			expect(signZ >= plaza.Z0 + 1 and signZ <= plaza.Z1 - 1).toBe(true)
			expect(signX < market.X0).toBe(true) -- west of the Market
			expect(gap(at, market) >= 1).toBe(true)
			expect(gap(at, spawnBox) >= 1).toBe(true)
			expect(gap(at, laneBox) >= 1).toBe(true)
			expect(Belt.distanceToPath(Config, signX, signZ) <= Config.Belt.HireDistance).toBe(true)
			-- Facing TownSpawn (+x from here) its width runs along z. Keeping a stud from the lane and from the plaza's
			-- edges, it may be this wide at most (T2 sizes the sign's plate to fit):
			local widest = 2 * math.min(signZ - (plaza.Z0 + 1), (plaza.Z1 - 1) - signZ)
			print(string.format("    [town] the odds sign may be at most %.1f studs wide", widest))
			expect(widest >= 9).toBe(true)
			-- ... and that deep before it reaches the Market or the plaza's west edge
			expect(market.X0 - signX >= 1 + 1).toBe(true)
			expect(signX - plaza.X0 >= 1 + 1).toBe(true)
		end
	)

	test(
		"the street lamps (x +-74, z +-16.4) and the crossings (x +-148) are outside the plaza and the kiosks",
		function()
			-- TownBuilder: the lamps stand in the gaps between plot columns, the crossings at the outer gates
			local pitch = Town.PlotSize + GAP -- 148
			expect(pitch).toBe(148)
			for _, x in { -pitch / 2, pitch / 2 } do
				local lamp = box(x - 0.8, x + 0.8, 16.4 - 0.8, 16.4 + 0.8)
				expect(gap(lamp, agency) >= 1 and gap(lamp, market) >= 1 and gap(lamp, spawnBox) >= 1).toBe(true)
				expect(math.abs(x) > plaza.X1).toBe(true)
			end
			expect(pitch - 4 > plaza.X1).toBe(true)
		end
	)
end)
