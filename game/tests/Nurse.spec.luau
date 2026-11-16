--!strict
-- Owned nurses: copies and levels, stats, equip slots and the Nurse Journal (depth-update build plan §B7).

local T = require("./expect")
local expect, test = T.expect, T.test

local Nurse = require("../src/shared/Logic/Nurse")
local Nurses = require("../src/shared/Data/Nurses")
local Rarities = require("../src/shared/Data/Rarities")

local CFG = {
	Nurses = {
		MaxLevel = 5,
		TrayMax = 4,
		MinSeconds = 3,
		FasterPerLevel = 0.08,
		MakerSeconds = { Common = 14, Rare = 12, Epic = 10, Legendary = 8, Mythic = 7, Secret = 6 },
		HealerSeconds = { Common = 16, Rare = 14, Epic = 12, Legendary = 10, Mythic = 9, Secret = 8 },
		CheerPatience = { Common = 0.1, Rare = 0.15, Epic = 0.2, Legendary = 0.3, Mythic = 0.35, Secret = 0.4 },
		CheerTip = { Common = 0.05, Rare = 0.08, Epic = 0.12, Legendary = 0.18, Mythic = 0.22, Secret = 0.25 },
		CheerPerLevel = 0.03,
	},
}

T.describe("Nurse", function()
	test("hire: a first copy, then each copy adds a level up to 5", function()
		local entry, isNew, up = Nurse.hire(nil, CFG)
		expect(entry).toEqual({ Level = 1, Copies = 1 })
		expect(isNew).toBe(true)
		expect(up).toBe(false)
		for level = 2, 5 do
			entry, isNew, up = Nurse.hire(entry, CFG)
			expect(entry.Level).toBe(level)
			expect(isNew).toBe(false)
			expect(up).toBe(true)
		end
		local before = entry
		entry, _, up = Nurse.hire(entry, CFG)
		expect(entry).toEqual({ Level = 5, Copies = 6 })
		expect(up).toBe(false)
		expect(before).toEqual({ Level = 5, Copies = 5 }) -- never changed in place
	end)

	test("stats: Makers and Healers get faster with rarity and level", function()
		expect(Nurse.stats("Maker", "Common", 1, CFG).Every).toBe(14)
		expect(Nurse.stats("Maker", "Common", 5, CFG).Every).toBeCloseTo(14 * 0.68)
		expect(Nurse.stats("Healer", "Secret", 1, CFG).Every).toBe(8)
		expect(Nurse.stats("Healer", "Secret", 5, CFG).Every).toBeCloseTo(5.44)
		expect(Nurse.stats("Maker", "Nope", 1, CFG).Every).toBeNil()
		local maker = Nurse.stats("Maker", "Rare", 1, CFG)
		expect(maker.Patience).toBe(1)
		expect(maker.Tip).toBe(1)
	end)

	test("stats: Cheerers add patience and tips", function()
		local cheer = Nurse.stats("Cheerer", "Epic", 1, CFG)
		expect(cheer.Every).toBeNil()
		expect(cheer.Patience).toBeCloseTo(1.2)
		expect(cheer.Tip).toBeCloseTo(1.12)
		local top = Nurse.stats("Cheerer", "Epic", 5, CFG)
		expect(top.Patience).toBeCloseTo(1.32)
		expect(top.Tip).toBeCloseTo(1.24)
	end)

	test("bestCheer takes the best, not the sum", function()
		local best = Nurse.bestCheer({
			{ Patience = 1.2, Tip = 1.05 },
			{ Patience = 1.1, Tip = 1.2 },
		})
		expect(best).toEqual({ Patience = 1.2, Tip = 1.2 })
		expect(Nurse.bestCheer({})).toEqual({ Patience = 1, Tip = 1 })
	end)

	test("equip needs a hired nurse and a free slot", function()
		local owned = { PuffPup = { Level = 1, Copies = 1 }, MintMouse = { Level = 2, Copies = 2 } }
		local ok, message, list = Nurse.equip({}, owned, "PuffPup", true, 1)
		expect(ok).toBe(true)
		expect(list).toEqual({ "PuffPup" })
		ok, message, list = Nurse.equip(list, owned, "MintMouse", true, 1)
		expect(ok).toBe(false)
		expect(message).toBe("All slots full!")
		expect(list).toEqual({ "PuffPup" })
		ok, message = Nurse.equip({}, owned, "BeanBear", true, 3)
		expect(ok).toBe(false)
		expect(message).toBe("Hire it first!")
		ok, _, list = Nurse.equip({ "PuffPup" }, owned, "PuffPup", true, 1)
		expect(ok).toBe(true)
		expect(list).toEqual({ "PuffPup" })
		ok, _, list = Nurse.equip({ "PuffPup", "MintMouse" }, owned, "PuffPup", false, 2)
		expect(ok).toBe(true)
		expect(list).toEqual({ "MintMouse" })
	end)

	test("mark: Seen never overwrites Hired", function()
		local index = {}
		expect(Nurse.mark(index, "PuffPup", "Seen")).toBe(true)
		expect(Nurse.mark(index, "PuffPup", "Seen")).toBe(false)
		expect(Nurse.mark(index, "PuffPup", "Hired")).toBe(true)
		expect(Nurse.mark(index, "PuffPup", "Seen")).toBe(false)
		expect(index.PuffPup).toBe("Hired")
		expect(Nurse.mark(index, "MintMouse", "Maybe")).toBe(false)
		expect(index.MintMouse).toBeNil()
	end)

	test("journal counts seen and hired by rarity", function()
		local index = { PuffPup = "Hired", MintMouse = "Seen", MoonpuffDrake = "Hired" }
		local journal = Nurse.journal(index, Nurses, Rarities)
		expect(journal.Total).toBe(16)
		expect(journal.Seen).toBe(3)
		expect(journal.Hired).toBe(2)
		expect(journal.Percent).toBe(12) -- 2 / 16
		expect(journal.Groups.Common).toEqual({ Total = 5, Seen = 2, Hired = 1, Complete = false })
		expect(journal.Groups.Mythic).toEqual({ Total = 1, Seen = 1, Hired = 1, Complete = true })
		expect(journal.Groups.Secret.Complete).toBe(false)
	end)

	test("setsDue: complete groups not yet rewarded, lowest first", function()
		local index = { MoonpuffDrake = "Hired" }
		for _, id in Nurses.Order do
			if Nurses[id].Rarity == "Common" then
				index[id] = "Hired"
			end
		end
		expect(Nurse.setsDue(index, Nurses, Rarities, {})).toEqual({ "Common", "Mythic" })
		expect(Nurse.setsDue(index, Nurses, Rarities, { Common = true })).toEqual({ "Mythic" })
		expect(Nurse.setsDue({}, Nurses, Rarities, {})).toEqual({})
	end)
end)
