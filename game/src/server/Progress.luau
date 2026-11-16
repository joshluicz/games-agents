--!strict
-- Clinic Stars and "what's next" (build plan §B5, design §5.5). Server only.
--   Progress.addStars(p, n): boolean      adds a whole amount > 0 of Clinic Stars (fractions round down)
--   Progress.nextGoal(p): { Kind, Id, Icon }
--       Kind "Room" | "Upgrade" | "None" (Logic/Progress.nextGoal), plus that room's or upgrade's icon.
--       DayReport uses it for "Next", and it skips the Winter Wing out of season.
-- start(): whenever a player's Stars cross a room's StarsNeeded (however they were earned: cures, goals, the
-- mailbox), the player gets one toast that says what to do next: "🔓 🛁 Bath Room! Buy in 🛒" when the cash is
-- there too, else "⭐ 🛁 Bath Room! Save 💰150". Then, once per session, the moment the cash for a room whose
-- stars are reached comes in: "🛒 🛁 Bath Room ready!". Seasonal rooms only toast in season, and rooms already
-- owned never do. (The room only appears on the plot once it's bought, so "unlocked" alone would mislead.)

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
local lastCash: { [Player]: number } = {}
local toldReady: { [Player]: { [string]: boolean } } = {} -- rooms whose "ready to buy" toast was sent

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

local function forSale(data: Types.Data, roomId: string, winter: boolean): boolean
	local room = Rooms[roomId]
	return not data.Rooms[roomId] and room.Price > 0 and (room.Season == nil or (room.Season == "Winter" and winter))
end

local function markReady(player: Player, roomId: string)
	local told = toldReady[player]
	if not told then
		told = {}
		toldReady[player] = told
	end
	told[roomId] = true
end

-- Toasts each room whose stars line was just crossed, and a room that just became affordable.
local function onChanged(player: Player, data: Types.Data)
	if player.Parent ~= Players then
		return -- a last update while leaving: don't keep an entry for a player who's gone
	end
	local before, cashBefore = lastStars[player], lastCash[player]
	local now, cash = data.Stars, data.Cash
	lastStars[player], lastCash[player] = now, cash
	if before == nil or cashBefore == nil then
		return
	end
	local winter = isWinter()

	-- Stars just reached a room's line.
	local crossed: { [string]: boolean } = {}
	if now > before then
		for _, roomId in ProgressLogic.unlockedBetween(Rooms, before, now) do
			if forSale(data, roomId, winter) then
				crossed[roomId] = true
				local room = Rooms[roomId]
				local name = room.Icon .. " " .. room.Name
				if cash >= room.Price then
					markReady(player, roomId)
					Remotes.news(player, "🔓 " .. name .. "! Buy in 🛒")
				else
					Remotes.news(player, "⭐ " .. name .. "! Save " .. ProgressLogic.CASH_ICON .. room.Price)
				end
			end
		end
	end

	-- The cash for a room whose stars are already there just came in (once per room per session).
	if cash > cashBefore then
		for _, roomId in Rooms.Order do
			local room = Rooms[roomId]
			local told = toldReady[player]
			if
				not crossed[roomId]
				and not (told and told[roomId])
				and forSale(data, roomId, winter)
				and now >= room.StarsNeeded
				and cashBefore < room.Price
				and cash >= room.Price
			then
				markReady(player, roomId)
				Remotes.news(player, "🛒 " .. room.Icon .. " " .. room.Name .. " ready!")
			end
		end
	end
end

function Progress.start()
	PlayerData.Loaded:Connect(function(player: Player, data: Types.Data)
		-- The baseline: loading a save never toasts.
		lastStars[player] = data.Stars
		lastCash[player] = data.Cash
	end)
	PlayerData.Changed:Connect(onChanged)
	Players.PlayerRemoving:Connect(function(player)
		lastStars[player] = nil
		lastCash[player] = nil
		toldReady[player] = nil
	end)
end

return Progress
