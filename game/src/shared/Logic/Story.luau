--!strict
-- Regulars' story rules (build plan §B6, design §5.7). Pure: no Roblox services, no requires, so Lune tests it
-- (tests/Story.spec.luau). Safe to require on the client too.
--
--   Story.unlocked(regulars, stars): { RegularId }        unlocked by Clinic Stars, in Regulars.Order
--   Story.due(entry?, today): boolean                       may visit today? (one beat per UTC day)
--   Story.advance(entry?, today): Entry                     the entry after today's beat (a new table)
--   Story.finished(entry?, beats): boolean                  reached the last beat? (beats = count or Beats list)
-- Extras:
--   Story.beat(entry?, today, beats): number                which beat this visit tells (1..#beats)
--   Story.nightOnly(regular): boolean                       Night-wing regulars only visit at night
--   Story.nextDue(regulars, story, stars, today, isNight, can?)   the first regular who should visit now, or nil
--                                                           (`can(regularId)` false: not due yet, e.g. a case the
--                                                           clinic can't treat at its level)
--   Story.unrewarded(regulars, story, ownedDecor, ownedRooms)   finished stories whose reward is missing
--
-- A story day is a real UTC calendar day number (os.time() // 86400), not the 10-minute clinic day.
-- `entry` is Data.Story[regularId]: { Beat, LastBeatDay }, or nil before the first visit. Beat counts the beats
-- already told, so a fresh regular tells beat 1. Missing days skips nothing: the next visit tells the next beat.

export type Entry = { Beat: number, LastBeatDay: number }

local Story = {}

-- A finite number, or 0.
local function num(value: any): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return value
end

local function beatCount(beats: number | { any }): number
	if type(beats) == "table" then
		return #beats
	end
	return num(beats)
end

-- A keyed Data map's ids: its `.Order` list when it has one, otherwise its string keys sorted.
local function orderOf(map: any): { string }
	if type(map.Order) == "table" then
		return map.Order
	end
	local ids = {}
	for id in map do
		if type(id) == "string" then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

-- RegularIds unlocked at this many Clinic Stars, in Regulars.Order.
function Story.unlocked(regulars: any, stars: number): { string }
	local have = num(stars)
	local ids = {}
	for _, regularId in orderOf(regulars) do
		local regular = regulars[regularId]
		if type(regular) == "table" and num(regular.UnlockStars) <= have then
			table.insert(ids, regularId)
		end
	end
	return ids
end

-- May this regular visit today? Yes before their first visit, then once per UTC day.
function Story.due(entry: Entry?, today: number): boolean
	if entry == nil then
		return true
	end
	return num(entry.LastBeatDay) < today
end

-- The entry after one more beat today. Never mutates `entry`.
function Story.advance(entry: Entry?, today: number): Entry
	return { Beat = (if entry then num(entry.Beat) else 0) + 1, LastBeatDay = today }
end

-- Has the story reached its last beat? `beats` is the beat count or the Beats list.
function Story.finished(entry: Entry?, beats: number | { any }): boolean
	if entry == nil then
		return false
	end
	return num(entry.Beat) >= beatCount(beats)
end

-- The beat (1..count) this visit tells: the next one when due, otherwise the one already told today.
function Story.beat(entry: Entry?, today: number, beats: number | { any }): number
	local told = if entry then num(entry.Beat) else 0
	local index = if Story.due(entry, today) then told + 1 else told
	return math.clamp(index, 1, math.max(1, beatCount(beats)))
end

-- Night-wing regulars (DizzyComet: "lost under the stars") only walk in at night.
function Story.nightOnly(regular: any): boolean
	return type(regular) == "table" and regular.Wing == "Night"
end

-- The first regular, in Regulars.Order, who is unlocked, not finished, due today and right for the time of day.
-- `can` (optional) is asked last, about that regular only: false means it simply isn't due yet and the next one is
-- looked at. Server/Patients passes whether the clinic can treat the regular's case (Dizzy Comet's Bumped head is a
-- Lv 2 case: named at Lv 1 it was turned away at the door, and held every other regular back for minutes).
function Story.nextDue(
	regulars: any,
	story: { [string]: Entry }?,
	stars: number,
	today: number,
	isNight: boolean,
	can: ((regularId: string) -> boolean)?
): string?
	local entries = story or {}
	for _, regularId in Story.unlocked(regulars, stars) do
		local regular = regulars[regularId]
		local entry = entries[regularId]
		if
			not Story.finished(entry, regular.Beats or 0)
			and Story.due(entry, today)
			and (isNight or not Story.nightOnly(regular))
			and (can == nil or can(regularId) == true)
		then
			return regularId
		end
	end
	return nil
end

-- RegularIds whose story is finished but whose Reward isn't owned (RewardKind "Room" checks ownedRooms,
-- anything else checks ownedDecor). The server grants these on load, so a reward is never lost.
function Story.unrewarded(
	regulars: any,
	story: { [string]: Entry }?,
	ownedDecor: { [string]: boolean },
	ownedRooms: { [string]: boolean }
): { string }
	local entries = story or {}
	local ids = {}
	for _, regularId in orderOf(regulars) do
		local regular = regulars[regularId]
		if type(regular) == "table" and type(regular.Reward) == "string" then
			local owned = if regular.RewardKind == "Room" then ownedRooms else ownedDecor
			if Story.finished(entries[regularId], regular.Beats or 0) and owned[regular.Reward] ~= true then
				table.insert(ids, regularId)
			end
		end
	end
	return ids
end

return Story
