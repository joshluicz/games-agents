--!strict
-- The Nurse Agency's rules (Logic/Agency; Progression v2 build plan §B3.1/§B6/§B7).

local T = require("./expect")
local expect, test = T.expect, T.test

local Agency = require("../src/shared/Logic/Agency")
local Belt = require("../src/shared/Logic/Belt")
local Nurses = require("../src/shared/Data/Nurses")
local Config = require("./config")

T.describe("Agency", function()
	test("restocks every 5 minutes of uptime", function()
		expect(Agency.restock(0, Config)).toBe(0)
		expect(Agency.restock(299, Config)).toBe(0)
		expect(Agency.restock(300, Config)).toBe(1)
		expect(Agency.restock(3601, Config)).toBe(12)
		expect(Agency.restock(-5, Config)).toBe(0)
	end)

	test("the shown odds: 70 / 26 / 4, never Legendary or up", function()
		expect(Agency.odds(Config)).toEqual({ Common = 70, Rare = 26, Epic = 4 })
		local total = 0
		for _, value in Agency.odds(Config) do
			total += value
		end
		expect(total).toBe(100)
		expect(Agency.rarity(Agency.odds(Config), 0)).toBe("Common")
		expect(Agency.rarity(Agency.odds(Config), 0.69)).toBe("Common")
		expect(Agency.rarity(Agency.odds(Config), 0.70)).toBe("Rare")
		expect(Agency.rarity(Agency.odds(Config), 0.97)).toBe("Epic")
		expect(Agency.rarity(Agency.odds(Config), 1)).toBe("Epic")
	end)

	test("roll: 4 distinct nurses, never rebirth-only, a full rarity falls to the next lower", function()
		local stock = Agency.roll(Nurses, Config, { 0.1, 0, 0.1, 0, 0.1, 0, 0.1, 0 })
		expect(#stock).toBe(4)
		local seen = {}
		for _, id in stock do
			expect(seen[id]).toBeNil()
			seen[id] = true
			expect(Nurses[id].Source).toBeNil()
			expect(Nurses[id].Rarity).toBe("Common")
		end
		-- four Epic rolls: only 3 Epics exist, so the 4th is a Rare
		local epics = Agency.roll(Nurses, Config, { 0.99, 0, 0.99, 0, 0.99, 0, 0.99, 0 })
		local rarities = {}
		for _, id in epics do
			table.insert(rarities, Nurses[id].Rarity)
		end
		expect(rarities).toEqual({ "Epic", "Epic", "Epic", "Rare" })
		-- fewer random numbers, fewer slots; `taken` is never repeated
		expect(#Agency.roll(Nurses, Config, { 0.5, 0.5 })).toBe(1)
		local others = Agency.roll(Nurses, Config, { 0.1, 0, 0.1, 0 }, 2, { "PuffPup" })
		expect(table.find(others, "PuffPup")).toBeNil()
	end)

	test(
		"seeded and personal: the same seed, the same nurses; 2 Lucky Stock slots, none from the shared stock",
		function()
			expect(Agency.seeded(12345, 4)).toEqual(Agency.seeded(12345, 4))
			for _, r in Agency.seeded(42, 50) do
				expect(r >= 0 and r < 1).toBe(true)
			end
			local shared = { "PuffPup", "MintMouse", "CuddleCub", "BeanBear" }
			local mine = Agency.personal(Nurses, Config, 311718381, 7, shared)
			expect(#mine).toBe(Config.Agency.LuckySlots)
			expect(Agency.personal(Nurses, Config, 311718381, 7, shared)).toEqual(mine) -- a rejoin never re-rolls
			for _, id in mine do
				expect(table.find(shared, id)).toBeNil()
				expect(Nurses[id].Source).toBeNil()
			end
			-- a different restock or player usually differs (seeds are not all the same)
			local different = false
			for restock = 8, 20 do
				if
					Agency.seeded(311718381 % 1000003 * 7919 + restock + 1, 4)[1]
					~= Agency.seeded(311718381 % 1000003 * 7919 + 8, 4)[1]
				then
					different = true
				end
			end
			expect(different).toBe(true)
		end
	)

	test("price: x1.5 the belt's price at your level, Bargain off", function()
		expect(Agency.price(Config, "Common", 1)).toBe(150)
		expect(Agency.price(Config, "Rare", 1)).toBe(600)
		expect(Agency.price(Config, "Epic", 1)).toBe(2250)
		expect(Agency.price(Config, "Common", 5)).toBe(math.floor(Belt.price(Config, "Common", 5) * 1.5 + 0.5))
		expect(Agency.price(Config, "Rare", 1, 0.15)).toBe(510)
		expect(Agency.price(Config, "Nope", 1)).toBe(0)
	end)

	test("sellBack: 30% of the belt's base price per copy, never level-scaled (§E14)", function()
		local each = {}
		for _, rarity in Belt.RARITIES do
			each[rarity] = Agency.sellBack({ Level = 1, Copies = 1 }, rarity, Config)
		end
		expect(each).toEqual({ Common = 30, Rare = 120, Epic = 450, Legendary = 1800, Mythic = 6000, Secret = 15000 })
		expect(Agency.sellBack({ Level = 9, XP = 30, Copies = 3 }, "Rare", Config)).toBe(360)
		expect(Agency.sellBack(nil, "Rare", Config)).toBe(0)
		-- never a profit: an Agency buy always costs more than its sell-back
		for _, rarity in { "Common", "Rare", "Epic" } do
			expect(Agency.price(Config, rarity, 1, 0.15) > Agency.sellBack({ Copies = 1 }, rarity, Config)).toBe(true)
		end
	end)
end)
