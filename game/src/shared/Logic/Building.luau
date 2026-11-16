--!strict
-- The hospital building's INTERFACE numbers (look build plan §B6; docs/research/2026-11-16-hospital-building.md
-- §3.2-3.3, plus the front ward). Pure: no Roblox services and no requires, so Lune can test it.
-- These are the numbers everything round the building depends on: Server/HospitalBuilder (T3) builds to them,
-- Server/PlotBuilder (T4) puts the Stand's stations, bed and decor slots at them, and tests/Building.spec checks them
-- against what Server/Patients assumes (its walkways at x = ±12.5, its back lane at z = 4, its bedRoute at x = 7.6
-- and its straight-line walk upstairs). T3's own interior layout lives in HospitalBuilder.Pure.
--
-- Plot-local studs: x right as you face the street, -z is the street, y = 0 is the pad's top.
--
--   Building.footprint(level, floor?): Rect      the outer walls' rectangle on that floor (0 = ground): the podium at
--                                                Lv 1, the whole block for G and F1 from Lv 2, the tower from F2
--   Building.slabTop(floor): number              the walking surface: 0, 11, 20, 29, 38
--   Building.floors(level): number               upper floors at that level (0, 1, 2, 3, 4: Data/Levels.Floors)
--   Building.wardBeds(level): { WardBed }        the main ward's bed spots that hold a bed at that level, each with
--                                                Functional (a BedSpot_<n>) or not (a dressing bed in that spot)
--   Building.bedRect(x): Rect · Building.bedFoot(x): (x, z)   a main-ward bed's frame, and where Patients stands a
--                                                patient before it hops on
--   Building.obstacles(level, floor?): { Obstacle }   everything solid at walking height on that floor: the walls
--                                                (with their doorways left open), the lift shaft, the stair atrium,
--                                                the beds, the bench
--   Building.clear(rect, level): boolean         nothing solid on the GROUND touches that rectangle
--   Building.reach(fromXZ, toXZ, level, floor?): boolean   the straight walk from one { X, Z } to another on that
--                                                floor (0 unless given) crosses nothing solid. A path may skim a
--                                                corner by under SKIM studs (see SKIM)
-- `floor` is a Foundation addition to the plan's reach(fromXZ, toXZ, level): the ground and F1 need different
-- obstacles, and the plan's own checks ask about both.

local Building = {}

export type Rect = { X0: number, X1: number, Z0: number, Z1: number }
export type Point = { X: number, Z: number }
export type Obstacle = { Name: string, X0: number, X1: number, Z0: number, Z1: number }
export type WardBed = { Index: number, X: number, Functional: boolean }

------------------------------------------------------------------------------------------------------------------
-- The shape
------------------------------------------------------------------------------------------------------------------
Building.HALF = 11.5 -- the footprint is x -11.5..11.5 on every floor
Building.FRONT = -13 -- the façade (the street side)
Building.PODIUM_BACK = 3 -- Lv 1: the podium's back wall (Patients' back lane at z = 4 stays outside it)
Building.BACK = 13 -- Lv 2+: the block's back wall
Building.TOWER_FRONT = -3 -- F2 and up: the tower's street face (F1's roof in front of it is the terrace)
Building.GROUND = 11 -- the ground storey's height
Building.STOREY = 9 -- every upper storey
-- A slab is at most this thick, so F1's underside is >= 10.4: Patients' ground raycasts start at +10 and must
-- never meet a slab.
Building.SLAB_MAX = 0.6
Building.SLAB_TOPS = table.freeze({ 11, 20, 29, 38 }) -- F1, F2, F3, the roof deck
Building.WALL = 0.6 -- the outer walls, inside the footprint's edge (clear/reach model them this thick)
Building.MIN_LEVEL = 1
Building.MAX_LEVEL = 5

-- The lift: at the tower's street-facing -x corner, its door on +z, onto a landing on every floor.
Building.SHAFT = table.freeze({ X0 = -11.5, X1 = -6.5, Z0 = -3, Z1 = 2 }) :: Rect
Building.LANDING = table.freeze({ X = -9, Z = 4, Size = 4 }) -- Landing_0 and Floor_<n>.Landing, at each slab top

-- The stair atrium (hospital doc §3.2): two 3-wide lanes, the flights alternating between them. On the ground the
-- G -> 1 flight stands in lane A; upstairs the whole atrium is stairs or a stairwell.
Building.ATRIUM = table.freeze({ X0 = -9, X1 = 9, Z0 = 7, Z1 = 13 }) :: Rect
Building.LANE_A = table.freeze({ X0 = -9, X1 = 9, Z0 = 7, Z1 = 10 }) :: Rect

-- Doorways and windows. On the front wall they are x ranges; on a side wall, z ranges.
Building.DOORS = table.freeze({
	Main = table.freeze({ X0 = 7, X1 = 11, Height = 7 }), -- ground-bed patients walk in along x = 7.6 (bedRoute)
	Reception = table.freeze({ X0 = -6.5, X1 = 6.5, Height = 7 }), -- the open window the Counter sits in
	Display = table.freeze({ X0 = -11, X1 = -7 }), -- glass: decor slot 1 shows through it (solid)
	Side = table.freeze({ Z0 = -1, Z1 = 3 }), -- Lv 1 only, on BOTH side walls (to the Bath Room and the Winter Wing)
	AE = table.freeze({ Z0 = -7, Z1 = -3 }), -- Lv 2+: the -x wall, facing the ambulance bay (a red canopy outside)
	LiftLobby = table.freeze({ Z0 = 2, Z1 = 6 }), -- Lv 2+: the -x wall (upstairs patients come in at z = 4)
	Corridor = table.freeze({ Z0 = 2, Z1 = 6 }), -- Lv 2+: the +x wall (the back lane at z = 4 out to the walkway)
	Partition = table.freeze({ X0 = 8.9, X1 = 11.5 }), -- F1: the doorway in the glass partition, to the front ward
})

-- The canopy over the Counter: soft, overhead, and short of queue spot 1 (z = -18).
Building.CANOPY = table.freeze({ X0 = -9, X1 = 9, Z0 = -17, Z1 = -13, Y = 9.5 })

-- The Stand's spots (the building is built round them; T4's Stand room uses them).
Building.STAND = table.freeze({
	Remedy = table.freeze({ X = -4.3, Z = -1.3 }), -- moved +1.2 in x (clear of the lift shaft)
	Plaster = table.freeze({ X = 1.7, Z = -1.3 }), -- moved +1.2 in x
	Bed = table.freeze({ X = 7.6, Z = -4.8 }), -- Bed_1, unchanged
	Decor = table.freeze({
		table.freeze({ X = -8.5, Z = -10.2 }), -- slot 1, unchanged: behind the display window
		table.freeze({ X = -9.5, Z = -17.5 }), -- slot 2: moved to the porch (the old spot is inside the main door)
	}),
	Mascot = table.freeze({ X = -7, Z = -14.8 }), -- MascotSpot: beside the Counter's -x end
	Bench = table.freeze({ X0 = 10, X1 = 10.9, Z0 = -8, Z1 = -3.5 }), -- the waiting bench, along the +x wall
})
Building.STAND_BED_FRAME = table.freeze({ Width = 4.4, Length = 7 }) -- Bed_1's frame (pillow to +z)

-- The main ward (F1, the tower part): the functional bed spots, pillows toward the glass partition at z = -3.
Building.WARD_FLOOR = 1
Building.BED_HALF = 2.2 -- a bed frame is 4.4 wide ...
Building.BED_Z0 = -2.4 -- ... and runs z -2.4..4.6 (the pillow end is -z)
Building.BED_Z1 = 4.6
Building.BED_FOOT_Z = 6.0 -- the foot spot: in the back aisle, beside the landing
Building.PARTITION_Z = -3 -- the glass partition between the two wards (glass above, headboards below)
-- BedSpot_<n>: its x, and the level from which it is FUNCTIONAL. Spot 3 holds a dressing bed at Lv 2-3.
Building.WARD_BEDS = table.freeze({
	table.freeze({ X = -4.1, Since = 2 }),
	table.freeze({ X = 1.3, Since = 2 }),
	table.freeze({ X = 6.7, Since = 4 }),
})
-- The front ward (F1, over the podium): 4 dressing beds, heads at the street window. Patients never go there.
Building.FRONT_WARD = table.freeze({ Xs = table.freeze({ -8.1, -2.7, 2.7, 8.1 }), Z0 = -12.6, Z1 = -5.6 })
-- Lv 1 only: one dressing bed (with a sleeper) along the -x wall, clear of the side door, decor slot 1 and Remedy.
Building.LV1_DRESSING = table.freeze({ X0 = -11.3, X1 = -6.9, Z0 = -8.5, Z1 = -1.5 }) :: Rect

-- reach() lets a straight walk skim a solid corner by less than this. The plan's own numbers need it: the line from
-- the landing's centre (-9, 4) to BedSpot_3's foot (6.7, 6.0) passes 0.26 studs inside the foot corner of bed 1's
-- frame (z up to 4.6). A patient is about 5 studs wide, so nobody can see that; a real crossing (a bed, the shaft, a
-- wall) is always deeper than this.
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

function Building.slabTop(floor: number): number
	if floor <= 0 then
		return 0
	end
	return Building.SLAB_TOPS[math.min(floor, #Building.SLAB_TOPS)]
end

function Building.footprint(level: number, floor: number?): Rect
	local lv = levelOf(level)
	local k = floor or 0
	local front = if k >= 2 then Building.TOWER_FRONT else Building.FRONT
	local back = if lv <= 1 then Building.PODIUM_BACK else Building.BACK
	return { X0 = -Building.HALF, X1 = Building.HALF, Z0 = front, Z1 = back }
end

function Building.bedRect(x: number): Rect
	return { X0 = x - Building.BED_HALF, X1 = x + Building.BED_HALF, Z0 = Building.BED_Z0, Z1 = Building.BED_Z1 }
end

function Building.bedFoot(x: number): (number, number)
	return x, Building.BED_FOOT_Z
end

function Building.wardBeds(level: number): { WardBed }
	local lv = levelOf(level)
	local beds: { WardBed } = {}
	if lv < 2 then
		return beds
	end
	for index, spot in Building.WARD_BEDS do
		table.insert(beds, { Index = index, X = spot.X, Functional = lv >= spot.Since })
	end
	return beds
end

------------------------------------------------------------------------------------------------------------------
-- What's solid
------------------------------------------------------------------------------------------------------------------

local function add(list: { Obstacle }, name: string, x0: number, x1: number, z0: number, z1: number)
	if x1 - x0 > 1e-6 and z1 - z0 > 1e-6 then
		table.insert(list, { Name = name, X0 = x0, X1 = x1, Z0 = z0, Z1 = z1 })
	end
end

-- A wall along z (a side wall at x0..x1) from z0 to z1, with `gaps` ({ Z0, Z1 } doorways) left open.
local function sideWall(
	list: { Obstacle },
	name: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	gaps: { { Z0: number, Z1: number } }
)
	local at = z0
	for _, gap in gaps do
		add(list, name, x0, x1, at, math.min(gap.Z0, z1))
		at = math.max(at, gap.Z1)
	end
	add(list, name, x0, x1, at, z1)
end

function Building.obstacles(level: number, floor: number?): { Obstacle }
	local lv = levelOf(level)
	local k = floor or 0
	local list: { Obstacle } = {}
	if k > Building.floors(lv) then
		return list -- that floor isn't built at this level
	end
	local f = Building.footprint(lv, k)
	local w = Building.WALL
	local doors = Building.DOORS

	if k == 0 then
		-- The façade: solid at the display window and the two piers; open at the reception window and the main door.
		add(list, "FrontWall", f.X0, doors.Reception.X0, f.Z0, f.Z0 + w)
		add(list, "FrontWall", doors.Reception.X1, doors.Main.X0, f.Z0, f.Z0 + w)
		add(list, "FrontWall", doors.Main.X1, f.X1, f.Z0, f.Z0 + w)
		add(list, "BackWall", f.X0, f.X1, f.Z1 - w, f.Z1)
		if lv <= 1 then
			sideWall(list, "LeftWall", f.X0, f.X0 + w, f.Z0, f.Z1, { doors.Side })
			sideWall(list, "RightWall", f.X1 - w, f.X1, f.Z0, f.Z1, { doors.Side })
			local d = Building.LV1_DRESSING
			add(list, "DressBed", d.X0, d.X1, d.Z0, d.Z1)
		else
			sideWall(list, "LeftWall", f.X0, f.X0 + w, f.Z0, f.Z1, { doors.AE, doors.LiftLobby })
			sideWall(list, "RightWall", f.X1 - w, f.X1, f.Z0, f.Z1, { doors.Corridor })
			local s = Building.SHAFT
			add(list, "Shaft", s.X0, s.X1, s.Z0, s.Z1)
			local a = Building.LANE_A
			add(list, "Stairs", a.X0, a.X1, a.Z0, a.Z1)
		end
		local bed, frame = Building.STAND.Bed, Building.STAND_BED_FRAME
		add(
			list,
			"Bed_1",
			bed.X - frame.Width / 2,
			bed.X + frame.Width / 2,
			bed.Z - frame.Length / 2,
			bed.Z + frame.Length / 2
		)
		local bench = Building.STAND.Bench
		add(list, "Bench", bench.X0, bench.X1, bench.Z0, bench.Z1)
		return list
	end

	-- Upstairs: solid walls all round (kids can't walk out of F3), the shaft and the stair atrium.
	add(list, "FrontWall", f.X0, f.X1, f.Z0, f.Z0 + w)
	add(list, "BackWall", f.X0, f.X1, f.Z1 - w, f.Z1)
	add(list, "LeftWall", f.X0, f.X0 + w, f.Z0, f.Z1)
	add(list, "RightWall", f.X1 - w, f.X1, f.Z0, f.Z1)
	local s = Building.SHAFT
	add(list, "Shaft", s.X0, s.X1, s.Z0, s.Z1)
	local a = Building.ATRIUM
	add(list, "Atrium", a.X0, a.X1, a.Z0, a.Z1)
	if k == Building.WARD_FLOOR then
		for _, bed in Building.wardBeds(lv) do
			local r = Building.bedRect(bed.X)
			add(list, if bed.Functional then "BedSpot_" .. bed.Index else "DressBed", r.X0, r.X1, r.Z0, r.Z1)
		end
		-- The glass partition, from the shaft to its doorway.
		local z = Building.PARTITION_Z
		add(list, "Partition", s.X1, doors.Partition.X0, z - w / 2, z + w / 2)
		local front = Building.FRONT_WARD
		for _, x in front.Xs do
			add(list, "DressBed", x - Building.BED_HALF, x + Building.BED_HALF, front.Z0, front.Z1)
		end
	end
	return list
end

local EPSILON = 0.01

function Building.clear(rect: Rect, level: number): boolean
	for _, o in Building.obstacles(level, 0) do
		if
			rect.X0 < o.X1 - EPSILON
			and o.X0 < rect.X1 - EPSILON
			and rect.Z0 < o.Z1 - EPSILON
			and o.Z0 < rect.Z1 - EPSILON
		then
			return false
		end
	end
	return true
end

-- Whether the segment a -> b passes through the rectangle (Liang-Barsky), after shrinking it by `shrink` a side.
local function crosses(a: Point, b: Point, o: Obstacle, shrink: number): boolean
	local x0, x1, z0, z1 = o.X0 + shrink, o.X1 - shrink, o.Z0 + shrink, o.Z1 - shrink
	if x1 <= x0 or z1 <= z0 then
		-- Thinner than the skim allowance (a wall): test its centre line instead, so a wall is never walked through.
		if x1 <= x0 then
			x0, x1 = (o.X0 + o.X1) / 2 - 1e-3, (o.X0 + o.X1) / 2 + 1e-3
		end
		if z1 <= z0 then
			z0, z1 = (o.Z0 + o.Z1) / 2 - 1e-3, (o.Z0 + o.Z1) / 2 + 1e-3
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

function Building.reach(from: Point, to: Point, level: number, floor: number?): boolean
	for _, o in Building.obstacles(level, floor or 0) do
		if crosses(from, to, o, Building.SKIM) then
			return false
		end
	end
	return true
end

return Building
