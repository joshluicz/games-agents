--!strict
-- The first-session tutorial's rules (Logic/Tutorial; docs/plan/2026-11-16-first-session-design.md §B; the Real Clinic
-- design §13: examine, then treat, then 3 more).

local T = require("./expect")
local expect, test = T.expect, T.test

local Tutorial = require("../src/shared/Logic/Tutorial")
local Schema = require("../src/shared/Logic/Schema")

local WELCOME, PATIENT, EXAMINE, TREAT, REST, MORE, SHOP, BOOK, DONE =
	Tutorial.WELCOME,
	Tutorial.PATIENT,
	Tutorial.EXAMINE,
	Tutorial.TREAT,
	Tutorial.REST,
	Tutorial.MORE,
	Tutorial.SHOP,
	Tutorial.BOOK,
	Tutorial.DONE

T.describe("Tutorial steps", function()
	test("are 1 to 9 in the design's order", function()
		expect(WELCOME).toBe(1)
		expect(PATIENT).toBe(2)
		expect(EXAMINE).toBe(3)
		expect(TREAT).toBe(4)
		expect(REST).toBe(5)
		expect(MORE).toBe(6)
		expect(SHOP).toBe(7)
		expect(BOOK).toBe(8)
		expect(DONE).toBe(9)
	end)

	test("match the save schema's welcome and done", function()
		expect(Schema.TUTORIAL_FIRST).toBe(WELCOME)
		expect(Schema.TUTORIAL_DONE).toBe(DONE)
	end)

	test("isStep takes only whole steps from 1 to 9", function()
		expect(Tutorial.isStep(1)).toBe(true)
		expect(Tutorial.isStep(9)).toBe(true)
		for _, bad in { 0, 10, 1.5, -3, 0 / 0, math.huge, "2", nil } :: { any } do
			expect(Tutorial.isStep(bad)).toBe(false)
		end
	end)

	test("active means started and not done", function()
		expect(Tutorial.active(WELCOME)).toBe(true)
		expect(Tutorial.active(BOOK)).toBe(true)
		expect(Tutorial.active(DONE)).toBe(false)
		expect(Tutorial.active(0)).toBe(false) -- the client's "not known yet"
		expect(Tutorial.active(nil)).toBe(false)
	end)

	test("isDone", function()
		expect(Tutorial.isDone(DONE)).toBe(true)
		expect(Tutorial.isDone(BOOK)).toBe(false)
		expect(Tutorial.isDone(nil)).toBe(false)
	end)

	test("patience never runs out in steps 1 to 6", function()
		for step = WELCOME, MORE do
			expect(Tutorial.calm(step)).toBe(true)
		end
		expect(Tutorial.calm(SHOP)).toBe(false)
		expect(Tutorial.calm(BOOK)).toBe(false)
		expect(Tutorial.calm(DONE)).toBe(false)
	end)

	test("guests (regulars, Today's Visitor) only once done", function()
		expect(Tutorial.guests(MORE)).toBe(false)
		expect(Tutorial.guests(BOOK)).toBe(false)
		expect(Tutorial.guests(DONE)).toBe(true)
	end)
end)

T.describe("Tutorial.migrate", function()
	test("keeps a saved step", function()
		expect(Tutorial.migrate(4, 0)).toBe(4)
		expect(Tutorial.migrate(DONE, 0)).toBe(DONE)
	end)

	test("marks a save without a step as done when it has a cure", function()
		expect(Tutorial.migrate(nil, 1)).toBe(DONE)
		expect(Tutorial.migrate(nil, 0)).toBe(WELCOME)
		expect(Tutorial.migrate("junk", 3)).toBe(DONE)
	end)
end)

T.describe("Tutorial.resume", function()
	test("sends steps that needed the live patient back to the patient step", function()
		expect(Tutorial.resume(EXAMINE)).toBe(PATIENT)
		expect(Tutorial.resume(TREAT)).toBe(PATIENT)
		expect(Tutorial.resume(REST)).toBe(PATIENT)
	end)

	test("keeps every other step", function()
		for _, step in { WELCOME, PATIENT, MORE, SHOP, BOOK, DONE } do
			expect(Tutorial.resume(step)).toBe(step)
		end
	end)
end)

T.describe("Tutorial.advance", function()
	test("walks the whole first session", function()
		local step = WELCOME
		step = Tutorial.advance(step, "Ack")
		expect(step).toBe(PATIENT)
		step = Tutorial.advance(step, "Arrived")
		expect(step).toBe(EXAMINE)
		step = Tutorial.advance(step, "Examined")
		expect(step).toBe(TREAT)
		step = Tutorial.advance(step, "Treated")
		expect(step).toBe(REST)
		step = Tutorial.advance(step, "Cured")
		expect(step).toBe(MORE)
		step = Tutorial.advance(step, "Cured", { Cures = 1 })
		expect(step).toBe(MORE)
		step = Tutorial.advance(step, "Cured", { Cures = 2 })
		expect(step).toBe(MORE)
		step = Tutorial.advance(step, "Cured", { Cures = 3 })
		expect(step).toBe(SHOP)
		step = Tutorial.advance(step, "Purchased")
		expect(step).toBe(BOOK)
		step = Tutorial.advance(step, "BookShown")
		expect(step).toBe(DONE)
	end)

	test("treat 3 more (design §13)", function()
		expect(Tutorial.MORE_CURES).toBe(3)
	end)

	test("the ack only moves past the welcome card", function()
		for step = PATIENT, DONE do
			expect(Tutorial.advance(step, "Ack")).toBe(step)
		end
	end)

	test("the arrival only moves the patient card on; the exam waits for it in step 2 too", function()
		expect(Tutorial.advance(PATIENT, "Arrived")).toBe(EXAMINE)
		for _, step in { WELCOME, EXAMINE, TREAT, REST, MORE, SHOP, BOOK } do
			expect(Tutorial.advance(step, "Arrived")).toBe(step)
		end
	end)

	test("an exam skips ahead from steps 2 and 3 (a friend or a nurse examined it, say); nowhere else", function()
		expect(Tutorial.advance(PATIENT, "Examined")).toBe(TREAT)
		expect(Tutorial.advance(EXAMINE, "Examined")).toBe(TREAT)
		for _, step in { WELCOME, TREAT, REST, MORE, SHOP, BOOK, DONE } do
			expect(Tutorial.advance(step, "Examined")).toBe(step)
		end
	end)

	test("fetching the item is no step of its own: an old Made event moves nothing", function()
		for step = WELCOME, DONE do
			expect(Tutorial.advance(step, "Made" :: any)).toBe(step)
		end
	end)

	test("a treat skips ahead from steps 2 to 4 (a friend treated it, say)", function()
		expect(Tutorial.advance(PATIENT, "Treated")).toBe(REST)
		expect(Tutorial.advance(EXAMINE, "Treated")).toBe(REST)
		expect(Tutorial.advance(TREAT, "Treated")).toBe(REST)
		expect(Tutorial.advance(MORE, "Treated")).toBe(MORE)
		expect(Tutorial.advance(WELCOME, "Treated")).toBe(WELCOME)
	end)

	test("a payout skips ahead from steps 2 to 5", function()
		expect(Tutorial.advance(TREAT, "Cured")).toBe(MORE)
		expect(Tutorial.advance(WELCOME, "Cured")).toBe(WELCOME)
		expect(Tutorial.advance(SHOP, "Cured", { Cures = 5 })).toBe(SHOP)
	end)

	test("only a purchase in the shop step counts", function()
		expect(Tutorial.advance(MORE, "Purchased")).toBe(MORE)
		expect(Tutorial.advance(SHOP, "Purchased")).toBe(BOOK)
	end)

	test("Skip ends any active step; it does nothing once done or before the step is known", function()
		for step = WELCOME, BOOK do
			expect(Tutorial.advance(step, "Skip")).toBe(DONE)
			expect(Tutorial.canSkip(step)).toBe(true)
		end
		expect(Tutorial.advance(DONE, "Skip")).toBe(DONE)
		expect(Tutorial.canSkip(DONE)).toBe(false)
		for _, bad in { 0, 10, 2.5, "3", false } :: { any } do
			expect(Tutorial.canSkip(bad)).toBe(false)
		end
		expect(Tutorial.canSkip(nil)).toBe(false)
	end)

	test("Replay is the one step back: only from DONE, to the first patient", function()
		expect(Tutorial.advance(DONE, "Replay")).toBe(PATIENT)
		for step = WELCOME, BOOK do
			expect(Tutorial.advance(step, "Replay")).toBe(step) -- mid-tutorial: nothing
		end
		expect(Tutorial.advance(0, "Replay")).toBe(0)
		expect(Tutorial.advance(12, "Replay")).toBe(12)
	end)

	test("canReplay: done AND owns a clinic", function()
		local rows = {
			{ DONE, true, true },
			{ DONE, false, false },
			{ BOOK, true, false },
			{ WELCOME, true, false },
			{ 0, true, false },
			{ 10, true, false },
			{ 9.5, true, false },
			{ "9", true, false },
		} :: { any }
		for _, row in rows do
			expect(Tutorial.canReplay(row[1], row[2])).toBe(row[3])
		end
		expect(Tutorial.canReplay(nil, true)).toBe(false)
		expect(Tutorial.canReplay(DONE, nil :: any)).toBe(false)
	end)

	test("never moves once done", function()
		for _, event in { "Ack", "Arrived", "Examined", "Treated", "Cured", "Purchased", "BookShown" } :: { any } do
			expect(Tutorial.advance(DONE, event, { Cures = 9 })).toBe(DONE)
		end
	end)
end)

T.describe("Tutorial.spawnPlan", function()
	test("the first patient already hops in during the welcome sweep (look overhaul)", function()
		expect(Tutorial.spawnPlan(WELCOME, true, false)).toBe("First")
		expect(Tutorial.spawnPlan(WELCOME, false, false)).toBe("Wait") -- one at a time
	end)

	test("only the first patient in steps 2 to 4", function()
		expect(Tutorial.spawnPlan(PATIENT, true, false)).toBe("First")
		expect(Tutorial.spawnPlan(PATIENT, false, false)).toBe("Wait")
		expect(Tutorial.spawnPlan(TREAT, false, false)).toBe("Wait")
	end)

	test("the second patient once, then anyone", function()
		expect(Tutorial.spawnPlan(REST, false, false)).toBe("Second")
		expect(Tutorial.spawnPlan(REST, false, true)).toBe("Wait")
		expect(Tutorial.spawnPlan(MORE, true, false)).toBe("Second") -- a rejoin in step 6
		expect(Tutorial.spawnPlan(MORE, false, true)).toBe("Any")
		expect(Tutorial.spawnPlan(SHOP, false, true)).toBe("Any")
		expect(Tutorial.spawnPlan(BOOK, false, false)).toBe("Any")
	end)

	test("the normal game once done", function()
		expect(Tutorial.spawnPlan(DONE, true, false)).toBe("Normal")
		expect(Tutorial.spawnPlan(nil, true, false)).toBe("Normal")
	end)
end)

T.describe("Tutorial.queueCap", function()
	test("one at a time in steps 1 to 6, normal after", function()
		expect(Tutorial.queueCap(PATIENT)).toBe(1)
		expect(Tutorial.queueCap(MORE)).toBe(1)
		expect(Tutorial.queueCap(SHOP)).toBeNil()
		expect(Tutorial.queueCap(DONE)).toBeNil()
	end)
end)

T.describe("Tutorial gift", function()
	test("cheapest skips maxed upgrades", function()
		expect(Tutorial.cheapest({ 50, 100, 75, 75 })).toBe(50)
		expect(Tutorial.cheapest({ 150, 100 })).toBe(100)
		expect(Tutorial.cheapest({})).toBeNil()
	end)

	test("tops up exactly to the cheapest price, only when short", function()
		expect(Tutorial.topUp(38, 50)).toBe(12)
		expect(Tutorial.topUp(0, 50)).toBe(50)
		expect(Tutorial.topUp(50, 50)).toBe(0)
		expect(Tutorial.topUp(80, 50)).toBe(0)
		expect(Tutorial.topUp(10, nil)).toBe(0)
	end)
end)

T.describe("Tutorial cards (the Real Clinic design §13)", function()
	test("the 9 server steps show as 7 cards", function()
		expect(Tutorial.CARDS).toBe(7)
		expect(#Tutorial.CARD_NAMES).toBe(7)
		expect(Tutorial.CARD_NAMES).toEqual({ "Welcome", "Examine", "Tool", "Fetch", "Treat", "Treated", "More" })
		expect(Tutorial.card(WELCOME)).toBe(1)
		expect(Tutorial.card(PATIENT)).toBe(1)
		expect(Tutorial.card(EXAMINE)).toBe(2)
		expect(Tutorial.card(EXAMINE, "Exam")).toBe(3) -- the exam card is up: pick the glowing tool
		expect(Tutorial.card(EXAMINE, true)).toBe(3)
		expect(Tutorial.card(TREAT)).toBe(4) -- get it from the shelf or the dispensary
		expect(Tutorial.card(TREAT, "Dispense")).toBe(4) -- still fetching
		expect(Tutorial.card(TREAT, nil, true)).toBe(5) -- carrying it: tap Treat
		expect(Tutorial.card(TREAT, "Treat")).toBe(5) -- its game is up on the patient
		expect(Tutorial.card(REST)).toBe(6)
		expect(Tutorial.card(MORE)).toBe(7)
		expect(Tutorial.card(SHOP)).toBe(7)
		expect(Tutorial.card(BOOK)).toBe(7)
	end)

	test(
		"no card once done, or before the step is known; the session and the carrying only matter in 3 and 4",
		function()
			expect(Tutorial.card(DONE)).toBeNil()
			expect(Tutorial.card(DONE, true)).toBeNil()
			expect(Tutorial.card(0)).toBeNil()
			expect(Tutorial.card(nil)).toBeNil()
			expect(Tutorial.card("3")).toBeNil()
			expect(Tutorial.card(EXAMINE, "Treat", true)).toBe(2)
			expect(Tutorial.card(PATIENT, "Exam", true)).toBe(1)
			expect(Tutorial.card(REST, true, true)).toBe(6)
			expect(Tutorial.card(MORE, "Exam", true)).toBe(7)
		end
	)

	test("the funnel: the card a step shows, then the Shop as its own 8th stage", function()
		expect(Tutorial.FUNNEL_SHOP).toBe(8)
		expect(#Tutorial.FUNNEL_NAMES).toBe(8)
		expect(Tutorial.FUNNEL_NAMES[8]).toBe("Upgrade")
		for card = 1, Tutorial.CARDS do
			expect(Tutorial.FUNNEL_NAMES[card]).toBe(Tutorial.CARD_NAMES[card])
		end
		expect(Tutorial.funnelStep(PATIENT)).toBe(1)
		expect(Tutorial.funnelStep(EXAMINE)).toBe(2)
		expect(Tutorial.funnelStep(TREAT)).toBe(4)
		expect(Tutorial.funnelStep(REST)).toBe(6)
		expect(Tutorial.funnelStep(MORE)).toBe(7)
		expect(Tutorial.funnelStep(SHOP)).toBe(8)
		expect(Tutorial.funnelStep(BOOK)).toBe(8)
		expect(Tutorial.funnelStep(DONE)).toBeNil()
		expect(Tutorial.funnelStep(nil)).toBeNil()
	end)

	test("cards never go backwards as the steps go forward", function()
		local last = 0
		for step = WELCOME, BOOK do
			local card = Tutorial.card(step) :: number
			expect(card >= last).toBe(true)
			expect(card >= 1 and card <= Tutorial.CARDS).toBe(true)
			last = card
		end
	end)

	test("the idle nudge only on the walking steps", function()
		for _, step in { EXAMINE, TREAT, MORE } do
			expect(Tutorial.nudge(step)).toBe(true)
		end
		for _, step in { WELCOME, PATIENT, REST, SHOP, BOOK, DONE, 0 } do
			expect(Tutorial.nudge(step)).toBe(false)
		end
		expect(Tutorial.nudge(nil)).toBe(false)
	end)

	test("the first patient sits one second in its bay before the Examine card", function()
		expect(Tutorial.ARRIVED_SECONDS).toBe(1)
	end)
end)

T.describe("Tutorial gift flag (look overhaul)", function()
	test("the top-up is due only on entering SHOP, and only once", function()
		expect(Tutorial.giftDue(SHOP, false)).toBe(true)
		expect(Tutorial.giftDue(SHOP, true)).toBe(false)
		for _, step in { WELCOME, PATIENT, EXAMINE, TREAT, REST, MORE, BOOK, DONE } do
			expect(Tutorial.giftDue(step, false)).toBe(false)
		end
		expect(Tutorial.giftDue(SHOP, nil :: any)).toBe(true) -- an unknown flag counts as not given
	end)

	test("a replay never gives a second gift: the flag is set by the time anyone is done", function()
		-- Schema derives TutorialGift = true for every save at or past SHOP, so a replayed run enters SHOP gifted.
		expect(Schema.TUTORIAL_SHOP).toBe(SHOP)
		local replayed = Schema.reconcile({ Version = 4, Cured = 9, Tutorial = DONE })
		expect(replayed.TutorialGift).toBe(true)
		local step = Tutorial.advance(replayed.Tutorial, "Replay")
		expect(step).toBe(PATIENT)
		expect(Tutorial.giftDue(SHOP, replayed.TutorialGift)).toBe(false)
	end)
end)

-- The slim strip over a mini-game card (UI/Tutorial's PURE block, loaded from the shipped source): it follows the
-- card's steps. Joshua's playtest 2026-11-17: the dispensary's strip still said "Tap the matching bottle!" while he
-- was measuring the dose.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local function clientCard(): any
	local path = if fs.isFile("src/client/UI/Tutorial.luau")
		then "src/client/UI/Tutorial.luau"
		else "game/src/client/UI/Tutorial.luau"
	local text = fs.readFile(path)
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to and to > from, "UI/Tutorial has no PURE block")
	local chunk = string.sub(text, from, to - 1) .. "\nreturn Pure\n"
	return luau.load(chunk, { debugName = "UI/Tutorial (Pure)" })(), text
end

T.describe("Tutorial strip over a mini-game (UI/Tutorial)", function()
	local Card, text = clientCard()

	test("the dispensary's strip follows the card: the bottle, then the dose", function()
		local games = { "Pick", "Dose" }
		expect(Card.gameAt(games, 1, false)).toBe("Pick")
		expect(Card.gameAt(games, 2, false)).toBe("Dose")
		expect(Card.gameAt(games, 3, false)).toBe(nil) -- past the last: the strip keeps what it shows
		expect(Card.words(4, { Game = Card.gameAt(games, 1, false) }).Title).toBe("FIND THE BOTTLE!")
		expect(Card.words(4, { Game = Card.gameAt(games, 1, false) }).Sub).toBe("Tap the same bottle!")
		expect(Card.words(4, { Game = Card.gameAt(games, 2, false) }).Title).toBe("MEASURE THE DOSE!")
		expect(Card.words(4, { Game = Card.gameAt(games, 2, false) }).Sub ~= "Tap the same bottle!").toBe(true)
	end)

	test("a two-supply treat moves on too; Simple mode is one Tap; junk names nothing", function()
		expect(Card.gameAt({ "Ice", "Bandage" }, 2, false)).toBe("Bandage")
		expect(Card.gameAt({ "Pick", "Dose" }, 2, true)).toBe("Tap")
		expect(Card.gameAt({ "Juggle" }, 1, false)).toBe(nil)
		expect(Card.gameAt(nil, 1, false)).toBe(nil)
		expect(Card.gameAt({ 5 }, 1, false)).toBe(nil)
	end)

	test("each rated game moves the strip on (MiniGameRated), from the session's own games", function()
		assert(string.find(text, "playGame = Pure.gameAt(playGames, playIndex, playSimple)", 1, true), "TreatStart")
		assert(string.find(text, "playIndex += 1", 1, true), "MiniGameRated moves it on")
	end)
end)
