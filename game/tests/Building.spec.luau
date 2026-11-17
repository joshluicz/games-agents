--!nocheck
-- The clinic building's interface numbers (Logic/Building; Real Clinic build plan, contract C1; design §8 and §15):
-- the 64 x 44 block that stands whole from Lv 1, its rooms and doors, the 6 waiting seats, the 9 exam bays, the 5
-- stations, the lift, the stairs and the wards upstairs, checked against Data/Levels and Config, and every route a
-- visit needs (door -> reception -> seat -> bay -> stations -> lift -> ward -> exit) with Building.reach and
-- Building.path.

local T = require("./expect")
local expect, test = T.expect, T.test

local Config = require("./config")
local Building = require("../src/shared/Logic/Building")
local Levels = require("../src/shared/Data/Levels")
local Departments = require("../src/shared/Data/Departments")
local Rooms = require("../src/shared/Data/Rooms")

local LEVELS = { 1, 2, 3, 4, 5 }
local ROOM_NAMES =
	{ "Lobby", "Waiting", "Dispensary", "Bays", "Supply", "XRay", "BathRoom", "WinterWing", "CozyWard", "LiftCore" }
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
	test("the footprint is 64 x 44 at every level, big from Lv 1; upstairs is the tower", function()
		for _, level in LEVELS do
			local f = Building.footprint(level)
			expect(f).toEqual(rect(-32, 32, -24, 20))
			expect({ f.X1 - f.X0, f.Z1 - f.Z0 }).toEqual({ 64, 44 })
			expect(Building.footprint(level, 0)).toEqual(f)
			for k = 1, 4 do
				expect(Building.footprint(level, k)).toEqual(rect(-5, 32, -5, 20))
				expect(inside(Building.footprint(level, k), f)).toBe(true)
			end
		end
		expect({ Building.HALF_X, Building.FRONT, Building.BACK }).toEqual({ 32, -24, 20 })
		expect({ Building.MIN_LEVEL, Building.MAX_LEVEL }).toEqual({ 1, 5 })
		expect(Building.footprint(0 / 0)).toEqual(Building.footprint(1))
	end)

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

	test("the plot is 110 x 110 and the block keeps a yard on every side", function()
		expect(Config.Town.PlotSize).toBe(110)
		local half = Config.Town.PlotSize / 2
		local f = Building.footprint(1)
		expect(half + f.X0 >= 20 and half - f.X1 >= 20).toBe(true) -- the side yards (the ambulance bay is in one)
		expect(half + f.Z0 >= 25).toBe(true) -- the front garden and the path to the doors
		expect(half - f.Z1 >= 25).toBe(true) -- the back yard (the Sunny Garden)
	end)
end)

T.describe("Building: rooms and doors", function()
	test("the ten rooms of the sketch (and the two corridors) are inside the block and never overlap", function()
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

	test("every room is roomy: at least 9 studs each way (a creature is 5 wide, a bed 7 long)", function()
		for _, name in ROOM_NAMES do
			local room = Building.ROOMS[name]
			if room.X1 - room.X0 < 9 or room.Z1 - room.Z0 < 8.5 then
				error(name .. " is too small")
			end
		end
		expect(Building.ROOMS.CorridorA.Z1 - Building.ROOMS.CorridorA.Z0 >= CREATURE + 1.5).toBe(true)
		expect(Building.ROOMS.CorridorB.Z1 - Building.ROOMS.CorridorB.Z0 >= CREATURE).toBe(true)
		expect(Building.BAY_WIDTH >= Building.BAY_BED.Width + 2).toBe(true)
	end)

	test("the doors: the front pair in the middle, A&E on the -x wall, each tall enough for a creature", function()
		local d = Building.DOORS
		expect({ d.Front.X0, d.Front.X1 }).toEqual({ -4, 4 })
		expect(d.AE.X < -Building.HALF_X + Building.WALL).toBe(true)
		expect(d.AE.Opens).toBe(Departments.AE.Opens)
		expect(d.XRay.Opens).toBe(Departments.Imaging.Opens)
		for name, door in d do
			expect(door.Height >= 8).toBe(true)
			expect(door.Height < Building.GROUND - Building.SLAB_MAX).toBe(true)
			local width = if door.X0 then door.X1 - door.X0 else door.Z1 - door.Z0
			if width < 3 then
				error(name .. " is too narrow")
			end
			if door.Room then
				expect(Rooms[door.Room] ~= nil).toBe(true)
			end
		end
		for _, name in { "BathRoom", "WinterWing", "CozyWard", "Garden" } do
			expect(d[name].Room ~= nil).toBe(true)
			expect(d[name].Opens).toBeNil()
		end
		-- the canopy covers the front doors, outside the façade, under the first slab
		local c = Building.CANOPY
		expect(c.X0 <= d.Front.X0 and c.X1 >= d.Front.X1).toBe(true)
		expect(c.Z1).toBe(Building.FRONT)
		expect(c.Y > d.Front.Height and c.Y < Building.GROUND).toBe(true)
	end)

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

	test("shut doors are solid: A&E below Lv 2, the X-ray room below Lv 3", function()
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
		local aeIn, aeOut = Building.doorPoints("AE")
		expect(Building.reach(aeOut, aeIn, 1)).toBe(false)
		expect(Building.reach(aeOut, aeIn, 2)).toBe(true)
		local xIn, xOut = Building.doorPoints("XRay")
		expect(Building.reach(xOut, xIn, 2)).toBe(false)
		expect(Building.reach(xOut, xIn, 3)).toBe(true)
		-- not even at the seam between the wall and the shut door
		expect(Building.reach({ X = 21, Z = -8.5 }, { X = 26, Z = -2.8 }, 1)).toBe(false)
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

	test("each DoctorSpot is on open floor at the bed's foot, with room for the doctor", function()
		for _, bay in Building.BAYS do
			local spot = Building.doctorSpot(bay)
			local bed = Building.bayBed(bay)
			expect(within(spot, bed)).toBe(false)
			local dx, dz = Building.facing(bay.Face)
			local gap = (spot.X - bay.X) * dx + (spot.Z - bay.Z) * dz - Building.BAY_BED.Length / 2
			expect(gap).toBeCloseTo(Building.SPOT_GAP, 6)
			expect(gap >= 2).toBe(true)
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

	test("the 5 stations: on the supply shelf, in the X-ray room and at the dispensary counter", function()
		local where = { Plaster = "Supply", Ice = "Supply", Bandage = "Supply", Cast = "XRay", Remedy = "Dispensary" }
		local opens = {}
		for id, station in Building.STATIONS do
			opens[id] = station.Opens
			local body = Building.stationRect(id)
			expect(inside(body, Building.footprint(1))).toBe(true)
			expect(inside(body, Building.ROOMS[where[id]])).toBe(true)
			expect(string.match(id, "^%w+$") ~= nil).toBe(true) -- Station_<id>
			local stand = Building.stationStand(id)
			expect(within(stand, Building.ROOMS[where[id]])).toBe(true)
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
		expect(opens).toEqual({ Plaster = 1, Ice = 1, Bandage = 2, Cast = 3, Remedy = 1 })
		expect(Building.stationOpen("Bandage", 1)).toBe(false)
		expect(Building.stationOpen("Bandage", 2)).toBe(true)
		expect(Building.stationOpen("Cast", 2)).toBe(false)
		expect(Building.stationOpen("Bath", 5)).toBe(false) -- the Bath Room's own (PlotBuilder)
		expect(Building.stationRect("Bath")).toBeNil()
		-- the alcove stays a passage between the two corridors: a creature fits between the shelves
		local plaster, bandage = Building.stationRect("Plaster"), Building.stationRect("Bandage")
		expect(bandage.X0 - plaster.X1 >= 4.5).toBe(true)
		-- the dispensary counter is behind the hatch onto the lobby
		local remedy, hatch = Building.stationRect("Remedy"), Building.HATCH
		expect(remedy.Z0 >= hatch.Z0 and remedy.Z1 <= hatch.Z1).toBe(true)
		expect(remedy.X0 - hatch.X < 0.5).toBe(true)
	end)

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

	test("from every seat a straight walk to the DoctorSpot of bays 1-6, from Lv 1", function()
		for _, level in LEVELS do
			for index, seat in Building.SEATS do
				local front = Building.seatFront(seat)
				for id = 1, 6 do
					local spot = Building.doctorSpot(Building.bay(tostring(id)))
					if not Building.reach(front, spot, level) then
						error(string.format("seat %d can't walk straight to bay %d at Lv %d", index, id, level))
					end
					expect(Building.path(front, spot, level)).toEqual({ spot })
				end
			end
		end
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

	test("the back rooms, the stairs and the garden door are reachable from the lobby", function()
		local lobby = Building.RECEPTION.Stop
		for _, name in { "BathRoom", "WinterWing", "CozyWard", "Garden", "Dispensary" } do
			local inP, outP = Building.doorPoints(name)
			mustPath("to " .. name, lobby, if name == "Garden" then outP else inP, 1)
		end
		local landing = Building.STAIR_LANDING
		mustPath("to the stairs", lobby, { X = (landing.X0 + landing.X1) / 2, Z = landing.Z0 + 1 }, 1)
	end)

	test("walls, beds, seats and the shaft stop a straight walk", function()
		for _, level in LEVELS do
			expect(Building.reach({ X = 0, Z = -30 }, { X = -15, Z = -15 }, level)).toBe(false) -- the street wall
			expect(Building.reach({ X = 0, Z = -8.5 }, { X = 0, Z = 6 }, level)).toBe(false) -- over a bay bed
			expect(Building.reach({ X = -8, Z = 6 }, { X = -8, Z = 15 }, level)).toBe(false) -- a room wall
			expect(Building.reach({ X = 16, Z = -19 }, { X = 8, Z = -19 }, level)).toBe(false) -- the hatch is glass
			expect(Building.reach({ X = -40, Z = 0 }, { X = -20, Z = 0 }, level)).toBe(false) -- the -x wall
			expect(Building.reach(Building.LANDING, { X = 29, Z = 6 }, level)).toBe(false) -- into the shaft
			expect(Building.reach({ X = 14.9, Z = 12 }, { X = 25, Z = 16 }, level)).toBe(false) -- the stairs
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
		expect({ s.X1 - s.X0, s.Z1 - s.Z0 }).toEqual({ 5, 5 })
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
			expect(lane.Z1 - lane.Z0 >= 3 - 1e-6).toBe(true)
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
				expect(Building.reach(Building.LANDING, { X = 21.6, Z = 0 }, level, floor)).toBe(false)
				expect(Building.reach(Building.LANDING, { X = 29, Z = 6 }, level, floor)).toBe(false)
				expect(Building.reach(Building.LANDING, { X = 24, Z = 16 }, level, floor)).toBe(false)
				expect(Building.reach(Building.LANDING, { X = 24.4, Z = -10 }, level, floor)).toBe(false)
				expect(Building.reach(Building.LANDING, { X = -10, Z = 6 }, level, floor)).toBe(false)
				-- from the stairs' landing too (a player who walked up)
				local stairs = { X = 14.9, Z = 12 }
				mustPath("from the stairs to the lift landing", stairs, Building.LANDING, level, floor)
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
