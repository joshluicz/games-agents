--!strict
-- Shop (build plan Task 6): spend cash on ⚡ Upgrades, 🏠 Rooms and 🌸 Decor, and place decor in your rooms.
--   init(ctx)   opens on ctx.fire("Open", "Shop", tab?) with tab "Upgrades" | "Rooms" | "Decor"
-- Every price, lock and level shown here is read from the Snapshot and Shared/Data, for display only. Buying calls
-- Purchase(kind, id) and placing calls PlaceDecor(slotKey, decorId?); the server checks everything and answers
-- (ok, message), which is shown as a toast. Nothing changes on screen until the server's next Snapshot.
-- Bus: fires "Purchased" (kind, id) and "DecorPlaced" (slotKey, decorId?) after the server says yes.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Prices = require(Shared:WaitForChild("Logic"):WaitForChild("Prices"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Shop = {}

local TABS = {
	{ Id = "Upgrades", Icon = "⚡", Caption = "Upgrades" },
	{ Id = "Rooms", Icon = "🏠", Caption = "Rooms" },
	{ Id = "Decor", Icon = "🌸", Caption = "Decor" },
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
	Icon: TextLabel,
	Title: TextLabel,
	Pips: Frame,
	Note: TextLabel,
	Buy: TextButton,
}

type Style = { Color: Color3, Text: Color3, Active: boolean }
local STYLES: { [string]: Style } = {
	Buy = { Color = Theme.Colors.Primary, Text = Theme.Colors.OnColor, Active = true },
	Poor = { Color = Theme.Colors.Quiet, Text = Theme.Colors.InkSoft, Active = true }, -- still tappable: says why
	Done = { Color = Theme.Colors.Good, Text = Theme.Colors.OnColor, Active = false },
	Locked = { Color = Theme.Colors.Disabled, Text = Theme.Colors.Ink, Active = false },
	Place = { Color = Theme.Colors.Secondary, Text = Theme.Colors.OnColor, Active = true },
	Busy = { Color = Theme.Colors.Quiet, Text = Theme.Colors.Ink, Active = false },
}

local function style(button: TextButton, name: string, text: string)
	local s = STYLES[name] or STYLES.Buy
	button.Text = text
	button.BackgroundColor3 = s.Color
	button.TextColor3 = s.Text
	button.TextStrokeColor3 = Kit.shade(s.Color, 0.45)
	button.TextStrokeTransparency = if s.Text == Theme.Colors.OnColor then 0.55 else 1
	button.Interactable = s.Active
	button.AutoButtonColor = false
	button:SetAttribute("KitColor", s.Color)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Kit.shade(s.Color, 0.25)
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

local function makeRow(parent: Instance, order: number, icon: string, title: string): Row
	local frame = Instance.new("Frame")
	frame.Name = "Row" .. order
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	frame.BackgroundColor3 = Theme.Colors.Card
	frame.BorderSizePixel = 0
	Kit.corner(frame, 16)
	local stroke = Kit.stroke(frame, Theme.Colors.Stroke, 2)
	stroke.Transparency = 0.55

	local iconLabel = Kit.label({
		Name = "Icon",
		Text = icon,
		TextScaled = true,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(60, 60),
		Parent = frame,
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
	local pipList = Kit.list(pips, Enum.FillDirection.Horizontal, 4)
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
		Kind = "Primary",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(BUY_WIDTH, Theme.Size.ButtonHeight),
		TextSize = Theme.TextSize.Body,
		Parent = frame,
	})
	frame.Parent = parent
	return { Frame = frame, Icon = iconLabel, Title = titleLabel, Pips = pips, Note = note, Buy = buy }
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
		dot.Size = UDim2.fromOffset(14, 14)
		dot.BackgroundColor3 = if i <= level then Theme.Colors.Star else Theme.Colors.Quiet
		dot.BorderSizePixel = 0
		Kit.corner(dot, 7)
		local stroke = Kit.stroke(dot, Theme.Colors.Stroke, 1.5)
		stroke.Transparency = 0.5
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

function Shop.init(ctx: Types.Ctx)
	local data = ctx.Data :: any
	local modal = Hud.modal(ctx, {
		Name = "Shop",
		Title = "🛒 Shop",
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
	local pages: { [string]: ScrollingFrame } = {}
	local current = "Upgrades"

	local function selectTab(id: string)
		if not pages[id] then
			return
		end
		current = id
		for tabId, button in tabButtons do
			local selected = tabId == id
			button.BackgroundColor3 = if selected then Theme.Colors.Card else Theme.Colors.Quiet
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if selected then Theme.Colors.Primary else Kit.shade(Theme.Colors.Quiet, 0.25)
				stroke.Thickness = if selected then 4 else Theme.Size.Stroke
			end
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
		pages[tab.Id] = page(pagesArea, tab.Id)
	end
	Hud.fitTabs(tabColumn, { tabButtons.Upgrades, tabButtons.Rooms, tabButtons.Decor }, 8)

	--------------------------------------------------------------------------------------------------------------
	-- Asking the server
	--------------------------------------------------------------------------------------------------------------
	local busy = false
	local refresh: (state: Types.Snapshot) -> ()

	local function request(button: TextButton, remote: RemoteFunction, ...: any): boolean
		if busy then
			return false
		end
		busy = true
		local before = {
			Text = button.Text,
			BackgroundColor3 = button.BackgroundColor3,
			TextColor3 = button.TextColor3,
			Interactable = button.Interactable,
		}
		style(button, "Busy", "⏳")
		local ok, message = Hud.ask(remote, ...)
		busy = false
		-- Put the button back as it was; refresh restyles the rows from the newest Snapshot.
		button.Text = before.Text
		button.BackgroundColor3 = before.BackgroundColor3
		button.TextColor3 = before.TextColor3
		button.Interactable = before.Interactable
		if ok then
			ctx.toast(if message ~= "" then message else "🎉 Yay!")
			Hud.fly(button, "✨", nil, 6)
			Hud.sound("Chime")
		else
			ctx.toast(if message ~= "" then message else "Oops! Try again.")
			Hud.shake(button)
		end
		refresh(ctx.State)
		return ok
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
			end
		end)
		upgradeRows[upgradeId] = row
	end

	local function refreshUpgrades(state: Types.Snapshot)
		for upgradeId, row in upgradeRows do
			local upgrade = data.Upgrades[upgradeId]
			local level = (state.Upgrades or {})[upgradeId] or 0
			local max = #upgrade.Prices
			local price = Prices.upgradePrice(data.Upgrades, upgradeId, level)
			setPips(row, math.min(level, max), max)
			row.Note.Text = upgrade.Hint
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
				if (state.Cash or 0) < room.Price then
					needMore(row.Buy, room.Price)
					return
				end
				if request(row.Buy, ctx.Remotes.Purchase, "Room", roomId) then
					ctx.fire("Purchased", "Room", roomId)
					Hud.pop(row.Frame, 1.06)
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
				style(row.Buy, "Done", "✅ Built")
			elseif room.Season == "Winter" and not state.IsWinter then
				row.Note.Text = "❄️ Winter only"
				style(row.Buy, "Locked", "❄️ Soon")
			elseif stars < room.StarsNeeded then
				row.Note.Text = "⭐ " .. stars .. " / " .. room.StarsNeeded
				style(row.Buy, "Locked", "🔒 ⭐" .. room.StarsNeeded)
			else
				row.Note.Text = roomGifts(room)
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
		Kind = "Quiet",
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
			local button = Kit.iconButton({
				Name = slot.Key,
				Icon = if here then here.Icon else "➕",
				Caption = room.Icon .. " " .. slot.N,
				LayoutOrder = if slot.Placed then 100 + index else index, -- empty spots first
				ZIndex = 5,
				Parent = slotGrid,
			})
			if mine then
				button.BackgroundColor3 = Theme.Colors.Good
				button.Interactable = false
			elseif not slot.Placed then
				local stroke = button:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = Theme.Colors.Good
					stroke.Thickness = 4
				end
			else
				button.BackgroundColor3 = Theme.Colors.Quiet
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
				style(row.Buy, "Place", "📍 Place")
			elseif decor.Price then
				row.Note.Text = ""
				style(
					row.Buy,
					if (state.Cash or 0) >= decor.Price then "Buy" else "Poor",
					"💰 " .. Hud.format(decor.Price)
				)
			else
				row.Note.Text = EARNED_HOW[decor.EarnedBy or ""] or "🏆 Earned"
				style(row.Buy, "Locked", "🏆")
			end
			-- Owned first, then what you can buy, then what you earn.
			row.Frame.LayoutOrder = (if owned[decorId] == true then 0 elseif decor.Price then 100 else 200)
				+ (table.find(data.Decor.Order, decorId) or 0)
		end
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
		local news = Hud.shopNews(data, state)
		Kit.setDot(tabButtons.Rooms, news.Rooms)
		Kit.setDot(tabButtons.Decor, news.Decor)
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
