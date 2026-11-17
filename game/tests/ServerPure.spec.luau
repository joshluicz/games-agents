--!nocheck
-- The server's pure helpers for the treat flow (depth update T1): the PURE-BEGIN..PURE-END blocks of
-- Server/Patients, Server/Treatment and Server/Stations, loaded on their own (the rest of those modules needs
-- Roblox) and tested against the real Logic/Recipe, Logic/MiniGame and (Progression v2) Logic/Hospital. The
-- Hospital v2 rules of the Patients block have their own spec, HospitalPatients.spec. Run from game/ with the rest:
--   lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local Recipe = require("../src/shared/Logic/Recipe")
local MiniGame = require("../src/shared/Logic/MiniGame")
local Hospital = require("../src/shared/Logic/Hospital")
local Items = require("../src/shared/Data/Items")

local function source(path: string): string
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("can't find " .. path .. " (run from game/)")
end

local function loadPure(path: string, env: { [string]: any }): any
	local text = source(path)
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to and to > from, path .. ": no PURE block")
	local block = string.sub(text, from, to - 1) .. "\nreturn Pure\n"
	return luau.load(block, { debugName = path .. " (pure)", environment = env })()
end

-- Config uses Vector3, so the plan's Config.MiniGame numbers (§B6) are copied here, like tests/MiniGame.spec does.
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
}

local Tools = require("../src/shared/Data/Tools")
local P = loadPure("src/server/Patients.luau", {
	Recipe = Recipe,
	Hospital = Hospital,
	Visit = require("../src/shared/Logic/Visit"),
	Cases = require("../src/shared/Data/Cases"),
	Items = Items,
	Tools = Tools,
})
local Tr = loadPure("src/server/Treatment.luau", { MiniGame = MiniGame })
local S = loadPure("src/server/Stations.luau", {})

T.describe("Patients (pure)", function()
	test("plan: the helper's own items first, then the nurse tray", function()
		local plan = { "Bubbles", "PainRelief" }
		local carry, tray = P.plan(plan, { false, false }, { "PainRelief" }, { "Bubbles", "PainRelief" })
		expect(carry).toEqual({ 2 })
		expect(tray).toEqual({ 1 })
	end)

	test("plan: each item fills one slot; done slots are skipped", function()
		local plan = { "Cast", "PainRelief", "Bandage" }
		local carry, tray = P.plan(plan, { true, false, false }, { "PainRelief", "PainRelief" }, {})
		expect(carry).toEqual({ 2 })
		expect(tray).toEqual({})
		local carry2, tray2 = P.plan(plan, { false, false, false }, { "Cast" }, { "Bandage", "Cast" })
		expect(carry2).toEqual({ 1 })
		expect(tray2).toEqual({ 3 })
	end)

	test("plan: nothing fits -> two empty lists", function()
		local carry, tray = P.plan({ "Cocoa", "FeverMeds" }, { false, false }, { "Plaster" }, { "Bubbles" })
		expect(#carry + #tray).toBe(0)
		local carry2, tray2 = P.plan({ "CoughSyrup" }, { true }, { "CoughSyrup" }, { "CoughSyrup" })
		expect(#carry2 + #tray2).toBe(0) -- complete: nothing more is taken
	end)

	test("plan: an item only fills its own step (no crafted medicines any more)", function()
		local carry = P.plan(
			{ "Lozenges", "CoughSyrup" },
			{ false, false },
			{ "Potion", "WarmTonic", "CoughSyrup" },
			{}
		)
		expect(carry).toEqual({ 2 })
	end)

	test("firstMissing", function()
		expect(P.firstMissing({ "A", "B", "C" }, { true, false, false })).toBe(2)
		expect(P.firstMissing({ "A", "B" }, { false, true })).toBe(1)
		expect(P.firstMissing({ "A" }, { true })).toBe(nil)
	end)

	test("needs: missing steps, not counting the ones mid-game", function()
		local plan = { "Ice", "Bandage" }
		expect(P.needs(plan, { false, false }, nil)).toEqual({ "Ice", "Bandage" })
		expect(P.needs(plan, { false, false }, { 1 })).toEqual({ "Bandage" })
		expect(P.needs(plan, { true, false }, { 2 })).toEqual({})
	end)

	test("refill: each item adds a share of the max, clamped", function()
		expect(P.refill(10, 60, 0.25, 1)).toBe(25)
		expect(P.refill(10, 60, 0.25, 2)).toBe(40)
		expect(P.refill(50, 60, 0.25, 3)).toBe(60)
		expect(P.refill(10, 60, -1, 2)).toBe(10)
		expect(P.refill(10, 60, 0.25, -2)).toBe(10)
	end)

	test("cheer: a safe drain divisor", function()
		expect(P.cheer(nil, 3)).toBe(1)
		expect(P.cheer("2", 3)).toBe(1)
		expect(P.cheer(0 / 0, 3)).toBe(1)
		expect(P.cheer(0.5, 3)).toBe(1)
		expect(P.cheer(1.3, 3)).toBe(1.3)
		expect(P.cheer(math.huge, 3)).toBe(3)
	end)
end)

T.describe("Treatment (pure)", function()
	local games = { "Pour", "Patch" } -- min 2.2 s, x 0.8 slack = 1.76 s

	test("a timeout or a helper who left is all OK, even in Simple mode", function()
		expect(Tr.ratings("Timeout", nil, games, 99, false, true, Config)).toEqual({ "OK", "OK" })
		expect(Tr.ratings("Timeout", nil, games, 99, true, true, Config)).toEqual({ "OK", "OK" })
		expect(Tr.ratings("Left", { "Perfect", "Perfect" }, games, 99, false, true, Config)).toEqual({ "OK", "OK" })
	end)

	test("a report from far from the Counter is all OK", function()
		expect(Tr.ratings("Report", { "Perfect", "Perfect" }, games, 5, false, false, Config)).toEqual({ "OK", "OK" })
	end)

	test("a report too soon, the wrong length or junk is all OK", function()
		expect(Tr.ratings("Report", { "Perfect", "Perfect" }, games, 0.1, false, true, Config)).toEqual({ "OK", "OK" })
		expect(Tr.ratings("Report", { "Perfect" }, games, 5, false, true, Config)).toEqual({ "OK", "OK" })
		expect(Tr.ratings("Report", { "Perfect", "Great" }, games, 5, false, true, Config)).toEqual({ "OK", "OK" })
		expect(Tr.ratings("Report", "Perfect", games, 5, false, true, Config)).toEqual({ "OK", "OK" })
		expect(Tr.ratings("Report", { "Perfect", "Perfect", "Perfect" }, games, 5, false, true, Config)).toEqual({
			"OK",
			"OK",
		})
	end)

	test("an honest report counts; Simple is all Good", function()
		expect(Tr.ratings("Report", { "Perfect", "Good" }, games, 1.8, false, true, Config)).toEqual({
			"Perfect",
			"Good",
		})
		expect(Tr.ratings("Report", { "Perfect", "Perfect" }, games, 0.1, true, true, Config)).toEqual({
			"Good",
			"Good",
		})
	end)

	test("a cheating client gains at most one capped tip per cure", function()
		-- Ten Perfects at a huge combo and a big Cheerer: never more than TipCapPerCure, less what's been paid.
		local ratings = table.create(10, "Perfect")
		local _, tip = MiniGame.settle(50, ratings, Config, 0, Tr.tipScale(99, 3))
		expect(tip).toBe(15)
		local _, more = MiniGame.settle(50, ratings, Config, 15, Tr.tipScale(99, 3))
		expect(more).toBe(0)
	end)

	test("tipScale: junk -> 1, capped", function()
		expect(Tr.tipScale(nil, 3)).toBe(1)
		expect(Tr.tipScale(0 / 0, 3)).toBe(1)
		expect(Tr.tipScale(0.2, 3)).toBe(1)
		expect(Tr.tipScale(1.12, 3)).toBe(1.12)
		expect(Tr.tipScale(10, 3)).toBe(3)
	end)

	test("sessionId: only finite whole numbers", function()
		expect(Tr.sessionId(4)).toBe(4)
		expect(Tr.sessionId(-1)).toBe(-1) -- well-formed, just never anyone's session
		expect(Tr.sessionId(1.5)).toBe(nil)
		expect(Tr.sessionId(0 / 0)).toBe(nil)
		expect(Tr.sessionId(math.huge)).toBe(nil)
		expect(Tr.sessionId("4")).toBe(nil)
		expect(Tr.sessionId({})).toBe(nil)
		expect(Tr.sessionId(nil)).toBe(nil)
	end)

	test("games: one per supply (its Data/Items Game), in order; none for a medicine or an unknown item", function()
		expect(Tr.games({ "Bubbles", "Ice" }, Items)).toEqual({ "Bath", "Ice" })
		expect(Tr.games({ "Cocoa", "Plaster" }, Items)).toEqual({ "Cocoa", "Plaster" })
		expect(Tr.games({ "CoughSyrup" }, Items)).toBe(nil) -- handed over with no session
		expect(Tr.games({ "Mystery" }, Items)).toBe(nil)
		expect(Tr.games({}, Items)).toBe(nil)
	end)

	test("all", function()
		expect(Tr.all("OK", 3)).toEqual({ "OK", "OK", "OK" })
		expect(Tr.all("Good", 0)).toEqual({})
	end)

	-- Progression v2 (T7)
	test("auto games are Perfect on every path: a report, too soon, far away, a timeout, Simple", function()
		local auto = { true, false }
		expect(Tr.ratings("Report", { "OK", "Good" }, games, 1.0, false, true, Config, auto)).toEqual({
			"Perfect",
			"Good",
		})
		expect(Tr.ratings("Report", { "Perfect", "Perfect" }, games, 0.1, false, true, Config, auto)).toEqual({
			"Perfect",
			"OK",
		})
		expect(Tr.ratings("Report", { "Perfect", "Perfect" }, games, 5, false, false, Config, auto)).toEqual({
			"Perfect",
			"OK",
		})
		expect(Tr.ratings("Timeout", nil, games, 99, false, true, Config, auto)).toEqual({ "Perfect", "OK" })
		expect(Tr.ratings("Report", nil, games, 0.1, true, true, Config, auto)).toEqual({ "Perfect", "Good" })
		expect(Tr.ratings("Timeout", nil, games, 99, false, true, Config, nil)).toEqual({ "OK", "OK" })
	end)

	test("autoFlags: exactly one boolean per game, junk -> false", function()
		expect(Tr.autoFlags({ true, false, true }, 2)).toEqual({ true, false })
		expect(Tr.autoFlags({ true }, 3)).toEqual({ true, false, false })
		expect(Tr.autoFlags("yes", 2)).toEqual({ false, false })
		expect(Tr.autoFlags({ 1, "true" }, 2)).toEqual({ false, false })
		expect(Tr.autoFlags(nil, 0)).toEqual({})
	end)

	test("ease: 1..1.3, junk -> 1", function()
		expect(Tr.ease(1.2)).toBe(1.2)
		expect(Tr.ease(9)).toBe(1.3)
		expect(Tr.ease(0.5)).toBe(1)
		expect(Tr.ease(0 / 0)).toBe(1)
		expect(Tr.ease("1.3")).toBe(1)
	end)

	test("an exam picks the tool, then plays its game; a dispense picks the bottle, then measures the dose", function()
		expect(Tr.examGames("Stethoscope", Tools)).toEqual({ "Pick", "Listen" })
		expect(Tr.examGames("XRay", Tools)).toEqual({ "Pick", "XRay" })
		expect(Tr.examGames("Spoon", Tools)).toBe(nil)
		expect(Tr.dispenseGames()).toEqual({ "Pick", "Dose" })
		expect(Tr.games({ "PainRelief", "Plaster" }, Items)).toBe(nil) -- a medicine never plays in a Treat
	end)

	test("triageAsk: two or more distinct string options and a Right among them", function()
		expect(Tr.triageAsk({ Options = { "Wards", "Hydro" }, Right = "Hydro" })).toEqual({
			Options = { "Wards", "Hydro" },
			Right = "Hydro",
		})
		expect(Tr.triageAsk({ Options = { "Wards", "Wards", 3, "Hydro" }, Right = "Wards" })).toEqual({
			Options = { "Wards", "Hydro" },
			Right = "Wards",
		})
		expect(Tr.triageAsk({ Options = { "Wards" }, Right = "Wards" })).toBe(nil)
		expect(Tr.triageAsk({ Options = { "Wards", "Hydro" }, Right = "Roof" })).toBe(nil)
		expect(Tr.triageAsk({ Options = "Wards", Right = "Wards" })).toBe(nil)
		expect(Tr.triageAsk(nil)).toBe(nil)
	end)

	test("triageCheck: your pending pick only, an option, in the window, once", function()
		local entry = { Session = 5, Options = { "Wards", "Hydro" }, Right = "Hydro", Ends = 10, Pick = nil }
		expect(Tr.triageCheck(entry, 5, "Hydro", 9)).toBe(true)
		expect(Tr.triageCheck(entry, 5, "Wards", 9)).toBe(false) -- wrong, but a real pick
		expect(Tr.triageCheck(entry, 5, "Roof", 9)).toBe(nil)
		expect(Tr.triageCheck(entry, 5, 1, 9)).toBe(nil)
		expect(Tr.triageCheck(entry, 6, "Hydro", 9)).toBe(nil)
		expect(Tr.triageCheck(entry, nil, "Hydro", 9)).toBe(nil)
		expect(Tr.triageCheck(entry, 5, "Hydro", 10.5)).toBe(nil) -- too late
		expect(Tr.triageCheck(nil, 5, "Hydro", 9)).toBe(nil)
		entry.Pick = "Hydro"
		expect(Tr.triageCheck(entry, 5, "Hydro", 9)).toBe(nil) -- once
	end)
end)

T.describe("Stations (pure)", function()
	test("a full tray gives up what nobody in line needs first", function()
		expect(S.swapOut({ "Potion", "Plaster" }, "Bubbles", { "Bubbles", "Potion" })).toBe("Plaster")
		expect(S.swapOut({ "Plaster", "Potion" }, "Bubbles", { "Bubbles", "Potion" })).toBe("Plaster")
	end)

	test("duplicates: only as many as the line needs are spoken for", function()
		expect(S.swapOut({ "Potion", "Potion" }, "Bubbles", { "Bubbles", "Potion" })).toBe("Potion")
		expect(S.swapOut({ "Potion", "Plaster", "Potion" }, "Cocoa", { "Potion", "Potion", "Plaster" })).toBe("Potion")
	end)

	test("everything needed: the oldest different one, as before", function()
		expect(S.swapOut({ "Potion", "Plaster" }, "Bubbles", { "Plaster", "Potion" })).toBe("Potion")
		expect(S.swapOut({ "Potion", "Plaster" }, "Bubbles", {})).toBe("Potion")
	end)

	test("a tray of only this item: nil (Tray full!)", function()
		expect(S.swapOut({ "Potion", "Potion" }, "Potion", { "Bubbles" })).toBe(nil)
		expect(S.swapOut({}, "Potion", {})).toBe(nil)
	end)
end)
