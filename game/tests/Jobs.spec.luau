--!strict
-- Nurse jobs, departments and team bonuses (Logic/Jobs; Progression v2 build plan §B5/§B7).

local T = require("./expect")
local expect, test = T.expect, T.test

local Jobs = require("../src/shared/Logic/Jobs")
local JobsData = require("../src/shared/Data/Jobs")
local Departments = require("../src/shared/Data/Departments")
local Wings = require("../src/shared/Data/Wings")

T.describe("Jobs", function()
	test("open: a known job at or above its level; Rest and junk never", function()
		expect(Jobs.open("Maker", 1, JobsData)).toBe(true)
		expect(Jobs.open("Porter", 1, JobsData)).toBe(false)
		expect(Jobs.open("Porter", 2, JobsData)).toBe(true)
		expect(Jobs.open("Medic", 5, JobsData)).toBe(true)
		expect(Jobs.open("Rest", 5, JobsData)).toBe(false)
		expect(Jobs.open("Order", 5, JobsData)).toBe(false)
		expect(Jobs.open(nil, 5, JobsData)).toBe(false)
	end)

	test('effective: "" is the role; a closed job is worked as the role; Rest stays Rest', function()
		expect(Jobs.effective("", "Healer", 1, JobsData)).toBe("Healer")
		expect(Jobs.effective("Receptionist", "Healer", 1, JobsData)).toBe("Receptionist")
		expect(Jobs.effective("Porter", "Maker", 1, JobsData)).toBe("Maker") -- after a rebirth, until Lv 2
		expect(Jobs.effective("Porter", "Maker", 2, JobsData)).toBe("Porter")
		expect(Jobs.effective("Rest", "Maker", 5, JobsData)).toBe("Rest")
		expect(Jobs.effective("SomeFutureJob", "Cheerer", 5, JobsData)).toBe("Cheerer")
		expect(Jobs.effective(7, "Cheerer", 5, JobsData)).toBe("Cheerer")
	end)

	test("department: a job's own; a Maker's is its station's", function()
		expect(Jobs.department("Healer", nil, JobsData)).toBe("Reception")
		expect(Jobs.department("Porter", nil, JobsData)).toBe("Wards")
		expect(Jobs.department("Medic", nil, JobsData)).toBe("AE")
		expect(Jobs.department("Maker", "Bath", JobsData, Departments.Stations)).toBe("Hydro")
		expect(Jobs.department("Maker", "Cocoa", JobsData)).toBe("Pharmacy")
		expect(Jobs.department("Maker", "Pharmacy", JobsData)).toBe("Pharmacy")
		expect(Jobs.department("Maker", "Remedy", JobsData)).toBe("Reception")
		expect(Jobs.department("Maker", nil, JobsData)).toBe("Reception")
		expect(Jobs.department("Nope", nil, JobsData)).toBe("Reception")
	end)

	test("Logic/Jobs' maps are Data/Departments' maps", function()
		expect(Jobs.STATIONS).toEqual(Departments.Stations)
		expect(Jobs.WINGS).toEqual(Departments.Wings)
		for _, wingId in Wings.Order do
			expect(Jobs.WINGS[wingId] ~= nil).toBe(true)
		end
	end)

	test("patientDepartment: urgent patients are A&E's, else the wing's", function()
		expect(Jobs.patientDepartment("Starter", nil)).toBe("Reception")
		expect(Jobs.patientDepartment("Bath", nil)).toBe("Hydro")
		expect(Jobs.patientDepartment("Winter", nil)).toBe("Pharmacy")
		expect(Jobs.patientDepartment("Night", nil)).toBe("Wards")
		expect(Jobs.patientDepartment("Sky", nil)).toBe("AE")
		expect(Jobs.patientDepartment("Starter", "AE")).toBe("AE")
		expect(Jobs.patientDepartment("Bath", "VIP")).toBe("AE")
		expect(Jobs.patientDepartment("Unknown", nil)).toBe("Reception")
	end)

	test("teams: matching specialties per department; Any counts for every one", function()
		local counts = Jobs.teams({ "Reception", "Reception", "Hydro", "Any", "Nope" }, Departments)
		expect(counts).toEqual({ Reception = 3, AE = 1, Wards = 1, Hydro = 2, Pharmacy = 1, Roof = 1 })
		expect(Jobs.teams({}, Departments).Reception).toBe(0)
	end)

	test("teamEffects: 2 the small bonus, 3+ the big one, never stacked", function()
		local none = Jobs.teamEffects(Jobs.teams({ "Reception" }, Departments), Departments)
		expect(none).toEqual({ Cash = 1, Urgent = 1, Recover = 1, Make = {} })
		local two = Jobs.teamEffects(Jobs.teams({ "Reception", "Reception" }, Departments), Departments)
		expect(two.Cash).toBeCloseTo(1.1)
		local four = Jobs.teamEffects(
			Jobs.teams({ "Reception", "Reception", "Reception", "Reception" }, Departments),
			Departments
		)
		expect(four.Cash).toBeCloseTo(1.2)
		local hydro = Jobs.teamEffects(Jobs.teams({ "Hydro", "Hydro", "Hydro" }, Departments), Departments)
		expect(hydro.Make.Bath).toBeCloseTo(0.6) -- 🛁 holds 40% shorter
		local pharmacy = Jobs.teamEffects(Jobs.teams({ "Pharmacy", "Pharmacy" }, Departments), Departments)
		expect(pharmacy.Make.Cocoa).toBeCloseTo(0.8)
		expect(pharmacy.Make.Pharmacy).toBeCloseTo(0.8)
		local mixed = Jobs.teamEffects(Jobs.teams({ "AE", "AE", "Wards", "Wards", "Wards" }, Departments), Departments)
		expect(mixed.Urgent).toBeCloseTo(1.25)
		expect(mixed.Recover).toBeCloseTo(0.5)
	end)
end)
