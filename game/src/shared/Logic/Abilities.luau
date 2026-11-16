--!strict
-- Nurse signature abilities: strength by level, when one helps, banked charges (Progression v2 build plan §B5/§B7;
-- design §7). Pure: no Roblox services, no requires. `abilities` is Shared/Data/Abilities, `cfg` Shared/Config
-- (cfg.Abilities is read). Server/Abilities runs the cooldowns; Patients, Treatment and Cure spend the effects.
-- Cooldowns are shown as filling rings, never seconds (red line 3).
--
--   Abilities.BANKED                              the kinds that wait for the next matching treat or cure
--   Abilities.TIMED                               the kinds whose Value is seconds (Strength.Seconds)
--   Abilities.tier(level, cfg): 0 | 1 | 2         how many of cfg.Abilities.UpgradeLevels (5, 10) the nurse reached
--   Abilities.strength(abilityId, level, abilities, cfg, secondWind?): Strength?
--       { Kind, Cooldown, Value, Seconds?, Game?, Daily } at this nurse level, nil for an unknown id: Value =
--       Values[tier + 1]; Cooldown = Cooldown x CooldownStep ^ tier (x SecondWind with the perk), never below
--       MinCooldown; a Daily ability's Cooldown is only its ring's length and never scales; Seconds = Value for the
--       timed kinds
--   Abilities.useful(kind, view): boolean        it would help right now (an ability fires by itself only then):
--       view = { FrontPatience: number? (0..1, the front WAITING patient), LowCount (waiting patients under 50%),
--       Waiting (patients waiting, not being treated), Missing (items the line needs that no hand or tray holds),
--       TrayRoom (free tray places), NearStation (the owner is within 25 studs of a station), OnCooldown (OTHER
--       abilities at this plot cooling down) }. Banked kinds are always useful (they light up and wait).
--         TrayItem    Missing >= 1 and TrayRoom >= 1      RefillFront  FrontPatience < 0.5
--         PauseLine   LowCount >= 1                       FastMake     Missing >= 2
--         RefillLine  LowCount >= 2                       InstantMake  Missing >= 2 and NearStation
--         CureLine    Waiting >= 2                        Recharge     OnCooldown >= 2
--   Abilities.ready(readyAt, now): boolean        readyAt <= now (server time)
--   Abilities.autoGames(games, charges): ({ boolean }, charges)
--       which of a session's games an AutoPerfect bank makes PERFECT. `charges` is one { Game: GameId?, Count } or a
--       list of them; a charge for one game (QuickBandage: "Patch") is spent before an any-game charge (GoldenTouch:
--       Game nil), each game takes one Count. Returns the flags and the charges left (same shape, Count >= 0; new
--       tables)

export type Strength = {
	Kind: string,
	Cooldown: number,
	Value: number,
	Seconds: number?,
	Game: string?,
	Daily: boolean,
}
export type View = {
	FrontPatience: number?,
	LowCount: number?,
	Waiting: number?,
	Missing: number?,
	TrayRoom: number?,
	NearStation: boolean?,
	OnCooldown: number?,
}
export type Charge = { Game: string?, Count: number }

local Abilities = {}

Abilities.BANKED = table.freeze({ AutoPerfect = true, CashNext = true, StarsNext = true }) :: { [string]: boolean }
Abilities.TIMED = table.freeze({ PauseLine = true, FastMake = true, InstantMake = true }) :: { [string]: boolean }
Abilities.LOW = 0.5 -- "under 50% patience"

local function num(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

local function settings(cfg: any): any
	return if type(cfg) == "table" and type(cfg.Abilities) == "table" then cfg.Abilities else {}
end

function Abilities.tier(level: number, cfg: any): number
	local steps = settings(cfg).UpgradeLevels
	local tier = 0
	if type(steps) == "table" then
		for _, at in steps do
			if num(level, 1) >= num(at, math.huge) then
				tier += 1
			end
		end
	end
	return math.min(tier, 2)
end

function Abilities.strength(abilityId: string, level: number, abilities: any, cfg: any, secondWind: boolean?): Strength?
	local def = if type(abilities) == "table" and type(abilityId) == "string" then rawget(abilities, abilityId) else nil
	if type(def) ~= "table" then
		return nil
	end
	local s = settings(cfg)
	local tier = Abilities.tier(level, cfg)
	local values = if type(def.Values) == "table" then def.Values else {}
	local value = num(values[tier + 1], num(values[#values], 1))
	local base = math.max(0, num(def.Cooldown, 60))
	local cooldown = base
	local daily = def.Daily == true
	if not daily then
		cooldown = base * num(s.CooldownStep, 1) ^ tier
		if secondWind == true then
			cooldown *= num(s.SecondWind, 1)
		end
		cooldown = math.max(num(s.MinCooldown, 0), cooldown)
	end
	return {
		Kind = def.Kind,
		Cooldown = cooldown,
		Value = value,
		Seconds = if Abilities.TIMED[def.Kind] then value else nil,
		Game = if type(def.Game) == "string" then def.Game else nil,
		Daily = daily,
	}
end

function Abilities.useful(kind: string, view: View): boolean
	if Abilities.BANKED[kind] then
		return true
	end
	if type(view) ~= "table" then
		return false
	end
	local missing = num(view.Missing, 0)
	local low = num(view.LowCount, 0)
	if kind == "TrayItem" then
		return missing >= 1 and num(view.TrayRoom, 0) >= 1
	elseif kind == "RefillFront" then
		return view.FrontPatience ~= nil and num(view.FrontPatience, 1) < Abilities.LOW
	elseif kind == "PauseLine" then
		return low >= 1
	elseif kind == "FastMake" then
		return missing >= 2
	elseif kind == "RefillLine" then
		return low >= 2
	elseif kind == "InstantMake" then
		return missing >= 2 and view.NearStation == true
	elseif kind == "CureLine" then
		return num(view.Waiting, 0) >= 2
	elseif kind == "Recharge" then
		return num(view.OnCooldown, 0) >= 2
	end
	return false
end

function Abilities.ready(readyAt: number, now: number): boolean
	return num(readyAt, 0) <= num(now, 0)
end

function Abilities.autoGames(games: { string }, charges: any): ({ boolean }, any)
	local single = type(charges) == "table" and charges.Count ~= nil
	local list: { Charge } = {}
	if single then
		list[1] = { Game = charges.Game, Count = math.max(0, math.floor(num(charges.Count, 0))) }
	elseif type(charges) == "table" then
		for _, charge in ipairs(charges) do
			if type(charge) == "table" then
				table.insert(list, {
					Game = if type(charge.Game) == "string" then charge.Game else nil,
					Count = math.max(0, math.floor(num(charge.Count, 0))),
				})
			end
		end
	end
	local flags: { boolean } = {}
	for index, game in games do
		flags[index] = false
		-- A charge for this very game first, then an any-game one.
		local pick: Charge? = nil
		for _, charge in list do
			if charge.Count > 0 and charge.Game == game then
				pick = charge
				break
			end
		end
		if not pick then
			for _, charge in list do
				if charge.Count > 0 and charge.Game == nil then
					pick = charge
					break
				end
			end
		end
		if pick then
			pick.Count -= 1
			flags[index] = true
		end
	end
	return flags, if single then list[1] else list
end

return Abilities
