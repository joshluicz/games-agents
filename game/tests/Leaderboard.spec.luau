--!strict
-- Leaderboard rules: UTC week keys, store names, values from the save, the write throttle's "what changed",
-- backoff, permanent errors, and the live merge and rank behind "You: #12".

local T = require("./expect")
local expect, test, describe = T.expect, T.test, T.describe

local Leaderboard = require("../src/shared/Logic/Leaderboard")
local Schema = require("../src/shared/Logic/Schema")

local DAY = 86400
-- 2026-01-01 is day 20454 (a Thursday, like 1970-01-01); 2026-11-16 is day 20773, a Monday.
local MONDAY_2026_11_16 = 20773 * DAY

describe("Leaderboard week", function()
	test("weeks start on Monday 00:00 UTC", function()
		expect(Leaderboard.week(4 * DAY)).toBe(1) -- 1970-01-05, the first Monday
		expect(Leaderboard.week(4 * DAY - 1)).toBe(0) -- the Sunday before
		expect(Leaderboard.week(0)).toBe(0)
	end)

	test("2026-11-16 starts week 2968", function()
		expect(Leaderboard.week(MONDAY_2026_11_16)).toBe(2968)
		expect(Leaderboard.week(MONDAY_2026_11_16 - 1)).toBe(2967) -- Sunday 23:59:59
		expect(Leaderboard.week(MONDAY_2026_11_16 + 7 * DAY - 1)).toBe(2968) -- the next Sunday 23:59:59
		expect(Leaderboard.week(MONDAY_2026_11_16 + 7 * DAY)).toBe(2969)
	end)
end)

describe("Leaderboard store names", function()
	test("all-time boards have no week; the weekly board does", function()
		expect(Leaderboard.storeName("Cured", 2968, 1)).toBe("Board_Cured_v1")
		expect(Leaderboard.storeName("Hearts", 2968, 2)).toBe("Board_Hearts_v2")
		expect(Leaderboard.storeName("Week", 2968, 1)).toBe("Board_Week_v1_w2968")
		expect(Leaderboard.storeName("Week", 2969, 1)).toBe("Board_Week_v1_w2969")
	end)

	test("every name fits the 50-character DataStore limit", function()
		for id in Leaderboard.BOARDS do
			expect(#Leaderboard.storeName(id, 99999, 999) <= 50).toBe(true)
		end
	end)

	test("isBoard knows the ids", function()
		expect(Leaderboard.isBoard("Cured")).toBe(true)
		expect(Leaderboard.isBoard("Week")).toBe(true)
		expect(Leaderboard.isBoard("Nope")).toBe(false)
		expect(Leaderboard.isBoard(5)).toBe(false)
	end)
end)

describe("Leaderboard values", function()
	local function save()
		local data: any = Schema.default()
		data.Cured = 40
		data.Stars = 12
		data.HeartsReceived = 3
		data.WeekCures = { Week = 2968, Count = 9 }
		return data
	end

	test("read from the save", function()
		local data = save()
		expect(Leaderboard.valueOf("Cured", data, 2968)).toBe(40)
		expect(Leaderboard.valueOf("Stars", data, 2968)).toBe(12)
		expect(Leaderboard.valueOf("Hearts", data, 2968)).toBe(3)
		expect(Leaderboard.valueOf("Week", data, 2968)).toBe(9)
	end)

	test("this week's count is 0 once the week has moved on", function()
		expect(Leaderboard.valueOf("Week", save(), 2969)).toBe(0)
	end)

	test("bad numbers are nil or whole", function()
		local data = save()
		data.Cured = 0 / 0
		data.Stars = 7.9
		expect(Leaderboard.valueOf("Cured", data, 2968)).toBeNil()
		expect(Leaderboard.valueOf("Stars", data, 2968)).toBe(7)
		expect(Leaderboard.valueOf("Cured", "junk", 2968)).toBeNil()
	end)

	test("Rebirths: the save's Rebirth.Count, nil before v4 (Progression v2)", function()
		local data = save()
		expect(Leaderboard.valueOf("Rebirths", data, 2968)).toBe(0)
		data.Rebirth.Count = 4
		expect(Leaderboard.valueOf("Rebirths", data, 2968)).toBe(4)
		data.Rebirth = nil
		expect(Leaderboard.valueOf("Rebirths", data, 2968)).toBeNil()
		local board = Leaderboard.BOARDS.Rebirths
		expect({ board.Icon, board.Title, board.Caption, board.Color, board.Weekly }).toEqual({
			"🏢",
			"Most Rebirths",
			"Branches",
			"Purple",
			false,
		})
		expect(Leaderboard.storeName("Rebirths", 2968, 1)).toBe("Board_Rebirths_v1")
	end)

	test("Level and Journal only once the save has them", function()
		local data = save()
		data.Level = nil -- a save from before the depth update (Schema v2) has neither
		data.NurseIndex = nil
		expect(Leaderboard.valueOf("Level", data, 2968)).toBeNil()
		expect(Leaderboard.valueOf("Journal", data, 2968, { JournalTotal = 16 })).toBeNil()
		data.Level = 3
		data.NurseIndex = { A = "Hired", B = "Seen", C = "Hired", D = "Hired", E = "Hired" }
		expect(Leaderboard.valueOf("Level", data, 2968)).toBe(3)
		expect(Leaderboard.valueOf("Journal", data, 2968, { JournalTotal = 16 })).toBe(25)
		expect(Leaderboard.valueOf("Journal", data, 2968)).toBeNil() -- no total known
	end)

	test("values: one store per board, the weekly one named for its week", function()
		local values = Leaderboard.values({ "Cured", "Stars", "Hearts", "Week" }, save(), 2968, 1)
		expect(values).toEqual({
			Board_Cured_v1 = 40,
			Board_Stars_v1 = 12,
			Board_Hearts_v1 = 3,
			Board_Week_v1_w2968 = 9,
		})
	end)

	test("values: just after Monday 00:00, last week's final count goes to last week's board", function()
		local values = Leaderboard.values({ "Week" }, save(), 2969, 1)
		expect(values).toEqual({ Board_Week_v1_w2968 = 9 })
	end)

	test("values: an older week is left alone", function()
		local values = Leaderboard.values({ "Week" }, save(), 2970, 1)
		expect(values).toEqual({})
	end)

	test("values: unknown boards and boards the save can't fill are skipped", function()
		local old = save()
		old.Level = nil -- a pre-depth (v2) save: no hospital level to rank
		local values = Leaderboard.values({ "Nope", "Level", "Journal", "Cured" }, old, 2968, 1)
		expect(values).toEqual({ Board_Cured_v1 = 40 })
		-- a v3 save has a Level (1 at least), so that board applies to it
		expect(Leaderboard.values({ "Level" }, save(), 2968, 1)).toEqual({ Board_Level_v1 = 1 })
	end)
end)

describe("Leaderboard weekly count", function()
	test("counts up within a week", function()
		local entry = { Week = 2968, Count = 2 }
		Leaderboard.addWeekCure(entry, 2968)
		expect(entry).toEqual({ Week = 2968, Count = 3 })
	end)

	test("a new week starts again from 0", function()
		local entry = { Week = 2967, Count = 50 }
		Leaderboard.addWeekCure(entry, 2968)
		expect(entry).toEqual({ Week = 2968, Count = 1 })
	end)

	test("a fresh save's first cure", function()
		local entry = Schema.default().WeekCures
		Leaderboard.addWeekCure(entry, 2968)
		expect(entry).toEqual({ Week = 2968, Count = 1 })
	end)
end)

describe("Leaderboard write throttle", function()
	test("writes only what changed since the last write", function()
		local values = { Board_Cured_v1 = 40, Board_Stars_v1 = 12, Board_Hearts_v1 = 3 }
		expect(Leaderboard.changed({}, values)).toEqual({ "Board_Cured_v1", "Board_Hearts_v1", "Board_Stars_v1" })
		local written = { Board_Cured_v1 = 40, Board_Stars_v1 = 11, Board_Hearts_v1 = 3 }
		expect(Leaderboard.changed(written, values)).toEqual({ "Board_Stars_v1" })
		expect(Leaderboard.changed(values, values)).toEqual({})
	end)

	test("never writes a 0", function()
		expect(Leaderboard.changed({}, { Board_Hearts_v1 = 0, Board_Cured_v1 = 1 })).toEqual({ "Board_Cured_v1" })
	end)

	test("backoff doubles up to the cap", function()
		expect(Leaderboard.backoff(0, 30, 600)).toBe(0)
		expect(Leaderboard.backoff(1, 30, 600)).toBe(30)
		expect(Leaderboard.backoff(2, 30, 600)).toBe(60)
		expect(Leaderboard.backoff(4, 30, 600)).toBe(240)
		expect(Leaderboard.backoff(9, 30, 600)).toBe(600)
	end)

	test("permanent errors: Studio without API access, 403, not published", function()
		expect(Leaderboard.isPermanent("StudioAccessToApisNotAllowed: no")).toBe(true)
		expect(Leaderboard.isPermanent("403: Cannot write to DataStore from studio")).toBe(true)
		expect(Leaderboard.isPermanent("You must publish this place to the web to access DataStore.")).toBe(true)
		expect(Leaderboard.isPermanent("502: API Services rejected request")).toBe(false)
		expect(Leaderboard.isPermanent("301: GetSortedAsync request dropped. Request was throttled")).toBe(false)
	end)
end)

describe("Leaderboard admin exclusion", function()
	local live = { Studio = false, CreatorIsUser = true, CreatorId = 100, UserIds = { 311718381 } }

	test("the owner and Config.AdminUserIds are excluded on a live server", function()
		expect(Leaderboard.excluded(100, live)).toBe(true)
		expect(Leaderboard.excluded(311718381, live)).toBe(true)
		expect(Leaderboard.excluded(555, live)).toBe(false)
	end)

	test("a group-owned game has no owner account to exclude", function()
		local group = { Studio = false, CreatorIsUser = false, CreatorId = 100, UserIds = {} }
		expect(Leaderboard.excluded(100, group)).toBe(false)
	end)

	test("nobody is excluded in Studio", function()
		local studio = { Studio = true, CreatorIsUser = true, CreatorId = 100, UserIds = { 311718381 } }
		expect(Leaderboard.excluded(100, studio)).toBe(false)
		expect(Leaderboard.excluded(311718381, studio)).toBe(false)
	end)

	test("without() drops admins from a stored list, keeping the order", function()
		local entries = {
			{ UserId = 311718381, Value = 9000 },
			{ UserId = 7, Value = 50 },
			{ UserId = 100, Value = 40 },
			{ UserId = 8, Value = 30 },
		}
		expect(Leaderboard.without(entries, live)).toEqual({
			{ UserId = 7, Value = 50 },
			{ UserId = 8, Value = 30 },
		})
	end)
end)

describe("Leaderboard format", function()
	test("commas, then millions", function()
		expect(Leaderboard.format(0)).toBe("0")
		expect(Leaderboard.format(999)).toBe("999")
		expect(Leaderboard.format(1234)).toBe("1,234")
		expect(Leaderboard.format(999999)).toBe("999,999")
		expect(Leaderboard.format(1000000)).toBe("1M")
		expect(Leaderboard.format(1250000)).toBe("1.2M")
		expect(Leaderboard.format(0 / 0)).toBe("0")
		expect(Leaderboard.format("x")).toBe("0")
	end)
end)

describe("Leaderboard lists", function()
	test("parse keeps good rows in order, drops junk, stops at depth", function()
		local rows = {
			{ key = "111", value = 50 },
			{ key = "abc", value = 40 },
			{ key = "-5", value = 30 },
			{ key = "222", value = 0 / 0 },
			{ key = "333", value = 20 },
			{ key = "444", value = 10 },
		}
		expect(Leaderboard.parse(rows, 10)).toEqual({
			{ UserId = 111, Value = 50 },
			{ UserId = 333, Value = 20 },
			{ UserId = 444, Value = 10 },
		})
		expect(#Leaderboard.parse(rows, 2)).toBe(2)
		expect(Leaderboard.parse("junk", 10)).toEqual({})
	end)

	local stored = {
		{ UserId = 1, Value = 100 },
		{ UserId = 2, Value = 80 },
		{ UserId = 3, Value = 60 },
	}

	test("merge: a live value replaces the stored one and re-sorts", function()
		local merged = Leaderboard.merge(stored, { [3] = 90 }, 10)
		expect(merged).toEqual({
			{ UserId = 1, Value = 100 },
			{ UserId = 3, Value = 90 },
			{ UserId = 2, Value = 80 },
		})
		expect(Leaderboard.rankOf(merged, 3)).toBe(2)
	end)

	test("merge: a live player not written yet joins the list", function()
		local merged = Leaderboard.merge(stored, { [9] = 70 }, 10)
		expect(Leaderboard.rankOf(merged, 9)).toBe(3)
		expect(#merged).toBe(4)
	end)

	test("merge: a live 0 leaves the list (this week's board on Monday)", function()
		local merged = Leaderboard.merge(stored, { [1] = 0 }, 10)
		expect(Leaderboard.rankOf(merged, 1)).toBeNil()
		expect(#merged).toBe(2)
	end)

	test("merge: trimmed to depth, so a low score has no rank", function()
		local merged = Leaderboard.merge(stored, { [9] = 5 }, 3)
		expect(#merged).toBe(3)
		expect(Leaderboard.rankOf(merged, 9)).toBeNil()
	end)

	test("merge: ties keep a fixed order and the input is untouched", function()
		local merged = Leaderboard.merge(stored, { [7] = 80 }, 10)
		expect(Leaderboard.rankOf(merged, 2)).toBe(2)
		expect(Leaderboard.rankOf(merged, 7)).toBe(3)
		expect(stored[3]).toEqual({ UserId = 3, Value = 60 })
	end)
end)
