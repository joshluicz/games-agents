--!strict
-- Loads, holds and saves each player's progress: save schema v2 (Logic/Schema). Server only.
--
-- API (build plan §B5):
--   PlayerData.get(p): Data?            the live save. READ ONLY: change it with update()
--   PlayerData.update(p, fn)            fn(data) mutates; marks dirty, refreshes leaderstats, then State.push(p)
--   PlayerData.waitLoaded(p): Data?     yields until loaded (nil if the player left first)
--   PlayerData.Loaded                   signal (p, data), after a load (even a failed one: data is then defaults)
--   PlayerData.Changed                  signal (p, data), after every update (State listens to push snapshots)
--
-- Safety (roblox-datastores skill):
--   · Writes use UpdateAsync with a session lock, so two servers never write over each other (fast rejoin,
--     teleport). The stored record is { Data = <v2 save>, Lock = { Owner = <session id>, At = <unix> } }.
--   · A failed load NEVER saves: the player plays on defaults, `DataOk` is false and a toast warns.
--   · Autosave every Config.AutosaveSeconds, save on leave, and save everyone in BindToClose.
--   · A first v2 load reads Config.LegacyDataStoreName once and migrates the shop-sim save.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Schema = require(Shared.Logic.Schema)
local Signal = require(Shared.Signal)

export type Data = Schema.Data

local PlayerData = {}

PlayerData.Loaded = Signal.new()
PlayerData.Changed = Signal.new()

local SESSION_ID = HttpService:GenerateGUID(false) -- game.JobId is "" in Studio, so not unique enough
local LEASE_SECONDS = Config.AutosaveSeconds * 3 + 30 -- a lock older than this is from a server that died
local LOCK_RETRIES = 6 -- another server still holds the lock: wait for its leave-save to release it
local LOCK_RETRY_SECONDS = 3
local ERROR_RETRIES = 3
local SAVING_OFF_TOAST = "⚠️ Saving is off"

type Session = {
	Data: Data,
	CanSave: boolean, -- false after a failed load or a lost lock: never write
	Owned: boolean, -- this server holds the lock and must release it
	Dirty: boolean,
	LastWrite: number,
	Saving: boolean,
	Released: boolean,
}

local sessions: { [Player]: Session } = {}
local pendingWrites = 0

local function getStore(name: string): DataStore?
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(name)
	end)
	if ok then
		return result
	end
	warn("[PlayerData] DataStore unavailable, progress will not save:", result)
	return nil
end

local store = getStore(Config.DataStoreName)
local legacyStore = getStore(Config.LegacyDataStoreName)

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

-- Studio without "Enable Studio Access to API Services" fails every request the same way: don't retry those.
local function isPermanent(err: any): boolean
	local text = tostring(err)
	return string.find(text, "StudioAccessToApisNotAllowed", 1, true) ~= nil or string.find(text, "^%s*403") ~= nil
end

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value :: any do
		copy[key] = deepCopy(item)
	end
	return copy :: any
end

------------------------------------------------------------------------------------------------------------------
-- Leaderstats and attributes
------------------------------------------------------------------------------------------------------------------

local function makeLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = Config.CurrencyName
	cash.Parent = leaderstats
	local stars = Instance.new("IntValue")
	stars.Name = "Stars"
	stars.Parent = leaderstats
	leaderstats.Parent = player
end

local function pushToPlayer(player: Player, data: Data)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local cash = leaderstats:FindFirstChild(Config.CurrencyName)
		if cash and cash:IsA("IntValue") then
			cash.Value = math.floor(data.Cash)
		end
		local stars = leaderstats:FindFirstChild("Stars")
		if stars and stars:IsA("IntValue") then
			stars.Value = math.floor(data.Stars)
		end
	end
	player:SetAttribute("Stars", data.Stars)
	player:SetAttribute("Cured", data.Cured)
end

------------------------------------------------------------------------------------------------------------------
-- DataStore calls
------------------------------------------------------------------------------------------------------------------

type ClaimResult = "Claimed" | "Locked" | "Error"

-- Takes the session lock in one UpdateAsync, and returns the saved v2 data (nil for a new key).
local function claim(activeStore: DataStore, player: Player): (ClaimResult, any)
	local status: ClaimResult = "Error"
	local saved: any = nil
	local ok, err = pcall(function()
		activeStore:UpdateAsync(keyFor(player), function(record: any)
			-- This callback can run more than once and must not yield: reset the outputs every time.
			status, saved = "Locked", nil
			if type(record) ~= "table" then
				record = {}
			elseif record.Data == nil and record.Lock == nil and next(record) ~= nil then
				record = { Data = record } -- a bare save written without the lock wrapper
			end
			local lock = record.Lock
			local now = os.time()
			if
				type(lock) == "table"
				and lock.Owner ~= SESSION_ID
				and type(lock.At) == "number"
				and now - lock.At < LEASE_SECONDS
			then
				return nil -- another live server owns it: cancel the write
			end
			record.Lock = { Owner = SESSION_ID, At = now }
			status, saved = "Claimed", record.Data
			return record, { player.UserId }
		end)
	end)
	if not ok then
		return "Error", err
	end
	return status, saved
end

local function readLegacy(player: Player): (boolean, any)
	local activeStore = legacyStore
	if not activeStore then
		return false, "no legacy store"
	end
	local lastError: any = nil
	for attempt = 1, ERROR_RETRIES do
		local ok, result = pcall(function()
			return activeStore:GetAsync(keyFor(player))
		end)
		if ok then
			return true, result
		end
		lastError = result
		if isPermanent(result) then
			break
		end
		task.wait(attempt)
	end
	return false, lastError
end

-- Writes the save (unless it can't), refreshes or releases the lock. Serialised per player.
local function write(player: Player, session: Session, release: boolean)
	local activeStore = store
	if not activeStore or not session.Owned then
		return
	end
	while session.Saving do
		task.wait(0.1)
	end
	if not session.Owned then
		return
	end
	session.Saving = true
	pendingWrites += 1

	local snapshot = if session.CanSave then deepCopy(session.Data) else nil
	local lostLock = false
	local wroteData = false
	local ok, err = pcall(function()
		activeStore:UpdateAsync(keyFor(player), function(record: any)
			lostLock, wroteData = false, false
			if type(record) ~= "table" or type(record.Lock) ~= "table" or record.Lock.Owner ~= SESSION_ID then
				lostLock = true
				return nil -- never write a stale snapshot over another server's newer save
			end
			if snapshot ~= nil then
				record.Data = snapshot
				wroteData = true
			end
			record.Lock = if release then nil else { Owner = SESSION_ID, At = os.time() }
			return record, { player.UserId }
		end)
	end)

	if not ok then
		warn("[PlayerData] Save failed for", player.UserId, err)
	elseif lostLock then
		warn("[PlayerData] Lost the save lock for", player.UserId, "- saving is off for this session")
		session.Owned = false
		session.CanSave = false
		player:SetAttribute("DataOk", false)
		Remotes.toast(player, SAVING_OFF_TOAST)
	else
		session.LastWrite = os.clock()
		if wroteData then
			session.Dirty = false
		end
		if release then
			session.Owned = false
		end
	end

	session.Saving = false
	pendingWrites -= 1
end

------------------------------------------------------------------------------------------------------------------
-- Load and release
------------------------------------------------------------------------------------------------------------------

-- Returns (data, canSave, owned).
local function loadFromStore(player: Player): (Data, boolean, boolean)
	local activeStore = store
	if not activeStore then
		return Schema.default(), false, false
	end

	local errors = 0
	local locks = 0
	while true do
		local status, result = claim(activeStore, player)
		if status == "Claimed" then
			if result ~= nil then
				return Schema.reconcile(result), true, true
			end
			-- A new v2 key: migrate the shop-sim save once. If that read fails, play on defaults without
			-- saving, so the v1 save is still there to migrate next time.
			local legacyOk, legacy = readLegacy(player)
			if not legacyOk then
				warn("[PlayerData] Could not read the v1 save for", player.UserId, legacy)
				return Schema.default(), false, true
			end
			return Schema.reconcile(legacy), true, true
		elseif status == "Locked" then
			locks += 1
			if locks > LOCK_RETRIES then
				warn("[PlayerData] Save still locked by another server for", player.UserId)
				return Schema.default(), false, false
			end
			task.wait(LOCK_RETRY_SECONDS)
		else
			errors += 1
			warn("[PlayerData] Load failed for", player.UserId, result)
			if errors >= ERROR_RETRIES or isPermanent(result) then
				return Schema.default(), false, false
			end
			task.wait(errors)
		end
		if player.Parent ~= Players then
			return Schema.default(), false, false
		end
	end
end

local function load(player: Player)
	if sessions[player] then
		return
	end
	makeLeaderstats(player)

	local data, canSave, owned = loadFromStore(player)
	local session: Session = {
		Data = data,
		CanSave = canSave,
		Owned = owned,
		Dirty = canSave, -- a migrated or reconciled save gets written back in v2 shape on the next autosave
		LastWrite = os.clock(),
		Saving = false,
		Released = false,
	}

	if player.Parent ~= Players then
		-- Left while loading: hand the lock straight back, without writing data.
		session.CanSave = false
		task.spawn(write, player, session, true)
		return
	end

	sessions[player] = session
	player:SetAttribute("DataOk", canSave)
	pushToPlayer(player, data)
	if not canSave then
		Remotes.toast(player, SAVING_OFF_TOAST)
	end
	PlayerData.Loaded:Fire(player, data)
	PlayerData.Changed:Fire(player, data)
end

local function release(player: Player)
	local session = sessions[player]
	if not session or session.Released then
		return
	end
	session.Released = true
	-- Let other PlayerRemoving handlers (a cure landing, a goal) finish their last update first.
	task.wait()
	write(player, session, true)
	sessions[player] = nil
end

------------------------------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------------------------------

function PlayerData.get(player: Player): Data?
	local session = sessions[player]
	return session and session.Data
end

-- fn mutates the live data. Returns false if the player has no loaded data (not loaded yet, or gone).
function PlayerData.update(player: Player, fn: (Data) -> ()): boolean
	local session = sessions[player]
	if not session or session.Released then
		return false
	end
	fn(session.Data)
	session.Dirty = true
	pushToPlayer(player, session.Data)
	PlayerData.Changed:Fire(player, session.Data)
	return true
end

function PlayerData.waitLoaded(player: Player): Data?
	local started = os.clock()
	while not sessions[player] do
		if player.Parent ~= Players or os.clock() - started > 60 then
			return nil
		end
		task.wait(0.1)
	end
	return sessions[player].Data
end

-- True when this session's progress is being saved (also the player's `DataOk` attribute).
function PlayerData.canSave(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.CanSave
end

function PlayerData.start()
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(release)

	task.spawn(function()
		while true do
			task.wait(Config.AutosaveSeconds)
			for player, session in sessions do
				local leaseDue = os.clock() - session.LastWrite > LEASE_SECONDS / 3
				if session.Owned and not session.Released and (session.Dirty or leaseDue) then
					task.spawn(write, player, session, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		for player in sessions do
			task.spawn(release, player)
		end
		local started = os.clock()
		task.wait() -- let every release start its write
		while (pendingWrites > 0 or next(sessions) ~= nil) and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

return PlayerData
