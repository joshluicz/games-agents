--!strict
-- The Player Market panel (Progression v2 build plan §B3.2/§B9, §C T4; design §8). OWNER: T4 (the calm UI: T3).
--   init(ctx)   opens on ctx.fire("Open", "Market", tab?) (NursePanel's Market link; tab "Buy" | "Sell" | "Mine"), on
--               the kiosk's prompt (Workspace.PlayerMarket, a ProximityPrompt with the attribute Kiosk = "Market":
--               ProximityPromptService.PromptTriggered on this client, so streaming never matters) and on the bus
--               "List" (nurseId) (NursePanel's List: the Sell tab with that nurse picked). Listens to the bus
--               "MarketNews" (view). Asks GetMarket, ListNurse(nurseId, price), Unlist(id), BuyListing(id, price)
--               through Hud.ask; plays "Sparkle" (listed), "Click" (unlisted) and Hud.shake's "Nope" over the bus
--               (a buy's "Bought" and a sale's "Sold" come with the server's NurseNews, Feel/Sounds).
--
-- Inside (a Hud.modal Panel on the one template: the navy header "Market", Modal.tabs down the left; the calm UI,
-- docs/plan/2026-11-17-ui-direction.md: cards without lines, one button per card, chrome emoji from UI/Icons):
--   the rules  one Soft line over the pages: "This server only · No swaps · No chat" (no free text anywhere)
--   Buy   every listing as a card: the nurse in its rarity frame, "Name · Lv 7", "by DisplayName" (Soft), the price
--         ("💰 420") and Buy (Primary; or why not: "Yours", "🏥 Lv 3", "🏢 R1", "You have one!", "Roster full",
--         "Need 💰420"). Buy asks first through THE confirm (Hud.confirm, Pure.buyConfirm: title "Buy?", the line
--         "Buy 🐶 Lv 7 for 💰420?" and who sells it, Yes "Buy"; Not now is the default), then BuyListing with exactly
--         the price shown, so a changed price changes nothing ("Price changed! Look again")
--   Sell  your nurses that may be listed (not rebirth-only, not listed), then a price picker locked to the band
--         (Logic/Market.band at its level; the min and max shown), − / + steps and a slider, "You get 💰 378" (after
--         the 10% fee) and List (Primary; THE confirm first, Pure.listConfirm: "List 🐶 Lv 7 for 💰420?")
--   Mine  your listings ("1/3 listed") with Unlist. A listed nurse keeps working until it's sold
-- No clocks, no countdowns, no Robux. Every motion is Kit's or Hud's (both honour Kit.reducedMotion()). The server
-- decides everything; this panel only shows and asks. The pure block's money, confirm and List texts keep the 💰 and
-- 🏷️ the server-side specs pin (tests/MarketServer.spec, tests/ProgressionPanels.spec).

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local MarketLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Market"))
local Hud = require(script.Parent.Hud)
local Icons = require(script.Parent.Icons)
local Kit = require(script.Parent.Kit)
local Modal = require(script.Parent.Modal)
local Theme = require(script.Parent.Theme)

local MarketPanel = {}

local SLOT = Theme.Size.ButtonHeight
local GAP = Theme.Space.Gap
local RULES_HEIGHT = Theme.TextSize.Caption + Theme.Space.Tight
local PAGES_TOP = RULES_HEIGHT + GAP
local MIN_CARD = 128
local CARD_GAP = Theme.Space.PadCard
-- Under each card's face: 4 + name 40 + seller 22 + price 28 + 4 + the button + 6, plus the face's 6 on top.
local NAME_HEIGHT = 40 -- two lines: "Cuddle Cub · Lv 15" at the 18 px floor
local SELLER_HEIGHT = 22
local PRICE_HEIGHT = 28
local CARD_FIXED = 6 + 4 + NAME_HEIGHT + SELLER_HEIGHT + PRICE_HEIGHT + 4 + SLOT + 6
local STRIP_CARD = 96
local STRIP_HEIGHT = STRIP_CARD + 34 + 12
local ROW_HEIGHT = 76
-- THE tab pattern: a left column of square tabs (Modal.tabs), so a short phone keeps its height.
local TABS: { Modal.TabSpec } = {
	{ Id = "Buy", Icon = Icons.Door.Shop, Caption = "Buy" },
	{ Id = "Sell", Icon = Icons.Door.Market, Caption = "Sell" },
	{ Id = "Mine", Icon = "📋", Caption = "Mine" },
}
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
	return "💰" .. Pure.commas(n) -- uirules: allow TypedEmoji (the confirms' wording, pinned by tests/MarketServer.spec)
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

export type ConfirmSpec = { Title: string, Line: string, Yes: string, Kind: string, Hold: number }

-- THE confirm (Hud.confirm) before a buy (calm wording: the verb as the title, the verb alone on Yes): the question
-- and who sells it. Buy is the Primary; no hold.
function Pure.buyConfirm(icon: string, level: number, price: number, sellerName: any): ConfirmSpec
	local line = Pure.confirmBuy(icon, level, price)
	if type(sellerName) == "string" and sellerName ~= "" then
		line ..= "\nby " .. sellerName
	end
	return { Title = "Buy?", Line = line, Yes = "Buy", Kind = "Primary", Hold = 0 }
end

-- THE confirm before a listing: the question and what you get after the fee. List is the Primary; no hold.
function Pure.listConfirm(icon: string, level: number, price: number, payout: number): ConfirmSpec
	return {
		Title = "List?",
		Line = Pure.confirmList(icon, level, price) .. "\nYou get " .. Pure.money(payout),
		Yes = "List",
		Kind = "Primary",
		Hold = 0,
	}
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
	return true, "🏷️ List it!" -- uirules: allow TypedEmoji (pinned by tests/MarketServer.spec; the button says "List")
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
	pad.PaddingTop = UDim.new(0, Theme.Space.Tight)
	pad.PaddingBottom = UDim.new(0, Theme.Space.PadCard)
	pad.PaddingLeft = UDim.new(0, Theme.Space.Tight)
	pad.PaddingRight = UDim.new(0, Theme.Space.Line)
	pad.Parent = scroll
	scroll.Parent = parent
	return scroll
end

local function rounded(gui: GuiObject): UICorner
	local corner = Kit.corner(gui)
	corner.CornerRadius = Theme.Radius.Round
	return corner
end

-- A nurse cap in the rarity's colour, tipped on the portrait's head (as the Journal draws it). Its mark is a white
-- heart, never a cross (look build plan, Global constraints: no cross emblem on anything).
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
	Kit.corner(cap, Theme.Radius.Small)
	local mark = Kit.label({
		Name = "Mark",
		Text = "♥",
		TextScaled = true,
		Outlined = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 1),
		ZIndex = 7,
		Parent = cap,
	})
	mark.TextColor3 = Theme.Colors.OnColor
	cap.Parent = portrait
end

-- The nurse's face: the image well (the template's tile) in its rarity frame, with a cap. Returns the frame's stop.
local function face(parent: Instance, nurse: any, props: { [string]: any }): (Frame, () -> ())
	local rarity = if nurse then nurse.Rarity else "Common"
	props.BackgroundColor3 = Theme.Colors.Well
	props.Parent = parent
	local holder = frame(props)
	Kit.corner(holder, Theme.Radius.Medium)
	local stop = Kit.rarityFrame(holder, rarity)
	local portrait = Hud.portrait(if nurse then nurse.Look else nil, false)
	portrait.AnchorPoint = Vector2.new(0.5, 0.5)
	portrait.Position = UDim2.fromScale(0.5, 0.5)
	portrait.Size = UDim2.fromScale(0.95, 0.95)
	portrait.Parent = holder
	addCap(portrait, Kit.rarityColor(rarity))
	return holder, stop
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
	Face: Frame,
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
		Title = "Market",
		MaxSize = Vector2.new(720, 620),
	})
	local render: () -> ()

	--------------------------------------------------------------------------------------------------------------
	-- The tabs: THE tab pattern (Modal.tabs: a column of square tabs on the left, painted by Kit.tab)
	--------------------------------------------------------------------------------------------------------------
	local tabs = Modal.tabs(modal, TABS, function(id: string)
		tab = id
		render()
	end)
	local content = tabs.Content
	local function tabButton(id: string): GuiObject?
		local found = tabs.Column:FindFirstChild("Tab_" .. id, true)
		return if found and found:IsA("GuiObject") then found else nil
	end
	-- Switches the tab (and paints the column): Modal.tabs' select calls the callback above.
	local function setTab(name: string)
		tabs.select(name)
	end

	--------------------------------------------------------------------------------------------------------------
	-- The rules, in one Soft line: same server only, no swaps, no chat (no badges, no pills: R3)
	--------------------------------------------------------------------------------------------------------------
	Kit.fact({
		Name = "Rules",
		Text = "This server only · No swaps · No chat",
		Size = UDim2.new(1, 0, 0, RULES_HEIGHT),
		Parent = content,
	})

	local pagesArea = frame({
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, PAGES_TOP),
		Size = UDim2.new(1, 0, 1, -PAGES_TOP),
		Parent = content,
	})

	--------------------------------------------------------------------------------------------------------------
	-- Server calls
	--------------------------------------------------------------------------------------------------------------
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
	local buyEmpty = Kit.fact({
		Name = "Empty",
		Text = "Nothing for sale yet",
		LayoutOrder = 1,
		Parent = buyPage,
	})
	local buyHint = Kit.button({
		Name = "SellHint",
		Kind = "Secondary",
		Text = "Sell one",
		TextScaled = true,
		Size = UDim2.fromOffset(220, SLOT),
		LayoutOrder = 2,
		Parent = buyPage,
	})
	Kit.textLimit(buyHint, Theme.TextSize.Button)
	local grid = frame({
		Name = "Grid",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -Theme.Space.PadCard, 0, 0),
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
		Hud.confirm(ctx, Pure.buyConfirm(nurse.Icon, listing.Level, listing.Price, listing.SellerName), function()
			call(ctx.Remotes.BuyListing, card.Action, nil, listing.Id, listing.Price)
		end)
	end

	local function newBuyCard(listing: any): BuyCard
		local nurse = nurseOf(listing.NurseId)
		local card = Kit.card({
			Name = "Listing_" .. tostring(listing.Id),
			Pad = false,
			AutomaticSize = Enum.AutomaticSize.None,
			Parent = grid,
		})
		local _, stop = face(card, nurse, {
			Name = "Face",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.new(1, -12, 1, -CARD_FIXED),
		})
		-- The name (Normal voice, two lines at most), who sells it and the price (Soft and Normal): one Loud thing on
		-- the card, its Buy button.
		local title = Kit.label({
			Name = "NurseName",
			Text = "",
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(6 + SLOT + 4 + PRICE_HEIGHT + SELLER_HEIGHT)),
			Size = UDim2.new(1, -10, 0, NAME_HEIGHT),
			Parent = card,
		})
		Kit.voice(title, "Normal")
		local seller = Kit.fact({
			Name = "Seller",
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(6 + SLOT + 4 + PRICE_HEIGHT)),
			Size = UDim2.new(1, -10, 0, SELLER_HEIGHT),
			Parent = card,
		})
		local priceLabel = Kit.name({
			Name = "Price",
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(6 + SLOT + 4)),
			Size = UDim2.new(1, -10, 0, PRICE_HEIGHT),
			Parent = card,
		})
		local action = Kit.button({
			Name = "Buy",
			Kind = "Primary",
			Text = "Buy",
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -12, 0, SLOT),
			Parent = card,
		})
		Kit.textLimit(action, Theme.TextSize.Button)
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
			card.Price.Text = Icons.unit("Cash", Pure.commas(listing.Price))
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
	local pickLabel = Kit.fact({
		Name = "Pick",
		Text = "Pick a nurse to sell",
		LayoutOrder = 1,
		Parent = sellPage,
	})
	local sellEmpty = Kit.fact({
		Name = "Empty",
		Text = "No nurses to sell",
		LayoutOrder = 2,
		Visible = false,
		Parent = sellPage,
	})
	local strip = Instance.new("ScrollingFrame")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.Size = UDim2.new(1, -Theme.Space.PadCard, 0, STRIP_HEIGHT)
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
	stripPad.PaddingTop = UDim.new(0, Theme.Space.Tight)
	stripPad.PaddingLeft = UDim.new(0, Theme.Space.Tight)
	stripPad.PaddingRight = UDim.new(0, Theme.Space.Tight)
	stripPad.Parent = strip

	-- The price card
	local priceCard = Kit.card({
		Name = "PriceCard",
		Size = UDim2.new(1, -Theme.Space.PadCard, 0, 0),
		LayoutOrder = 4,
		Parent = sellPage,
	})
	local priceList = Kit.list(priceCard, Enum.FillDirection.Vertical, GAP)
	priceList.VerticalAlignment = Enum.VerticalAlignment.Top
	local pickedTitle = Kit.name({
		Name = "Picked",
		Text = "",
		LayoutOrder = 1,
		Parent = priceCard,
	})
	local bandLabel = Kit.fact({
		Name = "Band",
		Text = "",
		LayoutOrder = 2,
		Parent = priceCard,
	})
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
		Font = Theme.DisplayFont,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -2 * (SLOT + 8) - 2 * GAP, 1, -4),
		Parent = stepper,
	})
	Kit.textLimit(priceText, Theme.TextSize.Number)

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
		BackgroundColor3 = Theme.Colors.Track,
		Parent = slider,
	})
	rounded(track)
	local fill = frame({
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.Cash,
		Parent = track,
	})
	rounded(fill)
	local knob = frame({
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = Theme.Colors.Header, -- the knob in navy: it stands out on the track without a line
		ZIndex = 2,
		Parent = track,
	})
	rounded(knob)

	-- What you get, said plainly (no plate inside the card: R3).
	local getRow = frame({
		Name = "YouGet",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = 5,
		Parent = priceCard,
	})
	local getText = Kit.name({
		Name = "Text",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -Theme.Space.Section, 0, Theme.TextSize.Body + Theme.Space.Tight),
		Parent = getRow,
	})
	local feeNote = Kit.fact({
		Name = "Fee",
		Text = "",
		LayoutOrder = 6,
		Parent = priceCard,
	})
	local listButton = Kit.button({
		Name = "List",
		Kind = "Primary",
		Text = "List",
		TextScaled = true,
		Size = UDim2.new(1, 0, 0, SLOT),
		LayoutOrder = 7,
		Parent = priceCard,
	})
	Kit.textLimit(listButton, Theme.TextSize.Button)

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
		priceText.Text = Icons.unit("Cash", Pure.commas(price))
		local f = Pure.fraction(price, band.Min, band.Max)
		fill.Size = UDim2.fromScale(f, 1)
		knob.Position = UDim2.fromScale(f, 0.5)
		getText.Text = "You get " .. Icons.unit("Cash", Pure.commas(Pure.payout(price, cfg)))
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
		pickedTitle.Text = nurse.Name .. " · Lv " .. tostring(level)
		bandLabel.Text = "From " .. Icons.unit("Cash", Pure.commas(min)) .. " to " .. Pure.commas(max)
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
		button.BackgroundColor3 = Theme.Colors.Card
		button.BorderSizePixel = 0
		button.Size = UDim2.fromOffset(STRIP_CARD, STRIP_CARD + 30)
		button.Parent = strip
		Kit.corner(button, Theme.Radius.Medium)
		local holder, stop = face(button, nurse, {
			Name = "Face",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 5),
			Size = UDim2.new(1, -10, 0, STRIP_CARD - 10),
		})
		local level = Kit.name({
			Name = "Level",
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.new(1, -10, 0, 26),
			Parent = button,
		})
		button.Activated:Connect(function()
			pick(nurseId)
		end)
		return { Button = button, Face = holder, Level = level, StopFrame = stop }
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
			-- The picked nurse: the selected tab's navy fill and the ✅ State badge on its face (no outline: R2).
			local picked = nurseId == selected
			card.Button.BackgroundColor3 = if picked then Theme.Colors.Header else Theme.Colors.Card
			card.Level.TextColor3 = if picked then Theme.Colors.OnColor else Theme.Colors.Ink
			Kit.setState(card.Face, if picked then Icons.State.Done else nil)
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
			listButton.Text = if ok then "List" else text
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
		Hud.confirm(ctx, Pure.listConfirm(nurse.Icon, level, asking, Pure.payout(asking, cfg)), function()
			if call(ctx.Remotes.ListNurse, listButton, "Sparkle", nurseId, asking) then
				selected = nil
				setTab("Mine")
			end
		end)
	end)

	--------------------------------------------------------------------------------------------------------------
	-- 📋 Mine
	--------------------------------------------------------------------------------------------------------------
	local minePage = scroller("Mine", pagesArea)
	local mineLayout = Kit.list(minePage, Enum.FillDirection.Vertical, GAP)
	mineLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	local mineCount = Kit.fact({
		Name = "Count",
		Text = "",
		LayoutOrder = 0,
		Parent = minePage,
	})
	local mineEmpty = Kit.fact({
		Name = "Empty",
		Text = "Nothing listed yet",
		LayoutOrder = 1,
		Parent = minePage,
	})
	local mineNote = Kit.fact({
		Name = "Note",
		Text = "Listed nurses keep working",
		LayoutOrder = 100,
		Parent = minePage,
	})
	local mineRows: { [number]: MineRow } = {}

	local function newMineRow(listing: any): MineRow
		local nurse = nurseOf(listing.NurseId)
		local row = Kit.card({
			Name = "Mine_" .. tostring(listing.Id),
			Pad = false,
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.new(1, -Theme.Space.PadCard, 0, ROW_HEIGHT),
			Parent = minePage,
		})
		face(row, nurse, {
			Name = "Face",
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(ROW_HEIGHT - 16, ROW_HEIGHT - 16),
		})
		local unlist = Kit.button({
			Name = "Unlist",
			Kind = "Secondary",
			Text = "Unlist",
			TextScaled = true,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(120, SLOT),
			Parent = row,
		})
		Kit.textLimit(unlist, Theme.TextSize.Button)
		local textLeft = ROW_HEIGHT + 2
		local title = Kit.name({
			Name = "Title",
			Text = "",
			Position = UDim2.fromOffset(textLeft, 12),
			Size = UDim2.new(1, -(textLeft + 120 + 16), 0, Theme.TextSize.Body + Theme.Space.Tight),
			Parent = row,
		})
		local info = Kit.fact({
			Name = "Info",
			Text = "",
			Position = UDim2.fromOffset(textLeft, 42),
			Size = UDim2.new(1, -(textLeft + 120 + 16), 0, Theme.TextSize.Caption + Theme.Space.Tight),
			Parent = row,
		})
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
			row.Title.Text = (if nurse then nurse.Name else "???") .. " · Lv " .. tostring(listing.Level)
			row.Info.Text = "You get "
				.. Icons.unit("Cash", Pure.commas(Pure.payout(listing.Price, cfg)))
				.. " of "
				.. Pure.commas(listing.Price)
		end
		for id, row in mineRows do
			if not seen[id] then
				row.Frame:Destroy()
				mineRows[id] = nil
			end
		end
		mineCount.Text = tostring(#list) .. "/" .. tostring(view.MaxPerSeller) .. " listed"
		mineEmpty.Visible = #list == 0
		mineNote.Visible = #list > 0
	end

	--------------------------------------------------------------------------------------------------------------
	-- Tabs and rendering
	--------------------------------------------------------------------------------------------------------------
	local pages: { [string]: ScrollingFrame } = { Buy = buyPage, Sell = sellPage, Mine = minePage }

	render = function()
		-- Modal.tabs paints the column (Kit.tab); this shows the open tab's page.
		for name, page in pages do
			page.Visible = name == tab
		end
		if tab == "Buy" then
			renderBuy()
		elseif tab == "Sell" then
			renderSell()
		else
			renderMine()
		end
		modal.Focus = tabButton(tab)
	end

	buyHint.Activated:Connect(function()
		setTab("Sell")
	end)

	local function openTo(which: string?, nurseId: string?)
		local goTo = tab
		if which == "Sell" or which == "Mine" or which == "Buy" then
			goTo = which
		end
		if nurseId then
			goTo = "Sell"
			if selected ~= nurseId then
				selected = nurseId
				band.Min, band.Max = 0, 0
				syncBand(true)
			end
		end
		setTab(goTo) -- paints the column and renders the page
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
