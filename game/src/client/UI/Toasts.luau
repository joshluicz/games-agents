--!strict
-- Toasts and banners (build plan Task 6; depth update T6; look overhaul T5): ONE notice stack under the HUD's Now card.
--   init(ctx)   listens to ctx.on("Toast", text) and ctx.on("Banner", spec: Types.BannerSpec)
-- Every toast in the game, from the server or from ctx.toast, arrives on the client bus as "Toast" (Main.client
-- wires that). Banners come from UI/BeltView (Golden Hour, Night Rush, an Epic+ nurse stepping on the belt; none of
-- them sends EndsAt, red line 3) and other panels' reward cheers: `{ Id, Icon, Text (≤ 6 words), Color?, EndsAt?
-- (server time: a countdown to it, free events only), Seconds? }`. A banner with the same Id replaces the old one in
-- place (it bumps); Seconds = 0 hides it; with no Seconds it stays until EndsAt (else a few seconds). Banners sit
-- above the toasts; at most MAX_BANNERS at once.
-- Where (look build plan §B7; ux audit §3.1): top centre, 8 px under the Now card (Hud.nowBottom; under the top bar
-- when no card shows), as wide as the Now card. It follows the card as it comes, goes or changes height
-- (Hud.NowMoved). The screen uses the same device-safe insets as the HUD's zones, so their numbers line up.
-- The look (ux audit §3.2 and §3.5): a white plate (Theme.Colors.Plate) with the Bold outline, the Large radius and
-- the one shadow, ink words in the body font. A banner is the same plate with an icon tile in its event's colour
-- (its Color; the night purple by default) and, with EndsAt, a small ink clock chip. Nothing on them loops (no shine).
-- Motion: each one slides down into its place with a springy overshoot while the others make room, and slides up
-- and away when it goes. The same toast text twice in a row bumps a "×2" counter instead of stacking a copy. At most
-- MAX_SHOWN toasts; the oldest goes first. Calm (Hud.calm()): no sliding or fading, they just appear and go. A soft
-- blip plays for each new one.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local HudZones = require(Shared:WaitForChild("Logic"):WaitForChild("HudZones"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Toasts = {}

local MAX_SHOWN = 3
local MAX_BANNERS = 2
local MAX_CHARS = 120
local BASE_SECONDS = 2.6
local SECONDS_PER_EXTRA_CHAR = 0.03 -- longer messages stay a little longer
local MAX_SECONDS = 5
local BANNER_SECONDS = 4 -- a banner with neither Seconds nor EndsAt
local TILE = 44 -- a banner's icon tile
local CLOCK_WIDTH = 72 -- a banner's clock chip
-- A CanvasGroup clips whatever is drawn outside it, so the card sits this far inside to keep its outline (and, at
-- the bottom, its shadow).
local OUTLINE_ROOM = 4
local SHADOW_ROOM = OUTLINE_ROOM + Theme.Shadow.Offset.Y
-- A new one starts this share of its height above its place, a little small, and springs into it.
local SLIDE_FROM = 0.7
local POP_FROM = 0.85
local REPEAT_FROM = 1.12
local JUMP = 24 -- px: the stack glides to a new place further than this, and follows smaller moves directly
local MOVE_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

type Entry = {
	Kind: "Toast" | "Banner",
	Id: string, -- banners: their Id; toasts: ""
	Text: string,
	Count: number,
	Slot: Frame, -- in the stack, sized by hand so the others slide to make room
	Group: CanvasGroup, -- what fades and slides inside the slot
	Scale: UIScale,
	Card: Frame, -- the white plate
	Tile: Frame?, -- banners: the icon tile
	Label: TextLabel,
	Icon: TextLabel?, -- banners
	Clock: TextLabel?, -- banners with EndsAt
	EndsAt: number?,
	UntilEnds: boolean, -- banners: stays until EndsAt (no Seconds)
	Token: number,
	Leaving: boolean,
	Entered: boolean,
	Height: number,
}

-- The white plate with its one shadow (Theme.Shadow), inside the entry's CanvasGroup. The shadow follows the plate's
-- height by hand (an automatic size can't take it from a sibling).
local function plate(group: CanvasGroup): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.Parent = group
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BackgroundColor3 = Theme.Shadow.Color
	shadow.BackgroundTransparency = Theme.Shadow.Transparency
	shadow.BorderSizePixel = 0
	shadow.Position = UDim2.fromOffset(Theme.Shadow.Offset.X, Theme.Shadow.Offset.Y)
	shadow.Size = UDim2.fromScale(1, 0)
	shadow.ZIndex = 1
	Kit.corner(shadow, Theme.Radius.Large)
	shadow.Parent = holder
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = Theme.Colors.Plate
	card.BorderSizePixel = 0
	card.ZIndex = 2
	Kit.corner(card, Theme.Radius.Large)
	Kit.stroke(card, Theme.Colors.Stroke, Theme.Stroke.Bold) -- uirules: allow StrokeBudget (a plate over the world)
	card.Parent = holder
	local function follow()
		local scale = group:FindFirstChildOfClass("UIScale")
		local factor = if scale and scale.Scale > 0.01 then scale.Scale else 1
		shadow.Size = UDim2.new(1, 0, 0, math.floor(card.AbsoluteSize.Y / factor + 0.5))
	end
	card:GetPropertyChangedSignal("AbsoluteSize"):Connect(follow)
	task.defer(follow)
	return card
end

-- A toast: the plate holding ink words.
local function toastCard(group: CanvasGroup, text: string): (Frame, TextLabel)
	local card = plate(group)
	local pad = Kit.pad(card, Theme.Space.Step[2])
	pad.PaddingLeft = UDim.new(0, Theme.Space.PadPanel)
	pad.PaddingRight = UDim.new(0, Theme.Space.PadPanel)
	local label = Kit.label({
		Name = "Text",
		Text = text,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Colors.Ink,
		TextWrapped = true,
		ZIndex = 3,
		Parent = card,
	})
	return card, label
end

-- A banner: the plate with its icon tile on the left, the words, and a clock chip on the right (only with EndsAt).
local function bannerCard(group: CanvasGroup): (Frame, Frame, TextLabel, TextLabel, TextLabel)
	local card = plate(group)
	Kit.pad(card, Theme.Space.Step[2])
	local list = Kit.list(card, Enum.FillDirection.Horizontal, Theme.Space.Step[3])
	list.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local tile = Instance.new("Frame")
	tile.Name = "Tile"
	tile.LayoutOrder = 1
	tile.Size = UDim2.fromOffset(TILE, TILE)
	tile.BackgroundColor3 = Theme.Colors.Night
	tile.BorderSizePixel = 0
	tile.ZIndex = 3
	Kit.corner(tile, Theme.Radius.Medium)
	tile.Parent = card
	local icon = Kit.label({
		Name = "Icon",
		Text = "",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.74, 0.74),
		ZIndex = 4,
		Parent = tile,
	})
	local text = Kit.label({
		Name = "Text",
		Text = "",
		LayoutOrder = 2,
		Size = UDim2.new(1, -(TILE + Theme.Space.Step[3]), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Colors.Ink,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
		Parent = card,
	})
	local clock = Kit.label({
		Name = "Clock",
		Text = "",
		LayoutOrder = 3,
		TextSize = Theme.TextSize.Caption,
		TextColor3 = Theme.Colors.Ink,
		TextWrapped = false,
		BackgroundColor3 = Theme.Colors.Card,
		BackgroundTransparency = 0,
		Size = UDim2.fromOffset(CLOCK_WIDTH, Theme.Size.ButtonHeight - 20),
		Visible = false,
		ZIndex = 3,
		Parent = card,
	})
	Kit.corner(clock, Theme.Radius.Small)
	-- At least a tap target tall, so a one-line banner still reads as a banner.
	local minimum = Instance.new("UISizeConstraint")
	minimum.MinSize = Vector2.new(0, Theme.Size.ButtonHeight)
	minimum.Parent = card
	return card, tile, text, icon, clock
end

function Toasts.init(ctx: Types.Ctx)
	local gui = Kit.screen("Toasts", Theme.DisplayOrder.Toast)
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- the HUD zones' insets (Hud.nowBottom's numbers)

	local holder = Instance.new("Frame")
	holder.Name = "Stack"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, Hud.Pure.noticeTop(0, Hud.topbar()))
	holder.Size = UDim2.fromOffset(HudZones.NOW_MAX, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local list = Kit.list(holder, Enum.FillDirection.Vertical, 0) -- each one's padding is the gap
	list.VerticalAlignment = Enum.VerticalAlignment.Top

	-- Under the Now card (or the top bar), as wide as the Now card. Small moves (the card growing as it pops) are
	-- followed directly; a jump (the card coming or going) glides.
	local moving: Tween? = nil
	local function place(glide: boolean)
		local size = gui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local topbar = Hud.topbar()
		local layout = HudZones.layout(size.X, size.Y, topbar)
		holder.Size = UDim2.fromOffset(Hud.Pure.noticeWidth(layout, size.X), 0)
		local y = Hud.Pure.noticeTop(Hud.nowBottom(), topbar)
		local target = UDim2.new(0.5, 0, 0, y)
		if moving then
			moving:Cancel()
			moving = nil
		end
		if glide and not Hud.calm() and math.abs(holder.Position.Y.Offset - y) > JUMP then
			local tween = TweenService:Create(holder, MOVE_INFO, { Position = target })
			moving = tween
			tween:Play()
		else
			holder.Position = target
		end
	end
	Hud.NowMoved:Connect(function()
		place(true)
	end)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		place(false)
	end)
	pcall(function()
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function()
			place(false)
		end)
	end)
	place(false)

	local toasts: { Entry } = {}
	local banners: { Entry } = {}
	local order = 0

	--------------------------------------------------------------------------------------------------------------
	-- Slots: each entry's slot is sized by hand from its card's natural height, so the stack slides to make room
	--------------------------------------------------------------------------------------------------------------

	local function natural(entry: Entry): number
		return entry.Group.AbsoluteSize.Y / math.max(entry.Scale.Scale, 0.01)
	end

	local function enter(entry: Entry)
		entry.Entered = true
		local height = entry.Height
		if Hud.calm() then
			entry.Slot.Size = UDim2.new(1, 0, 0, height)
			entry.Group.Position = UDim2.new()
			entry.Group.GroupTransparency = 0
			entry.Scale.Scale = 1
			return
		end
		entry.Group.Position = UDim2.fromOffset(0, -height * SLIDE_FROM)
		entry.Scale.Scale = POP_FROM
		TweenService:Create(entry.Slot, Theme.Tween.Slide, { Size = UDim2.new(1, 0, 0, height) }):Play()
		TweenService:Create(entry.Group, Theme.Tween.Slide, { Position = UDim2.new() }):Play()
		TweenService:Create(entry.Group, Theme.Tween.Fade, { GroupTransparency = 0 }):Play()
		TweenService:Create(entry.Scale, Theme.Tween.Slide, { Scale = 1 }):Play()
	end

	-- Measures the card once it's laid out, slides it in, and keeps the slot fitted if its text grows (×2).
	local function settle(entry: Entry)
		local function sync()
			if entry.Leaving then
				return
			end
			local height = math.floor(natural(entry) + 0.5)
			if height <= 0 or math.abs(height - entry.Height) < 2 then
				return -- not laid out yet, or a rounding wobble while it scales
			end
			entry.Height = height
			if not entry.Entered then
				enter(entry)
			else
				entry.Slot.Size = UDim2.new(1, 0, 0, height)
			end
		end
		entry.Group:GetPropertyChangedSignal("AbsoluteSize"):Connect(sync)
		task.defer(sync)
	end

	local function newEntry(kind: "Toast" | "Banner", layoutOrder: number): (Frame, CanvasGroup, UIScale)
		local slot = Instance.new("Frame")
		slot.Name = kind
		slot.LayoutOrder = layoutOrder
		slot.BackgroundTransparency = 1
		slot.Size = UDim2.fromScale(1, 0)
		slot.Parent = holder
		local group = Instance.new("CanvasGroup")
		group.Name = "Group"
		group.Size = UDim2.fromScale(1, 0)
		group.AutomaticSize = Enum.AutomaticSize.Y
		group.BackgroundTransparency = 1
		group.BorderSizePixel = 0
		group.GroupTransparency = 1
		local pad = Kit.pad(group, OUTLINE_ROOM)
		pad.PaddingBottom = UDim.new(0, SHADOW_ROOM)
		local scale = Instance.new("UIScale")
		scale.Parent = group
		group.Parent = slot
		return slot, group, scale
	end

	local function remove(entry: Entry, quick: boolean)
		if entry.Leaving then
			return
		end
		entry.Leaving = true
		local from = if entry.Kind == "Banner" then banners else toasts
		local index = table.find(from, entry)
		if index then
			table.remove(from, index)
		end
		if Hud.calm() or quick or not entry.Entered then
			entry.Slot:Destroy()
			return
		end
		local out = Theme.Tween.SlideOut
		TweenService:Create(entry.Group, out, {
			Position = UDim2.fromOffset(0, -entry.Height * 0.4),
			GroupTransparency = 1,
		}):Play()
		TweenService:Create(entry.Scale, out, { Scale = 0.92 }):Play()
		local close = TweenService:Create(entry.Slot, out, { Size = UDim2.fromScale(1, 0) })
		close.Completed:Once(function()
			entry.Slot:Destroy()
		end)
		close:Play()
	end

	local function schedule(entry: Entry, seconds: number)
		entry.Token += 1
		local token = entry.Token
		task.delay(seconds, function()
			if entry.Token == token then
				remove(entry, false)
			end
		end)
	end

	-- The same text again, or a banner updated: a springy bump instead of a new one.
	local function bump(entry: Entry)
		if Hud.calm() or not entry.Entered then
			return
		end
		entry.Scale.Scale = REPEAT_FROM
		TweenService:Create(entry.Scale, Theme.Tween.Bump, { Scale = 1 }):Play()
	end

	--------------------------------------------------------------------------------------------------------------
	-- Toasts
	--------------------------------------------------------------------------------------------------------------

	local function show(text: any)
		if type(text) ~= "string" or text == "" then
			return
		end
		if #text > MAX_CHARS then
			text = string.sub(text, 1, MAX_CHARS) .. "…"
		end
		local seconds = Kit.Juice.toastSeconds(text, BASE_SECONDS, SECONDS_PER_EXTRA_CHAR, MAX_SECONDS)

		-- The same message again: count it on the newest toast instead of stacking a copy.
		local newest = toasts[#toasts]
		if newest and newest.Text == text and not newest.Leaving then
			newest.Count += 1
			newest.Label.Text = text .. "  ×" .. newest.Count
			bump(newest)
			schedule(newest, seconds)
			Hud.sound("Toast", 0.6)
			return
		end

		while #toasts >= MAX_SHOWN do
			remove(toasts[1], true)
		end

		order += 1
		local slot, group, scale = newEntry("Toast", order)
		local card, label = toastCard(group, text)
		local entry: Entry = {
			Kind = "Toast",
			Id = "",
			Text = text,
			Count = 1,
			Slot = slot,
			Group = group,
			Scale = scale,
			Card = card,
			Tile = nil,
			Label = label,
			Icon = nil,
			Clock = nil,
			EndsAt = nil,
			UntilEnds = false,
			Token = 0,
			Leaving = false,
			Entered = false,
			Height = 0,
		}
		table.insert(toasts, entry)
		settle(entry)
		schedule(entry, seconds)
		Hud.sound("Toast")
	end

	ctx.on("Toast", show)

	--------------------------------------------------------------------------------------------------------------
	-- Banners
	--------------------------------------------------------------------------------------------------------------

	local ticking = false
	local function tickClocks()
		if ticking then
			return
		end
		ticking = true
		task.spawn(function()
			while true do
				local any = false
				local now = Workspace:GetServerTimeNow()
				for _, entry in table.clone(banners) do
					local endsAt = entry.EndsAt
					local clock = entry.Clock
					if endsAt and clock then
						any = true
						local left = endsAt - now
						clock.Text = Kit.Juice.clock(left)
						if left <= 0 and entry.UntilEnds then
							remove(entry, false) -- no Seconds: it lasted until EndsAt
						end
					end
				end
				if not any then
					break
				end
				task.wait(0.25)
			end
			ticking = false
		end)
	end

	local function findBanner(id: string): Entry?
		for _, entry in banners do
			if entry.Id == id and not entry.Leaving then
				return entry
			end
		end
		return nil
	end

	local function paintBanner(entry: Entry, spec: any)
		local tile = entry.Tile
		if tile then
			tile.BackgroundColor3 = if typeof(spec.Color) == "Color3" then spec.Color else Theme.Colors.Night
		end
		entry.Label.Text = spec.Text
		if entry.Icon then
			entry.Icon.Text = spec.Icon
		end
		local endsAt = if type(spec.EndsAt) == "number" and spec.EndsAt == spec.EndsAt then spec.EndsAt else nil
		entry.EndsAt = endsAt
		local clock = entry.Clock
		if clock then
			clock.Visible = endsAt ~= nil
			local room = TILE + Theme.Space.Step[3] + (if endsAt then CLOCK_WIDTH + Theme.Space.Step[3] else 0)
			entry.Label.Size = UDim2.new(1, -room, 0, 0)
			if endsAt then
				clock.Text = Kit.Juice.clock(endsAt - Workspace:GetServerTimeNow())
			end
		end
	end

	-- How long it stays: Seconds if given; else until EndsAt (the clock loop removes it); else a few seconds.
	local function plan(entry: Entry, spec: any)
		entry.Token += 1 -- cancels any old timer
		entry.UntilEnds = false
		if type(spec.Seconds) == "number" and spec.Seconds > 0 then
			schedule(entry, spec.Seconds)
		elseif entry.EndsAt then
			entry.UntilEnds = true -- tickClocks takes it down when the countdown ends
		else
			schedule(entry, BANNER_SECONDS)
		end
		if entry.EndsAt then
			tickClocks()
		end
	end

	local function banner(spec: any)
		if type(spec) ~= "table" or type(spec.Id) ~= "string" or spec.Id == "" then
			return
		end
		if spec.Seconds == 0 then
			local existing = findBanner(spec.Id)
			if existing then
				remove(existing, false)
			end
			return
		end
		if type(spec.Text) ~= "string" or spec.Text == "" or type(spec.Icon) ~= "string" then
			return
		end
		local existing = findBanner(spec.Id)
		if existing then
			existing.Text = spec.Text
			paintBanner(existing, spec)
			plan(existing, spec)
			bump(existing)
			return
		end

		while #banners >= MAX_BANNERS do
			remove(banners[1], true)
		end
		order += 1
		local slot, group, scale = newEntry("Banner", -10000 + order) -- banners above every toast
		local card, tile, text, icon, clock = bannerCard(group)
		local entry: Entry = {
			Kind = "Banner",
			Id = spec.Id,
			Text = spec.Text,
			Count = 1,
			Slot = slot,
			Group = group,
			Scale = scale,
			Card = card,
			Tile = tile,
			Label = text,
			Icon = icon,
			Clock = clock,
			EndsAt = nil,
			UntilEnds = false,
			Token = 0,
			Leaving = false,
			Entered = false,
			Height = 0,
		}
		table.insert(banners, entry)
		paintBanner(entry, spec)
		settle(entry)
		plan(entry, spec)
		Hud.sound("Whoosh", 0.5)
		task.delay(0.12, Hud.sound, "Sparkle", 0.7)
	end

	ctx.on("Banner", banner)
end

return Toasts
