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

T.describe("Recipe medicines (Progression v2)", function()
	local Items = require("../src/shared/Data/Items")

	test("match: exact items first, then a medicine fills both its ingredients' slots", function()
		local recipe = { "Cocoa", "Potion" } -- Chills
		local indices, used = Recipe.match(recipe, { false, false }, { "WarmTonic" }, Items)
		expect(indices).toEqual({ 1, 2 })
		expect(used).toEqual({ "WarmTonic" })
		-- an exact item covers its slot first; the medicine still fills the other one
		indices, used = Recipe.match(recipe, { false, false }, { "Potion", "WarmTonic" }, Items)
		expect(indices).toEqual({ 1, 2 })
		expect(used).toEqual({ "Potion", "WarmTonic" })
	end)

	test("a medicine is used only when at least one of its ingredients is missing", function()
		local indices, used = Recipe.match({ "Cocoa", "Potion" }, { true, true }, { "WarmTonic" }, Items)
		expect(indices).toEqual({})
		expect(used).toEqual({})
		indices, used = Recipe.match({ "Cocoa", "Potion" }, { true, false }, { "WarmTonic" }, Items)
		expect(indices).toEqual({ 2 })
		expect(used).toEqual({ "WarmTonic" })
		indices = Recipe.match({ "Bubbles", "Plaster" }, { false, false }, { "WarmTonic" }, Items)
		expect(indices).toEqual({})
	end)

	test("without medicines, a medicine is just an unknown item (v3 behaviour)", function()
		local indices, used = Recipe.match({ "Cocoa", "Potion" }, { false, false }, { "WarmTonic", "Potion" })
		expect(indices).toEqual({ 2 })
		expect(used).toEqual({ "Potion" })
	end)

	test("expand and craft", function()
		expect(Recipe.expand("WarmTonic", Items)).toEqual({ "Potion", "Cocoa" })
		expect(Recipe.expand("Potion", Items)).toEqual({ "Potion" })
		expect(Recipe.expand("Order", Items)).toEqual({ "Order" })
		expect(Recipe.craft({ "Potion", "Cocoa" }, Items, 1)).toBe("WarmTonic")
		expect(Recipe.craft({ "Cocoa", "Potion" }, Items, 1)).toBe("WarmTonic")
		expect(Recipe.craft({ "Plaster", "Bubbles" }, Items, 1)).toBe("SoapyPatch")
		expect(Recipe.craft({ "Potion", "Plaster" }, Items, 1)).toBeNil() -- Super Syrup is tier 2 (R2)
		expect(Recipe.craft({ "Potion", "Plaster" }, Items, 2)).toBe("SuperSyrup")
		expect(Recipe.craft({ "Potion" }, Items, 2)).toBeNil()
		expect(Recipe.craft({ "Potion", "Potion" }, Items, 2)).toBeNil()
		expect(Recipe.craft({}, Items, 2)).toBeNil()
	end)
end)
