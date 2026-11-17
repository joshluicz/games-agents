--!strict
-- Boards: the 🏆 leaderboards panel (game/README.md "Leaderboards").
--   init(ctx)   opens on ctx.fire("Open", "Boards") (the HUD's 🏆 Top button)
-- One tab per board (Config.Leaderboards.Boards: 🏥 Cured, ⭐ Stars, ❤️ Hearts, 🏆 Week and, Progression v2, 🏢
-- Branches: Most Rebirths, admins never on it like every board). A page shows the top 10
-- (🥇🥈🥉, then numbers; each player's DisplayName with their @username small under it, as Roblox shows them) and,
-- pinned under it, your own bar: "You: #12" and your value, "You: #100+" past the top 100, "Play to join in!" before you
-- have a value, or "🛠️ Admins aren't ranked". Without DataStores (Studio without API access) the page says
-- "Leaderboards open when the game is live" and your bar still shows your value.
-- Everything comes from the server's GetBoards (its cache: no DataStore call), asked when the panel opens and every
-- POLL_SECONDS while it stays open. The client only shows it.
-- Look (the look overhaul's template, look build plan §B8): UI/Modal's navy header, its meta chip naming the open
-- board ("🏥 Most Patients Treated": the titles are Logic/Leaderboard's, the ids stay Cured and Week); Modal.tabs down
-- the left, each board's own colour as its tab's 6 px stripe; tinted rows
-- (the medal tints stay for the top 3, your own row gets the Bold outline); your bar pinned under them on the navy
-- of the header, in white outlined text. Phone-friendly: the tab column fits the height (and scrolls when five tabs
-- at 56 px don't fit a short landscape phone), the rows scroll, your bar stays put.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local Leaderboard = require(Shared:WaitForChild("Logic"):WaitForChild("Leaderboard"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Modal = require(script.Parent.Modal)
local Theme = require(script.Parent.Theme)

local Boards = {}

local TITLE = "Leaderboards" -- words only: the 🏆 is on the door (UI/Icons.Door.Top)
local ROW_HEIGHT = 52
local YOU_HEIGHT = 56
local RANK_WIDTH = 48
local VALUE_WIDTH = 116
local POLL_SECONDS = 20
local ASK_TIMEOUT = 10
local MEDALS = { "🥇", "🥈", "🥉" }
-- The medal tints for the top 3 (gold, silver, bronze); everyone else is the plain card.
local ROW_TINTS = {
	Kit.lighten(Palette.Candy.Yellow, 0.62),
	Theme.Colors.Well,
	Kit.lighten(Palette.Candy.Orange, 0.66),
}

type RowView = { Frame: Frame, Stroke: UIStroke, Rank: TextLabel, Name: TextLabel, User: TextLabel, Value: TextLabel }

local function colorOf(id: string): Color3
	local def = Leaderboard.BOARDS[id]
	local color = def and rawget(Palette.Candy :: any, def.Color)
	return if typeof(color) == "Color3" then color else Theme.Colors.Secondary
end

-- A server answer, checked field by field (it is the server's, but a bad one must never break the panel).
local function clean(payload: any): Leaderboard.Payload?
	if type(payload) ~= "table" or type(payload.Boards) ~= "table" then
		return nil
	end
	local status = payload.Status
	if status ~= "Live" and status ~= "Offline" and status ~= "Loading" then
		return nil
	end
	local boards: { Leaderboard.BoardPayload } = {}
	for _, board in payload.Boards do
		if type(board) ~= "table" or not Leaderboard.isBoard(board.Id) then
			continue
		end
		local top: { Leaderboard.Row } = {}
		if type(board.Top) == "table" then
			for _, row in board.Top do
				if type(row) == "table" and type(row.Rank) == "number" and type(row.Value) == "number" then
					table.insert(top, {
						Rank = row.Rank,
						Name = if type(row.Name) == "string" then row.Name else "...",
						User = if type(row.User) == "string" then row.User else "",
						Value = row.Value,
					})
				end
			end
		end
		local mine: any = if type(board.You) == "table" then board.You else {}
		table.insert(boards, {
			Id = board.Id,
			Top = top,
			You = {
				Rank = if type(mine.Rank) == "number" then mine.Rank else nil,
				Value = if type(mine.Value) == "number" then mine.Value else 0,
				Hidden = mine.Hidden == true,
			},
		})
	end
	return {
		Status = status,
		Depth = if type(payload.Depth) == "number" then payload.Depth else 100,
		Boards = boards,
	}
end

function Boards.init(ctx: Types.Ctx)
	local config = ctx.Config.Leaderboards
	local ids: { string } = {}
	for _, id in (if type(config) == "table" and type(config.Boards) == "table" then config.Boards else {}) do
		if Leaderboard.isBoard(id) and not table.find(ids, id) then
			table.insert(ids, id)
		end
	end
	local shown = if type(config) == "table" and type(config.Shown) == "number" then config.Shown else 10
	if #ids == 0 then
		return
	end

	local modal = Hud.modal(ctx, {
		Name = "Boards",
		Title = TITLE,
		MaxSize = Vector2.new(640, 580),
	})

	--------------------------------------------------------------------------------------------------------------
	-- THE tabs (Modal.tabs: the column scrolls so five fit a short phone), the page beside them: the rows
	-- (scrolling) and your bar under them
	--------------------------------------------------------------------------------------------------------------
	local current = ids[1]
	local selectTab: (id: string) -> () = function() end
	local tabSpecs = {}
	for _, id in ids do
		local def = Leaderboard.BOARDS[id]
		table.insert(tabSpecs, { Id = id, Icon = def.Icon, Caption = def.Caption, Stripe = colorOf(id) })
	end
	local tabView = Modal.tabs(modal, tabSpecs, function(id: string)
		selectTab(id)
	end)
	local tabButtons = tabView.Buttons
	local page = tabView.Content

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.new(1, 0, 1, -(YOU_HEIGHT + Theme.Size.Gap))
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = Theme.Colors.Stroke
	scroll.Selectable = false
	scroll.Parent = page
	local rowList = Kit.list(scroll, Enum.FillDirection.Vertical, Theme.Space.Line)
	rowList.VerticalAlignment = Enum.VerticalAlignment.Top
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 3)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 3) -- scrolling frames clip: keep the rows' outlines whole
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = scroll

	local rows: { RowView } = {}
	for rank = 1, shown do
		local frame = Instance.new("Frame")
		frame.Name = "Row" .. rank
		frame.LayoutOrder = rank
		frame.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		frame.BackgroundColor3 = ROW_TINTS[rank] or Theme.Colors.Card
		frame.BorderSizePixel = 0
		frame.Visible = false
		Kit.corner(frame, Theme.Radius.Medium)
		-- A row is a card: a fill and no line. Only YOUR row is outlined (a state, not decoration).
		local stroke = Kit.stroke(frame, Theme.Colors.Stroke, Theme.Stroke.Bold) -- uirules: allow StrokeBudget (your own row)
		stroke.Enabled = false
		frame.Parent = scroll

		local rankLabel = Kit.label({
			Name = "Rank",
			Text = MEDALS[rank] or tostring(rank),
			Font = Theme.DisplayFont,
			TextScaled = true,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, 0),
			Size = UDim2.fromOffset(RANK_WIDTH - 8, ROW_HEIGHT - 14),
			Parent = frame,
		})
		Kit.textLimit(rankLabel, Theme.TextSize.Title)
		local nameLabel = Kit.label({
			Name = "Name",
			TextSize = Theme.TextSize.Caption + 2,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(RANK_WIDTH + 4, 3),
			Size = UDim2.new(1, -(RANK_WIDTH + VALUE_WIDTH + 14), 0, 26),
			Parent = frame,
		})
		local userLabel = Kit.label({
			Name = "User",
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Colors.InkSoft,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(RANK_WIDTH + 4, 28),
			Size = UDim2.new(1, -(RANK_WIDTH + VALUE_WIDTH + 14), 0, 20),
			Parent = frame,
		})
		local valueLabel = Kit.label({
			Name = "Value",
			Font = Theme.DisplayFont,
			TextScaled = true,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(VALUE_WIDTH, ROW_HEIGHT - 18),
			Parent = frame,
		})
		Kit.textLimit(valueLabel, Theme.TextSize.Title)
		rows[rank] = {
			Frame = frame,
			Stroke = stroke,
			Rank = rankLabel,
			Name = nameLabel,
			User = userLabel,
			Value = valueLabel,
		}
	end

	-- Loading, offline or nobody yet: one line where the rows go.
	local message = Kit.label({
		Name = "Message",
		Font = Theme.DisplayFont,
		TextColor3 = Theme.Colors.Ink,
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -(YOU_HEIGHT + Theme.Size.Gap) / 2),
		Size = UDim2.new(0.9, 0, 0, 90),
		Visible = false,
		Parent = page,
	})
	Kit.textLimit(message, Theme.TextSize.Title)

	-- Your own bar, pinned at the bottom on the header's navy (the template's footer: "your bar").
	local you = Instance.new("Frame")
	you.Name = "You"
	you.AnchorPoint = Vector2.new(0, 1)
	you.Position = UDim2.new(0, Theme.Space.Step[1], 1, -Theme.Space.Step[1])
	you.Size = UDim2.new(1, -Theme.Space.Step[5], 0, YOU_HEIGHT - Theme.Space.Gap)
	you.BackgroundColor3 = Theme.Colors.Header
	you.BorderSizePixel = 0
	Kit.corner(you, Theme.Radius.Medium)
	you.Parent = page
	local youText = Kit.label({
		Name = "Place",
		Outlined = true,
		TextScaled = true,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.new(1, -(VALUE_WIDTH + 34), 0, 32),
		ZIndex = 2,
		Parent = you,
	})
	Kit.textLimit(youText, Theme.TextSize.Title)
	local youValue = Kit.label({
		Name = "Value",
		Outlined = true,
		TextScaled = true,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(VALUE_WIDTH, 32),
		ZIndex = 2,
		Parent = you,
	})
	Kit.textLimit(youValue, Theme.TextSize.Title)

	--------------------------------------------------------------------------------------------------------------
	-- Drawing
	--------------------------------------------------------------------------------------------------------------
	local latest: Leaderboard.Payload? = nil

	local function boardOf(payload: Leaderboard.Payload?, id: string): Leaderboard.BoardPayload?
		if not payload then
			return nil
		end
		for _, board in payload.Boards do
			if board.Id == id then
				return board
			end
		end
		return nil
	end

	local function render()
		local def = Leaderboard.BOARDS[current]
		modal.setMeta(if def then def.Icon .. " " .. def.Title else "")

		local payload = latest
		local status: Leaderboard.Status = if payload then payload.Status else "Loading"
		local board = boardOf(payload, current)
		local top = if status == "Live" and board then board.Top else {}
		local mine = if board then board.You else nil
		for rank, row in rows do
			local entry = top[rank]
			row.Frame.Visible = entry ~= nil
			if entry then
				row.Name.Text = entry.Name
				row.User.Text = if entry.User ~= "" then "@" .. entry.User else ""
				row.Value.Text = Hud.format(entry.Value)
				local isMe = mine ~= nil and mine.Rank == rank
				row.Frame.BackgroundColor3 = ROW_TINTS[rank] or Theme.Colors.Card
				row.Stroke.Enabled = isMe
			end
		end
		local text = if status == "Offline"
			then Leaderboard.TEXT.Offline
			elseif status == "Loading" or not board then Leaderboard.TEXT.Loading
			elseif #top == 0 then Leaderboard.TEXT.Empty
			else ""
		message.Text = text
		message.Visible = text ~= ""

		local value = if mine then mine.Value else 0
		youValue.Text = if mine and not mine.Hidden and value > 0 then Hud.format(value) else ""
		if mine and mine.Hidden then
			youText.Text = Leaderboard.TEXT.Admin
		elseif mine and value <= 0 then
			youText.Text = Leaderboard.TEXT.Join
		elseif not mine or status ~= "Live" then
			youText.Text = "You" -- no rank to show: still loading, or offline (Studio without API access)
		elseif mine.Rank then
			youText.Text = "You: #" .. mine.Rank
		else
			youText.Text = "You: #" .. (if payload then payload.Depth else 100) .. "+"
		end
	end

	-- Shows a board (Modal.tabs has painted its tab already).
	selectTab = function(id: string)
		if not tabButtons[id] then
			return
		end
		current = id
		modal.Focus = tabButtons[id]
		scroll.CanvasPosition = Vector2.zero
		render()
	end

	--------------------------------------------------------------------------------------------------------------
	-- Asking the server (its cache): when the panel opens, then every POLL_SECONDS while it's open
	--------------------------------------------------------------------------------------------------------------
	-- Like Hud.ask, but the answer is a table: nil on an error, a rate limit or no answer within ASK_TIMEOUT.
	local function ask(): any
		local thread = coroutine.running()
		local done = false
		local function finish(result: any)
			if not done then
				done = true
				task.spawn(thread, result)
			end
		end
		task.defer(function()
			local ok, result = pcall(function()
				return ctx.Remotes.GetBoards:InvokeServer()
			end)
			finish(if ok then result else nil)
		end)
		task.delay(ASK_TIMEOUT, finish, nil)
		return coroutine.yield()
	end

	local fetching = false
	local function refresh()
		if fetching then
			return
		end
		fetching = true
		local payload = clean(ask())
		fetching = false
		if payload then
			latest = payload
		end
		if modal.isOpen() then
			render()
		end
	end

	local session = 0
	ctx.on("Open", function(name: any)
		if name ~= "Boards" then
			return
		end
		tabView.select(current)
		modal.open()
		session += 1
		local mySession = session
		task.spawn(function()
			while modal.isOpen() and session == mySession do
				refresh()
				task.wait(POLL_SECONDS)
			end
		end)
	end)

	selectTab(current)
end

return Boards
