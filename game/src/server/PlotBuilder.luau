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
-- Every plot also has a MascotSpot marker beside the Counter (Server/Rebirth's mascot, from R5) and a hidden
-- SignGui.BranchBadge pill beside the RankBadge (Server/Rebirth shows "🏢 n" from R1).
--
-- Parts budget (docs/plan/2026-11-16-perf-budget.md; Config.Look): a Lv 5 plot with every room is at most 400 parts
-- without creatures and decor. Flat details are drawn as SurfaceGuis (the awnings' stripes, the floor and lawn
-- stripes, the wall bands) so everything fits; tests/PartBudget.spec keeps the count per level.
--
-- Every plot (kit or placeholder) also gets a QueueLane Model: pavement under the patients' line, from the Counter
-- out toward the gate, with a coloured edge on each side and a numbered spot at each place in line (queueSpot), so
-- it reads as "the line" (Joshua: "make a pavement outside of the place where they line up"). Walk-through and
-- ray-ignored. A kit Plot with its own QueueLane child keeps that one.
--
-- Coordinates. Each plot has a CFrame at the centre of its ground's TOP face, LookVector pointing at the street
-- (that CFrame is also the plot Model's WorldPivot). In plot-local space +X is right as you face the street, -Z is
-- the street side (front edge z = -35) and +Z the back. Markers are 2x1x2 invisible Parts resting on the ground.
-- Rooms face the street too. Inside a room Model, y = 0.3 is the top of the Floor.
--
-- The brother's models win: ServerStorage.ClinicKit.<RoomId> replaces a placeholder room, and
-- ServerStorage.ClinicKit.Plot (pivot = ground-top centre, facing the street) replaces the placeholder plot.
-- Workspace.Shop is never touched: the town sits at Config.Town.Origin.
--
-- STUB (T4): the plots and rooms below are still the candy-pop ones (awnings, white fences, glossy boards). T4
-- rebuilds them to the look build plan §B6 "T4's side": the dark studded Pad, the Stand without its shell at the
-- Shared/Logic/Building spots, the annexes, floating sign text.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local Rooms = require(Shared.Data.Rooms)
local Stations = require(Shared.Data.Stations)
local HospitalBuilder = require(script.Parent.HospitalBuilder)
local TownBuilder = require(script.Parent.TownBuilder)
local NightLights = require(script.Parent.World.NightLights)
local Parts = require(script.Parent.World.Parts)
local Props = require(script.Parent.World.Props)

local part, soft, ball, cylinder = Parts.part, Parts.soft, Parts.ball, Parts.cylinder
local marker, paint, rounded, band = Parts.marker, Parts.paint, Parts.rounded, Parts.band
local detailGui, iconBadge, iconLabel = Parts.surface, Parts.iconBadge, Parts.iconLabel
local candyLabel, candyBoard = Parts.candyLabel, Parts.candyBoard
local lighten, darken = Parts.lighten, Parts.darken
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

local WHITE = Palette.White
local CANDY = Palette.Candy
local WORLD = Palette.World

-- Candy pop (memory-20261116-007). The base colours live in shared/Palette; these are their jobs on a plot.
local COLORS = {
	Lawn = WORLD.Grass,
	LawnStripe = WORLD.Grass:Lerp(WORLD.LeavesLight, 0.45),
	Path = WORLD.Path,
	Fence = WORLD.Fence,
	Trunk = WORLD.Trunk,
	LampGlow = WORLD.Lamp,
	Water = WORLD.Water,
	Flag = CANDY.Red,
	ForSale = CANDY.Yellow,
	Pavement = WORLD.Pavement,
	PavementAlt = WORLD.PavementAlt,
	PavementGrout = WORLD.PavementGrout,
}
local FLOWERS = { CANDY.Pink, CANDY.Yellow, WHITE, CANDY.Purple, CANDY.Red, CANDY.Orange }
local STONES =
	{ lighten(CANDY.Pink, 0.4), lighten(CANDY.Yellow, 0.4), lighten(CANDY.Blue, 0.4), lighten(CANDY.Purple, 0.4) }

-- Plot_n's own accent (Palette.PlotColors).
local function plotAccentFor(index: number): Color3
	local colors = Palette.PlotColors
	return colors[(index - 1) % #colors + 1]
end

-- Each room has its own candy colour (awning stripes, trim, plaque, bed frames); the Stand takes its plot's accent.
type RoomStyle = {
	Main: Color3,
	Blanket: Color3,
	Floor: Color3,
	FloorStripe: Color3,
	Wall: Color3,
	Garden: boolean, -- low hedges and a flower arbor instead of walls and a striped awning
	Snow: boolean,
}

local function roomStyle(main: Color3, blanket: Color3, snow: boolean?): RoomStyle
	return {
		Main = main,
		Blanket = blanket,
		Floor = lighten(main, 0.82),
		FloorStripe = lighten(main, 0.64),
		Wall = lighten(main, 0.5),
		Garden = false,
		Snow = snow == true,
	}
end

local STYLES: { [string]: RoomStyle } = {
	Stand = roomStyle(CANDY.Red, CANDY.Yellow),
	BathRoom = roomStyle(CANDY.Cyan, CANDY.Yellow),
	Ward = roomStyle(CANDY.Purple, CANDY.Pink),
	WinterWing = roomStyle(CANDY.Blue, CANDY.Mint, true),
	Garden = {
		Main = CANDY.Yellow,
		Blanket = WHITE,
		Floor = WORLD.Grass:Lerp(WORLD.LeavesLight, 0.3),
		FloorStripe = WORLD.LeavesLight,
		Wall = WORLD.Leaves,
		Garden = true,
		Snow = false,
	},
}

local function styleFor(roomId: string, accent: Color3?): RoomStyle
	if roomId == "Stand" and accent then
		return roomStyle(accent, CANDY.Yellow)
	end
	return STYLES[roomId] or STYLES.Stand
end

-- Where things go inside each placeholder room (room-local x, z; y is ignored). Counts match Data/Rooms.
type Layout = { Stations: { [string]: Vector3 }, Beds: { Vector3 }, Decor: { Vector3 } }
local LAYOUTS: { [string]: Layout } = {
	Stand = {
		Stations = { Remedy = Vector3.new(-5.5, 0, 4.7), Plaster = Vector3.new(0.5, 0, 4.7) },
		Beds = { Vector3.new(7.6, 0, 1.2) },
		Decor = { Vector3.new(-8.5, 0, -4.2), Vector3.new(8.3, 0, -4.5) },
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

local function buildStation(model: Model, stationId: string, at: Vector3)
	local station = Stations[stationId]
	local color = if station then station.Color else CANDY.Orange
	local icon = if station then station.Icon else "❔"
	local base = CFrame.new(at.X, FLOOR_TOP, at.Z)
	local stationPart: BasePart

	-- Every station wears its Data/Stations colour (the colour kids match to the ailment), with white trim.
	if stationId == "Bath" then
		stationPart = part(model, "Station_Bath", Vector3.new(5.6, 2.2, 3.6), base * CFrame.new(0, 1.1, 0), WHITE)
		soft(part(model, "TubStripe", Vector3.new(5.68, 0.5, 3.68), base * CFrame.new(0, 1.4, 0), color))
		soft(part(model, "Water", Vector3.new(5, 0.15, 3), base * CFrame.new(0, 2.15, 0), COLORS.Water))
		for i, offset in { Vector3.new(-1.8, 2.5, -0.6), Vector3.new(-0.4, 2.6, 0.7), Vector3.new(1.2, 2.5, -0.3) } do
			local bubble = soft(ball(model, "Bubble", 0.8 + i * 0.15, base * CFrame.new(offset), WHITE))
			bubble.Transparency = 0.1
		end
		for _, x in { -2.3, 2.3 } do
			soft(ball(model, "Foot", 0.6, base * CFrame.new(x, 0.2, 1.3), CANDY.Yellow))
			soft(ball(model, "Foot", 0.6, base * CFrame.new(x, 0.2, -1.3), CANDY.Yellow))
		end
	else
		stationPart =
			part(model, "Station_" .. stationId, Vector3.new(4.2, 3, 2.6), base * CFrame.new(0, 1.5, 0), color)
		soft(part(model, "Top", Vector3.new(4.5, 0.3, 2.9), base * CFrame.new(0, 3.15, 0), WHITE))
		-- A white stripe across its front, 0.7 above its middle (drawn: the parts budget).
		local front = detailGui(stationPart, "StripeGui", Enum.NormalId.Front, 20)
		band(front, "Stripe", UDim2.fromScale(1, 0.5 / 3), UDim2.fromScale(0.5, 0.5 - 0.7 / 3), WHITE)
		local top = base * CFrame.new(0, 3.3, 0)
		if stationId == "Remedy" then
			-- Potion bottles in colours no other station uses, so they never read as a colour clue.
			local bottles = { CANDY.Mint, CANDY.Lime, lighten(color, 0.4) }
			for i, bottleColor in bottles do
				local x = (i - 2) * 1.2
				soft(cylinder(model, "Bottle", 1, 0.6, top * CFrame.new(x, 0.5, 0.2), bottleColor))
				soft(ball(model, "Cork", 0.4, top * CFrame.new(x, 1.1, 0.2), WORLD.Wood))
			end
		elseif stationId == "Plaster" then
			soft(part(model, "Box", Vector3.new(1.8, 0.8, 1.2), top * CFrame.new(-0.6, 0.4, 0.2), WHITE))
			soft(part(model, "BoxStripe", Vector3.new(1.82, 0.22, 1.22), top * CFrame.new(-0.6, 0.4, 0.2), CANDY.Red))
			soft(cylinder(model, "Roll", 0.5, 0.9, top * CFrame.new(1.2, 0.25, 0.1), lighten(color, 0.5)))
		elseif stationId == "Cocoa" then
			soft(cylinder(model, "Mug", 0.9, 0.8, top * CFrame.new(-0.9, 0.45, 0.1), WHITE))
			soft(cylinder(model, "CocoaTop", 0.1, 0.7, top * CFrame.new(-0.9, 0.86, 0.1), COLORS.Trunk)) -- cocoa brown
			soft(part(model, "Marshmallow", Vector3.new(0.3, 0.3, 0.3), top * CFrame.new(-0.8, 1.0, 0.1), WHITE))
			soft(ball(model, "Pot", 1.3, top * CFrame.new(0.9, 0.55, 0.2), CANDY.Red))
		end
	end

	iconBadge(stationPart, "IconGui", icon, color, 2.6, stationPart.Size.Y / 2 + 2.1)
end

-- `floorTop` is the height of the floor it stands on in the model's own space (a room's FLOOR_TOP by default);
-- `turn` 1 turns its pillow end from the back (+Z) to +X (a ward bed across the front of the Wards floor).
local function buildBed(model: Model, index: number, at: Vector3, style: RoomStyle, floorTop: number?, turn: number?)
	local base = CFrame.new(at.X, floorTop or FLOOR_TOP, at.Z)
	if turn == 1 then
		base *= CFrame.Angles(0, math.pi / 2, 0)
	end
	part(model, "BedFrame", Vector3.new(4.4, 0.8, 7), base * CFrame.new(0, 0.4, 0), style.Main)
	-- Bed_<n> is the mattress: patients lie on its top face; the pillow end is +Z (the room's back).
	part(model, "Bed_" .. index, Vector3.new(4, 1, 6.6), base * CFrame.new(0, 1.3, 0), WHITE)
	soft(part(model, "Pillow", Vector3.new(3, 0.5, 1.4), base * CFrame.new(0, 2.05, 2.4), lighten(style.Blanket, 0.6)))
	soft(part(model, "Blanket", Vector3.new(4.1, 0.25, 3.4), base * CFrame.new(0, 1.92, -1.4), style.Blanket))
	soft(part(model, "BlanketStripe", Vector3.new(4.18, 0.31, 0.6), base * CFrame.new(0, 1.92, -0.2), WHITE))
	part(model, "Headboard", Vector3.new(4.4, 2.6, 0.5), base * CFrame.new(0, 1.3, 3.75), darken(style.Main, 0.1))
end

local function buildDecorSlot(model: Model, index: number, at: Vector3)
	marker(model, "DecorSlot_" .. index, CFrame.new(at.X, FLOOR_TOP + 0.5, at.Z), Vector3.new(4, 1, 4))
	-- A soft white spot that shows where decor goes.
	local spot = paint(cylinder(model, "DecorSpot", 0.06, 3.4, CFrame.new(at.X, FLOOR_TOP + 0.03, at.Z), WHITE))
	spot.Transparency = 0.35
end

local function buildShell(model: Model, roomId: string, w: number, d: number, style: RoomStyle)
	local room = Rooms[roomId]
	local back = d / 2
	if not style.Garden then
		-- Tall enough that the awning's high back edge rests on it.
		local backWall =
			part(model, "BackWall", Vector3.new(w, 8.6, 0.6), CFrame.new(0, FLOOR_TOP + 4.3, back - 0.3), style.Wall)
		-- A white band low on the back wall (two-tone, like a sweet shop), 1.2 above the floor (drawn).
		local wallGui = detailGui(backWall, "BandGui", Enum.NormalId.Front, 10)
		band(wallGui, "WallBand", UDim2.fromScale((w - 1.3) / w, 1.1 / 8.6), UDim2.fromScale(0.5, 1 - 1.2 / 8.6), WHITE)
		for _, side in { -1, 1 } do
			local x = side * (w / 2 - 0.3)
			part(
				model,
				"SideWall",
				Vector3.new(0.6, 4, d * 0.5),
				CFrame.new(x, FLOOR_TOP + 2, back - d * 0.25),
				style.Wall
			)
			soft(
				part(
					model,
					"WallCap",
					Vector3.new(0.8, 0.3, d * 0.5 + 0.2),
					CFrame.new(x, FLOOR_TOP + 4.15, back - d * 0.25),
					style.Main
				)
			)
		end
		-- A striped awning over the back half, sloping down toward the front, with a flap hanging off its front
		-- edge so the stripes run down the front. One part each, the white stripes drawn on (the parts budget):
		-- six stripes across, white first from the left.
		local depth = d * 0.45
		local stripes = 6
		local slope = CFrame.new(0, FLOOR_TOP + 8.1, back - depth / 2) * CFrame.Angles(math.rad(-12), 0, 0)
		local awning = soft(part(model, "Awning", Vector3.new(w + 1, 0.35, depth + 0.6), slope, style.Main))
		local edge = slope * Vector3.new(0, -0.175, -(depth + 0.6) / 2)
		local flap = soft(
			part(
				model,
				"AwningFlap",
				Vector3.new(w + 1, 0.8, 0.12),
				CFrame.new(edge - Vector3.new(0, 0.4, 0)),
				style.Main
			)
		)
		local topGui = detailGui(awning, "StripesGui", Enum.NormalId.Top, 8)
		local flapGui = detailGui(flap, "StripesGui", Enum.NormalId.Front, 8)
		for i = 1, stripes, 2 do
			-- Stripe i counts from the left (-X). On the Top face the gui's Y runs along +X; on the Front face its X
			-- runs along -X (seen from the street).
			band(topGui, "Stripe", UDim2.fromScale(1, 1 / stripes), UDim2.fromScale(0.5, (i - 0.5) / stripes), WHITE)
			band(
				flapGui,
				"Stripe",
				UDim2.fromScale(1 / stripes, 1),
				UDim2.fromScale(1 - (i - 0.5) / stripes, 0.5),
				WHITE
			)
		end
		for _, side in { -1, 1 } do
			cylinder(
				model,
				"AwningPost",
				7.2,
				0.5,
				CFrame.new(side * (w / 2 - 0.6), FLOOR_TOP + 3.6, back - depth + 0.2),
				WHITE
			)
		end
		if style.Snow then
			for _, x in { -w / 3, 0, w / 3 } do
				soft(
					part(
						model,
						"Snow",
						Vector3.new(w / 4, 0.4, depth * 0.7),
						CFrame.new(x, FLOOR_TOP + 8.45, back - depth / 2) * CFrame.Angles(math.rad(-12), 0, 0),
						WHITE
					)
				)
			end
		end
	else
		-- Garden: low hedges and a flower arbor instead of walls and an awning.
		part(model, "BackWall", Vector3.new(w, 3, 1.2), CFrame.new(0, FLOOR_TOP + 1.5, back - 0.6), style.Wall)
		for _, side in { -1, 1 } do
			part(
				model,
				"SideWall",
				Vector3.new(1.2, 2.4, d * 0.6),
				CFrame.new(side * (w / 2 - 0.6), FLOOR_TOP + 1.2, back - d * 0.3),
				style.Wall
			)
		end
		for _, side in { -1, 1 } do
			cylinder(model, "ArborPost", 7, 0.6, CFrame.new(side * 4.5, FLOOR_TOP + 3.5, back - 2.2), WHITE)
		end
		part(model, "ArborBeam", Vector3.new(10.4, 0.6, 1.2), CFrame.new(0, FLOOR_TOP + 7.2, back - 2.2), style.Main)
		for i = 0, 6 do
			soft(
				ball(
					model,
					"ArborFlower",
					0.9,
					CFrame.new(-4.5 + i * 1.5, FLOOR_TOP + 7.6, back - 2.2 + (i % 2) * 0.4),
					FLOWERS[i % #FLOWERS + 1]
				)
			)
		end
		for _, x in { -w / 2 + 1.6, w / 2 - 1.6 } do -- along the hedges, clear of the decor slots
			for z = -d / 2 + 2, d / 2 - 5, 3.5 do
				soft(ball(model, "Flower", 0.8, CFrame.new(x, FLOOR_TOP + 0.4, z), FLOWERS[math.random(1, #FLOWERS)]))
			end
		end
	end

	-- Name plaque: on the back wall above the station badges, or hanging under the garden arbor.
	local plaqueHeight = if style.Garden then FLOOR_TOP + 6.1 else FLOOR_TOP + 7.3
	local plaqueZ = if style.Garden then back - 2.88 else back - 0.68
	local plaqueWidth = if style.Garden then 8 else math.min(w * 0.5, 10)
	local plaque = soft(
		part(
			model,
			"Plaque",
			Vector3.new(plaqueWidth, 1.5, 0.15),
			CFrame.new(0, plaqueHeight, plaqueZ),
			darken(style.Main, 0.12)
		)
	)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PlaqueGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.MaxDistance = 100
	candyBoard(gui, style.Main, 3, 10, 3)
	candyLabel(gui, "Name", room.Icon .. " " .. room.Name, UDim2.fromScale(0.92, 0.72), UDim2.fromScale(0.04, 0.14), 3)
	gui.Parent = plaque
end

local function placeholderRoom(roomId: string, accent: Color3?): Model
	local room = Rooms[roomId]
	local style = styleFor(roomId, accent)
	local size = slotSize(roomId)
	local w, d = size.X, size.Z

	local model = Instance.new("Model")
	model.Name = "Room_" .. roomId
	local floor = part(model, "Floor", size, CFrame.identity, style.Floor)
	part(model, "Edge", Vector3.new(w + 0.6, 0.4, d + 0.6), CFrame.new(0, -0.15, 0), style.Main)
	model.PrimaryPart = floor
	-- Three painted stripes across the floor, so it reads as seven two-tone bands (drawn on its top: on a Top face
	-- the gui's X runs along Z, so bands across Z are columns).
	local floorGui = detailGui(floor, "StripesGui", Enum.NormalId.Top, 6)
	for i = -1, 1 do
		band(
			floorGui,
			"FloorStripe",
			UDim2.fromScale(1 / 7, (w - 0.4) / w),
			UDim2.fromScale(0.5 + i * 2 / 7, 0.5),
			style.FloorStripe
		)
	end

	buildShell(model, roomId, w, d, style)

	local layout = layoutFor(roomId, w, d)
	for _, stationId in room.Stations do
		buildStation(model, stationId, layout.Stations[stationId])
	end
	for index, at in layout.Beds do
		buildBed(model, index, at, style)
	end
	for index, at in layout.Decor do
		buildDecorSlot(model, index, at)
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

-- `accent` is the plot's colour, for the Stand's awning (a kit room ignores it).
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
-- Slot previews ("for sale"): a see-through yellow floor, a candy dashed outline and a floating price badge
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
			local color = if n % 2 == 0 then WHITE else COLORS.ForSale
			paint(part(preview, "Dash", Vector3.new(dash, 0.14, 0.6), cf, color))
		end
	end

	-- The price badge: a candy-yellow panel with a thick ink outline (nested frames, so it scales with distance).
	local anchor = marker(preview, "BadgeAnchor", ground * CFrame.new(0, 3.5, 0), Vector3.one)
	local gui = Instance.new("BillboardGui")
	gui.Name = "PreviewGui"
	gui.Size = UDim2.fromScale(6, 4)
	gui.LightInfluence = 0
	gui.MaxDistance = 90
	gui.DistanceLowerLimit = PREVIEW_NEAR_STUDS
	local outline = Instance.new("Frame")
	outline.Name = "Outline"
	outline.Size = UDim2.fromScale(1, 1)
	outline.BackgroundColor3 = Palette.Outline
	outline.BorderSizePixel = 0
	outline.ZIndex = 1
	rounded(outline, UDim.new(0.24, 0))
	outline.Parent = gui
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.94, 0.91)
	panel.BackgroundColor3 = COLORS.ForSale
	panel.BorderSizePixel = 0
	panel.ZIndex = 2
	rounded(panel, UDim.new(0.22, 0))
	Palette.candyGradient(panel)
	panel.Parent = gui
	iconLabel(gui, "Icon", "🔒" .. room.Icon, UDim2.fromScale(0.86, 0.46), UDim2.fromScale(0.07, 0.08))
	candyLabel(
		gui,
		"Cost",
		string.format("⭐%d  💰%d", room.StarsNeeded, room.Price),
		UDim2.fromScale(0.86, 0.34),
		UDim2.fromScale(0.07, 0.57),
		2
	)
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

-- The clinic sign: a glossy board in the plot's accent inside an accent frame, and the owner's name in white
-- outlined display text. It stands beside the gate facing the street, raised on two tall white posts (candy balls
-- on top) so the whole board, frame and all, clears the 3-stud fence in front of it (Joshua: "the signboard is
-- behind the fence so i cant see it well"). OwnerName and HeartCount stay direct children of SignGui (Plots and
-- Visits set them), and so does RankBadge, the owner's Doctor rank on a white pill beside the hearts
-- (Server/Playtime sets it).
local SIGN_SIZE = Vector3.new(10, 4, 0.5)
local SIGN_X = -13 -- plot-local: beside the gate (the gate posts stand at x = ±6.2)
local SIGN_Z = -34 -- just behind the front fence (z = -34.6), the board's face 0.2 behind its rails
local SIGN_BOTTOM = 4 -- the board's bottom edge; its frame starts 0.6 above the fence's 3-stud top

-- A white pill with a dark rim on the sign's bottom row (the Doctor rank, the 🏢 branches), hidden until its system
-- fills it.
local function signPill(gui: SurfaceGui, name: string, size: UDim2, position: UDim2): TextLabel
	local pill = Instance.new("TextLabel")
	pill.Name = name
	pill.BackgroundColor3 = WHITE
	pill.BackgroundTransparency = 0.05
	pill.Position = position
	pill.Size = size
	pill.Font = Palette.DisplayFont
	pill.TextColor3 = Palette.Ink
	pill.TextScaled = true
	pill.Text = ""
	pill.Visible = false
	pill.ZIndex = 3
	rounded(pill, UDim.new(0.5, 0))
	local rim = Instance.new("UIStroke")
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Color = Palette.Outline
	rim.Thickness = 3
	rim.Parent = pill
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
	local y = SIGN_BOTTOM + h / 2
	local sign = part(model, "Sign", SIGN_SIZE, cf * CFrame.new(SIGN_X, y, SIGN_Z), darken(accent, 0.15))
	soft(
		part(scenery, "SignTrim", Vector3.new(w + 0.8, h + 0.8, 0.4), cf * CFrame.new(SIGN_X, y, SIGN_Z + 0.45), accent)
	)
	local postHeight = y + h / 2 + 0.4 -- up to the frame's top edge
	for _, side in { -1, 1 } do
		local x = SIGN_X + side * (w / 2 - 0.6)
		part(
			scenery,
			"SignPost",
			Vector3.new(0.7, postHeight, 0.7),
			cf * CFrame.new(x, postHeight / 2, SIGN_Z + 1),
			WHITE
		)
		soft(ball(scenery, "SignPostCap", 1.1, cf * CFrame.new(x, postHeight + 0.4, SIGN_Z + 1), accent))
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front -- the side facing the street
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0 -- stays bright and readable at night
	gui.MaxDistance = 150
	candyBoard(gui, accent, 8, 18, 5)
	candyLabel(gui, "OwnerName", "✨ Free clinic", UDim2.fromScale(0.86, 0.5), UDim2.fromScale(0.07, 0.1), 4)
	candyLabel(gui, "HeartCount", "", UDim2.fromScale(0.3, 0.28), UDim2.fromScale(0.07, 0.62), 3)
	signPill(gui, "RankBadge", UDim2.fromScale(0.39, 0.3), UDim2.fromScale(0.54, 0.6))
	signPill(gui, "BranchBadge", UDim2.fromScale(0.16, 0.3), UDim2.fromScale(0.37, 0.6))
	gui.Parent = sign
end

-- Progression v2 (§B4): every sign has a hidden BranchBadge pill (Server/Rebirth shows "🏢 n" from R1), and every
-- plot a MascotSpot marker beside the Counter (Server/Rebirth's mascot, from R5). A kit plot without them gets them.
local MASCOT_SPOT = Vector3.new(-8, 0.5, -13) -- plot-local: left of the Counter, clear of the line and the Stand

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
			signPill(gui, "BranchBadge", UDim2.fromScale(0.16, 0.3), UDim2.fromScale(0.37, 0.6))
		end
	end
	if not model:FindFirstChild("MascotSpot") then
		marker(model, "MascotSpot", model:GetPivot() * CFrame.new(MASCOT_SPOT))
	end
end

local function buildFenceAndGate(scenery: Model, cf: CFrame, half: number, accent: Color3)
	local e = half - 0.4
	local gate = 5.6
	local function at(x: number, z: number): CFrame
		return cf * CFrame.new(x, 0, z)
	end
	Props.fence(scenery, at(-e, e), at(e, e))
	Props.fence(scenery, at(-e, -e), at(-e, e))
	Props.fence(scenery, at(e, -e), at(e, e))
	Props.fence(scenery, at(-e, -e), at(-gate - 0.6, -e))
	Props.fence(scenery, at(gate + 0.6, -e), at(e, -e))

	for _, x in { -gate - 0.6, gate + 0.6 } do
		part(scenery, "GatePost", Vector3.new(1.4, 6, 1.4), cf * CFrame.new(x, 3, -e), COLORS.Fence)
		local glow = soft(ball(scenery, "GateLamp", 1.2, cf * CFrame.new(x, 7.6, -e), COLORS.LampGlow))
		NightLights.light(glow, 16)
	end
	local arch = part(scenery, "GateArch", Vector3.new(gate * 2 + 2.6, 1, 1.6), cf * CFrame.new(0, 6.5, -e), accent)
	-- A white stripe round its middle, on the street and plot sides (drawn: the parts budget).
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		band(
			detailGui(arch, "StripeGui", face, 10, 300),
			"Stripe",
			UDim2.fromScale(1, 0.34),
			UDim2.fromScale(0.5, 0.5),
			WHITE
		)
	end
end

local function buildMailbox(scenery: Model, cf: CFrame, accent: Color3)
	local model = Instance.new("Model")
	model.Name = "MailboxProp"
	part(model, "Post", Vector3.new(0.4, 3, 0.4), cf * CFrame.new(9.5, 1.5, -33), WHITE)
	part(model, "Box", Vector3.new(1.6, 1.2, 2), cf * CFrame.new(9.5, 3.5, -33), accent)
	soft(part(model, "Flag", Vector3.new(0.1, 0.9, 0.35), cf * CFrame.new(10.4, 3.9, -33.5), COLORS.Flag))
	model.Parent = scenery
end

local function buildPlaceholderPlot(index: number, cf: CFrame): Model
	local half = Config.Town.PlotSize / 2
	local accent = plotAccentFor(index)
	local model = Instance.new("Model")
	model.Name = "Plot_" .. index

	local scenery = Instance.new("Model")
	scenery.Name = "Scenery"
	scenery.Parent = model

	local ground = part(model, "Ground", Vector3.new(half * 2, 1, half * 2), cf * CFrame.new(0, -0.5, 0), COLORS.Lawn)
	-- Mowing stripes, running from the street to the back (drawn on the lawn: on a Top face the gui's Y runs along
	-- +X, so stripes along Z are rows).
	local lawn = detailGui(ground, "StripesGui", Enum.NormalId.Top, 3, 400)
	for _, x in { -28, -14, 0, 14, 28 } do
		band(
			lawn,
			"LawnStripe",
			UDim2.fromScale((half * 2 - 1) / (half * 2), 7 / (half * 2)),
			UDim2.fromScale(0.5, (x + half) / (half * 2)),
			COLORS.LawnStripe
		)
	end

	-- The front path from the gate to the counter (white edged), and candy stepping stones across the back yard.
	local pathLength = half - 15.6
	local pathZ = -(half + 15.6) / 2
	local path = part(scenery, "Path", Vector3.new(10.2, 0.2, pathLength), cf * CFrame.new(0, 0.05, pathZ), COLORS.Path)
	-- Its white edges, drawn along both sides (rows on its Top face).
	local pathGui = detailGui(path, "EdgesGui", Enum.NormalId.Top, 10)
	for _, v in { 0.3 / 10.2, 1 - 0.3 / 10.2 } do
		band(pathGui, "PathEdge", UDim2.fromScale(1, 0.6 / 10.2), UDim2.fromScale(0.5, v), WHITE)
	end
	for i, z in { 3.5, 7.2, 10.9, 14.6 } do
		cylinder(scenery, "SteppingStone", 0.2, 2.8, cf * CFrame.new(math.sin(z) * 0.8, 0.05, z), STONES[i])
	end

	-- The counter: patients queue in front of it (toward the street), you treat from behind it.
	local counter = part(model, "Counter", Vector3.new(12, 3.4, 2.4), cf * CFrame.new(0, 1.7, -14.5), accent)
	soft(part(scenery, "CounterTop", Vector3.new(12.8, 0.4, 3), cf * CFrame.new(0, 3.6, -14.5), WHITE))
	-- A white stripe across its street side, 0.8 above its middle (drawn).
	local counterGui = detailGui(counter, "StripeGui", Enum.NormalId.Front, 10)
	band(counterGui, "CounterStripe", UDim2.fromScale(1, 0.6 / 3.4), UDim2.fromScale(0.5, 0.5 - 0.8 / 3.4), WHITE)

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

	-- The first-aid stand sits under a big tree (design §5.10).
	Props.tree(scenery, cf * CFrame.new(16.5, 0, -9), 1.35)
	Props.tree(scenery, cf * CFrame.new(-28, 0, -27), 1, true)
	Props.tree(scenery, cf * CFrame.new(28.5, 0, -26), 1.1)
	Props.tree(scenery, cf * CFrame.new(-29, 0, 29), 1.2)
	Props.tree(scenery, cf * CFrame.new(29.5, 0, 29.5), 1, true)
	local bushes = {
		Vector3.new(-24, 0, -32.6),
		Vector3.new(-31.5, 0, -31.8),
		Vector3.new(16, 0, -32.6),
		Vector3.new(21.5, 0, -32.6),
		Vector3.new(32, 0, -10),
		Vector3.new(-32, 0, -10),
		Vector3.new(0, 0, 32.6),
		Vector3.new(-32, 0, 20),
	}
	for _, at in bushes do
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
local LANE_TILE = 3 -- tiles are about this square
local LANE_GROUT = 0.14 -- the gap between tiles
local LANE_FAR = 3 -- the pavement runs this far past the last place in line ...
local LANE_GATE_GAP = 0.9 -- ... but stops this short of the plot's edge (inside the fence, in the gate)
local LANE_NEAR_GAP = 0.25 -- it starts this far in front of the Counter ...
local LANE_NEAR_MAX = 3.5 -- ... or at most this far ahead of the front place
local SPOT_DIAMETER = 3.6
-- Heights of each layer's top above the ground. The placeholder path's top is at 0.15; each layer sits a visible
-- step above the one under it so nothing flickers. A creature standing in line sinks only a little into it.
local LANE_BASE_TOP = 0.2
local LANE_TILE_TOP = 0.25
local LANE_SPOT_TOP = 0.3
local LANE_NUMBER_TOP = 0.33
local LANE_EDGE_TOP = 0.35
-- Spots face the counter. A Top-face SurfaceGui on a part turned that way draws sideways, so the plate turns a
-- quarter: then the numbers read upright for someone walking in from the gate (checked in Studio, 2026-11-16).
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

-- Pavement over the rectangle from (a) to (b) in lane space, LANE_WIDTH across: a grout slab with checkered tiles.
local function lanePaving(lane: Model, start: CFrame, a: Vector2, b: Vector2)
	local length = (b - a).Magnitude
	if length < 0.1 then
		return
	end
	laneStrip(lane, start, "LaneBase", a, b, LANE_WIDTH, LANE_BASE_TOP, COLORS.PavementGrout)
	local along = (b - a) / length
	local across = Vector2.new(-along.Y, along.X)
	local rows = math.max(1, math.floor(length / LANE_TILE + 0.5))
	local columns = math.max(1, math.floor(LANE_WIDTH / LANE_TILE + 0.5))
	local tileLength, tileWidth = length / rows, LANE_WIDTH / columns
	for row = 1, rows do
		for column = 1, columns do
			local centre = a
				+ along * ((row - 0.5) * tileLength)
				+ across * ((column - 0.5) * tileWidth - LANE_WIDTH / 2)
			local half = along * ((tileLength - LANE_GROUT) / 2)
			local color = if (row + column) % 2 == 0 then COLORS.Pavement else COLORS.PavementAlt
			laneStrip(
				lane,
				start,
				"LaneTile",
				centre - half,
				centre + half,
				tileWidth - LANE_GROUT,
				LANE_TILE_TOP,
				color
			)
		end
	end
end

-- A numbered spot where a patient waits: a candy disc in the plot's colour with a big white outlined number.
local function laneSpot(lane: Model, spot: CFrame, index: number, accent: Color3)
	paint(
		cylinder(
			lane,
			"LaneSpot",
			0.1,
			SPOT_DIAMETER,
			spot * CFrame.new(0, LANE_SPOT_TOP - 0.05, 0),
			lighten(accent, 0.25)
		)
	)
	local plate = marker(
		lane,
		"LaneNumber",
		spot * CFrame.new(0, LANE_NUMBER_TOP - 0.02, 0) * NUMBER_TURN,
		Vector3.new(2.6, 0.04, 2.6)
	)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "NumberGui"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 1 -- lit like the ground, so it dims at night with everything else
	gui.MaxDistance = 100
	candyLabel(gui, "Number", tostring(index), UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.1, 0.1), 4)
	gui.Parent = plate
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
	local ground = plotModel:FindFirstChild("Ground")
	if ground and ground:IsA("BasePart") then
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
	PlotBuilder.buildBuilding(plotModel, 1) -- a free plot is back to the open-air Stand (Level attribute 1)
end

return PlotBuilder
