--!strict
-- Shop (build plan Task 6): spend cash on ⚡ Upgrades, 🏠 Rooms and 🌸 Decor, and place decor in your rooms.
-- Depth update (T5): the Hospital tab, your hospital level and the next one (what it costs, what it unlocks, Level
-- up), and rooms that need a higher level (their note says "Needs 🏥 Lv 3"; a tap leads to the Hospital tab).
--   init(ctx)   opens on ctx.fire("Open", "Shop", tab?) with tab "Upgrades" | "Rooms" | "Decor" | "Hospital"
--   Shop.upgradeButton(upgradeId): TextButton?   that upgrade row's buy button (UI/Tutorial points at it)
--   Shop.tabButton(tabId): TextButton?           a tab ("Upgrades" | "Rooms" | "Decor" | "Hospital")
--   Shop.levelUpButton(): TextButton?            the Hospital tab's Level up button (for pointers)
--   Shop.Pure                                    the pure helpers below (tests/BranchUI.spec and tests/Agency.spec
--                                                load the block)
-- THE ENTRY POINTS (who opens which tab). Every one is the bus "Open" with a tab name; a tab that is still hidden
-- (R0 below) is shown first, then selected, and stays shown:
--   · the HUD's 🛒 door: ctx.fire("Open", "Shop", shopTab) with Hud's shopTab ("Rooms" | "Decor" | "Hospital" | nil,
--     the tab its dot is about; nil = the tab you had). T2's level badge uses the same path with "Hospital":
--     ctx.fire("Open", "Shop", "Hospital") opens the Shop straight on the Hospital tab, whatever the save
--   · the tutorial: "Upgrades" · a room or upgrade gated by the hospital level: its tap selects "Hospital"
-- Progression v2 (T5, build plan §C): gated upgrades say Logic/Progress.canBuyUpgrade's gate in their note ("Needs
-- 🏥 Lv 2" opens the Hospital tab on a tap; "Needs 🏢 R4" just says so); the Hospital tab has a calm Branch card: at
-- hospital Lv 5 "New branch" with its cost and Look (→ Open("Branch", "Open"), the keep/reset screen), and once you
-- have branches (or a reward waits) Quiet links into UI/BranchPanel plus a line for a card to pick or tree points to
-- spend. No dot, shine or breathing for "you can open a branch" (red line 3): the Hospital tab's dot is a level-up
-- you can afford or a branch reward to claim (Hud.shopNews.Branch).
-- Every price, lock and level shown here is read from the Snapshot and Shared/Data, for display only. Buying calls
-- Purchase(kind, id), placing calls PlaceDecor(slotKey, decorId?) and levelling up calls LevelUp(); the server
-- checks everything and answers (ok, message), which is shown as a toast (a level-up's yes is the server's Celebrate
-- screen instead, and the Shop closes so the building can be seen growing). Nothing changes on screen until the
-- server's next Snapshot.
-- Bus: fires "Purchased" (kind, id) and "DecorPlaced" (slotKey, decorId?) after the server says yes (a level-up is
-- kind "Level", id "<new level>").
-- THE CALM UI (docs/plan/2026-11-17-ui-direction.md §4 #7, R0; Joshua, memory-20261117-007 and -006):
--   R0  only what you can use now (Pure.visible): Upgrades always; Rooms once a room's gates are met (or one level
--       away) or you own one; Decor once you can afford the cheapest or own one; Hospital from Lv 2, once the next
--       level's ⭐ is met, or with a branch line (Lv 5). One tab showing = no tab column at all. Winter rooms aren't
--       listed out of season. The Branch card only from Lv 5 (or with branches)
--   Rows are a Kit.card with one Kit.artTile (the item's own Art from Shared/Data), the name (Kit.name) and ONE Soft
--       fact in words ("3 beds · 2 decor spots"). The price button (Icons.unit("Cash", price)) is the only button:
--       Primary when you can buy, the Disabled grey when short (a tap says how much more). A gate is the note
--       (Icons.needs(3), "Needs ⭐ 25") and the button shows the State badge 🔒 alone. Done is a Quiet ✅
--   The Hospital tab: the level now (its Art, name, a navy Kit.bar up the five levels, one fact line), the next level
--       (its unlocks as calm chips that wrap on a phone, then what it asks: ⭐ and 💰 as two Units) and Level up (the
--       view's one Primary; disabled it says why: "Needs ⭐ 15", or the price on grey)
--   The header meta is your cash: modal.setMeta(Hud.format(cash), Icons.Unit.Cash)
-- Buy and Level up are Primary (orange, never shining: nothing loud points at spending). Nothing here is Robux: every
-- price is in-game 💰.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Prices = require(Shared:WaitForChild("Logic"):WaitForChild("Prices"))
local LevelsLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Levels"))
local ProgressLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Progress"))
local RebirthLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Rebirth"))
local TreeLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Tree"))
local Hud = require(script.Parent.Hud)
local Icons = require(script.Parent.Icons)
local Kit = require(script.Parent.Kit)
local Modal = require(script.Parent.Modal)
local Theme = require(script.Parent.Theme)

local Shop = {}

------------------------------------------------------------------------------------------------------------------
-- Pure helpers (Progression v2): no Roblox services or types, only RebirthLogic and TreeLogic. tests/BranchUI.spec
-- loads the block between the PURE markers on its own, so keep it that way. The calm helpers read UI/Icons through
-- Pure.use (the file hands it in below; a spec hands in the same file).
------------------------------------------------------------------------------------------------------------------
-- PURE-BEGIN
local Pure = {}

local I: any = nil -- UI/Icons (Pure.use)

function Pure.use(icons: any)
	I = icons
end

export type BranchCard = {
	Show: boolean, -- at hospital Lv 5, with branches, or a reward waiting
	Title: string,
	Sub: string,
	Look: boolean, -- "Look" (the keep/reset screen): at hospital Lv 5 only
	Links: boolean, -- Cards, Tree, Themes: once there's anything to see there
	Lines: { string }, -- a reward to claim: a card to pick, tree points to spend
}

-- The branch card's words. NewBranch, YourBranches and CardWaits keep the 🏢 / 🃏 tests/BranchUI.spec pins (T5's);
-- the card draws its title without the emoji (Icons.words), the 🏢 being its art tile.
Pure.TEXT = {
	NewBranch = "🏢 New branch", -- uirules: allow TypedEmoji (pinned by tests/BranchUI.spec; drawn as words)
	YourBranches = "🏢 Your branches", -- uirules: allow TypedEmoji (pinned by tests/BranchUI.spec; drawn as words)
	Look = "Look",
	CardWaits = "🃏 A card to pick!", -- uirules: allow TypedEmoji, uirules: allow LeadEmoji (pinned by tests/BranchUI.spec)
}

local function count(value: any): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return math.max(0, math.floor(value))
end

local function commas(n: number): string
	local digits = tostring(math.floor(math.abs(n)))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return grouped
end

-- 50,000 · 1.3M past a million (as Hud.format).
function Pure.short(n: any): string
	local value = count(n)
	if value >= 1000000 then
		return (string.gsub(string.format("%.1f", value / 1000000), "%.0$", "")) .. "M"
	end
	return commas(value)
end

-- The Hospital tab's branch card. It says what a branch costs and where to look, never "you can open one now".
function Pure.branchCard(state: any, cfg: any, treeData: any): BranchCard
	local rebirth = if type(state) == "table" and type(state.Rebirth) == "table" then state.Rebirth else {}
	local branches = count(rebirth.Count)
	local settings = if type(cfg) == "table" and type(cfg.Rebirth) == "table" then cfg.Rebirth else {}
	local minLevel = math.max(1, count(settings.MinLevel or 5))
	local atTop = type(state) == "table" and count(state.Level) >= minLevel
	local offer = type(rebirth.Offer) == "table" and #rebirth.Offer > 0
	local points = count(rebirth.Points)
	local nodes = if type(treeData) == "table" then treeData.Nodes else nil
	local spendable = false
	if points > 0 and type(nodes) == "table" and type(nodes.Order) == "table" then
		for _, nodeId in nodes.Order do
			if TreeLogic.canBuy(rebirth.Tree, points, nodeId, nodes) then
				spendable = true
				break
			end
		end
	end
	local lines: { string } = {}
	if offer then
		table.insert(lines, Pure.TEXT.CardWaits)
	end
	if spendable then
		table.insert(lines, "🌳 " .. points .. (if points == 1 then " point" else " points") .. " to spend") -- uirules: allow TypedEmoji (pinned by tests/BranchUI.spec)
	end
	-- "Need": what a branch asks for, not a price (a rebirth starts ALL cash fresh; the Branch panel shows how much).
	local sub = if atTop then "Need 💰" .. Pure.short(RebirthLogic.cost(branches, cfg)) else "" -- uirules: allow TypedEmoji (pinned by tests/BranchUI.spec)
	if branches > 0 then
		sub = (if sub ~= "" then sub .. "  ·  " else "") .. "🏢 R" .. branches -- uirules: allow TypedEmoji (pinned by tests/BranchUI.spec)
	end
	return {
		Show = atTop or branches > 0 or offer or spendable,
		Title = if atTop then Pure.TEXT.NewBranch else Pure.TEXT.YourBranches,
		Sub = sub,
		Look = atTop,
		Links = branches > 0 or offer or spendable,
		Lines = lines,
	}
end

-- A gated upgrade's short gate: "Needs 🏥 Lv 2" -> "🏥 Lv 2" (Logic/Progress.canBuyUpgrade's words). Kept for
-- tests/BranchUI.spec; the calm row shows the whole message as its note instead (Pure.gateNote).
function Pure.gateText(message: string): string
	return (string.gsub(message, "^Needs ", ""))
end

-- A level's icons line (departments, 🩺 bays, 🛏️ beds, 📋 plan size). Kept for tests/BranchUI.spec; the calm card
-- says it in words instead (Pure.levelFacts).
function Pure.levelLine(row: any, departments: any): string
	local icons: { string } = {}
	for _, deptId in (if type(row) == "table" and type(row.Departments) == "table" then row.Departments else {}) do
		local dept = if type(departments) == "table" then rawget(departments, deptId) else nil
		if type(dept) == "table" then
			table.insert(icons, dept.Icon)
		end
	end
	local bays = if type(row) == "table" then count(row.Bays) else 0
	local beds = if type(row) == "table" then count(row.Beds) else 0
	local recipe = if type(row) == "table" then count(row.RecipeCap) else 0
	return table.concat(icons, " ") .. "   🩺 " .. bays .. "   🛏️ " .. beds .. "   📋 " .. recipe
end

------------------------------------------------------------------------------------------------------------------
-- The calm Shop (UI direction §4 #7, R0). Everything below reads UI/Icons through Pure.use.
------------------------------------------------------------------------------------------------------------------

Pure.TABS = { "Upgrades", "Rooms", "Decor", "Hospital" }

local function plural(n: number, one: string, many: string): string
	return tostring(n) .. " " .. (if n == 1 then one else many)
end

-- "3 beds · 2 decor spots": what a room adds, in words. `stations` is Data/Stations (their Names); a room's Adds
-- (the Cozy Ward's "+2 exam bays") replaces its beds, which are the bays' own.
function Pure.roomNote(room: any, stations: any): string
	if type(room) ~= "table" then
		return ""
	end
	local parts: { string } = {}
	for _, stationId in (if type(room.Stations) == "table" then room.Stations else {}) do
		local station = if type(stations) == "table" then rawget(stations, stationId) else nil
		if type(station) == "table" and type(station.Name) == "string" then
			table.insert(parts, station.Name)
		end
	end
	if type(room.Adds) == "string" and room.Adds ~= "" then
		table.insert(parts, room.Adds)
	elseif count(room.Beds) > 0 then
		table.insert(parts, plural(count(room.Beds), "bed", "beds"))
	end
	if count(room.DecorSlots) > 0 then
		table.insert(parts, plural(count(room.DecorSlots), "decor spot", "decor spots"))
	end
	return table.concat(parts, " · ")
end

-- A level in words: "3 exam bays · 3 ward beds · 2-step plans" (beds and plans only once there are any).
function Pure.levelFacts(row: any): string
	if type(row) ~= "table" then
		return ""
	end
	local parts = { plural(count(row.Bays), "exam bay", "exam bays") }
	if count(row.Beds) > 0 then
		table.insert(parts, plural(count(row.Beds), "ward bed", "ward beds"))
	end
	if count(row.RecipeCap) > 1 then
		table.insert(parts, tostring(count(row.RecipeCap)) .. "-step plans")
	end
	return table.concat(parts, " · ")
end

-- The price on a button: "💰 300" (THE Unit glued to its number).
function Pure.price(n: any): string
	return I.unit("Cash", Pure.short(n))
end

-- What a Stars gate says: "Needs ⭐ 25".
function Pure.needsStars(n: any): string
	return "Needs " .. I.unit("Stars", Pure.short(n))
end

-- A row as the Shop draws it: its Style (Buy | Poor | Gate | Done | Place | Locked), the button's text and the one
-- fact line. A gate is the note plus 🔒 alone on the button; the price button is the only button.
export type RowView = { Style: string, Text: string, Note: string, Hidden: boolean }

function Pure.upgradeRow(level: any, max: any, price: any, hint: any, gateOk: boolean, gateMessage: any): RowView
	local have, top = count(level), count(max)
	local hintText = if type(hint) == "string" then hint else ""
	local step = if top > 1 then "Lv " .. math.min(have, top) .. "/" .. top else ""
	local note = if step ~= "" and hintText ~= "" then step .. " · " .. hintText else step .. hintText
	if price == nil then
		return { Style = "Done", Text = I.State.Done, Note = "MAX · " .. hintText, Hidden = false }
	end
	if not gateOk then
		return { Style = "Gate", Text = I.State.Locked, Note = tostring(gateMessage or ""), Hidden = false }
	end
	return { Style = "Buy", Text = Pure.price(price), Note = note, Hidden = false }
end

-- A room row in the server's order (Logic/Progress.canBuyRoom): built, out of season (not listed), the hospital level,
-- the ⭐ gate, then the price. `cash` only picks Buy or Poor.
function Pure.roomRow(room: any, state: any, stations: any): RowView
	local s = if type(state) == "table" then state else {}
	local owned = type(s.Rooms) == "table" and s.Rooms[room.Id] == true
	if owned then
		return { Style = "Done", Text = I.State.Done, Note = Pure.roomNote(room, stations), Hidden = false }
	end
	if room.Season == "Winter" and s.IsWinter ~= true then
		return { Style = "Locked", Text = "", Note = "", Hidden = true }
	end
	local need = count(room.Level or 1)
	if need > math.max(1, count(s.Level)) then
		return { Style = "Gate", Text = I.State.Locked, Note = I.needs(need), Hidden = false }
	end
	if count(s.Stars) < count(room.StarsNeeded) then
		return { Style = "Locked", Text = I.State.Locked, Note = Pure.needsStars(room.StarsNeeded), Hidden = false }
	end
	return {
		Style = if count(s.Cash) >= count(room.Price) then "Buy" else "Poor",
		Text = Pure.price(room.Price),
		Note = Pure.roomNote(room, stations),
		Hidden = false,
	}
end

-- The Level up button and what the next level asks for: Style (Buy | Poor | Locked), the button's Text (the reason
-- when it can't: "Needs ⭐ 15", "No clinic yet"), and the two Units shown beside it (⭐ have / need, 💰 price).
export type LevelView = { Style: string, Text: string, Stars: string, StarsMet: boolean, Cash: string }

function Pure.levelUp(state: any, nextRow: any): LevelView?
	if type(nextRow) ~= "table" then
		return nil
	end
	local s = if type(state) == "table" then state else {}
	local have, need, cash = count(s.Stars), count(nextRow.Stars), count(nextRow.Cash)
	local met = have >= need
	local view = {
		Style = "Buy",
		Text = "Level up",
		Stars = if met then Pure.short(need) else Pure.short(have) .. " / " .. Pure.short(need),
		StarsMet = met,
		Cash = Pure.short(cash),
	}
	if s.PlotIndex == nil then
		view.Style, view.Text = "Locked", "No clinic yet"
	elseif not met then
		view.Style, view.Text = "Locked", Pure.needsStars(need)
	elseif count(s.Cash) < cash then
		view.Style, view.Text = "Poor", Pure.price(cash)
	end
	return view
end

-- R0: which tabs show for this save (one tab showing = no column). `data` is Shared/Data (Rooms, Decor, Levels);
-- `branch` is Pure.branchCard(...).Show. Proposals (UI direction "What a Lv 1 player sees"), as data:
--   Upgrades  always (the tutorial's first buy)
--   Rooms     you own a bought room, or one in season has its ⭐ gate met at your level or the next
--   Decor     you own decor, or you can afford the cheapest decor for sale
--   Hospital  Lv 2 and up, the next level's ⭐ is met, or a branch line shows
function Pure.visible(state: any, data: any, branch: boolean?): { [string]: boolean }
	local s = if type(state) == "table" then state else {}
	local d = if type(data) == "table" then data else {}
	local level = math.max(1, count(s.Level))
	local shown = { Upgrades = true, Rooms = false, Decor = false, Hospital = false }
	local rooms = d.Rooms
	if type(rooms) == "table" and type(rooms.Order) == "table" then
		for _, roomId in rooms.Order do
			local room = rawget(rooms, roomId)
			if type(room) == "table" and count(room.Price) > 0 then
				local owned = type(s.Rooms) == "table" and s.Rooms[roomId] == true
				local season = room.Season ~= "Winter" or s.IsWinter == true
				local near = count(room.Level or 1) <= level + 1 and count(s.Stars) >= count(room.StarsNeeded)
				if owned or (season and near) then
					shown.Rooms = true
				end
			end
		end
	end
	local decor = d.Decor
	local owned = if type(s.Decor) == "table" and type(s.Decor.Owned) == "table" then s.Decor.Owned else {}
	if next(owned) ~= nil then
		shown.Decor = true
	elseif type(decor) == "table" and type(decor.Order) == "table" then
		for _, decorId in decor.Order do
			local item = rawget(decor, decorId)
			if type(item) == "table" and type(item.Price) == "number" and count(s.Cash) >= item.Price then
				shown.Decor = true
			end
		end
	end
	local levels = d.Levels
	local nextRow = if type(levels) == "table" then levels[level + 1] else nil
	shown.Hospital = level > 1
		or branch == true
		or (type(nextRow) == "table" and count(s.Stars) >= count(nextRow.Stars))
	return shown
end

-- The unlock chips on a phone (568 x 320, the floor): each chip's width at 18 px (a generous guess: 11 px a letter,
-- 24 an emoji, 12 padding each side) and how many rows they wrap into across `width`. tests/Agency.spec checks the
-- six Lv 2 chips fit the narrowest Shop page in three rows or fewer, and that no chip is wider than the page.
Pure.CHIP_LETTER = 11
Pure.CHIP_EMOJI = 24
Pure.CHIP_PAD = 12

function Pure.chipWidth(text: string): number
	local emoji = I.count(text)
	local letters = utf8.len(I.words(text)) or #text
	return Pure.CHIP_PAD * 2 + emoji * Pure.CHIP_EMOJI + (if emoji > 0 then 4 else 0) + letters * Pure.CHIP_LETTER
end

function Pure.chipRows(texts: { string }, width: number, gap: number): number
	local rows, used = 0, 0
	for _, text in texts do
		local w = Pure.chipWidth(text)
		if rows == 0 or used + gap + w > width then
			rows += 1
			used = w
		else
			used += gap + w
		end
	end
	return rows
end
-- PURE-END

Pure.use(Icons)
Shop.Pure = Pure

local TABS = {
	{ Id = "Upgrades", Icon = "⚡", Caption = "Upgrades" },
	{ Id = "Rooms", Icon = "🏠", Caption = "Rooms" },
	{ Id = "Decor", Icon = "🌸", Caption = "Decor" },
	{ Id = "Hospital", Icon = Icons.Unit.Level, Caption = "Hospital" }, -- depth update
}
local LEVEL_BUTTON_WIDTH = 200
local TILE = Theme.Calm.ArtTile -- a row's art tile (56)
local PAD = Theme.Space.PadCard -- 12: inside a card and between cards
local NAME_HEIGHT = Theme.TextSize.Body + Theme.Space.Tight
local FACT_HEIGHT = Theme.TextSize.Caption + Theme.Space.Tight
local ROW_HEIGHT = PAD + NAME_HEIGHT + Theme.Space.Tight + FACT_HEIGHT + PAD + Theme.Space.Line -- 80
local BUY_WIDTH = 120
local TEXT_LEFT = PAD + TILE + PAD -- the name and the fact start here
local EARNED_HOW: { [string]: string } = {
	Book = "Finish a Book set",
	Story = "A friend's thank-you",
	Referral = "A friend's gift",
	Playtime = "A Doctor rank",
	Journal = "Fill the Journal",
	Rebirth = "Open a branch",
}

type Row = {
	Frame: Frame,
	Tile: Frame,
	Icon: TextLabel?,
	Title: TextLabel,
	Note: TextLabel,
	Buy: TextButton,
}

-- A row's action, by role (Kit.setRole): Buy is the view's Primary; can't-yet is the Disabled look (still tappable
-- where a tap can say what it needs: Poor says how much more, Gate says what it waits for); Done is a quiet status.
type Style = { Role: string, Active: boolean }
local STYLES: { [string]: Style } = {
	Buy = { Role = "Primary", Active = true },
	Poor = { Role = "Disabled", Active = true }, -- the price on grey: a tap says how much more
	Done = { Role = "Quiet", Active = false },
	Locked = { Role = "Disabled", Active = true }, -- 🔒 on grey: a tap says what it waits for
	Place = { Role = "Secondary", Active = true },
	Busy = { Role = "Secondary", Active = false },
	-- Progression v2: an upgrade for later branches or a higher level: 🔒 on grey, its gate in the note, and a tap
	-- says why (a level gate also opens the Hospital tab).
	Gate = { Role = "Disabled", Active = true },
}

local function style(button: TextButton, name: string, text: string)
	local s = STYLES[name] or STYLES.Buy
	Kit.setRole(button, s.Role)
	button.Text = text
	button.Interactable = s.Active
end

-- Everything style() changes, so a request can put the button back exactly as it was.
type Look = { Text: string, Role: string, Interactable: boolean }

local function lookOf(button: TextButton): Look
	local role = button:GetAttribute("KitKind")
	return {
		Text = button.Text,
		Role = if type(role) == "string" then role else "Primary",
		Interactable = button.Interactable,
	}
end

local function setLook(button: TextButton, look: Look)
	Kit.setRole(button, look.Role)
	button.Text = look.Text
	button.Interactable = look.Interactable
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
	scroll.ScrollBarImageColor3 = Theme.Colors.InkSoft
	scroll.Selectable = false
	scroll.Visible = false
	local list = Kit.list(scroll, Enum.FillDirection.Vertical, Theme.Space.PadCard)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, Theme.Space.Tight)
	pad.PaddingBottom = UDim.new(0, Theme.Space.PadCard)
	pad.PaddingRight = UDim.new(0, Theme.Space.PadCard) -- clear of the scroll bar
	pad.Parent = scroll
	scroll.Parent = parent
	return scroll
end

-- The art tile's emoji label (Kit.artTile makes it when given an Icon).
local function tileIcon(tile: Frame): TextLabel?
	local found = tile:FindFirstChild("Icon")
	return if found and found:IsA("TextLabel") then found else nil
end

-- "Open" = the plain card · "Owned" = a faint green card (green = done) · "Locked" = the art fades a little.
local function setRowState(row: Row, state: string)
	row.Frame.BackgroundColor3 = if state == "Owned" then Kit.lighten(Theme.Colors.Collect, 0.86) else Theme.Colors.Card
	if row.Icon then
		row.Icon.TextTransparency = if state == "Locked" then 0.35 else 0
	end
end

-- THE row: a Kit.card (no line), the item's art tile, its name, one Soft fact, and the one button on the right.
local function makeRow(parent: Instance, order: number, icon: string, title: string): Row
	local frame = Kit.card({
		Name = "Row" .. order,
		LayoutOrder = order,
		Pad = false,
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
	})
	local tile = Kit.artTile({
		Icon = icon,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, PAD, 0.5, 0),
		Parent = frame,
	})
	local textWidth = -(TEXT_LEFT + BUY_WIDTH + PAD * 2)
	local titleLabel = Kit.name({
		Text = title,
		Position = UDim2.fromOffset(TEXT_LEFT, PAD),
		Size = UDim2.new(1, textWidth, 0, NAME_HEIGHT),
		Parent = frame,
	})
	local note = Kit.fact({
		Name = "Note",
		Text = "",
		Position = UDim2.fromOffset(TEXT_LEFT, PAD + NAME_HEIGHT + Theme.Space.Tight),
		Size = UDim2.new(1, textWidth, 0, FACT_HEIGHT),
		Parent = frame,
	})
	local buy = Kit.button({
		Name = "Buy",
		Kind = "Primary",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -PAD, 0.5, 0),
		Size = UDim2.fromOffset(BUY_WIDTH, Theme.Size.ButtonHeight),
		TextScaled = true, -- the chunky display font is wide: a long price shrinks to fit, never below 18
		Parent = frame,
	})
	Kit.textLimit(buy, Theme.TextSize.Body)
	frame.Parent = parent
	return {
		Frame = frame,
		Tile = tile,
		Icon = tileIcon(tile),
		Title = titleLabel,
		Note = note,
		Buy = buy,
	}
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

-- An unlock chip (Data/Levels Unlocks: one Art emoji and two or three words) on a calm Well fill, no line. The chip
-- row wraps (UIListLayout.Wraps), so six chips sit in rows on a phone instead of running off the card.
local function chip(parent: Instance, order: number, text: string)
	local pill = Instance.new("Frame")
	pill.Name = "Chip" .. order
	pill.LayoutOrder = order
	pill.Size = UDim2.fromOffset(0, 36)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.BackgroundColor3 = Theme.Colors.Well
	pill.BorderSizePixel = 0
	Kit.corner(pill, Theme.Radius.Small)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, Theme.Space.PadCard)
	pad.PaddingRight = UDim.new(0, Theme.Space.PadCard)
	pad.Parent = pill
	local label = Kit.label({
		Name = "Text",
		Text = text,
		TextSize = Theme.TextSize.Caption,
		TextWrapped = false,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 36),
		Parent = pill,
	})
	Kit.voice(label, "Soft")
	label.TextColor3 = Theme.Colors.Ink -- an unlock is a noun, not a hint: ink, at the Soft size
	pill.Parent = parent
end

-- A head row inside a card: the art tile, the name and one fact beside it.
local function headRow(parent: Instance, order: number, icon: string): (Frame, Frame, TextLabel, TextLabel)
	local head = Instance.new("Frame")
	head.Name = "Head"
	head.LayoutOrder = order
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, TILE)
	head.Parent = parent
	local tile = Kit.artTile({ Icon = icon, Parent = head })
	local left = TILE + PAD
	local name = Kit.name({
		Text = "",
		Position = UDim2.fromOffset(left, Theme.Space.Tight),
		Size = UDim2.new(1, -left, 0, NAME_HEIGHT),
		Parent = head,
	})
	local fact = Kit.fact({
		Text = "",
		Position = UDim2.fromOffset(left, Theme.Space.Tight + NAME_HEIGHT + Theme.Space.Tight),
		Size = UDim2.new(1, -left, 0, FACT_HEIGHT),
		Parent = head,
	})
	return head, tile, name, fact
end

function Shop.init(ctx: Types.Ctx)
	local data = ctx.Data :: any
	local modal = Hud.modal(ctx, {
		Name = "Shop",
		Title = "Shop",
		MaxSize = Vector2.new(680, 560),
	})

	--------------------------------------------------------------------------------------------------------------
	-- THE tabs (Modal.tabs) down the left (landscape phones are short, so the list gets the height), pages beside.
	-- R0: a tab shows once it has something in it (Pure.visible), and stays shown; one tab = no column.
	--------------------------------------------------------------------------------------------------------------
	local pages: { [string]: ScrollingFrame } = {}
	local current = "Upgrades"
	local revealed: { [string]: boolean } = { Upgrades = true }
	local tabSpecs = {}
	for _, tab in TABS do
		table.insert(tabSpecs, { Id = tab.Id, Icon = tab.Icon, Caption = tab.Caption, Hidden = not revealed[tab.Id] })
	end
	local tabView = Modal.tabs(modal, tabSpecs, function(id: string)
		if not pages[id] then
			return
		end
		current = id
		for tabId, scroll in pages do
			scroll.Visible = tabId == id
		end
		modal.Focus = tabs[id]
	end)
	local pagesArea = tabView.Content
	local tabButtons = tabView.Buttons
	for _, tab in TABS do
		tabs[tab.Id] = tabButtons[tab.Id]
		pages[tab.Id] = page(pagesArea, tab.Id)
	end
	local function reveal(id: string)
		if pages[id] and not revealed[id] then
			revealed[id] = true
			tabView.setVisible(id, true)
		end
	end
	-- Selects a tab, showing it first when it was hidden (the HUD may open the Shop on any tab).
	local function selectTab(id: string)
		if pages[id] then
			reveal(id)
			tabView.select(id)
		end
	end

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
		style(button, "Busy", Icons.State.Waiting)
		local ok, message = Hud.ask(remote, ...)
		busy = false
		-- Put the button back as it was; refresh restyles the rows from the newest Snapshot.
		setLook(button, before)
		if ok then
			if not quiet then
				ctx.toast(if message ~= "" then message else "Done!")
				Hud.sound("Chime")
			end
			Hud.fly(button, Icons.Party.Sparkle, nil, 6)
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
		ctx.toast("Need " .. Icons.unit("Cash", Hud.format(short)) .. " more!")
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
			-- Progression v2: a hospital-level gate leads to the Hospital tab; a branch gate just says so.
			local gateOk, gateMessage = ProgressLogic.canBuyUpgrade(state, upgradeId, data.Upgrades)
			if not gateOk then
				ctx.toast(gateMessage)
				Hud.shake(row.Buy)
				if string.find(gateMessage, ProgressLogic.LEVEL_ICON, 1, true) then
					selectTab("Hospital")
				end
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
			local price = Prices.upgradePrice(data.Upgrades, upgradeId, level)
			-- Same order as the server (Economy checks Logic/Progress.canBuyUpgrade first).
			local gateOk, gateMessage = ProgressLogic.canBuyUpgrade(state, upgradeId, data.Upgrades)
			local view = Pure.upgradeRow(level, #upgrade.Prices, price, upgrade.Hint, gateOk, gateMessage)
			row.Note.Text = view.Note
			setRowState(row, if view.Style == "Done" then "Owned" elseif view.Style == "Gate" then "Locked" else "Open")
			local styleName = view.Style
			if styleName == "Buy" and (state.Cash or 0) < (price or 0) then
				styleName = "Poor"
			end
			style(row.Buy, styleName, view.Text)
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
					ctx.toast("You need a clinic first!")
					Hud.shake(row.Buy)
					return
				end
				local needLevel = room.Level or 1
				if needLevel > (state.Level or 1) then
					-- A room for a bigger hospital: show the way there.
					ctx.toast(Icons.needs(needLevel))
					Hud.shake(row.Buy)
					selectTab("Hospital")
					return
				end
				if (state.Stars or 0) < room.StarsNeeded then
					ctx.toast(Pure.needsStars(room.StarsNeeded))
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
					Kit.bump(row.Tile) -- CureFX's NEW ROOM banner (with rays) follows
				end
			end)
			roomRows[roomId] = row
		end
	end

	local function refreshRooms(state: Types.Snapshot)
		for roomId, row in roomRows do
			local room = table.clone(data.Rooms[roomId])
			room.Id = roomId
			local view = Pure.roomRow(room, state, data.Stations)
			row.Frame.Visible = not view.Hidden -- out of season: not listed (no "Soon" row)
			row.Note.Text = view.Note
			setRowState(
				row,
				if view.Style == "Done"
					then "Owned"
					elseif view.Style == "Gate" or view.Style == "Locked" then "Locked"
					else "Open"
			)
			if not view.Hidden then
				style(row.Buy, view.Style, view.Text)
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
	local placeTitle = Kit.name({
		Name = "Title",
		Text = "",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(Theme.Size.ButtonHeight + PAD, Theme.Size.ButtonHeight / 2),
		Size = UDim2.new(1, -(Theme.Size.ButtonHeight * 2 + PAD * 3), 0, NAME_HEIGHT),
		ZIndex = 5,
		Parent = placeView,
	})
	local storeButton = Kit.button({
		Name = "PutAway",
		Kind = "Secondary",
		Text = "📦",
		TextSize = Theme.TextSize.Title,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(Theme.Size.ButtonHeight + PAD, Theme.Size.ButtonHeight),
		ZIndex = 5,
		Parent = placeView,
	})
	local slotGrid = Instance.new("ScrollingFrame")
	slotGrid.Name = "Slots"
	slotGrid.BackgroundTransparency = 1
	slotGrid.BorderSizePixel = 0
	slotGrid.Position = UDim2.fromOffset(0, Theme.Size.ButtonHeight + PAD)
	slotGrid.Size = UDim2.new(1, 0, 1, -(Theme.Size.ButtonHeight + PAD))
	slotGrid.CanvasSize = UDim2.new()
	slotGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	slotGrid.ScrollBarThickness = 8
	slotGrid.ScrollBarImageColor3 = Theme.Colors.InkSoft
	slotGrid.Selectable = false
	slotGrid.ZIndex = 5
	slotGrid.Parent = placeView
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(96, 96)
	grid.CellPadding = UDim2.fromOffset(PAD, PAD)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = slotGrid
	local gridPad = Instance.new("UIPadding")
	gridPad.PaddingTop = UDim.new(0, Theme.Space.Line)
	gridPad.PaddingLeft = UDim.new(0, Theme.Space.Line)
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
	Kit.textLimit(emptyNote, Theme.TextSize.Body)

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
		placeTitle.Text = "Where does " .. decor.Name .. " go?"
		storeButton.Visible = placedSlotOf(state, decorId) ~= nil

		for _, child in slotGrid:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		local slots = if state.PlotIndex ~= nil then Hud.decorSlots(data, state) else {}
		emptyNote.Visible = #slots == 0
		emptyNote.Text = if state.PlotIndex == nil then "No clinic yet" else "Buy a room first"

		local first: GuiObject? = nil
		for index, slot in slots do
			local room = data.Rooms[slot.RoomId]
			local here = slot.Placed and rawget(data.Decor, slot.Placed)
			local mine = slot.Placed == decorId
			-- Every spot is an Icon plate: an empty one shows this decor's own art (it goes here), a spot with other
			-- decor (a swap) shows that one, and where this one is now wears the selected tab's navy (Kit.tab) and
			-- takes no tap.
			local button = Kit.iconButton({
				Name = slot.Key,
				Kind = "Icon",
				Icon = if here then here.Icon else decor.Icon,
				Caption = room.Name .. " " .. slot.N,
				LayoutOrder = if slot.Placed then 100 + index else index, -- empty spots first
				ZIndex = 5,
				Parent = slotGrid,
			})
			if not here then
				local icon = button:FindFirstChild("Icon")
				if icon and icon:IsA("TextLabel") then
					icon.TextTransparency = 0.5 -- an empty spot: its art faded
				end
			end
			if mine then
				Kit.tab(button, true)
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
				ctx.toast(EARNED_HOW[decor.EarnedBy or ""] or "Earned, not bought")
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
			local mine = owned[decorId] == true
			-- R0: an earned-only piece is listed once you have it (no row for a thing you can't buy).
			row.Frame.Visible = mine or decor.Price ~= nil
			if mine then
				local placed = placedSlotOf(state, decorId) ~= nil
				row.Note.Text = if placed then "In your clinic" else "In storage"
				setRowState(row, "Owned")
				style(row.Buy, "Place", "Place")
			elseif decor.Price then
				row.Note.Text = ""
				setRowState(row, "Open")
				style(row.Buy, if (state.Cash or 0) >= decor.Price then "Buy" else "Poor", Pure.price(decor.Price))
			end
			-- Owned first, then what you can buy, cheapest first (Data/Decor's order).
			row.Frame.LayoutOrder = (if mine then 0 else 100) + (table.find(data.Decor.Order, decorId) or 0)
		end
	end

	--------------------------------------------------------------------------------------------------------------
	-- Hospital (depth update): your level, the way up the five levels, and the next level's cost and unlocks
	--------------------------------------------------------------------------------------------------------------
	local levels = data.Levels
	local maxLevel = LevelsLogic.max(levels)

	-- The "now" card: the level's art, its name, a navy bar up the levels and what it gives you, in words.
	local nowCard = Kit.card({ Name = "Now", LayoutOrder = 1, Parent = pages.Hospital })
	local nowList = Kit.list(nowCard, Enum.FillDirection.Vertical, Theme.Space.Line)
	nowList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	nowList.VerticalAlignment = Enum.VerticalAlignment.Top
	local _, nowTile, nowTitle, nowLevel = headRow(nowCard, 1, levels[1].Icon)
	local _, setLadder = Kit.bar({ Name = "Ladder", LayoutOrder = 2, Parent = nowCard })
	local nowStats = Kit.fact({ Name = "Stats", Text = "", LayoutOrder = 3, Parent = nowCard })

	-- The "next" card: the next level, its unlock chips, what it needs, and Level up (the view's one Primary).
	local nextCard = Kit.card({ Name = "Next", LayoutOrder = 2, Parent = pages.Hospital })
	local nextList = Kit.list(nextCard, Enum.FillDirection.Vertical, Theme.Space.PadCard)
	nextList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	nextList.VerticalAlignment = Enum.VerticalAlignment.Top
	local _, nextTile, nextTitle, nextLevelFact = headRow(nextCard, 1, levels[1].Icon)

	local chips = Instance.new("Frame")
	chips.Name = "Chips"
	chips.LayoutOrder = 2
	chips.BackgroundTransparency = 1
	chips.Size = UDim2.fromScale(1, 0)
	chips.AutomaticSize = Enum.AutomaticSize.Y
	chips.Parent = nextCard
	local chipList = Kit.list(chips, Enum.FillDirection.Horizontal, Theme.Space.Line)
	chipList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	chipList.VerticalAlignment = Enum.VerticalAlignment.Top
	chipList.Wraps = true -- six chips on a 568 px phone: rows, never off the card

	-- What it asks: ⭐ (a gate, not spent) and 💰 (spent), each a Unit glued to its number.
	local needs = Instance.new("Frame")
	needs.Name = "Needs"
	needs.LayoutOrder = 3
	needs.BackgroundTransparency = 1
	needs.Size = UDim2.new(1, 0, 0, Theme.TextSize.Body + Theme.Space.Line)
	needs.Parent = nextCard
	local needsList = Kit.list(needs, Enum.FillDirection.Horizontal, Theme.Space.Section)
	needsList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	needsList.VerticalAlignment = Enum.VerticalAlignment.Center
	local starsUnit, starsAmount = Kit.unit({ Name = "Stars", Icon = Icons.Unit.Stars, Parent = needs })
	starsUnit.LayoutOrder = 1
	local cashUnit, cashAmount = Kit.unit({ Name = "Cash", Icon = Icons.Unit.Cash, Parent = needs })
	cashUnit.LayoutOrder = 2

	local foot = Instance.new("Frame")
	foot.Name = "Foot"
	foot.LayoutOrder = 4
	foot.BackgroundTransparency = 1
	foot.Size = UDim2.new(1, 0, 0, Theme.Size.ButtonHeight)
	foot.Parent = nextCard
	local levelUp = Kit.button({
		Name = "LevelUp",
		Kind = "Primary", -- never shines: nothing loud points at spending
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(1, 0, 0, Theme.Size.ButtonHeight),
		TextScaled = true,
		Parent = foot,
	})
	Kit.textLimit(levelUp, Theme.TextSize.Body)
	local levelLimit = Instance.new("UISizeConstraint")
	levelLimit.MaxSize = Vector2.new(LEVEL_BUTTON_WIDTH, Theme.Size.ButtonHeight)
	levelLimit.Parent = levelUp
	levelButton = levelUp

	local shownChipsFor = -1 -- the level whose chips are on the card

	local function setTile(tile: Frame, icon: string)
		local label = tileIcon(tile)
		if label then
			label.Text = icon
		end
	end

	local function refreshHospital(state: Types.Snapshot)
		local level = LevelsLogic.clamp(levels, state.Level)
		local row = LevelsLogic.row(levels, level)
		setTile(nowTile, row.Icon)
		nowTitle.Text = row.Name
		nowLevel.Text = Icons.level(level) .. " of " .. maxLevel
		setLadder(if maxLevel > 1 then (level - 1) / (maxLevel - 1) else 1, level >= maxLevel)
		nowStats.Text = Pure.levelFacts(row)

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
		chips.Visible = nextRow ~= nil and #nextRow.Unlocks > 0
		needs.Visible = nextRow ~= nil
		foot.Visible = nextRow ~= nil
		local view = Pure.levelUp(state, nextRow)
		if not nextRow or not view then
			setTile(nextTile, Icons.State.Done)
			nextTitle.Text = "Top level"
			nextLevelFact.Text = "Your hospital is as big as it gets"
			return
		end
		setTile(nextTile, nextRow.Icon)
		nextTitle.Text = nextRow.Name
		nextLevelFact.Text = "Next: " .. Icons.level(nextLevel)
		starsAmount.Text = view.Stars
		starsAmount.TextColor3 = if view.StarsMet then Theme.Colors.Ink else Theme.Colors.InkSoft
		cashAmount.Text = view.Cash
		style(levelUp, view.Style, view.Text)
	end

	levelUp.Activated:Connect(function()
		local state = ctx.State
		local level = LevelsLogic.clamp(levels, state.Level)
		local nextRow = LevelsLogic.nextRow(levels, level)
		if not nextRow or busy then
			return
		end
		local view = Pure.levelUp(state, nextRow)
		if state.PlotIndex == nil then
			ctx.toast("You need a clinic first!")
			Hud.shake(levelUp)
			return
		end
		if view and not view.StarsMet then
			ctx.toast(view.Text .. " (treat more patients)") -- ⭐ is a gate, not spent
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

	-- The Branch card (Progression v2): calm. At Lv 5 what a new branch costs and Look (the keep/reset screen); with
	-- branches, Quiet links into the cards, the tree and the themes, and a line for any reward waiting there.
	local branchCard = Kit.card({ Name = "Branch", LayoutOrder = 3, Parent = pages.Hospital })
	local branchList = Kit.list(branchCard, Enum.FillDirection.Vertical, Theme.Space.Line)
	branchList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	branchList.VerticalAlignment = Enum.VerticalAlignment.Top
	local _, _, branchTitle, branchSub = headRow(branchCard, 1, Icons.Door.Branches)
	local branchLines = Kit.fact({ Name = "Lines", Text = "", LayoutOrder = 2, Parent = branchCard })
	local branchButtons = Instance.new("Frame")
	branchButtons.Name = "Buttons"
	branchButtons.LayoutOrder = 3
	branchButtons.BackgroundTransparency = 1
	branchButtons.Size = UDim2.new(1, 0, 0, Theme.Size.ButtonHeight)
	branchButtons.Parent = branchCard
	local branchButtonList = Kit.list(branchButtons, Enum.FillDirection.Horizontal, Theme.Space.Line)
	branchButtonList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local function branchButton(name: string, order: number, kind: string, text: string, width: number): TextButton
		local button = Kit.button({
			Name = name,
			Kind = kind,
			Text = text,
			TextScaled = true,
			LayoutOrder = order,
			Size = UDim2.fromOffset(width, Theme.Size.ButtonHeight),
			Parent = branchButtons,
		})
		Kit.textLimit(button, Theme.TextSize.Body)
		return button
	end
	-- One Secondary way in (Look) and Quiet links: a calm way in, never a call to spend (red line 3).
	local lookButton = branchButton("Look", 1, "Secondary", Pure.TEXT.Look, 110)
	local perksLink = branchButton("Perks", 2, "Quiet", "Cards", 88)
	local treeLink = branchButton("Tree", 3, "Quiet", "Tree", 72)
	local themesLink = branchButton("Themes", 4, "Quiet", "Themes", 96)
	lookButton.Activated:Connect(function()
		ctx.fire("Open", "Branch", "Open")
	end)
	perksLink.Activated:Connect(function()
		ctx.fire("Open", "Branch", "Perks")
	end)
	treeLink.Activated:Connect(function()
		ctx.fire("Open", "Branch", "Tree")
	end)
	themesLink.Activated:Connect(function()
		ctx.fire("Open", "Branch", "Themes")
	end)

	local function refreshBranch(state: Types.Snapshot)
		local view = Pure.branchCard(state, ctx.Config, data.Tree)
		branchCard.Visible = view.Show and state.PlotIndex ~= nil
		branchTitle.Text = Icons.words(view.Title)
		branchSub.Text = view.Sub
		branchLines.Text = table.concat(view.Lines, " · ")
		branchLines.Visible = #view.Lines > 0
		lookButton.Visible = view.Look
		perksLink.Visible = view.Links
		treeLink.Visible = view.Links
		themesLink.Visible = view.Links
		branchButtons.Visible = view.Look or view.Links
		return view.Show and state.PlotIndex ~= nil
	end

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
		local branchShown = refreshBranch(state)
		-- R0: a tab arrives once it has something in it, and stays (no tab ever vanishes under you).
		for id, shown in Pure.visible(state, data, branchShown) do
			if shown then
				reveal(id)
			end
		end
		-- The header's meta: your cash (the one number every row here is about), the Unit as its own label.
		modal.setMeta(Hud.format(state.Cash or 0), Icons.Unit.Cash)
		local news = Hud.shopNews(data, state)
		Kit.setDot(tabButtons.Rooms, roomReady(state))
		Kit.setDot(tabButtons.Decor, news.Decor)
		-- A level-up you can afford, or a branch reward to claim (a card, tree points); never "you can open a branch".
		Kit.setDot(tabButtons.Hospital, levelReady(state) or news.Branch)
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
		refresh(ctx.State)
		-- The HUD's shopTab ("Hospital" from the level badge too) opens straight on that tab, shown if it was hidden.
		selectTab(if type(tab) == "string" and pages[tab] then tab else current)
		modal.open()
	end)

	selectTab(current)
end

return Shop
