--!nocheck
-- The visit's pure rules (Logic/Visit; Real Clinic build plan, contract C4; design §5, §6 and §15): which case a
-- patient gets, whether a clinic can treat it, the exam's three tools, the glow, the plan, the ward stay, who goes to
-- which bay and who is the front patient.

local T = require("./expect")
local expect, test = T.expect, T.test

local Config = require("./config")
local Visit = require("../src/shared/Logic/Visit")
local Recipe = require("../src/shared/Logic/Recipe")
local Cases = require("../src/shared/Data/Cases")
local Tools = require("../src/shared/Data/Tools")
local Items = require("../src/shared/Data/Items")
local Levels = require("../src/shared/Data/Levels")
local Building = require("../src/shared/Logic/Building")

local function rolls()
	local out = {}
	for i = 0, 99 do
		table.insert(out, i / 100)
	end
	table.insert(out, 0.999999)
	return out
end

-- What a clinic's stations make: the Building's by level, plus the bought rooms' own.
local function stationOpen(level, rooms)
	return function(id)
		if id == "Bath" then
			return rooms.BathRoom == true
		elseif id == "Cocoa" then
			return rooms.WinterWing == true
		end
		return Building.stationOpen(id, level)
	end
end

local function can(level, rooms)
	return function(caseId)
		return Visit.canTreat(Cases[caseId], level, rooms, stationOpen(level, rooms), Items)
	end
end

local function distinct(list)
	local seen = {}
	for _, id in list do
		if seen[id] then
			return false
		end
		seen[id] = true
	end
	return true
end

T.describe("Visit.rollCase", function()
	test("never returns a case `can` refuses; picks evenly among the rest", function()
		local pool = { "Cough", "Fever", "CutKnee", "Sprain", "BrokenArm" }
		local function allow(id)
			return id ~= "Sprain" and id ~= "BrokenArm"
		end
		local counts = {}
		for _, roll in rolls() do
			local id = Visit.rollCase(pool, allow, roll)
			expect(allow(id)).toBe(true)
			counts[id] = (counts[id] or 0) + 1
		end
		expect(counts.Sprain).toBeNil()
		for _, id in { "Cough", "Fever", "CutKnee" } do
			expect(counts[id] >= 30).toBe(true)
		end
		expect(Visit.rollCase(pool, allow, 0)).toBe("Cough")
		expect(Visit.rollCase(pool, allow, 0.999999)).toBe("CutKnee")
	end)

	test("an empty pool, or one nothing in is allowed, gives nil; a bad roll still picks", function()
		expect(Visit.rollCase({}, function()
			return true
		end, 0.5)).toBeNil()
		expect(Visit.rollCase({ "Cough" }, function()
			return false
		end, 0.5)).toBeNil()
		expect(Visit.rollCase(nil, nil, 0.5)).toBeNil()
		local always = function()
			return true
		end
		for _, roll in { -1, 1, 7, 0 / 0, "x" } do
			expect(Visit.rollCase({ "Cough", "Fever" }, always, roll) ~= nil).toBe(true)
		end
	end)

	test("an id listed twice in a pool is twice as likely", function()
		local counts = { A = 0, B = 0 }
		for _, roll in rolls() do
			local id = Visit.rollCase({ "A", "A", "A", "B" }, function()
				return true
			end, roll)
			counts[id] += 1
		end
		expect(counts.A > counts.B * 2).toBe(true)
	end)
end)

T.describe("Visit.canTreat (Review Focus 1: never a case needing an item no open station makes)", function()
	test("a Lv 1 clinic treats the three Lv 1 cases and nothing else (simple start)", function()
		local allowed = {}
		for _, id in Cases.ORDER do
			if can(1, {})(id) then
				table.insert(allowed, id)
			end
		end
		expect(allowed).toEqual({ "Cough", "Fever", "CutKnee" })
	end)

	test("levels and rooms open the rest", function()
		expect(can(1, {})("Sprain")).toBe(false) -- bandages are Lv 2
		expect(can(1, {})("BumpedHead")).toBe(false) -- the Ice chest is Lv 2
		expect(can(2, {})("BumpedHead")).toBe(true)
		expect(can(1, {})("Earache")).toBe(false) -- the 🔦 Light is Lv 2
		expect(can(2, {})("Earache")).toBe(true)
		expect(can(2, {})("Rash")).toBe(false) -- Lv 3
		expect(can(3, {})("SoreThroat")).toBe(true)
		expect(can(2, {})("Sprain")).toBe(true)
		expect(can(2, {})("BrokenArm")).toBe(false) -- the X-ray and casts are Lv 3
		expect(can(3, {})("BrokenArm")).toBe(true)
		expect(can(4, {})("BrokenLeg")).toBe(false)
		expect(can(5, {})("BrokenLeg")).toBe(true)
		expect(can(5, {})("SoreMuscles")).toBe(false) -- no Bath Room
		expect(can(1, { BathRoom = true })("SoreMuscles")).toBe(true)
		expect(can(5, { BathRoom = true })("Chills")).toBe(false)
		expect(can(1, { WinterWing = true })("Chills")).toBe(true)
	end)

	test("every plan item's station must be open, whatever the level says", function()
		local closed = function(id)
			return id ~= "Ice"
		end
		expect(Visit.canTreat(Cases.BumpedHead, 5, {}, closed, Items)).toBe(false)
		expect(Visit.canTreat(Cases.Rash, 5, {}, closed, Items)).toBe(false) -- its second step
		expect(Visit.canTreat(Cases.Cough, 5, {}, closed, Items)).toBe(true)
		-- an unknown item, a missing case or junk is never treatable
		expect(Visit.canTreat({ Level = 1, Tool = "Light", Plan = { "Gum" } }, 5, {}, function()
			return true
		end, Items)).toBe(false)
		expect(Visit.canTreat({ Level = 1, Tool = "Light", Plan = {} }, 5, {}, function()
			return true
		end, Items)).toBe(false)
		expect(Visit.canTreat(nil, 5, {}, closed, Items)).toBe(false)
		expect(Visit.canTreat(Cases.Cough, 0 / 0, {}, closed, Items)).toBe(true) -- a bad level counts as Lv 1
	end)

	test("with rollCase: a spawn at any level and any rooms only ever picks a case that clinic can treat", function()
		for level = 1, 5 do
			for _, rooms in { {}, { BathRoom = true }, { WinterWing = true }, { BathRoom = true, WinterWing = true } } do
				local allow = can(level, rooms)
				for wing, pool in Cases.POOLS do
					for _, roll in rolls() do
						local id = Visit.rollCase(pool, allow, roll)
						if id then
							local case = Cases[id]
							expect(case.Level <= level).toBe(true)
							expect(case.Room == nil or rooms[case.Room] == true).toBe(true)
							for _, item in case.Plan do
								expect(stationOpen(level, rooms)(Items[item].Station)).toBe(true)
							end
						end
					end
					-- every wing that can come to a Lv 1 clinic has a case there
					if wing == "Starter" or wing == "Night" or wing == "Sunny" then
						expect(Visit.rollCase(pool, allow, 0.5) ~= nil).toBe(true)
					end
				end
			end
		end
		-- the helicopter's wing has nothing below Lv 5
		expect(Visit.rollCase(Cases.POOLS.Sky, can(4, {}), 0.5)).toBeNil()
		expect(Visit.rollCase(Cases.POOLS.Sky, can(5, {}), 0.5)).toBe("BrokenLeg")
	end)
end)

T.describe("Visit.examTools", function()
	test("3 distinct tools with the answer among them, even an answer that isn't unlocked", function()
		local tools = Visit.examTools("XRay", { "Stethoscope", "Magnifier" }, 0.5)
		expect(#tools).toBe(3)
		expect(distinct(tools)).toBe(true)
		expect(table.find(tools, "XRay") ~= nil).toBe(true)
	end)

	test("every answer, every roll: 3 distinct known tools from the unlocked ones", function()
		local unlocked = { "Stethoscope", "Thermometer", "Light", "Magnifier" }
		local places = {}
		for _, answer in Tools.ORDER do
			for _, roll in rolls() do
				local tools = Visit.examTools(answer, unlocked, roll)
				expect(#tools).toBe(3)
				expect(distinct(tools)).toBe(true)
				local at = table.find(tools, answer)
				expect(at ~= nil).toBe(true)
				places[at] = true
				for _, id in tools do
					expect(Tools[id] ~= nil).toBe(true)
					expect(id == answer or table.find(unlocked, id) ~= nil).toBe(true)
				end
				expect(Visit.examTools(answer, unlocked, roll)).toEqual(tools) -- the roll decides it
			end
		end
		expect(places).toEqual({ true, true, true }) -- the answer isn't always in the same place
	end)

	test("fewer than 3 when fewer are unlocked; the list passed in is never changed", function()
		expect(Visit.examTools("Light", {}, 0.3)).toEqual({ "Light" })
		expect(Visit.examTools("Light", { "Light" }, 0.3)).toEqual({ "Light" })
		local unlocked = { "Light", "Magnifier", "Magnifier" }
		local two = Visit.examTools("Light", unlocked, 0.3)
		table.sort(two)
		expect(two).toEqual({ "Light", "Magnifier" })
		expect(unlocked).toEqual({ "Light", "Magnifier", "Magnifier" })
		expect(#Visit.examTools("Light", nil, 0 / 0)).toBe(1)
	end)

	test("unlocked(level, tools): three hand tools at Lv 1, the Light from Lv 2, the X-ray from Lv 3", function()
		expect(Visit.unlocked(1, Tools)).toEqual({ "Stethoscope", "Thermometer", "Magnifier" })
		expect(Visit.unlocked(2, Tools)).toEqual({ "Stethoscope", "Thermometer", "Light", "Magnifier" })
		expect(Visit.unlocked(3, Tools)).toEqual(Tools.ORDER)
	end)
end)

T.describe("Visit: the glow, the plan and the ward stay", function()
	test("the right tool glows for the first 3 exams, and always in Simple mode", function()
		expect(Visit.glow(0, false)).toBe(true)
		expect(Visit.glow(2, false)).toBe(true)
		expect(Visit.glow(3, false)).toBe(false)
		expect(Visit.glow(9, true)).toBe(true)
		expect(Visit.glow(nil, false)).toBe(true) -- an unknown count is a new player
		expect(Visit.EXAMS_GLOW).toBe(Config.Visit.ExamsGlow)
		expect(Visit.glow(4, false, { Visit = { ExamsGlow = 5 } })).toBe(true)
	end)

	test("the plan is the case's plan cut by the level's cap (Logic/Recipe.effective)", function()
		for _, id in Cases.ORDER do
			for cap = 0, 4 do
				expect(Visit.plan(Cases[id], cap)).toEqual(Recipe.effective(Cases[id].Plan, cap))
			end
		end
		expect(Visit.plan(Cases.BrokenLeg, 1)).toEqual({ "Cast" })
		expect(Visit.plan(Cases.BrokenLeg, 3)).toEqual({ "Cast", "PainRelief", "Bandage" })
		expect(Visit.plan(Cases.Sprain, Levels[2].RecipeCap)).toEqual({ "Ice", "Bandage" })
		local plan = Visit.plan(Cases.Cough, 3)
		table.insert(plan, "Junk") -- a copy: the data is never changed
		expect(Cases.Cough.Plan).toEqual({ "CoughSyrup" })
		expect(Visit.plan(nil, 3)).toEqual({})
	end)

	test("a Stay case rests in the Injury Ward from Lv 2 and the Rest Ward from Lv 3", function()
		expect(Visit.stayWard(Cases.BrokenArm, 1)).toBeNil()
		expect(Visit.stayWard(Cases.BrokenArm, 2)).toBe("Wards")
		expect(Visit.stayWard(Cases.BrokenArm, 5)).toBe("Wards")
		expect(Visit.stayWard(Cases.Sprain, 2)).toBe("Wards") -- the Injury Ward has patients from the level it opens
		expect(Visit.stayWard(Cases.Fever, 2)).toBeNil()
		expect(Visit.stayWard(Cases.Fever, 3)).toBe("Rest")
		expect(Visit.stayWard(Cases.Chills, 5)).toBe("Rest")
		expect(Visit.stayWard(Cases.Cough, 5)).toBeNil()
		expect(Visit.stayWard(nil, 5)).toBeNil()
		-- the ward it names has beds at that level
		for _, id in Cases.ORDER do
			for level = 1, 5 do
				local ward = Visit.stayWard(Cases[id], level)
				if ward then
					local found = false
					for floor = 1, 3 do
						for _, bed in Building.wardBeds(level, floor) do
							found = found or bed.Ward == ward
						end
					end
					expect(found).toBe(true)
				end
			end
		end
	end)
end)

T.describe("Visit.nextForBay and Visit.front", function()
	local waiting = {
		{ Id = 1, Since = 30, Tool = "Stethoscope" },
		{ Id = 2, Since = 10, Tool = "XRay" }, -- a broken arm: the longest wait, but only for the X-ray bay
		{ Id = 3, Since = 20, Tool = "Magnifier" },
		{ Id = 4, Since = 25, Tool = "XRay" },
	}

	test("a BrokenArm patient goes only to an XRay bay; each bay takes the one who waited longest", function()
		expect(Cases.BrokenArm.Tool).toBe("XRay")
		expect(Visit.nextForBay(waiting, "XRay")).toBe(2)
		expect(Visit.nextForBay(waiting, "Exam")).toBe(3)
		expect(Visit.nextForBay({ waiting[2], waiting[4] }, "Exam")).toBeNil()
		expect(Visit.nextForBay({ waiting[1], waiting[3] }, "XRay")).toBeNil()
		expect(Visit.nextForBay({}, "Exam")).toBeNil()
		expect(Visit.nextForBay(nil, "Exam")).toBeNil()
	end)

	test("a tie goes to the lower id; junk rows are skipped", function()
		local tie = { { Id = 9, Since = 5, Tool = "Light" }, { Id = 4, Since = 5, Tool = "Light" }, "junk", {} }
		expect(Visit.nextForBay(tie, "Exam")).toBe(4)
	end)

	test("the front patient: the bay patient who has waited longest for the doctor", function()
		local inBays = {
			{ Id = 1, Since = 5, NeedsDoctor = false }, -- mid-game or resting
			{ Id = 2, Since = 40, NeedsDoctor = true },
			{ Id = 3, Since = 12, NeedsDoctor = true },
		}
		expect(Visit.front(inBays)).toBe(3)
		inBays[3].NeedsDoctor = false
		expect(Visit.front(inBays)).toBe(2)
		inBays[2].NeedsDoctor = false
		expect(Visit.front(inBays)).toBeNil()
		expect(Visit.front({})).toBeNil()
		expect(Visit.front(nil)).toBeNil()
	end)

	test("patience drains at half speed in the waiting room and full speed in a bay", function()
		expect(Visit.PATIENCE).toEqual({ Waiting = 0.5, Bay = 1 })
		expect(Visit.PATIENCE.Waiting).toBe(Config.QueuePatienceRate)
	end)
end)
