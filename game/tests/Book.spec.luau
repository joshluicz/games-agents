--!strict
-- Patient Book rules (build plan §B6, Task 4). Pure: runs in Lune.

local T = require("./expect")
local expect, test = T.expect, T.test

local Book = require("../src/shared/Logic/Book")
local Patients = require("../src/shared/Data/Patients")
local Wings = require("../src/shared/Data/Wings")

local STARTER = { "DumplingFrog", "CloudSheep", "ToastPup", "JellyBun" }

local function cureAll(book: any, ids: { string })
	for _, id in ids do
		Book.stamp(book, id, nil)
	end
end

T.describe("Book.stamp", function()
	test("a first stamp is a new page and no new variant", function()
		local book = {}
		local newPage, newVariant = Book.stamp(book, "DumplingFrog", nil)
		expect(newPage).toBe(true)
		expect(newVariant).toBe(false)
		expect(book).toEqual({ DumplingFrog = { Cured = 1, Variants = {} } })
	end)

	test("a repeat with no variant is nothing new, but still counts", function()
		local book = {}
		Book.stamp(book, "DumplingFrog", nil)
		local newPage, newVariant = Book.stamp(book, "DumplingFrog", nil)
		expect(newPage).toBe(false)
		expect(newVariant).toBe(false)
		expect(book.DumplingFrog.Cured).toBe(2)
	end)

	test("a new variant on a seen page is a new variant only", function()
		local book = {}
		Book.stamp(book, "CloudSheep", nil)
		local newPage, newVariant = Book.stamp(book, "CloudSheep", "Sparkly")
		expect(newPage).toBe(false)
		expect(newVariant).toBe(true)
		expect(book.CloudSheep.Variants).toEqual({ Sparkly = true })
	end)

	test("the same variant again is nothing new", function()
		local book = {}
		Book.stamp(book, "CloudSheep", "Sparkly")
		local newPage, newVariant = Book.stamp(book, "CloudSheep", "Sparkly")
		expect(newPage).toBe(false)
		expect(newVariant).toBe(false)
		expect(book.CloudSheep.Cured).toBe(2)
	end)

	test("a first stamp with a variant is both new", function()
		local book = {}
		local newPage, newVariant = Book.stamp(book, "ToastPup", "Frosty")
		expect(newPage).toBe(true)
		expect(newVariant).toBe(true)
	end)

	test("a saved page with Cured 0 still counts as a new page", function()
		local book = { JellyBun = { Cured = 0, Variants = {} } }
		local newPage = Book.stamp(book, "JellyBun", nil)
		expect(newPage).toBe(true)
		expect(book.JellyBun.Cured).toBe(1)
	end)

	test("ignores junk ids and leaves the book unchanged", function()
		local book = {}
		local a, b = Book.stamp(book, (42 :: any) :: string, nil)
		expect(a).toBe(false)
		expect(b).toBe(false)
		local c, d = Book.stamp(book, "", nil)
		expect(c).toBe(false)
		expect(d).toBe(false)
		expect(book).toEqual({})
	end)

	test("a junk variant is treated as no variant", function()
		local book = {}
		local newPage, newVariant = Book.stamp(book, "MossMole", (7 :: any) :: string)
		expect(newPage).toBe(true)
		expect(newVariant).toBe(false)
		expect(book.MossMole.Variants).toEqual({})
	end)
end)

T.describe("Book.setComplete", function()
	test("is false while any page is missing", function()
		local book = {}
		cureAll(book, { "DumplingFrog", "CloudSheep", "ToastPup" })
		expect(Book.setComplete(book, STARTER)).toBe(false)
	end)

	test("is false when a page has Cured 0", function()
		local book = {}
		cureAll(book, { "DumplingFrog", "CloudSheep", "ToastPup" })
		book.JellyBun = { Cured = 0, Variants = {} }
		expect(Book.setComplete(book, STARTER)).toBe(false)
	end)

	test("is true when every id has Cured >= 1, whatever else is in the book", function()
		local book = {}
		cureAll(book, STARTER)
		Book.stamp(book, "SlimeCat", nil)
		expect(Book.setComplete(book, STARTER)).toBe(true)
	end)

	test("is false for an empty set", function()
		expect(Book.setComplete({}, {})).toBe(false)
	end)
end)

T.describe("Book.wingIds", function()
	test("lists a wing's patients in Data order", function()
		expect(Book.wingIds(Patients, "Starter")).toEqual(STARTER)
		expect(Book.wingIds(Patients, "Bath")).toEqual({ "SlimeCat", "MossMole" })
		expect(Book.wingIds(Patients, "Night")).toEqual({ "HiccupGhost", "MoonMoth" })
	end)

	test("is empty for an unknown wing", function()
		expect(Book.wingIds(Patients, "Lagoon")).toEqual({})
	end)

	test("works on a plain map without Order, sorted by id", function()
		local map = { B = { Wing = "X" }, A = { Wing = "X" }, C = { Wing = "Y" } }
		expect(Book.wingIds(map, "X")).toEqual({ "A", "B" })
	end)
end)

T.describe("Book.progress", function()
	test("counts the cured pages of a set", function()
		local book = {}
		cureAll(book, { "DumplingFrog", "ToastPup" })
		local done, total = Book.progress(book, STARTER)
		expect(done).toBe(2)
		expect(total).toBe(4)
	end)
end)

T.describe("Book.rewardsDue", function()
	test("is empty while no set is complete", function()
		local book = {}
		cureAll(book, { "DumplingFrog", "SlimeCat" })
		expect(Book.rewardsDue(book, {}, Patients, Wings)).toEqual({})
	end)

	test("gives the Starter set's HeartRug once the set completes", function()
		local book = {}
		cureAll(book, STARTER)
		expect(Book.rewardsDue(book, {}, Patients, Wings)).toEqual({ "HeartRug" })
	end)

	test("never gives a reward that is already owned", function()
		local book = {}
		cureAll(book, STARTER)
		expect(Book.rewardsDue(book, { HeartRug = true }, Patients, Wings)).toEqual({})
	end)

	test("gives every completed set's reward, in wing order", function()
		local book = {}
		cureAll(book, { "SlimeCat", "MossMole", "SnowconePenguin", "IcicleOwl" })
		cureAll(book, STARTER)
		expect(Book.rewardsDue(book, {}, Patients, Wings)).toEqual({
			"HeartRug",
			"RubberDuckFountain",
			"SnowGlobeLamp",
		})
	end)

	test("regulars do not count toward a wing set", function()
		local book = {}
		cureAll(book, { "DumplingFrog", "CloudSheep", "ToastPup", "ShySprout", "GrumpyTeapot" })
		expect(Book.rewardsDue(book, {}, Patients, Wings)).toEqual({})
	end)
end)
