--!nocheck
-- The Nurses client's pure helpers (depth update T4; Progression v2 T5): the PURE-BEGIN..PURE-END blocks of
-- UI/BeltView and UI/NursePanel, loaded on their own (the rest of those modules needs Roblox) and tested against the
-- real Logic/Belt, Logic/Nurse, Logic/Jobs, Logic/Abilities, Logic/Levels, Logic/Tutorial, the shipped Config
-- (tests/config) and Data/Nurses, Rarities, Levels, Jobs, Departments and Abilities. Run from game/ with the rest:
--   lune run tests/run

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
local JobsLogic = require("../src/shared/Logic/Jobs")
local AbilitiesLogic = require("../src/shared/Logic/Abilities")
local Jobs = require("../src/shared/Data/Jobs")
local Departments = require("../src/shared/Data/Departments")
local Abilities = require("../src/shared/Data/Abilities")

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
	BeltPure = BeltPure,
	NurseLogic = NurseLogic,
	JobsLogic = JobsLogic,
	AbilitiesLogic = AbilitiesLogic,
})

-- Config's numbers: the belt is the real Config's (tests/config.luau), so the odds the popup shows are tested on what
-- ships; the nurse numbers are copied.
local Config = require("./config")
local CFG = {
	Belt = Config.Belt,
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
	test("percent prints every row of the shipped odds table (memory-017)", function()
		local day = BeltLogic.odds(CFG, false, false)
		eq(BeltPure.percent(day.Common), "75%")
		eq(BeltPure.percent(day.Rare), "20%")
		eq(BeltPure.percent(day.Epic), "4.5%")
		eq(BeltPure.percent(day.Legendary), "0.5%")
		eq(BeltPure.percent(day.Mythic), "–")
		local night = BeltLogic.odds(CFG, true, false)
		eq(BeltPure.percent(night.Common), "49.5%")
		eq(BeltPure.percent(night.Rare), "40%")
		eq(BeltPure.percent(night.Mythic), "0.5%")
		eq(BeltPure.percent(night.Secret), "–")
		local both = BeltLogic.odds(CFG, true, true)
		eq(BeltPure.percent(both.Common), "48.5%")
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
	test("hireState: hired, max, level, far, poor, ready (in that order)", function()
		-- Epic and up need hospital Lv 3 (Config.Belt.MinLevel): "Level" before distance and cash
		eq(BeltPure.hireState(false, nil, CFG, 1e9, 100, 1, "Epic", 2), "Level")
		eq(BeltPure.hireState(false, nil, CFG, 1e9, 100, 99, "Legendary", 1), "Level")
		eq(BeltPure.hireState(false, nil, CFG, 1e9, 100, 1, "Epic", 3), "Ready")
		eq(BeltPure.hireState(false, nil, CFG, 1e9, 100, 1, "Rare", 1), "Ready")
		eq(BeltPure.hireState(true, nil, CFG, 1e9, 100, 1, "Epic", 1), "Hired")
		eq(BeltPure.hireState(false, { Level = 5, Copies = 7 }, CFG, 1e9, 100, 1, "Epic", 1), "Max")
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
		eq(rows[1].Price, 120) -- Common 100 x 1.2 at Lv 3
		eq(rows[6].Price, 60000)
		-- the popup shows exactly the belt's odds (memory-017): 75 / 20 / 4.5 / 0.5 by day
		eq({ rows[1].Day, rows[2].Day, rows[3].Day, rows[4].Day }, { 75, 20, 4.5, 0.5 })
		eq({ rows[1].Night, rows[2].Night, rows[3].Night, rows[4].Night }, { 49.5, 40, 9, 1 })
		eq(rows[5].Day, 0) -- Mythic: Night Rush only
		eq(rows[5].Night, 0.5)
		eq(rows[6].Day, 0) -- Secret: Golden Hour only
		eq(rows[6].Golden, 1)
		for index, row in rows do
			eq(row.Day, BeltLogic.odds(Config, false, false)[Rarities.Order[index]])
			eq(row.MinLevel, if index >= 3 then 3 else 1)
		end
		local nightRows = BeltPure.oddsRows(CFG, Rarities.Order, true, 1)
		eq(nightRows[1].Golden, 48.5) -- Golden Hour at night carries the Night Rush boost
	end)
	test("priceText: your price, or the hospital level a rarity needs", function()
		eq(BeltPure.priceText(1800, 3, 3), "💰1,800")
		eq(BeltPure.priceText(1800, 3, 2), "🏥 Lv 3")
		eq(BeltPure.priceText(100, 1, 1), "💰100")
	end)
end)

-- A Snapshot with only what the panel reads.
local function snap(fields: { [string]: any }?): any
	local f = fields or {}
	local rebirth = f.Rebirth or {}
	return {
		Level = f.Level or 1,
		Nurses = f.Nurses or {},
		NurseIndex = f.NurseIndex or {},
		Rebirth = {
			Count = rebirth.Count or 0,
			Points = 0,
			Tree = {},
			Perks = {},
			Offer = {},
			Theme = "",
			Pending = rebirth.Pending or {},
			Told = false,
		},
	}
end

local function own(ids: { string }, job: string?): { [string]: any }
	local out = {}
	for _, id in ids do
		out[id] = { Level = 1, XP = 0, Copies = 1, Job = job or "" }
	end
	return out
end

local STATION_ICONS =
	{ Remedy = "💊", Plaster = "🩹", Ice = "🧊", Bandage = "🧻", Bath = "🛁", Cocoa = "☕" }

local function assertWords(text: string, where: string)
	assert(PanelPure.words(text) <= 6, where .. ": more than 6 words: " .. text)
end

local function isKnown(id: string): boolean
	return rawget(Nurses, id) ~= nil
end

T.describe("NursePanel (pure): the Journal", function()
	test("mark: Hired, Seen, Unseen (junk too)", function()
		local index = { PuffPup = "Hired", MintMouse = "Seen", BeanBear = "Maybe" }
		eq(PanelPure.mark(index, "PuffPup"), "Hired")
		eq(PanelPure.mark(index, "MintMouse"), "Seen")
		eq(PanelPure.mark(index, "BeanBear"), "Unseen")
		eq(PanelPure.mark(index, "DewDuck"), "Unseen")
		eq(PanelPure.mark(nil, "PuffPup"), "Unseen")
	end)
	test("noteNews: Seen, Hired and Level; a stronger kind replaces a weaker one, never back", function()
		local fresh = {}
		eq(PanelPure.noteNews(fresh, { Kind = "Seen", NurseId = "PuffPup" }), true)
		eq(PanelPure.noteNews(fresh, { Kind = "Seen", NurseId = "PuffPup" }), false)
		eq(PanelPure.noteNews(fresh, { Kind = "Hired", NurseId = "PuffPup", Level = 1, New = true }), true)
		eq(PanelPure.noteNews(fresh, { Kind = "Seen", NurseId = "PuffPup" }), false)
		eq(PanelPure.noteNews(fresh, { Kind = "Level", NurseId = "PuffPup", Level = 2 }), false)
		eq(fresh.PuffPup, "Hired")
		eq(PanelPure.noteNews(fresh, { Kind = "Level", NurseId = "MintMouse", Level = 3 }), true)
		eq(PanelPure.noteNews(fresh, { Kind = "Level", NurseId = "MintMouse", Level = 4 }), false)
		eq(PanelPure.noteNews(fresh, { Kind = "Hired", NurseId = "MintMouse", Level = 4 }), true)
		eq(fresh.MintMouse, "Hired")
		for _, kind in { "Job", "Sold", "Bought", "Gone", "Listed", "Resting", "Equipped" } do
			eq(PanelPure.noteNews(fresh, { Kind = kind, NurseId = "BeanBear" }), false)
		end
		eq(PanelPure.noteNews(fresh, { Kind = "Seen", NurseId = 5 }), false)
		eq(PanelPure.noteNews(fresh, "junk"), false)
		eq(PanelPure.count(fresh), 2)
		eq(PanelPure.count({}), 0)
	end)
	test("levelText at the level cap", function()
		eq(PanelPure.levelText({ Level = 2, Copies = 2 }, 10), "Lv 2")
		eq(PanelPure.levelText({ Level = 10, Copies = 9 }, 10), "Lv 10 MAX")
		eq(PanelPure.levelText({ Level = 10 }, 15), "Lv 10")
		eq(PanelPure.levelText(nil, 10), "Lv 1")
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
	test("openView: asked for, else journal news, else 🏢 news, else level news, else where you were", function()
		local order = Rarities.Order
		eq(PanelPure.openView("Team", {}, Nurses, order, nil), "Team")
		eq(PanelPure.openView("Branch", {}, Nurses, order, nil), "Branch")
		eq(PanelPure.openView("Rare", { PuffPup = "Seen" }, Nurses, order, nil), "Rare")
		eq(PanelPure.openView(nil, { JamJelly = "Seen", AuroraOtter = "Hired" }, Nurses, order, "Common"), "Epic")
		eq(PanelPure.openView(nil, { FounderFennec = "Hired" }, Nurses, order, "Common"), "Branch")
		eq(PanelPure.openView(nil, { PuffPup = "Level" }, Nurses, order, "Common"), "Team")
		eq(PanelPure.openView(nil, { PuffPup = "Level", MintMouse = "Seen" }, Nurses, order, nil), "Common")
		-- FounderFennec is Legendary but never opens the Legendary page
		eq(PanelPure.openView(nil, { FounderFennec = "Seen" }, Nurses, order, nil), "Branch")
		eq(PanelPure.openView(nil, {}, Nurses, order, "Rare"), "Rare")
		eq(PanelPure.openView(nil, {}, Nurses, order, "Team"), "Team")
		eq(PanelPure.openView(nil, {}, Nurses, order, "Nope"), "Common")
		eq(PanelPure.openView(nil, {}, Nurses, order, nil), "Common")
		eq(PanelPure.openView(nil, { Unknown = "Seen", Order = "Level" }, Nurses, order, nil), "Common")
	end)
	test("the journal's completion % leaves the rebirth-only nurse out", function()
		local index = { FounderFennec = "Hired" }
		for _, id in Nurses.Order do
			local nurse = rawget(Nurses, id)
			if nurse.Rarity == "Common" then
				index[id] = "Hired"
			end
		end
		local journal = NurseLogic.journal(index, Nurses, Rarities)
		eq(journal.Percent, 31) -- 5 of 16
		eq(journal.Groups.Common.Complete, true)
		eq(PanelPure.branchNurses(Nurses), { "FounderFennec" })
	end)
	test("the 🏢 page's cards: Owned, Pending (Claim), Locked", function()
		eq(PanelPure.branchCard("FounderFennec", snap()), "Locked")
		eq(PanelPure.branchCard("FounderFennec", snap({ Rebirth = { Pending = { "FounderFennec" } } })), "Pending")
		eq(PanelPure.branchCard("FounderFennec", snap({ Nurses = own({ "FounderFennec" }) })), "Owned")
	end)
	-- The look overhaul (T7): one tab column (Modal.tabs) and the header's one meta chip.
	test(
		"the tab column: 👩‍⚕️ Team first, every rarity in order, then 🏢 only when there are branch nurses",
		function()
			local order = Rarities.Order
			local ids = PanelPure.tabIds(order, #PanelPure.branchNurses(Nurses) > 0)
			eq(ids[1], "Team")
			for index, rarity in order do
				eq(ids[index + 1], rarity)
			end
			eq(ids[#ids], "Branch")
			eq(#ids, #order + 2)
			eq(PanelPure.tabIds({ "Common", "Rare" }, false), { "Team", "Common", "Rare" })
			-- every view openView can pick is a tab (so Modal.tabs' select always has a page to show)
			for _, tab in { "Team", "Branch", "Rare", "Nope" } do
				eq(table.find(ids, PanelPure.openView(tab, {}, Nurses, order, nil)) ~= nil, true)
			end
			eq(table.find(ids, PanelPure.openView(nil, { PuffPup = "Level" }, Nurses, order, nil)) ~= nil, true)
		end
	)
	test("the meta chip: the journal's completion, whole percent", function()
		eq(PanelPure.metaText(0), "📔 0%")
		eq(PanelPure.metaText(31), "📔 31%")
		eq(PanelPure.metaText(100), "📔 100%")
		eq(PanelPure.metaText(nil), "📔 0%")
		eq(PanelPure.metaText(0 / 0), "📔 0%")
		local journal = NurseLogic.journal({}, Nurses, Rarities)
		eq(PanelPure.metaText(journal.Percent), "📔 0%")
		assertWords(PanelPure.metaText(journal.Percent), "meta chip")
	end)
end)

T.describe("NursePanel (pure): the Team page", function()
	test("roster: 0/3 fresh, then working by NurseId, resting the rest, unknown ids ignored", function()
		local fresh = PanelPure.roster({}, 0, Config, Nurses)
		eq(fresh.Text, "👩‍⚕️ 0/3")
		eq(fresh.RestText, "")
		eq(fresh.Full, false)
		-- an Update 1 save: 5 nurses, 2 resting (Logic/Schema put them there)
		local nurses = own({ "PuffPup", "MintMouse", "BeanBear" })
		nurses.DewDuck = { Level = 3, XP = 0, Copies = 3, Job = "Rest" }
		nurses.CuddleCub = { Level = 1, XP = 0, Copies = 1, Job = "Rest" }
		nurses.Ghost = { Level = 1, XP = 0, Copies = 1, Job = "" }
		local legacy = PanelPure.roster(nurses, 0, Config, Nurses)
		eq(legacy.Working, { "BeanBear", "MintMouse", "PuffPup" })
		eq(legacy.Resting, { "CuddleCub", "DewDuck" })
		eq(legacy.Text, "👩‍⚕️ 5/3")
		eq(legacy.RestText, "💤 2 resting")
		eq(legacy.Full, true)
		-- the same rule as the server: Logic/Nurse.canAdd refuses a new nurse at owned >= cap
		local canAdd, message =
			NurseLogic.canAdd({ Nurses = nurses, Rebirth = { Count = 0 } }, "JamJelly", Config, isKnown)
		eq(canAdd, false)
		eq(message, "Roster full: sell or list one")
		eq(PanelPure.roster({}, 2, Config, Nurses).Cap, 5)
		eq(PanelPure.roster({}, 9, Config, Nurses).Cap, 8)
	end)
	test("team chips: 2 and 3+ working specialists of a department, 'Any' counting for each", function()
		local function chips(ids: { string }): { string }
			local out = {}
			for _, chip in PanelPure.teamChips(ids, Nurses, Departments, STATION_ICONS) do
				table.insert(out, chip.Text)
			end
			return out
		end
		eq(chips({ "PuffPup" }), {})
		eq(chips({ "PuffPup", "HumHamster" }), { "🛎️ ×2  +10% 💰" })
		eq(chips({ "PuffPup", "HumHamster", "StarlightLamb" }), { "🛎️ ×3  +20% 💰" })
		eq(chips({ "DewDuck", "PebblePenguin", "JamJelly" }), { "🛁 ×3  🛁 40% faster" })
		eq(chips({ "MintMouse", "SunnySnail" }), { "🛏️ ×2  rest 25% faster" })
		eq(chips({ "CuddleCub", "ToffeeFox" }), { "🚑 ×2  🚑 wait +25%" })
		eq(chips({ "BeanBear", "BerryBat" }), { "💊 ×2  📦 20% faster" })
		-- FounderFennec ("Any") makes a pair with anyone, and alone with none
		eq(chips({ "FounderFennec" }), {})
		eq(chips({ "FounderFennec", "MintMouse" }), { "🛏️ ×2  rest 25% faster" })
		-- the same counts as the server's Logic/Jobs.teams
		local counts = JobsLogic.teams({ "Reception", "Reception", "Hydro" }, Departments)
		eq(counts.Reception, 2)
		eq(counts.Hydro, 1)
	end)
	test("specialty, ability and boost texts", function()
		eq(PanelPure.specialtyText("Reception", Departments), "🛎️ Reception")
		eq(PanelPure.specialtyText("AE", Departments), "🚑 A&E")
		eq(PanelPure.specialtyText("Any", Departments), "🌟 Any")
		eq(PanelPure.specialtyText("Nope", Departments), "")
		eq(PanelPure.abilityText("CalmSong", 1, Abilities, Config), "🎵 Calm Song")
		eq(PanelPure.abilityText("CalmSong", 5, Abilities, Config), "🎵 Calm Song ★")
		eq(PanelPure.abilityText("CalmSong", 10, Abilities, Config), "🎵 Calm Song ★★")
		eq(PanelPure.abilityText("Nope", 1, Abilities, Config), "")
		eq(PanelPure.boostText(Config), "⭐ +40% at its specialty")
	end)
	test("the XP bar: toward the next level, full and MAX at the cap", function()
		local start = PanelPure.xp({ Level = 1, XP = 5 }, 10)
		eq(start.Need, 20)
		eq(start.Fraction, 0.25)
		eq(PanelPure.xpText(start), "5/20")
		local top = PanelPure.xp({ Level = 10, XP = 0 }, 10)
		eq(top.Max, true)
		eq(top.Fraction, 1)
		eq(PanelPure.xpText(top), "⭐ MAX")
		eq(PanelPure.xp({ Level = 10, XP = 7 }, 15).Max, false) -- R3 lifts the cap
		eq(PanelPure.xpText(PanelPure.xp("junk", 10)), "0/20")
		eq(PanelPure.xp({ Level = 4, XP = 999 }, 10).Fraction, 1) -- clamped, never past full
		for level = 1, 14 do
			eq(PanelPure.xp({ Level = level, XP = 0 }, 15).Need, NurseLogic.xpToNext(level))
		end
	end)
	test("the ability ring: ready when no time is known or it has passed, else the part recharged", function()
		eq(PanelPure.ringFraction(nil, 60, 100), 1)
		eq(PanelPure.ringFraction(0 / 0, 60, 100), 1)
		eq(PanelPure.ringFraction(90, 60, 100), 1)
		eq(PanelPure.ringFraction(130, 60, 100), 0.5)
		eq(PanelPure.ringFraction(160, 60, 100), 0)
		eq(PanelPure.ringFraction(130, 0, 100), 0)
		eq(PanelPure.ringFraction(1000, 60, 100), 0)
	end)
	test("boosted: the job's department is the nurse's specialty (a Maker's: any department with a station)", function()
		local stations = Departments.Stations
		eq(PanelPure.boosted("Healer", "Reception", Jobs, stations), true)
		eq(PanelPure.boosted("Healer", "Wards", Jobs, stations), false)
		eq(PanelPure.boosted("Porter", "Wards", Jobs, stations), true)
		eq(PanelPure.boosted("Medic", "AE", Jobs, stations), true)
		eq(PanelPure.boosted("Maker", "Hydro", Jobs, stations), true)
		eq(PanelPure.boosted("Maker", "Pharmacy", Jobs, stations), true)
		eq(PanelPure.boosted("Maker", "Wards", Jobs, stations), false)
		eq(PanelPure.boosted("Maker", "AE", Jobs, stations), false)
		for _, jobId in Jobs.Order do
			eq(PanelPure.boosted(jobId, "Any", Jobs, stations), true)
		end
		eq(PanelPure.boosted("Nope", "Reception", Jobs, stations), false)
	end)
end)

T.describe("NursePanel (pure): the job picker's states", function()
	local stations = Departments.Stations
	local function states(options: { any }): { string }
		local out = {}
		for _, option in options do
			table.insert(out, option.Id .. ":" .. option.State .. ":" .. option.Caption)
		end
		return out
	end
	local puff = rawget(Nurses, "PuffPup") -- a Maker, Reception specialty
	test("a working nurse at Lv 1: its job ✅, the Lv 2 jobs closed, ⭐ where its specialty helps", function()
		local entry = { Level = 1, XP = 0, Copies = 1, Job = "" }
		local options = PanelPure.jobOptions(entry, puff, 1, Jobs, false, 1, 3, stations)
		eq(states(options), {
			"Maker:Current:✅",
			"Healer:Open:",
			"Cheerer:Open:",
			"Receptionist:Open:",
			"Porter:Closed:🏥 Lv 2",
			"Medic:Closed:🏥 Lv 2",
		})
		local boosts = {}
		for _, option in options do
			table.insert(boosts, option.Boost)
		end
		-- a Reception specialist: no station is Reception's since the Real Clinic, so Maker has no ⭐
		eq(boosts, { false, true, true, true, false, false })
	end)
	test("a Porter after a rebirth works its role until Lv 2 (nothing is lost)", function()
		local porter = { Level = 4, XP = 0, Copies = 1, Job = "Porter" }
		eq(states(PanelPure.jobOptions(porter, puff, 1, Jobs, false, 1, 3, stations))[1], "Maker:Current:✅")
		eq(PanelPure.jobButton(porter, puff, 1, Jobs, false), "🧪 Maker (↕️ at 🏥 Lv 2)")
		local atTwo = states(PanelPure.jobOptions(porter, puff, 2, Jobs, false, 1, 3, stations))
		eq(atTwo[1], "Maker:Open:")
		eq(atTwo[5], "Porter:Current:✅")
		eq(PanelPure.jobButton(porter, puff, 2, Jobs, false), "↕️ Porter")
	end)
	test("a resting nurse: 💤 while the roster is full, open jobs when it has room, never a ✅", function()
		local entry = { Level = 3, XP = 0, Copies = 3, Job = "Rest" }
		eq(states(PanelPure.jobOptions(entry, puff, 2, Jobs, true, 3, 3, stations)), {
			"Maker:Full:💤",
			"Healer:Full:💤",
			"Cheerer:Full:💤",
			"Receptionist:Full:💤",
			"Porter:Full:💤",
			"Medic:Full:💤",
		})
		eq(states(PanelPure.jobOptions(entry, puff, 1, Jobs, true, 2, 3, stations)), {
			"Maker:Open:",
			"Healer:Open:",
			"Cheerer:Open:",
			"Receptionist:Open:",
			"Porter:Closed:🏥 Lv 2",
			"Medic:Closed:🏥 Lv 2",
		})
		eq(PanelPure.jobButton(entry, puff, 1, Jobs, true), "💤 Resting")
	end)
	test("what a refused row says is what the server says (Logic/Nurse.setJob)", function()
		local nurses = own({ "PuffPup", "MintMouse", "BeanBear" })
		nurses.DewDuck = { Level = 1, XP = 0, Copies = 1, Job = "Rest" }
		local closed = PanelPure.jobOptions(nurses.PuffPup, puff, 1, Jobs, false, 3, 3, stations)[5]
		local _, serverClosed = NurseLogic.setJob(nurses, "PuffPup", "Porter", 1, 3, Jobs, "Maker")
		eq(PanelPure.jobMessage(closed), serverClosed)
		local dew = rawget(Nurses, "DewDuck")
		local full = PanelPure.jobOptions(nurses.DewDuck, dew, 1, Jobs, true, 3, 3, stations)[2]
		local _, serverFull = NurseLogic.setJob(nurses, "DewDuck", "Healer", 1, 3, Jobs, "Healer")
		eq(PanelPure.jobMessage(full), serverFull)
		eq(PanelPure.jobMessage({ State = "Open", Caption = "" }), nil)
		eq(PanelPure.jobMessage({ State = "Current", Caption = "✅" }), nil)
	end)
	test("the job button names the job it works", function()
		eq(PanelPure.jobButton({ Job = "" }, puff, 1, Jobs, false), "🧪 Maker")
		eq(PanelPure.jobButton({ Job = "Healer" }, puff, 1, Jobs, false), "🩺 Healer")
		eq(PanelPure.jobButton({ Job = "Nope" }, puff, 1, Jobs, false), "🧪 Maker")
	end)
end)

T.describe("NursePanel (pure): selling, listing and gifts", function()
	test("actions: Sell and List, 🏷️ Listed on the Market, and a rebirth-only nurse stays", function()
		eq(PanelPure.actions("PuffPup", Nurses, {}), { Sell = true, List = true, Listed = false, Stays = false })
		eq(
			PanelPure.actions("PuffPup", Nurses, { PuffPup = true }),
			{ Sell = true, List = true, Listed = true, Stays = false }
		)
		eq(PanelPure.actions("FounderFennec", Nurses, {}), { Sell = false, List = false, Listed = false, Stays = true })
		eq(PanelPure.actions("PuffPup", Nurses, nil).Listed, false)
	end)
	test("listedSet: only your listings", function()
		local view = {
			Listings = {
				{
					Id = 1,
					Seller = 7,
					SellerName = "Me",
					NurseId = "PuffPup",
					Rarity = "Common",
					Level = 2,
					Price = 100,
				},
				{
					Id = 2,
					Seller = 9,
					SellerName = "Pal",
					NurseId = "MintMouse",
					Rarity = "Common",
					Level = 1,
					Price = 90,
				},
				{
					Id = 3,
					Seller = 7,
					SellerName = "Me",
					NurseId = "JamJelly",
					Rarity = "Epic",
					Level = 1,
					Price = 900,
				},
				"junk",
			},
			FeePercent = 10,
			MaxPerSeller = 3,
		}
		eq(PanelPure.listedSet(view, 7), { PuffPup = true, JamJelly = true })
		eq(PanelPure.listedSet(view, 1), {})
		eq(PanelPure.listedSet(nil, 7), {})
		eq(PanelPure.listedSet({ Listings = "x" }, 7), {})
	end)
	test("the gift: a waiting rebirth-only nurse, and whether the roster has room", function()
		eq(PanelPure.gift(snap(), Nurses, Config), nil)
		local waiting = snap({ Rebirth = { Count = 5, Pending = { "FounderFennec" } } })
		eq(PanelPure.gift(waiting, Nurses, Config), { NurseId = "FounderFennec", Room = true })
		local eight = own({
			"PuffPup",
			"MintMouse",
			"BeanBear",
			"DewDuck",
			"HumHamster",
			"CuddleCub",
			"PebblePenguin",
			"BerryBat",
		})
		local full = snap({ Nurses = eight, Rebirth = { Count = 5, Pending = { "FounderFennec" } } })
		eq(PanelPure.gift(full, Nurses, Config), { NurseId = "FounderFennec", Room = false })
	end)
	test("≤ 6 words on every label: fixed texts, rosters, chips, jobs, abilities, specialties", function()
		for key, text in PanelPure.TEXT do
			assertWords(text, "TEXT." .. key)
		end
		assertWords(PanelPure.boostText(Config), "boost")
		for _, count in { 0, 3, 8, 16 } do
			local ids = {}
			for index = 1, count do
				table.insert(ids, Nurses.Order[index])
			end
			local roster = PanelPure.roster(own(ids, "Rest"), 0, Config, Nurses)
			assertWords(roster.Text, "roster")
			assertWords(roster.RestText, "resting")
		end
		for _, deptId in Departments.Order do
			local dept = rawget(Departments, deptId)
			for _, effect in { dept.Team2, dept.Team3 } do
				assertWords(dept.Icon .. " ×3  " .. PanelPure.effectText(effect, STATION_ICONS), "team " .. deptId)
			end
			assertWords(PanelPure.specialtyText(deptId, Departments), "specialty")
		end
		for _, nurseId in Nurses.Order do
			local nurse = rawget(Nurses, nurseId)
			for _, level in { 1, 2, 5 } do
				for _, jobId in Jobs.Order do
					local entry = { Level = 1, XP = 0, Copies = 1, Job = jobId }
					assertWords(PanelPure.jobButton(entry, nurse, level, Jobs, false), "job button")
					for _, option in PanelPure.jobOptions(entry, nurse, level, Jobs, false, 1, 3, Departments.Stations) do
						assertWords(option.Name .. " ⭐", "job name")
						assertWords(option.Text, "job text")
						assertWords(option.Caption, "job caption")
						assertWords(PanelPure.jobMessage(option) or "", "job message")
					end
				end
			end
			for _, level in { 1, 5, 10, 15 } do
				assertWords(PanelPure.abilityText(nurse.Ability, level, Abilities, Config), "ability")
			end
		end
	end)
end)
