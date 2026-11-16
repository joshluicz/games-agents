--!strict
-- The "coming up" chip's rules (look build plan §B9; memory-20261116-022: countdowns only for FREE events). Pure: no
-- Roblox services and no requires, so Lune can test it. The HUD's Status zone (one chip: Golden Hour) and the
-- tutorial's finale (one "COMING UP" chip) both pick with it, so neither can ever show a timer on something paid.
--
--   NextEvent.pick(now, candidates, maxAhead?): View?
--       the soonest candidate whose At is after `now` and at most `maxAhead` seconds away (MAX_AHEAD, 6 h, unless
--       given). Ties keep the list's order. A candidate with Paid = true is NEVER picked (CLAUDE.md red line 3),
--       and neither is one with a broken At. Returns a fresh { Id, Icon, Name, At } (Types.NextEventView)
--   NextEvent.label(seconds): string
--       "in 12m" · "in 1h 5m" · "in 2h" · "in 1m" for anything under 2 minutes. Minutes only, never seconds: a
--       chip that ticks every second reads as pressure
-- `now` and every At are on one clock (the server's: Workspace:GetServerTimeNow()).

local NextEvent = {}

NextEvent.MAX_AHEAD = 6 * 3600 -- an event further off than this isn't "coming up": the chip hides

export type Candidate = { Id: string, Icon: string, Name: string, At: number, Paid: boolean? }
export type View = { Id: string, Icon: string, Name: string, At: number }

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function NextEvent.pick(now: number, candidates: { Candidate }, maxAhead: number?): View?
	if not finite(now) or type(candidates) ~= "table" then
		return nil
	end
	local ahead = if finite(maxAhead) and (maxAhead :: number) > 0 then maxAhead :: number else NextEvent.MAX_AHEAD
	local best: Candidate? = nil
	for _, candidate in candidates do
		if
			type(candidate) == "table"
			and candidate.Paid ~= true
			and finite(candidate.At)
			and candidate.At > now
			and candidate.At - now <= ahead
			and (best == nil or candidate.At < best.At)
		then
			best = candidate
		end
	end
	if not best then
		return nil
	end
	return { Id = best.Id, Icon = best.Icon, Name = best.Name, At = best.At }
end

function NextEvent.label(seconds: number): string
	local left = if finite(seconds) then math.max(seconds, 0) else 0
	local minutes = math.max(1, math.floor(left / 60))
	if minutes < 60 then
		return "in " .. minutes .. "m"
	end
	local hours = math.floor(minutes / 60)
	local rest = minutes % 60
	if rest == 0 then
		return "in " .. hours .. "h"
	end
	return "in " .. hours .. "h " .. rest .. "m"
end

return NextEvent
