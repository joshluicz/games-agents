--!strict
-- The Nurse Belt: one shared conveyor in the town plaza where nurses ride by and anyone can hire the one they see,
-- for in-game cash (depth-update design §2, build plan §B4/§B8; memory-20261116-012/-013). Server only. OWNER: T3.
-- FOUNDATION STUB: no belt is built yet; the API exists with its final signatures.
--
--   NurseBelt.start()                     builds Workspace.NurseBelt (BeltStart, BeltEnd, Conveyor, Sign/OddsGui,
--                                         Riders) at Config.Town.Origin + Config.Belt.Offset; wires HireNurse and
--                                         each rider's HirePrompt; runs arrivals every Config.Belt.ArriveSeconds
--                                         (Logic/Belt.roll with the Night Rush / Golden Hour odds and the
--                                         server-wide pity), Nurses.markSeen, the Shout remote for Epic+, Golden
--                                         Hour (Workspace GoldenHour, GoldenStartsAt, GoldenEndsAt), NightRush and
--                                         BeltPity attributes, and the sign (every odd, event odds too)
--   NurseBelt.hire(p, riderId): (ok, message)
--                                         the rider exists and isn't hired · Config.Belt.HireCooldown per player ·
--                                         within HireDistance of the rider's formula position (Logic/Belt.alpha) ·
--                                         Logic/Belt.canHire · price = Logic/Belt.price(rarity, Levels.level(p)) ->
--                                         Nurses.grant. A hired Common or Rare is replaced in ReplaceSeconds.
--   NurseBelt.odds(): { [Rarity]: number }   the odds right now (percent)
--   NurseBelt.goldenHour(): boolean
-- Cash only; no Robux anywhere on the belt (red line 3). Night Rush follows Workspace.IsNight (the game's clock) and
-- Golden Hour follows server uptime, never real-world dates.

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local BeltLogic = require(Shared.Logic.Belt)

local NurseBelt = {}

function NurseBelt.hire(_player: Player, _riderId: number): (boolean, string)
	return false, Remotes.SOON -- T3
end

function NurseBelt.goldenHour(): boolean
	return Workspace:GetAttribute("GoldenHour") == true
end

function NurseBelt.odds(): { [string]: number }
	return BeltLogic.odds(Config, Workspace:GetAttribute("IsNight") == true, NurseBelt.goldenHour())
end

function NurseBelt.start()
	Remotes.serve("HireNurse", function(player: Player, riderId: any)
		if type(riderId) ~= "number" or riderId ~= riderId or riderId % 1 ~= 0 then
			return false, Remotes.OOPS
		end
		return NurseBelt.hire(player, riderId)
	end)
end

return NurseBelt
