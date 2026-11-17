--!nocheck
-- The HUD's level bar (Logic/LevelBar): Joshua, 2026-11-17: "how to level up ... is there a level up bar. where to
-- see my level?". One bar that counts BOTH things the next hospital level needs (its Clinic Stars, a gate that is
-- kept, and its Cash, which is spent). Every number is read from Data/Levels, never typed here twice.

local T = require("./expect")
local expect, test = T.expect, T.test

local LevelBar = require("../src/shared/Logic/LevelBar")
local Levels = require("../src/shared/Logic/Levels")
local LevelsData = require("../src/shared/Data/Levels")
local Rooms = require("../src/shared/Data/Rooms")

local function state(level, stars, cash)
	return { Level = level, Stars = stars, Cash = cash }
end

T.describe("LevelBar.view", function()
	test("a fresh Lv 1 clinic: the level, its name, both needs read from Data/Levels", function()
		local view = LevelBar.view(state(1, 0, 0), LevelsData)
		expect(view.Level).toBe(1)
		expect(view.Name).toBe(LevelsData[1].Name)
		expect(view.Max).toBe(false)
		expect(view.Ready).toBe(false)
		expect(view.Fraction).toBe(0)
		expect(view.Stars).toEqual({ Have = 0, Need = LevelsData[2].Stars })
		expect(view.Cash).toEqual({ Have = 0, Need = LevelsData[2].Cash })
		expect(view.NextLevel).toBe(2)
		expect(view.NextName).toBe(LevelsData[2].Name)
	end)

	test("the rule: the average of the two shares, each capped at 1", function()
		local row = LevelsData[2]
		expect(LevelBar.view(state(1, row.Stars, 0), LevelsData).Fraction).toBeCloseTo(0.5)
		expect(LevelBar.view(state(1, 0, row.Cash), LevelsData).Fraction).toBeCloseTo(0.5)
		expect(LevelBar.view(state(1, row.Stars * 10, 0), LevelsData).Fraction).toBeCloseTo(0.5) -- capped
		expect(LevelBar.view(state(1, row.Stars / 3, row.Cash / 2), LevelsData).Fraction).toBeCloseTo(
			(math.floor(row.Stars / 3) / row.Stars + 0.5) / 2
		)
		expect(LevelBar.fraction(12, 15, 300, 400)).toBeCloseTo((12 / 15 + 300 / 400) / 2)
		expect(LevelBar.fraction(0, 0, 0, 0)).toBe(1) -- nothing needed
		expect(LevelBar.fraction(nil, 15, 0 / 0, 400)).toBe(0) -- junk reads as nothing
		expect(LevelBar.fraction(-5, 15, -5, 400)).toBe(0)
	end)

	test("the bar is full exactly when the Shop's button works (Logic/Levels.canLevelUp), at every level", function()
		for level = 1, Levels.max(LevelsData) - 1 do
			local row = LevelsData[level + 1]
			for _, stars in { 0, row.Stars - 1, row.Stars, row.Stars + 50 } do
				for _, cash in { 0, row.Cash - 1, row.Cash, row.Cash * 3 } do
					local data = state(level, stars, cash)
					local view = LevelBar.view(data, LevelsData)
					local ok = Levels.canLevelUp(data, LevelsData)
					expect(view.Ready).toBe(ok)
					expect(view.Fraction >= 1).toBe(ok)
					expect(view.Fraction >= 0 and view.Fraction <= 1).toBe(true)
				end
			end
		end
	end)

	test("the count never reads past its need", function()
		local row = LevelsData[2]
		local view = LevelBar.view(state(1, row.Stars + 30, row.Cash - 100), LevelsData)
		expect(view.Stars).toEqual({ Have = row.Stars, Need = row.Stars })
		expect(view.Cash).toEqual({ Have = row.Cash - 100, Need = row.Cash })
		expect(view.Ready).toBe(false)
	end)

	test("the top level: Max, a full bar, no needs; a bigger or junk level is clamped", function()
		local top = Levels.max(LevelsData)
		local view = LevelBar.view(state(top, 0, 0), LevelsData)
		expect(view.Max).toBe(true)
		expect(view.Ready).toBe(false)
		expect(view.Fraction).toBe(1)
		expect(view.Stars).toBeNil()
		expect(view.NextLevel).toBeNil()
		expect(view.Name).toBe(LevelsData[top].Name)
		expect(LevelBar.view(state(99, 0, 0), LevelsData).Level).toBe(top)
		expect(LevelBar.view(state("two", 0, 0), LevelsData).Level).toBe(1)
		expect(LevelBar.view(nil, LevelsData).Level).toBe(1)
		expect(LevelBar.view({}, LevelsData).Fraction).toBe(0)
	end)
end)

T.describe("LevelBar words", function()
	test("the counts, 'Level up!' when both are met, 'Max level' at the top", function()
		local row = LevelsData[2]
		local view = LevelBar.view(state(1, 12, 300), LevelsData)
		expect(LevelBar.label(view)).toBeNil()
		expect(LevelBar.text(view)).toBe("⭐ 12/" .. row.Stars .. " · 💰 300/" .. row.Cash)
		expect(LevelBar.parts(view)).toEqual({
			{ Unit = "Stars", Text = "12/" .. row.Stars },
			{ Unit = "Cash", Text = "300/" .. row.Cash },
		})
		local ready = LevelBar.view(state(1, row.Stars, row.Cash), LevelsData)
		expect(LevelBar.label(ready)).toBe("Level up!")
		expect(LevelBar.text(ready)).toBe("Level up!")
		local top = LevelBar.view(state(Levels.max(LevelsData), 9999, 99999), LevelsData)
		expect(LevelBar.label(top)).toBe("Max level")
		expect(LevelBar.text(top)).toBe("Max level")
		expect(LevelBar.parts(top)).toEqual({})
	end)

	test("a tap on the bar says what the next level is and what it needs", function()
		local row = LevelsData[2]
		local view = LevelBar.view(state(1, 12, 300), LevelsData)
		expect(LevelBar.nextText(view)).toBe("Lv 2 " .. row.Name .. ": ⭐ 12/" .. row.Stars .. " · 💰 300/" .. row.Cash)
		expect(LevelBar.nextText(LevelBar.view(state(1, row.Stars, row.Cash), LevelsData))).toBe("Level up in the Shop!")
		expect(LevelBar.nextText(LevelBar.view(state(5, 0, 0), LevelsData))).toBe("Max level")
	end)

	test("a format writes the big numbers", function()
		local function commas(n)
			return "<" .. n .. ">"
		end
		local row = LevelsData[5]
		local view = LevelBar.view(state(4, 150, 7000), LevelsData)
		expect(LevelBar.parts(view, commas)[2].Text).toBe("<7000>/<" .. row.Cash .. ">")
	end)

	test("it never says everything is unlocked: no such words at any level, Stars or Cash", function()
		for level = 1, Levels.max(LevelsData) do
			for _, stars in { 0, 15, 45, 100, 200, 99999 } do
				for _, cash in { 0, 400, 99999999 } do
					local view = LevelBar.view(state(level, stars, cash), LevelsData)
					for _, text in { LevelBar.text(view), LevelBar.nextText(view), LevelBar.label(view) or "" } do
						expect(string.find(string.lower(text), "everything", 1, true)).toBeNil()
						expect(string.find(string.lower(text), "unlocked", 1, true)).toBeNil()
					end
					-- and below the top level it never says Max either: the level still has to be bought
					if level < Levels.max(LevelsData) then
						expect(string.find(LevelBar.text(view), "Max", 1, true)).toBeNil()
					end
				end
			end
		end
	end)

	test("every word is short (6 words or fewer) and nothing mentions Robux", function()
		for _, text in LevelBar.TEXT do
			local words = 0
			for _ in string.gmatch(text, "%S+") do
				words += 1
			end
			expect(words <= 6).toBe(true)
			expect(string.find(string.lower(text), "robux", 1, true)).toBeNil()
		end
	end)
end)

T.describe("LevelBar: everything", function()
	test("only the top level AND every priced room owned", function()
		local owned = {}
		for _, roomId in Rooms.Order do
			if Rooms[roomId].Price > 0 then
				owned[roomId] = true
			end
		end
		local top = LevelBar.view(state(Levels.max(LevelsData), 0, 0), LevelsData)
		local low = LevelBar.view(state(1, 9999, 999999), LevelsData)
		expect(LevelBar.allRooms(owned, Rooms)).toBe(true)
		expect(LevelBar.everything(top, owned, Rooms)).toBe(true)
		expect(LevelBar.everything(low, owned, Rooms)).toBe(false) -- every Star passed, the level not bought
		local missing = table.clone(owned)
		missing[next(owned)] = nil
		expect(LevelBar.allRooms(missing, Rooms)).toBe(false)
		expect(LevelBar.everything(top, missing, Rooms)).toBe(false)
		expect(LevelBar.allRooms(nil, Rooms)).toBe(false)
		expect(LevelBar.allRooms(owned, nil)).toBe(false)
	end)
end)
