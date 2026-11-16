--!strict
-- The 🏢 Nurse Agency panel (Progression v2 build plan §B3.1/§B9, §C T3; design §8, memory-20261116-018). OWNER: T3.
--   init(ctx)   opens on ctx.fire("Open", "Agency", "Hire" | "Sell"?) (the kiosk's prompt: Workspace.NurseAgency's
--               ProximityPrompt "Prompt", client Triggered; NursePanel's 🏢 button) and on the bus "Sell" (nurseId)
--               (NursePanel's Sell button: the Sell tab and that nurse's confirm); listens to the bus "AgencyNews"
--               (view), "MarketNews" (which of yours are listed) and "NurseNews". Asks GetAgency, AgencyBuy(slot,
--               nurseId, expect) and SellNurse(nurseId, expect); `expect` is always the price the server showed.
-- Inside (a Hud.modal Panel, cyan like the 👩‍⚕️ button):
--   · 🛒 Hire: the stock, one row per nurse (4, or 6 with 🍀 Lucky Stock: those wear a 🍀): portrait, rarity frame,
--     name, its job, specialty and ability icons, and one button: "Hire 💰150" · "✅ Bought" · "🏥 Lv 3" / "🏢 R1"
--     (a gate: no lock, no price) · "Roster full" (opens the 👩‍⚕️ Team page) · "⭐ MAX". Over it: "🔄 New nurses
--     every 5 min", never a clock (§E9).
--   · 💰 Sell: every nurse you own with what the Agency pays (30% of the belt's base price per copy): "Sell 💰30" ·
--     "🏷️ Listed" (unlist it on the Market first) · "🏢 Stays" (rebirth-only).
--   · 🎲: the odds popup, from the server's own table (AgencyView.Odds): 70 / 26 / 4, "🚫 Never Legendary+", the
--     Lucky Stock uses the same odds, and the Epic gate.
--   · Every buy and sell asks first ("Hire 🐶 Puff Pup for 💰150?" · "Sell 🐶 Lv 7 for 💰30?"); "Not now" is the
--     default button, and selling an Epic or rarer is a 1 s hold (Kit.holdButton).
-- Cash only, no Robux, no "hurry" words, no countdowns (red line 3). Every motion goes through Hud.pop / Kit (they
-- honour Kit.reducedMotion()). Buttons are 56 px tall and every label is 6 words or fewer.

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local Logic = Shared:WaitForChild("Logic")
local AgencyLogic = require(Logic:WaitForChild("Agency"))
local BeltLogic = require(Logic:WaitForChild("Belt"))
local NurseLogic = require(Logic:WaitForChild("Nurse"))
local RebirthLogic = require(Logic:WaitForChild("Rebirth"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local AgencyPanel = {}

------------------------------------------------------------------------------------------------------------------
-- Pure helpers: no Roblox services or types; the only upvalue is Logic/Nurse as NurseLogic (pure itself).
-- tests/AgencyServer.spec loads the block between the PURE markers on its own, so keep it that way.
------------------------------------------------------------------------------------------------------------------
-- PURE-BEGIN
local Pure = {}

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
		return "🔄 New nurses every " .. tostring(s // 60) .. " min"
	end
	return "🔄 New nurses every " .. tostring(s) .. " s"
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
		return "✅ Bought"
	elseif cardState == "Gate" then
		return tostring(slot.Gate)
	elseif cardState == "Full" then
		return "Roster full"
	elseif cardState == "Max" then
		return "⭐ MAX"
	end
	return "Hire 💰" .. Pure.commas(slot.Price)
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
		return string.format("Sell %s Lv %d for 💰%s?", icon, math.floor(level), Pure.commas(price))
	end
	return string.format("Hire %s %s for 💰%s?", icon, name, Pure.commas(price))
end

-- Selling an Epic or rarer is a hold (Kit.holdButton), not a tap.
function Pure.needsHold(rarity: any): boolean
	return Pure.rank(rarity) >= 3
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

AgencyPanel.Pure = Pure -- for a scratch harness and the spec

------------------------------------------------------------------------------------------------------------------
-- Look helpers
------------------------------------------------------------------------------------------------------------------

local ROW_HEIGHT = 76
local FACE = 60
local BAR_HEIGHT = Theme.Size.ButtonHeight
local NOTE_HEIGHT = 28
local ODDS_WIDTH = 64
local GAP = Theme.Size.Gap
local HOLD_SECONDS = 1

local function hexColor(value: any, fallback: Color3): Color3
	if type(value) ~= "string" then
		return fallback
	end
	local ok, color = pcall(Color3.fromHex, value)
	return if ok then color else fallback
end

local function textLimit(label: TextLabel | TextButton, max: number)
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

local function padButton(button: GuiObject, x: number, y: number)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, x)
	pad.PaddingRight = UDim.new(0, x)
	pad.PaddingTop = UDim.new(0, y)
	pad.PaddingBottom = UDim.new(0, y)
	pad.Parent = button
end

local function scrollPage(name: string, parent: Instance): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, BAR_HEIGHT + GAP + NOTE_HEIGHT + 4)
	scroll.Size = UDim2.new(1, 0, 1, -(BAR_HEIGHT + GAP + NOTE_HEIGHT + 4))
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = Theme.Colors.Stroke
	scroll.Selectable = false
	scroll.Parent = parent
	local list = Kit.list(scroll, Enum.FillDirection.Vertical, 8)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 3)
	pad.PaddingRight = UDim.new(0, 12)
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

	local function rarityInfo(rarity: string): any
		return rawget(data.Rarities, rarity) or rawget(data.Rarities, "Common")
	end

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

	local function icons(nurse: any): string
		local job = rawget(data.Jobs, nurse.Role)
		local dept = if nurse.Specialty == "Any" then nil else rawget(data.Departments, nurse.Specialty)
		local ability = rawget(data.Abilities, nurse.Ability)
		return string.format(
			"%s %s  %s  %s",
			if job then job.Icon else "",
			tostring(nurse.Role),
			if dept then dept.Icon else Pure.ANY_ICON,
			if ability then ability.Icon else ""
		)
	end

	--------------------------------------------------------------------------------------------------------------
	-- The modal and its bar
	--------------------------------------------------------------------------------------------------------------
	local modal = Hud.modal(ctx, {
		Name = "Agency",
		Title = "🏢 Agency",
		Accent = Theme.Colors.Cyan,
	})
	local body = modal.Body

	local tabWidth = UDim2.new(0.5, -(ODDS_WIDTH + GAP * 2) / 2, 0, BAR_HEIGHT)
	local hireTab = Kit.button({
		Name = "HireTab",
		Kind = "Cyan",
		Text = "🛒 Hire",
		TextScaled = true,
		Position = UDim2.fromOffset(0, 0),
		Size = tabWidth,
		Parent = body,
	})
	padButton(hireTab, 10, 10)
	local sellTab = Kit.button({
		Name = "SellTab",
		Kind = "Cyan",
		Text = "💰 Sell",
		TextScaled = true,
		Position = UDim2.new(0.5, -(ODDS_WIDTH + GAP * 2) / 2 + GAP, 0, 0),
		Size = tabWidth,
		Parent = body,
	})
	padButton(sellTab, 10, 10)
	local oddsButton = Kit.button({
		Name = "Odds",
		Kind = "Purple",
		Text = "🎲",
		TextScaled = true,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(ODDS_WIDTH, BAR_HEIGHT),
		Parent = body,
	})
	padButton(oddsButton, 8, 8)
	modal.Focus = hireTab

	local note = Kit.label({
		Name = "Note",
		Text = Pure.everyText(cfg.Agency.RestockSeconds),
		TextScaled = true,
		TextColor3 = Theme.Colors.InkSoft,
		Position = UDim2.fromOffset(0, BAR_HEIGHT + GAP),
		Size = UDim2.new(1, 0, 0, NOTE_HEIGHT),
		Parent = body,
	})
	textLimit(note, 22)

	local hirePage = scrollPage("HirePage", body)
	local sellPage = scrollPage("SellPage", body)
	local emptyLabel = Kit.label({
		Name = "Empty",
		Text = "",
		TextScaled = true,
		TextColor3 = Theme.Colors.InkSoft,
		Size = UDim2.new(1, -12, 0, 44),
		LayoutOrder = 999,
		Visible = false,
	})
	textLimit(emptyLabel, 24)

	-- A tab in the panel's colour: a pale tint while it waits, full candy when it's open.
	local function paintTab(button: TextButton, selected: boolean)
		local color = Theme.Colors.Cyan
		button.BackgroundColor3 = if selected then Kit.lighten(color, 0.08) else Kit.lighten(color, 0.7)
		button.TextColor3 = if selected then Theme.Colors.OnColor else Theme.Colors.Ink
		Kit.outline(button, 2).Enabled = selected
	end

	--------------------------------------------------------------------------------------------------------------
	-- The confirm popup ("Not now" first) and the odds popup
	--------------------------------------------------------------------------------------------------------------
	local confirm = Hud.modal(ctx, {
		Name = "AgencyConfirm",
		Title = "🏢 Agency",
		Accent = Theme.Colors.Cyan,
		Layer = "Popup",
		MaxSize = Vector2.new(420, 340),
	})
	local confirmFace = frame({
		Name = "Face",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(92, 92),
		BackgroundColor3 = Theme.Colors.Card,
		Parent = confirm.Body,
	})
	Kit.corner(confirmFace, 16)
	local question = Kit.label({
		Name = "Question",
		Text = "",
		TextScaled = true,
		Font = Theme.DisplayFont,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 100),
		Size = UDim2.new(1, -8, 0, 52),
		Parent = confirm.Body,
	})
	textLimit(question, 28)
	local buttonRow = UDim2.new(0.5, -GAP / 2, 0, Theme.Size.ButtonHeight)
	local notNow = Kit.button({
		Name = "NotNow",
		Kind = "Quiet",
		Text = "Not now",
		TextScaled = true,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = buttonRow,
		Parent = confirm.Body,
	})
	padButton(notNow, 10, 12)
	local yesTap = Kit.button({
		Name = "Yes",
		Kind = "Good",
		Text = "✅ Yes!",
		TextScaled = true,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = buttonRow,
		Parent = confirm.Body,
	})
	padButton(yesTap, 10, 12)
	local yesHold = Kit.button({
		Name = "Hold",
		Kind = "Primary",
		Text = "✋ Hold to sell",
		TextScaled = true,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = buttonRow,
		Visible = false,
		Parent = confirm.Body,
	})
	padButton(yesHold, 10, 12)
	confirm.Focus = notNow

	local pending: (() -> ())? = nil
	local function accept()
		local fn = pending
		pending = nil
		if fn then
			confirm.close()
			task.spawn(fn)
		end
	end
	notNow.Activated:Connect(function()
		pending = nil
		confirm.close()
	end)
	yesTap.Activated:Connect(accept)
	Kit.holdButton(yesHold, HOLD_SECONDS, accept)

	local function ask(nurse: any, text: string, hold: boolean, onYes: () -> ())
		for _, child in confirmFace:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local color = hexColor(rarityInfo(nurse.Rarity).Color, Theme.Colors.Quiet)
		confirmFace.BackgroundColor3 = Kit.lighten(color, 0.45)
		Kit.rarityFrame(confirmFace, nurse.Rarity)
		local portrait = Hud.portrait(nurse.Look, false)
		portrait.AnchorPoint = Vector2.new(0.5, 0.5)
		portrait.Position = UDim2.fromScale(0.5, 0.5)
		portrait.Size = UDim2.fromScale(0.92, 0.92)
		portrait.Parent = confirmFace
		question.Text = text
		yesTap.Visible = not hold
		yesHold.Visible = hold
		pending = onYes
		confirm.open()
	end

	local odds = Hud.modal(ctx, {
		Name = "AgencyOdds",
		Title = "🎲 Odds",
		Accent = Theme.Colors.Purple,
		Layer = "Popup",
		MaxSize = Vector2.new(420, 460),
	})
	local oddsScroll = scrollPage("Rows", odds.Body)
	oddsScroll.Position = UDim2.new()
	oddsScroll.Size = UDim2.fromScale(1, 1)

	local function renderOdds()
		for _, child in oddsScroll:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		-- The server's own table (the one its rolls use); before the first view, the same Logic on the same Config.
		local shown = if view and type(view.Odds) == "table" then view.Odds else AgencyLogic.odds(cfg)
		for order, row in Pure.oddsRows(shown) do
			local info = rarityInfo(row.Rarity)
			local color = hexColor(info.Color, Theme.Colors.Quiet)
			local line = frame({
				Name = row.Rarity,
				BackgroundColor3 = Theme.Colors.Paper,
				Size = UDim2.new(1, 0, 0, 44),
				LayoutOrder = order,
				Parent = oddsScroll,
			})
			Kit.corner(line, 12)
			Kit.rarityFrame(line, row.Rarity)
			local chip = frame({
				Name = "Rarity",
				BackgroundColor3 = Kit.lighten(color, 0.1),
				Position = UDim2.fromOffset(4, 4),
				Size = UDim2.new(0.62, -8, 1, -8),
				Parent = line,
			})
			Kit.corner(chip, 10)
			Palette.candyGradient(chip)
			local name = Kit.label({
				Name = "Name",
				Text = info.Icon .. " " .. info.Name,
				TextScaled = true,
				Outlined = true,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -8, 1, -6),
				Parent = chip,
			})
			textLimit(name, 22)
			local percent = Kit.label({
				Name = "Odds",
				Text = Pure.percent(row.Odds),
				TextScaled = true,
				Font = Theme.DisplayFont,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.new(0.38, -8, 1, -12),
				Parent = line,
			})
			textLimit(percent, 24)
		end
		local notes: { string } = {}
		local never = Pure.neverText(shown)
		if never then
			table.insert(notes, never)
		end
		table.insert(notes, "🍀 Lucky Stock: same odds")
		local epicLevel = BeltLogic.minLevel(cfg, "Epic")
		if epicLevel > 1 and (shown.Epic or 0) > 0 then
			table.insert(notes, "🏥 Epic: hospital Lv " .. epicLevel .. "+")
		end
		table.insert(notes, Pure.everyText(cfg.Agency.RestockSeconds))
		for index, text in notes do
			local label = Kit.label({
				Name = "Note" .. index,
				Text = text,
				TextScaled = true,
				TextColor3 = Theme.Colors.InkSoft,
				Size = UDim2.new(1, 0, 0, 26),
				LayoutOrder = 100 + index,
				Parent = oddsScroll,
			})
			textLimit(label, 20)
		end
	end

	oddsButton.Activated:Connect(function()
		renderOdds()
		odds.open()
	end)

	--------------------------------------------------------------------------------------------------------------
	-- Rows
	--------------------------------------------------------------------------------------------------------------
	local function newRow(parent: Instance, key: string, nurse: any, nurseId: string, order: number): Row
		local color = hexColor(rarityInfo(nurse.Rarity).Color, Theme.Colors.Quiet)
		local row = frame({
			Name = "Row_" .. key,
			BackgroundColor3 = Theme.Colors.Paper,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			LayoutOrder = order,
			Parent = parent,
		})
		Kit.corner(row, 16)
		Kit.rarityFrame(row, nurse.Rarity)
		local face = frame({
			Name = "Face",
			Position = UDim2.fromOffset(8, (ROW_HEIGHT - FACE) / 2),
			Size = UDim2.fromOffset(FACE, FACE),
			BackgroundColor3 = Kit.lighten(color, 0.45),
			Parent = row,
		})
		Kit.corner(face, 12)
		Palette.candyGradient(face)
		Kit.stroke(face, Theme.Colors.Outline, 2)
		local portrait = Hud.portrait(nurse.Look, false)
		portrait.AnchorPoint = Vector2.new(0.5, 0.5)
		portrait.Position = UDim2.fromScale(0.5, 0.5)
		portrait.Size = UDim2.fromScale(0.92, 0.92)
		portrait.Parent = face
		local textLeft = 8 + FACE + 10
		local name = Kit.label({
			Name = "NurseName",
			Text = nurse.Icon .. " " .. nurse.Name,
			TextScaled = true,
			Font = Theme.DisplayFont,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(textLeft, 8),
			Size = UDim2.new(0.62, -textLeft - 6, 0, 30),
			Parent = row,
		})
		textLimit(name, 24)
		local sub = Kit.label({
			Name = "Sub",
			Text = "",
			TextScaled = true,
			TextColor3 = Theme.Colors.InkSoft,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(textLeft, 40),
			Size = UDim2.new(0.62, -textLeft - 6, 0, 26),
			Parent = row,
		})
		textLimit(sub, 20)
		local button = Kit.button({
			Name = "Act",
			Kind = "Cash",
			Text = "",
			TextScaled = true,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(0.38, -14, 0, Theme.Size.ButtonHeight),
			Parent = row,
		})
		padButton(button, 8, 12)
		local limits = Instance.new("UISizeConstraint")
		limits.MinSize = Vector2.new(112, Theme.Size.ButtonHeight)
		limits.MaxSize = Vector2.new(190, Theme.Size.ButtonHeight)
		limits.Parent = button
		return { Key = key, NurseId = nurseId, Frame = row, Name = name, Sub = sub, Button = button }
	end

	local function paint(button: TextButton, text: string, fill: Color3, active: boolean)
		if button.Text ~= text then
			button.Text = text
		end
		button.BackgroundColor3 = fill
		for _, child in button:GetChildren() do
			if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
				child.Transparency = if active then 0 else 0.3
			end
		end
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
					row.Sub.Text = icons(nurse)
					if slot.Personal == true then
						local clover = Kit.label({
							Name = "Lucky",
							Text = "🍀",
							TextScaled = true,
							BackgroundColor3 = Theme.Colors.Good,
							BackgroundTransparency = 0,
							Position = UDim2.fromOffset(2, 2),
							Size = UDim2.fromOffset(26, 26),
							ZIndex = 3,
							Parent = row.Frame,
						})
						Kit.corner(clover, 13)
						Kit.stroke(clover, Theme.Colors.Outline, 2)
					end
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
				local text = if busy then "⏳" else Pure.buttonText(state, slot)
				local fill = if state == "Ready"
					then Kit.lighten(Theme.Colors.Cash, 0.08)
					elseif state == "Bought" then Kit.lighten(Theme.Colors.Good, 0.08)
					elseif state == "Full" then Kit.lighten(Theme.Colors.Secondary, 0.08)
					else Theme.Colors.Disabled
				paint(row.Button, text, fill, state == "Ready" or state == "Bought" or state == "Full")
			end
		end
		if #hireRows == 0 then
			showEmpty(hirePage, if view then "🏢 Back soon!" elseif status ~= "" then status else "⏳")
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
			local sub = "⭐ Lv " .. math.floor(level)
			if copies > 1 then
				sub ..= "  ×" .. math.floor(copies)
			end
			if resting then
				sub ..= "  💤"
			end
			if state == "Listed" then
				sub ..= "  🏷️"
			end
			row.Sub.Text = sub
			local text = if busy
				then "⏳"
				elseif state == "Sell" then "Sell 💰" .. Pure.commas(sellBack[row.NurseId])
				elseif state == "Listed" then "🏷️ Listed"
				elseif state == "Stays" then "🏢 Stays"
				else "⏳"
			local fill = if state == "Sell" then Kit.lighten(Theme.Colors.Primary, 0.08) else Theme.Colors.Disabled
			paint(row.Button, text, fill, state == "Sell")
		end
		if #sellRows == 0 then
			showEmpty(sellPage, "👩‍⚕️ No nurses yet!")
		elseif emptyLabel.Parent == sellPage then
			showEmpty(sellPage, "")
		end
	end

	local function render()
		if not modal.isOpen() then
			return
		end
		hirePage.Visible = tab == "Hire"
		sellPage.Visible = tab == "Sell"
		paintTab(hireTab, tab == "Hire")
		paintTab(sellTab, tab == "Sell")
		note.Text = if tab == "Hire" then Pure.everyText(cfg.Agency.RestockSeconds) else "💰 The Agency buys nurses"
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

	local function fetchListed()
		local ok, _, payload = Hud.ask(ctx.Remotes.GetMarket)
		if ok and type(payload) == "table" then
			listed = Pure.listed(payload, player.UserId)
			render()
		end
	end

	local function selectTab(name: string)
		tab = if name == "Sell" then "Sell" else "Hire"
		render()
	end
	hireTab.Activated:Connect(function()
		selectTab("Hire")
	end)
	sellTab.Activated:Connect(function()
		selectTab("Sell")
		task.spawn(fetchListed)
	end)

	--------------------------------------------------------------------------------------------------------------
	-- Buying and selling (always ask first; the server checks everything again)
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
			ctx.toast("✅ You bought this one!")
		elseif state == "Gate" then
			ctx.toast(slot.Gate .. " first!")
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
			ctx.toast("Need 💰" .. Pure.commas(math.max(1, slot.Price - cash)) .. " more!")
			Hud.shake(button)
		else
			ask(nurse, Pure.confirmText("Hire", nurse.Icon, nurse.Name, 1, slot.Price), false, function()
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
			Hud.fly(modal.Panel, "💰", "Cash", 6)
			ctx.toast(if message ~= "" then message else "💰 Sold!")
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
			ctx.toast("🏷️ Unlist it first!")
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
		ask(
			nurse,
			Pure.confirmText("Sell", nurse.Icon, nurse.Name, level, price),
			Pure.needsHold(nurse.Rarity),
			function()
				sell(nurseId, price)
			end
		)
	end

	--------------------------------------------------------------------------------------------------------------
	-- Opening, news and the kiosk
	--------------------------------------------------------------------------------------------------------------
	local function open(name: string?)
		tab = if name == "Sell" then "Sell" else "Hire"
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
