--!nocheck
-- Hospital v2's patients (Progression v2 build plan §C T7): the Hospital v2 rules in the PURE-BEGIN..PURE-END block
-- of Server/Patients, loaded on their own (the rest of the module needs Roblox) against the real Logic/Recipe,
-- Logic/Hospital, Shared/Config (tests/config.luau) and the Lune-safe Data (Items, Levels, Wings). Routing and
-- where a patient rests, triage right / wrong / timeout, escort with and without, the urgent recipe and its
-- padding, Twin Counters' pick, medicines filling two slots, urgent places in line, patience and timers, variants
-- and wing gates. The session side (auto-Perfect games, the Soak tip under the cap, the Triage remote) is in
-- TreatmentSessions.spec. Run from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local Config = require("./config")
local Recipe = require("../src/shared/Logic/Recipe")
local Hospital = require("../src/shared/Logic/Hospital")
local MiniGame = require("../src/shared/Logic/MiniGame")
local Items = require("../src/shared/Data/Items")
local Levels = require("../src/shared/Data/Levels")
local Wings = require("../src/shared/Data/Wings")

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

local P = loadPure("src/server/Patients.luau", { Recipe = Recipe, Hospital = Hospital })
local MAX_EXTRA = 5 -- Logic/Pay.MAX_EXTRA

T.describe("Hospital patients: routing and where they rest", function()
	test("a Bath patient goes to Hydro once it's open (Lv 3); everyone else to the Wards", function()
		expect(Hospital.route("Bath", "", 2, Levels)).toBe("Wards")
		expect(Hospital.route("Bath", "", 3, Levels)).toBe("Hydro")
		expect(Hospital.route("Bath", "AE", 5, Levels)).toBe("Hydro")
		expect(Hospital.route("Starter", "", 5, Levels)).toBe("Wards")
		expect(Hospital.route("Sky", "VIP", 5, Levels)).toBe("Wards")
	end)

	test("Hydro takes a free tub first; then a ground bed, then a ward bed upstairs, then in place", function()
		expect(P.destination("Hydro", { Tub = true, Ground = true, Upstairs = true })).toBe("Tub")
		expect(P.destination("Hydro", { Tub = false, Ground = true, Upstairs = true })).toBe("Ground")
		expect(P.destination("Hydro", { Upstairs = true })).toBe("Upstairs")
		expect(P.destination("Hydro", {})).toBe("Place")
	end)

	test("Wards: the ground bed first, then upstairs; never a tub", function()
		expect(P.destination("Wards", { Tub = true, Ground = true, Upstairs = true })).toBe("Ground")
		expect(P.destination("Wards", { Ground = false, Upstairs = true })).toBe("Upstairs")
		expect(P.destination("Wards", { Tub = true })).toBe("Place")
	end)
end)

T.describe("Hospital patients: triage", function()
	test("the floor pick starts at Lv 3, when Wards and Hydro are both open", function()
		expect(Hospital.triageOptions(1, Levels)).toBe(nil)
		expect(Hospital.triageOptions(2, Levels)).toBe(nil)
		expect(Hospital.triageOptions(3, Levels)).toEqual({ "Wards", "Hydro" })
		expect(Hospital.triageOptions(5, Levels)).toEqual({ "Wards", "Hydro" })
	end)

	test("who picks: the helper asks; a Receptionist sends at once; a nurse's finish asks nobody", function()
		local options = Hospital.triageOptions(3, Levels)
		expect(P.triageMode(nil, false, true)).toBe("None") -- below Lv 3
		expect(P.triageMode(nil, true, true)).toBe("None")
		expect(P.triageMode(options, false, true)).toBe("Ask")
		expect(P.triageMode(options, true, true)).toBe("Instant")
		expect(P.triageMode(options, true, false)).toBe("Instant")
		expect(P.triageMode(options, false, false)).toBe("None")
		expect(P.triageMode({ "Wards" }, false, true)).toBe("None")
	end)

	test("it only asks when the patient really goes to its department's floor; Simple mode never asks", function()
		local options = Hospital.triageOptions(3, Levels)
		-- routed: a Hydro patient into a tub, a Wards patient up to a ward bed
		expect(P.routed("Hydro", "Tub")).toBe(true)
		expect(P.routed("Wards", "Upstairs")).toBe(true)
		-- not routed: a ground bed, in place, or a Hydro patient in a ward bed because the tubs are full
		expect(P.routed("Wards", "Ground")).toBe(false)
		expect(P.routed("Hydro", "Ground")).toBe(false)
		expect(P.routed("Hydro", "Upstairs")).toBe(false)
		expect(P.routed("Wards", "Place")).toBe(false)
		expect(P.triageMode(options, false, true, true)).toBe("Ask")
		expect(P.triageMode(options, false, true, false)).toBe("None") -- no question, no bonus
		expect(P.triageMode(options, true, true, false)).toBe("Instant") -- a Receptionist still sends it, as before
		-- Simple mode: no timed decision; it goes at once with the bonus, as a Receptionist sends it
		expect(P.triageMode(options, false, true, true, true)).toBe("Instant")
		expect(P.triageMode(options, false, true, false, true)).toBe("None")
		expect(P.triageMode(options, false, false, true, true)).toBe("None") -- a nurse's finish asks nobody
		expect(P.triageMode(nil, false, true, true, true)).toBe("None") -- below Lv 3
	end)

	test("right earns +10%; wrong and no pick (timeout) earn nothing (it goes the right way regardless)", function()
		expect(P.triageBonus("Hydro", "Hydro")).toBe(true)
		expect(P.triageBonus("Wards", "Hydro")).toBe(false)
		expect(P.triageBonus("", "Hydro")).toBe(false) -- no pick in Config.Triage.Seconds
		expect(P.triageBonus(nil, "Hydro")).toBe(false)
		expect(P.extra({ Triage = true }, Config, MAX_EXTRA)).toBeCloseTo(1 + Config.Triage.RightBonus)
		expect(P.extra({ Triage = false }, Config, MAX_EXTRA)).toBe(1)
	end)
end)

T.describe("Hospital patients: escort, the hot tub, rest and pay", function()
	test("escort: +20% cash and rest x0.5; without: nothing changes", function()
		expect(P.extra({ Escorted = true }, Config, MAX_EXTRA)).toBeCloseTo(1.2)
		expect(P.extra({ Escorted = false }, Config, MAX_EXTRA)).toBe(1)
		expect(P.rest(4, { Escorted = true }, Config)).toBeCloseTo(2)
		expect(P.rest(4, {}, Config)).toBeCloseTo(4)
	end)

	test("the hot tub: +25% and rest x0.5, on top of an escort", function()
		expect(P.extra({ Soaked = true }, Config, MAX_EXTRA)).toBeCloseTo(1.25)
		expect(P.extra({ Escorted = true, Soaked = true }, Config, MAX_EXTRA)).toBeCloseTo(1.5)
		expect(P.rest(4, { Escorted = true, Soaked = true }, Config)).toBeCloseTo(1)
	end)

	test("Ward Comfort (-20% rest, +5% cash a level) and the team multiply in; rest never under 0.5 s", function()
		expect(P.rest(4, { Comfort = 3 }, Config)).toBeCloseTo(1.6)
		expect(P.extra({ Comfort = 3 }, Config, MAX_EXTRA)).toBeCloseTo(1.15)
		expect(P.extra({ Team = 1.2 }, Config, MAX_EXTRA)).toBeCloseTo(1.2)
		expect(P.rest(4, { Team = 0.5 }, Config)).toBeCloseTo(2)
		expect(P.rest(4, { Escorted = true, Soaked = true, Comfort = 3, Team = 0.5 }, Config)).toBe(0.5)
	end)

	test("junk never pays less or more than it should: Extra stays in 1..MAX_EXTRA", function()
		expect(P.extra({ Team = 0 / 0, Comfort = "3" }, Config, MAX_EXTRA)).toBe(1)
		expect(P.extra({ Team = 0.2 }, Config, MAX_EXTRA)).toBe(1) -- a team never lowers the pay
		expect(P.extra({ Team = 99, Escorted = true, Soaked = true }, Config, MAX_EXTRA)).toBe(MAX_EXTRA)
		expect(P.rest(4, { Team = 7 }, Config)).toBeCloseTo(4) -- a team never slows the rest
	end)
end)

T.describe("Hospital patients: urgent (🚑 A&E, 🚁 air ambulance)", function()
	local stand = { Potion = true, Plaster = true }
	local all = { Potion = true, Plaster = true, Bubbles = true, Cocoa = true }

	test("the urgent recipe: at least MinItems, a 1-item recipe padded with the other Stand item", function()
		expect(P.urgentFor({ "Potion" }, stand, 1, Config.AE.MinItems)).toEqual({ "Potion", "Plaster" })
		expect(P.urgentFor({ "Plaster" }, stand, 2, Config.AE.MinItems)).toEqual({ "Plaster", "Potion" })
		expect(P.urgentFor({ "Cocoa", "Potion" }, all, 2, Config.AE.MinItems)).toEqual({ "Cocoa", "Potion" })
		expect(P.urgentFor({ "Potion", "Cocoa", "Plaster" }, all, 3, Config.AE.MinItems)).toEqual({
			"Potion",
			"Cocoa",
			"Plaster",
		})
	end)

	test("an item no station here makes is left out (the Sky wing's ☕ without a Winter Wing)", function()
		expect(P.urgentFor({ "Potion", "Cocoa", "Plaster" }, stand, 3, Config.AE.MinItems)).toEqual({
			"Potion",
			"Plaster",
		})
		expect(P.urgentFor({ "Cocoa", "Potion" }, stand, 2, Config.AE.MinItems)).toBe(nil) -- its own item: no
		expect(P.urgentFor({ "Bubbles", "Potion" }, { Potion = true }, 2, Config.AE.MinItems)).toBe(nil)
	end)

	test("it joins at the front, behind anyone mid-mini-game or resting there", function()
		expect(P.urgentPlace({})).toBe(1)
		expect(P.urgentPlace({ false, false })).toBe(1)
		expect(P.urgentPlace({ true, false })).toBe(2) -- the front is being treated: second
		expect(P.urgentPlace({ true, true })).toBe(3)
	end)

	test("patience: x0.6 (x1.15 a level of A&E Speed for 🚑); it drains slower with the team and a Medic", function()
		expect(P.urgentPatience(60, "AE", 0, Config)).toBeCloseTo(36)
		expect(P.urgentPatience(60, "AE", 2, Config)).toBeCloseTo(36 * 1.3)
		expect(P.urgentPatience(60, "VIP", 2, Config)).toBeCloseTo(36)
		expect(P.urgentPatience(0 / 0, "AE", 0, Config) >= 1).toBe(true)
		expect(P.slower(1, 1, 4)).toBe(1)
		expect(P.slower(1.25, 1.2, 4)).toBeCloseTo(1.5)
		expect(P.slower(0.5, "x", 4)).toBe(1) -- junk and "faster" both count as normal
		expect(P.slower(3, 3, 4)).toBe(4)
	end)

	test(
		"timers: ambulances every 150 s +-20%, sooner with A&E Speed and Siren Pro; helicopters every 300 s",
		function()
			expect(P.aeSeconds(Config, 0.5, 0, 1)).toBeCloseTo(150)
			expect(P.aeSeconds(Config, 0, 0, 1)).toBeCloseTo(120)
			expect(P.aeSeconds(Config, 1, 0, 1)).toBeCloseTo(180)
			expect(P.aeSeconds(Config, 0.5, 3, 1)).toBeCloseTo(150 * 0.7)
			expect(P.aeSeconds(Config, 0.5, 0, 1.25)).toBeCloseTo(120)
			expect(P.aeSeconds(Config, 0.5, 99, 99) >= 1).toBe(true)
			expect(P.vipSeconds(Config, 0.5)).toBeCloseTo(300)
			expect(P.vipSeconds(Config, 0)).toBeCloseTo(240)
		end
	)

	test("the line still holds at most Config.MaxQueue (3) at every level", function()
		expect(Config.MaxQueue).toBe(3)
		for _, row in Levels do
			expect(row.Queue <= Config.MaxQueue).toBe(true)
		end
	end)
end)

T.describe("Hospital patients: Twin Counters and medicines", function()
	test("the first of the two front patients whose missing items you carry; else the first the tray fits", function()
		expect(P.pickTwin({ { Carry = 0, Tray = 1 }, { Carry = 1, Tray = 0 } })).toBe(2)
		expect(P.pickTwin({ { Carry = 1, Tray = 0 }, { Carry = 2, Tray = 0 } })).toBe(1)
		expect(P.pickTwin({ { Carry = 0, Tray = 0 }, { Carry = 0, Tray = 1 } })).toBe(2)
		expect(P.pickTwin({ { Carry = 0, Tray = 1 }, { Carry = 0, Tray = 1 } })).toBe(1)
		expect(P.pickTwin({ { Carry = 0, Tray = 0 }, { Carry = 0, Tray = 0 } })).toBe(nil)
		expect(P.pickTwin({ { Carry = 0, Tray = 0 } })).toBe(nil)
	end)

	test("with real plans: #2 is served when only its items are in hand", function()
		local carried = { "Bubbles" }
		local front = { P.plan({ "Potion" }, { false }, carried, {}, Items) }
		local second = { P.plan({ "Bubbles", "Potion" }, { false, false }, carried, {}, Items) }
		local plans = {
			{ Carry = #front[1], Tray = #front[2] },
			{ Carry = #second[1], Tray = #second[2] },
		}
		expect(P.pickTwin(plans)).toBe(2)
	end)

	test("a medicine fills both slots its ingredients cover, as one item (one 🧪 Pour game)", function()
		local carry, tray, used = P.plan({ "Cocoa", "Potion" }, { false, false }, { "WarmTonic" }, {}, Items)
		expect(carry).toEqual({ 1, 2 })
		expect(tray).toEqual({})
		expect(used).toEqual({ "WarmTonic" })
		expect(MiniGame.gameFor(used[1])).toBe("Pour")
		-- one slot left: it fills that one
		local half = P.plan({ "Cocoa", "Potion" }, { true, false }, { "WarmTonic" }, {}, Items)
		expect(half).toEqual({ 2 })
		-- both done: it isn't spent
		local none, _, unused = P.plan({ "Cocoa", "Potion" }, { true, true }, { "WarmTonic" }, {}, Items)
		expect(none).toEqual({})
		expect(unused).toEqual({})
	end)

	test("exact items first, then a medicine for what's still missing; tier 2 works the same", function()
		local carry, _, used = P.plan(
			{ "Potion", "Plaster", "Potion" },
			{ false, false, false },
			{ "Potion", "SuperSyrup" },
			{},
			Items
		)
		expect(carry).toEqual({ 1, 2, 3 })
		expect(used).toEqual({ "Potion", "SuperSyrup" })
	end)
end)

T.describe("Hospital patients: variants and wings", function()
	local goldenAt = 3 -- Data/Variants.Golden.Rebirths

	test("🌟 Golden only from R3, at Config.GoldenChance (or always with the Studio switch)", function()
		expect(P.variant(3, { 0.01, 0.99, 0.99 }, false, false, Config, goldenAt)).toBe("Golden")
		expect(P.variant(2, { 0.01, 0.99, 0.99 }, false, false, Config, goldenAt)).toBe(nil)
		expect(P.variant(3, { 0.5, 0.99, 0.99 }, false, false, Config, goldenAt)).toBe(nil)
		expect(P.variant(3, { 0.99, 0.99, 0.99 }, false, true, Config, goldenAt)).toBe("Golden")
		expect(P.variant(2, { 0.99, 0.99, 0.99 }, false, true, Config, goldenAt)).toBe(nil) -- the switch: R3+ only
	end)

	test("Sparkly and (in winter only) Frosty as before", function()
		expect(P.variant(0, { 0.99, 0.01, 0.99 }, false, false, Config, goldenAt)).toBe("Sparkly")
		expect(P.variant(0, { 0.99, 0.99, 0.01 }, false, false, Config, goldenAt)).toBe(nil)
		expect(P.variant(0, { 0.99, 0.99, 0.01 }, true, false, Config, goldenAt)).toBe("Frosty")
	end)

	test("🌻 Sunny comes from R1; 🚁 Sky only by air ambulance; the helicopter brings only Sky", function()
		expect(P.wingOpen(Wings.Starter, 0, false)).toBe(true)
		expect(P.wingOpen(Wings.Sunny, 0, false)).toBe(false)
		expect(P.wingOpen(Wings.Sunny, 1, false)).toBe(true)
		expect(P.wingOpen(Wings.Sky, 9, false)).toBe(false)
		expect(P.wingOpen(Wings.Sky, 0, true)).toBe(true) -- (the helicopter itself flies from R2)
		expect(P.wingOpen(Wings.Starter, 5, true)).toBe(false)
	end)
end)
