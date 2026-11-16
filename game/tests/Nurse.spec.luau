--!strict
-- Owned nurses: XP and levels, the roster, jobs, stats and the Nurse Journal (depth-update build plan §B7;
-- Progression v2 build plan §B1/§B6/§B7).

local T = require("./expect")
local expect, test = T.expect, T.test

local Nurse = require("../src/shared/Logic/Nurse")
local Schema = require("../src/shared/Logic/Schema")
local Nurses = require("../src/shared/Data/Nurses")
local Rarities = require("../src/shared/Data/Rarities")
local Jobs = require("../src/shared/Data/Jobs")
local Config = require("./config")

local CFG = Config -- the shipped numbers (tests/config.luau)

local function known(nurseId: string): boolean
	return type(rawget(Nurses :: any, nurseId)) == "table"
end

T.describe("Nurse caps and the XP curve", function()
	test("xpToNext is 10 + 5L(L+1) and matches Schema", function()
		for level = 1, 15 do
			expect(Nurse.xpToNext(level)).toBe(10 + 5 * level * (level + 1))
			expect(Nurse.xpToNext(level)).toBe(Schema.xpToNext(level))
		end
		expect(Nurse.xpToNext(0 / 0)).toBe(20)
	end)

	test("the level cap is 10, 15 from R3, and Schema repeats Config's numbers", function()
		expect(Nurse.levelCap(0, CFG)).toBe(10)
		expect(Nurse.levelCap(2, CFG)).toBe(10)
		expect(Nurse.levelCap(3, CFG)).toBe(15)
		expect(Nurse.levelCap(9, CFG)).toBe(15)
		expect(Schema.NURSE_LEVEL_CAP).toBe(CFG.Nurses.MaxLevel)
		expect(Schema.NURSE_LEVEL_CAP_R3).toBe(CFG.Nurses.MaxLevel + CFG.Nurses.LevelCapBonus)
		expect(Schema.LEVEL_CAP_REBIRTHS).toBe(CFG.Nurses.LevelCapRebirths)
		for count = 0, 6 do
			expect(Nurse.levelCap(count, CFG)).toBe(Schema.levelCap(count))
		end
	end)

	test("the roster is 3, +1 a rebirth, at most 8 (memory-019), the same as Schema", function()
		expect(Nurse.rosterCap(0, CFG)).toBe(3)
		expect(Nurse.rosterCap(1, CFG)).toBe(4)
		expect(Nurse.rosterCap(5, CFG)).toBe(8)
		expect(Nurse.rosterCap(50, CFG)).toBe(8)
		expect(Schema.ROSTER_BASE).toBe(CFG.Roster.Base)
		expect(Schema.ROSTER_PER_REBIRTH).toBe(CFG.Roster.PerRebirth)
		expect(Schema.ROSTER_MAX).toBe(CFG.Roster.Max)
		for count = 0, 8 do
			expect(Nurse.rosterCap(count, CFG)).toBe(Schema.rosterCap(count))
		end
	end)
end)

T.describe("Nurse XP", function()
	test("addXP levels up across two levels and keeps the rest", function()
		local entry = { Level = 1, XP = 15, Copies = 1, Job = "" }
		local out, gained = Nurse.addXP(entry, 50, 10) -- 65: 20 to Lv 2, 40 to Lv 3, 5 left
		expect(out).toEqual({ Level = 3, XP = 5, Copies = 1, Job = "" })
		expect(gained).toBe(2)
		expect(entry).toEqual({ Level = 1, XP = 15, Copies = 1, Job = "" }) -- never changed in place
	end)

	test("addXP drops XP past the cap (0 at the cap)", function()
		local out, gained = Nurse.addXP({ Level = 9, XP = 400, Copies = 1, Job = "" }, 500, 10)
		expect(out.Level).toBe(10)
		expect(out.XP).toBe(0)
		expect(gained).toBe(1)
		out, gained = Nurse.addXP(out, 999, 10)
		expect(out).toEqual({ Level = 10, XP = 0, Copies = 1, Job = "" })
		expect(gained).toBe(0)
		out = Nurse.addXP({ Level = 10, XP = 0, Copies = 1, Job = "" }, 1, 15)
		expect(out.XP).toBe(1) -- from R3 it grows again
		local junk = Nurse.addXP({ Level = 2, XP = 0, Copies = 1, Job = "" }, 0 / 0, 10)
		expect(junk.XP).toBe(0)
	end)

	test("hire: a new nurse, then each copy is exactly one level (none at the cap)", function()
		local entry, isNew, up = Nurse.hire(nil, 10, CFG)
		expect(entry).toEqual({ Level = 1, XP = 0, Copies = 1, Job = "" })
		expect(isNew).toBe(true)
		expect(up).toBe(false)
		entry.XP = 7
		local before = table.clone(entry)
		for level = 2, 10 do
			entry, isNew, up = Nurse.hire(entry, 10, CFG)
			expect(entry.Level).toBe(level)
			expect(entry.XP).toBe(if level < 10 then 7 else 0)
			expect(isNew).toBe(false)
			expect(up).toBe(true)
		end
		expect(entry.Copies).toBe(10)
		entry, _, up = Nurse.hire(entry, 10, CFG)
		expect(entry.Level).toBe(10)
		expect(entry.Copies).toBe(11)
		expect(up).toBe(false)
		expect(before).toEqual({ Level = 1, XP = 7, Copies = 1, Job = "" }) -- never changed in place
		local job = Nurse.hire({ Level = 2, XP = 0, Copies = 2, Job = "Porter" }, 10, CFG)
		expect(job.Job).toBe("Porter") -- a copy keeps the job
	end)
end)

T.describe("Nurse stats", function()
	-- The depth update's numbers, so the old expectations still hold for the formula; Config's own numbers after.
	local OLD = {
		Nurses = {
			MinSeconds = 3,
			FasterPerLevel = 0.08,
			MakerSeconds = { Common = 14, Rare = 12, Epic = 10, Legendary = 8, Mythic = 7, Secret = 6 },
			HealerSeconds = { Common = 16, Rare = 14, Epic = 12, Legendary = 10, Mythic = 9, Secret = 8 },
			CheerPatience = { Common = 0.1, Rare = 0.15, Epic = 0.2, Legendary = 0.3, Mythic = 0.35, Secret = 0.4 },
			CheerTip = { Common = 0.05, Rare = 0.08, Epic = 0.12, Legendary = 0.18, Mythic = 0.22, Secret = 0.25 },
			CheerPerLevel = 0.03,
		},
	}

	test("Makers and Healers get faster with rarity and level", function()
		expect(Nurse.stats("Maker", "Common", 1, OLD).Every).toBe(14)
		expect(Nurse.stats("Maker", "Common", 5, OLD).Every).toBeCloseTo(14 * 0.68)
		expect(Nurse.stats("Healer", "Secret", 1, OLD).Every).toBe(8)
		expect(Nurse.stats("Healer", "Secret", 5, OLD).Every).toBeCloseTo(5.44)
		expect(Nurse.stats("Maker", "Nope", 1, OLD).Every).toBeNil()
		local maker = Nurse.stats("Maker", "Rare", 1, OLD)
		expect(maker.Patience).toBe(1)
		expect(maker.Tip).toBe(1)
		expect(maker.Arrive).toBe(1)
		expect(maker.Urgent).toBe(1)
	end)

	test("Cheerers add patience and tips", function()
		local cheer = Nurse.stats("Cheerer", "Epic", 1, OLD)
		expect(cheer.Every).toBeNil()
		expect(cheer.Patience).toBeCloseTo(1.2)
		expect(cheer.Tip).toBeCloseTo(1.12)
		local top = Nurse.stats("Cheerer", "Epic", 5, OLD)
		expect(top.Patience).toBeCloseTo(1.32)
		expect(top.Tip).toBeCloseTo(1.24)
	end)

	test("the shipped numbers: 5% faster a level (Lv 10 x0.55), never under 3 s; Cheerers +2% a level", function()
		expect(Nurse.stats("Maker", "Common", 10, CFG).Every).toBeCloseTo(14 * 0.55)
		expect(Nurse.stats("Healer", "Common", 10, CFG).Every).toBeCloseTo(16 * 0.55)
		expect(Nurse.stats("Medic", "Rare", 1, CFG).Every).toBe(12)
		expect(Nurse.stats("Maker", "Secret", 15, CFG).Every).toBe(3) -- 6 x 0.3 = 1.8 -> the 3 s floor
		expect(Nurse.stats("Cheerer", "Common", 6, CFG).Patience).toBeCloseTo(1.2) -- 0.1 + 5 x 0.02
	end)

	test("Medics, Receptionists and Porters (Progression v2 §B6)", function()
		local medic = Nurse.stats("Medic", "Epic", 1, CFG)
		expect(medic.Every).toBe(10)
		expect(medic.Urgent).toBeCloseTo(1.3)
		local desk = Nurse.stats("Receptionist", "Legendary", 1, CFG)
		expect(desk.Every).toBeNil()
		expect(desk.Arrive).toBeCloseTo(0.84)
		expect(Nurse.stats("Receptionist", "Common", 11, CFG).Arrive).toBeCloseTo(1 - (0.05 + 10 * 0.005))
		expect(Nurse.stats("Porter", "Common", 1, CFG).Every).toBe(5)
		expect(Nurse.stats("Porter", "Mythic", 1, CFG).Every).toBe(3)
		expect(Nurse.stats("Receptionist", "Nope", 4, CFG).Arrive).toBe(1)
		expect(Nurse.stats("Juggler", "Common", 1, CFG)).toEqual({ Patience = 1, Tip = 1, Arrive = 1, Urgent = 1 })
	end)

	test("a specialty match: +40% speed or effect", function()
		expect(Nurse.stats("Maker", "Common", 1, CFG, true).Every).toBeCloseTo(10) -- 14 / 1.4
		expect(Nurse.stats("Cheerer", "Epic", 1, CFG, true).Patience).toBeCloseTo(1.28) -- 0.2 x 1.4
		expect(Nurse.stats("Medic", "Common", 1, CFG, true).Urgent).toBeCloseTo(1.28)
		expect(Nurse.stats("Receptionist", "Common", 1, CFG, true).Arrive).toBeCloseTo(0.93)
		expect(Nurse.stats("Maker", "Secret", 10, CFG, true).Every).toBe(3)
	end)

	test("bestCheer and best take the best, not the sum", function()
		local best = Nurse.bestCheer({
			{ Patience = 1.2, Tip = 1.05 },
			{ Patience = 1.1, Tip = 1.2 },
		})
		expect(best).toEqual({ Patience = 1.2, Tip = 1.2 })
		expect(Nurse.bestCheer({})).toEqual({ Patience = 1, Tip = 1 })
		local list = { { Arrive = 0.95, Urgent = 1.2 }, { Arrive = 0.9, Urgent = 1.1 }, {} }
		expect(Nurse.best(list, "Arrive")).toBe(0.9)
		expect(Nurse.best(list, "Urgent")).toBe(1.2)
		expect(Nurse.best({}, "Arrive")).toBe(1)
	end)
end)

T.describe("Nurse roster and jobs", function()
	local function save(nurses: { [string]: any }, rebirths: number?): any
		local data = Schema.default()
		data.Nurses = nurses
		data.Rebirth.Count = rebirths or 0
		return data
	end

	test("working: not resting, known, by NurseId, at most the cap", function()
		local nurses = {
			PuffPup = { Level = 1, XP = 0, Copies = 1, Job = "" },
			MintMouse = { Level = 1, XP = 0, Copies = 1, Job = "Rest" },
			BeanBear = { Level = 1, XP = 0, Copies = 1, Job = "Healer" },
			Renamed = { Level = 1, XP = 0, Copies = 1, Job = "" },
			DewDuck = { Level = 1, XP = 0, Copies = 1, Job = "" },
		}
		expect(Nurse.working(nurses, 3, known)).toEqual({ "BeanBear", "DewDuck", "PuffPup" })
		expect(Nurse.working(nurses, 2, known)).toEqual({ "BeanBear", "DewDuck" })
		expect(Nurse.working(nil, 3, known)).toEqual({})
		expect(Nurse.owned(nurses)).toBe(5)
		expect(Nurse.owned(nurses, known)).toBe(4)
	end)

	test("canAdd: a copy unless at the cap; a new nurse needs roster room (resting ones count)", function()
		local three = {
			PuffPup = { Level = 10, XP = 0, Copies = 9, Job = "" },
			MintMouse = { Level = 1, XP = 0, Copies = 1, Job = "" },
			BeanBear = { Level = 1, XP = 0, Copies = 1, Job = "Rest" },
		}
		local ok, message = Nurse.canAdd(save(three), "MintMouse", CFG)
		expect(ok).toBe(true)
		expect(message).toBe("")
		ok, message = Nurse.canAdd(save(three), "PuffPup", CFG)
		expect(ok).toBe(false)
		expect(message).toBe("Max level!")
		expect((Nurse.canAdd(save(three, 3), "PuffPup", CFG))).toBe(true) -- Lv 15 from R3
		ok, message = Nurse.canAdd(save(three), "DewDuck", CFG)
		expect(ok).toBe(false)
		expect(message).toBe("Roster full: sell or list one")
		expect((Nurse.canAdd(save(three, 1), "DewDuck", CFG))).toBe(true) -- +1 slot at R1
		expect((Nurse.canAdd(nil, "DewDuck", CFG))).toBe(false)
		-- an unknown id in the save takes no place when isKnown is given
		local withOld = table.clone(three)
		withOld.BeanBear = nil
		withOld.Renamed = { Level = 1, XP = 0, Copies = 1, Job = "" }
		expect((Nurse.canAdd(save(withOld), "DewDuck", CFG))).toBe(false)
		expect((Nurse.canAdd(save(withOld), "DewDuck", CFG, known))).toBe(true)
	end)

	test("setJob: owned, a real job (never Rest), open at your level, a resting nurse only with room", function()
		local nurses = {
			PuffPup = { Level = 1, XP = 0, Copies = 1, Job = "" },
			MintMouse = { Level = 1, XP = 0, Copies = 1, Job = "Rest" },
			BeanBear = { Level = 1, XP = 0, Copies = 1, Job = "" },
		}
		local ok, message, out = Nurse.setJob(nurses, "PuffPup", "Receptionist", 1, 3, Jobs, "Maker")
		expect(ok).toBe(true)
		expect(message).toBe("")
		expect(out.PuffPup.Job).toBe("Receptionist")
		expect(nurses.PuffPup.Job).toBe("") -- never changed in place
		ok, _, out = Nurse.setJob(out, "PuffPup", "Maker", 1, 3, Jobs, "Maker")
		expect(ok).toBe(true)
		expect(out.PuffPup.Job).toBe("") -- its own role is saved as ""
		ok, message = Nurse.setJob(nurses, "PuffPup", "Porter", 1, 3, Jobs, "Maker")
		expect(ok).toBe(false)
		expect(message).toBe("🏥 Lv 2 first!")
		expect((Nurse.setJob(nurses, "PuffPup", "Porter", 2, 3, Jobs, "Maker"))).toBe(true)
		ok, message = Nurse.setJob(nurses, "PuffPup", "Rest", 1, 3, Jobs, "Maker")
		expect(ok).toBe(false)
		expect(message).toBe("Oops! Try again.")
		expect((Nurse.setJob(nurses, "PuffPup", "Order", 1, 3, Jobs, "Maker"))).toBe(false)
		ok, message = Nurse.setJob(nurses, "DewDuck", "Healer", 1, 3, Jobs, "Healer")
		expect(ok).toBe(false)
		expect(message).toBe("Hire it first!")
		-- the resting nurse: 2 work and the cap is 3 -> it may take a job; at a cap of 2 it may not
		expect((Nurse.setJob(nurses, "MintMouse", "Healer", 1, 3, Jobs, "Healer"))).toBe(true)
		ok, message = Nurse.setJob(nurses, "MintMouse", "Healer", 1, 2, Jobs, "Healer")
		expect(ok).toBe(false)
		expect(message).toBe("Roster full: sell or list one")
	end)
end)

T.describe("Nurse journal", function()
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

	test("journal counts seen and hired by rarity, without rebirth-only nurses", function()
		local index = { PuffPup = "Hired", MintMouse = "Seen", MoonpuffDrake = "Hired", FounderFennec = "Hired" }
		local journal = Nurse.journal(index, Nurses, Rarities)
		expect(journal.Total).toBe(16)
		expect(journal.Seen).toBe(3)
		expect(journal.Hired).toBe(2)
		expect(journal.Percent).toBe(12) -- 2 / 16
		expect(journal.Groups.Common).toEqual({ Total = 5, Seen = 2, Hired = 1, Complete = false })
		expect(journal.Groups.Legendary.Total).toBe(2) -- FounderFennec is in no group
		expect(journal.Groups.Mythic).toEqual({ Total = 1, Seen = 1, Hired = 1, Complete = true })
		expect(journal.Groups.Secret.Complete).toBe(false)
		expect(Nurse.isRebirthOnly(Nurses, "FounderFennec")).toBe(true)
		expect(Nurse.isRebirthOnly(Nurses, "PuffPup")).toBe(false)
		expect(Nurse.isRebirthOnly(Nurses, "Order")).toBe(false)
	end)

	test("setsDue: complete groups not yet rewarded, lowest first; the Legendary set ignores FounderFennec", function()
		local index = { MoonpuffDrake = "Hired" }
		for _, id in Nurses.Order do
			if Nurses[id].Rarity == "Common" then
				index[id] = "Hired"
			end
		end
		expect(Nurse.setsDue(index, Nurses, Rarities, {})).toEqual({ "Common", "Mythic" })
		expect(Nurse.setsDue(index, Nurses, Rarities, { Common = true })).toEqual({ "Mythic" })
		expect(Nurse.setsDue({}, Nurses, Rarities, {})).toEqual({})
		local legends = { AuroraOtter = "Hired", StarlightLamb = "Hired" }
		expect(Nurse.setsDue(legends, Nurses, Rarities, {})).toEqual({ "Legendary" })
	end)
end)
