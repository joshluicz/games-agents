--!strict
-- Daily rules (Task 5): Today's Visitor, banked daily goals (no streaks, never a penalty), the mailbox and the
-- seasonal date window. Pure: Logic/Daily plus the Lune-safe DailyGoals data. The Real Clinic: the visitor pool comes
-- from patient -> wing, and a wing is treatable when its case pool has a case the clinic can treat.

local T = require("./expect")
local expect, test, describe = T.expect, T.test, T.describe

local Daily = require("../src/shared/Logic/Daily")
local DailyGoals = require("../src/shared/Data/DailyGoals")
local Patients = require("../src/shared/Data/Patients")
local Wings = require("../src/shared/Data/Wings")
local Cases = require("../src/shared/Data/Cases")
local Items = require("../src/shared/Data/Items")
local Rooms = require("../src/shared/Data/Rooms")
local Visit = require("../src/shared/Logic/Visit")
local Building = require("../src/shared/Logic/Building")

local POOL = { "A", "B", "C", "D", "E", "F" }

local GOALS = {
	{ Id = "Cure3", Kind = "Cure", Target = 3, Icon = "😊", Reward = { Cash = 30, Stars = 1 } },
	{ Id = "Make2", Kind = "Make", Target = 2, Icon = "✨", Reward = { Cash = 20, Stars = 1 } },
	{ Id = "Night1", Kind = "CureNight", Target = 1, Icon = "🌙", Reward = { Cash = 50, Stars = 2 } },
	{ Id = "Bath2", Kind = "CureWing", Target = 2, Wing = "Bath", Icon = "🛁", Reward = { Cash = 40, Stars = 2 } },
}

local function fresh(): any
	return { Goals = {}, LastGrantDay = 0 }
end

local function holding(goals: { any }, lastGrantDay: number): any
	local copy = {}
	for i, goal in goals do
		copy[i] = { Id = goal.Id, Progress = goal.Progress or 0, Day = goal.Day or lastGrantDay }
	end
	return { Goals = copy, LastGrantDay = lastGrantDay }
end

local function ids(daily: any): { string }
	local out = {}
	for _, goal in daily.Goals do
		table.insert(out, goal.Id)
	end
	return out
end

local function progressOf(daily: any, id: string): number?
	for _, goal in daily.Goals do
		if goal.Id == id then
			return goal.Progress
		end
	end
	return nil
end

describe("day", function()
	test("unix time to the UTC day number", function()
		expect(Daily.day(0)).toBe(0)
		expect(Daily.day(86399)).toBe(0)
		expect(Daily.day(86400)).toBe(1)
		expect(Daily.day(20773 * 86400)).toBe(20773) -- 2026-11-16 00:00 UTC
		expect(Daily.day(20773 * 86400 + 86399)).toBe(20773) -- 23:59:59 the same day
	end)
end)

describe("visitor", function()
	test("is always one of the pool", function()
		for day = 20000, 20030 do
			expect(table.find(POOL, Daily.visitor(day, POOL)) ~= nil).toBeTruthy()
		end
	end)

	test("is stable for the same day", function()
		for day = 20770, 20780 do
			expect(Daily.visitor(day, POOL)).toBe(Daily.visitor(day, POOL))
		end
	end)

	test("changes across at least 3 of 7 days", function()
		local changes = 0
		local seen: { [string]: boolean } = {}
		local distinct = 0
		for day = 20773, 20779 do
			local visitor = Daily.visitor(day, POOL)
			if not seen[visitor] then
				seen[visitor] = true
				distinct += 1
			end
			if visitor ~= Daily.visitor(day - 1, POOL) then
				changes += 1
			end
		end
		expect(changes >= 3).toBeTruthy()
		expect(distinct >= 3).toBeTruthy()
	end)

	test("is never the same two days running", function()
		for day = 20000, 20400 do
			expect(Daily.visitor(day, POOL) ~= Daily.visitor(day + 1, POOL)).toBeTruthy()
		end
	end)

	test("meets every creature within any 2n - 1 days", function()
		for start = 20000, 20060 do
			local seen: { [string]: boolean } = {}
			for day = start, start + 2 * #POOL - 2 do
				seen[Daily.visitor(day, POOL)] = true
			end
			for _, id in POOL do
				expect(seen[id]).toBe(true)
			end
		end
	end)

	test("handles tiny pools", function()
		expect(Daily.visitor(20773, {})).toBe("")
		expect(Daily.visitor(20773, { "Solo" })).toBe("Solo")
		expect(Daily.visitor(20773, { "A", "B" }) ~= Daily.visitor(20774, { "A", "B" })).toBeTruthy()
	end)
end)

describe("grant", function()
	test("a brand-new player gets one goal on their first day", function()
		local daily = Daily.grant(fresh(), 100, GOALS, 3)
		expect(#daily.Goals).toBe(1)
		expect(daily.LastGrantDay).toBe(100)
		expect(daily.Goals[1].Progress).toBe(0)
		expect(daily.Goals[1].Day).toBe(100)
	end)

	test("the same day again adds nothing", function()
		local once = Daily.grant(fresh(), 100, GOALS, 3)
		local twice = Daily.grant(once, 100, GOALS, 3)
		expect(twice).toEqual(once)
	end)

	test("adds one goal per new day, up to max 3", function()
		local daily = Daily.grant(fresh(), 100, GOALS, 3)
		daily = Daily.grant(daily, 101, GOALS, 3)
		expect(#daily.Goals).toBe(2)
		daily = Daily.grant(daily, 102, GOALS, 3)
		expect(#daily.Goals).toBe(3)
		daily = Daily.grant(daily, 103, GOALS, 3)
		expect(#daily.Goals).toBe(3)
		expect(daily.LastGrantDay).toBe(103)
	end)

	test("days away bank up to the max (no streak lost, nothing expires)", function()
		local daily = Daily.grant(holding({ { Id = "Cure3", Progress = 1 } }, 100), 105, GOALS, 3)
		expect(#daily.Goals).toBe(3)
		expect(progressOf(daily, "Cure3")).toBe(1)
	end)

	test("never removes or resets progress", function()
		local before = holding({ { Id = "Cure3", Progress = 2 }, { Id = "Make2", Progress = 1 } }, 100)
		local daily = Daily.grant(before, 101, GOALS, 3)
		expect(daily.Goals[1]).toEqual({ Id = "Cure3", Progress = 2, Day = 100 })
		expect(daily.Goals[2]).toEqual({ Id = "Make2", Progress = 1, Day = 100 })
		expect(#daily.Goals).toBe(3)
	end)

	test("keeps goals over the max instead of removing them", function()
		local four = holding({ { Id = "Cure3" }, { Id = "Make2" }, { Id = "Night1" }, { Id = "Bath2" } }, 100)
		local daily = Daily.grant(four, 101, GOALS, 3)
		expect(#daily.Goals).toBe(4)
	end)

	test("does not hand out a goal you already hold", function()
		local daily = fresh()
		for day = 100, 102 do
			daily = Daily.grant(daily, day, GOALS, 3)
		end
		local seen: { [string]: boolean } = {}
		for _, id in ids(daily) do
			expect(seen[id]).toBeNil()
			seen[id] = true
		end
	end)

	test("adds nothing when every goal in the pool is already held", function()
		local daily = Daily.grant(holding({ { Id = "Cure3" } }, 100), 101, { GOALS[1] }, 3)
		expect(ids(daily)).toEqual({ "Cure3" })
		expect(daily.LastGrantDay).toBe(101)
	end)

	test("a clock that goes backwards adds nothing", function()
		local daily = Daily.grant(holding({ { Id = "Cure3" } }, 100), 99, GOALS, 3)
		expect(#daily.Goals).toBe(1)
		expect(daily.LastGrantDay).toBe(100)
	end)

	test("does not change the table it was given", function()
		local before = holding({ { Id = "Cure3", Progress = 2 } }, 100)
		Daily.grant(before, 104, GOALS, 3)
		expect(before).toEqual(holding({ { Id = "Cure3", Progress = 2 } }, 100))
	end)

	test("works with the real goal pool", function()
		local daily = fresh()
		for day = 20773, 20775 do
			daily = Daily.grant(daily, day, DailyGoals, 3)
		end
		expect(#daily.Goals).toBe(3)
		for _, id in ids(daily) do
			expect(Daily.find(DailyGoals, id) ~= nil).toBeTruthy()
		end
	end)
end)

describe("onEvent", function()
	local function event(night: boolean?, wing: string?): any
		return { Pool = GOALS, Night = night, Wing = wing }
	end

	test("a cure raises Cure progress", function()
		local daily = Daily.onEvent(holding({ { Id = "Cure3" } }, 100), "Cure", event(false, "Starter"))
		expect(progressOf(daily, "Cure3")).toBe(1)
	end)

	test("a night cure raises CureNight; a day cure doesn't", function()
		local start = holding({ { Id = "Night1" } }, 100)
		expect(progressOf(Daily.onEvent(start, "Cure", event(false, "Starter")), "Night1")).toBe(0)
		expect(progressOf(Daily.onEvent(start, "Cure", event(true, "Night")), "Night1")).toBe(1)
	end)

	test("CureWing counts only its own wing", function()
		local start = holding({ { Id = "Bath2" } }, 100)
		expect(progressOf(Daily.onEvent(start, "Cure", event(false, "Starter")), "Bath2")).toBe(0)
		expect(progressOf(Daily.onEvent(start, "Cure", event(false, "Bath")), "Bath2")).toBe(1)
	end)

	test("one cure can fill several goals at once", function()
		local start = holding({ { Id = "Cure3" }, { Id = "Night1" } }, 100)
		local daily = Daily.onEvent(start, "Cure", event(true, "Night"))
		expect(progressOf(daily, "Cure3")).toBe(1)
		expect(progressOf(daily, "Night1")).toBe(1)
	end)

	test("Make raises Make goals only", function()
		local start = holding({ { Id = "Cure3" }, { Id = "Make2" } }, 100)
		local daily = Daily.onEvent(start, "Make", { Pool = GOALS })
		expect(progressOf(daily, "Make2")).toBe(1)
		expect(progressOf(daily, "Cure3")).toBe(0)
	end)

	test("progress stops at the target", function()
		local daily = Daily.onEvent(holding({ { Id = "Night1", Progress = 1 } }, 100), "Cure", event(true, "Night"))
		expect(progressOf(daily, "Night1")).toBe(1)
	end)

	test("unknown kinds, unknown goals and a missing pool change nothing", function()
		local start = holding({ { Id = "Cure3" }, { Id = "Gone" } }, 100)
		expect(Daily.onEvent(start, "Dance", event(false, "Starter"))).toEqual(start)
		expect(Daily.onEvent(start, "Cure", {} :: any)).toEqual(start)
		expect(progressOf(Daily.onEvent(start, "Cure", event(false, "Starter")), "Gone")).toBe(0)
	end)

	test("does not change the table it was given", function()
		local start = holding({ { Id = "Cure3" } }, 100)
		Daily.onEvent(start, "Cure", event(false, "Starter"))
		expect(progressOf(start, "Cure3")).toBe(0)
	end)
end)

describe("claim", function()
	test("before the target: no reward and the goal stays", function()
		local start = holding({ { Id = "Cure3", Progress = 2 } }, 100)
		local daily, reward = Daily.claim(start, 1, GOALS)
		expect(reward).toBeNil()
		expect(daily).toEqual(start)
	end)

	test("at the target: the reward, and the goal is removed", function()
		local start =
			holding({ { Id = "Make2", Progress = 0 }, { Id = "Cure3", Progress = 3 }, { Id = "Night1" } }, 100)
		local daily, reward = Daily.claim(start, 2, GOALS)
		expect(reward).toEqual({ Cash = 30, Stars = 1 })
		expect(ids(daily)).toEqual({ "Make2", "Night1" })
	end)

	test("bad indexes give nothing", function()
		local start = holding({ { Id = "Cure3", Progress = 3 } }, 100)
		for _, index in { 0, 2, -1, 1.5, 0 / 0, math.huge } do
			local daily, reward = Daily.claim(start, index, GOALS)
			expect(reward).toBeNil()
			expect(daily).toEqual(start)
		end
		local _, reward = Daily.claim(start, "1" :: any, GOALS)
		expect(reward).toBeNil()
	end)

	test("a goal missing from the pool gives nothing", function()
		local _, reward = Daily.claim(holding({ { Id = "Gone", Progress = 99 } }, 100), 1, GOALS)
		expect(reward).toBeNil()
	end)

	test("does not change the table it was given, or hand out the data table", function()
		local start = holding({ { Id = "Cure3", Progress = 3 } }, 100)
		local _, reward = Daily.claim(start, 1, GOALS)
		expect(#start.Goals).toBe(1)
		expect(reward ~= GOALS[1].Reward).toBeTruthy()
	end)
end)

describe("mailbox", function()
	test("mailboxReady is false the same day and true on a later day", function()
		expect(Daily.mailboxReady(5, 5)).toBe(false)
		expect(Daily.mailboxReady(4, 5)).toBe(true)
		expect(Daily.mailboxReady(0, 20773)).toBe(true)
		expect(Daily.mailboxReady(6, 5)).toBe(false)
	end)

	test("the gift is the same however long you were away", function()
		expect(Daily.mailboxGift(4, 5, 25)).toBe(25)
		expect(Daily.mailboxGift(1, 11, 25)).toBe(25)
		expect(Daily.mailboxGift(0, 20773, 25)).toBe(25)
		expect(Daily.mailboxGift(5, 5, 25)).toBe(0)
	end)
end)

describe("goal helpers", function()
	test("eligible drops CureWing goals for wings you can't treat yet", function()
		local starterOnly = Daily.eligible(GOALS, { Starter = true })
		local found: { [string]: boolean } = {}
		for _, def in starterOnly do
			found[def.Id] = true
		end
		expect(found).toEqual({ Cure3 = true, Make2 = true, Night1 = true })
		expect(#Daily.eligible(GOALS, { Starter = true, Bath = true })).toBe(4)
	end)

	test("eligible on the real pool: a new clinic never gets Bath or Snow goals", function()
		for _, def in Daily.eligible(DailyGoals, { Starter = true, Night = true }) do
			expect(def.Wing == nil or def.Wing == "Starter" or def.Wing == "Night").toBeTruthy()
		end
	end)

	test("prune drops goals that no longer exist and keeps the rest", function()
		local start = holding({ { Id = "Gone" }, { Id = "Cure3", Progress = 2 } }, 100)
		local daily = Daily.prune(start, GOALS)
		expect(ids(daily)).toEqual({ "Cure3" })
		expect(progressOf(daily, "Cure3")).toBe(2)
		expect(daily.LastGrantDay).toBe(100)
		expect(#start.Goals).toBe(2)
	end)

	test("readyCount counts goals at their target", function()
		local daily = holding(
			{ { Id = "Cure3", Progress = 3 }, { Id = "Make2", Progress = 1 }, { Id = "Night1", Progress = 1 } },
			1
		)
		expect(Daily.readyCount(daily, GOALS)).toBe(2)
	end)

	test("find looks a goal up by Id", function()
		expect((Daily.find(GOALS, "Make2") :: any).Target).toBe(2)
		expect(Daily.find(GOALS, "Nope")).toBeNil()
	end)
end)

-- What Server/Daily asks: can this clinic (its level and rooms) treat this case? (Logic/Visit.canTreat, with the
-- Building's stations by level, the pantry's two once their room is owned.)
local function clinic(level: number, rooms: { [string]: boolean }): (string) -> boolean
	local function open(stationId: string): boolean
		if Building.stationOpen(stationId, level, rooms) then
			return true
		end
		for roomId, owned in rooms do
			if owned and table.find(Rooms[roomId].Stations, stationId) then
				return true
			end
		end
		return false
	end
	return function(caseId: string): boolean
		return Visit.canTreat(rawget(Cases :: any, caseId), level, rooms, open, Items)
	end
end

describe("the Real Clinic's visitor pool and wings", function()
	test("the visitor pool comes from patient -> wing: day patients of the road wings, in Patients.Order", function()
		local pool = Daily.visitorPool(Patients, Wings)
		expect(pool).toEqual({
			"DumplingFrog",
			"CloudSheep",
			"ToastPup",
			"JellyBun",
			"SlimeCat",
			"MossMole",
			"SnowconePenguin",
			"IcicleOwl",
		})
		for _, id in pool do
			local patient = Patients[id]
			expect(patient.Night).toBeNil() -- never a night patient
			expect(Wings[patient.Wing].Rebirths).toBeNil() -- never Sunny (R1) or Sky (R2, helicopter only)
			expect(Wings[patient.Wing].Only).toBeNil()
			expect(Cases.POOLS[patient.Wing] ~= nil).toBe(true) -- it rolls its case from its wing's pool
		end
		expect(Daily.visitorPool({}, Wings)).toEqual({})
		expect(Daily.visitorPool(nil, nil)).toEqual({})
	end)

	test("treatableWings: a fresh Lv 1 clinic treats the Meadow, the night and the Sunny pools", function()
		expect(Daily.treatableWings(Cases.POOLS, Cases, clinic(1, { Stand = true }))).toEqual({
			Starter = true,
			Night = true,
			Sunny = true, -- a cut knee is Lv 1 (its patients still need R1: Data/Wings)
		})
	end)

	test("treatableWings: a Bath or Winter wing waits for its room, as it always has; Sky for Lv 5", function()
		local bath = Daily.treatableWings(Cases.POOLS, Cases, clinic(1, { Stand = true, BathRoom = true }))
		expect(bath.Bath).toBe(true)
		expect(bath.Winter).toBeNil()
		local winter = Daily.treatableWings(Cases.POOLS, Cases, clinic(2, { Stand = true, WinterWing = true }))
		expect(winter.Winter).toBe(true)
		expect(winter.Bath).toBeNil()
		expect(Daily.treatableWings(Cases.POOLS, Cases, clinic(4, { Stand = true })).Sky).toBeNil()
		expect(Daily.treatableWings(Cases.POOLS, Cases, clinic(5, { Stand = true })).Sky).toBe(true)
	end)

	test("treatableWings and eligible together: a new clinic gets no Bath or Snow goal", function()
		local wings = Daily.treatableWings(Cases.POOLS, Cases, clinic(1, { Stand = true }))
		for _, def in Daily.eligible(DailyGoals, wings) do
			expect(def.Wing == nil or def.Wing == "Starter").toBe(true)
		end
	end)

	test("treatableWings: junk gives no wings, and a case nobody can treat counts for nothing", function()
		expect(Daily.treatableWings(nil, Cases, clinic(1, {}))).toEqual({})
		expect(Daily.treatableWings(Cases.POOLS, Cases, nil :: any)).toEqual({})
		expect(Daily.treatableWings(Cases.POOLS, Cases, function()
			return false
		end)).toEqual({})
		expect(Daily.treatableWings({ Starter = { "Nope", 7 } } :: any, Cases, function()
			return true
		end)).toEqual({})
	end)
end)

describe("dates", function()
	test("dateDay turns a UTC date into a day number", function()
		expect(Daily.dateDay("1970-01-01")).toBe(0)
		expect(Daily.dateDay("2000-02-29")).toBe(11016)
		expect(Daily.dateDay("2026-11-16")).toBe(20773)
		expect(Daily.dateDay("2026-12-01")).toBe(20788)
		expect(Daily.dateDay("2027-01-10")).toBe(20828)
	end)

	test("dateDay rejects dates that don't exist", function()
		for _, text in { "2026-02-30", "2025-02-29", "2026-13-01", "2026-00-10", "junk", "", "2026-1-1" } do
			expect(Daily.dateDay(text)).toBeNil()
		end
	end)

	test("inWindow is inclusive at both ends", function()
		local winter = { Start = "2026-12-01", End = "2027-01-10" }
		expect(Daily.inWindow(20787, winter)).toBe(false)
		expect(Daily.inWindow(20788, winter)).toBe(true)
		expect(Daily.inWindow(20800, winter)).toBe(true)
		expect(Daily.inWindow(20828, winter)).toBe(true)
		expect(Daily.inWindow(20829, winter)).toBe(false)
	end)

	test("a broken window is never on", function()
		expect(Daily.inWindow(20800, { Start = "soon", End = "2027-01-10" })).toBe(false)
		expect(Daily.inWindow(20800, nil :: any)).toBe(false)
	end)
end)
