--!strict
-- Sends each player a Snapshot of their own state (build plan §B4/§B5). Server only.
--   State.push(p)          debounced 0.2 s: builds the Snapshot and fires the State remote to that player
--   State.snapshot(p)      the Snapshot now (a copy; defaults if the player's data isn't loaded)
--   wires GetState         answers with the Snapshot, after waiting for the data to load (nil when rate-limited)
-- It pushes on its own when: the player's data changes (PlayerData.Changed), their PlotIndex or TutorialCures
-- attribute changes, or the Workspace's UtcDay, TodaysVisitor or IsWinter changes. Other modules only call push()
-- for state that lives outside the save.
-- Tutorial is the saved step (Data.Tutorial); TutorialCures is Server/Tutorial's step-6 count, kept on the player
-- as an attribute (it isn't saved: a rejoin in step 6 counts 2 more from 0).
-- Time played, boosts and badges: Playtime, Stats and Badges are the saved fields; Boosts is Server/Boosts.list (timed
-- boosts running, permanent percents) and MakeSeconds the hold time at each station with every boost (the client's
-- ring follows it, Guide). The live play seconds are the player attributes PlayToday/PlayTotal (Server/Playtime).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Remotes)
local Schema = require(Shared.Logic.Schema)
local DailyLogic = require(Shared.Logic.Daily)
local Types = require(Shared.Types)
local StationsData = require(Shared.Data.Stations)
local PlayerData = require(script.Parent.PlayerData)
local Daily = require(script.Parent.Daily)
local Boosts = require(script.Parent.Boosts)

local State = {}

local DEBOUNCE_SECONDS = 0.2

local pending: { [Player]: boolean } = {}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[key] = deepCopy(item)
	end
	return copy
end

local function today(): number
	local day = Workspace:GetAttribute("UtcDay")
	if type(day) == "number" then
		return day
	end
	return DailyLogic.day(os.time())
end

-- Whether today's visitor can still come to this player's clinic (the HUD hides the chip for "None").
local function visitorStatus(player: Player): Types.VisitorStatus
	local ok, status = pcall(Daily.visitorStatus, player)
	return if ok and (status == "Coming" or status == "Done") then status else "None"
end

local function boostList(player: Player): Types.BoostList
	local ok, list = pcall(Boosts.list, player)
	return if ok and type(list) == "table" then list else { Timed = {}, Permanent = {} }
end

local function makeSeconds(player: Player): { [string]: number }
	local out: { [string]: number } = {}
	for _, stationId in StationsData.Order do
		local ok, seconds = pcall(Boosts.makeSeconds, player, stationId)
		if ok and type(seconds) == "number" then
			out[stationId] = seconds
		end
	end
	return out
end

function State.snapshot(player: Player): Types.Snapshot
	local data = PlayerData.get(player) or Schema.default()
	local plotIndex = player:GetAttribute("PlotIndex")
	local visitor = Workspace:GetAttribute("TodaysVisitor")
	local tutorialCures = player:GetAttribute("TutorialCures")
	return {
		Upgrades = deepCopy(data.Upgrades),
		Rooms = deepCopy(data.Rooms),
		Decor = deepCopy(data.Decor),
		Book = deepCopy(data.Book),
		Story = deepCopy(data.Story),
		Daily = deepCopy(data.Daily),
		Cash = data.Cash,
		Stars = data.Stars,
		Cured = data.Cured,
		MailboxReady = DailyLogic.mailboxReady(data.Mailbox.LastSeenDay, today()),
		PlotIndex = if type(plotIndex) == "number" then plotIndex else nil,
		TodaysVisitor = if type(visitor) == "string" then visitor else "",
		VisitorStatus = visitorStatus(player),
		IsWinter = Workspace:GetAttribute("IsWinter") == true,
		Tutorial = data.Tutorial,
		TutorialCures = if type(tutorialCures) == "number" then tutorialCures else 0,
		Playtime = deepCopy(data.Playtime),
		Boosts = boostList(player),
		MakeSeconds = makeSeconds(player),
		Stats = deepCopy(data.Stats),
		Badges = deepCopy(data.Badges),
	}
end

function State.push(player: Player)
	if pending[player] then
		return
	end
	pending[player] = true
	task.delay(DEBOUNCE_SECONDS, function()
		pending[player] = nil
		if player.Parent == Players and PlayerData.get(player) then
			Remotes.State:FireClient(player, State.snapshot(player))
		end
	end)
end

local function pushAll()
	for _, player in Players:GetPlayers() do
		State.push(player)
	end
end

function State.start()
	PlayerData.Changed:Connect(function(player: Player)
		State.push(player)
	end)

	local function watch(player: Player)
		for _, attribute in { "PlotIndex", "TutorialCures" } do
			player:GetAttributeChangedSignal(attribute):Connect(function()
				State.push(player)
			end)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
	end)

	for _, attribute in { "UtcDay", "TodaysVisitor", "IsWinter" } do
		Workspace:GetAttributeChangedSignal(attribute):Connect(pushAll)
	end

	Remotes.GetState.OnServerInvoke = function(player: Player)
		if not Remotes.allow(player, "GetState") then
			return nil
		end
		PlayerData.waitLoaded(player) -- however long the load takes; nil if the player leaves first
		return State.snapshot(player)
	end
end

return State
