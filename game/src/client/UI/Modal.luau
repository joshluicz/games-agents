--!strict
-- The one modal template (look build plan §B8; docs/research/2026-11-16-ux-cohesion-audit.md §3.2). A LIBRARY: it
-- has no init, and it requires only Kit and Theme (never Hud: Hud re-exports everything here, so no caller changed).
-- OWNER: T6. The shell was moved out of Hud by the look overhaul's Foundation; tabs, confirm and oddsPopup are the
-- Foundation's plain first versions, which T6 restyles (the names and signatures stay: T2, T5, T7 and T8 code
-- against them).
--
--   Modal.modal(ctx, spec): Modal        a panel or popup shell (= Hud.modal): a dim, the paper card with ONE navy
--                                        header (Theme.Colors.Header: spec.Accent is accepted and IGNORED), ✖, pop
--                                        in and out, one Panel open at a time, gamepad focus and ButtonB to close.
--                                        New in the overhaul: spec.HudMode ("Panel" for Layer Panel, "None" for a
--                                        Popup, unless given; "Game" for the mini-game) and spec.Meta (the header's
--                                        one meta chip: "📔 6%", "💰 726"; modal.setMeta(text) changes it, "" hides it)
--   Modal.isOpen(name?): boolean         a modal is open (that one, or any)
--   Modal.tabs(modal, tabs, onSelect): { select, Column, Content }
--                                        THE tab pattern: a left column of square tabs (fitTabs sizes them), each
--                                        painted by Kit.tab. tabs = { { Id, Icon, Caption, Stripe? } }. select(id)
--                                        paints the tabs and calls onSelect(id); the first tab starts selected
--                                        (without calling onSelect). Content is the body's space beside the column
--   Modal.confirm(ctx, spec, onYes)      a 420 x 360 Popup on the same shell. spec = { Title, Line, Yes, No?, Kind?,
--                                        Hold? }. "Not now" (spec.No) is the default focus; Hold > 0 makes Yes a
--                                        Kit.holdButton of that many seconds. Every confirm in the game goes
--                                        through Hud.confirm
--   Modal.oddsPopup(ctx, spec)           ONE odds popup for the belt (sign, hire card), the Agency and the Journal.
--                                        spec = { Title, Rows = { { Icon, Name, Percent } }, Notes? }. Every row
--                                        shows the word AND the number ("Rare 20%"), as Roblox's paid-random-item
--                                        guidance asks, even though these use in-game cash (CLAUDE.md red line 3)
--   Modal.fitTabs(column, tabs, gap)     square tabs sized to the column (56 to 76 px)
--   Modal.fitHeight(content, area, min?) scales a block down to fit a short screen (not below min, default 0.6)
--   Modal.Pure                           hudMode(layer, given) · confirm(spec) (the defaults) · percent(n) ·
--                                        oddsLine(row): tests load the PURE block on its own
-- Client bus: fires "ModalOpened" (name, hudMode) and "ModalClosed" (name, hudMode) (Hud hides its rails by the
-- mode; Tutorial pauses its nudge), and "Sound" (Whoosh on open, Close on close).
-- Every motion honours Kit.reducedMotion().

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Modal = {}

export type Layer = "Panel" | "Popup"
export type HudMode = Types.HudMode
export type ModalSpec = {
	Name: string,
	Title: string?, -- header text: an emoji and at most two words
	Accent: Color3?, -- IGNORED (every header is Theme.Colors.Header); kept so old callers compile
	Layer: Layer?, -- "Panel" (default): only one open at a time · "Popup": stacks above panels
	HudMode: HudMode?, -- what the HUD does while it's open: default "Panel" for a Panel, "None" for a Popup
	Meta: string?, -- the header's one meta chip ("💰 726"); nil or "" = none
	MaxSize: Vector2?, -- default Theme PanelMaxWidth x PanelMaxHeight
	Scale: Vector2?, -- share of the safe area, default 0.94 x 0.94
	CloseButton: boolean?, -- default true
	Dim: boolean?, -- default true; false leaves the world playable around the card
	DimCloses: boolean?, -- default true
	AutoFocus: boolean?, -- default true; false = never grab gamepad focus (popups that arrive on their own)
	OnOpen: (() -> ())?,
	OnClose: (() -> ())?,
}
export type Modal = {
	Name: string,
	Layer: Layer,
	HudMode: HudMode,
	Gui: ScreenGui,
	Root: Frame, -- what pops (holds the shadow and the panel)
	Panel: Frame, -- the paper card
	Body: Frame, -- the space under the header
	CloseButton: TextButton?,
	Focus: GuiObject?, -- what a gamepad selects on open (set it after building; default the ✖)
	open: () -> (),
	close: () -> (),
	toggle: () -> (),
	isOpen: () -> boolean,
	setMeta: (text: string?) -> (),
}
export type TabSpec = { Id: string, Icon: string, Caption: string, Stripe: Color3? }
export type Tabs = { select: (id: string) -> (), Column: Frame, Content: Frame }
export type ConfirmSpec = {
	Title: string,
	Line: string,
	Yes: string,
	No: string?,
	Kind: ("Primary" | "Destructive" | "Collect")?,
	Hold: number?,
}
export type OddsRow = { Icon: string, Name: string, Percent: number }
export type OddsSpec = { Title: string, Rows: { OddsRow }, Notes: { string }? }

-- PURE-BEGIN
-- No Roblox APIs: a Lune spec loads this block on its own.
local Pure = {}

Pure.CONFIRM_SIZE = { X = 420, Y = 360 }
Pure.ODDS_SIZE = { X = 420, Y = 560 }
Pure.NOT_NOW = "Not now"

-- What the HUD does while a modal of this layer is open, unless the spec says otherwise.
function Pure.hudMode(layer: string?, given: string?): string
	if given == "Panel" or given == "Game" or given == "None" then
		return given
	end
	return if layer == "Popup" then "None" else "Panel"
end

-- A confirm's defaults: "Not now" is always there and always the default focus; a hold is never negative.
function Pure.confirm(
	spec: any
): { Title: string, Line: string, Yes: string, No: string, Kind: string, Hold: number, Focus: string }
	local kind = if type(spec) == "table" then spec.Kind else nil
	local hold = if type(spec) == "table"
			and type(spec.Hold) == "number"
			and spec.Hold == spec.Hold
		then math.max(spec.Hold, 0)
		else 0
	local function text(value: any, fallback: string): string
		return if type(value) == "string" and value ~= "" then value else fallback
	end
	return {
		Title = text(type(spec) == "table" and spec.Title, "Sure?"),
		Line = text(type(spec) == "table" and spec.Line, ""),
		Yes = text(type(spec) == "table" and spec.Yes, "Yes"),
		No = text(type(spec) == "table" and spec.No, Pure.NOT_NOW),
		Kind = if kind == "Destructive" or kind == "Collect" then kind else "Primary",
		Hold = hold,
		Focus = "No",
	}
end

-- "20%", "4.5%", "0.5%": the number as it is, never rounded to a friendlier one.
function Pure.percent(n: any): string
	if type(n) ~= "number" or n ~= n then
		return "0%"
	end
	local text = string.format("%.2f", n)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text .. "%"
end

-- One odds row: the word and the number.
function Pure.oddsLine(row: any): string
	local name = if type(row) == "table" and type(row.Name) == "string" then row.Name else "?"
	return name .. " " .. Pure.percent(if type(row) == "table" then row.Percent else nil)
end
-- PURE-END

Modal.Pure = Pure

local SLIDE_FROM = 36 -- px below its place a panel starts as it pops in
local DIM_BLEED = 400 -- the dim reaches past the safe area so the whole screen darkens (decoration may bleed)
local CLOSE_ACTION = "ClinicCloseModal"

local function sound(ctx: Types.Ctx, name: string, volume: number?)
	ctx.fire("Sound", name, volume)
end

local function scaleNamed(gui: GuiObject, name: string): UIScale
	local existing = gui:FindFirstChild(name)
	if existing and existing:IsA("UIScale") then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = name
	scale.Parent = gui
	return scale
end

local function usesDirectionalFocus(): boolean
	local preferred = UserInputService.PreferredInput
	return preferred == Enum.PreferredInput.Gamepad or preferred == Enum.PreferredInput.MicroGamepad
end

------------------------------------------------------------------------------------------------------------------
-- Modals: a stack, so ButtonB and focus always belong to the top one
------------------------------------------------------------------------------------------------------------------

local stack: { Modal } = {}

function Modal.isOpen(name: string?): boolean
	for _, modal in stack do
		if name == nil or modal.Name == name then
			return true
		end
	end
	return false
end

local function firstButton(root: Instance): GuiObject?
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("GuiButton") and descendant.Selectable and descendant.Visible then
			return descendant
		end
	end
	return nil
end

local function focusTop()
	task.defer(function()
		local top = stack[#stack]
		if top and usesDirectionalFocus() then
			local target = top.Focus or top.CloseButton or firstButton(top.Panel)
			if target and target:IsDescendantOf(top.Gui) then
				GuiService.SelectedObject = target
			end
		end
	end)
end

local function syncCloseBinding()
	if #stack == 0 then
		ContextActionService:UnbindAction(CLOSE_ACTION)
		return
	end
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_, inputState: Enum.UserInputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		local top = stack[#stack]
		if top then
			top.close()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
end

function Modal.modal(ctx: Types.Ctx, spec: ModalSpec): Modal
	local layer: Layer = spec.Layer or "Panel"
	local hudMode = Pure.hudMode(layer, spec.HudMode) :: HudMode
	local gui = Kit.screen(
		"Modal_" .. spec.Name,
		if layer == "Popup" then Theme.DisplayOrder.Popup else Theme.DisplayOrder.Panel
	)
	gui.Enabled = false

	local dim: TextButton? = nil
	if spec.Dim ~= false then
		local shade = Instance.new("TextButton")
		shade.Name = "Dim"
		shade.Text = ""
		shade.AutoButtonColor = false
		shade.Selectable = false
		shade.BackgroundColor3 = Theme.Colors.Shade
		shade.BackgroundTransparency = 1
		shade.BorderSizePixel = 0
		shade.Position = UDim2.fromOffset(-DIM_BLEED, -DIM_BLEED)
		shade.Size = UDim2.new(1, DIM_BLEED * 2, 1, DIM_BLEED * 2)
		shade.Parent = gui
		dim = shade
	end

	local maxSize = spec.MaxSize or Vector2.new(Theme.Size.PanelMaxWidth, Theme.Size.PanelMaxHeight)
	local share = spec.Scale or Vector2.new(0.94, 0.94)
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(share.X, share.Y)
	root.BackgroundTransparency = 1
	root.Visible = false
	-- Keep gamepad focus inside the card while it's open.
	root.SelectionGroup = true
	root.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = maxSize
	limit.Parent = root
	root.Parent = gui

	-- The one shadow (Theme.Shadow).
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.Position = UDim2.fromOffset(Theme.Shadow.Offset.X, Theme.Shadow.Offset.Y)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.BackgroundColor3 = Theme.Shadow.Color
	shadow.BackgroundTransparency = Theme.Shadow.Transparency
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 0
	Kit.corner(shadow, Theme.Radius.Large)
	shadow.Parent = root

	-- Kit.panel's header is Theme.Colors.Header unless a colour is passed: none is, so every header is navy.
	local panel = Kit.panel({
		Name = "Panel",
		Title = spec.Title,
		AnchorPoint = Vector2.zero,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = root,
	})
	-- The Root carries the size limit, so the shadow and the card stay the same size.
	local panelLimit = panel:FindFirstChildOfClass("UISizeConstraint")
	if panelLimit then
		panelLimit:Destroy()
	end
	-- With a dim, taps on the card stop here so they never reach the dim behind it (which would close it).
	-- Without one, taps on the card's background fall through, so the thumbstick still works under it.
	panel.Active = dim ~= nil

	local closeButton: TextButton? = nil
	if spec.CloseButton ~= false then
		closeButton = Kit.button({
			Name = "Close",
			Kind = "Destructive",
			Text = "✖",
			TextSize = Theme.TextSize.Title,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(Theme.Size.ButtonHeight, Theme.Size.ButtonHeight),
			ZIndex = 2,
			Parent = panel,
		})
	end

	-- The header's one meta chip: white, ink text, left of the ✖. Hidden while it has no text.
	local closeRoom = if closeButton then Theme.Size.ButtonHeight + Theme.Space.Gap else 0
	local meta = Kit.label({
		Name = "Meta",
		Text = "",
		Font = Theme.DisplayFont,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Colors.Ink,
		TextWrapped = false,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.Plate,
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -closeRoom, 0, Theme.Size.ButtonHeight / 2),
		Size = UDim2.fromOffset(0, 40),
		Visible = false,
		ZIndex = 2,
		Parent = panel,
	})
	Kit.corner(meta, Theme.Radius.Small)
	Kit.stroke(meta, Theme.Colors.Stroke, Theme.Stroke.Fine)
	local metaPad = Instance.new("UIPadding")
	metaPad.PaddingLeft = UDim.new(0, Theme.Space.PadCard)
	metaPad.PaddingRight = UDim.new(0, Theme.Space.PadCard)
	metaPad.Parent = meta

	local header = if spec.Title or closeButton then Theme.Size.ButtonHeight + Theme.Size.Gap else 0
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, header)
	body.Size = UDim2.new(1, 0, 1, -header)
	body.BackgroundTransparency = 1
	body.Parent = panel

	local opened = false
	local dimTween: Tween? = nil
	local function fadeDim(target: number)
		local shade = dim
		if not shade then
			return
		end
		if dimTween then
			dimTween:Cancel()
		end
		if Kit.reducedMotion() then
			shade.BackgroundTransparency = target
			return
		end
		local tween = TweenService:Create(shade, Theme.Tween.Fade, { BackgroundTransparency = target })
		dimTween = tween
		tween:Play()
	end

	local modal = {
		Name = spec.Name,
		Layer = layer,
		HudMode = hudMode,
		Gui = gui,
		Root = root,
		Panel = panel,
		Body = body,
		CloseButton = closeButton,
		Focus = closeButton :: GuiObject?,
	} :: Modal

	function modal.setMeta(text: string?)
		local shown = type(text) == "string" and text ~= ""
		meta.Text = if shown then text :: string else ""
		meta.Visible = shown
	end
	modal.setMeta(spec.Meta)

	function modal.isOpen(): boolean
		return opened
	end

	function modal.close()
		if not opened then
			return
		end
		opened = false
		local index = table.find(stack, modal)
		if index then
			table.remove(stack, index)
		end
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(gui) then
			GuiService.SelectedObject = nil
		end
		fadeDim(1)
		Kit.popOut(root, function()
			if opened then
				root.Visible = true -- reopened while closing
			else
				gui.Enabled = false
			end
		end)
		syncCloseBinding()
		focusTop()
		sound(ctx, "Close")
		ctx.fire("ModalClosed", spec.Name, hudMode)
		if spec.OnClose then
			task.spawn(spec.OnClose)
		end
	end

	function modal.open()
		if opened then
			return
		end
		if layer == "Panel" then
			for _, other in table.clone(stack) do
				if other ~= modal and other.Layer == "Panel" then
					other.close()
				end
			end
		end
		opened = true
		table.insert(stack, modal)
		gui.Enabled = true
		fadeDim(Theme.Transparency.Dim)
		Kit.popIn(root)
		-- ... and slides up into place as it pops (calm: just there).
		if Kit.reducedMotion() then
			root.Position = UDim2.fromScale(0.5, 0.5)
		else
			root.Position = UDim2.new(0.5, 0, 0.5, SLIDE_FROM)
			TweenService:Create(root, Theme.Tween.Slide, { Position = UDim2.fromScale(0.5, 0.5) }):Play()
		end
		syncCloseBinding()
		if spec.AutoFocus ~= false then
			focusTop()
		end
		sound(ctx, "Whoosh", 0.7)
		ctx.fire("ModalOpened", spec.Name, hudMode)
		if spec.OnOpen then
			task.spawn(spec.OnOpen)
		end
	end

	function modal.toggle()
		if opened then
			modal.close()
		else
			modal.open()
		end
	end

	if closeButton then
		closeButton.Activated:Connect(function()
			modal.close()
		end)
	end
	if dim and spec.DimCloses ~= false then
		dim.Activated:Connect(function()
			modal.close()
		end)
	end
	return modal
end

------------------------------------------------------------------------------------------------------------------
-- Fitting
------------------------------------------------------------------------------------------------------------------

-- Square tab buttons down a column: as big as the column's height allows, between 56 (the tap minimum) and 76.
-- A column taller than that scrolls if it's a ScrollingFrame.
function Modal.fitTabs(column: GuiObject, tabs: { GuiObject }, gap: number)
	local function fit()
		local height = column.AbsoluteSize.Y
		if height <= 0 or #tabs == 0 then
			return
		end
		local side =
			math.clamp(math.floor((height - gap * (#tabs - 1)) / #tabs), Theme.Size.ButtonHeight, Theme.Size.IconButton)
		for _, tab in tabs do
			tab.Size = UDim2.fromOffset(side, side)
		end
	end
	column:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
end

-- Scales a block of content down (never up) so it fits the height it's given, but never below `minScale` (0.6
-- unless given). The content should have AnchorPoint (0.5, 0), a scale width and AutomaticSize Y.
function Modal.fitHeight(content: GuiObject, area: GuiObject, minScale: number?)
	local floor = math.clamp(minScale or 0.6, 0.3, 1)
	local scale = scaleNamed(content, "FitScale")
	-- Changing the scale changes content.AbsoluteSize, which fires this again: the guard and the deferred
	-- re-check stop that loop, and tiny changes are ignored so rounding can't make it flicker.
	local busy = false
	local queued = false
	local function fit()
		if busy then
			return
		end
		busy = true
		local needed = content.AbsoluteSize.Y / math.max(scale.Scale, 0.01)
		local available = area.AbsoluteSize.Y
		if needed > 0 and available > 0 then
			local target = math.clamp(available / needed, floor, 1)
			if math.abs(target - scale.Scale) > 0.01 then
				scale.Scale = target
			end
		end
		busy = false
	end
	local function request()
		if not queued then
			queued = true
			task.defer(function()
				queued = false
				fit()
			end)
		end
	end
	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(request)
	area:GetPropertyChangedSignal("AbsoluteSize"):Connect(request)
	fit()
end

------------------------------------------------------------------------------------------------------------------
-- THE tab pattern (first version: T6 restyles it)
------------------------------------------------------------------------------------------------------------------

function Modal.tabs(modal: Modal, tabs: { TabSpec }, onSelect: (id: string) -> ()): Tabs
	local gap = Theme.Space.Gap
	local columnWidth = Theme.Size.IconButton
	local column = Instance.new("Frame")
	column.Name = "Tabs"
	column.BackgroundTransparency = 1
	column.Size = UDim2.new(0, columnWidth, 1, 0)
	Kit.list(column, Enum.FillDirection.Vertical, gap)
	column.Parent = modal.Body

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(columnWidth + gap, 0)
	content.Size = UDim2.new(1, -(columnWidth + gap), 1, 0)
	content.Parent = modal.Body

	local buttons: { [string]: TextButton } = {}
	local stripes: { [string]: Color3? } = {}
	local ordered: { GuiObject } = {}
	local selected: string? = nil

	local function paint()
		for id, button in buttons do
			Kit.tab(button, id == selected, stripes[id])
		end
	end

	local function choose(id: string)
		if not buttons[id] then
			return
		end
		selected = id
		paint()
		onSelect(id)
	end

	for index, tab in tabs do
		local button = Kit.iconButton({
			Name = "Tab_" .. tab.Id,
			Kind = "Quiet",
			Icon = tab.Icon,
			Caption = tab.Caption,
			LayoutOrder = index,
			Parent = column,
		})
		local caption = button:FindFirstChild("Caption")
		if caption and (caption:IsA("TextLabel") or caption:IsA("TextButton")) then
			caption.TextScaled = true
			Kit.textLimit(caption, Theme.TextSize.Caption)
		end
		buttons[tab.Id] = button
		stripes[tab.Id] = tab.Stripe
		table.insert(ordered, button)
		button.Activated:Connect(function()
			choose(tab.Id)
		end)
	end
	Modal.fitTabs(column, ordered, gap)

	if tabs[1] then
		selected = tabs[1].Id
	end
	paint()
	return { select = choose, Column = column, Content = content }
end

------------------------------------------------------------------------------------------------------------------
-- The one confirm and the one odds popup (first versions: T6 restyles them)
------------------------------------------------------------------------------------------------------------------

-- A popup made for one question: it removes itself once it has closed.
local function oneShot(ctx: Types.Ctx, name: string, title: string, size: { X: number, Y: number }): Modal
	local modal: Modal
	modal = Modal.modal(ctx, {
		Name = name,
		Title = title,
		Layer = "Popup",
		MaxSize = Vector2.new(size.X, size.Y),
		OnClose = function()
			task.delay(1, function()
				if not modal.isOpen() then
					modal.Gui:Destroy()
				end
			end)
		end,
	})
	return modal
end

function Modal.confirm(ctx: Types.Ctx, spec: ConfirmSpec, onYes: () -> ())
	local c = Pure.confirm(spec)
	local modal = oneShot(ctx, "Confirm", c.Title, Pure.CONFIRM_SIZE)
	local gap = Theme.Space.Gap
	local row = Theme.Size.ButtonHeight

	Kit.label({
		Name = "Line",
		Text = c.Line,
		TextSize = Theme.TextSize.Body,
		TextScaled = false,
		Size = UDim2.new(1, 0, 1, -(row + gap)),
		Parent = modal.Body,
	})

	local no = Kit.button({
		Name = "No",
		Kind = "Secondary",
		Text = c.No,
		TextSize = Theme.TextSize.Button,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(0.5, -gap / 2, 0, row),
		Parent = modal.Body,
	})
	local yes = Kit.button({
		Name = "Yes",
		Kind = c.Kind,
		Text = c.Yes,
		TextSize = Theme.TextSize.Button,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(0.5, -gap / 2, 0, row),
		Parent = modal.Body,
	})
	for _, button in { no, yes } do
		button.TextScaled = true
		Kit.textLimit(button, Theme.TextSize.Button)
	end

	local answered = false
	local function accept()
		if answered then
			return
		end
		answered = true
		modal.close()
		onYes()
	end
	no.Activated:Connect(function()
		modal.close()
	end)
	if c.Hold > 0 then
		Kit.holdButton(yes, c.Hold, accept)
	else
		yes.Activated:Connect(accept)
	end

	modal.Focus = no -- "Not now" is always the default
	modal.open()
end

function Modal.oddsPopup(ctx: Types.Ctx, spec: OddsSpec)
	local modal = oneShot(ctx, "Odds", spec.Title, Pure.ODDS_SIZE)
	local gap = Theme.Space.Gap
	local rowHeight = 44

	local list = Instance.new("ScrollingFrame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.fromScale(1, 1)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	Kit.list(list, Enum.FillDirection.Vertical, gap)
	list.Parent = modal.Body

	for index, entry in spec.Rows do
		local row = Instance.new("Frame")
		row.Name = "Row_" .. index
		row.LayoutOrder = index
		row.Size = UDim2.new(1, -gap, 0, rowHeight)
		row.BackgroundColor3 = Theme.Colors.Card
		row.BorderSizePixel = 0
		Kit.corner(row, Theme.Radius.Small)
		Kit.stroke(row, Theme.Colors.CardLine, Theme.Stroke.Fine)
		row.Parent = list
		Kit.label({
			Name = "Name",
			Text = entry.Icon .. " " .. entry.Name,
			TextSize = Theme.TextSize.Body,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(Theme.Space.PadCard, 0),
			Size = UDim2.new(0.62, -Theme.Space.PadCard, 1, 0),
			Parent = row,
		})
		Kit.label({
			Name = "Percent",
			Text = Pure.percent(entry.Percent),
			Font = Theme.DisplayFont,
			TextSize = Theme.TextSize.Body,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -Theme.Space.PadCard, 0, 0),
			Size = UDim2.new(0.38, -Theme.Space.PadCard, 1, 0),
			Parent = row,
		})
	end
	for index, note in spec.Notes or {} do
		Kit.label({
			Name = "Note_" .. index,
			Text = note,
			TextSize = Theme.TextSize.Caption,
			TextColor3 = Theme.Colors.InkSoft,
			LayoutOrder = #spec.Rows + index,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, -gap, 0, 0),
			Parent = list,
		})
	end

	modal.open()
end

return Modal
