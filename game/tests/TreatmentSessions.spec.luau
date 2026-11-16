--!nocheck
-- Treat sessions end to end (depth update T1, build plan Review focus 1): the real src/server/Treatment.luau runs
-- under Lune with mocked Roblox services (Players, Remotes, Economy, PlayerData, Nurses, Abilities). It checks the
-- session lifecycle a cheating client would poke at: one session per player, junk / someone else's / stale ids
-- refused with nothing changed, a too-early report rated all OK, Simple mode, the distance check, the tip cap per
-- cure, the timeout, drop, the helper leaving, and Healer routing. Progression v2 (T7): auto-Perfect sessions
-- (Abilities.consumePerfects), Ease from the tree, a medicine as one Pour game, the 🫧 Soak kind and its tip under
-- the cap, the Triage remote (right / wrong / junk / late / timeout) and Medic routing.
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
local Remotes = {
	OOPS = "Oops! Try again.",
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

local Config = {
	MiniGame = {
		PerfectTip = 3,
		TipCapPerCure = 15,
		Combo = { { At = 3, Multiplier = 1.2 }, { At = 6, Multiplier = 1.5 }, { At = 10, Multiplier = 2 } },
		MinSeconds = { Pour = 1.2, Patch = 1, Scrub = 1.5, Cool = 1.5 },
		SimpleMinSeconds = 0.25,
		Slack = 0.8,
		SessionSeconds = 12,
		PerGameSeconds = 6,
	},
	Treat = { ItemPatience = 0.25, Distance = 20 },
	Triage = { Seconds = 4, RightBonus = 0.1 },
}
local MiniGame = require("../src/shared/Logic/MiniGame")
local RebirthLogic = require("../src/shared/Logic/Rebirth")
local PerksData = require("../src/shared/Data/Perks")
local TreeData = require("../src/shared/Data/Tree")

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
	Data = { Perks = "PerksData", Tree = "TreeData" },
}
local modules = {
	Config = Config,
	Remotes = Remotes,
	Types = {},
	MiniGame = MiniGame,
	RebirthLogic = RebirthLogic,
	PerksData = PerksData,
	TreeData = TreeData,
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
	test("open fires TreatStart with one game per item and the timeout", function()
		local a = newPlayer("A")
		saves[a] = { Simple = false }
		local settled = {}
		local id = Treatment.open(a, spec({ "Bubbles", "Potion" }, settled))
		expect(type(id)).toBe("number")
		local last = fired[#fired]
		expect(last.Player).toBe(a)
		expect(last.Payload.Session).toBe(id)
		expect(last.Payload.Games).toEqual({ "Scrub", "Pour" })
		expect(last.Payload.Items).toEqual({ "Bubbles", "Potion" })
		expect(last.Payload.Simple).toBe(false)
		expect(last.Payload.Combo).toBe(0)
		expect(last.Payload.Timeout).toBe(24)
		expect(Treatment.busy(a)).toBe(true)
		expect(Treatment.open(a, spec({ "Potion" }, settled))).toBe(nil) -- one at a time
		Treatment.drop(id)
		expect(Treatment.busy(a)).toBe(false)
	end)

	test("junk, someone else's and stale sessions are refused and change nothing", function()
		local a, b = newPlayer("A2"), newPlayer("B2")
		saves[a], saves[b] = { Simple = false }, { Simple = false }
		local settledA, settledB = {}, {}
		local idA = Treatment.open(a, spec({ "Potion" }, settledA))
		local idB = Treatment.open(b, spec({ "Potion" }, settledB))
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
		local id = Treatment.open(a, spec({ "Potion" }, settled))
		now += 1.0 -- Pour min 1.2 x 0.8 = 0.96
		local ok, _, outcome = TreatResult(a, id, { "Perfect" })
		expect(ok).toBe(true)
		expect(outcome.Ratings).toEqual({ "Perfect" })
		expect(outcome.Tip).toBe(3)
		expect(outcome.Combo).toBe(1)
		expect(outcome.Complete).toBe(true)
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
		local id = Treatment.open(a, spec({ "Potion", "Plaster" }, settled))
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

	test("from far from the Counter: all OK", function()
		local a = newPlayer("A6", Vector3.new(0, 0, 30))
		saves[a] = { Simple = false }
		local settled = {}
		local id = Treatment.open(a, spec({ "Potion" }, settled))
		now += 5
		local _, _, outcome = TreatResult(a, id, { "Perfect" })
		expect(outcome.Ratings).toEqual({ "OK" })
		expect(outcome.Tip).toBe(0)
	end)

	test("the tip is capped per cure, with a Cheerer and a big combo", function()
		local a = newPlayer("A7")
		saves[a] = { Simple = false }
		a:SetAttribute("Combo", 20)
		cheerTip = 99 -- junk-big: capped
		local s = spec({ "Potion", "Plaster", "Potion" }, {})
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
		local id = Treatment.open(a, spec({ "Potion" }, settled))
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
		local id = Treatment.open(a, spec({ "Potion" }, settled))
		Config.MiniGame.SessionSeconds, Config.MiniGame.PerGameSeconds = 12, 6
		Treatment.drop(id)
		task.wait(0.15)
		expect(#settled).toBe(0)
		expect(TreatResult(a, id, { "OK" })).toBe(false)
	end)

	test("the helper leaves mid-game: settled all OK, no tip, combo kept", function()
		local a = newPlayer("A10")
		saves[a] = { Simple = false }
		a:SetAttribute("Combo", 5)
		local settled = {}
		Treatment.open(a, spec({ "Potion" }, settled))
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
		local s = spec({ "Potion" }, {})
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
		give = { "Potion" }
		Nurses.Heal:Fire(plot, "MintMouse")
		expect(#healed).toBe(1)
		expect(healed[1].Items).toEqual({ "Potion" })
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
local HYDRO_ASK = { Options = { "Wards", "Hydro" }, Right = "Hydro" }

T.describe("Treatment v2 (mocked)", function()
	test("auto-Perfect: the ability's games are Perfect whatever is reported; the minimum time skips them", function()
		local a = newPlayer("V1")
		saves[a] = { Simple = false }
		autoNext = { true, false }
		local asks = perfectAsks
		local settled = {}
		local id = Treatment.open(a, spec({ "Plaster", "Potion" }, settled))
		expect(perfectAsks).toBe(asks + 1)
		local payload = fired[#fired].Payload
		expect(payload.Games).toEqual({ "Patch", "Pour" })
		expect(payload.Auto).toEqual({ true, false })
		expect(payload.Kind).toBe("Treat")
		now += 1.0 -- Pour alone: 1.2 x 0.8 = 0.96 s (with Patch it would need 1.76 s)
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
		Treatment.open(a, spec({ "Potion", "Plaster" }, settled))
		Config.MiniGame.SessionSeconds, Config.MiniGame.PerGameSeconds = 12, 6
		task.wait(0.15)
		expect(#settled).toBe(1)
		expect(settled[1].Ratings).toEqual({ "OK", "Perfect" })
	end)

	test("a medicine is ONE Pour game; no ability banked means no auto games", function()
		local a = newPlayer("V3")
		saves[a] = { Simple = false }
		local id = Treatment.open(a, spec({ "WarmTonic" }, {}))
		local payload = fired[#fired].Payload
		expect(payload.Items).toEqual({ "WarmTonic" })
		expect(payload.Games).toEqual({ "Pour" })
		expect(payload.Auto).toEqual({ false })
		Treatment.drop(id)
	end)

	test("Ease: the helper's own 🎯 Steady Hands (1 without, 1.3 at three ranks)", function()
		local a, b = newPlayer("V4a"), newPlayer("V4b")
		saves[a] = { Simple = false }
		saves[b] = { Simple = false, Rebirth = { Tree = { SteadyHands = 3 }, Perks = {} } }
		local idA = Treatment.open(a, spec({ "Potion" }, {}))
		expect(fired[#fired].Payload.Ease).toBe(1)
		local idB = Treatment.open(b, spec({ "Potion" }, {}))
		expect(fired[#fired].Payload.Ease).toBeCloseTo(1.3)
		Treatment.drop(idA)
		Treatment.drop(idB)
	end)

	test("a Soak: one Scrub game, no items, and its tip stays under the patient's cap", function()
		local a = newPlayer("V5")
		saves[a] = { Simple = false }
		expect(Treatment.open(a, spec({}, {}))).toBe(nil) -- a Treat needs items
		local settled = {}
		local s = spec({}, settled)
		s.Kind = "Soak"
		s.TipSoFar = 13 -- the cure paid 13 already: 2 left under TipCapPerCure 15
		s.Settle = function(ratings, tip)
			table.insert(settled, { Ratings = ratings, Tip = tip })
			return false, nil
		end
		local id = Treatment.open(a, s)
		local payload = fired[#fired].Payload
		expect(payload.Kind).toBe("Soak")
		expect(payload.Items).toEqual({})
		expect(payload.Games).toEqual({ "Scrub" })
		now += 2 -- Scrub: 1.5 x 0.8 = 1.2 s
		local before = cash[a] or 0
		local ok, _, outcome = TreatResult(a, id, { "Perfect" })
		expect(ok).toBe(true)
		expect(outcome.Tip).toBe(2)
		expect(outcome.Complete).toBe(false)
		expect(outcome.Triage).toBe(nil)
		expect((cash[a] or 0) - before).toBe(2)
	end)

	test("Triage: a right pick, once; waitTriage answers it", function()
		local a = newPlayer("V6")
		saves[a] = { Simple = false }
		expect(Triage(a, 1, "Hydro")).toBe(false) -- nothing pending yet
		local id = Treatment.open(a, triageSpec({ "Bubbles" }, {}, HYDRO_ASK))
		now += 2
		local ok, _, outcome = TreatResult(a, id, { "Good" })
		expect(ok).toBe(true)
		expect(outcome.Complete).toBe(true)
		expect(outcome.Triage).toEqual({ Options = { "Wards", "Hydro" }, Seconds = 4 })
		local picked, message, payload = Triage(a, id, "Hydro")
		expect(picked).toBe(true)
		expect(message).toBe("✅ Right floor!")
		expect(payload).toEqual({ Right = true })
		expect(Triage(a, id, "Hydro")).toBe(false) -- once
		expect(Treatment.waitTriage(a, id, HYDRO_ASK.Options, "Hydro")).toBe("Hydro")
	end)

	test("Triage: junk and someone else's are refused; a wrong pick says Oops (it still goes the right way)", function()
		local a, b = newPlayer("V7a"), newPlayer("V7b")
		saves[a], saves[b] = { Simple = false }, { Simple = false }
		local id = Treatment.open(a, triageSpec({ "Bubbles" }, {}, HYDRO_ASK))
		now += 2
		TreatResult(a, id, { "Good" })
		for _, call in { { id, "Roof" }, { id, 7 }, { id + 1, "Wards" }, { "1", "Wards" }, { 0 / 0, "Wards" } } do
			local okJunk, messageJunk = Triage(a, call[1], call[2])
			expect(okJunk).toBe(false)
			expect(messageJunk).toBe(Remotes.OOPS)
		end
		expect(Triage(b, id, "Hydro")).toBe(false) -- not b's patient
		local ok, message, payload = Triage(a, id, "Wards")
		expect(ok).toBe(true)
		expect(message).toBe("Oops, not this floor!")
		expect(payload).toEqual({ Right = false })
		expect(Treatment.waitTriage(a, id, HYDRO_ASK.Options, "Hydro")).toBe("Wards")
	end)

	test("Triage: no pick in time -> waitTriage answers '' and a late pick is refused", function()
		local a = newPlayer("V8")
		saves[a] = { Simple = false }
		local id = Treatment.open(a, triageSpec({ "Bubbles" }, {}, HYDRO_ASK))
		now += 2
		TreatResult(a, id, { "Good" })
		local answer = nil
		task.spawn(function()
			answer = Treatment.waitTriage(a, id, HYDRO_ASK.Options, "Hydro")
		end)
		expect(answer).toBe(nil) -- still waiting for the pick
		now += 5 -- past Config.Triage.Seconds
		task.wait(0.25)
		expect(answer).toBe("")
		expect(Triage(a, id, "Hydro")).toBe(false)
	end)

	test("Triage: only the helper's own report asks; a timeout or an unfinished recipe asks nobody", function()
		local a = newPlayer("V9")
		saves[a] = { Simple = false }
		Config.MiniGame.SessionSeconds, Config.MiniGame.PerGameSeconds = 0.05, 0
		local id = Treatment.open(a, triageSpec({ "Bubbles" }, {}, HYDRO_ASK))
		Config.MiniGame.SessionSeconds, Config.MiniGame.PerGameSeconds = 12, 6
		task.wait(0.15)
		expect(Treatment.waitTriage(a, id, HYDRO_ASK.Options, "Hydro")).toBe("")
		expect(Triage(a, id, "Hydro")).toBe(false)
		local id2 = Treatment.open(a, triageSpec({ "Bubbles" }, {}, HYDRO_ASK, false))
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
