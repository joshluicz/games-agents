--!strict
-- The clinic building's INTERFACE numbers (Real Clinic build plan, contract C1; design §8 and §15; the bigger, open
-- building of docs/plan/2026-11-17-simple-start-design.md §4). Pure: no Roblox services and no requires, so Lune can
-- test it (tests/Building.spec).
-- These are the numbers everything round the building depends on: Server/HospitalBuilder builds to them,
-- Server/PlotBuilder puts the Counter, the gate path and the bought rooms' fit-outs at them, Server/Patients walks
-- its patients along them, and the nurses, the guide and the tutorial find the markers the builders name after them
-- (contract C2). Nobody else hardcodes one of these numbers.
--
-- The big clinic (Joshua, 2026-11-17: "realistic and big enough from the first moment"): the whole building stands at
-- every level. A level only changes what is OPEN: bays, the A&E door, the X-ray room, the stairwell's door, the
-- floors upstairs.
-- The bigger, open building (Joshua, 2026-11-17, after playing: "its very cramped especially for someone
-- claustrophobic"; memory-20261117-006): the ground floor is 96 x 66 (was 64 x 44, 1.5x each way), every corridor is
-- at least CORRIDOR_MIN (10) wide, a bay is BAY_WIDTH (9.5) wide, every inside doorway is at least DOOR_WIDTH (6) wide
-- and DOOR_HEIGHT (10) tall, and the bays' dividers and curtains are CURTAIN_HEIGHT (6) high, so you see over them.
--
-- Plot-local studs: x right as you face the street, -z is the street, y = 0 is the pad's top.
--
--   z -36 (street) ┌───────────────────────── front doors (DOORS.Front, x -4..4) ─────────────────────────┐
--                  │ DISPENSARY (its door: on the lobby) │ LOBBY +         │ WAITING (6 seats)              │
--                  │ ══ hatch ══ the SUPPLY WALL ═══════ │ reception desk  │                                │  z -36..-20
--                  │ Bath Cocoa Bandage Ice Plaster Remedy                 │                                │
--            A&E ──│────────────────────────────── corridor A (12 wide) ────────────────── nurses' station │  z -20..-8
--                  │ EXAM BAYS  6   5   4   3   2   1  (open to corridor A) │ HALL          │ X-RAY (door   │
--                  │                                                        │               │ on corridor A)│  z -8..4
--                  │────────────────────────────── corridor B (10 wide) ───────────────────────────│ LIFT  │  z 4..14
--                  │ BATH ROOM   │ WINTER WING   │ COZY WARD (W1, W2) │ the way to │ hall behind the lift   │  z 14..20
--                  │             │               │                    │ the Garden │ STAIRWELL (enclosed;   │
--                  │             │               │                    │ door       │ its door on that hall) │  z 20..30
--   z 30           └──────────────────────────────────────── Garden door ─────────────────────────────────┘
--   x -48        -28.4           -9.4             10 12 14           24.4  26                 39.4       x 48
-- The supply wall (Joshua, 2026-11-17: "the alley way for the cabinets are narrow. can consider shifting them
-- elsewhere"): all six ground stations stand SIDE BY SIDE in one recess of the dispensary's wall along corridor A,
-- facing the bays across the corridor's 12 studs of open floor. From the lobby end: Remedy (the dispensary's counter,
-- under its hatch), Plaster, Ice, Bandage, then the pantry's Cocoa and Bath (open once the Winter Wing / the Bath Room
-- is owned). Bay 1 is the bay nearest the lobby, so a Lv 1 clinic (bays 1-2, Remedy and Plaster) plays in the middle
-- of the building. The bought rooms have no station: patients never walk into one to be treated.
-- The stairs (Joshua, 2026-11-17, of the old open flight at Lv 1: "the stairs model is stupid. i can see it. the door
-- is narrow too"): the dog-leg stands in its own ENCLOSED stairwell (ROOMS.Stairwell: walls from floor to ceiling on
-- every floor), entered through DOORS.Stairs, 6 wide, which is shut (solid, signed) until floor 1 opens at Lv 2. A
-- Lv 1 player never sees a step.
-- Upstairs is a TOWER over the back-right part (x -9.4..48, z -8..30): F1 the Injury Ward, F2 the Rest Ward, F3 the
-- staff room (more Rest beds), then the roof deck with the helipad. The lift and the stairwell stack in the same
-- place on every floor.
--
-- FACE: a yaw in degrees, used as CFrame.Angles(0, math.rad(Face), 0). The thing's FRONT is that CFrame's
-- LookVector: 0 = toward the street (-z), 90 = toward -x, 180 = toward the back (+z), 270 = toward +x.
-- A seat's front is where its sitter looks; a bay bed's front is its FOOT (the doctor stands there); a station's
-- front is the side the player stands on. Building.facing(face) gives the unit step (dx, dz).
--
--   Building.footprint(level, floor?): Rect      the outer walls' rectangle on that floor (0 = ground): the 96 x 66
--                                                block on the ground, the tower upstairs. The same at every level
--   Building.slabTop(floor): number              the walking surface: 0, 12, 23, 34, 45
--   Building.floors(level): number               upper floors OPEN at that level (0, 1, 2, 3, 4: Data/Levels.Floors;
--                                                the 4th is the roof deck)
--   Building.storeys(level): number              upper storeys STANDING at that level (1, 1, 2, 3, 3): F1 stands,
--                                                closed, at Lv 1
--   Building.facing(face): (dx, dz)
--   Building.seatRect(seat): Rect · Building.seatFront(seat): Point
--                                                a waiting seat's body, and the spot in front of it a patient hops
--                                                on from and off to (the seat itself is solid)
--   Building.bay(id): Bay?                       by id: "1".."6", "X", "W1", "W2"
--   Building.bayBed(bay): Rect                   the bay bed's frame
--   Building.doctorSpot(bay): Point              the bay's DoctorSpot, at the bed's foot, inside the bay (bay X: its
--                                                Spot, at the bed's side): the doctor stands here, and a patient
--                                                hops on from here
--                                                (its Examine prompt hangs here, BAY_PROMPT_REACH studs reach)
--   Building.bayOpen(bay, level, rooms?): boolean   level >= Opens, and for a room's bay that room is owned
--                                                (rooms = { [RoomId]: boolean })
--   Building.openBays(level, rooms?): { Bay }    in BAYS order
--   Building.stationRect(id): Rect? · Building.stationStand(id): Point?
--   Building.stationPromptAt(id): Point?         where the station's E prompt hangs: PROMPT_OUT off its front face
--                                                (PROMPT_REACH studs reach; Server/Stations)
--                                                a station's body, and where the player stands to use it
--   Building.stationOpen(id, level, rooms?): boolean   level >= Opens, and for a pantry station (Cocoa, Bath: its
--                                                Room) that room is owned (rooms = { [RoomId]: boolean }), as bayOpen
--   Building.wardBeds(level, floor?): { WardBed }   the bed spots on that floor (default F1) at that level, each
--                                                Functional (a BedSpot_<Index>, with its Ward) or a dressing bed.
--                                                {} when that floor isn't open
--   Building.bedRect(x): Rect · Building.bedFoot(x): (x, z)   a ward bed's frame, and where Patients stands a patient
--                                                before it hops on (the same on every upper floor)
--   Building.doorPoints(name): (Point, Point)?   a walk-through door's two sides (2 studs off the wall): inside,
--                                                then outside (inside the building for Front, AE and Garden; inside
--                                                its room for the others). nil for the lift's door
--   Building.obstacles(level, floor?): { Obstacle }   everything solid at walking height on that floor: the walls
--                                                (their open doorways left out, a door that opens at a later level
--                                                kept shut), the lift shaft, the stairwell's enclosure and its
--                                                flights, the bays' dividers, seats, beds, stations, the desk, the
--                                                nurses' desk, shelves. NOT modelled: the bought rooms' own
--                                                fit-outs (their doors count as open; Server/PlotBuilder keeps a
--                                                fit-out inside its ROOMS rect and off the door)
--   Building.clear(rect, level): boolean         nothing solid on the GROUND touches that rectangle
--   Building.reach(fromXZ, toXZ, level, floor?): boolean   the straight walk from one { X, Z } to another on that
--                                                floor (0 unless given) crosses nothing solid. A path may skim a
--                                                corner by under SKIM studs
--   Building.path(fromXZ, toXZ, level, floor?): { Point }?   the walk as waypoints (`to` last, `from` left out),
--                                                each leg a reach(): straight when it can be, else through NODES,
--                                                BAY_MOUTHS, the doors and the nurses' station's mouth. nil when a
--                                                shut door or a wall is in the way
--   Building.NURSE_STATION, NURSE_PLACES         where nurses stand (see "Where nurses stand" below): the nurses'
--                                                station (its Desk is solid) and the places a job has of its own
--                                                (NURSE_SHARES: a job that takes what another leaves of its place)
--   Building.nurseSlot(job, k, counts?): NurseSpot   where nurse number k of a job waits; counts = nurses per job
--                                                at the plot, so jobs sharing the station never share a slot
--   Building.stationRank(job, k, counts?): number?   its slot at the station (nil: at its own place)
-- Data the builders read (all below): ROOMS, DOORS, CANOPY, RECEPTION, SEATS, PLANTER, BAYS, BAY_DIVIDERS, BAY_MOUTHS,
-- STATIONS, SUPPLY_ORDER, PANTRY_ORDER, PANTRY_ROOMS, HATCH, SHELVES, SHAFT, LANDING, ATRIUM, STAIR_LANDING, LANE_A,
-- LANE_B, STAIR_MID, STAIRWELL, WARD_BEDS, DRESS_BEDS, BAY_AMBULANCE, HELI, TOWER, and the rules CORRIDOR_MIN,
-- DOOR_WIDTH, DOOR_HEIGHT, CURTAIN_HEIGHT.

local Building = {}

export type Rect = { X0: number, X1: number, Z0: number, Z1: number }
export type Point = { X: number, Z: number }
export type Obstacle = { Name: string, X0: number, X1: number, Z0: number, Z1: number }
export type Seat = { X: number, Z: number, Face: number }
export type Bay = {
	Id: string,
	X: number, -- the bed's centre
	Z: number,
	Face: number,
	Opens: number,
	Kind: "Exam" | "XRay",
	Room: string?, -- a RoomId (Data/Rooms): the bay exists only while that room is owned
	Spot: { X: number, Z: number }?, -- the DoctorSpot when it is not at the foot (bay X)
}
export type Station = {
	X: number,
	Z: number,
	Face: number,
	Opens: number,
	Room: string?, -- a RoomId (Data/Rooms): the station is open only while that room is owned (the pantry's)
	Width: number?, -- along its wall, when it is not STATION_SIZE.Width (no station today: the pantry's are full width)
}
export type WardBed = { Index: number, X: number, Z: number, Floor: number, Functional: boolean, Ward: string? }
export type Door = {
	X0: number?, -- a door in a wall along x: its span, and the wall's centre plane Z
	X1: number?,
	Z: number?,
	Z0: number?, -- a door in a wall along z: its span, and the wall's centre plane X
	Z1: number?,
	X: number?,
	Height: number,
	Opens: number?, -- shut (solid) below this level
	Room: string?, -- a bought room's door: shut until the room is owned (not modelled in obstacles)
	Lift: boolean?, -- the lift's own door: never walked through
}

local function rect(x0: number, x1: number, z0: number, z1: number): Rect
	return table.freeze({ X0 = x0, X1 = x1, Z0 = z0, Z1 = z1 })
end

------------------------------------------------------------------------------------------------------------------
-- The shape
------------------------------------------------------------------------------------------------------------------
Building.HALF_X = 48 -- the ground floor is x -48..48 ...
Building.FRONT = -36 -- ... from the façade (the street side) ...
Building.BACK = 30 -- ... to the back wall: 96 x 66 (was 64 x 44)
Building.GROUND = 12 -- the ground storey's height
Building.STOREY = 11 -- every upper storey: 10.4 clear, so a 6.5-stud creature sitting on a bed keeps its headroom
-- A slab is at most this thick, so F1's underside is 11.4: Patients' ground raycasts start at +10 and must never
-- meet a slab.
Building.SLAB_MAX = 0.6
Building.SLAB_TOPS = table.freeze({ 12, 23, 34, 45 }) -- F1, F2, F3, the roof deck
Building.WALL = 0.6 -- the outer walls, inside the footprint's edge
Building.PARTITION = 0.4 -- the inside walls
Building.DIVIDER = 0.3 -- the thin walls between two exam bays
Building.MIN_LEVEL = 1
Building.MAX_LEVEL = 5

-- The open building's rules (design §4; tests/Building.spec holds the layout to them).
Building.CORRIDOR_MIN = 10 -- every corridor and hall is at least this wide, wall to wall
-- Every inside doorway is at least DOOR_WIDTH wide and DOOR_HEIGHT tall (the front pair stays 8, under the canopy
-- and the name sign). Not every creature fits: the widest (CloudSheep, 6.9 across in the Phase 3 review's measure) is
-- wider than a 6-wide doorway and its sides pass through the frame. Nothing can get stuck, because no creature part
-- collides (CreatureBuilder builds every one CanCollide = false; tests/BlockyCreatures.spec holds that). Widening
-- the doors would cost parts the Building has none of to spare.
Building.DOOR_WIDTH = 6
Building.DOOR_HEIGHT = 10
-- The bays' dividers and their curtains are this high (was the doorways' 10): you see over them, so the row of bays
-- reads as one open ward. HospitalBuilder builds both to it.
Building.CURTAIN_HEIGHT = 6

-- Upstairs: the tower over the back-right part of the block. F1 stands (closed) from Lv 1; see storeys(). Its -x wall
-- stands over the divider between bays 2 and 3 and the wall between the Winter Wing and the Cozy Ward.
Building.TOWER = rect(-9.4, 48, -8, 30)

-- The ground floor's rooms (the outer rectangles: walls are inside them). Waiting, Lobby, the two corridors and the
-- Hall between them are one open hall; the Bays are open to corridor A; Supply is the stations' recess in the
-- dispensary's wall, open to corridor A; LiftCore (the way to the Garden door) and LiftHall (behind the lift, in
-- front of the stairwell) are open to corridor B. Stairwell is the stairs' enclosure, behind DOORS.Stairs.
Building.ROOMS = table.freeze({
	Dispensary = rect(-48, -10, -36, -22.4),
	Supply = rect(-48, -10, -22.4, -20),
	Lobby = rect(-10, 12, -36, -20),
	Waiting = rect(12, 48, -36, -20),
	CorridorA = rect(-48, 48, -20, -8),
	Bays = rect(-48, 10, -8, 4),
	Hall = rect(10, 26, -8, 4), -- the hall between the two corridors
	XRay = rect(26, 48, -8, 4),
	CorridorB = rect(-48, 39.4, 4, 14),
	BathRoom = rect(-48, -28.4, 14, 30),
	WinterWing = rect(-28.4, -9.4, 14, 30),
	CozyWard = rect(-9.4, 14, 14, 30),
	LiftCore = rect(14, 24.4, 14, 30),
	LiftHall = rect(24.4, 48, 14, 20),
	Stairwell = rect(24.4, 48, 20, 30),
})

-- Doors. Front, AE and Garden are in the outer walls; the rest are inside. A door with X0/X1 is in a wall that runs
-- along x (its plane at Z); one with Z0/Z1 is in a wall along z (its plane at X). Every one is at least DOOR_WIDTH
-- wide, and every inside one DOOR_HEIGHT tall.
Building.DOORS = table.freeze({
	Front = table.freeze({ X0 = -4, X1 = 4, Z = -35.7, Height = 8 }), -- the sliding glass pair, in the middle
	AE = table.freeze({ Z0 = -17, Z1 = -11, X = -47.7, Height = 10, Opens = 2 }), -- -x wall, onto corridor A
	Garden = table.freeze({ X0 = 16.2, X1 = 22.2, Z = 29.7, Height = 10, Room = "Garden" }), -- the back wall
	Dispensary = table.freeze({ Z0 = -33, Z1 = -27, X = -10.2, Height = 10 }), -- onto the lobby (was: corridor A)
	XRay = table.freeze({ X0 = 34, X1 = 40, Z = -7.8, Height = 10, Opens = 3 }), -- onto corridor A
	BathRoom = table.freeze({ X0 = -41.2, X1 = -35.2, Z = 14.2, Height = 10, Room = "BathRoom" }), -- onto corridor B
	WinterWing = table.freeze({ X0 = -21.9, X1 = -15.9, Z = 14.2, Height = 10, Room = "WinterWing" }),
	CozyWard = table.freeze({ X0 = -0.7, X1 = 5.3, Z = 14.2, Height = 10, Room = "Ward" }),
	LiftLobby = table.freeze({ Z0 = 6, Z1 = 12, X = 39.4, Height = 10, Opens = 2, Lift = true }), -- the lift's door
	-- The stairwell's door, in its wall onto the hall behind the lift: shut and solid until floor 1 opens (Lv 2), with
	-- "Upstairs: opens at Lv 2" on it. Upstairs the same span is an open doorway in the enclosure (never shut).
	Stairs = table.freeze({ X0 = 25.1, X1 = 31.1, Z = 20.2, Height = 10, Opens = 2 }),
}) :: { [string]: Door }

-- The canopy over the front doors (outside; overhead, never solid at walking height).
Building.CANOPY = table.freeze({ X0 = -9, X1 = 9, Z0 = -40, Z1 = -36, Y = 10.5 })

-- Reception: the desk (the plot's `Counter`, built by PlotBuilder), where an arriving patient stops in front of it,
-- and where a Receptionist stands behind it. On the waiting room's side of the lobby, off the line from the doors.
Building.RECEPTION = table.freeze({
	Desk = rect(3, 11, -29, -26.6),
	Stop = table.freeze({ X = 7, Z = -31.6 }),
	Staff = table.freeze({ X = 7, Z = -25.2 }),
})

-- The waiting room: 5 seats along the street wall and 1 on the +x wall, all facing into the room, 7 apart (a
-- creature is about 5 wide). Seat 1 is nearest the lobby. SEAT_FRONT is from a seat's centre to its front spot.
Building.SEAT_SIZE = 3
Building.SEAT_FRONT = 3
Building.SEATS = table.freeze({
	table.freeze({ X = 16, Z = -33.9, Face = 180 }),
	table.freeze({ X = 23, Z = -33.9, Face = 180 }),
	table.freeze({ X = 30, Z = -33.9, Face = 180 }),
	table.freeze({ X = 37, Z = -33.9, Face = 180 }),
	table.freeze({ X = 44, Z = -33.9, Face = 180 }),
	table.freeze({ X = 45.9, Z = -27, Face = 90 }),
}) :: { Seat }
Building.PLANTER = rect(45.9, 47.4, -35.4, -33) -- the plant in the waiting room's street corner

-- Exam bays. A bay bed's frame is BAY_BED (Width across, Length from head to foot); the DoctorSpot is SPOT_GAP past
-- the foot. Bays 1-6 are BAY_WIDTH wide and 12 deep, heads at their back wall, open to corridor A; bay 1 is the one
-- nearest the lobby and the supply wall, bay 6 the one by the A&E door. Their DoctorSpots are INSIDE the bay (2.2
-- behind its mouth): BAY_MOUTHS are path()'s waypoints in front of each. Bay X is in the X-ray room, its head at the
-- +x wall. W1 and W2 are the Cozy Ward's (built by PlotBuilder while the Ward room is owned).
Building.BAY_BED = table.freeze({ Width = 4.4, Length = 7 })
Building.SPOT_GAP = 2.4
Building.BAY_WIDTH = 9.5
Building.BAYS = table.freeze({
	table.freeze({ Id = "1", X = 4.85, Z = 0.1, Face = 0, Opens = 1, Kind = "Exam" }),
	table.freeze({ Id = "2", X = -4.65, Z = 0.1, Face = 0, Opens = 1, Kind = "Exam" }),
	table.freeze({ Id = "3", X = -14.15, Z = 0.1, Face = 0, Opens = 2, Kind = "Exam" }),
	table.freeze({ Id = "4", X = -23.65, Z = 0.1, Face = 0, Opens = 3, Kind = "Exam" }),
	table.freeze({ Id = "5", X = -33.15, Z = 0.1, Face = 0, Opens = 4, Kind = "Exam" }),
	table.freeze({ Id = "6", X = -42.65, Z = 0.1, Face = 0, Opens = 5, Kind = "Exam" }),
	-- Bay X's doctor stands at the bed's -z side, in line with the way in from the door: at the foot the bay's prompt
	-- was nearer than the Cast Table's from where you take a cast, and both are on E, so only the bay's showed
	-- (Studio test 2026-11-17).
	table.freeze({
		Id = "X",
		X = 43.9,
		Z = 1.4,
		Face = 90,
		Opens = 3,
		Kind = "XRay",
		Spot = table.freeze({ X = 43.9, Z = -2.8 }),
	}),
	table.freeze({ Id = "W1", X = -2.7, Z = 25.9, Face = 0, Opens = 1, Kind = "Exam", Room = "Ward" }),
	table.freeze({ Id = "W2", X = 7.3, Z = 25.9, Face = 0, Opens = 1, Kind = "Exam", Room = "Ward" }),
}) :: { Bay }

-- The thin walls between two of bays 1-6 (DIVIDER thick, CURTAIN_HEIGHT high), from bay 1's side.
local function bayDividers(): { Rect }
	local bays, half = Building.ROOMS.Bays, Building.DIVIDER / 2
	local out = {}
	for k = 1, 5 do
		local x = bays.X1 - Building.PARTITION - k * Building.BAY_WIDTH
		table.insert(out, rect(x - half, x + half, bays.Z0, bays.Z1))
	end
	return table.freeze(out)
end
Building.BAY_DIVIDERS = bayDividers()

-- Stations in the Building (Station_<id>). A body is STATION_SIZE (Width along its wall, Depth out from it; a
-- station's own Width wins); the player stands STATION_STAND in front of its centre.
-- THE SUPPLY WALL: SUPPLY_ORDER's six stand side by side in ROOMS.Supply, backs on the dispensary's wall, SUPPLY_PITCH
-- between centres (a stud between two bodies), all facing the bays (Face 180) with corridor A's whole width open in
-- front of them. Remedy, the dispensary's counter, is the first (nearest the lobby), under the HATCH; the pantry's
-- Cocoa and Bath are the last two (PANTRY_ORDER: they open with their rooms, and no room has a station of its own).
-- Cast stays in the X-ray room, where its patient is.
Building.STATION_SIZE = table.freeze({ Width = 4, Depth = 2.4 })
Building.STATION_STAND = 2.8
-- A Building station's prompt hangs PROMPT_OUT off its front face (half the way to its stand: 0.2 from where the
-- player stands) and reaches PROMPT_REACH. On the station's centre with 10 studs' reach, a neighbour's prompt
-- (through a wall, too) beat the Cast Table's at its own stand, and a cast could not be taken (Studio test
-- 2026-11-17). Roblox shows one prompt per key. The two numbers together keep every prompt on its own side of the
-- walls (tests/Prompts.spec): the prompt is 4.2 from the far face of the wall behind its station (the dispensary's
-- inside, corridor A behind the Cast Table) and 4 from the Hall's side of the X-ray room's wall, where a character's
-- root is never nearer than half a stud; and SUPPLY_PITCH keeps a neighbour's prompt a stud out of reach at each stand
-- (5.0 away). No line of sight on these prompts: Roblox casts it from the CAMERA, and with Invisicam the camera is
-- often behind a wall the player is not.
Building.PROMPT_OUT = 1.4
Building.PROMPT_REACH = 4
-- A bay's Examine prompt hangs on its DoctorSpot and reaches this far (Server/Patients). No one sphere covers a whole
-- bay (9.5 x 12) and stays inside its walls: bay 1's DoctorSpot is 5.15 from the Hall's side of its end wall, bay X's
-- 4.1 from the yard's side of the outer wall and 5.2 from corridor A's side of the X-ray wall (the nurses' station).
-- 4.5 covers the bay's mouth and the floor round the bed's foot, where the doctor stands, and reaches no root on a
-- wall's far side (half a stud off it at the nearest; tests/Prompts.spec). It was 9: bay 1's showed in the Hall.
Building.BAY_PROMPT_REACH = 4.5
Building.SUPPLY_ORDER = table.freeze({ "Remedy", "Plaster", "Ice", "Bandage", "Cocoa", "Bath" }) -- from the lobby end
Building.SUPPLY_PITCH = 5
Building.SUPPLY_FIRST = 4 -- from the recess's lobby end to the first station's centre
-- The pantry (Joshua, 2026-11-17: "minimise the patients walking around. yes move the hot cocoa into like a pantry or
-- something"; memory-20261117-006). Hot chocolate and bath foam are taken at the supply wall, never in a bought room:
-- Station_Cocoa opens with the Winter Wing and Station_Bath with the Bath Room (the same pairs as Data/Rooms
-- Stations, tests/Pantry.spec). They are full-width units now, beside the Bandage shelf.
Building.PANTRY_ORDER = table.freeze({ "Cocoa", "Bath" }) -- from the Bandage shelf's side
Building.PANTRY_ROOMS = table.freeze({ Cocoa = "WinterWing", Bath = "BathRoom" }) :: { [string]: string }
local SUPPLY_OPENS: { [string]: number } = { Remedy = 1, Plaster = 1, Ice = 2, Bandage = 2, Cocoa = 1, Bath = 1 }
local STATIONS: { [string]: Station } = {
	Cast = table.freeze({ X = 30, Z = -6.4, Face = 180, Opens = 3 }), -- against the X-ray room's corridor wall
}
for index, id in Building.SUPPLY_ORDER do
	local wall = Building.ROOMS.Supply
	STATIONS[id] = table.freeze({
		X = wall.X1 - Building.SUPPLY_FIRST - (index - 1) * Building.SUPPLY_PITCH,
		Z = wall.Z0 + Building.STATION_SIZE.Depth / 2,
		Face = 180,
		Opens = SUPPLY_OPENS[id],
		Room = Building.PANTRY_ROOMS[id],
	})
end
Building.STATIONS = table.freeze(STATIONS) :: { [string]: Station }
-- The dispensary: its hatch (glass over the Remedy counter, in its wall along corridor A: the wall's plane at Z, the
-- opening X0..X1) and the bottle shelves you see through it (against the -x wall and the street wall).
Building.HATCH = table.freeze({ Z = -22.6, X0 = -17, X1 = -11 })
Building.SHELVES = table.freeze({ rect(-47.4, -46, -34, -24), rect(-44, -14, -35.4, -34.2) })

-- The lift: at corridor B's +x end, its door on its -x face, onto a landing on every floor. The shaft fills the
-- corridor's width (8 x 10).
Building.SHAFT = rect(39.4, 47.4, 4, 14)
Building.LANDING = table.freeze({ X = 36.4, Z = 9, Size = 6 }) -- Landing_0 and Floor_<n>.Landing, at each slab top

-- The stairs: a dog-leg in the block's back +x corner, the same on every storey, inside its own enclosure
-- (ROOMS.Stairwell: a wall on the hall's side with DOORS.Stairs in it, a wall on the Garden way's side, the outer
-- walls behind and beside; full height on every floor). From the landing (x 24.8..31.4, level with the floor, just
-- inside the door) the first half-flight climbs lane A toward +x to the mid landing (x 43.4..47.4, half a storey
-- up); the second comes back along lane B to the next floor's landing. Each half-flight runs 12 and rises 6 (5.5
-- upstairs): never steeper than 1 in 2. A lane is 4.5 wide. On a floor, STAIRWELL is solid (flights, rails or a hole)
-- and the landing is floor.
Building.ATRIUM = rect(24.8, 47.4, 20.4, 29.4) -- the enclosure's inside
Building.STAIR_LANDING = rect(24.8, 31.4, 20.4, 29.4)
Building.LANE_A = rect(31.4, 43.4, 20.4, 24.9)
Building.LANE_B = rect(31.4, 43.4, 24.9, 29.4)
Building.STAIR_MID = rect(43.4, 47.4, 20.4, 29.4)
Building.STAIRWELL = rect(31.4, 47.4, 20.4, 29.4)

-- The wards upstairs: one row of four bed spots per floor, heads at the tower's street wall, 6.4 between frames,
-- spot 1 nearest the lift. WARD_BEDS are the functional ones (Floor_<n>.BedSpot_<k>.Bed_<k>); DRESS_BEDS the spots
-- that hold a dressing bed instead.
Building.WARD_FLOOR = 1
Building.BED_HALF = 2.2 -- a bed frame is 4.4 wide ...
Building.BED_Z0 = -7.4 -- ... and runs z -7.4..-0.4 (the pillow end is -z, against the wall)
Building.BED_Z1 = -0.4
Building.BED_Z = -3.9 -- its centre
Building.BED_FOOT_Z = 1.2 -- the foot spot (1.6 past the mattress), in the aisle the landing opens onto
Building.WARD_BEDS = table.freeze({
	[1] = table.freeze({
		table.freeze({ X = 32.4, Z = -3.9, Ward = "Wards" }),
		table.freeze({ X = 21.6, Z = -3.9, Ward = "Wards" }),
		table.freeze({ X = 10.8, Z = -3.9, Ward = "Wards" }),
	}),
	[2] = table.freeze({
		table.freeze({ X = 32.4, Z = -3.9, Ward = "Rest" }),
		table.freeze({ X = 21.6, Z = -3.9, Ward = "Rest" }),
	}),
	[3] = table.freeze({
		table.freeze({ X = 32.4, Z = -3.9, Ward = "Rest" }),
		table.freeze({ X = 21.6, Z = -3.9, Ward = "Rest" }),
	}),
}) :: { [number]: { { X: number, Z: number, Ward: string } } }
Building.DRESS_BEDS = table.freeze({
	[1] = table.freeze({ table.freeze({ X = 0, Z = -3.9 }) }),
	[2] = table.freeze({ table.freeze({ X = 10.8, Z = -3.9 }), table.freeze({ X = 0, Z = -3.9 }) }),
	[3] = table.freeze({ table.freeze({ X = 10.8, Z = -3.9 }), table.freeze({ X = 0, Z = -3.9 }) }),
}) :: { [number]: { Point } }

-- Outside. The ambulance bay is in the -x side yard at the A&E door; the helipad is on the roof deck.
Building.BAY_AMBULANCE = table.freeze({
	X = -57, -- the van's centre
	Z = -14,
	Area = rect(-64, -50, -20, -8),
	Stretcher = table.freeze({ X = -51.5, Z = -14 }), -- StretcherSpot: in line with the A&E door
})
Building.HELI = table.freeze({ X = 8, Z = 9, Size = 20 }) -- the pad's centre and width, on the roof deck (floor 4)

-- Waypoints for path(). BAY_MOUTHS: one in corridor A in front of each of bays 1-6 (BAY_MOUTH_OUT before its mouth),
-- in BAYS order: a patient walks to its bay's, then in to the DoctorSpot. NODES: the junctions of the corridors and
-- the halls. Both sides of every walk-through door are added from DOORS.
Building.BAY_MOUTH_OUT = 2.5
local function bayMouths(): { Point }
	local out = {}
	for _, bay in Building.BAYS do
		if bay.Kind == "Exam" and not bay.Room then
			table.insert(out, table.freeze({ X = bay.X, Z = Building.ROOMS.Bays.Z0 - Building.BAY_MOUTH_OUT }))
		end
	end
	return table.freeze(out)
end
Building.BAY_MOUTHS = bayMouths()
Building.NODES = table.freeze({
	[0] = table.freeze({
		table.freeze({ X = 13.5, Z = -24.5 }), -- round the reception desk's end, between the seats and the bays
		table.freeze({ X = -40, Z = -14 }), -- corridor A, from the A&E door ...
		table.freeze({ X = -20, Z = -14 }),
		table.freeze({ X = 0, Z = -14 }), -- ... past the lobby ...
		table.freeze({ X = 20, Z = -14 }), -- ... to the Hall's mouth ...
		table.freeze({ X = 37, Z = -14 }), -- ... and the X-ray door
		table.freeze({ X = 12.5, Z = -10.5 }), -- round the bays' end, between bay 1's mouth and the Hall
		table.freeze({ X = 20, Z = -2 }), -- the Hall between the two corridors
		table.freeze({ X = 20, Z = 9 }), -- corridor B, at the Hall
		table.freeze({ X = -38.2, Z = 9 }), -- ... in front of the three back rooms' doors
		table.freeze({ X = -18.9, Z = 9 }),
		table.freeze({ X = 2.3, Z = 9 }),
		table.freeze({ X = 36.4, Z = 9 }), -- the lift's landing
		table.freeze({ X = 19.2, Z = 17 }), -- the way to the Garden door
		table.freeze({ X = 28.1, Z = 16 }), -- the hall behind the lift, in front of the stairwell's door
	}),
	[1] = table.freeze({ table.freeze({ X = 36.4, Z = 9 }), table.freeze({ X = 20, Z = 9 }) }),
}) :: { [number]: { Point } }

-- reach() lets a straight walk skim a solid corner by less than this. A patient is about 5 studs wide, so nobody
-- can see a skim; a real crossing (a bed, the shaft, a wall) is always deeper than this.
Building.SKIM = 0.3

------------------------------------------------------------------------------------------------------------------
-- Numbers by level and floor
------------------------------------------------------------------------------------------------------------------

local function levelOf(level: any): number
	if type(level) ~= "number" or level ~= level then
		return Building.MIN_LEVEL
	end
	return math.clamp(math.floor(level), Building.MIN_LEVEL, Building.MAX_LEVEL)
end

function Building.floors(level: number): number
	return levelOf(level) - 1
end

function Building.storeys(level: number): number
	return math.clamp(levelOf(level) - 1, 1, 3)
end

function Building.slabTop(floor: number): number
	if floor <= 0 then
		return 0
	end
	return Building.SLAB_TOPS[math.min(floor, #Building.SLAB_TOPS)]
end

function Building.footprint(_level: number, floor: number?): Rect
	if (floor or 0) >= 1 then
		local t = Building.TOWER
		return { X0 = t.X0, X1 = t.X1, Z0 = t.Z0, Z1 = t.Z1 }
	end
	return { X0 = -Building.HALF_X, X1 = Building.HALF_X, Z0 = Building.FRONT, Z1 = Building.BACK }
end

function Building.facing(face: number): (number, number)
	local turns = math.floor(face / 90 + 0.5) % 4
	if turns == 0 then
		return 0, -1
	elseif turns == 1 then
		return -1, 0
	elseif turns == 2 then
		return 0, 1
	end
	return 1, 0
end

-- A box `across` wide and `along` long (along its facing), centred on (x, z).
local function facedRect(x: number, z: number, face: number, across: number, along: number): Rect
	local dx = Building.facing(face)
	local halfX = if dx ~= 0 then along / 2 else across / 2
	local halfZ = if dx ~= 0 then across / 2 else along / 2
	return { X0 = x - halfX, X1 = x + halfX, Z0 = z - halfZ, Z1 = z + halfZ }
end

local function ahead(x: number, z: number, face: number, studs: number): Point
	local dx, dz = Building.facing(face)
	return { X = x + dx * studs, Z = z + dz * studs }
end

function Building.seatRect(seat: Seat): Rect
	return facedRect(seat.X, seat.Z, seat.Face, Building.SEAT_SIZE, Building.SEAT_SIZE)
end

function Building.seatFront(seat: Seat): Point
	return ahead(seat.X, seat.Z, seat.Face, Building.SEAT_FRONT)
end

function Building.bay(id: any): Bay?
	for _, bay in Building.BAYS do
		if bay.Id == id then
			return bay
		end
	end
	return nil
end

function Building.bayBed(bay: Bay): Rect
	return facedRect(bay.X, bay.Z, bay.Face, Building.BAY_BED.Width, Building.BAY_BED.Length)
end

function Building.doctorSpot(bay: Bay): Point
	local spot = bay.Spot
	if spot then
		return { X = spot.X, Z = spot.Z }
	end
	return ahead(bay.X, bay.Z, bay.Face, Building.BAY_BED.Length / 2 + Building.SPOT_GAP)
end

function Building.bayOpen(bay: Bay, level: number, rooms: { [string]: boolean }?): boolean
	if levelOf(level) < bay.Opens then
		return false
	end
	if bay.Room then
		return type(rooms) == "table" and rooms[bay.Room] == true
	end
	return true
end

function Building.openBays(level: number, rooms: { [string]: boolean }?): { Bay }
	local out: { Bay } = {}
	for _, bay in Building.BAYS do
		if Building.bayOpen(bay, level, rooms) then
			table.insert(out, bay)
		end
	end
	return out
end

function Building.stationRect(id: string): Rect?
	local station = Building.STATIONS[id]
	if not station then
		return nil
	end
	local size = Building.STATION_SIZE
	return facedRect(station.X, station.Z, station.Face, station.Width or size.Width, size.Depth)
end

function Building.stationStand(id: string): Point?
	local station = Building.STATIONS[id]
	if not station then
		return nil
	end
	return ahead(station.X, station.Z, station.Face, Building.STATION_STAND)
end

function Building.stationPromptAt(id: string): Point?
	local station = Building.STATIONS[id]
	if not station then
		return nil
	end
	return ahead(station.X, station.Z, station.Face, Building.STATION_SIZE.Depth / 2 + Building.PROMPT_OUT)
end

function Building.stationOpen(id: string, level: number, rooms: { [string]: boolean }?): boolean
	local station = Building.STATIONS[id]
	if station == nil or levelOf(level) < station.Opens then
		return false
	end
	if station.Room then
		return type(rooms) == "table" and rooms[station.Room] == true
	end
	return true
end

function Building.bedRect(x: number): Rect
	return { X0 = x - Building.BED_HALF, X1 = x + Building.BED_HALF, Z0 = Building.BED_Z0, Z1 = Building.BED_Z1 }
end

function Building.bedFoot(x: number): (number, number)
	return x, Building.BED_FOOT_Z
end

function Building.wardBeds(level: number, floor: number?): { WardBed }
	local k = floor or Building.WARD_FLOOR
	local beds: { WardBed } = {}
	local functional = Building.WARD_BEDS[k]
	if not functional or k > Building.floors(level) then
		return beds
	end
	for index, spot in functional do
		table.insert(beds, { Index = index, X = spot.X, Z = spot.Z, Floor = k, Functional = true, Ward = spot.Ward })
	end
	for _, spot in Building.DRESS_BEDS[k] or {} do
		table.insert(beds, { Index = #beds + 1, X = spot.X, Z = spot.Z, Floor = k, Functional = false })
	end
	return beds
end

------------------------------------------------------------------------------------------------------------------
-- Where nurses stand (Server/Nurses reads these; tests/NurseSpots.spec). Joshua, 2026-11-17, after playing: "nurses
-- look like theyre in the middle of nowhere". Every hired nurse has a place that means something, all of it derived
-- from the rooms, doors, seats and stations above (so a change to the building moves them with it):
--   the nurses' station  a long counter across corridor A's far (+x) end, past the X-ray door, one end on the X-ray
--                        room's wall: the idle place, for any job without a place of its own and the nurses past
--                        their own place's last slot. Its slots: two columns of four behind the counter, between it
--                        and the end wall, looking over it down the corridor at the bays. A dead end: no patient
--                        walks there (in the Hall between the corridors they cut every corner)
--   Healers, Medics      at the bays' end: against the outside of bay 1's end wall, in the Hall, a few hops from
--                        bays 1 and 2 (the bays every clinic has). Healers first, Medics take what is left
--   Porters              beside the lift's ground landing: against the X-ray room's back wall, on corridor B, one
--                        straight walk from where its patient waits
--   Makers               at the supply wall: in its recess past the last station (the A&E door's end), where no
--                        patient walks
--   Cheerers             between the waiting seats, at their backs (among the patients they cheer)
--   Receptionists        behind the reception desk: RECEPTION.Staff first, then either side of it
-- A slot is a NurseSpot (plot-local studs and the FACE the nurse looks at). Nobody stands in a corridor's middle, on
-- a patient's walk, in a doorway, on a station's stand or under its prompt (tests/NurseSpots.spec checks it all).
------------------------------------------------------------------------------------------------------------------

export type NurseSpot = { X: number, Z: number, Face: number }

Building.NURSE_FOOT = 0.8 -- half a nurse's footprint: this much round its spot is clear of anything solid
Building.NURSE_GAP = 2.2 -- between two nurses standing side by side
Building.NURSE_EDGE = 1 -- a nurse's spot is this far off the wall or the desk behind it
-- The station's counter (HospitalBuilder builds it): Depth across, Length out from the wall (four nurses long).
Building.NURSE_DESK = table.freeze({ Depth = 0.9, Length = 8.8 })

local function nurseSpot(x: number, z: number, face: number): NurseSpot
	return table.freeze({ X = x, Z = z, Face = face })
end

-- The nurses' station: Desk (solid, in obstacles as "NurseDesk"), Slots (in order: the first nurse takes the first)
-- and Mouth (a waypoint just past the desk's open end, so path() gets the nurses behind it out).
local function nurseStation()
	local hall = Building.ROOMS.CorridorA
	local gap, edge = Building.NURSE_GAP, Building.NURSE_EDGE
	local back = hall.Z1 -- the X-ray room's wall along corridor A
	local outer = Building.HALF_X - Building.WALL - edge -- the column against the end wall
	local inner = outer - gap -- the column just behind the desk
	local deskX1 = inner - edge
	local size = Building.NURSE_DESK
	local desk = rect(deskX1 - size.Depth, deskX1, back - size.Length, back)
	local rows = math.floor(size.Length / gap + 0.5)
	local slots = {}
	for _, x in { inner, outer } do
		for row = rows, 1, -1 do -- from the desk's open end back to the wall
			table.insert(slots, nurseSpot(x, back - edge - (row - 1) * gap, 90)) -- looking down corridor A at the bays
		end
	end
	return table.freeze({
		Desk = desk,
		Slots = table.freeze(slots),
		Mouth = table.freeze({ X = (inner + outer) / 2, Z = desk.Z0 - 0.8 }),
	})
end
Building.NURSE_STATION = nurseStation()

-- The places a job has of its own (Healers and Medics, Porters, Makers, Cheerers, Receptionists), each a list of
-- slots in order.
local function nursePlaces()
	local foot, gap, edge = Building.NURSE_FOOT, Building.NURSE_GAP, Building.NURSE_EDGE
	-- Healers and Medics: against the outside of the bays' end wall (bay 1's), in the Hall, from the corridor-A end.
	-- Looking into the Hall.
	local bays = Building.ROOMS.Bays
	local HEALER_IN = 4.7 -- from the bays' mouth line: patients cut the Hall's corner there
	local healers = {}
	for k = 1, 2 do -- past these two, patients cutting the Hall on their way to the Cozy Ward pass too close
		table.insert(healers, nurseSpot(bays.X1 + edge, bays.Z0 + HEALER_IN + (k - 1) * gap, 270))
	end
	-- Porters: against the X-ray room's back wall, on corridor B, just clear of the lift's landing and one more beside
	-- it. Looking across the corridor.
	local landing = Building.LANDING
	local porterX = landing.X - landing.Size / 2 - foot / 2
	local porterZ = Building.ROOMS.XRay.Z1 + edge
	local porters = { nurseSpot(porterX, porterZ, 180), nurseSpot(porterX - gap, porterZ, 180) }
	-- Makers: in the supply wall's recess, past its last station (toward the A&E door), looking out at the bays
	local order = Building.SUPPLY_ORDER
	local last = Building.stationRect(order[#order]) :: Rect
	local makerX = last.X0 - foot - 0.4
	local makerZ = Building.ROOMS.Supply.Z0 + edge + 0.2
	local makers = { nurseSpot(makerX, makerZ, 180), nurseSpot(makerX - gap, makerZ, 180) }
	-- Cheerers: in the gap between two seats of a row (same line, same facing), half a stud back toward the wall,
	-- looking the way the seats do. Nearest the lobby first.
	local cheerers = {}
	local seats = Building.SEATS
	for index = 1, #seats - 1 do
		local a, b = seats[index], seats[index + 1]
		if a.Face == b.Face and math.abs(a.Z - b.Z) < 1e-6 then
			local dx, dz = Building.facing(a.Face)
			table.insert(cheerers, nurseSpot((a.X + b.X) / 2 - dx * 0.5, (a.Z + b.Z) / 2 - dz * 0.5, a.Face))
		end
	end
	-- Receptionists: behind the desk, the staff spot first, then one each side (inside the desk's length)
	local staff, desk = Building.RECEPTION.Staff, Building.RECEPTION.Desk
	local receptionists = { nurseSpot(staff.X, staff.Z, 0) }
	for _, side in { 1, -1 } do
		local at = staff.X + side * gap
		if at - foot >= desk.X0 and at + foot <= desk.X1 then
			table.insert(receptionists, nurseSpot(at, staff.Z, 0))
		end
	end
	local atBays = table.freeze(healers)
	return table.freeze({
		Healer = atBays,
		Medic = atBays, -- the same spots: NURSE_SHARES
		Porter = table.freeze(porters),
		Maker = table.freeze(makers),
		Cheerer = table.freeze(cheerers),
		Receptionist = table.freeze(receptionists),
	})
end
Building.NURSE_PLACES = nursePlaces() :: { [string]: { NurseSpot } }

-- A job that shares another's place: it takes the slots that job's nurses leave (Medics after the Healers).
Building.NURSE_SHARES = table.freeze({ Medic = "Healer" }) :: { [string]: string }

-- The order the jobs take the nurses' station's slots (only the nurses past their own place's last slot wait
-- there); a job without a place of its own comes after these three (by name), then Makers, Cheerers, Receptionists.
Building.NURSE_STATION_ORDER = table.freeze({ "Healer", "Medic", "Porter" })
local OVERFLOW_ORDER = { "Maker", "Cheerer", "Receptionist" }

local function whole(value: any, min: number): number
	if type(value) ~= "number" or value ~= value then
		return min
	end
	return math.clamp(math.floor(value), min, 99)
end

-- The jobs in the order they take the station's slots, for this plot's head count (`counts`: nurses per job).
local function stationOrder(counts: { [string]: number }): { string }
	local order = table.clone(Building.NURSE_STATION_ORDER)
	local others = {}
	for job in counts do
		if
			type(job) == "string"
			and not table.find(Building.NURSE_STATION_ORDER, job)
			and not table.find(OVERFLOW_ORDER, job)
		then
			table.insert(others, job)
		end
	end
	table.sort(others)
	for _, job in others do
		table.insert(order, job)
	end
	for _, job in OVERFLOW_ORDER do
		table.insert(order, job)
	end
	return order
end

-- How many of its place's slots a job's nurses get, and how many of that place's slots come before them (taken by
-- the job it shares the place with: NURSE_SHARES). 0, 0 for a job without a place.
local function ownSlots(job: string, counts: { [string]: number }?): (number, number)
	local place = Building.NURSE_PLACES[job]
	if not place then
		return 0, 0
	end
	local first = Building.NURSE_SHARES[job]
	local taken = if first and counts then math.min(#place, whole(counts[first], 0)) else 0
	return #place - taken, taken
end

-- Which of the station's slots nurse number `k` of `job` takes (1 = the first), or nil when it stands at its job's
-- own place. `counts` = nurses per job at this plot (the jobs earlier in the station's order take the first slots;
-- without it, as if no other job were there). Past the last slot it starts again from the first.
function Building.stationRank(job: string, k: number, counts: { [string]: number }?): number?
	local index = whole(k, 1)
	local own = ownSlots(job, counts)
	if index <= own then
		return nil
	end
	local before = 0
	if counts then
		for _, other in stationOrder(counts) do
			if other == job then
				break
			end
			before += math.max(0, whole(counts[other], 0) - (ownSlots(other, counts)))
		end
	end
	local slots = #Building.NURSE_STATION.Slots
	return (before + index - own - 1) % slots + 1
end

-- Where nurse number `k` of `job` waits: its job's own place, else the nurses' station (Building.stationRank).
function Building.nurseSlot(job: string, k: number, counts: { [string]: number }?): NurseSpot
	local rank = Building.stationRank(job, k, counts)
	local slot
	if rank then
		slot = Building.NURSE_STATION.Slots[rank]
	else
		local _, taken = ownSlots(job, counts)
		slot = Building.NURSE_PLACES[job][taken + whole(k, 1)]
	end
	return { X = slot.X, Z = slot.Z, Face = slot.Face }
end

local DOOR_SIDE = 2 -- a door's two sides stand this far off its wall's plane

-- Which side of each walk-through door is "inside" (+1 = the +z or +x side of its wall): inside the building for
-- the three outer doors, inside its room for the others.
local INSIDE: { [string]: number } = {
	Front = 1,
	AE = 1,
	Garden = -1,
	Dispensary = -1,
	XRay = 1,
	BathRoom = 1,
	WinterWing = 1,
	CozyWard = 1,
	Stairs = 1,
}

function Building.doorPoints(name: string): (Point?, Point?)
	local door = Building.DOORS[name]
	local side = INSIDE[name]
	if not door or not side then
		return nil, nil
	end
	if door.X0 and door.X1 and door.Z then
		local x = (door.X0 + door.X1) / 2
		return { X = x, Z = door.Z + side * DOOR_SIDE }, { X = x, Z = door.Z - side * DOOR_SIDE }
	elseif door.Z0 and door.Z1 and door.X then
		local z = (door.Z0 + door.Z1) / 2
		return { X = door.X + side * DOOR_SIDE, Z = z }, { X = door.X - side * DOOR_SIDE, Z = z }
	end
	return nil, nil
end

------------------------------------------------------------------------------------------------------------------
-- What's solid
------------------------------------------------------------------------------------------------------------------

local function add(list: { Obstacle }, name: string, x0: number, x1: number, z0: number, z1: number)
	if x1 - x0 > 1e-6 and z1 - z0 > 1e-6 then
		table.insert(list, { Name = name, X0 = x0, X1 = x1, Z0 = z0, Z1 = z1 })
	end
end

local function addRect(list: { Obstacle }, name: string, r: Rect)
	add(list, name, r.X0, r.X1, r.Z0, r.Z1)
end

-- Whether that door is a walk-through gap at this level (a bought room's door counts as open).
local function gapOpen(door: Door, level: number): boolean
	return not door.Lift and level >= (door.Opens or 1)
end

-- A wall along x (z0..z1 thick) from x0 to x1, with the named doors left open (or shut, as "Door_<name>").
local function wallX(
	list: { Obstacle },
	name: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	level: number,
	doors: { string }
)
	local at = x0
	for _, doorName in doors do
		local door = Building.DOORS[doorName]
		local d0, d1 = door.X0 :: number, door.X1 :: number
		add(list, name, at, math.min(d0, x1), z0, z1)
		if not gapOpen(door, level) then
			add(list, "Door_" .. doorName, d0, d1, z0, z1)
		end
		at = math.max(at, d1)
	end
	add(list, name, at, x1, z0, z1)
end

-- The same for a wall along z (x0..x1 thick).
local function wallZ(
	list: { Obstacle },
	name: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	level: number,
	doors: { string }
)
	local at = z0
	for _, doorName in doors do
		local door = Building.DOORS[doorName]
		local d0, d1 = door.Z0 :: number, door.Z1 :: number
		add(list, name, x0, x1, at, math.min(d0, z1))
		if not gapOpen(door, level) then
			add(list, "Door_" .. doorName, x0, x1, d0, d1)
		end
		at = math.max(at, d1)
	end
	add(list, name, x0, x1, at, z1)
end

local function ground(list: { Obstacle }, lv: number)
	local w, p = Building.WALL, Building.PARTITION
	local x0, x1, z0, z1 = -Building.HALF_X, Building.HALF_X, Building.FRONT, Building.BACK
	local rooms = Building.ROOMS

	-- The outer walls
	wallX(list, "FrontWall", x0, x1, z0, z0 + w, lv, { "Front" })
	wallX(list, "BackWall", x0, x1, z1 - w, z1, lv, { "Garden" })
	wallZ(list, "LeftWall", x0, x0 + w, z0, z1, lv, { "AE" })
	add(list, "RightWall", x1 - w, x1, z0, z1)

	-- The dispensary: the wall it shares with the lobby, with its door, and the wall along corridor A behind the
	-- supply wall's stations (its hatch is glass over the Remedy counter: solid)
	local disp = rooms.Dispensary
	wallZ(list, "DispensaryWall", disp.X1 - p, disp.X1, disp.Z0, disp.Z1, lv, { "Dispensary" })
	add(list, "DispensaryWall", disp.X0, disp.X1, disp.Z1 - p, disp.Z1)
	for _, shelf in Building.SHELVES do
		addRect(list, "Shelf", shelf)
	end

	-- The waiting room and reception
	addRect(list, "Counter", Building.RECEPTION.Desk)
	for index, seat in Building.SEATS do
		addRect(list, "WaitSeat_" .. index, Building.seatRect(seat))
	end
	addRect(list, "Planter", Building.PLANTER)
	addRect(list, "NurseDesk", Building.NURSE_STATION.Desk)

	-- The exam bays: a back wall, the thin dividers between them and the wall at bay 1's +x side
	local bays = rooms.Bays
	add(list, "BayWall", bays.X0, bays.X1, bays.Z1 - p, bays.Z1)
	add(list, "BayWall", bays.X1 - p, bays.X1, bays.Z0, bays.Z1)
	for _, divider in Building.BAY_DIVIDERS do
		addRect(list, "BayDivider", divider)
	end
	for _, bay in Building.BAYS do
		addRect(list, "Bed_" .. bay.Id, Building.bayBed(bay))
	end

	-- The stations
	for id in Building.STATIONS do
		addRect(list, "Station_" .. id, Building.stationRect(id) :: Rect)
	end

	-- The X-ray room
	local xray = rooms.XRay
	add(list, "XRayWall", xray.X0, xray.X0 + p, xray.Z0, xray.Z1)
	wallX(list, "XRayWall", xray.X0, xray.X1, xray.Z0, xray.Z0 + p, lv, { "XRay" })
	add(list, "XRayWall", xray.X0, xray.X1, xray.Z1 - p, xray.Z1)

	-- The back rooms: their wall along corridor B (three doors) and the walls between them
	local bath, winter, cozy = rooms.BathRoom, rooms.WinterWing, rooms.CozyWard
	wallX(list, "RoomWall", bath.X0, cozy.X1, bath.Z0, bath.Z0 + p, lv, { "BathRoom", "WinterWing", "CozyWard" })
	add(list, "RoomWall", bath.X1, bath.X1 + p, bath.Z0, bath.Z1)
	add(list, "RoomWall", winter.X1, winter.X1 + p, winter.Z0, winter.Z1)
	add(list, "RoomWall", cozy.X1 - p, cozy.X1, cozy.Z0, cozy.Z1)

	addRect(list, "Shaft", Building.SHAFT)
end

-- The stairwell's enclosure (the same on every floor): the wall on the hall's side with its door (on the ground,
-- shut below DOORS.Stairs.Opens; upstairs, always an open doorway), the wall on the Garden way's side, and the
-- flights themselves. The other two sides are the outer walls.
local function stairwell(list: { Obstacle }, lv: number)
	local p, w = Building.PARTITION, Building.WALL
	local well = Building.ROOMS.Stairwell
	wallX(list, "StairWall", well.X0, well.X1 - w, well.Z0, well.Z0 + p, lv, { "Stairs" })
	add(list, "StairWall", well.X0, well.X0 + p, well.Z0, well.Z1 - w)
	addRect(list, "Stairs", Building.STAIRWELL)
end

local function upper(list: { Obstacle }, lv: number, k: number)
	local f = Building.TOWER
	local w = Building.WALL
	-- Solid walls all round (kids can't walk off a floor, or off the roof deck), the shaft and the stairwell
	add(list, "FrontWall", f.X0, f.X1, f.Z0, f.Z0 + w)
	add(list, "BackWall", f.X0, f.X1, f.Z1 - w, f.Z1)
	add(list, "LeftWall", f.X0, f.X0 + w, f.Z0, f.Z1)
	add(list, "RightWall", f.X1 - w, f.X1, f.Z0, f.Z1)
	addRect(list, "Shaft", Building.SHAFT)
	stairwell(list, Building.MAX_LEVEL) -- its doorway is open on every floor that is
	for _, bed in Building.wardBeds(lv, k) do
		addRect(list, if bed.Functional then "BedSpot_" .. bed.Index else "DressBed", Building.bedRect(bed.X))
	end
end

function Building.obstacles(level: number, floor: number?): { Obstacle }
	local lv = levelOf(level)
	local k = floor or 0
	local list: { Obstacle } = {}
	if k > Building.floors(lv) then
		return list -- that floor isn't open at this level
	end
	if k <= 0 then
		ground(list, lv)
		stairwell(list, lv)
	else
		upper(list, lv, k)
	end
	return list
end

local EPSILON = 0.01

function Building.clear(area: Rect, level: number): boolean
	for _, o in Building.obstacles(level, 0) do
		if
			area.X0 < o.X1 - EPSILON
			and o.X0 < area.X1 - EPSILON
			and area.Z0 < o.Z1 - EPSILON
			and o.Z0 < area.Z1 - EPSILON
		then
			return false
		end
	end
	return true
end

-- Whether the segment a -> b passes through the rectangle (Liang-Barsky), after shrinking it by `shrink` a side.
local function crosses(a: Point, b: Point, o: Obstacle, shrink: number): boolean
	local x0, x1, z0, z1 = o.X0 + shrink, o.X1 - shrink, o.Z0 + shrink, o.Z1 - shrink
	local thinX, thinZ = x1 <= x0, z1 <= z0
	if thinX or thinZ then
		-- Thinner than the skim allowance (a wall): test its centre line instead, at its full length, so a wall is
		-- never walked through, not even at the seam between two of its pieces (a wall and its shut door).
		if thinX then
			x0, x1 = (o.X0 + o.X1) / 2 - 1e-3, (o.X0 + o.X1) / 2 + 1e-3
			if not thinZ then
				z0, z1 = o.Z0, o.Z1
			end
		end
		if thinZ then
			z0, z1 = (o.Z0 + o.Z1) / 2 - 1e-3, (o.Z0 + o.Z1) / 2 + 1e-3
			if not thinX then
				x0, x1 = o.X0, o.X1
			end
		end
	end
	local dx, dz = b.X - a.X, b.Z - a.Z
	local t0, t1 = 0, 1
	for _, edge in { { -dx, a.X - x0 }, { dx, x1 - a.X }, { -dz, a.Z - z0 }, { dz, z1 - a.Z } } do
		local p, q = edge[1], edge[2]
		if math.abs(p) < 1e-9 then
			if q < 0 then
				return false -- parallel to this edge and outside it
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

local function reachIn(obstacles: { Obstacle }, from: Point, to: Point): boolean
	for _, o in obstacles do
		if crosses(from, to, o, Building.SKIM) then
			return false
		end
	end
	return true
end

function Building.reach(from: Point, to: Point, level: number, floor: number?): boolean
	return reachIn(Building.obstacles(level, floor or 0), from, to)
end

-- The waypoints on a floor: its NODES and both sides of the stairwell's door, and on the ground the bays' mouths,
-- both sides of every other walk-through door and the nurses' station's mouth.
local function waypoints(floor: number): { Point }
	local nodes: { Point } = table.clone(Building.NODES[if floor <= 0 then 0 else 1])
	if floor <= 0 then
		for _, mouth in Building.BAY_MOUTHS do
			table.insert(nodes, mouth)
		end
		table.insert(nodes, Building.NURSE_STATION.Mouth)
	end
	for name in INSIDE do
		if floor <= 0 or name == "Stairs" then
			local inside, outside = Building.doorPoints(name)
			if inside and outside then
				table.insert(nodes, inside)
				table.insert(nodes, outside)
			end
		end
	end
	return nodes
end

function Building.path(from: Point, to: Point, level: number, floor: number?): { Point }?
	local k = floor or 0
	local obstacles = Building.obstacles(level, k)
	if reachIn(obstacles, from, to) then
		return { to }
	end
	-- Dijkstra over { from, the waypoints, to }: few enough points to try every pair.
	local points: { Point } = { from }
	for _, node in waypoints(k) do
		table.insert(points, node)
	end
	table.insert(points, to)
	local n = #points
	local dist: { number } = table.create(n, math.huge)
	local prev: { number } = table.create(n, 0)
	local done: { boolean } = table.create(n, false)
	dist[1] = 0
	while true do
		local at, best = 0, math.huge
		for index = 1, n do
			if not done[index] and dist[index] < best then
				at, best = index, dist[index]
			end
		end
		if at == 0 or at == n then
			break
		end
		done[at] = true
		local a = points[at]
		for index = 2, n do
			if not done[index] then
				local b = points[index]
				local length = math.sqrt((b.X - a.X) ^ 2 + (b.Z - a.Z) ^ 2)
				if best + length < dist[index] and reachIn(obstacles, a, b) then
					dist[index] = best + length
					prev[index] = at
				end
			end
		end
	end
	if dist[n] == math.huge then
		return nil
	end
	local out: { Point } = {}
	local at = n
	while at ~= 1 do
		table.insert(out, 1, points[at])
		at = prev[at]
	end
	return out
end

return Building
