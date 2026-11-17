--!nocheck
-- Simple at the start (memory-20261117-006; docs/plan/2026-11-17-simple-start-design.md §1). A Lv 1 clinic has three
-- cases (Cough 🩺, Cut knee 🔍, Fever 🌡️), the exam card's three tools, two places (the Plaster shelf and the
-- dispensary) and two bottles on the dispensary shelf. Lv 2 adds Bumped head, Earache and Sprain; Lv 3 Sore throat,
-- Rash and Broken arm; Lv 5 Broken leg. A room's case still comes with its room. Pure: Lune only.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local Visit = require("../src/shared/Logic/Visit")
local Building = require("../src/shared/Logic/Building")
local Cases = require("../src/shared/Data/Cases")
local Tools = require("../src/shared/Data/Tools")
local Items = require("../src/shared/Data/Items")
local Levels = require("../src/shared/Data/Levels")
local Regulars = require("../src/shared/Data/Regulars")

local LV1 = { Cough = true, CutKnee = true, Fever = true }
local LV2 = { BumpedHead = true, Earache = true, Sprain = true }
local LV3 = { SoreThroat = true, Rash = true, BrokenArm = true }

-- What a clinic at `level` with `rooms` can treat: its level, its rooms, every plan station open (the Building's by
-- level, a room's own when owned) and its exam tool in use (Server/Patients Pure.eligible checks the same).
local function can(level: number, rooms: { [string]: boolean })
	local function open(id: string): boolean
		if id == "Bath" then
			return rooms.BathRoom == true
		elseif id == "Cocoa" then
			return rooms.WinterWing == true
		end
		return Building.stationOpen(id, level)
	end
	local tools = Visit.unlocked(level, Tools)
	return function(caseId: string): boolean
		local case = Cases[caseId]
		return Visit.canTreat(case, level, rooms, open, Items) and table.find(tools, case.Tool) ~= nil
	end
end

-- Every case a pool can roll at that clinic (rolls 0, 0.01 .. 0.99).
local function rolled(pool: { string }, level: number, rooms: { [string]: boolean }): { [string]: boolean }
	local out = {}
	local allow = can(level, rooms)
	for i = 0, 99 do
		local id = Visit.rollCase(pool, allow, i / 100)
		if id then
			out[id] = true
		end
	end
	return out
end

local function union(...): { [string]: boolean }
	local out = {}
	for _, set in { ... } do
		for id in set do
			out[id] = true
		end
	end
	return out
end

local function loadShelf(): any
	local text: string? = nil
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. "src/client/UI/MiniGames.luau") then
			text = fs.readFile(prefix .. "src/client/UI/MiniGames.luau")
			break
		end
	end
	assert(text, "can't find MiniGames.luau (run from game/)")
	local first = string.find(text, "PURE:BEGIN", 1, true)
	local last = string.find(text, "PURE:END", 1, true)
	assert(first and last and last > first, "PURE markers missing")
	local from = (string.find(text, "\n", first, true) :: number) + 1
	local upto = (string.find(text, "\n[^\n]*PURE:END", from) :: number) - 1
	return luau.load(string.sub(text, from, upto) .. "\nreturn Pure", { debugName = "MiniGames.Pure" })()
end

T.describe("Simple start: the cases by level", function()
	test("Lv 1 rolls only Cough, Cut knee and Fever from every pool (no rooms owned)", function()
		for wing, pool in Cases.POOLS do
			for id in rolled(pool, 1, {}) do
				if not LV1[id] then
					error(wing .. " pool rolled " .. id .. " at Lv 1")
				end
			end
		end
		expect(rolled(Cases.POOLS.Starter, 1, {})).toEqual(LV1)
		expect(rolled(Cases.POOLS.Night, 1, {})).toEqual(LV1)
	end)

	test("a room's case still comes with its room at Lv 1, and only from its own wing", function()
		local rooms = { BathRoom = true, WinterWing = true }
		expect(rolled(Cases.POOLS.Bath, 1, rooms)).toEqual(union(LV1, { SoreMuscles = true }))
		expect(rolled(Cases.POOLS.Winter, 1, rooms)).toEqual(union(LV1, { Chills = true }))
		expect(rolled(Cases.POOLS.Starter, 1, rooms)).toEqual(LV1)
		expect(rolled(Cases.POOLS.Night, 1, rooms)).toEqual(LV1)
	end)

	test("Lv 2 adds Bumped head, Earache and Sprain; Lv 3 Sore throat, Rash and Broken arm", function()
		expect(rolled(Cases.POOLS.Starter, 2, {})).toEqual(union(LV1, LV2))
		expect(rolled(Cases.POOLS.Starter, 3, {})).toEqual(union(LV1, LV2, LV3))
		expect(rolled(Cases.POOLS.Starter, 5, {})).toEqual(union(LV1, LV2, LV3))
		for id in LV2 do
			expect(Cases[id].Level).toBe(2)
		end
		for id in LV3 do
			expect(Cases[id].Level).toBe(3)
		end
		expect(Cases.BrokenLeg.Level).toBe(5)
		expect(rolled(Cases.POOLS.Sky, 4, {})).toEqual({})
		expect(rolled(Cases.POOLS.Sky, 5, {})).toEqual({ BrokenLeg = true })
	end)

	test("the Night pool is Lv 1 cases only, at every level", function()
		for level = 1, #Levels do
			expect(rolled(Cases.POOLS.Night, level, {})).toEqual(LV1)
		end
	end)

	test("every pool (but the helicopter's Sky) yields a case at every level, with or without rooms", function()
		for wing, pool in Cases.POOLS do
			if wing ~= "Sky" then
				for level = 1, #Levels do
					for _, rooms in { {}, { BathRoom = true, WinterWing = true } } do
						if next(rolled(pool, level, rooms)) == nil then
							error(wing .. " pool yields nothing at Lv " .. level)
						end
					end
				end
			end
		end
	end)

	test("the tutorial's two cases are Lv 1: a cough (the dispensary), then a cut knee (the Plaster shelf)", function()
		expect(Cases.Cough.Level).toBe(1)
		expect(Items[Cases.Cough.Plan[1]].Station).toBe("Remedy")
		expect(Cases.CutKnee.Level).toBe(1)
		expect(Items[Cases.CutKnee.Plan[1]].Station).toBe("Plaster")
	end)

	test("every regular's case has a level where it can be treated, and the first one's is Lv 1", function()
		for _, id in Regulars.Order do
			local case = Cases[Regulars[id].Case]
			expect(can(case.Level, {})(Regulars[id].Case)).toBe(true)
		end
		expect(Cases[Regulars.ShySprout.Case].Level).toBe(1)
	end)

	test("every case id is kept", function()
		expect(Cases.ORDER).toEqual({
			"Cough",
			"Fever",
			"CutKnee",
			"BumpedHead",
			"Earache",
			"Sprain",
			"SoreThroat",
			"Rash",
			"BrokenArm",
			"SoreMuscles",
			"Chills",
			"BrokenLeg",
		})
	end)
end)

T.describe("Simple start: tools, stations and the shelf at Lv 1", function()
	test("the exam card at Lv 1 is exactly 🩺 🌡️ 🔍, the answer always among them", function()
		local three = { "Stethoscope", "Thermometer", "Magnifier" }
		expect(Visit.unlocked(1, Tools)).toEqual(three)
		expect(Visit.unlocked(2, Tools)).toEqual({ "Stethoscope", "Thermometer", "Light", "Magnifier" })
		expect(table.find(Visit.unlocked(2, Tools), "XRay")).toBeNil()
		expect(table.find(Visit.unlocked(3, Tools), "XRay") ~= nil).toBe(true)
		for id in LV1 do
			for i = 0, 99 do
				local card = Visit.examTools(Cases[id].Tool, Visit.unlocked(1, Tools), i / 100)
				local sorted = table.clone(card)
				table.sort(sorted)
				expect(sorted).toEqual({ "Magnifier", "Stethoscope", "Thermometer" })
				expect(table.find(card, Cases[id].Tool) ~= nil).toBe(true)
			end
		end
		expect(Cases.Cough.Tool).toBe("Stethoscope")
		expect(Cases.CutKnee.Tool).toBe("Magnifier")
		expect(Cases.Fever.Tool).toBe("Thermometer")
	end)

	test("the Lv 1 places are the Plaster shelf and the dispensary; Ice and Bandage at Lv 2, Cast at Lv 3", function()
		local function openAt(level: number): { string }
			local out = {}
			for id in Building.STATIONS do
				if Building.stationOpen(id, level) then
					table.insert(out, id)
				end
			end
			table.sort(out)
			return out
		end
		expect(openAt(1)).toEqual({ "Plaster", "Remedy" })
		expect(openAt(2)).toEqual({ "Bandage", "Ice", "Plaster", "Remedy" })
		expect(openAt(3)).toEqual({ "Bandage", "Cast", "Ice", "Plaster", "Remedy" })
	end)

	test("the Lv 1 dispensary shelf has exactly cough syrup and fever medicine", function()
		local Pure = loadShelf()
		local pool = {}
		for _, id in Items.Order do
			if Items[id].Kind == "Medicine" then
				table.insert(pool, { Id = id, Icon = Items[id].Icon })
			end
		end
		for _, answer in { "CoughSyrup", "FeverMeds" } do
			local shelf, count = Pure.shelf(answer, pool, Cases, 1, Levels, 4)
			local ids = {}
			for _, entry in shelf do
				table.insert(ids, entry.Id)
			end
			table.sort(ids)
			expect(ids).toEqual({ "CoughSyrup", "FeverMeds" })
			expect(count).toBe(2)
		end
	end)
end)

T.describe("Simple start: the 🦴 symptom", function()
	test("an X-ray case's bubble starts with 🦴; no other case's does", function()
		expect(Cases.BONE).toBe("🦴")
		for _, id in Cases.ORDER do
			local case = Cases[id]
			local bone = string.sub(case.Bubble, 1, #Cases.BONE) == Cases.BONE
			expect(bone).toBe(case.Tool == Visit.XRAY)
		end
		expect(string.sub(Cases.BrokenArm.Bubble, 1, #Cases.BONE)).toBe("🦴")
		expect(string.sub(Cases.BrokenLeg.Bubble, 1, #Cases.BONE)).toBe("🦴")
	end)
end)
