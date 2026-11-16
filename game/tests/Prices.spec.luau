--!strict
-- Upgrade prices and their effects (build plan §B6, Task 3). CFG copies the §B2 values from Config.

local T = require("./expect")
local expect, test = T.expect, T.test

local Prices = require("../src/shared/Logic/Prices")
local Upgrades = require("../src/shared/Data/Upgrades")

local CFG = {
	BaseMakeSeconds = 2,
	MinMakeSeconds = 0.5,
	MakeSpeedFactor = 0.8,
	PatienceSeconds = 60,
	ChairsPatienceBonus = 10,
}

T.describe("Prices.upgradePrice", function()
	test("Speed at level 0 costs 50", function()
		expect(Prices.upgradePrice(Upgrades, "Speed", 0)).toBe(50)
	end)

	test("is the price of the NEXT level", function()
		expect(Prices.upgradePrice(Upgrades, "Speed", 1)).toBe(150)
		expect(Prices.upgradePrice(Upgrades, "Speed", 4)).toBe(2000)
		expect(Prices.upgradePrice(Upgrades, "Tray", 2)).toBe(1500)
	end)

	test("is nil at max level and above", function()
		expect(Prices.upgradePrice(Upgrades, "Speed", 5)).toBeNil()
		expect(Prices.upgradePrice(Upgrades, "Tray", 3)).toBeNil()
		expect(Prices.upgradePrice(Upgrades, "Speed", 99)).toBeNil()
	end)

	test("is nil for unknown ids, including the Order list", function()
		expect(Prices.upgradePrice(Upgrades, "Rocket", 0)).toBeNil()
		expect(Prices.upgradePrice(Upgrades, "Order", 0)).toBeNil()
		expect(Prices.upgradePrice(Upgrades, 42 :: any, 0)).toBeNil()
		expect(Prices.upgradePrice(Upgrades, nil :: any, 0)).toBeNil()
	end)

	test("is nil for a junk level", function()
		expect(Prices.upgradePrice(Upgrades, "Speed", -1)).toBeNil()
		expect(Prices.upgradePrice(Upgrades, "Speed", 0 / 0)).toBeNil()
		expect(Prices.upgradePrice(Upgrades, "Speed", "0" :: any)).toBeNil()
	end)

	test("floors a fractional level", function()
		expect(Prices.upgradePrice(Upgrades, "Speed", 1.7)).toBe(150)
	end)
end)

T.describe("Prices.maxLevel", function()
	test("is the number of prices", function()
		expect(Prices.maxLevel(Upgrades, "Speed")).toBe(5)
		expect(Prices.maxLevel(Upgrades, "Tray")).toBe(3)
		expect(Prices.maxLevel(Upgrades, "Chairs")).toBe(3)
		expect(Prices.maxLevel(Upgrades, "Tips")).toBe(5)
	end)

	test("is 0 for unknown ids", function()
		expect(Prices.maxLevel(Upgrades, "Rocket")).toBe(0)
		expect(Prices.maxLevel(Upgrades, "Order")).toBe(0)
	end)
end)

T.describe("Prices.makeSeconds", function()
	test("level 0 holds for the base 2 s", function()
		expect(Prices.makeSeconds(0, CFG)).toBe(2)
	end)

	test("level 99 is clamped to the 0.5 s minimum", function()
		expect(Prices.makeSeconds(99, CFG)).toBe(0.5)
	end)

	test("each Faster Hands level is a real step faster", function()
		local previous = math.huge
		for level = 0, Prices.maxLevel(Upgrades, "Speed") do
			local seconds = Prices.makeSeconds(level, CFG)
			expect(seconds < previous).toBe(true)
			expect(seconds >= CFG.MinMakeSeconds).toBe(true)
			previous = seconds
		end
		expect(Prices.makeSeconds(1, CFG)).toBeCloseTo(1.6)
	end)

	test("a junk level holds for the base time", function()
		expect(Prices.makeSeconds(-3, CFG)).toBe(2)
		expect(Prices.makeSeconds(0 / 0, CFG)).toBe(2)
		expect(Prices.makeSeconds(nil :: any, CFG)).toBe(2)
	end)
end)

T.describe("Prices.capacity", function()
	test("is 1 + Tray level", function()
		expect(Prices.capacity(0)).toBe(1)
		expect(Prices.capacity(2)).toBe(3)
		expect(Prices.capacity(3)).toBe(4)
	end)

	test("a junk level carries 1", function()
		expect(Prices.capacity(-2)).toBe(1)
		expect(Prices.capacity(0 / 0)).toBe(1)
		expect(Prices.capacity(math.huge)).toBe(1)
	end)
end)

T.describe("Prices.patience", function()
	test("adds 10 s per Comfy Chairs level", function()
		expect(Prices.patience(0, CFG)).toBe(60)
		expect(Prices.patience(1, CFG)).toBe(70)
		expect(Prices.patience(3, CFG)).toBe(90)
	end)

	test("a junk level waits the base time", function()
		expect(Prices.patience(-1, CFG)).toBe(60)
		expect(Prices.patience(0 / 0, CFG)).toBe(60)
	end)
end)
