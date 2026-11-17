--!strict
-- Small UI building blocks so every screen looks and feels the same (build plan Task 0).
-- Each maker takes an optional props table: any Instance property (Size, Position, AnchorPoint, Text,
-- LayoutOrder, ...), plus Parent (set last) and the extras noted below. Colours and sizes come from Theme.
--
--   Kit.screen(name, displayOrder): ScreenGui       ResetOnSpawn off, inside the safe area, in PlayerGui
--   Kit.panel(props?): Frame                       flat white card, the Panel stroke; extra: Title = "Shop" adds
--                                                  THE header: a Kit.HEADER (64) px navy band (Theme.Colors.Header)
--                                                  with the title in white display text. A TITLE IS WORDS ONLY
--                                                  (memory-20261117-007): any emoji in it is dropped (Icons.words).
--                                                  Accent is IGNORED (every header is navy: look build plan §B8)
--   Kit.label(props?): TextLabel                   extra: Outlined = true -> display font, white text, dark stroke
--   Kit.button(props?): TextButton                 a button with a press bounce and (with a mouse) a hover grow, min
--                                                  56 px tall; extras: Kind (its ROLE), Fill (a game piece's own
--                                                  colour, e.g. a triage floor: candy roles only). The ROLES (look
--                                                  build plan §B8, ux audit §3.3):
--                                                    "Primary"     orange candy: Buy, Hire, Level up, List. One per
--                                                                  view; NEVER shines or breathes (red line 3)
--                                                    "Collect"     green candy: Claim, Open!, Yay!, ✅ Take it. The only
--                                                                  role that may shine or breathe
--                                                    "Secondary"   a quiet flat fill, ink text, NO outline:
--                                                                  everything else
--                                                    "Quiet"       no fill, no outline, ink text: links ("See odds")
--                                                    "Destructive" red candy: Sell, Reset, Throw away (always behind
--                                                                  Hud.confirm or a hold), and the modal's ✖
--                                                    "Icon"        a white plate with the Bold outline (HUD and tabs)
--                                                  Old kinds map (Kit.Juice.role): Good -> Collect, Danger ->
--                                                  Destructive, Pink/Purple/Cyan/Cash -> Secondary, Card -> Quiet; an
--                                                  unknown kind is Secondary. Kind nil = Primary (as before)
--   Kit.setRole(button, kind)                      repaints a Kit button as another role (or the "Disabled" look:
--                                                  grey with grey text and no outline, for "can't yet"; pair it with
--                                                  a gate note)
--   Kit.tab(button, selected, stripe?)             THE tab look (Modal.tabs paints with it). Unselected: NO plate
--                                                  and no line, ink caption · selected: Header (navy) fill, white
--                                                  outlined caption, no line · stripe: a 6 px left edge in the
--                                                  section's own colour (a wing, a rarity, a board)
--   Kit.textLimit(label, maxPx)                    THE text fit: a UITextSizeConstraint with MinTextSize =
--                                                  Theme.TextSize.Caption (18, the floor) and MaxTextSize =
--                                                  max(maxPx, 18). For TextScaled labels; no local copies
--   Kit.iconButton(props?): TextButton             the Icon plate: white, the Bold outline, the emoji at 60%, an
--                                                  optional caption, a "Dot" top-right; extras: Icon, Caption, Kind
--                                                  (default "Icon"), Glass = true (the dark-glass plate of the
--                                                  top-bar row, beside Roblox's own buttons)
--   Kit.setDot(button, visible, glyph?)            the red "something new" dot: pops in ONCE and stays still (no hop
--                                                  loop); a glyph (an emoji) turns it into a slightly bigger still
--                                                  sticker
--   Kit.setEnabled(button, enabled)                off: the Disabled look and no taps · on: its role again (and the
--                                                  KitColor attribute's fill, for callers that set their own)
--   Kit.corner(parent, radius?) · Kit.pad(parent, px?) · Kit.stroke(parent, colour?, px?)
--                                                  radius: px or a UDim (Theme.Radius.Round); default Radius.Medium
--   Kit.outline(text, px?): UIStroke              outlined text (a dark stroke around the letters)
--   Kit.list(parent, direction?, gap?) · Kit.popIn(gui) · Kit.popOut(gui, onDone?)
--   Kit.shade(colour, amount) · Kit.lighten(colour, amount)
--   Kit.shine(button): () -> ()                     a white shine sweeps across every few seconds. Collect buttons
--                                                  only (any other role rests: Kit.Juice.mayLoop); returns stop.
--                                                  Paused with reduced motion.
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
--   Kit.rarityFrame(gui, rarity): () -> ()         the rarity's frame: a UIStroke "RarityFrame" with a gradient in
--                                                  its colours (Common grey, Rare blue, Epic purple, Legendary
--                                                  rainbow, Mythic cosmic, Secret gold); returns stop. Always
--                                                  still (the motion budget: nothing on it loops)
--   Kit.rarityColor(rarity): Color3                the rarity's colour (Data/Rarities; unknown = Common grey)
--   Kit.breathing(gui, amount?): () -> ()          idle "breathing" on a Collect button while its reward waits: a
--                                                  slow gentle grow and shrink, paused while it's pressed or bounced
--                                                  (any other role rests); returns stop
-- Progression v2 (build plan §B9; T8 juiced the Foundation's first versions, same signatures):
--   Kit.ring(parent, color): (fraction) -> ()      a filling ring (ability cooldowns) round the edge of `parent`:
--                                                  Theme.Juice.RingBeads beads light up clockwise (the newest pops)
--                                                  WHILE IT RECHARGES. Full (ready) = nothing is drawn at all (UI
--                                                  direction R7: no decorative dots). Call the setter with 0..1
--                                                  (Kit.Juice.ringFraction). It NEVER prints seconds (red line 3)
--                                                  and never loops on its own
--   Kit.holdButton(button, seconds, onDone): () -> ()   hold-to-confirm: a bright band fills across the button and
--                                                  it swells a little while held, a rising tick each quarter
--                                                  (Kit.Ticked); onDone runs once the hold lasts `seconds`; letting
--                                                  go early empties it. Reduced motion: the same hold, the band steps
--                                                  by quarters and nothing swells. Returns stop
--   Kit.Juice                                      the pure helpers behind all this (no Roblox APIs; see below)
-- THE CALM UI (docs/plan/2026-11-17-ui-direction.md; Joshua, memory-20261117-007). "Candy on the verbs, calm on the
-- nouns." Panels build from these parts and never hand-build a card, a bar, a switch or a chip:
--   Kit.card(props?): Frame                        THE card: the Card fill, NO line, the Medium radius, PadCard (12)
--                                                  inside. Two surfaces, never three: the paper, then a card; the
--                                                  only thing inside a card is one Kit.artTile. extra: Pad = false
--                                                  (no padding). Default size: full width, as tall as its content
--   Kit.name(props?): TextLabel                    the Normal voice: a card's name, ONCE per card (Font, Body 22,
--                                                  Ink, left, one line, cut with "..." when too long)
--   Kit.fact(props?): TextLabel                    the Soft voice: a fact, count, hint, caption or a section
--                                                  heading in words (Font, Caption 18, InkSoft, left, one line).
--                                                  Facts are plain text joined with " · ", never chips or pills
--   Kit.voice(label, voice)                        paints any label or button text as "Loud", "Normal" or "Soft"
--                                                  (Theme.Voice)
--   Kit.bar(props?): (Frame, set)                  THE progress bar (one place): 8 px, navy on a Well track, no
--                                                  line and no text inside. set(fraction, atMax?) fills it (0..1;
--                                                  atMax = gold). extras: Value (the starting fraction), Max
--   Kit.artTile(props?): Frame                     THE art tile: a Well square (Theme.Calm.ArtTile) with ONE emoji
--                                                  at 40 px. extras: Icon (the Art emoji, from shared/Data), State
--                                                  (a State emoji: Kit.setState), Rarity (its Kit.rarityFrame).
--                                                  Without an Icon it is the well for a portrait
--   Kit.setState(gui, emoji?)                      the State badge (Icons.State: 🔒 ✅ 💤 ⏳) on the top-right corner
--                                                  of a tile or portrait: an 18 px emoji on a small round plate.
--                                                  nil or "" removes it. One per card
--   Kit.unit(props?): (Frame, TextLabel)           a Unit glued to its number where the number is Loud (outlined
--                                                  display text can't hold an emoji: Roblox can't outline one). The
--                                                  emoji and the number are two labels, 4 px apart. extras: Icon
--                                                  (Icons.Unit.Cash), Text ("300"), Voice (default "Normal"), Px
--                                                  (the text size). Returns the row and the number's label (for
--                                                  Kit.countUp). In Normal or Soft text use Icons.unit("Cash", n)
--   Kit.toggle(props?): (TextButton, set)          a Settings row: its Label on the left (words that never change
--                                                  with state) and a switch on the right, green when on. set(on,
--                                                  instant?) slides it (no bounce). The caller connects Activated.
--                                                  extras: Label, On
--   Kit.more(props?): TextButton                   THE "More" control: a Quiet text button that opens Kit.menu with
--                                                  the card's other actions (Sell, List). extras: Text (default
--                                                  "More"), Items ({ { Id, Text, Kind? } } or a function that
--                                                  returns them when it opens), OnPick (id)
--   Kit.menu(anchor, items, onPick): () -> ()      the overflow menu: a small paper card beside `anchor` with one
--                                                  Secondary button per item (Kind overrides). A tap outside, a
--                                                  pick, ButtonB or the screen closing shuts it; one at a time.
--                                                  Returns close
--   Kit.reveal(gui, shown): boolean                a HUD door arriving (UI direction R0): shown = true pops it ONCE
--                                                  into its fixed slot (it never moves) and returns true if it just
--                                                  appeared; false hides it. Kit.Juice.nextReveal picks which door
--                                                  is next, one at a time
-- THE OUTLINE BUDGET (R2): the dark outline is for the panel shell, candy buttons (Primary, Collect, Destructive),
-- HUD plates over the 3D world and text over the world or over colour. Nothing else inside a white panel has one.
-- ZIndex 0 is the decoration layer inside a Kit button or panel (Gloss, Shine, Header, Rays): it draws over the
-- parent's own fill but under every other child, so give your own children ZIndex 1 or more (the default).
--   Kit.Clicked: Signal (button)                   fires on every Kit button press (Sounds plays a click)
--   Kit.Ticked: Signal (label, progress)           a count-up showed a new number (progress 0..1; Sounds ticks)
--   Kit.reducedMotion(): boolean                   honour it in your own tweens too
-- Every looping effect here (rays, breathing, shines, shimmer, count-ups, confetti) runs on ONE shared loop that
-- skips anything not on screen and sleeps (4 checks a second) while nothing is moving.
-- THE MOTION BUDGET (Theme.Motion.Perpetual = 1; ux audit §3.4): shines and breathing are "perpetual" effects, and
-- only ONE button's may run on screen at a time: the Collect button on the topmost screen (its ScreenGui's
-- DisplayOrder), the oldest first on a tie (Kit.Juice.pickPerpetual). The others rest until it goes.
-- Radii come from Theme.Radius and strokes from Theme.Stroke (look build plan §B8).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Palette = require(Shared:WaitForChild("Palette"))
local Signal = require(Shared:WaitForChild("Signal"))
local Rarities = require(Shared:WaitForChild("Data"):WaitForChild("Rarities")) :: any
local Icons = require(script.Parent.Icons)
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

-- The look overhaul's button roles (look build plan §B8; ux audit §3.3), and what each old colour kind became.
Juice.ROLES = { "Primary", "Collect", "Secondary", "Quiet", "Destructive", "Icon" }
Juice.OLD_KINDS = {
	Good = "Collect",
	Danger = "Destructive",
	Pink = "Secondary",
	Purple = "Secondary",
	Cyan = "Secondary",
	Cash = "Secondary",
	Card = "Quiet",
}

-- A Kind's role: a role is itself, an old kind maps, "Disabled" is the can't-yet look, nil is Primary (Kit.button's
-- default since the start), and anything else is the calm Secondary (never a loud colour by accident).
function Juice.role(kind: any): string
	if kind == nil then
		return "Primary"
	end
	if type(kind) ~= "string" then
		return "Secondary"
	end
	if kind == "Disabled" or table.find(Juice.ROLES, kind) then
		return kind
	end
	return Juice.OLD_KINDS[kind] or "Secondary"
end

export type Look = {
	Fill: string, -- a Theme.Colors key
	Text: string, -- a Theme.Colors key
	Candy: boolean, -- gradient, gloss, display font and white outlined text
	Stroke: string?, -- a Theme.Stroke key; nil = no outline
	Clear: boolean, -- no fill at all
}
-- How each role (and the Disabled look) is drawn, by Theme key: Kit paints from this table.
-- THE OUTLINE BUDGET (UI direction R2): only the candy roles and the Icon plate (HUD, over the 3D world) carry the
-- dark outline. Secondary and Disabled are flat fills with no line.
Juice.LOOKS = {
	Primary = { Fill = "Primary", Text = "OnColor", Candy = true, Stroke = "Bold", Clear = false },
	Collect = { Fill = "Collect", Text = "OnColor", Candy = true, Stroke = "Bold", Clear = false },
	Destructive = { Fill = "Destructive", Text = "OnColor", Candy = true, Stroke = "Bold", Clear = false },
	Secondary = { Fill = "Secondary", Text = "Ink", Candy = false, Stroke = nil, Clear = false },
	Quiet = { Fill = "Secondary", Text = "Ink", Candy = false, Stroke = nil, Clear = true },
	Icon = { Fill = "Plate", Text = "Ink", Candy = false, Stroke = "Bold", Clear = false },
	Disabled = { Fill = "Disabled", Text = "DisabledText", Candy = false, Stroke = nil, Clear = false },
} :: { [string]: Look }

function Juice.look(kind: any): Look
	return Juice.LOOKS[Juice.role(kind)] or Juice.LOOKS.Secondary
end

-- Only a Collect button may shine or breathe (red line 3: nothing loud points at spending).
function Juice.mayLoop(role: any): boolean
	return role == "Collect"
end

-- The motion budget: which of the perpetual effects on screen may run. Each candidate is { Order = its screen's
-- DisplayOrder, Seq = when it was made }; the topmost screen wins, then the oldest. Returns its index (nil for none).
function Juice.pickPerpetual(candidates: { { Order: number, Seq: number } }): number?
	local best: number? = nil
	for index, candidate in candidates do
		local current = if best then candidates[best] else nil
		if
			current == nil
			or candidate.Order > current.Order
			or (candidate.Order == current.Order and candidate.Seq < current.Seq)
		then
			best = index
		end
	end
	return best
end

-- The calm UI. A progress bar's fill: `value` of `goal` as 0..1 (junk, a zero or a negative goal = 0; at or past the
-- goal = 1). With no goal, `value` is already the fraction.
function Juice.barFraction(value: any, goal: any): number
	local v = finite(value)
	if v == nil then
		return 0
	end
	if goal == nil then
		return math.clamp(v, 0, 1)
	end
	local g = finite(goal)
	if g == nil or g <= 0 then
		return 0
	end
	return math.clamp(v / g, 0, 1)
end

-- HUD doors arrive ONE AT A TIME (UI direction R0): the first id in `order` that is wanted (it has content now) and
-- not shown yet, or nil when nothing is waiting. The caller shows it (Kit.reveal), waits, and asks again.
function Juice.nextReveal(order: { string }, wanted: { [string]: any }, shown: { [string]: any }): string?
	for _, id in order do
		if wanted[id] and not shown[id] then
			return id
		end
	end
	return nil
end

-- Where the "More" menu sits: under its anchor with their right edges in line, above it when there is no room
-- below, and always inside the screen by `gap`. All in the screen's own px. Returns the menu's top-left corner.
function Juice.menuPlace(
	anchor: { X: number, Y: number, W: number, H: number },
	menu: { W: number, H: number },
	screen: { W: number, H: number },
	gap: number
): (number, number)
	local x = anchor.X + anchor.W - menu.W
	x = math.max(gap, math.min(x, screen.W - menu.W - gap))
	local y = anchor.Y + anchor.H + gap
	if y + menu.H > screen.H - gap then
		y = anchor.Y - gap - menu.H
	end
	y = math.max(gap, math.min(y, screen.H - menu.H - gap))
	return x, y
end
-- END JUICE

Kit.Juice = Juice

-- The header band's height (ux audit §3.2): Kit.panel draws it, UI/Modal lays its body out under it.
Kit.HEADER = 64

-- Props that are Kit's own, not Instance properties.
local EXTRA_KEYS: { [string]: boolean } = {}
for _, key in
	{
		"Parent",
		"Kind",
		"Title",
		"Icon",
		"Caption",
		"Accent",
		"Outlined",
		"Fill",
		"Glass",
		-- the calm parts' extras
		"Pad",
		"Value",
		"Max",
		"State",
		"Rarity",
		"Voice",
		"Px",
		"Label",
		"On",
		"Items",
		"OnPick",
	}
do
	EXTRA_KEYS[key] = true
end

local function colorOf(key: string): Color3
	local color = (Theme.Colors :: any)[key]
	return if typeof(color) == "Color3" then color else Theme.Colors.Secondary
end

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

-- radius: px (a Theme.Radius token) or a UDim (Theme.Radius.Round); default Theme.Radius.Medium.
function Kit.corner(parent: Instance, radius: (number | UDim)?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = if typeof(radius) == "UDim"
		then radius
		else UDim.new(0, if type(radius) == "number" then radius else Theme.Radius.Medium)
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

function Kit.stroke(parent: Instance, color: Color3?, px: number?): UIStroke -- uirules: allow StrokeBudget
	local stroke = Instance.new("UIStroke") -- uirules: allow StrokeBudget (the maker itself)
	stroke.Color = color or Theme.Colors.Stroke
	stroke.Thickness = px or Theme.Stroke.Bold
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function Kit.outline(text: GuiObject, px: number?): UIStroke
	return Palette.outlineText(text, px or Theme.Stroke.Text)
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
	Owner: GuiObject?, -- a perpetual effect's button (shine, breathing): the motion budget runs one owner's
	Seq: number,
}

local ORPHAN_SECONDS = 5
local jobs: { Job } = {}
local looping = false
local jobSeq = 0

-- The DisplayOrder of the screen a gui is on (0 when it isn't on one).
local function screenOrder(gui: Instance): number
	local screen = gui:FindFirstAncestorWhichIsA("LayerCollector")
	return if screen and screen:IsA("ScreenGui") then screen.DisplayOrder else 0
end

-- The motion budget: the one owner whose perpetual effects may run this frame (Kit.Juice.pickPerpetual), among the
-- Collect buttons on screen with one.
local function perpetualOwner(): GuiObject?
	local owners: { GuiObject } = {}
	local candidates: { { Order: number, Seq: number } } = {}
	local seen: { [GuiObject]: boolean } = {}
	for _, job in jobs do
		local owner = job.Owner
		if
			owner
			and not seen[owner]
			and not job.Stopped
			and owner.Parent ~= nil
			and Juice.mayLoop(owner:GetAttribute("KitKind"))
			and isShown(job.Gui)
		then
			seen[owner] = true
			table.insert(owners, owner)
			table.insert(candidates, { Order = screenOrder(owner), Seq = job.Seq })
		end
	end
	local pick = Juice.pickPerpetual(candidates)
	return if pick then owners[pick] else nil
end

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
			local allowed = if calm then nil else perpetualOwner()
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
						-- Over the motion budget (another button's turn, or not a Collect button): rest like calm.
						if calm or (job.Owner ~= nil and job.Owner ~= allowed) then
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

local function addJob(
	gui: GuiObject,
	step: (now: number, dt: number) -> StepResult,
	rest: (() -> ())?,
	owner: GuiObject?
): Job
	jobSeq += 1
	local job: Job = {
		Gui = gui,
		Step = step,
		Rest = rest,
		Resting = false,
		Stopped = false,
		Orphaned = nil,
		Owner = owner,
		Seq = jobSeq,
	}
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

-- The paper card: flat white (no gradient), the Large radius, the Panel stroke, PadPanel inside. With a Title, THE
-- header: one Kit.HEADER px navy band (Theme.Colors.Header) across the top, out through the padding, with the title
-- in white display text (the Title stroke). The title is WORDS ONLY (memory-20261117-007): an emoji a caller still
-- passes is dropped. Accent is ignored: every header is navy (look build plan §B8).
function Kit.panel(props: Props?): Frame
	local pad = Theme.Space.PadPanel
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.92, 0.8)
	panel.BackgroundColor3 = Theme.Colors.Paper
	panel.BorderSizePixel = 0
	Kit.corner(panel, Theme.Radius.Large)
	Kit.stroke(panel, Theme.Colors.Stroke, Theme.Stroke.Panel) -- uirules: allow StrokeBudget (the panel shell)
	Kit.pad(panel, pad)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(Theme.Size.PanelMaxWidth, Theme.Size.PanelMaxHeight)
	limit.Parent = panel
	apply(panel, props)
	if props and type(props.Title) == "string" then
		local header = Instance.new("Frame")
		header.Name = "Header"
		header.ZIndex = 0
		header.Position = UDim2.fromOffset(-pad, -pad)
		header.Size = UDim2.new(1, pad * 2, 0, Kit.HEADER)
		header.BackgroundColor3 = Theme.Colors.Header
		header.BorderSizePixel = 0
		Kit.corner(header, Theme.Radius.Large)
		local foot = Instance.new("Frame") -- squares off the band's bottom corners
		foot.Name = "Foot"
		foot.ZIndex = 0
		foot.AnchorPoint = Vector2.new(0, 1)
		foot.Position = UDim2.fromScale(0, 1)
		foot.Size = UDim2.new(1, 0, 0, Theme.Radius.Large)
		foot.BackgroundColor3 = Theme.Colors.Header
		foot.BorderSizePixel = 0
		foot.Parent = header
		header.Parent = panel
		local title = Kit.label({
			Name = "Title",
			Text = Icons.words(props.Title),
			TextScaled = true,
			TextWrapped = false,
			Outlined = true,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(0, Kit.HEADER / 2 - pad),
			Size = UDim2.new(1, -Theme.Size.ButtonHeight - Theme.Space.Gap, 0, Kit.HEADER - Theme.Space.PadCard * 2),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 2,
			Parent = panel,
		})
		Kit.outline(title, Theme.Stroke.Title)
		Kit.textLimit(title, Theme.TextSize.Title)
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
	Kit.corner(gloss, Theme.Radius.Small)
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(0.15, 1)
	fade.Parent = gloss
	gloss.Parent = button
	return gloss
end
Kit.gloss = addGloss

-- The shape outline Kit draws round a button (not the Contextual one round its text).
local function borderOf(gui: Instance): UIStroke?
	for _, child in gui:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
			return child
		end
	end
	return nil
end

-- Paints a button (and its Caption, if it's an iconButton) with a look from Kit.Juice.LOOKS. `fill` overrides the
-- look's fill (a game piece's own colour, or the KitColor a caller set). Never touches the KitKind attribute.
local function paint(button: GuiButton, lookName: string, fill: Color3?)
	local look = Juice.LOOKS[lookName] or Juice.LOOKS.Secondary
	local base = fill or colorOf(look.Fill)
	button.BackgroundColor3 = if look.Candy and fill == nil then Kit.lighten(base, 0.08) else base
	button.BackgroundTransparency = if look.Clear then 1 else 0
	local textColor = colorOf(look.Text)
	local function ink(text: Instance?)
		if text and (text:IsA("TextLabel") or text:IsA("TextButton")) then
			text.TextColor3 = textColor
			local outline = text:FindFirstChild("TextOutline")
			if look.Candy then
				Kit.outline(text).Enabled = true
			elseif outline and outline:IsA("UIStroke") then
				outline.Enabled = false
			end
		end
	end
	if button:IsA("TextButton") then
		button.Font = if look.Candy then Theme.DisplayFont else Theme.Font
		ink(button)
	end
	ink(button:FindFirstChild("Caption"))
	local border = borderOf(button)
	if border then
		border.Enabled = look.Stroke ~= nil
		border.Color = Theme.Colors.Stroke
		border.Thickness = (Theme.Stroke :: any)[look.Stroke or "Fine"] or Theme.Stroke.Fine
	end
	local gradient = button:FindFirstChild("CandyGradient")
	if gradient and gradient:IsA("UIGradient") then
		gradient.Enabled = look.Candy
	end
	local gloss = button:FindFirstChild("Gloss")
	if gloss and gloss:IsA("GuiObject") then
		gloss.Visible = look.Candy
	end
end

-- Repaints a Kit button as a role (Kit.Juice.role maps old kinds), or the "Disabled" can't-yet look.
function Kit.setRole(button: GuiButton, kind: string)
	local role = Juice.role(kind)
	local fill = button:GetAttribute("KitFill")
	paint(button, role, if typeof(fill) == "Color3" and (Juice.LOOKS[role] :: any).Candy then fill else nil)
	button:SetAttribute("KitKind", role)
	button:SetAttribute("KitColor", button.BackgroundColor3)
end

function Kit.button(props: Props?): TextButton
	local role = Juice.role(if props then props.Kind else nil)
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(180, Theme.Size.ButtonHeight)
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.TextSize = Theme.TextSize.Body
	button.TextStrokeTransparency = 1
	button.Text = ""
	Kit.corner(button, Theme.Radius.Medium)
	Kit.stroke(button, Theme.Colors.Stroke, Theme.Stroke.Bold) -- uirules: allow StrokeBudget (candy and Icon looks)
	Palette.candyGradient(button)
	addGloss(button)
	local minimum = Instance.new("UISizeConstraint")
	minimum.MinSize = Vector2.new(Theme.Size.ButtonHeight, Theme.Size.ButtonHeight)
	minimum.Parent = button
	if props and typeof(props.Fill) == "Color3" then
		button:SetAttribute("KitFill", props.Fill)
	end
	Kit.setRole(button, role)
	addBounce(button)
	apply(button, props)
	return finish(button, props)
end

-- THE Icon plate (ux audit §3.3): white with the Bold outline (Glass: the top-bar row's dark glass), the emoji at
-- 60%, an optional caption under it, and the red dot top-right.
function Kit.iconButton(props: Props?): TextButton
	local kind = if props and type(props.Kind) == "string" then props.Kind else "Icon"
	local glass = props ~= nil and props.Glass == true
	local button = Kit.button({ Kind = kind, Size = UDim2.fromOffset(Theme.Size.IconButton, Theme.Size.IconButton) })
	local caption = if props and type(props.Caption) == "string" then props.Caption else nil

	Kit.label({
		Name = "Icon",
		Text = if props and type(props.Icon) == "string" then props.Icon else "",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, if caption then 0.06 else 0.2),
		Size = UDim2.fromScale(0.6, if caption then 0.56 else 0.6),
		ZIndex = 2,
		Parent = button,
	})
	if caption then
		local label = Kit.label({
			Name = "Caption",
			Text = caption,
			TextScaled = true,
			TextWrapped = false,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.98),
			Size = UDim2.new(1, -Theme.Space.Step[1], 0.36, 0),
			ZIndex = 2,
			Parent = button,
		})
		Kit.textLimit(label, Theme.TextSize.Caption)
	end
	Kit.setRole(button, kind) -- again, now the caption is there
	if glass then
		-- Roblox's own top-bar buttons: dark glass, white glyph, no outline.
		button.BackgroundColor3 = Theme.Colors.Shade
		button.BackgroundTransparency = 0.3
		button:SetAttribute("KitColor", Theme.Colors.Shade)
		local border = borderOf(button)
		if border then
			border.Enabled = false
		end
		local label = button:FindFirstChild("Caption")
		if label and label:IsA("TextLabel") then
			label.TextColor3 = Theme.Colors.OnColor
		end
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
	Kit.corner(dot, Theme.Radius.Round)
	Kit.stroke(dot, Theme.Colors.Stroke, Theme.Stroke.Fine) -- uirules: allow StrokeBudget (a HUD plate's dot)
	dot.Parent = button

	apply(button, props)
	return finish(button, props)
end

-- THE tab look (look build plan §B8; Modal.tabs paints with it). `button` is a Kit.iconButton (its Icon and Caption
-- labels) or any text button. The calm UI (UI direction change 1): unselected = NO plate and no line, just the icon
-- and an ink caption · selected: the navy Header fill and a white outlined caption (text over colour), no line ·
-- stripe: a 6 px left edge in the section's own colour (its only colour here).
function Kit.tab(button: GuiButton, selected: boolean, stripe: Color3?)
	local fill = if selected then Theme.Colors.Header else Theme.Colors.Card
	button.BackgroundColor3 = fill
	button.BackgroundTransparency = if selected then 0 else 1
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
	local border = borderOf(button)
	if border then
		border.Enabled = false -- the outline budget (R2): a tab inside a white panel has no dark line
	end
	local function ink(text: Instance?)
		if text and (text:IsA("TextLabel") or text:IsA("TextButton")) then
			text.TextColor3 = if selected then Theme.Colors.OnColor else Theme.Colors.Ink
			local outline = text:FindFirstChild("TextOutline")
			if selected then
				Kit.outline(text).Enabled = true
			elseif outline and outline:IsA("UIStroke") then
				outline.Enabled = false
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

-- The red dot pops in ONCE when it appears and then stays still (the motion budget: no hop loop). A glyph sticker
-- (🃏 / 🌳) is still too.
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
	end
end

-- Off: the Disabled look (grey, grey text) and no taps. On: the button's role again, with the fill a caller stored in
-- KitColor (the role's own when none).
function Kit.setEnabled(button: GuiButton, enabled: boolean)
	button.Interactable = enabled
	local role = button:GetAttribute("KitKind")
	local roleName = if type(role) == "string" then role else "Secondary"
	if enabled then
		local color = button:GetAttribute("KitColor")
		paint(button, roleName, if typeof(color) == "Color3" then color else nil)
	else
		paint(button, "Disabled", nil)
	end
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

-- A white shine that sweeps across a Collect button every Theme.ShineEvery seconds (any other role rests: red line 3,
-- nothing loud points at spending). It runs on the shared loop under the motion budget. Returns stop.
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
	Kit.corner(shine, Theme.Radius.Medium)
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

	-- A sweep every ShineEvery seconds; between sweeps the band rests off the edge (an idle step).
	local sweep = Theme.Tween.Shine.Time
	local started = os.clock()
	local resting = true
	local function park()
		if not resting then
			resting = true
			band.Offset = Vector2.new(-1, 0)
		end
	end
	local job = addJob(shine, function(now): StepResult
		local phase = (now - started) % (Theme.ShineEvery + sweep)
		if phase < Theme.ShineEvery then
			park()
			return "idle"
		end
		resting = false
		band.Offset = Vector2.new(-1 + 2 * Juice.ease((phase - Theme.ShineEvery) / sweep), 0)
		return nil
	end, park, button)
	return function()
		job.Stopped = true
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
-- The calm UI (docs/plan/2026-11-17-ui-direction.md; Joshua, memory-20261117-007): candy on the verbs, calm on the
-- nouns. The parts every panel builds from, so nobody hand-builds a card, a bar, a switch or a chip.
------------------------------------------------------------------------------------------------------------------

-- Paints a label's (or a button's) text in one of the three voices (Theme.Voice): Loud = display font, white,
-- outlined (over colour only) · Normal = body font, Body, Ink · Soft = body font, Caption, InkSoft.
function Kit.voice(text: TextLabel | TextButton, voice: string)
	local look = (Theme.Voice :: any)[voice] or Theme.Voice.Normal
	local size = (Theme.TextSize :: any)[look.Size] or Theme.TextSize.Body
	text.Font = if look.Font == "DisplayFont" then Theme.DisplayFont else Theme.Font
	text.TextColor3 = colorOf(look.Ink)
	text.TextSize = size
	if text.TextScaled then
		Kit.textLimit(text, size)
	end
	local outline = text:FindFirstChild("TextOutline")
	if look.Outlined then
		Kit.outline(text).Enabled = true
	elseif outline and outline:IsA("UIStroke") then
		outline.Enabled = false
	end
end

-- One line of text in a voice: left, one line, cut with an ellipsis when it is too long (never shrunk under 18 px).
local function line(voice: string, name: string, props: Props?): TextLabel
	local size = (Theme.TextSize :: any)[(Theme.Voice :: any)[voice].Size]
	local label = Kit.label({
		Name = name,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, size + Theme.Space.Tight),
	})
	Kit.voice(label, voice)
	apply(label, props)
	return finish(label, props)
end

-- The Normal voice: a card's name. Once per card.
function Kit.name(props: Props?): TextLabel
	return line("Normal", "Name", props)
end

-- The Soft voice: a fact, a count, a hint, a caption, a section heading in words. Plain text, never a chip.
function Kit.fact(props: Props?): TextLabel
	return line("Soft", "Fact", props)
end

-- THE card (R2, R3): the Card fill and nothing else. No line, no shadow, no gloss. PadCard inside (Pad = false: none).
function Kit.card(props: Props?): Frame
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.BackgroundColor3 = Theme.Colors.Card
	card.BorderSizePixel = 0
	card.Size = UDim2.fromScale(1, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	Kit.corner(card, Theme.Radius.Medium)
	if not (props and props.Pad == false) then
		Kit.pad(card, Theme.Space.PadCard)
	end
	apply(card, props)
	return finish(card, props)
end

-- THE progress bar (R6: progress is navy, gold at MAX; one place). Theme.Calm.Bar px tall, a Track with a fill, no
-- line, no text inside (the count is a Kit.fact beside it). Returns the bar and set(fraction, atMax?): the fill
-- slides there (Theme.Tween.Fill; at once the first time, with reduced motion or while not on screen).
function Kit.bar(props: Props?): (Frame, (fraction: number, atMax: boolean?) -> ())
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundColor3 = Theme.Colors.Track
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(1, 0, 0, Theme.Calm.Bar)
	Kit.corner(bar, Theme.Radius.Round)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Theme.Colors.Progress
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Visible = false
	Kit.corner(fill, Theme.Radius.Round)
	fill.Parent = bar

	local first = true
	local running: Tween? = nil
	local function set(fraction: number, atMax: boolean?)
		local share = Juice.barFraction(fraction, nil)
		fill.BackgroundColor3 = if atMax == true then Theme.Colors.ProgressMax else Theme.Colors.Progress
		bar:SetAttribute("Fraction", share)
		if running then
			running:Cancel()
			running = nil
		end
		local target = UDim2.fromScale(share, 1)
		if share > 0 then
			fill.Visible = true
		end
		if first or Kit.reducedMotion() or not isShown(bar) then
			fill.Size = target
			fill.Visible = share > 0
		else
			local tween = TweenService:Create(fill, Theme.Tween.Fill, { Size = target })
			running = tween
			tween.Completed:Once(function(state)
				if state == Enum.PlaybackState.Completed then
					fill.Visible = share > 0
				end
			end)
			tween:Play()
		end
		first = false
	end
	apply(bar, props)
	set(if props and type(props.Value) == "number" then props.Value else 0, props ~= nil and props.Max == true)
	return finish(bar, props), set
end

-- The State badge (Icons.State) on the top-right corner of a tile or a portrait: one 18 px emoji on a small round
-- paper plate, no line. nil or "" takes it away. One per card.
function Kit.setState(gui: GuiObject, emoji: string?)
	local existing = gui:FindFirstChild("State")
	if type(emoji) ~= "string" or emoji == "" then
		if existing then
			existing:Destroy()
		end
		return
	end
	local badge: Frame
	if existing and existing:IsA("Frame") then
		badge = existing
	else
		local side = Theme.Calm.Badge
		local made = Instance.new("Frame")
		made.Name = "State"
		made.AnchorPoint = Vector2.new(0.5, 0.5)
		made.Position = UDim2.new(1, -Theme.Space.Tight, 0, Theme.Space.Tight)
		made.Size = UDim2.fromOffset(side, side)
		made.BackgroundColor3 = Theme.Colors.Paper
		made.BorderSizePixel = 0
		made.ZIndex = gui.ZIndex + 2
		Kit.corner(made, Theme.Radius.Round)
		Kit.label({
			Name = "Icon",
			Text = "",
			TextSize = Theme.Emoji.State,
			TextWrapped = false,
			Size = UDim2.fromScale(1, 1),
			ZIndex = gui.ZIndex + 3,
			Parent = made,
		})
		made.Parent = gui
		badge = made
	end
	local icon = badge:FindFirstChild("Icon")
	if icon and icon:IsA("TextLabel") then
		icon.Text = emoji
	end
end

-- THE art tile (R3: the one thing allowed inside a card): a Well square with ONE Art emoji at Theme.Emoji.Art (40),
-- no line. Icon = the emoji (from shared/Data, never typed in a UI file); without one it is the well for a
-- portrait. State = its State badge; Rarity = the rarity frame round it (rarity's only colour).
function Kit.artTile(props: Props?): Frame
	local side = Theme.Calm.ArtTile
	local tile = Instance.new("Frame")
	tile.Name = "ArtTile"
	tile.BackgroundColor3 = Theme.Colors.Well
	tile.BorderSizePixel = 0
	tile.Size = UDim2.fromOffset(side, side)
	Kit.corner(tile, Theme.Radius.Small)
	if props and type(props.Icon) == "string" then
		local icon = Kit.label({
			Name = "Icon",
			Text = props.Icon,
			TextScaled = true,
			TextWrapped = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.76, 0.76),
			Parent = tile,
		})
		Kit.textLimit(icon, Theme.Emoji.Art)
	end
	apply(tile, props)
	if props and type(props.Rarity) == "string" then
		Kit.rarityFrame(tile, props.Rarity)
	end
	if props and type(props.State) == "string" then
		Kit.setState(tile, props.State)
	end
	return finish(tile, props)
end

-- A Unit glued to its number (Icons.Unit: 💰 Cash, ⭐ Stars, 🏥 the level, 🌳 tree points): the emoji and the number
-- are TWO labels 4 px apart, because Roblox can't outline or tint an emoji, so one inside Loud (outlined) text
-- looks pasted on. Voice (default "Normal") paints the number; Px sets both sizes. Returns the row (as wide as its
-- content) and the number's label, for Kit.countUp.
function Kit.unit(props: Props?): (Frame, TextLabel)
	local voice = if props and type(props.Voice) == "string" then props.Voice else "Normal"
	local look = (Theme.Voice :: any)[voice] or Theme.Voice.Normal
	local px = if props and type(props.Px) == "number"
		then math.max(props.Px, Theme.TextSize.Caption)
		else (Theme.TextSize :: any)[look.Size]
	local row = Instance.new("Frame")
	row.Name = "Unit"
	row.BackgroundTransparency = 1
	row.AutomaticSize = Enum.AutomaticSize.X
	row.Size = UDim2.fromOffset(0, px + Theme.Space.Line)
	local list = Kit.list(row, Enum.FillDirection.Horizontal, Theme.Space.Tight)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Left
	Kit.label({
		Name = "Icon",
		Text = if props and type(props.Icon) == "string" then props.Icon else "",
		TextSize = px,
		TextWrapped = false,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 1,
		Parent = row,
	})
	local amount = Kit.label({
		Name = "Amount",
		Text = if props and props.Text ~= nil then tostring(props.Text) else "",
		TextWrapped = false,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 2,
		Parent = row,
	})
	Kit.voice(amount, voice)
	amount.TextSize = px
	apply(row, props)
	return finish(row, props), amount
end

-- A Settings row (UI direction: "Music" + a switch, not a button whose words change): the Label on the left in the
-- Normal voice, a switch on the right, green (Collect) when on and grey when off, its knob on the right when on (so
-- the state never rides on colour alone). The whole row is the tap target (56 px tall); the caller connects
-- Activated and calls set(on). The knob SLIDES (Theme.Tween.Switch): a toggle doesn't bounce (R7).
function Kit.toggle(props: Props?): (TextButton, (on: boolean, instant: boolean?) -> ())
	local row = Kit.button({ Kind = "Quiet", Text = "", Size = UDim2.new(1, 0, 0, Theme.Size.ButtonHeight) })
	local width, height, knobSide = Theme.Calm.SwitchWidth, Theme.Calm.SwitchHeight, Theme.Calm.Knob
	local inset = (height - knobSide) / 2
	local label = Kit.name({
		Name = "Label",
		Text = if props and type(props.Label) == "string" then props.Label else "",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, Theme.Space.PadCard, 0.5, 0),
		Size = UDim2.new(1, -(width + Theme.Space.PadCard * 2 + Theme.Space.Line), 1, 0),
		ZIndex = 2,
		Parent = row,
	})
	label.TextScaled = true
	Kit.textLimit(label, Theme.TextSize.Body)
	local track = Instance.new("Frame")
	track.Name = "Switch"
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.new(1, -Theme.Space.PadCard, 0.5, 0)
	track.Size = UDim2.fromOffset(width, height)
	track.BackgroundColor3 = Theme.Colors.Disabled
	track.BorderSizePixel = 0
	track.ZIndex = 2
	Kit.corner(track, Theme.Radius.Round)
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Position = UDim2.new(0, inset, 0.5, 0)
	knob.Size = UDim2.fromOffset(knobSide, knobSide)
	knob.BackgroundColor3 = Theme.Colors.Paper
	knob.BorderSizePixel = 0
	knob.ZIndex = 3
	Kit.corner(knob, Theme.Radius.Round)
	knob.Parent = track
	track.Parent = row

	local running: Tween? = nil
	local function set(on: boolean, instant: boolean?)
		local isOn = on == true
		row:SetAttribute("On", isOn)
		track.BackgroundColor3 = if isOn then Theme.Colors.Collect else Theme.Colors.Disabled
		local target = UDim2.new(0, if isOn then width - inset - knobSide else inset, 0.5, 0)
		if running then
			running:Cancel()
			running = nil
		end
		if instant == true or Kit.reducedMotion() or not isShown(row) then
			knob.Position = target
		else
			local tween = TweenService:Create(knob, Theme.Tween.Switch, { Position = target })
			running = tween
			tween:Play()
		end
	end
	apply(row, props)
	set(props ~= nil and props.On == true, true)
	return finish(row, props), set
end

-- The overflow menu behind "More" (UI direction: Sell and List sit behind More, so a card has ONE obvious action
-- and a stray tap never sells a nurse). A small paper card beside `anchor`, on the anchor's own screen above
-- everything else on it: one Secondary button per item (an item's Kind overrides). It closes on a pick (then
-- onPick(id) runs), a tap anywhere else, ButtonB, or when its screen closes. One menu at a time. Returns close.
export type MenuItem = { Id: string, Text: string, Kind: string? }
local MENU_ACTION = "KitCloseMenu"
local MENU_Z = 900
local closeMenu: (() -> ())? = nil

function Kit.menu(anchor: GuiObject, items: { MenuItem }, onPick: (id: string) -> ()): () -> ()
	if closeMenu then
		closeMenu()
	end
	-- The anchor's screen: the menu sits on it, above everything else there.
	local screen: LayerCollector? = nil
	local node: Instance? = anchor.Parent
	while node do
		if node:IsA("LayerCollector") then
			screen = node
			break
		end
		node = node.Parent
	end
	if not screen or #items == 0 then
		return function() end
	end
	local gap = Theme.Space.Line
	local rowHeight = Theme.Size.ButtonHeight
	local width = Theme.Calm.MenuWidth
	local height = #items * rowHeight + (#items - 1) * Theme.Space.Tight + gap * 2

	-- Anything tapped outside the menu closes it (and the tap goes no further).
	local catcher = Instance.new("TextButton")
	catcher.Name = "MenuCatcher"
	catcher.Text = ""
	catcher.AutoButtonColor = false
	catcher.Selectable = false
	catcher.BackgroundTransparency = 1
	catcher.Position = UDim2.fromOffset(-400, -400)
	catcher.Size = UDim2.new(1, 800, 1, 800)
	catcher.ZIndex = MENU_Z
	catcher.Parent = screen

	local origin, bounds = screen.AbsolutePosition, screen.AbsoluteSize
	local x, y = Juice.menuPlace({
		X = anchor.AbsolutePosition.X - origin.X,
		Y = anchor.AbsolutePosition.Y - origin.Y,
		W = anchor.AbsoluteSize.X,
		H = anchor.AbsoluteSize.Y,
	}, { W = width, H = height }, { W = bounds.X, H = bounds.Y }, Theme.Space.Tight)
	local card = Instance.new("Frame")
	card.Name = "Menu"
	card.Position = UDim2.fromOffset(x, y)
	card.Size = UDim2.fromOffset(width, height)
	card.BackgroundColor3 = Theme.Colors.Paper
	card.BorderSizePixel = 0
	card.ZIndex = MENU_Z + 1
	card.Active = true
	card.SelectionGroup = true
	card.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	Kit.corner(card, Theme.Radius.Medium)
	Kit.stroke(card, Theme.Colors.Stroke, Theme.Stroke.Bold) -- uirules: allow StrokeBudget (a floating shell)
	Kit.pad(card, gap)
	local list = Kit.list(card, Enum.FillDirection.Vertical, Theme.Space.Tight)
	list.VerticalAlignment = Enum.VerticalAlignment.Top

	local closed = false
	local connections: { RBXScriptConnection } = {}
	local hadFocus = GuiService.SelectedObject ~= nil
	local function close()
		if closed then
			return
		end
		closed = true
		if closeMenu == close then
			closeMenu = nil
		end
		ContextActionService:UnbindAction(MENU_ACTION)
		for _, connection in connections do
			connection:Disconnect()
		end
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(card) then
			GuiService.SelectedObject = if anchor.Parent and isShown(anchor) then anchor else nil
		end
		catcher:Destroy()
		card:Destroy()
	end

	local firstButton: TextButton? = nil
	for index, item in items do
		local button = Kit.button({
			Name = "Item_" .. item.Id,
			Kind = item.Kind or "Secondary",
			Text = item.Text,
			TextScaled = true,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, rowHeight),
			ZIndex = MENU_Z + 2,
			Parent = card,
		})
		Kit.textLimit(button, Theme.TextSize.Body)
		firstButton = firstButton or button
		button.Activated:Connect(function()
			close()
			onPick(item.Id)
		end)
	end
	card.Parent = screen
	Kit.punch(card, 0.9, Theme.Tween.Fade)

	table.insert(connections, catcher.Activated:Connect(close))
	table.insert(connections, anchor.Destroying:Connect(close))
	table.insert(connections, screen:GetPropertyChangedSignal("Enabled"):Connect(close))
	-- ButtonB closes the menu first (above the modal's own close).
	ContextActionService:BindActionAtPriority(MENU_ACTION, function(_, inputState: Enum.UserInputState)
		if inputState == Enum.UserInputState.Begin then
			close()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 1, Enum.KeyCode.ButtonB)
	if hadFocus and firstButton then
		GuiService.SelectedObject = firstButton
	end
	closeMenu = close
	return close
end

-- THE "More" control: a Quiet text button (no fill, no line). With Items it opens Kit.menu when tapped: Items is the
-- list, or a function that returns it then (so what it offers can follow the save); OnPick(id) gets the choice.
function Kit.more(props: Props?): TextButton
	local button = Kit.button({
		Name = "More",
		Kind = "Quiet",
		Text = if props and type(props.Text) == "string" then props.Text else "More",
		TextSize = Theme.TextSize.Body,
		Size = UDim2.fromOffset(88, Theme.Size.ButtonHeight),
	})
	local items = if props then props.Items else nil
	local onPick = if props then props.OnPick else nil
	if items ~= nil then
		button.Activated:Connect(function()
			local list = if type(items) == "function" then items() else items
			if type(list) == "table" then
				Kit.menu(button, list, function(id: string)
					if type(onPick) == "function" then
						onPick(id)
					end
				end)
			end
		end)
	end
	apply(button, props)
	return finish(button, props)
end

-- A HUD door arriving (UI direction R0: a feature appears when it becomes usable, one door at a time). shown = true:
-- the door pops ONCE into its slot (its slot never moves: HudZones) and this returns true if it just appeared
-- (the caller then says what it is on the Now card). Already there: nothing happens. shown = false hides it.
function Kit.reveal(gui: GuiObject, shown: boolean): boolean
	if not shown then
		gui.Visible = false
		return false
	end
	if gui.Visible then
		return false
	end
	Kit.popIn(gui)
	return true
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
			Kit.corner(piece, Theme.Radius.Round) -- a few round ones
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
	return Theme.Colors.Secondary
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
	local width = Theme.Stroke.Bold + 1
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
-- the colours). It is STILL (look overhaul: a list shows up to 60 of these, and Theme.Motion.Perpetual allows one
-- looping effect on screen, the Collect button's): the colours and the bright band stay, nothing moves. Returns
-- stop (removes it).
function Kit.rarityFrame(gui: GuiObject, rarity: string): () -> ()
	local existing = gui:FindFirstChild("RarityFrame")
	if existing then
		existing:Destroy()
	end
	local look = shimmerFor(rarity)
	local stroke = Instance.new("UIStroke") -- uirules: allow StrokeBudget (the rarity frame: rarity's only colour)
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

	return function()
		stroke:Destroy()
	end
end

-- A filling ring (Progression v2: ability cooldowns, build plan §B9). A circle of Theme.Juice.RingBeads beads round
-- the edge of `parent` (its middle stays clear for the icon under it): they light up one by one, clockwise from the
-- top, in `color`, the next one glowing in as it nears; the newest lit bead pops. Full = ready: NOTHING is drawn
-- (UI direction R7 and C4: the beads are there only while the ability recharges, never as decoration). Returns a
-- setter for the fraction (0 = empty, 1 = full: ready; junk = 0). It NEVER prints seconds (red line 3):
-- Kit.Juice.ringFraction turns AbilityReadyAt/AbilityCooldown into the fraction. Reduced motion: no pops.
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
	Kit.corner(holder, Theme.Radius.Round)
	holder.Visible = false -- until the first fraction says it is recharging

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
		Kit.corner(bead, Theme.Radius.Round)
		local edge = Kit.stroke(bead, Theme.Colors.Outline, Theme.Stroke.Fine) -- uirules: allow StrokeBudget (over the world)
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
		holder.Visible = not ready
		if not ready and lit >= 0 and on > lit and not Kit.reducedMotion() then
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
	Kit.corner(fill, Theme.Radius.Medium)
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

-- Idle breathing on a Collect button while its reward waits: a slow, gentle grow and shrink (`amount`, default
-- Theme.Juice.BreathScale), paused while a press, hover or bump owns its scale, and restarting from rest after. Any
-- other role rests (the motion budget: one perpetual effect, on the one Collect button). Returns stop.
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
	end, gui)
	return function()
		job.Stopped = true
		if not isBusy(scale, os.clock()) then
			scale.Scale = 1
		end
	end
end

return Kit
