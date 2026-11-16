--!strict
-- Room unlocks and the one clear "next goal" (build plan §B6, design §5.5). Pure: no Roblox services, no requires.
--   Progress.canBuyRoom(data, room, roomId, isWinter?): (ok, message)
--       checks, in order: owned · in season · hospital level (room.Level vs data.Level, nil = 1) · Clinic Stars ·
--       cash. The message is short (6 words or fewer) and says what's missing: "Already yours!", "❄️ Winter only!",
--       "Needs 🏥 Lv 3", "Need ⭐10", "Need 💰150". "" when ok.
--   Progress.nextGoal(data, rooms, upgrades, isWinter?): { Kind, Id }
--       Kind "Room": the unowned room with the fewest StarsNeeded (rooms.Order breaks ties), skipping free rooms,
--       rooms out of season and rooms above the hospital level (Progress.levelAllows). Then Kind "Upgrade": the
--       cheapest next upgrade level. Then Kind "None", Id "".
--   Progress.levelAllows(data, room): boolean   the save's hospital level (nil = 1) reaches room.Level (nil = 1)
--   Progress.unlockedBetween(rooms, before, after): { RoomId }
--       rooms whose StarsNeeded was crossed going from `before` to `after` stars (for the "unlocked!" toast)
--   Progress.parseSlotKey(rooms, slotKey): (RoomId?, n?)
--       a decor slot key "<RoomId>:<n>" checked against Data/Rooms (validates the PlaceDecor remote)
-- `data` is a Schema.Data (or a Snapshot: it has Cash, Stars, Rooms and Upgrades). `rooms` and `upgrades` are
-- Shared/Data/Rooms and Shared/Data/Upgrades. isWinter nil means "not winter".

export type Room = {
	Price: number,
	StarsNeeded: number,
	Season: string?,
	Level: number?, -- the hospital level it needs (depth update; nil = 1)
}
export type Goal = { Kind: string, Id: string }

local Progress = {}

Progress.CASH_ICON = "💰" -- the same coin bag the HUD wallet, CureFX pops and room previews show
Progress.STAR_ICON = "⭐"
Progress.LEVEL_ICON = "🏥"
Progress.MAX_SLOT_KEY_LENGTH = 48

local function count(value: any): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return value
end

local function owns(data: any, roomId: string): boolean
	return type(data) == "table" and type(data.Rooms) == "table" and data.Rooms[roomId] == true
end

local function inSeason(room: Room, isWinter: boolean?): boolean
	if room.Season == nil then
		return true
	end
	return room.Season == "Winter" and isWinter == true
end

-- Entries of a Data map, in its Order when it has one (rawget, so "Order" is never an entry).
local function ordered(map: any): { string }
	local ids: { string } = {}
	if type(map) ~= "table" then
		return ids
	end
	local order = map.Order
	if type(order) == "table" then
		for _, id in order do
			if type(id) == "string" and type(rawget(map, id)) == "table" then
				table.insert(ids, id)
			end
		end
	else
		for id, entry in map do
			if type(id) == "string" and type(entry) == "table" then
				table.insert(ids, id)
			end
		end
		table.sort(ids)
	end
	return ids
end

function Progress.levelAllows(data: any, room: any): boolean
	local level = if type(data) == "table" then count(data.Level) else 0
	local needed = if type(room) == "table" then count(room.Level) else 0
	return needed <= math.max(1, level)
end

function Progress.canBuyRoom(data: any, room: Room?, roomId: string, isWinter: boolean?): (boolean, string)
	if type(data) ~= "table" or type(room) ~= "table" or type(roomId) ~= "string" then
		return false, "Coming soon!"
	end
	if owns(data, roomId) then
		return false, "Already yours!"
	end
	if not inSeason(room, isWinter) then
		return false, "❄️ Winter only!"
	end
	local levelNeeded = count(room.Level)
	if levelNeeded > math.max(1, count(data.Level)) then
		return false, "Needs " .. Progress.LEVEL_ICON .. " Lv " .. levelNeeded
	end
	local starsNeeded = count(room.StarsNeeded)
	if count(data.Stars) < starsNeeded then
		return false, "Need " .. Progress.STAR_ICON .. starsNeeded
	end
	local price = count(room.Price)
	if count(data.Cash) < price then
		return false, "Need " .. Progress.CASH_ICON .. price
	end
	return true, ""
end

function Progress.nextGoal(data: any, rooms: any, upgrades: any, isWinter: boolean?): Goal
	if type(data) ~= "table" then
		return { Kind = "None", Id = "" }
	end

	local bestRoom: string? = nil
	local bestStars = math.huge
	for _, roomId in ordered(rooms) do
		local room = rawget(rooms, roomId)
		local stars = count(room.StarsNeeded)
		if
			count(room.Price) > 0
			and not owns(data, roomId)
			and inSeason(room, isWinter)
			and Progress.levelAllows(data, room)
			and stars < bestStars
		then
			bestRoom, bestStars = roomId, stars
		end
	end
	if bestRoom then
		return { Kind = "Room", Id = bestRoom }
	end

	local levels = if type(data.Upgrades) == "table" then data.Upgrades else {}
	local bestUpgrade: string? = nil
	local bestPrice = math.huge
	for _, upgradeId in ordered(upgrades) do
		local upgrade = rawget(upgrades, upgradeId)
		local level = math.max(0, math.floor(count(levels[upgradeId])))
		local price = if type(upgrade.Prices) == "table" then upgrade.Prices[level + 1] else nil
		if type(price) == "number" and price < bestPrice then
			bestUpgrade, bestPrice = upgradeId, price
		end
	end
	if bestUpgrade then
		return { Kind = "Upgrade", Id = bestUpgrade }
	end

	return { Kind = "None", Id = "" }
end

-- A decor slot key "<RoomId>:<n>" (build plan §B1) -> (roomId, n), or nil. The room must be known and n in
-- 1..room.DecorSlots, written the one canonical way ("Stand:1", never "Stand:01"), so a save can't hold two keys
-- for one slot. It says nothing about ownership: the server checks that separately.
function Progress.parseSlotKey(rooms: any, slotKey: any): (string?, number?)
	if type(rooms) ~= "table" or type(slotKey) ~= "string" or #slotKey > Progress.MAX_SLOT_KEY_LENGTH then
		return nil, nil
	end
	local roomId, digits = string.match(slotKey, "^(%w+):(%d+)$")
	if not roomId or not digits then
		return nil, nil
	end
	local room = rawget(rooms, roomId)
	local index = tonumber(digits)
	if type(room) ~= "table" or not index or index < 1 or index > count(room.DecorSlots) then
		return nil, nil
	end
	if slotKey ~= roomId .. ":" .. index then
		return nil, nil
	end
	return roomId, index
end

function Progress.unlockedBetween(rooms: any, before: number, after: number): { string }
	local crossed: { string } = {}
	local from, to = count(before), count(after)
	if to <= from then
		return crossed
	end
	for _, roomId in ordered(rooms) do
		local room = rawget(rooms, roomId)
		local stars = count(room.StarsNeeded)
		if count(room.Price) > 0 and stars > from and stars <= to then
			table.insert(crossed, roomId)
		end
	end
	return crossed
end

return Progress
