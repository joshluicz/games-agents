--!strict
-- Small UI building blocks so every screen looks and feels the same (build plan Task 0).
-- Each maker takes an optional props table: any Instance property (Size, Position, AnchorPoint, Text,
-- LayoutOrder, ...), plus Parent (set last) and the extras noted below. Colours and sizes come from Theme.
--
--   Kit.screen(name, displayOrder): ScreenGui       ResetOnSpawn off, inside the safe area, in PlayerGui
--   Kit.panel(props?): Frame                       white card, thick outline; extras: Title = "🛒 Shop" adds a
--                                                  coloured header band with an outlined title, Accent = Color3
--                                                  (the band's colour, default Secondary)
--   Kit.label(props?): TextLabel                   extra: Outlined = true -> display font, white text, dark stroke
--   Kit.button(props?): TextButton                 glossy candy button with an outline and press bounce; extra:
--                                                  Kind = "Primary" | "Secondary" | "Good" | "Danger" | "Pink" |
--                                                  "Purple" | "Cyan" | "Cash" | "Quiet" | "Card"; min 56 px tall
--   Kit.iconButton(props?): TextButton             big emoji square; extras: Icon, Caption, Kind; has a "Dot"
--   Kit.setDot(button, visible) · Kit.setEnabled(button, enabled)
--   Kit.corner(parent, radius?) · Kit.pad(parent, px?) · Kit.stroke(parent, colour?, px?)
--   Kit.outline(text, px?): UIStroke              outlined text (a dark stroke around the letters)
--   Kit.list(parent, direction?, gap?) · Kit.popIn(gui) · Kit.popOut(gui, onDone?)
--   Kit.shade(colour, amount) · Kit.lighten(colour, amount)
--   Kit.shine(button): () -> ()                     a white shine sweeps across every few seconds (calls to
--                                                  action only); returns stop. Paused with reduced motion.
--   Kit.rays(parent, colour?): Frame               a slowly turning sunburst behind a reward (ZIndex 0, behind
--                                                  the parent's other children). Still with reduced motion.
--   Kit.bump(gui)                                  a quick springy grow-and-settle (a number changed, a reward)
--   Kit.gloss(gui, inset?): Frame                  the white top highlight Kit buttons have, for your own chips
-- ZIndex 0 is the decoration layer inside a Kit button or panel (Gloss, Shine, Header, Rays): it draws over the
-- parent's own fill but under every other child, so give your own children ZIndex 1 or more (the default).
--   Kit.Clicked: Signal (button)                   fires on every Kit button press (Sounds plays a click)
--   Kit.reducedMotion(): boolean                   honour it in your own tweens too

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Palette = require(Shared:WaitForChild("Palette"))
local Signal = require(Shared:WaitForChild("Signal"))
local Theme = require(script.Parent.Theme)

type Props = { [string]: any }

local Kit = {}

Kit.Clicked = Signal.new()

local KIND_COLORS: { [string]: Color3 } = {
	Primary = Theme.Colors.Primary,
	Secondary = Theme.Colors.Secondary,
	Good = Theme.Colors.Good,
	Danger = Theme.Colors.Danger,
	Pink = Theme.Colors.Pink,
	Purple = Theme.Colors.Purple,
	Cyan = Theme.Colors.Cyan,
	Cash = Theme.Colors.Cash,
	Quiet = Theme.Colors.Quiet,
	Card = Theme.Colors.Card,
}
-- Light kinds carry dark, un-outlined text; every other kind carries white outlined text.
local LIGHT_KINDS = { Quiet = true, Card = true }
local EXTRA_KEYS =
	{ Parent = true, Kind = true, Title = true, Icon = true, Caption = true, Accent = true, Outlined = true }

local function apply(instance: Instance, props: Props?)
	if not props then
		return
	end
	for key, value in props do
		if not EXTRA_KEYS[key] then
			(instance :: any)[key] = value
		end
	end
end

local function finish<T>(instance: T, props: Props?): T
	if props and props.Parent then
		(instance :: any).Parent = props.Parent
	end
	return instance
end

-- The device's Reduced Motion setting, or the in-game ✨/💤 calm toggle (Feel/Atmosphere sets the client-only
-- LocalPlayer attribute ReduceEffects).
function Kit.reducedMotion(): boolean
	local player = Players.LocalPlayer
	if player and player:GetAttribute("ReduceEffects") == true then
		return true
	end
	local ok, reduced = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	return ok and reduced == true
end

function Kit.shade(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

function Kit.lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

function Kit.corner(parent: Instance, radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or Theme.Size.Corner)
	corner.Parent = parent
	return corner
end

function Kit.pad(parent: Instance, px: number?): UIPadding
	local pad = Instance.new("UIPadding")
	local amount = UDim.new(0, px or Theme.Size.Pad)
	pad.PaddingTop = amount
	pad.PaddingBottom = amount
	pad.PaddingLeft = amount
	pad.PaddingRight = amount
	pad.Parent = parent
	return pad
end

function Kit.stroke(parent: Instance, color: Color3?, px: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.Colors.Stroke
	stroke.Thickness = px or Theme.Size.Stroke
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function Kit.outline(text: GuiObject, px: number?): UIStroke
	return Palette.outlineText(text, px or Theme.Size.TextStroke)
end

function Kit.list(parent: Instance, direction: Enum.FillDirection?, gap: number?): UIListLayout
	local list = Instance.new("UIListLayout")
	list.FillDirection = direction or Enum.FillDirection.Vertical
	list.Padding = UDim.new(0, gap or Theme.Size.Gap)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = parent
	return list
end

local function scaleOf(gui: GuiObject): UIScale
	local existing = gui:FindFirstChild("KitScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = "KitScale"
	scale.Parent = gui
	return scale
end

-- A quick squash on press and a springy release (game-feel: small tier, no shake).
local function addBounce(button: GuiButton)
	local scale = scaleOf(button)
	local tween: Tween? = nil
	local function to(target: number, info: TweenInfo)
		if tween then
			tween:Cancel()
		end
		if Kit.reducedMotion() then
			scale.Scale = 1
			return
		end
		local created = TweenService:Create(scale, info, { Scale = target })
		tween = created
		created:Play()
	end
	button.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if button.Interactable and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) then
			to(Theme.PressScale, Theme.Tween.Press)
		end
	end)
	button.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			to(1, Theme.Tween.Release)
		end
	end)
	button.MouseLeave:Connect(function()
		to(1, Theme.Tween.Release)
	end)
	button.Activated:Connect(function()
		Kit.Clicked:Fire(button)
	end)
end

function Kit.screen(name: string, displayOrder: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = displayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

function Kit.label(props: Props?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(200, 32)
	label.Font = Theme.Font
	label.TextSize = Theme.TextSize.Body
	label.TextColor3 = Theme.Colors.Ink
	label.TextWrapped = true
	if props and props.Outlined == true then
		label.Font = Theme.DisplayFont
		label.TextColor3 = Theme.Colors.OnColor
		Kit.outline(label)
	end
	apply(label, props)
	return finish(label, props)
end

function Kit.panel(props: Props?): Frame
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.92, 0.8)
	panel.BackgroundColor3 = Theme.Colors.Paper
	panel.BorderSizePixel = 0
	Kit.corner(panel, Theme.Size.CornerLarge)
	Kit.stroke(panel, Theme.Colors.Outline, Theme.Size.StrokeLarge)
	Kit.pad(panel)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Theme.Colors.Paper, Theme.Colors.PaperEdge)
	gradient.Parent = panel
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(Theme.Size.PanelMaxWidth, Theme.Size.PanelMaxHeight)
	limit.Parent = panel
	apply(panel, props)
	if props and type(props.Title) == "string" then
		local accent: Color3 = if typeof(props.Accent) == "Color3" then props.Accent else Theme.Colors.Secondary
		-- The header band runs edge to edge (out through the panel's padding) behind the title and close button.
		local pad = Theme.Size.Pad
		local header = Instance.new("Frame")
		header.Name = "Header"
		header.ZIndex = 0
		header.Position = UDim2.fromOffset(-pad, -pad)
		header.Size = UDim2.new(1, pad * 2, 0, Theme.Size.ButtonHeight + pad + 4)
		header.BackgroundColor3 = Kit.lighten(accent, 0.08)
		header.BorderSizePixel = 0
		Kit.corner(header, Theme.Size.CornerLarge)
		Palette.candyGradient(header)
		local foot = Instance.new("Frame") -- squares off the band's bottom corners
		foot.Name = "Foot"
		foot.ZIndex = 0
		foot.AnchorPoint = Vector2.new(0, 1)
		foot.Position = UDim2.fromScale(0, 1)
		foot.Size = UDim2.new(1, 0, 0, Theme.Size.CornerLarge)
		foot.BackgroundColor3 = Kit.shade(accent, 0.06)
		foot.BorderSizePixel = 0
		foot.Parent = header
		local line = Instance.new("Frame") -- the outline under the band
		line.Name = "Line"
		line.ZIndex = 0
		line.AnchorPoint = Vector2.new(0, 1)
		line.Position = UDim2.fromScale(0, 1)
		line.Size = UDim2.new(1, 0, 0, Theme.Size.StrokeLarge)
		line.BackgroundColor3 = Theme.Colors.Outline
		line.BorderSizePixel = 0
		line.Parent = header
		header.Parent = panel
		Kit.label({
			Name = "Title",
			Text = props.Title,
			TextSize = Theme.TextSize.Title,
			Outlined = true,
			Size = UDim2.new(1, -Theme.Size.ButtonHeight - Theme.Size.Gap, 0, Theme.Size.ButtonHeight),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = panel,
		})
	end
	return finish(panel, props)
end

-- The gloss: a soft white highlight across the top of a candy button (decoration layer, ZIndex 0).
-- Also exported as Kit.gloss(gui, inset?) for chips and pills that aren't Kit buttons.
local function addGloss(button: GuiObject, inset: number?): Frame
	local side = inset or 6
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.ZIndex = 0
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 0.5
	gloss.BorderSizePixel = 0
	gloss.Position = UDim2.fromOffset(side, 4)
	gloss.Size = UDim2.new(1, -side * 2, 0.42, 0)
	Kit.corner(gloss, Theme.Size.Corner - 5)
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(0.15, 1)
	fade.Parent = gloss
	gloss.Parent = button
	return gloss
end
Kit.gloss = addGloss

function Kit.button(props: Props?): TextButton
	local kind = if props and type(props.Kind) == "string" then props.Kind else "Primary"
	local color = KIND_COLORS[kind] or Theme.Colors.Primary
	local light = LIGHT_KINDS[kind] == true
	local fill = if light then color else Kit.lighten(color, 0.08)

	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(180, Theme.Size.ButtonHeight)
	button.BackgroundColor3 = fill
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = if light then Theme.Font else Theme.DisplayFont
	button.TextSize = Theme.TextSize.Body
	button.TextColor3 = if light then Theme.Colors.Ink else Theme.Colors.OnColor
	button.TextStrokeTransparency = 1
	button.Text = ""
	button:SetAttribute("KitColor", fill)
	Kit.corner(button)
	Kit.stroke(button, Theme.Colors.Outline, Theme.Size.Stroke)
	if not light then
		Kit.outline(button)
	end
	Palette.candyGradient(button)
	addGloss(button)
	local minimum = Instance.new("UISizeConstraint")
	minimum.MinSize = Vector2.new(Theme.Size.ButtonHeight, Theme.Size.ButtonHeight)
	minimum.Parent = button
	addBounce(button)
	apply(button, props)
	return finish(button, props)
end

function Kit.iconButton(props: Props?): TextButton
	local kind = if props and type(props.Kind) == "string" then props.Kind else "Card"
	local button = Kit.button({ Kind = kind, Size = UDim2.fromOffset(Theme.Size.IconButton, Theme.Size.IconButton) })
	local caption = if props and type(props.Caption) == "string" then props.Caption else nil

	Kit.label({
		Name = "Icon",
		Text = if props and type(props.Icon) == "string" then props.Icon else "",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.08),
		Size = UDim2.fromScale(0.7, if caption then 0.6 else 0.84),
		ZIndex = 2,
		Parent = button,
	})
	if caption then
		local light = LIGHT_KINDS[kind] == true
		Kit.label({
			Name = "Caption",
			Text = caption,
			TextSize = Theme.TextSize.Small,
			Outlined = not light,
			TextColor3 = if light then Theme.Colors.Ink else Theme.Colors.OnColor,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.97),
			Size = UDim2.fromScale(1, 0.3),
			ZIndex = 2,
			Parent = button,
		})
	end

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.92, 0.08)
	dot.Size = UDim2.fromOffset(Theme.Size.Dot, Theme.Size.Dot)
	dot.BackgroundColor3 = Theme.Colors.Dot
	dot.BorderSizePixel = 0
	dot.Visible = false
	dot.ZIndex = 3
	Kit.corner(dot, Theme.Size.Dot)
	Kit.stroke(dot, Theme.Colors.Outline, 2.5)
	dot.Parent = button

	apply(button, props)
	return finish(button, props)
end

function Kit.setDot(button: GuiObject, visible: boolean)
	local dot = button:FindFirstChild("Dot")
	if dot and dot:IsA("GuiObject") then
		dot.Visible = visible
	end
end

function Kit.setEnabled(button: GuiButton, enabled: boolean)
	button.Interactable = enabled
	local color = button:GetAttribute("KitColor")
	button.BackgroundColor3 = if enabled and typeof(color) == "Color3" then color else Theme.Colors.Disabled
	local shine = button:FindFirstChild("Shine")
	if shine and shine:IsA("GuiObject") then
		shine.Visible = enabled
	end
end

function Kit.popIn(gui: GuiObject)
	local scale = scaleOf(gui)
	gui.Visible = true
	if Kit.reducedMotion() then
		scale.Scale = 1
		return
	end
	scale.Scale = 0.85
	TweenService:Create(scale, Theme.Tween.PopIn, { Scale = 1 }):Play()
end

function Kit.popOut(gui: GuiObject, onDone: (() -> ())?)
	local scale = scaleOf(gui)
	local function done()
		gui.Visible = false
		scale.Scale = 1
		if onDone then
			onDone()
		end
	end
	if Kit.reducedMotion() then
		done()
		return
	end
	local tween = TweenService:Create(scale, Theme.Tween.PopOut, { Scale = 0.85 })
	tween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then
			done()
		end
	end)
	tween:Play()
end

-- True when gui is actually on screen: it and every GuiObject above it are Visible, and its ScreenGui is enabled.
-- The shine and rays loops use it to sleep while their panel is closed.
local function isShown(gui: GuiObject): boolean
	local node: Instance? = gui
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end
		elseif node:IsA("LayerCollector") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

-- A quick springy grow-and-settle: a number changed, a reward landed.
function Kit.bump(gui: GuiObject)
	if Kit.reducedMotion() then
		return
	end
	local scale = scaleOf(gui)
	scale.Scale = 1.18
	TweenService:Create(scale, Theme.Tween.Bump, { Scale = 1 }):Play()
end

-- A white shine that sweeps across a call-to-action button every Theme.ShineEvery seconds. Returns stop.
-- The shine is a rounded frame the size of the button, so the sweep never spills past the corners.
function Kit.shine(button: GuiObject): () -> ()
	local existing = button:FindFirstChild("Shine")
	if existing then
		existing:Destroy()
	end
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.ZIndex = 0
	shine.Size = UDim2.fromScale(1, 1)
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BorderSizePixel = 0
	Kit.corner(shine, Theme.Size.Corner)
	local band = Instance.new("UIGradient")
	band.Rotation = 20
	band.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.42, 1),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(0.58, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	band.Offset = Vector2.new(-1, 0)
	band.Parent = shine
	shine.Parent = button

	local running = true
	task.spawn(function()
		while running and shine.Parent do
			task.wait(Theme.ShineEvery)
			if not running or not shine.Parent then
				break
			end
			if isShown(shine) and not Kit.reducedMotion() then
				band.Offset = Vector2.new(-1, 0)
				TweenService:Create(band, Theme.Tween.Shine, { Offset = Vector2.new(1, 0) }):Play()
			end
		end
	end)
	return function()
		running = false
		shine:Destroy()
	end
end

-- A slowly turning sunburst behind a reward: square, centred on its parent and 1.6x its size, ZIndex 0 so it
-- sits behind the parent's other children. Still (but shown) with reduced motion.
function Kit.rays(parent: GuiObject, color: Color3?): Frame
	local rays = Instance.new("Frame")
	rays.Name = "Rays"
	rays.ZIndex = 0
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.5)
	rays.Size = UDim2.fromScale(1.6, 1.6)
	rays.BackgroundTransparency = 1
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = rays
	local count = 12
	for i = 1, count do
		local ray = Instance.new("Frame")
		ray.Name = "Ray"
		ray.ZIndex = 0
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.fromScale(0.13, 1)
		ray.Rotation = (i - 1) * (180 / count)
		ray.BackgroundColor3 = color or Theme.Colors.Cash
		ray.BorderSizePixel = 0
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = ray
		ray.Parent = rays
	end
	rays.Parent = parent
	task.spawn(function()
		while rays.Parent do
			if not isShown(rays) or Kit.reducedMotion() then
				task.wait(0.5) -- closed panel or calm mode: check again in a moment
			else
				local dt = task.wait()
				rays.Rotation = (rays.Rotation + dt * 360 / Theme.RaysSpin) % 360
			end
		end
	end)
	return rays
end

return Kit
