--!nocheck
-- The server's pure helpers for the treat flow (depth update T1): the PURE-BEGIN..PURE-END blocks of
-- Server/Patients, Server/Treatment and Server/Stations, loaded on their own (the rest of those modules needs
-- Roblox) and tested against the real Logic/Recipe and Logic/MiniGame. Run from game/ with the rest:
--   lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local Recipe = require("../src/shared/Logic/Recipe")
local MiniGame = require("../src/shared/Logic/MiniGame")

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

local P = loadPure("src/server/Patients.luau", { Recipe = Recipe })
local Tr = loadPure("src/server/Treatment.luau", { MiniGame = MiniGame })
local S = loadPure("src/server/Stations.luau", {})

T.describe("Patients (pure)", function()
	test("plan: the helper's own items first, then the nurse tray", function()
		local recipe = { "Bubbles", "Potion" }
		local carry, tray = P.plan(recipe, { false, false }, { "Potion" }, { "Bubbles", "Potion" })
		expect(carry).toEqual({ 2 })
		expect(tray).toEqual({ 1 })
	end)

	test("plan: each item fills one slot; done slots are skipped", function()
		local recipe = { "Potion", "Plaster", "Potion" }
		local carry, tray = P.plan(recipe, { true, false, false }, { "Potion", "Potion" }, {})
		expect(carry).toEqual({ 3 })
		expect(tray).toEqual({})
		local carry2, tray2 = P.plan(recipe, { false, false, false }, { "Potion" }, { "Potion", "Plaster" })
		expect(carry2).toEqual({ 1 })
		expect(tray2).toEqual({ 2, 3 })
	end)

	test("plan: nothing fits -> two empty lists", function()
		local carry, tray = P.plan({ "Cocoa", "Potion" }, { false, false }, { "Plaster" }, { "Bubbles" })
		expect(#carry + #tray).toBe(0)
		local carry2, tray2 = P.plan({ "Potion" }, { true }, { "Potion" }, { "Potion" })
		expect(#carry2 + #tray2).toBe(0) -- complete: nothing more is taken
	end)

	test("firstMissing", function()
		expect(P.firstMissing({ "A", "B", "C" }, { true, false, false })).toBe(2)
		expect(P.firstMissing({ "A", "B" }, { false, true })).toBe(1)
		expect(P.firstMissing({ "A" }, { true })).toBe(nil)
	end)

	test("recipeFor: cut to the level cap, never empty, item 1 is the station's", function()
		local full = { "Potion", "Plaster", "Potion" }
		expect(P.recipeFor(full, "Potion", 1)).toEqual({ "Potion" })
		expect(P.recipeFor(full, "Potion", 2)).toEqual({ "Potion", "Plaster" })
		expect(P.recipeFor(full, "Potion", 3)).toEqual(full)
		expect(P.recipeFor(nil, "Plaster", 3)).toEqual({ "Plaster" })
		expect(P.recipeFor({}, "Plaster", 3)).toEqual({ "Plaster" })
		expect(P.recipeFor({ 7, "Potion" }, "Potion", 3)).toEqual({ "Potion" })
		expect(P.recipeFor({ "Cocoa", "Potion" }, "Bubbles", 3)).toEqual({ "Bubbles" }) -- broken data: the safe one
		expect(P.recipeFor(full, "Potion", 0 / 0)).toEqual({ "Potion" })
	end)

	test("needs: missing items, not counting the ones mid-mini-game", function()
		local recipe = { "Bubbles", "Potion" }
		expect(P.needs(recipe, { false, false }, nil)).toEqual({ "Bubbles", "Potion" })
		expect(P.needs(recipe, { false, false }, { 1 })).toEqual({ "Potion" })
		expect(P.needs(recipe, { true, false }, { 2 })).toEqual({})
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

	test("games: one per item, in order", function()
		expect(Tr.games({ "Bubbles", "Potion" })).toEqual({ "Scrub", "Pour" })
		expect(Tr.games({ "Cocoa", "Plaster" })).toEqual({ "Cool", "Patch" })
		expect(Tr.games({ "Mystery" })).toEqual({ "Pour" })
	end)

	test("all", function()
		expect(Tr.all("OK", 3)).toEqual({ "OK", "OK", "OK" })
		expect(Tr.all("Good", 0)).toEqual({})
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
