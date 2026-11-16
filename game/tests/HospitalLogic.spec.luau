--!strict
-- Hospital v2's rules (Logic/Hospital; Progression v2 build plan §B5/§B7). Not "Hospital.spec": that name is T6's
-- (the world's spec, build plan §A).

local T = require("./expect")
local expect, test = T.expect, T.test

local Hospital = require("../src/shared/Logic/Hospital")
local LevelsData = require("../src/shared/Data/Levels")
local Config = require("./config")

local STAND = { Potion = true, Plaster = true }
local ALL = { Potion = true, Plaster = true, Bubbles = true, Cocoa = true }

T.describe("Hospital", function()
	test("floors and departments by level", function()
		local floors = {}
		for level = 1, 5 do
			floors[level] = Hospital.floors(level, LevelsData)
		end
		expect(floors).toEqual({ 0, 1, 2, 3, 4 })
		expect(Hospital.departments(1, LevelsData)).toEqual({ "Reception" })
		expect(Hospital.departments(3, LevelsData)).toEqual({ "Reception", "AE", "Wards", "Hydro" })
		expect(Hospital.isOpen("AE", 1, LevelsData)).toBe(false)
		expect(Hospital.isOpen("AE", 2, LevelsData)).toBe(true)
		expect(Hospital.isOpen("Roof", 5, LevelsData)).toBe(true)
		expect(Hospital.floors(99, LevelsData)).toBe(4)
	end)

	test("route: a Bath-wing patient to Hydro once it's open, everyone else to the Wards", function()
		expect(Hospital.route("Bath", nil, 2, LevelsData)).toBe("Wards")
		expect(Hospital.route("Bath", nil, 3, LevelsData)).toBe("Hydro")
		expect(Hospital.route("Starter", nil, 5, LevelsData)).toBe("Wards")
		expect(Hospital.route("Bath", "AE", 4, LevelsData)).toBe("Hydro")
	end)

	test("triageOptions: Wards and Hydro from Lv 3, nil before", function()
		expect(Hospital.triageOptions(1, LevelsData)).toBeNil()
		expect(Hospital.triageOptions(2, LevelsData)).toBeNil()
		expect(Hospital.triageOptions(3, LevelsData)).toEqual({ "Wards", "Hydro" })
		expect(Hospital.triageOptions(5, LevelsData)).toEqual({ "Wards", "Hydro" })
	end)

	test("urgentRecipe: at least 2 items; a 1-item recipe gets the other Stand item; nil when not makeable", function()
		expect(Hospital.MIN_ITEMS).toBe(Config.AE.MinItems)
		expect(Hospital.urgentRecipe({ "Potion" }, STAND, 2)).toEqual({ "Potion", "Plaster" })
		expect(Hospital.urgentRecipe({ "Plaster" }, STAND, 2)).toEqual({ "Plaster", "Potion" })
		expect(Hospital.urgentRecipe({ "Potion" }, STAND, 1)).toEqual({ "Potion", "Plaster" })
		expect(Hospital.urgentRecipe({ "Bubbles", "Potion" }, STAND, 2)).toBeNil()
		expect(Hospital.urgentRecipe({ "Bubbles", "Potion" }, ALL, 2)).toEqual({ "Bubbles", "Potion" })
		expect(Hospital.urgentRecipe({ "Potion", "Cocoa", "Plaster" }, ALL, 3)).toEqual({ "Potion", "Cocoa", "Plaster" })
		expect(Hospital.urgentRecipe({ "Potion", "Cocoa", "Plaster" }, ALL, 2)).toEqual({ "Potion", "Cocoa" })
		expect(Hospital.urgentRecipe({}, ALL, 2)).toBeNil()
	end)

	test("arrival and recover multiply their factors, with floors", function()
		expect(Hospital.arrival(13, { 0.85, 0.92 })).toBeCloseTo(13 * 0.85 * 0.92)
		expect(Hospital.arrival(13, { 0 / 0, -1, 0 })).toBe(13) -- junk factors are ignored
		expect(Hospital.arrival(2, { 0.1 })).toBe(1)
		expect(Hospital.recover(4, { 0.5, 0.75 })).toBe(1.5)
		expect(Hospital.recover(4, { 0.01 })).toBe(0.5)
		expect(Hospital.recover(4, nil)).toBe(4)
	end)

	test("nightOwl: night patients keep coming for 30% of a night after morning", function()
		local window = Config.NightOwl * Config.NightSeconds -- 54 s
		expect(Hospital.nightOwl(1000, 1000, Config)).toBe(true)
		expect(Hospital.nightOwl(1000, 1000 + window, Config)).toBe(true)
		expect(Hospital.nightOwl(1000, 1000 + window + 1, Config)).toBe(false)
		expect(Hospital.nightOwl(1000, 999, Config)).toBe(false)
		expect(Hospital.nightOwl(1000, 1010, nil)).toBe(false)
	end)
end)
