--!nocheck
-- T1 of the calm UI build (docs/plan/2026-11-17-ui-direction.md §4 row 4, §5 "T1 Nurses"; Joshua's rulings
-- memory-20261117-006 "simple, especially at the start" and -007: one main button per Team card, Sell and List behind
-- "More" once you own 2 nurses, titles in words, navy progress bars). Run from game/ with the rest:  lune run tests/run
--   · the ratchet: UI/NursePanel.luau has NO calm-rule fault left (TitleEmoji, LabelEmoji, LeadEmoji, TypedEmoji,
--     SpaceLiteral, StrokeBudget all 0; the two outlines left, the nurse cap and the stamp over the 3D world, carry
--     the allow comment), and the old hard rules still hold
--   · THE TEAM CARD (Pure.teamCard): exactly one filled button (the job), More only from 2 nurses and never for a
--     rebirth-only nurse, at most 2 Soft facts with at most one emoji each, the bar only once the first XP is earned,
--     the ability only once it can differ, 💤 as the State badge of a resting nurse whose button reads "Pick a job"
--   · R0, "a fresh save is simple" (Pure.visible): a Lv 1 save sees the Team tab alone (no Journal tab, no Agency or
--     Market link); a rich save still sees everything, so nothing is lost
--   · the source draws what the pure block decides: Kit.card, Kit.bar, Kit.more, Kit.setState, Kit.artTile

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test
local UiRules = require("./uirules")

local BeltLogic = require("../src/shared/Logic/Belt")
local NurseLogic = require("../src/shared/Logic/Nurse")
local TutorialLogic = require("../src/shared/Logic/Tutorial")
local JobsLogic = require("../src/shared/Logic/Jobs")
local AbilitiesLogic = require("../src/shared/Logic/Abilities")
local Nurses = require("../src/shared/Data/Nurses")
local Rarities = require("../src/shared/Data/Rarities")
local Jobs = require("../src/shared/Data/Jobs")
local Departments = require("../src/shared/Data/Departments")
local Abilities = require("../src/shared/Data/Abilities")
local Config = require("./config")

local PATH = "src/client/UI/NursePanel.luau"

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

local Icons = UiRules.Icons
local BeltPure = pureBlock("src/client/UI/BeltView.luau", {
	BeltLogic = BeltLogic,
	NurseLogic = NurseLogic,
	TutorialLogic = TutorialLogic,
})
local Pure = pureBlock(PATH, {
	BeltPure = BeltPure,
	Icons = Icons,
	NurseLogic = NurseLogic,
	JobsLogic = JobsLogic,
	AbilitiesLogic = AbilitiesLogic,
})

local FILLED = { Primary = true, Collect = true, Secondary = true, Destructive = true }

local function eq(actual: any, expected: any)
	expect(actual).toEqual(expected)
end

local function own(ids: { string }, fields: { [string]: any }?): { [string]: any }
	local out = {}
	for _, id in ids do
		local entry = { Level = 1, XP = 0, Copies = 1, Job = "" }
		for key, value in fields or {} do
			entry[key] = value
		end
		out[id] = entry
	end
	return out
end

local function snap(fields: { [string]: any }?): any
	local f = fields or {}
	local rebirth = f.Rebirth or {}
	return {
		Level = f.Level or 1,
		Rooms = f.Rooms or {},
		Nurses = f.Nurses or {},
		NurseIndex = f.NurseIndex or {},
		Rebirth = { Count = rebirth.Count or 0, Pending = rebirth.Pending or {} },
	}
end

-- A Team card as the panel asks for it (UI/NursePanel renderTeamCard's info).
local function card(nurseId: string, entry: any, extra: { [string]: any }?): any
	local info = {
		Level = 1,
		Jobs = Jobs,
		Departments = Departments,
		Abilities = Abilities,
		Cfg = Config,
		Roster = Nurses,
		LevelCap = NurseLogic.levelCap(0, Config),
		Resting = false,
		Owned = 1,
		Listed = false,
		Depts = 1,
		Fired = false,
		News = nil,
	}
	for key, value in extra or {} do
		info[key] = value
	end
	return Pure.teamCard(nurseId, entry, rawget(Nurses, nurseId), info)
end

local function filled(view: any): number
	local n = 0
	for _, button in view.Buttons do
		if FILLED[button.Kind] then
			n += 1
		end
	end
	return n
end

T.describe("T1 Nurses: the calm rules are locked at 0", function()
	test("UI/NursePanel.luau: no calm-rule fault left (the ratchet at 0 for every rule)", function()
		local over = UiRules.ratchet({ PATH }, {})
		assert(#over == 0, "\n" .. table.concat(over, "\n"))
		eq(#UiRules.calm({ PATH }), 0)
	end)
	test("the old hard rules still hold (text floor, corners, helpers, header colour)", function()
		local faults = UiRules.check({ PATH })
		assert(#faults == 0, "\n" .. UiRules.format(faults))
	end)
	test("the two outlines left say why (the nurse cap, the stamp over the 3D world)", function()
		local allowed = 0
		for line in string.gmatch(source(PATH), "[^\n]+") do
			if string.find(line, "Kit.stroke(", 1, true) then
				assert(
					string.find(line, "uirules: allow StrokeBudget (", 1, true),
					"an outline without its reason: " .. line
				)
				allowed += 1
			end
		end
		eq(allowed, 2)
	end)
end)

T.describe("T1 Nurses: THE TEAM CARD (Pure.teamCard; memory-20261117-007)", function()
	local fresh = { Level = 1, XP = 0, Copies = 1, Job = "" }

	test("a fresh Lv 1 nurse, your only one: portrait, name, level, ONE button; no More, no bar, no facts", function()
		local view = card("PuffPup", fresh)
		eq(view.Name, "Puff Pup")
		eq(view.Level, "Lv 1")
		eq(view.Job, "🧪 Maker")
		eq(view.Buttons, { { Id = "Job", Kind = "Secondary" } })
		eq(filled(view), 1)
		eq(view.More, false)
		eq(view.Items, {})
		eq(view.Bar, false)
		eq(view.Facts, {})
		eq(view.State, nil)
		eq(view.Ring, false)
	end)

	test("Sell and List go behind More once you own 2 nurses (still one filled button)", function()
		local view = card("PuffPup", fresh, { Owned = 2 })
		eq(view.More, true)
		eq(view.Items, { { Id = "Sell", Text = "Sell" }, { Id = "List", Text = "List" } })
		eq(view.Buttons, { { Id = "Job", Kind = "Secondary" }, { Id = "More", Kind = "Quiet" } })
		eq(filled(view), 1)
		for _, item in view.Items do
			eq(Icons.count(item.Text), 0)
		end
	end)

	test("a listed nurse: More reaches its listing (even alone), and one Soft line says so", function()
		local view = card("PuffPup", fresh, { Owned = 1, Listed = true })
		eq(view.More, true)
		eq(view.Items[2], { Id = "List", Text = "See listing" })
		eq(view.Facts, { "On the Market" })
	end)

	test("a rebirth-only nurse never gets More: it stays with you", function()
		local view = card("FounderFennec", fresh, { Owned = 4 })
		eq(view.More, false)
		eq(view.Facts, { "Stays with you" })
		eq(filled(view), 1)
	end)

	test("a resting nurse: 💤 as the State badge, the button reads Pick a job, no ring", function()
		local view = card("PuffPup", { Level = 3, XP = 4, Copies = 3, Job = "Rest" }, { Resting = true, Owned = 4 })
		eq(view.State, Icons.State.Resting)
		eq(view.Job, "Pick a job")
		eq(view.Resting, true)
		eq(view.Ring, false)
		eq(filled(view), 1)
	end)

	test("the job it waits for is a Soft line, never inside the button", function()
		local view = card("PuffPup", { Level = 1, XP = 0, Copies = 1, Job = "Porter" })
		eq(view.Job, "🧪 Maker")
		eq(view.Facts, { "Porter opens at 🏥 Lv 2" })
	end)

	test(
		"each fact shows once it can differ: the bar (first XP), the specialty (2 departments), the ability",
		function()
			local xp = card("DewDuck", { Level = 1, XP = 3, Copies = 1, Job = "" })
			eq(xp.Bar, true)
			eq(xp.Facts, {})
			local depts = card("DewDuck", fresh, { Depts = 2 })
			eq(depts.Facts, { "Bath Room" })
			local fired = card("DewDuck", fresh, { Depts = 2, Fired = true })
			local ability = rawget(Abilities, rawget(Nurses, "DewDuck").Ability).Name
			eq(fired.Facts, { "Bath Room · " .. ability })
			eq(fired.Ring, true)
			-- a levelled nurse has surely worked: its ability shows, with its tier from Lv 5
			local five = card("DewDuck", { Level = 5, XP = 0, Copies = 5, Job = "" }, { Depts = 2 })
			eq(five.Facts, { "Bath Room · " .. ability .. "+" })
			eq(five.Bar, true)
			-- a new card shows its XP count with the rest
			local new = card("DewDuck", { Level = 2, XP = 7, Copies = 2, Job = "" }, { Depts = 2, News = "Level" })
			eq(new.Facts, { "Bath Room · " .. ability .. " · 7/" .. NurseLogic.xpToNext(2) .. " XP" })
		end
	)

	test("every nurse, every state: one filled button, at most 2 facts, at most one emoji per label", function()
		for _, nurseId in Nurses.Order do
			for _, entry in
				{
					fresh,
					{ Level = 1, XP = 9, Copies = 1, Job = "Porter" },
					{ Level = 5, XP = 3, Copies = 5, Job = "Healer" },
					{ Level = 10, XP = 0, Copies = 9, Job = "Rest" },
				}
			do
				for _, extra in
					{
						{},
						{ Owned = 2, Depts = 3, Fired = true, News = "Hired" },
						{ Owned = 5, Resting = true, Listed = true, Depts = 8, Level = 3 },
						{ Owned = 3, Listed = true, Fired = true, News = "Level", Level = 2 },
					}
				do
					local view = card(nurseId, entry, extra)
					local where = nurseId .. " " .. tostring(entry.Job)
					eq(filled(view), 1)
					assert(#view.Facts <= 2, where .. ": more than 2 facts")
					assert(Icons.count(view.Job) <= 1, where .. ": " .. view.Job)
					assert(Pure.words(view.Job) <= 6, where .. ": " .. view.Job)
					for _, fact in view.Facts do
						assert(fact ~= "", where .. ": an empty fact")
						assert(Icons.count(fact) <= 1, where .. ": " .. fact)
					end
					eq(Icons.count(view.Level), 0)
					if view.More then
						assert(extra.Owned and extra.Owned >= 2 or extra.Listed, where .. ": More with one nurse")
					end
				end
			end
		end
	end)
end)

T.describe("T1 Nurses: R0, a fresh save is simple (Pure.visible)", function()
	local order = Rarities.Order
	local function tabsShown(view: any): { string }
		local out = {}
		for _, id in Pure.tabIds(order, true) do
			if view.Tabs[id] then
				table.insert(out, id)
			end
		end
		return out
	end

	test("a brand-new Lv 1 save: the Team tab alone, no Agency, no Market", function()
		local view = Pure.visible(snap(), Nurses, order, Config, nil)
		eq(tabsShown(view), { "Team" })
		eq(view.Agency, false)
		eq(view.Market, false)
	end)

	test("one nurse hired, one rarity seen: still the Team alone (a Journal tab needs a second rarity)", function()
		local state = snap({ Nurses = own({ "PuffPup" }), NurseIndex = { PuffPup = "Hired", MintMouse = "Seen" } })
		local view = Pure.visible(state, Nurses, order, Config, nil)
		eq(tabsShown(view), { "Team" })
		eq(view.Agency, false)
		eq(view.Market, false)
	end)

	test("a second rarity seen: a tab for each rarity seen, and only those", function()
		local state = snap({ Nurses = own({ "PuffPup" }), NurseIndex = { PuffPup = "Hired", JamJelly = "Seen" } })
		eq(tabsShown(Pure.visible(state, Nurses, order, Config, nil)), { "Team", "Common", "Epic" })
	end)

	test("the Agency link: once the roster is full, a nurse has left you, or this session showed it", function()
		local full = snap({ Nurses = own({ "PuffPup", "MintMouse", "BeanBear" }) })
		eq(Pure.visible(full, Nurses, order, Config, nil).Agency, true)
		local two = snap({ Nurses = own({ "PuffPup", "MintMouse" }) })
		eq(Pure.visible(two, Nurses, order, Config, nil).Agency, false)
		eq(Pure.visible(two, Nurses, order, Config, { Agency = true }).Agency, true)
		local sold = snap({ Nurses = own({ "PuffPup" }), NurseIndex = { PuffPup = "Hired", MintMouse = "Hired" } })
		local view = Pure.visible(sold, Nurses, order, Config, nil)
		eq(view.Agency, true)
		eq(view.Market, true) -- a nurse left: you have used the Agency or the Market
	end)

	test("the Market link: once the Agency was opened, or a nurse of yours is listed", function()
		local two = snap({ Nurses = own({ "PuffPup", "MintMouse" }) })
		eq(Pure.visible(two, Nurses, order, Config, nil).Market, false)
		eq(Pure.visible(two, Nurses, order, Config, { AgencyOpened = true }).Market, true)
		eq(Pure.visible(two, Nurses, order, Config, { Listed = true }).Market, true)
	end)

	test("a rich save (a branch, a full roster, many rarities) still shows everything", function()
		local index = {}
		for _, nurseId in Nurses.Order do
			index[nurseId] = "Seen"
		end
		local ids = { "PuffPup", "JamJelly", "MintMouse", "BeanBear" }
		for _, id in ids do
			index[id] = "Hired"
		end
		local state = snap({
			Level = 5,
			Nurses = own(ids, { Level = 6, XP = 3 }),
			NurseIndex = index,
			Rebirth = { Count = 1 },
		})
		local view = Pure.visible(state, Nurses, order, Config, { AgencyOpened = true })
		local all = { "Team" }
		for _, rarity in order do
			table.insert(all, rarity)
		end
		table.insert(all, "Branch")
		eq(tabsShown(view), all)
		eq(view.Agency, true)
		eq(view.Market, true)
	end)
end)

T.describe("T1 Nurses: the source draws what the pure block decides", function()
	local text = source(PATH)
	local function has(needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end

	test("the calm parts: Kit.card, Kit.bar, Kit.more, Kit.setState, Kit.artTile, Kit.fact, Kit.name", function()
		for _, part in
			{ "Kit.card(", "Kit.bar(", "Kit.more(", "Kit.setState(", "Kit.artTile(", "Kit.fact(", "Kit.name(" }
		do
			assert(has(part), "NursePanel doesn't use " .. part)
		end
		assert(has("Pure.teamCard("), "the Team card isn't drawn from Pure.teamCard")
		assert(has("Pure.visible("), "the panel doesn't ask Pure.visible what shows")
		assert(has("tabs.setVisible("), "the tabs don't follow Pure.visible")
	end)

	test("no hand-built chip, pill, plate or tilted ribbon is left", function()
		for _, gone in { "local function chip(", "Rotation = -8", "Rotation = -10", "XpFill", "LevelBadge" } do
			assert(not has(gone), "still in NursePanel: " .. gone)
		end
	end)

	test("the titles are words and the meta has no emoji", function()
		eq(Pure.TEXT.TitleTeam, "Team")
		eq(Pure.TEXT.TitleJournal, "Journal")
		eq(Icons.count(Pure.metaText(42)), 0)
	end)
end)
