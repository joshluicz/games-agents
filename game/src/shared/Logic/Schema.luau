--!strict
-- Save schema v4 (build plan §B3; depth-update build plan §B1; Progression v2 build plan §B1). Pure: no Roblox
-- services, no requires, so Lune can test it.
--   Schema.default(): Data            a fresh save
--   Schema.reconcile(saved: any, today: number?): Data  repairs anything loaded from a DataStore into a valid
--   v4 save:
--     · v1 shop-sim saves { Cash, Served, Upgrades } migrate: Served -> Cured; Speed, Tray and Tips are kept
--     · unknown fields are dropped, and bad types or non-finite numbers are replaced by defaults
--     · with `today` (the real UTC day), every saved day field later than today is pulled back to today, so a
--       Studio test that moved Workspace.UtcDay forward can't lock a real save out of its mailbox, goals or story
--     · the result never shares a table with `saved`
--   Schema.isNewer(saved: any): boolean  the save was written by a newer schema (never write it back down)
--   Schema.levelFromRooms(rooms): number  the hospital level a save's rooms imply (for saves from before levels)
--   Schema.xpToNext(level): number       XP from `level` to the next: 10 + 5 x level x (level + 1)
--   Schema.rosterCap(count): number      nurses that may work after `count` rebirths: 3 + count, at most 8
--   Schema.levelCap(count): number       the nurse level cap: 10, or 15 from 3 rebirths
--   Schema.TUTORIAL_FIRST / TUTORIAL_DONE / TUTORIAL_SHOP   the Tutorial values for the welcome, done and step 7
--
-- v4 (Progression v2) adds Rebirth, gives every nurse XP and a Job, drops Equipped, and adds the upgrades WardComfort,
-- AESpeed and NightClinic and the counter Stats.RoomsBefore (the numberMap rules, like every counter). The version went
-- up so a v3 server, still running while the update rolls out, loads a v4 save read-only (isNewer) instead of saving
-- it back without its rebirths. Every v2 and v3 save migrates:
--   Nurses       { [NurseId]: { Level, XP, Copies, Job } }, every entry repaired: Copies a whole number >= 1 (junk ->
--                1); Level whole in 1..levelCap(Rebirth.Count) (junk -> 1; a v3 save's 1..5 is kept); XP whole in
--                0..xpToNext(Level) - 1 (junk -> 0; 0 at the cap); Job a string of 1-20 letters or "" (junk -> ""):
--                "" = the nurse's own Role, a Data/Jobs id, or "Rest" (not working). A v3 save's nurses get XP 0 and
--                Job "" (each works its role). NOTHING IS EVER DELETED, and unknown ids are kept (servers ignore them).
--   Who works    on EVERY load, at most rosterCap(Rebirth.Count) entries have Job ~= "Rest". A v3 save fills those
--                places in its old Equipped order (owned ids, once each), then the rest by NurseId; a v4 save by
--                NurseId. The others get "Rest" (build plan §E2: until you sell or list one, or a rebirth adds a slot).
--   Rebirth      { Count, Points, Tree, Perks, Offer, Theme, Pending, Told }: Count 0..MAX_REBIRTHS and Points
--                0..MAX_POINTS (whole); Tree { [NodeId]: rank 1..MAX_RANK } (numberMap rules; unknown nodes kept, and
--                refunded by ResetTree); Perks (<= MAX_PERKS), Offer (<= MAX_OFFER, none already in Perks) and
--                Pending (<= MAX_PENDING) are arrays of short unique strings; Theme a short string ("" = Candy, junk ->
--                ""); Told only when exactly true.
--   Equipped     gone: read once (a v3 save's working order) and never written again.
--
-- v3 (the depth update) added Level, Nurses, NurseIndex, JournalSets and Simple. A v2 save migrates: Level from its
-- rooms (levelFromRooms), no nurses, an empty journal, Simple off.
--   Level        1..MAX_LEVEL. Missing or junk: the level the rooms imply. ROOM_LEVELS gives, for each room, the
--                highest level whose ⭐ gate is at or below the room's own ⭐ gate (Logic/Levels.impliedByRoom
--                computes the same from Data; Levels.spec checks they match). No rooms: 1.
--   NurseIndex   { [NurseId]: "Seen" | "Hired" }: anything else dropped; every owned nurse is "Hired".
--   JournalSets  { [Rarity]: true }: the journal rarity groups whose reward was granted.
--   Simple       Simple mode (true only when saved exactly true).
--
-- Fields added inside v2 (missing in older v2 saves, so they reconcile to their defaults):
--   VisitorDay      the UTC day this clinic last cured Today's Visitor (0 = never): once per player per day,
--                   across servers
--   HeartsReceived  hearts other players have left on this clinic's sign, all time (cosmetic)
--   Tutorial        the first-session tutorial step (Logic/Tutorial: 1 = the welcome .. 9 = done). A save without
--                   it is migrated: any cure (Cured > 0, a v1 "Served" included) means an existing player, so done;
--                   anyone else starts at the welcome. A fresh save starts at the welcome.
--   TutorialGift    (look overhaul) the step-7 top-up has run or was never needed. A boolean is kept; missing or
--                   junk is derived: true when Tutorial >= TUTORIAL_SHOP (7), since the top-up runs on entering
--                   step 7. So a Replay (DONE -> PATIENT) never gives a second gift, and an older v4 server that
--                   drops the field loses nothing: the next load derives it again. No version bump.
--   WeekCures       this player's cures in one UTC week (Logic/Leaderboard.week), for the weekly leaderboard:
--                   { Week, Count }. A cure in a new week starts the count again (Leaderboard.addWeekCure)
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
export type NurseEntry = { Level: number, XP: number, Copies: number, Job: string }
export type RebirthData = {
	Count: number,
	Points: number,
	Tree: { [string]: number },
	Perks: { string },
	Offer: { string },
	Theme: string,
	Pending: { string },
	Told: boolean,
}
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
	TutorialGift: boolean,
	WeekCures: { Week: number, Count: number },
	Playtime: Playtime,
	Boosts: { [string]: number },
	Stats: { [string]: number },
	Badges: { [string]: number },
	Level: number,
	Nurses: { [string]: NurseEntry },
	NurseIndex: { [string]: string },
	JournalSets: { [string]: boolean },
	Simple: boolean,
	Rebirth: RebirthData,
}

local Schema = {}

Schema.VERSION = 4
Schema.UPGRADES = table.freeze({ "Speed", "Tray", "Chairs", "Tips", "WardComfort", "AESpeed", "NightClinic" })
Schema.MAX_GOALS = 10 -- a safety cap on banked goals in a save; the real cap is Config.MaxBankedGoals
Schema.MAX_GIFTS = 32 -- a safety cap on play gift indexes; the real list is Data/Playtime.Gifts
Schema.MAX_RANK = 32 -- likewise for Doctor ranks (Data/Playtime.Ranks)
Schema.MAX_TIER = 32 -- likewise for badge tiers (Data/Badges.Tiers)
Schema.MAX_BOOST_SECONDS = 86400 -- a safety cap; the real cap is Config.BoostMaxMinutes
Schema.MAX_KEYS = 128 -- a safety cap on the entries in Stats, Badges, Boosts and Rebirth.Tree
Schema.MAX_KEY_LENGTH = 40
-- Logic/Tutorial's WELCOME and DONE, repeated because Schema has no requires (Tutorial.spec checks they match).
Schema.TUTORIAL_FIRST = 1
Schema.TUTORIAL_DONE = 9
Schema.TUTORIAL_SHOP = 7 -- Logic/Tutorial's SHOP: entering it runs the one-time top-up (TutorialGift)
-- Data/Levels, Config.Nurses and Config.Roster values, repeated because Schema has no requires (Levels.spec and
-- Nurse.spec check they match).
Schema.MAX_LEVEL = 5
Schema.MAX_NURSE_LEVEL = 15 -- the highest any cap goes (Lv 15 from R3)
Schema.NURSE_LEVEL_CAP = 10 -- Config.Nurses.MaxLevel
Schema.NURSE_LEVEL_CAP_R3 = 15 -- Config.Nurses.MaxLevel + LevelCapBonus, from LevelCapRebirths
Schema.LEVEL_CAP_REBIRTHS = 3 -- Config.Nurses.LevelCapRebirths
Schema.ROSTER_BASE = 3 -- Config.Roster.Base
Schema.ROSTER_PER_REBIRTH = 1 -- Config.Roster.PerRebirth
Schema.ROSTER_MAX = 8 -- Config.Roster.Max
Schema.MAX_NURSES = 64 -- a safety cap on nurse entries in a save (Data/Nurses has 17)
Schema.MAX_JOB_LENGTH = 20
Schema.REST = "Rest" -- the Job of a nurse that isn't working (Logic/Jobs.REST)
Schema.ROOM_LEVELS = table.freeze({ BathRoom = 1, Ward = 2, WinterWing = 2, Garden = 3 })
-- Rebirth safety caps (the real rules are in Config and Data)
Schema.MAX_REBIRTHS = 1000
Schema.MAX_POINTS = 1000
Schema.MAX_NODE_RANK = 10
Schema.MAX_PERKS = 32
Schema.MAX_OFFER = 3
Schema.MAX_PENDING = 4

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
		TutorialGift = false,
		WeekCures = { Week = 0, Count = 0 },
		Playtime = { Day = 0, TodaySeconds = 0, TotalSeconds = 0, Claimed = {}, Rank = 0 },
		Boosts = {},
		Stats = { Seeded = 1 }, -- nothing older to count from
		Badges = {},
		Level = 1,
		Nurses = {},
		NurseIndex = {},
		JournalSets = {},
		Simple = false,
		Rebirth = {
			Count = 0,
			Points = 0,
			Tree = {},
			Perks = {},
			Offer = {},
			Theme = "",
			Pending = {},
			Told = false,
		},
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

function Schema.xpToNext(level: number): number
	local l = count(level, 1) or 1
	return 10 + 5 * l * (l + 1)
end

function Schema.rosterCap(rebirths: number): number
	local n = math.min(Schema.MAX_REBIRTHS, count(rebirths, 0) or 0)
	return math.min(Schema.ROSTER_MAX, Schema.ROSTER_BASE + Schema.ROSTER_PER_REBIRTH * n)
end

function Schema.levelCap(rebirths: number): number
	local n = count(rebirths, 0) or 0
	return if n >= Schema.LEVEL_CAP_REBIRTHS then Schema.NURSE_LEVEL_CAP_R3 else Schema.NURSE_LEVEL_CAP
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

-- { [string]: number } maps (Stats, Badges, Boosts, Rebirth.Tree): short string keys, finite numbers floored into
-- min..max, entries at `min` dropped when `dropMin`, at most MAX_KEYS entries.
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

function Schema.levelFromRooms(rooms: any): number
	local level = 1
	if isTable(rooms) then
		for roomId, implied in Schema.ROOM_LEVELS do
			if rooms[roomId] == true then
				level = math.max(level, implied)
			end
		end
	end
	return level
end

local function isInteger(value: any): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and math.abs(value) < 1e9
end

local function isJob(value: any): boolean
	return type(value) == "string"
		and (value == "" or (#value <= Schema.MAX_JOB_LENGTH and string.match(value, "^%a+$") ~= nil))
end

-- Every nurse entry repaired (see the header); who works is applyRoster's.
local function reconcileNurses(value: any, cap: number): { [string]: NurseEntry }
	local out: { [string]: NurseEntry } = {}
	if not isTable(value) then
		return out
	end
	local kept = 0
	for nurseId, entry in value do
		if kept >= Schema.MAX_NURSES then
			break
		end
		if type(nurseId) == "string" and #nurseId > 0 and #nurseId <= 40 and isTable(entry) then
			local copies = count(entry.Copies, 1) or 1
			local level = if isInteger(entry.Level) then math.clamp(entry.Level, 1, cap) else 1
			local xp = 0
			if level < cap and isInteger(entry.XP) then
				xp = math.clamp(entry.XP, 0, Schema.xpToNext(level) - 1)
			end
			out[nurseId] = {
				Level = level,
				XP = xp,
				Copies = copies,
				Job = if isJob(entry.Job) then entry.Job else "",
			}
			kept += 1
		end
	end
	return out
end

-- At most `cap` entries keep working (Job ~= "Rest"); the others rest. The working places go to `equipped` first (a
-- v3 save's old Equipped list: in order, owned ids, once each), then to the rest by NurseId. A v3 save comes in with
-- Job "" everywhere, so it keeps exactly its first `cap` equipped nurses on duty. Mutates `nurses`.
local function applyRoster(nurses: { [string]: NurseEntry }, cap: number, equipped: any)
	local order: { string } = {}
	local seen: { [string]: boolean } = {}
	if isTable(equipped) then
		for _, nurseId in ipairs(equipped) do
			if type(nurseId) == "string" and nurses[nurseId] and not seen[nurseId] then
				seen[nurseId] = true
				table.insert(order, nurseId)
			end
		end
	end
	local others: { string } = {}
	for nurseId in nurses do
		if not seen[nurseId] then
			table.insert(others, nurseId)
		end
	end
	table.sort(others)
	for _, nurseId in others do
		table.insert(order, nurseId)
	end
	local working = 0
	for _, nurseId in order do
		local entry = nurses[nurseId]
		if entry.Job ~= Schema.REST then
			if working < cap then
				working += 1
			else
				entry.Job = Schema.REST
			end
		end
	end
end

-- An array of short unique strings: at most `max`, none of them in `skip`.
local function stringList(value: any, max: number, skip: { string }?): { string }
	local out: { string } = {}
	if not isTable(value) then
		return out
	end
	for _, item in ipairs(value) do
		if #out >= max then
			break
		end
		if
			type(item) == "string"
			and #item > 0
			and #item <= Schema.MAX_KEY_LENGTH
			and not table.find(out, item)
			and not (skip and table.find(skip, item))
		then
			table.insert(out, item)
		end
	end
	return out
end

local function reconcileRebirth(value: any): RebirthData
	local out = Schema.default().Rebirth
	if not isTable(value) then
		return out
	end
	out.Count = math.min(Schema.MAX_REBIRTHS, countOr(value.Count, 0))
	out.Points = math.min(Schema.MAX_POINTS, countOr(value.Points, 0))
	out.Tree = numberMap(value.Tree, 0, Schema.MAX_NODE_RANK, true)
	out.Perks = stringList(value.Perks, Schema.MAX_PERKS)
	out.Offer = stringList(value.Offer, Schema.MAX_OFFER, out.Perks)
	local theme = value.Theme
	out.Theme = if type(theme) == "string" and #theme <= Schema.MAX_KEY_LENGTH then theme else ""
	out.Pending = stringList(value.Pending, Schema.MAX_PENDING)
	out.Told = value.Told == true
	return out
end

local function reconcileIndex(value: any, nurses: { [string]: NurseEntry }): { [string]: string }
	local out: { [string]: string } = {}
	if isTable(value) then
		for nurseId, mark in value do
			if type(nurseId) == "string" and #nurseId <= 40 and (mark == "Seen" or mark == "Hired") then
				out[nurseId] = mark
			end
		end
	end
	for nurseId in nurses do
		out[nurseId] = "Hired"
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
	if isTable(saved.WeekCures) then
		data.WeekCures.Week = countOr(saved.WeekCures.Week, 0)
		data.WeekCures.Count = countOr(saved.WeekCures.Count, 0)
	end

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
	-- The step-7 top-up's flag (look overhaul; no version bump). A boolean is kept. Missing or junk: the top-up
	-- runs when step 7 is entered, so a save at or past it has had its chance. That makes the field harmless to
	-- lose (an older v4 server writing the save back): the next load derives it again.
	if type(saved.TutorialGift) == "boolean" then
		data.TutorialGift = saved.TutorialGift
	else
		data.TutorialGift = data.Tutorial >= Schema.TUTORIAL_SHOP
	end

	-- Time-played rewards, boosts and badges. A save from before them starts at 0 (Stats unseeded: {}).
	data.Playtime = reconcilePlaytime(saved.Playtime, today)
	data.Boosts = numberMap(saved.Boosts, 0, Schema.MAX_BOOST_SECONDS, true)
	data.Stats = numberMap(saved.Stats, 0, math.huge, false)
	data.Badges = numberMap(saved.Badges, 0, Schema.MAX_TIER, true)

	-- The depth update (v3). A v2 save has no Level: it starts at the level its rooms imply.
	local level = saved.Level
	data.Level = if isInteger(level) and level >= 1
		then math.min(level, Schema.MAX_LEVEL)
		else Schema.levelFromRooms(data.Rooms)
	data.JournalSets = trueSet(saved.JournalSets)
	data.Simple = saved.Simple == true

	-- Progression v2 (v4). Rebirth first: the level cap and the roster follow its Count. A save written before v4
	-- (v3, or a v2 with no nurses) fills the working places in its old Equipped order.
	data.Rebirth = reconcileRebirth(saved.Rebirth)
	data.Nurses = reconcileNurses(saved.Nurses, Schema.levelCap(data.Rebirth.Count))
	local before4 = not (type(saved.Version) == "number" and saved.Version >= 4)
	applyRoster(data.Nurses, Schema.rosterCap(data.Rebirth.Count), if before4 then saved.Equipped else nil)
	data.NurseIndex = reconcileIndex(saved.NurseIndex, data.Nurses)

	local realDay = count(today, 0)
	if realDay then
		clampDays(data, realDay)
	end
	return data
end

return Schema
