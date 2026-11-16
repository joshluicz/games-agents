--!nocheck
-- The Nurses client's pure helpers (depth update T4): the PURE-BEGIN..PURE-END blocks of UI/BeltView and
-- UI/NursePanel, loaded on their own (the rest of those modules needs Roblox) and tested against the real
-- Logic/Belt, Logic/Nurse, Logic/Levels, Logic/Tutorial and Data/Nurses, Rarities and Levels. Run from game/ with
-- the rest:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local BeltLogic = require("../src/shared/Logic/Belt")
local NurseLogic = require("../src/shared/Logic/Nurse")
local LevelsLogic = require("../src/shared/Logic/Levels")
local TutorialLogic = require("../src/shared/Logic/Tutorial")
local Nurses = require("../src/shared/Data/Nurses")
local Rarities = require("../src/shared/Data/Rarities")
local Levels = require("../src/shared/Data/Levels")

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

local BeltPure = pureBlock("src/client/UI/BeltView.luau", {
	BeltLogic = BeltLogic,
	NurseLogic = NurseLogic,
	TutorialLogic = TutorialLogic,
})
local PanelPure = pureBlock("src/client/UI/NursePanel.luau", {
	LevelsLogic = LevelsLogic,
	BeltPure = BeltPure,
})

-- Config's numbers (Config itself uses Vector3, so they're copied, as tests/Belt.spec does).
local CFG = {
	Belt = {
		Odds = { Common = 70, Rare = 24, Epic = 5, Legendary = 1 },
		NightRushBoost = 2,
		NightRushMythic = 0.5,
		GoldenSecret = 1,
		GoldenEverySeconds = 1200,
		GoldenSeconds = 120,
		PityArrivals = 8,
		HireDistance = 40,
		RideSeconds = 30,
		Prices = { Common = 100, Rare = 400, Epic = 1500, Legendary = 6000, Mythic = 20000, Secret = 50000 },
		PriceScale = { 1, 1.25, 1.5, 1.75, 2 },
	},
	Nurses = {
		MaxLevel = 5,
		MinSeconds = 3,
		FasterPerLevel = 0.08,
		MakerSeconds = { Common = 14, Rare = 12, Epic = 10, Legendary = 8, Mythic = 7, Secret = 6 },
		HealerSeconds = { Common = 16, Rare = 14, Epic = 12, Legendary = 10, Mythic = 9, Secret = 8 },
		CheerPatience = { Common = 0.1, Rare = 0.15, Epic = 0.2, Legendary = 0.3, Mythic = 0.35, Secret = 0.4 },
		CheerTip = { Common = 0.05, Rare = 0.08, Epic = 0.12, Legendary = 0.18, Mythic = 0.22, Secret = 0.25 },
		CheerPerLevel = 0.03,
	},
}

local function eq(actual: any, expected: any)
	expect(actual).toEqual(expected)
end

T.describe("BeltView (pure)", function()
	test("percent: whole, tenths, hundredths, nothing", function()
		eq(BeltPure.percent(70), "70%")
		eq(BeltPure.percent(39.5), "39.5%")
		eq(BeltPure.percent(0.5), "0.5%")
		eq(BeltPure.percent(0.25), "0.25%")
		eq(BeltPure.percent(1), "1%")
		eq(BeltPure.percent(0), "–")
		eq(BeltPure.percent(-3), "–")
		eq(BeltPure.percent(0 / 0), "–")
		eq(BeltPure.percent("70"), "–")
		eq(BeltPure.percent(0.001), "<0.01%")
	end)
	test("percent prints every row of the plan's odds table", function()
		local night = BeltLogic.odds(CFG, true, false)
		eq(BeltPure.percent(night.Common), "39.5%")
		eq(BeltPure.percent(night.Rare), "48%")
		eq(BeltPure.percent(night.Mythic), "0.5%")
		eq(BeltPure.percent(night.Secret), "–")
		local both = BeltLogic.odds(CFG, true, true)
		eq(BeltPure.percent(both.Common), "38.5%")
		eq(BeltPure.percent(both.Secret), "1%")
	end)
	test("clock: rounds up, never negative, hours", function()
		eq(BeltPure.clock(65.2), "1:06")
		eq(BeltPure.clock(120), "2:00")
		eq(BeltPure.clock(0.1), "0:01")
		eq(BeltPure.clock(-5), "0:00")
		eq(BeltPure.clock(nil), "0:00")
		eq(BeltPure.clock(math.huge), "0:00")
		eq(BeltPure.clock(3723), "1:02:03")
	end)
	test("short: commas, K and M", function()
		eq(BeltPure.short(0), "0")
		eq(BeltPure.short(100), "100")
		eq(BeltPure.short(1500), "1,500")
		eq(BeltPure.short(9999), "9,999")
		eq(BeltPure.short(10000), "10K")
		eq(BeltPure.short(20000), "20K")
		eq(BeltPure.short(112500), "112.5K")
		eq(BeltPure.short(100000), "100K")
		eq(BeltPure.short(1200000), "1.2M")
		eq(BeltPure.short(-4), "0")
		eq(BeltPure.short("x"), "0")
	end)
	test("statText follows Logic/Nurse.stats", function()
		eq(BeltPure.statText("Maker", "Common", 1, CFG), "⏱️14s")
		eq(BeltPure.statText("Healer", "Secret", 1, CFG), "⏱️8s")
		eq(BeltPure.statText("Maker", "Common", 2, CFG), "⏱️12.9s") -- 14 x 0.92 = 12.88
		eq(BeltPure.statText("Cheerer", "Common", 1, CFG), "⏳+10% 💰+5%")
		eq(BeltPure.statText("Cheerer", "Legendary", 3, CFG), "⏳+36% 💰+24%")
		eq(BeltPure.statText("Juggler", "Common", 1, CFG), "")
	end)
	test("every Data/Nurses role has an icon", function()
		for _, id in Nurses.Order do
			local nurse = rawget(Nurses, id)
			assert(BeltPure.ROLE_ICONS[nurse.Role], "no icon for " .. nurse.Role)
			assert(PanelPure.ROLE_NAMES[nurse.Role], "no name for " .. nurse.Role)
		end
	end)
	test("hireState: hired, max, far, poor, ready (in that order)", function()
		eq(BeltPure.hireState(true, nil, CFG, 1e9, 100, 1), "Hired")
		eq(BeltPure.hireState(false, { Level = 5, Copies = 7 }, CFG, 1e9, 100, 1), "Max")
		eq(BeltPure.hireState(false, nil, CFG, 1e9, 100, nil), "Far")
		eq(BeltPure.hireState(false, nil, CFG, 1e9, 100, 39.5), "Far") -- a stud of slack under HireDistance 40
		eq(BeltPure.hireState(false, nil, CFG, 1e9, 100, math.huge), "Far")
		eq(BeltPure.hireState(false, nil, CFG, 99, 100, 10), "Poor")
		eq(BeltPure.hireState(false, nil, CFG, nil, 100, 10), "Poor")
		eq(BeltPure.hireState(false, nil, CFG, 100, 100, 39), "Ready")
		eq(BeltPure.hireState(false, { Level = 4, Copies = 4 }, CFG, 500, 100, 10), "Ready")
	end)
	test("focus: prompt, then tap, then a held card, then the nearest open one", function()
		local list = {
			{ Id = 1, Distance = 5, Open = true },
			{ Id = 2, Distance = 7, Open = true },
			{ Id = 3, Distance = 2, Open = false },
			{ Id = 4, Distance = 50, Open = true },
		}
		eq(BeltPure.focus(list, nil, nil, nil, 30), 1) -- nearest open (3 is hired)
		eq(BeltPure.focus(list, 2, 4, nil, 30), 2) -- the prompt wins
		eq(BeltPure.focus(list, nil, 4, 1, 30), 4) -- then the tap (even out of reach)
		eq(BeltPure.focus(list, nil, 99, nil, 30), 1) -- a tap on a rider that's gone is ignored
		eq(BeltPure.focus(list, nil, nil, 2, 30), 2) -- held: 7 is within 3 of 5
		eq(
			BeltPure.focus(
				{ { Id = 1, Distance = 2, Open = true }, { Id = 2, Distance = 6, Open = true } },
				nil,
				nil,
				2,
				30
			),
			1
		)
		eq(BeltPure.focus(list, nil, nil, 3, 30), 1) -- a held card that's no longer open lets go
		eq(BeltPure.focus({ { Id = 4, Distance = 50, Open = true } }, nil, nil, nil, 30), nil)
		eq(BeltPure.focus({}, nil, nil, nil, 30), nil)
	end)
	test("nightRush: NightRush wins, IsNight until it's set", function()
		eq(BeltPure.nightRush(true, false), true)
		eq(BeltPure.nightRush(false, true), false)
		eq(BeltPure.nightRush(nil, true), true)
		eq(BeltPure.nightRush(nil, nil), false)
	end)
	test("mode: Golden over Night over Day", function()
		eq(BeltPure.mode(true, true), "Golden")
		eq(BeltPure.mode(false, true), "Night")
		eq(BeltPure.mode(false, false), "Day")
	end)
	test("quiet: before the first snapshot and during the tutorial", function()
		eq(BeltPure.quiet(0), true)
		eq(BeltPure.quiet(1), true)
		eq(BeltPure.quiet(8), true)
		eq(BeltPure.quiet(9), false)
		eq(BeltPure.quiet(nil), true)
	end)
	test("oddsRows: every rarity in order, each column sums to 100, prices by level", function()
		local rows = BeltPure.oddsRows(CFG, Rarities.Order, false, 3)
		eq(#rows, 6)
		local sums = { Day = 0, Night = 0, Golden = 0 }
		for index, row in rows do
			eq(row.Rarity, Rarities.Order[index])
			sums.Day += row.Day
			sums.Night += row.Night
			sums.Golden += row.Golden
		end
		eq(math.abs(sums.Day - 100) < 1e-9, true)
		eq(math.abs(sums.Night - 100) < 1e-9, true)
		eq(math.abs(sums.Golden - 100) < 1e-9, true)
		eq(rows[1].Price, 150) -- Common 100 x 1.5 at Lv 3
		eq(rows[6].Price, 75000)
		eq(rows[5].Day, 0) -- Mythic: Night Rush only
		eq(rows[5].Night, 0.5)
		eq(rows[6].Golden, 1) -- Secret in Golden Hour
		local nightRows = BeltPure.oddsRows(CFG, Rarities.Order, true, 1)
		eq(nightRows[1].Golden, 38.5) -- Golden Hour at night carries the Night Rush boost
	end)
end)

T.describe("NursePanel (pure)", function()
	test("mark: Hired, Seen, Unseen (junk too)", function()
		local index = { PuffPup = "Hired", MintMouse = "Seen", BeanBear = "Maybe" }
		eq(PanelPure.mark(index, "PuffPup"), "Hired")
		eq(PanelPure.mark(index, "MintMouse"), "Seen")
		eq(PanelPure.mark(index, "BeanBear"), "Unseen")
		eq(PanelPure.mark(index, "DewDuck"), "Unseen")
		eq(PanelPure.mark(nil, "PuffPup"), "Unseen")
	end)
	test("noteNews: Seen and Hired only, Seen never replaces Hired", function()
		local fresh = {}
		eq(PanelPure.noteNews(fresh, { Kind = "Seen", NurseId = "PuffPup" }), true)
		eq(PanelPure.noteNews(fresh, { Kind = "Seen", NurseId = "PuffPup" }), false)
		eq(PanelPure.noteNews(fresh, { Kind = "Hired", NurseId = "PuffPup", Level = 1, New = true }), true)
		eq(PanelPure.noteNews(fresh, { Kind = "Seen", NurseId = "PuffPup" }), false)
		eq(fresh.PuffPup, "Hired")
		eq(PanelPure.noteNews(fresh, { Kind = "Equipped", NurseId = "MintMouse", On = true }), false)
		eq(PanelPure.noteNews(fresh, { Kind = "Seen", NurseId = 5 }), false)
		eq(PanelPure.noteNews(fresh, "junk"), false)
		eq(PanelPure.count(fresh), 1)
		eq(PanelPure.count({}), 0)
	end)
	test("levelText", function()
		eq(PanelPure.levelText({ Level = 2, Copies = 2 }, 5), "Lv 2")
		eq(PanelPure.levelText({ Level = 5, Copies = 9 }, 5), "Lv 5 MAX")
		eq(PanelPure.levelText(nil, 5), "Lv 1")
	end)
	test("slotChips: slots at your level, then the next level's lock", function()
		eq(PanelPure.slotChips({}, 1, Levels), { { Kind = "Empty" }, { Kind = "Locked", Level = 2 } })
		eq(PanelPure.slotChips({ "PuffPup" }, 1, Levels), {
			{ Kind = "Filled", NurseId = "PuffPup" },
			{ Kind = "Locked", Level = 2 },
		})
		eq(PanelPure.slotChips({ "PuffPup" }, 3, Levels), {
			{ Kind = "Filled", NurseId = "PuffPup" },
			{ Kind = "Empty" },
			{ Kind = "Empty" },
			{ Kind = "Locked", Level = 4 },
		})
		local top = PanelPure.slotChips({ "A", "B", "C", "D", "E" }, 5, Levels)
		eq(#top, 5) -- no lock at the top
		eq(top[5], { Kind = "Filled", NurseId = "E" })
		-- An over-full list (an old save) shows only the slots there are.
		eq(#PanelPure.slotChips({ "A", "B", "C" }, 1, Levels), 2)
		-- Junk levels clamp like the server's.
		eq(PanelPure.slotChips({}, 0, Levels)[2], { Kind = "Locked", Level = 2 })
		eq(#PanelPure.slotChips({}, 99, Levels), 5)
	end)
	test("rewardText for every rarity's journal reward", function()
		eq(PanelPure.rewardText(rawget(Rarities, "Common"), "🩹"), "💰300 + 🩹")
		eq(PanelPure.rewardText(rawget(Rarities, "Secret"), "🏆"), "💰30K + 🏆")
		eq(PanelPure.rewardText(rawget(Rarities, "Rare"), nil), "💰1,000")
		eq(PanelPure.rewardText(nil, nil), "💰0")
	end)
	test("hint: where to find an unseen nurse; your price for a seen one", function()
		eq(PanelPure.hint("Unseen", rawget(Rarities, "Common"), 100), "👀 On the belt")
		eq(PanelPure.hint("Unseen", rawget(Rarities, "Mythic"), 100), "🌙 Night Rush")
		eq(PanelPure.hint("Unseen", rawget(Rarities, "Secret"), 100), "👑 Golden Hour")
		eq(PanelPure.hint("Seen", rawget(Rarities, "Epic"), 2250), "💰2,250")
	end)
	test("eventNote", function()
		eq(PanelPure.eventNote(rawget(Rarities, "Mythic")), "🌙 Night Rush only")
		eq(PanelPure.eventNote(rawget(Rarities, "Secret")), "👑 Golden Hour only")
		eq(PanelPure.eventNote(rawget(Rarities, "Legendary")), "")
	end)
	test("firstPage: the lowest rarity with news, else where you were, else the first", function()
		eq(PanelPure.firstPage({ JamJelly = "Seen", AuroraOtter = "Hired" }, Nurses, Rarities.Order, "Common"), "Epic")
		eq(PanelPure.firstPage({}, Nurses, Rarities.Order, "Rare"), "Rare")
		eq(PanelPure.firstPage({}, Nurses, Rarities.Order, "Nope"), "Common")
		eq(PanelPure.firstPage({}, Nurses, Rarities.Order, nil), "Common")
		eq(PanelPure.firstPage({ Unknown = "Seen" }, Nurses, Rarities.Order, nil), "Common")
	end)
	test("the journal's completion % matches Logic/Nurse.journal", function()
		local index = {}
		for _, id in Nurses.Order do
			local nurse = rawget(Nurses, id)
			if nurse.Rarity == "Common" then
				index[id] = "Hired"
			end
		end
		local journal = NurseLogic.journal(index, Nurses, Rarities)
		eq(journal.Percent, 31) -- 5 of 16
		eq(journal.Groups.Common.Complete, true)
	end)
end)
