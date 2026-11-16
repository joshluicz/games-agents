--!strict
-- Shop (build plan Task 6): spend cash on ⚡ Upgrades, 🏠 Rooms and 🌸 Decor, and place decor in your rooms.
-- Depth update (T5): the 🏥 Hospital tab, your hospital level and the next one (what it costs, what it unlocks,
-- Level up), and rooms that need a higher level ("🏥 Lv 3", which leads to the Hospital tab).
--   init(ctx)   opens on ctx.fire("Open", "Shop", tab?) with tab "Upgrades" | "Rooms" | "Decor" | "Hospital"
--   Shop.upgradeButton(upgradeId): TextButton?   that upgrade row's buy button (UI/Tutorial points at it)
--   Shop.tabButton(tabId): TextButton?           a tab ("Upgrades" | "Rooms" | "Decor" | "Hospital")
--   Shop.levelUpButton(): TextButton?            the Hospital tab's Level up button (for pointers)
-- Every price, lock and level shown here is read from the Snapshot and Shared/Data, for display only. Buying calls
-- Purchase(kind, id), placing calls PlaceDecor(slotKey, decorId?) and levelling up calls LevelUp(); the server
-- checks everything and answers (ok, message), which is shown as a toast (a level-up's yes is the server's Celebrate
-- screen instead, and the Shop closes so the building can be seen growing). Nothing changes on screen until the
-- server's next Snapshot.
-- Bus: fires "Purchased" (kind, id) and "DecorPlaced" (slotKey, decorId?) after the server says yes (a level-up is
-- kind "Level", id "<new level>").
-- Look (candy pop, memory-20261116-007): a pink header; each row is a white card with a thick outline and a bright
-- icon tile. What you can buy is a lime button with a shine; what you can't is grey with a 🔒. Nothing here is
-- Robux: every price is in-game 💰.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local Prices = require(Shared:WaitForChild("Logic"):WaitForChild("Prices"))
local LevelsLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Levels"))
local ProgressLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Progress"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Shop = {}

local ACCENT = Theme.Colors.Pink
local TABS = {
	{ Id = "Upgrades", Icon = "⚡", Caption = "Upgrades", Color = Theme.Colors.Primary },
	{ Id = "Rooms", Icon = "🏠", Caption = "Rooms", Color = Theme.Colors.Secondary },
	{ Id = "Decor", Icon = "🌸", Caption = "Decor", Color = Theme.Colors.Pink },
	{ Id = "Hospital", Icon = "🏥", Caption = "Hospital", Color = Theme.Colors.Purple }, -- depth update
}
local HOSPITAL = Theme.Colors.Purple
local LEVEL_BUTTON_WIDTH = 200
local LADDER_TILE = 40
-- Each row's icon tile takes the next candy colour, so a page reads as a bright stack.
local TILE_COLORS = {
	Theme.Colors.Pink,
	Theme.Colors.Secondary,
	Theme.Colors.Primary,
	Theme.Colors.Purple,
	Theme.Colors.Good,
	Theme.Colors.Cyan,
}
local TAB_WIDTH = Theme.Size.IconButton
local ROW_HEIGHT = 84
local BUY_WIDTH = 132
local EARNED_HOW: { [string]: string } = {
	Book = "📖 Finish a Book set",
	Story = "💌 A friend's thank-you",
	Referral = "🤝 Friend gift",
}

type Row = {
	Frame: Frame,
	Tile: Frame,
	Color: Color3, -- the tile's own candy colour
	Icon: TextLabel,
	Title: TextLabel,
	Pips: Frame,
	Note: TextLabel,
	Buy: TextButton,
}

-- Light = dark body text with no outline (like Kit's Quiet/Card kinds); otherwise white outlined display text.
-- Shine = a call to action (Kit.shine); Lock = the 🔒 badge on the button's corner.
type Style = { Color: Color3, Light: boolean, Active: boolean, Shine: boolean, Lock: boolean }
local STYLES: { [string]: Style } = {
	Buy = { Color = Theme.Colors.Good, Light = false, Active = true, Shine = true, Lock = false },
	-- Can't afford it yet: grey and locked, but still tappable so it can say how much more you need.
	Poor = { Color = Theme.Colors.Disabled, Light = false, Active = true, Shine = false, Lock = true },
	Done = { Color = Theme.Colors.Card, Light = true, Active = false, Shine = false, Lock = false },
	Locked = { Color = Theme.Colors.Disabled, Light = false, Active = false, Shine = false, Lock = true },
	Place = { Color = Theme.Colors.Secondary, Light = false, Active = true, Shine = true, Lock = false },
	Busy = { Color = Theme.Colors.Quiet, Light = true, Active = false, Shine = false, Lock = false },
}

local function childOf(parent: Instance, name: string, class: string): Instance?
	local found = parent:FindFirstChild(name)
	return if found and found:IsA(class) then found else nil
end

local function setVisible(parent: Instance, name: string, visible: boolean)
	local found = childOf(parent, name, "GuiObject") :: GuiObject?
	if found then
		found.Visible = visible
	end
end

local function style(button: TextButton, name: string, text: string)
	local s = STYLES[name] or STYLES.Buy
	local fill = if s.Light then s.Color else Kit.lighten(s.Color, 0.08)
	button.Text = text
	button.BackgroundColor3 = fill
	button.TextColor3 = if s.Light then Theme.Colors.Ink else Theme.Colors.OnColor
	button.Font = if s.Light then Theme.Font else Theme.DisplayFont
	button.Interactable = s.Active
	button:SetAttribute("KitColor", fill)
	local outline = childOf(button, "TextOutline", "UIStroke") :: UIStroke?
	if outline then
		outline.Enabled = not s.Light
	end
	setVisible(button, "Shine", s.Shine)
	setVisible(button, "Lock", s.Lock)
end

-- Everything style() changes, so a request can put the button back exactly as it was.
type Look = {
	Text: string,
	Color: Color3,
	TextColor: Color3,
	Font: Enum.Font,
	Interactable: boolean,
	KitColor: any,
	Outlined: boolean?,
	Shine: boolean?,
	Lock: boolean?,
}

local function lookOf(button: TextButton): Look
	local outline = childOf(button, "TextOutline", "UIStroke") :: UIStroke?
	local shine = childOf(button, "Shine", "GuiObject") :: GuiObject?
	local lock = childOf(button, "Lock", "GuiObject") :: GuiObject?
	return {
		Text = button.Text,
		Color = button.BackgroundColor3,
		TextColor = button.TextColor3,
		Font = button.Font,
		Interactable = button.Interactable,
		KitColor = button:GetAttribute("KitColor"),
		Outlined = if outline then outline.Enabled else nil,
		Shine = if shine then shine.Visible else nil,
		Lock = if lock then lock.Visible else nil,
	}
end

local function setLook(button: TextButton, look: Look)
	button.Text = look.Text
	button.BackgroundColor3 = look.Color
	button.TextColor3 = look.TextColor
	button.Font = look.Font
	button.Interactable = look.Interactable
	button:SetAttribute("KitColor", look.KitColor)
	local outline = childOf(button, "TextOutline", "UIStroke") :: UIStroke?
	if outline and look.Outlined ~= nil then
		outline.Enabled = look.Outlined
	end
	if look.Shine ~= nil then
		setVisible(button, "Shine", look.Shine)
	end
	if look.Lock ~= nil then
		setVisible(button, "Lock", look.Lock)
	end
end

-- The shape outline Kit draws round a button (not the Contextual one round its text).
local function borderOf(gui: Instance): UIStroke?
	for _, child in gui:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
			return child
		end
	end
	return nil
end

-- A tab in its own colour: a pale tint while it waits, full candy with outlined text when it's open.
local function paintTab(button: TextButton, selected: boolean, color: Color3)
	button.BackgroundColor3 = if selected then Kit.lighten(color, 0.08) else Kit.lighten(color, 0.78)
	local border = borderOf(button)
	if border then
		border.Color = Theme.Colors.Outline
		border.Thickness = if selected then Theme.Size.StrokeLarge else Theme.Size.Stroke
	end
	local caption = childOf(button, "Caption", "TextLabel") :: TextLabel?
	if caption then
		caption.TextColor3 = if selected then Theme.Colors.OnColor else Theme.Colors.Ink
		Kit.outline(caption, 2).Enabled = selected
	end
end

local function textLimit(label: TextLabel, max: number)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = max
	limit.MinTextSize = 12
	limit.Parent = label
end

local function page(parent: Instance, name: string): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = Theme.Colors.Stroke
	scroll.Selectable = false
	scroll.Visible = false
	local list = Kit.list(scroll, Enum.FillDirection.Vertical, 8)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 3)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 3) -- scrolling frames clip: keep the rows' outlines whole
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = scroll
	scroll.Parent = parent
	return scroll
end

-- The 🔒 badge on a button's top-left corner (shown by the Poor and Locked styles).
local function lockBadge(button: TextButton)
	local badge = Instance.new("Frame")
	badge.Name = "Lock"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromOffset(6, 6)
	badge.Size = UDim2.fromOffset(28, 28)
	badge.BackgroundColor3 = Theme.Colors.Paper
	badge.BorderSizePixel = 0
	badge.Visible = false
	badge.ZIndex = 3
	Kit.corner(badge, 14)
	Kit.stroke(badge, Theme.Colors.Outline, 2.5)
	Kit.label({
		Name = "Icon",
		Text = "🔒",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.7),
		ZIndex = 3,
		Parent = badge,
	})
	badge.Parent = button
end

-- "Open" = a white card · "Owned" = a pale lime card · "Locked" = the icon tile goes grey.
local function setRowState(row: Row, state: string)
	row.Frame.BackgroundColor3 = if state == "Owned" then Kit.lighten(Theme.Colors.Good, 0.85) else Theme.Colors.Paper
	row.Tile.BackgroundColor3 = if state == "Locked" then Theme.Colors.Disabled else Kit.lighten(row.Color, 0.08)
end

local function makeRow(parent: Instance, order: number, icon: string, title: string): Row
	local color = TILE_COLORS[(order - 1) % #TILE_COLORS + 1]
	local frame = Instance.new("Frame")
	frame.Name = "Row" .. order
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	frame.BackgroundColor3 = Theme.Colors.Paper
	frame.BorderSizePixel = 0
	Kit.corner(frame, 16)
	Kit.stroke(frame, Theme.Colors.Outline, Theme.Size.Stroke)

	-- The icon tile: the item's emoji on its own candy square.
	local tile = Instance.new("Frame")
	tile.Name = "Tile"
	tile.AnchorPoint = Vector2.new(0, 0.5)
	tile.Position = UDim2.new(0, 10, 0.5, 0)
	tile.Size = UDim2.fromOffset(60, 60)
	tile.BackgroundColor3 = Kit.lighten(color, 0.08)
	tile.BorderSizePixel = 0
	Kit.corner(tile, 14)
	Kit.stroke(tile, Theme.Colors.Outline, Theme.Size.Stroke)
	Palette.candyGradient(tile)
	Kit.gloss(tile, 4)
	tile.Parent = frame
	local iconLabel = Kit.label({
		Name = "Icon",
		Text = icon,
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.78, 0.78),
		Parent = tile,
	})
	local titleLabel = Kit.label({
		Name = "Title",
		Text = title,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(80, 12),
		Size = UDim2.new(1, -(80 + BUY_WIDTH + 20), 0, 28),
		Parent = frame,
	})
	textLimit(titleLabel, 24)

	local pips = Instance.new("Frame")
	pips.Name = "Pips"
	pips.BackgroundTransparency = 1
	pips.Position = UDim2.fromOffset(80, 46)
	pips.Size = UDim2.fromOffset(0, 24)
	pips.AutomaticSize = Enum.AutomaticSize.X
	pips.Parent = frame
	local pipList = Kit.list(pips, Enum.FillDirection.Horizontal, 6)
	pipList.HorizontalAlignment = Enum.HorizontalAlignment.Left

	local note = Kit.label({
		Name = "Note",
		Text = "",
		TextScaled = true,
		TextColor3 = Theme.Colors.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(80, 46),
		Size = UDim2.new(1, -(80 + BUY_WIDTH + 20), 0, 24),
		Parent = frame,
	})
	textLimit(note, 18)

	local buy = Kit.button({
		Name = "Buy",
		Kind = "Good",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(BUY_WIDTH, Theme.Size.ButtonHeight),
		TextSize = Theme.TextSize.Body,
		TextScaled = true, -- the chunky display font is wide: a long price shrinks to fit, never below 18
		Parent = frame,
	})
	local buyLimit = Instance.new("UITextSizeConstraint")
	buyLimit.MaxTextSize = Theme.TextSize.Body
	buyLimit.MinTextSize = Theme.TextSize.Small
	buyLimit.Parent = buy
	Kit.shine(buy) -- shown only while the row is a call to action (style's Shine)
	lockBadge(buy)
	frame.Parent = parent
	return {
		Frame = frame,
		Tile = tile,
		Color = color,
		Icon = iconLabel,
		Title = titleLabel,
		Pips = pips,
		Note = note,
		Buy = buy,
	}
end

-- Level dots (●●○) at the start of the note line; the note moves right to make room.
local function setPips(row: Row, level: number, max: number)
	for _, child in row.Pips:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i = 1, max do
		local dot = Instance.new("Frame")
		dot.Name = "Pip" .. i
		dot.LayoutOrder = i
		dot.Size = UDim2.fromOffset(12, 12) -- 12 + a 2 px outline each side, 6 apart: the same 18 px pitch
		dot.BackgroundColor3 = if i <= level then Theme.Colors.Star else Theme.Colors.Paper
		dot.BorderSizePixel = 0
		Kit.corner(dot, 6)
		Kit.stroke(dot, Theme.Colors.Outline, 2)
		dot.Parent = row.Pips
	end
	local shift = if max > 0 then max * 18 + 6 else 0
	row.Note.Position = UDim2.fromOffset(80 + shift, 46)
	row.Note.Size = UDim2.new(1, -(80 + shift + BUY_WIDTH + 20), 0, 24)
end

local function usesDirectionalFocus(): boolean
	local preferred = UserInputService.PreferredInput
	return preferred == Enum.PreferredInput.Gamepad or preferred == Enum.PreferredInput.MicroGamepad
end

local upgradeButtons: { [string]: TextButton } = {}
local tabs: { [string]: TextButton } = {}
local levelButton: TextButton? = nil

function Shop.upgradeButton(upgradeId: string): TextButton?
	return upgradeButtons[upgradeId]
end

function Shop.tabButton(tabId: string): TextButton?
	return tabs[tabId]
end

function Shop.levelUpButton(): TextButton?
	return levelButton
end

-- A white card with the shop's thick outline.
local function card(parent: Instance, name: string, order: number, color: Color3): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.LayoutOrder = order
	frame.Size = UDim2.fromScale(1, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	Kit.corner(frame, 16)
	Kit.stroke(frame, Theme.Colors.Outline, Theme.Size.Stroke)
	frame.Parent = parent
	return frame
end

-- A candy icon tile (like the rows' tiles).
local function iconTile(parent: Instance, name: string, size: number, color: Color3, icon: string): (Frame, TextLabel)
	local tile = Instance.new("Frame")
	tile.Name = name
	tile.Size = UDim2.fromOffset(size, size)
	tile.BackgroundColor3 = Kit.lighten(color, 0.08)
	tile.BorderSizePixel = 0
	Kit.corner(tile, math.floor(size * 0.22))
	Kit.stroke(tile, Theme.Colors.Outline, Theme.Size.Stroke)
	Palette.candyGradient(tile)
	Kit.gloss(tile, 4)
	tile.Parent = parent
	local label = Kit.label({
		Name = "Icon",
		Text = icon,
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.78, 0.78),
		Parent = tile,
	})
	return tile, label
end

-- An unlock chip: an emoji and a couple of words on a pale pill.
local function chip(parent: Instance, order: number, text: string)
	local pill = Instance.new("Frame")
	pill.Name = "Chip" .. order
	pill.LayoutOrder = order
	pill.Size = UDim2.fromOffset(0, 36)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.BackgroundColor3 = Kit.lighten(HOSPITAL, 0.86)
	pill.BorderSizePixel = 0
	Kit.corner(pill, 18)
	Kit.stroke(pill, Theme.Colors.Outline, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = pill
	Kit.label({
		Name = "Text",
		Text = text,
		TextSize = Theme.TextSize.Small,
		TextWrapped = false,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 36),
		Parent = pill,
	})
	pill.Parent = parent
end

function Shop.init(ctx: Types.Ctx)
	local data = ctx.Data :: any
	local modal = Hud.modal(ctx, {
		Name = "Shop",
		Title = "🛒 Shop",
		Accent = ACCENT,
		MaxSize = Vector2.new(680, 560),
	})

	--------------------------------------------------------------------------------------------------------------
	-- Tabs down the left (landscape phones are short, so the list gets the height), pages on the right
	--------------------------------------------------------------------------------------------------------------
	local tabColumn = Instance.new("Frame")
	tabColumn.Name = "Tabs"
	tabColumn.BackgroundTransparency = 1
	tabColumn.Size = UDim2.new(0, TAB_WIDTH, 1, 0)
	tabColumn.Parent = modal.Body
	local tabList = Kit.list(tabColumn, Enum.FillDirection.Vertical, 8)
	tabList.VerticalAlignment = Enum.VerticalAlignment.Top

	local pagesArea = Instance.new("Frame")
	pagesArea.Name = "Pages"
	pagesArea.BackgroundTransparency = 1
	pagesArea.Position = UDim2.fromOffset(TAB_WIDTH + Theme.Size.Gap, 0)
	pagesArea.Size = UDim2.new(1, -(TAB_WIDTH + Theme.Size.Gap), 1, 0)
	pagesArea.Parent = modal.Body

	local tabButtons: { [string]: TextButton } = {}
	local tabColors: { [string]: Color3 } = {}
	local pages: { [string]: ScrollingFrame } = {}
	local current = "Upgrades"

	local function selectTab(id: string)
		if not pages[id] then
			return
		end
		current = id
		for tabId, button in tabButtons do
			local selected = tabId == id
			paintTab(button, selected, tabColors[tabId])
			pages[tabId].Visible = selected
		end
		modal.Focus = tabButtons[id]
	end

	for index, tab in TABS do
		local button = Kit.iconButton({
			Name = "Tab_" .. tab.Id,
			Icon = tab.Icon,
			Caption = tab.Caption,
			LayoutOrder = index,
			Size = UDim2.fromOffset(TAB_WIDTH, TAB_WIDTH),
			Parent = tabColumn,
		})
		local caption = button:FindFirstChild("Caption")
		if caption and caption:IsA("TextLabel") then
			caption.TextScaled = true
			textLimit(caption, Theme.TextSize.Small)
		end
		button.Activated:Connect(function()
			selectTab(tab.Id)
		end)
		tabButtons[tab.Id] = button
		tabs[tab.Id] = button
		tabColors[tab.Id] = tab.Color
		pages[tab.Id] = page(pagesArea, tab.Id)
	end
	Hud.fitTabs(tabColumn, { tabButtons.Upgrades, tabButtons.Rooms, tabButtons.Decor, tabButtons.Hospital }, 8)

	--------------------------------------------------------------------------------------------------------------
	-- Asking the server
	--------------------------------------------------------------------------------------------------------------
	local busy = false
	local refresh: (state: Types.Snapshot) -> ()

	-- quiet = no toast and no chime on a yes (a level-up: the server's Celebrate screen says it).
	local function send(button: TextButton, quiet: boolean, remote: RemoteFunction, ...: any): boolean
		if busy then
			return false
		end
		busy = true
		local before = lookOf(button)
		style(button, "Busy", "⏳")
		local ok, message = Hud.ask(remote, ...)
		busy = false
		-- Put the button back as it was; refresh restyles the rows from the newest Snapshot.
		setLook(button, before)
		if ok then
			if not quiet then
				ctx.toast(if message ~= "" then message else "🎉 Yay!")
				Hud.sound("Chime")
			end
			Hud.fly(button, "✨", nil, 6)
		else
			ctx.toast(if message ~= "" then message else "Oops! Try again.")
			Hud.shake(button)
		end
		refresh(ctx.State)
		return ok
	end

	local function request(button: TextButton, remote: RemoteFunction, ...: any): boolean
		return send(button, false, remote, ...)
	end

	local function needMore(button: TextButton, price: number)
		local short = price - (ctx.State.Cash or 0)
		ctx.toast("Need 💰" .. Hud.format(short) .. " more!")
		Hud.shake(button)
	end

	--------------------------------------------------------------------------------------------------------------
	-- Upgrades
	--------------------------------------------------------------------------------------------------------------
	local upgradeRows: { [string]: Row } = {}
	for index, upgradeId in data.Upgrades.Order do
		local upgrade = data.Upgrades[upgradeId]
		local row = makeRow(pages.Upgrades, index, upgrade.Icon, upgrade.Name)
		row.Buy.Activated:Connect(function()
			local state = ctx.State
			local level = (state.Upgrades or {})[upgradeId] or 0
			local price = Prices.upgradePrice(data.Upgrades, upgradeId, level)
			if not price then
				return
			end
			if (state.Cash or 0) < price then
				needMore(row.Buy, price)
				return
			end
			if request(row.Buy, ctx.Remotes.Purchase, "Upgrade", upgradeId) then
				ctx.fire("Purchased", "Upgrade", upgradeId)
				Hud.pop(row.Frame, 1.05)
				Kit.bump(row.Tile)
			end
		end)
		upgradeRows[upgradeId] = row
		upgradeButtons[upgradeId] = row.Buy
	end

	local function refreshUpgrades(state: Types.Snapshot)
		for upgradeId, row in upgradeRows do
			local upgrade = data.Upgrades[upgradeId]
			local level = (state.Upgrades or {})[upgradeId] or 0
			local max = #upgrade.Prices
			local price = Prices.upgradePrice(data.Upgrades, upgradeId, level)
			setPips(row, math.min(level, max), max)
			row.Note.Text = upgrade.Hint
			setRowState(row, if price then "Open" else "Owned")
			if not price then
				style(row.Buy, "Done", "✅ Max")
			elseif (state.Cash or 0) >= price then
				style(row.Buy, "Buy", "💰 " .. Hud.format(price))
			else
				style(row.Buy, "Poor", "💰 " .. Hud.format(price))
			end
		end
	end

	--------------------------------------------------------------------------------------------------------------
	-- Rooms
	--------------------------------------------------------------------------------------------------------------
	local roomRows: { [string]: Row } = {}
	local roomOrder = 0
	for _, roomId in data.Rooms.Order do
		local room = data.Rooms[roomId]
		if room.Price > 0 then -- the Stand is free and always yours
			roomOrder += 1
			local row = makeRow(pages.Rooms, roomOrder, room.Icon, room.Name)
			row.Buy.Activated:Connect(function()
				local state = ctx.State
				if state.PlotIndex == nil then
					ctx.toast("🏠 You need a clinic first!")
					Hud.shake(row.Buy)
					return
				end
				local needLevel = room.Level or 1
				if needLevel > (state.Level or 1) then
					-- A room for a bigger hospital: show the way there.
					ctx.toast("Needs 🏥 Lv " .. needLevel .. "!")
					Hud.shake(row.Buy)
					selectTab("Hospital")
					return
				end
				if (state.Cash or 0) < room.Price then
					needMore(row.Buy, room.Price)
					return
				end
				if request(row.Buy, ctx.Remotes.Purchase, "Room", roomId) then
					ctx.fire("Purchased", "Room", roomId)
					Hud.pop(row.Frame, 1.06)
					Kit.bump(row.Tile) -- CureFX's NEW ROOM banner (with rays) follows
				end
			end)
			roomRows[roomId] = row
		end
	end

	-- What a room adds, in icons: its stations, a 🛏️ per bed and a 🌸 per decor slot.
	local function roomGifts(room: any): string
		local parts = {}
		for _, stationId in room.Stations do
			local station = data.Stations[stationId]
			if station then
				table.insert(parts, station.Icon)
			end
		end
		if room.Beds > 0 then
			table.insert(parts, string.rep("🛏️", room.Beds))
		end
		if room.DecorSlots > 0 then
			table.insert(parts, string.rep("🌸", room.DecorSlots))
		end
		return table.concat(parts, " ")
	end

	local function refreshRooms(state: Types.Snapshot)
		local stars = state.Stars or 0
		for roomId, row in roomRows do
			local room = data.Rooms[roomId]
			local owned = state.Rooms and state.Rooms[roomId] == true
			setPips(row, 0, 0)
			if owned then
				row.Note.Text = roomGifts(room)
				setRowState(row, "Owned")
				style(row.Buy, "Done", "✅ Built")
			elseif room.Season == "Winter" and not state.IsWinter then
				row.Note.Text = "❄️ Winter only"
				setRowState(row, "Locked")
				style(row.Buy, "Locked", "❄️ Soon")
			elseif (room.Level or 1) > (state.Level or 1) then
				-- Same order as the server (Logic/Progress.canBuyRoom): the level before the ⭐ gate. Grey and
				-- locked, but tappable: it opens the Hospital tab.
				row.Note.Text = "🔒 🏥 Lv " .. room.Level
				setRowState(row, "Locked")
				style(row.Buy, "Poor", "🏥 Lv " .. room.Level)
			elseif stars < room.StarsNeeded then
				row.Note.Text = "⭐ " .. stars .. " / " .. room.StarsNeeded
				setRowState(row, "Locked")
				style(row.Buy, "Locked", "⭐ " .. room.StarsNeeded) -- the 🔒 is the button's badge
			else
				row.Note.Text = roomGifts(room)
				setRowState(row, "Open")
				style(
					row.Buy,
					if (state.Cash or 0) >= room.Price then "Buy" else "Poor",
					"💰 " .. Hud.format(room.Price)
				)
			end
		end
	end

	--------------------------------------------------------------------------------------------------------------
	-- Decor, and placing it
	--------------------------------------------------------------------------------------------------------------
	local placeView = Instance.new("Frame")
	placeView.Name = "PlaceMode"
	placeView.BackgroundColor3 = Theme.Colors.Paper
	placeView.BorderSizePixel = 0
	placeView.Size = UDim2.fromScale(1, 1)
	placeView.Visible = false
	placeView.ZIndex = 5
	placeView.Parent = pagesArea

	local backButton = Kit.button({
		Name = "Back",
		Kind = "Secondary",
		Text = "⬅",
		TextSize = Theme.TextSize.Title,
		Size = UDim2.fromOffset(Theme.Size.ButtonHeight, Theme.Size.ButtonHeight),
		ZIndex = 5,
		Parent = placeView,
	})
	local placeTitle = Kit.label({
		Name = "Title",
		Text = "",
		TextScaled = true,
		Outlined = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(Theme.Size.ButtonHeight + 10, 8),
		Size = UDim2.new(1, -(Theme.Size.ButtonHeight * 2 + 30), 0, 40),
		ZIndex = 5,
		Parent = placeView,
	})
	textLimit(placeTitle, Theme.TextSize.Title)
	local storeButton = Kit.button({
		Name = "PutAway",
		Kind = "Quiet",
		Text = "📦",
		TextSize = Theme.TextSize.Title,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(Theme.Size.ButtonHeight + 12, Theme.Size.ButtonHeight),
		ZIndex = 5,
		Parent = placeView,
	})
	local slotGrid = Instance.new("ScrollingFrame")
	slotGrid.Name = "Slots"
	slotGrid.BackgroundTransparency = 1
	slotGrid.BorderSizePixel = 0
	slotGrid.Position = UDim2.fromOffset(0, Theme.Size.ButtonHeight + 10)
	slotGrid.Size = UDim2.new(1, 0, 1, -(Theme.Size.ButtonHeight + 10))
	slotGrid.CanvasSize = UDim2.new()
	slotGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	slotGrid.ScrollBarThickness = 8
	slotGrid.ScrollBarImageColor3 = Theme.Colors.Stroke
	slotGrid.Selectable = false
	slotGrid.ZIndex = 5
	slotGrid.Parent = placeView
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(96, 96)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = slotGrid
	local gridPad = Instance.new("UIPadding")
	gridPad.PaddingTop = UDim.new(0, 6)
	gridPad.PaddingLeft = UDim.new(0, 6)
	gridPad.Parent = slotGrid
	local emptyNote = Kit.label({
		Name = "Empty",
		Text = "",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0, 40),
		ZIndex = 6,
		Visible = false,
		Parent = placeView,
	})

	local placing: string? = nil -- the DecorId being placed

	local function placedSlotOf(state: Types.Snapshot, decorId: string): string?
		for key, placed in (state.Decor and state.Decor.Placed) or {} do
			if placed == decorId then
				return key
			end
		end
		return nil
	end

	local function exitPlace()
		placing = nil
		placeView.Visible = false
		modal.Focus = tabButtons[current]
	end

	local function renderPlace(state: Types.Snapshot)
		local decorId = placing
		if not decorId then
			return
		end
		local decor = data.Decor[decorId]
		placeTitle.Text = decor.Icon .. " Pick a spot!"
		storeButton.Visible = placedSlotOf(state, decorId) ~= nil

		for _, child in slotGrid:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		local slots = if state.PlotIndex ~= nil then Hud.decorSlots(data, state) else {}
		emptyNote.Visible = #slots == 0
		emptyNote.Text = if state.PlotIndex == nil then "🏠 No clinic yet!" else "🏠 Buy a room first!"

		local first: GuiObject? = nil
		for index, slot in slots do
			local room = data.Rooms[slot.RoomId]
			local here = slot.Placed and rawget(data.Decor, slot.Placed)
			local mine = slot.Placed == decorId
			-- An empty spot is a bright lime "put it here"; where it is now is cyan; a spot with other decor (a
			-- swap) stays a white card.
			local button = Kit.iconButton({
				Name = slot.Key,
				Kind = if mine then "Cyan" elseif not slot.Placed then "Good" else "Card",
				Icon = if here then here.Icon else "➕",
				Caption = room.Icon .. " " .. slot.N,
				LayoutOrder = if slot.Placed then 100 + index else index, -- empty spots first
				ZIndex = 5,
				Parent = slotGrid,
			})
			if mine then
				button.Interactable = false
			end
			button.Activated:Connect(function()
				if busy or placing ~= decorId then
					return
				end
				if request(button, ctx.Remotes.PlaceDecor, slot.Key, decorId) then
					ctx.fire("DecorPlaced", slot.Key, decorId)
					exitPlace()
					modal.close() -- show it: the decor appears in the world
				end
			end)
			if not first and not mine then
				first = button
			end
		end
		modal.Focus = first or backButton
	end

	local function enterPlace(decorId: string)
		placing = decorId
		placeView.Visible = true
		renderPlace(ctx.State)
		if usesDirectionalFocus() and modal.Focus then
			GuiService.SelectedObject = modal.Focus
		end
	end

	backButton.Activated:Connect(exitPlace)
	storeButton.Activated:Connect(function()
		local decorId = placing
		local key = decorId and placedSlotOf(ctx.State, decorId)
		if not key or busy then
			return
		end
		if request(storeButton, ctx.Remotes.PlaceDecor, key, nil) then
			ctx.fire("DecorPlaced", key, nil)
			exitPlace()
		end
	end)

	local decorRows: { [string]: Row } = {}
	for index, decorId in data.Decor.Order do
		local decor = data.Decor[decorId]
		local row = makeRow(pages.Decor, index, decor.Icon, decor.Name)
		row.Buy.Activated:Connect(function()
			local state = ctx.State
			local owned = state.Decor and state.Decor.Owned and state.Decor.Owned[decorId] == true
			if owned then
				enterPlace(decorId)
				return
			end
			local price = decor.Price
			if not price then
				return
			end
			if (state.Cash or 0) < price then
				needMore(row.Buy, price)
				return
			end
			if request(row.Buy, ctx.Remotes.Purchase, "Decor", decorId) then
				ctx.fire("Purchased", "Decor", decorId)
				Hud.pop(row.Frame, 1.05)
				Kit.bump(row.Tile)
				enterPlace(decorId) -- straight to "where does it go?"
			end
		end)
		decorRows[decorId] = row
	end

	local function refreshDecor(state: Types.Snapshot)
		local owned = (state.Decor and state.Decor.Owned) or {}
		for decorId, row in decorRows do
			local decor = data.Decor[decorId]
			setPips(row, 0, 0)
			if owned[decorId] == true then
				local placed = placedSlotOf(state, decorId) ~= nil
				row.Note.Text = if placed then "📍 In your clinic" else "📦 In storage"
				setRowState(row, "Owned")
				style(row.Buy, "Place", "📍 Place")
			elseif decor.Price then
				row.Note.Text = ""
				setRowState(row, "Open")
				style(
					row.Buy,
					if (state.Cash or 0) >= decor.Price then "Buy" else "Poor",
					"💰 " .. Hud.format(decor.Price)
				)
			else
				row.Note.Text = EARNED_HOW[decor.EarnedBy or ""] or "🏆 Earned"
				setRowState(row, "Locked")
				style(row.Buy, "Locked", "🏆")
			end
			-- Owned first, then what you can buy, then what you earn.
			row.Frame.LayoutOrder = (if owned[decorId] == true then 0 elseif decor.Price then 100 else 200)
				+ (table.find(data.Decor.Order, decorId) or 0)
		end
	end

	--------------------------------------------------------------------------------------------------------------
	-- Hospital (depth update): your level, the ladder to the Mega Hospital, and the next level's cost and unlocks
	--------------------------------------------------------------------------------------------------------------
	local levels = data.Levels
	local maxLevel = LevelsLogic.max(levels)

	-- The "now" card: a candy card with the level's icon, its name, the five-step ladder and what it gives you.
	local nowCard = card(pages.Hospital, "Now", 1, Kit.lighten(HOSPITAL, 0.08))
	nowCard.AutomaticSize = Enum.AutomaticSize.None
	nowCard.Size = UDim2.new(1, 0, 0, 150)
	Palette.candyGradient(nowCard)
	local nowTile, nowIcon = iconTile(nowCard, "Tile", 80, Theme.Colors.Paper, "")
	nowTile.Position = UDim2.fromOffset(12, 12)
	local nowTitle = Kit.label({
		Name = "Title",
		Text = "",
		TextScaled = true,
		Outlined = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(104, 12),
		Size = UDim2.new(1, -116, 0, 36),
		Parent = nowCard,
	})
	textLimit(nowTitle, Theme.TextSize.Title)
	local ladder = Instance.new("Frame")
	ladder.Name = "Ladder"
	ladder.BackgroundTransparency = 1
	ladder.Position = UDim2.fromOffset(104, 54)
	ladder.Size = UDim2.new(1, -116, 0, LADDER_TILE)
	ladder.Parent = nowCard
	local ladderList = Kit.list(ladder, Enum.FillDirection.Horizontal, 6)
	ladderList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local steps: { { Tile: Frame, Icon: TextLabel } } = {}
	for level = 1, maxLevel do
		local tile, icon = iconTile(ladder, "Step" .. level, LADDER_TILE, Theme.Colors.Paper, levels[level].Icon)
		tile.LayoutOrder = level
		steps[level] = { Tile = tile, Icon = icon }
	end
	local nowStats = Kit.label({
		Name = "Stats",
		Text = "",
		TextScaled = true,
		Outlined = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(12, 104),
		Size = UDim2.new(1, -24, 0, 34),
		Parent = nowCard,
	})
	textLimit(nowStats, Theme.TextSize.Body)

	-- The "next" card: the next level, its unlock chips, what it needs, and Level up.
	local nextCard = card(pages.Hospital, "Next", 2, Theme.Colors.Paper)
	Kit.pad(nextCard, 12)
	local nextList = Kit.list(nextCard, Enum.FillDirection.Vertical, 10)
	nextList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	nextList.VerticalAlignment = Enum.VerticalAlignment.Top

	local nextHead = Instance.new("Frame")
	nextHead.Name = "Head"
	nextHead.LayoutOrder = 1
	nextHead.BackgroundTransparency = 1
	nextHead.Size = UDim2.new(1, 0, 0, 60)
	nextHead.Parent = nextCard
	local nextTile, nextIcon = iconTile(nextHead, "Tile", 60, HOSPITAL, "")
	local nextTitle = Kit.label({
		Name = "Title",
		Text = "",
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(72, 0),
		Size = UDim2.new(1, -72, 1, 0),
		Parent = nextHead,
	})
	textLimit(nextTitle, Theme.TextSize.Title)

	local chips = Instance.new("Frame")
	chips.Name = "Chips"
	chips.LayoutOrder = 2
	chips.BackgroundTransparency = 1
	chips.Size = UDim2.fromScale(1, 0)
	chips.AutomaticSize = Enum.AutomaticSize.Y
	chips.Parent = nextCard
	local chipList = Kit.list(chips, Enum.FillDirection.Horizontal, 8)
	chipList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	chipList.VerticalAlignment = Enum.VerticalAlignment.Top
	chipList.Wraps = true

	local foot = Instance.new("Frame")
	foot.Name = "Foot"
	foot.LayoutOrder = 3
	foot.BackgroundTransparency = 1
	foot.Size = UDim2.new(1, 0, 0, Theme.Size.ButtonHeight)
	foot.Parent = nextCard
	local cost = Kit.label({
		Name = "Cost",
		Text = "",
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -(LEVEL_BUTTON_WIDTH + 12), 1, 0),
		Parent = foot,
	})
	textLimit(cost, Theme.TextSize.Body)
	local levelUp = Kit.button({
		Name = "LevelUp",
		Kind = "Good",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(LEVEL_BUTTON_WIDTH, Theme.Size.ButtonHeight),
		TextSize = Theme.TextSize.Body,
		TextScaled = true,
		Parent = foot,
	})
	local levelLimit = Instance.new("UITextSizeConstraint")
	levelLimit.MaxTextSize = Theme.TextSize.Body
	levelLimit.MinTextSize = Theme.TextSize.Small
	levelLimit.Parent = levelUp
	Kit.shine(levelUp)
	lockBadge(levelUp)
	levelButton = levelUp

	local shownChipsFor = -1 -- the level whose chips are on the card

	local function starsText(n: number): string
		return "⭐ " .. Hud.format(n)
	end

	local function refreshHospital(state: Types.Snapshot)
		local level = LevelsLogic.clamp(levels, state.Level)
		local row = LevelsLogic.row(levels, level)
		nowIcon.Text = row.Icon
		nowTitle.Text = "Lv " .. level .. " · " .. row.Name
		nowStats.Text = ("👩‍⚕️ %d   🛏️ %d   🧍 %d   🧪 %d"):format(
			row.Slots,
			row.Beds,
			row.Queue,
			row.RecipeCap
		)
		for index, step in steps do
			local done = index <= level
			step.Tile.BackgroundColor3 = if index == level
				then Theme.Colors.Cash
				elseif done then Kit.lighten(Theme.Colors.Good, 0.08)
				else Theme.Colors.Disabled
			step.Icon.TextTransparency = if done then 0 else 0.55
		end

		local nextRow = LevelsLogic.nextRow(levels, level)
		local nextLevel = level + 1
		if shownChipsFor ~= nextLevel then
			shownChipsFor = nextLevel
			for _, child in chips:GetChildren() do
				if child:IsA("Frame") then
					child:Destroy()
				end
			end
			if nextRow then
				for index, text in nextRow.Unlocks do
					chip(chips, index, text)
				end
			end
		end
		chips.Visible = nextRow ~= nil
		foot.Visible = nextRow ~= nil
		if not nextRow then
			nextIcon.Text = "🏆"
			nextTitle.Text = "Max level!"
			nextTile.BackgroundColor3 = Kit.lighten(Theme.Colors.Cash, 0.08)
			return
		end
		nextIcon.Text = nextRow.Icon
		nextTitle.Text = "⬆️ Lv " .. nextLevel .. " · " .. nextRow.Name
		nextTile.BackgroundColor3 = Kit.lighten(HOSPITAL, 0.08)

		local have = state.Stars or 0
		local starText = if have >= nextRow.Stars
			then starsText(nextRow.Stars) .. " ✅"
			else starsText(have) .. " / " .. Hud.format(nextRow.Stars)
		cost.Text = starText .. "   💰 " .. Hud.format(nextRow.Cash)
		if state.PlotIndex == nil then
			style(levelUp, "Locked", "🏠")
		elseif have < nextRow.Stars then
			style(levelUp, "Locked", starsText(nextRow.Stars)) -- ⭐ is a gate: keep curing
		elseif (state.Cash or 0) < nextRow.Cash then
			style(levelUp, "Poor", "💰 " .. Hud.format(nextRow.Cash))
		else
			style(levelUp, "Buy", "⬆️ Level up!")
		end
	end

	levelUp.Activated:Connect(function()
		local state = ctx.State
		local level = LevelsLogic.clamp(levels, state.Level)
		local nextRow = LevelsLogic.nextRow(levels, level)
		if not nextRow or busy then
			return
		end
		if state.PlotIndex == nil then
			ctx.toast("🏠 You need a clinic first!")
			Hud.shake(levelUp)
			return
		end
		if (state.Cash or 0) < nextRow.Cash then
			needMore(levelUp, nextRow.Cash)
			return
		end
		if send(levelUp, true, ctx.Remotes.LevelUp) then
			ctx.fire("Purchased", "Level", tostring(level + 1))
			Hud.pop(nowCard, 1.05)
			Kit.bump(nowTile)
			modal.close() -- the Celebrate screen, then the building growing behind it
		end
	end)

	-- The tab's dot: a room you can buy right now (its level too), or the next level is ready.
	local function roomReady(state: Types.Snapshot): boolean
		if state.PlotIndex == nil then
			return false
		end
		for _, roomId in data.Rooms.Order do
			local room = data.Rooms[roomId]
			if room.Price > 0 and ProgressLogic.canBuyRoom(state, room, roomId, state.IsWinter == true) then
				return true
			end
		end
		return false
	end

	local function levelReady(state: Types.Snapshot): boolean
		return state.PlotIndex ~= nil and (LevelsLogic.canLevelUp(state, levels))
	end

	--------------------------------------------------------------------------------------------------------------
	-- Keeping it current
	--------------------------------------------------------------------------------------------------------------
	refresh = function(state: Types.Snapshot)
		if busy then
			return -- the pressed button shows ⏳ until the server answers
		end
		refreshUpgrades(state)
		refreshRooms(state)
		refreshDecor(state)
		refreshHospital(state)
		local news = Hud.shopNews(data, state)
		Kit.setDot(tabButtons.Rooms, roomReady(state))
		Kit.setDot(tabButtons.Decor, news.Decor)
		Kit.setDot(tabButtons.Hospital, levelReady(state))
		if placing and placeView.Visible then
			renderPlace(state)
		end
	end
	ctx.onState(refresh)

	ctx.on("Open", function(name: any, tab: any)
		if name ~= "Shop" then
			return
		end
		exitPlace()
		selectTab(if type(tab) == "string" and pages[tab] then tab else current)
		refresh(ctx.State)
		modal.open()
	end)

	selectTab(current)
end

return Shop
