--!nocheck
-- The Nurses server's pure helpers (depth update T3; Progression v2 T1; the Real Clinic, Task 6): the four files
-- compile, and the PURE-BEGIN..PURE-END blocks of Server/Nurses and Server/NurseBelt, loaded on their own (the rest
-- needs Roblox), are tested against the real Logic/Belt, Logic/Nurse, Logic/Jobs, Logic/Visit, Logic/Building,
-- Data/Items, Data/Nurses and Data/Rarities. The Progression v2 nurse work (jobs, XP, teams, grant/take/give,
-- abilities) is tests/NurseWork.spec. Run from game/:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local ROOT = "src/server/"
local BeltLogic = require("../src/shared/Logic/Belt")
local BuildingLogic = require("../src/shared/Logic/Building")
local JobsLogic = require("../src/shared/Logic/Jobs")
local NurseLogic = require("../src/shared/Logic/Nurse")
local VisitLogic = require("../src/shared/Logic/Visit")
local DeptData = require("../src/shared/Data/Departments")
local ItemsData = require("../src/shared/Data/Items")
local JobsData = require("../src/shared/Data/Jobs")
local NursesData = require("../src/shared/Data/Nurses")
local Rarities = require("../src/shared/Data/Rarities")

local function source(path: string): string
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("can't find " .. path .. " (run from game/)")
end

local function pureBlock(name: string, env: { [string]: any }): any
	local text = source(ROOT .. name)
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to, name .. ": no PURE block")
	local block = string.sub(text, from, to - 1) .. "\nreturn Pure\n"
	local chunk = luau.load(block, { debugName = name .. ":Pure", environment = env, injectGlobals = true })
	return chunk()
end

-- The real Config's belt numbers (tests/config.luau loads Shared/Config with a Vector3 stub), so these rules run on
-- what ships.
local Config = require("./config")
local CFG = { Belt = Config.Belt, Nurses = { MaxLevel = Config.Nurses.MaxLevel } }

T.describe("compile", function()
	for _, name in { "Nurses.luau", "NurseBelt.luau", "NurseBuilder.luau", "Abilities.luau" } do
		test(name, function()
			local ok, err = pcall(luau.compile, source(ROOT .. name))
			expect(ok).toBe(true)
			if not ok then
				error(err)
			end
		end)
	end
end)

local NP = pureBlock("Nurses.luau", {
	NurseLogic = NurseLogic,
	JobsLogic = JobsLogic,
	VisitLogic = VisitLogic,
	BuildingLogic = BuildingLogic,
})
local BP = pureBlock("NurseBelt.luau", { BeltLogic = BeltLogic })

-- A bay patient as Patients.bayView reports one (contract C6).
local function bayRow(bay: string, id: number, stage: string, needs: { string }, since: number)
	return { Bay = bay, PatientId = id, Stage = stage, Needs = needs, Since = since }
end

T.describe("Nurses.Pure", function()
	test("without is a multiset difference, order kept", function()
		expect(NP.without({ "Ice", "Plaster", "Ice", "Cocoa" }, { "Ice", "Cocoa" })).toEqual({
			"Plaster",
			"Ice",
		})
		expect(NP.without({ "Ice" }, {})).toEqual({ "Ice" })
		expect(NP.without({}, { "Ice" })).toEqual({})
	end)

	test("spare finds the oldest item the bay patients don't need", function()
		expect(NP.spare({ "Cocoa", "Ice" }, { "Ice" })).toBe(1)
		expect(NP.spare({ "Ice", "Ice" }, { "Ice" })).toBe(2)
		expect(NP.spare({ "Ice", "Plaster" }, { "Plaster", "Ice" })).toBeNil()
		expect(NP.spare({}, {})).toBeNil()
	end)

	test("trayAdd appends while there's room", function()
		local tray, added = NP.trayAdd({ "Ice" }, "Plaster", 4, {})
		expect(added).toBe(true)
		expect(tray).toEqual({ "Ice", "Plaster" })
	end)

	test("trayAdd on a full tray swaps the oldest unneeded item", function()
		local tray, added = NP.trayAdd({ "Cocoa", "Ice", "Ice", "Plaster" }, "Bubbles", 4, { "Ice", "Plaster" })
		expect(added).toBe(true)
		expect(tray).toEqual({ "Ice", "Ice", "Plaster", "Bubbles" })
	end)

	test("trayAdd refuses a tray full of needed items, and never grows past max", function()
		local full = { "Ice", "Plaster", "Ice", "Cocoa" }
		local tray, added = NP.trayAdd(full, "Bubbles", 4, { "Ice", "Plaster", "Ice", "Cocoa" })
		expect(added).toBe(false)
		expect(tray).toEqual(full)
		expect(#full).toBe(4) -- the input isn't changed
	end)

	test("trayTake removes the oldest copy only", function()
		local tray, taken = NP.trayTake({ "Ice", "Plaster", "Ice" }, "Ice")
		expect(taken).toBe(true)
		expect(tray).toEqual({ "Plaster", "Ice" })
		local same, none = NP.trayTake({ "Plaster" }, "Cocoa")
		expect(none).toBe(false)
		expect(same).toEqual({ "Plaster" })
	end)

	test("pickMake: the first needed supply not covered, that the plot can make", function()
		local can = { Ice = true, Plaster = true }
		expect(NP.pickMake({ "Bubbles", "Ice", "Plaster" }, {}, can, {}, 4, ItemsData)).toBe("Ice")
		-- the tray already holds an Ice pack: the next one is the Plaster
		expect(NP.pickMake({ "Ice", "Plaster" }, { "Ice" }, can, { "Ice" }, 4, ItemsData)).toBe("Plaster")
		-- two Ice packs needed, one in the tray: make the second
		expect(NP.pickMake({ "Ice", "Ice" }, { "Ice" }, can, { "Ice" }, 4, ItemsData)).toBe("Ice")
		-- everything covered (tray, another Maker, the owner's carry)
		expect(NP.pickMake({ "Ice", "Plaster" }, { "Ice", "Plaster" }, can, {}, 4, ItemsData)).toBeNil()
		-- nothing needed
		expect(NP.pickMake({}, {}, can, {}, 4, ItemsData)).toBeNil()
		-- needed, but no station makes it here
		expect(NP.pickMake({ "Cocoa" }, {}, can, {}, 4, ItemsData)).toBeNil()
	end)

	test("pickMake waits when the tray is full of needed items", function()
		local can = { Ice = true, Plaster = true }
		local tray = { "Ice", "Ice", "Plaster", "Plaster" }
		local needs = { "Ice", "Ice", "Plaster", "Plaster", "Ice" }
		expect(NP.pickMake(needs, tray, can, tray, 4, ItemsData)).toBeNil()
		-- one tray item is spare: it can make (the deposit swaps the spare out)
		local spareTray = { "Cocoa", "Ice", "Plaster", "Plaster" }
		expect(NP.pickMake({ "Ice", "Plaster", "Plaster", "Ice" }, spareTray, can, spareTray, 4, ItemsData)).toBe("Ice")
	end)

	test("pickMake never returns a medicine or the dispensary, whatever it is told it can make", function()
		local can = { Remedy = true, Plaster = true }
		for _, id in ItemsData.Order do
			can[id] = true
		end
		expect(NP.pickMake({ "CoughSyrup", "Remedy", "PainRelief" }, {}, can, {}, 4, ItemsData)).toBeNil()
		expect(NP.pickMake({ "CoughSyrup", "Remedy", "Plaster" }, {}, can, {}, 4, ItemsData)).toBe("Plaster")
		for _, id in ItemsData.Order do
			local made = NP.pickMake({ id }, {}, { [id] = true }, {}, 4, ItemsData)
			if ItemsData[id].Kind == "Medicine" then
				expect(made).toBeNil()
			else
				expect(made).toBe(id)
			end
		end
		expect(NP.pickMake({ "Remedy" }, {}, { Remedy = true }, {}, 4, ItemsData)).toBeNil()
		-- no Items: nothing is a supply
		expect(NP.pickMake({ "Plaster" }, {}, { Plaster = true }, {}, 4, nil)).toBeNil()
	end)

	test("a Maker's stations: every supply's, never the dispensary; each makes only its supplies", function()
		expect(NP.supplyStations(ItemsData)).toEqual({ "Plaster", "Ice", "Bandage", "Cast", "Bath", "Cocoa" })
		expect(NP.makeable(ItemsData, "Remedy")).toEqual({})
		expect(NP.makeable(ItemsData, "Bath")).toEqual({ "Bubbles" })
		expect(NP.makeable(ItemsData, "Cocoa")).toEqual({ "Cocoa" })
		expect(NP.makeable(ItemsData, "Nope")).toEqual({})
		for _, id in ItemsData.Order do
			local item = ItemsData[id]
			expect(NP.isSupply(ItemsData, id)).toBe(item.Kind == "Supply" and item.Station ~= "Remedy")
		end
		expect(NP.isSupply(ItemsData, "Order")).toBe(false)
		expect(NP.isSupply(ItemsData, "Remedy")).toBe(false)
	end)

	test("rows: bay patients front first, junk dropped, each Model's State, Urgent and patience", function()
		local rows = NP.rows({
			bayRow("2", 7, "Treat", { "Plaster", 5, "CoughSyrup" }, 30),
			bayRow("1", 4, "Exam", {}, 10),
			bayRow("X", 9, "Treat", { "Cast" }, 10),
			{ Bay = "3", PatientId = "nine", Stage = "Exam", Since = 1 }, -- junk id
			bayRow("4", 5, "Nope", {}, 1), -- junk stage
			"junk",
		}, {
			["1"] = { State = "AtBay", Urgent = "", Patience = 0.4 },
			["2"] = { State = "Treating", Urgent = "AE", Patience = 0.9 },
			["X"] = { State = "Planned", Urgent = "VIP" },
		})
		expect(#rows).toBe(3)
		expect(rows[1].PatientId).toBe(4) -- Since 10, the lower id first
		expect(rows[2].PatientId).toBe(9)
		expect(rows[3].PatientId).toBe(7)
		expect(rows[1].NeedsDoctor).toBe(true) -- its exam
		expect(rows[1].Patience).toBe(0.4)
		expect(rows[2].Urgent).toBe("VIP")
		expect(rows[2].Patience).toBe(1) -- unknown: full
		expect(rows[3].Needs).toEqual({ "Plaster", "CoughSyrup" })
		expect(rows[3].Busy).toBe(true) -- mid mini-game: nobody else helps it now
		expect(rows[3].NeedsDoctor).toBe(false)
		expect(NP.rows(nil, nil)).toEqual({})
		expect(NP.lineNeeds(rows)).toEqual({ "Cast", "Plaster", "CoughSyrup" })
	end)

	test("the front is the bay patient who has waited longest for the doctor (Logic/Visit.front)", function()
		local rows = NP.rows({
			bayRow("1", 1, "Treat", {}, 1), -- its plan is done (leaving): not waiting
			bayRow("2", 2, "Exam", {}, 5),
			bayRow("3", 3, "Treat", { "Ice" }, 8),
		}, { ["2"] = { State = "Examining" } }) -- 2 is in its exam right now
		expect(NP.front(rows).PatientId).toBe(3)
		expect(NP.front({})).toBeNil()
	end)

	test("canHeal: a nurse may examine, or hand over a supply the tray holds; never a medicine", function()
		local exam = NP.rows({ bayRow("1", 1, "Exam", {}, 1) }, {})[1]
		expect(NP.canHeal(exam, {}, ItemsData)).toBe(true)
		local plaster = NP.rows({ bayRow("1", 1, "Treat", { "CoughSyrup", "Plaster" }, 1) }, {})[1]
		expect(NP.canHeal(plaster, { "Plaster" }, ItemsData)).toBe(true)
		expect(NP.canHeal(plaster, { "Ice" }, ItemsData)).toBe(false)
		expect(NP.canHeal(plaster, {}, ItemsData)).toBe(false)
		-- only a medicine to go: even a tray holding it (it never does) gives nothing
		local syrup = NP.rows({ bayRow("1", 1, "Treat", { "CoughSyrup" }, 1) }, {})[1]
		expect(NP.canHeal(syrup, { "CoughSyrup", "Plaster" }, ItemsData)).toBe(false)
		local busy = NP.rows({ bayRow("1", 1, "Exam", {}, 1) }, { ["1"] = { State = "Examining" } })[1]
		expect(NP.canHeal(busy, {}, ItemsData)).toBe(false)
		expect(NP.canHeal(nil, { "Plaster" }, ItemsData)).toBe(false)
	end)

	test("a Healer facing a patient whose only missing step is a medicine does nothing", function()
		local rows = NP.rows({
			bayRow("1", 1, "Treat", { "CoughSyrup" }, 1), -- the front: waits for the player's dispensing
			bayRow("2", 2, "Exam", {}, 5),
			bayRow("3", 3, "Treat", { "Plaster" }, 6),
		}, {})
		expect(NP.front(rows).PatientId).toBe(1)
		expect(NP.healerTarget(rows, { "Plaster", "Ice", "Ice", "Bandage" }, ItemsData)).toBeNil()
		-- 👯 Twin Counters: Patients' delivery serves the next one too, so the Healer goes to it (never a third)
		expect(NP.healerTarget(rows, {}, ItemsData, true).PatientId).toBe(2)
		local busy = NP.rows(
			{ bayRow("1", 1, "Treat", { "CoughSyrup" }, 1), bayRow("2", 2, "Treat", { "Ice" }, 2) },
			{}
		)
		expect(NP.healerTarget(busy, { "Plaster" }, ItemsData, true)).toBeNil()
		expect(#busy).toBe(2) -- the rows passed in are never changed
		-- once the player hands the syrup over, the next front gets its exam from the Healer
		rows = NP.rows({ bayRow("2", 2, "Exam", {}, 5), bayRow("3", 3, "Treat", { "Plaster" }, 6) }, {})
		expect(NP.healerTarget(rows, {}, ItemsData).PatientId).toBe(2)
	end)

	test(
		"a Medic goes to the 🚑/🚁 bay patient who waited longest; it helps only with an exam or a supply",
		function()
			local rows = NP.rows({
				bayRow("1", 1, "Exam", {}, 1),
				bayRow("2", 2, "Treat", { "PainRelief" }, 2),
				bayRow("3", 3, "Treat", { "Ice", "Bandage" }, 3),
			}, { ["2"] = { Urgent = "AE" }, ["3"] = { Urgent = "AE" } })
			local urgent = NP.urgentRow(rows)
			expect(urgent.PatientId).toBe(2)
			expect(NP.canHeal(urgent, { "Ice" }, ItemsData)).toBe(false) -- pain relief is the player's to dispense
			expect(NP.urgentRow(NP.rows({ bayRow("1", 1, "Exam", {}, 1) }, {}))).toBeNil()
		end
	)

	test("moved: the patient a nurse helped got its exam or a step", function()
		local before = NP.rows({ bayRow("1", 1, "Exam", {}, 1) }, {})[1]
		expect(NP.moved(before, NP.rows({ bayRow("1", 1, "Treat", { "Ice" }, 1) }, {})[1])).toBe(true)
		expect(NP.moved(before, before)).toBe(false)
		expect(NP.moved(before, nil)).toBe(false)
		local two = NP.rows({ bayRow("1", 1, "Treat", { "Ice", "CoughSyrup" }, 1) }, {})[1]
		expect(NP.moved(two, NP.rows({ bayRow("1", 1, "Treat", { "CoughSyrup" }, 1) }, {})[1])).toBe(true)
	end)

	test("any: the waiting and arriving patient States", function()
		expect(NP.any({ "Recovering", "AtBay" }, NP.WAITING)).toBe(true)
		expect(NP.any({ "Recovering", "Treating", nil, 5 }, NP.WAITING)).toBe(false)
		expect(NP.any({ "Arriving" }, NP.ARRIVING)).toBe(true)
		expect(NP.any({}, NP.ARRIVING)).toBe(false)
	end)

	test("Hydro and Pharmacy specialists keep their bonus: the Bath Room, and the supply shelf", function()
		local stations = DeptData.Stations
		-- a Pharmacy specialist Maker at the supply shelf (and the Cocoa Corner), a Hydro one at the Bath
		for _, stationId in { "Plaster", "Ice", "Bandage", "Cocoa" } do
			expect(NP.specialty("Maker", "Pharmacy", stationId, JobsData, stations)).toBe(true)
			expect(NP.specialty("Maker", "Hydro", stationId, JobsData, stations)).toBe(false)
		end
		expect(NP.specialty("Maker", "Hydro", "Bath", JobsData, stations)).toBe(true)
		expect(NP.specialty("Maker", "Pharmacy", "Bath", JobsData, stations)).toBe(false)
		expect(NP.specialty("Maker", "Any", "Cast", JobsData, stations)).toBe(true)
		-- a Healer works in Reception (Data/Jobs), wherever the patient is
		expect(NP.specialty("Healer", "Pharmacy", "Plaster", JobsData, stations)).toBe(false)
		-- and the bonus really is faster (+40%)
		local plain = NurseLogic.stats("Maker", "Common", 1, { Nurses = { MakerSeconds = { Common = 14 } } }, false)
		local cfg = { Nurses = { MakerSeconds = { Common = 14 }, SpecialtyBoost = 0.4 } }
		local boosted = NurseLogic.stats("Maker", "Common", 1, cfg, true)
		expect(boosted.Every < plain.Every).toBe(true)
		-- every supply's station has a department, so every Maker trip can be a specialist's
		for _, stationId in NP.supplyStations(ItemsData) do
			expect(type(rawget(DeptData, stations[stationId]))).toBe("table")
		end
	end)

	test("Equipped is gone: no onDuty helper is left to drift from Logic/Nurse.working", function()
		expect(NP.onDuty).toBeNil()
		expect(NP.sameList).toBeNil()
	end)

	test("level: clamped 1..max, junk -> 1", function()
		expect(NP.level({ Level = 3, Copies = 3 }, 5)).toBe(3)
		expect(NP.level({ Level = 9 }, 5)).toBe(5)
		expect(NP.level({ Level = 0 }, 5)).toBe(1)
		expect(NP.level({ Level = 0 / 0 }, 5)).toBe(1)
		expect(NP.level(nil, 5)).toBe(1)
		expect(NP.level({ Level = 2.7 }, 5)).toBe(2)
	end)

	test("cash: thousands commas", function()
		expect(NP.cash(0)).toBe("0")
		expect(NP.cash(100)).toBe("100")
		expect(NP.cash(1500)).toBe("1,500")
		expect(NP.cash(12345)).toBe("12,345")
		expect(NP.cash(100000)).toBe("100,000")
		expect(NP.cash(1234567)).toBe("1,234,567")
		expect(NP.cash(-1500)).toBe("-1,500")
	end)
end)

T.describe("Nurses.Pure: where nurses stand and walk (Logic/Building)", function()
	local B = BuildingLogic
	local JOBS = { "Maker", "Healer", "Cheerer", "Receptionist", "Medic", "Porter" }
	local ROSTER = 8 -- Config.Roster.Max: every nurse could have one job

	-- A nurse's footprint at a spot is clear of everything solid on the ground floor.
	local function clearAt(spot, level: number): boolean
		return B.clear({ X0 = spot.X - 0.8, X1 = spot.X + 0.8, Z0 = spot.Z - 0.8, Z1 = spot.Z + 0.8 }, level)
	end

	local function inside(spot, rect, margin: number): boolean
		return spot.X >= rect.X0 + margin
			and spot.X <= rect.X1 - margin
			and spot.Z >= rect.Z0 + margin
			and spot.Z <= rect.Z1 - margin
	end

	test("every job's home, for a full roster, is clear at every level; inside the clinic but the Medic's", function()
		local footprint = B.footprint(1, 0)
		for _, job in JOBS do
			for k = 1, ROSTER do
				local spot = NP.home(job, k)
				expect(spot.Face % 90).toBe(0)
				for level = B.MIN_LEVEL, B.MAX_LEVEL do
					if not clearAt(spot, level) then
						error(job .. " " .. k .. " stands in something at Lv " .. level)
					end
				end
				if job == "Medic" then
					-- the A&E yard: outside the -x wall, off the walk from the StretcherSpot to the side door
					expect(spot.X < footprint.X0).toBe(true)
					expect(math.abs(spot.Z - B.BAY_AMBULANCE.Stretcher.Z) >= 2.5).toBe(true)
				else
					expect(inside(spot, footprint, B.WALL + 0.8)).toBe(true)
				end
			end
		end
		-- two nurses of a job never share a spot
		for _, job in JOBS do
			local seen = {}
			for k = 1, ROSTER do
				local spot = NP.home(job, k)
				local key = string.format("%.1f,%.1f", spot.X, spot.Z)
				expect(seen[key]).toBeNil()
				seen[key] = true
			end
		end
	end)

	test("beside every bay: clear, facing the bed, and the walk from the Healers' corridor reaches it", function()
		for _, bay in B.BAYS do
			local rooms = if bay.Room then { [bay.Room] = true } else nil
			for level = bay.Opens, B.MAX_LEVEL do
				if B.bayOpen(bay, level, rooms) then
					for index = 1, 2 do
						local spot = NP.bedside(bay, index, level)
						if not clearAt(spot, level) then
							error("beside bay " .. bay.Id .. " (" .. index .. ") is blocked at Lv " .. level)
						end
						-- facing the bed: from its foot, or bay X's from its side (the doctor's spot is there)
						expect(spot.Face).toBe(if bay.Spot then 180 else (bay.Face + 180) % 360)
						-- the player's own spot (the DoctorSpot) stays free
						local doctor = B.doctorSpot(bay)
						expect(math.abs(spot.X - doctor.X) + math.abs(spot.Z - doctor.Z) > 1).toBe(true)
						local home = NP.home("Healer", index)
						if not B.path({ X = home.X, Z = home.Z }, { X = spot.X, Z = spot.Z }, level, 0) then
							error("no walk to bay " .. bay.Id .. " at Lv " .. level)
						end
						if level >= 2 then -- the Medic's job opens with the A&E side door
							local yard = NP.home("Medic", index)
							if not B.path({ X = yard.X, Z = yard.Z }, { X = spot.X, Z = spot.Z }, level, 0) then
								error("no walk from the A&E yard to bay " .. bay.Id .. " at Lv " .. level)
							end
						end
					end
				end
			end
		end
	end)

	test("a Maker's spot at each Building station is clear and reachable from the corridor once it opens", function()
		for _, stationId in NP.supplyStations(ItemsData) do
			if B.STATIONS[stationId] then
				for level = B.STATIONS[stationId].Opens, B.MAX_LEVEL do
					for index = 1, 2 do
						local spot = NP.stationSpot(stationId, index)
						if not clearAt(spot, level) then
							error(stationId .. " (" .. index .. ") is blocked at Lv " .. level)
						end
						local home = NP.home("Maker", index)
						if not B.path({ X = home.X, Z = home.Z }, { X = spot.X, Z = spot.Z }, level, 0) then
							error("no walk to " .. stationId .. " at Lv " .. level)
						end
					end
				end
			else
				expect(NP.stationSpot(stationId, 1)).toBeNil() -- a bought room's: its part says where
			end
		end
		expect(NP.stationSpot("Remedy", 1) ~= nil).toBe(true) -- a Building station, but no Maker ever goes there
		expect(table.find(NP.supplyStations(ItemsData), "Remedy")).toBeNil()
	end)

	test("pathKey: both ends to the half stud and the level", function()
		expect(NP.pathKey(1.24, -2, 3, 4.76, 2)).toBe(NP.pathKey(1.1, -2.2, 3.2, 4.9, 2))
		expect(NP.pathKey(1, 1, 3, 3, 2) ~= NP.pathKey(1, 1, 3, 3, 3)).toBe(true)
		expect(NP.pathKey(1, 1, 3, 3, 2) ~= NP.pathKey(3, 3, 1, 1, 2)).toBe(true)
	end)
end)

T.describe("NurseBelt.Pure", function()
	test("rarities match Data/Rarities and Logic/Belt", function()
		expect(BP.RARITIES).toEqual(Rarities.Order)
		expect(BP.RARITIES).toEqual(BeltLogic.RARITIES)
	end)

	test("percent formats every odd the sign prints", function()
		expect(BP.percent(70)).toBe("70%")
		expect(BP.percent(39.5)).toBe("39.5%")
		expect(BP.percent(38.5)).toBe("38.5%")
		expect(BP.percent(0.5)).toBe("0.5%")
		expect(BP.percent(1)).toBe("1%")
		expect(BP.percent(0)).toBe("–")
		expect(BP.percent(0 / 0)).toBe("–")
		-- every odd in every state formats without long decimals
		for _, night in { false, true } do
			for _, golden in { false, true } do
				for rarity, value in BeltLogic.odds(CFG, night, golden) do
					local text = BP.percent(value)
					expect(#text <= 6).toBe(true)
					if value > 0 then
						expect(tonumber(string.sub(text, 1, -2))).toBeCloseTo(value, 1)
					end
					local _ = rarity
				end
			end
		end
	end)

	test("status line, 6 words or fewer", function()
		expect(BP.status(false, false, 2)).toBe("☀️ Day odds")
		expect(BP.status(true, false, 2)).toBe("🌙 Night Rush! Rare+ ×2")
		expect(BP.status(false, true, 2)).toBe("👑 Golden Hour!")
		expect(BP.status(true, true, 2)).toBe("👑 Golden Night Rush!")
	end)

	test("afterHire: a Common or Rare hire that empties the belt brings the next in ReplaceSeconds", function()
		local soon = 100 + CFG.Belt.ReplaceSeconds
		expect(BP.afterHire(140, 100, "Common", CFG, 0)).toBe(soon)
		expect(BP.afterHire(140, 100, "Rare", CFG, 0)).toBe(soon)
		expect(BP.afterHire(140, 100, "Epic", CFG, 0)).toBe(140) -- an Epic+ is never replaced early
		expect(BP.afterHire(101, 100, "Common", CFG, 0)).toBe(101) -- never later than it was due
	end)

	test("afterHire: while other nurses still ride, the belt keeps its 40 s cadence", function()
		expect(BP.afterHire(140, 100, "Common", CFG, 1)).toBe(140)
		expect(BP.afterHire(140, 100, "Rare", CFG, 2)).toBe(140)
	end)

	test("gateText: the sign says who may hire Epic and up, and Mythic/Secret from R1", function()
		expect(BP.gateText(CFG)).toBe("🏥 Epic+ from Lv 3 · 🏢 Mythic/Secret from R1")
		for _, line in BP.gateLines(CFG) do
			local words = 0
			for _ in string.gmatch(line, "%S+") do
				words += 1
			end
			expect(words <= 6).toBe(true)
		end
	end)

	test("hiredShout: Legendary and up", function()
		expect(BP.hiredShout("Common")).toBe(false)
		expect(BP.hiredShout("Epic")).toBe(false)
		expect(BP.hiredShout("Legendary")).toBe(true)
		expect(BP.hiredShout("Mythic")).toBe(true)
		expect(BP.hiredShout("Secret")).toBe(true)
		expect(BP.hiredShout("Junk")).toBe(false)
	end)

	test("golden: the natural window, or a forced one", function()
		local active, s, e = BP.golden(CFG, 1210, nil)
		expect(active).toBe(true)
		expect(s).toBe(1200)
		expect(e).toBe(1320)
		active, s, e = BP.golden(CFG, 50, nil)
		expect(active).toBe(false)
		expect(s).toBe(1200)
		-- forced at uptime 50: on for GoldenSeconds, then the natural schedule again
		active, s, e = BP.golden(CFG, 60, 50)
		expect(active).toBe(true)
		expect(s).toBe(50)
		expect(e).toBe(170)
		active = BP.golden(CFG, 171, 50)
		expect(active).toBe(false)
	end)

	test("forced: Studio BeltForce, but the pity still wins over a Common", function()
		expect(BP.forced("Mythic", false)).toBe("Mythic")
		expect(BP.forced("Common", false)).toBe("Common")
		expect(BP.forced("Common", true)).toBeNil()
		expect(BP.forced("Rare", true)).toBe("Rare")
		expect(BP.forced("Junk", false)).toBeNil()
		expect(BP.forced(5, false)).toBeNil()
		expect(BP.forced(nil, false)).toBeNil()
	end)

	test("15 forced Commons, then the pity gives a Rare+", function()
		local dry = 0
		local rolled = {}
		local pityAt = CFG.Belt.PityArrivals + 1
		expect(pityAt).toBe(16)
		for _ = 1, pityAt do
			local pity = BeltLogic.pityDue(dry, CFG)
			local rarity = BP.forced("Common", pity) or BeltLogic.roll(BeltLogic.odds(CFG, false, false), 0, pity)
			table.insert(rolled, rarity)
			dry = BeltLogic.afterArrival(dry, rarity)
		end
		for i = 1, pityAt - 1 do
			expect(rolled[i]).toBe("Common")
		end
		expect(BeltLogic.isRarePlus(rolled[pityAt])).toBe(true)
	end)

	test("event: which odds rolled it", function()
		expect(BP.event(false, false)).toBe("")
		expect(BP.event(true, false)).toBe("NightRush")
		expect(BP.event(false, true)).toBe("GoldenHour")
		expect(BP.event(true, true)).toBe("GoldenHour")
	end)
end)

T.describe("contract numbers the T3 code relies on", function()
	test("every rarity has a nurse to pick", function()
		for _, rarity in Rarities.Order do
			expect(BeltLogic.pick(NursesData, rarity, 0.5) ~= nil).toBe(true)
		end
	end)

	test("the journal: hiring every Common makes exactly the Common set due", function()
		local index = {}
		for _, id in NursesData.Order do
			if NursesData[id].Rarity == "Common" then
				NurseLogic.mark(index, id, "Hired")
			end
		end
		expect(NurseLogic.setsDue(index, NursesData, Rarities, {})).toEqual({ "Common" })
		expect(NurseLogic.setsDue(index, NursesData, Rarities, { Common = true })).toEqual({})
	end)

	test("every journal reward decor is a real Decor id (source check)", function()
		local decor = source("src/shared/Data/Decor.luau")
		for _, rarity in Rarities.Order do
			local id = Rarities[rarity].Journal.Decor
			expect(string.find(decor, "\n\t" .. id .. " = {", 1, true) ~= nil).toBe(true)
		end
	end)
end)
