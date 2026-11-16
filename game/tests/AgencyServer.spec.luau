--!nocheck
-- The Nurse Agency and the belt's Progression v2 rules (build plan §B3.1, §C T3). Server/Agency, Server/NurseBelt,
-- UI/AgencyPanel and UI/BeltView compile, and their PURE-BEGIN..PURE-END blocks (loaded on their own: the rest needs
-- Roblox) are tested against the real Logic/Agency, Logic/Belt, Logic/Nurse, Data/Nurses and Config:
--   · AgencyBuy's checks in order: a stale slot, the wrong nurse, a wrong `expect`, a double buy in one restock, an
--     in-flight buy, the gates, a full roster, the level cap, cash, the cooldown, and a buy after the restock
--   · SellNurse's: not yours, listed on the Market, rebirth-only (FounderFennec), a wrong `expect`, the cooldown
--   · 🍀 Lucky Stock: the same nurses for the same (player, restock), however often you ask
--   · the odds shown are the odds rolled (AgencyView.Odds is Logic/Agency.odds; 20,000 stocks land on 70/26/4)
--   · the belt: Bargain prices agree server and client, the sign's gate lines, the new hire states
-- Run from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local AgencyLogic = require("../src/shared/Logic/Agency")
local BeltLogic = require("../src/shared/Logic/Belt")
local NurseLogic = require("../src/shared/Logic/Nurse")
local TutorialLogic = require("../src/shared/Logic/Tutorial")
local Nurses = require("../src/shared/Data/Nurses")
local Rarities = require("../src/shared/Data/Rarities")
local Config = require("./config")

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

local function words(text: string): number
	local n = 0
	for _ in string.gmatch(text, "%S+") do
		n += 1
	end
	return n
end

T.describe("compile", function()
	for _, path in
		{
			"src/server/Agency.luau",
			"src/server/NurseBelt.luau",
			"src/client/UI/AgencyPanel.luau",
			"src/client/UI/BeltView.luau",
		}
	do
		test(path, function()
			local ok, err = pcall(luau.compile, source(path))
			expect(ok).toBe(true)
			if not ok then
				error(err)
			end
		end)
	end
end)

local AP = pureBlock("src/server/Agency.luau", {
	AgencyLogic = AgencyLogic,
	BeltLogic = BeltLogic,
	NurseLogic = NurseLogic,
})
local BP = pureBlock("src/server/NurseBelt.luau", { BeltLogic = BeltLogic })
local PP = pureBlock("src/client/UI/AgencyPanel.luau", { NurseLogic = NurseLogic })
local VP = pureBlock("src/client/UI/BeltView.luau", {
	BeltLogic = BeltLogic,
	NurseLogic = NurseLogic,
	TutorialLogic = TutorialLogic,
})

local function isKnown(id: string): boolean
	return type(id) == "string" and type(rawget(Nurses, id)) == "table"
end

local USER = 311718381
local SHARED = { "PuffPup", "CuddleCub", "CloudKoala", "MintMouse" } -- Common, Rare, Epic, Common

local function save(fields: any?): any
	local data = { Cash = 100000, Level = 3, Nurses = {}, Rebirth = { Count = 0 } }
	for key, value in fields or {} do
		data[key] = value
	end
	return data
end

-- The view the server builds for one player (Server/Agency's viewFor, minus Roblox).
local function viewOf(ledger: any, restock: number, data: any, extra: any?): any
	extra = extra or {}
	return AP.view({
		Restock = restock,
		Stock = extra.Stock or SHARED,
		Lucky = extra.Lucky or {},
		Roster = Nurses,
		Cfg = Config,
		Level = data.Level,
		Rebirths = data.Rebirth.Count,
		Bargain = extra.Bargain or 0,
		Nurses = data.Nurses,
		Bought = function(slot)
			return AP.isBought(ledger, USER, restock, slot)
		end,
	})
end

local function buy(
	view: any,
	data: any,
	slot: any,
	nurseId: any,
	expect_: any,
	extra: any?
): (boolean, string, number, boolean)
	extra = extra or {}
	return AP.checkBuy({
		View = view,
		Slot = slot,
		NurseId = nurseId,
		Expect = expect_,
		Data = data,
		Cfg = Config,
		IsKnown = isKnown,
		Busy = extra.Busy == true,
		Now = extra.Now or 100,
		Last = extra.Last,
	})
end

T.describe("Agency.Pure: the view", function()
	test("4 slots with YOUR price, gates, the shown odds and the sell-back", function()
		local data = save({ Level = 1, Nurses = { PuffPup = { Level = 4, XP = 0, Copies = 2, Job = "" } } })
		local view = viewOf(AP.ledger(), 7, data)
		expect(view.Restock).toBe(7)
		expect(#view.Slots).toBe(4)
		for index, slot in view.Slots do
			expect(slot.Slot).toBe(index)
			expect(slot.NurseId).toBe(SHARED[index])
			expect(slot.Rarity).toBe(Nurses[SHARED[index]].Rarity)
			expect(slot.Price).toBe(AgencyLogic.price(Config, slot.Rarity, 1, 0))
			expect(slot.Bought).toBe(false)
			expect(slot.Personal).toBe(false)
		end
		expect(view.Slots[1].Price).toBe(150)
		expect(view.Slots[2].Price).toBe(600)
		expect(view.Slots[3].Price).toBe(2250)
		expect(view.Slots[3].Gate).toBe("🏥 Lv 3") -- Epic below hospital Lv 3
		expect(view.Slots[1].Gate).toBeNil()
		-- the odds shown are the very table the rolls use
		expect(view.Odds).toEqual(AgencyLogic.odds(Config))
		expect(view.Odds).toEqual({ Common = 70, Rare = 26, Epic = 4 })
		expect(view.SellBack).toEqual({ PuffPup = 60 }) -- 30 a copy, never level-scaled
	end)

	test("Bargain and your level change the price; rebirth-only and unknown nurses have no sell-back", function()
		local data = save({
			Level = 5,
			Nurses = {
				FounderFennec = { Level = 1, XP = 0, Copies = 1, Job = "" },
				Nobody = { Level = 1, XP = 0, Copies = 1, Job = "" },
				CloudKoala = { Level = 1, XP = 0, Copies = 1, Job = "" },
			},
		})
		local view = viewOf(AP.ledger(), 1, data, { Bargain = 0.15 })
		expect(view.Slots[1].Price).toBe(AgencyLogic.price(Config, "Common", 5, 0.15))
		expect(view.Slots[3].Gate).toBeNil()
		expect(view.SellBack).toEqual({ CloudKoala = 450 })
	end)

	test("🍀 Lucky Stock slots come after the shared ones, Personal, the same each time you ask", function()
		local lucky = AP.lucky(Nurses, Config, USER, 9, SHARED)
		expect(#lucky).toBe(Config.Agency.LuckySlots)
		for _ = 1, 5 do
			expect(AP.lucky(Nurses, Config, USER, 9, SHARED)).toEqual(lucky) -- a rejoin never re-rolls
		end
		local view = viewOf(AP.ledger(), 9, save(), { Lucky = lucky })
		expect(#view.Slots).toBe(6)
		expect(view.Slots[5].Slot).toBe(5)
		expect(view.Slots[5].Personal).toBe(true)
		expect(view.Slots[6].Personal).toBe(true)
		expect(view.Slots[5].NurseId).toBe(lucky[1])
		for _, id in lucky do
			expect(table.find(SHARED, id)).toBeNil()
		end
	end)
end)

T.describe("Agency.Pure.lucky: 🍀 Lucky Stock with the shown odds", function()
	local function rarityOf(id: string): string
		return Nurses[id].Rarity
	end

	test("the same nurses as Logic/Agency.personal whenever that one keeps the rolled rarities", function()
		local r = AgencyLogic.seeded(4242, 3000 * 8)
		local compared = 0
		for k = 0, 2999 do
			local shared = AgencyLogic.roll(Nurses, Config, table.move(r, k * 8 + 1, k * 8 + 8, 1, {}))
			local userId, restock = 1000 + k * 37, k % 50
			local mine = AP.lucky(Nurses, Config, userId, restock, shared)
			local logic = AgencyLogic.personal(Nurses, Config, userId, restock, shared)
			local same = #logic == #mine
			for index, id in logic do
				same = same and mine[index] ~= nil and rarityOf(mine[index]) == rarityOf(id)
			end
			if same then
				expect(mine).toEqual(logic)
				compared += 1
			end
		end
		expect(compared > 2400).toBe(true) -- the usual case
	end)

	test("200,000 own slots land on 70 / 26 / 4; never fewer than 2; never a repeat among your own", function()
		local N = 100000
		local r = AgencyLogic.seeded(777, N * 8)
		local counts = { Common = 0, Rare = 0, Epic = 0 }
		local total = 0
		for k = 0, N - 1 do
			local shared = AgencyLogic.roll(Nurses, Config, table.move(r, k * 8 + 1, k * 8 + 8, 1, {}))
			local mine = AP.lucky(Nurses, Config, 1000 + k, k, shared)
			assert(#mine == Config.Agency.LuckySlots, "a Lucky Stock slot went missing")
			assert(mine[1] ~= mine[2], "a nurse repeated among your own slots")
			for _, id in mine do
				counts[rarityOf(id)] += 1
				total += 1
			end
		end
		for rarity, odds in AgencyLogic.odds(Config) do
			expect(math.abs(counts[rarity] / total * 100 - odds) < 0.4).toBe(true)
		end
	end)

	test("a shared nurse repeats only when every nurse of the rolled rarity is in the shared stock", function()
		-- every Common is in the shared stock (5 Commons, so a 5-slot "stock" for the test)
		local commons = {}
		for _, id in Nurses.Order do
			if Nurses[id].Rarity == "Common" and Nurses[id].Source == nil then
				table.insert(commons, id)
			end
		end
		for k = 1, 400 do
			local mine = AP.lucky(Nurses, Config, k, k, commons)
			expect(#mine).toBe(2)
			for _, id in mine do
				expect(Nurses[id].Source).toBeNil()
				if table.find(commons, id) then
					expect(rarityOf(id)).toBe("Common") -- a repeat, of the rarity rolled
				end
			end
		end
		-- with room, never a repeat of the shared stock
		for k = 1, 400 do
			for _, id in AP.lucky(Nurses, Config, k, k, SHARED) do
				expect(table.find(SHARED, id)).toBeNil()
			end
		end
	end)
end)

T.describe("Agency.Pure: AgencyBuy's checks (§B3.1 order)", function()
	test("a good buy passes with the price to charge", function()
		local data = save()
		local view = viewOf(AP.ledger(), 3, data)
		local ok, message, price, refresh = buy(view, data, 2, "CuddleCub", 720) -- Rare at Lv 3: 400 x 1.2 x 1.5
		expect(ok).toBe(true)
		expect(message).toBe("")
		expect(price).toBe(720)
		expect(price).toBe(AgencyLogic.price(Config, "Rare", 3, 0))
		expect(refresh).toBe(false)
	end)

	test("junk slots and ids change nothing", function()
		local data = save()
		local view = viewOf(AP.ledger(), 3, data)
		for _, slot in { 0 / 0, 1.5, "1", math.huge, nil } do
			local ok, message, _, refresh = buy(view, data, slot, "PuffPup", 150)
			expect(ok).toBe(false)
			expect(message).toBe(AP.MSG.Oops)
			expect(refresh).toBe(false)
		end
		local ok, message = buy(view, data, 1, 42, 150)
		expect(ok).toBe(false)
		expect(message).toBe(AP.MSG.Oops)
	end)

	test("a stale slot or the wrong nurse: 'New nurses came!' and a fresh view", function()
		local data = save()
		local view = viewOf(AP.ledger(), 3, data)
		local price = view.Slots[1].Price
		local ok, message, _, refresh = buy(view, data, 9, "PuffPup", price)
		expect(ok).toBe(false)
		expect(message).toBe("New nurses came! Look again")
		expect(refresh).toBe(true)
		ok, message, _, refresh = buy(view, data, 1, "GoldieGryphlet", price)
		expect(ok).toBe(false)
		expect(message).toBe("New nurses came! Look again")
		expect(refresh).toBe(true)
	end)

	test("a wrong expect: 'Price changed!' and a fresh view (the client's price is only compared)", function()
		local data = save()
		local view = viewOf(AP.ledger(), 3, data)
		for _, wrong in { 1, view.Slots[1].Price - 1, view.Slots[1].Price + 1, 0 / 0 } do
			local ok, message, _, refresh = buy(view, data, 1, "PuffPup", wrong)
			expect(ok).toBe(false)
			expect(message).toBe("Price changed! Look again")
			expect(refresh).toBe(true)
		end
	end)

	test("a double buy in one restock is refused; a buy in flight waits; the next restock is buyable again", function()
		local ledger = AP.ledger()
		local data = save()
		local view = viewOf(ledger, 3, data)
		local price = view.Slots[1].Price
		expect((buy(view, data, 1, "PuffPup", price))).toBe(true)
		-- in flight (the server claims it before the grant)
		AP.setBusy(ledger, USER, 3, 1, true)
		expect(AP.isBusy(ledger, USER, 3, 1)).toBe(true)
		local ok, message = buy(view, data, 1, "PuffPup", price, { Busy = true })
		expect(ok).toBe(false)
		expect(message).toBe(AP.MSG.Wait)
		-- bought: marked only after the grant said yes
		AP.markBought(ledger, USER, 3, 1)
		AP.setBusy(ledger, USER, 3, 1, false)
		view = viewOf(ledger, 3, data)
		expect(view.Slots[1].Bought).toBe(true)
		ok, message = buy(view, data, 1, "PuffPup", price)
		expect(ok).toBe(false)
		expect(message).toBe("✅ You bought this one!")
		-- someone else's ledger entry is theirs alone
		expect(AP.isBought(ledger, USER + 1, 3, 1)).toBe(false)
		-- the next restock: the marks go, the slot is buyable again
		AP.prune(ledger, 4)
		expect(AP.isBought(ledger, USER, 3, 1)).toBe(false)
		view = viewOf(ledger, 4, data)
		expect(view.Slots[1].Bought).toBe(false)
		expect((buy(view, data, 1, "PuffPup", price))).toBe(true)
		-- a grant from the old restock landing late marks only the old key
		AP.markBought(ledger, USER, 3, 2)
		expect(viewOf(ledger, 4, data).Slots[2].Bought).toBe(false)
	end)

	test("the gates, the roster, the level cap, the cash and the cooldown, in that order", function()
		-- gate: an Epic below hospital Lv 3
		local low = save({ Level = 2 })
		local view = viewOf(AP.ledger(), 3, low)
		local ok, message = buy(view, low, 3, "CloudKoala", view.Slots[3].Price)
		expect(ok).toBe(false)
		expect(message).toBe("🏥 Lv 3 first!")
		-- roster full (3 nurses, none of these): a new one is refused, a copy of an owned one isn't
		local full = save({
			Nurses = {
				DewDuck = { Level = 1, XP = 0, Copies = 1, Job = "" },
				HumHamster = { Level = 1, XP = 0, Copies = 1, Job = "" },
				PuffPup = { Level = 2, XP = 0, Copies = 2, Job = "" },
			},
		})
		view = viewOf(AP.ledger(), 3, full)
		ok, message = buy(view, full, 2, "CuddleCub", view.Slots[2].Price)
		expect(ok).toBe(false)
		expect(message).toBe("Roster full: sell or list one")
		expect((buy(view, full, 1, "PuffPup", view.Slots[1].Price))).toBe(true)
		-- a copy at the level cap
		local capped = save({ Nurses = { PuffPup = { Level = 10, XP = 0, Copies = 9, Job = "" } } })
		view = viewOf(AP.ledger(), 3, capped)
		ok, message = buy(view, capped, 1, "PuffPup", view.Slots[1].Price)
		expect(ok).toBe(false)
		expect(message).toBe("Max level!")
		-- cash
		local poor = save({ Cash = 100 })
		view = viewOf(AP.ledger(), 3, poor)
		ok, message = buy(view, poor, 1, "PuffPup", view.Slots[1].Price)
		expect(ok).toBe(false)
		expect(message).toBe("Need 💰" .. AP.commas(view.Slots[1].Price - 100) .. " more!")
		-- the cooldown (Config.Agency.Cooldown)
		local data = save()
		view = viewOf(AP.ledger(), 3, data)
		ok, message = buy(view, data, 1, "PuffPup", view.Slots[1].Price, { Now = 100.5, Last = 100 })
		expect(ok).toBe(false)
		expect(message).toBe(AP.MSG.Wait)
		expect((buy(view, data, 1, "PuffPup", view.Slots[1].Price, { Now = 101.1, Last = 100 }))).toBe(true)
		-- every reply is 6 words or fewer
		for _, text in AP.MSG do
			expect(words(text) <= 6).toBe(true)
		end
	end)
end)

T.describe("Agency.Pure: SellNurse's checks", function()
	local function sell(data: any, nurseId: any, expect_: any, extra: any?): (boolean, string, number, boolean)
		extra = extra or {}
		return AP.checkSell({
			Data = data,
			NurseId = nurseId,
			Expect = expect_,
			Listed = extra.Listed == true,
			Roster = Nurses,
			Cfg = Config,
			Now = extra.Now or 100,
			Last = extra.Last,
		})
	end
	local data = save({
		Nurses = {
			BerryBat = { Level = 6, XP = 3, Copies = 3, Job = "" },
			FounderFennec = { Level = 1, XP = 0, Copies = 1, Job = "" },
		},
	})

	test("30% of the belt's base price per copy, never level-scaled", function()
		local ok, message, cash = sell(data, "BerryBat", 360)
		expect(ok).toBe(true)
		expect(message).toBe("")
		expect(cash).toBe(360)
	end)

	test("not yours, listed, rebirth-only, a wrong expect, the cooldown", function()
		local ok, message = sell(data, "PuffPup", 30)
		expect(ok).toBe(false)
		expect(message).toBe("That nurse isn't yours!")
		ok, message = sell(data, "Order", 30)
		expect(ok).toBe(false)
		expect(message).toBe("That nurse isn't yours!")
		ok, message = sell(data, 7, 30)
		expect(ok).toBe(false)
		expect(message).toBe(AP.MSG.Oops)
		ok, message = sell(data, "BerryBat", 360, { Listed = true })
		expect(ok).toBe(false)
		expect(message).toBe("🏷️ Unlist it first!")
		ok, message = sell(data, "FounderFennec", 0)
		expect(ok).toBe(false)
		expect(message).toBe("This one stays with you!")
		local refresh
		ok, message, _, refresh = sell(data, "BerryBat", 999)
		expect(ok).toBe(false)
		expect(message).toBe("Price changed! Look again")
		expect(refresh).toBe(true)
		ok, message = sell(data, "BerryBat", 360, { Now = 100.2, Last = 100 })
		expect(ok).toBe(false)
		expect(message).toBe(AP.MSG.Wait)
	end)

	test("never a profit: every Agency or belt buy costs more than its sell-back", function()
		for _, rarity in { "Common", "Rare", "Epic" } do
			for level = 1, 5 do
				local back = AgencyLogic.sellBack({ Copies = 1 }, rarity, Config)
				expect(AgencyLogic.price(Config, rarity, level, 0.5) > back).toBe(true)
				expect(BP.bargainPrice(BeltLogic.price(Config, rarity, level), 0.5) > back).toBe(true)
			end
		end
	end)
end)

T.describe("Agency.Pure: the kiosk check", function()
	test("near: within the reach in studs; junk is never near; the reply is 6 words or fewer", function()
		local kioskAt = { X = 11, Y = 2, Z = 12 }
		expect(AP.near({ X = 11, Y = 3, Z = 12 }, kioskAt, 15)).toBe(true)
		expect(AP.near({ X = 26, Y = 2, Z = 12 }, kioskAt, 15)).toBe(true) -- exactly 15
		expect(AP.near({ X = 26.1, Y = 2, Z = 12 }, kioskAt, 15)).toBe(false)
		expect(AP.near({ X = 11, Y = 2, Z = -200 }, kioskAt, 15)).toBe(false)
		for _, junk in { 0, "here", true, {}, { X = 0 / 0, Y = 0, Z = 0 }, { X = 1, Y = 2 } } do
			expect(AP.near(junk, kioskAt, 15)).toBe(false)
			expect(AP.near(kioskAt, junk, 15)).toBe(false)
		end
		expect(AP.near(nil, kioskAt, 15)).toBe(false)
		expect(AP.MSG.Far).toBe("🚶 Come closer!")
		expect(words(AP.MSG.Far) <= 6).toBe(true)
	end)

	test("it ships off: the 👩‍⚕️ panel opens the Agency and the Market from anywhere", function()
		expect(Config.KioskReach).toBe(0)
	end)
end)

T.describe("Agency: the odds shown are the odds rolled", function()
	test("20,000 stocks of 4 land on 70 / 26 / 4 and never Legendary+", function()
		local counts = { Common = 0, Rare = 0, Epic = 0 }
		local total = 0
		local r = AgencyLogic.seeded(20261116, 20000 * 8)
		for k = 0, 19999 do
			local r01s = table.move(r, k * 8 + 1, k * 8 + 8, 1, {})
			for _, id in AgencyLogic.roll(Nurses, Config, r01s) do
				local rarity = Nurses[id].Rarity
				expect(counts[rarity] ~= nil).toBe(true)
				counts[rarity] += 1
				total += 1
			end
		end
		expect(total).toBe(80000)
		for rarity, odds in AgencyLogic.odds(Config) do
			expect(math.abs(counts[rarity] / total * 100 - odds) < 0.75).toBe(true)
		end
	end)

	test("the panel's 🎲 shows the server's table as it is", function()
		local rows = PP.oddsRows(AgencyLogic.odds(Config))
		expect(rows).toEqual({
			{ Rarity = "Common", Odds = 70 },
			{ Rarity = "Rare", Odds = 26 },
			{ Rarity = "Epic", Odds = 4 },
		})
		expect(PP.percent(70)).toBe("70%")
		expect(PP.percent(4)).toBe("4%")
		expect(PP.percent(0.5)).toBe("0.5%")
		expect(PP.percent(0)).toBe("–")
		expect(PP.neverText(AgencyLogic.odds(Config))).toBe("🚫 Never Legendary+")
		expect(PP.neverText({ Common = 50, Secret = 50 })).toBeNil()
	end)

	test("'New nurses every 5 min', the same words on the kiosk and the panel (never a clock)", function()
		expect(AP.everyText(Config.Agency.RestockSeconds)).toBe("🔄 New nurses every 5 min")
		for _, seconds in { 60, 300, 90, 45, 0 / 0 } do
			expect(PP.everyText(seconds)).toBe(AP.everyText(seconds))
			expect(words(AP.everyText(seconds)) <= 6).toBe(true)
			expect(string.find(AP.everyText(seconds), ":", 1, true)).toBeNil()
		end
	end)
end)

T.describe("AgencyPanel.Pure", function()
	local slot = { Slot = 1, NurseId = "PuffPup", Rarity = "Common", Price = 150, Bought = false, Personal = false }

	test("a card's state in the server's order", function()
		local state = { Cash = 1000, Nurses = {}, Rebirth = { Count = 0 } }
		expect(PP.cardState(slot, state, Config, isKnown)).toBe("Ready")
		expect(PP.cardState(table.clone(slot), { Cash = 10, Nurses = {}, Rebirth = { Count = 0 } }, Config, isKnown)).toBe(
			"Poor"
		)
		local bought = table.clone(slot)
		bought.Bought = true
		expect(PP.cardState(bought, state, Config, isKnown)).toBe("Bought")
		local gated = table.clone(slot)
		gated.Gate = "🏥 Lv 3"
		expect(PP.cardState(gated, state, Config, isKnown)).toBe("Gate")
		local fullState = {
			Cash = 1000,
			Nurses = { DewDuck = { Level = 1 }, HumHamster = { Level = 1 }, MintMouse = { Level = 1 } },
			Rebirth = { Count = 0 },
		}
		expect(PP.cardState(slot, fullState, Config, isKnown)).toBe("Full")
		fullState.Rebirth.Count = 1 -- a rebirth adds a slot
		expect(PP.cardState(slot, fullState, Config, isKnown)).toBe("Ready")
		local maxed = { Cash = 1000, Nurses = { PuffPup = { Level = 10 } }, Rebirth = { Count = 0 } }
		expect(PP.cardState(slot, maxed, Config, isKnown)).toBe("Max")
		maxed.Rebirth.Count = 3 -- Lv 15 from R3
		expect(PP.cardState(slot, maxed, Config, isKnown)).toBe("Ready")
	end)

	test("buttons, confirms and the hold (6 words or fewer)", function()
		expect(PP.buttonText("Ready", slot)).toBe("Hire 💰150")
		expect(PP.buttonText("Bought", slot)).toBe("✅ Bought")
		expect(PP.buttonText("Gate", { Gate = "🏢 R1" })).toBe("🏢 R1")
		expect(PP.buttonText("Full", slot)).toBe("Roster full")
		expect(PP.buttonText("Max", slot)).toBe("⭐ MAX")
		expect(PP.buttonText("Poor", { Price = 2250 })).toBe("Hire 💰2,250")
		expect(PP.confirmText("Sell", "🐶", "Puff Pup", 7, 30)).toBe("Sell 🐶 Lv 7 for 💰30?")
		expect(PP.confirmText("Hire", "🐶", "Puff Pup", 1, 150)).toBe("Hire 🐶 Puff Pup for 💰150?")
		for _, id in Nurses.Order do
			local nurse = Nurses[id]
			expect(words(PP.confirmText("Hire", nurse.Icon, nurse.Name, 1, 1234567)) <= 6).toBe(true)
			expect(words(PP.confirmText("Sell", nurse.Icon, nurse.Name, 15, 1234567)) <= 6).toBe(true)
		end
		expect(PP.needsHold("Rare")).toBe(false)
		expect(PP.needsHold("Rare", 1)).toBe(false)
		expect(PP.needsHold("Epic")).toBe(true)
		expect(PP.needsHold("Secret")).toBe(true)
		expect(PP.needsHold("Junk")).toBe(false)
		-- a levelled Common or Rare is a hold too: its levels go for the flat sell-back
		expect(PP.needsHold("Common", 2)).toBe(true)
		expect(PP.needsHold("Common", 9)).toBe(true)
		expect(PP.needsHold("Rare", 0 / 0)).toBe(false)
	end)

	test("the Sell tab: your nurses in the Journal's order; listed, rebirth-only, priced", function()
		local nurses = {
			ToffeeFox = { Level = 1 },
			PuffPup = { Level = 3 },
			FounderFennec = { Level = 1 },
			Nobody = { Level = 1 },
		}
		local list = PP.sellList(nurses, Nurses)
		expect(list).toEqual({ "PuffPup", "ToffeeFox", "FounderFennec" })
		local sellBack = { PuffPup = 30, ToffeeFox = 450 }
		local listed = PP.listed({
			Listings = {
				{ Id = 1, Seller = USER, NurseId = "ToffeeFox" },
				{ Id = 2, Seller = USER + 1, NurseId = "PuffPup" },
			},
		}, USER)
		expect(listed).toEqual({ ToffeeFox = true })
		expect(PP.sellState("PuffPup", Nurses, sellBack, listed)).toBe("Sell")
		expect(PP.sellState("ToffeeFox", Nurses, sellBack, listed)).toBe("Listed")
		expect(PP.sellState("FounderFennec", Nurses, sellBack, listed)).toBe("Stays")
		expect(PP.sellState("Nobody", Nurses, sellBack, listed)).toBe("None")
		expect(PP.sellState("PuffPup", Nurses, nil, listed)).toBe("None")
		expect(PP.listed(nil, USER)).toEqual({})
	end)

	test("the price key follows level, rebirths, Bargain and Lucky Stock", function()
		local a = PP.priceKey({ Level = 2, Rebirth = { Count = 1 } }, { Bargain = 0.05, LuckyStock = false })
		expect(PP.priceKey({ Level = 2, Rebirth = { Count = 1 } }, { Bargain = 0.05, LuckyStock = false })).toBe(a)
		expect(PP.priceKey({ Level = 3, Rebirth = { Count = 1 } }, { Bargain = 0.05 }) ~= a).toBe(true)
		expect(PP.priceKey({ Level = 2, Rebirth = { Count = 1 } }, { Bargain = 0.1 }) ~= a).toBe(true)
		expect(PP.priceKey({ Level = 2, Rebirth = { Count = 1 } }, { Bargain = 0.05, LuckyStock = true }) ~= a).toBe(
			true
		)
		expect(PP.priceKey(nil, nil)).toBe("1|0|0|false")
	end)
end)

T.describe("the belt (Progression v2)", function()
	test("Bargain: the card's price is the price charged (server and client formulas agree)", function()
		for _, rarity in BeltLogic.RARITIES do
			for level = 1, 5 do
				for _, bargain in { 0, 0.05, 0.1, 0.15, 0.5, 2, -1, 0 / 0 } do
					local base = BeltLogic.price(Config, rarity, level)
					expect(VP.bargainPrice(base, bargain)).toBe(BP.bargainPrice(base, bargain))
				end
			end
		end
		expect(BP.bargainPrice(100, 0.15)).toBe(85)
		expect(BP.bargainPrice(1500, 0)).toBe(1500)
		expect(BP.bargainPrice(1500, 0 / 0)).toBe(1500)
		expect(BP.bargainPrice(0 / 0, 0.1)).toBe(0)
	end)

	test("the sign's gate lines: Lv 3 and R1, each 6 words or fewer", function()
		expect(BP.gateText(Config)).toBe("🏥 Epic+ from Lv 3 · 🏢 Mythic/Secret from R1")
		for _, line in BP.gateLines(Config) do
			expect(words(line) <= 6).toBe(true)
		end
		expect(BP.gateLines({ Belt = {} })).toEqual({})
		expect(BP.gateLines({ Belt = { MinRebirths = { Mythic = 1, Secret = 2 } } })).toEqual({
			"🏢 Mythic from R1",
			"🏢 Secret from R2",
		})
		expect(BP.gateMessage("🏥 Lv 3")).toBe("🏥 Lv 3 hospital first!")
		expect(BP.gateMessage("🏢 R1")).toBe("🏢 R1 first!")
		expect(VP.gateMessage("🏥 Lv 3")).toBe(BP.gateMessage("🏥 Lv 3"))
		expect(VP.gateMessage("🏢 R1")).toBe(BP.gateMessage("🏢 R1"))
		expect(VP.rebirthNote(Config, Rarities.Order)).toBe("🏢 Mythic/Secret from R1")
		expect(VP.rebirthNote({ Belt = {} }, Rarities.Order)).toBeNil()
	end)

	test("hire states: the R1 gate, a full roster, the R3 level cap", function()
		local cfg = Config
		-- Mythic at Lv 3 and R0: the rebirth gate (after the level gate)
		expect(VP.hireState(false, nil, cfg, 1e9, 100, 1, "Mythic", 3, 0)).toBe("Rebirth")
		expect(VP.hireState(false, nil, cfg, 1e9, 100, 1, "Mythic", 2, 0)).toBe("Level")
		expect(VP.hireState(false, nil, cfg, 1e9, 100, 1, "Mythic", 3, 1)).toBe("Ready")
		expect(VP.hireState(false, nil, cfg, 1e9, 100, 1, "Secret", 5, 0)).toBe("Rebirth")
		-- no rebirths given: no rebirth gate (Update 1's callers)
		expect(VP.hireState(false, nil, cfg, 1e9, 100, 1, "Mythic", 3)).toBe("Ready")
		-- a full roster: a new nurse is "Full" (before distance and cash); a copy isn't
		expect(VP.hireState(false, nil, cfg, 0, 100, 999, "Common", 1, 0, true)).toBe("Full")
		expect(VP.hireState(false, { Level = 2 }, cfg, 1e9, 100, 1, "Common", 1, 0, true)).toBe("Ready")
		-- the level cap follows rebirths: Lv 10 is MAX at R0, not at R3
		expect(VP.hireState(false, { Level = 10 }, cfg, 1e9, 100, 1, "Common", 1, 0)).toBe("Max")
		expect(VP.hireState(false, { Level = 10 }, cfg, 1e9, 100, 1, "Common", 1, 3)).toBe("Ready")
		expect(VP.hireState(false, { Level = 15 }, cfg, 1e9, 100, 1, "Common", 1, 3)).toBe("Max")
	end)

	test("the roster check, the gated price, the 🔭 chip and the house lamp", function()
		local full = {
			Nurses = { DewDuck = { Level = 1 }, HumHamster = { Level = 1 }, MintMouse = { Level = 1 } },
			Rebirth = { Count = 0 },
		}
		expect(VP.rosterFull(full, "PuffPup", Config, isKnown)).toBe(true)
		expect(VP.rosterFull(full, "DewDuck", Config, isKnown)).toBe(false)
		expect(VP.rosterFull({ Nurses = {}, Rebirth = { Count = 0 } }, "PuffPup", Config, isKnown)).toBe(false)
		expect(VP.gatedPrice(1800, "🏢 R1")).toBe("🏢 R1")
		expect(VP.gatedPrice(1800, nil)).toBe("💰1,800")
		expect(VP.scoutText(Rarities.Rare)).toBe("🔭 Next: " .. Rarities.Rare.Icon .. " " .. Rarities.Rare.Name)
		expect(VP.scoutText(nil)).toBeNil()
		expect(words(VP.scoutText(Rarities.Legendary)) <= 6).toBe(true)
		expect(VP.lampLevel(140, 100, 40)).toBe(0)
		expect(VP.lampLevel(120, 100, 40)).toBe(0.5)
		expect(VP.lampLevel(90, 100, 40)).toBe(1)
		expect(VP.lampLevel(nil, 100, 40)).toBe(0)
	end)
end)
