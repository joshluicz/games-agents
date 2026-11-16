--!strict
-- The game's colours and fonts, shared by the server (world, creatures, billboards) and the client (UI/Theme).
-- Change a colour here, not per part. Not Lune-safe by itself (Color3); tests/Palette.spec loads it with Lune's
-- roblox datatypes.
--
-- The look overhaul (memory-20261117-001; docs/research/2026-11-16-art-direction.md §4.1; look build plan §B3):
-- "saturated, flashy, trending" stands (memory-20261116-007), but the WORLD is no longer pastel candy. World colours
-- are albedo values, before lighting: big surfaces at mid value, dark anchors (road, plot pad, roofs), warm whites
-- capped at 240, and never a lerp toward white for a surface bigger than trim. The UI is unlit, so it keeps the
-- brighter Candy hues.
--   Palette.World       surfaces. Its material is set by Server/World/Studs or the builder (noted per key)
--   Palette.Accent      world accents: plot and room colours, props
--   Palette.PlotColors  Plot_1..6: Pink, Blue, Orange, Purple, Yellow, Cyan (Yellow replaced Lime, which vanished
--                       against the grass)
--   Palette.Departments the departments' colours, used INSIDE only (dado bands, curtains, blankets, headboards, the
--                       lift buttons). Reception has no entry: it wears the plot's colour
--   Palette.Navy        the Now card, every panel header and every world information plate
--   Palette.Gold        gold world titles
--   Palette.Candy       the UI's bright set (unchanged)
-- Every key the candy-pop Palette had is still here as an ALIAS of its new value (see "Old keys"), so files the
-- overhaul hasn't reached keep compiling and pick up the calmer colours.

local Palette = {}

local hex = Color3.fromHex

-- Ink: every thick outline, every text stroke, and dark text on light panels.
Palette.Outline = hex("#1B1238")
Palette.Ink = hex("#221A48")
Palette.InkSoft = hex("#5D5788")
Palette.White = Color3.fromRGB(255, 255, 255) -- UI and floating text only: no world surface is pure white
Palette.Navy = hex("#1E2440")
Palette.Gold = hex("#FFD84A")

-- The candy set: UI buttons, accents, creature colours. Bright and fully saturated (the UI is unlit).
Palette.Candy = table.freeze({
	Lime = Color3.fromRGB(80, 220, 60),
	Orange = Color3.fromRGB(255, 150, 30),
	Pink = Color3.fromRGB(255, 70, 170),
	Blue = Color3.fromRGB(40, 170, 255),
	Purple = Color3.fromRGB(160, 80, 255),
	Red = Color3.fromRGB(255, 64, 90),
	Yellow = Color3.fromRGB(255, 214, 30),
	Cyan = Color3.fromRGB(0, 214, 232),
	Mint = Color3.fromRGB(40, 228, 170),
})

-- World accents (art-direction §4.1). Red and Lime are for props only: never a plot, and Red is never a cross.
Palette.Accent = table.freeze({
	Pink = hex("#DB3D7D"),
	Blue = hex("#3195E0"),
	Orange = hex("#EB842A"),
	Purple = hex("#894ECC"),
	Cyan = hex("#29BCCC"),
	Yellow = hex("#F5C731"),
	Red = hex("#D63C4B"), -- props only: the A&E canopy, the ambulance stripe
	Lime = hex("#6ACC39"), -- props only
})

-- Each plot's own colour (its walls, gate arch, sign letters), Plot_1 .. Plot_6. Never red.
Palette.PlotColors = table.freeze({
	Palette.Accent.Pink,
	Palette.Accent.Blue,
	Palette.Accent.Orange,
	Palette.Accent.Purple,
	Palette.Accent.Yellow,
	Palette.Accent.Cyan,
})

local GRASS_A = hex("#56C740")
local GRASS_B = hex("#3FB536")
local LEAVES_A = hex("#39A844")
local LEAVES_C = hex("#67C246")
local PLANK = hex("#D6B27C")
local PLANK_ALT = hex("#BA9265")
local ROAD = hex("#3E4352")
local ROAD_LINE = hex("#F0EBE1")
local BEAM = hex("#805738")
local FLOOR_A = hex("#AD8053")
local WALL_UPPER = hex("#EBE4D8")

-- The world. The material beside each key is what Server/World/Studs or the builder gives it.
Palette.World = table.freeze({
	GrassA = GRASS_A, -- Plastic, studded
	GrassB = GRASS_B, -- Plastic, studded (the checker's darker tile)
	Dirt = hex("#8C603E"), -- Plastic, studded
	LeavesA = LEAVES_A, -- Plastic, studded (voxel cubes)
	LeavesB = hex("#2B8F42"),
	LeavesC = LEAVES_C,
	Trunk = hex("#704B31"), -- Wood
	Plank = PLANK, -- WoodPlanks
	PlankAlt = PLANK_ALT,
	Road = ROAD, -- SmoothPlastic: a dark anchor
	RoadLine = ROAD_LINE, -- SmoothPlastic
	Curb = hex("#999CA3"), -- Slate
	Pad = hex("#253D4C"), -- Plastic, studded: a dark anchor
	Edge = hex("#8A8E94"), -- Slate
	Roof = hex("#2D2B3D"), -- SmoothPlastic: a dark anchor
	Trim = hex("#F0EBDF"), -- SmoothPlastic: the warm white
	Beam = BEAM, -- Wood
	Fence = hex("#EBE6DA"), -- SmoothPlastic
	CheckerTeal = hex("#369E94"), -- Plastic, studded (an optional backdrop)
	CheckerCream = hex("#EBDEC0"),
	Water = hex("#38A7D6"), -- Glass 0.3
	FloorA = FLOOR_A, -- WoodPlanks (interior floors, slabs)
	FloorB = hex("#996B45"),
	WallUpper = WALL_UPPER, -- SmoothPlastic (the interior upper wall)
	Window = hex("#2F3B57"), -- SmoothPlastic (the opaque ribbon windows)
	Glass = hex("#CDE8F5"), -- Glass at Transparency 0.55: the see-through bands (the navy Window read as black)
	WindowNight = hex("#D8B470"), -- warm at night, NOT Neon
	Pavement = hex("#CDB38A"), -- SmoothPlastic: the queue lane, in mid-tones ...
	PavementAlt = hex("#B79D74"), -- ... checkered ...
	PavementGrout = hex("#8A7558"), -- ... and the lines between
	Lamp = Color3.fromRGB(255, 232, 140), -- unchanged: Neon at night only, small parts only
	-- Old keys (aliases; new code uses the names above)
	Grass = GRASS_A,
	GrassDark = GRASS_B,
	Path = PLANK,
	Street = ROAD,
	StreetLine = ROAD_LINE,
	Wood = PLANK_ALT,
	WoodDark = BEAM,
	Leaves = LEAVES_A,
	LeavesLight = LEAVES_C,
	Floor = FLOOR_A,
	Wall = WALL_UPPER,
})

-- Inside only. Reception = the plot's colour (no entry).
Palette.Departments = table.freeze({
	Wards = Palette.Accent.Purple,
	Hydro = Palette.Accent.Cyan,
	Pharmacy = Palette.Accent.Blue,
	Roof = LEAVES_A,
	AE = Palette.Accent.Red,
}) :: { [string]: Color3 }

-- Fonts: a chunky display font for titles, buttons and numbers; a round one for reading.
Palette.DisplayFont = Enum.Font.LuckiestGuy
Palette.BodyFont = Enum.Font.FredokaOne

Palette.OutlineThickness = 3 -- shapes (UIStroke Border)
Palette.TextOutlineThickness = 2.5 -- text (UIStroke Contextual)

-- Gives a TextLabel/TextButton/TextBox the outlined-text look (white text with a dark stroke). Works on billboards
-- and SurfaceGuis too. Returns the UIStroke.
function Palette.outlineText(text: GuiObject, thickness: number?): UIStroke
	local existing = text:FindFirstChild("TextOutline")
	local stroke: UIStroke = if existing and existing:IsA("UIStroke") then existing else Instance.new("UIStroke")
	stroke.Name = "TextOutline"
	stroke.Color = Palette.Outline
	stroke.Thickness = thickness or Palette.TextOutlineThickness
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = text
	return stroke
end

-- A thick dark outline around a frame or button's shape. Returns the UIStroke.
function Palette.outlineShape(gui: GuiObject, thickness: number?): UIStroke
	local existing = gui:FindFirstChild("ShapeOutline")
	local stroke: UIStroke = if existing and existing:IsA("UIStroke") then existing else Instance.new("UIStroke")
	stroke.Name = "ShapeOutline"
	stroke.Color = Palette.Outline
	stroke.Thickness = thickness or Palette.OutlineThickness
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = gui
	return stroke
end

-- The button gradient: lighter at the top, a little deeper at the bottom. Put it on a GuiObject whose
-- BackgroundColor3 is the base colour. Kept light enough that white text on it stays white.
function Palette.candyGradient(parent: GuiObject): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Name = "CandyGradient"
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(222, 222, 222))
	gradient.Parent = parent
	return gradient
end

return table.freeze(Palette)
