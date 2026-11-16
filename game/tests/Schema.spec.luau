--!strict
-- Save schema v3 (build plan §B3, Task 0; depth-update build plan §B1).

local T = require("./expect")
local expect, test = T.expect, T.test

local Schema = require("../src/shared/Logic/Schema")

T.describe("Schema.default", function()
	test("is Version 3", function()
		expect(Schema.default().Version).toBe(3)
		expect(Schema.VERSION).toBe(3)
	end)

	test("starts at hospital level 1 with no nurses, an empty journal and Simple off", function()
		local data = Schema.default()
		expect(data.Level).toBe(1)
		expect(data.Nurses).toEqual({})
		expect(data.Equipped).toEqual({})
		expect(data.NurseIndex).toEqual({})
		expect(data.JournalSets).toEqual({})
		expect(data.Simple).toBe(false)
	end)

	test("owns the Stand", function()
		expect(Schema.default().Rooms.Stand).toBe(true)
	end)

	test("starts every upgrade at 0", function()
		expect(Schema.default().Upgrades).toEqual({ Speed = 0, Tray = 0, Chairs = 0, Tips = 0 })
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
		expect(data.Version).toBe(3)
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

	test("keeps a valid v3 save unchanged (every field from both updates)", function()
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
		saved.Nurses = { PuffPup = { Level = 2, Copies = 3 } }
		saved.Equipped = { "PuffPup" }
		saved.NurseIndex = { PuffPup = "Hired", MintMouse = "Seen" }
		saved.JournalSets = { Common = true }
		saved.Simple = true
		expect(Schema.reconcile(saved)).toEqual(saved)
		expect(Schema.reconcile(saved, 20500)).toEqual(saved) -- nothing is in the future
	end)

	test("a live v2 save (play time, boosts, stats, badges, weekly cures) migrates to v3 keeping all of it", function()
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
		expect(data.Version).toBe(3)
		for _, field in
			{
				"Cash",
				"Stars",
				"Cured",
				"Upgrades",
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
		-- and the depth update's fields arrive at their migration values
		expect(data.Level).toBe(2) -- the Ward implies Lv 2
		expect(data.Nurses).toEqual({})
		expect(data.Equipped).toEqual({})
		expect(data.NurseIndex).toEqual({})
		expect(data.JournalSets).toEqual({})
		expect(data.Simple).toBe(false)
		-- a second pass (the v3 save written back) changes nothing
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
		expect(data.Upgrades).toEqual({ Speed = 0, Tray = 0, Chairs = 0, Tips = 0 })
		expect(data.Rooms).toEqual({ Stand = true, Ward = true })
		expect(data.Book).toEqual({ CloudSheep = { Cured = 1, Variants = {} } })
		expect(data.Daily.Goals).toEqual({ { Id = "Cure5", Progress = 1, Day = 1 } })
	end)

	test("spots a save from a newer schema", function()
		expect(Schema.isNewer({ Version = Schema.VERSION + 1 })).toBe(true)
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

	test("a v2 save gets no nurses, an empty journal and Simple off", function()
		local data = Schema.reconcile({ Version = 2, Cash = 40, Cured = 9 })
		expect(data.Nurses).toEqual({})
		expect(data.Equipped).toEqual({})
		expect(data.NurseIndex).toEqual({})
		expect(data.JournalSets).toEqual({})
		expect(data.Simple).toBe(false)
	end)

	test("keeps a saved level, clamped to 1..5; junk falls back to the rooms", function()
		expect(Schema.reconcile({ Version = 3, Level = 4 }).Level).toBe(4)
		expect(Schema.reconcile({ Version = 3, Level = 99 }).Level).toBe(5)
		for _, bad in { 0, -2, 2.5, 0 / 0, math.huge, "3", true } :: { any } do
			expect(Schema.reconcile({ Version = 3, Level = bad, Rooms = { Ward = true } }).Level).toBe(2)
		end
	end)

	test("cleans nurse entries: copies at least 1, level 1..min(5, copies)", function()
		local data = Schema.reconcile({
			Version = 3,
			Nurses = {
				PuffPup = { Level = 2, Copies = 3 },
				MintMouse = { Level = 9, Copies = 7 },
				BeanBear = { Level = 4, Copies = 2 },
				DewDuck = { Copies = "x" },
				[5] = { Level = 1, Copies = 1 },
				HumHamster = "junk",
			},
		})
		expect(data.Nurses).toEqual({
			PuffPup = { Level = 2, Copies = 3 },
			MintMouse = { Level = 5, Copies = 7 },
			BeanBear = { Level = 2, Copies = 2 },
			DewDuck = { Level = 1, Copies = 1 },
		})
	end)

	test("equipped nurses are owned, unique and at most the level's slots", function()
		local data = Schema.reconcile({
			Version = 3,
			Level = 2,
			Nurses = { PuffPup = { Level = 1, Copies = 1 }, MintMouse = { Level = 1, Copies = 1 } },
			Equipped = { "PuffPup", "PuffPup", "NotMine", 7, "MintMouse" },
		})
		expect(data.Equipped).toEqual({ "PuffPup", "MintMouse" })
		local one = Schema.reconcile({
			Version = 3,
			Level = 1,
			Nurses = { PuffPup = { Level = 1, Copies = 1 }, MintMouse = { Level = 1, Copies = 1 } },
			Equipped = { "MintMouse", "PuffPup" },
		})
		expect(one.Equipped).toEqual({ "MintMouse" })
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
