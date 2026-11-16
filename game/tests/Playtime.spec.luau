--!strict
-- Time-played rewards (Logic/Playtime): the daily play gifts, the day rollover and the Doctor ranks.

local T = require("./expect")
local expect, test = T.expect, T.test

local Playtime = require("../src/shared/Logic/Playtime")
local Data = require("../src/shared/Data/Playtime")
local Boosts = require("../src/shared/Data/Boosts")
local Decor = require("../src/shared/Data/Decor")

local GIFTS = Data.Gifts
local RANKS = Data.Ranks
local DAY = 20500

local function save(overrides: { [string]: any }?): Playtime.Save
	local out: any = { Day = DAY, TodaySeconds = 0, TotalSeconds = 0, Claimed = {}, Rank = 0 }
	for key, value in overrides or {} do
		out[key] = value
	end
	return out
end

T.describe("Data/Playtime", function()
	test("six gifts at 2, 5, 10, 15, 25 and 40 minutes", function()
		local minutes = {}
		for _, gift in GIFTS do
			table.insert(minutes, gift.Minutes)
		end
		expect(minutes).toEqual({ 2, 5, 10, 15, 25, 40 })
	end)

	test("rewards grow through the day and the last gift is the biggest", function()
		for index = 2, #GIFTS do
			expect(GIFTS[index].Cash >= GIFTS[index - 1].Cash).toBe(true)
		end
		expect(GIFTS[#GIFTS].Cash).toBe(150)
	end)

	test("every gift boost is a real timed boost", function()
		for _, gift in GIFTS do
			if gift.Boost then
				expect(rawget(Boosts :: any, gift.Boost) ~= nil).toBe(true)
			end
		end
	end)

	test("ranks at 1, 3, 10, 25, 50 and 100 hours, each with its own earned decor", function()
		local hours, names = {}, {}
		local seen = {}
		for _, rank in RANKS do
			table.insert(hours, rank.Hours)
			table.insert(names, rank.Name)
			local decor = rawget(Decor :: any, rank.Decor)
			expect(decor ~= nil).toBe(true)
			expect(decor.EarnedBy).toBe("Playtime")
			expect(seen[rank.Decor]).toBeNil()
			seen[rank.Decor] = true
		end
		expect(hours).toEqual({ 1, 3, 10, 25, 50, 100 })
		expect(names).toEqual({ "Intern", "Resident", "Doctor", "Senior Doctor", "Chief", "Legend" })
	end)

	test("rank cash boosts are +2/4/6/8/10/15%", function()
		local cash = {}
		for _, rank in RANKS do
			table.insert(cash, rank.Cash)
		end
		expect(cash).toEqual({ 2, 4, 6, 8, 10, 15 })
	end)
end)

T.describe("Playtime gifts", function()
	test("a gift is locked until its minutes of play today", function()
		expect(Playtime.state(save({ TodaySeconds = 119 }), DAY, GIFTS, 1)).toBe("Locked")
		expect(Playtime.state(save({ TodaySeconds = 120 }), DAY, GIFTS, 1)).toBe("Ready")
		expect(Playtime.state(save({ TodaySeconds = 120 }), DAY, GIFTS, 2)).toBe("Locked")
	end)

	test("ready lists every unlocked gift not opened yet", function()
		expect(Playtime.ready(save({ TodaySeconds = 11 * 60 }), DAY, GIFTS)).toEqual({ 1, 2, 3 })
		expect(Playtime.ready(save({ TodaySeconds = 11 * 60, Claimed = { 1, 3 } }), DAY, GIFTS)).toEqual({ 2 })
	end)

	test("claiming a ready gift marks it once and returns it", function()
		local after, gift = Playtime.claim(save({ TodaySeconds = 300 }), DAY, GIFTS, 2)
		expect(gift).toBe(GIFTS[2])
		expect(after.Claimed).toEqual({ 2 })
		local again, none = Playtime.claim(after, DAY, GIFTS, 2)
		expect(none).toBeNil()
		expect(again.Claimed).toEqual({ 2 })
	end)

	test("a locked gift, a bad index or junk never pays", function()
		for _, junk in { 0, 7, 1.5, -1, 0 / 0, math.huge, "1" } :: { any } do
			local _, gift = Playtime.claim(save({ TodaySeconds = 99999 }), DAY, GIFTS, junk)
			expect(gift).toBeNil()
		end
		local _, locked = Playtime.claim(save({ TodaySeconds = 60 }), DAY, GIFTS, 1)
		expect(locked).toBeNil()
	end)

	test("claim keeps the list sorted and never changes its input", function()
		local before = save({ TodaySeconds = 3000, Claimed = { 3 } })
		local after = Playtime.claim(before, DAY, GIFTS, 1)
		expect(after.Claimed).toEqual({ 1, 3 })
		expect(before.Claimed).toEqual({ 3 })
	end)

	test("next gift is the first still locked, with the seconds left", function()
		local index, left = Playtime.nextGift(save({ TodaySeconds = 200 }), DAY, GIFTS)
		expect(index).toBe(2)
		expect(left).toBe(100)
		local none, zero = Playtime.nextGift(save({ TodaySeconds = 40 * 60 }), DAY, GIFTS)
		expect(none).toBeNil()
		expect(zero).toBe(0)
	end)

	test("all opened is the natural stopping point", function()
		expect(Playtime.allOpened(save({ TodaySeconds = 99999, Claimed = { 1, 2, 3, 4, 5 } }), DAY, GIFTS)).toBe(false)
		expect(Playtime.allOpened(save({ TodaySeconds = 99999, Claimed = { 1, 2, 3, 4, 5, 6 } }), DAY, GIFTS)).toBe(
			true
		)
	end)
end)

T.describe("Playtime days", function()
	test("a new UTC day refills the gifts and starts today's time again", function()
		local yesterday =
			save({ Day = DAY - 1, TodaySeconds = 3000, TotalSeconds = 9000, Claimed = { 1, 2 }, Rank = 2 })
		local rolled = Playtime.rollover(yesterday, DAY)
		expect(rolled).toEqual({ Day = DAY, TodaySeconds = 0, TotalSeconds = 9000, Claimed = {}, Rank = 2 })
		expect(yesterday.Claimed).toEqual({ 1, 2 }) -- the input is untouched
	end)

	test("the same day keeps everything", function()
		local today = save({ TodaySeconds = 500, TotalSeconds = 900, Claimed = { 1 } })
		expect(Playtime.rollover(today, DAY)).toEqual(today)
	end)

	test("days away cost nothing: no streak, the same refill", function()
		local long = Playtime.rollover(save({ Day = DAY - 30, TotalSeconds = 50, Claimed = { 1 } }), DAY)
		local short = Playtime.rollover(save({ Day = DAY - 1, TotalSeconds = 50, Claimed = { 1 } }), DAY)
		expect(long).toEqual(short)
	end)

	test("add rolls over, then counts toward today and the total", function()
		local after = Playtime.add(save({ Day = DAY - 1, TodaySeconds = 2000, TotalSeconds = 2000 }), DAY, 30)
		expect(after.TodaySeconds).toBe(30)
		expect(after.TotalSeconds).toBe(2030)
		expect(after.Day).toBe(DAY)
	end)

	test("add ignores junk and negative seconds", function()
		for _, junk in { -5, 0 / 0, math.huge, 0 } do
			local after = Playtime.add(save({ TodaySeconds = 10, TotalSeconds = 10 }), DAY, junk)
			expect(after.TodaySeconds).toBe(10)
			expect(after.TotalSeconds).toBe(10)
		end
	end)

	test("yesterday's opened gifts don't count on a new day", function()
		local yesterday = save({ Day = DAY - 1, TodaySeconds = 40 * 60, Claimed = { 1, 2, 3, 4, 5, 6 } })
		expect(Playtime.state(yesterday, DAY, GIFTS, 1)).toBe("Locked")
		expect(Playtime.allOpened(yesterday, DAY, GIFTS)).toBe(false)
	end)
end)

T.describe("Playtime ranks", function()
	test("rank from total seconds", function()
		expect(Playtime.rankFor(0, RANKS)).toBe(0)
		expect(Playtime.rankFor(3599, RANKS)).toBe(0)
		expect(Playtime.rankFor(3600, RANKS)).toBe(1)
		expect(Playtime.rankFor(3 * 3600, RANKS)).toBe(2)
		expect(Playtime.rankFor(99 * 3600, RANKS)).toBe(5)
		expect(Playtime.rankFor(500 * 3600, RANKS)).toBe(6)
		expect(Playtime.rankFor(0 / 0, RANKS)).toBe(0)
	end)

	test("next rank and the time to it", function()
		local index, left = Playtime.nextRank(4 * 3600 + 12 * 60, RANKS)
		expect(index).toBe(3)
		expect(left).toBe(10 * 3600 - (4 * 3600 + 12 * 60))
		local none = Playtime.nextRank(100 * 3600, RANKS)
		expect(none).toBeNil()
	end)

	test("new ranks are the ones reached but not rewarded", function()
		expect(Playtime.newRanks(save({ TotalSeconds = 11 * 3600, Rank = 1 }), RANKS)).toEqual({ 2, 3 })
		expect(Playtime.newRanks(save({ TotalSeconds = 11 * 3600, Rank = 3 }), RANKS)).toEqual({})
		expect(Playtime.newRanks(save({ TotalSeconds = 100, Rank = 0 }), RANKS)).toEqual({})
	end)
end)

T.describe("Playtime idle and text", function()
	test("active means moved or acted within the idle time", function()
		expect(Playtime.active(100, 399, 300)).toBe(true)
		expect(Playtime.active(100, 400, 300)).toBe(false)
		expect(Playtime.active(0 / 0, 1, 300)).toBe(false)
	end)

	test("durations read like a kid would say them", function()
		expect(Playtime.duration(45)).toBe("45s")
		expect(Playtime.duration(12 * 60 + 30)).toBe("12m")
		expect(Playtime.duration(4 * 3600)).toBe("4h")
		expect(Playtime.duration(4 * 3600 + 12 * 60 + 5)).toBe("4h 12m")
		expect(Playtime.duration(-5)).toBe("0s")
	end)

	test("clocks round up so zero only shows at zero", function()
		expect(Playtime.clock(185)).toBe("3:05")
		expect(Playtime.clock(0.2)).toBe("0:01")
		expect(Playtime.clock(0)).toBe("0:00")
		expect(Playtime.clock(3725)).toBe("1:02:05")
	end)
end)
