--!strict
-- Nurses you own: hiring copies, stats by rarity x level, equip slots and the Nurse Journal (depth-update design §2,
-- build plan §B7). Pure: no Roblox services, no requires. `cfg` is Shared/Config (cfg.Nurses is read); `roster` is
-- Shared/Data/Nurses and `rarities` Shared/Data/Rarities (keyed maps with .Order).
--
--   Nurse.hire(entry?, cfg): (entry, isNew, levelledUp)
--       one more copy: Copies + 1, Level = min(Copies, MaxLevel). A new table (entry is not changed).
--   Nurse.stats(role, rarity, level, cfg): { Every: number?, Patience: number, Tip: number }
--       Maker / Healer: Every = MakerSeconds / HealerSeconds[rarity] x (1 - FasterPerLevel x (level - 1)), never
--       below MinSeconds. Cheerer: Patience = 1 + CheerPatience[rarity] + CheerPerLevel x (level - 1), Tip the same
--       with CheerTip (multipliers). Everything else is neutral (Every nil, Patience 1, Tip 1).
--   Nurse.bestCheer(list): { Patience, Tip }      the best of several Cheerers on duty (they don't stack)
--   Nurse.equip(equipped, nurses, nurseId, on, slots): (ok, message, equipped)
--       on: must be hired ("Hire it first!"), and a free slot ("All slots full!"). Already on duty: ok, unchanged.
--       off: removed (not on duty: ok, unchanged). Returns a new list.
--   Nurse.mark(index, nurseId, mark): boolean
--       the Journal: "Seen" or "Hired". Seen never overwrites Hired. CHANGES `index` in place (call it inside
--       PlayerData.update); true if it changed.
--   Nurse.journal(index, roster, rarities): Journal
--       { Total, Seen, Hired, Percent, Groups = { [Rarity] = { Total, Seen, Hired, Complete } } }. Seen counts
--       hired ones too. Percent = hired out of all, floored. A group is Complete when every nurse in it is hired.
--   Nurse.setsDue(index, roster, rarities, claimed): { Rarity }
--       complete groups whose reward isn't in `claimed` (Data.JournalSets) yet, lowest rarity first

export type Entry = { Level: number, Copies: number }
export type Stats = { Every: number?, Patience: number, Tip: number }
export type Group = { Total: number, Seen: number, Hired: number, Complete: boolean }
export type Journal = { Total: number, Seen: number, Hired: number, Percent: number, Groups: { [string]: Group } }

local Nurse = {}

local function num(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

local function settings(cfg: any): any
	return if type(cfg) == "table" and type(cfg.Nurses) == "table" then cfg.Nurses else {}
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

function Nurse.hire(entry: Entry?, cfg: any): (Entry, boolean, boolean)
	local maxLevel = math.max(1, num(settings(cfg).MaxLevel, 5))
	local copies = if entry then math.max(0, math.floor(num(entry.Copies, 0))) else 0
	local before = if entry then num(entry.Level, 0) else 0
	copies += 1
	local level = math.min(copies, maxLevel)
	return { Level = level, Copies = copies }, entry == nil, entry ~= nil and level > before
end

function Nurse.stats(role: string, rarity: string, level: number, cfg: any): Stats
	local s = settings(cfg)
	local steps = math.max(0, math.floor(num(level, 1)) - 1)
	if role == "Maker" or role == "Healer" then
		local base = byRarity(if role == "Maker" then s.MakerSeconds else s.HealerSeconds, rarity)
		if base <= 0 then
			return { Every = nil, Patience = 1, Tip = 1 }
		end
		local faster = math.clamp(1 - num(s.FasterPerLevel, 0) * steps, 0.1, 1)
		return { Every = math.max(num(s.MinSeconds, 1), base * faster), Patience = 1, Tip = 1 }
	elseif role == "Cheerer" then
		local extra = num(s.CheerPerLevel, 0) * steps
		return {
			Every = nil,
			Patience = 1 + byRarity(s.CheerPatience, rarity) + extra,
			Tip = 1 + byRarity(s.CheerTip, rarity) + extra,
		}
	end
	return { Every = nil, Patience = 1, Tip = 1 }
end

function Nurse.bestCheer(list: { Stats }): { Patience: number, Tip: number }
	local patience, tip = 1, 1
	for _, stats in list do
		patience = math.max(patience, num(stats.Patience, 1))
		tip = math.max(tip, num(stats.Tip, 1))
	end
	return { Patience = patience, Tip = tip }
end

function Nurse.equip(
	equipped: { string },
	nurses: { [string]: Entry },
	nurseId: string,
	on: boolean,
	slots: number
): (boolean, string, { string })
	local out = table.clone(equipped)
	local index = table.find(out, nurseId)
	if not on then
		if index then
			table.remove(out, index)
		end
		return true, "", out
	end
	if type(nurses) ~= "table" or nurses[nurseId] == nil then
		return false, "Hire it first!", out
	end
	if index then
		return true, "", out
	end
	if #out >= math.max(0, math.floor(num(slots, 0))) then
		return false, "All slots full!", out
	end
	table.insert(out, nurseId)
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

function Nurse.journal(index: { [string]: string }, roster: any, rarities: any): Journal
	local groups: { [string]: Group } = {}
	for _, rarity in ordered(rarities) do
		groups[rarity] = { Total = 0, Seen = 0, Hired = 0, Complete = false }
	end
	local total, seen, hired = 0, 0, 0
	for _, nurseId in ordered(roster) do
		local nurse = rawget(roster, nurseId)
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
