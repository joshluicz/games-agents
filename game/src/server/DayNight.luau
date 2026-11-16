--!strict
-- Day and night: one clinic day is Config.DaySeconds of day then Config.NightSeconds of night (build plan §B5).
-- At night the light goes a rich blue-purple (spooky-cute, never dark or scary) and glowing night patients come in
-- (Patients reads Workspace.IsNight). When a night ends, DayReport.flush() sends everyone their Day Report.
-- Server only.
--   Workspace.IsNight: boolean · Workspace.PhaseEndsAt: number (GetServerTimeNow time; the HUD's timer)
--
-- The look lives here in code, so it's versioned ("candy pop", memory-20261116-007): a bright, saturated day and a
-- saturated blue-purple night. start() finds or creates, in Lighting, a ColorCorrectionEffect named CandyColor
-- (more saturation and a little contrast), the Atmosphere (thin and sky-blue, not grey haze) and a subtle Bloom, and
-- turns any DepthOfFieldEffect off (it blurs). Each phase change tweens Lighting and those effects together. Only
-- the day's ClockTime still comes from the place (8 to 16, else 14). The clock always runs forward: day -> sunset ->
-- night, and night -> sunrise -> day, never the sun sliding backwards.
--
-- Testing: workspace:SetAttribute("SkipPhase", true) ends the current phase now (twice = a whole clinic day).

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local DayReport = require(script.Parent.DayReport)

local DayNight = {}

local FADE_SECONDS = 6
local NIGHT_CLOCK = 0.5 -- just after midnight: moon up
local DEFAULT_DAY_CLOCK = 14
local POLL_SECONDS = 0.25
local COLOR_EFFECT_NAME = "CandyColor"

-- Property tables, one per instance, tweened together on each phase change.
type Props = { [string]: any }
type Look = { Lighting: Props, ColorCorrection: Props, Atmosphere: Props, Bloom: Props }

local DAY_LOOK: Look = {
	Lighting = {
		Brightness = 2.6,
		Ambient = Color3.fromRGB(124, 120, 146), -- bright, slightly lilac shadows: toy-like, never muddy
		OutdoorAmbient = Color3.fromRGB(166, 160, 186),
	},
	ColorCorrection = {
		Saturation = 0.2,
		Contrast = 0.08,
		Brightness = 0.02,
		TintColor = Color3.fromRGB(255, 255, 255),
	},
	Atmosphere = {
		Density = 0.24,
		Color = Color3.fromRGB(198, 230, 255),
		Decay = Color3.fromRGB(120, 178, 255),
	},
	Bloom = { Intensity = 0.3, Threshold = 2 },
}

-- Night is never brighter than day, and never dark: a saturated blue-purple with a lilac tint.
local NIGHT_LOOK: Look = {
	Lighting = {
		Brightness = 1.2,
		Ambient = Color3.fromRGB(100, 74, 196),
		OutdoorAmbient = Color3.fromRGB(124, 94, 228),
	},
	ColorCorrection = {
		Saturation = 0.28,
		Contrast = 0.1,
		Brightness = 0.03,
		TintColor = Color3.fromRGB(226, 214, 255),
	},
	Atmosphere = {
		Density = 0.3,
		Color = Color3.fromRGB(128, 104, 222),
		Decay = Color3.fromRGB(76, 54, 172),
	},
	Bloom = { Intensity = 0.55, Threshold = 1.6 }, -- the night lamps (Neon) glow a little more
}

local dayClock = DEFAULT_DAY_CLOCK
local clockToken: {}? = nil
local colorEffect: ColorCorrectionEffect? = nil
local atmosphere: Atmosphere? = nil
local bloom: BloomEffect? = nil

local function captureDayClock()
	local clock = Lighting.ClockTime
	dayClock = if clock >= 8 and clock <= 16 then clock else DEFAULT_DAY_CLOCK
end

-- Finds or creates the post effects (by name for ours, by class for the place's own Atmosphere and Bloom), sets the
-- settings that never change, and turns off any depth-of-field blur.
local function setupEffects()
	local existing = Lighting:FindFirstChild(COLOR_EFFECT_NAME)
	local color: ColorCorrectionEffect
	if existing and existing:IsA("ColorCorrectionEffect") then
		color = existing
	else
		color = Instance.new("ColorCorrectionEffect")
		color.Name = COLOR_EFFECT_NAME
		color.Parent = Lighting
	end
	color.Enabled = true
	colorEffect = color

	local air = Lighting:FindFirstChildOfClass("Atmosphere")
	if not air then
		air = Instance.new("Atmosphere")
		air.Parent = Lighting
	end
	local airNow = air :: Atmosphere
	airNow.Offset = 0.2 -- the horizon stays clear
	airNow.Glare = 0
	airNow.Haze = 0
	atmosphere = airNow

	local glow = Lighting:FindFirstChildOfClass("BloomEffect")
	if not glow then
		glow = Instance.new("BloomEffect")
		glow.Parent = Lighting
	end
	local glowNow = glow :: BloomEffect
	glowNow.Size = 24
	glowNow.Enabled = true
	bloom = glowNow

	for _, child in Lighting:GetChildren() do
		if child:IsA("DepthOfFieldEffect") then
			child.Enabled = false
		end
	end
end

local function setProps(instance: Instance, props: Props)
	for key, value in props do
		(instance :: any)[key] = value
	end
end

-- Puts a look on Lighting and the effects: at once (seconds = nil) or tweened over `seconds`.
local function applyLook(look: Look, seconds: number?)
	local targets: { [Instance]: Props } = { [Lighting] = look.Lighting }
	if colorEffect then
		targets[colorEffect] = look.ColorCorrection
	end
	if atmosphere then
		targets[atmosphere] = look.Atmosphere
	end
	if bloom then
		targets[bloom] = look.Bloom
	end
	for instance, props in targets do
		if seconds then
			TweenService:Create(instance, TweenInfo.new(seconds, Enum.EasingStyle.Sine), props):Play()
		else
			setProps(instance, props)
		end
	end
end

-- Moves Lighting.ClockTime forward from `from` to `to` (to may pass 24) over `seconds`, eased.
local function sweepClock(from: number, to: number, seconds: number)
	local token = {}
	clockToken = token
	task.spawn(function()
		local started = os.clock()
		while clockToken == token do
			local alpha = math.min(1, (os.clock() - started) / seconds)
			local eased = TweenService:GetValue(alpha, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			Lighting.ClockTime = (from + (to - from) * eased) % 24
			if alpha >= 1 then
				break
			end
			task.wait()
		end
	end)
end

local function setPhase(isNight: boolean, seconds: number)
	Workspace:SetAttribute("IsNight", isNight)
	Workspace:SetAttribute("PhaseEndsAt", Workspace:GetServerTimeNow() + seconds)

	applyLook(if isNight then NIGHT_LOOK else DAY_LOOK, FADE_SECONDS)
	if isNight then
		sweepClock(dayClock, 24 + NIGHT_CLOCK, FADE_SECONDS) -- sunset
		Remotes.toastAll("🌙 Night shift! Night patients pay " .. Config.NightPayMultiplier .. "x")
	else
		sweepClock(NIGHT_CLOCK, dayClock, FADE_SECONDS) -- sunrise
		Remotes.toastAll("☀️ Good morning! The clinic is open.")
	end
end

-- Waits out a phase, or less if someone sets Workspace.SkipPhase (testing).
local function waitPhase(seconds: number)
	local endsAt = os.clock() + seconds
	while os.clock() < endsAt do
		if Workspace:GetAttribute("SkipPhase") == true then
			Workspace:SetAttribute("SkipPhase", nil)
			return
		end
		task.wait(POLL_SECONDS)
	end
end

local function guarded(what: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn("[DayNight] " .. what .. " failed:", err)
	end
end

function DayNight.start()
	captureDayClock()
	guarded("Lighting setup", function()
		setupEffects()
		applyLook(DAY_LOOK)
	end)
	Lighting.ClockTime = dayClock
	task.spawn(function()
		while true do
			guarded("Morning", function()
				setPhase(false, Config.DaySeconds)
			end)
			waitPhase(Config.DaySeconds)
			guarded("Nightfall", function()
				setPhase(true, Config.NightSeconds)
			end)
			waitPhase(Config.NightSeconds)
			guarded("DayReport.flush", DayReport.flush)
		end
	end)
end

return DayNight
