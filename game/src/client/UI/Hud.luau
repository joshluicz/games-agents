--!strict
-- Hud (build plan Task 6): the always-on screen, plus the shared UI pieces the other panels build on.
--
-- On screen (all inside the safe area, nothing under the touch thumbstick or jump button, and the right edge's
-- middle left free for the 🎵 and ✨ comfort buttons from Music.client and Feel/Atmosphere):
--   top left      💰 cash · ⭐ stars with a bar to the next unlock (tap it: what's next) · ⚠️ not saving · 🏠 no clinic
--   top right     ☀️/🌙 day-night timer (×2 at night) · ⭐ Today's Visitor (tap: what it means)
--   bottom centre your hands (the `Carry` and `CarryMax` attributes) above the 🛒 📖 📬 🎯 buttons, each with a
--                 dot when something waits there (a room you can buy or decor to place · new pages · mail · a goal)
-- Everything is drawn from the Snapshot, player attributes and Workspace attributes. The client never decides
-- anything: buttons only open panels, and panels only ask the server.
--
-- Shared helpers (the other UI modules require this module for them; none of them needs Hud.init to have run):
--   Hud.modal(ctx, spec): Modal        a panel or popup shell: dim, paper card with a soft shadow, title, ✖,
--                                      pop in/out, one Panel open at a time, gamepad focus and ButtonB to close
--   Hud.ask(remote, ...): (ok, msg)    InvokeServer that never throws and gives up after ASK_TIMEOUT seconds
--   Hud.portrait(look, dark?): Frame   a cute 2D creature face drawn from a Data `Look` (dark = "not met yet")
--   Hud.lookOf(id): Look?              the Look of a PatientId or RegularId
--   Hud.decorSlots(data, state)        every "<RoomId>:<n>" decor slot in your rooms, and what's in it
--   Hud.shopNews(data, state)          { Rooms, Decor }: what the 🛒 dot is about
--   Hud.fly(from, icon, target?, n?)   icons burst from a GuiObject and fly into "Cash" or "Stars" (or float up)
--   Hud.pop(gui) · Hud.shake(gui)      a happy bounce · a "nope" wiggle
--   Hud.fitTabs(column, tabs, gap)     square tabs sized to the column (56 to 76 px)
--   Hud.fitHeight(content, area)       scales a block down to fit a short screen
--   Hud.calm(): boolean                Reduced Motion, or the ✨ calm toggle (ReduceEffects): skip the motion
--   Hud.sound(name, volume?)           a Feel/Sounds cue over the bus
--   Hud.format(n): string              1,234 · 1.2M past a million
--
-- Client bus (ctx.on / ctx.fire):
--   listens  "BookNew" (count)                      BookPanel: unseen new pages, for the 📖 dot
--   fires    "Open" (name, tab?)                    name = "Shop" | "Book" | "Mailbox" | "Goals"
--   fires    "ModalOpened" (name) · "ModalClosed" (name)
--   fires    "Sound" (name, volume?)                Whoosh on open, Nope on a shake, Pop when icons land

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local PatientsData = require(Shared:WaitForChild("Data"):WaitForChild("Patients")) :: any
local RegularsData = require(Shared:WaitForChild("Data"):WaitForChild("Regulars")) :: any
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Hud = {}

export type Layer = "Panel" | "Popup"
export type ModalSpec = {
	Name: string,
	Title: string?, -- header text: an emoji and at most two words
	Layer: Layer?, -- "Panel" (default): only one open at a time · "Popup": stacks above panels
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
}

------------------------------------------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------------------------------------------

local SHADOW_OFFSET = 6
local DIM_BLEED = 400 -- the dim reaches past the safe area so the whole screen darkens (decoration may bleed)
local FLOAT_INFO = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function commas(n: number): string
	local digits = tostring(math.floor(math.abs(n)))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return (if n < 0 then "-" else "") .. grouped
end

function Hud.format(n: any): string
	if type(n) ~= "number" or n ~= n then
		return "0"
	end
	if math.abs(n) >= 1e6 then
		return (string.gsub(string.format("%.1fM", n / 1e6), "%.0M", "M"))
	end
	return commas(n)
end

-- Calm motion: the device's Reduced Motion setting, or the ✨ calm-effects toggle (Feel/Atmosphere sets the
-- client-only player attribute ReduceEffects). Every tween in the UI checks this.
function Hud.calm(): boolean
	return Kit.reducedMotion() or Players.LocalPlayer:GetAttribute("ReduceEffects") == true
end

-- Sound cues go over the client bus to Feel/Sounds ("Sound", name), so UI never requires a Feel module.
local fireBus: ((string, ...any) -> ())? = nil
function Hud.sound(name: string, volumeScale: number?)
	if fireBus then
		fireBus("Sound", name, volumeScale)
	end
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

local popTweens: { [GuiObject]: Tween } = {}
function Hud.pop(gui: GuiObject?, size: number?)
	if not gui or Hud.calm() then
		return
	end
	-- Reuse a UIScale that's already there (Kit buttons have one): two on one object fight.
	local scale = gui:FindFirstChildOfClass("UIScale") or scaleNamed(gui, "PopScale")
	local running = popTweens[gui]
	if running then
		running:Cancel()
	end
	scale.Scale = size or 1.18
	local tween = TweenService:Create(scale, POP_INFO, { Scale = 1 })
	popTweens[gui] = tween
	tween.Completed:Once(function()
		if popTweens[gui] == tween then
			popTweens[gui] = nil
		end
	end)
	tween:Play()
end

function Hud.shake(gui: GuiObject?)
	Hud.sound("Nope")
	if not gui or Hud.calm() then
		return
	end
	task.spawn(function()
		for _, angle in { -7, 7, -5, 5, 0 } do
			local tween = TweenService:Create(gui, TweenInfo.new(0.05), { Rotation = angle })
			tween:Play()
			tween.Completed:Wait()
		end
		gui.Rotation = 0
	end)
end

local function usesDirectionalFocus(): boolean
	local preferred = UserInputService.PreferredInput
	return preferred == Enum.PreferredInput.Gamepad or preferred == Enum.PreferredInput.MicroGamepad
end

------------------------------------------------------------------------------------------------------------------
-- Modals: a stack, so ButtonB and focus always belong to the top one
------------------------------------------------------------------------------------------------------------------

local CLOSE_ACTION = "ClinicCloseModal"
local stack: { Modal } = {}

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

function Hud.modal(ctx: Types.Ctx, spec: ModalSpec): Modal
	fireBus = fireBus or ctx.fire
	local layer: Layer = spec.Layer or "Panel"
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

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.Position = UDim2.fromOffset(0, SHADOW_OFFSET)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.BackgroundColor3 = Theme.Colors.Shade
	shadow.BackgroundTransparency = 0.72
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 0
	Kit.corner(shadow, Theme.Size.CornerLarge)
	shadow.Parent = root

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
			Kind = "Danger",
			Text = "✖",
			TextSize = Theme.TextSize.Title,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(Theme.Size.ButtonHeight, Theme.Size.ButtonHeight),
			ZIndex = 2,
			Parent = panel,
		})
	end

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
		if Hud.calm() then
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
		Gui = gui,
		Root = root,
		Panel = panel,
		Body = body,
		CloseButton = closeButton,
		Focus = closeButton :: GuiObject?,
	} :: Modal

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
		ctx.fire("ModalClosed", spec.Name)
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
		syncCloseBinding()
		if spec.AutoFocus ~= false then
			focusTop()
		end
		Hud.sound("Whoosh", 0.7)
		ctx.fire("ModalOpened", spec.Name)
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
-- Creature portraits: a friendly face from a Data `Look` (the same recipe CreatureBuilder uses in 3D)
------------------------------------------------------------------------------------------------------------------

local SILHOUETTE = Color3.fromRGB(92, 76, 98)
local CHEEK = Color3.fromRGB(255, 138, 160)
local PUPIL = Color3.fromRGB(46, 34, 40)
local WHITE = Color3.new(1, 1, 1)

type ShapeSpec = { W: number, H: number, Round: number }
local SHAPES: { [string]: ShapeSpec } = {
	Ball = { W = 0.74, H = 0.7, Round = 0.5 },
	Bean = { W = 0.6, H = 0.76, Round = 0.5 },
	Blob = { W = 0.84, H = 0.62, Round = 0.5 },
	Box = { W = 0.7, H = 0.64, Round = 0.24 },
	Drop = { W = 0.7, H = 0.68, Round = 0.5 },
}

local function hex(value: any, fallback: Color3): Color3
	if type(value) ~= "string" then
		return fallback
	end
	local ok, color = pcall(Color3.fromHex, value)
	return if ok then color else fallback
end

local function blob(
	parent: Instance,
	name: string,
	color: Color3,
	center: Vector2,
	size: Vector2,
	z: number,
	round: number?,
	rotation: number?
): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(center.X, center.Y)
	frame.Size = UDim2.fromScale(size.X, size.Y)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = z
	frame.Rotation = rotation or 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(round or 0.5, 0)
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

local function outline(frame: Frame, color: Color3)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Kit.shade(color, 0.3)
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = frame
end

local function emoji(parent: Instance, text: string, center: Vector2, size: Vector2, z: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Top"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(center.X, center.Y)
	label.Size = UDim2.fromScale(size.X, size.Y)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Theme.Font
	label.ZIndex = z
	label.Parent = parent
	return label
end

local TOP_EMOJI: { [string]: { Text: string, Size: number, Dy: number, Dx: number } } = {
	Leaf = { Text = "🌱", Size = 0.3, Dy = -0.05, Dx = 0 },
	Bow = { Text = "🎀", Size = 0.26, Dy = 0.01, Dx = 0.18 },
	Cloud = { Text = "☁️", Size = 0.36, Dy = -0.03, Dx = 0 },
	Star = { Text = "⭐", Size = 0.28, Dy = -0.06, Dx = 0 },
}

function Hud.lookOf(id: any): any
	if type(id) ~= "string" or id == "" or id == "Order" then
		return nil
	end
	local entry = rawget(PatientsData, id) or rawget(RegularsData, id)
	return if type(entry) == "table" then entry.Look else nil
end

function Hud.portrait(look: any, dark: boolean?): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Portrait"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = frame

	local l = if type(look) == "table" then look else {}
	local shape = SHAPES[l.Shape] or SHAPES.Ball
	local bodyColor = if dark then SILHOUETTE else hex(l.Body, Color3.fromRGB(255, 200, 220))
	local accent = if dark then Kit.shade(SILHOUETTE, 0.15) else hex(l.Accent, WHITE)
	local cx, cy, w, h = 0.5, 0.6, shape.W, shape.H
	local top = cy - h / 2
	local left, right = cx - w / 2, cx + w / 2

	-- Behind the body (z 1): ears and extras.
	for _, side in { -1, 1 } do
		local ears = l.Ears
		if ears == "Round" then
			local ear =
				blob(frame, "Ear", bodyColor, Vector2.new(cx + side * w * 0.34, top + 0.03), Vector2.one * 0.22, 1)
			outline(ear, bodyColor)
			blob(ear, "Inner", accent, Vector2.new(0.5, 0.5), Vector2.one * 0.55, 1)
		elseif ears == "Floppy" then
			local ear = blob(
				frame,
				"Ear",
				accent,
				Vector2.new(if side < 0 then left + 0.02 else right - 0.02, top + h * 0.32),
				Vector2.new(0.17, 0.32),
				1,
				0.5,
				side * -18
			)
			outline(ear, accent)
		elseif ears == "Pointy" then
			local ear = blob(
				frame,
				"Ear",
				bodyColor,
				Vector2.new(cx + side * w * 0.3, top + 0.05),
				Vector2.one * 0.2,
				1,
				0.18,
				45
			)
			outline(ear, bodyColor)
		elseif ears == "Long" then
			local ear = blob(
				frame,
				"Ear",
				bodyColor,
				Vector2.new(cx + side * 0.12, top - 0.05),
				Vector2.new(0.13, 0.36),
				1,
				0.5,
				side * 10
			)
			outline(ear, bodyColor)
			blob(ear, "Inner", accent, Vector2.new(0.5, 0.45), Vector2.new(0.5, 0.7), 1)
		elseif ears == "Tufts" then
			blob(frame, "Ear", accent, Vector2.new(cx + side * w * 0.34, top + 0.02), Vector2.one * 0.13, 1, 0.2, 45)
		end

		local extra = l.Extra
		if extra == "Wings" then
			local wing = blob(
				frame,
				"Wing",
				accent,
				Vector2.new(if side < 0 then left - 0.01 else right + 0.01, cy - 0.02),
				Vector2.new(0.2, 0.32),
				1,
				0.5,
				side * 28
			)
			outline(wing, accent)
		elseif extra == "Flippers" then
			blob(
				frame,
				"Flipper",
				Kit.shade(bodyColor, 0.12),
				Vector2.new(if side < 0 then left + 0.01 else right - 0.01, cy + 0.08),
				Vector2.new(0.12, 0.26),
				1,
				0.5,
				side * -25
			)
		end
	end
	if l.Extra == "Tail" then
		local tail = blob(frame, "Tail", accent, Vector2.new(right + 0.02, cy + h * 0.25), Vector2.one * 0.17, 1)
		outline(tail, accent)
	elseif l.Extra == "Spout" then
		local spout =
			blob(frame, "Spout", bodyColor, Vector2.new(right + 0.06, cy), Vector2.new(0.24, 0.11), 1, 0.5, -30)
		outline(spout, bodyColor)
	end
	if l.Shape == "Drop" then
		local tip = blob(frame, "Tip", bodyColor, Vector2.new(cx, top + 0.03), Vector2.one * 0.26, 1, 0.22, 45)
		outline(tip, bodyColor)
	end

	-- The body (z 2).
	local body = blob(frame, "Body", bodyColor, Vector2.new(cx, cy), Vector2.new(w, h), 2, shape.Round)
	outline(body, bodyColor)

	-- On the head (z 6).
	local topKind = l.Top
	local topEmoji = TOP_EMOJI[topKind]
	if topEmoji and not dark then
		emoji(frame, topEmoji.Text, Vector2.new(cx + topEmoji.Dx, top + topEmoji.Dy), Vector2.one * topEmoji.Size, 6)
	elseif topKind == "Antennae" then
		for _, side in { -1, 1 } do
			blob(
				frame,
				"Stalk",
				Kit.shade(bodyColor, 0.3),
				Vector2.new(cx + side * 0.1, top - 0.05),
				Vector2.new(0.025, 0.16),
				6,
				0.5,
				side * 22
			)
			blob(frame, "Bobble", accent, Vector2.new(cx + side * 0.14, top - 0.13), Vector2.one * 0.09, 6)
		end
	elseif topKind == "Crust" then
		blob(frame, "Crust", Kit.shade(bodyColor, 0.28), Vector2.new(cx, top + 0.04), Vector2.new(w * 1.02, 0.12), 6)
	elseif topKind == "Pleat" then
		for i = -1, 1 do
			blob(frame, "Pleat", accent, Vector2.new(cx + i * 0.08, top + 0.02), Vector2.one * 0.08, 6)
		end
	elseif topKind == "Scoop" then
		blob(frame, "Scoop", accent, Vector2.new(cx, top + 0.02), Vector2.new(w * 0.7, 0.22), 6)
	elseif topKind == "Lid" then
		blob(frame, "Lid", accent, Vector2.new(cx, top + 0.02), Vector2.new(w * 0.6, 0.1), 6)
		blob(frame, "Knob", accent, Vector2.new(cx, top - 0.05), Vector2.one * 0.09, 6)
	end

	if dark then
		local mystery = emoji(frame, "?", Vector2.new(cx, cy + 0.02), Vector2.one * 0.42, 7)
		mystery.Name = "Mystery"
		mystery.TextColor3 = Color3.fromRGB(236, 228, 240)
		return frame
	end

	-- The face (z 3-5): belly, big eyes, rosy cheeks and a happy mouth.
	blob(frame, "Belly", accent, Vector2.new(cx, cy + h * 0.2), Vector2.new(w * 0.56, h * 0.46), 3)
	for _, side in { -1, 1 } do
		local eye = blob(frame, "Eye", WHITE, Vector2.new(cx + side * w * 0.2, cy - h * 0.1), Vector2.one * 0.16, 4)
		local pupil = blob(eye, "Pupil", PUPIL, Vector2.new(0.55, 0.58), Vector2.one * 0.64, 4)
		blob(pupil, "Shine", WHITE, Vector2.new(0.32, 0.3), Vector2.one * 0.38, 4)
		local cheek =
			blob(frame, "Cheek", CHEEK, Vector2.new(cx + side * w * 0.33, cy + h * 0.06), Vector2.new(0.11, 0.07), 4)
		cheek.BackgroundTransparency = 0.35
	end
	local mouth = Instance.new("Frame")
	mouth.Name = "Mouth"
	mouth.AnchorPoint = Vector2.new(0.5, 0)
	mouth.Position = UDim2.fromScale(cx, cy + h * 0.02)
	mouth.Size = UDim2.fromScale(0.1, 0.05)
	mouth.BackgroundTransparency = 1
	mouth.ClipsDescendants = true -- only the bottom half of the circle shows: a smile
	mouth.ZIndex = 5
	mouth.Parent = frame
	blob(mouth, "Smile", PUPIL, Vector2.new(0.5, 0), Vector2.new(1, 2), 5)
	return frame
end

------------------------------------------------------------------------------------------------------------------
-- Flying icons: rewards visibly land in the wallet
------------------------------------------------------------------------------------------------------------------

local fxGui: ScreenGui? = nil
local targets: { [string]: GuiObject } = {}

local function fxLayer(): ScreenGui
	local layer = fxGui
	if not layer or not layer.Parent then
		layer = Kit.screen("HudFx", Theme.DisplayOrder.Fx)
		fxGui = layer
	end
	return layer :: ScreenGui
end

local function centreOf(gui: GuiObject, layer: ScreenGui): Vector2
	return gui.AbsolutePosition + gui.AbsoluteSize / 2 - layer.AbsolutePosition
end

function Hud.fly(from: GuiObject?, icon: string, target: string?, count: number?)
	local layer = fxLayer()
	local goalGui = if target then targets[target] else nil
	if Hud.calm() then
		Hud.pop(goalGui)
		return
	end
	local start = if from then centreOf(from, layer) else layer.AbsoluteSize / 2
	local goal = if goalGui then centreOf(goalGui, layer) else nil
	local n = math.clamp(math.floor(count or 6), 1, 10)
	local landed = false
	for i = 1, n do
		local label = Instance.new("TextLabel")
		label.Name = "Fly"
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromOffset(start.X, start.Y)
		label.Size = UDim2.fromOffset(34, 34)
		label.BackgroundTransparency = 1
		label.Text = icon
		label.TextScaled = true
		label.Font = Theme.Font
		label.ZIndex = 10
		label.Parent = layer

		local angle = (i / n) * math.pi * 2 + math.random() * 0.6
		local spread = start + Vector2.new(math.cos(angle), math.sin(angle)) * (36 + math.random() * 34)
		TweenService:Create(
			label,
			TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(spread.X, spread.Y) }
		):Play()

		task.delay(0.24 + i * 0.05, function()
			if not label.Parent then
				return
			end
			local tween: Tween
			if goal then
				tween = TweenService:Create(
					label,
					TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Position = UDim2.fromOffset(goal.X, goal.Y), Size = UDim2.fromOffset(20, 20) }
				)
			else
				tween = TweenService:Create(label, FLOAT_INFO, {
					Position = UDim2.fromOffset(spread.X, spread.Y - 60),
					TextTransparency = 1,
				})
			end
			tween.Completed:Once(function()
				label:Destroy()
				if goal then
					Hud.pop(goalGui, 1.12)
					if not landed then
						landed = true
						Hud.sound("Pop")
					end
				end
			end)
			tween:Play()
		end)
	end
end

------------------------------------------------------------------------------------------------------------------
-- The HUD itself
------------------------------------------------------------------------------------------------------------------

local function pill(props: { [string]: any }): Frame
	local frame = Instance.new(if props.Button then "TextButton" else "Frame") :: any
	frame.Name = props.Name
	frame.BackgroundColor3 = props.Color or Theme.Colors.Card
	frame.BorderSizePixel = 0
	frame.Size = props.Size or UDim2.fromOffset(120, 46)
	frame.LayoutOrder = props.LayoutOrder or 0
	if props.Button then
		frame.Text = ""
		frame.AutoButtonColor = false
	end
	Kit.corner(frame, 23)
	local stroke = Kit.stroke(frame, Theme.Colors.Stroke, 2.5)
	stroke.Transparency = 0.2
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(232, 232, 232))
	gradient.Parent = frame
	frame.Parent = props.Parent
	return frame
end

local function iconLabel(parent: Instance, text: string, position: UDim2, px: number): TextLabel
	return Kit.label({
		Name = "Icon",
		Text = text,
		TextScaled = true,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = position,
		Size = UDim2.fromOffset(px, px),
		Parent = parent,
	})
end

local function textSizeLimit(label: TextLabel, max: number)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = max
	limit.MinTextSize = 12
	limit.Parent = label
end

local function splitCarry(raw: any): { string }
	local items = {}
	if type(raw) == "string" then
		for id in string.gmatch(raw, "[^,]+") do
			table.insert(items, id)
		end
	end
	return items
end

-- The ⭐ bar runs from the last star unlock you passed to the next one (a room you don't own, or a regular).
local function starTrack(data: any, state: Types.Snapshot): (number, number?, string, string)
	local stars = state.Stars or 0
	local rooms = state.Rooms or {}
	local passed, nextAt, nextIcon, nextName = 0, nil :: number?, "👑", ""
	local function consider(at: number, icon: string, name: string, eligible: boolean)
		if at <= 0 then
			return
		end
		if at <= stars then
			passed = math.max(passed, at)
		elseif eligible and (nextAt == nil or at < nextAt) then
			nextAt, nextIcon, nextName = at, icon, name
		end
	end
	for _, roomId in data.Rooms.Order do
		local room = data.Rooms[roomId]
		local inSeason = room.Season == nil or state.IsWinter == true
		consider(room.StarsNeeded, room.Icon, room.Name, rooms[roomId] ~= true and inSeason)
	end
	for _, regularId in data.Regulars.Order do
		local regular = data.Regulars[regularId]
		consider(regular.UnlockStars, "💌", regular.Name, true)
	end
	return passed, nextAt, nextIcon, nextName
end

export type DecorSlot = { Key: string, RoomId: string, N: number, Placed: string? }

-- Every decor slot in the rooms you own, in room order: "<RoomId>:<n>" plus what's in it now.
function Hud.decorSlots(data: any, state: Types.Snapshot): { DecorSlot }
	local slots: { DecorSlot } = {}
	local placed = (state.Decor and state.Decor.Placed) or {}
	for _, roomId in data.Rooms.Order do
		local room = data.Rooms[roomId]
		if state.Rooms and state.Rooms[roomId] == true then
			for n = 1, room.DecorSlots do
				local key = roomId .. ":" .. n
				local decorId = placed[key]
				table.insert(slots, { Key = key, RoomId = roomId, N = n, Placed = decorId })
			end
		end
	end
	return slots
end

-- What the 🛒 dot points at: a room you could buy right now (stars and cash both enough), or decor you own
-- that isn't placed while a slot is free (a fresh Book or story reward, say).
function Hud.shopNews(data: any, state: Types.Snapshot): { Rooms: boolean, Decor: boolean }
	local news = { Rooms = false, Decor = false }
	if state.PlotIndex == nil then
		return news
	end
	for _, roomId in data.Rooms.Order do
		local room = data.Rooms[roomId]
		local owned = state.Rooms and state.Rooms[roomId] == true
		local inSeason = room.Season == nil or state.IsWinter == true
		if
			not owned
			and inSeason
			and room.Price > 0
			and (state.Stars or 0) >= room.StarsNeeded
			and (state.Cash or 0) >= room.Price
		then
			news.Rooms = true
		end
	end
	local placedIds: { [string]: boolean } = {}
	local freeSlot = false
	for _, slot in Hud.decorSlots(data, state) do
		if slot.Placed then
			placedIds[slot.Placed] = true
		else
			freeSlot = true
		end
	end
	if freeSlot and state.Decor and state.Decor.Owned then
		for decorId, owned in state.Decor.Owned do
			if owned == true and not placedIds[decorId] and rawget(data.Decor, decorId) then
				news.Decor = true
			end
		end
	end
	return news
end

-- Square tab buttons down a column: as big as the column's height allows, between 56 (the tap minimum) and 76.
-- A column taller than that scrolls if it's a ScrollingFrame.
function Hud.fitTabs(column: GuiObject, tabs: { GuiObject }, gap: number)
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

-- Scales a block of content down (never up) so it fits the height it's given. The content should have
-- AnchorPoint (0.5, 0), a scale width and AutomaticSize Y.
function Hud.fitHeight(content: GuiObject, area: GuiObject)
	local scale = scaleNamed(content, "FitScale")
	local function fit()
		local needed = content.AbsoluteSize.Y / math.max(scale.Scale, 0.01)
		local available = area.AbsoluteSize.Y
		if needed > 0 and available > 0 then
			scale.Scale = math.clamp(available / needed, 0.6, 1)
		end
	end
	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	area:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
end

-- Calls a client -> server RemoteFunction safely and yields for the answer. Returns (ok, message); message may
-- be "". A server that errors, or doesn't answer within ASK_TIMEOUT seconds, counts as not ok (the call still
-- finishes in the background; the caller just stops waiting for it).
local ASK_TIMEOUT = 10
function Hud.ask(remote: RemoteFunction, ...: any): (boolean, string)
	local args = table.pack(...)
	local thread = coroutine.running()
	local done = false
	local function finish(ok: boolean, message: string)
		if not done then
			done = true
			task.spawn(thread, ok, message)
		end
	end
	-- Deferred, so this thread is already waiting below even if the call fails at once.
	task.defer(function()
		local called, result, message = pcall(function()
			return remote:InvokeServer(table.unpack(args, 1, args.n))
		end)
		if not called then
			finish(false, "Oops! Try again.")
		else
			finish(result == true, if type(message) == "string" then message else "")
		end
	end)
	task.delay(ASK_TIMEOUT, function()
		finish(false, "Oops! Try again.")
	end)
	return coroutine.yield()
end

local function goalReady(data: any, state: Types.Snapshot): boolean
	local goals = state.Daily and state.Daily.Goals
	if type(goals) ~= "table" then
		return false
	end
	for _, goal in goals do
		for _, def in data.DailyGoals do
			if def.Id == goal.Id and (goal.Progress or 0) >= def.Target then
				return true
			end
		end
	end
	return false
end

-- A number label that counts to its new value and shows a floating "+n" (or "-n").
type Counter = { set: (value: number, animate: boolean) -> () }
local function counter(holder: GuiObject, label: TextLabel, prefix: string): Counter
	local value = Instance.new("NumberValue")
	value.Name = "Shown"
	value.Parent = holder
	local tween: Tween? = nil
	local target = 0
	value.Changed:Connect(function(v: number)
		label.Text = prefix .. Hud.format(math.floor(v + 0.5))
	end)
	label.Text = prefix .. "0"

	local function floater(delta: number)
		local layer = fxLayer()
		local at = centreOf(holder, layer)
		local text = Kit.label({
			Name = "Delta",
			Text = (if delta > 0 then "+" else "-") .. Hud.format(math.abs(delta)),
			TextSize = Theme.TextSize.Body,
			TextColor3 = if delta > 0 then Theme.Colors.Good else Theme.Colors.Danger,
			TextStrokeColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0,
			TextWrapped = false,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(at.X + holder.AbsoluteSize.X / 2 + 6, at.Y),
			Size = UDim2.fromOffset(90, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 10,
			Parent = layer,
		})
		local rise = TweenService:Create(text, FLOAT_INFO, {
			Position = UDim2.fromOffset(at.X + holder.AbsoluteSize.X / 2 + 6, at.Y - 34),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		rise.Completed:Once(function()
			text:Destroy()
		end)
		rise:Play()
	end

	return {
		set = function(newValue: number, animate: boolean)
			if newValue == target then
				return
			end
			local delta = newValue - target
			target = newValue
			if tween then
				tween:Cancel()
				tween = nil
			end
			if not animate or Hud.calm() then
				value.Value = newValue
				label.Text = prefix .. Hud.format(newValue)
				return
			end
			local created = TweenService:Create(
				value,
				TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Value = newValue }
			)
			tween = created
			created:Play()
			floater(delta)
			if delta > 0 then
				Hud.pop(holder, 1.1)
			end
		end,
	}
end

function Hud.init(ctx: Types.Ctx)
	local data = ctx.Data :: any
	local player = ctx.Player
	fireBus = fireBus or ctx.fire
	-- Main.client hands every module the default snapshot first; the first one after it is the save loading in,
	-- so it is shown without "+n" floaters.
	local initial = ctx.State
	local margin = Theme.Size.Margin

	local gui = Kit.screen("Hud", Theme.DisplayOrder.Hud)

	--------------------------------------------------------------------------------------------------------------
	-- Top left: the wallet
	--------------------------------------------------------------------------------------------------------------
	local wallet = Instance.new("Frame")
	wallet.Name = "Wallet"
	wallet.BackgroundTransparency = 1
	wallet.Position = UDim2.fromOffset(margin, margin)
	wallet.Size = UDim2.fromOffset(210, 200) -- cash, stars, and the rare status chips under them
	wallet.Parent = gui
	local walletList = Kit.list(wallet, Enum.FillDirection.Vertical, 8)
	walletList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	walletList.VerticalAlignment = Enum.VerticalAlignment.Top

	local cashPill = pill({ Name = "Cash", Parent = wallet, LayoutOrder = 1, Size = UDim2.fromOffset(150, 46) })
	iconLabel(cashPill, "💰", UDim2.new(0, 8, 0.5, 0), 32)
	local cashText = Kit.label({
		Name = "Amount",
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 46, 0.5, 0),
		Size = UDim2.new(1, -58, 0, 30),
		Parent = cashPill,
	})
	textSizeLimit(cashText, 28)
	targets.Cash = cashPill
	local cash = counter(cashPill, cashText, "")

	local starsPill =
		pill({ Name = "Stars", Parent = wallet, LayoutOrder = 2, Size = UDim2.fromOffset(210, 46), Button = true })
	iconLabel(starsPill, "⭐", UDim2.new(0, 8, 0.5, 0), 30)
	local starsText = Kit.label({
		Name = "Amount",
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 42, 0.5, 0),
		Size = UDim2.fromOffset(50, 28),
		Parent = starsPill,
	})
	textSizeLimit(starsText, 26)
	targets.Stars = starsPill
	local stars = counter(starsPill, starsText, "")

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, 96, 0.5, 0)
	track.Size = UDim2.new(1, -96 - 44, 0, 14)
	track.BackgroundColor3 = Theme.Colors.Quiet
	track.BorderSizePixel = 0
	Kit.corner(track, 7)
	track.Parent = starsPill
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Theme.Colors.Star
	fill.BorderSizePixel = 0
	Kit.corner(fill, 7)
	fill.Parent = track
	local nextIcon = Kit.label({
		Name = "Next",
		Text = "👑",
		TextScaled = true,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(30, 30),
		Parent = starsPill,
	})
	local nextTip = ""

	--------------------------------------------------------------------------------------------------------------
	-- Top right: the clock and status chips
	--------------------------------------------------------------------------------------------------------------
	local side = Instance.new("Frame")
	side.Name = "Clock"
	side.AnchorPoint = Vector2.new(1, 0)
	side.BackgroundTransparency = 1
	side.Position = UDim2.new(1, -margin, 0, margin)
	side.Size = UDim2.fromOffset(200, 220)
	side.Parent = gui
	local sideList = Kit.list(side, Enum.FillDirection.Vertical, 8)
	sideList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	sideList.VerticalAlignment = Enum.VerticalAlignment.Top

	local timerPill = pill({ Name = "Timer", Parent = side, LayoutOrder = 1, Size = UDim2.fromOffset(124, 46) })
	local phaseIcon = iconLabel(timerPill, "☀️", UDim2.new(0, 8, 0.5, 0), 32)
	local timeText = Kit.label({
		Name = "Time",
		Text = "",
		TextScaled = true,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 44, 0.5, 0),
		Size = UDim2.new(1, -54, 0, 28),
		Parent = timerPill,
	})
	textSizeLimit(timeText, 26)
	local nightBadge = Kit.label({
		Name = "NightPay",
		Text = "×" .. tostring(ctx.Config.NightPayMultiplier or 2),
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.Ink,
		BackgroundColor3 = Theme.Colors.Cash,
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.fromOffset(34, 22),
		Visible = false,
		ZIndex = 3,
		Parent = timerPill,
	})
	Kit.corner(nightBadge, 11)

	local visitorChip = pill({
		Name = "Visitor",
		Parent = side,
		LayoutOrder = 2,
		Size = UDim2.fromOffset(92, 52),
		Button = true,
	})
	visitorChip.Visible = false
	iconLabel(visitorChip, "⭐", UDim2.new(0, 8, 0.5, 0), 26)
	local visitorFace = Instance.new("Frame")
	visitorFace.Name = "Face"
	visitorFace.BackgroundTransparency = 1
	visitorFace.AnchorPoint = Vector2.new(1, 0.5)
	visitorFace.Position = UDim2.new(1, -8, 0.5, 0)
	visitorFace.Size = UDim2.fromOffset(44, 44)
	visitorFace.Parent = visitorChip
	local shownVisitor = ""

	-- Rare status chips sit under the wallet: the right edge's middle belongs to the 🎵 and ✨ buttons (Feel).
	local function chip(name: string, text: string, color: Color3, order: number): Frame
		local frame = pill({ Name = name, Parent = wallet, LayoutOrder = order, Size = UDim2.fromOffset(180, 40) })
		frame.BackgroundColor3 = color
		Kit.label({
			Name = "Text",
			Text = text,
			TextScaled = true,
			TextColor3 = Theme.Colors.OnColor,
			TextStrokeColor3 = Kit.shade(color, 0.5),
			TextStrokeTransparency = 0.5,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -20, 0, 24),
			Parent = frame,
		})
		frame.Visible = false
		return frame
	end
	local savingChip = chip("NotSaving", "⚠️ Not saving", Theme.Colors.Danger, 3)
	local noPlotChip = chip("NoClinic", "🏠 Clinics full", Theme.Colors.Secondary, 4)

	--------------------------------------------------------------------------------------------------------------
	-- Bottom centre: hands, then the big buttons (clear of the thumbstick and the jump button)
	--------------------------------------------------------------------------------------------------------------
	local size = Theme.Size.IconButton
	local gap = Theme.Size.Gap
	local bar = Instance.new("Frame")
	bar.Name = "Buttons"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.BackgroundTransparency = 1
	bar.Position = UDim2.new(0.5, 0, 1, -margin)
	bar.Size = UDim2.fromOffset(size * 4 + gap * 3, size)
	bar.Parent = gui
	Kit.list(bar, Enum.FillDirection.Horizontal, gap)

	local buttons: { [string]: TextButton } = {}
	local shopTab: string? = nil -- the Shop opens on the tab its dot is about
	for index, spec in
		{
			{ "Shop", "🛒", "Shop" },
			{ "Book", "📖", "Book" },
			{ "Mailbox", "📭", "Mail" },
			{ "Goals", "🎯", "Goals" },
		}
	do
		local name, icon, caption = spec[1], spec[2], spec[3]
		local button =
			Kit.iconButton({ Name = name, Icon = icon, Caption = caption, LayoutOrder = index, Parent = bar })
		button.Activated:Connect(function()
			if name == "Shop" then
				ctx.fire("Open", name, shopTab)
			else
				ctx.fire("Open", name)
			end
		end)
		buttons[name] = button
	end
	targets.Book = buttons.Book
	targets.Goals = buttons.Goals

	local hands = Instance.new("Frame")
	hands.Name = "Hands"
	hands.AnchorPoint = Vector2.new(0.5, 1)
	hands.BackgroundTransparency = 1
	hands.Position = UDim2.new(0.5, 0, 1, -(margin + size + 10))
	hands.Size = UDim2.fromOffset(0, 50)
	hands.AutomaticSize = Enum.AutomaticSize.X
	hands.Parent = gui
	Kit.list(hands, Enum.FillDirection.Horizontal, 6)

	local slots: { Frame } = {}
	local lastItems: { string } = {}
	local function slot(index: number): Frame
		local frame = Instance.new("Frame")
		frame.Name = "Hand" .. index
		frame.LayoutOrder = index
		frame.Size = UDim2.fromOffset(50, 50)
		frame.BorderSizePixel = 0
		Kit.corner(frame, 14)
		Kit.stroke(frame, Theme.Colors.Stroke, 2.5)
		Kit.label({
			Name = "Icon",
			Text = "",
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.76, 0.76),
			Parent = frame,
		})
		frame.Parent = hands
		return frame
	end

	local function renderHands()
		local items = splitCarry(player:GetAttribute("Carry"))
		local max = player:GetAttribute("CarryMax")
		local count = math.clamp(math.max(if type(max) == "number" then max else 1, #items), 1, 8)
		while #slots < count do
			table.insert(slots, slot(#slots + 1))
		end
		while #slots > count do
			(table.remove(slots) :: Frame):Destroy()
		end
		for index, frame in slots do
			local itemId = items[index]
			local item = itemId and rawget(data.Items, itemId)
			local icon = frame:FindFirstChild("Icon") :: TextLabel
			local stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke
			if item then
				local station = data.Stations[item.Station]
				icon.Text = item.Icon
				frame.BackgroundColor3 = Theme.Colors.Card
				frame.BackgroundTransparency = 0
				stroke.Color = if station then station.Color else Theme.Colors.Stroke
				stroke.Thickness = 3.5
				stroke.Transparency = 0
				if lastItems[index] ~= itemId then
					Hud.pop(frame, 1.35)
				end
			else
				icon.Text = ""
				frame.BackgroundColor3 = Theme.Colors.Paper
				frame.BackgroundTransparency = 0.45
				stroke.Color = Theme.Colors.Stroke
				stroke.Thickness = 2
				stroke.Transparency = 0.55
			end
		end
		lastItems = items
	end
	player:GetAttributeChangedSignal("Carry"):Connect(renderHands)
	player:GetAttributeChangedSignal("CarryMax"):Connect(renderHands)
	renderHands()

	-- Small screens: scale the bottom cluster down a touch, never below the 56 px tap target.
	local bottomScale = Instance.new("UIScale")
	bottomScale.Parent = bar
	local function fit()
		local width = gui.AbsoluteSize.X
		bottomScale.Scale = if width < 420 then 0.8 else 1
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	--------------------------------------------------------------------------------------------------------------
	-- Keeping it current
	--------------------------------------------------------------------------------------------------------------
	local function renderPhase()
		local night = Workspace:GetAttribute("IsNight") == true
		phaseIcon.Text = if night then "🌙" else "☀️"
		nightBadge.Visible = night
		timerPill.BackgroundColor3 = if night then Theme.Colors.Night else Theme.Colors.Card
		timeText.TextColor3 = if night then Theme.Colors.NightText else Theme.Colors.Ink
	end
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(function()
		renderPhase()
		Hud.pop(timerPill, 1.15)
	end)
	renderPhase()

	task.spawn(function()
		local shown = ""
		while gui.Parent do
			local endsAt = Workspace:GetAttribute("PhaseEndsAt")
			local text = ""
			if type(endsAt) == "number" then
				local left = math.max(0, math.floor(endsAt - Workspace:GetServerTimeNow()))
				text = string.format("%d:%02d", left // 60, left % 60)
			end
			if text ~= shown then
				shown = text
				timeText.Text = text
				timerPill.Visible = text ~= ""
			end
			task.wait(0.25)
		end
	end)

	local function renderSaving()
		savingChip.Visible = player:GetAttribute("DataOk") == false
	end
	player:GetAttributeChangedSignal("DataOk"):Connect(renderSaving)
	renderSaving()

	starsPill.Activated:Connect(function()
		if nextTip ~= "" then
			ctx.toast(nextTip)
		end
		Hud.pop(starsPill, 1.08)
	end)
	visitorChip.Activated:Connect(function()
		ctx.toast("⭐ Today's visitor pays " .. tostring(ctx.Config.VisitorMultiplier or 3) .. "×!")
		Hud.pop(visitorChip, 1.1)
	end)

	ctx.on("BookNew", function(count: any)
		Kit.setDot(buttons.Book, type(count) == "number" and count > 0)
	end)

	-- No clinic for a while after loading (all six taken): say so, but don't flash it during the normal assign.
	local plotToken = 0
	local function watchPlot(state: Types.Snapshot)
		plotToken += 1
		local token = plotToken
		if state.PlotIndex ~= nil then
			noPlotChip.Visible = false
			return
		end
		task.delay(4, function()
			if token == plotToken and ctx.State.PlotIndex == nil then
				noPlotChip.Visible = true
			end
		end)
	end

	local loaded = false
	local mailWasReady = false
	local goalsWereReady = false
	ctx.onState(function(state: Types.Snapshot)
		local isServerState = state ~= initial
		local animate = isServerState and loaded
		if isServerState then
			loaded = true
		end

		cash.set(state.Cash or 0, animate)
		stars.set(state.Stars or 0, animate)

		local passed, nextAt, icon, name = starTrack(data, state)
		local ratio = if nextAt then math.clamp(((state.Stars or 0) - passed) / (nextAt - passed), 0, 1) else 1
		nextIcon.Text = icon
		nextTip = if nextAt then icon .. " " .. name .. " at ⭐" .. nextAt else "👑 Everything unlocked!"
		if animate and not Hud.calm() then
			TweenService:Create(fill, Theme.Tween.Release, { Size = UDim2.fromScale(ratio, 1) }):Play()
		else
			fill.Size = UDim2.fromScale(ratio, 1)
		end

		local mailReady = state.MailboxReady == true
		local goalsReady = goalReady(data, state)
		Kit.setDot(buttons.Mailbox, mailReady)
		local mailIcon = buttons.Mailbox:FindFirstChild("Icon")
		if mailIcon and mailIcon:IsA("TextLabel") then
			mailIcon.Text = if mailReady then "📬" else "📭"
		end
		Kit.setDot(buttons.Goals, goalsReady)
		local news = Hud.shopNews(data, state)
		shopTab = if news.Rooms then "Rooms" elseif news.Decor then "Decor" else nil
		Kit.setDot(buttons.Shop, shopTab ~= nil)
		if animate and mailReady and not mailWasReady then
			Hud.shake(buttons.Mailbox)
		end
		if animate and goalsReady and not goalsWereReady then
			Hud.shake(buttons.Goals)
		end
		mailWasReady, goalsWereReady = mailReady, goalsReady

		local visitor = if type(state.TodaysVisitor) == "string" then state.TodaysVisitor else ""
		local look = Hud.lookOf(visitor)
		if visitor ~= shownVisitor then
			shownVisitor = visitor
			visitorFace:ClearAllChildren()
			if look then
				Hud.portrait(look).Parent = visitorFace
			end
		end
		visitorChip.Visible = look ~= nil

		if isServerState then
			watchPlot(state)
		end
	end)
end

return Hud
