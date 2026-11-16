--!strict
-- Achievement badges in six tiers (game/README.md "Badges"). Pure: no Roblox services, no requires, so Lune tests it
-- (tests/Badges.spec.luau). Server/Badges counts, levels up and pays; the Badge Book only reads the Snapshot.
--
-- The save:
--   Data.Stats   { [counter]: number }  what's been done, all time ("Cures", "Made:Remedy", ...). "Seeded" = 1
--                once the counters were worked out from an older save (Badges.seed)
--   Data.Badges  { [BadgeId]: tier }    the tier whose rewards were handed out (0..6). Tiers only ever go up
--
--   Badges.DERIVED                     stats read from the save instead of a counter: PlayHours, Beats, Builder
--                                      (rooms + Stats.RoomsBefore + decor), Rebirths (Data.Rebirth.Count)
--   Badges.statValue(data, stat): number      a counter (0 if missing) or a derived stat. `data` may be the save or
--                                             a Snapshot (same field names)
--   Badges.tierFor(value, thresholds): number 0..#thresholds
--   Badges.progress(value, thresholds): { Tier, Prev, Next?, Ratio }   for a progress bar (Next nil = maxed)
--   Badges.ups(saved, data, defs, force?): { { Id, From, To } }   badges whose tier went past the saved one (force:
--                                             every badge to its top tier, for the 🛠️ Admin panel)
--   Badges.reward(from, to, tiers): { Cash, Stars }   the rewards of tiers from+1..to
--   Badges.effects(saved, defs): { Effect }   each badge's permanent boost x the tier reached (Logic/Boosts)
--   Badges.boostAt(def, tier): number         that badge's boost percent at a tier
--   Badges.add(stats, counts): stats          a copy with each { [counter]: n } added (whole n > 0 only)
--   Badges.seed(data, creatures): stats       counters worked out from an older save: Cures from Cured; per-wing,
--                                             night and per-station counts from the Patient Book (each cure needed
--                                             one treatment made); Visitors 1 if a visitor was ever cured
--   Badges.maxed(stats, defs): stats          every counter badge's counter at least its top threshold (Admin)

export type Tier = { Id: string, Name: string, Icon: string, Color: string, Cash: number, Stars: number }
export type Boost = { Kind: string, Scope: string?, Percent: number }
export type Def = {
	Id: string,
	Name: string,
	Icon: string,
	Category: string,
	Stat: string,
	Goal: string,
	Thresholds: { number },
	Boost: Boost,
}
export type Up = { Id: string, From: number, To: number }
export type Effect = { Kind: string, Scope: string?, Percent: number }
export type Progress = { Tier: number, Prev: number, Next: number?, Ratio: number }
export type Creature = { Wing: string, Station: string?, Night: boolean }

local Badges = {}

Badges.DERIVED = table.freeze({ PlayHours = true, Beats = true, Builder = true, Rebirths = true })
Badges.SEEDED = "Seeded"

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function count(value: any): number
	return if finite(value) then math.max(0, math.floor(value)) else 0
end

local function size(map: any, skip: string?): number
	local n = 0
	if type(map) == "table" then
		for key, flag in map do
			if flag == true and key ~= skip then
				n += 1
			end
		end
	end
	return n
end

function Badges.statValue(data: any, stat: string): number
	if type(data) ~= "table" then
		return 0
	end
	if stat == "PlayHours" then
		local playtime = data.Playtime
		return if type(playtime) == "table" then count(playtime.TotalSeconds) // 3600 else 0
	elseif stat == "Beats" then
		local total = 0
		if type(data.Story) == "table" then
			for _, entry in data.Story do
				if type(entry) == "table" then
					total += count(entry.Beat)
				end
			end
		end
		return total
	elseif stat == "Builder" then
		-- Progression v2: + the rooms rebirths reset (Stats.RoomsBefore), so a rebirth never empties the bar
		local owned = if type(data.Decor) == "table" then data.Decor.Owned else nil
		local before = if type(data.Stats) == "table" then count(data.Stats.RoomsBefore) else 0
		return size(data.Rooms, "Stand") + before + size(owned)
	elseif stat == "Rebirths" then
		local rebirth = data.Rebirth
		return if type(rebirth) == "table" then count(rebirth.Count) else 0
	end
	return if type(data.Stats) == "table" then count(data.Stats[stat]) else 0
end

function Badges.tierFor(value: number, thresholds: { number }): number
	local tier = 0
	for index, needed in thresholds do
		if finite(value) and value >= needed then
			tier = index
		else
			break
		end
	end
	return tier
end

function Badges.progress(value: number, thresholds: { number }): Progress
	local tier = Badges.tierFor(value, thresholds)
	local prev = if tier > 0 then thresholds[tier] else 0
	local nextAt = thresholds[tier + 1]
	if nextAt == nil then
		return { Tier = tier, Prev = prev, Next = nil, Ratio = 1 }
	end
	local span = math.max(1, nextAt - prev)
	return { Tier = tier, Prev = prev, Next = nextAt, Ratio = math.clamp((count(value) - prev) / span, 0, 1) }
end

function Badges.ups(saved: { [string]: number }, data: any, defs: { Def }, force: boolean?): { Up }
	local out: { Up } = {}
	for _, def in defs do
		local from = count(saved[def.Id])
		local to = if force then #def.Thresholds else Badges.tierFor(Badges.statValue(data, def.Stat), def.Thresholds)
		if to > from then
			table.insert(out, { Id = def.Id, From = from, To = to })
		end
	end
	return out
end

function Badges.reward(from: number, to: number, tiers: { Tier }): { Cash: number, Stars: number }
	local cash, stars = 0, 0
	for index = math.max(1, count(from) + 1), math.min(#tiers, count(to)) do
		cash += tiers[index].Cash
		stars += tiers[index].Stars
	end
	return { Cash = cash, Stars = stars }
end

function Badges.boostAt(def: Def, tier: number): number
	return def.Boost.Percent * math.clamp(count(tier), 0, #def.Thresholds)
end

function Badges.effects(saved: { [string]: number }, defs: { Def }): { Effect }
	local out: { Effect } = {}
	for _, def in defs do
		local percent = Badges.boostAt(def, saved[def.Id] or 0)
		if percent > 0 then
			table.insert(out, { Kind = def.Boost.Kind, Scope = def.Boost.Scope, Percent = percent })
		end
	end
	return out
end

function Badges.add(stats: { [string]: number }, counts: { [string]: number }): { [string]: number }
	local out = table.clone(stats)
	for key, n in counts do
		if type(key) == "string" and finite(n) and n >= 1 then
			out[key] = count(out[key]) + math.floor(n)
		end
	end
	return out
end

function Badges.seed(data: any, creatures: { [string]: Creature }): { [string]: number }
	local stats: { [string]: number } = {}
	local function bump(key: string, n: number)
		stats[key] = (stats[key] or 0) + n
	end
	stats.Cures = count(data.Cured)
	if type(data.Book) == "table" then
		for patientId, page in data.Book do
			local info = creatures[patientId]
			local cured = if type(page) == "table" then count(page.Cured) else 0
			if info and cured > 0 then
				bump("Cures:" .. info.Wing, cured)
				if info.Night then
					bump("NightCures", cured)
				end
				if info.Station then
					bump("Made:" .. info.Station, cured)
				end
			end
		end
	end
	if count(data.VisitorDay) > 0 then
		stats.Visitors = 1
	end
	stats[Badges.SEEDED] = 1
	return stats
end

function Badges.maxed(stats: { [string]: number }, defs: { Def }): { [string]: number }
	local out = table.clone(stats)
	for _, def in defs do
		if not Badges.DERIVED[def.Stat] then
			out[def.Stat] = math.max(count(out[def.Stat]), def.Thresholds[#def.Thresholds] or 0)
		end
	end
	return out
end

return table.freeze(Badges)
