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

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
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

-- Cozy, bright, not oversaturated (design §6).
local COLORS = {
	TownLawn = Color3.fromRGB(122, 190, 98),
	Lawn = Color3.fromRGB(140, 206, 112),
	Street = Color3.fromRGB(240, 224, 190),
	Curb = Color3.fromRGB(216, 202, 178),
	Plaza = Color3.fromRGB(248, 216, 198),
	Spawn = Color3.fromRGB(255, 248, 236),
	Path = Color3.fromRGB(242, 222, 178),
	Stone = Color3.fromRGB(228, 222, 212),
	Fence = Color3.fromRGB(255, 250, 240),
	Wood = Color3.fromRGB(206, 152, 106),
	WoodDark = Color3.fromRGB(160, 112, 76),
	Board = Color3.fromRGB(255, 244, 222),
	Trunk = Color3.fromRGB(150, 104, 72),
	Leaf1 = Color3.fromRGB(120, 190, 92),
	Leaf2 = Color3.fromRGB(104, 176, 84),
	Leaf3 = Color3.fromRGB(146, 208, 110),
	Bush = Color3.fromRGB(98, 170, 84),
	LampPost = Color3.fromRGB(86, 112, 104),
	LampGlow = Color3.fromRGB(255, 232, 176),
	Ink = Color3.fromRGB(74, 52, 42),
	White = Color3.fromRGB(255, 255, 255),
	Cream = Color3.fromRGB(255, 252, 245),
	Snow = Color3.fromRGB(248, 252, 255),
}
local FLOWERS = {
	Color3.fromRGB(255, 150, 190),
	Color3.fromRGB(255, 222, 102),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(200, 170, 255),
}
-- One accent per plot (sign trim, gate arch, mailbox), so a kid can say "mine is the pink one".
local PLOT_ACCENTS = {
	Color3.fromRGB(255, 143, 171),
	Color3.fromRGB(110, 190, 255),
	Color3.fromRGB(110, 215, 170),
	Color3.fromRGB(255, 206, 92),
	Color3.fromRGB(190, 150, 255),
	Color3.fromRGB(255, 166, 120),
}

type RoomStyle = {
	Floor: Color3,
	FloorMaterial: Enum.Material,
	Wall: Color3,
	Trim: Color3,
	Awning: { Color3 }?, -- two colours that alternate; nil = a garden arbor instead
	Blanket: Color3,
	Snow: boolean?,
}

local STYLES: { [string]: RoomStyle } = {
	Stand = {
		Floor = Color3.fromRGB(228, 192, 142),
		FloorMaterial = Enum.Material.WoodPlanks,
		Wall = Color3.fromRGB(255, 240, 222),
		Trim = COLORS.Wood,
		Awning = { Color3.fromRGB(255, 132, 122), COLORS.Cream },
		Blanket = Color3.fromRGB(255, 160, 150),
	},
	BathRoom = {
		Floor = Color3.fromRGB(206, 236, 246),
		FloorMaterial = Enum.Material.SmoothPlastic,
		Wall = Color3.fromRGB(226, 246, 255),
		Trim = Color3.fromRGB(150, 200, 226),
		Awning = { Color3.fromRGB(90, 196, 240), COLORS.White },
		Blanket = Color3.fromRGB(140, 214, 240),
	},
	Ward = {
		Floor = Color3.fromRGB(248, 224, 232),
		FloorMaterial = Enum.Material.Fabric,
		Wall = Color3.fromRGB(255, 242, 246),
		Trim = Color3.fromRGB(214, 170, 190),
		Awning = { Color3.fromRGB(196, 166, 255), COLORS.White },
		Blanket = Color3.fromRGB(196, 166, 255),
	},
	WinterWing = {
		Floor = Color3.fromRGB(226, 238, 255),
		FloorMaterial = Enum.Material.SmoothPlastic,
		Wall = Color3.fromRGB(240, 248, 255),
		Trim = Color3.fromRGB(150, 180, 226),
		Awning = { Color3.fromRGB(122, 162, 232), COLORS.White },
		Blanket = Color3.fromRGB(122, 162, 232),
		Snow = true,
	},
	Garden = {
		Floor = Color3.fromRGB(158, 214, 122),
		FloorMaterial = Enum.Material.Grass,
		Wall = Color3.fromRGB(104, 176, 86),
		Trim = COLORS.Wood,
		Awning = nil,
		Blanket = COLORS.White,
	},
}

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
	local p = part(parent, name, size or Vector3.new(2, 1, 2), cframe, COLORS.White)
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function lighten(color: Color3, amount: number): Color3
	return color:Lerp(COLORS.White, amount)
end

local function darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

local function label(parent: Instance, name: string, text: string, size: UDim2, position: UDim2): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = Enum.Font.FredokaOne
	l.TextColor3 = COLORS.Ink
	l.TextScaled = true
	l.Text = text
	l.Parent = parent
	return l
end

-- A round icon badge floating above a part (station icons, slot previews).
local function iconBadge(adornee: BasePart, name: string, icon: string, ring: Color3, studs: number, height: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = UDim2.fromScale(studs, studs)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 80

	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.Size = UDim2.fromScale(1, 1)
	disc.BackgroundColor3 = COLORS.White
	disc.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = disc
	local stroke = Instance.new("UIStroke")
	stroke.Color = ring
	stroke.Thickness = 4
	stroke.Parent = disc
	local text = label(disc, "Icon", icon, UDim2.fromScale(0.7, 0.7), UDim2.fromScale(0.15, 0.15))
	text.TextColor3 = COLORS.Ink

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

local function tree(parent: Instance, at: CFrame, scale: number)
	local model = Instance.new("Model")
	model.Name = "Tree"
	cylinder(model, "Trunk", 6 * scale, 1.4 * scale, at * CFrame.new(0, 3 * scale, 0), COLORS.Trunk, Enum.Material.Wood)
	soft(ball(model, "Leaves", 7 * scale, at * CFrame.new(0, 7 * scale, 0), COLORS.Leaf1))
	soft(ball(model, "Leaves", 5.5 * scale, at * CFrame.new(1.8 * scale, 8.8 * scale, 0.6 * scale), COLORS.Leaf3))
	soft(ball(model, "Leaves", 5 * scale, at * CFrame.new(-1.6 * scale, 8.4 * scale, -1 * scale), COLORS.Leaf2))
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
	part(model, "Seat", Vector3.new(5, 0.4, 1.6), at * CFrame.new(0, 1.4, 0), COLORS.Wood, Enum.Material.Wood)
	part(model, "Back", Vector3.new(5, 1.4, 0.3), at * CFrame.new(0, 2.3, 0.7), COLORS.Wood, Enum.Material.Wood)
	part(model, "Leg", Vector3.new(0.4, 1.2, 1.4), at * CFrame.new(-2.1, 0.6, 0), COLORS.LampPost)
	part(model, "Leg", Vector3.new(0.4, 1.2, 1.4), at * CFrame.new(2.1, 0.6, 0), COLORS.LampPost)
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
	local color = if station then station.Color else COLORS.Wood
	local icon = if station then station.Icon else "❔"
	local base = CFrame.new(at.X, FLOOR_TOP, at.Z)
	local stationPart: BasePart

	if stationId == "Bath" then
		stationPart =
			part(model, "Station_Bath", Vector3.new(5.6, 2.2, 3.6), base * CFrame.new(0, 1.1, 0), COLORS.White)
		soft(part(model, "Water", Vector3.new(5, 0.15, 3), base * CFrame.new(0, 2.15, 0), lighten(color, 0.2)))
		for i, offset in { Vector3.new(-1.8, 2.5, -0.6), Vector3.new(-0.4, 2.6, 0.7), Vector3.new(1.2, 2.5, -0.3) } do
			local bubble = soft(ball(model, "Bubble", 0.8 + i * 0.15, base * CFrame.new(offset), COLORS.White))
			bubble.Transparency = 0.15
		end
		for _, x in { -2.3, 2.3 } do
			soft(ball(model, "Foot", 0.6, base * CFrame.new(x, 0.2, 1.3), color))
			soft(ball(model, "Foot", 0.6, base * CFrame.new(x, 0.2, -1.3), color))
		end
	else
		stationPart = part(
			model,
			"Station_" .. stationId,
			Vector3.new(4.2, 3, 2.6),
			base * CFrame.new(0, 1.5, 0),
			lighten(color, 0.55)
		)
		soft(part(model, "Top", Vector3.new(4.5, 0.3, 2.9), base * CFrame.new(0, 3.15, 0), darken(color, 0.1)))
		soft(part(model, "Stripe", Vector3.new(4.25, 0.5, 0.1), base * CFrame.new(0, 2.2, -1.3), color))
		local top = base * CFrame.new(0, 3.3, 0)
		if stationId == "Remedy" then
			local bottles = { color, Color3.fromRGB(255, 150, 200), Color3.fromRGB(120, 220, 180) }
			for i, bottleColor in bottles do
				local x = (i - 2) * 1.2
				local bottle = soft(
					cylinder(model, "Bottle", 1, 0.6, top * CFrame.new(x, 0.5, 0.2), bottleColor, Enum.Material.Glass)
				)
				bottle.Transparency = 0.2
				soft(ball(model, "Cork", 0.4, top * CFrame.new(x, 1.1, 0.2), COLORS.Wood))
			end
		elseif stationId == "Plaster" then
			soft(part(model, "Box", Vector3.new(1.8, 0.8, 1.2), top * CFrame.new(-0.6, 0.4, 0.2), COLORS.White))
			soft(part(model, "BoxStripe", Vector3.new(1.82, 0.22, 1.22), top * CFrame.new(-0.6, 0.4, 0.2), color))
			soft(cylinder(model, "Roll", 0.5, 0.9, top * CFrame.new(1.2, 0.25, 0.1), lighten(color, 0.3)))
		elseif stationId == "Cocoa" then
			soft(cylinder(model, "Mug", 0.9, 0.8, top * CFrame.new(-0.9, 0.45, 0.1), COLORS.White))
			soft(cylinder(model, "CocoaTop", 0.1, 0.7, top * CFrame.new(-0.9, 0.86, 0.1), color))
			soft(part(model, "Marshmallow", Vector3.new(0.3, 0.3, 0.3), top * CFrame.new(-0.8, 1.0, 0.1), COLORS.White))
			soft(ball(model, "Pot", 1.3, top * CFrame.new(0.9, 0.55, 0.2), color))
		end
	end

	iconBadge(stationPart, "IconGui", icon, color, 2.6, stationPart.Size.Y / 2 + 2.1)
end

local function buildBed(model: Model, index: number, at: Vector3, blanket: Color3, frame: Color3)
	local base = CFrame.new(at.X, FLOOR_TOP, at.Z)
	part(model, "BedFrame", Vector3.new(4.4, 0.8, 7), base * CFrame.new(0, 0.4, 0), frame, Enum.Material.Wood)
	-- Bed_<n> is the mattress: patients lie on its top face; the pillow end is +Z (the room's back).
	part(
		model,
		"Bed_" .. index,
		Vector3.new(4, 1, 6.6),
		base * CFrame.new(0, 1.3, 0),
		COLORS.Cream,
		Enum.Material.Fabric
	)
	soft(
		part(
			model,
			"Pillow",
			Vector3.new(3, 0.5, 1.4),
			base * CFrame.new(0, 2.05, 2.4),
			COLORS.White,
			Enum.Material.Fabric
		)
	)
	soft(
		part(
			model,
			"Blanket",
			Vector3.new(4.1, 0.25, 3.4),
			base * CFrame.new(0, 1.92, -1.4),
			blanket,
			Enum.Material.Fabric
		)
	)
	part(
		model,
		"Headboard",
		Vector3.new(4.4, 2.6, 0.5),
		base * CFrame.new(0, 1.3, 3.75),
		darken(frame, 0.08),
		Enum.Material.Wood
	)
end

local function buildDecorSlot(model: Model, index: number, at: Vector3, floorColor: Color3)
	marker(model, "DecorSlot_" .. index, CFrame.new(at.X, FLOOR_TOP + 0.5, at.Z), Vector3.new(4, 1, 4))
	-- A soft round spot that shows where decor goes.
	local spot = soft(
		cylinder(model, "DecorSpot", 0.06, 3.4, CFrame.new(at.X, FLOOR_TOP + 0.03, at.Z), lighten(floorColor, 0.45))
	)
	spot.Transparency = 0.3
	spot.CastShadow = false
end

local function buildShell(model: Model, roomId: string, w: number, d: number, style: RoomStyle)
	local room = Rooms[roomId]
	local back = d / 2
	if style.Awning then
		-- Tall enough that the awning's high back edge rests on it.
		part(model, "BackWall", Vector3.new(w, 8.6, 0.6), CFrame.new(0, FLOOR_TOP + 4.3, back - 0.3), style.Wall)
		for _, side in { -1, 1 } do
			part(
				model,
				"SideWall",
				Vector3.new(0.6, 4, d * 0.5),
				CFrame.new(side * (w / 2 - 0.3), FLOOR_TOP + 2, back - d * 0.25),
				style.Wall
			)
		end
		-- A striped awning over the back half, sloping down toward the front.
		local awning = style.Awning
		local depth = d * 0.45
		local stripes = 6
		local stripeWidth = (w + 1) / stripes
		for i = 1, stripes do
			local x = -(w + 1) / 2 + (i - 0.5) * stripeWidth
			soft(
				part(
					model,
					"Awning",
					Vector3.new(stripeWidth, 0.35, depth + 0.6),
					CFrame.new(x, FLOOR_TOP + 8.1, back - depth / 2) * CFrame.Angles(math.rad(-12), 0, 0),
					awning[(i % 2) + 1]
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
				style.Trim
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
						COLORS.Snow
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
			cylinder(
				model,
				"ArborPost",
				7,
				0.6,
				CFrame.new(side * 4.5, FLOOR_TOP + 3.5, back - 2.2),
				style.Trim,
				Enum.Material.Wood
			)
		end
		part(
			model,
			"ArborBeam",
			Vector3.new(10.4, 0.6, 1.2),
			CFrame.new(0, FLOOR_TOP + 7.2, back - 2.2),
			style.Trim,
			Enum.Material.Wood
		)
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
	local plaqueHeight = if style.Awning then FLOOR_TOP + 7.3 else FLOOR_TOP + 6.1
	local plaqueZ = if style.Awning then back - 0.68 else back - 2.88
	local plaqueWidth = if style.Awning then math.min(w * 0.5, 10) else 8
	local plaque = soft(
		part(model, "Plaque", Vector3.new(plaqueWidth, 1.5, 0.15), CFrame.new(0, plaqueHeight, plaqueZ), COLORS.Board)
	)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PlaqueGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	gui.MaxDistance = 100
	label(gui, "Name", room.Icon .. " " .. room.Name, UDim2.fromScale(0.94, 0.8), UDim2.fromScale(0.03, 0.1))
	gui.Parent = plaque
end

local function placeholderRoom(roomId: string): Model
	local room = Rooms[roomId]
	local style = STYLES[roomId] or STYLES.Stand
	local size = slotSize(roomId)
	local w, d = size.X, size.Z

	local model = Instance.new("Model")
	model.Name = "Room_" .. roomId
	local floor = part(model, "Floor", size, CFrame.identity, style.Floor, style.FloorMaterial)
	part(model, "Edge", Vector3.new(w + 0.6, 0.4, d + 0.6), CFrame.new(0, -0.15, 0), darken(style.Floor, 0.12))
	model.PrimaryPart = floor

	buildShell(model, roomId, w, d, style)

	local layout = layoutFor(roomId, w, d)
	for _, stationId in room.Stations do
		buildStation(model, stationId, layout.Stations[stationId])
	end
	for index, at in layout.Beds do
		buildBed(model, index, at, style.Blanket, COLORS.Wood)
	end
	for index, at in layout.Decor do
		buildDecorSlot(model, index, at, style.Floor)
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
	anchorAll(model)

	local room = Rooms[roomId]
	for _, stationId in room.Stations do
		if not model:FindFirstChild("Station_" .. stationId, true) then
			warn("[PlotBuilder] ClinicKit." .. roomId .. " is missing Station_" .. stationId)
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

function PlotBuilder.buildRoom(roomId: string): Model
	assert(Rooms[roomId], "Unknown room " .. tostring(roomId))
	local model = kitRoom(roomId) or placeholderRoom(roomId)
	model:SetAttribute("RoomId", roomId)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- a room streams in whole, with its stations
	return model
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

	local model = PlotBuilder.buildRoom(roomId)
	local floor = model.PrimaryPart :: BasePart
	model:PivotTo(slot.CFrame * floor.CFrame:ToObjectSpace(model:GetPivot()))
	model.Parent = roomsFolder
	PlotBuilder.setPreview(plotModel, room.Slot, nil)
	return model
end

------------------------------------------------------------------------------------------------------------------
-- Slot previews: a dashed outline and a floating badge showing what unlocks there
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
	local dash = 2.2
	for _, edge in { { w, -d / 2, 0 }, { w, d / 2, 0 }, { d, -w / 2, 90 }, { d, w / 2, 90 } } do
		local length, offset, angle = edge[1], edge[2], edge[3]
		local count = math.floor(length / (dash * 2))
		for i = 0, count - 1 do
			local along = -length / 2 + dash / 2 + i * dash * 2 + (length - count * dash * 2 + dash) / 2
			local cf = if angle == 0
				then ground * CFrame.new(along, 0, offset)
				else ground * CFrame.new(offset, 0, along) * CFrame.Angles(0, math.rad(90), 0)
			local strip = soft(part(preview, "Dash", Vector3.new(dash, 0.12, 0.5), cf, COLORS.White))
			strip.Transparency = 0.25
			strip.CastShadow = false
		end
	end

	local anchor = marker(preview, "BadgeAnchor", ground * CFrame.new(0, 3.5, 0), Vector3.one)
	local gui = Instance.new("BillboardGui")
	gui.Name = "PreviewGui"
	gui.Size = UDim2.fromScale(6, 4)
	gui.LightInfluence = 0
	gui.MaxDistance = 90
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = COLORS.White
	panel.BackgroundTransparency = 0.1
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.Wood
	stroke.Thickness = 3
	stroke.Parent = panel
	label(panel, "Icon", "🔒" .. room.Icon, UDim2.fromScale(0.9, 0.5), UDim2.fromScale(0.05, 0.04))
	label(
		panel,
		"Cost",
		string.format("⭐%d  💰%d", room.StarsNeeded, room.Price),
		UDim2.fromScale(0.9, 0.36),
		UDim2.fromScale(0.05, 0.58)
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

local function buildSign(model: Model, scenery: Model, cf: CFrame, accent: Color3)
	local sign = part(
		model,
		"Sign",
		Vector3.new(9, 3.4, 0.5),
		cf * CFrame.new(-13, 3.4, -33.6),
		COLORS.Board,
		Enum.Material.Wood
	)
	soft(part(scenery, "SignTrim", Vector3.new(9.8, 4.2, 0.4), cf * CFrame.new(-13, 3.4, -33.2), accent))
	for _, x in { -17.2, -8.8 } do
		part(
			scenery,
			"SignPost",
			Vector3.new(0.7, 5.6, 0.7),
			cf * CFrame.new(x, 2.8, -33.2),
			COLORS.WoodDark,
			Enum.Material.Wood
		)
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front -- the side facing the street
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	gui.MaxDistance = 150
	label(gui, "OwnerName", "✨ Free clinic", UDim2.fromScale(0.92, 0.56), UDim2.fromScale(0.04, 0.06))
	label(gui, "HeartCount", "", UDim2.fromScale(0.92, 0.32), UDim2.fromScale(0.04, 0.62))
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
end

local function buildMailbox(scenery: Model, cf: CFrame, accent: Color3)
	local model = Instance.new("Model")
	model.Name = "MailboxProp"
	part(model, "Post", Vector3.new(0.4, 3, 0.4), cf * CFrame.new(9.5, 1.5, -33), COLORS.WoodDark, Enum.Material.Wood)
	part(model, "Box", Vector3.new(1.6, 1.2, 2), cf * CFrame.new(9.5, 3.5, -33), accent)
	soft(
		part(model, "Flag", Vector3.new(0.1, 0.9, 0.35), cf * CFrame.new(10.4, 3.9, -33.5), Color3.fromRGB(240, 90, 90))
	)
	model.Parent = scenery
end

local function buildPlaceholderPlot(index: number, cf: CFrame): Model
	local half = Config.Town.PlotSize / 2
	local accent = PLOT_ACCENTS[(index - 1) % #PLOT_ACCENTS + 1]
	local model = Instance.new("Model")
	model.Name = "Plot_" .. index

	local scenery = Instance.new("Model")
	scenery.Name = "Scenery"
	scenery.Parent = model

	part(model, "Ground", Vector3.new(half * 2, 1, half * 2), cf * CFrame.new(0, -0.5, 0), COLORS.Lawn)

	-- The front path from the gate to the counter, and stepping stones across the back yard.
	part(scenery, "Path", Vector3.new(9, 0.2, half - 15.6), cf * CFrame.new(0, 0.05, -(half + 15.6) / 2), COLORS.Path)
	for _, z in { 3.5, 7.2, 10.9, 14.6 } do
		cylinder(scenery, "SteppingStone", 0.2, 2.8, cf * CFrame.new(math.sin(z) * 0.8, 0.05, z), COLORS.Stone)
	end

	-- The counter: patients queue in front of it (toward the street), you treat from behind it.
	part(model, "Counter", Vector3.new(12, 3.4, 2.4), cf * CFrame.new(0, 1.7, -14.5), COLORS.Wood, Enum.Material.Wood)
	soft(part(scenery, "CounterTop", Vector3.new(12.8, 0.4, 3), cf * CFrame.new(0, 3.6, -14.5), COLORS.Cream))
	soft(part(scenery, "CounterStripe", Vector3.new(12.2, 0.6, 0.1), cf * CFrame.new(0, 2.5, -15.72), accent))

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
	tree(scenery, cf * CFrame.new(-28, 0, -27), 1)
	tree(scenery, cf * CFrame.new(28.5, 0, -26), 1.1)
	tree(scenery, cf * CFrame.new(-29, 0, 29), 1.2)
	tree(scenery, cf * CFrame.new(29.5, 0, 29.5), 1)
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
	cylinder(town, "Plaza", 0.2, h * 2 - 2, ground * CFrame.new(0, 0.3, 0), COLORS.Plaza)

	-- Plaza: round planters with little trees at the corners, benches facing the spawn.
	for _, corner in { Vector2.new(1, 1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(-1, -1) } do
		local at = ground * CFrame.new(corner.X * 10.5, 0.4, corner.Y * 10.5)
		cylinder(town, "Planter", 1.2, 4, at * CFrame.new(0, 0.6, 0), COLORS.Wood, Enum.Material.Wood)
		tree(town, at * CFrame.new(0, 1.2, 0), 0.55)
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
			tree(town, ground * CFrame.new(x, 0, side * (h + size / 2)), 1.1)
		end
	end

	-- Welcome arches at both ends of the street (the clinic's motto, design §5.1).
	for _, side in { -1, 1 } do
		local x = side * (width / 2 - 5)
		for _, zSide in { -1, 1 } do
			part(town, "ArchPost", Vector3.new(1.6, 12, 1.6), ground * CFrame.new(x, 6, zSide * (h - 2)), COLORS.Fence)
		end
		local beam = part(
			town,
			"ArchBeam",
			Vector3.new(1.4, 3.4, h * 2 - 2),
			ground * CFrame.new(x, 12.4, 0),
			COLORS.Board,
			Enum.Material.Wood
		)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "WelcomeGui"
		gui.Face = if side < 0 then Enum.NormalId.Right else Enum.NormalId.Left -- faces the town centre
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0.2
		label(
			gui,
			"Motto",
			"Everyone welcome. Even the weird ones.",
			UDim2.fromScale(0.94, 0.8),
			UDim2.fromScale(0.03, 0.1)
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
