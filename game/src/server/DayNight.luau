--!strict
-- Day and night: one clinic day is Config.DaySeconds of day then Config.NightSeconds of night (build plan §B5).
-- At night the light goes soft purple-blue (spooky-cute, never dark or scary) and glowing night patients come in
-- (Patients reads Workspace.IsNight). When a night ends, DayReport.flush() sends everyone their Day Report.
-- Server only.
--   Workspace.IsNight: boolean · Workspace.PhaseEndsAt: number (GetServerTimeNow time; the HUD's timer)
--
-- The day look is whatever Lighting the place has when the server starts (the brother's lighting wins); night
-- tweens away from it and morning tweens back. The clock always runs forward: day -> sunset -> night, and
-- night -> sunrise -> day, never the sun sliding backwards.
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

local NIGHT_LOOK = {
	Brightness = 1.2,
	Ambient = Color3.fromRGB(92, 84, 150),
	OutdoorAmbient = Color3.fromRGB(112, 102, 172),
}

type Look = { Brightness: number, Ambient: Color3, OutdoorAmbient: Color3 }

local dayLook: Look = {
	Brightness = 2,
	Ambient = Color3.fromRGB(70, 70, 70),
	OutdoorAmbient = Color3.fromRGB(128, 128, 128),
}
local dayClock = DEFAULT_DAY_CLOCK
local clockToken: {}? = nil

local function captureDayLook()
	dayLook = {
		-- Never let night be brighter than day, whatever the place was saved with.
		Brightness = math.max(Lighting.Brightness, NIGHT_LOOK.Brightness + 0.6),
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
	}
	local clock = Lighting.ClockTime
	dayClock = if clock >= 8 and clock <= 16 then clock else DEFAULT_DAY_CLOCK
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

	local look = if isNight then NIGHT_LOOK else dayLook
	TweenService:Create(Lighting, TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Sine), {
		Brightness = look.Brightness,
		Ambient = look.Ambient,
		OutdoorAmbient = look.OutdoorAmbient,
	}):Play()
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
	captureDayLook()
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
