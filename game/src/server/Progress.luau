--!strict
-- Clinic Stars and "what's next" (build plan §B5, design §5.5). Server only.
--   Progress.addStars(p, n): boolean      adds a whole amount > 0 of Clinic Stars (fractions round down)
--   Progress.nextGoal(p): { Kind, Id, Icon }
--       Kind "Room" | "Upgrade" | "None" (Logic/Progress.nextGoal), plus that room's or upgrade's icon.
--       DayReport uses it for "Next", and it skips the Winter Wing out of season.
-- start(): whenever a player's Stars cross a room's StarsNeeded (however they were earned: cures, goals, the
-- mailbox), the player gets one toast, e.g. "🔓 🛁 Bath Room unlocked!". Seasonal rooms only toast in season,
-- and rooms already owned never do.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Rooms = require(Shared.Data.Rooms)
local Upgrades = require(Shared.Data.Upgrades)
local ProgressLogic = require(Shared.Logic.Progress)
local PlayerData = require(script.Parent.PlayerData)

local Progress = {}

local MAX_STARS = 1e9

local lastStars: { [Player]: number } = {}

local function isWinter(): boolean
	return Workspace:GetAttribute("IsWinter") == true
end

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Progress.addStars(player: Player, amount: number): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not finite(amount) then
		return false
	end
	local whole = math.floor(amount)
	if whole <= 0 then
		return false
	end
	return PlayerData.update(player, function(d)
		d.Stars = math.min(MAX_STARS, d.Stars + whole)
	end)
end

local function iconFor(goal: ProgressLogic.Goal): string
	if goal.Kind == "Room" then
		local room = rawget(Rooms :: any, goal.Id)
		if room then
			return room.Icon
		end
	elseif goal.Kind == "Upgrade" then
		local upgrade = rawget(Upgrades :: any, goal.Id)
		if upgrade then
			return upgrade.Icon
		end
	end
	return ProgressLogic.STAR_ICON
end

function Progress.nextGoal(player: Player): Types.NextGoal
	local goal = ProgressLogic.nextGoal(PlayerData.get(player), Rooms, Upgrades, isWinter())
	return { Kind = goal.Kind, Id = goal.Id, Icon = iconFor(goal) }
end

-- Toasts each room whose stars line was just crossed.
local function onChanged(player: Player, data: Types.Data)
	if player.Parent ~= Players then
		return -- a last update while leaving: don't keep an entry for a player who's gone
	end
	local before = lastStars[player]
	local now = data.Stars
	lastStars[player] = now
	if before == nil or now <= before then
		return
	end
	local winter = isWinter()
	for _, roomId in ProgressLogic.unlockedBetween(Rooms, before, now) do
		local room = Rooms[roomId]
		if not data.Rooms[roomId] and (room.Season == nil or (room.Season == "Winter" and winter)) then
			Remotes.toast(player, "🔓 " .. room.Icon .. " " .. room.Name .. " unlocked!")
		end
	end
end

function Progress.start()
	PlayerData.Loaded:Connect(function(player: Player, data: Types.Data)
		lastStars[player] = data.Stars -- the baseline: loading a save never toasts
	end)
	PlayerData.Changed:Connect(onChanged)
	Players.PlayerRemoving:Connect(function(player)
		lastStars[player] = nil
	end)
end

return Progress
