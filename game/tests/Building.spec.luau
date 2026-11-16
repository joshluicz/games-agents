--!nocheck
-- The hospital building's interface numbers (Logic/Building; look build plan §B6; hospital-building §3.2-3.3),
-- checked against what Server/Patients assumes: its walkways at x = ±12.5, its back lane at z = 4 (BackZ), its
-- bedRoute at x = 7.6 through the main door, and its straight-line walk upstairs from the landing to a bed's foot.
-- The plot's own numbers (the Counter, the line, the gate, the sign, the room slots) are read from PlotBuilder's
-- SLOTS and Config, or repeated here from PlotBuilder's text where it has no table (noted).

local T = require("./expect")
local expect, test = T.expect, T.test

local Config = require("./config")
local Building = require("../src/shared/Logic/Building")
local Levels = require("../src/shared/Data/Levels")
local Departments = require("../src/shared/Data/Departments")

local LEVELS = { 1, 2, 3, 4, 5 }

-- What Server/Patients works out on a placeholder plot (Patients.nav): the Stand slot is x ±11, z -13..1, the side
-- rooms start at |x| = 14, so the walkways run at 11 + (14 - 11) / 2 and the back lane at 1 + 3.
local WALKWAY = 12.5
local BACK_Z = 4
local BED_ROUTE_X = 7.6 -- the Counter's half width (6) + 1.6: Patients' SideStep
local LANE_Z = -18 -- QueueStart
local RAY_START = 10 -- Patients' ground raycasts start at the plot's y + 10

local function rect(x0, x1, z0, z1)
	return { X0 = x0, X1 = x1, Z0 = z0, Z1 = z1 }
end

local function around(x, z, half)
	return rect(x - half, x + half, z - half, z + half)
end

T.describe("Building: the shape", function()
	test("footprints: the podium at Lv 1, the block from Lv 2, the tower from F2", function()
		expect(Building.footprint(1)).toEqual(rect(-11.5, 11.5, -13, 3))
		for level = 2, 5 do
			expect(Building.footprint(level, 0)).toEqual(rect(-11.5, 11.5, -13, 13))
			expect(Building.footprint(level, 1)).toEqual(rect(-11.5, 11.5, -13, 13))
			expect(Building.footprint(level, 2)).toEqual(rect(-11.5, 11.5, -3, 13))
			expect(Building.footprint(level, 4)).toEqual(rect(-11.5, 11.5, -3, 13))
		end
	end)

	test("storeys: ground 11, upper 9; slab tops 11, 20, 29, 38", function()
		expect(Building.GROUND).toBe(11)
		expect(Building.STOREY).toBe(9)
		expect(Building.SLAB_TOPS).toEqual({ 11, 20, 29, 38 })
		expect(Building.slabTop(0)).toBe(0)
		for k = 1, 4 do
			expect(Building.slabTop(k)).toBe(Building.GROUND + (k - 1) * Building.STOREY)
		end
	end)

	test("a slab's underside is >= 10.4, above where Patients' ground raycasts start", function()
		expect(Building.SLAB_MAX).toBe(0.6)
		local underside = Building.slabTop(1) - Building.SLAB_MAX
		expect(underside >= 10.4 - 1e-9).toBe(true)
		expect(underside > RAY_START).toBe(true)
	end)

	test("the floors and departments follow Data/Levels and Data/Departments", function()
		for level, row in Levels do
			if type(level) == "number" then
				expect(Building.floors(level)).toBe(row.Floors)
			end
		end
		expect(Building.WARD_FLOOR).toBe(Departments.Wards.Floor)
		expect(Departments.Hydro.Floor).toBe(2)
		expect(Departments.Pharmacy.Floor).toBe(3)
		expect(Departments.Roof.Floor).toBe(4)
		expect(Building.slabTop(Departments.Roof.Floor)).toBe(38) -- the roof deck
	end)

	test("the lift: the shaft at the street-facing -x corner, its landing on +z, 4 x 4 at (-9, 4)", function()
		expect(Building.SHAFT).toEqual(rect(-11.5, -6.5, -3, 2))
		expect(Building.LANDING).toEqual({ X = -9, Z = 4, Size = 4 })
		local landing = around(Building.LANDING.X, Building.LANDING.Z, Building.LANDING.Size / 2)
		-- right behind the door, inside the block, and not on the shaft or the stair atrium
		expect(landing.Z0 >= Building.SHAFT.Z1).toBe(true)
		expect(landing.X0 >= -Building.HALF and landing.X1 <= Building.HALF).toBe(true)
		expect(landing.Z1 <= Building.ATRIUM.Z0).toBe(true)
		expect(Building.LANDING.X > Building.SHAFT.X0 and Building.LANDING.X < Building.SHAFT.X1).toBe(true)
	end)

	test("the door rects (hospital doc §3.3)", function()
		local d = Building.DOORS
		expect({ d.Main.X0, d.Main.X1, d.Main.Height }).toEqual({ 7, 11, 7 })
		expect({ d.Reception.X0, d.Reception.X1, d.Reception.Height }).toEqual({ -6.5, 6.5, 7 })
		expect({ d.Display.X0, d.Display.X1 }).toEqual({ -11, -7 })
		expect({ d.Side.Z0, d.Side.Z1 }).toEqual({ -1, 3 })
		expect({ d.AE.Z0, d.AE.Z1 }).toEqual({ -7, -3 })
		expect({ d.LiftLobby.Z0, d.LiftLobby.Z1 }).toEqual({ 2, 6 })
		expect({ d.Corridor.Z0, d.Corridor.Z1 }).toEqual({ 2, 6 })
		-- the lift-lobby and corridor doors cover Patients' back lane
		expect(d.LiftLobby.Z0 < BACK_Z and BACK_Z < d.LiftLobby.Z1).toBe(true)
		expect(d.Corridor.Z0 < BACK_Z and BACK_Z < d.Corridor.Z1).toBe(true)
		-- the main door covers the bedRoute's x, with a stud to spare each side
		expect(d.Main.X0 <= BED_ROUTE_X - 0.5 and BED_ROUTE_X + 0.5 <= d.Main.X1).toBe(true)
		-- a creature (about 7 tall at most) fits under every door and under the ground storey's ceiling
		expect(d.Main.Height >= 7).toBe(true)
	end)

	test("the canopy covers the Counter and stops short of queue spot 1", function()
		local c = Building.CANOPY
		expect({ c.X0, c.X1, c.Z0, c.Z1, c.Y }).toEqual({ -9, 9, -17, -13, 9.5 })
		expect(c.Z0 > LANE_Z).toBe(true) -- spot 1 stands at z = -18, in the open
		expect(c.Z1).toBe(Building.FRONT)
		expect(c.Y < Building.GROUND).toBe(true)
		expect(c.Y > Building.DOORS.Main.Height).toBe(true)
	end)
end)

T.describe("Building: the Stand's spots", function()
	test("the spots (Remedy and Plaster moved +1.2 in x; decor 2 on the porch; the mascot by the Counter)", function()
		local s = Building.STAND
		expect(s.Remedy).toEqual({ X = -4.3, Z = -1.3 })
		expect(s.Plaster).toEqual({ X = 1.7, Z = -1.3 })
		expect(s.Bed).toEqual({ X = 7.6, Z = -4.8 })
		expect(s.Decor[1]).toEqual({ X = -8.5, Z = -10.2 })
		expect(s.Decor[2]).toEqual({ X = -9.5, Z = -17.5 })
		expect(s.Mascot).toEqual({ X = -7, Z = -14.8 })
		expect(s.Bench).toEqual(rect(10, 10.9, -8, -3.5))
		-- Bed_1 is on the bedRoute's line
		expect(s.Bed.X).toBe(BED_ROUTE_X)
	end)

	test("the stations stand inside the podium, clear of the lift shaft and of each other", function()
		local s = Building.STAND
		local podium = Building.footprint(1)
		for _, at in { s.Remedy, s.Plaster } do
			local station = rect(at.X - 2.1, at.X + 2.1, at.Z - 1.3, at.Z + 1.3) -- a station's 4.2 x 2.6 body
			expect(station.X0 > podium.X0 and station.X1 < podium.X1).toBe(true)
			expect(station.Z0 > podium.Z0 and station.Z1 < podium.Z1).toBe(true)
			expect(station.X0 >= Building.SHAFT.X1).toBe(true) -- the reason they moved
		end
		expect(s.Plaster.X - s.Remedy.X >= 4.5 + 1).toBe(true)
		-- nothing in the Stand blocks the bedRoute lane (x 7.6, a 4.4-wide bed at its end)
		expect(s.Plaster.X + 2.25 < s.Bed.X - 2.2).toBe(true)
	end)

	test("decor slot 2 and the mascot are outside the façade; the bench is against the +x wall", function()
		local s = Building.STAND
		expect(s.Decor[2].Z < Building.FRONT).toBe(true)
		expect(s.Mascot.Z < Building.FRONT).toBe(true)
		expect(s.Decor[1].Z > Building.FRONT).toBe(true) -- slot 1 is inside, behind the display window
		expect(s.Decor[1].X > Building.DOORS.Display.X0 and s.Decor[1].X < Building.DOORS.Display.X1).toBe(true)
		expect(s.Bench.X1 <= Building.HALF - Building.WALL + 1e-9).toBe(true)
		-- neither porch spot is on the line or the gate path (|x| < 5.1)
		expect(math.abs(s.Decor[2].X) - 2 >= 5.1).toBe(true)
		expect(math.abs(s.Mascot.X) - 1 >= 5.1).toBe(true)
	end)
end)

T.describe("Building.clear: nothing solid where the plot needs room", function()
	local slots = { -- PlotBuilder.SLOTS: Offset and Size
		Stand = rect(-11, 11, -13, 1),
		A = rect(-32, -14, -2, 14),
		C = rect(14, 32, -2, 14),
		B = rect(-24, -2, 18, 32),
		D = rect(2, 24, 18, 32),
	}

	test("the Counter, the line spots, the gate, the sign and the owner's spawn, at every level", function()
		local zones = {
			Counter = rect(-6.4, 6.4, -16, -13), -- the CounterTop (13 x 3 at z -14.5: it fills the reception window, x ±6.5)
			Gate = rect(-7, 7, -35, -33),
			Sign = rect(-18.5, -7.5, -35, -32),
			OwnerSpawn = around(-6.5, -22, 2),
			QueueStart = around(0, LANE_Z, 1),
		}
		for index = 1, Config.MaxQueue do
			-- PlotBuilder.queueSpot: straight back from QueueStart, Config.QueueSpacing apart
			zones["Line" .. index] = around(0, LANE_Z - (index - 1) * Config.QueueSpacing, 1.8)
		end
		for _, level in LEVELS do
			for name, zone in zones do
				if not Building.clear(zone, level) then
					error(name .. " is covered at Lv " .. level)
				end
			end
		end
	end)

	test("the room slots A to D, the walkways and (at Lv 1) the back lane", function()
		for _, level in LEVELS do
			for _, id in { "A", "B", "C", "D" } do
				expect(Building.clear(slots[id], level)).toBe(true)
			end
			for _, side in { -1, 1 } do
				local x = side * WALKWAY
				-- the walkway, a stud wide, from the line to the back of the block
				expect(Building.clear(rect(x - 0.5, x + 0.5, LANE_Z, 14), level)).toBe(true)
			end
		end
		expect(Building.clear(rect(-WALKWAY, WALKWAY, BACK_Z - 0.5, BACK_Z + 0.5), 1)).toBe(true)
	end)

	test("the block does cover the Stand's slot (the Stand is inside it), and clear() says so", function()
		for _, level in LEVELS do
			expect(Building.clear(slots.Stand, level)).toBe(false)
		end
		local function has(level, name)
			for _, o in Building.obstacles(level, 0) do
				if o.Name == name then
					return true
				end
			end
			return false
		end
		expect(has(1, "Shaft")).toBe(false) -- no lift at Lv 1 ...
		expect(has(1, "DressBed")).toBe(true) -- ... the Lv 1 dressing bed stands along that wall instead
		expect(has(2, "Shaft")).toBe(true)
		expect(has(2, "DressBed")).toBe(false)
		expect(has(2, "Stairs")).toBe(true)
		expect(Building.clear(Building.SHAFT, 2)).toBe(false)
		expect(#Building.obstacles(1, 1)).toBe(0) -- a floor that isn't built has nothing on it
	end)

	test("the footprint stays inside the walkways, and off every side and back slot", function()
		for _, level in LEVELS do
			local f = Building.footprint(level)
			expect(f.X1 < WALKWAY - 0.5 and f.X0 > -WALKWAY + 0.5).toBe(true)
			expect(f.X1 <= slots.C.X0 - 2).toBe(true)
			expect(f.X0 >= slots.A.X1 + 2).toBe(true)
			expect(f.Z1 <= slots.B.Z0 - 5).toBe(true) -- the back rooms keep a yard
		end
	end)
end)

T.describe("Building.reach: Patients' routes cross no wall, shaft, bed or stairs", function()
	local function pt(x, z)
		return { X = x, Z = z }
	end
	local stand = Building.STAND
	-- Patients.bedFoot: 1.6 past the mattress's foot (Bed_1 is 6.6 long, its pillow to +z)
	local bed1Foot = pt(stand.Bed.X, stand.Bed.Z - 3.3 - 1.6)

	test("ground beds: the bedRoute at x = 7.6 from the line through the main door, at every level", function()
		for _, level in LEVELS do
			expect(Building.reach(pt(BED_ROUTE_X, LANE_Z), bed1Foot, level)).toBe(true)
			expect(Building.reach(bed1Foot, pt(BED_ROUTE_X, LANE_Z), level)).toBe(true) -- and back out
		end
	end)

	test("a route through the façade anywhere else is blocked (the check isn't blind)", function()
		for _, level in LEVELS do
			expect(Building.reach(pt(-9, LANE_Z), pt(-9, -9), level)).toBe(false) -- the display window is glass
			expect(Building.reach(pt(6.75, LANE_Z), pt(6.75, -9), level)).toBe(false) -- the pier by the main door
			expect(Building.reach(pt(-WALKWAY, -9), pt(0, -9), level)).toBe(false) -- the -x wall
		end
	end)

	test("the walkways at x = ±12.5 run clear from the line to the back lane", function()
		for _, level in LEVELS do
			for _, side in { -1, 1 } do
				expect(Building.reach(pt(side * WALKWAY, LANE_Z), pt(side * WALKWAY, BACK_Z), level)).toBe(true)
			end
		end
	end)

	test("Lv 1: the back lane at z = 4 passes behind the podium", function()
		expect(Building.PODIUM_BACK < BACK_Z).toBe(true)
		expect(Building.reach(pt(-WALKWAY, BACK_Z), pt(WALKWAY, BACK_Z), 1)).toBe(true)
	end)

	test("Lv 2+: in at the lift-lobby door to Landing_0, and east along z = 4 out of the corridor door", function()
		local landing = pt(Building.LANDING.X, Building.LANDING.Z)
		for level = 2, 5 do
			expect(Building.reach(pt(-WALKWAY, BACK_Z), landing, level)).toBe(true)
			expect(Building.reach(landing, pt(WALKWAY, BACK_Z), level)).toBe(true)
			expect(Building.reach(pt(-WALKWAY, BACK_Z), pt(WALKWAY, BACK_Z), level)).toBe(true)
			-- but not through the walls beside those doors
			expect(Building.reach(pt(-WALKWAY, 8), pt(0, 8), level)).toBe(false)
			expect(Building.reach(pt(WALKWAY, 0), pt(0, 0), level)).toBe(false)
		end
	end)

	test("upstairs: every ward bed's foot is a straight walk from Floor_1.Landing", function()
		local landing = pt(Building.LANDING.X, Building.LANDING.Z)
		for level = 2, 5 do
			local beds = Building.wardBeds(level)
			expect(#beds).toBe(3) -- the main ward always shows three beds
			for _, bed in beds do
				local x, z = Building.bedFoot(bed.X)
				expect(z).toBe(6.0)
				if not Building.reach(landing, pt(x, z), level, Building.WARD_FLOOR) then
					error(string.format("Lv %d: BedSpot_%d's foot isn't reachable from the landing", level, bed.Index))
				end
			end
		end
	end)

	test("upstairs: a walk through a bed, the shaft, the atrium or the partition is blocked", function()
		local landing = pt(Building.LANDING.X, Building.LANDING.Z)
		for level = 2, 5 do
			expect(Building.reach(landing, pt(-4.1, 0), level, 1)).toBe(false) -- onto bed 1
			expect(Building.reach(landing, pt(-9, -6), level, 1)).toBe(false) -- through the shaft
			expect(Building.reach(landing, pt(0, 11), level, 1)).toBe(false) -- into the stair atrium
			expect(Building.reach(pt(-0.5, 5.5), pt(-0.5, -8), level, 1)).toBe(false) -- through the glass partition
			expect(Building.reach(landing, pt(-9, 20), level, 1)).toBe(false) -- out through the back wall
		end
		-- the front ward has its doorway (players only: Patients never go there)
		expect(Building.reach(pt(10.2, 5.5), pt(10.2, -4.5), 2, 1)).toBe(true)
	end)

	test("the skim allowance is small: under a third of a stud", function()
		expect(Building.SKIM > 0 and Building.SKIM <= 0.3).toBe(true)
	end)
end)

T.describe("Building: the wards look full (Joshua, memory-20261117-002)", function()
	test("functional ward beds match Data/Levels.Beds - 1 at every level (no gameplay change)", function()
		for level, row in Levels do
			if type(level) == "number" then
				local functional = 0
				for _, bed in Building.wardBeds(level) do
					if bed.Functional then
						functional += 1
					end
				end
				expect(functional).toBe(math.max(0, row.Beds - 1))
			end
		end
	end)

	test("BedSpot_3's spot holds a dressing bed at Lv 2-3 and turns functional at Lv 4, in the same spot", function()
		for level = 2, 5 do
			local third = Building.wardBeds(level)[3]
			expect(third.X).toBe(6.7)
			expect(third.Functional).toBe(level >= 4)
		end
		expect(Building.wardBeds(1)).toEqual({})
	end)

	test("visible beds: 2 at Lv 1, and 7 on the Wards floor at Lv 2-5 (Config.Look)", function()
		expect(Config.Look.Lv1Beds).toBe(2) -- Bed_1 + the Lv 1 dressing bed
		for level = 2, 5 do
			local onFloor = #Building.wardBeds(level) + #Building.FRONT_WARD.Xs
			expect(onFloor).toBe(Config.Look.WardFloorBeds)
		end
		expect(Config.Look.Sleepers).toEqual({ Lv1 = 1, Ward = 2 })
	end)

	test("no two beds on the Wards floor overlap, and each is inside the floor and off the shaft", function()
		local beds = {}
		for _, bed in Building.wardBeds(2) do
			table.insert(beds, Building.bedRect(bed.X))
		end
		local front = Building.FRONT_WARD
		for _, x in front.Xs do
			table.insert(beds, rect(x - Building.BED_HALF, x + Building.BED_HALF, front.Z0, front.Z1))
		end
		local f = Building.footprint(2, 1)
		for i, a in beds do
			expect(a.X0 >= f.X0 and a.X1 <= f.X1 and a.Z0 >= f.Z0 and a.Z1 <= f.Z1).toBe(true)
			local s = Building.SHAFT
			expect(a.X0 < s.X1 and s.X0 < a.X1 and a.Z0 < s.Z1 and s.Z0 < a.Z1).toBe(false)
			for j, b in beds do
				if i < j then
					expect(a.X0 < b.X1 and b.X0 < a.X1 and a.Z0 < b.Z1 and b.Z0 < a.Z1).toBe(false)
				end
			end
		end
		-- the main ward's pillows are at the partition; the front ward's heads at the street window
		expect(Building.BED_Z0 > Building.PARTITION_Z).toBe(true)
		expect(front.Z0 > Building.FRONT).toBe(true)
		expect(front.Z1 < Building.PARTITION_Z).toBe(true)
	end)

	test("the Lv 1 dressing bed: along the -x wall, clear of the side door and the Remedy table", function()
		local d = Building.LV1_DRESSING
		expect(d).toEqual(rect(-11.3, -6.9, -8.5, -1.5))
		expect(d.Z1 <= Building.DOORS.Side.Z0).toBe(true)
		expect(d.X1 <= Building.STAND.Remedy.X - 2.25).toBe(true)
		expect(d.X0 >= -Building.HALF).toBe(true)
	end)
end)
