--!strict
-- Recipes: what a patient needs and its progress (depth-update build plan §B7).

local T = require("./expect")
local expect, test = T.expect, T.test

local Recipe = require("../src/shared/Logic/Recipe")

T.describe("Recipe", function()
	test("split and join round-trip", function()
		expect(Recipe.split("Bubbles,Potion")).toEqual({ "Bubbles", "Potion" })
		expect(Recipe.split("")).toEqual({})
		expect(Recipe.split(nil)).toEqual({})
		expect(Recipe.join({ "Potion", "Plaster", "Potion" })).toBe("Potion,Plaster,Potion")
		expect(Recipe.split(Recipe.join({ "Cocoa" }))).toEqual({ "Cocoa" })
	end)

	test("effective cuts the recipe to the level's cap", function()
		local full = { "Potion", "Plaster", "Potion" }
		expect(Recipe.effective(full, 1)).toEqual({ "Potion" })
		expect(Recipe.effective(full, 2)).toEqual({ "Potion", "Plaster" })
		expect(Recipe.effective(full, 3)).toEqual(full)
		expect(Recipe.effective(full, 9)).toEqual(full)
		expect(Recipe.effective(full, 0)).toEqual({ "Potion" })
		expect(Recipe.effective(full, 0 / 0)).toEqual({ "Potion" })
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

	test("missing lists what's still needed in recipe order", function()
		local recipe = { "Potion", "Plaster", "Potion" }
		expect(Recipe.missing(recipe, { false, false, false })).toEqual(recipe)
		expect(Recipe.missing(recipe, { true, false, false })).toEqual({ "Plaster", "Potion" })
		expect(Recipe.missing(recipe, { true, true, true })).toEqual({})
	end)

	test("match fills each missing slot with one item in hand", function()
		local recipe = { "Potion", "Plaster", "Potion" }
		local none = { false, false, false }
		expect(Recipe.match(recipe, none, { "Potion" })).toEqual({ 1 })
		expect(Recipe.match(recipe, none, { "Potion", "Potion" })).toEqual({ 1, 3 })
		expect(Recipe.match(recipe, none, { "Plaster", "Potion", "Potion", "Potion" })).toEqual({ 1, 2, 3 })
		expect(Recipe.match(recipe, { true, false, false }, { "Potion" })).toEqual({ 3 })
		expect(Recipe.match(recipe, none, { "Cocoa", "Bubbles" })).toEqual({})
		expect(Recipe.match(recipe, none, {})).toEqual({})
	end)

	test("apply marks indices done on a copy, and complete checks them all", function()
		local recipe = { "Bubbles", "Potion" }
		local done = Recipe.newDone(recipe)
		local after = Recipe.apply(done, { 2 })
		expect(done).toEqual({ false, false })
		expect(after).toEqual({ false, true })
		expect(Recipe.complete(recipe, after)).toBe(false)
		expect(Recipe.complete(recipe, Recipe.apply(after, { 1, 5 }))).toBe(true)
		expect(Recipe.complete({}, {})).toBe(true)
	end)

	test("makeable needs every item's station on the plot", function()
		local stand = { Potion = true, Plaster = true }
		expect(Recipe.makeable({ "Potion", "Plaster" }, stand)).toBe(true)
		expect(Recipe.makeable({ "Bubbles", "Potion" }, stand)).toBe(false)
		expect(Recipe.makeable({}, stand)).toBe(true)
	end)
end)
