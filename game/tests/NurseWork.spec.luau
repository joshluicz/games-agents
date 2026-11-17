--!nocheck
-- Progression v2 nurse work (T1, build plan §C T1 and Review focus 1): the PURE blocks of Server/Nurses and
-- Server/Abilities against the real Logic and Data (working/rest picking, team counts, the usefulness views, the
-- ability state machine), and the real src/server/Nurses.luau under mocked Roblox services and a mocked PlayerData:
-- grant to a full roster, take of a listed nurse, give and the Market's undo (no nurse lost or doubled, cash
-- conserved), SetJob's rules, XP from cures across levels, the ability upgrade celebrations, and a sale waking a
-- resting nurse. Run from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")

local T = require("./expect")
local expect, test = T.expect, T.test

local Config = require("./config")
local AbilitiesLogic = require("../src/shared/Logic/Abilities")
local BuildingLogic = require("../src/shared/Logic/Building")
local JobsLogic = require("../src/shared/Logic/Jobs")
local NurseLogic = require("../src/shared/Logic/Nurse")
local RebirthLogic = require("../src/shared/Logic/Rebirth")
local RecipeLogic = require("../src/shared/Logic/Recipe")
local Schema = require("../src/shared/Logic/Schema")
local VisitLogic = require("../src/shared/Logic/Visit")
local AbilitiesData = require("../src/shared/Data/Abilities")
local DecorData = require("../src/shared/Data/Decor")
local DeptData = require("../src/shared/Data/Departments")
local ItemsData = require("../src/shared/Data/Items")
local JobsData = require("../src/shared/Data/Jobs")
local NursesData = require("../src/shared/Data/Nurses")
local PerksData = require("../src/shared/Data/Perks")
local Rarities = require("../src/shared/Data/Rarities")
local TreeData = require("../src/shared/Data/Tree")

local function source(path: string): string
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("can't find " .. path .. " (run from game/)")
end

local function pureBlock(name: string, env: { [string]: any }): any
	local text = source("src/server/" .. name)
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to, name .. ": no PURE block")
	local block = string.sub(text, from, to - 1) .. "\nreturn Pure\n"
	local chunk = luau.load(block, { debugName = name .. ":Pure", environment = env, injectGlobals = true })
	return chunk()
end

local NP = pureBlock("Nurses.luau", {
	NurseLogic = NurseLogic,
	JobsLogic = JobsLogic,
	VisitLogic = VisitLogic,
	BuildingLogic = BuildingLogic,
})
local AP = pureBlock("Abilities.luau", {})

local function isSupply(id: string): boolean
	return NP.isSupply(ItemsData, id)
end

-- A bay patient as Nurses.bays gives one (Nurses.Pure.rows over Patients.bayView, front first).
local function bays(list: { any }, models: any?)
	local view = {}
	for index, row in list do
		table.insert(view, { Bay = tostring(index), PatientId = index, Stage = row[1], Needs = row[2], Since = index })
	end
	return NP.rows(view, models or {})
end

local function known(id: string): boolean
	return type(rawget(NursesData, id)) == "table"
end

local function entry(level: number?, job: string?, xp: number?, copies: number?)
	return { Level = level or 1, XP = xp or 0, Copies = copies or 1, Job = job or "" }
end

------------------------------------------------------------------------------------------------------------------
-- Server/Nurses: the pure helpers
------------------------------------------------------------------------------------------------------------------

T.describe("Nurses.Pure (v2)", function()
	test("matches: its own department or Any", function()
		expect(NP.matches("Hydro", "Hydro")).toBe(true)
		expect(NP.matches("Any", "Wards")).toBe(true)
		expect(NP.matches("Hydro", "Wards")).toBe(false)
		expect(NP.matches("Any", "")).toBe(false)
		expect(NP.matches("Any", nil)).toBe(false)
	end)

	test("shift: Double Shift divides the seconds, never under the floor", function()
		expect(NP.shift(10, 1.25, 3)).toBeCloseTo(8)
		expect(NP.shift(10, 1, 3)).toBe(10)
		expect(NP.shift(3.5, 1.25, 3)).toBe(3)
		expect(NP.shift(10, 0 / 0, 3)).toBe(10) -- junk factor = none
		expect(NP.shift(10, 0.5, 3)).toBe(10) -- never slower
	end)

	test("cureXP: PerCure, + Specialty on a matching department, x Fast Learners", function()
		local xp = Config.NurseXP
		expect(NP.cureXP(xp, "Reception", { "Reception", "" }, 1)).toBe(xp.PerCure + xp.Specialty)
		expect(NP.cureXP(xp, "Wards", { "Reception", "Wards" }, 1)).toBe(xp.PerCure + xp.Specialty) -- where it rested
		expect(NP.cureXP(xp, "Hydro", { "Reception", "" }, 1)).toBe(xp.PerCure)
		expect(NP.cureXP(xp, "Any", { "AE", "" }, 1)).toBe(xp.PerCure + xp.Specialty)
		expect(NP.cureXP(xp, "Reception", { "Reception", "Reception" }, 1)).toBe(2) -- one bonus, not two
		expect(NP.cureXP(xp, "Reception", { "Reception", "" }, xp.FastLearners)).toBe(4)
		expect(NP.cureXP(xp, "Hydro", { "Reception", "" }, 0 / 0)).toBe(1)
	end)

	test("the Fast Learners perk is the same x2 as Config.NurseXP.FastLearners", function()
		local effects =
			RebirthLogic.effects({ Rebirth = { Perks = { "FastLearners" }, Tree = {} } }, Config, PerksData, TreeData)
		expect(effects.XP).toBe(Config.NurseXP.FastLearners)
	end)

	test(
		"working/rest picking: Logic/Nurse.working keeps the cap's first by id; a freed place wakes the first resting",
		function()
			local nurses = {
				PuffPup = entry(),
				BeanBear = entry(),
				DewDuck = entry(1, "Rest"),
				MintMouse = entry(1, "Rest"),
				Ghost = entry(1, "Rest"), -- unknown: kept in the save, never woken
			}
			expect(NurseLogic.working(nurses, 3, known)).toEqual({ "BeanBear", "PuffPup" })
			expect(NP.toWake(nurses, 3, known)).toEqual({ "DewDuck" })
			expect(NP.toWake(nurses, 4, known)).toEqual({ "DewDuck", "MintMouse" })
			expect(NP.toWake(nurses, 9, known)).toEqual({ "DewDuck", "MintMouse" })
			expect(NP.toWake(nurses, 2, known)).toEqual({})
			-- an unknown id that still works holds a place (as Logic/Nurse.setJob counts)
			nurses.Ghost = entry()
			expect(NP.toWake(nurses, 3, known)).toEqual({})
			expect(NP.toWake(nil, 3, known)).toEqual({})
		end
	)

	test("team counts: working specialties, Any counts everywhere, chips only for teams with a bonus", function()
		local counts = JobsLogic.teams({ "Reception", "Reception", "Hydro", "Any" }, DeptData)
		expect(counts.Reception).toBe(3)
		expect(counts.Hydro).toBe(2)
		expect(counts.Roof).toBe(1)
		expect(NP.teamLine(counts, DeptData)).toBe("Reception:3,Hydro:2")
		local effects = JobsLogic.teamEffects(counts, DeptData)
		expect(effects.Cash).toBeCloseTo(1.2)
		expect(NP.makeLine(effects.Make)).toBe("Bath=0.8")
		expect(NP.teamLine(JobsLogic.teams({ "Reception" }, DeptData), DeptData)).toBe("")
		-- the Pharmacy team works the supply shelf and the Cocoa Corner (never the dispensary: nurses don't dispense)
		local pharmacy =
			JobsLogic.teamEffects(JobsLogic.teams({ "Pharmacy", "Pharmacy", "Pharmacy" }, DeptData), DeptData)
		expect(NP.makeLine(pharmacy.Make)).toBe("Bandage=0.6,Cocoa=0.6,Ice=0.6,Plaster=0.6")
		expect(pharmacy.Make.Remedy).toBeNil()
		local hydro = JobsLogic.teamEffects(JobsLogic.teams({ "Hydro", "Hydro" }, DeptData), DeptData)
		expect(NP.makeLine(hydro.Make)).toBe("Bath=0.8")
		expect(NP.makeLine({})).toBe("")
	end)

	test("every specialty is a department (or Any), so teams can form", function()
		for _, id in NursesData.Order do
			local s = NursesData[id].Specialty
			expect(s == "Any" or type(rawget(DeptData, s)) == "table").toBe(true)
		end
	end)

	test("urgentRow: only a 🚑/🚁 bay patient waiting for the doctor, the longest-waiting first", function()
		local rows = bays({
			{ "Treat", { "Cocoa" } },
			{ "Exam", {} },
			{ "Treat", { "Plaster", "CoughSyrup" } },
			{ "Treat", { "Bubbles" } },
		}, {
			["1"] = { Urgent = "" },
			["2"] = { Urgent = "AE", State = "Examining" }, -- in its exam: not waiting
			["3"] = { Urgent = "VIP" },
			["4"] = { Urgent = "AE" },
		})
		expect(NP.urgentRow(rows).PatientId).toBe(3)
		expect(NP.urgentRow({})).toBeNil()
	end)

	test("canTake: owned, not rebirth-only, not listed unless the Market takes it", function()
		local nurses = { PuffPup = entry() }
		expect(NP.canTake(nurses, "PuffPup", "Sold", false, false)).toBe(true)
		local ok, why = NP.canTake(nurses, "PuffPup", "Sold", true, false)
		expect(ok).toBe(false)
		expect(why).toBe("Unlist it first")
		expect(NP.canTake(nurses, "PuffPup", "Market", true, false)).toBe(true)
		ok, why = NP.canTake(nurses, "FounderFennec", "Sold", false, true)
		expect(why).toBe("Hire it first!")
		ok, why = NP.canTake({ FounderFennec = entry() }, "FounderFennec", "Sold", false, true)
		expect(ok).toBe(false)
		expect(why).toBe("This one stays with you!")
	end)

	test("giveEntry: the exact Level, XP and Copies, sane, Job '' (or kept for the undo)", function()
		expect(NP.giveEntry(entry(7, "Porter", 33, 4), false)).toEqual(entry(7, "", 33, 4))
		expect(NP.giveEntry(entry(7, "Porter", 33, 4), true)).toEqual(entry(7, "Porter", 33, 4))
		expect(NP.giveEntry({ Level = 0 / 0, XP = -5, Copies = 0 }, false)).toEqual(entry(1, "", 0, 1))
		expect(NP.giveEntry({ Level = 2, XP = 999 }, false).XP).toBe(NurseLogic.xpToNext(2) - 1)
	end)

	test("canGive: new, a slot, a level the cap allows, the cash; the undo skips only the roster check", function()
		local data = Schema.default()
		data.Cash = 500
		data.Nurses = { BeanBear = entry(), DewDuck = entry(), HumHamster = entry() }
		local ok, why = NP.canGive(data, "PuffPup", entry(), 100, Config, known, false, false)
		expect(ok).toBe(false)
		expect(why).toBe("Roster full: sell or list one")
		expect(NP.canGive(data, "PuffPup", entry(), 100, Config, known, false, true)).toBe(true)
		ok, why = NP.canGive(data, "BeanBear", entry(), 100, Config, known, false, true)
		expect(why).toBe("You have one!")
		data.Nurses.HumHamster = nil
		ok, why = NP.canGive(data, "PuffPup", entry(12), 100, Config, known, false, false)
		expect(why).toBe("🏢 R" .. Config.Nurses.LevelCapRebirths .. " first!")
		data.Rebirth.Count = Config.Nurses.LevelCapRebirths
		expect(NP.canGive(data, "PuffPup", entry(12), 100, Config, known, false, false)).toBe(true)
		ok, why = NP.canGive(data, "PuffPup", entry(), 501, Config, known, false, false)
		expect(why).toBe("Need 💰501")
		ok, why = NP.canGive(data, "FounderFennec", entry(), 0, Config, known, true, false)
		expect(why).toBe("This one stays with you!")
	end)

	test("abilityUp: crossing Lv 5 or Lv 10 (even two levels at once)", function()
		local at = Config.Abilities.UpgradeLevels
		expect(NP.abilityUp(4, 5, at)).toBe(true)
		expect(NP.abilityUp(5, 6, at)).toBe(false)
		expect(NP.abilityUp(3, 6, at)).toBe(true)
		expect(NP.abilityUp(9, 11, at)).toBe(true)
		expect(NP.abilityUp(1, 2, at)).toBe(false)
	end)

	test("amount: whole, finite, >= 0", function()
		expect(NP.amount(10.4)).toBe(10)
		expect(NP.amount(0)).toBe(0)
		expect(NP.amount(-1)).toBeNil()
		expect(NP.amount(0 / 0)).toBeNil()
		expect(NP.amount(math.huge)).toBeNil()
		expect(NP.amount("5")).toBeNil()
	end)

	test("every job has a loop and every task a bubble (source check)", function()
		local nurses = source("src/server/Nurses.luau")
		for _, jobId in JobsData.Order do
			expect(string.find(nurses, "\n\t" .. jobId .. " = %l+Loop,") ~= nil).toBe(true)
		end
		local builder = source("src/server/NurseBuilder.luau")
		for _, name in { "Escorting", "Greeting", "Treating" } do
			expect(string.find(builder, '"' .. name .. '"', 1, true) ~= nil).toBe(true)
		end
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- Server/Abilities: the state machine
------------------------------------------------------------------------------------------------------------------

T.describe("Abilities.Pure", function()
	local function strength(id: string, level: number?, secondWind: boolean?)
		return AbilitiesLogic.strength(id, level or 1, AbilitiesData, Config, secondWind)
	end

	test("LOW matches Logic/Abilities", function()
		expect(AP.LOW).toBe(AbilitiesLogic.LOW)
	end)

	test("a new slot is ready; firing starts the cooldown; it's ready again when it ends", function()
		local s = strength("CalmSong")
		local slot = AP.newSlot("CalmSong", s.Kind, s.Daily, s.Cooldown, 100)
		expect(AP.ready(slot, 100, 0)).toBe(true)
		AP.startCooldown(slot, s.Cooldown, 100, 0, nil)
		expect(slot.ReadyAt).toBe(190)
		expect(slot.UsedAt).toBe(100)
		expect(AP.ready(slot, 189.9, 0)).toBe(false)
		expect(AP.ready(slot, 190, 0)).toBe(true)
	end)

	test("prune: an owner who left keeps only what a rejoin must not reset", function()
		local ready = AP.newSlot("CalmSong", "PauseLine", false, 90, 0)
		local cooling = AP.newSlot("BusyPaws", "FastMake", false, 90, 0)
		AP.startCooldown(cooling, 90, 0, 0, nil)
		local banked = AP.newSlot("GoldenTouch", "AutoPerfect", false, 90, 0)
		banked.Charges = 2
		local miracle = AP.newSlot("Miracle", "CureLine", true, 240, 0)
		AP.startCooldown(miracle, 240, 0, 3, 500)
		local slots = { A = ready, B = cooling, C = banked, D = miracle }
		expect(AP.prune(slots, 10, 3)).toBe(false)
		expect(slots.A).toBeNil() -- a fresh slot would equal it
		expect(slots.B ~= nil and slots.C ~= nil and slots.D ~= nil).toBe(true)
		expect(AP.prune(slots, 100, 3)).toBe(false) -- B ready now; C still banked; D used today
		expect(slots.B).toBeNil()
		slots.C.Charges = 0
		expect(AP.prune(slots, 100, 4)).toBe(true) -- a new in-game day: Miracle is ready again
	end)

	test("cooldowns shrink at Lv 5 and 10 and with Second Wind, never under the floor", function()
		expect(strength("CalmSong", 5).Cooldown).toBeCloseTo(76.5)
		expect(strength("CalmSong", 10).Cooldown).toBeCloseTo(65.025)
		expect(strength("QuickBandage", 10, true).Cooldown).toBeCloseTo(34.68)
		expect(strength("QuickBandage", 1).Cooldown >= Config.Abilities.MinCooldown).toBe(true)
	end)

	test("the ring: fills with the cooldown, full only when ready or banked, written in steps", function()
		local slot = AP.newSlot("CalmSong", "PauseLine", false, 90, 0)
		AP.startCooldown(slot, 80, 0, 0, nil)
		expect(AP.fraction(slot, 0, 0)).toBe(0)
		expect(AP.fraction(slot, 40, 0)).toBeCloseTo(0.5)
		expect(AP.fraction(slot, 79.99, 0) < 1).toBe(true)
		expect(AP.fraction(slot, 80, 0)).toBe(1)
		expect(AP.quantize(0.5, 8)).toBe(0.5)
		expect(AP.quantize(0.99, 8)).toBe(0.875)
		expect(AP.quantize(1, 8)).toBe(1)
		slot.Charges = 2
		expect(AP.fraction(slot, 10, 0)).toBe(1)
	end)

	test("banked: Golden Touch banks 3 games, spends them over two treats, then cools down", function()
		local s = strength("GoldenTouch")
		local slot = AP.newSlot("GoldenTouch", s.Kind, s.Daily, s.Cooldown, 0)
		expect(AbilitiesLogic.BANKED[s.Kind]).toBe(true)
		slot.Charges = AP.charges(s.Kind, s.Value)
		expect(slot.Charges).toBe(3)
		local flags, left = AbilitiesLogic.autoGames({ "Pour", "Patch" }, { { Game = nil, Count = slot.Charges } })
		expect(flags).toEqual({ true, true })
		expect(AP.spend(slot, slot.Charges - left[1].Count, s.Cooldown, 10, 0, nil)).toBe(2)
		expect(slot.Charges).toBe(1)
		expect(slot.FiredAt).toBe(0) -- not cooling yet
		expect(AP.spend(slot, 5, s.Cooldown, 20, 0, nil)).toBe(1) -- never more than it holds
		expect(slot.Charges).toBe(0)
		expect(slot.ReadyAt).toBe(20 + s.Cooldown)
		expect(AP.ready(slot, 21, 0)).toBe(false)
	end)

	test("charges: Star Burst holds one cure, Double Dose its Value cures", function()
		expect(AP.charges("StarsNext", 5)).toBe(1)
		expect(AP.charges("CashNext", strength("DoubleDose", 10).Value)).toBe(3)
		expect(AP.charges("AutoPerfect", 0 / 0)).toBe(1)
	end)

	test("Miracle: once per in-game day; the ring runs to the next morning", function()
		local s = strength("Miracle")
		expect(s.Daily).toBe(true)
		local slot = AP.newSlot("Miracle", s.Kind, s.Daily, s.Cooldown, 0)
		expect(AP.ready(slot, 0, 3)).toBe(true)
		AP.startCooldown(slot, s.Cooldown, 50, 3, 250)
		expect(slot.Day).toBe(3)
		expect(slot.ReadyAt).toBe(250)
		expect(slot.Cooldown).toBe(200)
		expect(AP.ready(slot, 9999, 3)).toBe(false) -- the same day, however long
		expect(AP.fraction(slot, 9999, 3) < 1).toBe(true)
		expect(AP.ready(slot, 60, 4)).toBe(true) -- the next morning
		expect(AP.nextMorning(false, 400, Config.NightSeconds)).toBe(400 + Config.NightSeconds)
		expect(AP.nextMorning(true, 400, Config.NightSeconds)).toBe(400)
		expect(AP.nextMorning(true, nil, Config.NightSeconds)).toBeNil()
	end)

	test("Team Spirit: every OTHER ability ready now, never Miracle; cooling counts the others", function()
		local slots = {
			A = AP.newSlot("CalmSong", "PauseLine", false, 90, 0),
			B = AP.newSlot("BusyPaws", "FastMake", false, 90, 0),
			C = AP.newSlot("Miracle", "CureLine", true, 600, 0),
			Me = AP.newSlot("TeamSpirit", "Recharge", false, 240, 0),
		}
		AP.startCooldown(slots.A, 90, 0, 0, nil)
		AP.startCooldown(slots.B, 90, 0, 0, nil)
		AP.startCooldown(slots.C, 600, 0, 0, 600)
		expect(AP.cooling(slots, "Me", 10, 0)).toBe(3)
		expect(AbilitiesLogic.useful("Recharge", { OnCooldown = AP.cooling(slots, "Me", 10, 0) })).toBe(true)
		AP.startCooldown(slots.Me, 240, 10, 0, nil)
		AP.recharge(slots, "Me", 10)
		expect(AP.ready(slots.A, 10, 0)).toBe(true)
		expect(AP.ready(slots.B, 10, 0)).toBe(true)
		expect(AP.ready(slots.C, 10, 0)).toBe(false)
		expect(AP.ready(slots.Me, 10, 0)).toBe(false)
	end)

	test("the usefulness views: built from the bays, the waiting room, the tray and the hands", function()
		local rows = bays({
			{ "Treat", { "Ice", "Plaster" } }, -- the front
			{ "Treat", { "Ice", "CoughSyrup" } }, -- in a mini-game: not waiting for the doctor
			{ "Exam", {} },
		}, {
			["1"] = { Patience = 0.3 },
			["2"] = { State = "Treating", Patience = 0.1 },
			["3"] = { Patience = 0.8 },
		})
		local view = AP.view(rows, { 0.9, 0.2 }, { "Ice" }, { "Plaster" }, 4, false, 0, isSupply)
		expect(view.FrontPatience).toBeCloseTo(0.3)
		expect(view.LowCount).toBe(2) -- the front, and one in a seat
		expect(view.Waiting).toBe(2) -- the bay patients Miracle would finish
		expect(view.Missing).toBe(2) -- the second Ice pack and the cough syrup
		expect(view.Supplies).toBe(1) -- only the Ice pack can go in the tray
		expect(view.TrayRoom).toBe(3)
		expect(AbilitiesLogic.useful("RefillFront", view)).toBe(true)
		expect(AbilitiesLogic.useful("PauseLine", view)).toBe(true)
		expect(AbilitiesLogic.useful("RefillLine", view)).toBe(true)
		expect(AbilitiesLogic.useful("CureLine", view)).toBe(true)
		expect(AbilitiesLogic.useful("TrayItem", view)).toBe(true)
		expect(AbilitiesLogic.useful("FastMake", view)).toBe(true)
		expect(AP.targets(rows)).toEqual({ 1, 3 }) -- never the one in a mini-game
		local calm = AP.view({}, {}, {}, {}, 4, true, 0, isSupply)
		expect(calm.FrontPatience).toBeNil()
		for _, kind in { "RefillFront", "PauseLine", "RefillLine", "CureLine", "TrayItem", "FastMake", "InstantMake" } do
			expect(AbilitiesLogic.useful(kind, calm)).toBe(false) -- nothing fires on a quiet clinic
		end
		-- only medicines missing: Fresh Brew has nothing to do (the player dispenses them)
		local meds = AP.view(bays({ { "Treat", { "CoughSyrup", "EarDrops" } } }), {}, {}, {}, 4, true, 0, isSupply)
		expect(meds.Missing).toBe(2)
		expect(AbilitiesLogic.useful("TrayItem", meds)).toBe(false)
		expect(AbilitiesLogic.useful("InstantMake", meds)).toBe(true)
		meds.NearStation = false
		expect(AbilitiesLogic.useful("InstantMake", meds)).toBe(false)
	end)

	test("Fresh Brew: the missing supplies (never a medicine), capped by its value and the tray's room", function()
		local brew = AP.brew
		expect(brew({ "Ice", "Plaster", "Cocoa" }, { "Ice" }, {}, 3, 3, isSupply)).toEqual({ "Plaster", "Cocoa" })
		expect(brew({ "Ice", "Plaster", "Cocoa" }, {}, {}, 1, 3, isSupply)).toEqual({ "Ice" })
		expect(brew({ "Ice", "Plaster" }, {}, {}, 3, 1, isSupply)).toEqual({ "Ice" })
		expect(brew({ "Ice" }, {}, { "Ice" }, 3, 3, isSupply)).toEqual({})
		expect(brew({ "CoughSyrup", "Bandage", "PainRelief" }, {}, {}, 3, 3, isSupply)).toEqual({ "Bandage" })
		expect(AP.needs(bays({ { "Treat", { "Cast", "PainRelief" } }, { "Exam", {} } }))).toEqual({
			"Cast",
			"PainRelief",
		})
	end)

	test("station rush: the strongest running one wins, ended ones drop off", function()
		local rushes = {}
		AP.addRush(rushes, 0.5, 20)
		AP.addRush(rushes, 0, 12)
		AP.addRush(rushes, 0.5, 16) -- a shorter Busy Paws keeps the longer end
		local factor, untilAt = AP.rush(rushes, 10)
		expect(factor).toBe(0)
		expect(untilAt).toBe(12)
		factor, untilAt = AP.rush(rushes, 13)
		expect(factor).toBe(0.5)
		expect(untilAt).toBe(20)
		expect(#rushes).toBe(1)
		factor, untilAt = AP.rush(rushes, 25)
		expect(factor).toBe(1)
		expect(untilAt).toBe(0)
		expect(#rushes).toBe(0)
	end)

	test("games: a list of strings, at most the max, else junk", function()
		expect(AP.games({ "Pour", "Patch" }, 8)).toEqual({ "Pour", "Patch" })
		expect(AP.games({ "Pour", 5 }, 8)).toBeNil()
		expect(AP.games("Pour", 8)).toBeNil()
		expect(AP.games({ "a", "b", "c" }, 2)).toBeNil()
		expect(AP.games({}, 8)).toEqual({})
	end)

	test("every nurse's ability exists, and every ability kind is handled by someone", function()
		local handled = {
			AutoPerfect = true, -- consumePerfects
			CashNext = true, -- consumeCure
			StarsNext = true,
			TrayItem = true, -- Abilities
			FastMake = true,
			InstantMake = true,
			PauseLine = true,
			Recharge = true,
			RefillFront = true, -- Patients (Fired)
			RefillLine = true,
			CureLine = true,
		}
		for _, id in NursesData.Order do
			expect(type(rawget(AbilitiesData, NursesData[id].Ability))).toBe("table")
		end
		for _, id in AbilitiesData.Order do
			expect(handled[AbilitiesData[id].Kind]).toBe(true)
		end
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- The real Server/Nurses under mocks
------------------------------------------------------------------------------------------------------------------

local function mockSignal()
	local fns = {}
	local signal = {}
	function signal:Connect(fn)
		table.insert(fns, fn)
		return { Disconnect = function() end }
	end
	function signal:Fire(...)
		for _, fn in table.clone(fns) do
			fn(...)
		end
	end
	return signal
end

local Players = { list = {}, PlayerRemoving = mockSignal(), PlayerAdded = mockSignal() }
function Players:GetPlayers()
	return self.list
end

local nextUserId = 1000
local function newPlayer(name: string)
	nextUserId += 1
	local attributes = {}
	local p = { __instance = true, Name = name, UserId = nextUserId, Parent = Players }
	function p:IsA(class)
		return class == "Player"
	end
	function p:GetAttribute(k)
		return attributes[k]
	end
	function p:SetAttribute(k, v)
		attributes[k] = v
	end
	table.insert(Players.list, p)
	return p
end

local sent = {}
local served = {}
local function remoteEvent(name: string)
	return {
		FireClient = function(_, player, payload)
			table.insert(sent, { Remote = name, Player = player, Payload = payload })
		end,
	}
end
local Remotes = {
	OOPS = "Oops! Try again.",
	TOO_FAST = "Too fast! Try again.",
	SOON = "Coming soon!",
	NurseNews = remoteEvent("NurseNews"),
	Celebrate = remoteEvent("Celebrate"),
	serve = function(name, handler)
		served[name] = handler
	end,
}

local saves = {}
local PlayerData = { Changed = mockSignal(), Loaded = mockSignal() }
function PlayerData.get(p)
	return saves[p]
end
function PlayerData.update(p, fn)
	local data = saves[p]
	if not data then
		return false
	end
	fn(data)
	PlayerData.Changed:Fire(p, data)
	return true
end

local signals = { Hired = {}, LevelUp = {}, Removed = {} }
local noop = function() end
local modules = {
	Config = Config,
	Palette = {},
	Remotes = Remotes,
	Signal = { new = mockSignal },
	Types = {},
	["Logic.Building"] = BuildingLogic,
	["Logic.Jobs"] = JobsLogic,
	["Logic.Nurse"] = NurseLogic,
	["Logic.Rebirth"] = RebirthLogic,
	["Logic.Recipe"] = RecipeLogic,
	["Logic.Tutorial"] = require("../src/shared/Logic/Tutorial"),
	["Logic.Visit"] = VisitLogic,
	["Data.Decor"] = DecorData,
	["Data.Departments"] = DeptData,
	["Data.Items"] = ItemsData,
	["Data.Jobs"] = JobsData,
	["Data.Nurses"] = NursesData,
	["Data.Perks"] = PerksData,
	["Data.Rarities"] = Rarities,
	["Data.Tree"] = TreeData,
	Book = {
		placeReward = function()
			return true
		end,
	},
	CreatureBuilder = { effectAt = noop },
	Levels = { LevelChanged = mockSignal() },
	Lift = {
		landing = function()
			return nil
		end,
		carry = function()
			return false
		end,
	},
	NurseBuilder = { setTask = noop, setJob = noop, addAbility = noop, popIn = noop },
	PlayerData = PlayerData,
	Plots = {
		getPlot = function()
			return nil
		end,
		all = function()
			return {}
		end,
		fromInstance = function()
			return nil
		end,
		PlotAssigned = mockSignal(),
		PlotReleased = mockSignal(),
	},
}
local Shared = {
	Config = "Config",
	Palette = "Palette",
	Remotes = "Remotes",
	Signal = "Signal",
	Types = "Types",
	Logic = setmetatable({}, {
		__index = function(_, k)
			return "Logic." .. k
		end,
	}),
	Data = setmetatable({}, {
		__index = function(_, k)
			return "Data." .. k
		end,
	}),
}
local services = {
	Players = Players,
	Workspace = {
		Raycast = function()
			return nil
		end,
	},
	CollectionService = { AddTag = noop },
	ReplicatedStorage = { Shared = Shared },
}
local env = {
	game = {
		GetService = function(_, name)
			return assert(services[name], "no mock service " .. tostring(name))
		end,
	},
	script = { Parent = setmetatable({}, {
		__index = function(_, k)
			return k
		end,
	}) },
	require = function(token)
		return assert(modules[token], "no mock for " .. tostring(token))
	end,
	typeof = function(v)
		if type(v) == "table" and v.__instance then
			return "Instance"
		end
		return typeof(v)
	end,
	task = task,
	Random = {
		new = function()
			return {
				NextNumber = function(_, a, b)
					return (a + b) / 2
				end,
			}
		end,
	},
	warn = noop,
}
local Nurses = luau.load(source("src/server/Nurses.luau"), { debugName = "Server/Nurses", environment = env })()
Nurses.Hired:Connect(function(p, id, level)
	table.insert(signals.Hired, { p, id, level })
end)
Nurses.LevelUp:Connect(function(p, id, level)
	table.insert(signals.LevelUp, { p, id, level })
end)
Nurses.Removed:Connect(function(p, id)
	table.insert(signals.Removed, { p, id })
end)
Nurses.start()
local SetJob = served.SetJob

local function newSave(player, nurses, cash: number?, extra: ((any) -> ())?)
	local data = Schema.default()
	data.Tutorial = 9
	data.Cash = cash or 1000
	data.Level = 1
	data.Nurses = nurses or {}
	for id in data.Nurses do
		data.NurseIndex[id] = "Hired"
	end
	-- like a real save: a journal set already complete was already rewarded
	for _, rarity in NurseLogic.setsDue(data.NurseIndex, NursesData, Rarities, data.JournalSets) do
		data.JournalSets[rarity] = true
	end
	if extra then
		extra(data)
	end
	saves[player] = data
	return data
end

local function sentTo(player, remote: string, kind: string?)
	local out = {}
	for _, item in sent do
		if item.Player == player and item.Remote == remote and (kind == nil or item.Payload.Kind == kind) then
			table.insert(out, item.Payload)
		end
	end
	return out
end

T.describe("Server/Nurses (mocked): grant", function()
	test("a new nurse to a full roster is refused and nothing changes; a copy still levels up", function()
		local p = newPlayer("Full")
		local data = newSave(p, { PuffPup = entry(), MintMouse = entry(), BeanBear = entry() }, 1000)
		local ok, why = Nurses.grant(p, "DewDuck", 100, "Agency")
		expect(ok).toBe(false)
		expect(why).toBe("Roster full: sell or list one")
		expect(data.Cash).toBe(1000)
		expect(data.Nurses.DewDuck).toBeNil()
		expect(data.NurseIndex.DewDuck).toBeNil()
		ok = Nurses.grant(p, "PuffPup", 100)
		expect(ok).toBe(true)
		expect(data.Nurses.PuffPup).toEqual(entry(2, "", 0, 2))
		expect(data.Cash).toBe(900)
		local hired = sentTo(p, "NurseNews", "Hired")
		expect(hired[#hired].Level).toBe(2)
		expect(hired[#hired].New).toBe(false)
	end)

	test("short of cash, junk ids and prices, and a rebirth-only nurse off the belt are refused", function()
		local p = newPlayer("Junk")
		local data = newSave(p, { PuffPup = entry() }, 50)
		local ok, why = Nurses.grant(p, "DewDuck", 100)
		expect(ok).toBe(false)
		expect(why).toBe("Need 💰100")
		for _, args in
			{
				{ "FounderFennec", 0, "Belt" },
				{ "FounderFennec", 0, "Agency" },
				{ "Order", 0 },
				{ "PuffPup", -1 },
				{ "PuffPup", 0 / 0 },
				{ "PuffPup", math.huge },
				{ "PuffPup", 0, "Robux" },
				{ 5, 0 },
			}
		do
			ok, why = Nurses.grant(p, args[1], args[2], args[3])
			expect(ok).toBe(false)
			expect(why).toBe(Remotes.OOPS)
		end
		expect(data.Cash).toBe(50)
		expect(data.Nurses).toEqual({ PuffPup = entry() })
	end)

	test("a Gift arrives free and leaves Rebirth.Pending", function()
		local p = newPlayer("Gift")
		local data = newSave(p, { PuffPup = entry() }, 0, function(d)
			d.Rebirth.Count = 5
			d.Rebirth.Pending = { "FounderFennec" }
		end)
		local ok = Nurses.grant(p, "FounderFennec", 0, "Gift")
		expect(ok).toBe(true)
		expect(data.Nurses.FounderFennec).toEqual(entry())
		expect(data.Rebirth.Pending).toEqual({})
		expect(data.NurseIndex.FounderFennec).toBe("Hired")
		expect(#sentTo(p, "Celebrate", "NewNurse")).toBe(1)
	end)
end)

T.describe("Server/Nurses (mocked): take", function()
	test("a listed nurse can't go to the Agency; the Market takes it and clears the lock", function()
		local p = newPlayer("Seller")
		local data = newSave(p, { PuffPup = entry(4, "Healer", 9, 2), MintMouse = entry() }, 100)
		Nurses.setListed(p, "PuffPup", 7)
		expect(Nurses.isListed(p, "PuffPup")).toBe(true)
		expect(sentTo(p, "NurseNews", "Listed")[1].On).toBe(true)
		local ok, why = Nurses.take(p, "PuffPup", 30, "Sold")
		expect(ok).toBe(false)
		expect(why).toBe("Unlist it first")
		expect(data.Cash).toBe(100)
		expect(data.Nurses.PuffPup ~= nil).toBe(true)
		local taken
		ok, why, taken = Nurses.take(p, "PuffPup", 90, "Market")
		expect(ok).toBe(true)
		expect(taken).toEqual(entry(4, "Healer", 9, 2))
		expect(data.Nurses.PuffPup).toBeNil()
		expect(data.Cash).toBe(190)
		expect(Nurses.isListed(p, "PuffPup")).toBe(false)
		expect(data.NurseIndex.PuffPup).toBe("Hired") -- the Journal keeps it
		expect(sentTo(p, "NurseNews", "Gone")[1].Cash).toBe(90)
		expect(signals.Removed[#signals.Removed][2]).toBe("PuffPup")
	end)

	test("selling to the Agency: cash in, nurse out, Journal kept; FounderFennec stays; junk refused", function()
		local p = newPlayer("Agency")
		local data = newSave(p, { MintMouse = entry(), FounderFennec = entry() }, 0)
		local ok, why = Nurses.take(p, "FounderFennec", 0, "Sold")
		expect(ok).toBe(false)
		expect(why).toBe("This one stays with you!")
		ok, why = Nurses.take(p, "DewDuck", 10, "Sold")
		expect(why).toBe("Hire it first!")
		for _, args in { { "MintMouse", -5, "Sold" }, { "MintMouse", 5, "Gift" }, { "MintMouse", 0 / 0, "Sold" } } do
			ok, why = Nurses.take(p, args[1], args[2], args[3])
			expect(ok).toBe(false)
			expect(why).toBe(Remotes.OOPS)
		end
		expect(data.Cash).toBe(0)
		ok = Nurses.take(p, "MintMouse", 30, "Sold")
		expect(ok).toBe(true)
		expect(data.Cash).toBe(30)
		expect(data.Nurses.MintMouse).toBeNil()
		expect(data.NurseIndex.MintMouse).toBe("Hired")
		expect(sentTo(p, "NurseNews", "Sold")[1].Cash).toBe(30)
		ok = Nurses.take(p, "MintMouse", 30, "Sold") -- a second sale of the same nurse
		expect(ok).toBe(false)
		expect(data.Cash).toBe(30)
	end)

	test("setListed ignores junk and nurses you don't own; leaving clears the lock", function()
		local p = newPlayer("Locks")
		newSave(p, { PuffPup = entry() })
		Nurses.setListed(p, "DewDuck", 3)
		expect(Nurses.isListed(p, "DewDuck")).toBe(false)
		Nurses.setListed(p, "PuffPup", "3")
		expect(Nurses.isListed(p, "PuffPup")).toBe(false)
		Nurses.setListed(p, "PuffPup", 3)
		expect(Nurses.isListed(p, "PuffPup")).toBe(true)
		Nurses.setListed(p, "PuffPup", nil)
		expect(Nurses.isListed(p, "PuffPup")).toBe(false)
		Nurses.setListed(p, "PuffPup", 4)
		Players.PlayerRemoving:Fire(p)
		expect(Nurses.isListed(p, "PuffPup")).toBe(false)
	end)
end)

T.describe("Server/Nurses (mocked): give and the Market's undo", function()
	test("the buyer gets the exact level, XP and copies and works its role", function()
		local b = newPlayer("Buyer")
		local data = newSave(b, {}, 1000)
		local ok = Nurses.give(b, "PuffPup", entry(7, "Porter", 33, 4), 420)
		expect(ok).toBe(true)
		expect(data.Nurses.PuffPup).toEqual(entry(7, "", 33, 4))
		expect(data.Cash).toBe(580)
		expect(data.NurseIndex.PuffPup).toBe("Hired")
		expect(sentTo(b, "NurseNews", "Bought")[1].Price).toBe(420)
		expect(#sentTo(b, "Celebrate", "NewNurse")).toBe(1)
		local why
		ok, why = Nurses.give(b, "PuffPup", entry(7), 1)
		expect(ok).toBe(false)
		expect(why).toBe("You have one!")
		expect(data.Cash).toBe(580)
	end)

	test("a full roster, a level above the cap, short cash, rebirth-only and junk are refused", function()
		local b = newPlayer("Picky")
		local data = newSave(b, { BeanBear = entry(), DewDuck = entry(), HumHamster = entry() }, 100)
		local ok, why = Nurses.give(b, "PuffPup", entry(), 10)
		expect(why).toBe("Roster full: sell or list one")
		data.Nurses.HumHamster = nil
		ok, why = Nurses.give(b, "PuffPup", entry(12), 10)
		expect(why).toBe("🏢 R3 first!")
		ok, why = Nurses.give(b, "PuffPup", entry(), 101)
		expect(why).toBe("Need 💰101")
		ok, why = Nurses.give(b, "FounderFennec", entry(), 0)
		expect(why).toBe("This one stays with you!")
		for _, args in { { "PuffPup", nil, 10 }, { "PuffPup", entry(), -1 }, { "Order", entry(), 0 } } do
			ok, why = Nurses.give(b, args[1], args[2], args[3])
			expect(ok).toBe(false)
			expect(why).toBe(Remotes.OOPS)
		end
		expect(data.Cash).toBe(100)
		expect(data.Nurses.PuffPup).toBeNil()
	end)

	test("the buyer's side failing: the undo puts the seller back exactly, and cash is conserved", function()
		local s, b = newPlayer("UndoSeller"), newPlayer("UndoBuyer")
		local sd = newSave(s, { PuffPup = entry(6, "Healer", 12, 3), MintMouse = entry() }, 100)
		local bd = newSave(b, {}, 50) -- can't pay: step 11 fails
		local before = sd.Cash + bd.Cash
		local price, payout = 450, 450 - math.floor(450 * Config.Market.Fee)
		Nurses.setListed(s, "PuffPup", 1)
		local ok, _, taken = Nurses.take(s, "PuffPup", payout, "Market")
		expect(ok).toBe(true)
		local bought = Nurses.give(b, "PuffPup", taken, price)
		expect(bought).toBe(false)
		local newsBefore = #sentTo(s, "NurseNews", "Bought")
		local undone = Nurses.give(s, "PuffPup", taken, payout, true)
		expect(undone).toBe(true)
		expect(sd.Nurses.PuffPup).toEqual(entry(6, "Healer", 12, 3)) -- its job too
		expect(bd.Nurses.PuffPup).toBeNil()
		expect(sd.Cash + bd.Cash).toBe(before)
		expect(#sentTo(s, "NurseNews", "Bought")).toBe(newsBefore) -- no "Bought" for an undo
	end)

	test("the undo works for an over-roster seller; a later give is a normal one", function()
		local s = newPlayer("OverSeller")
		local sd = newSave(s, {
			BeanBear = entry(),
			DewDuck = entry(),
			HumHamster = entry(),
			MintMouse = entry(1, "Rest"),
			PuffPup = entry(3, "Rest", 5),
		}, 0)
		local ok, _, taken = Nurses.take(s, "PuffPup", 100, "Market")
		expect(ok).toBe(true)
		expect(Nurses.give(s, "PuffPup", taken, 100, true)).toBe(true) -- the explicit undo: no roster check
		expect(sd.Nurses.PuffPup).toEqual(entry(3, "Rest", 5))
		expect(sd.Cash).toBe(0)
		ok, _, taken = Nurses.take(s, "PuffPup", 100, "Market")
		expect(ok).toBe(true)
		Nurses.endUndo(s, "PuffPup") -- the Market's sale is over: the token goes at once
		local why
		ok, why = Nurses.give(s, "PuffPup", taken, 100, true)
		expect(ok).toBe(false)
		expect(why).toBe(Remotes.OOPS) -- no token, no undo
		ok, why = Nurses.give(s, "PuffPup", taken, 100)
		expect(ok).toBe(false)
		expect(why).toBe("Roster full: sell or list one")
		expect(sd.Cash).toBe(100)
		-- and without endUndo, a frame later the deferred backstop has cleared it too
		sd.Nurses.PuffPup = entry(3, "Rest", 5)
		sd.Cash = 0
		ok, _, taken = Nurses.take(s, "PuffPup", 100, "Market")
		expect(ok).toBe(true)
		task.wait()
		ok, why = Nurses.give(s, "PuffPup", taken, 100, true)
		expect(ok).toBe(false)
		expect(why).toBe(Remotes.OOPS)
	end)

	test("a normal give in the same frame as a Market take is never an undo (no nurse doubled, none lost)", function()
		-- A lists PuffPup and C lists a PuffPup too. B buys A's (take A) and, in the same frame, A buys C's.
		local a, b, c = newPlayer("RaceA"), newPlayer("RaceB"), newPlayer("RaceC")
		local ad = newSave(a, { PuffPup = entry(6, "Healer", 12, 3) }, 1000)
		local bd = newSave(b, {}, 1000)
		local cd = newSave(c, { PuffPup = entry(2, "Maker", 4, 1) }, 0)
		Nurses.setListed(a, "PuffPup", 1)
		Nurses.setListed(c, "PuffPup", 2)
		local ok, _, fromA = Nurses.take(a, "PuffPup", 270, "Market")
		expect(ok).toBe(true)
		expect(Nurses.give(b, "PuffPup", fromA, 300)).toBe(true)
		local fromC
		ok, _, fromC = Nurses.take(c, "PuffPup", 90, "Market")
		expect(ok).toBe(true)
		expect(Nurses.give(a, "PuffPup", fromC, 100)).toBe(true) -- a normal buy: A's old token is never read
		expect(ad.Nurses.PuffPup).toEqual(entry(2, "", 4, 1)) -- C's nurse, working its role for A
		expect(bd.Nurses.PuffPup).toEqual(entry(6, "", 12, 3)) -- A's old nurse, only in B's save
		expect(cd.Nurses.PuffPup).toBeNil()
		expect(#sentTo(a, "NurseNews", "Bought")).toBe(1)
		Nurses.endUndo(a, "PuffPup")
		Nurses.endUndo(c, "PuffPup")
	end)

	test("one nurse, two buyers in one frame: only the first gets it", function()
		local s, b1, b2 = newPlayer("TwoSeller"), newPlayer("Buyer1"), newPlayer("Buyer2")
		local sd = newSave(s, { CuddleCub = entry(2) }, 0)
		local d1, d2 = newSave(b1, {}, 1000), newSave(b2, {}, 1000)
		local ok, _, taken = Nurses.take(s, "CuddleCub", 540, "Market")
		expect(ok).toBe(true)
		expect(Nurses.give(b1, "CuddleCub", taken, 600)).toBe(true)
		local again = Nurses.take(s, "CuddleCub", 540, "Market") -- the second buyer's take finds nothing
		expect(again).toBe(false)
		expect(sd.Nurses.CuddleCub).toBeNil()
		expect(d1.Nurses.CuddleCub).toEqual(entry(2))
		expect(d2.Nurses.CuddleCub).toBeNil()
		expect(sd.Cash + d1.Cash + d2.Cash).toBe(540 + 400 + 1000)
	end)
end)

T.describe("Server/Nurses (mocked): the roster wakes", function()
	test("selling a working nurse wakes the first resting one (after the update)", function()
		local p = newPlayer("Wake")
		local data = newSave(p, {
			BeanBear = entry(),
			DewDuck = entry(),
			HumHamster = entry(),
			MintMouse = entry(1, "Rest"),
			PuffPup = entry(1, "Rest"),
		}, 0)
		expect(Nurses.take(p, "BeanBear", 30, "Sold")).toBe(true)
		expect(data.Nurses.MintMouse.Job).toBe("Rest") -- not inside the sale's update
		task.wait()
		expect(data.Nurses.MintMouse.Job).toBe("")
		expect(data.Nurses.PuffPup.Job).toBe("Rest")
		expect(sentTo(p, "NurseNews", "Resting")[1].NurseId).toBe("MintMouse")
		expect(#NurseLogic.working(data.Nurses, 3, known)).toBe(3)
	end)
end)

T.describe("Server/Nurses (mocked): SetJob", function()
	test("junk, Rest, unknown, not owned and closed jobs are refused and nothing changes", function()
		local p = newPlayer("Jobs")
		local data = newSave(p, { PuffPup = entry() })
		local cases = {
			{ "PuffPup", "Rest", Remotes.OOPS },
			{ "PuffPup", "Order", Remotes.OOPS },
			{ "PuffPup", "Porter", "🏥 Lv 2 first!" },
			{ "PuffPup", "Medic", "🏥 Lv 2 first!" },
			{ "Ghost", "Healer", Remotes.OOPS },
			{ "DewDuck", "Healer", "Hire it first!" },
		}
		for _, case in cases do
			local ok, why = Nurses.setJob(p, case[1], case[2])
			expect(ok).toBe(false)
			expect(why).toBe(case[3])
		end
		expect(data.Nurses.PuffPup).toEqual(entry())
	end)

	test("a job saves, the role saves as '', and Lv 2 opens Porter", function()
		local p = newPlayer("Jobs2")
		local data = newSave(p, { PuffPup = entry() })
		local ok, message = Nurses.setJob(p, "PuffPup", "Healer")
		expect(ok).toBe(true)
		expect(message).toBe("🩺 Healer!")
		expect(data.Nurses.PuffPup.Job).toBe("Healer")
		expect(sentTo(p, "NurseNews", "Job")[1].Job).toBe("Healer")
		Nurses.setJob(p, "PuffPup", "Maker")
		expect(data.Nurses.PuffPup.Job).toBe("") -- its own Role
		data.Level = 2
		expect(Nurses.setJob(p, "PuffPup", "Porter")).toBe(true)
		expect(data.Nurses.PuffPup.Job).toBe("Porter")
		expect(JobsLogic.effective(data.Nurses.PuffPup.Job, "Maker", 1, JobsData)).toBe("Maker") -- after a rebirth
	end)

	test("a resting nurse takes a job only while the roster has a free working place", function()
		local p = newPlayer("Jobs3")
		local data = newSave(p, {
			BeanBear = entry(),
			DewDuck = entry(),
			HumHamster = entry(),
			PuffPup = entry(1, "Rest"),
		})
		local ok, why = Nurses.setJob(p, "PuffPup", "Maker")
		expect(ok).toBe(false)
		expect(why).toBe("Roster full: sell or list one")
		expect(data.Nurses.PuffPup.Job).toBe("Rest")
	end)

	test("the remote: junk types refused, then 0.35 s per player", function()
		local p = newPlayer("Remote")
		newSave(p, { PuffPup = entry() })
		for _, args in { { 5, "Healer" }, { "PuffPup", nil }, { "PuffPup", {} }, { string.rep("x", 41), "Healer" } } do
			local ok, why = SetJob(p, args[1], args[2])
			expect(ok).toBe(false)
			expect(why).toBe(Remotes.OOPS)
		end
		expect(SetJob(p, "PuffPup", "Healer")).toBe(true)
		local ok, why = SetJob(p, "PuffPup", "Cheerer")
		expect(ok).toBe(false)
		expect(why).toBe(Remotes.TOO_FAST)
	end)
end)

T.describe("Server/Nurses (mocked): XP", function()
	test("a cure gives every WORKING nurse XP, +1 in its department; resting ones get none", function()
		local p = newPlayer("XP")
		local data = newSave(p, {
			PuffPup = entry(), -- Reception
			MintMouse = entry(), -- Wards
			CuddleCub = entry(), -- AE
			BeanBear = entry(1, "Rest"), -- Pharmacy, resting
		})
		Nurses.onCure(p, { Wing = "Starter" })
		expect(data.Nurses.PuffPup.XP).toBe(2)
		expect(data.Nurses.MintMouse.XP).toBe(1)
		expect(data.Nurses.CuddleCub.XP).toBe(1)
		expect(data.Nurses.BeanBear.XP).toBe(0)
		Nurses.onCure(p, { Wing = "Starter", Dept = "Wards" })
		expect(data.Nurses.MintMouse.XP).toBe(3)
		Nurses.onCure(p, { Wing = "Starter", Urgent = "AE" })
		expect(data.Nurses.CuddleCub.XP).toBe(4)
		Nurses.onCure(p, "junk") -- junk info: the base XP, no specialty
		expect(data.Nurses.MintMouse.XP).toBe(5)
	end)

	test("Fast Learners doubles it; XP carries across two level-ups; the cap drops the rest", function()
		local p = newPlayer("XP2")
		local data = newSave(p, { PuffPup = entry(), StarlightLamb = entry(10, "", 0) }, 0, function(d)
			d.Rebirth.Perks = { "FastLearners" }
		end)
		for _ = 1, 30 do
			Nurses.onCure(p, { Wing = "Starter" }) -- 4 XP each for the Reception specialist
		end
		-- 120 XP: Lv 1 -> 2 (20), Lv 2 -> 3 (40), 60 left toward Lv 4 (70)
		expect(data.Nurses.PuffPup).toEqual(entry(3, "", 60))
		local levels = {}
		for _, item in sentTo(p, "NurseNews", "Level") do
			table.insert(levels, item.Level)
		end
		expect(levels).toEqual({ 2, 3 })
		expect(data.Nurses.StarlightLamb).toEqual(entry(10, "", 0)) -- at the cap: no XP
		expect(signals.LevelUp[#signals.LevelUp][3]).toBe(3)
	end)

	test("admin levels: +1 each to the cap; reaching Lv 5 celebrates the ability upgrade once", function()
		local p = newPlayer("Admin")
		local data = newSave(p, { PuffPup = entry(3, "", 5), MintMouse = entry(10) })
		expect(Nurses.adminLevels(p)).toBe(true)
		expect(Nurses.adminLevels(p)).toBe(true)
		expect(data.Nurses.PuffPup).toEqual(entry(5, "", 5))
		expect(data.Nurses.MintMouse).toEqual(entry(10))
		local news = sentTo(p, "NurseNews", "Level")
		expect(#news).toBe(2)
		expect(news[1].Ability).toBe(false)
		expect(news[2].Ability).toBe(true)
		local party = sentTo(p, "Celebrate", "NurseLevel")
		expect(#party).toBe(1)
		expect(party[1].Level).toBe(5)
		expect(party[1].Ability).toBe(true)
		data.Nurses.PuffPup.Level = 10
		local ok, why = Nurses.adminLevels(p)
		expect(ok).toBe(false)
		expect(why).toBe("Max level!")
	end)

	test("a plot with no workers answers neutral numbers", function()
		expect(Nurses.team({})).toEqual({ Cash = 1, Urgent = 1, Recover = 1, Make = {} })
		expect(Nurses.reception({})).toEqual({ Arrive = 1, Triage = false })
		expect(Nurses.medic({})).toEqual({ Patience = 1 })
		expect(Nurses.cheer({})).toEqual({ Patience = 1, Tip = 1 })
		expect(Nurses.claimPorter({})).toBeNil()
		expect(Nurses.escort({}, "PuffPup", nil)).toBe(false)
		expect(Nurses.bays({})).toEqual({})
		expect(Nurses.addToTray({}, "Plaster")).toBe(false) -- no plot
	end)
end)
