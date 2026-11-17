--!strict
-- The leaderboards in the 🏆 Hall of Fame garden (game/README.md "Leaderboards"). Server only: a library
-- Server/Leaderboards builds and renders, like PlotBuilder and DecorBuilder. Nothing here reads a DataStore.
-- OWNER: T2 (the look overhaul, look build plan §B5).
--   BoardBuilder.build(ids): Gantry     builds Workspace.TownBoards (replacing an old one) and returns it
--   gantry.render(id, view)             view = { Status = "Loading" | "Live" | "Offline", Rows = { Row } }
--   gantry.Model                        the Model
--
-- Where it stands: off the main road (Joshua, 2026-11-16: "leaderboards shouldnt be on the main road... conveyor
-- belt should be on the main road"), so the whole street is free for the Nurse Belt. Nothing here sits on the
-- street, its curbs, a plot, a welcome arch or the plaza. The garden is its own lawn past the street's WEST
-- end (GARDEN_END), beyond the welcome arch: GARDEN_DEPTH (38) deep, 2 x GARDEN_HALF_WIDTH (80) wide, centred on
-- the street's line, its east edge on the town lawn's west edge (Origin.X - 242 with PlotBuilder's town). A plank
-- path runs from the street's end to a "🏆 Hall of Fame" title with a gold trophy on top, ARC_BACK (24) studs in.
-- The boards stand on low Slate plinths on the grass in a shallow arc through the title, two each side, each turned
-- to a point on the street's line ARC_RADIUS (80) studs in front of the arc: they face back down the street to the
-- plaza and the TownSpawn (~266 studs since the plots grew to 140, inside MAX_DISTANCE). Board 1 is on the left as
-- seen from the plaza (+Z); each board's back shows the same board. Benches face the boards, low planters flank the path, lamps stand at the arc's
-- ends and trees behind it. The edges come from the built town (ClinicTown.Street and Lawn), so the garden follows
-- the town's layout; if they're missing it falls back to PlotBuilder's numbers. The garden does not move with the
-- look overhaul (look build plan §G7).
--
-- Look (the look overhaul: art-direction §2.4, §4.1, §4.4; look build plan §B5): the garden lawn is studded GrassA
-- with an 8-stud GrassB checker (whole studs), the path planks; the scenery is World/Props (voxel trees, plank
-- benches, dark lamps, planters), the same family as the town's. Each board is a table, so it sits on a NAVY PLATE
-- (World/Parts.navyPlate) with white rows, between two studded posts in the board's own accent; its title floats
-- above the plate in outlined letters (World/Parts.floatText), and so does the gold "🏆 Hall of Fame". Rows show the
-- rank (🥇🥈🥉 then numbers), the player's DisplayName with their @username small under it (what Roblox already shows
-- publicly, nothing else), and the value in gold. Text never dims at night (LightInfluence 0). The lamps and the
-- title's post lights are World/NightLights "Lamp"s. No colour above 245 on a world surface.

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local Leaderboard = require(Shared.Logic.Leaderboard)
local NightLights = require(script.Parent.World.NightLights)
local Parts = require(script.Parent.World.Parts)
local Props = require(script.Parent.World.Props)
local Studs = require(script.Parent.World.Studs)

local part, soft, paint = Parts.part, Parts.soft, Parts.paint

local BoardBuilder = {}

export type View = { Status: Leaderboard.Status, Rows: { Leaderboard.Row } }
export type Gantry = {
	Model: Model,
	render: (id: string, view: View) -> (),
}

BoardBuilder.MODEL_NAME = "TownBoards"

-- PlotBuilder's town, used when ClinicTown's parts can't be read (above / along from Config.Town.Origin).
local FALLBACK_STREET_HALF_LENGTH = 242
local FALLBACK_STREET_TOP = 0.5
local FALLBACK_LAWN_TOP = 0.3

-- The garden, in studs from where the street and the town lawn end, on the street's centre line.
local GARDEN_END = -1 -- past the street's west end (-1); +1 puts the garden past the east end instead
local GARDEN_DEPTH = 38
local GARDEN_HALF_WIDTH = 40
local CHECKER_CELL = Config.Look.CheckerFarStuds -- the garden's checker, like the town's far lawn
local ARC_BACK = 24 -- from the garden's edge to the middle of the arc, where the title stands
local ARC_RADIUS = 80 -- the boards turn to a point this far in front of the arc, on the street's line
local PATH_WIDTH = 8

local PLINTH_HEIGHT = 0.5 -- each board's bottom rests on a low Slate plinth on the grass
local BOARD_WIDTH = 10
local BOARD_HEIGHT = 12 -- the navy plate
local BOARD_TITLE = 1.8 -- the floating title over it
local BOARD_DEPTH = 0.6
local POST_SIZE = 1
local POST_GAP = 0.3 -- between a plate and its posts
local UNIT_GAP = 0.8 -- between the posts of two neighbours along the arc
local SIGN_WIDTH = 10
local SIGN_HEIGHT = 2.6
local SIGN_BOTTOM = 2.6
local PIXELS_PER_STUD = 40
local MAX_BOARDS = 4
local MAX_DISTANCE = 270 -- the SurfaceGuis stop drawing beyond this (the title is ~266 from TownSpawn; was 220)

-- Half the width of a board between its posts, and of the title; where the boards sit along the arc.
local UNIT_HALF = BOARD_WIDTH / 2 + POST_GAP + POST_SIZE
local SIGN_HALF = SIGN_WIDTH / 2 + POST_GAP + POST_SIZE
local INNER = SIGN_HALF + UNIT_GAP + UNIT_HALF -- the title's neighbours, along the arc from its middle
local PITCH = UNIT_HALF * 2 + UNIT_GAP

local WHITE = Palette.White
local WORLD = Palette.World
local ACCENT = Palette.Accent
local MEDALS = { "🥇", "🥈", "🥉" }

-- The board's own colour (its Leaderboard.BOARDS Color, a Palette key) in the world accents: its posts.
local function colorOf(id: string): Color3
	local def = Leaderboard.BOARDS[id]
	local color = def and rawget(ACCENT :: any, def.Color)
	return if typeof(color) == "Color3" then color else ACCENT.Blue
end

-- The garden's frame, read from what the town built: on the street's centre line where both the street and the
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
	local lawn = town and town:FindFirstChild("Lawn")
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
-- on the other side, the title in the middle.
local function arcPosition(index: number, count: number): number
	local left = math.ceil(count / 2)
	if index <= left then
		return INNER + (left - index) * PITCH
	end
	return -(INNER + (index - left - 1) * PITCH)
end

------------------------------------------------------------------------------------------------------------------
-- The board's SurfaceGui: the title floating over a navy plate with the rows on it
------------------------------------------------------------------------------------------------------------------

type RowView = { Frame: Frame, Rank: TextLabel, Name: TextLabel, User: TextLabel, Value: TextLabel }
type Face = { Rows: { RowView }, Message: TextLabel }

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

local function buildFace(board: BasePart, id: string, face: Enum.NormalId, shown: number): Face
	local def = Leaderboard.BOARDS[id]
	local width = board.Size.X * PIXELS_PER_STUD
	local titlePixels = BOARD_TITLE * PIXELS_PER_STUD
	local plateHeight = BOARD_HEIGHT * PIXELS_PER_STUD

	local gui = Parts.surface(
		board,
		if face == Enum.NormalId.Front then "BoardGui" else "BoardGuiBack",
		face,
		PIXELS_PER_STUD,
		MAX_DISTANCE,
		0 -- bright and readable at night
	)
	gui.ClipsDescendants = true
	Parts.floatText(gui, if def then def.Icon .. " " .. def.Title else id, {
		Shadow = true,
		Size = UDim2.new(1, 0, 0, titlePixels - 6),
		Position = UDim2.fromOffset(0, 0),
	})
	local plate = Parts.navyPlate(gui, {
		Size = UDim2.new(1, -8, 0, plateHeight - 8),
		Position = UDim2.new(0.5, 0, 0, titlePixels + plateHeight / 2),
	})

	local pad = 18
	local list = Instance.new("Frame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(pad, pad)
	list.Size = UDim2.new(1, -pad * 2, 1, -pad * 2)
	list.ZIndex = 3
	list.Parent = plate
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list

	local inner = width - 8 - pad * 2
	local rowHeight = math.floor((plateHeight - 8 - pad * 2 - 4 * (shown - 1)) / shown)
	local rows: { RowView } = {}
	for rank = 1, shown do
		local row = Instance.new("Frame")
		row.Name = "Row" .. rank
		row.LayoutOrder = rank
		row.Size = UDim2.new(1, 0, 0, rowHeight)
		row.BackgroundColor3 = WHITE
		row.BackgroundTransparency = if rank <= #MEDALS then 0.88 else 1 -- a faint band under the top 3
		row.BorderSizePixel = 0
		row.Visible = false
		row.ZIndex = 3
		Parts.rounded(row, UDim.new(0, 10))
		row.Parent = list

		local rankWidth = 36
		local valueWidth = 84
		local rankLabel =
			text(row, "Rank", UDim2.new(0, rankWidth, 1, -6), UDim2.fromOffset(4, 3), Palette.DisplayFont, WHITE)
		rankLabel.TextScaled = true
		rankLabel.Text = MEDALS[rank] or tostring(rank)

		local nameWidth = inner - rankWidth - valueWidth - 16
		local nameLabel = text(
			row,
			"Name",
			UDim2.fromOffset(nameWidth, math.floor(rowHeight * 0.6)),
			UDim2.fromOffset(rankWidth + 8, 1),
			Palette.BodyFont,
			WHITE
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
			WHITE
		)
		userLabel.TextTransparency = 0.35
		userLabel.TextSize = math.floor(rowHeight * 0.32)
		userLabel.TextXAlignment = Enum.TextXAlignment.Left
		userLabel.TextTruncate = Enum.TextTruncate.AtEnd

		local valueLabel = text(
			row,
			"Value",
			UDim2.new(0, valueWidth, 1, -8),
			UDim2.new(1, -valueWidth - 8, 0, 4),
			Palette.DisplayFont,
			Palette.Gold
		)
		valueLabel.TextScaled = true
		valueLabel.TextXAlignment = Enum.TextXAlignment.Right

		rows[rank] = { Frame = row, Rank = rankLabel, Name = nameLabel, User = userLabel, Value = valueLabel }
	end

	-- Loading, offline (Studio without API access) or nobody yet: one big outlined line where the rows go.
	local message = text(
		plate,
		"Message",
		UDim2.new(1, -pad * 4, 0.5, 0),
		UDim2.new(0, pad * 2, 0.2, 0),
		Palette.DisplayFont,
		WHITE
	)
	message.TextScaled = true
	message.TextWrapped = true
	Palette.outlineText(message, 3)

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

-- The lawn (studded GrassA, an 8-stud GrassB checker on whole studs), the plank path from the street's end to the
-- title, planters at the path's start, benches facing the boards, lamps at the arc's ends and voxel trees behind it.
local function buildGarden(model: Model, base: CFrame, pathStart: number, pathTop: number)
	local garden = Instance.new("Model")
	garden.Name = "Garden"
	local middle = GARDEN_DEPTH / 2
	local lawn = part(
		garden,
		"Lawn",
		Vector3.new(GARDEN_HALF_WIDTH * 2, 2, GARDEN_DEPTH),
		base * CFrame.new(0, -1, middle),
		WORLD.GrassA
	)
	Studs.apply(lawn)
	local cell = CHECKER_CELL
	for i = 0, math.ceil(GARDEN_HALF_WIDTH * 2 / cell) - 1 do
		for j = 0, math.ceil(GARDEN_DEPTH / cell) - 1 do
			if (i + j) % 2 == 1 then
				local x0 = -GARDEN_HALF_WIDTH + i * cell
				local x1 = math.min(x0 + cell, GARDEN_HALF_WIDTH)
				local z0 = j * cell
				local z1 = math.min(z0 + cell, GARDEN_DEPTH)
				if x1 - x0 >= 1 and z1 - z0 >= 1 then
					local tile = part(
						garden,
						"LawnTile",
						Vector3.new(x1 - x0, 0.2, z1 - z0),
						base * CFrame.new((x0 + x1) / 2, -0.05, (z0 + z1) / 2),
						WORLD.GrassB
					)
					soft(tile)
					Studs.apply(tile)
				end
			end
		end
	end

	-- The path's top is level with the street's, so the street runs straight onto it.
	local pathEnd = ARC_BACK - POST_SIZE / 2
	local length = pathEnd - pathStart
	local pathZ = pathStart + length / 2
	local path = Vector3.new(PATH_WIDTH, pathTop + 0.06, length)
	part(garden, "Path", path, base * CFrame.new(0, (pathTop - 0.06) / 2, pathZ), WORLD.Plank, Enum.Material.WoodPlanks)
	for _, side in { -1, 1 } do
		local edge = Vector3.new(0.5, pathTop + 0.1, length)
		local at = base * CFrame.new(side * (PATH_WIDTH / 2 + 0.25), (pathTop + 0.1) / 2 - 0.05, pathZ)
		paint(part(garden, "PathEdge", edge, at, WORLD.Trim))
	end

	for _, side in { 1, -1 } do
		Props.planter(garden, base * CFrame.new(side * (PATH_WIDTH / 2 + 3), 0, 4), Vector3.new(3, 1, 3))
		-- Between each pair of boards, 9 studs in front, facing them.
		Props.bench(garden, onArc(base, side * (INNER + PITCH / 2), 9) * CFrame.Angles(0, math.pi, 0))
		Props.lamp(garden, onArc(base, side * (INNER + PITCH + UNIT_HALF + 2.5), 0), 8)
	end
	Props.tree(garden, base * CFrame.new(0, 0, ARC_BACK + 9), 1.2)
	for _, side in { -1, 1 } do
		Props.tree(garden, base * CFrame.new(side * 18, 0, ARC_BACK + 7.5), 1.1)
		Props.tree(garden, base * CFrame.new(side * 36, 0, ARC_BACK + 2), 1.2)
	end
	garden.Parent = model
end

-- The "🏆 Hall of Fame" title in the middle of the arc, at the end of the path: gold outlined letters floating
-- between two dark posts whose lamp heads glow at night, and a gold trophy on top.
local function buildTitleSign(model: Model, at: CFrame)
	local postHeight = SIGN_BOTTOM + SIGN_HEIGHT + 0.4
	for _, side in { -1, 1 } do
		local x = side * (SIGN_HALF - POST_SIZE / 2)
		part(
			model,
			"SignPost",
			Vector3.new(POST_SIZE, postHeight, POST_SIZE),
			at * CFrame.new(x, postHeight / 2, 0),
			WORLD.Roof
		)
		local head = soft(
			part(model, "SignCap", Vector3.new(1.2, 1.2, 1.2), at * CFrame.new(x, postHeight + 0.6, 0), WORLD.Lamp)
		)
		head.CastShadow = false
		NightLights.light(head, 16)
	end
	local centre = at * CFrame.new(0, SIGN_BOTTOM + SIGN_HEIGHT / 2, 0)
	local sign = soft(part(model, "TitleSign", Vector3.new(SIGN_WIDTH, SIGN_HEIGHT, 0.4), centre, WORLD.Roof))
	sign.Transparency = 1 -- it only carries the floating letters
	sign.CastShadow = false
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Parts.surface(
			sign,
			if face == Enum.NormalId.Front then "TitleGui" else "TitleGuiBack",
			face,
			30,
			MAX_DISTANCE,
			0
		)
		Parts.floatText(gui, "🏆 Hall of Fame", { Gold = true, Shadow = true })
	end

	-- The trophy rests on a dark bar between the posts' tops.
	local gold = ACCENT.Yellow
	local barY = SIGN_BOTTOM + SIGN_HEIGHT + 0.2
	part(model, "TitleBar", Vector3.new(SIGN_HALF * 2, 0.4, POST_SIZE), at * CFrame.new(0, barY, 0), WORLD.Roof)
	local top = at * CFrame.new(0, barY + 0.2, 0)
	soft(part(model, "TrophyBase", Vector3.new(3, 0.5, 1.4), top * CFrame.new(0, 0.25, 0), WORLD.Trim))
	soft(Parts.cylinder(model, "TrophyStem", 0.9, 0.8, top * CFrame.new(0, 0.95, 0), gold))
	soft(Parts.ball(model, "TrophyCup", 2.4, top * CFrame.new(0, 2, 0), gold))
	soft(Parts.cylinder(model, "TrophyCup", 1.4, 2.6, top * CFrame.new(0, 2.7, 0), gold))
	soft(Parts.cylinder(model, "TrophyRim", 0.25, 2.7, top * CFrame.new(0, 3.45, 0), WORLD.Trim))
	for _, side in { -1, 1 } do
		soft(Parts.ball(model, "TrophyHandle", 1, top * CFrame.new(side * 1.5, 2.6, 0), gold))
	end
end

-- One board on the arc: a see-through part that carries the two faces (title + navy plate), a dark backing inside
-- the plate's edge, two studded posts in the board's accent, and a low Slate plinth.
local function buildStand(model: Model, id: string, at: CFrame): BasePart
	local tall = BOARD_HEIGHT + BOARD_TITLE
	local centre = at * CFrame.new(0, PLINTH_HEIGHT + tall / 2, 0)
	local board = part(model, "Board_" .. id, Vector3.new(BOARD_WIDTH, tall, BOARD_DEPTH), centre, Palette.Navy)
	board.Transparency = 1 -- the plate (a GUI) is the board: its round corners show
	board.CastShadow = false
	board:SetAttribute("BoardId", id)
	local back = part(
		model,
		"Back_" .. id,
		Vector3.new(BOARD_WIDTH - 1.2, BOARD_HEIGHT - 1.2, BOARD_DEPTH * 0.5),
		at * CFrame.new(0, PLINTH_HEIGHT + BOARD_HEIGHT / 2, 0),
		WORLD.Roof
	)
	back.CastShadow = false
	local plinth = Vector3.new(BOARD_WIDTH + (POST_GAP + POST_SIZE) * 2, PLINTH_HEIGHT + 0.1, 2)
	part(model, "Plinth", plinth, at * CFrame.new(0, (PLINTH_HEIGHT - 0.1) / 2, 0), WORLD.Edge, Enum.Material.Slate)
	local postHeight = PLINTH_HEIGHT + BOARD_HEIGHT + 0.6
	for _, side in { -1, 1 } do
		local x = side * (UNIT_HALF - POST_SIZE / 2)
		local post = part(
			model,
			"Post",
			Vector3.new(POST_SIZE, postHeight, POST_SIZE),
			at * CFrame.new(x, postHeight / 2, 0),
			colorOf(id)
		)
		Studs.apply(post)
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
