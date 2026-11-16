--!strict
-- The first-session tutorial's rules (Logic/Tutorial; docs/plan/2026-11-16-first-session-design.md §B).

local T = require("./expect")
local expect, test = T.expect, T.test

local Tutorial = require("../src/shared/Logic/Tutorial")
local Schema = require("../src/shared/Logic/Schema")

local WELCOME, PATIENT, MAKE, TREAT, REST, MORE, SHOP, BOOK, DONE =
	Tutorial.WELCOME,
	Tutorial.PATIENT,
	Tutorial.MAKE,
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
		expect(MAKE).toBe(3)
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
		expect(Tutorial.resume(MAKE)).toBe(PATIENT)
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
		expect(step).toBe(MAKE)
		step = Tutorial.advance(step, "Made", { Right = true })
		expect(step).toBe(TREAT)
		step = Tutorial.advance(step, "Treated")
		expect(step).toBe(REST)
		step = Tutorial.advance(step, "Cured")
		expect(step).toBe(MORE)
		step = Tutorial.advance(step, "Cured", { Cures = 1 })
		expect(step).toBe(MORE)
		step = Tutorial.advance(step, "Cured", { Cures = 2 })
		expect(step).toBe(SHOP)
		step = Tutorial.advance(step, "Purchased")
		expect(step).toBe(BOOK)
		step = Tutorial.advance(step, "BookShown")
		expect(step).toBe(DONE)
	end)

	test("the ack only moves past the welcome card", function()
		for step = PATIENT, DONE do
			expect(Tutorial.advance(step, "Ack")).toBe(step)
		end
	end)

	test("making the wrong item doesn't move on", function()
		expect(Tutorial.advance(MAKE, "Made", { Right = false })).toBe(MAKE)
		expect(Tutorial.advance(MAKE, "Made")).toBe(MAKE)
		expect(Tutorial.advance(PATIENT, "Made", { Right = true })).toBe(PATIENT) -- step 2 waits for its 2 s
	end)

	test("a treat skips ahead from steps 2 to 4 (a friend treated it, say)", function()
		expect(Tutorial.advance(PATIENT, "Treated")).toBe(REST)
		expect(Tutorial.advance(MAKE, "Treated")).toBe(REST)
		expect(Tutorial.advance(MORE, "Treated")).toBe(MORE)
		expect(Tutorial.advance(WELCOME, "Treated")).toBe(WELCOME)
	end)

	test("a cure skips ahead from steps 2 to 5", function()
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
		for _, event in { "Ack", "Arrived", "Made", "Treated", "Cured", "Purchased", "BookShown" } :: { any } do
			expect(Tutorial.advance(DONE, event, { Right = true, Cures = 9 })).toBe(DONE)
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

	test("the second (🩹) patient once, then anyone", function()
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

T.describe("Tutorial cards (look overhaul)", function()
	test("the 9 server steps show as 7 cards", function()
		expect(Tutorial.CARDS).toBe(7)
		expect(#Tutorial.CARD_NAMES).toBe(7)
		expect(Tutorial.CARD_NAMES).toEqual({ "Meet", "Make", "Give", "Pour", "Rest", "More", "Upgrade" })
		expect(Tutorial.card(WELCOME)).toBe(1)
		expect(Tutorial.card(PATIENT)).toBe(1)
		expect(Tutorial.card(MAKE)).toBe(2)
		expect(Tutorial.card(TREAT)).toBe(3)
		expect(Tutorial.card(TREAT, false)).toBe(3)
		expect(Tutorial.card(TREAT, true)).toBe(4) -- the mini-game is up
		expect(Tutorial.card(REST)).toBe(5)
		expect(Tutorial.card(MORE)).toBe(6)
		expect(Tutorial.card(SHOP)).toBe(7)
		expect(Tutorial.card(BOOK)).toBe(7)
	end)

	test("no card once done, or before the step is known; `treating` only matters in TREAT", function()
		expect(Tutorial.card(DONE)).toBeNil()
		expect(Tutorial.card(DONE, true)).toBeNil()
		expect(Tutorial.card(0)).toBeNil()
		expect(Tutorial.card(nil)).toBeNil()
		expect(Tutorial.card("3")).toBeNil()
		expect(Tutorial.card(MAKE, true)).toBe(2)
		expect(Tutorial.card(REST, true)).toBe(5)
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
		for _, step in { MAKE, TREAT, MORE } do
			expect(Tutorial.nudge(step)).toBe(true)
		end
		for _, step in { WELCOME, PATIENT, REST, SHOP, BOOK, DONE, 0 } do
			expect(Tutorial.nudge(step)).toBe(false)
		end
		expect(Tutorial.nudge(nil)).toBe(false)
	end)

	test("the first patient stands one second before the Make card", function()
		expect(Tutorial.ARRIVED_SECONDS).toBe(1)
	end)
end)

T.describe("Tutorial gift flag (look overhaul)", function()
	test("the top-up is due only on entering SHOP, and only once", function()
		expect(Tutorial.giftDue(SHOP, false)).toBe(true)
		expect(Tutorial.giftDue(SHOP, true)).toBe(false)
		for _, step in { WELCOME, PATIENT, MAKE, TREAT, REST, MORE, BOOK, DONE } do
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
