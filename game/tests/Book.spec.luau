--!strict
-- Patient Book rules (build plan §B6, Task 4). Pure: runs in Lune.

local T = require("./expect")
local expect, test = T.expect, T.test

local Book = require("../src/shared/Logic/Book")
local Patients = require("../src/shared/Data/Patients")
local Wings = require("../src/shared/Data/Wings")
local Variants = require("../src/shared/Data/Variants")
local Regulars = require("../src/shared/Data/Regulars")
local Icons = require("../src/client/UI/Icons")
local UiRules = require("./uirules")
local fs = require("@lune/fs")
local luau = require("@lune/luau")

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

------------------------------------------------------------------------------------------------------------------
-- The Book panel's GATE block (UI/BookPanel, loaded on its own) and the calm UI (UI direction §4 #10; Joshua,
-- memory-20261117-007; R0 is memory-20261117-006): words for the gates, one sticker, one heart, the tabs that have
-- something in them.
------------------------------------------------------------------------------------------------------------------
local Gate = (function()
	local root = if fs.isDir("src/client") then "." else "game"
	local text = fs.readFile(root .. "/src/client/UI/BookPanel.luau")
	local first = string.find(text, "-- BEGIN GATE", 1, true)
	local last = string.find(text, "-- END GATE", 1, true)
	assert(first and last, "no GATE block in BookPanel")
	return luau.load(string.sub(text, first, last - 1) .. "\nreturn Gate", { debugName = "BookPanel.Gate" })()
end)()

T.describe("BookPanel (GATE): the calm Book", function()
	test("a rebirth wing's gate in words: no lock icon, no 🏢, no hurry", function()
		expect(Gate.wingWords(Wings.Starter, 0)).toBe("")
		expect(Gate.wingWords(Wings.Sunny, 0)).toBe("From branch 1")
		expect(Gate.wingWords(Wings.Sunny, 1)).toBe("")
		expect(Gate.wingWords(Wings.Sky, 1)).toBe("From branch 2 · by air")
		expect(Gate.wingWords(Wings.Sky, 2)).toBe("By air only")
		expect(Gate.wingWords(Wings.Sky, "x")).toBe("From branch 2 · by air")
		expect(Gate.wingWords(nil, 3)).toBe("")
		for _, id in Wings.Order do
			for _, count in { 0, 1, 2, 5 } do
				expect(Icons.count(Gate.wingWords(rawget(Wings, id), count))).toBe(0)
			end
		end
	end)
	test("one sticker per card (never two emoji side by side): Golden first, then +n for the rest", function()
		expect({ Gate.sticker(nil, Variants) }).toEqual({ "", false })
		expect({ Gate.sticker({}, Variants) }).toEqual({ "", false })
		expect({ Gate.sticker({ Sparkly = true }, Variants) }).toEqual({ rawget(Variants, "Sparkly").Icon, false })
		local text, golden = Gate.sticker({ Sparkly = true, Golden = true, Frosty = true }, Variants)
		expect(text).toBe(rawget(Variants, "Golden").Icon .. " +2")
		expect(golden).toBe(true)
		expect(Icons.count(text)).toBe(1)
	end)
	test("a regular's story is one heart and a count; the meta is plain text", function()
		expect(Gate.story(3, 5)).toBe("💛 3/5")
		expect(Gate.story(9, 5)).toBe("💛 5/5")
		expect(Gate.story(nil, 5)).toBe("💛 0/5")
		expect(Icons.count(Gate.story(2, 5))).toBe(1)
		expect(Gate.meta(0)).toBe("0%")
		expect(Gate.meta(6.4)).toBe("6%")
		expect(Gate.meta(0 / 0)).toBe("0%")
		expect(Icons.count(Gate.meta(50))).toBe(0)
	end)
	test("R0: a fresh save sees the first wing only; met pages and visits bring their tabs, and keep them", function()
		local fresh = Gate.visible({}, {}, Wings, Patients, Regulars)
		local shown = {}
		for id, on in fresh do
			if on then
				table.insert(shown, id)
			end
		end
		expect(shown).toEqual({ Wings.Order[1] })
		local book = {}
		Book.stamp(book, "SlimeCat", nil)
		local after = Gate.visible(book, {}, Wings, Patients, Regulars)
		expect(after.Starter).toBe(true)
		expect(after.Bath).toBe(true)
		expect(after.Winter).toBe(false)
		expect(after.Friends).toBe(false)
		local regular = Regulars.Order[1]
		expect(Gate.visible(book, { [regular] = { Beat = 1 } }, Wings, Patients, Regulars).Friends).toBe(true)
		expect(Gate.visible(book, { [regular] = { Beat = 0 } }, Wings, Patients, Regulars).Friends).toBe(false)
		-- a page saved with Cured 0 isn't met yet
		expect(Gate.visible({ IcicleOwl = { Cured = 0 } }, {}, Wings, Patients, Regulars).Winter).toBe(false)
		-- junk in, the first wing still out
		expect(Gate.visible(nil, nil, Wings, nil, nil)[Wings.Order[1]]).toBe(true)
	end)
	test("the calm rules: BookPanel is at 0 on every one (the ratchet, locked here)", function()
		local over = UiRules.ratchet({ "src/client/UI/BookPanel.luau" }, {})
		assert(#over == 0, "\n" .. table.concat(over, "\n"))
		expect(UiRules.check({ "src/client/UI/BookPanel.luau" })).toEqual({})
	end)
end)
