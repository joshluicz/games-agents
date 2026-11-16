--!strict
-- BookPanel (build plan Task 6): the Patient Book. One tab per wing (Data/Wings) plus 💌 for the regulars.
--   init(ctx)   opens on ctx.fire("Open", "Book")
-- A wing page shows its set progress, the set reward and a card per patient: not met yet = a dark silhouette
-- with "?"; met = a face, name, ailment → station icons, times cured and variant stickers (✨ 🧊). Cards for
-- pages stamped since you last looked carry a 🆕 ribbon. The 💌 page shows each regular's story as 5 hearts.
-- Reads only the Snapshot (Book, Story, Stars) and the Cured remote (NewPage). Fires "BookNew" (count) for the
-- HUD's 📖 dot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local BookPanel = {}

local TAB_WIDTH = Theme.Size.IconButton
local MIN_CARD = 118
local CARD_GAP = 10
local FRIENDS = "Friends"

type Card = {
	Frame: Frame,
	Face: Frame,
	Name: TextLabel,
	Info: TextLabel,
	Stickers: TextLabel,
	Ribbon: TextLabel,
	Shown: string, -- "seen" | "unseen": which portrait is drawn now
}

type Page = {
	Frame: Frame,
	Tab: TextButton,
	Progress: TextLabel?,
	Fill: Frame?,
	Reward: TextLabel?,
	Cards: { [string]: Card },
	Ids: { string },
}

local function textLimit(label: TextLabel, max: number)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = max
	limit.MinTextSize = 10
	limit.Parent = label
end

local function patientsOf(data: any, wingId: string): { string }
	local ids = {}
	for _, patientId in data.Patients.Order do
		if data.Patients[patientId].Wing == wingId then
			table.insert(ids, patientId)
		end
	end
	return ids
end

local function curedCount(state: Types.Snapshot, id: string): number
	local entry = state.Book and state.Book[id]
	return if entry and type(entry.Cured) == "number" then entry.Cured else 0
end

local function newCard(parent: Instance, order: number): Card
	local frame = Instance.new("Frame")
	frame.Name = "Card" .. order
	frame.LayoutOrder = order
	frame.BackgroundColor3 = Theme.Colors.Card
	frame.BorderSizePixel = 0
	Kit.corner(frame, 16)
	local stroke = Kit.stroke(frame, Theme.Colors.Stroke, 2)
	stroke.Transparency = 0.5

	local face = Instance.new("Frame")
	face.Name = "Face"
	face.BackgroundColor3 = Theme.Colors.Paper
	face.BorderSizePixel = 0
	face.AnchorPoint = Vector2.new(0.5, 0)
	face.Position = UDim2.new(0.5, 0, 0, 8)
	face.Size = UDim2.new(1, -16, 0.58, -8)
	Kit.corner(face, 12)
	face.Parent = frame

	local name = Kit.label({
		Name = "PatientName",
		Text = "",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.6),
		Size = UDim2.new(1, -10, 0.17, 0),
		Parent = frame,
	})
	textLimit(name, 20)
	local info = Kit.label({
		Name = "Info",
		Text = "",
		TextScaled = true,
		TextColor3 = Theme.Colors.InkSoft,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.78),
		Size = UDim2.new(1, -10, 0.18, 0),
		Parent = frame,
	})
	textLimit(info, 22)
	local stickers = Kit.label({
		Name = "Stickers",
		Text = "",
		TextScaled = true,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(52, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 3,
		Parent = frame,
	})
	local ribbon = Kit.label({
		Name = "New",
		Text = "🆕",
		TextScaled = true,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.fromOffset(28, 28),
		Visible = false,
		ZIndex = 3,
		Parent = frame,
	})
	frame.Parent = parent
	return {
		Frame = frame,
		Face = face,
		Name = name,
		Info = info,
		Stickers = stickers,
		Ribbon = ribbon,
		Shown = "",
	}
end

local function setFace(card: Card, look: any, dark: boolean)
	local wanted = if dark then "unseen" else "seen"
	if card.Shown == wanted then
		return
	end
	card.Shown = wanted
	card.Face:ClearAllChildren()
	Kit.corner(card.Face, 12)
	local portrait = Hud.portrait(look, dark)
	portrait.AnchorPoint = Vector2.new(0.5, 0.5)
	portrait.Position = UDim2.fromScale(0.5, 0.5)
	portrait.Size = UDim2.fromScale(0.95, 0.95)
	portrait.Parent = card.Face
	card.Face.BackgroundColor3 = if dark then Color3.fromRGB(226, 218, 230) else Theme.Colors.Paper
end

local function grid(parent: Instance): (ScrollingFrame, UIGridLayout)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Cards"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = Theme.Colors.Stroke
	scroll.Selectable = false
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP)
	layout.CellSize = UDim2.fromOffset(MIN_CARD, MIN_CARD * 1.3)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 3) -- scrolling frames clip: keep the cards' outlines whole
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = scroll
	scroll.Parent = parent

	-- As many columns as fit, cards stretched to fill the row (2 on a phone, up to 5 on a big screen).
	local function fit()
		local width = scroll.AbsoluteSize.X - 15 -- minus the left and right padding
		if width <= 0 then
			return
		end
		local columns = math.clamp(math.floor((width + CARD_GAP) / (MIN_CARD + CARD_GAP)), 2, 5)
		local cell = math.floor((width - CARD_GAP * (columns - 1)) / columns)
		layout.CellSize = UDim2.fromOffset(cell, math.min(math.floor(cell * 1.3), 190))
	end
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	return scroll, layout
end

function BookPanel.init(ctx: Types.Ctx)
	local data = ctx.Data :: any
	local player = ctx.Player
	local modal = Hud.modal(ctx, {
		Name = "Book",
		Title = "📖 Book",
		MaxSize = Vector2.new(760, 600),
	})
	local title = modal.Panel:FindFirstChild("Title") :: TextLabel?

	local tabColumn = Instance.new("ScrollingFrame")
	tabColumn.Name = "Tabs"
	tabColumn.BackgroundTransparency = 1
	tabColumn.BorderSizePixel = 0
	tabColumn.Size = UDim2.new(0, TAB_WIDTH + 10, 1, 0) -- room for the selected tab's thick outline
	tabColumn.CanvasSize = UDim2.new()
	tabColumn.AutomaticCanvasSize = Enum.AutomaticSize.Y
	tabColumn.ScrollBarThickness = 0
	tabColumn.Selectable = false
	tabColumn.Parent = modal.Body
	local tabList = Kit.list(tabColumn, Enum.FillDirection.Vertical, 8)
	tabList.VerticalAlignment = Enum.VerticalAlignment.Top
	local tabPad = Instance.new("UIPadding")
	tabPad.PaddingTop = UDim.new(0, 5)
	tabPad.PaddingBottom = UDim.new(0, 5)
	tabPad.Parent = tabColumn

	local pagesArea = Instance.new("Frame")
	pagesArea.Name = "Pages"
	pagesArea.BackgroundTransparency = 1
	pagesArea.Position = UDim2.fromOffset(TAB_WIDTH + 10 + Theme.Size.Gap, 0)
	pagesArea.Size = UDim2.new(1, -(TAB_WIDTH + 10 + Theme.Size.Gap), 1, 0)
	pagesArea.Parent = modal.Body

	local pages: { [string]: Page } = {}
	local pageOrder: { string } = {}
	local current = ""

	local function selectPage(id: string)
		if not pages[id] then
			return
		end
		current = id
		for pageId, p in pages do
			local selected = pageId == id
			p.Frame.Visible = selected
			p.Tab.BackgroundColor3 = if selected then Theme.Colors.Card else Theme.Colors.Quiet
			local stroke = p.Tab:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if selected then Theme.Colors.Secondary else Kit.shade(Theme.Colors.Quiet, 0.25)
				stroke.Thickness = if selected then 4 else Theme.Size.Stroke
			end
		end
		modal.Focus = pages[id].Tab
	end

	local function makeTab(id: string, icon: string, order: number): TextButton
		local tab = Kit.iconButton({
			Name = "Tab_" .. id,
			Icon = icon,
			Caption = "0/0",
			LayoutOrder = order,
			Size = UDim2.fromOffset(TAB_WIDTH, TAB_WIDTH),
			Parent = tabColumn,
		})
		tab.Activated:Connect(function()
			selectPage(id)
		end)
		return tab
	end

	-- The header of a page: icon and name, a progress bar, and the reward it leads to.
	local function header(
		parent: Instance,
		icon: string,
		text: string,
		rewardIcon: string?
	): (TextLabel, Frame, TextLabel?)
		local frame = Instance.new("Frame")
		frame.Name = "Header"
		frame.BackgroundColor3 = Theme.Colors.Card
		frame.BorderSizePixel = 0
		frame.Size = UDim2.new(1, -12, 0, 64)
		Kit.corner(frame, 16)
		local stroke = Kit.stroke(frame, Theme.Colors.Stroke, 2)
		stroke.Transparency = 0.5
		Kit.label({
			Name = "Icon",
			Text = icon,
			TextScaled = true,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Size = UDim2.fromOffset(46, 46),
			Parent = frame,
		})
		local nameLabel = Kit.label({
			Name = "WingName",
			Text = text,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(62, 6),
			Size = UDim2.new(1, -62 - 70, 0, 26),
			Parent = frame,
		})
		textLimit(nameLabel, 22)
		local track = Instance.new("Frame")
		track.Name = "Track"
		track.BackgroundColor3 = Theme.Colors.Quiet
		track.BorderSizePixel = 0
		track.Position = UDim2.fromOffset(62, 38)
		track.Size = UDim2.new(1, -62 - 70 - 56, 0, 16)
		Kit.corner(track, 8)
		track.Parent = frame
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BackgroundColor3 = Theme.Colors.Good
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(0, 1)
		Kit.corner(fill, 8)
		fill.Parent = track
		local count = Kit.label({
			Name = "Count",
			Text = "0/0",
			TextScaled = true,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -74, 0, 34),
			Size = UDim2.fromOffset(50, 24),
			Parent = frame,
		})
		textLimit(count, 20)
		local reward: TextLabel? = nil
		if rewardIcon then
			local badge = Kit.label({
				Name = "Reward",
				Text = rewardIcon,
				TextScaled = true,
				BackgroundColor3 = Theme.Colors.Paper,
				BackgroundTransparency = 0,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(52, 52),
				Parent = frame,
			})
			Kit.corner(badge, 26)
			Kit.stroke(badge, Theme.Colors.Star, 3)
			Kit.pad(badge, 6)
			reward = badge
		end
		frame.Parent = parent
		return count, fill, reward
	end

	local function pageFrame(id: string): (Frame, ScrollingFrame)
		local frame = Instance.new("Frame")
		frame.Name = id
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.fromScale(1, 1)
		frame.Visible = false
		frame.Parent = pagesArea
		local scroll = grid(frame)
		scroll.Position = UDim2.fromOffset(0, 74)
		scroll.Size = UDim2.new(1, 0, 1, -74)
		return frame, scroll
	end

	-- Wing pages
	for index, wingId in data.Wings.Order do
		local wing = data.Wings[wingId]
		local reward = data.Decor[wing.SetReward]
		local frame, scroll = pageFrame(wingId)
		local count, fill, rewardBadge = header(frame, wing.Icon, wing.Name, reward and reward.Icon)
		local ids = patientsOf(data, wingId)
		local cards: { [string]: Card } = {}
		for order, patientId in ids do
			cards[patientId] = newCard(scroll, order)
		end
		pages[wingId] = {
			Frame = frame,
			Tab = makeTab(wingId, wing.Icon, index),
			Progress = count,
			Fill = fill,
			Reward = rewardBadge,
			Cards = cards,
			Ids = ids,
		}
		table.insert(pageOrder, wingId)
	end

	-- The regulars
	do
		local frame, scroll = pageFrame(FRIENDS)
		local count, fill = header(frame, "💌", "Story friends", nil)
		local cards: { [string]: Card } = {}
		local ids = {}
		for order, regularId in data.Regulars.Order do
			cards[regularId] = newCard(scroll, order)
			table.insert(ids, regularId)
		end
		pages[FRIENDS] = {
			Frame = frame,
			Tab = makeTab(FRIENDS, "💌", #pageOrder + 1),
			Progress = count,
			Fill = fill,
			Reward = nil,
			Cards = cards,
			Ids = ids,
		}
		table.insert(pageOrder, FRIENDS)
	end
	local tabs = {}
	for _, pageId in pageOrder do
		table.insert(tabs, pages[pageId].Tab)
	end
	Hud.fitTabs(tabColumn, tabs, 8)

	--------------------------------------------------------------------------------------------------------------
	-- New pages since you last looked (from the Cured remote: exact, and only the helper's own stamps)
	--------------------------------------------------------------------------------------------------------------
	local fresh: { [string]: boolean } = {}
	local function freshCount(): number
		local n = 0
		for _ in fresh do
			n += 1
		end
		return n
	end
	ctx.Remotes.Cured.OnClientEvent:Connect(function(info: any)
		if type(info) ~= "table" or info.NewPage ~= true or type(info.PatientId) ~= "string" then
			return
		end
		if info.Helper ~= nil and info.Helper ~= player.UserId then
			return
		end
		if rawget(data.Patients, info.PatientId) or rawget(data.Regulars, info.PatientId) then
			fresh[info.PatientId] = true
			ctx.fire("BookNew", freshCount())
		end
	end)

	--------------------------------------------------------------------------------------------------------------
	-- Drawing from the Snapshot
	--------------------------------------------------------------------------------------------------------------
	local function setProgress(p: Page, done: number, total: number)
		if p.Progress then
			p.Progress.Text = done .. "/" .. total
		end
		if p.Fill then
			p.Fill.Size = UDim2.fromScale(if total > 0 then done / total else 0, 1)
		end
		local caption = p.Tab:FindFirstChild("Caption")
		if caption and caption:IsA("TextLabel") then
			caption.Text = if total > 0 and done >= total then "✅" else done .. "/" .. total
		end
	end

	local function renderWing(wingId: string, state: Types.Snapshot): (number, number)
		local p = pages[wingId]
		local met = 0
		for _, patientId in p.Ids do
			local patient = data.Patients[patientId]
			local card = p.Cards[patientId]
			local cured = curedCount(state, patientId)
			local seen = cured > 0
			if seen then
				met += 1
			end
			setFace(card, patient.Look, not seen)
			card.Ribbon.Visible = fresh[patientId] == true
			if seen then
				local ailment = data.Ailments[patient.Ailment]
				local station = ailment and data.Stations[ailment.Station]
				card.Name.Text = patient.Name
				card.Info.Text = (if ailment then ailment.Icon else "")
					.. "→"
					.. (if station then station.Icon else "")
					.. "  ×"
					.. cured
				local stickers = {}
				local variants = (state.Book[patientId] or {}).Variants or {}
				for _, variantId in data.Variants.Order do
					if variants[variantId] then
						table.insert(stickers, data.Variants[variantId].Icon)
					end
				end
				card.Stickers.Text = table.concat(stickers, "")
			else
				card.Name.Text = "???"
				card.Info.Text = ""
				card.Stickers.Text = ""
			end
		end
		setProgress(p, met, #p.Ids)
		if p.Reward then
			local complete = #p.Ids > 0 and met >= #p.Ids
			p.Reward.TextTransparency = if complete then 0 else 0.55
			local stroke = p.Reward:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if complete then Theme.Colors.Good else Theme.Colors.Star
			end
		end
		return met, #p.Ids
	end

	local function renderFriends(state: Types.Snapshot)
		local p = pages[FRIENDS]
		local stars = state.Stars or 0
		local finished = 0
		for _, regularId in p.Ids do
			local regular = data.Regulars[regularId]
			local card = p.Cards[regularId]
			local entry = state.Story and state.Story[regularId]
			local beat = if entry and type(entry.Beat) == "number" then entry.Beat else 0
			local total = #regular.Beats
			local unlocked = stars >= regular.UnlockStars
			local met = beat > 0
			if beat >= total then
				finished += 1
			end
			setFace(card, regular.Look, not met)
			card.Ribbon.Visible = fresh[regularId] == true
			if met then
				card.Name.Text = regular.Name
				card.Info.Text = string.rep("💛", math.min(beat, total))
					.. string.rep("🤍", math.max(0, total - beat))
				local reward = data.Decor[regular.Reward] or data.Rooms[regular.Reward]
				card.Stickers.Text = if beat >= total and reward
					then "🎁" .. reward.Icon
					else regular.Beats[math.min(beat, total)].Emote
			elseif unlocked then
				card.Name.Text = "???"
				card.Info.Text = "👀 Coming soon"
				card.Stickers.Text = ""
			else
				card.Name.Text = "???"
				card.Info.Text = "🔒 ⭐" .. regular.UnlockStars
				card.Stickers.Text = ""
			end
		end
		setProgress(p, finished, #p.Ids)
	end

	local function render(state: Types.Snapshot)
		local met, total = 0, 0
		for _, wingId in data.Wings.Order do
			local m, t = renderWing(wingId, state)
			met += m
			total += t
		end
		renderFriends(state)
		if title then
			title.Text = "📖 Book  " .. met .. "/" .. total
		end
	end
	ctx.onState(render)

	ctx.on("Open", function(name: any)
		if name ~= "Book" then
			return
		end
		-- Open on the page with something new, else where you were (or the first wing).
		local target = if current ~= "" then current else pageOrder[1]
		for _, pageId in pageOrder do
			for id in fresh do
				if pages[pageId].Cards[id] then
					target = pageId
				end
			end
		end
		selectPage(target)
		render(ctx.State)
		modal.open()
		for id in fresh do
			for _, p in pages do
				local card = p.Cards[id]
				if card then
					Hud.pop(card.Frame, 1.12)
				end
			end
		end
	end)

	-- Closing the Book counts the new pages as seen.
	ctx.on("ModalClosed", function(name: any)
		if name == "Book" and next(fresh) ~= nil then
			table.clear(fresh)
			ctx.fire("BookNew", 0)
			render(ctx.State)
		end
	end)

	selectPage(pageOrder[1])
end

return BookPanel
