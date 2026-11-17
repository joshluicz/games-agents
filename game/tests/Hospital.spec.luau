--!nocheck
-- The clinic building (the Real Clinic build plan, Task 1; contracts C1 and C2; design §8): HospitalBuilder's own
-- numbers (its PURE block, which PlotBuilder.Pure re-exports, against Shared/Logic/Building), the doors' rules
-- (World/Doors' PURE block), the lift's rules (Server/Lift and UI/LiftPanel pure blocks), the stations' hold factors
-- (Server/Stations) and the cutaway's rules (Feel/Cutaway).
-- The pure blocks are loaded straight from the shipped source. The last part builds the REAL HospitalBuilder (and
-- World/*) under tests/worldmock (Lune's roblox datatypes; no Roblox services) on a bare plot Model that is moved and
-- turned like a town plot, at every level and theme, so the contract's markers, the budgets, the closed doors and
-- "everything solid is in Logic/Building.obstacles" are checked on what ships. It prints the building's measured part
-- count per level. The whole plot's budget is tests/PartBudget.spec. Run from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local T = require("./expect")
local expect, test = T.expect, T.test

local Config = require("./config")
local LevelsData = require("../src/shared/Data/Levels")
local Departments = require("../src/shared/Data/Departments")
local RoomsData = require("../src/shared/Data/Rooms")
local Themes = require("../src/shared/Data/Themes")
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

local ROOF = Departments.Roof.Floor
local LANDING = { X = B.LANDING.X, Z = B.LANDING.Z }
local LEVELS = { 1, 2, 3, 4, 5 }

local function rect(x0, x1, z0, z1)
	return { X0 = x0, X1 = x1, Z0 = z0, Z1 = z1 }
end

local function overlaps(a, b): boolean
	local e = 0.01
	return a.X0 < b.X1 - e and b.X0 < a.X1 - e and a.Z0 < b.Z1 - e and b.Z0 < a.Z1 - e
end

local function inside(inner, outer, slack: number?): boolean
	local e = slack or 0.01
	return inner.X0 >= outer.X0 - e
		and inner.X1 <= outer.X1 + e
		and inner.Z0 >= outer.Z0 - e
		and inner.Z1 <= outer.Z1 + e
end

local function area(r): number
	return math.max(0, r.X1 - r.X0) * math.max(0, r.Z1 - r.Z0)
end

local function cut(a, b)
	return rect(math.max(a.X0, b.X0), math.min(a.X1, b.X1), math.max(a.Z0, b.Z0), math.min(a.Z1, b.Z1))
end

local function grow(r, by: number)
	return rect(r.X0 - by, r.X1 + by, r.Z0 - by, r.Z1 + by)
end

local function landingRect()
	local h = B.LANDING.Size / 2
	return rect(LANDING.X - h, LANDING.X + h, LANDING.Z - h, LANDING.Z + h)
end

local function words(text: string): number
	local n = 0
	for _ in string.gmatch(text, "%S+") do
		n += 1
	end
	return n
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
-- The building's own numbers (HospitalBuilder.Pure on Logic/Building)
------------------------------------------------------------------------------------------------------------------

T.describe("Hospital (numbers)", function()
	local H = loadPure("src/server/HospitalBuilder.luau")

	test("floors that stand: F1 from Lv 1 (shut), the tower to three storeys, the roof deck at Lv 5", function()
		local standing, opened = {}, {}
		for _, level in LEVELS do
			table.insert(standing, H.standing(B, level))
			table.insert(opened, B.floors(level))
			expect(B.floors(level)).toBe(LevelsData[level].Floors)
		end
		expect(standing).toEqual({ 1, 1, 2, 3, 4 })
		expect(opened).toEqual({ 0, 1, 2, 3, 4 })
		expect({ H.sinceStanding(B, 1), H.sinceStanding(B, 2), H.sinceStanding(B, 3), H.sinceStanding(B, 4) }).toEqual({
			1,
			3,
			4,
			5,
		})
		expect({ H.sinceOpen(B, 1), H.sinceOpen(B, 2), H.sinceOpen(B, 3), H.sinceOpen(B, 4) }).toEqual({ 2, 3, 4, 5 })
		expect(ROOF).toBe(#B.SLAB_TOPS)
	end)

	test(
		"an upper floor's slab: the tower inside its walls, less the shaft and the stairwell, never overlapping",
		function()
			local rects = H.slabRects(B)
			local t, w = B.TOWER, B.WALL
			local inner = rect(t.X0 + w, t.X1 - w, t.Z0 + w, t.Z1 - w)
			local total, named = 0, 0
			for i, r in rects do
				expect(inside(r, inner)).toBe(true)
				expect(overlaps(r, B.SHAFT)).toBe(false)
				expect(overlaps(r, B.STAIRWELL)).toBe(false)
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
			expect(total).toBeCloseTo(area(inner) - area(cut(B.SHAFT, inner)) - area(cut(B.STAIRWELL, inner)), 5)
			-- the stairs' landing is floor: some piece covers it whole
			local covered = false
			for _, r in rects do
				covered = covered or inside(B.STAIR_LANDING, r)
			end
			expect(covered).toBe(true)
		end
	)

	test("each half-flight: never steeper than 1 in 2, floor -> mid landing -> next floor, inside the well", function()
		local well = B.STAIRWELL
		for k = 0, 3 do
			local y0, y1 = B.slabTop(k), B.slabTop(k + 1)
			local mid = (y0 + y1) / 2
			local a, b = H.ramp(B, k, "A"), H.ramp(B, k, "B")
			-- lane A: from the landing's edge on the floor up toward +x to the mid landing
			expect({ a.XL, a.YL, a.XR, a.YR }).toEqual({ B.LANE_A.X0, y0, B.LANE_A.X1, mid })
			-- across, each lane stops at the faces it meets (the rail, the wall between the lanes), never inside them
			expect({ a.Z0, a.Z1 }).toEqual({ B.LANE_A.Z0 + H.RAIL.Thick, B.LANE_A.Z1 - B.DIVIDER / 2 })
			-- lane B: from the mid landing back to the next floor (a small step short of its landing)
			expect({ b.XR, b.YR }).toEqual({ B.LANE_B.X1, mid })
			expect(b.XL - B.LANE_B.X0 <= 0.3).toBe(true)
			expect(y1 - b.YL <= 0.15 and y1 - b.YL >= 0).toBe(true)
			expect({ b.Z0, b.Z1 }).toEqual({ B.LANE_B.Z0 + B.DIVIDER / 2, B.LANE_B.Z1 })
			for _, r in { a, b } do
				expect(math.abs(r.YR - r.YL) / math.abs(r.XR - r.XL) <= 0.5 + 1e-9).toBe(true)
				-- the tilted slab stays inside the well, and its frame puts its top on the walking line
				local bx = H.rampBox(r, H.RAMP)
				expect(bx.X0 >= well.X0 - 1e-6 and bx.X1 <= well.X1 + 1e-6).toBe(true)
				local fr = H.rampFrame(r, H.RAMP)
				local c, s = math.cos(fr.Angle), math.sin(fr.Angle)
				local topX = fr.X + fr.Length / 2 * c - H.RAMP / 2 * s
				local topY = fr.Y + fr.Length / 2 * s + H.RAMP / 2 * c
				expect(topX).toBeCloseTo(r.XR, 4)
				expect(topY).toBeCloseTo(r.YR, 4)
			end
			-- the same lane one storey up passes a whole storey over it: headroom on every step
			if k < 3 then
				local above = H.ramp(B, k + 1, "A")
				expect(above.YL - a.YL - H.RAMP >= 10).toBe(true)
			end
		end
	end)

	test(
		"the steps: 6-8 a half-flight, every nose on the ramp's line, no tread above it, the last riser on the landing",
		function()
			-- Joshua (2026-11-17): "look at how this block is glitchy". The steps are what you see; the ramp under the
			-- noses is what you walk on (it is never below a tread, so feet never catch on one).
			expect(H.STEPS >= 6 and H.STEPS <= 9).toBe(true)
			for k = 0, 3 do
				local y0, y1 = B.slabTop(k), B.slabTop(k + 1)
				local mid = (y0 + y1) / 2
				for _, lane in { "A", "B" } do
					local r = H.ramp(B, k, lane)
					-- the ramp's walking line (lane B's ramp is cut a little short of its landing: the same line)
					local function line(x: number): number
						return r.YR + (x - r.XR) * (r.YL - r.YR) / (r.XL - r.XR)
					end
					local steps = H.steps(B, k, lane)
					expect(#steps).toBe(H.STEPS)
					local l = if lane == "A" then B.LANE_A else B.LANE_B
					for i, s in steps do
						local going = s.X1 - s.X0
						expect(going).toBeCloseTo((l.X1 - l.X0) / H.STEPS, 6)
						expect(s.Rise / going <= 0.5 + 1e-9).toBe(true) -- never steeper than 1 in 2
						expect(s.Rise <= 1 and s.Rise >= 0.5).toBe(true)
						-- the nose (the downhill edge) on the line; the tread never above it, never a riser below it
						local nose = if lane == "A" then s.X0 else s.X1
						expect(s.Top).toBeCloseTo(line(nose), 6)
						for _, x in { s.X0, s.X1 } do
							expect(s.Top <= line(x) + 1e-6).toBe(true)
							expect(s.Top >= line(x) - s.Rise - 1e-6).toBe(true)
						end
						expect(s.X0 >= l.X0 - 1e-6 and s.X1 <= l.X1 + 1e-6).toBe(true)
						local nxt = steps[i + 1]
						if nxt then -- one after another, a riser up each time
							expect(if lane == "A" then nxt.X0 else nxt.X1).toBeCloseTo(
								if lane == "A" then s.X1 else s.X0,
								6
							)
							expect(nxt.Top - s.Top).toBeCloseTo(s.Rise, 6)
						end
					end
					local first, last = steps[1], steps[#steps]
					if lane == "A" then
						expect({ first.X0, first.Top }).toEqual({ l.X0, y0 }) -- level with the floor it starts from
						expect(last.X1).toBeCloseTo(l.X1, 6)
						expect(last.Top + last.Rise).toBeCloseTo(mid, 6) -- the last riser onto the mid landing
					else
						expect({ first.X1, first.Top }).toEqual({ l.X1, mid }) -- level with the mid landing
						expect(last.X0).toBeCloseTo(l.X0, 6)
						expect(last.Top + last.Rise).toBeCloseTo(y1, 6) -- the last riser onto the next floor
					end
					-- upstairs a step reaches WAIST under the riser below it: the flight below keeps its headroom
					if k > 0 then
						local below = H.steps(B, k - 1, lane)
						for i, s in steps do
							expect(s.Top - s.Rise - H.WAIST - below[i].Top >= 9).toBe(true)
						end
					end
				end
			end
		end
	)

	test("the ward beds: each mattress puts its foot spot on Logic/Building.BED_FOOT_Z, inside the bed spot", function()
		local bed = H.BED
		local z = H.mattressZ(B)
		expect(z + bed.MattressLength / 2 + bed.FootStep).toBeCloseTo(B.BED_FOOT_Z, 5)
		expect(z - bed.MattressLength / 2 >= B.BED_Z0 + bed.HeadboardThick - 0.01).toBe(true)
		expect(z + bed.MattressLength / 2 <= B.BED_Z1 + 1e-9).toBe(true)
		expect(bed.Width).toBeCloseTo(B.BED_HALF * 2, 5)
		expect(bed.Headboard <= bed.Width and bed.Headboard % 1 == 0).toBe(true)
	end)

	test("the lift and the roofs: the shaft up under the top roof, past the car at the roof deck", function()
		expect(H.shaftTop(B, 1, ROOF)).toBeCloseTo(23 - H.SLAB, 5)
		expect(H.shaftTop(B, 2, ROOF)).toBeCloseTo(34 - H.SLAB, 5)
		expect(H.shaftTop(B, 3, ROOF)).toBeCloseTo(45 - H.SLAB, 5)
		expect(H.shaftTop(B, 4, ROOF)).toBeCloseTo(45 + H.CAR + H.CLEAR, 5)
		expect(H.CAR < B.STOREY - H.SLAB).toBe(true)
		expect(H.CAR >= 6.5 + 1).toBe(true) -- the biggest creature (6.5 tall) rides inside with a stud to spare
		expect(H.roofTop(B, 1)).toBe(23)
		expect(H.wallTop(B, 0)).toBeCloseTo(11.4, 5)
		expect(H.wallTop(B, 3)).toBeCloseTo(44.4, 5)
		expect(H.wallBase(B, 0)).toBe(0)
		expect(H.wallBase(B, 2)).toBeCloseTo(22.4, 5)
		expect(H.SLAB <= B.SLAB_MAX).toBe(true)
		-- the tall doorways (Joshua, 2026-11-17: "the door is so low"): the bays' header starts at their height; no
		-- doorway is taller (the front doors and the dispensary's stay lower)
		expect(H.DOOR).toBe(B.DOORS.XRay.Height)
		for _, d in B.DOORS do
			expect(d.Height <= H.DOOR).toBe(true)
		end
		expect(H.TUCK >= 0.08).toBe(true) -- an open door's edge stands clear of its jamb's face
		-- the X-ray scanner hangs clear of a 6.5-stud creature sitting on the couch, under the ceiling
		expect(H.XRAY.Head >= H.COUCH + 6.5 + 0.5).toBe(true)
		expect(H.XRAY.HeadTop < H.wallTop(B, 0)).toBe(true)
	end)

	test("walls leave their doorways open", function()
		local ae = B.DOORS.AE
		expect(H.segments(-23.4, 19.4, { ae })).toEqual({ { Z0 = -23.4, Z1 = ae.Z0 }, { Z0 = ae.Z1, Z1 = 19.4 } })
		expect(H.segments(0, 5, {})).toEqual({ { Z0 = 0, Z1 = 5 } })
		expect(H.segments(0, 10, { { Z0 = 6, Z1 = 8 }, { Z0 = 1, Z1 = 2 } })).toEqual({
			{ Z0 = 0, Z1 = 1 },
			{ Z0 = 2, Z1 = 6 },
			{ Z0 = 8, Z1 = 10 },
		})
	end)

	test("a waiting-room chair fills its seat's rect, its back behind the sitter", function()
		for _, seat in B.SEATS do
			local c = H.chair(B, seat)
			local r = B.seatRect(seat)
			expect(inside(c.Cushion, r)).toBe(true)
			expect(inside(c.Back, r)).toBe(true)
			expect(overlaps(c.Cushion, c.Back)).toBe(false)
			expect(area(c.Cushion) + area(c.Back)).toBeCloseTo(area(r), 5)
			local dx, dz = B.facing(seat.Face)
			local bx, bz = (c.Back.X0 + c.Back.X1) / 2 - seat.X, (c.Back.Z0 + c.Back.Z1) / 2 - seat.Z
			expect(bx * dx + bz * dz < 0).toBe(true)
		end
		expect(H.SEAT.Height < H.SEAT.BackHeight).toBe(true)
	end)

	test("a closed door's words: short, the level it opens at or the room's price", function()
		expect(H.levelLock(2)).toBe("🔒 Opens at Lv 2")
		local bath = { Icon = "🛁", Name = "Bath Room", Price = 150 }
		expect(H.roomLock(1, bath)).toEqual({ "🛁 Bath Room", "💰 150 to open" })
		local garden = { Icon = "🌻", Name = "Sunny Garden", Price = 800, Level = 3 }
		expect(H.roomLock(2, garden)).toEqual({ "🌻 Sunny Garden", "🔒 Opens at Lv 3" })
		expect(H.roomLock(3, garden)).toEqual({ "🌻 Sunny Garden", "💰 800 to open" })
		expect(H.roomLock(1, nil)).toEqual({ "Room", "💰 0 to open" })
		-- the real rooms behind the building's doors
		for _, door in B.DOORS do
			if door.Room then
				for _, level in LEVELS do
					for _, line in H.roomLock(level, RoomsData[door.Room]) do
						expect(words(line) <= 6).toBe(true)
						expect(string.find(string.lower(line), "cure")).toBeNil()
					end
				end
			end
		end
	end)

	test("the roof deck: the helipad, the planters and a theme's prop each have their own place", function()
		local t, w = B.TOWER, B.WALL
		local deck = rect(t.X0 + w, t.X1 - w, t.Z0 + w, t.Z1 - w)
		local h = B.HELI
		local pad = rect(h.X - h.Size / 2, h.X + h.Size / 2, h.Z - h.Size / 2, h.Z + h.Size / 2)
		local s = H.PLANTER / 2
		local spots = {}
		for _, at in H.PLANTERS do
			table.insert(spots, rect(at.X - s, at.X + s, at.Z - s, at.Z + s))
		end
		table.insert(spots, rect(H.PROP.X - 1.5, H.PROP.X + 1.5, H.PROP.Z - 1.5, H.PROP.Z + 1.5))
		for i, r in spots do
			expect(inside(r, deck)).toBe(true)
			-- off the pad, the lift and the stair head (the stairwell's whole enclosure rises through the deck)
			for _, other in { pad, B.SHAFT, B.ROOMS.Stairwell, landingRect() } do
				expect(overlaps(r, other)).toBe(false)
			end
			for j, other in spots do
				if i < j then
					expect(overlaps(r, other)).toBe(false)
				end
			end
		end
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
-- The doors' rules (World/Doors)
------------------------------------------------------------------------------------------------------------------

T.describe("Hospital (doors)", function()
	local D = loadPure("src/server/World/Doors.luau")

	test("locked: under its level, or its room not owned; anything else is free", function()
		expect(D.locked(1, 2, nil, false)).toBe(true)
		expect(D.locked(2, 2, nil, false)).toBe(false)
		expect(D.locked(5, nil, nil, false)).toBe(false)
		expect(D.locked(5, nil, "BathRoom", false)).toBe(true)
		expect(D.locked(1, nil, "BathRoom", true)).toBe(false)
		expect(D.locked(nil, 2, nil, false)).toBe(true) -- no level reads as Lv 1
		expect(D.locked(0 / 0, 2, nil, false)).toBe(true)
		expect(D.locked(3, nil, "", false)).toBe(false)
	end)

	test("near: within the radius across and the height up or down; the floor upstairs never counts", function()
		local r, h = D.RADIUS, D.HEIGHT
		expect(r).toBe(8)
		expect(D.near({}, 0, 0, 0, r, h)).toBe(false)
		expect(D.near({ { X = 7.9, Y = 3, Z = 0 } }, 0, 0.5, 0, r, h)).toBe(true)
		expect(D.near({ { X = 6, Y = 3, Z = 6 } }, 0, 0.5, 0, r, h)).toBe(false) -- 8.5 away
		expect(D.near({ { X = 1, Y = 14, Z = 0 } }, 0, 0.5, 0, r, h)).toBe(false) -- F1, over the door
		expect(D.near({ { X = 50, Y = 0, Z = 0 }, { X = 0, Y = 0, Z = -3 } }, 0, 0.5, 0, r, h)).toBe(true)
	end)

	test(
		"state: locked wins, else open while someone is near; checked a few times a second, never per frame",
		function()
			expect(D.state(true, true)).toBe("Locked")
			expect(D.state(false, true)).toBe("Open")
			expect(D.state(false, false)).toBe("Shut")
			expect(D.CHECK_SECONDS >= 0.2).toBe(true)
			expect(D.SLIDE_SECONDS > 0 and D.SLIDE_SECONDS < 1).toBe(true)
		end
	)

	test("nobody is sealed in: a player in a room that locked, or upstairs of a closed floor, is trapped", function()
		local tops = B.SLAB_TOPS
		expect(D.floorAt(3, tops)).toBe(0)
		expect(D.floorAt(tops[1] + 3, tops)).toBe(1)
		expect(D.floorAt(tops[2] + 3, tops)).toBe(2)
		expect(D.floorAt(tops[4] + 3, tops)).toBe(4) -- the roof deck
		expect(D.floorAt(0 / 0, tops)).toBe(0)
		expect(D.floorAt(3, nil)).toBe(0)
		-- an owner leaves a Lv 3 clinic (or rebirths): the Building is Lv 1 again and the X-ray room's door is solid
		local xray, bath = B.ROOMS.XRay, B.ROOMS.BathRoom
		local spot = B.doctorSpot(B.bay("X"))
		expect(D.trapped(spot.X, 3, spot.Z, { xray }, 0, tops)).toBe(true)
		expect(D.trapped(spot.X, 3, spot.Z, {}, 2, tops)).toBe(false) -- its door is open: nobody is moved
		expect(D.trapped((bath.X0 + bath.X1) / 2, 3, (bath.Z0 + bath.Z1) / 2, { xray, bath }, 0, tops)).toBe(true)
		-- the corridor outside the door, the lobby and reception are never a trap
		local _, outside = B.doorPoints("XRay")
		expect(D.trapped(outside.X, 3, outside.Z, { xray, bath }, 0, tops)).toBe(false)
		expect(D.trapped(B.RECEPTION.Stop.X, 3, B.RECEPTION.Stop.Z, { xray, bath }, 0, tops)).toBe(false)
		for _, r in { xray, bath, B.ROOMS.WinterWing, B.ROOMS.CozyWard } do
			local s = B.RECEPTION.Stop
			expect(s.X > r.X0 and s.X < r.X1 and s.Z > r.Z0 and s.Z < r.Z1).toBe(false) -- where the rescued land
		end
		-- upstairs: closed behind the stair gate and the lift's locked door under the level that opens it
		expect(D.trapped(20, tops[1] + 3, 10, {}, 0, tops)).toBe(true) -- F1 at Lv 1
		expect(D.trapped(20, tops[1] + 3, 10, {}, 1, tops)).toBe(false) -- F1 at Lv 2
		expect(D.trapped(20, tops[3] + 3, 10, {}, 2, tops)).toBe(true) -- F3 at Lv 3
		expect(D.trapped(20, tops[4] + 3, 10, {}, 4, tops)).toBe(false) -- the roof at Lv 5
		expect(D.trapped(0 / 0, 3, 0, { xray }, 0, tops)).toBe(false)
		expect(D.RESCUE_SECONDS <= 2).toBe(true)
	end)

	test(
		"shut: a building without a Door_Stairs (a kit) still counts its stair flights while upstairs is closed",
		function()
			local xray, flights = B.ROOMS.XRay, B.STAIRWELL
			local tops = B.SLAB_TOPS
			local on = { X = (flights.X0 + flights.X1) / 2, Z = (flights.Z0 + flights.Z1) / 2 }
			-- HospitalBuilder's own building: Door_Stairs is Locked at Lv 1 and its room is already in the list
			local rooms = { xray, B.ROOMS.Stairwell }
			expect(D.shut(rooms, 0, true, flights)).toBe(rooms)
			expect(D.trapped(on.X, 3, on.Z, D.shut(rooms, 0, true, flights), 0, tops)).toBe(true)
			-- a kit building with no such door: the flights are added, on a copy
			local kit = { xray }
			local shut = D.shut(kit, 0, false, flights)
			expect(#kit).toBe(1)
			expect(shut).toEqual({ xray, flights })
			expect(D.trapped(on.X, 3, on.Z, kit, 0, tops)).toBe(false) -- without the fallback nobody would be moved
			expect(D.trapped(on.X, 3, on.Z, shut, 0, tops)).toBe(true)
			-- upstairs open: the flights are a way up, not a trap
			expect(D.shut(kit, 1, false, flights)).toBe(kit)
			expect(D.trapped(on.X, 3, on.Z, D.shut(kit, 1, false, flights), 1, tops)).toBe(false)
			-- the server asks it, and knows which buildings have the door
			local text = fs.readFile("src/server/World/Doors.luau")
			expect(
				string.find(
					text,
					"Pure.shut(rooms, floorsOpen, stairsDoor[building] == true, Building.STAIRWELL)",
					1,
					true
				) ~= nil
			).toBe(true)
			expect(string.find(text, 'if door == "Stairs" then', 1, true) ~= nil).toBe(true)
		end
	)

	test("HospitalBuilder hooks a plot's Rooms folder once: a strong table, cleared when the folder goes", function()
		local text = fs.readFile("src/server/HospitalBuilder.luau")
		expect(string.find(text, "local watching: { [Instance]: boolean } = {}", 1, true) ~= nil).toBe(true)
		expect(string.find(text, "__mode", 1, true)).toBeNil() -- a weak key may go while the folder lives
		local i = string.find(text, "local function watchRooms(", 1, true)
		local fn = string.sub(text, i, i + 500)
		expect(string.find(fn, "rooms.Destroying:Connect(function()", 1, true) ~= nil).toBe(true)
		expect(string.find(fn, "watching[rooms] = nil", 1, true) ~= nil).toBe(true)
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- The lift's rules and the stations
------------------------------------------------------------------------------------------------------------------

T.describe("Hospital (lift rules)", function()
	local Lift = loadPure("src/server/Lift.luau")
	local Panel = loadPure("src/client/UI/LiftPanel.luau")

	test("which floors exist per level (Data/Levels Floors)", function()
		local got = {}
		for level = 1, 5 do
			got[level] = Lift.floors(LevelsData[level].Floors)
		end
		expect(got).toEqual({ { 0 }, { 0, 1 }, { 0, 1, 2 }, { 0, 1, 2, 3 }, { 0, 1, 2, 3, 4 } })
		expect(Lift.exists(4, LevelsData[5].Floors)).toBe(true)
		expect(Lift.exists(5, LevelsData[5].Floors)).toBe(false)
		expect(Lift.exists(1, LevelsData[1].Floors)).toBe(false) -- F1 stands at Lv 1, but it is shut
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
		expect(Lift.nearest(landings, LANDING.X - 1, 0 + 3, LANDING.Z, reach).Floor).toBe(0)
		expect(Lift.nearest(landings, LANDING.X - 1, B.slabTop(2) + 3, LANDING.Z, reach).Floor).toBe(2)
		expect(Lift.nearest(landings, LANDING.X, B.slabTop(4) + 3, LANDING.Z, reach).Floor).toBe(4)
		expect(Lift.nearest(landings, LANDING.X - reach - 1, 3, LANDING.Z, reach)).toBeNil()
		expect(Lift.nearest(landings, LANDING.X, -5, LANDING.Z, reach)).toBeNil()
		expect(Lift.ABOVE < B.STOREY).toBe(true)
	end)

	test("riders are set down side by side, along the lift's door, on open floor on every floor", function()
		expect({ Lift.spread(1), Lift.spread(2), Lift.spread(3), Lift.spread(4) }).toEqual({ 0, 2.8, -2.8, 5.6 })
		for index = 1, 6 do
			expect(Panel.spread(index)).toBe(Lift.spread(index))
		end
		expect(Panel.inCar(1, 2)).toBe(0)
		expect(Panel.inCar(2, 2) > 0 and Panel.inCar(3, 2) < 0).toBe(true)
		for index = 1, 6 do
			expect(math.abs(Panel.inCar(index, 2)) <= 2).toBe(true)
		end
		expect(Panel.inCar(4, -1)).toBe(0)
		-- The landing faces the lift (its door is on the shaft's -x face), so its X runs along +z: a rider and the
		-- escort (riders 1 and 2) step out on open floor, clear of the shaft and every wall, on every floor.
		for k = 0, 4 do
			local obstacles = B.obstacles(5, k)
			for index = 1, 2 do
				local z = LANDING.Z + Lift.spread(index)
				local spot = rect(LANDING.X - 1, LANDING.X + 1, z - 1, z + 1)
				for _, o in obstacles do
					if overlaps(spot, o) then
						error(string.format("floor %d: rider %d steps out into %s", k, index, o.Name))
					end
				end
			end
		end
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
		-- F3 (the staff room) has no department of its own, so it shows the lift
		expect(texts).toEqual({ "🚁 R", "↕️ 3", "😴 2", "🛏️ 1", "🛎️ G" })
		local lv2 = Panel.buttons(LevelsData[2].Floors, 1, Departments)
		expect(#lv2).toBe(2)
		expect(lv2[1].Here).toBe(true)
		expect(lv2[2].Here).toBe(false)
		for _, button in Panel.buttons(4, nil, Departments) do
			expect(words(button.Text) <= 6).toBe(true)
		end
	end)
end)

T.describe("Hospital (stations)", function()
	local Stations = loadPure("src/server/Stations.luau")

	test("hold factors: team x ability rush, never under Config.BoostMinMakeSeconds, never longer", function()
		local floor = Config.BoostMinMakeSeconds
		expect(Stations.holdSeconds(2, 1, 1, floor)).toBe(2)
		expect(Stations.holdSeconds(2, 0.6, 1, floor)).toBeCloseTo(1.2, 5) -- a team of 3 (40%)
		expect(Stations.holdSeconds(2, 0.6, 0.5, floor)).toBeCloseTo(0.6, 5) -- + Busy Paws
		expect(Stations.holdSeconds(2, 1, 0, floor)).toBe(floor) -- Time Bubble: the shortest hold
		expect(Stations.holdSeconds(0.2, 1, 1, floor)).toBe(0.2) -- already under the floor: unchanged
		expect(Stations.holdSeconds(2, 1.5, 3, floor)).toBe(2) -- never slower than base
		expect(Stations.holdSeconds(2, 0 / 0, -1, floor)).toBe(2) -- junk factors change nothing
		expect(Stations.holdSeconds(-1, 1, 1, floor)).toBe(floor)
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- The cutaway's rules (Feel/Cutaway)
------------------------------------------------------------------------------------------------------------------

T.describe("Hospital (cutaway)", function()
	local Cut = loadPure("src/client/Feel/Cutaway.luau")

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
		expect(Cut.floorOf(34, Cut.tops(tops, 2))).toBe(2)
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
		expect(Cut.FADE >= 0.25).toBe(true)
		expect(Cut.CHECKS_PER_SECOND).toBe(4)
		expect(Cut.IDLE_SECONDS >= 1).toBe(true)
	end)

	test("feet: R15 stands HipHeight under its root; the footprint counts a doorway in, not the yard", function()
		expect(Cut.feet(14, 1, 2)).toBe(11)
		expect(Cut.feet(14, 1, 0)).toBe(11)
		local block = B.footprint(1, 0)
		expect(Cut.inside(0, 0, block, 0)).toBe(true)
		expect(Cut.inside(-B.HALF_X - 0.3, 0, block, Cut.MARGIN)).toBe(true) -- in the A&E doorway
		expect(Cut.inside(-B.HALF_X - 1.5, 0, block, Cut.MARGIN)).toBe(false) -- the -x yard
		expect(Cut.inside(0, B.BACK + 1.5, block, Cut.MARGIN)).toBe(false)
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- The real HospitalBuilder under tests/worldmock (Lune's roblox datatypes; Instances are plain tables)
------------------------------------------------------------------------------------------------------------------

T.describe("Hospital (the built world)", function()
	local world = require("./worldmock").new()
	local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
	local Enum = roblox.Enum
	local Palette = world.load("src/shared/Palette.luau")
	local WORLD = Palette.World
	local HospitalBuilder = world.load("src/server/HospitalBuilder.luau")
	local H = HospitalBuilder.Pure

	-- A bare plot, moved and turned round like the plots across the street, so the plot-local maths is tested.
	local plot = world.new("Model")
	plot.Name = "Plot_1"
	plot.WorldPivot = CFrame.new(118, 0.5, 80) * CFrame.Angles(0, math.pi, 0)
	plot:SetAttribute("Accent", Palette.PlotColors[1])
	plot:SetAttribute("PlotIndex", 1)
	local roomsFolder = world.new("Folder")
	roomsFolder.Name = "Rooms"
	roomsFolder.Parent = plot
	plot.Parent = world.Workspace
	local pivot = plot:GetPivot()
	local accent = plot:GetAttribute("Accent")

	local function own(list: { string })
		roomsFolder:ClearAllChildren()
		for _, id in list do
			local room = world.new("Model")
			room.Name = "Room_" .. id
			room.Parent = roomsFolder
		end
	end

	local function build(level: number, theme: string?, grewFrom: number?)
		return HospitalBuilder.build(plot, level, grewFrom, theme or "Candy")
	end

	-- A part's box in plot-local studs, as a rect plus its y range.
	local function boxOf(p)
		local lo, hi = world.box(p, pivot)
		return rect(lo.X, hi.X, lo.Z, hi.Z), lo.Y, hi.Y
	end

	-- A part's frame in plot-local space.
	local function frameOf(p)
		return pivot:ToObjectSpace(p.CFrame)
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

	-- Walking height: up to the lowest doorway's top (the inside doors are 10 tall, the front pair and the
	-- dispensary's 8).
	local LOW_DOOR = math.huge
	for _, d in B.DOORS do
		LOW_DOOR = math.min(LOW_DOOR, d.Height)
	end

	-- A part's box in plot-local studs as { P, Lo, Hi } (Vector3s).
	local function box3(p)
		local lo, hi = world.box(p, pivot)
		return { P = p, Lo = lo, Hi = hi }
	end

	-- How far two boxes overlap along each axis (negative: apart; 0: touching).
	local function overlap3(a, b): (number, number, number)
		return math.min(a.Hi.X, b.Hi.X) - math.max(a.Lo.X, b.Lo.X),
			math.min(a.Hi.Y, b.Hi.Y) - math.max(a.Lo.Y, b.Lo.Y),
			math.min(a.Hi.Z, b.Hi.Z) - math.max(a.Lo.Z, b.Lo.Z)
	end

	-- A block lying square to the plot (its box is its faces).
	local function squareBlock(p): boolean
		if p.ClassName ~= "Part" or (p.Shape ~= nil and p.Shape ~= Enum.PartType.Block) then
			return false
		end
		local cf = pivot:ToObjectSpace(p.CFrame)
		for _, v in { cf.RightVector, cf.UpVector, cf.LookVector } do
			if math.max(math.abs(v.X), math.abs(v.Y), math.abs(v.Z)) < 1 - 1e-4 then
				return false
			end
		end
		return true
	end

	-- "Plot_1.Building.Shell.WallFascia" (the mock has no GetFullName).
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

	-- The texts of every TextLabel under `root`.
	local function texts(root): string
		local out = {}
		for _, d in root:GetDescendants() do
			if d.ClassName == "TextLabel" and d.Name == "Text" then
				table.insert(out, d.Text)
			end
		end
		return table.concat(out, " | ")
	end

	local function near(a: number, b: number, digits: number?): boolean
		return math.abs(a - b) < (10 ^ -(digits or 3))
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

	test("the contract's markers at every level: doors, seats, bays, stations, floors, the lift, the stairs", function()
		own({})
		for _, level in LEVELS do
			local building = build(level, "Candy", level - 1)
			local floors, standing = B.floors(level), H.standing(B, level)
			expect(building.Name).toBe("Building")
			expect(building:GetAttribute("Level")).toBe(level)
			expect(building:GetAttribute("Floors")).toBe(LevelsData[level].Floors)
			expect(building:GetAttribute("Storeys")).toBe(standing)
			expect(building:GetAttribute("Theme")).toBe("Candy")
			expect(building:GetAttribute("GrewFrom")).toBe(level - 1)
			expect(building:GetAttribute("Origin")).toEqual(pivot)
			expect(plot:GetAttribute("Level")).toBe(level)
			for _, child in building:GetChildren() do
				if child:GetAttribute("Since") == nil or child:GetAttribute("Storey") == nil then
					error(string.format("Lv %d: %s has no Since or Storey", level, child.Name))
				end
				expect(child:GetAttribute("Since") <= level).toBe(true)
			end
			-- the front doors
			local front = building.FrontDoor
			expect(front.ClassName).toBe("Model")
			expect(front.DoorL:IsA("BasePart") and front.DoorR:IsA("BasePart") and front.Sensor:IsA("BasePart")).toBe(
				true
			)
			expect(front:HasTag("ClinicDoor")).toBe(true)
			expect(building.ReceptionStop:IsA("BasePart")).toBe(true)
			-- the waiting room's 6 seats
			for n = 1, 6 do
				local seat = building:FindFirstChild("WaitSeat_" .. n)
				expect(seat:IsA("BasePart") and seat.Transparency == 1 and seat.CanCollide == false).toBe(true)
			end
			expect(building:FindFirstChild("WaitSeat_7")).toBeNil()
			-- the bays: 1-6 and X here; the Cozy Ward's W1 and W2 are PlotBuilder's
			local openBays = 0
			for _, bay in B.BAYS do
				local model = building:FindFirstChild("ExamBay_" .. bay.Id)
				if bay.Room then
					expect(model).toBeNil()
				else
					expect(model.ClassName).toBe("Model")
					for _, name in { "Bed", "DoctorSpot", "Curtain", "Tray", "Sign" } do
						if not (model:FindFirstChild(name) and model[name]:IsA("BasePart")) then
							error(string.format("Lv %d: ExamBay_%s has no %s", level, bay.Id, name))
						end
					end
					expect(model:GetAttribute("Bay")).toBe(bay.Id)
					expect(model:GetAttribute("Kind")).toBe(bay.Kind)
					expect(model:GetAttribute("Opens")).toBe(bay.Opens)
					expect(model:GetAttribute("Open")).toBe(level >= bay.Opens)
					if bay.Kind == "Exam" and level >= bay.Opens then
						openBays += 1
					end
				end
			end
			expect(openBays).toBe(LevelsData[level].Bays)
			-- the stations
			for id in B.STATIONS do
				local p = building:FindFirstChild("Station_" .. id)
				expect(p:IsA("BasePart")).toBe(true)
				expect(p:GetAttribute("Open")).toBe(B.stationOpen(id, level))
				expect(p:GetAttribute("StationId")).toBe(id)
				expect(p:HasTag("BuildingStation")).toBe(true)
				expect(p.IconGui ~= nil).toBe(true)
			end
			-- the floors upstairs: every one that stands, a landing on the open ones
			for k = 1, standing do
				local floorModel = building:FindFirstChild("Floor_" .. k)
				expect(floorModel.Slab.CanCollide).toBe(true)
				expect(floorModel:GetAttribute("Since")).toBe(H.sinceStanding(B, k))
				if k <= floors then
					local point = floorModel.Landing.PromptPoint
					expect(floorModel.Landing:GetAttribute("Floor")).toBe(k)
					expect(point.LiftPrompt.ActionText).toBe("Lift")
					expect(point.LiftPrompt:HasTag("LiftPrompt")).toBe(true)
					expect(point.EscortPrompt.Enabled).toBe(false)
					expect(point.EscortPrompt:HasTag("EscortPrompt")).toBe(true)
				else
					expect(floorModel:FindFirstChild("Landing")).toBeNil()
				end
			end
			expect(building:FindFirstChild("Floor_" .. (standing + 1))).toBeNil()
			-- the lift stands from Lv 1; its ground landing (and prompt) only once a floor opens
			expect(building.Lift.Shaft.CanCollide).toBe(true)
			expect(building.Lift.Car.CanCollide).toBe(false)
			expect(building.Lift.Car.DoorsGui.DoorL ~= nil and building.Lift.Car.DoorsGui.DoorR ~= nil).toBe(true)
			expect(building.Lift:HasTag("HospitalLift")).toBe(true)
			expect(building.Lift:GetAttribute("Ride")).toBe("")
			if floors >= 1 then
				expect(building.Landing_0:GetAttribute("Floor")).toBe(0)
				expect(building.Landing_0.PromptPoint.LiftPrompt.ActionText).toBe("Lift")
				-- the ground landing is 2.5 studs from the X-ray room's back wall and a prompt needs no line of sight:
				-- its prompts must not reach the X-ray bay's doctor spot (or anyone standing in that room), yet must
				-- reach the landing itself and the hall in front of the lift
				local point = building.Landing_0.PromptPoint
				local reach = point.LiftPrompt.MaxActivationDistance
				expect(point.EscortPrompt.MaxActivationDistance).toBe(reach)
				local px, pz = B.LANDING.X, B.LANDING.Z + point.Position.X -- the landing's X runs along +z
				local function away(x: number, z: number): number
					return math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
				end
				local spot = B.doctorSpot(B.bay("X"))
				expect(away(spot.X, spot.Z) > reach + 1).toBe(true)
				expect(away(B.LANDING.X, B.ROOMS.XRay.Z1 - 1.3) > reach).toBe(true) -- hugging the wall behind it
				expect(away(B.LANDING.X, B.LANDING.Z) < reach - 1).toBe(true)
				expect(away(B.SHAFT.X0 - 1.5, (B.DOORS.LiftLobby.Z0 + B.DOORS.LiftLobby.Z1) / 2) < reach).toBe(true)
				expect(pz < B.ROOMS.CorridorB.Z1 - 0.5).toBe(true) -- still in the hall
				-- upstairs nothing stands behind the landing: the usual reach, over its middle
				if floors >= 1 then
					local up = building.Floor_1.Landing.PromptPoint
					expect(up.Position.X).toBe(0)
					expect(up.LiftPrompt.MaxActivationDistance > reach).toBe(true)
				end
			else
				expect(building:FindFirstChild("Landing_0")).toBeNil()
			end
			-- the stairs: two half-flights a storey that stands, none above; none at all until floor 1 opens (the Stairs
			-- Model stays, empty: Joshua, "the stairs model is stupid. i can see it")
			expect(building.Stairs.ClassName).toBe("Model")
			if floors >= 1 then
				for k = 0, standing - 1 do
					expect(building.Stairs:FindFirstChild("Flight_" .. k .. "A").CanCollide).toBe(true)
					expect(building.Stairs:FindFirstChild("Flight_" .. k .. "B").CanCollide).toBe(true)
				end
				expect(building.Stairs:FindFirstChild("Flight_" .. standing .. "A")).toBeNil()
			else
				expect(#building.Stairs:GetChildren()).toBe(0)
			end
			-- the stairwell's door: a ClinicDoor, shut until floor 1 opens
			expect(building.Door_Stairs:HasTag("ClinicDoor")).toBe(true)
			expect(building.Door_Stairs:GetAttribute("State")).toBe(if floors >= 1 then "Shut" else "Locked")
			-- A&E from Lv 2, the roof deck at Lv 5
			if level >= Departments.AE.Opens then
				expect(building.AmbulanceBay.Ambulance:GetAttribute("ArriveAt")).toBe(0)
				expect(building.AmbulanceBay.StretcherSpot ~= nil).toBe(true)
				expect(building.AmbulanceBay:GetAttribute("Since")).toBe(Departments.AE.Opens)
			else
				expect(building:FindFirstChild("AmbulanceBay")).toBeNil()
			end
			expect(building:FindFirstChild("Roof") ~= nil).toBe(level >= 5)
			expect(building:FindFirstChild("Tower") ~= nil).toBe(level >= 5)
			expect(building:FindFirstChild("RoofTop") ~= nil).toBe(level < 5)
			if level >= 5 then
				expect(building.Roof.HeliSpot:GetAttribute("ArriveAt")).toBe(0)
			end
			-- the ward beds: Floor_<n>.BedSpot_<k>.Bed_<k> with Floor and Ward, as many as Data/Levels.Beds
			local beds = 0
			for k = 1, math.min(3, standing) do
				local floorModel = building:FindFirstChild("Floor_" .. k)
				for _, bed in B.wardBeds(level, k) do
					if bed.Functional then
						local spot = floorModel:FindFirstChild("BedSpot_" .. bed.Index)
						expect(spot:GetAttribute("Floor")).toBe(k)
						expect(spot:GetAttribute("Ward")).toBe(bed.Ward)
						local mattress = spot:FindFirstChild("Bed_" .. bed.Index)
						expect(mattress:GetAttribute("Floor")).toBe(k)
						expect(mattress:GetAttribute("Ward")).toBe(bed.Ward)
						beds += 1
					end
				end
			end
			expect(beds).toBe(LevelsData[level].Beds)
		end
		-- the bandages open with the Medical Centre, the X-ray room's cast table and bay with the Hospital
		expect(build(1).Station_Bandage:GetAttribute("Open")).toBe(false)
		expect(build(2).Station_Bandage:GetAttribute("Open")).toBe(true)
		expect(build(2).Station_Cast:GetAttribute("Open")).toBe(false)
		local lv3 = build(3)
		expect(lv3.Station_Cast:GetAttribute("Open")).toBe(true)
		expect(lv3.ExamBay_X:GetAttribute("Open")).toBe(true)
	end)

	test("the markers stand where Logic/Building says, facing its way", function()
		own({})
		local function at(p, x: number, y: number, z: number)
			local f = frameOf(p)
			if not (near(f.Position.X, x) and near(f.Position.Y, y) and near(f.Position.Z, z)) then
				error(string.format("%s at %s, not (%.2f, %.2f, %.2f)", fullName(p), tostring(f.Position), x, y, z))
			end
		end
		local function facing(p, face: number)
			local dx, dz = B.facing(face)
			local look = frameOf(p).LookVector
			if not (near(look.X, dx) and near(look.Z, dz)) then
				error(string.format("%s looks %s, not Face %d", fullName(p), tostring(look), face))
			end
		end
		for _, level in { 1, 3, 5 } do
			local building = build(level)
			for n, seat in B.SEATS do
				local p = building:FindFirstChild("WaitSeat_" .. n)
				at(p, seat.X, H.SEAT.Height + 0.5, seat.Z) -- resting on the seat
				facing(p, seat.Face)
			end
			for _, bay in B.BAYS do
				local model = building:FindFirstChild("ExamBay_" .. bay.Id)
				if model then
					at(model.Bed, bay.X, H.COUCH / 2, bay.Z)
					facing(model.Bed, bay.Face) -- toward the foot
					local r, lo, hi = boxOf(model.Bed)
					expect(inside(r, B.bayBed(bay), 0.01) and inside(B.bayBed(bay), r, 0.01)).toBe(true)
					expect(lo).toBeCloseTo(0, 3)
					expect(hi).toBeCloseTo(H.COUCH, 3)
					local spot = B.doctorSpot(bay)
					at(model.DoctorSpot, spot.X, 0.5, spot.Z)
					-- at the bed: from its foot, or (bay X) from its side, the Studio test's fix
					facing(model.DoctorSpot, if bay.Spot then 180 else (bay.Face + 180) % 360)
				end
			end
			for id in B.STATIONS do
				local r, lo = boxOf(building:FindFirstChild("Station_" .. id))
				expect(inside(r, B.stationRect(id), 0.01) and inside(B.stationRect(id), r, 0.01)).toBe(true)
				expect(lo).toBeCloseTo(0, 3)
			end
			at(building.ReceptionStop, B.RECEPTION.Stop.X, 0.5, B.RECEPTION.Stop.Z)
			facing(building.ReceptionStop, 180) -- at the desk
			at(building.ReceptionStaff, B.RECEPTION.Staff.X, 0.5, B.RECEPTION.Staff.Z)
			local front = B.DOORS.Front
			at(building.FrontDoor.Sensor, (front.X0 + front.X1) / 2, 0.5, front.Z)
			for k = 0, B.floors(level) do
				local landing = if k == 0 then building.Landing_0 else building:FindFirstChild("Floor_" .. k).Landing
				if landing then
					at(landing, LANDING.X, B.slabTop(k) + 0.5, LANDING.Z)
					facing(landing, 270) -- into the lift (its door is on the shaft's -x face)
				end
			end
			if building:FindFirstChild("AmbulanceBay") then
				local s = B.BAY_AMBULANCE.Stretcher
				at(building.AmbulanceBay.StretcherSpot, s.X, 0.5, s.Z)
				facing(building.AmbulanceBay.StretcherSpot, 270) -- at the A&E door
				local van = boxOf(building.AmbulanceBay.Ambulance.Body)
				expect(inside(van, B.BAY_AMBULANCE.Area)).toBe(true)
			end
			if level >= 5 then
				at(building.Roof.HeliSpot, B.HELI.X, B.slabTop(4) + 0.5, B.HELI.Z)
			end
		end
	end)

	test(
		"big from Lv 1: the ground's outer walls are Logic/Building's 96 x 66 footprint; upstairs the tower",
		function()
			own({})
			for _, level in LEVELS do
				local building = build(level)
				local function bounds(root)
					local out
					for _, p in root:GetChildren() do
						if p:IsA("BasePart") and p:GetAttribute("Outer") == true and string.match(p.Name, "^Wall") then
							local r = boxOf(p)
							out = if out
								then rect(
									math.min(out.X0, r.X0),
									math.max(out.X1, r.X1),
									math.min(out.Z0, r.Z0),
									math.max(out.Z1, r.Z1)
								)
								else r
						end
					end
					return out
				end
				local ground, f = bounds(building.Shell), B.footprint(level, 0)
				expect(inside(ground, f) and inside(f, ground)).toBe(true)
				expect({ f.X1 - f.X0, f.Z1 - f.Z0 }).toEqual({ 96, 66 }) -- the bigger, open clinic (was 64 x 44)
				for k = 1, math.min(3, H.standing(B, level)) do
					local storey = bounds(building:FindFirstChild("Floor_" .. k))
					expect(inside(storey, B.TOWER) and inside(B.TOWER, storey)).toBe(true)
				end
			end
		end
	)

	test(
		"budgets at every level and theme: parts, SurfaceGuis, see-through parts; no Texture, Decal, cross or Highlight",
		function()
			own({ "BathRoom", "Ward", "WinterWing", "Garden" })
			local lines = {}
			local worst = 0
			for _, theme in Themes.Order do
				for _, level in LEVELS do
					local building = build(level, theme)
					-- every theme carries the whole contract: the front doors, 6 seats, 7 bays and the 7 stations (the
					-- supply shelf's three, the Cast Table, the dispensary and the pantry's two)
					local seats, bays, stations = 0, 0, 0
					for _, child in building:GetChildren() do
						if string.match(child.Name, "^WaitSeat_%d+$") then
							seats += 1
						elseif string.match(child.Name, "^ExamBay_") then
							bays += 1
						elseif string.match(child.Name, "^Station_") then
							stations += 1
						end
					end
					expect({ seats, bays, stations }).toEqual({ 6, 7, 7 })
					expect(building:FindFirstChild("FrontDoor") ~= nil).toBe(true)
					local parts, guis, glassParts = 0, 0, 0
					for _, d in building:GetDescendants() do
						if d:IsA("BasePart") then
							parts += 1
							if seeThrough(d) then
								glassParts += 1
							end
						elseif d.ClassName == "SurfaceGui" then
							guis += 1
							expect(type(d.MaxDistance) == "number" and d.MaxDistance > 0).toBe(true)
						elseif d.ClassName == "Texture" or d.ClassName == "Decal" or d.ClassName == "Highlight" then
							error(string.format("Lv %d %s: a %s (%s)", level, theme, d.ClassName, fullName(d)))
						elseif d:IsA("Light") then
							expect(d.Shadows).toBe(false)
						end
						expect(string.find(string.lower(d.Name), "cross")).toBeNil()
						expect(string.find(string.lower(d.Name), "lego")).toBeNil()
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
					if glassParts > Config.Look.GlassPerBuilding then
						error(string.format("Lv %d %s: %d see-through parts", level, theme, glassParts))
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
								glassParts
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

	test("floors, slabs and flights are ceramic tiles (never wood); slabs on Logic/Building's tops", function()
		own({})
		for _, level in LEVELS do
			local building = build(level)
			for _, p in world.parts(building) do
				local name = p.Name
				local walkable = string.match(name, "^Floor")
					or string.match(name, "^Slab")
					or string.match(name, "^Flight_")
					or string.match(name, "^Mid_")
				if walkable then
					local deck = p:FindFirstAncestor("Floor_4") ~= nil
					local want = if deck then Enum.Material.SmoothPlastic else Enum.Material.CeramicTiles
					if p.Material ~= want then
						error(string.format("Lv %d: %s is %s", level, fullName(p), tostring(p.Material)))
					end
					if deck then
						expect(p.Color).toEqual(WORLD.Roof)
					end
				end
				expect(p.Material ~= Enum.Material.WoodPlanks or string.match(name, "^Shelf") ~= nil).toBe(true)
			end
			for k = 1, H.standing(B, level) do
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
				expect(slabs).toBe(#H.slabRects(B))
				local landing = floorModel:FindFirstChild("Landing")
				if landing then
					local r, lo = boxOf(landing)
					expect(lo).toBeCloseTo(B.slabTop(k), 4)
					expect(inside(r, boxOf(floorModel.Slab))).toBe(true)
				end
			end
			local floorGround = building.Shell.FloorGround
			expect(floorGround.Material).toBe(Enum.Material.CeramicTiles)
			expect(floorGround.CanCollide).toBe(false) -- painted on the pad: markers and patients stand at 0
		end
	end)

	test(
		"the nurses' station: a three-part desk on Logic/Building's NurseDesk, from Lv 1, no sign or emblem",
		function()
			for _, level in { 1, 5 } do
				local building = build(level)
				local station = building:FindFirstChild("NurseStation")
				expect(station ~= nil).toBe(true)
				expect(station:GetAttribute("Since")).toBe(1)
				expect(station:GetAttribute("Storey")).toBe(0)
				local parts = world.parts(station)
				expect(#parts).toBe(3)
				local desk = station:FindFirstChild("Desk")
				local r, y0, y1 = boxOf(desk)
				local want = B.NURSE_STATION.Desk
				expect(near(r.X0, want.X0) and near(r.X1, want.X1) and near(r.Z0, want.Z0) and near(r.Z1, want.Z1)).toBe(
					true
				)
				expect(near(y0, 0)).toBe(true)
				expect(near(y1, HospitalBuilder.Pure.NURSE_DESK)).toBe(true)
				expect(solid(desk)).toBe(true)
				for _, p in parts do
					if p ~= desk then
						expect(solid(p)).toBe(false) -- the countertop and the clipboard are walk-through
					end
				end
				for _, d in station:GetDescendants() do
					expect(d.ClassName ~= "SurfaceGui" and d.ClassName ~= "BillboardGui").toBe(true)
				end
			end
		end
	)

	test("everything solid at walking height is inside Logic/Building.obstacles (reach tells the truth)", function()
		own({}) -- every bought room's door shut: those (and only those) are solid outside obstacles
		local bad = {}
		for _, level in LEVELS do
			local building = build(level)
			for k = 0, B.floors(level) do
				local obstacles = B.obstacles(level, k)
				local f = B.footprint(level, k)
				local y = B.slabTop(k)
				for _, p in world.parts(building) do
					local door = p.Parent and p.Parent:GetAttribute("Room")
					if solid(p) and not door then
						local r, lo, hi = boxOf(p)
						if hi > y + 0.7 and lo < y + LOW_DOOR - 0.1 and inside(r, f) then
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
	end)

	test("closed doors are shut, solid and say why; open ones are walk-through and slide into their wall", function()
		local function door(building, name)
			local model = building:FindFirstChild(name)
			local panels = {}
			for _, child in model:GetChildren() do
				if child:IsA("BasePart") and child:GetAttribute("Slide") ~= nil then
					table.insert(panels, child)
				end
			end
			return model, panels
		end
		local function lockOf(panels)
			for _, p in panels do
				local gui = p:FindFirstChild("LockGui")
				if gui then
					return gui
				end
			end
			return nil
		end
		-- Lv 1, nothing bought: every door but the front is shut, and says what opens it
		own({})
		local building = build(1)
		local expected = {
			Door_AE = "Lv 2",
			Door_XRay = "Lv 3",
			Door_BathRoom = "💰 150",
			Door_WinterWing = "💰 500",
			Door_CozyWard = "💰 300",
			Door_Garden = "Lv 3",
			Door_Stairs = "Lv 2",
		}
		for name, words in expected do
			local model, panels = door(building, name)
			expect(model:GetAttribute("State")).toBe("Locked")
			expect(model:HasTag("ClinicDoor")).toBe(true)
			for _, p in panels do
				expect(p.CanCollide).toBe(true)
			end
			local gui = lockOf(panels)
			expect(gui ~= nil and gui.Enabled == true and gui.MaxDistance > 0).toBe(true)
			if not string.find(texts(gui), words, 1, true) then
				error(string.format("%s says %q, not %q", name, texts(gui), words))
			end
		end
		local _, frontPanels = door(building, "FrontDoor")
		expect(building.FrontDoor:GetAttribute("State")).toBe("Shut")
		expect(#frontPanels).toBe(2)
		for _, p in frontPanels do
			expect(p.CanCollide).toBe(false)
			expect(lockOf({ p })).toBeNil()
		end
		-- the stairwell's door says where it goes, on the hall's side; the lift's doors are drawn shut below the first
		-- open floor; the old stair gate is gone
		local _, stairPanels = door(building, "Door_Stairs")
		local stairGui = lockOf(stairPanels)
		expect(string.find(texts(stairGui), "Upstairs", 1, true) ~= nil).toBe(true)
		expect(stairGui.Face).toBe(Enum.NormalId.Front) -- the -z side: the hall behind the lift
		expect(building:FindFirstChild("StairGate", true)).toBeNil()
		expect(string.find(texts(building.Lift.Car.DoorsGui), "Lv 2", 1, true) ~= nil).toBe(true)
		-- Lv 3 with the Bath Room bought: A&E and X-ray open (no plate), the Bath Room's door unlocked, the others not
		own({ "BathRoom" })
		building = build(3)
		for _, name in { "Door_AE", "Door_XRay", "Door_BathRoom" } do
			local model, panels = door(building, name)
			expect(model:GetAttribute("State")).toBe("Shut")
			for _, p in panels do
				expect(p.CanCollide).toBe(false)
			end
			local gui = lockOf(panels)
			expect(gui == nil or gui.Enabled == false).toBe(true)
		end
		local garden, gardenPanels = door(building, "Door_Garden")
		expect(garden:GetAttribute("State")).toBe("Locked")
		expect(string.find(texts(lockOf(gardenPanels)), "💰 800", 1, true) ~= nil).toBe(true)
		local stairs = door(building, "Door_Stairs")
		expect(stairs:GetAttribute("State")).toBe("Shut")
		expect(string.find(texts(building.Lift.Car.DoorsGui), "🔒", 1, true)).toBeNil()
		-- every panel slides into the wall beside its doorway: its open place is inside an obstacle (a wall)
		local walls = B.obstacles(5, 0)
		for _, name in
			{
				"FrontDoor",
				"Door_AE",
				"Door_XRay",
				"Door_BathRoom",
				"Door_WinterWing",
				"Door_CozyWard",
				"Door_Garden",
				"Door_Stairs",
			}
		do
			local model, panels = door(building, name)
			expect(model.Sensor ~= nil).toBe(true)
			for _, p in panels do
				local cf = pivot:ToObjectSpace(p.CFrame * CFrame.new(p:GetAttribute("Slide")))
				local s = p.Size / 2
				local lo, hi
				for _, sx in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local c = cf * Vector3.new(sx * s.X, 0, sz * s.Z)
						lo = if lo then lo:Min(c) else c
						hi = if hi then hi:Max(c) else c
					end
				end
				local open = rect(lo.X, hi.X, lo.Z, hi.Z)
				local hidden = false
				for _, o in walls do
					hidden = hidden or (string.match(o.Name, "Wall$") ~= nil and inside(open, o, 0.02))
				end
				if not hidden then
					error(string.format("%s.%s slides out to %s", name, p.Name, T.show(open)))
				end
			end
		end
	end)

	test("exam bays: an open bay's curtain is drawn back, a closed one's drawn across with a 🔒 sign", function()
		-- The open bays (Joshua: "its very cramped"): curtains CURTAIN_HEIGHT high, and the number signs over them
		-- (bays 1-6: on their back wall; bay X: over its door), so a sign reads across corridor A over a drawn curtain.
		own({})
		for _, level in LEVELS do
			local building = build(level)
			for _, bay in B.BAYS do
				local model = building:FindFirstChild("ExamBay_" .. bay.Id)
				if model then
					local open = level >= bay.Opens
					local curtain = model.Curtain
					local width = math.max(curtain.Size.X, curtain.Size.Z)
					if open then
						expect(width <= 1.1).toBe(true)
					else
						expect(width >= 5).toBe(true)
					end
					local said = texts(model.Sign)
					if open then
						expect(said).toBe(if bay.Kind == "XRay" then "📸 X-ray" else bay.Id)
					else
						expect(said).toBe("🔒 Lv " .. bay.Opens)
					end
					for _, name in { "Pillow", "Curtain", "Tray", "Sign", "DoctorSpot" } do
						expect(model[name].CanCollide).toBe(false)
					end
					expect(model.Bed.CanCollide).toBe(true)
					local sign, signLo = boxOf(model.Sign)
					if bay.Kind == "XRay" then
						-- over its door, on the corridor's side
						expect(signLo >= H.DOOR).toBe(true)
						expect(sign.Z1 <= B.ROOMS.CorridorA.Z1 + 1e-3).toBe(true)
					else
						-- on the bays' back wall, in its own bay, high over the curtains (read over a drawn one)
						expect(signLo >= B.CURTAIN_HEIGHT + 1).toBe(true)
						expect(sign.Z1).toBeCloseTo(B.ROOMS.Bays.Z1 - B.PARTITION, 3)
						expect(inside(sign, rect(bay.X - B.BAY_WIDTH / 2, bay.X + B.BAY_WIDTH / 2, -100, 100))).toBe(
							true
						)
					end
					local room = if bay.Kind == "XRay" then B.ROOMS.XRay else B.ROOMS.Bays
					expect(inside(boxOf(curtain), room)).toBe(true)
					local _, _, curtainTop = boxOf(curtain)
					expect(curtainTop).toBeCloseTo(B.CURTAIN_HEIGHT, 3)
					expect(inside(boxOf(model.Tray), B.bayBed(bay))).toBe(true)
					if bay.Kind == "Exam" then
						local half = B.BAY_WIDTH / 2
						expect(inside(boxOf(curtain), rect(bay.X - half, bay.X + half, -100, 100))).toBe(true)
					end
				end
			end
		end
		-- the X-ray arm hangs over bay X's bed, clear of a sitting creature, and never stops anyone
		local building = build(3)
		local bay = B.bay("X")
		local headRect, headLo = boxOf(building.XRay.XRayHead)
		expect(overlaps(headRect, B.bayBed(bay))).toBe(true)
		expect(headLo >= H.COUCH + 6.5).toBe(true)
		expect(building.XRay.XRayHead.CanCollide).toBe(false)
		expect(building.XRay.XRayColumn.CanCollide).toBe(false)
	end)

	test(
		"the dog-leg stairs: each flight where Pure.ramp says, rails on every floor, the top floor railed round",
		function()
			own({})
			for _, level in { 2, 5 } do
				local building = build(level)
				local standing = H.standing(B, level)
				for k = 0, standing - 1 do
					for _, lane in { "A", "B" } do
						local p = building.Stairs:FindFirstChild("Flight_" .. k .. lane)
						local r, lo, hi = boxOf(p)
						local want = H.rampBox(H.ramp(B, k, lane), H.RAMP)
						expect(r.X0).toBeCloseTo(want.X0, 3)
						expect(r.X1).toBeCloseTo(want.X1, 3)
						expect(lo).toBeCloseTo(want.Y0, 3)
						expect(hi).toBeCloseTo(want.Y1, 3)
						local ramp = H.ramp(B, k, lane)
						expect(r.Z0).toBeCloseTo(ramp.Z0, 3)
						expect(r.Z1).toBeCloseTo(ramp.Z1, 3)
						expect(p:GetAttribute("Storey")).toBe(k)
						-- the ramp is walked on, never seen (Joshua: "look at how this block is glitchy")
						expect(p.Transparency).toBe(1)
						expect(p.CanCollide).toBe(true)
						expect(p.CastShadow).toBe(false)
						-- the steps you see: where Pure.steps says, across the ramp's width; solid blocks from the
						-- floor on the ground (nothing hides or walks in under the stairs), walk-through upstairs
						local steps = H.steps(B, k, lane)
						local count = 0
						for i, s in steps do
							local step = building.Stairs:FindFirstChild("Step_" .. k .. lane .. "_" .. (i - 1))
							if k == 0 and lane == "A" and i == 1 then
								expect(step).toBeNil() -- the ground itself is that tread
							else
								count += 1
								local sr, slo, shi = boxOf(step)
								expect(sr.X0).toBeCloseTo(s.X0, 3)
								expect(sr.X1).toBeCloseTo(s.X1, 3)
								expect(sr.Z0).toBeCloseTo(ramp.Z0, 3)
								expect(sr.Z1).toBeCloseTo(ramp.Z1, 3)
								expect(shi).toBeCloseTo(s.Top, 3)
								expect(slo).toBeCloseTo(if k == 0 then 0 else s.Top - s.Rise - H.WAIST, 3)
								expect(step.CanCollide).toBe(k == 0)
								expect(step.Material).toBe(Enum.Material.CeramicTiles)
								expect(step:GetAttribute("Storey")).toBe(k)
							end
						end
						expect(count).toBe(if k == 0 and lane == "A" then H.STEPS - 1 else H.STEPS)
					end
					local _, _, midTop = boxOf(building.Stairs:FindFirstChild("Mid_" .. k))
					expect(midTop).toBeCloseTo((B.slabTop(k) + B.slabTop(k + 1)) / 2, 3)
				end
				expect(building.Stairs:FindFirstChild("Flight_" .. standing .. "A")).toBeNil()
				expect(building.Stairs:FindFirstChild("StairSide")).toBeNil() -- the ground's steps fill that space
				local rails, ends = {}, 0
				for _, p in building.Stairs:GetChildren() do
					local r = boxOf(p)
					expect(inside(r, B.STAIRWELL)).toBe(true)
					if p.Name == "Rail" then
						rails[p:GetAttribute("Storey")] = true
					elseif p.Name == "RailEnd" or p.Name == "RailMid" then
						ends += 1
						expect(p:GetAttribute("Storey")).toBe(standing)
					end
				end
				for k = 0, standing do
					expect(rails[k]).toBe(true)
				end
				expect(ends).toBe(2)
				-- Nothing in the well reaches into anything else: no part's box (the ramps' included) overlaps a lane
				-- wall's, and no two visible parts overlap at all (they may touch).
				local walls, seen = {}, {}
				for _, p in building.Stairs:GetChildren() do
					if p:IsA("BasePart") then
						local b = box3(p)
						if p.Name == "StairWall" then
							table.insert(walls, b)
						end
						if p.Transparency < 1 then
							table.insert(seen, b)
						end
					end
				end
				expect(#walls).toBe(standing)
				local bad = {}
				for _, p in building.Stairs:GetChildren() do
					if p:IsA("BasePart") and p.Name ~= "StairWall" then
						for _, w in walls do
							local ox, oy, oz = overlap3(box3(p), w)
							if ox > 1e-3 and oy > 1e-3 and oz > 1e-3 then
								table.insert(bad, p.Name .. " in a StairWall")
							end
						end
					end
				end
				for i, a in seen do
					for j, b in seen do
						if i < j then
							local ox, oy, oz = overlap3(a, b)
							if ox > 1e-3 and oy > 1e-3 and oz > 1e-3 then
								table.insert(bad, a.P.Name .. " x " .. b.P.Name)
							end
						end
					end
				end
				expect(bad).toEqual({})
			end
		end
	)

	test(
		"no part thinner than 0.3 studs overlaps another part's box: thin strips touch, or hide wholly inside",
		function()
			-- Joshua (2026-11-17): "the purple bits are glitching". A thin strip sunk into a wall, or lying in a face's
			-- plane, flickers. Checked on every visible block lying square to the plot (a turned or round part's box is
			-- not its faces), at every level, with no room and every room bought. The painted floors are the one
			-- exception: thin, at a floor's own level, and everything stands through them.
			local function painted(x): boolean
				if x.Hi.Y - x.Lo.Y > 0.1 then
					return false
				end
				for k = 0, #B.SLAB_TOPS do
					local y = B.slabTop(k)
					if x.Lo.Y >= y - 1e-3 and x.Hi.Y <= y + 0.1 then
						return true
					end
				end
				return false
			end
			local bad = {}
			for _, rooms in { {}, { "BathRoom", "Ward", "WinterWing", "Garden" } } do
				own(rooms)
				for _, level in LEVELS do
					local blocks = {}
					for _, p in world.parts(build(level)) do
						if p.Transparency < 1 and squareBlock(p) then
							table.insert(blocks, box3(p))
						end
					end
					for _, a in blocks do
						local s = a.P.Size
						if math.min(s.X, s.Y, s.Z) < 0.3 then
							for _, b in blocks do
								if b ~= a then
									local ox, oy, oz = overlap3(a, b)
									local e = 0.005
									local hidden = a.Lo.X > b.Lo.X + e
										and a.Hi.X < b.Hi.X - e
										and a.Lo.Y > b.Lo.Y + e
										and a.Hi.Y < b.Hi.Y - e
										and a.Lo.Z > b.Lo.Z + e
										and a.Hi.Z < b.Hi.Z - e
									local paint = (painted(a) or painted(b)) and oy <= 0.1 + 1e-6
									if ox > 1e-3 and oy > 1e-3 and oz > 1e-3 and not hidden and not paint then
										table.insert(
											bad,
											string.format("Lv %d: %s x %s", level, fullName(a.P), fullName(b.P))
										)
									end
								end
							end
						end
					end
				end
			end
			expect(bad).toEqual({})
		end
	)

	test(
		"the stations look like the real thing: a cabinet, a freezer, open shelves, a table on legs, counters",
		function()
			-- Joshua (2026-11-17): "the texture of the cabinets / places to take the bandage should be improved. now its
			-- just a rectangular block". Each Station_<id> keeps its contract (its rect, from the floor) and wears its
			-- furniture as its own walk-through children, in its own colour; its badge floats over the furniture.
			local want = {
				Plaster = { "Door", "Knob", "Countertop", "PlasterBox", "PlasterBoxLid", "Plaster" },
				Ice = { "Lid", "Handle", "IceCube" },
				Bandage = { "ShelfSide", "ShelfBack", "ShelfBoard", "BandageRoll" },
				Cast = { "TableTop", "TableLeg", "TableShelf", "Tray", "CastRoll", "Bucket" },
				Remedy = { "Drawer", "Pull", "Countertop", "Bottle", "MeasuringCup" },
				-- the pantry (memory-20261117-006): a cocoa counter and a shelf of bath foam and towels
				Cocoa = { "Door", "Countertop", "CocoaPot", "CocoaPotLid", "Mug" },
				Bath = { "ShelfSide", "ShelfBack", "ShelfBoard", "FoamBottle", "Towel" },
			}
			-- the body is the part (else: an invisible box)
			local body = { Plaster = true, Ice = true, Remedy = true, Cocoa = true }
			own({})
			local counts = {}
			for _, level in LEVELS do
				local building = build(level)
				for id, names in want do
					local p = building:FindFirstChild("Station_" .. id)
					local r, _, hi = boxOf(p)
					expect(hi).toBeCloseTo(H.STATION[id], 3)
					local kinds = {}
					local top = hi
					for _, child in p:GetChildren() do
						if child:IsA("BasePart") then
							kinds[child.Name] = (kinds[child.Name] or 0) + 1
							-- walk-through: the station part is what stops you
							expect(child.CanCollide == false and child.CanQuery == false).toBe(true)
							-- close round its rect (a countertop's lip, a door, a pull)
							local cr, clo, chi = boxOf(child)
							expect(inside(cr, grow(r, 0.25))).toBe(true)
							expect(clo >= -1e-3).toBe(true)
							top = math.max(top, chi)
						end
					end
					for _, name in names do
						if not kinds[name] then
							error(string.format("Lv %d: Station_%s has no %s", level, id, name))
						end
					end
					-- the cabinet, the freezer and the counter are the part; the shelves and the table are open furniture
					-- round an invisible box
					expect(p.Transparency).toBe(if body[id] then 0 else 1)
					-- the badge floats over the furniture, never inside it
					local badge = p.IconGui
					expect(p.Position.Y + badge.StudsOffsetWorldSpace.Y - 1.3 >= pivot.Position.Y + top - 0.01).toBe(
						true
					)
					-- a closed station is the same furniture (only its badge says 🔒)
					local n = #p:GetChildren()
					counts[id] = counts[id] or n
					expect(n).toBe(counts[id])
				end
				-- the bandage rolls are white, the shelves the station's colour (kids match a plan step to it)
				local bandage = building.Station_Bandage
				expect(bandage.BandageRoll.Color).toEqual(WORLD.Trim)
				expect(bandage.ShelfSide.Color ~= WORLD.Trim).toBe(true)
			end
		end
	)

	test(
		"every part has a Storey; outer walls are studded, the plot's colour and solid; roofs are World.Roof",
		function()
			own({})
			for _, level in LEVELS do
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
						expect(p.Material).toBe(Enum.Material.Plastic)
						expect(p.Color).toEqual(accent)
						expect(p.CanCollide).toBe(true)
					end
					if string.match(p.Name, "^Roof") or string.match(p.Name, "^Parapet") then
						expect(p.Color).toEqual(WORLD.Roof)
					end
					if p.Transparency < 1 and Look.maxChannel(p.Color) > 245 then
						error(string.format("Lv %d: %s is too bright", level, fullName(p)))
					end
				end
				expect(walls >= 10).toBe(true)
			end
		end
	)

	test(
		"night: the glass and ribbon windows are Windows, the neon paw-heart and the beacon Lamps, one light",
		function()
			own({})
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
			expect(lights).toBe(1)
			expect(building.Tower.LogoNeon.LogoGui.Mark.PawHeart ~= nil).toBe(true)
			for _, p in { building.FrontDoor.DoorL, building.FrontDoor.DoorR, building.Lift.Shaft } do
				expect(p:GetAttribute("NightKind")).toBe("Window")
			end
		end
	)

	test("room lights: shadowless, on Attachments: three on the ground and one in each indoor storey", function()
		own({})
		local building = build(5)
		local rooms = {}
		for _, d in building:GetDescendants() do
			if d:IsA("Attachment") and d.Name == "RoomLight" then
				local light = d:FindFirstChildWhichIsA("PointLight")
				expect(light ~= nil and light.Shadows == false).toBe(true)
				local owner = d.Parent and d.Parent.Parent
				table.insert(rooms, owner and owner.Name or "?")
			end
		end
		table.sort(rooms)
		expect(table.concat(rooms, ",")).toBe("Floor_1,Floor_2,Floor_3,Shell,Shell,Shell")
	end)

	test(
		"the wards look full: 4 beds a floor, one sleeper on each open floor, made-up beds never named Bed_",
		function()
			own({})
			for _, level in LEVELS do
				local building = build(level)
				for k = 1, math.min(3, H.standing(B, level)) do
					local floorModel = building:FindFirstChild("Floor_" .. k)
					local beds, sleepers = 0, 0
					for _, d in floorModel:GetDescendants() do
						if d:IsA("BasePart") and string.match(d.Name, "^Bed_%d+$") then
							beds += 1
						elseif string.match(d.Name, "^DressBed_%d+$") then
							beds += 1
						elseif d.Name == "Sleeper" then
							sleepers += 1
						end
						if d:FindFirstAncestor("Dressing") then
							expect(string.match(d.Name, "^Bed_%d+$")).toBeNil()
							expect(string.match(d.Name, "^BedSpot_")).toBeNil()
						end
						if d:IsA("BasePart") and d:FindFirstAncestor("Sleeper") then
							expect(d.CanCollide == false and d.CanQuery == false and d.CastShadow == false).toBe(true)
						end
						-- every bed stands on its floor
						if d:IsA("BasePart") and (d.Name == "Base" or string.match(d.Name, "^Bed_")) then
							local _, lo = boxOf(d)
							expect(lo >= B.slabTop(k) - 0.01).toBe(true)
						end
					end
					expect(beds).toBe(Config.Look.WardFloorBeds)
					local open = k <= B.floors(level)
					expect(sleepers).toBe(if open then Config.Look.Sleepers.Ward else Config.Look.Sleepers.Lv1)
				end
			end
		end
	)

	test("upstairs: each functional bed's foot is a straight walk from the landing, past nothing solid", function()
		own({})
		for level = 2, 5 do
			local building = build(level)
			for k = 1, math.min(3, B.floors(level)) do
				local floorModel = building:FindFirstChild("Floor_" .. k)
				local solids = solidsOn(building, k)
				local beds = 0
				for _, spot in floorModel:GetChildren() do
					local index = string.match(spot.Name, "^BedSpot_(%d+)$")
					if index then
						local bed = spot:FindFirstChild("Bed_" .. index)
						beds += 1
						-- Server/Patients.bedFoot: 1.6 past the mattress's -Z end
						local foot =
							pivot:PointToObjectSpace((bed.CFrame * CFrame.new(0, 0, -bed.Size.Z / 2 - 1.6)).Position)
						expect(foot.Z).toBeCloseTo(B.BED_FOOT_Z, 3)
						for _, s in solids do
							if crosses(LANDING, { X = foot.X, Z = foot.Z }, s.Rect, B.SKIM) then
								error(
									string.format(
										"Lv %d F%d: %s's foot: the walk crosses %s",
										level,
										k,
										bed.Name,
										fullName(s.Part)
									)
								)
							end
						end
					end
				end
				local functional = 0
				for _, bed in B.wardBeds(level, k) do
					if bed.Functional then
						functional += 1
					end
				end
				expect(beds).toBe(functional)
			end
		end
	end)

	test("bed spots stay put (the same parts, the same place) across Lv 2 -> 5 and a theme change", function()
		own({})
		build(2)
		local first = plot.Building.Floor_1.BedSpot_1
		local at = pivot:PointToObjectSpace(first.Bed_1.Position)
		expect(at.X).toBeCloseTo(B.WARD_BEDS[1][1].X, 3)
		expect(at.Z).toBeCloseTo(H.mattressZ(B), 3)
		for level = 3, 5 do
			expect(build(level, "Candy", level - 1).Floor_1.BedSpot_1).toBe(first)
		end
		local rest = plot.Building.Floor_2.BedSpot_2
		expect(build(5, "Space").Floor_2.BedSpot_2).toBe(rest)
		expect(plot.Building.Floor_1.BedSpot_1).toBe(first)
		expect(pivot:PointToObjectSpace(rest.Bed_2.Position).X).toBeCloseTo(B.WARD_BEDS[2][2].X, 3)
		expect(plot.Building:GetAttribute("GrewAt")).toBe(0)
	end)

	test(
		"a theme recolours only the Trim and Band parts (and adds its prop); the walls stay the plot's colour",
		function()
			own({})
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
			for _, level in LEVELS do
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
			expect(build(3, "Order"):GetAttribute("Theme")).toBe("Candy")
		end
	)

	test("the theme props: at most 6 parts, walk-through, up on the roof (or under its edge)", function()
		own({})
		for _, theme in Themes.Order do
			for _, level in LEVELS do
				local prop = build(level, theme):FindFirstChild("ThemeProp")
				if prop then
					local parts = world.parts(prop)
					expect(#parts <= 6).toBe(true)
					for _, p in parts do
						expect(p.CanCollide).toBe(false)
						local _, lo = boxOf(p)
						expect(lo >= H.DOOR).toBe(true)
					end
				end
			end
		end
	end)

	test(
		"the stairwell (Joshua: 'the stairs model is stupid. i can see it'): walled floor to ceiling on every storey",
		function()
			own({})
			for _, level in LEVELS do
				local building = build(level)
				local standing = H.standing(B, level)
				local well = building:FindFirstChild("Stairwell")
				expect(well ~= nil and well:GetAttribute("Since") == 1 and well:GetAttribute("Storey") == 0).toBe(true)
				-- every storey that stands (the roof deck: the stair head) carries the enclosure's two own walls, each
				-- from the slab's underside up to the next one's: every StairWall obstacle is covered on every floor
				for k = 0, math.min(standing, 3) do
					local base, top = H.wallBase(B, k), H.wallTop(B, k)
					local walls = {}
					for _, p in world.parts(well) do
						if p:GetAttribute("Storey") == k and string.match(p.Name, "^WallStairs") then
							local r, lo, hi = boxOf(p)
							expect(lo).toBeCloseTo(base, 3)
							expect(hi).toBeCloseTo(top, 3)
							expect(p.CanCollide).toBe(true)
							expect(p.Transparency).toBe(0)
							table.insert(walls, r)
						end
					end
					expect(#walls).toBe(#H.stairWalls(B))
					for _, o in B.obstacles(5, k) do
						if o.Name == "StairWall" then
							-- each stud of the obstacle is inside a built wall (the corner they share counts once)
							local x = o.X0 + 0.05
							while x < o.X1 do
								local z = o.Z0 + 0.05
								while z < o.Z1 do
									local found = false
									for _, r in walls do
										found = found
											or (
												x >= r.X0 - 1e-3
												and x <= r.X1 + 1e-3
												and z >= r.Z0 - 1e-3
												and z <= r.Z1 + 1e-3
											)
									end
									if not found then
										error(string.format("Lv %d storey %d: no wall at (%.2f, %.2f)", level, k, x, z))
									end
									z += 0.25
								end
								x += 0.25
							end
						end
					end
				end
				-- no two of its walls share volume (two faces in one plane flicker)
				local parts = world.parts(well)
				for i, a in parts do
					for j, b in parts do
						if i < j then
							local ox, oy, oz = overlap3(box3(a), box3(b))
							if ox > 1e-3 and oy > 1e-3 and oz > 1e-3 then
								error(string.format("Lv %d: %s x %s", level, fullName(a), fullName(b)))
							end
						end
					end
				end
				-- Lv 5: the stair head on the deck, walled all round under a roof, its back and +x walls on the parapets
				local head = building:FindFirstChild("StairHead")
				expect(head ~= nil).toBe(level >= 5)
				if head then
					local roof = head:FindFirstChild("RoofStairHead")
					local r, lo = boxOf(roof)
					expect(inside(B.ROOMS.Stairwell, r) and inside(r, B.ROOMS.Stairwell)).toBe(true)
					expect(lo).toBeCloseTo(B.slabTop(ROOF) + H.STAIR_HEAD, 3)
					for _, name in { "WallStairsBack", "WallStairsEnd" } do
						local _, wlo = boxOf(head:FindFirstChild(name))
						expect(wlo).toBeCloseTo(B.slabTop(ROOF) + H.PARAPET, 3)
					end
				end
			end
		end
	)

	test("a Lv 1 clinic shows no step: nothing of the flights is built, the door is shut, solid and signed", function()
		-- The camera's Invisicam makes the walls between it and the player see-through, so a flight behind a wall is
		-- not hidden: below Lv 2 none is built at all.
		own({})
		local building = build(1)
		for _, p in world.parts(building) do
			local r, _, hi = boxOf(p)
			if overlaps(r, B.STAIRWELL) and hi > 0.2 and hi < B.slabTop(1) - 0.1 then
				error("Lv 1: " .. fullName(p) .. " stands in the stairwell")
			end
			expect(string.match(p.Name, "^Step_") or string.match(p.Name, "^Flight_") or string.match(p.Name, "^Rail")).toBeNil()
		end
		local door = building.Door_Stairs
		local d = B.DOORS.Stairs
		local r, lo, hi = boxOf(door.Panel)
		expect(r.X1 - r.X0).toBeCloseTo(d.X1 - d.X0, 3)
		expect(r.X1 - r.X0 >= B.DOOR_WIDTH - 1e-6).toBe(true)
		expect(lo).toBeCloseTo(0, 3)
		expect(hi).toBeCloseTo(d.Height, 3)
		expect(door.Panel.CanCollide).toBe(true)
		expect(door:GetAttribute("Opens")).toBe(2)
		-- Lv 2: the flights are in, from that level on (Since), and the door is walk-through
		building = build(2)
		expect(building.Stairs:FindFirstChild("Flight_0A"):GetAttribute("Since")).toBe(2)
		expect(building.Door_Stairs.Panel.CanCollide).toBe(false)
	end)

	test("the open bays: dividers CURTAIN_HEIGHT high, nothing over the mouths, bay 1 nearest the lobby", function()
		own({})
		local building = build(5)
		local dividers = {}
		for _, p in building.Bays:GetChildren() do
			if p.Name == "BayDivider" then
				local r, lo, hi = boxOf(p)
				expect(lo).toBeCloseTo(0, 3)
				expect(hi).toBeCloseTo(B.CURTAIN_HEIGHT, 3)
				table.insert(dividers, r)
			end
			expect(p.Name ~= "BayHeader").toBe(true)
		end
		expect(#dividers).toBe(#B.BAY_DIVIDERS)
		for _, d in B.BAY_DIVIDERS do
			local found = false
			for _, r in dividers do
				found = found or (near(r.X0, d.X0) and near(r.X1, d.X1) and inside(r, d))
			end
			expect(found).toBe(true)
		end
		-- over the bays' mouths, between the curtains and the ceiling, nothing at all: you see over the row
		local bays = B.ROOMS.Bays
		local mouth = rect(bays.X0 + B.WALL, bays.X1 - B.PARTITION, bays.Z0 - 0.5, bays.Z0 + 0.5)
		for _, p in world.parts(building) do
			local r, lo, hi = boxOf(p)
			if p.Transparency < 1 and overlaps(r, mouth) and hi > B.CURTAIN_HEIGHT + 0.01 and lo < H.wallTop(B, 0) then
				error("over the bays' mouths: " .. fullName(p))
			end
		end
		-- bay 1 is the one at the lobby's end (+x)
		expect(building.ExamBay_1.Bed.Position.X ~= building.ExamBay_6.Bed.Position.X).toBe(true)
		local one = pivot:PointToObjectSpace(building.ExamBay_1.Bed.Position)
		local six = pivot:PointToObjectSpace(building.ExamBay_6.Bed.Position)
		expect(one.X > six.X).toBe(true)
	end)

	test(
		"every inside doorway: at least DOOR_WIDTH wide and its door's Height clear (the front pair stays 8)",
		function()
			-- Joshua (2026-11-17): "the door is narrow too". Nothing visible stands in a doorway under its Height except
			-- the door's own panels and sensor.
			own({ "BathRoom", "Ward", "WinterWing", "Garden" })
			for _, level in { 1, 5 } do
				local building = build(level)
				for name, d in B.DOORS do
					local width = if d.X0 then d.X1 - d.X0 else d.Z1 - d.Z0
					expect(width >= B.DOOR_WIDTH - 1e-6).toBe(true)
					expect(d.Height).toBe(if name == "Front" then 8 else B.DOOR_HEIGHT)
					if not d.Lift then
						local gap = if d.X0
							then rect(d.X0 + 0.05, d.X1 - 0.05, d.Z - 0.15, d.Z + 0.15)
							else rect(d.X - 0.15, d.X + 0.15, d.Z0 + 0.05, d.Z1 - 0.05)
						for _, p in world.parts(building) do
							local ownDoor = p.Parent and p.Parent:GetAttribute("Door") == name
							local r, lo, hi = boxOf(p)
							if
								not ownDoor
								and p.Transparency < 1
								and overlaps(r, gap)
								and lo < d.Height - 0.01
								and hi > 0.2
							then
								error(string.format("Lv %d: %s stands in the %s doorway", level, fullName(p), name))
							end
						end
					end
				end
			end
		end
	)

	test("the supply wall: six stations side by side in the recess, facing the bays; Remedy under the hatch", function()
		own({})
		local building = build(5)
		local recess = B.ROOMS.Supply
		local last
		for index, id in B.SUPPLY_ORDER do
			local p = building:FindFirstChild("Station_" .. id)
			local r = boxOf(p)
			expect(inside(r, recess)).toBe(true)
			-- its front is toward the bays (+z): the furniture's front faces (doors, drawers) are on that side
			local station = B.STATIONS[id]
			expect(station.Face).toBe(180)
			if last then
				expect(r.X1 <= last.X0 + 1e-3).toBe(true) -- from the lobby end toward the A&E door
			end
			last = r
			expect(index >= 1).toBe(true)
		end
		-- the hatch's glass stands over the Remedy counter, in the dispensary's wall along corridor A
		local glassR, glassLo, glassHi = boxOf(building.Dispensary.GlassHatch)
		local remedy = B.stationRect("Remedy")
		expect(glassR.X0 <= remedy.X0 and glassR.X1 >= remedy.X1).toBe(true)
		expect(glassLo).toBeCloseTo(H.HATCH.Sill, 3)
		expect(glassHi).toBeCloseTo(H.HATCH.Top, 3)
		expect((glassR.Z0 + glassR.Z1) / 2).toBeCloseTo(B.HATCH.Z, 3)
		-- the dispensary's door is an open doorway onto the lobby, signed on the lobby's side
		local lintel = building.Dispensary.LintelDispensary
		local _, lintelLo = boxOf(lintel)
		expect(lintelLo).toBeCloseTo(B.DOORS.Dispensary.Height, 3)
		expect(lintel.SignGui.Face).toBe(Enum.NormalId.Right)
	end)

	test(
		"the desk, the front path and the yard stay clear: outside the block only canopies, trim and the A&E bay",
		function()
			own({})
			local f = B.footprint(1, 0)
			local frontDoor = B.DOORS.Front
			local path = rect(frontDoor.X0, frontDoor.X1, -Config.Town.PlotSize / 2, f.Z0 - 0.3)
			local bad = {}
			for _, theme in { "Candy", "Arctic", "Royal" } do
				for _, level in LEVELS do
					for _, p in world.parts(build(level, theme)) do
						local r, lo, hi = boxOf(p)
						-- invisible markers (door sensors) and the painted floor (the desk stands on it) take no room
						local marker = p.Transparency >= 1 and p.CanCollide == false
						local low = lo < H.DOOR - 0.5 and hi > 0.2 and not marker
						if low and overlaps(r, B.RECEPTION.Desk) then
							table.insert(bad, string.format("Lv %d %s %s on the desk", level, theme, fullName(p)))
						end
						if low and overlaps(r, path) then
							table.insert(bad, string.format("Lv %d %s %s on the front path", level, theme, fullName(p)))
						end
						if low and not inside(r, grow(f, 0.3)) and not inside(r, B.BAY_AMBULANCE.Area) then
							table.insert(bad, string.format("Lv %d %s %s out in the yard", level, theme, fullName(p)))
						end
					end
				end
			end
			expect(bad).toEqual({})
		end
	)
end)
