--!strict
-- The clinic building's INTERFACE numbers (Real Clinic build plan, contract C1; design §8 and §15). Pure: no Roblox
-- services and no requires, so Lune can test it (tests/Building.spec).
-- These are the numbers everything round the building depends on: Server/HospitalBuilder builds to them,
-- Server/PlotBuilder puts the Counter, the gate path and the bought rooms' fit-outs at them, Server/Patients walks
-- its patients along them, and the nurses, the guide and the tutorial find the markers the builders name after them
-- (contract C2). Nobody else hardcodes one of these numbers.
--
-- The big clinic (Joshua, 2026-11-17: "realistic and big enough from the first moment"): the whole building stands at
-- every level. A level only changes what is OPEN: bays, the A&E door, the X-ray room, the floors upstairs.
--
-- Plot-local studs: x right as you face the street, -z is the street, y = 0 is the pad's top.
--
--   z -24 (street) ┌───────────── front doors (DOORS.Front, x -4..4) ─────────────┐
--                  │ WAITING (6 seats)   │ LOBBY + reception desk │ DISPENSARY     │   z -24..-12
--            A&E ──│──────────────────── corridor A ──────────────┴─ (its door) ───│   z -12..-5
--                  │ EXAM BAYS 1-6 (open to corridor A) │ SUPPLY shelf │ X-RAY     │   z -5..3.5
--                  │──────────────────── corridor B ──────────────────────│ LIFT   │   z 3.5..8.5
--                  │ BATH ROOM │ WINTER WING │ COZY WARD (W1, W2) │ hall + STAIRS  │   z 8.5..20
--   z 20           └──────────────────────────────── Garden door ─────────────────┘
--   x -32                                                                        x 32
-- The supply shelf's alcove (x 8..17.5) is also the passage between the two corridors. Upstairs is a TOWER over the
-- back-right part (x -5..32, z -5..20): F1 the Injury Ward, F2 the Rest Ward, F3 the staff room (more Rest beds),
-- then the roof deck with the helipad. The lift and the dog-leg stairs stack in the same place on every floor.
--
-- FACE: a yaw in degrees, used as CFrame.Angles(0, math.rad(Face), 0). The thing's FRONT is that CFrame's
-- LookVector: 0 = toward the street (-z), 90 = toward -x, 180 = toward the back (+z), 270 = toward +x.
-- A seat's front is where its sitter looks; a bay bed's front is its FOOT (the doctor stands there); a station's
-- front is the side the player stands on. Building.facing(face) gives the unit step (dx, dz).
--
--   Building.footprint(level, floor?): Rect      the outer walls' rectangle on that floor (0 = ground): the 64 x 44
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
--   Building.doctorSpot(bay): Point              the bay's DoctorSpot, at the bed's foot (bay X: its Spot, at the
--                                                bed's side): the doctor stands here, and a patient hops on from here
--   Building.bayOpen(bay, level, rooms?): boolean   level >= Opens, and for a room's bay that room is owned
--                                                (rooms = { [RoomId]: boolean })
--   Building.openBays(level, rooms?): { Bay }    in BAYS order
--   Building.stationRect(id): Rect? · Building.stationStand(id): Point?
--                                                a station's body, and where the player stands to use it
--   Building.stationOpen(id, level): boolean
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
--                                                kept shut), the lift shaft, the stairs, seats, beds, stations, the
--                                                desk, shelves. NOT modelled: the bought rooms' own fit-outs (their
--                                                doors count as open; Server/PlotBuilder keeps a fit-out inside its
--                                                ROOMS rect and off the door)
--   Building.clear(rect, level): boolean         nothing solid on the GROUND touches that rectangle
--   Building.reach(fromXZ, toXZ, level, floor?): boolean   the straight walk from one { X, Z } to another on that
--                                                floor (0 unless given) crosses nothing solid. A path may skim a
--                                                corner by under SKIM studs
--   Building.path(fromXZ, toXZ, level, floor?): { Point }?   the walk as waypoints (`to` last, `from` left out),
--                                                each leg a reach(): straight when it can be, else through NODES and
--                                                the doors. nil when a shut door or a wall is in the way

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
export type Station = { X: number, Z: number, Face: number, Opens: number }
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
Building.HALF_X = 32 -- the ground floor is x -32..32 ...
Building.FRONT = -24 -- ... from the façade (the street side) ...
Building.BACK = 20 -- ... to the back wall: 64 x 44
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

-- Upstairs: the tower over the back-right part of the block. F1 stands (closed) from Lv 1; see storeys().
Building.TOWER = rect(-5, 32, -5, 20)

-- The ground floor's rooms (the outer rectangles: walls are inside them). Waiting, Lobby and the two corridors are
-- one open hall; the Bays and the Supply alcove are open to the corridors.
Building.ROOMS = table.freeze({
	Waiting = rect(-32, -4.5, -24, -12),
	Lobby = rect(-4.5, 12, -24, -12),
	Dispensary = rect(12, 32, -24, -12),
	CorridorA = rect(-32, 32, -12, -5),
	Bays = rect(-32, 8, -5, 3.5),
	Supply = rect(8, 17.5, -5, 3.5),
	XRay = rect(17.5, 32, -5, 3.5),
	CorridorB = rect(-32, 26.4, 3.5, 8.5),
	BathRoom = rect(-32, -18, 8.5, 20),
	WinterWing = rect(-18, -5, 8.5, 20),
	CozyWard = rect(-5, 9.4, 8.5, 20),
	LiftCore = rect(9.4, 32, 8.5, 20), -- the hall in front of the stairs, the stairs, the way to the Garden door
})

-- Doors. Front, AE and Garden are in the outer walls; the rest are inside. A door with X0/X1 is in a wall that runs
-- along x (its plane at Z); one with Z0/Z1 is in a wall along z (its plane at X).
Building.DOORS = table.freeze({
	Front = table.freeze({ X0 = -4, X1 = 4, Z = -23.7, Height = 8 }), -- the sliding glass pair, in the middle
	AE = table.freeze({ Z0 = -10.5, Z1 = -6.5, X = -31.7, Height = 8, Opens = 2 }), -- -x wall, onto corridor A
	Garden = table.freeze({ X0 = 9.5, X1 = 13.3, Z = 19.7, Height = 8, Room = "Garden" }), -- the back wall
	Dispensary = table.freeze({ X0 = 13.5, X1 = 17.5, Z = -12.2, Height = 8 }), -- onto corridor A
	XRay = table.freeze({ X0 = 24, X1 = 28, Z = -4.8, Height = 8, Opens = 3 }), -- onto corridor A
	BathRoom = table.freeze({ X0 = -27, X1 = -23, Z = 8.7, Height = 8, Room = "BathRoom" }), -- onto corridor B
	WinterWing = table.freeze({ X0 = -13.5, X1 = -9.5, Z = 8.7, Height = 8, Room = "WinterWing" }),
	CozyWard = table.freeze({ X0 = 0, X1 = 4, Z = 8.7, Height = 8, Room = "Ward" }),
	LiftLobby = table.freeze({ Z0 = 4.5, Z1 = 7.5, X = 26.4, Height = 8, Opens = 2, Lift = true }), -- the lift's door
}) :: { [string]: Door }

-- The canopy over the front doors (outside; overhead, never solid at walking height).
Building.CANOPY = table.freeze({ X0 = -9, X1 = 9, Z0 = -28, Z1 = -24, Y = 10.5 })

-- Reception: the desk (the plot's `Counter`, built by PlotBuilder), where an arriving patient stops in front of it,
-- and where a Receptionist stands behind it.
Building.RECEPTION = table.freeze({
	Desk = rect(3, 11, -17, -14.6),
	Stop = table.freeze({ X = 7, Z = -19.6 }),
	Staff = table.freeze({ X = 7, Z = -13.2 }),
})

-- The waiting room: 5 seats along the street wall and 1 on the -x wall, all facing into the room, 5.5 apart (a
-- creature is about 5 wide). Seat 1 is nearest the lobby. SEAT_FRONT is from a seat's centre to its front spot.
Building.SEAT_SIZE = 3
Building.SEAT_FRONT = 3
Building.SEATS = table.freeze({
	table.freeze({ X = -6.2, Z = -21.9, Face = 180 }),
	table.freeze({ X = -11.7, Z = -21.9, Face = 180 }),
	table.freeze({ X = -17.2, Z = -21.9, Face = 180 }),
	table.freeze({ X = -22.7, Z = -21.9, Face = 180 }),
	table.freeze({ X = -28.2, Z = -21.9, Face = 180 }),
	table.freeze({ X = -29.9, Z = -16, Face = 270 }),
}) :: { Seat }
Building.PLANTER = rect(-31.4, -29.9, -23.4, -21) -- the plant in the waiting room's street corner

-- Exam bays. A bay bed's frame is BAY_BED (Width across, Length from head to foot); the DoctorSpot is SPOT_GAP past
-- the foot. Bays 1-6 are 6.5 wide, heads at their back wall, open to corridor A. Bay X is in the X-ray room, its head
-- at the +x wall. W1 and W2 are the Cozy Ward's (built by PlotBuilder while the Ward room is owned).
Building.BAY_BED = table.freeze({ Width = 4.4, Length = 7 })
Building.SPOT_GAP = 2.4
Building.BAY_WIDTH = 6.5
Building.BAYS = table.freeze({
	table.freeze({ Id = "1", X = -28.15, Z = -0.4, Face = 0, Opens = 1, Kind = "Exam" }),
	table.freeze({ Id = "2", X = -21.65, Z = -0.4, Face = 0, Opens = 1, Kind = "Exam" }),
	table.freeze({ Id = "3", X = -15.15, Z = -0.4, Face = 0, Opens = 2, Kind = "Exam" }),
	table.freeze({ Id = "4", X = -8.65, Z = -0.4, Face = 0, Opens = 3, Kind = "Exam" }),
	table.freeze({ Id = "5", X = -2.15, Z = -0.4, Face = 0, Opens = 4, Kind = "Exam" }),
	table.freeze({ Id = "6", X = 4.35, Z = -0.4, Face = 0, Opens = 5, Kind = "Exam" }),
	-- Bay X's doctor stands at the bed's -z side, just inside the door: at the foot (22, 0.9) the bay's prompt was
	-- nearer than the Cast Table's from where you take a cast, and both are on E, so only the bay's showed (Studio
	-- test 2026-11-17).
	table.freeze({
		Id = "X",
		X = 27.9,
		Z = 0.9,
		Face = 90,
		Opens = 3,
		Kind = "XRay",
		Spot = table.freeze({ X = 27.9, Z = -2.9 }),
	}),
	table.freeze({ Id = "W1", X = -1.2, Z = 15.9, Face = 0, Opens = 1, Kind = "Exam", Room = "Ward" }),
	table.freeze({ Id = "W2", X = 5.6, Z = 15.9, Face = 0, Opens = 1, Kind = "Exam", Room = "Ward" }),
}) :: { Bay }

-- Stations in the Building (Station_<id>). A body is STATION_SIZE (Width along its wall, Depth out from it); the
-- player stands STATION_STAND in front of its centre. Plaster and Ice share the supply alcove's -x wall, Bandage
-- its +x wall; Cast is in the X-ray room; Remedy is the dispensary's counter, behind its hatch onto the lobby.
-- Station_Bath and Station_Cocoa belong to their rooms' fit-outs (PlotBuilder).
Building.STATION_SIZE = table.freeze({ Width = 4, Depth = 2.4 })
Building.STATION_STAND = 2.8
Building.STATIONS = table.freeze({
	Plaster = table.freeze({ X = 9.2, Z = -2.7, Face = 270, Opens = 1 }),
	Ice = table.freeze({ X = 9.2, Z = 1.5, Face = 270, Opens = 1 }),
	Bandage = table.freeze({ X = 16.3, Z = -0.6, Face = 90, Opens = 2 }),
	Cast = table.freeze({ X = 20.5, Z = -3.4, Face = 180, Opens = 3 }),
	Remedy = table.freeze({ X = 13.6, Z = -19, Face = 270, Opens = 1 }),
}) :: { [string]: Station }
-- The dispensary: its hatch in the wall it shares with the lobby (the counter is behind it), and the bottle shelves.
Building.HATCH = table.freeze({ X = 12.2, Z0 = -21.5, Z1 = -16.5 })
Building.SHELVES = table.freeze({ rect(30, 31.4, -22.4, -13.4), rect(17, 29, -23.4, -22.2) })

-- The lift: at corridor B's +x end, its door on its -x face, onto a landing on every floor.
Building.SHAFT = rect(26.4, 31.4, 3.5, 8.5)
Building.LANDING = table.freeze({ X = 24.4, Z = 6, Size = 4 }) -- Landing_0 and Floor_<n>.Landing, at each slab top

-- The stairs: a dog-leg in the block's back +x corner, the same on every storey. From the landing (x 13.4..16.4,
-- level with the floor) the first half-flight climbs lane A toward +x to the mid landing (x 28.4..31.4, half a
-- storey up); the second comes back along lane B to the next floor's landing. Each half-flight runs 12 and rises 6
-- (5.5 upstairs): never steeper than 1 in 2. On a floor, STAIRWELL is solid (flights, rails or a hole) and the
-- landing is floor.
Building.ATRIUM = rect(13.4, 31.4, 13.4, 19.4)
Building.STAIR_LANDING = rect(13.4, 16.4, 13.4, 19.4)
Building.LANE_A = rect(16.4, 28.4, 13.4, 16.4)
Building.LANE_B = rect(16.4, 28.4, 16.4, 19.4)
Building.STAIR_MID = rect(28.4, 31.4, 13.4, 19.4)
Building.STAIRWELL = rect(16.4, 31.4, 13.4, 19.4)

-- The wards upstairs: one row of four bed spots per floor, heads at the tower's street wall, 2.8 between frames,
-- spot 1 nearest the lift. WARD_BEDS are the functional ones (Floor_<n>.BedSpot_<k>.Bed_<k>); DRESS_BEDS the spots
-- that hold a dressing bed instead.
Building.WARD_FLOOR = 1
Building.BED_HALF = 2.2 -- a bed frame is 4.4 wide ...
Building.BED_Z0 = -4.4 -- ... and runs z -4.4..2.6 (the pillow end is -z, against the wall)
Building.BED_Z1 = 2.6
Building.BED_Z = -0.9 -- its centre
Building.BED_FOOT_Z = 4.2 -- the foot spot (1.6 past the mattress), in the aisle the landing opens onto
Building.WARD_BEDS = table.freeze({
	[1] = table.freeze({
		table.freeze({ X = 21.6, Z = -0.9, Ward = "Wards" }),
		table.freeze({ X = 14.4, Z = -0.9, Ward = "Wards" }),
		table.freeze({ X = 7.2, Z = -0.9, Ward = "Wards" }),
	}),
	[2] = table.freeze({
		table.freeze({ X = 21.6, Z = -0.9, Ward = "Rest" }),
		table.freeze({ X = 14.4, Z = -0.9, Ward = "Rest" }),
	}),
	[3] = table.freeze({
		table.freeze({ X = 21.6, Z = -0.9, Ward = "Rest" }),
		table.freeze({ X = 14.4, Z = -0.9, Ward = "Rest" }),
	}),
}) :: { [number]: { { X: number, Z: number, Ward: string } } }
Building.DRESS_BEDS = table.freeze({
	[1] = table.freeze({ table.freeze({ X = 0, Z = -0.9 }) }),
	[2] = table.freeze({ table.freeze({ X = 7.2, Z = -0.9 }), table.freeze({ X = 0, Z = -0.9 }) }),
	[3] = table.freeze({ table.freeze({ X = 7.2, Z = -0.9 }), table.freeze({ X = 0, Z = -0.9 }) }),
}) :: { [number]: { Point } }

-- Outside. The ambulance bay is in the -x side yard at the A&E door; the helipad is on the roof deck.
Building.BAY_AMBULANCE = table.freeze({
	X = -41, -- the van's centre
	Z = -8.5,
	Area = rect(-48, -34, -14, -3),
	Stretcher = table.freeze({ X = -35.5, Z = -8.5 }), -- StretcherSpot: in line with the A&E door
})
Building.HELI = table.freeze({ X = 5, Z = 6, Size = 14 }) -- the pad's centre and width, on the roof deck (floor 4)

-- Waypoints for path(): the junctions of the two corridors and the hall. Door sides are added from DOORS.
Building.NODES = table.freeze({
	[0] = table.freeze({
		table.freeze({ X = -28, Z = -8.5 }), -- corridor A, from the A&E door ...
		table.freeze({ X = -14, Z = -8.5 }),
		table.freeze({ X = 0, Z = -8.5 }),
		table.freeze({ X = 12.7, Z = -8.5 }), -- ... past the supply alcove's mouth ...
		table.freeze({ X = 21, Z = -8.5 }),
		table.freeze({ X = 12.7, Z = 6 }), -- the alcove's other end, on corridor B
		table.freeze({ X = -25, Z = 6 }),
		table.freeze({ X = -11.5, Z = 6 }),
		table.freeze({ X = 2, Z = 6 }),
		table.freeze({ X = 24.4, Z = 6 }), -- the lift's landing
		table.freeze({ X = 11.4, Z = 11 }), -- the hall by the stairs
		table.freeze({ X = 14.9, Z = 12.4 }), -- the foot of the stairs
	}),
	[1] = table.freeze({ table.freeze({ X = 24.4, Z = 6 }), table.freeze({ X = 12, Z = 9 }) }),
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
	return facedRect(station.X, station.Z, station.Face, size.Width, size.Depth)
end

function Building.stationStand(id: string): Point?
	local station = Building.STATIONS[id]
	if not station then
		return nil
	end
	return ahead(station.X, station.Z, station.Face, Building.STATION_STAND)
end

function Building.stationOpen(id: string, level: number): boolean
	local station = Building.STATIONS[id]
	return station ~= nil and levelOf(level) >= station.Opens
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

	-- The dispensary: the wall it shares with the lobby (its hatch is glass over the counter: solid), and the wall
	-- along corridor A with its door
	local disp = rooms.Dispensary
	add(list, "DispensaryWall", disp.X0, disp.X0 + p, disp.Z0, disp.Z1)
	wallX(list, "DispensaryWall", disp.X0, disp.X1, disp.Z1 - p, disp.Z1, lv, { "Dispensary" })
	for _, shelf in Building.SHELVES do
		addRect(list, "Shelf", shelf)
	end

	-- The waiting room and reception
	addRect(list, "Counter", Building.RECEPTION.Desk)
	for index, seat in Building.SEATS do
		addRect(list, "WaitSeat_" .. index, Building.seatRect(seat))
	end
	addRect(list, "Planter", Building.PLANTER)

	-- The exam bays: a back wall, the thin dividers between them and the wall at bay 6's +x side
	local bays = rooms.Bays
	add(list, "BayWall", bays.X0, bays.X1, bays.Z1 - p, bays.Z1)
	add(list, "BayWall", bays.X1 - p, bays.X1, bays.Z0, bays.Z1)
	local half = Building.DIVIDER / 2
	for k = 1, 5 do
		local x = bays.X0 + w + k * Building.BAY_WIDTH
		add(list, "BayDivider", x - half, x + half, bays.Z0, bays.Z1)
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
	addRect(list, "Stairs", Building.STAIRWELL)
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

-- The waypoints on a floor: its NODES, and on the ground both sides of every walk-through door.
local function waypoints(floor: number): { Point }
	local nodes: { Point } = table.clone(Building.NODES[if floor <= 0 then 0 else 1])
	if floor <= 0 then
		for name in INSIDE do
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
