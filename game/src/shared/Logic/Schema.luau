--!strict
-- Save schema v2 (build plan §B3). Pure: no Roblox services, no requires, so Lune can test it.
--   Schema.default(): Data            a fresh save
--   Schema.reconcile(saved: any): Data  repairs anything loaded from a DataStore into a valid v2 save:
--     · v1 shop-sim saves { Cash, Served, Upgrades } migrate: Served -> Cured; Speed, Tray and Tips are kept
--     · unknown fields are dropped, and bad types or non-finite numbers are replaced by defaults
--     · the result never shares a table with `saved`

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
	}
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

function Schema.reconcile(saved: any): Data
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
	return data
end

return Schema
