--!strict
-- The 🏷️ Player Market panel (Progression v2 build plan §B3.2/§B9, §C T4; design §8). OWNER: T4.
--   init(ctx)   opens on ctx.fire("Open", "Market", tab?) (NursePanel's 🏷️ button; tab "Buy" | "Sell" | "Mine"), on
--               the kiosk's prompt (Workspace.PlayerMarket, a ProximityPrompt with the attribute Kiosk = "Market":
--               ProximityPromptService.PromptTriggered on this client, so streaming never matters) and on the bus
--               "List" (nurseId) (NursePanel's List button: the Sell tab with that nurse picked). Listens to the bus
--               "MarketNews" (view). Asks GetMarket, ListNurse(nurseId, price), Unlist(id), BuyListing(id, price)
--               through Hud.ask; plays "Sparkle" (listed), "Click" (unlisted) and Hud.shake's "Nope" over the bus
--               (a buy's "Bought" and a sale's "Sold" come with the server's NurseNews, Feel/Sounds).
--
-- Inside (a Hud.modal Panel, orange like the kiosk):
--   badges   "🏷️ Only this server" and "🚫 No swaps. No chat." (same server only; no free text anywhere)
--   🛒 Buy   every listing as a card: the nurse in its rarity frame, its level, the price and "by DisplayName",
--            and Buy (or why not: "Yours", "🏥 Lv 3", "🏢 R1", "You have one!", "Roster full", "Need 💰420").
--            Buy asks first: "Buy 🐶 Lv 7 for 💰420?" (Not now is the default), then BuyListing with exactly the
--            price shown, so a changed price changes nothing ("Price changed! Look again")
--   🏷️ Sell  your nurses that may be listed (not rebirth-only, not listed), then a price picker locked to the band
--            (Logic/Market.band at its level; the min and max shown), − / + steps and a slider, "You get 💰378"
--            (after the 10% fee) shown big, and List it! (asks first: "List 🐶 Lv 7 for 💰420?")
--   📋 Mine  your listings (n/3) with Unlist. A listed nurse keeps working until it's sold
-- No clocks, no countdowns, no Robux. Every motion is Kit's or Hud's (both honour Kit.reducedMotion()). The server
-- decides everything; this panel only shows and asks.

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local MarketLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Market"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local MarketPanel = {}

local ACCENT = Theme.Colors.Primary -- the kiosk's orange
local SLOT = Theme.Size.ButtonHeight
local GAP = Theme.Size.Gap
local BADGE_HEIGHT = 30
local PAGES_TOP = BADGE_HEIGHT + 8
local TAB_SIZE = Theme.Size.IconButton -- the tabs stand in a column on the left, so a short phone keeps its height
local TABS_WIDTH = TAB_SIZE + 6
local MIN_CARD = 128
local CARD_GAP = 10
-- Under each card's face: 4 + name 22 + seller 18 + price 26 + 4 + the button + 6, plus the face's 6 on top.
local CARD_FIXED = 6 + 4 + 22 + 18 + 26 + 4 + SLOT + 6
local STRIP_CARD = 96
local STRIP_HEIGHT = STRIP_CARD + 34 + 12
local ROW_HEIGHT = 76
local KIOSK_ATTRIBUTE = "Kiosk"
local KIOSK_MODEL = "PlayerMarket"

------------------------------------------------------------------------------------------------------------------
-- Pure helpers: no Roblox services or types, only MarketLogic (Shared/Logic/Market). tests/MarketServer.spec loads
-- the block between the PURE markers on its own, so keep it that way.
------------------------------------------------------------------------------------------------------------------
-- PURE-BEGIN
local Pure = {}

function Pure.commas(n: number): string
	local digits = tostring(math.floor(math.abs(n)))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return grouped
end

function Pure.money(n: number): string
	return "💰" .. Pure.commas(n)
end

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- The picker's step: about 20 taps across the band, a 1-2-5 multiple of `round` (Config.Market.Round, 10), so
-- every price it offers is a round number (Common Lv 1: 50..300 in 20s; Secret Lv 15: in 20,000s).
function Pure.step(min: number, max: number, round: number): number
	local unit = if finite(round) and round >= 1 then math.floor(round) else 1
	local raw = (max - min) / 20
	for _ = 1, 16 do
		for _, m in { 1, 2, 5 } do
			if unit * m >= raw then
				return unit * m
			end
		end
		unit *= 10
	end
	return unit
end

-- A price on the picker's grid (min, min + step, ... and max itself), inside [min, max].
function Pure.snap(price: number, min: number, max: number, step: number): number
	if max <= min then
		return min
	end
	local p = if finite(price) then math.clamp(price, min, max) else min
	if p >= max then
		return max
	end
	local k = math.floor((p - min) / math.max(step, 1) + 0.5)
	return math.clamp(min + k * step, min, max)
end

-- One tap of − (-1) or + (+1).
function Pure.nudge(price: number, direction: number, min: number, max: number, step: number): number
	local at = Pure.snap(price, min, max, step)
	return Pure.snap(at + (if direction < 0 then -step else step), min, max, step)
end

-- Where a price sits on the slider (0..1), and the price at a slider point.
function Pure.fraction(price: number, min: number, max: number): number
	if max <= min or not finite(price) then
		return 0
	end
	return math.clamp((price - min) / (max - min), 0, 1)
end

function Pure.fromFraction(f: number, min: number, max: number, step: number): number
	local t = if finite(f) then math.clamp(f, 0, 1) else 0
	return Pure.snap(min + t * (max - min), min, max, step)
end

-- Where the picker starts: the belt's base price at this level (a fair deal), on the grid.
function Pure.fair(cfg: any, rarity: string, level: number, min: number, max: number, step: number): number
	local market = if type(cfg) == "table" and type(cfg.Market) == "table" then cfg.Market else {}
	local belt = if type(cfg) == "table" and type(cfg.Belt) == "table" then cfg.Belt else {}
	local prices = if type(belt.Prices) == "table" then belt.Prices else {}
	local base = if finite(prices[rarity]) then prices[rarity] else min
	local levelStep = if finite(market.LevelStep) then market.LevelStep else 0.1
	local lv = if finite(level) then math.max(1, math.floor(level)) else 1
	return Pure.snap(base * (1 + levelStep * (lv - 1)), min, max, step)
end

-- What the seller gets: the price minus the fee (Logic/Market.fee).
function Pure.payout(price: number, cfg: any): number
	return price - MarketLogic.fee(price, cfg)
end

-- What a listing's card offers you: ("Buy", "Buy"), ("Mine", "Yours") or ("Blocked", why), from the Snapshot with
-- Logic/Market.canBuy (the server checks it all again).
function Pure.buyState(state: any, listing: any, userId: number, cfg: any, roster: any): (string, string)
	if listing.Seller == userId then
		return "Mine", "Yours"
	end
	local nurses = if type(state) == "table" and type(state.Nurses) == "table" then state.Nurses else {}
	local owns = type(nurses[listing.NurseId]) == "table"
	local ok, why = MarketLogic.canBuy(state, listing, owns, cfg, roster)
	if ok then
		return "Buy", "Buy"
	end
	if string.sub(why, 1, 11) == "Roster full" then
		return "Blocked", "Roster full"
	end
	return "Blocked", why
end

-- Your nurses that may be listed now: owned, known, not rebirth-only, not listed. Rarest first, then the highest
-- level, then by id. `rarityOrder` is Data/Rarities.Order (Common first).
function Pure.sellable(nurses: any, roster: any, listed: { [string]: boolean }, rarityOrder: { string }): { string }
	local rank: { [string]: number } = {}
	for index, rarity in rarityOrder do
		rank[rarity] = index
	end
	local ids: { string } = {}
	if type(nurses) == "table" then
		for nurseId, entry in nurses do
			local nurse = if type(nurseId) == "string" then rawget(roster, nurseId) else nil
			if type(entry) == "table" and type(nurse) == "table" and nurse.Source == nil and not listed[nurseId] then
				table.insert(ids, nurseId)
			end
		end
	end
	table.sort(ids, function(a, b)
		local ra, rb = rank[rawget(roster, a).Rarity] or 0, rank[rawget(roster, b).Rarity] or 0
		if ra ~= rb then
			return ra > rb
		end
		local la = if finite(nurses[a].Level) then nurses[a].Level else 1
		local lb = if finite(nurses[b].Level) then nurses[b].Level else 1
		if la ~= lb then
			return la > lb
		end
		return a < b
	end)
	return ids
end

-- The Buy tab's order: everyone else's listings, newest first, then your own.
function Pure.forSale(listings: { any }, userId: number): { any }
	local list = table.clone(listings)
	table.sort(list, function(a, b)
		local mineA, mineB = a.Seller == userId, b.Seller == userId
		if mineA ~= mineB then
			return mineB
		end
		return a.Id > b.Id
	end)
	return list
end

-- Your own listings, oldest first.
function Pure.mine(listings: { any }, userId: number): { any }
	local list = {}
	for _, listing in listings do
		if listing.Seller == userId then
			table.insert(list, listing)
		end
	end
	table.sort(list, function(a, b)
		return a.Id < b.Id
	end)
	return list
end

-- The confirms (6 words): "Buy 🐶 Lv 7 for 💰420?" · "List 🐶 Lv 7 for 💰420?"
function Pure.confirmBuy(icon: string, level: number, price: number): string
	return "Buy " .. icon .. " Lv " .. tostring(level) .. " for " .. Pure.money(price) .. "?"
end

function Pure.confirmList(icon: string, level: number, price: number): string
	return "List " .. icon .. " Lv " .. tostring(level) .. " for " .. Pure.money(price) .. "?"
end

-- The List button: (ok, text). Your cap first, then the server's (Config.Market).
function Pure.listButton(mine: number, total: number, cfg: any): (boolean, string)
	local market = if type(cfg) == "table" and type(cfg.Market) == "table" then cfg.Market else {}
	local perSeller = if finite(market.MaxPerSeller) then market.MaxPerSeller else 3
	local maxListings = if finite(market.MaxListings) then market.MaxListings else 30
	if mine >= perSeller then
		return false, tostring(perSeller) .. " listings max!"
	end
	if total >= maxListings then
		return false, "Market is full!"
	end
	return true, "🏷️ List it!"
end

-- A MarketView from the network, checked field by field (anything odd is dropped). nil when it isn't one.
function Pure.view(raw: any): any
	if type(raw) ~= "table" or type(raw.Listings) ~= "table" then
		return nil
	end
	local list = {}
	for _, listing in raw.Listings do
		if
			type(listing) == "table"
			and finite(listing.Id)
			and finite(listing.Seller)
			and type(listing.SellerName) == "string"
			and type(listing.NurseId) == "string"
			and type(listing.Rarity) == "string"
			and finite(listing.Level)
			and finite(listing.Price)
			and #list < 60
		then
			table.insert(list, {
				Id = listing.Id,
				Seller = listing.Seller,
				SellerName = listing.SellerName,
				NurseId = listing.NurseId,
				Rarity = listing.Rarity,
				Level = listing.Level,
				Price = listing.Price,
			})
		end
	end
	return {
		Listings = list,
		FeePercent = if finite(raw.FeePercent) then raw.FeePercent else 10,
		MaxPerSeller = if finite(raw.MaxPerSeller) then raw.MaxPerSeller else 3,
	}
end
-- PURE-END

MarketPanel.Pure = Pure

------------------------------------------------------------------------------------------------------------------
-- Small UI helpers
------------------------------------------------------------------------------------------------------------------

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

local function textLimit(label: TextLabel | TextButton, max: number)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = max
	limit.MinTextSize = 9
	limit.Parent = label
end

local function padButton(button: GuiObject, x: number, y: number)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, x)
	pad.PaddingRight = UDim.new(0, x)
	pad.PaddingTop = UDim.new(0, y)
	pad.PaddingBottom = UDim.new(0, y)
	pad.Parent = button
end

local function scroller(name: string, parent: Instance): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Theme.Colors.InkSoft
	scroll.Selectable = false
	scroll.Visible = false
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = scroll
	scroll.Parent = parent
	return scroll
end

-- A nurse cap in the rarity's colour, tipped on the portrait's head (as the Journal draws it).
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
	Kit.corner(cap, 6)
	Kit.stroke(cap, Theme.Colors.Outline, 2)
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

-- The nurse's face on its rarity's tint, with a cap.
local function face(parent: Instance, nurse: any, props: { [string]: any }): Frame
	local color = Kit.rarityColor(if nurse then nurse.Rarity else "Common")
	props.BackgroundColor3 = Kit.lighten(color, 0.45)
	props.Parent = parent
	local holder = frame(props)
	Kit.corner(holder, 12)
	Palette.candyGradient(holder)
	local portrait = Hud.portrait(if nurse then nurse.Look else nil, false)
	portrait.AnchorPoint = Vector2.new(0.5, 0.5)
	portrait.Position = UDim2.fromScale(0.5, 0.5)
	portrait.Size = UDim2.fromScale(0.95, 0.95)
	portrait.Parent = holder
	addCap(portrait, color)
	return holder
end

------------------------------------------------------------------------------------------------------------------
-- The panel
------------------------------------------------------------------------------------------------------------------

type BuyCard = {
	Frame: Frame,
	Title: TextLabel,
	Seller: TextLabel,
	Price: TextLabel,
	Action: TextButton,
	Listing: any,
	StopFrame: () -> (),
}

type SellCard = {
	Button: TextButton,
	Level: TextLabel,
	StopFrame: () -> (),
}

type MineRow = {
	Frame: Frame,
	Title: TextLabel,
	Info: TextLabel,
	Unlist: TextButton,
	Listing: any,
}

function MarketPanel.init(ctx: Types.Ctx)
	local data = ctx.Data :: any
	local cfg = ctx.Config
	local roster = data.Nurses
	local rarityOrder: { string } = data.Rarities.Order
	local userId = ctx.Player.UserId
	local round = if type(cfg.Market) == "table" and type(cfg.Market.Round) == "number" then cfg.Market.Round else 10

	local view: any = Pure.view({ Listings = {} })
	local tab = "Buy"
	local selected: string? = nil
	local price = 0
	local busy = false

	local function nurseOf(nurseId: string): any
		local nurse = rawget(roster, nurseId)
		return if type(nurse) == "table" then nurse else nil
	end

	local modal = Hud.modal(ctx, {
		Name = "Market",
		Title = "🏷️ Market",
		Accent = ACCENT,
		MaxSize = Vector2.new(720, 620),
	})
	local body = modal.Body

	--------------------------------------------------------------------------------------------------------------
	-- The tabs: a column of big icon buttons on the left
	--------------------------------------------------------------------------------------------------------------
	local tabColumn = frame({
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, TABS_WIDTH, 1, 0),
		Parent = body,
	})
	local tabList = Kit.list(tabColumn, Enum.FillDirection.Vertical, 8)
	tabList.VerticalAlignment = Enum.VerticalAlignment.Top
	local tabButtons: { [string]: TextButton } = {}
	for index, spec in { { "Buy", "🛒", "Buy" }, { "Sell", "🏷️", "Sell" }, { "Mine", "📋", "Mine" } } do
		local button = Kit.iconButton({
			Name = spec[1],
			Icon = spec[2],
			Caption = spec[3],
			Kind = "Card",
			Size = UDim2.fromOffset(TAB_SIZE, TAB_SIZE),
			LayoutOrder = index,
			Parent = tabColumn,
		})
		tabButtons[spec[1]] = button
	end

	local content = frame({
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(TABS_WIDTH + GAP, 0),
		Size = UDim2.new(1, -(TABS_WIDTH + GAP), 1, 0),
		Parent = body,
	})

	--------------------------------------------------------------------------------------------------------------
	-- The badges: same server only, no swaps, no chat
	--------------------------------------------------------------------------------------------------------------
	local badges = frame({
		Name = "Badges",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, BADGE_HEIGHT),
		Parent = content,
	})
	local badgeList = Kit.list(badges, Enum.FillDirection.Horizontal, 8)
	badgeList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	for index, text in { "🏷️ Only this server", "🚫 No swaps. No chat." } do
		local badge = Kit.label({
			Name = "Badge" .. index,
			Text = text,
			TextScaled = true,
			BackgroundColor3 = if index == 1 then Kit.lighten(ACCENT, 0.7) else Theme.Colors.Card,
			BackgroundTransparency = 0,
			Size = UDim2.new(0.5, -4, 1, 0),
			LayoutOrder = index,
			Parent = badges,
		})
		Kit.corner(badge, BADGE_HEIGHT // 2)
		Kit.stroke(badge, Theme.Colors.Outline, 2)
		padButton(badge, 10, 4)
		textLimit(badge, 18)
	end

	local pagesArea = frame({
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, PAGES_TOP),
		Size = UDim2.new(1, 0, 1, -PAGES_TOP),
		Parent = content,
	})

	--------------------------------------------------------------------------------------------------------------
	-- The confirm popup (Not now is the default)
	--------------------------------------------------------------------------------------------------------------
	local confirm = Hud.modal(ctx, {
		Name = "MarketConfirm",
		Title = "🏷️ Sure?",
		Accent = ACCENT,
		Layer = "Popup",
		MaxSize = Vector2.new(440, 300),
		Scale = Vector2.new(0.86, 0.8),
	})
	local question = Kit.label({
		Name = "Question",
		Text = "",
		TextScaled = true,
		Font = Theme.DisplayFont,
		Size = UDim2.fromScale(1, 0.42),
		Parent = confirm.Body,
	})
	textLimit(question, Theme.TextSize.Title)
	local note = Kit.label({
		Name = "Note",
		Text = "",
		TextScaled = true,
		TextColor3 = Theme.Colors.InkSoft,
		Position = UDim2.fromScale(0, 0.44),
		Size = UDim2.fromScale(1, 0.18),
		Parent = confirm.Body,
	})
	textLimit(note, Theme.TextSize.Body)
	local answers = frame({
		Name = "Answers",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, SLOT),
		Parent = confirm.Body,
	})
	Kit.list(answers, Enum.FillDirection.Horizontal, GAP)
	local notNow = Kit.button({
		Name = "NotNow",
		Kind = "Quiet",
		Text = "Not now",
		TextScaled = true,
		Size = UDim2.new(0.5, -GAP / 2, 1, 0),
		LayoutOrder = 1,
		Parent = answers,
	})
	padButton(notNow, 10, 12)
	local yes = Kit.button({
		Name = "Yes",
		Kind = "Good",
		Text = "✅ Yes!",
		TextScaled = true,
		Size = UDim2.new(0.5, -GAP / 2, 1, 0),
		LayoutOrder = 2,
		Parent = answers,
	})
	padButton(yes, 10, 12)
	confirm.Focus = notNow
	local onYes: (() -> ())? = nil
	notNow.Activated:Connect(function()
		onYes = nil
		confirm.close()
	end)
	yes.Activated:Connect(function()
		local fn = onYes
		onYes = nil
		confirm.close()
		if fn then
			fn()
		end
	end)
	local function ask(text: string, sub: string, fn: () -> ())
		question.Text = text
		note.Text = sub
		onYes = fn
		confirm.open()
	end

	--------------------------------------------------------------------------------------------------------------
	-- Server calls
	--------------------------------------------------------------------------------------------------------------
	local render: () -> ()

	local function refresh()
		task.spawn(function()
			local ok, _, payload = Hud.ask(ctx.Remotes.GetMarket)
			local fresh = if ok then Pure.view(payload) else nil
			if fresh then
				view = fresh
				if modal.isOpen() then
					render()
				end
			end
		end)
	end

	-- Asks the server; toasts its reply; a "no" shakes the button and fetches what's really there.
	-- `okSound` nil: the server's NurseNews plays the cue (a buy's "Bought", Feel/Sounds), so it never plays twice.
	local function call(remote: RemoteFunction, button: GuiObject?, okSound: string?, ...: any): boolean
		busy = true
		local ok, message = Hud.ask(remote, ...)
		busy = false
		if message ~= "" then
			ctx.toast(message)
		end
		if ok then
			if okSound then
				Hud.sound(okSound)
			end
			if button then
				Hud.pop(button)
			end
		else
			Hud.shake(button)
		end
		refresh()
		return ok
	end

	--------------------------------------------------------------------------------------------------------------
	-- 🛒 Buy
	--------------------------------------------------------------------------------------------------------------
	local buyPage = scroller("Buy", pagesArea)
	local buyList = Kit.list(buyPage, Enum.FillDirection.Vertical, GAP)
	buyList.VerticalAlignment = Enum.VerticalAlignment.Top
	local buyEmpty = Kit.label({
		Name = "Empty",
		Text = "🏷️ Nothing for sale yet",
		TextScaled = true,
		Font = Theme.DisplayFont,
		TextColor3 = Theme.Colors.InkSoft,
		Size = UDim2.new(1, -12, 0, 44),
		LayoutOrder = 1,
		Parent = buyPage,
	})
	textLimit(buyEmpty, Theme.TextSize.Title)
	local buyHint = Kit.button({
		Name = "SellHint",
		Kind = "Secondary",
		Text = "🏷️ Sell one!",
		TextScaled = true,
		Size = UDim2.fromOffset(220, SLOT),
		LayoutOrder = 2,
		Parent = buyPage,
	})
	padButton(buyHint, 12, 12)
	local grid = frame({
		Name = "Grid",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -12, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		Parent = buyPage,
	})
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP)
	gridLayout.CellSize = UDim2.fromOffset(MIN_CARD, MIN_CARD + CARD_FIXED)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	-- As many columns as fit, cards stretched to fill the row (2 on a phone, up to 4 on a big screen).
	local function fitGrid()
		local width = grid.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local columns = math.clamp(math.floor((width + CARD_GAP) / (MIN_CARD + CARD_GAP)), 2, 4)
		local cell = math.floor((width - CARD_GAP * (columns - 1)) / columns)
		-- The face shrinks on a short screen (a landscape phone) so a whole card still fits on the page.
		local roomy = pagesArea.AbsoluteSize.Y - CARD_FIXED - 20
		local faceHeight = math.clamp(math.min(math.floor(cell * 0.6), 100, roomy), 48, 100)
		gridLayout.CellSize = UDim2.fromOffset(cell, faceHeight + CARD_FIXED)
	end
	grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitGrid)
	pagesArea:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitGrid)
	fitGrid()

	local buyCards: { [number]: BuyCard } = {}

	local function buy(card: BuyCard)
		local listing = card.Listing
		local nurse = nurseOf(listing.NurseId)
		if busy or not nurse then
			return
		end
		ask(Pure.confirmBuy(nurse.Icon, listing.Level, listing.Price), "by " .. listing.SellerName, function()
			call(ctx.Remotes.BuyListing, card.Action, nil, listing.Id, listing.Price)
		end)
	end

	local function newBuyCard(listing: any): BuyCard
		local nurse = nurseOf(listing.NurseId)
		local card = frame({
			Name = "Listing_" .. tostring(listing.Id),
			BackgroundColor3 = Theme.Colors.Paper,
			Parent = grid,
		})
		Kit.corner(card, 16)
		local stop = Kit.rarityFrame(card, listing.Rarity)
		face(card, nurse, {
			Name = "Face",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.new(1, -12, 1, -CARD_FIXED),
		})
		local title = Kit.label({
			Name = "NurseName",
			Text = "",
			TextScaled = true,
			Font = Theme.DisplayFont,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(6 + SLOT + 4 + 26 + 18)),
			Size = UDim2.new(1, -10, 0, 22),
			Parent = card,
		})
		textLimit(title, 20)
		local seller = Kit.label({
			Name = "Seller",
			Text = "",
			TextScaled = true,
			TextColor3 = Theme.Colors.InkSoft,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(6 + SLOT + 4 + 26)),
			Size = UDim2.new(1, -10, 0, 18),
			Parent = card,
		})
		textLimit(seller, 16)
		local priceLabel = Kit.label({
			Name = "Price",
			Text = "",
			TextScaled = true,
			Outlined = true,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(6 + SLOT + 4)),
			Size = UDim2.new(1, -10, 0, 26),
			Parent = card,
		})
		priceLabel.TextColor3 = Theme.Colors.Cash
		textLimit(priceLabel, 24)
		local action = Kit.button({
			Name = "Buy",
			Kind = "Good",
			Text = "Buy",
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -12, 0, SLOT),
			Parent = card,
		})
		padButton(action, 8, 14)
		local entry: BuyCard = {
			Frame = card,
			Title = title,
			Seller = seller,
			Price = priceLabel,
			Action = action,
			Listing = listing,
			StopFrame = stop,
		}
		action.Activated:Connect(function()
			buy(entry)
		end)
		return entry
	end

	local function renderBuy()
		local list = Pure.forSale(view.Listings, userId)
		local seen: { [number]: boolean } = {}
		for order, listing in list do
			seen[listing.Id] = true
			local card = buyCards[listing.Id]
			if not card then
				card = newBuyCard(listing)
				buyCards[listing.Id] = card
			end
			card.Listing = listing
			card.Frame.LayoutOrder = order
			local nurse = nurseOf(listing.NurseId)
			card.Title.Text = (if nurse then nurse.Name else "???") .. " · Lv " .. tostring(listing.Level)
			card.Seller.Text = "by " .. listing.SellerName
			card.Price.Text = Pure.money(listing.Price)
			local kind, text = Pure.buyState(ctx.State, listing, userId, cfg, roster)
			card.Action.Text = text
			Kit.setEnabled(card.Action, kind == "Buy")
		end
		for id, card in buyCards do
			if not seen[id] then
				card.StopFrame()
				card.Frame:Destroy()
				buyCards[id] = nil
			end
		end
		local empty = #list == 0
		buyEmpty.Visible = empty
		buyHint.Visible = empty
		grid.Visible = not empty
	end

	--------------------------------------------------------------------------------------------------------------
	-- 🏷️ Sell
	--------------------------------------------------------------------------------------------------------------
	local sellPage = scroller("Sell", pagesArea)
	local sellList = Kit.list(sellPage, Enum.FillDirection.Vertical, GAP)
	sellList.VerticalAlignment = Enum.VerticalAlignment.Top
	local pickLabel = Kit.label({
		Name = "Pick",
		Text = "👇 Pick a nurse to sell",
		TextScaled = true,
		Font = Theme.DisplayFont,
		Size = UDim2.new(1, -12, 0, 30),
		LayoutOrder = 1,
		Parent = sellPage,
	})
	textLimit(pickLabel, Theme.TextSize.Body)
	local sellEmpty = Kit.label({
		Name = "Empty",
		Text = "No nurses to sell",
		TextScaled = true,
		Font = Theme.DisplayFont,
		TextColor3 = Theme.Colors.InkSoft,
		Size = UDim2.new(1, -12, 0, 44),
		LayoutOrder = 2,
		Visible = false,
		Parent = sellPage,
	})
	textLimit(sellEmpty, Theme.TextSize.Title)
	local strip = Instance.new("ScrollingFrame")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.Size = UDim2.new(1, -12, 0, STRIP_HEIGHT)
	strip.CanvasSize = UDim2.new()
	strip.AutomaticCanvasSize = Enum.AutomaticSize.X
	strip.ScrollingDirection = Enum.ScrollingDirection.X
	strip.ScrollBarThickness = 6
	strip.ScrollBarImageColor3 = Theme.Colors.InkSoft
	strip.Selectable = false
	strip.LayoutOrder = 3
	strip.Parent = sellPage
	local stripList = Kit.list(strip, Enum.FillDirection.Horizontal, 8)
	stripList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	stripList.VerticalAlignment = Enum.VerticalAlignment.Top
	local stripPad = Instance.new("UIPadding")
	stripPad.PaddingTop = UDim.new(0, 6)
	stripPad.PaddingLeft = UDim.new(0, 6)
	stripPad.PaddingRight = UDim.new(0, 6)
	stripPad.Parent = strip

	-- The price card
	local priceCard = frame({
		Name = "PriceCard",
		BackgroundColor3 = Theme.Colors.Paper,
		Size = UDim2.new(1, -12, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 4,
		Parent = sellPage,
	})
	Kit.corner(priceCard, 16)
	Kit.stroke(priceCard, Theme.Colors.Outline, Theme.Size.Stroke)
	Kit.pad(priceCard, 10)
	local priceList = Kit.list(priceCard, Enum.FillDirection.Vertical, 8)
	priceList.VerticalAlignment = Enum.VerticalAlignment.Top
	local pickedTitle = Kit.label({
		Name = "Picked",
		Text = "",
		TextScaled = true,
		Font = Theme.DisplayFont,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 1,
		Parent = priceCard,
	})
	textLimit(pickedTitle, Theme.TextSize.Body)
	local bandLabel = Kit.label({
		Name = "Band",
		Text = "",
		TextScaled = true,
		TextColor3 = Theme.Colors.InkSoft,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 2,
		Parent = priceCard,
	})
	textLimit(bandLabel, 20)
	local stepper = frame({
		Name = "Stepper",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, SLOT),
		LayoutOrder = 3,
		Parent = priceCard,
	})
	local minus = Kit.button({
		Name = "Minus",
		Kind = "Secondary",
		Text = "−",
		TextSize = Theme.TextSize.Title,
		Size = UDim2.fromOffset(SLOT + 8, SLOT),
		Parent = stepper,
	})
	local plus = Kit.button({
		Name = "Plus",
		Kind = "Secondary",
		Text = "+",
		TextSize = Theme.TextSize.Title,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(SLOT + 8, SLOT),
		Parent = stepper,
	})
	local priceText = Kit.label({
		Name = "Price",
		Text = "",
		TextScaled = true,
		Outlined = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -2 * (SLOT + 8) - 2 * GAP, 1, -4),
		Parent = stepper,
	})
	priceText.TextColor3 = Theme.Colors.Cash
	textLimit(priceText, Theme.TextSize.Big)

	-- The slider: a wide hit area (so a thumb finds it) around a thin track, its fill and a knob.
	local slider = Instance.new("TextButton")
	slider.Name = "Slider"
	slider.Text = ""
	slider.AutoButtonColor = false
	slider.Selectable = false
	slider.BackgroundTransparency = 1
	slider.Size = UDim2.new(1, 0, 0, 40)
	slider.LayoutOrder = 4
	slider.Parent = priceCard
	local track = frame({
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -36, 0, 14),
		BackgroundColor3 = Theme.Colors.Quiet,
		Parent = slider,
	})
	Kit.corner(track, 7)
	Kit.stroke(track, Theme.Colors.Outline, 2)
	local fill = frame({
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.Cash,
		Parent = track,
	})
	Kit.corner(fill, 7)
	local knob = frame({
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = Theme.Colors.Paper,
		ZIndex = 2,
		Parent = track,
	})
	Kit.corner(knob, 16)
	Kit.stroke(knob, Theme.Colors.Outline, 3)

	local getRow = frame({
		Name = "YouGet",
		BackgroundColor3 = Kit.lighten(Theme.Colors.Cash, 0.6),
		Size = UDim2.new(1, 0, 0, 48),
		LayoutOrder = 5,
		Parent = priceCard,
	})
	Kit.corner(getRow, 14)
	local getText = Kit.label({
		Name = "Text",
		Text = "",
		TextScaled = true,
		Font = Theme.DisplayFont,
		Size = UDim2.new(1, -20, 1, -8),
		Position = UDim2.fromOffset(10, 4),
		Parent = getRow,
	})
	textLimit(getText, Theme.TextSize.Title)
	local feeNote = Kit.label({
		Name = "Fee",
		Text = "",
		TextScaled = true,
		TextColor3 = Theme.Colors.InkSoft,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 6,
		Parent = priceCard,
	})
	textLimit(feeNote, 18)
	local listButton = Kit.button({
		Name = "List",
		Kind = "Good",
		Text = "🏷️ List it!",
		TextScaled = true,
		Size = UDim2.new(1, 0, 0, SLOT),
		LayoutOrder = 7,
		Parent = priceCard,
	})
	padButton(listButton, 12, 12)

	local sellCards: { [string]: SellCard } = {}
	local band = { Min = 0, Max = 0, Step = 1 }

	local function selectedEntry(): (any, any)
		local id = selected
		if not id then
			return nil, nil
		end
		local nurses = ctx.State.Nurses
		local entry = if type(nurses) == "table" then nurses[id] else nil
		return nurseOf(id), entry
	end

	local function showPrice()
		local nurse = selectedEntry()
		if not nurse then
			return
		end
		priceText.Text = Pure.money(price)
		local f = Pure.fraction(price, band.Min, band.Max)
		fill.Size = UDim2.fromScale(f, 1)
		knob.Position = UDim2.fromScale(f, 0.5)
		getText.Text = "You get " .. Pure.money(Pure.payout(price, cfg))
		Kit.setEnabled(minus, price > band.Min)
		Kit.setEnabled(plus, price < band.Max)
	end

	local function setPrice(value: number, bump: boolean)
		local before = price
		price = Pure.snap(value, band.Min, band.Max, band.Step)
		showPrice()
		if bump and price ~= before then
			Hud.pop(priceText, 1.08)
		end
	end

	-- Works out the band for the picked nurse at its level now (it can grow while you look) and keeps the price in it.
	local function syncBand(reset: boolean)
		local nurse, entry = selectedEntry()
		if not nurse or not entry then
			return
		end
		local level = if type(entry.Level) == "number" then entry.Level else 1
		-- Its copies too: never below what the Agency pays for them after the fee (the server's check). The picker
		-- starts at the fair price snapped into this band, so never below that either.
		local copies = if type(entry.Copies) == "number" then entry.Copies else 1
		local min, max = MarketLogic.band(cfg, nurse.Rarity, level, copies)
		local changed = min ~= band.Min or max ~= band.Max
		band.Min, band.Max = min, max
		band.Step = Pure.step(min, max, round)
		if reset then
			price = Pure.fair(cfg, nurse.Rarity, level, min, max, band.Step)
		elseif changed then
			price = Pure.snap(price, min, max, band.Step) -- it levelled up while you looked: still in its band
		end
		pickedTitle.Text = nurse.Icon .. " " .. nurse.Name .. " · Lv " .. tostring(level)
		bandLabel.Text = Pure.money(min) .. " – " .. Pure.money(max)
		feeNote.Text = tostring(view.FeePercent) .. "% goes to the Market"
		showPrice()
	end

	local function pick(nurseId: string)
		if selected == nurseId then
			return
		end
		selected = nurseId
		syncBand(true)
		render()
	end

	local function newSellCard(nurseId: string): SellCard
		local nurse = nurseOf(nurseId)
		local button = Instance.new("TextButton")
		button.Name = nurseId
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundColor3 = Theme.Colors.Paper
		button.BorderSizePixel = 0
		button.Size = UDim2.fromOffset(STRIP_CARD, STRIP_CARD + 30)
		button.Parent = strip
		Kit.corner(button, 14)
		local stop = Kit.rarityFrame(button, if nurse then nurse.Rarity else "Common")
		face(button, nurse, {
			Name = "Face",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 5),
			Size = UDim2.new(1, -10, 0, STRIP_CARD - 10),
		})
		local level = Kit.label({
			Name = "Level",
			Text = "",
			TextScaled = true,
			Font = Theme.DisplayFont,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.new(1, -10, 0, 26),
			Parent = button,
		})
		textLimit(level, 20)
		button.Activated:Connect(function()
			pick(nurseId)
		end)
		return { Button = button, Level = level, StopFrame = stop }
	end

	local function renderSell()
		local listed: { [string]: boolean } = {}
		local mineList = Pure.mine(view.Listings, userId)
		for _, listing in mineList do
			listed[listing.NurseId] = true
		end
		local ids = Pure.sellable(ctx.State.Nurses, roster, listed, rarityOrder)
		local seen: { [string]: boolean } = {}
		for order, nurseId in ids do
			seen[nurseId] = true
			local card = sellCards[nurseId]
			if not card then
				card = newSellCard(nurseId)
				sellCards[nurseId] = card
			end
			card.Button.LayoutOrder = order
			local entry = ctx.State.Nurses[nurseId]
			card.Level.Text = "Lv " .. tostring(if type(entry.Level) == "number" then entry.Level else 1)
			card.Button.BackgroundColor3 = if nurseId == selected
				then Kit.lighten(Theme.Colors.Good, 0.55)
				else Theme.Colors.Paper
		end
		for nurseId, card in sellCards do
			if not seen[nurseId] then
				card.StopFrame()
				card.Button:Destroy()
				sellCards[nurseId] = nil
			end
		end
		if selected and not seen[selected] then
			selected = nil
		end
		local hasSome = #ids > 0
		pickLabel.Visible = hasSome
		strip.Visible = hasSome
		sellEmpty.Visible = not hasSome
		priceCard.Visible = selected ~= nil
		if selected then
			syncBand(false)
			local ok, text = Pure.listButton(#mineList, #view.Listings, cfg)
			listButton.Text = text
			Kit.setEnabled(listButton, ok)
		end
	end

	minus.Activated:Connect(function()
		setPrice(Pure.nudge(price, -1, band.Min, band.Max, band.Step), true)
	end)
	plus.Activated:Connect(function()
		setPrice(Pure.nudge(price, 1, band.Min, band.Max, band.Step), true)
	end)

	local dragging = false
	local function slideTo(x: number)
		local left = track.AbsolutePosition.X
		local width = track.AbsoluteSize.X
		if width > 0 then
			setPrice(Pure.fromFraction((x - left) / width, band.Min, band.Max, band.Step), false)
		end
	end
	local function pointer(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	slider.InputBegan:Connect(function(input: InputObject)
		if pointer(input) and selected then
			dragging = true
			slideTo(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			slideTo(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if pointer(input) then
			dragging = false
		end
	end)

	listButton.Activated:Connect(function()
		local nurse, entry = selectedEntry()
		local nurseId = selected
		if busy or not nurse or not entry or not nurseId then
			return
		end
		local level = if type(entry.Level) == "number" then entry.Level else 1
		local asking = price
		ask(Pure.confirmList(nurse.Icon, level, asking), "You get " .. Pure.money(Pure.payout(asking, cfg)), function()
			if call(ctx.Remotes.ListNurse, listButton, "Sparkle", nurseId, asking) then
				selected = nil
				tab = "Mine"
				render()
			end
		end)
	end)

	--------------------------------------------------------------------------------------------------------------
	-- 📋 Mine
	--------------------------------------------------------------------------------------------------------------
	local minePage = scroller("Mine", pagesArea)
	local mineLayout = Kit.list(minePage, Enum.FillDirection.Vertical, GAP)
	mineLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	local mineCount = Kit.label({
		Name = "Count",
		Text = "",
		TextScaled = true,
		Font = Theme.DisplayFont,
		Size = UDim2.new(1, -12, 0, 30),
		LayoutOrder = 0,
		Parent = minePage,
	})
	textLimit(mineCount, Theme.TextSize.Body)
	local mineEmpty = Kit.label({
		Name = "Empty",
		Text = "Nothing listed yet",
		TextScaled = true,
		TextColor3 = Theme.Colors.InkSoft,
		Size = UDim2.new(1, -12, 0, 36),
		LayoutOrder = 1,
		Parent = minePage,
	})
	textLimit(mineEmpty, Theme.TextSize.Body)
	local mineNote = Kit.label({
		Name = "Note",
		Text = "💼 Listed nurses keep working",
		TextScaled = true,
		TextColor3 = Theme.Colors.InkSoft,
		Size = UDim2.new(1, -12, 0, 24),
		LayoutOrder = 100,
		Parent = minePage,
	})
	textLimit(mineNote, 18)
	local mineRows: { [number]: MineRow } = {}

	local function newMineRow(listing: any): MineRow
		local nurse = nurseOf(listing.NurseId)
		local row = frame({
			Name = "Mine_" .. tostring(listing.Id),
			BackgroundColor3 = Theme.Colors.Card,
			Size = UDim2.new(1, -12, 0, ROW_HEIGHT),
			Parent = minePage,
		})
		Kit.corner(row, 14)
		Kit.stroke(row, Theme.Colors.Outline, 2)
		face(row, nurse, {
			Name = "Face",
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(ROW_HEIGHT - 16, ROW_HEIGHT - 16),
		})
		local unlist = Kit.button({
			Name = "Unlist",
			Kind = "Quiet",
			Text = "Unlist",
			TextScaled = true,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(120, SLOT),
			Parent = row,
		})
		padButton(unlist, 10, 14)
		local textLeft = ROW_HEIGHT + 2
		local title = Kit.label({
			Name = "Title",
			Text = "",
			TextScaled = true,
			Font = Theme.DisplayFont,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(textLeft, 10),
			Size = UDim2.new(1, -(textLeft + 120 + 16), 0, 28),
			Parent = row,
		})
		textLimit(title, 22)
		local info = Kit.label({
			Name = "Info",
			Text = "",
			TextScaled = true,
			TextColor3 = Theme.Colors.InkSoft,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(textLeft, 40),
			Size = UDim2.new(1, -(textLeft + 120 + 16), 0, 24),
			Parent = row,
		})
		textLimit(info, 18)
		local entry: MineRow = { Frame = row, Title = title, Info = info, Unlist = unlist, Listing = listing }
		unlist.Activated:Connect(function()
			if not busy then
				call(ctx.Remotes.Unlist, unlist, "Click", entry.Listing.Id)
			end
		end)
		return entry
	end

	local function renderMine()
		local list = Pure.mine(view.Listings, userId)
		local seen: { [number]: boolean } = {}
		for order, listing in list do
			seen[listing.Id] = true
			local row = mineRows[listing.Id]
			if not row then
				row = newMineRow(listing)
				mineRows[listing.Id] = row
			end
			row.Listing = listing
			row.Frame.LayoutOrder = order + 1
			local nurse = nurseOf(listing.NurseId)
			row.Title.Text = (if nurse then nurse.Icon .. " " .. nurse.Name else "???")
				.. " · Lv "
				.. tostring(listing.Level)
			row.Info.Text = Pure.money(listing.Price) .. " · you get " .. Pure.money(Pure.payout(listing.Price, cfg))
		end
		for id, row in mineRows do
			if not seen[id] then
				row.Frame:Destroy()
				mineRows[id] = nil
			end
		end
		mineCount.Text = "📋 " .. tostring(#list) .. "/" .. tostring(view.MaxPerSeller) .. " listed"
		mineEmpty.Visible = #list == 0
		mineNote.Visible = #list > 0
	end

	--------------------------------------------------------------------------------------------------------------
	-- Tabs and rendering
	--------------------------------------------------------------------------------------------------------------
	local pages: { [string]: ScrollingFrame } = { Buy = buyPage, Sell = sellPage, Mine = minePage }

	render = function()
		-- The open tab in full candy with outlined text; the others a pale tint.
		for name, page in pages do
			local open = name == tab
			page.Visible = open
			local button = tabButtons[name]
			button.BackgroundColor3 = if open then Kit.lighten(ACCENT, 0.08) else Kit.lighten(ACCENT, 0.78)
			local caption = button:FindFirstChild("Caption")
			if caption and caption:IsA("TextLabel") then
				caption.TextColor3 = if open then Theme.Colors.OnColor else Theme.Colors.Ink
				Kit.outline(caption, 2).Enabled = open
			end
		end
		if tab == "Buy" then
			renderBuy()
		elseif tab == "Sell" then
			renderSell()
		else
			renderMine()
		end
		modal.Focus = tabButtons[tab]
	end

	for name, button in tabButtons do
		button.Activated:Connect(function()
			if tab ~= name then
				tab = name
				render()
			end
		end)
	end
	buyHint.Activated:Connect(function()
		tab = "Sell"
		render()
	end)

	local function openTo(which: string?, nurseId: string?)
		if which == "Sell" or which == "Mine" or which == "Buy" then
			tab = which
		end
		if nurseId then
			tab = "Sell"
			if selected ~= nurseId then
				selected = nurseId
				band.Min, band.Max = 0, 0
				syncBand(true)
			end
		end
		render()
		modal.open()
		refresh()
	end

	ctx.on("Open", function(name: any, which: any)
		if name == "Market" then
			openTo(if type(which) == "string" then which else nil)
		end
	end)

	-- NursePanel's List button: the Sell tab with that nurse picked (or why it can't be).
	ctx.on("List", function(nurseId: any)
		if type(nurseId) ~= "string" then
			return
		end
		local nurse = nurseOf(nurseId)
		local nurses = ctx.State.Nurses
		if not nurse or type(nurses) ~= "table" or type(nurses[nurseId]) ~= "table" then
			return
		end
		if nurse.Source ~= nil then
			ctx.toast("This one stays with you!")
			return
		end
		for _, listing in Pure.mine(view.Listings, userId) do
			if listing.NurseId == nurseId then
				openTo("Mine")
				return
			end
		end
		openTo("Sell", nurseId)
	end)

	ctx.on("MarketNews", function(raw: any)
		local fresh = Pure.view(raw)
		if fresh then
			view = fresh
			if modal.isOpen() then
				render()
			end
		end
	end)

	ctx.onState(function()
		if modal.isOpen() then
			render()
		end
	end)

	-- The kiosk: its prompt opens the Buy tab (the server builds Workspace.PlayerMarket and tags the prompt).
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if player ~= ctx.Player then
			return
		end
		if prompt:GetAttribute(KIOSK_ATTRIBUTE) == "Market" or prompt:FindFirstAncestor(KIOSK_MODEL) ~= nil then
			openTo("Buy")
		end
	end)

	render()
end

return MarketPanel
