--!strict
-- Nurses you own: copies, XP and levels, the roster, jobs, stats and the Nurse Journal (depth-update design §2;
-- Progression v2 build plan §B1/§B7). Pure: no Roblox services, no requires. `cfg` is Shared/Config (cfg.Nurses and
-- cfg.Roster are read); `roster` is Shared/Data/Nurses, `rarities` Shared/Data/Rarities and `jobs` Shared/Data/Jobs
-- (keyed maps with .Order; read with rawget, so "Order" is never an id).
--
-- Progression v2: every nurse you own works (no equip slots). The roster holds rosterCap nurses (3, +1 a rebirth,
-- at most 8); a save with more (an Update 1 test save) keeps them all, and the extra ones rest (Job "Rest") until
-- you sell or list one or a rebirth adds a slot. Levels come from XP: a cure gives XP, a copy gives exactly one level.
--
--   Nurse.REST = "Rest"
--   Nurse.xpToNext(level): number              10 + 5 x level x (level + 1) (Logic/Schema.xpToNext)
--   Nurse.levelCap(rebirths, cfg): number      cfg.Nurses.MaxLevel (10), + LevelCapBonus (5) from LevelCapRebirths (3)
--   Nurse.rosterCap(rebirths, cfg): number     cfg.Roster.Base + PerRebirth x rebirths, at most Max
--   Nurse.addXP(entry, xp, cap): (entry, levelsGained)
--       a copy of entry with xp more XP, levelling up as often as it fills; XP past the cap is dropped (XP 0 at it)
--   Nurse.hire(entry?, cap, cfg): (entry, isNew, levelledUp)
--       one more copy: a new entry is { Level 1, XP 0, Copies 1, Job "" }; a copy adds Copies + 1 and xpToNext(Level)
--       XP, i.e. exactly one level (none at the cap). A new table (entry is not changed).
--   Nurse.stats(job, rarity, level, cfg, specialty?): Stats
--       { Every: number?, Patience, Tip, Arrive, Urgent } (multipliers; 1 = no effect). Level steps = level - 1.
--       Maker / Healer / Medic / Porter: Every = Maker/Healer/Medic/PorterSeconds[rarity] x (1 - FasterPerLevel x
--       steps) (at least x0.1), never below MinSeconds. Medic: Urgent = 1 + MedicPatience[rarity] (urgent patients
--       drain this much slower). Cheerer: Patience = 1 + CheerPatience[rarity] + CheerPerLevel x steps, Tip the same
--       with CheerTip. Receptionist: Arrive = 1 - (ReceptionArrive[rarity] + ReceptionPerLevel x steps) (arrival
--       seconds x this, never below 0.5). `specialty` (the job works in the nurse's own department): Every / (1 +
--       SpecialtyBoost), and each bonus part (Patience - 1, Tip - 1, Urgent - 1, 1 - Arrive) x (1 + SpecialtyBoost).
--       An unknown job or rarity is neutral (Every nil, the rest 1).
--   Nurse.bestCheer(list): { Patience, Tip }   the best of several Cheerers working (they don't stack)
--   Nurse.best(list, field): number            the strongest of a field across stats: the smallest "Arrive", the
--                                              largest "Patience" / "Tip" / "Urgent"; 1 when none
--   Nurse.working(nurses, cap, isKnown): { NurseId }
--       the nurses that work: Job ~= "Rest", isKnown(id), sorted by NurseId, at most cap
--   Nurse.owned(nurses, isKnown?): number      how many nurses the save owns (known ids only when isKnown is given)
--   Nurse.canAdd(data, nurseId, cfg, isKnown?): (ok, message)
--       a copy of one you own: ok unless it's at the level cap ("Max level!"); a new one: the roster must have room
--       (owned < rosterCap: "Roster full: sell or list one"). `data` is a save or a Snapshot (Nurses, Rebirth)
--   Nurse.setJob(nurses, nurseId, job, level, cap, jobs, role?): (ok, message, nurses)
--       owned ("Hire it first!") · `job` a Data/Jobs id, never "Rest" ("Oops! Try again.") · open at hospital `level`
--       (Logic/Jobs rules: "🏥 Lv 2 first!") · a resting nurse takes a job only while fewer than `cap` work ("Roster
--       full: sell or list one"). Saves Job = "" when job is the nurse's `role`. Returns a new map (shallow; the
--       changed entry is a copy)
--   Nurse.mark(index, nurseId, mark): boolean
--       the Journal: "Seen" or "Hired". Seen never overwrites Hired. CHANGES `index` in place (call it inside
--       PlayerData.update); true if it changed.
--   Nurse.journal(index, roster, rarities): Journal
--       { Total, Seen, Hired, Percent, Groups = { [Rarity] = { Total, Seen, Hired, Complete } } }. Seen counts
--       hired ones too. Percent = hired out of all, floored. A group is Complete when every nurse in it is hired.
--       Rebirth-only nurses (Source) are in no group and not in Percent: they have their own Journal tab.
--   Nurse.setsDue(index, roster, rarities, claimed): { Rarity }
--       complete groups whose reward isn't in `claimed` (Data.JournalSets) yet, lowest rarity first
--   Nurse.isRebirthOnly(roster, nurseId): boolean   the nurse has a Source (FounderFennec)

export type Entry = { Level: number, XP: number, Copies: number, Job: string }
export type Stats = { Every: number?, Patience: number, Tip: number, Arrive: number, Urgent: number }
export type Group = { Total: number, Seen: number, Hired: number, Complete: boolean }
export type Journal = { Total: number, Seen: number, Hired: number, Percent: number, Groups: { [string]: Group } }

local Nurse = {}

Nurse.REST = "Rest"

local ROSTER_FULL = "Roster full: sell or list one"
local MAX_LEVEL = "Max level!"
local OOPS = "Oops! Try again."
local MIN_ARRIVE = 0.5

local SECONDS_KEY: { [string]: string } = {
	Maker = "MakerSeconds",
	Healer = "HealerSeconds",
	Medic = "MedicSeconds",
	Porter = "PorterSeconds",
}

local function num(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

local function whole(value: any, fallback: number): number
	return math.floor(num(value, fallback))
end

local function settings(cfg: any): any
	return if type(cfg) == "table" and type(cfg.Nurses) == "table" then cfg.Nurses else {}
end

local function rosterSettings(cfg: any): any
	return if type(cfg) == "table" and type(cfg.Roster) == "table" then cfg.Roster else {}
end

local function byRarity(map: any, rarity: string): number
	return if type(map) == "table" then num(map[rarity], 0) else 0
end

-- Ids of a Data map in its Order (rawget, so "Order" is never an id).
local function ordered(map: any): { string }
	local ids: { string } = {}
	if type(map) == "table" and type(map.Order) == "table" then
		for _, id in map.Order do
			if type(id) == "string" and type(rawget(map, id)) == "table" then
				table.insert(ids, id)
			end
		end
	end
	return ids
end

local function rebirthsOf(data: any): number
	local rebirth = if type(data) == "table" then data.Rebirth else nil
	return if type(rebirth) == "table" then math.max(0, whole(rebirth.Count, 0)) else 0
end

function Nurse.xpToNext(level: number): number
	local l = math.max(1, whole(level, 1))
	return 10 + 5 * l * (l + 1)
end

function Nurse.levelCap(rebirths: number, cfg: any): number
	local s = settings(cfg)
	local cap = math.max(1, whole(s.MaxLevel, 10))
	if num(rebirths, 0) >= num(s.LevelCapRebirths, math.huge) then
		cap += math.max(0, whole(s.LevelCapBonus, 0))
	end
	return cap
end

function Nurse.rosterCap(rebirths: number, cfg: any): number
	local r = rosterSettings(cfg)
	local count = math.max(0, whole(rebirths, 0))
	local cap = whole(r.Base, 3) + whole(r.PerRebirth, 1) * count
	return math.max(0, math.min(cap, whole(r.Max, 8)))
end

local function copyEntry(entry: any): Entry
	local e = if type(entry) == "table" then entry else {}
	return {
		Level = math.max(1, whole(e.Level, 1)),
		XP = math.max(0, whole(e.XP, 0)),
		Copies = math.max(1, whole(e.Copies, 1)),
		Job = if type(e.Job) == "string" then e.Job else "",
	}
end

function Nurse.addXP(entry: Entry, xp: number, cap: number): (Entry, number)
	local out = copyEntry(entry)
	local top = math.max(1, whole(cap, 1))
	local gained = 0
	if out.Level >= top then
		out.Level = top
		out.XP = 0
		return out, 0
	end
	out.XP += math.max(0, whole(xp, 0))
	while out.Level < top and out.XP >= Nurse.xpToNext(out.Level) do
		out.XP -= Nurse.xpToNext(out.Level)
		out.Level += 1
		gained += 1
	end
	if out.Level >= top then
		out.XP = 0 -- extra XP at the cap is dropped
	end
	return out, gained
end

function Nurse.hire(entry: Entry?, cap: number, _cfg: any): (Entry, boolean, boolean)
	if entry == nil then
		return { Level = 1, XP = 0, Copies = 1, Job = "" }, true, false
	end
	local before = copyEntry(entry)
	local out, gained = Nurse.addXP(before, Nurse.xpToNext(before.Level), cap)
	out.Copies = before.Copies + 1
	return out, false, gained > 0
end

function Nurse.stats(job: string, rarity: string, level: number, cfg: any, specialty: boolean?): Stats
	local s = settings(cfg)
	local steps = math.max(0, whole(level, 1) - 1)
	local boost = if specialty == true then 1 + math.max(0, num(s.SpecialtyBoost, 0)) else 1
	local out: Stats = { Every = nil, Patience = 1, Tip = 1, Arrive = 1, Urgent = 1 }
	local secondsKey = SECONDS_KEY[job]
	if secondsKey then
		local base = byRarity(s[secondsKey], rarity)
		if base <= 0 then
			return out
		end
		local faster = math.clamp(1 - num(s.FasterPerLevel, 0) * steps, 0.1, 1)
		out.Every = math.max(num(s.MinSeconds, 1), base * faster / boost)
		if job == "Medic" then
			out.Urgent = 1 + byRarity(s.MedicPatience, rarity) * boost
		end
	elseif job == "Cheerer" then
		local extra = num(s.CheerPerLevel, 0) * steps
		out.Patience = 1 + (byRarity(s.CheerPatience, rarity) + extra) * boost
		out.Tip = 1 + (byRarity(s.CheerTip, rarity) + extra) * boost
	elseif job == "Receptionist" then
		local bonus = byRarity(s.ReceptionArrive, rarity)
		if bonus > 0 then
			bonus += num(s.ReceptionPerLevel, 0) * steps
		end
		out.Arrive = math.clamp(1 - bonus * boost, MIN_ARRIVE, 1)
	end
	return out
end

function Nurse.bestCheer(list: { any }): { Patience: number, Tip: number }
	local patience, tip = 1, 1
	for _, stats in list do
		patience = math.max(patience, num(stats.Patience, 1))
		tip = math.max(tip, num(stats.Tip, 1))
	end
	return { Patience = patience, Tip = tip }
end

function Nurse.best(list: { any }, field: string): number
	local best = 1
	for _, stats in list do
		local value = if type(stats) == "table" then num(stats[field], 1) else 1
		if field == "Arrive" then
			best = math.min(best, value)
		else
			best = math.max(best, value)
		end
	end
	return best
end

function Nurse.working(nurses: any, cap: number, isKnown: (string) -> boolean): { string }
	local ids: { string } = {}
	if type(nurses) ~= "table" then
		return ids
	end
	for nurseId, entry in nurses do
		if type(nurseId) == "string" and type(entry) == "table" and entry.Job ~= Nurse.REST and isKnown(nurseId) then
			table.insert(ids, nurseId)
		end
	end
	table.sort(ids)
	local limit = math.max(0, whole(cap, 0))
	local out: { string } = {}
	for index = 1, math.min(#ids, limit) do
		out[index] = ids[index]
	end
	return out
end

function Nurse.owned(nurses: any, isKnown: ((string) -> boolean)?): number
	local n = 0
	if type(nurses) == "table" then
		for nurseId, entry in nurses do
			if type(nurseId) == "string" and type(entry) == "table" and (isKnown == nil or isKnown(nurseId)) then
				n += 1
			end
		end
	end
	return n
end

function Nurse.canAdd(data: any, nurseId: string, cfg: any, isKnown: ((string) -> boolean)?): (boolean, string)
	if type(data) ~= "table" or type(nurseId) ~= "string" then
		return false, OOPS
	end
	local nurses = if type(data.Nurses) == "table" then data.Nurses else {}
	local rebirths = rebirthsOf(data)
	local entry = nurses[nurseId]
	if type(entry) == "table" then
		if num(entry.Level, 1) >= Nurse.levelCap(rebirths, cfg) then
			return false, MAX_LEVEL
		end
		return true, ""
	end
	if Nurse.owned(nurses, isKnown) >= Nurse.rosterCap(rebirths, cfg) then
		return false, ROSTER_FULL
	end
	return true, ""
end

local function jobOpen(jobs: any, job: string, level: number): (boolean, number)
	local row = if type(jobs) == "table" then rawget(jobs, job) else nil
	if type(row) ~= "table" then
		return false, 0
	end
	local opens = math.max(1, whole(row.Opens, 1))
	return whole(level, 1) >= opens, opens
end

function Nurse.setJob(
	nurses: { [string]: Entry },
	nurseId: string,
	job: string,
	level: number,
	cap: number,
	jobs: any,
	role: string?
): (boolean, string, { [string]: Entry })
	local current = if type(nurses) == "table" then nurses else {}
	local entry = current[nurseId]
	if type(entry) ~= "table" then
		return false, "Hire it first!", current
	end
	if type(job) ~= "string" or job == Nurse.REST or type(jobs) ~= "table" or type(rawget(jobs, job)) ~= "table" then
		return false, OOPS, current
	end
	local open, opens = jobOpen(jobs, job, level)
	if not open then
		return false, "🏥 Lv " .. opens .. " first!", current
	end
	if entry.Job == Nurse.REST then
		local working = 0
		for _, other in current do
			if type(other) == "table" and other.Job ~= Nurse.REST then
				working += 1
			end
		end
		if working >= math.max(0, whole(cap, 0)) then
			return false, ROSTER_FULL, current
		end
	end
	local out = table.clone(current)
	local changed = copyEntry(entry)
	changed.Job = if job == role then "" else job
	out[nurseId] = changed
	return true, "", out
end

function Nurse.mark(index: { [string]: string }, nurseId: string, mark: string): boolean
	if mark ~= "Seen" and mark ~= "Hired" then
		return false
	end
	local current = index[nurseId]
	if current == mark or (current == "Hired" and mark == "Seen") then
		return false
	end
	index[nurseId] = mark
	return true
end

function Nurse.isRebirthOnly(roster: any, nurseId: string): boolean
	local nurse = if type(roster) == "table" and type(nurseId) == "string" then rawget(roster, nurseId) else nil
	return type(nurse) == "table" and nurse.Source ~= nil
end

function Nurse.journal(index: { [string]: string }, roster: any, rarities: any): Journal
	local groups: { [string]: Group } = {}
	for _, rarity in ordered(rarities) do
		groups[rarity] = { Total = 0, Seen = 0, Hired = 0, Complete = false }
	end
	local total, seen, hired = 0, 0, 0
	for _, nurseId in ordered(roster) do
		local nurse = rawget(roster, nurseId)
		if nurse.Source ~= nil then
			continue -- rebirth-only: its own Journal tab, never a group or the Percent
		end
		local group = groups[nurse.Rarity]
		if not group then
			group = { Total = 0, Seen = 0, Hired = 0, Complete = false }
			groups[nurse.Rarity] = group
		end
		local mark = index[nurseId]
		group.Total += 1
		total += 1
		if mark == "Seen" or mark == "Hired" then
			group.Seen += 1
			seen += 1
		end
		if mark == "Hired" then
			group.Hired += 1
			hired += 1
		end
	end
	for _, group in groups do
		group.Complete = group.Total > 0 and group.Hired == group.Total
	end
	return {
		Total = total,
		Seen = seen,
		Hired = hired,
		Percent = if total > 0 then math.floor(hired / total * 100) else 0,
		Groups = groups,
	}
end

function Nurse.setsDue(
	index: { [string]: string },
	roster: any,
	rarities: any,
	claimed: { [string]: boolean }
): { string }
	local journal = Nurse.journal(index, roster, rarities)
	local due: { string } = {}
	for _, rarity in ordered(rarities) do
		local group = journal.Groups[rarity]
		if group and group.Complete and not (type(claimed) == "table" and claimed[rarity] == true) then
			table.insert(due, rarity)
		end
	end
	return due
end

return Nurse
