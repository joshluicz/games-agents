--!strict
-- The Day Report: what you did this clinic day, shown when the night ends (build plan §B5, design §5.4).
-- Server only.
--   DayReport.record(p, ctx, newPage, stars)   adds one cure to p's report. Cure calls it for the helper (with
--                                              their new page) and again for the owner when that's someone else
--                                              (with the stars their clinic earned). Each call counts for p only.
--   DayReport.flush()                          DayNight calls it when the night ends: sends every player their
--                                              DayReport { Cured, NewPages, StarsGained, Next } and starts a new day
--
-- A player who joined moments ago and hasn't cured anything yet gets no report (an empty pop-up 10 seconds after
-- joining is noise), and neither does a player in the first-session tutorial (it stays quiet: their counter is
-- cleared with everyone's). Everyone else gets one, even on a quiet day: it still points at the next goal.
-- Counters live in memory only: they're a summary of this session's clinic day, not progress.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local TutorialLogic = require(Shared.Logic.Tutorial)
local PlayerData = require(script.Parent.PlayerData)
local Progress = require(script.Parent.Progress)

local DayReport = {}

local QUIET_NEWCOMER_SECONDS = 120 -- joined this recently and cured nothing: skip the report
local MAX_PAGES = 30 -- a bound on the payload; there are far fewer patients than this

type Counter = {
	Cured: number,
	NewPages: { string },
	Seen: { [string]: boolean },
	StarsGained: number,
}

local counters: { [Player]: Counter } = {}
local joinedAt: { [Player]: number } = {}

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function isCount(value: any): boolean
	return type(value) == "number" and value == value and value > 0 and value < math.huge
end

local function counterFor(player: Player): Counter
	local counter = counters[player]
	if not counter then
		counter = { Cured = 0, NewPages = {}, Seen = {}, StarsGained = 0 }
		counters[player] = counter
	end
	return counter
end

local function nextGoal(player: Player): Types.NextGoal
	local ok, goal = pcall(Progress.nextGoal, player)
	if
		ok
		and type(goal) == "table"
		and type(goal.Kind) == "string"
		and type(goal.Id) == "string"
		and type(goal.Icon) == "string"
	then
		return { Kind = goal.Kind, Id = goal.Id, Icon = goal.Icon }
	end
	return { Kind = "None", Id = "", Icon = "⭐" }
end

function DayReport.record(player: Player, ctx: Types.CureCtx, newPage: boolean, stars: number)
	if not isPlayer(player) or player.Parent ~= Players then
		return
	end
	local counter = counterFor(player)
	counter.Cured += 1
	local patientId = if type(ctx) == "table" then ctx.PatientId else nil
	if newPage == true and type(patientId) == "string" and not counter.Seen[patientId] then
		counter.Seen[patientId] = true
		if #counter.NewPages < MAX_PAGES then
			table.insert(counter.NewPages, patientId)
		end
	end
	if isCount(stars) then
		counter.StarsGained += math.floor(stars)
	end
end

function DayReport.flush()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local counter = counters[player]
		local cured = if counter then counter.Cured else 0
		local newcomer = now - (joinedAt[player] or 0) < QUIET_NEWCOMER_SECONDS
		local data = PlayerData.get(player)
		if data and not TutorialLogic.active(data.Tutorial) and (cured > 0 or not newcomer) then
			local report: Types.DayReportInfo = {
				Cured = cured,
				NewPages = if counter then table.clone(counter.NewPages) else {},
				StarsGained = if counter then counter.StarsGained else 0,
				Next = nextGoal(player),
			}
			Remotes.DayReport:FireClient(player, report)
		end
	end
	table.clear(counters)
end

function DayReport.start()
	local function onJoin(player: Player)
		joinedAt[player] = os.clock()
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		if not joinedAt[player] then
			onJoin(player)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		counters[player] = nil
		joinedAt[player] = nil
	end)
end

return DayReport
