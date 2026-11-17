--!nocheck
-- The clinic building's interface numbers (Logic/Building; Real Clinic build plan, contract C1; design §8 and §15):
-- the 96 x 66 block that stands whole from Lv 1, its rooms and doors, the 6 waiting seats, the 9 exam bays, the 7
-- stations, the lift, the enclosed stairwell and the wards upstairs, checked against Data/Levels and Config, and every
-- route a visit needs (door -> reception -> seat -> bay -> stations -> lift -> ward -> exit) with Building.reach and
-- Building.path.
-- The bigger, open building (docs/plan/2026-11-17-simple-start-design.md §4; memory-20261117-006; Joshua's notes in
-- logs/playtests/2026-11-17-clinic-feedback.md): corridors at least 10 wide, bays about 9, inside doors at least 6
-- wide and 10 tall, low dividers, the supply wall (every ground station side by side on one wall, 12 studs of open
-- floor in front, a short walk from the bays) and the stairwell shut behind a door until Lv 2.

local T = require("./expect")
local expect, test = T.expect, T.test

local Config = require("./config")
local Building = require("../src/shared/Logic/Building")
local Levels = require("../src/shared/Data/Levels")
local Departments = require("../src/shared/Data/Departments")
local Rooms = require("../src/shared/Data/Rooms")

local LEVELS = { 1, 2, 3, 4, 5 }
local ROOM_NAMES = {
	"Lobby",
	"Waiting",
	"Dispensary",
	"Bays",
	"Hall",
	"XRay",
	"BathRoom",
	"WinterWing",
	"CozyWard",
	"LiftCore",
	"Stairwell",
}
local SUPPLY_WALL = { "Remedy", "Plaster", "Ice", "Bandage", "Cocoa", "Bath" } -- side by side, from the lobby end
local CREATURE = 5 -- a patient is about 5 studs wide
local ALL_ROOMS = { Ward = true, BathRoom = true, WinterWing = true, Garden = true }

local function rect(x0, x1, z0, z1)
	return { X0 = x0, X1 = x1, Z0 = z0, Z1 = z1 }
end

local function around(p, half)
	return rect(p.X - half, p.X + half, p.Z - half, p.Z + half)
end

local function inside(a, b, slack)
	local s = slack or 1e-9
	return a.X0 >= b.X0 - s and a.X1 <= b.X1 + s and a.Z0 >= b.Z0 - s and a.Z1 <= b.Z1 + s
end

local function overlap(a, b)
	return a.X0 < b.X1 - 1e-6 and b.X0 < a.X1 - 1e-6 and a.Z0 < b.Z1 - 1e-6 and b.Z0 < a.Z1 - 1e-6
end

local function within(p, r)
	return p.X > r.X0 and p.X < r.X1 and p.Z > r.Z0 and p.Z < r.Z1
end

-- The obstacles at `level` on the ground, without the ones `skip(name)` names.
local function solids(level, skip)
	local out = {}
	for _, o in Building.obstacles(level, 0) do
		if not skip(o.Name) then
			table.insert(out, o)
		end
	end
	return out
end

-- Every leg of a path is a straight, clear walk.
local function walkable(from, path, level, floor)
	local at = from
	for _, point in path do
		if not Building.reach(at, point, level, floor) then
			return false
		end
		at = point
	end
	return true
end

-- A path's length from `from`.
local function walked(from, path)
	local total, at = 0, from
	for _, point in path do
		total += math.sqrt((point.X - at.X) ^ 2 + (point.Z - at.Z) ^ 2)
		at = point
	end
	return total
end

local function mustPath(label, from, to, level, floor)
	local path = Building.path(from, to, level, floor)
	if not path then
		error(string.format("no way %s at Lv %d", label, level))
	end
	if not walkable(from, path, level, floor) then
		error(string.format("the way %s at Lv %d crosses something solid", label, level))
	end
	local last = path[#path]
	expect({ last.X, last.Z }).toEqual({ to.X, to.Z })
	return path
end

T.describe("Building: the shape", function()
	test(
		"the footprint is 96 x 66 at every level (1.5x the old 64 x 44), big from Lv 1; upstairs is the tower",
		function()
			for _, level in LEVELS do
				local f = Building.footprint(level)
				expect(f).toEqual(rect(-48, 48, -36, 30))
				expect({ f.X1 - f.X0, f.Z1 - f.Z0 }).toEqual({ 64 * 1.5, 44 * 1.5 })
				expect(Building.footprint(level, 0)).toEqual(f)
				for k = 1, 4 do
					expect(Building.footprint(level, k)).toEqual(rect(-9.4, 48, -8, 30))
					expect(inside(Building.footprint(level, k), f)).toBe(true)
				end
			end
			-- the tower scaled with it: about 1.5x the old 37 x 25 each way, over the bays' row and everything behind it
			local t = Building.TOWER
			expect((t.X1 - t.X0) / 37 >= 1.4 and (t.X1 - t.X0) / 37 <= 1.6).toBe(true)
			expect((t.Z1 - t.Z0) / 25 >= 1.4 and (t.Z1 - t.Z0) / 25 <= 1.6).toBe(true)
			expect(t.Z0).toBe(Building.ROOMS.Bays.Z0)
			expect({ Building.HALF_X, Building.FRONT, Building.BACK }).toEqual({ 48, -36, 30 })
			expect({ Building.MIN_LEVEL, Building.MAX_LEVEL }).toEqual({ 1, 5 })
			expect(Building.footprint(0 / 0)).toEqual(Building.footprint(1))
		end
	)

	test("storeys: ground 12, upper 11; slab tops 12, 23, 34, 45", function()
		expect(Building.GROUND).toBe(12)
		expect(Building.STOREY).toBe(11)
		expect(Building.SLAB_TOPS).toEqual({ 12, 23, 34, 45 })
		expect(Building.slabTop(0)).toBe(0)
		for k = 1, 4 do
			expect(Building.slabTop(k)).toBe(Building.GROUND + (k - 1) * Building.STOREY)
		end
	end)

	test("a slab's underside is >= 10.4, above where Patients' ground raycasts start (+10)", function()
		expect(Building.SLAB_MAX).toBe(0.6)
		local underside = Building.slabTop(1) - Building.SLAB_MAX
		expect(underside >= 10.4 - 1e-9).toBe(true)
		expect(underside > 10).toBe(true)
	end)

	test("headroom: a 6.5-stud creature sitting on a bed (1.8 up) keeps 2 studs under every ceiling", function()
		for k = 1, 3 do
			local clearHeight = Building.slabTop(k + 1) - Building.SLAB_MAX - Building.slabTop(k)
			expect(clearHeight >= 1.8 + 6.5 + 2).toBe(true)
		end
		expect(Building.slabTop(1) - Building.SLAB_MAX >= 1.8 + 6.5 + 2).toBe(true)
	end)

	test("open floors follow Data/Levels; F1 stands (closed) at Lv 1 and the tower grows to three storeys", function()
		local standing = {}
		for level, row in Levels do
			expect(Building.floors(level)).toBe(row.Floors)
			standing[level] = Building.storeys(level)
			expect(Building.storeys(level) >= math.min(row.Floors, 3)).toBe(true)
		end
		expect(standing).toEqual({ 1, 1, 2, 3, 3 })
		expect(Building.WARD_FLOOR).toBe(Departments.Wards.Floor)
		expect(Departments.Rest.Floor).toBe(2)
		expect(Building.slabTop(Departments.Roof.Floor)).toBe(45) -- the roof deck
	end)

	test("the plot is 140 x 140 and the block keeps a yard on every side", function()
		expect(Config.Town.PlotSize).toBe(140)
		local half = Config.Town.PlotSize / 2
		local f = Building.footprint(1)
		expect(half + f.X0 >= 20 and half - f.X1 >= 20).toBe(true) -- the side yards (the ambulance bay is in one)
		expect(half + f.Z0 >= 25).toBe(true) -- the front garden and the path to the doors
		expect(half - f.Z1 >= 25).toBe(true) -- the back yard (the Sunny Garden)
	end)
end)

T.describe("Building: rooms and doors", function()
	test("the rooms of the sketch (and the corridors and halls) are inside the block and never overlap", function()
		local f = Building.footprint(1)
		for _, name in ROOM_NAMES do
			if not Building.ROOMS[name] then
				error("no room " .. name)
			end
		end
		for name, room in Building.ROOMS do
			expect(inside(room, f)).toBe(true)
			for other, b in Building.ROOMS do
				if name < other and overlap(room, b) then
					error(name .. " overlaps " .. other)
				end
			end
		end
	end)

	test("every room is roomy: at least 9 studs each way, and about 1.5x the old building's floor", function()
		for _, name in ROOM_NAMES do
			local room = Building.ROOMS[name]
			if room.X1 - room.X0 < 9 or room.Z1 - room.Z0 < 8.5 then
				error(name .. " is too small")
			end
		end
		-- the old 64 x 44 building's rooms (studs): each has at least 1.5x the floor now
		local old = {
			Waiting = 27.5 * 12,
			Lobby = 16.5 * 12,
			Dispensary = 20 * 12,
			XRay = 14.5 * 8.5,
			BathRoom = 14 * 11.5,
			WinterWing = 13 * 11.5,
			CozyWard = 14.4 * 11.5,
		}
		for name, area in old do
			local room = Building.ROOMS[name]
			local now = (room.X1 - room.X0) * (room.Z1 - room.Z0)
			if now < 1.5 * area then
				error(string.format("%s has %.0f square studs, under 1.5x its old %.0f", name, now, area))
			end
		end
	end)

	test("every corridor and hall is at least 10 studs wide, with nothing solid standing in that width", function()
		local r, w = Building.ROOMS, Building.WALL
		expect(Building.CORRIDOR_MIN).toBe(10)
		local min = Building.CORRIDOR_MIN
		expect(r.CorridorA.Z1 - r.CorridorA.Z0 >= min).toBe(true)
		expect(r.CorridorB.Z1 - r.CorridorB.Z0 >= min).toBe(true)
		expect(r.Hall.X1 - r.Hall.X0 >= min).toBe(true)
		expect(r.LiftCore.X1 - r.LiftCore.X0 >= min).toBe(true)
		-- the hall behind the lift is open to corridor B: together they are the width in front of the stairwell's door
		expect(r.LiftHall.Z1 - r.CorridorB.Z0 >= min).toBe(true)
		for _, level in LEVELS do
			-- corridor A, wall to wall, from the A&E door's wall to the nurses' station at its far end, past the X-ray
			-- door (the stations stand in their recess, not in it)
			local desk = Building.NURSE_STATION.Desk
			expect(desk.X0 > Building.DOORS.XRay.X1).toBe(true)
			expect(Building.clear(rect(r.CorridorA.X0 + w, desk.X0, r.CorridorA.Z0, r.CorridorA.Z1), level)).toBe(true)
			-- corridor B, from the -x wall to the lift's door
			expect(Building.clear(rect(r.CorridorB.X0 + w, r.CorridorB.X1, r.CorridorB.Z0, r.CorridorB.Z1), level)).toBe(
				true
			)
			-- the Hall between the corridors: nothing stands in it
			expect(Building.clear(rect(r.Hall.X0, r.Hall.X1, r.Hall.Z0, r.Hall.Z1), level)).toBe(true)
			-- the way to the Garden door and the hall behind the lift
			expect(Building.clear(rect(r.LiftCore.X0, r.LiftCore.X1, r.LiftCore.Z0, r.LiftCore.Z1 - w), level)).toBe(
				true
			)
			expect(Building.clear(rect(r.LiftHall.X0, r.LiftHall.X1 - w, r.LiftHall.Z0, r.LiftHall.Z1), level)).toBe(
				true
			)
		end
	end)

	test(
		"the bays are about 9 wide and open; their dividers and curtains are about 6 high, so you see over them",
		function()
			expect(Building.BAY_WIDTH >= 9 and Building.BAY_WIDTH <= 10).toBe(true)
			expect(Building.BAY_WIDTH >= Building.BAY_BED.Width + 4).toBe(true)
			expect(Building.CURTAIN_HEIGHT >= 5.5 and Building.CURTAIN_HEIGHT <= 6.5).toBe(true)
			expect(Building.CURTAIN_HEIGHT < Building.DOOR_HEIGHT).toBe(true)
			local bays = Building.ROOMS.Bays
			expect(#Building.BAY_DIVIDERS).toBe(5)
			-- each of bays 1-6 has its bed in the middle of a 9-stud clear width, between two dividers (or an end wall)
			local edges = { bays.X0 + Building.WALL, bays.X1 - Building.PARTITION }
			for _, d in Building.BAY_DIVIDERS do
				expect(d.X1 - d.X0).toBeCloseTo(Building.DIVIDER)
				expect({ d.Z0, d.Z1 }).toEqual({ bays.Z0, bays.Z1 })
				table.insert(edges, d.X0)
				table.insert(edges, d.X1)
			end
			table.sort(edges)
			for id = 1, 6 do
				local bay = Building.bay(tostring(id))
				local left, right = -math.huge, math.huge
				for _, edge in edges do
					if edge <= bay.X then
						left = math.max(left, edge)
					else
						right = math.min(right, edge)
					end
				end
				if right - left < 9 or right - left > 10 then
					error(string.format("bay %d is %.2f wide", id, right - left))
				end
				expect(math.abs((left + right) / 2 - bay.X) <= 0.2).toBe(true)
				-- roomy: 2 studs or more each side of the bed, and the doctor stands inside the bay
				local bed = Building.bayBed(bay)
				expect(bed.X0 - left >= 2 and right - bed.X1 >= 2).toBe(true)
				expect(within(Building.doctorSpot(bay), bays)).toBe(true)
			end
			-- bay 1 is the one nearest the lobby; the numbers run away from it
			for id = 2, 6 do
				expect(Building.bay(tostring(id)).X < Building.bay(tostring(id - 1)).X).toBe(true)
			end
			expect(Building.bay("1").X > Building.ROOMS.Lobby.X0 and Building.bay("1").X < Building.ROOMS.Lobby.X1).toBe(
				true
			)
		end
	)

	test(
		"the doors: the front pair in the middle, A&E on the -x wall; every one 6+ wide, the inside ones 10 tall",
		function()
			local d = Building.DOORS
			expect({ d.Front.X0, d.Front.X1 }).toEqual({ -4, 4 })
			expect(d.AE.X < -Building.HALF_X + Building.WALL).toBe(true)
			expect(d.AE.Opens).toBe(Departments.AE.Opens)
			expect(d.XRay.Opens).toBe(Departments.Imaging.Opens)
			expect({ Building.DOOR_WIDTH, Building.DOOR_HEIGHT }).toEqual({ 6, 10 })
			local names = {}
			for name, door in d do
				table.insert(names, name)
				-- the front pair stays 8 tall, under the canopy and the name sign; every other door is 10
				expect(door.Height).toBe(if name == "Front" then 8 else Building.DOOR_HEIGHT)
				expect(door.Height < Building.GROUND - Building.SLAB_MAX).toBe(true)
				local width = if door.X0 then door.X1 - door.X0 else door.Z1 - door.Z0
				if width < Building.DOOR_WIDTH - 1e-9 then -- the big creatures fit
					error(string.format("%s is %.1f wide", name, width))
				end
				if door.Room then
					expect(Rooms[door.Room] ~= nil).toBe(true)
				end
			end
			-- the names the code uses (Server/World/Doors, HospitalBuilder, PlotBuilder), and the stairwell's
			table.sort(names)
			expect(names).toEqual({
				"AE",
				"BathRoom",
				"CozyWard",
				"Dispensary",
				"Front",
				"Garden",
				"LiftLobby",
				"Stairs",
				"WinterWing",
				"XRay",
			})
			for _, name in { "BathRoom", "WinterWing", "CozyWard", "Garden" } do
				expect(d[name].Room ~= nil).toBe(true)
				expect(d[name].Opens).toBeNil()
			end
			-- a doorway is a gap in a wall that is there: each inside door lies in one of its room's walls
			local r = Building.ROOMS
			expect(d.Dispensary.X > r.Dispensary.X1 - Building.PARTITION and d.Dispensary.X < r.Dispensary.X1).toBe(
				true
			)
			expect(d.XRay.Z > r.XRay.Z0 and d.XRay.Z < r.XRay.Z0 + Building.PARTITION).toBe(true)
			expect(d.Stairs.Z > r.Stairwell.Z0 and d.Stairs.Z < r.Stairwell.Z0 + Building.PARTITION).toBe(true)
			for _, name in { "BathRoom", "WinterWing", "CozyWard" } do
				local room = r[if name == "CozyWard" then "CozyWard" else name]
				expect(d[name].Z > room.Z0 and d[name].Z < room.Z0 + Building.PARTITION).toBe(true)
				expect(d[name].X0 >= room.X0 + 1 and d[name].X1 <= room.X1 - 1).toBe(true)
			end
			-- the canopy covers the front doors, outside the façade, under the first slab
			local c = Building.CANOPY
			expect(c.X0 <= d.Front.X0 and c.X1 >= d.Front.X1).toBe(true)
			expect(c.Z1).toBe(Building.FRONT)
			expect(c.Y > d.Front.Height and c.Y < Building.GROUND).toBe(true)
		end
	)

	test("a door's two sides are open floor, the first one inside", function()
		local f = Building.footprint(1)
		for _, name in { "Front", "AE", "Garden" } do
			local inP, outP = Building.doorPoints(name)
			expect(within(inP, f)).toBe(true)
			expect(within(outP, f)).toBe(false)
			expect(Building.reach(outP, inP, 5)).toBe(true)
		end
		for name, room in
			{
				Dispensary = "Dispensary",
				XRay = "XRay",
				BathRoom = "BathRoom",
				WinterWing = "WinterWing",
				CozyWard = "CozyWard",
				Stairs = "Stairwell",
			}
		do
			local inP, outP = Building.doorPoints(name)
			expect(within(inP, Building.ROOMS[room])).toBe(true)
			expect(within(outP, Building.ROOMS[room])).toBe(false)
			expect(Building.reach(outP, inP, 5)).toBe(true)
		end
		expect((Building.doorPoints("LiftLobby"))).toBeNil()
		expect((Building.doorPoints("Nope"))).toBeNil()
	end)

	test("shut doors are solid: A&E and the stairwell below Lv 2, the X-ray room below Lv 3", function()
		local function has(level, name)
			for _, o in Building.obstacles(level, 0) do
				if o.Name == name then
					return true
				end
			end
			return false
		end
		expect(has(1, "Door_AE")).toBe(true)
		expect(has(2, "Door_AE")).toBe(false)
		expect(has(2, "Door_XRay")).toBe(true)
		expect(has(3, "Door_XRay")).toBe(false)
		expect(has(1, "Door_Stairs")).toBe(true)
		expect(has(2, "Door_Stairs")).toBe(false)
		local aeIn, aeOut = Building.doorPoints("AE")
		expect(Building.reach(aeOut, aeIn, 1)).toBe(false)
		expect(Building.reach(aeOut, aeIn, 2)).toBe(true)
		local xIn, xOut = Building.doorPoints("XRay")
		expect(Building.reach(xOut, xIn, 2)).toBe(false)
		expect(Building.reach(xOut, xIn, 3)).toBe(true)
		-- not even at the seam between the wall and the shut door
		expect(Building.reach({ X = 30, Z = -14 }, { X = 36, Z = -5 }, 1)).toBe(false)
		expect(Building.reach({ X = 30, Z = -14 }, { X = 36, Z = -5 }, 3)).toBe(true)
	end)

	test("reception: the desk is in the lobby, the stop in front of it, the staff spot behind", function()
		local r = Building.RECEPTION
		expect(inside(r.Desk, Building.ROOMS.Lobby)).toBe(true)
		expect(r.Stop.Z < r.Desk.Z0 and r.Staff.Z > r.Desk.Z1).toBe(true)
		expect(r.Stop.X > r.Desk.X0 and r.Stop.X < r.Desk.X1).toBe(true)
		for _, level in LEVELS do
			expect(Building.clear(around(r.Stop, 1), level)).toBe(true)
			expect(Building.clear(around(r.Staff, 0.5), level)).toBe(true)
			expect(Building.clear(r.Desk, level)).toBe(false) -- the desk itself is solid
		end
		-- the desk is off the line from the doors into the hall
		expect(r.Desk.X0 >= Building.DOORS.Front.X1 - 1).toBe(true)
	end)
end)

T.describe("Building: seats, bays and stations", function()
	test("6 seats in the waiting room, a creature's width apart, each front spot on open floor", function()
		expect(#Building.SEATS).toBe(6)
		local bodies = {}
		for index, seat in Building.SEATS do
			local body = Building.seatRect(seat)
			expect(inside(body, Building.footprint(1))).toBe(true)
			expect(inside(body, Building.ROOMS.Waiting, 0.5)).toBe(true)
			expect(seat.Face % 90).toBe(0)
			local front = Building.seatFront(seat)
			expect(within(front, Building.ROOMS.Waiting)).toBe(true)
			for _, level in LEVELS do
				if not Building.clear(around(front, 0.5), level) then
					error("seat " .. index .. "'s front spot is covered at Lv " .. level)
				end
			end
			bodies[index] = body
		end
		for i, a in bodies do
			-- solid, but nothing else stands on it
			local others = solids(1, function(name)
				return name == "WaitSeat_" .. i
			end)
			for _, o in others do
				if overlap(a, o) then
					error("seat " .. i .. " overlaps " .. o.Name)
				end
			end
			for j = i + 1, #bodies do
				local s, t = Building.SEATS[i], Building.SEATS[j]
				local apart = math.max(math.abs(s.X - t.X), math.abs(s.Z - t.Z))
				expect(apart >= CREATURE + 0.5 - 1e-6).toBe(true)
			end
		end
	end)

	test("the 9 bays: 1-6, X (the X-ray room), W1 and W2 (the Cozy Ward), each bed in its room", function()
		local ids = {}
		for _, bay in Building.BAYS do
			table.insert(ids, bay.Id)
			expect(Building.bay(bay.Id)).toBe(bay)
			local bed = Building.bayBed(bay)
			expect(inside(bed, Building.footprint(1))).toBe(true)
			local room = if bay.Id == "X" then "XRay" elseif bay.Room then "CozyWard" else "Bays"
			expect(inside(bed, Building.ROOMS[room])).toBe(true)
			expect(bay.Kind).toBe(if bay.Id == "X" then "XRay" else "Exam")
			expect(bay.Room).toBe(if bay.Id == "W1" or bay.Id == "W2" then "Ward" else nil)
			expect(string.match(bay.Id, "^%w+$") ~= nil).toBe(true) -- ExamBay_<id>
			-- the bed is solid, and stands on nothing else
			for _, o in
				solids(5, function(name)
					return name == "Bed_" .. bay.Id
				end)
			do
				if overlap(bed, o) then
					error("bay " .. bay.Id .. "'s bed overlaps " .. o.Name)
				end
			end
		end
		expect(ids).toEqual({ "1", "2", "3", "4", "5", "6", "X", "W1", "W2" })
		expect(Building.bay("7")).toBeNil()
		expect(Rooms.Ward ~= nil).toBe(true)
	end)

	test(
		"from each station's stand, the station is nearer than any bay's DoctorSpot (both prompts are on E)",
		function()
			-- Roblox shows only the nearest prompt on a key: at the Cast Table the X-ray bay's prompt used to win, so a
			-- cast could not be taken (Studio test 2026-11-17). A margin of 1.5 studs covers standing a little off.
			for id in Building.STATIONS do
				local stand = Building.stationStand(id)
				local s = Building.STATIONS[id]
				local own = math.sqrt((stand.X - s.X) ^ 2 + (stand.Z - s.Z) ^ 2)
				for _, bay in Building.BAYS do
					local spot = Building.doctorSpot(bay)
					local other = math.sqrt((stand.X - spot.X) ^ 2 + (stand.Z - spot.Z) ^ 2)
					if other < own + 1.5 then
						error(
							string.format("at %s's stand, bay %s's prompt is %.1f away vs %.1f", id, bay.Id, other, own)
						)
					end
				end
			end
		end
	)

	test(
		"from each station's stand its own prompt is in reach, and no other station's is (through walls too)",
		function()
			-- Roblox shows one prompt per key. At the Cast Table the Bandage shelf's prompt (on the other side of the
			-- X-ray room's wall, centre to centre 4.3 vs 3.1) kept showing instead (Studio test 2026-11-17).
			for id in Building.STATIONS do
				local stand = Building.stationStand(id)
				local own = Building.stationPromptAt(id)
				local d = math.sqrt((stand.X - own.X) ^ 2 + (stand.Z - own.Z) ^ 2)
				expect(d < Building.PROMPT_REACH - 2).toBe(true)
				expect(Building.clear({ X0 = own.X - 0.1, X1 = own.X + 0.1, Z0 = own.Z - 0.1, Z1 = own.Z + 0.1 }, 5)).toBe(
					true
				)
				for other in Building.STATIONS do
					if other ~= id then
						local at = Building.stationPromptAt(other)
						local e = math.sqrt((stand.X - at.X) ^ 2 + (stand.Z - at.Z) ^ 2)
						if e < d + 2 or e < 2 * d then -- the alcove: 1.4 vs 3.6 across it; the old Cast case: 3.1 vs 4.3
							error(
								string.format(
									"at %s's stand, %s's prompt is %.1f away vs its own %.1f",
									id,
									other,
									e,
									d
								)
							)
						end
					end
				end
			end
			-- the case that was broken
			local stand = Building.stationStand("Cast")
			local bandage = Building.stationPromptAt("Bandage")
			expect(math.sqrt((stand.X - bandage.X) ^ 2 + (stand.Z - bandage.Z) ^ 2) > Building.PROMPT_REACH).toBe(true)
		end
	)

	test("each DoctorSpot is on open floor at the bed's foot (bay X: its side), with room for the doctor", function()
		for _, bay in Building.BAYS do
			local spot = Building.doctorSpot(bay)
			local bed = Building.bayBed(bay)
			expect(within(spot, bed)).toBe(false)
			if bay.Spot then
				-- bay X: beside the bed's -z side (Studio test 2026-11-17), 1.5..2.5 studs off it
				expect(bay.Id).toBe("X")
				expect(spot.X > bed.X0 and spot.X < bed.X1).toBe(true)
				local off = bed.Z0 - spot.Z
				expect(off >= 1.5 and off <= 2.5).toBe(true)
			else
				local dx, dz = Building.facing(bay.Face)
				local gap = (spot.X - bay.X) * dx + (spot.Z - bay.Z) * dz - Building.BAY_BED.Length / 2
				expect(gap).toBeCloseTo(Building.SPOT_GAP, 6)
				expect(gap >= 2).toBe(true)
			end
			for _, level in LEVELS do
				if not Building.clear(around(spot, 1), level) then
					error("bay " .. bay.Id .. "'s DoctorSpot is covered at Lv " .. level)
				end
			end
		end
	end)

	test("open bays follow Data/Levels.Bays (2, 3, 4, 5, 6); X from Lv 3; the Cozy Ward's two with the room", function()
		for level, row in Levels do
			local exam, xray, ward = 0, 0, 0
			for _, bay in Building.openBays(level, ALL_ROOMS) do
				if bay.Room then
					ward += 1
				elseif bay.Kind == "XRay" then
					xray += 1
				else
					exam += 1
				end
			end
			expect(exam).toBe(row.Bays)
			expect(xray).toBe(if level >= 3 then 1 else 0)
			expect(ward).toBe(2) -- they work from Lv 1 (design §15 #5)
			expect(#Building.openBays(level)).toBe(exam + xray) -- no rooms owned
			expect(#Building.openBays(level, { Ward = false })).toBe(exam + xray)
		end
		expect(Building.bayOpen(Building.bay("X"), 2)).toBe(false)
		expect(Building.bayOpen(Building.bay("X"), 3)).toBe(true)
		expect(Building.bayOpen(Building.bay("1"), 0 / 0)).toBe(true)
	end)

	test(
		"the 7 stations: the supply wall's six (the dispensary counter and the pantry among them) and the Cast table",
		function()
			-- the pantry (memory-20261117-006; tests/Pantry.spec): Cocoa and Bath, the supply wall's last two
			local where = {
				Remedy = "Supply",
				Plaster = "Supply",
				Ice = "Supply",
				Bandage = "Supply",
				Cocoa = "Supply",
				Bath = "Supply",
				Cast = "XRay",
			}
			local opens = {}
			for id, station in Building.STATIONS do
				opens[id] = station.Opens
				local body = Building.stationRect(id)
				expect(inside(body, Building.footprint(1))).toBe(true)
				expect(inside(body, Building.ROOMS[where[id]])).toBe(true)
				expect(station.Width).toBeNil() -- every one is STATION_SIZE.Width wide (the pantry's narrow units are gone)
				expect(string.match(id, "^%w+$") ~= nil).toBe(true) -- Station_<id>
				-- you stand in corridor A at the supply wall, and inside the X-ray room at the Cast table
				local stand = Building.stationStand(id)
				expect(within(stand, Building.ROOMS[if where[id] == "Supply" then "CorridorA" else "XRay"])).toBe(true)
				for _, level in LEVELS do
					if not Building.clear(around(stand, 0.8), level) then
						error(id .. "'s standing spot is covered at Lv " .. level)
					end
				end
				for _, o in
					solids(5, function(name)
						return name == "Station_" .. id
					end)
				do
					if overlap(body, o) then
						error("Station_" .. id .. " overlaps " .. o.Name)
					end
				end
			end
			-- simple start (memory-20261117-006): Lv 1 has only the Plaster shelf and the dispensary
			-- (the pantry's two are Lv 1 by level, and shut until their room is owned)
			expect(opens).toEqual({ Plaster = 1, Ice = 2, Bandage = 2, Cast = 3, Remedy = 1, Cocoa = 1, Bath = 1 })
			expect(Building.stationOpen("Ice", 1)).toBe(false)
			expect(Building.stationOpen("Ice", 2)).toBe(true)
			expect(Building.stationOpen("Bandage", 1)).toBe(false)
			expect(Building.stationOpen("Bandage", 2)).toBe(true)
			expect(Building.stationOpen("Cast", 2)).toBe(false)
			expect(Building.stationOpen("Bath", 5)).toBe(false) -- the pantry's: only with the Bath Room
			expect(Building.stationOpen("Bath", 1, { BathRoom = true })).toBe(true)
			expect(Building.stationOpen("Pharmacy", 5)).toBe(false)
			expect(Building.stationRect("Pharmacy")).toBeNil()
			-- the dispensary counter is under the hatch in the dispensary's wall along corridor A
			local remedy, hatch, disp = Building.stationRect("Remedy"), Building.HATCH, Building.ROOMS.Dispensary
			expect(remedy.X0 >= hatch.X0 and remedy.X1 <= hatch.X1).toBe(true)
			expect(hatch.Z > disp.Z1 - Building.PARTITION and hatch.Z < disp.Z1).toBe(true)
			expect(remedy.Z0 - hatch.Z < 0.5).toBe(true)
			expect(hatch.X0 >= disp.X0 + 1 and hatch.X1 <= disp.X1 - Building.PARTITION).toBe(true)
			-- the Cast table stays in the X-ray room, against its corridor wall, clear of the door
			local cast = Building.stationRect("Cast")
			expect(cast.Z0).toBeCloseTo(Building.ROOMS.XRay.Z0 + Building.PARTITION)
			expect(cast.X1 <= Building.DOORS.XRay.X0 - 1).toBe(true)
		end
	)

	test(
		"the supply wall (Joshua: 'the alley way for the cabinets are narrow'): six side by side on ONE wall, 12 studs open in front",
		function()
			expect(Building.SUPPLY_ORDER).toEqual(SUPPLY_WALL)
			local recess, disp, hall = Building.ROOMS.Supply, Building.ROOMS.Dispensary, Building.ROOMS.CorridorA
			-- the recess is the strip between the dispensary's wall and corridor A, open to the corridor along its length
			expect({ recess.X0, recess.X1 }).toEqual({ disp.X0, disp.X1 })
			expect(recess.Z0).toBe(disp.Z1)
			expect(recess.Z1).toBe(hall.Z0)
			local last
			for _, id in SUPPLY_WALL do
				local station, body = Building.STATIONS[id], Building.stationRect(id)
				-- one wall, one line, one facing: nobody faces another across an alley
				expect(station.Face).toBe(180) -- toward the bays
				expect(body.Z0).toBeCloseTo(recess.Z0) -- its back on the dispensary's wall
				expect(body.Z1).toBeCloseTo(recess.Z1) -- its front flush with the corridor's edge
				expect(body.X1 - body.X0).toBeCloseTo(Building.STATION_SIZE.Width)
				if last then
					-- side by side from the lobby end, a gap between two bodies (no two faces in one plane)
					local gap = last.X0 - body.X1
					expect(gap >= 0.5 and gap <= 2).toBe(true)
				end
				last = body
				-- at least 12 studs of open floor in front, as wide as the station, at every level
				local front = rect(body.X0, body.X1, body.Z1, body.Z1 + 12)
				for _, level in LEVELS do
					if not Building.clear(front, level) then
						error(id .. " has less than 12 studs of open floor in front at Lv " .. level)
					end
				end
				-- nothing faces it within those 12 studs: no other station stands in that strip
				for other in Building.STATIONS do
					if other ~= id then
						expect(overlap(front, Building.stationRect(other))).toBe(false)
					end
				end
			end
			-- no station anywhere faces another's front (the old alcove: Plaster and Ice faced Bandage 4.7 apart)
			for id in Building.STATIONS do
				local stand = Building.stationStand(id)
				for other in Building.STATIONS do
					if other ~= id then
						local body = Building.stationRect(other)
						local dx = math.max(body.X0 - stand.X, 0, stand.X - body.X1)
						local dz = math.max(body.Z0 - stand.Z, 0, stand.Z - body.Z1)
						expect(math.sqrt(dx * dx + dz * dz) >= 2).toBe(true)
					end
				end
			end
			-- the pantry's two stand beside the supplies, the last on the wall
			expect({ SUPPLY_WALL[5], SUPPLY_WALL[6] }).toEqual(Building.PANTRY_ORDER)
			-- the Lv 1 stations are the two nearest the lobby (and bay 1)
			expect({ SUPPLY_WALL[1], SUPPLY_WALL[2] }).toEqual({ "Remedy", "Plaster" })
		end
	)

	test(
		"a short walk from the supplies to the bays: under 30 studs at Lv 1, under 48 from any bay to any station",
		function()
			-- The old building, 1.5x smaller: 34-51 studs from bays 1-2 to the Plaster shelf and the dispensary counter.
			local longest, longestLv1 = 0, 0
			for _, level in LEVELS do
				for _, bay in Building.openBays(level) do
					if bay.Kind == "Exam" then
						local spot = Building.doctorSpot(bay)
						local nearest = math.huge
						for _, id in SUPPLY_WALL do
							if Building.stationOpen(id, level, ALL_ROOMS) then
								local stand = Building.stationStand(id)
								local there =
									walked(spot, mustPath("from bay " .. bay.Id .. " to " .. id, spot, stand, level))
								local back =
									walked(stand, mustPath("from " .. id .. " to bay " .. bay.Id, stand, spot, level))
								expect(math.abs(there - back) < 0.01).toBe(true)
								nearest = math.min(nearest, there)
								longest = math.max(longest, there)
								if level == 1 and Building.stationOpen(id, 1) then -- a new clinic: no room owned
									longestLv1 = math.max(longestLv1, there)
								end
							end
						end
						-- every bay has a station it can use within 25 studs
						if nearest > 25 then
							error(
								string.format("Lv %d: bay %s is %.1f from its nearest station", level, bay.Id, nearest)
							)
						end
					end
				end
			end
			print(
				string.format(
					"    [walks] bay -> supply wall: at most %.1f at Lv 1, %.1f at any level",
					longestLv1,
					longest
				)
			)
			expect(longestLv1 <= 30).toBe(true)
			expect(longest <= 48).toBe(true)
		end
	)

	test("facing: 0 the street, 90 -x, 180 the back, 270 +x", function()
		expect({ Building.facing(0) }).toEqual({ 0, -1 })
		expect({ Building.facing(90) }).toEqual({ -1, 0 })
		expect({ Building.facing(180) }).toEqual({ 0, 1 })
		expect({ Building.facing(270) }).toEqual({ 1, 0 })
		expect({ Building.facing(360) }).toEqual({ 0, -1 })
	end)
end)

T.describe("Building.reach and path: the visit's routes cross no wall, seat, bed or shelf", function()
	local stop = Building.RECEPTION.Stop

	test("in through the front doors to the reception stop, then straight to every seat's front spot", function()
		local doorIn, doorOut = Building.doorPoints("Front")
		for _, level in LEVELS do
			expect(Building.reach(doorOut, doorIn, level)).toBe(true)
			expect(Building.reach(doorIn, stop, level)).toBe(true)
			for index, seat in Building.SEATS do
				if not Building.reach(stop, Building.seatFront(seat), level) then
					error("no straight walk from the stop to seat " .. index .. " at Lv " .. level)
				end
			end
		end
	end)

	test("from every seat to bays 1-6, from Lv 1: to the bay's mouth and straight in, never a detour", function()
		expect(#Building.BAY_MOUTHS).toBe(6)
		local worst = 1
		for _, level in LEVELS do
			for id = 1, 6 do
				local bay = Building.bay(tostring(id))
				local spot, mouth = Building.doctorSpot(bay), Building.BAY_MOUTHS[id]
				-- the mouth's waypoint: in corridor A, in front of the bay, a straight step from its DoctorSpot
				expect(mouth.X).toBe(bay.X)
				expect(within(mouth, Building.ROOMS.CorridorA)).toBe(true)
				expect(Building.reach(mouth, spot, level)).toBe(true)
				expect(Building.clear(around(mouth, 1), level)).toBe(true)
				for index, seat in Building.SEATS do
					local front = Building.seatFront(seat)
					local path = mustPath("from seat " .. index .. " to bay " .. id, front, spot, level)
					local straight = math.sqrt((front.X - spot.X) ^ 2 + (front.Z - spot.Z) ^ 2)
					local ratio = walked(front, path) / straight
					worst = math.max(worst, ratio)
					if #path > 3 or ratio > 1.1 then
						error(
							string.format(
								"seat %d to bay %d at Lv %d: %d legs, %.2fx the straight line",
								index,
								id,
								level,
								#path,
								ratio
							)
						)
					end
				end
			end
		end
		print(string.format("    [walks] seat -> bay: at most %.2fx the straight line", worst))
	end)

	test("from every seat a way to every bay that can be open (X from Lv 3, the Cozy Ward's from Lv 1)", function()
		for _, bay in Building.BAYS do
			for level = bay.Opens, 5 do
				for index, seat in Building.SEATS do
					mustPath(
						"from seat " .. index .. " to bay " .. bay.Id,
						Building.seatFront(seat),
						Building.doctorSpot(bay),
						level
					)
				end
			end
		end
		-- the X-ray room is shut below Lv 3
		for level = 1, 2 do
			expect(Building.path(Building.seatFront(Building.SEATS[1]), Building.doctorSpot(Building.bay("X")), level)).toBeNil()
		end
	end)

	test("from every bay: out of the front doors, and (from Lv 2) to the lift's landing", function()
		local _, doorOut = Building.doorPoints("Front")
		for _, bay in Building.BAYS do
			for level = bay.Opens, 5 do
				local spot = Building.doctorSpot(bay)
				mustPath("from bay " .. bay.Id .. " to the street", spot, doorOut, level)
				if level >= 2 then
					mustPath("from bay " .. bay.Id .. " to the lift", spot, Building.LANDING, level)
				end
			end
		end
	end)

	test("an ambulance patient: from the stretcher through the A&E door to every open bay (Lv 2+)", function()
		local stretcher = Building.BAY_AMBULANCE.Stretcher
		for _, bay in Building.BAYS do
			for level = math.max(2, bay.Opens), 5 do
				mustPath("from the ambulance to bay " .. bay.Id, stretcher, Building.doctorSpot(bay), level)
			end
		end
		expect(Building.path(stretcher, Building.doctorSpot(Building.bay("1")), 1)).toBeNil() -- the door is shut at Lv 1
	end)

	test("the doctor's walks: from every bay to every open station's standing spot, and back", function()
		for _, bay in Building.BAYS do
			for id, station in Building.STATIONS do
				local level = math.max(bay.Opens, station.Opens)
				local spot, stand = Building.doctorSpot(bay), Building.stationStand(id)
				mustPath("from bay " .. bay.Id .. " to " .. id, spot, stand, level)
				mustPath("from " .. id .. " to bay " .. bay.Id, stand, spot, level)
			end
		end
		expect(Building.path(Building.doctorSpot(Building.bay("1")), Building.stationStand("Cast"), 2)).toBeNil()
	end)

	test("the back rooms, the stairwell's door and the garden door are reachable from the lobby", function()
		local lobby = Building.RECEPTION.Stop
		for _, name in { "BathRoom", "WinterWing", "CozyWard", "Garden", "Dispensary" } do
			local inP, outP = Building.doorPoints(name)
			mustPath("to " .. name, lobby, if name == "Garden" then outP else inP, 1)
		end
		-- the stairwell's door, from outside (the stairs themselves open at Lv 2: the stairwell's own test)
		local _, stairsOut = Building.doorPoints("Stairs")
		mustPath("to the stairwell's door", lobby, stairsOut, 1)
		local landing = Building.STAIR_LANDING
		mustPath("to the stairs", lobby, { X = (landing.X0 + landing.X1) / 2, Z = landing.Z0 + 1 }, 2)
	end)

	test("walls, beds, seats and the shaft stop a straight walk", function()
		for _, level in LEVELS do
			expect(Building.reach({ X = 0, Z = -42 }, { X = 20, Z = -30 }, level)).toBe(false) -- the street wall
			expect(Building.reach({ X = 4.85, Z = -14 }, { X = 4.85, Z = 9 }, level)).toBe(false) -- over a bay bed
			expect(Building.reach({ X = -12, Z = 9 }, { X = -12, Z = 22 }, level)).toBe(false) -- a room wall
			expect(Building.reach({ X = -11.5, Z = -25 }, { X = -11.5, Z = -19 }, level)).toBe(false) -- the hatch is glass
			expect(Building.reach({ X = -60, Z = 0 }, { X = -40, Z = 0 }, level)).toBe(false) -- the -x wall
			expect(Building.reach(Building.LANDING, { X = 43, Z = 9 }, level)).toBe(false) -- into the shaft
			expect(Building.reach({ X = 28, Z = 22 }, { X = 40, Z = 26 }, level)).toBe(false) -- the flights
			expect(Building.reach({ X = 36, Z = 17 }, { X = 36, Z = 23 }, level)).toBe(false) -- the stairwell's wall
			expect(Building.reach({ X = 4.85, Z = -5.8 }, { X = -4.65, Z = -5.8 }, level)).toBe(false) -- a bay divider
			expect(Building.reach(stop, Building.SEATS[1], level)).toBe(false) -- a seat is solid
			expect(Building.clear(Building.SHAFT, level)).toBe(false)
		end
		expect(Building.SKIM > 0 and Building.SKIM <= 0.3).toBe(true)
	end)

	test("a floor that isn't open has nothing on it, and no way across it", function()
		expect(#Building.obstacles(1, 1)).toBe(0)
		expect(#Building.obstacles(2, 2)).toBe(0)
		expect(#Building.obstacles(4, 4)).toBe(0)
		expect(#Building.obstacles(5, 4) > 0).toBe(true)
	end)
end)

T.describe("Building: the lift, the stairs and the wards upstairs", function()
	test("the lift: the shaft inside the tower on every floor, its landing in front of its door", function()
		local s, l = Building.SHAFT, Building.LANDING
		expect(inside(s, Building.TOWER)).toBe(true)
		expect({ s.X1 - s.X0, s.Z1 - s.Z0 }).toEqual({ 8, 10 }) -- was 5 x 5: a big creature and its porter fit
		expect({ s.Z0, s.Z1 }).toEqual({ Building.ROOMS.CorridorB.Z0, Building.ROOMS.CorridorB.Z1 }) -- it ends corridor B
		expect(l.Size >= Building.DOOR_WIDTH).toBe(true)
		local landing = rect(l.X - l.Size / 2, l.X + l.Size / 2, l.Z - l.Size / 2, l.Z + l.Size / 2)
		expect(landing.X1).toBeCloseTo(s.X0, 6) -- right at the door, on the shaft's -x face
		expect(landing.Z0 >= s.Z0 and landing.Z1 <= s.Z1).toBe(true)
		local door = Building.DOORS.LiftLobby
		expect(door.X).toBe(s.X0)
		expect(door.Z0 >= s.Z0 and door.Z1 <= s.Z1).toBe(true)
		expect(l.Z > door.Z0 and l.Z < door.Z1).toBe(true)
		for _, level in LEVELS do
			expect(Building.clear(landing, level)).toBe(true)
		end
		expect(overlap(landing, Building.ATRIUM)).toBe(false)
	end)

	test("the stairs: a dog-leg of two lanes, never steeper than 1 in 2, inside the back wall", function()
		local a = Building.ATRIUM
		expect(inside(a, Building.TOWER)).toBe(true)
		expect(a.Z1).toBeCloseTo(Building.BACK - Building.WALL, 6) -- no flight or rail shares the wall's outer plane
		expect(a.X1).toBeCloseTo(Building.HALF_X - Building.WALL, 6)
		local laneA, laneB = Building.LANE_A, Building.LANE_B
		expect(laneA.X1 - laneA.X0).toBe(laneB.X1 - laneB.X0)
		local run = laneA.X1 - laneA.X0
		expect(Building.GROUND / 2 / run <= 0.5).toBe(true)
		expect(Building.STOREY / 2 / run <= 0.5).toBe(true)
		for _, lane in { laneA, laneB } do
			expect(lane.Z1 - lane.Z0 >= 4.5 - 1e-6).toBe(true) -- was 3
			expect(inside(lane, Building.STAIRWELL)).toBe(true)
		end
		expect(overlap(laneA, laneB)).toBe(false)
		for _, landing in { Building.STAIR_LANDING, Building.STAIR_MID } do
			expect(landing.X1 - landing.X0 >= 3 - 1e-6).toBe(true)
			expect(inside(landing, a)).toBe(true)
		end
		-- the landing is floor (you step onto it from the hall); the rest is solid on every floor
		for _, level in LEVELS do
			expect(Building.clear(Building.STAIR_LANDING, level)).toBe(true)
			expect(Building.clear(Building.STAIRWELL, level)).toBe(false)
		end
	end)

	test(
		"the stairwell (Joshua: 'the stairs model is stupid. i can see it. the door is narrow too'): enclosed on every side, on every floor",
		function()
			local well, atrium, door = Building.ROOMS.Stairwell, Building.ATRIUM, Building.DOORS.Stairs
			expect(inside(atrium, well)).toBe(true)
			expect(inside(well, Building.TOWER)).toBe(true)
			-- its door: at least 6 wide, 10 tall, in the wall onto the hall behind the lift, opening onto the LANDING
			-- (never onto a flight), shut until the first floor upstairs opens
			expect(door.X1 - door.X0 >= 6).toBe(true)
			expect(door.Height).toBe(10)
			expect(door.X0 >= Building.STAIR_LANDING.X0 and door.X1 <= Building.STAIR_LANDING.X1).toBe(true)
			local inP, outP = Building.doorPoints("Stairs")
			expect(within(inP, Building.STAIR_LANDING)).toBe(true)
			expect(within(outP, Building.ROOMS.LiftHall)).toBe(true)
			local opensAt
			for _, level in LEVELS do
				if not opensAt and Building.floors(level) >= 1 then
					opensAt = level
				end
			end
			expect(door.Opens).toBe(opensAt)
			expect(door.Opens).toBe(2)
			-- Every stud of the enclosure's four sides is inside something solid, from the ground to the roof deck: the
			-- stairwell's own two walls, the outer walls behind and beside, and (shut) its door. Open, the only gap is
			-- the doorway.
			local function gaps(level, floor)
				local obstacles = Building.obstacles(level, floor)
				local function solidAt(x, z)
					for _, o in obstacles do
						if
							o.Name ~= "Stairs"
							and x >= o.X0 - 1e-6
							and x <= o.X1 + 1e-6
							and z >= o.Z0 - 1e-6
							and z <= o.Z1 + 1e-6
						then
							return true
						end
					end
					return false
				end
				local open = {}
				local inset = 0.2 -- inside each wall's thickness
				local x = well.X0 + inset
				while x <= well.X1 - inset + 1e-6 do
					for _, z in { well.Z0 + inset, well.Z1 - inset } do
						if not solidAt(x, z) then
							table.insert(open, { X = x, Z = z })
						end
					end
					x += 0.1
				end
				local z = well.Z0 + inset
				while z <= well.Z1 - inset + 1e-6 do
					for _, side in { well.X0 + inset, well.X1 - inset } do
						if not solidAt(side, z) then
							table.insert(open, { X = side, Z = z })
						end
					end
					z += 0.1
				end
				return open
			end
			expect(#gaps(1, 0)).toBe(0) -- Lv 1: sealed. Nobody sees a step leading into a ceiling
			for level = 2, 5 do
				for floor = 0, Building.floors(level) do
					local open = gaps(level, floor)
					expect(#open > 0).toBe(true)
					for _, at in open do
						-- the doorway, and only the doorway, in the wall on the hall's side
						if
							not (
								at.X > door.X0 - 1e-6
								and at.X < door.X1 + 1e-6
								and at.Z < well.Z0 + Building.PARTITION
							)
						then
							error(
								string.format(
									"Lv %d F%d: the stairwell is open at (%.1f, %.1f)",
									level,
									floor,
									at.X,
									at.Z
								)
							)
						end
					end
				end
			end
			-- Lv 1: no way in from anywhere (the lobby, both corridors, the halls round it)
			local landing =
				{ X = (Building.STAIR_LANDING.X0 + Building.STAIR_LANDING.X1) / 2, Z = Building.STAIR_LANDING.Z0 + 2 }
			local from = { Building.RECEPTION.Stop, Building.LANDING, outP, { X = 19.2, Z = 25 }, { X = 44, Z = 17 } }
			for _, at in from do
				expect(Building.path(at, landing, 1)).toBeNil()
				expect(Building.reach(at, landing, 1)).toBe(false)
				mustPath("into the stairwell", at, landing, 2)
			end
			expect(Building.reach(outP, inP, 1)).toBe(false)
			expect(Building.reach(outP, inP, 2)).toBe(true)
		end
	)

	test("the ward beds carry Wards on F1 and Rest on F2 and F3, and add up to Data/Levels.Beds", function()
		for floor, beds in Building.WARD_BEDS do
			for _, bed in beds do
				expect(bed.Ward).toBe(if floor == 1 then "Wards" else "Rest")
			end
		end
		expect({ #Building.WARD_BEDS[1], #Building.WARD_BEDS[2], #Building.WARD_BEDS[3] }).toEqual({ 3, 2, 2 })
		expect(Departments.Wards.Floor).toBe(1)
		for level, row in Levels do
			local functional = 0
			for floor = 1, 3 do
				for _, bed in Building.wardBeds(level, floor) do
					expect(bed.Floor).toBe(floor)
					if bed.Functional then
						functional += 1
						expect(bed.Ward).toBe(if floor == 1 then "Wards" else "Rest")
						expect(Building.WARD_BEDS[floor][bed.Index].X).toBe(bed.X)
					else
						expect(bed.Ward).toBeNil()
					end
				end
			end
			expect(functional).toBe(row.Beds)
		end
		expect(Building.wardBeds(1)).toEqual({})
		expect(#Building.wardBeds(2)).toBe(Config.Look.WardFloorBeds)
		expect(Building.wardBeds(2, 2)).toEqual({})
		expect(Building.wardBeds(5, 4)).toEqual({}) -- the roof has no beds
	end)

	test(
		"no two beds on a floor overlap; each is inside the tower, off the shaft and the stairs, 2.5+ apart",
		function()
			for floor = 1, 3 do
				local beds = Building.wardBeds(5, floor)
				table.sort(beds, function(a, b)
					return a.X < b.X
				end)
				local f = Building.footprint(5, floor)
				for i, bed in beds do
					local r = Building.bedRect(bed.X)
					expect(r.X1 - r.X0).toBeCloseTo(4.4, 6)
					expect(r.Z1 - r.Z0).toBeCloseTo(7, 6)
					expect((r.Z0 + r.Z1) / 2).toBeCloseTo(bed.Z, 6)
					expect(r.X0 >= f.X0 + Building.WALL + 2 and r.X1 <= f.X1 - Building.WALL).toBe(true)
					expect(r.Z0).toBeCloseTo(f.Z0 + Building.WALL, 6) -- the pillow end against the street wall
					expect(overlap(r, Building.SHAFT)).toBe(false)
					expect(overlap(r, Building.ATRIUM)).toBe(false)
					if i > 1 then
						expect(bed.X - beds[i - 1].X - 2 * Building.BED_HALF >= 2.5).toBe(true)
					end
				end
			end
		end
	)

	test("upstairs a patient walks straight from the landing to every functional bed's foot", function()
		for level = 2, 5 do
			for floor = 1, math.min(3, Building.floors(level)) do
				for _, bed in Building.wardBeds(level, floor) do
					local x, z = Building.bedFoot(bed.X)
					expect(z).toBe(Building.BED_FOOT_Z)
					expect(z - Building.BED_Z1 >= 1.5).toBe(true)
					if bed.Functional and not Building.reach(Building.LANDING, { X = x, Z = z }, level, floor) then
						error(string.format("Lv %d F%d: no straight walk to bed %d", level, floor, bed.Index))
					end
				end
				-- and never onto a bed, through the shaft, into the stairwell or out through a wall
				expect(Building.reach(Building.LANDING, { X = 32.4, Z = -3 }, level, floor)).toBe(false)
				expect(Building.reach(Building.LANDING, { X = 43, Z = 9 }, level, floor)).toBe(false)
				expect(Building.reach(Building.LANDING, { X = 38, Z = 25 }, level, floor)).toBe(false)
				expect(Building.reach(Building.LANDING, { X = 36.4, Z = -14 }, level, floor)).toBe(false)
				expect(Building.reach(Building.LANDING, { X = -20, Z = 9 }, level, floor)).toBe(false)
				-- from the stairs' landing too (a player who walked up), out through the stairwell's open doorway
				local landing = Building.STAIR_LANDING
				local stairs = { X = (landing.X0 + landing.X1) / 2, Z = landing.Z0 + 2 }
				mustPath("from the stairs to the lift landing", stairs, Building.LANDING, level, floor)
				mustPath("from the lift landing to the stairs", Building.LANDING, stairs, level, floor)
			end
		end
	end)

	test("outside: the ambulance bay in the -x yard at the A&E door; the helipad on the roof deck", function()
		local bay = Building.BAY_AMBULANCE
		local half = Config.Town.PlotSize / 2 - 1.5 -- the pad
		expect(bay.Area.X1 < -Building.HALF_X).toBe(true)
		expect(bay.Area.X0 >= -half).toBe(true)
		expect(within({ X = bay.X, Z = bay.Z }, bay.Area)).toBe(true)
		expect(within(bay.Stretcher, bay.Area)).toBe(true)
		local door = Building.DOORS.AE
		expect(bay.Stretcher.Z > door.Z0 and bay.Stretcher.Z < door.Z1).toBe(true)
		expect(overlap(bay.Area, Building.footprint(1))).toBe(false)
		local h = Building.HELI
		local pad = rect(h.X - h.Size / 2, h.X + h.Size / 2, h.Z - h.Size / 2, h.Z + h.Size / 2)
		local roof = Building.footprint(5, 4)
		expect(inside(pad, rect(roof.X0 + 1, roof.X1 - 1, roof.Z0 + 1, roof.Z1 - 1))).toBe(true)
		expect(overlap(pad, Building.SHAFT)).toBe(false)
		expect(overlap(pad, Building.ATRIUM)).toBe(false)
		expect(Building.reach({ X = h.X, Z = h.Z }, Building.LANDING, 5, 4)).toBe(true) -- a VIP walks to the lift
	end)
end)
