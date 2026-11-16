--!strict
-- Toasts and banners (build plan Task 6; depth update T6): short messages stacked at the top centre.
--   init(ctx)   listens to ctx.on("Toast", text) and ctx.on("Banner", spec: Types.BannerSpec)
-- Every toast in the game, from the server or from ctx.toast, arrives on the client bus as "Toast" (Main.client
-- wires that). Banners come from UI/BeltView (Golden Hour, Night Rush, an Epic+ nurse stepping on the belt; none of
-- them sends EndsAt, red line 3): `{ Id, Icon, Text (≤ 6 words), Color?, EndsAt? (server time: a countdown to it),
-- Seconds? }`. A
-- banner with the same Id replaces the old one in place (it bumps); Seconds = 0 hides it; with no Seconds it stays
-- until EndsAt (else a few seconds). Banners sit above the toasts; at most MAX_BANNERS at once.
-- The look is candy pop (memory-20261116-007): a chunky pill with a glossy top, a thick dark outline and white
-- outlined text. Toasts are purple; a banner is a wider ribbon in its Color (purple by default) with its icon in a
-- white bubble, a shine sweeping across it and the countdown in a dark chip. Motion: each one slides down into its
-- place with a springy overshoot while the others make room smoothly, and slides up and away when it goes. The same
-- toast text twice in a row bumps a "×2" counter instead of stacking a copy. At most MAX_SHOWN toasts; the oldest
-- goes first. Calm (Hud.calm()): no sliding or fading, they just appear and go. A soft blip plays for each new one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
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
local BANNER_HEIGHT = 60
local FILL = Theme.Colors.Purple
-- A CanvasGroup clips whatever is drawn outside it, so the card sits this far inside to keep its outline.
local OUTLINE_ROOM = 4
-- The HUD's wallet (top left) and clock (top right) are about this wide; toasts sit between them when they fit.
local SIDE_RESERVE = 214
local MIN_WIDTH = 240
local MAX_WIDTH = 440
-- Narrow screens: under the HUD's cash and stars pills (margin 12 + cash 52 + gap 8 + stars 56, plus a little).
local BELOW_WALLET_Y = 132
-- A new one starts this share of its height above its place, a little small, and springs into it.
local SLIDE_FROM = 0.7
local POP_FROM = 0.85
local REPEAT_FROM = 1.12

type Entry = {
	Kind: "Toast" | "Banner",
	Id: string, -- banners: their Id; toasts: ""
	Text: string,
	Count: number,
	Slot: Frame, -- in the stack, sized by hand so the others slide to make room
	Group: CanvasGroup, -- what fades and slides inside the slot
	Scale: UIScale,
	Card: Frame,
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

local function gloss(frame: Frame, inset: number)
	local shine = Instance.new("Frame")
	shine.Name = "Gloss"
	shine.ZIndex = 0
	shine.BackgroundColor3 = Palette.White
	shine.BackgroundTransparency = 0.5
	shine.BorderSizePixel = 0
	shine.Position = UDim2.fromOffset(inset, 3)
	shine.Size = UDim2.new(1, -inset * 2, 0, 14)
	Kit.corner(shine, 7)
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(0.15, 1)
	fade.Parent = shine
	shine.Parent = frame
end

-- A candy pill (fill, gradient, glossy top, thick dark outline).
local function pillCard(group: CanvasGroup, color: Color3): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Card"
	frame.Size = UDim2.fromScale(1, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Kit.lighten(color, 0.08)
	frame.BorderSizePixel = 0
	Kit.corner(frame, Theme.Size.CornerLarge)
	Kit.stroke(frame, Theme.Colors.Outline, Theme.Size.Stroke)
	Palette.candyGradient(frame)
	gloss(frame, 14)
	frame.Parent = group
	return frame
end

-- A toast's card: the pill holding the outlined text in its own padded holder (so the gloss stays on top).
local function toastCard(group: CanvasGroup, text: string): (Frame, TextLabel)
	local frame = pillCard(group, FILL)
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.fromScale(1, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	local pad = Kit.pad(body, 8)
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	body.Parent = frame

	local label = Kit.label({
		Name = "Text",
		Text = text,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Colors.OnColor,
		TextWrapped = true,
		Parent = body,
	})
	Kit.outline(label)
	return frame, label
end

-- A banner's card: a fixed-height ribbon, its icon in a white bubble on the left, the words, a countdown chip on
-- the right (shown only with EndsAt), and a shine that sweeps across now and then.
local function bannerCard(group: CanvasGroup, color: Color3): (Frame, TextLabel, TextLabel, TextLabel)
	local frame = pillCard(group, color)
	frame.AutomaticSize = Enum.AutomaticSize.None
	frame.Size = UDim2.new(1, 0, 0, BANNER_HEIGHT)
	local bubble = Instance.new("Frame")
	bubble.Name = "Bubble"
	bubble.AnchorPoint = Vector2.new(0, 0.5)
	bubble.Position = UDim2.new(0, 8, 0.5, 0)
	bubble.Size = UDim2.fromOffset(BANNER_HEIGHT - 16, BANNER_HEIGHT - 16)
	bubble.BackgroundColor3 = Theme.Colors.Paper
	bubble.BorderSizePixel = 0
	bubble.ZIndex = 2
	Kit.corner(bubble, (BANNER_HEIGHT - 16) // 2)
	Kit.stroke(bubble, Theme.Colors.Outline, Theme.Size.Stroke)
	bubble.Parent = frame
	local icon = Kit.label({
		Name = "Icon",
		Text = "",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.74, 0.74),
		ZIndex = 2,
		Parent = bubble,
	})
	local clock = Kit.label({
		Name = "Clock",
		Text = "",
		Outlined = true,
		TextScaled = true,
		TextWrapped = false,
		BackgroundColor3 = Theme.Colors.Outline,
		BackgroundTransparency = 0.45,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(70, 36),
		Visible = false,
		ZIndex = 2,
		Parent = frame,
	})
	Kit.corner(clock, 18)
	Kit.pad(clock, 4)
	local text = Kit.label({
		Name = "Text",
		Text = "",
		Outlined = true,
		TextScaled = true,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, BANNER_HEIGHT, 0.5, 0),
		Size = UDim2.new(1, -BANNER_HEIGHT - 12, 0, 32),
		ZIndex = 2,
		Parent = frame,
	})
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 30
	limit.MinTextSize = 14
	limit.Parent = text
	Kit.shine(frame)
	return frame, text, icon, clock
end

function Toasts.init(ctx: Types.Ctx)
	local gui = Kit.screen("Toasts", Theme.DisplayOrder.Toast)

	local holder = Instance.new("Frame")
	holder.Name = "Stack"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, Theme.Size.Margin)
	holder.Size = UDim2.fromOffset(MAX_WIDTH, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local list = Kit.list(holder, Enum.FillDirection.Vertical, 0) -- each one's OUTLINE_ROOM is the gap
	list.VerticalAlignment = Enum.VerticalAlignment.Top

	-- Between the wallet and the clock when there's room; on narrow screens, full width under the wallet.
	local function fit()
		local width = gui.AbsoluteSize.X
		local between = width - SIDE_RESERVE * 2
		if between >= MIN_WIDTH then
			holder.Size = UDim2.fromOffset(math.min(MAX_WIDTH, between), 0)
			holder.Position = UDim2.new(0.5, 0, 0, Theme.Size.Margin)
		else
			holder.Size = UDim2.fromOffset(math.min(MAX_WIDTH, width - Theme.Size.Margin * 2), 0)
			holder.Position = UDim2.new(0.5, 0, 0, BELOW_WALLET_Y)
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

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
		Kit.pad(group, OUTLINE_ROOM)
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
		local color: Color3 = if typeof(spec.Color) == "Color3" then spec.Color else FILL
		entry.Card.BackgroundColor3 = Kit.lighten(color, 0.08)
		entry.Label.Text = spec.Text
		if entry.Icon then
			entry.Icon.Text = spec.Icon
		end
		local endsAt = if type(spec.EndsAt) == "number" and spec.EndsAt == spec.EndsAt then spec.EndsAt else nil
		entry.EndsAt = endsAt
		local clock = entry.Clock
		if clock then
			clock.Visible = endsAt ~= nil
			entry.Label.Size = UDim2.new(1, -BANNER_HEIGHT - 12 - (if endsAt then 82 else 0), 0, 32)
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
		local card, text, icon, clock = bannerCard(group, FILL)
		local entry: Entry = {
			Kind = "Banner",
			Id = spec.Id,
			Text = spec.Text,
			Count = 1,
			Slot = slot,
			Group = group,
			Scale = scale,
			Card = card,
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
