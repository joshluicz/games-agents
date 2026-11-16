--!nocheck
-- Branches on the server (Progression v2 build plan §C T2, Review focus 1-2): the real src/server/Rebirth.luau,
-- Economy.luau, Carry.luau and Plots.luau run under Lune with mocked Roblox services (Players, PlayerData, Patients,
-- Treatment, Nurses, Plots, the builders), against the real Config, Logic and Data. Rebirth's PURE-BEGIN..PURE-END
-- block is also loaded on its own. It checks what a cheating or impatient client would poke at:
--   · a rebirth resets exactly what Logic/Rebirth.apply says, after Patients.reopen, in ONE update, then syncs the
--     rooms, saves at once and celebrates; a rejoin keeps the same offer; spam makes one rebirth; the count it
--     checked is the count it writes;
--   · ChoosePerk only takes an offered card; the tree's buy/refund round trip; themes; the gift nurse; junk calls
--     change nothing; the one gentle toast comes once;
--   · Economy's upgrade gates, Carry's 🧺 Big Hands, Plots.syncRooms.
-- Run from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local T = require("./expect")
local expect, test = T.expect, T.test

local Config = require("./config")
local Schema = require("../src/shared/Logic/Schema")
local RebirthLogic = require("../src/shared/Logic/Rebirth")
local TreeLogic = require("../src/shared/Logic/Tree")
local TutorialLogic = require("../src/shared/Logic/Tutorial")
local Prices = require("../src/shared/Logic/Prices")
local Progress = require("../src/shared/Logic/Progress")
local DecorData = require("../src/shared/Data/Decor")
local NursesData = require("../src/shared/Data/Nurses")
local PerksData = require("../src/shared/Data/Perks")
local ThemesData = require("../src/shared/Data/Themes")
local TreeData = require("../src/shared/Data/Tree")
local RoomsData = require("../src/shared/Data/Rooms")
local UpgradesData = require("../src/shared/Data/Upgrades")
local ItemsData = require("../src/shared/Data/Items")

local ROOT = "src/server/"

local function source(path: string): string
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("can't find " .. path .. " (run from game/)")
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, item in value do
		out[key] = deepCopy(item)
	end
	return out
end

local function words(text: string): number
	local n = 0
	for _ in string.gmatch(text, "%S+") do
		n += 1
	end
	return n
end

local Signal = luau.load(source("src/shared/Signal.luau"), {
	debugName = "Shared/Signal",
	environment = { task = task },
	injectGlobals = true,
})()

------------------------------------------------------------------------------------------------------------------
-- Mocks shared by every module below
------------------------------------------------------------------------------------------------------------------

local warnings: { string } = {}
local now = 1000
local fakeOs = setmetatable({
	clock = function()
		return now
	end,
}, { __index = os })

-- A deterministic Random: the offers are reproducible.
local FakeRandom = {
	new = function()
		local state = 12345
		local rng = {}
		function rng:NextNumber(a, b)
			state = (state * 1103515245 + 12345) % 2147483648
			local r = state / 2147483648
			if a and b then
				return a + (b - a) * r
			end
			return r
		end
		return rng
	end,
}

local Players = { PlayerAdded = Signal.new(), PlayerRemoving = Signal.new(), list = {} }
function Players:GetPlayers()
	return self.list
end

local nextUserId = 100
local function newPlayer(name: string)
	nextUserId += 1
	local attributes = {}
	local p = {
		__instance = true,
		Name = name,
		DisplayName = name,
		UserId = nextUserId,
		Parent = Players,
		Character = nil,
		CharacterAdded = Signal.new(),
		CharacterRemoving = Signal.new(),
	}
	function p:IsA(class)
		return class == "Player" or class == "Instance"
	end
	function p:GetAttribute(k)
		return attributes[k]
	end
	function p:SetAttribute(k, v)
		attributes[k] = v
	end
	function p:IsFriendsWith()
		return false
	end
	table.insert(Players.list, p)
	return p
end

local toasts: { { Player: any, Text: string } } = {}
local celebrations: { { Player: any, Info: any } } = {}
local served: { [string]: (...any) -> ...any } = {}
local Remotes = {
	OOPS = "Oops! Try again.",
	TOO_FAST = "Too fast! Try again.",
	SOON = "Coming soon!",
	serve = function(name, handler)
		served[name] = handler
	end,
	toast = function(player, text)
		table.insert(toasts, { Player = player, Text = text })
	end,
	news = function(player, text)
		table.insert(toasts, { Player = player, Text = text })
	end,
	toastAll = function() end,
	Celebrate = {
		FireClient = function(_, player, info)
			table.insert(celebrations, { Player = player, Info = info })
		end,
	},
}

-- PlayerData: the live saves, one update at a time (fn, then Changed, like the real one), a yielding saveNow.
local saves = {}
local notSaving = {}
local saveNows = 0
local updates = 0
local PlayerData = { Loaded = Signal.new(), Changed = Signal.new() }
function PlayerData.get(player)
	return saves[player]
end
function PlayerData.update(player, fn)
	local data = saves[player]
	if not data then
		return false
	end
	updates += 1
	fn(data)
	PlayerData.Changed:Fire(player, data)
	return true
end
function PlayerData.canSave(player)
	return saves[player] ~= nil and not notSaving[player]
end
function PlayerData.isOpen(player)
	return saves[player] ~= nil and player.Parent == Players
end
function PlayerData.saveNow(player)
	task.wait(0.03) -- a DataStore write yields
	saveNows += 1
	return saves[player] ~= nil
end

local function typeofMock(value)
	if type(value) == "table" and value.__instance then
		return "Instance"
	end
	return typeof(value)
end

-- A Lv 5 save at the start of its first branch's end: everything touched.
local function richSave(): any
	local data = Schema.default()
	data.Tutorial = TutorialLogic.DONE
	data.Level = 5
	data.Cash = 60000
	data.Stars = 321
	data.Cured = 4000
	data.Upgrades = { Speed = 5, Tray = 3, Chairs = 2, Tips = 4, WardComfort = 2, AESpeed = 1, NightClinic = 0 }
	data.Rooms = { Stand = true, BathRoom = true, Ward = true }
	data.Decor = {
		Owned = { PottedFern = true, CozyRug = true, HeartRug = true },
		Placed = { ["Stand:1"] = "PottedFern", ["Ward:1"] = "CozyRug" },
	}
	data.Nurses = {
		PuffPup = { Level = 4, XP = 3, Copies = 4, Job = "" },
		MintMouse = { Level = 2, XP = 0, Copies = 2, Job = "" },
	}
	data.Book = { Puffle = { Count = 3 } }
	data.Rebirth.Told = false
	return data
end

local function load(path: string, scriptParent: any, shared: any, services: any): any
	local env = {
		game = {
			GetService = function(_, name)
				if services[name] then
					return services[name]
				end
				return { Shared = shared }
			end,
		},
		script = { Parent = scriptParent },
		require = function(module)
			return assert(module, "no mock for a require in " .. path)
		end,
		typeof = typeofMock,
		task = task,
		os = fakeOs,
		warn = function(...)
			local parts = {}
			for _, part in { ... } do
				table.insert(parts, tostring(part))
			end
			table.insert(warnings, table.concat(parts, " ")) -- kept quiet: the suite's output stays PASS/FAIL
		end,
		Random = FakeRandom,
		CFrame = roblox.CFrame,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
	}
	return luau.load(source(path), { debugName = path, environment = env, injectGlobals = true })()
end

local Palette = {
	White = roblox.Color3.new(1, 1, 1),
	Ink = roblox.Color3.new(0.1, 0.1, 0.2),
	Outline = roblox.Color3.new(0.1, 0.1, 0.2),
	Candy = { Yellow = roblox.Color3.new(1, 0.9, 0.3), Orange = roblox.Color3.new(1, 0.6, 0.2) },
	outlineShape = function() end,
}

local SHARED = {
	Config = Config,
	Palette = Palette,
	Remotes = Remotes,
	Signal = Signal,
	Types = {},
	Logic = {
		Rebirth = RebirthLogic,
		Tree = TreeLogic,
		Tutorial = TutorialLogic,
		Prices = Prices,
		Progress = Progress,
	},
	Data = {
		Decor = DecorData,
		Nurses = NursesData,
		Perks = PerksData,
		Themes = ThemesData,
		Tree = TreeData,
		Rooms = RoomsData,
		Upgrades = UpgradesData,
		Items = ItemsData,
		Stations = {},
	},
}

------------------------------------------------------------------------------------------------------------------
-- compile
------------------------------------------------------------------------------------------------------------------

T.describe("compile", function()
	for _, name in { "Rebirth.luau", "Economy.luau", "Carry.luau", "Plots.luau" } do
		test(name, function()
			local ok, err = pcall(luau.compile, source(ROOT .. name))
			expect(ok).toBe(true)
			if not ok then
				error(err)
			end
		end)
	end
end)

------------------------------------------------------------------------------------------------------------------
-- Rebirth.Pure, loaded on its own
------------------------------------------------------------------------------------------------------------------

local function pureBlock(name: string, env: { [string]: any }): any
	local text = source(ROOT .. name)
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to, name .. ": no PURE block")
	local block = string.sub(text, from, to - 1) .. "\nreturn Pure\n"
	local chunk = luau.load(block, { debugName = name .. ":Pure", environment = env, injectGlobals = true })
	return chunk()
end

local P = pureBlock("Rebirth.luau", { RebirthLogic = RebirthLogic, TutorialLogic = TutorialLogic })

T.describe("Rebirth.Pure atomic", function()
	test("writes back only the listed fields when fn says yes", function()
		local data = { Cash = 10, Rebirth = { Count = 0 }, Stars = 5 }
		local rebirthTable = data.Rebirth
		local ok, result = P.atomic(data, { "Cash", "Rebirth" }, function(trial)
			trial.Cash = 0
			trial.Rebirth.Count = 1
			trial.Stars = 999 -- not listed: never written
			return true, "done"
		end)
		expect(ok).toBe(true)
		expect(result).toBe("done")
		expect(data).toEqual({ Cash = 0, Rebirth = { Count = 1 }, Stars = 5 })
		expect(data.Rebirth == rebirthTable).toBe(true) -- the live sub-table is kept (filled in place)
	end)

	test("an error halfway leaves the save exactly as it was", function()
		local data = richSave()
		local before = deepCopy(data)
		local ok = P.atomic(data, P.APPLY_KEYS, function(trial)
			trial.Cash = 0
			trial.Rooms = { Stand = true }
			trial.Rebirth.Count = 99
			error("boom")
		end)
		expect(ok).toBe(false)
		expect(data).toEqual(before)
	end)

	test("a no leaves the save unchanged and passes the message on", function()
		local data = richSave()
		local before = deepCopy(data)
		local ok, why = P.atomic(data, P.REBIRTH_KEYS, function(trial)
			trial.Rebirth.Points = 50
			return false, "Max rank!"
		end)
		expect(ok).toBe(false)
		expect(why).toBe("Max rank!")
		expect(data).toEqual(before)
	end)

	test("Logic/Rebirth.apply through atomic equals apply on a copy", function()
		local data = richSave()
		local expected = deepCopy(data)
		local offer = { "BusyDoors", "WarmUp", "NightOwl" }
		local content = { Perks = PerksData, Themes = ThemesData, Nurses = NursesData, Decor = DecorData }
		RebirthLogic.apply(expected, Config, offer, content)
		local ok = P.atomic(data, P.APPLY_KEYS, function(trial)
			return true, RebirthLogic.apply(trial, Config, offer, content)
		end)
		expect(ok).toBe(true)
		expect(data).toEqual(expected) -- APPLY_KEYS covers every field apply touches
	end)
end)

T.describe("Rebirth.Pure check", function()
	local yes = { Free = false, CanSave = true, Treating = false }

	test("a ready Lv 5 save passes", function()
		expect(P.check(richSave(), Config, yes)).toBe(true)
	end)

	test("the §B3 order: saving, tutorial, a waiting card, Lv 5 / cash, treating", function()
		local data = richSave()
		data.Tutorial = 3
		data.Rebirth.Offer = { "BusyDoors" }
		data.Level = 2
		local _, why = P.check(data, Config, { Free = false, CanSave = false, Treating = true })
		expect(why).toBe(P.MSG.SavingOff)
		_, why = P.check(data, Config, { Free = false, CanSave = true, Treating = true })
		expect(why).toBe(P.MSG.Tutorial)
		data.Tutorial = TutorialLogic.DONE
		_, why = P.check(data, Config, { Free = false, CanSave = true, Treating = true })
		expect(why).toBe(P.MSG.PickCard)
		data.Rebirth.Offer = {}
		_, why = P.check(data, Config, { Free = false, CanSave = true, Treating = true })
		expect(why).toBe("Need 🏙️ Lv 5")
		data.Level = 5
		data.Cash = 49999
		_, why = P.check(data, Config, { Free = false, CanSave = true, Treating = true })
		expect(why).toBe("Need 💰50,000")
		data.Cash = 50000
		_, why = P.check(data, Config, { Free = false, CanSave = true, Treating = true })
		expect(why).toBe(P.MSG.Treating)
	end)

	test("free (admin) skips saving, tutorial, card, level and cost; never the treat session", function()
		local data = Schema.default()
		data.Rebirth.Offer = { "BusyDoors" }
		expect(P.check(data, Config, { Free = true, CanSave = false, Treating = false })).toBe(true)
		local ok, why = P.check(data, Config, { Free = true, CanSave = false, Treating = true })
		expect(ok).toBe(false)
		expect(why).toBe(P.MSG.Treating)
	end)

	test("the count tops out at Schema.MAX_REBIRTHS", function()
		local data = richSave()
		data.Rebirth.Count = Schema.MAX_REBIRTHS
		local ok, why = P.check(data, Config, { Free = true, CanSave = true, Treating = false })
		expect(ok).toBe(false)
		expect(why).toBe(P.MSG.MaxBranches)
	end)

	test("junk data is 'still loading'", function()
		local _, why = P.check(nil, Config, yes)
		expect(why).toBe(P.MSG.Loading)
	end)
end)

T.describe("Rebirth.Pure display", function()
	test("R1 celebrates the rebirth, then each new unlock", function()
		local list = P.celebrations({ Count = 1, Theme = "Arctic", Unlocks = { "MythicSecret", "SunnyWing" } })
		expect(#list).toBe(3)
		expect(list[1]).toEqual({ Kind = "Rebirth", Title = "New branch!", Icon = "🏢", Count = 1, Theme = "Arctic" })
		expect(list[2].Kind).toBe("Unlock")
		expect(list[2].Unlock).toBe("MythicSecret")
		expect(list[3].Unlock).toBe("SunnyWing")
	end)

	test("a Branch Trophy names its decor", function()
		local list = P.celebrations({ Count = 6, Theme = "Royal", Unlocks = { "Trophy6" }, Trophies = { "TrophyCup" } })
		expect(list[2].Decor).toBe("TrophyCup")
	end)

	test("titles are 3 words or fewer; replies 6 or fewer", function()
		for _, info in P.celebrations({ Count = 5, Theme = "Royal", Unlocks = RebirthLogic.unlocks(5) }) do
			expect(words(info.Title) <= 3).toBe(true)
		end
		for _, perkId in PerksData.Order do
			expect(words(P.perkCelebration(perkId, PerksData).Title) <= 3).toBe(true)
			expect(words(P.perkReply(perkId, PerksData)) <= 6).toBe(true)
		end
		expect(P.perkReply("TreePoints", PerksData)).toBe("🌳 +2 tree points!")
		for _, nodeId in TreeData.Nodes.Order do
			expect(words(P.nodeReply(TreeData.Nodes[nodeId], 3)) <= 6).toBe(true)
		end
		for key, text in P.MSG do
			if key ~= "GiftWaits" then -- the build plan's exact words
				expect(words(text) <= 6).toBe(true)
			end
		end
	end)

	test("the first waiting gift is a known rebirth-only nurse", function()
		expect(P.firstPending({ "Nobody", "PuffPup", "FounderFennec" }, NursesData)).toBe("FounderFennec")
		expect(P.firstPending({ "Order" }, NursesData)).toBeNil()
		expect(P.firstPending({}, NursesData)).toBeNil()
		expect(P.firstPending("junk", NursesData)).toBeNil()
	end)

	test("the sign's badge shows from R1", function()
		local text, visible = P.badge(0)
		expect(visible).toBe(false)
		text, visible = P.badge(3)
		expect(text).toBe("🏢 3")
		expect(visible).toBe(true)
	end)

	test("Quick Feet ranks are the walk boost", function()
		expect(P.walkBoost({ Walk = 2 })).toBe(2)
		expect(P.walkBoost({ Walk = -1 })).toBe(0)
		expect(P.walkBoost(nil)).toBe(0)
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- Server/Rebirth, the whole module
------------------------------------------------------------------------------------------------------------------

local reopens: { number } = {} -- the Rebirth.Count each Patients.reopen saw
local onReopen: ((any) -> ())? = nil
local busy = {}
local grants = {}
local rosterFull = false
local synced = 0

local Patients = {
	reopen = function(player)
		table.insert(reopens, saves[player] and saves[player].Rebirth.Count or -1)
		if onReopen then
			onReopen(player)
		end
		return true
	end,
}
local Treatment = {
	busy = function(player)
		return busy[player] == true
	end,
}
local NursesMock = {
	grant = function(player, nurseId, price, source)
		table.insert(grants, { Player = player, NurseId = nurseId, Price = price, Source = source })
		if rosterFull then
			return false, "Roster full: sell or list one"
		end
		PlayerData.update(player, function(d)
			d.Nurses[nurseId] = { Level = 1, XP = 0, Copies = 1, Job = "" }
			local index = table.find(d.Rebirth.Pending, nurseId)
			if index then
				table.remove(d.Rebirth.Pending, index)
			end
		end)
		return true, "🎉 Hired!"
	end,
}
local PlotsMock = {
	PlotAssigned = Signal.new(),
	PlotReleased = Signal.new(),
	getPlot = function()
		return nil
	end,
	all = function()
		return {}
	end,
	syncRooms = function()
		synced += 1
	end,
}

local Rebirth = load(
	ROOT .. "Rebirth.luau",
	{
		CreatureBuilder = { MOTION_TAG = "CreatureMotion" },
		NurseBuilder = {},
		Nurses = NursesMock,
		Patients = Patients,
		PlayerData = PlayerData,
		Plots = PlotsMock,
		Treatment = Treatment,
	},
	SHARED,
	{
		Players = Players,
		CollectionService = { AddTag = function() end },
		StarterPlayer = { CharacterWalkSpeed = 16 },
	}
)
local reborn = {}
Rebirth.Reborn:Connect(function(player, count)
	table.insert(reborn, { Player = player, Count = count })
end)
Rebirth.start()

local function fresh(name: string, data: any?): any
	local p = newPlayer(name)
	saves[p] = data or richSave()
	return p
end

local function clearLogs()
	table.clear(reopens)
	table.clear(toasts)
	table.clear(celebrations)
	table.clear(grants)
	table.clear(reborn)
	synced = 0
	saveNows = 0
	onReopen = nil
	rosterFull = false
end

local function kinds(list): { string }
	local out = {}
	for _, entry in list do
		table.insert(out, entry.Info.Kind .. ":" .. tostring(entry.Info.Unlock or entry.Info.Perk or entry.Info.Count))
	end
	return out
end

T.describe("Server/Rebirth OpenBranch", function()
	test("a rebirth resets exactly what apply resets, after reopen, then syncs, saves and celebrates", function()
		clearLogs()
		local p = fresh("Ava")
		local expected = deepCopy(saves[p])
		local ok, message = served.OpenBranch(p, true)
		expect(ok).toBe(true)
		expect(message).toBe("🏢 New branch open!")
		local d = saves[p]
		-- the same as Logic/Rebirth.apply with the offer it rolled (+ Told)
		RebirthLogic.apply(
			expected,
			Config,
			d.Rebirth.Offer,
			{ Perks = PerksData, Themes = ThemesData, Nurses = NursesData, Decor = DecorData }
		)
		expected.Rebirth.Told = true
		expect(d).toEqual(expected)
		expect(d.Rebirth.Count).toBe(1)
		expect(d.Cash).toBe(0)
		expect(d.Level).toBe(1)
		expect(d.Rooms).toEqual({ Stand = true })
		expect(d.Decor.Placed).toEqual({ ["Stand:1"] = "PottedFern" })
		expect(d.Decor.Owned.CozyRug).toBe(true) -- decor goes back to the inventory, still owned
		expect(d.Nurses.PuffPup.Level).toBe(4) -- nurses kept
		expect(d.Stars).toBe(321)
		expect(d.Rebirth.Points).toBe(3)
		expect(d.Rebirth.Theme).toBe("Arctic")
		-- three distinct cards, none owned
		expect(#d.Rebirth.Offer).toBe(3)
		expect(d.Rebirth.Offer[1] ~= d.Rebirth.Offer[2] and d.Rebirth.Offer[2] ~= d.Rebirth.Offer[3]).toBe(true)
		-- order: reopen saw the old count; then the update; syncRooms; saveNow; the celebrations
		expect(reopens).toEqual({ 0 })
		expect(synced).toBe(1)
		expect(saveNows).toBe(1)
		expect(kinds(celebrations)).toEqual({ "Rebirth:1", "Unlock:MythicSecret", "Unlock:SunnyWing" })
		expect(#reborn).toBe(1)
		expect(reborn[1].Count).toBe(1)
	end)

	test("a cure landing in reopen still resets (its cash came first)", function()
		clearLogs()
		local p = fresh("Ben")
		onReopen = function(player)
			PlayerData.update(player, function(d)
				d.Cash += 120
				d.Cured += 1
			end)
		end
		expect(served.OpenBranch(p, true)).toBe(true)
		expect(saves[p].Cash).toBe(0)
		expect(saves[p].Cured).toBe(4001) -- the cure itself is kept
	end)

	test("spam: 3 calls in 0.1 s make one rebirth", function()
		clearLogs()
		local p = fresh("Cy")
		local results = {}
		for index = 1, 3 do
			task.spawn(function()
				results[index] = { served.OpenBranch(p, true) }
			end)
			now += 0.03
		end
		task.wait(0.2)
		local wins = 0
		for index = 1, 3 do
			if results[index][1] == true then
				wins += 1
			end
		end
		expect(wins).toBe(1)
		expect(saves[p].Rebirth.Count).toBe(1)
		expect(#reopens).toBe(1)
		expect(saveNows).toBe(1)
	end)

	test("5 s per player, even when the save could go again", function()
		clearLogs()
		local p = fresh("Dee")
		expect(served.OpenBranch(p, true)).toBe(true)
		-- (a save that could somehow rebirth again at once)
		saves[p].Level = 5
		saves[p].Cash = 999999
		saves[p].Rebirth.Offer = {}
		now += 2
		local ok, why = served.OpenBranch(p, true)
		expect(ok).toBe(false)
		expect(why).toBe("Too fast! Try again.")
		expect(saves[p].Rebirth.Count).toBe(1)
		now += 5
		expect(served.OpenBranch(p, true)).toBe(true)
		expect(saves[p].Rebirth.Count).toBe(2)
	end)

	test("admin spam: one in flight at a time", function()
		clearLogs()
		local p = fresh("Eve", Schema.default())
		local results = {}
		for index = 1, 3 do
			task.spawn(function()
				results[index] = { Rebirth.adminRebirth(p) }
			end)
		end
		task.wait(0.15)
		expect(saves[p].Rebirth.Count).toBe(1)
		expect(results[1][1]).toBe(true)
		expect(results[2][2]).toBe("One at a time!")
		expect(results[3][2]).toBe("One at a time!")
		-- once it lands, the admin can go again (no Lv 5, no cost, no cooldown)
		expect(Rebirth.adminRebirth(p)).toBe(true)
		expect(saves[p].Rebirth.Count).toBe(2)
	end)

	test("the count it checked must be the count it writes", function()
		clearLogs()
		local p = fresh("Finn")
		onReopen = function(player)
			saves[player].Rebirth.Count += 1 -- as if another rebirth landed meanwhile
		end
		local ok, why = served.OpenBranch(p, true)
		expect(ok).toBe(false)
		expect(why).toBe("One at a time!")
		expect(saves[p].Rebirth.Count).toBe(1) -- only the other one
		expect(saves[p].Cash).toBe(60000) -- nothing reset
		expect(saveNows).toBe(0)
	end)

	test("junk and every refusal change nothing", function()
		clearLogs()
		local p = fresh("Gus")
		local before = deepCopy(saves[p])
		local function refused(why, ...)
			local ok, message = served.OpenBranch(p, ...)
			expect(ok).toBe(false)
			expect(message).toBe(why)
			expect(saves[p]).toEqual(before)
		end
		refused("Oops! Try again.", false)
		refused("Oops! Try again.", "true")
		refused("Oops! Try again.", 1)
		refused("Oops! Try again.")
		notSaving[p] = true
		refused("⚠️ Saving is off", true)
		notSaving[p] = nil
		busy[p] = true
		refused("Finish treating first!", true)
		busy[p] = nil
		saves[p].Tutorial = 4
		before = deepCopy(saves[p])
		refused("Finish the tutorial first!", true)
		saves[p].Tutorial = TutorialLogic.DONE
		saves[p].Level = 4
		before = deepCopy(saves[p])
		refused("Need 🏙️ Lv 5", true)
		saves[p].Level = 5
		saves[p].Cash = 100
		before = deepCopy(saves[p])
		refused("Need 💰50,000", true)
		expect(#reopens).toBe(0)
		expect(#celebrations).toBe(0)
		-- not a player at all
		expect(Rebirth.open({}, false)).toBe(false)
	end)

	test("a waiting card blocks the next rebirth (one card per branch; no re-roll)", function()
		clearLogs()
		local p = fresh("Hal")
		expect(served.OpenBranch(p, true)).toBe(true)
		local offer = deepCopy(saves[p].Rebirth.Offer)
		saves[p].Level = 5
		saves[p].Cash = 999999
		now += 10
		local ok, why = served.OpenBranch(p, true)
		expect(ok).toBe(false)
		expect(why).toBe("🃏 Pick your card first!")
		expect(saves[p].Rebirth.Offer).toEqual(offer)
		expect(saves[p].Rebirth.Count).toBe(1)
	end)

	test("a rejoin keeps the same offer", function()
		clearLogs()
		local p = fresh("Ivy")
		expect(served.OpenBranch(p, true)).toBe(true)
		local offer = deepCopy(saves[p].Rebirth.Offer)
		-- leave, then join again: the saved record goes through Schema.reconcile on load
		local stored = deepCopy(saves[p])
		Players.PlayerRemoving:Fire(p)
		saves[p] = nil
		local again = newPlayer("Ivy")
		saves[again] = Schema.reconcile(stored)
		PlayerData.Loaded:Fire(again, saves[again])
		task.wait()
		expect(saves[again].Rebirth.Offer).toEqual(offer)
		-- and the card can be chosen from it
		local ok = served.ChoosePerk(again, offer[2])
		expect(ok).toBe(true)
		expect(saves[again].Rebirth.Perks).toEqual({ offer[2] })
		expect(saves[again].Rebirth.Offer).toEqual({})
	end)

	test("R5: FounderFennec arrives as a gift, or waits with a toast", function()
		clearLogs()
		local data = richSave()
		data.Rebirth.Count = 4
		data.Cash = 300000
		local p = fresh("Jo", data)
		rosterFull = true
		expect(served.OpenBranch(p, true)).toBe(true)
		expect(saves[p].Rebirth.Count).toBe(5)
		expect(saves[p].Rebirth.Pending).toEqual({ "FounderFennec" })
		expect(grants[1]).toEqual({ Player = p, NurseId = "FounderFennec", Price = 0, Source = "Gift" })
		local waits = false
		for _, t in toasts do
			waits = waits or t.Text == "🎁 A nurse waits for a free slot!"
		end
		expect(waits).toBe(true)
		expect(kinds(celebrations)).toEqual({ "Rebirth:5", "Unlock:FounderFennec", "Unlock:Mascot" })
		-- a slot frees up: ClaimBranchNurse
		rosterFull = false
		local ok = served.ClaimBranchNurse(p)
		expect(ok).toBe(true)
		expect(saves[p].Nurses.FounderFennec ~= nil).toBe(true)
		expect(saves[p].Rebirth.Pending).toEqual({})
		local again, why = served.ClaimBranchNurse(p)
		expect(again).toBe(false)
		expect(why).toBe("🎁 No gift waiting!")
	end)

	test("a gift already on the roster just clears", function()
		clearLogs()
		local data = richSave()
		data.Rebirth.Pending = { "FounderFennec" }
		data.Nurses.FounderFennec = { Level = 3, XP = 0, Copies = 1, Job = "" }
		local p = fresh("Kit", data)
		local ok, why = served.ClaimBranchNurse(p)
		expect(ok).toBe(true)
		expect(why).toBe("🎁 Already yours!")
		expect(saves[p].Rebirth.Pending).toEqual({})
		expect(saves[p].Nurses.FounderFennec.Level).toBe(3)
		expect(#grants).toBe(0)
	end)
end)

T.describe("Server/Rebirth ChoosePerk", function()
	test("a card not offered fails and changes nothing", function()
		clearLogs()
		local data = richSave()
		data.Rebirth.Offer = { "BusyDoors", "WarmUp", "NightOwl" }
		local p = fresh("Lu", data)
		local before = deepCopy(saves[p])
		for _, junk in { "BathReady", "TreePoints", "Order", "", 42, nil, {}, string.rep("x", 80) } do
			local ok = served.ChoosePerk(p, junk)
			expect(ok).toBe(false)
			expect(saves[p]).toEqual(before)
		end
		expect(#celebrations).toBe(0)
	end)

	test("an offered card is kept, the offer clears, and it can't be chosen twice", function()
		clearLogs()
		local data = richSave()
		data.Rebirth.Offer = { "BusyDoors", "WarmUp", "NightOwl" }
		local p = fresh("Max", data)
		local ok, reply = served.ChoosePerk(p, "WarmUp")
		expect(ok).toBe(true)
		expect(reply).toBe("⚡ Warm Up!")
		expect(saves[p].Rebirth.Perks).toEqual({ "WarmUp" })
		expect(saves[p].Rebirth.Offer).toEqual({})
		expect(saves[p].Upgrades.Speed).toBe(5) -- already above Warm Up's 2: kept
		expect(celebrations[1].Info).toEqual({ Kind = "Perk", Title = "Warm Up", Icon = "⚡", Perk = "WarmUp" })
		expect(served.ChoosePerk(p, "BusyDoors")).toBe(false)
		expect(saves[p].Rebirth.Perks).toEqual({ "WarmUp" })
	end)

	test("🛁 Bath Ready owns the room now and syncs the plot", function()
		clearLogs()
		local data = richSave()
		data.Rooms = { Stand = true }
		data.Rebirth.Offer = { "BathReady", "SeedMoney", "BigHands" }
		local p = fresh("Nia", data)
		expect(served.ChoosePerk(p, "BathReady")).toBe(true)
		expect(saves[p].Rooms.BathRoom).toBe(true)
		expect(synced).toBe(1)
	end)

	test("the Fallback card adds tree points", function()
		clearLogs()
		local data = richSave()
		data.Rebirth.Offer = { "TreePoints" }
		data.Rebirth.Points = 1
		local p = fresh("Oz", data)
		local ok, reply = served.ChoosePerk(p, "TreePoints")
		expect(ok).toBe(true)
		expect(reply).toBe("🌳 +2 tree points!")
		expect(saves[p].Rebirth.Points).toBe(3)
		expect(saves[p].Rebirth.Perks).toEqual({})
	end)
end)

T.describe("Server/Rebirth tree and themes", function()
	test("the tree buy/refund round trip", function()
		clearLogs()
		local data = richSave()
		data.Rebirth.Points = 8
		local p = fresh("Pia", data)
		for rank = 1, 3 do
			local ok, reply = served.BuyNode(p, "GentleWords")
			expect(ok).toBe(true)
			expect(reply).toBe("💺 Gentle Words " .. rank .. "!")
		end
		expect(saves[p].Rebirth.Points).toBe(5)
		local ok, why = served.BuyNode(p, "GentleWords")
		expect(ok).toBe(false)
		expect(why).toBe("Max rank!")
		ok, why = served.BuyNode(p, "TwinCounters")
		expect(ok).toBe(false)
		expect(why).toBe("Need 6 🌳 in Care")
		for _ = 1, 3 do
			expect(served.BuyNode(p, "ThankYou")).toBe(true)
		end
		expect(saves[p].Rebirth.Points).toBe(2)
		ok, why = served.BuyNode(p, "TwinCounters")
		expect(ok).toBe(true)
		expect(why).toBe("👯 Twin Counters!")
		expect(saves[p].Rebirth.Points).toBe(0)
		ok, why = served.BuyNode(p, "QuickFeet")
		expect(ok).toBe(false)
		expect(why).toBe("Need 🌳1")
		expect(saves[p].Rebirth.Tree).toEqual({ GentleWords = 3, ThankYou = 3, TwinCounters = 1 })
		-- reset: free, every point back
		ok, why = served.ResetTree(p)
		expect(ok).toBe(true)
		expect(why).toBe("🔄 Tree reset! 🌳8 back")
		expect(saves[p].Rebirth.Points).toBe(8)
		expect(saves[p].Rebirth.Tree).toEqual({})
		ok, why = served.ResetTree(p)
		expect(ok).toBe(false)
		expect(why).toBe("🌳 Nothing to reset!")
	end)

	test("reset: 2 s per player; unknown nodes are refunded too", function()
		clearLogs()
		local data = richSave()
		data.Rebirth.Points = 2
		data.Rebirth.Tree = { OldNode = 2 }
		local p = fresh("Quin", data)
		expect(served.ResetTree(p)).toBe(true)
		expect(saves[p].Rebirth.Points).toBe(4)
		expect(served.BuyNode(p, "LuckyCoins")).toBe(true)
		now += 1
		local ok, why = served.ResetTree(p)
		expect(ok).toBe(false)
		expect(why).toBe("Too fast! Try again.")
		now += 2
		expect(served.ResetTree(p)).toBe(true)
		expect(saves[p].Rebirth.Points).toBe(4)
	end)

	test("junk nodes change nothing", function()
		clearLogs()
		local data = richSave()
		data.Rebirth.Points = 5
		local p = fresh("Rae", data)
		local before = deepCopy(saves[p])
		for _, junk in { "Order", "Nodes", "Care", "", 7, nil, { "QuickFeet" }, string.rep("Q", 99) } do
			expect(served.BuyNode(p, junk)).toBe(false)
			expect(saves[p]).toEqual(before)
		end
	end)

	test("👟 Quick Feet sets WalkBoost", function()
		clearLogs()
		local data = richSave()
		data.Rebirth.Points = 3
		local p = fresh("Sam", data)
		expect(served.BuyNode(p, "QuickFeet")).toBe(true)
		expect(served.BuyNode(p, "QuickFeet")).toBe(true)
		expect(p:GetAttribute("WalkBoost")).toBe(2)
		now += 5
		expect(served.ResetTree(p)).toBe(true)
		expect(p:GetAttribute("WalkBoost")).toBe(0)
	end)

	test("themes: only ones unlocked at your count", function()
		clearLogs()
		local data = richSave()
		data.Rebirth.Count = 2
		local p = fresh("Tia", data)
		local ok, reply = served.SetTheme(p, "Jungle")
		expect(ok).toBe(true)
		expect(reply).toBe("🌴 Jungle look!")
		expect(saves[p].Rebirth.Theme).toBe("Jungle")
		local before = deepCopy(saves[p])
		local why
		ok, why = served.SetTheme(p, "Space")
		expect(ok).toBe(false)
		expect(why).toBe("Needs 🏢 R3")
		for _, junk in { "Order", "Default", "", 3, nil } do
			expect(served.SetTheme(p, junk)).toBe(false)
		end
		expect(saves[p]).toEqual(before)
		expect(served.SetTheme(p, "Candy")).toBe(true)
		expect(saves[p].Rebirth.Theme).toBe("Candy")
	end)

	test("admin +3 tree points", function()
		clearLogs()
		local p = fresh("Uma")
		local ok, reply = Rebirth.adminPoints(p)
		expect(ok).toBe(true)
		expect(reply).toBe("🌳 +3 tree points!")
		expect(saves[p].Rebirth.Points).toBe(3)
	end)
end)

T.describe("Server/Rebirth the one gentle toast", function()
	test("once, the first time a branch could open; never again", function()
		clearLogs()
		local data = richSave()
		data.Cash = 49000
		local p = fresh("Vic", data)
		PlayerData.update(p, function(d)
			d.Cash += 500
		end)
		task.wait()
		expect(#toasts).toBe(0)
		PlayerData.update(p, function(d)
			d.Cash += 500
		end)
		task.wait()
		expect(#toasts).toBe(1)
		expect(toasts[1].Text).toBe("🏢 You can open a branch!")
		expect(saves[p].Rebirth.Told).toBe(true)
		PlayerData.update(p, function(d)
			d.Cash += 5000
		end)
		task.wait()
		expect(#toasts).toBe(1)
	end)

	test("never during the tutorial", function()
		clearLogs()
		local data = richSave()
		data.Tutorial = 5
		local p = fresh("Wes", data)
		PlayerData.update(p, function(d)
			d.Cash += 1
		end)
		task.wait()
		expect(#toasts).toBe(0)
		expect(saves[p].Rebirth.Told).toBe(false)
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- Server/Economy: the upgrade gates
------------------------------------------------------------------------------------------------------------------

local Economy = load(
	ROOT .. "Economy.luau",
	{
		PlayerData = PlayerData,
		Plots = { getPlot = function() end, decorSlot = function() end },
	},
	SHARED,
	{
		Players = Players,
		Workspace = {
			GetAttribute = function()
				return nil
			end,
		},
	}
)

T.describe("Server/Economy upgrade gates", function()
	test("Ward Comfort and A&E Speed need hospital Lv 2", function()
		local data = Schema.default()
		data.Cash = 100000
		local p = fresh("Xan", data)
		local ok, why = Economy.purchase(p, "Upgrade", "WardComfort")
		expect(ok).toBe(false)
		expect(why).toBe("Needs 🏥 Lv 2")
		ok, why = Economy.purchase(p, "Upgrade", "AESpeed")
		expect(why).toBe("Needs 🏥 Lv 2")
		expect(saves[p].Cash).toBe(100000)
		saves[p].Level = 2
		expect(Economy.purchase(p, "Upgrade", "WardComfort")).toBe(true)
		expect(saves[p].Upgrades.WardComfort).toBe(1)
		expect(saves[p].Cash).toBe(100000 - UpgradesData.WardComfort.Prices[1])
	end)

	test("Night Clinic needs R4, then sells like the others", function()
		local data = Schema.default()
		data.Cash = 100000
		data.Level = 5
		local p = fresh("Yul", data)
		local ok, why = Economy.purchase(p, "Upgrade", "NightClinic")
		expect(ok).toBe(false)
		expect(why).toBe("Needs 🏢 R4")
		expect(saves[p].Upgrades.NightClinic).toBe(0)
		saves[p].Rebirth.Count = 4
		for level = 1, #UpgradesData.NightClinic.Prices do
			expect(Economy.purchase(p, "Upgrade", "NightClinic")).toBe(true)
			expect(saves[p].Upgrades.NightClinic).toBe(level)
		end
		ok, why = Economy.purchase(p, "Upgrade", "NightClinic")
		expect(ok).toBe(false)
		expect(why).toBe("Maxed out! 🎉")
	end)

	test("ungated upgrades are unchanged", function()
		local data = Schema.default()
		data.Cash = 1000
		local p = fresh("Zed", data)
		expect(Economy.purchase(p, "Upgrade", "Speed")).toBe(true)
		expect(Economy.purchase(p, "Upgrade", "Order")).toBe(false)
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- Server/Carry: 🧺 Big Hands
------------------------------------------------------------------------------------------------------------------

local Carry = load(ROOT .. "Carry.luau", { PlayerData = PlayerData }, SHARED, { Players = Players })

T.describe("Server/Carry Big Hands", function()
	test("capacity = 1 + Bigger Tray + Big Hands; a rebirth keeps the card", function()
		local data = Schema.default()
		data.Upgrades.Tray = 2
		local p = fresh("Ada", data)
		expect(Carry.capacity(p)).toBe(3)
		saves[p].Rebirth.Perks = { "BigHands" }
		expect(Carry.capacity(p)).toBe(4)
		saves[p].Upgrades.Tray = 0 -- a rebirth reset Bigger Tray
		expect(Carry.capacity(p)).toBe(2)
		saves[p].Rebirth.Perks = {}
		expect(Carry.capacity(p)).toBe(1)
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- Server/Plots.syncRooms, on a small fake Instance tree
------------------------------------------------------------------------------------------------------------------

local states = setmetatable({}, { __mode = "k" })
local methods = {}
local function newInstance(class: string, name: string): any
	local state = { ClassName = class, Name = name, Parent = nil, Children = {}, Attributes = {}, Destroyed = false }
	local obj
	obj = setmetatable({}, {
		__index = function(_, key)
			if key == "__instance" then
				return true
			end
			if methods[key] then
				return methods[key]
			end
			return state[key]
		end,
		__newindex = function(_, key, value)
			if key == "Parent" then
				local old = state.Parent
				if old then
					local siblings = states[old].Children
					local index = table.find(siblings, obj)
					if index then
						table.remove(siblings, index)
					end
				end
				state.Parent = value
				if value then
					table.insert(states[value].Children, obj)
				end
			else
				state[key] = value
			end
		end,
	})
	states[obj] = state
	return obj
end
function methods:IsA(class)
	local own = states[self].ClassName
	return own == class or class == "Instance" or (class == "BasePart" and own == "Part")
end
function methods:GetChildren()
	return table.clone(states[self].Children)
end
function methods:GetDescendants()
	local out = {}
	for _, child in states[self].Children do
		table.insert(out, child)
		for _, below in child:GetDescendants() do
			table.insert(out, below)
		end
	end
	return out
end
function methods:FindFirstChild(name, recursive)
	for _, child in states[self].Children do
		if child.Name == name then
			return child
		end
	end
	if recursive then
		for _, child in states[self].Children do
			local found = child:FindFirstChild(name, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function methods:GetAttribute(key)
	return states[self].Attributes[key]
end
function methods:SetAttribute(key, value)
	states[self].Attributes[key] = value
end
function methods:Destroy()
	for _, child in states[self].Children do
		child:Destroy()
	end
	states[self].Destroyed = true
	self.Parent = nil
end
function methods:PivotTo() end
function methods:GetPivot()
	return roblox.CFrame.new()
end

local function child(parent: any, class: string, name: string): any
	local made = newInstance(class, name)
	if class == "Part" then
		made.CFrame = roblox.CFrame.new()
		made.Size = roblox.Vector3.new(2, 1, 2)
		made.Position = roblox.Vector3.new()
	end
	made.Parent = parent
	return made
end

local function roomModel(roomId: string): any
	local room = newInstance("Model", "Room_" .. roomId)
	room:SetAttribute("RoomId", roomId)
	child(room, "Part", "DecorSlot_1")
	return room
end

local plotModel = newInstance("Model", "Plot_1")
for _, name in { "Counter", "QueueStart", "PatientSpawn", "PatientExit" } do
	child(plotModel, "Part", name)
end
for _, name in { "Rooms", "Decor", "Patients", "Slots" } do
	child(plotModel, "Folder", name)
end
roomModel("Stand").Parent = plotModel:FindFirstChild("Rooms")

local placed: { string } = {}
local previews: { [string]: any } = {}
local PlotBuilder = {
	buildTown = function()
		return { plotModel }
	end,
	placeRoom = function(model, roomId)
		local folder = model:FindFirstChild("Rooms")
		local existing = folder:FindFirstChild("Room_" .. roomId)
		if existing then
			return existing
		end
		table.insert(placed, roomId)
		local room = roomModel(roomId)
		room.Parent = folder
		return room
	end,
	setPreview = function(_, slotId, roomId)
		previews[slotId] = roomId or false
	end,
	clearPlot = function() end,
}
local DecorBuilder = {
	build = function(decorId)
		local model = newInstance("Model", decorId)
		return model
	end,
}

local Plots = load(
	ROOT .. "Plots.luau",
	{
		PlayerData = PlayerData,
		PlotBuilder = PlotBuilder,
		DecorBuilder = DecorBuilder,
	},
	SHARED,
	{
		Players = Players,
		Workspace = {
			FindFirstChild = function()
				return nil
			end,
		},
	}
)

local function decorShown(): { [string]: string }
	local out = {}
	for _, model in plotModel:FindFirstChild("Decor"):GetChildren() do
		out[model:GetAttribute("SlotKey")] = model:GetAttribute("DecorId")
	end
	return out
end

local function roomsShown(): { string }
	local out = {}
	for _, room in plotModel:FindFirstChild("Rooms"):GetChildren() do
		table.insert(out, room:GetAttribute("RoomId"))
	end
	table.sort(out)
	return out
end

T.describe("Server/Plots.syncRooms", function()
	table.clear(Players.list) -- the earlier tests' players would take the one plot first
	Plots.start()
	local data = richSave()
	data.Decor.Placed["BathRoom:1"] = "HeartRug"
	local owner = fresh("Bo", data)
	PlayerData.Loaded:Fire(owner, data)
	task.wait()

	test("the plot starts with the save's rooms and decor", function()
		expect(Plots.getPlot(owner) ~= nil).toBe(true)
		expect(roomsShown()).toEqual({ "BathRoom", "Stand", "Ward" })
		local shown = decorShown()
		expect(shown).toEqual({ ["Stand:1"] = "PottedFern", ["Ward:1"] = "CozyRug", ["BathRoom:1"] = "HeartRug" })
	end)

	test("after a rebirth: rooms the save no longer owns go, with their decor; the Stand's stays", function()
		RebirthLogic.apply(
			saves[owner],
			Config,
			{},
			{ Perks = PerksData, Themes = ThemesData, Nurses = NursesData, Decor = DecorData }
		)
		local standDecor = plotModel:FindFirstChild("Decor"):GetChildren()
		local keptModel
		for _, model in standDecor do
			if model:GetAttribute("SlotKey") == "Stand:1" then
				keptModel = model
			end
		end
		Plots.syncRooms(owner)
		expect(roomsShown()).toEqual({ "Stand" })
		expect(decorShown()).toEqual({ ["Stand:1"] = "PottedFern" })
		expect(states[keptModel].Destroyed).toBe(false) -- not rebuilt, just kept
		expect(previews[RoomsData.Ward.Slot]).toBe("Ward") -- "for sale" again
		expect(previews[RoomsData.BathRoom.Slot]).toBe("BathRoom")
	end)

	test("🛁 Bath Ready: the room the save owns but the plot lacks appears", function()
		table.clear(placed)
		saves[owner].Rooms.BathRoom = true
		saves[owner].Decor.Placed["BathRoom:1"] = "HeartRug"
		Plots.syncRooms(owner)
		expect(placed).toEqual({ "BathRoom" })
		expect(roomsShown()).toEqual({ "BathRoom", "Stand" })
		expect(decorShown()).toEqual({ ["Stand:1"] = "PottedFern", ["BathRoom:1"] = "HeartRug" })
		expect(previews[RoomsData.BathRoom.Slot]).toBe(false)
		-- a second sync changes nothing
		Plots.syncRooms(owner)
		expect(placed).toEqual({ "BathRoom" })
		expect(roomsShown()).toEqual({ "BathRoom", "Stand" })
	end)

	test("someone without a plot, or not loaded: nothing happens", function()
		local stranger = newPlayer("Cam")
		Plots.syncRooms(stranger)
		expect(roomsShown()).toEqual({ "BathRoom", "Stand" })
	end)
end)
