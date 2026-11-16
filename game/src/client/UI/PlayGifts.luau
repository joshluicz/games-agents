--!strict
-- PlayGifts (game/README.md "Play gifts, Doctor ranks, boosts and badges"): the 🎁 panel.
--   init(ctx)   opens on ctx.fire("Open", "Gifts") (the HUD's 🎁 button under the wallet)
--
-- From the top:
--   the Doctor rank card   "🩺 Doctor rank: Resident", then "4h 12m played · next: 🥼 Doctor at 10h" and a bar to it
--   your boosts            Hud.boostLine: timed boosts with their play time left, then the permanent percents
--   six gift cards         one per Data/Playtime gift: its minutes of play today, its rewards (💰 ⭐ and a boost
--                          icon), and its state: 🔒 with the play time still to go, READY (rays behind it and a
--                          shining Open! button) or ✅ opened
--   the footer             "🎉 All gifts opened today!" once they all are: the natural place to stop. While the
--                          server has paused your time (PlayCounting false: you've been still a while) it says so
-- Opening calls ClaimPlayGift(index); the server checks everything and decides what you get, the panel only shows it.
-- Nothing here counts down to something you could miss: time only moves while you play, and a new UTC day just
-- refills the gifts. No Robux, no streaks.
-- Bus: fires "Claimed" ("PlayGift", index) after the server says yes, and "Cheer" (icon, text, colour) when the
-- Snapshot's Doctor rank goes up (BadgeBook shows the banner).
-- Phones: the content scrolls, the cards go two to a row on a narrow panel, and every button is >= 56 px tall.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local PlaytimeLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Playtime"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local PlayGifts = {}

local NAME = "Gifts"
local CARD_HEIGHT = 184
local GAP = 10
local RANK_COLOR = Theme.Colors.Purple

local function textLimit(label: TextLabel, max: number)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = max
	limit.MinTextSize = 12
	limit.Parent = label
end

-- A Kit button's colour (and the colour Kit.setEnabled restores).
local function paintButton(button: TextButton, color: Color3)
	local fill = Kit.lighten(color, 0.08)
	button.BackgroundColor3 = fill
	button:SetAttribute("KitColor", fill)
end

local function rewardText(data: any, gift: any): string
	local parts = { "💰" .. Hud.format(gift.Cash) }
	if gift.Stars > 0 then
		table.insert(parts, "⭐" .. gift.Stars)
	end
	local boost = gift.Boost and rawget(data.Boosts, gift.Boost)
	if boost then
		table.insert(parts, boost.Icon)
	end
	return table.concat(parts, " ")
end

type Card = {
	Frame: Frame,
	Icon: TextLabel,
	Rays: Frame,
	Lock: TextLabel,
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
		Title = "🎁 Play Gifts",
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
	pad.PaddingTop = UDim.new(0, 3)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 3) -- scrolling frames clip: keep the outlines whole
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = scroll

	--------------------------------------------------------------------------------------------------------------
	-- The Doctor rank card
	--------------------------------------------------------------------------------------------------------------
	local rankCard = Instance.new("Frame")
	rankCard.Name = "Rank"
	rankCard.LayoutOrder = 1
	rankCard.BackgroundColor3 = Kit.lighten(RANK_COLOR, 0.86)
	rankCard.BorderSizePixel = 0
	rankCard.Size = UDim2.new(1, 0, 0, 100)
	Kit.corner(rankCard, 16)
	Kit.stroke(rankCard, Theme.Colors.Outline, Theme.Size.Stroke)
	rankCard.Parent = scroll

	local rankTile = Instance.new("Frame")
	rankTile.Name = "Tile"
	rankTile.AnchorPoint = Vector2.new(0, 0.5)
	rankTile.Position = UDim2.new(0, 10, 0.5, 0)
	rankTile.Size = UDim2.fromOffset(72, 72)
	rankTile.BackgroundColor3 = Kit.lighten(RANK_COLOR, 0.08)
	rankTile.BorderSizePixel = 0
	Kit.corner(rankTile, 18)
	Kit.stroke(rankTile, Theme.Colors.Outline, Theme.Size.Stroke)
	Palette.candyGradient(rankTile)
	Kit.gloss(rankTile, 4)
	rankTile.Parent = rankCard
	local rankIcon = Kit.label({
		Name = "Icon",
		Text = "",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.74, 0.74),
		Parent = rankTile,
	})
	local rankTitle = Kit.label({
		Name = "Title",
		Text = "",
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(94, 10),
		Size = UDim2.new(1, -104, 0, 30),
		Parent = rankCard,
	})
	textLimit(rankTitle, 24)
	local rankSub = Kit.label({
		Name = "Played",
		Text = "",
		TextScaled = true,
		TextColor3 = Theme.Colors.InkSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(94, 42),
		Size = UDim2.new(1, -104, 0, 22),
		Parent = rankCard,
	})
	textLimit(rankSub, 20)
	local rankTrack = Instance.new("Frame")
	rankTrack.Name = "Track"
	rankTrack.Position = UDim2.fromOffset(94, 70)
	rankTrack.Size = UDim2.new(1, -108, 0, 16)
	rankTrack.BackgroundColor3 = Theme.Colors.Paper
	rankTrack.BorderSizePixel = 0
	Kit.corner(rankTrack, 8)
	Kit.stroke(rankTrack, Theme.Colors.Outline, 2)
	rankTrack.Parent = rankCard
	local rankFill = Instance.new("Frame")
	rankFill.Name = "Fill"
	rankFill.Size = UDim2.fromScale(0, 1)
	rankFill.BackgroundColor3 = Kit.lighten(RANK_COLOR, 0.08)
	rankFill.BorderSizePixel = 0
	Kit.corner(rankFill, 8)
	Palette.candyGradient(rankFill)
	rankFill.Parent = rankTrack

	--------------------------------------------------------------------------------------------------------------
	-- Your boosts
	--------------------------------------------------------------------------------------------------------------
	local boostLine = Kit.label({
		Name = "Boosts",
		Text = "",
		TextScaled = true,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 30),
		Parent = scroll,
	})
	textLimit(boostLine, 22)

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

	local footer = Kit.label({
		Name = "Footer",
		Text = "",
		TextScaled = true,
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 32),
		Parent = scroll,
	})
	textLimit(footer, 24)

	local cards: { Card } = {}
	local claiming: number? = nil
	local render: () -> ()

	local function makeCard(index: number, gift: any): Card
		local frame = Instance.new("Frame")
		frame.Name = "Gift" .. index
		frame.LayoutOrder = index
		frame.BackgroundColor3 = Theme.Colors.Paper
		frame.BorderSizePixel = 0
		Kit.corner(frame, 16)
		Kit.stroke(frame, Theme.Colors.Outline, Theme.Size.Stroke)
		frame.Parent = grid

		local minutes = Kit.label({
			Name = "Minutes",
			Text = "⏱️ " .. gift.Minutes .. " min",
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.new(1, -12, 0, 24),
			Parent = frame,
		})
		textLimit(minutes, 20)

		local holder = Instance.new("Frame")
		holder.Name = "Holder"
		holder.AnchorPoint = Vector2.new(0.5, 0)
		holder.Position = UDim2.new(0.5, 0, 0, 34)
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
		local lock = Kit.label({
			Name = "Lock",
			Text = "🔒",
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.92, 0.88),
			Size = UDim2.fromOffset(26, 26),
			ZIndex = 3,
			Parent = holder,
		})

		local reward = Kit.label({
			Name = "Reward",
			Text = rewardText(data, gift),
			TextScaled = true,
			Outlined = true,
			TextColor3 = Theme.Colors.Cash,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 98),
			Size = UDim2.new(1, -12, 0, 22),
			Parent = frame,
		})
		textLimit(reward, 20)
		Kit.outline(reward, 2)

		local stateLabel = Kit.label({
			Name = "State",
			Text = "",
			TextScaled = true,
			TextColor3 = Theme.Colors.InkSoft,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -14),
			Size = UDim2.new(1, -16, 0, 34),
			Parent = frame,
		})
		textLimit(stateLabel, 24)

		local claim = Kit.button({
			Name = "Claim",
			Kind = "Good",
			Text = "Open!",
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -16, 0, Theme.Size.ButtonHeight),
			Visible = false,
			Parent = frame,
		})
		textLimit(claim :: any, Theme.TextSize.Body)
		Kit.shine(claim)

		local card: Card = {
			Frame = frame,
			Icon = icon,
			Rays = rays,
			Lock = lock,
			State = stateLabel,
			Claim = claim,
			Shown = "",
		}

		claim.Activated:Connect(function()
			if claiming then
				return
			end
			claiming = index
			claim.Text = "⏳"
			claim.Interactable = false
			local ok, reply = Hud.ask(ctx.Remotes.ClaimPlayGift, index)
			claiming = nil
			claim.Interactable = true
			claim.Text = "Open!"
			if ok then
				ctx.fire("Claimed", "PlayGift", index)
				Hud.sound("Fanfare")
				Kit.bump(icon)
				Hud.fly(holder, "💰", "Cash", 6)
				if gift.Stars > 0 then
					Hud.fly(holder, "⭐", "Stars", math.min(gift.Stars, 5))
				end
				ctx.toast(if reply ~= "" then reply else "🎁 " .. rewardText(data, gift))
			else
				ctx.toast(if reply ~= "" then reply else "Oops! Try again.")
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
		local played = PlaytimeLogic.duration(save.TotalSeconds) .. " played"
		local nextIndex = PlaytimeLogic.nextRank(save.TotalSeconds, ranks)
		local nextRank = if nextIndex then ranks[nextIndex] else nil
		if nextRank then
			rankSub.Text = played
				.. " · next: "
				.. nextRank.Icon
				.. " "
				.. nextRank.Name
				.. " at "
				.. nextRank.Hours
				.. "h"
			local from = if nextIndex and nextIndex > 1 then PlaytimeLogic.rankSeconds(ranks[nextIndex - 1]) else 0
			local goal = PlaytimeLogic.rankSeconds(nextRank)
			rankFill.Size = UDim2.fromScale(math.clamp((save.TotalSeconds - from) / math.max(1, goal - from), 0, 1), 1)
		else
			rankSub.Text = played .. " · top rank! 🎉"
			rankFill.Size = UDim2.fromScale(1, 1)
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
			card.Lock.Visible = giftState == "Locked"
			card.Icon.Text = if giftState == "Claimed" then "✅" else gift.Icon
			card.Icon.TextTransparency = if giftState == "Locked" then 0.35 else 0
			card.Claim.Visible = ready and claiming ~= index or claiming == index
			card.State.Visible = not card.Claim.Visible
			if giftState == "Locked" then
				local left = PlaytimeLogic.giftSeconds(gift) - save.TodaySeconds
				card.State.Text = "⏳ " .. PlaytimeLogic.clock(left)
				card.Frame.BackgroundColor3 = Theme.Colors.Paper
			elseif giftState == "Claimed" then
				card.State.Text = "✅ Opened"
				card.Frame.BackgroundColor3 = Kit.lighten(Theme.Colors.Good, 0.85)
			else
				card.Frame.BackgroundColor3 = Kit.lighten(Theme.Colors.Cash, 0.8)
				paintButton(card.Claim, Theme.Colors.Good)
				focus = focus or card.Claim
			end
			if ready and card.Shown ~= "Ready" and card.Shown ~= "" then
				Kit.bump(card.Claim)
			end
			card.Shown = giftState
		end
		if PlaytimeLogic.allOpened(save, day, gifts) then
			footer.Text = "🎉 All gifts opened today!"
		elseif player:GetAttribute("PlayCounting") == false then
			footer.Text = "💤 Paused while you rest"
		else
			footer.Text = "🎁 Gifts unlock as you play"
		end
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
