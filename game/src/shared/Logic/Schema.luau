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
--
-- Fields added inside v2 (missing in older v2 saves, so they reconcile to their defaults):
--   VisitorDay      the UTC day this clinic last cured Today's Visitor (0 = never): once per player per day,
--                   across servers
--   HeartsReceived  hearts other players have left on this clinic's sign, all time (cosmetic)

export type BookPage = { Cured: number, Variants: { [string]: boolean } }
export type StoryEntry = { Beat: number, LastBeatDay: number }
export type Goal = { Id: string, Progress: number, Day: number }
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
}

local Schema = {}

Schema.VERSION = 2
Schema.UPGRADES = table.freeze({ "Speed", "Tray", "Chairs", "Tips" })
Schema.MAX_GOALS = 10 -- a safety cap on banked goals in a save; the real cap is Config.MaxBankedGoals

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

	local realDay = count(today, 0)
	if realDay then
		clampDays(data, realDay)
	end
	return data
end

return Schema
