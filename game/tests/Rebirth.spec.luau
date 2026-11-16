--!strict
-- Rebirths: "Open a new branch" (Logic/Rebirth; Progression v2 build plan §B1/§B5/§B7). The required table test of
-- Rebirth.apply walks EVERY save field and says whether it's kept or reset.

local T = require("./expect")
local expect, test = T.expect, T.test

local Rebirth = require("../src/shared/Logic/Rebirth")
local Tree = require("../src/shared/Logic/Tree")
local Schema = require("../src/shared/Logic/Schema")
local Perks = require("../src/shared/Data/Perks")
local Themes = require("../src/shared/Data/Themes")
local TreeData = require("../src/shared/Data/Tree")
local Nurses = require("../src/shared/Data/Nurses")
local Decor = require("../src/shared/Data/Decor")
local Config = require("./config")

local CONTENT = { Perks = Perks, Themes = Themes, Nurses = Nurses, Decor = Decor }

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, item in value do
		out[key] = deepCopy(item)
	end
	return out
end

-- A rich Lv 5 save that has touched every field.
local function richSave(): any
	local data = Schema.default()
	data.Cash = 60000
	data.Stars = 321
	data.Cured = 4000
	data.Upgrades = { Speed = 5, Tray = 3, Chairs = 2, Tips = 4, WardComfort = 2, AESpeed = 1, NightClinic = 0 }
	data.Rooms = { Stand = true, BathRoom = true, Ward = true, WinterWing = true, Garden = true }
	data.Decor = {
		Owned = { PottedFern = true, CozyRug = true, HeartRug = true },
		Placed = { ["Stand:1"] = "PottedFern", ["BathRoom:1"] = "CozyRug", ["Garden:2"] = "HeartRug" },
	}
	data.Book = { DumplingFrog = { Cured = 12, Variants = { Sparkly = true } } }
	data.Story = { ShySprout = { Beat = 5, LastBeatDay = 20500 } }
	data.Daily = { Goals = { { Id = "Cure5", Progress = 2, Day = 20500 } }, LastGrantDay = 20500 }
	data.Mailbox = { LastSeenDay = 20500 }
	data.HeartsGiven = { Day = 20500, Plots = { ["7"] = true } }
	data.ReferralRewarded = true
	data.VisitorDay = 20500
	data.HeartsReceived = 9
	data.Tutorial = 9
	data.WeekCures = { Week = 2968, Count = 50 }
	data.Playtime = { Day = 20500, TodaySeconds = 900, TotalSeconds = 99999, Claimed = { 1, 2 }, Rank = 4 }
	data.Boosts = { StarRush = 300 }
	data.Stats = { Seeded = 1, Cures = 4000, RoomsBefore = 2 }
	data.Badges = { Healer = 3 }
	data.Level = 5
	data.Nurses = { PuffPup = { Level = 7, XP = 12, Copies = 4, Job = "Porter" } }
	data.NurseIndex = { PuffPup = "Hired", MintMouse = "Seen" }
	data.JournalSets = { Common = true }
	data.Simple = true
	data.Rebirth = {
		Count = 0,
		Points = 1,
		Tree = { GentleWords = 2 },
		Perks = { "BigHands" },
		Offer = {},
		Theme = "",
		Pending = {},
		Told = true,
	}
	return data
end

T.describe("Rebirth cost and checks", function()
	test("cost: the table, then x1.5 a rebirth rounded to 2 significant figures", function()
		local costs = {}
		for count = 0, 9 do
			costs[count + 1] = Rebirth.cost(count, Config)
		end
		expect(costs).toEqual({ 50000, 75000, 110000, 170000, 250000, 380000, 570000, 850000, 1300000, 1900000 })
		expect(Rebirth.cost(10, Config)).toBe(2900000) -- 2,850,000 -> 2.9M
		expect(Rebirth.cost(11, Config)).toBe(4400000) -- 4,350,000 -> 4.4M
		expect(Rebirth.cost(-3, Config)).toBe(50000)
	end)

	test("canRebirth: a Mega Hospital, then the cash", function()
		local data = richSave()
		expect({ Rebirth.canRebirth(data, Config) }).toEqual({ true, "" })
		data.Level = 4
		expect({ Rebirth.canRebirth(data, Config) }).toEqual({ false, "Need 🏙️ Lv 5" })
		data.Level = 5
		data.Cash = 49999
		expect({ Rebirth.canRebirth(data, Config) }).toEqual({ false, "Need 💰50,000" })
		data.Cash = 80000
		data.Rebirth.Count = 1
		expect({ Rebirth.canRebirth(data, Config) }).toEqual({ true, "" })
		data.Rebirth.Count = 2
		expect({ Rebirth.canRebirth(data, Config) }).toEqual({ false, "Need 💰110,000" })
		expect((Rebirth.canRebirth(nil, Config))).toBe(false)
	end)

	test("multiplier: +25% a rebirth, added, up to 20 (§E12)", function()
		expect(Rebirth.multiplier(0, Config)).toBe(1)
		expect(Rebirth.multiplier(1, Config)).toBe(1.25)
		expect(Rebirth.multiplier(4, Config)).toBe(2)
		expect(Rebirth.multiplier(8, Config)).toBe(3)
		expect(Rebirth.multiplier(20, Config)).toBe(6)
		expect(Rebirth.multiplier(99, Config)).toBe(6)
		expect(Rebirth.multiplier(4, Config, "Stars")).toBe(2)
	end)
end)

T.describe("Rebirth.apply", function()
	test("every save field, kept or reset (the required table test)", function()
		local before = richSave()
		local data = deepCopy(before)
		local result = Rebirth.apply(data, Config, { "NightOwl", "BusyDoors", "BeltScout" }, CONTENT)

		-- Every v4 field is in exactly one of these lists (checked below), so a new field must be placed here.
		local KEPT = {
			"Version",
			"Stars",
			"Cured",
			"Book",
			"Story",
			"Daily",
			"Mailbox",
			"HeartsGiven",
			"ReferralRewarded",
			"VisitorDay",
			"HeartsReceived",
			"Tutorial",
			"WeekCures",
			"Playtime",
			"Boosts",
			"Badges",
			"Nurses",
			"NurseIndex",
			"JournalSets",
			"Simple",
		}
		local CHANGED = { "Cash", "Upgrades", "Rooms", "Decor", "Stats", "Level", "Rebirth" }
		local listed: { [string]: boolean } = {}
		for _, field in KEPT do
			listed[field] = true
			local ok, err = pcall(function()
				expect(data[field]).toEqual(before[field])
			end)
			if not ok then
				error("kept field " .. field .. ": " .. tostring(err))
			end
		end
		for _, field in CHANGED do
			listed[field] = true
		end
		for field in Schema.default() do
			if not listed[field] then
				error("Rebirth.spec doesn't say whether " .. field .. " is kept or reset")
			end
		end

		-- reset
		expect(data.Cash).toBe(Config.Rebirth.StartCash)
		expect(data.Upgrades).toEqual({
			Speed = 0,
			Tray = 0,
			Chairs = 0,
			Tips = 0,
			WardComfort = 0,
			AESpeed = 0,
			NightClinic = 0,
		})
		expect(data.Level).toBe(1)
		expect(data.Rooms).toEqual({ Stand = true })
		-- decor: everything still owned; only the Stand's placement stays
		expect(data.Decor.Owned).toEqual(before.Decor.Owned)
		expect(data.Decor.Placed).toEqual({ ["Stand:1"] = "PottedFern" })
		-- Stats: only RoomsBefore moves (+4 rooms reset)
		local stats = table.clone(before.Stats)
		stats.RoomsBefore = 6
		expect(data.Stats).toEqual(stats)
		-- Rebirth: count, points, the offer and the theme; Perks, Tree and Told kept
		expect(data.Rebirth).toEqual({
			Count = 1,
			Points = 4,
			Tree = { GentleWords = 2 },
			Perks = { "BigHands" },
			Offer = { "NightOwl", "BusyDoors", "BeltScout" },
			Theme = "Arctic",
			Pending = {},
			Told = true,
		})
		expect(result).toEqual({
			Count = 1,
			Theme = "Arctic",
			Unlocks = { "MythicSecret", "SunnyWing" },
			Pending = {},
			Trophies = {},
			RoomsReset = 4,
		})
	end)

	test("the start-of-branch perks: SeedMoney, WarmUp, ClinicStart, BathReady", function()
		local data = richSave()
		data.Rebirth.Perks = { "SeedMoney", "WarmUp", "ClinicStart", "BathReady" }
		local result = Rebirth.apply(data, Config, {}, CONTENT)
		expect(data.Cash).toBe(1000)
		expect(data.Upgrades.Speed).toBe(2)
		expect(data.Upgrades.Tips).toBe(1)
		expect(data.Upgrades.Tray).toBe(0)
		expect(data.Level).toBe(2)
		expect(data.Rooms).toEqual({ Stand = true, BathRoom = true })
		expect(data.Decor.Placed).toEqual({ ["Stand:1"] = "PottedFern", ["BathRoom:1"] = "CozyRug" })
		expect(result.RoomsReset).toBe(3) -- Ward, WinterWing, Garden
	end)

	test("R5 brings FounderFennec to Pending (unless owned); R6 a trophy; the newest theme", function()
		local data = richSave()
		data.Rebirth.Count = 4
		local result = Rebirth.apply(data, Config, {}, CONTENT)
		expect(result.Count).toBe(5)
		expect(data.Rebirth.Pending).toEqual({ "FounderFennec" })
		expect(result.Pending).toEqual({ "FounderFennec" })
		expect(data.Rebirth.Theme).toBe("Royal")
		expect(result.Unlocks).toEqual({ "FounderFennec", "Mascot" })
		-- R6: TrophyCup, and the theme stays the newest (Royal)
		result = Rebirth.apply(data, Config, {}, CONTENT)
		expect(result.Trophies).toEqual({ "TrophyCup" })
		expect(data.Decor.Owned.TrophyCup).toBe(true)
		expect(data.Rebirth.Theme).toBe("Royal")
		expect(data.Rebirth.Pending).toEqual({ "FounderFennec" }) -- still waiting, never twice
		-- an owner of FounderFennec never gets it pending
		local owner = richSave()
		owner.Rebirth.Count = 4
		owner.Nurses.FounderFennec = { Level = 1, XP = 0, Copies = 1, Job = "" }
		Rebirth.apply(owner, Config, {}, CONTENT)
		expect(owner.Rebirth.Pending).toEqual({})
	end)

	test("the offer is cleaned: unique, never a perk you own, at most 3", function()
		local data = richSave()
		Rebirth.apply(data, Config, { "BigHands", "NightOwl", "NightOwl", "BusyDoors", "BeltScout" }, CONTENT)
		expect(data.Rebirth.Offer).toEqual({ "NightOwl", "BusyDoors", "BeltScout" })
	end)
end)

T.describe("Rebirth offer and choose", function()
	test("offer: 3 distinct unowned cards, each even among those left; the Fallback when none are left", function()
		expect(Rebirth.offer({}, Perks, { 0, 0, 0 })).toEqual({ "BusyDoors", "BathReady", "FastLearners" })
		expect(Rebirth.offer({}, Perks, { 0.99, 0.99, 0.99 })).toEqual({ "SecondWind", "ClinicStart", "PatientPals" })
		local owned = table.clone(Perks.Order)
		table.remove(owned, 3) -- FastLearners left
		expect(Rebirth.offer(owned, Perks, { 0.5, 0.5, 0.5 })).toEqual({ "FastLearners" })
		expect(Rebirth.offer(Perks.Order, Perks, { 0.5, 0.5, 0.5 })).toEqual({ "TreePoints" })
		expect(#Rebirth.offer({}, Perks, { 0.1 })).toBe(1) -- no more cards than random numbers
		for _, id in Rebirth.offer({ "BusyDoors" }, Perks, { 0, 0.4, 0.8 }) do
			expect(id ~= "BusyDoors").toBe(true)
		end
	end)

	test("choose: only an offered, unowned card; it's added, the offer clears, a start card applies now", function()
		local data = richSave()
		data.Rebirth.Offer = { "SeedMoney", "NightOwl", "BathReady" }
		data.Cash = 0
		data.Rooms = { Stand = true }
		expect({ Rebirth.choose(data, "BusyDoors", Perks, Config) }).toEqual({ false, "Oops! Try again." })
		expect({ Rebirth.choose(data, "SeedMoney", Perks, Config) }).toEqual({ true, "" })
		expect(data.Rebirth.Perks).toEqual({ "BigHands", "SeedMoney" })
		expect(data.Rebirth.Offer).toEqual({})
		expect(data.Cash).toBe(1000)
		expect((Rebirth.choose(data, "NightOwl", Perks, Config))).toBe(false) -- the offer is gone
		data.Rebirth.Offer = { "BathReady" }
		expect((Rebirth.choose(data, "BathReady", Perks, Config))).toBe(true)
		expect(data.Rooms.BathRoom).toBe(true)
		data.Rebirth.Offer = { "ClinicStart" }
		data.Level = 1
		Rebirth.choose(data, "ClinicStart", Perks, Config)
		expect(data.Level).toBe(2)
		data.Rebirth.Offer = { "WarmUp" }
		data.Upgrades.Speed = 4
		Rebirth.choose(data, "WarmUp", Perks, Config)
		expect(data.Upgrades.Speed).toBe(4) -- never lowers
		expect(data.Upgrades.Tips).toBe(4)
		expect((Rebirth.choose(nil, "WarmUp", Perks, Config))).toBe(false)
	end)

	test("choose the Fallback: +2 points, nothing added to Perks", function()
		local data = richSave()
		data.Rebirth.Offer = { "TreePoints" }
		expect((Rebirth.choose(data, "TreePoints", Perks, Config))).toBe(true)
		expect(data.Rebirth.Points).toBe(3)
		expect(data.Rebirth.Perks).toEqual({ "BigHands" })
		expect(data.Rebirth.Offer).toEqual({})
	end)

	test("a waiting offer whose cards were all renamed or removed becomes the Fallback (never a dead end)", function()
		expect(Rebirth.liveOffer({ "GoneCard", "OldName" }, Perks)).toEqual({ "TreePoints" })
		expect(Rebirth.liveOffer({ "GoneCard", "SeedMoney" }, Perks)).toEqual({ "SeedMoney" })
		expect(Rebirth.liveOffer({ "Order", "Fallback" }, Perks)).toEqual({ "TreePoints" }) -- never a Data key
		expect(Rebirth.liveOffer({}, Perks)).toEqual({})
		expect(Rebirth.liveOffer(nil, Perks)).toEqual({})
		local data = richSave()
		data.Rebirth.Offer = { "GoneCard" }
		expect((Rebirth.choose(data, "GoneCard", Perks, Config))).toBe(false)
		expect((Rebirth.choose(data, "TreePoints", Perks, Config))).toBe(true)
		expect(data.Rebirth.Offer).toEqual({})
		expect(data.Rebirth.Points).toBe(3)
		-- with a known card still waiting, only the waiting cards can be chosen (not the Fallback)
		data.Rebirth.Offer = { "GoneCard", "NightOwl" }
		expect((Rebirth.choose(data, "TreePoints", Perks, Config))).toBe(false)
		expect((Rebirth.choose(data, "NightOwl", Perks, Config))).toBe(true)
	end)

	test("startCash: what ALL cash becomes on a rebirth (Seed Money's amount, else StartCash)", function()
		local data = richSave()
		data.Rebirth.Perks = {}
		expect(Rebirth.startCash(data, Config, Perks)).toBe(Config.Rebirth.StartCash)
		data.Rebirth.Perks = { "SeedMoney" }
		expect(Rebirth.startCash(data, Config, Perks)).toBe(rawget(Perks, "SeedMoney").Value)
		expect(Rebirth.startCash(nil, Config, Perks)).toBe(Config.Rebirth.StartCash)
	end)
end)

T.describe("Rebirth unlocks, themes and effects", function()
	test("unlocks per count, and has()", function()
		expect(Rebirth.unlocks(0)).toEqual({})
		expect(Rebirth.unlocks(1)).toEqual({ "MythicSecret", "SunnyWing" })
		expect(Rebirth.unlocks(2)).toEqual({ "Helicopter", "Pharmacy2" })
		expect(Rebirth.unlocks(3)).toEqual({ "Golden", "LevelCap15" })
		expect(Rebirth.unlocks(4)).toEqual({ "NightClinic" })
		expect(Rebirth.unlocks(5)).toEqual({ "FounderFennec", "Mascot" })
		expect(Rebirth.unlocks(8)).toEqual({ "Trophy8" })
		expect(Rebirth.unlocks(11)).toEqual({})
		expect(Rebirth.has(0, "SunnyWing")).toBe(false)
		expect(Rebirth.has(1, "SunnyWing")).toBe(true)
		expect(Rebirth.has(2, "Golden")).toBe(false)
		expect(Rebirth.has(9, "Golden")).toBe(true)
		expect(Rebirth.has(9, "Nope")).toBe(false)
		for id, info in Rebirth.UNLOCKS do
			expect(table.find(Rebirth.unlocks(info.Rebirths), id) ~= nil).toBe(true)
			local words = 0
			for _ in string.gmatch(info.Text, "%S+") do
				words += 1
			end
			expect(words <= 4).toBe(true)
		end
	end)

	test("the unlocks match the content they open", function()
		expect(Config.Belt.MinRebirths.Mythic).toBe(1) -- MythicSecret
		expect(Nurses.FounderFennec.Rebirths).toBe(5) -- FounderFennec
		expect(Decor.TrophyCup.Rebirths).toBe(6) -- Trophy6
		expect(Config.Nurses.LevelCapRebirths).toBe(3) -- LevelCap15
	end)

	test("themes: unlocked by count; the theme shown falls back to Candy", function()
		expect(Rebirth.themes(0, Themes)).toEqual({ "Candy" })
		expect(Rebirth.themes(2, Themes)).toEqual({ "Candy", "Arctic", "Jungle" })
		expect(#Rebirth.themes(99, Themes)).toBe(6)
		local data = richSave()
		data.Rebirth.Count = 2
		data.Rebirth.Theme = "Jungle"
		expect(Rebirth.theme(data, Themes)).toBe("Jungle")
		data.Rebirth.Theme = "Royal" -- locked at R2
		expect(Rebirth.theme(data, Themes)).toBe("Candy")
		data.Rebirth.Theme = ""
		expect(Rebirth.theme(data, Themes)).toBe("Candy")
		data.Rebirth.Theme = "Order"
		expect(Rebirth.theme(data, Themes)).toBe("Candy")
	end)

	test("effects: the tree and the perks merged (the tree part agrees with Logic/Tree)", function()
		local data = richSave()
		data.Rebirth.Tree = {
			GentleWords = 3,
			SteadyHands = 2,
			ExpressLift = 3,
			QuickFeet = 2,
			Bargain = 1,
			LuckyCoins = 1,
			DoubleShift = 1,
		}
		data.Rebirth.Perks = {
			"PatientPals",
			"FastLearners",
			"BigHands",
			"BusyDoors",
			"SirenPro",
			"SecondWind",
			"NightOwl",
			"BeltScout",
		}
		local fx = Rebirth.effects(data, Config, Perks, TreeData)
		expect(fx.Patience).toBe(50) -- 30 from the tree + 20 Patient Pals
		expect(fx.Ease).toBeCloseTo(1.2)
		expect(fx.Lift).toBeCloseTo(0.4)
		expect(fx.Walk).toBe(2)
		expect(fx.Bargain).toBeCloseTo(0.05)
		expect(fx.Cash).toBe(10)
		expect(fx.Stars).toBe(0)
		expect(fx.XP).toBe(2)
		expect(fx.Tray).toBe(1)
		expect(fx.Arrive).toBeCloseTo(0.85)
		expect(fx.SirenPro).toBe(1.25)
		expect(fx.Recharge).toBeCloseTo(0.8)
		expect(fx.NightOwl).toBe(true)
		expect(fx.BeltScout).toBe(true)
		expect(fx.DoubleShift).toBe(1.25)
		expect(fx.TwinCounters).toBe(false)
		expect(fx.LuckyStock).toBe(false)
		local tree = Tree.effects(data.Rebirth.Tree, TreeData.Nodes)
		expect(fx.Cash).toBe(tree.Cash)
		expect(fx.Walk).toBe(tree.Walk)
		local none = Rebirth.effects(Schema.default(), Config, Perks, TreeData)
		expect(none).toEqual({
			Patience = 0,
			Tips = 0,
			Ease = 1,
			MakeSpeed = 0,
			Walk = 0,
			Lift = 1,
			Cash = 0,
			Stars = 0,
			Bargain = 0,
			Arrive = 1,
			XP = 1,
			NightOwl = false,
			Tray = 0,
			BeltScout = false,
			SirenPro = 1,
			Recharge = 1,
			TwinCounters = false,
			DoubleShift = 1,
			LuckyStock = false,
		})
	end)

	test("the keep/reset screen's rows are short; GET matches Config", function()
		for _, list in { Rebirth.KEEP, Rebirth.RESET, Rebirth.GET } do
			for _, row in list do
				local words = 0
				for _ in string.gmatch(row.Text, "%S+") do
					words += 1
				end
				expect(words <= 3).toBe(true)
				expect(#row.Icon > 0).toBe(true)
			end
		end
		expect(Config.Rebirth.PointsPerRebirth).toBe(3) -- "+3 tree points"
		expect(Config.Rebirth.CashPerRebirth).toBe(0.25) -- "+25% cash"
		expect(Config.Rebirth.StarsPerRebirth).toBe(0.25)
		expect(Config.Rebirth.OfferSize).toBe(3)
	end)
end)
