--!strict
-- The clinic Building on a plot (the Real Clinic build plan, Task 1, contracts C1 and C2; design §8 and §15 #3).
-- Server only. OWNER: Task 1 (the building).
--   HospitalBuilder.build(plotModel, level, grewFrom?, theme?): Model
--       = PlotBuilder.buildBuilding (the same signature and attributes): the clinic at that level (Data/Levels) in
--       that branch theme (Data/Themes id; nil or unknown = Candy). Replaces Plot.Building, sets the Building's
--       Level, GrewFrom, GrewAt, Floors (OPEN floors above the ground), Storeys (floors that STAND above it), Theme
--       and Origin (the plot-local frame as a CFrame, for Feel/Cutaway) and the plot's Level and Theme attributes
--   HospitalBuilder.Pure          the building's own numbers (plot-local studs; PlotBuilder.Pure re-exports it;
--                                 tests/Hospital.spec loads the PURE block). Its functions take Shared/Logic/Building
--                                 (the interface numbers everyone else builds to) as their first argument
--   HospitalBuilder.syncStations(plotModel)
--       the pantry's stations (Logic/Building.STATIONS with a Room: Cocoa, Bath) follow the rooms the plot owns NOW:
--       their Open attribute, their badge (the icon, or 🔒 on a grey ring) and their "Needs ❄️ Winter Wing" hint.
--       build() calls it and hooks it to the plot's Rooms folder, so buying (or losing) a room needs no rebuild
--   HospitalBuilder.STATION_TAG   ("BuildingStation")  every Station_<id> part in the Building (Server/Stations)
--   HospitalBuilder.LIFT_TAG      ("HospitalLift")     each Building's Lift Model (UI/LiftPanel slides its car)
--   HospitalBuilder.DOOR_TAG      ("ClinicDoor")       each door Model (Server/World/Doors slides and locks them)
--   HospitalBuilder.PROMPT_TAGS   { Lift = "LiftPrompt", Escort = "EscortPrompt" }  (PlotBuilder re-exports all)
-- The plot's colour comes from the plot Model's `Accent` attribute (a Color3 PlotBuilder sets; its PlotIndex's
-- Palette.PlotColors entry when missing). It never requires PlotBuilder (PlotBuilder requires this).
--
-- THE BIG CLINIC (Joshua, 2026-11-17: "realistic and big enough from the first moment"). The whole 64 x 44 block
-- (Logic/Building, x -32..32, z -24..20) stands at EVERY level, with its tower over the back right (x -5..32,
-- z -5..20). A level only OPENS what is already there: bays, the A&E door, the X-ray room, the floors upstairs.
-- A closed door is shut and solid with a navy "🔒 Opens at Lv N" (or "💰 150 to open") plate; a closed bay has its
-- curtain drawn and a 🔒 sign; a closed station shows a 🔒 badge.
--   Ground floor (Storey 0), as the sketch in Logic/Building:
--     the front: a sliding glass pair (FrontDoor) in the middle, the canopy over it and the clinic's name floating
--       on the fascia; studded walls in the plot's colour with dark ribbon windows; the A&E door on the -x wall
--       (shut until Lv 2) with its red canopy; the Garden door in the back wall (shut until the Garden is bought)
--     the waiting room: 6 chairs (WaitSeat_<n> markers on their seats), a plant; ReceptionStop and ReceptionStaff
--       markers by the desk. The desk itself is the plot's Counter (Server/PlotBuilder): its rect is left clear
--     the dispensary: its glass hatch onto the lobby, Station_Remedy (the counter behind it, with drawers, bottles
--       and a measuring cup), bottle shelves
--     the nurses' station (NurseStation): a small desk at corridor A's far end, past the X-ray door, where Healers and
--       idle nurses wait (Logic/Building.NURSE_STATION)
--     the exam bays 1-6 in a row (ExamBay_<id>: a couch, a curtain, a tool tray, a number sign, the DoctorSpot)
--     the supply alcove between the two corridors: Station_Plaster (a supply cabinet with a box of plasters),
--       Station_Ice (a freezer chest with ice cubes on its lid), Station_Bandage (an open shelf of bandage rolls)
--     the X-ray room (shut until Lv 3): ExamBay_X under the X-ray arm, Station_Cast (a work table on legs: a tray of
--       plaster rolls and a bucket)
--     the pantry, in the hall behind the supply alcove, against the stairs' rail (memory-20261117-006: "move the hot
--       cocoa into like a pantry"): Station_Cocoa (a small counter with a cocoa pot and two mugs; open while the
--       Winter Wing is owned) and Station_Bath (an open shelf of bath-foam bottles and a towel stack; open while the
--       Bath Room is owned). Closed, each wears 🔒 and a floating hint naming its room (RoomHint)
--     the Bath Room, Winter Wing and Cozy Ward behind their doors (shut until bought; their fit-outs are
--       PlotBuilder's, ExamBay_W1/W2 included), the lift (glass shaft, door on its -x face) and the dog-leg stairs
--       (tiled steps over an invisible walking ramp a half-flight)
--   Upstairs (Floor_<n>, Storey n): F1 the Injury Ward (stands from Lv 1, shut; opens at Lv 2), F2 the Rest Ward
--     (Lv 3), F3 the staff room with more Rest beds (Lv 4); each with its slab, landing, glass front band, studded
--     walls, ribbon windows and a row of beds: BedSpot_<k> (Model; Floor, Ward) round Bed_<k> (the mattress; Floor,
--     Ward) for the functional beds (Logic/Building.wardBeds), made-up beds (Dressing.DressBed_<k>, never named Bed_*)
--     for the rest, one with a sleeper. A floor that stands but isn't open (F1 at Lv 1) has every bed made up and no
--     Landing. Lv 5: Floor_4 is the roof deck (the helipad, Roof.HeliSpot) and the lift tower with the neon sign
--   AmbulanceBay (Lv 2+) in the -x yard (Logic/Building.BAY_AMBULANCE): the Ambulance and the StretcherSpot
-- Contract C2's markers are DIRECT children of the Building: FrontDoor, ReceptionStop, WaitSeat_<n>, ExamBay_<id>,
-- Station_<id>, Landing_0, Lift, Stairs, Floor_<n>, AmbulanceBay, Roof (with HeliSpot). Facing: a marker's LookVector
-- is its Logic/Building Face (a WaitSeat_<n> looks where its sitter looks, a DoctorSpot at its bed, a landing into
-- the lift); a marker RESTS on its surface (its bottom face is the seat top, the floor), like the lift landings.
-- An ExamBay_<id> Model's Bed is the couch the patient sits on (its top at Pure.COUCH; its LookVector toward the
-- foot, where the DoctorSpot is), with the attributes Bay, Kind, Opens, Face and Open (level >= Opens).
-- Station_<id> parts carry Open (Logic/Building.stationOpen, with the plot's rooms), StationId and, the pantry's,
-- Room (the RoomId that opens it), and are tagged STATION_TAG. Each is
-- Logic/Building.stationRect's box from the floor (what stops you; invisible round the open shelf and the table) with
-- its walk-through furniture as its own children and its IconGui badge over that furniture.
--
-- Pieces. Every direct child carries Since (the level that adds it: Feel/HospitalFX grows only those in) and Storey
-- (0 = the ground ... 4 = the roof deck; a part may carry its own). Feel/Cutaway hides every part whose Storey is
-- above the floor you stand on and fades your floor's parts with Outer = true.
-- Themes (Data/Themes): the outer walls always stay the plot's Accent (kids find "the pink one"). A theme recolours
-- only the parts with the attribute Paint: "Trim" (the door's piers, the canopy's edge, the rails) takes its Trim
-- hex, "Band" (the fascia stripe and the top roof's edge band) its Roof hex; plus its prop. Theme colours are capped
-- at 240 a channel.
-- Night (World/NightLights): the glass and the ribbon windows are "Window"; the neon paw-heart, the beacon and the
-- ambulance's sirens are "Lamp". One shadowless night light per building (Lv 5, on the paw-heart); the room lights
-- are shadowless PointLights on Attachments.
-- Budget (Config.Look): <= BuildingParts parts at every level and theme, <= SurfaceGuisPerBuilding SurfaceGuis (each
-- with a MaxDistance), <= GlassPerBuilding see-through parts, no Texture, no Decal, nothing named or shaped like a
-- cross. Floors, slabs and flights are CeramicTiles, never wood. tests/Hospital.spec measures them.
-- Solid. Everything solid at walking height inside the footprint is inside Shared/Logic/Building.obstacles (the
-- bought rooms' shut doors aside: obstacles counts those as open); door panels are solid only while locked.
--
-- ServerStorage.ClinicKit.Building<level> (pivot = the plot's ground-top centre, facing the street) replaces the
-- placeholder for that level: it needs the same names (FrontDoor, WaitSeat_<n>, ExamBay_<id>, Station_<id>,
-- Landing_0, Floor_<n>.Landing, Lift ...). Its stations, doors and lift get their tags and its landings their prompts.
--
-- Coordinates: plot-local studs, the plot's ground-top centre at the origin, x right as you face the street, -z the
-- street, y up. The Building's pivot is the plot's.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local Departments = require(Shared.Data.Departments)
local ItemsData = require(Shared.Data.Items)
local LevelsData = require(Shared.Data.Levels)
local PatientsData = require(Shared.Data.Patients)
local RoomsData = require(Shared.Data.Rooms)
local Stations = require(Shared.Data.Stations)
local Themes = require(Shared.Data.Themes)
local BuildingLogic = require(Shared.Logic.Building)
local Doors = require(script.Parent.World.Doors)
local NightLights = require(script.Parent.World.NightLights)
local Parts = require(script.Parent.World.Parts)
local Studs = require(script.Parent.World.Studs)

local part, soft, cylinder = Parts.part, Parts.soft, Parts.cylinder
local marker, paint, band, disc = Parts.marker, Parts.paint, Parts.band, Parts.disc
local surface, iconBadge, floatText, navyPlate = Parts.surface, Parts.iconBadge, Parts.floatText, Parts.navyPlate
local anchorAll, scrubScripts = Parts.anchorAll, Parts.scrubScripts

local HospitalBuilder = {}

HospitalBuilder.STATION_TAG = "BuildingStation"
HospitalBuilder.LIFT_TAG = "HospitalLift"
HospitalBuilder.DOOR_TAG = Doors.TAG
HospitalBuilder.PROMPT_TAGS = table.freeze({ Lift = "LiftPrompt", Escort = "EscortPrompt" })

-- PURE-BEGIN
-- The building's own numbers (no Roblox types, no requires): tests/Hospital.spec loads this block on its own. `B` is
-- Shared/Logic/Building: the footprint, rooms, doors, bays, stations, shaft, landing, stairs and beds come from there;
-- what is only the building's own (heights, thicknesses, the flights' parts, the chairs, the signs) is here.
local Pure = {}

-- Every slab and roof (Logic/Building.SLAB_MAX): F1's underside is at 11.4, over the 10.4 it must clear.
Pure.SLAB = 0.6
-- The tall doorways' height (Logic/Building.DOORS Height, raised from 8; Joshua 2026-11-17: "the door is so low,
-- things look cluttered"; the front pair and the dispensary's stay 8): the bays' header and dividers start here. Each
-- lintel starts at its own door's Height.
Pure.DOOR = 10
-- An open door's panel slides this far past its jamb into the wall, so its edge never lies flush with the jamb's face
-- (two faces in one plane flicker).
Pure.TUCK = 0.1
Pure.BAND = 0.5 -- the fascia stripe's height, at the top of the ground storey's façade
Pure.SPANDREL = 2.4 -- an upper storey's studded wall under its front glass band
Pure.GLASS = 0.55 -- the see-through parts: the front doors, the hatch, the glass bands, the lift shaft
Pure.CAR = 7.5 -- the lift car's height: a 6.5-stud creature rides inside with room over its head
Pure.CLEAR = 0.5 -- Lv 5: the shaft's glass reaches this far over the car standing at the roof
Pure.HEAD = 4.5 -- Lv 5: the lift tower's head over the shaft (the neon paw-heart's wall)
Pure.LIFT_HEAD = 2.5 -- Lv 1-4: the lift's head box on the top roof
Pure.PAINT = 0.05 -- the ground floor's painted tiles (walk-through: markers and patients stand at 0)
Pure.PROUD = 0.1 -- trim and ribbon windows stand this far proud of an outer face
Pure.CEILING = 0.4 -- the ground storey's light ceiling under the podium's dark roof
Pure.PARAPET = 1.2
Pure.RAIL = { Height = 3, Thick = 0.3 }
-- A half-flight's walking ramp: a tilted slab this thick, INVISIBLE (the steps are what you see; Joshua, 2026-11-17:
-- "look at how this block is glitchy"). It carries the walker; a storey of headroom under the next one.
Pure.RAMP = 0.6
-- The steps you see: STEPS risers a half-flight (a going of 1.5, a riser of 0.75 or 0.69), every tread's nose on the
-- ramp's line. On the ground each step is a solid block from the floor up (nothing hides under the stairs); upstairs
-- each reaches WAIST under the riser below it (a stepped underside) and is walk-through.
Pure.STEPS = 8
Pure.WAIST = 0.6
Pure.WINDOW = { Y0 = 3.5, Y1 = 7 } -- ribbon windows, from the storey's floor
Pure.HATCH = { Sill = 3, Top = 7 } -- the dispensary's glass hatch over its counter
Pure.COUCH = 1.8 -- an exam bay's Bed: its top, where the patient sits
-- The lift's prompts. Upstairs they sit over the landing and reach Reach studs. The GROUND landing stands 2.5 studs
-- from the X-ray room's back wall, and a prompt needs no line of sight, so there the PromptPoint stands Away studs
-- along the hall from the landing's middle (+z, away from that wall) and reaches only GroundReach: far enough for
-- anyone in the hall in front of the lift, too short for the X-ray bay's DoctorSpot behind the wall (where "Lift"
-- would take the tap meant for Examine or Treat).
Pure.LIFT_PROMPT = { Reach = 8, GroundReach = 4.5, Away = 1.5 }
-- The stations' furniture (Joshua, 2026-11-17: "the cabinets / places to take the bandage ... now its just a
-- rectangular block"). Each Station_<id> part keeps Logic/Building.stationRect's box from the floor up to its Height
-- (the supply cabinet and freezer, the bandage shelf, the cast table and the dispensary counter); what makes it look
-- like the thing is its own children (see buildStation).
Pure.STATION = {
	Plaster = 3, -- the supply cabinet's body (its countertop and the box of plasters sit on it)
	Ice = 2.6, -- the freezer chest's body (its lid on it)
	Bandage = 4.6, -- the open shelf unit (an invisible box round it: the shelves are open)
	Cast = 3.2, -- the work table's top (an invisible box round it: the table stands on legs)
	Remedy = 3, -- the dispensary counter's body (its countertop on it)
	Cocoa = 3, -- the pantry's cocoa counter's body (its countertop, the pot and the mugs on it)
	Bath = 4.6, -- the pantry's shelf unit (an invisible box round it: bath-foam bottles and towels on open shelves)
}
-- A room-gated station's hint while it is closed (a BillboardGui over its badge: no part, no SurfaceGui): which room
-- opens it. A room is bought with in-game cash at its own door (the price is on the door, never here).
Pure.HINT = { Width = 7, Height = 1, Over = 1.9, MaxDistance = 45 }
function Pure.roomHint(room: any): string
	local icon = if type(room) == "table" and type(room.Icon) == "string" then room.Icon .. " " else ""
	local name = if type(room) == "table" and type(room.Name) == "string" then room.Name else "a room"
	return "Needs " .. icon .. name
end
Pure.TOP = 0.3 -- a countertop's (and the freezer lid's) thickness
-- The nurses' station's desk (Logic/Building.NURSE_STATION.Desk): its body's height (counter height, like the
-- dispensary's), with a countertop and a clipboard on it. Three parts: the Building was near its budget.
Pure.NURSE_DESK = 3
Pure.BADGE = 1.6 -- a station's icon badge floats this far over its furniture's highest point
Pure.SEAT = { Height = 1.6, Back = 0.6, BackHeight = 4 } -- a waiting-room chair: the seat, its back
Pure.PANEL = 0.2 -- a door panel's thickness, in its wall's middle
Pure.SIGN = { Width = 3, Y0 = 10.1, Y1 = 11.3, Out = 0.1 } -- a bay's number sign on the header over its mouth
-- A bay's curtain: hung this far inside the mouth; drawn back it is Bunch wide at one side, drawn shut across. It
-- hangs from just under the bays' header (Pure.DOOR).
Pure.CURTAIN = { Inset = 0.5, Bunch = 1, Height = 9.3, Thick = 0.2, Half = 3 }
Pure.XRAY = { Head = 9, HeadTop = 10, Width = 2.8, Depth = 2.4 } -- the scanner over bay X (clear of a sitter's head)
Pure.LOGO = 6 -- the paw-heart sign on the tower's roof edge (Lv 1-4)
-- A ward bed. Functional: Frame + Headboard + Bed_<k> (the mattress). Made up: Base (frame and mattress in one block)
-- + Headboard.
Pure.BED = {
	Width = 4.4, -- the frame (= Logic/Building.BED_HALF * 2)
	FrameHeight = 0.8,
	Headboard = 4, -- whole studs across (studded)
	HeadboardHeight = 2.6,
	HeadboardThick = 0.5,
	Mattress = 4,
	MattressHeight = 1,
	MattressLength = 6.2,
	FootStep = 1.6, -- Server/Patients.bedFoot: a patient waits 1.6 past the mattress's foot
	DressHeight = 1.6, -- a made-up bed's Base
}
-- A sleeper: a head on the pillow and a blanket over the foot two-thirds (blocky, like every creature).
Pure.SLEEPER = { Width = 2, Height = 1.8, Depth = 1.8, Blocky = true, Blanket = 0.5 }
-- The roof deck (Lv 5): the planters behind the helipad, and where a theme's prop stands (front right of the top
-- roof or the deck, off the pad, the lift and the stairs).
Pure.PLANTERS = { { X = -2.5, Z = 16.5 }, { X = 1.5, Z = 16.5 } }
Pure.PLANTER = 2
Pure.PROP = { X = 22, Z = -1 }
Pure.CAP = 240 -- no world colour brighter than this in any channel (theme colours are capped to it)

type Rect = { X0: number, X1: number, Z0: number, Z1: number }
type Named = { Name: string, X0: number, X1: number, Z0: number, Z1: number }
type Span = { Z0: number, Z1: number }
-- A half-flight's walking surface: from its -x end (XL, YL) to its +x end (XR, YR), across Z0..Z1.
export type Ramp = { XL: number, YL: number, XR: number, YR: number, Z0: number, Z1: number }

-- How many floors above the ground STAND at a level: Logic/Building.storeys, plus the roof deck once it is open.
function Pure.standing(B: any, level: number): number
	return B.storeys(level) + (if B.floors(level) >= #B.SLAB_TOPS then 1 else 0)
end

-- The first level at which floor k stands (Since of its pieces) ...
function Pure.sinceStanding(B: any, k: number): number
	for level = B.MIN_LEVEL, B.MAX_LEVEL do
		if Pure.standing(B, level) >= k then
			return level
		end
	end
	return B.MAX_LEVEL
end

-- ... and the first level at which it is open (its landing, its working beds).
function Pure.sinceOpen(B: any, k: number): number
	for level = B.MIN_LEVEL, B.MAX_LEVEL do
		if B.floors(level) >= k then
			return level
		end
	end
	return B.MAX_LEVEL
end

-- The top roof over `standing` floors: its top is the next slab top.
function Pure.roofTop(B: any, standing: number): number
	return B.slabTop(standing + 1)
end

-- Storey k's walls stand up to the next slab's (or roof's) underside ...
function Pure.wallTop(B: any, k: number): number
	return B.slabTop(k + 1) - Pure.SLAB
end

-- ... from its own slab's underside (the ground's from the ground).
function Pure.wallBase(B: any, k: number): number
	return if k <= 0 then 0 else B.slabTop(k) - Pure.SLAB
end

-- The glass shaft: up under the top roof, or (the roof deck) past the car standing at the roof.
function Pure.shaftTop(B: any, standing: number, roofFloor: number): number
	if standing >= roofFloor then
		return B.slabTop(standing) + Pure.CAR + Pure.CLEAR
	end
	return Pure.roofTop(B, standing) - Pure.SLAB
end

-- An upper floor's slab, in pieces: the tower inside its walls (the walls stand on their own from the slab's
-- underside), less the lift shaft and the stairwell. "Slab" is the piece the landing stands on (Floor_<n>.Slab).
function Pure.slabRects(B: any): { Named }
	local t, w, s, well = B.TOWER, B.WALL, B.SHAFT, B.STAIRWELL
	local x0, x1, z0, z1 = t.X0 + w, t.X1 - w, t.Z0 + w, t.Z1 - w
	local out: { Named } = {}
	local function add(name: string, a0: number, a1: number, b0: number, b1: number)
		if a1 - a0 > 1e-6 and b1 - b0 > 1e-6 then
			table.insert(out, { Name = name, X0 = a0, X1 = a1, Z0 = b0, Z1 = b1 })
		end
	end
	add("SlabFront", x0, x1, z0, s.Z0)
	add("Slab", x0, s.X0, s.Z0, s.Z1)
	add("SlabSide", s.X1, x1, s.Z0, s.Z1)
	add("SlabMid", x0, x1, s.Z1, well.Z0)
	add("SlabBack", x0, well.X0, well.Z0, z1)
	add("SlabEnd", well.X1, x1, well.Z0, z1)
	add("SlabRear", well.X0, well.X1, well.Z1, z1)
	return out
end

-- Storey k's half-flights (Logic/Building's dog-leg): lane A from the floor's landing up toward +x to the mid
-- landing, lane B from there back to the next floor. Lane B stops Pure.RAMP x sin(slope) short of the landing, so its
-- tilted slab stays inside the stairwell (a 0.27-stud step onto the landing). Across, each lane stops at the faces it
-- meets, never inside them: lane A between the rail along the well's front edge and the wall between the lanes, lane
-- B between that wall and the back wall.
function Pure.ramp(B: any, k: number, lane: string): Ramp
	local y0, y1 = B.slabTop(k), B.slabTop(k + 1)
	local rise = (y1 - y0) / 2
	local half = B.DIVIDER / 2
	if lane == "A" then
		local l = B.LANE_A
		return {
			XL = l.X0,
			YL = y0,
			XR = l.X1,
			YR = y0 + rise,
			Z0 = l.Z0 + Pure.RAIL.Thick,
			Z1 = l.Z1 - half,
		}
	end
	local l = B.LANE_B
	local run = l.X1 - l.X0
	local shift = Pure.RAMP * rise / math.sqrt(run * run + rise * rise)
	return { XL = l.X0 + shift, YL = y1 - rise * shift / run, XR = l.X1, YR = y0 + rise, Z0 = l.Z0 + half, Z1 = l.Z1 }
end

export type Step = { X0: number, X1: number, Top: number, Rise: number }

-- Storey k's steps on one lane, from the bottom up: tread i (0 .. STEPS - 1) runs one going back from its nose, which
-- lies on the ramp's line (Pure.ramp, before lane B's cut), and its top is i risers over the half-flight's foot. Lane
-- A's tread 0 is level with the floor it starts from (on the ground that is the floor itself); lane B's is level with
-- the mid landing. The last riser rises onto the landing (lane A) or the next floor (lane B).
function Pure.steps(B: any, k: number, lane: string): { Step }
	local y0, y1 = B.slabTop(k), B.slabTop(k + 1)
	local rise = (y1 - y0) / 2
	local n = Pure.STEPS
	local l = if lane == "A" then B.LANE_A else B.LANE_B
	local going = (l.X1 - l.X0) / n
	local r = rise / n
	local out: { Step } = {}
	for i = 0, n - 1 do
		if lane == "A" then
			table.insert(out, { X0 = l.X0 + i * going, X1 = l.X0 + (i + 1) * going, Top = y0 + i * r, Rise = r })
		else
			table.insert(out, { X0 = l.X1 - (i + 1) * going, X1 = l.X1 - i * going, Top = y0 + rise + i * r, Rise = r })
		end
	end
	return out
end

-- A half-flight's part: its centre, its length along the slope and its tilt about z (radians; + rises toward +x).
function Pure.rampFrame(r: Ramp, thick: number): { X: number, Y: number, Z: number, Length: number, Angle: number }
	local dx, dy = r.XR - r.XL, r.YR - r.YL
	local angle = math.atan2(dy, dx)
	return {
		X = (r.XL + r.XR) / 2 + thick / 2 * math.sin(angle),
		Y = (r.YL + r.YR) / 2 - thick / 2 * math.cos(angle),
		Z = (r.Z0 + r.Z1) / 2,
		Length = math.sqrt(dx * dx + dy * dy),
		Angle = angle,
	}
end

-- The box round a half-flight's part (its four edges across x and y).
function Pure.rampBox(r: Ramp, thick: number): { X0: number, X1: number, Y0: number, Y1: number }
	local angle = math.atan2(r.YR - r.YL, r.XR - r.XL)
	local bx, by = thick * math.sin(angle), -thick * math.cos(angle)
	return {
		X0 = math.min(r.XL, r.XR, r.XL + bx, r.XR + bx),
		X1 = math.max(r.XL, r.XR, r.XL + bx, r.XR + bx),
		Y0 = math.min(r.YL, r.YR, r.YL + by, r.YR + by),
		Y1 = math.max(r.YL, r.YR, r.YL + by, r.YR + by),
	}
end

-- A wall from z0 to z1 with gaps (doorways) left open, as the spans that stand.
function Pure.segments(z0: number, z1: number, gaps: { Span }): { Span }
	local sorted = table.clone(gaps)
	table.sort(sorted, function(a, b)
		return a.Z0 < b.Z0
	end)
	local out: { Span } = {}
	local at = z0
	for _, gap in sorted do
		local stop = math.min(gap.Z0, z1)
		if stop - at > 1e-6 then
			table.insert(out, { Z0 = at, Z1 = stop })
		end
		at = math.max(at, gap.Z1)
	end
	if z1 - at > 1e-6 then
		table.insert(out, { Z0 = at, Z1 = z1 })
	end
	return out
end

-- A waiting-room chair inside its seat's rect (Logic/Building.seatRect): the seat, and its back behind the sitter.
function Pure.chair(B: any, seat: any): { Cushion: Rect, Back: Rect }
	local r = B.seatRect(seat)
	local dx, dz = B.facing(seat.Face) -- where the sitter looks: the back is the other side
	local b = Pure.SEAT.Back
	if dx > 0 then
		return {
			Cushion = { X0 = r.X0 + b, X1 = r.X1, Z0 = r.Z0, Z1 = r.Z1 },
			Back = { X0 = r.X0, X1 = r.X0 + b, Z0 = r.Z0, Z1 = r.Z1 },
		}
	elseif dx < 0 then
		return {
			Cushion = { X0 = r.X0, X1 = r.X1 - b, Z0 = r.Z0, Z1 = r.Z1 },
			Back = { X0 = r.X1 - b, X1 = r.X1, Z0 = r.Z0, Z1 = r.Z1 },
		}
	elseif dz > 0 then
		return {
			Cushion = { X0 = r.X0, X1 = r.X1, Z0 = r.Z0 + b, Z1 = r.Z1 },
			Back = { X0 = r.X0, X1 = r.X1, Z0 = r.Z0, Z1 = r.Z0 + b },
		}
	end
	return {
		Cushion = { X0 = r.X0, X1 = r.X1, Z0 = r.Z0, Z1 = r.Z1 - b },
		Back = { X0 = r.X0, X1 = r.X1, Z0 = r.Z1 - b, Z1 = r.Z1 },
	}
end

-- The words on a closed door's plate (short: a kid reads them at a glance).
function Pure.levelLock(opens: number): string
	return "🔒 Opens at Lv " .. tostring(opens)
end

-- A bought room's door: its name, then the level it needs (Data/Rooms Level) or its price (cash, in game).
function Pure.roomLock(level: number, room: any): { string }
	local icon = if type(room) == "table" and type(room.Icon) == "string" then room.Icon .. " " else ""
	local name = if type(room) == "table" and type(room.Name) == "string" then room.Name else "Room"
	local gate = if type(room) == "table" then room.Level else nil
	if type(gate) == "number" and level < gate then
		return { icon .. name, Pure.levelLock(gate) }
	end
	local price = if type(room) == "table" and type(room.Price) == "number" then room.Price else 0
	return { icon .. name, "💰 " .. tostring(math.floor(price)) .. " to open" }
end

-- A main-ward mattress's centre z: its foot spot (Server/Patients.bedFoot) lands on Logic/Building.BED_FOOT_Z.
function Pure.mattressZ(B: any): number
	return B.BED_FOOT_Z - (Pure.BED.MattressLength / 2 + Pure.BED.FootStep)
end

-- Which of `count` made-up beds get a sleeper, spread out: 2 of 4 -> 1 and 3.
function Pure.sleepers(beds: number, count: number): { [number]: boolean }
	local out: { [number]: boolean } = {}
	local n = math.clamp(math.floor(count), 0, beds)
	for j = 1, n do
		out[math.floor((j - 1) * beds / n) + 1] = true
	end
	return out
end

-- A colour (0..255 a channel) scaled down so no channel passes Pure.CAP: bleached theme whites become warm greys.
function Pure.tame(r: number, g: number, b: number): (number, number, number)
	local top = math.max(r, g, b)
	if top <= Pure.CAP then
		return r, g, b
	end
	local k = Pure.CAP / top
	return r * k, g * k, b * k
end
-- PURE-END

HospitalBuilder.Pure = Pure

local B = BuildingLogic

local WORLD = Palette.World
local ACCENT = Palette.Accent

-- A department's colour (Palette.Departments), with a stand-in should it ever list none.
local function deptColor(dept: string, fallback: Color3): Color3
	local color = rawget(Palette.Departments :: any, dept)
	return if typeof(color) == "Color3" then color else fallback
end
local WARDS_COLOR = deptColor("Wards", ACCENT.Purple)
local REST_COLOR = deptColor("Rest", ACCENT.Blue)
local IMAGING_COLOR = deptColor("Imaging", ACCENT.Blue)
local HYDRO_COLOR = deptColor("Hydro", ACCENT.Cyan)
local AE_COLOR = deptColor("AE", ACCENT.Red)
local INSIDE = WORLD.WallUpper -- the inside walls: warm white, studded
local COUCH_COLOR = Parts.lighten(ACCENT.Cyan, 0.45)
local CURTAIN_COLOR = Parts.lighten(ACCENT.Blue, 0.5)
local CLOSED_RING = WORLD.Edge -- a closed station's badge ring

local function deptRow(dept: string): any
	local row = rawget(Departments :: any, dept)
	return if type(row) == "table" then row else nil
end
local ROOF_FLOOR = (deptRow("Roof") and deptRow("Roof").Floor) or #B.SLAB_TOPS
local AE_OPENS = (deptRow("AE") and deptRow("AE").Opens) or 2

-- The icon on floor k's glass band: the first department on it (Data/Departments), else the staff room's.
local function floorIcon(k: number): string
	for _, id in Departments.Order do
		local row = deptRow(id)
		if row and row.Floor == k and type(row.Icon) == "string" then
			return row.Icon
		end
	end
	return if k == 3 then "🛋️" else "🏥"
end

local function wardColor(ward: string?): Color3
	return if ward == "Rest" then REST_COLOR else WARDS_COLOR
end

------------------------------------------------------------------------------------------------------------------
-- Colours
------------------------------------------------------------------------------------------------------------------

local function tame(color: Color3): Color3
	local r, g, b = Pure.tame(color.R * 255, color.G * 255, color.B * 255)
	return Color3.fromRGB(math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5))
end

local function hexColor(hex: any, fallback: Color3): Color3
	if type(hex) == "string" and string.match(hex, "^#%x%x%x%x%x%x$") then
		local ok, color = pcall(Color3.fromHex, hex)
		if ok then
			return tame(color)
		end
	end
	return fallback
end

-- The plot's own colour: the `Accent` attribute PlotBuilder sets, else its PlotIndex's Palette.PlotColors entry.
local function plotAccent(plotModel: Model): Color3
	local accent = plotModel:GetAttribute("Accent")
	if typeof(accent) == "Color3" then
		return accent
	end
	local index = plotModel:GetAttribute("PlotIndex")
	local colors = Palette.PlotColors
	if type(index) == "number" then
		return colors[(index - 1) % #colors + 1]
	end
	return colors[1]
end

type Style = {
	Accent: Color3, -- the plot's own colour: the walls, the chairs, the car, the paw-heart. Never themed
	Trim: Color3, -- Paint "Trim": the door's piers, the canopy's edge, the rails (a theme's Trim hex)
	Band: Color3, -- Paint "Band": the fascia stripe and the top roof's edge band (a theme's Roof hex)
	Theme: string,
	Prop: string,
}

-- A Data/Themes id and its row; anything unknown is the default (Candy).
local function themeOf(themeId: any): (string, any)
	local row = if type(themeId) == "string" then rawget(Themes :: any, themeId) else nil
	if type(row) == "table" then
		return themeId, row
	end
	return Themes.Default, rawget(Themes :: any, Themes.Default)
end

local function buildingStyle(accent: Color3, themeId: string?): Style
	local id, theme = themeOf(themeId)
	return {
		Accent = accent,
		Trim = hexColor(theme.Trim, WORLD.Trim),
		Band = hexColor(theme.Roof, WORLD.Trim),
		Theme = id,
		Prop = if type(theme.Prop) == "string" then theme.Prop else "",
	}
end

-- A creature's colour for a sleeper's head (Data/Patients looks, in order), capped like every world colour.
local function creatureColor(index: number): Color3
	local order = PatientsData.Order
	local id = order[(index - 1) % #order + 1]
	local row = rawget(PatientsData :: any, id)
	local look = if type(row) == "table" then row.Look else nil
	return hexColor(if type(look) == "table" then look.Body else nil, ACCENT.Orange)
end

------------------------------------------------------------------------------------------------------------------
-- Part helpers (plot-local boxes)
------------------------------------------------------------------------------------------------------------------

local function box(
	parent: Instance,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	color: Color3,
	material: Enum.Material?
): Part
	return part(
		parent,
		name,
		Vector3.new(x1 - x0, y1 - y0, z1 - z0),
		CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
		color,
		material
	)
end

local function piece(parent: Instance, name: string, since: number, storey: number): Model
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("Since", since)
	model:SetAttribute("Storey", storey)
	model.Parent = parent
	return model
end

-- A loose part straight under the Building carries its own Since and Storey.
local function loose<T>(p: T, since: number, storey: number): T
	local instance = p :: any
	instance:SetAttribute("Since", since)
	instance:SetAttribute("Storey", storey)
	return p
end

-- An outer wall: studded, the plot's colour, solid. Its name starts with "Wall".
local function outerWall(
	parent: Instance,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	style: Style
): Part
	local p = box(parent, name, x0, x1, y0, y1, z0, z1, style.Accent)
	Studs.apply(p)
	p:SetAttribute("Outer", true)
	return p
end

-- An inside wall: studded warm white, solid.
local function partition(
	parent: Instance,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number
): Part
	local p = box(parent, name, x0, x1, y0, y1, z0, z1, INSIDE)
	Studs.apply(p)
	return p
end

-- A part a theme recolours: "Trim" or "Band".
local function painted(p: BasePart, paintRole: string): BasePart
	p:SetAttribute("Paint", paintRole)
	return p
end

-- See-through glass (the bands, the hatch, the shaft): warm at night.
local function glass(
	parent: Instance,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number
): Part
	local p = box(parent, name, x0, x1, y0, y1, z0, z1, WORLD.Glass, Enum.Material.Glass)
	p.Transparency = Pure.GLASS
	p.CastShadow = false
	NightLights.tag(p, "Window")
	return p
end

-- A dark ribbon window on an outer face (soft paint; warm at night). Its name starts with "Window".
local function ribbon(
	parent: Instance,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number
)
	if x1 - x0 < 1 and z1 - z0 < 1 then
		return
	end
	local p = paint(box(parent, name, x0, x1, y0, y1, z0, z1, WORLD.Window))
	p:SetAttribute("Outer", true)
	NightLights.tag(p, "Window")
end

-- A room's own light: shadowless (the perf budget), always on, warm white, on an Attachment (no part).
local ROOM_LIGHT_BRIGHTNESS = 1.1
local ROOM_LIGHT_RANGE = 24
local function roomLight(anchor: BasePart, at: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.Name = "RoomLight"
	attachment.Position = anchor.CFrame:PointToObjectSpace(at)
	attachment.Parent = anchor
	local light = Instance.new("PointLight")
	light.Color = WORLD.WallUpper
	light.Brightness = ROOM_LIGHT_BRIGHTNESS
	light.Range = ROOM_LIGHT_RANGE
	light.Shadows = false
	light.Parent = attachment
end

-- A SurfaceGui with a holder Frame filling it (for Parts.pawHeart, which draws into a GuiObject).
local function holder(gui: SurfaceGui, size: UDim2, position: UDim2): Frame
	local f = Instance.new("Frame")
	f.Name = "Mark"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size
	f.Position = position
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Parent = gui
	return f
end

-- A disc standing upright and facing the street (Roblox cylinders run along X, so it is turned to face -Z). Its
-- Right face is the one toward the street.
local function upright(parent: Instance, name: string, diameter: number, thick: number, at: CFrame, color: Color3)
	local p = part(parent, name, Vector3.new(thick, diameter, diameter), at * CFrame.Angles(0, math.rad(90), 0), color)
	p.Shape = Enum.PartType.Cylinder
	soft(p)
	return p
end

-- The paw-heart on a disc facing the street (our placeholder mark; never a cross).
local function pawSign(parent: Instance, name: string, at: CFrame, diameter: number, style: Style): Part
	local p = upright(parent, name, diameter, 0.4, at, WORLD.Trim)
	local gui = surface(p, "LogoGui", Enum.NormalId.Right, 30, 400, 0)
	Parts.pawHeart(holder(gui, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5)), UDim2.fromScale(1, 1), style.Accent)
	return p
end

-- A navy plate with one or two lines on a part's face: a closed door's lock, the stair gate's.
local function lockGui(p: BasePart, face: Enum.NormalId, lines: { string }, enabled: boolean): SurfaceGui
	local gui = surface(p, "LockGui", face, 24, 60, 0)
	gui.Enabled = enabled
	navyPlate(gui, { Size = UDim2.fromScale(0.94, 0.32), Position = UDim2.fromScale(0.5, 0.34) })
	for i, text in lines do
		floatText(gui, text, {
			Size = UDim2.fromScale(0.84, 0.12),
			Position = UDim2.fromScale(0.08, 0.205 + (i - 1) * 0.14),
		})
	end
	return gui
end

------------------------------------------------------------------------------------------------------------------
-- The doors (Server/World/Doors slides and locks them)
------------------------------------------------------------------------------------------------------------------

type DoorSpec = {
	Key: string, -- Logic/Building.DOORS
	Name: string,
	Pair: boolean?, -- DoorL + DoorR (the front doors); else one Panel
	Slide: number, -- a Panel slides this way along its wall (-1 / 1, in its own x)
	Face: Enum.NormalId, -- the side its lock plate is on (where people come from)
	Color: Color3,
	Glass: boolean?,
	Title: string?, -- a level-gated door's name on its plate
}

local DOOR_SPECS: { DoorSpec } = {
	{
		Key = "Front",
		Name = "FrontDoor",
		Pair = true,
		Slide = 1,
		Face = Enum.NormalId.Back,
		Color = WORLD.Glass,
		Glass = true,
	},
	{ Key = "AE", Name = "Door_AE", Slide = 1, Face = Enum.NormalId.Back, Color = AE_COLOR, Title = "🚑 A&E" },
	{
		Key = "XRay",
		Name = "Door_XRay",
		Slide = -1,
		Face = Enum.NormalId.Front,
		Color = IMAGING_COLOR,
		Title = "📸 X-ray",
	},
	{ Key = "BathRoom", Name = "Door_BathRoom", Slide = -1, Face = Enum.NormalId.Front, Color = HYDRO_COLOR },
	{ Key = "WinterWing", Name = "Door_WinterWing", Slide = -1, Face = Enum.NormalId.Front, Color = ACCENT.Blue },
	{ Key = "CozyWard", Name = "Door_CozyWard", Slide = -1, Face = Enum.NormalId.Front, Color = WARDS_COLOR },
	{ Key = "Garden", Name = "Door_Garden", Slide = 1, Face = Enum.NormalId.Front, Color = WORLD.LeavesA },
}

local NO_ROOMS: { [string]: boolean } = table.freeze({}) -- for a station no room gates

-- The rooms the plot owns now (Plot.Rooms.Room_<RoomId>).
local function ownedRooms(plotModel: Model): { [string]: boolean }
	local owned: { [string]: boolean } = {}
	local rooms = plotModel:FindFirstChild("Rooms")
	if rooms then
		for _, child in rooms:GetChildren() do
			local id = string.match(child.Name, "^Room_(%w+)$")
			if id then
				owned[id] = true
			end
		end
	end
	return owned
end

local function buildDoor(model: Model, level: number, owned: { [string]: boolean }, spec: DoorSpec)
	local d = B.DOORS[spec.Key]
	if not d then
		return
	end
	local doorModel = Instance.new("Model")
	doorModel.Name = spec.Name
	loose(doorModel, 1, 0)
	doorModel:SetAttribute("Door", spec.Key)
	if d.Opens then
		doorModel:SetAttribute("Opens", d.Opens)
	end
	if d.Room then
		doorModel:SetAttribute("Room", d.Room)
	end
	local alongX = d.X0 ~= nil and d.X1 ~= nil
	local width: number, cx: number, cz: number
	if alongX then
		width, cx, cz = (d.X1 :: number) - (d.X0 :: number), ((d.X0 :: number) + (d.X1 :: number)) / 2, d.Z :: number
	else
		width, cx, cz = (d.Z1 :: number) - (d.Z0 :: number), d.X :: number, ((d.Z0 :: number) + (d.Z1 :: number)) / 2
	end
	-- The panels' own x runs along the wall (a wall along z: turned a quarter, so their +x is the world's -z).
	local turn = if alongX then CFrame.identity else CFrame.Angles(0, math.rad(90), 0)
	local frame = CFrame.new(cx, d.Height / 2, cz) * turn
	local locked = Doors.Pure.locked(level, d.Opens, d.Room, d.Room ~= nil and owned[d.Room] == true)
	local panels: { BasePart } = {}
	if spec.Pair then
		for i, name in { "DoorL", "DoorR" } do
			local side = if i == 1 then -1 else 1
			local p = part(
				doorModel,
				name,
				Vector3.new(width / 2, d.Height, Pure.PANEL),
				frame * CFrame.new(side * width / 4, 0, 0),
				spec.Color
			)
			p:SetAttribute("Slide", Vector3.new(side * (width / 2 + Pure.TUCK), 0, 0))
			table.insert(panels, p)
		end
	else
		local p = part(doorModel, "Panel", Vector3.new(width, d.Height, Pure.PANEL), frame, spec.Color)
		p:SetAttribute("Slide", Vector3.new(spec.Slide * (width + Pure.TUCK), 0, 0))
		table.insert(panels, p)
	end
	for _, p in panels do
		p.CanCollide = locked -- an open door is walk-through: it only looks shut
		p.CanTouch = false
		p.CastShadow = false
		if spec.Glass then
			p.Material = Enum.Material.Glass
			p.Transparency = Pure.GLASS
			NightLights.tag(p, "Window")
		end
	end
	local lines: { string }? = nil
	if d.Room then
		lines = Pure.roomLock(level, rawget(RoomsData :: any, d.Room))
	elseif d.Opens and level < d.Opens then
		lines = { spec.Title or "", Pure.levelLock(d.Opens) }
	end
	if lines then
		lockGui(panels[1], spec.Face, lines, locked)
	end
	marker(doorModel, "Sensor", CFrame.new(cx, 0.5, cz) * turn)
	doorModel:SetAttribute("State", if locked then "Locked" else "Shut")
	CollectionService:AddTag(doorModel, Doors.TAG)
	doorModel.Parent = model
end

------------------------------------------------------------------------------------------------------------------
-- The ground storey
------------------------------------------------------------------------------------------------------------------

-- The outer walls, the façade (the name, the canopy, the stripe, the door's piers), the A&E canopy, the windows,
-- the podium's roof and the ground's ceiling and tiled floor.
local function buildShell(model: Model, style: Style, levelName: string)
	local shell = piece(model, "Shell", 1, 0)
	local hx, f, bk, w = B.HALF_X, B.FRONT, B.BACK, B.WALL
	local top = Pure.wallTop(B, 0)
	local doors = B.DOORS
	local front, ae, garden = doors.Front, doors.AE, doors.Garden
	local x0, x1 = front.X0 :: number, front.X1 :: number
	local wy0, wy1 = Pure.WINDOW.Y0, Pure.WINDOW.Y1
	local out = Pure.PROUD

	-- The street face: studded walls either side of the front doors, the fascia over them with the name. Each wall
	-- ends inside its door pier (Pier, below), so the jamb is the pier's face alone (two faces in one plane flicker).
	local tuck = 0.25 -- the walls stop this far inside the 0.5-wide piers
	outerWall(shell, "WallFrontLeft", -hx, x0 - tuck, 0, front.Height, f, f + w, style)
	outerWall(shell, "WallFrontRight", x1 + tuck, hx, 0, front.Height, f, f + w, style)
	local fascia = outerWall(shell, "WallFascia", -hx, hx, front.Height, top, f, f + w, style)
	local canopy = B.CANOPY
	local under = canopy.Y - 0.25 - 0.15
	local height = top - front.Height
	local nameWidth = 20 -- studs, centred over the doors and under the canopy
	floatText(surface(fascia, "NameGui", Enum.NormalId.Front, 24, 220, 0), levelName, {
		Shadow = true,
		Size = UDim2.fromScale(nameWidth / (2 * hx), (under - front.Height - 0.2) / height),
		Position = UDim2.fromScale((hx - nameWidth / 2) / (2 * hx), (top - under) / height),
	})
	-- The door's warm frame, and the fascia stripe (a theme's roof band), proud of the façade.
	for _, xs in { { x0 - 0.5, x0 }, { x1, x1 + 0.5 } } do
		painted(paint(box(shell, "Pier", xs[1], xs[2], 0, front.Height, f - out, f + w + out, style.Trim)), "Trim")
	end
	painted(
		paint(box(shell, "PierTop", x0 - 0.5, x1 + 0.5, front.Height, front.Height + 0.4, f - out, f, style.Trim)),
		"Trim"
	)
	painted(
		paint(box(shell, "BandFascia", -hx - 0.15, hx + 0.15, top - Pure.BAND, top, f - 0.15, f, style.Band)),
		"Band"
	)
	-- The canopy over the front doors: soft and overhead.
	soft(
		box(
			shell,
			"RoofCanopy",
			canopy.X0,
			canopy.X1,
			canopy.Y - 0.25,
			canopy.Y + 0.25,
			canopy.Z0,
			canopy.Z1,
			WORLD.Roof
		)
	)
	painted(
		paint(
			box(
				shell,
				"TrimCanopy",
				canopy.X0 - 0.15,
				canopy.X1 + 0.15,
				canopy.Y - 0.35,
				canopy.Y + 0.35,
				canopy.Z0 - 0.15,
				canopy.Z0 + 0.15,
				style.Trim
			)
		),
		"Trim"
	)
	ribbon(shell, "WindowFront", -hx + 2, x0 - 3, wy0, wy1, f - out, f)
	ribbon(shell, "WindowFront", x1 + 3, hx - 2, wy0, wy1, f - out, f)

	-- The back, with the Garden door.
	local g0, g1 = garden.X0 :: number, garden.X1 :: number
	outerWall(shell, "WallBackLeft", -hx, g0, 0, top, bk - w, bk, style)
	outerWall(shell, "WallBackRight", g1, hx, 0, top, bk - w, bk, style)
	outerWall(shell, "WallLintelGarden", g0, g1, garden.Height, top, bk - w, bk, style)
	ribbon(shell, "WindowBack", -hx + 2, g0 - 2, wy0, wy1, bk, bk + out)
	ribbon(shell, "WindowBack", g1 + 2, hx - 2, wy0, wy1, bk, bk + out)

	-- The -x side, with the A&E door, its red canopy and the letters over it (facing the ambulance bay).
	local a0, a1 = ae.Z0 :: number, ae.Z1 :: number
	outerWall(shell, "WallLeftFront", -hx, -hx + w, 0, top, f + w, a0, style)
	outerWall(shell, "WallLeftBack", -hx, -hx + w, 0, top, a1, bk - w, style)
	local lintelAE = outerWall(shell, "WallLintelAE", -hx, -hx + w, ae.Height, top, a0, a1, style)
	floatText(surface(lintelAE, "AEGui", Enum.NormalId.Left, 30, 160, 0), "A&E", {
		Shadow = true,
		Size = UDim2.fromScale(0.9, 0.5),
		Position = UDim2.fromScale(0.05, 0.3),
	})
	soft(box(shell, "CanopyAE", -hx - 2, -hx, ae.Height + 0.6, ae.Height + 1, a0 - 0.5, a1 + 0.5, AE_COLOR))
	paint(
		box(shell, "RoofEdgeAE", -hx - 2.2, -hx - 2, ae.Height + 0.4, ae.Height + 1.1, a0 - 0.5, a1 + 0.5, WORLD.Roof)
	)
	ribbon(shell, "WindowLeft", -hx - out, -hx, wy0, wy1, f + 2, a0 - 2)
	ribbon(shell, "WindowLeft", -hx - out, -hx, wy0, wy1, a1 + 2, bk - 2)

	-- The +x side.
	outerWall(shell, "WallRight", hx - w, hx, 0, top, f + w, bk - w, style)
	ribbon(shell, "WindowRight", hx, hx + out, wy0, wy1, f + 2, bk - 2)

	-- The tiled floor (painted over the pad) and the ground's lights, and its light ceiling.
	local floorPart = paint(
		box(
			shell,
			"FloorGround",
			-hx + 0.1,
			hx - 0.1,
			Pure.PAINT - 0.04,
			Pure.PAINT,
			f + 0.1,
			bk - 0.1,
			WORLD.FloorTile,
			Enum.Material.CeramicTiles
		)
	)
	for _, at in { Vector3.new(-16, top - 1, -14), Vector3.new(16, top - 1, -12), Vector3.new(0, top - 1, 8) } do
		roomLight(floorPart, at)
	end
	local t = B.TOWER
	local c = Pure.CEILING
	box(shell, "Ceiling", -hx + w, hx - w, top, top + c, f + w, t.Z0 + w, INSIDE)
	box(shell, "Ceiling", -hx + w, t.X0 + w, top, top + c, t.Z0 + w, bk - w, INSIDE)

	-- The podium's dark roof round the tower, up to the tower's walls (they stand on the ceiling: buildFloor), and a
	-- low parapet on the street.
	local roof = piece(model, "PodiumRoof", 1, 1)
	box(roof, "RoofPodium", -hx - 0.2, hx + 0.2, top + c, B.GROUND, f - 0.2, t.Z0, WORLD.Roof)
	box(roof, "RoofPodium", -hx - 0.2, t.X0, top + c, B.GROUND, t.Z0, bk + 0.2, WORLD.Roof)
	box(roof, "ParapetPodium", -hx - 0.2, hx + 0.2, B.GROUND, B.GROUND + 0.8, f - 0.2, f + w, WORLD.Roof)
end

-- The waiting room's chairs (WaitSeat_<n> on their seats) and plant, and the reception markers.
local function buildWaiting(model: Model, style: Style)
	local waiting = piece(model, "Waiting", 1, 0)
	local s = Pure.SEAT
	local backColor = Parts.darken(style.Accent, 0.15)
	for index, seat in B.SEATS do
		local c = Pure.chair(B, seat)
		box(waiting, "Chair", c.Cushion.X0, c.Cushion.X1, 0, s.Height, c.Cushion.Z0, c.Cushion.Z1, style.Accent)
		box(waiting, "ChairBack", c.Back.X0, c.Back.X1, 0, s.BackHeight, c.Back.Z0, c.Back.Z1, backColor)
		local seatMarker = loose(
			marker(
				model,
				"WaitSeat_" .. index,
				CFrame.new(seat.X, s.Height + 0.5, seat.Z) * CFrame.Angles(0, math.rad(seat.Face), 0)
			),
			1,
			0
		)
		seatMarker:SetAttribute("Seat", index)
		seatMarker:SetAttribute("Face", seat.Face)
	end
	local p = B.PLANTER
	Studs.apply(box(waiting, "Pot", p.X0, p.X1, 0, 1.6, p.Z0, p.Z1, WORLD.PlankAlt))
	Studs.apply(box(waiting, "Leaves", p.X0 + 0.15, p.X1 - 0.15, 1.6, 4.2, p.Z0 + 0.15, p.Z1 - 0.15, WORLD.LeavesA))
	local r = B.RECEPTION
	loose(
		marker(model, "ReceptionStop", CFrame.new(r.Stop.X, 0.5, r.Stop.Z) * CFrame.Angles(0, math.rad(180), 0)),
		1,
		0
	)
	loose(marker(model, "ReceptionStaff", CFrame.new(r.Staff.X, 0.5, r.Staff.Z)), 1, 0)
end

------------------------------------------------------------------------------------------------------------------
-- The stations' furniture (Joshua, 2026-11-17: "the texture of the cabinets / places to take the bandage should be
-- improved. now its just a rectangular block")
------------------------------------------------------------------------------------------------------------------

-- A box in a station's own frame (`frame`: Logic/Building's centre and Face, on the floor): x across its Width, y up
-- from the floor, z from its front (-Depth/2, the side the player stands on) to its back (+Depth/2, at the wall).
-- Walk-through: the Station_<id> part itself is what stops anyone.
local function fit(
	parent: Instance,
	name: string,
	frame: CFrame,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	color: Color3,
	material: Enum.Material?
): Part
	local p = part(
		parent,
		name,
		Vector3.new(x1 - x0, y1 - y0, z1 - z0),
		frame * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
		color,
		material
	)
	soft(p)
	return p
end

-- A small detail casts no shadow (the perf budget).
local function tiny<T>(p: T): T
	(p :: any).CastShadow = false
	return p
end

-- An upright cylinder standing on y0 in a station's frame (rolls, bottles, the bucket, the measuring cup).
local function cylinderOn(
	parent: Instance,
	name: string,
	frame: CFrame,
	x: number,
	y0: number,
	z: number,
	height: number,
	diameter: number,
	color: Color3
): Part
	local p = cylinder(parent, name, height, diameter, frame * CFrame.new(x, y0 + height / 2, z), color)
	soft(p)
	return p
end

local PLASTER_TAN = Color3.fromRGB(226, 182, 138) -- a sticking plaster
local COCOA_BROWN = Color3.fromRGB(122, 74, 46) -- the pantry's cocoa pot
-- Half a station's width in its own frame (Logic/Building.stationRect: the pantry's units are narrower than 4).
local function stationHalf(id: string): number
	local station = B.STATIONS[id]
	return ((station and station.Width) or B.STATION_SIZE.Width) / 2
end
local function bottleColor(itemId: string, fallback: Color3): Color3
	local row = rawget(ItemsData :: any, itemId)
	return hexColor(if type(row) == "table" then row.Bottle else nil, fallback)
end

-- Each station's furniture round its part `p` (in `color`, the station's own, capped). Returns the furniture's
-- highest point (its badge floats Pure.BADGE over it). Sizes: Logic/Building.STATION_SIZE, 4 across and 2.4 deep.
type Furnish = (p: Part, frame: CFrame, color: Color3) -> number
local OPEN_FURNITURE: { [string]: boolean } = { Bandage = true, Cast = true, Bath = true } -- an invisible box round it
local FURNISH: { [string]: Furnish } = {
	-- 🩹 A supply cabinet: the pink body (the part) with two doors and their knobs, a white countertop, and on it a box
	-- of plasters (its lid pink) and a plaster.
	Plaster = function(p, frame, color)
		local h, t = Pure.STATION.Plaster, Pure.TOP
		local door = tame(Parts.lighten(color, 0.3))
		for _, side in { -1, 1 } do
			local x0, x1 = if side < 0 then -1.85 else 0.06, if side < 0 then -0.06 else 1.85
			fit(p, "Door", frame, x0, x1, 0.35, h - 0.25, -1.3, -1.2, door)
			tiny(fit(p, "Knob", frame, side * 0.32 - 0.15, side * 0.32 + 0.15, 1.6, 1.9, -1.45, -1.3, WORLD.Trim))
		end
		fit(p, "Countertop", frame, -2, 2, h, h + t, -1.35, 1.2, WORLD.Trim)
		local y = h + t
		fit(p, "PlasterBox", frame, -1.5, 0.1, y, y + 0.7, -0.5, 0.6, WORLD.Trim)
		fit(p, "PlasterBoxLid", frame, -1.55, 0.15, y + 0.7, y + 0.9, -0.55, 0.65, color)
		tiny(fit(p, "Plaster", frame, 0.5, 1.7, y, y + 0.08, -0.6, -0.2, PLASTER_TAN))
		tiny(fit(p, "PlasterPad", frame, 0.95, 1.25, y + 0.08, y + 0.12, -0.55, -0.25, WORLD.Trim))
		return y + 0.9
	end,
	-- 🧊 A freezer chest: the white body (the part), its lid in the station's colour with a handle, ice cubes on top.
	Ice = function(p, frame, color)
		local h, t = Pure.STATION.Ice, Pure.TOP
		fit(p, "Lid", frame, -2, 2, h, h + t, -1.3, 1.2, color)
		tiny(fit(p, "Handle", frame, -0.8, 0.8, h + 0.04, h + t - 0.04, -1.45, -1.3, Palette.Navy))
		local y = h + t
		local ice = tame(Parts.lighten(color, 0.6))
		local top = y
		for _, c in { { -0.9, -0.15, 0.7, 15 }, { 0.15, 0.35, 0.6, -20 }, { 1, -0.25, 0.55, 35 } } do
			local size = c[3]
			local cube = tiny(
				part(
					p,
					"IceCube",
					Vector3.one * size,
					frame * CFrame.new(c[1], y + size / 2, c[2]) * CFrame.Angles(0, math.rad(c[4]), 0),
					ice,
					Enum.Material.Ice
				)
			)
			soft(cube)
			cube.Transparency = 0.3
			top = math.max(top, y + size)
		end
		return top
	end,
	-- 🧻 An open shelf unit in the station's colour (the part is an invisible box round it): two sides, a darker back,
	-- four boards, and white bandage rolls standing on three of them.
	Bandage = function(p, frame, color)
		local h, w = Pure.STATION.Bandage, 0.3
		for _, side in { -1, 1 } do
			local x0 = if side < 0 then -2 else 2 - w
			fit(p, "ShelfSide", frame, x0, x0 + w, 0, h, -1.2, 1.2, color)
		end
		fit(p, "ShelfBack", frame, -2 + w, 2 - w, 0, h, 1.2 - w, 1.2, tame(Parts.darken(color, 0.25)))
		local boards = { 0, 1.4, 2.8, h - w }
		for _, y in boards do
			fit(p, "ShelfBoard", frame, -2 + w, 2 - w, y, y + w, -1.2, 1.2 - w, color)
		end
		for b, xs in { { -0.55, 0.55 }, { -1.05, 0, 1.05 }, { -0.55, 0.55 } } do
			for _, x in xs do
				cylinderOn(p, "BandageRoll", frame, x, boards[b] + w, -0.2, 0.8, 0.9, WORLD.Trim)
			end
		end
		return h
	end,
	-- 🦴 A work table on four legs (the part is an invisible box round it) with a low shelf, a steel tray of white
	-- plaster rolls and a small bucket.
	Cast = function(p, frame, color)
		local h, t, leg = Pure.STATION.Cast, Pure.TOP, 0.3
		local legColor = tame(Parts.darken(color, 0.3))
		fit(p, "TableTop", frame, -2, 2, h - t, h, -1.2, 1.2, color)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local x0 = if sx < 0 then -2 else 2 - leg
				local z0 = if sz < 0 then -1.2 else 1.2 - leg
				fit(p, "TableLeg", frame, x0, x0 + leg, 0, h - t, z0, z0 + leg, legColor)
			end
		end
		fit(p, "TableShelf", frame, -2 + leg, 2 - leg, 0.5, 0.8, -1.2, 1.2, color)
		tiny(fit(p, "Tray", frame, -1.7, 0.3, h, h + 0.15, -0.8, 0.8, WORLD.Edge))
		local d = 0.5
		for _, z in { -0.35, 0.3 } do
			local rollPart =
				part(p, "CastRoll", Vector3.new(1.2, d, d), frame * CFrame.new(-0.7, h + 0.15 + d / 2, z), WORLD.Trim)
			rollPart.Shape = Enum.PartType.Cylinder
			tiny(soft(rollPart))
		end
		cylinderOn(p, "Bucket", frame, 1.15, h, 0, 0.9, 0.9, tame(ACCENT.Blue))
		return h + 0.9
	end,
	-- 💊 The dispensary counter: the purple body (the part) with four drawers and their pulls, a white countertop, and
	-- on it three medicine bottles (their colours from Data/Items) and a measuring cup.
	Remedy = function(p, frame, color)
		local h, t = Pure.STATION.Remedy, Pure.TOP
		local drawer = tame(Parts.lighten(color, 0.3))
		for _, xs in { { -1.85, -0.08 }, { 0.08, 1.85 } } do
			for _, ys in { { 0.35, 1.45 }, { 1.65, h - 0.25 } } do
				fit(p, "Drawer", frame, xs[1], xs[2], ys[1], ys[2], -1.3, -1.2, drawer)
				local mx, my = (xs[1] + xs[2]) / 2, (ys[1] + ys[2]) / 2
				tiny(fit(p, "Pull", frame, mx - 0.4, mx + 0.4, my - 0.07, my + 0.07, -1.42, -1.3, WORLD.Trim))
			end
		end
		fit(p, "Countertop", frame, -2, 2, h, h + t, -1.35, 1.2, WORLD.Trim)
		local y = h + t
		local bottles = {
			{ -1.3, 0.3, "FeverMeds", ACCENT.Orange },
			{ -0.6, 0.55, "EarDrops", ACCENT.Blue },
			{ 0.1, 0.3, "Cream", ACCENT.Cyan },
		}
		for _, b in bottles do
			cylinderOn(p, "Bottle", frame, b[1], y, b[2], 0.8, 0.5, bottleColor(b[3], b[4]))
			tiny(cylinderOn(p, "BottleCap", frame, b[1], y + 0.8, b[2], 0.2, 0.3, WORLD.Trim))
		end
		tiny(cylinderOn(p, "MeasuringCup", frame, 1.1, y, -0.3, 0.6, 0.6, WORLD.Trim))
		return y + 1
	end,
	-- ☕ The pantry's cocoa counter: the orange body (the part) with one wide door, a white countertop, and on it a
	-- chocolate-brown pot with its lid and two white mugs. (Its width is Logic/Building.PANTRY's, not 4.)
	Cocoa = function(p, frame, color)
		local h, t = Pure.STATION.Cocoa, Pure.TOP
		local half = stationHalf("Cocoa")
		fit(p, "Door", frame, -half + 0.15, half - 0.15, 0.35, h - 0.25, -1.3, -1.2, tame(Parts.lighten(color, 0.3)))
		fit(p, "Countertop", frame, -half, half, h, h + t, -1.35, 1.2, WORLD.Trim)
		local y = h + t
		cylinderOn(p, "CocoaPot", frame, -0.7, y, 0.2, 0.9, 1.1, COCOA_BROWN)
		tiny(cylinderOn(p, "CocoaPotLid", frame, -0.7, y + 0.9, 0.2, 0.2, 0.6, WORLD.Trim))
		for _, x in { 0.45, 1.1 } do
			tiny(cylinderOn(p, "Mug", frame, x, y, -0.35, 0.55, 0.5, WORLD.Trim))
		end
		return y + 1.1
	end,
	-- 🛁 The pantry's bath shelf: an open shelf unit in the station's blue (the part is an invisible box round it):
	-- two sides, a darker back, three boards, bottles of bath foam on the middle board and a stack of two towels on
	-- the bottom one.
	Bath = function(p, frame, color)
		local h, w = Pure.STATION.Bath, 0.3
		local half = stationHalf("Bath")
		for _, side in { -1, 1 } do
			local x0 = if side < 0 then -half else half - w
			fit(p, "ShelfSide", frame, x0, x0 + w, 0, h, -1.2, 1.2, color)
		end
		fit(p, "ShelfBack", frame, -half + w, half - w, 0, h, 1.2 - w, 1.2, tame(Parts.darken(color, 0.25)))
		local boards = { 0, 2.1, h - w }
		for _, y in boards do
			fit(p, "ShelfBoard", frame, -half + w, half - w, y, y + w, -1.2, 1.2 - w, color)
		end
		for i, x in { -0.75, 0, 0.75 } do
			local foam = if i == 2 then tame(ACCENT.Cyan) else tame(ACCENT.Pink)
			tiny(cylinderOn(p, "FoamBottle", frame, x, boards[2] + w, -0.2, 1.1, 0.55, foam))
		end
		for i = 1, 2 do
			local y0 = boards[1] + w + (i - 1) * 0.5
			local towel = fit(p, "Towel", frame, -0.8, 0.8, y0, y0 + 0.5, -0.8, 0.5, WORLD.Trim, Enum.Material.Fabric)
			tiny(towel)
		end
		return h
	end,
}

-- A station's floating badge: its icon in its own colour's ring, or 🔒 on a grey ring while it is closed. `height`
-- is the badge's offset over the part's centre. A room-gated station's RoomHint shows only while it is closed.
local function stationBadge(p: BasePart, id: string, open: boolean, height: number)
	local data = rawget(Stations :: any, id)
	local color = if data and typeof(data.Color) == "Color3" then data.Color else WORLD.Trim
	iconBadge(
		p,
		"IconGui",
		if open and data then data.Icon else "🔒",
		if open then color else CLOSED_RING,
		2.6,
		height
	)
	local hint = p:FindFirstChild("RoomHint")
	if hint and hint:IsA("BillboardGui") then
		hint.Enabled = not open
	end
end

-- A station in the Building: Station_<id> (tagged), Logic/Building.stationRect's box from the floor up to its Height,
-- with its furniture as its own children and its icon badge over it (🔒 on a grey ring while closed; a closed station
-- looks the same otherwise, so kids see what's coming). The body keeps the station's colour where it is one solid
-- body (the cabinet, the counters; the freezer is white with a coloured lid), and the open furniture (the shelves, the
-- table) is coloured itself round an invisible box. `owned`: the rooms the plot owns (the pantry's stations open with
-- theirs; closed, each also floats a hint naming its room).
local function buildStation(model: Model, id: string, level: number, owned: { [string]: boolean })
	local r = B.stationRect(id)
	local station = B.STATIONS[id]
	if not (r and station) then
		return
	end
	local data = rawget(Stations :: any, id)
	-- The ring is the station's own candy colour (kids match a plan step to it); the furniture's is the same, capped
	-- like every world colour.
	local color = if data and typeof(data.Color) == "Color3" then data.Color else WORLD.Trim
	local height = rawget(Pure.STATION :: any, id) or 3
	local open = B.stationOpen(id, level, owned)
	local body = if id == "Ice" then WORLD.Trim else tame(color)
	local p = loose(box(model, "Station_" .. id, r.X0, r.X1, 0, height, r.Z0, r.Z1, body), 1, 0)
	p:SetAttribute("StationId", id)
	p:SetAttribute("Open", open)
	local frame = CFrame.new(station.X, 0, station.Z) * CFrame.Angles(0, math.rad(station.Face), 0)
	local furnish = FURNISH[id]
	local top = if furnish then furnish(p, frame, tame(color)) else height
	if OPEN_FURNITURE[id] then
		p.Transparency = 1 -- open furniture: the part is only the box that stops you
		p.CastShadow = false
	end
	local badgeAt = top + Pure.BADGE - height / 2
	if station.Room then
		p:SetAttribute("Room", station.Room)
		local hint = Instance.new("BillboardGui")
		hint.Name = "RoomHint"
		hint.Size = UDim2.fromScale(Pure.HINT.Width, Pure.HINT.Height)
		hint.StudsOffsetWorldSpace = Vector3.new(0, badgeAt + Pure.HINT.Over, 0)
		hint.LightInfluence = 0
		hint.MaxDistance = Pure.HINT.MaxDistance
		floatText(hint, Pure.roomHint(rawget(RoomsData :: any, station.Room)))
		hint.Parent = p
	end
	stationBadge(p, id, open, badgeAt)
	CollectionService:AddTag(p, HospitalBuilder.STATION_TAG)
end

-- The pantry's stations follow the rooms the plot owns now (see the header): Open, the badge and the hint. A kit
-- Building's Station_Cocoa / Station_Bath get their Open the same way (their look is the kit's own).
function HospitalBuilder.syncStations(plotModel: Model)
	local building = plotModel:FindFirstChild("Building")
	if not building then
		return
	end
	local level = building:GetAttribute("Level")
	local owned = ownedRooms(plotModel)
	for id, station in B.STATIONS do
		local p = if station.Room then building:FindFirstChild("Station_" .. id, true) else nil
		if p then
			local open = B.stationOpen(id, if type(level) == "number" then level else 1, owned)
			if p:GetAttribute("Open") ~= open then
				p:SetAttribute("Open", open)
				local badge = p:FindFirstChild("IconGui")
				if p:IsA("BasePart") and p:FindFirstChild("RoomHint") and badge and badge:IsA("BillboardGui") then
					local height = badge.StudsOffsetWorldSpace.Y
					badge:Destroy()
					stationBadge(p, id, open, height)
				end
			end
		end
	end
end

-- Hooks syncStations to a plot's Rooms folder, once per plot (PlotBuilder makes the folder with the plot; a room is
-- named Room_<id> before it is parented).
local watching: { [Instance]: boolean } = {}
local function watchRooms(plotModel: Model)
	local rooms = plotModel:FindFirstChild("Rooms")
	if not rooms or watching[rooms] then
		return
	end
	watching[rooms] = true
	local function changed()
		HospitalBuilder.syncStations(plotModel)
	end
	rooms.ChildAdded:Connect(changed)
	rooms.ChildRemoved:Connect(changed)
end

-- The dispensary: the wall onto the lobby with its glass hatch over the counter (Station_Remedy), the wall onto
-- corridor A with its open doorway and sign, and the bottle shelves.
local function buildDispensary(model: Model, level: number)
	local disp = piece(model, "Dispensary", 1, 0)
	local r = B.ROOMS.Dispensary
	local p, w = B.PARTITION, B.WALL
	local top = Pure.wallTop(B, 0)
	local hatch = B.HATCH
	local x0, x1 = r.X0, r.X0 + p
	partition(disp, "WallHatch", x0, x1, 0, top, B.FRONT + w, hatch.Z0)
	partition(disp, "WallHatch", x0, x1, 0, top, hatch.Z1, r.Z1)
	partition(disp, "HatchSill", x0, x1, 0, Pure.HATCH.Sill, hatch.Z0, hatch.Z1)
	partition(disp, "HatchHeader", x0, x1, Pure.HATCH.Top, top, hatch.Z0, hatch.Z1)
	glass(disp, "GlassHatch", x0 + 0.1, x1 - 0.1, Pure.HATCH.Sill, Pure.HATCH.Top, hatch.Z0, hatch.Z1)
	local d = B.DOORS.Dispensary
	local d0, d1 = d.X0 :: number, d.X1 :: number
	partition(disp, "WallDispensary", x1, d0, 0, top, r.Z1 - p, r.Z1)
	partition(disp, "WallDispensary", d1, r.X1 - w, 0, top, r.Z1 - p, r.Z1)
	local lintel = partition(disp, "LintelDispensary", d0, d1, d.Height, top, r.Z1 - p, r.Z1)
	local sign = surface(lintel, "SignGui", Enum.NormalId.Back, 24, 80, 0)
	navyPlate(sign, { Size = UDim2.fromScale(0.94, 0.6), Position = UDim2.fromScale(0.5, 0.45) })
	floatText(sign, "💊 Dispensary", { Size = UDim2.fromScale(0.84, 0.4), Position = UDim2.fromScale(0.08, 0.25) })
	-- The shelves: the long one along the +x wall carries the coloured bottles (seen through the hatch).
	local side, back = B.SHELVES[1], B.SHELVES[2]
	local shelf =
		box(disp, "ShelfBottles", side.X0, side.X1, 0, 7, side.Z0, side.Z1, WORLD.PlankAlt, Enum.Material.WoodPlanks)
	box(disp, "Shelf", back.X0, back.X1, 0, 7, back.Z0, back.Z1, WORLD.PlankAlt, Enum.Material.WoodPlanks)
	local gui = surface(shelf, "BottleGui", Enum.NormalId.Left, 16, 80)
	local bottles = { ACCENT.Pink, ACCENT.Yellow, ACCENT.Cyan, ACCENT.Purple, ACCENT.Orange, ACCENT.Blue }
	for row = 1, 3 do
		for col = 1, 8 do
			local bottle = band(
				gui,
				"Bottle",
				UDim2.fromScale(0.06, 0.11),
				UDim2.fromScale((col - 0.5) / 8, 0.12 + (row - 1) * 0.28),
				bottles[(col + row - 2) % #bottles + 1]
			)
			Parts.rounded(bottle, UDim.new(0.35, 0))
		end
	end
	buildStation(model, "Remedy", level, NO_ROOMS)
end

-- The nurses' station (Logic/Building.NURSE_STATION; Joshua 2026-11-17: "nurses look like theyre in the middle of
-- nowhere"): a small desk at corridor A's far end, where Healers and idle nurses wait. Like the station furniture: a
-- calm blue body (solid: Logic/Building's NurseDesk obstacle), a white countertop overhanging the corridor side, and a
-- clipboard on it. No sign, no emblem. Three parts.
local function buildNurseStation(model: Model)
	local station = piece(model, "NurseStation", 1, 0)
	local d = B.NURSE_STATION.Desk
	local h, t = Pure.NURSE_DESK, Pure.TOP
	box(station, "Desk", d.X0, d.X1, 0, h, d.Z0, d.Z1, tame(ACCENT.Blue))
	soft(box(station, "Countertop", d.X0 - 0.15, d.X1, h, h + t, d.Z0, d.Z1, WORLD.Trim))
	local cx, cz = (d.X0 + d.X1) / 2, (d.Z0 + d.Z1) / 2
	tiny(soft(box(station, "Clipboard", cx - 0.3, cx + 0.3, h + t, h + t + 0.08, cz - 0.4, cz + 0.4, WORLD.PlankAlt)))
end

-- One exam bay: ExamBay_<id> (Bed, Pillow, Curtain, Tray, Sign, DoctorSpot). `signAt` is its number sign's
-- middle, on the corridor side of the wall over its mouth.
local function buildBay(model: Model, bay: any, level: number, signAt: Vector3)
	local open = B.bayOpen(bay, level)
	local bayModel = Instance.new("Model")
	bayModel.Name = "ExamBay_" .. bay.Id
	loose(bayModel, 1, 0)
	bayModel:SetAttribute("Bay", bay.Id)
	bayModel:SetAttribute("Kind", bay.Kind)
	bayModel:SetAttribute("Opens", bay.Opens)
	bayModel:SetAttribute("Face", bay.Face)
	bayModel:SetAttribute("Open", open)
	-- The bay's own frame: its -z (the LookVector) toward the bed's foot, +z its head.
	local frame = CFrame.new(bay.X, 0, bay.Z) * CFrame.Angles(0, math.rad(bay.Face), 0)
	local width, length = B.BAY_BED.Width, B.BAY_BED.Length
	local bed = part(
		bayModel,
		"Bed",
		Vector3.new(width, Pure.COUCH, length),
		frame * CFrame.new(0, Pure.COUCH / 2, 0),
		COUCH_COLOR
	)
	bayModel.PrimaryPart = bed
	soft(
		part(
			bayModel,
			"Pillow",
			Vector3.new(width - 1.2, 0.5, 1.3),
			frame * CFrame.new(0, Pure.COUCH + 0.25, length / 2 - 0.85),
			WORLD.Trim
		)
	).CastShadow =
		false
	-- The curtain, just inside the mouth: drawn back to one side while the bay is open, shut across it while closed.
	-- Bays 1-6 bunch it on their -x side; bay X on the side away from its back wall.
	local c = Pure.CURTAIN
	local bunchSign = if bay.Kind == "XRay" then 1 else -1
	local a0: number, a1: number
	if open then
		a0, a1 =
			if bunchSign < 0 then -c.Half else c.Half - c.Bunch, if bunchSign < 0 then -c.Half + c.Bunch else c.Half
	else
		a0, a1 = if bay.Kind == "XRay" then -(width / 2) else -c.Half, c.Half
	end
	soft(
		part(
			bayModel,
			"Curtain",
			Vector3.new(a1 - a0, c.Height, c.Thick),
			frame * CFrame.new((a0 + a1) / 2, 0.5 + c.Height / 2, -(length / 2 + c.Inset)),
			CURTAIN_COLOR,
			Enum.Material.Fabric
		)
	).CastShadow =
		false
	-- The tool tray: a shelf on the wall over the bed's head (soft: it never stops anyone).
	soft(part(bayModel, "Tray", Vector3.new(2.4, 0.25, 0.5), frame * CFrame.new(0, 3.6, length / 2 - 0.25), WORLD.Trim)).CastShadow =
		false
	-- The number sign over the mouth (🔒 while closed).
	local s = Pure.SIGN
	local signPart = paint(
		part(
			bayModel,
			"Sign",
			Vector3.new(s.Width, s.Y1 - s.Y0, s.Out),
			CFrame.new(signAt.X, (s.Y0 + s.Y1) / 2, signAt.Z),
			Palette.Navy
		)
	)
	local gui = surface(signPart, "SignGui", Enum.NormalId.Front, 30, 60, 0)
	local text = if not open
		then "🔒 Lv " .. tostring(bay.Opens)
		elseif bay.Kind == "XRay" then "📸 X-ray"
		else bay.Id
	floatText(gui, text, { Size = UDim2.fromScale(0.86, 0.72), Position = UDim2.fromScale(0.07, 0.14) })
	-- Where the doctor stands, at the foot (bay X: at the side), looking at the bed.
	local spot = B.doctorSpot(bay)
	local stand = CFrame.new(spot.X, 0.5, spot.Z)
	marker(
		bayModel,
		"DoctorSpot",
		if bay.Spot
			then CFrame.lookAt(stand.Position, Vector3.new(bay.X, 0.5, bay.Z))
			else stand * CFrame.Angles(0, math.rad(bay.Face + 180), 0)
	)
	bayModel.Parent = model
end

-- The exam bays' row: the back wall onto corridor B, the side wall at bay 6, the header over the mouths (the signs
-- hang on it), the dividers, and bays 1-6. (The Cozy Ward's W1 and W2 are PlotBuilder's.)
local function buildBays(model: Model, level: number)
	local bays = piece(model, "Bays", 1, 0)
	local r = B.ROOMS.Bays
	local p, w = B.PARTITION, B.WALL
	local top = Pure.wallTop(B, 0)
	partition(bays, "WallBays", r.X0 + w, r.X1, 0, top, r.Z1 - p, r.Z1)
	partition(bays, "WallBaysSide", r.X1 - p, r.X1, 0, top, r.Z0, r.Z1 - p)
	partition(bays, "BayHeader", r.X0 + w, r.X1 - p, Pure.DOOR, top, r.Z0, r.Z0 + p)
	local half = B.DIVIDER / 2
	for k = 1, 5 do
		local x = r.X0 + w + k * B.BAY_WIDTH
		partition(bays, "BayDivider", x - half, x + half, 0, Pure.DOOR, r.Z0 + p, r.Z1 - p)
	end
	for _, bay in B.BAYS do
		if bay.Kind == "Exam" and not bay.Room then
			buildBay(model, bay, level, Vector3.new(bay.X, 0, r.Z0 - Pure.SIGN.Out / 2))
		end
	end
end

-- The X-ray room: its walls (the door is a Door_XRay), bay X under the scanner arm, and the cast table.
local function buildXRay(model: Model, level: number)
	local xray = piece(model, "XRay", 1, 0)
	local r = B.ROOMS.XRay
	local p, w = B.PARTITION, B.WALL
	local top = Pure.wallTop(B, 0)
	local d = B.DOORS.XRay
	local d0, d1 = d.X0 :: number, d.X1 :: number
	partition(xray, "WallXRaySide", r.X0, r.X0 + p, 0, top, r.Z0, r.Z1)
	partition(xray, "WallXRay", r.X0 + p, d0, 0, top, r.Z0, r.Z0 + p)
	partition(xray, "WallXRay", d1, r.X1 - w, 0, top, r.Z0, r.Z0 + p)
	partition(xray, "LintelXRay", d0, d1, d.Height, top, r.Z0, r.Z0 + p)
	partition(xray, "WallXRayBack", r.X0 + p, r.X1 - w, 0, top, r.Z1 - p, r.Z1)
	local bay = B.bay("X") :: any
	buildBay(model, bay, level, Vector3.new((d0 + d1) / 2, 0, r.Z0 - Pure.SIGN.Out / 2))
	-- The arm: a column from the ceiling and the scanner head over the bed, clear of a sitting creature (soft).
	local x = Pure.XRAY
	local cx = bay.X + 0.8 -- a little toward the head
	soft(box(xray, "XRayColumn", cx - 0.4, cx + 0.4, x.HeadTop, top, bay.Z - 0.4, bay.Z + 0.4, WORLD.Trim)).CastShadow =
		false
	soft(
		box(
			xray,
			"XRayHead",
			cx - x.Depth / 2,
			cx + x.Depth / 2,
			x.Head,
			x.HeadTop,
			bay.Z - x.Width / 2,
			bay.Z + x.Width / 2,
			Palette.Navy
		)
	).CastShadow =
		false
	buildStation(model, "Cast", level, NO_ROOMS)
end

-- The back rooms' walls: the long wall onto corridor B (three doorways, their doors are Door_<room>) and the walls
-- between the rooms. Their insides are PlotBuilder's fit-outs.
local function buildBackRooms(model: Model)
	local backRooms = piece(model, "BackRooms", 1, 0)
	local bath, winter, cozy = B.ROOMS.BathRoom, B.ROOMS.WinterWing, B.ROOMS.CozyWard
	local p, w = B.PARTITION, B.WALL
	local top = Pure.wallTop(B, 0)
	local z0, z1 = bath.Z0, bath.Z0 + p
	local at = bath.X0 + w
	for _, key in { "BathRoom", "WinterWing", "CozyWard" } do
		local d = B.DOORS[key]
		local d0, d1 = d.X0 :: number, d.X1 :: number
		partition(backRooms, "WallRooms", at, d0, 0, top, z0, z1)
		partition(backRooms, "LintelRooms", d0, d1, d.Height, top, z0, z1)
		at = d1
	end
	partition(backRooms, "WallRooms", at, cozy.X1, 0, top, z0, z1)
	partition(backRooms, "WallRoom", bath.X1, bath.X1 + p, 0, top, z1, bath.Z1 - w)
	partition(backRooms, "WallRoom", winter.X1, winter.X1 + p, 0, top, z1, winter.Z1 - w)
	partition(backRooms, "WallRoom", cozy.X1 - p, cozy.X1, 0, top, z1, cozy.Z1 - w)
end

------------------------------------------------------------------------------------------------------------------
-- The lift, the stairs and the floors
------------------------------------------------------------------------------------------------------------------

-- The two prompts every landing has, at a rider's chest height (Pure.LIFT_PROMPT: the ground landing's stand off
-- the X-ray room's wall and reach less). A landing's X runs along the lift door, +z (landingMarker).
local function liftPrompts(landing: BasePart, ground: boolean?)
	if landing:FindFirstChild("PromptPoint") then
		return
	end
	local reach = if ground then Pure.LIFT_PROMPT.GroundReach else Pure.LIFT_PROMPT.Reach
	local point = Instance.new("Attachment")
	point.Name = "PromptPoint"
	point.Position = Vector3.new(if ground then Pure.LIFT_PROMPT.Away else 0, 2.5, 0)
	point.Parent = landing
	local lift = Instance.new("ProximityPrompt")
	lift.Name = "LiftPrompt"
	lift.ActionText = "Lift"
	lift.ObjectText = "↕️"
	lift.HoldDuration = 0
	lift.MaxActivationDistance = reach
	lift.RequiresLineOfSight = false
	CollectionService:AddTag(lift, HospitalBuilder.PROMPT_TAGS.Lift)
	lift.Parent = point
	local escort = Instance.new("ProximityPrompt")
	escort.Name = "EscortPrompt"
	escort.ActionText = "Ride with patient"
	escort.ObjectText = "↕️"
	escort.HoldDuration = 0
	escort.MaxActivationDistance = reach
	escort.RequiresLineOfSight = false
	escort.KeyboardKeyCode = Enum.KeyCode.F -- beside the LiftPrompt's E
	escort.GamepadKeyCode = Enum.KeyCode.ButtonY
	escort.Enabled = false
	CollectionService:AddTag(escort, HospitalBuilder.PROMPT_TAGS.Escort)
	escort.Parent = point
end

-- A landing marker in front of the lift door (Logic/Building.LANDING, resting on the floor), turned toward the lift
-- (the door is on the shaft's -x face): Server/Lift sets riders down side by side along its X, which runs along the
-- door (+z), so a second rider steps out into the hall, never into a wall.
local function landingMarker(parent: Instance, name: string, floor: number): BasePart
	local l = B.LANDING
	local landing = marker(
		parent,
		name,
		CFrame.new(l.X, B.slabTop(floor) + 0.5, l.Z) * CFrame.Angles(0, math.rad(270), 0),
		Vector3.new(l.Size, 1, l.Size)
	)
	landing:SetAttribute("Floor", floor)
	liftPrompts(landing, floor == 0)
	return landing
end

-- The glass lift (solid shaft) and the car in the plot's colour, studded, resting at the ground with its doors drawn
-- on its -x face (open; UI/LiftPanel closes them, slides the car and opens them on each client). Before the first
-- floor opens the car's doors are drawn shut with a 🔒 under them, and there is no Landing_0 (no prompt).
local function buildLift(model: Model, style: Style, level: number, standing: number)
	local lift = piece(model, "Lift", 1, 0)
	local s = B.SHAFT
	glass(lift, "Shaft", s.X0, s.X1, 0, Pure.shaftTop(B, standing, ROOF_FLOOR), s.Z0, s.Z1)
	local car = soft(box(lift, "Car", s.X0 + 0.3, s.X1 - 0.3, 0, Pure.CAR, s.Z0 + 0.3, s.Z1 - 0.3, style.Accent))
	Studs.apply(car)
	car.CastShadow = false
	local open = B.floors(level) >= 1
	local doors = surface(car, "DoorsGui", Enum.NormalId.Left, 20, 200)
	for i, name in { "DoorL", "DoorR" } do
		local x = if open then (if i == 1 then -0.21 else 1.21) else (if i == 1 then 0.25 else 0.75)
		local door = band(doors, name, UDim2.fromScale(0.5, 1), UDim2.fromScale(x, 0.5), style.Trim)
		local rim = Instance.new("UIStroke")
		rim.Color = Palette.Outline
		rim.Thickness = 3
		rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rim.Parent = door
	end
	if not open then
		local label = floatText(doors, Pure.levelLock(Pure.sinceOpen(B, 1)), {
			Size = UDim2.fromScale(0.9, 0.12),
			Position = UDim2.fromScale(0.05, 0.3),
		})
		label.ZIndex = 4
	end
	lift:SetAttribute("Ride", "") -- Server/Lift: "<from>,<to>,<seconds>,<serverTime>" for each ride (clients slide it)
	lift:SetAttribute("Rider", 0) -- ... and who rode and when (Feel/HospitalFX dings others' rides)
	lift:SetAttribute("RideAt", 0)
	CollectionService:AddTag(lift, HospitalBuilder.LIFT_TAG)
	if open then
		loose(landingMarker(model, "Landing_0", 0), Pure.sinceOpen(B, 1), 0)
	end
end

-- The dog-leg stairs (Logic/Building's well): each storey's two half-flights (Flight_<k>A up toward +x to Mid_<k>,
-- Flight_<k>B back to the next floor), the wall between the lanes, each floor's rail along the well, and on the top
-- floor the rails round its open half. Below the first open floor a shut gate stands at the foot.
-- A half-flight is its Flight_<k><lane> (the invisible walking ramp: smooth, so feet never catch) and its steps
-- (Step_<k><lane>_<i>, Pure.steps): blocky tiled treads, every nose on the ramp's line, so the ramp is never under a
-- tread and the walker stands on it. On the ground the steps are solid blocks from the floor up: they fill the space
-- under both flights (nobody walks or jumps in under them). Upstairs they are walk-through, with a stepped underside.
-- Nothing in the well shares a face with anything else or reaches inside it: each lane stops at the rail's and the
-- lane wall's faces, the walls stack slab to slab, the ground's rail stops at the mid landing.
local function buildStairs(model: Model, style: Style, level: number, standing: number)
	local stairs = piece(model, "Stairs", 1, 0)
	local well, mid, laneA = B.STAIRWELL, B.STAIR_MID, B.LANE_A
	local rail, half = Pure.RAIL, B.DIVIDER / 2
	local between = laneA.Z1 -- the lanes' shared edge
	for k = 0, standing - 1 do
		local since = Pure.sinceStanding(B, k + 1)
		for _, lane in { "A", "B" } do
			local r = Pure.ramp(B, k, lane)
			local fr = Pure.rampFrame(r, Pure.RAMP)
			local ramp = loose(
				part(
					stairs,
					"Flight_" .. k .. lane,
					Vector3.new(fr.Length, Pure.RAMP, r.Z1 - r.Z0),
					CFrame.new(fr.X, fr.Y, fr.Z) * CFrame.Angles(0, 0, fr.Angle),
					WORLD.FloorTile,
					Enum.Material.CeramicTiles
				),
				since,
				k
			)
			ramp.Transparency = 1
			ramp.CastShadow = false
			for i, s in Pure.steps(B, k, lane) do
				local bottom = if k == 0 then 0 else s.Top - s.Rise - Pure.WAIST
				if s.Top - bottom > 1e-3 then -- the ground's own floor is lane A's first tread there
					local step = loose(
						box(
							stairs,
							"Step_" .. k .. lane .. "_" .. (i - 1),
							s.X0,
							s.X1,
							bottom,
							s.Top,
							r.Z0,
							r.Z1,
							WORLD.FloorTile,
							Enum.Material.CeramicTiles
						),
						since,
						k
					)
					if k > 0 then
						soft(step)
					end
				end
			end
		end
		-- The mid landing (a solid block on the ground, so nothing hides under the stairs).
		local midTop = (B.slabTop(k) + B.slabTop(k + 1)) / 2
		loose(
			box(
				stairs,
				"Mid_" .. k,
				mid.X0,
				mid.X1,
				if k == 0 then 0 else midTop - Pure.SLAB,
				midTop,
				mid.Z0,
				mid.Z1,
				WORLD.FloorTile,
				Enum.Material.CeramicTiles
			),
			since,
			k
		)
		-- The wall between the lanes: slab to slab (each storey's stands on the one below it).
		loose(
			box(
				stairs,
				"StairWall",
				laneA.X0,
				laneA.X1,
				Pure.wallBase(B, k),
				Pure.wallTop(B, k),
				between - half,
				between + half,
				INSIDE
			),
			since,
			k
		)
	end
	-- Each floor's rail along the well's front edge (the ground's stops at the mid landing's block); on the top floor
	-- the rails round the hole over lane A, the middle one standing on the lane wall below.
	for k = 0, standing do
		local y = B.slabTop(k)
		local since = if k == 0 then 1 else Pure.sinceStanding(B, k)
		local function railBox(name: string, x0: number, x1: number, y0: number, z0: number, z1: number)
			loose(painted(box(stairs, name, x0, x1, y0, y + rail.Height, z0, z1, style.Trim), "Trim"), since, k)
		end
		railBox("Rail", well.X0, if k == 0 then mid.X0 else well.X1, y, well.Z0, well.Z0 + rail.Thick)
		if k == standing then
			railBox("RailEnd", well.X0, well.X0 + rail.Thick, y, well.Z0 + rail.Thick, between - half)
			railBox("RailMid", laneA.X0, laneA.X1, Pure.wallBase(B, k), between - half, between + half)
		end
	end
	-- Below the first open floor: a shut gate at lane A's foot.
	if B.floors(level) < 1 then
		local gate = loose(
			box(stairs, "StairGate", well.X0, well.X0 + 0.4, 0, 5, well.Z0 + rail.Thick, between - half, style.Accent),
			1,
			0
		)
		lockGui(gate, Enum.NormalId.Left, { "⬆️ Upstairs", Pure.levelLock(Pure.sinceOpen(B, 1)) }, true)
	end
end

------------------------------------------------------------------------------------------------------------------
-- The wards
------------------------------------------------------------------------------------------------------------------

-- A functional ward bed: BedSpot_<k> round the mattress Bed_<k> (Floor and Ward on both), its pillow at the street
-- wall (-z) and its foot spot in the aisle (Logic/Building.BED_FOOT_Z).
local function wardBed(parent: Instance, index: number, x: number, k: number, ward: string, since: number)
	local bed = Pure.BED
	local color = wardColor(ward)
	local floorY = B.slabTop(k)
	local spot = piece(parent, "BedSpot_" .. index, since, k)
	spot:SetAttribute("Floor", k)
	spot:SetAttribute("Ward", ward)
	local head = B.BED_Z0 + bed.HeadboardThick
	box(spot, "Frame", x - bed.Width / 2, x + bed.Width / 2, floorY, floorY + bed.FrameHeight, head, B.BED_Z1, color)
	Studs.apply(
		box(
			spot,
			"Headboard",
			x - bed.Headboard / 2,
			x + bed.Headboard / 2,
			floorY,
			floorY + bed.HeadboardHeight,
			B.BED_Z0,
			head,
			color
		)
	)
	-- Bed_<k> is the mattress: Server/Patients lies patients on its top, pillow end along its +Z (turned to face -z
	-- here) and their foot spot 1.6 past its -Z end.
	local mattress = part(
		spot,
		"Bed_" .. index,
		Vector3.new(bed.Mattress, bed.MattressHeight, bed.MattressLength),
		CFrame.new(x, floorY + bed.FrameHeight + bed.MattressHeight / 2, Pure.mattressZ(B))
			* CFrame.Angles(0, math.pi, 0),
		WORLD.Trim
	)
	mattress:SetAttribute("Floor", k)
	mattress:SetAttribute("Ward", ward)
end

-- A made-up bed (never used): DressBed_<n> with a Base and a Headboard at the pillow end (`pillow` -1: toward -z,
-- 1: toward +z), and with `sleeper` a sleeping stand-in on it.
local function dressBed(
	parent: Instance,
	index: number,
	r: Rect,
	floorY: number,
	pillow: number,
	color: Color3,
	sleeper: boolean
)
	local bed = Pure.BED
	local model = Instance.new("Model")
	model.Name = "DressBed_" .. index
	local cx = (r.X0 + r.X1) / 2
	local headZ0 = if pillow < 0 then r.Z0 else r.Z1 - bed.HeadboardThick
	local headZ1 = headZ0 + bed.HeadboardThick
	local baseZ0 = if pillow < 0 then headZ1 else r.Z0
	local baseZ1 = if pillow < 0 then r.Z1 else headZ0
	local width = math.min(bed.Headboard, r.X1 - r.X0)
	box(model, "Base", r.X0, r.X1, floorY, floorY + bed.DressHeight, baseZ0, baseZ1, WORLD.Trim)
	Studs.apply(
		box(
			model,
			"Headboard",
			cx - width / 2,
			cx + width / 2,
			floorY,
			floorY + bed.HeadboardHeight,
			headZ0,
			headZ1,
			color
		)
	)
	if sleeper then
		local s = Pure.SLEEPER
		local top = floorY + bed.DressHeight
		local length = baseZ1 - baseZ0
		local sleep = Instance.new("Model")
		sleep.Name = "Sleeper"
		-- The head on the pillow (a creature colour; blocky like every creature) ...
		local headZ = if pillow < 0 then baseZ0 + s.Depth / 2 + 0.3 else baseZ1 - s.Depth / 2 - 0.3
		local headPart: Part
		if s.Blocky then
			headPart = part(
				sleep,
				"Head",
				Vector3.new(s.Width, s.Height, s.Depth),
				CFrame.new(cx, top + s.Height / 2, headZ),
				creatureColor(index)
			)
		else
			headPart =
				Parts.ball(sleep, "Head", s.Width, CFrame.new(cx, top + s.Width / 2, headZ), creatureColor(index))
		end
		-- ... and a blanket over the foot two-thirds, just proud of the base at the sides and the foot.
		local blanketZ0 = if pillow < 0 then baseZ1 - length * 2 / 3 else baseZ0 - 0.05
		local blanketZ1 = if pillow < 0 then baseZ1 + 0.05 else baseZ0 + length * 2 / 3
		local blanket =
			box(sleep, "Blanket", r.X0 - 0.05, r.X1 + 0.05, top - 0.2, top + s.Blanket, blanketZ0, blanketZ1, color)
		for _, p in { headPart, blanket } do
			soft(p)
			p.CastShadow = false
		end
		local zzz = Instance.new("BillboardGui")
		zzz.Name = "SleepGui"
		zzz.Size = UDim2.fromScale(1.6, 1.6)
		zzz.StudsOffsetWorldSpace = Vector3.new(0, s.Height / 2 + 1.1, 0)
		zzz.LightInfluence = 0
		zzz.MaxDistance = 60
		local text = Instance.new("TextLabel")
		text.Name = "Zzz"
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.TextScaled = true
		text.Font = Palette.DisplayFont
		text.Text = "💤"
		text.Parent = zzz
		zzz.Parent = headPart
		sleep.Parent = model
	end
	model.Parent = parent
end

-- Floor k's beds: the functional ones (Logic/Building.wardBeds) as BedSpot_<k> (unless `keep` has them: those move
-- across from the old Building), the rest made up (all of them on a floor that stands but isn't open), one with a
-- sleeper, and curtains between them.
local function buildWard(floorModel: Model, level: number, k: number, keep: { [number]: boolean })
	local spots = B.wardBeds(level, k)
	local open = #spots > 0
	if not open then
		-- Standing, not open yet: every spot made up.
		for _, spot in B.WARD_BEDS[k] or {} do
			table.insert(spots, { Index = #spots + 1, X = spot.X, Z = spot.Z, Floor = k, Functional = false })
		end
		for _, spot in B.DRESS_BEDS[k] or {} do
			table.insert(spots, { Index = #spots + 1, X = spot.X, Z = spot.Z, Floor = k, Functional = false })
		end
	end
	local rows = B.WARD_BEDS[k]
	local ward = if rows and rows[1] then rows[1].Ward else "Wards"
	local color = wardColor(ward)
	local dressing = Instance.new("Model")
	dressing.Name = "Dressing"
	local made = 0
	for _, spot in spots do
		if not spot.Functional then
			made += 1
		end
	end
	local sleepers = Pure.sleepers(made, if open then Config.Look.Sleepers.Ward else Config.Look.Sleepers.Lv1)
	local y = B.slabTop(k)
	local half = Pure.BED.Width / 2
	local nth = 0
	local xs: { number } = {}
	for _, spot in spots do
		table.insert(xs, spot.X)
		if spot.Functional then
			if not keep[spot.Index] then
				wardBed(floorModel, spot.Index, spot.X, k, spot.Ward or ward, Pure.sinceOpen(B, k))
			end
		else
			nth += 1
			local r = { X0 = spot.X - half, X1 = spot.X + half, Z0 = B.BED_Z0, Z1 = B.BED_Z1 }
			dressBed(dressing, spot.Index, r, y, -1, color, sleepers[nth] == true)
		end
	end
	dressing.Parent = floorModel
	-- Curtains between neighbouring beds (soft).
	table.sort(xs)
	local curtainH = 6.5 -- in a 10.4-clear storey
	for i = 1, #xs - 1 do
		local x = (xs[i] + xs[i + 1]) / 2
		soft(
			box(
				floorModel,
				"Curtain",
				x - 0.1,
				x + 0.1,
				y + 0.6,
				y + curtainH,
				B.BED_Z0 + 0.4,
				B.BED_Z1 - 0.4,
				color,
				Enum.Material.Fabric
			)
		).CastShadow =
			false
	end
end

-- Floor_k: its slab (tiles indoors, dark on the roof deck), its landing once open, and indoors its studded walls,
-- its front glass band with the floor's icon, ribbon windows, a coloured dado, a room light and its beds; the roof
-- deck gets parapets instead.
local function buildFloor(model: Model, style: Style, level: number, k: number, keep: { [number]: boolean }): Model
	local open = k <= B.floors(level)
	local floorModel = piece(model, "Floor_" .. k, Pure.sinceStanding(B, k), k)
	floorModel:SetAttribute("Floor", k)
	floorModel:SetAttribute("Open", open)
	local y = B.slabTop(k)
	local deck = k >= ROOF_FLOOR
	for _, r in Pure.slabRects(B) do
		local slab = box(
			floorModel,
			r.Name,
			r.X0,
			r.X1,
			y - Pure.SLAB,
			y,
			r.Z0,
			r.Z1,
			if deck then WORLD.Roof else WORLD.FloorTile,
			if deck then Enum.Material.SmoothPlastic else Enum.Material.CeramicTiles
		)
		slab.CanCollide = true
	end
	if open then
		loose(landingMarker(floorModel, "Landing", k), Pure.sinceOpen(B, k), k)
	end
	local t, w = B.TOWER, B.WALL
	local base, top = Pure.wallBase(B, k), Pure.wallTop(B, k)
	if deck then
		local p = Pure.PARAPET
		box(floorModel, "ParapetFront", t.X0, t.X1, base, y + p, t.Z0, t.Z0 + w, WORLD.Roof)
		box(floorModel, "ParapetBack", t.X0, t.X1, base, y + p, t.Z1 - w, t.Z1, WORLD.Roof)
		box(floorModel, "ParapetLeft", t.X0, t.X0 + w, base, y + p, t.Z0 + w, t.Z1 - w, WORLD.Roof)
		box(floorModel, "ParapetRight", t.X1 - w, t.X1, base, y + p, t.Z0 + w, t.Z1 - w, WORLD.Roof)
		return floorModel
	end
	-- F1's street and -x walls stand over the podium: on the ground's ceiling (its top), never through it (their
	-- undersides and the ceiling's lay in one plane and flickered; Joshua, 2026-11-17). Its back and +x walls stand on
	-- the ground's outer walls.
	local podium = if k == 1 then Pure.wallTop(B, 0) + Pure.CEILING else base
	-- The street face: a studded spandrel and the glass band over it, with the floor's icon floating on the glass.
	outerWall(floorModel, "WallSpandrel", t.X0, t.X1, podium, y + Pure.SPANDREL, t.Z0, t.Z0 + w, style)
	local glassBand = glass(floorModel, "GlassBand", t.X0, t.X1, y + Pure.SPANDREL, top, t.Z0, t.Z0 + w)
	glassBand:SetAttribute("Outer", true)
	local width = t.X1 - t.X0
	local iconSize = math.min(0.7, 3.4 / (top - y - Pure.SPANDREL))
	floatText(surface(glassBand, "IconGui", Enum.NormalId.Front, 20, 200, 0), floorIcon(k), {
		Size = UDim2.fromScale(3.4 / width, iconSize),
		Position = UDim2.fromScale(0.5 / width, (1 - iconSize) / 2),
	})
	-- The back and the sides, with a ribbon window on each.
	outerWall(floorModel, "WallBack", t.X0, t.X1, base, top, t.Z1 - w, t.Z1, style)
	outerWall(floorModel, "WallLeft", t.X0, t.X0 + w, podium, top, t.Z0 + w, t.Z1 - w, style)
	outerWall(floorModel, "WallRight", t.X1 - w, t.X1, base, top, t.Z0 + w, t.Z1 - w, style)
	local out = Pure.PROUD
	local wy0, wy1 = y + Pure.WINDOW.Y0 + 0.5, y + Pure.WINDOW.Y1 + 0.5
	ribbon(floorModel, "WindowBack", t.X0 + 1.5, t.X1 - 1.5, wy0, wy1, t.Z1, t.Z1 + out)
	ribbon(floorModel, "WindowLeft", t.X0 - out, t.X0, wy0, wy1, t.Z0 + 1.5, t.Z1 - 1.5)
	ribbon(floorModel, "WindowRight", t.X1, t.X1 + out, wy0, wy1, t.Z0 + 1.5, t.Z1 - 1.5)
	-- The ward's colour inside: a studded dado band along the -x wall.
	local rows = B.WARD_BEDS[k]
	local dado = soft(
		box(
			floorModel,
			"Dado",
			t.X0 + w,
			t.X0 + w + 0.2,
			y,
			y + 3,
			t.Z0 + w,
			t.Z1 - w,
			wardColor(if rows and rows[1] then rows[1].Ward else nil)
		)
	)
	Studs.apply(dado)
	dado.CastShadow = false
	local slab = floorModel:FindFirstChild("Slab")
	if slab and slab:IsA("BasePart") then
		roomLight(slab, Vector3.new((t.X0 + t.X1) / 2, top - 1, (t.Z0 + t.Z1) / 2))
	end
	if B.WARD_BEDS[k] then
		buildWard(floorModel, level, k, keep)
	end
	return floorModel
end

-- Lv 1-4: the top roof over the tower, its edge band, the lift's head and the paw-heart on its street edge. Returns
-- where a theme prop stands, and the roof's front edge (icicles) and its width.
local function buildRoofTop(model: Model, style: Style, standing: number): (CFrame, CFrame, number)
	local roofTop = piece(model, "RoofTop", Pure.sinceStanding(B, standing), standing + 1)
	local t, s = B.TOWER, B.SHAFT
	local top = Pure.roofTop(B, standing)
	box(roofTop, "RoofCap", t.X0 - 0.2, t.X1 + 0.2, top - Pure.SLAB, top, t.Z0 - 0.2, t.Z1 + 0.2, WORLD.Roof)
	painted(
		paint(box(roofTop, "BandRoof", t.X0 - 0.2, t.X1 + 0.2, top, top + 0.4, t.Z0 - 0.2, t.Z0 + 0.4, style.Band)),
		"Band"
	)
	Studs.apply(box(roofTop, "LiftHead", s.X0, s.X1, top, top + Pure.LIFT_HEAD, s.Z0, s.Z1, style.Accent))
	local cx = (t.X0 + t.X1) / 2
	pawSign(roofTop, "LogoSign", CFrame.new(cx, top + 0.4 + Pure.LOGO / 2, t.Z0 - 0.1), Pure.LOGO, style)
	return CFrame.new(Pure.PROP.X, top, Pure.PROP.Z), CFrame.new(cx, top - Pure.SLAB, t.Z0 - 0.45), t.X1 - t.X0 + 0.4
end

-- Lv 5: the helipad (a ring and an H drawn on one flat invisible part), HeliSpot and the roof garden, and the lift
-- tower's head with the neon paw-heart and the beacon. Returns where a theme prop stands, and the deck's front edge.
local function buildRoofDeck(model: Model, style: Style): (CFrame, CFrame, number)
	local roof = piece(model, "Roof", Pure.sinceOpen(B, ROOF_FLOOR), ROOF_FLOOR)
	local y = B.slabTop(ROOF_FLOOR)
	local h = B.HELI
	local pad =
		paint(part(roof, "Helipad", Vector3.new(h.Size, 0.1, h.Size), CFrame.new(h.X, y + 0.06, h.Z), WORLD.Roof))
	pad.Transparency = 1
	local gui = surface(pad, "PadGui", Enum.NormalId.Top, 12, 300, 1)
	disc(gui, "Ring", 1, Palette.Gold, 1)
	disc(gui, "Inner", 0.84, WORLD.Road, 2)
	local letter = floatText(gui, "H", { Size = UDim2.fromScale(0.44, 0.44), Position = UDim2.fromScale(0.28, 0.28) })
	letter.ZIndex = 4
	local heli = marker(roof, "HeliSpot", CFrame.new(h.X, y + 0.5, h.Z))
	heli:SetAttribute("ArriveAt", 0) -- Server/Patients sets it; Feel/HospitalFX flies the helicopter in
	local size = Pure.PLANTER
	for i, at in Pure.PLANTERS do
		local planter = soft(
			box(
				roof,
				"Planter",
				at.X - size / 2,
				at.X + size / 2,
				y,
				y + size,
				at.Z - size / 2,
				at.Z + size / 2,
				if i % 2 == 0 then WORLD.LeavesB else WORLD.LeavesA
			)
		)
		Studs.apply(planter)
	end
	-- The lift tower's head, over the glass shaft: the neon paw-heart on its street face and the beacon on top.
	local tower = piece(model, "Tower", Pure.sinceOpen(B, ROOF_FLOOR), ROOF_FLOOR)
	local s = B.SHAFT
	local base = Pure.shaftTop(B, ROOF_FLOOR, ROOF_FLOOR)
	Studs.apply(box(tower, "TowerHead", s.X0, s.X1, base, base + Pure.HEAD, s.Z0, s.Z1, style.Accent))
	local cx = (s.X0 + s.X1) / 2
	local logo = pawSign(tower, "LogoNeon", CFrame.new(cx, base + Pure.HEAD / 2, s.Z0 - 0.25), 4, style)
	NightLights.light(logo, 24) -- the building's one night light; the disc goes Neon after dark
	local beacon = soft(
		box(
			tower,
			"Beacon",
			cx - 0.5,
			cx + 0.5,
			base + Pure.HEAD,
			base + Pure.HEAD + 1,
			s.Z0 + 1.5,
			s.Z0 + 2.5,
			ACCENT.Red
		)
	)
	beacon.CastShadow = false
	NightLights.tag(beacon, "Lamp")
	local t = B.TOWER
	return CFrame.new(Pure.PROP.X, y, Pure.PROP.Z),
		CFrame.new((t.X0 + t.X1) / 2, y - Pure.SLAB, t.Z0 - 0.25),
		t.X1 - t.X0
end

-- A&E (Lv 2+): the ambulance bay in the -x yard (Logic/Building.BAY_AMBULANCE) and a toy Ambulance parked nose to
-- the street: warm white, a red stripe round it, the paw-heart on its side (never a cross), sirens that go Neon at
-- night. The StretcherSpot is in line with the A&E door, facing it (Server/Patients sets an urgent patient there).
local function buildAmbulanceBay(model: Model, style: Style)
	local a = B.BAY_AMBULANCE
	local bay = piece(model, "AmbulanceBay", AE_OPENS, 0)
	local area = a.Area
	paint(box(bay, "BayFloor", area.X0, area.X1, 0.01, 0.07, area.Z0, area.Z1, WORLD.Road))
	local at = CFrame.new(a.X, 0, a.Z)
	local van = Instance.new("Model")
	van.Name = "Ambulance"
	local lift = 0.7 -- the wheels' radius: the body sits on them
	local body = part(van, "Body", Vector3.new(4.6, 3.8, 7), at * CFrame.new(0, lift + 1.9, 1.3), WORLD.Trim)
	part(van, "Cab", Vector3.new(4.6, 2.6, 2.6), at * CFrame.new(0, lift + 1.3, -3.5), WORLD.Trim)
	paint(part(van, "Stripe", Vector3.new(4.7, 0.6, 9.75), at * CFrame.new(0, lift + 1.2, -0.05), ACCENT.Red))
	local badge = surface(body, "BadgeGui", Enum.NormalId.Right, 20, 150, 0)
	Parts.pawHeart(
		holder(badge, UDim2.fromScale(0.34, 0.6), UDim2.fromScale(0.5, 0.36)),
		UDim2.fromScale(1, 1),
		style.Accent
	)
	for i, color in { ACCENT.Red, ACCENT.Blue } do
		local siren = soft(
			part(van, "Siren", Vector3.new(1.2, 0.5, 0.9), at * CFrame.new(i * 1.4 - 2.1, lift + 2.85, -3.5), color)
		)
		siren.CastShadow = false
		NightLights.tag(siren, "Lamp")
	end
	for _, z in { -3.2, 3 } do
		local axle =
			soft(part(van, "Axle", Vector3.new(5, lift * 2, lift * 2), at * CFrame.new(0, lift, z), Palette.Ink))
		axle.Shape = Enum.PartType.Cylinder
	end
	van:SetAttribute("ArriveAt", 0) -- Server/Patients sets it; Feel/HospitalFX flashes and sirens
	van.Parent = bay
	local s = a.Stretcher
	marker(bay, "StretcherSpot", CFrame.new(s.X, 0.5, s.Z) * CFrame.Angles(0, math.rad(270), 0))
end

------------------------------------------------------------------------------------------------------------------
-- Branch themes: one roof prop each (Data/Themes Prop, <= 6 parts, all walk-through)
------------------------------------------------------------------------------------------------------------------

-- Icicles hang under a roof's front edge (`edge`: its centre line, facing the street), with a snow lip on it.
local function propIcicles(parent: Instance, edge: CFrame, width: number)
	soft(part(parent, "Snow", Vector3.new(width, 0.35, 0.9), edge * CFrame.new(0, 0.12, 0), WORLD.Trim)).CastShadow =
		false
	local ice = WORLD.Water
	for i = 1, 4 do
		local x = (i - 2.5) / 4 * width * 0.8
		local length = if i % 2 == 0 then 1.8 else 1.2
		soft(
			part(
				parent,
				"Icicle",
				Vector3.new(0.45, length, 0.45),
				edge * CFrame.new(x, -length / 2, 0) * CFrame.Angles(0, math.rad(45), 0),
				ice
			)
		).CastShadow =
			false
	end
end

local PROPS: { [string]: (Instance, CFrame, Style) -> () } = {
	Palm = function(parent, at, _style)
		local height = 4.5
		soft(cylinder(parent, "Trunk", height, 0.7, at * CFrame.new(0, height / 2, 0), WORLD.Trunk, Enum.Material.Wood))
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
					WORLD.LeavesA
				)
			).CastShadow =
				false
		end
		soft(Parts.ball(parent, "Coconut", 0.8, crown * CFrame.new(0.3, -0.5, 0.4), WORLD.Trunk)).CastShadow = false
	end,
	Rocket = function(parent, at, style)
		soft(cylinder(parent, "Body", 4, 1.7, at * CFrame.new(0, 2.2, 0), WORLD.Trim))
		soft(Parts.ball(parent, "Nose", 1.7, at * CFrame.new(0, 4.2, 0), style.Band)).CastShadow = false
		for _, side in { -1, 1 } do
			soft(part(parent, "Fin", Vector3.new(0.25, 1.6, 1.4), at * CFrame.new(side * 0.95, 1, 0), style.Trim)).CastShadow =
				false
		end
		soft(Parts.ball(parent, "Porthole", 0.75, at * CFrame.new(0, 3, -0.75), WORLD.Window)).CastShadow = false
	end,
	Shell = function(parent, at, style)
		upright(parent, "Shell", 3.2, 0.4, at * CFrame.new(0, 1.3, 0), style.Trim)
		for _, angle in { -35, 0, 35 } do
			soft(
				part(
					parent,
					"Rib",
					Vector3.new(0.2, 1.5, 0.3),
					at * CFrame.new(0, 1.3, -0.3) * CFrame.Angles(0, 0, math.rad(angle)) * CFrame.new(0, 0.75, 0),
					WORLD.Trim
				)
			).CastShadow =
				false
		end
		soft(Parts.ball(parent, "Pearl", 0.8, at * CFrame.new(0, 0.45, -0.5), WORLD.Trim)).CastShadow = false
	end,
	Crown = function(parent, at, style)
		soft(cylinder(parent, "Band", 1.1, 3, at * CFrame.new(0, 0.55, 0), style.Band))
		for i = 0, 3 do
			local a = i * math.pi / 2 + math.pi / 4
			soft(
				Parts.ball(
					parent,
					"Point",
					0.7,
					at * CFrame.new(math.cos(a) * 1.2, 1.45, math.sin(a) * 1.2),
					style.Band
				)
			).CastShadow =
				false
		end
		soft(Parts.ball(parent, "Gem", 0.7, at * CFrame.new(0, 0.6, -1.45), style.Trim)).CastShadow = false
	end,
}

-- The theme's prop: icicles under `edge`, anything else standing at `spot` (both plot-local, facing the street).
local function themeProp(
	model: Model,
	style: Style,
	level: number,
	storey: number,
	spot: CFrame,
	edge: CFrame,
	width: number
)
	if style.Prop == "" then
		return
	end
	local prop = piece(model, "ThemeProp", level, storey)
	prop:SetAttribute("Theme", style.Theme)
	if style.Prop == "Icicles" then
		if width > 0 then
			propIcicles(prop, edge, width)
		end
	else
		local build = PROPS[style.Prop]
		if build then
			build(prop, spot, style)
		end
	end
	if #prop:GetChildren() == 0 then
		prop:Destroy()
	end
end

------------------------------------------------------------------------------------------------------------------
-- Putting it together
------------------------------------------------------------------------------------------------------------------

-- The names a ClinicKit building must carry (the brother's builds), so the systems find what they need.
local KIT_NEEDS = { "FrontDoor", "ReceptionStop", "WaitSeat_1", "ExamBay_1", "Station_Remedy" }

local function kitBuilding(level: number, themeId: string): Model?
	local kit = ServerStorage:FindFirstChild("ClinicKit")
	local template = kit and kit:FindFirstChild("Building" .. level)
	if not (template and template:IsA("Model")) then
		return nil
	end
	local model = template:Clone()
	scrubScripts(model, "ClinicKit.Building" .. level)
	anchorAll(model)
	for _, descendant in model:GetDescendants() do
		local name = descendant.Name
		if descendant:IsA("BasePart") and (name == "Landing" or name == "Landing_0") then
			liftPrompts(descendant) -- the brother's landings get the same prompts
		elseif string.match(name, "^Station_%w+$") and (descendant:IsA("BasePart") or descendant:IsA("Model")) then
			CollectionService:AddTag(descendant, HospitalBuilder.STATION_TAG)
		elseif name == "Lift" and descendant:IsA("Model") then
			CollectionService:AddTag(descendant, HospitalBuilder.LIFT_TAG)
		elseif descendant:IsA("Model") and (name == "FrontDoor" or string.match(name, "^Door_%w+$")) then
			CollectionService:AddTag(descendant, Doors.TAG)
		end
	end
	for _, name in KIT_NEEDS do
		if not model:FindFirstChild(name, true) then
			warn("[HospitalBuilder] ClinicKit.Building" .. level .. " has no " .. name)
		end
	end
	for _, id in B.PANTRY_ORDER do
		if not model:FindFirstChild("Station_" .. id, true) then
			-- no room has a station any more: without it that room's cases never come
			warn("[HospitalBuilder] ClinicKit.Building" .. level .. " has no Station_" .. id .. " (the pantry)")
		end
	end
	if B.floors(level) > 0 and not model:FindFirstChild("Landing_0", true) then
		warn("[HospitalBuilder] ClinicKit.Building" .. level .. " has no Landing_0: its lift won't work")
	end
	model:SetAttribute("Theme", themeId)
	return model
end

-- Builds the clinic in plot-local space (the plot's ground-top centre at the origin, -Z to the street). Bed spots in
-- `keep` ([floor][index]) are left out: the old ones move across.
local function placeholderBuilding(
	plotModel: Model,
	level: number,
	keep: { [number]: { [number]: boolean } },
	themeId: string
): Model
	local model = Instance.new("Model")
	local row = LevelsData[level]
	local style = buildingStyle(plotAccent(plotModel), themeId)
	local standing = Pure.standing(B, level)
	local owned = ownedRooms(plotModel)
	buildShell(model, style, if row then row.Name else "")
	for _, spec in DOOR_SPECS do
		buildDoor(model, level, owned, spec)
	end
	buildWaiting(model, style)
	buildDispensary(model, level)
	buildNurseStation(model)
	buildBays(model, level)
	for _, id in { "Plaster", "Ice", "Bandage" } do
		buildStation(model, id, level, owned) -- the supply alcove
	end
	for _, id in B.PANTRY_ORDER do
		buildStation(model, id, level, owned) -- the pantry: open with its room
	end
	buildXRay(model, level)
	buildBackRooms(model)
	buildLift(model, style, level, standing)
	buildStairs(model, style, level, standing)
	for k = 1, standing do
		buildFloor(model, style, level, k, keep[k] or {})
	end
	local spot: CFrame, edge: CFrame, width: number, storey: number
	if standing >= ROOF_FLOOR then
		spot, edge, width = buildRoofDeck(model, style)
		storey = ROOF_FLOOR
	else
		spot, edge, width = buildRoofTop(model, style, standing)
		storey = standing + 1
	end
	if level >= AE_OPENS then
		buildAmbulanceBay(model, style)
	end
	themeProp(model, style, level, storey, spot, edge, width)
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
		-- Keep the ward bed spots that stay (a patient may be resting on one): same floor, same index, same spot.
		local keep: { [number]: { [number]: boolean } } = {}
		local moving: { { Spot: Instance, Floor: number } } = {}
		if old then
			for k = 1, #B.SLAB_TOPS do
				local oldFloor = old:FindFirstChild("Floor_" .. k)
				for _, bed in B.wardBeds(lv, k) do
					local spot = oldFloor and oldFloor:FindFirstChild("BedSpot_" .. bed.Index)
					if bed.Functional and spot then
						keep[k] = keep[k] or {}
						keep[k][bed.Index] = true
						table.insert(moving, { Spot = spot, Floor = k })
					end
				end
			end
		end
		model = placeholderBuilding(plotModel, lv, keep, themeId)
		for _, entry in moving do
			local floorModel = (model :: Model):FindFirstChild("Floor_" .. entry.Floor)
			if floorModel then
				entry.Spot.Parent = floorModel
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
	building:SetAttribute("Floors", B.floors(lv))
	building:SetAttribute("Storeys", Pure.standing(B, lv))
	building:SetAttribute("Theme", themeId)
	-- The plot-local frame, for Feel/Cutaway (which falls back to the Building's pivot): never worth a failed build.
	pcall(building.SetAttribute, building, "Origin", plotModel:GetPivot())
	if old then
		old:Destroy()
	end
	building.Parent = plotModel
	plotModel:SetAttribute("Level", lv)
	plotModel:SetAttribute("Theme", themeId)
	-- The pantry follows the plot's rooms: now (a kit Building's too) and whenever one is bought or lost.
	HospitalBuilder.syncStations(plotModel)
	watchRooms(plotModel)
	return building
end

return HospitalBuilder
