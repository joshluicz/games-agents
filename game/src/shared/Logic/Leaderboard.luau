--!strict
-- The leaderboards' rules (Server/Leaderboards, Server/BoardBuilder, UI/Boards; game/README.md "Leaderboards").
-- Pure: no Roblox services, no requires, so Lune tests it (tests/Leaderboard.spec.luau).
--
--   Leaderboard.BOARDS[id]                 { Id, Icon, Title, Caption, Color (a Palette.Candy key), Weekly }
--   Leaderboard.TEXT                       what a board says with no rows (offline, loading, empty) and more
--   Leaderboard.week(unix): number         the UTC week: weeks start Monday 00:00 UTC (week 1 = 1970-01-05)
--   Leaderboard.storeName(id, week, version): string   the OrderedDataStore's name. The weekly board's name has
--                                          the week in it ("Board_Week_v1_w2968"), so it starts empty each Monday
--   Leaderboard.valueOf(id, data, week, extra?): number?   a player's value on a board, from their SAVED data.
--                                          nil = the board doesn't apply to this save (no Data.Level yet...)
--   Leaderboard.values(ids, data, week, version, extra?): { [storeName]: number }   what to write for a player.
--                                          The weekly count goes to the week it was counted in (this week's or,
--                                          just after Monday 00:00, last week's final count)
--   Leaderboard.addWeekCure(entry, week)   counts one cure in the save's WeekCures (a new week starts from 0)
--   Leaderboard.changed(written, values): { string }   the stores whose value is new since the last write (> 0)
--   Leaderboard.backoff(failures, base, max): number    seconds to wait after `failures` failures in a row
--   Leaderboard.isPermanent(err): boolean  an error that retrying won't fix (Studio without API access, a place
--                                          that isn't published): the boards go "open when live" instead
--   Leaderboard.parse(rows, depth): { Entry }          GetSortedAsync rows ({ key, value }) -> entries, junk dropped
--   Leaderboard.merge(entries, live, depth): { Entry } the stored top list with this server's players' live values
--                                          laid over it (live wins: it is their save right now), sorted
--   Leaderboard.rankOf(entries, userId): number?       1-based place, nil when not in the list
--   Leaderboard.format(n): string           1,234 · 1.2M past a million (the plaza boards; the HUD has Hud.format)
--   Leaderboard.excluded(userId, who): boolean   an admin account, kept off every board (Joshua, 2026-11-16: the
--                                          🛠️ Admin panel can add cash and stars, so their numbers are fake):
--                                          the game's owner (who.CreatorIsUser and userId == who.CreatorId) or a
--                                          UserId in who.UserIds (Config.AdminUserIds). Nobody in Studio (who.Studio),
--                                          so the boards can still be tested there
--   Leaderboard.without(entries, who): { Entry }   the list with every excluded account taken out
--
-- Boards that come with the depth update (Hospital Level, Nurse Journal %) are defined here already; they read
-- Data.Level and Data.NurseIndex only if the save has them, and only show once Config.Leaderboards lists them.
-- Progression v2 adds 🏢 Most Rebirths ("Rebirths", caption "Branches"): Data.Rebirth.Count (nil before v4). A 0 is
-- never written (Leaderboard.changed skips zeros), so only players with a rebirth appear.

export type Board = {
	Id: string,
	Icon: string,
	Title: string, -- the board's heading, at most 3 words
	Caption: string, -- its tab in the 🏆 panel, one word
	Color: string, -- a Palette.Candy key
	Weekly: boolean,
}
export type Entry = { UserId: number, Value: number }
export type Extra = { JournalTotal: number? }
-- What GetBoards answers (Server/Leaderboards.payload) and what the plaza boards draw.
export type Status = "Loading" | "Live" | "Offline" -- Offline: no DataStores here (Studio without API access)
export type Row = { Rank: number, Name: string, User: string, Value: number } -- Name = DisplayName, User = @name
-- Rank nil: not in the top Depth (or not on the board yet). Hidden: an admin, never ranked (Leaderboard.excluded).
export type You = { Rank: number?, Value: number, Hidden: boolean? }
export type BoardPayload = { Id: string, Top: { Row }, You: You }
export type Payload = { Status: Status, Depth: number, Boards: { BoardPayload } }
export type Who = { Studio: boolean, CreatorIsUser: boolean, CreatorId: number, UserIds: { number } }

local Leaderboard = {}

-- What a board says instead of rows (the plaza boards and the 🏆 panel).
Leaderboard.TEXT = table.freeze({
	Offline = "Leaderboards open when the game is live", -- Studio without API access
	Loading = "⏳ Loading...",
	Empty = "🌟 Be the first!",
	Join = "Play to join in!", -- your own bar, before you have a value
	Admin = "🛠️ Admins aren't ranked",
})

local MAX_VALUE = 1e15 -- OrderedDataStore values are 64-bit integers; nothing in the game comes near this
local SECONDS_PER_DAY = 86400

local function board(id: string, icon: string, title: string, caption: string, color: string, weekly: boolean): Board
	return table.freeze({
		Id = id,
		Icon = icon,
		Title = title,
		Caption = caption,
		Color = color,
		Weekly = weekly,
	})
end

Leaderboard.BOARDS = table.freeze({
	Cured = board("Cured", "🏥", "Most Cured", "Cured", "Blue", false),
	Stars = board("Stars", "⭐", "Most Stars", "Stars", "Orange", false),
	Hearts = board("Hearts", "❤️", "Most Hearts", "Hearts", "Pink", false),
	Week = board("Week", "🏆", "Cures This Week", "Week", "Purple", true),
	-- The depth update (docs/plan/2026-11-16-depth-update-design.md): add to Config.Leaderboards when it lands.
	Level = board("Level", "🏨", "Top Hospitals", "Level", "Cyan", false),
	Journal = board("Journal", "📔", "Nurse Journal", "Journal", "Lime", false),
	-- Progression v2 (build plan §B7): rebirths done ("branches opened"); admins are kept off it like every board.
	Rebirths = board("Rebirths", "🏢", "Most Rebirths", "Branches", "Purple", false),
}) :: { [string]: Board }

function Leaderboard.isBoard(id: any): boolean
	return type(id) == "string" and rawget(Leaderboard.BOARDS :: any, id) ~= nil
end

-- Day 0 (1970-01-01) was a Thursday, so day 4 is the first Monday: (day + 3) // 7 turns over every Monday.
function Leaderboard.week(unix: number): number
	local day = math.floor(unix / SECONDS_PER_DAY)
	return (day + 3) // 7
end

function Leaderboard.storeName(id: string, week: number, version: number): string
	local name = "Board_" .. id .. "_v" .. tostring(version)
	local def = Leaderboard.BOARDS[id]
	if def and def.Weekly then
		name ..= "_w" .. tostring(week)
	end
	return name
end

-- A finite number as a whole number from 0 to MAX_VALUE; anything else is nil.
local function whole(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return math.clamp(math.floor(value), 0, MAX_VALUE)
end

local function journalPercent(index: any, total: any): number?
	if type(index) ~= "table" or type(total) ~= "number" or total <= 0 then
		return nil
	end
	local hired = 0
	for _, entry in index do
		if entry == "Hired" then
			hired += 1
		end
	end
	return math.clamp(math.floor(100 * hired / total), 0, 100)
end

function Leaderboard.valueOf(id: string, data: any, week: number, extra: Extra?): number?
	if type(data) ~= "table" then
		return nil
	end
	if id == "Cured" then
		return whole(data.Cured)
	elseif id == "Stars" then
		return whole(data.Stars)
	elseif id == "Hearts" then
		return whole(data.HeartsReceived)
	elseif id == "Week" then
		local entry = data.WeekCures
		if type(entry) == "table" and entry.Week == week then
			return whole(entry.Count) or 0
		end
		return 0
	elseif id == "Level" then
		return whole(data.Level) -- nil until the depth update adds Data.Level
	elseif id == "Journal" then
		return journalPercent(data.NurseIndex, extra and extra.JournalTotal)
	elseif id == "Rebirths" then
		local rebirth = data.Rebirth -- nil before the v4 save (Progression v2)
		return if type(rebirth) == "table" then whole(rebirth.Count) else nil
	end
	return nil
end

function Leaderboard.values(
	ids: { string },
	data: any,
	week: number,
	version: number,
	extra: Extra?
): { [string]: number }
	local out: { [string]: number } = {}
	if type(data) ~= "table" then
		return out
	end
	for _, id in ids do
		local def = Leaderboard.BOARDS[id]
		if not def then
			continue
		end
		if def.Weekly then
			-- The count belongs to the week it was made in: a player whose last cure was on Sunday still gets that
			-- final count written to last week's board after Monday 00:00. Older weeks are left alone.
			local entry = data.WeekCures
			if type(entry) == "table" and (entry.Week == week or entry.Week == week - 1) then
				local count = whole(entry.Count)
				if count then
					out[Leaderboard.storeName(id, entry.Week, version)] = count
				end
			end
		else
			local value = Leaderboard.valueOf(id, data, week, extra)
			if value then
				out[Leaderboard.storeName(id, week, version)] = value
			end
		end
	end
	return out
end

-- entry is the save's WeekCures ({ Week, Count }); mutated in place.
function Leaderboard.addWeekCure(entry: { Week: number, Count: number }, week: number)
	if entry.Week ~= week then
		entry.Week = week
		entry.Count = 0
	end
	entry.Count += 1
end

-- Sorted, so the writes go out in a fixed order (and tests can compare lists).
function Leaderboard.changed(written: { [string]: number }, values: { [string]: number }): { string }
	local out: { string } = {}
	for name, value in values do
		if value > 0 and written[name] ~= value then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

function Leaderboard.backoff(failures: number, base: number, max: number): number
	if failures <= 0 then
		return 0
	end
	return math.min(max, base * 2 ^ (failures - 1))
end

function Leaderboard.isPermanent(err: any): boolean
	local text = string.lower(tostring(err))
	return string.find(text, "studioaccesstoapisnotallowed", 1, true) ~= nil
		or string.find(text, "^%s*403") ~= nil
		or string.find(text, "publish", 1, true) ~= nil -- "You must publish this place to the web..."
end

function Leaderboard.parse(rows: any, depth: number): { Entry }
	local out: { Entry } = {}
	if type(rows) ~= "table" then
		return out
	end
	for _, row in ipairs(rows) do
		if #out >= depth then
			break
		end
		if type(row) == "table" then
			local userId = tonumber(row.key)
			local value = whole(row.value)
			if userId and userId > 0 and userId % 1 == 0 and value then
				table.insert(out, { UserId = userId, Value = value })
			end
		end
	end
	return out
end

local function before(a: Entry, b: Entry): boolean
	if a.Value ~= b.Value then
		return a.Value > b.Value
	end
	return a.UserId < b.UserId -- ties: a fixed order, so the boards don't flicker
end

-- live: { [userId] = value } for the players in this server whose save loaded. A live 0 takes them off the list
-- (this week's board on Monday morning).
function Leaderboard.merge(entries: { Entry }, live: { [number]: number }, depth: number): { Entry }
	local out: { Entry } = {}
	for _, entry in entries do
		if live[entry.UserId] == nil then
			table.insert(out, { UserId = entry.UserId, Value = entry.Value })
		end
	end
	for userId, value in live do
		if value > 0 then
			table.insert(out, { UserId = userId, Value = value })
		end
	end
	table.sort(out, before)
	while #out > depth do
		table.remove(out)
	end
	return out
end

function Leaderboard.rankOf(entries: { Entry }, userId: number): number?
	for index, entry in entries do
		if entry.UserId == userId then
			return index
		end
	end
	return nil
end

function Leaderboard.excluded(userId: number, who: Who): boolean
	if who.Studio then
		return false
	end
	if who.CreatorIsUser and userId == who.CreatorId then
		return true
	end
	return table.find(who.UserIds, userId) ~= nil
end

function Leaderboard.without(entries: { Entry }, who: Who): { Entry }
	local out: { Entry } = {}
	for _, entry in entries do
		if not Leaderboard.excluded(entry.UserId, who) then
			table.insert(out, entry)
		end
	end
	return out
end

function Leaderboard.format(n: any): string
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return "0"
	end
	local size = math.floor(math.abs(n))
	local sign = if n < 0 then "-" else ""
	if size >= 1e6 then
		return sign .. (string.gsub(string.format("%.1fM", size / 1e6), "%.0M", "M"))
	end
	local digits = tostring(size)
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return sign .. grouped
end

return Leaderboard
