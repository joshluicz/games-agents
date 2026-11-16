--!strict
-- Loads, holds and saves each player's progress. Server only.
-- If DataStores are unavailable (e.g. Studio without "Enable Studio Access to API Services"),
-- the game still runs; progress just isn't saved.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

export type Data = {
	Cash: number,
	Served: number,
	Upgrades: { [string]: number },
}

local PlayerData = {}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[PlayerData] DataStore unavailable, progress will not save:", result)
	end
end

local sessions: { [Player]: Data } = {}
local loadedOk: { [Player]: boolean } = {}

local function defaultData(): Data
	local upgrades = {}
	for _, name in Config.UpgradeOrder do
		upgrades[name] = 0
	end
	return { Cash = 0, Served = 0, Upgrades = upgrades }
end

local function reconcile(saved: any): Data
	local data = defaultData()
	if typeof(saved) ~= "table" then
		return data
	end
	if typeof(saved.Cash) == "number" then
		data.Cash = saved.Cash
	end
	if typeof(saved.Served) == "number" then
		data.Served = saved.Served
	end
	if typeof(saved.Upgrades) == "table" then
		for _, name in Config.UpgradeOrder do
			local level = saved.Upgrades[name]
			if typeof(level) == "number" then
				data.Upgrades[name] = level
			end
		end
	end
	return data
end

local function withRetries<T>(fn: () -> T): (boolean, T | string)
	local lastError: any = nil
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		task.wait(attempt)
	end
	return false, tostring(lastError)
end

local function key(player: Player): string
	return "player_" .. player.UserId
end

local function pushToPlayer(player: Player, data: Data)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local cash = leaderstats:FindFirstChild(Config.CurrencyName)
		if cash and cash:IsA("IntValue") then
			cash.Value = math.floor(data.Cash)
		end
		local served = leaderstats:FindFirstChild("Served")
		if served and served:IsA("IntValue") then
			served.Value = data.Served
		end
	end
	for name, level in data.Upgrades do
		player:SetAttribute("Upgrade_" .. name, level)
	end
end

function PlayerData.load(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = Config.CurrencyName
	cash.Parent = leaderstats
	local served = Instance.new("IntValue")
	served.Name = "Served"
	served.Parent = leaderstats
	leaderstats.Parent = player

	local data = defaultData()
	local ok = false
	local activeStore = store
	if activeStore then
		local success, result = withRetries(function()
			return activeStore:GetAsync(key(player))
		end)
		if success then
			data = reconcile(result)
			ok = true
		else
			warn("[PlayerData] Load failed for", player.Name, result)
		end
	end

	if not player.Parent then
		return -- left while loading
	end
	sessions[player] = data
	-- Never overwrite saved progress with defaults after a failed load.
	loadedOk[player] = ok
	pushToPlayer(player, data)
end

function PlayerData.get(player: Player): Data?
	return sessions[player]
end

function PlayerData.addCash(player: Player, amount: number)
	local data = sessions[player]
	if not data then
		return
	end
	data.Cash += amount
	pushToPlayer(player, data)
end

function PlayerData.spendCash(player: Player, amount: number): boolean
	local data = sessions[player]
	if not data or data.Cash < amount then
		return false
	end
	data.Cash -= amount
	pushToPlayer(player, data)
	return true
end

function PlayerData.addServed(player: Player)
	local data = sessions[player]
	if not data then
		return
	end
	data.Served += 1
	pushToPlayer(player, data)
end

function PlayerData.setUpgrade(player: Player, name: string, level: number)
	local data = sessions[player]
	if not data then
		return
	end
	data.Upgrades[name] = level
	pushToPlayer(player, data)
end

function PlayerData.save(player: Player)
	local data = sessions[player]
	local activeStore = store
	if not data or not activeStore or not loadedOk[player] then
		return
	end
	local snapshot = table.clone(data)
	snapshot.Upgrades = table.clone(data.Upgrades)
	local ok, err = withRetries(function()
		activeStore:SetAsync(key(player), snapshot, { player.UserId })
		return true
	end)
	if not ok then
		warn("[PlayerData] Save failed for", player.Name, err)
	end
end

function PlayerData.release(player: Player)
	PlayerData.save(player)
	sessions[player] = nil
	loadedOk[player] = nil
end

function PlayerData.start()
	Players.PlayerAdded:Connect(PlayerData.load)
	for _, player in Players:GetPlayers() do
		task.spawn(PlayerData.load, player)
	end
	Players.PlayerRemoving:Connect(PlayerData.release)

	task.spawn(function()
		while true do
			task.wait(Config.AutosaveSeconds)
			for player in sessions do
				task.spawn(PlayerData.save, player)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in sessions do
			pending += 1
			task.spawn(function()
				PlayerData.save(player)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

return PlayerData
