--!nocheck
-- Where hired nurses stand (Logic/Building: NURSE_STATION, NURSE_PLACES, NURSE_SHARES, nurseSlot, stationRank; Server/Nurses'
-- Pure.home reads them). Joshua, 2026-11-17, after playing: "nurses look like theyre in the middle of nowhere". Every
-- job's spots, for a full roster (Config.Roster.Max = 8) in any mix of jobs, are inside the clinic, clear of anything
-- solid, against a wall or a piece of furniture, off the corridors' centre lines, off the patients' walks, out of the
-- doorways, off every stand, prompt and DoctorSpot, apart from each other, near what they belong to, and every one
-- of them can walk to its work (Building.path).

local T = require("./expect")
local expect, test = T.expect, T.test

local B = require("../src/shared/Logic/Building")

local ROSTER = 8 -- Config.Roster.Max: at most this many nurses work at once
-- Janitor: a job with no place of its own (it waits at the station)
local JOBS = { "Healer", "Medic", "Porter", "Maker", "Cheerer", "Receptionist", "Janitor" }
local ALL_ROOMS = { Ward = true, BathRoom = true, WinterWing = true, Garden = true }
local PATH_CLEAR = 2 -- a nurse's spot is at least this far from any patient's walk (a patient is ~5 wide)
local KEEP_OFF = 2 -- ... and from a station's stand and prompt, a DoctorSpot, a seat's front, the reception stop
local DOOR_CLEAR = 2.5 -- ... and from either side of a doorway
local AGAINST = 1.5 -- a spot stands at most this far from a wall or a piece of furniture (never out in the open)

local function dist(a, b)
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end

local function toRect(p, r)
	local dx = math.max(r.X0 - p.X, 0, p.X - r.X1)
	local dz = math.max(r.Z0 - p.Z, 0, p.Z - r.Z1)
	return math.sqrt(dx * dx + dz * dz)
end

local function toSegment(p, a, b)
	local dx, dz = b.X - a.X, b.Z - a.Z
	local l2 = dx * dx + dz * dz
	local t = if l2 < 1e-9 then 0 else math.clamp(((p.X - a.X) * dx + (p.Z - a.Z) * dz) / l2, 0, 1)
	return math.sqrt((p.X - a.X - t * dx) ^ 2 + (p.Z - a.Z - t * dz) ^ 2)
end

local function within(p, r)
	return p.X > r.X0 and p.X < r.X1 and p.Z > r.Z0 and p.Z < r.Z1
end

local function name(spot)
	return string.format("(%.2f, %.2f)", spot.X, spot.Z)
end

-- Every slot there is: the station's and each job's own place's, with what it is.
local function everySlot()
	local out = {}
	for index, slot in B.NURSE_STATION.Slots do
		table.insert(out, { Slot = slot, Kind = "Station", Index = index })
	end
	for job, list in B.NURSE_PLACES do
		if not B.NURSE_SHARES[job] then -- a shared place's slots are listed once, under the job that owns it
			for index, slot in list do
				table.insert(out, { Slot = slot, Kind = job, Index = index })
			end
		end
	end
	return out
end

-- The patients' walks at a level (every room owned), as segments: in through the front doors to the reception
-- stop, to every seat's front and onto the seat, from every seat to every open bay, from every bay out of the front
-- doors, to the lift (Lv 2+) and to the back rooms' doors, and from the A&E door to every bay (Lv 2+).
local function patientWalks(level)
	local segments = {}
	local function walk(from, to)
		local path = B.path(from, to, level, 0)
		if path then
			local at = from
			for _, point in path do
				table.insert(segments, { at, point })
				at = point
			end
		end
	end
	local frontIn, frontOut = B.doorPoints("Front")
	local aeIn = B.doorPoints("AE")
	walk(frontOut, frontIn)
	walk(frontIn, B.RECEPTION.Stop)
	local bays = B.openBays(level, ALL_ROOMS)
	for _, seat in B.SEATS do
		local front = B.seatFront(seat)
		walk(B.RECEPTION.Stop, front)
		table.insert(segments, { front, { X = seat.X, Z = seat.Z } })
		for _, bay in bays do
			walk(front, B.doctorSpot(bay))
		end
	end
	for _, bay in bays do
		local spot = B.doctorSpot(bay)
		walk(spot, frontIn)
		if level >= 2 then
			walk(aeIn, spot)
			walk(spot, { X = B.LANDING.X, Z = B.LANDING.Z })
		end
		for _, door in { "BathRoom", "WinterWing", "CozyWard", "Garden" } do
			walk(spot, (B.doorPoints(door)))
		end
	end
	return segments
end

T.describe("Where nurses stand (Logic/Building.nurseSlot)", function()
	test(
		"the places: a station with 8 slots, 2 at the bays' end, 2 Porters', 2 Makers', 4 Cheerers', 3 Receptionists'",
		function()
			expect(#B.NURSE_STATION.Slots).toBe(ROSTER) -- a full roster of one job without a place fits at the station
			expect(#B.NURSE_PLACES.Healer).toBe(2)
			expect(B.NURSE_PLACES.Medic).toBe(B.NURSE_PLACES.Healer) -- Medics take what the Healers leave of it
			expect(B.NURSE_SHARES.Medic).toBe("Healer")
			expect(#B.NURSE_PLACES.Porter).toBe(2)
			expect(#B.NURSE_PLACES.Maker).toBe(2)
			expect(#B.NURSE_PLACES.Cheerer).toBe(#B.SEATS - 2) -- the gaps in the street wall's row of 5
			expect(#B.NURSE_PLACES.Receptionist).toBe(3)
			expect(B.NURSE_PLACES.Janitor).toBeNil() -- a job without a place waits at the station
			-- the first Receptionist stands on RECEPTION.Staff
			local first = B.NURSE_PLACES.Receptionist[1]
			expect(first.X).toBe(B.RECEPTION.Staff.X)
			expect(first.Z).toBe(B.RECEPTION.Staff.Z)
		end
	)

	test(
		"every slot is inside the clinic's front rooms, clear of anything solid at every level, facing square",
		function()
			local footprint = B.footprint(1, 0)
			local margin = B.WALL + B.NURSE_FOOT
			local f = B.NURSE_FOOT
			for _, entry in everySlot() do
				local s = entry.Slot
				expect(s.Face % 90).toBe(0)
				expect(
					s.X >= footprint.X0 + margin
						and s.X <= footprint.X1 - margin
						and s.Z >= footprint.Z0 + margin
						and s.Z <= footprint.Z1 - margin
				).toBe(true)
				-- never in a bought room (it may not be there), the dispensary or the X-ray room (the player's): the open
				-- hall, the Hall between the corridors, the supply wall's recess, and (Porters) corridor B, by the lift
				local inHall = false
				local rooms = { "Waiting", "Lobby", "CorridorA", "Supply", "Hall" }
				if entry.Kind == "Porter" then
					rooms = { "CorridorB" }
				end
				for _, room in rooms do
					inHall = inHall or within(s, B.ROOMS[room])
				end
				if not inHall then
					error(entry.Kind .. " " .. entry.Index .. " " .. name(s) .. " is not in the hall or the recess")
				end
				for level = B.MIN_LEVEL, B.MAX_LEVEL do
					if not B.clear({ X0 = s.X - f, X1 = s.X + f, Z0 = s.Z - f, Z1 = s.Z + f }, level) then
						error(
							entry.Kind .. " " .. entry.Index .. " " .. name(s) .. " stands in something at Lv " .. level
						)
					end
				end
			end
		end
	)

	test("every slot stands against a wall or furniture, never out in the open", function()
		for _, entry in everySlot() do
			local s = entry.Slot
			local nearest = math.huge
			for _, o in B.obstacles(1, 0) do
				nearest = math.min(nearest, toRect(s, o))
			end
			if nearest > AGAINST then
				error(string.format("%s %d %s is %.2f from anything", entry.Kind, entry.Index, name(s), nearest))
			end
		end
	end)

	test(
		"off the corridors' centre lines (corridor A's dead end past the X-ray door aside), the Hall's and the lobby's middle",
		function()
			-- Corridor A is a walkway from the A&E door to the X-ray door's far jamb; past it is a dead end.
			local walkwayEnd = B.DOORS.XRay.X1 :: number
			for _, entry in everySlot() do
				local s = entry.Slot
				for _, corridor in { "CorridorA", "CorridorB" } do
					local r = B.ROOMS[corridor]
					if within(s, r) then
						local mid = (r.Z0 + r.Z1) / 2
						if math.abs(s.Z - mid) < 1.5 and (corridor == "CorridorB" or s.X < walkwayEnd) then
							error(
								entry.Kind
									.. " "
									.. entry.Index
									.. " "
									.. name(s)
									.. " is on "
									.. corridor
									.. "'s centre line"
							)
						end
					end
				end
				if within(s, B.ROOMS.Hall) then
					-- only against the bays' end wall: the rest of the Hall is the way between the two corridors
					expect(s.X <= B.ROOMS.Hall.X0 + AGAINST).toBe(true)
				end
				if within(s, B.ROOMS.Lobby) then
					-- only behind the reception desk
					expect(toRect(s, B.RECEPTION.Desk) <= AGAINST).toBe(true)
				end
			end
		end
	)

	test("off the patients' walks at every level (the Receptionists' spots, behind the desk, aside)", function()
		local worst = math.huge
		for level = B.MIN_LEVEL, B.MAX_LEVEL do
			local walks = patientWalks(level)
			expect(#walks > 50).toBe(true)
			for _, entry in everySlot() do
				-- RECEPTION.Staff is where the Receptionist has always stood, at the desk patients walk past
				if entry.Kind ~= "Receptionist" then
					for _, seg in walks do
						local d = toSegment(entry.Slot, seg[1], seg[2])
						worst = math.min(worst, d)
						if d < PATH_CLEAR then
							error(
								string.format(
									"%s %d %s is %.2f from a patient's walk (%.1f, %.1f) -> (%.1f, %.1f) at Lv %d",
									entry.Kind,
									entry.Index,
									name(entry.Slot),
									d,
									seg[1].X,
									seg[1].Z,
									seg[2].X,
									seg[2].Z,
									level
								)
							)
						end
					end
				end
			end
		end
		expect(worst >= PATH_CLEAR).toBe(true)
	end)

	test("out of every doorway, off every stand, prompt, DoctorSpot, seat front and the reception stop", function()
		local keepOff = { B.RECEPTION.Stop, { X = B.LANDING.X, Z = B.LANDING.Z } }
		for id in B.STATIONS do
			table.insert(keepOff, B.stationStand(id))
			table.insert(keepOff, B.stationPromptAt(id))
		end
		for _, bay in B.BAYS do
			table.insert(keepOff, B.doctorSpot(bay))
		end
		for _, seat in B.SEATS do
			table.insert(keepOff, B.seatFront(seat))
		end
		for _, entry in everySlot() do
			local s = entry.Slot
			for _, p in keepOff do
				if dist(s, p) < KEEP_OFF then
					error(entry.Kind .. " " .. entry.Index .. " " .. name(s) .. " stands on " .. name(p))
				end
			end
			for doorName, door in B.DOORS do
				local inside, outside = B.doorPoints(doorName)
				for _, p in { inside, outside } do
					if p and dist(s, p) < DOOR_CLEAR then
						error(
							entry.Kind .. " " .. entry.Index .. " " .. name(s) .. " is in the " .. doorName .. " door"
						)
					end
				end
				-- nor in front of the doorway's span (2 studs either side of its wall)
				local strip = if door.X0
					then { X0 = door.X0, X1 = door.X1, Z0 = door.Z - 2, Z1 = door.Z + 2 }
					else { X0 = door.X - 2, X1 = door.X + 2, Z0 = door.Z0, Z1 = door.Z1 }
				expect(toRect(s, strip) >= B.NURSE_FOOT - 1e-6).toBe(true)
			end
		end
	end)

	test(
		"near what they belong to: the desk, the bays, the lift, the supply wall, the seats, the reception desk",
		function()
			local desk = B.NURSE_STATION.Desk
			for _, slot in B.NURSE_STATION.Slots do
				expect(toRect(slot, desk) <= 2 * B.NURSE_GAP).toBe(true)
				expect(slot.X > desk.X1).toBe(true) -- behind it (the end wall's side) ...
				expect(slot.Face).toBe(90) -- ... looking over it, down corridor A at the bays
			end
			-- Healers and Medics: a short walk from the bays every clinic has (the Phase 0 review: from the old station
			-- at corridor A's far end each heal was a ~50 stud commute), against the outside of bay 1's end wall
			local lv1 = B.openBays(1)
			expect(#lv1 >= 2).toBe(true)
			local longest = 0
			for _, slot in B.NURSE_PLACES.Healer do
				local at = { X = slot.X, Z = slot.Z }
				for _, bay in lv1 do
					local walk, from = 0, at
					for _, point in B.path(at, B.doctorSpot(bay), 1, 0) do
						walk += dist(from, point)
						from = point
					end
					longest = math.max(longest, walk)
				end
				expect(slot.X).toBeCloseTo(B.ROOMS.Bays.X1 + B.NURSE_EDGE)
				expect(within(slot, B.ROOMS.Hall)).toBe(true)
				expect(slot.Face).toBe(270) -- looking into the Hall
				-- beside the bays, never in front of a bay's mouth (the bays open onto corridor A at their Z0)
				expect(slot.Z > B.ROOMS.Bays.Z0 + 2 * B.NURSE_FOOT).toBe(true)
			end
			print(string.format("    [nurses] a Healer's longest walk to a Lv 1 bay: %.1f studs", longest))
			expect(longest <= 32).toBe(true)
			-- ... and the first Healer is nearer bay 1 than the lobby's reception desk is
			local first = B.NURSE_PLACES.Healer[1]
			expect(dist(first, B.doctorSpot(B.bay("1"))) < dist(B.RECEPTION.Staff, B.doctorSpot(B.bay("1")))).toBe(true)
			-- Porters: one straight walk from the lift's ground landing (no wall to walk through: the review), against
			-- the X-ray room's back wall, facing across corridor B
			local landing = { X = B.LANDING.X, Z = B.LANDING.Z }
			for level = B.MIN_LEVEL, B.MAX_LEVEL do
				for _, slot in B.NURSE_PLACES.Porter do
					local at = { X = slot.X, Z = slot.Z }
					expect(B.reach(at, landing, level, 0)).toBe(true)
					expect(B.reach(landing, at, level, 0)).toBe(true)
					expect(dist(at, landing) <= 8).toBe(true)
					expect(dist(at, landing) >= B.LANDING.Size / 2 + 2 * B.NURSE_FOOT).toBe(true) -- off the landing itself
					expect(slot.Z).toBeCloseTo(B.ROOMS.XRay.Z1 + B.NURSE_EDGE)
					expect(slot.X > B.ROOMS.XRay.X0 and slot.X < B.SHAFT.X0).toBe(true)
					expect(slot.Face).toBe(180)
				end
			end
			-- Makers: in the supply wall's recess, beside its last station, nobody's stand in front of them
			local order = B.SUPPLY_ORDER
			local shelf = B.stationRect(order[#order])
			for index, slot in B.NURSE_PLACES.Maker do
				expect(toRect(slot, shelf) <= AGAINST + (index - 1) * B.NURSE_GAP).toBe(true)
				expect(within(slot, B.ROOMS.Supply)).toBe(true)
				expect(slot.X < shelf.X0).toBe(true) -- past the last one, away from the lobby
				expect(slot.Face).toBe(180) -- looking out at the bays, like the stations
			end
			for _, slot in B.NURSE_PLACES.Cheerer do
				local seats = 0
				for _, seat in B.SEATS do
					if toRect(slot, B.seatRect(seat)) <= 2.5 then
						seats += 1
					end
				end
				expect(seats).toBe(2) -- between two seats
				expect(within(slot, B.ROOMS.Waiting)).toBe(true)
				expect(slot.Face).toBe(180) -- looking into the room, like the seats
			end
			for _, slot in B.NURSE_PLACES.Receptionist do
				expect(toRect(slot, B.RECEPTION.Desk) <= AGAINST).toBe(true)
				expect(slot.Z > B.RECEPTION.Desk.Z1).toBe(true) -- behind it
				expect(slot.Face).toBe(0) -- facing the lobby
			end
		end
	)

	test("the desk: against the X-ray room's wall at corridor A's far end, solid, overlapping nothing", function()
		local desk = B.NURSE_STATION.Desk
		local hall = B.ROOMS.CorridorA
		expect(desk.Z1).toBe(hall.Z1) -- one end on the X-ray room's wall: nobody walks through behind it
		expect(desk.X0 >= (B.DOORS.XRay.X1 :: number) + 2 and desk.X1 <= B.HALF_X - B.WALL).toBe(true)
		expect(desk.X1 - desk.X0).toBeCloseTo(B.NURSE_DESK.Depth)
		expect(desk.Z1 - desk.Z0).toBeCloseTo(B.NURSE_DESK.Length)
		-- two columns of nurses fit between it and the end wall; the waiting room's side of it stays open
		expect(B.HALF_X - B.WALL - desk.X1).toBeCloseTo(2 * B.NURSE_EDGE + B.NURSE_GAP)
		expect(desk.Z0 - hall.Z0 >= 3).toBe(true)
		for level = B.MIN_LEVEL, B.MAX_LEVEL do
			local found = 0
			for _, o in B.obstacles(level, 0) do
				if o.Name == "NurseDesk" then
					found += 1
				elseif
					desk.X0 < o.X1 - 1e-6
					and o.X0 < desk.X1 - 1e-6
					and desk.Z0 < o.Z1 - 1e-6
					and o.Z0 < desk.Z1 - 1e-6
				then
					error("the nurses' desk overlaps " .. o.Name)
				end
			end
			expect(found).toBe(1)
		end
		-- off every door and every patient's walk by a creature's half-width
		for doorName in B.DOORS do
			local inside, outside = B.doorPoints(doorName)
			if inside and outside then
				expect(toRect(inside, desk) >= 2.5 and toRect(outside, desk) >= 2.5).toBe(true)
			end
		end
		for level = B.MIN_LEVEL, B.MAX_LEVEL do
			for _, seg in patientWalks(level) do
				for _, corner in
					{
						{ X = desk.X0, Z = desk.Z1 },
						{ X = desk.X0, Z = desk.Z0 },
						{ X = desk.X1, Z = desk.Z0 },
					}
				do
					expect(toSegment(corner, seg[1], seg[2]) >= 2.5).toBe(true)
				end
			end
		end
		-- the mouth (path()'s waypoint past the desk's open end) is open floor
		local m = B.NURSE_STATION.Mouth
		expect(B.clear({ X0 = m.X - 0.8, X1 = m.X + 0.8, Z0 = m.Z - 0.8, Z1 = m.Z + 0.8 }, 1)).toBe(true)
	end)

	test("every slot can walk to its work: the front doors, every open bay, every open station, the lift", function()
		local frontIn = B.doorPoints("Front")
		for level = B.MIN_LEVEL, B.MAX_LEVEL do
			local bays = B.openBays(level, ALL_ROOMS)
			for _, entry in everySlot() do
				local s = { X = entry.Slot.X, Z = entry.Slot.Z }
				local function need(to, what)
					if not B.path(s, to, level, 0) or not B.path(to, s, level, 0) then
						error(
							entry.Kind
								.. " "
								.. entry.Index
								.. " "
								.. name(s)
								.. ": no walk to "
								.. what
								.. " at Lv "
								.. level
						)
					end
				end
				need(frontIn, "the front doors")
				for id in B.STATIONS do
					if B.stationOpen(id, level) then
						need(B.stationStand(id), "the " .. id .. " stand")
					end
				end
				if entry.Kind == "Station" or entry.Kind == "Healer" then
					for _, bay in bays do
						need(B.doctorSpot(bay), "bay " .. bay.Id)
					end
				end
				if (entry.Kind == "Station" or entry.Kind == "Porter") and level >= 2 then
					need({ X = B.LANDING.X, Z = B.LANDING.Z }, "the lift")
				end
			end
		end
	end)

	test(
		"nurseSlot: a job's own place first, then the station; Healers, Medics, Porters, others, then overflow",
		function()
			local function same(a, b)
				return math.abs(a.X - b.X) < 1e-9 and math.abs(a.Z - b.Z) < 1e-9 and a.Face == b.Face
			end
			local station = B.NURSE_STATION.Slots
			local bays = B.NURSE_PLACES.Healer
			expect(same(B.nurseSlot("Maker", 1), B.NURSE_PLACES.Maker[1])).toBe(true)
			expect(same(B.nurseSlot("Cheerer", 4), B.NURSE_PLACES.Cheerer[4])).toBe(true)
			expect(same(B.nurseSlot("Healer", 1), bays[1])).toBe(true)
			expect(same(B.nurseSlot("Healer", 2, { Healer = 2 }), bays[2])).toBe(true)
			expect(same(B.nurseSlot("Healer", #bays, { Healer = #bays }), bays[#bays])).toBe(true)
			expect(same(B.nurseSlot("Porter", 1), B.NURSE_PLACES.Porter[1])).toBe(true)
			expect(same(B.nurseSlot("Janitor", 1), station[1])).toBe(true) -- a job with no place waits at the station
			local n = #bays -- the bays' end has this many slots
			expect(B.stationRank("Maker", 1)).toBeNil()
			expect(B.stationRank("Healer", n, { Healer = n })).toBeNil()
			expect(B.stationRank("Healer", n + 1, { Healer = n + 1 })).toBe(1) -- one Healer more than the bays' end holds
			-- Medics take what the Healers leave at the bays' end, then the station (after the Healers there)
			expect(same(B.nurseSlot("Medic", 1), bays[1])).toBe(true)
			expect(same(B.nurseSlot("Medic", 1, { Healer = 1, Medic = 2 }), bays[2])).toBe(true)
			expect(B.stationRank("Medic", n, { Healer = 1, Medic = n })).toBe(1)
			expect(B.stationRank("Medic", 1, { Healer = n, Medic = 1 })).toBe(1)
			expect(B.stationRank("Medic", 1, { Healer = n + 1, Medic = 1 })).toBe(2)
			expect(B.stationRank("Porter", 1, { Healer = 1, Medic = 1, Porter = 1 })).toBeNil()
			expect(B.stationRank("Porter", 3, { Healer = n + 1, Medic = 1, Porter = 3 })).toBe(3)
			expect(B.stationRank("Janitor", 1, { Healer = n + 1, Porter = 1, Janitor = 1 })).toBe(2)
			expect(B.stationRank("Maker", 3, { Healer = n + 1, Maker = 3 })).toBe(2) -- the 3rd Maker: past its place's 2
			expect(B.stationRank("Cheerer", 5, { Healer = n + 1, Maker = 3, Cheerer = 5 })).toBe(3)
			-- junk index: the first; a returned spot is a fresh table (callers may keep it)
			expect(same(B.nurseSlot("Healer", 0 / 0), bays[1])).toBe(true)
			expect(same(B.nurseSlot("Janitor", 0 / 0), station[1])).toBe(true)
			local a = B.nurseSlot("Janitor", 1)
			a.X = 999
			expect(station[1].X ~= 999).toBe(true)
			local b = B.nurseSlot("Healer", 1)
			b.X = 999
			expect(bays[1].X ~= 999).toBe(true)
		end
	)

	test("a full roster in any mix of jobs: no two nurses share a spot (each at least NURSE_GAP apart)", function()
		local checked = 0
		local counts = {}
		local function check()
			local spots = {}
			for _, job in JOBS do
				for k = 1, counts[job] or 0 do
					table.insert(spots, { Job = job, K = k, Spot = B.nurseSlot(job, k, counts) })
				end
			end
			for i = 1, #spots do
				for j = i + 1, #spots do
					if dist(spots[i].Spot, spots[j].Spot) < B.NURSE_GAP - 1e-6 then
						error(
							string.format(
								"%s %d and %s %d share %s",
								spots[i].Job,
								spots[i].K,
								spots[j].Job,
								spots[j].K,
								name(spots[i].Spot)
							)
						)
					end
				end
			end
			checked += 1
		end
		local function fill(index, left)
			if index > #JOBS then
				check()
				return
			end
			for n = 0, left do
				counts[JOBS[index]] = if n > 0 then n else nil
				fill(index + 1, left - n)
			end
			counts[JOBS[index]] = nil
		end
		fill(1, ROSTER)
		expect(checked).toBe(6435) -- every mix of up to 8 nurses over 7 jobs
	end)
end)
