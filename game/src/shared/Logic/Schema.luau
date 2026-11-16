--!strict
-- Save schema v2 (build plan §B3). Pure: no Roblox services, no requires, so Lune can test it.
--   Schema.default(): Data            a fresh save
--   Schema.reconcile(saved: any, today: number?): Data  repairs anything loaded from a DataStore into a valid
--   v2 save:
--     · v1 shop-sim saves { Cash, Served, Upgrades } migrate: Served -> Cured; Speed, Tray and Tips are kept
--     · unknown fields are dropped, and bad types or non-finite numbers are replaced by defaults
--     · with `today` (the real UTC day), every saved day field later than today is pulled back to today, so a
--       Studio test that moved Workspace.UtcDay forward can't lock a real save out of its mailbox, goals or story
--     · the result never shares a table with `saved`
--   Schema.isNewer(saved: any): boolean  the save was written by a newer schema (never write it back down)
--   Schema.TUTORIAL_FIRST / TUTORIAL_DONE   the Tutorial values for the welcome and for done
--
-- Fields added inside v2 (missing in older v2 saves, so they reconcile to their defaults):
--   VisitorDay      the UTC day this clinic last cured Today's Visitor (0 = never): once per player per day,
--                   across servers
--   HeartsReceived  hearts other players have left on this clinic's sign, all time (cosmetic)
--   Tutorial        the first-session tutorial step (Logic/Tutorial: 1 = the welcome .. 9 = done). A save without
--                   it is migrated: any cure (Cured > 0, a v1 "Served" included) means an existing player, so done;
--                   anyone else starts at the welcome. A fresh save starts at the welcome.
--   Playtime        { Day, TodaySeconds, TotalSeconds, Claimed, Rank } (Logic/Playtime): active play today and all
--                   time, the play gifts opened on Day, the Doctor rank rewarded. A save without it starts at 0 on
--                   `today` (or day 0 without one, which the first tick rolls over to today). Claimed keeps whole
--                   indexes 1..MAX_GIFTS once each, sorted; Day is pulled back to today like the other days
--   Boosts          { [BoostId]: secondsLeft } the timed boosts still running (Logic/Boosts); at most MAX_BOOST_SECONDS
--   Stats           { [counter]: number } badge counters (Logic/Badges). A fresh save is { Seeded = 1 }; a save
--                   without it gets {} and Server/Badges seeds it once from Cured and the Patient Book
--   Badges          { [BadgeId]: tier } the badge tier rewarded so far (0..MAX_TIER)

export type BookPage = { Cured: number, Variants: { [string]: boolean } }
export type StoryEntry = { Beat: number, LastBeatDay: number }
export type Goal = { Id: string, Progress: number, Day: number }
export type Playtime = { Day: number, TodaySeconds: number, TotalSeconds: number, Claimed: { number }, Rank: number }
export type Data = {
	Version: number,
	Cash: number,
	Stars: number,
	Cured: number,
	Upgrades: { [string]: number },
	Rooms: { [string]: boolean },
	Decor: { Owned: { [string]: boolean }, Placed: { [string]: string } },
	Book: { [string]: BookPage },
	Story: { [string]: StoryEntry },
	Daily: { Goals: { Goal }, LastGrantDay: number },
	Mailbox: { LastSeenDay: number },
	HeartsGiven: { Day: number, Plots: { [string]: boolean } },
	ReferralRewarded: boolean,
	VisitorDay: number,
	HeartsReceived: number,
	Tutorial: number,
	Playtime: Playtime,
	Boosts: { [string]: number },
	Stats: { [string]: number },
	Badges: { [string]: number },
}

local Schema = {}

Schema.VERSION = 2
Schema.UPGRADES = table.freeze({ "Speed", "Tray", "Chairs", "Tips" })
Schema.MAX_GOALS = 10 -- a safety cap on banked goals in a save; the real cap is Config.MaxBankedGoals
Schema.MAX_GIFTS = 32 -- a safety cap on play gift indexes; the real list is Data/Playtime.Gifts
Schema.MAX_RANK = 32 -- likewise for Doctor ranks (Data/Playtime.Ranks)
Schema.MAX_TIER = 32 -- likewise for badge tiers (Data/Badges.Tiers)
Schema.MAX_BOOST_SECONDS = 86400 -- a safety cap; the real cap is Config.BoostMaxMinutes
Schema.MAX_KEYS = 128 -- a safety cap on the entries in Stats, Badges and Boosts
Schema.MAX_KEY_LENGTH = 40
-- Logic/Tutorial's WELCOME and DONE, repeated because Schema has no requires (Tutorial.spec checks they match).
Schema.TUTORIAL_FIRST = 1
Schema.TUTORIAL_DONE = 9

function Schema.default(): Data
	local upgrades: { [string]: number } = {}
	for _, id in Schema.UPGRADES do
		upgrades[id] = 0
	end
	return {
		Version = Schema.VERSION,
		Cash = 0,
		Stars = 0,
		Cured = 0,
		Upgrades = upgrades,
		Rooms = { Stand = true },
		Decor = { Owned = {}, Placed = {} },
		Book = {},
		Story = {},
		Daily = { Goals = {}, LastGrantDay = 0 },
		Mailbox = { LastSeenDay = 0 },
		HeartsGiven = { Day = 0, Plots = {} },
		ReferralRewarded = false,
		VisitorDay = 0,
		HeartsReceived = 0,
		Tutorial = Schema.TUTORIAL_FIRST,
		Playtime = { Day = 0, TodaySeconds = 0, TotalSeconds = 0, Claimed = {}, Rank = 0 },
		Boosts = {},
		Stats = { Seeded = 1 }, -- nothing older to count from
		Badges = {},
	}
end

function Schema.isNewer(saved: any): boolean
	return type(saved) == "table" and type(saved.Version) == "number" and saved.Version > Schema.VERSION
end

-- A finite number, floored and at least `min`; otherwise nil.
local function count(value: any, min: number): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return math.max(min, math.floor(value))
end

local function countOr(value: any, fallback: number): number
	return count(value, 0) or fallback
end

local function isTable(value: any): boolean
	return type(value) == "table"
end

-- { [string]: true } maps: keep string keys whose value is exactly true.
local function trueSet(value: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if isTable(value) then
		for key, flag in value do
			if type(key) == "string" and flag == true then
				out[key] = true
			end
		end
	end
	return out
end

local function stringMap(value: any): { [string]: string }
	local out: { [string]: string } = {}
	if isTable(value) then
		for key, item in value do
			if type(key) == "string" and type(item) == "string" then
				out[key] = item
			end
		end
	end
	return out
end

local function reconcileBook(value: any): { [string]: BookPage }
	local out: { [string]: BookPage } = {}
	if not isTable(value) then
		return out
	end
	for patientId, page in value do
		if type(patientId) == "string" and isTable(page) then
			out[patientId] = {
				Cured = countOr(page.Cured, 0),
				Variants = trueSet(page.Variants),
			}
		end
	end
	return out
end

local function reconcileStory(value: any): { [string]: StoryEntry }
	local out: { [string]: StoryEntry } = {}
	if not isTable(value) then
		return out
	end
	for regularId, entry in value do
		if type(regularId) == "string" and isTable(entry) then
			out[regularId] = {
				Beat = countOr(entry.Beat, 0),
				LastBeatDay = countOr(entry.LastBeatDay, 0),
			}
		end
	end
	return out
end

local function reconcileGoals(value: any): { Goal }
	local out: { Goal } = {}
	if not isTable(value) then
		return out
	end
	for _, goal in ipairs(value) do
		if #out >= Schema.MAX_GOALS then
			break
		end
		if isTable(goal) and type(goal.Id) == "string" then
			table.insert(out, {
				Id = goal.Id,
				Progress = countOr(goal.Progress, 0),
				Day = countOr(goal.Day, 0),
			})
		end
	end
	return out
end

-- { [string]: number } maps (Stats, Badges, Boosts): short string keys, finite numbers floored into min..max,
-- entries at `min` dropped when `dropMin`, at most MAX_KEYS entries.
local function numberMap(value: any, min: number, max: number, dropMin: boolean): { [string]: number }
	local out: { [string]: number } = {}
	if not isTable(value) then
		return out
	end
	local kept = 0
	for key, item in value do
		if kept >= Schema.MAX_KEYS then
			break
		end
		local n = count(item, min)
		if
			type(key) == "string"
			and #key > 0
			and #key <= Schema.MAX_KEY_LENGTH
			and n
			and not (dropMin and n <= min)
		then
			out[key] = math.min(max, n)
			kept += 1
		end
	end
	return out
end

local function reconcilePlaytime(value: any, today: number?): Playtime
	local out: Playtime = { Day = 0, TodaySeconds = 0, TotalSeconds = 0, Claimed = {}, Rank = 0 }
	if not isTable(value) then
		-- An older save: it starts at 0, on today.
		out.Day = count(today, 0) or 0
		return out
	end
	out.Day = countOr(value.Day, 0)
	out.TodaySeconds = countOr(value.TodaySeconds, 0)
	out.TotalSeconds = math.max(countOr(value.TotalSeconds, 0), out.TodaySeconds)
	out.Rank = math.min(Schema.MAX_RANK, countOr(value.Rank, 0))
	if isTable(value.Claimed) then
		local seen: { [number]: boolean } = {}
		for _, index in ipairs(value.Claimed) do
			if
				type(index) == "number"
				and index % 1 == 0
				and index >= 1
				and index <= Schema.MAX_GIFTS
				and not seen[index]
			then
				seen[index] = true
				table.insert(out.Claimed, index)
			end
		end
		table.sort(out.Claimed)
	end
	return out
end

-- Pulls every saved day field that's later than `today` back to today.
local function clampDays(data: Data, today: number)
	local function clamp(day: number): number
		return math.min(day, today)
	end
	data.VisitorDay = clamp(data.VisitorDay)
	data.Mailbox.LastSeenDay = clamp(data.Mailbox.LastSeenDay)
	data.Daily.LastGrantDay = clamp(data.Daily.LastGrantDay)
	for _, goal in data.Daily.Goals do
		goal.Day = clamp(goal.Day)
	end
	for _, entry in data.Story do
		entry.LastBeatDay = clamp(entry.LastBeatDay)
	end
	data.HeartsGiven.Day = clamp(data.HeartsGiven.Day)
	data.Playtime.Day = clamp(data.Playtime.Day)
end

function Schema.reconcile(saved: any, today: number?): Data
	local data = Schema.default()
	if not isTable(saved) then
		return data
	end

	data.Cash = countOr(saved.Cash, 0)
	data.Stars = countOr(saved.Stars, 0)
	-- v1 counted "Served"; v2 counts "Cured".
	data.Cured = count(saved.Cured, 0) or countOr(saved.Served, 0)

	if isTable(saved.Upgrades) then
		for _, id in Schema.UPGRADES do
			local level = count(saved.Upgrades[id], 0)
			if level then
				data.Upgrades[id] = level
			end
		end
	end

	data.Rooms = trueSet(saved.Rooms)
	data.Rooms.Stand = true

	if isTable(saved.Decor) then
		data.Decor.Owned = trueSet(saved.Decor.Owned)
		data.Decor.Placed = stringMap(saved.Decor.Placed)
	end

	data.Book = reconcileBook(saved.Book)
	data.Story = reconcileStory(saved.Story)

	if isTable(saved.Daily) then
		data.Daily.Goals = reconcileGoals(saved.Daily.Goals)
		data.Daily.LastGrantDay = countOr(saved.Daily.LastGrantDay, 0)
	end

	if isTable(saved.Mailbox) then
		data.Mailbox.LastSeenDay = countOr(saved.Mailbox.LastSeenDay, 0)
	end

	if isTable(saved.HeartsGiven) then
		data.HeartsGiven.Day = countOr(saved.HeartsGiven.Day, 0)
		data.HeartsGiven.Plots = trueSet(saved.HeartsGiven.Plots)
	end

	data.ReferralRewarded = saved.ReferralRewarded == true
	data.VisitorDay = countOr(saved.VisitorDay, 0)
	data.HeartsReceived = countOr(saved.HeartsReceived, 0)

	-- The tutorial step. A save from before the tutorial existed has none: a player with any cure already knows
	-- the game (done), anyone else starts at the welcome.
	local tutorial = saved.Tutorial
	if
		type(tutorial) == "number"
		and tutorial % 1 == 0
		and tutorial >= Schema.TUTORIAL_FIRST
		and tutorial <= Schema.TUTORIAL_DONE
	then
		data.Tutorial = tutorial
	else
		data.Tutorial = if data.Cured > 0 then Schema.TUTORIAL_DONE else Schema.TUTORIAL_FIRST
	end

	-- Time-played rewards, boosts and badges. A save from before them starts at 0 (Stats unseeded: {}).
	data.Playtime = reconcilePlaytime(saved.Playtime, today)
	data.Boosts = numberMap(saved.Boosts, 0, Schema.MAX_BOOST_SECONDS, true)
	data.Stats = numberMap(saved.Stats, 0, math.huge, false)
	data.Badges = numberMap(saved.Badges, 0, Schema.MAX_TIER, true)

	local realDay = count(today, 0)
	if realDay then
		clampDays(data, realDay)
	end
	return data
end

return Schema
