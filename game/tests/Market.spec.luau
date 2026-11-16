--!strict
-- The Player Market's rules (Logic/Market; Progression v2 build plan §B3.2/§B6/§B7). The required table test: the
-- B6.1 bands and the fee.

local T = require("./expect")
local expect, test = T.expect, T.test

local Market = require("../src/shared/Logic/Market")
local Belt = require("../src/shared/Logic/Belt")
local Schema = require("../src/shared/Logic/Schema")
local Nurses = require("../src/shared/Data/Nurses")
local Config = require("./config")

local function buyer(overrides: { [string]: any }?): any
	local data = Schema.default()
	data.Level = 3
	data.Cash = 10000
	for key, value in overrides or {} do
		(data :: any)[key] = value
	end
	return data
end

T.describe("Market bands and the fee (the B6.1 table)", function()
	test("Lv 1 bands: 50% to 300% of the belt's base price, to 10s", function()
		local bands = {}
		for _, rarity in Belt.RARITIES do
			bands[rarity] = { Market.band(Config, rarity, 1) }
		end
		expect(bands).toEqual({
			Common = { 50, 300 },
			Rare = { 200, 1200 },
			Epic = { 750, 4500 },
			Legendary = { 3000, 18000 },
			Mythic = { 10000, 60000 },
			Secret = { 25000, 150000 },
		})
	end)

	test("a levelled nurse is worth more: Lv 10 x1.9, Lv 15 x2.4", function()
		expect({ Market.band(Config, "Rare", 10) }).toEqual({ 380, 2280 })
		expect({ Market.band(Config, "Rare", 15) }).toEqual({ 480, 2880 })
		expect({ Market.band(Config, "Legendary", 10) }).toEqual({ 5700, 34200 })
		expect({ Market.band(Config, "Common", 10) }).toEqual({ 100, 570 }) -- 95 -> 100 (to 10s)
		expect({ Market.band(Config, "Common", 0 / 0) }).toEqual({ 50, 300 })
	end)

	test("valid: a whole number inside the band", function()
		expect(Market.valid(50, 50, 300)).toBe(true)
		expect(Market.valid(300, 50, 300)).toBe(true)
		expect(Market.valid(49, 50, 300)).toBe(false)
		expect(Market.valid(301, 50, 300)).toBe(false)
		expect(Market.valid(120.5, 50, 300)).toBe(false)
		expect(Market.valid(0 / 0, 50, 300)).toBe(false)
		expect(Market.valid("120", 50, 300)).toBe(false)
		expect(Market.valid(1e9, 50, 300)).toBe(false)
	end)

	test("fee: 10%, floored; the seller gets the rest", function()
		local rows = {}
		for _, price in { 50, 99, 420, 1200, 150000 } do
			rows[price] = { Market.fee(price, Config), price - Market.fee(price, Config) }
		end
		expect(rows).toEqual({
			[50] = { 5, 45 },
			[99] = { 9, 90 },
			[420] = { 42, 378 },
			[1200] = { 120, 1080 },
			[150000] = { 15000, 135000 },
		})
		expect(Market.fee(-5, Config)).toBe(0)
	end)
end)

T.describe("Market listing and buying", function()
	test("canList: owned, not rebirth-only, under the per-seller and server caps; resting is fine", function()
		local seller = buyer({
			Nurses = {
				PuffPup = { Level = 3, XP = 0, Copies = 1, Job = "" },
				MintMouse = { Level = 1, XP = 0, Copies = 1, Job = "Rest" },
				FounderFennec = { Level = 1, XP = 0, Copies = 1, Job = "" },
			},
		})
		expect({ Market.canList(seller, "PuffPup", 0, 0, Config, Nurses) }).toEqual({ true, "" })
		expect({ Market.canList(seller, "MintMouse", 0, 0, Config, Nurses) }).toEqual({ true, "" })
		expect({ Market.canList(seller, "BeanBear", 0, 0, Config, Nurses) }).toEqual({ false, "Hire it first!" })
		expect({ Market.canList(seller, "FounderFennec", 0, 0, Config, Nurses) }).toEqual({
			false,
			"This one stays with you!",
		})
		expect({ Market.canList(seller, "PuffPup", 3, 0, Config, Nurses) }).toEqual({ false, "3 listings max!" })
		expect({ Market.canList(seller, "PuffPup", 0, 30, Config, Nurses) }).toEqual({ false, "Market is full!" })
		expect((Market.canList(nil, "PuffPup", 0, 0, Config, Nurses))).toBe(false)
	end)

	test("canBuy: gates, no copy already, roster room, then cash", function()
		local listing = { NurseId = "CloudKoala", Rarity = "Epic", Level = 4, Price = 900 }
		expect({ Market.canBuy(buyer(), listing, false, Config, Nurses) }).toEqual({ true, "" })
		expect({ Market.canBuy(buyer({ Level = 2 }), listing, false, Config, Nurses) }).toEqual({ false, "🏥 Lv 3" })
		local mythic = { NurseId = "MoonpuffDrake", Rarity = "Mythic", Level = 1, Price = 10000 }
		expect({ Market.canBuy(buyer({ Level = 5 }), mythic, false, Config, Nurses) }).toEqual({ false, "🏢 R1" })
		expect((Market.canBuy(buyer({ Level = 5 }), mythic, false, Config, Nurses, 1))).toBe(true)
		expect({ Market.canBuy(buyer(), listing, true, Config, Nurses) }).toEqual({ false, "You have one!" })
		local full = buyer({
			Nurses = {
				PuffPup = { Level = 1, XP = 0, Copies = 1, Job = "" },
				MintMouse = { Level = 1, XP = 0, Copies = 1, Job = "" },
				BeanBear = { Level = 1, XP = 0, Copies = 1, Job = "Rest" },
			},
		})
		expect({ Market.canBuy(full, listing, false, Config, Nurses) }).toEqual({
			false,
			"Roster full: sell or list one",
		})
		expect({ Market.canBuy(buyer({ Cash = 899 }), listing, false, Config, Nurses) }).toEqual({
			false,
			"Need 💰900",
		})
		local rebirthOnly = { NurseId = "FounderFennec", Rarity = "Legendary", Level = 1, Price = 3000 }
		expect((Market.canBuy(buyer({ Level = 5 }), rebirthOnly, false, Config, Nurses))).toBe(false)
		expect((Market.canBuy(buyer(), { NurseId = "Order", Price = 1 }, false, Config, Nurses))).toBe(false)
	end)

	test("canBuy: a nurse above the buyer's level cap needs R3 first (never clamped)", function()
		local cap = Config.Nurses.MaxLevel
		local at = Config.Nurses.LevelCapRebirths
		local listing = { NurseId = "CloudKoala", Rarity = "Epic", Level = cap + 1, Price = 900 }
		expect({ Market.canBuy(buyer(), listing, false, Config, Nurses) }).toEqual({
			false,
			"🏢 R" .. at .. " first!",
		})
		expect((Market.canBuy(buyer(), listing, false, Config, Nurses, at))).toBe(true)
		local atCap = { NurseId = "CloudKoala", Rarity = "Epic", Level = cap, Price = 900 }
		expect((Market.canBuy(buyer(), atCap, false, Config, Nurses))).toBe(true)
	end)
end)
