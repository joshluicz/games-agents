--!strict
-- How big a creature is (Logic/CreatureSize). CFG copies Config.CreatureSize and Config.CreatureSizeJitter.

local T = require("./expect")
local expect, test = T.expect, T.test

local CreatureSize = require("../src/shared/Logic/CreatureSize")

local CFG = { CreatureSize = 1.6, CreatureSizeJitter = 0.08 }

T.describe("CreatureSize.jitter", function()
	test("is exactly 1 at the middle roll", function()
		expect(CreatureSize.jitter(0.5, CFG)).toBeCloseTo(1)
	end)

	test("spans 8% either way", function()
		expect(CreatureSize.jitter(0, CFG)).toBeCloseTo(0.92)
		expect(CreatureSize.jitter(1, CFG)).toBeCloseTo(1.08)
	end)

	test("clamps a roll outside 0..1 and a missing jitter", function()
		expect(CreatureSize.jitter(-3, CFG)).toBeCloseTo(0.92)
		expect(CreatureSize.jitter(7, CFG)).toBeCloseTo(1.08)
		expect(CreatureSize.jitter(0, { CreatureSize = 1.6 })).toBeCloseTo(1)
	end)
end)

T.describe("CreatureSize.scale", function()
	test("is the species size times the player-sized multiplier", function()
		expect(CreatureSize.scale(1, CFG)).toBeCloseTo(1.6)
		expect(CreatureSize.scale(0.75, CFG, 0.5)).toBeCloseTo(1.2)
		expect(CreatureSize.scale(1.25, CFG, 0.5)).toBeCloseTo(2)
	end)

	test("adds this patient's wobble", function()
		expect(CreatureSize.scale(1.25, CFG, 1)).toBeCloseTo(1.25 * 1.6 * 1.08)
		expect(CreatureSize.scale(0.75, CFG, 0)).toBeCloseTo(0.75 * 1.6 * 0.92)
	end)

	test("never makes a giant or a speck from a typo", function()
		expect(CreatureSize.scale(40, CFG, 0.5)).toBeCloseTo(2 * 1.6)
		expect(CreatureSize.scale(0, CFG, 0.5)).toBeCloseTo(0.5 * 1.6)
		expect(CreatureSize.scale(nil, CFG, 0.5)).toBeCloseTo(1.6)
	end)
end)
