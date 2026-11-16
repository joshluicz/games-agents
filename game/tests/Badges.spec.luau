--!strict
-- Achievement badges (Logic/Badges, Data/Badges): tiers, derived stats, rewards, boosts and seeding old saves.

local T = require("./expect")
local expect, test = T.expect, T.test

local Badges = require("../src/shared/Logic/Badges")
local Data = require("../src/shared/Data/Badges")
local Boosts = require("../src/shared/Logic/Boosts")
local Schema = require("../src/shared/Logic/Schema")
local Wings = require("../src/shared/Data/Wings")

local DEFS = Data.List :: { Badges.Def }
local TIERS = Data.Tiers :: { Badges.Tier }

local function def(id: string): Badges.Def
	for _, found in DEFS do
		if found.Id == id then
			return found
		end
	end
	error("no badge " .. id)
end

local function words(text: string): number
	local n = 0
	for _ in string.gmatch(text, "%S+") do
		n += 1
	end
	return n
end

T.describe("Data/Badges", function()
	test("six tiers, Bronze to Mythic, with growing rewards", function()
		local names = {}
		for index, tier in TIERS do
			table.insert(names, tier.Name)
			if index > 1 then
				expect(tier.Cash > TIERS[index - 1].Cash).toBe(true)
				expect(tier.Stars > TIERS[index - 1].Stars).toBe(true)
			end
			expect(string.sub(tier.Color, 1, 1)).toBe("#")
		end
		expect(names).toEqual({ "Bronze", "Silver", "Gold", "Diamond", "Ruby", "Mythic" })
	end)

	test("every badge: a unique id, a known category, 6 rising thresholds, a short goal, a known boost", function()
		local categories = {}
		for _, category in Data.Categories do
			categories[category.Id] = true
		end
		local seen = {}
		for _, badge in DEFS do
			expect(seen[badge.Id]).toBeNil()
			seen[badge.Id] = true
			expect(categories[badge.Category]).toBe(true)
			expect(#badge.Thresholds).toBe(#TIERS)
			for index = 2, #badge.Thresholds do
				expect(badge.Thresholds[index] > badge.Thresholds[index - 1]).toBe(true)
			end
			if words(badge.Goal) > 6 then
				error(badge.Id .. " goal too long: " .. badge.Goal)
			end
			expect(table.find(Boosts.KINDS, badge.Boost.Kind) ~= nil).toBe(true)
			expect(badge.Boost.Percent > 0).toBe(true)
		end
	end)

	test("Healer counts cures at 25 / 100 / 500 / 2,000 / 10,000 / 50,000 for +1% Cash a tier", function()
		local healer = def("Healer")
		expect(healer.Stat).toBe("Cures")
		expect(healer.Thresholds).toEqual({ 25, 100, 500, 2000, 10000, 50000 })
		expect(healer.Boost).toEqual({ Kind = "Cash", Percent = 1 })
	end)

	test("a badge for every wing and every station", function()
		for _, wingId in Wings.Order do
			if Wings[wingId].Rebirths ~= nil then
				continue -- Progression v2's wings (Sunny, Sky) count toward 🏢 Branches, not a badge of their own
			end
			local found = false
			for _, badge in DEFS do
				found = found or badge.Stat == "Cures:" .. wingId
			end
			expect(found).toBe(true)
		end
		for _, stationId in { "Remedy", "Plaster", "Bath", "Cocoa" } do
			local badge = nil
			for _, candidate in DEFS do
				if candidate.Stat == "Made:" .. stationId then
					badge = candidate
				end
			end
			expect(badge ~= nil).toBe(true)
			expect((badge :: any).Boost).toEqual({ Kind = "MakeSpeed", Scope = stationId, Percent = 3 })
		end
	end)

	test("every badge at Mythic stays inside the boost caps", function()
		local effects = {}
		for _, badge in DEFS do
			table.insert(
				effects,
				{ Kind = badge.Boost.Kind, Scope = badge.Boost.Scope, Percent = Badges.boostAt(badge, 6) }
			)
		end
		-- Unscoped totals alone (the caps then still hold scoped extras in check).
		local summary = Boosts.summary(effects, nil)
		expect(summary.MakeSpeed <= 40).toBe(true)
		expect(summary.Patience <= 50).toBe(true)
		expect(summary.Tips <= 50).toBe(true)
	end)
end)

T.describe("Badges tiers", function()
	test("tier from a value", function()
		local thresholds = { 25, 100, 500, 2000, 10000, 50000 }
		expect(Badges.tierFor(0, thresholds)).toBe(0)
		expect(Badges.tierFor(24, thresholds)).toBe(0)
		expect(Badges.tierFor(25, thresholds)).toBe(1)
		expect(Badges.tierFor(499, thresholds)).toBe(2)
		expect(Badges.tierFor(1e9, thresholds)).toBe(6)
		expect(Badges.tierFor(0 / 0, thresholds)).toBe(0)
	end)

	test("progress runs from the last tier to the next", function()
		expect(Badges.progress(50, { 25, 100, 500 })).toEqual({ Tier = 1, Prev = 25, Next = 100, Ratio = 1 / 3 })
		expect(Badges.progress(600, { 25, 100, 500 })).toEqual({ Tier = 3, Prev = 500, Ratio = 1 })
	end)

	test("ups are badges past their saved tier, and tiers never go down", function()
		local data = Schema.default()
		data.Stats = { Cures = 120, ["Made:Remedy"] = 30 }
		local ups = Badges.ups({ Healer = 1 }, data, DEFS)
		local byId = {}
		for _, up in ups do
			byId[up.Id] = up
		end
		expect(byId.Healer).toEqual({ Id = "Healer", From = 1, To = 2 })
		expect(byId.Potions).toEqual({ Id = "Potions", From = 0, To = 1 })
		expect(#Badges.ups({ Healer = 5, Potions = 1 }, data, DEFS)).toBe(0) -- a higher saved tier stays
	end)

	test("force takes every badge to the top", function()
		local ups = Badges.ups({}, Schema.default(), DEFS, true)
		expect(#ups).toBe(#DEFS)
		for _, up in ups do
			expect(up.To).toBe(6)
		end
	end)

	test("rewards add up the tiers passed", function()
		expect(Badges.reward(0, 1, TIERS)).toEqual({ Cash = 50, Stars = 2 })
		expect(Badges.reward(1, 3, TIERS)).toEqual({ Cash = 550, Stars = 12 })
		expect(Badges.reward(3, 3, TIERS)).toEqual({ Cash = 0, Stars = 0 })
		expect(Badges.reward(0, 99, TIERS).Cash).toBe(50 + 150 + 400 + 1000 + 2500 + 6000)
	end)

	test("effects are each badge's boost times its saved tier", function()
		local effects = Badges.effects({ Healer = 3, NightShift = 2 }, DEFS)
		expect(effects).toEqual({
			{ Kind = "Cash", Percent = 3 },
			{ Kind = "Cash", Scope = "Night", Percent = 10 },
		})
		expect(Badges.effects({}, DEFS)).toEqual({})
	end)
end)

T.describe("Badges stats", function()
	test("counters come from Stats, missing ones are 0", function()
		local data = Schema.default()
		data.Stats = { Cures = 7 }
		expect(Badges.statValue(data, "Cures")).toBe(7)
		expect(Badges.statValue(data, "NightCures")).toBe(0)
		expect(Badges.statValue(nil, "Cures")).toBe(0)
	end)

	test("play hours, story beats and builder are worked out from the save", function()
		local data = Schema.default()
		data.Playtime.TotalSeconds = 5 * 3600 + 59
		data.Story = { ShySprout = { Beat = 3, LastBeatDay = 1 }, GrumpyTeapot = { Beat = 2, LastBeatDay = 1 } }
		data.Rooms = { Stand = true, BathRoom = true, Ward = true }
		data.Decor.Owned = { PottedFern = true, HeartRug = true }
		expect(Badges.statValue(data, "PlayHours")).toBe(5)
		expect(Badges.statValue(data, "Beats")).toBe(5)
		expect(Badges.statValue(data, "Builder")).toBe(4) -- 2 rooms (the Stand doesn't count) + 2 decor
	end)

	test("Progression v2: Builder keeps the rooms rebirths reset; Rebirths is the rebirth count", function()
		local data = Schema.default()
		data.Rooms = { Stand = true, BathRoom = true }
		data.Decor.Owned = { PottedFern = true }
		data.Stats.RoomsBefore = 4
		expect(Badges.statValue(data, "Builder")).toBe(6) -- 1 room + 4 reset + 1 decor
		expect(Badges.statValue(data, "Rebirths")).toBe(0)
		data.Rebirth.Count = 5
		expect(Badges.statValue(data, "Rebirths")).toBe(5)
		expect(Badges.DERIVED.Rebirths).toBe(true)
		expect(Badges.statValue({ Rebirth = "junk" }, "Rebirths")).toBe(0)
		-- a derived stat is never written as a counter by maxed()
		expect(Badges.maxed({}, { { Id = "Branches", Stat = "Rebirths", Thresholds = { 1, 12 } } } :: any)).toEqual({})
	end)

	test("add counts whole positive amounts and copies", function()
		local stats = { Cures = 1 }
		local after = Badges.add(stats, { Cures = 2, ["Made:Bath"] = 1, Junk = -4, Half = 0.5 })
		expect(after).toEqual({ Cures = 3, ["Made:Bath"] = 1 })
		expect(stats).toEqual({ Cures = 1 })
	end)

	test("seed works out counters from an older save", function()
		local data = Schema.reconcile({
			Version = 2,
			Cured = 40,
			VisitorDay = 20400,
			Book = {
				DumplingFrog = { Cured = 6, Variants = {} },
				GlowMoth = { Cured = 2, Variants = {} },
			},
		})
		local creatures = {
			DumplingFrog = { Wing = "Starter", Station = "Remedy", Night = false },
			GlowMoth = { Wing = "Night", Station = "Plaster", Night = true },
		}
		local stats = Badges.seed(data, creatures)
		expect(stats).toEqual({
			Cures = 40,
			["Cures:Starter"] = 6,
			["Cures:Night"] = 2,
			NightCures = 2,
			["Made:Remedy"] = 6,
			["Made:Plaster"] = 2,
			Visitors = 1,
			Seeded = 1,
		})
	end)

	test("maxed lifts every counter to its top threshold, never lowers one", function()
		local stats = Badges.maxed({ Cures = 99999 }, DEFS)
		expect(stats.Cures).toBe(99999)
		expect(stats.NightCures).toBe(6000)
		expect(stats.PlayHours).toBeNil() -- derived: worked out from the save, never a counter
	end)
end)
