--!strict
-- Builds the clinic plots and their rooms, and puts the town together (build plan §B1). Server only.
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
--   PlotBuilder.queueSpot(queueStart, spawn?, index): CFrame   place `index` in line (Patients stands patients there)
--   PlotBuilder.SLOTS                                      the room slots on a plot
--
-- THE SPLIT (look build plan §A/§B4; the look overhaul's Foundation). This file used to hold everything. Now:
--   Server/TownBuilder            the town round the plots, and TownSpawn                        (T2)
--   Server/HospitalBuilder        the Building and its layout numbers (Pure)                     (T3)
--   Server/World/Props            the shared scenery: trees, bushes, lamps, benches, fences      (T2)
--   Server/World/NightLights      the parts that glow after dark                                 (T1)
--   Server/World/Parts            the generic part and label helpers, and the shared look pieces (frozen)
--   Server/World/Studs            the studs look                                                 (frozen)
-- PlotBuilder keeps the plots, the rooms, the queue lane and every public function above, and requires the others
-- (never the other way round: TownBuilder and HospitalBuilder require World/* only). These stay as RE-EXPORTS, so
-- no caller changed:
--   PlotBuilder.NIGHT_LIGHT_TAG   = World/NightLights.TAG     tag a lamp Part: Neon + PointLight on only at night
--   PlotBuilder.STATION_TAG / LIFT_TAG / PROMPT_TAGS   = HospitalBuilder's (Progression v2's CollectionService tags)
--   PlotBuilder.Pure              = HospitalBuilder.Pure      the building's layout in numbers
-- Every plot Model carries the attribute `Accent` (a Color3: its Palette.PlotColors entry), which HospitalBuilder
-- reads, beside PlotIndex, OwnerUserId, OpenHelpers and Hearts.
--
-- THE LOOK (memory-20261117-001; look build plan §B6 "T4's side"; docs/research/2026-11-16-hospital-building.md
-- §3.8-3.9, §5.4; art-direction §2.4, §4.1). Studs, dark anchors, one colour per surface, no lerp toward white:
--   Ground       a Model: the plot's dark studded `Pad` (World.Pad, 67 x 67: odd, so its studs fall whole at its
--                edges) framed by 4 Slate `Edge` parts (World.Edge) out to the plot's 70 x 70. Patients and Nurses
--                stand creatures on it by the name Ground (their rays include its descendants)
--   Scenery      the plank path from the gate to the Counter, 2 slate stepping stones to the main entrance, the fence
--                (Props.fence: posts every 14 studs) and the gate (warm-white posts, a studded arch in the plot's
--                colour, two lamps), the mailbox, 5 voxel trees (Props.tree; the one by the Stand moved to (18.5,
--                -10), clear of the podium) and 8 one-cube bushes (Props.bush). No blossom tree on a plot: Pink is one
--                plot's colour, and the town keeps blossoms to 1 tree in 6
--   Counter      the reception desk: a SmoothPlastic body in the plot's colour, its CounterTop studded in warm
--                white, and OUR paw-heart mark (Parts.pawHeart) on its street face: one SurfaceGui, no cross
--   Sign         the owner's name floats (Parts.floatText: outlined letters, NO board; the Sign part is invisible)
--                between two studded posts in the plot's colour, above the fence. SignGui keeps OwnerName and
--                HeartCount (Plots and Visits write them), RankBadge (Playtime) and BranchBadge (Rebirth): navy pills,
--                hidden until their system fills them
--   MascotSpot   at Shared/Logic/Building's (-7, -14.8), beside the Counter's -x end (Server/Rebirth's mascot)
--   QueueLane    6 tiles in the mid-tone pavement (World.Pavement / PavementAlt), an edge in the plot's colour on
--                each side, and a disc in the plot's colour at each place in line with its number floating on it
--   Rooms        no awnings, walls in pale tints or plaques. The Stand has NO shell (the hospital podium is its
--                building, HospitalBuilder's): a plank floor, the stations, Bed_1 and the decor slots at
--                Shared/Logic/Building's spots (decor slot 2 sits on the pad, on the porch). The Bath Room (Cyan),
--                Cozy Ward (Purple) and Winter Wing (Blue) are single-storey ANNEXES: a plank floor, three studded
--                walls in the room colour (inside: the colour as a dado band, warm upper walls above a wood rail,
--                drawn on), a dark flat roof with a warm-white trim edge and the room's name floating on it, and the
--                same open front as before, so stations and patients work unchanged. The Winter Wing keeps one snow
--                slab. The Garden is a studded lawn with studded hedges and an arbor. Beds are 3 parts (Frame,
--                Headboard studded, the mattress Bed_<n>); stations are a body, a studded Top and a few blocky props
-- No Texture or Decal anywhere. Studded parts go through World/Studs with whole-stud X and Z.
--
-- Parts budget (docs/plan/2026-11-16-perf-budget.md; Config.Look): a Lv 5 plot with every room is at most 400 parts
-- without creatures and decor: the plot's own share (everything here but the Building and the rooms) at most
-- Config.Look.PlotParts (115), every room together at most Config.Look.RoomParts (90). tests/PlotWorld.spec holds
-- both; tests/PartBudget.spec the total.
--
-- Every plot (kit or placeholder) also gets a QueueLane Model: pavement under the patients' line, from the Counter
-- out toward the gate, so it reads as "the line" (Joshua: "make a pavement outside of the place where they line
-- up"). Walk-through and ray-ignored. A kit Plot with its own QueueLane child keeps that one.
--
-- Coordinates. Each plot has a CFrame at the centre of its ground's TOP face, LookVector pointing at the street
-- (that CFrame is also the plot Model's WorldPivot). In plot-local space +X is right as you face the street, -Z is
-- the street side (front edge z = -35) and +Z the back. Markers are 2x1x2 invisible Parts resting on the ground.
-- Rooms face the street too. Inside a room Model, y = 0.3 is the top of the Floor (and y = -0.3 the pad under it).
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
local ball, marker, paint, rounded, band = Parts.ball, Parts.marker, Parts.paint, Parts.rounded, Parts.band
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

-- Room slots on a 70 x 70 plot, plot-local. Offset is the slot (= Floor) centre; Size is the floor footprint.
PlotBuilder.SLOTS = table.freeze({
	Stand = table.freeze({ Offset = Vector3.new(0, 0.3, -6), Size = Vector3.new(22, 0.6, 14) }),
	A = table.freeze({ Offset = Vector3.new(-23, 0.3, 6), Size = Vector3.new(18, 0.6, 16) }),
	C = table.freeze({ Offset = Vector3.new(23, 0.3, 6), Size = Vector3.new(18, 0.6, 16) }),
	B = table.freeze({ Offset = Vector3.new(-13, 0.3, 25), Size = Vector3.new(22, 0.6, 14) }),
	D = table.freeze({ Offset = Vector3.new(13, 0.3, 25), Size = Vector3.new(22, 0.6, 14) }),
})

local STREET_HALF_WIDTH = 18
local PLOT_GAP = 8
local BASE_TOP = 0.3 -- the town lawn's top, just above a default baseplate at y = 0 (TownBuilder's too)
local PLOT_RAISE = 0.6 -- plots sit a small step above the street
local FLOOR_TOP = 0.3 -- room-local height of the floor's top face
local MAX_PLOTS = 6

local WORLD = Palette.World
local ACCENT = Palette.Accent

-- The look's colours, by job (Palette.World / Palette.Accent; art-direction §4.1). No lerp toward white anywhere.
local COLORS = {
	Pad = WORLD.Pad, -- the plot's floor: a dark anchor, studded
	Edge = WORLD.Edge, -- the stone edging round it (Slate)
	Path = WORLD.Plank, -- WoodPlanks
	Stone = WORLD.Edge, -- the stepping stones (Slate)
	Fence = WORLD.Fence, -- the gate posts (the fence itself is Props')
	Trim = WORLD.Trim, -- warm white: the CounterTop, station tops, mattresses, trim edges, decor spots
	Roof = WORLD.Roof, -- the annexes' flat roofs: a dark anchor
	Floor = WORLD.FloorA, -- room floors: WoodPlanks
	WallUpper = WORLD.WallUpper, -- the warm upper wall inside an annex (drawn above the dado)
	Rail = WORLD.Beam, -- the wood rail between the dado and the upper wall (drawn)
	Wood = WORLD.Beam, -- the arbor's posts
	Lawn = WORLD.GrassA, -- the Garden's floor, studded
	Hedge = WORLD.LeavesB, -- the Garden's hedges, studded
	Vine = WORLD.LeavesA, -- the arbor's beam, studded
	Snow = WORLD.Trim, -- the Winter Wing's snow slab
	LampGlow = WORLD.Lamp,
	Water = WORLD.Water,
	Flag = ACCENT.Red, -- the mailbox flag (Red: props only)
	ForSale = ACCENT.Yellow,
	Pavement = WORLD.Pavement, -- the queue lane's tiles, in mid-tones
	PavementAlt = WORLD.PavementAlt,
	Roll = WORLD.CheckerCream, -- the Plaster Table's bandage roll
}

-- Plot_n's own accent (Palette.PlotColors).
local function plotAccentFor(index: number): Color3
	local colors = Palette.PlotColors
	return colors[(index - 1) % #colors + 1]
end

-- A station's colour in the WORLD: Data/Stations gives the UI's Candy colour (kids match it to the ailment); a world
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

-- Each room's look. Main is the room colour (art-direction §4.1: the Stand = its plot's colour, Bath = Cyan, Ward =
-- Purple, Winter Wing = Blue, Garden = leaves): annex walls, bed frames and headboards.
type RoomKind = "Open" | "Annex" | "Garden"
type RoomStyle = { Main: Color3, Kind: RoomKind, Snow: boolean }

local STYLES: { [string]: RoomStyle } = {
	Stand = { Main = ACCENT.Pink, Kind = "Open", Snow = false }, -- the plot's colour replaces Main (styleFor)
	BathRoom = { Main = ACCENT.Cyan, Kind = "Annex", Snow = false },
	Ward = { Main = ACCENT.Purple, Kind = "Annex", Snow = false },
	WinterWing = { Main = ACCENT.Blue, Kind = "Annex", Snow = true },
	Garden = { Main = WORLD.LeavesA, Kind = "Garden", Snow = false },
}

local function styleFor(roomId: string, accent: Color3?): RoomStyle
	if roomId == "Stand" then
		return { Main = accent or STYLES.Stand.Main, Kind = "Open", Snow = false }
	end
	return STYLES[roomId] or { Main = ACCENT.Orange, Kind = "Annex", Snow = false }
end

-- Where things go inside each placeholder room (room-local x, z; y is ignored). Counts match Data/Rooms.
-- The Stand's spots are Shared/Logic/Building's (plot-local; the hospital is built round them), moved into the
-- Stand slot's own space: Remedy and Plaster moved +1.2 in x (clear of the lift shaft), decor slot 2 on the porch.
type Layout = { Stations: { [string]: Vector3 }, Beds: { Vector3 }, Decor: { Vector3 } }

local STAND_AT = PlotBuilder.SLOTS.Stand.Offset
local function standLocal(spot: { X: number, Z: number }): Vector3
	return Vector3.new(spot.X - STAND_AT.X, 0, spot.Z - STAND_AT.Z)
end

local LAYOUTS: { [string]: Layout } = {
	Stand = {
		Stations = { Remedy = standLocal(Building.STAND.Remedy), Plaster = standLocal(Building.STAND.Plaster) },
		Beds = { standLocal(Building.STAND.Bed) },
		Decor = { standLocal(Building.STAND.Decor[1]), standLocal(Building.STAND.Decor[2]) },
	},
	BathRoom = {
		Stations = { Bath = Vector3.new(0, 0, 4.6) },
		Beds = {},
		Decor = { Vector3.new(-5.5, 0, -4.6) },
	},
	Ward = {
		Stations = {},
		Beds = { Vector3.new(-6, 0, 1.3), Vector3.new(6, 0, 1.3) },
		Decor = { Vector3.new(0, 0, 3.6), Vector3.new(8.6, 0, -4.5) },
	},
	WinterWing = {
		Stations = { Cocoa = Vector3.new(-3, 0, 5) },
		Beds = { Vector3.new(5, 0, 1.6) },
		Decor = { Vector3.new(-5.5, 0, -4.8), Vector3.new(4.8, 0, -5.2) },
	},
	Garden = {
		Stations = {},
		Beds = {},
		Decor = { Vector3.new(-6.5, 0, 2.4), Vector3.new(6.5, 0, 2.4), Vector3.new(0, 0, -3.2) },
	},
}

------------------------------------------------------------------------------------------------------------------
-- Rooms
------------------------------------------------------------------------------------------------------------------

local function slotSize(roomId: string): Vector3
	local room = Rooms[roomId]
	local slot = room and PlotBuilder.SLOTS[room.Slot]
	return if slot then slot.Size else Vector3.new(18, 0.6, 14)
end

-- Fallback positions if Data/Rooms counts ever outgrow a layout: stations along the back, beds along the
-- sides, decor along the front.
local function genericLayout(roomId: string, w: number, d: number): Layout
	local room = Rooms[roomId]
	local layout: Layout = { Stations = {}, Beds = {}, Decor = {} }
	local stationCount = #room.Stations
	for i, stationId in room.Stations do
		layout.Stations[stationId] = Vector3.new((i - (stationCount + 1) / 2) * 6, 0, d / 2 - 2)
	end
	for i = 1, room.Beds do
		local side = if i % 2 == 1 then 1 else -1
		layout.Beds[i] = Vector3.new(side * (w / 2 - 2.6), 0, d / 2 - 6 - math.floor((i - 1) / 2) * 7.5)
	end
	for i = 1, room.DecorSlots do
		layout.Decor[i] = Vector3.new((i - (room.DecorSlots + 1) / 2) * (w / (room.DecorSlots + 1)), 0, -d / 2 + 2.5)
	end
	return layout
end

local function layoutFor(roomId: string, w: number, d: number): Layout
	local room = Rooms[roomId]
	local layout = LAYOUTS[roomId]
	if layout then
		local stationsOk = true
		for _, stationId in room.Stations do
			if not layout.Stations[stationId] then
				stationsOk = false
			end
		end
		if stationsOk and #layout.Beds == room.Beds and #layout.Decor == room.DecorSlots then
			return layout
		end
		warn("[PlotBuilder] Layout for", roomId, "doesn't match Data/Rooms; using a generic one")
	end
	return genericLayout(roomId, w, d)
end

-- A table station: its body in the station's colour, a studded warm-white Top in whole studs (4 x 3: at Remedy's x
-- it ends 0.2 short of the lift shaft's face, Shared/Logic/Building.SHAFT), and a few blocky props on it.
local STATION_BODY = Vector3.new(3.8, 3, 2.6)
local STATION_TOP = Vector3.new(4, 0.3, 3)

local function buildStation(model: Model, stationId: string, at: Vector3)
	local station = Stations[stationId]
	local uiColor = if station then station.Color else Palette.Candy.Orange
	local color = worldColor(uiColor)
	local icon = if station then station.Icon else "❔"
	local base = CFrame.new(at.X, FLOOR_TOP, at.Z)
	local stationPart: BasePart

	if stationId == "Bath" then
		-- A warm-white tub with a band in the station's colour round it and the water on top.
		stationPart = part(model, "Station_Bath", Vector3.new(5.6, 2.2, 3.6), base * CFrame.new(0, 1.1, 0), COLORS.Trim)
		soft(part(model, "TubStripe", Vector3.new(5.68, 0.5, 3.68), base * CFrame.new(0, 1.4, 0), color))
		paint(part(model, "Water", Vector3.new(5, 0.15, 3), base * CFrame.new(0, 2.15, 0), COLORS.Water))
	else
		local body = STATION_BODY
		stationPart = part(model, "Station_" .. stationId, body, base * CFrame.new(0, body.Y / 2, 0), color) :: BasePart
		local top =
			soft(part(model, "Top", STATION_TOP, base * CFrame.new(0, body.Y + STATION_TOP.Y / 2, 0), COLORS.Trim))
		Studs.apply(top)
		local on = base * CFrame.new(0, body.Y + STATION_TOP.Y, 0) -- the Top's upper face
		if stationId == "Remedy" then
			-- Potion bottles in colours no station wears, so they never read as a colour clue.
			for i, bottleColor in { ACCENT.Lime, ACCENT.Yellow, ACCENT.Lime } do
				local x = (i - 2) * 1.2
				soft(part(model, "Bottle", Vector3.new(0.6, 1, 0.6), on * CFrame.new(x, 0.5, 0.2), bottleColor))
			end
		elseif stationId == "Plaster" then
			soft(part(model, "Box", Vector3.new(1.8, 0.8, 1.2), on * CFrame.new(-0.6, 0.4, 0.2), COLORS.Trim))
			soft(cylinder(model, "Roll", 0.5, 0.9, on * CFrame.new(1.2, 0.25, 0.1), COLORS.Roll))
		elseif stationId == "Cocoa" then
			soft(part(model, "Mug", Vector3.new(0.8, 0.9, 0.8), on * CFrame.new(-0.9, 0.45, 0.1), COLORS.Trim))
			soft(part(model, "Pot", Vector3.new(1.3, 1.1, 1.3), on * CFrame.new(0.9, 0.55, 0.2), ACCENT.Red))
		end
	end

	-- The floating icon badge is a billboard (unlit, like the UI), so its ring keeps the UI's colour.
	iconBadge(stationPart, "IconGui", icon, uiColor, 2.6, stationPart.Size.Y / 2 + 2.1)
end

-- A bed: 3 parts (the look build plan's bed contract). Frame in the room's colour, a studded Headboard in it (whole
-- studs), and Bed_<n>, the warm-white mattress patients lie on (its top face; the pillow end is +Z, the room's
-- back). Bed_<n>'s size and place are unchanged, so a patient lies exactly as before.
local function buildBed(model: Model, index: number, at: Vector3, color: Color3)
	local base = CFrame.new(at.X, FLOOR_TOP, at.Z)
	part(model, "Frame", Vector3.new(4.4, 0.8, 7), base * CFrame.new(0, 0.4, 0), color)
	part(model, "Bed_" .. index, Vector3.new(4, 1, 6.6), base * CFrame.new(0, 1.3, 0), COLORS.Trim)
	Studs.apply(part(model, "Headboard", Vector3.new(4, 2.6, 1), base * CFrame.new(0, 1.3, 4), color))
end

-- A decor slot: the invisible 4 x 4 marker (Plots puts decor on its bottom face) and a warm-white spot that shows
-- where decor goes. `floorTop` is the height under it in room space: a slot off the room's floor (the Stand's decor
-- slot 2, on the porch) stands on the pad instead.
local function buildDecorSlot(model: Model, index: number, at: Vector3, floorTop: number)
	marker(model, "DecorSlot_" .. index, CFrame.new(at.X, floorTop + 0.5, at.Z), Vector3.new(4, 1, 4))
	paint(cylinder(model, "DecorSpot", 0.06, 3.4, CFrame.new(at.X, floorTop + 0.03, at.Z), COLORS.Trim))
end

-- The inside of an annex wall: the room's colour stays below as the dado band, the warm upper wall goes above it,
-- with a wood rail between (drawn on that face: no parts).
local DADO = 3 -- studs of room colour above the floor, inside
local function lineWall(wall: BasePart, face: Enum.NormalId)
	local h = wall.Size.Y
	local upper = (h - DADO) / h
	local gui = detailGui(wall, "LiningGui", face, 8)
	band(gui, "UpperWall", UDim2.fromScale(1, upper), UDim2.fromScale(0.5, upper / 2), COLORS.WallUpper)
	band(gui, "Rail", UDim2.fromScale(1, 0.3 / h), UDim2.fromScale(0.5, upper), COLORS.Rail)
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

-- An annex (hospital doc §3.8): three studded walls in the room's colour (the back one full width; the side ones
-- on the back half only, as before, so the patients' ways in at the front stay open), a dark flat roof over the
-- back half with a warm-white trim along its front edge and the name floating on it. Walk-through roof (the camera
-- isn't pushed in under it, like the old awning); solid walls.
local WALL_HEIGHT = 8
local ROOF_THICK = 1.5

local function buildAnnex(model: Model, room: RoomInfo, w: number, d: number, style: RoomStyle)
	local back = d / 2
	local wallY = FLOOR_TOP + WALL_HEIGHT / 2
	local backWall =
		part(model, "BackWall", Vector3.new(w, WALL_HEIGHT, 1), CFrame.new(0, wallY, back - 0.5), style.Main)
	Studs.apply(backWall)
	lineWall(backWall, Enum.NormalId.Front)
	local sideDepth = back - 1 -- from the room's middle (z = 0) to the back wall
	for _, side in { -1, 1 } do
		local wall = part(
			model,
			"SideWall",
			Vector3.new(1, WALL_HEIGHT, sideDepth),
			CFrame.new(side * (w / 2 - 0.5), wallY, sideDepth / 2),
			style.Main
		)
		Studs.apply(wall)
		lineWall(wall, if side < 0 then Enum.NormalId.Right else Enum.NormalId.Left) -- the face toward the room
	end

	local roofY = FLOOR_TOP + WALL_HEIGHT + ROOF_THICK / 2
	local roof =
		soft(part(model, "Roof", Vector3.new(w + 1, ROOF_THICK, back + 1), CFrame.new(0, roofY, back / 2), COLORS.Roof))
	nameOn(roof, room)
	-- The warm-white trim under the roof's front edge, from side wall to side wall.
	soft(
		part(
			model,
			"Trim",
			Vector3.new(w + 1.2, 0.5, 0.5),
			CFrame.new(0, FLOOR_TOP + WALL_HEIGHT - 0.25, -0.25),
			COLORS.Trim
		)
	)
	if style.Snow then
		paint(
			part(
				model,
				"Snow",
				Vector3.new(w - 1, 0.4, back - 0.5),
				CFrame.new(0, roofY + ROOF_THICK / 2 + 0.2, back / 2 + 0.25),
				COLORS.Snow
			)
		)
	end
end

-- The Garden: a studded lawn (its Floor), studded hedges on three sides (the side ones on the back half, like the
-- annexes' walls) and an arbor at the back: two wood posts and a studded beam of leaves with the name on it.
local function buildGarden(model: Model, room: RoomInfo, w: number, d: number)
	local back = d / 2
	Studs.apply(
		part(model, "BackHedge", Vector3.new(w, 3, 1), CFrame.new(0, FLOOR_TOP + 1.5, back - 0.5), COLORS.Hedge)
	)
	local sideDepth = back - 1
	for _, side in { -1, 1 } do
		Studs.apply(
			part(
				model,
				"SideHedge",
				Vector3.new(1, 2, sideDepth),
				CFrame.new(side * (w / 2 - 0.5), FLOOR_TOP + 1, sideDepth / 2),
				COLORS.Hedge
			)
		)
	end
	local arborZ = back - 1.5
	for _, side in { -1, 1 } do
		part(model, "ArborPost", Vector3.new(0.8, 7, 0.8), CFrame.new(side * 4.5, FLOOR_TOP + 3.5, arborZ), COLORS.Wood)
	end
	-- Overhead and walk-through: no ray (Patients', Nurses') ever lands a creature on it.
	local beam =
		soft(part(model, "ArborBeam", Vector3.new(11, 1.5, 2), CFrame.new(0, FLOOR_TOP + 7.75, arborZ), COLORS.Vine))
	Studs.apply(beam)
	nameOn(beam, room)
end

local function placeholderRoom(roomId: string, accent: Color3?): Model
	local room = Rooms[roomId]
	local style = styleFor(roomId, accent)
	local size = slotSize(roomId)
	local w, d = size.X, size.Z

	local model = Instance.new("Model")
	model.Name = "Room_" .. roomId
	local floor: BasePart
	if style.Kind == "Garden" then
		floor = part(model, "Floor", size, CFrame.identity, COLORS.Lawn)
		Studs.apply(floor)
	else
		floor = part(model, "Floor", size, CFrame.identity, COLORS.Floor, Enum.Material.WoodPlanks)
	end
	model.PrimaryPart = floor

	if style.Kind == "Annex" then
		buildAnnex(model, room, w, d, style)
	elseif style.Kind == "Garden" then
		buildGarden(model, room, w, d)
	end

	local layout = layoutFor(roomId, w, d)
	for _, stationId in room.Stations do
		buildStation(model, stationId, layout.Stations[stationId])
	end
	for index, at in layout.Beds do
		buildBed(model, index, at, style.Main)
	end
	for index, at in layout.Decor do
		local onFloor = math.abs(at.X) <= w / 2 and math.abs(at.Z) <= d / 2
		buildDecorSlot(model, index, at, if onFloor then FLOOR_TOP else -FLOOR_TOP)
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
	for _, stationId in room.Stations do
		local station = model:FindFirstChild("Station_" .. stationId, true)
		if not station then
			warn("[PlotBuilder] ClinicKit." .. roomId .. " is missing Station_" .. stationId)
		else
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
	for i = 1, room.Beds do
		if not model:FindFirstChild("Bed_" .. i, true) then
			warn("[PlotBuilder] ClinicKit." .. roomId .. " is missing Bed_" .. i)
		end
	end
	for i = 1, room.DecorSlots do
		if not model:FindFirstChild("DecorSlot_" .. i, true) then
			warn("[PlotBuilder] ClinicKit." .. roomId .. " is missing DecorSlot_" .. i)
		end
	end
	return model
end

-- `accent` is the plot's colour, for the Stand's bed (a kit room ignores it).
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
-- odd (67 x 67) and centred on the plot, so its studs fall whole at its edges in both studs modes; the edging fills
-- the rest of the plot's square and stands EDGE_RAISE proud of the pad, so it reads as a stone frame.
local PAD = 67
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
local SIGN_Z = -34 -- just behind the front fence (z = -34.6)
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

local function buildSign(model: Model, scenery: Model, cf: CFrame, accent: Color3)
	local w, h = SIGN_SIZE.X, SIGN_SIZE.Y
	local sign = part(model, "Sign", SIGN_SIZE, cf * CFrame.new(SIGN_X, SIGN_BOTTOM + h / 2, SIGN_Z), accent)
	sign.Transparency = 1
	sign.CastShadow = false
	soft(sign)
	local postHeight = SIGN_BOTTOM + h
	for _, side in { -1, 1 } do
		local post = part(
			scenery,
			"SignPost",
			Vector3.new(1, postHeight, 1),
			cf * CFrame.new(SIGN_X + side * (w / 2 - 0.5), postHeight / 2, SIGN_Z + 0.75),
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
-- plot a MascotSpot marker beside the Counter (Server/Rebirth's mascot, from R5). A kit plot without them gets them.
-- The spot is Shared/Logic/Building's: beside the Counter's -x end, clear of the line and the hospital's façade.
local MASCOT_SPOT = Vector3.new(Building.STAND.Mascot.X, 0.5, Building.STAND.Mascot.Z)

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

local function buildMailbox(scenery: Model, cf: CFrame, accent: Color3)
	local model = Instance.new("Model")
	model.Name = "MailboxProp"
	part(model, "Post", Vector3.new(0.4, 3, 0.4), cf * CFrame.new(9.5, 1.5, -33), COLORS.Trim)
	part(model, "Box", Vector3.new(1.6, 1.2, 2), cf * CFrame.new(9.5, 3.5, -33), accent)
	soft(part(model, "Flag", Vector3.new(0.1, 0.9, 0.35), cf * CFrame.new(10.4, 3.9, -33.5), COLORS.Flag))
	model.Parent = scenery
end

-- The reception desk: the Counter (solid: patients queue in front of it, you treat from behind it) in the plot's
-- colour, its studded CounterTop (13 x 3: whole studs) and our paw-heart mark on the street face.
local function buildCounter(model: Model, scenery: Model, cf: CFrame, accent: Color3)
	local counter = part(model, "Counter", Vector3.new(12, 3.4, 2.4), cf * CFrame.new(0, 1.7, -14.5), accent)
	local top = soft(part(scenery, "CounterTop", Vector3.new(13, 0.4, 3), cf * CFrame.new(0, 3.6, -14.5), COLORS.Trim))
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

-- The trees and bushes (Props: voxel trees, one-cube bushes). The tree beside the Stand moved to (18.5, -10), so
-- its crown stays clear of the podium (hospital doc §3.9) and of the +x walkway.
local TREES = {
	{ X = 18.5, Z = -10, Scale = 1.35 },
	{ X = -28, Z = -27, Scale = 1 },
	{ X = 28.5, Z = -26, Scale = 1.1 },
	{ X = -29, Z = 29, Scale = 1.2 },
	{ X = 29.5, Z = 29.5, Scale = 1 },
}
local BUSHES = {
	Vector3.new(-24, 0, -32.6),
	Vector3.new(-31.5, 0, -31.8),
	Vector3.new(16, 0, -32.6),
	Vector3.new(21.5, 0, -32.6),
	Vector3.new(32, 0, -10),
	Vector3.new(-32, 0, -10),
	Vector3.new(0, 0, 32.6),
	Vector3.new(-32, 0, 20),
}

local function buildPlaceholderPlot(index: number, cf: CFrame): Model
	local half = Config.Town.PlotSize / 2
	local accent = plotAccentFor(index)
	local model = Instance.new("Model")
	model.Name = "Plot_" .. index

	local scenery = Instance.new("Model")
	scenery.Name = "Scenery"
	scenery.Parent = model

	local pad = buildGround(model, cf, half)

	-- The plank path from the gate to the Counter (under the queue lane), and 2 slate stepping stones from it to the
	-- hospital's main entrance (ground-bed patients walk in that way). Nothing under the building.
	local front = pad.Size.Z / 2
	local pathLength = front - 15.6
	local path = part(
		scenery,
		"Path",
		Vector3.new(11, 0.2, pathLength),
		cf * CFrame.new(0, 0.05, -(front + 15.6) / 2),
		COLORS.Path,
		Enum.Material.WoodPlanks
	)
	path.CastShadow = false
	local doorX = (Building.DOORS.Main.X0 + Building.DOORS.Main.X1) / 2
	for _, z in { -16.2, -19.6 } do
		paint(cylinder(scenery, "Stone", 0.2, 2.6, cf * CFrame.new(doorX, 0.05, z), COLORS.Stone, Enum.Material.Slate))
	end

	buildCounter(model, scenery, cf, accent)

	-- Markers. QueueStart and PatientSpawn face the counter; PatientExit faces the street.
	local turn = CFrame.Angles(0, math.pi, 0)
	marker(model, "QueueStart", cf * CFrame.new(0, 0.5, -18) * turn)
	marker(model, "PatientSpawn", cf * CFrame.new(-4, 0.5, -32.5) * turn)
	marker(model, "PatientExit", cf * CFrame.new(4, 0.5, -32.5))
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

	buildSign(model, scenery, cf, accent)
	buildFenceAndGate(scenery, cf, half, accent)
	buildMailbox(scenery, cf, accent)

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
	for _, name in { "Ground", "Sign", "Counter", "QueueStart", "PatientSpawn", "PatientExit" } do
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
-- The line: where patients stand, and the queue lane paved under them
------------------------------------------------------------------------------------------------------------------

-- Markers are 2x1x2 and rest on the ground: their bottom face is the ground, facing as they face.
local function markerGround(markerPart: BasePart): CFrame
	return markerPart.CFrame * CFrame.new(0, -markerPart.Size.Y / 2, 0)
end

-- How many places run straight back from the counter before the line turns.
local function straightPlaces(): number
	return math.max(1, math.floor(Config.QueueDepth / Config.QueueSpacing) + 1)
end

-- Place `index` in line (1 = the front), on the ground, facing the counter as QueueStart does. Patients stand
-- exactly here (Patients.queueSpot calls this) and the queue lane paints its numbered spots here, so the two always
-- agree, kit plots included. The line grows away from the counter, Config.QueueSpacing apart. Once it is
-- Config.QueueDepth studs long it turns sideways (away from where patients arrive), so big creatures spaced out
-- still fit on the plot's path instead of spilling into the street.
function PlotBuilder.queueSpot(queueStart: BasePart, spawn: BasePart?, index: number): CFrame
	local start = markerGround(queueStart)
	local spacing = Config.QueueSpacing
	local straight = straightPlaces()
	if index <= straight then
		return start * CFrame.new(0, 0, (index - 1) * spacing)
	end
	local arriveX = if spawn then start:PointToObjectSpace(spawn.Position).X else 0
	local side = if arriveX > 0 then -1 else 1
	return start * CFrame.new(side * (index - straight) * spacing, 0, (straight - 1) * spacing)
end

-- The lane, in the frame of the ground under QueueStart: +Z runs back from the counter toward the gate.
local LANE_WIDTH = 6 -- the pavement between its edges (the biggest creature is about 5 studs wide)
local LANE_EDGE = 0.45 -- each coloured edge
local LANE_TILE = 3 -- each tile runs about this far along the lane, the lane's full width across (6 on a plot)
local LANE_GROUT = 0.14 -- the gap between tiles
local LANE_FAR = 3 -- the pavement runs this far past the last place in line ...
local LANE_GATE_GAP = 0.9 -- ... but stops this short of the plot's edge (inside the fence, in the gate)
local LANE_NEAR_GAP = 0.25 -- it starts this far in front of the Counter ...
local LANE_NEAR_MAX = 3.5 -- ... or at most this far ahead of the front place
local SPOT_DIAMETER = 3.6
-- Heights of each layer's top above the ground. The placeholder path's top is at 0.15; each layer sits a visible
-- step above the one under it so nothing flickers. A creature standing in line sinks only a little into it.
local LANE_TILE_TOP = 0.25
local LANE_SPOT_TOP = 0.3
local LANE_EDGE_TOP = 0.35
-- Each number floats on its spot disc: on the disc's top (a cylinder's Right face once Parts.cylinder stands it
-- up). The disc turns a quarter first, so the face's up runs toward the Counter and the numbers read upright for
-- someone walking in from the gate (the same quarter turn the old number plates took, checked in Studio 2026-11-16).
local NUMBER_TURN = CFrame.Angles(0, -math.pi / 2, 0)

-- How far a point can go along a flat world direction before it leaves the part's footprint (its own X and Z).
-- math.huge when it never does, or when the point isn't over the part.
local function distanceToEdge(boxPart: BasePart, origin: Vector3, direction: Vector3): number
	local o = boxPart.CFrame:PointToObjectSpace(origin)
	local d = boxPart.CFrame:VectorToObjectSpace(direction)
	local halfX, halfZ = boxPart.Size.X / 2, boxPart.Size.Z / 2
	if math.abs(o.X) > halfX or math.abs(o.Z) > halfZ then
		return math.huge
	end
	local function exit(p: number, v: number, half: number): number
		if v > 1e-6 then
			return (half - p) / v
		elseif v < -1e-6 then
			return (-half - p) / v
		end
		return math.huge
	end
	return math.min(exit(o.X, d.X, halfX), exit(o.Z, d.Z, halfZ))
end

-- The Counter's half depth along a flat world direction (its box projected on it).
local function halfDepth(boxPart: BasePart, direction: Vector3): number
	local cf, size = boxPart.CFrame, boxPart.Size
	return math.abs(direction:Dot(cf.RightVector)) * size.X / 2
		+ math.abs(direction:Dot(cf.UpVector)) * size.Y / 2
		+ math.abs(direction:Dot(cf.LookVector)) * size.Z / 2
end

-- The part the plot stands on: a kit plot's Ground Part, or the placeholder's Ground.Pad.
local function groundPart(plotModel: Model): BasePart?
	local ground = plotModel:FindFirstChild("Ground")
	if ground and ground:IsA("BasePart") then
		return ground
	end
	local pad = ground and ground:FindFirstChild("Pad")
	return if pad and pad:IsA("BasePart") then pad else nil
end

-- A flat strip in lane space from (a.X, a.Y) to (b.X, b.Y) (x, z on the ground), `width` across, its top at `top`.
local function laneStrip(
	lane: Model,
	start: CFrame,
	name: string,
	a: Vector2,
	b: Vector2,
	width: number,
	top: number,
	color: Color3
): BasePart
	local from = Vector3.new(a.X, top / 2, a.Y)
	local to = Vector3.new(b.X, top / 2, b.Y)
	local length = (to - from).Magnitude
	local middle = (from + to) / 2
	local cf = start * (if length > 1e-3 then CFrame.lookAt(middle, to) else CFrame.new(middle))
	return paint(part(lane, name, Vector3.new(width, top, math.max(length, 0.05)), cf, color))
end

-- Pavement over the rectangle from (a) to (b) in lane space, LANE_WIDTH across: rows of tiles the lane's full width,
-- alternating the two mid-tones, with a thin gap between them.
local function lanePaving(lane: Model, start: CFrame, a: Vector2, b: Vector2)
	local length = (b - a).Magnitude
	if length < 0.1 then
		return
	end
	local along = (b - a) / length
	local rows = math.max(1, math.floor(length / LANE_TILE + 0.5))
	local tileLength = length / rows
	for row = 1, rows do
		local centre = a + along * ((row - 0.5) * tileLength)
		local half = along * ((tileLength - LANE_GROUT) / 2)
		local color = if row % 2 == 0 then COLORS.Pavement else COLORS.PavementAlt
		laneStrip(lane, start, "LaneTile", centre - half, centre + half, LANE_WIDTH, LANE_TILE_TOP, color)
	end
end

-- A numbered spot where a patient waits: a disc in the plot's colour with its number floating on it (white,
-- outlined, no board).
local function laneSpot(lane: Model, spot: CFrame, index: number, accent: Color3)
	local disc = paint(
		cylinder(
			lane,
			"LaneSpot",
			0.1,
			SPOT_DIAMETER,
			spot * CFrame.new(0, LANE_SPOT_TOP - 0.05, 0) * NUMBER_TURN,
			accent
		)
	)
	-- Lit like the ground, so it dims at night with everything else.
	local gui = detailGui(disc, "NumberGui", Enum.NormalId.Right, 40, 100, 1)
	local number = floatText(gui, tostring(index), {
		Size = UDim2.fromScale(0.62, 0.62),
		Position = UDim2.fromScale(0.19, 0.19),
	})
	number.Name = "Number"
end

-- Paves the plot's line from just in front of the Counter out toward the gate, worked out from the QueueStart,
-- PatientSpawn, Counter and Ground parts and PlotBuilder.queueSpot, so it lines up on a kit plot too.
local function buildQueueLane(plotModel: Model, accent: Color3)
	if plotModel:FindFirstChild("QueueLane") then
		return -- the brother's own
	end
	local queueStart = plotModel:FindFirstChild("QueueStart")
	if not (queueStart and queueStart:IsA("BasePart")) then
		return
	end
	local spawnMarker = plotModel:FindFirstChild("PatientSpawn")
	local spawn = if spawnMarker and spawnMarker:IsA("BasePart") then spawnMarker else nil
	local start = markerGround(queueStart)
	local back = start:VectorToWorldSpace(Vector3.zAxis) -- from the counter toward the gate

	local lane = Instance.new("Model")
	lane.Name = "QueueLane"

	-- The front end: just short of the Counter's face.
	local near = 1.5
	local counter = plotModel:FindFirstChild("Counter")
	if counter and counter:IsA("BasePart") then
		local gap = -start:PointToObjectSpace(counter.Position).Z - halfDepth(counter, back)
		if gap > 0 then
			near = math.clamp(gap - LANE_NEAR_GAP, 0.5, LANE_NEAR_MAX)
		end
	end

	-- Every place in line, in lane space.
	local count = math.max(1, Config.MaxQueue)
	local spots: { CFrame } = {}
	for index = 1, count do
		spots[index] = start:ToObjectSpace(PlotBuilder.queueSpot(queueStart, spawn, index))
	end
	local last = spots[count].Position

	-- The far end: LANE_FAR past the last place, inside the plot's edge.
	local turned = count > straightPlaces()
	local cornerZ = spots[math.min(count, straightPlaces())].Position.Z
	local outward = if turned then Vector2.new(if last.X > 0 then 1 else -1, 0) else Vector2.new(0, 1)
	local far = LANE_FAR
	local ground = groundPart(plotModel)
	if ground then
		local room = distanceToEdge(
			ground,
			start:PointToWorldSpace(last),
			start:VectorToWorldSpace(Vector3.new(outward.X, 0, outward.Y))
		)
		far = math.max(math.min(far, room - LANE_GATE_GAP), SPOT_DIAMETER / 2 + 0.3)
	end
	local tip = Vector2.new(last.X, last.Z) + outward * far

	local h, e = LANE_WIDTH / 2, LANE_EDGE
	local frontZ = -near
	if not turned then
		lanePaving(lane, start, Vector2.new(0, frontZ), tip)
		for _, side in { -1, 1 } do
			local x = side * (h + e / 2)
			laneStrip(lane, start, "LaneEdge", Vector2.new(x, frontZ), Vector2.new(x, tip.Y), e, LANE_EDGE_TOP, accent)
		end
	else
		-- Straight back to the corner, then sideways (Patients turns the line once it's Config.QueueDepth long).
		local s = outward.X
		lanePaving(lane, start, Vector2.new(0, frontZ), Vector2.new(0, cornerZ + h))
		lanePaving(lane, start, Vector2.new(s * h, cornerZ), Vector2.new(tip.X, cornerZ))
		local outer, inner = -s * (h + e / 2), s * (h + e / 2)
		laneStrip(
			lane,
			start,
			"LaneEdge",
			Vector2.new(outer, frontZ),
			Vector2.new(outer, cornerZ + h + e),
			e,
			LANE_EDGE_TOP,
			accent
		)
		laneStrip(
			lane,
			start,
			"LaneEdge",
			Vector2.new(-s * h, cornerZ + h + e / 2),
			Vector2.new(tip.X, cornerZ + h + e / 2),
			e,
			LANE_EDGE_TOP,
			accent
		)
		laneStrip(
			lane,
			start,
			"LaneEdge",
			Vector2.new(inner, frontZ),
			Vector2.new(inner, cornerZ - h - e),
			e,
			LANE_EDGE_TOP,
			accent
		)
		laneStrip(
			lane,
			start,
			"LaneEdge",
			Vector2.new(s * h, cornerZ - h - e / 2),
			Vector2.new(tip.X, cornerZ - h - e / 2),
			e,
			LANE_EDGE_TOP,
			accent
		)
	end

	for index, spot in spots do
		laneSpot(lane, start * spot, index, accent)
	end
	lane.Parent = plotModel
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
		buildQueueLane(model, plotAccentFor(index))
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
	PlotBuilder.buildBuilding(plotModel, 1) -- a free plot is back to Lv 1's podium (Level attribute 1)
end

return PlotBuilder
