--!strict
-- Builds the town and its clinic plots (build plan §B1). Server only.
--   PlotBuilder.buildTown(): { Model }            Workspace.Clinics.Plot_1..N, the town around them, TownSpawn
--   PlotBuilder.buildRoom(roomId): Model           an unplaced room (kit clone or placeholder), PrimaryPart = Floor
--   PlotBuilder.clearPlot(plotModel)               removes patients, decor and every room except the Stand, and
--                                                  puts the Building back to Lv 1's (Level attribute 1)
--   PlotBuilder.buildBuilding(plotModel, level, grewFrom?): Model   (depth update, T5) the hospital shell for that
--                                                  level (Data/Levels): replaces Plot.Building, sets the plot's
--                                                  Level attribute. See "The hospital building" below
-- Extra helpers (Plots uses them):
--   PlotBuilder.placeRoom(plotModel, roomId): Model?      build + place in its slot (Floor.CFrame == slot CFrame)
--   PlotBuilder.setPreview(plotModel, slotId, roomId?)    the "for sale" outline in an empty slot (nil = none)
--   PlotBuilder.queueSpot(queueStart, spawn?, index): CFrame   place `index` in line (Patients stands patients there)
--   PlotBuilder.NIGHT_LIGHT_TAG                            tag a lamp Part: Neon + PointLight on only at night
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
-- The look is "candy pop" (memory-20261116-007, colours in shared/Palette): toy-like SmoothPlastic in saturated
-- colours, white fences and trims, two-tone stripes instead of textures, and Neon only on lamps at night. Each plot
-- wears its own Palette.PlotColors accent (gate arch, sign frame, counter, mailbox, the Stand's awning), so a kid can
-- say "mine is the pink one". Signs and plaques are white outlined display text on a glossy candy board.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local LevelsData = require(Shared.Data.Levels)
local Rooms = require(Shared.Data.Rooms)
local Stations = require(Shared.Data.Stations)

local PlotBuilder = {}

PlotBuilder.NIGHT_LIGHT_TAG = "ClinicNightLight"

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
local BASE_TOP = 0.3 -- the town lawn's top, just above a default baseplate at y = 0
local PLOT_RAISE = 0.6 -- plots sit a small step above the street
local FLOOR_TOP = 0.3 -- room-local height of the floor's top face
local MAX_PLOTS = 6

local WHITE = Palette.White
local CANDY = Palette.Candy
local WORLD = Palette.World

local function lighten(color: Color3, amount: number): Color3
	return color:Lerp(WHITE, amount)
end

local function darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

-- Candy pop (memory-20261116-007). The base colours live in shared/Palette; these are their jobs in the town.
local COLORS = {
	TownLawn = WORLD.GrassDark,
	Lawn = WORLD.Grass,
	LawnStripe = WORLD.Grass:Lerp(WORLD.LeavesLight, 0.45),
	Street = WORLD.Street,
	StreetLine = WORLD.StreetLine,
	Curb = WHITE,
	PlazaRing = CANDY.Pink,
	Plaza = WORLD.Path,
	Spawn = CANDY.Yellow,
	Path = WORLD.Path,
	Fence = WORLD.Fence,
	Trunk = WORLD.Trunk,
	Bush = WORLD.GrassDark,
	LampPost = CANDY.Purple,
	LampGlow = WORLD.Lamp,
	Bench = CANDY.Blue,
	Water = WORLD.Water,
	Flag = CANDY.Red,
	ForSale = CANDY.Yellow,
	Pavement = WORLD.Pavement,
	PavementAlt = WORLD.PavementAlt,
	PavementGrout = WORLD.PavementGrout,
}
-- Tree crowns, biggest ball first. Some trees are pink blossom trees, for a bit of candy in the green.
local LEAVES =
	{ WORLD.Leaves, WORLD.LeavesLight, WORLD.Leaves:Lerp(WORLD.LeavesLight, 0.5), lighten(WORLD.LeavesLight, 0.2) }
local BLOSSOM = { lighten(CANDY.Pink, 0.2), lighten(CANDY.Pink, 0.45), CANDY.Pink, lighten(CANDY.Pink, 0.6) }
local FLOWERS = { CANDY.Pink, CANDY.Yellow, WHITE, CANDY.Purple, CANDY.Red, CANDY.Orange }
local STONES =
	{ lighten(CANDY.Pink, 0.4), lighten(CANDY.Yellow, 0.4), lighten(CANDY.Blue, 0.4), lighten(CANDY.Purple, 0.4) }
local PLANTERS = { CANDY.Pink, CANDY.Blue, CANDY.Yellow, CANDY.Purple }

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
-- Part helpers
------------------------------------------------------------------------------------------------------------------

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A decoration players walk through and rays ignore.
local function soft(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function ball(parent: Instance, name: string, diameter: number, cframe: CFrame, color: Color3): Part
	local p = part(parent, name, Vector3.one * diameter, cframe, color)
	p.Shape = Enum.PartType.Ball
	return p
end

-- An upright cylinder (Roblox cylinders run along X, so turn it to stand on Y). `cframe` is its centre.
local function cylinder(
	parent: Instance,
	name: string,
	height: number,
	diameter: number,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = part(
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		cframe * CFrame.Angles(0, 0, math.rad(90)),
		color,
		material
	)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function marker(parent: Instance, name: string, cframe: CFrame, size: Vector3?): Part
	local p = part(parent, name, size or Vector3.new(2, 1, 2), cframe, WHITE)
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

-- A flat painted detail (stripes, road lines): walk-through, ray-ignored and shadowless.
local function paint(p: BasePart): BasePart
	soft(p)
	p.CastShadow = false
	return p
end

------------------------------------------------------------------------------------------------------------------
-- GUI helpers (signs, plaques, billboards)
------------------------------------------------------------------------------------------------------------------

local function rounded(gui: GuiObject, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = gui
end

-- White display text with a thick ink outline: the candy-pop sign look. `stroke` is in the gui's own pixels.
local function candyLabel(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	position: UDim2,
	stroke: number
): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = Palette.DisplayFont
	l.TextColor3 = WHITE
	l.TextScaled = true
	l.Text = text
	l.ZIndex = 3
	Palette.outlineText(l, stroke)
	l.Parent = parent
	return l
end

-- An emoji icon. No text outline: the badge it sits on has one.
local function iconLabel(parent: Instance, name: string, text: string, size: UDim2, position: UDim2): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = Palette.BodyFont
	l.TextColor3 = Palette.Ink
	l.TextScaled = true
	l.Text = text
	l.ZIndex = 3
	l.Parent = parent
	return l
end

-- A glossy candy board filling a SurfaceGui (the sign, plaques, the welcome arch): the colour with a light-to-deep
-- gradient, a white rim and a soft shine across the top. Text labels go on top (ZIndex 3). Sizes are gui pixels.
local function candyBoard(gui: SurfaceGui, color: Color3, inset: number, radius: number, rim: number): Frame
	local board = Instance.new("Frame")
	board.Name = "Board"
	board.AnchorPoint = Vector2.new(0.5, 0.5)
	board.Position = UDim2.fromScale(0.5, 0.5)
	board.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
	board.BackgroundColor3 = color
	board.BorderSizePixel = 0
	board.ZIndex = 1
	rounded(board, UDim.new(0, radius))
	Palette.candyGradient(board)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Rim"
	stroke.Color = WHITE
	stroke.Thickness = rim
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = board

	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.AnchorPoint = Vector2.new(0.5, 0)
	shine.Position = UDim2.new(0.5, 0, 0, rim)
	shine.Size = UDim2.new(1, -radius * 2, 0.3, 0)
	shine.BackgroundColor3 = WHITE
	shine.BackgroundTransparency = 0.78
	shine.BorderSizePixel = 0
	shine.ZIndex = 2
	rounded(shine, UDim.new(0, radius))
	shine.Parent = board

	board.Parent = gui
	return board
end

-- A filled circle centred in its parent; `scale` is its diameter as a fraction of the parent.
local function disc(parent: Instance, name: string, scale: number, color: Color3, zIndex: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(scale, scale)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = zIndex
	rounded(f, UDim.new(0.5, 0))
	f.Parent = parent
	return f
end

-- Billboards sized in studs shrink with distance like real objects, but never grow past their size at this many
-- studs (BillboardGui.DistanceLowerLimit): standing next to a station, its icon stays a small part of the screen
-- (first-session declutter, docs/plan/2026-11-16-first-session-design.md §A2).
local ICON_NEAR_STUDS = 14
local PREVIEW_NEAR_STUDS = 18

-- A round icon badge floating above a part (station icons): a white disc with a thick ink outline inside a candy
-- ring. Drawn as nested circles rather than UIStrokes, so the outline keeps its weight at any distance.
local function iconBadge(adornee: BasePart, name: string, icon: string, ring: Color3, studs: number, height: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = UDim2.fromScale(studs, studs)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 80
	gui.DistanceLowerLimit = ICON_NEAR_STUDS

	disc(gui, "Outline", 1, Palette.Outline, 1)
	disc(gui, "Ring", 0.86, ring, 2)
	local shine = disc(gui, "Shine", 0.08, WHITE, 3) -- a glossy dot on the ring, top left
	shine.Position = UDim2.fromScale(0.228, 0.228)
	shine.BackgroundTransparency = 0.2
	disc(gui, "Rim", 0.68, Palette.Outline, 3)
	disc(gui, "Disc", 0.6, WHITE, 4)
	local text = iconLabel(gui, "Icon", icon, UDim2.fromScale(0.42, 0.42), UDim2.fromScale(0.5, 0.5))
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.ZIndex = 5

	gui.Parent = adornee
	return gui
end

local function nightLight(p: BasePart, range: number)
	local light = Instance.new("PointLight")
	light.Color = COLORS.LampGlow
	light.Brightness = 1.4
	light.Range = range
	light.Shadows = false
	light.Enabled = false
	light.Parent = p
	CollectionService:AddTag(p, PlotBuilder.NIGHT_LIGHT_TAG)
end

------------------------------------------------------------------------------------------------------------------
-- Scenery pieces. `at` is a CFrame on the ground where the piece stands.
------------------------------------------------------------------------------------------------------------------

-- A round, layered toy tree: a trunk and four stacked balls. `blossom` makes it a pink blossom tree.
local function tree(parent: Instance, at: CFrame, scale: number, blossom: boolean?)
	local crown = if blossom then BLOSSOM else LEAVES
	local model = Instance.new("Model")
	model.Name = "Tree"
	cylinder(model, "Trunk", 6 * scale, 1.4 * scale, at * CFrame.new(0, 3 * scale, 0), COLORS.Trunk)
	soft(ball(model, "Leaves", 7 * scale, at * CFrame.new(0, 7 * scale, 0), crown[1]))
	soft(ball(model, "Leaves", 5.5 * scale, at * CFrame.new(1.8 * scale, 8.8 * scale, 0.6 * scale), crown[2]))
	soft(ball(model, "Leaves", 5 * scale, at * CFrame.new(-1.6 * scale, 8.4 * scale, -1 * scale), crown[3]))
	soft(ball(model, "Leaves", 4 * scale, at * CFrame.new(0.2 * scale, 10.6 * scale, -0.2 * scale), crown[4]))
	model.Parent = parent
end

local function bush(parent: Instance, at: CFrame, flower: Color3)
	local model = Instance.new("Model")
	model.Name = "Bush"
	soft(ball(model, "Leaves", 2.8, at * CFrame.new(0, 0.9, 0), COLORS.Bush))
	soft(ball(model, "Flower", 0.7, at * CFrame.new(0.6, 2.2, -0.4), flower))
	soft(ball(model, "Flower", 0.6, at * CFrame.new(-0.7, 2.0, 0.3), flower))
	soft(ball(model, "Flower", 0.6, at * CFrame.new(0.1, 2.25, 0.8), flower))
	model.Parent = parent
end

local function lamp(parent: Instance, at: CFrame, height: number)
	local model = Instance.new("Model")
	model.Name = "Lamp"
	cylinder(model, "Post", height, 0.5, at * CFrame.new(0, height / 2, 0), COLORS.LampPost)
	cylinder(model, "Cap", 0.3, 1.6, at * CFrame.new(0, height + 1.05, 0), COLORS.LampPost)
	local head = soft(ball(model, "Glow", 1.4, at * CFrame.new(0, height + 0.3, 0), COLORS.LampGlow))
	nightLight(head, 18)
	model.Parent = parent
end

local function bench(parent: Instance, at: CFrame)
	local model = Instance.new("Model")
	model.Name = "Bench"
	part(model, "Seat", Vector3.new(5, 0.4, 1.6), at * CFrame.new(0, 1.4, 0), COLORS.Bench)
	part(model, "Back", Vector3.new(5, 1.4, 0.3), at * CFrame.new(0, 2.3, 0.7), COLORS.Bench)
	part(model, "Leg", Vector3.new(0.4, 1.2, 1.4), at * CFrame.new(-2.1, 0.6, 0), WHITE)
	part(model, "Leg", Vector3.new(0.4, 1.2, 1.4), at * CFrame.new(2.1, 0.6, 0), WHITE)
	model.Parent = parent
end

-- Posts every <= 10 studs and two rails, from a to b (CFrames on the ground).
local function fenceLine(parent: Instance, a: CFrame, b: CFrame)
	local from, to = a.Position, b.Position
	local length = (to - from).Magnitude
	local segments = math.max(1, math.ceil(length / 10))
	for i = 0, segments do
		local p = from:Lerp(to, i / segments)
		part(parent, "FencePost", Vector3.new(0.8, 3, 0.8), a.Rotation + p + Vector3.new(0, 1.5, 0), COLORS.Fence)
	end
	local middle = (from + to) / 2
	for _, y in { 1.1, 2.3 } do
		local cf = CFrame.lookAt(middle + Vector3.new(0, y, 0), to + Vector3.new(0, y, 0))
		part(parent, "FenceRail", Vector3.new(0.3, 0.35, length), cf, COLORS.Fence)
	end
end

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
		soft(part(model, "Stripe", Vector3.new(4.25, 0.5, 0.1), base * CFrame.new(0, 2.2, -1.3), WHITE))
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

-- `floorTop` is the height of the floor it stands on in the model's own space (a room's FLOOR_TOP by default).
local function buildBed(model: Model, index: number, at: Vector3, style: RoomStyle, floorTop: number?)
	local base = CFrame.new(at.X, floorTop or FLOOR_TOP, at.Z)
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
		part(model, "BackWall", Vector3.new(w, 8.6, 0.6), CFrame.new(0, FLOOR_TOP + 4.3, back - 0.3), style.Wall)
		-- A white band low on the back wall (two-tone, like a sweet shop).
		soft(
			part(model, "WallBand", Vector3.new(w - 1.3, 1.1, 0.06), CFrame.new(0, FLOOR_TOP + 1.2, back - 0.63), WHITE)
		)
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
		-- edge so the stripes run down the front.
		local awning = { style.Main, WHITE }
		local depth = d * 0.45
		local stripes = 6
		local stripeWidth = (w + 1) / stripes
		for i = 1, stripes do
			local x = -(w + 1) / 2 + (i - 0.5) * stripeWidth
			local color = awning[(i % 2) + 1]
			local stripe = CFrame.new(x, FLOOR_TOP + 8.1, back - depth / 2) * CFrame.Angles(math.rad(-12), 0, 0)
			soft(part(model, "Awning", Vector3.new(stripeWidth, 0.35, depth + 0.6), stripe, color))
			local edge = stripe * Vector3.new(0, -0.175, -(depth + 0.6) / 2)
			soft(
				part(
					model,
					"AwningFlap",
					Vector3.new(stripeWidth, 0.8, 0.12),
					CFrame.new(edge - Vector3.new(0, 0.4, 0)),
					color
				)
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
	-- Three painted stripes across the floor, so it reads as seven two-tone bands.
	for i = -1, 1 do
		paint(
			part(
				model,
				"FloorStripe",
				Vector3.new(w - 0.4, 0.04, d / 7),
				CFrame.new(0, FLOOR_TOP + 0.03, i * d * 2 / 7),
				style.FloorStripe
			)
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

local function anchorAll(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
end

-- Kit models are cloned into Workspace, where a Script hidden inside (a free model's, say) would run. They're
-- scenery only, so every script is removed. They also keep the perf budget (docs/plan/2026-11-16-perf-budget.md):
-- no light casts shadows, and no Highlights (the world keeps at most one).
local function scrubScripts(model: Instance, source: string)
	local removed, highlights = 0, 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
			removed += 1
		elseif descendant:IsA("Highlight") then
			descendant:Destroy()
			highlights += 1
		elseif descendant:IsA("Light") then
			descendant.Shadows = false
		end
	end
	if removed > 0 then
		warn("[PlotBuilder] Removed " .. removed .. " script(s) from " .. source .. " (kit models are scenery only)")
	end
	if highlights > 0 then
		warn("[PlotBuilder] Removed " .. highlights .. " Highlight(s) from " .. source .. " (the perf budget)")
	end
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
	candyLabel(gui, "HeartCount", "", UDim2.fromScale(0.4, 0.28), UDim2.fromScale(0.07, 0.62), 3)
	local rank = Instance.new("TextLabel")
	rank.Name = "RankBadge"
	rank.BackgroundColor3 = WHITE
	rank.BackgroundTransparency = 0.05
	rank.Position = UDim2.fromScale(0.5, 0.6)
	rank.Size = UDim2.fromScale(0.43, 0.3)
	rank.Font = Palette.DisplayFont
	rank.TextColor3 = Palette.Ink
	rank.TextScaled = true
	rank.Text = ""
	rank.Visible = false
	rank.ZIndex = 3
	rounded(rank, UDim.new(0.5, 0))
	local rim = Instance.new("UIStroke")
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Color = Palette.Outline
	rim.Thickness = 3
	rim.Parent = rank
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.Parent = rank
	rank.Parent = gui
	gui.Parent = sign
end

local function buildFenceAndGate(scenery: Model, cf: CFrame, half: number, accent: Color3)
	local e = half - 0.4
	local gate = 5.6
	local function at(x: number, z: number): CFrame
		return cf * CFrame.new(x, 0, z)
	end
	fenceLine(scenery, at(-e, e), at(e, e))
	fenceLine(scenery, at(-e, -e), at(-e, e))
	fenceLine(scenery, at(e, -e), at(e, e))
	fenceLine(scenery, at(-e, -e), at(-gate - 0.6, -e))
	fenceLine(scenery, at(gate + 0.6, -e), at(e, -e))

	for _, x in { -gate - 0.6, gate + 0.6 } do
		part(scenery, "GatePost", Vector3.new(1.4, 6, 1.4), cf * CFrame.new(x, 3, -e), COLORS.Fence)
		local glow = soft(ball(scenery, "GateLamp", 1.2, cf * CFrame.new(x, 7.6, -e), COLORS.LampGlow))
		nightLight(glow, 16)
	end
	part(scenery, "GateArch", Vector3.new(gate * 2 + 2.6, 1, 1.6), cf * CFrame.new(0, 6.5, -e), accent)
	soft(part(scenery, "GateArchStripe", Vector3.new(gate * 2 + 2.7, 0.34, 1.7), cf * CFrame.new(0, 6.5, -e), WHITE))
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

	part(model, "Ground", Vector3.new(half * 2, 1, half * 2), cf * CFrame.new(0, -0.5, 0), COLORS.Lawn)
	-- Mowing stripes, running from the street to the back.
	for _, x in { -28, -14, 0, 14, 28 } do
		paint(
			part(
				scenery,
				"LawnStripe",
				Vector3.new(7, 0.04, half * 2 - 1),
				cf * CFrame.new(x, 0.02, 0),
				COLORS.LawnStripe
			)
		)
	end

	-- The front path from the gate to the counter (white edged), and candy stepping stones across the back yard.
	local pathLength = half - 15.6
	local pathZ = -(half + 15.6) / 2
	part(scenery, "Path", Vector3.new(9, 0.2, pathLength), cf * CFrame.new(0, 0.05, pathZ), COLORS.Path)
	for _, side in { -1, 1 } do
		paint(
			part(
				scenery,
				"PathEdge",
				Vector3.new(0.6, 0.24, pathLength),
				cf * CFrame.new(side * 4.8, 0.05, pathZ),
				WHITE
			)
		)
	end
	for i, z in { 3.5, 7.2, 10.9, 14.6 } do
		cylinder(scenery, "SteppingStone", 0.2, 2.8, cf * CFrame.new(math.sin(z) * 0.8, 0.05, z), STONES[i])
	end

	-- The counter: patients queue in front of it (toward the street), you treat from behind it.
	part(model, "Counter", Vector3.new(12, 3.4, 2.4), cf * CFrame.new(0, 1.7, -14.5), accent)
	soft(part(scenery, "CounterTop", Vector3.new(12.8, 0.4, 3), cf * CFrame.new(0, 3.6, -14.5), WHITE))
	soft(part(scenery, "CounterStripe", Vector3.new(12.2, 0.6, 0.1), cf * CFrame.new(0, 2.5, -15.72), WHITE))

	-- Markers. QueueStart and PatientSpawn face the counter; PatientExit faces the street.
	local turn = CFrame.Angles(0, math.pi, 0)
	marker(model, "QueueStart", cf * CFrame.new(0, 0.5, -18) * turn)
	marker(model, "PatientSpawn", cf * CFrame.new(-4, 0.5, -32.5) * turn)
	marker(model, "PatientExit", cf * CFrame.new(4, 0.5, -32.5))

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
	tree(scenery, cf * CFrame.new(16.5, 0, -9), 1.35)
	tree(scenery, cf * CFrame.new(-28, 0, -27), 1, true)
	tree(scenery, cf * CFrame.new(28.5, 0, -26), 1.1)
	tree(scenery, cf * CFrame.new(-29, 0, 29), 1.2)
	tree(scenery, cf * CFrame.new(29.5, 0, 29.5), 1, true)
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
	for i, at in bushes do
		bush(scenery, cf * CFrame.new(at), FLOWERS[(i + index) % #FLOWERS + 1])
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
-- The hospital building (depth update §3, build plan §B4/§B8; memory-20261116-008: the building grows)
------------------------------------------------------------------------------------------------------------------
-- Plot.Building is a Model that every plot always has (an empty one at Lv 1, the open-air Stand). From Lv 2 a block
-- stands right behind the Stand, so from the street the Stand becomes its front porch and the block rises over it:
--   the ward       the ground storey (Lv 2+): walls on three sides, open at its two front corners where the side
--                  walkways come in (patients walk to its beds that way), a back door onto the stepping stones.
--                  Its beds are the level's Beds - 1 (the Stand has the first): BedSpot_<n> Models, each holding the
--                  mattress Part Bed_<n> that Patients looks for. A bed is kept (not rebuilt) when the level changes,
--                  so a patient resting on one never notices
--   storeys        Lv 3+ stack on top (Floors - 1 of them, STOREY studs each). Windows, the ambulance's stripe
--                  and crosses and the helipad's H are drawn on the walls (SurfaceGuis, LightInfluence 0 for windows,
--                  so they glow at night), which keeps a Lv 5 plot with every room at 389 parts (the building 45;
--                  budget 400, decor not counted)
--   the roof       Lv 2: a candy gable · Lv 3+: flat, with a water tank (Lv 3-4), then the tower and helipad
--   the signs      a name board on the façade (the level's name); Lv 3-4 a big ✚ on the roof's front edge; Lv 5
--                  a neon ✚ on the tower (Neon and a shadowless light at night, like the lamps)
--   Lv 4           the ambulance bay on the front-left lawn (the line turns right, so it's clear of patients)
-- The block's footprint comes from the plot's own Slots (so a kit plot moves it): between the side rooms' walkways,
-- in front of the back rooms, behind the Stand. Nothing reaches the Counter, the line, the gate, the walkways, the
-- stations or a room slot, and everything above the ward's walls is soft (walk-through and ray-ignored), so the
-- camera never snaps against it. Each piece is a child Model with the attribute Since (the level that adds it); the
-- Building carries Level, GrewFrom and GrewAt (the GetServerTimeNow() of a level-up, else 0) so a client effect can
-- grow the new pieces in. ServerStorage.ClinicKit.Building<level> (pivot = the plot's ground-top centre, facing the
-- street, with its own Bed_<n> Parts) replaces the placeholder for that level.

local BUILDING_GAP = 1 -- studs between the Stand's back and the block's front wall
local BUILDING_DEPTH = 11 -- the block's depth when nothing behind it is closer
local WALKWAY_CLEAR = 2.5 -- kept free between the block and a room slot beside it (the side walkways)
local YARD_CLEAR = 5 -- kept free between the block and a room slot behind it
local WARD_HEIGHT = 12 -- the ground storey, at least (it grows so its sign shows over a taller kit Stand)
local SIGN_CLEAR = 2.5 -- the ward's façade shows this much above the Stand
local STOREY = 7
local WARD_OPEN = 5.5 -- the ward's sides are open this far back from its front wall (the walkways' way in)
local WARD_DOOR = 4 -- the back door's width (the stepping stones run through it)
local DOOR_HEIGHT = 7
local WARD_FLOOR_TOP = 0.05 -- the ward's painted floor, just above the lawn
local BED_INSET = 6.2 -- a ward bed's centre from the block's middle
local BED_BACK = 6.2 -- and behind the block's front wall
local WINDOW = 3.2 -- windows are this square (drawn on the walls)
local DETAIL_PIXELS = 12 -- SurfaceGui detail on walls: low resolution is plenty for flat candy shapes
local BAY_AT = Vector3.new(-26.8, 0, -16.5) -- the ambulance bay (plot-local), its nose to the street

type Footprint = { Half: number, Front: number, Back: number, Ground: number }
type BuildingStyle = { Accent: Color3, Wall: Color3, Glass: Color3, Floor: Color3, Board: Color3 }

local function buildingStyle(accent: Color3): BuildingStyle
	return {
		Accent = accent,
		Wall = lighten(accent, 0.78),
		Glass = lighten(WORLD.Water, 0.35),
		Floor = WORLD.Floor,
		Board = darken(accent, 0.12),
	}
end

-- Where the block goes, in plot-local studs (x from -Half to Half, z from Front to Back), and the ward's height.
local function footprint(plotModel: Model): Footprint
	local pivot = plotModel:GetPivot()
	local standHalf, standBack = 11, 1
	local slots = plotModel:FindFirstChild("Slots")
	local stand = slots and slots:FindFirstChild("RoomSlot_Stand")
	if stand and stand:IsA("BasePart") then
		local c = pivot:PointToObjectSpace(stand.CFrame.Position)
		standHalf = math.abs(c.X) + stand.Size.X / 2
		standBack = c.Z + stand.Size.Z / 2
	end
	local front = standBack + BUILDING_GAP
	local half = standHalf + 0.5
	local back = front + BUILDING_DEPTH
	if slots then
		for _, slot in slots:GetChildren() do
			if slot:IsA("BasePart") and slot ~= stand then
				local c = pivot:PointToObjectSpace(slot.CFrame.Position)
				local inner = math.abs(c.X) - slot.Size.X / 2
				local slotFront, slotBack = c.Z - slot.Size.Z / 2, c.Z + slot.Size.Z / 2
				if slotFront >= front then
					if inner < half then
						back = math.min(back, slotFront - YARD_CLEAR) -- a room behind: leave its yard
					end
				elseif slotBack > front and inner > 0 then
					half = math.min(half, inner - WALKWAY_CLEAR) -- a room beside: leave its walkway
				end
			end
		end
	end
	half = math.max(half, 7)
	back = math.max(back, front + 8)

	local standTop = 9.5
	local rooms = plotModel:FindFirstChild("Rooms")
	local standRoom = rooms and rooms:FindFirstChild("Room_Stand")
	if standRoom and standRoom:IsA("Model") then
		local box, size = standRoom:GetBoundingBox()
		standTop = pivot:PointToObjectSpace(box.Position).Y + size.Y / 2
	end
	return { Half = half, Front = front, Back = back, Ground = math.max(WARD_HEIGHT, standTop + SIGN_CLEAR) }
end

local function wedge(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.Size = size
	w.CFrame = cframe
	w.Color = color
	w.Material = Enum.Material.SmoothPlastic
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Parent = parent
	return w
end

-- A thin part that glows at night like the lamps (Neon only after dark), with no light of its own.
local function nightGlow(p: BasePart): BasePart
	CollectionService:AddTag(p, PlotBuilder.NIGHT_LIGHT_TAG)
	return p
end

-- A disc standing upright and facing the street (Roblox cylinders run along X, so turn it to face -Z).
local function upright(parent: Instance, name: string, diameter: number, thick: number, at: CFrame, color: Color3)
	local p = part(parent, name, Vector3.new(thick, diameter, diameter), at * CFrame.Angles(0, math.rad(90), 0), color)
	p.Shape = Enum.PartType.Cylinder
	return soft(p)
end

-- A SurfaceGui on one face of a part, sized in studs (flat details drawn on a wall cost no parts).
local function faceGui(p: BasePart, name: string, face: Enum.NormalId, lightInfluence: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = DETAIL_PIXELS
	gui.LightInfluence = lightInfluence
	gui.MaxDistance = 400
	gui.Parent = p
	return gui
end

-- Windows drawn on a wall's face: cols x rows rounded panes in white frames, each WINDOW studs square (smaller if
-- the face is crowded). LightInfluence 0 keeps them bright, so after dark they glow against the darkened walls.
-- skipTopMiddle leaves the top row's middle window out (a sign hangs there).
local function windowGui(
	p: BasePart,
	face: Enum.NormalId,
	cols: number,
	rows: number,
	glass: Color3,
	skipTopMiddle: boolean?
)
	local sideways = face == Enum.NormalId.Left or face == Enum.NormalId.Right
	local width = if sideways then p.Size.Z else p.Size.X
	local gui = faceGui(p, "Windows" .. face.Name, face, 0)
	local w, h = math.min(WINDOW / width, 0.85 / cols), math.min(WINDOW / p.Size.Y, 0.8 / rows)
	local middle = (cols + 1) / 2
	for row = 1, rows do
		for col = 1, cols do
			if not (skipTopMiddle and row == 1 and col == middle) then
				local glassPane = Instance.new("Frame")
				glassPane.Name = "Window"
				glassPane.AnchorPoint = Vector2.new(0.5, 0.5)
				glassPane.Position = UDim2.fromScale((col - 0.5) / cols, (row - 0.5) / rows)
				glassPane.Size = UDim2.fromScale(w, h)
				glassPane.BackgroundColor3 = glass
				glassPane.BorderSizePixel = 0
				rounded(glassPane, UDim.new(0.2, 0))
				local frame = Instance.new("UIStroke")
				frame.Color = WHITE
				frame.Thickness = 3
				frame.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				frame.Parent = glassPane
				glassPane.Parent = gui
			end
		end
	end
end

-- A flat rectangle on a face (scale units): stripes, crosses, a windscreen.
local function decal(gui: SurfaceGui, name: string, size: UDim2, position: UDim2, color: Color3, corner: number?)
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = position
	f.Size = size
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	if corner then
		rounded(f, UDim.new(corner, 0))
	end
	f.Parent = gui
end

local function piece(parent: Instance, name: string, since: number): Model
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("Since", since)
	model.Parent = parent
	return model
end

-- A name board (a glossy candy board with the level's name in white outlined text), centred at `at`.
local function nameBoard(parent: Instance, at: CFrame, width: number, text: string, style: BuildingStyle)
	local board = soft(part(parent, "NameBoard", Vector3.new(width, 1.8, 0.3), at, style.Board))
	local gui = Instance.new("SurfaceGui")
	gui.Name = "NameGui"
	gui.Face = Enum.NormalId.Front -- the street side
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0 -- readable at night
	gui.MaxDistance = 220
	candyBoard(gui, style.Accent, 3, 12, 3)
	candyLabel(gui, "Name", text, UDim2.fromScale(0.92, 0.74), UDim2.fromScale(0.04, 0.13), 3)
	gui.Parent = board
end

-- The ✚: a WHITE cross on a disc in the plot's accent colour, in a white rim, facing the street from `at` (its
-- centre). Never a red cross on white: that's the Red Cross emblem, a protected symbol games may not use
-- (docs/guides/build-the-clinic.md, Rules); the plot accents (Palette.PlotColors) are never red. A neon one glows at
-- night: the rim and cross turn Neon and the disc lights up (a shadowless PointLight, like the lamps).
local function crossSign(parent: Instance, at: CFrame, diameter: number, accent: Color3, neon: boolean)
	local rim = upright(parent, "SignRim", diameter + 0.7, 0.5, at, WHITE)
	local face = upright(parent, "SignDisc", diameter, 0.5, at * CFrame.new(0, 0, -0.12), accent)
	local long, short = diameter * 0.64, diameter * 0.22
	local bars = {
		soft(part(parent, "Cross", Vector3.new(long, short, 0.3), at * CFrame.new(0, 0, -0.45), WHITE)),
		soft(part(parent, "Cross", Vector3.new(short, long, 0.3), at * CFrame.new(0, 0, -0.45), WHITE)),
	}
	if neon then
		nightGlow(rim)
		for _, bar in bars do
			nightGlow(bar)
		end
		nightLight(face, 24)
	end
end

local function buildWard(model: Model, f: Footprint, style: BuildingStyle)
	local ward = piece(model, "Ward", 2)
	local half, front, back, g = f.Half, f.Front, f.Back, f.Ground
	local w, d = half * 2, back - front
	local cz = (front + back) / 2
	paint(part(ward, "WardFloor", Vector3.new(w - 0.6, 0.04, d - 0.6), CFrame.new(0, 0.03, cz), style.Floor))
	part(ward, "FrontWall", Vector3.new(w, g, 0.6), CFrame.new(0, g / 2, front + 0.3), style.Wall)

	-- The back wall, with a door onto the stepping stones and a window either side.
	local segment = (w - WARD_DOOR) / 2
	for _, side in { -1, 1 } do
		local x = side * (WARD_DOOR / 2 + segment / 2)
		local wall = part(ward, "BackWall", Vector3.new(segment, g, 0.6), CFrame.new(x, g / 2, back - 0.3), style.Wall)
		windowGui(wall, Enum.NormalId.Back, 1, 1, style.Glass)
	end
	part(
		ward,
		"DoorTop",
		Vector3.new(WARD_DOOR + 0.2, g - DOOR_HEIGHT, 0.6),
		CFrame.new(0, (g + DOOR_HEIGHT) / 2, back - 0.3),
		style.Wall
	)

	-- The sides: open at the front (the walkways' way in, up to the ceiling), walled behind, with a window.
	local openTo = front + WARD_OPEN
	local wallLength = back - openTo
	for _, side in { -1, 1 } do
		local x = side * (half - 0.3)
		local wall = part(
			ward,
			"SideWall",
			Vector3.new(0.6, g, wallLength),
			CFrame.new(x, g / 2, openTo + wallLength / 2),
			style.Wall
		)
		windowGui(wall, if side < 0 then Enum.NormalId.Left else Enum.NormalId.Right, 1, 1, style.Glass)
	end

	-- The ceiling and the candy trim round it (soft: the camera passes through).
	soft(part(ward, "Ledge", Vector3.new(w + 0.8, 0.6, d + 0.8), CFrame.new(0, g, cz), style.Accent))
end

local function buildStorey(model: Model, f: Footprint, style: BuildingStyle, index: number)
	local storey = piece(model, "Storey_" .. index, index + 2)
	local half, front, back = f.Half, f.Front, f.Back
	local base = f.Ground + (index - 1) * STOREY
	local cz = (front + back) / 2
	local color = if index % 2 == 1 then WHITE else style.Wall -- white and pastel layers, like a cake
	local block = soft(
		part(storey, "Block", Vector3.new(half * 2, STOREY, back - front), CFrame.new(0, base + STOREY / 2, cz), color)
	)
	-- Windows on the three sides you can see from the street (one every ~7 studs across, ~5.5 deep).
	local across = math.max(1, math.floor(half * 2 / 7))
	local deep = math.max(1, math.floor((back - front) / 5.5))
	windowGui(block, Enum.NormalId.Front, across, 1, style.Glass)
	windowGui(block, Enum.NormalId.Left, deep, 1, style.Glass)
	windowGui(block, Enum.NormalId.Right, deep, 1, style.Glass)
	if index > 1 then
		soft(
			part(
				storey,
				"Ledge",
				Vector3.new(half * 2 + 0.8, 0.6, back - front + 0.8),
				CFrame.new(0, base, cz),
				style.Accent
			)
		)
	end
end

-- Lv 2: a candy gable over the ward (ridge running across, so its front slope faces the street).
local function buildGable(model: Model, f: Footprint, style: BuildingStyle, top: number)
	local roof = piece(model, "Roof", 2)
	local w = f.Half * 2 + 1.2
	local front, back = f.Front - 0.6, f.Back + 0.6
	local roofHalf = (back - front) / 2
	local centre = (front + back) / 2
	local rise = 3.6
	local angle = math.atan2(rise, roofHalf)
	local length = math.sqrt(roofHalf * roofHalf + rise * rise) + 0.3
	local base = top + 0.3
	for _, side in { -1, 1 } do -- -1 = the front slope, rising toward the back
		local slope = CFrame.new(0, base + rise / 2, centre + side * roofHalf / 2) * CFrame.Angles(side * angle, 0, 0)
		soft(part(roof, "RoofSlope", Vector3.new(w, 0.5, length), slope, style.Accent))
		-- A white stripe across each slope, like the Stand's awning.
		soft(part(roof, "RoofStripe", Vector3.new(w + 0.04, 0.54, 1.2), slope, WHITE))
	end
	for _, xSide in { -1, 1 } do
		local x = xSide * (f.Half - 0.2)
		-- The gable ends: a WedgePart rises toward its +Z, so the back half is turned round.
		soft(
			wedge(
				roof,
				"Gable",
				Vector3.new(0.4, rise, roofHalf),
				CFrame.new(x, base + rise / 2, centre - roofHalf / 2),
				style.Wall
			)
		)
		soft(
			wedge(
				roof,
				"Gable",
				Vector3.new(0.4, rise, roofHalf),
				CFrame.new(x, base + rise / 2, centre + roofHalf / 2) * CFrame.Angles(0, math.pi, 0),
				style.Wall
			)
		)
	end
	local ridge = soft(part(roof, "Ridge", Vector3.new(w + 0.3, 0.8, 0.8), CFrame.new(0, base + rise, centre), WHITE))
	ridge.Shape = Enum.PartType.Cylinder
end

-- Lv 3+: a flat roof with a lip, and a water tank until the tower and helipad take the space (Lv 5).
local function buildFlatRoof(model: Model, f: Footprint, style: BuildingStyle, top: number, level: number)
	local roof = piece(model, "Roof", level)
	local half, front, back = f.Half, f.Front, f.Back
	local cz = (front + back) / 2
	soft(
		part(
			roof,
			"RoofCap",
			Vector3.new(half * 2 + 0.8, 0.6, back - front + 0.8),
			CFrame.new(0, top, cz),
			style.Accent
		)
	)
	if level < 5 then
		local at = CFrame.new(half - 3, top + 0.3, back - 3)
		soft(part(roof, "TankStand", Vector3.new(2.4, 1.2, 2.4), at * CFrame.new(0, 0.6, 0), WHITE))
		soft(cylinder(roof, "Tank", 2.6, 3, at * CFrame.new(0, 2.5, 0), style.Accent))
		soft(ball(roof, "TankTop", 1.2, at * CFrame.new(0, 3.9, 0), WHITE))
	end
end

-- Lv 5: a two-storey tower on the roof's left, its neon ✚ facing the street and a beacon on top.
local function buildTower(model: Model, f: Footprint, style: BuildingStyle, top: number)
	local tower = piece(model, "Tower", 5)
	local x0, x1 = -f.Half + 1, -f.Half + 9
	local z0 = f.Front + 2
	local z1 = math.min(z0 + 8, f.Back - 1)
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local base = top + 0.3
	local height = STOREY * 2
	local block = soft(
		part(tower, "TowerBlock", Vector3.new(x1 - x0, height, z1 - z0), CFrame.new(cx, base + height / 2, cz), WHITE)
	)
	windowGui(block, Enum.NormalId.Front, 1, 2, style.Glass, true) -- the neon ✚ takes the top front window
	windowGui(block, Enum.NormalId.Left, 1, 2, style.Glass)
	windowGui(block, Enum.NormalId.Right, 1, 2, style.Glass)
	soft(
		part(
			tower,
			"TowerLedge",
			Vector3.new(x1 - x0 + 0.8, 0.6, z1 - z0 + 0.8),
			CFrame.new(cx, base + STOREY, cz),
			style.Accent
		)
	)
	soft(
		part(
			tower,
			"TowerCap",
			Vector3.new(x1 - x0 + 1, 0.8, z1 - z0 + 1),
			CFrame.new(cx, base + height, cz),
			style.Accent
		)
	)
	crossSign(tower, CFrame.new(cx, base + STOREY + 3.5, z0 - 0.4), 4.8, style.Accent, true)
	-- A beacon on the roof, glowing red at night.
	nightGlow(soft(ball(tower, "Beacon", 1.4, CFrame.new(cx, base + height + 1.1, cz), CANDY.Red)))
end

-- Lv 5: the helipad on the roof beside the tower: a yellow ring, a dark pad and a white H, all drawn on one flat
-- see-through part (a SurfaceGui on its top).
local function buildHelipad(model: Model, f: Footprint, top: number)
	local pad = piece(model, "Helipad", 5)
	local left = -f.Half + 10 -- the tower's right side, plus a step
	local cx, cz = (left + f.Half) / 2, (f.Front + f.Back) / 2
	local diameter = math.min(f.Half - left, f.Back - f.Front) - 1.5
	local surface = paint(part(pad, "Pad", Vector3.new(diameter, 0.1, diameter), CFrame.new(cx, top + 0.36, cz), WHITE))
	surface.Transparency = 1
	local gui = faceGui(surface, "PadGui", Enum.NormalId.Top, 1)
	disc(gui, "Ring", 1, CANDY.Yellow, 1)
	disc(gui, "Inner", 0.86, WORLD.Street, 2)
	local letter = candyLabel(gui, "H", "H", UDim2.fromScale(0.44, 0.44), UDim2.fromScale(0.28, 0.28), 5)
	letter.ZIndex = 3
end

-- Lv 4: the ambulance bay, a painted bay with a toy ambulance parked nose to the street. Its stripe, its badges (a
-- white cross on the plot's accent colour, never a red cross on white: see crossSign) and windscreen are drawn on
-- its sides (SurfaceGuis), so it stays a handful of parts.
local function buildAmbulanceBay(model: Model, style: BuildingStyle)
	local bay = piece(model, "AmbulanceBay", 4)
	local at = CFrame.new(BAY_AT)
	paint(part(bay, "BayFloor", Vector3.new(7.4, 0.06, 13), at * CFrame.new(0, 0.04, 0), lighten(WORLD.Street, 0.5)))
	local van = Instance.new("Model")
	van.Name = "Ambulance"
	local lift = 0.7 -- the wheels' radius: the body sits on them
	local body = part(van, "Body", Vector3.new(4.6, 3.8, 7), at * CFrame.new(0, lift + 1.9, 1.3), WHITE)
	local cab = part(van, "Cab", Vector3.new(4.6, 2.6, 2.6), at * CFrame.new(0, lift + 1.3, -3.5), WHITE)
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		-- Body sides are 7 wide and 3.8 tall: a red band low down and, above it, a square accent badge (2.1 x 2)
		-- with a white ✚ on it.
		local side = faceGui(body, "Side" .. face.Name, face, 1)
		decal(side, "Stripe", UDim2.fromScale(1, 0.18), UDim2.fromScale(0.5, 0.66), CANDY.Red)
		decal(side, "Badge", UDim2.fromScale(0.3, 0.52), UDim2.fromScale(0.5, 0.3), style.Accent, 0.2)
		decal(side, "CrossUp", UDim2.fromScale(0.08, 0.42), UDim2.fromScale(0.5, 0.3), WHITE)
		decal(side, "CrossAcross", UDim2.fromScale(0.23, 0.15), UDim2.fromScale(0.5, 0.3), WHITE)
		for _, name in { "CrossUp", "CrossAcross" } do
			local bar = side:FindFirstChild(name)
			if bar and bar:IsA("GuiObject") then
				bar.ZIndex = 2 -- over the badge
			end
		end
	end
	local front = faceGui(cab, "Windscreen", Enum.NormalId.Front, 1)
	decal(front, "Glass", UDim2.fromScale(0.86, 0.42), UDim2.fromScale(0.5, 0.3), style.Glass, 0.25)
	decal(front, "Stripe", UDim2.fromScale(1, 0.14), UDim2.fromScale(0.5, 0.72), CANDY.Red)
	for i, color in { CANDY.Red, CANDY.Blue } do
		nightGlow(
			soft(
				part(van, "Siren", Vector3.new(1.2, 0.5, 0.9), at * CFrame.new(i * 1.4 - 2.1, lift + 2.85, -3.5), color)
			)
		)
	end
	for _, x in { -2.15, 2.15 } do
		for _, z in { -3.2, 3 } do
			local wheel =
				soft(part(van, "Wheel", Vector3.new(0.7, lift * 2, lift * 2), at * CFrame.new(x, lift, z), Palette.Ink))
			wheel.Shape = Enum.PartType.Cylinder
		end
	end
	van.Parent = bay
end

-- A ward bed: a BedSpot_<n> Model round the mattress Part Bed_<n>.
local function wardBed(model: Model, f: Footprint, index: number, accent: Color3)
	local spot = piece(model, "BedSpot_" .. index, if index == 1 then 2 else 4)
	local side = if index % 2 == 1 then -1 else 1
	local x = side * math.min(BED_INSET, f.Half - 3)
	local z = math.min(f.Front + BED_BACK, f.Back - 4.4)
	buildBed(spot, index, Vector3.new(x, 0, z), styleFor("Stand", accent), WARD_FLOOR_TOP)
end

local function extraBeds(level: number): number
	local row = LevelsData[level]
	return if row then math.max(0, row.Beds - 1) else 0
end

local function kitBuilding(level: number): Model?
	local kit = ServerStorage:FindFirstChild("ClinicKit")
	local template = kit and kit:FindFirstChild("Building" .. level)
	if not (template and template:IsA("Model")) then
		return nil
	end
	local model = template:Clone()
	scrubScripts(model, "ClinicKit.Building" .. level)
	anchorAll(model)
	local beds = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and string.match(descendant.Name, "^Bed_%d+$") then
			beds += 1
		end
	end
	if beds < extraBeds(level) then
		warn("[PlotBuilder] ClinicKit.Building" .. level .. " needs " .. extraBeds(level) .. " Bed_<n> Parts")
	end
	return model
end

-- Builds the shell in plot-local space (the plot's ground-top centre at the origin, -Z to the street). Beds whose
-- index is in `keep` are left out: the old ones move across.
local function placeholderBuilding(plotModel: Model, level: number, keep: { [number]: boolean }): Model
	local model = Instance.new("Model")
	local row = LevelsData[level]
	if row and row.Floors > 0 then
		local accent = plotAccent(plotModel) or CANDY.Pink
		local style = buildingStyle(accent)
		local f = footprint(plotModel)
		local upper = row.Floors - 1
		local top = f.Ground + upper * STOREY
		buildWard(model, f, style)
		for index = 1, upper do
			buildStorey(model, f, style, index)
		end
		local sign = piece(model, "Sign", level)
		if upper == 0 then
			buildGable(model, f, style, top)
			-- The Clinic's name on the ward's façade, above the Stand.
			nameBoard(sign, CFrame.new(0, f.Ground - 1.4, f.Front - 0.16), math.min(f.Half, 9), row.Name, style)
		else
			buildFlatRoof(model, f, style, top, level)
			nameBoard(sign, CFrame.new(0, top - 1.15, f.Front - 0.16), math.min(f.Half * 1.1, 13), row.Name, style)
			if level < 5 then
				crossSign(sign, CFrame.new(0, top + 3.95, f.Front + 1), 6, accent, false)
			else
				buildTower(model, f, style, top)
				buildHelipad(model, f, top)
			end
		end
		if level >= 4 then
			buildAmbulanceBay(model, style)
		end
		for index = 1, extraBeds(level) do
			if not keep[index] then
				wardBed(model, f, index, accent)
			end
		end
	end
	model.WorldPivot = CFrame.identity
	model:PivotTo(plotModel:GetPivot())
	return model
end

function PlotBuilder.buildBuilding(plotModel: Model, level: number, grewFrom: number?): Model
	local row = LevelsData[level]
	local lv = if row then level else 1
	local old = plotModel:FindFirstChild("Building")
	local model = kitBuilding(lv)
	if model then
		model:PivotTo(plotModel:GetPivot())
	else
		-- Keep the beds that stay (a patient may be resting on one): same index, same spot.
		local keep: { [number]: boolean } = {}
		if old then
			for index = 1, extraBeds(lv) do
				if old:FindFirstChild("BedSpot_" .. index) then
					keep[index] = true
				end
			end
		end
		model = placeholderBuilding(plotModel, lv, keep)
		for index in keep do
			local spot = (old :: Instance):FindFirstChild("BedSpot_" .. index)
			if spot then
				spot.Parent = model
			end
		end
	end
	local building = model :: Model
	building.Name = "Building"
	building.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	building:SetAttribute("Level", lv)
	local from = if type(grewFrom) == "number" then grewFrom else lv
	building:SetAttribute("GrewFrom", from)
	building:SetAttribute("GrewAt", if from < lv then Workspace:GetServerTimeNow() else 0)
	if old then
		old:Destroy()
	end
	building.Parent = plotModel
	plotModel:SetAttribute("Level", lv)
	return building
end

------------------------------------------------------------------------------------------------------------------
-- The town
------------------------------------------------------------------------------------------------------------------

local function buildTownScenery(count: number): Model
	local origin = Config.Town.Origin
	local size = Config.Town.PlotSize
	local perRow = math.ceil(count / 2)
	local width = perRow * (size + PLOT_GAP) + 40
	local depth = 2 * (STREET_HALF_WIDTH + size) + 40
	local h = STREET_HALF_WIDTH
	local ground = CFrame.new(origin + Vector3.new(0, BASE_TOP, 0))

	local town = Instance.new("Model")
	town.Name = "ClinicTown"

	part(town, "TownLawn", Vector3.new(width, 2, depth), ground * CFrame.new(0, -1, 0), COLORS.TownLawn)
	part(town, "Street", Vector3.new(width, 0.2, h * 2), ground * CFrame.new(0, 0.1, 0), COLORS.Street)
	for _, side in { -1, 1 } do
		part(town, "Curb", Vector3.new(width, 0.4, 0.8), ground * CFrame.new(0, 0.2, side * (h - 0.4)), COLORS.Curb)
	end
	-- The plaza: a candy-pink ring round a cream disc.
	local plazaRadius = h - 1
	cylinder(town, "Plaza", 0.2, plazaRadius * 2, ground * CFrame.new(0, 0.3, 0), COLORS.PlazaRing)
	cylinder(town, "PlazaInner", 0.25, plazaRadius * 2 - 4, ground * CFrame.new(0, 0.325, 0), COLORS.Plaza)

	-- Road paint: a white zebra crossing in front of each pair of facing gates (the middle pair opens onto the
	-- plaza), and white dashes down the middle of the street.
	local crossings: { number } = {}
	for column = 1, perRow do
		local x = (column - (perRow + 1) / 2) * (size + PLOT_GAP)
		if math.abs(x) > plazaRadius + 4 then
			table.insert(crossings, x)
			for z = -(h - 4), h - 4, 4 do
				paint(
					part(town, "Crossing", Vector3.new(8, 0.05, 2), ground * CFrame.new(x, 0.235, z), COLORS.StreetLine)
				)
			end
		end
	end
	local function nearCrossing(x: number): boolean
		for _, crossingX in crossings do
			if math.abs(x - crossingX) < 7 then
				return true
			end
		end
		return false
	end
	for _, side in { -1, 1 } do
		local x = plazaRadius + 4
		while x < width / 2 - 3 do
			if not nearCrossing(side * x) then
				paint(
					part(
						town,
						"RoadLine",
						Vector3.new(4, 0.05, 0.6),
						ground * CFrame.new(side * x, 0.235, 0),
						COLORS.StreetLine
					)
				)
			end
			x += 8
		end
	end

	-- Plaza: round candy planters with little trees at the corners, benches facing the spawn.
	for i, corner in { Vector2.new(1, 1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(-1, -1) } do
		local at = ground * CFrame.new(corner.X * 10.5, 0.4, corner.Y * 10.5)
		cylinder(town, "Planter", 1.2, 4, at * CFrame.new(0, 0.6, 0), PLANTERS[i])
		soft(cylinder(town, "PlanterGrass", 0.1, 3.4, at * CFrame.new(0, 1.22, 0), COLORS.Lawn))
		tree(town, at * CFrame.new(0, 1.2, 0), 0.55, i % 2 == 0)
	end
	for _, side in { -1, 1 } do
		local at = ground * CFrame.new(side * 15, 0.4, 0)
		bench(town, CFrame.lookAt(at.Position, ground.Position + Vector3.new(0, 0.4, 0))) -- sits facing the spawn
		lamp(town, ground * CFrame.new(side * 15, 0.4, 4.5), 8)
	end

	-- Street lamps between the plots, and trees in the gaps between plots.
	for column = 0, perRow do
		local x = (column - perRow / 2) * (size + PLOT_GAP)
		for _, side in { -1, 1 } do
			if math.abs(x) > 1 then
				lamp(town, ground * CFrame.new(x, 0.4, side * (h - 1.6)), 8)
			end
			tree(town, ground * CFrame.new(x, 0, side * (h + size / 2)), 1.1, column % 2 == 0)
		end
	end

	-- Welcome arches at both ends of the street (the clinic's motto, design §5.1): white posts with candy balls on
	-- top and a glossy pink board.
	for _, side in { -1, 1 } do
		local x = side * (width / 2 - 5)
		for _, zSide in { -1, 1 } do
			part(town, "ArchPost", Vector3.new(1.6, 12, 1.6), ground * CFrame.new(x, 6, zSide * (h - 2)), WHITE)
			soft(ball(town, "ArchCap", 1.8, ground * CFrame.new(x, 14.9, zSide * (h - 2)), CANDY.Yellow))
		end
		local beam = part(
			town,
			"ArchBeam",
			Vector3.new(1.4, 3.4, h * 2 - 2),
			ground * CFrame.new(x, 12.4, 0),
			darken(CANDY.Pink, 0.15)
		)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "WelcomeGui"
		gui.Face = if side < 0 then Enum.NormalId.Right else Enum.NormalId.Left -- faces the town centre
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		candyBoard(gui, CANDY.Pink, 6, 16, 4)
		candyLabel(
			gui,
			"Motto",
			"Everyone welcome. Even the weird ones.",
			UDim2.fromScale(0.94, 0.7),
			UDim2.fromScale(0.03, 0.15),
			4
		)
		gui.Parent = beam
	end

	return town
end

local function townSpawn(): SpawnLocation
	local existing = Workspace:FindFirstChild("TownSpawn")
	if existing and existing:IsA("SpawnLocation") then
		return existing -- the brother placed one: keep it
	end
	local origin = Config.Town.Origin
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "TownSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(origin + Vector3.new(0, BASE_TOP, 0))
	spawn.Color = COLORS.Spawn
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.Duration = 0 -- no force field bubble
	spawn.Parent = Workspace
	return spawn
end

local function applyNight(instance: Instance, isNight: boolean)
	if not instance:IsA("BasePart") then
		return
	end
	instance.Material = if isNight then Enum.Material.Neon else Enum.Material.SmoothPlastic
	for _, child in instance:GetChildren() do
		if child:IsA("Light") then
			child.Enabled = isNight
		end
	end
end

local nightWired = false
local function wireNightLights()
	if nightWired then
		return
	end
	nightWired = true
	local function refresh()
		local isNight = Workspace:GetAttribute("IsNight") == true
		for _, instance in CollectionService:GetTagged(PlotBuilder.NIGHT_LIGHT_TAG) do
			applyNight(instance, isNight)
		end
	end
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(refresh)
	CollectionService:GetInstanceAddedSignal(PlotBuilder.NIGHT_LIGHT_TAG):Connect(function(instance)
		applyNight(instance, Workspace:GetAttribute("IsNight") == true)
	end)
	refresh()
end

function PlotBuilder.buildTown(): { Model }
	local count = math.clamp(Config.Town.Plots, 1, MAX_PLOTS)
	for _, name in { "Clinics", "ClinicTown" } do
		local old = Workspace:FindFirstChild(name)
		if old then
			warn("[PlotBuilder] Replacing an existing Workspace." .. name)
			old:Destroy()
		end
	end

	local town = buildTownScenery(count)
	town.Parent = Workspace
	townSpawn()

	local clinics = Instance.new("Folder")
	clinics.Name = "Clinics"
	local models = {}
	for index = 1, count do
		local cf = plotCFrame(index, count)
		local model = kitPlot(index, cf) or buildPlaceholderPlot(index, cf)
		model.WorldPivot = cf
		buildQueueLane(model, plotAccentFor(index))
		model:SetAttribute("PlotIndex", index)
		model:SetAttribute("OwnerUserId", 0)
		model:SetAttribute("OpenHelpers", false)
		model:SetAttribute("Hearts", 0)
		model.Parent = clinics
		PlotBuilder.placeRoom(model, "Stand")
		PlotBuilder.buildBuilding(model, 1) -- Lv 1's (empty) Building; Server/Levels grows it for the owner
		models[index] = model
	end
	clinics.Parent = Workspace

	wireNightLights()
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
