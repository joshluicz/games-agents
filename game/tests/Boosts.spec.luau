--!strict
-- Boosts (Logic/Boosts): permanent effects with caps, timed boosts that tick and extend, and hold times.

local T = require("./expect")
local expect, test = T.expect, T.test

local Boosts = require("../src/shared/Logic/Boosts")
local Defs = require("../src/shared/Data/Boosts")

-- Config.BoostCaps, copied (Logic never requires Config).
local CAPS = { Cash = 50, Tips = 50, Stars = 50, MakeSpeed = 40, Patience = 50 }

T.describe("Data/Boosts", function()
	test("the three play-gift boosts", function()
		expect(Defs.Order).toEqual({ "QuickHands", "LuckyTips", "StarRush" })
		expect({ Defs.QuickHands.Kind, Defs.QuickHands.Percent, Defs.QuickHands.Minutes }).toEqual({
			"MakeSpeed",
			25,
			10,
		})
		expect({ Defs.LuckyTips.Kind, Defs.LuckyTips.Percent, Defs.LuckyTips.Minutes }).toEqual({ "Tips", 50, 15 })
		expect({ Defs.StarRush.Kind, Defs.StarRush.Percent, Defs.StarRush.Minutes }).toEqual({ "Stars", 100, 10 })
	end)

	test("every boost has a known kind", function()
		for _, id in Defs.Order do
			expect(table.find(Boosts.KINDS, Defs[id].Kind) ~= nil).toBe(true)
		end
	end)
end)

T.describe("Boosts permanent", function()
	test("effects of a kind add up", function()
		local effects =
			{ { Kind = "Cash", Percent = 2 }, { Kind = "Cash", Percent = 3 }, { Kind = "Tips", Percent = 9 } }
		expect(Boosts.permanent(effects, "Cash", nil, CAPS)).toBe(5)
		expect(Boosts.permanent(effects, "Tips", nil, CAPS)).toBe(9)
		expect(Boosts.permanent(effects, "Stars", nil, CAPS)).toBe(0)
	end)

	test("a scoped effect only counts for its scope", function()
		local effects = { { Kind = "Cash", Percent = 1 }, { Kind = "Cash", Scope = "Night", Percent = 10 } }
		expect(Boosts.permanent(effects, "Cash", nil, CAPS)).toBe(1)
		expect(Boosts.permanent(effects, "Cash", { Starter = true }, CAPS)).toBe(1)
		expect(Boosts.permanent(effects, "Cash", { Night = true }, CAPS)).toBe(11)
	end)

	test("totals are capped", function()
		local effects = { { Kind = "Cash", Percent = 40 }, { Kind = "Cash", Percent = 40 } }
		expect(Boosts.permanent(effects, "Cash", nil, CAPS)).toBe(50)
		local speed = { { Kind = "MakeSpeed", Percent = 30 }, { Kind = "MakeSpeed", Percent = 30 } }
		expect(Boosts.permanent(speed, "MakeSpeed", nil, CAPS)).toBe(40)
		expect(Boosts.permanent(effects, "Cash", nil, nil)).toBe(80) -- no caps given: no cap
	end)

	test("junk percents are ignored", function()
		local effects =
			{ { Kind = "Cash", Percent = 0 / 0 }, { Kind = "Cash", Percent = -20 }, { Kind = "Cash", Percent = 3 } }
		expect(Boosts.permanent(effects :: any, "Cash", nil, CAPS)).toBe(3)
	end)

	test("summary is the everywhere percent of each kind", function()
		local effects = { { Kind = "Cash", Percent = 6 }, { Kind = "Cash", Scope = "Night", Percent = 20 } }
		local summary = Boosts.summary(effects, CAPS)
		expect(summary.Cash).toBe(6)
		expect(summary.MakeSpeed).toBe(0)
	end)
end)

T.describe("Boosts timed", function()
	test("a running boost adds its percent on top of the capped permanent part", function()
		local effects = { { Kind = "Stars", Percent = 80 } }
		local timed = { StarRush = 300 }
		expect(Boosts.percent(effects, timed, Defs, "Stars", nil, CAPS)).toBe(150) -- 50 (capped) + 100
		expect(Boosts.multiplier({}, timed, Defs, "Stars", nil, CAPS)).toBe(2)
		expect(Boosts.multiplier({}, {}, Defs, "Stars", nil, CAPS)).toBe(1)
	end)

	test("a finished or unknown boost adds nothing", function()
		expect(Boosts.timed({ StarRush = 0 }, Defs, "Stars")).toBe(0)
		expect(Boosts.timed({ Nope = 500 }, Defs, "Stars")).toBe(0)
		expect(Boosts.timed({ Order = 500 } :: any, Defs, "Stars")).toBe(0)
	end)

	test("getting it again extends it, never stacks, up to the cap", function()
		local once = Boosts.extend({}, Defs, "QuickHands", 600, 3600)
		expect(once.QuickHands).toBe(600)
		local twice = Boosts.extend(once, Defs, "QuickHands", 600, 3600)
		expect(twice.QuickHands).toBe(1200)
		expect(Boosts.timed(twice, Defs, "MakeSpeed")).toBe(25) -- the same strength
		local capped = Boosts.extend({ QuickHands = 3500 }, Defs, "QuickHands", 600, 3600)
		expect(capped.QuickHands).toBe(3600)
		expect(once.QuickHands).toBe(600) -- the input is untouched
	end)

	test("extend ignores unknown ids and junk seconds", function()
		expect(Boosts.extend({}, Defs, "Robux", 600, 3600)).toEqual({})
		expect(Boosts.extend({}, Defs, "StarRush", -5, 3600)).toEqual({})
		expect(Boosts.extend({}, Defs, "StarRush", 0 / 0, 3600)).toEqual({})
	end)

	test("tick takes play seconds off, and finished boosts go", function()
		local after = Boosts.tick({ StarRush = 100, QuickHands = 30 }, 30)
		expect(after).toEqual({ StarRush = 70 })
		expect(Boosts.tick({ StarRush = 100 }, 0 / 0)).toEqual({ StarRush = 100 })
		expect(Boosts.tick({ StarRush = 100 }, -50)).toEqual({ StarRush = 100 })
	end)

	test("soonest is the boost closest to ending", function()
		expect(Boosts.soonest({ StarRush = 100, QuickHands = 30 })).toBe(30)
		expect(Boosts.soonest({})).toBeNil()
	end)
end)

T.describe("Boosts hold time", function()
	test("MakeSpeed divides the hold time", function()
		expect(Boosts.makeSeconds(2, 25, 0.3)).toBe(1.6)
		expect(Boosts.makeSeconds(2, 0, 0.3)).toBe(2)
		expect(Boosts.makeSeconds(2, 100, 0.3)).toBe(1)
	end)

	test("never below the floor, and never above the base", function()
		expect(Boosts.makeSeconds(0.5, 400, 0.3)).toBe(0.3)
		expect(Boosts.makeSeconds(0.2, 50, 0.3)).toBe(0.2)
		expect(Boosts.makeSeconds(2, -50, 0.3)).toBe(2)
		expect(Boosts.makeSeconds(2, 0 / 0, 0.3)).toBe(2)
	end)
end)

T.describe("Boosts branch source (Progression v2)", function()
	local BRANCH_CAPS = { Cash = 30, Stars = 30, Tips = 30, MakeSpeed = 30, Patience = 50 }

	test("branch: the tree + perks percent, capped by its own caps", function()
		expect(Boosts.branch({ Cash = 20 }, "Cash", BRANCH_CAPS)).toBe(20)
		expect(Boosts.branch({ Cash = 45 }, "Cash", BRANCH_CAPS)).toBe(30)
		expect(Boosts.branch({ Patience = 50 }, "Patience", BRANCH_CAPS)).toBe(50)
		expect(Boosts.branch({ Cash = 0 / 0 }, "Cash", BRANCH_CAPS)).toBe(0)
		expect(Boosts.branch(nil, "Cash", BRANCH_CAPS)).toBe(0)
		expect(Boosts.branch({ Cash = 70 }, "Cash", nil)).toBe(70) -- no cap entry = no cap
	end)

	test("percent = min(permanent, caps) + min(branch, branchCaps) + timed: neither eats the other's room", function()
		local effects = { { Kind = "Cash", Percent = 60 } } -- badges past their cap
		local caps = { Cash = 50 }
		expect(Boosts.percent(effects, {}, {}, "Cash", nil, caps)).toBe(50)
		expect(Boosts.percent(effects, {}, {}, "Cash", nil, caps, { Cash = 40 }, BRANCH_CAPS)).toBe(80)
		local defs = { StarRush = { Name = "Star Rush", Icon = "🌠", Kind = "Stars", Percent = 100, Minutes = 10 } }
		expect(Boosts.percent({}, { StarRush = 60 }, defs, "Stars", nil, caps, { Stars = 10 }, BRANCH_CAPS)).toBe(110)
		expect(Boosts.multiplier(effects, {}, {}, "Cash", nil, caps, { Cash = 40 }, BRANCH_CAPS)).toBeCloseTo(1.8)
	end)

	test("summary adds the branch part when given; branchSummary is the branch alone", function()
		local effects = { { Kind = "Tips", Percent = 4 } }
		local caps = { Tips = 50 }
		expect(Boosts.summary(effects, caps).Tips).toBe(4)
		expect(Boosts.summary(effects, caps, { Tips = 50 }, BRANCH_CAPS).Tips).toBe(34)
		expect(Boosts.branchSummary({ Tips = 50, Patience = 20 }, BRANCH_CAPS)).toEqual({
			Cash = 0,
			Tips = 30,
			Stars = 0,
			MakeSpeed = 0,
			Patience = 20,
		})
	end)
end)
