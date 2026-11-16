--!strict
-- Mini-game ratings, the combo, tips and the server's plausibility check (depth-update build plan §B7).
-- Config uses Vector3 (Roblox-only), so the plan's numbers are copied here; the Config check is in Studio.

local T = require("./expect")
local expect, test = T.expect, T.test

local MiniGame = require("../src/shared/Logic/MiniGame")

local CFG = {
	MiniGame = {
		PerfectTip = 3,
		TipCapPerCure = 15,
		Combo = { { At = 3, Multiplier = 1.2 }, { At = 6, Multiplier = 1.5 }, { At = 10, Multiplier = 2 } },
		MinSeconds = { Pour = 1.2, Patch = 1, Scrub = 1.5, Cool = 1.5 },
		SimpleMinSeconds = 0.25,
		Slack = 0.8,
		SessionSeconds = 12,
		PerGameSeconds = 6,
		Pour = { FillSeconds = 2.4, BandMin = 0.7, BandMax = 0.86, GoodSlack = 0.12 },
		Patch = { Spots = 3, Seconds = 4.5, Good = 2 },
		Scrub = { Seconds = 4, Perfect = 6, Good = 3 },
		Cool = { Blows = 3, Good = 2, PulseSeconds = 1.2, Window = 0.3 },
	},
}

T.describe("MiniGame", function()
	test("one game per item", function()
		expect(MiniGame.gameFor("Potion")).toBe("Pour")
		expect(MiniGame.gameFor("Plaster")).toBe("Patch")
		expect(MiniGame.gameFor("Bubbles")).toBe("Scrub")
		expect(MiniGame.gameFor("Cocoa")).toBe("Cool")
		expect(MiniGame.gameFor("Order")).toBeNil()
		expect(MiniGame.gameFor(5)).toBeNil()
	end)

	test("Pour: Perfect in the band, Good near it, else OK", function()
		expect(MiniGame.rate("Pour", 0.78, CFG)).toBe("Perfect")
		expect(MiniGame.rate("Pour", 0.7, CFG)).toBe("Perfect")
		expect(MiniGame.rate("Pour", 0.6, CFG)).toBe("Good")
		expect(MiniGame.rate("Pour", 0.95, CFG)).toBe("Good")
		expect(MiniGame.rate("Pour", 0.2, CFG)).toBe("OK")
		expect(MiniGame.rate("Pour", 0 / 0, CFG)).toBe("OK")
	end)

	test("Patch, Scrub and Cool count hits", function()
		expect(MiniGame.rate("Patch", 3, CFG)).toBe("Perfect")
		expect(MiniGame.rate("Patch", 2, CFG)).toBe("Good")
		expect(MiniGame.rate("Patch", 1, CFG)).toBe("OK")
		expect(MiniGame.rate("Scrub", 7, CFG)).toBe("Perfect")
		expect(MiniGame.rate("Scrub", 3, CFG)).toBe("Good")
		expect(MiniGame.rate("Scrub", 0, CFG)).toBe("OK")
		expect(MiniGame.rate("Cool", 3, CFG)).toBe("Perfect")
		expect(MiniGame.rate("Cool", 2, CFG)).toBe("Good")
		expect(MiniGame.rate("Cool", 1, CFG)).toBe("OK")
		expect(MiniGame.rate("Juggle", 99, CFG)).toBe("OK")
	end)

	test("minimum time and timeout", function()
		expect(MiniGame.minSeconds({ "Pour", "Scrub" }, false, CFG)).toBeCloseTo(2.7)
		expect(MiniGame.minSeconds({ "Pour", "Scrub" }, true, CFG)).toBeCloseTo(0.5)
		expect(MiniGame.timeout({ "Pour" }, CFG)).toBe(18)
		expect(MiniGame.timeout({ "Pour", "Patch", "Cool" }, CFG)).toBe(30)
	end)

	test("accept: a fair report stands", function()
		local games = { "Pour", "Patch" }
		expect(MiniGame.accept({ "Perfect", "Good" }, games, 3, false, CFG)).toEqual({ "Perfect", "Good" })
	end)

	test("accept: too fast, wrong length or junk is all OK", function()
		local games = { "Pour", "Patch" }
		-- min 2.2 s x 0.8 slack = 1.76 s
		expect(MiniGame.accept({ "Perfect", "Perfect" }, games, 1.5, false, CFG)).toEqual({ "OK", "OK" })
		expect(MiniGame.accept({ "Perfect", "Perfect" }, games, 1.8, false, CFG)).toEqual({ "Perfect", "Perfect" })
		expect(MiniGame.accept({ "Perfect" }, games, 9, false, CFG)).toEqual({ "OK", "OK" })
		expect(MiniGame.accept({ "Perfect", "Perfect", "Perfect" }, games, 9, false, CFG)).toEqual({ "OK", "OK" })
		expect(MiniGame.accept({ "Perfect", "Great" }, games, 9, false, CFG)).toEqual({ "OK", "OK" })
		expect(MiniGame.accept("Perfect", games, 9, false, CFG)).toEqual({ "OK", "OK" })
		expect(MiniGame.accept(nil, games, 9, false, CFG)).toEqual({ "OK", "OK" })
	end)

	test("accept: Simple mode is always Good", function()
		expect(MiniGame.accept({ "Perfect", "Perfect" }, { "Pour", "Cool" }, 0.6, true, CFG)).toEqual({
			"Good",
			"Good",
		})
		expect(MiniGame.accept(nil, { "Scrub" }, 0, true, CFG)).toEqual({ "Good" })
	end)

	test("combo multiplier steps", function()
		expect(MiniGame.multiplier(0, CFG)).toBe(1)
		expect(MiniGame.multiplier(2, CFG)).toBe(1)
		expect(MiniGame.multiplier(3, CFG)).toBe(1.2)
		expect(MiniGame.multiplier(6, CFG)).toBe(1.5)
		expect(MiniGame.multiplier(10, CFG)).toBe(2)
		expect(MiniGame.multiplier(40, CFG)).toBe(2)
	end)

	test("settle: Perfects build the combo and tip; a Good holds it; an OK resets it", function()
		local combo, tip = MiniGame.settle(0, { "Perfect", "Perfect" }, CFG)
		expect(combo).toBe(2)
		expect(tip).toBe(6)
		combo, tip = MiniGame.settle(2, { "Perfect" }, CFG) -- the third in a row: x1.2
		expect(combo).toBe(3)
		expect(tip).toBe(3) -- floor(3.6)
		combo, tip = MiniGame.settle(5, { "Good" }, CFG)
		expect(combo).toBe(5) -- held: no +1, no tip, no reset (§E7)
		expect(tip).toBe(0)
		combo, tip = MiniGame.settle(5, { "OK" }, CFG)
		expect(combo).toBe(0) -- the miss resets it
		expect(tip).toBe(0)
		combo, tip = MiniGame.settle(5, { "Perfect", "OK", "Perfect" }, CFG)
		expect(combo).toBe(1)
		expect(tip).toBe(7) -- 3 x 1.5 + 3 x 1 = 7.5
	end)

	test("settle: a Good between Perfects keeps the run going (it only doesn't add)", function()
		local combo, tip = MiniGame.settle(1, { "Perfect", "Good", "Perfect" }, CFG)
		expect(combo).toBe(3) -- 1 -> 2, held at 2, -> 3
		expect(tip).toBe(6) -- 3 x 1 + 3 x 1.2 = 6.6, floored
		combo = MiniGame.settle(9, { "Good", "Good", "Good" }, CFG)
		expect(combo).toBe(9) -- Simple mode (all Good) neither builds nor breaks a combo
		combo = MiniGame.settle(9, { "Good", "junk" :: any }, CFG)
		expect(combo).toBe(0) -- anything that isn't Perfect or Good counts as the miss
	end)

	test("settle: tips never pass the cap per cure, and a Cheerer scales them", function()
		local _, tip = MiniGame.settle(9, { "Perfect", "Perfect", "Perfect" }, CFG)
		expect(tip).toBe(15) -- 6 + 6 + 6 = 18, capped
		local _, after = MiniGame.settle(9, { "Perfect" }, CFG, 12)
		expect(after).toBe(3)
		local _, none = MiniGame.settle(9, { "Perfect" }, CFG, 15)
		expect(none).toBe(0)
		local _, cheered = MiniGame.settle(0, { "Perfect" }, CFG, 0, 1.5)
		expect(cheered).toBe(4) -- floor(4.5)
	end)
end)
