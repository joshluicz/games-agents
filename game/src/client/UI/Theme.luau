--!strict
-- The look of every screen: palette, fonts, sizes and motion. Change a token here, not per button.
-- The look overhaul's tokens (look build plan §B3; docs/research/2026-11-16-ux-cohesion-audit.md §3.4, with Joshua's
-- navy header, memory-20261117-001): flat white paper, ONE navy header, calmer roles, text never under 18 px, three
-- radii, one shadow and a motion budget. The colours themselves live in Shared/Palette so the world and the UI match.
-- Every key the candy-pop Theme had is still here (an alias where its token was renamed), so files the overhaul
-- hasn't reached keep compiling.
--
--   Theme.Colors      chrome (Paper, Card, CardLine, Well, Locked, Header = NowPlate = Palette.Navy, Plate, Ink,
--                     InkSoft, Stroke) · roles (Primary, Collect, Secondary, Destructive, Disabled, each gradient
--                     role with its ...End; aliases Good = Collect, Danger = Destructive) · meaning (Cash, Star,
--                     Night, and Pink / Purple / Cyan for rarity, wing and station stripes only)
--   Theme.Radius      Small 8 · Medium 14 · Large 22 (px) · Round (a UDim: 0.5 scale)
--   Theme.Stroke      Fine 2 · Bold 3 · Panel 4 · Text 2.5 · Title 3
--   Theme.TextSize    Caption 18 (THE FLOOR: nothing a player reads is smaller) · Body 22 · Button 24 · Title 30 ·
--                     Number 36 · Hero 56 · Icon 40 (aliases Small = Caption, Big = 48)
--   Theme.Space       Step { 4, 8, 12, 16, 24, 32 } · Gap 8 · PadCard 12 · PadPanel 16 · Margin 16 / MarginPhone 8
--   Theme.Shadow      the one shadow: only under modals, the Now card and toasts
--   Theme.Motion      Perpetual = 1: at most one looping effect on screen, on the one Collect button
--   Theme.Zone        the HUD zone numbers (mirrors Shared/Logic/HudZones)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Palette = require(Shared:WaitForChild("Palette"))
local HudZones = require(Shared:WaitForChild("Logic"):WaitForChild("HudZones"))

local Candy = Palette.Candy
local hex = Color3.fromHex

local Theme = {}

local PAPER = hex("#FFFFFF")
local COLLECT = hex("#45CF3A")
local DESTRUCTIVE = hex("#FF4459")
local QUIET = hex("#DFE6F2")

Theme.Colors = table.freeze({
	-- Chrome
	Paper = PAPER, -- panels: flat white
	PaperEdge = PAPER, -- (old key) the panel gradient's bottom: the same white now, so there is no gradient
	Card = hex("#EEF3FA"), -- rows and cards inside panels ...
	CardLine = hex("#C3D0E6"), -- ... and their 2 px stroke
	Well = hex("#D6E3F5"), -- a card's image tile; every row's icon tile (neutral)
	Locked = hex("#6A5FA0"), -- "???" silhouettes
	Header = Palette.Navy, -- EVERY panel header (no per-panel colour)
	NowPlate = Palette.Navy, -- the top-centre Now card
	Plate = hex("#FFFFFF"), -- HUD plates (rail buttons, toasts)
	Shade = Color3.fromRGB(20, 12, 48), -- the dim behind a modal (use with Transparency.Dim)
	-- Text
	Ink = Palette.Ink,
	InkSoft = Palette.InkSoft,
	OnColor = Palette.White, -- text on coloured buttons (always outlined)
	Outline = Palette.Outline,
	Stroke = Palette.Outline, -- every outline
	-- Roles (ux audit §3.3). A role with an ...End is a top-to-bottom gradient
	Primary = hex("#FF9A1F"), -- Buy, Hire, Level up, List: one per view. Never shines or breathes
	PrimaryEnd = hex("#F27A0C"),
	Collect = COLLECT, -- Claim, Open!, Yay!: the only role that may shine or breathe
	CollectEnd = hex("#2BA52A"),
	Secondary = QUIET, -- everything else: a quiet fill with ink text
	Destructive = DESTRUCTIVE, -- Sell, Reset, Throw away (always behind a confirm or a hold), and the ✖
	DestructiveEnd = hex("#D9283F"),
	Disabled = hex("#B3B6C9"),
	DisabledText = hex("#6E7190"),
	Dot = Color3.fromRGB(255, 40, 70), -- the "something new" badge
	-- Old role keys (aliases)
	Good = COLLECT,
	Danger = DESTRUCTIVE,
	Quiet = QUIET,
	-- Meaning
	Cash = hex("#FFD43B"),
	Star = hex("#FFE228"),
	Heart = Candy.Pink,
	Night = hex("#5B3BD6"),
	NightText = Color3.fromRGB(240, 232, 255),
	Pink = Candy.Pink, -- rarity, wing and station stripes only
	Purple = Candy.Purple,
	Cyan = Candy.Cyan,
})

Theme.Transparency = table.freeze({
	Dim = 0.4,
	Panel = 0,
	Soft = 0.1,
})

-- Body text: FredokaOne, round and readable. Display (titles, buttons, numbers): LuckiestGuy, chunky and loud.
Theme.Font = Palette.BodyFont
Theme.FontFace = Font.fromEnum(Palette.BodyFont)
Theme.DisplayFont = Palette.DisplayFont
Theme.DisplayFontFace = Font.fromEnum(Palette.DisplayFont)

Theme.TextSize = table.freeze({
	Caption = 18, -- THE FLOOR: every UITextSizeConstraint's MinTextSize (Kit.textLimit)
	Body = 22,
	Button = 24,
	Title = 30,
	Number = 36, -- HUD numbers
	Hero = 56, -- Celebrate, the Day Report's count
	Icon = 40, -- emoji on icon buttons
	-- Old keys (aliases, for files the overhaul hasn't reached)
	Small = 18,
	Big = 48,
})

Theme.Radius = table.freeze({
	Small = 8, -- chips, bars, small tiles
	Medium = 14, -- buttons, cards, tabs
	Large = 22, -- panels, the Now card, toasts
	Round = UDim.new(0.5, 0), -- dots, portraits (a UDim, not px)
})

Theme.Stroke = table.freeze({
	Fine = 2, -- cards (in CardLine), tiles, chips
	Bold = 3, -- buttons, HUD plates
	Panel = 4, -- panels
	Text = 2.5, -- labels on colour
	Title = 3, -- HUD numbers, titles
})

Theme.Space = table.freeze({
	Step = table.freeze({ 4, 8, 12, 16, 24, 32 }), -- the only spacings
	Gap = 8, -- lists
	PadCard = 12,
	PadPanel = 16,
	Margin = 16, -- from the safe-area edge (desktop and tablet)
	MarginPhone = 8,
})

-- The one shadow: only under modals, the Now card and toasts. None on the HUD (the outline does that job).
Theme.Shadow = table.freeze({
	Color = Palette.Outline,
	Transparency = 0.6,
	Offset = Vector2.new(0, 6),
})

-- The motion budget: at most this many looping effects on screen at once, on the one Collect button. Dots pop once.
Theme.Motion = table.freeze({
	Perpetual = 1,
})

-- The HUD zone numbers (Shared/Logic/HudZones owns them; UI/Hud lays out from HudZones.layout).
Theme.Zone = table.freeze({
	PhoneBreak = HudZones.PHONE_BREAK,
	RailButton = HudZones.RAIL_BUTTON,
	RailButtonMin = HudZones.RAIL_BUTTON_MIN,
	RailGap = HudZones.RAIL_GAP,
	RailGapPhone = HudZones.RAIL_GAP_PHONE,
	CornerClear = HudZones.CORNER_CLEAR,
	Topbar = HudZones.TOPBAR,
	WalletHeight = HudZones.WALLET_HEIGHT,
	NowHeight = HudZones.NOW_HEIGHT,
	NowHeightShort = HudZones.NOW_HEIGHT_SHORT,
	NowTab = HudZones.NOW_TAB,
	NowSlim = HudZones.NOW_SLIM,
	NowMax = HudZones.NOW_MAX,
	StatusWidth = HudZones.STATUS_WIDTH,
})

-- Old sizes (kept so untouched layouts don't shift; new code uses Radius, Stroke and Space).
Theme.Size = table.freeze({
	ButtonHeight = 56, -- the minimum tap target height (Global Constraints)
	IconButton = 76, -- square icon buttons (the rails use Theme.Zone.RailButton)
	Corner = 14, -- = Radius.Medium
	CornerLarge = 22, -- = Radius.Large
	Stroke = 3, -- = Stroke.Bold
	StrokeLarge = 4, -- = Stroke.Panel
	TextStroke = 2.5, -- = Stroke.Text
	Pad = 12,
	Gap = 10,
	Margin = 12, -- from the safe-area edge
	PanelMaxWidth = 560,
	PanelMaxHeight = 640,
	Dot = 20,
})

-- Short and interruptible. Panels pop with a little overshoot; presses squash quickly and spring back.
Theme.Tween = table.freeze({
	Press = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Release = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Hover = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	PopIn = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	PopOut = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	Fade = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Bump = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Shine = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
	Slide = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), -- toasts and panels slide in
	SlideOut = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	Fill = TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), -- progress bars filling up
})
Theme.PressScale = 0.9
Theme.HoverScale = 1.05 -- a mouse over a Kit button (computers only; touch never hovers)
Theme.PopFrom = 0.75 -- Kit.popIn grows from this scale
Theme.ShineEvery = 3.5 -- seconds between shine sweeps on call-to-action buttons
Theme.RaysSpin = 18 -- seconds per turn of the reward rays

-- Depth update juice (design §4). Every one of these stops with reduced motion (Kit.reducedMotion()).
Theme.Juice = table.freeze({
	BreathScale = 0.045, -- idle "breathing" on a call to action: grows this much at the top of a breath
	BreathSeconds = 1.6, -- one breath, in and out
	DotHopEvery = 2.6, -- a red "something new" dot hops this often
	ShimmerSeconds = 2.2, -- one sweep of a rarity frame's shimmer (Legendary and up turn faster)
	CountSeconds = 0.6, -- Kit.countUp's default roll (Kit.Juice.countSeconds stretches it for big jumps)
	ConfettiPieces = 28, -- one Kit.confetti burst
	ConfettiSeconds = 1.8, -- how long a piece takes to fall
	CelebrateSeconds = 7, -- a celebration screen closes itself after this (tap to close sooner)
	FlySeconds = 0.55, -- a flying coin's trip to the wallet, after its burst
	-- Progression v2
	RingBeads = 12, -- beads round an ability's cooldown ring (Kit.ring): they light up as it fills, no numbers
})

-- The candy confetti set (UI and world).
Theme.Confetti = table.freeze({
	Palette.Candy.Pink,
	Palette.Candy.Yellow,
	Palette.Candy.Cyan,
	Palette.Candy.Lime,
	Palette.Candy.Purple,
	Palette.Candy.Orange,
})

-- ScreenGui.DisplayOrder: higher draws on top.
Theme.DisplayOrder = table.freeze({
	World = 0, -- world-ish overlays (Guide)
	Hud = 10,
	Panel = 20, -- Shop, Book, Goals
	Popup = 30, -- Mailbox letter, Day Report
	Fx = 40, -- cure pops, NEW PAGE banner, flying coins
	Celebrate = 45, -- level-up, new nurse, set complete, new room (UI/Celebrate)
	Toast = 50,
})

return table.freeze(Theme)
