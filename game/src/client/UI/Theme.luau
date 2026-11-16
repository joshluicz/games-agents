--!strict
-- The look of every screen: palette, fonts, sizes and motion. Change a token here, not per button.
-- "Candy pop" (memory-20261116-007): saturated colours, thick dark outlines, chunky outlined text, glossy buttons.
-- The colours themselves live in Shared/Palette so the world and the UI match. Chunky and readable for phones.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Palette"))

local Candy = Palette.Candy

local Theme = {}

Theme.Colors = table.freeze({
	-- Surfaces
	Paper = Color3.fromRGB(255, 255, 255), -- panels (a white-to-ice gradient is added by Kit.panel)
	PaperEdge = Color3.fromRGB(220, 232, 255), -- the bottom of the panel gradient
	Card = Color3.fromRGB(238, 244, 255), -- rows and cards inside panels
	Shade = Color3.fromRGB(20, 12, 48), -- the dim behind a modal (use with Transparency.Dim)
	-- Text
	Ink = Palette.Ink,
	InkSoft = Palette.InkSoft,
	OnColor = Palette.White, -- text on coloured buttons (always outlined)
	Outline = Palette.Outline,
	-- Roles
	Primary = Candy.Orange, -- main actions
	Secondary = Candy.Blue, -- other actions
	Good = Candy.Lime, -- claim, open, done
	Danger = Candy.Red, -- close, cancel
	Pink = Candy.Pink,
	Purple = Candy.Purple,
	Cyan = Candy.Cyan,
	Quiet = Color3.fromRGB(226, 232, 252), -- tertiary buttons
	Disabled = Color3.fromRGB(176, 176, 198),
	-- Game values
	Cash = Candy.Yellow,
	Star = Color3.fromRGB(255, 226, 40),
	Heart = Candy.Pink,
	Night = Color3.fromRGB(96, 52, 214),
	NightText = Color3.fromRGB(240, 232, 255),
	Stroke = Palette.Outline, -- every outline
	Dot = Color3.fromRGB(255, 40, 70), -- the "something new" badge
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
	Small = 18, -- the minimum for anything a player must read
	Body = 24,
	Title = 34,
	Big = 48, -- numbers that matter (cash, the Day Report count)
	Icon = 40, -- emoji on icon buttons
})

Theme.Size = table.freeze({
	ButtonHeight = 56, -- the minimum tap target height (Global Constraints)
	IconButton = 76, -- square bottom-bar buttons
	Corner = 16,
	CornerLarge = 24,
	Stroke = 3, -- outlines on buttons and chips
	StrokeLarge = 4, -- outlines on panels
	TextStroke = 2.5, -- outlines on text
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
