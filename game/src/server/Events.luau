--!strict
-- Seasonal events: the winter switch (build plan §B5, design §5.8). Server only.
--   Events.isWinter(): boolean   true inside Config.Winter (UTC dates, inclusive), or while Workspace.ForceWinter
--   start(): keeps Workspace.IsWinter up to date (Atmosphere snows, Patients sends Frosty variants, the Winter
--            Wing can be bought). Checked every minute, and straight away when ForceWinter or UtcDay changes.
--
-- Testing: workspace:SetAttribute("ForceWinter", true) turns winter on now; nil or false gives the dates back.
-- Starts before Plots and Daily, so it reads the day itself (the real UTC day, or a forward-set Workspace.UtcDay)
-- instead of requiring the server Daily module.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local DailyLogic = require(Shared.Logic.Daily)

local Events = {}

local CHECK_SECONDS = 60

local started = false

local function today(): number
	local real = DailyLogic.day(os.time())
	local attribute = Workspace:GetAttribute("UtcDay") -- a forward-set day counts in Studio only (testing)
	if
		RunService:IsStudio()
		and type(attribute) == "number"
		and attribute % 1 == 0
		and attribute > real
		and attribute < math.huge
	then
		return attribute
	end
	return real
end

function Events.isWinter(): boolean
	if Workspace:GetAttribute("ForceWinter") == true then
		return true
	end
	return DailyLogic.inWindow(today(), Config.Winter)
end

local function refresh()
	local winter = Events.isWinter()
	if Workspace:GetAttribute("IsWinter") == winter then
		return
	end
	Workspace:SetAttribute("IsWinter", winter)
	if started then
		Remotes.toastAll(if winter then "❄️ Winter is here!" else "👋 Bye bye, winter!")
	end
end

function Events.start()
	if DailyLogic.dateDay(Config.Winter.Start) == nil or DailyLogic.dateDay(Config.Winter.End) == nil then
		warn("[Events] Config.Winter dates must be YYYY-MM-DD; winter only comes with ForceWinter")
	end
	refresh()
	started = true
	Workspace:GetAttributeChangedSignal("ForceWinter"):Connect(refresh)
	Workspace:GetAttributeChangedSignal("UtcDay"):Connect(refresh)
	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			local ok, err = pcall(refresh)
			if not ok then
				warn("[Events] Winter check failed:", err)
			end
		end
	end)
end

return Events
