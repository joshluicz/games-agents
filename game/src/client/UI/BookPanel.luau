--!strict
-- BookPanel (build plan Task 6): the Patient Book. One tab per wing (Data/Wings) plus 💛 for the regulars.
--   init(ctx)   opens on ctx.fire("Open", "Book")
-- A wing page shows its set progress, the set reward and a card per patient: not met yet = a dark silhouette
-- with "???"; met = a face, name, "🩺 ×n" (times treated: a patient's case is rolled each visit from its wing's pool,
-- so the card shows none) and its variant sticker (one: ✨ or 🧊, with "+n" for the rest). Cards for pages stamped
-- since you last looked carry a flat NEW badge. The 💛 page shows each regular's story as "💛 3/5".
-- Reads only the Snapshot (Book, Story, Stars) and the Cured remote (NewPage). Fires "BookNew" (count) for the
-- HUD's 📖 dot.
-- The calm UI (docs/plan/2026-11-17-ui-direction.md §4 #10; Joshua, memory-20261117-007): the title in words
-- ("Book"), the header meta plain text ("6%": the share of every page met, rolling while it's open), Kit.card
-- cards with no line, the set's progress a Kit.bar (navy; gold when the set is done), one emoji per label and never
-- two side by side. R0 (memory-20261117-006): only the tabs with something in them (Gate.visible): the first wing,
-- then each wing once you've met one of its patients, and the regulars once one has visited. A wing's own colour
-- lives only on its tab's stripe and its page tile. A finished set's reward sits on turning rays (a reward moment).
-- Juice (depth update, design §4): opening the Book or a tab, the page slides in (the cards are simply there: a
-- list never pops card by card); the counts roll (Kit.countUp) while it's open; each new page's card bursts with
-- confetti when you open the Book on it; a set finished this session throws confetti from its reward badge the
-- first time you see it. Calm (Kit.reducedMotion()): all of it simply appears.
-- Progression v2 (build plan §C T8): a wing that comes with rebirths says so calmly on its page and its unmet cards
-- in words ("From branch 1" for the 🌻 Sunny wing; "From branch 2 · by air" for the Sky wing, whose patients only
-- come by air ambulance; "By air only" once your branch has it): no lock icon, no "hurry". A page stamped Golden
-- 🌟 (R3+) gets a gold card, and the 🌟 is its sticker. The rules are the pure GATE block (tests/Juice, tests/Book).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Modal = require(script.Parent.Modal)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local BookPanel = {}

local MIN_CARD = 118
local CARD_GAP = Theme.Space.PadCard
local FRIENDS = "Friends"
local FRIENDS_ICON = "💛" -- the regulars' page: their story is told in hearts (Art, not a chrome Door)
local HEADER_HEIGHT = 72
-- Each wing's own colour (Data/Wings ids): only its tab's stripe and its page tile. A wing added later takes the
-- next one from SPARE_COLORS.
local WING_COLORS: { [string]: Color3 } = {
	Starter = Theme.Colors.Collect,
	Bath = Theme.Colors.Cyan,
	Winter = Palette.Candy.Blue,
	Night = Theme.Colors.Night,
	[FRIENDS] = Theme.Colors.Pink,
}
local SPARE_COLORS = { Theme.Colors.Primary, Theme.Colors.Cash, Theme.Colors.Purple }
local UNSEEN_FACE = Kit.lighten(Theme.Colors.Locked, 0.6) -- a "???" silhouette's tile
local GOLDEN_CARD = Kit.lighten(Theme.Colors.Cash, 0.55) -- a Golden 🌟 page's card fill (no outline: R2)

type Card = {
	Frame: Frame,
	Color: Color3, -- its wing's colour
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
	Color: Color3,
	Progress: TextLabel?,
	SetBar: ((fraction: number, atMax: boolean?) -> ())?,
	Reward: TextLabel?, -- the reward's emoji
	Badge: Frame?, -- the circle it sits on
	Rays: Frame?, -- made the first time the set is complete
	Complete: boolean,
	JustCompleted: boolean, -- finished this session, not yet celebrated on screen
	Cards: { [string]: Card },
	Ids: { string },
	Title: TextLabel?, -- the page's name
	Gate: TextLabel?, -- a wing's gate in words ("From branch 1")
	Wing: any?, -- its Data/Wings row
}

type Header = {
	Count: TextLabel,
	SetBar: (fraction: number, atMax: boolean?) -> (),
	Reward: TextLabel?,
	Badge: Frame?,
	Name: TextLabel,
	Gate: TextLabel,
}

-- BEGIN GATE
local Gate = {}

local function wholeNumber(value: any): number
	if type(value) == "number" and value == value and value > 0 and value ~= math.huge then
		return math.floor(value)
	end
	return 0
end

-- The old chip for a wing (Data/Wings Rebirths, Only) at your rebirth count: "" (it comes to everyone), "🏢 R1",
-- "🏢 R2 · 🚁" or "🚁". KEPT for tests/Juice (this block loads with no requires, so it can't read UI/Icons); the
-- panel shows Gate.wingWords. 🏢 here means Branches (= Icons.Door.Branches).
function Gate.wing(wing: any, rebirths: any): string
	if type(wing) ~= "table" then
		return ""
	end
	local need = wholeNumber(wing.Rebirths)
	local byAir = wing.Only == "Helicopter"
	if need > 0 and wholeNumber(rebirths) < need then
		return "🏢 R" .. need .. (if byAir then " · 🚁" else "") -- uirules: allow TypedEmoji (no Icons in this block)
	end
	return if byAir then "🚁" else ""
end

-- The same gate in words (the calm UI: no emoji in front of words, no lock icon, no hurry): "" · "From branch 1" ·
-- "From branch 2 · by air" · "By air only".
function Gate.wingWords(wing: any, rebirths: any): string
	if type(wing) ~= "table" then
		return ""
	end
	local need = wholeNumber(wing.Rebirths)
	local byAir = wing.Only == "Helicopter"
	if need > 0 and wholeNumber(rebirths) < need then
		return "From branch " .. need .. (if byAir then " · by air" else "")
	end
	return if byAir then "By air only" else ""
end

-- A page's stickers: each variant stamped (Book.Variants), Golden 🌟 first (the rare one), then Data/Variants order.
function Gate.stickers(stamped: any, variants: any): (string, boolean)
	if type(stamped) ~= "table" or type(variants) ~= "table" or type(variants.Order) ~= "table" then
		return "", false
	end
	local golden = stamped.Golden == true and type(rawget(variants, "Golden")) == "table"
	local out = {}
	if golden then
		table.insert(out, rawget(variants, "Golden").Icon)
	end
	for _, id in variants.Order do
		local row = rawget(variants, id)
		if id ~= "Golden" and stamped[id] == true and type(row) == "table" then
			table.insert(out, row.Icon)
		end
	end
	return table.concat(out, ""), golden
end

-- The ONE sticker a card shows (never two emoji side by side): the first of Gate.stickers' order, then "+n" for
-- the rest ("🌟 +1"). "" with none.
function Gate.sticker(stamped: any, variants: any): (string, boolean)
	if type(stamped) ~= "table" or type(variants) ~= "table" or type(variants.Order) ~= "table" then
		return "", false
	end
	local golden = stamped.Golden == true and type(rawget(variants, "Golden")) == "table"
	local icons = {}
	if golden then
		table.insert(icons, rawget(variants, "Golden").Icon)
	end
	for _, id in variants.Order do
		local row = rawget(variants, id)
		if id ~= "Golden" and stamped[id] == true and type(row) == "table" then
			table.insert(icons, row.Icon)
		end
	end
	if #icons == 0 then
		return "", false
	end
	return icons[1] .. (if #icons > 1 then " +" .. (#icons - 1) else ""), golden
end

-- A regular's story so far: one heart glued to the count ("💛 3/5"), not a row of hearts.
function Gate.story(beat: any, total: any): string
	local all = wholeNumber(total)
	return "💛 " .. math.min(wholeNumber(beat), all) .. "/" .. all
end

-- The header's meta: the share of every page met, plain text ("6%").
function Gate.meta(percent: any): string
	return math.floor((if type(percent) == "number" and percent == percent then percent else 0) + 0.5) .. "%"
end

-- R0: which tabs show. The first wing always (where every player starts); any other wing once one of its patients
-- has a page; the regulars once one has visited (a story beat). Nothing vanishes: a page met stays met.
function Gate.visible(book: any, story: any, wings: any, patients: any, regulars: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	local order = if type(wings) == "table" and type(wings.Order) == "table" then wings.Order else {}
	local function met(id: string): boolean
		local entry = if type(book) == "table" then rawget(book, id) else nil
		return type(entry) == "table" and type(entry.Cured) == "number" and entry.Cured > 0
	end
	for index, wingId in order do
		local shown = index == 1
		if not shown and type(patients) == "table" and type(patients.Order) == "table" then
			for _, patientId in patients.Order do
				local row = rawget(patients, patientId)
				if type(row) == "table" and row.Wing == wingId and met(patientId) then
					shown = true
					break
				end
			end
		end
		out[wingId] = shown
	end
	local friends = false
	if type(regulars) == "table" and type(regulars.Order) == "table" and type(story) == "table" then
		for _, regularId in regulars.Order do
			local entry = rawget(story, regularId)
			if type(entry) == "table" and type(entry.Beat) == "number" and entry.Beat > 0 then
				friends = true
				break
			end
		end
	end
	out.Friends = friends
	return out
end
-- END GATE

BookPanel.Gate = Gate

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

local function newCard(parent: Instance, order: number, color: Color3): Card
	local frame = Kit.card({ Name = "Card" .. order, LayoutOrder = order, Pad = false })
	frame.AutomaticSize = Enum.AutomaticSize.None

	local face = Instance.new("Frame")
	face.Name = "Face"
	face.BackgroundColor3 = UNSEEN_FACE
	face.BorderSizePixel = 0
	face.AnchorPoint = Vector2.new(0.5, 0)
	face.Position = UDim2.new(0.5, 0, 0, Theme.Space.Line)
	face.Size = UDim2.new(1, -Theme.Space.PadPanel, 0.58, -Theme.Space.Line)
	Kit.corner(face, Theme.Radius.Medium)
	face.Parent = frame

	local name = Kit.name({
		Name = "PatientName",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.6),
		Size = UDim2.new(1, -Theme.Space.Line, 0.17, 0),
		Parent = frame,
	})
	local info = Kit.fact({
		Name = "Info",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.78),
		Size = UDim2.new(1, -Theme.Space.Line, 0.18, 0),
		Parent = frame,
	})
	-- The variant sticker: one emoji (and "+n"), top-right of the card.
	local stickers = Kit.label({
		Name = "Stickers",
		Text = "",
		TextSize = Theme.Emoji.State,
		TextWrapped = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Theme.Space.Tight, 0, Theme.Space.Tight),
		Size = UDim2.fromOffset(56, Theme.Calm.Badge),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 3,
		Parent = frame,
	})
	-- A flat red "NEW" badge on a page stamped since you last looked (no tilt, no outline round it: R2, R7). Its
	-- white words are outlined: text over colour.
	local ribbon = Kit.label({
		Name = "New",
		Text = "NEW",
		TextSize = Theme.TextSize.Caption,
		TextWrapped = false,
		Outlined = true,
		BackgroundColor3 = Theme.Colors.Dot,
		BackgroundTransparency = 0,
		Position = UDim2.fromOffset(Theme.Space.Tight, Theme.Space.Tight),
		Size = UDim2.fromOffset(52, Theme.Calm.Badge),
		Visible = false,
		ZIndex = 3,
		Parent = frame,
	})
	Kit.corner(ribbon, Theme.Radius.Small)
	frame.Parent = parent
	return {
		Frame = frame,
		Color = color,
		Face = face,
		Name = name,
		Info = info,
		Stickers = stickers,
		Ribbon = ribbon,
		Shown = "",
	}
end

-- Seen: the creature on a neutral Well tile. Not seen: a faded card with a dark silhouette on a soft lilac tile.
local function setFace(card: Card, look: any, dark: boolean)
	local wanted = if dark then "unseen" else "seen"
	if card.Shown == wanted then
		return
	end
	card.Shown = wanted
	card.Face:ClearAllChildren()
	Kit.corner(card.Face, Theme.Radius.Medium)
	local portrait = Hud.portrait(look, dark)
	portrait.AnchorPoint = Vector2.new(0.5, 0.5)
	portrait.Position = UDim2.fromScale(0.5, 0.5)
	portrait.Size = UDim2.fromScale(0.95, 0.95)
	portrait.Parent = card.Face
	card.Frame.BackgroundTransparency = if dark then 0.4 else 0
	card.Face.BackgroundColor3 = if dark then UNSEEN_FACE else Theme.Colors.Well
	card.Name.TextColor3 = if dark then Theme.Colors.InkSoft else Theme.Colors.Ink
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
	pad.PaddingTop = UDim.new(0, Theme.Space.Tight)
	pad.PaddingBottom = UDim.new(0, Theme.Space.Line)
	pad.PaddingLeft = UDim.new(0, Theme.Space.Tight)
	pad.PaddingRight = UDim.new(0, Theme.Space.PadCard)
	pad.Parent = scroll
	scroll.Parent = parent

	-- As many columns as fit, cards stretched to fill the row (2 on a phone, up to 5 on a big screen).
	local function fit()
		local width = scroll.AbsoluteSize.X - Theme.Space.Tight - Theme.Space.PadCard -- minus the padding
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
		Title = "Book",
		Meta = Gate.meta(0),
		MaxSize = Vector2.new(760, 600),
	})

	-- Every page, in order (the wings, then the regulars), each with its own colour for its tab's stripe. R0: a tab
	-- shows once its page has something in it (Gate.visible).
	local function visibleNow(state: Types.Snapshot): { [string]: boolean }
		return Gate.visible(state.Book, state.Story, data.Wings, data.Patients, data.Regulars)
	end
	local shownAtStart = visibleNow(ctx.State)
	local pageOrder: { string } = {}
	local colors: { [string]: Color3 } = {}
	local tabSpecs: { Modal.TabSpec } = {}
	local spare = 0
	for _, wingId in data.Wings.Order do
		local wing = data.Wings[wingId]
		local color = WING_COLORS[wingId]
		if not color then
			spare += 1
			color = SPARE_COLORS[(spare - 1) % #SPARE_COLORS + 1]
		end
		colors[wingId] = color
		table.insert(pageOrder, wingId)
		table.insert(
			tabSpecs,
			{ Id = wingId, Icon = wing.Icon, Caption = "0/0", Stripe = color, Hidden = not shownAtStart[wingId] }
		)
	end
	colors[FRIENDS] = WING_COLORS[FRIENDS]
	table.insert(pageOrder, FRIENDS)
	table.insert(tabSpecs, {
		Id = FRIENDS,
		Icon = FRIENDS_ICON,
		Caption = "0/0",
		Stripe = WING_COLORS[FRIENDS],
		Hidden = not shownAtStart[FRIENDS],
	})

	-- THE tabs (Modal.tabs): the column scrolls when seven don't fit a short phone.
	local onTab: (id: string) -> () = function() end
	local tabView = Modal.tabs(modal, tabSpecs, function(id: string)
		onTab(id)
	end)
	local pagesArea = tabView.Content

	local pages: { [string]: Page } = {}
	local current = ""

	-- The page slides in from the side (calm: it's just there). The cards come with it, all at once: a list never
	-- pops card by card (R7).
	local function enterPage(p: Page)
		if Kit.reducedMotion() then
			p.Frame.Position = UDim2.new()
			return
		end
		p.Frame.Position = UDim2.fromOffset(Theme.Space.Section, 0)
		TweenService:Create(p.Frame, Theme.Tween.Slide, { Position = UDim2.new() }):Play()
	end

	-- Shows a page (Modal.tabs has painted its tab already: tabView.select, or a tap).
	local celebrateSet: (p: Page) -> () = function() end
	local function selectPage(id: string, animate: boolean?)
		local page = pages[id]
		if not page then
			return
		end
		local changed = current ~= id
		current = id
		for pageId, p in pages do
			p.Frame.Visible = pageId == id
		end
		modal.Focus = page.Tab
		if animate and (changed or not modal.isOpen()) then
			enterPage(page)
		end
		if animate and page.JustCompleted then
			task.delay(0.45, function()
				celebrateSet(page)
			end)
		end
	end
	onTab = function(id: string)
		selectPage(id, true)
	end

	-- The header of a page (a Kit.card): the wing's Art on its own colour, its name, its gate in words, a progress
	-- bar with its count beside it, and the reward it leads to.
	local function header(parent: Instance, icon: string, text: string, color: Color3, rewardIcon: string?): Header
		local frame = Kit.card({ Name = "Header", Pad = false })
		frame.AutomaticSize = Enum.AutomaticSize.None
		frame.Size = UDim2.new(1, -Theme.Space.PadCard, 0, HEADER_HEIGHT)
		local pad = Theme.Space.PadCard
		local tile = Kit.artTile({
			Icon = icon,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, pad, 0.5, 0),
			Size = UDim2.fromOffset(48, 48),
			BackgroundColor3 = color, -- the one place, with its stripe, the wing's colour lives
			Parent = frame,
		})
		tile.Name = "Tile"
		local left = pad * 2 + 48
		local right = if rewardIcon then 52 + pad * 2 else pad
		local nameLabel = Kit.name({
			Name = "WingName",
			Text = text,
			Position = UDim2.fromOffset(left, pad - Theme.Space.Tight),
			Size = UDim2.new(0.6, -left, 0, Theme.TextSize.Body + Theme.Space.Tight),
			Parent = frame,
		})
		local gateLabel = Kit.fact({
			Name = "Gate",
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -right, 0, pad - Theme.Space.Tight),
			Size = UDim2.new(0.4, -right, 0, Theme.TextSize.Caption + Theme.Space.Tight),
			Parent = frame,
		})
		local count = Kit.fact({
			Name = "Count",
			Text = "0/0",
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -right, 1, -Theme.Space.Line),
			Size = UDim2.fromOffset(56, Theme.TextSize.Caption + Theme.Space.Tight),
			Parent = frame,
		})
		local _, setBar = Kit.bar({
			Name = "Bar",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, left, 1, -(pad + Theme.Space.Tight)),
			Size = UDim2.new(1, -(left + right + 56 + Theme.Space.Line), 0, Theme.Calm.Bar),
			Parent = frame,
		})
		local reward: TextLabel? = nil
		local badge: Frame? = nil
		if rewardIcon then
			-- A holder, so the rays (made when the set is done) can sit behind the badge.
			local holder = Instance.new("Frame")
			holder.Name = "Reward"
			holder.BackgroundTransparency = 1
			holder.AnchorPoint = Vector2.new(1, 0.5)
			holder.Position = UDim2.new(1, -pad, 0.5, 0)
			holder.Size = UDim2.fromOffset(52, 52)
			holder.Parent = frame
			local circle = Instance.new("Frame")
			circle.Name = "Badge"
			circle.BackgroundColor3 = Theme.Colors.Well
			circle.BorderSizePixel = 0
			circle.Size = UDim2.fromScale(1, 1)
			circle.ZIndex = 1
			Kit.corner(circle, Theme.Radius.Round)
			circle.Parent = holder
			reward = Kit.label({
				Name = "Icon",
				Text = rewardIcon,
				TextScaled = true,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.72, 0.72),
				Parent = circle,
			})
			badge = circle
		end
		frame.Parent = parent
		return { Count = count, SetBar = setBar, Reward = reward, Badge = badge, Name = nameLabel, Gate = gateLabel }
	end

	local function pageFrame(id: string): (Frame, ScrollingFrame)
		local frame = Instance.new("Frame")
		frame.Name = id
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.fromScale(1, 1)
		frame.Visible = false
		frame.Parent = pagesArea
		local scroll = grid(frame)
		local top = HEADER_HEIGHT + Theme.Space.PadCard
		scroll.Position = UDim2.fromOffset(0, top)
		scroll.Size = UDim2.new(1, 0, 1, -top)
		return frame, scroll
	end

	-- Wing pages
	for _, wingId in data.Wings.Order do
		local wing = data.Wings[wingId]
		local reward = data.Decor[wing.SetReward]
		local color = colors[wingId]
		local frame, scroll = pageFrame(wingId)
		local top = header(frame, wing.Icon, wing.Name, color, reward and reward.Icon)
		local ids = patientsOf(data, wingId)
		local cards: { [string]: Card } = {}
		for order, patientId in ids do
			cards[patientId] = newCard(scroll, order, color)
		end
		pages[wingId] = {
			Frame = frame,
			Tab = tabView.Buttons[wingId],
			Color = color,
			Progress = top.Count,
			SetBar = top.SetBar,
			Reward = top.Reward,
			Badge = top.Badge,
			Rays = nil,
			Complete = false,
			JustCompleted = false,
			Cards = cards,
			Ids = ids,
			Title = top.Name,
			Gate = top.Gate,
			Wing = wing,
		}
	end

	-- The regulars
	do
		local color = colors[FRIENDS]
		local frame, scroll = pageFrame(FRIENDS)
		local top = header(frame, FRIENDS_ICON, "Story friends", color, nil)
		local cards: { [string]: Card } = {}
		local ids = {}
		for order, regularId in data.Regulars.Order do
			cards[regularId] = newCard(scroll, order, color)
			table.insert(ids, regularId)
		end
		pages[FRIENDS] = {
			Frame = frame,
			Tab = tabView.Buttons[FRIENDS],
			Color = color,
			Progress = top.Count,
			SetBar = top.SetBar,
			Reward = nil,
			Badge = nil,
			Rays = nil,
			Complete = false,
			JustCompleted = false,
			Cards = cards,
			Ids = ids,
		}
	end

	--------------------------------------------------------------------------------------------------------------
	-- New pages since you last looked (from the Cured remote: exact, and only the helper's own stamps)
	--------------------------------------------------------------------------------------------------------------
	local fresh: { [string]: boolean } = {}
	local initial = ctx.State
	local armed = false -- set after the first server snapshot (see render)
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
	-- The count rolls while the Book is open (closed, it's just set); the bar slides (Kit.bar), gold when done.
	local function setProgress(p: Page, done: number, total: number)
		local live = modal.isOpen() and not Kit.reducedMotion()
		if p.Progress then
			Kit.countUp(p.Progress, done, function(n: number): string
				return math.floor(n + 0.5) .. "/" .. total
			end, if live then nil else 0)
		end
		if p.SetBar then
			p.SetBar(Kit.Juice.barFraction(done, total), total > 0 and done >= total)
		end
		local caption = p.Tab:FindFirstChild("Caption")
		if caption and caption:IsA("TextLabel") then
			caption.Text = if total > 0 and done >= total then Icons.State.Done else done .. "/" .. total
		end
	end

	local function renderWing(wingId: string, state: Types.Snapshot): (number, number)
		local p = pages[wingId]
		local met = 0
		local rebirth = (state :: any).Rebirth
		local gate = Gate.wingWords(p.Wing, if type(rebirth) == "table" then rebirth.Count else 0)
		if p.Gate then
			p.Gate.Text = gate
		end
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
				card.Name.Text = patient.Name
				card.Info.Text = "🩺 ×" .. cured -- times treated (its case is rolled each visit, so none is shown)
				local sticker, golden = Gate.sticker((state.Book[patientId] or {}).Variants, data.Variants)
				card.Stickers.Text = sticker
				-- A Golden 🌟 page: a gold card (a fill, not an outline).
				card.Frame.BackgroundColor3 = if golden then GOLDEN_CARD else Theme.Colors.Card
			else
				card.Name.Text = "???"
				card.Info.Text = gate -- "From branch 1": calm, no lock
				card.Stickers.Text = ""
				card.Frame.BackgroundColor3 = Theme.Colors.Card
			end
		end
		setProgress(p, met, #p.Ids)
		local badge = p.Badge
		if p.Reward and badge then
			-- Still to earn: a faded icon on the Well. Earned: a gold badge on turning rays.
			local complete = #p.Ids > 0 and met >= #p.Ids
			p.Reward.TextTransparency = if complete then 0 else 0.55
			badge.BackgroundColor3 = if complete then Kit.lighten(Theme.Colors.Cash, 0.08) else Theme.Colors.Well
			local holder = badge.Parent
			if complete and not p.Rays and holder and holder:IsA("GuiObject") then
				p.Rays = Kit.rays(holder, Theme.Colors.Cash)
			end
			local rays = p.Rays
			if rays then
				rays.Visible = complete
			end
			if complete and not p.Complete then
				Kit.bump(badge)
				if armed then
					p.JustCompleted = true -- celebrated when its page is next on screen
					if modal.isOpen() and current == wingId then
						task.delay(0.3, function()
							celebrateSet(p)
						end)
					end
				end
			end
			p.Complete = complete
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
				card.Info.Text = Gate.story(beat, total)
				-- One sticker: the reward when the story is done (its Art), else the last visit's emote.
				local reward = data.Decor[regular.Reward] or data.Rooms[regular.Reward]
				card.Stickers.Text = if beat >= total and reward
					then reward.Icon
					else regular.Beats[math.min(beat, total)].Emote
			elseif unlocked then
				card.Name.Text = "???"
				card.Info.Text = "Coming soon"
				card.Stickers.Text = ""
			else
				card.Name.Text = "???"
				card.Info.Text = "Needs " .. Icons.unit("Stars", regular.UnlockStars)
				card.Stickers.Text = ""
			end
		end
		setProgress(p, finished, #p.Ids)
	end

	local function render(state: Types.Snapshot)
		-- R0: a tab appears the moment its page has something in it.
		local visible = visibleNow(state)
		for _, pageId in pageOrder do
			tabView.setVisible(pageId, visible[pageId] == true)
		end
		local met, total = 0, 0
		for _, wingId in data.Wings.Order do
			local m, t = renderWing(wingId, state)
			met += m
			total += t
		end
		renderFriends(state)
		-- The header's meta: the share of every page met ("6%"), rolling while it's open.
		local percent = if total > 0 then math.floor(met / total * 100) else 0
		Kit.countUp(modal.Meta, percent, Gate.meta, if modal.isOpen() then nil else 0)
		-- The first server snapshot is the save loading in: sets already done then aren't "just" done.
		if state ~= initial then
			armed = true
		end
	end
	ctx.onState(render)

	-- A finished set: confetti from its reward badge and a fanfare, once.
	celebrateSet = function(p: Page)
		if not p.JustCompleted or not modal.isOpen() or pages[current] ~= p then
			return
		end
		p.JustCompleted = false
		local holder = p.Badge and p.Badge.Parent
		if holder and holder:IsA("GuiObject") then
			Kit.punch(holder, 1.4, Theme.Tween.Bump)
			Kit.confetti(holder, 18, UDim2.fromScale(0.5, 0.5))
		end
		Hud.sound("Fanfare", 0.7)
	end

	ctx.on("Open", function(name: any)
		if name ~= "Book" then
			return
		end
		render(ctx.State)
		-- Open on the page with something new, else where you were (or the first page showing).
		local showing = tabView.visible()
		local target = if current ~= "" and table.find(showing, current) then current else showing[1] or pageOrder[1]
		for _, pageId in pageOrder do
			for id in fresh do
				if pages[pageId].Cards[id] and table.find(showing, pageId) then
					target = pageId
				end
			end
		end
		tabView.select(target) -- paints its tab and shows the page (sliding in: the Book isn't open yet)
		modal.open()
		-- Each new page on screen: a pop and a confetti puff once the page is in, and a sparkle.
		local any = false
		for id in fresh do
			for _, p in pages do
				local card = p.Cards[id]
				if card and p.Frame.Visible then
					any = true
					task.delay(0.45, function()
						Hud.pop(card.Frame, 1.2)
						Kit.confetti(card.Frame, 12, UDim2.fromScale(0.5, 0.35))
					end)
				end
			end
		end
		if any then
			task.delay(0.45, Hud.sound, "Sparkle")
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
