--!strict
-- Time-played rewards: the daily play gifts and the Doctor ranks (game/README.md "Play gifts, Doctor ranks, boosts
-- and badges"). Pure: no Roblox services, no requires, so Lune tests it (tests/Playtime.spec.luau). Server/Playtime
-- counts the seconds and owns the save; the client only reads (the Snapshot and the PlayToday/PlayTotal attributes).
--
-- The save, Data.Playtime = { Day, TodaySeconds, TotalSeconds, Claimed, Rank }:
--   Day           the UTC day that TodaySeconds and Claimed belong to
--   TodaySeconds  active play on Day: only at your own clinic, paused while you're idle (Server/Playtime)
--   TotalSeconds  active play, all time: Doctor ranks and the ⏱️ Dedication badge
--   Claimed       the gifts opened on Day, as indexes into Data/Playtime.Gifts
--   Rank          the highest Doctor rank whose one-time rewards were handed out (0 = none yet)
-- No streaks, nothing to miss: a new day simply refills the gifts, and a day away costs nothing.
--
--   Playtime.giftSeconds(gift) · Playtime.rankSeconds(rank)   a gift's or rank's threshold in seconds
--   Playtime.rollover(save, today): Save          a copy; on another day, TodaySeconds and Claimed start again
--   Playtime.add(save, today, seconds): Save      rollover, then seconds (> 0, finite) onto today's and the total
--   Playtime.state(save, today, gifts, i)         "Locked" | "Ready" | "Claimed" (nil for a bad index)
--   Playtime.ready(save, today, gifts): { number }   the gifts unlocked and not opened yet
--   Playtime.claim(save, today, gifts, i): (Save, Gift?)   opens a Ready gift; anything else returns no gift
--   Playtime.nextGift(save, today, gifts): (i?, secondsLeft)   the next gift still locked (nil, 0 when none)
--   Playtime.allOpened(save, today, gifts): boolean   every gift opened today: the natural stopping point
--   Playtime.rankFor(totalSeconds, ranks): number    the rank those seconds reach (0 = none yet)
--   Playtime.nextRank(totalSeconds, ranks): (i?, secondsLeft)
--   Playtime.newRanks(save, ranks): { number }      ranks reached but not rewarded yet (save.Rank + 1 ..)
--   Playtime.active(lastActive, now, idleSeconds): boolean   moved or acted within idleSeconds
--   Playtime.duration(seconds): string   "45s" · "12m" · "4h" · "4h 12m"
--   Playtime.clock(seconds): string      "3:05" (rounded up, so 0:00 only at zero) · "1:02:05" past an hour

export type Gift = { Minutes: number, Icon: string, Cash: number, Stars: number, Boost: string? }
export type Rank = { Id: string, Name: string, Icon: string, Hours: number, Decor: string, Cash: number }
export type Save = { Day: number, TodaySeconds: number, TotalSeconds: number, Claimed: { number }, Rank: number }
export type GiftState = "Locked" | "Ready" | "Claimed"

local Playtime = {}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isIndex(value: any, count: number): boolean
	return finite(value) and value % 1 == 0 and value >= 1 and value <= count
end

local function copy(save: Save): Save
	return {
		Day = save.Day,
		TodaySeconds = save.TodaySeconds,
		TotalSeconds = save.TotalSeconds,
		Claimed = table.clone(save.Claimed),
		Rank = save.Rank,
	}
end

function Playtime.giftSeconds(gift: Gift): number
	return if finite(gift.Minutes) then math.max(0, gift.Minutes) * 60 else math.huge
end

function Playtime.rankSeconds(rank: Rank): number
	return if finite(rank.Hours) then math.max(0, rank.Hours) * 3600 else math.huge
end

------------------------------------------------------------------------------------------------------------------
-- Today
------------------------------------------------------------------------------------------------------------------

function Playtime.rollover(save: Save, today: number): Save
	local out = copy(save)
	if out.Day ~= today then
		out.Day = today
		out.TodaySeconds = 0
		out.Claimed = {}
	end
	return out
end

function Playtime.add(save: Save, today: number, seconds: number): Save
	local out = Playtime.rollover(save, today)
	if finite(seconds) and seconds > 0 then
		out.TodaySeconds += seconds
		out.TotalSeconds += seconds
	end
	return out
end

function Playtime.state(save: Save, today: number, gifts: { Gift }, index: number): GiftState?
	if not isIndex(index, #gifts) then
		return nil
	end
	local rolled = Playtime.rollover(save, today)
	if table.find(rolled.Claimed, index) then
		return "Claimed"
	end
	return if rolled.TodaySeconds >= Playtime.giftSeconds(gifts[index]) then "Ready" else "Locked"
end

function Playtime.ready(save: Save, today: number, gifts: { Gift }): { number }
	local out = {}
	for index in gifts do
		if Playtime.state(save, today, gifts, index) == "Ready" then
			table.insert(out, index)
		end
	end
	return out
end

function Playtime.claim(save: Save, today: number, gifts: { Gift }, index: number): (Save, Gift?)
	local out = Playtime.rollover(save, today)
	if Playtime.state(out, today, gifts, index) ~= "Ready" then
		return out, nil
	end
	table.insert(out.Claimed, index)
	table.sort(out.Claimed)
	return out, gifts[index]
end

function Playtime.nextGift(save: Save, today: number, gifts: { Gift }): (number?, number)
	local rolled = Playtime.rollover(save, today)
	local best: number?, bestLeft = nil, math.huge
	for index, gift in gifts do
		local left = Playtime.giftSeconds(gift) - rolled.TodaySeconds
		if left > 0 and not table.find(rolled.Claimed, index) and left < bestLeft then
			best, bestLeft = index, left
		end
	end
	return best, if best then bestLeft else 0
end

function Playtime.allOpened(save: Save, today: number, gifts: { Gift }): boolean
	for index in gifts do
		if Playtime.state(save, today, gifts, index) ~= "Claimed" then
			return false
		end
	end
	return true
end

------------------------------------------------------------------------------------------------------------------
-- Doctor ranks
------------------------------------------------------------------------------------------------------------------

function Playtime.rankFor(totalSeconds: number, ranks: { Rank }): number
	local seconds = if finite(totalSeconds) then totalSeconds else 0
	local reached = 0
	for index, rank in ranks do
		if seconds >= Playtime.rankSeconds(rank) then
			reached = index
		end
	end
	return reached
end

function Playtime.nextRank(totalSeconds: number, ranks: { Rank }): (number?, number)
	local seconds = if finite(totalSeconds) then totalSeconds else 0
	for index, rank in ranks do
		local left = Playtime.rankSeconds(rank) - seconds
		if left > 0 then
			return index, left
		end
	end
	return nil, 0
end

function Playtime.newRanks(save: Save, ranks: { Rank }): { number }
	local out = {}
	local from = if isIndex(save.Rank, #ranks) then save.Rank else 0
	for index = from + 1, Playtime.rankFor(save.TotalSeconds, ranks) do
		table.insert(out, index)
	end
	return out
end

------------------------------------------------------------------------------------------------------------------
-- Idle and text
------------------------------------------------------------------------------------------------------------------

function Playtime.active(lastActive: number, now: number, idleSeconds: number): boolean
	if not (finite(lastActive) and finite(now) and finite(idleSeconds)) then
		return false
	end
	return now - lastActive < idleSeconds
end

function Playtime.duration(seconds: number): string
	local s = if finite(seconds) then math.max(0, math.floor(seconds)) else 0
	if s < 60 then
		return s .. "s"
	end
	local minutes = s // 60
	if minutes < 60 then
		return minutes .. "m"
	end
	local hours, rest = minutes // 60, minutes % 60
	return if rest == 0 then hours .. "h" else hours .. "h " .. rest .. "m"
end

function Playtime.clock(seconds: number): string
	local s = if finite(seconds) then math.max(0, math.ceil(seconds)) else 0
	if s >= 3600 then
		return string.format("%d:%02d:%02d", s // 3600, (s // 60) % 60, s % 60)
	end
	return string.format("%d:%02d", s // 60, s % 60)
end

return table.freeze(Playtime)
