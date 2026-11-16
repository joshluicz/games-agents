--!strict
-- Hospital levels (depth-update build plan §B5/§B7).

local T = require("./expect")
local expect, test = T.expect, T.test

local Levels = require("../src/shared/Logic/Levels")
local Schema = require("../src/shared/Logic/Schema")
local Progress = require("../src/shared/Logic/Progress")
local LevelsData = require("../src/shared/Data/Levels")
local Rooms = require("../src/shared/Data/Rooms")

local function save(level: number, stars: number, cash: number): Schema.Data
	local data = Schema.default()
	data.Level = level
	data.Stars = stars
	data.Cash = cash
	return data
end

T.describe("Levels", function()
	test("the design's ladder", function()
		expect(Levels.max(LevelsData)).toBe(5)
		local rows = {}
		for index, row in LevelsData do
			rows[index] = { row.Stars, row.Cash, row.Slots, row.Beds, row.Queue, row.RecipeCap }
		end
		expect(rows).toEqual({
			{ 0, 0, 1, 1, 4, 1 },
			{ 15, 400, 2, 2, 4, 2 },
			{ 45, 1500, 3, 2, 5, 3 },
			{ 100, 5000, 4, 3, 5, 3 },
			{ 200, 15000, 5, 3, 6, 3 },
		})
		expect(LevelsData[1].Name).toBe("First-Aid Stand")
		expect(LevelsData[5].Name).toBe("Mega Hospital")
	end)

	test("slots equal the level (Schema caps Equipped by Level)", function()
		for index, row in LevelsData do
			expect(row.Slots).toBe(index)
		end
		expect(Schema.MAX_LEVEL).toBe(Levels.max(LevelsData))
	end)

	test("unlock chips are short", function()
		for _, row in LevelsData do
			for _, chip in row.Unlocks do
				local words = 0
				for _ in string.gmatch(chip, "%S+") do
					words += 1
				end
				expect(words <= 4).toBe(true)
			end
		end
	end)

	test("clamp, row and nextRow", function()
		expect(Levels.clamp(LevelsData, 0)).toBe(1)
		expect(Levels.clamp(LevelsData, 9)).toBe(5)
		expect(Levels.clamp(LevelsData, "x")).toBe(1)
		expect(Levels.row(LevelsData, 3).Name).toBe("Hospital")
		expect((Levels.nextRow(LevelsData, 1) :: any).Name).toBe("Clinic")
		expect(Levels.nextRow(LevelsData, 5)).toBeNil()
	end)

	test("canLevelUp: max, then stars (a gate), then cash", function()
		local ok, message = Levels.canLevelUp(save(1, 15, 400), LevelsData)
		expect(ok).toBe(true)
		expect(message).toBe("")
		ok, message = Levels.canLevelUp(save(1, 14, 9999), LevelsData)
		expect(ok).toBe(false)
		expect(message).toBe("Need ⭐15")
		ok, message = Levels.canLevelUp(save(2, 45, 1499), LevelsData)
		expect(ok).toBe(false)
		expect(message).toBe("Need 💰1500")
		ok, message = Levels.canLevelUp(save(5, 999, 99999), LevelsData)
		expect(ok).toBe(false)
		expect(message).toBe("Max level!")
		expect((Levels.canLevelUp(nil, LevelsData))).toBe(false)
	end)

	test("slots, beds, queue and recipe cap by level", function()
		expect(Levels.slots(LevelsData, 3)).toBe(3)
		expect(Levels.beds(LevelsData, 4)).toBe(3)
		expect(Levels.queue(LevelsData, 5)).toBe(6)
		expect(Levels.recipeCap(LevelsData, 1)).toBe(1)
		expect(Levels.recipeCap(LevelsData, 2)).toBe(2)
		expect(Levels.recipeCap(LevelsData, 99)).toBe(3)
	end)

	test("Schema.ROOM_LEVELS matches impliedByRoom for every room", function()
		for _, roomId in Rooms.Order do
			local implied = Levels.impliedByRoom(LevelsData, Rooms[roomId])
			if roomId ~= "Stand" then
				expect(Schema.ROOM_LEVELS[roomId]).toBe(implied)
			else
				expect(implied).toBe(1)
			end
		end
	end)

	test("the Garden needs the Hospital", function()
		expect(Rooms.Garden.Level).toBe(3)
		expect(Levels.roomAllowed(Rooms.Garden, 2)).toBe(false)
		expect(Levels.roomAllowed(Rooms.Garden, 3)).toBe(true)
		expect(Levels.roomAllowed(Rooms.BathRoom, 1)).toBe(true)
		local ok, message = Progress.canBuyRoom(save(2, 999, 9999), Rooms.Garden, "Garden")
		expect(ok).toBe(false)
		expect(message).toBe("Needs 🏥 Lv 3")
		expect((Progress.canBuyRoom(save(3, 999, 9999), Rooms.Garden, "Garden"))).toBe(true)
	end)
end)
