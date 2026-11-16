--!strict
-- BadgeBook (game/README.md "Badges"): the 🏅 Badge Book, and the cheer for tier-ups and Doctor ranks.
--   init(ctx)   opens on ctx.fire("Open", "Badges") (the HUD's 🏅 rail button, shown once the tutorial is done)
--
-- The Book (the look overhaul's template, look build plan §B8): UI/Modal's navy header, then
--   category tabs    THE tab column (Modal.tabs): one per Data/Badges category (🏥 Clinic, 🗺️ Wings, 🧪 Stations,
--                    💛 Friends), down the left like every panel (it was a row)
--   your boosts      Hud.boostLine at the top of the page: timed boosts with their play time left, then the
--                    permanent percents
--   badge cards      tinted cards: per badge its icon on a tile framed in its tier's colour (Bronze, Silver, Gold,
--                    Diamond, Ruby, Mythic; grey before Bronze; the Bold stroke) with the tier's medal, the name and
--                    what to do, a bar and "n/next" to the next tier, then that tier's boost and rewards ("🥇 Gold →
--                    +3% 💰 · 💰400 ⭐8"); a maxed badge says so. Values come from Logic/Badges.statValue on the
--                    Snapshot (Stats, Playtime, Story, Rooms, Decor), the tiers from Snapshot.Badges. The server
--                    decides; this only shows it.
-- The cheer (ctx.on "Cheer" (icon, text, colour), and every tier-up the Snapshot shows after the save loaded): one
-- banner in THE notice stack (the bus "Banner": UI/Toasts draws it under the Now card) with a fanfare, one at a time.
-- It never blocks play, waits while the first-session tutorial runs, and leaves by itself.
-- Phones: the cards scroll, the tab column scrolls, every button is >= 56 px tall, no text under 18 px.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local BadgesLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Badges"))
local BoostsLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Boosts"))
local TutorialLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Tutorial"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Modal = require(script.Parent.Modal)
local Theme = require(script.Parent.Theme)

local BadgeBook = {}

local NAME = "Badges"
local CARD_HEIGHT = 124
local GAP = Theme.Space.Gap
local BOOSTS_HEIGHT = 30
local NO_TIER = Color3.fromRGB(190, 190, 210)
local BANNER_SECONDS = 3.2
local BANNER_GAP = 0.4 -- between two cheers in a row

local function hex(value: any, fallback: Color3): Color3
	if type(value) ~= "string" then
		return fallback
	end
	local ok, color = pcall(Color3.fromHex, value)
	return if ok then color else fallback
end

-- "+3% 💰", with the scope's icon when the boost is only for some cures or one station ("+5% 💰 🌙").
local function boostText(data: any, boost: any, percent: number): string
	local text = "+" .. percent .. "% " .. ((BoostsLogic.ICONS :: any)[boost.Kind] or "✨")
	local scope = boost.Scope
	if type(scope) == "string" then
		local wing = rawget(data.Wings, scope)
		local station = rawget(data.Stations, scope)
		local icon = if scope == "Night" then "🌙" elseif wing then wing.Icon elseif station then station.Icon else nil
		if icon then
			text ..= " " .. icon
		end
	end
	return text
end

type Card = {
	Frame: Frame,
	Def: any,
	Tile: Frame,
	TileStroke: UIStroke,
	Medal: TextLabel,
	Title: TextLabel,
	Fill: Frame,
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
		Title = "🏅 Badges",
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

	local boostLine = Kit.label({
		Name = "Boosts",
		Text = "",
		TextScaled = true,
		Size = UDim2.new(1, 0, 0, BOOSTS_HEIGHT - Theme.Space.Step[1]),
		Parent = page,
	})
	Kit.textLimit(boostLine, Theme.TextSize.Body)

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
	pad.PaddingTop = UDim.new(0, Theme.Space.Step[1])
	pad.PaddingBottom = UDim.new(0, Theme.Space.Gap)
	pad.PaddingLeft = UDim.new(0, Theme.Space.Step[1]) -- scrolling frames clip: keep the tier frames whole
	pad.PaddingRight = UDim.new(0, Theme.Space.PadCard)
	pad.Parent = scroll

	local function choose(id: string)
		tabView.select(id)
	end

	--------------------------------------------------------------------------------------------------------------
	-- The cards
	--------------------------------------------------------------------------------------------------------------
	for index, def in defs do
		local frame = Instance.new("Frame")
		frame.Name = def.Id
		frame.LayoutOrder = index
		frame.BackgroundColor3 = Theme.Colors.Card
		frame.BorderSizePixel = 0
		frame.Size = UDim2.new(1, 0, 0, CARD_HEIGHT)
		Kit.corner(frame, Theme.Radius.Medium)
		Kit.stroke(frame, Theme.Colors.CardLine, Theme.Stroke.Fine)
		frame.Parent = scroll

		-- The badge's own tile, framed in its tier's colour (the tier is what the colour means here).
		local tile = Instance.new("Frame")
		tile.Name = "Tile"
		tile.AnchorPoint = Vector2.new(0, 0.5)
		tile.Position = UDim2.new(0, Theme.Space.PadCard, 0.5, 0)
		tile.Size = UDim2.fromOffset(80, 80)
		tile.BackgroundColor3 = Theme.Colors.Well
		tile.BorderSizePixel = 0
		Kit.corner(tile, Theme.Radius.Medium)
		local tileStroke = Kit.stroke(tile, NO_TIER, Theme.Stroke.Bold)
		tile.Parent = frame
		Kit.label({
			Name = "Icon",
			Text = def.Icon,
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.66, 0.66),
			Parent = tile,
		})
		local medal = Kit.label({
			Name = "Medal",
			Text = "",
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -2, 0, 4),
			Size = UDim2.fromOffset(32, 32),
			ZIndex = 3,
			Parent = tile,
		})

		local left = 106
		local title = Kit.label({
			Name = "Title",
			Text = def.Name,
			Font = Theme.DisplayFont,
			TextScaled = true,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(left, Theme.Space.Gap),
			Size = UDim2.new(1, -left - Theme.Space.PadCard, 0, 28),
			Parent = frame,
		})
		Kit.textLimit(title, Theme.TextSize.Body)
		local goal = Kit.label({
			Name = "Goal",
			Text = def.Goal,
			TextScaled = true,
			TextWrapped = false,
			TextColor3 = Theme.Colors.InkSoft,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(left, 38),
			Size = UDim2.new(1, -left - Theme.Space.PadCard, 0, 22),
			Parent = frame,
		})
		Kit.textLimit(goal, Theme.TextSize.Caption)

		local track = Instance.new("Frame")
		track.Name = "Track"
		track.Position = UDim2.fromOffset(left, 66)
		track.Size = UDim2.new(1, -left - 96, 0, 16)
		track.BackgroundColor3 = Theme.Colors.Well
		track.BorderSizePixel = 0
		Kit.corner(track, Theme.Radius.Small)
		track.Parent = frame
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(0, 1)
		fill.BorderSizePixel = 0
		Kit.corner(fill, Theme.Radius.Small)
		fill.Parent = track
		local countLabel = Kit.label({
			Name = "Count",
			Text = "",
			Font = Theme.DisplayFont,
			TextScaled = true,
			TextWrapped = false,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -Theme.Space.PadCard, 0, 60),
			Size = UDim2.fromOffset(80, 26),
			Parent = frame,
		})
		Kit.textLimit(countLabel, Theme.TextSize.Body)
		local nextLabel = Kit.label({
			Name = "Next",
			Text = "",
			TextScaled = true,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(left, 92),
			Size = UDim2.new(1, -left - Theme.Space.PadCard, 0, 24),
			Parent = frame,
		})
		Kit.textLimit(nextLabel, Theme.TextSize.Body)

		table.insert(cards, {
			Frame = frame,
			Def = def,
			Tile = tile,
			TileStroke = tileStroke,
			Medal = medal,
			Title = title,
			Fill = fill,
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
			local tierColor = if tier then hex(tier.Color, NO_TIER) else NO_TIER
			card.TileStroke.Color = tierColor
			card.Tile.BackgroundColor3 = if tier then Kit.lighten(tierColor, 0.55) else Theme.Colors.Well
			card.Medal.Text = if tier then tier.Icon else ""
			card.Title.Text = def.Name .. (if tier then " · " .. tier.Name else "")
			local nextTier = tiers[tierIndex + 1]
			local nextAt = def.Thresholds[tierIndex + 1]
			if nextTier and nextAt then
				local from = if tierIndex > 0 then def.Thresholds[tierIndex] else 0
				local ratio = math.clamp((value - from) / math.max(1, nextAt - from), 0, 1)
				card.Fill.Size = UDim2.fromScale(ratio, 1)
				card.Fill.BackgroundColor3 = hex(nextTier.Color, NO_TIER)
				card.Count.Text = Hud.format(value) .. "/" .. Hud.format(nextAt)
				card.Next.Text = nextTier.Icon
					.. " "
					.. nextTier.Name
					.. " → "
					.. boostText(data, def.Boost, BadgesLogic.boostAt(def, tierIndex + 1))
					.. " · 💰"
					.. Hud.format(nextTier.Cash)
					.. " ⭐"
					.. nextTier.Stars
			else
				card.Fill.Size = UDim2.fromScale(1, 1)
				card.Fill.BackgroundColor3 = tierColor
				card.Count.Text = Hud.format(value)
				card.Next.Text = "🎉 Maxed! " .. boostText(data, def.Boost, BadgesLogic.boostAt(def, tierIndex))
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
				cheer("🏅", #ups .. " badges up!", Theme.Colors.Cash) -- one banner, not a long queue
			else
				for _, up in ups do
					local tier = up.Tier
					cheer(
						up.Def.Icon,
						tier.Icon .. " " .. tier.Name .. " " .. up.Def.Name .. "!",
						hex(tier.Color, Theme.Colors.Cash)
					)
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
