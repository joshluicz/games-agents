--!strict
-- The leaderboards in the 🏆 Hall of Fame garden (game/README.md "Leaderboards"). Server only: a library
-- Server/Leaderboards builds and renders, like PlotBuilder and DecorBuilder. Nothing here reads a DataStore.
--   BoardBuilder.build(ids): Gantry     builds Workspace.TownBoards (replacing an old one) and returns it
--   gantry.render(id, view)             view = { Status = "Loading" | "Live" | "Offline", Rows = { Row } }
--   gantry.Model                        the Model
--
-- Where it stands: off the main road (Joshua, 2026-11-16: "leaderboards shouldnt be on the main road... conveyor
-- belt should be on the main road"), so the whole street is free for the Nurse Belt. Nothing here sits on the
-- street, its curbs, a plot, a welcome arch or the plaza. The garden is its own grass slab past the street's WEST
-- end (GARDEN_END), beyond the welcome arch: GARDEN_DEPTH (38) deep, 2 x GARDEN_HALF_WIDTH (80) wide, centred on
-- the street's line, its east edge on the town lawn's west edge (Origin.X - 137 with PlotBuilder's town). A cream
-- path runs from the street's end to a "🏆 Hall of Fame" sign with a gold trophy on top, ARC_BACK (24) studs in.
-- The boards stand on low plinths on the grass in a shallow arc through the sign, two each side, each turned to a
-- point on the street's line ARC_RADIUS (80) studs in front of the arc: they face back down the street to the plaza
-- and the TownSpawn (~160 studs, inside MAX_DISTANCE). Board 1 is on the left as seen from the plaza (+Z); each
-- board's back shows the same board. Benches face the boards, low flower planters flank the path, lamps stand at
-- the arc's ends and trees behind it. The edges come from the built town (ClinicTown.Street and TownLawn), so the
-- garden follows PlotBuilder's layout; if they're missing it falls back to PlotBuilder's numbers.
-- Seen from the spawn, the welcome arch frames the sign and the inner boards (its beam, 11-14.4 studs up, hides
-- their top strip from there), and the outer boards stand between the arch's posts and the corner trees of the two
-- west plots. Planters, path and plinths stay low so nothing in front of a board hides it.
--
-- Look (candy pop, memory-20261116-007): SmoothPlastic in Palette colours, white posts with yellow candy-ball caps,
-- each board a glossy candy panel in its own colour with a white rim inside a thick trim, white outlined display
-- titles, and white rows with a thick ink outline (gold, silver and bronze tints for the top 3). Rows show the
-- rank (🥇🥈🥉 then numbers), the player's DisplayName with their @username small under it (what Roblox already
-- shows publicly, nothing else), and the value. Text never dims at night (LightInfluence 0).

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local Leaderboard = require(Shared.Logic.Leaderboard)
local PlotBuilder = require(script.Parent.PlotBuilder) -- only for its night-light tag

local BoardBuilder = {}

export type View = { Status: Leaderboard.Status, Rows: { Leaderboard.Row } }
export type Gantry = {
	Model: Model,
	render: (id: string, view: View) -> (),
}

BoardBuilder.MODEL_NAME = "TownBoards"

-- PlotBuilder's town, used when ClinicTown's parts can't be read (above / along from Config.Town.Origin).
local FALLBACK_STREET_HALF_LENGTH = 137
local FALLBACK_STREET_TOP = 0.5
local FALLBACK_LAWN_TOP = 0.3

-- The garden, in studs from where the street and the town lawn end, on the street's centre line.
local GARDEN_END = -1 -- past the street's west end (-1); +1 puts the garden past the east end instead
local GARDEN_DEPTH = 38
local GARDEN_HALF_WIDTH = 40
local ARC_BACK = 24 -- from the garden's edge to the middle of the arc, where the sign stands
local ARC_RADIUS = 80 -- the boards turn to a point this far in front of the arc, on the street's line
local PATH_WIDTH = 8

local PLINTH_HEIGHT = 0.5 -- each board's bottom rests on a low white plinth on the grass
local BOARD_WIDTH = 10
local BOARD_HEIGHT = 12
local BOARD_DEPTH = 0.6
local TRIM = 0.22 -- the trim frame shows this much round each board and the sign
local POST_SIZE = 1.2
local POST_GAP = 0.08 -- between a trim and its posts
local UNIT_GAP = 0.8 -- between the posts of two neighbours along the arc
local SIGN_WIDTH = 8
local SIGN_HEIGHT = 3.2
local SIGN_BOTTOM = 2.6
local PIXELS_PER_STUD = 40
local MAX_BOARDS = 4
local MAX_DISTANCE = 220 -- the SurfaceGuis stop drawing beyond this

-- Half the width of a board between its posts, and of the sign; where the boards sit along the arc.
local UNIT_HALF = BOARD_WIDTH / 2 + TRIM + POST_GAP + POST_SIZE
local SIGN_HALF = SIGN_WIDTH / 2 + TRIM + POST_GAP + POST_SIZE
local INNER = SIGN_HALF + UNIT_GAP + UNIT_HALF -- the sign's neighbours, along the arc from its middle
local PITCH = UNIT_HALF * 2 + UNIT_GAP

local WHITE = Palette.White
local CANDY = Palette.Candy
local WORLD = Palette.World
local LAWN_STRIPE = WORLD.Grass:Lerp(WORLD.LeavesLight, 0.45)
local FLOWERS = { CANDY.Pink, CANDY.Yellow, WHITE, CANDY.Purple, CANDY.Red, CANDY.Orange }
local PLANTERS = { CANDY.Pink, CANDY.Blue }
local LEAVES = { WORLD.Leaves, WORLD.LeavesLight, WORLD.Leaves:Lerp(WORLD.LeavesLight, 0.5), WORLD.LeavesLight }
local BLOSSOM = { CANDY.Pink:Lerp(WHITE, 0.2), CANDY.Pink:Lerp(WHITE, 0.45), CANDY.Pink, CANDY.Pink:Lerp(WHITE, 0.6) }
local MEDALS = { "🥇", "🥈", "🥉" }
local ROW_TINTS = {
	CANDY.Yellow:Lerp(WHITE, 0.62),
	Color3.fromRGB(214, 222, 240),
	CANDY.Orange:Lerp(WHITE, 0.66),
}

local function darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

local function colorOf(id: string): Color3
	local def = Leaderboard.BOARDS[id]
	local color = def and rawget(CANDY :: any, def.Color)
	return if typeof(color) == "Color3" then color else CANDY.Blue
end

------------------------------------------------------------------------------------------------------------------
-- Parts
------------------------------------------------------------------------------------------------------------------

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Decoration: walk-through and ignored by rays.
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
	color: Color3
): Part
	local p =
		part(parent, name, Vector3.new(height, diameter, diameter), cframe * CFrame.Angles(0, 0, math.rad(90)), color)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A flat painted detail (lawn stripes, path edges): walk-through, ray-ignored and shadowless.
local function paint(p: BasePart): BasePart
	soft(p)
	p.CastShadow = false
	return p
end

-- A lamp glow: Neon with its PointLight on only at night (PlotBuilder's night-light tag does the switching).
local function nightLight(p: BasePart, range: number)
	local light = Instance.new("PointLight")
	light.Color = WORLD.Lamp
	light.Brightness = 1.4
	light.Range = range
	light.Shadows = false
	light.Enabled = false
	light.Parent = p
	CollectionService:AddTag(p, PlotBuilder.NIGHT_LIGHT_TAG)
end

-- The garden's frame, read from what PlotBuilder built: on the street's centre line where both the street and the
-- town lawn end (at GARDEN_END), at the lawn's top, its LookVector pointing back down the street to the plaza. In
-- it +X is board 1's side (+Z in the world for the west end) and +Z runs away from the town, into the garden.
-- Also returns where the street ends in that frame (z <= 0) and how far the street's top is above the lawn's.
local function gardenFrame(): (CFrame, number, number)
	local origin = Config.Town.Origin
	local streetEnd = origin.X + GARDEN_END * FALLBACK_STREET_HALF_LENGTH
	local lineZ = origin.Z
	local streetTop = origin.Y + FALLBACK_STREET_TOP
	local lawnTop = origin.Y + FALLBACK_LAWN_TOP
	local town = Workspace:FindFirstChild("ClinicTown")
	local street = town and town:FindFirstChild("Street")
	if street and street:IsA("BasePart") then
		streetEnd = street.Position.X + GARDEN_END * street.Size.X / 2
		lineZ = street.Position.Z
		streetTop = street.Position.Y + street.Size.Y / 2
	else
		warn("[BoardBuilder] No ClinicTown.Street: the Hall of Fame uses PlotBuilder's default layout")
	end
	local edge = streetEnd
	local lawn = town and town:FindFirstChild("TownLawn")
	if lawn and lawn:IsA("BasePart") then
		local lawnEdge = lawn.Position.X + GARDEN_END * lawn.Size.X / 2
		edge = if GARDEN_END < 0 then math.min(edge, lawnEdge) else math.max(edge, lawnEdge)
		lawnTop = lawn.Position.Y + lawn.Size.Y / 2
	end
	local position = Vector3.new(edge, lawnTop, lineZ)
	local frame = CFrame.lookAt(position, position - Vector3.xAxis * GARDEN_END)
	return frame, (streetEnd - edge) * GARDEN_END, streetTop - lawnTop
end

-- A spot on the ground `along` studs round the arc from its middle (+ = board 1's side) and `inset` studs in front
-- of it, facing the arc's focus (back down the street).
local function onArc(base: CFrame, along: number, inset: number): CFrame
	local angle = along / ARC_RADIUS
	local radius = ARC_RADIUS - inset
	local focus = Vector3.new(0, 0, ARC_BACK - ARC_RADIUS)
	local at = focus + Vector3.new(radius * math.sin(angle), 0, radius * math.cos(angle))
	return base * CFrame.lookAt(at, focus)
end

-- Where board `index` of `count` sits along the arc: the first half on board 1's side (board 1 outermost), the rest
-- on the other side, the sign in the middle.
local function arcPosition(index: number, count: number): number
	local left = math.ceil(count / 2)
	if index <= left then
		return INNER + (left - index) * PITCH
	end
	return -(INNER + (index - left - 1) * PITCH)
end

------------------------------------------------------------------------------------------------------------------
-- The board's SurfaceGui
------------------------------------------------------------------------------------------------------------------

type RowView = { Frame: Frame, Rank: TextLabel, Name: TextLabel, User: TextLabel, Value: TextLabel }
type Face = { Rows: { RowView }, Message: TextLabel }

local function corner(gui: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = gui
end

local function text(
	parent: Instance,
	name: string,
	size: UDim2,
	position: UDim2,
	font: Enum.Font,
	color: Color3
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Font = font
	label.TextColor3 = color
	label.Text = ""
	label.ZIndex = 4
	label.Parent = parent
	return label
end

-- A glossy candy panel filling the gui: the colour with a light-to-deep gradient, a white rim and a soft shine.
local function candyPanel(gui: SurfaceGui, color: Color3)
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(1, -12, 1, -12)
	panel.BackgroundColor3 = color
	panel.BorderSizePixel = 0
	panel.ZIndex = 1
	corner(panel, 20)
	Palette.candyGradient(panel)
	local rim = Instance.new("UIStroke")
	rim.Name = "Rim"
	rim.Color = WHITE
	rim.Thickness = 5
	rim.LineJoinMode = Enum.LineJoinMode.Round
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = panel
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.AnchorPoint = Vector2.new(0.5, 0)
	shine.Position = UDim2.new(0.5, 0, 0, 5)
	shine.Size = UDim2.new(1, -40, 0, 46)
	shine.BackgroundColor3 = WHITE
	shine.BackgroundTransparency = 0.8
	shine.BorderSizePixel = 0
	shine.ZIndex = 2
	corner(shine, 20)
	shine.Parent = panel
	panel.Parent = gui
end

local function buildFace(board: BasePart, id: string, face: Enum.NormalId, shown: number): Face
	local def = Leaderboard.BOARDS[id]
	local width = board.Size.X * PIXELS_PER_STUD
	local height = board.Size.Y * PIXELS_PER_STUD

	local gui = Instance.new("SurfaceGui")
	gui.Name = if face == Enum.NormalId.Front then "BoardGui" else "BoardGuiBack"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0 -- bright and readable at night
	gui.MaxDistance = MAX_DISTANCE
	gui.ClipsDescendants = true
	candyPanel(gui, colorOf(id))

	local pad = 16
	local titleHeight = 56
	local title = text(
		gui,
		"Title",
		UDim2.new(1, -pad * 2, 0, titleHeight),
		UDim2.fromOffset(pad, 12),
		Palette.DisplayFont,
		WHITE
	)
	title.Text = if def then def.Icon .. " " .. def.Title else id
	title.TextScaled = true
	Palette.outlineText(title, 3)

	local top = 12 + titleHeight + 8
	local list = Instance.new("Frame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(pad, top)
	list.Size = UDim2.fromOffset(width - pad * 2, height - top - pad)
	list.ZIndex = 3
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list

	local rowHeight = math.floor((list.Size.Y.Offset - 4 * (shown - 1)) / shown)
	local rows: { RowView } = {}
	for rank = 1, shown do
		local row = Instance.new("Frame")
		row.Name = "Row" .. rank
		row.LayoutOrder = rank
		row.Size = UDim2.new(1, 0, 0, rowHeight)
		row.BackgroundColor3 = ROW_TINTS[rank] or WHITE
		row.BorderSizePixel = 0
		row.Visible = false
		row.ZIndex = 3
		corner(row, 10)
		local stroke = Instance.new("UIStroke")
		stroke.Color = Palette.Outline
		stroke.Thickness = 3
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = row
		row.Parent = list

		local rankWidth = 36
		local valueWidth = 84
		local rankLabel =
			text(row, "Rank", UDim2.new(0, rankWidth, 1, -6), UDim2.fromOffset(4, 3), Palette.DisplayFont, Palette.Ink)
		rankLabel.TextScaled = true
		rankLabel.Text = MEDALS[rank] or tostring(rank)

		local nameWidth = width - pad * 2 - rankWidth - valueWidth - 16
		local nameLabel = text(
			row,
			"Name",
			UDim2.fromOffset(nameWidth, math.floor(rowHeight * 0.6)),
			UDim2.fromOffset(rankWidth + 8, 1),
			Palette.BodyFont,
			Palette.Ink
		)
		nameLabel.TextSize = math.floor(rowHeight * 0.52)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		local userLabel = text(
			row,
			"User",
			UDim2.fromOffset(nameWidth, math.floor(rowHeight * 0.36)),
			UDim2.fromOffset(rankWidth + 8, math.floor(rowHeight * 0.6)),
			Palette.BodyFont,
			Palette.InkSoft
		)
		userLabel.TextSize = math.floor(rowHeight * 0.32)
		userLabel.TextXAlignment = Enum.TextXAlignment.Left
		userLabel.TextTruncate = Enum.TextTruncate.AtEnd

		local valueLabel = text(
			row,
			"Value",
			UDim2.new(0, valueWidth, 1, -8),
			UDim2.new(1, -valueWidth - 8, 0, 4),
			Palette.DisplayFont,
			Palette.Ink
		)
		valueLabel.TextScaled = true
		valueLabel.TextXAlignment = Enum.TextXAlignment.Right

		rows[rank] = { Frame = row, Rank = rankLabel, Name = nameLabel, User = userLabel, Value = valueLabel }
	end

	-- Loading, offline (Studio without API access) or nobody yet: one big outlined line where the rows go.
	local message = text(
		gui,
		"Message",
		UDim2.fromOffset(width - pad * 4, math.floor((height - top) * 0.5)),
		UDim2.fromOffset(pad * 2, top + math.floor((height - top) * 0.2)),
		Palette.DisplayFont,
		WHITE
	)
	message.TextScaled = true
	message.TextWrapped = true
	Palette.outlineText(message, 3)

	gui.Parent = board
	return { Rows = rows, Message = message }
end

local function renderFace(face: Face, view: View)
	local live = view.Status == "Live"
	for rank, row in face.Rows do
		local entry = if live then view.Rows[rank] else nil
		row.Frame.Visible = entry ~= nil
		if entry then
			row.Name.Text = entry.Name
			row.User.Text = if entry.User ~= "" then "@" .. entry.User else ""
			row.Value.Text = Leaderboard.format(entry.Value)
		end
	end
	local message = if view.Status == "Offline"
		then Leaderboard.TEXT.Offline
		elseif view.Status == "Loading" then Leaderboard.TEXT.Loading
		elseif #view.Rows == 0 then Leaderboard.TEXT.Empty
		else ""
	face.Message.Text = message
	face.Message.Visible = message ~= ""
end

------------------------------------------------------------------------------------------------------------------
-- The Hall of Fame garden. `at` is a CFrame on the ground where a piece stands, facing the plaza.
------------------------------------------------------------------------------------------------------------------

-- A round toy tree like the town's: a trunk and four stacked balls. `blossom` makes it a pink blossom tree.
local function tree(parent: Instance, at: CFrame, scale: number, blossom: boolean)
	local crown = if blossom then BLOSSOM else LEAVES
	local model = Instance.new("Model")
	model.Name = "Tree"
	cylinder(model, "Trunk", 6 * scale, 1.4 * scale, at * CFrame.new(0, 3 * scale, 0), WORLD.Trunk)
	soft(ball(model, "Leaves", 7 * scale, at * CFrame.new(0, 7 * scale, 0), crown[1]))
	soft(ball(model, "Leaves", 5.5 * scale, at * CFrame.new(1.8 * scale, 8.8 * scale, 0.6 * scale), crown[2]))
	soft(ball(model, "Leaves", 5 * scale, at * CFrame.new(-1.6 * scale, 8.4 * scale, -1 * scale), crown[3]))
	soft(ball(model, "Leaves", 4 * scale, at * CFrame.new(0.2 * scale, 10.6 * scale, -0.2 * scale), crown[4]))
	model.Parent = parent
end

-- The town's candy-blue bench; whoever sits on it faces along `at`'s LookVector.
local function bench(parent: Instance, at: CFrame)
	local model = Instance.new("Model")
	model.Name = "Bench"
	part(model, "Seat", Vector3.new(5, 0.4, 1.6), at * CFrame.new(0, 1.4, 0), CANDY.Blue)
	part(model, "Back", Vector3.new(5, 1.4, 0.3), at * CFrame.new(0, 2.3, 0.7), CANDY.Blue)
	part(model, "Leg", Vector3.new(0.4, 1.2, 1.4), at * CFrame.new(-2.1, 0.6, 0), WHITE)
	part(model, "Leg", Vector3.new(0.4, 1.2, 1.4), at * CFrame.new(2.1, 0.6, 0), WHITE)
	model.Parent = parent
end

-- The town's purple street lamp, lit at night.
local function lamp(parent: Instance, at: CFrame)
	local model = Instance.new("Model")
	model.Name = "Lamp"
	cylinder(model, "Post", 8, 0.5, at * CFrame.new(0, 4, 0), CANDY.Purple)
	cylinder(model, "Cap", 0.3, 1.6, at * CFrame.new(0, 9.05, 0), CANDY.Purple)
	nightLight(soft(ball(model, "Glow", 1.4, at * CFrame.new(0, 8.3, 0), WORLD.Lamp)), 18)
	model.Parent = parent
end

-- A round candy planter, kept low (flowers, no tree) so it never hides a board from the street.
local function planter(parent: Instance, at: CFrame, color: Color3, seed: number)
	local model = Instance.new("Model")
	model.Name = "Planter"
	cylinder(model, "Pot", 1.2, 4, at * CFrame.new(0, 0.6, 0), color)
	soft(cylinder(model, "Grass", 0.1, 3.4, at * CFrame.new(0, 1.22, 0), WORLD.Grass))
	for i, offset in { Vector3.new(0.8, 1.6, 0.5), Vector3.new(-0.9, 1.6, 0.4), Vector3.new(0.1, 1.6, -0.9) } do
		soft(ball(model, "Flower", 0.9, at * CFrame.new(offset), FLOWERS[(seed + i) % #FLOWERS + 1]))
	end
	model.Parent = parent
end

-- The grass slab, its mowing stripes, the cream path from the street's end to the sign, planters at the path's
-- start, benches facing the boards, lamps at the arc's ends and trees behind it.
local function buildGarden(model: Model, base: CFrame, pathStart: number, pathTop: number)
	local garden = Instance.new("Model")
	garden.Name = "Garden"
	local middle = GARDEN_DEPTH / 2
	part(
		garden,
		"Lawn",
		Vector3.new(GARDEN_HALF_WIDTH * 2, 2, GARDEN_DEPTH),
		base * CFrame.new(0, -1, middle),
		WORLD.Grass
	)
	for _, x in { -30, -16, 16, 30 } do
		local stripe = Vector3.new(6, 0.04, GARDEN_DEPTH - 1)
		paint(part(garden, "LawnStripe", stripe, base * CFrame.new(x, 0.02, middle), LAWN_STRIPE))
	end

	-- The path's top is level with the street's, so the street runs straight onto it.
	local pathEnd = ARC_BACK - POST_SIZE / 2
	local length = pathEnd - pathStart
	local pathZ = pathStart + length / 2
	local path = Vector3.new(PATH_WIDTH, pathTop + 0.06, length)
	part(garden, "Path", path, base * CFrame.new(0, (pathTop - 0.06) / 2, pathZ), WORLD.Path)
	for _, side in { -1, 1 } do
		local edge = Vector3.new(0.5, pathTop + 0.1, length)
		local at = base * CFrame.new(side * (PATH_WIDTH / 2 + 0.25), (pathTop + 0.1) / 2 - 0.05, pathZ)
		paint(part(garden, "PathEdge", edge, at, WHITE))
	end

	for i, side in { 1, -1 } do
		planter(garden, base * CFrame.new(side * (PATH_WIDTH / 2 + 3.5), 0, 4), PLANTERS[i], i * 2)
		-- Between each pair of boards, 9 studs in front, facing them.
		bench(garden, onArc(base, side * (INNER + PITCH / 2), 9) * CFrame.Angles(0, math.pi, 0))
		lamp(garden, onArc(base, side * (INNER + PITCH + UNIT_HALF + 2.5), 0))
	end
	tree(garden, base * CFrame.new(0, 0, ARC_BACK + 9), 1.2, false)
	for _, side in { -1, 1 } do
		tree(garden, base * CFrame.new(side * 18, 0, ARC_BACK + 7.5), 1.1, true)
		tree(garden, base * CFrame.new(side * 36, 0, ARC_BACK + 2), 1.2, false)
	end
	garden.Parent = model
end

-- The "🏆 Hall of Fame" sign in the middle of the arc, at the end of the path: a glossy pink board between white
-- posts with candy-ball caps that glow at night, and a gold trophy on top.
local function buildTitleSign(model: Model, at: CFrame)
	local postHeight = SIGN_BOTTOM + SIGN_HEIGHT + TRIM + 0.5
	for _, side in { -1, 1 } do
		local x = side * (SIGN_HALF - POST_SIZE / 2)
		part(
			model,
			"SignPost",
			Vector3.new(POST_SIZE, postHeight, POST_SIZE),
			at * CFrame.new(x, postHeight / 2, 0),
			WHITE
		)
		nightLight(soft(ball(model, "SignCap", 1.8, at * CFrame.new(x, postHeight + 0.7, 0), CANDY.Yellow)), 16)
	end
	local centre = at * CFrame.new(0, SIGN_BOTTOM + SIGN_HEIGHT / 2, 0)
	local sign = part(model, "TitleSign", Vector3.new(SIGN_WIDTH, SIGN_HEIGHT, 0.5), centre, darken(CANDY.Pink, 0.12))
	soft(part(model, "TitleTrim", Vector3.new(SIGN_WIDTH + TRIM * 2, SIGN_HEIGHT + TRIM * 2, 0.3), centre, CANDY.Pink))
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = if face == Enum.NormalId.Front then "TitleGui" else "TitleGuiBack"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		gui.MaxDistance = MAX_DISTANCE
		candyPanel(gui, CANDY.Pink)
		local title =
			text(gui, "Title", UDim2.fromScale(0.86, 0.66), UDim2.fromScale(0.07, 0.17), Palette.DisplayFont, WHITE)
		title.Text = "🏆 Hall of Fame"
		title.TextScaled = true
		Palette.outlineText(title, 4)
		gui.Parent = sign
	end

	local gold = CANDY.Yellow
	local top = at * CFrame.new(0, SIGN_BOTTOM + SIGN_HEIGHT + TRIM, 0)
	soft(part(model, "TrophyBase", Vector3.new(3, 0.5, 1.4), top * CFrame.new(0, 0.25, 0), WHITE))
	soft(cylinder(model, "TrophyStem", 0.9, 0.8, top * CFrame.new(0, 0.95, 0), gold))
	soft(ball(model, "TrophyCup", 2.4, top * CFrame.new(0, 2, 0), gold))
	soft(cylinder(model, "TrophyCup", 1.4, 2.6, top * CFrame.new(0, 2.7, 0), gold))
	soft(cylinder(model, "TrophyRim", 0.25, 2.7, top * CFrame.new(0, 3.45, 0), WHITE))
	for _, side in { -1, 1 } do
		soft(ball(model, "TrophyHandle", 1, top * CFrame.new(side * 1.5, 2.6, 0), gold))
	end
end

-- One board on the arc: the board between two white posts with candy-ball caps, its bottom on a low white plinth.
local function buildStand(model: Model, id: string, at: CFrame): BasePart
	local color = colorOf(id)
	local centre = at * CFrame.new(0, PLINTH_HEIGHT + BOARD_HEIGHT / 2, 0)
	local size = Vector3.new(BOARD_WIDTH, BOARD_HEIGHT, BOARD_DEPTH)
	local board = part(model, "Board_" .. id, size, centre, darken(color, 0.15))
	board:SetAttribute("BoardId", id)
	local trim = Vector3.new(BOARD_WIDTH + TRIM * 2, BOARD_HEIGHT + TRIM * 2, BOARD_DEPTH * 0.6)
	soft(part(model, "Trim_" .. id, trim, centre, color))
	local plinth = Vector3.new(BOARD_WIDTH + (TRIM + POST_GAP) * 2, PLINTH_HEIGHT + 0.1, 1.6)
	part(model, "Plinth", plinth, at * CFrame.new(0, (PLINTH_HEIGHT - 0.1) / 2, 0), WHITE)
	local postHeight = PLINTH_HEIGHT + BOARD_HEIGHT + TRIM + 0.5
	for _, side in { -1, 1 } do
		local x = side * (UNIT_HALF - POST_SIZE / 2)
		part(model, "Post", Vector3.new(POST_SIZE, postHeight, POST_SIZE), at * CFrame.new(x, postHeight / 2, 0), WHITE)
		soft(ball(model, "PostCap", 2, at * CFrame.new(x, postHeight + 0.8, 0), CANDY.Yellow))
	end
	return board
end

function BoardBuilder.build(ids: { string }): Gantry
	local old = Workspace:FindFirstChild(BoardBuilder.MODEL_NAME)
	if old then
		old:Destroy()
	end

	local boards: { string } = {}
	for _, id in ids do
		if Leaderboard.isBoard(id) and #boards < MAX_BOARDS then
			table.insert(boards, id)
		end
	end

	local model = Instance.new("Model")
	model.Name = BoardBuilder.MODEL_NAME
	local base, pathStart, pathTop = gardenFrame()
	buildGarden(model, base, pathStart, pathTop)
	buildTitleSign(model, onArc(base, 0, 0))

	-- The boards' Front faces look back down the street; their local X runs toward board 1's side.
	local faces: { [string]: { Face } } = {}
	for index, id in boards do
		local board = buildStand(model, id, onArc(base, arcPosition(index, #boards), 0))
		faces[id] = {
			buildFace(board, id, Enum.NormalId.Front, Config.Leaderboards.Shown),
			buildFace(board, id, Enum.NormalId.Back, Config.Leaderboards.Shown),
		}
	end

	model.Parent = Workspace

	local gantry = {
		Model = model,
		render = function(id: string, view: View)
			local list = faces[id]
			if not list then
				return
			end
			for _, face in list do
				renderFace(face, view)
			end
		end,
	}
	return gantry
end

return BoardBuilder
