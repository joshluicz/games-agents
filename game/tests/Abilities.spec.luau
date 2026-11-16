--!strict
-- Nurse signature abilities (Logic/Abilities; Progression v2 build plan §B5/§B7).

local T = require("./expect")
local expect, test = T.expect, T.test

local Abilities = require("../src/shared/Logic/Abilities")
local AbilitiesData = require("../src/shared/Data/Abilities")
local Config = require("./config")

T.describe("Abilities", function()
	test("tier: 0 below Lv 5, 1 from Lv 5, 2 from Lv 10", function()
		expect(Abilities.tier(1, Config)).toBe(0)
		expect(Abilities.tier(4, Config)).toBe(0)
		expect(Abilities.tier(5, Config)).toBe(1)
		expect(Abilities.tier(9, Config)).toBe(1)
		expect(Abilities.tier(10, Config)).toBe(2)
		expect(Abilities.tier(15, Config)).toBe(2)
		expect(Abilities.tier(0 / 0, Config)).toBe(0)
	end)

	test("strength: cooldown x0.85 at Lv 5 and Lv 10 (60 -> 51 -> 43.35), values by tier", function()
		local base = Abilities.strength("QuickBandage", 1, AbilitiesData, Config) :: Abilities.Strength
		expect(base.Kind).toBe("AutoPerfect")
		expect(base.Cooldown).toBe(60)
		expect(base.Value).toBe(1)
		expect(base.Game).toBe("Patch")
		expect(base.Seconds).toBeNil()
		local five = Abilities.strength("QuickBandage", 5, AbilitiesData, Config) :: Abilities.Strength
		expect(five.Cooldown).toBeCloseTo(51)
		expect(five.Value).toBe(2)
		local ten = Abilities.strength("QuickBandage", 10, AbilitiesData, Config) :: Abilities.Strength
		expect(ten.Cooldown).toBeCloseTo(43.35)
		expect(ten.Value).toBe(3)
		local calm = Abilities.strength("CalmSong", 10, AbilitiesData, Config) :: Abilities.Strength
		expect(calm.Seconds).toBe(16)
		expect(Abilities.strength("Nope", 1, AbilitiesData, Config)).toBeNil()
		expect(Abilities.strength("Order", 1, AbilitiesData, Config)).toBeNil()
	end)

	test("strength: never under MinCooldown; SecondWind x0.8; Miracle is daily and never scales", function()
		local wind = Abilities.strength("WarmHug", 1, AbilitiesData, Config, true) :: Abilities.Strength
		expect(wind.Cooldown).toBeCloseTo(48)
		local floor = Abilities.strength("WarmHug", 10, AbilitiesData, Config, true) :: Abilities.Strength
		expect(floor.Cooldown).toBeCloseTo(60 * 0.85 * 0.85 * 0.8)
		local tiny = { Fast = { Kind = "RefillFront", Cooldown = 10, Values = { 1, 1, 1 } } }
		expect((Abilities.strength("Fast", 1, tiny, Config) :: Abilities.Strength).Cooldown).toBe(
			Config.Abilities.MinCooldown
		)
		local miracle = Abilities.strength("Miracle", 10, AbilitiesData, Config, true) :: Abilities.Strength
		expect(miracle.Daily).toBe(true)
		expect(miracle.Cooldown).toBe(AbilitiesData.Miracle.Cooldown)
	end)

	test("useful: each kind only when it would help; banked ones always", function()
		local quiet = {
			FrontPatience = 0.9,
			LowCount = 0,
			Waiting = 1,
			Missing = 0,
			TrayRoom = 2,
			NearStation = false,
			OnCooldown = 0,
		}
		for _, kind in { "AutoPerfect", "CashNext", "StarsNext" } do
			expect(Abilities.useful(kind, quiet)).toBe(true)
		end
		for _, kind in
			{ "TrayItem", "RefillFront", "PauseLine", "FastMake", "RefillLine", "InstantMake", "CureLine", "Recharge" }
		do
			expect(Abilities.useful(kind, quiet)).toBe(false)
		end
		expect(Abilities.useful("TrayItem", { Missing = 1, TrayRoom = 1 })).toBe(true)
		expect(Abilities.useful("TrayItem", { Missing = 1, TrayRoom = 0 })).toBe(false)
		expect(Abilities.useful("RefillFront", { FrontPatience = 0.49 })).toBe(true)
		expect(Abilities.useful("RefillFront", {})).toBe(false) -- nobody waiting at the front
		expect(Abilities.useful("PauseLine", { LowCount = 1 })).toBe(true)
		expect(Abilities.useful("RefillLine", { LowCount = 1 })).toBe(false)
		expect(Abilities.useful("RefillLine", { LowCount = 2 })).toBe(true)
		expect(Abilities.useful("FastMake", { Missing = 2 })).toBe(true)
		expect(Abilities.useful("InstantMake", { Missing = 2 })).toBe(false)
		expect(Abilities.useful("InstantMake", { Missing = 2, NearStation = true })).toBe(true)
		expect(Abilities.useful("CureLine", { Waiting = 2 })).toBe(true)
		expect(Abilities.useful("Recharge", { OnCooldown = 2 })).toBe(true)
		expect(Abilities.useful("Nope", { Waiting = 9 })).toBe(false)
		expect(Abilities.useful("PauseLine", nil :: any)).toBe(false)
		-- every Data/Abilities kind is one useful() knows
		for _, id in AbilitiesData.Order do
			local kind = AbilitiesData[id].Kind
			local busy = {
				FrontPatience = 0,
				LowCount = 3,
				Waiting = 3,
				Missing = 3,
				TrayRoom = 3,
				NearStation = true,
				OnCooldown = 3,
			}
			expect(Abilities.useful(kind, busy)).toBe(true)
		end
	end)

	test("ready", function()
		expect(Abilities.ready(10, 10)).toBe(true)
		expect(Abilities.ready(10, 9.9)).toBe(false)
		expect(Abilities.ready(0, 5)).toBe(true)
	end)

	test("autoGames: one charge per game, a matching game's charge before an any-game one", function()
		local flags, left = Abilities.autoGames({ "Pour", "Patch", "Patch" }, { Game = "Patch", Count = 1 })
		expect(flags).toEqual({ false, true, false })
		expect(left).toEqual({ Game = "Patch", Count = 0 })
		flags, left = Abilities.autoGames({ "Patch", "Scrub" }, {
			{ Game = nil, Count = 3 },
			{ Game = "Patch", Count = 1 },
		})
		expect(flags).toEqual({ true, true })
		expect(left).toEqual({ { Count = 2 }, { Game = "Patch", Count = 0 } })
		flags = Abilities.autoGames({ "Pour" }, {})
		expect(flags).toEqual({ false })
		local charge = { Game = nil, Count = 1 }
		Abilities.autoGames({ "Pour" }, charge)
		expect(charge.Count).toBe(1) -- never changed in place
	end)
end)
