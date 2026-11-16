--!strict
-- The Nurse Belt's rules (depth-update build plan §B6/§B7; memory-20261116-017). CFG copies the rule numbers so each
-- rule is tested on its own; the last block loads the real Config (tests/config.luau) and checks the shipped numbers
-- and where the belt stands in town.

local T = require("./expect")
local expect, test = T.expect, T.test

local Belt = require("../src/shared/Logic/Belt")
local Nurses = require("../src/shared/Data/Nurses")
local Rarities = require("../src/shared/Data/Rarities")
local Config = require("./config")
local fs = require("@lune/fs")

local CFG = {
	Belt = {
		Odds = { Common = 75, Rare = 20, Epic = 4.5, Legendary = 0.5 },
		MinLevel = { Epic = 3, Legendary = 3, Mythic = 3, Secret = 3 },
		NightRushBoost = 2,
		NightRushMythic = 0.5,
		GoldenSecret = 1,
		GoldenEverySeconds = 1200,
		GoldenSeconds = 120,
		PityArrivals = 15,
		Offset = { X = 120, Y = 0, Z = -11 },
		Heading = 180,
		Length = 240,
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

	test("day odds are the design's (memory-017), with no Mythic or Secret", function()
		local odds = Belt.odds(CFG, false, false)
		expect(odds).toEqual({ Common = 75, Rare = 20, Epic = 4.5, Legendary = 0.5, Mythic = 0, Secret = 0 })
	end)

	test("Night Rush doubles Rare+ and adds Mythic; Common takes the rest", function()
		local odds = Belt.odds(CFG, true, false)
		expect(odds.Rare).toBe(40)
		expect(odds.Epic).toBe(9)
		expect(odds.Legendary).toBe(1)
		expect(odds.Mythic).toBe(0.5)
		expect(odds.Secret).toBe(0)
		expect(odds.Common).toBeCloseTo(49.5)
	end)

	test("Golden Hour adds Secret, day or night", function()
		expect(Belt.odds(CFG, false, true).Secret).toBe(1)
		expect(Belt.odds(CFG, false, true).Common).toBeCloseTo(74)
		local both = Belt.odds(CFG, true, true)
		expect(both.Secret).toBe(1)
		expect(both.Mythic).toBe(0.5)
		expect(both.Common).toBeCloseTo(48.5)
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
		expect(Belt.roll(odds, 0.74, false)).toBe("Common")
		expect(Belt.roll(odds, 0.76, false)).toBe("Rare")
		expect(Belt.roll(odds, 0.96, false)).toBe("Epic")
		expect(Belt.roll(odds, 0.9960, false)).toBe("Legendary")
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

	test("pity: 15 arrivals without a Rare+ make the next one Rare+", function()
		local dry = 0
		for _ = 1, 15 do
			expect(Belt.pityDue(dry, CFG)).toBe(false)
			dry = Belt.afterArrival(dry, "Common")
		end
		expect(dry).toBe(15)
		expect(Belt.pityDue(dry, CFG)).toBe(true)
		expect(Belt.pityLeft(dry, CFG)).toBe(1)
		expect(Belt.pityLeft(0, CFG)).toBe(16)
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

	test("Epic and up need hospital Lv 3 to hire; Common and Rare anyone", function()
		expect(Belt.minLevel(CFG, "Common")).toBe(1)
		expect(Belt.minLevel(CFG, "Rare")).toBe(1)
		for _, rarity in { "Epic", "Legendary", "Mythic", "Secret" } do
			expect(Belt.minLevel(CFG, rarity)).toBe(3)
			expect(Belt.levelOk(CFG, rarity, 2)).toBe(false)
			expect(Belt.levelOk(CFG, rarity, 3)).toBe(true)
			expect(Belt.levelOk(CFG, rarity, 5)).toBe(true)
		end
		expect(Belt.levelOk(CFG, "Common", 1)).toBe(true)
		expect(Belt.levelOk(CFG, "Epic", 0 / 0)).toBe(false) -- junk level counts as Lv 1
		expect(Belt.minLevel(CFG, "Nope")).toBe(1)
		expect(Belt.minLevel({ Belt = {} }, "Epic")).toBe(1) -- no gate configured: anyone
	end)

	test("path: Offset, then Length studs along Heading (180 = toward -X)", function()
		local sx, sz, ex, ez = Belt.path(CFG)
		expect(sx).toBe(120)
		expect(sz).toBe(-11)
		expect(ex).toBeCloseTo(-120)
		expect(ez).toBeCloseTo(-11)
		local _, _, ex2, ez2 = Belt.path({ Belt = { Offset = { X = 0, Z = 0 }, Length = 10, Heading = 90 } })
		expect(ex2).toBeCloseTo(0)
		expect(ez2).toBeCloseTo(-10) -- a quarter turn about +Y takes +X to -Z
		expect(Belt.distanceToPath(CFG, 0, 0)).toBeCloseTo(11)
		expect(Belt.distanceToPath(CFG, 130, -11)).toBeCloseTo(10) -- past the start: to the end point
		expect(Belt.distanceToPath(CFG, -78, 18.4)).toBeCloseTo(29.4)
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

-- PlotBuilder's town numbers (a Roblox module, so read from its text): the street's half width and the plot gap.
local function plotBuilderNumber(name: string): number
	local source: string? = nil
	for _, path in
		{ "src/server/PlotBuilder.luau", "game/src/server/PlotBuilder.luau", "../src/server/PlotBuilder.luau" }
	do
		if fs.isFile(path) then
			source = fs.readFile(path)
			break
		end
	end
	assert(source, "could not find PlotBuilder.luau")
	local value = tonumber(string.match(source, "local " .. name .. " = ([%d%.]+)"))
	assert(value, "PlotBuilder has no " .. name)
	return value :: number
end

T.describe("Belt: the shipped Config (memory-20261116-017)", function()
	local B = Config.Belt

	test("about one arrival per 40 s, base odds 75 / 20 / 4.5 / 0.5, pity 15", function()
		expect(B.ArriveSeconds).toBe(40)
		expect(B.Odds).toEqual({ Common = 75, Rare = 20, Epic = 4.5, Legendary = 0.5 })
		expect(B.PityArrivals).toBe(15)
		expect(Belt.odds(Config, false, false)).toEqual({
			Common = 75,
			Rare = 20,
			Epic = 4.5,
			Legendary = 0.5,
			Mythic = 0,
			Secret = 0,
		})
	end)

	test("Mythic only in Night Rush, Secret only in Golden Hour; every state adds up to 100", function()
		for _, night in { false, true } do
			for _, golden in { false, true } do
				local odds = Belt.odds(Config, night, golden)
				expect(total(odds)).toBeCloseTo(100)
				expect(odds.Mythic > 0).toBe(night)
				expect(odds.Secret > 0).toBe(golden)
			end
		end
	end)

	test("Epic and up need hospital Lv 3 (the rebirth gate for Mythic and Secret comes with rebirths)", function()
		for _, rarity in { "Epic", "Legendary", "Mythic", "Secret" } do
			expect(Belt.minLevel(Config, rarity)).toBe(3)
		end
		expect(Belt.minLevel(Config, "Common")).toBe(1)
		expect(Belt.minLevel(Config, "Rare")).toBe(1)
	end)

	test("a rider is on the belt most of the time, and the safety cap leaves room for the cadence", function()
		expect(B.RideSeconds >= 2 * B.ArriveSeconds).toBe(true) -- two or three ride at once
		expect(B.MaxRiders >= math.ceil(B.RideSeconds / B.ArriveSeconds) + 1).toBe(true)
		expect(B.ReplaceSeconds < B.ArriveSeconds).toBe(true)
		-- a calm ride: well under a walk (16 studs/s), so a kid can follow a nurse along the street
		expect(B.Length / B.RideSeconds <= 4).toBe(true)
	end)

	test("prices: newcomers can afford Commons; a level-up never doubles a price", function()
		expect(Belt.price(Config, "Common", 1)).toBe(100)
		expect(Belt.price(Config, "Common", 5) <= 150).toBe(true)
		expect(Belt.price(Config, "Epic", 3)).toBe(1800)
	end)
end)

T.describe("Belt: where it stands in town (on the main road)", function()
	local B = Config.Belt
	local size = Config.Town.PlotSize
	local count = Config.Town.Plots
	local perRow = math.ceil(count / 2)
	local half = plotBuilderNumber("STREET_HALF_WIDTH") -- 18
	local gap = plotBuilderNumber("PLOT_GAP") -- 8
	local streetEnd = (perRow * (size + gap) + 40) / 2 -- 137: the street (and the Hall of Fame past x < -137)
	local archInner = streetEnd - 5 - 0.8 -- the welcome arches' posts (1.6 wide) at x = ±(end - 5)
	local curb = half - 0.8 -- the curbs' inner edge
	local beltHalf = 3.4 -- NurseBelt: the bed (BELT_WIDTH 5 + 1.6) and the rollers, either side of the line
	local houseReach, cloudReach = 7.5, 7.5 -- NurseBelt: the nurse house before the start, the cloud past the end
	local sx, sz, ex, ez = Belt.path(Config)

	test("along the street for most of its length, between the welcome arches", function()
		expect(math.abs(sz - ez) < 0.01).toBe(true) -- straight down the street
		expect(math.abs(sx - ex) >= 0.8 * 2 * streetEnd).toBe(true)
		local east, west = math.max(sx, ex), math.min(sx, ex)
		local eastReach = if sx > ex then houseReach else cloudReach
		local westReach = if sx > ex then cloudReach else houseReach
		expect(east + eastReach <= archInner - 2).toBe(true)
		expect(west - westReach >= -archInner + 2).toBe(true)
		expect(west - westReach > -streetEnd).toBe(true) -- the Hall of Fame garden (x < -137) stays clear
	end)

	test("inside the curbs, clear of the spawn pad and the plaza planters", function()
		expect(math.abs(sz) + beltHalf <= curb - 2).toBe(true) -- a lane stays free along the curb
		expect(math.abs(sz) - beltHalf >= 5 + 2).toBe(true) -- the 10 x 10 spawn pad
		expect(math.abs(sz) - beltHalf >= 5 + 2 + 0.5).toBe(true) -- planters at z = ±5 (4 across)
	end)

	test("every plot's gate is within hire reach of riders passing it", function()
		for column = 1, perRow do
			local x = (column - (perRow + 1) / 2) * (size + gap)
			for _, side in { -1, 1 } do
				local gateZ = side * (half + size / 2 - 34.6) -- the gate in the plot's front fence
				expect(Belt.distanceToPath(Config, x, gateZ) <= B.HireDistance - 5).toBe(true)
			end
		end
	end)

	test("the odds sign stands at the plaza, off the belt, clear of the middle gate, inside the curb", function()
		local signX, signZ = B.SignOffset.X, B.SignOffset.Z
		local signHalf = 6 -- 12 studs wide
		expect(math.abs(signZ) - math.abs(sz) >= beltHalf + 1).toBe(true) -- behind the belt, from the spawn
		expect(math.abs(signZ) + 0.8 <= curb).toBe(true) -- its posts stay on the street
		expect(math.abs(signX) - signHalf >= 6.2 + 0.6 + 1).toBe(true) -- the middle gate (posts at ±6.8) stays open
		expect(math.abs(signX) + signHalf <= half - 1 + 3).toBe(true) -- at the plaza, readable from the spawn
		expect(Belt.distanceToPath(Config, signX, signZ) <= B.HireDistance).toBe(true)
	end)
end)
