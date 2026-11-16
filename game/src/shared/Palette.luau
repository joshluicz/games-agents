--!strict
-- The game's colours and fonts, shared by the server (world, creatures, billboards) and the client (UI/Theme).
-- The look is "candy pop": saturated colours, thick dark outlines and chunky outlined text, like the top kids'
-- games (memory-20261116-007). Change a colour here, not per part. Not Lune-safe (Color3), so Logic never uses it.

local Palette = {}

-- Ink: every thick outline, every text stroke, and dark text on light panels.
Palette.Outline = Color3.fromRGB(24, 16, 52)
Palette.Ink = Color3.fromRGB(36, 24, 72)
Palette.InkSoft = Color3.fromRGB(98, 86, 140)
Palette.White = Color3.fromRGB(255, 255, 255)

-- The candy set: buttons, accents, plot colours, creature colours. Bright and fully saturated.
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

-- Each plot's own accent (gate arch, awning, sign), Plot_1 .. Plot_6.
Palette.PlotColors = table.freeze({
	Palette.Candy.Pink,
	Palette.Candy.Blue,
	Palette.Candy.Orange,
	Palette.Candy.Purple,
	Palette.Candy.Lime,
	Palette.Candy.Cyan,
})

-- The world: toy-like and bright. Mostly SmoothPlastic, a little Neon for glow; no realistic materials.
Palette.World = table.freeze({
	Grass = Color3.fromRGB(96, 214, 72),
	GrassDark = Color3.fromRGB(62, 180, 58),
	Path = Color3.fromRGB(255, 224, 150),
	Street = Color3.fromRGB(118, 124, 168),
	StreetLine = Color3.fromRGB(255, 255, 255),
	Fence = Color3.fromRGB(255, 255, 255),
	Wood = Color3.fromRGB(222, 142, 70),
	WoodDark = Color3.fromRGB(170, 96, 48),
	Leaves = Color3.fromRGB(64, 204, 82),
	LeavesLight = Color3.fromRGB(132, 236, 86),
	Trunk = Color3.fromRGB(150, 92, 52),
	Water = Color3.fromRGB(40, 196, 255),
	Floor = Color3.fromRGB(255, 244, 222),
	Wall = Color3.fromRGB(255, 255, 255),
	Lamp = Color3.fromRGB(255, 232, 140),
})

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

-- The candy gradient: lighter at the top, a little deeper at the bottom. Put it on a GuiObject whose
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
