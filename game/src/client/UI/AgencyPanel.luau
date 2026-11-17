--!strict
-- The Nurse Agency panel (Progression v2 build plan §B3.1/§B9, §C T3; design §8, memory-20261116-018). OWNER: T3.
--   init(ctx)   opens on ctx.fire("Open", "Agency", "Hire" | "Sell"?) (the kiosk's prompt: Workspace.NurseAgency's
--               ProximityPrompt "Prompt", client Triggered; NursePanel's Agency link) and on the bus "Sell" (nurseId)
--               (NursePanel's Sell: the Sell tab and that nurse's confirm); listens to the bus "AgencyNews" (view),
--               "MarketNews" (which of yours are listed) and "NurseNews". Asks GetAgency, AgencyBuy(slot, nurseId,
--               expect) and SellNurse(nurseId, expect); `expect` is always the price the server showed.
-- Inside (a Hud.modal Panel on the one template: the navy header "Agency", Modal.tabs down the left):
--   · Hire (the Agency's own door icon, Icons.Door.Agency): the stock, one Kit.card per nurse (4, or 6 with Lucky
--     Stock: its fact line says so): the portrait in its rarity frame (a Kit.artTile well), the name (Kit.name), one
--     Soft fact in words ("Healer · Bath Room"), and ONE button (Pure.calmButton): the price "💰 150" (Primary;
--     grey when short) · ✅ (bought this restock, Quiet) · 🔒 with "Needs 🏥 Lv 3" in the fact (a gate) · "Roster
--     full" (opens the Team page) · "MAX". Over the list, in words: "New nurses every 5 min" (never a clock, §E9)
--     and the Quiet "Odds" link.
--   · Sell (Icons.Unit.Cash: what you get): every nurse you own, the fact "Lv 7 · You get 💰 30" (30% of the belt's
--     base price per copy) and "Sell" (Destructive) · "Listed" (unlist it on the Market first) · "Stays"
--     (rebirth-only).
--   · Odds: THE odds popup (Hud.oddsPopup, Pure.oddsSpec), from the server's own table (AgencyView.Odds): every
--     rarity with its word and number (70 / 26 / 4), "Never Legendary+", Lucky Stock uses the same odds, the Epic
--     gate. Odds are never hidden or collapsed (red line 3).
--   · Every buy and sell asks first through THE confirm (Hud.confirm, Pure.confirmSpec): the title is the verb
--     ("Hire?", "Sell?"), the line the question with its price ("Hire 🐶 Puff Pup for 💰150?"), Yes the verb alone
--     ("Hire", "Sell"); "Not now" is the default button, and selling an Epic or rarer (or any nurse at Lv 2+) is a
--     1 s hold ("Hold to sell": Kit.holdButton).
-- Cash only, no Robux, no "hurry" words, no countdowns (red line 3). Every motion goes through Hud.pop / Kit (they
-- honour Kit.reducedMotion()). Buttons are 56 px tall and every label is 6 words or fewer. The calm UI
-- (docs/plan/2026-11-17-ui-direction.md; memory-20261117-007): cards without lines, one button per card, titles in
-- words, chrome emoji from UI/Icons. The pure block's older texts (buttonText, confirmText, everyText, the odds
-- notes) keep the emoji the server-side specs pin; the panel draws the calm ones.

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Logic = Shared:WaitForChild("Logic")
local AgencyLogic = require(Logic:WaitForChild("Agency"))
local BeltLogic = require(Logic:WaitForChild("Belt"))
local NurseLogic = require(Logic:WaitForChild("Nurse"))
local RebirthLogic = require(Logic:WaitForChild("Rebirth"))
local Hud = require(script.Parent.Hud)
local Icons = require(script.Parent.Icons)
local Kit = require(script.Parent.Kit)
local Modal = require(script.Parent.Modal)
local Theme = require(script.Parent.Theme)

local AgencyPanel = {}

------------------------------------------------------------------------------------------------------------------
-- Pure helpers: no Roblox services or types; the only upvalue is Logic/Nurse as NurseLogic (pure itself).
-- tests/AgencyServer.spec loads the block between the PURE markers on its own, so keep it that way.
------------------------------------------------------------------------------------------------------------------
-- PURE-BEGIN
local Pure = {}

local I: any = nil -- UI/Icons, handed in by Pure.use (the calm texts read it; the older ones don't)

function Pure.use(icons: any)
	I = icons
end

Pure.RARITIES = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
Pure.ANY_ICON = "🌈" -- a specialty of "Any" (it counts for every department)

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Pure.rank(rarity: any): number
	return table.find(Pure.RARITIES, rarity) or 0
end

-- 12345 -> "12,345"
function Pure.commas(n: any): string
	local digits = tostring(math.floor(math.abs(if finite(n) then n else 0)))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return grouped
end

-- "70%", "4%", "0.5%"; "–" for 0 or junk.
function Pure.percent(value: any): string
	if not finite(value) or value <= 0 then
		return "–"
	end
	local tenths = math.floor(value * 10 + 0.5)
	if tenths % 10 == 0 then
		return string.format("%d%%", tenths // 10)
	end
	return string.format("%.1f%%", tenths / 10)
end

-- How often new nurses come, never a clock (§E9): "🔄 New nurses every 5 min" (Server/Agency's kiosk says the same).
function Pure.everyText(seconds: any): string
	local s = if finite(seconds) then math.max(1, math.floor(seconds + 0.5)) else 300
	if s % 60 == 0 then
		return "🔄 New nurses every " .. tostring(s // 60) .. " min" -- uirules: allow TypedEmoji, uirules: allow LeadEmoji (the kiosk's words, pinned by tests/AgencyServer.spec; the panel draws Icons.words of it)
	end
	return "🔄 New nurses every " .. tostring(s) .. " s" -- uirules: allow TypedEmoji, uirules: allow LeadEmoji (as above)
end

export type OddsRow = { Rarity: string, Odds: number }

-- The 🎲 popup's rows: every rarity the Agency can stock, lowest first, with the server's own odds.
function Pure.oddsRows(odds: any): { OddsRow }
	local rows: { OddsRow } = {}
	if type(odds) ~= "table" then
		return rows
	end
	for _, rarity in Pure.RARITIES do
		local value = odds[rarity]
		if finite(value) and value > 0 then
			table.insert(rows, { Rarity = rarity, Odds = value })
		end
	end
	return rows
end

-- "🚫 Never Legendary+": the first rarity above the rarest one it stocks; nil when every rarity can come.
function Pure.neverText(odds: any): string?
	local top = 0
	for index, row in Pure.RARITIES do
		local value = if type(odds) == "table" then odds[row] else nil
		if finite(value) and value > 0 then
			top = index
		end
	end
	if top == 0 or top >= #Pure.RARITIES then
		return nil
	end
	return "🚫 Never " .. Pure.RARITIES[top + 1] .. "+"
end

-- A stock card's state for you, in the server's order (§B3.1): "Bought" (this restock) · "Gate" ("🏥 Lv 3" /
-- "🏢 R1") · "Full" (a new nurse and your roster is full) · "Max" (a copy at the level cap) · "Poor" (short of
-- cash) · "Ready". `state` is the Snapshot (Cash, Nurses, Rebirth).
function Pure.cardState(slot: any, state: any, cfg: any, isKnown: ((string) -> boolean)?): string
	if type(slot) ~= "table" then
		return "Poor"
	end
	if slot.Bought == true then
		return "Bought"
	end
	if type(slot.Gate) == "string" and slot.Gate ~= "" then
		return "Gate"
	end
	local ok = NurseLogic.canAdd(state, slot.NurseId, cfg, isKnown)
	if not ok then
		local nurses = if type(state) == "table" and type(state.Nurses) == "table" then state.Nurses else {}
		return if nurses[slot.NurseId] ~= nil then "Max" else "Full"
	end
	local cash = if type(state) == "table" and finite(state.Cash) then state.Cash else 0
	if not finite(slot.Price) or cash < slot.Price then
		return "Poor"
	end
	return "Ready"
end

-- A stock card's button (6 words or fewer).
function Pure.buttonText(cardState: string, slot: any): string
	if cardState == "Bought" then
		return "✅ Bought" -- uirules: allow TypedEmoji, uirules: allow LeadEmoji (pinned by tests/AgencyServer.spec; drawn as Pure.calmButton)
	elseif cardState == "Gate" then
		return tostring(slot.Gate)
	elseif cardState == "Full" then
		return "Roster full"
	elseif cardState == "Max" then
		return "⭐ MAX" -- uirules: allow TypedEmoji (pinned by tests/AgencyServer.spec; drawn as Pure.calmButton)
	end
	return "Hire 💰" .. Pure.commas(slot.Price) -- uirules: allow TypedEmoji (pinned by tests/AgencyServer.spec)
end

-- The calm card's one button (UI direction rule 2: no emoji in a button but a Unit with its price or a State alone):
-- "💰 150" · ✅ · 🔒 (the gate goes in the fact line: Pure.gateNote) · "Roster full" · "MAX".
function Pure.calmButton(cardState: string, slot: any): string
	if cardState == "Bought" then
		return I.State.Done
	elseif cardState == "Gate" then
		return I.State.Locked
	elseif cardState == "Full" then
		return "Roster full"
	elseif cardState == "Max" then
		return "MAX"
	end
	return I.unit("Cash", Pure.commas(if type(slot) == "table" then slot.Price else 0))
end

-- A gate in words for the fact line: "Needs 🏥 Lv 3" · "Needs 🏢 R1" (the server's gate text, Logic/Belt.gate).
function Pure.gateNote(gate: any): string
	return if type(gate) == "string" and gate ~= "" then "Needs " .. gate else ""
end

-- A Sell row's fact and button: "Lv 7 · 2 copies · You get 💰 30" and "Sell" | "Listed" | "Stays" | ⏳.
function Pure.sellFact(level: any, copies: any, resting: boolean, sellState: string, price: any): string
	local parts = { "Lv " .. tostring(if finite(level) then math.floor(level) else 1) }
	if finite(copies) and copies > 1 then
		table.insert(parts, tostring(math.floor(copies)) .. " copies")
	end
	if resting then
		table.insert(parts, "resting")
	end
	if sellState == "Sell" and finite(price) then
		table.insert(parts, "You get " .. I.unit("Cash", Pure.commas(price)))
	elseif sellState == "Listed" then
		table.insert(parts, "on the Market")
	elseif sellState == "Stays" then
		table.insert(parts, "stays with you")
	end
	return table.concat(parts, " · ")
end

function Pure.sellButton(sellState: string): string
	if sellState == "Sell" then
		return "Sell"
	elseif sellState == "Listed" then
		return "Listed"
	elseif sellState == "Stays" then
		return "Stays"
	end
	return I.State.Waiting
end

-- A Sell row's state: "Sell" · "Listed" (on the Market: unlist it first) · "Stays" (rebirth-only) · "None" (the
-- Agency has no price for it: an unknown nurse, or no view yet).
function Pure.sellState(nurseId: string, roster: any, sellBack: any, listed: any): string
	local nurse = if type(roster) == "table" then rawget(roster, nurseId) else nil
	if type(nurse) ~= "table" then
		return "None"
	end
	if nurse.Source ~= nil then
		return "Stays"
	end
	if type(listed) == "table" and listed[nurseId] == true then
		return "Listed"
	end
	local price = if type(sellBack) == "table" then sellBack[nurseId] else nil
	return if finite(price) then "Sell" else "None"
end

-- The confirm's question (6 words or fewer): "Hire 🐶 Puff Pup for 💰150?" · "Sell 🐶 Lv 7 for 💰30?".
function Pure.confirmText(kind: string, icon: string, name: string, level: number, price: number): string
	if kind == "Sell" then
		return string.format("Sell %s Lv %d for 💰%s?", icon, math.floor(level), Pure.commas(price)) -- uirules: allow TypedEmoji (pinned by tests/AgencyServer.spec)
	end
	return string.format("Hire %s %s for 💰%s?", icon, name, Pure.commas(price)) -- uirules: allow TypedEmoji (pinned by tests/AgencyServer.spec)
end

-- Selling an Epic or rarer is a hold (Kit.holdButton), not a tap; so is selling any nurse you've levelled (Lv 2+):
-- the sell-back is never level-scaled, so a tap must never throw away hours of levels.
Pure.HOLD_LEVEL = 2
function Pure.needsHold(rarity: any, level: any): boolean
	return Pure.rank(rarity) >= 3 or (finite(level) and level >= Pure.HOLD_LEVEL)
end

-- Your nurses listed on the Market (a MarketView), by NurseId.
function Pure.listed(market: any, userId: number): { [string]: boolean }
	local out: { [string]: boolean } = {}
	local listings = if type(market) == "table" then market.Listings else nil
	if type(listings) == "table" then
		for _, listing in listings do
			if type(listing) == "table" and listing.Seller == userId and type(listing.NurseId) == "string" then
				out[listing.NurseId] = true
			end
		end
	end
	return out
end

-- What your Agency view hangs on besides the stock (your hospital level, rebirths, 🏷️ Bargain, 🍀 Lucky Stock):
-- when it changes, the panel asks again.
function Pure.priceKey(state: any, effects: any): string
	local level = if type(state) == "table" and finite(state.Level) then state.Level else 1
	local rebirth = if type(state) == "table" then state.Rebirth else nil
	local count = if type(rebirth) == "table" and finite(rebirth.Count) then rebirth.Count else 0
	local bargain = if type(effects) == "table" and finite(effects.Bargain) then effects.Bargain else 0
	local lucky = type(effects) == "table" and effects.LuckyStock == true
	return table.concat({ tostring(level), tostring(count), tostring(bargain), tostring(lucky) }, "|")
end

-- Selling a nurse that needsHold waits on a hold this long (Kit.holdButton, through Hud.confirm's Hold).
Pure.HOLD_SECONDS = 1

export type ConfirmSpec = { Title: string, Line: string, Yes: string, Kind: string, Hold: number }

-- THE confirm (Hud.confirm) for a hire or a sell (the UI direction's calm wording): the title is the verb in words
-- ("Sell?"), the line the question with its price (Pure.confirmText, 6 words or fewer), Yes the verb alone ("Sell",
-- or "Hold to sell" for a sell that needsHold), its role (Hire is Primary; Sell is Destructive) and the hold.
function Pure.confirmSpec(
	kind: string,
	icon: string,
	name: string,
	level: number,
	price: number,
	rarity: any
): ConfirmSpec
	if kind == "Sell" then
		local hold = Pure.needsHold(rarity, level)
		return {
			Title = "Sell?",
			Line = Pure.confirmText("Sell", icon, name, level, price),
			Yes = if hold then "Hold to sell" else "Sell",
			Kind = "Destructive",
			Hold = if hold then Pure.HOLD_SECONDS else 0,
		}
	end
	return {
		Title = "Hire?",
		Line = Pure.confirmText("Hire", icon, name, 1, price),
		Yes = "Hire",
		Kind = "Primary",
		Hold = 0,
	}
end

-- The 🎲 popup's notes: "🚫 Never Legendary+", Lucky Stock rolls the same odds, the Epic gate ("🏥 Epic: hospital
-- Lv 3+", only while the Agency can stock Epics) and how often new nurses come.
function Pure.oddsNotes(odds: any, epicLevel: any, restockSeconds: any): { string }
	local notes: { string } = {}
	local never = Pure.neverText(odds)
	if never then
		table.insert(notes, never)
	end
	table.insert(notes, "🍀 Lucky Stock: same odds") -- uirules: allow LeadEmoji (an odds note, pinned by tests/ProgressionPanels.spec)
	local epic = if type(odds) == "table" then odds.Epic else nil
	if finite(epicLevel) and epicLevel > 1 and finite(epic) and epic > 0 then
		table.insert(notes, "🏥 Epic: hospital Lv " .. tostring(math.floor(epicLevel)) .. "+") -- uirules: allow TypedEmoji, uirules: allow LeadEmoji (an odds note, pinned by tests/ProgressionPanels.spec)
	end
	table.insert(notes, Pure.everyText(restockSeconds))
	return notes
end

export type OddsSpec = { Title: string, Rows: { { Icon: string, Name: string, Percent: number } }, Notes: { string } }

-- THE odds popup (Hud.oddsPopup): every rarity the Agency can stock, lowest first, each with its word and the
-- server's own number (AgencyView.Odds), and the notes. `rarities` is Data/Rarities (its Icon and Name).
function Pure.oddsSpec(odds: any, rarities: any, notes: { string }?): OddsSpec
	local rows: { { Icon: string, Name: string, Percent: number } } = {}
	for _, row in Pure.oddsRows(odds) do
		local info = if type(rarities) == "table" then rawget(rarities, row.Rarity) else nil
		local known = type(info) == "table"
		table.insert(rows, {
			Icon = if known and type(info.Icon) == "string" then info.Icon else "❔",
			Name = if known and type(info.Name) == "string" then info.Name else row.Rarity,
			Percent = row.Odds,
		})
	end
	return { Title = "🎲 Odds", Rows = rows, Notes = notes or {} } -- uirules: allow TitleEmoji, uirules: allow TypedEmoji (pinned by tests/ProgressionPanels.spec; Modal draws the title as words)
end

-- The Sell tab's nurses: the ones you own that this game knows, in the Journal's order (Data/Nurses.Order).
function Pure.sellList(nurses: any, roster: any): { string }
	local out: { string } = {}
	if type(nurses) ~= "table" or type(roster) ~= "table" or type(roster.Order) ~= "table" then
		return out
	end
	for _, nurseId in roster.Order do
		if type(rawget(roster, nurseId)) == "table" and type(nurses[nurseId]) == "table" then
			table.insert(out, nurseId)
		end
	end
	return out
end
-- PURE-END

Pure.use(Icons)
AgencyPanel.Pure = Pure -- for a scratch harness and the spec

------------------------------------------------------------------------------------------------------------------
-- Look helpers: the one template (look build plan §B8) made calm (UI direction R2, R3): cards without lines on white
-- paper, the rarity frame on the face tile only, buttons by role (Kit.setRole), sizes from Theme.
------------------------------------------------------------------------------------------------------------------

local ROW_HEIGHT = 80
local FACE = Theme.Calm.ArtTile
local PAD = Theme.Space.PadCard
local BAR_HEIGHT = Theme.Size.ButtonHeight
local ODDS_WIDTH = 104
local GAP = Theme.Space.Gap
local TABS: { Modal.TabSpec } = {
	{ Id = "Hire", Icon = Icons.Door.Agency, Caption = "Hire" },
	{ Id = "Sell", Icon = Icons.Unit.Cash, Caption = "Sell" },
}

local function scrollPage(name: string, parent: Instance): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, BAR_HEIGHT + GAP)
	scroll.Size = UDim2.new(1, 0, 1, -(BAR_HEIGHT + GAP))
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = Theme.Colors.Stroke
	scroll.Selectable = false
	scroll.Parent = parent
	local list = Kit.list(scroll, Enum.FillDirection.Vertical, Theme.Space.PadCard)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, Theme.Space.Tight)
	pad.PaddingBottom = UDim.new(0, Theme.Space.Line)
	pad.PaddingRight = UDim.new(0, Theme.Space.PadCard) -- clear of the scroll bar
	pad.Parent = scroll
	return scroll
end

------------------------------------------------------------------------------------------------------------------
-- The panel
------------------------------------------------------------------------------------------------------------------

type Row = {
	Key: string, -- the slot (Hire) or NurseId (Sell) it shows
	NurseId: string,
	Frame: Frame,
	Name: TextLabel,
	Sub: TextLabel,
	Button: TextButton,
}

function AgencyPanel.init(ctx: Types.Ctx)
	local data = ctx.Data :: any
	local cfg = ctx.Config
	local player = ctx.Player

	local view: any = nil -- the latest AgencyView from the server
	local status = "" -- a reply to show when there's no view (e.g. "Coming soon!")
	local listed: { [string]: boolean } = {}
	local tab = "Hire"
	local busy = false
	local fetching = false
	local askedKey = "" -- Pure.priceKey when the view was last asked for
	local hireRows: { Row } = {}
	local sellRows: { Row } = {}
	local hireKey = ""
	local sellKey = ""

	local function nurseOf(nurseId: any): any
		local nurse = if type(nurseId) == "string" then rawget(data.Nurses, nurseId) else nil
		return if type(nurse) == "table" then nurse else nil
	end

	local function isKnown(nurseId: string): boolean
		return nurseOf(nurseId) ~= nil
	end

	local function myEntry(nurseId: string): any
		local nurses = ctx.State.Nurses
		return if type(nurses) == "table" then nurses[nurseId] else nil
	end

	local function effects(): any
		local ok, result = pcall(RebirthLogic.effects, ctx.State, cfg, data.Perks, data.Tree)
		return if ok then result else nil
	end

	-- A stock nurse's fact in words: "Healer · Bath Room" (its job, then its specialty; "Any" counts everywhere).
	local function about(nurse: any): string
		local job = rawget(data.Jobs, nurse.Role)
		local dept = if nurse.Specialty == "Any" then nil else rawget(data.Departments, nurse.Specialty)
		local jobName = if job and type(job.Name) == "string" then job.Name else tostring(nurse.Role)
		return jobName .. " · " .. (if dept and type(dept.Name) == "string" then dept.Name else "Any department")
	end

	--------------------------------------------------------------------------------------------------------------
	-- The modal, its tab column and its bar
	--------------------------------------------------------------------------------------------------------------
	local modal = Hud.modal(ctx, {
		Name = "Agency",
		Title = "Agency",
	})
	local render: () -> ()
	local fetchListed: () -> ()

	-- THE tab pattern: Hire and Sell down the left (Modal.tabs paints them with Kit.tab).
	local tabs = Modal.tabs(modal, TABS, function(id: string)
		tab = if id == "Sell" then "Sell" else "Hire"
		render()
		if tab == "Sell" and modal.isOpen() then
			task.spawn(fetchListed)
		end
	end)
	local content = tabs.Content
	local function tabButton(id: string): GuiObject?
		local found = tabs.Column:FindFirstChild("Tab_" .. id, true)
		return if found and found:IsA("GuiObject") then found else nil
	end
	modal.Focus = tabButton("Hire")

	-- The bar: how often new nurses come, in words (never a clock), and the Odds link (a Quiet button: THE odds
	-- popup, one tap away on every visit: red line 3).
	local note = Kit.fact({
		Name = "Note",
		Text = Icons.words(Pure.everyText(cfg.Agency.RestockSeconds)),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(0, BAR_HEIGHT / 2),
		Size = UDim2.new(1, -(ODDS_WIDTH + GAP), 0, Theme.TextSize.Caption + Theme.Space.Tight),
		Parent = content,
	})
	local oddsButton = Kit.button({
		Name = "Odds",
		Kind = "Quiet",
		Text = "Odds",
		TextScaled = true,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(ODDS_WIDTH, BAR_HEIGHT),
		Parent = content,
	})
	Kit.textLimit(oddsButton, Theme.TextSize.Button)

	local hirePage = scrollPage("HirePage", content)
	local sellPage = scrollPage("SellPage", content)
	local emptyLabel = Kit.fact({
		Name = "Empty",
		Text = "",
		LayoutOrder = 999,
		Visible = false,
	})

	--------------------------------------------------------------------------------------------------------------
	-- THE odds popup: the server's own table (the one its rolls use); before the first view, the same Logic on the
	-- same Config
	--------------------------------------------------------------------------------------------------------------
	oddsButton.Activated:Connect(function()
		local shown = if view and type(view.Odds) == "table" then view.Odds else AgencyLogic.odds(cfg)
		local notes = Pure.oddsNotes(shown, BeltLogic.minLevel(cfg, "Epic"), cfg.Agency.RestockSeconds)
		Hud.oddsPopup(ctx, Pure.oddsSpec(shown, data.Rarities, notes))
	end)

	--------------------------------------------------------------------------------------------------------------
	-- Rows
	--------------------------------------------------------------------------------------------------------------
	-- THE row (R2, R3): a Kit.card with no line, the face in its rarity frame (a Kit.artTile well), the name, one Soft
	-- fact, and the one button on the right.
	local function newRow(parent: Instance, key: string, nurse: any, nurseId: string, order: number): Row
		local row = Kit.card({
			Name = "Row_" .. key,
			Pad = false,
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			LayoutOrder = order,
			Parent = parent,
		})
		local face = Kit.artTile({
			Name = "Face",
			Rarity = nurse.Rarity,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, PAD, 0.5, 0),
			Size = UDim2.fromOffset(FACE, FACE),
			Parent = row,
		})
		local portrait = Hud.portrait(nurse.Look, false)
		portrait.AnchorPoint = Vector2.new(0.5, 0.5)
		portrait.Position = UDim2.fromScale(0.5, 0.5)
		portrait.Size = UDim2.fromScale(0.92, 0.92)
		portrait.Parent = face
		local textLeft = PAD + FACE + PAD
		local nameHeight = Theme.TextSize.Body + Theme.Space.Tight
		local name = Kit.name({
			Name = "NurseName",
			Text = nurse.Name,
			Position = UDim2.fromOffset(textLeft, PAD),
			Size = UDim2.new(0.6, -textLeft - Theme.Space.Line, 0, nameHeight),
			Parent = row,
		})
		local sub = Kit.fact({
			Name = "Sub",
			Text = "",
			Position = UDim2.fromOffset(textLeft, PAD + nameHeight + Theme.Space.Tight),
			Size = UDim2.new(0.6, -textLeft - Theme.Space.Line, 0, Theme.TextSize.Caption + Theme.Space.Tight),
			Parent = row,
		})
		local button = Kit.button({
			Name = "Act",
			Kind = "Primary",
			Text = "",
			TextScaled = true,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -PAD, 0.5, 0),
			Size = UDim2.new(0.4, -PAD, 0, Theme.Size.ButtonHeight),
			Parent = row,
		})
		Kit.textLimit(button, Theme.TextSize.Button)
		local limits = Instance.new("UISizeConstraint")
		limits.MinSize = Vector2.new(112, Theme.Size.ButtonHeight)
		limits.MaxSize = Vector2.new(200, Theme.Size.ButtonHeight)
		limits.Parent = button
		return { Key = key, NurseId = nurseId, Frame = row, Name = name, Sub = sub, Button = button }
	end

	local function paint(button: TextButton, text: string, role: string)
		if button.Text ~= text then
			button.Text = text
		end
		Kit.setRole(button, role)
	end

	local function clearRows(rows: { Row })
		for _, row in rows do
			row.Frame:Destroy()
		end
		table.clear(rows)
	end

	local function showEmpty(parent: Instance, text: string)
		emptyLabel.Text = text
		emptyLabel.Visible = text ~= ""
		emptyLabel.Parent = parent
	end

	local askBuy: (slotNumber: number) -> ()
	local askSell: (nurseId: string) -> ()

	local function renderHire()
		local slots = if view and type(view.Slots) == "table" then view.Slots else {}
		local parts: { string } = { tostring(if view then view.Restock else "") }
		for _, slot in slots do
			table.insert(parts, tostring(slot.Slot) .. "=" .. tostring(slot.NurseId))
		end
		local key = table.concat(parts, ",")
		if key ~= hireKey then
			hireKey = key
			clearRows(hireRows)
			for order, slot in slots do
				local nurse = nurseOf(slot.NurseId)
				if nurse then
					local row = newRow(hirePage, tostring(slot.Slot), nurse, slot.NurseId, order)
					-- A Lucky Stock slot says so in words (no sticker of its own).
					row.Sub.Text = (if slot.Personal == true then "Lucky Stock · " else "") .. about(nurse)
					local slotNumber = slot.Slot
					row.Button.Activated:Connect(function()
						askBuy(slotNumber)
					end)
					table.insert(hireRows, row)
				end
			end
		end
		for _, row in hireRows do
			local slot = nil
			for _, candidate in slots do
				if tostring(candidate.Slot) == row.Key then
					slot = candidate
				end
			end
			if slot then
				local state = Pure.cardState(slot, ctx.State, cfg, isKnown)
				local text = if busy then Icons.State.Waiting else Pure.calmButton(state, slot)
				-- The price is the Primary; ✅ (bought) is Quiet; "Roster full" (it opens the Team page) is Secondary;
				-- a gate (🔒, its words in the fact line), MAX or short of cash is the gated grey (a tap says why).
				local role = if state == "Ready"
					then "Primary"
					elseif state == "Bought" then "Quiet"
					elseif state == "Full" then "Secondary"
					else "Disabled"
				paint(row.Button, text, role)
				local nurse = nurseOf(slot.NurseId)
				if nurse then
					local lucky = if slot.Personal == true then "Lucky Stock · " else ""
					row.Sub.Text = if state == "Gate" then Pure.gateNote(slot.Gate) else lucky .. about(nurse)
				end
			end
		end
		if #hireRows == 0 then
			showEmpty(hirePage, if view then "Back soon" elseif status ~= "" then status else Icons.State.Waiting)
		elseif emptyLabel.Parent == hirePage then
			showEmpty(hirePage, "")
		end
	end

	local function renderSell()
		local ids = Pure.sellList(ctx.State.Nurses, data.Nurses)
		local key = table.concat(ids, ",")
		if key ~= sellKey then
			sellKey = key
			clearRows(sellRows)
			for order, nurseId in ids do
				local nurse = nurseOf(nurseId) :: any
				local row = newRow(sellPage, nurseId, nurse, nurseId, order)
				row.Button.Activated:Connect(function()
					askSell(nurseId)
				end)
				table.insert(sellRows, row)
			end
		end
		local sellBack = if view then view.SellBack else nil
		for _, row in sellRows do
			local entry = myEntry(row.NurseId)
			local level = if type(entry) == "table" and type(entry.Level) == "number" then entry.Level else 1
			local copies = if type(entry) == "table" and type(entry.Copies) == "number" then entry.Copies else 1
			local resting = type(entry) == "table" and entry.Job == NurseLogic.REST
			local state = Pure.sellState(row.NurseId, data.Nurses, sellBack, listed)
			local price = if type(sellBack) == "table" then sellBack[row.NurseId] else nil
			row.Sub.Text = Pure.sellFact(level, copies, resting, state, price)
			local text = if busy then Icons.State.Waiting else Pure.sellButton(state)
			-- Sell is Destructive (always behind THE confirm, a hold for Epic and up); the rest is the gated grey.
			paint(row.Button, text, if state == "Sell" then "Destructive" else "Disabled")
		end
		if #sellRows == 0 then
			showEmpty(sellPage, "No nurses yet")
		elseif emptyLabel.Parent == sellPage then
			showEmpty(sellPage, "")
		end
	end

	render = function()
		if not modal.isOpen() then
			return
		end
		hirePage.Visible = tab == "Hire"
		sellPage.Visible = tab == "Sell"
		note.Text = if tab == "Hire"
			then Icons.words(Pure.everyText(cfg.Agency.RestockSeconds))
			else "The Agency buys nurses"
		if tab == "Hire" then
			renderHire()
		else
			renderSell()
		end
	end

	local function setView(fresh: any)
		if type(fresh) ~= "table" or type(fresh.Slots) ~= "table" then
			return
		end
		local restocked = view ~= nil and view.Restock ~= fresh.Restock
		view = fresh
		status = ""
		render()
		if restocked and modal.isOpen() and tab == "Hire" then
			Hud.sound("Restock")
			for _, row in hireRows do
				Hud.pop(row.Frame, 1.06)
			end
		end
	end

	local function fetch()
		if fetching then
			return
		end
		fetching = true
		askedKey = Pure.priceKey(ctx.State, effects())
		local ok, message, payload = Hud.ask(ctx.Remotes.GetAgency)
		fetching = false
		if ok and type(payload) == "table" then
			setView(payload)
		elseif not ok then
			status = message
			render()
		end
	end

	-- The view, asking for it (or waiting for the ask already in flight) when there's none yet. Yields.
	local function ensureView(): boolean
		if view then
			return true
		end
		if not fetching then
			fetch()
		end
		local waited = 0
		while not view and fetching and waited < 12 do
			waited += task.wait(0.1)
		end
		return view ~= nil
	end

	fetchListed = function()
		local ok, _, payload = Hud.ask(ctx.Remotes.GetMarket)
		if ok and type(payload) == "table" then
			listed = Pure.listed(payload, player.UserId)
			render()
		end
	end

	--------------------------------------------------------------------------------------------------------------
	-- Buying and selling (always THE confirm first; the server checks everything again)
	--------------------------------------------------------------------------------------------------------------
	local function slotOf(number: number): any
		if view then
			for _, slot in view.Slots do
				if slot.Slot == number then
					return slot
				end
			end
		end
		return nil
	end

	local function rowButton(rows: { Row }, key: string): TextButton?
		for _, row in rows do
			if row.Key == key then
				return row.Button
			end
		end
		return nil
	end

	local function buy(slot: any)
		if busy then
			return
		end
		busy = true
		render()
		local owned = myEntry(slot.NurseId) ~= nil
		local ok, message, payload = Hud.ask(ctx.Remotes.AgencyBuy, slot.Slot, slot.NurseId, slot.Price)
		busy = false
		if type(payload) == "table" then
			setView(payload)
		end
		if ok then
			-- The cue comes with the server's NurseNews (Hired: Feel/Sounds), as for a belt hire.
			local button = rowButton(hireRows, tostring(slot.Slot))
			if button then
				Hud.pop(button, 1.15)
			end
			-- A first copy gets the big NewNurse celebration; a copy's level-up a toast (as the belt does).
			if owned and message ~= "" then
				ctx.toast(message)
			end
		else
			ctx.toast(if message ~= "" then message else "Oops! Try again.")
		end
		render()
	end

	askBuy = function(slotNumber: number)
		local slot = slotOf(slotNumber)
		local nurse = if slot then nurseOf(slot.NurseId) else nil
		if not slot or not nurse or busy then
			return
		end
		local button = rowButton(hireRows, tostring(slotNumber))
		local state = Pure.cardState(slot, ctx.State, cfg, isKnown)
		if state == "Bought" then
			ctx.toast("You bought this one")
		elseif state == "Gate" then
			ctx.toast(Pure.gateNote(slot.Gate))
			Hud.shake(button)
		elseif state == "Full" then
			-- Making room is your call: the Team page, where you can sell or list one.
			Hud.sound("Pop")
			ctx.fire("Open", "Nurses", "Team")
		elseif state == "Max" then
			ctx.toast("Max level!")
			Hud.shake(button)
		elseif state == "Poor" then
			local cash = if type(ctx.State.Cash) == "number" then ctx.State.Cash else 0
			ctx.toast("Need " .. Icons.unit("Cash", Pure.commas(math.max(1, slot.Price - cash))) .. " more!")
			Hud.shake(button)
		else
			Hud.confirm(ctx, Pure.confirmSpec("Hire", nurse.Icon, nurse.Name, 1, slot.Price, nurse.Rarity), function()
				buy(slot)
			end)
		end
	end

	local function sell(nurseId: string, price: number)
		if busy then
			return
		end
		busy = true
		render()
		local ok, message, payload = Hud.ask(ctx.Remotes.SellNurse, nurseId, price)
		busy = false
		if type(payload) == "table" then
			setView(payload)
		end
		if ok then
			-- The Sold cue comes with the server's NurseNews (Sold: Feel/Sounds); the coins fly to 💰 here.
			Hud.fly(modal.Panel, Icons.Unit.Cash, "Cash", 6)
			ctx.toast(if message ~= "" then message else "Sold!")
		else
			ctx.toast(if message ~= "" then message else "Oops! Try again.")
		end
		render()
	end

	askSell = function(nurseId: string)
		local nurse = nurseOf(nurseId)
		local entry = myEntry(nurseId)
		if not nurse or type(entry) ~= "table" or busy or not ensureView() then
			return
		end
		local sellBack = if view then view.SellBack else nil
		local state = Pure.sellState(nurseId, data.Nurses, sellBack, listed)
		local button = rowButton(sellRows, nurseId)
		if state == "Listed" then
			ctx.toast("Unlist it on the Market first")
			Hud.shake(button)
			return
		elseif state == "Stays" then
			ctx.toast("This one stays with you!")
			return
		elseif state ~= "Sell" then
			return
		end
		local price = sellBack[nurseId]
		local level = if type(entry.Level) == "number" then entry.Level else 1
		-- Selling an Epic or rarer, or any nurse at Lv 2+, is a 1 s hold (Pure.needsHold): Hud.confirm's Hold.
		Hud.confirm(ctx, Pure.confirmSpec("Sell", nurse.Icon, nurse.Name, level, price, nurse.Rarity), function()
			sell(nurseId, price)
		end)
	end

	--------------------------------------------------------------------------------------------------------------
	-- Opening, news and the kiosk
	--------------------------------------------------------------------------------------------------------------
	local function open(name: string?)
		tabs.select(if name == "Sell" then "Sell" else "Hire")
		modal.Focus = tabButton(tab)
		modal.open()
		render()
		task.spawn(fetch)
		task.spawn(fetchListed)
	end

	ctx.on("Open", function(name: any, which: any)
		if name == "Agency" then
			open(if type(which) == "string" then which else nil)
		end
	end)

	ctx.on("Sell", function(nurseId: any)
		if type(nurseId) ~= "string" or not nurseOf(nurseId) or myEntry(nurseId) == nil then
			return
		end
		open("Sell")
		task.spawn(askSell, nurseId)
	end)

	ctx.on("AgencyNews", function(payload: any)
		setView(payload)
	end)

	ctx.on("MarketNews", function(payload: any)
		if type(payload) == "table" then
			listed = Pure.listed(payload, player.UserId)
			render()
		end
	end)

	ctx.on("NurseNews", function(info: any)
		if type(info) == "table" and info.Kind == "Listed" and type(info.NurseId) == "string" then
			listed[info.NurseId] = info.On == true or nil
			render()
		end
	end)

	-- Your cash and nurses change the buttons; your level, rebirths, Bargain or Lucky Stock change the view itself.
	ctx.onState(function(state: any)
		if not modal.isOpen() then
			return
		end
		render()
		if Pure.priceKey(state, effects()) ~= askedKey then
			task.spawn(fetch)
		end
	end)

	-- The kiosk's ProximityPrompt (Workspace.NurseAgency's "Prompt", or any prompt in a kit kiosk): heard through
	-- ProximityPromptService on this client, so a kiosk that streams in late (or out and back) still opens the panel.
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who == player and prompt:FindFirstAncestor("NurseAgency") ~= nil then
			ctx.fire("Open", "Agency")
		end
	end)
end

return AgencyPanel
