--!nocheck
-- Sessions end to end (depth update T1; Real Clinic build plan, Task 5, Review Focus 3 and 4): the real
-- src/server/Treatment.luau runs under Lune with mocked Roblox services (Players, Remotes, Economy, PlayerData, Nurses,
-- Abilities) and the real Data/Items, Data/Tools and Logic/MiniGame. It checks the session lifecycle a cheating
-- client would poke at: one session per player AND per patient, junk / someone else's / stale ids refused with
-- nothing changed, a too-early report rated all OK, Simple mode, the distance check, the tip cap per patient, the
-- timeout, drop, the player leaving, and Healer routing. Progression v2: auto-Perfect sessions
-- (Abilities.consumePerfects), Ease from the tree, the Triage remote (right / wrong / junk / late / timeout) and Medic
-- routing. The Real Clinic: the three kinds (an Exam reveals its case whatever the ratings; a Treat plays one game per
-- supply and refuses a medicine; a Dispense gives only one of its own Options, before any tip, and nothing to a
-- player who left), Expert Dispensing's wider Dose band, and Server/Stations' pure dispensary rules (the card's
-- options, the tip ledger, the prompt's text).
-- Run from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local T = require("./expect")
local expect, test = T.expect, T.test

local Vector3 = roblox.Vector3
local warnings: { string } = {}

local function source(path: string): string
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("can't find " .. path .. " (run from game/)")
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
				fn(...)
			end
		end,
	}
end

local Players = { PlayerAdded = mockSignal(), PlayerRemoving = mockSignal(), list = {} }
function Players:GetPlayers()
	return self.list
end

local function newPlayer(name: string, at: Vector3?)
	local attributes = {}
	local p = {
		__instance = true,
		Name = name,
		Parent = Players,
		Character = {
			FindFirstChild = function(self, child)
				if child == "HumanoidRootPart" then
					return self.Root
				end
				return nil
			end,
			Root = {
				IsA = function(_, c)
					return c == "BasePart"
				end,
				Position = at or Vector3.new(0, 0, 0),
			},
		},
	}
	function p:IsA(class)
		return class == "Player"
	end
	function p:GetAttribute(k)
		return attributes[k]
	end
	function p:SetAttribute(k, v)
		attributes[k] = v
	end
	table.insert(Players.list, p)
	return p
end

local fired = {}
local served = {}
local toasts = {}
local Remotes = {
	OOPS = "Oops! Try again.",
	toast = function(player, text)
		table.insert(toasts, { Player = player, Text = text })
	end,
	TreatStart = {
		FireClient = function(_, player, payload)
			table.insert(fired, { Player = player, Payload = payload })
		end,
	},
	serve = function(name, handler)
		served[name] = handler
	end,
}

local cash = {}
local Economy = {
	addCash = function(player, amount)
		cash[player] = (cash[player] or 0) + amount
		return true
	end,
}
local saves = {}
local updates = 0 -- PlayerData.update calls that reached a save
local PlayerData = {
	get = function(player)
		return saves[player]
	end,
	update = function(player, fn)
		if not saves[player] then
			return false
		end
		updates += 1
		fn(saves[player])
		return true
	end,
}
local healed = {}
local cheerTip = 1
local Nurses = {
	Heal = mockSignal(),
	cheer = function()
		return { Patience = 1, Tip = cheerTip }
	end,
	healed = function(plot, nurseId, items)
		table.insert(healed, { Plot = plot, NurseId = nurseId, Items = items })
	end,
}

-- The shipped per-game tuning (Config.MiniGame.Games) and dispensary numbers; the rest is copied so the timeout
-- tests can shorten the session.
local Shipped = require("./config")
local Config = {
	MiniGame = {
		PerfectTip = 3,
		TipCapPerCure = 15,
		Combo = { { At = 3, Multiplier = 1.2 }, { At = 6, Multiplier = 1.5 }, { At = 10, Multiplier = 2 } },
		MinSeconds = { Pour = 1.2, Patch = 1, Scrub = 1.5, Cool = 1.5, Pick = 0.6 },
		SimpleMinSeconds = 0.25,
		Slack = 0.8,
		SessionSeconds = 12,
		PerGameSeconds = 6,
		Games = Shipped.MiniGame.Games,
	},
	Treat = { ItemPatience = 0.25, Distance = 20 },
	Triage = { Seconds = 4, RightBonus = 0.1 },
	Dispensary = Shipped.Dispensary,
}
local MiniGame = require("../src/shared/Logic/MiniGame")
local RebirthLogic = require("../src/shared/Logic/Rebirth")
local PerksData = require("../src/shared/Data/Perks")
local TreeData = require("../src/shared/Data/Tree")
local ItemsData = require("../src/shared/Data/Items")
local ToolsData = require("../src/shared/Data/Tools")

-- Abilities: what a banked AutoPerfect makes PERFECT (the test sets `autoNext`; each ask spends it).
local autoNext: { boolean }? = nil
local perfectAsks = 0
local Abilities = {
	consumePerfects = function(_plot, games)
		perfectAsks += 1
		local flags = autoNext or {}
		autoNext = nil
		local out = {}
		for index in games do
			out[index] = flags[index] == true
		end
		return out
	end,
}

local now = 100
local fakeOs = setmetatable({
	clock = function()
		return now
	end,
}, { __index = os })

local Shared = {
	Config = "Config",
	Remotes = "Remotes",
	Types = "Types",
	Logic = { MiniGame = "MiniGame", Rebirth = "RebirthLogic" },
	Data = { Perks = "PerksData", Tree = "TreeData", Items = "ItemsData", Tools = "ToolsData" },
}
local modules = {
	Config = Config,
	Remotes = Remotes,
	Types = {},
	MiniGame = MiniGame,
	RebirthLogic = RebirthLogic,
	PerksData = PerksData,
	TreeData = TreeData,
	ItemsData = ItemsData,
	ToolsData = ToolsData,
	Abilities = Abilities,
	Economy = Economy,
	PlayerData = PlayerData,
	Nurses = Nurses,
}
local env = {
	game = {
		GetService = function(_, name)
			if name == "Players" then
				return Players
			end
			return { Shared = Shared }
		end,
	},
	script = {
		Parent = { Economy = "Economy", PlayerData = "PlayerData", Nurses = "Nurses", Abilities = "Abilities" },
	},
	require = function(token)
		return assert(modules[token], "no mock for " .. tostring(token))
	end,
	typeof = function(v)
		if type(v) == "table" and v.__instance then
			return "Instance"
		end
		return typeof(v)
	end,
	task = task,
	os = fakeOs,
	warn = function(...)
		table.insert(warnings, table.concat({ ... }, " ")) -- kept quiet: the suite's output stays PASS/FAIL
	end,
}
local Treatment =
	luau.load(source("src/server/Treatment.luau"), { debugName = "Server/Treatment", environment = env })()
Treatment.start()
local TreatResult = served.TreatResult
local SetSimple = served.SetSimple
local Triage = served.Triage

local function pureBlock(path: string, globals: { [string]: any }): any
	local text = source(path)
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to and to > from, path .. ": no PURE block")
	local block = string.sub(text, from, to - 1) .. "\nreturn Pure\n"
	return luau.load(block, { debugName = path .. " (pure)", environment = globals })()
end
local TrPure = pureBlock("src/server/Treatment.luau", { MiniGame = MiniGame })
local StPure = pureBlock("src/server/Stations.luau", {})

local plot = { Index = 1 }
local function spec(items, settled)
	return {
		Plot = plot,
		PatientId = "Puffle",
		Items = items,
		Position = Vector3.new(0, 3, 0),
		Counter = Vector3.new(0, 0, 0),
		TipSoFar = 0,
		Settle = function(ratings, tip)
			table.insert(settled, { Ratings = ratings, Tip = tip })
			return #items == 1
		end,
	}
end

-- Tests ----------------------------------------------------------------------------------------------------------
T.describe("Treatment sessions (mocked)", function()
	test("open fires TreatStart with one game per supply and the timeout", function()
		local a = newPlayer("A")
		saves[a] = { Simple = false }
		local settled = {}
		local id = Treatment.open(a, spec({ "Bubbles", "Ice" }, settled))
		expect(type(id)).toBe("number")
		local last = fired[#fired]
		expect(last.Player).toBe(a)
		expect(last.Payload.Session).toBe(id)
		expect(last.Payload.Kind).toBe("Treat")
		expect(last.Payload.Games).toEqual({ "Bath", "Ice" })
		expect(last.Payload.Items).toEqual({ "Bubbles", "Ice" })
		expect(last.Payload.Simple).toBe(false)
		expect(last.Payload.Combo).toBe(0)
		expect(last.Payload.Timeout).toBe(24)
		expect(Treatment.busy(a)).toBe(true)
		expect(Treatment.open(a, spec({ "Ice" }, settled))).toBe(nil) -- one at a time
		Treatment.drop(id)
		expect(Treatment.busy(a)).toBe(false)
	end)

	test("junk, someone else's and stale sessions are refused and change nothing", function()
		local a, b = newPlayer("A2"), newPlayer("B2")
		saves[a], saves[b] = { Simple = false }, { Simple = false }
		local settledA, settledB = {}, {}
		local idA = Treatment.open(a, spec({ "Ice" }, settledA))
		local idB = Treatment.open(b, spec({ "Ice" }, settledB))
		for _, junk in { "1", nil, 1.5, 0 / 0, math.huge, {}, -1, idB } do
			local ok, message, payload = TreatResult(a, junk, { "Perfect" })
			expect(ok).toBe(false)
			expect(message).toBe(Remotes.OOPS)
			expect(payload).toBe(nil)
		end
		expect(#settledA).toBe(0)
		expect(#settledB).toBe(0)
		expect(Treatment.busy(a)).toBe(true)
		expect(cash[a]).toBe(nil)
		Treatment.drop(idA)
		Treatment.drop(idB)
	end)

	test("an honest Perfect pays a small tip once; a second report is refused", function()
		local a = newPlayer("A3")
		saves[a] = { Simple = false }
		local settled = {}
		local id = Treatment.open(a, spec({ "Ice" }, settled))
		now += 1.0 -- Ice min 1.2 x 0.8 = 0.96
		local ok, _, outcome = TreatResult(a, id, { "Perfect" })
		expect(ok).toBe(true)
		expect(outcome.Ratings).toEqual({ "Perfect" })
		expect(outcome.Tip).toBe(3)
		expect(outcome.Combo).toBe(1)
		expect(outcome.Complete).toBe(true)
		expect(outcome.Case).toBe(nil) -- only an Exam reveals a case
		expect(outcome.Item).toBe(nil) -- only a Dispense puts something in your hands
		expect(a:GetAttribute("Combo")).toBe(1)
		expect(cash[a]).toBe(3)
		expect(#settled).toBe(1)
		local again = TreatResult(a, id, { "Perfect" })
		expect(again).toBe(false)
		expect(#settled).toBe(1)
		expect(cash[a]).toBe(3)
	end)

	test("a report 0.1 s after the start is all OK: no tip, combo reset", function()
		local a = newPlayer("A4")
		saves[a] = { Simple = false }
		a:SetAttribute("Combo", 4)
		local settled = {}
		local id = Treatment.open(a, spec({ "Ice", "Plaster" }, settled))
		now += 0.1
		local ok, _, outcome = TreatResult(a, id, { "Perfect", "Perfect" })
		expect(ok).toBe(true)
		expect(outcome.Ratings).toEqual({ "OK", "OK" })
		expect(outcome.Tip).toBe(0)
		expect(outcome.Combo).toBe(0)
		expect(outcome.Complete).toBe(false)
		expect(cash[a]).toBe(nil)
	end)

	test("SetSimple to what it already is: ok, but no save write", function()
		local a = newPlayer("A5b")
		saves[a] = { Simple = false }
		local before = updates
		expect(SetSimple(a, false)).toBe(true)
		expect(updates).toBe(before)
		expect(SetSimple(a, true)).toBe(true)
		expect(updates).toBe(before + 1)
		expect(SetSimple(a, true)).toBe(true)
		expect(updates).toBe(before + 1)
		expect(saves[a].Simple).toBe(true)
	end)

	test("Simple mode: all Good whatever is reported, no tip", function()
		local a = newPlayer("A5")
		saves[a] = { Simple = false }
		expect(SetSimple(a, "yes")).toBe(false)
		expect(SetSimple(a, nil)).toBe(false)
		expect(SetSimple(a, true)).toBe(true)
		expect(saves[a].Simple).toBe(true)
		local settled = {}
		local id = Treatment.open(a, spec({ "Cocoa" }, settled))
		expect(fired[#fired].Payload.Simple).toBe(true)
		now += 0.3
		local ok, _, outcome = TreatResult(a, id, { "Perfect" })
		expect(ok).toBe(true)
		expect(outcome.Ratings).toEqual({ "Good" })
		expect(outcome.Tip).toBe(0)
	end)

	test("from far from the bay: all OK", function()
		local a = newPlayer("A6", Vector3.new(0, 0, 30))
		saves[a] = { Simple = false }
		local settled = {}
		local id = Treatment.open(a, spec({ "Ice" }, settled))
		now += 5
		local _, _, outcome = TreatResult(a, id, { "Perfect" })
		expect(outcome.Ratings).toEqual({ "OK" })
		expect(outcome.Tip).toBe(0)
	end)

	test("the tip is capped per patient, with a Cheerer and a big combo", function()
		local a = newPlayer("A7")
		saves[a] = { Simple = false }
		a:SetAttribute("Combo", 20)
		cheerTip = 99 -- junk-big: capped
		local s = spec({ "Ice", "Plaster", "Ice" }, {})
		s.TipSoFar = 10
		local id = Treatment.open(a, s)
		now += 10
		local _, _, outcome = TreatResult(a, id, { "Perfect", "Perfect", "Perfect" })
		expect(outcome.Tip).toBe(5) -- 15 - 10 already paid
		cheerTip = 1
	end)

	test("the timeout settles all OK by itself; a late report is refused", function()
		local a = newPlayer("A8")
		saves[a] = { Simple = false }
		Config.MiniGame.SessionSeconds, Config.MiniGame.PerGameSeconds = 0.05, 0
		local settled = {}
		local id = Treatment.open(a, spec({ "Ice" }, settled))
		Config.MiniGame.SessionSeconds, Config.MiniGame.PerGameSeconds = 12, 6
		task.wait(0.15)
		expect(#settled).toBe(1)
		expect(settled[1].Ratings).toEqual({ "OK" })
		expect(Treatment.busy(a)).toBe(false)
		expect(TreatResult(a, id, { "Perfect" })).toBe(false)
		expect(#settled).toBe(1)
	end)

	test("drop: never settles, refuses the report, and the timer is gone", function()
		local a = newPlayer("A9")
		saves[a] = { Simple = false }
		Config.MiniGame.SessionSeconds, Config.MiniGame.PerGameSeconds = 0.05, 0
		local settled = {}
		local id = Treatment.open(a, spec({ "Ice" }, settled))
		Config.MiniGame.SessionSeconds, Config.MiniGame.PerGameSeconds = 12, 6
		Treatment.drop(id)
		task.wait(0.15)
		expect(#settled).toBe(0)
		expect(TreatResult(a, id, { "OK" })).toBe(false)
	end)

	test("the player leaves mid-game: settled all OK, no tip, combo kept", function()
		local a = newPlayer("A10")
		saves[a] = { Simple = false }
		a:SetAttribute("Combo", 5)
		local settled = {}
		Treatment.open(a, spec({ "Ice" }, settled))
		Players.PlayerRemoving:Fire(a)
		expect(#settled).toBe(1)
		expect(settled[1].Ratings).toEqual({ "OK" })
		expect(settled[1].Tip).toBe(0)
		expect(a:GetAttribute("Combo")).toBe(5)
		expect(Treatment.busy(a)).toBe(false)
	end)

	test("a Settle that errors still answers, and the session is closed", function()
		local a = newPlayer("A11")
		saves[a] = { Simple = false }
		local s = spec({ "Ice" }, {})
		s.Settle = function()
			error("boom")
		end
		local id = Treatment.open(a, s)
		now += 2
		local ok, _, outcome = TreatResult(a, id, { "Good" })
		expect(ok).toBe(true)
		expect(outcome.Complete).toBe(false)
		expect(Treatment.busy(a)).toBe(false)
	end)

	test("Healers: Nurses.Heal -> the Patients handler -> Nurses.healed only when something was given", function()
		local calls = 0
		local give: { string } = {}
		Treatment.onHeal(function(p, nurseId)
			calls += 1
			expect(p).toBe(plot)
			expect(nurseId).toBe("MintMouse")
			return give
		end)
		Nurses.Heal:Fire(plot, "MintMouse")
		expect(calls).toBe(1)
		expect(#healed).toBe(0)
		give = { "Ice" }
		Nurses.Heal:Fire(plot, "MintMouse")
		expect(#healed).toBe(1)
		expect(healed[1].Items).toEqual({ "Ice" })
		Nurses.Heal:Fire(plot, 42) -- junk id: ignored
		Nurses.Heal:Fire("plot", "MintMouse") -- junk plot: ignored
		expect(calls).toBe(2)
	end)
end)

-- Progression v2 (T7) ----------------------------------------------------------------------------------------------
local function triageSpec(items, settled, ask, complete)
	local s = spec(items, settled)
	s.Settle = function(ratings, tip)
		table.insert(settled, { Ratings = ratings, Tip = tip })
		return complete ~= false, ask
	end
	return s
end
local REST_ASK = { Options = { "Wards", "Rest" }, Right = "Rest" }

T.describe("Treatment v2 (mocked)", function()
	test("auto-Perfect: the ability's games are Perfect whatever is reported; the minimum time skips them", function()
		local a = newPlayer("V1")
		saves[a] = { Simple = false }
		autoNext = { true, false }
		local asks = perfectAsks
		local settled = {}
		local id = Treatment.open(a, spec({ "Plaster", "Ice" }, settled))
		expect(perfectAsks).toBe(asks + 1)
		local payload = fired[#fired].Payload
		expect(payload.Games).toEqual({ "Plaster", "Ice" })
		expect(payload.Auto).toEqual({ true, false })
		expect(payload.Kind).toBe("Treat")
		now += 1.0 -- Ice alone: 1.2 x 0.8 = 0.96 s (with Plaster it would need 1.76 s)
		local ok, _, outcome = TreatResult(a, id, { "OK", "Perfect" })
		expect(ok).toBe(true)
		expect(outcome.Ratings).toEqual({ "Perfect", "Perfect" })
		expect(outcome.Tip).toBe(6) -- two Perfects, combo 1 and 2: 3 + 3
	end)

	test("auto-Perfect survives a timeout (the ability was spent); other games are OK", function()
		local a = newPlayer("V2")
		saves[a] = { Simple = false }
		autoNext = { false, true }
		Config.MiniGame.SessionSeconds, Config.MiniGame.PerGameSeconds = 0.05, 0
		local settled = {}
		Treatment.open(a, spec({ "Ice", "Plaster" }, settled))
		Config.MiniGame.SessionSeconds, Config.MiniGame.PerGameSeconds = 12, 6
		task.wait(0.15)
		expect(#settled).toBe(1)
		expect(settled[1].Ratings).toEqual({ "OK", "Perfect" })
	end)

	test("a Treat with a medicine or an unknown item is refused (a medicine is handed over with no game)", function()
		local a = newPlayer("V3")
		saves[a] = { Simple = false }
		local before = #fired
		expect(Treatment.open(a, spec({ "CoughSyrup" }, {}))).toBe(nil)
		expect(Treatment.open(a, spec({ "Plaster", "PainRelief" }, {}))).toBe(nil)
		expect(Treatment.open(a, spec({ "Mystery" }, {}))).toBe(nil)
		expect(Treatment.open(a, spec({ "Order" }, {}))).toBe(nil)
		expect(Treatment.open(a, spec({}, {}))).toBe(nil) -- a Treat needs supplies
		expect(#fired).toBe(before)
		expect(Treatment.busy(a)).toBe(false)
	end)

	test("an unknown Kind (the old hot tub's Soak too) or a missing Settle is refused", function()
		local a = newPlayer("V3b")
		saves[a] = { Simple = false }
		local s = spec({ "Ice" }, {})
		s.Kind = "Soak"
		expect(Treatment.open(a, s)).toBe(nil)
		s.Kind = 7
		expect(Treatment.open(a, s)).toBe(nil)
		local t = spec({ "Ice" }, {})
		t.Settle = nil
		expect(Treatment.open(a, t)).toBe(nil)
		expect(Treatment.busy(a)).toBe(false)
	end)

	test("Ease: the player's own 🎯 Steady Hands (1 without, 1.3 at three ranks)", function()
		local a, b = newPlayer("V4a"), newPlayer("V4b")
		saves[a] = { Simple = false }
		saves[b] = { Simple = false, Rebirth = { Tree = { SteadyHands = 3 }, Perks = {} } }
		local idA = Treatment.open(a, spec({ "Ice" }, {}))
		expect(fired[#fired].Payload.Ease).toBe(1)
		local idB = Treatment.open(b, spec({ "Ice" }, {}))
		expect(fired[#fired].Payload.Ease).toBeCloseTo(1.3)
		Treatment.drop(idA)
		Treatment.drop(idB)
	end)

	test("Triage: a right pick, once; waitTriage answers it", function()
		local a = newPlayer("V6")
		saves[a] = { Simple = false }
		expect(Triage(a, 1, "Rest")).toBe(false) -- nothing pending yet
		local id = Treatment.open(a, triageSpec({ "Bubbles" }, {}, REST_ASK))
		now += 2
		local ok, _, outcome = TreatResult(a, id, { "Good" })
		expect(ok).toBe(true)
		expect(outcome.Complete).toBe(true)
		expect(outcome.Triage).toEqual({ Options = { "Wards", "Rest" }, Seconds = 4 })
		local picked, message, payload = Triage(a, id, "Rest")
		expect(picked).toBe(true)
		expect(message).toBe("✅ Right floor!")
		expect(payload).toEqual({ Right = true })
		expect(Triage(a, id, "Rest")).toBe(false) -- once
		expect(Treatment.waitTriage(a, id, REST_ASK.Options, "Rest")).toBe("Rest")
	end)

	test("Triage: junk and someone else's are refused; a wrong pick says Oops (it still goes the right way)", function()
		local a, b = newPlayer("V7a"), newPlayer("V7b")
		saves[a], saves[b] = { Simple = false }, { Simple = false }
		local id = Treatment.open(a, triageSpec({ "Bubbles" }, {}, REST_ASK))
		now += 2
		TreatResult(a, id, { "Good" })
		for _, call in { { id, "Roof" }, { id, 7 }, { id + 1, "Wards" }, { "1", "Wards" }, { 0 / 0, "Wards" } } do
			local okJunk, messageJunk = Triage(a, call[1], call[2])
			expect(okJunk).toBe(false)
			expect(messageJunk).toBe(Remotes.OOPS)
		end
		expect(Triage(b, id, "Rest")).toBe(false) -- not b's patient
		local ok, message, payload = Triage(a, id, "Wards")
		expect(ok).toBe(true)
		expect(message).toBe("Oops, not this floor!")
		expect(payload).toEqual({ Right = false })
		expect(Treatment.waitTriage(a, id, REST_ASK.Options, "Rest")).toBe("Wards")
	end)

	test("Triage: no pick in time -> waitTriage answers '' and a late pick is refused", function()
		local a = newPlayer("V8")
		saves[a] = { Simple = false }
		local id = Treatment.open(a, triageSpec({ "Bubbles" }, {}, REST_ASK))
		now += 2
		TreatResult(a, id, { "Good" })
		local answer = nil
		task.spawn(function()
			answer = Treatment.waitTriage(a, id, REST_ASK.Options, "Rest")
		end)
		expect(answer).toBe(nil) -- still waiting for the pick
		now += 5 -- past Config.Triage.Seconds
		task.wait(0.25)
		expect(answer).toBe("")
		expect(Triage(a, id, "Rest")).toBe(false)
	end)

	test("Triage: only the player's own report asks; a timeout or an unfinished plan asks nobody", function()
		local a = newPlayer("V9")
		saves[a] = { Simple = false }
		Config.MiniGame.SessionSeconds, Config.MiniGame.PerGameSeconds = 0.05, 0
		local id = Treatment.open(a, triageSpec({ "Bubbles" }, {}, REST_ASK))
		Config.MiniGame.SessionSeconds, Config.MiniGame.PerGameSeconds = 12, 6
		task.wait(0.15)
		expect(Treatment.waitTriage(a, id, REST_ASK.Options, "Rest")).toBe("")
		expect(Triage(a, id, "Rest")).toBe(false)
		local id2 = Treatment.open(a, triageSpec({ "Bubbles" }, {}, REST_ASK, false))
		now += 2
		local _, _, outcome = TreatResult(a, id2, { "Good" })
		expect(outcome.Complete).toBe(false)
		expect(outcome.Triage).toBe(nil)
		-- A broken ask (one option, or a Right that isn't one) asks nothing.
		local id3 = Treatment.open(a, triageSpec({ "Bubbles" }, {}, { Options = { "Wards" }, Right = "Wards" }))
		now += 2
		local _, _, outcome3 = TreatResult(a, id3, { "Good" })
		expect(outcome3.Triage).toBe(nil)
	end)

	test("Medics: Nurses.Heal target Urgent reaches Patients as Urgent; anything else is Front", function()
		local targets = {}
		Treatment.onHeal(function(_p, _nurseId, target)
			table.insert(targets, target)
			return {}
		end)
		Nurses.Heal:Fire(plot, "CuddleCub", "Urgent")
		Nurses.Heal:Fire(plot, "MintMouse", "Front")
		Nurses.Heal:Fire(plot, "MintMouse", "junk")
		Nurses.Heal:Fire(plot, "MintMouse")
		expect(targets).toEqual({ "Urgent", "Front", "Front", "Front" })
	end)
end)

-- The Real Clinic (Task 5) ---------------------------------------------------------------------------------------
local function examSpec(key, settled, case)
	local s = spec({}, settled)
	s.Kind = "Exam"
	s.Key = key
	s.Tools = { "Magnifier", "Stethoscope", "Light" }
	s.Answer = "Stethoscope"
	s.Glow = true
	s.Case = case or "Cough"
	s.Settle = function(ratings, tip)
		table.insert(settled, { Ratings = ratings, Tip = tip })
		return false
	end
	return s
end

-- A Dispense spec as Server/Stations builds it. `gives` records each Give; `answer` is what Give says.
local function dispenseSpec(options, gives, answer)
	return {
		Plot = plot,
		PatientId = "",
		Kind = "Dispense",
		Items = {},
		Position = Vector3.new(0, 3, 0),
		Counter = Vector3.new(0, 0, 0),
		TipSoFar = 0,
		Options = options,
		Give = function(itemId)
			table.insert(gives, itemId)
			local result = answer or { true, true }
			return result[1], result[2]
		end,
	}
end

T.describe("Real Clinic sessions (mocked)", function()
	test("an Exam: Pick the tool, then the answer tool's own game; the case is never sent ahead", function()
		local a = newPlayer("R1")
		saves[a] = { Simple = false }
		local id = Treatment.open(a, examSpec(101, {}))
		expect(type(id)).toBe("number")
		local payload = fired[#fired].Payload
		expect(payload.Kind).toBe("Exam")
		expect(payload.Games).toEqual({ "Pick", "Listen" })
		expect(payload.Tools).toEqual({ "Magnifier", "Stethoscope", "Light" })
		expect(payload.Answer).toBe("Stethoscope")
		expect(payload.Glow).toBe(true)
		expect(payload.Items).toEqual({})
		expect(payload.Case).toBe(nil)
		expect(payload.Options).toBe(nil)
		expect(payload.Timeout).toBe(24)
		Treatment.drop(id)
	end)

	test("Exam settle with any ratings reveals the case", function()
		local a = newPlayer("R2")
		saves[a] = { Simple = false }
		for _, report in { { "Perfect", "Perfect" }, { "OK", "OK" }, "Perfect", {}, nil } do
			local settled = {}
			local id = Treatment.open(a, examSpec(102, settled, "Earache"))
			now += 3
			local ok, _, outcome = TreatResult(a, id, report)
			expect(ok).toBe(true)
			expect(outcome.Case).toBe("Earache")
			expect(outcome.Item).toBe(nil)
			expect(#settled).toBe(1) -- Patients marked the case found
		end
		-- ... a report that came far too soon too (rated all OK, still revealed)
		local settled = {}
		local id = Treatment.open(a, examSpec(102, settled, "Fever"))
		now += 0.1
		local _, _, outcome = TreatResult(a, id, { "Perfect", "Perfect" })
		expect(outcome.Ratings).toEqual({ "OK", "OK" })
		expect(outcome.Case).toBe("Fever")
	end)

	test("a second Exam open on a patient already in a session is refused (Review Focus 3)", function()
		local a, b = newPlayer("R3a"), newPlayer("R3b")
		saves[a], saves[b] = { Simple = false }, { Simple = false }
		local idA = Treatment.open(a, examSpec(7, {}))
		expect(type(idA)).toBe("number")
		expect(Treatment.working(7)).toBe(true)
		local before = #fired
		expect(Treatment.open(b, examSpec(7, {}))).toBe(nil) -- the helper taps Examine too: refused
		local treat = spec({ "Ice" }, {})
		treat.Key = 7
		expect(Treatment.open(b, treat)).toBe(nil) -- nor a Treat on that patient
		expect(#fired).toBe(before)
		expect(Treatment.busy(b)).toBe(false)
		local idB = Treatment.open(b, examSpec(8, {})) -- another patient: fine
		expect(type(idB)).toBe("number")
		now += 3
		TreatResult(a, idA, { "Good", "Good" })
		expect(Treatment.working(7)).toBe(false)
		Treatment.drop(idB)
		local again = Treatment.open(b, examSpec(7, {}))
		expect(type(again)).toBe("number") -- free again
		expect(Treatment.working(nil)).toBe(false)
		-- ids may restart per plot: patient 7 at another clinic is someone else
		local elsewhere = examSpec(7, {})
		elsewhere.Plot = { Index = 2 }
		local idC = Treatment.open(a, elsewhere)
		expect(type(idC)).toBe("number")
		expect(Treatment.working(7, plot)).toBe(true)
		expect(Treatment.working(7, elsewhere.Plot)).toBe(true)
		Treatment.drop(again)
		expect(Treatment.working(7, plot)).toBe(false)
		expect(Treatment.working(7, elsewhere.Plot)).toBe(true)
		Treatment.drop(idC)
	end)

	test("a broken exam card is refused", function()
		local a = newPlayer("R4")
		saves[a] = { Simple = false }
		local s = examSpec(104, {})
		s.Answer = "XRay" -- not on the card
		expect(Treatment.open(a, s)).toBe(nil)
		s = examSpec(104, {})
		s.Tools = { "Scalpel", "Stethoscope" }
		s.Answer = "Scalpel" -- not a tool
		expect(Treatment.open(a, s)).toBe(nil)
		s = examSpec(104, {})
		s.Tools = "Stethoscope"
		expect(Treatment.open(a, s)).toBe(nil)
		s = examSpec(104, {})
		s.Settle = nil
		expect(Treatment.open(a, s)).toBe(nil)
		expect(Treatment.busy(a)).toBe(false)
		-- junk among the tools is dropped, the card still plays
		s = examSpec(104, {})
		s.Tools = { "Light", "Light", 5, "Stethoscope", "Order" }
		local id = Treatment.open(a, s)
		expect(fired[#fired].Payload.Tools).toEqual({ "Light", "Stethoscope" })
		Treatment.drop(id)
	end)

	test("a Treat sends its case with the card", function()
		local a = newPlayer("R5")
		saves[a] = { Simple = false }
		local s = spec({ "Ice", "Bandage" }, {})
		s.Case = "Sprain"
		local id = Treatment.open(a, s)
		local payload = fired[#fired].Payload
		expect(payload.Case).toBe("Sprain")
		expect(payload.Games).toEqual({ "Ice", "Bandage" })
		expect(payload.Tools).toBe(nil)
		Treatment.drop(id)
	end)

	test("a Dispense: Pick then Dose; ONE known medicine (never a 'Which one?')", function()
		local a = newPlayer("D1")
		saves[a] = { Simple = false }
		local options = { "Plaster", "CoughSyrup", "CoughSyrup", "Mystery", "EarDrops", "Order", "Cream", "Lozenges" }
		local id = Treatment.open(a, dispenseSpec(options, {}))
		expect(type(id)).toBe("number")
		local payload = fired[#fired].Payload
		expect(payload.Kind).toBe("Dispense")
		expect(payload.Games).toEqual({ "Pick", "Dose" })
		expect(payload.Options).toEqual({ "CoughSyrup" }) -- the first known medicine only
		expect(TrPure.OPTIONS_MAX).toBe(1)
		expect(payload.Items).toEqual({})
		expect(payload.PatientId).toBe("")
		expect(payload.Glow).toBe(false)
		expect(payload.Level).toBe(nil)
		expect(payload.Tools).toBe(nil)
		expect(payload.Tuning).toBe(nil) -- no Expert Dispensing
		expect(payload.Expert).toBe(nil)
		Treatment.drop(id)
		-- nothing a dispensary makes, or no Give: refused
		expect(Treatment.open(a, dispenseSpec({ "Plaster", "Ice" }, {}))).toBe(nil)
		expect(Treatment.open(a, dispenseSpec({}, {}))).toBe(nil)
		local noGive = dispenseSpec({ "CoughSyrup" }, {})
		noGive.Give = nil
		expect(Treatment.open(a, noGive)).toBe(nil)
		expect(Treatment.busy(a)).toBe(false)
	end)

	test("a Dispense's slip: the patient it is for, the clinic's level and the glow go with TreatStart", function()
		local a = newPlayer("D1b")
		saves[a] = { Simple = false }
		local s = dispenseSpec({ "EarDrops" }, {})
		s.PatientId = "CloudSheep"
		s.Level = 2.6
		s.Glow = true
		local id = Treatment.open(a, s)
		local payload = fired[#fired].Payload
		expect(payload.PatientId).toBe("CloudSheep")
		expect(payload.Level).toBe(2)
		expect(payload.Glow).toBe(true)
		Treatment.drop(id)
		for _, junk in { 0, -3, 0 / 0, math.huge, "2" } do
			local j = dispenseSpec({ "EarDrops" }, {})
			j.Level = junk
			j.PatientId = 7
			local jid = Treatment.open(a, j)
			expect(fired[#fired].Payload.Level).toBe(nil)
			expect(fired[#fired].Payload.PatientId).toBe("")
			Treatment.drop(jid)
		end
	end)

	test("a Dispense gives the chosen medicine first, then pays its tip at once", function()
		local a = newPlayer("D2")
		saves[a] = { Simple = false }
		local gives = {}
		local id = Treatment.open(a, dispenseSpec({ "EarDrops", "CoughSyrup" }, gives))
		now += 2 -- Pick 0.6 + Dose 1.2 = 1.8 x 0.8 = 1.44 s
		local ok, _, outcome = TreatResult(a, id, { "Perfect", "Perfect" }, "EarDrops")
		expect(ok).toBe(true)
		expect(gives).toEqual({ "EarDrops" })
		expect(outcome.Item).toBe("EarDrops")
		expect(outcome.Ratings).toEqual({ "Perfect", "Perfect" })
		expect(outcome.Tip).toBe(6)
		expect(cash[a]).toBe(6)
		expect(outcome.Complete).toBe(false)
		expect(outcome.Case).toBe(nil)
		expect(Treatment.busy(a)).toBe(false)
	end)

	test("a Dispense result whose Choice isn't in Options gives nothing and rates OK", function()
		local a = newPlayer("D3")
		saves[a] = { Simple = false }
		a:SetAttribute("Combo", 4)
		-- (EarDrops was named too, but cut from the card: one medicine per dispense)
		for _, choice in { "EarDrops", "FeverMeds", "Plaster", "Order", 5, {}, nil } do
			local gives = {}
			local id = Treatment.open(a, dispenseSpec({ "CoughSyrup", "EarDrops" }, gives))
			now += 3
			local ok, _, outcome = TreatResult(a, id, { "Perfect", "Perfect" }, choice)
			expect(ok).toBe(true)
			expect(#gives).toBe(0)
			expect(outcome.Item).toBe(nil)
			expect(outcome.Ratings).toEqual({ "OK", "OK" })
			expect(outcome.Tip).toBe(0)
		end
		-- no choice at all (even with a single option on the card)
		local gives = {}
		local id = Treatment.open(a, dispenseSpec({ "CoughSyrup" }, gives))
		now += 3
		local ok, _, outcome = TreatResult(a, id, { "Perfect", "Perfect" })
		expect(ok).toBe(true)
		expect(#gives).toBe(0)
		expect(outcome.Item).toBe(nil)
		expect(outcome.Ratings).toEqual({ "OK", "OK" })
		expect(cash[a]).toBe(nil)
		expect(a:GetAttribute("Combo")).toBe(0) -- rated OK: the combo resets as any OK does
	end)

	test("a Dispense session for a player who left is dropped and gives nothing (Review Focus 4)", function()
		local a = newPlayer("D4")
		saves[a] = { Simple = false }
		a:SetAttribute("Combo", 3)
		local gives = {}
		local id = Treatment.open(a, dispenseSpec({ "CoughSyrup" }, gives))
		Players.PlayerRemoving:Fire(a)
		expect(#gives).toBe(0)
		expect(Treatment.busy(a)).toBe(false)
		expect(a:GetAttribute("Combo")).toBe(3)
		expect(TreatResult(a, id, { "Perfect", "Perfect" }, "CoughSyrup")).toBe(false)
		expect(#gives).toBe(0)
	end)

	test("a Dispense that times out gives nothing (hold Dispense again)", function()
		local a = newPlayer("D5")
		saves[a] = { Simple = false }
		local gives = {}
		Config.MiniGame.SessionSeconds, Config.MiniGame.PerGameSeconds = 0.05, 0
		local id = Treatment.open(a, dispenseSpec({ "CoughSyrup" }, gives))
		Config.MiniGame.SessionSeconds, Config.MiniGame.PerGameSeconds = 12, 6
		task.wait(0.15)
		expect(#gives).toBe(0)
		expect(Treatment.busy(a)).toBe(false)
		expect(TreatResult(a, id, { "Perfect", "Perfect" }, "CoughSyrup")).toBe(false)
		-- never a silent empty hand: the player is told to hold Dispense again
		local last = toasts[#toasts]
		expect(last.Player).toBe(a)
		expect(last.Text).toBe("💊 Hold Dispense to try again!")
	end)

	test("the timeout waits UntimedSeconds for every untimed tap (a Pick; no 'Which one?' any more)", function()
		local a = newPlayer("D5b")
		saves[a] = { Simple = false }
		Config.MiniGame.UntimedSeconds = 20
		local one = Treatment.open(a, dispenseSpec({ "CoughSyrup" }, {}))
		expect(fired[#fired].Payload.Timeout).toBe(44) -- 12 + 2 x 6 + the bottle Pick
		Treatment.drop(one)
		local several = Treatment.open(a, dispenseSpec({ "CoughSyrup", "EarDrops" }, {}))
		expect(fired[#fired].Payload.Timeout).toBe(44) -- cut to one: nothing more to wait for
		Treatment.drop(several)
		local exam = Treatment.open(a, examSpec(180, {}))
		expect(fired[#fired].Payload.Timeout).toBe(44)
		Treatment.drop(exam)
		local treat = Treatment.open(a, spec({ "Bubbles", "Ice" }, {}))
		expect(fired[#fired].Payload.Timeout).toBe(24) -- every supply game has its own clock
		Treatment.drop(treat)
		Config.MiniGame.UntimedSeconds = nil
	end)

	test(
		"a handover: no games, no ability spent, the ward pick asked on the report; a medicine Treat is refused",
		function()
			local a = newPlayer("H1")
			saves[a] = { Simple = false }
			local settled = {}
			local s = triageSpec({}, settled, REST_ASK)
			s.Handover = true
			s.Key = 190
			local asks = perfectAsks
			local id = Treatment.open(a, s)
			expect(type(id)).toBe("number")
			expect(perfectAsks).toBe(asks)
			local payload = fired[#fired].Payload
			expect(payload.Kind).toBe("Treat")
			expect(payload.Games).toEqual({})
			expect(payload.Items).toEqual({})
			expect(payload.Handover).toBe(true)
			expect(payload.Timeout).toBe(TrPure.HANDOVER_SECONDS)
			expect(Treatment.working(190, plot)).toBe(true)
			local combo = Treatment.combo(a)
			local ok, _, outcome = TreatResult(a, id, {}) -- at once: there is nothing to play
			expect(ok).toBe(true)
			expect(outcome.Ratings).toEqual({})
			expect(outcome.Tip).toBe(0)
			expect(outcome.Combo).toBe(combo)
			expect(outcome.Complete).toBe(true)
			expect(outcome.Triage.Options).toEqual({ "Wards", "Rest" })
			expect(#settled).toBe(1)
			expect(Triage(a, id, "Rest")).toBe(true)
			expect(TrPure.HANDOVER_SECONDS).toBe(4) -- unanswered, it settles by itself this soon
			-- without Handover, a Treat with nothing to give is no session; nor is a handover that names items
			expect(Treatment.open(a, triageSpec({}, {}, REST_ASK))).toBe(nil)
			local named = triageSpec({ "Ice" }, {}, REST_ASK)
			named.Handover = true
			expect(Treatment.open(a, named)).toBe(nil)
			expect(TrPure.games({}, ItemsData, true)).toEqual({})
			expect(TrPure.games(nil, ItemsData, true)).toEqual({})
			expect(TrPure.games({ "CoughSyrup" }, ItemsData, true)).toBe(nil)
			expect(TrPure.games({}, ItemsData)).toBe(nil)
		end
	)

	test("a Dispense that may not tip (already tipped for) still gives; one whose Give fails gives no tip", function()
		local a = newPlayer("D6")
		saves[a] = { Simple = false }
		local gives = {}
		local id = Treatment.open(a, dispenseSpec({ "CoughSyrup" }, gives, { true, false }))
		now += 2
		local _, _, outcome = TreatResult(a, id, { "Perfect", "Perfect" }, "CoughSyrup")
		expect(outcome.Item).toBe("CoughSyrup")
		expect(outcome.Tip).toBe(0)
		expect(outcome.Combo).toBe(2) -- the Perfects still count for the combo
		expect(cash[a]).toBe(nil)
		id = Treatment.open(a, dispenseSpec({ "CoughSyrup" }, gives, { false, true }))
		now += 2
		_, _, outcome = TreatResult(a, id, { "Perfect", "Perfect" }, "CoughSyrup")
		expect(outcome.Item).toBe(nil)
		expect(outcome.Tip).toBe(0)
		expect(cash[a]).toBe(nil)
		local broken = dispenseSpec({ "CoughSyrup" }, gives)
		broken.Give = function()
			error("boom")
		end
		id = Treatment.open(a, broken)
		now += 2
		local ok
		ok, _, outcome = TreatResult(a, id, { "Perfect", "Perfect" }, "CoughSyrup")
		expect(ok).toBe(true)
		expect(outcome.Item).toBe(nil)
		expect(outcome.Tip).toBe(0)
	end)

	test("a Dispense reported from far away still gives the medicine, rated OK", function()
		local a = newPlayer("D7", Vector3.new(0, 0, 40))
		saves[a] = { Simple = false }
		local gives = {}
		local id = Treatment.open(a, dispenseSpec({ "FeverMeds" }, gives))
		now += 3
		local _, _, outcome = TreatResult(a, id, { "Perfect", "Perfect" }, "FeverMeds")
		expect(gives).toEqual({ "FeverMeds" })
		expect(outcome.Item).toBe("FeverMeds")
		expect(outcome.Ratings).toEqual({ "OK", "OK" })
		expect(outcome.Tip).toBe(0)
	end)

	test("Expert Dispensing widens the Dose band by 50%", function()
		local a = newPlayer("D8")
		saves[a] = { Simple = false }
		local s = dispenseSpec({ "CoughSyrup" }, {})
		s.Expert = true
		local id = Treatment.open(a, s)
		expect(fired[#fired].Payload.Expert).toBe(true) -- what the client widens its own Dose row on
		local dose = fired[#fired].Payload.Tuning.Dose
		local plain = Config.MiniGame.Games.Dose
		expect(dose.BandMax - dose.BandMin).toBeCloseTo((plain.BandMax - plain.BandMin) * Config.Dispensary.ExpertBand)
		expect(Config.Dispensary.ExpertBand).toBe(1.5)
		expect((dose.BandMin + dose.BandMax) / 2).toBeCloseTo((plain.BandMin + plain.BandMax) / 2)
		expect(dose.GoodSlack).toBe(plain.GoodSlack)
		expect(dose.MinSeconds).toBe(plain.MinSeconds) -- the server's timing rule is unchanged
		expect(plain.BandMax - plain.BandMin).toBeCloseTo(0.16) -- the shipped row is untouched
		-- the wider band rates a fill the plain band calls Good as Perfect
		local fill = plain.BandMax + 0.03
		expect(MiniGame.rate("Dose", fill, Config)).toBe("Good")
		local expertCfg = { MiniGame = { Games = { Dose = dose } } }
		expect(MiniGame.rate("Dose", fill, expertCfg)).toBe("Perfect")
		Treatment.drop(id)
		-- Expert only ever touches a Dispense
		local t = spec({ "Ice" }, {})
		t.Expert = true
		local tid = Treatment.open(a, t)
		expect(fired[#fired].Payload.Tuning).toBe(nil)
		expect(fired[#fired].Payload.Expert).toBe(nil)
		Treatment.drop(tid)
	end)

	test("widen: round the middle, inside 0..1; junk factors change nothing", function()
		local row = { BandMin = 0.7, BandMax = 0.86, GoodSlack = 0.12 }
		local wide = TrPure.widen(row, 1.5)
		expect(wide.BandMin).toBeCloseTo(0.66)
		expect(wide.BandMax).toBeCloseTo(0.9)
		expect(row.BandMin).toBe(0.7) -- a new table
		expect(TrPure.widen({ BandMin = 0.1, BandMax = 0.95 }, 3).BandMax).toBe(1)
		expect(TrPure.widen({ BandMin = 0.1, BandMax = 0.95 }, 3).BandMin).toBe(0)
		for _, junk in { 0 / 0, -2, 0.5, "1.5", nil, math.huge } do
			expect(TrPure.widen(row, junk)).toEqual(row)
		end
		expect(TrPure.tuning("Treat", true, Config)).toBe(nil)
		expect(TrPure.tuning("Dispense", false, Config)).toBe(nil)
	end)
end)

T.describe("The dispensary's rules (Server/Stations pure)", function()
	local bay = {
		{ Bay = "1", PatientId = 11, Stage = "Treat", Needs = { "CoughSyrup" }, Since = 50 },
		{ Bay = "2", PatientId = 12, Stage = "Treat", Needs = { "Lozenges", "CoughSyrup" }, Since = 40 },
		{ Bay = "3", PatientId = 13, Stage = "Exam", Needs = {}, Since = 30 },
	}

	test("the card offers what the bay patients need, less what you already carry", function()
		local needed = { "Lozenges", "CoughSyrup" }
		local options, why = StPure.dispenseOptions(needed, bay, {}, ItemsData)
		expect(options).toEqual({ "Lozenges", "CoughSyrup" })
		expect(why).toBe("")
		options = StPure.dispenseOptions(needed, bay, { "CoughSyrup" }, ItemsData)
		expect(options).toEqual({ "Lozenges", "CoughSyrup" }) -- two patients need it: one more to go
		options = StPure.dispenseOptions(needed, bay, { "CoughSyrup", "Plaster", "CoughSyrup" }, ItemsData)
		expect(options).toEqual({ "Lozenges" })
		options, why = StPure.dispenseOptions(needed, bay, { "CoughSyrup", "Lozenges", "CoughSyrup" }, ItemsData)
		expect(options).toEqual({})
		expect(why).toBe("Have")
		options, why = StPure.dispenseOptions({}, {}, {}, ItemsData)
		expect(options).toEqual({})
		expect(why).toBe("None")
		options, why = StPure.dispenseOptions({}, { bay[3] }, {}, ItemsData)
		expect(why).toBe("None") -- only an unexamined patient: no prescription yet
		options, why = StPure.dispenseOptions({ "Plaster", "Mystery", "Order" }, {}, {}, ItemsData)
		expect(why).toBe("None") -- supplies and junk are never on the card
		options = StPure.dispenseOptions(needed, nil, { "CoughSyrup", "Lozenges" }, ItemsData)
		expect(options).toEqual(needed) -- no bay view: trust the needs
	end)

	test("the card: the carried ones go BEFORE the cut to 3, so a fourth needed medicine comes up", function()
		local busy = {
			{ Bay = "1", PatientId = 21, Needs = { "CoughSyrup" }, Since = 10 },
			{ Bay = "2", PatientId = 22, Needs = { "FeverMeds" }, Since = 20 },
			{ Bay = "3", PatientId = 23, Needs = { "EarDrops" }, Since = 30 },
			{ Bay = "4", PatientId = 24, Needs = { "PainRelief" }, Since = 40 },
		}
		local needed = { "CoughSyrup", "FeverMeds", "EarDrops" } -- Patients.neededMedicines: the oldest 3
		local options, why = StPure.dispenseOptions(needed, busy, {}, ItemsData, 3, false)
		expect(options).toEqual({ "CoughSyrup", "FeverMeds", "EarDrops" })
		-- a tray of 4 holding the first three, one slot free: the fourth is offered, not "Already in your hands!"
		options, why =
			StPure.dispenseOptions(needed, busy, { "CoughSyrup", "FeverMeds", "EarDrops" }, ItemsData, 3, false)
		expect(options).toEqual({ "PainRelief" })
		expect(why).toBe("")
		options = StPure.dispenseOptions(needed, busy, { "FeverMeds" }, ItemsData, 3, false)
		expect(options).toEqual({ "CoughSyrup", "EarDrops", "PainRelief" })
		-- the rest of the rows come the longest wait first, whatever order the rows are in
		options = StPure.dispenseOptions({}, { busy[4], busy[2], busy[1] }, {}, ItemsData, 2, false)
		expect(options).toEqual({ "CoughSyrup", "FeverMeds" })
		options, why = StPure.dispenseOptions(
			needed,
			busy,
			{ "CoughSyrup", "FeverMeds", "EarDrops", "PainRelief" },
			ItemsData,
			3,
			true
		)
		expect(options).toEqual({})
		expect(why).toBe("Have")
	end)

	test(
		"one medicine per dispense: the bay patient who has waited longest, then the next once it's in hand",
		function()
			expect(StPure.PER_DISPENSE).toBe(1)
			local busy = {
				{ Bay = "2", PatientId = 52, Needs = { "FeverMeds" }, Since = 20 },
				{ Bay = "1", PatientId = 51, Needs = { "Plaster", "CoughSyrup" }, Since = 10 },
				{ Bay = "3", PatientId = 53, Needs = { "EarDrops" }, Since = 30 },
			}
			local needed = { "CoughSyrup", "FeverMeds", "EarDrops" }
			local options, why = StPure.dispenseOptions(needed, busy, {}, ItemsData, StPure.PER_DISPENSE, false)
			expect(options).toEqual({ "CoughSyrup" }) -- bay 1 has waited longest
			expect(why).toBe("")
			options = StPure.dispenseOptions(needed, busy, { "CoughSyrup" }, ItemsData, StPure.PER_DISPENSE, false)
			expect(options).toEqual({ "FeverMeds" }) -- its syrup is in hand: the next patient's
			-- the real dispensary passes PER_DISPENSE (never Config.Dispensary.Options)
			local text = source("src/server/Stations.luau")
			assert(string.find(text, "\t\tPure.PER_DISPENSE,\n", 1, true), "Stations cuts the card to one")
			expect(string.find(text, "Config.Dispensary and Config.Dispensary.Options", 1, true)).toBe(nil)
		end
	)

	test("the slip's patient: the longest wait among those who need it, one skipped per copy in hand", function()
		local rows = {
			{ Bay = "2", PatientId = 62, Needs = { "CoughSyrup" }, Since = 20 },
			{ Bay = "1", PatientId = 61, Needs = { "Lozenges", "CoughSyrup" }, Since = 10 },
			{ Bay = "3", PatientId = 63, Needs = { "EarDrops" }, Since = 30 },
		}
		expect(StPure.patientFor(rows, "CoughSyrup", {})).toBe(61)
		expect(StPure.patientFor(rows, "CoughSyrup", { "CoughSyrup" })).toBe(62) -- 61's is in hand already
		expect(StPure.patientFor(rows, "CoughSyrup", { "CoughSyrup", "CoughSyrup" })).toBe(61) -- all covered
		expect(StPure.patientFor(rows, "EarDrops", { "CoughSyrup" })).toBe(63)
		expect(StPure.patientFor(rows, "FeverMeds", {})).toBe(nil)
		expect(StPure.patientFor("junk", "CoughSyrup", {})).toBe(nil)
		expect(StPure.patientFor(rows, nil, {})).toBe(nil)
	end)

	test(
		"the glow: a player's first 3 dispenses by their own counter, always in Simple mode and the tutorial",
		function()
			expect(StPure.DISPENSES_STAT).toBe("Dispenses")
			expect(StPure.DISPENSE_GLOW).toBe(3)
			expect(StPure.dispensesDone({ Stats = { Dispenses = 2 } })).toBe(2)
			for _, junk in
				{ {}, { Stats = {} }, { Stats = { Dispenses = -1 } }, { Stats = { Dispenses = 0 / 0 } }, nil }
			do
				expect(StPure.dispensesDone(junk)).toBe(0)
			end
			-- the exam's counter is its own: a player who examined plenty still gets the bottle's glow
			expect(StPure.dispensesDone({ Stats = { Exams = 9 } })).toBe(0)
			for done = 0, 2 do
				expect(StPure.dispenseGlow(done, false, Config)).toBe(true)
			end
			expect(StPure.dispenseGlow(3, false, Config)).toBe(false)
			expect(StPure.dispenseGlow(40, true, Config)).toBe(true) -- Simple mode or the tutorial
			-- Config.Dispensary.Glow overrides the number when it is set
			expect(StPure.glowLimit({ Dispensary = { Glow = 5 } })).toBe(5)
			expect(StPure.glowLimit({ Dispensary = { Glow = 0 } })).toBe(0)
			expect(StPure.glowLimit({ Dispensary = { Glow = "x" } })).toBe(3)
			expect(StPure.glowLimit(nil)).toBe(3)
			-- the real dispensary sends the glow, counts each dispense that lands, and asks the tutorial
			local text = source("src/server/Stations.luau")
			assert(string.find(text, "Glow = dispenseGlow(player),", 1, true), "the session carries the glow")
			assert(string.find(text, "countDispense(player) -- the glow's own counter", 1, true), "counted in Give")
			assert(string.find(text, "(Tutorial :: any).active", 1, true), "the tutorial glows")
		end
	)

	test("the card: a full tray of the only medicine left is refused before the games ('Tray full')", function()
		-- Lv 1, a tray of 1: bays 1 and 2 both need cough syrup, and one bottle is in hand already
		local two = {
			{ Bay = "1", PatientId = 31, Needs = { "CoughSyrup" }, Since = 10 },
			{ Bay = "2", PatientId = 32, Needs = { "CoughSyrup" }, Since = 20 },
		}
		local options, why = StPure.dispenseOptions({ "CoughSyrup" }, two, { "CoughSyrup" }, ItemsData, 3, true)
		expect(options).toEqual({})
		expect(why).toBe("Full")
		-- room in the tray: one more to make
		options, why = StPure.dispenseOptions({ "CoughSyrup" }, two, { "CoughSyrup" }, ItemsData, 3, false)
		expect(options).toEqual({ "CoughSyrup" })
		-- a full tray with something else in it swaps that out, so it is still offered
		options = StPure.dispenseOptions({ "CoughSyrup" }, two, { "CoughSyrup", "Plaster" }, ItemsData, 3, true)
		expect(options).toEqual({ "CoughSyrup" })
		-- full of cough syrup, but ear drops are needed too: those can swap in
		local mixed = { two[1], two[2], { Bay = "3", PatientId = 33, Needs = { "EarDrops" }, Since = 30 } }
		options, why = StPure.dispenseOptions({ "CoughSyrup", "EarDrops" }, mixed, { "CoughSyrup" }, ItemsData, 3, true)
		expect(options).toEqual({ "EarDrops" })
		expect(why).toBe("")
		expect(StPure.MSG.Full).toBe("🙌 Tray full! Treat a patient.")
	end)

	test("the tip ledger: one tip per need, whoever gets the bottle; a spare dispense tips nothing", function()
		local ledger = StPure.ledger()
		StPure.sync(ledger, bay)
		expect(StPure.claimTip(ledger, "CoughSyrup")).toBe(true)
		expect(StPure.claimTip(ledger, "CoughSyrup")).toBe(true) -- two patients need it
		expect(StPure.claimTip(ledger, "CoughSyrup")).toBe(false) -- both players dispensed: one spare, no tip
		expect(StPure.claimTip(ledger, "Lozenges")).toBe(true)
		expect(StPure.claimTip(ledger, "Lozenges")).toBe(false) -- thrown away and dispensed again: never twice
		expect(StPure.claimTip(ledger, "FeverMeds")).toBe(false)
		expect(StPure.claimTip(ledger, nil)).toBe(false)
		-- patient 12 left its bay: its needs go, each with one tip; a new patient's need tips again
		local later = { bay[1], { Bay = "2", PatientId = 14, Needs = { "CoughSyrup" }, Since = 60 } }
		StPure.sync(ledger, later)
		expect(ledger.Seen["12:CoughSyrup"]).toBe(nil)
		expect(ledger.Seen["12:Lozenges"]).toBe(nil)
		expect(ledger.Seen["11:CoughSyrup"]).toBe(true)
		expect(ledger.Tips.Lozenges).toBe(nil)
		expect(StPure.claimTip(ledger, "CoughSyrup")).toBe(true) -- patient 14's
		expect(StPure.claimTip(ledger, "CoughSyrup")).toBe(false)
		StPure.sync(ledger, "junk") -- junk changes nothing
		expect(ledger.Seen["14:CoughSyrup"]).toBe(true)
	end)

	test("the tip ledger: the bottle may go to the younger patient; the older one's dispense still tips", function()
		-- bays 1 (older) and 2 both need cough syrup
		local older = { Bay = "1", PatientId = 41, Needs = { "CoughSyrup" }, Since = 10 }
		local younger = { Bay = "2", PatientId = 42, Needs = { "CoughSyrup" }, Since = 20 }
		local ledger = StPure.ledger()
		StPure.sync(ledger, { older, younger })
		expect(StPure.claimTip(ledger, "CoughSyrup")).toBe(true)
		-- handed to the YOUNGER patient, who is treated and leaves its bay
		StPure.sync(ledger, { older })
		expect(StPure.claimTip(ledger, "CoughSyrup")).toBe(true) -- the first medicine the older one ever gets
		expect(StPure.claimTip(ledger, "CoughSyrup")).toBe(false)
		-- a need that was given stays seen while its patient is in the bay (a 2-step plan): no second tip for it
		local twoStep = { Bay = "3", PatientId = 43, Needs = { "Lozenges", "CoughSyrup" }, Since = 30 }
		local l2 = StPure.ledger()
		StPure.sync(l2, { twoStep })
		expect(StPure.claimTip(l2, "Lozenges")).toBe(true)
		StPure.sync(l2, { { Bay = "3", PatientId = 43, Needs = { "CoughSyrup" }, Since = 30 } }) -- lozenges given
		expect(StPure.claimTip(l2, "Lozenges")).toBe(false)
		expect(StPure.claimTip(l2, "CoughSyrup")).toBe(true)
	end)

	test("the prompt's text: the needed medicines' icons, or no prescriptions yet", function()
		expect(StPure.objectText({}, ItemsData)).toBe("💊 No prescriptions yet")
		expect(StPure.objectText(nil, ItemsData)).toBe("💊 No prescriptions yet")
		expect(StPure.objectText({ "Plaster" }, ItemsData)).toBe("💊 No prescriptions yet")
		expect(StPure.objectText({ "EarDrops", "Lozenges" }, ItemsData)).toBe("💊 💧 🍬")
		expect(StPure.MSG.None).toBe("💊 No prescriptions yet")
	end)

	test("Expert Dispensing is the clinic owner's Pharmacy2 unlock (R2)", function()
		expect(StPure.pharmacyTier(0, RebirthLogic.has)).toBe(1)
		expect(StPure.pharmacyTier(1, RebirthLogic.has)).toBe(1)
		expect(StPure.pharmacyTier(2, RebirthLogic.has)).toBe(2)
		expect(StPure.pharmacyTier("x", RebirthLogic.has)).toBe(1)
	end)

	test("no crafting is left in the stations", function()
		expect(StPure.pharmacy).toBe(nil)
		local text = source("src/server/Stations.luau")
		expect(string.find(text, "Recipe.craft", 1, true)).toBe(nil)
		expect(string.find(text, "Potion", 1, true)).toBe(nil)
	end)
end)
