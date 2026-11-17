--!nocheck
-- The hospital world (look build plan §B6, §D T3; Progression v2 build plan §B4 for the names): the building's layout
-- (HospitalBuilder.Pure, which PlotBuilder.Pure re-exports, against Shared/Logic/Building), the lift's rules
-- (Server/Lift and UI/LiftPanel pure blocks), the 💊 Pharmacy's craft check and the hold factors (Server/Stations),
-- and the cutaway's rules (Feel/Cutaway).
-- The pure blocks are loaded straight from the shipped source. The last part builds the REAL PlotBuilder (and through
-- it HospitalBuilder, TownBuilder and World/*) under tests/worldmock (Lune's roblox datatypes; no Roblox services),
-- so the contract's names, the budgets, the straight walks upstairs and the clearances are checked on what ships.
-- It prints the building's measured part count per level (the perf note's table). The plot's 400 is
-- tests/PartBudget.spec. Run from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local T = require("./expect")
local expect, test = T.expect, T.test

local Config = require("./config")
local LevelsData = require("../src/shared/Data/Levels")
local Departments = require("../src/shared/Data/Departments")
local Items = require("../src/shared/Data/Items")
local Themes = require("../src/shared/Data/Themes")
local Recipe = require("../src/shared/Logic/Recipe")
local Rebirth = require("../src/shared/Logic/Rebirth")
local B = require("../src/shared/Logic/Building")
local Look = require("./look")

local function find(relative: string): string
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. relative) then
			return prefix .. relative
		end
	end
	error("can't find " .. relative .. " (run from game/)")
end

local function loadPure(path: string): any
	local text = fs.readFile(find(path))
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to and to > from, path .. ": no PURE block")
	return luau.load(string.sub(text, from, to - 1) .. "\nreturn Pure\n", { debugName = path .. " (pure)" })()
end

local H = loadPure("src/server/HospitalBuilder.luau")
local Lift = loadPure("src/server/Lift.luau")
local Panel = loadPure("src/client/UI/LiftPanel.luau")
local Stations = loadPure("src/server/Stations.luau")
local Cut = loadPure("src/client/Feel/Cutaway.luau")

local ROOF = Departments.Roof.Floor
local LANDING = { X = B.LANDING.X, Z = B.LANDING.Z }

local function rect(x0, x1, z0, z1)
	return { X0 = x0, X1 = x1, Z0 = z0, Z1 = z1 }
end

local function overlaps(a, b): boolean
	local e = 0.01
	return a.X0 < b.X1 - e and b.X0 < a.X1 - e and a.Z0 < b.Z1 - e and b.Z0 < a.Z1 - e
end

local function inside(inner, outer): boolean
	local e = 0.01
	return inner.X0 >= outer.X0 - e
		and inner.X1 <= outer.X1 + e
		and inner.Z0 >= outer.Z0 - e
		and inner.Z1 <= outer.Z1 + e
end

local function area(r): number
	return (r.X1 - r.X0) * (r.Z1 - r.Z0)
end

local function landingRect()
	local h = B.LANDING.Size / 2
	return rect(LANDING.X - h, LANDING.X + h, LANDING.Z - h, LANDING.Z + h)
end

-- Whether the segment a -> b passes through r shrunk by `shrink` a side (Liang-Barsky; as Logic/Building.reach).
local function crosses(a, b, r, shrink: number): boolean
	local x0, x1, z0, z1 = r.X0 + shrink, r.X1 - shrink, r.Z0 + shrink, r.Z1 - shrink
	if x1 <= x0 then
		x0, x1 = (r.X0 + r.X1) / 2 - 1e-3, (r.X0 + r.X1) / 2 + 1e-3
	end
	if z1 <= z0 then
		z0, z1 = (r.Z0 + r.Z1) / 2 - 1e-3, (r.Z0 + r.Z1) / 2 + 1e-3
	end
	local dx, dz = b.X - a.X, b.Z - a.Z
	local t0, t1 = 0, 1
	for _, edge in { { -dx, a.X - x0 }, { dx, x1 - a.X }, { -dz, a.Z - z0 }, { dz, z1 - a.Z } } do
		local p, q = edge[1], edge[2]
		if math.abs(p) < 1e-9 then
			if q < 0 then
				return false
			end
		else
			local t = q / p
			if p < 0 then
				t0 = math.max(t0, t)
			else
				t1 = math.min(t1, t)
			end
			if t0 > t1 then
				return false
			end
		end
	end
	return true
end

------------------------------------------------------------------------------------------------------------------
-- The layout in numbers (HospitalBuilder.Pure on Logic/Building)
------------------------------------------------------------------------------------------------------------------

T.describe("Hospital (layout)", function()
	test("each floor's slab: its footprint less the shaft and one open lane, in pieces that never overlap", function()
		for k = 1, 4 do
			local rects = H.slabRects(B, k)
			local f = B.footprint(5, k)
			local hole = H.lane(B, H.holeLane(k))
			local total, named = 0, 0
			for i, r in rects do
				expect(inside(r, f)).toBe(true)
				expect(overlaps(r, B.SHAFT)).toBe(false)
				expect(overlaps(r, hole)).toBe(false)
				for j, other in rects do
					if i < j then
						expect(overlaps(r, other)).toBe(false)
					end
				end
				total += area(r)
				if r.Name == "Slab" then
					named += 1
					expect(inside(landingRect(), r)).toBe(true) -- the contract's Slab carries the landing
				end
			end
			expect(named).toBe(1)
			local shaft = if inside(B.SHAFT, f) then area(B.SHAFT) else 0
			expect(total).toBeCloseTo(area(f) - shaft - area(hole), 5)
		end
	end)

	test("the open lanes alternate (F1 and F3 lane A, F2 and the roof lane B)", function()
		expect({ H.holeLane(1), H.holeLane(2), H.holeLane(3), H.holeLane(4) }).toEqual({ "A", "B", "A", "B" })
		expect(H.lane(B, "A")).toEqual(rect(-12, 12, 7, 10))
		expect(H.lane(B, "B")).toEqual(rect(-12, 12, 10, 13))
	end)

	test(
		"each flight: one storey up at 45 degrees or less, its top meeting the next one's foot, with headroom",
		function()
			local a = B.ATRIUM
			for k = 0, 3 do
				local fl = H.flight(B, k)
				expect(fl.YLow).toBe(B.slabTop(k))
				expect(fl.YHigh).toBe(B.slabTop(k + 1))
				local run = math.abs(fl.XHigh - fl.XLow)
				expect(math.deg(math.atan2(fl.YHigh - fl.YLow, run)) <= 45).toBe(true)
				expect((fl.YHigh - fl.YLow) / run <= 0.5 + 1e-9).toBe(true) -- the wide hospital's shallower flights
				expect(run).toBe(a.X1 - a.X0) -- the whole lane
				-- the floor it arrives on leaves its lane open ...
				for _, r in H.slabRects(B, k + 1) do
					expect(overlaps(r, rect(a.X0, a.X1, fl.Z0, fl.Z1))).toBe(false)
				end
				-- ... and the floor it starts from (above the ground) holds it up: its lane is covered there
				if k >= 1 then
					local covered = 0
					for _, r in H.slabRects(B, k) do
						local x0, x1 = math.max(r.X0, a.X0), math.min(r.X1, a.X1)
						local z0, z1 = math.max(r.Z0, fl.Z0), math.min(r.Z1, fl.Z1)
						if x1 > x0 and z1 > z0 then
							covered += (x1 - x0) * (z1 - z0)
						end
					end
					expect(covered).toBeCloseTo((a.X1 - a.X0) * (fl.Z1 - fl.Z0), 5)
				end
				if k < 3 then
					local nextFlight = H.flight(B, k + 1)
					expect(nextFlight.XLow).toBe(fl.XHigh)
					expect(nextFlight.Lane ~= fl.Lane).toBe(true)
				end
				-- standing at the top of a flight, the slab over it is a full storey up (a 5-stud rider fits)
				expect(B.slabTop(k + 2) - H.SLAB - fl.YHigh >= 5 or k + 2 > 4).toBe(true)
			end
		end
	)

	test(
		"the rails stand inside the open lane: one along the room's edge, one at the drop over the flight's foot",
		function()
			for k = 1, 4 do
				local hole = H.lane(B, H.holeLane(k))
				local rails = H.rails(B, k)
				expect(inside(rails.Long, hole)).toBe(true)
				expect(inside(rails.End, hole)).toBe(true)
				expect(rails.Long.Z0).toBe(hole.Z0) -- the edge toward the landing
				local foot = H.flight(B, k - 1).XLow
				expect(math.abs((rails.End.X0 + rails.End.X1) / 2 - foot) < 0.5).toBe(true)
				expect(overlaps(rails.Long, rails.End)).toBe(false)
			end
		end
	)

	test(
		"the main ward's beds: the mattress puts each foot spot on Logic/Building.BED_FOOT_Z, inside the bed spot",
		function()
			local bed = H.BED
			local z = H.mattressZ(B)
			expect(z + bed.MattressLength / 2 + bed.FootStep).toBeCloseTo(B.BED_FOOT_Z, 5)
			expect(z - bed.MattressLength / 2 >= B.BED_Z0 + bed.HeadboardThick - 0.01).toBe(true) -- clear of the headboard
			expect(z + bed.MattressLength / 2 <= B.BED_Z1).toBe(true)
			expect(bed.Width).toBeCloseTo(B.BED_HALF * 2, 5)
			expect(bed.Headboard <= bed.Width and bed.Headboard % 1 == 0).toBe(true) -- whole studs across
			expect(bed.HeadboardHeight + 0.01 < H.DOOR).toBe(true)
		end
	)

	test("the hot tub: in the tower, off the shaft, the landing and the atrium; both spots in its water", function()
		local t = H.TUB
		local r = t.Diameter / 2
		local tub = rect(t.X - r, t.X + r, t.Z - r, t.Z + r)
		expect(inside(tub, rect(-B.HALF + B.WALL, B.HALF - B.WALL, B.TOWER_FRONT + B.WALL, B.ATRIUM.Z0))).toBe(true)
		expect(overlaps(tub, B.SHAFT)).toBe(false)
		expect(overlaps(tub, landingRect())).toBe(false)
		expect(#H.TUB_SPOTS).toBe(2)
		for _, spot in H.TUB_SPOTS do
			local d = math.sqrt((spot.X - t.X) ^ 2 + (spot.Z - t.Z) ^ 2)
			expect(d < r - 1).toBe(true)
		end
		local a, b = H.TUB_SPOTS[1], H.TUB_SPOTS[2]
		expect(math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2) >= 3).toBe(true) -- two soakers side by side
	end)

	test("a soaker's approach (Patients.shortOf from the landing) is outside the tub, a straight walk away", function()
		local t = H.TUB
		local r = t.Diameter / 2
		for _, spot in H.TUB_SPOTS do
			local x, z = H.tubApproach(spot.X, spot.Z, LANDING.X, LANDING.Z)
			expect(math.sqrt((x - t.X) ^ 2 + (z - t.Z) ^ 2) >= r + 1).toBe(true)
			expect(B.reach(LANDING, { X = x, Z = z }, 5, 2)).toBe(true)
			-- and the walk there never comes within the tub (its closest point to the tub's centre is the approach)
			local dx, dz = x - LANDING.X, z - LANDING.Z
			local along = ((t.X - LANDING.X) * dx + (t.Z - LANDING.Z) * dz) / (dx * dx + dz * dz)
			expect(along >= 1).toBe(true)
		end
		-- Patients.shortOf: 3 short, never past the start
		expect({ H.tubApproach(0, 0, 10, 0) }).toEqual({ 3, 0 })
		expect({ H.tubApproach(0, 0, 1, 0) }).toEqual({ 1, 0 })
		expect({ H.tubApproach(2, 2, 2, 2) }).toEqual({ 2, 2 })
	end)

	test("the Pharmacy, its bench, the helipad, the planters and the roof prop each have their own place", function()
		local p = H.PHARMACY
		local station = rect(p.X - p.Width / 2, p.X + p.Width / 2, p.Z - p.Depth / 2, p.Z + p.Depth / 2)
		local tower = rect(-B.HALF + B.WALL, B.HALF - B.WALL, B.TOWER_FRONT + B.WALL, B.BACK - B.WALL)
		local shelf = rect(B.ATRIUM.X0, B.ATRIUM.X1, B.ATRIUM.Z0, B.ATRIUM.Z0 + H.SHELF.Thick)
		local bench = rect(H.BENCH.X0, H.BENCH.X1, H.BENCH.Z0, H.BENCH.Z1)
		for _, r in { station, bench } do
			expect(inside(r, tower)).toBe(true)
			for _, other in { B.SHAFT, landingRect(), B.ATRIUM, shelf } do
				expect(overlaps(r, other)).toBe(false)
			end
		end
		expect(overlaps(station, bench)).toBe(false)
		-- the station is held from its street side, on the open floor
		expect(station.Z0 - 1.5 > tower.Z0).toBe(true)
		local pad = H.PAD
		local padRect =
			rect(pad.X - pad.Diameter / 2, pad.X + pad.Diameter / 2, pad.Z - pad.Diameter / 2, pad.Z + pad.Diameter / 2)
		expect(pad.Diameter >= 6.5).toBe(true)
		expect(inside(padRect, tower)).toBe(true)
		for _, other in { B.SHAFT, landingRect(), B.ATRIUM } do
			expect(overlaps(padRect, other)).toBe(false)
		end
		local s = H.PLANTER / 2
		local spots = {}
		for _, at in H.PLANTERS do
			table.insert(spots, rect(at.X - s, at.X + s, at.Z - s, at.Z + s))
		end
		local prop = H.PROP.Tower
		table.insert(spots, rect(prop.X - 1.5, prop.X + 1.5, prop.Z - 1.5, prop.Z + 1.5))
		for i, r in spots do
			expect(inside(r, tower)).toBe(true)
			expect(overlaps(r, padRect)).toBe(false)
			expect(overlaps(r, B.ATRIUM)).toBe(false)
			for j, other in spots do
				if i < j then
					expect(overlaps(r, other)).toBe(false)
				end
			end
		end
	end)

	test(
		"the shaft: up under the top roof at Lv 2-4, past the car at the roof at Lv 5; the car fits a storey",
		function()
			expect(H.shaftTop(B, 1, ROOF)).toBeCloseTo(23 - H.SLAB, 5)
			expect(H.shaftTop(B, 2, ROOF)).toBeCloseTo(34 - H.SLAB, 5)
			expect(H.shaftTop(B, 3, ROOF)).toBeCloseTo(45 - H.SLAB, 5)
			expect(H.shaftTop(B, 4, ROOF)).toBeCloseTo(45 + H.CAR + H.CLEAR, 5)
			expect(H.CAR < B.STOREY - H.SLAB).toBe(true)
			expect(H.CAR >= 6.5 + 1).toBe(true) -- the biggest creature (6.5 tall) rides inside with a stud to spare
			expect(H.roofTop(B, 1)).toBe(23)
			expect(H.wallTop(B, 0)).toBeCloseTo(11.4, 5)
			expect(H.wallTop(B, 3)).toBeCloseTo(44.4, 5)
			expect(H.SLAB <= B.SLAB_MAX).toBe(true)
		end
	)

	test("walls leave their doorways open", function()
		expect(H.segments(-12.4, 12.4, { B.DOORS.LiftLobby, B.DOORS.AE, { Z0 = -3, Z1 = 2 } })).toEqual({
			{ Z0 = -12.4, Z1 = -7 },
			{ Z0 = 6, Z1 = 12.4 },
		})
		expect(H.segments(-12.4, 2.4, { B.DOORS.Side })).toEqual({ { Z0 = -12.4, Z1 = -1 } })
		expect(H.segments(0, 5, {})).toEqual({ { Z0 = 0, Z1 = 5 } })
	end)

	test("sleepers spread out; a theme's colour is capped at 240 a channel", function()
		expect(H.sleepers(4, 2)).toEqual({ [1] = true, [3] = true })
		expect(H.sleepers(1, 1)).toEqual({ [1] = true })
		expect(H.sleepers(4, 0)).toEqual({})
		expect(H.sleepers(2, 9)).toEqual({ [1] = true, [2] = true })
		expect({ H.tame(255, 255, 255) }).toEqual({ 240, 240, 240 })
		expect({ H.tame(10, 20, 30) }).toEqual({ 10, 20, 30 })
		local r, g, b = H.tame(255, 0, 127.5)
		expect(r).toBeCloseTo(240, 5)
		expect(b).toBeCloseTo(120, 5)
		expect(g).toBe(0)
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- The lift's rules (unchanged by the overhaul) and the stations
------------------------------------------------------------------------------------------------------------------

T.describe("Hospital (lift rules)", function()
	test("which floors exist per level (Data/Levels Floors)", function()
		local got = {}
		for level = 1, 5 do
			got[level] = Lift.floors(LevelsData[level].Floors)
		end
		expect(got).toEqual({ { 0 }, { 0, 1 }, { 0, 1, 2 }, { 0, 1, 2, 3 }, { 0, 1, 2, 3, 4 } })
		expect(Lift.exists(4, LevelsData[5].Floors)).toBe(true)
		expect(Lift.exists(5, LevelsData[5].Floors)).toBe(false)
		expect(Lift.exists(1, LevelsData[1].Floors)).toBe(false)
		expect(Lift.exists(-1, 4)).toBe(false)
		expect(Lift.exists(1.5, 4)).toBe(false)
		expect(Lift.exists(0 / 0, 4)).toBe(false)
		expect(Lift.exists("1", 4)).toBe(false)
	end)

	test("a floor must be a whole, finite number", function()
		expect(Lift.whole(2)).toBe(2)
		expect(Lift.whole(2.5)).toBeNil()
		expect(Lift.whole(math.huge)).toBeNil()
		expect(Lift.whole(0 / 0)).toBeNil()
		expect(Lift.whole("2")).toBeNil()
		expect(Lift.whole(nil)).toBeNil()
	end)

	test("ride seconds: Config.Lift.RideSeconds x Express Lift (2 s -> 0.8 s at 3 ranks), never below 20%", function()
		expect(Lift.rideSeconds(Config.Lift.RideSeconds, 1)).toBe(2)
		expect(
			Lift.rideSeconds(Config.Lift.RideSeconds, Rebirth.effects({ Rebirth = { Tree = {} } }, Config, {}, {}).Lift)
		).toBe(2)
		expect(Lift.rideSeconds(2, 0.4)).toBeCloseTo(0.8, 5)
		expect(Lift.rideSeconds(2, 0)).toBeCloseTo(0.4, 5)
		expect(Lift.rideSeconds(2, 5)).toBe(2)
		expect(Lift.rideSeconds(-1, 1)).toBe(2)
		expect(Lift.rideSeconds(2, 0 / 0)).toBe(2)
	end)

	test("the landing you stand at: near across the floor, on that floor's height, the nearest wins", function()
		local landings = {}
		for k = 0, 4 do
			table.insert(landings, { Floor = k, X = LANDING.X, Y = B.slabTop(k), Z = LANDING.Z })
		end
		local reach = Config.Lift.CarDistance + Lift.REACH_SLACK
		-- A rider's root stands ~3 over the floor.
		expect(Lift.nearest(landings, LANDING.X + 1, 0 + 3, LANDING.Z, reach).Floor).toBe(0)
		expect(Lift.nearest(landings, LANDING.X + 1, B.slabTop(2) + 3, LANDING.Z, reach).Floor).toBe(2)
		expect(Lift.nearest(landings, LANDING.X, B.slabTop(4) + 3, LANDING.Z, reach).Floor).toBe(4)
		expect(Lift.nearest(landings, LANDING.X + reach + 1, 3, LANDING.Z, reach)).toBeNil() -- from the street
		expect(Lift.nearest(landings, LANDING.X, -5, LANDING.Z, reach)).toBeNil()
		-- Between two floors (a jump off a slab): never counted as a storey it isn't on.
		expect(Lift.ABOVE < B.STOREY).toBe(true)
	end)

	test("riders are set down side by side", function()
		expect({ Lift.spread(1), Lift.spread(2), Lift.spread(3), Lift.spread(4) }).toEqual({ 0, 2.8, -2.8, 5.6 })
		-- UI/LiftPanel steps patients and porters out where Server/Lift sets them down
		for index = 1, 6 do
			expect(Panel.spread(index)).toBe(Lift.spread(index))
		end
		-- inside the car they stand side by side, never past its walls
		expect(Panel.inCar(1, 2)).toBe(0)
		expect(Panel.inCar(2, 2) > 0 and Panel.inCar(3, 2) < 0).toBe(true)
		for index = 1, 6 do
			expect(math.abs(Panel.inCar(index, 2)) <= 2).toBe(true)
		end
		expect(Panel.inCar(4, -1)).toBe(0)
		-- The landing stays turned toward the lift, so the side-by-side spread runs along +x: the second rider (an
		-- escort) lands inside the building, never past the -x wall 2 studs from the landing's centre.
		expect(LANDING.X + Lift.spread(2) < B.HALF - B.WALL).toBe(true)
		expect(LANDING.X + Lift.spread(2) > -B.HALF + B.WALL).toBe(true)
	end)

	test("the ride attributes: Server/Lift writes what UI/LiftPanel reads", function()
		local mine = Panel.decodeRide(Lift.encodeRide(0, 3, 2, 1234.5678, 2), true)
		expect(mine).toEqual({ Plot = 2, From = 0, To = 3, Seconds = 2, At = 1234.568 })
		local car = Panel.decodeRide(Lift.encodeRide(4, 0, 0.8, 99), false)
		expect(car).toEqual({ From = 4, To = 0, Seconds = 0.8, At = 99 })
		expect(Panel.decodeRide("1,2,3", false)).toBeNil()
		expect(Panel.decodeRide("a,b,c,d", false)).toBeNil()
		expect(Panel.decodeRide("0,1.5,2,9", false)).toBeNil()
		expect(Panel.decodeRide("0,1,-2,9", false)).toBeNil()
		expect(Panel.decodeRide(nil, true)).toBeNil()
		expect(Panel.remaining(2, 100, 100.5)).toBeCloseTo(1.5, 5)
		expect(Panel.remaining(2, 100, 200)).toBeCloseTo(0.15, 5)
	end)

	test("the floor picker: this building's floors only, top first, icons from Data/Departments", function()
		local texts = {}
		for _, button in Panel.buttons(LevelsData[5].Floors, 0, Departments) do
			table.insert(texts, button.Text)
		end
		expect(texts).toEqual({ "🚁 R", "💊 3", "🛁 2", "🛏️ 1", "🛎️ G" })
		local lv2 = Panel.buttons(LevelsData[2].Floors, 1, Departments)
		expect(#lv2).toBe(2)
		expect(lv2[1].Here).toBe(true)
		expect(lv2[2].Here).toBe(false)
		for _, button in Panel.buttons(4, nil, Departments) do
			local words = 0
			for _ in string.gmatch(button.Text, "%S+") do
				words += 1
			end
			expect(words <= 6).toBe(true)
		end
	end)
end)

T.describe("Hospital (stations)", function()
	local function has(count, id)
		return Rebirth.has(count, id)
	end

	test("hold factors: team x ability rush, never under Config.BoostMinMakeSeconds, never longer", function()
		local floor = Config.BoostMinMakeSeconds
		expect(Stations.holdSeconds(2, 1, 1, floor)).toBe(2)
		expect(Stations.holdSeconds(2, 0.6, 1, floor)).toBeCloseTo(1.2, 5) -- a Hydro/Pharmacy team of 3 (40%)
		expect(Stations.holdSeconds(2, 0.6, 0.5, floor)).toBeCloseTo(0.6, 5) -- + Busy Paws
		expect(Stations.holdSeconds(2, 1, 0, floor)).toBe(floor) -- Time Bubble: the shortest hold
		expect(Stations.holdSeconds(0.2, 1, 1, floor)).toBe(0.2) -- already under the floor: unchanged
		expect(Stations.holdSeconds(2, 1.5, 3, floor)).toBe(2) -- never slower than base
		expect(Stations.holdSeconds(2, 0 / 0, -1, floor)).toBe(2) -- junk factors change nothing
		expect(Stations.holdSeconds(-1, 1, 1, floor)).toBe(floor)
	end)

	test("the Pharmacy's tier follows the owner's branches (Pharmacy2 at R2)", function()
		expect(Stations.pharmacyTier(0, has)).toBe(1)
		expect(Stations.pharmacyTier(1, has)).toBe(1)
		expect(Stations.pharmacyTier(2, has)).toBe(2)
		expect(Stations.pharmacyTier("x", has)).toBe(1)
	end)

	test("the craft check: two carried ingredients make one medicine (tier 2 from R2)", function()
		local made, taken = Stations.pharmacy({ "Potion", "Cocoa" }, Items, 1, Recipe.craft)
		expect(made).toBe("WarmTonic")
		expect(taken).toEqual({ "Potion", "Cocoa" })
		made, taken = Stations.pharmacy({ "Cocoa", "Bubbles", "Plaster" }, Items, 1, Recipe.craft)
		expect(made).toBe("SoapyPatch")
		expect(taken).toEqual({ "Bubbles", "Plaster" })
		expect((Stations.pharmacy({ "Potion", "Plaster" }, Items, 1, Recipe.craft))).toBeNil() -- SuperSyrup is tier 2
		expect((Stations.pharmacy({ "Potion", "Plaster" }, Items, 2, Recipe.craft))).toBe("SuperSyrup")
		expect((Stations.pharmacy({ "Potion" }, Items, 2, Recipe.craft))).toBeNil()
		expect((Stations.pharmacy({ "Potion", "Potion" }, Items, 2, Recipe.craft))).toBeNil()
		expect((Stations.pharmacy({}, Items, 2, Recipe.craft))).toBeNil()
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- The cutaway's rules (Feel/Cutaway)
------------------------------------------------------------------------------------------------------------------

T.describe("Hospital (cutaway)", function()
	test("floorOf: the highest slab at or just under the feet; only the building's own floors count", function()
		local tops = B.SLAB_TOPS
		local got = {}
		for _, y in { 0, 5, 11.4, 11.5, 12, 18, 22.6, 23, 34, 44.6, 45, 60 } do
			table.insert(got, Cut.floorOf(y, tops))
		end
		expect(got).toEqual({ 0, 0, 0, 1, 1, 1, 2, 2, 3, 4, 4, 4 })
		expect(Cut.tops(tops, 2)).toEqual({ 12, 23 })
		expect(Cut.tops(tops, 0)).toEqual({})
		expect(Cut.tops(tops, 9)).toEqual({ 12, 23, 34, 45 })
		expect(Cut.floorOf(34, Cut.tops(tops, 2))).toBe(2) -- on a Lv 3 roof: still the top floor
	end)

	test("hide: on the ground nothing changes; above, everything over you hides and your outer walls fade", function()
		for storey = 0, 4 do
			expect(Cut.hide(0, storey, true)).toBe(0)
			expect(Cut.hide(0, storey, false)).toBe(0)
		end
		expect(Cut.hide(1, 2, false)).toBe(1)
		expect(Cut.hide(1, 4, true)).toBe(1)
		expect(Cut.hide(1, 1, true)).toBe(Cut.FADE)
		expect(Cut.hide(1, 1, false)).toBe(0)
		expect(Cut.hide(2, 1, true)).toBe(0)
		expect(Cut.hide(2, 0, false)).toBe(0)
		expect(Cut.hide(4, 4, true)).toBe(Cut.FADE)
		-- the camera's Popper ignores a part at 0.25 total transparency or more (hospital doc §3.7)
		expect(Cut.FADE >= 0.25).toBe(true)
		expect(Cut.CHECKS_PER_SECOND).toBe(4)
		expect(Cut.IDLE_SECONDS >= 1).toBe(true)
	end)

	test("feet: R15 stands HipHeight under its root; R6 on 2-stud legs; the footprint counts a doorway in", function()
		expect(Cut.feet(14, 1, 2)).toBe(11)
		expect(Cut.feet(14, 1, 0)).toBe(11)
		local podium = B.footprint(1, 0)
		expect(Cut.inside(0, 0, podium, 0)).toBe(true)
		expect(Cut.inside(-B.HALF - 0.3, 0, podium, Cut.MARGIN)).toBe(true)
		expect(Cut.inside(-17.5, 0, podium, Cut.MARGIN)).toBe(false) -- the walkway (Patients: x = ±17.5) is outside
		expect(Cut.inside(0, 5, podium, Cut.MARGIN)).toBe(false)
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- The real PlotBuilder under tests/worldmock (Lune's roblox datatypes; Instances are plain tables)
------------------------------------------------------------------------------------------------------------------

local world = require("./worldmock").new()
local loadModule = world.load
local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local Palette = loadModule("src/shared/Palette.luau")
local WORLD = Palette.World

T.describe("Hospital (the built world)", function()
	local PlotBuilder = loadModule("src/server/PlotBuilder.luau")
	local plot = PlotBuilder.buildTown()[1]
	for _, roomId in { "BathRoom", "Ward", "WinterWing", "Garden" } do
		PlotBuilder.placeRoom(plot, roomId)
	end
	local pivot = plot:GetPivot()
	local accent = plot:GetAttribute("Accent")

	local function build(level: number, theme: string?)
		return PlotBuilder.buildBuilding(plot, level, nil, theme or "Candy")
	end

	-- A part's box in plot-local studs, as a rect plus its y range.
	local function boxOf(p)
		local lo, hi = world.box(p, pivot)
		return rect(lo.X, hi.X, lo.Z, hi.Z), lo.Y, hi.Y
	end

	local function storeyOf(p, building): number?
		local node = p
		while node and node ~= building do
			local s = node:GetAttribute("Storey")
			if s ~= nil then
				return s
			end
			node = node.Parent
		end
		return nil
	end

	local function solid(p): boolean
		return p.CanCollide ~= false
	end

	-- The building's solid parts at walking height on floor k (feet to head), with their boxes.
	local function solidsOn(building, k: number)
		local out = {}
		local y = B.slabTop(k)
		for _, p in world.parts(building) do
			if solid(p) then
				local r, lo, hi = boxOf(p)
				if hi > y + 0.2 and lo < y + 5 then
					table.insert(out, { Part = p, Rect = r })
				end
			end
		end
		return out
	end

	-- "Plot_1.Building.Podium.WallFascia" (the mock has no GetFullName).
	local function fullName(p): string
		local names = {}
		local node = p
		while node and node ~= plot.Parent do
			table.insert(names, 1, node.Name)
			node = node.Parent
		end
		return table.concat(names, ".")
	end

	local function seeThrough(p): boolean
		return p.Transparency > 0 and p.Transparency < 1
	end

	test(
		"the contract's names: floors, landings with both prompts, the lift, stairs, departments, attributes",
		function()
			for level = 1, 5 do
				local building = PlotBuilder.buildBuilding(plot, level, level - 1, "Candy")
				local floors = LevelsData[level].Floors
				expect(building.Name).toBe("Building")
				expect(building:GetAttribute("Floors")).toBe(floors)
				expect(building:GetAttribute("Theme")).toBe("Candy")
				expect(building:GetAttribute("Level")).toBe(level)
				expect(building:GetAttribute("GrewFrom")).toBe(level - 1)
				expect(plot:GetAttribute("Theme")).toBe("Candy")
				expect(plot:GetAttribute("Level")).toBe(level)
				expect(building:GetAttribute("Origin")).toEqual(pivot)
				expect(building.Podium ~= nil).toBe(true)
				for _, child in building:GetChildren() do
					expect(child:GetAttribute("Since") ~= nil).toBe(true)
					expect(child:GetAttribute("Storey") ~= nil).toBe(true)
				end
				if floors > 0 then
					expect(building.Landing_0:GetAttribute("Floor")).toBe(0)
					expect(building.Landing_0.PromptPoint.LiftPrompt.ActionText).toBe("Lift")
					for k = 1, floors do
						local floorModel = building:FindFirstChild("Floor_" .. k)
						expect(floorModel.Slab.CanCollide).toBe(true)
						expect(floorModel.Landing:GetAttribute("Floor")).toBe(k)
						local point = floorModel.Landing.PromptPoint
						expect(point.LiftPrompt.ActionText).toBe("Lift")
						expect(point.LiftPrompt.ObjectText).toBe("🛗")
						expect(point.EscortPrompt.Enabled).toBe(false)
						expect(point.LiftPrompt:HasTag("LiftPrompt")).toBe(true)
						expect(point.EscortPrompt:HasTag("EscortPrompt")).toBe(true)
					end
					expect(building:FindFirstChild("Floor_" .. (floors + 1))).toBeNil()
					expect(building.Lift.Car.CanCollide).toBe(false)
					expect(building.Lift.Car.DoorsGui.DoorL ~= nil and building.Lift.Car.DoorsGui.DoorR ~= nil).toBe(
						true
					)
					expect(building.Lift.Shaft.CanCollide).toBe(true) -- solid now: it is the wall at its corner
					expect(building.Lift:HasTag("HospitalLift")).toBe(true)
					expect(building.Lift:GetAttribute("Ride")).toBe("")
					expect(building.Stairs:FindFirstChild("Flight_" .. (floors - 1)).CanCollide).toBe(true)
					expect(building.Stairs:FindFirstChild("Flight_" .. floors)).toBeNil()
					expect(building.AmbulanceBay.Ambulance:GetAttribute("ArriveAt")).toBe(0)
					expect(building.AmbulanceBay.Ambulance.StretcherSpot ~= nil).toBe(true)
					for i = 1, LevelsData[level].Beds - 1 do
						local spot = building.Wards:FindFirstChild("BedSpot_" .. i)
						expect(spot:GetAttribute("Floor")).toBe(1)
						expect(spot:FindFirstChild("Bed_" .. i):GetAttribute("Floor")).toBe(1)
					end
					expect(building.Wards:FindFirstChild("BedSpot_" .. LevelsData[level].Beds)).toBeNil()
				else
					expect(building:FindFirstChild("Landing_0")).toBeNil()
					expect(building:FindFirstChild("Lift")).toBeNil()
					expect(building.PodiumShell ~= nil).toBe(true)
				end
				expect(building:FindFirstChild("Hydro") ~= nil).toBe(level >= 3)
				expect(building:FindFirstChild("Pharmacy") ~= nil).toBe(level >= 4)
				expect(building:FindFirstChild("Roof") ~= nil).toBe(level >= 5)
				expect(building:FindFirstChild("Tower") ~= nil).toBe(level >= 5)
				expect(building:FindFirstChild("Terrace") ~= nil).toBe(level >= 3)
			end
			local building = plot.Building
			expect(building.Hydro.HotTub.TubSpot_2:GetAttribute("Floor")).toBe(2)
			expect(building.Hydro.HotTub.Tub.SoakPoint.SoakPrompt.Enabled).toBe(false)
			expect(building.Hydro.HotTub.Tub.SoakPoint.SoakPrompt:HasTag("SoakPrompt")).toBe(true)
			expect(building.Pharmacy.Station_Pharmacy.PrimaryPart ~= nil).toBe(true)
			expect(building.Pharmacy.Station_Pharmacy:HasTag("BuildingStation")).toBe(true)
			expect(building.Roof.HeliSpot:GetAttribute("ArriveAt")).toBe(0)
			expect(plot.MascotSpot ~= nil).toBe(true)
			expect(plot.Sign.SignGui.BranchBadge.Visible).toBe(false)
		end
	)

	test(
		"budgets at every level and theme: parts, SurfaceGuis, see-through parts; no Texture, Decal, cross or Highlight",
		function()
			local lines = {}
			local worst = 0
			for _, theme in Themes.Order do
				for level = 1, 5 do
					local building = build(level, theme)
					local parts, guis, glass = 0, 0, 0
					for _, d in building:GetDescendants() do
						if d:IsA("BasePart") then
							parts += 1
							if seeThrough(d) then
								glass += 1
							end
							expect(string.find(string.lower(d.Name), "cross") == nil).toBe(true)
						elseif d.ClassName == "SurfaceGui" then
							guis += 1
							expect(type(d.MaxDistance) == "number" and d.MaxDistance > 0).toBe(true)
						elseif d.ClassName == "Texture" or d.ClassName == "Decal" or d.ClassName == "Highlight" then
							error(string.format("Lv %d %s: a %s (%s)", level, theme, d.ClassName, fullName(d)))
						elseif d:IsA("Light") then
							expect(d.Shadows).toBe(false)
						end
						expect(string.find(string.lower(d.Name), "cross") == nil).toBe(true)
					end
					if parts > Config.Look.BuildingParts then
						error(
							string.format(
								"Lv %d %s: %d parts (Config.Look.BuildingParts %d)",
								level,
								theme,
								parts,
								Config.Look.BuildingParts
							)
						)
					end
					if guis > Config.Look.SurfaceGuisPerBuilding then
						error(string.format("Lv %d %s: %d SurfaceGuis", level, theme, guis))
					end
					if glass > Config.Look.GlassPerBuilding then
						error(string.format("Lv %d %s: %d see-through parts", level, theme, glass))
					end
					worst = math.max(worst, parts)
					if theme == Themes.Default or level == 5 then
						table.insert(
							lines,
							string.format(
								"    [building] Lv %d %s: %d parts · %d SurfaceGuis · %d see-through",
								level,
								theme,
								parts,
								guis,
								glass
							)
						)
					end
				end
			end
			print(table.concat(lines, "\n"))
			print(
				string.format(
					"    [building] the heaviest (any level, any theme): %d / %d",
					worst,
					Config.Look.BuildingParts
				)
			)
		end
	)

	test(
		"slabs: on Logic/Building's tops, at most 0.6 thick, F1's underside >= 10.4; each landing rests on its Slab",
		function()
			local building = build(5)
			for k = 1, 4 do
				local floorModel = building:FindFirstChild("Floor_" .. k)
				local slabs = 0
				for _, p in floorModel:GetChildren() do
					if string.match(p.Name, "^Slab") then
						slabs += 1
						local _, lo, hi = boxOf(p)
						expect(hi).toBeCloseTo(B.slabTop(k), 4)
						expect(hi - lo <= B.SLAB_MAX + 1e-6).toBe(true)
						expect(lo >= 10.4 - 1e-6).toBe(true)
						expect(p.CanCollide).toBe(true)
					end
				end
				expect(slabs).toBe(#H.slabRects(B, k))
				local landing, lo = boxOf(floorModel.Landing)
				local slab = boxOf(floorModel.Slab)
				expect(lo).toBeCloseTo(B.slabTop(k), 4)
				expect(inside(landing, slab)).toBe(true)
			end
			local _, lo0 = boxOf(building.Landing_0)
			expect(lo0).toBeCloseTo(0, 4)
		end
	)

	test(
		"every part has a Storey; outer walls are studded, the plot's colour and solid; roofs are World.Roof",
		function()
			for level = 1, 5 do
				local building = build(level)
				local walls = 0
				for _, p in world.parts(building) do
					local storey = storeyOf(p, building)
					if storey == nil then
						error(string.format("Lv %d: %s has no Storey", level, fullName(p)))
					end
					expect(storey >= 0 and storey <= 4).toBe(true)
					if string.match(p.Name, "^Wall") and p:GetAttribute("Outer") == true then
						walls += 1
						expect(p:GetAttribute("Studded")).toBe(true)
						expect(p.Material).toBe(roblox.Enum.Material.Plastic)
						expect(p.Color).toEqual(accent)
						expect(p.CanCollide).toBe(true)
					end
					if string.match(p.Name, "^Roof") or string.match(p.Name, "^Parapet") then
						expect(p.Color).toEqual(WORLD.Roof)
					end
					-- no bleached world colour (art-direction §4.1: warm whites cap at 240)
					if p.Transparency < 1 then
						expect(Look.maxChannel(p.Color) <= 245).toBe(true)
					end
				end
				expect(walls >= 5).toBe(true)
			end
		end
	)

	test(
		"the Lv 1 podium: studded walls, the fascia's name, the stripe, a dark roof, the canopy, 2 beds, no lift",
		function()
			local building = build(1)
			local podium = building.Podium
			expect(podium.WallFascia.NameGui.Text.Text).toBe(LevelsData[1].Name)
			expect(podium.WallFascia.NameGui:FindFirstChild("Plate")).toBeNil() -- floating letters, no board
			expect(podium.BandFascia:GetAttribute("Paint")).toBe("Band")
			expect(podium.RoofCanopy.CanCollide).toBe(false)
			local canopy, lo, hi = boxOf(podium.RoofCanopy)
			expect(inside(canopy, rect(B.CANOPY.X0, B.CANOPY.X1, B.CANOPY.Z0, B.CANOPY.Z1))).toBe(true)
			expect((lo + hi) / 2).toBeCloseTo(B.CANOPY.Y, 4)
			local _, roofLo, roofHi = boxOf(building.PodiumShell.RoofPodium)
			expect(roofHi).toBeCloseTo(B.GROUND, 4)
			expect(roofLo >= 10.4 - 1e-6).toBe(true)
			expect(building.PodiumShell.RoofPodium:GetAttribute("Storey")).toBe(1)
			-- the made-up bed with its sleeper, clear of the side door and decor slot 1
			local bed = building.PodiumShell.Dressing.DressBed_1
			local r = boxOf(bed.Base)
			expect(inside(r, B.LV1_DRESSING)).toBe(true)
			expect(r.Z0 >= B.STAND.Decor[1].Z + H.DECOR_HALF).toBe(true)
			expect(bed.Sleeper.Head.CanCollide).toBe(false)
			expect(bed.Sleeper.Head.SleepGui.MaxDistance).toBe(60)
		end
	)

	test("the wards look full: Lv 1 shows 2 beds, the Wards floor Config.Look.WardFloorBeds (7) at Lv 2-5", function()
		local function count(level)
			local building = build(level)
			local beds, dressing, sleepers = 0, 0, 0
			for _, holder in { plot.Rooms.Room_Stand, building } do -- the Stand's Bed_1 and the building's
				for _, d in holder:GetDescendants() do
					if d:IsA("BasePart") and string.match(d.Name, "^Bed_%d+$") then
						beds += 1
					elseif d.Name == "Sleeper" then
						sleepers += 1
					elseif string.match(d.Name, "^DressBed_%d+$") then
						dressing += 1
					end
				end
			end
			return beds, dressing, sleepers, building
		end
		local beds, dressing, sleepers = count(1)
		expect(beds + dressing).toBe(Config.Look.Lv1Beds)
		expect(sleepers).toBe(Config.Look.Sleepers.Lv1)
		for level = 2, 5 do
			local _, made, asleep, building = count(level)
			local onFloor = made
			for _, d in building.Wards:GetDescendants() do
				if d:IsA("BasePart") and string.match(d.Name, "^Bed_%d+$") then
					onFloor += 1
				end
			end
			expect(onFloor).toBe(Config.Look.WardFloorBeds)
			expect(asleep).toBe(Config.Look.Sleepers.Ward)
			-- every bed on the Wards floor stands on F1
			for _, d in building.Wards:GetDescendants() do
				if d:IsA("BasePart") and (d.Name == "Base" or string.match(d.Name, "^Bed_")) then
					local _, lo = boxOf(d)
					expect(lo >= B.slabTop(1) - 0.01).toBe(true)
				end
			end
		end
	end)

	test("made-up beds and sleepers never carry a bed's name, and sleepers never move or collide", function()
		for level = 1, 5 do
			local building = build(level)
			for _, d in building:GetDescendants() do
				local made = d:FindFirstAncestor("Dressing")
				if made then
					expect(string.match(d.Name, "^Bed_%d+$")).toBeNil()
					expect(string.match(d.Name, "^BedSpot_")).toBeNil()
				end
				if d:IsA("BasePart") and d:FindFirstAncestor("Sleeper") then
					expect(d.CanCollide).toBe(false)
					expect(d.CanQuery).toBe(false)
					expect(d.CastShadow).toBe(false)
					expect(d:HasTag("CreatureMotion")).toBe(false)
				end
			end
		end
	end)

	test("upstairs: each functional bed's foot is a straight walk from Floor_1.Landing, past nothing solid", function()
		for level = 2, 5 do
			local building = build(level)
			local solids = solidsOn(building, 1)
			local beds = 0
			for _, bed in building.Wards:GetDescendants() do
				if bed:IsA("BasePart") and string.match(bed.Name, "^Bed_%d+$") then
					beds += 1
					-- Server/Patients.bedFoot: 1.6 past the mattress's -Z end
					local foot =
						pivot:PointToObjectSpace((bed.CFrame * CFrame.new(0, 0, -bed.Size.Z / 2 - 1.6)).Position)
					expect(foot.Z).toBeCloseTo(B.BED_FOOT_Z, 3)
					expect(inside(rect(foot.X, foot.X, foot.Z, foot.Z), boxOf(building.Floor_1.Slab))).toBe(true)
					for _, s in solids do
						if crosses(LANDING, { X = foot.X, Z = foot.Z }, s.Rect, B.SKIM) then
							error(
								string.format(
									"Lv %d: %s's foot: the walk crosses %s",
									level,
									bed.Name,
									fullName(s.Part)
								)
							)
						end
					end
				end
			end
			expect(beds).toBe(LevelsData[level].Beds - 1)
		end
	end)

	test("Hydro: each soaker's approach is a straight walk from Floor_2.Landing, outside the tub", function()
		for level = 3, 5 do
			local building = build(level)
			local solids = solidsOn(building, 2)
			for i = 1, 2 do
				local spot = pivot:PointToObjectSpace(building.Hydro.HotTub:FindFirstChild("TubSpot_" .. i).Position)
				local x, z = H.tubApproach(spot.X, spot.Z, LANDING.X, LANDING.Z)
				for _, s in solids do
					if crosses(LANDING, { X = x, Z = z }, s.Rect, 0) then
						error(string.format("Lv %d: TubSpot_%d's approach crosses %s", level, i, fullName(s.Part)))
					end
				end
			end
		end
	end)

	test(
		"everything solid on the ground and the Wards floor is inside Logic/Building.obstacles (reach tells the truth)",
		function()
			local bad = {}
			for level = 1, 5 do
				local building = build(level)
				for k = 0, math.min(1, LevelsData[level].Floors) do
					local obstacles = B.obstacles(level, k)
					local f = B.footprint(level, k)
					local y = B.slabTop(k)
					for _, p in world.parts(building) do
						if solid(p) then
							local r, lo, hi = boxOf(p)
							-- at walking height on this floor, inside the footprint (the canopies, bay and lintels are not)
							if hi > y + 0.7 and lo < y + H.DOOR - 0.1 and inside(r, f) then
								local step = 0.25
								local x = r.X0 + 0.05
								local covered = true
								while covered and x <= r.X1 - 0.05 + 1e-9 do
									local z = r.Z0 + 0.05
									while covered and z <= r.Z1 - 0.05 + 1e-9 do
										local found = false
										for _, o in obstacles do
											if
												x >= o.X0 - 0.06
												and x <= o.X1 + 0.06
												and z >= o.Z0 - 0.06
												and z <= o.Z1 + 0.06
											then
												found = true
												break
											end
										end
										covered = found
										z += step
									end
									x += step
								end
								if not covered then
									table.insert(bad, string.format("Lv %d floor %d: %s", level, k, fullName(p)))
								end
							end
						end
					end
				end
			end
			expect(bad).toEqual({})
		end
	)

	test("stairs: each flight's wedge runs from its floor's top up to the next, in its own lane", function()
		local building = build(5)
		for k = 0, 3 do
			local flight = building.Stairs:FindFirstChild("Flight_" .. k)
			local fl = H.flight(B, k)
			local s = flight.Size
			local high = pivot:PointToObjectSpace((flight.CFrame * CFrame.new(0, s.Y / 2, s.Z / 2)).Position)
			local low = pivot:PointToObjectSpace((flight.CFrame * CFrame.new(0, -s.Y / 2, -s.Z / 2)).Position)
			expect(high.X).toBeCloseTo(fl.XHigh, 3)
			expect(high.Y).toBeCloseTo(fl.YHigh, 3)
			expect(low.X).toBeCloseTo(fl.XLow, 3)
			expect(low.Y).toBeCloseTo(fl.YLow, 3)
			expect(high.Z).toBeCloseTo((fl.Z0 + fl.Z1) / 2, 3)
			expect(flight:GetAttribute("Storey")).toBe(k)
		end
	end)

	test(
		"roomy (Joshua, 2026-11-17: 'cramped'): 2.5+ studs between the Wards' bed frames, headroom over a sitting creature",
		function()
			for level = 2, 5 do
				local building = build(level)
				-- every bed frame on the Wards floor (a functional bed's Frame, a made-up bed's Base), by ward row
				local rows = {}
				for _, d in building.Wards:GetDescendants() do
					if d:IsA("BasePart") and (d.Name == "Frame" or d.Name == "Base") then
						local r = boxOf(d)
						local row = if r.Z1 <= B.PARTITION_Z then "front" else "main"
						rows[row] = rows[row] or {}
						table.insert(rows[row], r)
					end
				end
				for name, frames in rows do
					table.sort(frames, function(a, b)
						return a.X0 < b.X0
					end)
					for i = 2, #frames do
						local gap = frames[i].X0 - frames[i - 1].X1
						if gap < 2.5 then
							error(string.format("Lv %d %s ward: %.2f studs between two bed frames", level, name, gap))
						end
					end
				end
				expect(#rows.front).toBe(#B.FRONT_WARD.Xs)
				expect(#rows.main).toBe(#B.WARD_BEDS)
				-- a 6.5-stud creature sitting on a mattress keeps 1.5+ studs under the ceiling (the roof at Lv 2)
				local ceiling = B.slabTop(2) - H.SLAB
				for _, d in building.Wards:GetDescendants() do
					if d:IsA("BasePart") and string.match(d.Name, "^Bed_%d+$") then
						local _, _, top = boxOf(d)
						expect(ceiling - (top + 6.5) >= 1.5).toBe(true)
					end
				end
				-- the lift car: the biggest creature stands inside with a stud over its head
				expect(building.Lift.Car.Size.Y >= 6.5 + 1).toBe(true)
			end
			-- the stairs: no flight steeper than 1 in 2, and a landing of 3+ studs at each lane end inside the walls
			local building = build(5)
			for k = 0, 3 do
				local s = building.Stairs:FindFirstChild("Flight_" .. k).Size
				expect(s.Y / s.Z <= 0.5 + 1e-6).toBe(true)
			end
			expect(B.ATRIUM.X0 - (-B.HALF + B.WALL) >= 3).toBe(true)
			expect(B.HALF - B.WALL - B.ATRIUM.X1 >= 3).toBe(true)
		end
	)

	test(
		"night: the glass and ribbon windows are Windows, the neon paw-heart and the beacon Lamps, one light",
		function()
			local building = build(5)
			local lights = 0
			for _, d in building:GetDescendants() do
				if d:IsA("BasePart") and (string.match(d.Name, "^Glass") or string.match(d.Name, "^Window")) then
					expect(d:GetAttribute("NightKind")).toBe("Window")
					expect(d:HasTag("ClinicNightLight")).toBe(true)
				elseif d:IsA("Light") and not (d.Parent and d.Parent.Name == "RoomLight") then
					lights += 1
				end
			end
			expect(building.Tower.LogoNeon:GetAttribute("NightKind")).toBe("Lamp")
			expect(building.Tower.Beacon:GetAttribute("NightKind")).toBe("Lamp")
			expect(lights).toBe(1) -- the one night light (room lights are counted in the next test)
			expect(building.Tower.LogoNeon.LogoGui.Mark.PawHeart ~= nil).toBe(true) -- our mark, never a cross
		end
	)

	test(
		"room lights: one shadowless light in the hall and in each indoor storey, on an Attachment (no part)",
		function()
			local building = build(5)
			local rooms = {}
			for _, d in building:GetDescendants() do
				if d:IsA("Attachment") and d.Name == "RoomLight" then
					local light = d:FindFirstChildWhichIsA("PointLight")
					expect(light ~= nil).toBe(true)
					expect(light.Shadows).toBe(false)
					local owner = d.Parent and d.Parent.Parent
					table.insert(rooms, owner and owner.Name or "?")
				end
			end
			table.sort(rooms)
			expect(table.concat(rooms, ",")).toBe("Floor_1,Floor_2,Floor_3,Hall")
		end
	)

	test("bed spots stay put (the same parts, the same place) across Lv 2 -> 5 and a theme change", function()
		build(2)
		local first = plot.Building.Wards.BedSpot_1
		local mattress = first.Bed_1
		local at = pivot:PointToObjectSpace(mattress.Position)
		expect(at.X).toBeCloseTo(B.WARD_BEDS[1].X, 3)
		expect(at.Z).toBeCloseTo(H.mattressZ(B), 3)
		for level = 3, 5 do
			expect(PlotBuilder.buildBuilding(plot, level, level - 1, "Candy").Wards.BedSpot_1).toBe(first)
		end
		local third = plot.Building.Wards.BedSpot_3
		expect(PlotBuilder.buildBuilding(plot, 5, nil, "Space").Wards.BedSpot_3).toBe(third)
		expect(plot.Building.Wards.BedSpot_1).toBe(first)
		expect(pivot:PointToObjectSpace(third.Bed_3.Position).X).toBeCloseTo(B.WARD_BEDS[3].X, 3)
		expect(plot.Building:GetAttribute("GrewAt")).toBe(0)
	end)

	test(
		"a theme recolours only the Trim and Band parts (and adds its prop); the walls stay the plot's colour",
		function()
			local function colours(building)
				local out = {}
				for _, p in world.parts(building) do
					if not p:FindFirstAncestor("ThemeProp") then
						local at = pivot:PointToObjectSpace(p.Position)
						local key = string.format("%s|%.2f|%.2f|%.2f", p.Name, at.X, at.Y, at.Z)
						out[key] = { Color = p.Color, Paint = p:GetAttribute("Paint") }
					end
				end
				return out
			end
			for level = 1, 5 do
				local candy = colours(build(level, "Candy"))
				for _, theme in Themes.Order do
					local themed = colours(build(level, theme))
					local changedTrim, changedBand = false, false
					for key, entry in candy do
						local other = themed[key]
						if other == nil then
							error(string.format("Lv %d %s: %s is missing", level, theme, key))
						end
						if other.Color ~= entry.Color then
							if entry.Paint == "Trim" then
								changedTrim = true
							elseif entry.Paint == "Band" then
								changedBand = true
							else
								error(string.format("Lv %d %s: %s changed colour", level, theme, key))
							end
						end
					end
					expect(changedTrim).toBe(theme ~= "Candy")
					expect(changedBand).toBe(theme ~= "Candy")
					expect(plot.Building:FindFirstChild("ThemeProp") ~= nil).toBe(theme ~= "Candy")
				end
			end
			expect(PlotBuilder.buildBuilding(plot, 3, nil, "Order"):GetAttribute("Theme")).toBe("Candy")
			expect(PlotBuilder.buildBuilding(plot, 1, nil, "Arctic"):FindFirstChild("ThemeProp") ~= nil).toBe(true)
		end
	)

	test("the theme props: at most 6 parts, walk-through, on the roof (or under its edge)", function()
		for _, theme in Themes.Order do
			for level = 1, 5 do
				local building = build(level, theme)
				local prop = building:FindFirstChild("ThemeProp")
				if prop then
					local parts = world.parts(prop)
					expect(#parts <= 6).toBe(true)
					for _, p in parts do
						expect(p.CanCollide).toBe(false)
						local _, lo = boxOf(p)
						expect(lo >= H.DOOR).toBe(true) -- overhead: never in the line or on the walkways
					end
				end
			end
		end
	end)

	test("nothing low covers the Counter, the line, the gate, the sign, the walkways or a room slot", function()
		local DOOR = H.DOOR
		-- The 80 x 80 plot (Config.Town.PlotSize; its front edge at z = -40), PlotBuilder.SLOTS and Patients' walkways
		-- at x = ±17.5 (makeNav: halfway between the Stand's edge, 15, and a side slot's, 20).
		local edge = -Config.Town.PlotSize / 2
		local walk = 17.5
		local zones = {
			-- name, x0, x1, z0, z1, below (nil = any height)
			{ "Counter", -6.4, 6.4, -16, -13, DOOR },
			{ "QueueLane", -4, 4, edge + 0.5, -15.8, DOOR },
			{ "Gate", -7, 7, edge, edge + 2 },
			{ "Sign", -18.5, -7.5, edge, edge + 3 },
			{ "OwnerSpawn", -8.5, -4.5, -24, -20 },
			{ "WalkwayLeft", -walk - 1.5, -B.HALF - 0.45, -18, 14, DOOR },
			{ "WalkwayRight", B.HALF + 0.45, walk + 1.5, -18, 14, DOOR },
			{ "SlotA", -38, -20, -2, 14 },
			{ "SlotC", 20, 38, -2, 14 },
			{ "SlotB", -24, -2, 20, 34 },
			{ "SlotD", 2, 24, 20, 34 },
		}
		local bad = {}
		for _, theme in { "Candy", "Arctic", "Royal" } do
			for level = 1, 5 do
				for _, p in world.parts(build(level, theme)) do
					local r, lo = boxOf(p)
					for _, z in zones do
						if overlaps(r, rect(z[2], z[3], z[4], z[5])) and lo < (z[6] or math.huge) then
							table.insert(bad, string.format("Lv %d %s %s on %s", level, theme, fullName(p), z[1]))
						end
					end
				end
			end
		end
		expect(bad).toEqual({})
	end)

	test("a free plot goes back to the Lv 1 podium in Candy", function()
		build(5, "Space")
		PlotBuilder.clearPlot(plot)
		expect(plot:GetAttribute("Theme")).toBe("Candy")
		expect(plot:GetAttribute("Level")).toBe(1)
		expect(plot.Building.PodiumShell ~= nil).toBe(true)
		expect(plot.Building:FindFirstChild("Lift")).toBeNil()
	end)
end)
