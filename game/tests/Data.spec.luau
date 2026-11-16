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
local Nurses = require("../src/shared/Data/Nurses")
local Rarities = require("../src/shared/Data/Rarities")
local fs = require("@lune/fs")

local STATIONS = { Remedy = true, Plaster = true, Bath = true, Cocoa = true }
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
}

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
				Nurses = Nurses,
				Rarities = Rarities,
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
		expect(#Patients.Order).toBe(10)
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
		expect(Upgrades.Order).toEqual({ "Speed", "Tray", "Chairs", "Tips" })
		expect(Upgrades.Speed.Prices).toEqual({ 50, 150, 400, 900, 2000 })
		expect(Upgrades.Tray.Prices).toEqual({ 100, 500, 1500 })
		expect(Upgrades.Chairs.Prices).toEqual({ 75, 250, 600 })
		expect(Upgrades.Tips.Prices).toEqual({ 75, 250, 600, 1400, 3000 })
		for _, id in Upgrades.Order do
			expect(words(Upgrades[id].Hint) <= 6).toBe(true)
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
				local by = item.EarnedBy
				expect(by == "Book" or by == "Story" or by == "Referral" or by == "Journal").toBe(true)
			end
		end
		expect(Decor.FriendBench.EarnedBy).toBe("Referral")
	end)

	test("wing set rewards are earned decor", function()
		expect(Wings.Starter.SetReward).toBe("HeartRug")
		expect(Wings.Bath.SetReward).toBe("RubberDuckFountain")
		expect(Wings.Winter.SetReward).toBe("SnowGlobeLamp")
		for _, id in Wings.Order do
			expect(Decor[Wings[id].SetReward].EarnedBy).toBe("Book")
		end
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

	test("every ailment has a recipe of 1-3 known items, led by its station's item", function()
		local recipes = ailmentRecipes()
		local wingSize = { Starter = 1, Bath = 2, Winter = 2, Night = 2 }
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

	test("the nurse cast: 16 original nurses, 5/4/3/2/1/1 by rarity, each with a role and a look", function()
		expect(#Nurses.Order).toBe(16)
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
		expect(byRarity).toEqual({ Common = 5, Rare = 4, Epic = 3, Legendary = 2, Mythic = 1, Secret = 1 })
		-- Order runs by rarity, lowest first
		local last = 0
		for _, id in Nurses.Order do
			local rank = table.find(Rarities.Order, Nurses[id].Rarity) :: number
			expect(rank >= last).toBe(true)
			last = rank
		end
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
