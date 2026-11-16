--!strict
-- Small UI building blocks so every screen looks and feels the same (build plan Task 0).
-- Each maker takes an optional props table: any Instance property (Size, Position, AnchorPoint, Text,
-- LayoutOrder, ...), plus Parent (set last) and the extras noted below. Colours and sizes come from Theme.
--
--   Kit.screen(name, displayOrder): ScreenGui       ResetOnSpawn off, inside the safe area, in PlayerGui
--   Kit.panel(props?): Frame                       paper card; extra: Title = "🛒 Shop" adds a header label
--   Kit.label(props?): TextLabel
--   Kit.button(props?): TextButton                 press bounce; extra: Kind = "Primary" | "Secondary" | "Good"
--                                                  | "Danger" | "Quiet"; min 56 px tall
--   Kit.iconButton(props?): TextButton             big emoji square; extras: Icon, Caption, Kind; has a "Dot"
--   Kit.setDot(button, visible) · Kit.setEnabled(button, enabled)
--   Kit.corner(parent, radius?) · Kit.pad(parent, px?) · Kit.stroke(parent, colour?, px?)
--   Kit.list(parent, direction?, gap?) · Kit.popIn(gui) · Kit.popOut(gui, onDone?) · Kit.shade(colour, amount)
--   Kit.Clicked: Signal (button)                   fires on every Kit button press (Sounds plays a click)
--   Kit.reducedMotion(): boolean                   honour it in your own tweens too

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Signal"))
local Theme = require(script.Parent.Theme)

type Props = { [string]: any }

local Kit = {}

Kit.Clicked = Signal.new()

local KIND_COLORS: { [string]: Color3 } = {
	Primary = Theme.Colors.Primary,
	Secondary = Theme.Colors.Secondary,
	Good = Theme.Colors.Good,
	Danger = Theme.Colors.Danger,
	Quiet = Theme.Colors.Quiet,
	Card = Theme.Colors.Card,
}
local EXTRA_KEYS = { Parent = true, Kind = true, Title = true, Icon = true, Caption = true }

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
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
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
	Kit.stroke(panel)
	Kit.pad(panel)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(Theme.Size.PanelMaxWidth, Theme.Size.PanelMaxHeight)
	limit.Parent = panel
	apply(panel, props)
	if props and type(props.Title) == "string" then
		Kit.label({
			Name = "Title",
			Text = props.Title,
			TextSize = Theme.TextSize.Title,
			Size = UDim2.new(1, -Theme.Size.ButtonHeight - Theme.Size.Gap, 0, Theme.Size.ButtonHeight),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = panel,
		})
	end
	return finish(panel, props)
end

function Kit.button(props: Props?): TextButton
	local kind = if props and type(props.Kind) == "string" then props.Kind else "Primary"
	local color = KIND_COLORS[kind] or Theme.Colors.Primary
	local onColor = kind ~= "Quiet" and kind ~= "Card"

	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(180, Theme.Size.ButtonHeight)
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Theme.Font
	button.TextSize = Theme.TextSize.Body
	button.TextColor3 = if onColor then Theme.Colors.OnColor else Theme.Colors.Ink
	button.TextStrokeColor3 = Kit.shade(color, 0.45)
	button.TextStrokeTransparency = if onColor then 0.55 else 1
	button.Text = ""
	button:SetAttribute("KitColor", color)
	Kit.corner(button)
	Kit.stroke(button, Kit.shade(color, 0.25))
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(226, 226, 226))
	gradient.Parent = button
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
		Parent = button,
	})
	if caption then
		Kit.label({
			Name = "Caption",
			Text = caption,
			TextSize = Theme.TextSize.Small,
			TextColor3 = if kind == "Card" or kind == "Quiet" then Theme.Colors.Ink else Theme.Colors.OnColor,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.96),
			Size = UDim2.fromScale(1, 0.3),
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
	Kit.stroke(dot, Theme.Colors.OnColor, 2)
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

return Kit
