--!strict
-- The Nurse Agency's rules (Logic/Agency; Progression v2 build plan §B3.1/§B6/§B7).

local T = require("./expect")
local expect, test = T.expect, T.test

local Agency = require("../src/shared/Logic/Agency")
local Belt = require("../src/shared/Logic/Belt")
local Nurses = require("../src/shared/Data/Nurses")
local Config = require("./config")

T.describe("Agency", function()
	test("restocks every 5 minutes of uptime", function()
		expect(Agency.restock(0, Config)).toBe(0)
		expect(Agency.restock(299, Config)).toBe(0)
		expect(Agency.restock(300, Config)).toBe(1)
		expect(Agency.restock(3601, Config)).toBe(12)
		expect(Agency.restock(-5, Config)).toBe(0)
	end)

	test("the shown odds: 70 / 26 / 4, never Legendary or up", function()
		expect(Agency.odds(Config)).toEqual({ Common = 70, Rare = 26, Epic = 4 })
		local total = 0
		for _, value in Agency.odds(Config) do
			total += value
		end
		expect(total).toBe(100)
		expect(Agency.rarity(Agency.odds(Config), 0)).toBe("Common")
		expect(Agency.rarity(Agency.odds(Config), 0.69)).toBe("Common")
		expect(Agency.rarity(Agency.odds(Config), 0.70)).toBe("Rare")
		expect(Agency.rarity(Agency.odds(Config), 0.97)).toBe("Epic")
		expect(Agency.rarity(Agency.odds(Config), 1)).toBe("Epic")
	end)

	test("roll: 4 distinct nurses, never rebirth-only, a full rarity falls to the next lower", function()
		local stock = Agency.roll(Nurses, Config, { 0.1, 0, 0.1, 0, 0.1, 0, 0.1, 0 })
		expect(#stock).toBe(4)
		local seen = {}
		for _, id in stock do
			expect(seen[id]).toBeNil()
			seen[id] = true
			expect(Nurses[id].Source).toBeNil()
			expect(Nurses[id].Rarity).toBe("Common")
		end
		-- four Epic rolls: only 3 Epics exist, so the 4th is a Rare
		local epics = Agency.roll(Nurses, Config, { 0.99, 0, 0.99, 0, 0.99, 0, 0.99, 0 })
		local rarities = {}
		for _, id in epics do
			table.insert(rarities, Nurses[id].Rarity)
		end
		expect(rarities).toEqual({ "Epic", "Epic", "Epic", "Rare" })
		-- fewer random numbers, fewer slots; `taken` is never repeated
		expect(#Agency.roll(Nurses, Config, { 0.5, 0.5 })).toBe(1)
		local others = Agency.roll(Nurses, Config, { 0.1, 0, 0.1, 0 }, 2, { "PuffPup" })
		expect(table.find(others, "PuffPup")).toBeNil()
	end)

	test(
		"seeded and personal: the same seed, the same nurses; 2 Lucky Stock slots, none from the shared stock",
		function()
			expect(Agency.seeded(12345, 4)).toEqual(Agency.seeded(12345, 4))
			for _, r in Agency.seeded(42, 50) do
				expect(r >= 0 and r < 1).toBe(true)
			end
			local shared = { "PuffPup", "MintMouse", "CuddleCub", "BeanBear" }
			local mine = Agency.personal(Nurses, Config, 311718381, 7, shared)
			expect(#mine).toBe(Config.Agency.LuckySlots)
			expect(Agency.personal(Nurses, Config, 311718381, 7, shared)).toEqual(mine) -- a rejoin never re-rolls
			for _, id in mine do
				expect(table.find(shared, id)).toBeNil()
				expect(Nurses[id].Source).toBeNil()
			end
			-- a different restock or player usually differs (seeds are not all the same)
			local different = false
			for restock = 8, 20 do
				if
					Agency.seeded(311718381 % 1000003 * 7919 + restock + 1, 4)[1]
					~= Agency.seeded(311718381 % 1000003 * 7919 + 8, 4)[1]
				then
					different = true
				end
			end
			expect(different).toBe(true)
		end
	)

	test(
		"personal: every Common in the shared stock still gives 2 own slots, a shared one repeating only then",
		function()
			local commons = {}
			for _, id in Nurses.Order do
				if Nurses[id].Rarity == "Common" and Nurses[id].Source == nil then
					table.insert(commons, id)
				end
			end
			for k = 1, 300 do
				local mine = Agency.personal(Nurses, Config, 5000 + k, k, commons)
				expect(#mine).toBe(Config.Agency.LuckySlots)
				expect(mine[1] ~= mine[2]).toBe(true)
				for _, id in mine do
					expect(Nurses[id].Source).toBeNil()
					if table.find(commons, id) then
						expect(Nurses[id].Rarity).toBe("Common") -- the rolled rarity, never a fall to another
					end
				end
			end
		end
	)

	test("price: x1.5 the belt's price at your level, Bargain off", function()
		expect(Agency.price(Config, "Common", 1)).toBe(150)
		expect(Agency.price(Config, "Rare", 1)).toBe(600)
		expect(Agency.price(Config, "Epic", 1)).toBe(2250)
		expect(Agency.price(Config, "Common", 5)).toBe(math.floor(Belt.price(Config, "Common", 5) * 1.5 + 0.5))
		expect(Agency.price(Config, "Rare", 1, 0.15)).toBe(510)
		expect(Agency.price(Config, "Nope", 1)).toBe(0)
	end)

	test("sellBack: 30% of the belt's base price per copy, never level-scaled (§E14)", function()
		local each = {}
		for _, rarity in Belt.RARITIES do
			each[rarity] = Agency.sellBack({ Level = 1, Copies = 1 }, rarity, Config)
		end
		expect(each).toEqual({ Common = 30, Rare = 120, Epic = 450, Legendary = 1800, Mythic = 6000, Secret = 15000 })
		expect(Agency.sellBack({ Level = 9, XP = 30, Copies = 3 }, "Rare", Config)).toBe(360)
		expect(Agency.sellBack(nil, "Rare", Config)).toBe(0)
		-- never a profit: an Agency buy always costs more than its sell-back
		for _, rarity in { "Common", "Rare", "Epic" } do
			expect(Agency.price(Config, rarity, 1, 0.15) > Agency.sellBack({ Copies = 1 }, rarity, Config)).toBe(true)
		end
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- The money panels' calm UI (T3: UI direction §4 #7-8, R0; memory-20261117-007 and -006). UI/Shop and
-- UI/AgencyPanel's PURE blocks, loaded on their own with UI/Icons handed in (Pure.use), and the four T3 files'
-- calm-rule counts locked at 0 (tests/uirules ratchet: a deliberate line carries "uirules: allow <Rule>").
------------------------------------------------------------------------------------------------------------------

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local UiRules = require("./uirules")
local NurseLogic = require("../src/shared/Logic/Nurse")
local RebirthLogic = require("../src/shared/Logic/Rebirth")
local TreeLogic = require("../src/shared/Logic/Tree")
local Levels = require("../src/shared/Data/Levels")
local Rooms = require("../src/shared/Data/Rooms")
local Decor = require("../src/shared/Data/Decor")
-- Data/Stations needs Roblox (its colours): the names the room notes read, as Data/Stations has them.
local Stations = {
	Remedy = { Name = "Dispensary" },
	Plaster = { Name = "Plasters" },
	Ice = { Name = "Ice Packs" },
	Bandage = { Name = "Bandages" },
	Cast = { Name = "Cast Table" },
	Bath = { Name = "Bath Foam" },
	Cocoa = { Name = "Cocoa Corner" },
}
local Rarities = require("../src/shared/Data/Rarities")

local Icons = UiRules.Icons

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
	local pure = luau.load(block, { debugName = path .. " (pure)", environment = env, injectGlobals = true })()
	pure.use(Icons)
	return pure
end

local ShopPure = pureBlock("src/client/UI/Shop.luau", { RebirthLogic = RebirthLogic, TreeLogic = TreeLogic })
local AgencyPure = pureBlock("src/client/UI/AgencyPanel.luau", { NurseLogic = NurseLogic })
local DATA = { Rooms = Rooms, Decor = Decor, Levels = Levels }

-- How many emoji a text draws, and the text without them.
local function emoji(text: string): number
	return Icons.count(text)
end

T.describe("Shop: only what you can use now (R0, Pure.visible)", function()
	test("a fresh Lv 1 save: Upgrades only, so there is no tab column at all", function()
		local fresh = { Level = 1, Cash = 0, Stars = 0, PlotIndex = 1, Rooms = {}, Decor = { Owned = {}, Placed = {} } }
		expect(ShopPure.visible(fresh, DATA, false)).toEqual({
			Upgrades = true,
			Rooms = false,
			Decor = false,
			Hospital = false,
		})
	end)

	test(
		"each tab arrives with its first thing: a room's ⭐ met, cash for the cheapest decor, the next level's ⭐",
		function()
			local cheapest = math.huge
			for _, id in Decor.Order do
				local price = Decor[id].Price
				if type(price) == "number" then
					cheapest = math.min(cheapest, price)
				end
			end
			local function save(fields: { [string]: any }): any
				local s = { Level = 1, Cash = 0, Stars = 0, PlotIndex = 1, Rooms = {}, Decor = { Owned = {} } }
				for key, value in fields do
					s[key] = value
				end
				return s
			end
			local firstRoomStars = math.huge
			for _, id in Rooms.Order do
				if Rooms[id].Price > 0 and (Rooms[id].Level or 1) == 1 and Rooms[id].Season == nil then
					firstRoomStars = math.min(firstRoomStars, Rooms[id].StarsNeeded)
				end
			end
			expect(ShopPure.visible(save({ Stars = firstRoomStars - 1 }), DATA).Rooms).toBe(false)
			expect(ShopPure.visible(save({ Stars = firstRoomStars }), DATA).Rooms).toBe(true)
			expect(ShopPure.visible(save({ Cash = cheapest - 1 }), DATA).Decor).toBe(false)
			expect(ShopPure.visible(save({ Cash = cheapest }), DATA).Decor).toBe(true)
			expect(ShopPure.visible(save({ Decor = { Owned = { Anything = true } } }), DATA).Decor).toBe(true)
			expect(ShopPure.visible(save({ Stars = Levels[2].Stars - 1 }), DATA).Hospital).toBe(false)
			expect(ShopPure.visible(save({ Stars = Levels[2].Stars }), DATA).Hospital).toBe(true)
			expect(ShopPure.visible(save({ Level = 2 }), DATA).Hospital).toBe(true)
			expect(ShopPure.visible(save({}), DATA, true).Hospital).toBe(true) -- a branch line shows it
		end
	)

	test("a rich save (Lv 5, rooms, decor) still shows every tab: nothing is lost", function()
		local rich = {
			Level = 5,
			Cash = 99999,
			Stars = 500,
			PlotIndex = 1,
			Rooms = { Bath = true },
			Decor = { Owned = { Anything = true } },
		}
		expect(ShopPure.visible(rich, DATA, true)).toEqual({
			Upgrades = true,
			Rooms = true,
			Decor = true,
			Hospital = true,
		})
	end)

	test(
		"the HUD can open the Shop straight on its Hospital tab, whatever the save (documented in the header)",
		function()
			local text = source("src/client/UI/Shop.luau")
			assert(string.find(text, 'ctx.fire("Open", "Shop", "Hospital")', 1, true), "the entry point is documented")
			-- Opening on a tab shows it first (selectTab reveals), then selects it; levelUpButton stays for pointers.
			assert(
				string.find(
					text,
					"local function selectTab(id: string)\n\t\tif pages[id] then\n\t\t\treveal(id)",
					1,
					true
				)
			)
			assert(string.find(text, "function Shop.levelUpButton(): TextButton?", 1, true))
			assert(
				string.find(text, 'selectTab(if type(tab) == "string" and pages[tab] then tab else current)', 1, true)
			)
		end
	)
end)

T.describe("Shop: calm rows, gates and the level-up", function()
	local function room(id: string): any
		local r = table.clone(Rooms[id])
		r.Id = id
		return r
	end
	local first, gated, winter = nil, nil, nil
	for _, id in Rooms.Order do
		local r = Rooms[id]
		if r.Price > 0 and r.Season == "Winter" and not winter then
			winter = id
		elseif r.Price > 0 and (r.Level or 1) > 1 and not gated then
			gated = id
		elseif r.Price > 0 and (r.Level or 1) == 1 and r.Season == nil and not first then
			first = id
		end
	end

	test("a room: its note in words, the price the only button, a gate is the note plus 🔒 alone", function()
		assert(first, "a Lv 1 room for sale")
		local r = room(first :: string)
		local base = { Level = 1, Stars = r.StarsNeeded, Cash = r.Price, Rooms = {} }
		local buy = ShopPure.roomRow(r, base, Stations)
		expect(buy.Style).toBe("Buy")
		expect(buy.Text).toBe(Icons.unit("Cash", ShopPure.short(r.Price)))
		expect(emoji(buy.Note)).toBe(0) -- "3 beds · 2 decor spots": words, no 🛏️🛏️🛏️ 🌸🌸
		expect(ShopPure.roomRow(r, { Level = 1, Stars = r.StarsNeeded, Cash = 0, Rooms = {} }, Stations).Style).toBe(
			"Poor"
		)
		local stars = ShopPure.roomRow(r, { Level = 1, Stars = 0, Cash = 1e9, Rooms = {} }, Stations)
		expect(stars.Text).toBe(Icons.State.Locked)
		expect(stars.Note).toBe("Needs " .. Icons.unit("Stars", tostring(r.StarsNeeded)))
		local built = ShopPure.roomRow(r, { Level = 1, Rooms = { [first] = true } }, Stations)
		expect(built.Style).toBe("Done")
		expect(built.Text).toBe(Icons.State.Done)
		if gated then
			local g = room(gated)
			local view = ShopPure.roomRow(g, { Level = 1, Stars = 999, Cash = 1e9, Rooms = {} }, Stations)
			expect(view.Note).toBe(Icons.needs(g.Level))
			expect(view.Text).toBe(Icons.State.Locked)
		end
		if winter then
			-- out of season a winter room is not listed at all (no "Soon" row)
			expect(ShopPure.roomRow(room(winter), { Level = 5, Stars = 999, IsWinter = false }, Stations).Hidden).toBe(
				true
			)
			expect(ShopPure.roomRow(room(winter), { Level = 5, Stars = 999, IsWinter = true }, Stations).Hidden).toBe(
				false
			)
		end
	end)

	test(
		"room notes and level facts are words: '3 beds · 2 decor spots', '3 exam bays · 3 ward beds · 2-step plans'",
		function()
			expect(ShopPure.roomNote({ Stations = {}, Beds = 3, DecorSlots = 2 }, Stations)).toBe(
				"3 beds · 2 decor spots"
			)
			expect(ShopPure.roomNote({ Stations = {}, Beds = 1, DecorSlots = 1 }, Stations)).toBe(
				"1 bed · 1 decor spot"
			)
			expect(ShopPure.roomNote({ Stations = {}, Beds = 2, DecorSlots = 2, Adds = "+2 exam bays" }, Stations)).toBe(
				"+2 exam bays · 2 decor spots"
			)
			expect(ShopPure.levelFacts(Levels[1])).toBe("2 exam bays")
			expect(ShopPure.levelFacts(Levels[2])).toBe("3 exam bays · 3 ward beds · 2-step plans")
			for level = 1, #Levels do
				expect(emoji(ShopPure.levelFacts(Levels[level]))).toBe(0)
			end
			for _, id in Rooms.Order do
				expect(emoji(ShopPure.roomNote(Rooms[id], Stations))).toBe(0)
			end
		end
	)

	test("upgrades: the level in words, MAX when done, a gate as the note with 🔒 on the button", function()
		local open = ShopPure.upgradeRow(1, 3, 500, "Carry one more", true, "")
		expect(open).toEqual({
			Style = "Buy",
			Text = Icons.unit("Cash", "500"),
			Note = "Lv 1/3 · Carry one more",
			Hidden = false,
		})
		expect(ShopPure.upgradeRow(3, 3, nil, "Carry one more", true, "").Text).toBe(Icons.State.Done)
		local gate = ShopPure.upgradeRow(0, 3, 100, "Patients rest faster", false, "Needs 🏥 Lv 2")
		expect(gate.Text).toBe(Icons.State.Locked)
		expect(gate.Note).toBe("Needs 🏥 Lv 2")
	end)

	test("Level up shows ⭐ and 💰 clearly and says why it can't: 'Needs ⭐ 15', the price on grey", function()
		local next2 = Levels[2]
		local short = ShopPure.levelUp({ PlotIndex = 1, Stars = 9, Cash = 1e9 }, next2)
		expect(short.Style).toBe("Locked")
		expect(short.Text).toBe("Needs " .. Icons.unit("Stars", tostring(next2.Stars)))
		expect(short.Stars).toBe("9 / " .. next2.Stars)
		expect(short.StarsMet).toBe(false)
		expect(short.Cash).toBe(ShopPure.short(next2.Cash))
		local poor = ShopPure.levelUp({ PlotIndex = 1, Stars = next2.Stars, Cash = 0 }, next2)
		expect(poor.Style).toBe("Poor")
		expect(poor.Text).toBe(Icons.unit("Cash", ShopPure.short(next2.Cash)))
		expect(poor.Stars).toBe(tostring(next2.Stars))
		local ready = ShopPure.levelUp({ PlotIndex = 1, Stars = next2.Stars, Cash = next2.Cash }, next2)
		expect(ready.Style).toBe("Buy")
		expect(ready.Text).toBe("Level up")
		expect(ShopPure.levelUp({ Stars = 99, Cash = 1e9 }, next2).Text).toBe("No clinic yet")
		expect(ShopPure.levelUp({}, nil)).toBeNil()
		-- every button text: one emoji at most (a Unit with its number), never a lone sentence emoji
		for _, view in { short, poor, ready } do
			assert(emoji(view.Text) <= 1, view.Text)
		end
	end)

	test("the Lv 2 card's six unlock chips wrap cleanly at 568 x 320 (4 rows at most) and 1280 x 720 (3)", function()
		expect(#Levels[2].Unlocks).toBe(6)
		-- The page: the modal at 94% of the screen up to its 680 px MaxSize, its 16 px panel padding each side, the tab
		-- column (88 + 4 + 4) and its 8 px gap, the page's 12 px scroll margin, and the card's 12 px padding each side.
		local function pageWidth(screen: number): number
			return math.min(math.floor(screen * 0.94), 680) - 16 * 2 - (88 + 8) - 8 - 12 - 12 * 2
		end
		local phone, desktop = pageWidth(568), pageWidth(1280)
		expect(phone > 300).toBe(true)
		for level = 2, #Levels do
			local texts = Levels[level].Unlocks
			for _, text in texts do
				assert(ShopPure.chipWidth(text) <= phone, "chip wider than the phone page: " .. text)
				assert(emoji(text) == 1, "one Art emoji per chip: " .. text)
			end
			assert(ShopPure.chipRows(texts, phone, 8) <= 4, "Lv " .. level .. " chips take more than 4 rows on a phone")
			assert(ShopPure.chipRows(texts, desktop, 8) <= 3, "Lv " .. level .. " chips take more than 3 rows at 1280")
		end
		-- the chip row really wraps (UIListLayout.Wraps), so it never runs off the card
		assert(string.find(source("src/client/UI/Shop.luau"), "chipList.Wraps = true", 1, true))
	end)

	test("the source: a title in words, the cash meta as a Unit, no 'Soon' row, nothing loud, nothing Robux", function()
		local text = source("src/client/UI/Shop.luau")
		assert(string.find(text, 'Title = "Shop",', 1, true), "the title is words only")
		assert(string.find(text, "modal.setMeta(Hud.format(state.Cash or 0), Icons.Unit.Cash)", 1, true))
		expect(string.find(text, '"❄️', 1, true)).toBeNil() -- no "❄️ Soon" row or note
		expect(string.find(text, "Robux", 1, true) ~= nil).toBe(true) -- only the header's "Nothing here is Robux"
		expect(string.find(text, "MarketplaceService", 1, true)).toBeNil()
		expect(string.find(text, "Kit.shine(", 1, true)).toBeNil()
	end)
end)

T.describe("Agency panel: calm cards and confirms", function()
	local slot = { Slot = 1, NurseId = "PuffPup", Rarity = "Common", Price = 150, Bought = false, Personal = false }

	test("one button per card: the price, ✅, 🔒, 'Roster full' or 'MAX' (one emoji at most)", function()
		expect(AgencyPure.calmButton("Ready", slot)).toBe(Icons.unit("Cash", "150"))
		expect(AgencyPure.calmButton("Poor", { Price = 2250 })).toBe(Icons.unit("Cash", "2,250"))
		expect(AgencyPure.calmButton("Bought", slot)).toBe(Icons.State.Done)
		expect(AgencyPure.calmButton("Gate", { Gate = "🏥 Lv 3" })).toBe(Icons.State.Locked)
		expect(AgencyPure.calmButton("Full", slot)).toBe("Roster full")
		expect(AgencyPure.calmButton("Max", slot)).toBe("MAX")
		expect(AgencyPure.gateNote("🏥 Lv 3")).toBe("Needs 🏥 Lv 3")
		expect(AgencyPure.gateNote(nil)).toBe("")
	end)

	test("the confirms: the verb as a word title, the question with its price, the verb alone on Yes", function()
		for _, id in Nurses.Order do
			local nurse = Nurses[id]
			local hire = AgencyPure.confirmSpec("Hire", nurse.Icon, nurse.Name, 1, 150, nurse.Rarity)
			expect(hire.Title).toBe("Hire?")
			expect(hire.Yes).toBe("Hire")
			for _, level in { 1, 2 } do
				local sell = AgencyPure.confirmSpec("Sell", nurse.Icon, nurse.Name, level, 30, nurse.Rarity)
				expect(sell.Title).toBe("Sell?")
				expect(sell.Yes).toBe(if sell.Hold > 0 then "Hold to sell" else "Sell")
				expect(emoji(sell.Title) + emoji(sell.Yes)).toBe(0)
			end
		end
	end)

	test("the Sell row in words: 'Lv 7 · 2 copies · You get 💰 30'; Listed and Stays say so", function()
		expect(AgencyPure.sellFact(7, 2, false, "Sell", 30)).toBe(
			"Lv 7 · 2 copies · You get " .. Icons.unit("Cash", "30")
		)
		expect(AgencyPure.sellFact(1, 1, true, "Listed", nil)).toBe("Lv 1 · resting · on the Market")
		expect(AgencyPure.sellFact(3, 1, false, "Stays", nil)).toBe("Lv 3 · stays with you")
		expect(AgencyPure.sellButton("Sell")).toBe("Sell")
		expect(AgencyPure.sellButton("Listed")).toBe("Listed")
		expect(AgencyPure.sellButton("None")).toBe(Icons.State.Waiting)
	end)

	test("odds stay fully visible (red line 3): every rarity it stocks, its word and the server's number", function()
		local odds = Agency.odds(Config)
		local spec = AgencyPure.oddsSpec(odds, Rarities, AgencyPure.oddsNotes(odds, 3, 300))
		local stocked = 0
		for _, value in odds do
			if value > 0 then
				stocked += 1
			end
		end
		expect(#spec.Rows).toBe(stocked)
		for _, row in spec.Rows do
			expect(type(row.Icon) == "string" and type(row.Name) == "string" and row.Percent > 0).toBe(true)
		end
		-- the panel's Odds link is a Quiet text button one tap away; the Agency sells for cash only
		local text = source("src/client/UI/AgencyPanel.luau")
		assert(string.find(text, 'Text = "Odds",', 1, true), "the Odds link")
		expect(string.find(text, "MarketplaceService", 1, true)).toBeNil()
	end)
end)

T.describe("T3 money panels: the calm rules (tests/uirules ratchet)", function()
	test(
		"Shop, AgencyPanel, MarketPanel and BeltView: 0 on every calm rule (deliberate lines carry the allow)",
		function()
			local files = {
				"src/client/UI/Shop.luau",
				"src/client/UI/AgencyPanel.luau",
				"src/client/UI/MarketPanel.luau",
				"src/client/UI/BeltView.luau",
			}
			local over = UiRules.ratchet(files, {})
			assert(#over == 0, "\n" .. table.concat(over, "\n"))
			local old = UiRules.check(files)
			assert(#old == 0, "\n" .. UiRules.format(old))
		end
	)
end)
