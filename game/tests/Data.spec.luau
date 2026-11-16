--!strict
-- Content checks for the Lune-safe Data modules (Task 0). Stations and Ailments use Color3, so they are
-- checked by id lists here instead of being required.

local T = require("./expect")
local expect, test = T.expect, T.test

local Items = require("../src/shared/Data/Items")
local Patients = require("../src/shared/Data/Patients")
local Regulars = require("../src/shared/Data/Regulars")
local Rooms = require("../src/shared/Data/Rooms")
local Upgrades = require("../src/shared/Data/Upgrades")
local Decor = require("../src/shared/Data/Decor")
local DailyGoals = require("../src/shared/Data/DailyGoals")
local Wings = require("../src/shared/Data/Wings")
local Variants = require("../src/shared/Data/Variants")
local AilmentActing = require("../src/shared/Data/AilmentActing")
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
local fs = require("@lune/fs")

local STATIONS = { Remedy = true, Plaster = true, Bath = true, Cocoa = true, Pharmacy = true }
local AILMENTS = {
	Hiccups = "Remedy",
	Sneezes = "Remedy",
	Cough = "Remedy",
	Bump = "Plaster",
	Scrape = "Plaster",
	LostGlow = "Plaster",
	Sticky = "Bath",
	Muddy = "Bath",
	Chills = "Cocoa",
	FrozenNose = "Cocoa",
	-- Progression v2
	Pollen = "Remedy",
	Prickles = "Plaster",
	Airsick = "Remedy",
}
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
local GAMES = { Pour = true, Patch = true, Scrub = true, Cool = true }

local function source(path: string): string
	for _, prefix in { "", "game/", "../" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("could not find " .. path)
end

-- Data/Ailments uses Color3 (Roblox-only), so its recipes are read from the file's text: one entry per line,
--   Hiccups = ailment("Hiccups", "❗", "Remedy", { "Potion" }),
local function ailmentRecipes(): { [string]: { string } }
	local source: string? = nil
	for _, path in
		{ "src/shared/Data/Ailments.luau", "game/src/shared/Data/Ailments.luau", "../src/shared/Data/Ailments.luau" }
	do
		if fs.isFile(path) then
			source = fs.readFile(path)
			break
		end
	end
	assert(source, "could not find Data/Ailments.luau")
	local out: { [string]: { string } } = {}
	for id, items in string.gmatch(source, "(%w+) = ailment%([^{}]-{([^}]*)}%)") do
		local recipe = {}
		for item in string.gmatch(items, '"(%w+)"') do
			table.insert(recipe, item)
		end
		out[id] = recipe
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

T.describe("Data", function()
	test("every keyed module's Order lists exactly its entries", function()
		for name, module in
			{
				Items = Items,
				Patients = Patients,
				Regulars = Regulars,
				Rooms = Rooms,
				Upgrades = Upgrades,
				Decor = Decor,
				Wings = Wings,
				Variants = Variants,
				AilmentActing = AilmentActing,
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

	test("patients use known ailments and wings, with the plan's cast", function()
		expect(#Patients.Order).toBe(17) -- 10 + Progression v2's Sunny (4) and Sky (3)
		for id, patient in Patients do
			expect(AILMENTS[patient.Ailment] ~= nil).toBe(true)
			expect(Wings[patient.Wing] ~= nil).toBe(true)
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
			-- Every clinic can treat a regular: their ailment uses a First-Aid Stand station.
			local station = AILMENTS[regular.Ailment]
			expect(station == "Remedy" or station == "Plaster").toBe(true)
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

	test("items come from known stations", function()
		for _, item in Items do
			expect(STATIONS[item.Station]).toBe(true)
		end
	end)

	test("medicines: two known plain ingredients, a tier, made at the Pharmacy (build plan §B5)", function()
		local medicines = {}
		for _, id in Items.Order do
			local item = Items[id]
			if item.Medicine then
				medicines[id] = { item.Medicine[1], item.Medicine[2], item.Tier }
				expect(item.Station).toBe("Pharmacy")
				for _, part in item.Medicine do
					expect(Items[part] ~= nil and Items[part].Medicine == nil).toBe(true)
				end
			else
				expect(item.Tier).toBeNil()
			end
		end
		expect(medicines).toEqual({
			WarmTonic = { "Potion", "Cocoa", 1 },
			SoapyPatch = { "Bubbles", "Plaster", 1 },
			SuperSyrup = { "Potion", "Plaster", 2 },
			CocoaFizz = { "Cocoa", "Bubbles", 2 },
		})
	end)

	test("the Pharmacy station (read from the source: Stations uses Color3)", function()
		local text = source("src/shared/Data/Stations.luau")
		expect(
			string.find(
				text,
				'Pharmacy = { Name = "Pharmacy", Icon = "💊", Item = "", Craft = true, Color = Candy.',
				1,
				true
			) ~= nil
		).toBe(true)
		expect(string.find(text, 'local ORDER = { "Remedy", "Plaster", "Bath", "Cocoa", "Pharmacy" }', 1, true) ~= nil).toBe(
			true
		)
	end)

	test("every ailment has a recipe of 1-3 known items, led by its station's item", function()
		local recipes = ailmentRecipes()
		local wingSize = { Starter = 1, Bath = 2, Winter = 2, Night = 2, Sunny = 2, Sky = 3 }
		for ailmentId, station in AILMENTS do
			local recipe = recipes[ailmentId]
			if not recipe then
				error("no recipe found for " .. ailmentId)
			end
			expect(#recipe >= 1 and #recipe <= 3).toBe(true)
			expect(Items[recipe[1]].Station).toBe(station)
			for _, item in recipe do
				expect(Items[item] ~= nil).toBe(true)
			end
		end
		-- By wing (design §1): the ailment's patients set its recipe length.
		for _, patientId in Patients.Order do
			local patient = Patients[patientId]
			local recipe = recipes[patient.Ailment]
			if #recipe ~= wingSize[patient.Wing] then
				error(patientId .. " (" .. patient.Wing .. ") has a " .. #recipe .. "-item recipe")
			end
			-- Night patients come to every clinic: First-Aid Stand items only.
			if patient.Night then
				for _, item in recipe do
					expect(item == "Potion" or item == "Plaster").toBe(true)
				end
			end
		end
	end)

	test("regulars have their own recipes of Stand items, led by their ailment's item", function()
		local recipes = ailmentRecipes()
		for _, id in Regulars.Order do
			local recipe = Regulars[id].Recipe
			expect(#recipe >= 1 and #recipe <= 3).toBe(true)
			expect(recipe[1]).toBe(recipes[Regulars[id].Ailment][1])
			for _, item in recipe do
				expect(item == "Potion" or item == "Plaster").toBe(true)
			end
		end
		expect(#Regulars.ShySprout.Recipe).toBe(1) -- the first regular stays simple
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
			Porter = { "🛗", "Wards", 2 },
			Medic = { "🚑", "AE", 2 },
		})
		expect(rawget(Jobs :: any, "Rest")).toBeNil() -- "Rest" is never a job
	end)

	test("departments: the §B5 table; opens agree with Data/Levels; stations and wings map to them", function()
		local rows = {}
		for _, id in Departments.Order do
			local dept = Departments[id]
			rows[id] = { dept.Opens, dept.Floor, dept.Team2 and dept.Team2.Value, dept.Team3 and dept.Team3.Value }
			for level, row in Levels do
				expect(table.find(row.Departments, id) ~= nil).toBe(level >= dept.Opens)
			end
		end
		expect(rows).toEqual({
			Reception = { 1, 0, 0.1, 0.2 },
			AE = { 2, 0, 0.25, 0.5 },
			Wards = { 2, 1, 0.25, 0.5 },
			Hydro = { 3, 2, 0.2, 0.4 },
			Pharmacy = { 4, 3, 0.2, 0.4 },
			Roof = { 5, 4 },
		})
		expect(Departments.Hydro.Team3.Stations).toEqual({ "Bath" })
		expect(Departments.Pharmacy.Team3.Stations).toEqual({ "Cocoa", "Pharmacy" })
		for stationId, dept in Departments.Stations do
			expect(STATIONS[stationId]).toBe(true)
			expect(Departments[dept] ~= nil).toBe(true)
		end
		for _, wingId in Wings.Order do
			expect(Departments[Departments.Wings[wingId]] ~= nil).toBe(true)
		end
	end)

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
		expect(Abilities.QuickBandage.Game).toBe("Patch")
		expect(Abilities.QuickSoap.Game).toBe("Scrub")
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

	test("the new ailments: their stations and recipes (build plan §B5)", function()
		local recipes = ailmentRecipes()
		expect(recipes.Pollen).toEqual({ "Potion", "Bubbles" })
		expect(recipes.Prickles).toEqual({ "Plaster", "Cocoa" })
		expect(recipes.Airsick).toEqual({ "Potion", "Cocoa", "Plaster" })
	end)

	test("every ailment acts something out, with only things the client can play", function()
		local known: { [string]: { [string]: boolean } } = {}
		for kind, list in AilmentActing.Vocabulary do
			known[kind] = {}
			for _, name in list do
				known[kind][name] = true
			end
		end
		expect(sorted(AilmentActing.Order)).toEqual(keys(AILMENTS))
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
		for _, id in AilmentActing.Order do
			check(id, AilmentActing[id])
			expect(#AilmentActing[id].Props >= 1).toBe(true) -- every ailment shows a prop
		end
		check("Default", AilmentActing.Default)
	end)

	test("attention comes as patience runs low", function()
		local attention = AilmentActing.Attention
		expect(0 < attention.Alert and attention.Alert < attention.Wave and attention.Wave < 1).toBe(true)
		for _, range in { attention.WaveEvery, attention.AlertEvery } do
			expect(range[1] > 0 and range[1] <= range[2]).toBe(true)
		end
		expect(attention.AlertEvery[2] <= attention.WaveEvery[1]).toBe(true) -- lower patience, more waving
	end)
end)
