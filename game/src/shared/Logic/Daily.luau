--!strict
-- The daily rules (build plan §B6): Today's Visitor, banked daily goals, the mailbox and seasonal date windows.
-- Pure: no Roblox services, no requires, every input passed in, inputs never changed. Spec: tests/Daily.spec.luau.
--
-- No streaks, nothing is ever lost (design §5.5):
--   · goals bank up to `max` (one per new UTC day) and never expire; a full bank just waits for you
--   · the mailbox gift is the same whether you were away one day or ten
--
--   Daily.day(unix): number                         the UTC day number (os.time() // 86400)
--   Daily.visitor(day, pool): PatientId             deterministic per day, the same on every server; never the
--                                                   same two days running, and everyone in the pool comes round
--   Daily.grant(daily, today, pool, max): daily     adds one goal per new day, banked up to max, never removes
--   Daily.onEvent(daily, kind, ctx): daily          kind "Cure" (a patient treated) | "Make" (a supply taken or a
--                                                   medicine dispensed). ctx = { Pool = goal defs (required),
--                                                   Night: boolean?, Wing: WingId? (both for "Cure") }
--   Daily.claim(daily, index, pool): (daily, reward?)  reward = { Cash, Stars } once the goal reached its Target
--   Daily.mailboxReady(lastSeenDay, today): boolean
-- Extra helpers (the server Daily and Events use them):
--   Daily.mailboxGift(lastSeenDay, today, gift): number   `gift` when ready, else 0
--   Daily.eligible(pool, wings): { GoalDef }        the goals a player can finish: CureWing only for wings in `wings`
--   Daily.visitorPool(patients, wings): { PatientId }   who can be Today's Visitor, from patient -> wing: the day
--                                                   patients (not Night) whose wing needs no rebirths and comes by
--                                                   road (Data/Wings Rebirths / Only), in the patients' Order. A
--                                                   species has no case of its own: it rolls one when it comes
--   Daily.treatableWings(pools, cases, can): { [WingId]: boolean }   the wings this clinic can treat: pools =
--                                                   Data/Cases.POOLS, cases = Data/Cases, can(caseId) = this clinic
--                                                   can treat that case (Logic/Visit.canTreat). A wing counts when
--                                                   its pool has a case `can` allows, and, if its pool brings a
--                                                   room's own case (Bath: Sore muscles, Winter: Chills), once one of
--                                                   those can come too: a Bubble Pond goal or visitor waits for the
--                                                   Bath Room, as it always has
--   Daily.prune(daily, pool): daily                 drops goals whose Id left the pool (content removed in an update)
--   Daily.readyCount(daily, pool): number           goals at their target, waiting to be claimed
--   Daily.find(pool, id): GoalDef?
--   Daily.dateDay("YYYY-MM-DD"): number?            a UTC date as a day number (nil if it isn't a real date)
--   Daily.inWindow(today, { Start, End }): boolean  inclusive at both ends; a broken window is never on
--
-- `daily` is Data.Daily: { Goals: { { Id, Progress, Day } }, LastGrantDay }. `pool` is Data/DailyGoals or a filtered
-- copy of it (an array of goal defs). The kinds keep their saved names ("Cure", "CureWing"...); players read "treat".

export type Goal = { Id: string, Progress: number, Day: number }
export type DailyData = { Goals: { Goal }, LastGrantDay: number }
export type Reward = { Cash: number, Stars: number }
export type GoalDef = {
	Id: string,
	Kind: string, -- "Cure" | "CureNight" | "Make" | "CureWing"
	Target: number,
	Wing: string?,
	Icon: string,
	Reward: Reward,
}
export type EventCtx = { Pool: { GoalDef }?, Night: boolean?, Wing: string? }
export type Window = { Start: string, End: string }

local Daily = {}

local SECONDS_PER_DAY = 86400
local TWO_32 = 4294967296

------------------------------------------------------------------------------------------------------------------
-- Deterministic hashing (identical in Lune and on every Roblox server)
------------------------------------------------------------------------------------------------------------------

-- (a * b) mod 2^32 without losing precision in a double.
local function mul32(a: number, b: number): number
	return (((a // 65536) * b % 65536) * 65536 + (a % 65536) * b) % TWO_32
end

-- MurmurHash3's 32-bit finaliser: small input changes scatter across the whole range.
local function hash(n: number): number
	local h = math.floor(n) % TWO_32
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 0xC2B2AE35)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h
end

-- A seeded shuffle of 1..n (Fisher-Yates).
local function shuffled(n: number, seed: number): { number }
	local order = table.create(n)
	for i = 1, n do
		order[i] = i
	end
	for i = n, 2, -1 do
		local j = hash(seed * 64 + i) % i + 1
		order[i], order[j] = order[j], order[i]
	end
	return order
end

local function copyDaily(daily: DailyData): DailyData
	local goals = table.create(#daily.Goals)
	for i, goal in daily.Goals do
		goals[i] = { Id = goal.Id, Progress = goal.Progress, Day = goal.Day }
	end
	return { Goals = goals, LastGrantDay = daily.LastGrantDay }
end

local function isIndex(value: any, count: number): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= 1 and value <= count
end

------------------------------------------------------------------------------------------------------------------
-- Days and the visitor
------------------------------------------------------------------------------------------------------------------

function Daily.day(unix: number): number
	return unix // SECONDS_PER_DAY
end

-- The pool is walked in shuffled rounds of n days, so everyone comes round once per round. Where one round meets
-- the next, the first two days swap if needed, so the same creature never visits two days running.
function Daily.visitor(day: number, pool: { string }): string
	local n = #pool
	if n == 0 then
		return ""
	elseif n == 1 then
		return pool[1]
	elseif n == 2 then
		return pool[day % 2 + 1]
	end
	local round, position = day // n, day % n + 1
	local order = shuffled(n, round)
	if position <= 2 and order[1] == shuffled(n, round - 1)[n] then
		order[1], order[2] = order[2], order[1]
	end
	return pool[order[position]]
end

------------------------------------------------------------------------------------------------------------------
-- Goals
------------------------------------------------------------------------------------------------------------------

function Daily.find(pool: { GoalDef }, id: string): GoalDef?
	for _, def in pool do
		if def.Id == id then
			return def
		end
	end
	return nil
end

function Daily.grant(daily: DailyData, today: number, pool: { GoalDef }, max: number): DailyData
	local out = copyDaily(daily)
	if today <= out.LastGrantDay then
		return out
	end
	-- A first-ever grant (LastGrantDay 0) is one new day, not twenty thousand.
	local newDays = if out.LastGrantDay <= 0 then 1 else today - out.LastGrantDay
	local add = math.min(newDays, max - #out.Goals)
	for n = 1, add do
		local candidates = {}
		for _, def in pool do
			local held = false
			for _, goal in out.Goals do
				if goal.Id == def.Id then
					held = true
					break
				end
			end
			if not held then
				table.insert(candidates, def)
			end
		end
		if #candidates == 0 then
			break
		end
		local pick = candidates[hash(today * 8 + n + 7919) % #candidates + 1]
		table.insert(out.Goals, { Id = pick.Id, Progress = 0, Day = today })
	end
	out.LastGrantDay = today
	return out
end

local function matches(def: GoalDef, kind: string, ctx: EventCtx): boolean
	if kind == "Make" then
		return def.Kind == "Make"
	elseif kind == "Cure" then
		if def.Kind == "Cure" then
			return true
		elseif def.Kind == "CureNight" then
			return ctx.Night == true
		elseif def.Kind == "CureWing" then
			return def.Wing ~= nil and ctx.Wing == def.Wing
		end
	end
	return false
end

function Daily.onEvent(daily: DailyData, kind: string, ctx: EventCtx): DailyData
	local out = copyDaily(daily)
	local pool = type(ctx) == "table" and ctx.Pool
	if type(pool) ~= "table" then
		return out
	end
	for _, goal in out.Goals do
		local def = Daily.find(pool, goal.Id)
		if def and goal.Progress < def.Target and matches(def, kind, ctx) then
			goal.Progress = math.min(def.Target, goal.Progress + 1)
		end
	end
	return out
end

function Daily.claim(daily: DailyData, index: number, pool: { GoalDef }): (DailyData, Reward?)
	local out = copyDaily(daily)
	if not isIndex(index, #out.Goals) then
		return out, nil
	end
	local goal = out.Goals[index]
	local def = Daily.find(pool, goal.Id)
	if not def or goal.Progress < def.Target then
		return out, nil
	end
	table.remove(out.Goals, index)
	return out, { Cash = def.Reward.Cash, Stars = def.Reward.Stars }
end

function Daily.eligible(pool: { GoalDef }, wings: { [string]: boolean }): { GoalDef }
	local out = {}
	for _, def in pool do
		if def.Kind ~= "CureWing" or (def.Wing ~= nil and wings[def.Wing] == true) then
			table.insert(out, def)
		end
	end
	return out
end

-- A keyed Data map's ids: its `.Order` list when it has one, otherwise its string keys sorted.
local function orderOf(map: any): { string }
	if type(map) ~= "table" then
		return {}
	end
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

function Daily.visitorPool(patients: any, wings: any): { string }
	local out: { string } = {}
	for _, patientId in orderOf(patients) do
		local patient = rawget(patients, patientId)
		local wing = if type(patient) == "table" and type(wings) == "table" then rawget(wings, patient.Wing) else nil
		if type(wing) == "table" and patient.Night ~= true and wing.Rebirths == nil and wing.Only == nil then
			table.insert(out, patientId)
		end
	end
	return out
end

function Daily.treatableWings(pools: any, cases: any, can: (string) -> boolean): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(pools) ~= "table" or type(cases) ~= "table" or type(can) ~= "function" then
		return out
	end
	for wingId, pool in pools do
		if type(wingId) ~= "string" or type(pool) ~= "table" then
			continue
		end
		local any, roomCase, roomOk = false, false, false
		for _, caseId in pool do
			local case = if type(caseId) == "string" then rawget(cases, caseId) else nil
			local ok = type(case) == "table" and can(caseId) == true
			any = any or ok
			if type(case) == "table" and case.Room ~= nil then
				roomCase = true
				roomOk = roomOk or ok
			end
		end
		if any and (roomOk or not roomCase) then
			out[wingId] = true
		end
	end
	return out
end

function Daily.prune(daily: DailyData, pool: { GoalDef }): DailyData
	local out = copyDaily(daily)
	for i = #out.Goals, 1, -1 do
		if not Daily.find(pool, out.Goals[i].Id) then
			table.remove(out.Goals, i)
		end
	end
	return out
end

function Daily.readyCount(daily: DailyData, pool: { GoalDef }): number
	local ready = 0
	for _, goal in daily.Goals do
		local def = Daily.find(pool, goal.Id)
		if def and goal.Progress >= def.Target then
			ready += 1
		end
	end
	return ready
end

------------------------------------------------------------------------------------------------------------------
-- Mailbox
------------------------------------------------------------------------------------------------------------------

function Daily.mailboxReady(lastSeenDay: number, today: number): boolean
	return lastSeenDay < today
end

-- Deliberately ignores how many days you were away: no catch-up pile, no reason to feel you missed out.
function Daily.mailboxGift(lastSeenDay: number, today: number, gift: number): number
	return if Daily.mailboxReady(lastSeenDay, today) then gift else 0
end

------------------------------------------------------------------------------------------------------------------
-- Dates (UTC)
------------------------------------------------------------------------------------------------------------------

local function daysInMonth(year: number, month: number): number
	if month == 2 then
		local leap = (year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0
		return if leap then 29 else 28
	end
	return if month == 4 or month == 6 or month == 9 or month == 11 then 30 else 31
end

-- Howard Hinnant's days_from_civil: proleptic Gregorian date -> days since 1970-01-01.
function Daily.dateDay(text: string): number?
	if type(text) ~= "string" then
		return nil
	end
	local ys, ms, ds = string.match(text, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not ys then
		return nil
	end
	local year, month, day = tonumber(ys) :: number, tonumber(ms) :: number, tonumber(ds) :: number
	if month < 1 or month > 12 or day < 1 or day > daysInMonth(year, month) then
		return nil
	end
	local y = if month <= 2 then year - 1 else year
	local era = y // 400
	local yearOfEra = y - era * 400
	local dayOfYear = (153 * (if month > 2 then month - 3 else month + 9) + 2) // 5 + day - 1
	local dayOfEra = yearOfEra * 365 + yearOfEra // 4 - yearOfEra // 100 + dayOfYear
	return era * 146097 + dayOfEra - 719468
end

function Daily.inWindow(today: number, window: Window): boolean
	if type(window) ~= "table" then
		return false
	end
	local first, last = Daily.dateDay(window.Start), Daily.dateDay(window.End)
	if not first or not last then
		return false
	end
	return first <= today and today <= last
end

return Daily
