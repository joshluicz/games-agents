--!strict
-- Global leaderboards (game/README.md "Leaderboards"). Server only.
--   Leaderboards.payload(p): Payload      what the 🏆 panel shows p: each board's top rows and p's own place
--   Leaderboards.status(): Status         "Loading" (no read yet) | "Live" | "Offline" (no DataStores here)
--   start(): the plaza boards (BoardBuilder), the write and read loops, the GetBoards remote, BindToClose
--
-- Boards (Logic/Leaderboard.BOARDS, listed in Config.Leaderboards): 🏥 Most Cured (Data.Cured), ⭐ Most Stars
-- (Data.Stars), ❤️ Most Hearts (Data.HeartsReceived) and 🏆 Cures This Week (Data.WeekCures, counted by Cure). One
-- OrderedDataStore per board ("Board_<Id>_v<Version>", the weekly one "..._w<UTC week>"), key tostring(UserId),
-- value a whole number. Hospital Level and Nurse Journal % are defined and switch on from Config once the depth
-- update's Data.Level and Data.NurseIndex exist.
--
-- Trust: values come ONLY from the server's save (PlayerData), and only from a save that loaded and is being saved
-- (PlayerData.canSave): defaults after a failed load, a lost lock or the Studio FreshSave switch never reach a board.
-- The client only asks "show me" (GetBoards: rate-limited, answered from the cache, never a DataStore call).
--
-- Admins are never on a board (Joshua, 2026-11-16: the 🛠️ Admin panel adds cash and stars, so their numbers are
-- fake): the game's owner (game.CreatorId when a user owns the game) and every UserId in Config.AdminUserIds
-- (Logic/Leaderboard.excluded). Their values are never written, and they're filtered out of every list read back,
-- in case an old value is stored. In Studio nobody is excluded, so the boards can be tested.
--
-- Budgets (Roblox's limits as of 2026-11, .claude/skills/roblox-datastores):
--   writes  only a player's CHANGED values, at most every WriteSeconds (150 s, the first one jittered 75-150 s after
--           join) and once when they leave: at most 4 SetAsync per player per 150 s (~1.6 a minute), against the
--           ordered-store write budget of 60 + 10 per player per minute per server (and the experience's 300 + 20 per
--           CCU per minute). Zeros are never written.
--   reads   one GetSortedAsync (the top Depth = 100) per board per RefreshSeconds (120 s), shared by the whole server:
--           4 every 2 minutes, against 5 + 2 per player per minute per server.
--   names   one UserService:GetUserInfosByUserIdsAsync per read pass, only for top-10 players who aren't in this
--           server and weren't looked up in the last hour.
--   Every call is in a pcall, and checks its request budget first (GetRequestBudgetForRequestType). A failure backs
--   off (30 s, doubling to 10 min); a write waits for the next pass, a leave-write tries once per board.
--
-- Live merge: the boards show the stored top list with this server's players' current saved values laid over it
-- (Logic/Leaderboard.merge), so a cure moves you up the plaza boards and your "You: #n" within seconds, without
-- waiting for the next write and read. Ranks are exact within the top Depth, then "#100+".
--
-- Studio: without "Enable Studio Access to API Services" (or in an unpublished place) the first DataStore call fails
-- with a permanent error. The status goes Offline (one line in Output, no errors), nothing is tried again, and the
-- boards say "Leaderboards open when the game is live". With API access, Studio reads and writes the LIVE boards
-- from the real save, just as it writes the real save.
--
-- Names: the DisplayName and @username Roblox already shows publicly. Players in this server: from their Player;
-- others: UserService (cached). Nothing else about anyone is read or shown.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Leaderboard = require(Shared.Logic.Leaderboard)
local PlayerData = require(script.Parent.PlayerData)
local BoardBuilder = require(script.Parent.BoardBuilder)

export type Status = Leaderboard.Status

local Leaderboards = {}

local CFG = Config.Leaderboards
local TICK_SECONDS = 5
local BUDGET_WAIT_SECONDS = 10
local CLOSE_WAIT_SECONDS = 20 -- BindToClose has 30 s in all, shared with PlayerData's saves
local UNKNOWN_NAME = "..." -- until UserService answers

type Cache = {
	Store: string, -- the store this list was read from (the weekly board's changes every Monday)
	Entries: { Leaderboard.Entry }, -- the stored top list, admins taken out
	Failures: number,
	NextReadAt: number,
}
type Writer = {
	Written: { [string]: number }, -- store -> the value this server last wrote for the player
	NextWriteAt: number,
	Busy: boolean,
}
type Name = { Display: string, User: string, At: number }

local status: Status = "Loading"
local boardIds: { string } = {} -- the 🏆 panel's tabs
local worldIds: { string } = {} -- the plaza boards
local allIds: { string } = {} -- both: every board that is read and written
local caches: { [string]: Cache } = {}
local writers: { [Player]: Writer } = {}
local stores: { [string]: OrderedDataStore } = {}
local names: { [number]: Name } = {}
local writeFailures = 0
local writeBlockedUntil = 0
local pendingWrites = 0
local renderDirty = true
local gantry: BoardBuilder.Gantry? = nil
local extra: Leaderboard.Extra = {}
local who: Leaderboard.Who = { Studio = true, CreatorIsUser = false, CreatorId = 0, UserIds = {} }

function Leaderboards.status(): Status
	return status
end

local function currentWeek(): number
	return Leaderboard.week(os.time())
end

local function goOffline(err: any)
	if status == "Offline" then
		return
	end
	status = "Offline"
	renderDirty = true
	print("[Leaderboards] DataStores aren't available here, so the boards wait for the live game: " .. tostring(err))
end

local function storeFor(name: string): OrderedDataStore?
	if status == "Offline" then
		return nil
	end
	local cached = stores[name]
	if cached then
		return cached
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	if not ok then
		if Leaderboard.isPermanent(result) then
			goOffline(result)
		else
			warn("[Leaderboards] Couldn't open " .. name .. ":", result)
		end
		return nil
	end
	stores[name] = result
	return result
end

-- Requests of this kind left right now (huge if the budget can't be read: the request itself is still pcalled).
local function budget(kind: Enum.DataStoreRequestType): number
	local ok, left = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(kind)
	end)
	return if ok and type(left) == "number" then left else math.huge
end

local function excluded(userId: number): boolean
	return Leaderboard.excluded(userId, who)
end

------------------------------------------------------------------------------------------------------------------
-- What the boards show
------------------------------------------------------------------------------------------------------------------

local function nameOf(userId: number): (string, string)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.DisplayName, player.Name
	end
	local known = names[userId]
	if known then
		return known.Display, known.User
	end
	return UNKNOWN_NAME, ""
end

-- The current saved values of this server's players on one board (only saves that are being saved, no admins).
local function liveValues(id: string, week: number): { [number]: number }
	local live: { [number]: number } = {}
	for _, player in Players:GetPlayers() do
		if PlayerData.canSave(player) and not excluded(player.UserId) then
			local value = Leaderboard.valueOf(id, PlayerData.get(player), week, extra)
			if value then
				live[player.UserId] = value
			end
		end
	end
	return live
end

local function merged(id: string, week: number): { Leaderboard.Entry }
	local cache = caches[id]
	if status ~= "Live" or not cache then
		return {}
	end
	return Leaderboard.merge(cache.Entries, liveValues(id, week), CFG.Depth)
end

local function topRows(list: { Leaderboard.Entry }): { Leaderboard.Row }
	local rows: { Leaderboard.Row } = {}
	for rank = 1, math.min(CFG.Shown, #list) do
		local entry = list[rank]
		local display, user = nameOf(entry.UserId)
		rows[rank] = { Rank = rank, Name = display, User = user, Value = entry.Value }
	end
	return rows
end

local function render()
	renderDirty = false
	local built = gantry
	if not built then
		return
	end
	local week = currentWeek()
	for _, id in worldIds do
		built.render(id, { Status = status, Rows = topRows(merged(id, week)) })
	end
end

function Leaderboards.payload(player: Player): Leaderboard.Payload
	local week = currentWeek()
	local data = PlayerData.get(player)
	local hidden = excluded(player.UserId)
	local boards: { Leaderboard.BoardPayload } = {}
	for _, id in boardIds do
		local list = merged(id, week)
		table.insert(boards, {
			Id = id,
			Top = topRows(list),
			You = {
				Rank = if hidden then nil else Leaderboard.rankOf(list, player.UserId),
				Value = Leaderboard.valueOf(id, data, week, extra) or 0,
				Hidden = if hidden then true else nil,
			},
		})
	end
	return { Status = status, Depth = CFG.Depth, Boards = boards }
end

------------------------------------------------------------------------------------------------------------------
-- Reading
------------------------------------------------------------------------------------------------------------------

-- Points each cache at this week's store; the weekly board starts empty when the UTC week turns.
local function syncWeek(week: number)
	for id, cache in caches do
		local name = Leaderboard.storeName(id, week, CFG.Version)
		if cache.Store ~= name then
			cache.Store = name
			cache.Entries = {}
			cache.Failures = 0
			cache.NextReadAt = 0
			renderDirty = true
		end
	end
end

local function read(id: string): boolean
	local cache = caches[id]
	local name = cache.Store
	local store = storeFor(name)
	if not store then
		cache.NextReadAt = os.clock() + CFG.RetrySeconds
		return false
	end
	if budget(Enum.DataStoreRequestType.GetSortedAsync) < CFG.MinBudget then
		cache.NextReadAt = os.clock() + BUDGET_WAIT_SECONDS
		return false
	end
	local ok, result = pcall(function()
		return store:GetSortedAsync(false, CFG.Depth):GetCurrentPage()
	end)
	if cache.Store ~= name then
		return false -- the week turned while this was in flight
	end
	if not ok then
		if Leaderboard.isPermanent(result) then
			goOffline(result)
			return false
		end
		cache.Failures += 1
		cache.NextReadAt = os.clock() + Leaderboard.backoff(cache.Failures, CFG.RetrySeconds, CFG.MaxBackoffSeconds)
		if cache.Failures == 1 then
			warn("[Leaderboards] Couldn't read " .. name .. " (trying again later):", result)
		end
		return false
	end
	cache.Failures = 0
	cache.Entries = Leaderboard.without(Leaderboard.parse(result, CFG.Depth), who)
	cache.NextReadAt = os.clock() + CFG.RefreshSeconds
	if status == "Loading" then
		status = "Live"
	end
	return true
end

-- DisplayNames for the top rows of players who aren't in this server: one batched lookup, cached.
local function resolveNames()
	local now = os.clock()
	local wanted: { number } = {}
	local asked: { [number]: boolean } = {}
	for _, cache in caches do
		for rank = 1, math.min(CFG.Shown, #cache.Entries) do
			local userId = cache.Entries[rank].UserId
			local known = names[userId]
			if
				not asked[userId]
				and not Players:GetPlayerByUserId(userId)
				and (not known or now - known.At > CFG.NameCacheSeconds)
			then
				asked[userId] = true
				table.insert(wanted, userId)
			end
		end
	end
	if #wanted == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(wanted)
	end)
	if not ok or type(infos) ~= "table" then
		warn("[Leaderboards] Couldn't look up names (trying again next read):", infos)
		return
	end
	for _, info: any in infos do
		if type(info) == "table" and type(info.Id) == "number" and type(info.Username) == "string" then
			local display = info.DisplayName
			names[info.Id] = {
				Display = if type(display) == "string" and display ~= "" then display else info.Username,
				User = info.Username,
				At = now,
			}
		end
	end
end

local function readPass()
	local readAny = false
	for _, id in allIds do
		if status == "Offline" then
			break
		end
		if os.clock() >= caches[id].NextReadAt and read(id) then
			readAny = true
		end
	end
	if readAny then
		resolveNames()
		renderDirty = true
	end
end

------------------------------------------------------------------------------------------------------------------
-- Writing
------------------------------------------------------------------------------------------------------------------

-- What to write for a player, from their save: nil for a save that isn't being saved, or an admin.
local function collect(player: Player): { [string]: number }?
	if excluded(player.UserId) or not PlayerData.canSave(player) then
		return nil
	end
	local data = PlayerData.get(player)
	if not data then
		return nil
	end
	return Leaderboard.values(allIds, data, currentWeek(), CFG.Version, extra)
end

-- Our own write is in the cache at once, so a player who just left keeps their place until the next read.
local function noteWritten(name: string, userId: number, value: number)
	for _, cache in caches do
		if cache.Store == name then
			cache.Entries = Leaderboard.merge(cache.Entries, { [userId] = value }, CFG.Depth)
		end
	end
end

local function write(player: Player, writer: Writer, values: { [string]: number }, leaving: boolean)
	pendingWrites += 1
	while writer.Busy do
		task.wait(0.1)
	end
	writer.Busy = true
	local key = tostring(player.UserId)
	for _, name in Leaderboard.changed(writer.Written, values) do
		if status == "Offline" then
			break
		end
		local blocked = os.clock() < writeBlockedUntil
			or budget(Enum.DataStoreRequestType.SetIncrementSortedAsync) < CFG.MinBudget
		if blocked and not leaving then
			break -- the next pass tries again
		end
		local store = storeFor(name)
		if not store then
			break
		end
		local value = values[name]
		local ok, err = pcall(function()
			store:SetAsync(key, value)
		end)
		if ok then
			writer.Written[name] = value
			writeFailures = 0
			noteWritten(name, player.UserId, value)
		elseif Leaderboard.isPermanent(err) then
			goOffline(err)
			break
		else
			writeFailures += 1
			writeBlockedUntil = os.clock() + Leaderboard.backoff(writeFailures, CFG.RetrySeconds, CFG.MaxBackoffSeconds)
			warn("[Leaderboards] Couldn't write " .. name .. " for " .. key .. ":", err)
			if not leaving then
				break
			end
		end
	end
	writer.Busy = false
	pendingWrites -= 1
end

local function writePass()
	local now = os.clock()
	for player, writer in writers do
		if now >= writer.NextWriteAt and not writer.Busy and player.Parent == Players then
			writer.NextWriteAt = now + CFG.WriteSeconds
			local values = collect(player)
			if values then
				task.spawn(write, player, writer, values, false)
			end
		end
	end
end

local function track(player: Player)
	if writers[player] or player.Parent ~= Players then
		return
	end
	-- Jittered, so a full server's writes don't all land in the same second.
	writers[player] = {
		Written = {},
		NextWriteAt = os.clock() + CFG.WriteSeconds * (0.5 + 0.5 * math.random()),
		Busy = false,
	}
	renderDirty = true
end

local function onLeave(player: Player)
	renderDirty = true
	local writer = writers[player]
	if not writer then
		return
	end
	-- Read the save now, before PlayerData lets it go.
	local values = collect(player)
	if values and status ~= "Offline" then
		write(player, writer, values, true)
	end
	if writers[player] == writer then
		writers[player] = nil
	end
end

------------------------------------------------------------------------------------------------------------------

local function validIds(list: any, max: number?): { string }
	local out: { string } = {}
	if type(list) ~= "table" then
		return out
	end
	for _, id in list do
		if not Leaderboard.isBoard(id) or table.find(out, id) then
			warn("[Leaderboards] Config.Leaderboards: skipping an unknown or repeated board:", id)
		elseif max == nil or #out < max then
			table.insert(out, id)
		end
	end
	return out
end

-- How many nurses the Nurse Journal has (the depth update's Data/Nurses, a keyed map like the other Data files),
-- for the Journal % board. nil until that file exists.
local function journalTotal(): number?
	local folder = Shared:FindFirstChild("Data")
	local module = folder and folder:FindFirstChild("Nurses")
	if not (module and module:IsA("ModuleScript")) then
		return nil
	end
	local ok, map = pcall(require, module)
	if not ok or type(map) ~= "table" then
		return nil
	end
	local count = 0
	for _ in map :: { [any]: any } do
		count += 1
	end
	return if count > 0 then count else nil
end

local function adminIds(): { number }
	local out: { number } = {}
	local list: any = (Config :: any).AdminUserIds
	if type(list) == "table" then
		for _, id in list do
			if type(id) == "number" then
				table.insert(out, id)
			end
		end
	end
	return out
end

function Leaderboards.start()
	boardIds = validIds(CFG.Boards)
	worldIds = validIds(CFG.WorldBoards, 4)
	for _, list in { boardIds, worldIds } do
		for _, id in list do
			if not table.find(allIds, id) then
				table.insert(allIds, id)
			end
		end
	end
	if table.find(allIds, "Journal") then
		extra.JournalTotal = journalTotal()
	end
	who = {
		Studio = RunService:IsStudio(),
		CreatorIsUser = game.CreatorType == Enum.CreatorType.User,
		CreatorId = game.CreatorId,
		UserIds = adminIds(),
	}

	local week = currentWeek()
	for _, id in allIds do
		caches[id] =
			{ Store = Leaderboard.storeName(id, week, CFG.Version), Entries = {}, Failures = 0, NextReadAt = 0 }
	end

	local ok, built = pcall(BoardBuilder.build, worldIds)
	if ok then
		gantry = built
	else
		warn("[Leaderboards] The plaza boards couldn't be built:", built)
	end
	render()

	PlayerData.Loaded:Connect(track)
	for _, player in Players:GetPlayers() do
		if PlayerData.get(player) then
			track(player)
		end
	end
	PlayerData.Changed:Connect(function()
		renderDirty = true
	end)
	Players.PlayerRemoving:Connect(onLeave)

	Remotes.GetBoards.OnServerInvoke = function(player: Player)
		if not Remotes.allow(player, "GetBoards") then
			return nil
		end
		local answered, payload = pcall(Leaderboards.payload, player)
		if not answered then
			warn("[Leaderboards] GetBoards failed:", payload)
			return nil
		end
		return payload
	end

	task.spawn(function()
		while true do
			syncWeek(currentWeek())
			writePass()
			readPass()
			if renderDirty then
				render()
			end
			task.wait(TICK_SECONDS)
		end
	end)

	game:BindToClose(function()
		if status == "Offline" then
			return
		end
		local started = os.clock()
		for player, writer in writers do
			local values = collect(player)
			if values then
				task.spawn(write, player, writer, values, true)
			end
		end
		task.wait()
		while pendingWrites > 0 and os.clock() - started < CLOSE_WAIT_SECONDS do
			task.wait(0.1)
		end
	end)
end

return Leaderboards
