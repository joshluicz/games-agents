--!strict
-- Save schema v3 (build plan §B3; depth-update build plan §B1). Pure: no Roblox services, no requires, so Lune
-- can test it.
--   Schema.default(): Data            a fresh save
--   Schema.reconcile(saved: any, today: number?): Data  repairs anything loaded from a DataStore into a valid
--   v3 save:
--     · v1 shop-sim saves { Cash, Served, Upgrades } migrate: Served -> Cured; Speed, Tray and Tips are kept
--     · unknown fields are dropped, and bad types or non-finite numbers are replaced by defaults
--     · with `today` (the real UTC day), every saved day field later than today is pulled back to today, so a
--       Studio test that moved Workspace.UtcDay forward can't lock a real save out of its mailbox, goals or story
--     · the result never shares a table with `saved`
--   Schema.isNewer(saved: any): boolean  the save was written by a newer schema (never write it back down)
--   Schema.levelFromRooms(rooms): number  the hospital level a save's rooms imply (for saves from before levels)
--   Schema.TUTORIAL_FIRST / TUTORIAL_DONE   the Tutorial values for the welcome and for done
--
-- v3 (the depth update) adds Level, Nurses, Equipped, NurseIndex, JournalSets and Simple. The version went up so an
-- older server, still running while the update rolls out, loads a v3 save read-only (isNewer) instead of saving it
-- back without its nurses. Every v2 save migrates: Level from its rooms (levelFromRooms), no nurses, an empty
-- journal, Simple off.
--   Level        1..MAX_LEVEL. Missing or junk: the level the rooms imply. ROOM_LEVELS gives, for each room, the
--                highest level whose ⭐ gate is at or below the room's own ⭐ gate (Logic/Levels.impliedByRoom
--                computes the same from Data; Levels.spec checks they match). No rooms: 1.
--   Nurses       { [NurseId]: { Level, Copies } }: Copies an integer >= 1 (junk -> 1), Level an integer in
--                1..min(MAX_NURSE_LEVEL, Copies) (junk -> that top). Unknown ids are kept, like Book pages.
--   Equipped     { NurseId } in order: strings, no repeats, each one owned (in Nurses), at most Level of them.
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

export type BookPage = { Cured: number, Variants: { [string]: boolean } }
export type StoryEntry = { Beat: number, LastBeatDay: number }
export type Goal = { Id: string, Progress: number, Day: number }
export type NurseEntry = { Level: number, Copies: number }
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
	Level: number,
	Nurses: { [string]: NurseEntry },
	Equipped: { string },
	NurseIndex: { [string]: string },
	JournalSets: { [string]: boolean },
	Simple: boolean,
}

local Schema = {}

Schema.VERSION = 3
Schema.UPGRADES = table.freeze({ "Speed", "Tray", "Chairs", "Tips" })
Schema.MAX_GOALS = 10 -- a safety cap on banked goals in a save; the real cap is Config.MaxBankedGoals
-- Logic/Tutorial's WELCOME and DONE, repeated because Schema has no requires (Tutorial.spec checks they match).
Schema.TUTORIAL_FIRST = 1
Schema.TUTORIAL_DONE = 9
-- Data/Levels and Config.Nurses values, repeated because Schema has no requires (Levels.spec checks they match).
Schema.MAX_LEVEL = 5
Schema.MAX_NURSE_LEVEL = 5
Schema.MAX_NURSES = 64 -- a safety cap on nurse entries in a save (the roster has 16)
Schema.ROOM_LEVELS = table.freeze({ BathRoom = 1, Ward = 2, WinterWing = 2, Garden = 3 })

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
		Level = 1,
		Nurses = {},
		Equipped = {},
		NurseIndex = {},
		JournalSets = {},
		Simple = false,
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

local function reconcileNurses(value: any): { [string]: NurseEntry }
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
			local top = math.min(Schema.MAX_NURSE_LEVEL, copies)
			local level = if isInteger(entry.Level) then math.clamp(entry.Level, 1, top) else top
			out[nurseId] = { Level = level, Copies = copies }
			kept += 1
		end
	end
	return out
end

local function reconcileEquipped(value: any, nurses: { [string]: NurseEntry }, slots: number): { string }
	local out: { string } = {}
	if not isTable(value) then
		return out
	end
	local seen: { [string]: boolean } = {}
	for _, nurseId in ipairs(value) do
		if #out >= slots then
			break
		end
		if type(nurseId) == "string" and nurses[nurseId] and not seen[nurseId] then
			seen[nurseId] = true
			table.insert(out, nurseId)
		end
	end
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

	-- The depth update (v3). A v2 save has no Level: it starts at the level its rooms imply.
	local level = saved.Level
	data.Level = if isInteger(level) and level >= 1
		then math.min(level, Schema.MAX_LEVEL)
		else Schema.levelFromRooms(data.Rooms)
	data.Nurses = reconcileNurses(saved.Nurses)
	data.Equipped = reconcileEquipped(saved.Equipped, data.Nurses, data.Level)
	data.NurseIndex = reconcileIndex(saved.NurseIndex, data.Nurses)
	data.JournalSets = trueSet(saved.JournalSets)
	data.Simple = saved.Simple == true

	local realDay = count(today, 0)
	if realDay then
		clampDays(data, realDay)
	end
	return data
end

return Schema
