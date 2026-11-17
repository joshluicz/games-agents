--!strict
-- BadgeBook (game/README.md "Badges"): the Badge Book, and the cheer for tier-ups and Doctor ranks.
--   init(ctx)   opens on ctx.fire("Open", "Badges") (the HUD's badge link, shown once the tutorial is done)
--   BadgeBook.Pure   the words each card shows (tests/Badges.spec loads the PURE block on its own)
--
-- The Book (UI/Modal's navy header, the title in words; the calm UI, docs/plan/2026-11-17-ui-direction.md §4 #10;
-- Joshua, memory-20261117-007), then
--   category tabs    THE tab column (Modal.tabs): one per Data/Badges category (🏥 Clinic, 🗺️ Wings, 🩹 Stations,
--                    💛 Friends), down the left like every panel
--   your boosts      Hud.boostLine at the top of the page (a Soft line): timed boosts with their play time left,
--                    then the permanent percents
--   badge cards      Kit.card cards with no line: per badge its Art on a tile tinted in its tier's colour (Bronze,
--                    Silver, Gold, Diamond, Ruby, Mythic; the Well before Bronze) with the tier's medal as its one
--                    State badge, the name (Normal) and what to do (Soft), a Kit.bar (navy; gold when maxed) with
--                    "n/next" beside it, then ONE Soft line for the next tier in words with one Unit ("Gold: +3%
--                    cash at night · 💰 400 + 8 stars"); a maxed badge says so in words. Values come from
--                    Logic/Badges.statValue on the Snapshot (Stats, Playtime, Story, Rooms, Decor), the tiers from
--                    Snapshot.Badges. The server decides; this only shows it.
-- The cheer (ctx.on "Cheer" (icon, text, colour), and every tier-up the Snapshot shows after the save loaded): one
-- banner in THE notice stack (the bus "Banner": UI/Toasts draws it under the Now card) with a fanfare, one at a time.
-- It never blocks play, waits while the first-session tutorial runs, and leaves by itself.
-- Phones: the cards scroll, the tab column scrolls, every button is >= 56 px tall, no text under 18 px.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local BadgesLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Badges"))
local TutorialLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Tutorial"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Modal = require(script.Parent.Modal)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local BadgeBook = {}

------------------------------------------------------------------------------------------------------------------
-- Pure: the card's words. Only UI/Icons (a pure library); tests/Badges.spec loads the block with the real Data.
------------------------------------------------------------------------------------------------------------------
-- PURE-BEGIN
local Pure = {}

Pure.TITLE = "Badges"
Pure.MANY_UP = " badges up!"

-- What each boost kind (Logic/Boosts.KINDS) is, in words.
Pure.KIND_WORDS = {
	Cash = "cash",
	Tips = "tips",
	Stars = "stars",
	MakeSpeed = "faster making",
	Patience = "patience",
} :: { [string]: string }

local function formatWhole(n: any): string
	local value = if type(n) == "number" and n == n and n ~= math.huge then math.max(0, math.floor(n)) else 0
	local digits = tostring(value)
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return grouped
end

-- "+3% cash", with the scope in words when the boost is only for some patients or one station ("+5% cash at
-- night", "+2% cash in Meadow", "+3% faster making at Pharmacy").
function Pure.boostWords(data: any, boost: any, percent: number): string
	local kind = if type(boost) == "table" then boost.Kind else nil
	local text = "+" .. percent .. "% " .. (Pure.KIND_WORDS[kind] or "boost")
	local scope = if type(boost) == "table" then boost.Scope else nil
	if type(scope) == "string" and type(data) == "table" then
		local wing = if type(data.Wings) == "table" then rawget(data.Wings, scope) else nil
		local station = if type(data.Stations) == "table" then rawget(data.Stations, scope) else nil
		if scope == "Night" then
			text ..= " at night"
		elseif type(wing) == "table" then
			text ..= " in " .. tostring(wing.Name)
		elseif type(station) == "table" then
			text ..= " at " .. tostring(station.Name)
		end
	end
	return text
end

-- The next tier in one Soft line: its name, the boost it brings and what it pays, with ONE Unit (the cash).
function Pure.nextLine(data: any, tier: any, boost: any, percent: number): string
	return tostring(tier.Name)
		.. ": "
		.. Pure.boostWords(data, boost, percent)
		.. " · "
		.. Icons.unit("Cash", formatWhole(tier.Cash))
		.. " + "
		.. formatWhole(tier.Stars)
		.. " stars"
end

-- A maxed badge, in words.
function Pure.maxLine(data: any, boost: any, percent: number): string
	return "Maxed · " .. Pure.boostWords(data, boost, percent)
end

-- A tier-up's banner words ("Gold Fast Hands!"); the banner's icon is the badge's own Art.
function Pure.cheerText(tier: any, def: any): string
	return tostring(tier.Name) .. " " .. tostring(def.Name) .. "!"
end
-- PURE-END

BadgeBook.Pure = Pure

local NAME = "Badges"
local CARD_HEIGHT = 136
local GAP = Theme.Space.PadCard
local TILE = 80
local BOOSTS_HEIGHT = 30
local BANNER_SECONDS = 3.2
local BANNER_GAP = 0.4 -- between two cheers in a row

local function hex(value: any, fallback: Color3): Color3
	if type(value) ~= "string" then
		return fallback
	end
	local ok, color = pcall(Color3.fromHex, value)
	return if ok then color else fallback
end

type Card = {
	Frame: Frame,
	Def: any,
	Tile: Frame,
	Title: TextLabel,
	SetBar: (fraction: number, atMax: boolean?) -> (),
	Count: TextLabel,
	Next: TextLabel,
}

function BadgeBook.init(ctx: Types.Ctx)
	local data = ctx.Data :: any
	local tiers = data.Badges.Tiers
	local defs = data.Badges.List
	local categories = data.Badges.Categories
	local initial = ctx.State

	local modal = Hud.modal(ctx, {
		Name = NAME,
		Title = Pure.TITLE,
		MaxSize = Vector2.new(620, 640),
	})

	local chosen = categories[1] and categories[1].Id or ""
	local cards: { Card } = {}
	local render: () -> ()
	local scroll: ScrollingFrame

	-- THE tab column (Modal.tabs): the categories down the left.
	local tabSpecs = {}
	for _, category in categories do
		table.insert(tabSpecs, { Id = category.Id, Icon = category.Icon, Caption = category.Name })
	end
	local tabView: Modal.Tabs -- (declared first: the select callback below reads it)
	tabView = Modal.tabs(modal, tabSpecs, function(id: string)
		chosen = id
		for _, card in cards do
			card.Frame.Visible = card.Def.Category == id
		end
		scroll.CanvasPosition = Vector2.zero
		modal.Focus = tabView.Buttons[id]
	end)
	local page = tabView.Content

	local boostLine = Kit.fact({
		Name = "Boosts",
		Text = "",
		Size = UDim2.new(1, 0, 0, BOOSTS_HEIGHT - Theme.Space.Tight),
		Parent = page,
	})

	scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, BOOSTS_HEIGHT)
	scroll.Size = UDim2.new(1, 0, 1, -BOOSTS_HEIGHT)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = Theme.Colors.Stroke
	scroll.Selectable = false
	scroll.Parent = page
	local list = Kit.list(scroll, Enum.FillDirection.Vertical, GAP)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, Theme.Space.Tight)
	pad.PaddingBottom = UDim.new(0, Theme.Space.Line)
	pad.PaddingLeft = UDim.new(0, Theme.Space.Tight)
	pad.PaddingRight = UDim.new(0, Theme.Space.PadCard)
	pad.Parent = scroll

	local function choose(id: string)
		tabView.select(id)
	end

	--------------------------------------------------------------------------------------------------------------
	-- The cards: the Art tile (tinted by its tier, the medal its State badge), the name, the goal, the bar and
	-- its count, and the next tier in one line
	--------------------------------------------------------------------------------------------------------------
	for index, def in defs do
		local frame = Kit.card({ Name = def.Id, LayoutOrder = index, Pad = false, Parent = scroll })
		frame.AutomaticSize = Enum.AutomaticSize.None
		frame.Size = UDim2.new(1, 0, 0, CARD_HEIGHT)
		local padCard = Theme.Space.PadCard

		local tile = Kit.artTile({
			Name = "Tile",
			Icon = def.Icon,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, padCard, 0.5, 0),
			Size = UDim2.fromOffset(TILE, TILE),
			Parent = frame,
		})

		local left = padCard * 2 + TILE
		local width = UDim2.new(1, -left - padCard, 0, 0)
		local title = Kit.name({
			Name = "Title",
			Text = def.Name,
			Position = UDim2.fromOffset(left, padCard - Theme.Space.Tight),
			Size = width + UDim2.fromOffset(0, Theme.TextSize.Body + Theme.Space.Tight),
			Parent = frame,
		})
		Kit.fact({
			Name = "Goal",
			Text = def.Goal,
			Position = UDim2.fromOffset(left, padCard + 26),
			Size = width + UDim2.fromOffset(0, Theme.TextSize.Caption + Theme.Space.Tight),
			Parent = frame,
		})
		local countWidth = 96
		local _, setBar = Kit.bar({
			Name = "Bar",
			Position = UDim2.fromOffset(left, padCard + 60),
			Size = UDim2.new(1, -left - padCard - countWidth - Theme.Space.Line, 0, Theme.Calm.Bar),
			Parent = frame,
		})
		local countLabel = Kit.fact({
			Name = "Count",
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -padCard, 0, padCard + 60 + Theme.Calm.Bar / 2),
			Size = UDim2.fromOffset(countWidth, Theme.TextSize.Caption + Theme.Space.Tight),
			Parent = frame,
		})
		local nextLabel = Kit.fact({
			Name = "Next",
			Text = "",
			Position = UDim2.fromOffset(left, padCard + 78),
			Size = width + UDim2.fromOffset(0, Theme.TextSize.Caption + Theme.Space.Tight),
			Parent = frame,
		})

		table.insert(cards, {
			Frame = frame,
			Def = def,
			Tile = tile,
			Title = title,
			SetBar = setBar,
			Count = countLabel,
			Next = nextLabel,
		})
	end

	render = function()
		local state = ctx.State
		boostLine.Text = Hud.boostLine(data, state)
		local saved = (state.Badges or {}) :: { [string]: number }
		for _, card in cards do
			local def = card.Def
			local tierIndex = math.clamp(math.floor(saved[def.Id] or 0), 0, #tiers)
			local tier = tiers[tierIndex]
			local value = BadgesLogic.statValue(state, def.Stat)
			card.Tile.BackgroundColor3 = if tier
				then Kit.lighten(hex(tier.Color, Theme.Colors.Well), 0.55)
				else Theme.Colors.Well
			Kit.setState(card.Tile, if tier then tier.Icon else nil) -- the medal: the card's one State badge
			card.Title.Text = def.Name .. (if tier then " · " .. tier.Name else "")
			local nextTier = tiers[tierIndex + 1]
			local nextAt = def.Thresholds[tierIndex + 1]
			if nextTier and nextAt then
				local from = if tierIndex > 0 then def.Thresholds[tierIndex] else 0
				card.SetBar(Kit.Juice.barFraction(value - from, math.max(1, nextAt - from)), false)
				card.Count.Text = Hud.format(value) .. "/" .. Hud.format(nextAt)
				card.Next.Text = Pure.nextLine(data, nextTier, def.Boost, BadgesLogic.boostAt(def, tierIndex + 1))
			else
				card.SetBar(1, true)
				card.Count.Text = Hud.format(value)
				card.Next.Text = Pure.maxLine(data, def.Boost, BadgesLogic.boostAt(def, tierIndex))
			end
		end
	end

	--------------------------------------------------------------------------------------------------------------
	-- The cheer: tier-ups and Doctor ranks, one at a time, through THE notice stack (the bus "Banner")
	--------------------------------------------------------------------------------------------------------------
	type Cheer = { Icon: string, Text: string, Color: Color3 }
	local queue: { Cheer } = {}
	local showing = false
	local cheers = 0
	local function showNext()
		if showing then
			return
		end
		showing = true
		task.spawn(function()
			while #queue > 0 do
				while TutorialLogic.active(ctx.State.Tutorial) do
					task.wait(1)
				end
				local cheer = table.remove(queue, 1) :: Cheer
				cheers += 1
				local banner: Types.BannerSpec = {
					Id = "Cheer" .. cheers,
					Icon = cheer.Icon,
					Text = cheer.Text,
					Color = cheer.Color,
					Seconds = BANNER_SECONDS,
				}
				ctx.fire("Banner", banner)
				Hud.sound("Fanfare")
				task.wait(BANNER_SECONDS + BANNER_GAP)
			end
			showing = false
		end)
	end
	local function cheer(icon: any, text: any, color: any)
		if type(icon) ~= "string" or type(text) ~= "string" then
			return
		end
		table.insert(queue, {
			Icon = icon,
			Text = text,
			Color = if typeof(color) == "Color3" then color else Theme.Colors.Cash,
		})
		showNext()
	end
	ctx.on("Cheer", cheer)

	-- Tier-ups the Snapshot shows (never for the save loading in).
	local known: { [string]: number }? = nil
	ctx.onState(function(state: Types.Snapshot)
		if state == initial or type(state.Badges) ~= "table" then
			return
		end
		local now = state.Badges
		if known then
			local ups = {}
			for _, def in defs do
				local before = known[def.Id] or 0
				local after = now[def.Id] or 0
				local tier = tiers[after]
				if after > before and tier then
					table.insert(ups, { Def = def, Tier = tier })
				end
			end
			if #ups > 2 then
				-- one banner, not a long queue
				cheer(Icons.Door.Badges, #ups .. Pure.MANY_UP, Theme.Colors.Cash)
			else
				for _, up in ups do
					cheer(up.Def.Icon, Pure.cheerText(up.Tier, up.Def), hex(up.Tier.Color, Theme.Colors.Cash))
				end
			end
		end
		known = table.clone(now)
		if modal.isOpen() then
			render()
		end
	end)
	ctx.Player:GetAttributeChangedSignal("PlayTotal"):Connect(function()
		if modal.isOpen() then
			boostLine.Text = Hud.boostLine(data, ctx.State)
		end
	end)

	ctx.on("Open", function(name: any)
		if name == NAME then
			render()
			choose(chosen)
			modal.open()
		end
	end)
	render()
	choose(chosen)
end

return BadgeBook
