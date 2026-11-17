--!strict
-- BookPanel (build plan Task 6): the Patient Book. One tab per wing (Data/Wings) plus 💌 for the regulars.
--   init(ctx)   opens on ctx.fire("Open", "Book")
-- A wing page shows its set progress, the set reward and a card per patient: not met yet = a dark silhouette
-- with "?"; met = a face, name, "🩺 ×n" (times treated: a patient's case is rolled each visit from its wing's pool,
-- so the card shows none) and variant stickers (✨ 🧊). Cards for
-- pages stamped since you last looked carry a 🆕 ribbon. The 💌 page shows each regular's story as 5 hearts.
-- Reads only the Snapshot (Book, Story, Stars) and the Cured remote (NewPage). Fires "BookNew" (count) for the
-- HUD's 📖 dot.
-- Look (the look overhaul's template, look build plan §B8): UI/Modal's navy header with the "📖 n%" meta chip (the
-- share of every page met, rolling while it's open), Modal.tabs down the left with each wing's own colour as its
-- 6 px stripe, and tinted cards on flat paper. A wing's colour lives only on its tab's stripe, its page tile and its
-- bar. A page you've filled shows the creature on a neutral Well tile; one you haven't is a faded "???" silhouette.
-- A finished set's reward sits on turning rays (a reward moment).
-- Juice (depth update, design §4): opening the Book or a tab, the page slides in and its cards pop in one after
-- another; the progress bars fill up and the counts roll (Kit.countUp) while it's open; each new page's card bursts
-- with confetti when you open the Book on it (its NEW! sticker stays still: the motion budget); a set finished this
-- session throws confetti from its reward badge the first time you see it. Calm (Kit.reducedMotion()): all of it
-- simply appears.
-- Progression v2 (build plan §C T8): a wing that comes with rebirths says so calmly on its page and its unmet cards
-- ("🏢 R1" for the 🌻 Sunny wing; "🏢 R2 · 🚁" for the Sky wing, whose patients only come by air ambulance; just
-- "🚁" once your branch has it): no lock icon, no "hurry". A page stamped Golden 🌟 (R3+) gets a gold outline, and
-- the 🌟 leads its stickers. The rules are the pure GATE block (tests/Juice).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Modal = require(script.Parent.Modal)
local Theme = require(script.Parent.Theme)

local BookPanel = {}

local MIN_CARD = 118
local CARD_GAP = Theme.Space.PadCard
local FRIENDS = "Friends"
-- Each wing's own colour (Data/Wings ids): only its tab's stripe, its page tile and its bar. A wing added later
-- takes the next one from SPARE_COLORS.
local WING_COLORS: { [string]: Color3 } = {
	Starter = Theme.Colors.Collect,
	Bath = Theme.Colors.Cyan,
	Winter = Palette.Candy.Blue,
	Night = Theme.Colors.Night,
	[FRIENDS] = Theme.Colors.Pink,
}
local SPARE_COLORS = { Theme.Colors.Primary, Theme.Colors.Cash, Theme.Colors.Purple }
local SEEN_STROKE = Theme.Stroke.Fine
local GOLDEN_STROKE = Theme.Stroke.Bold
local UNSEEN_FACE = Kit.lighten(Theme.Colors.Locked, 0.6) -- a "???" silhouette's tile

type Card = {
	Frame: Frame,
	Stroke: UIStroke,
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
	Fill: Frame?,
	Reward: TextLabel?, -- the reward's emoji
	Badge: Frame?, -- the circle it sits on
	Rays: Frame?, -- made the first time the set is complete
	Complete: boolean,
	JustCompleted: boolean, -- finished this session, not yet celebrated on screen
	Cards: { [string]: Card },
	Ids: { string },
	Title: TextLabel?, -- the page's name (a wing's gets its 🏢 / 🚁 chip)
	Wing: any?, -- its Data/Wings row
}

type Header = { Count: TextLabel, Fill: Frame, Reward: TextLabel?, Badge: Frame?, Name: TextLabel }

-- BEGIN GATE
local Gate = {}

local function wholeNumber(value: any): number
	if type(value) == "number" and value == value and value > 0 and value ~= math.huge then
		return math.floor(value)
	end
	return 0
end

-- The calm chip for a wing (Data/Wings Rebirths, Only) at your rebirth count: "" (it comes to everyone), "🏢 R1" (from
-- your first branch), "🏢 R2 · 🚁" (from your second, and only by air ambulance), or "🚁" (open, but only by air).
function Gate.wing(wing: any, rebirths: any): string
	if type(wing) ~= "table" then
		return ""
	end
	local need = wholeNumber(wing.Rebirths)
	local byAir = wing.Only == "Helicopter"
	if need > 0 and wholeNumber(rebirths) < need then
		return "🏢 R" .. need .. (if byAir then " · 🚁" else "")
	end
	return if byAir then "🚁" else ""
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
-- END GATE

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
	local frame = Instance.new("Frame")
	frame.Name = "Card" .. order
	frame.LayoutOrder = order
	frame.BackgroundColor3 = Theme.Colors.Card
	frame.BorderSizePixel = 0
	Kit.corner(frame, Theme.Radius.Medium)
	local stroke = Kit.stroke(frame, Theme.Colors.CardLine, SEEN_STROKE)

	local face = Instance.new("Frame")
	face.Name = "Face"
	face.BackgroundColor3 = UNSEEN_FACE
	face.BorderSizePixel = 0
	face.AnchorPoint = Vector2.new(0.5, 0)
	face.Position = UDim2.new(0.5, 0, 0, Theme.Space.Gap)
	face.Size = UDim2.new(1, -Theme.Space.PadPanel, 0.58, -Theme.Space.Gap)
	Kit.corner(face, Theme.Radius.Medium)
	face.Parent = frame

	local name = Kit.label({
		Name = "PatientName",
		Text = "",
		Font = Theme.DisplayFont,
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.6),
		Size = UDim2.new(1, -10, 0.17, 0),
		Parent = frame,
	})
	Kit.textLimit(name, Theme.TextSize.Body)
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
	Kit.textLimit(info, Theme.TextSize.Body)
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
	Kit.textLimit(stickers, Theme.TextSize.Body)
	-- A red "NEW!" sticker, tipped at an angle, on a page stamped since you last looked. It stays still (only a
	-- Collect button may breathe: the motion budget).
	local ribbon = Kit.label({
		Name = "New",
		Text = "NEW!",
		TextSize = Theme.TextSize.Caption,
		TextWrapped = false,
		Outlined = true,
		BackgroundColor3 = Theme.Colors.Dot,
		BackgroundTransparency = 0,
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.fromOffset(58, 26),
		Rotation = -8,
		Visible = false,
		ZIndex = 3,
		Parent = frame,
	})
	Kit.corner(ribbon, Theme.Radius.Small)
	Kit.stroke(ribbon, Theme.Colors.Stroke, Theme.Stroke.Fine)
	frame.Parent = parent
	return {
		Frame = frame,
		Stroke = stroke,
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
	card.Stroke.Transparency = if dark then 0.5 else 0
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
	pad.PaddingTop = UDim.new(0, Theme.Space.Step[1])
	pad.PaddingBottom = UDim.new(0, Theme.Space.Gap)
	pad.PaddingLeft = UDim.new(0, Theme.Space.Step[1]) -- scrolling frames clip: keep the cards' outlines whole
	pad.PaddingRight = UDim.new(0, Theme.Space.PadCard)
	pad.Parent = scroll
	scroll.Parent = parent

	-- As many columns as fit, cards stretched to fill the row (2 on a phone, up to 5 on a big screen).
	local function fit()
		local width = scroll.AbsoluteSize.X - Theme.Space.Step[1] - Theme.Space.PadCard -- minus the padding
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
		Meta = "📖 0%",
		MaxSize = Vector2.new(760, 600),
	})

	-- Every page, in order (the wings, then the regulars), each with its own colour for its tab's stripe.
	local pageOrder: { string } = {}
	local colors: { [string]: Color3 } = {}
	local tabSpecs = {}
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
		table.insert(tabSpecs, { Id = wingId, Icon = wing.Icon, Caption = "0/0", Stripe = color })
	end
	colors[FRIENDS] = WING_COLORS[FRIENDS]
	table.insert(pageOrder, FRIENDS)
	table.insert(tabSpecs, { Id = FRIENDS, Icon = "💌", Caption = "0/0", Stripe = WING_COLORS[FRIENDS] })

	-- THE tabs (Modal.tabs): the column scrolls when seven don't fit a short phone.
	local onTab: (id: string) -> () = function() end
	local tabView = Modal.tabs(modal, tabSpecs, function(id: string)
		onTab(id)
	end)
	local pagesArea = tabView.Content
	for _, button in tabView.Buttons do
		local caption = button:FindFirstChild("Caption")
		if caption and caption:IsA("TextLabel") then
			caption.Font = Theme.DisplayFont -- the count is a number: chunky
		end
	end

	local pages: { [string]: Page } = {}
	local current = ""

	-- The page slides in from the side and its cards pop in one after another (calm: they're just there).
	local MAX_STAGGERED = 12
	local function enterPage(p: Page)
		if Kit.reducedMotion() then
			p.Frame.Position = UDim2.new()
			return
		end
		p.Frame.Position = UDim2.fromOffset(28, 0)
		TweenService:Create(p.Frame, Theme.Tween.Slide, { Position = UDim2.new() }):Play()
		local fill = p.Fill
		if fill then -- the bar fills up from empty
			local ratio = fill:GetAttribute("Goal")
			local goal = UDim2.fromScale(if type(ratio) == "number" then ratio else fill.Size.X.Scale, 1)
			fill.Size = UDim2.fromScale(0, 1)
			TweenService:Create(fill, Theme.Tween.Fill, { Size = goal }):Play()
		end
		for order, id in p.Ids do
			if order > MAX_STAGGERED then
				break
			end
			local card = p.Cards[id]
			if card then
				-- Tiny until its turn (the tween's delay), then it springs up (the grid never reflows).
				local info =
					TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0.035 * order)
				Kit.punch(card.Frame, 0.05, info)
			end
		end
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

	-- The header of a page (a tinted card): the wing's icon on its own colour, its name, a progress bar, and the
	-- reward it leads to.
	local function header(parent: Instance, icon: string, text: string, color: Color3, rewardIcon: string?): Header
		local frame = Instance.new("Frame")
		frame.Name = "Header"
		frame.BackgroundColor3 = Theme.Colors.Card
		frame.BorderSizePixel = 0
		frame.Size = UDim2.new(1, -Theme.Space.PadCard, 0, 64)
		Kit.corner(frame, Theme.Radius.Medium)
		Kit.stroke(frame, Theme.Colors.CardLine, Theme.Stroke.Fine)
		-- The wing's icon on a tile of its own colour (the one place, with its stripe and bar, the colour lives).
		local tile = Instance.new("Frame")
		tile.Name = "Tile"
		tile.AnchorPoint = Vector2.new(0, 0.5)
		tile.Position = UDim2.new(0, Theme.Space.Gap, 0.5, 0)
		tile.Size = UDim2.fromOffset(46, 46)
		tile.BackgroundColor3 = color
		tile.BorderSizePixel = 0
		Kit.corner(tile, Theme.Radius.Small)
		tile.Parent = frame
		Kit.label({
			Name = "Icon",
			Text = icon,
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.78, 0.78),
			Parent = tile,
		})
		local nameLabel = Kit.label({
			Name = "WingName",
			Text = text,
			Font = Theme.DisplayFont,
			TextScaled = true,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(62, 6),
			Size = UDim2.new(1, -62 - 70, 0, 26),
			Parent = frame,
		})
		Kit.textLimit(nameLabel, Theme.TextSize.Body)
		local track = Instance.new("Frame")
		track.Name = "Track"
		track.BackgroundColor3 = Theme.Colors.Well
		track.BorderSizePixel = 0
		track.Position = UDim2.fromOffset(62, 38)
		track.Size = UDim2.new(1, -62 - 70 - 56, 0, 16)
		Kit.corner(track, Theme.Radius.Small)
		track.Parent = frame
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BackgroundColor3 = color
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(0, 1)
		Kit.corner(fill, Theme.Radius.Small)
		fill.Parent = track
		local count = Kit.label({
			Name = "Count",
			Text = "0/0",
			Font = Theme.DisplayFont,
			TextScaled = true,
			TextWrapped = false,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -74, 0, 32),
			Size = UDim2.fromOffset(50, 26),
			Parent = frame,
		})
		Kit.textLimit(count, Theme.TextSize.Body)
		local reward: TextLabel? = nil
		local badge: Frame? = nil
		if rewardIcon then
			-- A holder, so the rays (made when the set is done) can sit behind the badge.
			local holder = Instance.new("Frame")
			holder.Name = "Reward"
			holder.BackgroundTransparency = 1
			holder.AnchorPoint = Vector2.new(1, 0.5)
			holder.Position = UDim2.new(1, -Theme.Space.Gap, 0.5, 0)
			holder.Size = UDim2.fromOffset(52, 52)
			holder.Parent = frame
			local circle = Instance.new("Frame")
			circle.Name = "Badge"
			circle.BackgroundColor3 = Theme.Colors.Paper
			circle.BorderSizePixel = 0
			circle.Size = UDim2.fromScale(1, 1)
			circle.ZIndex = 1
			Kit.corner(circle, Theme.Radius.Round)
			Kit.stroke(circle, Theme.Colors.CardLine, Theme.Stroke.Fine)
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
		return { Count = count, Fill = fill, Reward = reward, Badge = badge, Name = nameLabel }
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
			Fill = top.Fill,
			Reward = top.Reward,
			Badge = top.Badge,
			Rays = nil,
			Complete = false,
			JustCompleted = false,
			Cards = cards,
			Ids = ids,
			Title = top.Name,
			Wing = wing,
		}
	end

	-- The regulars
	do
		local color = colors[FRIENDS]
		local frame, scroll = pageFrame(FRIENDS)
		local top = header(frame, "💌", "Story friends", color, nil)
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
			Fill = top.Fill,
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
	-- The count rolls and the bar fills while the Book is open; closed, they're just set.
	local function setProgress(p: Page, done: number, total: number)
		local live = modal.isOpen() and not Kit.reducedMotion()
		if p.Progress then
			Kit.countUp(p.Progress, done, function(n: number): string
				return math.floor(n + 0.5) .. "/" .. total
			end, if live then nil else 0)
		end
		if p.Fill then
			local ratio = if total > 0 then done / total else 0
			p.Fill:SetAttribute("Goal", ratio) -- enterPage fills up to it
			local goal = UDim2.fromScale(ratio, 1)
			if live and p.Fill.Size ~= goal then
				TweenService:Create(p.Fill, Theme.Tween.Fill, { Size = goal }):Play()
			else
				p.Fill.Size = goal
			end
		end
		local caption = p.Tab:FindFirstChild("Caption")
		if caption and caption:IsA("TextLabel") then
			caption.Text = if total > 0 and done >= total then "✅" else done .. "/" .. total
		end
	end

	local function renderWing(wingId: string, state: Types.Snapshot): (number, number)
		local p = pages[wingId]
		local met = 0
		local rebirth = (state :: any).Rebirth
		local gate = Gate.wing(p.Wing, if type(rebirth) == "table" then rebirth.Count else 0)
		if p.Title and p.Wing then
			p.Title.Text = tostring(p.Wing.Name) .. (if gate ~= "" then "  " .. gate else "")
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
				local stickers, golden = Gate.stickers((state.Book[patientId] or {}).Variants, data.Variants)
				card.Stickers.Text = stickers
				-- A Golden 🌟 page: a gold outline round the card.
				card.Stroke.Color = if golden then Theme.Colors.Cash else Theme.Colors.CardLine
				card.Stroke.Thickness = if golden then GOLDEN_STROKE else SEEN_STROKE
			else
				card.Name.Text = "???"
				card.Info.Text = gate -- "🏢 R1": calm, no lock
				card.Stickers.Text = ""
				card.Stroke.Color = Theme.Colors.CardLine
				card.Stroke.Thickness = SEEN_STROKE
			end
		end
		setProgress(p, met, #p.Ids)
		local badge = p.Badge
		if p.Reward and badge then
			-- Still to earn: a faded icon on white. Earned: a gold badge on turning rays.
			local complete = #p.Ids > 0 and met >= #p.Ids
			p.Reward.TextTransparency = if complete then 0 else 0.55
			badge.BackgroundColor3 = if complete then Kit.lighten(Theme.Colors.Cash, 0.08) else Theme.Colors.Paper
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
		-- The header's meta chip: the share of every page met ("📖 6%"), rolling while it's open.
		local percent = if total > 0 then math.floor(met / total * 100) else 0
		Kit.countUp(modal.Meta, percent, function(n: number): string
			return "📖 " .. math.floor(n + 0.5) .. "%"
		end, if modal.isOpen() then nil else 0)
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
		-- Open on the page with something new, else where you were (or the first wing).
		local target = if current ~= "" then current else pageOrder[1]
		for _, pageId in pageOrder do
			for id in fresh do
				if pages[pageId].Cards[id] then
					target = pageId
				end
			end
		end
		render(ctx.State)
		tabView.select(target) -- paints its tab and shows the page (sliding in: the Book isn't open yet)
		modal.open()
		-- Each new page on screen: a pop and a confetti puff once the cards are in, and a sparkle.
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
