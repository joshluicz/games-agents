--!strict
-- The Branch panel: open a new branch, perk cards, the Branch Ability Tree and themes (Progression v2 build plan
-- §B3/§B5/§B9, §C T5; design §7/§8, memory-20261116-017/-019). OWNER: T5. The calm UI (docs/plan/2026-11-17-ui-
-- direction.md §4 #6; Joshua, memory-20261117-007): headings in words, one Primary, cards without lines, no 🏙️.
--   init(ctx)   opens on ctx.fire("Open", "Branch", "Open" | "Perks" | "Tree" | "Themes") (the Shop's level tab; "Perks"
--               after the Rebirth celebration). With no tab it opens where a reward waits (a perk card, then tree
--               points), else on Open. Asks OpenBranch(true), ChoosePerk(perkId), BuyNode(nodeId), ResetTree(),
--               SetTheme(themeId) and ClaimBranchNurse() through Hud.ask; the server checks everything and the next
--               Snapshot redraws. Fires "Open" ("Nurses", "Team") from the gift row's roster hint, and "Sound" (via
--               Hud: Whoosh, Nope).
--   BranchPanel.Pure   the pure helpers below (tests/BranchUI.spec loads the block on its own)
--
-- Inside (a Hud.modal Panel: the navy header with the title in words, Modal.tabs down the left, Kit.card cards):
--   R0 (Pure.visible; memory-20261117-006): only the tabs with something in them. Before the first branch the panel
--             is the Open page alone (no tab column); Perks, Tree and Themes join with the first branch.
--   Open      a head card (Kit.name "Open a new branch", the Soft line "Needs 🏥 Lv 5 · 50,000 cash" and one Soft
--             hint: how to open, or what is still missing), then three cards with a Soft word heading each: You keep
--             (Logic/Rebirth.KEEP), Starts fresh (RESET, with the start-of-branch perk you own beside its row by
--             name) and You get (GET: +25% cash and stars while they still add up, +3 tree points, a card, +1 nurse
--             slot until the roster's Max, the next theme by name, the next R-unlocks, Golden with its odds). Each
--             row is its Art apart and its words. A big "Not now" is the default focus; "Open branch" (the view's one
--             Primary) is a Kit.holdButton (1.5 s) that asks OpenBranch(true). A tap without the hold says "Hold the
--             button down" (or what's still needed).
--   Perks     the offered cards (tap one: the ✅ State badge; then Take it), "3 random cards, never repeats" and how
--             many are left (every card equally likely), or "No cards waiting"; every perk, ✅ owned; the gift row
--             when a rebirth-only nurse waits (Claim).
--   Tree      the points to spend (🌳 3 points), three branch cards (stacked on a phone) of node tiles with a rank
--             bar (Kit.bar: navy, gold at MAX), the capstone note "Needs 🌳 6 in Care", and Reset (a quiet button:
--             free, every point back) behind THE confirm (Hud.confirm, Destructive).
--   Themes    every theme: On (the ✅ badge), Pick (unlocked) or "From branch 3" (locked: no lock icon, no "hurry"),
--             with its Roof and Trim swatches and "Walls stay your colour" (a theme recolours only the trim and the
--             roof band: look build plan §G4).
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
local Modal = require(script.Parent.Modal)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local BranchPanel = {}

------------------------------------------------------------------------------------------------------------------
-- Pure helpers: no Roblox services or types; only RebirthLogic, TreeLogic and NurseLogic (the shared Logic
-- modules) and UI/Icons (a pure library). tests/BranchUI.spec loads the block between the PURE markers on its own, so keep it that way.
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
	Hint: string,
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

-- Every fixed label on the panel (BranchUI.spec checks each is ≤ 6 words). Words only (UI direction, the emoji
-- rules: no emoji as a bullet, in a heading or in a button; Joshua, memory-20261117-007).
Pure.TEXT = {
	Title = "Branches",
	TabOpen = "Open",
	TabPerks = "Perks",
	TabTree = "Tree",
	TabThemes = "Themes",
	OpenHead = "Open a new branch",
	Keep = "You keep",
	Reset = "Starts fresh",
	Get = "You get",
	NotNow = "Not now",
	OpenButton = "Open branch",
	HoldHint = "Hold the button to open",
	HoldTip = "Hold the button down",
	NotYet = "Not ready yet",
	PickCard = "Pick a card",
	PickCardFirst = "Pick your card first",
	NoCards = "No cards waiting",
	NoCardsNote = "A card each new branch",
	Take = "Take it",
	TapCard = "Tap a card",
	AllCards = "Every card",
	TreeReset = "Reset",
	ResetTitle = "Reset tree?",
	ResetNote = "Every point comes back",
	ResetYes = "Reset",
	NothingToReset = "Nothing to reset",
	ThemesHead = "Pick a look",
	GiftHead = "A nurse waits",
	Claim = "Claim",
	RosterFull = "Roster full: sell or list one",
	Busy = Icons.State.Waiting, -- alone in place of a button's label while the server answers
	Oops = "Oops! Try again.",
	WallsStay = "Walls stay your colour",
	Max = "MAX",
	On = "On",
	Pick = "Pick",
}

-- The theme card's swatches: a theme recolours only the trim and the roof band; the walls stay the plot's colour
-- (look build plan §G4, §F6).
Pure.SWATCHES = { "Roof", "Trim" }

-- The tree's Reset confirm (Hud.confirm; "Not now" stays the default). Reset is a Destructive role (look build plan
-- §B8).
function Pure.resetConfirm(): { Title: string, Line: string, Yes: string, Kind: string, Hold: number }
	return {
		Title = Pure.TEXT.ResetTitle,
		Line = Pure.TEXT.ResetNote,
		Yes = Pure.TEXT.ResetYes,
		Kind = "Destructive",
		Hold = 0,
	}
end

-- The keep/reset screen's RESET rows that a start-of-branch perk softens (by the row's icon; BranchUI.spec checks
-- every RESET row is here).
Pure.RESET_KINDS = {
	[Icons.Unit.Cash] = "StartCash",
	["⚡"] = "StartUpgrades",
	[Icons.Unit.Level] = "StartLevel",
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
	return Icons.unit("Tree", n) .. (if n == 1 then " point" else " points")
end

function Pure.randomText(cfg: any): string
	local s = if type(cfg) == "table" and type(cfg.Rebirth) == "table" then cfg.Rebirth else {}
	local size = math.clamp(whole(s.OfferSize or RebirthLogic.MAX_OFFER), 1, RebirthLogic.MAX_OFFER)
	return size .. " random cards, never repeats"
end

-- The Open page's facts: the next rebirth's cost and the hospital level it needs (Line: one Unit, the level; the
-- cash in words), whether each is met, and the Soft hint under it (Hint: how to open, or what is still missing).
-- The line never says "hurry": only what it takes.
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
	-- Server/Rebirth refuses a branch while a perk card waits (its MSG.PickCard says the same words): one card per
	-- branch.
	local cardWaits = #listOf(rebirthOf(state).Offer) > 0
	if ok and cardWaits then
		ok, message = false, Pure.TEXT.PickCardFirst
	end
	-- "Needs": a requirement, not a price. A rebirth doesn't take the cost off: ALL cash starts fresh (resetRows says
	-- how much).
	local line = Icons.needs(minLevel) .. "  ·  " .. Pure.short(cost) .. " cash"
	local hint = if ok
		then Pure.TEXT.HoldHint
		elseif cardWaits then Pure.TEXT.PickCardFirst
		elseif not levelOk and not cashOk then "Not yet: level and cash"
		elseif not levelOk then "Not yet: hospital level"
		elseif not cashOk then "Not yet: more cash"
		else Pure.TEXT.NotYet
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
		Hint = hint,
		CardWaits = cardWaits,
	}
end

-- What you keep: Logic/Rebirth.KEEP as it is.
function Pure.keepRows(): { Row }
	local out: { Row } = {}
	for _, r in RebirthLogic.KEEP do
		table.insert(out, { Icon = r.Icon, Text = r.Text })
	end
	return out
end

-- What starts fresh: Logic/Rebirth.RESET, each with the start-of-branch perk you own beside it by name ("🏠 Rooms ·
-- Bath Ready": one emoji per row, the row's own). With `cfg`, the cash row says exactly what happens to your cash:
-- ALL of it starts fresh, not the cost taken off ("💰 Cash: 180,000 → 0", or → Seed Money's amount).
function Pure.resetRows(state: any, perks: any, cfg: any?): { Row }
	local owned = listOf(rebirthOf(state).Perks)
	local out: { Row } = {}
	for _, r in RebirthLogic.RESET do
		local kind = Pure.RESET_KINDS[r.Icon]
		local note: string? = nil
		for _, perkId in owned do
			local perk = row(perks, perkId)
			if perk and kind and perk.Kind == kind then
				note = perk.Name
			end
		end
		local text = r.Text
		if kind == "StartCash" and cfg ~= nil then
			local cash = if type(state) == "table" then state.Cash else 0
			local start = RebirthLogic.startCash(state, cfg, perks)
			text ..= ": " .. Pure.short(cash) .. " → " .. Pure.short(start)
		end
		table.insert(out, { Icon = r.Icon, Text = text, Note = note })
	end
	return out
end

-- What the next rebirth gives: Logic/Rebirth.GET (the cash and stars rows only while the bonus still adds up,
-- the slot row only below the roster's Max, the look row as the new theme by name or not at all), then the
-- unlocks new at that count (Golden with its odds).
function Pure.getRows(state: any, cfg: any, themes: any): { Row }
	local count = countOf(state)
	local nextCount = count + 1
	local s = if type(cfg) == "table" and type(cfg.Rebirth) == "table" then cfg.Rebirth else {}
	local out: { Row } = {}
	for _, r in RebirthLogic.GET do
		if r.Icon == Icons.Unit.Cash or r.Icon == Icons.Unit.Stars then
			local kind = if r.Icon == Icons.Unit.Stars then "Stars" else "Cash"
			local gain = RebirthLogic.multiplier(nextCount, cfg, kind) - RebirthLogic.multiplier(count, cfg, kind)
			if gain > 1e-9 then
				local word = if kind == "Stars" then "stars" else "cash"
				table.insert(out, { Icon = r.Icon, Text = "+" .. math.floor(gain * 100 + 0.5) .. "% " .. word })
			end
		elseif r.Icon == Icons.Unit.Tree then
			local points = whole(s.PointsPerRebirth)
			if points > 0 then
				table.insert(
					out,
					{ Icon = r.Icon, Text = "+" .. points .. (if points == 1 then " tree point" else " tree points") }
				)
			end
		elseif r.Icon == Icons.Door.Nurses then
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

-- A row's words: "Rooms · Bath Ready" (the panel draws the row's Icon apart, in its own column).
function Pure.rowWords(r: Row): string
	local text = r.Text
	if r.Note and r.Note ~= "" then
		text ..= " · " .. r.Note
	end
	return text
end

-- A row as one line: "🏠 Rooms · Bath Ready" (one emoji: the row's own).
function Pure.rowText(r: Row): string
	return r.Icon .. " " .. Pure.rowWords(r)
end

-- The cards waiting to be chosen (the Fallback "TreePoints" card too); unknown ids are skipped, and an offer with no
-- known card left shows the Fallback (Logic/Rebirth.liveOffer: the server takes it), so it's never a dead end.
function Pure.offerCards(state: any, perks: any): { PerkCard }
	local out: { PerkCard } = {}
	for _, perkId in ipairs(RebirthLogic.liveOffer(rebirthOf(state).Offer, perks)) do
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

-- The odds, in words: every card you don't own is equally likely (Logic/Rebirth.offer picks evenly). Words only.
function Pure.oddsText(state: any, perks: any): string
	local owned = listOf(rebirthOf(state).Perks)
	local left = 0
	for _, perkId in ordered(perks) do
		if not table.find(owned, perkId) then
			left += 1
		end
	end
	if left >= 2 then
		return "All " .. left .. " cards equally likely"
	elseif left == 1 then
		return "1 card left"
	end
	local fallback = if type(perks) == "table" then perks.Fallback else nil
	local text = if type(fallback) == "table" then fallback.Text else "+2 tree points"
	return "Every card owned: " .. text
end

-- One node tile: its rank, and what tapping it does now. Buy · Poor (not enough points) · Locked (a capstone
-- before 6 points in its branch: "Needs 🌳 6 in Care") · Max ("MAX", the word). Button is a Soft line: one Unit.
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
		kind, button = "Max", Pure.TEXT.Max
	elseif ok then
		kind, button = "Buy", Icons.unit("Tree", cost)
	elseif def.Capstone == true and TreeLogic.spent(ranks, nodes, def.Branch) < TreeLogic.CAPSTONE_NEEDS then
		kind = "Locked"
		button = "Needs "
			.. Icons.unit("Tree", TreeLogic.CAPSTONE_NEEDS)
			.. " in "
			.. (if branch then branch.Name else tostring(def.Branch))
	else
		kind, button = "Poor", Icons.unit("Tree", cost)
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

-- A branch column's head ("Care · 🌳 4" spent: the name in words, one Unit) and its nodes in Data order.
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
		Head = name .. "  ·  " .. Icons.unit("Tree", spent),
		Nodes = ids,
	}
end

-- Reset is offered once anything (even a node that no longer exists) would come back.
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

-- Every theme: "On" (shown now: Logic/Rebirth.theme) · "Pick" (unlocked) · "Locked" ("From branch 3": words, no
-- lock icon, no hurry).
function Pure.themeCards(state: any, themes: any): { ThemeCard }
	local count = countOf(state)
	local current = RebirthLogic.theme(state, themes)
	local out: { ThemeCard } = {}
	for _, themeId in ordered(themes) do
		local theme = row(themes, themeId)
		local needs = whole(theme.Rebirths)
		local kind = if themeId == current then "On" elseif needs <= count then "Pick" else "Locked"
		local text = if kind == "On"
			then Pure.TEXT.On
			elseif kind == "Pick" then Pure.TEXT.Pick
			else "From branch " .. needs
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

-- R0 (UI direction; memory-20261117-006 "simple, especially at the start"): only the tabs with something in them.
-- Before the first branch there is only Open (no tab column at all: Modal.tabs drops it under two tabs). Perks
-- once a branch is open or a card or a gift waits; Tree once a branch is open or points wait; Themes once a branch
-- is open (Candy is the only look before that). A save that already has any of these keeps its tab.
function Pure.visible(state: any): { [string]: boolean }
	local rebirth = rebirthOf(state)
	local opened = countOf(state) > 0
	local perks = opened or #listOf(rebirth.Offer) > 0 or #listOf(rebirth.Pending) > 0 or #listOf(rebirth.Perks) > 0
	local tree = opened or whole(rebirth.Points) > 0 or next(listOf(rebirth.Tree)) ~= nil
	return { Open = true, Perks = perks, Tree = tree, Themes = opened }
end

-- Where the panel opens: the tab asked for (when it shows), else where a reward waits (a card, then tree points),
-- else Open.
function Pure.firstTab(tab: any, state: any, treeData: any): string
	local shown = Pure.visible(state)
	if type(tab) == "string" and table.find(Pure.TABS, tab) and shown[tab] then
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
-- Look helpers: the calm UI (docs/plan/2026-11-17-ui-direction.md; Joshua, memory-20261117-007): Kit.card (a fill,
-- no line), Kit.name once per card, Kit.fact for the rest, one Kit.artTile per card, Kit.bar for a rank, buttons by
-- role. No shape here draws an outline (R2): only Kit's candy buttons do.
------------------------------------------------------------------------------------------------------------------

local BUTTON = Theme.Size.ButtonHeight
local GAP = Theme.Space.PadCard -- between cards (R4)
local ROW_ICON = 28 -- a keep/reset/get row's icon column
local NODE_HEIGHT = 160 -- the art, a two-line name, two lines of words, the rank bar and what a tap does
local PERK_HEIGHT = 124
local OFFER_HEIGHT = 160
local THEME_HEIGHT = 166
local SWATCH = 26
-- The 🎨 tab icon is the Themes tab's own Art (not a chrome Door: it appears nowhere else).
local THEMES_ICON = "🎨"
-- The Candy theme keeps the building's own trim and roof (Data/Themes ""): the warm trim and the dark roof.
local DEFAULT_SWATCH: { [string]: Color3 } = { Roof = Palette.World.Roof, Trim = Palette.World.Trim }

-- A Kit button used as a card (a node, a theme, a perk): a flat fill, no gloss (as Kit.tab does for tabs).
local function flatCard(button: TextButton, fill: Color3)
	button.BackgroundColor3 = fill
	button:SetAttribute("KitColor", fill)
	for _, name in { "Gloss", "CandyGradient" } do
		local shine = button:FindFirstChild(name)
		if shine and shine:IsA("GuiObject") then
			shine.Visible = false
		elseif shine and shine:IsA("UIGradient") then
			shine.Enabled = false
		end
	end
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

-- A Soft line that wraps and grows to fit its words (Kit.fact cuts to one line; a row of words may need two).
local function wrapFact(props: { [string]: any }): TextLabel
	local label = Kit.fact(props)
	label.TextWrapped = true
	label.TextTruncate = Enum.TextTruncate.None
	label.AutomaticSize = Enum.AutomaticSize.Y
	return label
end

-- A name or words that shrink to fit a fixed box (a tile's name), never under the 18 px floor.
local function fitText(label: TextLabel, maxPx: number)
	label.TextScaled = true
	label.TextWrapped = true
	label.TextTruncate = Enum.TextTruncate.None
	Kit.textLimit(label, maxPx)
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
	local list = Kit.list(scroll, Enum.FillDirection.Vertical, GAP)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	list.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, Theme.Space.Tight)
	pad.PaddingBottom = UDim.new(0, Theme.Space.PadCard)
	pad.PaddingLeft = UDim.new(0, Theme.Space.Tight)
	pad.PaddingRight = UDim.new(0, Theme.Space.PadPanel) -- room for the scroll bar
	pad.Parent = scroll
	scroll.Parent = parent
	return scroll
end

-- A card on the paper (Kit.card: the Card fill, no line; AutomaticSize Y unless a height is given).
local function card(parent: Instance, name: string, order: number, height: number?): Frame
	local f = Kit.card({ Name = name, LayoutOrder = order, Pad = if height then false else nil, Parent = parent })
	if height then
		f.AutomaticSize = Enum.AutomaticSize.None
		f.Size = UDim2.new(1, 0, 0, height)
	end
	return f
end

-- A card's content as a vertical list, Line apart.
local function stack(parent: Instance): UIListLayout
	local list = Kit.list(parent, Enum.FillDirection.Vertical, Theme.Space.Line)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Left
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	return list
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
		MaxSize = Vector2.new(760, 600),
	})

	local pages: { [string]: GuiObject } = {}
	local focusOf: { [string]: GuiObject } = {}
	local current = "Open"
	local busy = false
	local render: (state: Types.Snapshot) -> ()
	local tabs: Modal.Tabs

	-- A tab's button (Modal.tabs names them "Tab_<Id>").
	local function tabButton(id: string): GuiObject?
		local found = tabs.Column:FindFirstChild("Tab_" .. id, true)
		return if found and found:IsA("GuiObject") then found else nil
	end

	local function showPage(id: string)
		if not pages[id] then
			return
		end
		current = id
		for pageId, page in pages do
			page.Visible = pageId == id
		end
		modal.Focus = focusOf[id] or tabButton(id)
	end

	-- THE tab pattern, R0: only the tabs with something in them (Pure.visible). Before the first branch that is Open
	-- alone, so there is no tab column at all.
	local shown = Pure.visible(ctx.State)
	tabs = Modal.tabs(modal, {
		{ Id = "Open", Icon = Icons.Door.Branches, Caption = T.TabOpen, Hidden = not shown.Open },
		{ Id = "Perks", Icon = Icons.Unit.Cards, Caption = T.TabPerks, Hidden = not shown.Perks },
		{ Id = "Tree", Icon = Icons.Unit.Tree, Caption = T.TabTree, Hidden = not shown.Tree },
		{ Id = "Themes", Icon = THEMES_ICON, Caption = T.TabThemes, Hidden = not shown.Themes },
	}, function(id: string)
		showPage(id)
		render(ctx.State)
	end)
	local pagesArea = tabs.Content

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

	--------------------------------------------------------------------------------------------------------------
	-- Open: the keep/reset screen. A head card (name, what it takes, one hint), three cards with a word heading
	-- each (You keep · Starts fresh · You get), and the foot: Not now and the one Primary, Open branch (hold).
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
	openScroll.Size = UDim2.new(1, 0, 1, -(BUTTON + GAP))

	local head = card(openScroll, "Head", 1)
	stack(head)
	Kit.name({ Name = "Title", Text = T.OpenHead, LayoutOrder = 1, Parent = head })
	local headStatus = Kit.fact({ Name = "Status", Text = "", LayoutOrder = 2, Parent = head })
	local headHint = Kit.fact({ Name = "Hint", Text = T.HoldHint, LayoutOrder = 3, Parent = head })

	-- Three cards (stacked on a narrow screen): you keep · starts fresh · you get.
	local columns = frame({
		Name = "Columns",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = openScroll,
	})
	local columnList = Kit.list(columns, Enum.FillDirection.Horizontal, GAP)
	columnList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	columnList.VerticalAlignment = Enum.VerticalAlignment.Top

	type Column = { Frame: Frame, Rows: Frame }
	local function newColumn(name: string, order: number, title: string): Column
		local f = card(columns, name, order)
		f.Size = UDim2.new(1 / 3, -GAP, 0, 0)
		stack(f)
		Kit.fact({ Name = "Head", Text = title, LayoutOrder = 0, Parent = f })
		local rows = frame({
			Name = "Rows",
			LayoutOrder = 1,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = f,
		})
		stack(rows)
		return { Frame = f, Rows = rows }
	end
	local keepColumn = newColumn("Keep", 1, T.Keep)
	local resetColumn = newColumn("Reset", 2, T.Reset)
	local getColumn = newColumn("Get", 3, T.Get)
	local function fitColumns()
		local width = columns.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local wide = width >= 600
		columnList.FillDirection = if wide then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
		for _, column in { keepColumn, resetColumn, getColumn } do
			column.Frame.Size = if wide then UDim2.new(1 / 3, -GAP, 0, 0) else UDim2.fromScale(1, 0)
		end
	end
	columns:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitColumns)
	fitColumns()

	-- A row: its Art in a small column of its own, then its words in Normal ink (the heading above is Soft).
	local function fillRows(column: Column, rows: { Row })
		clearGui(column.Rows)
		for index, r in rows do
			local holder = frame({
				Name = "Row" .. index,
				LayoutOrder = index,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Parent = column.Rows,
			})
			local list = Kit.list(holder, Enum.FillDirection.Horizontal, Theme.Space.Tight)
			list.VerticalAlignment = Enum.VerticalAlignment.Top
			Kit.label({
				Name = "Icon",
				Text = r.Icon,
				TextSize = Theme.TextSize.Body,
				TextWrapped = false,
				LayoutOrder = 1,
				Size = UDim2.fromOffset(ROW_ICON, Theme.TextSize.Body + Theme.Space.Tight),
				Parent = holder,
			})
			local words = wrapFact({
				Name = "Text",
				Text = Pure.rowWords(r),
				LayoutOrder = 2,
				Size = UDim2.new(1, -(ROW_ICON + Theme.Space.Tight), 0, 0),
				Parent = holder,
			})
			words.TextColor3 = Theme.Colors.Ink
		end
	end

	-- The foot: a big "Not now" (the default focus) and the hold-to-open button (the view's one Primary: it never
	-- shines or breathes; no pressure).
	local foot = frame({
		Name = "Foot",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, -Theme.Space.PadPanel, 0, BUTTON),
		Parent = openPage,
	})
	local notNow = Kit.button({
		Name = "NotNow",
		Kind = "Secondary",
		Text = T.NotNow,
		TextScaled = true,
		Size = UDim2.new(0.5, -GAP / 2, 1, 0),
		Parent = foot,
	})
	Kit.textLimit(notNow, Theme.TextSize.Button)
	local openButton = Kit.button({
		Name = "OpenBranch",
		Kind = "Primary",
		Text = T.OpenButton,
		TextScaled = true,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, -GAP / 2, 1, 0),
		Parent = foot,
	})
	Kit.textLimit(openButton, Theme.TextSize.Button)
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
			modal.close() -- the server's Rebirth celebration comes next, then "Pick a card"
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
			tabs.select("Perks") -- the waiting card, one tap away
			return
		end
		ctx.toast(if status.Ok then T.HoldTip else status.Message)
		Hud.shake(openButton)
	end)

	-- One key per column: the cash row changes with every treatment, and only its column needs redrawing then.
	local openKeys: { [Column]: string } = {}
	local function renderOpen(state: Types.Snapshot)
		local status = Pure.status(state, cfg)
		headStatus.Text = status.Line
		headHint.Text = status.Hint
		Kit.setRole(openButton, if status.Ok then "Primary" else "Disabled")
		local columnRows: { { Column: Column, Rows: { Row } } } = {
			{ Column = keepColumn, Rows = Pure.keepRows() },
			{ Column = resetColumn, Rows = Pure.resetRows(state, data.Perks, cfg) },
			{ Column = getColumn, Rows = Pure.getRows(state, cfg, data.Themes) },
		}
		for _, entry in columnRows do
			local parts = {}
			for _, r in entry.Rows do
				table.insert(parts, Pure.rowText(r))
			end
			local key = table.concat(parts, ";")
			if key ~= openKeys[entry.Column] then
				openKeys[entry.Column] = key
				fillRows(entry.Column, entry.Rows)
			end
		end
	end

	--------------------------------------------------------------------------------------------------------------
	-- Perks: the gift (a nurse waiting), the offer (tap a card, then Take it) and every card (✅ when owned)
	--------------------------------------------------------------------------------------------------------------
	local perksPage = scrollPage(pagesArea, "Perks")
	perksPage.Visible = false
	pages.Perks = perksPage

	-- The gift row: a rebirth-only nurse waiting for a roster place.
	local giftRow = card(perksPage, "Gift", 1, 80)
	giftRow.Visible = false
	local giftFace = Kit.artTile({
		Name = "Face",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, Theme.Space.PadCard, 0.5, 0),
		Parent = giftRow,
	})
	Kit.name({
		Name = "Text",
		Text = T.GiftHead,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, Theme.Space.PadCard * 2 + Theme.Calm.ArtTile, 0.5, 0),
		Size = UDim2.new(1, -(Theme.Space.PadCard * 4 + Theme.Calm.ArtTile + 150), 0, Theme.TextSize.Body + 4),
		Parent = giftRow,
	})
	local claim = Kit.button({
		Name = "Claim",
		Kind = "Collect",
		Text = T.Claim,
		TextScaled = true,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -Theme.Space.PadCard, 0.5, 0),
		Size = UDim2.fromOffset(150, BUTTON),
		Parent = giftRow,
	})
	Kit.textLimit(claim, Theme.TextSize.Button)
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
	local offerCard = card(perksPage, "Offer", 2)
	stack(offerCard)
	local offerTitle = Kit.name({ Name = "Title", Text = T.PickCard, LayoutOrder = 1, Parent = offerCard })
	local offerRandom = Kit.fact({ Name = "Random", Text = Pure.randomText(cfg), LayoutOrder = 2, Parent = offerCard })
	local offerOdds = Kit.fact({ Name = "Odds", Text = "", LayoutOrder = 3, Parent = offerCard })
	local offerCards, offerGrid = grid(offerCard, "Cards", 4, GAP)
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
		Kind = "Collect",
		Text = T.TapCard,
		TextScaled = true,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.6, 1),
		Parent = takeRow,
	})
	Kit.textLimit(take, Theme.TextSize.Button)

	Kit.fact({ Name = "AllHead", Text = T.AllCards, LayoutOrder = 3, Parent = perksPage })
	local allCards, allGrid = grid(perksPage, "All", 4, GAP)
	fitGrid(allCards, allGrid, 160, 4, PERK_HEIGHT)

	local selectedPerk: string? = nil
	local offerKey = ""
	local offerButtons: { [string]: TextButton } = {}

	-- The chosen card: the Well fill and the ✅ State badge; Take it turns green.
	local function paintOffer()
		for perkId, button in offerButtons do
			local chosen = perkId == selectedPerk
			flatCard(button, if chosen then Theme.Colors.Well else Theme.Colors.Paper)
			Kit.setState(button, if chosen then Icons.State.Done else nil)
		end
		local ready = selectedPerk ~= nil and offerButtons[selectedPerk] ~= nil
		take.Text = if ready then T.Take else T.TapCard
		Kit.setRole(take, if ready then "Collect" else "Disabled")
	end

	-- A perk face: its Art big, its name (Normal) and its words (Soft).
	local function perkFace(button: GuiObject, perk: PerkCard, iconShare: number)
		local icon = Kit.label({
			Name = "Icon",
			Text = perk.Icon,
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, Theme.Space.Line),
			Size = UDim2.new(1, -16, iconShare, -Theme.Space.Line),
			ZIndex = 2,
			Parent = button,
		})
		Kit.textLimit(icon, Theme.Emoji.ArtBig)
		local name = Kit.name({
			Name = "PerkName",
			Text = perk.Name,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, iconShare, Theme.Space.Tight),
			Size = UDim2.new(1, -Theme.Space.PadCard, 0.2, 0),
			ZIndex = 2,
			Parent = button,
		})
		fitText(name, Theme.TextSize.Body)
		local words = Kit.fact({
			Name = "Words",
			Text = perk.Text,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -Theme.Space.Line),
			Size = UDim2.new(1, -Theme.Space.PadCard, 1 - iconShare - 0.2, -Theme.Space.PadCard),
			ZIndex = 2,
			Parent = button,
		})
		fitText(words, Theme.TextSize.Caption)
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
			Kit.corner(giftFace, Theme.Radius.Small)
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
					Kind = "Secondary",
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
					BackgroundColor3 = if perk.Owned then Theme.Colors.Well else Theme.Colors.Card,
					Parent = allCards,
				})
				Kit.corner(tile, Theme.Radius.Medium)
				perkFace(tile, perk, 0.36)
				if perk.Owned then
					Kit.setState(tile, Icons.State.Done)
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
	-- Tree: the points to spend, three branch cards (stacked on a phone) of node tiles with a rank bar, the capstone
	-- note "Needs 🌳 6 in Care", and Reset (free, every point back) behind THE confirm
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
		Size = UDim2.new(1, -Theme.Space.PadPanel, 0, BUTTON),
		Parent = treePage,
	})
	local pointsText = Kit.name({
		Name = "Points",
		Text = Pure.pointsText(0),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, -(150 + GAP), 0, Theme.TextSize.Body + Theme.Space.Tight),
		Parent = treeTop,
	})
	local resetButton = Kit.button({
		Name = "Reset",
		Kind = "Secondary",
		Text = T.TreeReset,
		TextScaled = true,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(150, BUTTON),
		Parent = treeTop,
	})
	Kit.textLimit(resetButton, Theme.TextSize.Button)
	focusOf.Tree = resetButton

	local treeScroll = scrollPage(treePage, "Scroll")
	treeScroll.Position = UDim2.fromOffset(0, BUTTON + GAP)
	treeScroll.Size = UDim2.new(1, 0, 1, -(BUTTON + GAP))
	local treeColumns = frame({
		Name = "Columns",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = treeScroll,
	})
	local treeColumnList = Kit.list(treeColumns, Enum.FillDirection.Horizontal, GAP)
	treeColumnList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	treeColumnList.VerticalAlignment = Enum.VerticalAlignment.Top

	type NodeTile = {
		Button: TextButton,
		SetBar: (fraction: number, atMax: boolean?) -> (),
		State: TextLabel,
		Tile: Frame,
		Shown: string,
	}
	type BranchColumn = { Frame: Frame, Head: TextLabel, Nodes: { [string]: NodeTile } }
	local branchColumns: { [string]: BranchColumn } = {}
	local branchOrder: { string } = if type(data.Tree) == "table" and type(data.Tree.BranchOrder) == "table"
		then data.Tree.BranchOrder
		else {}

	-- A node tile: its Art, its name, its words, its rank as a bar (navy; gold at MAX) and what a tap does now.
	local function newNodeTile(parent: Instance, order: number, nodeId: string): NodeTile
		local def = rawget(data.Tree.Nodes, nodeId)
		local pad = Theme.Space.PadCard
		local art = 40
		local button = Kit.button({
			Name = nodeId,
			Kind = "Secondary",
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, NODE_HEIGHT),
			Parent = parent,
		})
		flatCard(button, Theme.Colors.Paper)
		local tile = Kit.artTile({
			Icon = def.Icon,
			Position = UDim2.fromOffset(pad, pad),
			Size = UDim2.fromOffset(art, art),
			ZIndex = 2,
			Parent = button,
		})
		local name = Kit.name({
			Name = "NodeName",
			Text = def.Name,
			Position = UDim2.fromOffset(pad + art + Theme.Space.Line, pad - Theme.Space.Tight),
			Size = UDim2.new(1, -(pad * 2 + art + Theme.Space.Line), 0, 48),
			ZIndex = 2,
			Parent = button,
		})
		fitText(name, Theme.TextSize.Body)
		local words = Kit.fact({
			Name = "Words",
			Text = def.Text,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(pad, pad + art + Theme.Space.Line),
			Size = UDim2.new(1, -pad * 2, 0, 44),
			ZIndex = 2,
			Parent = button,
		})
		fitText(words, Theme.TextSize.Caption)
		local _, setBar = Kit.bar({
			Name = "Rank",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, pad, 1, -(pad + Theme.TextSize.Caption + Theme.Space.Line * 2)),
			Size = UDim2.new(1, -pad * 2, 0, Theme.Calm.Bar),
			ZIndex = 2,
			Parent = button,
		})
		local stateLabel = Kit.fact({
			Name = "State",
			Text = "",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, pad, 1, -pad),
			Size = UDim2.new(1, -pad * 2, 0, Theme.TextSize.Caption + Theme.Space.Line),
			ZIndex = 2,
			Parent = button,
		})
		local nodeTile: NodeTile = {
			Button = button,
			SetBar = setBar,
			State = stateLabel,
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
				Hud.sound("Node") -- Feel/Sounds' tree cue (Progression v2 §B9)
			end
		end)
		return nodeTile
	end

	for index, branchId in branchOrder do
		local column = card(treeColumns, branchId, index)
		column.Size = UDim2.new(1 / 3, -GAP, 0, 0)
		stack(column)
		local headLabel = Kit.name({
			Name = "Head",
			Text = Pure.branchView(ctx.State, branchId, data.Tree).Head,
			LayoutOrder = 0,
			Parent = column,
		})
		local entry: BranchColumn = { Frame = column, Head = headLabel, Nodes = {} }
		local view = Pure.branchView(ctx.State, branchId, data.Tree)
		for order, nodeId in view.Nodes do
			entry.Nodes[nodeId] = newNodeTile(column, order, nodeId)
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
			column.Frame.Size = if wide then UDim2.new(1 / 3, -GAP, 0, 0) else UDim2.fromScale(1, 0)
		end
	end
	treeColumns:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitTree)
	fitTree()

	local function renderTree(state: Types.Snapshot)
		local rebirth = (state :: any).Rebirth
		local points = if type(rebirth) == "table" and type(rebirth.Points) == "number" then rebirth.Points else 0
		pointsText.Text = Pure.pointsText(points)
		Kit.setRole(resetButton, if Pure.canReset(state, data.Tree) then "Secondary" else "Disabled")
		for branchId, column in branchColumns do
			column.Head.Text = Pure.branchView(state, branchId, data.Tree).Head
			for nodeId, tile in column.Nodes do
				local view = Pure.nodeView(state, nodeId, data.Tree)
				if view then
					tile.SetBar(Kit.Juice.barFraction(view.Rank, view.Max), view.State == "Max")
					tile.State.Text = view.Button
					-- What a tap does, in ink while the points can take it, soft while not.
					tile.State.TextColor3 = if view.State == "Buy" then Theme.Colors.Ink else Theme.Colors.InkSoft
					flatCard(tile.Button, if view.State == "Max" then Theme.Colors.Well else Theme.Colors.Paper)
					if tile.Shown ~= "" and tile.Shown ~= view.State .. view.Rank then
						Kit.bump(tile.Tile)
					end
					tile.Shown = view.State .. view.Rank
				end
			end
		end
	end

	-- Reset: free and every point comes back, but it undoes your picks, so it asks first (THE confirm: "Not now"
	-- is the default focus).
	resetButton.Activated:Connect(function()
		if not Pure.canReset(ctx.State, data.Tree) then
			ctx.toast(T.NothingToReset)
			Hud.shake(resetButton)
			return
		end
		Hud.confirm(ctx, Pure.resetConfirm(), function()
			if ask(resetButton, ctx.Remotes.ResetTree) then
				Hud.sound("Sparkle")
			end
		end)
	end)

	--------------------------------------------------------------------------------------------------------------
	-- Themes: a theme recolours the trim and the roof band only (the walls stay your plot's colour)
	--------------------------------------------------------------------------------------------------------------
	local themesPage = scrollPage(pagesArea, "Themes")
	themesPage.Visible = false
	pages.Themes = themesPage
	Kit.name({ Name = "Head", Text = T.ThemesHead, LayoutOrder = 1, Parent = themesPage })
	Kit.fact({ Name = "WallsStay", Text = T.WallsStay, LayoutOrder = 2, Parent = themesPage })
	local themeCards, themeGrid = grid(themesPage, "Grid", 3, GAP)
	fitGrid(themeCards, themeGrid, 140, 4, THEME_HEIGHT)

	type ThemeTile = { Button: TextButton, State: TextLabel }
	local themeTiles: { [string]: ThemeTile } = {}
	for index, themeId in data.Themes.Order :: { string } do
		local theme = rawget(data.Themes, themeId)
		local button = Kit.button({
			Name = themeId,
			Kind = "Secondary",
			LayoutOrder = index,
			Parent = themeCards,
		})
		flatCard(button, Theme.Colors.Paper)
		local icon = Kit.label({
			Name = "Icon",
			Text = theme.Icon,
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, Theme.Space.Line),
			Size = UDim2.new(1, -16, 0, 46),
			ZIndex = 2,
			Parent = button,
		})
		Kit.textLimit(icon, Theme.Emoji.Art)
		local name = Kit.name({
			Name = "ThemeName",
			Text = theme.Name,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 58),
			Size = UDim2.new(1, -Theme.Space.PadCard, 0, 26),
			ZIndex = 2,
			Parent = button,
		})
		fitText(name, Theme.TextSize.Body)
		local swatches = frame({
			Name = "Swatches",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 92),
			Size = UDim2.fromOffset(#Pure.SWATCHES * SWATCH + (#Pure.SWATCHES - 1) * Theme.Space.Line, SWATCH),
			ZIndex = 2,
			Parent = button,
		})
		local swatchList = Kit.list(swatches, Enum.FillDirection.Horizontal, Theme.Space.Line)
		swatchList.HorizontalAlignment = Enum.HorizontalAlignment.Center
		for i, key in Pure.SWATCHES do
			local swatch = frame({
				Name = key,
				LayoutOrder = i,
				Size = UDim2.fromOffset(SWATCH, SWATCH),
				BackgroundColor3 = hexColor(theme[key], DEFAULT_SWATCH[key] or Theme.Colors.Card),
				ZIndex = 2,
				Parent = swatches,
			})
			Kit.corner(swatch, Theme.Radius.Small)
		end
		local stateLabel = Kit.fact({
			Name = "State",
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -Theme.Space.PadCard),
			Size = UDim2.new(1, -Theme.Space.PadCard, 0, Theme.TextSize.Caption + Theme.Space.Line),
			ZIndex = 2,
			Parent = button,
		})
		themeTiles[themeId] = { Button = button, State = stateLabel }
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

	-- On: the Well fill and the ✅ State badge · Pick: ink · Locked: soft ("From branch 3").
	local function renderThemes(state: Types.Snapshot)
		for _, view in Pure.themeCards(state, data.Themes) do
			local tile = themeTiles[view.Id]
			if tile then
				tile.State.Text = view.Text
				tile.State.TextColor3 = if view.State == "Locked" then Theme.Colors.InkSoft else Theme.Colors.Ink
				flatCard(tile.Button, if view.State == "On" then Theme.Colors.Well else Theme.Colors.Paper)
				Kit.setState(tile.Button, if view.State == "On" then Icons.State.Done else nil)
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
		-- R0: a tab appears the moment it has something in it.
		local visible = Pure.visible(state)
		for _, id in Pure.TABS do
			tabs.setVisible(id, visible[id] == true)
		end
		-- The Perks and Tree tabs dot only for a reward waiting; the Open tab never does (no rebirth pressure).
		local perksTab, treeTab = tabButton("Perks"), tabButton("Tree")
		if perksTab then
			Kit.setDot(perksTab, #Pure.offerCards(state, data.Perks) > 0)
		end
		if treeTab then
			Kit.setDot(treeTab, Pure.treeNews(state, data.Tree))
		end
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
		local visible = Pure.visible(ctx.State)
		for _, id in Pure.TABS do
			tabs.setVisible(id, visible[id] == true)
		end
		tabs.select(Pure.firstTab(tab, ctx.State, data.Tree))
		modal.open()
		render(ctx.State)
	end)

	showPage(current)
end

return BranchPanel
