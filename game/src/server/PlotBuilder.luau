--!strict
-- Builds the clinic plots and their rooms, and puts the town together (build plan §B1; the Real Clinic build plan,
-- Task 2). Server only.
--   PlotBuilder.buildTown(): { Model }            Workspace.Clinics.Plot_1..N, the town around them, TownSpawn
--   PlotBuilder.buildRoom(roomId): Model           an unplaced room (kit clone or placeholder), PrimaryPart = Floor
--   PlotBuilder.clearPlot(plotModel)               removes patients, decor and every room except the Stand, and
--                                                  puts the Building back to Lv 1's (Level attribute 1)
--   PlotBuilder.buildBuilding(plotModel, level, grewFrom?, theme?): Model   = HospitalBuilder.build: the hospital
--                                                  for that level (Data/Levels) in that branch theme. Replaces
--                                                  Plot.Building, sets the Building's Level, GrewFrom, GrewAt,
--                                                  Floors and Theme and the plot's Level and Theme attributes
-- Extra helpers (Plots uses them):
--   PlotBuilder.placeRoom(plotModel, roomId): Model?      build + place in its slot (Floor.CFrame == slot CFrame)
--   PlotBuilder.setPreview(plotModel, slotId, roomId?)    the "for sale" outline in an empty slot (nil = none)
--   PlotBuilder.SLOTS                                      the room slots on a plot
-- The Real Clinic removed the queue: no QueueStart, no QueueLane and no queueSpot. The line is the Building's waiting
-- room (WaitSeat_<n>, Shared/Logic/Building.SEATS).
--
-- THE SPLIT (look build plan §A/§B4):
--   Server/TownBuilder            the town round the plots, and TownSpawn
--   Server/HospitalBuilder        the Building (Shared/Logic/Building's contract, C1/C2)
--   Server/World/Props            the shared scenery: trees, bushes, lamps, benches, fences
--   Server/World/NightLights      the parts that glow after dark
--   Server/World/Parts            the generic part and label helpers, and the shared look pieces (frozen)
--   Server/World/Studs            the studs look                                                 (frozen)
-- PlotBuilder keeps the plots, the rooms and every public function above, and requires the others (never the other
-- way round: TownBuilder and HospitalBuilder require World/* only). These stay as RE-EXPORTS, so no caller changed:
--   PlotBuilder.NIGHT_LIGHT_TAG   = World/NightLights.TAG     tag a lamp Part: Neon + PointLight on only at night
--   PlotBuilder.STATION_TAG / LIFT_TAG / PROMPT_TAGS   = HospitalBuilder's (CollectionService tags)
--   PlotBuilder.Pure              = HospitalBuilder.Pure      the building's layout in numbers
-- Every plot Model carries the attribute `Accent` (a Color3: its Palette.PlotColors entry), which HospitalBuilder
-- reads, beside PlotIndex, OwnerUserId, OpenHelpers and Hearts.
--
-- THE PLOT (Real Clinic design §8; Shared/Logic/Building, contract C1). A 110 x 110 plot (Config.Town.PlotSize) round
-- the 64 x 44 clinic (x -32..32, z -24..20): the front garden and path (z -55..-24), the ambulance bay's yard on -x
-- (Building.BAY_AMBULANCE.Area, kept clear), a side yard on +x and the Sunny Garden's yard behind (z 20..55).
--   Ground       a Model: the plot's dark studded `Pad` (107 x 107: odd, so its studs fall whole at its edges) framed
--                by 4 Slate `Edge` parts out to the plot's 110 x 110. Patients and Nurses stand creatures on it by the
--                name Ground (their rays include its descendants)
--   Scenery      the plank path from the gate to the Stand's forecourt at the front doors (Building.DOORS.Front), the
--                fence (Props.fence: posts every 14 studs) and the gate (warm-white posts, a studded arch in the
--                plot's colour, two lamps), the mailbox, 5 voxel trees (Props.tree: the big one in the +x side yard,
--                the others in the corners) and 5 one-cube bushes (Props.bush) by the fence. No blossom tree on a
--                plot: Pink is one plot's colour, and the town keeps blossoms to 1 tree in 6
--   Counter      the reception desk INSIDE the lobby, on Building.RECEPTION.Desk (8 x 2.4): a SmoothPlastic body in
--                the plot's colour, its CounterTop studded in warm white (soft), and OUR paw-heart mark
--                (Parts.pawHeart) on its street face, toward the front doors: one SurfaceGui, no cross. Kept by that
--                name at the plot's top level: Plots and Patients find it
--   Markers      PatientSpawn (facing in) and PatientExit (facing the street) just inside the gate; MascotSpot on the
--                Stand's forecourt beside the front doors (Server/Rebirth's mascot, from R5)
--   Sign         the owner's name floats (Parts.floatText: outlined letters, NO board; the Sign part is invisible)
--                between two studded posts in the plot's colour, above the fence. SignGui keeps OwnerName and
--                HeartCount (Plots and Visits write them), RankBadge (Playtime) and BranchBadge (Rebirth): navy pills,
--                hidden until their system fills them
-- THE ROOMS. A room is an INTERIOR FIT-OUT now: no walls and no roof (the Building has them, with each room's door).
-- Its Floor is the slot (CeramicTiles, ROOM_FLOOR thick, laid on the Building's ground floor); everything stays
-- inside its Building.ROOMS rect, inside the partitions, and off its door's span:
--   Stand       the forecourt in front of the doors (tiles, the plot's colour nowhere loud) with its 2 decor slots
--               either side of the canopy. Data/Rooms still lists Remedy, Plaster and a bed for it: those are the
--               Building's now (Station_Remedy in the dispensary, Station_Plaster on the supply shelf), so the
--               Stand's fit-out builds neither
--   BathRoom    (Cyan) Station_Bath (the tub) at the back wall, a bath mat, 1 decor slot
--   WinterWing  (Blue) Station_Cocoa, Bed_1 (a 3-part recovery bed, as before) on the -x wall, a rug, 2 decor slots
--   Ward        (Purple) the Cozy Ward: ExamBay_W1 and ExamBay_W2 to contract C2 at Building.bay("W1"/"W2") (Bed,
--               DoctorSpot, Curtain, Tray, Sign; attributes Bay, Kind, Opens, Face, Room and Open = true: a bay of a
--               room exists only while the room is owned). Its Bed is the mattress the patient sits on (its top
--               ROOM_FLOOR + 1.8 over the pad, its LookVector toward the foot and the DoctorSpot, as the Building's
--               couches), with a Frame and a studded Headboard; 2 small decor slots in the aisle's corners (its
--               3.5-stud aisle is all the floor its two bays leave)
--   Garden      the Sunny Garden behind the Garden door: a studded lawn, studded hedges (back and the back half of the
--               sides) and an arbor with its name. Outdoors
-- Stations in a room carry Open = true (Server/Patients' stationsOnPlot reads Open ~= false) and StationId, as the
-- Building's do; they are NOT tagged HospitalBuilder.STATION_TAG (Server/Stations finds room stations through the
-- rooms, Plots.observeRooms).
-- No Texture or Decal anywhere. Studded parts go through World/Studs with whole-stud X and Z.
--
-- Parts budget (Config.Look; docs/plan/2026-11-16-perf-budget.md): a Lv 5 plot with every room is at most PlotBudget
-- (640) parts without creatures and decor: the Building's share (HospitalBuilder), every room together at most
-- RoomParts (90), and the plot's own share (everything here but the Building and the rooms) at most PlotParts (130).
-- tests/PlotWorld.spec holds the rooms' and the plot's shares; tests/PartBudget.spec the total.
--
-- Coordinates. Each plot has a CFrame at the centre of its ground's TOP face, LookVector pointing at the street
-- (that CFrame is also the plot Model's WorldPivot). In plot-local space +X is right as you face the street, -Z is
-- the street side (front edge z = -55) and +Z the back: Shared/Logic/Building's space. Markers are 2x1x2 invisible
-- Parts resting on the ground. Rooms face the street too. Inside a room Model the Floor's centre is the origin, so
-- y = ROOM_FLOOR / 2 is the top of the Floor.
--
-- The brother's models win: ServerStorage.ClinicKit.<RoomId> replaces a placeholder room, and
-- ServerStorage.ClinicKit.Plot (pivot = ground-top centre, facing the street) replaces the placeholder plot.
-- Workspace.Shop is never touched: the town sits at Config.Town.Origin.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local Building = require(Shared.Logic.Building)
local Rooms = require(Shared.Data.Rooms)
local Stations = require(Shared.Data.Stations)
local HospitalBuilder = require(script.Parent.HospitalBuilder)
local TownBuilder = require(script.Parent.TownBuilder)
local NightLights = require(script.Parent.World.NightLights)
local Parts = require(script.Parent.World.Parts)
local Props = require(script.Parent.World.Props)
local Studs = require(script.Parent.World.Studs)

local part, soft, cylinder = Parts.part, Parts.soft, Parts.cylinder
local ball, marker, paint, rounded = Parts.ball, Parts.marker, Parts.paint, Parts.rounded
local detailGui, iconBadge, iconLabel = Parts.surface, Parts.iconBadge, Parts.iconLabel
local floatText, navyPlate, pawHeart = Parts.floatText, Parts.navyPlate, Parts.pawHeart
local anchorAll, scrubScripts = Parts.anchorAll, Parts.scrubScripts
local ICON_NEAR_STUDS, PREVIEW_NEAR_STUDS = Parts.ICON_NEAR, Parts.PREVIEW_NEAR

local PlotBuilder = {}

PlotBuilder.NIGHT_LIGHT_TAG = NightLights.TAG
PlotBuilder.STATION_TAG = HospitalBuilder.STATION_TAG
PlotBuilder.LIFT_TAG = HospitalBuilder.LIFT_TAG
PlotBuilder.PROMPT_TAGS = HospitalBuilder.PROMPT_TAGS
PlotBuilder.Pure = HospitalBuilder.Pure

type Rect = Building.Rect

local ROOM_FLOOR = 0.2 -- every room's Floor: laid on the Building's ground floor (slab top 0) or the pad

-- A ground-floor room's floor inside its walls: its Building.ROOMS rect pulled in past every wall Building.obstacles
-- puts across one of its edges (the outer walls, the 0.4 partitions). Bought rooms' doors are modelled open, so a
-- door never moves an edge.
local function innerRect(room: Rect): Rect
	local r = { X0 = room.X0, X1 = room.X1, Z0 = room.Z0, Z1 = room.Z1 }
	local midX, midZ = (room.X0 + room.X1) / 2, (room.Z0 + room.Z1) / 2
	for _, o in Building.obstacles(Building.MAX_LEVEL, 0) do
		local wall = string.match(o.Name, "Wall$") ~= nil
		if wall and o.X0 < room.X1 and o.X1 > room.X0 and o.Z0 < room.Z1 and o.Z1 > room.Z0 then
			if o.X1 - o.X0 < 1 and o.Z1 - o.Z0 >= 1 then
				if (o.X0 + o.X1) / 2 < midX then
					r.X0 = math.max(r.X0, o.X1)
				else
					r.X1 = math.min(r.X1, o.X0)
				end
			elseif o.Z1 - o.Z0 < 1 and o.X1 - o.X0 >= 1 then
				if (o.Z0 + o.Z1) / 2 < midZ then
					r.Z0 = math.max(r.Z0, o.Z1)
				else
					r.Z1 = math.min(r.Z1, o.Z0)
				end
			end
		end
	end
	return table.freeze(r)
end

-- Each bought room inside the Building: its Building.ROOMS name, and its floor inside the walls (plot-local).
local INTERIOR_ROOM = table.freeze({ BathRoom = "BathRoom", WinterWing = "WinterWing", Ward = "CozyWard" })
local INNER: { [string]: Rect } = {}
for roomId, name in INTERIOR_ROOM do
	INNER[roomId] = innerRect((Building.ROOMS :: any)[name])
end

-- The Stand's forecourt: in front of the front doors, under and either side of the canopy (Building.CANOPY), from
-- the façade (Building.FRONT) out FORECOURT_DEPTH.
local FORECOURT_HALF = 16
local FORECOURT_DEPTH = 7
-- The Sunny Garden: behind the Garden door (Building.DOORS.Garden), from the back wall out GARDEN_SIZE.Y. Whole studs
-- (its lawn is studded).
local GARDEN_SIZE = Vector2.new(24, 18)
local GARDEN_X = (Building.DOORS.Garden.X0 :: number + Building.DOORS.Garden.X1 :: number) / 2

local function slotOf(r: Rect)
	return table.freeze({
		Offset = Vector3.new((r.X0 + r.X1) / 2, ROOM_FLOOR / 2, (r.Z0 + r.Z1) / 2),
		Size = Vector3.new(r.X1 - r.X0, ROOM_FLOOR, r.Z1 - r.Z0),
	})
end

-- Room slots, plot-local. Offset is the slot (= Floor) centre; Size is the floor. Data/Rooms names each room's slot:
-- Stand = the forecourt, A = the Bath Room, B = the Cozy Ward, C = the Winter Wing (all three inside the Building's
-- ground floor, Building.ROOMS), D = the Sunny Garden behind the Building.
PlotBuilder.SLOTS = table.freeze({
	Stand = slotOf({
		X0 = -FORECOURT_HALF,
		X1 = FORECOURT_HALF,
		Z0 = Building.FRONT - FORECOURT_DEPTH,
		Z1 = Building.FRONT,
	}),
	A = slotOf(INNER.BathRoom),
	B = slotOf(INNER.Ward),
	C = slotOf(INNER.WinterWing),
	D = slotOf({
		X0 = GARDEN_X - GARDEN_SIZE.X / 2,
		X1 = GARDEN_X + GARDEN_SIZE.X / 2,
		Z0 = Building.BACK,
		Z1 = Building.BACK + GARDEN_SIZE.Y,
	}),
})

local STREET_HALF_WIDTH = 18
local PLOT_GAP = 8
local BASE_TOP = 0.3 -- the town lawn's top, just above a default baseplate at y = 0 (TownBuilder's too)
local PLOT_RAISE = 0.6 -- plots sit a small step above the street
local MAX_PLOTS = 6

local WORLD = Palette.World
local ACCENT = Palette.Accent

-- The look's colours, by job (Palette.World / Palette.Accent; art-direction §4.1). No lerp toward white anywhere.
local COLORS = {
	Pad = WORLD.Pad, -- the plot's floor: a dark anchor, studded
	Edge = WORLD.Edge, -- the stone edging round it (Slate)
	Path = WORLD.Plank, -- WoodPlanks
	Fence = WORLD.Fence, -- the gate posts (the fence itself is Props')
	Trim = WORLD.Trim, -- warm white: the CounterTop, station tops, mattresses, trays, decor spots
	Floor = WORLD.FloorTile, -- room floors: CeramicTiles (Joshua 2026-11-17: "floor texture shouldnt be wood")
	Wood = WORLD.Beam, -- the arbor's posts
	Lawn = WORLD.GrassA, -- the Garden's floor, studded
	Hedge = WORLD.LeavesB, -- the Garden's hedges, studded
	Vine = WORLD.LeavesA, -- the arbor's beam, studded
	LampGlow = WORLD.Lamp,
	Water = WORLD.Water,
	Flag = ACCENT.Red, -- the mailbox flag (Red: props only)
	ForSale = ACCENT.Yellow,
	Mug = WORLD.Trim,
}

-- Plot_n's own accent (Palette.PlotColors).
local function plotAccentFor(index: number): Color3
	local colors = Palette.PlotColors
	return colors[(index - 1) % #colors + 1]
end

-- A station's colour in the WORLD: Data/Stations gives the UI's Candy colour (kids match it to the plan step); a world
-- part wears the calmer world accent of the same name (Palette.Accent), so the hue still matches. A colour with no
-- world twin stays as it is.
local function worldColor(color: Color3): Color3
	for name, candy in Palette.Candy do
		if candy == color then
			local twin = (ACCENT :: any)[name]
			return if typeof(twin) == "Color3" then twin else color
		end
	end
	return color
end

-- Each room's colour (art-direction §4.1: Bath = Cyan, Ward = Purple, Winter Wing = Blue, Garden = leaves; the Stand
-- = its plot's colour): bed frames, headboards, curtains, mats and rugs.
local ROOM_COLOUR: { [string]: Color3 } = {
	BathRoom = ACCENT.Cyan,
	Ward = ACCENT.Purple,
	WinterWing = ACCENT.Blue,
	Garden = WORLD.LeavesA,
}

local function colourFor(roomId: string, accent: Color3?): Color3
	if roomId == "Stand" then
		return accent or ACCENT.Pink
	end
	return ROOM_COLOUR[roomId] or ACCENT.Orange
end

------------------------------------------------------------------------------------------------------------------
-- Room layouts: where things go in each fit-out (room-local x, z: the Floor's centre is the origin)
------------------------------------------------------------------------------------------------------------------

type Spot = { At: Vector3, Size: number } -- a decor slot: its centre and its square marker's side
type Layout = {
	Stations: { [string]: Vector3 },
	Beds: { Vector3 },
	Bays: { Building.Bay },
	Decor: { Spot },
	Mats: { { Name: string, At: Vector3, Size: Vector2 } },
}

-- The Building builds these rooms' stations and beds itself (Data/Rooms still lists them for the Stand: the free
-- clinic's Remedy and Plaster, now Station_Remedy in the dispensary and Station_Plaster on the supply shelf).
local BUILDING_OWNS: { [string]: boolean } = { Stand = true }

-- A room's own exam bays (Building.BAYS whose Room is that room: the Cozy Ward's W1 and W2).
local function baysOf(roomId: string): { Building.Bay }
	local out: { Building.Bay } = {}
	for _, bay in Building.BAYS do
		if bay.Room == roomId then
			table.insert(out, bay)
		end
	end
	return out
end

-- The stations a room's fit-out builds: its Data/Rooms stations, less the ones the Building builds.
local function ownStations(roomId: string): { string }
	local out: { string } = {}
	if BUILDING_OWNS[roomId] then
		return out
	end
	for _, stationId in Rooms[roomId].Stations do
		if not Building.STATIONS[stationId] then
			table.insert(out, stationId)
		end
	end
	return out
end

-- The Bed_<n> recovery beds a room's fit-out builds: its Data/Rooms beds, less the ones its exam bays stand for (the
-- Cozy Ward's 2 beds ARE its bays' beds) and none for a room whose bed the Building has.
local function ownBeds(roomId: string): number
	if BUILDING_OWNS[roomId] then
		return 0
	end
	return math.max(0, Rooms[roomId].Beds - #baysOf(roomId))
end

local function slotCentre(roomId: string): Vector3
	local room = Rooms[roomId]
	local slot = room and PlotBuilder.SLOTS[room.Slot]
	return if slot then slot.Offset else Vector3.zero
end

-- Plot-local (x, z) into the room's own space.
local function roomLocal(roomId: string, x: number, z: number): Vector3
	local centre = slotCentre(roomId)
	return Vector3.new(x - centre.X, 0, z - centre.Z)
end

local FULL_DECOR = 4 -- a decor model fits a 4 x 4 footprint (Server/DecorBuilder's contract)
local BED_DEPTH = 8 -- a recovery bed's frame (7) and its headboard (1), head to foot
local COCOA_DEPTH = 3 -- the Cocoa table's studded top, out from the wall

local function bathLayout(): Layout
	local r = INNER.BathRoom
	local midX = (r.X0 + r.X1) / 2
	local tubX = midX + 2
	return {
		Stations = { Bath = roomLocal("BathRoom", tubX, r.Z1 - 2) },
		Beds = {},
		Bays = {},
		Decor = { { At = roomLocal("BathRoom", r.X0 + 2.2, r.Z1 - 2.2), Size = FULL_DECOR } },
		Mats = { { Name = "BathMat", At = roomLocal("BathRoom", tubX, r.Z1 - 5.2), Size = Vector2.new(4, 2) } },
	}
end

local function winterLayout(): Layout
	local r = INNER.WinterWing
	local bedX = r.X0 + 0.2 + Building.BED_HALF
	local cocoaX = r.X1 - 2.2
	-- decor slot 2 sits between the bed's frame and the Cocoa table, at the back
	local between0, between1 = bedX + Building.BED_HALF, cocoaX - 2
	return {
		Stations = { Cocoa = roomLocal("WinterWing", cocoaX, r.Z1 - COCOA_DEPTH / 2 - 0.2) },
		Beds = { roomLocal("WinterWing", bedX, r.Z1 - BED_DEPTH / 2 - 0.5) },
		Bays = {},
		Decor = {
			{ At = roomLocal("WinterWing", r.X1 - 2, r.Z0 + 2.1), Size = FULL_DECOR },
			{
				At = roomLocal("WinterWing", (between0 + between1) / 2, r.Z1 - 2.1),
				Size = math.min(FULL_DECOR, between1 - between0 - 0.2),
			},
		},
		Mats = {
			{
				Name = "Rug",
				At = roomLocal("WinterWing", (between0 + r.X1 - 4) / 2, r.Z0 + 4.9),
				Size = Vector2.new(3.6, 2.6),
			},
		},
	}
end

-- The Cozy Ward: its two bays fill the back; the aisle in front (to the bays' DoctorSpots) leaves a small decor spot in
-- each corner, between the side wall and the DoctorSpot nearest it.
local DOCTOR_ROOM = 1.2 -- clear either side of a DoctorSpot (where the doctor stands)
local function wardLayout(): Layout
	local r = INNER.Ward
	local bays = baysOf("Ward")
	local spots: { Spot } = {}
	if #bays > 0 then
		local left, right = math.huge, -math.huge
		for _, bay in bays do
			local spot = Building.doctorSpot(bay)
			left = math.min(left, spot.X - DOCTOR_ROOM)
			right = math.max(right, spot.X + DOCTOR_ROOM)
		end
		local aisle = math.huge
		for _, bay in bays do
			aisle = math.min(aisle, Building.bayBed(bay).Z0)
		end
		local z = (r.Z0 + aisle) / 2
		local leftSize = math.min(FULL_DECOR, left - r.X0 - 0.2)
		local rightSize = math.min(FULL_DECOR, r.X1 - right - 0.2)
		table.insert(spots, { At = roomLocal("Ward", (r.X0 + left) / 2, z), Size = leftSize })
		table.insert(spots, { At = roomLocal("Ward", (right + r.X1) / 2, z), Size = rightSize })
	end
	return { Stations = {}, Beds = {}, Bays = bays, Decor = spots, Mats = {} }
end

local function standLayout(): Layout
	local canopy = Building.CANOPY
	local z = Building.FRONT - FORECOURT_DEPTH / 2
	local x = (canopy.X1 + FORECOURT_HALF) / 2 -- beside the canopy, out to the forecourt's end
	return {
		Stations = {},
		Beds = {},
		Bays = {},
		Decor = {
			{ At = roomLocal("Stand", -x, z), Size = FULL_DECOR },
			{ At = roomLocal("Stand", x, z), Size = FULL_DECOR },
		},
		Mats = {},
	}
end

local function gardenLayout(): Layout
	return {
		Stations = {},
		Beds = {},
		Bays = {},
		Decor = {
			{ At = Vector3.new(-7.5, 0, -2), Size = FULL_DECOR },
			{ At = Vector3.new(7.5, 0, -2), Size = FULL_DECOR },
			{ At = Vector3.new(0, 0, 3), Size = FULL_DECOR },
		},
		Mats = {},
	}
end

local LAYOUTS: { [string]: () -> Layout } = {
	Stand = standLayout,
	BathRoom = bathLayout,
	WinterWing = winterLayout,
	Ward = wardLayout,
	Garden = gardenLayout,
}

local function slotSize(roomId: string): Vector3
	local room = Rooms[roomId]
	local slot = room and PlotBuilder.SLOTS[room.Slot]
	return if slot then slot.Size else Vector3.new(12, ROOM_FLOOR, 10)
end

-- Fallback positions if Data/Rooms counts ever outgrow a layout: stations along the back, beds along the sides,
-- decor along the front.
local function genericLayout(roomId: string, w: number, d: number): Layout
	local room = Rooms[roomId]
	local layout: Layout = { Stations = {}, Beds = {}, Bays = baysOf(roomId), Decor = {}, Mats = {} }
	local stations = ownStations(roomId)
	for i, stationId in stations do
		layout.Stations[stationId] = Vector3.new((i - (#stations + 1) / 2) * 5, 0, d / 2 - 2)
	end
	for i = 1, ownBeds(roomId) do
		local side = if i % 2 == 1 then 1 else -1
		layout.Beds[i] = Vector3.new(side * (w / 2 - 2.6), 0, d / 2 - 4.5)
	end
	for i = 1, room.DecorSlots do
		layout.Decor[i] = {
			At = Vector3.new((i - (room.DecorSlots + 1) / 2) * (w / (room.DecorSlots + 1)), 0, -d / 2 + 2),
			Size = 2,
		}
	end
	return layout
end

local function layoutFor(roomId: string, w: number, d: number): Layout
	local room = Rooms[roomId]
	local make = LAYOUTS[roomId]
	if make then
		local layout = make()
		local stationsOk = true
		for _, stationId in ownStations(roomId) do
			if not layout.Stations[stationId] then
				stationsOk = false
			end
		end
		if stationsOk and #layout.Beds == ownBeds(roomId) and #layout.Decor == room.DecorSlots then
			return layout
		end
		warn("[PlotBuilder] Layout for", roomId, "doesn't match Data/Rooms; using a generic one")
	end
	return genericLayout(roomId, w, d)
end

------------------------------------------------------------------------------------------------------------------
-- Room pieces
------------------------------------------------------------------------------------------------------------------

-- A table station: its body in the station's colour, a studded warm-white Top in whole studs, and a few blocky props
-- on it. The Bath is a tub. Its front (where the player stands) is the room's front, -z.
local STATION_BODY = Vector3.new(3.8, 3, 2.6)
local STATION_TOP = Vector3.new(4, 0.3, COCOA_DEPTH)

local function buildStation(model: Model, stationId: string, at: Vector3, floorTop: number)
	local station = Stations[stationId]
	local uiColor = if station then station.Color else Palette.Candy.Orange
	local color = worldColor(uiColor)
	local icon = if station then station.Icon else "❔"
	local base = CFrame.new(at.X, floorTop, at.Z)
	local stationPart: BasePart

	if stationId == "Bath" then
		-- A warm-white tub with a band in the station's colour round it and the water on top.
		stationPart = part(model, "Station_Bath", Vector3.new(5.6, 2.2, 3.6), base * CFrame.new(0, 1.1, 0), COLORS.Trim)
		soft(part(model, "TubStripe", Vector3.new(5.68, 0.5, 3.68), base * CFrame.new(0, 1.4, 0), color))
		paint(part(model, "Water", Vector3.new(5, 0.15, 3), base * CFrame.new(0, 2.15, 0), COLORS.Water))
	else
		local body = STATION_BODY
		local back = (STATION_TOP.Z - body.Z) / 2 -- the body stands against the wall, under the Top's back edge
		stationPart =
			part(model, "Station_" .. stationId, body, base * CFrame.new(0, body.Y / 2, back), color) :: BasePart
		local top =
			soft(part(model, "Top", STATION_TOP, base * CFrame.new(0, body.Y + STATION_TOP.Y / 2, 0), COLORS.Trim))
		Studs.apply(top)
		local on = base * CFrame.new(0, body.Y + STATION_TOP.Y, 0) -- the Top's upper face
		if stationId == "Cocoa" then
			soft(part(model, "Mug", Vector3.new(0.8, 0.9, 0.8), on * CFrame.new(-0.9, 0.45, 0.1), COLORS.Mug))
			soft(part(model, "Pot", Vector3.new(1.3, 1.1, 1.3), on * CFrame.new(0.9, 0.55, 0.2), ACCENT.Red))
		end
	end
	stationPart:SetAttribute("Open", true) -- a room's station works while the room stands (it's owned)
	stationPart:SetAttribute("StationId", stationId) -- as the Building's Station_<id> parts carry

	-- The floating icon badge is a billboard (unlit, like the UI), so its ring keeps the UI's colour.
	iconBadge(stationPart, "IconGui", icon, uiColor, 2.6, stationPart.Size.Y / 2 + 2.1)
end

-- A recovery bed: 3 parts (the look build plan's bed contract). Frame in the room's colour, a studded Headboard in it
-- (whole studs), and Bed_<n>, the warm-white mattress patients lie on (its top face; the pillow end is +Z, the room's
-- back). Bed_<n>'s size is unchanged, so a patient lies exactly as before.
local function buildBed(model: Model, index: number, at: Vector3, color: Color3, floorTop: number)
	local base = CFrame.new(at.X, floorTop, at.Z)
	part(model, "Frame", Vector3.new(4.4, 0.8, 7), base * CFrame.new(0, 0.4, 0), color)
	part(model, "Bed_" .. index, Vector3.new(4, 1, 6.6), base * CFrame.new(0, 1.3, 0), COLORS.Trim)
	Studs.apply(part(model, "Headboard", Vector3.new(4, 2.6, 1), base * CFrame.new(0, 1.3, 4), color))
end

-- An exam bay of a room (contract C2: ExamBay_<id>, built here for the Cozy Ward's W1 and W2). The bed fills
-- Building.bayBed (a Frame in the room's colour, the warm-white `Bed` the patient sits on, a studded Headboard at the
-- head end), a soft Curtain on the side toward the room's middle, a Tray cart at the head on the other side, a Sign
-- on the wall over the head (the room's icon and the bay's number in it: "🛏️ 1", so a kid reads "bed 1"), and the
-- DoctorSpot marker at Building.doctorSpot, facing the bed. `toRoom` turns Building's plot-local (x, z) into the room's
-- own space.
local BAY_MATTRESS = 6 -- the Bed: from the foot end, leaving the head end to the Headboard
local CURTAIN_HEIGHT = 5.6

local function buildBay(
	model: Model,
	bay: Building.Bay,
	color: Color3,
	floorTop: number,
	toRoom: (number, number) -> Vector3,
	label: string
)
	local m = Instance.new("Model")
	m.Name = "ExamBay_" .. bay.Id
	m:SetAttribute("Bay", bay.Id)
	m:SetAttribute("Kind", bay.Kind)
	m:SetAttribute("Opens", bay.Opens)
	m:SetAttribute("Face", bay.Face)
	m:SetAttribute("Room", bay.Room)
	m:SetAttribute("Open", true) -- a room's bay exists only while the room is owned
	local turn = CFrame.Angles(0, math.rad(bay.Face), 0) -- local -Z is the bed's foot (its front)
	local centre = toRoom(bay.X, bay.Z)
	local base = CFrame.new(centre.X, floorTop, centre.Z) * turn
	local width, length = Building.BAY_BED.Width, Building.BAY_BED.Length

	part(m, "Frame", Vector3.new(width, 0.8, length), base * CFrame.new(0, 0.4, 0), color)
	local headDepth = length - BAY_MATTRESS
	local bed = part(
		m,
		"Bed",
		Vector3.new(width - 0.4, 1, BAY_MATTRESS),
		base * CFrame.new(0, 1.3, -headDepth / 2),
		COLORS.Trim
	)
	Studs.apply(
		part(
			m,
			"Headboard",
			Vector3.new(math.floor(width - 0.4), 2.6, math.floor(headDepth)),
			base * CFrame.new(0, 1.3, length / 2 - headDepth / 2),
			color
		)
	)
	m.PrimaryPart = bed

	-- The curtain hangs along the side toward the room's middle; the tray stands at the head on the other side.
	local inward = if centre.X < 0 then 1 else -1
	local curtain = soft(
		part(
			m,
			"Curtain",
			Vector3.new(0.2, CURTAIN_HEIGHT, length - 1),
			base * CFrame.new(inward * (width / 2 + 0.4), 1 + CURTAIN_HEIGHT / 2, 0.5),
			color,
			Enum.Material.Fabric
		)
	)
	curtain.CastShadow = false
	part(
		m,
		"Tray",
		Vector3.new(1, 2.8, 1.4),
		base * CFrame.new(-inward * (width / 2 + 0.6), 1.4, length / 2 - 1),
		COLORS.Trim
	)
	local sign = soft(part(m, "Sign", Vector3.new(2, 1.2, 0.2), base * CFrame.new(0, 5.4, length / 2 - 0.2), color))
	local gui = detailGui(sign, "SignGui", Enum.NormalId.Front, 40, 60)
	floatText(gui, label, { Size = UDim2.fromScale(0.9, 0.9), Position = UDim2.fromScale(0.05, 0.05) })

	local spot = Building.doctorSpot(bay)
	local at = toRoom(spot.X, spot.Z)
	marker(m, "DoctorSpot", CFrame.new(at.X, floorTop + 0.5, at.Z) * turn * CFrame.Angles(0, math.pi, 0))
	m.Parent = model
end

-- A decor slot: the invisible square marker (Plots puts decor on its bottom face) and a warm-white spot that shows
-- where decor goes, both resting on the floor.
local function buildDecorSlot(model: Model, index: number, spot: Spot, floorTop: number)
	local side = spot.Size
	marker(model, "DecorSlot_" .. index, CFrame.new(spot.At.X, floorTop + 0.5, spot.At.Z), Vector3.new(side, 1, side))
	paint(
		cylinder(model, "DecorSpot", 0.06, side - 0.6, CFrame.new(spot.At.X, floorTop + 0.03, spot.At.Z), COLORS.Trim)
	)
end

-- A flat mat or rug on the floor, in the room's colour.
local function buildMat(model: Model, name: string, at: Vector3, size: Vector2, color: Color3, floorTop: number)
	paint(part(model, name, Vector3.new(size.X, 0.06, size.Y), CFrame.new(at.X, floorTop + 0.03, at.Z), color))
end

-- The room's name in floating outlined letters (no board) on a face: bright at night like the signs.
type RoomInfo = { Icon: string, Name: string }

local function nameOn(p: BasePart, room: RoomInfo)
	local gui = detailGui(p, "NameGui", Enum.NormalId.Front, 40, 120, 0)
	floatText(gui, room.Icon .. " " .. room.Name, {
		Shadow = true,
		Size = UDim2.fromScale(0.9, 0.84),
		Position = UDim2.fromScale(0.05, 0.08),
	})
end

-- The Garden: a studded lawn (its Floor), studded hedges on three sides (the side ones on the back half; the front
-- stays open to the Garden door) and an arbor at the back: two wood posts and a studded beam of leaves with the name.
local function buildGarden(model: Model, room: RoomInfo, w: number, d: number, floorTop: number)
	local back = d / 2
	Studs.apply(part(model, "BackHedge", Vector3.new(w, 3, 1), CFrame.new(0, floorTop + 1.5, back - 0.5), COLORS.Hedge))
	local sideDepth = back - 1
	for _, side in { -1, 1 } do
		Studs.apply(
			part(
				model,
				"SideHedge",
				Vector3.new(1, 2, sideDepth),
				CFrame.new(side * (w / 2 - 0.5), floorTop + 1, sideDepth / 2),
				COLORS.Hedge
			)
		)
	end
	local arborZ = back - 1.5
	for _, side in { -1, 1 } do
		part(model, "ArborPost", Vector3.new(0.8, 7, 0.8), CFrame.new(side * 4.5, floorTop + 3.5, arborZ), COLORS.Wood)
	end
	-- Overhead and walk-through: no ray (Patients', Nurses') ever lands a creature on it.
	local beam =
		soft(part(model, "ArborBeam", Vector3.new(11, 1.5, 2), CFrame.new(0, floorTop + 7.75, arborZ), COLORS.Vine))
	Studs.apply(beam)
	nameOn(beam, room)
end

local function placeholderRoom(roomId: string, accent: Color3?): Model
	local room = Rooms[roomId]
	local color = colourFor(roomId, accent)
	local size = slotSize(roomId)
	local w, d = size.X, size.Z
	local floorTop = size.Y / 2

	local model = Instance.new("Model")
	model.Name = "Room_" .. roomId
	local floor: BasePart
	if roomId == "Garden" then
		floor = part(model, "Floor", size, CFrame.identity, COLORS.Lawn)
		Studs.apply(floor)
	else
		floor = part(model, "Floor", size, CFrame.identity, COLORS.Floor, Enum.Material.CeramicTiles)
	end
	model.PrimaryPart = floor

	if roomId == "Garden" then
		buildGarden(model, room, w, d, floorTop)
	end

	local layout = layoutFor(roomId, w, d)
	for _, stationId in ownStations(roomId) do
		buildStation(model, stationId, layout.Stations[stationId], floorTop)
	end
	for index, at in layout.Beds do
		buildBed(model, index, at, color, floorTop)
	end
	local function toRoom(x: number, z: number): Vector3
		return roomLocal(roomId, x, z)
	end
	for index, bay in layout.Bays do
		buildBay(model, bay, color, floorTop, toRoom, room.Icon .. " " .. index)
	end
	for _, mat in layout.Mats do
		buildMat(model, mat.Name, mat.At, mat.Size, color, floorTop)
	end
	for index, spot in layout.Decor do
		buildDecorSlot(model, index, spot, floorTop)
	end
	return model
end

-- The part a station's icon badge floats over, and how far its top is above that part's centre.
local function stationAdornee(station: Instance): (BasePart?, number)
	if station:IsA("BasePart") then
		return station, station.Size.Y / 2
	end
	if station:IsA("Model") then
		local found = station.PrimaryPart or station:FindFirstChildWhichIsA("BasePart", true)
		if found then
			local box, size = station:GetBoundingBox()
			return found, (box.Position.Y + size.Y / 2) - found.Position.Y
		end
	end
	return nil, 0
end

local function kitRoom(roomId: string): Model?
	local kit = ServerStorage:FindFirstChild("ClinicKit")
	local template = kit and kit:FindFirstChild(roomId)
	if not (template and template:IsA("Model")) then
		return nil
	end
	local model = template:Clone()
	local floor = model:FindFirstChild("Floor") or model:FindFirstChild("Floor", true)
	if not (floor and floor:IsA("BasePart")) then
		warn("[PlotBuilder] ClinicKit." .. roomId .. " has no Part named Floor; using the placeholder")
		model:Destroy()
		return nil
	end
	model.PrimaryPart = floor
	model.Name = "Room_" .. roomId
	scrubScripts(model, "ClinicKit." .. roomId)
	anchorAll(model)

	local room = Rooms[roomId]
	for _, stationId in ownStations(roomId) do
		local station = model:FindFirstChild("Station_" .. stationId, true)
		if not station then
			warn("[PlotBuilder] ClinicKit." .. roomId .. " is missing Station_" .. stationId)
		else
			station:SetAttribute("Open", true)
			station:SetAttribute("StationId", stationId)
			local kitIcon = station:FindFirstChild("IconGui", true)
			if not kitIcon then
				-- Placeholder stations carry their icon badge; give the brother's the same one.
				local adornee, top = stationAdornee(station)
				local data = Stations[stationId]
				if adornee and data then
					iconBadge(adornee, "IconGui", data.Icon, data.Color, 2.6, top + 2.1)
				end
			elseif kitIcon:IsA("BillboardGui") and kitIcon.DistanceLowerLimit <= 0 then
				kitIcon.DistanceLowerLimit = ICON_NEAR_STUDS -- the brother's own icon gets the same cap
			end
		end
	end
	for i = 1, ownBeds(roomId) do
		if not model:FindFirstChild("Bed_" .. i, true) then
			warn("[PlotBuilder] ClinicKit." .. roomId .. " is missing Bed_" .. i)
		end
	end
	for _, bay in baysOf(roomId) do
		local found = model:FindFirstChild("ExamBay_" .. bay.Id, true)
		if not found then
			warn("[PlotBuilder] ClinicKit." .. roomId .. " is missing ExamBay_" .. bay.Id)
		else
			found:SetAttribute("Bay", bay.Id)
			found:SetAttribute("Kind", bay.Kind)
			found:SetAttribute("Opens", bay.Opens)
			found:SetAttribute("Face", bay.Face)
			found:SetAttribute("Room", bay.Room)
			found:SetAttribute("Open", true)
		end
	end
	for i = 1, room.DecorSlots do
		if not model:FindFirstChild("DecorSlot_" .. i, true) then
			warn("[PlotBuilder] ClinicKit." .. roomId .. " is missing DecorSlot_" .. i)
		end
	end
	return model
end

-- `accent` is the plot's colour, for the Stand (a kit room ignores it).
local function buildRoomModel(roomId: string, accent: Color3?): Model
	assert(Rooms[roomId], "Unknown room " .. tostring(roomId))
	local model = kitRoom(roomId) or placeholderRoom(roomId, accent)
	model:SetAttribute("RoomId", roomId)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- a room streams in whole, with its stations
	return model
end

function PlotBuilder.buildRoom(roomId: string): Model
	return buildRoomModel(roomId, nil)
end

local function plotAccent(plotModel: Model): Color3?
	local index = plotModel:GetAttribute("PlotIndex")
	return if type(index) == "number" then plotAccentFor(index) else nil
end

function PlotBuilder.placeRoom(plotModel: Model, roomId: string): Model?
	local room = Rooms[roomId]
	local roomsFolder = plotModel:FindFirstChild("Rooms")
	local slots = plotModel:FindFirstChild("Slots")
	if not (room and roomsFolder and slots) then
		return nil
	end
	local existing = roomsFolder:FindFirstChild("Room_" .. roomId)
	if existing and existing:IsA("Model") then
		return existing
	end
	local slot = slots:FindFirstChild("RoomSlot_" .. room.Slot)
	if not (slot and slot:IsA("BasePart")) then
		warn("[PlotBuilder]", plotModel.Name, "has no RoomSlot_" .. room.Slot)
		return nil
	end

	local model = buildRoomModel(roomId, plotAccent(plotModel))
	local floor = model.PrimaryPart :: BasePart
	model:PivotTo(slot.CFrame * floor.CFrame:ToObjectSpace(model:GetPivot()))
	model.Parent = roomsFolder
	PlotBuilder.setPreview(plotModel, room.Slot, nil)
	return model
end

------------------------------------------------------------------------------------------------------------------
-- Slot previews ("for sale"): a see-through yellow floor, a dashed outline and a floating price on a navy plate
------------------------------------------------------------------------------------------------------------------

function PlotBuilder.setPreview(plotModel: Model, slotId: string, roomId: string?)
	local slots = plotModel:FindFirstChild("Slots")
	local slot = slots and slots:FindFirstChild("RoomSlot_" .. slotId)
	if not (slot and slot:IsA("BasePart")) then
		return
	end
	local old = slot:FindFirstChild("Preview")
	if old then
		old:Destroy()
	end
	local room = roomId and Rooms[roomId]
	if not room then
		return
	end

	local preview = Instance.new("Model")
	preview.Name = "Preview"
	local w, d = slot.Size.X, slot.Size.Z
	local ground = slot.CFrame * CFrame.new(0, -slot.Size.Y / 2 + 0.06, 0)
	local fill = paint(
		part(preview, "Fill", Vector3.new(w - 0.6, 0.04, d - 0.6), ground * CFrame.new(0, 0.01, 0), COLORS.ForSale)
	)
	fill.Transparency = 0.65
	local dash = 2.2
	local n = 0
	for _, edge in { { w, -d / 2, 0 }, { w, d / 2, 0 }, { d, -w / 2, 90 }, { d, w / 2, 90 } } do
		local length, offset, angle = edge[1], edge[2], edge[3]
		local count = math.floor(length / (dash * 2))
		for i = 0, count - 1 do
			local along = -length / 2 + dash / 2 + i * dash * 2 + (length - count * dash * 2 + dash) / 2
			local cf = if angle == 0
				then ground * CFrame.new(along, 0, offset)
				else ground * CFrame.new(offset, 0, along) * CFrame.Angles(0, math.rad(90), 0)
			n += 1
			local color = if n % 2 == 0 then COLORS.Trim else COLORS.ForSale
			paint(part(preview, "Dash", Vector3.new(dash, 0.14, 0.6), cf, color))
		end
	end

	-- The price: a navy plate (a world information plate) with the room's icon and its price floating on it. A room
	-- costs in-game 💰 and ⭐ only, and nothing here counts down.
	local anchor = marker(preview, "BadgeAnchor", ground * CFrame.new(0, 3.5, 0), Vector3.one)
	local gui = Instance.new("BillboardGui")
	gui.Name = "PreviewGui"
	gui.Size = UDim2.fromScale(6, 4)
	gui.LightInfluence = 0
	gui.MaxDistance = 90
	gui.DistanceLowerLimit = PREVIEW_NEAR_STUDS
	navyPlate(gui)
	local icon = iconLabel(gui, "Icon", "🔒" .. room.Icon, UDim2.fromScale(0.86, 0.46), UDim2.fromScale(0.07, 0.08))
	icon.ZIndex = 3
	local cost = floatText(gui, string.format("⭐%d  💰%d", room.StarsNeeded, room.Price), {
		Size = UDim2.fromScale(0.86, 0.34),
		Position = UDim2.fromScale(0.07, 0.57),
	})
	cost.Name = "Cost"
	gui.Parent = anchor
	preview.Parent = slot
end

------------------------------------------------------------------------------------------------------------------
-- Plots
------------------------------------------------------------------------------------------------------------------

local function plotCFrame(index: number, count: number): CFrame
	local origin = Config.Town.Origin
	local size = Config.Town.PlotSize
	local perRow = math.ceil(count / 2)
	local row = if index <= perRow then 1 else 2
	local column = if row == 1 then index else index - perRow
	local x = (column - (perRow + 1) / 2) * (size + PLOT_GAP)
	local z = STREET_HALF_WIDTH + size / 2
	local centre = origin + Vector3.new(x, BASE_TOP + PLOT_RAISE, if row == 1 then -z else z)
	local facing = if row == 1 then Vector3.zAxis else -Vector3.zAxis
	return CFrame.lookAt(centre, centre + facing)
end

-- The plot's floor: the Ground Model holding the dark studded Pad and the 4 Slate Edge parts round it. The pad is
-- odd (PAD x PAD) and centred on the plot, so its studs fall whole at its edges in both studs modes; the edging fills
-- the rest of the plot's square ((PlotSize - PAD) / 2 wide) and stands EDGE_RAISE proud of the pad, so it reads as a
-- stone frame.
local PAD = 107
local EDGE_RAISE = 0.1

local function buildGround(model: Model, cf: CFrame, half: number): BasePart
	local ground = Instance.new("Model")
	ground.Name = "Ground" -- Server/Patients and Server/Nurses stand creatures on it by this name
	local pad = part(ground, "Pad", Vector3.new(PAD, 1, PAD), cf * CFrame.new(0, -0.5, 0), COLORS.Pad)
	Studs.apply(pad)
	local width = half - PAD / 2
	local height = 1 + EDGE_RAISE
	local y = -1 + height / 2
	for _, side in { -1, 1 } do
		part(
			ground,
			"Edge",
			Vector3.new(half * 2, height, width),
			cf * CFrame.new(0, y, side * (half - width / 2)),
			COLORS.Edge,
			Enum.Material.Slate
		)
		part(
			ground,
			"Edge",
			Vector3.new(width, height, PAD),
			cf * CFrame.new(side * (half - width / 2), y, 0),
			COLORS.Edge,
			Enum.Material.Slate
		)
	end
	ground.Parent = model
	return pad
end

-- The clinic sign: the owner's name in floating outlined letters (art-direction §4.4: no board), between two studded
-- posts in the plot's colour beside the gate, high enough to clear the 3-stud fence in front of it (Joshua: "the
-- signboard is behind the fence so i cant see it well"). The Sign part only holds the letters: invisible and
-- walk-through. OwnerName and HeartCount stay direct children of SignGui (Plots and Visits set them), and so do
-- RankBadge, the owner's Doctor rank (Server/Playtime), and BranchBadge, "🏢 n" from R1 (Server/Rebirth): navy pills
-- (a world information plate) hidden until their system fills them.
local SIGN_SIZE = Vector3.new(10, 4, 0.5)
local SIGN_X = -13 -- plot-local: beside the gate (the gate posts stand at x = ±6.2)
local SIGN_IN = 1 -- studs inside the plot's front edge: just behind the front fence (0.4 inside it)
local SIGN_BOTTOM = 4 -- the letters' bottom edge: 1 stud over the fence's 3-stud top

local function signPill(gui: SurfaceGui, name: string, size: UDim2, position: UDim2): TextLabel
	local pill = Instance.new("TextLabel")
	pill.Name = name
	pill.BackgroundColor3 = Palette.Navy
	pill.BackgroundTransparency = 0.15
	pill.Position = position
	pill.Size = size
	pill.Font = Palette.DisplayFont
	pill.TextColor3 = Palette.White
	pill.TextScaled = true
	pill.Text = ""
	pill.Visible = false
	pill.ZIndex = 3
	rounded(pill, UDim.new(0.5, 0))
	Palette.outlineShape(pill, 3)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.Parent = pill
	pill.Parent = gui
	return pill
end

local function buildSign(model: Model, scenery: Model, cf: CFrame, half: number, accent: Color3)
	local w, h = SIGN_SIZE.X, SIGN_SIZE.Y
	local z = -half + SIGN_IN
	local sign = part(model, "Sign", SIGN_SIZE, cf * CFrame.new(SIGN_X, SIGN_BOTTOM + h / 2, z), accent)
	sign.Transparency = 1
	sign.CastShadow = false
	soft(sign)
	local postHeight = SIGN_BOTTOM + h
	for _, side in { -1, 1 } do
		local post = part(
			scenery,
			"SignPost",
			Vector3.new(1, postHeight, 1),
			cf * CFrame.new(SIGN_X + side * (w / 2 - 0.5), postHeight / 2, z + 0.75),
			accent
		)
		Studs.apply(post)
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front -- the side facing the street
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0 -- stays bright and readable at night
	gui.MaxDistance = 150
	local owner = floatText(gui, "✨ Free clinic", {
		Size = UDim2.fromScale(0.96, 0.52),
		Position = UDim2.fromScale(0.02, 0.04),
	})
	owner.Name = "OwnerName"
	local hearts = floatText(gui, "", { Size = UDim2.fromScale(0.34, 0.3), Position = UDim2.fromScale(0.03, 0.63) })
	hearts.Name = "HeartCount"
	signPill(gui, "RankBadge", UDim2.fromScale(0.39, 0.3), UDim2.fromScale(0.58, 0.63))
	signPill(gui, "BranchBadge", UDim2.fromScale(0.16, 0.3), UDim2.fromScale(0.39, 0.63))
	gui.Parent = sign
end

-- Progression v2 (§B4): every sign has a hidden BranchBadge pill (Server/Rebirth shows "🏢 n" from R1), and every
-- plot a MascotSpot marker (Server/Rebirth's mascot, from R5). A kit plot without them gets them.
-- The spot is on the Stand's forecourt, under the canopy beside the front doors, facing the street: it greets
-- whoever walks up the path, and stands off the doors' span (Building.DOORS.Front).
local MASCOT_SPOT =
	Vector3.new((Building.DOORS.Front.X0 :: number) - 2.5, ROOM_FLOOR + 0.5, Building.FRONT - FORECOURT_DEPTH / 2)

local function ensureSignBits(model: Model)
	local sign = model:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChild("SignGui")
	if gui and gui:IsA("SurfaceGui") and not gui:FindFirstChild("BranchBadge") then
		local rank = gui:FindFirstChild("RankBadge")
		if rank and rank:IsA("GuiObject") then
			-- Just left of the brother's RankBadge, the same height.
			local pill =
				signPill(gui, "BranchBadge", UDim2.new(0.16, 0, rank.Size.Y.Scale, rank.Size.Y.Offset), rank.Position)
			pill.AnchorPoint = Vector2.new(1, 0)
		else
			signPill(gui, "BranchBadge", UDim2.fromScale(0.16, 0.3), UDim2.fromScale(0.39, 0.63))
		end
	end
	if not model:FindFirstChild("MascotSpot") then
		marker(model, "MascotSpot", model:GetPivot() * CFrame.new(MASCOT_SPOT))
	end
end

-- The fence (Props.fence: warm-white posts at most every 14 studs) round the plot, open at the gate: two warm-white
-- posts with a lamp on each and a studded arch in the plot's colour across them.
local GATE = 5.6 -- the gate posts stand at x = ±(GATE + 0.6): a 11-stud opening between their faces
local GATE_ARCH = Vector3.new(15, 1.2, 1) -- whole studs across (studded), flush with the plot's front edge

local function buildFenceAndGate(scenery: Model, cf: CFrame, half: number, accent: Color3)
	local e = half - 0.4
	local function at(x: number, z: number): CFrame
		return cf * CFrame.new(x, 0, z)
	end
	Props.fence(scenery, at(-e, e), at(e, e))
	Props.fence(scenery, at(-e, -e), at(-e, e))
	Props.fence(scenery, at(e, -e), at(e, e))
	Props.fence(scenery, at(-e, -e), at(-GATE - 0.6, -e))
	Props.fence(scenery, at(GATE + 0.6, -e), at(e, -e))

	for _, x in { -GATE - 0.6, GATE + 0.6 } do
		part(scenery, "GatePost", Vector3.new(1.4, 6, 1.4), cf * CFrame.new(x, 3, -e), COLORS.Fence)
		local glow =
			soft(ball(scenery, "GateLamp", 1.2, cf * CFrame.new(x, 6 + GATE_ARCH.Y + 0.6, -e), COLORS.LampGlow))
		NightLights.light(glow, 16)
	end
	local archZ = -half + GATE_ARCH.Z / 2 -- inside the plot: it never hangs over the street
	local arch = part(scenery, "GateArch", GATE_ARCH, cf * CFrame.new(0, 6 + GATE_ARCH.Y / 2, archZ), accent)
	Studs.apply(arch)
end

local MAILBOX_X = 9.5 -- beside the gate, on the side away from the sign

local function buildMailbox(scenery: Model, cf: CFrame, half: number, accent: Color3)
	local z = -half + 2
	local model = Instance.new("Model")
	model.Name = "MailboxProp"
	part(model, "Post", Vector3.new(0.4, 3, 0.4), cf * CFrame.new(MAILBOX_X, 1.5, z), COLORS.Trim)
	part(model, "Box", Vector3.new(1.6, 1.2, 2), cf * CFrame.new(MAILBOX_X, 3.5, z), accent)
	soft(part(model, "Flag", Vector3.new(0.1, 0.9, 0.35), cf * CFrame.new(MAILBOX_X + 0.9, 3.9, z - 0.5), COLORS.Flag))
	model.Parent = scenery
end

-- The reception desk: the Counter on Building.RECEPTION.Desk, inside the lobby (solid: an arriving patient stops in
-- front of it at RECEPTION.Stop, a Receptionist stands behind it at RECEPTION.Staff) in the plot's colour, its studded
-- CounterTop (whole studs, a little proud of the body; soft) and our paw-heart mark on its street face, toward the
-- front doors.
local COUNTER_HEIGHT = 3.4

local function buildCounter(model: Model, scenery: Model, cf: CFrame, accent: Color3)
	local desk = Building.RECEPTION.Desk
	local width, depth = desk.X1 - desk.X0, desk.Z1 - desk.Z0
	local x, z = (desk.X0 + desk.X1) / 2, (desk.Z0 + desk.Z1) / 2
	local counter = part(
		model,
		"Counter",
		Vector3.new(width, COUNTER_HEIGHT, depth),
		cf * CFrame.new(x, COUNTER_HEIGHT / 2, z),
		accent
	)
	local top = soft(
		part(
			scenery,
			"CounterTop",
			Vector3.new(math.ceil(width + 0.5), 0.4, math.ceil(depth + 0.4)),
			cf * CFrame.new(x, COUNTER_HEIGHT + 0.2, z),
			COLORS.Trim
		)
	)
	Studs.apply(top)
	local gui = detailGui(counter, "DeskGui", Enum.NormalId.Front, 40, 120)
	local holder = Instance.new("Frame")
	holder.Name = "Mark"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = gui
	pawHeart(holder, UDim2.fromScale(0.82, 0.82), accent)
end

-- The trees and bushes (Props: voxel trees, one-cube bushes), all clear of the Building and its canopy, the path and
-- the gate, the room slots and the ambulance bay's yard (Building.BAY_AMBULANCE.Area; tests/PlotWorld.spec checks
-- them all). The big tree stands in the +x side yard; the others in the corners. The bushes stand by the fence: three
-- along the front either side of the gate, one on the +x side, one at the back.
local TREES = {
	{ X = 44, Z = -10, Scale = 1.35 },
	{ X = -46, Z = -45, Scale = 1 },
	{ X = 45, Z = -44, Scale = 1.1 },
	{ X = -45, Z = 45, Scale = 1.2 },
	{ X = 45, Z = 45, Scale = 1 },
}
local BUSHES = {
	Vector3.new(-26, 0, -52.6),
	Vector3.new(20, 0, -52.6),
	Vector3.new(26, 0, -52.6),
	Vector3.new(52.6, 0, 24),
	Vector3.new(-20, 0, 52.6),
}

-- Where patients come in and leave: just inside the gate, either side of the path's middle.
local GATE_MARK_X = 4
local GATE_MARK_IN = 2.5 -- studs inside the plot's front edge

local function buildPlaceholderPlot(index: number, cf: CFrame): Model
	local half = Config.Town.PlotSize / 2
	local accent = plotAccentFor(index)
	local model = Instance.new("Model")
	model.Name = "Plot_" .. index

	local scenery = Instance.new("Model")
	scenery.Name = "Scenery"
	scenery.Parent = model

	local pad = buildGround(model, cf, half)

	-- The plank path from the gate to the Stand's forecourt (whose tiles run on to the front doors). Nothing under the
	-- building.
	local front = pad.Size.Z / 2
	local doors = Building.DOORS.Front
	local doorX = ((doors.X0 :: number) + (doors.X1 :: number)) / 2
	local forecourtFront = Building.FRONT - FORECOURT_DEPTH
	local pathLength = front + forecourtFront
	local path = part(
		scenery,
		"Path",
		Vector3.new(GATE * 2 - 0.2, 0.2, pathLength),
		cf * CFrame.new(doorX, 0.05, -(front - pathLength / 2)),
		COLORS.Path,
		Enum.Material.WoodPlanks
	)
	path.CastShadow = false

	buildCounter(model, scenery, cf, accent)

	-- Markers. PatientSpawn faces into the plot; PatientExit faces the street.
	local turn = CFrame.Angles(0, math.pi, 0)
	local markZ = -half + GATE_MARK_IN
	marker(model, "PatientSpawn", cf * CFrame.new(doorX - GATE_MARK_X, 0.5, markZ) * turn)
	marker(model, "PatientExit", cf * CFrame.new(doorX + GATE_MARK_X, 0.5, markZ))
	marker(model, "MascotSpot", cf * CFrame.new(MASCOT_SPOT))

	local slots = Instance.new("Folder")
	slots.Name = "Slots"
	for slotId, slot in PlotBuilder.SLOTS do
		marker(slots, "RoomSlot_" .. slotId, cf * CFrame.new(slot.Offset), slot.Size)
	end
	slots.Parent = model

	for _, name in { "Rooms", "Patients", "Decor" } do
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = model
	end

	buildSign(model, scenery, cf, half, accent)
	buildFenceAndGate(scenery, cf, half, accent)
	buildMailbox(scenery, cf, half, accent)

	for _, tree in TREES do
		Props.tree(scenery, cf * CFrame.new(tree.X, 0, tree.Z), tree.Scale)
	end
	for _, at in BUSHES do
		Props.bush(scenery, cf * CFrame.new(at))
	end
	return model
end

-- The brother's plot template, if valid. Its pivot must be the ground-top centre, facing the street.
local function kitPlot(index: number, cf: CFrame): Model?
	local kit = ServerStorage:FindFirstChild("ClinicKit")
	local template = kit and kit:FindFirstChild("Plot")
	if not (template and template:IsA("Model")) then
		return nil
	end
	local problems = {}
	for _, name in { "Ground", "Sign", "Counter", "PatientSpawn", "PatientExit" } do
		local found = template:FindFirstChild(name)
		if not (found and found:IsA("BasePart")) then
			table.insert(problems, "a Part named " .. name)
		end
	end
	local sign = template:FindFirstChild("Sign")
	local signGui = sign and sign:FindFirstChild("SignGui")
	if not (signGui and signGui:FindFirstChild("OwnerName") and signGui:FindFirstChild("HeartCount")) then
		table.insert(problems, "Sign.SignGui with TextLabels OwnerName and HeartCount")
	end
	local slots = template:FindFirstChild("Slots")
	for _, roomId in Rooms.Order do
		local slotName = "RoomSlot_" .. Rooms[roomId].Slot
		if not (slots and slots:FindFirstChild(slotName)) then
			table.insert(problems, "Slots." .. slotName)
		end
	end
	if #problems > 0 then
		warn(
			"[PlotBuilder] ClinicKit.Plot is missing: "
				.. table.concat(problems, ", ")
				.. ". Using the placeholder plot."
		)
		return nil
	end

	local model = template:Clone()
	model.Name = "Plot_" .. index
	scrubScripts(model, "ClinicKit.Plot (Plot_" .. index .. ")")
	anchorAll(model)
	for _, name in { "Rooms", "Patients", "Decor" } do
		if not model:FindFirstChild(name) then
			local folder = Instance.new("Folder")
			folder.Name = name
			folder.Parent = model
		end
	end
	model:PivotTo(cf)
	return model
end

------------------------------------------------------------------------------------------------------------------
-- The hospital building: Server/HospitalBuilder builds it
------------------------------------------------------------------------------------------------------------------

function PlotBuilder.buildBuilding(plotModel: Model, level: number, grewFrom: number?, theme: string?): Model
	return HospitalBuilder.build(plotModel, level, grewFrom, theme)
end

------------------------------------------------------------------------------------------------------------------
-- The town: Server/TownBuilder builds the scenery and the spawn; the plots are built here
------------------------------------------------------------------------------------------------------------------

function PlotBuilder.buildTown(): { Model }
	local count = math.clamp(Config.Town.Plots, 1, MAX_PLOTS)
	for _, name in { "Clinics", "ClinicTown" } do
		local old = Workspace:FindFirstChild(name)
		if old then
			warn("[PlotBuilder] Replacing an existing Workspace." .. name)
			old:Destroy()
		end
	end

	local town = TownBuilder.build(count)
	town.Parent = Workspace
	TownBuilder.spawn()

	local clinics = Instance.new("Folder")
	clinics.Name = "Clinics"
	local models = {}
	for index = 1, count do
		local cf = plotCFrame(index, count)
		local model = kitPlot(index, cf) or buildPlaceholderPlot(index, cf)
		model.WorldPivot = cf
		ensureSignBits(model) -- a kit plot's sign gets its BranchBadge, and the plot its MascotSpot
		model:SetAttribute("PlotIndex", index)
		model:SetAttribute("Accent", plotAccentFor(index)) -- HospitalBuilder reads it
		model:SetAttribute("OwnerUserId", 0)
		model:SetAttribute("OpenHelpers", false)
		model:SetAttribute("Hearts", 0)
		model.Parent = clinics
		PlotBuilder.placeRoom(model, "Stand")
		PlotBuilder.buildBuilding(model, 1) -- Lv 1's Building; Server/Levels grows it for the owner
		models[index] = model
	end
	clinics.Parent = Workspace

	NightLights.wire()
	return models
end

function PlotBuilder.clearPlot(plotModel: Model)
	for _, name in { "Patients", "Decor" } do
		local folder = plotModel:FindFirstChild(name)
		if folder then
			folder:ClearAllChildren()
		end
	end
	local roomsFolder = plotModel:FindFirstChild("Rooms")
	if roomsFolder then
		for _, room in roomsFolder:GetChildren() do
			if room.Name ~= "Room_Stand" then
				room:Destroy()
			end
		end
	end
	local slots = plotModel:FindFirstChild("Slots")
	if slots then
		for _, slot in slots:GetChildren() do
			local preview = slot:FindFirstChild("Preview")
			if preview then
				preview:Destroy()
			end
		end
	end
	PlotBuilder.buildBuilding(plotModel, 1) -- a free plot is back to Lv 1's Building (Level attribute 1)
end

return PlotBuilder
