--!strict
-- The hospital Building on a plot (look build plan §B6; docs/research/2026-11-16-hospital-building.md §3-6; the
-- Progression v2 build plan §B4 for the names). Server only. OWNER: T3 (the look overhaul).
--   HospitalBuilder.build(plotModel, level, grewFrom?, theme?): Model
--       = PlotBuilder.buildBuilding (the same signature and attributes): the hospital for that level (Data/Levels)
--       in that branch theme (Data/Themes id; nil or unknown = Candy). Replaces Plot.Building, sets the Building's
--       Level, GrewFrom, GrewAt, Floors, Theme and Origin (the plot-local frame as a CFrame, for Feel/Cutaway) and
--       the plot's Level and Theme attributes
--   HospitalBuilder.Pure          the interior layout in numbers (plot-local studs; PlotBuilder.Pure re-exports it;
--                                 tests/Hospital.spec loads the PURE block). Its functions take Shared/Logic/Building
--                                 (the interface numbers everyone else builds to) as their first argument, so those
--                                 numbers live in one place
--   HospitalBuilder.STATION_TAG   ("BuildingStation")  a station inside the Building (the 💊 Station_Pharmacy Model)
--   HospitalBuilder.LIFT_TAG      ("HospitalLift")     each Building's Lift Model (UI/LiftPanel slides its car)
--   HospitalBuilder.PROMPT_TAGS   { Lift = "LiftPrompt", Escort = "EscortPrompt", Soak = "SoakPrompt" }
--       (PlotBuilder re-exports all three)
-- The plot's colour comes from the plot Model's `Accent` attribute (a Color3 PlotBuilder sets; its PlotIndex's
-- Palette.PlotColors entry when missing). It never requires PlotBuilder (PlotBuilder requires this).
--
-- THE BUILDING (memory-20261117-001 #2, -002 #1, -003; Joshua: "i want an actual hospital"). A studded podium clinic
-- from Lv 1 that grows a storey per level, one bold plot colour, warm trim, dark roofs, plank floors, glass bands:
--   Lv 1  the podium (x ±11.5, z -13..3): the reception window the Counter sits in, the main door, the display window,
--         the name floating on the fascia under the canopy, a warm stripe, a dark flat roof, a waiting bench and one
--         made-up bed with a sleeper. No tent, no awning
--   Lv 2  G + F1 over the whole footprint (z -13..13): the A&E door with its red canopy and the ambulance bay, the
--         glass lift on the street-facing -x corner (door on +z), the G -> 1 flight, F1 = the Wards (7 beds in two
--         rooms, below), a dark roof with the lift's head
--   Lv 3  the tower rises over z -3..13: F2 = Hydro (the hot tub). F1's roof in front of it is a dark terrace, and
--         the paw-heart stands on the tower's roof edge, facing the street
--   Lv 4  F3 = the Pharmacy (Station_Pharmacy, the medicine shelf that is the atrium rail, a bench); BedSpot_3 turns
--         from a made-up bed into a real one, in the same spot
--   Lv 5  the walkable roof (Floor_4): the helipad and HeliSpot, planters, the lift tower with the NEON paw-heart
--         facing the street and a beacon
-- THE WARDS (Joshua: "more beds, wards should look full"). F1 holds 7 beds: the main ward (z -3..7) has the three
-- BedSpot spots, pillows at a glass partition (z -3), feet in the back aisle (z 6, a straight walk from the landing);
-- the front ward (z -13..-3) has 4 made-up beds, heads at the street window, 2 with sleepers the street sees.
-- Made-up beds are Wards.Dressing.DressBed_<n> (Base + Headboard; never named Bed_* or BedSpot_*, so no system ever
-- picks one). A sleeper is DressBed_<n>.Sleeper (Head + Blanket + a 💤 billboard): soft, never moving, no faces.
-- The usable beds are exactly Data/Levels.Beds - 1 (BedSpot_<n>.Bed_<n>, Floor = 1): no gameplay change.
--
-- Pieces. Every child is a Model piece with the attributes Since (the level that adds it: HospitalFX grows only
-- those in) and Storey (0 = the ground ... 4 = the roof; a loose part carries its own). Feel/Cutaway hides every
-- part whose Storey is above the floor you stand on and fades your floor's parts with Outer = true:
--   Podium (0)       the street face at every level: WallFascia (the name), the Pier frames, GlassDisplay, the
--                    BandFascia stripe, RoofCanopy + TrimCanopy over the Counter, the waiting Bench
--   PodiumShell (0)  Lv 1 only: the side walls with their side doors, the back wall, RoofPodium (Storey 1), the
--                    floor strip and the made-up bed with its sleeper (Dressing.DressBed_1)
--   Hall (0)         Lv 2+: the ground's sides and back with the A&E, lift-lobby and corridor doors, the A&E canopy,
--                    the hall floor and the lift directory (a navy plate)
--   Landing_0 (0)    a loose marker in front of the lift door, with the LiftPrompt and EscortPrompt
--   Lift (0)         the glass Shaft (solid: it is the wall at that corner), the Car (soft, the plot colour,
--                    studded; its DoorsGui faces the landings, +z); attributes Ride, Rider, RideAt; tag HospitalLift
--   Stairs (0)       one collidable wedge per storey, Flight_<k> (Storey k), alternating the atrium's two lanes
--   Floor_<n> (n)    the slab (Slab is the part with the landing; plank, 0.6 thick), the Landing (Floor = n), the
--                    storey's studded walls (Wall*, Outer), its front glass band with the floor's icon, dark ribbon
--                    windows (Window*, Outer), a department dado band and the atrium rails. Floor_4 is the roof
--                    deck: dark, with parapets
--   Wards (1)        BedSpot_<n> (Floor = 1), Dressing (the made-up beds), Curtain x 4, GlassPartition
--   Terrace (2)      Lv 3+: the dark roof over the front ward and its parapet
--   Hydro (2)        HotTub (Tub, Water, TubSpot_1/2 with Floor = 2, Tub.SoakPoint.SoakPrompt), TowelShelf, Plant
--   Pharmacy (3)     Station_Pharmacy (tagged BuildingStation; IconGui), the Shelf (the rail, "Pharmacy"), a Bench
--   RoofTop (top)    Lv 2-4: RoofCap, BandRoof, the LiftHead and (Lv 3-4) the LogoSign paw-heart
--   Roof (4)         Lv 5: Helipad (the ring and the H drawn on top), HeliSpot (ArriveAt), Planter x 2
--   Tower (4)        Lv 5: TowerHead, LogoNeon (the neon paw-heart, NightLights "Lamp" with one light), Beacon
--   AmbulanceBay (0) Lv 2+: the bay and the Ambulance (ArriveAt, StretcherSpot; warm white, a red stripe, the
--                    paw-heart; never a cross)
--   ThemeProp        a branch theme's roof prop (<= 6 parts)
-- Themes (Data/Themes, unchanged data): the outer walls always stay the plot's Accent (kids find "the pink one"). A
-- theme recolours only the parts with the attribute Paint: "Trim" (the piers, the canopy's edge, the rails) takes
-- its Trim hex, "Band" (the fascia stripe and the top roof's edge band) its Roof hex; plus its prop. Theme colours
-- are capped at 240 a channel (no bleached white in the world).
-- Night (World/NightLights): the glass and the ribbon windows are "Window" (warm, not Neon); the neon paw-heart, the
-- beacon and the ambulance's sirens are "Lamp". One shadowless light per building, on the paw-heart.
-- Budget (Config.Look): <= BuildingParts (160) parts at every level and theme, <= SurfaceGuisPerBuilding (12)
-- SurfaceGuis (each with a MaxDistance), <= GlassPerBuilding (6) see-through parts, no Texture, no Decal, nothing
-- named like a cross. tests/Hospital.spec measures them.
-- Solid. Every outer wall is CanCollide, upstairs too (kids can't walk out of F3); the lift shaft is the wall at its
-- corner. Patients and porters move by hops and PivotTo, so walls never stop them; what they walk past is in
-- Shared/Logic/Building.obstacles, and tests/Hospital.spec checks that everything solid here is inside it.
--
-- ServerStorage.ClinicKit.Building<level> (pivot = the plot's ground-top centre, facing the street) replaces the
-- placeholder for that level: it needs the same names (Landing_0, Floor_<n>.Slab/Landing, Lift, BedSpot_<n>...).
-- It gets Floors and Theme, prompts on any landing without them and the station tag; a missing lift is warned.
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
local LevelsData = require(Shared.Data.Levels)
local PatientsData = require(Shared.Data.Patients)
local Stations = require(Shared.Data.Stations)
local Themes = require(Shared.Data.Themes)
local BuildingLogic = require(Shared.Logic.Building)
local NightLights = require(script.Parent.World.NightLights)
local Parts = require(script.Parent.World.Parts)
local Studs = require(script.Parent.World.Studs)

local part, soft, cylinder, wedge = Parts.part, Parts.soft, Parts.cylinder, Parts.wedge
local marker, paint, band, disc = Parts.marker, Parts.paint, Parts.band, Parts.disc
local surface, iconBadge, floatText, navyPlate = Parts.surface, Parts.iconBadge, Parts.floatText, Parts.navyPlate
local anchorAll, scrubScripts = Parts.anchorAll, Parts.scrubScripts

local HospitalBuilder = {}

HospitalBuilder.STATION_TAG = "BuildingStation"
HospitalBuilder.LIFT_TAG = "HospitalLift"
HospitalBuilder.PROMPT_TAGS = table.freeze({ Lift = "LiftPrompt", Escort = "EscortPrompt", Soak = "SoakPrompt" })

-- PURE-BEGIN
-- The building's interior layout in numbers only (no Roblox types, no requires): tests/Hospital.spec loads this
-- block on its own. `B` is Shared/Logic/Building: the footprints, slab tops, shaft, landing, atrium, doors and
-- bed spots come from there; what is only the building's own (bed sizes, the tub, the stairs' lanes per floor,
-- the slabs' pieces) is here.
local Pure = {}

Pure.SLAB = 0.6 -- every slab and roof (Logic/Building.SLAB_MAX: F1's underside stays at 10.4)
Pure.DOOR = 7 -- every doorway's height; the fascia and the lintels start here
Pure.BAND = 0.5 -- the fascia stripe's height, just under F1's slab (the podium's roof at Lv 1)
Pure.SPANDREL = 2.4 -- an upper storey's studded wall under its front glass band
Pure.GLASS = 0.55 -- (0.3 with a navy tint read as black from the street: Studio 2026-11-17) the see-through parts: the glass bands, the display window, the partition, the lift shaft
Pure.CAR = 6.5 -- the lift car's height
Pure.CLEAR = 0.5 -- Lv 5: the shaft's glass reaches this far over the car standing at the roof
Pure.HEAD = 4.5 -- Lv 5: the lift tower's head over the shaft (the neon paw-heart's wall)
Pure.LIFT_HEAD = 2.5 -- Lv 2-4: the lift's head box on the top roof
Pure.PAINT = 0.05 -- the hall's painted plank floor (walk-through: Landing_0 and the patients stand at 0)
Pure.STAND_TOP = 0.6 -- the Stand room's floor top when the plot has no Room_Stand to measure (PlotBuilder.SLOTS)
Pure.STAND_BACK = 1 -- the Stand room's back edge (PlotBuilder.SLOTS.Stand): the hall's floor starts there
Pure.DECOR_HALF = 2 -- a decor slot is 4 x 4 (PlotBuilder's DecorSlot markers): the Lv 1 bed stays off slot 1
Pure.RAIL = { Height = 3, Thick = 0.3 } -- the atrium rails (inside the open lane, along its edges)
Pure.PARAPET = 1.2
Pure.WINDOW = { Y0 = 3.5, Y1 = 6, Inset = 1, Proud = 0.1 } -- ribbon windows: from the storey's floor, ends inset
Pure.DADO = { Height = 2.4, Thick = 0.2 } -- the department's studded band inside the +x wall
-- A bed (look build plan §B6: the bed contract). Functional: Frame + Headboard + Bed_<n> (the mattress). Made up:
-- Base (frame and mattress in one block) + Headboard.
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
-- A sleeper: a head on the pillow and a blanket over the foot two-thirds. Blocky like every creature now
-- (memory-20261117-004); set Blocky = false for the round stand-in the plan first drew.
Pure.SLEEPER = { Width = 2, Height = 1.8, Depth = 1.8, Blocky = true, Blanket = 0.5 }
-- Hydro (F2): the hot tub, and its two spots on the landing's side so a soaker's approach (TUB_SHORT short of its
-- spot, on the line from the landing: Server/Patients.shortOf) stays outside the tub.
Pure.TUB = { X = 2.5, Z = 2.4, Diameter = 8, Rim = 1.6 }
Pure.TUB_SPOTS = { { X = 0.2, Z = 0.8 }, { X = 0.2, Z = 4 } }
Pure.TUB_SHORT = 3
-- The Pharmacy (F3): the station (hold it from the street side, z ~2.5) and the bench by the front glass.
Pure.PHARMACY = { X = 2, Z = 5, Width = 4.6, Depth = 2.6, Height = 3 }
Pure.SHELF = { Height = 4, Thick = 0.6 }
Pure.BENCH = { X0 = -5.5, X1 = -2.5, Z0 = -2.2, Z1 = -1.2, Height = 1.4 }
-- The roof (Lv 5).
Pure.PAD = { X = 3, Z = 2.3, Diameter = 9 }
Pure.PLANTERS = { { X = 9.6, Z = 3.5 }, { X = 9.6, Z = 5.8 } }
Pure.PLANTER = 2
-- Where a theme's prop stands: on the podium's roof (Lv 1), F1's roof (Lv 2), the tower's roof (Lv 3+).
Pure.PROP = { Podium = { X = 7, Z = -9 }, Block = { X = 8, Z = -9 }, Tower = { X = 9.2, Z = -0.5 } }
Pure.BAY = { X = -26.8, Z = -16.5 } -- the ambulance bay (unchanged from Progression v2), its nose to the street
Pure.CAP = 240 -- no world colour brighter than this in any channel (theme colours are capped to it)

type Rect = { X0: number, X1: number, Z0: number, Z1: number }
type Named = { Name: string, X0: number, X1: number, Z0: number, Z1: number }
type Flight = { Lane: string, Z0: number, Z1: number, XLow: number, XHigh: number, YLow: number, YHigh: number }
type Span = { Z0: number, Z1: number }

-- The atrium lane floor k leaves open, for the flight coming up from floor k - 1: F1 and F3 lane "A", F2 and the
-- roof lane "B". It covers the other lane: the next flight stands on it.
function Pure.holeLane(k: number): string
	return if k % 2 == 1 then "A" else "B"
end

function Pure.lane(B: any, which: string): Rect
	local a = B.LANE_A
	if which == "A" then
		return { X0 = a.X0, X1 = a.X1, Z0 = a.Z0, Z1 = a.Z1 }
	end
	return { X0 = a.X0, X1 = a.X1, Z0 = a.Z1, Z1 = B.ATRIUM.Z1 }
end

-- Flight_k, floor k up to k + 1: it stands in the lane floor k + 1 leaves open, rising toward +x when k is even
-- (G -> 1 lane A toward +x, 1 -> 2 lane B toward -x, ...), so each flight's top meets the next one's foot.
function Pure.flight(B: any, k: number): Flight
	local which = Pure.holeLane(k + 1)
	local lane = Pure.lane(B, which)
	local up = k % 2 == 0
	return {
		Lane = which,
		Z0 = lane.Z0,
		Z1 = lane.Z1,
		XLow = if up then lane.X0 else lane.X1,
		XHigh = if up then lane.X1 else lane.X0,
		YLow = B.slabTop(k),
		YHigh = B.slabTop(k + 1),
	}
end

-- Floor k's slab, in pieces: its footprint less the lift shaft and the open lane. "Slab" is the piece behind the
-- shaft that the landing stands on (the contract's Floor_<n>.Slab).
function Pure.slabRects(B: any, k: number): { Named }
	local f = B.footprint(B.MAX_LEVEL, k)
	local s = B.SHAFT
	local hole = Pure.lane(B, Pure.holeLane(k))
	local out: { Named } = {}
	local function add(name: string, x0: number, x1: number, z0: number, z1: number)
		if x1 - x0 > 1e-6 and z1 - z0 > 1e-6 then
			table.insert(out, { Name = name, X0 = x0, X1 = x1, Z0 = z0, Z1 = z1 })
		end
	end
	add("SlabFront", f.X0, f.X1, f.Z0, s.Z0) -- F1 only: over the podium (the front ward)
	add("SlabSide", s.X1, f.X1, s.Z0, s.Z1) -- beside the shaft
	add("Slab", f.X0, f.X1, s.Z1, hole.Z0) -- behind the shaft: the landing's
	add("SlabEnd", f.X0, hole.X0, hole.Z0, hole.Z1) -- the open lane's two ends (the stairs' landings)
	add("SlabEnd", hole.X1, f.X1, hole.Z0, hole.Z1)
	add("SlabBack", f.X0, f.X1, hole.Z1, f.Z1) -- behind the open lane
	return out
end

-- Floor k's two rails, inside its open lane: Long along the edge you walk beside, End at the low end of the flight
-- below (the only drop: the other end is that flight's top, level with the floor).
function Pure.rails(B: any, k: number): { Long: Rect, End: Rect }
	local hole = Pure.lane(B, Pure.holeLane(k))
	local below = Pure.flight(B, k - 1)
	local t = Pure.RAIL.Thick
	local long = { X0 = hole.X0, X1 = hole.X1, Z0 = hole.Z0, Z1 = hole.Z0 + t }
	local x0 = if below.XLow < (hole.X0 + hole.X1) / 2 then hole.X0 else hole.X1 - t
	return { Long = long, End = { X0 = x0, X1 = x0 + t, Z0 = hole.Z0 + t, Z1 = hole.Z1 } }
end

-- A main-ward mattress's centre z: its foot spot (Server/Patients.bedFoot) lands on Logic/Building.BED_FOOT_Z.
function Pure.mattressZ(B: any): number
	return B.BED_FOOT_Z - (Pure.BED.MattressLength / 2 + Pure.BED.FootStep)
end

-- The top roof (Lv 2-4): its top is the next slab top over the highest floor.
function Pure.roofTop(B: any, floors: number): number
	return B.slabTop(floors + 1)
end

-- Storey k's walls stand up to the next slab's (or roof's) underside.
function Pure.wallTop(B: any, k: number): number
	return B.slabTop(k + 1) - Pure.SLAB
end

-- The glass shaft: up under the top roof, or (a walkable roof) past the car standing at the roof.
function Pure.shaftTop(B: any, floors: number, roofFloor: number): number
	if floors >= roofFloor then
		return B.slabTop(floors) + Pure.CAR + Pure.CLEAR
	end
	return Pure.roofTop(B, floors) - Pure.SLAB
end

-- A wall from z0 to z1 with gaps (doorways, the shaft) left open, as the spans that stand.
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

-- Where a soaker stops before hopping into its tub spot: TUB_SHORT short of it, on the line from `from`
-- (Server/Patients.shortOf).
function Pure.tubApproach(spotX: number, spotZ: number, fromX: number, fromZ: number): (number, number)
	local dx, dz = fromX - spotX, fromZ - spotZ
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 0.05 then
		return spotX, spotZ
	end
	local step = math.min(Pure.TUB_SHORT, length)
	return spotX + dx / length * step, spotZ + dz / length * step
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
local DEPT = Palette.Departments

-- The floors the departments are on (Data/Departments) and the level each building piece first appears at
-- (Data/Levels), so a piece's Since follows the data.
local function deptFloor(dept: string, fallback: number): number
	local row = rawget(Departments :: any, dept)
	return if type(row) == "table" and type(row.Floor) == "number" then row.Floor else fallback
end
local HYDRO_FLOOR = deptFloor("Hydro", 2)
local PHARMACY_FLOOR = deptFloor("Pharmacy", 3)
local ROOF_FLOOR = deptFloor("Roof", 4)
local WARDS_FLOOR = B.WARD_FLOOR

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

-- The department on floor k (its icon on the glass band, its colour inside).
local FLOOR_DEPTS = { "Wards", "Hydro", "Pharmacy", "Roof" }
local function deptOn(k: number): string?
	for _, dept in FLOOR_DEPTS do
		if deptFloor(dept, -1) == k then
			return dept
		end
	end
	return nil
end

local function deptIcon(dept: string?, fallback: string): string
	local row = if dept then rawget(Departments :: any, dept) else nil
	return if type(row) == "table" and type(row.Icon) == "string" then row.Icon else fallback
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
	Accent: Color3, -- the plot's own colour: the walls, the car, the paw-heart. Never themed
	Trim: Color3, -- Paint "Trim": the piers, the canopy's edge, the rails (a theme's Trim hex)
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

-- A room's own light: shadowless (the perf budget), always on, warm white, on an Attachment (no part). Without it
-- every storey read as black through its glass from the street by day (Studio run, 2026-11-17).
local ROOM_LIGHT_BRIGHTNESS = 1.1
local ROOM_LIGHT_RANGE = 18
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

-- A part a theme recolours: "Trim" or "Band".
local function painted(p: BasePart, paintRole: string): BasePart
	p:SetAttribute("Paint", paintRole)
	return p
end

-- See-through glass (the bands, the display window, the partition): warm at night.
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

-- A dark ribbon window on an outer face, `Pure.WINDOW.Proud` out from it (soft paint; warm at night). `side` is
-- "Left" (x = -HALF), "Right" (x = HALF) or "Back" (z = `at`); a0..a1 is its span along the wall.
local function ribbon(parent: Instance, side: string, a0: number, a1: number, floorY: number, at: number?)
	local w = Pure.WINDOW
	local s0, s1 = a0 + w.Inset, a1 - w.Inset
	if s1 - s0 < 1 then
		return
	end
	local y0, y1 = floorY + w.Y0, floorY + w.Y1
	local h = B.HALF
	local p: Part
	if side == "Left" then
		p = box(parent, "WindowLeft", -h - w.Proud, -h, y0, y1, s0, s1, WORLD.Window)
	elseif side == "Right" then
		p = box(parent, "WindowRight", h, h + w.Proud, y0, y1, s0, s1, WORLD.Window)
	else
		local z = at or B.BACK
		p = box(parent, "WindowBack", s0, s1, y0, y1, z, z + w.Proud, WORLD.Window)
	end
	paint(p)
	p:SetAttribute("Outer", true)
	NightLights.tag(p, "Window")
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

------------------------------------------------------------------------------------------------------------------
-- Beds
------------------------------------------------------------------------------------------------------------------

-- A functional ward bed in the main ward: BedSpot_<n> round the mattress Bed_<n> (Floor = 1 on both), its pillow
-- toward the glass partition (-z) and its foot spot in the back aisle (Logic/Building.BED_FOOT_Z).
local function wardBed(parent: Instance, index: number, x: number, floorY: number)
	local bed = Pure.BED
	local color = DEPT.Wards
	local spot = piece(parent, "BedSpot_" .. index, sinceBed(index), WARDS_FLOOR)
	spot:SetAttribute("Floor", WARDS_FLOOR)
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
	-- Bed_<n> is the mattress: Server/Patients lies patients on its top, pillow end along its +Z (turned to face -z
	-- here) and their foot spot 1.6 past its -Z end.
	local mattress = part(
		spot,
		"Bed_" .. index,
		Vector3.new(bed.Mattress, bed.MattressHeight, bed.MattressLength),
		CFrame.new(x, floorY + bed.FrameHeight + bed.MattressHeight / 2, Pure.mattressZ(B))
			* CFrame.Angles(0, math.pi, 0),
		WORLD.Trim
	)
	mattress:SetAttribute("Floor", WARDS_FLOOR)
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
		-- The head on the pillow (a creature colour; blocky like every creature now) ...
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

------------------------------------------------------------------------------------------------------------------
-- The ground storey
------------------------------------------------------------------------------------------------------------------

-- The street face, at every level: the fascia with the name, the frames, the display window, the stripe, the
-- canopy over the Counter and the waiting bench.
local function buildPodium(model: Model, style: Style, standTop: number, name: string)
	local podium = piece(model, "Podium", 1, 0)
	local h, f, w = B.HALF, B.FRONT, B.WALL
	local top = Pure.wallTop(B, 0)
	local doors = B.DOORS
	local fascia = outerWall(podium, "WallFascia", -h, h, Pure.DOOR, top, f, f + w, style)
	-- The name floats on the fascia, over the reception window and under the canopy (art-direction §4.4: no board).
	local canopy = B.CANOPY
	local under = canopy.Y - 0.25 - 0.15
	local nameGui = surface(fascia, "NameGui", Enum.NormalId.Front, 24, 220, 0)
	local height = top - Pure.DOOR
	floatText(nameGui, name, {
		Shadow = true,
		Size = UDim2.fromScale(14 / (2 * h), (under - Pure.DOOR - 0.2) / height),
		Position = UDim2.fromScale((h - 7) / (2 * h), (top - under) / height),
	})
	-- Warm frames: the two corners, and between the display window, the reception window and the main door.
	for _, x in
		{
			{ -h, -h + w },
			{ doors.Display.X1, doors.Reception.X0 },
			{ doors.Reception.X1, doors.Main.X0 },
			{
				h - w,
				h,
			},
		}
	do
		local name0 = if x[1] == -h or x[2] == h then "PierCorner" else "Pier"
		painted(box(podium, name0, x[1], x[2], 0, Pure.DOOR, f, f + w, style.Trim), "Trim")
	end
	glass(podium, "GlassDisplay", -h + w, doors.Display.X1, 0, Pure.DOOR, f + 0.1, f + w - 0.1)
	-- The fascia stripe (a theme's roof band), just proud of the façade.
	local stripe = painted(
		box(podium, "BandFascia", -h - 0.15, h + 0.15, top - Pure.BAND, top, f - 0.15, f + 0.15, style.Band),
		"Band"
	)
	paint(stripe)
	-- The canopy over the Counter: soft and overhead, short of queue spot 1.
	soft(
		box(
			podium,
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
	local edge = painted(
		box(
			podium,
			"TrimCanopy",
			canopy.X0 - 0.15,
			canopy.X1 + 0.15,
			canopy.Y - 0.35,
			canopy.Y + 0.35,
			canopy.Z0 - 0.15,
			canopy.Z0 + 0.15,
			style.Trim
		),
		"Trim"
	)
	paint(edge)
	-- The waiting bench along the +x wall.
	local bench = B.STAND.Bench
	box(
		podium,
		"Bench",
		bench.X0,
		bench.X1,
		standTop,
		standTop + 1.5,
		bench.Z0,
		bench.Z1,
		WORLD.Plank,
		Enum.Material.WoodPlanks
	)
end

-- Lv 1: the podium's sides (a side door in each), its back, its dark flat roof and the made-up bed with a sleeper.
local function buildPodiumShell(model: Model, style: Style, standTop: number)
	local shell = piece(model, "PodiumShell", 1, 0)
	local h, f, w = B.HALF, B.FRONT, B.WALL
	local back = B.PODIUM_BACK
	local top = Pure.wallTop(B, 0)
	local door = B.DOORS.Side
	for _, side in { -1, 1 } do
		local x0 = if side < 0 then -h else h - w
		local sideName = if side < 0 then "Left" else "Right"
		for _, span in Pure.segments(f + w, back - w, { door }) do
			outerWall(shell, "Wall" .. sideName, x0, x0 + w, 0, top, span.Z0, span.Z1, style)
			ribbon(shell, sideName, span.Z0, span.Z1, 0)
		end
		outerWall(shell, "WallLintel" .. sideName, x0, x0 + w, Pure.DOOR, top, door.Z0, back - w, style)
	end
	outerWall(shell, "WallBack", -h, h, 0, top, back - w, back, style)
	ribbon(shell, "Back", -h, h, 0, back)
	local roof = box(shell, "RoofPodium", -h - 0.2, h + 0.2, top, B.GROUND, f - 0.2, back + 0.2, WORLD.Roof)
	roof:SetAttribute("Storey", 1)
	paint(
		box(
			shell,
			"FloorBack",
			-h + w,
			h - w,
			Pure.PAINT - 0.04,
			Pure.PAINT,
			Pure.STAND_BACK,
			back - w,
			WORLD.FloorA,
			Enum.Material.WoodPlanks
		)
	)
	-- The made-up bed along the -x wall, its pillow toward +z, clear of the side door, decor slot 1 and Remedy.
	local d = B.LV1_DRESSING
	local decor = B.STAND.Decor[1]
	local rect = {
		X0 = math.max(d.X0, -h + w),
		X1 = d.X1,
		Z0 = math.max(d.Z0, decor.Z + Pure.DECOR_HALF + 0.1),
		Z1 = d.Z1,
	}
	local dressing = Instance.new("Model")
	dressing.Name = "Dressing"
	local sleepers = Pure.sleepers(1, Config.Look.Sleepers.Lv1)
	dressBed(dressing, 1, rect, standTop, 1, style.Accent, sleepers[1] == true)
	dressing.Parent = shell
end

-- The lift directory: a navy plate by the ground's lift door, one row per floor (top first).
local function directory(wall: BasePart, floors: number)
	local gui = surface(wall, "DirectoryGui", Enum.NormalId.Right, 30, 60, 0)
	-- On the wall's inner (+x) face the gui runs from its back end (x scale 0) to its front end (1): the plate sits
	-- at the front end, beside the lift-lobby door and the landing.
	navyPlate(gui, { Size = UDim2.fromScale(0.42, 0.62), Position = UDim2.fromScale(0.74, 0.47) })
	local rows = floors + 1
	for i = 0, floors do
		local k = floors - i
		local label = if k == 0 then "G" elseif k >= ROOF_FLOOR then "R" else tostring(k)
		local icon = if k == 0 then deptIcon("Reception", "🛎️") else deptIcon(deptOn(k), "🛗")
		floatText(gui, icon .. " " .. label, {
			Size = UDim2.fromScale(0.34, 0.5 / rows),
			Position = UDim2.fromScale(0.57, 0.19 + i * 0.56 / rows),
		})
	end
end

-- Lv 2+: the ground's sides and back, the A&E door with its red canopy, the lift-lobby and corridor doors.
local function buildHall(model: Model, style: Style, floors: number)
	local hall = piece(model, "Hall", sinceFloor(1), 0)
	local h, f, w = B.HALF, B.FRONT, B.WALL
	local back = B.BACK
	local top = Pure.wallTop(B, 0)
	local doors = B.DOORS
	local s = B.SHAFT
	-- -x: the A&E door, the shaft (the glass lift is the wall there), the lift-lobby door.
	local left = Pure.segments(f + w, back - w, { doors.AE, { Z0 = s.Z0, Z1 = s.Z1 }, doors.LiftLobby })
	for i, span in left do
		local wall = outerWall(
			hall,
			if i == 1 then "WallLeftFront" else "WallLeftBack",
			-h,
			-h + w,
			0,
			top,
			span.Z0,
			span.Z1,
			style
		)
		if i == #left then
			directory(wall, floors)
		end
	end
	local lintelAE = outerWall(hall, "WallLintelAE", -h, -h + w, Pure.DOOR, top, doors.AE.Z0, doors.AE.Z1, style)
	outerWall(hall, "WallLintelLobby", -h, -h + w, Pure.DOOR, top, doors.LiftLobby.Z0, doors.LiftLobby.Z1, style)
	-- +x: the corridor door (the patients' back lane out to the walkway).
	for i, span in Pure.segments(f + w, back - w, { doors.Corridor }) do
		outerWall(hall, if i == 1 then "WallRightFront" else "WallRightBack", h - w, h, 0, top, span.Z0, span.Z1, style)
		if i == 1 then
			ribbon(hall, "Right", span.Z0, span.Z1, 0)
		end
	end
	outerWall(hall, "WallLintelCorridor", h - w, h, Pure.DOOR, top, doors.Corridor.Z0, doors.Corridor.Z1, style)
	outerWall(hall, "WallBack", -h, h, 0, top, back - w, back, style)
	ribbon(hall, "Back", -h, h, 0, back)
	local floorHall = paint(
		box(
			hall,
			"FloorHall",
			-h + w,
			h - w,
			Pure.PAINT - 0.04,
			Pure.PAINT,
			Pure.STAND_BACK,
			back - w,
			WORLD.FloorA,
			Enum.Material.WoodPlanks
		)
	)
	roomLight(floorHall, Vector3.new(0, top - 1, (Pure.STAND_BACK + back - w) / 2))
	-- A&E: a red canopy over its door, facing the ambulance bay, and the letters on the wall over it.
	local ae = doors.AE
	soft(box(hall, "CanopyAE", -h - 2, -h, Pure.DOOR + 0.6, Pure.DOOR + 1, ae.Z0 - 0.5, ae.Z1 + 0.5, DEPT.AE))
	paint(
		box(
			hall,
			"RoofEdgeAE",
			-h - 2.2,
			-h - 2,
			Pure.DOOR + 0.4,
			Pure.DOOR + 1.1,
			ae.Z0 - 0.5,
			ae.Z1 + 0.5,
			WORLD.Roof
		)
	)
	local letters = surface(lintelAE, "AEGui", Enum.NormalId.Left, 30, 160, 0)
	floatText(letters, "A&E", {
		Shadow = true,
		Size = UDim2.fromScale(0.9, 0.5),
		Position = UDim2.fromScale(0.05, 0.12),
	})
end

------------------------------------------------------------------------------------------------------------------
-- The lift, the stairs and the floors
------------------------------------------------------------------------------------------------------------------

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

-- A landing marker in front of the lift door (4 x 1 x 4, resting on the floor). It stays turned toward the lift:
-- Server/Lift sets riders down side by side along its X, and that keeps a second rider inside the building, off
-- the -x wall two studs away.
local function landingMarker(parent: Instance, name: string, floor: number): BasePart
	local l = B.LANDING
	local y = B.slabTop(floor)
	local landing = marker(parent, name, CFrame.new(l.X, y + 0.5, l.Z), Vector3.new(l.Size, 1, l.Size))
	landing:SetAttribute("Floor", floor)
	liftPrompts(landing)
	return landing
end

-- The glass lift at the street-facing -x corner: a solid glass shaft (it is the wall at that corner) and the car in
-- the plot's colour, studded, resting at the ground with its doors drawn on its +z side (open; UI/LiftPanel closes
-- them, slides the car and opens them on each client).
local function buildLift(model: Model, style: Style, floors: number)
	local lift = piece(model, "Lift", sinceFloor(1), 0)
	local s = B.SHAFT
	local shaftTop = Pure.shaftTop(B, floors, ROOF_FLOOR)
	local shaft = glass(lift, "Shaft", s.X0, s.X1, 0, shaftTop, s.Z0, s.Z1)
	shaft.CastShadow = false
	local car = soft(box(lift, "Car", s.X0 + 0.3, s.X1 - 0.3, 0, Pure.CAR, s.Z0 + 0.3, s.Z1 - 0.3, style.Accent))
	Studs.apply(car)
	car.CastShadow = false
	local doors = surface(car, "DoorsGui", Enum.NormalId.Back, 20, 200)
	for i, name in { "DoorL", "DoorR" } do
		local door =
			band(doors, name, UDim2.fromScale(0.5, 1), UDim2.fromScale(if i == 1 then -0.21 else 1.21, 0.5), style.Trim)
		local rim = Instance.new("UIStroke")
		rim.Color = Palette.Outline
		rim.Thickness = 3
		rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rim.Parent = door
	end
	lift:SetAttribute("Ride", "") -- Server/Lift: "<from>,<to>,<seconds>,<serverTime>" for each ride (clients slide it)
	lift:SetAttribute("Rider", 0) -- ... and who rode and when (Feel/HospitalFX dings others' rides)
	lift:SetAttribute("RideAt", 0)
	CollectionService:AddTag(lift, HospitalBuilder.LIFT_TAG)
end

-- One collidable wedge per storey (a WedgePart rises toward its +Z, so it is turned to rise along x).
local function buildStairs(model: Model, floors: number)
	local stairs = piece(model, "Stairs", sinceFloor(1), 0)
	for k = 0, floors - 1 do
		local fl = Pure.flight(B, k)
		local rise, run = fl.YHigh - fl.YLow, math.abs(fl.XHigh - fl.XLow)
		local turn = if fl.XHigh > fl.XLow then math.pi / 2 else -math.pi / 2
		local flight = wedge(
			stairs,
			"Flight_" .. k,
			Vector3.new(fl.Z1 - fl.Z0, rise, run),
			CFrame.new((fl.XLow + fl.XHigh) / 2, fl.YLow + rise / 2, (fl.Z0 + fl.Z1) / 2) * CFrame.Angles(0, turn, 0),
			WORLD.PlankAlt
		)
		flight.Material = Enum.Material.WoodPlanks
		flight:SetAttribute("Since", sinceFloor(k + 1))
		flight:SetAttribute("Storey", k)
	end
end

-- Floor_k: its slab, its landing, its rails and (indoors) its studded walls, front glass band, ribbon windows and
-- department dado; the roof deck (Floor_4) gets parapets instead.
local function buildFloor(model: Model, style: Style, k: number, hasPharmacy: boolean)
	local floorModel = piece(model, "Floor_" .. k, sinceFloor(k), k)
	local y = B.slabTop(k)
	local deck = k >= ROOF_FLOOR
	for _, r in Pure.slabRects(B, k) do
		local slab = box(
			floorModel,
			r.Name,
			r.X0,
			r.X1,
			y - Pure.SLAB,
			y,
			r.Z0,
			r.Z1,
			if deck then WORLD.Roof else WORLD.FloorA,
			if deck then Enum.Material.SmoothPlastic else Enum.Material.WoodPlanks
		)
		slab.CanCollide = true
	end
	landingMarker(floorModel, "Landing", k)
	local rails = Pure.rails(B, k)
	local railTop = y + Pure.RAIL.Height
	if not (k == PHARMACY_FLOOR and hasPharmacy) then -- on F3 the Pharmacy's shelf is the long rail
		local long = rails.Long
		painted(box(floorModel, "Rail", long.X0, long.X1, y, railTop, long.Z0, long.Z1, style.Trim), "Trim")
	end
	local e = rails.End
	painted(box(floorModel, "RailEnd", e.X0, e.X1, y, railTop, e.Z0, e.Z1, style.Trim), "Trim")

	local f = B.footprint(B.MAX_LEVEL, k)
	local h, w = B.HALF, B.WALL
	local s = B.SHAFT
	local front = if f.Z0 < s.Z0 then -h else s.X1 -- F1's front runs the whole width; the tower's starts at the shaft
	if deck then
		local p = Pure.PARAPET
		box(floorModel, "ParapetFront", front, h, y, y + p, f.Z0, f.Z0 + w, WORLD.Roof)
		box(floorModel, "ParapetBack", -h, h, y, y + p, f.Z1 - w, f.Z1, WORLD.Roof)
		box(floorModel, "ParapetLeft", -h, -h + w, y, y + p, s.Z1, f.Z1 - w, WORLD.Roof)
		box(floorModel, "ParapetRight", h - w, h, y, y + p, f.Z0 + w, f.Z1 - w, WORLD.Roof)
		return
	end
	local top = Pure.wallTop(B, k)
	-- The street face: a studded spandrel and the glass band over it, with the floor's icon floating on the glass.
	outerWall(floorModel, "WallSpandrel", front, h, y, y + Pure.SPANDREL, f.Z0, f.Z0 + w, style)
	local glassBand = glass(floorModel, "GlassBand", front, h, y + Pure.SPANDREL, top, f.Z0, f.Z0 + w)
	local width = h - front
	local iconGui = surface(glassBand, "IconGui", Enum.NormalId.Front, 20, 200, 0)
	local iconSize = math.min(0.7, 3.4 / (top - y - Pure.SPANDREL))
	floatText(iconGui, deptIcon(deptOn(k), "🏥"), {
		Size = UDim2.fromScale(3.4 / width, iconSize),
		Position = UDim2.fromScale(0.5 / width, (1 - iconSize) / 2),
	})
	-- The back and the sides, with a ribbon window on each.
	outerWall(floorModel, "WallBack", -h, h, y, top, f.Z1 - w, f.Z1, style)
	ribbon(floorModel, "Back", -h, h, y, f.Z1)
	local longest: { Z0: number, Z1: number }? = nil
	for i, span in Pure.segments(f.Z0 + w, f.Z1 - w, { { Z0 = s.Z0, Z1 = s.Z1 } }) do
		outerWall(
			floorModel,
			if i == 1 then "WallLeft" else "WallLeftBack",
			-h,
			-h + w,
			y,
			top,
			span.Z0,
			span.Z1,
			style
		)
		if not longest or span.Z1 - span.Z0 > longest.Z1 - longest.Z0 then
			longest = span
		end
	end
	if longest then
		ribbon(floorModel, "Left", longest.Z0, longest.Z1, y)
	end
	outerWall(floorModel, "WallRight", h - w, h, y, top, f.Z0 + w, f.Z1 - w, style)
	ribbon(floorModel, "Right", f.Z0 + w, f.Z1 - w, y)
	-- The department's colour inside: a studded dado band along the +x wall.
	local dept = deptOn(k)
	local color = if dept then DEPT[dept] else nil
	if color then
		local dado = soft(
			box(floorModel, "Dado", h - w - Pure.DADO.Thick, h - w, y, y + Pure.DADO.Height, f.Z0 + w, f.Z1 - w, color)
		)
		Studs.apply(dado)
		dado.CastShadow = false
	end
	local slab = floorModel:FindFirstChild("Slab")
	if slab and slab:IsA("BasePart") then
		roomLight(slab, Vector3.new(0, top - 1, (f.Z0 + f.Z1) / 2))
	end
end

------------------------------------------------------------------------------------------------------------------
-- The departments
------------------------------------------------------------------------------------------------------------------

-- F1, the Wards: the main ward's three bed spots (functional from their level, made up before), the front ward's
-- four made-up beds (two with sleepers), curtains and the glass partition. `keep`: bed spots moving across.
local function buildWards(model: Model, level: number, keep: { [number]: boolean })
	local wards = piece(model, "Wards", sinceDept("Wards"), WARDS_FLOOR)
	local y = B.slabTop(WARDS_FLOOR)
	local color = DEPT.Wards
	local dressing = Instance.new("Model")
	dressing.Name = "Dressing"
	dressing.Parent = wards
	local functional = extraBeds(level)
	local bedHalf = Pure.BED.Width / 2
	for index, spot in B.WARD_BEDS do
		if index <= functional then
			if not keep[index] then
				wardBed(wards, index, spot.X, y)
			end
		else
			-- Not open yet: a made-up bed in the same spot, pillow at the partition.
			local r = { X0 = spot.X - bedHalf, X1 = spot.X + bedHalf, Z0 = B.BED_Z0, Z1 = B.BED_Z1 }
			dressBed(dressing, #B.FRONT_WARD.Xs + index, r, y, -1, color, false)
		end
	end
	-- The front ward: heads at the street window, frames up to its z.
	local front = B.FRONT_WARD
	local sleepers = Pure.sleepers(#front.Xs, Config.Look.Sleepers.Ward)
	for index, x in front.Xs do
		local r = { X0 = x - bedHalf, X1 = x + bedHalf, Z0 = math.max(front.Z0, B.FRONT + B.WALL), Z1 = front.Z1 }
		dressBed(dressing, index, r, y, -1, color, sleepers[index] == true)
	end
	-- Curtains between the main ward's beds, and between the front ward's outer pairs.
	local curtainH = 5.4
	local mainZ0, mainZ1 = B.BED_Z0 + 0.4, B.BED_Z1 - 0.4
	for i = 1, #B.WARD_BEDS - 1 do
		local x = (B.WARD_BEDS[i].X + B.WARD_BEDS[i + 1].X) / 2
		soft(
			box(wards, "Curtain", x - 0.1, x + 0.1, y + 0.6, y + curtainH, mainZ0, mainZ1, color, Enum.Material.Fabric)
		)
	end
	local xs = front.Xs
	for _, pair in { { xs[1], xs[2] }, { xs[#xs - 1], xs[#xs] } } do
		local x = (pair[1] + pair[2]) / 2
		soft(
			box(
				wards,
				"Curtain",
				x - 0.1,
				x + 0.1,
				y + 0.6,
				y + curtainH,
				B.FRONT + B.WALL + 0.5,
				front.Z1 - 0.6,
				color,
				Enum.Material.Fabric
			)
		)
	end
	-- The glass partition: glass over the main ward's headboards, from the shaft to its doorway.
	local z = B.PARTITION_Z
	glass(
		wards,
		"GlassPartition",
		B.SHAFT.X1,
		B.DOORS.Partition.X0,
		y + Pure.BED.HeadboardHeight,
		Pure.wallTop(B, WARDS_FLOOR),
		z - B.WALL / 2,
		z + B.WALL / 2
	)
end

-- F2, Hydro: the round hot tub (patients soak at its two TubSpots; the SoakPrompt waits at its landing side), a
-- towel shelf and a plant.
local function buildHydro(model: Model)
	local hydro = piece(model, "Hydro", sinceDept("Hydro"), HYDRO_FLOOR)
	local t = Pure.TUB
	local y = B.slabTop(HYDRO_FLOOR)
	local tubModel = Instance.new("Model")
	tubModel.Name = "HotTub"
	local tub = cylinder(tubModel, "Tub", t.Rim, t.Diameter, CFrame.new(t.X, y + t.Rim / 2, t.Z), DEPT.Hydro)
	paint(cylinder(tubModel, "Water", 0.1, t.Diameter - 1, CFrame.new(t.X, y + t.Rim + 0.05, t.Z), WORLD.Water))
	for i, at in Pure.TUB_SPOTS do
		local spot = marker(tubModel, "TubSpot_" .. i, CFrame.new(at.X, y + t.Rim + 0.5, at.Z))
		spot:SetAttribute("Floor", HYDRO_FLOOR)
	end
	local point = Instance.new("Attachment")
	point.Name = "SoakPoint"
	point.CFrame = tub.CFrame:ToObjectSpace(CFrame.new(t.X - t.Diameter / 2, y + 2.6, t.Z))
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
	local h, w = B.HALF, B.WALL
	local inner = h - w - Pure.DADO.Thick
	box(hydro, "TowelShelf", inner - 0.7, inner, y, y + 3, 0, 4, WORLD.Plank, Enum.Material.WoodPlanks)
	local plant = Pure.PLANTER
	Studs.apply(
		box(
			hydro,
			"Plant",
			inner - plant - 0.1,
			inner - 0.1,
			y,
			y + plant,
			B.TOWER_FRONT + 0.8,
			B.TOWER_FRONT + 0.8 + plant,
			WORLD.LeavesA
		)
	)
end

-- F3, the Pharmacy: the station Model by the station contract (Server/Stations finds it by its tag), the medicine
-- shelf along the atrium (it is that floor's rail) and a bench by the front glass.
local function buildPharmacy(model: Model)
	local pharmacy = piece(model, "Pharmacy", sinceDept("Pharmacy"), PHARMACY_FLOOR)
	local p = Pure.PHARMACY
	local y = B.slabTop(PHARMACY_FLOOR)
	local data = rawget(Stations :: any, "Pharmacy")
	local station = Instance.new("Model")
	station.Name = "Station_Pharmacy"
	local counter = box(
		station,
		"Counter",
		p.X - p.Width / 2,
		p.X + p.Width / 2,
		y,
		y + p.Height,
		p.Z - p.Depth / 2,
		p.Z + p.Depth / 2,
		DEPT.Pharmacy
	)
	station.PrimaryPart = counter
	Studs.apply(
		box(
			station,
			"Top",
			p.X - p.Width / 2 - 0.15,
			p.X + p.Width / 2 + 0.15,
			y + p.Height,
			y + p.Height + 0.3,
			p.Z - p.Depth / 2 - 0.15,
			p.Z + p.Depth / 2 + 0.15,
			WORLD.Trim
		)
	)
	iconBadge(
		counter,
		"IconGui",
		if data then data.Icon else "💊",
		if data then data.Color else DEPT.Pharmacy,
		2.6,
		p.Height / 2 + 2.1
	)
	CollectionService:AddTag(station, HospitalBuilder.STATION_TAG)
	station.Parent = pharmacy
	-- The shelf stands where F3's long rail would: inside the open lane, along its edge.
	local long = Pure.rails(B, PHARMACY_FLOOR).Long
	local shelf = box(
		pharmacy,
		"Shelf",
		long.X0,
		long.X1,
		y,
		y + Pure.SHELF.Height,
		long.Z0,
		long.Z0 + Pure.SHELF.Thick,
		WORLD.PlankAlt,
		Enum.Material.WoodPlanks
	)
	local gui = surface(shelf, "ShelfGui", Enum.NormalId.Front, 16, 80)
	local bottles = { ACCENT.Pink, ACCENT.Yellow, ACCENT.Cyan, ACCENT.Purple, ACCENT.Orange, ACCENT.Blue }
	for col = 1, 12 do
		local bottle = band(
			gui,
			"Bottle",
			UDim2.fromScale(0.03, 0.22),
			UDim2.fromScale((col - 0.5) / 12, 0.72),
			bottles[(col - 1) % #bottles + 1]
		)
		Parts.rounded(bottle, UDim.new(0.35, 0))
	end
	floatText(gui, "💊 Pharmacy", {
		Shadow = true,
		Size = UDim2.fromScale(0.5, 0.36),
		Position = UDim2.fromScale(0.25, 0.08),
	})
	local b = Pure.BENCH
	box(pharmacy, "Bench", b.X0, b.X1, y, y + b.Height, b.Z0, b.Z1, WORLD.Plank, Enum.Material.WoodPlanks)
end

-- Lv 3+: F1's roof in front of the tower, dark, with a parapet on its street edge.
local function buildTerrace(model: Model)
	local terrace = piece(model, "Terrace", sinceFloor(2), WARDS_FLOOR + 1)
	local h, f, w = B.HALF, B.FRONT, B.WALL
	local y = B.slabTop(WARDS_FLOOR + 1)
	box(terrace, "RoofTerrace", -h, h, y - Pure.SLAB, y, f, B.TOWER_FRONT, WORLD.Roof)
	box(terrace, "ParapetTerrace", -h, h, y, y + Pure.PARAPET, f, f + w, WORLD.Roof)
end

-- Lv 2-4: the top roof (over the whole block at Lv 2, the tower from Lv 3), its edge band, the lift's head and
-- (Lv 3-4) the paw-heart on its street edge. Returns where a theme prop stands, and the front edge (icicles).
local function buildRoofTop(model: Model, style: Style, level: number, floors: number): (CFrame, CFrame, number)
	local storey = floors + 1
	local roofTop = piece(model, "RoofTop", level, storey)
	local h = B.HALF
	local f = B.footprint(B.MAX_LEVEL, floors) -- the top floor's: the whole block at Lv 2, the tower from Lv 3
	local top = Pure.roofTop(B, floors)
	box(roofTop, "RoofCap", -h - 0.2, h + 0.2, top - Pure.SLAB, top, f.Z0 - 0.2, f.Z1 + 0.2, WORLD.Roof)
	local s = B.SHAFT
	local x0 = if f.Z0 < s.Z0 then -h - 0.2 else s.X1 -- the tower's front edge starts beside the lift's head
	painted(paint(box(roofTop, "BandRoof", x0, h + 0.2, top, top + 0.4, f.Z0 - 0.2, f.Z0 + 0.4, style.Band)), "Band")
	Studs.apply(box(roofTop, "LiftHead", s.X0, s.X1, top, top + Pure.LIFT_HEAD, s.Z0, s.Z1, style.Accent))
	local spot = if floors <= WARDS_FLOOR then Pure.PROP.Block else Pure.PROP.Tower
	if floors > WARDS_FLOOR then
		-- The "big sign" (Data/Levels Lv 3): the paw-heart on the tower's roof edge, over the band, facing the street.
		local d = 5
		pawSign(roofTop, "LogoSign", CFrame.new((s.X1 + h) / 2, top + 0.4 + d / 2, f.Z0 - 0.1), d, style)
	end
	return CFrame.new(spot.X, top, spot.Z), CFrame.new((x0 + h) / 2, top - Pure.SLAB, f.Z0 - 0.25), h - x0
end

-- Lv 5: the helipad (a ring and an H drawn on one flat invisible part), HeliSpot and the roof garden, and the lift
-- tower's head with the neon paw-heart and the beacon. Returns where a theme prop stands, and the deck's front edge.
local function buildRoofDeck(model: Model, style: Style): (CFrame, CFrame, number)
	local roof = piece(model, "Roof", sinceDept("Roof"), ROOF_FLOOR)
	local y = B.slabTop(ROOF_FLOOR)
	local pad = Pure.PAD
	local surfacePart = paint(
		part(
			roof,
			"Helipad",
			Vector3.new(pad.Diameter, 0.1, pad.Diameter),
			CFrame.new(pad.X, y + 0.06, pad.Z),
			WORLD.Roof
		)
	)
	surfacePart.Transparency = 1
	local gui = surface(surfacePart, "PadGui", Enum.NormalId.Top, 12, 300, 1)
	disc(gui, "Ring", 1, Palette.Gold, 1)
	disc(gui, "Inner", 0.84, WORLD.Road, 2)
	local letter = floatText(gui, "H", { Size = UDim2.fromScale(0.44, 0.44), Position = UDim2.fromScale(0.28, 0.28) })
	letter.ZIndex = 4
	local heli = marker(roof, "HeliSpot", CFrame.new(pad.X, y + 0.5, pad.Z))
	heli:SetAttribute("ArriveAt", 0) -- Server/Patients sets it; Feel/HospitalFX flies the helicopter in
	local size = Pure.PLANTER
	for i, at in Pure.PLANTERS do
		local planter = box(
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
		Studs.apply(planter)
	end
	-- The lift tower's head, over the glass shaft: the neon paw-heart on its street face and the beacon on top.
	local tower = piece(model, "Tower", sinceDept("Roof"), ROOF_FLOOR)
	local s = B.SHAFT
	local base = Pure.shaftTop(B, ROOF_FLOOR, ROOF_FLOOR)
	Studs.apply(box(tower, "TowerHead", s.X0, s.X1, base, base + Pure.HEAD, s.Z0, s.Z1, style.Accent))
	local cx = (s.X0 + s.X1) / 2
	local logo = pawSign(tower, "LogoNeon", CFrame.new(cx, base + Pure.HEAD / 2, s.Z0 - 0.25), 4, style)
	NightLights.light(logo, 24) -- the building's one light; the disc goes Neon after dark
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
	local spot = Pure.PROP.Tower
	local h = B.HALF
	return CFrame.new(spot.X, y, spot.Z), CFrame.new((s.X1 + h) / 2, y - Pure.SLAB, B.TOWER_FRONT - 0.25), h - s.X1
end

-- A&E: the ambulance bay on the front-left lawn and a toy Ambulance parked nose to the street: warm white, a red
-- stripe round it, the paw-heart on its side (never a cross), sirens that go Neon at night. The StretcherSpot by
-- its side door faces the line (Server/Patients pops an urgent patient out there).
local function buildAmbulanceBay(model: Model, style: Style)
	local bay = piece(model, "AmbulanceBay", sinceDept("AE"), 0)
	local at = CFrame.new(Pure.BAY.X, 0, Pure.BAY.Z)
	paint(part(bay, "BayFloor", Vector3.new(7.4, 0.06, 13), at * CFrame.new(0, 0.04, 0), WORLD.Road))
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
	marker(van, "StretcherSpot", at * CFrame.new(3.6, 0.5, 1.3) * CFrame.Angles(0, -math.pi / 2, 0))
	van:SetAttribute("ArriveAt", 0) -- Server/Patients sets it; Feel/HospitalFX flashes and sirens
	van.Parent = bay
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

-- The Stand room's floor top (plot-local), where the podium's bench and the Lv 1 bed stand.
local function standFloorTop(plotModel: Model): number
	local rooms = plotModel:FindFirstChild("Rooms")
	local stand = rooms and rooms:FindFirstChild("Room_Stand")
	local floor = if stand and stand:IsA("Model") then stand.PrimaryPart or stand:FindFirstChild("Floor") else nil
	if floor and floor:IsA("BasePart") then
		local y = plotModel:GetPivot():PointToObjectSpace(floor.Position).Y + floor.Size.Y / 2
		if y > -1 and y < 3 then
			return y
		end
	end
	return Pure.STAND_TOP
end

-- Builds the hospital in plot-local space (the plot's ground-top centre at the origin, -Z to the street). Bed spots
-- whose index is in `keep` are left out: the old ones move across.
local function placeholderBuilding(plotModel: Model, level: number, keep: { [number]: boolean }, themeId: string): Model
	local model = Instance.new("Model")
	local row = LevelsData[level]
	local style = buildingStyle(plotAccent(plotModel), themeId)
	local floors = if row then math.max(0, row.Floors) else 0
	local standTop = standFloorTop(plotModel)
	buildPodium(model, style, standTop, if row then row.Name else "")
	local spot: CFrame, edge: CFrame, width: number, storey: number
	if floors == 0 then
		buildPodiumShell(model, style, standTop)
		-- A theme's prop stands on the podium's roof; icicles hang from the canopy's edge.
		local canopy = B.CANOPY
		spot = CFrame.new(Pure.PROP.Podium.X, B.GROUND, Pure.PROP.Podium.Z)
		edge = CFrame.new((canopy.X0 + canopy.X1) / 2, canopy.Y - 0.25, canopy.Z0 - 0.15)
		width = canopy.X1 - canopy.X0
		storey = 1
	else
		local roofWalkable = floors >= ROOF_FLOOR
		local hasPharmacy = hasDept(row, "Pharmacy") and PHARMACY_FLOOR <= floors
		buildHall(model, style, floors)
		local landing0 = landingMarker(model, "Landing_0", 0)
		landing0:SetAttribute("Since", sinceFloor(1))
		landing0:SetAttribute("Storey", 0)
		buildLift(model, style, floors)
		buildStairs(model, floors)
		for k = 1, floors do
			buildFloor(model, style, k, hasPharmacy)
		end
		if hasDept(row, "Wards") and WARDS_FLOOR <= floors then
			buildWards(model, level, keep)
		end
		if hasDept(row, "Hydro") and HYDRO_FLOOR <= floors then
			buildHydro(model)
		end
		if hasPharmacy then
			buildPharmacy(model)
		end
		if hasDept(row, "AE") then
			buildAmbulanceBay(model, style)
		end
		if floors > WARDS_FLOOR then
			buildTerrace(model)
		end
		if roofWalkable then
			spot, edge, width = buildRoofDeck(model, style)
			storey = ROOF_FLOOR
		else
			spot, edge, width = buildRoofTop(model, style, level, floors)
			storey = floors + 1
		end
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
		-- Keep the bed spots that stay (a patient may be resting on one): same index, same spot.
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
	-- The plot-local frame, for Feel/Cutaway (which falls back to the Building's pivot): never worth a failed build.
	pcall(building.SetAttribute, building, "Origin", plotModel:GetPivot())
	if old then
		old:Destroy()
	end
	building.Parent = plotModel
	plotModel:SetAttribute("Level", lv)
	plotModel:SetAttribute("Theme", themeId)
	return building
end

return HospitalBuilder
