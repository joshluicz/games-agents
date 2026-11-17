--!strict
-- Hospital levels (depth-update build plan §B5/§B7; Progression v2 build plan §B5: slots are gone, departments and
-- the ward floor at Lv 2; Real Clinic build plan contract C3 and design §10: the new names, Bays, Beds = ward beds).

local T = require("./expect")
local expect, test = T.expect, T.test

local Levels = require("../src/shared/Logic/Levels")
local Schema = require("../src/shared/Logic/Schema")
local Progress = require("../src/shared/Logic/Progress")
local LevelsData = require("../src/shared/Data/Levels")
local Rooms = require("../src/shared/Data/Rooms")
local fs = require("@lune/fs")

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
			rows[index] = { row.Stars, row.Cash, row.Floors, row.Beds, row.Queue, row.RecipeCap }
			expect((row :: any).Slots).toBeNil() -- Progression v2: every nurse you own works
		end
		-- the gates, costs, floors, line and plan caps are unchanged; Beds now counts ward beds upstairs
		expect(rows).toEqual({
			{ 0, 0, 0, 0, 3, 1 },
			{ 15, 400, 1, 3, 3, 2 },
			{ 45, 1500, 2, 5, 3, 3 },
			{ 100, 5000, 3, 7, 3, 3 },
			{ 200, 15000, 4, 7, 3, 3 },
		})
	end)

	test("the Real Clinic's names and open bays (design §10)", function()
		local names, bays = {}, {}
		for index, row in LevelsData do
			names[index] = row.Name
			bays[index] = row.Bays
			expect(type(row.Icon) == "string" and row.Icon ~= "").toBe(true)
			expect(row.Icon ~= "🧰").toBe(true) -- the kit went with the First-Aid Stand
		end
		expect(names).toEqual({ "Clinic", "Medical Centre", "Hospital", "General Hospital", "City Hospital" })
		expect(bays).toEqual({ 2, 3, 4, 5, 6 })
		-- a bigger clinic never has fewer bays or beds
		for index = 2, #LevelsData do
			expect(LevelsData[index].Bays > LevelsData[index - 1].Bays).toBe(true)
			expect(LevelsData[index].Beds >= LevelsData[index - 1].Beds).toBe(true)
		end
	end)

	test("departments open level by level (Progression v2 §B5), and Schema.MAX_LEVEL is the top", function()
		local opened = {}
		for index = 1, Levels.max(LevelsData) do
			opened[index] = Levels.departments(LevelsData, index)
		end
		expect(opened).toEqual({
			{ "Reception", "Pharmacy" }, -- the supply shelf and the dispensary are open from the start
			{ "Reception", "Pharmacy", "AE", "Wards" },
			{ "Reception", "Pharmacy", "AE", "Wards", "Imaging", "Rest" },
			{ "Reception", "Pharmacy", "AE", "Wards", "Imaging", "Rest" },
			{ "Reception", "Pharmacy", "AE", "Wards", "Imaging", "Rest", "Roof" },
		})
		expect(Schema.MAX_LEVEL).toBe(Levels.max(LevelsData))
		-- a copy: changing it never changes Data
		local copy = Levels.departments(LevelsData, 1)
		table.insert(copy, "Junk")
		expect(#Levels.departments(LevelsData, 1)).toBe(2)
	end)

	test("the unlock chips: what each level opens (design §10)", function()
		expect(LevelsData[1].Unlocks).toEqual({})
		expect(LevelsData[2].Unlocks).toEqual({
			"🚑 A&E ambulances",
			"🛏️ Injury Ward upstairs",
			"🧻 Bandages",
			"📋 2-step plans",
		})
		expect(LevelsData[3].Unlocks).toEqual({
			"📸 X-ray room",
			"😴 Rest Ward",
			"🔀 Pick the ward",
			"📋 3-step plans",
			"🌻 Garden",
		})
		expect(LevelsData[4].Unlocks).toEqual({ "🛋️ Staff room", "🛏️ 7 ward beds", "🚪 5 exam bays" })
		expect(LevelsData[5].Unlocks).toEqual({
			"🚁 Helipad",
			"🚪 6 exam bays",
			"✨ Neon sign",
			"🏢 New branches",
		})
		-- a chip never promises what the level doesn't have, and never says "cure"
		expect(LevelsData[4].Beds).toBe(7)
		expect({ LevelsData[4].Bays, LevelsData[5].Bays }).toEqual({ 5, 6 })
		for _, row in LevelsData do
			for _, chip in row.Unlocks do
				expect(string.find(string.lower(chip), "cure", 1, true)).toBeNil()
			end
		end
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
		expect(Levels.row(LevelsData, 1).Name).toBe("Clinic")
		expect((Levels.nextRow(LevelsData, 1) :: any).Name).toBe("Medical Centre")
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

	test("floors, beds, queue and recipe cap by level", function()
		expect((Levels :: any).slots).toBeNil()
		expect(Levels.floors(LevelsData, 1)).toBe(0)
		expect(Levels.floors(LevelsData, 5)).toBe(4)
		expect(Levels.floors(LevelsData, 99)).toBe(4)
		expect(Levels.beds(LevelsData, 1)).toBe(0)
		expect(Levels.beds(LevelsData, 4)).toBe(7)
		expect(Levels.queue(LevelsData, 5)).toBe(3) -- the line is 3 at every level (Config.MaxQueue)
		expect(Levels.recipeCap(LevelsData, 1)).toBe(1)
		expect(Levels.recipeCap(LevelsData, 2)).toBe(2)
		expect(Levels.recipeCap(LevelsData, 99)).toBe(3)
	end)

	test("each level brings patients faster (spawnSeconds), Lv 1 at Config's 13 s", function()
		local last = math.huge
		for level = 1, Levels.max(LevelsData) do
			local seconds = Levels.spawnSeconds(LevelsData, level)
			expect(seconds < last).toBe(true)
			expect(seconds >= 1).toBe(true)
			last = seconds
		end
		expect(Levels.spawnSeconds(LevelsData, 1)).toBe(13)
		expect(Levels.spawnSeconds(LevelsData, 5)).toBe(8)
		expect(Levels.spawnSeconds(LevelsData, 0 / 0)).toBe(13)
		expect(Levels.spawnSeconds({ { SpawnSeconds = 0 } } :: any, 1)).toBe(13)
		expect(Levels.spawnSeconds({ {} } :: any, 1)).toBe(13)
	end)

	test("no level's line is longer than Config.MaxQueue (3), and Lv 1 spawns at Config.SpawnEverySeconds", function()
		-- Config uses Vector3 (Roblox-only), so its numbers are read from the file's text.
		local source: string? = nil
		for _, path in { "src/shared/Config.luau", "game/src/shared/Config.luau", "../src/shared/Config.luau" } do
			if fs.isFile(path) then
				source = fs.readFile(path)
				break
			end
		end
		assert(source, "could not find Config.luau")
		local maxQueue = tonumber(string.match(source, "Config%.MaxQueue = (%d+)"))
		local spawnEvery = tonumber(string.match(source, "Config%.SpawnEverySeconds = (%d+)"))
		expect(maxQueue).toBe(3)
		for level = 1, Levels.max(LevelsData) do
			expect(Levels.queue(LevelsData, level) <= (maxQueue :: number)).toBe(true)
			for _, chip in LevelsData[level].Unlocks do
				expect(string.find(chip, "Line of", 1, true)).toBeNil() -- the Shop never promises a longer line
			end
		end
		expect(Levels.spawnSeconds(LevelsData, 1)).toBe(spawnEvery)
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
