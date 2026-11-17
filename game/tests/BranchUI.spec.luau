--!nocheck
-- The Branch panel's pure helpers (Progression v2 T5): the PURE-BEGIN..PURE-END blocks of UI/BranchPanel and
-- UI/Shop (the 🏥 tab's branch card, upgrade gates, the level line), loaded on their own (the rest of those modules
-- needs Roblox) and tested against the real Logic/Rebirth, Logic/Tree, Logic/Nurse, Logic/Progress, the shipped
-- Config (tests/config) and Data/Perks, Tree, Themes, Nurses, Upgrades, Levels and Departments. Run from game/ with
-- the rest:
--   lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local RebirthLogic = require("../src/shared/Logic/Rebirth")
local TreeLogic = require("../src/shared/Logic/Tree")
local NurseLogic = require("../src/shared/Logic/Nurse")
local Perks = require("../src/shared/Data/Perks")
local Tree = require("../src/shared/Data/Tree")
local Themes = require("../src/shared/Data/Themes")
local Nurses = require("../src/shared/Data/Nurses")
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

local Pure = pureBlock("src/client/UI/BranchPanel.luau", {
	RebirthLogic = RebirthLogic,
	TreeLogic = TreeLogic,
	NurseLogic = NurseLogic,
	Icons = Icons,
})
local ShopPure = pureBlock("src/client/UI/Shop.luau", {
	RebirthLogic = RebirthLogic,
	TreeLogic = TreeLogic,
})
local ProgressLogic = require("../src/shared/Logic/Progress")
local Upgrades = require("../src/shared/Data/Upgrades")
local Levels = require("../src/shared/Data/Levels")
local Departments = require("../src/shared/Data/Departments")

local function eq(actual: any, expected: any)
	expect(actual).toEqual(expected)
end

-- A Snapshot with only what the panel reads.
local function snap(fields: { [string]: any }?): any
	local f = fields or {}
	local rebirth = f.Rebirth or {}
	return {
		Level = f.Level or 1,
		Cash = f.Cash or 0,
		Nurses = f.Nurses or {},
		Rebirth = {
			Count = rebirth.Count or 0,
			Points = rebirth.Points or 0,
			Tree = rebirth.Tree or {},
			Perks = rebirth.Perks or {},
			Offer = rebirth.Offer or {},
			Theme = rebirth.Theme or "",
			Pending = rebirth.Pending or {},
			Told = false,
		},
	}
end

local function texts(rows: { any }): { string }
	local out = {}
	for _, row in rows do
		table.insert(out, Pure.rowText(row))
	end
	return out
end

local function assertWords(text: string, where: string)
	assert(Pure.words(text) <= 6, where .. ": more than 6 words: " .. text)
end

T.describe("BranchPanel (pure): the keep/reset screen", function()
	test("words counts tokens with letters only", function()
		eq(Pure.words("🏥 Lv 5  ·  💰50,000"), 1)
		eq(Pure.words("Hold the button to open"), 5)
		eq(Pure.words(""), 0)
		eq(Pure.words(nil), 0)
	end)
	test("keep rows are Logic/Rebirth.KEEP exactly", function()
		local rows = Pure.keepRows()
		eq(#rows, #RebirthLogic.KEEP)
		for index, row in rows do
			eq(row.Icon, RebirthLogic.KEEP[index].Icon)
			eq(row.Text, RebirthLogic.KEEP[index].Text)
		end
	end)
	test("reset rows are Logic/Rebirth.RESET, every one softened by its start perk", function()
		local plain = Pure.resetRows(snap(), Perks)
		eq(#plain, #RebirthLogic.RESET)
		for index, row in plain do
			eq(row.Icon, RebirthLogic.RESET[index].Icon)
			eq(row.Text, RebirthLogic.RESET[index].Text)
			eq(row.Note, nil)
			assert(Pure.RESET_KINDS[row.Icon], "no start perk kind for " .. row.Icon)
		end
		local all = snap({ Rebirth = { Perks = { "SeedMoney", "WarmUp", "ClinicStart", "BathReady", "BigHands" } } })
		eq(texts(Pure.resetRows(all, Perks)), {
			"💰 Cash · Seed Money",
			"⚡ Upgrades · Warm Up",
			"🏥 Hospital level · Clinic Start",
			"🏠 Rooms · Bath Ready",
		})
		-- every RESET kind exists among the perks, so each note can show
		for _, kind in Pure.RESET_KINDS do
			local found = false
			for _, perkId in Perks.Order do
				if rawget(Perks, perkId).Kind == kind then
					found = true
				end
			end
			assert(found, "no perk of kind " .. kind)
		end
	end)
	test("the cash row says ALL cash starts fresh, with the real numbers (not the cost taken off)", function()
		local rich = snap({ Level = 5, Cash = 180000 })
		eq(texts(Pure.resetRows(rich, Perks, Config))[1], "💰 Cash: 180,000 → 0")
		local seeded = snap({ Level = 5, Cash = 1.3e6, Rebirth = { Perks = { "SeedMoney" } } })
		local seed = RebirthLogic.startCash(seeded, Config, Perks)
		eq(seed, rawget(Perks, "SeedMoney").Value)
		eq(
			texts(Pure.resetRows(seeded, Perks, Config))[1],
			"💰 Cash: 1.3M → " .. Pure.short(seed) .. " · Seed Money"
		)
		-- the other rows are unchanged
		eq(Pure.resetRows(rich, Perks, Config)[2].Text, RebirthLogic.RESET[2].Text)
		for count = 0, 12 do
			for _, perks in { {}, table.clone(Perks.Order) } do
				local state = snap({ Level = 5, Cash = 1e7, Rebirth = { Count = count, Perks = perks } })
				for _, row in Pure.resetRows(state, Perks, Config) do
					assertWords(Pure.rowText(row), "reset with cash")
				end
			end
		end
	end)
	test("an offer whose cards were renamed or removed shows the Fallback card (never a dead end)", function()
		local stale = snap({ Rebirth = { Count = 1, Offer = { "GoneCard", "OldName" } } })
		local cards = Pure.offerCards(stale, Perks)
		eq(#cards, 1)
		eq(cards[1].Id, RebirthLogic.FALLBACK)
		local mixed = snap({ Rebirth = { Count = 1, Offer = { "GoneCard", "BigHands" } } })
		eq(#Pure.offerCards(mixed, Perks), 1)
		eq(Pure.offerCards(mixed, Perks)[1].Id, "BigHands")
		eq(#Pure.offerCards(snap({ Rebirth = { Count = 1, Offer = {} } }), Perks), 0)
	end)
	test("get rows at R0: Logic/Rebirth.GET's numbers from Config, the Arctic look, the R1 unlocks", function()
		local rows = Pure.getRows(snap(), Config, Themes)
		eq(texts(rows), {
			"💰 +25% cash",
			"⭐ +25% stars",
			"🌳 +3 tree points",
			"🃏 A perk card",
			"👩‍⚕️ +1 nurse slot",
			"❄️ Arctic look",
			"🐉 Mythic and Secret nurses",
			"🌻 Sunny wing patients",
		})
		-- the computed rows say exactly what Logic/Rebirth.GET says with the shipped Config
		for index = 1, 5 do
			eq(rows[index].Text, RebirthLogic.GET[index].Text)
		end
	end)
	test("get rows: Golden with its odds at R3, the slot row stops at the roster's Max, no look after R5", function()
		eq(texts(Pure.getRows(snap({ Rebirth = { Count = 2 } }), Config, Themes)), {
			"💰 +25% cash",
			"⭐ +25% stars",
			"🌳 +3 tree points",
			"🃏 A perk card",
			"👩‍⚕️ +1 nurse slot",
			"🚀 Space look",
			"🌟 Golden patients (2%)",
			"⬆️ Nurses to Lv 15",
		})
		-- R5 reaches the roster's Max (8): the slot row is still there for it, then gone
		local toFive = texts(Pure.getRows(snap({ Rebirth = { Count = 4 } }), Config, Themes))
		assert(table.find(toFive, "👩‍⚕️ +1 nurse slot"), "R5 still adds a slot")
		assert(table.find(toFive, "👑 Royal look"), "R5 brings Royal")
		eq(NurseLogic.rosterCap(5, Config), Config.Roster.Max)
		eq(texts(Pure.getRows(snap({ Rebirth = { Count = 5 } }), Config, Themes)), {
			"💰 +25% cash",
			"⭐ +25% stars",
			"🌳 +3 tree points",
			"🃏 A perk card",
			"🏆 Branch trophy",
		})
		eq(texts(Pure.getRows(snap({ Rebirth = { Count = 10 } }), Config, Themes)), {
			"💰 +25% cash",
			"⭐ +25% stars",
			"🌳 +3 tree points",
			"🃏 A perk card",
		})
	end)
	test("get rows: the 💰⭐ bonus rows stop once it no longer adds up (MaxBonusRebirths)", function()
		local last = texts(Pure.getRows(snap({ Rebirth = { Count = 19 } }), Config, Themes))
		eq(last[1], "💰 +25% cash")
		eq(texts(Pure.getRows(snap({ Rebirth = { Count = 20 } }), Config, Themes)), {
			"🌳 +3 tree points",
			"🃏 A perk card",
		})
	end)
	test("status: what it takes (one Unit), the hint says what's missing, the same yes/no as canRebirth", function()
		local low = Pure.status(snap({ Level = 4, Cash = 1e9 }), Config)
		eq(low.Ok, false)
		eq(low.Message, "Needs 🏥 Lv 5")
		eq(low.Message, Icons.needs(5)) -- THE gate note's words (Logic/Rebirth says the same)
		eq(low.LevelOk, false)
		eq(low.CashOk, true)
		eq(low.Line, "Needs 🏥 Lv 5  ·  50,000 cash")
		eq(low.Hint, "Not yet: hospital level")
		local poor = Pure.status(snap({ Level = 5, Cash = 49999 }), Config)
		eq(poor.Ok, false)
		eq(poor.Message, "Need 💰50,000")
		eq(poor.Line, "Needs 🏥 Lv 5  ·  50,000 cash")
		eq(poor.Hint, "Not yet: more cash")
		eq(Pure.status(snap({ Level = 1 }), Config).Hint, "Not yet: level and cash")
		local ready = Pure.status(snap({ Level = 5, Cash = 50000 }), Config)
		eq(ready.Ok, true)
		eq(ready.Next, 1)
		eq(ready.Line, "Needs 🏥 Lv 5  ·  50,000 cash")
		eq(ready.Hint, Pure.TEXT.HoldHint)
		local second = Pure.status(snap({ Level = 5, Cash = 0, Rebirth = { Count = 1 } }), Config)
		eq(second.Cost, 75000)
		eq(second.Next, 2)
		eq(Pure.status(snap({ Rebirth = { Count = 8 } }), Config).Line, "Needs 🏥 Lv 5  ·  1.3M cash")
		-- one emoji at most on every line the head card shows (the emoji rules: one per label)
		for count = 0, 25 do
			for _, level in { 1, 5 } do
				local status = Pure.status(snap({ Level = level, Cash = 1e7, Rebirth = { Count = count } }), Config)
				assert(Icons.count(status.Line) <= 1, status.Line)
				eq(Icons.count(status.Hint), 0)
			end
		end
		for count = 0, 25 do
			local status = Pure.status(snap({ Level = 5, Rebirth = { Count = count } }), Config)
			eq(status.Cost, RebirthLogic.cost(count, Config))
		end
	end)
	test("status: a waiting perk card blocks the branch with Server/Rebirth's own words", function()
		local waiting = Pure.status(
			snap({ Level = 5, Cash = 1e6, Rebirth = { Count = 1, Offer = { "BusyDoors", "NightOwl" } } }),
			Config
		)
		eq(waiting.Ok, false)
		eq(waiting.CardWaits, true)
		eq(waiting.Message, "Pick your card first")
		eq(waiting.Hint, "Pick your card first")
		local picked = Pure.status(snap({ Level = 5, Cash = 1e6, Rebirth = { Count = 1, Offer = {} } }), Config)
		eq(picked.Ok, true)
		eq(picked.CardWaits, false)
		-- the server's message says the same words (Server/Rebirth MSG.PickCard)
		local src = source("src/server/Rebirth.luau")
		eq(string.find(src, "Pick your card first", 1, true) ~= nil, true)
	end)
	test("short and percent", function()
		eq(Pure.short(50000), "50,000")
		eq(Pure.short(999999), "999,999")
		eq(Pure.short(1000000), "1M")
		eq(Pure.short(1300000), "1.3M")
		eq(Pure.short(-5), "0")
		eq(Pure.percent(0.02), "2%")
		eq(Pure.percent(0.025), "2.5%")
		eq(Pure.percent(nil), "0%")
	end)
end)

T.describe("BranchPanel (pure): perks", function()
	test("the offer's cards in order, the Fallback too, unknown ids skipped", function()
		local cards = Pure.offerCards(snap({ Rebirth = { Offer = { "BigHands", "Nope", "SeedMoney" } } }), Perks)
		eq(#cards, 2)
		eq(cards[1].Id, "BigHands")
		eq(cards[1].Text, "Carry one more")
		eq(cards[2].Id, "SeedMoney")
		local fallback = Pure.offerCards(snap({ Rebirth = { Offer = { "TreePoints" } } }), Perks)
		eq(#fallback, 1)
		eq(fallback[1].Icon, "🌳")
		eq(fallback[1].Text, "+2 tree points")
		eq(Pure.offerCards(snap(), Perks), {})
	end)
	test("the odds in words: every card left equally likely", function()
		eq(Pure.oddsText(snap(), Perks), "All 12 cards equally likely")
		eq(
			Pure.oddsText(snap({ Rebirth = { Perks = { "BigHands", "SeedMoney" } } }), Perks),
			"All 10 cards equally likely"
		)
		local eleven = table.clone(Perks.Order)
		table.remove(eleven)
		eq(Pure.oddsText(snap({ Rebirth = { Perks = eleven } }), Perks), "1 card left")
		eq(
			Pure.oddsText(snap({ Rebirth = { Perks = table.clone(Perks.Order) } }), Perks),
			"Every card owned: +2 tree points"
		)
		eq(Pure.randomText(Config), "3 random cards, never repeats")
	end)
	test("every perk in Data order, ✅ when owned", function()
		local list = Pure.perkList(snap({ Rebirth = { Perks = { "NightOwl" } } }), Perks)
		eq(#list, #Perks.Order)
		for index, card in list do
			eq(card.Id, Perks.Order[index])
			eq(card.Owned, card.Id == "NightOwl")
		end
	end)
	test("the gift: a waiting rebirth-only nurse, and whether the roster has room", function()
		eq(Pure.gift(snap(), Nurses, Config), nil)
		local roomy = Pure.gift(snap({ Rebirth = { Count = 5, Pending = { "FounderFennec" } } }), Nurses, Config)
		eq(roomy, { NurseId = "FounderFennec", Room = true })
		local full = {}
		for _, id in
			{ "PuffPup", "MintMouse", "BeanBear", "DewDuck", "HumHamster", "CuddleCub", "PebblePenguin", "BerryBat" }
		do
			full[id] = { Level = 1, XP = 0, Copies = 1, Job = "" }
		end
		eq(
			Pure.gift(snap({ Nurses = full, Rebirth = { Count = 5, Pending = { "FounderFennec" } } }), Nurses, Config),
			{ NurseId = "FounderFennec", Room = false }
		)
		eq(Pure.gift(snap({ Rebirth = { Pending = { "Ghost" } } }), Nurses, Config), nil)
	end)
end)

T.describe("BranchPanel (pure): the tree", function()
	test("node states: Poor with no points, Buy, Max, the capstone lock", function()
		local none = Pure.nodeView(snap(), "GentleWords", Tree)
		eq(none.State, "Poor")
		eq(none.Button, "🌳 1")
		eq(none.Message, "Need 🌳1")
		local some = Pure.nodeView(snap({ Rebirth = { Points = 3 } }), "GentleWords", Tree)
		eq(some.State, "Buy")
		eq(some.Rank, 0)
		eq(some.Max, 3)
		local maxed = Pure.nodeView(snap({ Rebirth = { Points = 3, Tree = { GentleWords = 3 } } }), "GentleWords", Tree)
		eq(maxed.State, "Max")
		eq(maxed.Button, "MAX") -- the word: ⭐ is Stars only, ✅ is a State badge
		local locked = Pure.nodeView(snap({ Rebirth = { Points = 9 } }), "TwinCounters", Tree)
		eq(locked.State, "Locked")
		eq(locked.Button, "Needs 🌳 6 in Care")
		eq(locked.Capstone, true)
		-- 6 points in Care opens it; 1 point isn't enough for its Cost 2
		local six = { GentleWords = 3, ThankYou = 3 }
		eq(Pure.nodeView(snap({ Rebirth = { Points = 2, Tree = six } }), "TwinCounters", Tree).State, "Buy")
		local short = Pure.nodeView(snap({ Rebirth = { Points = 1, Tree = six } }), "TwinCounters", Tree)
		eq(short.State, "Poor")
		eq(short.Button, "🌳 2")
		-- points spent in another branch don't open it
		local elsewhere = Pure.nodeView(
			snap({ Rebirth = { Points = 9, Tree = { LuckyCoins = 3, StarShine = 3 } } }),
			"TwinCounters",
			Tree
		)
		eq(elsewhere.State, "Locked")
		eq(Pure.nodeView(snap(), "Nope", Tree), nil)
		eq(Pure.nodeView(snap(), "Order", Tree), nil)
	end)
	test("every node's state agrees with Logic/Tree.canBuy", function()
		for _, points in { 0, 1, 2, 5 } do
			for _, nodeId in Tree.Nodes.Order do
				local state = snap({ Rebirth = { Points = points, Tree = { GentleWords = 2, NimbleFingers = 3 } } })
				local view = Pure.nodeView(state, nodeId, Tree)
				local ok = TreeLogic.canBuy(state.Rebirth.Tree, points, nodeId, Tree.Nodes)
				eq(view.State == "Buy", ok)
			end
		end
	end)
	test("branch heads and their nodes", function()
		local care = Pure.branchView(snap({ Rebirth = { Tree = { GentleWords = 2, LuckyCoins = 1 } } }), "Care", Tree)
		eq(care.Head, "Care  ·  🌳 2")
		eq(care.Nodes, { "GentleWords", "ThankYou", "SteadyHands", "TwinCounters" })
		eq(#Pure.branchView(snap(), "Speed", Tree).Nodes, 4)
		eq(#Pure.branchView(snap(), "Fortune", Tree).Nodes, 4)
	end)
	test("reset: offered once anything would come back (unknown nodes too); the reward dot", function()
		eq(Pure.canReset(snap(), Tree), false)
		eq(Pure.canReset(snap({ Rebirth = { Tree = { QuickFeet = 1 } } }), Tree), true)
		eq(Pure.canReset(snap({ Rebirth = { Tree = { OldNode = 2 } } }), Tree), true)
		eq(Pure.treeNews(snap(), Tree), false)
		eq(Pure.treeNews(snap({ Rebirth = { Points = 1 } }), Tree), true)
		local full = {}
		for _, nodeId in Tree.Nodes.Order do
			full[nodeId] = rawget(Tree.Nodes, nodeId).Max
		end
		eq(Pure.treeNews(snap({ Rebirth = { Points = 5, Tree = full } }), Tree), false)
		eq(Pure.pointsText(1), "🌳 1 point")
		eq(Pure.pointsText(3), "🌳 3 points")
	end)
end)

T.describe("BranchPanel (pure): themes and opening", function()
	test("themes at R0: Candy on, the rest locked by their rebirth (no lock icon)", function()
		local cards = Pure.themeCards(snap(), Themes)
		eq(#cards, #Themes.Order)
		eq(cards[1].State, "On")
		eq(cards[1].Text, "On")
		for index = 2, #cards do
			eq(cards[index].State, "Locked")
			eq(cards[index].Text, "From branch " .. rawget(Themes, cards[index].Id).Rebirths)
			eq(Icons.count(cards[index].Text), 0) -- no lock icon, no 🏢
		end
	end)
	test("themes at R2 on Arctic: Arctic on, Candy and Jungle to pick, Space locked", function()
		local cards = Pure.themeCards(snap({ Rebirth = { Count = 2, Theme = "Arctic" } }), Themes)
		local byId = {}
		for _, card in cards do
			byId[card.Id] = card
		end
		eq(byId.Arctic.State, "On")
		eq(byId.Candy.State, "Pick")
		eq(byId.Candy.Text, "Pick")
		eq(byId.Jungle.State, "Pick")
		eq(byId.Space.Text, "From branch 3")
		-- a theme the save can't show yet falls back to Candy (Logic/Rebirth.theme)
		local cheat = Pure.themeCards(snap({ Rebirth = { Count = 0, Theme = "Royal" } }), Themes)
		eq(cheat[1].State, "On")
	end)
	test("theme cards show the Roof and Trim swatches only: a theme never recolours the walls (look §G4)", function()
		eq(Pure.SWATCHES, { "Roof", "Trim" })
		for _, themeId in Themes.Order do
			local theme = rawget(Themes, themeId)
			for _, key in Pure.SWATCHES do
				-- a hex colour, or "" for Candy (the building's own trim and dark roof)
				local value = theme[key]
				assert(value == "" or string.match(value, "^#%x%x%x%x%x%x$"), themeId .. "." .. key .. ": " .. value)
			end
		end
		eq(Pure.TEXT.WallsStay, "Walls stay your colour")
	end)
	test("the tree reset asks through THE confirm: Destructive, its own words, no hold", function()
		eq(Pure.resetConfirm(), {
			Title = Pure.TEXT.ResetTitle,
			Line = Pure.TEXT.ResetNote,
			Yes = Pure.TEXT.ResetYes,
			Kind = "Destructive",
			Hold = 0,
		})
		assert(Pure.words(Pure.TEXT.ResetTitle) <= 2, "a confirm title is two words at most")
	end)
	test("firstTab: the tab asked for, else a card, else tree points, else Open", function()
		eq(Pure.firstTab("Themes", snap({ Rebirth = { Count = 1 } }), Tree), "Themes")
		eq(Pure.firstTab("Themes", snap(), Tree), "Open") -- R0: no Themes tab before the first branch
		eq(Pure.firstTab("Nope", snap(), Tree), "Open")
		eq(Pure.firstTab(nil, snap({ Rebirth = { Offer = { "BigHands" } } }), Tree), "Perks")
		eq(Pure.firstTab(nil, snap({ Rebirth = { Points = 3 } }), Tree), "Tree")
		eq(Pure.firstTab(nil, snap(), Tree), "Open")
		eq(Pure.firstTab("Open", snap({ Rebirth = { Offer = { "BigHands" } } }), Tree), "Open")
	end)
	test("≤ 6 words on every label: the fixed texts, every row at R0..R25, perks, nodes, themes", function()
		for key, text in Pure.TEXT do
			assertWords(text, "TEXT." .. key)
		end
		assertWords(Pure.randomText(Config), "randomText")
		local allPerks = table.clone(Perks.Order)
		for count = 0, 25 do
			for _, perks in { {}, allPerks } do
				local state = snap({ Level = 5, Cash = 1e7, Rebirth = { Count = count, Perks = perks } })
				for _, row in Pure.keepRows() do
					assertWords(Pure.rowText(row), "keep")
				end
				for _, row in Pure.resetRows(state, Perks) do
					assertWords(Pure.rowText(row), "reset")
				end
				for _, row in Pure.getRows(state, Config, Themes) do
					assertWords(Pure.rowText(row), "get at R" .. count)
				end
				assertWords(Pure.status(state, Config).Line, "status")
				assertWords(Pure.oddsText(state, Perks), "odds")
				for _, card in Pure.themeCards(state, Themes) do
					assertWords(card.Text, "theme")
				end
			end
		end
		for _, perkId in Perks.Order do
			assertWords(rawget(Perks, perkId).Text, "perk " .. perkId)
		end
		assertWords(Perks.Fallback.Text, "fallback")
		for _, nodeId in Tree.Nodes.Order do
			assertWords(rawget(Tree.Nodes, nodeId).Text, "node " .. nodeId)
			for _, points in { 0, 9 } do
				assertWords(Pure.nodeView(snap({ Rebirth = { Points = points } }), nodeId, Tree).Button, "node button")
			end
		end
		for _, branchId in Tree.BranchOrder do
			assertWords(Pure.branchView(snap(), branchId, Tree).Head, "branch head")
		end
	end)
end)

T.describe("Shop (pure): the 🏥 tab's branch card, gates and levels", function()
	test("the branch card: hidden below Lv 5 with no branches; at Lv 5 the cost and Look 👀", function()
		eq(ShopPure.branchCard(snap({ Level = 4 }), Config, Tree).Show, false)
		local top = ShopPure.branchCard(snap({ Level = 5 }), Config, Tree)
		eq(top, {
			Show = true,
			Title = "🏢 New branch",
			Sub = "Need 💰50,000",
			Look = true,
			Links = false,
			Lines = {},
		})
		local second = ShopPure.branchCard(snap({ Level = 5, Rebirth = { Count = 2 } }), Config, Tree)
		eq(second.Sub, "Need 💰110,000  ·  🏢 R2")
		eq(second.Links, true)
	end)
	test("after a rebirth: the way to cards, tree and themes, and a line per reward waiting", function()
		local fresh = ShopPure.branchCard(
			snap({ Level = 1, Rebirth = { Count = 1, Points = 3, Offer = { "BigHands" } } }),
			Config,
			Tree
		)
		eq(fresh, {
			Show = true,
			Title = "🏢 Your branches",
			Sub = "🏢 R1",
			Look = false,
			Links = true,
			Lines = { "🃏 A card to pick!", "🌳 3 points to spend" },
		})
		eq(
			ShopPure.branchCard(snap({ Rebirth = { Count = 1, Points = 1 } }), Config, Tree).Lines,
			{ "🌳 1 point to spend" }
		)
		-- points no node can take aren't a reward to claim (the same rule as Hud.shopNews.Branch)
		local full = {}
		for _, nodeId in Tree.Nodes.Order do
			full[nodeId] = rawget(Tree.Nodes, nodeId).Max
		end
		eq(ShopPure.branchCard(snap({ Rebirth = { Count = 11, Points = 4, Tree = full } }), Config, Tree).Lines, {})
	end)
	test("no pressure: having the cash changes nothing on the card", function()
		eq(
			ShopPure.branchCard(snap({ Level = 5, Cash = 1e9 }), Config, Tree),
			ShopPure.branchCard(snap({ Level = 5, Cash = 0 }), Config, Tree)
		)
		for key, text in ShopPure.TEXT do
			assertWords(text, "Shop TEXT." .. key)
			assert(not string.find(string.lower(text), "now", 1, true), "no 'now' on " .. key)
		end
	end)
	test("gated upgrades say Logic/Progress.canBuyUpgrade's gate", function()
		local _, ward = ProgressLogic.canBuyUpgrade(snap({ Level = 1 }), "WardComfort", Upgrades)
		eq(ShopPure.gateText(ward), "🏥 Lv 2")
		local _, night = ProgressLogic.canBuyUpgrade(snap({ Level = 5 }), "NightClinic", Upgrades)
		eq(ShopPure.gateText(night), "🏢 R4")
		eq((ProgressLogic.canBuyUpgrade(snap({ Level = 5, Rebirth = { Count = 4 } }), "NightClinic", Upgrades)), true)
		eq(ShopPure.gateText("Coming soon!"), "Coming soon!")
	end)
	test("the level line: the departments open at that level, the bays, the ward beds and the plan size", function()
		eq(ShopPure.levelLine(Levels[1], Departments), "🛎️ 💊   🩺 2   🛏️ 0   📋 1")
		eq(ShopPure.levelLine(Levels[2], Departments), "🛎️ 💊 🚑 🛏️   🩺 3   🛏️ 3   📋 2")
		eq(
			ShopPure.levelLine(Levels[5], Departments),
			"🛎️ 💊 🚑 🛏️ 📸 😴 🚁   🩺 6   🛏️ 7   📋 3"
		)
		eq(ShopPure.levelLine(nil, Departments), "   🩺 0   🛏️ 0   📋 0")
		for level = 1, #Levels do
			assertWords(ShopPure.levelLine(Levels[level], Departments), "level line")
		end
	end)
end)
