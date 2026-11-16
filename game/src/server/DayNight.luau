--!strict
-- Day and night: one clinic day is Config.DaySeconds of day then Config.NightSeconds of night (build plan §B5).
-- At night the light goes a deep blue-violet (spooky-cute, never black or scary) and glowing night patients come in
-- (Patients reads Workspace.IsNight). When a night ends, DayReport.flush() sends everyone their Day Report.
-- Server only.
--   Workspace.IsNight: boolean · Workspace.PhaseEndsAt: number (GetServerTimeNow time; the HUD's timer)
--   DayNight.start()   once, from Main.server
--   DayNight.Pure      the two Look tables in plain numbers, and the night-dimmer-than-day rule (tests/Lighting.spec)
--
-- The look lives here in code, so it's versioned: the look overhaul's relight (memory-20261117-001; look build plan
-- §C1 = art-direction §4.3). The candy-pop frames measured over-exposed and milky (mean V 0.95, luma P10 140, a third
-- pale), so: less sky and ambient fill, a grade that adds contrast instead of lifting highlights, a mid-blue
-- atmosphere instead of milk, and Bloom only on Neon.
--   Set once in start() (enums don't tween): Lighting.LightingStyle = Soft and PrioritizeLightingQuality = true (the
--   old ShadowMap path: sun shadows, diffused, without Future's per-light cost), GlobalShadows on, both ColorShifts
--   black. It finds or creates, in Lighting: a ColorCorrectionEffect named CandyColor, the Atmosphere, a Bloom and a
--   SunRaysEffect (CureRays when the place has none), and turns any DepthOfFieldEffect off (it blurs). No Clouds.
--   Tweened on each phase change: every value in Pure.DAY / Pure.NIGHT, together (FADE_SECONDS).
-- Tune by measurement (art-direction Appendix A; look build plan §E P1/P2), in this order: OutdoorAmbient, then
-- Brightness, then EnvironmentDiffuseScale, and the grade last. Night must stay dimmer than day (Pure.nightTooBright;
-- start() warns if a tune breaks it, and the spec fails).
-- Only the day's ClockTime still comes from the place (8 to 16, else 14). The clock always runs forward: day ->
-- sunset -> night, and night -> sunrise -> day, never the sun sliding backwards.
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
local SUN_RAYS_NAME = "CureRays"

-- PURE-BEGIN
-- Plain numbers only (no Roblox types): tests/Lighting.spec loads this block on its own. A colour is { R, G, B } in
-- 0..255; DayNight turns it into a Color3 below. One table per instance; every key is that instance's property.
local Pure = {}

type Rgb = { number }
type PlainLook = {
	Lighting: { [string]: any },
	ColorCorrection: { [string]: any },
	Atmosphere: { [string]: any },
	Bloom: { [string]: any },
	SunRays: { [string]: any },
}

-- Day: a warm sun with real shadows; the sky's own mid-blue in the distance; only Neon blooms.
Pure.DAY = {
	Lighting = {
		Brightness = 2.25,
		ExposureCompensation = 0,
		Ambient = { 70, 68, 84 }, -- the fill where the sky can't see: low, so shadows read
		OutdoorAmbient = { 128, 128, 140 },
		EnvironmentDiffuseScale = 0.6,
		EnvironmentSpecularScale = 0.15,
		ShadowSoftness = 0.15,
	},
	ColorCorrection = { Brightness = 0, Contrast = 0.12, Saturation = 0.08, TintColor = { 255, 251, 244 } },
	Atmosphere = {
		Density = 0.26,
		Offset = 0.15,
		Color = { 150, 198, 240 }, -- mid-blue, not milk
		Decay = { 104, 150, 214 },
		Haze = 0, -- crisp
		Glare = 0,
	},
	Bloom = { Intensity = 0.25, Size = 20, Threshold = 2 }, -- only Neon glows
	SunRays = { Intensity = 0.04, Spread = 0.45 },
} :: PlainLook

-- Night: a deep blue-violet, never black; the lamps, windows and Neon tips carry the frame.
Pure.NIGHT = {
	Lighting = {
		Brightness = 1.0,
		ExposureCompensation = 0,
		Ambient = { 54, 44, 110 },
		OutdoorAmbient = { 82, 68, 150 },
		EnvironmentDiffuseScale = 0.4,
		EnvironmentSpecularScale = 0.15,
		ShadowSoftness = 0.15,
	},
	ColorCorrection = { Brightness = 0, Contrast = 0.15, Saturation = 0.05, TintColor = { 222, 214, 255 } },
	Atmosphere = {
		Density = 0.32,
		Offset = 0.12,
		Color = { 74, 64, 152 },
		Decay = { 40, 32, 104 },
		Haze = 0,
		Glare = 0,
	},
	Bloom = { Intensity = 0.6, Size = 24, Threshold = 1.3 }, -- the lamps and the Neon tips glow
	SunRays = { Intensity = 0, Spread = 0 },
} :: PlainLook

-- Rec. 601 luma of an { R, G, B } colour, 0..255 (what the screenshot stats use).
function Pure.luma(rgb: Rgb): number
	return 0.299 * rgb[1] + 0.587 * rgb[2] + 0.114 * rgb[3]
end

-- The night-dimmer-than-day rule: the names of the fills where `night` is brighter than `day` (empty = the rule
-- holds). Colours compare by luma, so a bluer night ambient is fine as long as it is darker.
function Pure.nightTooBright(day: PlainLook, night: PlainLook): { string }
	local broken = {}
	local dayLight, nightLight = day.Lighting, night.Lighting
	for _, key in { "Brightness", "EnvironmentDiffuseScale" } do
		if nightLight[key] > dayLight[key] then
			table.insert(broken, key)
		end
	end
	for _, key in { "Ambient", "OutdoorAmbient" } do
		if Pure.luma(nightLight[key]) > Pure.luma(dayLight[key]) then
			table.insert(broken, key)
		end
	end
	if night.SunRays.Intensity > day.SunRays.Intensity then
		table.insert(broken, "SunRays.Intensity")
	end
	return broken
end
-- PURE-END

DayNight.Pure = Pure

-- Property tables, one per instance, tweened together on each phase change.
type Props = { [string]: any }
type Look = { Lighting: Props, ColorCorrection: Props, Atmosphere: Props, Bloom: Props, SunRays: Props }

local function toProps(plain: { [string]: any }): Props
	local props: Props = {}
	for key, value in plain do
		props[key] = if type(value) == "table" then Color3.fromRGB(value[1], value[2], value[3]) else value
	end
	return props
end

local function toLook(plain: PlainLook): Look
	return {
		Lighting = toProps(plain.Lighting),
		ColorCorrection = toProps(plain.ColorCorrection),
		Atmosphere = toProps(plain.Atmosphere),
		Bloom = toProps(plain.Bloom),
		SunRays = toProps(plain.SunRays),
	}
end

local DAY_LOOK: Look = toLook(Pure.DAY)
local NIGHT_LOOK: Look = toLook(Pure.NIGHT)

local dayClock = DEFAULT_DAY_CLOCK
local clockToken: {}? = nil
local colorEffect: ColorCorrectionEffect? = nil
local atmosphere: Atmosphere? = nil
local bloom: BloomEffect? = nil
local sunRays: SunRaysEffect? = nil

local function captureDayClock()
	local clock = Lighting.ClockTime
	dayClock = if clock >= 8 and clock <= 16 then clock else DEFAULT_DAY_CLOCK
end

-- Set once (enums and switches don't tween). Each one on its own, so one the engine refuses can't stop the rest.
local function setStyle()
	local style: Props = {
		LightingStyle = Enum.LightingStyle.Soft,
		PrioritizeLightingQuality = true,
		GlobalShadows = true,
		ColorShift_Top = Color3.new(0, 0, 0),
		ColorShift_Bottom = Color3.new(0, 0, 0),
	}
	for key, value in style do
		local ok, err = pcall(function()
			(Lighting :: any)[key] = value
		end)
		if not ok then
			warn("[DayNight] Lighting." .. key .. " not set:", err)
		end
	end
end

-- Finds or creates the post effects (by name for ours, by class for the place's own Atmosphere, Bloom and SunRays),
-- and turns off any depth-of-field blur. Everything that changes between day and night is in the Look tables.
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
	atmosphere = air :: Atmosphere

	local glow = Lighting:FindFirstChildOfClass("BloomEffect")
	if not glow then
		glow = Instance.new("BloomEffect")
		glow.Parent = Lighting
	end
	local glowNow = glow :: BloomEffect
	glowNow.Enabled = true
	bloom = glowNow

	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if not rays then
		local made = Instance.new("SunRaysEffect")
		made.Name = SUN_RAYS_NAME
		made.Parent = Lighting
		rays = made
	end
	local raysNow = rays :: SunRaysEffect
	raysNow.Enabled = true
	sunRays = raysNow

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
	if sunRays then
		targets[sunRays] = look.SunRays
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
	local broken = Pure.nightTooBright(Pure.DAY, Pure.NIGHT)
	if #broken > 0 then
		warn("[DayNight] the night is brighter than the day in: " .. table.concat(broken, ", "))
	end
	guarded("Lighting style", setStyle)
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
