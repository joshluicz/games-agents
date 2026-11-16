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

	test("keeps a valid v2 save unchanged", function()
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
		expect(Schema.reconcile(saved)).toEqual(saved)
		expect(Schema.reconcile(saved, 20500)).toEqual(saved) -- nothing is in the future
	end)

	test("gives an older v2 save the new fields at their defaults", function()
		local data = Schema.reconcile({ Version = 2, Cash = 5 })
		expect(data.VisitorDay).toBe(0)
		expect(data.HeartsReceived).toBe(0)
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
