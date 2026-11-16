--!strict
-- BadgeBook (game/README.md "Badges"): the 🏅 Badge Book, and the reward banner for tier-ups and Doctor ranks.
--   init(ctx)   opens on ctx.fire("Open", "Badges") (the HUD's 🏅 tab, shown once the tutorial is done)
--
-- The Book, from the top:
--   your boosts      Hud.boostLine: timed boosts with their play time left, then the permanent percents
--   category tabs    one per Data/Badges category (🏥 Clinic, 🗺️ Wings, 🧪 Stations, 💛 Friends)
--   badge cards      per badge: its icon on a tile framed in its tier's colour (Bronze, Silver, Gold, Diamond, Ruby,
--                    Mythic; grey before Bronze) with the tier's medal, the name and what to do, a bar and "n/next"
--                    to the next tier, then that tier's boost and rewards ("🥇 Gold → +3% 💰 · 💰400 ⭐8"); a maxed
--                    badge says so. Values come from Logic/Badges.statValue on the Snapshot (Stats, Playtime, Story,
--                    Rooms, Decor), the tiers from Snapshot.Badges. The server decides; this only shows it.
-- The banner (ctx.on "Celebrate" (icon, text, colour), and every tier-up the Snapshot shows after the save loaded):
-- a candy card slides in at the top with turning rays behind the icon, a bump and a fanfare, then leaves by itself
-- after a few seconds. It never blocks play, waits while the first-session tutorial runs, and honours calm motion.
-- Phones: the cards scroll, the tabs share the width, every button is >= 56 px tall.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local BadgesLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Badges"))
local BoostsLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Boosts"))
local TutorialLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Tutorial"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local BadgeBook = {}

local NAME = "Badges"
local ACCENT = Theme.Colors.Primary
local CARD_HEIGHT = 124
local GAP = 10
local NO_TIER = Color3.fromRGB(190, 190, 210)
local BANNER_SECONDS = 3.2

local function textLimit(gui: GuiObject, max: number)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = max
	limit.MinTextSize = 12
	limit.Parent = gui
end

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
		Accent = ACCENT,
		MaxSize = Vector2.new(560, 640),
	})

	local boostLine = Kit.label({
		Name = "Boosts",
		Text = "",
		TextScaled = true,
		Size = UDim2.new(1, 0, 0, 28),
		Parent = modal.Body,
	})
	textLimit(boostLine, 22)

	-- The category tabs: a pale tint while waiting, full orange with outlined text when chosen.
	local tabRow = Instance.new("Frame")
	tabRow.Name = "Tabs"
	tabRow.BackgroundTransparency = 1
	tabRow.Position = UDim2.fromOffset(0, 34)
	tabRow.Size = UDim2.new(1, 0, 0, Theme.Size.ButtonHeight)
	tabRow.Parent = modal.Body
	local tabList = Kit.list(tabRow, Enum.FillDirection.Horizontal, 8)
	tabList.HorizontalAlignment = Enum.HorizontalAlignment.Left

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, 34 + Theme.Size.ButtonHeight + GAP)
	scroll.Size = UDim2.new(1, 0, 1, -(34 + Theme.Size.ButtonHeight + GAP))
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = Theme.Colors.Stroke
	scroll.Selectable = false
	scroll.Parent = modal.Body
	local list = Kit.list(scroll, Enum.FillDirection.Vertical, GAP)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 3)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 4) -- scrolling frames clip: keep the tier frames whole
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = scroll

	local tabs: { [string]: TextButton } = {}
	local chosen = categories[1] and categories[1].Id or ""
	local cards: { Card } = {}
	local render: () -> ()

	local function paintTab(button: TextButton, selected: boolean)
		local fill = if selected then Kit.lighten(ACCENT, 0.08) else Kit.lighten(ACCENT, 0.78)
		button.BackgroundColor3 = fill
		button:SetAttribute("KitColor", fill)
		button.TextColor3 = if selected then Theme.Colors.OnColor else Theme.Colors.Ink
		Kit.outline(button, 2).Enabled = selected
	end

	local function choose(id: string)
		chosen = id
		for categoryId, button in tabs do
			paintTab(button, categoryId == id)
		end
		for _, card in cards do
			card.Frame.Visible = card.Def.Category == id
		end
		scroll.CanvasPosition = Vector2.zero
		modal.Focus = tabs[id]
	end

	local count = math.max(1, #categories)
	for index, category in categories do
		local button = Kit.button({
			Name = category.Id,
			Kind = "Quiet",
			Text = category.Icon .. " " .. category.Name,
			TextScaled = true,
			LayoutOrder = index,
			Size = UDim2.new(1 / count, -8 * (count - 1) / count, 1, 0),
			Parent = tabRow,
		})
		textLimit(button, 22)
		tabs[category.Id] = button
		button.Activated:Connect(function()
			choose(category.Id)
			Hud.pop(button, 1.06)
		end)
	end

	--------------------------------------------------------------------------------------------------------------
	-- The cards
	--------------------------------------------------------------------------------------------------------------
	for index, def in defs do
		local frame = Instance.new("Frame")
		frame.Name = def.Id
		frame.LayoutOrder = index
		frame.BackgroundColor3 = Theme.Colors.Paper
		frame.BorderSizePixel = 0
		frame.Size = UDim2.new(1, 0, 0, CARD_HEIGHT)
		Kit.corner(frame, 16)
		Kit.stroke(frame, Theme.Colors.Outline, Theme.Size.Stroke)
		frame.Parent = scroll

		local tile = Instance.new("Frame")
		tile.Name = "Tile"
		tile.AnchorPoint = Vector2.new(0, 0.5)
		tile.Position = UDim2.new(0, 12, 0.5, 0)
		tile.Size = UDim2.fromOffset(80, 80)
		tile.BorderSizePixel = 0
		Kit.corner(tile, 20)
		local tileStroke = Kit.stroke(tile, NO_TIER, 6)
		Palette.candyGradient(tile)
		Kit.gloss(tile, 6)
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
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(left, 8),
			Size = UDim2.new(1, -left - 10, 0, 28),
			Parent = frame,
		})
		textLimit(title, 24)
		local goal = Kit.label({
			Name = "Goal",
			Text = def.Goal,
			TextScaled = true,
			TextColor3 = Theme.Colors.InkSoft,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(left, 38),
			Size = UDim2.new(1, -left - 10, 0, 20),
			Parent = frame,
		})
		textLimit(goal, 18)

		local track = Instance.new("Frame")
		track.Name = "Track"
		track.Position = UDim2.fromOffset(left, 64)
		track.Size = UDim2.new(1, -left - 96, 0, 18)
		track.BackgroundColor3 = Theme.Colors.Paper
		track.BorderSizePixel = 0
		Kit.corner(track, 9)
		Kit.stroke(track, Theme.Colors.Outline, 2)
		track.Parent = frame
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(0, 1)
		fill.BorderSizePixel = 0
		Kit.corner(fill, 9)
		Palette.candyGradient(fill)
		fill.Parent = track
		local countLabel = Kit.label({
			Name = "Count",
			Text = "",
			TextScaled = true,
			Outlined = true,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 60),
			Size = UDim2.fromOffset(80, 26),
			Parent = frame,
		})
		textLimit(countLabel, 20)
		local nextLabel = Kit.label({
			Name = "Next",
			Text = "",
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(left, 92),
			Size = UDim2.new(1, -left - 10, 0, 22),
			Parent = frame,
		})
		textLimit(nextLabel, 20)

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
			card.Tile.BackgroundColor3 = if tier then Kit.lighten(tierColor, 0.45) else Theme.Colors.Card
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
	-- The banner: tier-ups and Doctor ranks
	--------------------------------------------------------------------------------------------------------------
	local bannerGui = Kit.screen("Celebrate", Theme.DisplayOrder.Fx)
	local banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 84)
	banner.Size = UDim2.fromOffset(360, 96)
	banner.BackgroundColor3 = Kit.lighten(ACCENT, 0.08)
	banner.BorderSizePixel = 0
	banner.Visible = false
	Kit.corner(banner, 26)
	Kit.stroke(banner, Theme.Colors.Outline, Theme.Size.StrokeLarge)
	Palette.candyGradient(banner)
	Kit.gloss(banner, 18)
	banner.Parent = bannerGui
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(360, 96)
	limit.Parent = banner
	local bannerHolder = Instance.new("Frame")
	bannerHolder.Name = "Holder"
	bannerHolder.AnchorPoint = Vector2.new(0, 0.5)
	bannerHolder.Position = UDim2.new(0, 10, 0.5, 0)
	bannerHolder.Size = UDim2.fromOffset(76, 76)
	bannerHolder.BackgroundTransparency = 1
	bannerHolder.Parent = banner
	local bannerRays = Kit.rays(bannerHolder, Theme.Colors.Cash)
	local bannerIcon = Kit.label({
		Name = "Icon",
		Text = "",
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
		Parent = bannerHolder,
	})
	local bannerText = Kit.label({
		Name = "Text",
		Text = "",
		TextScaled = true,
		Outlined = true,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 96, 0.5, 0),
		Size = UDim2.new(1, -108, 0, 56),
		Parent = banner,
	})
	textLimit(bannerText, 30)
	Kit.outline(bannerText, 3)

	type Cheer = { Icon: string, Text: string, Color: Color3 }
	local queue: { Cheer } = {}
	local showing = false
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
				bannerIcon.Text = cheer.Icon
				bannerText.Text = cheer.Text
				for _, ray in bannerRays:GetChildren() do
					if ray:IsA("Frame") then
						ray.BackgroundColor3 = Kit.lighten(cheer.Color, 0.2)
					end
				end
				Kit.popIn(banner)
				Kit.bump(bannerIcon)
				Hud.sound("Fanfare")
				task.wait(BANNER_SECONDS)
				Kit.popOut(banner)
				task.wait(0.4)
			end
			showing = false
		end)
	end
	local function cheer(icon: any, text: any, color: any)
		if type(icon) ~= "string" or type(text) ~= "string" then
			return
		end
		table.insert(queue, { Icon = icon, Text = text, Color = if typeof(color) == "Color3" then color else ACCENT })
		showNext()
	end
	ctx.on("Celebrate", cheer)

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
				cheer("🏅", #ups .. " badges up!", ACCENT) -- one banner, not a long queue
			else
				for _, up in ups do
					local tier = up.Tier
					cheer(
						up.Def.Icon,
						tier.Icon .. " " .. tier.Name .. " " .. up.Def.Name .. "!",
						hex(tier.Color, ACCENT)
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
