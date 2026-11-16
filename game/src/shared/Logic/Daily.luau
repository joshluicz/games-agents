--!strict
-- STUB (Task 0). Owned by Task 5: replace with the real daily rules and its spec (tests/Daily.spec.luau).
-- Pure: no Roblox services, no requires. Signatures from build plan §B6.
-- `daily` is Data.Daily: { Goals: { { Id, Progress, Day } }, LastGrantDay: number }.
-- `pool` is Data/DailyGoals (an array of goal defs).

local Daily = {}

-- The UTC day number for a unix time.
function Daily.day(unix: number): number
	return unix // 86400
end

-- Today's Visitor: deterministic for a day, picked from a list of PatientIds.
function Daily.visitor(_day: number, pool: { string }): string
	return pool[1] or ""
end

-- Adds one goal per new day, capped at `max`; never removes progress.
function Daily.grant(daily: any, _today: number, _pool: any, _max: number): any
	return daily
end

-- Raises progress on matching goals. kind: "Cure" | "Make".
function Daily.onEvent(daily: any, _kind: string, _ctx: any): any
	return daily
end

-- Claims goal `index` if its target is met: returns (daily, reward) or (daily, nil).
function Daily.claim(daily: any, _index: number, _pool: any): (any, { Cash: number, Stars: number }?)
	return daily, nil
end

function Daily.mailboxReady(lastSeenDay: number, today: number): boolean
	return lastSeenDay < today
end

return Daily
