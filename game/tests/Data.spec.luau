--!strict
-- Content checks for the Lune-safe Data modules (Task 0). Stations uses Color3, so it is checked from its source
-- text here instead of being required. The Real Clinic (build plan contract C3): cases, tools, items, stations,
-- levels and departments are checked against the design's tables; patients by wing and case pool, regulars by their
-- one Lv 1 case, the acting by case, a badge for every station, and the words (Task 3: no player-visible "cure" in
-- Data/* or Logic/*, design §12).

local T = require("./expect")
local expect, test = T.expect, T.test

local Items = require("../src/shared/Data/Items")
local Cases = require("../src/shared/Data/Cases")
local Tools = require("../src/shared/Data/Tools")
local MiniGame = require("../src/shared/Logic/MiniGame")
local Patients = require("../src/shared/Data/Patients")
local Regulars = require("../src/shared/Data/Regulars")
local Rooms = require("../src/shared/Data/Rooms")
local Upgrades = require("../src/shared/Data/Upgrades")
local Decor = require("../src/shared/Data/Decor")
local DailyGoals = require("../src/shared/Data/DailyGoals")
local Wings = require("../src/shared/Data/Wings")
local Variants = require("../src/shared/Data/Variants")
local CaseActing = require("../src/shared/Data/CaseActing")
local CreatureSize = require("../src/shared/Logic/CreatureSize")
local Nurses = require("../src/shared/Data/Nurses")
local Rarities = require("../src/shared/Data/Rarities")
local Jobs = require("../src/shared/Data/Jobs")
local Departments = require("../src/shared/Data/Departments")
local Abilities = require("../src/shared/Data/Abilities")
local Perks = require("../src/shared/Data/Perks")
local Tree = require("../src/shared/Data/Tree")
local Themes = require("../src/shared/Data/Themes")
local Levels = require("../src/shared/Data/Levels")
local Badges = require("../src/shared/Data/Badges")
local Building = require("../src/shared/Logic/Building")
local Visit = require("../src/shared/Logic/Visit")
local fs = require("@lune/fs")

local STATIONS = { Remedy = true, Plaster = true, Ice = true, Bandage = true, Cast = true, Bath = true, Cocoa = true }
-- What Logic/Abilities.useful and the servers know how to do (Data/Abilities Kind)
local ABILITY_KINDS = {
	AutoPerfect = true,
	TrayItem = true,
	RefillFront = true,
	PauseLine = true,
	FastMake = true,
	CashNext = true,
	StarsNext = true,
	RefillLine = true,
	InstantMake = true,
	CureLine = true,
	Recharge = true,
}
local PERK_KINDS = {
	Arrive = true,
	StartRoom = true,
	XP = true,
	NightOwl = true,
	Tray = true,
	BeltScout = true,
	StartCash = true,
	StartUpgrades = true,
	SirenPro = true,
	Patience = true,
	StartLevel = true,
	Recharge = true,
	Points = true,
}
local TREE_EFFECTS = {
	Patience = true,
	Tips = true,
	Ease = true,
	TwinCounters = true,
	MakeSpeed = true,
	Walk = true,
	Lift = true,
	DoubleShift = true,
	Cash = true,
	Stars = true,
	Bargain = true,
	LuckyStock = true,
}
local GAMES = {} -- the GameIds (Logic/MiniGame.ENGINE)
for game in MiniGame.ENGINE do
	GAMES[game] = true
end

local function source(path: string): string
	for _, prefix in { "", "game/", "../" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("could not find " .. path)
end

-- Data/Stations uses Color3 (Roblox-only), so its rows are read from the file's text: one station per line,
--   Plaster = { Name = "Plasters", Icon = "🩹", Item = "Plaster", Color = Candy.Pink },
local function stationRows(): { [string]: { Item: string, Dispense: boolean } }
	local out = {}
	for line in string.gmatch(source("src/shared/Data/Stations.luau"), "[^\n]+") do
		local id, body = string.match(line, "^\t(%w+) = {(.*)},%s*$")
		local item = if body then string.match(body, 'Item = "(%w*)"') else nil
		if id and item then
			out[id] = { Item = item, Dispense = string.find(body, "Dispense = true", 1, true) ~= nil }
		end
	end
	return out
end

local function words(text: string): number
	local count = 0
	for _ in string.gmatch(text, "%S+") do
		count += 1
	end
	return count
end

local function keys(map: any): { string }
	local out = {}
	for key in map do
		table.insert(out, key)
	end
	table.sort(out)
	return out
end

local function sorted(list: { string }): { string }
	local out = table.clone(list)
	table.sort(out)
	return out
end

-- The folder a source path lives in, from game/ or the repo root (as `source` finds files).
local function folder(path: string): string
	for _, prefix in { "", "game/", "../" } do
		if fs.isDir(prefix .. path) then
			return prefix .. path
		end
	end
	error("could not find " .. path)
end

-- Every string literal in Luau source, comments left out: "...", '...', `...` and [[...]] (any level).
local function literals(text: string): { string }
	local out = {}
	local i, n = 1, #text
	while i <= n do
		local c = string.sub(text, i, i)
		if c == "-" and string.sub(text, i, i + 1) == "--" then
			local level = string.match(text, "^%-%-%[(=*)%[", i)
			local close = if level then "]" .. level .. "]" else "\n"
			local stop = string.find(text, close, i + 2, true)
			i = if stop then stop + #close else n + 1
		elseif c == '"' or c == "'" or c == "`" then
			local j, parts = i + 1, {}
			while j <= n do
				local d = string.sub(text, j, j)
				if d == "\\" then
					table.insert(parts, string.sub(text, j, j + 1))
					j += 2
				elseif d == c then
					break
				else
					table.insert(parts, d)
					j += 1
				end
			end
			table.insert(out, table.concat(parts))
			i = j + 1
		elseif c == "[" and string.match(text, "^%[=*%[", i) then
			local level = string.match(text, "^%[(=*)%[", i) :: string
			local first = i + #level + 2
			local stop = string.find(text, "]" .. level .. "]", first, true)
			table.insert(out, string.sub(text, first, (stop or n + 1) - 1))
			i = if stop then stop + #level + 2 else n + 1
		else
			i += 1
		end
	end
	return out
end

T.describe("Data", function()
	test("every keyed module's Order lists exactly its entries", function()
		for name, module in
			{
				Items = Items,
				Cases = Cases,
				Tools = Tools,
				Patients = Patients,
				Regulars = Regulars,
				Rooms = Rooms,
				Upgrades = Upgrades,
				Decor = Decor,
				Wings = Wings,
				Variants = Variants,
				CaseActing = CaseActing,
				Nurses = Nurses,
				Rarities = Rarities,
				Jobs = Jobs,
				Departments = Departments,
				Abilities = Abilities,
				Perks = Perks,
				TreeNodes = Tree.Nodes,
				Themes = Themes,
			} :: { [string]: any }
		do
			local ok, err = pcall(function()
				expect(sorted(module.Order)).toEqual(keys(module))
			end)
			if not ok then
				error(name .. ": " .. tostring(err))
			end
		end
	end)

	test("data tables are frozen", function()
		expect(table.isfrozen(Rooms)).toBe(true)
		expect(table.isfrozen(Rooms.Stand)).toBe(true)
		expect(table.isfrozen(DailyGoals)).toBe(true)
	end)

	test("patients: known wings, each with a case pool; no case of their own (it's rolled each visit)", function()
		expect(#Patients.Order).toBe(17) -- 10 + Progression v2's Sunny (4) and Sky (3)
		for id, patient in Patients do
			expect(Wings[patient.Wing] ~= nil).toBe(true)
			expect(Cases.POOLS[patient.Wing] ~= nil).toBe(true)
			expect((patient :: any).Ailment).toBeNil()
			expect((patient :: any).Case).toBeNil()
			expect(patient.Night == true).toBe(patient.Wing == "Night")
			expect(type(patient.Look.Body) == "string" and string.sub(patient.Look.Body, 1, 1) == "#").toBe(true)
			expect(type(id)).toBe("string")
		end
	end)

	test("regulars have 5 beats of 6 words or fewer and a real reward", function()
		expect(Regulars.Order).toEqual({ "ShySprout", "GrumpyTeapot", "DizzyComet" })
		local unlocks = {}
		for _, id in Regulars.Order do
			local regular = Regulars[id]
			table.insert(unlocks, regular.UnlockStars)
			expect(#regular.Beats).toBe(5)
			for _, beat in regular.Beats do
				if words(beat.Bubble) > 6 then
					error(id .. " bubble too long: " .. beat.Bubble)
				end
				expect(#beat.Emote > 0).toBe(true)
			end
			expect(Wings[regular.Wing] ~= nil).toBe(true)
			if regular.RewardKind == "Decor" then
				expect(Decor[regular.Reward] ~= nil).toBe(true)
			else
				expect(Rooms[regular.Reward] ~= nil).toBe(true)
			end
		end
		expect(unlocks).toEqual({ 0, 40, 120 })
	end)

	test("rooms match the plan's table", function()
		local expected = {
			Stand = { "Stand", 0, 0, 1, 2 },
			BathRoom = { "A", 150, 10, 0, 1 },
			Ward = { "B", 300, 25, 2, 2 },
			WinterWing = { "C", 500, 40, 1, 2 },
			Garden = { "D", 800, 70, 0, 3 },
		}
		for id, row in expected do
			local room = Rooms[id]
			expect({ room.Slot, room.Price, room.StarsNeeded, room.Beds, room.DecorSlots }).toEqual(row)
			for _, station in room.Stations do
				expect(STATIONS[station]).toBe(true)
			end
		end
		expect(Rooms.Stand.Stations).toEqual({ "Remedy", "Plaster" })
		expect(Rooms.BathRoom.Stations).toEqual({ "Bath" })
		expect(Rooms.WinterWing.Stations).toEqual({ "Cocoa" })
	end)

	test("upgrades match the plan's prices", function()
		expect(Upgrades.Order).toEqual({ "Speed", "Tray", "Chairs", "Tips", "WardComfort", "AESpeed", "NightClinic" })
		expect(Upgrades.Speed.Prices).toEqual({ 50, 150, 400, 900, 2000 })
		expect(Upgrades.Tray.Prices).toEqual({ 100, 500, 1500 })
		expect(Upgrades.Chairs.Prices).toEqual({ 75, 250, 600 })
		expect(Upgrades.Tips.Prices).toEqual({ 75, 250, 600, 1400, 3000 })
		for _, id in Upgrades.Order do
			expect(words(Upgrades[id].Hint) <= 6).toBe(true)
		end
	end)

	test("Progression v2's department upgrades and their gates (build plan §B5)", function()
		expect(Upgrades.WardComfort.Prices).toEqual({ 800, 2500, 6000 })
		expect(Upgrades.WardComfort.Level).toBe(2)
		expect(Upgrades.AESpeed.Prices).toEqual({ 1000, 3000, 8000 })
		expect(Upgrades.AESpeed.Level).toBe(2)
		expect(Upgrades.NightClinic.Prices).toEqual({ 1500, 4000, 9000 })
		expect(Upgrades.NightClinic.Rebirths).toBe(4)
		expect(Upgrades.NightClinic.Level).toBeNil()
		for _, id in { "Speed", "Tray", "Chairs", "Tips" } do
			expect(Upgrades[id].Level).toBeNil()
			expect(Upgrades[id].Rebirths).toBeNil()
		end
	end)

	test("decor is either priced or earned, never both", function()
		for id, item in Decor do
			local priced = item.Price ~= nil
			local earned = item.EarnedBy ~= nil
			if priced == earned then
				error(id .. " must have exactly one of Price or EarnedBy")
			end
			if earned then
				local how = item.EarnedBy
				local known = how == "Book"
					or how == "Story"
					or how == "Referral"
					or how == "Playtime"
					or how == "Journal"
					or how == "Rebirth"
				if not known then
					error(id .. " is earned by " .. tostring(how))
				end
			end
			expect(item.Rebirths ~= nil).toBe(item.EarnedBy == "Rebirth")
		end
		expect(Decor.FriendBench.EarnedBy).toBe("Referral")
	end)

	test("one Branch Trophy for each of rebirths 6 to 10 (§E18), in existing DecorBuilder kinds", function()
		local byCount = {}
		local kinds = source("src/server/DecorBuilder.luau")
		for id, item in Decor do
			if item.EarnedBy == "Rebirth" then
				expect(byCount[item.Rebirths]).toBeNil()
				byCount[item.Rebirths] = id
				expect(string.find(kinds, '"' .. item.Look.Kind .. '"', 1, true) ~= nil).toBe(true)
			end
		end
		expect(byCount).toEqual({
			[6] = "TrophyCup",
			[7] = "TrophyStar",
			[8] = "TrophyGlobe",
			[9] = "TrophyRocket",
			[10] = "TrophyCrown",
		})
	end)

	test("wing set rewards are earned decor", function()
		expect(Wings.Starter.SetReward).toBe("HeartRug")
		expect(Wings.Bath.SetReward).toBe("RubberDuckFountain")
		expect(Wings.Winter.SetReward).toBe("SnowGlobeLamp")
		expect(Wings.Sunny.SetReward).toBe("SunflowerArch")
		expect(Wings.Sky.SetReward).toBe("CloudSwing")
		for _, id in Wings.Order do
			expect(Decor[Wings[id].SetReward].EarnedBy).toBe("Book")
		end
	end)

	test("the Progression v2 wings: Sunny from R1, Sky from R2 by helicopter only", function()
		expect(Wings.Sunny.Rebirths).toBe(1)
		expect(Wings.Sunny.Only).toBeNil()
		expect(Wings.Sky.Rebirths).toBe(2)
		expect(Wings.Sky.Only).toBe("Helicopter")
		for _, id in { "Starter", "Bath", "Winter", "Night" } do
			expect(Wings[id].Rebirths).toBeNil()
			expect(Wings[id].Only).toBeNil()
		end
		local cast = { Sunny = {}, Sky = {} }
		for _, id in Patients.Order do
			local patient = Patients[id]
			if cast[patient.Wing] then
				table.insert(cast[patient.Wing], id)
			end
		end
		expect(cast.Sunny).toEqual({ "DaisyDoodle", "BuzzBun", "ThistleTot", "CactusCub" })
		expect(cast.Sky).toEqual({ "CometKite", "NimbusNarwhal", "PuffinPilot" })
	end)

	test("variants: Golden from R3", function()
		expect(Variants.Golden.Rebirths).toBe(3)
		expect(Variants.Golden.WinterOnly).toBe(false)
		expect(Variants.Sparkly.Rebirths).toBeNil()
	end)

	test("daily goals are well formed", function()
		local seen = {}
		for _, goal in DailyGoals do
			expect(seen[goal.Id]).toBeNil()
			seen[goal.Id] = true
			expect(goal.Target > 0).toBe(true)
			expect(goal.Reward.Cash >= 0 and goal.Reward.Stars >= 0).toBe(true)
			if goal.Kind == "CureWing" then
				expect(Wings[goal.Wing :: string] ~= nil).toBe(true)
			end
		end
	end)

	test("items: supplies with a game from their own station, medicines from the dispensary with a bottle", function()
		local supplies, medicines = {}, {}
		local icons: { [string]: string } = {}
		for _, id in Items.Order do
			local item = Items[id]
			-- a plan chip, the dispensary prompt and the "needs ..." toast show an item by its icon alone
			expect(icons[item.Icon]).toBeNil()
			icons[item.Icon] = id
			expect(STATIONS[item.Station]).toBe(true)
			expect(type(item.Name) == "string" and item.Name ~= "").toBe(true)
			expect(type(item.Icon) == "string" and item.Icon ~= "").toBe(true)
			expect(string.match(id, "^%w+$") ~= nil).toBe(true) -- the Carry attribute joins ids with commas
			if item.Kind == "Supply" then
				table.insert(supplies, id)
				expect(GAMES[item.Game]).toBe(true)
				expect(item.Bottle).toBeNil()
				expect(item.Station ~= "Remedy").toBe(true)
			else
				expect(item.Kind).toBe("Medicine")
				table.insert(medicines, id)
				expect(item.Station).toBe("Remedy")
				expect(item.Game).toBeNil() -- handing a medicine over plays no game
				expect(string.match(item.Bottle, "^#%x%x%x%x%x%x$") ~= nil).toBe(true)
			end
		end
		expect(supplies).toEqual({ "Plaster", "Ice", "Bandage", "Cast", "Bubbles", "Cocoa" })
		expect(medicines).toEqual({ "CoughSyrup", "FeverMeds", "EarDrops", "Lozenges", "Cream", "PainRelief" })
		expect({ Items.Bubbles.Name, Items.Cocoa.Name }).toEqual({ "Bath foam", "Hot chocolate" })
		expect({ Items.Plaster.Game, Items.Ice.Game, Items.Bandage.Game, Items.Cast.Game }).toEqual({
			"Plaster",
			"Ice",
			"Bandage",
			"Cast",
		})
		expect({ Items.Bubbles.Game, Items.Cocoa.Game }).toEqual({ "Bath", "Cocoa" })
		-- every medicine's bottle is its own colour, so the dispensing game can tell them apart
		local bottles = {}
		for _, id in medicines do
			expect(bottles[Items[id].Bottle]).toBeNil()
			bottles[Items[id].Bottle] = true
		end
		-- the potion and the crafted medicines are gone
		for _, gone in { "Potion", "WarmTonic", "SoapyPatch", "SuperSyrup", "CocoaFizz" } do
			expect(rawget(Items :: any, gone)).toBeNil()
		end
	end)

	test("the stations (read from the source: Stations uses Color3): one per supply, and the dispensary", function()
		local rows = stationRows()
		local text = source("src/shared/Data/Stations.luau")
		expect(
			string.find(
				text,
				'local ORDER = { "Remedy", "Plaster", "Ice", "Bandage", "Cast", "Bath", "Cocoa" }',
				1,
				true
			) ~= nil
		).toBe(true)
		expect(sorted(keys(rows))).toEqual(sorted(keys(STATIONS)))
		expect(rows.Remedy).toEqual({ Item = "", Dispense = true })
		expect(string.find(text, 'Remedy = { Name = "Dispensary"', 1, true) ~= nil).toBe(true)
		expect(rows.Pharmacy).toBeNil() -- the crafting station is gone
		for id, row in rows do
			expect(string.match(id, "^%w+$") ~= nil).toBe(true) -- parts are named Station_<id>
			if id ~= "Remedy" then
				expect(row.Dispense).toBe(false)
				expect(Items[row.Item].Station).toBe(id)
				expect(Items[row.Item].Kind).toBe("Supply")
			end
		end
		-- and every item's station is one of them
		for _, id in Items.Order do
			expect(rows[Items[id].Station] ~= nil).toBe(true)
		end
		expect(string.find(text, "Craft", 1, true)).toBeNil()
	end)

	test("tools: the five of the design, each with a game; the X-ray is a machine from Lv 3", function()
		expect(Tools.ORDER).toEqual({ "Stethoscope", "Thermometer", "Light", "Magnifier", "XRay" })
		expect(Tools.Order).toBe(Tools.ORDER)
		local rows = {}
		for _, id in Tools.ORDER do
			local tool = Tools[id]
			rows[id] = { tool.Icon, tool.Game }
			expect(GAMES[tool.Game]).toBe(true)
			expect(type(tool.Name) == "string" and tool.Name ~= "").toBe(true)
			expect(tool.Machine == true).toBe(id == "XRay")
			-- simple start (memory-20261117-006): the 🔦 Light from Lv 2, the X-ray from Lv 3, the rest from Lv 1
			expect(tool.Level).toBe(if id == "XRay" then 3 elseif id == "Light" then 2 else nil)
		end
		expect(rows).toEqual({
			Stethoscope = { "🩺", "Listen" },
			Thermometer = { "🌡️", "Temp" },
			Light = { "🔦", "Light" },
			Magnifier = { "🔍", "Look" },
			XRay = { "📸", "XRay" },
		})
		expect(Tools.XRay.Level).toBe(Departments.Imaging.Opens)
	end)

	test("cases: the twelve of the design, each with a known tool and a plan of 1-3 known items", function()
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
		expect(Cases.Order).toBe(Cases.ORDER)
		local rows = {}
		for _, id in Cases.ORDER do
			local case = Cases[id]
			expect(Tools[case.Tool] ~= nil).toBe(true)
			expect(#case.Plan >= 1 and #case.Plan <= 3).toBe(true)
			local seen = {}
			for _, item in case.Plan do
				expect(Items[item] ~= nil).toBe(true)
				expect(STATIONS[Items[item].Station]).toBe(true)
				expect(seen[item]).toBeNil() -- no step twice
				seen[item] = true
			end
			expect(case.Level >= 1 and case.Level <= #Levels).toBe(true)
			expect(case.Room == nil or Rooms[case.Room] ~= nil).toBe(true)
			expect(case.Stay == nil or case.Stay == "Wards" or case.Stay == "Rest").toBe(true)
			expect(type(case.Name) == "string" and case.Name ~= "").toBe(true)
			-- the symptom bubble: the case's icon (an X-ray case's: the 🦴, so it can be sent to the X-ray), then two
			-- words at most
			local lead = if case.Tool == "XRay" then Cases.BONE else case.Icon
			expect(string.sub(case.Bubble, 1, #lead)).toBe(lead)
			expect(words(case.Bubble) <= 3).toBe(true)
			-- a case opens no sooner than its tool (the Light, the X-ray) and every plan station
			expect(case.Level >= (Tools[case.Tool].Level or 1)).toBe(true)
			for _, item in case.Plan do
				local station = Building.STATIONS[Items[item].Station]
				expect(station == nil or case.Level >= station.Opens).toBe(true)
			end
			rows[id] = { case.Tool, table.concat(case.Plan, ","), case.Stay or "", case.Level, case.Room or "" }
		end
		expect(rows).toEqual({
			Cough = { "Stethoscope", "CoughSyrup", "", 1, "" },
			Fever = { "Thermometer", "FeverMeds", "Rest", 1, "" },
			CutKnee = { "Magnifier", "Plaster", "", 1, "" },
			BumpedHead = { "Magnifier", "Ice", "", 2, "" },
			Earache = { "Light", "EarDrops", "", 2, "" },
			Sprain = { "Magnifier", "Ice,Bandage", "Wards", 2, "" },
			SoreThroat = { "Light", "Lozenges,CoughSyrup", "", 3, "" },
			Rash = { "Magnifier", "Cream,Ice", "", 3, "" },
			BrokenArm = { "XRay", "Cast,PainRelief", "Wards", 3, "" },
			SoreMuscles = { "Magnifier", "Bubbles,PainRelief", "", 1, "BathRoom" },
			Chills = { "Thermometer", "Cocoa,FeverMeds", "Rest", 1, "WinterWing" },
			BrokenLeg = { "XRay", "Cast,PainRelief,Bandage", "Wards", 5, "" },
		})
		-- a room's case starts with that room's own supply, so the room's station is always used
		expect(Items[Cases.SoreMuscles.Plan[1]].Station).toBe("Bath")
		expect(Items[Cases.Chills.Plan[1]].Station).toBe("Cocoa")
		-- every item and every tool is used by some case
		local used = {}
		for _, id in Cases.ORDER do
			used[Cases[id].Tool] = true
			for _, item in Cases[id].Plan do
				used[item] = true
			end
		end
		for _, id in Items.Order do
			expect(used[id]).toBe(true)
		end
		for _, id in Tools.ORDER do
			expect(used[id]).toBe(true)
		end
	end)

	test("a Lv 1 clinic can treat every Lv 1 case: its plan's first step comes from a station open at Lv 1", function()
		local lv1 = { Remedy = true, Plaster = true } -- simple start: the Ice chest is Lv 2
		local n = 0
		for _, id in Cases.ORDER do
			local case = Cases[id]
			if case.Level == 1 and not case.Room then
				n += 1
				for _, item in case.Plan do
					expect(lv1[Items[item].Station]).toBe(true)
				end
			end
		end
		expect(n).toBe(3)
	end)

	test("case pools: one per wing, every id a case; the Night pool is Lv 1 cases only", function()
		expect(sorted(keys(Cases.POOLS))).toEqual(sorted(table.clone(Wings.Order)))
		for wing, pool in Cases.POOLS do
			expect(#pool >= 1).toBe(true)
			for _, id in pool do
				if Cases[id] == nil then
					error(wing .. " pool: " .. tostring(id) .. " is not a case")
				end
			end
		end
		for _, id in Cases.POOLS.Night do
			expect(Cases[id].Level).toBe(1)
			expect(Cases[id].Room).toBeNil()
		end
		expect(Cases.POOLS.Night).toEqual({ "Cough", "Fever", "CutKnee" })
		expect(Cases.POOLS.Starter).toEqual({
			"Cough",
			"Fever",
			"CutKnee",
			"BumpedHead",
			"Earache",
			"Sprain",
			"SoreThroat",
			"Rash",
			"BrokenArm",
		})
		expect(Cases.POOLS.Sunny).toEqual({ "Rash", "Sprain", "CutKnee" })
		expect(Cases.POOLS.Sky).toEqual({ "BrokenLeg" })
		-- Bath and Winter: their own room's case (the likeliest), then the Starter pool
		for wing, own in { Bath = "SoreMuscles", Winter = "Chills" } do
			local pool = Cases.POOLS[wing]
			expect(pool[1]).toBe(own)
			local rest = {}
			for _, id in pool do
				if id ~= own then
					table.insert(rest, id)
				end
			end
			expect(rest).toEqual(Cases.POOLS.Starter)
		end
		-- every case is in some pool, and a room's case only in its own wing's
		local pooled = {}
		for wing, pool in Cases.POOLS do
			for _, id in pool do
				pooled[id] = true
				if Cases[id].Room then
					expect(Rooms[Cases[id].Room].Wing).toBe(wing)
				end
			end
		end
		for _, id in Cases.ORDER do
			expect(pooled[id]).toBe(true)
		end
		expect(table.isfrozen(Cases.POOLS) and table.isfrozen(Cases.POOLS.Starter)).toBe(true)
	end)

	test("gentle words only: no item, case or tool says cure or needle (or anything scary)", function()
		local banned = { "cure", "needle", "blood", "surgery", "inject", "syringe", "scalpel" }
		local function check(what: string, text: string)
			local lower = string.lower(text)
			for _, word in banned do
				if string.find(lower, word, 1, true) then
					error(what .. " says " .. word .. ": " .. text)
				end
			end
		end
		for _, id in Items.Order do
			check("item " .. id, id)
			check("item " .. id, Items[id].Name)
		end
		for _, id in Cases.ORDER do
			check("case " .. id, id)
			check("case " .. id, Cases[id].Name)
			check("case " .. id, Cases[id].Bubble)
		end
		for _, id in Tools.ORDER do
			check("tool " .. id, id)
			check("tool " .. id, Tools[id].Name)
		end
		for id, row in stationRows() do
			check("station " .. id, id)
		end
		check("stations", (string.gsub(source("src/shared/Data/Stations.luau"), "%-%-[^\n]*", "")))
		for _, row in Levels do
			check("level", row.Name)
			for _, chip in row.Unlocks do
				check("level chip", chip)
			end
		end
		for _, id in Departments.Order do
			check("department " .. id, Departments[id].Name)
		end
	end)

	test("regulars: one fixed case each with no room; the first two a fresh Lv 1 clinic can treat", function()
		local function lv1(stationId: string): boolean
			return Building.stationOpen(stationId, 1)
		end
		local cases = {}
		for _, id in Regulars.Order do
			local regular = Regulars[id] :: any
			local case = Cases[regular.Case]
			if case == nil then
				error(id .. ": unknown case " .. tostring(regular.Case))
			end
			-- simple start: Dizzy Comet's bumped head is a Lv 2 case (it unlocks at 120 Clinic Stars, at night)
			expect(case.Level).toBe(if id == "DizzyComet" then 2 else 1)
			expect(case.Room).toBeNil()
			expect(Visit.canTreat(case, 1, {}, lv1, Items)).toBe(id ~= "DizzyComet")
			expect(Visit.canTreat(case, 2, {}, function(stationId: string): boolean
				return Building.stationOpen(stationId, 2)
			end, Items)).toBe(true)
			expect(regular.Ailment).toBeNil() -- the ailments and their recipes are gone
			expect(regular.Recipe).toBeNil()
			cases[id] = regular.Case
		end
		-- their words fit their case: Shy Sprout coughs, Grumpy Teapot runs hot, Dizzy Comet bumped its head
		expect(cases).toEqual({ ShySprout = "Cough", GrumpyTeapot = "Fever", DizzyComet = "BumpedHead" })
		expect(#Cases[Regulars.ShySprout.Case].Plan).toBe(1) -- the first regular stays simple
	end)

	test("the nurse cast: 16 belt nurses (5/4/3/2/1/1) + 1 rebirth-only, each with a role and a look", function()
		expect(#Nurses.Order).toBe(17)
		local byRarity = {}
		local SHAPES = { Ball = true, Bean = true, Blob = true, Box = true, Drop = true }
		local ROLES = { Maker = true, Healer = true, Cheerer = true }
		for id, nurse in Nurses do
			expect(Rarities[nurse.Rarity] ~= nil).toBe(true)
			byRarity[nurse.Rarity] = (byRarity[nurse.Rarity] or 0) + 1
			if not ROLES[nurse.Role] then
				error(id .. " has an unknown role " .. tostring(nurse.Role))
			end
			expect(SHAPES[nurse.Look.Shape]).toBe(true)
			expect(string.match(nurse.Look.Body, "^#%x%x%x%x%x%x$") ~= nil).toBe(true)
			expect(string.match(nurse.Look.Accent, "^#%x%x%x%x%x%x$") ~= nil).toBe(true)
			expect(#nurse.Name > 0 and words(nurse.Name) <= 3).toBe(true)
			expect(#nurse.Icon > 0).toBe(true)
			expect(Patients[id]).toBeNil() -- no id clash with a patient
		end
		expect(byRarity).toEqual({ Common = 5, Rare = 4, Epic = 3, Legendary = 3, Mythic = 1, Secret = 1 })
		-- Order runs by rarity, lowest first; the rebirth-only nurses come last (their own Journal tab)
		local last = 0
		for _, id in Nurses.Order do
			if Nurses[id].Source == nil then
				local rank = table.find(Rarities.Order, Nurses[id].Rarity) :: number
				expect(rank >= last).toBe(true)
				last = rank
			else
				last = math.huge
			end
		end
	end)

	test("every nurse has a Specialty and an Ability (build plan §B5 table)", function()
		local expected = {
			PuffPup = { "Reception", "FreshBrew" },
			MintMouse = { "Wards", "QuickBandage" },
			BeanBear = { "Pharmacy", "FreshBrew" },
			DewDuck = { "Hydro", "QuickSoap" },
			HumHamster = { "Reception", "WarmHug" },
			CuddleCub = { "AE", "WarmHug" },
			PebblePenguin = { "Hydro", "CalmSong" },
			BerryBat = { "Pharmacy", "BusyPaws" },
			SunnySnail = { "Wards", "CalmSong" },
			CloudKoala = { "Wards", "DoubleDose" },
			JamJelly = { "Hydro", "StarBurst" },
			ToffeeFox = { "AE", "DoubleDose" },
			AuroraOtter = { "AE", "GoldenTouch" },
			StarlightLamb = { "Reception", "RainbowCheer" },
			MoonpuffDrake = { "Pharmacy", "TimeBubble" },
			GoldieGryphlet = { "Reception", "Miracle" },
			FounderFennec = { "Any", "TeamSpirit" },
		}
		local spread = {}
		for id, nurse in Nurses do
			expect({ nurse.Specialty, nurse.Ability }).toEqual(expected[id])
			expect(nurse.Specialty == "Any" or Departments[nurse.Specialty] ~= nil).toBe(true)
			expect(Abilities[nurse.Ability] ~= nil).toBe(true)
			expect(Jobs[nurse.Role] ~= nil).toBe(true)
			if nurse.Source == nil then
				spread[nurse.Specialty] = (spread[nurse.Specialty] or 0) + 1
			end
		end
		expect(spread).toEqual({ Reception = 4, AE = 3, Wards = 3, Hydro = 3, Pharmacy = 3 })
		-- a Common or Rare of every team's department
		for _, dept in { "Reception", "AE", "Wards", "Hydro", "Pharmacy" } do
			local cheap = 0
			for _, nurse in Nurses do
				if nurse.Specialty == dept and (nurse.Rarity == "Common" or nurse.Rarity == "Rare") then
					cheap += 1
				end
			end
			if cheap < 1 then
				error("no Common/Rare " .. dept .. " nurse")
			end
		end
	end)

	test("FounderFennec is the one rebirth-only nurse (R5)", function()
		local only = {}
		for id, nurse in Nurses do
			if nurse.Source ~= nil then
				table.insert(only, id)
				expect(nurse.Source).toBe("Rebirth")
			end
			expect(nurse.Rebirths ~= nil).toBe(nurse.Source ~= nil)
		end
		expect(only).toEqual({ "FounderFennec" })
		expect(Nurses.FounderFennec.Rebirths).toBe(5)
		expect(Nurses.FounderFennec.Rarity).toBe("Legendary")
		expect(Nurses.Order[#Nurses.Order]).toBe("FounderFennec")
	end)

	test("jobs: the §B5 table, short texts, known departments", function()
		local rows = {}
		for _, id in Jobs.Order do
			local job = Jobs[id]
			rows[id] = { job.Icon, job.Dept, job.Opens }
			expect(words(job.Text) <= 6).toBe(true)
			expect(job.Dept == "Station" or Departments[job.Dept] ~= nil).toBe(true)
		end
		expect(rows).toEqual({
			Maker = { "🧪", "Station", 1 },
			Healer = { "🩺", "Reception", 1 },
			Cheerer = { "🎉", "Reception", 1 },
			Receptionist = { "🛎️", "Reception", 1 },
			Porter = { "↕️", "Wards", 2 },
			Medic = { "🚑", "AE", 2 },
		})
		expect(rawget(Jobs :: any, "Rest")).toBeNil() -- "Rest" is never a job
	end)

	test(
		"departments: the Real Clinic's eight; opens agree with Data/Levels; stations and wings map to them",
		function()
			expect(Departments.Order).toEqual({
				"Reception",
				"Pharmacy",
				"Hydro",
				"AE",
				"Wards",
				"Imaging",
				"Rest",
				"Roof",
			})
			local rows = {}
			for _, id in Departments.Order do
				local dept = Departments[id]
				rows[id] = { dept.Opens, dept.Floor, dept.Team2 and dept.Team2.Value, dept.Team3 and dept.Team3.Value }
				for level, row in Levels do
					local listed = table.find(row.Departments, id) ~= nil
					if dept.Room then
						expect(listed).toBe(false) -- it comes with its room, not with a level
						expect(Rooms[dept.Room] ~= nil).toBe(true)
					else
						expect(listed).toBe(level >= dept.Opens)
					end
				end
			end
			expect(rows).toEqual({
				Reception = { 1, 0, 0.1, 0.2 },
				Pharmacy = { 1, 0, 0.2, 0.4 },
				Hydro = { 1, 0, 0.2, 0.4 },
				AE = { 2, 0, 0.25, 0.5 },
				Wards = { 2, 1, 0.25, 0.5 },
				Imaging = { 3, 0 },
				Rest = { 3, 2 },
				Roof = { 5, 4 },
			})
			expect(Departments.Hydro.Room).toBe("BathRoom")
			expect(Departments.Hydro.Team3.Stations).toEqual({ "Bath" })
			-- the Pharmacy team speeds up the supply shelf (and the Cocoa Corner); nobody speeds up dispensing
			expect(Departments.Pharmacy.Team3.Stations).toEqual({ "Plaster", "Ice", "Bandage", "Cocoa" })
			expect(Departments.Pharmacy.Team2.Stations).toEqual(Departments.Pharmacy.Team3.Stations)
			-- every station has a department, and only stations do
			expect(sorted(keys(Departments.Stations))).toEqual(sorted(keys(STATIONS)))
			for stationId, dept in Departments.Stations do
				expect(STATIONS[stationId]).toBe(true)
				expect(Departments[dept] ~= nil).toBe(true)
			end
			expect(Departments.Stations.Remedy).toBe("Pharmacy")
			expect(Departments.Stations.Cast).toBe("Imaging")
			expect(Departments.Stations.Bath).toBe("Hydro")
			for _, wingId in Wings.Order do
				expect(Departments[Departments.Wings[wingId]] ~= nil).toBe(true)
			end
			-- the lift's button for a floor is the first department in Order on it
			local onFloor = {}
			for _, id in Departments.Order do
				local floor = Departments[id].Floor
				onFloor[floor] = onFloor[floor] or id
			end
			expect({ onFloor[1], onFloor[2], onFloor[4] }).toEqual({ "Wards", "Rest", "Roof" })
		end
	)

	test("abilities: the §B5 table; values grow with the nurse; known kinds and games", function()
		local rows = {}
		for _, id in Abilities.Order do
			local ability = Abilities[id]
			rows[id] = { ability.Kind, ability.Cooldown, ability.Values[1], ability.Values[2], ability.Values[3] }
			expect(ABILITY_KINDS[ability.Kind]).toBe(true)
			expect(#ability.Values).toBe(3)
			expect(ability.Values[1] <= ability.Values[2] and ability.Values[2] <= ability.Values[3]).toBe(true)
			if ability.Game ~= nil then
				expect(GAMES[ability.Game]).toBe(true)
			end
		end
		expect(rows).toEqual({
			QuickBandage = { "AutoPerfect", 60, 1, 2, 3 },
			QuickSoap = { "AutoPerfect", 60, 1, 2, 3 },
			FreshBrew = { "TrayItem", 75, 1, 2, 3 },
			WarmHug = { "RefillFront", 60, 1, 1, 1 },
			CalmSong = { "PauseLine", 90, 10, 13, 16 },
			BusyPaws = { "FastMake", 90, 10, 13, 16 },
			DoubleDose = { "CashNext", 120, 1, 2, 3 },
			StarBurst = { "StarsNext", 120, 3, 4, 5 },
			GoldenTouch = { "AutoPerfect", 150, 3, 4, 5 },
			RainbowCheer = { "RefillLine", 150, 1, 1, 1 },
			TimeBubble = { "InstantMake", 180, 8, 10, 12 },
			Miracle = { "CureLine", 600, 1, 1, 1 },
			TeamSpirit = { "Recharge", 240, 1, 1, 1 },
		})
		-- GameIds since the Real Clinic: the 🩹 Plaster and 🛁 Bath games (they were the Patch and Scrub engines)
		expect(Abilities.QuickBandage.Game).toBe("Plaster")
		expect(Abilities.QuickSoap.Game).toBe("Bath")
		expect(MiniGame.ENGINE.Plaster).toBe("Patch")
		expect(MiniGame.ENGINE.Bath).toBe("Scrub")
		expect(Abilities.GoldenTouch.Game).toBeNil()
		expect(Abilities.Miracle.Daily).toBe(true)
	end)

	test("perks: 12 cards and the Fallback, texts of 6 words or fewer, known kinds", function()
		expect(#Perks.Order).toBe(12)
		for _, id in Perks.Order do
			local perk = Perks[id]
			if words(perk.Text) > 6 then
				error(id .. " text too long: " .. perk.Text)
			end
			expect(PERK_KINDS[perk.Kind]).toBe(true)
			expect(type(perk.Value) == "number" and perk.Value > 0).toBe(true)
		end
		expect(Perks.FallbackId).toBe("TreePoints")
		expect(rawget(Perks :: any, "TreePoints")).toBeNil() -- never a card you own
		expect(Perks.Fallback.Kind).toBe("Points")
		expect(Perks.Fallback.Value).toBe(2)
		expect(words(Perks.Fallback.Text) <= 6).toBe(true)
		expect(Perks.SeedMoney.Value).toBe(1000)
		expect(Perks.BusyDoors.Value).toBe(0.85)
		expect(Perks.ClinicStart.Value).toBe(2)
	end)

	test("the tree: 3 branches of 3 ranked nodes and a capstone, 33 points in all, short texts", function()
		expect(Tree.BranchOrder).toEqual({ "Care", "Speed", "Fortune" })
		expect(Tree.CapstoneNeeds).toBe(6)
		local total, capstones = 0, {}
		local perBranch = {}
		for _, id in Tree.Nodes.Order do
			local node = Tree.Nodes[id]
			expect(Tree.Branches[node.Branch] ~= nil).toBe(true)
			expect(TREE_EFFECTS[node.Effect]).toBe(true)
			if words(node.Text) > 6 then
				error(id .. " text too long: " .. node.Text)
			end
			total += node.Max * node.Cost
			perBranch[node.Branch] = (perBranch[node.Branch] or 0) + 1
			if node.Capstone then
				expect({ node.Max, node.Cost }).toEqual({ 1, 2 })
				capstones[node.Branch] = id
			else
				expect({ node.Max, node.Cost }).toEqual({ 3, 1 })
			end
		end
		expect(total).toBe(33)
		expect(perBranch).toEqual({ Care = 4, Speed = 4, Fortune = 4 })
		expect(capstones).toEqual({ Care = "TwinCounters", Speed = "DoubleShift", Fortune = "LuckyStock" })
	end)

	test("themes: Candy first, one more each rebirth to R5, hex colours", function()
		expect(Themes.Order).toEqual({ "Candy", "Arctic", "Jungle", "Space", "Ocean", "Royal" })
		expect(Themes.Default).toBe("Candy")
		for index, id in Themes.Order do
			local theme = Themes[id]
			expect(theme.Rebirths).toBe(index - 1)
			for _, field in { "Wall", "Roof", "Trim" } do
				local value = (theme :: any)[field]
				expect(value == "" or string.match(value, "^#%x%x%x%x%x%x$") ~= nil).toBe(true)
				expect(value == "").toBe(id == "Candy")
			end
			expect(theme.Prop == "").toBe(id == "Candy")
		end
	end)

	test("the Branches badge: Clinic, derived from rebirths, inside the Stars cap", function()
		local found = nil
		for _, badge in Badges.List do
			if badge.Id == "Branches" then
				found = badge
			end
		end
		assert(found, "no Branches badge")
		expect(found.Category).toBe("Clinic")
		expect(found.Stat).toBe("Rebirths")
		expect(found.Thresholds).toEqual({ 1, 2, 3, 5, 8, 12 })
		expect(found.Boost).toEqual({ Kind = "Stars", Percent = 2 })
	end)

	test(
		"every station has a Made: badge; the old potion badge is the 💊 Pharmacist and counts dispensing",
		function()
			local byStat = {}
			for _, badge in Badges.List do
				byStat[badge.Stat] = badge
			end
			for id in stationRows() do
				local badge = byStat["Made:" .. id]
				if badge == nil then
					error("no badge counts Made:" .. id)
				end
				expect(badge.Category).toBe("Stations")
				expect(badge.Boost).toEqual({ Kind = "MakeSpeed", Scope = id, Percent = 3 })
			end
			local pharmacist = byStat["Made:Remedy"]
			expect({ pharmacist.Id, pharmacist.Name, pharmacist.Icon }).toEqual({ "Potions", "Pharmacist", "💊" })
			-- the stations a save already counted keep their badge ids (and so their tiers); the new ones start at 0
			expect({ byStat["Made:Plaster"].Id, byStat["Made:Bath"].Id, byStat["Made:Cocoa"].Id }).toEqual({
				"Plasters",
				"Bubbles",
				"Cocoa",
			})
			expect({ byStat["Made:Ice"].Id, byStat["Made:Bandage"].Id, byStat["Made:Cast"].Id }).toEqual({
				"IcePacks",
				"Bandages",
				"Casts",
			})
		end
	)

	test('no player-visible string in Data/* or Logic/* says "cure" (design §12)', function()
		local VISIBLE =
			{ Name = true, Title = true, Caption = true, Text = true, Goal = true, Hint = true, Bubble = true }
		local function says(text: string): boolean
			return string.find(text, "%f[%a][Cc]ure") ~= nil
		end
		local scanned = 0
		for _, dir in { "src/shared/Data", "src/shared/Logic" } do
			local path = folder(dir)
			for _, name in fs.readDir(path) do
				if string.sub(name, -5) ~= ".luau" then
					continue
				end
				scanned += 1
				-- 1. Every literal in the code: one that says cure must be an id ("Cures", "CureWing", "Cured": the
				-- saved names), never words (a space, a "!" or any other mark gives words away).
				local text = fs.readFile(path .. "/" .. name)
				for _, literal in literals(text) do
					if says(literal) and not string.match(literal, "^[%w_:]+$") then
						error(dir .. "/" .. name .. ' says "' .. literal .. '"')
					end
				end
				-- 2. One-word texts a player reads (a board's Caption, a Name...): every table field of those names,
				-- in each module Lune can load (not one that reaches for Roblox, like Data/Stations' Palette: its
				-- literals were checked above).
				local roblox = string.find(text, "script.Parent", 1, true)
					or string.find(text, "game:GetService", 1, true)
				local ok, module = false, nil
				if not roblox then
					ok, module = pcall(require, "../" .. dir .. "/" .. string.sub(name, 1, -6))
				end
				local seen = {}
				local function walk(where: string, value: any, depth: number)
					if type(value) ~= "table" or seen[value] or depth > 8 then
						return
					end
					seen[value] = true
					for key, child in value do
						if type(child) == "string" and VISIBLE[key] and says(child) then
							error(where .. "." .. tostring(key) .. ' says "' .. child .. '"')
						end
						walk(where .. "." .. tostring(key), child, depth + 1)
					end
				end
				if ok then
					walk(dir .. "/" .. name, module, 0)
				end
			end
		end
		expect(scanned >= 40).toBe(true)
		-- and the words that replaced them
		expect(Badges.List[1].Goal).toBe("Treat patients")
		expect(Upgrades.Tips.Hint).toBe("More cash per patient")
		expect(Upgrades.NightClinic.Hint).toBe("Night patients pay more")
	end)

	test("rarities: lowest first, Epic+ shout, events only on Mythic and Secret, journal decor is earned", function()
		expect(Rarities.Order).toEqual({ "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" })
		expect(Rarities.Mythic.Event).toBe("NightRush")
		expect(Rarities.Secret.Event).toBe("GoldenHour")
		local lastCash = 0
		for _, id in Rarities.Order do
			local rarity = Rarities[id]
			if id ~= "Mythic" and id ~= "Secret" then
				expect(rarity.Event).toBeNil()
			end
			expect(string.match(rarity.Color, "^#%x%x%x%x%x%x$") ~= nil).toBe(true)
			expect(Decor[rarity.Journal.Decor].EarnedBy).toBe("Journal")
			expect(rarity.Journal.Cash > lastCash).toBe(true)
			lastCash = rarity.Journal.Cash
		end
	end)
end)

T.describe("Creatures", function()
	local function eachLook(fn: (id: string, look: any) -> ())
		for _, id in Patients.Order do
			fn(id, Patients[id].Look)
		end
		for _, id in Regulars.Order do
			fn(id, Regulars[id].Look)
		end
	end

	test("every species has its own size, from small to big", function()
		local smallest, biggest = math.huge, -math.huge
		eachLook(function(id, look)
			if look.Scale < CreatureSize.SPECIES_MIN or look.Scale > CreatureSize.SPECIES_MAX then
				error(id .. " Scale " .. tostring(look.Scale) .. " is outside the size range")
			end
			smallest = math.min(smallest, look.Scale)
			biggest = math.max(biggest, look.Scale)
		end)
		expect(smallest <= 0.8).toBe(true)
		expect(biggest >= 1.15).toBe(true)
	end)

	test("Bits are short lists of names, none twice", function()
		eachLook(function(id, look)
			local seen = {}
			for _, bit in look.Bits or {} do
				expect(type(bit)).toBe("string")
				if seen[bit] then
					error(id .. " lists the Bit " .. bit .. " twice")
				end
				seen[bit] = true
			end
			expect(#(look.Bits or {}) <= 4).toBe(true)
		end)
	end)

	test("every case acts something out, with only things the client can play", function()
		local known: { [string]: { [string]: boolean } } = {}
		for kind, list in CaseActing.Vocabulary do
			known[kind] = {}
			for _, name in list do
				known[kind][name] = true
			end
		end
		expect(CaseActing.Order).toEqual(Cases.ORDER) -- one per case, in the cases' order
		local function check(name: string, acting: any)
			if not known.Motions[acting.Motion] then
				error(name .. ": unknown Motion " .. tostring(acting.Motion))
			end
			expect(#acting.Every).toBe(2)
			expect(acting.Every[1] > 0 and acting.Every[1] <= acting.Every[2]).toBe(true)
			for _, prop in acting.Props do
				if not known.Props[prop] then
					error(name .. ": unknown prop " .. prop)
				end
			end
			for field, kind in { Burst = "Bursts", Ambient = "Ambients", Face = "Faces" } do
				local value = acting[field]
				if value ~= nil and not known[kind][value] then
					error(name .. ": unknown " .. field .. " " .. tostring(value))
				end
			end
			if acting.Cheeks ~= nil then
				expect(string.match(acting.Cheeks, "^#%x%x%x%x%x%x$") ~= nil).toBe(true)
			end
			if acting.Glow ~= nil then
				expect(acting.Glow > 0 and acting.Glow <= 1).toBe(true)
			end
		end
		for _, id in CaseActing.Order do
			check(id, CaseActing[id])
			expect(#CaseActing[id].Props >= 1).toBe(true) -- every case shows a prop
			-- gentle only (design §2): no crying
			expect(table.find(CaseActing[id].Props, "Tear")).toBeNil()
		end
		check("Default", CaseActing.Default)
	end)

	test("attention comes as patience runs low", function()
		local attention = CaseActing.Attention
		expect(0 < attention.Alert and attention.Alert < attention.Wave and attention.Wave < 1).toBe(true)
		for _, range in { attention.WaveEvery, attention.AlertEvery } do
			expect(range[1] > 0 and range[1] <= range[2]).toBe(true)
		end
		expect(attention.AlertEvery[2] <= attention.WaveEvery[1]).toBe(true) -- lower patience, more waving
	end)
end)
