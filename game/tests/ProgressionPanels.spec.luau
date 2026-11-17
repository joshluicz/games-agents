--!nocheck
-- The look overhaul's T7 (look build plan §D T7, §B8): the Progression panels (UI/NursePanel, AgencyPanel,
-- MarketPanel, BranchPanel, LiftPanel) on the one modal template. Run from game/ with the rest:  lune run tests/run
--   · every T7 file keeps the UI rules (tests/uirules: no text under 18 px, no local paintTab/textLimit, radii from
--     Theme.Radius, no panel-specific header colour)
--   · the confirms each panel passes to Hud.confirm: titles of at most two words, questions of at most six, the role
--     (Hire, Buy and List are Primary; Sell and Reset are Destructive), a 1 s hold for selling an Epic or rarer (or any
--     nurse at Lv 2+), and "Not now" the default (UI/Modal's PURE confirm defaults)
--   · the Agency's odds popup (Hud.oddsPopup): every rarity it can stock, the word and the server's own number, the
--     same odds Logic/Agency rolls, and its notes
--   · the source keeps the template: Modal.tabs for the tabbed panels, THE confirm and THE odds popup instead of
--     hand-built ones, role kinds only, no looping effect (shine, breathing, rays), no cross mark, flat fills
--   · Branch themes show only the Roof and Trim swatches (the walls stay the plot's colour, §G4)

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test
local UiRules = require("./uirules")

local AgencyLogic = require("../src/shared/Logic/Agency")
local MarketLogic = require("../src/shared/Logic/Market")
local NurseLogic = require("../src/shared/Logic/Nurse")
local RebirthLogic = require("../src/shared/Logic/Rebirth")
local TreeLogic = require("../src/shared/Logic/Tree")
local Nurses = require("../src/shared/Data/Nurses")
local Rarities = require("../src/shared/Data/Rarities")
local Themes = require("../src/shared/Data/Themes")
local Config = require("./config")
local Icons = require("../src/client/UI/Icons")

local FILES = {
	"src/client/UI/NursePanel.luau",
	"src/client/UI/AgencyPanel.luau",
	"src/client/UI/MarketPanel.luau",
	"src/client/UI/BranchPanel.luau",
	"src/client/UI/LiftPanel.luau",
}
local ROLES = { Primary = true, Collect = true, Secondary = true, Quiet = true, Destructive = true, Icon = true }

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
	return luau.load(block, { debugName = path .. " (pure)", environment = env, injectGlobals = true })()
end

-- The code part of a file: comments dropped, so a rule is about what runs, not what a comment says.
local function code(path: string): string
	local out = {}
	for line in string.gmatch(source(path) .. "\n", "(.-)\r?\n") do
		local body = line
		local quote = nil
		local i = 1
		while i <= #line do
			local c = string.sub(line, i, i)
			if quote then
				if c == "\\" then
					i += 1
				elseif c == quote then
					quote = nil
				end
			elseif c == '"' or c == "'" or c == "`" then
				quote = c
			elseif c == "-" and string.sub(line, i + 1, i + 1) == "-" then
				body = string.sub(line, 1, i - 1)
				break
			end
			i += 1
		end
		table.insert(out, body)
	end
	return table.concat(out, "\n")
end

local function count(text: string, plain: string): number
	local n, from = 0, 1
	while true do
		local at = string.find(text, plain, from, true)
		if not at then
			return n
		end
		n += 1
		from = at + #plain
	end
end

-- Words on screen: tokens with a letter in them (emoji, numbers and "·" aren't words), as the panels count them.
local function words(text: string): number
	local n = 0
	for token in string.gmatch(text, "%S+") do
		if string.find(token, "%a") then
			n += 1
		end
	end
	return n
end

-- Every pure block gets UI/Icons (the chrome emoji dictionary, a pure library) whether it reads it yet or not.
local ModalPure = pureBlock("src/client/UI/Modal.luau", { Icons = Icons })
local AP = pureBlock("src/client/UI/AgencyPanel.luau", { NurseLogic = NurseLogic, Icons = Icons })
local MP = pureBlock("src/client/UI/MarketPanel.luau", { MarketLogic = MarketLogic, Icons = Icons })
local BP = pureBlock("src/client/UI/BranchPanel.luau", {
	RebirthLogic = RebirthLogic,
	TreeLogic = TreeLogic,
	NurseLogic = NurseLogic,
	Icons = Icons,
})

-- What every confirm a panel passes must be: two words of title at most, six words of question at most, a role, the
-- hold it asks for, and (through UI/Modal's defaults) "Not now" as the default focus.
local function checkConfirm(spec: any, kind: string, hold: number, where: string)
	expect(type(spec.Title)).toBe("string")
	assert(words(spec.Title) >= 1 and words(spec.Title) <= 2, where .. ": title not 1-2 words: " .. spec.Title)
	assert(words(spec.Line) <= 6, where .. ": question over 6 words: " .. spec.Line)
	assert(words(spec.Yes) <= 6, where .. ": yes over 6 words: " .. spec.Yes)
	expect(spec.Kind).toBe(kind)
	expect(spec.Hold).toBe(hold)
	local shown = ModalPure.confirm(spec)
	expect(shown.Title).toBe(spec.Title)
	expect(shown.Line).toBe(spec.Line)
	expect(shown.Kind).toBe(kind)
	expect(shown.Hold).toBe(hold)
	expect(shown.No).toBe(ModalPure.NOT_NOW)
	expect(shown.Focus).toBe("No")
end

T.describe("T7 panels: the UI rules (tests/uirules)", function()
	for _, path in FILES do
		test(path, function()
			local violations = UiRules.check({ path })
			if #violations > 0 then
				error("\n" .. UiRules.format(violations))
			end
		end)
	end
end)

T.describe("T7 panels: THE confirm (Hud.confirm)", function()
	test("Agency hire: Primary, no hold, for every nurse at every price", function()
		for _, nurseId in Nurses.Order do
			local nurse = Nurses[nurseId]
			for _, price in { 150, 2250, 1234567 } do
				local spec = AP.confirmSpec("Hire", nurse.Icon, nurse.Name, 1, price, nurse.Rarity)
				checkConfirm(spec, "Primary", 0, "hire " .. nurseId)
				expect(spec.Line).toBe(AP.confirmText("Hire", nurse.Icon, nurse.Name, 1, price))
			end
		end
	end)

	test("Agency sell: Destructive; a 1 s hold for Epic and up, and for any nurse at Lv 2+", function()
		expect(AP.HOLD_SECONDS).toBe(1)
		for _, nurseId in Nurses.Order do
			local nurse = Nurses[nurseId]
			for _, level in { 1, 2, 7, 15 } do
				local spec = AP.confirmSpec("Sell", nurse.Icon, nurse.Name, level, 30, nurse.Rarity)
				local epicUp = AP.rank(nurse.Rarity) >= AP.rank("Epic")
				local hold = if epicUp or level >= 2 then AP.HOLD_SECONDS else 0
				checkConfirm(spec, "Destructive", hold, "sell " .. nurseId .. " Lv " .. level)
				expect(spec.Line).toBe(AP.confirmText("Sell", nurse.Icon, nurse.Name, level, 30))
				if epicUp then
					assert(spec.Hold >= 1, "an Epic or rarer sale is always a hold: " .. nurseId)
				end
			end
		end
		-- a plain tap only for a Common or Rare at Lv 1
		expect(AP.confirmSpec("Sell", "🐶", "Puff Pup", 1, 30, "Common").Hold).toBe(0)
		expect(AP.confirmSpec("Sell", "🐶", "Puff Pup", 1, 30, "Rare").Hold).toBe(0)
		expect(AP.confirmSpec("Sell", "🐶", "Puff Pup", 1, 30, "Epic").Hold).toBe(1)
	end)

	test("Market buy and list: Primary, no hold, the question, who sells it and what you get", function()
		for _, nurseId in Nurses.Order do
			local nurse = Nurses[nurseId]
			for _, level in { 1, 15 } do
				local buy = MP.buyConfirm(nurse.Icon, level, 1234567, "Sam")
				checkConfirm(buy, "Primary", 0, "buy " .. nurseId)
				assert(string.find(buy.Line, MP.confirmBuy(nurse.Icon, level, 1234567), 1, true) == 1, buy.Line)
				assert(string.find(buy.Line, "by Sam", 1, true), "the seller: " .. buy.Line)
				local list = MP.listConfirm(nurse.Icon, level, 420, MP.payout(420, Config))
				checkConfirm(list, "Primary", 0, "list " .. nurseId)
				assert(string.find(list.Line, MP.confirmList(nurse.Icon, level, 420), 1, true) == 1, list.Line)
				assert(string.find(list.Line, "You get " .. MP.money(MP.payout(420, Config)), 1, true), list.Line)
			end
		end
		-- no seller name: just the question
		expect(MP.buyConfirm("🐶", 7, 420, nil).Line).toBe("Buy 🐶 Lv 7 for 💰420?")
		expect(MP.buyConfirm("🐶", 7, 420, "").Line).toBe("Buy 🐶 Lv 7 for 💰420?")
	end)

	test("Branch tree reset: Destructive, no hold, its own words", function()
		local spec = BP.resetConfirm()
		checkConfirm(spec, "Destructive", 0, "reset")
		expect(spec.Title).toBe(BP.TEXT.ResetTitle)
		expect(spec.Line).toBe(BP.TEXT.ResetNote)
		expect(spec.Yes).toBe(BP.TEXT.ResetYes)
	end)
end)

T.describe("T7 panels: THE odds popup (Hud.oddsPopup)", function()
	test(
		"the Agency's: every rarity it stocks, the word and the server's own number, the same odds it rolls",
		function()
			local odds = AgencyLogic.odds(Config)
			local notes = AP.oddsNotes(odds, 3, Config.Agency.RestockSeconds)
			local spec = AP.oddsSpec(odds, Rarities, notes)
			expect(spec.Title).toBe("Odds")
			assert(words(spec.Title) <= 2, spec.Title)
			local rows = AP.oddsRows(odds)
			expect(#spec.Rows).toBe(#rows)
			local total = 0
			for index, row in spec.Rows do
				local rarity = rows[index].Rarity
				expect(row.Percent).toBe(odds[rarity])
				expect(row.Name).toBe(Rarities[rarity].Name)
				expect(row.Icon).toBe(Rarities[rarity].Icon)
				-- the word and the number on every row (Roblox's paid-random-item guidance, even for in-game cash)
				local line = ModalPure.oddsLine(row)
				assert(string.find(line, row.Name, 1, true), line)
				assert(string.find(line, ModalPure.percent(row.Percent), 1, true), line)
				total += row.Percent
			end
			expect(total).toBeCloseTo(100, 6)
			expect(spec.Notes).toEqual(notes)
			for _, note in notes do
				assert(words(note) <= 6, "note over 6 words: " .. note)
				assert(not string.find(note, ":%d%d"), "no clock in a note: " .. note)
			end
		end
	)

	test("the notes: never above its rarest, Lucky Stock's same odds, the Epic gate, the restock (no clock)", function()
		local odds = AgencyLogic.odds(Config)
		local notes = AP.oddsNotes(odds, 3, 300)
		expect(table.find(notes, AP.neverText(odds))).toBeTruthy()
		expect(table.find(notes, "Lucky Stock: same odds")).toBeTruthy()
		expect(table.find(notes, "Epic: hospital Lv 3+")).toBeTruthy()
		expect(notes[#notes]).toBe("New nurses every 5 min")
		-- no Epic gate line when Epics come from Lv 1, or when it can't stock Epics at all
		expect(table.find(AP.oddsNotes(odds, 1, 300), "Epic: hospital Lv 1+")).toBeNil()
		local noEpic = { Common = 80, Rare = 20 }
		for _, note in AP.oddsNotes(noEpic, 3, 300) do
			assert(not string.find(note, "Epic:", 1, true), note)
		end
		-- junk in, a popup still out (no rows, the notes it can say)
		expect(#AP.oddsSpec(nil, Rarities, nil).Rows).toBe(0)
		expect(AP.oddsSpec({ Common = 100 }, nil, nil).Rows[1].Name).toBe("Common")
	end)
end)

T.describe("T7 panels: the template in the source", function()
	local bodies = {}
	for _, path in FILES do
		bodies[path] = code(path)
	end

	test("every button Kind is a role (no candy kinds: Cyan, Pink, Purple, Cash, Good, Card)", function()
		for path, body in bodies do
			for kind in string.gmatch(body, 'Kind%s*=%s*"(%w+)"') do
				assert(ROLES[kind], path .. ": Kind " .. kind .. " is not a role")
			end
		end
	end)

	test(
		"the tabbed panels use THE tab pattern (Modal.tabs); the Lift is a Popup of big Secondary floor buttons",
		function()
			for _, name in { "NursePanel", "AgencyPanel", "MarketPanel", "BranchPanel" } do
				local body = bodies["src/client/UI/" .. name .. ".luau"]
				expect(count(body, "Modal.tabs(")).toBe(1)
				expect(count(body, "Kit.iconButton(")).toBe(0)
			end
			local lift = bodies["src/client/UI/LiftPanel.luau"]
			assert(string.find(lift, 'Layer = "Popup"', 1, true), "the Lift picker is a Popup")
			assert(string.find(lift, 'Kind = "Secondary"', 1, true), "the floor buttons are Secondary")
		end
	)

	test("THE confirm and THE odds popup: no hand-built confirm or odds popup is left", function()
		for _, name in { "AgencyPanel", "MarketPanel", "BranchPanel" } do
			local body = bodies["src/client/UI/" .. name .. ".luau"]
			assert(count(body, "Hud.confirm(") >= 1, name .. " asks through Hud.confirm")
		end
		-- v2's own popups are gone (Modal.confirm's "Not now" is the default focus now)
		for name, popup in { AgencyPanel = "AgencyConfirm", MarketPanel = "MarketConfirm", BranchPanel = "BranchReset" } do
			expect(count(bodies["src/client/UI/" .. name .. ".luau"], '"' .. popup .. '"')).toBe(0)
		end
		expect(count(bodies["src/client/UI/AgencyPanel.luau"], '"AgencyOdds"')).toBe(0)
		for _, name in { "AgencyPanel", "MarketPanel" } do
			expect(count(bodies["src/client/UI/" .. name .. ".luau"], '"Not now"')).toBe(0)
		end
		expect(count(bodies["src/client/UI/AgencyPanel.luau"], "Hud.oddsPopup(")).toBe(1)
		-- the only Popups the panels still build themselves: the job picker and the lift's floor picker
		local popups = 0
		for _, body in bodies do
			popups += count(body, 'Layer = "Popup"')
		end
		expect(popups).toBe(2)
		expect(count(bodies["src/client/UI/NursePanel.luau"], 'Layer = "Popup"')).toBe(1)
		expect(count(bodies["src/client/UI/LiftPanel.luau"], 'Layer = "Popup"')).toBe(1)
	end)

	test("no looping effect (nothing shines, breathes or turns) and no candy gradient", function()
		for path, body in bodies do
			for _, call in { "Kit.shine(", "Kit.breathing(", "Kit.rays(", "candyGradient(", "Kit.gloss(" } do
				if count(body, call) > 0 then
					error(path .. " calls " .. call)
				end
			end
		end
	end)

	test("no cross mark anywhere (the nurse cap wears a heart)", function()
		for path, text in { Nurse = source(FILES[1]), Market = source(FILES[3]) } do
			assert(not string.find(text, "✚", 1, true), path .. " has a cross")
			assert(string.find(text, '"♥"', 1, true), path .. ": the cap's heart")
		end
		for _, path in FILES do
			assert(not string.find(source(path), "✚", 1, true), path .. " has a cross")
		end
	end)

	test("the 🏢 Branch themes show only the Roof and Trim swatches, and say the walls stay your colour", function()
		expect(BP.SWATCHES).toEqual({ "Roof", "Trim" })
		for _, key in BP.SWATCHES do
			for _, themeId in Themes.Order do
				expect(type(Themes[themeId][key])).toBe("string")
			end
		end
		expect(BP.TEXT.WallsStay).toBe("Walls stay your colour")
		assert(words(BP.TEXT.WallsStay) <= 6, BP.TEXT.WallsStay)
		local body = bodies["src/client/UI/BranchPanel.luau"]
		assert(not string.find(body, '"Wall"', 1, true), "no Wall swatch")
		assert(string.find(body, "Palette.World.Roof", 1, true), "Candy's roof swatch is the world's dark roof")
		assert(string.find(body, "Palette.World.Trim", 1, true), "Candy's trim swatch is the world's warm trim")
	end)

	test("the Agency still says how often new nurses come, never a clock", function()
		local body = bodies["src/client/UI/AgencyPanel.luau"]
		assert(string.find(body, "Pure.everyText(cfg.Agency.RestockSeconds)", 1, true), "the restock line")
		expect(count(body, "Juice.clock(")).toBe(0)
		expect(count(body, "os.date(")).toBe(0)
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- T5 (UI direction §4 #6, #10, #11; Joshua, memory-20261117-007; R0 is memory-20261117-006): the progress and
-- reward panels' words, what a fresh save sees, and their calm-rule ratchet (every file at 0, locked here).
------------------------------------------------------------------------------------------------------------------
local Levels = require("../src/shared/Data/Levels")
local Perks = require("../src/shared/Data/Perks")
local Abilities = require("../src/shared/Data/Abilities")
local Wings = require("../src/shared/Data/Wings")
local DailyGoals = require("../src/shared/Data/DailyGoals")
local Playtime = require("../src/shared/Data/Playtime")

local function block(path: string, startMark: string, endMark: string, name: string, env: { [string]: any }?): any
	local text = source(path)
	local first = string.find(text, startMark, 1, true)
	local last = string.find(text, endMark, 1, true)
	assert(first and last and last > first, "no " .. startMark .. " block in " .. path)
	local options = if env then { debugName = path, environment = env, injectGlobals = true } else { debugName = path }
	return luau.load(string.sub(text, first, last - 1) .. "\nreturn " .. name, options)()
end

local MailPure = block("src/client/UI/Mailbox.luau", "-- PURE-BEGIN", "-- PURE-END", "Pure", { Icons = Icons })
local GiftPure = block("src/client/UI/PlayGifts.luau", "-- PURE-BEGIN", "-- PURE-END", "Pure", { Icons = Icons })
local DayPure = block("src/client/UI/DayReportPanel.luau", "-- PURE-BEGIN", "-- PURE-END", "Pure", { Icons = Icons })
local Words = block("src/client/UI/Celebrate.luau", "-- BEGIN PURE", "-- END PURE", "Words")

local T5_FILES = {
	"src/client/UI/BranchPanel.luau",
	"src/client/UI/BookPanel.luau",
	"src/client/UI/BadgeBook.luau",
	"src/client/UI/Mailbox.luau",
	"src/client/UI/PlayGifts.luau",
	"src/client/UI/DayReportPanel.luau",
	"src/client/UI/Celebrate.luau",
}

local function commas(n: number): string
	return tostring(math.floor(n))
end

T.describe("T5 progress and rewards: the calm UI", function()
	test("the calm rules: every T5 file is at 0 on every rule (the ratchet, locked here)", function()
		local over = UiRules.ratchet(T5_FILES, {})
		assert(#over == 0, "\n" .. table.concat(over, "\n"))
		for _, path in T5_FILES do
			expect(UiRules.check({ path })).toEqual({})
		end
	end)

	test("every T5 panel title is words only", function()
		expect(MailPure.TEXT.Title).toBe("Mail")
		expect(MailPure.TEXT.GoalsTitle).toBe("Goals")
		expect(GiftPure.TEXT.Title).toBe("Play gifts")
		expect(DayPure.TEXT.Title).toBe("Day done!")
		expect(BP.TEXT.Title).toBe("Branches")
		for _, text in { MailPure.TEXT.Title, MailPure.TEXT.GoalsTitle, GiftPure.TEXT.Title, DayPure.TEXT.Title } do
			expect(Icons.count(text)).toBe(0)
			assert(words(text) <= 2, text)
		end
		local book = source("src/client/UI/BookPanel.luau")
		assert(string.find(book, 'Title = "Book"', 1, true), "the Book's title is the word")
	end)

	test("Mailbox: goals in words, a reward with one Unit, Open on the Collect button (no 🎁)", function()
		for _, def in DailyGoals do
			local text = MailPure.goalText(Wings, def)
			expect(Icons.count(text)).toBe(0)
			assert(words(text) <= 6, text)
			local reward = MailPure.rewardText(def, commas)
			assert(Icons.count(reward) <= 1, reward)
		end
		expect(MailPure.rewardText({ Reward = { Cash = 40, Stars = 2 } }, commas)).toBe("💰 40 + 2 stars")
		expect(MailPure.rewardText({ Reward = { Stars = 1 } }, commas)).toBe("1 star")
		expect(MailPure.goalText(Wings, { Kind = "CureNight", Target = 3 })).toBe("Treat 3 night patients")
		expect(MailPure.goalText(Wings, { Kind = "CureWing", Target = 4, Wing = "Bath" })).toBe(
			"Treat 4 " .. Wings.Bath.Name .. " patients"
		)
		expect(MailPure.TEXT.Open).toBe("Open")
		expect(MailPure.TEXT.Busy).toBe(Icons.State.Waiting)
		for key, text in MailPure.TEXT do
			if key ~= "Busy" then
				expect(Icons.count(text)).toBe(0)
			end
		end
		expect(Icons.count(MailPure.KEEPER)).toBe(1)
	end)

	test("Play gifts: a reward with one Unit, the rank line and the footer in words", function()
		for _, gift in Playtime.Gifts do
			local line = GiftPure.rewardText(gift, { QuickHands = {}, LuckyTips = {}, StarRush = {} }, commas)
			expect(Icons.count(line)).toBe(1)
		end
		expect(GiftPure.rewardText({ Cash = 30, Stars = 1, Boost = "QuickHands" }, { QuickHands = {} }, commas)).toBe(
			"💰 30 · 1 star · boost"
		)
		expect(GiftPure.rankLine("4h 12m", Playtime.Ranks[3])).toBe(
			"4h 12m played · next: " .. Playtime.Ranks[3].Name .. " at " .. Playtime.Ranks[3].Hours .. "h"
		)
		expect(Icons.count(GiftPure.rankLine("4h", nil))).toBe(0)
		expect(GiftPure.footer(true, true)).toBe("All gifts opened today!")
		expect(GiftPure.footer(false, false)).toBe("Paused while you rest")
		expect(GiftPure.footer(false, true)).toBe("Gifts unlock as you play")
	end)

	test("Day Report: a fresh save sees three lines; pages and the next goal join as they unlock", function()
		local report = DayPure.clean({ Cured = 4, CashGained = 120, StarsGained = 3, NewPages = {}, Next = {} })
		local fresh = DayPure.visible(report, { Level = 1, Upgrades = {}, Rooms = { Stand = true } })
		expect(fresh).toEqual({ Cured = true, Cash = true, Stars = true, Pages = false, Next = false })
		-- a report without CashGained (an older server): no Cash line, nothing made up
		expect(report.CashGained).toBe(120)
		local today = DayPure.clean({ Cured = 4, StarsGained = 3, NewPages = { "ToastPup" } })
		expect(today.CashGained).toBeNil()
		expect(DayPure.visible(today, {}).Cash).toBe(false)
		expect(DayPure.visible(today, {}).Pages).toBe(true)
		-- the next goal once there is one and the Shop has been used
		local rich = DayPure.clean({ Cured = 9, StarsGained = 3, Next = { Kind = "Room", Id = "BathRoom", Icon = "" } })
		expect(DayPure.visible(rich, { Level = 1, Rooms = { Stand = true } }).Next).toBe(false)
		expect(DayPure.visible(rich, { Level = 2 }).Next).toBe(true)
		expect(DayPure.visible(rich, { Level = 1, Upgrades = { Speed = 1 } }).Next).toBe(true)
		expect(DayPure.visible(rich, { Level = 1, Rooms = { Stand = true, BathRoom = true } }).Next).toBe(true)
		-- junk in, a clean report out
		expect(DayPure.clean(nil)).toBeNil()
		expect(DayPure.clean({ Cured = -3, StarsGained = 0 / 0 }).Cured).toBe(0)
		expect(DayPure.pagesText(1)).toBe("+1 new page")
		expect(DayPure.pagesText(3)).toBe("+3 new pages")
		expect(DayPure.TEXT.Shop).toBe("Shop")
		local body = source("src/client/UI/DayReportPanel.luau")
		assert(string.find(body, "Kit.textLimit(cured, Theme.TextSize.Hero)", 1, true), "the count stays Hero")
	end)

	test("Celebrate stays loud, but its chrome emoji are the dictionary's and never two side by side", function()
		expect(Words.ICON.Cash).toBe(Icons.Unit.Cash)
		expect(Words.ICON.Tree).toBe(Icons.Unit.Tree)
		expect(Words.ICON.Branches).toBe(Icons.Door.Branches)
		expect(Words.ICON.Odds).toBe(Icons.Door.Odds)
		expect(Words.ICON.Nurses).toBe(Icons.Door.Nurses)
		expect(Words.ICON.Again).toBe(Icons.Mark.Again)
		local data = {
			Nurses = Nurses,
			Rarities = Rarities,
			Levels = Levels,
			Decor = {},
			Rooms = {},
			Perks = Perks,
			Themes = Themes,
			Abilities = Abilities,
			Unlocks = RebirthLogic.UNLOCKS,
			Config = Config,
		}
		for count = 1, 12 do
			local words = Words.of({ Kind = "Rebirth", Title = "New branch!", Icon = "🏢", Count = count }, data)
			for _, unlockId in RebirthLogic.unlocks(count) do
				Words.fold(words, unlockId, data)
			end
			expect(words.Chips[1]).toBe(
				"×" .. Words.decimal(RebirthLogic.multiplier(count, Config)) .. " cash and stars"
			)
			for _, chip in words.Chips do
				assert(Icons.count(chip) <= 1, "two emoji in a chip: " .. chip)
			end
		end
		-- the odds still show on the Golden unlock (red line 3)
		local golden = Words.unlockChips("Golden", data)
		expect(golden[2]).toBe(Icons.Door.Odds .. " 1 in " .. math.floor(1 / Config.GoldenChance + 0.5))
		for _, nurseId in Nurses.Order do
			local level = Words.of({
				Kind = "NurseLevel",
				Title = "Level up!",
				Icon = "⬆️",
				NurseId = nurseId,
				Level = 5,
				Ability = true,
			}, data)
			for _, chip in level.Chips do
				assert(Icons.count(chip) <= 1, "two emoji in a chip: " .. chip)
			end
		end
		local body = code("src/client/UI/Celebrate.luau")
		expect(count(body, '"🎉 Yay!"')).toBe(0)
		assert(string.find(body, "title.Text = words.Title", 1, true), "the title is words")
	end)
end)
