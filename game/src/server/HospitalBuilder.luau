--!strict
-- The hospital Building on a plot (look build plan §B4/§B6; Progression v2 build plan §B4 for the names). Server only.
-- Moved from PlotBuilder by the look overhaul's Foundation, behaviour unchanged; T3 owns it.
--   HospitalBuilder.build(plotModel, level, grewFrom?, theme?): Model
--       = PlotBuilder.buildBuilding (the same signature and attributes): the hospital for that level (Data/Levels)
--       in that branch theme (Data/Themes id; nil or unknown = Candy). Replaces Plot.Building, sets the Building's
--       Level, GrewFrom, GrewAt, Floors and Theme and the plot's Level and Theme attributes
--   HospitalBuilder.Pure          the building's interior layout in numbers (plot-local studs; PlotBuilder.Pure
--                                 re-exports it; tests/Hospital.spec loads the PURE block)
--   HospitalBuilder.STATION_TAG   ("BuildingStation")  a station inside the Building (the 💊 Station_Pharmacy Model)
--   HospitalBuilder.LIFT_TAG      ("HospitalLift")     each Building's Lift Model (UI/LiftPanel slides its car)
--   HospitalBuilder.PROMPT_TAGS   { Lift = "LiftPrompt", Escort = "EscortPrompt", Soak = "SoakPrompt" }
--       (PlotBuilder re-exports all three)
-- The plot's colour comes from the plot Model's `Accent` attribute (a Color3 PlotBuilder sets; its PlotIndex's
-- Palette.PlotColors entry when missing). It never requires PlotBuilder (PlotBuilder requires this).
-- The interface numbers the rest of the plot depends on (footprints, storeys, the shaft, the doors, the Stand's
-- spots, the ward beds) are Shared/Logic/Building.
--
-- Coordinates: plot-local studs, the plot's ground-top centre at the origin, x right as you face the street, -z the
-- street, y up. The Building's pivot is the plot's.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Palette = require(Shared.Palette)
local Departments = require(Shared.Data.Departments)
local LevelsData = require(Shared.Data.Levels)
local Stations = require(Shared.Data.Stations)
local Themes = require(Shared.Data.Themes)
local NightLights = require(script.Parent.World.NightLights)
local Parts = require(script.Parent.World.Parts)

local part, soft, ball, cylinder, wedge = Parts.part, Parts.soft, Parts.ball, Parts.cylinder, Parts.wedge
local marker, paint, rounded, band, disc = Parts.marker, Parts.paint, Parts.rounded, Parts.band, Parts.disc
local detailGui, iconBadge = Parts.surface, Parts.iconBadge
local candyLabel, candyBoard = Parts.candyLabel, Parts.candyBoard
local lighten, darken = Parts.lighten, Parts.darken
local anchorAll, scrubScripts = Parts.anchorAll, Parts.scrubScripts

local HospitalBuilder = {}

HospitalBuilder.STATION_TAG = "BuildingStation"
HospitalBuilder.LIFT_TAG = "HospitalLift"
HospitalBuilder.PROMPT_TAGS = table.freeze({ Lift = "LiftPrompt", Escort = "EscortPrompt", Soak = "SoakPrompt" })

local FLOOR_TOP = 0.3 -- room-local height of a room floor's top face (a ward bed's default)

local WHITE = Palette.White
local CANDY = Palette.Candy
local WORLD = Palette.World
local PLANTERS = { CANDY.Pink, CANDY.Blue, CANDY.Yellow, CANDY.Purple }

-- The plot's own colour: the `Accent` attribute PlotBuilder sets, else its PlotIndex's Palette.PlotColors entry.
local function plotAccent(plotModel: Model): Color3?
	local accent = plotModel:GetAttribute("Accent")
	if typeof(accent) == "Color3" then
		return accent
	end
	local index = plotModel:GetAttribute("PlotIndex")
	if type(index) == "number" then
		local colors = Palette.PlotColors
		return colors[(index - 1) % #colors + 1]
	end
	return nil
end

-- A ward bed is the room bed (a copy of PlotBuilder's, so this module never requires it).
type BedStyle = { Main: Color3, Blanket: Color3 }

-- `floorTop` is the height of the floor it stands on in the model's own space (a room's FLOOR_TOP by default);
-- `turn` 1 turns its pillow end from the back (+Z) to +X (a ward bed across the front of the Wards floor).
local function buildBed(model: Model, index: number, at: Vector3, style: BedStyle, floorTop: number?, turn: number?)
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

------------------------------------------------------------------------------------------------------------------
-- The hospital building (depth update §3; Progression v2 §B4/§B8; memory-20261116-008: the building grows)
------------------------------------------------------------------------------------------------------------------
-- STUB (T3): this is still Progression v2's building (the lift in the back strip, 7-stud storeys, ramps,
-- see-through upper walls, the Lv 1 Building empty). T3 rebuilds it to the look build plan §B6 and
-- Shared/Logic/Building, keeping every name, attribute and tag below.
-- Plot.Building is a Model that every plot always has: empty at Lv 1 (the open-air Stand; a branch theme only puts
-- its prop on the Stand), and from Lv 2 a hospital you can walk round, right behind the Stand (the Stand becomes its
-- front porch). Where everything goes is Pure.layout, in plot-local studs worked out from the plot's own Slots:
--   Lobby        the ground storey (Lv 2): walls on three sides, open at its two front corners where the side
--                walkways come in (patients cross it along the back lane), the lift's Landing_0 and the stairs'
--                foot inside. Solid and opaque, like a room
--   Floor_<n>    n = 1..Floors (Data/Levels): a collidable Slab and SlabBack (beside the lift) to walk on, a Landing
--                marker (4x1x4, Floor = n) in front of the lift door and, indoors, see-through Walls (soft and
--                ray-ignored: the camera never snaps on them, and the street sees in). At Lv 5 Floor_4 is the roof
--   Lift         a glass Shaft (soft) at the back with its Car (soft; it moves only on clients, UI/LiftPanel) and a
--                Cap. Every landing has an Attachment PromptPoint with a LiftPrompt (ActionText "Lift", ObjectText
--                "🛗", HoldDuration 0, MaxActivationDistance 8) and an EscortPrompt ("Ride with patient", key F,
--                disabled until Server/Lift.waitEscort turns the ground one on)
--   Stairs       a walkable ramp per storey (Flight_<k>, floor k to k + 1) along the back strip, stacked one above
--                the other; each floor's slab leaves that stairwell open. The steps are drawn on
--   Wards        (Floor_1) the ward beds: BedSpot_<n> Models round the mattress Bed_<n> (Floor = 1 on both), Beds - 1
--                of them (the Stand has the first). A bed is kept (not rebuilt) when the level or the theme changes,
--                so a patient resting on one never notices
--   Hydro        (Floor_2) the HotTub: TubSpot_1/2 markers on the water (Floor = 2) and a SoakPrompt ("🫧",
--                disabled until Server/Patients turns it on)
--   Pharmacy     (Floor_3) the 💊 Station_Pharmacy Model (tagged STATION_TAG: Server/Stations gives it the usual
--                hold prompt; its IconGui is here)
--   Roof         (Floor_4) the helipad with its HeliSpot marker (ArriveAt, set by Server/Patients) and a roof garden
--                of planters, beside the Tower with its neon ✚ and beacon
--   AmbulanceBay (Lv 2) on the front-left lawn: a painted bay and a toy Ambulance (ArriveAt, set by Server/Patients)
--                with a StretcherSpot marker at its side door, facing the line
--   the roof     Lv 2 a candy gable (RoofShell) · Lv 3-4 flat, with a water tank and a big ✚ on its front edge ·
--                Lv 5 walkable (Floor_4)
--   the sign     a name board (the level's name) high on the top storey's façade
--   the theme    Data/Themes recolours the walls, the roof and the trim (the slabs' candy bands) and adds one prop
--                (<= 6 parts) on the roof: ThemeProp. The plot's accent colour (the name board, the ✚ discs, the
--                ambulance's badge, the ward beds) never changes: kids find "the pink one"
-- Nothing covers the Counter, the line, the gate, the sign, the walkways, the stations or a room slot (the ambulance
-- bay sits on the front-left lawn: the line runs straight back from the Counter). Each piece is a child Model with the
-- attribute Since (the level that adds it); the Building carries Level, GrewFrom, GrewAt (the GetServerTimeNow() of a
-- level-up, else 0), Floors and Theme, so a client effect can grow the new pieces in. Windows, the stair steps, the
-- crosses, the helipad's H and the ambulance's stripes are drawn on faces (SurfaceGuis), which keeps a Lv 5 plot with
-- every room under 400 parts (Pure.PARTS in the perf note; decor not counted).
-- ServerStorage.ClinicKit.Building<level> (pivot = the plot's ground-top centre, facing the street) replaces the
-- placeholder for that level: it needs the same names (Landing_0, Floor_<n>.Slab/Landing, Lift, BedSpot_<n>...).
-- It gets Floors and Theme, prompts on any landing without them and the station tag; a missing lift is warned.

-- PURE-BEGIN
-- The building's layout in numbers only (no Roblox types), plot-local studs: x right as you face the street, z toward
-- the back, y up from the plot's ground top. tests/Hospital.spec loads this block on its own.
local Pure = {}

Pure.STOREY = 7 -- an upper storey, slab to slab
Pure.SLAB = 0.6 -- a slab's thickness; its centre is at its storey's base
Pure.WALL = 0.6 -- the lobby's walls
Pure.OVERHANG = 0.4 -- slabs reach this far past the walls (the candy band between storeys)
Pure.STRIP = 3.4 -- the back strip inside the back wall: the stairs and the lift
Pure.SHAFT = 3.6 -- the lift shaft's width (x)
Pure.RUN = 7.8 -- a flight's run (x): every flight rises one storey over it (<= 45 degrees)
Pure.LANDING = 4 -- a landing marker's footprint
Pure.CAR_HEIGHT = 6
Pure.GROUND_MIN = 7 -- the lobby is at least one walkable storey high ...
Pure.GROUND_MAX = 9 -- ... and at most this, so its flight stays walkable
Pure.SIGN_CLEAR = 2.5 -- the first upper storey's façade shows at least this much above the Stand
Pure.FLOOR_TOP = 0.05 -- the lobby's painted floor, just above the lawn
Pure.BED_HALF = 2.2 -- a bed is 4.4 wide ...
Pure.BED_FOOT = 3.5 -- ... reaches this far from the mattress centre toward its foot ...
Pure.BED_HEAD = 4 -- ... and this far toward its headboard
Pure.FOOT_POINT = 4.9 -- where Patients stands a patient before it hops on (half the mattress + 1.6)

type Footprint = { Half: number, Front: number, Back: number, Ground: number }
type Rect = { X0: number, X1: number, Z0: number, Z1: number }
type Bed = { X: number, Z: number, Turn: number } -- Turn 0: the pillow to the back (+z) · 1: the pillow to +x
type Layout = {
	Strip: { Z0: number, Z1: number },
	Left: { X0: number, X1: number }, -- beside the lift: the beds, the tub, the Pharmacy, the Tower
	Shaft: Rect,
	Landing: { X: number, Z: number }, -- every floor's, in front of the lift door
	Ramp: { XLow: number, XHigh: number, Z: number, Width: number }, -- a flight's foot (low) and top (high)
	Slab: Rect,
	SlabBack: Rect,
	Beds: { Bed },
	Tub: { X: number, Z: number, Diameter: number },
	Pharmacy: { X: number, Z: number, Width: number },
	Tower: Rect,
	Pad: { X: number, Z: number, Diameter: number },
	Planters: { { X: number, Z: number } },
}

-- The lobby's height: one walkable storey, raised (at most to GROUND_MAX) only when a tall kit Stand would hide the
-- first upper storey's façade.
function Pure.ground(standTop: number): number
	return math.clamp(standTop + Pure.SIGN_CLEAR - Pure.STOREY, Pure.GROUND_MIN, Pure.GROUND_MAX)
end

-- Floor k's slab centre (k >= 1).
function Pure.slabY(f: Footprint, k: number): number
	return f.Ground + (k - 1) * Pure.STOREY
end

-- Floor k's walking surface (k = 0: the lobby's painted floor).
function Pure.floorTop(f: Footprint, k: number): number
	if k <= 0 then
		return Pure.FLOOR_TOP
	end
	return Pure.slabY(f, k) + Pure.SLAB / 2
end

-- How many floors are indoors (walled storeys) and whether the top one is the roof (Data/Departments Roof's Floor).
function Pure.storeys(floors: number, roofFloor: number): (number, boolean)
	local count = math.max(0, math.floor(floors))
	return math.min(count, roofFloor - 1), count >= roofFloor
end

-- A bed's footprint (the frame and headboard).
function Pure.bedRect(bed: Bed): Rect
	if bed.Turn == 1 then
		return {
			X0 = bed.X - Pure.BED_FOOT,
			X1 = bed.X + Pure.BED_HEAD,
			Z0 = bed.Z - Pure.BED_HALF,
			Z1 = bed.Z + Pure.BED_HALF,
		}
	end
	return {
		X0 = bed.X - Pure.BED_HALF,
		X1 = bed.X + Pure.BED_HALF,
		Z0 = bed.Z - Pure.BED_FOOT,
		Z1 = bed.Z + Pure.BED_HEAD,
	}
end

-- Where Patients stands a patient before it hops onto that bed (just past its foot).
function Pure.bedFoot(bed: Bed): (number, number)
	if bed.Turn == 1 then
		return bed.X - Pure.FOOT_POINT, bed.Z
	end
	return bed.X, bed.Z - Pure.FOOT_POINT
end

function Pure.layout(f: Footprint): Layout
	local h, front, back = f.Half, f.Front, f.Back
	local wall, over = Pure.WALL, Pure.OVERHANG
	local stripZ0, stripZ1 = back - wall - Pure.STRIP, back - wall
	-- The flights' foot is by the right wall; each rises toward the lift, which stands just left of their top.
	local xLow = h - wall - 0.4
	local xHigh = xLow - Pure.RUN
	local shaftX1 = xHigh - 0.6
	local shaftX0 = shaftX1 - Pure.SHAFT
	local leftWall = -h + wall
	if shaftX0 < leftWall + 0.2 then
		-- A narrow kit plot: keep the shaft inside; the flights get shorter (steeper).
		shaftX0 = leftWall + 0.2
		shaftX1 = shaftX0 + Pure.SHAFT
		xHigh = math.min(shaftX1 + 0.6, xLow - 2)
	end
	local left = { X0 = leftWall, X1 = shaftX0 - 0.3 }
	local leftMid = (left.X0 + left.X1) / 2
	local firstBed = leftWall + 0.1 + Pure.BED_HALF
	local padX0, padX1 = xHigh + 1, h - over
	local padZ0, padZ1 = front - over + 0.2, stripZ0 - 0.2
	return {
		Strip = { Z0 = stripZ0, Z1 = stripZ1 },
		Left = left,
		Shaft = { X0 = shaftX0, X1 = shaftX1, Z0 = stripZ0, Z1 = stripZ1 },
		Landing = { X = (shaftX0 + shaftX1) / 2, Z = stripZ0 - Pure.LANDING / 2 - 0.2 },
		Ramp = { XLow = xLow, XHigh = xHigh, Z = (stripZ0 + stripZ1) / 2, Width = Pure.STRIP - 0.2 },
		Slab = { X0 = -h - over, X1 = h + over, Z0 = front - over, Z1 = stripZ0 },
		SlabBack = { X0 = -h - over, X1 = shaftX0, Z0 = stripZ0, Z1 = back + over },
		Beds = {
			-- Two side by side beside the lift, pillows to the back (their feet on the main slab) ...
			{ X = firstBed, Z = back - Pure.BED_HEAD, Turn = 0 },
			{ X = firstBed + Pure.BED_HALF * 2 + 0.2, Z = back - Pure.BED_HEAD, Turn = 0 },
			-- ... and from Lv 4 a third across the front right, its pillow to the right wall.
			{ X = h - Pure.BED_HEAD, Z = front + Pure.BED_HALF, Turn = 1 },
		},
		Tub = { X = leftMid, Z = back - 4.3, Diameter = 8 },
		Pharmacy = { X = leftMid, Z = stripZ0 + 1.3, Width = left.X1 - left.X0 - 1 },
		Tower = { X0 = -h + 0.5, X1 = shaftX0 - 1.5, Z0 = front + 2, Z1 = stripZ1 },
		Pad = { X = (padX0 + padX1) / 2, Z = (padZ0 + padZ1) / 2, Diameter = math.min(padX1 - padX0, padZ1 - padZ0) },
		Planters = { { X = -h + 2.5, Z = front + 0.8 }, { X = -h + 6.5, Z = front + 0.8 } },
	}
end
-- PURE-END

HospitalBuilder.Pure = Pure

local BUILDING_GAP = 1 -- studs between the Stand's back and the block's front wall
local BUILDING_DEPTH = 11 -- the block's depth when nothing behind it is closer
local WALKWAY_CLEAR = 2.5 -- kept free between the block and a room slot beside it (the side walkways)
local YARD_CLEAR = 5 -- kept free between the block and a room slot behind it
local WARD_OPEN = 5.5 -- the lobby's sides are open this far back from its front wall (the walkways' way in)
local WINDOW = 3.2 -- windows are this square (drawn on the walls)
local DETAIL_PIXELS = 12 -- SurfaceGui detail on walls: low resolution is plenty for flat candy shapes
local WALLS_GLASS = 0.5 -- the upper storeys' walls are see-through, so the street sees the wards, tub and pharmacy
local PANE_GLASS = 0.45 -- and their drawn windows too
local BAY_AT = Vector3.new(-26.8, 0, -16.5) -- the ambulance bay (plot-local), its nose to the street
local STAND_TOP = 9.5 -- the placeholder Stand's top, when there's no Room_Stand to measure

-- The floors the departments are on (Data/Departments) and the level each building piece first appears at
-- (Data/Levels), so a piece's Since follows the data.
local function deptFloor(dept: string, fallback: number): number
	local row = rawget(Departments :: any, dept)
	return if type(row) == "table" and type(row.Floor) == "number" then row.Floor else fallback
end
local WARDS_FLOOR = deptFloor("Wards", 1)
local HYDRO_FLOOR = deptFloor("Hydro", 2)
local PHARMACY_FLOOR = deptFloor("Pharmacy", 3)
local ROOF_FLOOR = deptFloor("Roof", 4)

local function hasDept(row: any, dept: string): boolean
	return type(row) == "table" and type(row.Departments) == "table" and table.find(row.Departments, dept) ~= nil
end

local function firstLevel(test: (any) -> boolean): number
	for level, row in LevelsData do
		if test(row) then
			return level
		end
	end
	return 2
end

local function sinceFloor(k: number): number
	return firstLevel(function(row)
		return row.Floors >= k
	end)
end

local function sinceDept(dept: string): number
	return firstLevel(function(row)
		return hasDept(row, dept)
	end)
end

local function sinceBed(index: number): number
	return firstLevel(function(row)
		return row.Beds - 1 >= index
	end)
end

local function extraBeds(level: number): number
	local row = LevelsData[level]
	return if row then math.max(0, row.Beds - 1) else 0
end

type BuildingStyle = {
	Accent: Color3, -- the plot's own colour: never themed
	Wall: Color3,
	Roof: Color3,
	Trim: Color3,
	Glass: Color3,
	Floor: Color3,
	Board: Color3,
	Theme: string,
	Prop: string,
}

local function hexColor(hex: any, fallback: Color3): Color3
	if type(hex) == "string" and string.match(hex, "^#%x%x%x%x%x%x$") then
		local ok, color = pcall(Color3.fromHex, hex)
		if ok then
			return color
		end
	end
	return fallback
end

-- A Data/Themes id and its row; anything unknown is the default (Candy: today's look).
local function themeOf(themeId: any): (string, any)
	local row = if type(themeId) == "string" then rawget(Themes :: any, themeId) else nil
	if type(row) == "table" then
		return themeId, row
	end
	return Themes.Default, rawget(Themes :: any, Themes.Default)
end

local function buildingStyle(accent: Color3, themeId: string?): BuildingStyle
	local id, theme = themeOf(themeId)
	return {
		Accent = accent,
		Wall = hexColor(theme.Wall, lighten(accent, 0.78)),
		Roof = hexColor(theme.Roof, accent),
		Trim = hexColor(theme.Trim, accent),
		Glass = lighten(WORLD.Water, 0.35),
		Floor = WORLD.Floor,
		Board = darken(accent, 0.12),
		Theme = id,
		Prop = if type(theme.Prop) == "string" then theme.Prop else "",
	}
end

-- Where the block goes, in plot-local studs (x from -Half to Half, z from Front to Back), and the lobby's height.
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

	local standTop = STAND_TOP
	local rooms = plotModel:FindFirstChild("Rooms")
	local standRoom = rooms and rooms:FindFirstChild("Room_Stand")
	if standRoom and standRoom:IsA("Model") then
		local box, size = standRoom:GetBoundingBox()
		standTop = pivot:PointToObjectSpace(box.Position).Y + size.Y / 2
	end
	return { Half = half, Front = front, Back = back, Ground = Pure.ground(standTop) }
end

-- A thin part that glows at night like the lamps (Neon only after dark), with no light of its own.
local function nightGlow(p: BasePart): BasePart
	NightLights.tag(p, "Lamp")
	return p
end

-- A disc standing upright and facing the street (Roblox cylinders run along X, so turn it to face -Z). Its Right
-- face is the one toward the street.
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
-- skipTopMiddle leaves the top row's middle window out (a sign hangs there). `see` makes the panes see-through (the
-- glass storeys).
local function windowGui(
	p: BasePart,
	face: Enum.NormalId,
	cols: number,
	rows: number,
	glass: Color3,
	skipTopMiddle: boolean?,
	see: number?
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
				glassPane.BackgroundTransparency = see or 0
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
	local f = band(gui, name, size, position, color)
	if corner then
		rounded(f, UDim.new(corner, 0))
	end
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
-- (docs/guides/build-the-clinic.md, Rules); the plot accents (Palette.PlotColors) are never red. The cross is drawn
-- on the disc (unlit, so it stays bright). A neon one glows at night: the rim turns Neon and the disc lights up (a
-- shadowless PointLight, like the lamps).
local function crossSign(parent: Instance, at: CFrame, diameter: number, accent: Color3, neon: boolean)
	local rim = upright(parent, "SignRim", diameter + 0.7, 0.5, at, WHITE)
	local face = upright(parent, "SignDisc", diameter, 0.5, at * CFrame.new(0, 0, -0.12), accent)
	local gui = faceGui(face, "CrossGui", Enum.NormalId.Right, 0)
	gui.PixelsPerStud = 24
	band(gui, "Cross", UDim2.fromScale(0.64, 0.22), UDim2.fromScale(0.5, 0.5), WHITE)
	band(gui, "Cross", UDim2.fromScale(0.22, 0.64), UDim2.fromScale(0.5, 0.5), WHITE)
	if neon then
		nightGlow(rim)
		NightLights.light(face, 24)
	end
end

------------------------------------------------------------------------------------------------------------------
-- The lobby, the floors, the lift and the stairs
------------------------------------------------------------------------------------------------------------------

-- The ground storey: open at its two front corners, with no back door (the lift and the stairs stand there).
local function buildLobby(model: Model, f: Footprint, style: BuildingStyle)
	local lobby = piece(model, "Lobby", sinceFloor(1))
	local half, front, back, g = f.Half, f.Front, f.Back, f.Ground
	local w, d = half * 2, back - front
	local cz = (front + back) / 2
	paint(part(lobby, "LobbyFloor", Vector3.new(w - 0.6, 0.04, d - 0.6), CFrame.new(0, 0.03, cz), style.Floor))
	part(lobby, "FrontWall", Vector3.new(w, g, 0.6), CFrame.new(0, g / 2, front + 0.3), style.Wall)
	local backWall = part(lobby, "BackWall", Vector3.new(w, g, 0.6), CFrame.new(0, g / 2, back - 0.3), style.Wall)
	windowGui(backWall, Enum.NormalId.Back, 2, 1, style.Glass)
	local openTo = front + WARD_OPEN
	local wallLength = back - openTo
	for _, side in { -1, 1 } do
		local wall = part(
			lobby,
			"SideWall",
			Vector3.new(0.6, g, wallLength),
			CFrame.new(side * (half - 0.3), g / 2, openTo + wallLength / 2),
			style.Wall
		)
		windowGui(wall, if side < 0 then Enum.NormalId.Left else Enum.NormalId.Right, 1, 1, style.Glass)
	end
end

-- The two prompts every landing has, at a rider's chest height.
local function liftPrompts(landing: BasePart)
	if landing:FindFirstChild("PromptPoint") then
		return
	end
	local point = Instance.new("Attachment")
	point.Name = "PromptPoint"
	point.Position = Vector3.new(0, 2.5, 0)
	point.Parent = landing
	local lift = Instance.new("ProximityPrompt")
	lift.Name = "LiftPrompt"
	lift.ActionText = "Lift"
	lift.ObjectText = "🛗"
	lift.HoldDuration = 0
	lift.MaxActivationDistance = 8
	lift.RequiresLineOfSight = false
	CollectionService:AddTag(lift, HospitalBuilder.PROMPT_TAGS.Lift)
	lift.Parent = point
	local escort = Instance.new("ProximityPrompt")
	escort.Name = "EscortPrompt"
	escort.ActionText = "Ride with patient"
	escort.ObjectText = "🛗"
	escort.HoldDuration = 0
	escort.MaxActivationDistance = 8
	escort.RequiresLineOfSight = false
	escort.KeyboardKeyCode = Enum.KeyCode.F -- beside the LiftPrompt's E
	escort.GamepadKeyCode = Enum.KeyCode.ButtonY
	escort.Enabled = false
	CollectionService:AddTag(escort, HospitalBuilder.PROMPT_TAGS.Escort)
	escort.Parent = point
end

local function landingMarker(parent: Instance, name: string, floor: number, f: Footprint, layout: Layout): BasePart
	local at = layout.Landing
	local y = Pure.floorTop(f, floor)
	-- Facing out of the lift (toward the street), resting on the floor.
	local landing = marker(parent, name, CFrame.new(at.X, y + 0.5, at.Z), Vector3.new(Pure.LANDING, 1, Pure.LANDING))
	landing:SetAttribute("Floor", floor)
	liftPrompts(landing)
	return landing
end

local function rectPart(parent: Instance, name: string, r: Rect, y: number, height: number, color: Color3): Part
	return part(
		parent,
		name,
		Vector3.new(r.X1 - r.X0, height, r.Z1 - r.Z0),
		CFrame.new((r.X0 + r.X1) / 2, y, (r.Z0 + r.Z1) / 2),
		color
	)
end

-- Floor_k: its slabs (they collide: you walk on them), its landing and, indoors, its see-through walls.
local function buildFloor(model: Model, f: Footprint, layout: Layout, style: BuildingStyle, k: number, indoor: boolean)
	local floorModel = piece(model, "Floor_" .. k, sinceFloor(k))
	local y = Pure.slabY(f, k)
	rectPart(floorModel, "Slab", layout.Slab, y, Pure.SLAB, style.Trim)
	rectPart(floorModel, "SlabBack", layout.SlabBack, y, Pure.SLAB, style.Trim)
	landingMarker(floorModel, "Landing", k, f, layout)
	if indoor then
		local height = Pure.STOREY - Pure.SLAB
		local walls = soft(part(
			floorModel,
			"Walls",
			Vector3.new(f.Half * 2, height, f.Back - f.Front),
			CFrame.new(0, y + Pure.SLAB / 2 + height / 2, (f.Front + f.Back) / 2),
			if k % 2 == 1 then WHITE else style.Wall -- white and pastel layers, like a cake
		))
		walls.Transparency = WALLS_GLASS
		walls.CastShadow = false
		-- Windows on the three sides you see from the street (one every ~7 studs across, ~5.5 deep).
		local across = math.max(1, math.floor(f.Half * 2 / 7))
		local deep = math.max(1, math.floor((f.Back - f.Front) / 5.5))
		windowGui(walls, Enum.NormalId.Front, across, 1, style.Glass, false, PANE_GLASS)
		windowGui(walls, Enum.NormalId.Left, deep, 1, style.Glass, false, PANE_GLASS)
		windowGui(walls, Enum.NormalId.Right, deep, 1, style.Glass, false, PANE_GLASS)
	end
end

-- The glass lift: its shaft from the lobby floor to `top`, a cap, and the car resting at the lobby with its doors
-- drawn on its street side (open; UI/LiftPanel closes them, slides the car and opens them on each client).
local function buildLift(model: Model, layout: Layout, style: BuildingStyle, top: number)
	local lift = piece(model, "Lift", sinceFloor(1))
	local s = layout.Shaft
	local w, d = s.X1 - s.X0, s.Z1 - s.Z0
	local cx, cz = (s.X0 + s.X1) / 2, (s.Z0 + s.Z1) / 2
	local shaft = soft(part(lift, "Shaft", Vector3.new(w, top, d), CFrame.new(cx, top / 2, cz), style.Glass))
	shaft.Transparency = 0.6
	shaft.CastShadow = false
	soft(part(lift, "Cap", Vector3.new(w + 0.5, 0.5, d + 0.5), CFrame.new(cx, top + 0.25, cz), style.Trim))
	local car = soft(
		part(
			lift,
			"Car",
			Vector3.new(w - 0.4, Pure.CAR_HEIGHT, d - 0.4),
			CFrame.new(cx, Pure.FLOOR_TOP + Pure.CAR_HEIGHT / 2, cz),
			WHITE
		)
	)
	car.Transparency = 0.35
	car.CastShadow = false
	local doors = detailGui(car, "DoorsGui", Enum.NormalId.Front, 20, 200)
	for i, name in { "DoorL", "DoorR" } do
		local door =
			band(doors, name, UDim2.fromScale(0.5, 1), UDim2.fromScale(if i == 1 then -0.21 else 1.21, 0.5), style.Trim)
		local rim = Instance.new("UIStroke")
		rim.Color = WHITE
		rim.Thickness = 3
		rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rim.Parent = door
	end
	lift:SetAttribute("Ride", "") -- Server/Lift: "<from>,<to>,<seconds>,<serverTime>" for each ride (clients slide it)
	lift:SetAttribute("Rider", 0) -- ... and who rode and when (Feel/HospitalFX dings others' rides)
	lift:SetAttribute("RideAt", 0)
	CollectionService:AddTag(lift, HospitalBuilder.LIFT_TAG)
end

-- One flight per storey, from floor k (at the right wall) up to floor k + 1 (beside the lift): a thin plate tilted
-- along the back strip with its steps drawn on, stacked one storey above the last so each keeps full headroom.
local function buildStairs(model: Model, f: Footprint, layout: Layout, style: BuildingStyle, floors: number)
	local stairs = piece(model, "Stairs", sinceFloor(1))
	local r = layout.Ramp
	local color = lighten(style.Trim, 0.35)
	for k = 0, floors - 1 do
		local low = Vector3.new(r.XLow, Pure.floorTop(f, k), r.Z)
		local high = Vector3.new(r.XHigh, Pure.floorTop(f, k + 1), r.Z)
		local length = (high - low).Magnitude
		-- The walking surface runs from `low` to `high`; the plate's centre sits half its thickness under it.
		local frame = CFrame.lookAt((low + high) / 2, high) * CFrame.new(0, -0.2, 0)
		local flight = part(stairs, "Flight_" .. k, Vector3.new(r.Width, 0.4, length), frame, color)
		flight:SetAttribute("Since", sinceFloor(k + 1))
		local steps = detailGui(flight, "StepsGui", Enum.NormalId.Top, 8)
		local count = math.max(3, math.floor(length / 1.2))
		for i = 1, count - 1 do
			band(steps, "Step", UDim2.fromScale(0.05, 1), UDim2.fromScale(i / count, 0.5), darken(color, 0.22))
		end
	end
end

------------------------------------------------------------------------------------------------------------------
-- The departments
------------------------------------------------------------------------------------------------------------------

-- A ward bed: a BedSpot_<n> Model round the mattress Part Bed_<n>, on the Wards floor.
local function wardBed(parent: Instance, f: Footprint, layout: Layout, index: number, accent: Color3)
	local bed = layout.Beds[index]
	if not bed then
		return
	end
	local spot = piece(parent, "BedSpot_" .. index, sinceBed(index))
	spot:SetAttribute("Floor", WARDS_FLOOR)
	buildBed(
		spot,
		index,
		Vector3.new(bed.X, 0, bed.Z),
		{ Main = accent, Blanket = CANDY.Yellow },
		Pure.floorTop(f, WARDS_FLOOR),
		bed.Turn
	)
	local mattress = spot:FindFirstChild("Bed_" .. index)
	if mattress then
		mattress:SetAttribute("Floor", WARDS_FLOOR)
	end
end

-- Hydro: a round hot tub; patients soak at its two TubSpots; the SoakPrompt waits at its front edge.
local function buildHydro(model: Model, f: Footprint, layout: Layout)
	local hydro = piece(model, "Hydro", sinceDept("Hydro"))
	local t = layout.Tub
	local base = Pure.floorTop(f, HYDRO_FLOOR)
	local rim = 1.6
	local tubModel = Instance.new("Model")
	tubModel.Name = "HotTub"
	local tub = cylinder(tubModel, "Tub", rim, t.Diameter, CFrame.new(t.X, base + rim / 2, t.Z), WHITE)
	local water =
		paint(cylinder(tubModel, "Water", 0.1, t.Diameter - 0.8, CFrame.new(t.X, base + rim + 0.03, t.Z), WORLD.Water))
	water.Transparency = 0.15
	local bubble = soft(ball(tubModel, "Bubble", 1.1, CFrame.new(t.X + 1.4, base + rim + 0.35, t.Z - 2.2), WHITE))
	bubble.Transparency = 0.1
	bubble.CastShadow = false
	for i, dx in { -1.9, 1.9 } do
		local spot = marker(tubModel, "TubSpot_" .. i, CFrame.new(t.X + dx, base + rim + 0.5, t.Z))
		spot:SetAttribute("Floor", HYDRO_FLOOR)
	end
	local point = Instance.new("Attachment")
	point.Name = "SoakPoint"
	point.CFrame = tub.CFrame:ToObjectSpace(CFrame.new(t.X, base + 2.6, t.Z - t.Diameter / 2))
	point.Parent = tub
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SoakPrompt"
	prompt.ActionText = "🫧"
	prompt.ObjectText = ""
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	CollectionService:AddTag(prompt, HospitalBuilder.PROMPT_TAGS.Soak)
	prompt.Parent = point
	tubModel.Parent = hydro
end

-- The 💊 Pharmacy: a station Model by the station contract (Server/Stations finds it by its tag), a counter in the
-- station's colour with a white stripe and its floating icon, and a shelf of bottles drawn behind it.
local function buildPharmacy(model: Model, f: Footprint, layout: Layout)
	local pharmacy = piece(model, "Pharmacy", sinceDept("Pharmacy"))
	local p = layout.Pharmacy
	local base = Pure.floorTop(f, PHARMACY_FLOOR)
	local data = rawget(Stations :: any, "Pharmacy")
	local color: Color3 = if data then data.Color else CANDY.Mint
	local station = Instance.new("Model")
	station.Name = "Station_Pharmacy"
	local counter = part(station, "Counter", Vector3.new(4.6, 3, 2.6), CFrame.new(p.X, base + 1.5, p.Z), color)
	station.PrimaryPart = counter
	soft(part(station, "Top", Vector3.new(4.9, 0.3, 2.9), CFrame.new(p.X, base + 3.15, p.Z), WHITE))
	band(
		detailGui(counter, "StripeGui", Enum.NormalId.Front, 20),
		"Stripe",
		UDim2.fromScale(1, 0.5 / 3),
		UDim2.fromScale(0.5, 0.5 - 0.7 / 3),
		WHITE
	)
	local shelf = soft(
		part(
			station,
			"Shelf",
			Vector3.new(math.max(p.Width, 4), 4.4, 0.6),
			CFrame.new(p.X, base + 2.2, layout.Strip.Z1 - 0.3),
			lighten(color, 0.55)
		)
	)
	local bottles = detailGui(shelf, "BottlesGui", Enum.NormalId.Front, 12)
	local colors = { CANDY.Pink, CANDY.Yellow, CANDY.Cyan, CANDY.Purple, CANDY.Orange }
	for row = 1, 2 do
		for col = 1, 5 do
			local bottle = band(
				bottles,
				"Bottle",
				UDim2.fromScale(0.1, 0.26),
				UDim2.fromScale((col - 0.5) / 5, row * 0.46 - 0.14),
				colors[(row + col) % #colors + 1]
			)
			rounded(bottle, UDim.new(0.35, 0))
		end
	end
	iconBadge(counter, "IconGui", if data then data.Icon else "💊", color, 2.6, 1.5 + 2.1)
	CollectionService:AddTag(station, HospitalBuilder.STATION_TAG)
	station.Parent = pharmacy
end

-- The roof (Floor_4): the helipad (a yellow ring, a dark pad and a white H drawn on one flat see-through part), its
-- HeliSpot marker, and a roof garden of planters in front of the tower.
local function buildRoofTop(model: Model, layout: Layout, roofTop: number)
	local roof = piece(model, "Roof", sinceDept("Roof"))
	local pad = layout.Pad
	local surface = paint(
		part(roof, "Pad", Vector3.new(pad.Diameter, 0.1, pad.Diameter), CFrame.new(pad.X, roofTop + 0.06, pad.Z), WHITE)
	)
	surface.Transparency = 1
	local gui = faceGui(surface, "PadGui", Enum.NormalId.Top, 1)
	disc(gui, "Ring", 1, CANDY.Yellow, 1)
	disc(gui, "Inner", 0.86, WORLD.Street, 2)
	local letter = candyLabel(gui, "H", "H", UDim2.fromScale(0.44, 0.44), UDim2.fromScale(0.28, 0.28), 5)
	letter.ZIndex = 3
	local heli = marker(roof, "HeliSpot", CFrame.new(pad.X, roofTop + 0.5, pad.Z))
	heli:SetAttribute("ArriveAt", 0) -- Server/Patients sets it; Feel/HospitalFX flies the helicopter in
	for i, at in layout.Planters do
		part(
			roof,
			"Planter",
			Vector3.new(3, 1.2, 1.6),
			CFrame.new(at.X, roofTop + 0.6, at.Z),
			PLANTERS[i % #PLANTERS + 1]
		)
		local flowers = if i % 2 == 0 then lighten(CANDY.Pink, 0.25) else WORLD.LeavesLight
		soft(ball(roof, "Flowers", 1.9, CFrame.new(at.X, roofTop + 1.6, at.Z), flowers))
	end
end

-- Lv 5: a two-storey tower on the roof's left, its neon ✚ facing the street and a beacon on top. Returns the spot on
-- its top where a theme prop stands.
local function buildTower(model: Model, layout: Layout, style: BuildingStyle, roofTop: number): CFrame
	local tower = piece(model, "Tower", sinceDept("Roof"))
	local t = layout.Tower
	local cx, cz = (t.X0 + t.X1) / 2, (t.Z0 + t.Z1) / 2
	local w, d = t.X1 - t.X0, t.Z1 - t.Z0
	local height = Pure.STOREY * 2
	local block =
		soft(part(tower, "TowerBlock", Vector3.new(w, height, d), CFrame.new(cx, roofTop + height / 2, cz), WHITE))
	windowGui(block, Enum.NormalId.Front, 1, 2, style.Glass, true) -- the neon ✚ takes the top front window
	windowGui(block, Enum.NormalId.Left, 1, 2, style.Glass)
	windowGui(block, Enum.NormalId.Right, 1, 2, style.Glass)
	soft(
		part(
			tower,
			"TowerLedge",
			Vector3.new(w + 0.8, 0.6, d + 0.8),
			CFrame.new(cx, roofTop + Pure.STOREY, cz),
			style.Trim
		)
	)
	soft(part(tower, "TowerCap", Vector3.new(w + 1, 0.8, d + 1), CFrame.new(cx, roofTop + height, cz), style.Roof))
	crossSign(tower, CFrame.new(cx, roofTop + Pure.STOREY + 3.5, t.Z0 - 0.4), 4.8, style.Accent, true)
	-- A beacon on the cap's front half, glowing red at night.
	nightGlow(soft(ball(tower, "Beacon", 1.4, CFrame.new(cx, roofTop + height + 1.1, t.Z0 + 2), CANDY.Red)))
	return CFrame.new(cx, roofTop + height + 0.4, t.Z1 - 2)
end

-- Lv 2: a candy gable over the top storey (ridge running across, so its front slope faces the street). Returns the
-- spot on its ridge for a theme prop, and its front eave (for icicles) with its width.
local function buildGable(model: Model, f: Footprint, style: BuildingStyle, top: number): (CFrame, CFrame, number)
	local roof = piece(model, "RoofShell", sinceFloor(1))
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
		local slab = soft(part(roof, "RoofSlope", Vector3.new(w, 0.5, length), slope, style.Roof))
		-- A white stripe across each slope's middle, like the Stand's awning (drawn).
		band(
			detailGui(slab, "StripeGui", Enum.NormalId.Top, 6, 400),
			"RoofStripe",
			UDim2.fromScale(1.2 / length, 1),
			UDim2.fromScale(0.5, 0.5),
			WHITE
		)
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
	return CFrame.new(-f.Half * 0.55, base + rise + 0.3, centre), CFrame.new(0, base, front + 0.1), w
end

-- Lv 3-4: a flat roof with a lip and a water tank. Returns the spot for a theme prop (the front left) and its front
-- edge (for icicles) with its width.
local function buildFlatRoof(
	model: Model,
	f: Footprint,
	style: BuildingStyle,
	top: number,
	level: number
): (CFrame, CFrame, number)
	local roof = piece(model, "RoofShell", level)
	local half, front, back = f.Half, f.Front, f.Back
	local cz = (front + back) / 2
	soft(
		part(roof, "RoofCap", Vector3.new(half * 2 + 0.8, 0.6, back - front + 0.8), CFrame.new(0, top, cz), style.Roof)
	)
	local at = CFrame.new(half - 3, top + 0.3, back - 3)
	soft(part(roof, "TankStand", Vector3.new(2.4, 1.2, 2.4), at * CFrame.new(0, 0.6, 0), WHITE))
	soft(cylinder(roof, "Tank", 2.6, 3, at * CFrame.new(0, 2.5, 0), style.Roof))
	soft(ball(roof, "TankTop", 1.2, at * CFrame.new(0, 3.9, 0), WHITE))
	return CFrame.new(-half + 3.5, top + 0.3, front + 2.5), CFrame.new(0, top - 0.3, front - 0.4), half * 2 + 0.8
end

-- A&E: the ambulance bay, a painted bay with a toy ambulance parked nose to the street. Its stripe, its badges (a
-- white cross on the plot's accent colour, never a red cross on white: see crossSign) and windscreen are drawn on its
-- sides; each axle is one long cylinder that shows a wheel on both sides. The StretcherSpot by its side door faces
-- the line (Server/Patients pops an urgent patient out there).
local function buildAmbulanceBay(model: Model, style: BuildingStyle)
	local bay = piece(model, "AmbulanceBay", sinceDept("AE"))
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
	for _, z in { -3.2, 3 } do
		local axle =
			soft(part(van, "Axle", Vector3.new(5, lift * 2, lift * 2), at * CFrame.new(0, lift, z), Palette.Ink))
		axle.Shape = Enum.PartType.Cylinder
	end
	marker(van, "StretcherSpot", at * CFrame.new(3.6, 0.5, 1.3) * CFrame.Angles(0, -math.pi / 2, 0))
	van:SetAttribute("ArriveAt", 0) -- Server/Patients sets it; Feel/HospitalFX flashes and sirens
	van.Parent = bay
end

------------------------------------------------------------------------------------------------------------------
-- Branch themes: one roof prop each (Data/Themes Prop, <= 6 parts, all walk-through)
------------------------------------------------------------------------------------------------------------------

-- Icicles hang under a roof's front edge (`edge`: its centre line, facing the street), with a snow lip on it.
local function propIcicles(parent: Instance, edge: CFrame, width: number)
	soft(part(parent, "Snow", Vector3.new(width, 0.35, 0.9), edge * CFrame.new(0, 0.12, 0), WHITE)).CastShadow = false
	local ice = lighten(CANDY.Blue, 0.6)
	for i = 1, 4 do
		local x = (i - 2.5) / 4 * width * 0.8
		local length = if i % 2 == 0 then 1.8 else 1.2
		local icicle = soft(
			part(
				parent,
				"Icicle",
				Vector3.new(0.45, length, 0.45),
				edge * CFrame.new(x, -length / 2, 0) * CFrame.Angles(0, math.rad(45), 0),
				ice
			)
		)
		icicle.Transparency = 0.15
		icicle.CastShadow = false
	end
end

local PROPS: { [string]: (Instance, CFrame, BuildingStyle) -> () } = {
	Palm = function(parent, at, _style)
		local height = 4.5
		soft(cylinder(parent, "Trunk", height, 0.7, at * CFrame.new(0, height / 2, 0), WORLD.Trunk))
		local crown = at * CFrame.new(0, height + 0.1, 0)
		for i = 0, 3 do
			soft(
				part(
					parent,
					"Leaf",
					Vector3.new(3.4, 0.2, 1.1),
					crown
						* CFrame.Angles(0, i * math.pi / 2, 0)
						* CFrame.new(1.5, -0.3, 0)
						* CFrame.Angles(0, 0, math.rad(-22)),
					WORLD.Leaves
				)
			).CastShadow =
				false
		end
		soft(ball(parent, "Coconut", 0.8, crown * CFrame.new(0.3, -0.5, 0.4), WORLD.Trunk)).CastShadow = false
	end,
	Rocket = function(parent, at, style)
		soft(cylinder(parent, "Body", 4, 1.7, at * CFrame.new(0, 2.2, 0), WHITE))
		soft(ball(parent, "Nose", 1.7, at * CFrame.new(0, 4.2, 0), style.Roof)).CastShadow = false
		for _, side in { -1, 1 } do
			soft(part(parent, "Fin", Vector3.new(0.25, 1.6, 1.4), at * CFrame.new(side * 0.95, 1, 0), style.Trim)).CastShadow =
				false
		end
		soft(ball(parent, "Window", 0.75, at * CFrame.new(0, 3, -0.75), style.Glass)).CastShadow = false
	end,
	Shell = function(parent, at, style)
		upright(parent, "Shell", 3.2, 0.4, at * CFrame.new(0, 1.3, 0), lighten(style.Trim, 0.2))
		for _, angle in { -35, 0, 35 } do
			soft(
				part(
					parent,
					"Rib",
					Vector3.new(0.2, 1.5, 0.3),
					at * CFrame.new(0, 1.3, -0.3) * CFrame.Angles(0, 0, math.rad(angle)) * CFrame.new(0, 0.75, 0),
					WHITE
				)
			).CastShadow =
				false
		end
		soft(ball(parent, "Pearl", 0.8, at * CFrame.new(0, 0.45, -0.5), WHITE)).CastShadow = false
	end,
	Crown = function(parent, at, style)
		soft(cylinder(parent, "Band", 1.1, 3, at * CFrame.new(0, 0.55, 0), style.Roof))
		for i = 0, 3 do
			local a = i * math.pi / 2 + math.pi / 4
			soft(ball(parent, "Point", 0.7, at * CFrame.new(math.cos(a) * 1.2, 1.45, math.sin(a) * 1.2), style.Roof)).CastShadow =
				false
		end
		soft(ball(parent, "Gem", 0.7, at * CFrame.new(0, 0.6, -1.45), style.Trim)).CastShadow = false
	end,
}

-- The theme's prop: icicles under `edge`, anything else standing at `spot` (both plot-local, facing the street).
local function themeProp(model: Model, style: BuildingStyle, level: number, spot: CFrame?, edge: CFrame?, width: number)
	if style.Prop == "" then
		return
	end
	local prop = piece(model, "ThemeProp", level)
	prop:SetAttribute("Theme", style.Theme)
	if style.Prop == "Icicles" then
		if edge and width > 0 then
			propIcicles(prop, edge, width)
		end
	elseif spot then
		local build = PROPS[style.Prop]
		if build then
			build(prop, spot, style)
		end
	end
	if #prop:GetChildren() == 0 then
		prop:Destroy()
	end
end

-- Lv 1 has no building, so a theme's prop goes on the Stand: standing on its awning's back, or (icicles) under the
-- awning's flap.
local function standSpots(plotModel: Model): (CFrame?, CFrame?, number)
	local rooms = plotModel:FindFirstChild("Rooms")
	local stand = rooms and rooms:FindFirstChild("Room_Stand")
	if not (stand and stand:IsA("Model")) then
		return nil, nil, 0
	end
	local pivot = plotModel:GetPivot()
	local box, size = stand:GetBoundingBox()
	local c = pivot:PointToObjectSpace(box.Position)
	local spot = CFrame.new(c.X - size.X * 0.27, c.Y + size.Y / 2 - 0.3, c.Z + size.Z / 2 - 1)
	local flap = stand:FindFirstChild("AwningFlap", true)
	if flap and flap:IsA("BasePart") then
		return spot, pivot:ToObjectSpace(flap.CFrame) * CFrame.new(0, -flap.Size.Y / 2, 0), flap.Size.X
	end
	return spot, nil, 0
end

------------------------------------------------------------------------------------------------------------------
-- Putting it together
------------------------------------------------------------------------------------------------------------------

local function kitBuilding(level: number, themeId: string): Model?
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
		elseif descendant:IsA("BasePart") and (descendant.Name == "Landing" or descendant.Name == "Landing_0") then
			liftPrompts(descendant) -- the brother's landings get the same prompts
		elseif descendant.Name == "Station_Pharmacy" then
			CollectionService:AddTag(descendant, HospitalBuilder.STATION_TAG)
		elseif descendant.Name == "Lift" and descendant:IsA("Model") then
			CollectionService:AddTag(descendant, HospitalBuilder.LIFT_TAG)
		end
	end
	if beds < extraBeds(level) then
		warn("[HospitalBuilder] ClinicKit.Building" .. level .. " needs " .. extraBeds(level) .. " Bed_<n> Parts")
	end
	local row = LevelsData[level]
	if row and row.Floors > 0 and not model:FindFirstChild("Landing_0") then
		warn("[HospitalBuilder] ClinicKit.Building" .. level .. " has no Landing_0: its lift won't work")
	end
	model:SetAttribute("Theme", themeId)
	return model
end

-- Builds the hospital in plot-local space (the plot's ground-top centre at the origin, -Z to the street). Beds whose
-- index is in `keep` are left out: the old ones move across.
local function placeholderBuilding(plotModel: Model, level: number, keep: { [number]: boolean }, themeId: string): Model
	local model = Instance.new("Model")
	local row = LevelsData[level]
	local accent = plotAccent(plotModel) or CANDY.Pink
	local style = buildingStyle(accent, themeId)
	local f = footprint(plotModel)
	local floors = if row then math.max(0, row.Floors) else 0
	if row and floors > 0 then
		local layout = Pure.layout(f)
		local indoor, roofWalkable = Pure.storeys(floors, ROOF_FLOOR)
		local top = Pure.slabY(f, indoor + 1) -- the roof's height (its slab's centre)
		buildLobby(model, f, style)
		for k = 1, floors do
			buildFloor(model, f, layout, style, k, k <= indoor)
		end
		landingMarker(model, "Landing_0", 0, f, layout)
		buildStairs(model, f, layout, style, floors)
		buildLift(
			model,
			layout,
			style,
			if roofWalkable then Pure.floorTop(f, floors) + Pure.CAR_HEIGHT + 0.6 else top - Pure.SLAB / 2
		)

		if hasDept(row, "Wards") and WARDS_FLOOR <= floors then
			local wards = piece(model, "Wards", sinceDept("Wards"))
			for index = 1, extraBeds(level) do
				if not keep[index] then
					wardBed(wards, f, layout, index, accent)
				end
			end
		end
		if hasDept(row, "Hydro") and HYDRO_FLOOR <= floors then
			buildHydro(model, f, layout)
		end
		if hasDept(row, "Pharmacy") and PHARMACY_FLOOR <= floors then
			buildPharmacy(model, f, layout)
		end
		if hasDept(row, "AE") then
			buildAmbulanceBay(model, style)
		end

		local sign = piece(model, "Sign", level)
		nameBoard(sign, CFrame.new(0, top - 1.15, f.Front - 0.16), math.min(f.Half * 1.1, 13), row.Name, style)
		local spot: CFrame?, edge: CFrame?, width = nil, nil, 0
		if roofWalkable then
			local roofTop = Pure.floorTop(f, floors)
			buildRoofTop(model, layout, roofTop)
			spot = buildTower(model, layout, style, roofTop)
			edge, width = CFrame.new(0, top - Pure.SLAB / 2, f.Front - Pure.OVERHANG), f.Half * 2 + Pure.OVERHANG * 2
		elseif indoor <= 1 then
			spot, edge, width = buildGable(model, f, style, top)
		else
			spot, edge, width = buildFlatRoof(model, f, style, top, level)
			crossSign(sign, CFrame.new(0, top + 3.95, f.Front + 1), 6, accent, false)
		end
		themeProp(model, style, level, spot, edge, width)
	else
		-- Lv 1: the open-air Stand. A branch theme still shows: its prop on the Stand.
		local spot, edge, width = standSpots(plotModel)
		themeProp(model, style, level, spot, edge, width)
	end
	model.WorldPivot = CFrame.identity
	model:PivotTo(plotModel:GetPivot())
	return model
end

function HospitalBuilder.build(plotModel: Model, level: number, grewFrom: number?, theme: string?): Model
	local row = LevelsData[level]
	local lv = if row then level else 1
	local themeId = themeOf(theme)
	local old = plotModel:FindFirstChild("Building")
	local model = kitBuilding(lv, themeId)
	if model then
		model:PivotTo(plotModel:GetPivot())
	else
		-- Keep the beds that stay (a patient may be resting on one): same index, same spot.
		local keep: { [number]: boolean } = {}
		if old then
			for index = 1, extraBeds(lv) do
				if old:FindFirstChild("BedSpot_" .. index, true) then
					keep[index] = true
				end
			end
		end
		model = placeholderBuilding(plotModel, lv, keep, themeId)
		local wards = (model :: Model):FindFirstChild("Wards")
		for index in keep do
			local spot = (old :: Instance):FindFirstChild("BedSpot_" .. index, true)
			if spot and wards then
				spot.Parent = wards
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
	building:SetAttribute("Floors", if LevelsData[lv] then LevelsData[lv].Floors else 0)
	building:SetAttribute("Theme", themeId)
	if old then
		old:Destroy()
	end
	building.Parent = plotModel
	plotModel:SetAttribute("Level", lv)
	plotModel:SetAttribute("Theme", themeId)
	return building
end

return HospitalBuilder
