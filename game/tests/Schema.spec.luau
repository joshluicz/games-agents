--!strict
-- Save schema v4 (build plan §B3, Task 0; depth-update build plan §B1; Progression v2 build plan §B1).

local T = require("./expect")
local expect, test = T.expect, T.test

local Schema = require("../src/shared/Logic/Schema")
local Nurses = require("../src/shared/Data/Nurses")
local Daily = require("../src/shared/Logic/Daily")
local DailyGoals = require("../src/shared/Data/DailyGoals")
local BadgesLogic = require("../src/shared/Logic/Badges")
local BadgeData = require("../src/shared/Data/Badges")
local Patients = require("../src/shared/Data/Patients")
local Rooms = require("../src/shared/Data/Rooms")
local Leaderboard = require("../src/shared/Logic/Leaderboard")

T.describe("Schema.default", function()
	test("is Version 4", function()
		expect(Schema.default().Version).toBe(4)
		expect(Schema.VERSION).toBe(4)
	end)

	test("starts at hospital level 1 with no nurses, an empty journal and Simple off", function()
		local data = Schema.default()
		expect(data.Level).toBe(1)
		expect(data.Nurses).toEqual({})
		expect((data :: any).Equipped).toBeNil()
		expect(data.NurseIndex).toEqual({})
		expect(data.JournalSets).toEqual({})
		expect(data.Simple).toBe(false)
	end)

	test("starts with no rebirths: the §B1 defaults", function()
		expect(Schema.default().Rebirth).toEqual({
			Count = 0,
			Points = 0,
			Tree = {},
			Perks = {},
			Offer = {},
			Theme = "",
			Pending = {},
			Told = false,
		})
	end)

	test("owns the Stand", function()
		expect(Schema.default().Rooms.Stand).toBe(true)
	end)

	test("starts every upgrade at 0 (Progression v2's three included)", function()
		expect(Schema.default().Upgrades).toEqual({
			Speed = 0,
			Tray = 0,
			Chairs = 0,
			Tips = 0,
			WardComfort = 0,
			AESpeed = 0,
			NightClinic = 0,
		})
	end)

	test("starts the tutorial at the welcome", function()
		expect(Schema.default().Tutorial).toBe(Schema.TUTORIAL_FIRST)
		expect(Schema.default().Tutorial).toBe(1)
	end)

	test("returns a fresh table each time", function()
		local a = Schema.default()
		a.Cash = 99
		a.Rooms.Garden = true
		local b = Schema.default()
		expect(b.Cash).toBe(0)
		expect(b.Rooms.Garden).toBeNil()
	end)
end)

T.describe("Schema.reconcile", function()
	test("migrates a v1 shop save", function()
		local data = Schema.reconcile({ Cash = 50, Served = 7, Upgrades = { Speed = 2, Tray = 1, Tips = 3 } })
		expect(data.Version).toBe(4)
		expect(data.Cash).toBe(50)
		expect(data.Cured).toBe(7)
		expect(data.Upgrades.Speed).toBe(2)
		expect(data.Upgrades.Tray).toBe(1)
		expect(data.Upgrades.Tips).toBe(3)
		expect(data.Upgrades.Chairs).toBe(0)
		expect(data.Rooms.Stand).toBe(true)
	end)

	test("returns defaults for junk", function()
		expect(Schema.reconcile("junk")).toEqual(Schema.default())
		expect(Schema.reconcile(nil)).toEqual(Schema.default())
		expect(Schema.reconcile(42)).toEqual(Schema.default())
	end)

	test("replaces a bad Cash with 0", function()
		expect(Schema.reconcile({ Cash = "x" }).Cash).toBe(0)
	end)

	test("replaces non-finite and negative numbers", function()
		local data = Schema.reconcile({ Cash = 0 / 0, Stars = math.huge, Cured = -5 })
		expect(data.Cash).toBe(0)
		expect(data.Stars).toBe(0)
		expect(data.Cured).toBe(0)
	end)

	test("keeps a valid v4 save unchanged (every field from every update)", function()
		local saved = Schema.default()
		saved.Cash = 321
		saved.Stars = 12
		saved.Cured = 40
		saved.Upgrades.Chairs = 2
		saved.Rooms.BathRoom = true
		saved.Decor.Owned.PottedFern = true
		saved.Decor.Placed["Stand:1"] = "PottedFern"
		saved.Book.DumplingFrog = { Cured = 3, Variants = { Sparkly = true } }
		saved.Story.ShySprout = { Beat = 2, LastBeatDay = 20500 }
		saved.Daily.Goals = { { Id = "Cure5", Progress = 2, Day = 20500 } }
		saved.Daily.LastGrantDay = 20500
		saved.Mailbox.LastSeenDay = 20499
		saved.HeartsGiven = { Day = 20500, Plots = { ["123"] = true } }
		saved.ReferralRewarded = true
		saved.VisitorDay = 20500
		saved.HeartsReceived = 7
		saved.WeekCures = { Week = 2968, Count = 11 }
		saved.Playtime = { Day = 20500, TodaySeconds = 610, TotalSeconds = 9000, Claimed = { 1, 2, 3 }, Rank = 2 }
		saved.Boosts = { StarRush = 420 }
		saved.Stats = { Seeded = 1, Cures = 40, ["Made:Remedy"] = 22 }
		saved.Badges = { Healer = 1 }
		saved.Level = 2
		saved.Upgrades.WardComfort = 1
		saved.Nurses = {
			PuffPup = { Level = 2, XP = 17, Copies = 3, Job = "" },
			MintMouse = { Level = 4, XP = 0, Copies = 1, Job = "Porter" },
		}
		saved.NurseIndex = { PuffPup = "Hired", MintMouse = "Hired", BeanBear = "Seen" }
		saved.JournalSets = { Common = true }
		saved.Simple = true
		saved.Stats.RoomsBefore = 4
		saved.Rebirth = {
			Count = 2,
			Points = 1,
			Tree = { GentleWords = 3, QuickFeet = 2 },
			Perks = { "BigHands", "SeedMoney" },
			Offer = { "NightOwl", "BusyDoors", "BeltScout" },
			Theme = "Jungle",
			Pending = {},
			Told = true,
		}
		expect(Schema.reconcile(saved)).toEqual(saved)
		expect(Schema.reconcile(saved, 20500)).toEqual(saved) -- nothing is in the future
	end)

	test("a live v2 save (play time, boosts, stats, badges, weekly cures) migrates to v4 keeping all of it", function()
		-- What a live server wrote before the depth update: Version 2, every field the playtime, badges and
		-- leaderboards updates added, and none of the depth update's.
		local v2 = {
			Version = 2,
			Cash = 1234,
			Stars = 50,
			Cured = 420,
			Upgrades = { Speed = 2, Tray = 1, Chairs = 3, Tips = 2 },
			Rooms = { Stand = true, BathRoom = true, Ward = true },
			Decor = { Owned = { InternRug = true, PottedFern = true }, Placed = { ["Stand:1"] = "InternRug" } },
			Book = { DumplingFrog = { Cured = 12, Variants = { Sparkly = true } } },
			Story = { ShySprout = { Beat = 3, LastBeatDay = 20499 } },
			Daily = { Goals = { { Id = "Cure5", Progress = 4, Day = 20500 } }, LastGrantDay = 20500 },
			Mailbox = { LastSeenDay = 20500 },
			HeartsGiven = { Day = 20500, Plots = { ["311718381"] = true } },
			ReferralRewarded = true,
			VisitorDay = 20498,
			HeartsReceived = 9,
			Tutorial = 9,
			WeekCures = { Week = 2968, Count = 37 },
			Playtime = { Day = 20500, TodaySeconds = 1500, TotalSeconds = 40000, Claimed = { 1, 2, 3, 4 }, Rank = 3 },
			Boosts = { StarRush = 300, LuckyTips = 90 },
			Stats = { Seeded = 1, Cures = 420, NightCures = 31, ["Made:Remedy"] = 150 },
			Badges = { Healer = 2, NightShift = 2, Potions = 2 },
		}
		local data = Schema.reconcile(v2, 20500)
		expect(data.Version).toBe(4)
		for _, field in
			{
				"Cash",
				"Stars",
				"Cured",
				"Rooms",
				"Decor",
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
				"Stats",
				"Badges",
			}
		do
			local ok, err = pcall(function()
				expect((data :: any)[field]).toEqual((v2 :: any)[field])
			end)
			if not ok then
				error(field .. ": " .. tostring(err))
			end
		end
		-- the four old upgrades are kept and the new three start at 0
		expect(data.Upgrades).toEqual({
			Speed = 2,
			Tray = 1,
			Chairs = 3,
			Tips = 2,
			WardComfort = 0,
			AESpeed = 0,
			NightClinic = 0,
		})
		-- and the depth update's and Progression v2's fields arrive at their migration values
		expect(data.Level).toBe(2) -- the Ward implies Lv 2
		expect(data.Nurses).toEqual({})
		expect((data :: any).Equipped).toBeNil()
		expect(data.NurseIndex).toEqual({})
		expect(data.JournalSets).toEqual({})
		expect(data.Simple).toBe(false)
		expect(data.Rebirth).toEqual(Schema.default().Rebirth)
		-- a second pass (the v4 save written back) changes nothing
		expect(Schema.reconcile(data, 20500)).toEqual(data)
		expect(Schema.isNewer(v2)).toBe(false)
	end)

	test("gives an older v2 save the new fields at their defaults", function()
		local data = Schema.reconcile({ Version = 2, Cash = 5 })
		expect(data.VisitorDay).toBe(0)
		expect(data.HeartsReceived).toBe(0)
		expect(data.WeekCures).toEqual({ Week = 0, Count = 0 })
	end)

	test("repairs a bad weekly count", function()
		local data = Schema.reconcile({ Version = 2, WeekCures = { Week = "x", Count = -3 } })
		expect(data.WeekCures).toEqual({ Week = 0, Count = 0 })
		expect(Schema.reconcile({ Version = 2, WeekCures = 5 }).WeekCures).toEqual({ Week = 0, Count = 0 })
	end)

	test("a fresh save starts play time at 0, no boosts, no badges, counters already seeded", function()
		local data = Schema.default()
		expect(data.Playtime).toEqual({ Day = 0, TodaySeconds = 0, TotalSeconds = 0, Claimed = {}, Rank = 0 })
		expect(data.Boosts).toEqual({})
		expect(data.Stats).toEqual({ Seeded = 1 })
		expect(data.Badges).toEqual({})
	end)

	test("an older save starts play time at 0 on today, with unseeded counters", function()
		local data = Schema.reconcile({ Version = 2, Cash = 5, Cured = 30 }, 20500)
		expect(data.Playtime).toEqual({ Day = 20500, TodaySeconds = 0, TotalSeconds = 0, Claimed = {}, Rank = 0 })
		expect(data.Boosts).toEqual({})
		expect(data.Stats).toEqual({}) -- Server/Badges seeds it once from Cured and the Book
		expect(data.Badges).toEqual({})
		expect(Schema.reconcile({ Version = 2 }).Playtime.Day).toBe(0) -- no today: day 0, rolled over on the first tick
	end)

	test("repairs play time: whole seconds, claimed gifts once each and sorted, total at least today", function()
		local data = Schema.reconcile({
			Playtime = {
				Day = 20500.7,
				TodaySeconds = 300.9,
				TotalSeconds = 100,
				Claimed = { 3, 1, 3, "2", 0, 99, 2.5, 2 },
				Rank = -4,
			},
		})
		expect(data.Playtime).toEqual({
			Day = 20500,
			TodaySeconds = 300,
			TotalSeconds = 300,
			Claimed = { 1, 2, 3 },
			Rank = 0,
		})
		expect(Schema.reconcile({ Playtime = "junk" }).Playtime.TotalSeconds).toBe(0)
		expect(Schema.reconcile({ Playtime = { TotalSeconds = 0 / 0 } }).Playtime.TotalSeconds).toBe(0)
	end)

	test("repairs boosts, stats and badges: string keys, finite numbers, nothing negative", function()
		local data = Schema.reconcile({
			Boosts = { StarRush = 300, QuickHands = 0, LuckyTips = -5, [5] = 100, Junk = "x", Long = 1e12 },
			Stats = { Cures = 12.9, Night = -3, [1] = 5, Bad = 0 / 0 },
			Badges = { Healer = 2, Potions = 0, Visitor = 1e9 },
		})
		expect(data.Boosts).toEqual({ StarRush = 300, Long = Schema.MAX_BOOST_SECONDS })
		expect(data.Stats).toEqual({ Cures = 12, Night = 0 })
		expect(data.Badges).toEqual({ Healer = 2, Visitor = Schema.MAX_TIER })
	end)

	test("pulls a future play day back to today", function()
		local saved = Schema.default()
		saved.Playtime = { Day = 103, TodaySeconds = 50, TotalSeconds = 50, Claimed = { 1 }, Rank = 0 }
		expect(Schema.reconcile(saved, 100).Playtime.Day).toBe(100)
		expect(Schema.reconcile(saved, 104).Playtime.Day).toBe(103)
	end)

	test("pulls saved days later than today back to today", function()
		local saved = Schema.default()
		saved.VisitorDay = 103
		saved.Mailbox.LastSeenDay = 103
		saved.Daily.LastGrantDay = 103
		saved.Daily.Goals = { { Id = "Cure5", Progress = 2, Day = 103 }, { Id = "Make8", Progress = 1, Day = 99 } }
		saved.Story.ShySprout = { Beat = 2, LastBeatDay = 104 }
		saved.HeartsGiven = { Day = 103, Plots = { ["123"] = true } }
		local data = Schema.reconcile(saved, 100)
		expect(data.VisitorDay).toBe(100)
		expect(data.Mailbox.LastSeenDay).toBe(100)
		expect(data.Daily.LastGrantDay).toBe(100)
		expect(data.Daily.Goals[1].Day).toBe(100)
		expect(data.Daily.Goals[2].Day).toBe(99) -- past days are kept
		expect(data.Story.ShySprout).toEqual({ Beat = 2, LastBeatDay = 100 })
		expect(data.HeartsGiven).toEqual({ Day = 100, Plots = { ["123"] = true } })
		expect(Schema.reconcile(saved).Mailbox.LastSeenDay).toBe(103) -- no today: no clamp
	end)

	test("drops unknown fields and bad entries", function()
		local data = Schema.reconcile({
			Hacked = true,
			Upgrades = { Speed = "fast", Rocket = 9 },
			Rooms = { Garden = "yes", Ward = true },
			Book = { DumplingFrog = "nope", CloudSheep = { Cured = 1, Variants = { Sparkly = 1 } } },
			Daily = { Goals = { { Id = "Cure5", Progress = 1, Day = 1 }, "junk", { Progress = 3 } } },
		})
		expect((data :: any).Hacked).toBeNil()
		expect(data.Upgrades).toEqual(Schema.default().Upgrades)
		expect(data.Rooms).toEqual({ Stand = true, Ward = true })
		expect(data.Book).toEqual({ CloudSheep = { Cured = 1, Variants = {} } })
		expect(data.Daily.Goals).toEqual({ { Id = "Cure5", Progress = 1, Day = 1 } })
	end)

	test("spots a save from a newer schema", function()
		expect(Schema.isNewer({ Version = Schema.VERSION + 1 })).toBe(true)
		expect(Schema.isNewer({ Version = 5 })).toBe(true)
		expect(Schema.isNewer({ Version = 4 })).toBe(false)
		expect(Schema.isNewer({ Version = 3 })).toBe(false)
		expect(Schema.isNewer({ Version = Schema.VERSION })).toBe(false)
		expect(Schema.isNewer({ Cash = 5 })).toBe(false)
		expect(Schema.isNewer("junk")).toBe(false)
	end)

	test("marks an existing player with a cure as done with the tutorial", function()
		expect(Schema.reconcile({ Version = 2, Cash = 5, Cured = 1 }).Tutorial).toBe(Schema.TUTORIAL_DONE)
		expect(Schema.reconcile({ Version = 2, Cured = 250 }).Tutorial).toBe(Schema.TUTORIAL_DONE)
	end)

	test("migrates a v1 shop save with serves as done with the tutorial", function()
		expect(Schema.reconcile({ Cash = 50, Served = 7 }).Tutorial).toBe(Schema.TUTORIAL_DONE)
	end)

	test("starts the tutorial for an old save without a cure", function()
		expect(Schema.reconcile({ Version = 2, Cash = 25, Cured = 0 }).Tutorial).toBe(Schema.TUTORIAL_FIRST)
		expect(Schema.reconcile({ Cash = 10, Served = 0 }).Tutorial).toBe(Schema.TUTORIAL_FIRST)
	end)

	test("keeps a saved tutorial step", function()
		expect(Schema.reconcile({ Version = 2, Cured = 1, Tutorial = 6 }).Tutorial).toBe(6)
		expect(Schema.reconcile({ Version = 2, Cured = 0, Tutorial = 3 }).Tutorial).toBe(3)
		expect(Schema.reconcile({ Version = 2, Cured = 0, Tutorial = 9 }).Tutorial).toBe(9)
	end)

	test("TutorialGift: false on a fresh save, a saved boolean is kept (look overhaul, still v4)", function()
		expect(Schema.default().TutorialGift).toBe(false)
		expect(Schema.VERSION).toBe(4)
		expect(Schema.reconcile({ Version = 4, Tutorial = 9, Cured = 5, TutorialGift = false }).TutorialGift).toBe(
			false
		)
		expect(Schema.reconcile({ Version = 4, Tutorial = 3, Cured = 0, TutorialGift = true }).TutorialGift).toBe(true)
	end)

	test("TutorialGift: missing or junk is derived from the step (at or past step 7 = it had its chance)", function()
		for _, junk in { "none", 1, 0, "true", {} } :: { any } do
			local past = if junk == "none" then nil else junk
			for step = 1, 9 do
				local data = Schema.reconcile({ Version = 4, Cured = 0, Tutorial = step, TutorialGift = past })
				expect(data.TutorialGift).toBe(step >= Schema.TUTORIAL_SHOP)
			end
		end
		-- an old save without a step: an existing player is done (so gifted); a new one starts ungifted
		expect(Schema.reconcile({ Version = 2, Cured = 4 }).TutorialGift).toBe(true)
		expect(Schema.reconcile({ Version = 2, Cured = 0 }).TutorialGift).toBe(false)
		expect(Schema.reconcile({ Cash = 50, Served = 7 }).TutorialGift).toBe(true)
	end)

	test("TutorialGift survives a round trip, and losing it loses nothing that matters", function()
		local once = Schema.reconcile({ Version = 4, Cured = 2, Tutorial = 8 })
		expect(once.TutorialGift).toBe(true)
		local again = Schema.reconcile(once)
		expect(again.TutorialGift).toBe(true)
		-- an older v4 server writes the save back without the field: the next load derives the same value
		local stripped = Schema.reconcile(once)
		stripped.TutorialGift = nil
		expect(Schema.reconcile(stripped).TutorialGift).toBe(true)
	end)

	test("replaces a bad tutorial step by the migration rule", function()
		for _, bad in { 0, 10, 2.5, -1, 0 / 0, math.huge, "3", true } :: { any } do
			expect(Schema.reconcile({ Version = 2, Cured = 0, Tutorial = bad }).Tutorial).toBe(1)
			expect(Schema.reconcile({ Version = 2, Cured = 4, Tutorial = bad }).Tutorial).toBe(9)
		end
	end)

	test("a v2 save starts at the level its rooms imply", function()
		expect(Schema.reconcile({ Version = 2, Cured = 3 }).Level).toBe(1)
		expect(Schema.reconcile({ Version = 2, Rooms = { Stand = true, BathRoom = true } }).Level).toBe(1)
		expect(Schema.reconcile({ Version = 2, Rooms = { BathRoom = true, Ward = true } }).Level).toBe(2)
		expect(Schema.reconcile({ Version = 2, Rooms = { WinterWing = true } }).Level).toBe(2)
		expect(Schema.reconcile({ Version = 2, Rooms = { Garden = true } }).Level).toBe(3)
		local everything = { Stand = true, BathRoom = true, Ward = true, WinterWing = true, Garden = true }
		expect(Schema.reconcile({ Version = 2, Rooms = everything }).Level).toBe(3)
	end)

	test("a v2 save gets no nurses, an empty journal, Simple off and the Rebirth defaults", function()
		local data = Schema.reconcile({ Version = 2, Cash = 40, Cured = 9 })
		expect(data.Nurses).toEqual({})
		expect((data :: any).Equipped).toBeNil()
		expect(data.NurseIndex).toEqual({})
		expect(data.JournalSets).toEqual({})
		expect(data.Simple).toBe(false)
		expect(data.Rebirth).toEqual(Schema.default().Rebirth)
	end)

	test("keeps a saved level, clamped to 1..5; junk falls back to the rooms", function()
		expect(Schema.reconcile({ Version = 3, Level = 4 }).Level).toBe(4)
		expect(Schema.reconcile({ Version = 3, Level = 99 }).Level).toBe(5)
		for _, bad in { 0, -2, 2.5, 0 / 0, math.huge, "3", true } :: { any } do
			expect(Schema.reconcile({ Version = 3, Level = bad, Rooms = { Ward = true } }).Level).toBe(2)
		end
	end)

	test('a v3 save\'s nurses keep their level (clamped 1..10), get XP 0 and Job ""; junk is repaired', function()
		local data = Schema.reconcile({
			Version = 3,
			Nurses = {
				PuffPup = { Level = 2, Copies = 3 },
				MintMouse = { Level = 12, Copies = 7 },
				BeanBear = { Level = 2.5, Copies = 2 },
				DewDuck = { Copies = "x" },
				[5] = { Level = 1, Copies = 1 },
				HumHamster = "junk",
			},
			Equipped = { "PuffPup", "MintMouse", "BeanBear" },
		})
		expect(data.Nurses).toEqual({
			PuffPup = { Level = 2, XP = 0, Copies = 3, Job = "" },
			MintMouse = { Level = 10, XP = 0, Copies = 7, Job = "" },
			BeanBear = { Level = 1, XP = 0, Copies = 2, Job = "" },
			DewDuck = { Level = 1, XP = 0, Copies = 1, Job = "Rest" }, -- the 4th: over the roster of 3
		})
		expect((data :: any).Equipped).toBeNil()
	end)

	test("v3 -> v4: 16 nurses with 5 equipped -> the first 3 equipped work, the rest rest, nothing deleted", function()
		local ids = {
			"PuffPup",
			"MintMouse",
			"BeanBear",
			"DewDuck",
			"HumHamster",
			"CuddleCub",
			"PebblePenguin",
			"BerryBat",
			"SunnySnail",
			"CloudKoala",
			"JamJelly",
			"ToffeeFox",
			"AuroraOtter",
			"StarlightLamb",
			"MoonpuffDrake",
			"GoldieGryphlet",
		}
		local nurses = {}
		for index, id in ids do
			nurses[id] = { Level = (index % 5) + 1, Copies = (index % 5) + 1 }
		end
		local v3 = {
			Version = 3,
			Level = 5,
			Cured = 900,
			Nurses = nurses,
			Equipped = { "ToffeeFox", "MintMouse", "GoldieGryphlet", "PuffPup", "JamJelly" },
			NurseIndex = { PuffPup = "Hired" },
		}
		local data = Schema.reconcile(v3, 20500)
		local working, resting = {}, 0
		local count = 0
		for id, entry in data.Nurses do
			count += 1
			expect(entry.XP).toBe(0)
			expect(entry.Copies).toBe(nurses[id].Copies)
			expect(entry.Level).toBe(nurses[id].Level)
			if entry.Job == "Rest" then
				resting += 1
			else
				expect(entry.Job).toBe("")
				table.insert(working, id)
			end
		end
		table.sort(working)
		expect(count).toBe(16)
		expect(resting).toBe(13)
		expect(working).toEqual({ "GoldieGryphlet", "MintMouse", "ToffeeFox" }) -- Equipped's first three
		for _, id in ids do
			expect(data.NurseIndex[id]).toBe("Hired")
		end
		-- written back as v4 and loaded again: the same three work (a v4 save fills by NurseId, and the resting
		-- ones stay resting)
		expect(Schema.reconcile(data, 20500)).toEqual(data)
	end)

	test(
		"a full v3 save (16 nurses, play time, boosts, stats, badges, journal) loads as v4 keeping everything",
		function()
			-- What an Update 1 test server wrote: Version 3 with every live field plus the depth update's.
			local ids = {}
			for _, id in Nurses.Order do
				if Nurses[id].Source == nil then
					table.insert(ids, id)
				end
			end
			expect(#ids).toBe(16)
			local nurses = {}
			for index, id in ids do
				nurses[id] = { Level = (index % 5) + 1, Copies = (index % 3) + 1 }
			end
			local v3 = {
				Version = 3,
				Cash = 98765,
				Stars = 410,
				Cured = 2600,
				Upgrades = { Speed = 4, Tray = 2, Chairs = 3, Tips = 4 },
				Rooms = { Stand = true, BathRoom = true, Ward = true, Garden = true },
				Decor = { Owned = { InternRug = true, HeartRug = true }, Placed = { ["Stand:1"] = "InternRug" } },
				Book = { DumplingFrog = { Cured = 40, Variants = { Sparkly = true } } },
				Story = { ShySprout = { Beat = 5, LastBeatDay = 20499 } },
				Daily = { Goals = { { Id = "Cure5", Progress = 4, Day = 20500 } }, LastGrantDay = 20500 },
				Mailbox = { LastSeenDay = 20500 },
				HeartsGiven = { Day = 20500, Plots = { ["311718381"] = true } },
				ReferralRewarded = true,
				VisitorDay = 20498,
				HeartsReceived = 14,
				Tutorial = 9,
				WeekCures = { Week = 2968, Count = 120 },
				Playtime = {
					Day = 20500,
					TodaySeconds = 2400,
					TotalSeconds = 90000,
					Claimed = { 1, 2, 3, 4, 5 },
					Rank = 4,
				},
				Boosts = { StarRush = 300, QuickHands = 120 },
				Stats = { Seeded = 1, Cures = 2600, NightCures = 200, ["Made:Remedy"] = 700 },
				Badges = { Healer = 3, NightShift = 3, Potions = 3, Builder = 2 },
				Level = 4,
				Nurses = nurses,
				Equipped = { ids[9], ids[2], ids[16], ids[1], ids[5] },
				NurseIndex = { [ids[1]] = "Hired", [ids[3]] = "Seen" },
				JournalSets = { Common = true },
				Simple = true,
			}
			local data = Schema.reconcile(v3, 20500)
			expect(data.Version).toBe(4)
			for _, field in
				{
					"Cash",
					"Stars",
					"Cured",
					"Rooms",
					"Decor",
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
					"Stats",
					"Badges",
					"Level",
					"JournalSets",
					"Simple",
				}
			do
				local ok, err = pcall(function()
					expect((data :: any)[field]).toEqual((v3 :: any)[field])
				end)
				if not ok then
					error(field .. ": " .. tostring(err))
				end
			end
			expect(data.Upgrades).toEqual({
				Speed = 4,
				Tray = 2,
				Chairs = 3,
				Tips = 4,
				WardComfort = 0,
				AESpeed = 0,
				NightClinic = 0,
			})
			-- every nurse kept with its level and copies, XP 0; Equipped's first three work, the other 13 rest
			local working: { string } = {}
			for _, id in ids do
				local entry = data.Nurses[id]
				expect(entry.Level).toBe(nurses[id].Level)
				expect(entry.Copies).toBe(nurses[id].Copies)
				expect(entry.XP).toBe(0)
				if entry.Job ~= "Rest" then
					expect(entry.Job).toBe("")
					table.insert(working, id)
				end
				expect(data.NurseIndex[id]).toBe("Hired") -- every owned nurse is Hired in the journal
			end
			table.sort(working)
			local expected = { ids[9], ids[2], ids[16] }
			table.sort(expected)
			expect(working).toEqual(expected)
			expect((data :: any).Equipped).toBeNil()
			expect(data.Rebirth).toEqual(Schema.default().Rebirth)
			expect(Schema.reconcile(data, 20500)).toEqual(data) -- the v4 save written back loads the same
			expect(Schema.isNewer(v3)).toBe(false)
			expect(Schema.isNewer(data)).toBe(false)
		end
	)

	test("the Real Clinic: a live v3 save keeps every count, page, room and badge; only a Potion goal goes", function()
		-- An Update 1 (live) save from before the Real Clinic, still Version 3 (design §11, §15 #4)
		local v3 = {
			Version = 3,
			Cash = 4321,
			Stars = 88,
			Cured = 640,
			Upgrades = { Speed = 3, Tray = 1, Chairs = 2, Tips = 3 },
			Rooms = { Stand = true, BathRoom = true, WinterWing = true },
			Decor = { Owned = { HeartRug = true }, Placed = { ["BathRoom:1"] = "HeartRug" } },
			Book = {
				DumplingFrog = { Cured = 12, Variants = { Sparkly = true } },
				SlimeCat = { Cured = 3, Variants = {} },
			},
			Story = { GrumpyTeapot = { Beat = 2, LastBeatDay = 20499 } },
			Daily = {
				Goals = {
					{ Id = "Cure5", Progress = 4, Day = 20498 },
					{ Id = "MakePotion5", Progress = 2, Day = 20499 }, -- a goal naming the gone Potion
					{ Id = "Bath4", Progress = 1, Day = 20500 },
				},
				LastGrantDay = 20500,
			},
			Mailbox = { LastSeenDay = 20500 },
			VisitorDay = 20500,
			Tutorial = 9,
			WeekCures = { Week = 2968, Count = 40 },
			Stats = {
				Seeded = 1,
				Cures = 640,
				NightCures = 30,
				["Cures:Starter"] = 500,
				["Cures:Bath"] = 60,
				["Made:Remedy"] = 410,
				["Made:Plaster"] = 230,
				["Made:Bath"] = 60,
			},
			Badges = { Healer = 3, Potions = 3, Plasters = 3, Bubbles = 2, Meadow = 3 },
			Level = 3,
		}
		local data = Schema.reconcile(v3, 20500)
		expect(data.Version).toBe(Schema.VERSION)
		expect(Schema.VERSION).toBe(4) -- no bump: no saved field changed shape
		for _, field in { "Cash", "Stars", "Cured", "Rooms", "Decor", "Book", "Story", "VisitorDay", "Stats", "Badges" } do
			local ok, err = pcall(function()
				expect((data :: any)[field]).toEqual((v3 :: any)[field])
			end)
			if not ok then
				error(field .. ": " .. tostring(err))
			end
		end
		expect(data.Level).toBe(3)
		expect(data.WeekCures).toEqual(v3.WeekCures)
		-- the server prunes banked goals whose Id left the pool (Server/Daily on load): only the Potion one goes, and
		-- the others keep their progress
		local daily = Daily.prune(data.Daily, DailyGoals)
		expect(daily.Goals).toEqual({
			{ Id = "Cure5", Progress = 4, Day = 20498 },
			{ Id = "Bath4", Progress = 1, Day = 20500 },
		})
		expect(daily.LastGrantDay).toBe(20500)
		-- every id the save names still means the same thing
		expect(rawget(Patients :: any, "DumplingFrog") ~= nil and rawget(Patients :: any, "SlimeCat") ~= nil).toBe(true)
		expect(rawget(Rooms :: any, "BathRoom") ~= nil and rawget(Rooms :: any, "WinterWing") ~= nil).toBe(true)
		local defs = BadgeData.List :: { BadgesLogic.Def }
		local byId = {}
		for _, def in defs do
			byId[def.Id] = def
		end
		for badgeId in v3.Badges do
			expect(byId[badgeId] ~= nil).toBe(true)
		end
		expect(byId.Potions.Stat).toBe("Made:Remedy") -- the 💊 Pharmacist counts on from 410
		-- no tier is lost, none is paid twice: nothing is due for the badges this save already holds
		for _, up in BadgesLogic.ups(data.Badges, data, defs) do
			expect(v3.Badges[up.Id] == nil or up.From >= v3.Badges[up.Id]).toBe(true)
			expect(up.To > up.From).toBe(true)
		end
		expect(BadgesLogic.statValue(data, "Made:Remedy")).toBe(410)
		-- the boards read the same numbers (their ids and store names are unchanged)
		expect(Leaderboard.valueOf("Cured", data, 2968)).toBe(640)
		expect(Leaderboard.valueOf("Week", data, 2968)).toBe(40)
		expect(Schema.reconcile(data, 20500)).toEqual(data) -- written back as v4, it loads the same
	end)

	test("a v3 save with fewer equipped than the roster fills the rest by NurseId", function()
		local data = Schema.reconcile({
			Version = 3,
			Nurses = {
				PuffPup = { Level = 1, Copies = 1 },
				MintMouse = { Level = 1, Copies = 1 },
				BeanBear = { Level = 1, Copies = 1 },
				DewDuck = { Level = 1, Copies = 1 },
			},
			Equipped = { "PuffPup", "NotMine", "PuffPup", 7 },
		})
		expect(data.Nurses.PuffPup.Job).toBe("")
		expect(data.Nurses.BeanBear.Job).toBe("") -- then by NurseId: BeanBear, DewDuck
		expect(data.Nurses.DewDuck.Job).toBe("")
		expect(data.Nurses.MintMouse.Job).toBe("Rest")
	end)

	test("a v4 save over the roster rests the extra ones by NurseId (Equipped is ignored in v4)", function()
		local data = Schema.reconcile({
			Version = 4,
			Nurses = {
				PuffPup = { Level = 3, XP = 5, Copies = 3, Job = "Maker" },
				MintMouse = { Level = 1, XP = 0, Copies = 1, Job = "" },
				BeanBear = { Level = 1, XP = 0, Copies = 1, Job = "Healer" },
				DewDuck = { Level = 1, XP = 0, Copies = 1, Job = "Rest" },
				HumHamster = { Level = 1, XP = 0, Copies = 1, Job = "Cheerer" },
			},
			Equipped = { "HumHamster" },
		})
		expect(data.Nurses.BeanBear.Job).toBe("Healer")
		expect(data.Nurses.HumHamster.Job).toBe("Cheerer")
		expect(data.Nurses.MintMouse.Job).toBe("")
		expect(data.Nurses.PuffPup.Job).toBe("Rest") -- the 4th working one by NurseId
		expect(data.Nurses.DewDuck.Job).toBe("Rest")
		expect(data.Nurses.PuffPup.XP).toBe(5) -- resting keeps everything else
	end)

	test("the roster grows with rebirths (3 + 1 a rebirth, at most 8)", function()
		local nurses = {}
		for index = 1, 10 do
			nurses["N" .. string.char(64 + index)] = { Level = 1, Copies = 1, Job = "" }
		end
		local function workingAt(count: number): number
			local data = Schema.reconcile({ Version = 4, Nurses = nurses, Rebirth = { Count = count } })
			local n = 0
			for _, entry in data.Nurses do
				if entry.Job ~= "Rest" then
					n += 1
				end
			end
			return n
		end
		expect(workingAt(0)).toBe(3)
		expect(workingAt(1)).toBe(4)
		expect(workingAt(5)).toBe(8)
		expect(workingAt(9)).toBe(8)
	end)

	test("nurse XP is whole and below the next level; 0 at the cap; the cap is 15 from R3", function()
		local data = Schema.reconcile({
			Version = 4,
			Nurses = {
				PuffPup = { Level = 2, XP = 39, Copies = 1, Job = "" }, -- xpToNext(2) = 40
				MintMouse = { Level = 2, XP = 40, Copies = 1, Job = "" },
				BeanBear = { Level = 10, XP = 99, Copies = 1, Job = "" }, -- at the cap
			},
		})
		expect(data.Nurses.PuffPup.XP).toBe(39)
		expect(data.Nurses.MintMouse.XP).toBe(39)
		expect(data.Nurses.BeanBear.XP).toBe(0)
		for _, bad in { -3, 2.5, 0 / 0, math.huge, "5", true } :: { any } do
			local junk = Schema.reconcile({ Version = 4, Nurses = { PuffPup = { Level = 3, XP = bad, Copies = 1 } } })
			expect(junk.Nurses.PuffPup.XP).toBe(0)
		end
		local r3 = Schema.reconcile({
			Version = 4,
			Rebirth = { Count = 3 },
			Nurses = { PuffPup = { Level = 14, XP = 3, Copies = 9, Job = "" }, MintMouse = { Level = 99, Copies = 1 } },
		})
		expect(r3.Nurses.PuffPup).toEqual({ Level = 14, XP = 3, Copies = 9, Job = "" })
		expect(r3.Nurses.MintMouse.Level).toBe(15)
		local r2 = Schema.reconcile({ Version = 4, Rebirth = { Count = 2 }, Nurses = { PuffPup = { Level = 14 } } })
		expect(r2.Nurses.PuffPup.Level).toBe(10)
	end)

	test('a Job is "", Rest, or 1-20 letters; junk becomes ""', function()
		local data = Schema.reconcile({
			Version = 4,
			Nurses = {
				PuffPup = { Level = 1, Copies = 1, Job = "Receptionist" },
				MintMouse = { Level = 1, Copies = 1, Job = "Port er" },
				BeanBear = { Level = 1, Copies = 1, Job = 7 },
				DewDuck = { Level = 1, Copies = 1, Job = string.rep("a", 21) },
				HumHamster = { Level = 1, Copies = 1, Job = "SomeFutureJob" },
			},
			Rebirth = { Count = 2 },
		})
		expect(data.Nurses.PuffPup.Job).toBe("Receptionist")
		expect(data.Nurses.MintMouse.Job).toBe("")
		expect(data.Nurses.BeanBear.Job).toBe("")
		expect(data.Nurses.DewDuck.Job).toBe("")
		expect(data.Nurses.HumHamster.Job).toBe("SomeFutureJob") -- an unknown job is kept (servers use the role)
	end)

	test("Rebirth: numbers whole and clamped, lists unique and capped, Offer never repeats a Perk", function()
		local data = Schema.reconcile({
			Version = 4,
			Rebirth = {
				Count = 3.7,
				Points = -4,
				Tree = { GentleWords = 3, QuickFeet = 0, Old = 99, [4] = 1, Bad = "x" },
				Perks = { "BigHands", "BigHands", 5, "SeedMoney" },
				Offer = { "BigHands", "NightOwl", "NightOwl", "BusyDoors", "BeltScout" },
				Theme = 42,
				Pending = { "FounderFennec", "FounderFennec", "A", "B", "C", "D" },
				Told = "yes",
			},
		})
		expect(data.Rebirth).toEqual({
			Count = 3,
			Points = 0,
			Tree = { GentleWords = 3, Old = Schema.MAX_NODE_RANK },
			Perks = { "BigHands", "SeedMoney" },
			Offer = { "NightOwl", "BusyDoors", "BeltScout" },
			Theme = "",
			Pending = { "FounderFennec", "A", "B", "C" },
			Told = false,
		})
		local huge = Schema.reconcile({ Rebirth = { Count = 1e9, Points = 1e9, Told = true, Theme = "Arctic" } })
		expect(huge.Rebirth.Count).toBe(Schema.MAX_REBIRTHS)
		expect(huge.Rebirth.Points).toBe(Schema.MAX_POINTS)
		expect(huge.Rebirth.Told).toBe(true)
		expect(huge.Rebirth.Theme).toBe("Arctic")
		for _, junk in { "junk", 5, true } :: { any } do
			expect(Schema.reconcile({ Rebirth = junk }).Rebirth).toEqual(Schema.default().Rebirth)
		end
	end)

	test("Stats.RoomsBefore follows the counter rules", function()
		expect(Schema.reconcile({ Stats = { RoomsBefore = 6.9 } }).Stats.RoomsBefore).toBe(6)
		expect(Schema.reconcile({ Stats = { RoomsBefore = -2 } }).Stats.RoomsBefore).toBe(0)
	end)

	test("xpToNext, rosterCap and levelCap", function()
		local curve = {}
		for level = 1, 9 do
			curve[level] = Schema.xpToNext(level)
		end
		expect(curve).toEqual({ 20, 40, 70, 110, 160, 220, 290, 370, 460 })
		local toTen = 0
		for level = 1, 9 do
			toTen += Schema.xpToNext(level)
		end
		expect(toTen).toBe(1740)
		local toFifteen = toTen
		for level = 10, 14 do
			toFifteen += Schema.xpToNext(level)
		end
		expect(toFifteen).toBe(5740)
		expect(Schema.rosterCap(0)).toBe(3)
		expect(Schema.rosterCap(4)).toBe(7)
		expect(Schema.rosterCap(5)).toBe(8)
		expect(Schema.rosterCap(500)).toBe(8)
		expect(Schema.rosterCap(-1)).toBe(3)
		expect(Schema.levelCap(0)).toBe(10)
		expect(Schema.levelCap(2)).toBe(10)
		expect(Schema.levelCap(3)).toBe(15)
		expect(Schema.MAX_NURSE_LEVEL).toBe(15)
	end)

	test("the journal keeps Seen and Hired only, and every owned nurse is Hired", function()
		local data = Schema.reconcile({
			Version = 3,
			Nurses = { PuffPup = { Level = 1, Copies = 1 } },
			NurseIndex = { PuffPup = "Seen", MintMouse = "Seen", BeanBear = "Hired", DewDuck = "Maybe", [3] = "Seen" },
			JournalSets = { Common = true, Rare = "yes" },
			Simple = true,
		})
		expect(data.NurseIndex).toEqual({ PuffPup = "Hired", MintMouse = "Seen", BeanBear = "Hired" })
		expect(data.JournalSets).toEqual({ Common = true })
		expect(data.Simple).toBe(true)
	end)

	test("levelFromRooms matches the room table", function()
		expect(Schema.levelFromRooms(nil)).toBe(1)
		expect(Schema.levelFromRooms({ Stand = true })).toBe(1)
		expect(Schema.levelFromRooms({ Ward = true })).toBe(2)
		expect(Schema.levelFromRooms({ Garden = true, BathRoom = true })).toBe(3)
	end)

	test("always owns the Stand", function()
		expect(Schema.reconcile({ Rooms = { Stand = false } }).Rooms.Stand).toBe(true)
	end)

	test("never shares tables with the saved value", function()
		local saved = { Rooms = { Stand = true, Ward = true }, Upgrades = { Speed = 1 } }
		local data = Schema.reconcile(saved)
		data.Rooms.Garden = true
		expect((saved.Rooms :: any).Garden).toBeNil()
	end)
end)
