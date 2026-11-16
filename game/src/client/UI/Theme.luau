--!strict
-- The look of every screen: palette, fonts, sizes and motion (build plan Task 0). Change a token here, not
-- per button. Cozy and bright, not oversaturated (design §6); chunky and readable for phones (Global Constraints).

local Theme = {}

Theme.Colors = table.freeze({
	-- Surfaces
	Paper = Color3.fromRGB(255, 250, 240), -- panels
	Card = Color3.fromRGB(255, 255, 255), -- rows and cards inside panels
	Shade = Color3.fromRGB(46, 30, 24), -- the dim behind a modal (use with Transparency.Dim)
	-- Text
	Ink = Color3.fromRGB(74, 52, 42),
	InkSoft = Color3.fromRGB(140, 112, 96),
	OnColor = Color3.fromRGB(255, 255, 255), -- text on coloured buttons
	-- Roles
	Primary = Color3.fromRGB(255, 132, 102), -- main actions (coral)
	Secondary = Color3.fromRGB(98, 170, 255), -- other actions (sky)
	Good = Color3.fromRGB(86, 196, 140), -- claim, done (mint)
	Danger = Color3.fromRGB(236, 98, 120), -- close, cancel (berry)
	Quiet = Color3.fromRGB(236, 226, 212), -- tertiary buttons
	Disabled = Color3.fromRGB(206, 198, 190),
	-- Game values
	Cash = Color3.fromRGB(255, 196, 64),
	Star = Color3.fromRGB(255, 214, 64),
	Heart = Color3.fromRGB(255, 111, 145),
	Night = Color3.fromRGB(62, 46, 110),
	NightText = Color3.fromRGB(236, 228, 255),
	Stroke = Color3.fromRGB(120, 86, 66), -- outlines on paper
	Dot = Color3.fromRGB(255, 72, 88), -- the "something new" badge
})

Theme.Transparency = table.freeze({
	Dim = 0.45,
	Panel = 0,
	Soft = 0.1,
})

-- FredokaOne: round and friendly, readable at small sizes.
Theme.Font = Enum.Font.FredokaOne
Theme.FontFace = Font.fromEnum(Enum.Font.FredokaOne)

Theme.TextSize = table.freeze({
	Small = 18, -- the minimum for anything a player must read
	Body = 24,
	Title = 32,
	Big = 48, -- numbers that matter (cash, the Day Report count)
	Icon = 40, -- emoji on icon buttons
})

Theme.Size = table.freeze({
	ButtonHeight = 56, -- the minimum tap target height (Global Constraints)
	IconButton = 76, -- square bottom-bar buttons
	Corner = 14,
	CornerLarge = 22,
	Stroke = 3,
	Pad = 12,
	Gap = 10,
	Margin = 12, -- from the safe-area edge
	PanelMaxWidth = 560,
	PanelMaxHeight = 640,
	Dot = 18,
})

-- Short and interruptible. Panels pop with a little overshoot; presses squash quickly and spring back.
Theme.Tween = table.freeze({
	Press = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Release = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	PopIn = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	PopOut = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	Fade = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
})
Theme.PressScale = 0.92

-- ScreenGui.DisplayOrder: higher draws on top.
Theme.DisplayOrder = table.freeze({
	World = 0, -- world-ish overlays (Guide)
	Hud = 10,
	Panel = 20, -- Shop, Book, Goals
	Popup = 30, -- Mailbox letter, Day Report
	Fx = 40, -- cure pops, NEW PAGE banner
	Toast = 50,
})

return table.freeze(Theme)
