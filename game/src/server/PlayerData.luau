--!strict
-- Loads, holds and saves each player's progress: save schema v4 (Logic/Schema). Server only.
--
-- API (build plan §B5):
--   PlayerData.get(p): Data?            the live save. READ ONLY: change it with update()
--   PlayerData.update(p, fn)            fn(data) mutates; marks dirty, refreshes leaderstats, then State.push(p)
--   PlayerData.waitLoaded(p): Data?     yields until loaded (nil if the player left first). A load always ends:
--                                       every DataStore wait below is bounded.
--   PlayerData.Loaded                   signal (p, data), after a load (even a failed one: data is then defaults)
--   PlayerData.Changed                  signal (p, data), after every update (State listens to push snapshots)
--   PlayerData.canSave(p): boolean      this session's progress is being saved (also the `DataOk` attribute)
--   Progression v2 (build plan §B8):
--   PlayerData.isOpen(p): boolean       loaded and not closing: update() would be accepted now (the Market checks
--                                       both sides with it before a transfer)
--   PlayerData.saveNow(p): boolean      yields: writes the save now if this session owns the lock (and may save),
--                                       true when the write landed. Never two writes for one player at once (it
--                                       waits for one in flight). False when not loaded, leaving, or not saving.
--                                       The Market saves the seller THEN the buyer; a rebirth saves at once
--   PlayerData.writeAfter(first, second, leaveOut?)   (integration; review fix) the ORDER of two saves. The Market
--                                       calls it (seller, buyer, Market.Pure.leaveOut(nurse, price)) on every sale.
--                                       Until `first`'s changes made so far have landed in the store, every write of
--                                       `second`'s (autosave, saveNow, a rebirth's, its leave-save) is written with
--                                       the sale left out (the nurse gone, the price back); it waits a moment (up to
--                                       WRITE_AFTER_SECONDS) only while first has a write in flight. So the buyer's
--                                       stored save never holds the nurse while the seller's still does: not after a
--                                       crash, not if the seller's leave-save gives up or its lock is lost (then the
--                                       seller keeps the nurse and the buyer the price), and two players trading both
--                                       ways never wait on each other. A crash can lose a sale, never duplicate one.
--                                       Each call adds a dependency (two sales, two); one that landed is dropped
--
-- Safety (roblox-datastores skill):
--   · Writes use UpdateAsync with a session lock, so two servers never write over each other (fast rejoin,
--     teleport). The stored record is { Data = <v2 save>, Lock = { Owner = <session id>, At = <unix> } }.
--   · A failed load NEVER saves: the player plays on defaults, `DataOk` is false and a toast warns.
--   · A save written by a NEWER schema loads read-only (never written back down to this version).
--   · Autosave every Config.AutosaveSeconds, save on leave, and save everyone in BindToClose. The leave-save
--     retries with backoff, so one DataStore hiccup neither loses the last minutes nor strands the lock.
--   · A join that finds another server's lock waits for it: quick retries for a fast rejoin, then slower ones
--     until that lock's lease runs out (a server that died without releasing it), never a whole session on
--     defaults while the real save sits behind a stale lock.
--   · A rejoin to THIS server (a new Player object, the same UserId) first waits for the old Player's load or
--     leave-save (bounded by RELEASE_WAIT): the lock carries this server's id, so the claim alone wouldn't stop it,
--     and the old write landing later would leave a stale save loaded and then clear the new session's lock.
--   · Dirty is only cleared when nothing changed while the write was in flight.
--   · A first v2 load reads Config.LegacyDataStoreName once and migrates the shop-sim save.
--   · Saved day fields later than the real UTC day are pulled back on load (Schema.reconcile's `today`).
--
-- Studio test switch: Workspace attribute FreshSave = true (set it before Play; Studio only, a live server
-- ignores it). Every player who joins then gets a blank save (Schema.default(), so the first-session tutorial
-- starts) that lives in memory only: the DataStore is never read or written and no lock is taken, so the real
-- save is untouched. DataOk is false (nothing is saved) and the player also gets the attribute FreshSave = true,
-- so the HUD skips its "Not saving" warning and the screen looks like a real first visit. Output says so.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

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
local LOCK_RETRIES = 6 -- another server still holds the lock: quick tries while its leave-save releases it
local LOCK_RETRY_SECONDS = 3
local LOCK_SLOW_RETRY_SECONDS = 10 -- then slower tries until that lock's lease runs out
local LOCK_MAX_WAIT = LEASE_SECONDS + 30 -- whatever the other server's clock says
local ERROR_RETRIES = 3
local RELEASE_WAIT = 60 -- seconds a same-server rejoin waits for the old session's leave-save (retries included)
local SAVING_OFF_TOAST = "⚠️ Saving is off"
local WAITING_TOAST = "⏳ Opening your clinic..."
local FRESH_SAVE = "FreshSave" -- the Workspace attribute (Studio test switch) and the player attribute it sets
local WRITE_AFTER_SECONDS = 10 -- writeAfter: the longest a save waits for the other one to land

------------------------------------------------------------------------------------------------------------------
-- writeAfter's rules (pure: no Roblox services, no upvalues; tests/PlayerData.spec loads this block on its own)
------------------------------------------------------------------------------------------------------------------

-- PURE-BEGIN
local Pure = {}

-- One writeAfter(first, second, leaveOut): `second`'s save may hold the sale only once `first`'s changes up to
-- Changes have landed in the store.
--   Session   first's session (Written, Saving and CanSave are read)
--   Changes   first's Changes count when it was called (the sale's take is in it)
--   From      second's Changes count then (the sale's give is in it, so everything before From is held in full)
--   Until     os.clock() bound for a dependency without LeaveOut (one that is only waited for)
--   LeaveOut  fn(snapshot): takes the sale back out of a COPY of second's save (the nurse goes, the price comes back)
export type Dep = { Session: any, Changes: number, From: number, Until: number, LeaveOut: ((any) -> ())? }

function Pure.landed(dep: Dep): boolean
	local first = dep.Session
	return type(first) == "table" and type(first.Written) == "number" and first.Written >= dep.Changes
end

-- Worth waiting a moment before a write: an unmet dependency whose session has a write in flight (it may land it in
-- a moment), or one without LeaveOut until its Until passes or its session can't save. Never needed for safety (a
-- LeaveOut dependency is left out of the snapshot whatever happens), only so the sale is in the write sooner.
function Pure.waiting(deps: { Dep }, now: number): boolean
	for _, dep in deps do
		if not Pure.landed(dep) then
			local first = dep.Session
			if dep.LeaveOut ~= nil then
				if type(first) == "table" and first.Saving == true then
					return true
				end
			elseif type(first) == "table" and first.CanSave == true and now < dep.Until then
				return true
			end
		end
	end
	return false
end

-- Right before a write, with no yield until the snapshot is written: drops the dependencies that landed (and, without
-- LeaveOut, those that lapsed), and takes every sale whose seller's write hasn't landed back out of `snapshot` (a
-- deep copy of the save; nil = no data write). So the buyer's stored save holds a nurse only once the seller's stored
-- save has lost it, whatever the write order, a crash, or a seller's save that never lands (its leave-save gave up,
-- or it lost its lock: the seller keeps the nurse and the buyer's stored save keeps the price). Returns (ok, masked,
-- heldUpTo): ok false if a LeaveOut errored (write no data this time); masked whether anything was left out; heldUpTo
-- the Changes count this snapshot holds in full (Written may become it): everything before the earliest sale left
-- out, so a sale chained on this one (it sells the nurse on) waits for it in turn.
function Pure.prepare(deps: { Dep }, snapshot: any, changes: number, now: number): (boolean, boolean, number)
	local ok, masked, held = true, false, changes
	for index = #deps, 1, -1 do
		local dep = deps[index]
		local leaveOut = dep.LeaveOut
		local first = dep.Session
		-- Gone: it landed, or (only waited for, without LeaveOut) its bound passed or its session can't save.
		local lapsed = leaveOut == nil and (type(first) ~= "table" or first.CanSave ~= true or now >= dep.Until)
		if Pure.landed(dep) or lapsed then
			table.remove(deps, index)
		elseif leaveOut ~= nil then
			masked = true
			held = math.min(held, dep.From - 1)
			if snapshot ~= nil and not pcall(leaveOut, snapshot) then
				ok = false
			end
		end
	end
	return ok, masked, held
end
-- PURE-END

PlayerData.Pure = Pure

type Session = {
	Data: Data,
	CanSave: boolean, -- false after a failed load or a lost lock: never write
	Owned: boolean, -- this server holds the lock and must release it
	Dirty: boolean,
	Changes: number, -- bumped by every update(): a write only clears Dirty if this didn't move meanwhile
	LastWrite: number,
	Saving: boolean,
	Released: boolean, -- the player left: no more autosaves, the leave-save is under way
	Final: boolean, -- the leave-save took its snapshot: later updates would be lost, so they're refused
	Written: number, -- the Changes count the last successful data write held in full (writeAfter reads it)
	After: { Dep }, -- writeAfter: sales this save may hold only once their seller's write landed (Pure.prepare)
}

type WriteResult = "Ok" | "Failed" | "LostLock" | "Skipped"

local sessions: { [Player]: Session } = {}
local pendingWrites = 0
-- UserId -> store calls still running on this server for a Player of that UserId: a load, or a leave-save.
-- Keyed by UserId, not Player: a rejoin to the same server is a new Player, and its load waits for these.
local busy: { [number]: number } = {}

local function hold(userId: number)
	busy[userId] = (busy[userId] or 0) + 1
end

local function unhold(userId: number)
	local left = (busy[userId] or 1) - 1
	busy[userId] = if left > 0 then left else nil
end

-- A rejoin to this server: the last Player's load or leave-save lands first. Its lock carries this server's id, so
-- claim() would take it at once; the old write would then clear the new session's lock (and this load would read a
-- save from before it). Bounded by RELEASE_WAIT. False if the player left meanwhile.
local function waitForStore(player: Player): boolean
	local started = os.clock()
	while busy[player.UserId] do
		if player.Parent ~= Players then
			return false
		end
		if os.clock() - started > RELEASE_WAIT then
			warn("[PlayerData] The last save for", player.UserId, "is still running; loading anyway")
			break
		end
		task.wait(0.2)
	end
	return player.Parent == Players
end

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
-- "Locked" returns the other lock's At (unix seconds) instead, so the caller knows when its lease runs out.
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
				saved = lock.At
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
-- Returns "Ok", "Failed" (the request errored: safe to try again, it writes the whole save), "LostLock" or
-- "Skipped" (nothing to do), plus the error for "Failed".
local function write(player: Player, session: Session, release: boolean): (WriteResult, any)
	local activeStore = store
	if not activeStore or not session.Owned then
		return "Skipped", nil
	end
	-- One write at a time; and a seller's write in flight may land a sale this save depends on in a moment, so wait
	-- for it (bounded). Checked again after every wait: a writeAfter can arrive while this write waits its turn. The
	-- order never rests on this wait: Pure.prepare leaves every sale whose seller hasn't landed out of the snapshot.
	local deadline = os.clock() + WRITE_AFTER_SECONDS
	while session.Saving or (os.clock() < deadline and Pure.waiting(session.After, os.clock())) do
		task.wait(0.1)
	end
	if not session.Owned then
		return "Skipped", nil
	end
	-- From here to the snapshot nothing yields.
	session.Saving = true
	pendingWrites += 1

	if release then
		session.Final = true -- from here on update() refuses: nothing after this snapshot would be saved
	end
	local changes = session.Changes
	local snapshot = if session.CanSave then deepCopy(session.Data) else nil
	local prepared, masked, heldUpTo = Pure.prepare(session.After, snapshot, changes, os.clock())
	if not prepared then
		warn("[PlayerData] Couldn't leave a pending sale out of the save for", player.UserId, "- lock only this time")
		snapshot = nil
	end
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

	local result: WriteResult = "Ok"
	if not ok then
		warn("[PlayerData] Save failed for", player.UserId, err)
		result = "Failed"
	elseif lostLock then
		warn("[PlayerData] Lost the save lock for", player.UserId, "- saving is off for this session")
		session.Owned = false
		session.CanSave = false
		if player.Parent == Players then
			player:SetAttribute("DataOk", false)
			Remotes.toast(player, SAVING_OFF_TOAST)
		end
		result = "LostLock"
	else
		session.LastWrite = os.clock()
		if wroteData then
			session.Written = math.max(session.Written, heldUpTo)
		end
		-- An update() that ran while the request was in flight isn't in this snapshot: stay dirty for it. So is a sale
		-- left out (masked): the next write holds it once its seller's write has landed.
		if wroteData and not masked and session.Changes == changes then
			session.Dirty = false
		end
		if release then
			session.Owned = false
		end
	end

	session.Saving = false
	pendingWrites -= 1
	return result, err
end

------------------------------------------------------------------------------------------------------------------
-- Load and release
------------------------------------------------------------------------------------------------------------------

local function realDay(): number
	return os.time() // 86400
end

-- Returns (data, canSave, owned).
local function loadFromStore(player: Player): (Data, boolean, boolean)
	local activeStore = store
	if not activeStore then
		return Schema.default(), false, false
	end

	local errors = 0
	local locks = 0
	local waitStarted = os.clock()
	local toldWaiting = false
	while true do
		local status, result = claim(activeStore, player)
		if status == "Claimed" then
			if result ~= nil then
				if Schema.isNewer(result) then
					-- A newer server wrote this: play on a copy, keep the lock (so it's released), never write.
					warn("[PlayerData] Save for", player.UserId, "is from a newer version: saving is off")
					return Schema.reconcile(result, realDay()), false, true
				end
				return Schema.reconcile(result, realDay()), true, true
			end
			-- A new v2 key: migrate the shop-sim save once. If that read fails, play on defaults without
			-- saving, so the v1 save is still there to migrate next time.
			local legacyOk, legacy = readLegacy(player)
			if not legacyOk then
				warn("[PlayerData] Could not read the v1 save for", player.UserId, legacy)
				return Schema.default(), false, true
			end
			return Schema.reconcile(legacy, realDay()), true, true
		elseif status == "Locked" then
			-- Quick tries first (the other server's leave-save is usually seconds away), then slower ones until
			-- that lock's lease runs out: a server that died, or whose leave-save failed, can't free it sooner.
			locks += 1
			local lockAt = if type(result) == "number" then result else os.time()
			local leaseLeft = lockAt + LEASE_SECONDS - os.time()
			if os.clock() - waitStarted > LOCK_MAX_WAIT then
				warn("[PlayerData] Save still locked by another server for", player.UserId)
				return Schema.default(), false, false
			end
			if locks > LOCK_RETRIES and not toldWaiting then
				toldWaiting = true
				Remotes.toast(player, WAITING_TOAST)
			end
			task.wait(
				if locks <= LOCK_RETRIES
					then LOCK_RETRY_SECONDS
					else math.clamp(leaseLeft + 1, 1, LOCK_SLOW_RETRY_SECONDS)
			)
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

-- The Studio-only FreshSave switch (see the header). Read at each join, so it can change between Plays.
local function freshSave(): boolean
	return RunService:IsStudio() and Workspace:GetAttribute(FRESH_SAVE) == true
end

local function load(player: Player)
	if sessions[player] then
		return
	end
	makeLeaderstats(player)

	local data: Data, canSave: boolean, owned: boolean = Schema.default(), false, false
	local fresh = freshSave()
	local userId = player.UserId
	local held = false
	if fresh then
		warn("[PlayerData] FreshSave is on (Studio only): " .. player.Name .. " plays a blank save that is never saved")
		task.wait() -- a real load always yields: let every system start first, as it would live
	elseif waitForStore(player) then
		hold(userId) -- a quicker rejoin waits for this load (and its hand-back below)
		held = true
		local loaded, err = pcall(function()
			data, canSave, owned = loadFromStore(player)
		end)
		if not loaded then
			-- A bug, not a DataStore error: play on defaults and never save (the lock, if taken, lapses).
			warn("[PlayerData] Load crashed for", player.UserId, err)
			data, canSave, owned = Schema.default(), false, false
		end
	end
	local session: Session = {
		Data = data,
		CanSave = canSave,
		Owned = owned,
		Dirty = canSave, -- a migrated or reconciled save gets written back in v2 shape on the next autosave
		Changes = 0,
		LastWrite = os.clock(),
		Saving = false,
		Released = false,
		Final = false,
		Written = 0,
		After = {},
	}

	if player.Parent ~= Players then
		-- Left while loading: hand the lock straight back, without writing data (a quick rejoin waits for it).
		session.CanSave = false
		task.spawn(function()
			pcall(write, player, session, true)
			if held then
				unhold(userId)
			end
		end)
		return
	end
	if held then
		unhold(userId)
	end

	sessions[player] = session
	player:SetAttribute("DataOk", canSave)
	player:SetAttribute(FRESH_SAVE, if fresh then true else nil)
	pushToPlayer(player, data)
	if not canSave and not fresh then
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
	local userId = player.UserId
	hold(userId) -- a rejoin to this server waits for this leave-save (waitForStore)
	-- Let other PlayerRemoving handlers (a cure landing, a goal) finish their last update first.
	task.wait()
	-- The last save, and the lock handed back. A failed request is retried with backoff (it writes the whole
	-- save, so a repeat is harmless); without that, one hiccup loses everything since the last autosave and
	-- strands the lock for a whole lease.
	local done, crash = pcall(function()
		for attempt = 1, ERROR_RETRIES do
			local result, err = write(player, session, true)
			if result ~= "Failed" or isPermanent(err) or attempt == ERROR_RETRIES then
				if result == "Failed" then
					warn("[PlayerData] Gave up on the leave-save for", userId)
				end
				break
			end
			task.wait(2 ^ (attempt - 1)) -- 1 s, 2 s
		end
	end)
	if not done then
		warn("[PlayerData] Leave-save crashed for", userId, crash)
	end
	sessions[player] = nil
	unhold(userId)
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
	if not session or session.Final then
		return false -- not loaded, gone, or the leave-save already took its snapshot
	end
	fn(session.Data)
	session.Dirty = true
	session.Changes += 1
	if player.Parent == Players then
		pushToPlayer(player, session.Data)
	end
	PlayerData.Changed:Fire(player, session.Data)
	return true
end

-- Waits for the load however long the DataStore takes (a lock wait can run for minutes); nil only if the player
-- leaves first. Every wait inside the load is bounded, so this always returns.
function PlayerData.waitLoaded(player: Player): Data?
	while not sessions[player] do
		if player.Parent ~= Players then
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

-- Loaded and not closing: an update() now would be accepted.
function PlayerData.isOpen(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and not session.Released and not session.Final and player.Parent == Players
end

-- Writes now (yields). write() already waits for a write in flight, so two never run for one player at once.
function PlayerData.saveNow(player: Player): boolean
	local session = sessions[player]
	if not session or session.Released or not session.CanSave or not session.Owned then
		return false
	end
	local ok, result = pcall(write, player, session, false)
	return ok and result == "Ok"
end

-- The order of two saves (see the header): `second`'s writes hold the sale only once `first`'s changes so far have
-- landed. `leaveOut(snapshot)` takes the sale back out of a copy of second's save; until first's write lands, every
-- write of second's (autosave, saveNow, its leave-save) is written with it applied (Pure.prepare). Without it the
-- dependency is only waited for, bounded by WRITE_AFTER_SECONDS. Each call adds one (two sales are two). Never yields.
-- Without both sessions it does nothing.
function PlayerData.writeAfter(first: Player, second: Player, leaveOut: ((any) -> ())?)
	local a, b = sessions[first], sessions[second]
	if not a or not b or a == b then
		return
	end
	table.insert(b.After, {
		Session = a,
		Changes = a.Changes,
		From = b.Changes,
		Until = os.clock() + WRITE_AFTER_SECONDS,
		LeaveOut = if type(leaveOut) == "function" then leaveOut else nil,
	})
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
