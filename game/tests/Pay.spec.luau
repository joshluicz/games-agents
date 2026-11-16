--!strict
-- Cure pay maths (build plan §B6, Task 3). Logic/Pay never requires Config, so CFG copies the §B2 values.

local T = require("./expect")
local expect, test = T.expect, T.test

local Pay = require("../src/shared/Logic/Pay")

local CFG = {
	BasePay = 12,
	QuickServeBonus = 0.5,
	TipsPerLevel = 0.2,
	NightPayMultiplier = 2,
	SparklyMultiplier = 2,
	FrostyMultiplier = 1.5,
	VisitorMultiplier = 3,
}

-- A plain day cure with full patience; override any field.
local function args(overrides: { [string]: any }?): Pay.RewardArgs
	local out: any = {
		BasePay = CFG.BasePay,
		Tips = 0,
		PatienceLeft = 1,
		Night = false,
		Variant = nil,
		Visitor = false,
		Regular = false,
		Cfg = CFG,
	}
	for key, value in overrides or {} do
		out[key] = value
	end
	return out
end

T.describe("Pay.reward", function()
	test("base 12 with full patience pays 18 (12 x 1.5) and 1 star", function()
		expect(Pay.reward(args())).toEqual({ Cash = 18, Stars = 1 })
	end)

	test("no patience left pays the base", function()
		expect(Pay.reward(args({ PatienceLeft = 0 })).Cash).toBe(12)
	end)

	test("half patience pays half the quick-serve bonus", function()
		expect(Pay.reward(args({ PatienceLeft = 0.5 })).Cash).toBe(15)
	end)

	test("night doubles cash and gives 2 stars", function()
		expect(Pay.reward(args({ Night = true }))).toEqual({ Cash = 36, Stars = 2 })
	end)

	test("sparkly doubles cash", function()
		expect(Pay.reward(args({ Variant = "Sparkly" }))).toEqual({ Cash = 36, Stars = 1 })
	end)

	test("frosty pays x1.5", function()
		expect(Pay.reward(args({ Variant = "Frosty" })).Cash).toBe(27)
	end)

	test("an unknown variant pays like no variant", function()
		expect(Pay.reward(args({ Variant = "Golden" })).Cash).toBe(18)
	end)

	test("Today's Visitor pays x3 and gives 3 stars", function()
		expect(Pay.reward(args({ Visitor = true }))).toEqual({ Cash = 54, Stars = 3 })
	end)

	test("a regular gives 3 stars and normal cash", function()
		expect(Pay.reward(args({ Regular = true }))).toEqual({ Cash = 18, Stars = 3 })
	end)

	test("stars take the best reason, they don't add up", function()
		expect(Pay.reward(args({ Night = true, Regular = true })).Stars).toBe(3)
		expect(Pay.reward(args({ Night = true, Visitor = true })).Stars).toBe(3)
	end)

	test("each Tip Jar level adds 20%", function()
		-- 12 x 1.5 x 1.4 = 25.2
		expect(Pay.reward(args({ Tips = 2 })).Cash).toBe(25)
		-- 12 x 1.5 x 2.0 = 36
		expect(Pay.reward(args({ Tips = 5 })).Cash).toBe(36)
	end)

	test("multipliers stack", function()
		-- 12 x 1.5 (quick) x 2 (night) x 2 (sparkly) x 3 (visitor) = 216
		local reward = Pay.reward(args({ Night = true, Variant = "Sparkly", Visitor = true }))
		expect(reward).toEqual({ Cash = 216, Stars = 3 })
	end)

	test("cash is always a whole number", function()
		for _, patience in { 0, 0.1, 0.33, 0.5, 0.77, 1 } do
			for tips = 0, 5 do
				local cash = Pay.reward(args({ PatienceLeft = patience, Tips = tips, Variant = "Frosty" })).Cash
				expect(cash).toBe(math.floor(cash))
			end
		end
	end)

	test("cash is never below 1", function()
		expect(Pay.reward(args({ BasePay = 0 })).Cash).toBe(1)
		expect(Pay.reward(args({ BasePay = -50 })).Cash).toBe(1)
		expect(Pay.reward(args({ BasePay = 0.2, PatienceLeft = 0 })).Cash).toBe(1)
	end)

	test("patience outside 0..1 is clamped", function()
		expect(Pay.reward(args({ PatienceLeft = 5 })).Cash).toBe(18)
		expect(Pay.reward(args({ PatienceLeft = -3 })).Cash).toBe(12)
	end)

	test("junk numbers fall back to safe values", function()
		expect(Pay.reward(args({ PatienceLeft = 0 / 0 })).Cash).toBe(12)
		expect(Pay.reward(args({ PatienceLeft = math.huge })).Cash).toBe(18)
		expect(Pay.reward(args({ Tips = 0 / 0 })).Cash).toBe(18)
		expect(Pay.reward(args({ Tips = -4 })).Cash).toBe(18)
		expect(Pay.reward(args({ BasePay = 0 / 0 })).Cash).toBe(1)
		expect(Pay.reward(args({ BasePay = math.huge })).Cash).toBe(1)
	end)

	test("a Cash boost multiplies the whole pay", function()
		-- 18 x 1.2 = 21.6
		expect(Pay.reward(args({ CashBoost = 1.2 })).Cash).toBe(22)
		-- 36 (night) x 1.5 = 54
		expect(Pay.reward(args({ Night = true, CashBoost = 1.5 })).Cash).toBe(54)
	end)

	test("a Tips boost adds onto the Tip Jar factor, even with no Tip Jar", function()
		-- 12 x 1.5 x (1 + 0.5) = 27
		expect(Pay.reward(args({ TipsBoost = 0.5 })).Cash).toBe(27)
		-- 12 x 1.5 x (1 + 0.4 + 0.5) = 34.2
		expect(Pay.reward(args({ Tips = 2, TipsBoost = 0.5 })).Cash).toBe(34)
	end)

	test("a Stars boost multiplies the stars", function()
		expect(Pay.reward(args({ StarsBoost = 2 })).Stars).toBe(2)
		expect(Pay.reward(args({ Visitor = true, StarsBoost = 2 })).Stars).toBe(6)
		expect(Pay.reward(args({ StarsBoost = 1.2 })).Stars).toBe(1)
	end)

	test("junk or negative boosts are neutral", function()
		for _, junk in { 0 / 0, math.huge, -3, 0, "2" } :: { any } do
			local reward = Pay.reward(args({ CashBoost = junk, TipsBoost = junk, StarsBoost = junk }))
			expect(reward).toEqual({ Cash = 18, Stars = 1 })
		end
	end)

	test("a missing Cfg field is neutral, never an error", function()
		local reward = Pay.reward(args({ Night = true, Variant = "Sparkly", Cfg = {} }))
		expect(reward).toEqual({ Cash = 12, Stars = 2 })
	end)
end)
