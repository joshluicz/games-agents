--!strict
-- The generic part and label helpers every world builder shares (look build plan §B4). Server only. FROZEN after
-- the look overhaul's Foundation: ask the lead for a change.
-- Moved here, unchanged, from PlotBuilder (the split): part, soft, ball, cylinder, wedge, marker, paint, rounded,
-- surface and iconBadge. New with the overhaul, so the town, the plots and the building read as one family:
-- floatText, navyPlate and pawHeart.
--
--   Parts.part(parent, name, size, cframe, color, material?): Part     anchored, SmoothPlastic unless given
--   Parts.soft(part): BasePart              a decoration players walk through and rays ignore
--   Parts.ball(parent, name, diameter, cframe, color): Part
--   Parts.cylinder(parent, name, height, diameter, cframe, color, material?): Part   upright; `cframe` its centre
--   Parts.wedge(parent, name, size, cframe, color): WedgePart
--   Parts.marker(parent, name, cframe, size?): Part    an invisible 2x1x2 marker (no collide, no query, no shadow)
--   Parts.paint(part): BasePart             a flat painted detail: soft and shadowless
--   Parts.rounded(gui, radius: UDim)        a UICorner
--   Parts.surface(part, name, face, pixels, maxDistance?, lightInfluence?): SurfaceGui
--                                           a SurfaceGui sized in studs (PixelsPerStud), hidden past maxDistance
--                                           (DETAIL_NEAR unless given), lit like its part unless lightInfluence is
--                                           given (0 = stays bright at night)
--   Parts.iconBadge(adornee, name, icon, ring, studs, height): BillboardGui   a station's floating icon badge
--   Parts.floatText(gui, text, props?): TextLabel
--                                           art-direction §4.4: NO board. BackgroundTransparency 1, the display
--                                           font, white (props.Gold: gold) with a 3.5 px ink stroke, and with
--                                           props.Shadow a second label 2 px lower in ink at 0.5 transparency.
--                                           props.Size / props.Position place it (the whole gui unless given)
--   Parts.navyPlate(gui, props?): Frame     a board ONLY where there is a table to read (the odds sign, the
--                                           leaderboards, the lift directory): navy at 0.15 transparency, a large
--                                           radius, a 4 px ink stroke. White text goes on it. props.Size /
--                                           props.Position place it (the whole gui, inset by its stroke, unless given)
--   Parts.pawHeart(parent, size, color): Frame
--                                           OUR placeholder mark (the brothers design the final one): a heart (two
--                                           discs and a turned square) in `color` with three white toe pads and
--                                           one white main pad, inside a warm-white rim. 8 Frames, no images. It
--                                           replaces every cross: never a red cross, a white cross on red or any
--                                           medical emblem (CLAUDE.md red line 2; the build plan's Global constraints)
-- Also here because more than one builder needs them:
--   Parts.lighten(color, amount) · Parts.darken(color, amount)
--   Parts.anchorAll(model) · Parts.scrubScripts(model, source)   kit models: anchored, and no scripts, Highlights or
--                                           shadow-casting lights (the perf budget)
--   Parts.band(gui, name, size, position, color): Frame · Parts.disc(parent, name, scale, color, zIndex): Frame
--   Parts.iconLabel(parent, name, text, size, position): TextLabel
--   LEGACY (the candy look; T2-T4 replace their uses with floatText and navyPlate, then these go):
--   Parts.candyLabel(parent, name, text, size, position, stroke): TextLabel · Parts.candyBoard(gui, color, inset,
--   radius, rim): Frame
--   Parts.DETAIL_NEAR · Parts.ICON_NEAR · Parts.PREVIEW_NEAR   the distances the details and billboards use

local Shared = game:GetService("ReplicatedStorage").Shared
local Palette = require(Shared.Palette)

local Parts = {}

local WHITE = Palette.White

local function lighten(color: Color3, amount: number): Color3
	return color:Lerp(WHITE, amount)
end

local function darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

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

-- Flat details drawn on a face instead of built from parts (the parts budget): a SurfaceGui sized in studs, at a low
-- resolution (flat shapes need little), hidden past `maxDistance` so far plots don't draw them. Lit like the part
-- (so it dims at night with it) unless `lightInfluence` says otherwise.
local DETAIL_NEAR = 160 -- studs: room and yard details
local function surface(
	p: BasePart,
	name: string,
	face: Enum.NormalId,
	pixels: number,
	maxDistance: number?,
	lightInfluence: number?
): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixels
	gui.LightInfluence = lightInfluence or 1
	gui.MaxDistance = maxDistance or DETAIL_NEAR
	gui.Parent = p
	return gui
end

-- A flat band (scale units, centred at `position`) on a detail gui.
-- Orientation (checked in Studio for the queue lane's numbers, 2026-11-16): on a part's Top face the gui's X runs
-- along the part's -Z and its Y along the part's +X; on a side face its Y is up. Bands drawn here are symmetric, so
-- they read the same either way round.
local function band(gui: SurfaceGui, name: string, size: UDim2, position: UDim2, color: Color3): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = position
	f.Size = size
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = gui
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
		warn("[World] Removed " .. removed .. " script(s) from " .. source .. " (kit models are scenery only)")
	end
	if highlights > 0 then
		warn("[World] Removed " .. highlights .. " Highlight(s) from " .. source .. " (the perf budget)")
	end
end

------------------------------------------------------------------------------------------------------------------
-- The overhaul's shared look pieces (art-direction §4.4)
------------------------------------------------------------------------------------------------------------------

type TextProps = { Gold: boolean?, Shadow: boolean?, Size: UDim2?, Position: UDim2? }
type PlateProps = { Size: UDim2?, Position: UDim2? }

local FLOAT_STROKE = 3.5
local PLATE_STROKE = 4
local PLATE_RADIUS = 22 -- = UI/Theme.Radius.Large
local RIM = Palette.World.Trim -- the warm white: never pure white on a world mark

local function floatLabel(parent: Instance, name: string, text: string, props: TextProps?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Size = if props and props.Size then props.Size else UDim2.fromScale(1, 1)
	l.Position = if props and props.Position then props.Position else UDim2.fromScale(0, 0)
	l.Font = Palette.DisplayFont
	l.TextScaled = true
	l.Text = text
	l.Parent = parent
	return l
end

local function floatText(gui: SurfaceGui | BillboardGui, text: string, props: TextProps?): TextLabel
	if props and props.Shadow then
		local shadow = floatLabel(gui, "TextShadow", text, props)
		shadow.Position += UDim2.fromOffset(0, 2)
		shadow.TextColor3 = Palette.Outline
		shadow.TextTransparency = 0.5
		shadow.ZIndex = 2
	end
	local label = floatLabel(gui, "Text", text, props)
	label.TextColor3 = if props and props.Gold then Palette.Gold else WHITE
	label.ZIndex = 3
	Palette.outlineText(label, FLOAT_STROKE)
	return label
end

local function navyPlate(gui: SurfaceGui | BillboardGui, props: PlateProps?): Frame
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = if props and props.Position then props.Position else UDim2.fromScale(0.5, 0.5)
	plate.Size = if props and props.Size then props.Size else UDim2.new(1, -PLATE_STROKE * 2, 1, -PLATE_STROKE * 2)
	plate.BackgroundColor3 = Palette.Navy
	plate.BackgroundTransparency = 0.15
	plate.BorderSizePixel = 0
	plate.ZIndex = 1
	rounded(plate, UDim.new(0, PLATE_RADIUS))
	Palette.outlineShape(plate, PLATE_STROKE)
	plate.Parent = gui
	return plate
end

-- A filled circle at a place in its parent (scale units), `scale` across.
local function dot(parent: Instance, name: string, x: number, y: number, scale: number, color: Color3, z: number): Frame
	local f = disc(parent, name, scale, color, z)
	f.Position = UDim2.fromScale(x, y)
	return f
end

local function pawHeart(parent: GuiObject, size: UDim2, color: Color3): Frame
	local mark = Instance.new("Frame")
	mark.Name = "PawHeart"
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, 0.5)
	mark.Size = size
	mark.BackgroundColor3 = RIM
	mark.BorderSizePixel = 0
	rounded(mark, UDim.new(0.5, 0))
	local keepSquare = Instance.new("UIAspectRatioConstraint")
	keepSquare.AspectRatio = 1
	keepSquare.Parent = mark

	-- The heart: a square turned 45 degrees, with a disc on each of its two upper edges.
	local side = 0.36
	local reach = side / (2 * math.sqrt(2))
	local cx, cy = 0.5, 0.56
	local diamond = Instance.new("Frame")
	diamond.Name = "HeartPoint"
	diamond.AnchorPoint = Vector2.new(0.5, 0.5)
	diamond.Position = UDim2.fromScale(cx, cy)
	diamond.Size = UDim2.fromScale(side, side)
	diamond.Rotation = 45
	diamond.BackgroundColor3 = color
	diamond.BorderSizePixel = 0
	diamond.ZIndex = 2
	diamond.Parent = mark
	dot(mark, "HeartLeft", cx - reach, cy - reach, side, color, 2)
	dot(mark, "HeartRight", cx + reach, cy - reach, side, color, 2)

	-- The paw: one main pad and three toes, white on the heart.
	dot(mark, "Pad", cx, cy + 0.02, 0.2, WHITE, 3)
	dot(mark, "Toe", cx - 0.14, cy - 0.13, 0.1, WHITE, 3)
	dot(mark, "Toe", cx, cy - 0.19, 0.1, WHITE, 3)
	dot(mark, "Toe", cx + 0.14, cy - 0.13, 0.1, WHITE, 3)

	mark.Parent = parent
	return mark
end

Parts.DETAIL_NEAR = DETAIL_NEAR
Parts.ICON_NEAR = ICON_NEAR_STUDS
Parts.PREVIEW_NEAR = PREVIEW_NEAR_STUDS
Parts.lighten = lighten
Parts.darken = darken
Parts.part = part
Parts.soft = soft
Parts.ball = ball
Parts.cylinder = cylinder
Parts.wedge = wedge
Parts.marker = marker
Parts.paint = paint
Parts.rounded = rounded
Parts.surface = surface
Parts.band = band
Parts.disc = disc
Parts.iconLabel = iconLabel
Parts.iconBadge = iconBadge
Parts.candyLabel = candyLabel
Parts.candyBoard = candyBoard
Parts.anchorAll = anchorAll
Parts.scrubScripts = scrubScripts
Parts.floatText = floatText
Parts.navyPlate = navyPlate
Parts.pawHeart = pawHeart

return table.freeze(Parts)
