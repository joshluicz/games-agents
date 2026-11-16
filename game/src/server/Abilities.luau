--!strict
-- Nurse signature abilities: cooldowns, triggers and effects (Progression v2 build plan §B5/§B8; design §7). Server
-- only. OWNER: T1. The rules are Logic/Abilities (Lune-tested); the content is Data/Abilities.
--
-- STUB (T1): the Foundation's safe defaults, so everything requires and boots. Nothing fires, nothing is banked.
--
--   Abilities.start()                        one loop per active plot (0.5 s), only while the owner is in the server
--                                            and done with the tutorial. Cooldowns run in real seconds from the
--                                            moment an ability fired; Miracle tracks in-game days (an IsNight true ->
--                                            false edge)
--   Abilities.Fired: Signal (plot, nurseId, abilityId, kind, value)
--                                            Patients does RefillFront, RefillLine, CureLine and PauseLine; Abilities
--                                            itself does TrayItem (Nurses), FastMake and InstantMake (plot attributes)
--                                            and Recharge
--   Abilities.consumePerfects(plot, games: { GameId }): { boolean }
--                                            Treatment asks at TreatStart: which games a banked AutoPerfect makes
--                                            PERFECT (any helper at the plot). Default: none
--   Abilities.consumeCure(plot): { Cash: number, Stars: number }
--                                            Cure asks once per cure: x Cash (Double Dose) and + Stars (Star Burst).
--                                            Default: x1 and +0
--   Abilities.patiencePaused(plot): boolean  Calm Song is pausing every waiting patient's patience. Default: false
--   Abilities.makeFactor(plot): number       station holds x this: 1, 0.5 (Busy Paws) or 0 (Time Bubble: the shortest
--                                            hold). Default: 1
--   Abilities.adminCharge(p): (ok, message)  Admin "ChargeAbilities": every ability at the player's plot ready now
-- Requires Nurses, PlayerData and Plots; NEVER Patients, Treatment, Cure or Stations (they require this).

local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local Abilities = {}

Abilities.Fired = Signal.new()

function Abilities.consumePerfects(_plot: any, games: { string }): { boolean }
	local out: { boolean } = {}
	if type(games) == "table" then
		for index in games do
			out[index] = false
		end
	end
	return out
end

function Abilities.consumeCure(_plot: any): { Cash: number, Stars: number }
	return { Cash = 1, Stars = 0 }
end

function Abilities.patiencePaused(_plot: any): boolean
	return false
end

function Abilities.makeFactor(_plot: any): number
	return 1
end

function Abilities.adminCharge(_player: Player): (boolean, string)
	return false, Remotes.SOON
end

function Abilities.start() end

return Abilities
