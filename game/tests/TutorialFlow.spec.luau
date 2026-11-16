--!nocheck
-- The tutorial's flow (look build plan §D T8, §B1, §B9; memory-20261117-002/-003). Everything here is loaded straight
-- from the shipped source (the PURE blocks), so a spec can't pass on a stale copy:
--   · Server/Tutorial's remote rules (Skip, Replay with its cooldown, the one-time gift, the funnel);
--   · UI/Wayfinder.Pure (feet, the beam's ends and bends, the chevrons, the near-hide, the fade);
--   · Logic/Tutorial.card for every (step, treating), and UI/Tutorial.Pure's words per device (≤ 6 words, the Skip
--     line the one binding exception), the confirms, the nurse's lines and the finale's FREE "coming up" chip;
--   · UI/Celebrate's "Tutorial" kind;
--   · uirules on every T8 UI file, Sounds' Chirp, and the budgets the source can show (one Highlight, one loop).
-- Run from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local Logic = require("../src/shared/Logic/Tutorial")
local NextEvent = require("../src/shared/Logic/NextEvent")
local UiRules = require("./uirules")
local Config = require("./config")

local function source(path: string): string
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("can't find " .. path .. " (run from game/)")
end

-- The block between two markers, loaded on its own and returning `name`.
local function block(path: string, first: string, last: string, name: string, env: { [string]: any }?): any
	local text = source(path)
	local from = string.find(text, first, 1, true)
	local to = string.find(text, last, 1, true)
	assert(from and to and to > from, path .. ": no " .. first .. " block")
	local chunk = string.sub(text, from, to - 1) .. "\nreturn " .. name .. "\n"
	return luau.load(chunk, { debugName = path .. " (" .. name .. ")", environment = env or {} })()
end

local Server = block("src/server/Tutorial.luau", "-- PURE-BEGIN", "-- PURE-END", "Pure", { Logic = Logic })
local Way = block("src/client/UI/Wayfinder.luau", "-- PURE-BEGIN", "-- PURE-END", "Pure")
local Card = block("src/client/UI/Tutorial.luau", "-- PURE-BEGIN", "-- PURE-END", "Pure")
local Words = block("src/client/UI/Celebrate.luau", "-- BEGIN PURE", "-- END PURE", "Words")

local WELCOME, PATIENT, MAKE, TREAT, REST, MORE, SHOP, BOOK, DONE =
	Logic.WELCOME, Logic.PATIENT, Logic.MAKE, Logic.TREAT, Logic.REST, Logic.MORE, Logic.SHOP, Logic.BOOK, Logic.DONE
local COOLDOWN = Config.Tutorial.ReplayCooldown

local function words(text: string): number
	return Card.countWords(text)
end

------------------------------------------------------------------------------------------------------------------
-- The server's remote rules
------------------------------------------------------------------------------------------------------------------

T.describe("TutorialSkip (server rules)", function()
	test("only an active step can be skipped", function()
		for step = WELCOME, BOOK do
			local ok, message = Server.skip(step)
			expect(ok).toBe(true)
			expect(message).toBe("")
		end
		local ok, message = Server.skip(DONE)
		expect(ok).toBe(false)
		expect(message).toBe(Server.ALREADY_DONE)
	end)

	test("not loaded, or a junk step: refused", function()
		expect((Server.skip(nil))).toBe(false)
		for _, junk in { 0, 10, 2.5, -1, "3", {}, 0 / 0 } do
			expect((Server.skip(junk))).toBe(false)
		end
	end)
end)

T.describe("TutorialReplay (server rules)", function()
	test("only from DONE, with your own clinic", function()
		expect({ Server.replay(DONE, true, true, nil, 100, COOLDOWN) }).toEqual({ true, "" })
		expect({ Server.replay(DONE, false, true, nil, 100, COOLDOWN) }).toEqual({ false, Server.NO_CLINIC })
		for step = WELCOME, BOOK do
			expect({ Server.replay(step, true, true, nil, 100, COOLDOWN) }).toEqual({ false, Server.PLAYING })
		end
	end)

	test("not loaded, or not saving: refused first", function()
		expect({ Server.replay(nil, true, true, nil, 100, COOLDOWN) }).toEqual({ false, Server.LOADING })
		expect({ Server.replay(DONE, true, false, nil, 100, COOLDOWN) }).toEqual({ false, Server.NOT_SAVING })
	end)

	test("junk steps are never DONE", function()
		for _, junk in { 0, 10, 9.5, "9", {} } do
			expect((Server.replay(junk, true, true, nil, 100, COOLDOWN))).toBe(false)
		end
	end)

	test("the cooldown: Config.Tutorial.ReplayCooldown seconds between replays", function()
		expect(COOLDOWN).toBe(30)
		expect({ Server.replay(DONE, true, true, 100, 100 + COOLDOWN - 0.1, COOLDOWN) }).toEqual({
			false,
			Server.TOO_SOON,
		})
		expect({ Server.replay(DONE, true, true, 100, 100 + COOLDOWN, COOLDOWN) }).toEqual({ true, "" })
	end)

	test("every refusal is at most 6 words", function()
		for _, text in
			{
				Server.LOADING,
				Server.ALREADY_DONE,
				Server.NO_CLINIC,
				Server.PLAYING,
				Server.TOO_SOON,
				Server.NOT_SAVING,
				Server.SKIP_TOAST,
			}
		do
			expect(words(text) <= 6).toBeTruthy()
		end
	end)
end)

T.describe("The one-time gift (server rules)", function()
	test("due only on entering SHOP, never twice", function()
		expect({ Server.gift(SHOP, false) }).toEqual({ true, true })
		expect({ Server.gift(SHOP, true) }).toEqual({ false, true })
		for _, step in { WELCOME, PATIENT, MAKE, TREAT, REST, MORE, BOOK } do
			expect({ Server.gift(step, false) }).toEqual({ false, false })
		end
	end)

	test("a replay never gifts, and marks the gift given", function()
		expect({ Server.gift(SHOP, false, true) }).toEqual({ false, true })
		expect({ Server.gift(PATIENT, false, true) }).toEqual({ false, true })
	end)

	test("reaching DONE (a Skip, the admin's finish) marks the gift given", function()
		expect({ Server.gift(DONE, false) }).toEqual({ false, true })
	end)

	-- The save's TutorialGift through whole runs, the way Server/Tutorial.move uses Server.gift.
	local function run(path: { { number } }, gifted: boolean): (number, boolean)
		local gifts = 0
		for _, move in path do
			local due, after = Server.gift(move[1], gifted, move[2] == 1)
			if due then
				gifts += 1
			end
			gifted = after
		end
		return gifts, gifted
	end

	test("a first run gets one gift; Skip and then Replay through the shop gets none", function()
		local first = { { PATIENT }, { MAKE }, { TREAT }, { REST }, { MORE }, { SHOP }, { BOOK }, { DONE } }
		expect({ run(first, false) }).toEqual({ 1, true })
		local skipped = { { PATIENT }, { MAKE }, { DONE } }
		local gifts, gifted = run(skipped, false)
		expect(gifts).toBe(0)
		local replayed = { { PATIENT, 1 }, { MAKE }, { TREAT }, { REST }, { MORE }, { SHOP }, { BOOK }, { DONE } }
		expect((run(replayed, gifted))).toBe(0)
		-- Even a save that somehow lost the flag gets nothing on a replay.
		expect((run(replayed, false))).toBe(0)
	end)
end)

T.describe("The onboarding funnel (server rules)", function()
	test("each card once, as the step moves onto it", function()
		expect(Server.funnel(WELCOME, PATIENT)).toBe(1)
		expect(Server.funnel(PATIENT, MAKE)).toBe(2)
		expect(Server.funnel(MAKE, TREAT)).toBe(3)
		expect(Server.funnel(TREAT, REST)).toBe(5)
		expect(Server.funnel(REST, MORE)).toBe(6)
		expect(Server.funnel(MORE, SHOP)).toBe(7)
		expect(Server.funnel(SHOP, BOOK)).toBeNil() -- the same card
	end)

	test("never on a replay, a Skip or the end (a later step would mark skipped ones done)", function()
		expect(Server.funnel(DONE, PATIENT, true)).toBeNil()
		expect(Server.funnel(MAKE, TREAT, true)).toBeNil()
		for step = WELCOME, BOOK do
			expect(Server.funnel(step, DONE)).toBeNil()
		end
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- The world guide's numbers (UI/Wayfinder.Pure)
------------------------------------------------------------------------------------------------------------------

T.describe("Wayfinder.Pure", function()
	test("feetY: R15 from HipHeight, R6 from its 2-stud legs", function()
		expect(Way.feetY(5, 2, 2)).toBe(2)
		expect(Way.feetY(5, 2, 1.35)).toBeCloseTo(2.65, 6)
		expect(Way.feetY(3, 2, 0, true)).toBe(0)
		expect(Way.feetY(3, 2, 7, true)).toBe(0) -- R6 ignores HipHeight
		expect(Way.feetY(5, 2, -1)).toBe(4) -- a junk HipHeight is no legs
	end)

	test("beamStart: BeamLift above the feet (the hips)", function()
		expect(Way.beamStart(10, Config.Tutorial.BeamLift)).toBe(11.75)
	end)

	test("endAnchor: the footprint's closest point, out by the margin", function()
		local box = { X0 = -2, X1 = 2, Z0 = -1, Z1 = 1 }
		local x, z = Way.endAnchor(box, 10, 0, 0.3)
		expect(x).toBeCloseTo(2.3, 6)
		expect(z).toBeCloseTo(0, 6)
		x, z = Way.endAnchor(box, 0, -9, 0.3)
		expect(x).toBeCloseTo(0, 6)
		expect(z).toBeCloseTo(-1.3, 6)
		-- a corner: out along the diagonal
		x, z = Way.endAnchor(box, 5, 4, 0.3)
		expect(x > 2 and z > 1).toBeTruthy()
		expect(math.sqrt((x - 2) ^ 2 + (z - 1) ^ 2)).toBeCloseTo(0.3, 6)
		-- standing on it: out by the nearest edge
		x, z = Way.endAnchor(box, 1.8, 0, 0.3)
		expect(x).toBeCloseTo(2.3, 6)
		expect(z).toBeCloseTo(0, 6)
	end)

	test("needsBend: only a line through the box, not one past or along it", function()
		local box = { X0 = -1, X1 = 1, Z0 = -1, Z1 = 1 }
		expect(Way.needsBend(-5, 0, 5, 0, box)).toBe(true)
		expect(Way.needsBend(-5, 3, 5, 3, box)).toBe(false)
		expect(Way.needsBend(-5, 0, -2, 0, box)).toBe(false) -- stops short
		expect(Way.needsBend(-5, 1, 5, 1, box)).toBe(false) -- along the edge
	end)

	test("detour: none when clear; else round the box's corners, out by the margin", function()
		local box = { X0 = -2, X1 = 2, Z0 = -1, Z1 = 1 }
		expect(#Way.detour(-6, 5, 6, 5, box, 2.5)).toBe(0)
		local knees = Way.detour(-6, 0.2, 6, 0.2, box, 2.5)
		expect(#knees >= 1 and #knees <= 2).toBeTruthy()
		-- every leg of the detour clears the box
		local points = { { X = -6, Z = 0.2 } }
		for _, knee in knees do
			table.insert(points, knee)
		end
		table.insert(points, { X = 6, Z = 0.2 })
		for i = 2, #points do
			local a, b = points[i - 1], points[i]
			expect(Way.needsBend(a.X, a.Z, b.X, b.Z, box)).toBe(false)
		end
		-- the knees sit at the margin
		for _, knee in knees do
			expect(math.abs(knee.X) == 4.5 or math.abs(knee.Z) == 3.5).toBeTruthy()
		end
	end)

	test("detour: never more spans than BeamMaxSpans", function()
		local box = { X0 = -2, X1 = 2, Z0 = -1, Z1 = 1 }
		for _, from in { { -6, 0 }, { 0, -6 }, { 6, 0 }, { 0, 6 }, { -3, 0.5 } } do
			for _, to in { { 6, 0 }, { 0, 6 }, { -6, 0 }, { 0, -6 } } do
				expect(#Way.detour(from[1], from[2], to[1], to[2], box, 2.5) + 1 <= Config.Tutorial.BeamMaxSpans).toBeTruthy()
			end
		end
	end)

	test("simplify: a straight path has no knees; a corner keeps one; at most maxKnees, nearest first", function()
		local straight = {}
		for i = 0, 10 do
			table.insert(straight, { X = i * 2, Z = 0, Y = 0 })
		end
		expect(#Way.simplify(straight, 1, 3)).toBe(0)
		local corner = {}
		for i = 0, 5 do
			table.insert(corner, { X = i * 2, Z = 0, Y = 0 })
		end
		for i = 1, 5 do
			table.insert(corner, { X = 10, Z = i * 2, Y = 0 })
		end
		local knees = Way.simplify(corner, 1, 3)
		expect(#knees).toBe(1)
		expect(corner[knees[1]].X).toBe(10)
		expect(corner[knees[1]].Z).toBe(0)
		local zigzag = {}
		for i = 0, 12 do
			table.insert(zigzag, { X = i * 3, Z = (i % 2) * 4, Y = 0 })
		end
		local capped = Way.simplify(zigzag, 1, 3)
		expect(#capped).toBe(3)
		expect(capped[1] < capped[2] and capped[2] < capped[3]).toBeTruthy()
		-- a step in the floor is a knee too
		local stepUp =
			{ { X = 0, Z = 0, Y = 0 }, { X = 4, Z = 0, Y = 0 }, { X = 8, Z = 0, Y = 1.2 }, { X = 12, Z = 0, Y = 1.2 } }
		expect(#Way.simplify(stepUp, 1, 3, 0.5)).toBe(1)
	end)

	test("routeLength and along", function()
		local route = { { X = 0, Z = 0 }, { X = 3, Z = 4 }, { X = 3, Z = 10 } }
		expect(Way.routeLength(route)).toBeCloseTo(11, 6)
		local x, z, dx, dz = Way.along(route, 2.5)
		expect(x).toBeCloseTo(1.5, 6)
		expect(z).toBeCloseTo(2, 6)
		expect(dx).toBeCloseTo(0.6, 6)
		expect(dz).toBeCloseTo(0.8, 6)
		x, z, dx, dz = Way.along(route, 8)
		expect(x).toBeCloseTo(3, 6)
		expect(z).toBeCloseTo(7, 6)
		expect(dz).toBeCloseTo(1, 6)
		x, z = Way.along(route, 99) -- past the end: the end
		expect(z).toBeCloseTo(10, 6)
	end)

	test("chevronSpots: every gap, never within near of the target or under your feet, at most max", function()
		local tune = Config.Tutorial
		local spots = Way.chevronSpots(30, tune.FirstChevron, tune.ChevronGap, tune.MaxChevrons, tune.NearStuds)
		expect(#spots <= tune.MaxChevrons).toBeTruthy()
		for i, d in spots do
			expect(d >= tune.FirstChevron).toBeTruthy()
			expect(30 - d >= tune.NearStuds).toBeTruthy()
			if i > 1 then
				expect(d - spots[i - 1]).toBeCloseTo(tune.ChevronGap, 6)
			end
		end
		expect(spots).toEqual({ 6, 12, 18, 24 })
		-- a long route: only the max, the ones nearest you
		local long = Way.chevronSpots(100, tune.FirstChevron, tune.ChevronGap, tune.MaxChevrons, tune.NearStuds)
		expect(#long).toBe(tune.MaxChevrons)
		expect(long[1] < long[#long]).toBeTruthy()
		-- too short: none
		expect(#Way.chevronSpots(8, tune.FirstChevron, tune.ChevronGap, tune.MaxChevrons, tune.NearStuds)).toBe(0)
		expect(#Way.chevronSpots(30, 3, 0, 6, 6)).toBe(0)
	end)

	test("chevronSpots: they stay put on the floor as you walk toward the target", function()
		local tune = Config.Tutorial
		local before = Way.chevronSpots(40, tune.FirstChevron, tune.ChevronGap, tune.MaxChevrons, tune.NearStuds)
		local after = Way.chevronSpots(38, tune.FirstChevron, tune.ChevronGap, tune.MaxChevrons, tune.NearStuds)
		-- the same spots seen from 2 studs closer: each is 2 nearer you
		local same = 0
		for _, d in after do
			for _, e in before do
				if math.abs((e - 2) - d) < 1e-6 then
					same += 1
				end
			end
		end
		expect(same).toBe(#after)
	end)

	test("near: the beam and the chevrons hide within NearStuds", function()
		expect(Config.Tutorial.NearStuds).toBe(6)
		expect(Way.near(5.9, 6)).toBe(true)
		expect(Way.near(6, 6)).toBe(true)
		expect(Way.near(6.1, 6)).toBe(false)
	end)

	test("fade: in at your body, out into the glow, flat between", function()
		expect(Way.fade(1, 1)).toEqual({ { 0, 1 }, { 0.1, 0.15 }, { 0.9, 0.15 }, { 1, 0.45 } })
		expect(Way.fade(1, 3)).toEqual({ { 0, 1 }, { 0.1, 0.15 }, { 1, 0.15 } })
		expect(Way.fade(2, 3)).toEqual({ { 0, 0.15 }, { 1, 0.15 } })
		expect(Way.fade(3, 3)).toEqual({ { 0, 0.15 }, { 0.9, 0.15 }, { 1, 0.45 } })
		for count = 1, 4 do
			for index = 1, count do
				local keys = Way.fade(index, count)
				expect(keys[1][1]).toBe(0)
				expect(keys[#keys][1]).toBe(1)
			end
		end
	end)

	test("pinOffset: the pin drops lower when the camera is close", function()
		expect(Way.pinOffset(5, 10)).toBe(1.2)
		expect(Way.pinOffset(30, 10)).toBe(3)
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- The cards
------------------------------------------------------------------------------------------------------------------

T.describe("The cards (Logic/Tutorial.card)", function()
	test("every (step, treating)", function()
		local want = {
			[WELCOME] = { 1, 1 },
			[PATIENT] = { 1, 1 },
			[MAKE] = { 2, 2 },
			[TREAT] = { 3, 4 },
			[REST] = { 5, 5 },
			[MORE] = { 6, 6 },
			[SHOP] = { 7, 7 },
			[BOOK] = { 7, 7 },
		}
		for step = WELCOME, BOOK do
			expect(Logic.card(step, false)).toBe(want[step][1])
			expect(Logic.card(step, true)).toBe(want[step][2])
			expect(Logic.card(step)).toBe(want[step][1])
		end
		expect(Logic.card(DONE, false)).toBeNil()
		expect(Logic.card(DONE, true)).toBeNil()
		expect(Logic.card(0)).toBeNil()
		expect(Card.CARDS).toBe(Logic.CARDS)
	end)

	test("the tab and the pips", function()
		expect(Card.tab(2, 7)).toBe("TUTORIAL 2/7")
		expect(Card.pips(0, 2)).toBe("○○")
		expect(Card.pips(1, 2)).toBe("●○")
		expect(Card.pips(2, 2)).toBe("●●")
		expect(Card.pips(5, 2)).toBe("●●")
	end)

	test("the bar fills on success and never by time (card 6 by its pips)", function()
		expect(Card.segments(1, false)).toEqual({ 0, 0, 0, 0, 0, 0, 0 })
		expect(Card.segments(1, true)).toEqual({ 1, 0, 0, 0, 0, 0, 0 })
		expect(Card.segments(4, false)).toEqual({ 1, 1, 1, 0, 0, 0, 0 })
		expect(Card.segments(6, false, 1, 2)).toEqual({ 1, 1, 1, 1, 1, 0.5, 0 })
		expect(Card.segments(7, true)).toEqual({ 1, 1, 1, 1, 1, 1, 1 })
	end)

	test("the device from PreferredInput (or the enabled inputs)", function()
		expect(Card.device("Touch")).toBe("Touch")
		expect(Card.device("Gamepad")).toBe("Pad")
		expect(Card.device("MicroGamepad")).toBe("Pad")
		expect(Card.device("KeyboardAndMouse")).toBe("Keyboard")
		expect(Card.device(nil, true, false, false)).toBe("Touch")
		expect(Card.device(nil, false, false, true)).toBe("Pad")
		expect(Card.device(nil, true, true, true)).toBe("Keyboard")
	end)

	-- Every situation a card can meet, per device.
	local function situations(): { any }
		local out = {}
		for _, deviceName in { "Keyboard", "Touch", "Pad" } do
			for _, waiting in { false, true } do
				for _, carrying in { false, true } do
					for cures = 0, 2 do
						for _, game in { "Pour", "Patch", "Scrub", "Cool", "Tap" } do
							for _, item in { "Potion", "Plaster", "Warm Tonic" } do
								table.insert(out, {
									Device = deviceName,
									Item = item,
									Need = "🧪",
									Waiting = waiting,
									Carrying = carrying,
									Cures = cures,
									Total = Logic.MORE_CURES,
									Cured = cures > 0,
									Game = game,
								})
							end
						end
					end
				end
			end
		end
		return out
	end

	test("the card words: a title of 4 words or fewer, a subtitle (with its key) of 6 or fewer", function()
		for _, s in situations() do
			for cardNumber = 1, Logic.CARDS do
				local w = Card.words(cardNumber, s)
				expect(w.Title ~= "").toBeTruthy()
				expect(w.Sub ~= "").toBeTruthy()
				local titleWords = words(w.Title)
				local subWords = words(w.Sub) + (if w.Key then 1 else 0)
				if titleWords > 4 or subWords > 6 then
					error(string.format("card %d (%s): %q / %q", cardNumber, s.Device, w.Title, w.Sub))
				end
			end
		end
	end)

	test("the plan's words (§B9) per device", function()
		local function w(cardNumber, deviceName, extra)
			local s = { Device = deviceName, Item = "Potion", Total = 2, Cures = 0 }
			for k, v in extra or {} do
				s[k] = v
			end
			return Card.words(cardNumber, s)
		end
		expect(w(1, "Keyboard").Title).toBe("A SICK CREATURE!")
		expect(w(1, "Keyboard").Sub).toBe("🤧 Look at its bubble")
		expect(w(1, "Keyboard", { Waiting = true, Need = "🧪" }).Sub).toBe("It needs a 🧪!")
		expect(w(2, "Keyboard")).toEqual({ Title = "MAKE A POTION", Sub = "Follow the arrows · hold", Key = "Prompt" })
		expect(w(2, "Touch").Sub).toBe("Follow the arrows · hold 👆 Make")
		expect(w(2, "Pad").Key).toBe("Prompt")
		expect(w(3, "Keyboard").Title).toBe("GIVE IT THE POTION")
		expect(w(3, "Touch").Sub).toBe("Go to the Counter · tap Treat")
		expect(w(4, "Keyboard", { Game = "Pour" })).toEqual({ Title = "POUR IT IN!", Sub = "Hold… let go on ⭐" })
		expect(w(5, "Keyboard").Title).toBe("RESTING…")
		expect(w(5, "Keyboard", { Cured = true }).Title).toBe("CURED! 🎉")
		expect(w(6, "Keyboard").Title).toBe("CURE 2 MORE ○○")
		expect(w(6, "Keyboard", { Cures = 1 }).Title).toBe("CURE 2 MORE ●○")
		expect(w(6, "Keyboard").Sub).toBe("🤕 New patient! Check its bubble")
		expect(w(6, "Keyboard", { Waiting = true, Need = "🩹" }).Sub).toBe("It needs a 🩹!")
		expect(w(6, "Keyboard", { Waiting = true, Carrying = true }).Key).toBe("Prompt")
		expect(w(7, "Touch").Sub).toBe("Tap 🛒 · buy a ⚡")
		expect(w(7, "Keyboard").Sub).toBe("Click 🛒 · buy a ⚡")
		expect(w(7, "Pad")).toEqual({ Title = "UPGRADE YOUR CLINIC", Sub = "on 🛒", Key = "Confirm", KeyFirst = true })
	end)

	test("the word 'Spend' never appears; the pointer's label points at an upgrade (in-game cash)", function()
		local text = source("src/client/UI/Tutorial.luau")
		expect(string.find(text, '"[^"\n]*[Ss]pend[^"\n]*"')).toBeNil()
		expect(Card.BUY_LABEL).toBe("Buy this! ⚡")
	end)
end)

T.describe("Skip and Replay (the confirms; memory-20261117-002)", function()
	test("Skip: the binding words, and 'Keep going' as the safe default", function()
		expect(Card.SKIP).toEqual({
			Title = "⏭️ Skip the tutorial?",
			Line = "You can replay it any time from ⚙️",
			Yes = "⏭️ Skip",
			No = "Keep going",
		})
		-- the one line past 6 words (look build plan §F11), on purpose
		expect(words(Card.SKIP.Line)).toBe(7)
	end)

	test("Replay: its words, 'Not now' as the safe default", function()
		expect(Card.REPLAY).toEqual({
			Title = "🔁 Replay the tutorial?",
			Line = "Your waiting patients go home",
			Yes = "🔁 Replay",
			No = "Not now",
		})
		for _, text in { Card.REPLAY.Title, Card.REPLAY.Line, Card.SKIP.Title, Card.SKIP_CHIP } do
			expect(words(text) <= 6).toBeTruthy()
		end
	end)

	test("both go through Hud.confirm and the remotes (no hand-built confirm)", function()
		local text = source("src/client/UI/Tutorial.luau")
		expect(string.find(text, "Hud.confirm(ctx", 1, true) ~= nil).toBeTruthy()
		expect(string.find(text, "ctx.Remotes.TutorialSkip", 1, true) ~= nil).toBeTruthy()
		expect(string.find(text, "ctx.Remotes.TutorialReplay", 1, true) ~= nil).toBeTruthy()
		expect(string.find(text, 'ctx.on("SkipTutorial"', 1, true) ~= nil).toBeTruthy()
		expect(string.find(text, 'ctx.on("ReplayTutorial"', 1, true) ~= nil).toBeTruthy()
	end)
end)

T.describe("The guide nurse and the finale", function()
	test("the nurse's lines are 2-4 words", function()
		for name, line in Card.SAY do
			local n = words(line)
			if n < 2 or n > 4 then
				error(name .. ": " .. line)
			end
		end
	end)

	test("the finale: YOU DID IT! and short chips", function()
		expect(Card.FINALE.Title).toBe("YOU DID IT!")
		expect(words(Card.FINALE.Title) <= 3).toBeTruthy()
		for _, chip in Card.FINALE.Chips do
			expect(words(chip) <= 6).toBeTruthy()
		end
	end)

	test("'coming up' candidates are free events only, and the pick is the soonest within 6 h", function()
		local now = 1000
		local list = Card.candidates(now, now + 720, false, now + 200, 90)
		expect(#list).toBe(3)
		for _, candidate in list do
			expect(candidate.Paid).toBeNil()
		end
		local picked = NextEvent.pick(now, list)
		expect(picked.Id).toBe("Gift")
		expect(NextEvent.label(picked.At - now)).toBe("in 1m")
		-- at night there's no "night" to wait for; Golden Hour is next
		picked = NextEvent.pick(now, Card.candidates(now, now + 720, true, now + 200, nil))
		expect(picked.Id).toBe("Golden")
		expect(NextEvent.label(picked.At - now)).toBe("in 12m")
		-- a paid thing slipped into the list is never picked (red line 3)
		table.insert(list, 1, { Id = "Sale", Icon = "💸", Name = "Sale", At = now + 5, Paid = true })
		expect(NextEvent.pick(now, list).Id).toBe("Gift")
		-- nothing coming within 6 h: no chip
		expect(NextEvent.pick(now, Card.candidates(now, now + 7 * 3600, true, nil, nil))).toBeNil()
	end)
end)

T.describe("Celebrate: the Tutorial kind", function()
	local data = { Nurses = {}, Rarities = {}, Levels = {}, Decor = {}, Rooms = {}, NextLabel = NextEvent.label }
	local function finale(next: any, now: number?): any
		return Words.of({
			Kind = "Tutorial",
			Title = Card.FINALE.Title,
			Icon = Card.FINALE.Icon,
			Chips = Card.FINALE.Chips,
			Next = next,
		}, data, now)
	end

	test("the guide nurse's face, the chips and one COMING UP chip in minutes", function()
		local w = finale({ Id = "Golden", Icon = "🌟", Name = "Golden Hour", At = 1000 + 12 * 60 }, 1000)
		expect(w.Title).toBe("YOU DID IT!")
		expect(w.Portrait).toBe("Guide")
		expect(w.Sound).toBe("Fanfare")
		expect(w.Chips).toEqual(Card.FINALE.Chips)
		expect(w.Next).toBe("🌟 Golden Hour in 12m")
		expect(words(w.Next) <= 6).toBeTruthy()
		expect(Words.DURING_TUTORIAL.Tutorial).toBe(true)
	end)

	test("no chip for an event already started, junk, or no clock", function()
		expect(finale({ Id = "Golden", Icon = "🌟", Name = "Golden Hour", At = 900 }, 1000).Next).toBeNil()
		expect(finale({ Id = "Golden", Icon = "🌟", Name = "Golden Hour", At = 2000 }, nil).Next).toBeNil()
		expect(finale({ Id = "Golden", At = 2000 }, 1000).Next).toBeNil()
		expect(finale(nil, 1000).Next).toBeNil()
		expect(finale("soon", 1000).Next).toBeNil()
	end)

	test("other kinds still wait for the tutorial to end", function()
		for kind in Words.KINDS do
			if kind ~= "Tutorial" then
				expect(Words.DURING_TUTORIAL[kind]).toBeNil()
			end
		end
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- The source: UI rules, the Chirp, and the budgets
------------------------------------------------------------------------------------------------------------------

T.describe("T8's files follow the rules", function()
	test("uirules: every T8 UI file", function()
		local found = UiRules.check({
			"src/client/UI/Tutorial.luau",
			"src/client/UI/Guide.luau",
			"src/client/UI/Celebrate.luau",
			"src/client/UI/Wayfinder.luau",
		})
		if #found > 0 then
			error(UiRules.format(found))
		end
	end)

	test("Sounds has the Chirp cue (and lists it)", function()
		local text = source("src/client/Feel/Sounds.luau")
		expect(string.find(text, "\n\tChirp = {", 1, true) ~= nil).toBeTruthy()
		expect(string.find(text, 'Sounds.LOOK_CUES = table.freeze({\n\t"Chirp",', 1, true) ~= nil).toBeTruthy()
	end)

	test("one Highlight in the whole tutorial, made in one place (Wayfinder) and deleted by destroy()", function()
		local count = 0
		for _, path in
			{
				"src/client/UI/Tutorial.luau",
				"src/client/UI/Guide.luau",
				"src/client/UI/Celebrate.luau",
				"src/client/UI/Wayfinder.luau",
			}
		do
			for _ in string.gmatch(source(path), 'Instance%.new%("Highlight"%)') do
				count += 1
			end
		end
		expect(count).toBe(1)
		local way = source("src/client/UI/Wayfinder.luau")
		expect(string.find(way, "local existing = glow\n\tif existing and existing.Parent then", 1, true) ~= nil).toBeTruthy()
	end)

	test("the beam's loop: one RenderStepped, connected only while something shows", function()
		local way = source("src/client/UI/Wayfinder.luau")
		local _, connects = string.gsub(way, "RenderStepped:Connect", "")
		expect(connects).toBe(1)
		expect(
			string.find(
				way,
				"function Wayfinder.hide()\n\tspec = nil\n\troute = nil\n\tlastAim = nil\n\tdisconnectLoop()",
				1,
				true
			) ~= nil
		).toBeTruthy()
		local guide = source("src/client/UI/Guide.luau")
		expect(string.find(guide, "Wayfinder.destroy()", 1, true) ~= nil).toBeTruthy()
	end)

	test("original only: no red cross and no toy brand in T8's files", function()
		for _, path in
			{
				"src/client/UI/Tutorial.luau",
				"src/client/UI/Guide.luau",
				"src/client/UI/Celebrate.luau",
				"src/client/UI/Wayfinder.luau",
				"src/server/Tutorial.luau",
			}
		do
			local text = source(path)
			expect(string.find(text, "LEGO", 1, true)).toBeNil()
			expect(string.find(text, "crossSign", 1, true)).toBeNil()
		end
	end)
end)
