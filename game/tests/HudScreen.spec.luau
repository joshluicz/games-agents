--!nocheck
-- The HUD's screen rules (look build plan §B7, T5): the PURE-BEGIN..PURE-END block of UI/Hud, loaded on its own (the
-- rest of Hud needs Roblox) against the real Logic/Tutorial, Logic/NextEvent, Logic/HudZones and UI/Icons, plus the
-- UI rules (tests/uirules) on Hud and Toasts and a few source checks (no perpetual effects, every pointer target
-- assigned). UI direction change 4b and §6: the reveal (one door at a time, each when it first has content; "a fresh
-- save is simple"; a rich save loses nothing), Settings as toggles and Quiet links, the level row, the calm ratchet.
-- Run from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local TutorialLogic = require("../src/shared/Logic/Tutorial")
local NextEvent = require("../src/shared/Logic/NextEvent")
local HudZones = require("../src/shared/Logic/HudZones")
local DailyGoals = require("../src/shared/Data/DailyGoals")
local Wings = require("../src/shared/Data/Wings")
local Schema = require("../src/shared/Logic/Schema")
local Belt = require("../src/shared/Logic/Belt")
local Config = require("./config")
local Icons = require("../src/client/UI/Icons")
local UiRules = require("./uirules")

local function source(path: string): string
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("can't find " .. path .. " (run from game/)")
end

local function pureBlock(path: string, env: { [string]: any }): any
	local text = source(path)
	local first = string.find(text, "-- PURE-BEGIN", 1, true)
	local last = string.find(text, "-- PURE-END", 1, true)
	assert(first and last and last > first, "no PURE block in " .. path)
	local block = string.sub(text, first, last - 1) .. "\nreturn Pure\n"
	return luau.load(block, { debugName = path .. " (pure)", environment = env })()
end

local Pure = pureBlock("src/client/UI/Hud.luau", {
	TutorialLogic = TutorialLogic,
	NextEvent = NextEvent,
	HudZones = HudZones,
	Icons = Icons,
})

-- A save as the Snapshot carries it (the same field names), past the tutorial. `change` edits it.
local function snapshot(change: ((any) -> ())?): any
	local data = Schema.default()
	data.Tutorial = TutorialLogic.DONE
	data.MailboxReady = false
	if change then
		change(data)
	end
	return data
end

-- What a session knows, worked out the way Hud.init does (the cheapest nurse on the belt at this level).
local function session(data: any, extra: { [string]: any }?): any
	local price = Belt.price(Config, Belt.RARITIES[1], data.Level or 1)
	local out = {
		CanHire = price > 0 and (data.Cash or 0) >= price,
		GoldenLevel = Belt.minLevel(Config, "Secret"),
	}
	for key, value in extra or {} do
		out[key] = value
	end
	return out
end

local function shownList(reveal: any): { string }
	local out = {}
	for _, name in Pure.REVEAL_ORDER do
		if reveal[name] then
			table.insert(out, name)
		end
	end
	return out
end

-- Every screen the plan names, from the narrowest phone to a big desktop (640 x 360 to 1920 x 1080 and past).
local SCREENS = {
	{ 640, 360 },
	{ 667, 375 },
	{ 800, 360 },
	{ 844, 390 },
	{ 932, 430 },
	{ 1024, 600 },
	{ 1024, 768 },
	{ 1280, 720 },
	{ 1366, 768 },
	{ 1600, 900 },
	{ 1920, 1080 },
	{ 2560, 1440 },
}

local function overlaps(a, b): boolean
	return a.X0 < b.X1 and b.X0 < a.X1 and a.Y0 < b.Y1 and b.Y0 < a.Y1
end

local function statusRect(box)
	local rows = box.Rows
	return {
		X0 = box.X1 - box.Width,
		X1 = box.X1,
		Y0 = box.Top,
		Y1 = box.Top + rows * Pure.ROW + (rows - 1) * Pure.ROW_GAP,
	}
end

T.describe("Hud (pure): the Now slot", function()
	test("the highest priority shows: warnings 30 > the tutorial 20 > Hud's hint 15 > the tracked goal 10", function()
		expect(Pure.PRIORITY).toEqual({ Warning = 30, Tutorial = 20, Hint = 15, Goal = 10 })
		expect(Pure.nowPick({
			{ Source = "Goal", Priority = Pure.PRIORITY.Goal, Seq = 9 },
			{ Source = "Hint", Priority = Pure.PRIORITY.Hint, Seq = 1 },
		})).toBe("Hint")
		local offers = {
			{ Source = "Goal", Priority = Pure.PRIORITY.Goal, Seq = 3 },
			{ Source = "Tutorial", Priority = Pure.PRIORITY.Tutorial, Seq = 1 },
			{ Source = "Warning", Priority = Pure.PRIORITY.Warning, Seq = 2 },
		}
		expect(Pure.nowPick(offers)).toBe("Warning")
		table.remove(offers, 3)
		expect(Pure.nowPick(offers)).toBe("Tutorial")
		table.remove(offers, 2)
		expect(Pure.nowPick(offers)).toBe("Goal")
	end)

	test("empty is nil; a tie goes to the newest offer; junk entries are skipped", function()
		expect(Pure.nowPick({})).toBeNil()
		expect(Pure.nowPick({
			{ Source = "A", Priority = 20, Seq = 1 },
			{ Source = "B", Priority = 20, Seq = 5 },
			{ Source = "C", Priority = 20, Seq = 2 },
		})).toBe("B")
		expect(Pure.nowPick({
			{ Source = "A", Priority = 0 / 0, Seq = 9 },
			"junk",
			{ Priority = 99 },
			{ Source = "B", Priority = 10 },
		})).toBe("B")
	end)

	test("toasts stack 8 px under the Now card, or under the top bar when there's none", function()
		expect(Pure.noticeTop(170, 58)).toBe(178)
		expect(Pure.noticeTop(0, 58)).toBe(66)
		expect(Pure.noticeTop(0, 0)).toBe(8)
		expect(Pure.noticeTop(nil, nil)).toBe(HudZones.TOPBAR + 8)
		for _, size in SCREENS do
			local layout = HudZones.layout(size[1], size[2])
			local width = Pure.noticeWidth(layout, size[1])
			expect(width >= layout.NowWidth).toBe(true)
			expect(width <= 480).toBe(true)
			expect(width <= size[1] - 2 * layout.Margin).toBe(true)
		end
	end)
end)

T.describe("Hud (pure): Status words", function()
	test("day or night with words; m:ss", function()
		expect(Pure.dayLine(false, 207, 2)).toBe("☀️ Night in 3:27")
		expect(Pure.dayLine(true, 128, 2)).toBe("🌙 ×2 · 2:08 left")
		expect(Pure.dayLine(true, 128, 1)).toBe("🌙 2:08 left")
		expect(Pure.dayLine(false, 207, 2, true)).toBe("☀️ 3:27") -- ONE icon a line: the sun and the day's time left
		expect(Pure.dayLine(true, 128, 2, true)).toBe("🌙 ×2 · 2:08")
		expect(Pure.dayLine(false, -5, 2)).toBe("☀️ Night in 0:00")
		expect(Pure.dayLine(false, nil, 2)).toBe("") -- not known yet: the row hides
		expect(Pure.clock(3600)).toBe("60:00")
	end)

	test("the event candidates: Golden Hour only, never paid, hidden while it runs", function()
		local list = Pure.eventCandidates(1000, false)
		expect(#list).toBe(1)
		expect(list[1].Id).toBe("GoldenHour")
		expect(list[1].Paid).toBe(false)
		expect(list[1].At).toBe(1000)
		expect(Pure.eventCandidates(1000, true)).toEqual({})
		expect(Pure.eventCandidates(nil, false)).toEqual({})
		expect(Pure.eventCandidates(0 / 0, false)).toEqual({})
		expect(Pure.eventCandidates("soon", false)).toEqual({})
		for _, candidate in Pure.eventCandidates(1000, false) do
			expect(candidate.Paid ~= true).toBe(true)
		end
	end)

	test("the chip: minutes only, the soonest free event within 6 h", function()
		local now = 5000
		expect(Pure.eventChip(now, Pure.eventCandidates(now + 12 * 60, false))).toBe("🌟 Golden Hour in 12m")
		expect(Pure.eventChip(now, Pure.eventCandidates(now + 12 * 60, false), true)).toBe("🌟 in 12m")
		expect(Pure.eventChip(now, Pure.eventCandidates(now + 65 * 60, false))).toBe("🌟 Golden Hour in 1h 5m")
		expect(Pure.eventChip(now, Pure.eventCandidates(now + 30, false))).toBe("🌟 Golden Hour in 1m")
		expect(Pure.eventChip(now, Pure.eventCandidates(now + 7 * 3600, false))).toBeNil() -- past 6 h
		expect(Pure.eventChip(now, Pure.eventCandidates(now - 60, false))).toBeNil() -- already begun
		expect(Pure.eventChip(now, Pure.eventCandidates(now + 600, true))).toBeNil() -- running: hidden
		-- never seconds
		local chip = Pure.eventChip(now, Pure.eventCandidates(now + 12 * 60 + 37, false))
		expect(string.find(chip, ":", 1, true)).toBeNil()
	end)

	test("a paid event is never picked, even when it's the soonest (red line 3)", function()
		local now = 100
		local candidates = {
			{ Id = "Sale", Icon = "💎", Name = "Robux Sale", At = now + 60, Paid = true },
			{ Id = "GoldenHour", Icon = "🌟", Name = "Golden Hour", At = now + 600, Paid = false },
		}
		expect(Pure.eventChip(now, candidates)).toBe("🌟 Golden Hour in 10m")
		expect(Pure.eventChip(now, { candidates[1] })).toBeNil()
	end)

	test(
		"one Status icon a line, each from UI/Icons.Status; the visitor line has none (its face is beside it)",
		function()
			for _, text in
				{
					Pure.dayLine(false, 207, 2),
					Pure.dayLine(false, 207, 2, true),
					Pure.dayLine(true, 128, 2),
					Pure.dayLine(true, 128, 2, true),
					Pure.eventChip(0, Pure.eventCandidates(600, false)),
					Pure.eventChip(0, Pure.eventCandidates(600, false), true),
				}
			do
				expect(Icons.count(text)).toBe(1)
			end
			expect(Icons.clusters(Pure.dayLine(false, 1, 2))[1]).toBe(Icons.Status.Day)
			expect(Icons.clusters(Pure.dayLine(true, 1, 2))[1]).toBe(Icons.Status.Night)
			expect(Pure.GOLDEN.Icon).toBe(Icons.Status.Golden)
			expect(Icons.count(Pure.visitorLine("Coming"))).toBe(0)
			expect(Icons.count(Pure.visitorLine("Done"))).toBe(0)
		end
	)

	test("the visitor, in words", function()
		expect(Pure.visitorLine("Coming")).toBe("Visitor today")
		expect(Pure.visitorLine("Done")).toBe("Visitor treated")
		expect(Pure.visitorLine("None")).toBeNil()
		expect(Pure.visitorLine(nil)).toBeNil()
	end)

	test("at most 3 boost chips, in order", function()
		local live = { { Id = "A" }, { Id = "B" }, { Id = "C" }, { Id = "D" } }
		expect(Pure.MAX_BOOSTS).toBe(3)
		expect(#Pure.boosts(live)).toBe(3)
		expect(Pure.boosts(live)[1].Id).toBe("A")
		expect(Pure.boosts(nil)).toEqual({})
	end)

	test("every Status word fits the floor: one row at 18 px is at most 6 words", function()
		for _, text in
			{
				Pure.dayLine(false, 207, 2),
				Pure.dayLine(true, 128, 2),
				Pure.eventChip(0, Pure.eventCandidates(65 * 60, false)),
				Pure.visitorLine("Coming"),
			}
		do
			local words = 0
			for _ in string.gmatch(text, "%S+") do
				words += 1
			end
			expect(words <= 6).toBe(true)
		end
	end)
end)

T.describe("Hud (pure): the tracked goal", function()
	test("the first goal under its target, as 'Treat 5 · 3/5' (the kind keeps its saved id, Cure)", function()
		local goals = { { Id = "Cure5", Progress = 3, Day = 1 }, { Id = "Make10", Progress = 0, Day = 1 } }
		local goal = Pure.trackedGoal(goals, DailyGoals, Wings)
		expect(goal.Id).toBe("Cure5")
		expect(goal.Text).toBe("Treat 5 · 3/5")
		expect(goal.Icon).toBe("🎯")
		expect(goal.Ratio).toBeCloseTo(0.6)
	end)

	test("the goal card reads 'Treat 3 · 0/3' (Real Clinic §12: treat, never cure)", function()
		local defs = { { Id = "Treat3", Kind = "Cure", Target = 3, Icon = "😊", Reward = { Cash = 1, Stars = 0 } } }
		local goal = Pure.trackedGoal({ { Id = "Treat3", Progress = 0, Day = 1 } }, defs, Wings)
		expect(goal.Text).toBe("Treat 3 · 0/3")
		expect(Pure.goalName({ Kind = "CureWing", Target = 6, Wing = "Starter" }, Wings)).toBe(
			"Treat 6 " .. Wings.Starter.Icon
		)
		for _, def in DailyGoals do
			local text = Pure.trackedGoal({ { Id = def.Id, Progress = 0, Day = 1 } }, DailyGoals, Wings).Text
			expect(string.find(string.lower(text), "%f[%a]cure")).toBeNil()
		end
	end)

	test("a finished goal (waiting for its claim) is skipped; all done is nil", function()
		local goals = { { Id = "Cure5", Progress = 5, Day = 1 }, { Id = "Make10", Progress = 4, Day = 1 } }
		expect(Pure.trackedGoal(goals, DailyGoals, Wings).Text).toBe("Make 10 · 4/10")
		expect(Pure.trackedGoal({ { Id = "Cure5", Progress = 9, Day = 1 } }, DailyGoals, Wings)).toBeNil()
		expect(Pure.trackedGoal({}, DailyGoals, Wings)).toBeNil()
		expect(Pure.trackedGoal(nil, DailyGoals, Wings)).toBeNil()
		expect(Pure.trackedGoal({ { Id = "Nope", Progress = 0 } }, DailyGoals, Wings)).toBeNil()
	end)

	test("every daily goal kind has short words (≤ 6 words with its count)", function()
		for _, def in DailyGoals do
			local goal = Pure.trackedGoal({ { Id = def.Id, Progress = 0, Day = 1 } }, DailyGoals, Wings)
			expect(goal ~= nil).toBe(true)
			local words = 0
			for _ in string.gmatch(goal.Icon .. " " .. goal.Text, "%S+") do
				words += 1
			end
			expect(words <= 6).toBe(true)
		end
		local night = Pure.trackedGoal({ { Id = "Night3", Progress = 1, Day = 1 } }, DailyGoals, Wings)
		expect(night.Text).toBe("Treat 3 🌙 · 1/3")
	end)
end)

T.describe("Hud (pure): the reveal during the tutorial", function()
	local function at(step, cured, replay)
		local data = snapshot(function(d)
			d.Tutorial = step
			d.TutorialReplay = replay == true
		end)
		return Pure.reveal(data, session(data, { Cured = cured == true }))
	end

	test("💰 only until the step is known; ⭐ after the first treatment; 🛒 at SHOP; 📖 at BOOK", function()
		expect(shownList(at(0))).toEqual({})
		expect(shownList(at(TutorialLogic.WELCOME))).toEqual({})
		expect(at(TutorialLogic.REST).Stars).toBe(false)
		expect(at(TutorialLogic.REST, true).Stars).toBe(true)
		expect(at(TutorialLogic.MORE).Stars).toBe(true)
		expect(at(TutorialLogic.MORE).Shop).toBe(false)
		expect(at(TutorialLogic.SHOP).Shop).toBe(true)
		expect(at(TutorialLogic.SHOP).Book).toBe(false)
		expect(shownList(at(TutorialLogic.BOOK))).toEqual({ "Stars", "Shop", "Book" })
	end)

	test("nothing else shows while the tutorial runs, whatever the save or the session holds", function()
		for step = TutorialLogic.WELCOME, TutorialLogic.BOOK do
			local data = snapshot(function(d)
				d.Tutorial = step
				d.Cash = 99999
				d.MailboxReady = true
				d.Badges = { Healer = 2 }
				d.Nurses = { DewDuck = { Level = 1, XP = 0, Copies = 1, Job = "" } }
			end)
			local seen = session(data, { Night = true, GiftReady = true, GoalReady = true })
			local kept = { Nurses = true, Mailbox = true, Goals = true }
			for _, name in shownList(Pure.reveal(data, seen, kept)) do
				expect(table.find({ "Stars", "Shop", "Book" }, name) ~= nil).toBe(true)
			end
		end
	end)

	test("a replay keeps every door the save has content for, at every step (and the Book at its step)", function()
		for step = TutorialLogic.WELCOME, TutorialLogic.DONE do
			local data = snapshot(function(d)
				d.Tutorial = step
				d.TutorialReplay = true
				d.Level = 3
				d.Book = { DumplingFrog = { Cured = 4, Variants = {} } }
			end)
			local reveal = Pure.reveal(data, session(data))
			for _, name in { "Stars", "Level", "Shop", "Nurses", "Book", "Gifts", "Goals", "Mailbox", "Clock", "Event" } do
				expect(reveal[name]).toBe(true)
			end
		end
		local fresh = snapshot(function(d)
			d.Tutorial = TutorialLogic.BOOK
			d.TutorialReplay = true
		end)
		expect(Pure.reveal(fresh, session(fresh)).Book).toBe(true) -- the tutorial's pointer needs its target
	end)
end)

T.describe("Hud (pure): the reveal after the tutorial (UI direction R0, change 4b)", function()
	test("the order: every rail piece once and every Status line once; the triggers are data", function()
		local seen = {}
		for _, name in Pure.REVEAL_ORDER do
			expect(seen[name]).toBeNil()
			seen[name] = true
			local facts = Pure.TRIGGERS[name]
			expect(type(facts) == "table" and #facts >= 1).toBe(true)
		end
		for _, list in HudZones.ORDER do
			for _, piece in list do
				expect(seen[piece]).toBe(true)
			end
		end
		for _, line in Pure.STATUS_ORDER do
			expect(seen[line]).toBe(true)
		end
		expect(seen.Stars and seen.Level).toBe(true)
		-- every fact a trigger names is one Pure.facts works out
		local facts = Pure.facts(snapshot(), {})
		for _, list in Pure.TRIGGERS do
			for _, fact in list do
				expect(type(facts[fact])).toBe("boolean")
			end
		end
		expect(Pure.STAGGER).toBe(0.15)
		expect(Pure.REVEAL_HOLD >= 2 and Pure.REVEAL_HOLD <= 6).toBe(true)
	end)

	test(
		"A FRESH SAVE IS SIMPLE: Lv 1, tutorial just done, no nurses, no mail: at most 3 doors and 1 Status line",
		function()
			local data = snapshot(function(d)
				d.Cured = 3
				d.Stars = 3
				d.Cash = 40 -- under the cheapest nurse
				d.Book = { DumplingFrog = { Cured = 3, Variants = {} } }
			end)
			expect(data.Cash < Belt.price(Config, "Common", 1)).toBe(true)
			local reveal = Pure.reveal(data, session(data))
			expect(shownList(reveal)).toEqual({ "Stars", "Level", "Shop", "Book" })
			local doors, lines = Pure.revealCount(reveal)
			expect(doors <= 3).toBe(true)
			expect(lines <= 1).toBe(true)
			-- with today's letter waiting it is still within the budget
			data.MailboxReady = true
			local withMail = Pure.reveal(data, session(data))
			expect(shownList(withMail)).toEqual({ "Stars", "Level", "Shop", "Book", "Mailbox" })
			doors, lines = Pure.revealCount(withMail)
			expect(doors).toBe(3)
			expect(lines).toBe(0)
			-- a brand-new default save that skipped the tutorial: the wallet and the Shop
			local skipped = snapshot()
			expect(shownList(Pure.reveal(skipped, session(skipped)))).toEqual({ "Stars", "Level", "Shop" })
		end
	)

	test("each door arrives on its own trigger (memory-20261117-007 #3)", function()
		local base = function(d)
			d.Book = { DumplingFrog = { Cured = 1, Variants = {} } }
		end
		local function door(name, change, extra)
			local data = snapshot(function(d)
				base(d)
				if change then
					change(d)
				end
			end)
			return Pure.reveal(data, session(data, extra))[name]
		end
		local common = Belt.price(Config, "Common", 1)
		-- Nurses: when the first nurse can be hired (the cheapest on the belt at your level), or you own one
		expect(door("Nurses")).toBe(false)
		expect(door("Nurses", function(d)
			d.Cash = common - 1
		end)).toBe(false)
		expect(door("Nurses", function(d)
			d.Cash = common
		end)).toBe(true)
		expect(door("Nurses", function(d)
			d.Nurses = { DewDuck = { Level = 1, XP = 0, Copies = 1, Job = "" } }
		end)).toBe(true)
		expect(door("Nurses", function(d)
			d.NurseIndex = { DewDuck = 1 }
		end)).toBe(true)
		-- Mail: with the first letter
		expect(door("Mailbox")).toBe(false)
		expect(door("Mailbox", function(d)
			d.MailboxReady = true
		end)).toBe(true)
		expect(door("Mailbox", function(d)
			d.Story = { Pip = { Beat = 1, LastBeatDay = 3 } }
		end)).toBe(true)
		-- Golden Hour: at hospital Lv 3 (Config.Belt.MinLevel.Secret; 3 when the session doesn't say)
		expect(Belt.minLevel(Config, "Secret")).toBe(Pure.GOLDEN_LEVEL)
		for level = 1, 5 do
			expect(door("Event", function(d)
				d.Level = level
			end)).toBe(level >= 3)
		end
		expect(Pure.reveal(
			snapshot(function(d)
				d.Level = 3
			end),
			{}
		).Event).toBe(true)
		-- Gifts: the first play gift ready, or one opened
		expect(door("Gifts")).toBe(false)
		expect(door("Gifts", nil, { GiftReady = true })).toBe(true)
		expect(door("Gifts", function(d)
			d.Playtime.Claimed = { 1 }
		end)).toBe(true)
		expect(door("Gifts", function(d)
			d.Playtime.Rank = 1
		end)).toBe(true)
		-- Goals and the day/night line: the first night (seen now, or a night patient treated before); a goal done
		expect(door("Goals")).toBe(false)
		expect(door("Clock")).toBe(false)
		expect(door("Goals", nil, { Night = true })).toBe(true)
		expect(door("Clock", nil, { Night = true })).toBe(true)
		expect(door("Clock", function(d)
			d.Stats.NightCures = 2
		end)).toBe(true)
		expect(door("Goals", nil, { GoalReady = true })).toBe(true)
		expect(door("Clock", nil, { GoalReady = true })).toBe(false)
		-- Badges and Top: the first badge
		expect(door("Badges")).toBe(false)
		expect(door("Badges", function(d)
			d.Badges = { Healer = 0 }
		end)).toBe(false)
		expect(door("Badges", function(d)
			d.Badges = { Healer = 1 }
		end)).toBe(true)
		expect(door("Boards", function(d)
			d.Badges = { Healer = 1 }
		end)).toBe(true)
		-- the Book: its first page
		expect(Pure.reveal(snapshot(), {}).Book).toBe(false)
		expect(door("Book")).toBe(true)
		-- boost chips: a timed boost running
		expect(door("Boosts")).toBe(false)
		expect(door("Boosts", function(d)
			d.Boosts = { Timed = { { Id = "QuickHands", Left = 60 } }, Permanent = {} }
		end)).toBe(true)
	end)

	test("players who already have a door keep it: read from the save, with no new save field", function()
		-- a rich save (Lv 5, nurses, a branch) shows everything, with nothing from this session
		local rich = snapshot(function(d)
			d.Level = 5
			d.Rebirth.Count = 1
			d.Nurses = { DewDuck = { Level = 4, XP = 0, Copies = 2, Job = "" } }
			d.Book = { DumplingFrog = { Cured = 40, Variants = {} } }
			d.Boosts = { Timed = { { Id = "QuickHands", Left = 60 } }, Permanent = {} }
		end)
		expect(shownList(Pure.reveal(rich, {}))).toEqual(Pure.REVEAL_ORDER)
		-- an older Lv 2 save with no cash, no nurse, nothing opened today: every door it had (all but the Lv 3 chip)
		local old = snapshot(function(d)
			d.Level = 2
		end)
		local reveal = Pure.reveal(old, {})
		for _, name in Pure.REVEAL_ORDER do
			expect(reveal[name]).toBe(name ~= "Event" and name ~= "Boosts")
		end
		-- every field the facts read is one the save already has (Schema.default), so nothing new is saved
		local default = Schema.default()
		for _, field in
			{ "Tutorial", "Level", "Rebirth", "Playtime", "Stats", "Badges", "Book", "Nurses", "NurseIndex", "Story" }
		do
			expect(default[field] ~= nil).toBe(true)
		end
	end)

	test(
		"a door shown this session stays (the cash was spent, the letter was opened), but not into a new tutorial",
		function()
			local data = snapshot(function(d)
				d.Cash = 0
			end)
			expect(Pure.reveal(data, session(data)).Nurses).toBe(false)
			expect(Pure.reveal(data, session(data), { Nurses = true, Mailbox = true }).Nurses).toBe(true)
			expect(Pure.reveal(data, session(data), { Nurses = true, Mailbox = true }).Mailbox).toBe(true)
			data.Tutorial = TutorialLogic.WELCOME
			expect(Pure.reveal(data, session(data), { Nurses = true }).Nurses).toBe(false)
		end
	)

	test("junk never errors: a missing snapshot shows nothing but what 'no tutorial' means", function()
		expect(shownList(Pure.reveal(nil, nil))).toEqual({ "Stars", "Level", "Shop" })
		expect(shownList(Pure.reveal({ Tutorial = "x", Badges = 3, Playtime = "?" }, 7))).toEqual({
			"Stars",
			"Level",
			"Shop",
		})
	end)

	test("a new door's line: six words or fewer, no emoji, an icon for its tile; quiet pieces have none", function()
		for name, line in Pure.DOOR_LINE do
			expect(table.find(Pure.REVEAL_ORDER, name) ~= nil).toBe(true)
			local words = 0
			for _ in string.gmatch(line, "%S+") do
				words += 1
			end
			expect(words <= 6).toBe(true)
			expect(Icons.count(line)).toBe(0)
			local text, icon = Pure.doorLine(name)
			expect(text).toBe(line)
			expect(Icons.count(icon)).toBe(1)
		end
		expect(Pure.doorLine("Mailbox")).toBe("New: you have mail")
		expect(select(2, Pure.doorLine("Nurses"))).toBe(Icons.Door.Nurses)
		expect(select(2, Pure.doorLine("Level"))).toBe(Icons.Unit.Level)
		expect(Pure.doorLine("Stars")).toBeNil()
		expect(Pure.doorLine("Shop")).toBeNil() -- the tutorial introduces it
	end)
end)

T.describe("Hud (pure): the Now card's hints", function()
	test("the first level-up: at Lv 1, once it can be afforded, past the tutorial, until it's used", function()
		expect(Pure.levelHint(TutorialLogic.DONE, 1, true, false)).toBe(true)
		expect(Pure.levelHint(TutorialLogic.DONE, 1, false, false)).toBe(false)
		expect(Pure.levelHint(TutorialLogic.DONE, 1, true, true)).toBe(false)
		expect(Pure.levelHint(TutorialLogic.DONE, 2, true, false)).toBe(false) -- later levels: the bar's own words
		expect(Pure.levelHint(TutorialLogic.SHOP, 1, true, false)).toBe(false)
		expect(Pure.levelHint(nil, 1, true, false)).toBe(false)
	end)

	test(
		"'Patients wait for you: press Send': past the tutorial, a patient has waited a while, once a session",
		function()
			expect(Pure.TEXT.Send).toBe("Patients wait for you: press Send")
			local after = Pure.SEND_HINT.After
			expect(Pure.sendHint(TutorialLogic.DONE, after, false)).toBe(true)
			expect(Pure.sendHint(TutorialLogic.DONE, after - 1, false)).toBe(false)
			expect(Pure.sendHint(TutorialLogic.DONE, nil, false)).toBe(false) -- nobody waits
			expect(Pure.sendHint(TutorialLogic.DONE, after + 60, true)).toBe(false) -- shown already
			expect(Pure.sendHint(TutorialLogic.TREAT, after + 60, false)).toBe(false) -- the tutorial has its own card
			expect(Pure.sendHint(0, after + 60, false)).toBe(false)
			expect(after >= 6).toBe(true) -- longer than a Receptionist takes (Logic/Routing.RECEPTION_WAIT)
			expect(Pure.SEND_HINT.Hold > 0).toBe(true)
			-- the prompt it looks for is the one Server/Patients makes and UI/SendCard reads
			expect(Pure.SEND_PROMPT.Name).toBe("SendPrompt")
			expect(
				string.find(source("src/client/UI/SendCard.luau"), 'Pure.PROMPT_NAME = "SendPrompt"', 1, true) ~= nil
			).toBe(true)
			local patients = source("src/server/Patients.luau")
			expect(string.find(patients, 'prompt.Name = "SendPrompt"', 1, true) ~= nil).toBe(true)
			expect(string.find(patients, 'prompt:AddTag("' .. Pure.SEND_PROMPT.Tag .. '")', 1, true) ~= nil).toBe(true)
		end
	)

	test("one hint at a time: the waiting patient, then a new door's line, then the level-up", function()
		expect(Pure.hintPick({})).toBeNil()
		expect(Pure.hintPick({ LevelUp = true })).toBe("LevelUp")
		expect(Pure.hintPick({ LevelUp = true, Door = "Nurses" })).toBe("Door")
		expect(Pure.hintPick({ LevelUp = true, Door = "Nurses", Send = true })).toBe("Send")
	end)

	test("Hud's words: short, no emoji, and nothing about Robux (in-game cash only)", function()
		for _, text in Pure.TEXT do
			local words = 0
			for _ in string.gmatch(text, "%S+") do
				words += 1
			end
			expect(words <= 7).toBe(true)
			expect(Icons.count(text)).toBe(0)
			expect(string.find(string.lower(text), "robux", 1, true)).toBeNil()
		end
	end)
end)

T.describe("Hud (pure): what hides while things are open", function()
	test("the strongest mode wins: Game > Panel > None", function()
		expect(Pure.mode({})).toBe("None")
		expect(Pure.mode({ Odds = "None" })).toBe("None")
		expect(Pure.mode({ Shop = "Panel", Odds = "None" })).toBe("Panel")
		expect(Pure.mode({ Shop = "Panel", MiniGames = "Game" })).toBe("Game")
	end)

	test("a Panel hides the rails, Now and Status; the wallet stays", function()
		expect(Pure.hidden("Panel", false)).toEqual({
			Rails = true,
			Now = true,
			Status = true,
			Wallet = false,
			System = false,
			Hands = false,
		})
	end)

	test("the mini-game hides the rails and Status; the wallet and the Now card stay", function()
		local hide = Pure.hidden("Game", false)
		expect(hide.Rails).toBe(true)
		expect(hide.Status).toBe(true)
		expect(hide.Now).toBe(false)
		expect(hide.Wallet).toBe(false)
	end)

	test("a Popup changes nothing; a celebration hides everything", function()
		for _, hidden in Pure.hidden("None", false) do
			expect(hidden).toBe(false)
		end
		for _, mode in { "None", "Panel", "Game" } do
			for _, hidden in Pure.hidden(mode, true) do
				expect(hidden).toBe(true)
			end
		end
	end)
end)

T.describe("Hud (pure): ⚙️ Settings", function()
	test("every row is a Toggle or a Quiet Link, in words; no label changes with state", function()
		local all = Pure.settingsRows(
			TutorialLogic.DONE,
			true,
			true,
			{ "Badges", "Boards", "Nurses", "Book", "Goals", "Mailbox" }
		)
		for _, extra in Pure.settingsRows(TutorialLogic.SHOP, true, false, {}) do
			table.insert(all, extra)
		end
		for _, name in all do
			local row = Pure.SETTINGS[name]
			local label = if row then row.Label else Pure.MORE[name]
			expect(type(label)).toBe("string")
			expect(Icons.count(label)).toBe(0)
			if row then
				expect(row.Kind == "Toggle" or row.Kind == "Link").toBe(true)
			end
		end
		for _, name in { "Music", "Effects", "Simple", "Helpers" } do
			expect(Pure.SETTINGS[name].Kind).toBe("Toggle")
		end
		for _, name in { "Skip", "Replay", "Admin" } do
			expect(Pure.SETTINGS[name].Kind).toBe("Link")
		end
		-- the builder: Kit.toggle for a Toggle, a Quiet button for a Link, and no words set from state
		local text = source("src/client/UI/Hud.luau")
		expect(string.find(text, "Kit.toggle({ Name = name, Label = spec.Label", 1, true) ~= nil).toBe(true)
		expect(string.find(text, 'Kind = "Quiet",', 1, true) ~= nil).toBe(true)
		expect(string.find(text, "Switch.Text =", 1, true)).toBeNil()
		expect(string.find(text, "Music off", 1, true)).toBeNil()
		expect(string.find(text, "Friends only", 1, true)).toBeNil()
	end)

	test(
		"a fresh Lv 1 player's Settings: three switches and Replay; Badges and Top only once they're revealed",
		function()
			expect(Pure.settingsRows(TutorialLogic.DONE, false, false, {})).toEqual({ "Music", "Effects", "Simple" })
			expect(Pure.settingsRows(TutorialLogic.DONE, true, false, {})).toEqual({
				"Music",
				"Effects",
				"Simple",
				"Helpers",
				"Replay",
			})
		end
	)

	test("Skip only while the tutorial runs; Replay only once it's done and you own a clinic", function()
		for step = TutorialLogic.WELCOME, TutorialLogic.BOOK do
			local rows = Pure.settingsRows(step, true, false, {})
			expect(table.find(rows, "Skip") ~= nil).toBe(true)
			expect(table.find(rows, "Replay")).toBeNil()
		end
		local done = Pure.settingsRows(TutorialLogic.DONE, true, false, {})
		expect(table.find(done, "Skip")).toBeNil()
		expect(table.find(done, "Replay") ~= nil).toBe(true)
		local street = Pure.settingsRows(TutorialLogic.DONE, false, false, {})
		expect(table.find(street, "Replay")).toBeNil()
		expect(table.find(street, "Helpers")).toBeNil()
		local unknown = Pure.settingsRows(0, true, false, {})
		expect(table.find(unknown, "Skip")).toBeNil()
		expect(table.find(unknown, "Replay")).toBeNil()
	end)

	test("today's rows stay, in order; ⚙️ More holds the rail pieces that are off the rail; Admin last", function()
		local rows = Pure.settingsRows(TutorialLogic.DONE, true, true, { "Badges", "Boards" })
		expect(rows).toEqual({ "Music", "Effects", "Simple", "Helpers", "Replay", "Badges", "Boards", "Admin" })
		expect(Pure.settingsRows(TutorialLogic.DONE, true, false, { "Shop", "Boards" })).toEqual({
			"Music",
			"Effects",
			"Simple",
			"Helpers",
			"Replay",
			"Boards",
		})
		-- the phone's More holds exactly what the zone map moves there
		for _, size in SCREENS do
			local layout = HudZones.layout(size[1], size[2])
			for _, piece in layout.More do
				expect(Pure.MORE[piece] ~= nil).toBe(true)
			end
		end
	end)
end)

T.describe("Hud (pure): the zone map on screen", function()
	test("every rail piece has a plate, all the same role (the Shop looks like its neighbours)", function()
		expect(Pure.RAIL_KIND).toBe("Icon")
		for _, list in HudZones.ORDER do
			for _, piece in list do
				local face = Pure.RAIL[piece]
				expect(face ~= nil).toBe(true)
				expect(type(face.Icon)).toBe("string")
				expect(Icons.count(face.Icon)).toBe(1)
				expect(Icons.count(face.Caption)).toBe(0)
				expect(type(face.Caption)).toBe("string")
				expect(face.Kind).toBeNil()
				expect(face.Color).toBeNil()
				expect(#face.Caption <= 8).toBe(true)
			end
		end
	end)

	test(
		"each door's icon is its UI/Icons.Door entry; Mail is always 📬 (the red dot says a letter waits)",
		function()
			expect(Pure.RAIL.Shop.Icon).toBe(Icons.Door.Shop)
			expect(Pure.RAIL.Nurses.Icon).toBe(Icons.Door.Nurses)
			expect(Pure.RAIL.Book.Icon).toBe(Icons.Door.Book)
			expect(Pure.RAIL.Badges.Icon).toBe(Icons.Door.Badges)
			expect(Pure.RAIL.Boards.Icon).toBe(Icons.Door.Top)
			expect(Pure.RAIL.Gifts.Icon).toBe(Icons.Door.Gifts)
			expect(Pure.RAIL.Goals.Icon).toBe(Icons.Door.Goals)
			expect(Pure.RAIL.Mailbox.Icon).toBe(Icons.Door.Mail)
			local text = source("src/client/UI/Hud.luau")
			expect(string.find(text, "mailIcon", 1, true)).toBeNil() -- no 📭 / 📬 swap
		end
	)

	test("phones: 3 a side, Badges and Top under ⚙️ More (640 x 360 too)", function()
		for _, size in { { 640, 360 }, { 667, 375 }, { 800, 360 }, { 844, 390 }, { 932, 430 } } do
			local layout = HudZones.layout(size[1], size[2])
			expect(#layout.Left).toBe(3)
			expect(#layout.Right).toBe(3)
			expect(layout.More).toEqual({ "Badges", "Boards" })
			expect(layout.Button >= 56).toBe(true)
		end
	end)

	test("Status never meets the Now card, the rails, the wallet or the bottom corners", function()
		for _, size in SCREENS do
			local w, h = size[1], size[2]
			local layout = HudZones.layout(w, h)
			local box = Pure.statusBox(layout, w)
			local status = statusRect(box)
			local now = HudZones.nowRect(layout, w)
			expect(box.Width >= 100).toBe(true) -- room for the shortest words at the 18 px floor
			expect(box.Rows >= 3).toBe(true) -- the clock, the event and the visitor always fit
			expect(status.X0 >= 0 and status.X1 <= w).toBe(true)
			expect(status.Y0 >= layout.Top).toBe(true)
			expect(status.Y1 <= h - HudZones.CORNER_CLEAR).toBe(true)
			expect(overlaps(status, now)).toBe(false)
			for _, side in { "Left", "Right" } do
				local list = if side == "Left" then layout.Left else layout.Right
				for index in list do
					expect(overlaps(status, HudZones.railRect(layout, side, index, w))).toBe(false)
				end
			end
			if not layout.WalletInTopbar then
				local wallet = {
					X0 = layout.Margin,
					X1 = layout.Margin + HudZones.WALLET_WIDTH,
					Y0 = layout.Top + 8,
					Y1 = layout.Top + 8 + HudZones.WALLET_HEIGHT,
				}
				expect(overlaps(status, wallet)).toBe(false)
				expect(overlaps(wallet, now)).toBe(false)
			end
			expect(box.Compact).toBe(layout.Phone)
		end
	end)

	test("desktop Status sits at the screen edge; 4 rows from 1280 x 720", function()
		local layout = HudZones.layout(1280, 720)
		local box = Pure.statusBox(layout, 1280)
		expect(box.X1).toBe(1280 - layout.Margin)
		expect(box.Width).toBe(HudZones.STATUS_WIDTH)
		expect(box.Rows).toBe(4)
		expect(Pure.statusBox(HudZones.layout(1920, 1080), 1920).Rows).toBe(4)
	end)

	test("the hands: 56..84 px each, the row clear of the bottom corners", function()
		for _, size in SCREENS do
			local w = size[1]
			for count = 1, 3 do
				local side = Pure.handSize(w, count)
				expect(side >= 56 and side <= 84).toBe(true)
				local row = count * side + (count - 1) * Pure.HAND.Gap
				expect((w - row) / 2 >= 100).toBe(true) -- the thumbstick and the jump button stay clear
			end
		end
		expect(Pure.handSize(1280, 1)).toBe(84)
		expect(Pure.handSize(0 / 0, 0)).toBe(56)
	end)
end)

T.describe("Hud: the level row (Joshua 2026-11-17: 'is there a level up bar. where to see my level?')", function()
	local text = source("src/client/UI/Hud.luau")

	test("the level is a Unit (Icons.Unit.Level via Kit.unit) with ONE Kit.bar, driven by Logic/LevelBar", function()
		expect(string.find(text, 'levelUnit("Badge", Icons.Unit.Level', 1, true) ~= nil).toBe(true)
		expect(string.find(text, "Icons.words(Icons.level(view.Level", 1, true) ~= nil).toBe(true)
		expect(string.find(text, "LevelBar.view(state, data.Levels)", 1, true) ~= nil).toBe(true)
		expect(string.find(text, "setLevelBar(view.Fraction, view.Max)", 1, true) ~= nil).toBe(true)
		expect(string.find(text, "targets.Level = levelButton", 1, true) ~= nil).toBe(true)
		local _, bars = string.gsub(text, "Kit%.bar%(", "")
		expect(bars).toBe(1) -- the level bar is the only Kit.bar on the HUD
	end)

	test("the old Stars-milestone bar is gone, and nothing says 'Everything unlocked'", function()
		expect(string.find(text, "starTrack", 1, true)).toBeNil()
		expect(string.find(text, "STAR_BAR", 1, true)).toBeNil()
		expect(string.find(text, "Everything unlocked", 1, true)).toBeNil()
	end)

	test("ready: a tap opens the Shop on its Hospital tab and points at Shop.levelUpButton()", function()
		expect(string.find(text, 'ctx.fire("Open", "Shop", "Hospital")', 1, true) ~= nil).toBe(true)
		expect(string.find(text, "shop.levelUpButton()", 1, true) ~= nil).toBe(true)
		expect(string.find(source("src/client/UI/Shop.luau"), "function Shop.levelUpButton()", 1, true) ~= nil).toBe(
			true
		)
		-- Hud never requires Shop at load (Shop requires Hud)
		expect(string.find(text, "require(script.Parent.Shop)", 1, true)).toBeNil()
	end)

	test("in-game cash only: the HUD never mentions Robux", function()
		expect(string.find(string.lower(text), "robux", 1, true)).toBeNil()
	end)

	test("the level row fits the wallet's rows in the zone map", function()
		expect(string.find(text, "HudZones.LEVEL_ROW", 1, true) ~= nil).toBe(true)
		expect(string.find(text, "HudZones.WALLET_ROW", 1, true) ~= nil).toBe(true)
		local line, barPx, gap = 24, 8, 4 -- LEVEL_LINE, Theme.Calm.Bar, Theme.Space.Tight
		expect(tonumber(string.match(text, "\nlocal LEVEL_LINE = (%d+)"))).toBe(line)
		expect(line + gap + barPx + gap + line).toBe(HudZones.LEVEL_ROW)
	end)
end)

T.describe("Hud and Toasts: the UI rules", function()
	test("the calm ratchet (UI direction §6): Hud, Toasts, Wayfinder and Boards are at 0 on every rule", function()
		local over = UiRules.ratchet({
			"src/client/UI/Hud.luau",
			"src/client/UI/Toasts.luau",
			"src/client/UI/Wayfinder.luau",
			"src/client/UI/Boards.luau",
		}, {})
		assert(#over == 0, "\n" .. table.concat(over, "\n"))
	end)

	test("the outlines left are the ones over the 3D world, each marked; a toast's inside has none", function()
		local allowed = {
			["src/client/UI/Hud.luau"] = 8,
			["src/client/UI/Toasts.luau"] = 1,
			["src/client/UI/Wayfinder.luau"] = 3,
			["src/client/UI/Boards.luau"] = 1,
		}
		for path, most in allowed do
			local _, count = string.gsub(source(path), "uirules: allow StrokeBudget", "")
			expect(count <= most).toBe(true)
		end
	end)

	test("uirules: no text under 18, no local tab or text fit copies, radii from tokens, no header colour", function()
		local violations = UiRules.check({ "src/client/UI/Hud.luau", "src/client/UI/Toasts.luau" })
		if #violations > 0 then
			error("UI rule violations:\n" .. UiRules.format(violations))
		end
	end)

	test("nothing in the HUD or the notices loops: no shine, breathing or rays (the motion budget)", function()
		for _, path in { "src/client/UI/Hud.luau", "src/client/UI/Toasts.luau" } do
			local text = source(path)
			expect(string.find(text, "Kit.shine(", 1, true)).toBeNil()
			expect(string.find(text, "Kit.breathing(", 1, true)).toBeNil()
			expect(string.find(text, "Kit.rays(", 1, true)).toBeNil()
		end
	end)

	test("every Hud.target name the pointers and flying icons use is assigned", function()
		local text = source("src/client/UI/Hud.luau")
		for _, name in { "Cash", "Stars", "Settings", "Hands" } do
			expect(string.find(text, "targets." .. name .. " = ", 1, true) ~= nil).toBe(true)
		end
		-- the rail plates: every piece of both rails, by name (the tutorial points at "Shop" and "Book")
		expect(string.find(text, "targets[name] = button", 1, true) ~= nil).toBe(true)
		expect(string.find(text, "addRail(leftZone, HudZones.ORDER.LeftRail)", 1, true) ~= nil).toBe(true)
		expect(string.find(text, "addRail(rightZone, HudZones.ORDER.RightRail)", 1, true) ~= nil).toBe(true)
		expect(table.find(HudZones.ORDER.LeftRail, "Shop") ~= nil).toBe(true)
		expect(table.find(HudZones.ORDER.LeftRail, "Book") ~= nil).toBe(true)
	end)

	test("no pills on the wallet and no bottom bar: the candy chips are gone", function()
		local text = source("src/client/UI/Hud.luau")
		expect(string.find(text, "local function pill(", 1, true)).toBeNil()
		expect(string.find(text, "local TABS", 1, true)).toBeNil()
		expect(string.find(text, "candyGradient", 1, true)).toBeNil()
		expect(string.find(source("src/client/UI/Toasts.luau"), "BELOW_WALLET_Y", 1, true)).toBeNil()
	end)
end)
