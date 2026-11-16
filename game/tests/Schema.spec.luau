--!strict
-- Save schema v2 (build plan §B3, Task 0).

local T = require("./expect")
local expect, test = T.expect, T.test

local Schema = require("../src/shared/Logic/Schema")

T.describe("Schema.default", function()
	test("is Version 2", function()
		expect(Schema.default().Version).toBe(2)
	end)

	test("owns the Stand", function()
		expect(Schema.default().Rooms.Stand).toBe(true)
	end)

	test("starts every upgrade at 0", function()
		expect(Schema.default().Upgrades).toEqual({ Speed = 0, Tray = 0, Chairs = 0, Tips = 0 })
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
		expect(data.Version).toBe(2)
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
