--!nocheck
-- The Player Market end to end (Progression v2 T4, build plan §B3.2, Review focus 1): the real src/server/Market.luau
-- runs under Lune with mocked Roblox services (Players, Remotes, PlayerData, Nurses; the real Config, Logic/Market,
-- Data/Nurses and Schema). Nurses' take/give follow their §B8 contract (ONE update each) against the mocked saves.
-- It checks what a cheating client or an unlucky moment would poke at: junk arguments, out-of-band prices, someone
-- else's listing, two buyers in one frame (also one arriving from inside the first transfer), the seller leaving,
-- a stale price, owning one already, a full roster, the buyer's update failing (the seller is restored and no cash
-- appears or vanishes), the save order. Plus the PURE blocks of Server/Market and UI/MarketPanel. Run from game/
-- with the rest:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")

local T = require("./expect")
local expect, test = T.expect, T.test

local Config = require("./config")
local MarketLogic = require("../src/shared/Logic/Market")
local NursesData = require("../src/shared/Data/Nurses")
local Schema = require("../src/shared/Logic/Schema")

local function source(path: string): string
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("can't find " .. path .. " (run from game/)")
end

local function pureBlock(path: string, env: { [string]: any }): any
	local text = source(path)
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to, path .. ": no PURE block")
	local block = string.sub(text, from, to - 1) .. "\nreturn Pure\n"
	return luau.load(block, { debugName = path .. ":Pure", environment = env, injectGlobals = true })()
end

local function words(text: string): number
	local n = 0
	for _ in string.gmatch(text, "%S+") do
		n += 1
	end
	return n
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
				fn(...) -- synchronous, like Shared/Signal's task.spawn up to the first yield
			end
		end,
	}
end

local Players = { PlayerAdded = mockSignal(), PlayerRemoving = mockSignal(), list = {} }
function Players:GetPlayers()
	return self.list
end

local nextUserId = 1000
local function newPlayer(name: string)
	nextUserId += 1
	local p = { __instance = true, Name = name, DisplayName = name .. "Kid", UserId = nextUserId, Parent = Players }
	function p:IsA(class)
		return class == "Player"
	end
	table.insert(Players.list, p)
	return p
end

local warnings: { string } = {}
local served = {}
local toasts = {}
local newsAll = 0
local newsTo = {}
local celebrations = {}
local Remotes = {
	OOPS = "Oops! Try again.",
	TOO_FAST = "Too fast! Try again.",
	serve = function(name, handler)
		served[name] = handler
	end,
	toast = function(player, text)
		table.insert(toasts, { Player = player, Text = text })
	end,
	MarketNews = {
		FireAllClients = function(_, _view)
			newsAll += 1
		end,
		FireClient = function(_, player, view)
			table.insert(newsTo, { Player = player, View = view })
		end,
	},
	Celebrate = {
		FireClient = function(_, player, info)
			table.insert(celebrations, { Player = player, Info = info })
		end,
	},
}

local saves = {}
local closed = {} -- [player] = true: the session is closing (isOpen false, update refused)
local notSaving = {}
local saveFails = {}
local saveLog: { string } = {}
local PlayerData = {
	Changed = mockSignal(),
}
function PlayerData.get(player)
	return saves[player]
end
function PlayerData.update(player, fn)
	if not saves[player] or closed[player] then
		return false
	end
	fn(saves[player])
	PlayerData.Changed:Fire(player, saves[player])
	return true
end
function PlayerData.isOpen(player)
	return saves[player] ~= nil and not closed[player] and player.Parent == Players
end
function PlayerData.canSave(player)
	return saves[player] ~= nil and not notSaving[player]
end
function PlayerData.saveNow(player)
	table.insert(saveLog, player.Name)
	return not saveFails[player]
end
local afterLog: { string } = {}
local afterLeaveOut = {} -- the leaveOut function of each writeAfter, in order
function PlayerData.writeAfter(first, second, leaveOut)
	table.insert(afterLog, first.Name .. ">" .. second.Name)
	table.insert(afterLeaveOut, leaveOut)
end

-- Nurses: take/give/setListed/isListed as §B8 says (ONE update each).
local locks = {}
local failGive = {}
local errorAfter = {} -- [player] = true: their next take/give errors AFTER its update landed (a bug in a follow-up)
local takeHook: (() -> ())? = nil
local Nurses = {}
function Nurses.setListed(player, nurseId, listingId)
	locks[player] = locks[player] or {}
	locks[player][nurseId] = listingId
end
function Nurses.isListed(player, nurseId)
	return locks[player] ~= nil and locks[player][nurseId] ~= nil
end
function Nurses.take(player, nurseId, cash, reason)
	local hook = takeHook
	if hook then
		takeHook = nil
		hook() -- someone else's call arriving "inside" this one (a synchronous signal handler)
	end
	local data = saves[player]
	if not data or type(data.Nurses[nurseId]) ~= "table" then
		return false, "Oops! Try again."
	end
	if Nurses.isListed(player, nurseId) and reason ~= "Market" then
		return false, "Unlist it first"
	end
	if rawget(NursesData, nurseId).Source ~= nil then
		return false, "This one stays with you!"
	end
	local removed
	local ok = PlayerData.update(player, function(d)
		removed = d.Nurses[nurseId]
		d.Nurses[nurseId] = nil
		d.Cash += cash
	end)
	if not ok then
		return false, "Oops! Try again."
	end
	if locks[player] then
		locks[player][nurseId] = nil
	end
	if errorAfter[player] then
		errorAfter[player] = nil
		error("a follow-up after the take's update broke")
	end
	return true, "", removed
end
local undoCalls = {} -- every give with undo = true: { Player, NurseId }
local endedUndo = {} -- every endUndo: { Player, NurseId }
function Nurses.endUndo(player, nurseId)
	table.insert(endedUndo, { Player = player, NurseId = nurseId })
end
function Nurses.give(player, nurseId, entry, price, undo)
	if undo == true then
		table.insert(undoCalls, { Player = player, NurseId = nurseId })
	end
	local data = saves[player]
	if failGive[player] or not data or data.Cash < price or data.Nurses[nurseId] ~= nil then
		return false, "Oops! Try again."
	end
	local ok = PlayerData.update(player, function(d)
		d.Cash -= price
		d.Nurses[nurseId] = { Level = entry.Level, XP = entry.XP, Copies = entry.Copies, Job = "" }
		d.NurseIndex[nurseId] = "Hired"
	end)
	if ok and errorAfter[player] then
		errorAfter[player] = nil
		error("a follow-up after the give's update broke")
	end
	return ok, if ok then "" else "Oops! Try again."
end

local now = 100
local fakeOs = setmetatable({
	clock = function()
		return now
	end,
}, { __index = os })
local delayed: { () -> () } = {}
local fakeTask = {
	delay = function(_seconds, fn, ...)
		local args = table.pack(...)
		table.insert(delayed, function()
			fn(table.unpack(args, 1, args.n))
		end)
	end,
	spawn = function(fn, ...)
		fn(...)
	end,
	defer = function(fn, ...)
		fn(...)
	end,
	wait = task.wait,
}
local function flush()
	local list = delayed
	delayed = {}
	for _, fn in list do
		fn()
	end
end

local sold = {}
local Signal = {
	new = function()
		local signal = mockSignal()
		return signal
	end,
}

local Shared = {
	Config = "Config",
	Palette = "Palette",
	Remotes = "Remotes",
	Signal = "Signal",
	Types = "Types",
	Logic = { Market = "MarketLogic" },
	Data = { Nurses = "NursesData" },
}
local modules = {
	Config = Config,
	Palette = {},
	Remotes = Remotes,
	Signal = Signal,
	Types = {},
	MarketLogic = MarketLogic,
	NursesData = NursesData,
	Nurses = Nurses,
	PlayerData = PlayerData,
}
local Workspace = {
	FindFirstChild = function()
		return nil
	end,
}
local ServerStorage = {
	FindFirstChild = function()
		return nil
	end,
}
local env = {
	game = {
		GetService = function(_, name)
			if name == "Players" then
				return Players
			elseif name == "Workspace" then
				return Workspace
			elseif name == "ServerStorage" then
				return ServerStorage
			end
			return { Shared = Shared }
		end,
	},
	script = { Parent = { Nurses = "Nurses", PlayerData = "PlayerData" } },
	require = function(token)
		return assert(modules[token], "no mock for " .. tostring(token))
	end,
	typeof = function(v)
		if type(v) == "table" and v.__instance then
			return "Instance"
		end
		return typeof(v)
	end,
	task = fakeTask,
	os = fakeOs,
	warn = function(...)
		local parts = {}
		for _, part in { ... } do
			table.insert(parts, tostring(part))
		end
		table.insert(warnings, table.concat(parts, " ")) -- kept quiet: the suite's output stays PASS/FAIL
	end,
}

local Market = luau.load(source("src/server/Market.luau"), { debugName = "Server/Market", environment = env })()
Market.start() -- the kiosk can't build without Roblox (it warns); the remotes and listeners are wired
Market.Sold:Connect(function(listing, buyer)
	table.insert(sold, { Listing = listing, Buyer = buyer })
end)
local GetMarket, ListNurse, Unlist, BuyListing = served.GetMarket, served.ListNurse, served.Unlist, served.BuyListing

-- Helpers ----------------------------------------------------------------------------------------------------------
local function save(player, fields)
	local data = Schema.default()
	data.Tutorial = 9
	data.Level = 3
	data.Cash = 0
	for key, value in fields or {} do
		data[key] = value
	end
	saves[player] = data
	return data
end

local function nurse(level, xp, copies, job)
	return { Level = level or 1, XP = xp or 0, Copies = copies or 1, Job = job or "" }
end

local function later(seconds)
	now += seconds or 10
end

local function listingsOf(userId)
	local found = {}
	for _, listing in Market.view().Listings do
		if listing.Seller == userId then
			table.insert(found, listing)
		end
	end
	return found
end

local function clone(t)
	if type(t) ~= "table" then
		return t
	end
	local copy = {}
	for k, v in t do
		copy[k] = clone(v)
	end
	return copy
end

local function leave(player)
	player.Parent = nil
	Players.PlayerRemoving:Fire(player)
	saves[player] = nil
end

-- A seller with a Common Lv 3 nurse listed at a price, and a buyer with cash. Returns (seller, buyer, id).
local function market(price, buyerCash, entry)
	local seller, buyer = newPlayer("Seller"), newPlayer("Buyer")
	save(seller, { Cash = 500, Nurses = { PuffPup = entry or nurse(3, 7, 2, "Healer") } })
	save(buyer, { Cash = buyerCash or 1000 })
	later()
	local ok, message = ListNurse(seller, "PuffPup", price)
	assert(ok, "listing failed: " .. tostring(message))
	local mine = listingsOf(seller.UserId)
	return seller, buyer, mine[#mine].Id
end

-- Tests ------------------------------------------------------------------------------------------------------------
T.describe("compile", function()
	for _, path in { "src/server/Market.luau", "src/client/UI/MarketPanel.luau" } do
		test(path, function()
			local ok, err = pcall(luau.compile, source(path))
			if not ok then
				error(err)
			end
		end)
	end
end)

local SP = pureBlock("src/server/Market.luau", {})

T.describe("Market.Pure (server)", function()
	test("ids and prices from a client: whole, finite, in range", function()
		for _, junk in { 0, -1, 1.5, 0 / 0, math.huge, -math.huge, "1", true, {}, 2 ^ 31 } do
			expect(SP.idOk(junk)).toBe(false)
		end
		expect(SP.idOk(1)).toBe(true)
		expect(SP.idOk(2 ^ 31 - 1)).toBe(true)
		expect(SP.whole(0 / 0)).toBe(false)
		expect(SP.whole(math.huge)).toBe(false)
		expect(SP.whole(-3)).toBe(true)
		for _, junk in { "", string.rep("x", 41), 1, nil, {} } do
			expect(SP.nurseIdOk(junk)).toBe(false)
		end
		expect(SP.nurseIdOk("PuffPup")).toBe(true)
	end)

	test("cooldowns", function()
		expect(SP.ready(nil, 10, 5)).toBe(true)
		expect(SP.ready(10, 14.9, 5)).toBe(false)
		expect(SP.ready(10, 15, 5)).toBe(true)
	end)

	test("the view: public fields only, oldest first, the fee in percent", function()
		local player = { secret = true }
		local view = SP.view({
			[7] = {
				Id = 7,
				Seller = 2,
				SellerName = "B",
				NurseId = "MintMouse",
				Rarity = "Common",
				Level = 2,
				Price = 90,
				Player = player,
			},
			[3] = {
				Id = 3,
				Seller = 1,
				SellerName = "A",
				NurseId = "PuffPup",
				Rarity = "Common",
				Level = 1,
				Price = 50,
				Player = player,
			},
		}, Config)
		expect(view.FeePercent).toBe(10)
		expect(view.MaxPerSeller).toBe(3)
		expect(#view.Listings).toBe(2)
		expect(view.Listings[1]).toEqual({
			Id = 3,
			Seller = 1,
			SellerName = "A",
			NurseId = "PuffPup",
			Rarity = "Common",
			Level = 1,
			Price = 50,
		})
		expect(view.Listings[2].Id).toBe(7)
		expect(view.Listings[2].Player).toBeNil()
	end)

	test("count and find", function()
		local listings = {
			[1] = { Id = 1, Seller = 5, NurseId = "PuffPup" },
			[2] = { Id = 2, Seller = 6, NurseId = "PuffPup" },
			[4] = { Id = 4, Seller = 5, NurseId = "MintMouse" },
		}
		local mine, total = SP.count(listings, 5)
		expect(mine).toBe(2)
		expect(total).toBe(3)
		expect(SP.find(listings, 5, "MintMouse")).toBe(4)
		expect(SP.find(listings, 6, "MintMouse")).toBeNil()
	end)

	test("entryCopy: whole numbers, Job reset, junk made safe", function()
		expect(SP.entryCopy({ Level = 7, XP = 12, Copies = 3, Job = "Porter" })).toEqual({
			Level = 7,
			XP = 12,
			Copies = 3,
			Job = "",
		})
		expect(SP.entryCopy({ Level = 0 / 0, XP = -5, Copies = "x" })).toEqual({
			Level = 1,
			XP = 0,
			Copies = 1,
			Job = "",
		})
		expect(SP.entryCopy(nil)).toEqual({ Level = 1, XP = 0, Copies = 1, Job = "" })
	end)

	test("messages stay at 6 words or fewer", function()
		expect(SP.bandText(50, 300)).toBe("Pick 💰50 to 💰300")
		expect(SP.soldText("🐶", 1350)).toBe("💰 Sold 🐶! +💰1,350")
		for _, text in { SP.bandText(25000, 150000), SP.soldText("🐶", 270) } do
			expect(words(text) <= 6).toBe(true)
		end
	end)
end)

T.describe("Market server (mocked)", function()
	test("start serves the four remotes; GetMarket answers the view", function()
		expect(type(GetMarket)).toBe("function")
		expect(type(ListNurse)).toBe("function")
		expect(type(Unlist)).toBe("function")
		expect(type(BuyListing)).toBe("function")
		local ok, message, view = GetMarket(newPlayer("Viewer"))
		expect(ok).toBe(true)
		expect(message).toBe("")
		expect(view.FeePercent).toBe(10)
		expect(view.MaxPerSeller).toBe(3)
		expect(type(view.Listings)).toBe("table")
	end)

	test("junk ListNurse arguments are refused and change nothing", function()
		local p = newPlayer("Junk")
		local data = save(p, { Cash = 100, Nurses = { PuffPup = nurse(1) } })
		local before = clone(data)
		for _, args in
			{
				{ nil, 100 },
				{ 1, 100 },
				{ "PuffPup", "100" },
				{ "PuffPup", nil },
				{ "Order", 100 },
				{ "NotANurse", 100 },
				{ string.rep("P", 200), 100 },
				{ {}, 100 },
			}
		do
			later()
			local ok, message = ListNurse(p, args[1], args[2])
			expect(ok).toBe(false)
			expect(type(message)).toBe("string")
		end
		expect(data).toEqual(before)
		expect(#listingsOf(p.UserId)).toBe(0)
		expect(Nurses.isListed(p, "PuffPup")).toBe(false)
	end)

	test("you can only list a nurse you own, never the rebirth-only one", function()
		local p = newPlayer("Owner")
		save(p, { Cash = 0, Nurses = { PuffPup = nurse(1), FounderFennec = nurse(1) } })
		later()
		local ok, message = ListNurse(p, "MintMouse", 100)
		expect(ok).toBe(false)
		expect(message).toBe("Hire it first!")
		later()
		ok, message = ListNurse(p, "FounderFennec", 6000)
		expect(ok).toBe(false)
		expect(message).toBe("This one stays with you!")
		expect(#listingsOf(p.UserId)).toBe(0)
	end)

	test("out-of-band, non-whole and junk prices are refused; inside the band works", function()
		local p = newPlayer("Bander")
		save(p, { Nurses = { PuffPup = nurse(3) } }) -- Common Lv 3: x1.2 -> 60..360
		local min, max = MarketLogic.band(Config, "Common", 3)
		expect(min).toBe(60)
		expect(max).toBe(360)
		for _, price in { 1, 59, 361, 1e9, 100.5, 0 / 0, math.huge, -100 } do
			later()
			local ok, message = ListNurse(p, "PuffPup", price)
			expect(ok).toBe(false)
			expect(message).toBe("Pick 💰60 to 💰360")
		end
		expect(#listingsOf(p.UserId)).toBe(0)
		later()
		local ok, message = ListNurse(p, "PuffPup", 360)
		expect(ok).toBe(true)
		expect(message).toBe("🏷️ Listed for 💰360!")
		local mine = listingsOf(p.UserId)
		expect(#mine).toBe(1)
		expect(mine[1].Price).toBe(360)
		expect(mine[1].Level).toBe(3)
		expect(mine[1].SellerName).toBe("BanderKid")
		expect(mine[1].Rarity).toBe("Common")
		expect(Nurses.isListed(p, "PuffPup")).toBe(true)
	end)

	test("a nurse is listed once; a resting nurse may be listed; 3 per seller", function()
		local p = newPlayer("Lister")
		save(p, {
			Nurses = {
				PuffPup = nurse(1),
				MintMouse = nurse(1),
				BeanBear = nurse(1),
				DewDuck = nurse(1, 0, 1, "Rest"),
			},
		})
		later()
		expect((ListNurse(p, "PuffPup", 100))).toBe(true)
		later()
		local ok, message = ListNurse(p, "PuffPup", 120)
		expect(ok).toBe(false)
		expect(message).toBe("Already listed!")
		later()
		ok = ListNurse(p, "DewDuck", 100) -- resting: listing it is how a full roster makes room
		expect(ok).toBe(true)
		later()
		expect((ListNurse(p, "MintMouse", 100))).toBe(true)
		later()
		ok, message = ListNurse(p, "BeanBear", 100)
		expect(ok).toBe(false)
		expect(message).toBe("3 listings max!")
		expect(#listingsOf(p.UserId)).toBe(3)
	end)

	test("listing waits 5 s per player and needs a saving session", function()
		local p = newPlayer("Quick")
		save(p, { Nurses = { PuffPup = nurse(1), MintMouse = nurse(1) } })
		later()
		expect((ListNurse(p, "PuffPup", 100))).toBe(true)
		later(4.9)
		local ok, message = ListNurse(p, "MintMouse", 100)
		expect(ok).toBe(false)
		expect(message).toBe("Too fast! Try again.")
		local q = newPlayer("NoSave")
		save(q, { Nurses = { PuffPup = nurse(1) } })
		notSaving[q] = true
		later()
		ok, message = ListNurse(q, "PuffPup", 100)
		expect(ok).toBe(false)
		expect(message).toBe("⚠️ Saving is off")
		expect(#listingsOf(q.UserId)).toBe(0)
	end)

	test("unlist: your own only; junk refused; the lock is freed", function()
		local seller, other, id = market(100)
		local ok, message = Unlist(other, id)
		expect(ok).toBe(false)
		expect(message).toBe("That's not yours!")
		for _, junk in { -1, 0, 1.5, "1", nil, 0 / 0 } do
			ok = Unlist(seller, junk)
			expect(ok).toBe(false)
		end
		expect(#listingsOf(seller.UserId)).toBe(1)
		ok, message = Unlist(seller, id)
		expect(ok).toBe(true)
		expect(message).toBe("📦 Unlisted!")
		expect(#listingsOf(seller.UserId)).toBe(0)
		expect(Nurses.isListed(seller, "PuffPup")).toBe(false)
		ok, message = Unlist(seller, id)
		expect(ok).toBe(false)
		expect(message).toBe("Not listed now!")
	end)

	test("a buy moves the exact nurse, charges the price and pays price - 10%", function()
		local seller, buyer, id = market(300)
		local cashBefore = saves[seller].Cash + saves[buyer].Cash
		saveLog = {}
		celebrations = {}
		toasts = {}
		sold = {}
		local ok, message = BuyListing(buyer, id, 300)
		expect(ok).toBe(true)
		expect(message).toBe("🎉 Puff Pup is yours!")
		expect(saves[buyer].Nurses.PuffPup).toEqual({ Level = 3, XP = 7, Copies = 2, Job = "" })
		expect(saves[seller].Nurses.PuffPup).toBeNil()
		expect(saves[buyer].Cash).toBe(700)
		expect(saves[seller].Cash).toBe(500 + 270)
		local fee = MarketLogic.fee(300, Config)
		expect(fee).toBe(30)
		expect(cashBefore).toBe(saves[seller].Cash + saves[buyer].Cash + fee) -- the fee is the only cash that goes
		expect(#listingsOf(seller.UserId)).toBe(0)
		expect(Nurses.isListed(seller, "PuffPup")).toBe(false)
		expect(saveLog).toEqual({ "Seller", "Buyer" }) -- seller first
		expect(#celebrations).toBe(0) -- Nurses.give celebrates the new nurse (once); Market never doubles it
		expect(toasts[#toasts].Player).toBe(seller)
		expect(toasts[#toasts].Text).toBe("💰 Sold " .. NursesData.PuffPup.Icon .. "! +💰270")
		expect(#sold).toBe(1)
		expect(sold[1].Buyer).toBe(buyer)
		expect(sold[1].Listing.Id).toBe(id)
	end)

	test("two buyers in one frame: one nurse moves, the other is told to look again", function()
		local seller, a, id = market(200)
		local b = newPlayer("Buyer2")
		save(b, { Cash = 1000 })
		local okA = BuyListing(a, id, 200)
		local okB, messageB = BuyListing(b, id, 200)
		expect(okA).toBe(true)
		expect(okB).toBe(false)
		expect(messageB).toBe("Price changed! Look again")
		expect(saves[a].Nurses.PuffPup ~= nil).toBe(true)
		expect(saves[b].Nurses.PuffPup).toBeNil()
		expect(saves[b].Cash).toBe(1000)
		expect(saves[seller].Nurses.PuffPup).toBeNil()
		expect(newsTo[#newsTo].Player).toBe(b) -- b's panel gets the fresh view
	end)

	test("a second buyer arriving from inside the first transfer finds nothing", function()
		local seller, a, id = market(200)
		local b = newPlayer("Sneaky")
		save(b, { Cash = 1000 })
		local inner
		takeHook = function()
			inner = { BuyListing(b, id, 200) }
		end
		local ok = BuyListing(a, id, 200)
		expect(ok).toBe(true)
		expect(inner[1]).toBe(false)
		expect(inner[2]).toBe("Price changed! Look again")
		local owners = 0
		for _, player in { seller, a, b } do
			if saves[player].Nurses.PuffPup then
				owners += 1
			end
		end
		expect(owners).toBe(1)
		expect(saves[b].Cash).toBe(1000)
	end)

	test("the seller leaves before the buy: the listing goes with them", function()
		local seller, buyer, id = market(150)
		local buyerBefore = clone(saves[buyer])
		leave(seller)
		expect(#listingsOf(seller.UserId)).toBe(0)
		local ok, message = BuyListing(buyer, id, 150)
		expect(ok).toBe(false)
		expect(message).toBe("Price changed! Look again")
		expect(saves[buyer]).toEqual(buyerBefore)
	end)

	test("a seller already gone (no PlayerRemoving yet) or closing can't be bought from", function()
		local seller, buyer, id = market(150)
		local sellerBefore, buyerBefore = clone(saves[seller]), clone(saves[buyer])
		seller.Parent = nil
		local ok, message = BuyListing(buyer, id, 150)
		expect(ok).toBe(false)
		expect(message).toBe("Seller left! Look again")
		expect(saves[seller]).toEqual(sellerBefore)
		expect(saves[buyer]).toEqual(buyerBefore)
		expect(#listingsOf(seller.UserId)).toBe(0)

		local seller2, buyer2, id2 = market(150)
		closed[seller2] = true
		ok, message = BuyListing(buyer2, id2, 150)
		expect(ok).toBe(false)
		expect(message).toBe("Seller left! Look again")
		expect(saves[seller2].Nurses.PuffPup ~= nil).toBe(true)
	end)

	test("a changed or stale price is refused; the listing stays", function()
		local seller, buyer, id = market(250)
		local before = clone(saves[buyer])
		for _, price in { 249, 251, 0, 25, 0 / 0 } do
			later()
			local ok, message = BuyListing(buyer, id, price)
			expect(ok).toBe(false)
			expect(message).toBe("Price changed! Look again")
		end
		expect(saves[buyer]).toEqual(before)
		expect(#listingsOf(seller.UserId)).toBe(1)
		expect(saves[seller].Nurses.PuffPup ~= nil).toBe(true)
	end)

	test("junk BuyListing arguments are refused and change nothing", function()
		local seller, buyer, id = market(100)
		local sellerBefore, buyerBefore = clone(saves[seller]), clone(saves[buyer])
		for _, args in
			{
				{ -1, 0 },
				{ "1", 100 },
				{ 1.5, 100 },
				{ 0 / 0, 100 },
				{ id, "100" },
				{ id, nil },
				{ nil, nil },
				{ 999999, 100 },
			}
		do
			later()
			local ok = BuyListing(buyer, args[1], args[2])
			expect(ok).toBe(false)
		end
		expect(saves[seller]).toEqual(sellerBefore)
		expect(saves[buyer]).toEqual(buyerBefore)
		expect(#listingsOf(seller.UserId)).toBe(1)
	end)

	test("buying your own listing is refused", function()
		local seller, _, id = market(100)
		local ok, message = BuyListing(seller, id, 100)
		expect(ok).toBe(false)
		expect(message).toBe("That's yours!")
	end)

	test("a buyer who owns that nurse is refused", function()
		local seller, buyer, id = market(100)
		saves[buyer].Nurses.PuffPup = nurse(1)
		local ok, message = BuyListing(buyer, id, 100)
		expect(ok).toBe(false)
		expect(message).toBe("You have one!")
		expect(saves[seller].Nurses.PuffPup.Level).toBe(3)
	end)

	test("a full roster is refused (resting nurses count)", function()
		local _, buyer, id = market(100)
		saves[buyer].Nurses = { MintMouse = nurse(1), BeanBear = nurse(1), DewDuck = nurse(1, 0, 1, "Rest") }
		local ok, message = BuyListing(buyer, id, 100)
		expect(ok).toBe(false)
		expect(message).toBe("Roster full: sell or list one")
		expect(saves[buyer].Cash).toBe(1000)
	end)

	test("not enough cash, the level gate and the rebirth gate are refused", function()
		local _, buyer, id = market(300, 299)
		local ok, message = BuyListing(buyer, id, 300)
		expect(ok).toBe(false)
		expect(message).toBe("Need 💰300")

		local seller = newPlayer("EpicSeller")
		save(seller, {
			Level = 3,
			Nurses = { CloudKoala = nurse(1), MoonpuffDrake = nurse(1) },
			Rebirth = {
				Count = 1,
				Points = 0,
				Tree = {},
				Perks = {},
				Offer = {},
				Theme = "",
				Pending = {},
				Told = false,
			},
		})
		later()
		expect((ListNurse(seller, "CloudKoala", 1500))).toBe(true)
		later()
		expect((ListNurse(seller, "MoonpuffDrake", 20000))).toBe(true)
		local epic, mythic
		for _, listing in listingsOf(seller.UserId) do
			if listing.NurseId == "CloudKoala" then
				epic = listing.Id
			else
				mythic = listing.Id
			end
		end
		local low = newPlayer("LowLevel")
		save(low, { Level = 2, Cash = 100000 })
		ok, message = BuyListing(low, epic, 1500)
		expect(ok).toBe(false)
		expect(message).toBe("🏥 Lv 3")
		local r0 = newPlayer("NoBranch")
		save(r0, { Level = 5, Cash = 100000 })
		ok, message = BuyListing(r0, mythic, 20000)
		expect(ok).toBe(false)
		expect(message).toBe("🏢 R1")
		expect(saves[low].Cash).toBe(100000)
		expect(saves[r0].Cash).toBe(100000)
	end)

	test("a buyer not saving can't buy", function()
		local _, buyer, id = market(100)
		notSaving[buyer] = true
		local ok, message = BuyListing(buyer, id, 100)
		expect(ok).toBe(false)
		expect(message).toBe("⚠️ Saving is off")
		notSaving[buyer] = nil
	end)

	test("the buyer's update failing restores the seller; no cash appears or vanishes", function()
		local seller, buyer, id = market(300)
		local sellerBefore, buyerBefore = clone(saves[seller]), clone(saves[buyer])
		failGive[buyer] = true
		saveLog = {}
		local ok, message = BuyListing(buyer, id, 300)
		failGive[buyer] = nil
		expect(ok).toBe(false)
		expect(message).toBe("Oops! Try again.")
		expect(saves[seller].Nurses.PuffPup).toEqual({ Level = 3, XP = 7, Copies = 2, Job = "" })
		expect(saves[seller].Cash).toBe(sellerBefore.Cash)
		expect(saves[buyer]).toEqual(buyerBefore)
		expect(saves[seller].Cash + saves[buyer].Cash).toBe(sellerBefore.Cash + buyerBefore.Cash)
		expect(#saveLog).toBe(0)
		expect(#listingsOf(seller.UserId)).toBe(0) -- the listing ended; the seller can list it again
		expect(Nurses.isListed(seller, "PuffPup")).toBe(false)
		-- the undo is explicit (give's undo = true, to the seller only), and its token ends before buy returns
		expect(undoCalls[#undoCalls].Player).toBe(seller)
		expect(undoCalls[#undoCalls].NurseId).toBe("PuffPup")
		expect(endedUndo[#endedUndo].Player).toBe(seller)
	end)

	test("a sale: the buyer's give is never an undo, and the take's undo token ends at once", function()
		local seller, buyer, id = market(300)
		local undosBefore, endedBefore = #undoCalls, #endedUndo
		expect((BuyListing(buyer, id, 300))).toBe(true)
		expect(#undoCalls).toBe(undosBefore)
		expect(#endedUndo).toBe(endedBefore + 1)
		expect(endedUndo[#endedUndo].Player).toBe(seller)
	end)

	test("writeAfter gets the sale's leaveOut: the nurse out and the price back, on a copy only", function()
		local _, buyer, id = market(300)
		afterLeaveOut = {}
		expect((BuyListing(buyer, id, 300))).toBe(true)
		local leaveOut = afterLeaveOut[1]
		expect(type(leaveOut)).toBe("function")
		local copy = clone(saves[buyer])
		leaveOut(copy)
		expect(copy.Nurses.PuffPup).toBeNil()
		expect(copy.Cash).toBe(saves[buyer].Cash + 300)
		expect(saves[buyer].Nurses.PuffPup ~= nil).toBe(true) -- the live save is untouched
		-- the pure helper on its own: junk is ignored
		local fn = SP.leaveOut("MintMouse", 50)
		fn(nil)
		local bare = {}
		fn(bare)
		expect(bare.Cash).toBe(50)
	end)

	test("a take that errors after its update still completes the sale (no lost nurse, no free cash)", function()
		local seller, buyer, id = market(300)
		local total = saves[seller].Cash + saves[buyer].Cash
		errorAfter[seller] = true
		local ok = BuyListing(buyer, id, 300)
		expect(ok).toBe(true)
		expect(saves[seller].Nurses.PuffPup).toBeNil()
		expect(saves[buyer].Nurses.PuffPup).toEqual({ Level = 3, XP = 7, Copies = 2, Job = "" })
		expect(saves[seller].Cash + saves[buyer].Cash).toBe(total - 30)
	end)

	test("a give that errors after its update is never undone (that would make two)", function()
		local seller, buyer, id = market(300)
		local total = saves[seller].Cash + saves[buyer].Cash
		errorAfter[buyer] = true
		local ok = BuyListing(buyer, id, 300)
		expect(ok).toBe(true)
		expect(saves[seller].Nurses.PuffPup).toBeNil()
		expect(saves[buyer].Nurses.PuffPup ~= nil).toBe(true)
		expect(saves[seller].Cash + saves[buyer].Cash).toBe(total - 30)
	end)

	test("buys wait 2 s per buyer", function()
		local _, buyer, id = market(100, 10000)
		expect((BuyListing(buyer, id, 100))).toBe(true)
		local seller2 = newPlayer("Seller2")
		save(seller2, { Nurses = { MintMouse = nurse(1) } })
		expect((ListNurse(seller2, "MintMouse", 100))).toBe(true) -- a seller's first listing needs no wait
		local id2 = listingsOf(seller2.UserId)[1].Id
		now += 1.9
		local ok, message = BuyListing(buyer, id2, 100)
		expect(ok).toBe(false)
		expect(message).toBe("Too fast! Try again.")
		expect(#listingsOf(seller2.UserId)).toBe(1)
		now += 0.1
		expect((BuyListing(buyer, id2, 100))).toBe(true)
	end)

	test("the buyer is saved only after the seller's write landed", function()
		local seller, buyer, id = market(100)
		saveFails[seller] = true
		saveLog = {}
		afterLog = {}
		expect((BuyListing(buyer, id, 100))).toBe(true)
		expect(saveLog).toEqual({ "Seller" })
		-- and the buyer's autosave / leave-save are held behind the seller's write too (PlayerData.writeAfter)
		expect(afterLog).toEqual({ seller.Name .. ">" .. buyer.Name })
		saveFails[seller] = nil
	end)

	test("a listed nurse keeps working: its level on the Market follows the save", function()
		local seller, _, _ = market(100)
		PlayerData.update(seller, function(d)
			d.Nurses.PuffPup.Level = 4
		end)
		expect(listingsOf(seller.UserId)[1].Level).toBe(4)
	end)

	test(
		"copies raise the lowest price: never listed below what the Agency pays, and a copy while listed ends it",
		function()
			local seller = newPlayer("CopySeller")
			save(seller, { Nurses = { MintMouse = nurse(10, 0, 10) } }) -- a Common Lv 10 with 10 copies: Agency pays 💰300
			later()
			local ok, message = ListNurse(seller, "MintMouse", 190) -- the old level-only default
			expect(ok).toBe(false)
			expect(message).toBe(SP.bandText(MarketLogic.band(Config, "Common", 10, 10)))
			expect((ListNurse(seller, "MintMouse", 340))).toBe(true)
			local before = #toasts
			PlayerData.update(seller, function(d)
				d.Nurses.MintMouse.Copies = 12 -- a belt copy while listed: 💰360 now pays less than the Agency
			end)
			expect(#listingsOf(seller.UserId)).toBe(0)
			expect(Nurses.isListed(seller, "MintMouse")).toBe(false)
			expect(toasts[before + 1].Text).toBe("🏷️ It grew! List it again")
		end
	)

	test("MarketNews is debounced: a burst of changes sends one view", function()
		flush()
		newsAll = 0
		local p = newPlayer("Burst")
		save(p, { Nurses = { PuffPup = nurse(1), MintMouse = nurse(1) } })
		later()
		ListNurse(p, "PuffPup", 100)
		later()
		ListNurse(p, "MintMouse", 100)
		Unlist(p, listingsOf(p.UserId)[1].Id)
		expect(newsAll).toBe(0)
		flush()
		expect(newsAll).toBe(1)
	end)

	test("a buyer leaving changes nothing for the seller's other listings", function()
		local seller, buyer, id = market(100)
		leave(buyer)
		expect(#listingsOf(seller.UserId)).toBe(1)
		local other = newPlayer("Late")
		save(other, { Cash = 1000 })
		expect((BuyListing(other, id, 100))).toBe(true)
	end)
end)

local CP = pureBlock("src/client/UI/MarketPanel.luau", { MarketLogic = MarketLogic })
local RARITY_ORDER = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

T.describe("MarketPanel.Pure (client)", function()
	test("the picker's step is a round 1-2-5 number, about 20 taps across the band", function()
		expect(CP.step(50, 300, 10)).toBe(20)
		expect(CP.step(60, 360, 10)).toBe(20)
		expect(CP.step(25000, 150000, 10)).toBe(10000)
		expect(CP.step(60000, 360000, 10)).toBe(20000)
		expect(CP.step(100, 100, 10)).toBe(10)
		for _, rarity in RARITY_ORDER do
			for _, level in { 1, 5, 10, 15 } do
				local min, max = MarketLogic.band(Config, rarity, level)
				local step = CP.step(min, max, 10)
				expect(step % 10).toBe(0)
				expect((max - min) / step <= 20).toBe(true)
			end
		end
	end)

	test("every price the picker offers is inside the band (the server's check)", function()
		for _, rarity in RARITY_ORDER do
			for _, level in { 1, 3, 10, 15 } do
				local min, max = MarketLogic.band(Config, rarity, level)
				local step = CP.step(min, max, 10)
				local price = CP.snap(min, min, max, step)
				local seen = 0
				while true do
					expect(MarketLogic.valid(price, min, max)).toBe(true)
					seen += 1
					local nextPrice = CP.nudge(price, 1, min, max, step)
					if nextPrice == price then
						break
					end
					expect(nextPrice > price).toBe(true)
					price = nextPrice
				end
				expect(price).toBe(max) -- + reaches the top
				expect(seen <= 22).toBe(true)
				for _, f in { -1, 0, 0.33, 0.5, 0.99, 1, 2, 0 / 0 } do
					expect(MarketLogic.valid(CP.fromFraction(f, min, max, step), min, max)).toBe(true)
				end
				local fair = CP.fair(Config, rarity, level, min, max, step)
				expect(MarketLogic.valid(fair, min, max)).toBe(true)
			end
		end
	end)

	test("snap, nudge and the slider fraction", function()
		expect(CP.snap(0 / 0, 50, 300, 20)).toBe(50)
		expect(CP.snap(1e9, 50, 300, 20)).toBe(300)
		expect(CP.snap(61, 50, 300, 20)).toBe(70)
		expect(CP.nudge(300, -1, 50, 300, 20)).toBe(290)
		expect(CP.nudge(290, 1, 50, 300, 20)).toBe(300)
		expect(CP.nudge(50, -1, 50, 300, 20)).toBe(50)
		expect(CP.fraction(175, 50, 300)).toBe(0.5)
		expect(CP.fraction(10, 50, 300)).toBe(0)
		expect(CP.fromFraction(0.5, 50, 300, 20)).toBe(170)
		expect(CP.fair(Config, "Common", 1, 50, 300, 20)).toBe(110) -- the belt's 100, on the grid (50 + 3 x 20)
	end)

	test("the payout shown is the server's: price minus floor(10%)", function()
		expect(CP.payout(420, Config)).toBe(378)
		expect(CP.payout(55, Config)).toBe(50)
	end)

	test("a card's state follows Logic/Market.canBuy", function()
		local state = Schema.default()
		state.Level = 3
		state.Cash = 500
		local listing =
			{ Id = 1, Seller = 77, SellerName = "A", NurseId = "PuffPup", Rarity = "Common", Level = 1, Price = 100 }
		expect({ CP.buyState(state, listing, 5, Config, NursesData) }).toEqual({ "Buy", "Buy" })
		expect({ CP.buyState(state, listing, 77, Config, NursesData) }).toEqual({ "Mine", "Yours" })
		state.Nurses = { PuffPup = nurse(1) }
		expect({ CP.buyState(state, listing, 5, Config, NursesData) }).toEqual({ "Blocked", "You have one!" })
		state.Nurses = { MintMouse = nurse(1), BeanBear = nurse(1), DewDuck = nurse(1) }
		expect({ CP.buyState(state, listing, 5, Config, NursesData) }).toEqual({ "Blocked", "Roster full" })
		state.Nurses = {}
		state.Cash = 99
		expect({ CP.buyState(state, listing, 5, Config, NursesData) }).toEqual({ "Blocked", "Need 💰100" })
		local epic =
			{ Id = 2, Seller = 77, SellerName = "A", NurseId = "CloudKoala", Rarity = "Epic", Level = 1, Price = 750 }
		state.Level = 1
		state.Cash = 5000
		expect({ CP.buyState(state, epic, 5, Config, NursesData) }).toEqual({ "Blocked", "🏥 Lv 3" })
	end)

	test("sellable: owned, not rebirth-only, not listed; rarest and highest first", function()
		local nurses = {
			PuffPup = nurse(2),
			MintMouse = nurse(5),
			CuddleCub = nurse(1),
			FounderFennec = nurse(1),
			Unknown = nurse(1),
			BeanBear = nurse(9),
		}
		expect(CP.sellable(nurses, NursesData, { BeanBear = true }, RARITY_ORDER)).toEqual({
			"CuddleCub",
			"MintMouse",
			"PuffPup",
		})
		expect(CP.sellable(nil, NursesData, {}, RARITY_ORDER)).toEqual({})
	end)

	test("the Buy tab shows others' newest first, then yours; Mine is yours, oldest first", function()
		local listings = {
			{ Id = 1, Seller = 5 },
			{ Id = 2, Seller = 9 },
			{ Id = 3, Seller = 5 },
			{ Id = 4, Seller = 8 },
		}
		local order = {}
		for _, listing in CP.forSale(listings, 5) do
			table.insert(order, listing.Id)
		end
		expect(order).toEqual({ 4, 2, 3, 1 })
		local mine = {}
		for _, listing in CP.mine(listings, 5) do
			table.insert(mine, listing.Id)
		end
		expect(mine).toEqual({ 1, 3 })
	end)

	test("confirms and buttons stay at 6 words or fewer", function()
		expect(CP.confirmBuy("🐶", 7, 420)).toBe("Buy 🐶 Lv 7 for 💰420?")
		expect(CP.confirmList("🐶", 7, 1200)).toBe("List 🐶 Lv 7 for 💰1,200?")
		expect({ CP.listButton(0, 0, Config) }).toEqual({ true, "🏷️ List it!" })
		expect({ CP.listButton(3, 3, Config) }).toEqual({ false, "3 listings max!" })
		expect({ CP.listButton(1, 30, Config) }).toEqual({ false, "Market is full!" })
		for _, text in
			{
				CP.confirmBuy("🐶", 15, 150000),
				CP.confirmList("🐶", 15, 150000),
				"🏷️ Only this server",
				"🚫 No swaps. No chat.",
				"👇 Pick a nurse to sell",
				"🏷️ Nothing for sale yet",
				"💼 Listed nurses keep working",
				"10% goes to the Market",
			}
		do
			expect(words(text) <= 6).toBe(true)
		end
	end)

	test("a view from the network is checked field by field", function()
		expect(CP.view(nil)).toBeNil()
		expect(CP.view({ Listings = 5 })).toBeNil()
		local view = CP.view({
			Listings = {
				{ Id = 1, Seller = 2, SellerName = "A", NurseId = "PuffPup", Rarity = "Common", Level = 1, Price = 50 },
				{
					Id = "x",
					Seller = 2,
					SellerName = "A",
					NurseId = "PuffPup",
					Rarity = "Common",
					Level = 1,
					Price = 50,
				},
				{
					Id = 3,
					Seller = 2,
					SellerName = "A",
					NurseId = "PuffPup",
					Rarity = "Common",
					Level = 0 / 0,
					Price = 50,
				},
				"junk",
			},
			FeePercent = 10,
		})
		expect(#view.Listings).toBe(1)
		expect(view.FeePercent).toBe(10)
		expect(view.MaxPerSeller).toBe(3)
	end)
end)
