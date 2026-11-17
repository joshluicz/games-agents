--!strict
-- PlayGifts (game/README.md "Play gifts, Doctor ranks, boosts and badges"): the play gifts panel.
--   init(ctx)   opens on ctx.fire("Open", "Gifts") (the HUD's gifts rail button)
--   PlayGifts.Pure   the words (tests/ProgressionPanels.spec loads the PURE block on its own)
--
-- From the top:
--   the Doctor rank card   the rank's Art in a Kit.artTile, "Doctor rank: Resident" (Normal), then one Soft line
--                          "4h 12m played · next: Doctor at 10h" and a Kit.bar (navy) to it
--   your boosts            Hud.boostLine (a Soft line): timed boosts with their play time left, then the permanent
--                          percents
--   six gift cards         one per Data/Playtime gift: its minutes of play today, its Art (🔒 / ✅ as its one State
--                          badge), what it pays in one Soft line with one Unit ("💰 30 · 1 star · boost"), and its
--                          state: the play time still to go, READY (rays behind it and a shining Collect "Open") or
--                          Opened
--   the footer             "All gifts opened today!" once they all are: the natural place to stop. While the server
--                          has paused your time (PlayCounting false: you've been still a while) it says so
-- Opening calls ClaimPlayGift(index); the server checks everything and decides what you get, the panel only shows it.
-- Nothing here counts down to something you could miss: time only moves while you play, and a new UTC day just
-- refills the gifts. No Robux, no streaks.
-- Bus: fires "Claimed" ("PlayGift", index) after the server says yes, and "Cheer" (icon, text, colour) when the
-- Snapshot's Doctor rank goes up (BadgeBook shows the banner).
-- Phones: the content scrolls, the cards go two to a row on a narrow panel, and every button is >= 56 px tall.
-- The calm UI (docs/plan/2026-11-17-ui-direction.md §4 #10; Joshua, memory-20261117-007): the title in words,
-- Kit.card cards with no line, words with one Unit, no emoji as a bullet. A READY gift is the reward moment: a warm
-- gold card, rays behind its Art and the Collect "Open", which may shine (one perpetual effect on screen: Kit's
-- motion budget). No text under 18 px.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local PlaytimeLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Playtime"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local PlayGifts = {}

------------------------------------------------------------------------------------------------------------------
-- Pure: the words. Only UI/Icons (a pure library).
------------------------------------------------------------------------------------------------------------------
-- PURE-BEGIN
local Pure = {}

Pure.TEXT = {
	Title = "Play gifts",
	Open = "Open",
	Opened = "Opened",
	Busy = Icons.State.Waiting, -- alone in place of the button's label while the server answers
	AllOpened = "All gifts opened today!",
	Paused = "Paused while you rest",
	Unlock = "Gifts unlock as you play",
	TopRank = "top rank!",
	Oops = "Oops! Try again.",
	Got = "You got ",
}

-- What a gift pays, with ONE Unit: "💰 30 · 1 star · boost".
function Pure.rewardText(gift: any, boosts: any, format: (n: number) -> string): string
	local parts = { Icons.unit("Cash", format(if type(gift.Cash) == "number" then gift.Cash else 0)) }
	local stars = if type(gift.Stars) == "number" then gift.Stars else 0
	if stars > 0 then
		table.insert(parts, stars .. (if stars == 1 then " star" else " stars"))
	end
	local boost = gift.Boost and type(boosts) == "table" and rawget(boosts, gift.Boost)
	if type(boost) == "table" then
		table.insert(parts, "boost")
	end
	return table.concat(parts, " · ")
end

-- The rank card's Soft line, in words: "4h 12m played · next: Doctor at 10h" (or "· top rank!").
function Pure.rankLine(played: string, nextRank: any): string
	if type(nextRank) == "table" then
		return played .. " played · next: " .. tostring(nextRank.Name) .. " at " .. tostring(nextRank.Hours) .. "h"
	end
	return played .. " played · " .. Pure.TEXT.TopRank
end

-- The footer, in words: every gift opened, time paused, or how gifts come.
function Pure.footer(allOpened: boolean, counting: boolean): string
	if allOpened then
		return Pure.TEXT.AllOpened
	elseif not counting then
		return Pure.TEXT.Paused
	end
	return Pure.TEXT.Unlock
end
-- PURE-END

PlayGifts.Pure = Pure

local NAME = "Gifts"
local CARD_HEIGHT = 196
local GAP = Theme.Space.PadCard
local RANK_COLOR = Theme.Colors.Purple -- the Doctor rank's own colour: its cheer (the bar is navy, as every bar)

local function rewardText(data: any, gift: any): string
	return Pure.rewardText(gift, data.Boosts, Hud.format)
end

type Card = {
	Frame: Frame,
	Holder: Frame,
	Icon: TextLabel,
	Rays: Frame,
	State: TextLabel,
	Claim: TextButton,
	Shown: string, -- the state as last drawn, so a gift that unlocks bounces once
}

function PlayGifts.init(ctx: Types.Ctx)
	local data = ctx.Data :: any
	local player = Players.LocalPlayer
	local gifts = data.Playtime.Gifts
	local ranks = data.Playtime.Ranks
	local trainee = data.Playtime.Trainee
	local initial = ctx.State

	local modal = Hud.modal(ctx, {
		Name = NAME,
		Title = Pure.TEXT.Title,
		MaxSize = Vector2.new(560, 620),
	})

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
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
	pad.PaddingTop = UDim.new(0, Theme.Space.Tight)
	pad.PaddingBottom = UDim.new(0, Theme.Space.Line)
	pad.PaddingLeft = UDim.new(0, Theme.Space.Tight)
	pad.PaddingRight = UDim.new(0, Theme.Space.PadCard)
	pad.Parent = scroll

	--------------------------------------------------------------------------------------------------------------
	-- The Doctor rank card
	--------------------------------------------------------------------------------------------------------------
	local rankCard = Kit.card({ Name = "Rank", LayoutOrder = 1, Pad = false, Parent = scroll })
	rankCard.AutomaticSize = Enum.AutomaticSize.None
	rankCard.Size = UDim2.new(1, 0, 0, 100)
	local padCard = Theme.Space.PadCard
	local rankTile = Kit.artTile({
		Icon = "",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, padCard, 0.5, 0),
		Size = UDim2.fromOffset(72, 72),
		Parent = rankCard,
	})
	local rankIcon = rankTile:FindFirstChild("Icon") :: TextLabel
	local rankLeft = padCard * 2 + 72
	local rankTitle = Kit.name({
		Name = "Title",
		Text = "",
		Position = UDim2.fromOffset(rankLeft, padCard),
		Size = UDim2.new(1, -rankLeft - padCard, 0, Theme.TextSize.Body + Theme.Space.Tight),
		Parent = rankCard,
	})
	local rankSub = Kit.fact({
		Name = "Played",
		Text = "",
		Position = UDim2.fromOffset(rankLeft, padCard + 30),
		Size = UDim2.new(1, -rankLeft - padCard, 0, Theme.TextSize.Caption + Theme.Space.Tight),
		Parent = rankCard,
	})
	local _, setRankBar = Kit.bar({
		Name = "Bar",
		Position = UDim2.fromOffset(rankLeft, padCard + 62),
		Size = UDim2.new(1, -rankLeft - padCard, 0, Theme.Calm.Bar),
		Parent = rankCard,
	})

	--------------------------------------------------------------------------------------------------------------
	-- Your boosts
	--------------------------------------------------------------------------------------------------------------
	local boostLine = Kit.fact({
		Name = "Boosts",
		Text = "",
		LayoutOrder = 2,
		Parent = scroll,
	})

	--------------------------------------------------------------------------------------------------------------
	-- The gift cards
	--------------------------------------------------------------------------------------------------------------
	local grid = Instance.new("Frame")
	grid.Name = "Gifts"
	grid.LayoutOrder = 3
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.fromScale(1, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.Parent = scroll
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellPadding = UDim2.fromOffset(GAP, GAP)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.Parent = grid
	local function fitGrid()
		local width = grid.AbsoluteSize.X
		local columns = if width > 0 and width < 400 then 2 else 3
		gridLayout.CellSize = UDim2.new(1 / columns, -GAP * (columns - 1) / columns, 0, CARD_HEIGHT)
	end
	grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitGrid)
	fitGrid()

	local footer = Kit.fact({
		Name = "Footer",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 4,
		Parent = scroll,
	})

	local cards: { Card } = {}
	local claiming: number? = nil
	local render: () -> ()

	local function makeCard(index: number, gift: any): Card
		local frame = Kit.card({ Name = "Gift" .. index, LayoutOrder = index, Pad = false, Parent = grid })
		frame.AutomaticSize = Enum.AutomaticSize.None

		Kit.fact({
			Name = "Minutes",
			Text = gift.Minutes .. " min",
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, Theme.Space.Line),
			Size = UDim2.new(1, -Theme.Space.PadCard, 0, Theme.TextSize.Caption + Theme.Space.Tight),
			Parent = frame,
		})

		local holder = Instance.new("Frame")
		holder.Name = "Holder"
		holder.AnchorPoint = Vector2.new(0.5, 0)
		holder.Position = UDim2.new(0.5, 0, 0, 36)
		holder.Size = UDim2.fromOffset(60, 60)
		holder.BackgroundTransparency = 1
		holder.Parent = frame
		local rays = Kit.rays(holder, Theme.Colors.Cash)
		rays.Visible = false
		local icon = Kit.label({
			Name = "Icon",
			Text = gift.Icon,
			TextScaled = true,
			Size = UDim2.fromScale(1, 1),
			Parent = holder,
		})

		local reward = Kit.fact({
			Name = "Reward",
			Text = rewardText(data, gift),
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 102),
			Size = UDim2.new(1, -Theme.Space.PadCard, 0, 40),
			Parent = frame,
		})
		reward.TextWrapped = true
		reward.TextTruncate = Enum.TextTruncate.None
		reward.TextColor3 = Theme.Colors.Ink

		local stateLabel = Kit.fact({
			Name = "State",
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -Theme.Space.PadCard),
			Size = UDim2.new(1, -Theme.Space.PadPanel, 0, 34),
			Parent = frame,
		})

		local claim = Kit.button({
			Name = "Claim",
			Kind = "Collect",
			Text = Pure.TEXT.Open,
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -Theme.Space.Line),
			Size = UDim2.new(1, -Theme.Space.PadPanel, 0, Theme.Size.ButtonHeight),
			Visible = false,
			Parent = frame,
		})
		Kit.textLimit(claim, Theme.TextSize.Body)
		Kit.shine(claim) -- READY: the one allowed shine (Collect, while it shows)

		local card: Card = {
			Frame = frame,
			Holder = holder,
			Icon = icon,
			Rays = rays,
			State = stateLabel,
			Claim = claim,
			Shown = "",
		}

		claim.Activated:Connect(function()
			if claiming then
				return
			end
			claiming = index
			claim.Text = Pure.TEXT.Busy
			claim.Interactable = false
			local ok, reply = Hud.ask(ctx.Remotes.ClaimPlayGift, index)
			claiming = nil
			claim.Interactable = true
			claim.Text = Pure.TEXT.Open
			if ok then
				ctx.fire("Claimed", "PlayGift", index)
				Hud.sound("Fanfare")
				Kit.bump(icon)
				Hud.fly(holder, Icons.Unit.Cash, "Cash", 6)
				if gift.Stars > 0 then
					Hud.fly(holder, Icons.Unit.Stars, "Stars", math.min(gift.Stars, 5))
				end
				ctx.toast(if reply ~= "" then reply else Pure.TEXT.Got .. rewardText(data, gift))
			else
				ctx.toast(if reply ~= "" then reply else Pure.TEXT.Oops)
				Hud.shake(claim)
			end
			render()
		end)
		return card
	end

	for index, gift in gifts do
		cards[index] = makeCard(index, gift)
	end

	--------------------------------------------------------------------------------------------------------------
	-- Drawing (on every snapshot, and every second of play while the panel is open)
	--------------------------------------------------------------------------------------------------------------
	local function renderRank(save: PlaytimeLogic.Save)
		local rank = ranks[save.Rank]
		local shown = rank or trainee
		rankIcon.Text = shown.Icon
		rankTitle.Text = "Doctor rank: " .. shown.Name
		local played = PlaytimeLogic.duration(save.TotalSeconds)
		local nextIndex = PlaytimeLogic.nextRank(save.TotalSeconds, ranks)
		local nextRank = if nextIndex then ranks[nextIndex] else nil
		rankSub.Text = Pure.rankLine(played, nextRank)
		if nextRank then
			local from = if nextIndex and nextIndex > 1 then PlaytimeLogic.rankSeconds(ranks[nextIndex - 1]) else 0
			local goal = PlaytimeLogic.rankSeconds(nextRank)
			setRankBar(Kit.Juice.barFraction(save.TotalSeconds - from, math.max(1, goal - from)), false)
		else
			setRankBar(1, true)
		end
	end

	render = function()
		local state = ctx.State
		local save, day = Hud.livePlay(state)
		renderRank(save)
		boostLine.Text = Hud.boostLine(data, state)
		local focus: GuiObject? = nil
		for index, card in cards do
			local gift = gifts[index]
			local giftState = PlaytimeLogic.state(save, day, gifts, index) or "Locked"
			local ready = giftState == "Ready"
			card.Rays.Visible = ready
			-- The Art stays the gift; its one State badge says locked or opened.
			Kit.setState(
				card.Holder,
				if giftState == "Locked"
					then Icons.State.Locked
					elseif giftState == "Claimed" then Icons.State.Done
					else nil
			)
			card.Icon.TextTransparency = if giftState == "Locked" then 0.35 else 0
			card.Claim.Visible = ready and claiming ~= index or claiming == index
			card.State.Visible = not card.Claim.Visible
			if giftState == "Locked" then
				-- A FREE gift's play time still to go (memory-20261116-022: countdowns only for free things; it
				-- only moves while you play).
				local left = PlaytimeLogic.giftSeconds(gift) - save.TodaySeconds
				card.State.Text = PlaytimeLogic.clock(left)
				card.Frame.BackgroundColor3 = Theme.Colors.Card
			elseif giftState == "Claimed" then
				card.State.Text = Pure.TEXT.Opened
				card.Frame.BackgroundColor3 = Kit.lighten(Theme.Colors.Collect, 0.86)
			else
				card.Frame.BackgroundColor3 = Kit.lighten(Theme.Colors.Cash, 0.8)
				Kit.setRole(card.Claim, "Collect")
				focus = focus or card.Claim
			end
			if ready and card.Shown ~= "Ready" and card.Shown ~= "" then
				Kit.bump(card.Claim)
			end
			card.Shown = giftState
		end
		footer.Text =
			Pure.footer(PlaytimeLogic.allOpened(save, day, gifts), player:GetAttribute("PlayCounting") ~= false)
		modal.Focus = focus or modal.CloseButton
	end

	ctx.onState(function()
		if not claiming then
			render()
		end
	end)
	for _, attribute in { "PlayToday", "PlayTotal", "PlayCounting" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if modal.isOpen() and not claiming then
				render()
			end
		end)
	end

	-- A Doctor rank up (after the save has loaded): the banner (BadgeBook draws it).
	local shownRank: number? = nil
	ctx.onState(function(state: Types.Snapshot)
		local saved = state.Playtime
		if state == initial or type(saved) ~= "table" then
			return
		end
		local rank = saved.Rank or 0
		if shownRank ~= nil and rank > shownRank then
			local reached = ranks[rank]
			if reached then
				ctx.fire("Cheer", reached.Icon, reached.Name .. "!", RANK_COLOR)
			end
		end
		shownRank = rank
	end)

	ctx.on("Open", function(name: any)
		if name == NAME then
			render()
			scroll.CanvasPosition = Vector2.zero
			modal.open()
		end
	end)
end

return PlayGifts
