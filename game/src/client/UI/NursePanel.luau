--!strict
-- NursePanel (depth-update design §2, build plan §B9; memory-20261116-012/-013). OWNER: T5 (Progression v2).
-- FOUNDATION (Progression v2 Task 0): EquipNurse and slots are gone. Until T5 builds the Team page, the strip shows
-- the roster (Logic/Nurse.rosterCap: the working nurses, then empty places) and Equip on a resting nurse asks SetJob
-- for its role (Logic/Nurse.setJob lets a resting nurse work while the roster has room); "off duty" no longer
-- exists (every nurse you own works).
-- The 👩‍⚕️ Nurses panel: the Nurse Journal first (a bestiary of every nurse, by rarity), and equipping inside it.
--   init(ctx)   opens on ctx.fire("Open", "Nurses", rarity?) (the Hud's 👩‍⚕️ button); listens for "NurseNews";
--               fires "NursesNew" (count) for the button's dot, "Open" ("NurseOdds") for UI/BeltView's odds popup,
--               "Open" ("Shop", "Hospital") from a locked slot, and "Sound" (Sparkle, Click; Equip and Hire cues
--               come with NurseNews in Feel/Sounds)
--
-- Inside (a Hud.modal Panel, cyan like its HUD button):
--   header    "👩‍⚕️ Journal" and a completion pill "📔 n%" (hired out of all, Logic/Nurse.journal)
--   on duty   a strip of slot chips (Logic/Levels.slots at your level): a nurse on duty (tap: off duty), an empty
--             slot (tap: points you at a hired nurse), and the next level's locked slot (🔒 Lv n; tap: the Shop's
--             Hospital tab)
--   tabs      one per rarity (Data/Rarities.Order), each with hired/total (✅ when the group is done) and a dot for
--             news inside
--   a page    the rarity's header (its icon, "Night Rush only" / "Golden Hour only" for Mythic and Secret, a
--             progress bar, the group reward 💰 + decor (✅ and rays once JournalSets has it), and a 🎲 chip with
--             the odds right now, which opens the odds popup), then a card per nurse:
--               unseen  a dark silhouette, "???" and where to find it (👀 On the belt / 🌙 Night Rush / 👑 Golden Hour)
--               seen    greyed out, its name, role and your belt price
--               hired   full colour with a nurse cap in the rarity's colour, its level and stat, and Equip /
--                       Unequip (EquipNurse via Hud.ask); ✅ in the corner while on duty
--             Cards with news since you last opened the panel wear a NEW! sticker and pop when it opens.
-- NEW! moments: a nurse seen for the first time (and a copy that levels one up) pops a little stamp card above the
-- 👩‍⚕️ button that flies into it (fades with reduced motion; none during the first-session tutorial or while the
-- panel is open, where the card pops instead). A first hire's big moment is UI/Celebrate's (the server's
-- "Celebrate" NewNurse).
-- Reads only the Snapshot (NurseIndex, Nurses, Equipped, JournalSets, Level, Cash) and Workspace's GoldenHour /
-- NightRush (for the 🎲 chips). The server decides everything; this panel only asks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local Logic = Shared:WaitForChild("Logic")
local BeltLogic = require(Logic:WaitForChild("Belt"))
local NurseLogic = require(Logic:WaitForChild("Nurse"))
local TutorialLogic = require(Logic:WaitForChild("Tutorial"))
local BeltView = require(script.Parent.BeltView)
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local BeltPure = BeltView.Pure

local NursePanel = {}

local ACCENT = Theme.Colors.Cyan
local TAB_WIDTH = Theme.Size.IconButton
local SLOT = Theme.Size.ButtonHeight
local STRIP_HEIGHT = SLOT + 8
local PILL_WIDTH = 118
local MIN_CARD = 112
local CARD_GAP = 10
-- Under each card's face: 4 gap + name 22 + info 20 + 4 gap + the button + 6, plus the face's 6 on top.
local CARD_FIXED = 6 + 4 + 22 + 20 + 4 + SLOT + 6
local HEADER_HEIGHT = 8 + 44 + 6 + 14 + 8 + SLOT + 8
local ODDS_WIDTH = 100
local STAMP_SIZE = Vector2.new(132, 156)
local STAMP_SECONDS = 1.7
local STAMP_QUEUE_MAX = 4
local UNSEEN_FILL = Kit.lighten(Theme.Colors.Disabled, 0.55)
local UNSEEN_FACE = Kit.lighten(Theme.Colors.Disabled, 0.2)
local SEEN_FACE = Kit.lighten(Theme.Colors.Disabled, 0.45)

------------------------------------------------------------------------------------------------------------------
-- Pure helpers: no Roblox services or types, only BeltPure (UI/BeltView's pure block). A scratch
-- Lune harness loads the block between the PURE markers on its own, so keep it that way.
------------------------------------------------------------------------------------------------------------------
-- PURE-BEGIN
local Pure = {}

Pure.ROLE_NAMES = { Maker = "Maker", Healer = "Healer", Cheerer = "Cheerer" } :: { [string]: string }

-- A nurse's Journal state: "Hired" · "Seen" · "Unseen" (no entry, or junk).
function Pure.mark(index: any, nurseId: string): string
	local value = if type(index) == "table" then index[nurseId] else nil
	return if value == "Hired" then "Hired" elseif value == "Seen" then "Seen" else "Unseen"
end

-- Journal news since the panel was last opened: fresh[nurseId] = "Seen" | "Hired" (Seen never replaces Hired;
-- Equipped news isn't journal news). Returns true when `fresh` changed.
function Pure.noteNews(fresh: { [string]: string }, info: any): boolean
	if type(info) ~= "table" or type(info.NurseId) ~= "string" then
		return false
	end
	local kind = info.Kind
	if kind ~= "Seen" and kind ~= "Hired" then
		return false
	end
	local current = fresh[info.NurseId]
	if current == kind or (current == "Hired" and kind == "Seen") then
		return false
	end
	fresh[info.NurseId] = kind
	return true
end

function Pure.count(fresh: { [string]: string }): number
	local n = 0
	for _ in fresh do
		n += 1
	end
	return n
end

-- "Lv 2" · "Lv 5 MAX" (an entry without a level counts as Lv 1).
function Pure.levelText(entry: any, maxLevel: number): string
	local level = if type(entry) == "table" and type(entry.Level) == "number" then math.floor(entry.Level) else 1
	if level >= maxLevel then
		return "Lv " .. level .. " MAX"
	end
	return "Lv " .. level
end

export type Chip = { Kind: string, NurseId: string?, Level: number? }

-- The roster strip (Progression v2, the Foundation's interim): one chip per roster place ("Filled" for each working
-- nurse in order, then "Empty"), at most `cap` (Logic/Nurse.rosterCap). No locked chips: the roster grows with
-- rebirths, and nothing here pushes toward one.
function Pure.slotChips(working: { string }, cap: number): { Chip }
	local places = if type(cap) == "number" and cap == cap then math.max(0, math.floor(cap)) else 0
	local chips: { Chip } = {}
	for i = 1, places do
		local nurseId = if type(working) == "table" then working[i] else nil
		if type(nurseId) == "string" then
			table.insert(chips, { Kind = "Filled", NurseId = nurseId })
		else
			table.insert(chips, { Kind = "Empty" })
		end
	end
	return chips
end

-- A group's reward line: "💰300 + 🩹" (in-game cash, then the decor's icon).
function Pure.rewardText(rarity: any, decorIcon: string?): string
	local journal = if type(rarity) == "table" and type(rarity.Journal) == "table" then rarity.Journal else {}
	local cash = if type(journal.Cash) == "number" then journal.Cash else 0
	local text = "💰" .. BeltPure.short(cash)
	if type(decorIcon) == "string" and decorIcon ~= "" then
		text ..= " + " .. decorIcon
	end
	return text
end

-- Under a card with no button: where to find an unseen nurse (an event rarity names its event), or your belt price
-- for a seen one.
function Pure.hint(mark: string, rarity: any, price: number): string
	if mark == "Unseen" then
		local event = if type(rarity) == "table" then rarity.Event else nil
		if event == "NightRush" then
			return "🌙 Night Rush"
		elseif event == "GoldenHour" then
			return "👑 Golden Hour"
		end
		return "👀 On the belt"
	end
	return "💰" .. BeltPure.short(price)
end

-- A page's note under its name: Mythic and Secret only come during their event.
function Pure.eventNote(rarity: any): string
	local event = if type(rarity) == "table" then rarity.Event else nil
	if event == "NightRush" then
		return "🌙 Night Rush only"
	elseif event == "GoldenHour" then
		return "👑 Golden Hour only"
	end
	return ""
end

-- The page the panel opens on: the lowest rarity with news in it, else the page you were on, else the first.
function Pure.firstPage(fresh: { [string]: string }, roster: any, order: { string }, current: string?): string
	for _, rarity in order do
		for nurseId in fresh do
			local nurse = rawget(roster, nurseId)
			if type(nurse) == "table" and nurse.Rarity == rarity then
				return rarity
			end
		end
	end
	if current and table.find(order, current) then
		return current
	end
	return order[1]
end
-- PURE-END

NursePanel.Pure = Pure -- for a scratch harness

------------------------------------------------------------------------------------------------------------------
-- Look helpers
------------------------------------------------------------------------------------------------------------------

local function hexColor(value: any, fallback: Color3): Color3
	if type(value) ~= "string" then
		return fallback
	end
	local ok, color = pcall(Color3.fromHex, value)
	return if ok then color else fallback
end

local function textLimit(label: TextLabel, max: number)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = max
	limit.MinTextSize = 9
	limit.Parent = label
end

local function frame(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for key, value in props do
		if key ~= "Parent" then
			(f :: any)[key] = value
		end
	end
	f.Parent = props.Parent
	return f
end

local function childOf(parent: Instance, name: string, class: string): Instance?
	local found = parent:FindFirstChild(name)
	return if found and found:IsA(class) then found else nil
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

local function padButton(button: GuiObject, x: number, y: number)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, x)
	pad.PaddingRight = UDim.new(0, x)
	pad.PaddingTop = UDim.new(0, y)
	pad.PaddingBottom = UDim.new(0, y)
	pad.Parent = button
end

-- A tab in its rarity's colour: a pale tint while it waits, full candy with outlined text when it's open.
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

-- A nurse cap in the rarity's colour, tipped on the portrait's head (the 3D nurses wear the same).
local function addCap(portrait: Frame, color: Color3)
	local cap = Instance.new("Frame")
	cap.Name = "Cap"
	cap.AnchorPoint = Vector2.new(0.5, 0.5)
	cap.Position = UDim2.fromScale(0.37, 0.25)
	cap.Size = UDim2.fromScale(0.3, 0.13)
	cap.Rotation = -16
	cap.BackgroundColor3 = color
	cap.BorderSizePixel = 0
	cap.ZIndex = 7
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.4, 0)
	corner.Parent = cap
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Outline
	stroke.Thickness = 2
	stroke.Parent = cap
	local cross = Kit.label({
		Name = "Cross",
		Text = "✚",
		TextScaled = true,
		Outlined = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 1),
		ZIndex = 7,
		Parent = cap,
	})
	cross.TextColor3 = Theme.Colors.OnColor
	cap.Parent = portrait
end

------------------------------------------------------------------------------------------------------------------
-- The panel
------------------------------------------------------------------------------------------------------------------

type Card = {
	Id: string,
	Rarity: string,
	Color: Color3,
	Frame: Frame,
	Face: Frame,
	Name: TextLabel,
	Info: TextLabel,
	Hint: TextLabel,
	Equip: TextButton,
	Rest: TextButton,
	Duty: TextLabel,
	Ribbon: TextLabel,
	Shown: string, -- "Unseen" | "Seen" | "Hired": which face is drawn now
	StopFrame: (() -> ())?,
}

type Page = {
	Rarity: string,
	Color: Color3,
	Frame: ScrollingFrame,
	Tab: TextButton,
	Count: TextLabel,
	Fill: Frame,
	Reward: Frame,
	RewardText: TextLabel,
	Badge: Frame,
	BadgeIcon: TextLabel,
	Rays: Frame?,
	Claimed: boolean,
	Odds: TextButton,
	Cards: { Card },
}

type Stamp = { NurseId: string, Kind: string, Level: number? }

function NursePanel.init(ctx: Types.Ctx)
	local data = ctx.Data :: any
	local cfg = ctx.Config
	local rarityOrder: { string } = data.Rarities.Order
	local maxLevel: number = if type(cfg.Nurses) == "table" and type(cfg.Nurses.MaxLevel) == "number"
		then cfg.Nurses.MaxLevel
		else 5

	local fresh: { [string]: string } = {} -- journal news since the panel was last opened
	local optimistic: { string }? = nil -- Equipped as the server just said yes to it, until the next snapshot
	local busy = false

	local function rarityInfo(rarity: string): any
		return rawget(data.Rarities, rarity) or rawget(data.Rarities, "Common")
	end

	local function nightRush(): boolean
		return BeltPure.nightRush(Workspace:GetAttribute("NightRush"), Workspace:GetAttribute("IsNight"))
	end

	local modal = Hud.modal(ctx, {
		Name = "Nurses",
		Title = "👩‍⚕️ Journal",
		Accent = ACCENT,
		MaxSize = Vector2.new(780, 620),
	})

	--------------------------------------------------------------------------------------------------------------
	-- The header's completion pill
	--------------------------------------------------------------------------------------------------------------
	local title = modal.Panel:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Size = UDim2.new(1, -(SLOT + Theme.Size.Gap + PILL_WIDTH + Theme.Size.Gap), 0, SLOT)
		title.TextScaled = true
		title.TextWrapped = false
		textLimit(title, Theme.TextSize.Title)
	end
	local pill = frame({
		Name = "Completion",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(SLOT + Theme.Size.Gap), 0, 8),
		Size = UDim2.fromOffset(PILL_WIDTH, 40),
		BackgroundColor3 = Theme.Colors.Paper,
		ZIndex = 2,
		Parent = modal.Panel,
	})
	Kit.corner(pill, 20)
	Kit.stroke(pill, Theme.Colors.Outline, Theme.Size.Stroke)
	pill.ClipsDescendants = true
	local pillFill = frame({
		Name = "Fill",
		BackgroundColor3 = Kit.lighten(Theme.Colors.Cash, 0.05),
		Size = UDim2.fromScale(0, 1),
		ZIndex = 2,
		Parent = pill,
	})
	Kit.corner(pillFill, 20)
	Palette.candyGradient(pillFill)
	local pillText = Kit.label({
		Name = "Percent",
		Text = "📔 0%",
		TextScaled = true,
		Outlined = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -14, 1, -10),
		ZIndex = 3,
		Parent = pill,
	})
	textLimit(pillText, 24)

	--------------------------------------------------------------------------------------------------------------
	-- The on-duty strip
	--------------------------------------------------------------------------------------------------------------
	local strip = Instance.new("ScrollingFrame")
	strip.Name = "Duty"
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.Size = UDim2.new(1, 0, 0, STRIP_HEIGHT)
	strip.CanvasSize = UDim2.new()
	strip.AutomaticCanvasSize = Enum.AutomaticSize.X
	strip.ScrollingDirection = Enum.ScrollingDirection.X
	strip.ScrollBarThickness = 0
	strip.Selectable = false
	strip.Parent = modal.Body
	local stripList = Kit.list(strip, Enum.FillDirection.Horizontal, 8)
	stripList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local stripPad = Instance.new("UIPadding")
	stripPad.PaddingLeft = UDim.new(0, 4)
	stripPad.PaddingRight = UDim.new(0, 4)
	stripPad.Parent = strip

	local dutyTile = frame({
		Name = "OnDuty",
		BackgroundColor3 = Kit.lighten(ACCENT, 0.08),
		Size = UDim2.fromOffset(SLOT, SLOT),
		LayoutOrder = 0,
		Parent = strip,
	})
	Kit.corner(dutyTile, Theme.Size.Corner)
	Kit.stroke(dutyTile, Theme.Colors.Outline, Theme.Size.Stroke)
	Palette.candyGradient(dutyTile)
	Kit.gloss(dutyTile, 4)
	Kit.label({
		Name = "Icon",
		Text = "🩺",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.06),
		Size = UDim2.fromScale(0.6, 0.5),
		Parent = dutyTile,
	})
	local dutyCount = Kit.label({
		Name = "Count",
		Text = "0/1",
		TextScaled = true,
		Outlined = true,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.96),
		Size = UDim2.fromScale(0.9, 0.38),
		Parent = dutyTile,
	})

	--------------------------------------------------------------------------------------------------------------
	-- Tabs and pages
	--------------------------------------------------------------------------------------------------------------
	local lower = frame({
		Name = "Journal",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, STRIP_HEIGHT + 6),
		Size = UDim2.new(1, 0, 1, -(STRIP_HEIGHT + 6)),
		Parent = modal.Body,
	})
	local tabColumn = Instance.new("ScrollingFrame")
	tabColumn.Name = "Tabs"
	tabColumn.BackgroundTransparency = 1
	tabColumn.BorderSizePixel = 0
	tabColumn.Size = UDim2.new(0, TAB_WIDTH + 10, 1, 0) -- room for the selected tab's thick outline
	tabColumn.CanvasSize = UDim2.new()
	tabColumn.AutomaticCanvasSize = Enum.AutomaticSize.Y
	tabColumn.ScrollBarThickness = 0
	tabColumn.Selectable = false
	tabColumn.Parent = lower
	local tabList = Kit.list(tabColumn, Enum.FillDirection.Vertical, 8)
	tabList.VerticalAlignment = Enum.VerticalAlignment.Top
	local tabPad = Instance.new("UIPadding")
	tabPad.PaddingTop = UDim.new(0, 5)
	tabPad.PaddingBottom = UDim.new(0, 5)
	tabPad.Parent = tabColumn

	local pagesArea = frame({
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(TAB_WIDTH + 10 + Theme.Size.Gap, 0),
		Size = UDim2.new(1, -(TAB_WIDTH + 10 + Theme.Size.Gap), 1, 0),
		Parent = lower,
	})

	local pages: { [string]: Page } = {}
	local cardsById: { [string]: Card } = {}
	local current = ""
	local render: (state: Types.Snapshot) -> ()
	local equip: (nurseId: string, on: boolean, button: GuiObject?) -> ()

	local function selectPage(rarity: string)
		local page = pages[rarity]
		if not page then
			return
		end
		current = rarity
		for id, p in pages do
			local selected = id == rarity
			p.Frame.Visible = selected
			paintTab(p.Tab, selected, p.Color)
		end
		modal.Focus = page.Tab
	end

	local function newCard(parent: Instance, order: number, nurseId: string, rarity: string, color: Color3): Card
		local card = frame({
			Name = nurseId,
			LayoutOrder = order,
			BackgroundColor3 = UNSEEN_FILL,
			Parent = parent,
		})
		Kit.corner(card, 16)
		local face = frame({
			Name = "Face",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.new(1, -12, 1, -CARD_FIXED),
			BackgroundColor3 = UNSEEN_FACE,
			Parent = card,
		})
		Kit.corner(face, 12)
		local name = Kit.label({
			Name = "NurseName",
			Text = "???",
			TextScaled = true,
			Font = Theme.DisplayFont,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(6 + SLOT + 4 + 20)),
			Size = UDim2.new(1, -10, 0, 22),
			Parent = card,
		})
		textLimit(name, 20)
		local info = Kit.label({
			Name = "Info",
			Text = "",
			TextScaled = true,
			TextColor3 = Theme.Colors.InkSoft,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(6 + SLOT + 4)),
			Size = UDim2.new(1, -10, 0, 20),
			Parent = card,
		})
		textLimit(info, 18)
		local hint = Kit.label({
			Name = "Hint",
			Text = "",
			TextScaled = true,
			TextColor3 = Theme.Colors.InkSoft,
			BackgroundColor3 = Theme.Colors.Card,
			BackgroundTransparency = 0,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -12, 0, SLOT),
			Parent = card,
		})
		Kit.corner(hint, 12)
		padButton(hint, 6, 14)
		textLimit(hint, 20)
		local equipButton = Kit.button({
			Name = "Equip",
			Kind = "Good",
			Text = "Equip",
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -12, 0, SLOT),
			Visible = false,
			Parent = card,
		})
		padButton(equipButton, 8, 14)
		local restButton = Kit.button({
			Name = "Unequip",
			Kind = "Quiet",
			Text = "Unequip",
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -12, 0, SLOT),
			Visible = false,
			Parent = card,
		})
		padButton(restButton, 8, 14)
		local duty = Kit.label({
			Name = "OnDuty",
			Text = "✅",
			TextScaled = true,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 2, 0, -4),
			Size = UDim2.fromOffset(28, 28),
			Visible = false,
			ZIndex = 4,
			Parent = card,
		})
		-- A red "NEW!" sticker, tipped at an angle, on news you haven't opened yet.
		local ribbon = Kit.label({
			Name = "New",
			Text = "NEW!",
			TextSize = Theme.TextSize.Small,
			TextWrapped = false,
			Outlined = true,
			BackgroundColor3 = Theme.Colors.Dot,
			BackgroundTransparency = 0,
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.fromOffset(58, 26),
			Rotation = -8,
			Visible = false,
			ZIndex = 4,
			Parent = card,
		})
		Kit.corner(ribbon, 13)
		Kit.stroke(ribbon, Theme.Colors.Outline, 2.5)

		local entry: Card = {
			Id = nurseId,
			Rarity = rarity,
			Color = color,
			Frame = card,
			Face = face,
			Name = name,
			Info = info,
			Hint = hint,
			Equip = equipButton,
			Rest = restButton,
			Duty = duty,
			Ribbon = ribbon,
			Shown = "",
			StopFrame = nil,
		}
		equipButton.Activated:Connect(function()
			equip(nurseId, true, equipButton)
		end)
		restButton.Activated:Connect(function()
			equip(nurseId, false, restButton)
		end)
		return entry
	end

	-- Unseen: a flat grey card, a soft outline and a dark silhouette. Seen: the rarity frame, the creature greyed
	-- out. Hired: a white card in its rarity frame, the creature in full colour on its rarity's tint, with a cap.
	local function setFace(card: Card, look: any, shown: string)
		if card.Shown == shown then
			return
		end
		card.Shown = shown
		local face = card.Face
		face:ClearAllChildren()
		Kit.corner(face, 12)
		local dark = shown == "Unseen"
		local portrait = Hud.portrait(look, dark)
		portrait.AnchorPoint = Vector2.new(0.5, 0.5)
		portrait.Position = UDim2.fromScale(0.5, 0.5)
		portrait.Size = UDim2.fromScale(0.95, 0.95)
		portrait.Parent = face
		if not dark then
			addCap(portrait, card.Color)
		end

		local stop = card.StopFrame
		if stop then
			stop()
			card.StopFrame = nil
		end
		local plain = card.Frame:FindFirstChild("Plain")
		if plain then
			plain:Destroy()
		end
		if dark then
			local stroke = Kit.stroke(card.Frame, Theme.Colors.Outline, 2)
			stroke.Name = "Plain"
			stroke.Transparency = 0.6
			card.Frame.BackgroundColor3 = UNSEEN_FILL
			face.BackgroundColor3 = UNSEEN_FACE
			card.Name.TextColor3 = Theme.Colors.InkSoft
			return
		end
		card.StopFrame = Kit.rarityFrame(card.Frame, card.Rarity)
		card.Frame.BackgroundColor3 = Theme.Colors.Paper
		card.Name.TextColor3 = Theme.Colors.Ink
		if shown == "Seen" then
			local frameStroke = card.Frame:FindFirstChild("RarityFrame")
			if frameStroke and frameStroke:IsA("UIStroke") then
				frameStroke.Transparency = 0.45
			end
			face.BackgroundColor3 = SEEN_FACE
			-- Greyed out: a grey veil over the creature (a sibling above the portrait).
			local veil = frame({
				Name = "Veil",
				BackgroundColor3 = Theme.Colors.Disabled,
				BackgroundTransparency = 0.45,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 8,
				Parent = face,
			})
			Kit.corner(veil, 12)
		else
			face.BackgroundColor3 = Kit.lighten(card.Color, 0.45)
			Palette.candyGradient(face)
			Kit.stroke(face, Theme.Colors.Outline, 2)
		end
	end

	local function cardGrid(parent: Instance): Frame
		local holder = frame({
			Name = "Grid",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -12, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			Parent = parent,
		})
		local layout = Instance.new("UIGridLayout")
		layout.CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP)
		layout.CellSize = UDim2.fromOffset(MIN_CARD, MIN_CARD + CARD_FIXED)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = holder
		-- As many columns as fit, cards stretched to fill the row (2 on a phone, up to 4 on a big screen).
		local function fit()
			local width = holder.AbsoluteSize.X
			if width <= 0 then
				return
			end
			local columns = math.clamp(math.floor((width + CARD_GAP) / (MIN_CARD + CARD_GAP)), 2, 4)
			local cell = math.floor((width - CARD_GAP * (columns - 1)) / columns)
			layout.CellSize = UDim2.fromOffset(cell, math.min(math.floor(cell * 0.62), 110) + CARD_FIXED)
		end
		holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		fit()
		return holder
	end

	local function pageHeader(parent: Instance, rarity: string, info: any, color: Color3): Page
		local header = frame({
			Name = "Header",
			BackgroundColor3 = Theme.Colors.Paper,
			Size = UDim2.new(1, -12, 0, HEADER_HEIGHT),
			LayoutOrder = 1,
			Parent = parent,
		})
		Kit.corner(header, 16)
		Kit.rarityFrame(header, rarity)
		local tile = frame({
			Name = "Tile",
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(44, 44),
			BackgroundColor3 = Kit.lighten(color, 0.08),
			Parent = header,
		})
		Kit.corner(tile, 12)
		Kit.stroke(tile, Theme.Colors.Outline, Theme.Size.Stroke)
		Palette.candyGradient(tile)
		Kit.gloss(tile, 4)
		Kit.label({
			Name = "Icon",
			Text = info.Icon,
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.78, 0.78),
			Parent = tile,
		})
		local note = Pure.eventNote(info)
		local name = Kit.label({
			Name = "RarityName",
			Text = info.Name,
			TextScaled = true,
			Font = Theme.DisplayFont,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(60, if note == "" then 14 else 6),
			Size = UDim2.new(1, -60 - 64, 0, 26),
			Parent = header,
		})
		textLimit(name, 24)
		if note ~= "" then
			local noteLabel = Kit.label({
				Name = "Note",
				Text = note,
				TextScaled = true,
				TextColor3 = Theme.Colors.InkSoft,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(60, 33),
				Size = UDim2.new(1, -60 - 64, 0, 18),
				Parent = header,
			})
			textLimit(noteLabel, 16)
		end
		local count = Kit.label({
			Name = "Count",
			Text = "0/0",
			TextScaled = true,
			Outlined = true,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 14),
			Size = UDim2.fromOffset(56, 26),
			Parent = header,
		})
		textLimit(count, 22)
		local track = frame({
			Name = "Track",
			BackgroundColor3 = Theme.Colors.Paper,
			Position = UDim2.fromOffset(8, 58),
			Size = UDim2.new(1, -16, 0, 14),
			Parent = header,
		})
		Kit.corner(track, 7)
		Kit.stroke(track, Theme.Colors.Outline, 2)
		local fill = frame({
			Name = "Fill",
			BackgroundColor3 = Kit.lighten(color, 0.08),
			Size = UDim2.fromScale(0, 1),
			Parent = track,
		})
		Kit.corner(fill, 7)
		Palette.candyGradient(fill)

		-- The group reward, then the 🎲 odds-now chip.
		local rowTop = 58 + 14 + 8
		local reward = frame({
			Name = "Reward",
			BackgroundColor3 = Theme.Colors.Card,
			Position = UDim2.fromOffset(8, rowTop),
			Size = UDim2.new(1, -(8 + 8 + 8 + ODDS_WIDTH), 0, SLOT),
			Parent = header,
		})
		Kit.corner(reward, 14)
		Kit.stroke(reward, Theme.Colors.Outline, 2)
		local holder = frame({
			Name = "BadgeHolder",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, 0),
			Size = UDim2.fromOffset(42, 42),
			Parent = reward,
		})
		local badge = frame({
			Name = "Badge",
			BackgroundColor3 = Theme.Colors.Paper,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
			Parent = holder,
		})
		Kit.corner(badge, 21)
		Kit.stroke(badge, Theme.Colors.Outline, Theme.Size.Stroke)
		local decor = rawget(data.Decor, info.Journal and info.Journal.Decor or "")
		local badgeIcon = Kit.label({
			Name = "Icon",
			Text = if decor then decor.Icon else "🎁",
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.7, 0.7),
			Parent = badge,
		})
		local rewardText = Kit.label({
			Name = "Text",
			Text = "🎁 " .. Pure.rewardText(info, if decor then decor.Icon else nil),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(56, 8),
			Size = UDim2.new(1, -62, 1, -16),
			Parent = reward,
		})
		textLimit(rewardText, 22)
		local odds = Kit.button({
			Name = "Odds",
			Kind = "Purple",
			Text = "🎲",
			TextScaled = true,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, rowTop),
			Size = UDim2.fromOffset(ODDS_WIDTH, SLOT),
			Parent = header,
		})
		padButton(odds, 8, 12)
		odds.Activated:Connect(function()
			ctx.fire("Open", "NurseOdds")
		end)

		return {
			Rarity = rarity,
			Color = color,
			Frame = parent :: ScrollingFrame,
			Tab = nil :: any,
			Count = count,
			Fill = fill,
			Reward = reward,
			RewardText = rewardText,
			Badge = badge,
			BadgeIcon = badgeIcon,
			Rays = nil,
			Claimed = false,
			Odds = odds,
			Cards = {},
		}
	end

	for order, rarity in rarityOrder do
		local info = rarityInfo(rarity)
		local color = hexColor(info.Color, Theme.Colors.Quiet)
		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = rarity
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
		scroll.Parent = pagesArea
		local list = Kit.list(scroll, Enum.FillDirection.Vertical, 10)
		list.VerticalAlignment = Enum.VerticalAlignment.Top
		list.HorizontalAlignment = Enum.HorizontalAlignment.Left
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 6)
		pad.PaddingBottom = UDim.new(0, 10)
		pad.PaddingLeft = UDim.new(0, 4) -- scrolling frames clip: keep the outlines whole
		pad.Parent = scroll

		local page = pageHeader(scroll, rarity, info, color)
		local grid = cardGrid(scroll)
		local index = 0
		for _, nurseId in data.Nurses.Order do
			local nurse = rawget(data.Nurses, nurseId)
			if nurse and nurse.Rarity == rarity then
				index += 1
				local card = newCard(grid, index, nurseId, rarity, color)
				table.insert(page.Cards, card)
				cardsById[nurseId] = card
			end
		end

		local tab = Kit.iconButton({
			Name = "Tab_" .. rarity,
			Icon = info.Icon,
			Caption = "0/" .. index,
			LayoutOrder = order,
			Size = UDim2.fromOffset(TAB_WIDTH, TAB_WIDTH),
			Parent = tabColumn,
		})
		local caption = childOf(tab, "Caption", "TextLabel") :: TextLabel?
		if caption then
			caption.Font = Theme.DisplayFont -- the count is a number: chunky
		end
		tab.Activated:Connect(function()
			selectPage(rarity)
		end)
		page.Tab = tab
		pages[rarity] = page
	end
	local tabs = {}
	for _, rarity in rarityOrder do
		table.insert(tabs, pages[rarity].Tab)
	end
	Hud.fitTabs(tabColumn, tabs, 8)

	--------------------------------------------------------------------------------------------------------------
	-- The roster (FOUNDATION interim until T5's Team page): who works, and a resting nurse back to work
	--------------------------------------------------------------------------------------------------------------
	local function knownNurse(nurseId: string): boolean
		return type(rawget(data.Nurses, nurseId)) == "table"
	end

	local function rebirthsNow(): number
		local rebirth = (ctx.State :: any).Rebirth
		return if type(rebirth) == "table" and type(rebirth.Count) == "number" then rebirth.Count else 0
	end

	local function slotsNow(): number
		return NurseLogic.rosterCap(rebirthsNow(), cfg)
	end

	-- Known nurses only (rawget, so "Order" is never one), like the server (Logic/Nurse.working).
	local function equippedNow(): { string }
		return optimistic or NurseLogic.working(ctx.State.Nurses, slotsNow(), knownNurse)
	end

	equip = function(nurseId: string, on: boolean, button: GuiObject?)
		if busy then
			return
		end
		local list = equippedNow()
		local slots = slotsNow()
		if on and not table.find(list, nurseId) and #list >= slots then
			ctx.toast("Roster full: sell or list one")
			Hud.shake(button)
			Hud.pop(dutyTile, 1.2)
			return
		end
		busy = true
		local textButton: TextButton? = if button and button:IsA("TextButton") then button :: TextButton else nil
		local before = if textButton then textButton.Text else ""
		if textButton then
			textButton.Text = "⏳"
		end
		if not on then
			busy = false
			if textButton then
				textButton.Text = before
			end
			ctx.toast("👩‍⚕️ Every nurse works!")
			return
		end
		-- A resting nurse back to work: SetJob with its own role (the server checks the roster has room).
		local nurse = rawget(data.Nurses, nurseId)
		local role = if nurse then nurse.Role else "Maker"
		local ok, message = Hud.ask(ctx.Remotes.SetJob, nurseId, role)
		busy = false
		if textButton then
			textButton.Text = before
		end
		if ok then
			local nextList = table.clone(list)
			table.insert(nextList, nurseId)
			optimistic = nextList
			if message ~= "" then
				ctx.toast(message)
			end
			local card = cardsById[nurseId]
			if card then
				Kit.bump(card.Frame)
			end
		else
			ctx.toast(if message ~= "" then message else "Oops! Try again.")
			Hud.shake(button)
		end
		render(ctx.State)
	end

	-- An empty slot: show the first hired nurse that's off duty (its page, and a pop on its card).
	local function pointAtBench()
		local list = equippedNow()
		local index = ctx.State.NurseIndex
		for _, rarity in rarityOrder do
			for _, card in pages[rarity].Cards do
				if Pure.mark(index, card.Id) == "Hired" and not table.find(list, card.Id) then
					selectPage(rarity)
					Hud.pop(card.Equip, 1.2)
					ctx.toast("👇 Tap Equip!")
					return
				end
			end
		end
		ctx.toast("🎠 Hire one on the belt!")
	end

	local stripKey = ""
	local function slotChip(order: number, chip: Chip): TextButton
		local button = Instance.new("TextButton")
		button.Name = "Slot_" .. order
		button.Text = ""
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.LayoutOrder = order
		button.Size = UDim2.fromOffset(SLOT, SLOT)
		Kit.corner(button, Theme.Size.Corner)
		-- Not a Kit button (its outline is the rarity frame), so it gets the press feel by hand.
		button.Activated:Connect(function()
			Hud.pop(button, 1.12)
			Hud.sound("Click")
		end)
		if chip.Kind == "Filled" then
			local nurseId = chip.NurseId :: string
			local nurse = rawget(data.Nurses, nurseId)
			local rarity = if nurse then nurse.Rarity else "Common"
			button.BackgroundColor3 = Kit.lighten(hexColor(rarityInfo(rarity).Color, Theme.Colors.Quiet), 0.55)
			Kit.rarityFrame(button, rarity)
			local portrait = Hud.portrait(if nurse then nurse.Look else nil, false)
			portrait.AnchorPoint = Vector2.new(0.5, 0.5)
			portrait.Position = UDim2.fromScale(0.5, 0.5)
			portrait.Size = UDim2.fromScale(0.92, 0.92)
			portrait.Parent = button
			local off = Kit.label({
				Name = "Off",
				Text = "✖",
				TextScaled = true,
				Outlined = true,
				BackgroundColor3 = Theme.Colors.Danger,
				BackgroundTransparency = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, -4, 0, 4),
				Size = UDim2.fromOffset(20, 20),
				ZIndex = 9,
				Parent = button,
			})
			Kit.corner(off, 10)
			Kit.stroke(off, Theme.Colors.Outline, 2)
			button.Activated:Connect(function()
				equip(nurseId, false, button)
			end)
		elseif chip.Kind == "Empty" then
			button.BackgroundColor3 = Theme.Colors.Card
			local stroke = Kit.stroke(button, Theme.Colors.Outline, 2)
			stroke.Transparency = 0.45
			Kit.label({
				Name = "Plus",
				Text = "+",
				TextScaled = true,
				Font = Theme.DisplayFont,
				TextColor3 = Theme.Colors.InkSoft,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.6, 0.6),
				Parent = button,
			})
			button.Activated:Connect(pointAtBench)
		else
			button.BackgroundColor3 = Kit.lighten(Theme.Colors.Disabled, 0.35)
			Kit.stroke(button, Theme.Colors.Outline, 2)
			Kit.label({
				Name = "Lock",
				Text = "🔒",
				TextScaled = true,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.06),
				Size = UDim2.fromScale(0.55, 0.5),
				Parent = button,
			})
			Kit.label({
				Name = "Level",
				Text = "Lv " .. tostring(chip.Level),
				TextScaled = true,
				Outlined = true,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 0.96),
				Size = UDim2.fromScale(0.9, 0.38),
				Parent = button,
			})
			button.Activated:Connect(function()
				ctx.fire("Open", "Shop", "Hospital")
			end)
		end
		button.Parent = strip
		return button
	end

	local function renderStrip(equipped: { string })
		local chips = Pure.slotChips(equipped, slotsNow())
		local parts = {}
		local filled, slots = 0, 0
		for _, chip in chips do
			table.insert(parts, chip.Kind .. ":" .. tostring(chip.NurseId or chip.Level or ""))
			if chip.Kind ~= "Locked" then
				slots += 1
			end
			if chip.Kind == "Filled" then
				filled += 1
			end
		end
		dutyCount.Text = filled .. "/" .. slots
		local key = table.concat(parts, ",")
		if key == stripKey then
			return
		end
		stripKey = key
		for _, child in strip:GetChildren() do
			if string.sub(child.Name, 1, 5) == "Slot_" then
				child:Destroy()
			end
		end
		for order, chip in chips do
			slotChip(order, chip)
		end
	end

	--------------------------------------------------------------------------------------------------------------
	-- Drawing from the Snapshot
	--------------------------------------------------------------------------------------------------------------
	local function renderCard(card: Card, state: Types.Snapshot, equipped: { string })
		local nurse = rawget(data.Nurses, card.Id)
		if not nurse then
			return
		end
		local mark = Pure.mark(state.NurseIndex, card.Id)
		setFace(card, nurse.Look, mark)
		card.Ribbon.Visible = fresh[card.Id] ~= nil
		local roleIcon = BeltPure.ROLE_ICONS[nurse.Role] or ""
		local onDuty = table.find(equipped, card.Id) ~= nil
		card.Duty.Visible = mark == "Hired" and onDuty
		local entry = if type(state.Nurses) == "table" then state.Nurses[card.Id] else nil
		if mark == "Hired" and type(entry) == "table" then
			local level = if type(entry.Level) == "number" then entry.Level else 1
			card.Name.Text = nurse.Name
			card.Info.Text = roleIcon
				.. " "
				.. Pure.levelText(entry, maxLevel)
				.. "  "
				.. BeltPure.statText(nurse.Role, nurse.Rarity, level, cfg)
			card.Equip.Visible = not onDuty
			card.Rest.Visible = onDuty
			card.Hint.Visible = false
		else
			card.Equip.Visible = false
			card.Rest.Visible = false
			card.Hint.Visible = true
			local price = BeltLogic.price(cfg, nurse.Rarity, state.Level)
			card.Hint.Text = Pure.hint(mark, rarityInfo(nurse.Rarity), price)
			if mark == "Seen" then
				card.Name.Text = nurse.Name
				card.Info.Text = roleIcon .. " " .. (Pure.ROLE_NAMES[nurse.Role] or "")
			else
				card.Name.Text = "???"
				card.Info.Text = ""
			end
		end
	end

	render = function(state: Types.Snapshot)
		local equipped = equippedNow()
		local journal = NurseLogic.journal(
			if type(state.NurseIndex) == "table" then state.NurseIndex else {},
			data.Nurses,
			data.Rarities
		)
		pillText.Text = "📔 " .. journal.Percent .. "%"
		pillFill.Size = UDim2.fromScale(math.clamp(journal.Percent / 100, 0, 1), 1)
		local oddsNow = BeltLogic.odds(cfg, nightRush(), Workspace:GetAttribute("GoldenHour") == true)
		local claimedSets = if type(state.JournalSets) == "table" then state.JournalSets else {}

		for rarity, page in pages do
			local group = journal.Groups[rarity] or { Total = 0, Seen = 0, Hired = 0, Complete = false }
			page.Count.Text = group.Hired .. "/" .. group.Total
			page.Fill.Size = UDim2.fromScale(if group.Total > 0 then group.Hired / group.Total else 0, 1)
			local caption = page.Tab:FindFirstChild("Caption")
			if caption and caption:IsA("TextLabel") then
				caption.Text = if group.Complete then "✅" else group.Hired .. "/" .. group.Total
			end
			local news = false
			for _, card in page.Cards do
				if fresh[card.Id] then
					news = true
				end
				renderCard(card, state, equipped)
			end
			Kit.setDot(page.Tab, news)
			page.Odds.Text = "🎲 " .. BeltPure.percent(oddsNow[rarity])

			-- Still to earn: a faded icon on white. Earned: ✅, a gold badge on turning rays.
			local claimed = claimedSets[rarity] == true
			local info = rarityInfo(rarity)
			local decor = rawget(data.Decor, info.Journal and info.Journal.Decor or "")
			page.RewardText.Text = (if claimed then "✅ " else "🎁 ")
				.. Pure.rewardText(info, if decor then decor.Icon else nil)
			page.BadgeIcon.TextTransparency = if claimed then 0 else 0.5
			page.Badge.BackgroundColor3 = if claimed then Kit.lighten(Theme.Colors.Cash, 0.08) else Theme.Colors.Paper
			page.Reward.BackgroundColor3 = if claimed then Kit.lighten(Theme.Colors.Cash, 0.6) else Theme.Colors.Card
			local holder = page.Badge.Parent
			if claimed and not page.Rays and holder and holder:IsA("GuiObject") then
				page.Rays = Kit.rays(holder, Theme.Colors.Cash)
			end
			local rays = page.Rays
			if rays then
				rays.Visible = claimed
			end
			if claimed and not page.Claimed then
				Kit.bump(page.Badge)
			end
			page.Claimed = claimed
		end
		renderStrip(equipped)
	end

	-- Snapshots come with every cure; the panel only redraws while it's open (and once as it opens).
	ctx.onState(function(state: Types.Snapshot)
		optimistic = nil
		if modal.isOpen() then
			render(state)
		end
	end)

	-- The 🎲 chips follow Night Rush and Golden Hour.
	local function oddsChanged()
		if modal.isOpen() then
			render(ctx.State)
		end
	end
	Workspace:GetAttributeChangedSignal("GoldenHour"):Connect(oddsChanged)
	Workspace:GetAttributeChangedSignal("NightRush"):Connect(oddsChanged)
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(oddsChanged)

	--------------------------------------------------------------------------------------------------------------
	-- NEW! stamps: a little card above the 👩‍⚕️ button that flies into it
	--------------------------------------------------------------------------------------------------------------
	local stampGui: ScreenGui? = nil
	local stampQueue: { Stamp } = {}
	local stamping = false

	local function showStamp(item: Stamp)
		local nurse = rawget(data.Nurses, item.NurseId)
		if not nurse then
			return
		end
		local gui = stampGui or Kit.screen("NurseStamps", Theme.DisplayOrder.Fx)
		stampGui = gui
		local info = rarityInfo(nurse.Rarity)
		local color = hexColor(info.Color, Theme.Colors.Quiet)
		local target = Hud.target("Nurses")
		local shown = target ~= nil and target.Visible and target.AbsoluteSize.X > 0
		local origin = gui.AbsolutePosition
		local area = gui.AbsoluteSize

		local card = frame({
			Name = "Stamp",
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = Theme.Colors.Paper,
			Size = UDim2.fromOffset(STAMP_SIZE.X, STAMP_SIZE.Y),
			Visible = false,
			ZIndex = 1,
			Parent = gui,
		})
		if shown and target then
			local centre = target.AbsolutePosition + target.AbsoluteSize / 2 - origin
			local x = math.clamp(
				centre.X,
				STAMP_SIZE.X / 2 + 8,
				math.max(STAMP_SIZE.X / 2 + 8, area.X - STAMP_SIZE.X / 2 - 8)
			)
			card.Position = UDim2.fromOffset(x, target.AbsolutePosition.Y - origin.Y - 12)
		else
			card.Position = UDim2.new(1, -(STAMP_SIZE.X / 2 + 16), 1, -120)
		end
		Kit.corner(card, 18)
		Kit.rarityFrame(card, nurse.Rarity)
		local stopRays = Kit.celebrate(card, color)
		local face = frame({
			Name = "Face",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 10),
			Size = UDim2.new(1, -20, 0, 96),
			BackgroundColor3 = Kit.lighten(color, 0.45),
			ZIndex = 1,
			Parent = card,
		})
		Kit.corner(face, 12)
		Palette.candyGradient(face)
		local portrait = Hud.portrait(nurse.Look, false)
		portrait.AnchorPoint = Vector2.new(0.5, 0.5)
		portrait.Position = UDim2.fromScale(0.5, 0.5)
		portrait.Size = UDim2.fromScale(0.95, 0.95)
		portrait.Parent = face
		addCap(portrait, color)
		local name = Kit.label({
			Name = "NurseName",
			Text = nurse.Name,
			TextScaled = true,
			Font = Theme.DisplayFont,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -14, 0, 30),
			ZIndex = 1,
			Parent = card,
		})
		textLimit(name, 22)
		local ribbon = Kit.label({
			Name = "New",
			Text = if item.Kind == "Level" then "⬆️ Lv " .. tostring(item.Level or 2) else "NEW!",
			TextScaled = true,
			Outlined = true,
			BackgroundColor3 = if item.Kind == "Level" then Theme.Colors.Good else Theme.Colors.Dot,
			BackgroundTransparency = 0,
			Position = UDim2.fromOffset(-10, -12),
			Size = UDim2.fromOffset(78, 28),
			Rotation = -10,
			ZIndex = 3,
			Parent = card,
		})
		Kit.corner(ribbon, 14)
		Kit.stroke(ribbon, Theme.Colors.Outline, 2.5)
		padButton(ribbon, 6, 3)

		Kit.popIn(card)
		if item.Kind == "Seen" then
			Hud.sound("Sparkle") -- a queued stamp gets its own; the first one shares the NurseNews sparkle
		end
		task.wait(STAMP_SECONDS)

		local function finish()
			stopRays()
			card:Destroy()
		end
		if Kit.reducedMotion() or not shown or not target then
			Kit.popOut(card, finish)
			task.wait(0.2)
			return
		end
		local centre = target.AbsolutePosition + target.AbsoluteSize / 2 - origin
		local scale = card:FindFirstChild("KitScale")
		local flyInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local fly = TweenService:Create(card, flyInfo, { Position = UDim2.fromOffset(centre.X, centre.Y + 16) })
		if scale and scale:IsA("UIScale") then
			TweenService:Create(scale, flyInfo, { Scale = 0.15 }):Play()
		end
		fly:Play()
		fly.Completed:Wait()
		finish()
		Hud.pop(target, 1.2)
	end

	local function stamp(nurseId: string, kind: string, level: number?)
		if not TutorialLogic.isDone(ctx.State.Tutorial) or modal.isOpen() then
			return
		end
		if #stampQueue >= STAMP_QUEUE_MAX then
			return
		end
		table.insert(stampQueue, { NurseId = nurseId, Kind = kind, Level = level })
		if stamping then
			return
		end
		stamping = true
		task.spawn(function()
			while #stampQueue > 0 do
				local item = table.remove(stampQueue, 1) :: Stamp
				if not modal.isOpen() then
					local ok, err = pcall(showStamp, item)
					if not ok then
						warn("[NursePanel] stamp failed: " .. tostring(err))
					end
				end
			end
			stamping = false
		end)
	end

	--------------------------------------------------------------------------------------------------------------
	-- News, opening and closing
	--------------------------------------------------------------------------------------------------------------
	ctx.on("NurseNews", function(info: any)
		if type(info) ~= "table" or type(info.NurseId) ~= "string" or not rawget(data.Nurses, info.NurseId) then
			return
		end
		if Pure.noteNews(fresh, info) then
			ctx.fire("NursesNew", Pure.count(fresh))
		end
		if info.Kind == "Seen" then
			stamp(info.NurseId, "Seen", nil)
		elseif info.Kind == "Hired" and info.New ~= true then
			stamp(info.NurseId, "Level", if type(info.Level) == "number" then info.Level else nil)
		end
		if modal.isOpen() then
			render(ctx.State)
			local card = cardsById[info.NurseId]
			if card and info.Kind ~= "Equipped" then
				Hud.pop(card.Frame, 1.15)
			end
		end
	end)

	ctx.on("Open", function(name: any, tab: any)
		if name ~= "Nurses" then
			return
		end
		local target = if type(tab) == "string" and pages[tab]
			then tab
			else Pure.firstPage(fresh, data.Nurses, rarityOrder, if current ~= "" then current else nil)
		selectPage(target)
		render(ctx.State)
		modal.open()
		-- NEW! moment: the cards with news pop as the panel opens.
		local popped = false
		for _, card in pages[target].Cards do
			if fresh[card.Id] then
				Hud.pop(card.Frame, 1.15)
				popped = true
			end
		end
		if popped then
			Hud.sound("Sparkle")
		end
	end)

	-- Closing the panel counts its news as seen (the NEW! stickers go on the next open's redraw).
	ctx.on("ModalClosed", function(name: any)
		if name == "Nurses" and next(fresh) ~= nil then
			table.clear(fresh)
			ctx.fire("NursesNew", 0)
		end
	end)

	selectPage(rarityOrder[1])
end

return NursePanel
