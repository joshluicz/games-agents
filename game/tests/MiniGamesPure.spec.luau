--!strict
-- The mini-games client's pure helpers (build plan T2): the block between "PURE:BEGIN" and "PURE:END" in
-- src/client/UI/MiniGames.luau, loaded on its own (the rest of that file needs Roblox), plus how they meet the
-- frozen Logic/MiniGame. Run from game/ (it reads the sources by path). Config uses Vector3, so the plan's
-- Config.MiniGame numbers are copied here like tests/MiniGame.spec.luau does.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local function source(path: string): string
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("can't find " .. path .. " (run from game/)")
end

local function loadPure(): any
	local text = source("src/client/UI/MiniGames.luau")
	local first = string.find(text, "PURE:BEGIN", 1, true)
	local last = string.find(text, "PURE:END", 1, true)
	assert(first and last and last > first, "PURE markers missing")
	local from = (string.find(text, "\n", first, true) :: number) + 1
	local upto = (string.find(text, "\n[^\n]*PURE:END", from) :: number) - 1
	return luau.load(string.sub(text, from, upto) .. "\nreturn Pure", { debugName = "MiniGames.Pure" })()
end

local Pure = loadPure()
local MiniGame = luau.load(source("src/shared/Logic/MiniGame.luau"), { debugName = "Logic.MiniGame" })()

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

-- A fixed "random" sequence, so scatter and freeSlot are repeatable.
local function sequence(values: { number }): () -> number
	local index = 0
	return function(): number
		index = index % #values + 1
		return values[index]
	end
end

T.describe("MiniGames (client pure helpers)", function()
	test("session: a good payload is tidied", function()
		local s = Pure.session({
			Session = 7,
			PatientId = "DumplingFrog",
			Items = { "Bubbles", "Potion" },
			Games = { "Scrub", "Pour" },
			Simple = false,
			Combo = 2.7,
			Position = "ignored",
			Timeout = 24,
		})
		expect(s.Session).toBe(7)
		expect(s.PatientId).toBe("DumplingFrog")
		expect(s.Games).toEqual({ "Scrub", "Pour" })
		expect(s.Items).toEqual({ "Bubbles", "Potion" })
		expect(s.Simple).toBe(false)
		expect(s.Combo).toBe(2)
		expect(s.Timeout).toBe(24)
	end)

	test("session: missing or junk fields get safe values", function()
		local s = Pure.session({ Session = 1, Games = { "Patch", "Cool" }, Items = { 5 }, Simple = "yes", Combo = -3 })
		expect(s.Items).toEqual({ "", "" })
		expect(s.PatientId).toBe("")
		expect(s.Simple).toBe(false)
		expect(s.Combo).toBe(0)
		expect(s.Timeout).toBeNil()
		expect(Pure.session({ Session = 1, Games = { "Pour" }, Timeout = 0 / 0 }).Timeout).toBeNil()
		expect(Pure.session({ Session = 1, Games = { "Pour" }, Timeout = -5 }).Timeout).toBeNil()
		expect(Pure.session({ Session = 1, Games = { "Pour" }, Combo = math.huge }).Combo).toBe(0)
		expect(Pure.session({ Session = 1, Games = { "Pour" }, Simple = true }).Simple).toBe(true)
	end)

	test("session: unplayable payloads are refused", function()
		expect(Pure.session(nil)).toBeNil()
		expect(Pure.session("Pour")).toBeNil()
		expect(Pure.session({ Games = { "Pour" } })).toBeNil()
		expect(Pure.session({ Session = "1", Games = { "Pour" } })).toBeNil()
		expect(Pure.session({ Session = 0 / 0, Games = { "Pour" } })).toBeNil()
		expect(Pure.session({ Session = 1 })).toBeNil()
		expect(Pure.session({ Session = 1, Games = {} })).toBeNil()
		expect(Pure.session({ Session = 1, Games = { "Pour", 3 } })).toBeNil()
		expect(Pure.session({ Session = 1, Games = { "Pour", "Pour", "Pour", "Pour", "Pour", "Pour", "Pour" } })).toBeNil()
		-- An unknown game id is kept (the client plays it as one tap); only the shape is checked here.
		expect(Pure.session({ Session = 1, Games = { "Juggle" } }).Games).toEqual({ "Juggle" })
		expect(Pure.KNOWN.Juggle).toBeNil()
		expect(Pure.KNOWN.Cool).toBe(true)
	end)

	test("fill: rises with the hold and stops at full", function()
		expect(Pure.fill(0, 2.4)).toBe(0)
		expect(Pure.fill(1.2, 2.4)).toBeCloseTo(0.5)
		expect(Pure.fill(10, 2.4)).toBe(1)
		expect(Pure.fill(-1, 2.4)).toBe(0)
		expect(Pure.fill(0 / 0, 2.4)).toBe(0)
		expect(Pure.fill(1.2, nil)).toBeCloseTo(0.5) -- default FillSeconds 2.4, as Logic/MiniGame
		expect(Pure.fill(0.05, 0)).toBeCloseTo(0.5) -- a broken FillSeconds can't divide by zero
	end)

	test("bands: what the bottle draws is what Logic/MiniGame rates", function()
		local lo, hi, goodLo, goodHi = Pure.bands(CFG.MiniGame.Pour)
		expect(lo).toBe(0.7)
		expect(hi).toBe(0.86)
		expect(goodLo).toBeCloseTo(0.58)
		expect(goodHi).toBeCloseTo(0.98)
		local dLo, dHi, dGoodLo, dGoodHi = Pure.bands(nil)
		expect(dLo).toBe(lo)
		expect(dHi).toBe(hi)
		expect(dGoodLo).toBeCloseTo(goodLo)
		expect(dGoodHi).toBeCloseTo(goodHi)
		local cLo, cHi, cGoodLo, cGoodHi = Pure.bands({ BandMin = 0.9, BandMax = 0.5, GoodSlack = 0.3 })
		expect(cLo).toBe(0.9)
		expect(cHi).toBe(0.9) -- never below lo
		expect(cGoodLo).toBeCloseTo(0.6)
		expect(cGoodHi).toBe(1) -- clamped to the bottle
		for _, fill in { lo + 0.001, (lo + hi) / 2, hi - 0.001 } do
			expect(MiniGame.rate("Pour", fill, CFG)).toBe("Perfect")
		end
		for _, fill in { goodLo + 0.001, lo - 0.01, hi + 0.01, goodHi - 0.001 } do
			expect(MiniGame.rate("Pour", fill, CFG)).toBe("Good")
		end
		for _, fill in { 0, goodLo - 0.01, goodHi + 0.01, 1 } do
			expect(MiniGame.rate("Pour", fill, CFG)).toBe("OK")
		end
	end)

	test("Pour: a hold of about 1.7-2.0 s lands in the band (Perfect)", function()
		local seconds = CFG.MiniGame.Pour.FillSeconds
		expect(MiniGame.rate("Pour", Pure.fill(1.8, seconds), CFG)).toBe("Perfect")
		expect(MiniGame.rate("Pour", Pure.fill(1.5, seconds), CFG)).toBe("Good")
		expect(MiniGame.rate("Pour", Pure.fill(0.5, seconds), CFG)).toBe("OK")
		expect(MiniGame.rate("Pour", Pure.fill(9, seconds), CFG)).toBe("OK") -- overflowed
	end)

	test("ring: small, biggest halfway, small again", function()
		expect(Pure.ring(0, 1.2, 0.3)).toBeCloseTo(0.3)
		expect(Pure.ring(0.6, 1.2, 0.3)).toBeCloseTo(1)
		expect(Pure.ring(1.2, 1.2, 0.3)).toBeCloseTo(0.3)
		expect(Pure.ring(0.3, 1.2, 0.3) < Pure.ring(0.5, 1.2, 0.3)).toBe(true)
		expect(Pure.ring(5, 1.2, 0.3)).toBeCloseTo(0.3) -- past the end: clamped
		expect(Pure.ring(0 / 0, nil, nil)).toBeCloseTo(0.3)
	end)

	test("goodBlow: within Window of the biggest moment", function()
		expect(Pure.goodBlow(0.6, 1.2, 0.3)).toBe(true)
		expect(Pure.goodBlow(0.3, 1.2, 0.3)).toBe(true)
		expect(Pure.goodBlow(0.9, 1.2, 0.3)).toBe(true)
		expect(Pure.goodBlow(0.29, 1.2, 0.3)).toBe(false)
		expect(Pure.goodBlow(0.91, 1.2, 0.3)).toBe(false)
		expect(Pure.goodBlow(0.9, 1.2, 0.3)).toBe(true) -- the edge counts despite float rounding
		expect(Pure.goodBlow(0.05, 1.2, 0.3)).toBe(false)
		expect(Pure.goodBlow(-0.1, 1.2, 5)).toBe(false)
		expect(Pure.goodBlow(1.3, 1.2, 5)).toBe(false)
		expect(Pure.goodBlow(0 / 0, 1.2, 0.3)).toBe(false)
		-- The ring is big while a blow is good: at the window's edge it's still past 70% of the way up.
		expect(Pure.ring(0.3, 1.2, 0) >= 0.7).toBe(true)
	end)

	test("Cool: three good blows rate Perfect, two Good", function()
		local cool = CFG.MiniGame.Cool
		local good = 0
		for _, t in { 0.6, 0.45, 0.8 } do
			if Pure.goodBlow(t, cool.PulseSeconds, cool.Window) then
				good += 1
			end
		end
		expect(MiniGame.rate("Cool", good, CFG)).toBe("Perfect")
		expect(MiniGame.rate("Cool", good - 1, CFG)).toBe("Good")
	end)

	test("scatter: inside the box, spread out, repeatable", function()
		local box = { 0.27, 0.4, 0.73, 0.82 }
		local r01 = sequence({ 0.1, 0.1, 0.9, 0.9, 0.5, 0.15, 0.9, 0.1 })
		local points = Pure.scatter(3, box, 0.3, r01)
		expect(#points).toBe(3)
		for _, p in points do
			expect(p.X >= box[1] and p.X <= box[3] and p.Y >= box[2] and p.Y <= box[4]).toBe(true)
		end
		for i = 1, #points do
			for j = i + 1, #points do
				local d = math.sqrt((points[i].X - points[j].X) ^ 2 + (points[i].Y - points[j].Y) ^ 2)
				expect(d >= 0.3).toBe(true)
			end
		end
		local again = Pure.scatter(3, box, 0.3, sequence({ 0.1, 0.1, 0.9, 0.9, 0.5, 0.15, 0.9, 0.1 }))
		expect(again).toEqual(points)
		-- No pick has room: it takes the roomiest of its tries.
		local tight = Pure.scatter(2, { 0, 0, 1, 1 }, 0.9, sequence({ 0, 0, 0.1, 0.1, 0.5, 0.5, 0.2, 0.2 }), nil, 3)
		expect(tight[2].X).toBeCloseTo(0.5)
		expect(tight[2].Y).toBeCloseTo(0.5)
	end)

	test("scatter: avoids given points; a full box still gives every point", function()
		local p = Pure.scatter(1, { 0, 0, 1, 1 }, 0.5, sequence({ 0.1, 0.1, 0.9, 0.9 }), { { X = 0.1, Y = 0.1 } })
		expect(p[1].X).toBeCloseTo(0.9)
		expect(p[1].Y).toBeCloseTo(0.9)
		local crowded = Pure.scatter(5, { 0.4, 0.4, 0.6, 0.6 }, 0.5, sequence({ 0.2, 0.7, 0.5, 0.1 }), nil, 4)
		expect(#crowded).toBe(5)
		expect(#Pure.scatter(0, { 0, 0, 1, 1 }, 0.1, math.random)).toBe(0)
		expect(#Pure.scatter(0 / 0, { 0, 0, 1, 1 }, 0.1, math.random)).toBe(0)
	end)

	test("freeSlot: only free slots, nil when full", function()
		expect(Pure.freeSlot(3, { true, true, true }, sequence({ 0.5 }))).toBeNil()
		expect(Pure.freeSlot(0, {}, sequence({ 0.5 }))).toBeNil()
		expect(Pure.freeSlot(3, { [1] = true, [3] = true }, sequence({ 0.99 }))).toBe(2)
		expect(Pure.freeSlot(6, { [2] = true }, sequence({ 0 }))).toBe(1)
		expect(Pure.freeSlot(6, { [2] = true }, sequence({ 0.9999 }))).toBe(6)
		expect(Pure.freeSlot(6, {}, sequence({ 1 }))).toBe(6) -- r01 of exactly 1 stays in range
	end)

	test("holdBack: the report never beats the server's minimum time", function()
		local games = { "Pour", "Patch" }
		local minimum = MiniGame.minSeconds(games, false, CFG)
		expect(Pure.holdBack(0.5, minimum, 0.15)).toBeCloseTo(minimum + 0.15 - 0.5)
		expect(Pure.holdBack(30, minimum, 0.15)).toBe(0)
		expect(Pure.holdBack(0 / 0, 1, nil)).toBe(1)
		-- Waiting holdBack after any elapsed time is always enough for MiniGame.accept to keep the ratings.
		for _, elapsed in { 0, 0.4, 1.9, 5 } do
			local total = elapsed + Pure.holdBack(elapsed, minimum, 0.15)
			local kept = MiniGame.accept({ "Perfect", "Good" }, games, total, false, CFG)
			expect(kept).toEqual({ "Perfect", "Good" })
		end
	end)

	test("multText: the combo chip's multiplier tag", function()
		expect(Pure.multText(1)).toBe("")
		expect(Pure.multText(0.5)).toBe("")
		expect(Pure.multText(0 / 0)).toBe("")
		expect(Pure.multText(1.2)).toBe("×1.2")
		expect(Pure.multText(1.5)).toBe("×1.5")
		expect(Pure.multText(2)).toBe("×2")
		expect(Pure.multText(MiniGame.multiplier(3, CFG))).toBe("×1.2")
		expect(Pure.multText(MiniGame.multiplier(2, CFG))).toBe("")
	end)

	test("the predicted combo the chip shows matches Logic/MiniGame.settle", function()
		local combo = MiniGame.settle(2, { "Perfect" }, CFG)
		expect(combo).toBe(3)
		expect(Pure.multText(MiniGame.multiplier(combo, CFG))).toBe("×1.2")
		expect((MiniGame.settle(2, { "Perfect", "Good" }, CFG))).toBe(3) -- a GOOD! holds the 🔥 (§E7)
		expect((MiniGame.settle(2, { "Perfect", "OK" }, CFG))).toBe(0) -- an OK sends it back to "Go!"
		expect((MiniGame.settle(0, { "Good", "Good" }, CFG))).toBe(0) -- Simple mode never builds a combo
	end)
end)

return nil
