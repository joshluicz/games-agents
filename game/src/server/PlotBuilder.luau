--!strict
-- Builds the town and its clinic plots (build plan §B1). Server only.
--   PlotBuilder.buildTown(): { Model }            Workspace.Clinics.Plot_1..N, the town around them, TownSpawn
--   PlotBuilder.buildRoom(roomId): Model           an unplaced room (kit clone or placeholder), PrimaryPart = Floor
--   PlotBuilder.clearPlot(plotModel)               removes patients, decor and every room except the Stand
-- Extra helpers (Plots uses them):
--   PlotBuilder.placeRoom(plotModel, roomId): Model?      build + place in its slot (Floor.CFrame == slot CFrame)
--   PlotBuilder.setPreview(plotModel, slotId, roomId?)    the "for sale" outline in an empty slot (nil = none)
--   PlotBuilder.NIGHT_LIGHT_TAG                            tag a lamp Part: Neon + PointLight on only at night
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

local function buildBed(model: Model, index: number, at: Vector3, style: RoomStyle)
	local base = CFrame.new(at.X, FLOOR_TOP, at.Z)
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
-- scenery only, so every script is removed.
local function scrubScripts(model: Instance, source: string)
	local removed = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
			removed += 1
		end
	end
	if removed > 0 then
		warn("[PlotBuilder] Removed " .. removed .. " script(s) from " .. source .. " (kit models are scenery only)")
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

-- The clinic sign: a glossy board in the plot's accent inside an accent frame, white posts, and the owner's name in
-- white outlined display text. OwnerName and HeartCount stay direct children of SignGui (Plots and Visits set them).
local function buildSign(model: Model, scenery: Model, cf: CFrame, accent: Color3)
	local sign = part(model, "Sign", Vector3.new(9, 3.4, 0.5), cf * CFrame.new(-13, 3.4, -33.6), darken(accent, 0.15))
	soft(part(scenery, "SignTrim", Vector3.new(9.8, 4.2, 0.4), cf * CFrame.new(-13, 3.4, -33.2), accent))
	for _, x in { -17.2, -8.8 } do
		part(scenery, "SignPost", Vector3.new(0.7, 5.6, 0.7), cf * CFrame.new(x, 2.8, -33.2), WHITE)
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
	candyLabel(gui, "HeartCount", "", UDim2.fromScale(0.86, 0.28), UDim2.fromScale(0.07, 0.62), 3)
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
		model:SetAttribute("PlotIndex", index)
		model:SetAttribute("OwnerUserId", 0)
		model:SetAttribute("OpenHelpers", false)
		model:SetAttribute("Hearts", 0)
		model.Parent = clinics
		PlotBuilder.placeRoom(model, "Stand")
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
end

return PlotBuilder
