--!strict
-- The Nurse Belt's rules (depth-update build plan §B6/§B7). Config uses Vector3 (Roblox-only), so the plan's numbers
-- are copied here.

local T = require("./expect")
local expect, test = T.expect, T.test

local Belt = require("../src/shared/Logic/Belt")
local Nurses = require("../src/shared/Data/Nurses")
local Rarities = require("../src/shared/Data/Rarities")

local CFG = {
	Belt = {
		Odds = { Common = 70, Rare = 24, Epic = 5, Legendary = 1 },
		NightRushBoost = 2,
		NightRushMythic = 0.5,
		GoldenSecret = 1,
		GoldenEverySeconds = 1200,
		GoldenSeconds = 120,
		PityArrivals = 8,
		Prices = { Common = 100, Rare = 400, Epic = 1500, Legendary = 6000, Mythic = 20000, Secret = 50000 },
		PriceScale = { 1, 1.1, 1.2, 1.3, 1.4 },
	},
	Nurses = { MaxLevel = 5 },
}

local function total(odds: { [string]: number }): number
	local sum = 0
	for _, value in odds do
		sum += value
	end
	return sum
end

T.describe("Belt", function()
	test("rarities match Data/Rarities", function()
		expect(Belt.RARITIES).toEqual(Rarities.Order)
	end)

	test("day odds are the design's, with no Mythic or Secret", function()
		local odds = Belt.odds(CFG, false, false)
		expect(odds).toEqual({ Common = 70, Rare = 24, Epic = 5, Legendary = 1, Mythic = 0, Secret = 0 })
	end)

	test("Night Rush doubles Rare+ and adds Mythic; Common takes the rest", function()
		local odds = Belt.odds(CFG, true, false)
		expect(odds.Rare).toBe(48)
		expect(odds.Epic).toBe(10)
		expect(odds.Legendary).toBe(2)
		expect(odds.Mythic).toBe(0.5)
		expect(odds.Secret).toBe(0)
		expect(odds.Common).toBeCloseTo(39.5)
	end)

	test("Golden Hour adds Secret, day or night", function()
		expect(Belt.odds(CFG, false, true).Secret).toBe(1)
		expect(Belt.odds(CFG, false, true).Common).toBeCloseTo(69)
		local both = Belt.odds(CFG, true, true)
		expect(both.Secret).toBe(1)
		expect(both.Mythic).toBe(0.5)
		expect(both.Common).toBeCloseTo(38.5)
	end)

	test("odds always add up to 100", function()
		for _, night in { false, true } do
			for _, golden in { false, true } do
				expect(total(Belt.odds(CFG, night, golden))).toBeCloseTo(100)
			end
		end
	end)

	test("roll walks the odds in rarity order", function()
		local odds = Belt.odds(CFG, false, false)
		expect(Belt.roll(odds, 0, false)).toBe("Common")
		expect(Belt.roll(odds, 0.69, false)).toBe("Common")
		expect(Belt.roll(odds, 0.71, false)).toBe("Rare")
		expect(Belt.roll(odds, 0.95, false)).toBe("Epic")
		expect(Belt.roll(odds, 0.995, false)).toBe("Legendary")
		expect(Belt.roll(odds, 1, false)).toBe("Legendary")
	end)

	test("Mythic and Secret only come during their events", function()
		local day = Belt.odds(CFG, false, false)
		for i = 0, 100 do
			local rarity = Belt.roll(day, i / 100, false)
			expect(rarity ~= "Mythic" and rarity ~= "Secret").toBe(true)
		end
		local both = Belt.odds(CFG, true, true)
		expect(Belt.roll(both, 0.999, false)).toBe("Secret")
		expect(Belt.roll(both, 0.988, false)).toBe("Mythic")
	end)

	test("a pity roll is always Rare+", function()
		local odds = Belt.odds(CFG, false, false)
		for i = 0, 100 do
			expect(Belt.isRarePlus(Belt.roll(odds, i / 100, true))).toBe(true)
		end
		expect(Belt.roll(odds, 0, true)).toBe("Rare")
	end)

	test("pity: 8 arrivals without a Rare+ make the next one Rare+", function()
		local dry = 0
		for _ = 1, 8 do
			expect(Belt.pityDue(dry, CFG)).toBe(false)
			dry = Belt.afterArrival(dry, "Common")
		end
		expect(dry).toBe(8)
		expect(Belt.pityDue(dry, CFG)).toBe(true)
		expect(Belt.pityLeft(dry, CFG)).toBe(1)
		expect(Belt.pityLeft(0, CFG)).toBe(9)
		expect(Belt.afterArrival(dry, "Rare")).toBe(0)
		expect(Belt.afterArrival(3, "Mythic")).toBe(0)
	end)

	test("shouts for Epic and up", function()
		expect(Belt.shouts("Rare")).toBe(false)
		expect(Belt.shouts("Epic")).toBe(true)
		expect(Belt.shouts("Secret")).toBe(true)
		expect(Belt.shouts("Nope")).toBe(false)
		for _, id in Rarities.Order do
			expect(Belt.shouts(id)).toBe(Rarities[id].Shout)
		end
	end)

	test("pick finds a nurse of the rarity, evenly", function()
		expect(Belt.pick(Nurses, "Mythic", 0.5)).toBe("MoonpuffDrake")
		expect(Belt.pick(Nurses, "Secret", 0)).toBe("GoldieGryphlet")
		local seen = {}
		for i = 0, 99 do
			local id = Belt.pick(Nurses, "Common", i / 100) :: string
			expect(Nurses[id].Rarity).toBe("Common")
			seen[id] = true
		end
		local count = 0
		for _ in seen do
			count += 1
		end
		expect(count).toBe(5)
		expect(Belt.pick(Nurses, "Nope", 0.5)).toBeNil()
	end)

	test("prices scale by the viewer's hospital level", function()
		expect(Belt.price(CFG, "Common", 1)).toBe(100)
		expect(Belt.price(CFG, "Common", 5)).toBe(140)
		expect(Belt.price(CFG, "Rare", 2)).toBe(440)
		expect(Belt.price(CFG, "Legendary", 3)).toBe(7200)
		expect(Belt.price(CFG, "Secret", 1)).toBe(50000)
		expect(Belt.price(CFG, "Common", 99)).toBe(140)
		expect(Belt.price(CFG, "Common", 0 / 0)).toBe(100)
	end)

	test("Golden Hour: every 20 minutes of uptime, 2 minutes long", function()
		local active, startsAt, endsAt = Belt.golden(CFG, 0)
		expect(active).toBe(false)
		expect(startsAt).toBe(1200)
		expect(endsAt).toBe(1320)
		active, startsAt, endsAt = Belt.golden(CFG, 1250)
		expect(active).toBe(true)
		expect(startsAt).toBe(1200)
		expect(endsAt).toBe(1320)
		active, startsAt = Belt.golden(CFG, 1320)
		expect(active).toBe(false)
		expect(startsAt).toBe(2400)
		active = Belt.golden(CFG, 2400)
		expect(active).toBe(true)
	end)

	test("alpha: how far along the belt", function()
		expect(Belt.alpha(100, 100, 30)).toBe(0)
		expect(Belt.alpha(100, 115, 30)).toBe(0.5)
		expect(Belt.alpha(100, 200, 30)).toBe(1)
		expect(Belt.alpha(100, 50, 30)).toBe(0)
		expect(Belt.alpha(100, 101, 0)).toBe(1)
	end)

	test("canHire stops at the max level", function()
		expect((Belt.canHire(nil, CFG))).toBe(true)
		expect((Belt.canHire({ Level = 4, Copies = 4 }, CFG))).toBe(true)
		local ok, message = Belt.canHire({ Level = 5, Copies = 9 }, CFG)
		expect(ok).toBe(false)
		expect(message).toBe("Max level!")
	end)
end)
