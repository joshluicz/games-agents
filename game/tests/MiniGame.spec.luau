--!strict
-- Mini-game ratings, the combo, tips and the server's plausibility check (depth-update build plan §B7), and the
-- Real Clinic's game ids on the five engines (build plan contract C5).
-- CFG repeats the engines' numbers so the old cases read on their own; the shipped Config (tests/config) is checked
-- at the end.

local T = require("./expect")
local expect, test = T.expect, T.test

local MiniGame = require("../src/shared/Logic/MiniGame")
local Items = require("../src/shared/Data/Items")
local Tools = require("../src/shared/Data/Tools")
local Config = require("./config")

local ENGINES = { Pour = true, Patch = true, Scrub = true, Cool = true, Pick = true }

local CFG = {
	MiniGame = {
		PerfectTip = 3,
		TipCapPerCure = 15,
		Combo = { { At = 3, Multiplier = 1.2 }, { At = 6, Multiplier = 1.5 }, { At = 10, Multiplier = 2 } },
		MinSeconds = { Pour = 1.2, Patch = 1, Scrub = 1.5, Cool = 1.5, Pick = 0.6 },
		SimpleMinSeconds = 0.25,
		Slack = 0.8,
		SessionSeconds = 12,
		PerGameSeconds = 6,
		Pour = { FillSeconds = 2.4, BandMin = 0.7, BandMax = 0.86, GoodSlack = 0.12 },
		Patch = { Spots = 3, Seconds = 4.5, Good = 2 },
		Scrub = { Seconds = 4, Perfect = 6, Good = 3 },
		Cool = { Blows = 3, Good = 2, PulseSeconds = 1.2, Window = 0.3 },
		Pick = { Good = 1 },
		Games = {
			Look = { Spots = 2, Seconds = 4, Good = 1, MinSeconds = 1 },
			Cast = { Blows = 4, Good = 3, PulseSeconds = 1, Window = 0.3, MinSeconds = 2 },
			Dose = { FillSeconds = 2.2, BandMin = 0.5, BandMax = 0.6, GoodSlack = 0.1, MinSeconds = 1.2 },
		},
	},
}

T.describe("MiniGame", function()
	test("one game per supply (Data/Items Game); a medicine is handed over with no game", function()
		expect(MiniGame.gameFor("Plaster", Items)).toBe("Plaster")
		expect(MiniGame.gameFor("Ice", Items)).toBe("Ice")
		expect(MiniGame.gameFor("Bubbles", Items)).toBe("Bath")
		expect(MiniGame.gameFor("Cocoa", Items)).toBe("Cocoa")
		expect(MiniGame.gameFor("CoughSyrup", Items)).toBeNil()
		expect(MiniGame.gameFor("Order", Items)).toBeNil()
		expect(MiniGame.gameFor("Potion", Items)).toBeNil() -- gone
		expect(MiniGame.gameFor(5, Items)).toBeNil()
		expect(MiniGame.gameFor("Plaster", nil)).toBeNil()
		expect((MiniGame :: any).GAMES).toBeNil() -- the item -> game table is Data/Items now
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

T.describe("MiniGame: the Real Clinic's games (contract C5)", function()
	local GAME_IDS = {
		"Listen",
		"Temp",
		"Light",
		"Look",
		"XRay",
		"Plaster",
		"Ice",
		"Bandage",
		"Cast",
		"Bath",
		"Cocoa",
		"Dose",
		"Pick",
	}

	test("every GameId has an ENGINE, and only they do", function()
		expect(MiniGame.GAME_IDS).toEqual(GAME_IDS)
		local count = 0
		for game, engine in MiniGame.ENGINE do
			count += 1
			expect(table.find(GAME_IDS, game) ~= nil).toBe(true)
			expect(ENGINES[engine]).toBe(true)
			expect(MiniGame.engineOf(game)).toBe(engine)
		end
		expect(count).toBe(#GAME_IDS)
		expect(MiniGame.ENGINE).toEqual({
			Listen = "Patch",
			Temp = "Pour",
			Light = "Cool",
			Look = "Patch",
			XRay = "Cool",
			Plaster = "Patch",
			Ice = "Pour",
			Bandage = "Cool",
			Cast = "Cool",
			Bath = "Scrub",
			Cocoa = "Cool",
			Dose = "Pour",
			Pick = "Pick",
		})
		-- an engine's own name still plays itself; anything else has none
		expect(MiniGame.engineOf("Pour")).toBe("Pour")
		expect(MiniGame.engineOf("Juggle")).toBeNil()
		expect(MiniGame.engineOf(5)).toBeNil()
	end)

	test("every supply's Game and every tool's Game is a GameId; medicines have none", function()
		for _, id in Items.Order do
			local item = Items[id]
			if item.Kind == "Supply" then
				expect(MiniGame.ENGINE[item.Game] ~= nil).toBe(true)
				expect(MiniGame.gameFor(id, Items)).toBe(item.Game)
			else
				expect(item.Game).toBeNil()
				expect(MiniGame.gameFor(id, Items)).toBeNil()
			end
		end
		for _, id in Tools.ORDER do
			expect(MiniGame.ENGINE[Tools[id].Game] ~= nil).toBe(true)
		end
	end)

	test("Pick: the score is wrong taps: 0 Perfect, 1 Good, 2 or more OK", function()
		expect(MiniGame.rate("Pick", 0, CFG)).toBe("Perfect")
		expect(MiniGame.rate("Pick", 1, CFG)).toBe("Good")
		expect(MiniGame.rate("Pick", 2, CFG)).toBe("OK")
		expect(MiniGame.rate("Pick", 9, CFG)).toBe("OK")
		expect(MiniGame.rate("Pick", 0 / 0, CFG)).toBe("OK")
		expect(MiniGame.rate("Pick", 0, {})).toBe("Perfect") -- no tuning: the defaults
		expect(MiniGame.rate("Pick", 1, {})).toBe("Good")
		expect(MiniGame.minSeconds({ "Pick" }, false, CFG)).toBeCloseTo(0.6)
		expect(MiniGame.minSeconds({ "Pick" }, false, {})).toBeCloseTo(1)
	end)

	test("rate uses the game's own tuning row on its engine's rule, else the engine's row", function()
		-- Look has its own row: 2 spots
		expect(MiniGame.rate("Look", 2, CFG)).toBe("Perfect")
		expect(MiniGame.rate("Look", 1, CFG)).toBe("Good")
		expect(MiniGame.rate("Look", 0, CFG)).toBe("OK")
		-- Listen has none here: the Patch row (3 spots)
		expect(MiniGame.rate("Listen", 2, CFG)).toBe("Good")
		expect(MiniGame.rate("Listen", 3, CFG)).toBe("Perfect")
		-- Cast: 4 beats
		expect(MiniGame.rate("Cast", 3, CFG)).toBe("Good")
		expect(MiniGame.rate("Cast", 4, CFG)).toBe("Perfect")
		expect(MiniGame.rate("Bandage", 3, CFG)).toBe("Perfect")
		-- Dose has its own band; Temp and Ice take Pour's
		expect(MiniGame.rate("Dose", 0.55, CFG)).toBe("Perfect")
		expect(MiniGame.rate("Dose", 0.78, CFG)).toBe("OK")
		expect(MiniGame.rate("Temp", 0.78, CFG)).toBe("Perfect")
		expect(MiniGame.rate("Ice", 0.6, CFG)).toBe("Good")
		expect(MiniGame.rate("Bath", 6, CFG)).toBe("Perfect")
		expect(MiniGame.rate("Cocoa", 2, CFG)).toBe("Good")
		expect(MiniGame.tuning("Look", CFG)).toBe(CFG.MiniGame.Games.Look)
		expect(MiniGame.tuning("Listen", CFG)).toBe(CFG.MiniGame.Patch)
		expect(MiniGame.tuning("Juggle", CFG)).toEqual({})
	end)

	test("minSeconds: a game's own, else its engine's; the timeout counts games", function()
		expect(MiniGame.minSeconds({ "Pick", "Look" }, false, CFG)).toBeCloseTo(1.6)
		expect(MiniGame.minSeconds({ "Pick", "Listen" }, false, CFG)).toBeCloseTo(1.6) -- Patch's 1
		expect(MiniGame.minSeconds({ "Cast" }, false, CFG)).toBeCloseTo(2)
		expect(MiniGame.minSeconds({ "Pick", "Dose" }, false, CFG)).toBeCloseTo(1.8)
		expect(MiniGame.minSeconds({ "Pick", "Dose" }, true, CFG)).toBeCloseTo(0.5)
		expect(MiniGame.timeout({ "Pick", "Dose" }, CFG)).toBe(24)
		-- a step that waits for a tap (each Pick, and `untimed` more) adds UntimedSeconds: nobody is timed out of a
		-- choice
		local slow = table.clone(CFG) :: any
		slow.MiniGame = table.clone(CFG.MiniGame)
		slow.MiniGame.UntimedSeconds = 20
		expect(MiniGame.timeout({ "Pick", "Dose" }, slow)).toBe(44)
		expect(MiniGame.timeout({ "Pick", "Dose" }, slow, 1)).toBe(64)
		expect(MiniGame.timeout({ "Pick", "Listen" }, slow)).toBe(44)
		expect(MiniGame.timeout({ "Plaster", "Ice" }, slow, 0 / 0)).toBe(24)
		-- an exam too fast to be real is all OK; a fair one stands
		local exam = { "Pick", "Listen" }
		expect(MiniGame.accept({ "Perfect", "Perfect" }, exam, 1, false, CFG)).toEqual({ "OK", "OK" })
		expect(MiniGame.accept({ "Perfect", "Good" }, exam, 1.4, false, CFG)).toEqual({ "Perfect", "Good" })
	end)

	test("the shipped Config: one tuning row per GameId, each fit for its engine, each beat 2-5 seconds", function()
		local mini = Config.MiniGame
		local need = {
			Pour = { "FillSeconds", "BandMin", "BandMax", "GoodSlack" },
			Patch = { "Spots", "Seconds", "Good" },
			Scrub = { "Seconds", "Perfect", "Good" },
			Cool = { "Blows", "Good", "PulseSeconds", "Window" },
			Pick = { "Good" },
		}
		local rows = 0
		for game, row in mini.Games do
			rows += 1
			local engine = MiniGame.ENGINE[game]
			if not engine then
				error("Config.MiniGame.Games." .. tostring(game) .. " is not a GameId")
			end
			for _, key in need[engine] do
				if type(row[key]) ~= "number" then
					error(game .. " has no " .. key)
				end
			end
			-- within the engine's minimum-time rule (never easier to fake than today's games)
			expect(row.MinSeconds >= mini.MinSeconds[engine]).toBe(true)
			expect(MiniGame.minSeconds({ game }, false, Config)).toBe(row.MinSeconds)
			local longest = if engine == "Pour"
				then row.FillSeconds
				elseif engine == "Cool" then row.Blows * row.PulseSeconds
				elseif engine == "Pick" then 0
				else row.Seconds
			expect(longest <= 5).toBe(true)
			expect(row.MinSeconds < math.max(longest, 1)).toBe(true) -- a real play is always slower than the minimum
			-- the best score is Perfect and the Good threshold is below it
			if engine == "Pour" then
				expect(MiniGame.rate(game, (row.BandMin + row.BandMax) / 2, Config)).toBe("Perfect")
				expect(row.BandMin - row.GoodSlack > 0 and row.BandMax + row.GoodSlack < 1).toBe(true)
			elseif engine == "Pick" then
				expect(MiniGame.rate(game, 0, Config)).toBe("Perfect")
			else
				local best = row.Spots or row.Blows or row.Perfect
				expect(MiniGame.rate(game, best, Config)).toBe("Perfect")
				expect(MiniGame.rate(game, row.Good, Config)).toBe(if row.Good >= best then "Perfect" else "Good")
				expect(row.Good < best).toBe(true)
			end
		end
		expect(rows).toBe(#GAME_IDS)
		for _, game in GAME_IDS do
			expect(mini.Games[game] ~= nil).toBe(true)
		end
		expect(mini.Pick.Good).toBe(1)
		expect(mini.MinSeconds.Pick).toBe(0.6)
		expect(mini.Games.Pick.MinSeconds).toBe(0.6)
		expect(Config.Visit.ExamsGlow).toBe(3)
	end)
end)

T.describe("MiniGame Progression v2", function()
	test("accept: an auto game is always Perfect, and the minimum time skips it", function()
		local games = { "Patch", "Pour" }
		-- only the Pour is played: 1.2 x 0.8 = 0.96 s is enough
		expect(MiniGame.accept({ "OK", "Good" }, games, 1, false, CFG, { true, false })).toEqual({ "Perfect", "Good" })
		-- too early for the played game: all OK, but the auto one is still Perfect
		expect(MiniGame.accept({ "OK", "Perfect" }, games, 0.5, false, CFG, { true, false })).toEqual({
			"Perfect",
			"OK",
		})
		-- junk report and Simple mode keep auto games Perfect
		expect(MiniGame.accept("junk", games, 9, false, CFG, { false, true })).toEqual({ "OK", "Perfect" })
		expect(MiniGame.accept({}, games, 9, true, CFG, { true, true })).toEqual({ "Perfect", "Perfect" })
		-- no auto: as before
		expect(MiniGame.accept({ "Good", "Good" }, games, 9, false, CFG)).toEqual({ "Good", "Good" })
		-- every game auto: no minimum time
		expect(MiniGame.accept({ "OK", "OK" }, games, 0, false, CFG, { true, true })).toEqual({ "Perfect", "Perfect" })
	end)
end)
