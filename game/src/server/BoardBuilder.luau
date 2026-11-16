--!strict
-- The leaderboards in the town plaza (game/README.md "Leaderboards"). Server only: a library Server/Leaderboards
-- builds and renders, like PlotBuilder and DecorBuilder. Nothing here reads a DataStore.
--   BoardBuilder.build(ids): Gantry     builds Workspace.TownBoards (replacing an old one) and returns it
--   gantry.render(id, view)             view = { Status = "Loading" | "Live" | "Offline", Rows = { Row } }
--   gantry.Model                        the Model
--
-- Where it stands: a candy-pop gantry, "🏆 Top Doctors", spanning the street just WEST of the plaza, at
-- Config.Town.Origin.X - (plaza radius + GAP_FROM_PLAZA) = Origin.X - 26 with PlotBuilder's town. Its two white
-- posts stand on the curbs, the boards hang from a pink beam from 7.5 studs up (players walk under them), and they
-- face the plaza and the TownSpawn (east); the same boards show on the back for players coming from the west
-- plots. Board 1 is on the left as seen from the plaza (+Z). The plaza's EAST side is left free for the Nurse Belt
-- (depth update). The street and plaza sizes are read from the built town (ClinicTown.Street, ClinicTown.Plaza), so
-- the gantry follows PlotBuilder if its layout changes; if they're missing it falls back to PlotBuilder's numbers.
-- Nothing here touches a plot, the arches (at the street's far ends), the plaza's benches, lamps and planters
-- (within 17 studs of the centre) or the street lamps (at Origin.X ± 39).
--
-- Look (candy pop, memory-20261116-007): SmoothPlastic in Palette colours, white posts with yellow candy-ball caps,
-- each board a glossy candy panel in its own colour with a white rim inside a thick trim, white outlined display
-- titles, and white rows with a thick ink outline (gold, silver and bronze tints for the top 3). Rows show the
-- rank (🥇🥈🥉 then numbers), the player's DisplayName with their @username small under it (what Roblox already
-- shows publicly, nothing else), and the value. Text never dims at night (LightInfluence 0).

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local Leaderboard = require(Shared.Logic.Leaderboard)

local BoardBuilder = {}

export type View = { Status: Leaderboard.Status, Rows: { Leaderboard.Row } }
export type Gantry = {
	Model: Model,
	render: (id: string, view: View) -> (),
}

BoardBuilder.MODEL_NAME = "TownBoards"

-- PlotBuilder's town, used when ClinicTown's parts can't be read.
local FALLBACK_STREET_HALF_WIDTH = 18
local FALLBACK_PLAZA_RADIUS = 17
local FALLBACK_GROUND_TOP = 0.5 -- the street's top, above Config.Town.Origin.Y

local GAP_FROM_PLAZA = 9 -- studs from the plaza's edge to the gantry
local CLEARANCE = 7.5 -- from the street to the bottom of the boards
local BOARD_HEIGHT = 12
local BOARD_DEPTH = 0.6
local TRIM = 0.22 -- the trim frame shows this much round each board (less than half BOARD_GAP: no overlap)
local BOARD_GAP = 0.6
local POST_SIZE = 1.6
local POST_INSET = 1.1 -- a post's centre, in from the street's edge (on the curb)
local BEAM_HEIGHT = 2.6
local PIXELS_PER_STUD = 40
local MAX_BOARDS = 4
local MAX_DISTANCE = 220 -- the SurfaceGuis stop drawing beyond this

local WHITE = Palette.White
local CANDY = Palette.Candy
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

-- The town's street half width, plaza radius and street top, read from what PlotBuilder built.
local function townLayout(): (number, number, number)
	local origin = Config.Town.Origin
	local halfWidth, radius, top = FALLBACK_STREET_HALF_WIDTH, FALLBACK_PLAZA_RADIUS, origin.Y + FALLBACK_GROUND_TOP
	local town = Workspace:FindFirstChild("ClinicTown")
	local street = town and town:FindFirstChild("Street")
	if street and street:IsA("BasePart") then
		halfWidth = street.Size.Z / 2
		top = street.Position.Y + street.Size.Y / 2
	else
		warn("[BoardBuilder] No ClinicTown.Street: the plaza boards use PlotBuilder's default layout")
	end
	local plaza = town and town:FindFirstChild("Plaza")
	if plaza and plaza:IsA("BasePart") then
		radius = math.max(plaza.Size.Y, plaza.Size.Z) / 2 -- an upright cylinder: (height, diameter, diameter)
	end
	return halfWidth, radius, top
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
-- The gantry
------------------------------------------------------------------------------------------------------------------

local function buildSignBeam(model: Model, size: Vector3, cframe: CFrame)
	local beam = part(model, "Beam", size, cframe, darken(CANDY.Pink, 0.12))
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
			text(gui, "Title", UDim2.fromScale(0.6, 0.74), UDim2.fromScale(0.2, 0.13), Palette.DisplayFont, WHITE)
		title.Text = "🏆 Top Doctors"
		title.TextScaled = true
		Palette.outlineText(title, 4)
		gui.Parent = beam
	end
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

	local origin = Config.Town.Origin
	local halfWidth, plazaRadius, groundTop = townLayout()
	local x = origin.X - (plazaRadius + GAP_FROM_PLAZA)
	-- Facing east (+X): the boards' Front faces look at the plaza; their local X runs along the street's width (+Z).
	local function at(z: number, y: number): CFrame
		local position = Vector3.new(x, groundTop + y, origin.Z + z)
		return CFrame.lookAt(position, position + Vector3.xAxis)
	end

	local model = Instance.new("Model")
	model.Name = BoardBuilder.MODEL_NAME

	local postZ = halfWidth - POST_INSET
	local boardBottom = CLEARANCE
	local boardTop = boardBottom + BOARD_HEIGHT
	local beamBottom = boardTop + TRIM
	local postHeight = beamBottom + BEAM_HEIGHT
	for _, side in { -1, 1 } do
		part(model, "Post", Vector3.new(POST_SIZE, postHeight, POST_SIZE), at(side * postZ, postHeight / 2), WHITE)
		soft(ball(model, "PostCap", 2.2, at(side * postZ, postHeight + 0.9), CANDY.Yellow))
	end
	local beamLength = postZ * 2 + POST_SIZE
	buildSignBeam(model, Vector3.new(beamLength, BEAM_HEIGHT, 1.4), at(0, beamBottom + BEAM_HEIGHT / 2))

	-- The boards share the space between the posts, board 1 on the left as seen from the plaza (+Z).
	local inner = postZ * 2 - POST_SIZE - TRIM * 2 - 0.4
	local count = math.max(#boards, 1)
	local width = (inner - BOARD_GAP * (count - 1)) / count
	local faces: { [string]: { Face } } = {}
	for index, id in boards do
		local z = inner / 2 - width / 2 - (index - 1) * (width + BOARD_GAP)
		local cframe = at(z, boardBottom + BOARD_HEIGHT / 2)
		local color = colorOf(id)
		local board =
			part(model, "Board_" .. id, Vector3.new(width, BOARD_HEIGHT, BOARD_DEPTH), cframe, darken(color, 0.15))
		board:SetAttribute("BoardId", id)
		local trim = Vector3.new(width + TRIM * 2, BOARD_HEIGHT + TRIM * 2, BOARD_DEPTH * 0.6)
		soft(part(model, "Trim_" .. id, trim, cframe, color))
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
