--!nocheck
-- The visit's server rules (Real Clinic build plan, Task 4; Progression v2 build plan §C T7): the PURE-BEGIN..PURE-END
-- block of Server/Patients, loaded on its own (the rest of the module needs Roblox) against the real Logic/Recipe,
-- Logic/Hospital, Logic/Visit, Logic/Building, Shared/Config (tests/config.luau) and the Lune-safe Data (Cases, Items,
-- Tools, Levels, Wings). Which case comes (Review Focus 1), who takes which bay, the front patient, re-seating after a
-- rebuild (Review Focus 2), the owner leaving (Review Focus 4), the ward stay and its pick, escort and pay, the urgent
-- plan and its 🧊 pad, patience and timers, variants and wing gates. The session side is TreatmentSessions.spec. Run
-- from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local Config = require("./config")
local Recipe = require("../src/shared/Logic/Recipe")
local Hospital = require("../src/shared/Logic/Hospital")
local Visit = require("../src/shared/Logic/Visit")
local Building = require("../src/shared/Logic/Building")
local Cases = require("../src/shared/Data/Cases")
local Items = require("../src/shared/Data/Items")
local Tools = require("../src/shared/Data/Tools")
local Levels = require("../src/shared/Data/Levels")
local Wings = require("../src/shared/Data/Wings")

local function source(path: string): string
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("can't find " .. path .. " (run from game/)")
end

local function loadPure(path: string, env: { [string]: any }): any
	local text = source(path)
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to and to > from, path .. ": no PURE block")
	local block = string.sub(text, from, to - 1) .. "\nreturn Pure\n"
	return luau.load(block, { debugName = path .. " (pure)", environment = env })()
end

local P = loadPure("src/server/Patients.luau", {
	Recipe = Recipe,
	Hospital = Hospital,
	Visit = Visit,
	Cases = Cases,
	Items = Items,
	Tools = Tools,
})
local MAX_EXTRA = 5 -- Logic/Pay.MAX_EXTRA

-- A clinic as Pure.eligible sees it: the Building's stations by level, the bought rooms' own, and its usable bays
-- (Logic/Building.openBays with every bay built).
local function clinic(level: number, rooms: { [string]: boolean }?, overrides: { [string]: any }?): any
	local owned = rooms or {}
	local stations = {}
	for stationId in Building.STATIONS do
		if Building.stationOpen(stationId, level) then
			stations[stationId] = true
		end
	end
	if owned.BathRoom then
		stations.Bath = true
	end
	if owned.WinterWing then
		stations.Cocoa = true
	end
	local bays = { Exam = false, XRay = false }
	for _, bay in Building.openBays(level, owned) do
		bays[bay.Kind] = true
	end
	local view = { Level = level, Rooms = owned, Stations = stations, Bays = bays }
	for key, value in overrides or {} do
		view[key] = value
	end
	return view
end

local function rolls()
	local out = {}
	for i = 0, 99 do
		table.insert(out, i / 100)
	end
	table.insert(out, 0.999999)
	return out
end

-- Every case Pure.pickCase can give that wing at that clinic, over 101 rolls.
local function picks(wing: string, view: any): { [string]: boolean }
	local seen = {}
	for _, roll in rolls() do
		local caseId = P.pickCase(wing, view, roll)
		if caseId then
			seen[caseId] = true
		end
	end
	return seen
end

T.describe("Patients.Pure: which case comes (Review Focus 1)", function()
	test(
		"eligible: no Sprain at Lv 1, no Broken arm without the X-ray, no Sore muscles without the Bath Room",
		function()
			expect(P.eligible(Cases.Sprain, clinic(1))).toBe(false) -- Lv 2, and no bandages at Lv 1
			expect(P.eligible(Cases.Sprain, clinic(2))).toBe(true)
			expect(P.eligible(Cases.BrokenArm, clinic(2))).toBe(false)
			expect(P.eligible(Cases.BrokenArm, clinic(3))).toBe(true)
			-- Lv 3 but the X-ray bay isn't built (or its Station_Cast is shut): never
			expect(P.eligible(Cases.BrokenArm, clinic(3, {}, { Bays = { Exam = true, XRay = false } }))).toBe(false)
			local noCast = clinic(3)
			noCast.Stations.Cast = nil
			expect(P.eligible(Cases.BrokenArm, noCast)).toBe(false)
			expect(P.eligible(Cases.SoreMuscles, clinic(5))).toBe(false)
			expect(P.eligible(Cases.SoreMuscles, clinic(1, { BathRoom = true }))).toBe(true)
			expect(P.eligible(Cases.Chills, clinic(1))).toBe(false)
			expect(P.eligible(Cases.Chills, clinic(1, { WinterWing = true }))).toBe(true)
			expect(P.eligible(Cases.Cough, clinic(1))).toBe(true)
			expect(P.eligible(nil, clinic(5))).toBe(false)
			expect(P.eligible(Cases.Cough, nil)).toBe(false)
		end
	)

	test("a case needing an item no open station makes is never picked, for any plot", function()
		-- every level, with and without each room, and with each Building station shut in turn
		local roomSets = { {}, { BathRoom = true }, { WinterWing = true }, { BathRoom = true, WinterWing = true } }
		for level = 1, 5 do
			for _, rooms in roomSets do
				local views = { clinic(level, rooms) }
				for stationId in Building.STATIONS do
					local shut = clinic(level, rooms)
					shut.Stations[stationId] = nil
					table.insert(views, shut)
				end
				for _, view in views do
					for wing in Cases.POOLS do
						for picked in picks(wing, view) do
							for _, itemId in Cases[picked].Plan do
								expect(view.Stations[Items[itemId].Station]).toBe(true)
							end
						end
					end
				end
			end
		end
	end)

	test("a spawn at Lv 1 never picks a case outside Lv 1 (every wing's pool)", function()
		for wing in Cases.POOLS do
			for picked in picks(wing, clinic(1, { BathRoom = true, WinterWing = true })) do
				expect(Cases[picked].Level).toBe(1)
			end
		end
		expect(picks("Starter", clinic(1))).toEqual({
			Cough = true,
			Fever = true,
			CutKnee = true,
			BumpedHead = true,
			Earache = true,
		})
		expect(P.pickCase("Sky", clinic(4), 0.5)).toBeNil() -- the broken leg: Lv 5 only
		expect(P.pickCase("Sky", clinic(5), 0.5)).toBe("BrokenLeg")
	end)

	test("night patients get Lv 1 cases only; an unknown wing uses the Starter pool", function()
		for _, level in { 1, 3, 5 } do
			for picked in picks("Night", clinic(level)) do
				expect(Cases[picked].Level).toBe(1)
				expect(Cases[picked].Room).toBeNil()
			end
		end
		expect(P.poolFor("Night")).toEqual(Cases.POOLS.Night)
		expect(P.poolFor("Nowhere")).toEqual(Cases.POOLS.Starter)
		expect(P.poolFor(nil)).toEqual(Cases.POOLS.Starter)
	end)

	test("a Bath patient brings its own case often once the Bath Room is there; nothing it can't have", function()
		local seen = picks("Bath", clinic(1, { BathRoom = true }))
		expect(seen.SoreMuscles).toBe(true)
		expect(seen.Sprain).toBeNil()
		expect(picks("Bath", clinic(1)).SoreMuscles).toBeNil()
	end)

	test("wingRoom: a Bath-wing patient needs the Bath Room, a Winter-wing one the Winter Wing", function()
		expect(P.wingRoom("Bath", {})).toBe(false)
		expect(P.wingRoom("Bath", { BathRoom = true })).toBe(true)
		expect(P.wingRoom("Winter", { BathRoom = true })).toBe(false)
		expect(P.wingRoom("Winter", { WinterWing = true })).toBe(true)
		expect(P.wingRoom("Starter", {})).toBe(true)
		expect(P.wingRoom("Night", nil)).toBe(true)
	end)

	test("makes: what the open stations make (every medicine with the dispensary)", function()
		local made = P.makes({ Remedy = true, Plaster = true })
		expect(made.Plaster).toBe(true)
		expect(made.CoughSyrup).toBe(true)
		expect(made.PainRelief).toBe(true)
		expect(made.Ice).toBeNil()
		expect(P.makes(nil)).toEqual({})
	end)

	test("the tutorial's patients: a cough (the dispensary), then a cut knee (a plaster)", function()
		expect(P.tutorialCase("Remedy", clinic(1))).toBe("Cough")
		expect(P.tutorialCase("Plaster", clinic(1))).toBe("CutKnee")
		expect(P.tutorialCase("Plaster", clinic(5))).toBe("CutKnee")
		expect(P.tutorialCase("Cast", clinic(5))).toBeNil() -- no Lv 1 case starts at the cast table
		expect(P.tutorialCase("Remedy", clinic(1, {}, { Bays = {} }))).toBeNil() -- no bay: nobody
	end)
end)

T.describe("Patients.Pure: bays and the front patient", function()
	local function bays(level: number, rooms: { [string]: boolean }?)
		local out = {}
		for _, bay in Building.openBays(level, rooms) do
			table.insert(out, { Id = bay.Id, Kind = bay.Kind })
		end
		return out
	end

	test("assign: the longest-waiting patient first; an X-ray case only to the X-ray bay", function()
		local waiting = {
			{ Id = 1, Since = 30, Tool = "Stethoscope" },
			{ Id = 2, Since = 10, Tool = "XRay" },
			{ Id = 3, Since = 20, Tool = "Magnifier" },
		}
		expect(P.assign(bays(1), waiting)).toEqual({ { Bay = "1", Patient = 3 }, { Bay = "2", Patient = 1 } })
		expect(P.assign(bays(3), waiting)).toEqual({
			{ Bay = "1", Patient = 3 },
			{ Bay = "2", Patient = 1 },
			{ Bay = "X", Patient = 2 },
		})
		expect(P.assign({ { Id = "X", Kind = "XRay" } }, { { Id = 1, Since = 1, Tool = "Light" } })).toEqual({})
		expect(P.assign({}, waiting)).toEqual({})
		expect(#waiting).toBe(3) -- the list passed in is never changed
	end)

	test("an urgent patient (it counts as waiting much longer) takes the next free bay", function()
		local waiting = {
			{ Id = 1, Since = 10, Tool = "Stethoscope" },
			{ Id = 9, Since = 50 - 1e6, Tool = "Light" },
		}
		expect(P.assign({ { Id = "4", Kind = "Exam" } }, waiting)).toEqual({ { Bay = "4", Patient = 9 } })
	end)

	test("the Cozy Ward's two bays work from Lv 1 once the room is owned", function()
		local ids = {}
		for _, bay in bays(1, { Ward = true }) do
			table.insert(ids, bay.Id)
		end
		expect(ids).toEqual({ "1", "2", "W1", "W2" })
	end)

	test("the front is the longest-waiting bay patient who needs the doctor", function()
		local rows = {
			{ Id = 4, Since = 12, NeedsDoctor = true },
			{ Id = 2, Since = 5, NeedsDoctor = false }, -- mid-game: not the front
			{ Id = 7, Since = 9, NeedsDoctor = true },
			{ Id = 3, Since = 9, NeedsDoctor = true },
		}
		expect(P.frontOrder(rows)).toEqual({ 3, 7, 4 })
		expect(P.frontOrder(rows)[1]).toBe(Visit.front(rows))
		expect(P.frontOrder({})).toEqual({})
		expect(#rows).toBe(4)
	end)
end)

T.describe("Patients.Pure: rebuilds and leavers (Review Focus 2 and 4)", function()
	local SEATS = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true }

	test("reseat: a rebuild that keeps the bays keeps everyone where they are", function()
		local list = {
			{ Id = 1, Bay = "1" },
			{ Id = 2, Bay = "2" },
			{ Id = 3, Seat = 1 },
			{ Id = 4, Seat = 4 },
		}
		local out = P.reseat(list, SEATS, { ["1"] = true, ["2"] = true, ["3"] = true })
		expect(out[1]).toEqual({ Bay = "1", Leave = false })
		expect(out[2]).toEqual({ Bay = "2", Leave = false })
		expect(out[3]).toEqual({ Seat = 1, Leave = false })
		expect(out[4]).toEqual({ Seat = 4, Leave = false })
	end)

	test("reseat: a patient whose bay closed sits down again on the lowest free seat; never two on one", function()
		local list = {
			{ Id = 1, Bay = "1" },
			{ Id = 5, Bay = "5" },
			{ Id = 6, Bay = "W1" },
			{ Id = 3, Seat = 1 },
		}
		local out = P.reseat(list, SEATS, { ["1"] = true, ["2"] = true })
		expect(out[1]).toEqual({ Bay = "1", Leave = false })
		expect(out[3]).toEqual({ Seat = 1, Leave = false })
		expect(out[5]).toEqual({ Seat = 2, Leave = false })
		expect(out[6]).toEqual({ Seat = 3, Leave = false })
	end)

	test("reseat: with no seat free it goes home ('Leave': no penalty), and everyone is mapped", function()
		local list = {}
		for id = 1, 6 do
			table.insert(list, { Id = id, Seat = id })
		end
		table.insert(list, { Id = 7, Bay = "6" })
		table.insert(list, { Id = 8, Bay = "5" })
		local out = P.reseat(list, SEATS, { ["1"] = true })
		for id = 1, 6 do
			expect(out[id]).toEqual({ Seat = id, Leave = false })
		end
		expect(out[7]).toEqual({ Leave = true })
		expect(out[8]).toEqual({ Leave = true })
		-- a seat that is gone (a kit building with fewer seats): another free one
		local kit = P.reseat({ { Id = 1, Seat = 6 }, { Id = 2, Seat = 1 } }, { [1] = true, [2] = true }, {})
		expect(kit[1]).toEqual({ Seat = 2, Leave = false })
		expect(kit[2]).toEqual({ Seat = 1, Leave = false })
	end)

	test("a patient seated while its bay was being given keeps its seat when that bay closes", function()
		local out = P.reseat({ { Id = 1, Seat = 3, Bay = "4" } }, SEATS, { ["1"] = true })
		expect(out[1]).toEqual({ Seat = 3, Leave = false })
	end)

	test(
		"the owner leaving sends everyone home; a finished plan (or one its open game finishes) is paid first",
		function()
			local out = P.closing({
				{ Id = 1, Plan = { "CoughSyrup" }, Done = { false } }, -- waiting for its medicine
				{ Id = 2, Plan = { "Ice", "Bandage" }, Done = { true, false }, InFlight = { 2 } }, -- its last game
				{ Id = 3, Plan = { "Cast", "PainRelief" }, Done = { true, true } }, -- resting in a ward bed
				{ Id = 4, Plan = { "Plaster" }, Done = { true }, Paid = true }, -- paid, walking out
				{ Id = 5, Plan = { "Ice", "Bandage" }, Done = { false, false }, InFlight = { 1 } },
				{ Id = 6, Plan = {}, Done = {} },
			})
			expect(out).toEqual({ [1] = "Leave", [2] = "Pay", [3] = "Pay", [4] = "Leave", [5] = "Leave", [6] = "Leave" })
		end
	)
end)

T.describe("Patients.Pure: after the plan (the ward stay)", function()
	local both = { Wards = true, Rest = true }

	test("a Stay case at Lv 1 goes home; at Lv 3 a fever goes to the Rest Ward", function()
		expect(P.afterPlan(Cases.Fever, 1, both)).toBe("Home")
		expect(P.afterPlan(Cases.BrokenArm, 1, both)).toBe("Home")
		expect(P.afterPlan(Cases.Fever, 2, both)).toBe("Home") -- the Rest Ward opens at Lv 3
		expect(P.afterPlan(Cases.Fever, 3, both)).toBe("Rest")
		expect(P.afterPlan(Cases.BrokenArm, 3, both)).toBe("Wards")
		expect(P.afterPlan(Cases.Cough, 5, both)).toBe("Home")
	end)

	test("its own ward full: the other ward's bed; every bed taken: home, no penalty", function()
		expect(P.afterPlan(Cases.Fever, 3, { Wards = true })).toBe("Wards")
		expect(P.afterPlan(Cases.BrokenArm, 3, { Rest = true })).toBe("Rest")
		expect(P.afterPlan(Cases.Fever, 3, {})).toBe("Home")
		expect(P.destination(nil, both)).toBe("Home")
		expect(P.destination("Hydro", both)).toBe("Home")
	end)

	test("the ward pick: only when it goes to its own ward, from Lv 3; a Receptionist or Simple sends it", function()
		local options = Hospital.triageOptions(3, Levels)
		expect(options).toEqual({ "Wards", "Rest" })
		expect(P.routed("Rest", "Rest")).toBe(true)
		expect(P.routed("Wards", "Wards")).toBe(true)
		expect(P.routed("Rest", "Wards")).toBe(false) -- its own ward was full
		expect(P.routed("Wards", "Home")).toBe(false)
		expect(P.routed(nil, "Home")).toBe(false)
		expect(P.triageMode(nil, false, true, true)).toBe("None") -- below Lv 3
		expect(P.triageMode(options, false, true, true)).toBe("Ask")
		expect(P.triageMode(options, false, true, false)).toBe("None") -- no question, no bonus
		expect(P.triageMode(options, true, true, false)).toBe("Instant") -- a Receptionist still sends it
		expect(P.triageMode(options, true, false, true)).toBe("Instant")
		expect(P.triageMode(options, false, false, true)).toBe("None") -- a nurse or a medicine finished it
		expect(P.triageMode(options, false, true, true, true)).toBe("Instant") -- Simple: no timed decision
		expect(P.triageMode(options, false, false, true, true)).toBe("None")
		expect(P.triageMode({ "Wards" }, false, true, true)).toBe("None")
	end)

	test("right earns +10%; wrong and no pick (timeout) earn nothing (it goes the right way regardless)", function()
		expect(P.triageBonus("Rest", "Rest")).toBe(true)
		expect(P.triageBonus("Wards", "Rest")).toBe(false)
		expect(P.triageBonus("", "Rest")).toBe(false) -- no pick in Config.Triage.Seconds
		expect(P.triageBonus(nil, "Rest")).toBe(false)
		expect(P.extra({ Triage = true }, Config, MAX_EXTRA)).toBeCloseTo(1 + Config.Triage.RightBonus)
		expect(P.extra({ Triage = false }, Config, MAX_EXTRA)).toBe(1)
	end)

	test("escort: +20% cash and rest x0.5; without: nothing changes", function()
		expect(P.extra({ Escorted = true }, Config, MAX_EXTRA)).toBeCloseTo(1.2)
		expect(P.extra({ Escorted = false }, Config, MAX_EXTRA)).toBe(1)
		expect(P.rest(4, { Escorted = true }, Config)).toBeCloseTo(2)
		expect(P.rest(4, {}, Config)).toBeCloseTo(4)
	end)

	test("the hot tub is gone: a Soaked flag no longer changes the pay or the rest", function()
		expect(P.extra({ Soaked = true }, Config, MAX_EXTRA)).toBe(1)
		expect(P.rest(4, { Soaked = true }, Config)).toBeCloseTo(4)
	end)

	test("Ward Comfort (-20% rest, +5% cash a level) and the team multiply in; rest never under 0.5 s", function()
		expect(P.rest(4, { Comfort = 3 }, Config)).toBeCloseTo(1.6)
		expect(P.extra({ Comfort = 3 }, Config, MAX_EXTRA)).toBeCloseTo(1.15)
		expect(P.extra({ Team = 1.2 }, Config, MAX_EXTRA)).toBeCloseTo(1.2)
		expect(P.rest(4, { Team = 0.5 }, Config)).toBeCloseTo(2)
		expect(P.rest(4, { Escorted = true, Comfort = 3, Team = 0.5 }, Config)).toBe(0.5)
	end)

	test("junk never pays less or more than it should: Extra stays in 1..MAX_EXTRA", function()
		expect(P.extra({ Team = 0 / 0, Comfort = "3" }, Config, MAX_EXTRA)).toBe(1)
		expect(P.extra({ Team = 0.2 }, Config, MAX_EXTRA)).toBe(1) -- a team never lowers the pay
		expect(P.extra({ Team = 99, Escorted = true, Triage = true }, Config, MAX_EXTRA)).toBe(MAX_EXTRA)
		expect(P.rest(4, { Team = 7 }, Config)).toBeCloseTo(4) -- a team never slows the rest
	end)
end)

T.describe("Patients.Pure: the exam, the treat and the dispensary", function()
	test(
		"the exam card: 3 distinct unlocked tools with the right one; it glows for the first 3 exams and in Simple",
		function()
			local tools, glow = P.examCard(Cases.Cough, 1, 0, false, 0.4, Config)
			expect(#tools).toBe(3)
			expect(table.find(tools, "Stethoscope") ~= nil).toBe(true)
			expect(table.find(tools, "XRay")).toBeNil() -- the X-ray is Lv 3's
			expect(glow).toBe(true)
			local _, later = P.examCard(Cases.Cough, 1, Config.Visit.ExamsGlow, false, 0.4, Config)
			expect(later).toBe(false)
			local _, simple = P.examCard(Cases.Cough, 1, 99, true, 0.4, Config)
			expect(simple).toBe(true)
			local xray = P.examCard(Cases.BrokenArm, 3, 9, false, 0.9, Config)
			expect(table.find(xray, "XRay") ~= nil).toBe(true)
		end
	)

	test("the glow counts EXAMS (Stats.Exams), never patients treated: an old save's first exams glow too", function()
		expect(P.EXAMS_STAT).toBe("Exams")
		-- a live save from before the Real Clinic: 50 treated, never examined anyone
		local veteran = { Cured = 50, Stats = { Seeded = 1, Cures = 50 } }
		expect(P.examsDone(veteran)).toBe(0)
		local _, glow = P.examCard(Cases.Cough, 1, P.examsDone(veteran), false, 0.4, Config)
		expect(glow).toBe(true)
		expect(P.examsDone({ Cured = 0, Stats = { Exams = 3 } })).toBe(3)
		local _, over = P.examCard(Cases.Cough, 1, 3, false, 0.4, Config)
		expect(over).toBe(false)
		for _, junk in { false, {}, { Stats = "x" }, { Stats = { Exams = -2 } }, { Stats = { Exams = 0 / 0 } } } do
			expect(P.examsDone(junk)).toBe(0)
		end
		expect(P.examsDone(nil)).toBe(0)
		expect(P.examsDone({ Stats = { Exams = 2.9 } })).toBe(2)
	end)

	test("plan: the helper's own items first, then the nurse tray; each fills one slot", function()
		local carry, tray = P.plan({ "Ice", "Bandage" }, { false, false }, { "Bandage" }, { "Ice", "Bandage" })
		expect(carry).toEqual({ 2 })
		expect(tray).toEqual({ 1 })
		local none = P.plan({ "Cast", "PainRelief" }, { false, false }, { "Plaster" }, {})
		expect(none).toEqual({})
	end)

	test("split: medicines are handed over at once, supplies play their game", function()
		local plan = { "Cast", "PainRelief", "Bandage" }
		local medicines, supplies = P.split(plan, { 3, 2, 1 })
		expect(medicines).toEqual({ 2 })
		expect(supplies).toEqual({ 1, 3 })
		expect(P.itemsAt(plan, supplies)).toEqual({ "Cast", "Bandage" })
		local m2, s2 = P.split({ "CoughSyrup" }, { 1 })
		expect(m2).toEqual({ 1 })
		expect(s2).toEqual({})
	end)

	test("the dispensary's options: medicine steps still needed, oldest first, distinct, at most 3", function()
		local rows = {
			{ Needs = { "Bandage", "PainRelief" } },
			{ Needs = {} },
			{ Needs = { "CoughSyrup", "PainRelief" } },
			{ Needs = { "EarDrops", "Lozenges" } },
		}
		expect(P.medicines(rows, 3)).toEqual({ "PainRelief", "CoughSyrup", "EarDrops" })
		expect(P.medicines(rows, 1)).toEqual({ "PainRelief" })
		expect(P.medicines({}, 3)).toEqual({})
	end)

	test("the symptom bubble splits into its emoji and its words", function()
		local emote, words = P.bubbleParts(Cases.Cough.Bubble)
		expect(emote).toBe("😷")
		expect(words).toBe("cough cough")
		expect(select(1, P.bubbleParts("🤒"))).toBe("🤒")
		expect(select(2, P.bubbleParts("🤒"))).toBe("")
		expect(select(1, P.bubbleParts(nil))).toBe("")
	end)
end)

T.describe("Patients.Pure: urgent (🚑 A&E, 🚁 air ambulance)", function()
	local lv1 = P.makes(clinic(1).Stations)
	local lv5 = P.makes(clinic(5).Stations)

	test("the urgent plan: at least MinItems steps, a one-step plan padded with an ice pack", function()
		expect(P.urgentFor({ "CoughSyrup" }, lv1, 1, Config.AE.MinItems)).toEqual({ "CoughSyrup", "Ice" })
		expect(P.urgentFor({ "Ice" }, lv1, 2, Config.AE.MinItems)).toEqual({ "Ice", "Plaster" })
		expect(P.urgentFor({ "Ice", "Bandage" }, lv5, 2, Config.AE.MinItems)).toEqual({ "Ice", "Bandage" })
		expect(P.urgentFor(Cases.BrokenLeg.Plan, lv5, 3, Config.AE.MinItems)).toEqual({
			"Cast",
			"PainRelief",
			"Bandage",
		})
	end)

	test("a step no station here makes is left out; its first step must stay", function()
		expect(P.urgentFor({ "Bubbles", "PainRelief" }, lv1, 2, Config.AE.MinItems)).toBe(nil)
		expect(P.urgentFor({ "CoughSyrup", "Cocoa" }, lv1, 2, Config.AE.MinItems)).toEqual({ "CoughSyrup", "Ice" })
		expect(P.urgentFor({ "Cast" }, {}, 2, Config.AE.MinItems)).toBe(nil)
	end)

	test("every urgent plan at any clinic can be made there", function()
		for level = 2, 5 do
			local view = clinic(level, { BathRoom = true, WinterWing = true })
			local made = P.makes(view.Stations)
			for _, caseId in Cases.ORDER do
				if P.eligible(Cases[caseId], view) then
					local plan = P.urgentFor(Cases[caseId].Plan, made, Levels[level].RecipeCap, Config.AE.MinItems)
					expect(plan ~= nil).toBe(true)
					expect(#plan >= Config.AE.MinItems).toBe(true)
					expect(Recipe.makeable(plan, made)).toBe(true)
				end
			end
		end
	end)

	test("patience: x0.6 (x1.15 a level of A&E Speed for 🚑); it drains slower with the team and a Medic", function()
		expect(P.urgentPatience(60, "AE", 0, Config)).toBeCloseTo(36)
		expect(P.urgentPatience(60, "AE", 2, Config)).toBeCloseTo(36 * 1.3)
		expect(P.urgentPatience(60, "VIP", 2, Config)).toBeCloseTo(36)
		expect(P.urgentPatience(0 / 0, "AE", 0, Config) >= 1).toBe(true)
		expect(P.slower(1, 1, 4)).toBe(1)
		expect(P.slower(1.25, 1.2, 4)).toBeCloseTo(1.5)
		expect(P.slower(0.5, "x", 4)).toBe(1) -- junk and "faster" both count as normal
		expect(P.slower(3, 3, 4)).toBe(4)
	end)

	test(
		"timers: ambulances every 150 s +-20%, sooner with A&E Speed and Siren Pro; helicopters every 300 s",
		function()
			expect(P.aeSeconds(Config, 0.5, 0, 1)).toBeCloseTo(150)
			expect(P.aeSeconds(Config, 0, 0, 1)).toBeCloseTo(120)
			expect(P.aeSeconds(Config, 1, 0, 1)).toBeCloseTo(180)
			expect(P.aeSeconds(Config, 0.5, 3, 1)).toBeCloseTo(150 * 0.7)
			expect(P.aeSeconds(Config, 0.5, 0, 1.25)).toBeCloseTo(120)
			expect(P.aeSeconds(Config, 0.5, 99, 99) >= 1).toBe(true)
			expect(P.vipSeconds(Config, 0.5)).toBeCloseTo(300)
			expect(P.vipSeconds(Config, 0)).toBeCloseTo(240)
		end
	)

	test("the waiting room still holds at most Config.MaxQueue (3) at every level", function()
		expect(Config.MaxQueue).toBe(3)
		for _, row in Levels do
			expect(row.Queue <= Config.MaxQueue).toBe(true)
		end
	end)
end)

T.describe("Patients.Pure: variants and wings", function()
	local goldenAt = 3 -- Data/Variants.Golden.Rebirths

	test("🌟 Golden only from R3, at Config.GoldenChance (or always with the Studio switch)", function()
		expect(P.variant(3, { 0.01, 0.99, 0.99 }, false, false, Config, goldenAt)).toBe("Golden")
		expect(P.variant(2, { 0.01, 0.99, 0.99 }, false, false, Config, goldenAt)).toBe(nil)
		expect(P.variant(3, { 0.5, 0.99, 0.99 }, false, false, Config, goldenAt)).toBe(nil)
		expect(P.variant(3, { 0.99, 0.99, 0.99 }, false, true, Config, goldenAt)).toBe("Golden")
		expect(P.variant(2, { 0.99, 0.99, 0.99 }, false, true, Config, goldenAt)).toBe(nil) -- the switch: R3+ only
	end)

	test("Sparkly and (in winter only) Frosty as before", function()
		expect(P.variant(0, { 0.99, 0.01, 0.99 }, false, false, Config, goldenAt)).toBe("Sparkly")
		expect(P.variant(0, { 0.99, 0.99, 0.01 }, false, false, Config, goldenAt)).toBe(nil)
		expect(P.variant(0, { 0.99, 0.99, 0.01 }, true, false, Config, goldenAt)).toBe("Frosty")
	end)

	test("🌻 Sunny comes from R1; 🚁 Sky only by air ambulance; the helicopter brings only Sky", function()
		expect(P.wingOpen(Wings.Starter, 0, false)).toBe(true)
		expect(P.wingOpen(Wings.Sunny, 0, false)).toBe(false)
		expect(P.wingOpen(Wings.Sunny, 1, false)).toBe(true)
		expect(P.wingOpen(Wings.Sky, 9, false)).toBe(false)
		expect(P.wingOpen(Wings.Sky, 0, true)).toBe(true) -- (the helicopter itself flies from R2)
		expect(P.wingOpen(Wings.Starter, 5, true)).toBe(false)
	end)
end)
