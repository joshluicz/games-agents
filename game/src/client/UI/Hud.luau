--!strict
-- Hud (build plan Task 6): the always-on screen, plus the shared UI pieces the other panels build on.
--
-- On screen (all inside the safe area, nothing under the touch thumbstick or jump button):
--   top left      💰 cash · ⭐ stars with a bar to the next unlock (tap it: what's next) · ⚠️ not saving · 🏠 no clinic
--   top right     ☀️/🌙 day-night timer (×2 at night) · ⭐ Today's Visitor (tap: what it means), only when it
--                 can come to your clinic, ✅ once cured today (the Snapshot's VisitorStatus)
--   right middle  ⚙️ settings: a small panel with the comfort switches 🎵 music and ✨ calm effects (the client-only
--                 attributes MusicMuted, read by Music.client, and ReduceEffects, read by Feel and Kit.reducedMotion),
--                 the 👆 Simple mode switch (the saved Data.Simple, asked of the server with SetSimple: every treatment
--                 mini-game becomes one tap; depth update), the owner's helpers switch "👥 Friends only" / "🤝 Anyone
--                 can help" (your plot's OpenHelpers, set by the server through SetHelpers; only while you own a
--                 clinic), plus 🛠️ Admin (opens UI/AdminPanel) only while the server has set the player attribute
--                 IsAdmin. The card grows a row for each of 👥 and 🛠️ and scales its rows down on a short screen
--   bottom centre your hands (the `Carry` attribute: only what you hold, nothing when your hands are empty, each
--                 with a red ✖ to throw it away) above the 🛒 📖 📬 🎯 👩‍⚕️ 🏅 🏆 buttons, each of the first five
--                 with a dot when something waits there (a room you can buy or decor to place · new pages · mail · a
--                 goal · Nurse Journal news); 👩‍⚕️ Nurses opens UI/NursePanel, 🏅 Badges UI/BadgeBook (no dot: its
--                 tier-ups celebrate by themselves) and 🏆 Top the leaderboards (UI/Boards). Seven tabs scale down
--                 together to fit between a phone's thumbstick and jump button, never under 56 px
--   under the wallet  🎁 the daily play gifts (UI/PlayGifts): a bar fills toward the next gift with the play time
--                 left on it ("3m"), "Open!" with a dot when one is ready, ✅ when all are opened
--   beside the clock  a chip per timed boost running (icon + play time left, Data/Boosts); it only counts down while
--                 you play (the PlayTotal attribute), so it never runs out while you're away
-- The 👩‍⚕️ Nurses button, its dot (bus "NursesNew") and the Simple switch are the depth update Foundation's minimal
-- hook (build plan §B9): it fires ctx.fire("Open", "Nurses") and UI/NursePanel does the rest.
-- It reveals itself to a new player (first-session declutter, docs/plan/2026-11-16-first-session-design.md §A3),
-- driven by the Snapshot's Tutorial step: at first only 💰; ⭐ after the first cure; 🛒 at the shop step and 📖 at
-- the Book step (its pointer needs it), each with a bounce; 📬 🎯 👩‍⚕️ 🏅 🏆 🎁, the clock and the visitor chip when
-- the tutorial ends. A player who's done sees everything at once, as before. Until the first snapshot arrives
-- (Tutorial 0, "not known yet") it stays at 💰 only. ⚙️, ⚠️ and 🏠 always show when they apply.
-- Everything is drawn from the Snapshot, player attributes and Workspace attributes. The client never decides
-- anything: buttons only open panels, and panels only ask the server.
--
-- The look is candy pop (memory-20261116-007): every chip is its own bright colour with a glossy top, a thick dark
-- outline and big outlined display-font numbers. 💰 Cash yellow · ⭐ star-to-orange with a candy bar · the clock
-- orange by day and purple by night · Today's Visitor pink (lime once cured) · 🛒 pink · 📖 purple · 📬 blue ·
-- 🎯 lime · 👩‍⚕️ cyan · 🏅 orange · 🏆 yellow · 🎁 pink. Every motion honours Hud.calm().
-- Juice (depth update, design §4): 💰 and ⭐ roll up to their new value (Kit.countUp, ticking), never jump, with a
-- floating "+n"; when coins or stars are flying to the pill (Hud.fly) the roll waits for the first one to land. The
-- mini-game combo (the player attribute Combo, T1) rides the 💰 pill as a 🔥 sticker that grows hotter at each tip
-- step (Config.MiniGame.Combo) and pops away when it resets; it never shows during the tutorial. Panels slide up
-- as they pop in and close with a soft sound.
--
-- Shared helpers (the other UI modules require this module for them; none of them needs Hud.init to have run):
--   Hud.modal(ctx, spec): Modal        a panel or popup shell: dim, paper card with a dark drop shadow, a coloured
--                                      title band (spec.Accent, or the colour of its HUD button), ✖, pop in/out,
--                                      one Panel open at a time, gamepad focus and ButtonB to close
--   Hud.ask(remote, ...): (ok, msg, payload?)   InvokeServer that never throws and gives up after ASK_TIMEOUT
--                                      seconds; payload is a table third value (TreatResult's TreatOutcome)
--   Hud.portrait(look, dark?): Frame   a cute 2D creature face drawn from a Data `Look` (dark = "not met yet")
--   Hud.lookOf(id): Look?              the Look of a PatientId or RegularId
--   Hud.decorSlots(data, state)        every "<RoomId>:<n>" decor slot in your rooms, and what's in it
--   Hud.shopNews(data, state)          { Rooms, Decor, Hospital, Branch }: what the 🛒 dot is about (a room you can
--                                      buy now, level gate included; decor to place; a hospital level-up you can
--                                      afford; Progression v2: Branch = a reward to claim, i.e. a perk card waiting
--                                      or tree points a node can take. NEVER "you can open a branch": no pressure to
--                                      rebirth, red line 3). Branch dots the 🛒 toward its 🏥 tab
--   Hud.fly(from, icon, target?, n?)   icons burst from `from` and arc into a HUD piece (Hud.target name: "Cash",
--                                      "Stars", "Nurses", ...), each landing with a bump and a coin tinkle; with no
--                                      target (or a hidden one) they float up and fade. `from` is a GuiObject, a
--                                      world Vector3 (a cured patient: flying coins) or nil (the screen's middle).
--                                      n defaults to 6, at most 10. Calm: nothing flies (the numbers still update)
--   Hud.pop(gui) · Hud.shake(gui)      a happy bounce · a "nope" wiggle
--   Hud.fitTabs(column, tabs, gap)     square tabs sized to the column (56 to 76 px)
--   Hud.fitHeight(content, area, min?) scales a block down to fit a short screen (not below min, default 0.6)
--   Hud.calm(): boolean                Reduced Motion, or the ✨ calm toggle (ReduceEffects): skip the motion
--   Hud.sound(name, volume?)           a Feel/Sounds cue over the bus
--   Hud.format(n): string              1,234 · 1.2M past a million
--   Hud.target(name): GuiObject?       a HUD piece by name ("Cash", "Stars", "Shop", "Book", "Mailbox", "Goals",
--                                      "Nurses", "Badges", "Boards", "Gifts", "Settings", "Hands"), for pointers
--                                      (UI/Tutorial) and flying icons
--   Hud.isOpen(name?): boolean         a modal is open (that one, or any)
--   Hud.livePlay(state): (save, day, pending)   Data.Playtime as it is right now: the Snapshot's saved part plus
--                                      the live PlayToday/PlayTotal attributes (Server/Playtime), on today's UTC
--                                      day (yesterday's opened gifts don't count); pending = seconds not saved yet
--   Hud.liveBoosts(state): { { Id, Left } }   the timed boosts still running, with their live play time left
--   Hud.boostLine(data, state): string the "Your boosts" summary: timed ones first, then permanent percents
--
-- Client bus (ctx.on / ctx.fire):
--   listens  "BookNew" (count)                      BookPanel: unseen new pages, for the 📖 dot
--   listens  "NursesNew" (count)                    NursePanel: unseen Nurse Journal news, for the 👩‍⚕️ dot
--   fires    "Open" (name, tab?)                    name = "Shop" | "Book" | "Mailbox" | "Goals" | "Nurses" |
--                                                   "Badges" | "Boards" | "Gifts" | "Admin"
--   fires    "ModalOpened" (name) · "ModalClosed" (name)
--   fires    "Sound" (name, volume?)                Whoosh on open, Nope on a shake, Pop when icons land

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local PatientsData = require(Shared:WaitForChild("Data"):WaitForChild("Patients")) :: any
local RegularsData = require(Shared:WaitForChild("Data"):WaitForChild("Regulars")) :: any
local TutorialLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Tutorial"))
local PlaytimeLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Playtime"))
local BoostsLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Boosts"))
local LevelsLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Levels"))
local ProgressLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Progress"))
local TreeLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Tree"))
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Hud = {}

export type Layer = "Panel" | "Popup"
export type ModalSpec = {
	Name: string,
	Title: string?, -- header text: an emoji and at most two words
	Accent: Color3?, -- the header band's colour; default the colour of the HUD button that opens it, else Secondary
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

local SHADOW_OFFSET = 8
local SLIDE_FROM = 36 -- px below its place a panel starts as it pops in
local DIM_BLEED = 400 -- the dim reaches past the safe area so the whole screen darkens (decoration may bleed)
local FLOAT_INFO = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- The big bottom buttons, each its own candy Kind. The panel each one opens wears the same colour on its header.
type Tab = { Name: string, Icon: string, Caption: string, Kind: string, Color: Color3 }
local TABS: { Tab } = {
	{ Name = "Shop", Icon = "🛒", Caption = "Shop", Kind = "Pink", Color = Theme.Colors.Pink },
	{ Name = "Book", Icon = "📖", Caption = "Book", Kind = "Purple", Color = Theme.Colors.Purple },
	{ Name = "Mailbox", Icon = "📭", Caption = "Mail", Kind = "Secondary", Color = Theme.Colors.Secondary },
	{ Name = "Goals", Icon = "🎯", Caption = "Goals", Kind = "Good", Color = Theme.Colors.Good },
	{ Name = "Nurses", Icon = "👩‍⚕️", Caption = "Nurses", Kind = "Cyan", Color = Theme.Colors.Cyan }, -- depth update
	{ Name = "Badges", Icon = "🏅", Caption = "Badges", Kind = "Primary", Color = Theme.Colors.Primary }, -- UI/BadgeBook
	{ Name = "Boards", Icon = "🏆", Caption = "Top", Kind = "Cash", Color = Theme.Colors.Cash }, -- UI/Boards
}
local GIFTS_COLOR = Theme.Colors.Pink -- the 🎁 button and its panel's header

local function tabColor(name: string): Color3?
	for _, tab in TABS do
		if tab.Name == name then
			return tab.Color
		end
	end
	return if name == "Gifts" then GIFTS_COLOR else nil
end

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

-- Kit.punch reuses the UIScale that's already there (Kit buttons have one: two on one object fight) and tells
-- Kit's breathing and dot hops to wait until the bounce is over.
function Hud.pop(gui: GuiObject?, size: number?)
	if not gui or Hud.calm() then
		return
	end
	Kit.punch(gui, size or 1.18, POP_INFO)
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

function Hud.isOpen(name: string?): boolean
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
	shadow.BackgroundColor3 = Theme.Colors.Outline -- a hard, dark sticker shadow
	shadow.BackgroundTransparency = 0.5
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 0
	Kit.corner(shadow, Theme.Size.CornerLarge)
	shadow.Parent = root

	local panel = Kit.panel({
		Name = "Panel",
		Title = spec.Title,
		Accent = spec.Accent or tabColor(spec.Name),
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
		Hud.sound("Close")
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
		-- ... and slides up into place as it pops (calm: just there).
		if Hud.calm() then
			root.Position = UDim2.fromScale(0.5, 0.5)
		else
			root.Position = UDim2.new(0.5, 0, 0.5, SLIDE_FROM)
			TweenService:Create(root, Theme.Tween.Slide, { Position = UDim2.fromScale(0.5, 0.5) }):Play()
		end
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

-- Candy pop: every shape gets the dark Outline, like the rest of the UI.
local SILHOUETTE = Palette.InkSoft -- "not met yet"
local CHEEK = Kit.lighten(Palette.Candy.Pink, 0.3)
local PUPIL = Palette.Outline
local WHITE = Palette.White
local NO_BODY = Kit.lighten(Palette.Candy.Pink, 0.5) -- a Look without a body colour

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

local function outline(frame: Frame)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Palette.Outline
	stroke.Thickness = 2
	stroke.LineJoinMode = Enum.LineJoinMode.Round
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
	local bodyColor = if dark then SILHOUETTE else hex(l.Body, NO_BODY)
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
			outline(ear)
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
			outline(ear)
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
			outline(ear)
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
			outline(ear)
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
			outline(wing)
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
		outline(tail)
	elseif l.Extra == "Spout" then
		local spout =
			blob(frame, "Spout", bodyColor, Vector2.new(right + 0.06, cy), Vector2.new(0.24, 0.11), 1, 0.5, -30)
		outline(spout)
	end
	if l.Shape == "Drop" then
		local tip = blob(frame, "Tip", bodyColor, Vector2.new(cx, top + 0.03), Vector2.one * 0.26, 1, 0.22, 45)
		outline(tip)
	end

	-- The body (z 2).
	local body = blob(frame, "Body", bodyColor, Vector2.new(cx, cy), Vector2.new(w, h), 2, shape.Round)
	outline(body)

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
		mystery.Font = Theme.DisplayFont
		mystery.TextColor3 = Theme.Colors.OnColor
		Kit.outline(mystery)
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

function Hud.target(name: string): GuiObject?
	return targets[name]
end

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

-- A little outlined line that floats up off a HUD piece and fades ("×1.2 💰"). Nothing in calm mode.
local function floatText(anchor: GuiObject, text: string, color: Color3)
	if Hud.calm() then
		return
	end
	local layer = fxLayer()
	local at = centreOf(anchor, layer)
	local label = Kit.label({
		Name = "Float",
		Text = text,
		Outlined = true,
		TextSize = Theme.TextSize.Body,
		TextColor3 = color,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(at.X, at.Y),
		Size = UDim2.fromOffset(160, 34),
		ZIndex = 10,
		Parent = layer,
	})
	local stroke = Kit.outline(label, Theme.Size.Stroke)
	local rise = TweenService:Create(label, FLOAT_INFO, {
		Position = UDim2.fromOffset(at.X, at.Y - 44),
		TextTransparency = 1,
	})
	TweenService:Create(stroke, FLOAT_INFO, { Transparency = 1 }):Play()
	rise.Completed:Once(function()
		label:Destroy()
	end)
	rise:Play()
end

-- Each flying icon bursts out from where it starts, then arcs into its target on a curve (Kit.Juice.arc) that
-- follows the target if the HUD moves under it. One RenderStepped connection draws them all and lets go when the
-- last one lands.
type Flyer = {
	Label: TextLabel,
	Start: Vector2,
	Spread: Vector2,
	Bend: number, -- px the arc bows out sideways (either side)
	Target: string?,
	Born: number, -- os.clock() it launches (staggered)
	Spin: number,
	Batch: { Landed: boolean },
}
local BURST_SECONDS = 0.22
local FLY_SIZE = 36
local LAND_SIZE = 22
local flyers: { Flyer } = {}
local flyConnection: RBXScriptConnection? = nil
local arrivals: { [string]: number } = {} -- target -> os.clock() its first flying icon lands (counters wait)

local function goalPoint(name: string?, layer: ScreenGui): (GuiObject?, Vector2?)
	local gui = if name then targets[name] else nil
	if gui and Kit.isShown(gui) then
		return gui, centreOf(gui, layer)
	end
	return nil, nil
end

-- A world position on this screen, in the fx layer's pixels (nil when it's behind the camera).
local function screenPoint(position: Vector3, layer: ScreenGui): Vector2?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local point, _ = camera:WorldToScreenPoint(position)
	if point.Z <= 0 then
		return nil
	end
	return Vector2.new(point.X, point.Y) - layer.AbsolutePosition
end

local function stepFlyers()
	local layer = fxLayer()
	local now = os.clock()
	local trip = Theme.Juice.FlySeconds
	for index = #flyers, 1, -1 do
		local flyer = flyers[index]
		local label = flyer.Label
		local age = now - flyer.Born
		if age < 0 then
			label.Visible = false
		elseif age < BURST_SECONDS then
			local t = Kit.Juice.ease(age / BURST_SECONDS)
			local at = flyer.Start:Lerp(flyer.Spread, t)
			label.Visible = true
			label.Position = UDim2.fromOffset(at.X, at.Y)
			local px = FLY_SIZE * (0.4 + 0.6 * t)
			label.Size = UDim2.fromOffset(px, px)
		else
			local t = math.min((age - BURST_SECONDS) / trip, 1)
			local goalGui, goal = goalPoint(flyer.Target, layer)
			if goal then
				local eased = t * t -- speeds up into the wallet
				local mid = (flyer.Spread + goal) / 2
				local along = goal - flyer.Spread
				local side = if along.Magnitude > 0 then Vector2.new(-along.Y, along.X).Unit else Vector2.zero
				local control = mid + side * flyer.Bend - Vector2.new(0, 40)
				local x = Kit.Juice.arc(flyer.Spread.X, control.X, goal.X, eased)
				local y = Kit.Juice.arc(flyer.Spread.Y, control.Y, goal.Y, eased)
				label.Position = UDim2.fromOffset(x, y)
				local px = FLY_SIZE + (LAND_SIZE - FLY_SIZE) * eased
				label.Size = UDim2.fromOffset(px, px)
				label.Rotation = flyer.Spin * t
			else
				-- No target (or it's hidden): drift up and fade.
				label.Position = UDim2.fromOffset(flyer.Spread.X, flyer.Spread.Y - 60 * Kit.Juice.ease(t))
				label.TextTransparency = t
			end
			if t >= 1 then
				label:Destroy()
				table.remove(flyers, index)
				if goalGui then
					Hud.pop(goalGui, 1.12)
					Hud.sound(if flyer.Target == "Cash" then "Coin" else "Pop", if flyer.Batch.Landed then 0.6 else 1)
					flyer.Batch.Landed = true
				end
			end
		end
	end
	if #flyers == 0 and flyConnection then
		flyConnection:Disconnect()
		flyConnection = nil
	end
end

function Hud.fly(from: any, icon: string, target: string?, count: number?)
	local layer = fxLayer()
	local goalGui = if target then targets[target] else nil
	if Hud.calm() then
		Hud.pop(goalGui)
		return
	end
	local start: Vector2 = layer.AbsoluteSize / 2
	if typeof(from) == "Instance" and from:IsA("GuiObject") then
		start = centreOf(from, layer)
	elseif typeof(from) == "Vector3" then
		start = screenPoint(from, layer) or Vector2.new(layer.AbsoluteSize.X / 2, layer.AbsoluteSize.Y * 0.7)
	elseif typeof(from) == "Vector2" then
		start = from
	end
	local n = math.clamp(math.floor(count or 6), 1, 10)
	local now = os.clock()
	local batch = { Landed = false }
	local stagger = 0.05
	for i = 1, n do
		local label = Instance.new("TextLabel")
		label.Name = "Fly"
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromOffset(start.X, start.Y)
		label.Size = UDim2.fromOffset(FLY_SIZE * 0.4, FLY_SIZE * 0.4)
		label.BackgroundTransparency = 1
		label.Text = icon
		label.TextScaled = true
		label.Font = Theme.Font
		label.ZIndex = 10
		label.Visible = false
		label.Parent = layer

		local angle = (i / n) * math.pi * 2 + math.random() * 0.6
		local spread = start + Vector2.new(math.cos(angle), math.sin(angle)) * (34 + math.random() * 36)
		table.insert(flyers, {
			Label = label,
			Start = start,
			Spread = spread,
			Bend = (math.random() * 2 - 1) * 90,
			Target = if goalGui then target else nil,
			Born = now + (i - 1) * stagger,
			Spin = (math.random() * 2 - 1) * 180,
			Batch = batch,
		})
	end
	if goalGui and target then
		-- The counter on the target waits for the first icon to land.
		arrivals[target] = math.max(arrivals[target] or 0, now + BURST_SECONDS + Theme.Juice.FlySeconds)
	end
	if not flyConnection then
		flyConnection = RunService.RenderStepped:Connect(stepFlyers)
	end
end

------------------------------------------------------------------------------------------------------------------
-- The HUD itself
------------------------------------------------------------------------------------------------------------------

-- Candy fills are a touch lighter than the base colour, like Kit's buttons, so the gradient can deepen them.
local function candy(color: Color3): Color3
	return Kit.lighten(color, 0.08)
end

-- The gloss: a soft white highlight across a chip's top, inset `inset` px from each end (decoration layer,
-- ZIndex 0, like Kit's buttons: it draws over the chip's fill and under its other children).
local function gloss(gui: GuiObject, inset: number): Frame
	local shine = Instance.new("Frame")
	shine.Name = "Gloss"
	shine.ZIndex = 0
	shine.BackgroundColor3 = Palette.White
	shine.BackgroundTransparency = 0.5
	shine.BorderSizePixel = 0
	shine.Position = UDim2.fromOffset(inset, 3)
	shine.Size = UDim2.new(1, -inset * 2, 0.42, 0)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = shine
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(0.15, 1)
	fade.Parent = shine
	shine.Parent = gui
	return shine
end

-- A candy chip: a bright fill (props.Color, or a top-to-bottom props.Gradient of two colours), a glossy top and a
-- thick dark outline, a full pill at any height.
local function pill(props: { [string]: any }): Frame
	local frame = Instance.new(if props.Button then "TextButton" else "Frame") :: any
	frame.Name = props.Name
	frame.BorderSizePixel = 0
	frame.Size = props.Size or UDim2.fromOffset(120, 46)
	frame.LayoutOrder = props.LayoutOrder or 0
	if props.Button then
		frame.Text = ""
		frame.AutoButtonColor = false
	end
	local height = frame.Size.Y.Offset
	Kit.corner(frame, math.floor(height / 2))
	Kit.stroke(frame, Theme.Colors.Outline, Theme.Size.Stroke)
	if type(props.Gradient) == "table" then
		frame.BackgroundColor3 = Palette.White
		local gradient = Instance.new("UIGradient")
		gradient.Name = "CandyGradient"
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new(candy(props.Gradient[1]), props.Gradient[2])
		gradient.Parent = frame
	else
		frame.BackgroundColor3 = candy(props.Color or Theme.Colors.Secondary)
		Palette.candyGradient(frame)
	end
	gloss(frame, math.floor(height * 0.3))
	frame.Parent = props.Parent
	return frame
end

local function paint(gui: GuiObject, color: Color3)
	gui.BackgroundColor3 = candy(color)
end

-- A big outlined display-font number (white with a dark stroke) on a chip.
local function bigNumber(parent: Instance, name: string, position: UDim2, size: UDim2, max: number): TextLabel
	local label = Kit.label({
		Name = name,
		Text = "",
		Outlined = true,
		TextScaled = true,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = position,
		Size = size,
		Parent = parent,
	})
	Kit.outline(label, Theme.Size.Stroke)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = max
	limit.MinTextSize = 12
	limit.Parent = label
	return label
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

local function splitCarry(raw: any): { string }
	local items = {}
	if type(raw) == "string" then
		for id in string.gmatch(raw, "[^,]+") do
			table.insert(items, id)
		end
	end
	return items
end

-- The ⭐ bar runs from the last star unlock you passed to the next one (a room you don't own and your hospital level
-- allows, the next hospital level's ⭐ gate, or a regular).
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
		consider(
			room.StarsNeeded,
			room.Icon,
			room.Name,
			rooms[roomId] ~= true and inSeason and ProgressLogic.levelAllows(state, room)
		)
	end
	local levels = data.Levels
	if type(levels) == "table" then
		local nextLevel = LevelsLogic.nextRow(levels, state.Level)
		if nextLevel then
			consider(nextLevel.Stars, nextLevel.Icon, nextLevel.Name, true)
		end
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
-- Progression v2 (Foundation hook; T8 restyles the dot): a perk card waiting, or tree points some node can take.
local function branchNews(data: any, state: Types.Snapshot): boolean
	local rebirth = (state :: any).Rebirth
	if type(rebirth) ~= "table" then
		return false
	end
	if type(rebirth.Offer) == "table" and #rebirth.Offer > 0 then
		return true
	end
	local points = if type(rebirth.Points) == "number" then rebirth.Points else 0
	local tree = if type(data.Tree) == "table" then data.Tree.Nodes else nil
	if points <= 0 or type(tree) ~= "table" or type(tree.Order) ~= "table" then
		return false
	end
	for _, nodeId in tree.Order do
		if TreeLogic.canBuy(rebirth.Tree, points, nodeId, tree) then
			return true
		end
	end
	return false
end

function Hud.shopNews(
	data: any,
	state: Types.Snapshot
): { Rooms: boolean, Decor: boolean, Hospital: boolean, Branch: boolean }
	local news = { Rooms = false, Decor = false, Hospital = false, Branch = false }
	if state.PlotIndex == nil then
		return news
	end
	news.Branch = branchNews(data, state)
	for _, roomId in data.Rooms.Order do
		local room = data.Rooms[roomId]
		-- The server's own rule (season, the hospital level a room needs, ⭐ and 💰), so the dot never lights for a
		-- room the Shop would refuse (the Garden below Lv 3).
		if room.Price > 0 and ProgressLogic.canBuyRoom(state, room, roomId, state.IsWinter == true) then
			news.Rooms = true
		end
	end
	if type(data.Levels) == "table" then
		news.Hospital = (LevelsLogic.canLevelUp(state, data.Levels))
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

-- Scales a block of content down (never up) so it fits the height it's given, but never below `minScale` (0.6
-- unless given). The content should have AnchorPoint (0.5, 0), a scale width and AutomaticSize Y.
function Hud.fitHeight(content: GuiObject, area: GuiObject, minScale: number?)
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

-- Calls a client -> server RemoteFunction safely and yields for the answer. Returns (ok, message); message may
-- be "". A server that errors, or doesn't answer within ASK_TIMEOUT seconds, counts as not ok (the call still
-- finishes in the background; the caller just stops waiting for it).
local ASK_TIMEOUT = 10
function Hud.ask(remote: RemoteFunction, ...: any): (boolean, string, any)
	local args = table.pack(...)
	local thread = coroutine.running()
	local done = false
	local function finish(ok: boolean, message: string, payload: any?)
		if not done then
			done = true
			task.spawn(thread, ok, message, payload)
		end
	end
	-- Deferred, so this thread is already waiting below even if the call fails at once.
	task.defer(function()
		local called, result, message, payload = pcall(function()
			return remote:InvokeServer(table.unpack(args, 1, args.n))
		end)
		if not called then
			finish(false, "Oops! Try again.")
		else
			finish(
				result == true,
				if type(message) == "string" then message else "",
				if type(payload) == "table" then payload else nil
			)
		end
	end)
	task.delay(ASK_TIMEOUT, function()
		finish(false, "Oops! Try again.")
	end)
	return coroutine.yield()
end

------------------------------------------------------------------------------------------------------------------
-- Time played and boosts, live (the Snapshot holds the saved part; Server/Playtime's attributes the rest)
------------------------------------------------------------------------------------------------------------------

local function numberAttribute(instance: Instance, name: string): number?
	local value = instance:GetAttribute(name)
	return if type(value) == "number" and value == value then value else nil
end

function Hud.livePlay(state: Types.Snapshot): (PlaytimeLogic.Save, number, number)
	local saved: any = state.Playtime
	if type(saved) ~= "table" then
		saved = { Day = 0, TodaySeconds = 0, TotalSeconds = 0, Claimed = {}, Rank = 0 }
	end
	local player = Players.LocalPlayer
	local day = numberAttribute(Workspace, "UtcDay") or saved.Day
	local total = numberAttribute(player, "PlayTotal") or saved.TotalSeconds or 0
	local liveToday = numberAttribute(player, "PlayToday")
	local sameDay = saved.Day == day
	local save: PlaytimeLogic.Save = {
		Day = day,
		TodaySeconds = liveToday or (if sameDay then saved.TodaySeconds or 0 else 0),
		TotalSeconds = math.max(total, saved.TotalSeconds or 0),
		Claimed = if sameDay and type(saved.Claimed) == "table" then saved.Claimed else {},
		Rank = saved.Rank or 0,
	}
	return save, day, math.max(0, total - (saved.TotalSeconds or 0))
end

function Hud.liveBoosts(state: Types.Snapshot): { { Id: string, Left: number } }
	local _, _, pending = Hud.livePlay(state)
	local out = {}
	local list = state.Boosts and state.Boosts.Timed
	if type(list) == "table" then
		for _, entry in list do
			local left = (if type(entry.Left) == "number" then entry.Left else 0) - pending
			if type(entry.Id) == "string" and left > 0 then
				table.insert(out, { Id = entry.Id, Left = left })
			end
		end
	end
	return out
end

function Hud.boostLine(data: any, state: Types.Snapshot): string
	local parts = {}
	for _, entry in Hud.liveBoosts(state) do
		local def = rawget(data.Boosts, entry.Id)
		if def then
			table.insert(parts, def.Icon .. " " .. PlaytimeLogic.clock(entry.Left))
		end
	end
	local permanent = state.Boosts and state.Boosts.Permanent
	if type(permanent) == "table" then
		for _, kind in BoostsLogic.KINDS do
			local percent = permanent[kind]
			if type(percent) == "number" and percent > 0 then
				table.insert(parts, (BoostsLogic.ICONS :: any)[kind] .. " +" .. math.floor(percent + 0.5) .. "%")
			end
		end
	end
	return if #parts > 0 then "✨ " .. table.concat(parts, "  ") else "✨ No boosts yet: earn badges!"
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

-- A number label that rolls to its new value (Kit.countUp: ticks, springs), and shows a floating "+n" (or "-n").
-- When icons are flying into it (Hud.fly to `target`), the roll waits for the first one to land, so the number
-- moves as the coins arrive. Changes while it waits add up into one roll and one "+n".
type Counter = { set: (value: number, animate: boolean) -> () }
local MAX_ARRIVAL_WAIT = 1.2
local function counter(holder: GuiObject, label: TextLabel, target: string): Counter
	label.Text = "0"
	label:SetAttribute("CountValue", 0)
	local shown = 0 -- the newest value we were given
	local pending = 0 -- change not yet shown as a "+n"
	local waiting = false

	local function floater(delta: number)
		local layer = fxLayer()
		local at = centreOf(holder, layer)
		local text = Kit.label({
			Name = "Delta",
			Text = (if delta > 0 then "+" else "-") .. Hud.format(math.abs(delta)),
			Outlined = true,
			TextSize = Theme.TextSize.Title,
			TextColor3 = if delta > 0 then Theme.Colors.Good else Theme.Colors.Danger,
			TextWrapped = false,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(at.X + holder.AbsoluteSize.X / 2 + 6, at.Y),
			Size = UDim2.fromOffset(150, 40),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 10,
			Parent = layer,
		})
		local stroke = Kit.outline(text, Theme.Size.Stroke)
		local rise = TweenService:Create(text, FLOAT_INFO, {
			Position = UDim2.fromOffset(at.X + holder.AbsoluteSize.X / 2 + 6, at.Y - 34),
			TextTransparency = 1,
		})
		TweenService:Create(stroke, FLOAT_INFO, { Transparency = 1 }):Play()
		rise.Completed:Once(function()
			text:Destroy()
		end)
		rise:Play()
	end

	local function roll()
		waiting = false
		local delta = pending
		pending = 0
		Kit.countUp(label, shown, Hud.format)
		if delta ~= 0 then
			floater(delta)
		end
	end

	return {
		set = function(newValue: number, animate: boolean)
			if newValue == shown then
				return
			end
			pending += newValue - shown
			shown = newValue
			if not animate or Hud.calm() then
				pending = 0
				Kit.countUp(label, newValue, Hud.format, 0)
				return
			end
			if waiting then
				return -- the roll already scheduled picks this up
			end
			local wait = math.clamp((arrivals[target] or 0) - os.clock(), 0, MAX_ARRIVAL_WAIT)
			if wait > 0.02 then
				waiting = true
				task.delay(wait, roll)
			else
				roll()
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
	wallet.Size = UDim2.fromOffset(210, 312) -- cash, stars, the rare status chips, then the 🎁 play gifts
	wallet.Parent = gui
	local walletList = Kit.list(wallet, Enum.FillDirection.Vertical, 8)
	walletList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	walletList.VerticalAlignment = Enum.VerticalAlignment.Top

	local cashPill = pill({
		Name = "Cash",
		Parent = wallet,
		LayoutOrder = 1,
		Color = Theme.Colors.Cash,
		Size = UDim2.fromOffset(170, 52),
	})
	iconLabel(cashPill, "💰", UDim2.new(0, 8, 0.5, 0), 36)
	local cashText = bigNumber(cashPill, "Amount", UDim2.new(0, 50, 0.5, 1), UDim2.new(1, -64, 0, 36), 34)
	targets.Cash = cashPill
	local cash = counter(cashPill, cashText, "Cash")

	-- The mini-game combo: a tilted 🔥 sticker on the cash pill's corner (Perfects in a row multiply tips). Orange,
	-- then pink, purple and gold at each Config.MiniGame.Combo step. Display only: the server owns the combo.
	local COMBO_COLORS = { Theme.Colors.Primary, Theme.Colors.Pink, Theme.Colors.Purple, Theme.Colors.Cash }
	local comboSticker = Kit.label({
		Name = "Combo",
		Text = "",
		Outlined = true,
		TextScaled = true,
		TextWrapped = false,
		BackgroundColor3 = candy(Theme.Colors.Primary),
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -8, 0, 2),
		Size = UDim2.fromOffset(58, 30),
		Rotation = 8,
		Visible = false,
		ZIndex = 3,
		Parent = cashPill,
	})
	Kit.corner(comboSticker, 15)
	Kit.stroke(comboSticker, Theme.Colors.Outline, 2.5)
	local comboPad = Kit.pad(comboSticker, 3)
	comboPad.PaddingLeft = UDim.new(0, 6)
	comboPad.PaddingRight = UDim.new(0, 6)

	-- Tappable (shows what's next), so it gets the full 56 px tap height. Star yellow melting into orange.
	local starsPill = pill({
		Name = "Stars",
		Parent = wallet,
		LayoutOrder = 2,
		Gradient = { Theme.Colors.Star, Theme.Colors.Primary },
		Size = UDim2.fromOffset(210, Theme.Size.ButtonHeight),
		Button = true,
	})
	iconLabel(starsPill, "⭐", UDim2.new(0, 8, 0.5, 0), 34)
	local starsText = bigNumber(starsPill, "Amount", UDim2.new(0, 46, 0.5, 1), UDim2.fromOffset(50, 34), 32)
	targets.Stars = starsPill
	local stars = counter(starsPill, starsText, "Stars")

	-- The candy bar: a dark outlined slot with a glossy star-yellow fill.
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, 100, 0.5, 0)
	track.Size = UDim2.new(1, -100 - 44, 0, 18)
	track.BackgroundColor3 = Theme.Colors.Outline
	track.BackgroundTransparency = 0.35
	track.BorderSizePixel = 0
	Kit.corner(track, 9)
	Kit.stroke(track, Theme.Colors.Outline, 2.5)
	track.Parent = starsPill
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = candy(Theme.Colors.Star)
	fill.BorderSizePixel = 0
	fill.ClipsDescendants = true -- an empty bar shows no sliver of gloss
	Kit.corner(fill, 9)
	Palette.candyGradient(fill)
	gloss(fill, 4)
	fill.Parent = track
	local nextIcon = Kit.label({
		Name = "Next",
		Text = "👑",
		TextScaled = true,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(32, 32),
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
	side.Size = UDim2.fromOffset(420, 220) -- the boost chips sit left of the clock, so the column stays short
	side.Parent = gui
	local sideList = Kit.list(side, Enum.FillDirection.Vertical, 8)
	sideList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	sideList.VerticalAlignment = Enum.VerticalAlignment.Top

	-- The top row: the timed boost chips (renderBoosts), then the clock at the right edge.
	local topRow = Instance.new("Frame")
	topRow.Name = "TopRow"
	topRow.BackgroundTransparency = 1
	topRow.LayoutOrder = 1
	topRow.Size = UDim2.fromOffset(420, 52)
	topRow.Parent = side
	local topList = Kit.list(topRow, Enum.FillDirection.Horizontal, 8)
	topList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local boostRow = Instance.new("Frame")
	boostRow.Name = "Boosts"
	boostRow.BackgroundTransparency = 1
	boostRow.LayoutOrder = 1
	boostRow.Size = UDim2.fromOffset(0, 40)
	boostRow.AutomaticSize = Enum.AutomaticSize.X
	boostRow.Visible = false
	boostRow.Parent = topRow
	Kit.list(boostRow, Enum.FillDirection.Horizontal, 6)

	-- Orange by day, purple by night (renderPhase).
	local timerPill = pill({
		Name = "Timer",
		Parent = topRow,
		LayoutOrder = 2,
		Color = Theme.Colors.Primary,
		Size = UDim2.fromOffset(136, 52),
	})
	local phaseIcon = iconLabel(timerPill, "☀️", UDim2.new(0, 8, 0.5, 0), 36)
	local timeText = bigNumber(timerPill, "Time", UDim2.new(0, 50, 0.5, 1), UDim2.new(1, -64, 0, 34), 32)
	-- The night pay sticker: a tilted yellow tag on the clock's corner.
	local nightBadge = Kit.label({
		Name = "NightPay",
		Text = "×" .. tostring(ctx.Config.NightPayMultiplier or 2),
		Outlined = true,
		TextSize = Theme.TextSize.Small,
		TextWrapped = false,
		BackgroundColor3 = candy(Theme.Colors.Cash),
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.fromOffset(40, 26),
		Rotation = -10,
		Visible = false,
		ZIndex = 3,
		Parent = timerPill,
	})
	Kit.corner(nightBadge, 13)
	Kit.stroke(nightBadge, Theme.Colors.Outline, 2.5)

	-- Pink while the visitor can come; lime with ✅ once it's cured today.
	local visitorChip = pill({
		Name = "Visitor",
		Parent = side,
		LayoutOrder = 2,
		Color = Theme.Colors.Pink,
		Size = UDim2.fromOffset(96, Theme.Size.ButtonHeight),
		Button = true,
	})
	visitorChip.Visible = false
	local visitorMark = iconLabel(visitorChip, "⭐", UDim2.new(0, 8, 0.5, 0), 30) -- ✅ once cured today
	local faceDisc = Instance.new("Frame") -- a white outlined disc, so any creature colour reads on the pink
	faceDisc.Name = "FaceDisc"
	faceDisc.AnchorPoint = Vector2.new(1, 0.5)
	faceDisc.Position = UDim2.new(1, -6, 0.5, 0)
	faceDisc.Size = UDim2.fromOffset(44, 44)
	faceDisc.BackgroundColor3 = Palette.White
	faceDisc.BorderSizePixel = 0
	Kit.corner(faceDisc, 22)
	Kit.stroke(faceDisc, Theme.Colors.Outline, 2.5)
	faceDisc.Parent = visitorChip
	local visitorFace = Instance.new("Frame")
	visitorFace.Name = "Face"
	visitorFace.BackgroundTransparency = 1
	visitorFace.Size = UDim2.fromScale(1, 1)
	visitorFace.Parent = faceDisc
	local shownVisitor = ""

	-- Rare status chips sit under the wallet: the right edge's middle belongs to the ⚙️ settings button.
	local function chip(name: string, text: string, color: Color3, order: number): Frame
		local frame = pill({
			Name = name,
			Parent = wallet,
			LayoutOrder = order,
			Color = color,
			Size = UDim2.fromOffset(200, 40),
		})
		Kit.label({
			Name = "Text",
			Text = text,
			Outlined = true,
			Font = Theme.Font, -- the round body font: a few words must stay at 18 px or more
			TextScaled = true,
			TextWrapped = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -24, 0, 26),
			Parent = frame,
		})
		frame.Visible = false
		return frame
	end
	local savingChip = chip("NotSaving", "⚠️ Not saving", Theme.Colors.Danger, 3)
	local noPlotChip = chip("NoClinic", "🏠 Clinics full", Theme.Colors.Secondary, 4)

	-- 🎁 The daily play gifts (UI/PlayGifts opens on "Open" "Gifts"): the button, and under it a candy progress bar
	-- that fills toward the next gift with the time left in it (renderGifts). It isn't a countdown to anything you
	-- could miss.
	local giftHolder = Instance.new("Frame")
	giftHolder.Name = "GiftsHolder"
	giftHolder.BackgroundTransparency = 1
	giftHolder.LayoutOrder = 5
	giftHolder.Size = UDim2.fromOffset(84, 92)
	giftHolder.Parent = wallet
	local giftButton = Kit.iconButton({
		Name = "Gifts",
		Icon = "🎁",
		Caption = "",
		Kind = "Pink",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(70, 70),
		Parent = giftHolder,
	})
	local giftBar = Instance.new("Frame")
	giftBar.Name = "GiftBar"
	giftBar.AnchorPoint = Vector2.new(0.5, 1)
	giftBar.Position = UDim2.fromScale(0.5, 1)
	giftBar.Size = UDim2.fromOffset(80, 26)
	giftBar.BackgroundColor3 = Palette.White
	giftBar.BorderSizePixel = 0
	giftBar.ZIndex = 4
	Kit.corner(giftBar, 13)
	Kit.stroke(giftBar, Theme.Colors.Outline, Theme.Size.Stroke)
	giftBar.Parent = giftHolder
	local giftFill = Instance.new("Frame")
	giftFill.Name = "Fill"
	giftFill.Size = UDim2.fromScale(0, 1)
	giftFill.BackgroundColor3 = Theme.Colors.Cash
	giftFill.BorderSizePixel = 0
	giftFill.ZIndex = 4
	Kit.corner(giftFill, 13)
	Palette.candyGradient(giftFill)
	giftFill.Parent = giftBar
	local giftTime = Kit.label({
		Name = "Time",
		Text = "",
		Outlined = true,
		TextSize = Theme.TextSize.Small,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = giftBar,
	})
	targets.Gifts = giftButton
	giftButton.Activated:Connect(function()
		ctx.fire("Open", "Gifts")
	end)

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
	local barWidth = size * #TABS + gap * (#TABS - 1) -- 7 tabs: 7 x 76 + 6 x 10 = 592 px at full size
	bar.Size = UDim2.fromOffset(barWidth, size)
	bar.Parent = gui
	Kit.list(bar, Enum.FillDirection.Horizontal, gap)

	-- The "something new" dot, made bigger, with a white "!" so it reads on every candy colour (pink included).
	local function badge(button: GuiObject)
		local dot = button:FindFirstChild("Dot")
		if not (dot and dot:IsA("GuiObject")) then
			return
		end
		dot.Size = UDim2.fromOffset(Theme.Size.Dot + 6, Theme.Size.Dot + 6)
		local mark = Kit.label({
			Name = "Mark",
			Text = "!",
			Outlined = true,
			TextSize = Theme.TextSize.Small,
			TextWrapped = false,
			Size = UDim2.fromScale(1, 1),
			ZIndex = dot.ZIndex + 1,
			Parent = dot,
		})
		Kit.outline(mark, 2)
	end

	local buttons: { [string]: TextButton } = {}
	local shopTab: string? = nil -- the Shop opens on the tab its dot is about
	for index, tab in TABS do
		local name = tab.Name
		local button = Kit.iconButton({
			Name = name,
			Icon = tab.Icon,
			Caption = tab.Caption,
			Kind = tab.Kind,
			LayoutOrder = index,
			Parent = bar,
		})
		badge(button)
		button.Activated:Connect(function()
			if name == "Shop" then
				-- The tutorial's shop step points at the cheapest upgrade, so it opens on Upgrades.
				local tutorial = TutorialLogic.active(ctx.State.Tutorial)
				ctx.fire("Open", name, if tutorial then "Upgrades" else shopTab)
			else
				ctx.fire("Open", name)
			end
		end)
		buttons[name] = button
	end
	targets.Shop = buttons.Shop
	targets.Book = buttons.Book
	targets.Mailbox = buttons.Mailbox
	targets.Goals = buttons.Goals
	targets.Nurses = buttons.Nurses
	targets.Badges = buttons.Badges
	targets.Boards = buttons.Boards
	badge(giftButton)

	local hands = Instance.new("Frame")
	hands.Name = "Hands"
	hands.AnchorPoint = Vector2.new(0.5, 1)
	hands.BackgroundTransparency = 1
	hands.Position = UDim2.new(0.5, 0, 1, -(margin + size + 10))
	hands.Size = UDim2.fromOffset(0, 50)
	hands.AutomaticSize = Enum.AutomaticSize.X
	hands.Visible = false
	hands.Parent = gui
	Kit.list(hands, Enum.FillDirection.Horizontal, 6)
	targets.Hands = hands

	-- Each hand: a big white disc with what you hold, ringed in the colour of the station that made it, and a red ✖
	-- (top right) that throws it away (the Discard remote), so an unneeded item never leaves you stuck. Only what you
	-- hold shows: empty hands draw nothing (first-session declutter, design §A5).
	local HAND = 84
	hands.Size = UDim2.fromOffset(0, HAND)
	local slots: { Frame } = {}
	local lastItems: { string } = {}
	local function slot(index: number): Frame
		local frame = Instance.new("Frame")
		frame.Name = "Hand" .. index
		frame.LayoutOrder = index
		frame.Size = UDim2.fromOffset(HAND, HAND)
		frame.BorderSizePixel = 0
		Kit.corner(frame, HAND)
		Kit.stroke(frame, Theme.Colors.Outline, Theme.Size.Stroke).Name = "Outline"
		local plate = Instance.new("Frame") -- the white middle
		plate.Name = "Plate"
		plate.AnchorPoint = Vector2.new(0.5, 0.5)
		plate.Position = UDim2.fromScale(0.5, 0.5)
		plate.Size = UDim2.fromScale(0.78, 0.78)
		plate.BackgroundColor3 = Theme.Colors.Paper
		plate.BorderSizePixel = 0
		Kit.corner(plate, HAND)
		Kit.stroke(plate, Theme.Colors.Outline, 2)
		plate.Parent = frame
		Kit.label({
			Name = "Icon",
			Text = "",
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.62, 0.62),
			ZIndex = 2,
			Parent = frame,
		})
		local throw = Instance.new("TextButton")
		throw.Name = "Discard"
		throw.AnchorPoint = Vector2.new(0.5, 0.5)
		throw.Position = UDim2.fromScale(0.86, 0.14)
		throw.Size = UDim2.fromOffset(40, 40)
		throw.BackgroundColor3 = Theme.Colors.Danger
		throw.AutoButtonColor = false
		throw.BorderSizePixel = 0
		throw.Font = Theme.DisplayFont
		throw.Text = "✖"
		throw.TextSize = 22
		throw.TextColor3 = Theme.Colors.OnColor
		throw.ZIndex = 3
		Kit.corner(throw, 40)
		Kit.stroke(throw, Theme.Colors.Outline, Theme.Size.Stroke)
		Kit.outline(throw, 2)
		throw.Parent = frame
		local busy = false
		throw.Activated:Connect(function()
			local itemId = lastItems[index]
			if busy or not itemId then
				return
			end
			busy = true
			Kit.Clicked:Fire(throw)
			Hud.pop(frame, 0.8)
			task.spawn(function()
				Hud.ask(ctx.Remotes.Discard, itemId)
				busy = false
			end)
		end)
		frame.Parent = hands
		return frame
	end

	local function renderHands()
		local items = splitCarry(player:GetAttribute("Carry"))
		local count = math.min(#items, 8)
		hands.Visible = count > 0
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
			local throw = frame:FindFirstChild("Discard") :: TextButton
			if item then
				local station = data.Stations[item.Station]
				icon.Text = item.Icon
				frame.BackgroundColor3 = if station then station.Color else Theme.Colors.Secondary
				throw.Visible = true
				if lastItems[index] ~= itemId then
					Hud.pop(frame, 1.35)
				end
			else
				icon.Text = ""
				frame.BackgroundColor3 = Theme.Colors.Paper
				throw.Visible = false
			end
		end
		lastItems = items
	end
	player:GetAttributeChangedSignal("Carry"):Connect(renderHands)
	renderHands()

	-- The hands sit just above the big buttons, or at the bottom while none of them shows yet (a new player).
	local function placeHands()
		local anyButton = false
		for _, button in buttons do
			anyButton = anyButton or button.Visible
		end
		hands.Position = UDim2.new(0.5, 0, 1, -(if anyButton then margin + size + 10 else margin))
	end

	--------------------------------------------------------------------------------------------------------------
	-- Right edge, half way down: ⚙️ settings, a small panel with the two comfort switches (what used to be the 🎵 and
	-- ✨ buttons), the owner's 👥 helpers switch and, for admins, 🛠️ Admin. Music.client follows MusicMuted and
	-- Feel/Atmosphere follows ReduceEffects, as before.
	--------------------------------------------------------------------------------------------------------------
	local settingsButton = Kit.iconButton({
		Name = "Settings",
		Icon = "⚙️",
		Kind = "Quiet",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -margin, 0.5, 0),
		Size = UDim2.fromOffset(Theme.Size.ButtonHeight, Theme.Size.ButtonHeight),
		Parent = gui,
	})
	targets.Settings = settingsButton
	local settings = Hud.modal(ctx, {
		Name = "Settings",
		Title = "⚙️ Settings",
		Accent = Theme.Colors.Cyan,
		MaxSize = Vector2.new(380, 350),
	})
	-- One column of switches, scaled down to fit a short landscape phone when the 👥 and 🛠️ rows both show.
	local switches = Instance.new("Frame")
	switches.Name = "Switches"
	switches.BackgroundTransparency = 1
	switches.AnchorPoint = Vector2.new(0.5, 0)
	switches.Position = UDim2.fromScale(0.5, 0)
	switches.Size = UDim2.fromScale(1, 0)
	switches.AutomaticSize = Enum.AutomaticSize.Y
	switches.Parent = settings.Body
	local switchList = Kit.list(switches, Enum.FillDirection.Vertical, gap)
	switchList.VerticalAlignment = Enum.VerticalAlignment.Top
	Hud.fitHeight(switches, settings.Body, 0.5)
	local function switch(name: string, kind: string, order: number): TextButton
		local button = Kit.button({
			Name = name,
			Kind = kind,
			TextSize = Theme.TextSize.Body,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, Theme.Size.ButtonHeight + 8),
			Parent = switches,
		})
		return button
	end
	local musicSwitch = switch("Music", "Pink", 1)
	local effectsSwitch = switch("Effects", "Cyan", 2)
	local simpleSwitch = switch("Simple", "Good", 3) -- depth update: Simple mode (saved; the server rates it)
	settings.Focus = musicSwitch
	-- 👥 Who may work at your clinic: only while you own one (see below).
	local helpersSwitch = switch("Helpers", "Good", 4)
	helpersSwitch.Visible = false
	-- 🛠️ Admin: only for the accounts the server marks IsAdmin (Server/Admin). It just opens UI/AdminPanel, whose every
	-- button the server checks again.
	local adminButton = switch("Admin", "Purple", 5)
	adminButton.Text = "🛠️ Admin"
	-- The card is three rows tall (🎵, ✨, 👆 Simple), and grows a row for each of 👥 and 🛠️ that shows: 280 px held
	-- the first two rows, each row is a switch plus the gap. On a short landscape phone the card is cut to the screen
	-- and Hud.fitHeight scales the rows down to fit (to half size at the most, for an admin who owns a clinic).
	local settingsLimit = settings.Root:FindFirstChildOfClass("UISizeConstraint")
	local function fitSettings()
		local rows = 1 -- 👆 Simple, always there
		for _, extra in { helpersSwitch, adminButton } do
			if extra.Visible then
				rows += 1
			end
		end
		if settingsLimit then
			settingsLimit.MaxSize = Vector2.new(380, 280 + rows * (Theme.Size.ButtonHeight + 8 + gap))
		end
	end
	local function renderAdmin()
		adminButton.Visible = player:GetAttribute("IsAdmin") == true
		fitSettings()
	end
	player:GetAttributeChangedSignal("IsAdmin"):Connect(renderAdmin)
	renderAdmin()
	adminButton.Activated:Connect(function()
		if player:GetAttribute("IsAdmin") == true then
			ctx.fire("Open", "Admin") -- a Panel: opening it closes ⚙️
		end
	end)
	local function paintSwitch(button: TextButton, on: boolean, color: Color3)
		local switchFill = if on then Kit.lighten(color, 0.08) else Theme.Colors.Quiet
		button.BackgroundColor3 = switchFill
		button:SetAttribute("KitColor", switchFill)
	end

	-- 👥 The helpers switch (it used to be a prompt on the sign, which covered the scene). Off = "👥 Friends only"
	-- (only you and your Roblox friends may work at your clinic), on = "🤝 Anyone can help". It shows your plot's
	-- OpenHelpers attribute; a tap asks the server (SetHelpers, Server/Visits), which checks you own the plot, switches
	-- it and toasts. Hidden while you have no clinic.
	local function myClinic(): Model?
		local index = player:GetAttribute("PlotIndex")
		local clinics = Workspace:FindFirstChild("Clinics")
		local plot = if type(index) == "number" and clinics then clinics:FindFirstChild("Plot_" .. index) else nil
		return if plot and plot:IsA("Model") then plot else nil
	end
	local function renderHelpers()
		local plot = myClinic()
		local open = plot ~= nil and plot:GetAttribute("OpenHelpers") == true
		helpersSwitch.Visible = plot ~= nil
		helpersSwitch.Text = if open then "🤝 Anyone can help" else "👥 Friends only"
		paintSwitch(helpersSwitch, open, Theme.Colors.Good)
		fitSettings()
	end
	local helpersWatch: RBXScriptConnection? = nil
	local function watchHelpers()
		if helpersWatch then
			helpersWatch:Disconnect()
			helpersWatch = nil
		end
		local plot = myClinic()
		if plot then
			helpersWatch = plot:GetAttributeChangedSignal("OpenHelpers"):Connect(renderHelpers)
		end
		renderHelpers()
	end
	player:GetAttributeChangedSignal("PlotIndex"):Connect(watchHelpers)
	task.spawn(function()
		if Workspace:WaitForChild("Clinics", 30) then -- the town may arrive after the HUD
			watchHelpers()
		end
	end)
	local helpersBusy = false
	helpersSwitch.Activated:Connect(function()
		local plot = myClinic()
		if helpersBusy or not plot then
			return
		end
		helpersBusy = true
		Hud.pop(helpersSwitch, 1.06)
		local ok, message = Hud.ask(ctx.Remotes.SetHelpers, plot:GetAttribute("OpenHelpers") ~= true)
		helpersBusy = false
		if not ok then
			Hud.shake(helpersSwitch)
			if message ~= "" then
				ctx.toast(message)
			end
		end
		renderHelpers()
	end)
	local function calmOn(): boolean
		local value = player:GetAttribute("ReduceEffects")
		return if value == nil then Kit.reducedMotion() else value == true
	end
	local function renderSettings()
		local muted = player:GetAttribute("MusicMuted") == true
		musicSwitch.Text = if muted then "🔇 Music off" else "🎵 Music on"
		paintSwitch(musicSwitch, not muted, Theme.Colors.Pink)
		local calmNow = calmOn()
		effectsSwitch.Text = if calmNow then "💤 Calm effects" else "✨ Full effects"
		paintSwitch(effectsSwitch, not calmNow, Theme.Colors.Cyan)
		local simple = ctx.State.Simple == true
		simpleSwitch.Text = if simple then "👆 Simple taps" else "🎮 Mini-games"
		paintSwitch(simpleSwitch, not simple, Theme.Colors.Good)
	end
	musicSwitch.Activated:Connect(function()
		player:SetAttribute("MusicMuted", player:GetAttribute("MusicMuted") ~= true)
		Hud.pop(musicSwitch, 1.06)
	end)
	effectsSwitch.Activated:Connect(function()
		player:SetAttribute("ReduceEffects", not calmOn())
		Hud.pop(effectsSwitch, 1.06)
	end)
	local askingSimple = false
	simpleSwitch.Activated:Connect(function()
		if askingSimple then
			return
		end
		askingSimple = true
		Hud.pop(simpleSwitch, 1.06)
		local ok, message = Hud.ask(ctx.Remotes.SetSimple, ctx.State.Simple ~= true)
		askingSimple = false
		if not ok and message ~= "" then
			ctx.toast(message)
		end
	end)
	ctx.onState(function()
		renderSettings()
	end)
	player:GetAttributeChangedSignal("MusicMuted"):Connect(renderSettings)
	player:GetAttributeChangedSignal("ReduceEffects"):Connect(renderSettings)
	renderSettings()
	settingsButton.Activated:Connect(function()
		renderSettings()
		watchHelpers() -- in case your clinic streamed in since
		settings.toggle()
	end)

	-- Small screens: scale the bottom cluster down so it keeps 100 px clear on each side (a phone's touch jump button
	-- sits 95 px in from the right edge, its thumbstick as far in from the left), never below the 56 px tap target
	-- (minScale = 56 / 76 ≈ 0.737). Seven tabs: full size from 792 px wide (592 + 200), the floor (436 px of bar)
	-- below 636 px; a 667 px phone gets 0.79 (60 px buttons), an 844 px one full size.
	local bottomScale = Instance.new("UIScale")
	bottomScale.Parent = bar
	local minScale = Theme.Size.ButtonHeight / size
	local function fit()
		local width = gui.AbsoluteSize.X
		bottomScale.Scale = math.clamp((width - 200) / barWidth, minScale, 1)
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
		paint(timerPill, if night then Theme.Colors.Purple else Theme.Colors.Primary)
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

	-- (Not shown for the Studio FreshSave test switch, so the screen looks like a real first visit.)
	local function renderSaving()
		savingChip.Visible = player:GetAttribute("DataOk") == false and player:GetAttribute("FreshSave") ~= true
	end
	player:GetAttributeChangedSignal("DataOk"):Connect(renderSaving)
	player:GetAttributeChangedSignal("FreshSave"):Connect(renderSaving)
	renderSaving()

	starsPill.Activated:Connect(function()
		if nextTip ~= "" then
			ctx.toast(nextTip)
		end
		Hud.pop(starsPill, 1.08)
	end)
	visitorChip.Activated:Connect(function()
		if ctx.State.VisitorStatus == "Done" then
			ctx.toast("✅ Visitor cured! New one tomorrow")
		else
			ctx.toast("⭐ Today's visitor pays " .. tostring(ctx.Config.VisitorMultiplier or 3) .. "×!")
		end
		Hud.pop(visitorChip, 1.1)
	end)

	ctx.on("BookNew", function(count: any)
		Kit.setDot(buttons.Book, type(count) == "number" and count > 0)
	end)
	ctx.on("NursesNew", function(count: any)
		Kit.setDot(buttons.Nurses, type(count) == "number" and count > 0)
	end)

	-- The 🔥 combo sticker follows the player attribute Combo (T1, session-only). Hidden during the tutorial.
	local comboSteps = (ctx.Config.MiniGame and ctx.Config.MiniGame.Combo) or {}
	local comboShown = 0
	local function renderCombo()
		local raw = player:GetAttribute("Combo")
		local combo = if type(raw) == "number" and raw == raw then math.max(0, math.floor(raw)) else 0
		if TutorialLogic.active(ctx.State.Tutorial) then
			combo = 0
		end
		local before = comboShown
		comboShown = combo
		if combo <= 0 then
			if comboSticker.Visible then
				if Hud.calm() then
					comboSticker.Visible = false
				else
					Kit.popOut(comboSticker)
				end
			end
			return
		end
		local tier, multiplier = Kit.Juice.comboStep(combo, comboSteps)
		comboSticker.Text = "🔥" .. combo
		paint(comboSticker, COMBO_COLORS[math.clamp(tier + 1, 1, #COMBO_COLORS)])
		if not comboSticker.Visible or before == 0 then
			Kit.popIn(comboSticker)
		elseif combo > before then
			Hud.pop(comboSticker, 1.35)
		end
		if Kit.Juice.crossed(before, combo, comboSteps) then
			floatText(comboSticker, "×" .. tostring(multiplier) .. " 💰", Theme.Colors.Cash)
		end
	end
	player:GetAttributeChangedSignal("Combo"):Connect(renderCombo)
	ctx.onState(function()
		if comboShown > 0 and TutorialLogic.active(ctx.State.Tutorial) then
			renderCombo()
		end
	end)
	renderCombo()

	--------------------------------------------------------------------------------------------------------------
	-- Play gifts and timed boosts, live: the server's PlayToday/PlayTotal attributes move every second of play
	--------------------------------------------------------------------------------------------------------------
	local gifts = data.Playtime.Gifts
	local giftsWereReady = false
	local giftsShown = false -- the first render after the save loads never shakes
	local function renderGifts()
		local state = ctx.State
		if type(state.Playtime) ~= "table" then
			return
		end
		local save, day = Hud.livePlay(state)
		local ready = #PlaytimeLogic.ready(save, day, gifts) > 0
		local nextIndex, left = PlaytimeLogic.nextGift(save, day, gifts)
		local ratio = 1
		if nextIndex then
			local goal = PlaytimeLogic.giftSeconds(gifts[nextIndex])
			local from = if nextIndex > 1 then PlaytimeLogic.giftSeconds(gifts[nextIndex - 1]) else 0
			ratio = math.clamp((save.TodaySeconds - from) / math.max(1, goal - from), 0, 1)
		end
		local full = ready or not nextIndex
		giftFill.Size = UDim2.fromScale(if full then 1 else math.max(ratio, 0.08), 1)
		giftFill.BackgroundColor3 = if ready then Theme.Colors.Good else Theme.Colors.Cash
		giftTime.Text = if ready
			then "OPEN!"
			elseif nextIndex then PlaytimeLogic.duration(math.max(60, left))
			else "✅ Done"
		Kit.setDot(giftButton, ready)
		if ready and not giftsWereReady and giftsShown and giftHolder.Visible then
			Hud.shake(giftButton)
		end
		giftsWereReady = ready
		giftsShown = state ~= initial
	end

	-- A chip per timed boost: its icon and the play time it has left, in its kind's colour.
	local BOOST_COLORS: { [string]: Color3 } = {
		MakeSpeed = Theme.Colors.Cyan,
		Tips = Theme.Colors.Good,
		Stars = Theme.Colors.Purple,
		Cash = Theme.Colors.Cash,
		Patience = Theme.Colors.Secondary,
	}
	local boostChips: { [string]: Frame } = {}
	local function renderBoosts()
		local live = Hud.liveBoosts(ctx.State)
		local seen: { [string]: boolean } = {}
		for index, entry in live do
			local def = rawget(data.Boosts, entry.Id)
			if not def then
				continue
			end
			seen[entry.Id] = true
			local chipFrame = boostChips[entry.Id]
			if not chipFrame then
				chipFrame = pill({
					Name = entry.Id,
					Parent = boostRow,
					Color = BOOST_COLORS[def.Kind] or Theme.Colors.Secondary,
					Size = UDim2.fromOffset(92, 40),
				})
				Kit.label({
					Name = "Text",
					Text = "",
					Outlined = true,
					TextScaled = true,
					TextWrapped = false,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.new(1, -16, 0, 26),
					Parent = chipFrame,
				})
				boostChips[entry.Id] = chipFrame
				Hud.pop(chipFrame, 1.3)
			end
			local chipFrame2 = chipFrame :: Frame
			chipFrame2.LayoutOrder = index
			local text = chipFrame2:FindFirstChild("Text") :: TextLabel?
			if text then
				text.Text = def.Icon .. " " .. PlaytimeLogic.clock(entry.Left)
			end
		end
		for id, chipFrame in boostChips do
			if not seen[id] then
				chipFrame:Destroy()
				boostChips[id] = nil
			end
		end
		boostRow.Visible = next(boostChips) ~= nil
	end

	local function renderPlay()
		renderGifts()
		renderBoosts()
	end
	for _, attribute in { "PlayToday", "PlayTotal" } do
		player:GetAttributeChangedSignal(attribute):Connect(renderPlay)
	end
	Workspace:GetAttributeChangedSignal("UtcDay"):Connect(renderPlay)

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

	--------------------------------------------------------------------------------------------------------------
	-- The reveal: a new player's HUD grows with their tutorial step (see the header)
	--------------------------------------------------------------------------------------------------------------
	-- (📖 comes at the tutorial's Book step rather than at its end: that step's pointer needs the button there.)
	type Reveal = { Stars: boolean, Shop: boolean, Book: boolean, Rest: boolean }
	local curedSeen = false -- a cure landed this session: ⭐ shows with it, not a moment later with the snapshot
	local function revealFor(state: Types.Snapshot): Reveal
		local step: any = state.Tutorial
		if type(step) ~= "number" then
			step = TutorialLogic.DONE -- a snapshot without the field: no tutorial
		end
		if TutorialLogic.isDone(step) then
			return { Stars = true, Shop = true, Book = true, Rest = true }
		elseif not TutorialLogic.active(step) then
			return { Stars = false, Shop = false, Book = false, Rest = false } -- 0: not known yet
		end
		return {
			Stars = step >= TutorialLogic.MORE or (step >= TutorialLogic.REST and curedSeen),
			Shop = step >= TutorialLogic.SHOP,
			Book = step >= TutorialLogic.BOOK,
			Rest = false,
		}
	end
	-- Shows or hides one piece; one that appears mid-session pops in (Hud.pop honours Hud.calm()).
	local function showPiece(piece: GuiObject, on: boolean, animate: boolean, bounce: number): boolean
		if piece.Visible == on then
			return false
		end
		piece.Visible = on
		if on and animate then
			Hud.pop(piece, bounce)
		end
		return on
	end
	local function applyReveal(state: Types.Snapshot, animate: boolean)
		local reveal = revealFor(state)
		local appeared = showPiece(starsPill, reveal.Stars, animate, 1.25)
		appeared = showPiece(buttons.Shop, reveal.Shop, animate, 1.45) or appeared -- the shop step's bounce
		appeared = showPiece(buttons.Book, reveal.Book, animate, 1.45) or appeared -- the Book step's
		for _, name in { "Mailbox", "Goals", "Nurses", "Badges", "Boards" } do
			appeared = showPiece(buttons[name], reveal.Rest, animate, 1.3) or appeared
		end
		appeared = showPiece(giftHolder, reveal.Rest, animate, 1.3) or appeared
		appeared = showPiece(side, reveal.Rest, animate, 1.12) or appeared
		placeHands()
		if appeared and animate then
			Hud.sound("Pop")
		end
	end
	applyReveal(initial, false)
	ctx.Remotes.Cured.OnClientEvent:Connect(function()
		curedSeen = true
		applyReveal(ctx.State, true)
	end)

	local loaded = false
	local mailWasReady = false
	local goalsWereReady = false
	ctx.onState(function(state: Types.Snapshot)
		local isServerState = state ~= initial
		local animate = isServerState and loaded
		if isServerState then
			loaded = true
		end
		applyReveal(state, animate)

		cash.set(state.Cash or 0, animate)
		stars.set(state.Stars or 0, animate)

		local passed, nextAt, icon, name = starTrack(data, state)
		local ratio = if nextAt then math.clamp(((state.Stars or 0) - passed) / (nextAt - passed), 0, 1) else 1
		nextIcon.Text = icon
		nextTip = if nextAt then icon .. " " .. name .. " at ⭐" .. nextAt else "👑 Everything unlocked!"
		if animate and not Hud.calm() then
			TweenService:Create(fill, Theme.Tween.Fill, { Size = UDim2.fromScale(ratio, 1) }):Play()
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
		shopTab = if news.Rooms
			then "Rooms"
			elseif news.Decor then "Decor"
			elseif news.Hospital or news.Branch then "Hospital"
			else nil
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
		-- Only for a clinic it can come to ("None": no plot, or no station here can treat it), and ✅ once cured.
		local status = state.VisitorStatus
		visitorMark.Text = if status == "Done" then "✅" else "⭐"
		paint(visitorChip, if status == "Done" then Theme.Colors.Good else Theme.Colors.Pink)
		visitorChip.Visible = look ~= nil and (status == "Coming" or status == "Done")

		if isServerState then
			watchPlot(state)
		end
		renderPlay()
	end)
end

return Hud
