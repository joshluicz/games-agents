--!strict
-- The mini-games client's pure helpers (build plan T2; the Real Clinic's Task 7): the block between "PURE:BEGIN" and
-- "PURE:END" in src/client/UI/MiniGames.luau, loaded on its own (the rest of that file needs Roblox), plus how they
-- meet Logic/MiniGame. Run from game/ (it reads the sources by path). The older tests copy the plan's Config.MiniGame
-- numbers (CFG below); the Real Clinic's load the real Config (tests/config.luau) so they can't pass on stale copies.

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
			Items = { "Bubbles", "Ice" },
			Games = { "Scrub", "Pour" },
			Simple = false,
			Combo = 2.7,
			Position = "ignored",
			Timeout = 24,
		})
		expect(s.Session).toBe(7)
		expect(s.PatientId).toBe("DumplingFrog")
		expect(s.Games).toEqual({ "Scrub", "Pour" })
		expect(s.Items).toEqual({ "Bubbles", "Ice" })
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

	test("session: a handover has no games; no games without Handover is refused", function()
		local s = Pure.session({ Session = 7, Games = {}, Handover = true, Kind = "Treat" })
		expect(s ~= nil).toBe(true)
		expect(s.Games).toEqual({})
		expect(s.Handover).toBe(true)
		expect(s.Kind).toBe("Treat")
		expect(Pure.session({ Session = 7, Games = {} })).toBeNil()
		expect(Pure.session({ Session = 7, Games = {}, Handover = "yes" })).toBeNil()
		expect(Pure.session({ Session = 7, Games = { "Ice" }, Handover = true }).Handover).toBe(false)
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
-- Progression v2 (build plan §B3 TreatSession / TreatOutcome, §C T8): auto games, the ease scaling
-- and the triage card's states. Same pure block, plus the frozen Logic/MiniGame they must agree with.
------------------------------------------------------------------------------------------------------------------

local Departments = luau.load(source("src/shared/Data/Departments.luau"), { debugName = "Data.Departments" })()

local function payload(extra: { [string]: any }): { [string]: any }
	local raw: { [string]: any } = {
		Session = 3,
		PatientId = "DumplingFrog",
		Items = { "Plaster", "Ice" },
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
	test("the hot tub's Soak kind is gone: an unknown Kind is a Treat", function()
		local s = Pure.session({ Session = 9, Kind = "Soak", Items = {}, Games = { "Scrub" }, Combo = 1, Timeout = 18 })
		expect(s.Kind).toBe("Treat")
		expect(s.Games).toEqual({ "Scrub" })
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
		-- The Real Clinic's floors: 🛏️ the Injury Ward and 😴 the Rest Ward (Logic/Hospital triage options).
		local card = Pure.triage({ Options = { "Wards", "Rest" }, Seconds = 4 }, Departments)
		expect(card.Seconds).toBe(4)
		expect(#card.Options).toBe(2)
		expect(card.Options[1].Dept).toBe("Wards")
		expect(card.Options[1].Icon).toBe(Departments.Wards.Icon)
		expect(card.Options[2].Icon).toBe(Departments.Rest.Icon)
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

------------------------------------------------------------------------------------------------------------------
-- The Real Clinic (build plan Task 7, contract C5; design §5, §7, §9): every GameId's look, the dispatch to the
-- engines, the exam's tools and the dispensary's bottles, phone fit (Review Focus 5), the case reveal, and the
-- windows each game is drawn and rated with. These read the real Config and Data.
------------------------------------------------------------------------------------------------------------------

local roblox = require("@lune/roblox")
local Config = require("./config")
local UiRules = require("./uirules")

local function data(path: string): any
	return luau.load(source(path), { debugName = path })()
end

local Items = data("src/shared/Data/Items.luau")
local Tools = data("src/shared/Data/Tools.luau")
local Cases = data("src/shared/Data/Cases.luau")
local Visit = data("src/shared/Logic/Visit.luau")

local MINI = source("src/client/UI/MiniGames.luau")
local SOUNDS = source("src/client/Feel/Sounds.luau")
local THEME = source("src/client/UI/Theme.luau")

-- The code of a source without its comments (a rule never trips on its own explanation).
local function codeOf(text: string): string
	local out = {}
	for line in string.gmatch(text .. "\n", "(.-)\r?\n") do
		local body = line
		local quote: string? = nil
		local index = 1
		while index <= #line do
			local c = string.sub(line, index, index)
			if quote then
				if c == "\\" then
					index += 1
				elseif c == quote then
					quote = nil
				end
			elseif c == '"' or c == "'" then
				quote = c
			elseif c == "-" and string.sub(line, index + 1, index + 1) == "-" then
				body = string.sub(line, 1, index - 1)
				break
			end
			index += 1
		end
		table.insert(out, body)
	end
	return table.concat(out, "\n")
end

-- Sounds.CUES has a cue of this name.
local function isCue(name: string): boolean
	local first = string.find(SOUNDS, "Sounds.CUES = table.freeze({", 1, true)
	local last = string.find(SOUNDS, "} :: { [string]: Cue })", 1, true)
	local cues = if first and last then string.sub(SOUNDS, first, last) else ""
	return string.find(cues, "\n\t" .. name .. " = {", 1, true) ~= nil
end

-- Theme.Colors has a colour of this name.
local function isThemeColor(name: string): boolean
	local first = string.find(THEME, "Theme.Colors = table.freeze({", 1, true)
	local last = first and string.find(THEME, "\n})", first, true)
	local colors = if first and last then string.sub(THEME, first, last) else ""
	return string.find(colors, "\n\t" .. name .. " = ", 1, true) ~= nil
end

local function overlaps(a: any, b: any): boolean
	return a.X < b.X + b.W and b.X < a.X + a.W and a.Y < b.Y + b.H and b.Y < a.Y + a.H
end

local function checkTargets(rects: { any }, stage: any, n: number, where: string)
	assert(#rects == n, where .. ": " .. #rects .. " targets for " .. n)
	for i, r in rects do
		assert(r.W >= Pure.TAP_MIN and r.H >= Pure.TAP_MIN, where .. ": target " .. i .. " is " .. r.W .. " px")
		assert(r.X >= 0 and r.Y >= 0, where .. ": target " .. i .. " starts off the stage")
		assert(r.X + r.W <= stage.X + 1e-6 and r.Y + r.H <= stage.Y + 1e-6, where .. ": target " .. i .. " leaves it")
		for j = i + 1, #rects do
			assert(not overlaps(r, rects[j]), where .. ": targets " .. i .. " and " .. j .. " overlap")
		end
	end
end

local CURE = "%f[%a][Cc][Uu][Rr][Ee]"

T.describe("The Real Clinic: every game's look", function()
	test("every GameId has a look: icon, short title and hint, a real sound, a Theme colour", function()
		for _, id in MiniGame.GAME_IDS do
			local look = Pure.LOOKS[id]
			assert(type(look) == "table", "no look for " .. id)
			for _, key in { "Icon", "Title", "Hint", "Sound", "Tint" } do
				assert(type(look[key]) == "string" and look[key] ~= "", id .. " has no " .. key)
			end
			assert(utf8.len(look.Title) <= Pure.HINT_MAX, id .. ": the title is too long for a phone")
			assert(utf8.len(look.Hint) <= Pure.HINT_MAX, id .. ": the hint is too long for a phone")
			assert(isCue(look.Sound), id .. ": no Sounds cue " .. look.Sound)
			assert(isThemeColor(look.Tint), id .. ": no Theme colour " .. look.Tint)
		end
	end)
	test("each look carries its engine's skin", function()
		for _, id in MiniGame.GAME_IDS do
			local look, engine = Pure.LOOKS[id], MiniGame.ENGINE[id]
			if engine == "Pour" then
				assert(table.find({ "Bottle", "Cup", "Tube", "Pack" }, look.Vessel), id .. ": a Pour needs a Vessel")
				assert(look.Liquid == "Bottle" or string.match(look.Liquid, "^#%x%x%x%x%x%x$"), id .. ": Liquid")
			elseif engine == "Patch" then
				assert(type(look.Mark) == "string" and look.Mark ~= "", id .. ": a Patch needs a Mark")
				assert(look.Spot == "Sore" or look.Spot == "Glow", id .. ": Spot")
			elseif engine == "Cool" then
				assert(look.Style == "Ring" or look.Style == "Sweep", id .. ": a Cool needs a Style")
				assert(type(look.Good) == "string" and type(look.Miss) == "string", id .. ": pips")
				assert(type(look.Target) == "string", id .. ": Target")
			end
		end
		-- The dispensary's cup is the chosen medicine's colour, poured from its own bottle (design §9).
		expect(Pure.LOOKS.Dose.Vessel).toBe("Cup")
		expect(Pure.LOOKS.Dose.Liquid).toBe("Bottle")
		expect(Pure.LOOKS.Dose.Pourer).toBe("Bottle")
		-- Design §7: the X-ray's scanner bar, the wraps' 3 and 4 beats, the stethoscope's glowing spots.
		expect(Pure.LOOKS.XRay.Style).toBe("Sweep")
		expect(Pure.LOOKS.Bandage.Style).toBe("Sweep")
		expect(Pure.LOOKS.Cast.Style).toBe("Sweep")
		expect(Pure.LOOKS.Listen.Spot).toBe("Glow")
		expect(Config.MiniGame.Games.Cast.Blows).toBe(4)
		expect(Config.MiniGame.Games.Look.Spots).toBe(2)
	end)
	test("a tool's game and a supply's game wear that tool's or supply's icon", function()
		for _, id in Tools.ORDER do
			expect(Pure.LOOKS[Tools[id].Game].Icon).toBe(Tools[id].Icon)
		end
		for _, id in Items.Order do
			local item = Items[id]
			if item.Kind == "Supply" then
				expect(Pure.LOOKS[item.Game].Icon).toBe(item.Icon)
			end
		end
	end)
	test("the cards' words are short, and nothing says cure or anything scary", function()
		for key, text in Pure.WORDS do
			assert(utf8.len(text) <= Pure.HINT_MAX, "WORDS." .. key .. " is too long for a phone")
		end
		local scary = { CURE, "[Nn]eedle", "[Bb]lood", "[Ss]urgery", "[Hh]urt" }
		local function clean(text: string, where: string)
			for _, pattern in scary do
				assert(not string.find(text, pattern), where .. ": " .. text)
			end
		end
		for key, text in Pure.WORDS do
			clean(text, "WORDS." .. key)
		end
		for id, look in Pure.LOOKS do
			clean(look.Title, id)
			clean(look.Hint, id)
		end
		-- Every string the file shows (comments aside: internal names like CureFX may be named there).
		for literal in string.gmatch(codeOf(MINI), '"([^"\n]*)"') do
			clean(literal, "MiniGames.luau")
		end
	end)
	test("Sounds has the Real Clinic's cues, and lists them", function()
		local first = string.find(SOUNDS, "Sounds.CLINIC_CUES = table.freeze({", 1, true)
		assert(first, "Sounds.CLINIC_CUES is missing")
		for _, name in { "Listen", "Beep", "Shine", "Scan", "Cold", "Wrap", "Found" } do
			assert(isCue(name), "no cue " .. name)
			assert(string.find(SOUNDS, '\t"' .. name .. '",', first, true), name .. " is not in CLINIC_CUES")
		end
		assert(isCue("Nope"), "a wrong pick's gentle Nope")
		-- A dispensed medicine (Kind "Medicine") bubbles in your hands; the old crafted-medicine field is gone.
		local code = codeOf(SOUNDS)
		assert(string.find(code, 'item.Kind == "Medicine"', 1, true), "medicines are found by Kind")
		expect(string.find(code, "item.Medicine", 1, true)).toBeNil()
	end)
	test("uirules hold on the mini-games file", function()
		local violations = UiRules.check({ "src/client/UI/MiniGames.luau" })
		assert(#violations == 0, "\n" .. UiRules.format(violations))
	end)
end)

T.describe("The Real Clinic: the dispatch plays each engine for its ids", function()
	test("every GameId plays its engine's routine; Simple and unknown games are one tap", function()
		for _, id in MiniGame.GAME_IDS do
			local engine = MiniGame.ENGINE[id]
			assert(Pure.KNOWN[engine], "this client can't draw the " .. engine .. " engine")
			expect(Pure.engine(id, MiniGame.ENGINE)).toBe(engine)
			expect(Pure.dispatch(id, MiniGame.ENGINE, false)).toBe(engine)
			expect(Pure.dispatch(id, MiniGame.ENGINE, true)).toBe("Tap")
		end
		-- An engine's own name still plays as itself (a session that still names one).
		for _, engine in { "Pour", "Patch", "Scrub", "Cool", "Pick" } do
			expect(Pure.dispatch(engine, MiniGame.ENGINE, false)).toBe(engine)
		end
		expect(Pure.dispatch("Juggle", MiniGame.ENGINE, false)).toBe("Tap")
		expect(Pure.dispatch(nil, MiniGame.ENGINE, false)).toBe("Tap")
		expect(Pure.engine("Listen", nil)).toBeNil() -- no engine map: only the engines' own names are known
	end)
	test("the routine table has a player for every route", function()
		local first = string.find(MINI, "local PLAY: { [string]: (env: Env) -> number } = {", 1, true)
		assert(first, "the PLAY table is missing")
		local last = string.find(MINI, "\n}", first, true) :: number
		local block = string.sub(MINI, first, last)
		for route, fn in
			{
				Pour = "playPour",
				Patch = "playPatch",
				Scrub = "playScrub",
				Cool = "playCool",
				Pick = "playPickGame",
				Tap = "playTap",
			}
		do
			assert(
				string.find(block, "\t" .. route .. " = " .. fn .. ",", 1, true),
				"PLAY." .. route .. " is not " .. fn
			)
		end
		assert(
			string.find(MINI, "Pure.dispatch(gameId, MiniGame.ENGINE, session.Simple)", 1, true),
			"playOne dispatches"
		)
	end)
	test("Pick: wrong taps rate 0 Perfect, 1 Good, more OK (the real Config)", function()
		expect(MiniGame.rate("Pick", 0, Config)).toBe("Perfect")
		expect(MiniGame.rate("Pick", 1, Config)).toBe("Good")
		expect(MiniGame.rate("Pick", 2, Config)).toBe("OK")
		expect(MiniGame.rate("Pick", 3, Config)).toBe("OK")
	end)
	test("an exam's and a dispense's report never comes too early for the server", function()
		local tool = Tools[Cases.Cough.Tool].Game
		for _, games in { { "Pick", tool }, { "Pick", "XRay" }, { "Pick", "Dose" } } do
			local minimum = MiniGame.minSeconds(games, false, Config)
			for _, elapsed in { 0, 0.5, 1.4, 4 } do
				local total = elapsed + Pure.holdBack(elapsed, minimum, 0.15)
				local kept = MiniGame.accept({ "Perfect", "Good" }, games, total, false, Config)
				expect(kept).toEqual({ "Perfect", "Good" })
			end
		end
	end)
end)

T.describe("The Real Clinic: the session's new fields", function()
	test("an Exam: its tools (no repeats, at most CHOICES_MAX), the answer, the glow, a symptom clue", function()
		local s = Pure.session({
			Session = 4,
			Kind = "Exam",
			Games = { "Pick", "Listen" },
			Items = {},
			Tools = { "Stethoscope", "Light", "Stethoscope", 7, "Magnifier", "Thermometer", "XRay" },
			Answer = "Stethoscope",
			Glow = true,
			Symptom = "😷 cough cough",
		})
		expect(s.Kind).toBe("Exam")
		expect(s.Tools).toEqual({ "Stethoscope", "Light", "Magnifier", "Thermometer" })
		expect(s.Answer).toBe("Stethoscope")
		expect(s.Glow).toBe(true)
		expect(s.Symptom).toBe("😷 cough cough")
		expect(s.Items).toEqual({ "", "" })
		expect(s.Case).toBeNil()
	end)
	test("a Dispense: its options and the Expert flag", function()
		local s = Pure.session({
			Session = 5,
			Kind = "Dispense",
			Games = { "Pick", "Dose" },
			Options = { "CoughSyrup", "EarDrops", "", "CoughSyrup" },
			Expert = true,
		})
		expect(s.Kind).toBe("Dispense")
		expect(s.Options).toEqual({ "CoughSyrup", "EarDrops" })
		expect(s.Expert).toBe(true)
		expect(s.Glow).toBe(false)
	end)
	test("junk new fields get safe values; an unknown kind is a Treat", function()
		local s = Pure.session({
			Session = 6,
			Kind = "Surgery",
			Games = { "Plaster" },
			Tools = "Stethoscope",
			Answer = 3,
			Glow = "yes",
			Options = { 1, 2 },
			Case = "",
			Symptom = string.rep("x", 200),
			Expert = 1,
		})
		expect(s.Kind).toBe("Treat")
		expect(s.Tools).toEqual({})
		expect(s.Answer).toBeNil()
		expect(s.Glow).toBe(false)
		expect(s.Options).toEqual({})
		expect(s.Case).toBeNil()
		expect(s.Symptom).toBe("")
		expect(s.Expert).toBe(false)
		expect(Pure.session({ Session = 7, Kind = "Treat", Games = { "Ice" }, Case = "Sprain" }).Case).toBe("Sprain")
	end)
end)

T.describe("The Real Clinic: the exam's tools and the dispensary's shelf", function()
	test("choices: the answer is always there, no repeats, at most the max", function()
		expect(Pure.choices({ "Stethoscope", "Light", "Magnifier" }, "Light")).toEqual({
			"Stethoscope",
			"Light",
			"Magnifier",
		})
		expect(Pure.choices({ "Stethoscope", "Light" }, "XRay")).toEqual({ "Stethoscope", "Light", "XRay" })
		expect(Pure.choices({ "A", "B", "C" }, "D", 3)).toEqual({ "A", "B", "D" }) -- full: it takes the last place
		expect(Pure.choices({ "A", "A", "B" }, "B")).toEqual({ "A", "B" })
		expect(Pure.choices({}, "A")).toEqual({ "A" })
		expect(Pure.choices("junk", "A")).toEqual({ "A" })
		expect(Pure.choices({ "A" }, nil)).toBeNil()
		expect(Pure.choices({ "A" }, "")).toBeNil()
		-- The server's exam card (Logic/Visit.examTools) always fits.
		local card = Visit.examTools("XRay", Visit.unlocked(3, Tools), 0.42)
		expect(Pure.choices(card, "XRay")).toEqual(card)
		assert(Visit.EXAM_TOOLS <= Pure.CHOICES_MAX, "the exam card has more tools than a Pick shows")
	end)
	test("bottles: the shelf has Config.Dispensary.Bottles distinct medicines, the right one among them", function()
		local pool = {}
		for _, id in Items.Order do
			if Items[id].Kind == "Medicine" then
				table.insert(pool, { Id = id, Icon = Items[id].Icon })
			end
		end
		local count = Config.Dispensary.Bottles
		assert(count <= Pure.CHOICES_MAX, "more bottles than a Pick shows")
		for _, entry in pool do
			for _, values in { { 0.1, 0.7, 0.3 }, { 0.95, 0.05, 0.5 }, { 0.5 } } do
				local shelf = Pure.bottles(entry.Id, pool, count, sequence(values))
				expect(#shelf).toBe(count)
				assert(table.find(shelf, entry.Id), "the right bottle is missing")
				local seen = {}
				for _, id in shelf do
					assert(Items[id] and Items[id].Kind == "Medicine", id .. " is not a medicine")
					assert(not seen[id], "two of " .. id)
					seen[id] = true
					-- Never a look-alike: the others don't share the right one's icon (the shelf has enough).
					if id ~= entry.Id then
						assert(Items[id].Icon ~= entry.Icon, entry.Id .. "'s shelf has a look-alike: " .. id)
					end
					assert(string.match(Items[id].Bottle, "^#%x%x%x%x%x%x$"), id .. " has no bottle colour")
				end
			end
		end
	end)
	test("bottles: the same roll gives the same shelf; the right one moves about", function()
		local pool = {}
		for _, id in Items.Order do
			if Items[id].Kind == "Medicine" then
				table.insert(pool, { Id = id, Icon = Items[id].Icon })
			end
		end
		local a = Pure.bottles("EarDrops", pool, 4, sequence({ 0.3, 0.8, 0.1 }))
		local b = Pure.bottles("EarDrops", pool, 4, sequence({ 0.3, 0.8, 0.1 }))
		expect(a).toEqual(b)
		local places = {}
		for _, start in { 0, 0.2, 0.4, 0.6, 0.8, 0.99 } do
			places[table.find(Pure.bottles("EarDrops", pool, 4, sequence({ start })), "EarDrops") :: number] = true
		end
		local distinct = 0
		for _ in places do
			distinct += 1
		end
		assert(distinct >= 2, "the right bottle always stands in the same place")
	end)
	test("bottles: a small or junk shelf still gives the right one", function()
		local alike = { { Id = "A", Icon = "🧴" }, { Id = "B", Icon = "🧴" } }
		local shelf = Pure.bottles("A", alike, 4, sequence({ 0.5 }))
		table.sort(shelf)
		expect(shelf).toEqual({ "A", "B" }) -- a look-alike only when nothing else is left
		expect(Pure.bottles("Z", {}, 4, sequence({ 0.5 }))).toEqual({ "Z" })
		expect(Pure.bottles("Z", nil, 4, sequence({ 0.5 }))).toEqual({ "Z" })
	end)
	test('the reveal: "It\'s a cough!", with the right little word for every case', function()
		expect(Pure.reveal("Cough")).toBe("It's a cough!")
		expect(Pure.reveal("Earache")).toBe("It's an earache!")
		expect(Pure.reveal("Itchy rash")).toBe("It's an itchy rash!")
		expect(Pure.reveal("Sore muscles")).toBe("It's sore muscles!")
		expect(Pure.reveal("Chills")).toBe("It's chills!")
		expect(Pure.reveal("Broken arm")).toBe("It's a broken arm!")
		expect(Pure.reveal(nil)).toBe("It's something!")
		for _, id in Cases.ORDER do
			local text = Pure.reveal(Cases[id].Name)
			assert(string.find(text, string.lower(Cases[id].Name), 1, true), id .. ": " .. text)
			assert(not string.find(text, CURE), id .. ": " .. text)
		end
	end)
end)

T.describe("The Real Clinic: the cards fit a phone (Review Focus 5)", function()
	local PHONE = roblox.Vector2.new(568, 320)
	test("the exam card's 3 tools and the dispensing card's 4 bottles fit 568 x 320, every target >= 44 px", function()
		for _, n in { 3, 4 } do
			local rects, stage, card = Pure.pickLayout(PHONE, n)
			checkTargets(rects, stage, n, "568x320 n=" .. n)
			-- The stage sits inside the card, and the card inside the screen under the top bar.
			assert(stage.X <= card.X and stage.Y <= card.Y, "the stage is bigger than the card")
			assert(card.X <= 568 and card.Y <= 320 - Pure.CARD.Topbar, "the card is bigger than the screen")
		end
		-- The medicine choice (up to Config.Dispensary.Options) uses the same layout.
		assert(Config.Dispensary.Options <= Pure.CHOICES_MAX, "more medicines to choose from than a Pick shows")
		local options, optionStage = Pure.pickLayout(PHONE, Config.Dispensary.Options)
		checkTargets(options, optionStage, Config.Dispensary.Options, "568x320 options")
	end)
	test("1 to 4 targets fit every screen from a small phone to a big monitor, and never grow huge", function()
		local screens = {
			{ 568, 320 },
			{ 640, 360 },
			{ 667, 375 },
			{ 812, 375 },
			{ 320, 568 },
			{ 375, 667 },
			{ 1024, 768 },
			{ 1280, 720 },
			{ 1920, 1080 },
			{ 2560, 1440 },
		}
		for _, size in screens do
			for n = 1, Pure.CHOICES_MAX do
				local rects, stage = Pure.pickLayout({ X = size[1], Y = size[2] }, n)
				checkTargets(rects, stage, n, size[1] .. "x" .. size[2] .. " n=" .. n)
				for _, r in rects do
					assert(r.W <= Pure.CARD.PickMax, "a target past PickMax")
				end
			end
		end
	end)
	test("pickRects: junk and empty stages give nothing; more than CHOICES_MAX is capped", function()
		expect(Pure.pickRects(roblox.Vector2.new(300, 100), 0)).toEqual({})
		expect(Pure.pickRects(roblox.Vector2.new(0, 0), 3)).toEqual({})
		expect(Pure.pickRects(nil, 3)).toEqual({})
		expect(Pure.pickRects({ X = 300, Y = 100 }, 0 / 0)).toEqual({})
		expect(#Pure.pickRects({ X = 600, Y = 300 }, 9)).toBe(Pure.CHOICES_MAX)
		-- Wide and short (a phone's stage): one row. Tall and narrow: rows.
		local wide = Pure.pickRects({ X = 300, Y = 80 }, 4)
		expect(wide[1].Y).toBe(wide[4].Y)
		local tall = Pure.pickRects({ X = 120, Y = 300 }, 4)
		assert(tall[4].Y > tall[1].Y, "a tall stage stacks its targets")
	end)
	test("Pure.CARD matches the card build() makes and the modules it copies", function()
		local kit = source("src/client/UI/Kit.luau")
		local modal = source("src/client/UI/Modal.luau")
		local zones = source("src/shared/Logic/HudZones.luau")
		expect(tonumber(string.match(kit, "\nKit%.HEADER = (%d+)"))).toBe(Pure.CARD.Header)
		assert(
			string.find(kit, "gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets", 1, true),
			"Kit.screen's insets"
		)
		expect(tonumber(string.match(THEME, "\n\tPadPanel = (%d+)"))).toBe(Pure.CARD.Pad)
		expect(tonumber(string.match(THEME, "\n\tGap = (%d+), %-%- lists"))).toBe(Pure.CARD.Gap)
		expect(tonumber(string.match(THEME, "Step = table%.freeze%({ %d+, (%d+),"))).toBe(Pure.CARD.Gap)
		expect(tonumber(string.match(zones, "\nHudZones%.TOPBAR = (%d+)"))).toBe(Pure.CARD.Topbar)
		assert(
			string.find(modal, "local top = if hasHeader then Kit.HEADER - pad + Theme.Space.Gap else 0", 1, true),
			"Modal's body starts under the header as Pure.cardSize thinks"
		)
		for _, needle in
			{
				"MaxSize = Vector2.new(Pure.CARD.MaxX, Pure.CARD.MaxY)",
				"Scale = Vector2.new(Pure.CARD.ShareX, Pure.CARD.ShareY)",
				"AspectRatio = Pure.CARD.Aspect",
				"local STATUS = Pure.CARD.Status",
				"local HINT = Pure.CARD.Hint",
				"local GAP = Theme.Space.Step[2]",
				"Pure.pickRects(stage.AbsoluteSize, #buttons)",
			}
		do
			assert(string.find(MINI, needle, 1, true), "MiniGames: " .. needle)
		end
	end)
end)

T.describe("The Real Clinic: every game draws and rates with its own row", function()
	local mini = Config.MiniGame
	test("each Games row is read as its engine's (Pure.rowEngine agrees with Logic/MiniGame.ENGINE)", function()
		for _, id in MiniGame.GAME_IDS do
			local row = mini.Games[id]
			assert(type(row) == "table", "Config.MiniGame.Games has no " .. id)
			local engine = MiniGame.ENGINE[id]
			expect(Pure.rowEngine(id, row)).toBe(engine)
		end
		-- A row is known by its own fields (a Games row isn't named after its engine); a Pick row has none to widen.
		expect(Pure.rowEngine("Mystery", { Window = 0.3 })).toBe("Cool")
		expect(Pure.rowEngine("Mystery", { BandMin = 0.7 })).toBe("Pour")
		expect(Pure.rowEngine("Mystery", { Spots = 2 })).toBe("Patch")
		expect(Pure.rowEngine("Mystery", { Perfect = 6 })).toBe("Scrub")
		expect(Pure.rowEngine("Mystery", { Good = 1 })).toBeNil()
	end)
	test("Steady Hands widens every game's row, the way the game is drawn and rated", function()
		local eased = Pure.eased(mini, 1.3)
		local temp, plainTemp = eased.Games.Temp, mini.Games.Temp
		expect(near(temp.BandMax - temp.BandMin, (plainTemp.BandMax - plainTemp.BandMin) * 1.3)).toBeTruthy()
		expect(near(eased.Games.Light.Window, mini.Games.Light.Window * 1.3)).toBeTruthy()
		expect(near(eased.Games.Look.Seconds, mini.Games.Look.Seconds * 1.3)).toBeTruthy()
		expect(near(eased.Games.Bath.Seconds, mini.Games.Bath.Seconds * 1.3)).toBeTruthy()
		expect(eased.Games.Pick.Good).toBe(mini.Games.Pick.Good) -- nothing to widen in a Pick
		expect(eased.Games.Cast.Blows).toBe(mini.Games.Cast.Blows) -- only windows, never the goal
		-- A thermometer let go just past the plain band: Good plain, Perfect eased (rate reads the Games row).
		local fill = plainTemp.BandMax + 0.02
		expect(MiniGame.rate("Temp", fill, Config)).toBe("Good")
		expect(MiniGame.rate("Temp", fill, { MiniGame = eased })).toBe("Perfect")
		expect(mini.Games.Temp.BandMax).toBe(plainTemp.BandMax) -- the shipped table is never changed
	end)
	test("Expert Dispensing widens only the Dose band, by Config.Dispensary.ExpertBand", function()
		local band = Config.Dispensary.ExpertBand
		local wide = Pure.widened(mini, "Dose", band)
		local dose, plain = wide.Games.Dose, mini.Games.Dose
		expect(near(dose.BandMax - dose.BandMin, (plain.BandMax - plain.BandMin) * band)).toBeTruthy()
		expect(near((dose.BandMax + dose.BandMin) / 2, (plain.BandMax + plain.BandMin) / 2)).toBeTruthy()
		expect(dose.GoodSlack).toBe(plain.GoodSlack)
		expect(wide.Games.Temp).toBe(mini.Games.Temp) -- every other game as it was
		local fill = plain.BandMax + 0.03
		expect(MiniGame.rate("Dose", fill, Config)).toBe("Good")
		expect(MiniGame.rate("Dose", fill, { MiniGame = wide })).toBe("Perfect")
		-- Junk, 1 or a game with no band changes nothing.
		expect(Pure.widened(mini, "Dose", 1).Games.Dose).toBe(plain)
		expect(Pure.widened(mini, "Dose", 0 / 0).Games.Dose).toBe(plain)
		expect(Pure.widened(mini, "Pick", 2).Games.Pick).toBe(mini.Games.Pick)
		expect(Pure.widened(mini, "Light", 2).Games.Light).toBe(mini.Games.Light)
		-- Stacked on Steady Hands, still inside the cup.
		local both = Pure.widened(Pure.eased(mini, Pure.EASE_MAX), "Dose", band).Games.Dose
		assert(both.BandMin >= 0 and both.BandMax <= 1, "the band left the cup")
	end)
	test("Sweep: the bar is in the green zone exactly while a tap is good", function()
		for _, id in { "XRay", "Bandage", "Cast" } do
			local row = mini.Games[id]
			local zone = Pure.sweepZone(row.PulseSeconds, row.Window)
			for step = 0, 200 do
				local t = row.PulseSeconds * step / 200
				local inZone = math.abs(Pure.sweep(t, row.PulseSeconds) - 0.5) <= zone + 1e-9
				expect(inZone).toBe(Pure.goodBlow(t, row.PulseSeconds, row.Window))
			end
		end
		expect(Pure.sweep(-1, 1.2)).toBe(0)
		expect(Pure.sweep(9, 1.2)).toBe(1)
		expect(Pure.sweepZone(1, 5)).toBe(0.5)
	end)
end)

return nil
