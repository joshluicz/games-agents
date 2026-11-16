--!strict
-- Boosts: how much stronger a player's cures, treatments and patients are (game/README.md "Boosts"). Pure: no Roblox
-- services, no requires, so Lune tests it (tests/Boosts.spec.luau). Server/Boosts gathers the inputs and applies the
-- result where rewards happen (Cure/Pay, Stations, Patients). Nothing here is paid or random.
--
-- Kinds (what a percent means):
--   Cash       x (1 + p/100) on a cure's whole pay
--   Tips       + p/100 onto the cure's tip factor (1 + Tip Jar levels x TipsPerLevel): works with no Tip Jar too
--   Stars      x (1 + p/100) on a cure's stars, rounded (Star Rush +100% = x2)
--   MakeSpeed  hold time / (1 + p/100) at a station, never below a floor (Boosts.makeSeconds)
--   Patience   x (1 + p/100) on how long a patient waits
--
-- Three sources:
--   permanent  Effects { Kind, Scope?, Percent } from Doctor ranks and badge tiers. Scope limits one to some cures or
--              stations ("Night", a WingId, a StationId); nil applies everywhere. The total of a kind is CAPPED
--              (Config.BoostCaps), so badges can never run away with the economy.
--   branch     Progression v2: { [Kind]: percent } from the Branch Ability Tree and the perk cards
--              (Logic/Rebirth.effects), everywhere, with its OWN caps (Config.BranchCaps), so neither source eats the
--              other's room and neither can run away. (The +25% a rebirth is not a boost here: Server/Boosts
--              multiplies Cash and Stars by Logic/Rebirth.multiplier on top.)
--   timed      Data.Boosts = { [BoostId]: secondsLeft } from the play gifts (Data/Boosts). They tick only during
--              active play, extend instead of stacking (capped), and add on top of the capped permanent part.
--
--   Boosts.KINDS · Boosts.ICONS                   the five kinds, and an icon for each
--   Boosts.applies(effect, scopes?): boolean      Scope nil, or scopes[Scope] == true
--   Boosts.permanent(effects, kind, scopes?, caps): number   percent, capped at caps[kind] (no cap entry = no cap)
--   Boosts.timed(timed, defs, kind): number       percent from the timed boosts still running
--   Boosts.branch(branch, kind, branchCaps?): number   the branch percent of a kind, capped at branchCaps[kind]
--   Boosts.percent(effects, timed, defs, kind, scopes?, caps, branch?, branchCaps?): number
--                                                 min(permanent, caps) + min(branch, branchCaps) + timed
--   Boosts.multiplier(...same...): number         1 + percent / 100
--   Boosts.extend(timed, defs, id, seconds, maxSeconds): Timed   adds time to one boost (unknown id: unchanged)
--   Boosts.tick(timed, seconds): Timed            takes active seconds off every boost; finished ones go
--   Boosts.soonest(timed): number?                the fewest seconds left on any running boost
--   Boosts.summary(effects, caps, branch?, branchCaps?): { [Kind]: number }   the everywhere (unscoped) permanent
--                                                 percent of each kind, plus the capped branch part when given
--   Boosts.branchSummary(branch, branchCaps): { [Kind]: number }   the capped branch percent of each kind
--   Boosts.makeSeconds(base, percent, floor): number    a hold time with a MakeSpeed percent applied
-- Every function returns new tables; inputs are never changed.

export type Effect = { Kind: string, Scope: string?, Percent: number }
export type TimedDef = { Name: string, Icon: string, Kind: string, Percent: number, Minutes: number }
export type Timed = { [string]: number }
export type Caps = { [string]: number }
export type Scopes = { [string]: boolean }
export type Branch = { [string]: number }

local Boosts = {}

Boosts.KINDS = table.freeze({ "Cash", "Tips", "Stars", "MakeSpeed", "Patience" })
Boosts.ICONS = table.freeze({ Cash = "💰", Tips = "💵", Stars = "⭐", MakeSpeed = "⚡", Patience = "💺" })

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function capOf(caps: Caps?, kind: string): number
	local cap = if type(caps) == "table" then caps[kind] else nil
	return if finite(cap) then math.max(0, cap :: number) else math.huge
end

function Boosts.applies(effect: Effect, scopes: Scopes?): boolean
	if effect.Scope == nil then
		return true
	end
	return type(scopes) == "table" and scopes[effect.Scope :: string] == true
end

function Boosts.permanent(effects: { Effect }, kind: string, scopes: Scopes?, caps: Caps?): number
	local total = 0
	for _, effect in effects do
		if effect.Kind == kind and finite(effect.Percent) and effect.Percent > 0 and Boosts.applies(effect, scopes) then
			total += effect.Percent
		end
	end
	return math.min(total, capOf(caps, kind))
end

function Boosts.timed(timed: Timed, defs: any, kind: string): number
	local total = 0
	for id, left in timed do
		local def = if type(defs) == "table" then rawget(defs, id) else nil
		if type(def) == "table" and def.Kind == kind and finite(left) and left > 0 and finite(def.Percent) then
			total += math.max(0, def.Percent)
		end
	end
	return total
end

function Boosts.branch(branch: Branch?, kind: string, branchCaps: Caps?): number
	local value = if type(branch) == "table" then branch[kind] else nil
	if not finite(value) or (value :: number) <= 0 then
		return 0
	end
	return math.min(value :: number, capOf(branchCaps, kind))
end

function Boosts.percent(
	effects: { Effect },
	timed: Timed,
	defs: any,
	kind: string,
	scopes: Scopes?,
	caps: Caps?,
	branch: Branch?,
	branchCaps: Caps?
): number
	return Boosts.permanent(effects, kind, scopes, caps)
		+ Boosts.branch(branch, kind, branchCaps)
		+ Boosts.timed(timed, defs, kind)
end

function Boosts.multiplier(
	effects: { Effect },
	timed: Timed,
	defs: any,
	kind: string,
	scopes: Scopes?,
	caps: Caps?,
	branch: Branch?,
	branchCaps: Caps?
): number
	return 1 + Boosts.percent(effects, timed, defs, kind, scopes, caps, branch, branchCaps) / 100
end

function Boosts.extend(timed: Timed, defs: any, id: string, seconds: number, maxSeconds: number): Timed
	local out = table.clone(timed)
	local def = if type(defs) == "table" and type(id) == "string" then rawget(defs, id) else nil
	if type(def) ~= "table" or not finite(seconds) or seconds <= 0 then
		return out
	end
	local cap = if finite(maxSeconds) then math.max(0, maxSeconds) else math.huge
	local left = if finite(out[id]) then math.max(0, out[id]) else 0
	out[id] = math.min(cap, left + seconds)
	return out
end

function Boosts.tick(timed: Timed, seconds: number): Timed
	local spent = if finite(seconds) then math.max(0, seconds) else 0
	local out: Timed = {}
	for id, left in timed do
		if finite(left) and left - spent > 0 then
			out[id] = left - spent
		end
	end
	return out
end

function Boosts.soonest(timed: Timed): number?
	local best: number? = nil
	for _, left in timed do
		if finite(left) and left > 0 and (best == nil or left < best) then
			best = left
		end
	end
	return best
end

function Boosts.summary(effects: { Effect }, caps: Caps?, branch: Branch?, branchCaps: Caps?): { [string]: number }
	local out: { [string]: number } = {}
	for _, kind in Boosts.KINDS do
		out[kind] = Boosts.permanent(effects, kind, nil, caps) + Boosts.branch(branch, kind, branchCaps)
	end
	return out
end

function Boosts.branchSummary(branch: Branch?, branchCaps: Caps?): { [string]: number }
	local out: { [string]: number } = {}
	for _, kind in Boosts.KINDS do
		out[kind] = Boosts.branch(branch, kind, branchCaps)
	end
	return out
end

-- A hold time with a MakeSpeed percent applied: base / (1 + percent/100), never below `floor`, never above base.
function Boosts.makeSeconds(base: number, percent: number, floor: number): number
	if not finite(base) or base <= 0 then
		return if finite(floor) then math.max(0, floor) else 0
	end
	local p = if finite(percent) then math.max(0, percent) else 0
	local low = if finite(floor) then math.min(base, math.max(0, floor)) else 0
	return math.max(low, base / (1 + p / 100))
end

return table.freeze(Boosts)
