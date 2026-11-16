--!strict
-- The 🏢 Branch panel: open a new branch, perk cards, the Branch Ability Tree and themes (Progression v2 build plan
-- §B3/§B5/§B9, §C T5; design §7/§8, memory-20261116-017/-019). OWNER: T5.
--   init(ctx)   opens on ctx.fire("Open", "Branch", "Open" | "Perks" | "Tree" | "Themes") (the Shop's 🏥 tab; "Perks"
--               after the Rebirth celebration). With no tab it opens where a reward waits (a perk card, then tree
--               points), else on Open. Asks OpenBranch(true), ChoosePerk(perkId), BuyNode(nodeId), ResetTree(),
--               SetTheme(themeId) and ClaimBranchNurse() through Hud.ask; the server checks everything and the next
--               Snapshot redraws. Fires "Open" ("Nurses", "Team") from the gift row's roster hint, and "Sound" (via
--               Hud: Whoosh, Nope).
--   BranchPanel.Pure   the pure helpers below (tests/BranchUI.spec loads the block on its own)
--
-- Inside (a Hud.modal Panel, purple like the Shop's 🏥 tab), tabs down the left:
--   🏢 Open    the keep/reset screen: what you keep (Logic/Rebirth.KEEP ✅), what starts fresh (RESET 🔄, with the
--             start-of-branch perk you own beside its row) and what you get (GET 🎁: +25% 💰⭐ while they still add
--             up, +3 🌳, a card, +1 nurse slot until the roster's Max, the next theme by name and the next R-unlocks,
--             Golden with its odds), the cost (Logic/Rebirth.cost) and the hospital level with ✅ when met. A big
--             "Not now" is the default focus; "🏢 Open branch!" is a Kit.holdButton (1.5 s) that asks
--             OpenBranch(true). A tap without the hold says "✋ Hold the button down!" (or what's still needed).
--   🃏 Perks   the offered cards (tap one, then ✅ Take it), "🎲 3 random cards, never repeats" and how many are
--             left (every card equally likely), or "No cards waiting"; every perk with ✅ owned; the 🎁 gift row
--             when a rebirth-only nurse waits (Claim).
--   🌳 Tree    the points to spend, three branch columns (two-up on a phone) of node tiles with rank pips, the
--             capstone lock "6 🌳 in Care", and 🔄 Reset (free, every point back) behind a small confirm.
--   🎨 Themes  every theme: ✅ On, 🎨 Pick (unlocked) or "🏢 R3" (locked: no lock icon, no "hurry").
-- No pressure (red line 3): no dots on the Open tab, no breathing or shine on Open branch, no timers. The Perks and
-- Tree tabs dot only for a reward waiting (a card to pick, points a node can take). Every motion honours
-- Kit.reducedMotion() (Kit and Hud do the tweens). Words on screen ≤ 6 (Pure.TEXT and every row; BranchUI.spec).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local Logic = Shared:WaitForChild("Logic")
local RebirthLogic = require(Logic:WaitForChild("Rebirth"))
local TreeLogic = require(Logic:WaitForChild("Tree"))
local NurseLogic = require(Logic:WaitForChild("Nurse"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local BranchPanel = {}

------------------------------------------------------------------------------------------------------------------
-- Pure helpers: no Roblox services or types; only RebirthLogic, TreeLogic and NurseLogic (the shared Logic
-- modules). tests/BranchUI.spec loads the block between the PURE markers on its own, so keep it that way.
------------------------------------------------------------------------------------------------------------------
-- PURE-BEGIN
local Pure = {}

export type Row = { Icon: string, Text: string, Note: string? }
export type Status = {
	Count: number,
	Next: number,
	Cost: number,
	MinLevel: number,
	LevelOk: boolean,
	CashOk: boolean,
	Ok: boolean,
	Message: string,
	Line: string,
	CardWaits: boolean, -- a perk card still waits: Server/Rebirth refuses OpenBranch until it's picked
}
export type PerkCard = { Id: string, Icon: string, Name: string, Text: string, Owned: boolean }
export type NodeView = {
	Id: string,
	Icon: string,
	Name: string,
	Text: string,
	Rank: number,
	Max: number,
	Cost: number,
	Capstone: boolean,
	State: string, -- "Buy" | "Poor" | "Locked" | "Max"
	Button: string,
	Message: string,
}
export type BranchView = { Id: string, Icon: string, Name: string, Spent: number, Head: string, Nodes: { string } }
export type ThemeCard = { Id: string, Icon: string, Name: string, State: string, Text: string }
export type Gift = { NurseId: string, Room: boolean }

Pure.TABS = { "Open", "Perks", "Tree", "Themes" }
Pure.HOLD_SECONDS = 1.5

-- Every fixed label on the panel (BranchUI.spec checks each is ≤ 6 words).
Pure.TEXT = {
	Title = "🏢 Branches",
	TabOpen = "Open",
	TabPerks = "Perks",
	TabTree = "Tree",
	TabThemes = "Themes",
	OpenHead = "🏢 Open a new branch",
	Keep = "✅ You keep",
	Reset = "🔄 Starts fresh",
	Get = "🎁 You get",
	NotNow = "Not now",
	OpenButton = "🏢 Open branch!",
	HoldHint = "✋ Hold the button to open",
	HoldTip = "✋ Hold the button down!",
	PickCard = "🃏 Pick a card!",
	PickCardFirst = "🃏 Pick your card first!",
	NoCards = "🃏 No cards waiting",
	NoCardsNote = "🏢 A card each new branch",
	Take = "✅ Take it",
	TapCard = "👆 Tap a card",
	AllCards = "🃏 Every card",
	TreeReset = "🔄 Reset",
	ResetTitle = "🔄 Reset tree?",
	ResetNote = "🌳 Every point comes back",
	ResetYes = "🔄 Reset",
	NothingToReset = "🌳 Nothing to reset",
	ThemesHead = "🎨 Pick a look",
	GiftHead = "🎁 A nurse waits!",
	Claim = "🎁 Claim",
	RosterFull = "Roster full: sell or list one",
	Busy = "⏳",
	Oops = "Oops! Try again.",
}

-- The keep/reset screen's RESET rows that a start-of-branch perk softens (by the row's icon; BranchUI.spec checks
-- every RESET row is here).
Pure.RESET_KINDS = {
	["💰"] = "StartCash",
	["⚡"] = "StartUpgrades",
	["🏥"] = "StartLevel",
	["🏠"] = "StartRoom",
} :: { [string]: string }

local function num(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

local function whole(value: any): number
	return math.max(0, math.floor(num(value, 0)))
end

local function row(map: any, id: any): any
	if type(map) ~= "table" or type(id) ~= "string" then
		return nil
	end
	local value = rawget(map, id)
	return if type(value) == "table" then value else nil
end

local function ordered(map: any): { string }
	local ids: { string } = {}
	if type(map) == "table" and type(map.Order) == "table" then
		for _, id in map.Order do
			if type(id) == "string" and row(map, id) then
				table.insert(ids, id)
			end
		end
	end
	return ids
end

local function rebirthOf(state: any): any
	local rebirth = if type(state) == "table" then state.Rebirth else nil
	return if type(rebirth) == "table" then rebirth else {}
end

local function countOf(state: any): number
	return whole(rebirthOf(state).Count)
end

local function listOf(value: any): { any }
	return if type(value) == "table" then value else {}
end

local function commas(n: number): string
	local digits = tostring(math.floor(math.abs(n)))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return grouped
end

-- How many words a label has: tokens with a letter in them (emoji, numbers and "·" aren't words).
function Pure.words(text: any): number
	if type(text) ~= "string" then
		return 0
	end
	local n = 0
	for token in string.gmatch(text, "%S+") do
		if string.find(token, "%a") then
			n += 1
		end
	end
	return n
end

-- 50,000 · 1.3M past a million (as Hud.format).
function Pure.short(n: any): string
	local value = whole(n)
	if value >= 1000000 then
		local text = string.format("%.1f", value / 1000000)
		text = (string.gsub(text, "%.0$", ""))
		return text .. "M"
	end
	return commas(value)
end

-- 0.02 -> "2%", 0.025 -> "2.5%".
function Pure.percent(fraction: any): string
	return string.format("%g", math.floor(num(fraction, 0) * 1000 + 0.5) / 10) .. "%"
end

function Pure.pointsText(points: any): string
	local n = whole(points)
	return "🌳 " .. n .. (if n == 1 then " point" else " points")
end

function Pure.randomText(cfg: any): string
	local s = if type(cfg) == "table" and type(cfg.Rebirth) == "table" then cfg.Rebirth else {}
	local size = math.clamp(whole(s.OfferSize or RebirthLogic.MAX_OFFER), 1, RebirthLogic.MAX_OFFER)
	return "🎲 " .. size .. " random cards, never repeats"
end

-- The Open page's facts: the next rebirth's cost, the hospital level it needs, and whether each is met (✅). The
-- line never says "hurry": only what it costs.
function Pure.status(state: any, cfg: any): Status
	local count = countOf(state)
	local cost = RebirthLogic.cost(count, cfg)
	local s = if type(cfg) == "table" and type(cfg.Rebirth) == "table" then cfg.Rebirth else {}
	local minLevel = math.max(1, math.floor(num(s.MinLevel, 5)))
	local level = if type(state) == "table" then num(state.Level, 1) else 1
	local cash = if type(state) == "table" then num(state.Cash, 0) else 0
	local levelOk = level >= minLevel
	local cashOk = cash >= cost
	local ok, message = RebirthLogic.canRebirth(state, cfg)
	-- Server/Rebirth refuses a branch while a perk card waits ("🃏 Pick your card first!"): one card per branch.
	local cardWaits = #listOf(rebirthOf(state).Offer) > 0
	if ok and cardWaits then
		ok, message = false, Pure.TEXT.PickCardFirst
	end
	local line = "🏙️ Lv "
		.. minLevel
		.. (if levelOk then " ✅" else "")
		.. "  ·  💰"
		.. Pure.short(cost)
		.. (if cashOk then " ✅" else "")
	return {
		Count = count,
		Next = count + 1,
		Cost = cost,
		MinLevel = minLevel,
		LevelOk = levelOk,
		CashOk = cashOk,
		Ok = ok,
		Message = message,
		Line = line,
		CardWaits = cardWaits,
	}
end

-- ✅ What you keep: Logic/Rebirth.KEEP as it is.
function Pure.keepRows(): { Row }
	local out: { Row } = {}
	for _, r in RebirthLogic.KEEP do
		table.insert(out, { Icon = r.Icon, Text = r.Text })
	end
	return out
end

-- 🔄 What starts fresh: Logic/Rebirth.RESET, each with the start-of-branch perk you own beside it ("🏠 Rooms ·
-- 🛁 Bath Ready").
function Pure.resetRows(state: any, perks: any): { Row }
	local owned = listOf(rebirthOf(state).Perks)
	local out: { Row } = {}
	for _, r in RebirthLogic.RESET do
		local kind = Pure.RESET_KINDS[r.Icon]
		local note: string? = nil
		for _, perkId in owned do
			local perk = row(perks, perkId)
			if perk and kind and perk.Kind == kind then
				note = perk.Icon .. " " .. perk.Name
			end
		end
		table.insert(out, { Icon = r.Icon, Text = r.Text, Note = note })
	end
	return out
end

-- 🎁 What the next rebirth gives: Logic/Rebirth.GET (the cash and stars rows only while the bonus still adds up,
-- the slot row only below the roster's Max, the look row as the new theme by name or not at all), then the
-- unlocks new at that count (Golden with its odds).
function Pure.getRows(state: any, cfg: any, themes: any): { Row }
	local count = countOf(state)
	local nextCount = count + 1
	local s = if type(cfg) == "table" and type(cfg.Rebirth) == "table" then cfg.Rebirth else {}
	local out: { Row } = {}
	for _, r in RebirthLogic.GET do
		if r.Icon == "💰" or r.Icon == "⭐" then
			local kind = if r.Icon == "⭐" then "Stars" else "Cash"
			local gain = RebirthLogic.multiplier(nextCount, cfg, kind) - RebirthLogic.multiplier(count, cfg, kind)
			if gain > 1e-9 then
				local word = if kind == "Stars" then "stars" else "cash"
				table.insert(out, { Icon = r.Icon, Text = "+" .. math.floor(gain * 100 + 0.5) .. "% " .. word })
			end
		elseif r.Icon == "🌳" then
			local points = whole(s.PointsPerRebirth)
			if points > 0 then
				table.insert(
					out,
					{ Icon = r.Icon, Text = "+" .. points .. (if points == 1 then " tree point" else " tree points") }
				)
			end
		elseif r.Icon == "👩‍⚕️" then
			if NurseLogic.rosterCap(nextCount, cfg) > NurseLogic.rosterCap(count, cfg) then
				table.insert(out, { Icon = r.Icon, Text = r.Text })
			end
		elseif r.Icon == "🎨" then
			for _, themeId in ordered(themes) do
				local theme = row(themes, themeId)
				if whole(theme.Rebirths) == nextCount then
					table.insert(out, { Icon = theme.Icon, Text = theme.Name .. " look" })
				end
			end
		else
			table.insert(out, { Icon = r.Icon, Text = r.Text })
		end
	end
	for _, unlockId in RebirthLogic.unlocks(nextCount) do
		local info = RebirthLogic.UNLOCKS[unlockId]
		if info then
			local text = info.Text
			if unlockId == "Golden" and type(cfg) == "table" then
				text ..= " (" .. Pure.percent(cfg.GoldenChance) .. ")"
			end
			table.insert(out, { Icon = info.Icon, Text = text })
		end
	end
	return out
end

-- A row as one line: "🏠 Rooms · 🛁 Bath Ready".
function Pure.rowText(r: Row): string
	local text = r.Icon .. " " .. r.Text
	if r.Note and r.Note ~= "" then
		text ..= " · " .. r.Note
	end
	return text
end

-- The cards waiting to be chosen (the Fallback "TreePoints" card too); unknown ids are skipped.
function Pure.offerCards(state: any, perks: any): { PerkCard }
	local out: { PerkCard } = {}
	for _, perkId in ipairs(listOf(rebirthOf(state).Offer)) do
		if perkId == RebirthLogic.FALLBACK then
			local fallback = if type(perks) == "table" then perks.Fallback else nil
			if type(fallback) == "table" then
				table.insert(
					out,
					{ Id = perkId, Icon = fallback.Icon, Name = fallback.Name, Text = fallback.Text, Owned = false }
				)
			end
		else
			local perk = row(perks, perkId)
			if perk then
				table.insert(out, { Id = perkId, Icon = perk.Icon, Name = perk.Name, Text = perk.Text, Owned = false })
			end
		end
	end
	return out
end

-- Every perk card in order, ✅ when owned.
function Pure.perkList(state: any, perks: any): { PerkCard }
	local owned = listOf(rebirthOf(state).Perks)
	local out: { PerkCard } = {}
	for _, perkId in ordered(perks) do
		local perk = row(perks, perkId)
		table.insert(out, {
			Id = perkId,
			Icon = perk.Icon,
			Name = perk.Name,
			Text = perk.Text,
			Owned = table.find(owned, perkId) ~= nil,
		})
	end
	return out
end

-- The odds, in words: every card you don't own is equally likely (Logic/Rebirth.offer picks evenly).
function Pure.oddsText(state: any, perks: any): string
	local owned = listOf(rebirthOf(state).Perks)
	local left = 0
	for _, perkId in ordered(perks) do
		if not table.find(owned, perkId) then
			left += 1
		end
	end
	if left >= 2 then
		return "🎲 All " .. left .. " cards equally likely"
	elseif left == 1 then
		return "🎲 1 card left"
	end
	local fallback = if type(perks) == "table" then perks.Fallback else nil
	local icon = if type(fallback) == "table" then fallback.Icon else "🌳"
	local text = if type(fallback) == "table" then fallback.Text else "+2 tree points"
	return icon .. " Every card owned: " .. text
end

-- One node tile: its rank, and what tapping it does now. Buy · Poor (not enough points) · Locked (a capstone
-- before 6 points in its branch: "6 🌳 in Care") · Max.
function Pure.nodeView(state: any, nodeId: string, treeData: any): NodeView?
	local nodes = if type(treeData) == "table" then treeData.Nodes else nil
	local def = row(nodes, nodeId)
	if not def then
		return nil
	end
	local rebirth = rebirthOf(state)
	local ranks = if type(rebirth.Tree) == "table" then rebirth.Tree else {}
	local points = whole(rebirth.Points)
	local max = math.max(1, whole(def.Max))
	local rank = math.clamp(whole(ranks[nodeId]), 0, max)
	local cost = whole(def.Cost)
	local ok, message = TreeLogic.canBuy(ranks, points, nodeId, nodes)
	local branch = row(if type(treeData) == "table" then treeData.Branches else nil, def.Branch)
	local kind: string, button: string = "Poor", ""
	if rank >= max then
		kind, button = "Max", "✅ Max"
	elseif ok then
		kind, button = "Buy", "🌳 " .. cost
	elseif def.Capstone == true and TreeLogic.spent(ranks, nodes, def.Branch) < TreeLogic.CAPSTONE_NEEDS then
		kind = "Locked"
		button = TreeLogic.CAPSTONE_NEEDS .. " 🌳 in " .. (if branch then branch.Name else tostring(def.Branch))
	else
		kind, button = "Poor", "🌳 " .. cost
	end
	return {
		Id = nodeId,
		Icon = def.Icon,
		Name = def.Name,
		Text = def.Text,
		Rank = rank,
		Max = max,
		Cost = cost,
		Capstone = def.Capstone == true,
		State = kind,
		Button = button,
		Message = message,
	}
end

-- A branch column's head ("💗 Care · 🌳 4" spent) and its nodes in Data order.
function Pure.branchView(state: any, branchId: string, treeData: any): BranchView
	local nodes = if type(treeData) == "table" then treeData.Nodes else nil
	local branch = row(if type(treeData) == "table" then treeData.Branches else nil, branchId)
	local rebirth = rebirthOf(state)
	local spent = TreeLogic.spent(if type(rebirth.Tree) == "table" then rebirth.Tree else {}, nodes, branchId)
	local ids: { string } = {}
	for _, nodeId in ordered(nodes) do
		if row(nodes, nodeId).Branch == branchId then
			table.insert(ids, nodeId)
		end
	end
	local icon = if branch then branch.Icon else ""
	local name = if branch then branch.Name else branchId
	return {
		Id = branchId,
		Icon = icon,
		Name = name,
		Spent = spent,
		Head = icon .. " " .. name .. "  ·  🌳 " .. spent,
		Nodes = ids,
	}
end

-- 🔄 Reset is offered once anything (even a node that no longer exists) would come back.
function Pure.canReset(state: any, treeData: any): boolean
	local rebirth = rebirthOf(state)
	local nodes = if type(treeData) == "table" then treeData.Nodes else nil
	return TreeLogic.refund(if type(rebirth.Tree) == "table" then rebirth.Tree else {}, nodes) > 0
end

-- Some node can take the points you have (the Tree tab's reward dot; Hud.shopNews.Branch says the same).
function Pure.treeNews(state: any, treeData: any): boolean
	local rebirth = rebirthOf(state)
	local points = whole(rebirth.Points)
	local nodes = if type(treeData) == "table" then treeData.Nodes else nil
	if points <= 0 then
		return false
	end
	for _, nodeId in ordered(nodes) do
		if TreeLogic.canBuy(rebirth.Tree, points, nodeId, nodes) then
			return true
		end
	end
	return false
end

-- Every theme: "On" (shown now: Logic/Rebirth.theme) · "Pick" (unlocked) · "Locked" ("🏢 R3": no lock icon).
function Pure.themeCards(state: any, themes: any): { ThemeCard }
	local count = countOf(state)
	local current = RebirthLogic.theme(state, themes)
	local out: { ThemeCard } = {}
	for _, themeId in ordered(themes) do
		local theme = row(themes, themeId)
		local needs = whole(theme.Rebirths)
		local kind = if themeId == current then "On" elseif needs <= count then "Pick" else "Locked"
		local text = if kind == "On" then "✅ On" elseif kind == "Pick" then "🎨 Pick" else "🏢 R" .. needs
		table.insert(out, { Id = themeId, Icon = theme.Icon, Name = theme.Name, State = kind, Text = text })
	end
	return out
end

-- The first rebirth-only nurse waiting for a roster place (Rebirth.Pending), and whether there's room now.
function Pure.gift(state: any, roster: any, cfg: any): Gift?
	for _, nurseId in ipairs(listOf(rebirthOf(state).Pending)) do
		if row(roster, nurseId) then
			local function isKnown(id: string): boolean
				return row(roster, id) ~= nil
			end
			local nurses = if type(state) == "table" then state.Nurses else nil
			local owned = NurseLogic.owned(nurses, isKnown)
			return { NurseId = nurseId, Room = owned < NurseLogic.rosterCap(countOf(state), cfg) }
		end
	end
	return nil
end

-- Where the panel opens: the tab asked for, else where a reward waits (a card, then tree points), else Open.
function Pure.firstTab(tab: any, state: any, treeData: any): string
	if type(tab) == "string" and table.find(Pure.TABS, tab) then
		return tab
	end
	if #listOf(rebirthOf(state).Offer) > 0 then
		return "Perks"
	end
	if Pure.treeNews(state, treeData) then
		return "Tree"
	end
	return "Open"
end
-- PURE-END

BranchPanel.Pure = Pure

------------------------------------------------------------------------------------------------------------------
-- Look helpers
------------------------------------------------------------------------------------------------------------------

local ACCENT = Theme.Colors.Purple
local TAB_WIDTH = Theme.Size.IconButton
local BUTTON = Theme.Size.ButtonHeight
local ROW_HEIGHT = 30
local NODE_HEIGHT = 124
local PERK_HEIGHT = 112
local OFFER_HEIGHT = 156
local THEME_HEIGHT = 150
local TABS = {
	{ Id = "Open", Icon = "🏢", Caption = Pure.TEXT.TabOpen, Color = Theme.Colors.Purple },
	{ Id = "Perks", Icon = "🃏", Caption = Pure.TEXT.TabPerks, Color = Theme.Colors.Pink },
	{ Id = "Tree", Icon = "🌳", Caption = Pure.TEXT.TabTree, Color = Theme.Colors.Good },
	{ Id = "Themes", Icon = "🎨", Caption = Pure.TEXT.TabThemes, Color = Theme.Colors.Cyan },
}
local BRANCH_COLORS: { [string]: Color3 } = {
	Care = Theme.Colors.Pink,
	Speed = Theme.Colors.Primary,
	Fortune = Theme.Colors.Good,
}
local CANDY_SWATCHES = { Theme.Colors.Pink, Theme.Colors.Cash, Theme.Colors.Cyan } -- the Candy theme: today's look

local function textLimit(label: TextLabel | TextButton, max: number, min: number?)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = max
	limit.MinTextSize = min or 12
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

local function hexColor(value: any, fallback: Color3): Color3
	if type(value) ~= "string" or value == "" then
		return fallback
	end
	local ok, color = pcall(Color3.fromHex, value)
	return if ok then color else fallback
end

local function childOf(parent: Instance, name: string, class: string): Instance?
	local found = parent:FindFirstChild(name)
	return if found and found:IsA(class) then found else nil
end

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

-- A button's colour (and its text style) after it was made: Kit.button picks them from its Kind once.
local function paint(button: TextButton, color: Color3, light: boolean)
	local fill = if light then color else Kit.lighten(color, 0.08)
	button.BackgroundColor3 = fill
	button:SetAttribute("KitColor", fill)
	button.TextColor3 = if light then Theme.Colors.Ink else Theme.Colors.OnColor
	local outline = childOf(button, "TextOutline", "UIStroke") :: UIStroke?
	if outline then
		outline.Enabled = not light
	end
end

local function scrollPage(parent: Instance, name: string): ScrollingFrame
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
	local list = Kit.list(scroll, Enum.FillDirection.Vertical, 10)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	list.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 4) -- scrolling frames clip: keep the outlines whole
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = scroll
	scroll.Parent = parent
	return scroll
end

-- A white card with the thick outline (AutomaticSize Y unless a height is given).
local function card(parent: Instance, name: string, order: number, color: Color3, height: number?): Frame
	local f = frame({
		Name = name,
		LayoutOrder = order,
		BackgroundColor3 = color,
		Size = UDim2.new(1, 0, 0, height or 0),
		AutomaticSize = if height then Enum.AutomaticSize.None else Enum.AutomaticSize.Y,
		Parent = parent,
	})
	Kit.corner(f, 16)
	Kit.stroke(f, Theme.Colors.Outline, Theme.Size.Stroke)
	return f
end

local function iconTile(parent: Instance, size: number, color: Color3, icon: string): (Frame, TextLabel)
	local tile = frame({
		Name = "Tile",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Kit.lighten(color, 0.08),
		Parent = parent,
	})
	Kit.corner(tile, math.floor(size * 0.22))
	Kit.stroke(tile, Theme.Colors.Outline, Theme.Size.Stroke)
	Palette.candyGradient(tile)
	Kit.gloss(tile, 4)
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

-- Cells as wide as fit (between `minCell` and the width), `maxColumns` at most, `height` tall.
local function fitGrid(holder: GuiObject, layout: UIGridLayout, minCell: number, maxColumns: number, height: number)
	local gap = layout.CellPadding.X.Offset
	local function fit()
		local width = holder.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local columns = math.clamp(math.floor((width + gap) / (minCell + gap)), 1, maxColumns)
		local cell = math.floor((width - gap * (columns - 1)) / columns)
		layout.CellSize = UDim2.fromOffset(cell, height)
	end
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
end

local function grid(parent: Instance, name: string, order: number, gap: number): (Frame, UIGridLayout)
	local holder = frame({
		Name = name,
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(gap, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder
	return holder, layout
end

local function clearGui(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

------------------------------------------------------------------------------------------------------------------
-- The panel
------------------------------------------------------------------------------------------------------------------

function BranchPanel.init(ctx: Types.Ctx)
	local data = ctx.Data :: any
	local cfg = ctx.Config
	local T = Pure.TEXT

	local modal = Hud.modal(ctx, {
		Name = "Branch",
		Title = T.Title,
		Accent = ACCENT,
		MaxSize = Vector2.new(760, 600),
	})

	local tabColumn = Instance.new("Frame")
	tabColumn.Name = "Tabs"
	tabColumn.BackgroundTransparency = 1
	tabColumn.Size = UDim2.new(0, TAB_WIDTH, 1, 0)
	tabColumn.Parent = modal.Body
	local tabList = Kit.list(tabColumn, Enum.FillDirection.Vertical, 8)
	tabList.VerticalAlignment = Enum.VerticalAlignment.Top

	local pagesArea = frame({
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(TAB_WIDTH + Theme.Size.Gap, 0),
		Size = UDim2.new(1, -(TAB_WIDTH + Theme.Size.Gap), 1, 0),
		Parent = modal.Body,
	})

	local tabButtons: { [string]: TextButton } = {}
	local tabColors: { [string]: Color3 } = {}
	local pages: { [string]: GuiObject } = {}
	local focusOf: { [string]: GuiObject } = {}
	local current = "Open"
	local busy = false
	local render: (state: Types.Snapshot) -> ()

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
		modal.Focus = focusOf[id] or tabButtons[id]
	end

	-- Asks the server; a "no" is a toast and a wiggle, a "yes" waits for the next Snapshot to redraw.
	local function ask(button: GuiObject?, remote: RemoteFunction, ...: any): boolean
		if busy then
			return false
		end
		busy = true
		local textButton: TextButton? = if button and button:IsA("TextButton") then button :: TextButton else nil
		local before = if textButton then textButton.Text else ""
		if textButton and before ~= "" then
			textButton.Text = T.Busy
		end
		local ok, message = Hud.ask(remote, ...)
		busy = false
		if textButton and before ~= "" then
			textButton.Text = before
		end
		if ok then
			if message ~= "" then
				ctx.toast(message)
			end
		else
			ctx.toast(if message ~= "" then message else T.Oops)
			Hud.shake(button)
		end
		render(ctx.State)
		return ok
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
			render(ctx.State)
		end)
		tabButtons[tab.Id] = button
		tabColors[tab.Id] = tab.Color
	end
	Hud.fitTabs(tabColumn, { tabButtons.Open, tabButtons.Perks, tabButtons.Tree, tabButtons.Themes }, 8)

	--------------------------------------------------------------------------------------------------------------
	-- 🏢 Open: the keep/reset screen
	--------------------------------------------------------------------------------------------------------------
	local openPage = frame({
		Name = "Open",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = pagesArea,
	})
	pages.Open = openPage
	local openScroll = scrollPage(openPage, "Scroll")
	openScroll.Size = UDim2.new(1, 0, 1, -(BUTTON + 10))

	local head = card(openScroll, "Head", 1, Kit.lighten(ACCENT, 0.86), 104)
	local headTile = iconTile(head, 64, ACCENT, "🏢")
	headTile.AnchorPoint = Vector2.new(0, 0.5)
	headTile.Position = UDim2.new(0, 12, 0.5, 0)
	local headTitle = Kit.label({
		Name = "Title",
		Text = T.OpenHead,
		TextScaled = true,
		Font = Theme.DisplayFont,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(88, 10),
		Size = UDim2.new(1, -98, 0, 30),
		Parent = head,
	})
	textLimit(headTitle, Theme.TextSize.Body)
	local headStatus = Kit.label({
		Name = "Status",
		Text = "",
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(88, 44),
		Size = UDim2.new(1, -98, 0, 26),
		Parent = head,
	})
	textLimit(headStatus, 22)
	local headHint = Kit.label({
		Name = "Hint",
		Text = T.HoldHint,
		TextScaled = true,
		TextColor3 = Theme.Colors.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(88, 74),
		Size = UDim2.new(1, -98, 0, 20),
		Parent = head,
	})
	textLimit(headHint, 18)

	-- Three columns (stacked on a narrow screen): ✅ keep · 🔄 starts fresh · 🎁 you get.
	local columns = frame({
		Name = "Columns",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = openScroll,
	})
	local columnList = Kit.list(columns, Enum.FillDirection.Horizontal, 8)
	columnList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	columnList.VerticalAlignment = Enum.VerticalAlignment.Top

	type Column = { Frame: Frame, Rows: Frame }
	local function newColumn(name: string, order: number, title: string, color: Color3): Column
		local f = frame({
			Name = name,
			LayoutOrder = order,
			BackgroundColor3 = Kit.lighten(color, 0.86),
			Size = UDim2.new(1 / 3, -6, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = columns,
		})
		Kit.corner(f, 14)
		Kit.stroke(f, Theme.Colors.Outline, 2.5)
		Kit.pad(f, 8)
		local list = Kit.list(f, Enum.FillDirection.Vertical, 4)
		list.HorizontalAlignment = Enum.HorizontalAlignment.Left
		list.VerticalAlignment = Enum.VerticalAlignment.Top
		local header = Kit.label({
			Name = "Head",
			Text = title,
			TextScaled = true,
			Outlined = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 0,
			Size = UDim2.new(1, 0, 0, 32),
			Parent = f,
		})
		textLimit(header, 24)
		local rows = frame({
			Name = "Rows",
			LayoutOrder = 1,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = f,
		})
		local rowList = Kit.list(rows, Enum.FillDirection.Vertical, 2)
		rowList.HorizontalAlignment = Enum.HorizontalAlignment.Left
		rowList.VerticalAlignment = Enum.VerticalAlignment.Top
		return { Frame = f, Rows = rows }
	end
	local keepColumn = newColumn("Keep", 1, T.Keep, Theme.Colors.Good)
	local resetColumn = newColumn("Reset", 2, T.Reset, Theme.Colors.Primary)
	local getColumn = newColumn("Get", 3, T.Get, Theme.Colors.Cash)
	local function fitColumns()
		local width = columns.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local wide = width >= 480
		columnList.FillDirection = if wide then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
		for _, column in { keepColumn, resetColumn, getColumn } do
			column.Frame.Size = if wide then UDim2.new(1 / 3, -6, 0, 0) else UDim2.fromScale(1, 0)
		end
	end
	columns:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitColumns)
	fitColumns()

	local function fillRows(column: Column, rows: { Row })
		clearGui(column.Rows)
		for index, r in rows do
			local label = Kit.label({
				Name = "Row" .. index,
				Text = Pure.rowText(r),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = index,
				Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
				Parent = column.Rows,
			})
			textLimit(label, 20)
		end
	end

	-- The foot: a big "Not now" (the default focus) and the hold-to-open button.
	local foot = frame({
		Name = "Foot",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, -14, 0, BUTTON),
		Parent = openPage,
	})
	local notNow = Kit.button({
		Name = "NotNow",
		Kind = "Secondary",
		Text = T.NotNow,
		TextScaled = true,
		Size = UDim2.new(0.55, -5, 1, 0),
		Parent = foot,
	})
	textLimit(notNow, Theme.TextSize.Body)
	local openButton = Kit.button({
		Name = "OpenBranch",
		Kind = "Purple",
		Text = T.OpenButton,
		TextScaled = true,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.45, -5, 1, 0),
		Parent = foot,
	})
	textLimit(openButton, Theme.TextSize.Body)
	focusOf.Open = notNow
	notNow.Activated:Connect(function()
		modal.close()
	end)

	local justHeld = false
	openButton.InputBegan:Connect(function()
		justHeld = false
	end)
	Kit.holdButton(openButton, Pure.HOLD_SECONDS, function()
		local status = Pure.status(ctx.State, cfg)
		if busy or not status.Ok then
			return -- the release's Activated says what's still needed
		end
		justHeld = true
		if ask(openButton, ctx.Remotes.OpenBranch, true) then
			modal.close() -- the server's Rebirth celebration comes next, then "Pick a card!"
		end
	end)
	openButton.Activated:Connect(function()
		if justHeld then
			justHeld = false
			return
		end
		local status = Pure.status(ctx.State, cfg)
		if status.CardWaits then
			ctx.toast(T.PickCardFirst)
			selectTab("Perks") -- the waiting card, one tap away
			return
		end
		ctx.toast(if status.Ok then T.HoldTip else status.Message)
		Hud.shake(openButton)
	end)

	local openKey = ""
	local function renderOpen(state: Types.Snapshot)
		local status = Pure.status(state, cfg)
		headStatus.Text = "🏢 " .. status.Next .. "  ·  " .. status.Line
		paint(openButton, if status.Ok then Theme.Colors.Purple else Theme.Colors.Disabled, false)
		local keep = Pure.keepRows()
		local reset = Pure.resetRows(state, data.Perks)
		local get = Pure.getRows(state, cfg, data.Themes)
		local parts = {}
		for _, list in { keep, reset, get } do
			for _, r in list do
				table.insert(parts, Pure.rowText(r))
			end
			table.insert(parts, "|")
		end
		local key = table.concat(parts, ";")
		if key ~= openKey then
			openKey = key
			fillRows(keepColumn, keep)
			fillRows(resetColumn, reset)
			fillRows(getColumn, get)
		end
	end

	--------------------------------------------------------------------------------------------------------------
	-- 🃏 Perks
	--------------------------------------------------------------------------------------------------------------
	local perksPage = scrollPage(pagesArea, "Perks")
	perksPage.Visible = false
	pages.Perks = perksPage

	-- The gift row: a rebirth-only nurse waiting for a roster place.
	local giftRow = card(perksPage, "Gift", 1, Kit.lighten(Theme.Colors.Good, 0.82), 76)
	giftRow.Visible = false
	local giftFace = frame({
		Name = "Face",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = Theme.Colors.Paper,
		Parent = giftRow,
	})
	Kit.corner(giftFace, 14)
	local giftText = Kit.label({
		Name = "Text",
		Text = T.GiftHead,
		TextScaled = true,
		Font = Theme.DisplayFont,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(76, 10),
		Size = UDim2.new(1, -(76 + 150 + 12), 1, -20),
		Parent = giftRow,
	})
	textLimit(giftText, Theme.TextSize.Body)
	local claim = Kit.button({
		Name = "Claim",
		Kind = "Good",
		Text = T.Claim,
		TextScaled = true,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(150, BUTTON),
		Parent = giftRow,
	})
	textLimit(claim, Theme.TextSize.Body)
	local giftShown = ""
	claim.Activated:Connect(function()
		local gift = Pure.gift(ctx.State, data.Nurses, cfg)
		if not gift then
			return
		end
		if not gift.Room then
			ctx.toast(T.RosterFull)
			Hud.shake(claim)
			ctx.fire("Open", "Nurses", "Team") -- the roster, where selling or listing makes room
			return
		end
		if ask(claim, ctx.Remotes.ClaimBranchNurse) then
			Kit.bump(giftRow)
		end
	end)

	-- The offer: the cards waiting, the odds in words, Take it.
	local offerCard = card(perksPage, "Offer", 2, Theme.Colors.Paper)
	Kit.pad(offerCard, 10)
	local offerList = Kit.list(offerCard, Enum.FillDirection.Vertical, 6)
	offerList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	offerList.VerticalAlignment = Enum.VerticalAlignment.Top
	local offerTitle = Kit.label({
		Name = "Title",
		Text = T.PickCard,
		TextScaled = true,
		Font = Theme.DisplayFont,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 32),
		Parent = offerCard,
	})
	textLimit(offerTitle, Theme.TextSize.Title)
	local offerRandom = Kit.label({
		Name = "Random",
		Text = Pure.randomText(cfg),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 24),
		Parent = offerCard,
	})
	textLimit(offerRandom, 20)
	local offerOdds = Kit.label({
		Name = "Odds",
		Text = "",
		TextScaled = true,
		TextColor3 = Theme.Colors.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = offerCard,
	})
	textLimit(offerOdds, 18)
	local offerCards, offerGrid = grid(offerCard, "Cards", 4, 10)
	fitGrid(offerCards, offerGrid, 150, 3, OFFER_HEIGHT)
	local takeRow = frame({
		Name = "TakeRow",
		LayoutOrder = 5,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, BUTTON),
		Parent = offerCard,
	})
	local take = Kit.button({
		Name = "Take",
		Kind = "Good",
		Text = T.TapCard,
		TextScaled = true,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.6, 1),
		Parent = takeRow,
	})
	textLimit(take, Theme.TextSize.Body)

	local allHead = Kit.label({
		Name = "AllHead",
		Text = T.AllCards,
		TextScaled = true,
		Outlined = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 32),
		Parent = perksPage,
	})
	textLimit(allHead, Theme.TextSize.Body)
	local allCards, allGrid = grid(perksPage, "All", 4, 8)
	fitGrid(allCards, allGrid, 140, 4, PERK_HEIGHT)

	local selectedPerk: string? = nil
	local offerKey = ""
	local offerButtons: { [string]: TextButton } = {}

	local function paintOffer()
		for perkId, button in offerButtons do
			local chosen = perkId == selectedPerk
			paint(button, if chosen then Kit.lighten(Theme.Colors.Pink, 0.55) else Theme.Colors.Paper, true)
			local border = borderOf(button)
			if border then
				border.Thickness = if chosen then Theme.Size.StrokeLarge + 1 else Theme.Size.Stroke
			end
		end
		local ready = selectedPerk ~= nil and offerButtons[selectedPerk] ~= nil
		take.Text = if ready then T.Take else T.TapCard
		paint(take, if ready then Theme.Colors.Good else Theme.Colors.Disabled, false)
	end

	-- A perk face: the icon big, its name and its words.
	local function perkFace(button: GuiObject, perk: PerkCard, iconShare: number)
		Kit.label({
			Name = "Icon",
			Text = perk.Icon,
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.new(1, -16, iconShare, -6),
			ZIndex = 2,
			Parent = button,
		})
		local name = Kit.label({
			Name = "PerkName",
			Text = perk.Name,
			TextScaled = true,
			Font = Theme.DisplayFont,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, iconShare, 2),
			Size = UDim2.new(1, -12, 0.2, 0),
			ZIndex = 2,
			Parent = button,
		})
		textLimit(name, 20)
		local words = Kit.label({
			Name = "Words",
			Text = perk.Text,
			TextScaled = true,
			TextColor3 = Theme.Colors.InkSoft,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -12, 1 - iconShare - 0.2, -10),
			ZIndex = 2,
			Parent = button,
		})
		textLimit(words, 18)
	end

	take.Activated:Connect(function()
		local perkId = selectedPerk
		if not perkId or not offerButtons[perkId] then
			ctx.toast(T.TapCard)
			Hud.shake(take)
			return
		end
		if ask(take, ctx.Remotes.ChoosePerk, perkId) then
			selectedPerk = nil
			Hud.sound("Sparkle")
		end
	end)

	local allKey = ""
	local function renderPerks(state: Types.Snapshot)
		-- The gift row.
		local gift = Pure.gift(state, data.Nurses, cfg)
		giftRow.Visible = gift ~= nil
		if gift and gift.NurseId ~= giftShown then
			giftShown = gift.NurseId
			giftFace:ClearAllChildren()
			Kit.corner(giftFace, 14)
			local nurse = rawget(data.Nurses, gift.NurseId)
			local portrait = Hud.portrait(if nurse then nurse.Look else nil, false)
			portrait.AnchorPoint = Vector2.new(0.5, 0.5)
			portrait.Position = UDim2.fromScale(0.5, 0.5)
			portrait.Size = UDim2.fromScale(0.95, 0.95)
			portrait.Parent = giftFace
			if nurse then
				Kit.rarityFrame(giftFace, nurse.Rarity)
			end
		end

		-- The offer.
		local cards = Pure.offerCards(state, data.Perks)
		offerTitle.Text = if #cards > 0 then T.PickCard else T.NoCards
		offerRandom.Text = if #cards > 0 then Pure.randomText(cfg) else T.NoCardsNote
		offerOdds.Text = Pure.oddsText(state, data.Perks)
		takeRow.Visible = #cards > 0
		offerCards.Visible = #cards > 0
		local ids = {}
		for _, perk in cards do
			table.insert(ids, perk.Id)
		end
		local key = table.concat(ids, ",")
		if key ~= offerKey then
			offerKey = key
			selectedPerk = nil
			clearGui(offerCards)
			table.clear(offerButtons)
			for index, perk in cards do
				local button = Kit.button({
					Name = "Card_" .. perk.Id,
					Kind = "Card",
					LayoutOrder = index,
					Parent = offerCards,
				})
				perkFace(button, perk, 0.42)
				button.Activated:Connect(function()
					selectedPerk = perk.Id
					paintOffer()
					Kit.bump(button)
				end)
				offerButtons[perk.Id] = button
			end
		end
		paintOffer()

		-- Every card, ✅ when owned (no lock icons: the rest simply waits for a branch).
		local list = Pure.perkList(state, data.Perks)
		local allParts = {}
		for _, perk in list do
			table.insert(allParts, perk.Id .. (if perk.Owned then "+" else "-"))
		end
		local aKey = table.concat(allParts, ",")
		if aKey ~= allKey then
			allKey = aKey
			clearGui(allCards)
			for index, perk in list do
				local tile = frame({
					Name = perk.Id,
					LayoutOrder = index,
					BackgroundColor3 = if perk.Owned then Kit.lighten(Theme.Colors.Good, 0.82) else Theme.Colors.Card,
					Parent = allCards,
				})
				Kit.corner(tile, 14)
				local stroke = Kit.stroke(tile, Theme.Colors.Outline, if perk.Owned then Theme.Size.Stroke else 2)
				stroke.Transparency = if perk.Owned then 0 else 0.5
				perkFace(tile, perk, 0.36)
				if perk.Owned then
					Kit.label({
						Name = "Owned",
						Text = "✅",
						TextScaled = true,
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, 4, 0, -4),
						Size = UDim2.fromOffset(26, 26),
						ZIndex = 3,
						Parent = tile,
					})
				else
					for _, child in tile:GetChildren() do
						if child:IsA("TextLabel") then
							child.TextTransparency = 0.35
						end
					end
				end
			end
		end
	end

	--------------------------------------------------------------------------------------------------------------
	-- 🌳 Tree
	--------------------------------------------------------------------------------------------------------------
	local treePage = frame({
		Name = "Tree",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = pagesArea,
	})
	pages.Tree = treePage
	local treeTop = frame({
		Name = "Top",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -14, 0, BUTTON),
		Parent = treePage,
	})
	local pointsChip = frame({
		Name = "Points",
		BackgroundColor3 = Kit.lighten(Theme.Colors.Good, 0.08),
		Size = UDim2.new(1, -(150 + 10), 1, 0),
		Parent = treeTop,
	})
	Kit.corner(pointsChip, 18)
	Kit.stroke(pointsChip, Theme.Colors.Outline, Theme.Size.Stroke)
	Palette.candyGradient(pointsChip)
	Kit.gloss(pointsChip, 4)
	local pointsText = Kit.label({
		Name = "Text",
		Text = Pure.pointsText(0),
		TextScaled = true,
		Outlined = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -20, 1, -14),
		Parent = pointsChip,
	})
	textLimit(pointsText, Theme.TextSize.Body)
	local resetButton = Kit.button({
		Name = "Reset",
		Kind = "Quiet",
		Text = T.TreeReset,
		TextScaled = true,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(150, BUTTON),
		Parent = treeTop,
	})
	textLimit(resetButton, Theme.TextSize.Body)
	focusOf.Tree = resetButton

	local treeScroll = scrollPage(treePage, "Scroll")
	treeScroll.Position = UDim2.fromOffset(0, BUTTON + 8)
	treeScroll.Size = UDim2.new(1, 0, 1, -(BUTTON + 8))
	local treeColumns = frame({
		Name = "Columns",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = treeScroll,
	})
	local treeColumnList = Kit.list(treeColumns, Enum.FillDirection.Horizontal, 8)
	treeColumnList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	treeColumnList.VerticalAlignment = Enum.VerticalAlignment.Top

	type NodeTile = {
		Button: TextButton,
		Pips: Frame,
		Pill: TextLabel,
		PillFrame: Frame,
		Tile: Frame,
		Shown: string,
	}
	type BranchColumn = { Frame: Frame, Head: TextLabel, Nodes: { [string]: NodeTile } }
	local branchColumns: { [string]: BranchColumn } = {}
	local branchOrder: { string } = if type(data.Tree) == "table" and type(data.Tree.BranchOrder) == "table"
		then data.Tree.BranchOrder
		else {}

	local function newNodeTile(parent: Instance, order: number, nodeId: string, color: Color3): NodeTile
		local def = rawget(data.Tree.Nodes, nodeId)
		local button = Kit.button({
			Name = nodeId,
			Kind = "Card",
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, NODE_HEIGHT),
			Parent = parent,
		})
		paint(button, Theme.Colors.Paper, true)
		local tile = iconTile(button, 40, color, def.Icon)
		tile.Position = UDim2.fromOffset(8, 8)
		tile.ZIndex = 2
		local name = Kit.label({
			Name = "NodeName",
			Text = def.Name,
			TextScaled = true,
			Font = Theme.DisplayFont,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(56, 8),
			Size = UDim2.new(1, -62, 0, 24),
			ZIndex = 2,
			Parent = button,
		})
		textLimit(name, 20)
		local words = Kit.label({
			Name = "Words",
			Text = def.Text,
			TextScaled = true,
			TextColor3 = Theme.Colors.InkSoft,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(56, 34),
			Size = UDim2.new(1, -62, 0, 40),
			ZIndex = 2,
			Parent = button,
		})
		textLimit(words, 18)
		local pips = frame({
			Name = "Pips",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 10, 1, -14),
			Size = UDim2.fromOffset(0, 16),
			AutomaticSize = Enum.AutomaticSize.X,
			ZIndex = 2,
			Parent = button,
		})
		local pipList = Kit.list(pips, Enum.FillDirection.Horizontal, 5)
		pipList.HorizontalAlignment = Enum.HorizontalAlignment.Left
		local pillFrame = frame({
			Name = "Pill",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -8, 1, -8),
			Size = UDim2.new(0.58, 0, 0, 34),
			BackgroundColor3 = Theme.Colors.Good,
			ZIndex = 2,
			Parent = button,
		})
		Kit.corner(pillFrame, 17)
		Kit.stroke(pillFrame, Theme.Colors.Outline, 2.5)
		local pill = Kit.label({
			Name = "Text",
			Text = "",
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -12, 1, -8),
			ZIndex = 3,
			Parent = pillFrame,
		})
		textLimit(pill, 18)
		local nodeTile: NodeTile = {
			Button = button,
			Pips = pips,
			Pill = pill,
			PillFrame = pillFrame,
			Tile = tile,
			Shown = "",
		}
		button.Activated:Connect(function()
			local view = Pure.nodeView(ctx.State, nodeId, data.Tree)
			if not view then
				return
			end
			if view.State ~= "Buy" then
				ctx.toast(if view.State == "Max" then "Max rank!" else view.Message)
				Hud.shake(button)
				return
			end
			if ask(button, ctx.Remotes.BuyNode, nodeId) then
				Kit.bump(tile)
				Hud.sound("Node") -- Feel/Sounds' 🌳 cue (Progression v2 §B9)
			end
		end)
		return nodeTile
	end

	for index, branchId in branchOrder do
		local branch = rawget(data.Tree.Branches, branchId)
		local color = BRANCH_COLORS[branchId] or ACCENT
		local column = frame({
			Name = branchId,
			LayoutOrder = index,
			BackgroundColor3 = Kit.lighten(color, 0.84),
			Size = UDim2.new(1 / 3, -6, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = treeColumns,
		})
		Kit.corner(column, 14)
		Kit.stroke(column, Theme.Colors.Outline, 2.5)
		Kit.pad(column, 8)
		local list = Kit.list(column, Enum.FillDirection.Vertical, 8)
		list.HorizontalAlignment = Enum.HorizontalAlignment.Left
		list.VerticalAlignment = Enum.VerticalAlignment.Top
		local headLabel = Kit.label({
			Name = "Head",
			Text = if branch then branch.Icon .. " " .. branch.Name else branchId,
			TextScaled = true,
			Outlined = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 0,
			Size = UDim2.new(1, 0, 0, 32),
			Parent = column,
		})
		textLimit(headLabel, 24)
		local entry: BranchColumn = { Frame = column, Head = headLabel, Nodes = {} }
		local view = Pure.branchView(ctx.State, branchId, data.Tree)
		for order, nodeId in view.Nodes do
			entry.Nodes[nodeId] = newNodeTile(column, order, nodeId, color)
		end
		branchColumns[branchId] = entry
	end
	local function fitTree()
		local width = treeColumns.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local wide = width >= 540
		treeColumnList.FillDirection = if wide then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
		for _, column in branchColumns do
			column.Frame.Size = if wide then UDim2.new(1 / 3, -6, 0, 0) else UDim2.fromScale(1, 0)
		end
	end
	treeColumns:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitTree)
	fitTree()

	local function setPips(pips: Frame, rank: number, max: number)
		if pips:GetAttribute("Shown") == rank .. "/" .. max then
			return
		end
		pips:SetAttribute("Shown", rank .. "/" .. max)
		clearGui(pips)
		for i = 1, max do
			local dot = frame({
				Name = "Pip" .. i,
				LayoutOrder = i,
				Size = UDim2.fromOffset(14, 14),
				BackgroundColor3 = if i <= rank then Theme.Colors.Star else Theme.Colors.Paper,
				ZIndex = 2,
				Parent = pips,
			})
			Kit.corner(dot, 7)
			Kit.stroke(dot, Theme.Colors.Outline, 2)
		end
	end

	local PILL_COLORS: { [string]: Color3 } = {
		Buy = Theme.Colors.Good,
		Poor = Theme.Colors.Disabled,
		Locked = Kit.lighten(Theme.Colors.Disabled, 0.35),
		Max = Theme.Colors.Cash,
	}

	local function renderTree(state: Types.Snapshot)
		local rebirth = (state :: any).Rebirth
		local points = if type(rebirth) == "table" and type(rebirth.Points) == "number" then rebirth.Points else 0
		pointsText.Text = Pure.pointsText(points)
		local canReset = Pure.canReset(state, data.Tree)
		paint(resetButton, if canReset then Theme.Colors.Quiet else Theme.Colors.Disabled, true)
		for branchId, column in branchColumns do
			column.Head.Text = Pure.branchView(state, branchId, data.Tree).Head
			for nodeId, tile in column.Nodes do
				local view = Pure.nodeView(state, nodeId, data.Tree)
				if view then
					setPips(tile.Pips, view.Rank, view.Max)
					tile.Pill.Text = view.Button
					tile.PillFrame.BackgroundColor3 = PILL_COLORS[view.State] or Theme.Colors.Card
					tile.Pill.TextColor3 = if view.State == "Locked" then Theme.Colors.InkSoft else Theme.Colors.Ink
					paint(
						tile.Button,
						if view.State == "Max" then Kit.lighten(Theme.Colors.Cash, 0.8) else Theme.Colors.Paper,
						true
					)
					if tile.Shown ~= "" and tile.Shown ~= view.State .. view.Rank then
						Kit.bump(tile.PillFrame)
					end
					tile.Shown = view.State .. view.Rank
				end
			end
		end
	end

	-- 🔄 Reset: free and every point comes back, but it undoes your picks, so it asks first (Not now is the focus).
	local resetAsk = Hud.modal(ctx, {
		Name = "BranchReset",
		Title = T.ResetTitle,
		Accent = Theme.Colors.Good,
		Layer = "Popup",
		MaxSize = Vector2.new(440, 250),
		Scale = Vector2.new(0.8, 0.7),
	})
	local resetNote = Kit.label({
		Name = "Note",
		Text = T.ResetNote,
		TextScaled = true,
		Size = UDim2.new(1, 0, 1, -(BUTTON + 12)),
		Parent = resetAsk.Body,
	})
	textLimit(resetNote, Theme.TextSize.Body)
	local resetNo = Kit.button({
		Name = "NotNow",
		Kind = "Secondary",
		Text = T.NotNow,
		TextScaled = true,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(0.5, -5, 0, BUTTON),
		Parent = resetAsk.Body,
	})
	textLimit(resetNo, Theme.TextSize.Body)
	local resetYes = Kit.button({
		Name = "Reset",
		Kind = "Good",
		Text = T.ResetYes,
		TextScaled = true,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(0.5, -5, 0, BUTTON),
		Parent = resetAsk.Body,
	})
	textLimit(resetYes, Theme.TextSize.Body)
	resetAsk.Focus = resetNo
	resetNo.Activated:Connect(function()
		resetAsk.close()
	end)
	resetYes.Activated:Connect(function()
		if ask(resetYes, ctx.Remotes.ResetTree) then
			resetAsk.close()
			Hud.sound("Sparkle")
		end
	end)
	resetButton.Activated:Connect(function()
		if not Pure.canReset(ctx.State, data.Tree) then
			ctx.toast(T.NothingToReset)
			Hud.shake(resetButton)
			return
		end
		resetAsk.open()
	end)

	--------------------------------------------------------------------------------------------------------------
	-- 🎨 Themes
	--------------------------------------------------------------------------------------------------------------
	local themesPage = scrollPage(pagesArea, "Themes")
	themesPage.Visible = false
	pages.Themes = themesPage
	local themesHead = Kit.label({
		Name = "Head",
		Text = T.ThemesHead,
		TextScaled = true,
		Outlined = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 34),
		Parent = themesPage,
	})
	textLimit(themesHead, Theme.TextSize.Body)
	local themeCards, themeGrid = grid(themesPage, "Grid", 2, 10)
	fitGrid(themeCards, themeGrid, 140, 4, THEME_HEIGHT)

	type ThemeTile = { Button: TextButton, Pill: TextLabel, PillFrame: Frame }
	local themeTiles: { [string]: ThemeTile } = {}
	for index, themeId in data.Themes.Order :: { string } do
		local theme = rawget(data.Themes, themeId)
		local button = Kit.button({
			Name = themeId,
			Kind = "Card",
			LayoutOrder = index,
			Parent = themeCards,
		})
		paint(button, Theme.Colors.Paper, true)
		Kit.label({
			Name = "Icon",
			Text = theme.Icon,
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.new(1, -16, 0.34, 0),
			ZIndex = 2,
			Parent = button,
		})
		local name = Kit.label({
			Name = "ThemeName",
			Text = theme.Name,
			TextScaled = true,
			Font = Theme.DisplayFont,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.34, 8),
			Size = UDim2.new(1, -12, 0, 22),
			ZIndex = 2,
			Parent = button,
		})
		textLimit(name, 20)
		local swatches = frame({
			Name = "Swatches",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.34, 34),
			Size = UDim2.fromOffset(3 * 22 + 2 * 6, 22),
			ZIndex = 2,
			Parent = button,
		})
		local swatchList = Kit.list(swatches, Enum.FillDirection.Horizontal, 6)
		swatchList.HorizontalAlignment = Enum.HorizontalAlignment.Center
		for i, key in { "Wall", "Roof", "Trim" } do
			local swatch = frame({
				Name = key,
				LayoutOrder = i,
				Size = UDim2.fromOffset(22, 22),
				BackgroundColor3 = hexColor(theme[key], CANDY_SWATCHES[i]),
				ZIndex = 2,
				Parent = swatches,
			})
			Kit.corner(swatch, 6)
			Kit.stroke(swatch, Theme.Colors.Outline, 2)
		end
		local pillFrame = frame({
			Name = "Pill",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -20, 0, 32),
			BackgroundColor3 = Theme.Colors.Card,
			ZIndex = 2,
			Parent = button,
		})
		Kit.corner(pillFrame, 16)
		Kit.stroke(pillFrame, Theme.Colors.Outline, 2.5)
		local pill = Kit.label({
			Name = "Text",
			Text = "",
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -12, 1, -8),
			ZIndex = 3,
			Parent = pillFrame,
		})
		textLimit(pill, 18)
		themeTiles[themeId] = { Button = button, Pill = pill, PillFrame = pillFrame }
		button.Activated:Connect(function()
			for _, view in Pure.themeCards(ctx.State, data.Themes) do
				if view.Id == themeId then
					if view.State == "Pick" then
						if ask(nil, ctx.Remotes.SetTheme, themeId) then
							Kit.bump(button)
							Hud.sound("Sparkle")
						end
					elseif view.State == "Locked" then
						ctx.toast(view.Text)
						Hud.shake(button)
					end
				end
			end
		end)
	end

	local function renderThemes(state: Types.Snapshot)
		for _, view in Pure.themeCards(state, data.Themes) do
			local tile = themeTiles[view.Id]
			if tile then
				tile.Pill.Text = view.Text
				tile.PillFrame.BackgroundColor3 = if view.State == "On"
					then Kit.lighten(Theme.Colors.Good, 0.3)
					elseif view.State == "Pick" then Kit.lighten(Theme.Colors.Cyan, 0.5)
					else Theme.Colors.Card
				paint(
					tile.Button,
					if view.State == "On" then Kit.lighten(Theme.Colors.Good, 0.82) else Theme.Colors.Paper,
					true
				)
				local border = borderOf(tile.Button)
				if border then
					border.Transparency = if view.State == "Locked" then 0.5 else 0
				end
			end
		end
	end

	--------------------------------------------------------------------------------------------------------------
	-- Keeping it current
	--------------------------------------------------------------------------------------------------------------
	render = function(state: Types.Snapshot)
		if not modal.isOpen() then
			return
		end
		-- The Perks and Tree tabs dot only for a reward waiting; the Open tab never does (no rebirth pressure).
		Kit.setDot(tabButtons.Perks, #Pure.offerCards(state, data.Perks) > 0)
		Kit.setDot(tabButtons.Tree, Pure.treeNews(state, data.Tree))
		if current == "Open" then
			renderOpen(state)
		elseif current == "Perks" then
			renderPerks(state)
		elseif current == "Tree" then
			renderTree(state)
		elseif current == "Themes" then
			renderThemes(state)
		end
	end
	ctx.onState(function(state: Types.Snapshot)
		if not busy then
			render(state)
		end
	end)

	ctx.on("Open", function(name: any, tab: any)
		if name ~= "Branch" then
			return
		end
		selectTab(Pure.firstTab(tab, ctx.State, data.Tree))
		modal.open()
		render(ctx.State)
	end)

	ctx.on("ModalClosed", function(name: any)
		if name == "Branch" and resetAsk.isOpen() then
			resetAsk.close()
		end
	end)

	selectTab(current)
end

return BranchPanel
