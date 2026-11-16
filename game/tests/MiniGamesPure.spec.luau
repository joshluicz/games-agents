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

local function near(a: number, b: number): boolean
	return math.abs(a - b) <= 1e-9
end

------------------------------------------------------------------------------------------------------------------
-- Progression v2 (build plan §B3 TreatSession / TreatOutcome, §C T8): auto games, the ease scaling, the Soak kind
-- and the triage card's states. Same pure block, plus the frozen Logic/MiniGame they must agree with.
------------------------------------------------------------------------------------------------------------------

local Departments = luau.load(source("src/shared/Data/Departments.luau"), { debugName = "Data.Departments" })()

local function payload(extra: { [string]: any }): { [string]: any }
	local raw: { [string]: any } = {
		Session = 3,
		PatientId = "DumplingFrog",
		Items = { "Plaster", "Potion" },
		Games = { "Patch", "Pour" },
		Simple = false,
		Combo = 0,
		Position = "ignored",
		Timeout = 24,
	}
	for key, value in extra do
		raw[key] = value
	end
	return raw
end

T.describe("MiniGames v2: the session's new fields", function()
	test("defaults when the server sends none: Treat, nothing auto, no ease", function()
		local s = Pure.session(payload({}))
		expect(s.Kind).toBe("Treat")
		expect(s.Auto).toEqual({ false, false })
		expect(s.Ease).toBe(1)
	end)
	test("Auto lines up with the games; anything but true is false", function()
		local s = Pure.session(payload({ Auto = { true, "yes" } }))
		expect(s.Auto).toEqual({ true, false })
		s = Pure.session(payload({ Auto = { [2] = true } }))
		expect(s.Auto).toEqual({ false, true })
		s = Pure.session(payload({ Auto = "all" }))
		expect(s.Auto).toEqual({ false, false })
	end)
	test("Ease is clamped to 1..1.3 (junk = 1)", function()
		expect(Pure.session(payload({ Ease = 1.2 })).Ease).toBe(1.2)
		expect(Pure.session(payload({ Ease = 5 })).Ease).toBe(Pure.EASE_MAX)
		expect(Pure.session(payload({ Ease = 0.5 })).Ease).toBe(1)
		expect(Pure.session(payload({ Ease = 0 / 0 })).Ease).toBe(1)
		expect(Pure.session(payload({ Ease = "wide" })).Ease).toBe(1)
	end)
	test("Soak: the hot tub's one Scrub game with no items", function()
		local s = Pure.session({ Session = 9, Kind = "Soak", Items = {}, Games = { "Scrub" }, Combo = 1, Timeout = 18 })
		expect(s.Kind).toBe("Soak")
		expect(s.Games).toEqual({ "Scrub" })
		expect(s.Items).toEqual({ "" })
		expect(Pure.session(payload({ Kind = "Bath" })).Kind).toBe("Treat")
	end)
end)

T.describe("MiniGames v2: auto games", function()
	test("played: only the games not made PERFECT count", function()
		expect(Pure.played({ "Patch", "Pour", "Cool" }, { true, false, true })).toEqual({ "Pour" })
		expect(Pure.played({ "Patch", "Pour" }, nil)).toEqual({ "Patch", "Pour" })
		expect(Pure.played({ "Patch" }, { true })).toEqual({})
	end)
	test("the report waits only for the played games, as the server's accept counts them", function()
		local games, auto = { "Patch", "Pour", "Cool" }, { true, false, true }
		local minimum = MiniGame.minSeconds(Pure.played(games, auto), false, CFG)
		expect(minimum).toBe(CFG.MiniGame.MinSeconds.Pour)
		-- A report right after that minimum is accepted as it is; the auto games come back Perfect whatever was sent.
		local ratings = MiniGame.accept({ "Perfect", "Good", "Perfect" }, games, minimum, false, CFG, auto)
		expect(ratings).toEqual({ "Perfect", "Good", "Perfect" })
		ratings = MiniGame.accept({ "OK", "Good", "OK" }, games, minimum, false, CFG, auto)
		expect(ratings).toEqual({ "Perfect", "Good", "Perfect" })
	end)
	test("all games auto: nothing to wait for", function()
		local minimum = MiniGame.minSeconds(Pure.played({ "Patch", "Scrub" }, { true, true }), false, CFG)
		expect(minimum).toBe(0)
		expect(Pure.holdBack(0, minimum, 0.15)).toBe(0.15)
	end)
	test("the predicted combo counts an auto Perfect like any other", function()
		local combo = MiniGame.settle(2, { "Perfect", "Perfect" }, CFG)
		expect(combo).toBe(4)
	end)
end)

T.describe("MiniGames v2: 🎯 Steady Hands widens the windows", function()
	local mini = CFG.MiniGame
	test("ease 1 (or junk) is the plain settings, as a fresh copy", function()
		local plain = Pure.eased(mini, 1)
		expect(plain.Pour.BandMin).toBe(mini.Pour.BandMin)
		expect(plain.Cool.Window).toBe(mini.Cool.Window)
		expect(plain ~= mini).toBeTruthy()
		expect(Pure.eased(mini, "x").Pour.BandMax).toBe(mini.Pour.BandMax)
		expect(Pure.eased(nil, 1.2).Pour.BandMin < 0.7).toBeTruthy() -- the Logic defaults, widened
	end)
	test("the Pour's ⭐ band widens round its middle; the Good slack grows too", function()
		local eased = Pure.eased(mini, 1.3)
		local width = mini.Pour.BandMax - mini.Pour.BandMin
		local middle = (mini.Pour.BandMax + mini.Pour.BandMin) / 2
		expect(near(eased.Pour.BandMax - eased.Pour.BandMin, width * 1.3)).toBeTruthy()
		expect(near((eased.Pour.BandMax + eased.Pour.BandMin) / 2, middle)).toBeTruthy()
		expect(near(eased.Pour.GoodSlack, mini.Pour.GoodSlack * 1.3)).toBeTruthy()
		expect(mini.Pour.BandMin).toBe(0.7) -- the shipped table is never changed
	end)
	test("a fill just outside the plain band is Perfect once eased, and rated the same as drawn", function()
		local fill = mini.Pour.BandMax + 0.02
		expect(MiniGame.rate("Pour", fill, CFG)).toBe("Good")
		expect(MiniGame.rate("Pour", fill, { MiniGame = Pure.eased(mini, 1.3) })).toBe("Perfect")
		local lo, hi = Pure.bands(Pure.eased(mini, 1.3).Pour)
		expect(fill >= lo and fill <= hi).toBeTruthy()
	end)
	test("the Cool's blow window, and more time to patch and scrub", function()
		local eased = Pure.eased(mini, 1.2)
		expect(near(eased.Cool.Window, mini.Cool.Window * 1.2)).toBeTruthy()
		expect(near(eased.Patch.Seconds, mini.Patch.Seconds * 1.2)).toBeTruthy()
		expect(near(eased.Scrub.Seconds, mini.Scrub.Seconds * 1.2)).toBeTruthy()
		local pulse = mini.Cool.PulseSeconds
		local late = pulse / 2 + mini.Cool.Window + 0.03
		expect(Pure.goodBlow(late, pulse, mini.Cool.Window)).toBe(false)
		expect(Pure.goodBlow(late, pulse, eased.Cool.Window)).toBe(true)
	end)
	test("the thresholds to reach (spots, bubbles, blows) never change: only the windows", function()
		local eased = Pure.eased(mini, 1.3)
		expect(eased.Patch.Spots).toBe(mini.Patch.Spots)
		expect(eased.Scrub.Perfect).toBe(mini.Scrub.Perfect)
		expect(eased.Cool.Blows).toBe(mini.Cool.Blows)
		expect(eased.TipCapPerCure).toBe(mini.TipCapPerCure)
	end)
end)

T.describe("MiniGames v2: the triage card's states", function()
	test("a card: one big button per known floor, in order, with its icon", function()
		local card = Pure.triage({ Options = { "Wards", "Hydro" }, Seconds = 4 }, Departments)
		expect(card.Seconds).toBe(4)
		expect(#card.Options).toBe(2)
		expect(card.Options[1].Dept).toBe("Wards")
		expect(card.Options[1].Icon).toBe(Departments.Wards.Icon)
		expect(card.Options[2].Icon).toBe(Departments.Hydro.Icon)
	end)
	test("no card: junk, one floor, unknown floors, repeats, no time", function()
		expect(Pure.triage(nil, Departments)).toBeNil()
		expect(Pure.triage({ Options = { "Wards" }, Seconds = 4 }, Departments)).toBeNil()
		expect(Pure.triage({ Options = { "Wards", "Wards" }, Seconds = 4 }, Departments)).toBeNil()
		expect(Pure.triage({ Options = { "Wards", "Order" }, Seconds = 4 }, Departments)).toBeNil()
		expect(Pure.triage({ Options = { "Wards", "Hydro" }, Seconds = 0 }, Departments)).toBeNil()
		expect(Pure.triage({ Options = { "Wards", "Hydro" } }, Departments)).toBeNil()
		expect(Pure.triage({ Options = "Wards,Hydro", Seconds = 4 }, Departments)).toBeNil()
	end)
	test("at most TRIAGE_MAX buttons, and a long wait is capped", function()
		local card = Pure.triage({ Options = { "Wards", "Hydro", "Pharmacy", "AE" }, Seconds = 99 }, Departments)
		expect(#card.Options).toBe(Pure.TRIAGE_MAX)
		expect(card.Seconds).toBe(Pure.TRIAGE_SECONDS_MAX)
	end)
	test("the soft bar drains from full to empty, never digits", function()
		expect(Pure.triageBar(0, 4)).toBe(1)
		expect(Pure.triageBar(2, 4)).toBe(0.5)
		expect(Pure.triageBar(9, 4)).toBe(0)
		expect(Pure.triageBar(-1, 4)).toBe(1)
		expect(Pure.triageBar(1, 0)).toBe(0)
	end)
	test("the answer: Right, Wrong (it still goes the right way) or Quiet", function()
		expect(Pure.triageResult(true, "", { Right = true })).toBe("Right")
		expect(Pure.triageResult(true, "", { Right = false })).toBe("Wrong")
		expect(Pure.triageResult(true, "✅ Right floor!", nil)).toBe("Right")
		expect(Pure.triageResult(true, "Oops, not this floor!", nil)).toBe("Wrong")
		expect(Pure.triageResult(false, "Oops, not this floor!", nil)).toBe("Wrong")
		expect(Pure.triageResult(false, "Oops! Try again.", nil)).toBe("Quiet") -- an error: nothing to say
		expect(Pure.triageResult(false, "", nil)).toBe("Quiet") -- rate-limited or too late
		expect(Pure.TRIAGE_TEXT.Right.Text).toBe("Right floor!")
		expect(Pure.TRIAGE_TEXT.Wrong.Text).toBe("Oops, not this floor!")
	end)
end)

return nil
