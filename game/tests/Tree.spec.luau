--!strict
-- The Branch Ability Tree (Logic/Tree; Progression v2 build plan §B5/§B7).

local T = require("./expect")
local expect, test = T.expect, T.test

local Tree = require("../src/shared/Logic/Tree")
local TreeData = require("../src/shared/Data/Tree")

local NODES = TreeData.Nodes

T.describe("Tree", function()
	test("CAPSTONE_NEEDS matches Data/Tree", function()
		expect(Tree.CAPSTONE_NEEDS).toBe(TreeData.CapstoneNeeds)
	end)

	test("canBuy: known, under Max, the capstone gate, then points", function()
		expect((Tree.canBuy({}, 1, "GentleWords", NODES))).toBe(true)
		local ok, message = Tree.canBuy({}, 0, "GentleWords", NODES)
		expect(ok).toBe(false)
		expect(message).toBe("Need 🌳1")
		ok, message = Tree.canBuy({ GentleWords = 3 }, 5, "GentleWords", NODES)
		expect(ok).toBe(false)
		expect(message).toBe("Max rank!")
		ok, message = Tree.canBuy({ GentleWords = 3, ThankYou = 2 }, 9, "TwinCounters", NODES)
		expect(ok).toBe(false)
		expect(message).toBe("Need 6 🌳 in Care")
		-- 6 points in Speed don't open Care's capstone
		ok = Tree.canBuy({ NimbleFingers = 3, QuickFeet = 3 }, 9, "TwinCounters", NODES)
		expect(ok).toBe(false)
		ok, message = Tree.canBuy({ GentleWords = 3, ThankYou = 3 }, 1, "TwinCounters", NODES)
		expect(ok).toBe(false)
		expect(message).toBe("Need 🌳2")
		expect((Tree.canBuy({ GentleWords = 3, ThankYou = 3 }, 2, "TwinCounters", NODES))).toBe(true)
		ok, message = Tree.canBuy({}, 9, "Order", NODES)
		expect(ok).toBe(false)
		expect(message).toBe("Oops! Try again.")
	end)

	test("buy adds a rank and spends; a refused buy changes nothing; inputs never change", function()
		local tree = { GentleWords = 1 }
		local after, points = Tree.buy(tree, 3, "GentleWords", NODES)
		expect(after).toEqual({ GentleWords = 2 })
		expect(points).toBe(2)
		expect(tree).toEqual({ GentleWords = 1 })
		local same, kept = Tree.buy(tree, 3, "TwinCounters", NODES)
		expect(same).toEqual({ GentleWords = 1 })
		expect(kept).toBe(3)
	end)

	test("the whole tree costs 33 points, and a refund gives every point back (unknown nodes at 1 a rank)", function()
		local tree: { [string]: number } = {}
		local points = 33
		for _, branch in TreeData.BranchOrder do
			for _, id in NODES.Order do
				local node = NODES[id]
				if node.Branch == branch and not node.Capstone then
					for _ = 1, node.Max do
						tree, points = Tree.buy(tree, points, id, NODES)
					end
				end
			end
			for _, id in NODES.Order do
				if NODES[id].Branch == branch and NODES[id].Capstone then
					tree, points = Tree.buy(tree, points, id, NODES)
				end
			end
		end
		expect(points).toBe(0)
		expect(Tree.refund(tree, NODES)).toBe(33)
		expect(Tree.spent(tree, NODES, "Care")).toBe(11)
		tree.OldNode = 2
		expect(Tree.refund(tree, NODES)).toBe(35)
		expect(Tree.refund(nil, NODES)).toBe(0)
	end)

	test("effects: rank x Value per key; capstones as flags (DoubleShift's Value)", function()
		local effects = Tree.effects({
			GentleWords = 2,
			SteadyHands = 3,
			QuickFeet = 1,
			ExpressLift = 3,
			Bargain = 2,
			DoubleShift = 1,
			LuckyStock = 1,
			OldNode = 3,
		}, NODES)
		expect(effects.Patience).toBe(20)
		expect(effects.Ease).toBeCloseTo(0.3)
		expect(effects.Walk).toBe(1)
		expect(effects.Lift).toBeCloseTo(0.6)
		expect(effects.Bargain).toBeCloseTo(0.1)
		expect(effects.DoubleShift).toBe(1.25)
		expect(effects.LuckyStock).toBe(1)
		expect(effects.TwinCounters).toBeNil()
		expect(Tree.effects({ GentleWords = 99 }, NODES).Patience).toBe(30) -- never past Max
	end)
end)
