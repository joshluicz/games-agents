--!nocheck
-- Creature motion maths and the badge's recipe row (depth-update perf pass, build plan §B4). The pure blocks
-- (BEGIN PURE .. END PURE) of Feel/CreatureMotion and Server/CreatureBuilder are loaded on their own, since those
-- modules use Roblox services. Run from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local T = require("./expect")
local expect, test = T.expect, T.test

local function pureBlock(path: string, returns: string): any
	local source = fs.readFile(path)
	local first = string.find(source, "-- BEGIN PURE", 1, true)
	local last = string.find(source, "-- END PURE", 1, true)
	assert(first and last, "no pure block in " .. path)
	local body = string.sub(source, first, last - 1) .. "\nreturn " .. returns
	return luau.load(body, {
		debugName = path,
		environment = { math = math, table = table, type = type, string = string },
	})()
end

local Motion = pureBlock("src/client/Feel/CreatureMotion.luau", "Motion")
local recipeLayout = pureBlock("src/server/CreatureBuilder.luau", "recipeLayout")
local urgentIcon = pureBlock("src/server/CreatureBuilder.luau", "urgentIcon")
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

T.describe("Motion", function()
	test("progress: half way, done, before the start, no length", function()
		local t, done = Motion.progress(10, 0.5, 10.25)
		expect(t).toBeCloseTo(0.5)
		expect(done).toBe(false)
		t, done = Motion.progress(10, 0.5, 10.5)
		expect(t).toBe(1)
		expect(done).toBe(true)
		t, done = Motion.progress(10, 0.5, 9)
		expect(t).toBe(0)
		expect(done).toBe(false)
		t, done = Motion.progress(10, 0, 9)
		expect(done).toBe(true)
	end)

	test("hop shape: full, and calm (lower, no lean, no spin)", function()
		local lift, lean, spin = Motion.hopShape(0.5, 0.5, 2, 0.14, math.pi * 2, false)
		expect(lift).toBeCloseTo(2)
		expect(lean).toBeCloseTo(-0.14)
		expect(spin).toBeCloseTo(math.pi)
		lift, lean, spin = Motion.hopShape(0.5, 0.5, 2, 0.14, math.pi * 2, true)
		expect(lift).toBeCloseTo(2 * Motion.CALM_HEIGHT)
		expect(lean).toBe(0)
		expect(spin).toBe(0)
	end)

	test("the head-shake starts and ends still, and calm shakes less", function()
		expect(Motion.shakeAngle(0, false)).toBeCloseTo(0)
		expect(Motion.shakeAngle(1, false)).toBeCloseTo(0)
		local biggest, calmBiggest = 0, 0
		for i = 0, 200 do
			biggest = math.max(biggest, math.abs(Motion.shakeAngle(i / 200, false)))
			calmBiggest = math.max(calmBiggest, math.abs(Motion.shakeAngle(i / 200, true)))
		end
		expect(biggest <= Motion.SHAKE_ANGLE + 1e-9).toBe(true)
		expect(calmBiggest <= Motion.SHAKE_ANGLE * Motion.CALM_SHAKE + 1e-9).toBe(true)
	end)

	test("scale never goes under MIN_SCALE; easing names fall back safely", function()
		expect(Motion.scaleValue(1, 2, 0.5)).toBeCloseTo(1.5)
		expect(Motion.scaleValue(1, 0.05, 1.2)).toBe(Motion.MIN_SCALE)
		expect(Motion.styleName("Back", false)).toBe("Back")
		expect(Motion.styleName("Back", true)).toBe("Quad")
		expect(Motion.styleName("Elastic", false)).toBe("Quad")
		expect(Motion.directionName("In")).toBe("In")
		expect(Motion.directionName("junk")).toBe("Out")
	end)

	test("attribute numbers must be finite", function()
		expect(Motion.number(2.5, 0)).toBe(2.5)
		expect(Motion.number(0 / 0, 7)).toBe(7)
		expect(Motion.number(math.huge, 7)).toBe(7)
		expect(Motion.number("3", 7)).toBe(7)
	end)

	test("the network delay: blends, clamps, ignores stale and junk samples", function()
		expect(Motion.blendDelay(nil, 0.1)).toBeCloseTo(0.1)
		expect(Motion.blendDelay(0.1, 0.2)).toBeCloseTo(0.1 + 0.1 * Motion.DELAY_BLEND)
		expect(Motion.blendDelay(nil, 0.6)).toBeCloseTo(Motion.MAX_DELAY)
		expect(Motion.blendDelay(0.1, 5)).toBe(0.1)
		expect(Motion.blendDelay(0.1, -1)).toBe(0.1)
		expect(Motion.blendDelay(0.1, 0 / 0)).toBe(0.1)
	end)

	test("same pose: tolerant of rounding, not of a move, a turn or a droop", function()
		local a = CFrame.new(10, 2, -4) * CFrame.Angles(0, 0.5, 0)
		expect(Motion.same(a, a + Vector3.new(0.004, 0, 0))).toBe(true)
		expect(Motion.same(a, a + Vector3.new(0.5, 0, 0))).toBe(false)
		expect(Motion.same(a, a * CFrame.Angles(0, 0.1, 0))).toBe(false)
		expect(Motion.same(a, a * CFrame.Angles(-0.22, 0, 0))).toBe(false)
	end)
end)

T.describe("CreatureBuilder recipe row", function()
	test("one item (or none) uses the Need chip: no row", function()
		expect(#recipeLayout(0, nil)).toBe(0)
		expect(#recipeLayout(1, 1)).toBe(0)
	end)

	test("two and three items: evenly spread, the next one bigger, cut to three", function()
		local two = recipeLayout(2, 2)
		expect(#two).toBe(2)
		expect(two[2].Size > two[1].Size).toBe(true)
		local three = recipeLayout(3, nil)
		expect(#three).toBe(3)
		expect(three[2].X - three[1].X).toBeCloseTo(three[3].X - three[2].X)
		expect(#recipeLayout(5, 1)).toBe(3)
	end)

	test("Progression v2: the urgent chip is 🚑 for A&E, 🚁 for the air ambulance, nothing otherwise", function()
		expect(urgentIcon("AE")).toBe("🚑")
		expect(urgentIcon("VIP")).toBe("🚁")
		expect(urgentIcon("")).toBe(nil)
		expect(urgentIcon(nil)).toBe(nil)
		expect(urgentIcon(1)).toBe(nil)
	end)
end)
