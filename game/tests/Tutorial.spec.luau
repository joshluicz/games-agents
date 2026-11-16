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

	test("never moves once done", function()
		for _, event in { "Ack", "Arrived", "Made", "Treated", "Cured", "Purchased", "BookShown" } :: { any } do
			expect(Tutorial.advance(DONE, event, { Right = true, Cures = 9 })).toBe(DONE)
		end
	end)
end)

T.describe("Tutorial.spawnPlan", function()
	test("nobody during the welcome", function()
		expect(Tutorial.spawnPlan(WELCOME, true, false)).toBe("Wait")
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
