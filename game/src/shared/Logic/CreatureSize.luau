--!strict
-- How big a creature is. Pure: no Roblox services and no requires (tests/CreatureSize.spec.luau).
--   CreatureSize.scale(lookScale, cfg, roll?): number   the build scale (studs per unit; Scale 1 is about 3 units
--                                                      tall): the species' own size (Look.Scale) times
--                                                      cfg.CreatureSize (player-sized), times this patient's wobble
--   CreatureSize.jitter(roll, cfg): number             1 ± cfg.CreatureSizeJitter, from roll 0..1 (0.5 = exactly 1)
-- Every species has its own Look.Scale between SPECIES_MIN and SPECIES_MAX (Data/Patients, Data/Regulars), so a line
-- has small, medium and big patients, and the per-patient wobble (±8%) means no two of a kind are the same size.
-- The biggest species at the biggest wobble still fit Config.QueueSpacing (7 studs between places in line).

local CreatureSize = {}

CreatureSize.SPECIES_MIN = 0.75
CreatureSize.SPECIES_MAX = 1.25
local CLAMP_MIN, CLAMP_MAX = 0.5, 2 -- a typo in a Look.Scale can't make a giant or a speck

type Cfg = { CreatureSize: number, CreatureSizeJitter: number? }

function CreatureSize.jitter(roll: number, cfg: Cfg): number
	local amount = math.clamp(tonumber(cfg.CreatureSizeJitter) or 0, 0, 0.5)
	return 1 + (math.clamp(roll, 0, 1) * 2 - 1) * amount
end

function CreatureSize.scale(lookScale: number?, cfg: Cfg, roll: number?): number
	local species = if type(lookScale) == "number" then math.clamp(lookScale, CLAMP_MIN, CLAMP_MAX) else 1
	return species * cfg.CreatureSize * CreatureSize.jitter(roll or 0.5, cfg)
end

return CreatureSize
