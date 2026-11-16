--!strict
-- The one modal template (look build plan §B8; docs/research/2026-11-16-ux-cohesion-audit.md §3.2). A LIBRARY: it
-- has no init, and it requires only Kit and Theme (never Hud: Hud re-exports everything here, so no caller changed).
-- OWNER: T6. The names and signatures are the Foundation's (T2, T5, T7 and T8 code against them).
--
--   Modal.modal(ctx, spec): Modal        a panel or popup shell (= Hud.modal), THE template:
--                                          header  one Kit.HEADER (64) px NAVY band (Theme.Colors.Header) with the
--                                                  icon and a title of at most two words (white display text, the
--                                                  Title stroke), ONE meta chip (white, ink: "📔 6%", "💰 726") and
--                                                  the red ✖ at 56 x 56: the only red on the chrome. spec.Accent is
--                                                  accepted and IGNORED: every header is navy
--                                          body    flat white paper (no gradient); panels put tinted cards on it
--                                          shadow  the one Theme.Shadow under the card
--                                        A dim behind it, pop in and out, one Panel open at a time, gamepad focus and
--                                        ButtonB to close. spec.HudMode ("Panel" for Layer Panel, "None" for a Popup,
--                                        unless given; "Game" for the mini-game) and spec.Meta (the chip's text;
--                                        modal.setMeta(text) changes it, "" hides it). A modal with neither a ✖ nor a
--                                        dim that closes (the mini-game) is never closed by ButtonB, and its dim is a
--                                        plain Frame that takes no input (the thumbstick still works under it). A
--                                        "Game" modal stays up when a Panel opens (the Panel opens under it)
--   modal.setTitle(text)                 changes the header's title (the mini-game's game name)
--   modal.Header · modal.Title · modal.Meta   the header band, its title label and the meta chip (for a caller's own
--                                        chip in the header, or a count-up on the meta)
--   Modal.isOpen(name?): boolean         a modal is open (that one, or any)
--   Modal.tabs(modal, tabs, onSelect): { select, Column, Content, Buttons }
--                                        THE tab pattern: a left column of tabs (fitTabs sizes them, the column
--                                        scrolls when they don't fit a short phone), each a Kit.iconButton painted
--                                        by Kit.tab. tabs = { { Id, Icon, Caption, Stripe? } }. select(id) paints the
--                                        tabs and calls onSelect(id); the first tab starts selected (without calling
--                                        onSelect). Content is the body's space beside the column; Buttons[id] is
--                                        each tab button (for Kit.setDot and pointers)
--   Modal.confirm(ctx, spec, onYes)      a 420 x 360 Popup on the same shell. spec = { Title, Line, Yes, No?, Kind?,
--                                        Hold? }. "Not now" (spec.No) is the default focus; Hold > 0 makes Yes a
--                                        Kit.holdButton of that many seconds. Every confirm in the game goes
--                                        through Hud.confirm
--   Modal.oddsPopup(ctx, spec)           ONE odds popup for the belt (sign, hire card), the Agency and the Journal.
--                                        spec = { Title, Rows = { { Icon, Name, Percent } }, Notes? }. Every row
--                                        shows the word AND the number ("Rare 20%"), as Roblox's paid-random-item
--                                        guidance asks, even though these use in-game cash (CLAUDE.md red line 3)
--   Modal.fitTabs(column, tabs, gap, width?)   tabs sized to the column's height (56 to 76 px tall; square unless
--                                        a width is given)
--   Modal.fitHeight(content, area, min?) scales a block down to fit a short screen (not below min, default 0.6)
--   Modal.Pure                           hudMode(layer, given) · confirm(spec) (the defaults) · percent(n) ·
--                                        oddsLine(row) · closable(spec) · TAB_WIDTH: tests load the PURE block on its own
-- Client bus: fires "ModalOpened" (name, hudMode) and "ModalClosed" (name, hudMode) (Hud hides its rails by the
-- mode; Tutorial pauses its nudge), and "Sound" (Whoosh on open, Close on close).
-- Every motion honours Kit.reducedMotion(). Radii from Theme.Radius, strokes from Theme.Stroke, text >= 18 px.

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
	DimCloses: boolean?, -- default true; false = the dim is only a shade (it takes no taps)
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
	Header: Frame?, -- the navy band (nil without a title or ✖)
	Title: TextLabel?, -- the header's title
	Meta: TextLabel, -- the header's meta chip (hidden while it has no text)
	CloseButton: TextButton?,
	Focus: GuiObject?, -- what a gamepad selects on open (set it after building; default the ✖)
	open: () -> (),
	close: () -> (),
	toggle: () -> (),
	isOpen: () -> boolean,
	setMeta: (text: string?) -> (),
	setTitle: (text: string) -> (),
}
export type TabSpec = { Id: string, Icon: string, Caption: string, Stripe: Color3? }
export type Tabs = { select: (id: string) -> (), Column: Frame, Content: Frame, Buttons: { [string]: TextButton } }
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
-- A tab is this wide: a one-word caption at the 18 px floor ("Upgrades", "Hospital") fits inside it.
Pure.TAB_WIDTH = 88

-- What the HUD does while a modal of this layer is open, unless the spec says otherwise.
function Pure.hudMode(layer: string?, given: string?): string
	if given == "Panel" or given == "Game" or given == "None" then
		return given
	end
	return if layer == "Popup" then "None" else "Panel"
end

-- Whether the player can close it: a ✖, or a dim that closes on a tap. The mini-game has neither, so ButtonB never
-- closes it either.
function Pure.closable(spec: any): boolean
	if type(spec) ~= "table" then
		return true
	end
	return spec.CloseButton ~= false or (spec.Dim ~= false and spec.DimCloses ~= false)
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
local CLOSE = Theme.Size.ButtonHeight -- the ✖: 56 x 56
local META_HEIGHT = 40
local EDGE = Theme.Space.Step[1] -- the ✖ sits this far inside the band's right end

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

type Entry = { Modal: Modal, Closable: boolean, AutoFocus: boolean }
local stack: { Entry } = {}

local function indexOf(modal: Modal): number?
	for index, entry in stack do
		if entry.Modal == modal then
			return index
		end
	end
	return nil
end

function Modal.isOpen(name: string?): boolean
	for _, entry in stack do
		if name == nil or entry.Modal.Name == name then
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
		if top and top.AutoFocus and usesDirectionalFocus() then
			local modal = top.Modal
			local target = modal.Focus or modal.CloseButton or firstButton(modal.Panel)
			if target and target:IsDescendantOf(modal.Gui) then
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
		if top and top.Closable then
			top.Modal.close()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass -- the mini-game: ButtonB is the player's, not a close
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
end

function Modal.modal(ctx: Types.Ctx, spec: ModalSpec): Modal
	local layer: Layer = spec.Layer or "Panel"
	local hudMode = Pure.hudMode(layer, spec.HudMode) :: HudMode
	local closable = Pure.closable(spec)
	local autoFocus = spec.AutoFocus ~= false
	local gui = Kit.screen(
		"Modal_" .. spec.Name,
		if layer == "Popup" then Theme.DisplayOrder.Popup else Theme.DisplayOrder.Panel
	)
	gui.Enabled = false

	-- The dim: a button that closes it on a tap, or (DimCloses = false) a shade that takes no input at all.
	local dim: GuiObject? = nil
	if spec.Dim ~= false then
		local shade: GuiObject
		if spec.DimCloses == false then
			local frame = Instance.new("Frame")
			frame.Active = false
			shade = frame
		else
			local button = Instance.new("TextButton")
			button.Text = ""
			button.AutoButtonColor = false
			button.Selectable = false
			shade = button
		end
		shade.Name = "Dim"
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

	-- THE header: Kit.panel's navy band (spec.Accent is never passed on).
	local hasHeader = spec.Title ~= nil or spec.CloseButton ~= false
	local pad = Theme.Space.PadPanel
	local panel = Kit.panel({
		Name = "Panel",
		Title = if hasHeader then spec.Title or "" else nil,
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
	-- With a dim that closes, taps on the card stop here so they never reach it. Otherwise taps on the card's
	-- background fall through, so the thumbstick still works under it.
	panel.Active = dim ~= nil and spec.DimCloses ~= false
	local header = panel:FindFirstChild("Header") :: Frame?
	local title = panel:FindFirstChild("Title") :: TextLabel?
	local middle = Kit.HEADER / 2 - pad -- the band's middle, in the padded panel's space

	local closeButton: TextButton? = nil
	if spec.CloseButton ~= false then
		closeButton = Kit.button({
			Name = "Close",
			Kind = "Destructive",
			Text = "✖",
			TextSize = Theme.TextSize.Title,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, pad - EDGE, 0, middle),
			Size = UDim2.fromOffset(CLOSE, CLOSE),
			ZIndex = 3,
			Parent = panel,
		})
	end

	-- The header's one meta chip: white, ink text, left of the ✖. Hidden while it has no text.
	local metaRight = pad - EDGE - (if closeButton then CLOSE + Theme.Space.Gap else 0)
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
		Position = UDim2.new(1, metaRight, 0, middle),
		Size = UDim2.fromOffset(0, META_HEIGHT),
		Visible = false,
		ZIndex = 3,
		Parent = panel,
	})
	Kit.corner(meta, Theme.Radius.Small)
	Kit.stroke(meta, Theme.Colors.Stroke, Theme.Stroke.Fine)
	local metaPad = Instance.new("UIPadding")
	metaPad.PaddingLeft = UDim.new(0, Theme.Space.PadCard)
	metaPad.PaddingRight = UDim.new(0, Theme.Space.PadCard)
	metaPad.Parent = meta

	-- The title makes room for the ✖ and the meta chip.
	local function fitTitle()
		if not title then
			return
		end
		local used = (if closeButton then CLOSE + Theme.Space.Gap else 0)
			- (pad - EDGE)
			+ (if meta.Visible then meta.AbsoluteSize.X + Theme.Space.Gap else 0)
		title.Size = UDim2.new(1, -math.max(used, 0), 0, Kit.HEADER - Theme.Space.PadCard * 2)
	end
	meta:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitTitle)

	local top = if hasHeader then Kit.HEADER - pad + Theme.Space.Gap else 0
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, top)
	body.Size = UDim2.new(1, 0, 1, -top)
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
		Header = header,
		Title = title,
		Meta = meta,
		CloseButton = closeButton,
		Focus = closeButton :: GuiObject?,
	} :: Modal
	local entry: Entry = { Modal = modal, Closable = closable, AutoFocus = autoFocus }

	function modal.setMeta(text: string?)
		local shown = type(text) == "string" and text ~= ""
		meta.Text = if shown then text :: string else ""
		meta.Visible = shown
		fitTitle()
	end
	modal.setMeta(spec.Meta)

	function modal.setTitle(text: string)
		if title then
			title.Text = text
		end
	end

	function modal.isOpen(): boolean
		return opened
	end

	function modal.close()
		if not opened then
			return
		end
		opened = false
		local index = indexOf(modal)
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
			-- One Panel at a time. A "Game" card (the mini-game) stays up: the new Panel opens under it.
			for _, other in table.clone(stack) do
				local otherModal = other.Modal
				if otherModal ~= modal and otherModal.Layer == "Panel" and otherModal.HudMode ~= "Game" then
					otherModal.close()
				end
			end
		end
		opened = true
		table.insert(stack, entry)
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
		if autoFocus then
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
	if dim and dim:IsA("TextButton") then
		dim.Activated:Connect(function()
			modal.close()
		end)
	end
	return modal
end

------------------------------------------------------------------------------------------------------------------
-- Fitting
------------------------------------------------------------------------------------------------------------------

-- Tab buttons down a column: as tall as the column's height allows, between 56 (the tap minimum) and 76; square
-- unless `width` is given. A column taller than that scrolls if it's a ScrollingFrame. The column's own UIPadding is
-- left out of the height.
function Modal.fitTabs(column: GuiObject, tabs: { GuiObject }, gap: number, width: number?)
	local function fit()
		local height = column.AbsoluteSize.Y
		local padding = column:FindFirstChildOfClass("UIPadding")
		if padding then
			height -= padding.PaddingTop.Offset + padding.PaddingBottom.Offset
		end
		if height <= 0 or #tabs == 0 then
			return
		end
		local side =
			math.clamp(math.floor((height - gap * (#tabs - 1)) / #tabs), Theme.Size.ButtonHeight, Theme.Size.IconButton)
		for _, tab in tabs do
			tab.Size = UDim2.fromOffset(width or side, side)
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
-- THE tab pattern
------------------------------------------------------------------------------------------------------------------

function Modal.tabs(modal: Modal, tabs: { TabSpec }, onSelect: (id: string) -> ()): Tabs
	local gap = Theme.Space.Gap
	local edge = Theme.Space.Step[1] -- room for the selected tab's outline inside the scrolling list
	local columnWidth = Pure.TAB_WIDTH + edge * 2
	local column = Instance.new("Frame")
	column.Name = "Tabs"
	column.BackgroundTransparency = 1
	column.Size = UDim2.new(0, columnWidth, 1, 0)
	column.Parent = modal.Body

	-- The tabs scroll when they don't fit a short landscape phone at 56 px (the Book has seven).
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.fromScale(1, 1)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 0
	list.Selectable = false
	list.Parent = column
	local layout = Kit.list(list, Enum.FillDirection.Vertical, gap)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	local padding = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(padding :: any)[side] = UDim.new(0, edge)
	end
	padding.Parent = list

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
			Kind = "Icon",
			Icon = tab.Icon,
			Caption = tab.Caption,
			LayoutOrder = index,
			Size = UDim2.fromOffset(Pure.TAB_WIDTH, Theme.Size.IconButton),
			Parent = list,
		})
		buttons[tab.Id] = button
		stripes[tab.Id] = tab.Stripe
		table.insert(ordered, button)
		button.Activated:Connect(function()
			choose(tab.Id)
		end)
	end
	Modal.fitTabs(list, ordered, gap, Pure.TAB_WIDTH)

	if tabs[1] then
		selected = tabs[1].Id
	end
	paint()
	return { select = choose, Column = column, Content = content, Buttons = buttons }
end

------------------------------------------------------------------------------------------------------------------
-- The one confirm and the one odds popup
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

	-- The one line, on a tinted card.
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.BackgroundColor3 = Theme.Colors.Card
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 1, -(row + Theme.Space.PadPanel))
	Kit.corner(card, Theme.Radius.Medium)
	Kit.stroke(card, Theme.Colors.CardLine, Theme.Stroke.Fine)
	Kit.pad(card, Theme.Space.PadCard)
	card.Parent = modal.Body
	local line = Kit.label({
		Name = "Line",
		Text = c.Line,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
		Parent = card,
	})
	Kit.textLimit(line, Theme.TextSize.Body)

	local no = Kit.button({
		Name = "No",
		Kind = "Secondary",
		Text = c.No,
		TextScaled = true,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(0.5, -gap / 2, 0, row),
		Parent = modal.Body,
	})
	local yes = Kit.button({
		Name = "Yes",
		Kind = c.Kind,
		Text = c.Yes,
		TextScaled = true,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(0.5, -gap / 2, 0, row),
		Parent = modal.Body,
	})
	for _, button in { no, yes } do
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
	local rowHeight = Theme.Size.ButtonHeight - Theme.Space.Step[2]

	local list = Instance.new("ScrollingFrame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.fromScale(1, 1)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Theme.Colors.Stroke
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Selectable = false
	local layout = Kit.list(list, Enum.FillDirection.Vertical, gap)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, Theme.Space.Step[1])
	padding.PaddingRight = UDim.new(0, Theme.Space.PadCard)
	padding.Parent = list
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
		local name = Kit.label({
			Name = "Name",
			Text = entry.Icon .. " " .. entry.Name,
			TextScaled = true,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(Theme.Space.PadCard, 0),
			Size = UDim2.new(0.62, -Theme.Space.PadCard, 1, 0),
			Parent = row,
		})
		Kit.textLimit(name, Theme.TextSize.Body)
		local percent = Kit.label({
			Name = "Percent",
			Text = Pure.percent(entry.Percent),
			Font = Theme.DisplayFont,
			TextScaled = true,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -Theme.Space.PadCard, 0, 0),
			Size = UDim2.new(0.38, -Theme.Space.PadCard, 1, 0),
			Parent = row,
		})
		Kit.textLimit(percent, Theme.TextSize.Body)
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
