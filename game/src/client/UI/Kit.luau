--!strict
-- Small UI building blocks so every screen looks and feels the same (build plan Task 0).
-- Each maker takes an optional props table: any Instance property (Size, Position, AnchorPoint, Text,
-- LayoutOrder, ...), plus Parent (set last) and the extras noted below. Colours and sizes come from Theme.
--
--   Kit.screen(name, displayOrder): ScreenGui       ResetOnSpawn off, inside the safe area, in PlayerGui
--   Kit.panel(props?): Frame                       white card, thick outline; extras: Title = "🛒 Shop" adds
--                                                  the header band with an outlined title: Theme.Colors.Header
--                                                  (navy, flat) unless Accent = Color3 is given (old callers; a
--                                                  modal never passes one)
--   Kit.label(props?): TextLabel                   extra: Outlined = true -> display font, white text, dark stroke
--   Kit.button(props?): TextButton                 glossy button with an outline, a press bounce and (with a
--                                                  mouse) a hover grow; extra: Kind, min 56 px tall. The ROLES (look
--                                                  build plan §B8): "Primary" | "Collect" | "Secondary" | "Quiet" |
--                                                  "Destructive" | "Icon". Old kinds still work until T6 maps them
--                                                  (Good -> Collect, Danger -> Destructive, Pink/Purple/Cyan/Cash ->
--                                                  Secondary, Card -> Quiet)
--   Kit.tab(button, selected, stripe?)             THE tab look (Modal.tabs paints with it). Unselected: Card fill,
--                                                  ink caption · selected: Header (navy) fill, white outlined
--                                                  caption, a 3 px outline · stripe: a 6 px left edge in the
--                                                  section's own colour (a wing, a rarity, a board)
--   Kit.textLimit(label, maxPx)                    THE text fit: a UITextSizeConstraint with MinTextSize =
--                                                  Theme.TextSize.Caption (18, the floor) and MaxTextSize =
--                                                  max(maxPx, 18). For TextScaled labels; no local copies
-- Kit.tab, Kit.textLimit and the role names are the look overhaul Foundation's first versions: T6 restyles them and
-- keeps the names and signatures.
--   Kit.iconButton(props?): TextButton             big emoji square; extras: Icon, Caption, Kind; has a "Dot"
--   Kit.setDot(button, visible, glyph?)            the red "something new" dot: pops in, then hops now and then;
--                                                  a glyph (an emoji) turns it into a slightly bigger sticker
--   Kit.setEnabled(button, enabled)
--   Kit.corner(parent, radius?) · Kit.pad(parent, px?) · Kit.stroke(parent, colour?, px?)
--   Kit.outline(text, px?): UIStroke              outlined text (a dark stroke around the letters)
--   Kit.list(parent, direction?, gap?) · Kit.popIn(gui) · Kit.popOut(gui, onDone?)
--   Kit.shade(colour, amount) · Kit.lighten(colour, amount)
--   Kit.shine(button): () -> ()                     a white shine sweeps across every few seconds (calls to
--                                                  action only); returns stop. Paused with reduced motion.
--   Kit.rays(parent, colour?): Frame               a slowly turning sunburst behind a reward (ZIndex 0, behind
--                                                  the parent's other children). Still with reduced motion.
--   Kit.bump(gui)                                  a quick springy grow-and-settle (a number changed, a reward)
--   Kit.punch(gui, from?, info?)                   the same with your own start scale and TweenInfo (Hud.pop)
--   Kit.gloss(gui, inset?): Frame                  the white top highlight Kit buttons have, for your own chips
--   Kit.isShown(gui): boolean                      it and every GuiObject above it are visible, its gui enabled
-- Depth update (build plan §B9; T6, design §4 "make it pop"):
--   Kit.countUp(label, to, format?, seconds?)      rolls a number label from its last value up (or down) to `to`;
--                                                  the attribute CountValue remembers it. A big jump rolls a little
--                                                  longer (Kit.Juice.countSeconds); a roll already heading to `to`
--                                                  carries on. Instant with reduced motion or while not on screen.
--                                                  Each new number it shows fires Kit.Ticked (Sounds ticks)
--   Kit.celebrate(parent, colour?): () -> ()       rays + candy confetti behind a reward; returns stop. Calm: still
--                                                  rays, no confetti
--   Kit.confetti(parent, count?, origin?)          one burst of candy confetti inside `parent` (origin: a UDim2 in
--                                                  the parent; nil = it rains from the top). Nothing with reduced
--                                                  motion
--   Kit.rarityFrame(gui, rarity): () -> ()         the rarity's frame: a UIStroke "RarityFrame" with a shimmer in
--                                                  its colours (Common grey, Rare blue, Epic purple, Legendary
--                                                  rainbow, Mythic cosmic, Secret gold); returns stop. Still (but
--                                                  coloured) with reduced motion
--   Kit.rarityColor(rarity): Color3                the rarity's colour (Data/Rarities; unknown = Common grey)
--   Kit.breathing(gui, amount?): () -> ()          idle "breathing" on a call to action: a slow gentle grow and
--                                                  shrink, paused while it's pressed or bounced; returns stop
-- Progression v2 (build plan §B9; T8 juiced the Foundation's first versions, same signatures):
--   Kit.ring(parent, color): (fraction) -> ()      a filling ring (ability cooldowns) round the edge of `parent`:
--                                                  Theme.Juice.RingBeads beads light up clockwise (the newest pops),
--                                                  all lit + a bright outline + one bump when ready. Call the setter
--                                                  with 0..1 (Kit.Juice.ringFraction). It NEVER prints seconds (red
--                                                  line 3) and never loops on its own
--   Kit.holdButton(button, seconds, onDone): () -> ()   hold-to-confirm: a bright band fills across the button and
--                                                  it swells a little while held, a rising tick each quarter
--                                                  (Kit.Ticked); onDone runs once the hold lasts `seconds`; letting
--                                                  go early empties it. Reduced motion: the same hold, the band steps
--                                                  by quarters and nothing swells. Returns stop
--   Kit.Juice                                      the pure helpers behind all this (no Roblox APIs; see below)
-- ZIndex 0 is the decoration layer inside a Kit button or panel (Gloss, Shine, Header, Rays): it draws over the
-- parent's own fill but under every other child, so give your own children ZIndex 1 or more (the default).
--   Kit.Clicked: Signal (button)                   fires on every Kit button press (Sounds plays a click)
--   Kit.Ticked: Signal (label, progress)           a count-up showed a new number (progress 0..1; Sounds ticks)
--   Kit.reducedMotion(): boolean                   honour it in your own tweens too
-- Every looping effect here (rays, breathing, dot hops, shimmer, count-ups, confetti) runs on ONE shared loop that
-- skips anything not on screen and sleeps (4 checks a second) while nothing is moving.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Palette = require(Shared:WaitForChild("Palette"))
local Signal = require(Shared:WaitForChild("Signal"))
local Rarities = require(Shared:WaitForChild("Data"):WaitForChild("Rarities")) :: any
local Theme = require(script.Parent.Theme)

type Props = { [string]: any }

local Kit = {}

Kit.Clicked = Signal.new()
Kit.Ticked = Signal.new()

------------------------------------------------------------------------------------------------------------------
-- Kit.Juice: pure helpers (numbers and strings only, no Roblox APIs). A scratch Lune harness loads the block
-- between the BEGIN/END markers on its own, so keep it self-contained.
------------------------------------------------------------------------------------------------------------------
-- BEGIN JUICE
local Juice = {}

-- How long a count-up rolls: `seconds` when given (never negative), else `base` (default 0.6) stretched a little
-- for big jumps (+1 → ~0.4 s, +100 → 0.6 s, +1,000,000 → ~1.1 s), between 0.3 and 1.4 s. 0 when nothing moves.
function Juice.countSeconds(from: number, to: number, seconds: number?, base: number?): number
	if seconds ~= nil then
		return math.max(seconds, 0)
	end
	local delta = math.abs(to - from)
	if delta == 0 or delta ~= delta then
		return 0
	end
	return math.clamp((base or 0.6) * (0.6 + 0.2 * math.log10(delta + 1)), 0.3, 1.4)
end

-- Ease-out quart, clamped to 0..1: fast at first, settling gently on the number.
function Juice.ease(t: number): number
	local x = math.clamp(t, 0, 1)
	return 1 - (1 - x) ^ 4
end

-- How many coins fly for an amount of cash: 0 for nothing, 3 for a little, one more each time it roughly triples
-- (18 → 5, 100 → 7, 1,000 → 9), at most 10.
function Juice.coins(amount: number): number
	if amount ~= amount or amount < 1 then
		return 0
	end
	return math.clamp(3 + math.floor(2 * math.log10(amount)), 3, 10)
end

-- A countdown as "m:ss" (never negative; minutes grow past 59).
function Juice.clock(seconds: number): string
	local left = if seconds ~= seconds then 0 else math.max(0, math.floor(seconds))
	return string.format("%d:%02d", left // 60, left % 60)
end

export type ComboStep = { At: number, Multiplier: number }

-- The combo's tier: the index of the highest step whose At it has reached (0 = none) and its tip multiplier.
-- `steps` is Config.MiniGame.Combo (sorted by At).
function Juice.comboStep(combo: number, steps: { ComboStep }): (number, number)
	local tier, multiplier = 0, 1
	for index, step in steps do
		if combo >= step.At then
			tier, multiplier = index, step.Multiplier
		end
	end
	return tier, multiplier
end

-- True when the combo went up into a new tier (before < At <= after for some step).
function Juice.crossed(before: number, after: number, steps: { ComboStep }): boolean
	if after <= before then
		return false
	end
	for _, step in steps do
		if before < step.At and after >= step.At then
			return true
		end
	end
	return false
end

-- A quadratic Bezier on one axis: from a through control b to c, t in 0..1 (flying coins arc on it).
function Juice.arc(a: number, b: number, c: number, t: number): number
	local x = math.clamp(t, 0, 1)
	local u = 1 - x
	return u * u * a + 2 * u * x * b + x * x * c
end

-- A breath: 0 at rest, 1 at the top, back to 0 every `period` seconds (a cosine, so it starts and ends still).
function Juice.breath(elapsed: number, period: number): number
	if period <= 0 then
		return 0
	end
	return 0.5 - 0.5 * math.cos(elapsed / period * 2 * math.pi)
end

-- A hop that repeats every `every` seconds and lasts `length`: 0 while resting, a sine bump 0 → 1 → 0 during it.
function Juice.hop(elapsed: number, every: number, length: number): number
	if every <= 0 or length <= 0 or elapsed < 0 then
		return 0
	end
	local phase = elapsed % every
	if phase >= length then
		return 0
	end
	return math.sin(phase / length * math.pi)
end

-- How long a toast stays: `base` seconds, a little longer for long messages, at most `max`.
function Juice.toastSeconds(text: string, base: number, perChar: number, max: number): number
	return math.min(max, base + math.max(0, #text - 30) * perChar)
end

local function finite(value: any): number?
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return nil
end

-- Progression v2: an ability's cooldown ring. How full it is at `now` (server time): 1 once it's ready (readyAt <=
-- now, or no readyAt at all), else the share of `cooldown` already waited (0 just fired). A future readyAt with no
-- usable cooldown is empty (0), never falsely "ready". Never seconds: the caller draws a ring, not a number.
function Juice.ringFraction(readyAt: any, cooldown: any, now: number): number
	local at, clock = finite(readyAt), finite(now) or 0
	if at == nil or at <= clock then
		return 1
	end
	local length = finite(cooldown)
	if length == nil or length <= 0 then
		return 0
	end
	return math.clamp(1 - (at - clock) / length, 0, 1)
end

-- A ring of `count` beads at `fraction`: how many are lit, and how far the next one is (0..1). Full = all lit, 0.
function Juice.ringBeads(fraction: number, count: number): (number, number)
	local n = math.max(1, math.floor(finite(count) or 1))
	local share = math.clamp(finite(fraction) or 0, 0, 1)
	local lit = math.floor(share * n + 1e-9)
	if lit >= n then
		return n, 0
	end
	return lit, math.clamp(share * n - lit, 0, 1)
end

-- Hold-to-confirm: the fill (0..1) after holding `held` of `seconds`. With `steps` (reduced motion) it moves in whole
-- steps (quarters), so it still shows the hold without a smooth slide.
function Juice.holdFill(held: number, seconds: number, steps: number?): number
	local total = finite(seconds) or 0
	if total <= 0 then
		total = 1
	end
	local share = math.clamp((finite(held) or 0) / total, 0, 1)
	local whole = finite(steps)
	if whole and whole >= 1 then
		share = math.floor(share * math.floor(whole) + 1e-9) / math.floor(whole)
	end
	return share
end
-- END JUICE

Kit.Juice = Juice

local KIND_COLORS: { [string]: Color3 } = {
	-- the roles (look build plan §B8)
	Primary = Theme.Colors.Primary,
	Collect = Theme.Colors.Collect,
	Secondary = Theme.Colors.Secondary,
	Destructive = Theme.Colors.Destructive,
	Icon = Theme.Colors.Plate,
	-- old kinds (T6 maps them onto the roles)
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
local LIGHT_KINDS = { Quiet = true, Card = true, Secondary = true, Icon = true }
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

-- True when gui is actually on screen: it and every GuiObject above it are Visible, and its ScreenGui (or
-- BillboardGui / SurfaceGui) is enabled. The shared loop uses it to skip what's hidden.
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
Kit.isShown = isShown

------------------------------------------------------------------------------------------------------------------
-- Scales: one UIScale per object (two on one object fight), and who's moving it right now
------------------------------------------------------------------------------------------------------------------

-- The UIScale Kit animates on `gui`: its KitScale, else a UIScale it already has (not a Hud.fitHeight FitScale),
-- else a new KitScale.
local function scaleOf(gui: GuiObject): UIScale
	local existing = gui:FindFirstChild("KitScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end
	for _, child in gui:GetChildren() do
		if child:IsA("UIScale") and child.Name ~= "FitScale" then
			return child
		end
	end
	local scale = Instance.new("UIScale")
	scale.Name = "KitScale"
	scale.Parent = gui
	return scale
end

-- A tween (press, hover, bump, pop) owns a scale until it ends, so breathing and dot hops never fight it.
local busyUntil: { [UIScale]: number } = setmetatable({}, { __mode = "k" }) :: any
local hovered: { [UIScale]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local scaleTweens: { [UIScale]: Tween } = setmetatable({}, { __mode = "k" }) :: any

local function isBusy(scale: UIScale, now: number): boolean
	return hovered[scale] == true or (busyUntil[scale] or 0) > now
end

-- Tweens a scale to `target`, cancelling any Kit tween already on it, and marks it busy until it ends.
local function tweenScale(scale: UIScale, info: TweenInfo, target: number)
	local running = scaleTweens[scale]
	if running then
		running:Cancel()
	end
	local tween = TweenService:Create(scale, info, { Scale = target })
	scaleTweens[scale] = tween
	busyUntil[scale] = os.clock() + info.Time + info.DelayTime + 0.02
	tween.Completed:Once(function()
		if scaleTweens[scale] == tween then
			scaleTweens[scale] = nil
		end
	end)
	tween:Play()
end

-- A quick springy grow-and-settle from `from` (default 1.18) back to 1. Nothing with reduced motion.
function Kit.punch(gui: GuiObject?, from: number?, info: TweenInfo?)
	if not gui or Kit.reducedMotion() then
		return
	end
	local scale = scaleOf(gui)
	scale.Scale = from or 1.18
	tweenScale(scale, info or Theme.Tween.Bump, 1)
end

-- A quick springy grow-and-settle: a number changed, a reward landed.
function Kit.bump(gui: GuiObject)
	Kit.punch(gui, 1.18, Theme.Tween.Bump)
end

------------------------------------------------------------------------------------------------------------------
-- The shared loop: every looping effect is a job. Hidden jobs are skipped; calm jobs rest once.
------------------------------------------------------------------------------------------------------------------

-- A step returns "done" when the job is finished, "idle" when nothing moved this frame (a resting dot: the loop
-- may wait a little longer), or nil while it animates.
type StepResult = ("done" | "idle")?
type Job = {
	Gui: GuiObject,
	Step: (now: number, dt: number) -> StepResult,
	Rest: (() -> ())?, -- reduced motion: put it at rest (called once each time calm starts)
	Resting: boolean,
	Stopped: boolean,
	Orphaned: number?, -- when it lost its parent (removed after ORPHAN_SECONDS without one)
}

local ORPHAN_SECONDS = 5
local jobs: { Job } = {}
local looping = false

local function runLoop()
	if looping then
		return
	end
	looping = true
	task.spawn(function()
		local last = os.clock()
		while #jobs > 0 do
			local now = os.clock()
			local dt = math.min(now - last, 0.1)
			last = now
			local calm = Kit.reducedMotion()
			local moving = false
			local resting = false
			for index = #jobs, 1, -1 do
				local job = jobs[index]
				local gui = job.Gui
				if job.Stopped then
					table.remove(jobs, index)
				elseif gui.Parent == nil then
					job.Orphaned = job.Orphaned or now
					if now - (job.Orphaned :: number) > ORPHAN_SECONDS then
						table.remove(jobs, index)
					end
				else
					job.Orphaned = nil
					if isShown(gui) then
						if calm then
							if not job.Resting then
								job.Resting = true
								if job.Rest then
									job.Rest()
								end
							end
						else
							job.Resting = false
							local ok, result = pcall(job.Step, now, dt)
							if not ok then
								warn("[Kit] effect failed:", result)
								job.Stopped = true
							elseif result == "done" then
								job.Stopped = true
							elseif result == "idle" then
								resting = true
							else
								moving = true
							end
						end
					end
				end
			end
			if moving then
				task.wait()
			elseif resting then
				task.wait(0.1) -- only resting effects on screen (dots between hops)
			else
				task.wait(0.25) -- nothing moving on screen: check again in a moment
			end
		end
		looping = false
	end)
end

local function addJob(gui: GuiObject, step: (now: number, dt: number) -> StepResult, rest: (() -> ())?): Job
	local job: Job = { Gui = gui, Step = step, Rest = rest, Resting = false, Stopped = false, Orphaned = nil }
	table.insert(jobs, job)
	gui.Destroying:Once(function()
		job.Stopped = true
	end)
	runLoop()
	return job
end

------------------------------------------------------------------------------------------------------------------
-- Buttons
------------------------------------------------------------------------------------------------------------------

local function mouseFirst(): boolean
	local ok, preferred = pcall(function()
		return UserInputService.PreferredInput
	end)
	return ok and preferred == Enum.PreferredInput.KeyboardAndMouse
end

-- A quick squash on press and a springy release (game-feel: small tier, no shake); with a mouse, a little grow
-- while it hovers.
local function addBounce(button: GuiButton)
	local scale = scaleOf(button)
	local function to(target: number, info: TweenInfo)
		if Kit.reducedMotion() then
			local running = scaleTweens[scale]
			if running then
				running:Cancel()
			end
			scale.Scale = 1
			return
		end
		tweenScale(scale, info, target)
	end
	local function rest(): number
		return if hovered[scale] then Theme.HoverScale else 1
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
			to(rest(), Theme.Tween.Release)
		end
	end)
	-- A button hidden while hovered (its panel closed) may never get MouseLeave: let go of the hover then.
	local function watchHover()
		task.spawn(function()
			while hovered[scale] do
				task.wait(0.25)
				local state = button.GuiState
				if
					hovered[scale]
					and (not isShown(button) or (state ~= Enum.GuiState.Hover and state ~= Enum.GuiState.Press))
				then
					hovered[scale] = nil
					to(1, Theme.Tween.Release)
				end
			end
		end)
	end
	button.MouseEnter:Connect(function()
		if button.Interactable and mouseFirst() and not Kit.reducedMotion() then
			local already = hovered[scale] == true
			hovered[scale] = true
			to(Theme.HoverScale, Theme.Tween.Hover)
			if not already then
				watchHover()
			end
		end
	end)
	button.MouseLeave:Connect(function()
		hovered[scale] = nil
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
		-- Every header is navy (Theme.Colors.Header), flat. A colour passed in is an old caller's.
		local custom = typeof(props.Accent) == "Color3"
		local accent: Color3 = if custom then props.Accent else Theme.Colors.Header
		-- The header band runs edge to edge (out through the panel's padding) behind the title and close button.
		local pad = Theme.Size.Pad
		local header = Instance.new("Frame")
		header.Name = "Header"
		header.ZIndex = 0
		header.Position = UDim2.fromOffset(-pad, -pad)
		header.Size = UDim2.new(1, pad * 2, 0, Theme.Size.ButtonHeight + pad + 4)
		header.BackgroundColor3 = if custom then Kit.lighten(accent, 0.08) else accent
		header.BorderSizePixel = 0
		Kit.corner(header, Theme.Size.CornerLarge)
		if custom then
			Palette.candyGradient(header)
		end
		local foot = Instance.new("Frame") -- squares off the band's bottom corners
		foot.Name = "Foot"
		foot.ZIndex = 0
		foot.AnchorPoint = Vector2.new(0, 1)
		foot.Position = UDim2.fromScale(0, 1)
		foot.Size = UDim2.new(1, 0, 0, Theme.Size.CornerLarge)
		foot.BackgroundColor3 = if custom then Kit.shade(accent, 0.06) else accent
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

-- THE tab look (first version; T6 restyles it). `button` is a Kit.iconButton (its Icon and Caption labels) or any
-- text button.
function Kit.tab(button: GuiButton, selected: boolean, stripe: Color3?)
	local fill = if selected then Theme.Colors.Header else Theme.Colors.Card
	button.BackgroundColor3 = fill
	button:SetAttribute("KitColor", fill)
	button:SetAttribute("Selected", selected)
	for _, name in { "Gloss", "CandyGradient" } do
		local shine = button:FindFirstChild(name)
		if shine and shine:IsA("GuiObject") then
			shine.Visible = false -- flat fills: the gloss reads as a grey smear on navy
		elseif shine and shine:IsA("UIGradient") then
			shine.Enabled = false
		end
	end
	local border = button:FindFirstChildOfClass("UIStroke")
	if border then
		border.Color = Theme.Colors.Stroke
		border.Thickness = if selected then Theme.Stroke.Bold else Theme.Stroke.Fine
	end
	local function ink(text: Instance?)
		if text and (text:IsA("TextLabel") or text:IsA("TextButton")) then
			text.TextColor3 = if selected then Theme.Colors.OnColor else Theme.Colors.Ink
			local outline = text:FindFirstChild("TextOutline")
			if selected then
				Kit.outline(text)
			elseif outline then
				outline:Destroy()
			end
		end
	end
	ink(button:FindFirstChild("Caption"))
	ink(button)
	local edge = button:FindFirstChild("Stripe")
	if stripe then
		local bar: Frame
		if edge and edge:IsA("Frame") then
			bar = edge
		else
			bar = Instance.new("Frame")
			bar.Name = "Stripe"
			bar.BorderSizePixel = 0
			bar.Position = UDim2.fromScale(0, 0.12)
			bar.Size = UDim2.new(0, 6, 0.76, 0)
			bar.ZIndex = 2
			Kit.corner(bar, Theme.Radius.Small)
			bar.Parent = button
		end
		bar.BackgroundColor3 = stripe
	elseif edge then
		edge:Destroy()
	end
end

-- THE text fit: a scaled label never shrinks under the floor (Theme.TextSize.Caption) and never grows past maxPx.
function Kit.textLimit(label: TextLabel | TextButton, maxPx: number): UITextSizeConstraint
	local existing = label:FindFirstChildOfClass("UITextSizeConstraint")
	local limit: UITextSizeConstraint = existing or Instance.new("UITextSizeConstraint")
	local floor = Theme.TextSize.Caption
	limit.MaxTextSize = math.max(maxPx, floor)
	limit.MinTextSize = floor
	limit.Parent = label
	return limit
end

-- The red dot pops in when it appears, then hops (a little jump and wiggle) every Theme.Juice.DotHopEvery seconds
-- while it shows. One hop job per dot, made the first time it shows.
local dotJobs: { [GuiObject]: Job } = setmetatable({}, { __mode = "k" }) :: any
local DOT_HOP_SECONDS = 0.42

local function startDotHops(dot: GuiObject)
	local existing = dotJobs[dot]
	if existing and not existing.Stopped then
		return
	end
	local scale = scaleOf(dot)
	local started = os.clock()
	local resting = true -- only write while it hops (or once to land it back at rest)
	dotJobs[dot] = addJob(dot, function(now): StepResult
		if isBusy(scale, now) then
			return nil
		end
		local hop = Juice.hop(now - started, Theme.Juice.DotHopEvery, DOT_HOP_SECONDS)
		if hop <= 0 and resting then
			return "idle"
		end
		resting = hop <= 0
		scale.Scale = 1 + 0.28 * hop
		dot.Rotation = 14 * hop * math.sin((now - started) * 30)
		return nil
	end, function()
		if not isBusy(scale, os.clock()) then
			scale.Scale = 1
		end
		dot.Rotation = 0
	end)
end

function Kit.setDot(button: GuiObject, visible: boolean, glyph: string?)
	local dot = button:FindFirstChild("Dot")
	if not (dot and dot:IsA("GuiObject")) then
		return
	end
	-- An optional glyph (Progression v2: 🃏 / 🌳 on the 🛒 dot for a branch reward) makes it a slightly bigger sticker
	-- with the emoji in it; without one it's the plain red dot again.
	local mark = dot:FindFirstChild("Glyph")
	local wanted = if visible and type(glyph) == "string" and glyph ~= "" then glyph else nil
	if wanted and not mark then
		local label = Instance.new("TextLabel")
		label.Name = "Glyph"
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.fromScale(0.86, 0.86)
		label.TextScaled = true
		label.Font = Theme.Font
		label.ZIndex = dot.ZIndex + 1
		label.Parent = dot
		mark = label
	end
	if mark and mark:IsA("TextLabel") then
		mark.Text = wanted or ""
		mark.Visible = wanted ~= nil
	end
	local side = if wanted then Theme.Size.Dot + 8 else Theme.Size.Dot
	if dot.Size.X.Offset ~= side then
		dot.Size = UDim2.fromOffset(side, side)
	end
	local appeared = visible and not dot.Visible
	dot.Visible = visible
	if appeared then
		Kit.punch(dot, 0.2, Theme.Tween.PopIn)
		startDotHops(dot)
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
		local running = scaleTweens[scale]
		if running then
			running:Cancel()
		end
		scale.Scale = 1
		return
	end
	scale.Scale = Theme.PopFrom
	tweenScale(scale, Theme.Tween.PopIn, 1)
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
	tweenScale(scale, Theme.Tween.PopOut, 0.85)
	local tween = scaleTweens[scale]
	if tween then
		tween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed then
				done()
			end
		end)
	end
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
	addJob(rays, function(_, dt): StepResult
		rays.Rotation = (rays.Rotation + dt * 360 / Theme.RaysSpin) % 360
		return nil
	end, nil)
	return rays
end

------------------------------------------------------------------------------------------------------------------
-- Depth update juice (build plan §B9; design §4)
------------------------------------------------------------------------------------------------------------------

local function plainNumber(n: number): string
	return tostring(math.floor(n + 0.5))
end

type Count = {
	From: number,
	To: number,
	Start: number,
	Seconds: number,
	Show: (number) -> string,
	Current: number,
	Job: Job,
}
local counts: { [TextLabel]: Count } = setmetatable({}, { __mode = "k" }) :: any

-- Rolls a number label to `to`. The label's attribute CountValue remembers the last number, so the next call rolls
-- from there (or from wherever a roll still running has got to). `format` turns the number into text (default: a
-- whole number); `seconds` sets the roll's length (0 = instant). The label springs when it starts and lands.
function Kit.countUp(label: TextLabel, to: number, format: ((number) -> string)?, seconds: number?)
	local show = format or plainNumber
	local running = counts[label]
	if running and not running.Job.Stopped and running.To == to then
		running.Show = show -- already rolling there: carry on
		return
	end
	local saved = label:GetAttribute("CountValue")
	local from: number? = if running and not running.Job.Stopped
		then running.Current
		elseif type(saved) == "number" then saved
		else nil
	label:SetAttribute("CountValue", to)
	if running then
		running.Job.Stopped = true
		counts[label] = nil
	end
	local duration = if from then Juice.countSeconds(from, to, seconds, Theme.Juice.CountSeconds) else 0
	if from == nil or duration <= 0 or Kit.reducedMotion() or not isShown(label) then
		label.Text = show(to)
		return
	end
	local start = from :: number
	local count: Count
	local shown = label.Text
	local job = addJob(label, function(now): StepResult
		local t = math.min((now - count.Start) / count.Seconds, 1)
		count.Current = start + (to - start) * Juice.ease(t)
		local text = count.Show(if t >= 1 then to else count.Current)
		if text ~= shown then
			shown = text
			label.Text = text
			Kit.Ticked:Fire(label, t)
		end
		if t >= 1 then
			counts[label] = nil
			Kit.punch(label, 1.1, Theme.Tween.Release)
			return "done"
		end
		return nil
	end, function()
		-- Calm mid-roll: land on the number now.
		counts[label] = nil
		label.Text = show(to)
		count.Job.Stopped = true
	end)
	count = {
		From = start,
		To = to,
		Start = os.clock(),
		Seconds = duration,
		Show = show,
		Current = start,
		Job = job,
	}
	counts[label] = count
	Kit.punch(label, 1.14, Theme.Tween.Bump)
end

-- One burst of candy confetti inside `parent`. With an origin (a UDim2 in the parent) the pieces pop up and out
-- from there; without one they rain from the parent's top edge. Pieces fall for Theme.Juice.ConfettiSeconds and
-- fade at the end. Nothing with reduced motion. Never takes taps.
type Piece = { Frame: Frame, X: number, Y: number, VX: number, VY: number, Spin: number, Sway: number }
function Kit.confetti(parent: GuiObject, count: number?, origin: UDim2?)
	if Kit.reducedMotion() then
		return
	end
	local n = math.clamp(math.floor(count or Theme.Juice.ConfettiPieces), 1, 60)
	local size = parent.AbsoluteSize
	local scale = math.clamp(math.max(size.X, size.Y) / 400, 0.5, 2) -- px speeds suit the parent's size
	local pieces: { Piece } = {}
	local holder = Instance.new("Frame")
	holder.Name = "Confetti"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = 8
	holder.Parent = parent
	local ox = if origin then origin.X.Scale * size.X + origin.X.Offset else 0
	local oy = if origin then origin.Y.Scale * size.Y + origin.Y.Offset else 0
	for i = 1, n do
		local piece = Instance.new("Frame")
		piece.Name = "Piece"
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.BorderSizePixel = 0
		piece.BackgroundColor3 = Theme.Confetti[(i - 1) % #Theme.Confetti + 1]
		local wide = math.random() < 0.5
		piece.Size = UDim2.fromOffset(if wide then 14 else 9, if wide then 8 else 14)
		piece.Rotation = math.random(0, 359)
		piece.ZIndex = 8
		if math.random() < 0.35 then
			Kit.corner(piece, 6) -- a few round ones
		end
		piece.Parent = holder
		local x, y, vx, vy = 0, 0, 0, 0
		if origin then
			local angle = -math.pi / 2 + (math.random() - 0.5) * 2.2
			local speed = (260 + math.random() * 260) * scale
			x, y = ox, oy
			vx, vy = math.cos(angle) * speed, math.sin(angle) * speed
		else
			x, y = math.random() * size.X, -10 - math.random() * 60
			vx, vy = (math.random() - 0.5) * 80 * scale, (40 + math.random() * 90) * scale
		end
		piece.Position = UDim2.fromOffset(x, y)
		table.insert(pieces, {
			Frame = piece,
			X = x,
			Y = y,
			VX = vx,
			VY = vy,
			Spin = (math.random() - 0.5) * 720,
			Sway = math.random() * math.pi * 2,
		})
	end
	local life = Theme.Juice.ConfettiSeconds
	local started = os.clock()
	local gravity = 520 * scale
	addJob(holder, function(now, dt): StepResult
		local age = now - started
		if age >= life then
			holder:Destroy()
			return "done"
		end
		local fade = math.clamp((age - life * 0.7) / (life * 0.3), 0, 1)
		for _, p in pieces do
			p.VY += gravity * dt
			p.VX *= 1 - math.min(dt * 1.6, 0.5) -- air drag, so they flutter down
			p.VY = math.min(p.VY, 260 * scale)
			p.X += (p.VX + math.sin(age * 5 + p.Sway) * 40 * scale) * dt
			p.Y += p.VY * dt
			p.Frame.Position = UDim2.fromOffset(p.X, p.Y)
			p.Frame.Rotation += p.Spin * dt
			p.Frame.BackgroundTransparency = fade
		end
		return nil
	end, function()
		holder:Destroy()
	end)
end

-- A reward's backdrop: Kit.rays behind `parent` plus a confetti burst from its middle (and a second, smaller one
-- a moment later). Returns stop. Calm: the rays hold still and there's no confetti.
function Kit.celebrate(parent: GuiObject, color: Color3?): () -> ()
	local rays = Kit.rays(parent, color)
	local stopped = false
	Kit.confetti(parent, Theme.Juice.ConfettiPieces, UDim2.fromScale(0.5, 0.5))
	task.delay(0.55, function()
		if not stopped and parent.Parent then
			Kit.confetti(parent, math.floor(Theme.Juice.ConfettiPieces / 2), UDim2.fromScale(0.5, 0.45))
		end
	end)
	return function()
		stopped = true
		rays:Destroy()
		for _, child in parent:GetChildren() do
			if child.Name == "Confetti" then
				child:Destroy()
			end
		end
	end
end

-- The rarity's colour (Data/Rarities hex). An unknown rarity is the Common grey.
function Kit.rarityColor(rarity: string): Color3
	local info = rawget(Rarities, rarity) or rawget(Rarities, "Common")
	if info and type(info.Color) == "string" then
		local ok, color = pcall(Color3.fromHex, info.Color)
		if ok then
			return color
		end
	end
	return Theme.Colors.Quiet
end

-- How each frame shimmers: its colours (a ColorSequence over the stroke), whether the gradient turns round the
-- frame ("Spin") or a bright band sweeps across it ("Sweep"), the speed, and whether the outline pulses.
type Shimmer = { Colors: ColorSequence, Motion: "Spin" | "Sweep", Speed: number, Pulse: boolean, Width: number }

local function band(base: Color3, light: Color3): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, base),
		ColorSequenceKeypoint.new(0.4, base),
		ColorSequenceKeypoint.new(0.5, light),
		ColorSequenceKeypoint.new(0.6, base),
		ColorSequenceKeypoint.new(1, base),
	})
end

local function shimmerFor(rarity: string): Shimmer
	local info = rawget(Rarities, rarity) or rawget(Rarities, "Common")
	local frame = if info then info.Frame else "Grey"
	local color = Kit.rarityColor(rarity)
	local seconds = Theme.Juice.ShimmerSeconds
	local width = Theme.Size.Stroke + 1
	if frame == "Rainbow" then
		return {
			Colors = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 90)),
				ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 160, 30)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 40)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 220, 60)),
				ColorSequenceKeypoint.new(0.67, Color3.fromRGB(40, 170, 255)),
				ColorSequenceKeypoint.new(0.83, Color3.fromRGB(160, 80, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 70, 90)),
			}),
			Motion = "Spin",
			Speed = 360 / seconds,
			Pulse = false,
			Width = width + 1,
		}
	elseif frame == "Cosmic" then
		return {
			Colors = ColorSequence.new({
				ColorSequenceKeypoint.new(0, color),
				ColorSequenceKeypoint.new(0.3, Color3.fromRGB(120, 60, 230)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(30, 20, 90)),
				ColorSequenceKeypoint.new(0.7, Color3.fromRGB(0, 214, 232)),
				ColorSequenceKeypoint.new(1, color),
			}),
			Motion = "Spin",
			Speed = 360 / (seconds * 1.3),
			Pulse = true,
			Width = width + 1,
		}
	elseif frame == "Gold" then
		return {
			Colors = band(color, Color3.new(1, 1, 1)),
			Motion = "Sweep",
			Speed = 1.6 / seconds,
			Pulse = true,
			Width = width + 1,
		}
	elseif frame == "Purple" then
		return {
			Colors = band(color, Kit.lighten(Theme.Colors.Pink, 0.35)),
			Motion = "Sweep",
			Speed = 1.2 / seconds,
			Pulse = true,
			Width = width,
		}
	end
	-- Grey (Common) and Blue (Rare): a soft white band sweeping slowly across.
	return {
		Colors = band(color, Kit.lighten(color, 0.75)),
		Motion = "Sweep",
		Speed = (if frame == "Blue" then 1 else 0.7) / seconds,
		Pulse = false,
		Width = width,
	}
end

-- The rarity's frame on a card or chip: a UIStroke named RarityFrame (white, so its UIGradient "Shimmer" carries
-- the colours), shimmering on the shared loop while it's on screen. Returns stop (removes it).
function Kit.rarityFrame(gui: GuiObject, rarity: string): () -> ()
	local existing = gui:FindFirstChild("RarityFrame")
	if existing then
		existing:Destroy()
	end
	local look = shimmerFor(rarity)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "RarityFrame"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = look.Width
	stroke:SetAttribute("Rarity", rarity)
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Shimmer"
	gradient.Color = look.Colors
	gradient.Rotation = 35
	gradient.Offset = Vector2.zero
	gradient.Parent = stroke
	stroke.Parent = gui

	local started = os.clock()
	local job = addJob(gui, function(now, dt): StepResult
		if not stroke.Parent then
			return "done"
		end
		if look.Motion == "Spin" then
			gradient.Rotation = (gradient.Rotation + dt * look.Speed) % 360
		else
			-- The bright band crosses from one side to the other, then rests off the edge a moment.
			local phase = ((now - started) * look.Speed) % 1.6
			gradient.Offset = Vector2.new(math.clamp(phase, 0, 1.6) * 2 - 1.6, 0)
		end
		if look.Pulse then
			stroke.Thickness = look.Width + 0.8 * Juice.breath(now - started, 1.2)
		end
		return nil
	end, function()
		gradient.Rotation = 35
		gradient.Offset = Vector2.zero
		stroke.Thickness = look.Width
	end)
	return function()
		job.Stopped = true
		stroke:Destroy()
	end
end

-- A filling ring (Progression v2: ability cooldowns, build plan §B9). A circle of Theme.Juice.RingBeads beads round
-- the edge of `parent` (its middle stays clear for the icon under it): they light up one by one, clockwise from the
-- top, in `color`, the next one glowing in as it nears; the newest lit bead pops. Full = ready: every bead lit, a
-- bright outline round the ring and one happy bump (no looping glow, so a ready ring never keeps the shared loop
-- awake). Returns a setter for the fraction (0 = empty, 1 = full: ready; junk = 0). It NEVER prints seconds (red
-- line 3): Kit.Juice.ringFraction turns AbilityReadyAt/AbilityCooldown into the fraction. Reduced motion: no pops.
function Kit.ring(parent: GuiObject, color: Color3): (fraction: number) -> ()
	local count = Theme.Juice.RingBeads
	local pale = Kit.lighten(color, 0.72)
	local holder = Instance.new("Frame")
	holder.Name = "Ring"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = parent.ZIndex + 1
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.Parent = holder
	Kit.corner(holder, 999)
	-- The ready outline: hidden until every bead is lit.
	local glow = Kit.stroke(holder, color, 3)
	glow.Name = "Glow"
	glow.Enabled = false

	local beads: { Frame } = {}
	local shown: { number } = {} -- each bead's drawn state: 0 pale, 1 lit, or the partial share
	for index = 1, count do
		local angle = (index - 1) / count * 2 * math.pi
		local bead = Instance.new("Frame")
		bead.Name = "Bead" .. index
		bead.AnchorPoint = Vector2.new(0.5, 0.5)
		bead.Position = UDim2.fromScale(0.5 + 0.42 * math.sin(angle), 0.5 - 0.42 * math.cos(angle))
		bead.Size = UDim2.fromScale(0.15, 0.15)
		bead.BackgroundColor3 = pale
		bead.BorderSizePixel = 0
		bead.ZIndex = holder.ZIndex
		Kit.corner(bead, 999)
		local edge = Kit.stroke(bead, Theme.Colors.Outline, 1.5)
		edge.Transparency = 0.35
		bead.Parent = holder
		beads[index] = bead
		shown[index] = 0
	end
	holder.Parent = parent

	local lit = -1 -- beads lit at the last call (-1 = never set: the first call never pops)
	return function(fraction: number)
		local on, partial = Juice.ringBeads(fraction, count)
		for index, bead in beads do
			local want = if index <= on then 1 elseif index == on + 1 then math.floor(partial * 4) / 4 else 0
			if shown[index] ~= want then
				shown[index] = want
				bead.BackgroundColor3 = pale:Lerp(color, want)
			end
		end
		local ready = on >= count
		glow.Enabled = ready
		if lit >= 0 and on > lit and not Kit.reducedMotion() then
			if ready then
				Kit.punch(holder, 1.15, Theme.Tween.Bump)
			end
			local newest = beads[on]
			if newest then
				Kit.punch(newest, 1.7, Theme.Tween.Bump)
			end
		end
		lit = on
	end
end

-- Hold-to-confirm (Progression v2: opening a branch, selling an Epic+; build plan §B9). Holding the button fills a
-- bright band across it from the left while the button swells a little, and each quarter of the way fires Kit.Ticked
-- (Sounds plays a rising tick), so a hold you can't see still sounds like it's filling. Letting go (or sliding off)
-- before `seconds` empties it and nothing happens; onDone runs once per completed hold, with a happy bump. A button
-- that isn't Interactable ignores presses. Reduced motion: the same hold, the band steps up by quarters instead of
-- sliding and the button doesn't swell. Returns stop (disconnects everything and removes the band).
function Kit.holdButton(button: TextButton, seconds: number, onDone: () -> ()): () -> ()
	local hold = if type(seconds) == "number" and seconds == seconds and seconds > 0 then seconds else 1
	local fill = Instance.new("Frame")
	fill.Name = "HoldFill"
	fill.BackgroundColor3 = Palette.White
	fill.BackgroundTransparency = 0.45
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = button.ZIndex
	Kit.corner(fill, Theme.Size.Corner)
	-- A brighter leading edge, so the band reads as moving.
	local shade = Instance.new("UIGradient")
	shade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.85, 0.1),
		NumberSequenceKeypoint.new(1, 0),
	})
	shade.Parent = fill
	fill.Parent = button
	local scale = scaleOf(button)

	local token = 0
	local connections: { RBXScriptConnection } = {}
	local tween: Tween? = nil
	local holding = false
	local function reset()
		token += 1
		if tween then
			tween:Cancel()
			tween = nil
		end
		fill.Size = UDim2.fromScale(0, 1)
		if holding then
			holding = false
			if not Kit.reducedMotion() then
				tweenScale(scale, Theme.Tween.Release, 1)
			else
				scale.Scale = 1
			end
		end
	end
	local function isPress(input: InputObject): boolean
		local kind = input.UserInputType
		return kind == Enum.UserInputType.MouseButton1
			or kind == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA
			or input.KeyCode == Enum.KeyCode.Return
	end
	table.insert(
		connections,
		button.InputBegan:Connect(function(input: InputObject)
			if not isPress(input) or not button.Interactable then
				return
			end
			reset()
			local mine = token
			holding = true
			local calm = Kit.reducedMotion()
			if calm then
				fill.Size = UDim2.fromScale(0, 1)
			else
				local slide = TweenService:Create(fill, TweenInfo.new(hold, Enum.EasingStyle.Linear), {
					Size = UDim2.fromScale(1, 1),
				})
				tween = slide
				slide:Play()
				tweenScale(scale, TweenInfo.new(hold, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), 1.06)
			end
			-- Quarters: a rising tick each (and the calm band's step).
			for step = 1, 3 do
				task.delay(hold * step / 4, function()
					if token == mine then
						if calm then
							fill.Size = UDim2.fromScale(Juice.holdFill(hold * step / 4, hold, 4), 1)
						end
						Kit.Ticked:Fire(button, step / 4)
					end
				end)
			end
			task.delay(hold, function()
				if token ~= mine then
					return
				end
				fill.Size = UDim2.fromScale(1, 1)
				holding = false
				token += 1
				Kit.Ticked:Fire(button, 1)
				Kit.punch(button, 1.2, Theme.Tween.Bump)
				task.spawn(onDone)
				task.delay(0.25, function()
					if token == mine + 1 then
						fill.Size = UDim2.fromScale(0, 1)
					end
				end)
			end)
		end)
	)
	table.insert(
		connections,
		button.InputEnded:Connect(function(input: InputObject)
			if isPress(input) then
				reset()
			end
		end)
	)
	table.insert(connections, button.MouseLeave:Connect(reset))
	table.insert(connections, button.SelectionLost:Connect(reset))
	return function()
		reset()
		for _, connection in connections do
			connection:Disconnect()
		end
		fill:Destroy()
	end
end

-- Idle breathing on a call to action: a slow, gentle grow and shrink (`amount`, default Theme.Juice.BreathScale),
-- paused while a press, hover or bump owns its scale, and restarting from rest after. Returns stop.
function Kit.breathing(gui: GuiObject, amount: number?): () -> ()
	local scale = scaleOf(gui)
	local amp = amount or Theme.Juice.BreathScale
	local since = os.clock()
	local job = addJob(gui, function(now): StepResult
		if isBusy(scale, now) then
			since = now
			return nil
		end
		scale.Scale = 1 + amp * Juice.breath(now - since, Theme.Juice.BreathSeconds)
		return nil
	end, function()
		if not isBusy(scale, os.clock()) then
			scale.Scale = 1
		end
	end)
	return function()
		job.Stopped = true
		if not isBusy(scale, os.clock()) then
			scale.Scale = 1
		end
	end
end

return Kit
