-- Day and night. At night the lights go down and night customers (who pay more) come in.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Economy = require(script.Parent.Economy)

local DayNight = {}

local function setPhase(isNight: boolean, seconds: number)
	Workspace:SetAttribute("IsNight", isNight)
	Workspace:SetAttribute("PhaseEndsAt", Workspace:GetServerTimeNow() + seconds)
	TweenService:Create(Lighting, TweenInfo.new(4), {
		ClockTime = isNight and 0.5 or 14,
		Brightness = isNight and 1 or 2,
	}):Play()
	if isNight then
		Economy.toastAll("Night shift! Night customers pay " .. Config.NightPayMultiplier .. "x")
	else
		Economy.toastAll("Good morning! The shop is open.")
	end
end

function DayNight.start()
	task.spawn(function()
		while true do
			setPhase(false, Config.DaySeconds)
			task.wait(Config.DaySeconds)
			setPhase(true, Config.NightSeconds)
			task.wait(Config.NightSeconds)
		end
	end)
end

return DayNight
