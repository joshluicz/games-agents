--!nocheck
-- The HUD's screen rules (look build plan §B7, T5): the PURE-BEGIN..PURE-END block of UI/Hud, loaded on its own (the
-- rest of Hud needs Roblox) against the real Logic/Tutorial, Logic/NextEvent and Logic/HudZones, plus the UI rules
-- (tests/uirules) on Hud and Toasts and a few source checks (no perpetual effects, every pointer target assigned).
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
})

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
	test("the highest priority shows: warnings 30 > the tutorial 20 > the tracked goal 10", function()
		expect(Pure.PRIORITY).toEqual({ Warning = 30, Tutorial = 20, Goal = 10 })
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
		expect(Pure.dayLine(false, 207, 2, true)).toBe("🌙 in 3:27")
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

	test("the visitor, with words", function()
		expect(Pure.visitorLine("Coming")).toBe("Visitor ⭐")
		expect(Pure.visitorLine("Done")).toBe("Visitor ✅")
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
	test("the first goal under its target, as 'Cure 5 · 3/5'", function()
		local goals = { { Id = "Cure5", Progress = 3, Day = 1 }, { Id = "Make10", Progress = 0, Day = 1 } }
		local goal = Pure.trackedGoal(goals, DailyGoals, Wings)
		expect(goal.Id).toBe("Cure5")
		expect(goal.Text).toBe("Cure 5 · 3/5")
		expect(goal.Icon).toBe("🎯")
		expect(goal.Ratio).toBeCloseTo(0.6)
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
		expect(night.Text).toBe("Cure 3 🌙 · 1/3")
	end)
end)

T.describe("Hud (pure): the first-session reveal", function()
	test(
		"💰 only until the step is known; ⭐ after the first cure; 🛒 at SHOP; 📖 at BOOK; the rest at DONE",
		function()
			local none = { Stars = false, Shop = false, Book = false, Rest = false }
			local all = { Stars = true, Shop = true, Book = true, Rest = true }
			expect(Pure.reveal(0)).toEqual(none)
			expect(Pure.reveal(TutorialLogic.WELCOME)).toEqual(none)
			expect(Pure.reveal(TutorialLogic.REST).Stars).toBe(false)
			expect(Pure.reveal(TutorialLogic.REST, true).Stars).toBe(true)
			expect(Pure.reveal(TutorialLogic.MORE).Stars).toBe(true)
			expect(Pure.reveal(TutorialLogic.MORE).Shop).toBe(false)
			expect(Pure.reveal(TutorialLogic.SHOP).Shop).toBe(true)
			expect(Pure.reveal(TutorialLogic.SHOP).Book).toBe(false)
			expect(Pure.reveal(TutorialLogic.BOOK).Book).toBe(true)
			expect(Pure.reveal(TutorialLogic.BOOK).Rest).toBe(false)
			expect(Pure.reveal(TutorialLogic.DONE)).toEqual(all)
			expect(Pure.reveal(nil)).toEqual(all) -- a snapshot without the field: no tutorial
		end
	)

	test("a replay keeps the HUD full at every step", function()
		for step = TutorialLogic.WELCOME, TutorialLogic.DONE do
			expect(Pure.reveal(step, false, true).Rest).toBe(true)
		end
	end)

	test("the staggered reveal walks every rail piece once, then Status", function()
		local seen = {}
		for _, name in Pure.REVEAL_ORDER do
			expect(seen[name]).toBeNil()
			seen[name] = true
		end
		for _, list in HudZones.ORDER do
			for _, piece in list do
				expect(seen[piece]).toBe(true)
			end
		end
		expect(Pure.REVEAL_ORDER[#Pure.REVEAL_ORDER]).toBe("Status")
		expect(Pure.STAGGER).toBe(0.15)
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
				expect(type(face.Caption)).toBe("string")
				expect(face.Kind).toBeNil()
				expect(face.Color).toBeNil()
				expect(#face.Caption <= 8).toBe(true)
			end
		end
	end)

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

T.describe("Hud and Toasts: the UI rules", function()
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
