--!nocheck
-- PlayerData's save order end to end (Market save safety): the real src/server/PlayerData.luau runs under Lune with a
-- mocked DataStore (it can fail, or hold a request in flight), Players, Remotes and Signal; the real Config, Schema
-- and Server/Market's Pure.leaveOut. It plays the moments a Market sale can go wrong between two saves:
--   · the seller's save fails once and the buyer leaves at once (the nurse must not end in NEITHER save)
--   · a seller autosave already in flight when the sale happens
--   · the server closing (BindToClose) with a sale, and with two players who traded both ways
--   · the seller's store staying down (then the seller keeps the nurse and the buyer the price)
--   · a seller who also bought another nurse from someone whose save never lands (its own buyers aren't held back),
--     and that same nurse sold on (it is)
-- Run from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")

local T = require("./expect")
local expect, test = T.expect, T.test

local Config = require("./config")
local Schema = require("../src/shared/Logic/Schema")

local function source(path: string): string
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("can't find " .. path .. " (run from game/)")
end

local function pureBlock(path: string): any
	local text = source(path)
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to, path .. ": no PURE block")
	local block = string.sub(text, from, to - 1) .. "\nreturn Pure\n"
	return luau.load(block, { debugName = path .. ":Pure", environment = {}, injectGlobals = true })()
end

local MarketPure = pureBlock("src/server/Market.luau")

local function clone(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[key] = clone(item)
	end
	return copy
end

-- Mocks ----------------------------------------------------------------------------------------------------------
local function mockSignal()
	local fns = {}
	return {
		Connect = function(_, fn)
			table.insert(fns, fn)
			return { Disconnect = function() end }
		end,
		Fire = function(_, ...)
			for _, fn in fns do
				task.spawn(fn, ...)
			end
		end,
	}
end

local Players = { PlayerAdded = mockSignal(), PlayerRemoving = mockSignal(), list = {} }
function Players:GetPlayers()
	return self.list
end

-- The DataStore: records by key; `fails[key]` requests still to fail; `held[key]` keeps requests in flight.
local records = {}
local fails = {}
local held = {}
local function mockStore()
	local store = {}
	function store:UpdateAsync(key, fn)
		task.wait() -- a real request always yields
		while held[key] do
			task.wait()
		end
		if (fails[key] or 0) > 0 then
			fails[key] -= 1
			error("502: the store is down")
		end
		local result = fn(clone(records[key]))
		if result ~= nil then
			records[key] = clone(result)
		end
	end
	function store:GetAsync(_key)
		task.wait()
		return nil
	end
	return store
end
local mainStore = mockStore()
local legacyStore = mockStore()

local closing: (() -> ())? = nil
local Workspace = {
	GetAttribute = function()
		return nil
	end,
}
local services = {
	Players = Players,
	Workspace = Workspace,
	DataStoreService = {
		GetDataStore = function(_, name)
			return if name == Config.DataStoreName then mainStore else legacyStore
		end,
	},
	HttpService = {
		GenerateGUID = function()
			return "this-server"
		end,
	},
	RunService = {
		IsStudio = function()
			return false
		end,
	},
	ReplicatedStorage = {
		Shared = { Config = "Config", Remotes = "Remotes", Signal = "Signal", Logic = { Schema = "Schema" } },
	},
}
local modules = {
	Config = Config,
	Remotes = { toast = function() end },
	Signal = { new = mockSignal },
	Schema = Schema,
}
local env = {
	game = {
		GetService = function(_, name)
			return assert(services[name], "no mock for the service " .. tostring(name))
		end,
		BindToClose = function(_, fn)
			closing = fn
		end,
	},
	require = function(token)
		return assert(modules[token], "no mock for " .. tostring(token))
	end,
	task = {
		spawn = task.spawn,
		defer = task.defer,
		delay = task.delay,
		-- The autosave loop sleeps for good here (the specs drive every write themselves); short waits are real.
		wait = function(seconds)
			if type(seconds) == "number" and seconds >= 30 then
				return coroutine.yield()
			end
			return task.wait(seconds)
		end,
	},
	warn = function() end, -- kept quiet: the suite's output stays PASS/FAIL
}

local PlayerData =
	luau.load(source("src/server/PlayerData.luau"), { debugName = "Server/PlayerData", environment = env })()
PlayerData.start()

-- Helpers ----------------------------------------------------------------------------------------------------------
local function settle(done: () -> boolean, seconds: number?)
	local started = os.clock()
	while not done() do
		if os.clock() - started > (seconds or 8) then
			error("timed out waiting", 2)
		end
		task.wait(0.02)
	end
end

local function keyOf(player): string
	return "player_" .. player.UserId
end

local function nurse(copies: number?)
	return { Level = 3, XP = 0, Copies = copies or 1, Job = "" }
end

local nextUserId = 5000
local function join(name: string, cash: number, nurses: any?)
	nextUserId += 1
	local leaderstats = {
		FindFirstChild = function()
			return nil
		end,
	}
	local player = { Name = name, UserId = nextUserId, Parent = Players }
	function player:FindFirstChild(child)
		return if child == "leaderstats" then leaderstats else nil
	end
	function player:SetAttribute() end
	local data = Schema.default()
	data.Cash = cash
	data.Nurses = nurses or {}
	records[keyOf(player)] = { Data = data }
	table.insert(Players.list, player)
	Players.PlayerAdded:Fire(player)
	settle(function()
		return PlayerData.get(player) ~= nil
	end)
	assert(PlayerData.canSave(player), name .. " should be saving")
	return player
end

local function leave(player)
	player.Parent = nil
	Players.PlayerRemoving:Fire(player)
end

local function gone(...): () -> boolean
	local players = { ... }
	return function()
		for _, player in players do
			if PlayerData.get(player) ~= nil then
				return false
			end
		end
		return true
	end
end

-- What the store holds for this player.
local function stored(player)
	return records[keyOf(player)].Data
end

-- A Market sale as Server/Market does it: the seller's take, the buyer's give, then writeAfter. No save yet.
local function sale(seller, buyer, nurseId: string, price: number, payout: number)
	local entry
	assert(PlayerData.update(seller, function(data)
		entry = data.Nurses[nurseId]
		data.Nurses[nurseId] = nil
		data.Cash += payout
	end))
	assert(entry, "the seller has no " .. nurseId)
	assert(PlayerData.update(buyer, function(data)
		data.Nurses[nurseId] = clone(entry)
		data.Cash -= price
	end))
	PlayerData.writeAfter(seller, buyer, MarketPure.leaveOut(nurseId, price, entry.Copies), nurseId)
end

-- How many stored saves hold this nurse.
local function owners(nurseId: string, ...): number
	local n = 0
	for _, player in { ... } do
		if stored(player).Nurses[nurseId] ~= nil then
			n += 1
		end
	end
	return n
end

-- Tests ------------------------------------------------------------------------------------------------------------
T.describe("PlayerData server (mocked store): a Market sale across two saves", function()
	test("the seller's save fails once and the buyer leaves: the buyer's last save lands the seller first", function()
		local seller = join("Seller", 500, { PuffPup = nurse() })
		local buyer = join("Buyer", 1000)
		sale(seller, buyer, "PuffPup", 300, 270)
		fails[keyOf(seller)] = 1
		expect(PlayerData.saveNow(seller)).toBe(false) -- Market's saveNow(seller): the store hiccups
		leave(buyer)
		settle(gone(buyer))
		-- the nurse is in the buyer's stored save and out of the seller's: never in neither, and no cash from nowhere
		expect(stored(buyer).Nurses.PuffPup ~= nil).toBe(true)
		expect(stored(buyer).Cash).toBe(700)
		expect(stored(seller).Nurses.PuffPup).toBeNil()
		expect(stored(seller).Cash).toBe(770)
		expect(records[keyOf(buyer)].Lock).toBeNil() -- the buyer's lock went back
		expect(records[keyOf(seller)].Lock ~= nil).toBe(true) -- the seller plays on
		leave(seller)
		settle(gone(seller))
		expect(owners("PuffPup", seller, buyer)).toBe(1)
		expect(stored(seller).Cash + stored(buyer).Cash).toBe(1500 - 30)
	end)

	test(
		"a seller autosave already in flight at the sale: the buyer's last save waits, then lands the seller",
		function()
			local seller = join("Seller", 500, { PuffPup = nurse() })
			local buyer = join("Buyer", 1000)
			held[keyOf(seller)] = true
			task.spawn(PlayerData.saveNow, seller) -- its snapshot is from BEFORE the sale, and the request hangs
			task.wait(0.05)
			sale(seller, buyer, "PuffPup", 300, 270)
			leave(buyer)
			task.wait(0.2)
			expect(PlayerData.get(buyer) ~= nil).toBe(true) -- still waiting: nothing of the buyer's is written yet
			held[keyOf(seller)] = nil
			settle(gone(buyer))
			expect(stored(buyer).Nurses.PuffPup ~= nil).toBe(true)
			expect(stored(buyer).Cash).toBe(700)
			expect(stored(seller).Nurses.PuffPup).toBeNil()
			expect(stored(seller).Cash).toBe(770)
			leave(seller)
			settle(gone(seller))
		end
	)

	test("the seller's store stays down: the seller keeps the nurse and the buyer the price", function()
		local seller = join("Seller", 500, { PuffPup = nurse() })
		local buyer = join("Buyer", 1000)
		sale(seller, buyer, "PuffPup", 300, 270)
		fails[keyOf(seller)] = 100
		leave(buyer)
		settle(gone(buyer))
		expect(stored(buyer).Nurses.PuffPup).toBeNil()
		expect(stored(buyer).Cash).toBe(1000)
		expect(stored(seller).Nurses.PuffPup ~= nil).toBe(true)
		expect(stored(seller).Cash).toBe(500)
		expect(owners("PuffPup", seller, buyer)).toBe(1)
		leave(seller) -- its leave-save gives up too: the stored saves stay as they are
		settle(gone(seller), 20)
		fails[keyOf(seller)] = nil
		expect(owners("PuffPup", seller, buyer)).toBe(1)
		expect(stored(seller).Cash + stored(buyer).Cash).toBe(1500)
	end)

	test("the server closes right after a sale: sellers are saved before their buyers", function()
		local seller = join("Seller", 500, { PuffPup = nurse() })
		local buyer = join("Buyer", 1000)
		sale(seller, buyer, "PuffPup", 300, 270)
		fails[keyOf(seller)] = 1
		expect(PlayerData.saveNow(seller)).toBe(false)
		task.spawn(assert(closing, "BindToClose was never set"))
		settle(gone(seller, buyer))
		expect(stored(buyer).Nurses.PuffPup ~= nil).toBe(true)
		expect(stored(seller).Nurses.PuffPup).toBeNil()
		expect(stored(seller).Cash + stored(buyer).Cash).toBe(1500 - 30)
		expect(records[keyOf(seller)].Lock).toBeNil()
		expect(records[keyOf(buyer)].Lock).toBeNil()
		Players.list = {}
	end)

	test("two players who traded both ways, and the server closes: each nurse ends in exactly one save", function()
		local a = join("A", 1000, { PuffPup = nurse() })
		local b = join("B", 1000, { MintMouse = nurse() })
		sale(a, b, "PuffPup", 300, 270)
		sale(b, a, "MintMouse", 200, 180)
		task.spawn(assert(closing))
		settle(gone(a, b))
		expect(stored(a).Nurses.PuffPup).toBeNil()
		expect(stored(b).Nurses.PuffPup ~= nil).toBe(true)
		expect(stored(b).Nurses.MintMouse).toBeNil()
		expect(stored(a).Nurses.MintMouse ~= nil).toBe(true)
		expect(stored(a).Cash).toBe(1000 + 270 - 200)
		expect(stored(b).Cash).toBe(1000 - 300 + 180)
	end)

	test("both leave in the same frame after trading both ways: nobody waits for ever, nothing is lost", function()
		local a = join("A", 1000, { PuffPup = nurse() })
		local b = join("B", 1000, { MintMouse = nurse() })
		sale(a, b, "PuffPup", 300, 270)
		sale(b, a, "MintMouse", 200, 180)
		leave(a)
		leave(b)
		settle(gone(a, b), 5)
		expect(owners("PuffPup", a, b)).toBe(1)
		expect(owners("MintMouse", a, b)).toBe(1)
		expect(stored(b).Nurses.PuffPup ~= nil).toBe(true)
		expect(stored(a).Nurses.MintMouse ~= nil).toBe(true)
	end)

	test("a seller who bought ANOTHER nurse from a save that never lands doesn't hold its own buyers back", function()
		local t = join("T", 0, { BeanBear = nurse() })
		local s = join("S", 1000, { PuffPup = nurse() })
		local b = join("B", 1000)
		sale(t, s, "BeanBear", 100, 90) -- S bought BeanBear from T...
		records[keyOf(t)].Lock.Owner = "another-server" -- ...whose lock is lost: T's write never lands
		expect(PlayerData.saveNow(t)).toBe(false)
		sale(s, b, "PuffPup", 300, 270) -- then S sold its own PuffPup to B
		expect(PlayerData.saveNow(s)).toBe(true) -- BeanBear left out of it, the PuffPup take in it
		expect(stored(s).Nurses.BeanBear).toBeNil()
		expect(stored(s).Nurses.PuffPup).toBeNil()
		expect(stored(s).Cash).toBe(1000 + 270) -- the BeanBear price back: T's stored save still has it
		expect(PlayerData.saveNow(b)).toBe(true)
		expect(stored(b).Nurses.PuffPup ~= nil).toBe(true) -- not left out all session
		expect(stored(b).Cash).toBe(700)
		expect(owners("PuffPup", t, s, b)).toBe(1)
		expect(owners("BeanBear", t, s, b)).toBe(1)
		expect(stored(t).Nurses.BeanBear ~= nil).toBe(true)

		-- The same nurse sold on is still held back (T's stored save has it: it may be in no other).
		local c = join("C", 1000)
		sale(s, c, "BeanBear", 100, 90)
		expect(PlayerData.saveNow(s)).toBe(true)
		expect(PlayerData.saveNow(c)).toBe(true)
		expect(stored(c).Nurses.BeanBear).toBeNil()
		expect(stored(c).Cash).toBe(1000)
		expect(owners("BeanBear", t, s, b, c)).toBe(1)
		leave(c)
		leave(b)
		leave(s)
		leave(t)
		settle(gone(t, s, b, c))
		expect(owners("BeanBear", t, s, b, c)).toBe(1)
		expect(owners("PuffPup", t, s, b, c)).toBe(1)
	end)
end)
