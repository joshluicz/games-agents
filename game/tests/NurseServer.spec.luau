--!nocheck
-- The Nurses server's pure helpers (depth update T3): the three files compile, and the PURE-BEGIN..PURE-END
-- blocks of Server/Nurses and Server/NurseBelt, loaded on their own (the rest needs Roblox), are tested against
-- the real Logic/Belt, Logic/Nurse, Data/Nurses and Data/Rarities. Run from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local ROOT = "src/server/"
local BeltLogic = require("../src/shared/Logic/Belt")
local NurseLogic = require("../src/shared/Logic/Nurse")
local NursesData = require("../src/shared/Data/Nurses")
local Rarities = require("../src/shared/Data/Rarities")

local function source(path: string): string
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("can't find " .. path .. " (run from game/)")
end

local function pureBlock(name: string, env: { [string]: any }): any
	local text = source(ROOT .. name)
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to, name .. ": no PURE block")
	local block = string.sub(text, from, to - 1) .. "\nreturn Pure\n"
	local chunk = luau.load(block, { debugName = name .. ":Pure", environment = env, injectGlobals = true })
	return chunk()
end

-- The real Config's belt numbers (tests/config.luau loads Shared/Config with a Vector3 stub), so these rules run on
-- what ships.
local Config = require("./config")
local CFG = { Belt = Config.Belt, Nurses = { MaxLevel = Config.Nurses.MaxLevel } }

T.describe("compile", function()
	for _, name in { "Nurses.luau", "NurseBelt.luau", "NurseBuilder.luau" } do
		test(name, function()
			local ok, err = pcall(luau.compile, source(ROOT .. name))
			expect(ok).toBe(true)
			if not ok then
				error(err)
			end
		end)
	end
end)

local NP = pureBlock("Nurses.luau", {})
local BP = pureBlock("NurseBelt.luau", { BeltLogic = BeltLogic })

T.describe("Nurses.Pure", function()
	test("without is a multiset difference, order kept", function()
		expect(NP.without({ "Potion", "Plaster", "Potion", "Cocoa" }, { "Potion", "Cocoa" })).toEqual({
			"Plaster",
			"Potion",
		})
		expect(NP.without({ "Potion" }, {})).toEqual({ "Potion" })
		expect(NP.without({}, { "Potion" })).toEqual({})
	end)

	test("spare finds the oldest item the line doesn't need", function()
		expect(NP.spare({ "Cocoa", "Potion" }, { "Potion" })).toBe(1)
		expect(NP.spare({ "Potion", "Potion" }, { "Potion" })).toBe(2)
		expect(NP.spare({ "Potion", "Plaster" }, { "Plaster", "Potion" })).toBeNil()
		expect(NP.spare({}, {})).toBeNil()
	end)

	test("trayAdd appends while there's room", function()
		local tray, added = NP.trayAdd({ "Potion" }, "Plaster", 4, {})
		expect(added).toBe(true)
		expect(tray).toEqual({ "Potion", "Plaster" })
	end)

	test("trayAdd on a full tray swaps the oldest unneeded item", function()
		local tray, added = NP.trayAdd(
			{ "Cocoa", "Potion", "Potion", "Plaster" },
			"Bubbles",
			4,
			{ "Potion", "Plaster" }
		)
		expect(added).toBe(true)
		expect(tray).toEqual({ "Potion", "Potion", "Plaster", "Bubbles" })
	end)

	test("trayAdd refuses a tray full of needed items, and never grows past max", function()
		local full = { "Potion", "Plaster", "Potion", "Cocoa" }
		local tray, added = NP.trayAdd(full, "Bubbles", 4, { "Potion", "Plaster", "Potion", "Cocoa" })
		expect(added).toBe(false)
		expect(tray).toEqual(full)
		expect(#full).toBe(4) -- the input isn't changed
	end)

	test("trayTake removes the oldest copy only", function()
		local tray, taken = NP.trayTake({ "Potion", "Plaster", "Potion" }, "Potion")
		expect(taken).toBe(true)
		expect(tray).toEqual({ "Plaster", "Potion" })
		local same, none = NP.trayTake({ "Plaster" }, "Cocoa")
		expect(none).toBe(false)
		expect(same).toEqual({ "Plaster" })
	end)

	test("pickMake: the first needed item not covered, that the plot can make", function()
		local can = { Potion = true, Plaster = true }
		expect(NP.pickMake({ "Bubbles", "Potion", "Plaster" }, {}, can, {}, 4)).toBe("Potion")
		-- the tray already holds a Potion: the next one is the Plaster
		expect(NP.pickMake({ "Potion", "Plaster" }, { "Potion" }, can, { "Potion" }, 4)).toBe("Plaster")
		-- two Potions needed, one in the tray: make the second
		expect(NP.pickMake({ "Potion", "Potion" }, { "Potion" }, can, { "Potion" }, 4)).toBe("Potion")
		-- everything covered (tray, another Maker, the owner's carry)
		expect(NP.pickMake({ "Potion", "Plaster" }, { "Potion", "Plaster" }, can, {}, 4)).toBeNil()
		-- nothing needed
		expect(NP.pickMake({}, {}, can, {}, 4)).toBeNil()
		-- needed, but no station makes it here
		expect(NP.pickMake({ "Cocoa" }, {}, can, {}, 4)).toBeNil()
	end)

	test("pickMake waits when the tray is full of needed items", function()
		local can = { Potion = true, Plaster = true }
		local tray = { "Potion", "Potion", "Plaster", "Plaster" }
		local needs = { "Potion", "Potion", "Plaster", "Plaster", "Potion" }
		expect(NP.pickMake(needs, tray, can, tray, 4)).toBeNil()
		-- one tray item is spare: it can make (the deposit swaps the spare out)
		local spareTray = { "Cocoa", "Potion", "Plaster", "Plaster" }
		expect(NP.pickMake({ "Potion", "Plaster", "Plaster", "Potion" }, spareTray, can, spareTray, 4)).toBe("Potion")
	end)

	test("canHeal: the tray holds something the front patient needs", function()
		expect(NP.canHeal({ "Bubbles", "Potion" }, { "Potion" })).toBe(true)
		expect(NP.canHeal({ "Bubbles" }, { "Potion" })).toBe(false)
		expect(NP.canHeal({}, { "Potion" })).toBe(false)
		expect(NP.canHeal({ "Potion" }, {})).toBe(false)
	end)

	test("onDuty: Equipped in order, unique, known, cut to the slots", function()
		local known = function(id)
			return id ~= "Ghost"
		end
		expect(NP.onDuty({ "A", "Ghost", "B", "A", "C" }, known, 2)).toEqual({ "A", "B" })
		expect(NP.onDuty({ "A", 5, "B" }, known, 5)).toEqual({ "A", "B" })
		expect(NP.onDuty(nil, known, 3)).toEqual({})
		expect(NP.onDuty({ "A" }, known, 0)).toEqual({})
	end)

	test("level: clamped 1..max, junk -> 1", function()
		expect(NP.level({ Level = 3, Copies = 3 }, 5)).toBe(3)
		expect(NP.level({ Level = 9 }, 5)).toBe(5)
		expect(NP.level({ Level = 0 }, 5)).toBe(1)
		expect(NP.level({ Level = 0 / 0 }, 5)).toBe(1)
		expect(NP.level(nil, 5)).toBe(1)
		expect(NP.level({ Level = 2.7 }, 5)).toBe(2)
	end)

	test("cash: thousands commas", function()
		expect(NP.cash(0)).toBe("0")
		expect(NP.cash(100)).toBe("100")
		expect(NP.cash(1500)).toBe("1,500")
		expect(NP.cash(12345)).toBe("12,345")
		expect(NP.cash(100000)).toBe("100,000")
		expect(NP.cash(1234567)).toBe("1,234,567")
		expect(NP.cash(-1500)).toBe("-1,500")
	end)
end)

T.describe("NurseBelt.Pure", function()
	test("rarities match Data/Rarities and Logic/Belt", function()
		expect(BP.RARITIES).toEqual(Rarities.Order)
		expect(BP.RARITIES).toEqual(BeltLogic.RARITIES)
	end)

	test("percent formats every odd the sign prints", function()
		expect(BP.percent(70)).toBe("70%")
		expect(BP.percent(39.5)).toBe("39.5%")
		expect(BP.percent(38.5)).toBe("38.5%")
		expect(BP.percent(0.5)).toBe("0.5%")
		expect(BP.percent(1)).toBe("1%")
		expect(BP.percent(0)).toBe("–")
		expect(BP.percent(0 / 0)).toBe("–")
		-- every odd in every state formats without long decimals
		for _, night in { false, true } do
			for _, golden in { false, true } do
				for rarity, value in BeltLogic.odds(CFG, night, golden) do
					local text = BP.percent(value)
					expect(#text <= 6).toBe(true)
					if value > 0 then
						expect(tonumber(string.sub(text, 1, -2))).toBeCloseTo(value, 1)
					end
					local _ = rarity
				end
			end
		end
	end)

	test("status line, 6 words or fewer", function()
		expect(BP.status(false, false, 2)).toBe("☀️ Day odds")
		expect(BP.status(true, false, 2)).toBe("🌙 Night Rush! Rare+ ×2")
		expect(BP.status(false, true, 2)).toBe("👑 Golden Hour!")
		expect(BP.status(true, true, 2)).toBe("👑 Golden Night Rush!")
	end)

	test("afterHire: a Common or Rare hire that empties the belt brings the next in ReplaceSeconds", function()
		local soon = 100 + CFG.Belt.ReplaceSeconds
		expect(BP.afterHire(140, 100, "Common", CFG, 0)).toBe(soon)
		expect(BP.afterHire(140, 100, "Rare", CFG, 0)).toBe(soon)
		expect(BP.afterHire(140, 100, "Epic", CFG, 0)).toBe(140) -- an Epic+ is never replaced early
		expect(BP.afterHire(101, 100, "Common", CFG, 0)).toBe(101) -- never later than it was due
	end)

	test("afterHire: while other nurses still ride, the belt keeps its 40 s cadence", function()
		expect(BP.afterHire(140, 100, "Common", CFG, 1)).toBe(140)
		expect(BP.afterHire(140, 100, "Rare", CFG, 2)).toBe(140)
	end)

	test("gateLine: the sign says who may hire Epic and up", function()
		expect(BP.gateLine(3)).toBe("🏥 Epic+ hire from Lv 3")
		expect(BP.gateLine(1)).toBe("")
		local words = 0
		for _ in string.gmatch(BP.gateLine(3), "%S+") do
			words += 1
		end
		expect(words <= 6).toBe(true)
	end)

	test("hiredShout: Legendary and up", function()
		expect(BP.hiredShout("Common")).toBe(false)
		expect(BP.hiredShout("Epic")).toBe(false)
		expect(BP.hiredShout("Legendary")).toBe(true)
		expect(BP.hiredShout("Mythic")).toBe(true)
		expect(BP.hiredShout("Secret")).toBe(true)
		expect(BP.hiredShout("Junk")).toBe(false)
	end)

	test("golden: the natural window, or a forced one", function()
		local active, s, e = BP.golden(CFG, 1210, nil)
		expect(active).toBe(true)
		expect(s).toBe(1200)
		expect(e).toBe(1320)
		active, s, e = BP.golden(CFG, 50, nil)
		expect(active).toBe(false)
		expect(s).toBe(1200)
		-- forced at uptime 50: on for GoldenSeconds, then the natural schedule again
		active, s, e = BP.golden(CFG, 60, 50)
		expect(active).toBe(true)
		expect(s).toBe(50)
		expect(e).toBe(170)
		active = BP.golden(CFG, 171, 50)
		expect(active).toBe(false)
	end)

	test("forced: Studio BeltForce, but the pity still wins over a Common", function()
		expect(BP.forced("Mythic", false)).toBe("Mythic")
		expect(BP.forced("Common", false)).toBe("Common")
		expect(BP.forced("Common", true)).toBeNil()
		expect(BP.forced("Rare", true)).toBe("Rare")
		expect(BP.forced("Junk", false)).toBeNil()
		expect(BP.forced(5, false)).toBeNil()
		expect(BP.forced(nil, false)).toBeNil()
	end)

	test("15 forced Commons, then the pity gives a Rare+", function()
		local dry = 0
		local rolled = {}
		local pityAt = CFG.Belt.PityArrivals + 1
		expect(pityAt).toBe(16)
		for _ = 1, pityAt do
			local pity = BeltLogic.pityDue(dry, CFG)
			local rarity = BP.forced("Common", pity) or BeltLogic.roll(BeltLogic.odds(CFG, false, false), 0, pity)
			table.insert(rolled, rarity)
			dry = BeltLogic.afterArrival(dry, rarity)
		end
		for i = 1, pityAt - 1 do
			expect(rolled[i]).toBe("Common")
		end
		expect(BeltLogic.isRarePlus(rolled[pityAt])).toBe(true)
	end)

	test("event: which odds rolled it", function()
		expect(BP.event(false, false)).toBe("")
		expect(BP.event(true, false)).toBe("NightRush")
		expect(BP.event(false, true)).toBe("GoldenHour")
		expect(BP.event(true, true)).toBe("GoldenHour")
	end)
end)

T.describe("contract numbers the T3 code relies on", function()
	test("every rarity has a nurse to pick", function()
		for _, rarity in Rarities.Order do
			expect(BeltLogic.pick(NursesData, rarity, 0.5) ~= nil).toBe(true)
		end
	end)

	test("the journal: hiring every Common makes exactly the Common set due", function()
		local index = {}
		for _, id in NursesData.Order do
			if NursesData[id].Rarity == "Common" then
				NurseLogic.mark(index, id, "Hired")
			end
		end
		expect(NurseLogic.setsDue(index, NursesData, Rarities, {})).toEqual({ "Common" })
		expect(NurseLogic.setsDue(index, NursesData, Rarities, { Common = true })).toEqual({})
	end)

	test("every journal reward decor is a real Decor id (source check)", function()
		local decor = source("src/shared/Data/Decor.luau")
		for _, rarity in Rarities.Order do
			local id = Rarities[rarity].Journal.Decor
			expect(string.find(decor, "\n\t" .. id .. " = {", 1, true) ~= nil).toBe(true)
		end
	end)
end)
