--!strict
-- Plans: what a patient needs and its progress (depth-update build plan §B7; the Real Clinic's plans, Task 5).
-- Logic/Recipe keeps the plan's bookkeeping; the Real Clinic removed crafting (medicines come from the dispensary).

local T = require("./expect")
local expect, test = T.expect, T.test

local Recipe = require("../src/shared/Logic/Recipe")
local Cases = require("../src/shared/Data/Cases")
local Items = require("../src/shared/Data/Items")
local Visit = require("../src/shared/Logic/Visit")

T.describe("Recipe", function()
	test("split and join round-trip", function()
		expect(Recipe.split("Ice,CoughSyrup")).toEqual({ "Ice", "CoughSyrup" })
		expect(Recipe.split("")).toEqual({})
		expect(Recipe.split(nil)).toEqual({})
		expect(Recipe.join({ "Cast", "PainRelief", "Bandage" })).toBe("Cast,PainRelief,Bandage")
		expect(Recipe.split(Recipe.join({ "Cocoa" }))).toEqual({ "Cocoa" })
	end)

	test("effective cuts the plan to the level's cap", function()
		local full = { "Cast", "PainRelief", "Bandage" } -- a broken leg
		expect(Recipe.effective(full, 1)).toEqual({ "Cast" })
		expect(Recipe.effective(full, 2)).toEqual({ "Cast", "PainRelief" })
		expect(Recipe.effective(full, 3)).toEqual(full)
		expect(Recipe.effective(full, 9)).toEqual(full)
		expect(Recipe.effective(full, 0)).toEqual({ "Cast" })
		expect(Recipe.effective(full, 0 / 0)).toEqual({ "Cast" })
		expect(Recipe.effective({ "Bubbles" }, 3)).toEqual({ "Bubbles" })
	end)

	test("encode and decode the done mask", function()
		expect(Recipe.encode({ true, false })).toBe("10")
		expect(Recipe.encode(Recipe.newDone({ "A", "B", "C" }))).toBe("000")
		expect(Recipe.decode("10", 2)).toEqual({ true, false })
		expect(Recipe.decode("1", 3)).toEqual({ true, false, false })
		expect(Recipe.decode(nil, 2)).toEqual({ false, false })
		expect(Recipe.decode("x1", 2)).toEqual({ false, true })
	end)

	test("missing lists what's still needed in plan order", function()
		local plan = { "Ice", "Bandage", "Ice" }
		expect(Recipe.missing(plan, { false, false, false })).toEqual(plan)
		expect(Recipe.missing(plan, { true, false, false })).toEqual({ "Bandage", "Ice" })
		expect(Recipe.missing(plan, { true, true, true })).toEqual({})
	end)

	test("match fills each missing step with one item in hand", function()
		local plan = { "Ice", "Bandage", "Ice" }
		local none = { false, false, false }
		expect(Recipe.match(plan, none, { "Ice" })).toEqual({ 1 })
		expect(Recipe.match(plan, none, { "Ice", "Ice" })).toEqual({ 1, 3 })
		expect(Recipe.match(plan, none, { "Bandage", "Ice", "Ice", "Ice" })).toEqual({ 1, 2, 3 })
		expect(Recipe.match(plan, { true, false, false }, { "Ice" })).toEqual({ 3 })
		expect(Recipe.match(plan, none, { "Cocoa", "Bubbles" })).toEqual({})
		expect(Recipe.match(plan, none, {})).toEqual({})
	end)

	test("apply marks indices done on a copy, and complete checks them all", function()
		local plan = { "Bubbles", "PainRelief" }
		local done = Recipe.newDone(plan)
		local after = Recipe.apply(done, { 2 })
		expect(done).toEqual({ false, false })
		expect(after).toEqual({ false, true })
		expect(Recipe.complete(plan, after)).toBe(false)
		expect(Recipe.complete(plan, Recipe.apply(after, { 1, 5 }))).toBe(true)
		expect(Recipe.complete({}, {})).toBe(true)
	end)

	test("makeable needs every item's station on the plot", function()
		local shelf = { Plaster = true, Ice = true, CoughSyrup = true }
		expect(Recipe.makeable({ "Ice", "CoughSyrup" }, shelf)).toBe(true)
		expect(Recipe.makeable({ "Ice", "Bandage" }, shelf)).toBe(false)
		expect(Recipe.makeable({}, shelf)).toBe(true)
	end)
end)

T.describe("Recipe in the Real Clinic", function()
	test("a medicine is just an item: it fills its own step, and only that", function()
		local plan = { "Lozenges", "CoughSyrup" } -- a sore throat
		local indices, used = Recipe.match(plan, { false, false }, { "CoughSyrup" })
		expect(indices).toEqual({ 2 })
		expect(used).toEqual({ "CoughSyrup" })
		indices, used = Recipe.match(plan, { false, false }, { "Cream", "Lozenges", "CoughSyrup" })
		expect(indices).toEqual({ 1, 2 })
		expect(used).toEqual({ "Lozenges", "CoughSyrup" })
		indices, used = Recipe.match(plan, { true, true }, { "CoughSyrup" })
		expect(indices).toEqual({})
		expect(used).toEqual({})
	end)

	test("no crafting: the medicine-pair helpers are gone", function()
		local R: any = Recipe
		expect(R.craft).toBeNil()
		expect(R.expand).toBeNil()
		for _, itemId in Items.Order do
			expect((Items :: any)[itemId].Medicine).toBeNil()
		end
	end)

	test("every case's plan is matched step by step by its own items, in order", function()
		for _, caseId in Cases.ORDER do
			local plan = Visit.plan(Cases[caseId], Recipe.MAX)
			expect(plan).toEqual(Recipe.effective(Cases[caseId].Plan, Recipe.MAX))
			local done = Recipe.newDone(plan)
			for index, itemId in plan do
				local indices, used = Recipe.match(plan, done, { itemId })
				expect(indices).toEqual({ index })
				expect(used).toEqual({ itemId })
				done = Recipe.apply(done, indices)
			end
			expect(Recipe.complete(plan, done)).toBe(true)
		end
	end)

	test("every plan item is something a station gives or the dispensary dispenses", function()
		for _, caseId in Cases.ORDER do
			for _, itemId in Cases[caseId].Plan do
				local item = (Items :: any)[itemId]
				expect(item ~= nil).toBe(true)
				if item.Kind == "Medicine" then
					expect(item.Station).toBe("Remedy")
				else
					expect(type(item.Game)).toBe("string")
				end
			end
		end
	end)
end)
