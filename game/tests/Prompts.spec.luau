--!nocheck
-- No E prompt through a wall (Phase 3 review, 2026-11-17). A ProximityPrompt is a sphere: Roblox shows it to anyone
-- whose character is within MaxActivationDistance, walls or no walls (these prompts ask for no line of sight: Roblox
-- casts that from the CAMERA, and with Invisicam the camera is often behind a wall the player is not). So where each
-- prompt hangs and how far it reaches must keep it on its own side of every wall by the numbers alone:
--   · a station's prompt (Logic/Building.stationPromptAt, PROMPT_OUT off its front face, PROMPT_REACH; Server/Stations)
--   · a bay's Examine prompt (on its DoctorSpot, BAY_PROMPT_REACH; Server/Patients K.BAY_PROMPT_DISTANCE)
-- What was wrong: from inside the dispensary, against the hatch wall, a player could take the supply wall's items;
-- the Cast Table's prompt showed in corridor A and in the Hall; a neighbour's prompt at a stand was 5.2 to 5.5 away
-- with 5 studs' reach; bay 1's prompt (9 studs) showed in the Hall and bay X's at the nurses' station.
-- A character's root is never nearer to a wall than ROOT_CLEAR (a HumanoidRootPart is 2 x 2 x 1: half its thinnest
-- side), so "the far side of a wall" is every point that far or farther off it.
-- Ground floor only: the prompts upstairs (the lift's, the ward beds') are not Logic/Building stations or bays.
-- Run from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")

local T = require("./expect")
local expect, test = T.expect, T.test

local B = require("../src/shared/Logic/Building")

local ROOT_CLEAR = 0.5
local STEP = 0.25 -- the grid the floor round each prompt is sampled on
local NEIGHBOUR = 1 -- at a stand or a DoctorSpot, every other prompt is at least this far beyond its reach
local LEVELS = { 1, 2, 3, 4, 5 }
-- Everything in Building.obstacles that is a wall (the low bay dividers too: a prompt has no height to see over
-- them); furniture is not.
local WALLS = {
	FrontWall = true,
	BackWall = true,
	LeftWall = true,
	RightWall = true,
	DispensaryWall = true,
	BayWall = true,
	BayDivider = true,
	XRayWall = true,
	RoomWall = true,
	StairWall = true,
	Shaft = true,
}

local function isWall(o): boolean
	local name = o.Name
	return type(name) == "string" and (WALLS[name] == true or string.sub(name, 1, 5) == "Door_")
end

local function dist(a, b): number
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end

-- Whether the segment a -> b touches the rectangle (Liang-Barsky, edges included).
local function crosses(a, b, r): boolean
	local dx, dz = b.X - a.X, b.Z - a.Z
	local t0, t1 = 0, 1
	for _, edge in { { -dx, a.X - r.X0 }, { dx, r.X1 - a.X }, { -dz, a.Z - r.Z0 }, { dz, r.Z1 - a.Z } } do
		local p, q = edge[1], edge[2]
		if math.abs(p) < 1e-12 then
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

local function wallsAt(level: number)
	local out = {}
	for _, o in B.obstacles(level, 0) do
		if isWall(o) then
			table.insert(out, o)
		end
	end
	return out
end

-- A root's centre can be here: ROOT_CLEAR off every wall.
local function canStand(p, walls): boolean
	for _, w in walls do
		if
			p.X > w.X0 - ROOT_CLEAR
			and p.X < w.X1 + ROOT_CLEAR
			and p.Z > w.Z0 - ROOT_CLEAR
			and p.Z < w.Z1 + ROOT_CLEAR
		then
			return false
		end
	end
	return true
end

-- Every prompt of the ground floor: { Name, At, Reach }
local PROMPTS = {}
for id in B.STATIONS do
	table.insert(PROMPTS, { Name = "Station " .. id, Station = id, At = B.stationPromptAt(id), Reach = B.PROMPT_REACH })
end
for _, bay in B.BAYS do
	table.insert(PROMPTS, { Name = "Bay " .. bay.Id, Bay = bay, At = B.doctorSpot(bay), Reach = B.BAY_PROMPT_REACH })
end
table.sort(PROMPTS, function(a, b)
	return a.Name < b.Name
end)

-- The first place a root can stand within the prompt's reach with a wall between the two, or nil.
local function throughWall(prompt, walls): string?
	local at, reach = prompt.At, prompt.Reach
	local n = math.ceil(reach / STEP)
	for i = -n, n do
		for j = -n, n do
			local p = { X = at.X + i * STEP, Z = at.Z + j * STEP }
			if dist(p, at) <= reach and canStand(p, walls) then
				for _, w in walls do
					if crosses(p, at, w) then
						return string.format(
							"%s (reach %.1f) is %.2f from (%.2f, %.2f), behind %s",
							prompt.Name,
							reach,
							dist(p, at),
							p.X,
							p.Z,
							tostring(w.Name)
						)
					end
				end
			end
		end
	end
	return nil
end

T.describe("Prompts: the numbers", function()
	test("PROMPT_OUT 1.4, PROMPT_REACH 4, BAY_PROMPT_REACH 4.5; every prompt hangs on open floor", function()
		expect({ B.PROMPT_OUT, B.PROMPT_REACH, B.BAY_PROMPT_REACH }).toEqual({ 1.4, 4, 4.5 })
		for _, prompt in PROMPTS do
			local at = prompt.At
			for _, level in LEVELS do
				if not canStand(at, wallsAt(level)) then
					error(prompt.Name .. " hangs in or against a wall at Lv " .. level)
				end
			end
		end
		expect(#PROMPTS).toBe(7 + 9) -- seven stations, nine bays
	end)

	test("a station's prompt hangs between its front face and its stand, nearer the stand", function()
		for id, station in B.STATIONS do
			local stand, at, body = B.stationStand(id), B.stationPromptAt(id), B.stationRect(id)
			expect(at.X > body.X0 - 1e-9 and at.X < body.X1 + 1e-9 and at.Z > body.Z0 and at.Z < body.Z1).toBe(false)
			expect(dist(at, { X = station.X, Z = station.Z })).toBeCloseTo(B.STATION_SIZE.Depth / 2 + B.PROMPT_OUT, 6)
			expect(dist(stand, at) <= 0.5).toBe(true)
			expect(dist(stand, at) < dist(stand, { X = station.X, Z = station.Z })).toBe(true)
		end
	end)
end)

T.describe("Prompts: one prompt at each place you stand", function()
	test("at every station's stand: its own prompt in reach, every other prompt a stud or more beyond reach", function()
		for id in B.STATIONS do
			local stand = B.stationStand(id)
			for _, prompt in PROMPTS do
				local d = dist(stand, prompt.At)
				if prompt.Station == id then
					expect(d <= prompt.Reach - 2).toBe(true) -- with room to stand a little off the mark
				elseif d < prompt.Reach + NEIGHBOUR then
					error(
						string.format("at %s's stand, %s is %.2f away (reach %.1f)", id, prompt.Name, d, prompt.Reach)
					)
				end
			end
		end
	end)

	test("at every DoctorSpot: its own prompt in reach, every other prompt a stud or more beyond reach", function()
		for _, bay in B.BAYS do
			local spot = B.doctorSpot(bay)
			for _, prompt in PROMPTS do
				local d = dist(spot, prompt.At)
				if prompt.Bay == bay then
					expect(d).toBe(0)
				elseif d < prompt.Reach + NEIGHBOUR then
					error(
						string.format(
							"at bay %s's spot, %s is %.2f away (reach %.1f)",
							bay.Id,
							prompt.Name,
							d,
							prompt.Reach
						)
					)
				end
			end
		end
	end)

	test("a bay's prompt covers what the doctor uses: across the bay at the spot, and the bay's mouth", function()
		local reach = B.BAY_PROMPT_REACH
		local half = B.BAY_WIDTH / 2 - B.DIVIDER / 2 - ROOT_CLEAR -- as far to a side as a root gets
		for index, mouth in B.BAY_MOUTHS do
			local bay = B.BAYS[index]
			local spot = B.doctorSpot(bay)
			expect(mouth.X).toBe(bay.X)
			for _, side in { -1, 1 } do
				expect(dist(spot, { X = bay.X + side * half, Z = spot.Z }) <= reach).toBe(true)
				-- the mouth line (the row's corridor edge), 3 studs either side of its middle
				expect(dist(spot, { X = bay.X + side * 3, Z = B.ROOMS.Bays.Z0 }) <= reach).toBe(true)
			end
			-- the bed's foot: a nurse's or a second player's place beside the doctor
			local bed = B.bayBed(bay)
			expect(dist(spot, { X = bay.X, Z = bed.Z0 }) <= reach - 2).toBe(true)
		end
	end)
end)

T.describe("Prompts: nothing through a wall", function()
	test("the scan sees a wall: a 9-stud bay prompt and a 5-stud station prompt both fail it", function()
		local walls = wallsAt(1)
		local bay1 = B.bay("1")
		expect(throughWall({ Name = "old bay 1", At = B.doctorSpot(bay1), Reach = 9 }, walls) ~= nil).toBe(true)
		local remedy = B.STATIONS.Remedy
		local old = { X = remedy.X, Z = remedy.Z + B.STATION_SIZE.Depth / 2 + 0.2 } -- PROMPT_OUT was 0.2
		expect(throughWall({ Name = "old Remedy", At = old, Reach = 5 }, walls) ~= nil).toBe(true)
		local cast = B.STATIONS.Cast
		old = { X = cast.X, Z = cast.Z + B.STATION_SIZE.Depth / 2 + 0.2 }
		expect(throughWall({ Name = "old Cast", At = old, Reach = 5 }, walls) ~= nil).toBe(true)
	end)

	test("at every level: no place a character can stand is within a prompt's reach with a wall between", function()
		for _, level in LEVELS do
			local walls = wallsAt(level)
			expect(#walls > 10).toBe(true)
			for _, prompt in PROMPTS do
				local found = throughWall(prompt, walls)
				if found then
					error("Lv " .. level .. ": " .. found)
				end
			end
		end
	end)

	test(
		"the review's cases by name: the dispensary, corridor A and the Hall, the nurses' station, the yard",
		function()
			-- inside the dispensary, against the hatch wall: no supply-wall prompt
			local disp = B.ROOMS.Dispensary
			for _, id in B.SUPPLY_ORDER do
				local at = B.stationPromptAt(id)
				local inside = { X = at.X, Z = disp.Z1 - B.PARTITION - ROOT_CLEAR }
				expect(dist(inside, at) > B.PROMPT_REACH + 0.5).toBe(true)
				expect(dist({ X = at.X, Z = disp.Z1 - B.PARTITION }, at) > B.PROMPT_REACH).toBe(true) -- on the wall's face
			end
			-- the Cast Table: from corridor A (behind it) and from the Hall (beside it)
			local cast, xray = B.stationPromptAt("Cast"), B.ROOMS.XRay
			expect(dist({ X = cast.X, Z = xray.Z0 }, cast) > B.PROMPT_REACH).toBe(true)
			expect(dist({ X = cast.X, Z = xray.Z0 - ROOT_CLEAR }, cast) > B.PROMPT_REACH + 0.5).toBe(true)
			expect(dist({ X = xray.X0, Z = cast.Z }, cast) >= B.PROMPT_REACH).toBe(true) -- on the wall's face: 4.0
			expect(dist({ X = xray.X0 - ROOT_CLEAR, Z = cast.Z }, cast) >= B.PROMPT_REACH + 0.5).toBe(true)
			-- bay 1 from the Hall, through its end wall (the Healers' spots stand against that wall)
			local spot1, hall = B.doctorSpot(B.bay("1")), B.ROOMS.Hall
			expect(dist({ X = hall.X0, Z = spot1.Z }, spot1) > B.BAY_PROMPT_REACH).toBe(true)
			for _, place in B.NURSE_PLACES.Healer do
				expect(dist(place, spot1) > B.BAY_PROMPT_REACH + 1).toBe(true)
			end
			-- bay X from the nurses' station (corridor A, behind the X-ray room's wall) and from the yard
			local spotX = B.doctorSpot(B.bay("X"))
			for _, slot in B.NURSE_STATION.Slots do
				expect(dist(slot, spotX) > B.BAY_PROMPT_REACH + 1).toBe(true)
			end
			expect(dist({ X = spotX.X, Z = xray.Z0 }, spotX) > B.BAY_PROMPT_REACH).toBe(true)
			expect(dist({ X = B.HALF_X + ROOT_CLEAR, Z = spotX.Z }, spotX) > B.BAY_PROMPT_REACH).toBe(true)
		end
	)
end)

T.describe("Prompts: the servers read these numbers", function()
	local stations = fs.readFile("src/server/Stations.luau")
	local patients = fs.readFile("src/server/Patients.luau")
	local function has(text: string, what: string): boolean
		return string.find(text, what, 1, true) ~= nil
	end

	test("Stations: the prompt hangs where Logic/Building says, with its reach; the guard allows PROMPT_OUT", function()
		expect(has(stations, "Building.stationPromptAt(stationId)")).toBe(true)
		expect(has(stations, "prompt.MaxActivationDistance = Building.PROMPT_REACH")).toBe(true)
		-- else every Building station falls back to its part's centre with 10 studs' reach
		expect(has(stations, "math.abs(offset.Z) > half.Z + Building.PROMPT_OUT + 1")).toBe(true)
		-- the guard's own numbers: the prompt's offset along the station's depth against what it lets through
		local offset = B.STATION_SIZE.Depth / 2 + B.PROMPT_OUT
		expect(offset <= B.STATION_SIZE.Depth / 2 + B.PROMPT_OUT + 1).toBe(true)
		expect(offset > B.STATION_SIZE.Depth / 2 + 1).toBe(true) -- the old guard (half.Z + 1) would refuse it
	end)

	test("Patients: a bay's prompt and the server's own distance check use BAY_PROMPT_REACH", function()
		expect(has(patients, "K.BAY_PROMPT_DISTANCE = Building.BAY_PROMPT_REACH")).toBe(true)
		expect(has(patients, "prompt.MaxActivationDistance = K.BAY_PROMPT_DISTANCE")).toBe(true)
		expect(has(patients, "U.spotWorld(state, bayId)).Magnitude <= K.BAY_PROMPT_DISTANCE + K.DISTANCE_SLACK")).toBe(
			true
		)
		-- the patient's own Send prompt keeps its reach (it hangs on a patient, not on the building)
		expect(has(patients, "K.PROMPT_DISTANCE = 9")).toBe(true)
	end)
end)
