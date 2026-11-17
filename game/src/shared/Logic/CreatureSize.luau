--!strict
-- How big a creature is. Pure: no Roblox services and no requires (tests/CreatureSize.spec.luau).
--   CreatureSize.scale(lookScale, cfg, roll?): number   the build scale (studs per unit; Scale 1 is about 3 units
--                                                      tall): the species' own size (Look.Scale) times
--                                                      cfg.CreatureSize (player-sized), times this patient's wobble
--   CreatureSize.jitter(roll, cfg): number             1 ± cfg.CreatureSizeJitter, from roll 0..1 (0.5 = exactly 1)
--   CreatureSize.seatFit(fit, seat): (forward, drop)   where a sitter's pivot goes on a waiting-room seat (below)
--   CreatureSize.sitEase(current, target, dt): number  the client's 0..1 sit blend, one frame on (SIT.EaseSeconds)
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

-- Sitting on a waiting-room seat (Joshua, 2026-11-17: "the patient still doesnt sit on the chair first"). Server/
-- Patients measures the creature as it is built (studs at its own size, from its pivot: the ground under its body,
-- its face looking at -Z): Hip = how high its body's bottom is (the feet go under it), Body = how far its body and
-- head reach back, Reach = how far anything but its tail reaches back (the client curls the tail up, SIT.TailCurl).
-- `seat` is in studs from the seat's centre: Cushion = to the chair back's front face, Wall = to the wall behind it.
-- The sitter's bottom rests on the seat top (its pivot `drop` studs under it; its feet sink into the cushion or hang
-- over its edge), its body and head against the chair back and everything else off the wall, SIT.Gap to spare (more
-- than the client's recline moves its top back), facing out of the seat. A big creature sits further forward, never
-- more than SIT.MaxForward past the seat's centre.
CreatureSize.SIT = table.freeze({
	Gap = 0.3, -- studs between a sitter and the chair back (and the wall)
	MaxForward = 2, -- studs: even the biggest sitter keeps most of its body over the cushion
	MaxHip = 1, -- studs: a sitter's pivot is never more than this under the seat top (a bad measure can't sink it)
	Recline = 0.03, -- radians the client leans a sitter back (its top moves back < Gap: MaxHeight * Recline)
	MaxHeight = 9.5, -- studs: the tallest sitter, ears and all (Look.Scale 1.25 at +8% is about 9)
	TailCurl = 1.1, -- radians the client turns a sitter's tail up over its back, off the chair back and the wall
	EaseSeconds = 0.35, -- the client settles into (and out of) the sit this fast
})

type Fit = { Hip: number, Body: number, Reach: number }
type Seat = { Cushion: number, Wall: number }

local function finite(value: any): number
	return if type(value) == "number" and value == value and math.abs(value) < math.huge then value else 0
end

function CreatureSize.seatFit(fit: Fit, seat: Seat): (number, number)
	local sit = CreatureSize.SIT
	local body = math.max(finite(fit.Body), 0)
	local reach = math.max(finite(fit.Reach), body)
	local forward = math.max(body + sit.Gap - finite(seat.Cushion), reach + sit.Gap - finite(seat.Wall), 0)
	return math.min(forward, sit.MaxForward), math.clamp(finite(fit.Hip), 0, sit.MaxHip)
end

function CreatureSize.sitEase(current: number, target: number, dt: number): number
	local to = if target > 0.5 then 1 else 0
	local step = math.max(finite(dt), 0) / CreatureSize.SIT.EaseSeconds
	local from = math.clamp(finite(current), 0, 1)
	return if from < to then math.min(from + step, to) else math.max(from - step, to)
end

return CreatureSize
