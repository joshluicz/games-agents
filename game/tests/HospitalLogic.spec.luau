--!strict
-- The hospital's rules (Logic/Hospital; Progression v2 build plan §B5/§B7; Real Clinic build plan, Task 4): floors and
-- departments by level, where a patient who stays rests, the ward pick, the urgent plan and its 🧊 pad, arrival and
-- rest times. Not "Hospital.spec": that name is the world's spec.

local T = require("./expect")
local expect, test = T.expect, T.test

local Hospital = require("../src/shared/Logic/Hospital")
local Visit = require("../src/shared/Logic/Visit")
local LevelsData = require("../src/shared/Data/Levels")
local Cases = require("../src/shared/Data/Cases")
local Items = require("../src/shared/Data/Items")
local Config = require("./config")

local LV1 = { Plaster = true, Ice = true, CoughSyrup = true, FeverMeds = true, EarDrops = true }
local ALL: { [string]: boolean } = {}
for _, itemId in Items.Order do
	ALL[itemId] = true
end

T.describe("Hospital", function()
	test("floors and departments by level (Data/Levels)", function()
		local floors = {}
		for level = 1, 5 do
			floors[level] = Hospital.floors(level, LevelsData)
		end
		expect(floors).toEqual({ 0, 1, 2, 3, 4 })
		expect(Hospital.departments(1, LevelsData)).toEqual({ "Reception", "Pharmacy" })
		expect(Hospital.departments(3, LevelsData)).toEqual({
			"Reception",
			"Pharmacy",
			"AE",
			"Wards",
			"Imaging",
			"Rest",
		})
		expect(Hospital.isOpen("AE", 1, LevelsData)).toBe(false)
		expect(Hospital.isOpen("AE", 2, LevelsData)).toBe(true)
		expect(Hospital.isOpen("Rest", 2, LevelsData)).toBe(false)
		expect(Hospital.isOpen("Rest", 3, LevelsData)).toBe(true)
		expect(Hospital.isOpen("Roof", 5, LevelsData)).toBe(true)
		expect(Hospital.floors(99, LevelsData)).toBe(4)
	end)

	test("route: a staying case's own ward once it's open; nothing (home) otherwise", function()
		expect(Hospital.route("Wards", nil, 1, LevelsData)).toBeNil()
		expect(Hospital.route("Wards", nil, 2, LevelsData)).toBe("Wards")
		expect(Hospital.route("Rest", nil, 2, LevelsData)).toBeNil()
		expect(Hospital.route("Rest", "AE", 3, LevelsData)).toBe("Rest")
		expect(Hospital.route(nil, nil, 5, LevelsData)).toBeNil()
		expect(Hospital.route("Hydro", nil, 5, LevelsData)).toBeNil() -- the hot tub is gone: never a destination
		expect(Hospital.route("Roof", nil, 5, LevelsData)).toBeNil()
	end)

	test("route agrees with Logic/Visit.stayWard for every case at every level", function()
		for _, caseId in Cases.ORDER do
			local case = Cases[caseId]
			for level = 1, 5 do
				expect(Hospital.route(case.Stay, nil, level, LevelsData)).toBe(Visit.stayWard(case, level))
			end
		end
	end)

	test("triageOptions: the Injury Ward or the Rest Ward from Lv 3, nil before", function()
		expect(Hospital.DESTINATIONS).toEqual({ "Wards", "Rest" })
		expect(Hospital.triageOptions(1, LevelsData)).toBeNil()
		expect(Hospital.triageOptions(2, LevelsData)).toBeNil()
		expect(Hospital.triageOptions(3, LevelsData)).toEqual({ "Wards", "Rest" })
		expect(Hospital.triageOptions(5, LevelsData)).toEqual({ "Wards", "Rest" })
	end)

	test("the urgent pad is an ice pack (a plaster for a plan that is only an ice pack)", function()
		expect(Hospital.PAD).toBe("Ice")
		expect(Hospital.pad("CoughSyrup")).toBe("Ice")
		expect(Hospital.pad("Plaster")).toBe("Ice")
		expect(Hospital.pad("Ice")).toBe("Plaster")
		expect(Items[Hospital.PAD].Station).toBe("Ice")
		expect(Items[Hospital.PAD_ICE].Station).toBe("Plaster")
	end)

	test("urgentRecipe: at least 2 steps, a one-step plan padded; nil when a step can't be made", function()
		expect(Hospital.MIN_ITEMS).toBe(Config.AE.MinItems)
		expect(Hospital.urgentRecipe({ "CoughSyrup" }, LV1, 2)).toEqual({ "CoughSyrup", "Ice" })
		expect(Hospital.urgentRecipe({ "Plaster" }, LV1, 1)).toEqual({ "Plaster", "Ice" })
		expect(Hospital.urgentRecipe({ "Ice" }, LV1, 2)).toEqual({ "Ice", "Plaster" })
		expect(Hospital.urgentRecipe({ "Ice", "Bandage" }, LV1, 2)).toBeNil() -- no bandages at Lv 1
		expect(Hospital.urgentRecipe({ "Ice", "Bandage" }, ALL, 2)).toEqual({ "Ice", "Bandage" })
		expect(Hospital.urgentRecipe({ "Cast", "PainRelief", "Bandage" }, ALL, 3)).toEqual({
			"Cast",
			"PainRelief",
			"Bandage",
		})
		expect(Hospital.urgentRecipe({ "Cast", "PainRelief", "Bandage" }, ALL, 2)).toEqual({ "Cast", "PainRelief" })
		expect(Hospital.urgentRecipe({ "CoughSyrup" }, { CoughSyrup = true }, 2)).toBeNil() -- the pad can't be made
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
