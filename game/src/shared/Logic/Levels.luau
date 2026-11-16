--!strict
-- Hospital levels: costs, unlocks and what each level gives (depth-update design §3, build plan §B7). Pure: no
-- Roblox services, no requires. `levels` is Shared/Data/Levels (an array, Levels[level]).
--
--   Levels.max(levels): number                     the top level (5)
--   Levels.clamp(levels, level): number            a junk or out-of-range level -> 1..max
--   Levels.row(levels, level): Level               that level's row (clamped)
--   Levels.nextRow(levels, level): Level?          the next level's row, nil at the top
--   Levels.canLevelUp(data, levels): (ok, message) checks, in order: the top · Clinic Stars (a gate, not spent) ·
--                                                  cash. Messages: "Max level!", "Need ⭐15", "Need 💰400"; "" when ok
--   Levels.slots / beds / queue / recipeCap (levels, level): number    from the row
--   Levels.impliedByRoom(levels, room): number     the highest level whose ⭐ gate is at or below the room's own ⭐
--                                                  gate (and at least the room's Level): what an old save that owns
--                                                  the room starts at (Schema.ROOM_LEVELS mirrors it)
--   Levels.roomAllowed(room, level): boolean       room.Level (nil = 1) is at or below level

export type Level = {
	Name: string,
	Icon: string,
	Stars: number,
	Cash: number,
	Slots: number,
	Beds: number,
	Queue: number,
	RecipeCap: number,
	Floors: number,
	Unlocks: { string },
}

local Levels = {}

local STAR_ICON = "⭐" -- the same icons as Logic/Progress
local CASH_ICON = "💰"

local function num(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

function Levels.max(levels: { Level }): number
	return math.max(1, #levels)
end

function Levels.clamp(levels: { Level }, level: any): number
	return math.clamp(math.floor(num(level, 1)), 1, Levels.max(levels))
end

function Levels.row(levels: { Level }, level: any): Level
	return levels[Levels.clamp(levels, level)]
end

function Levels.nextRow(levels: { Level }, level: any): Level?
	local current = Levels.clamp(levels, level)
	return levels[current + 1]
end

function Levels.canLevelUp(data: any, levels: { Level }): (boolean, string)
	if type(data) ~= "table" then
		return false, "Coming soon!"
	end
	local nextLevel = Levels.nextRow(levels, data.Level)
	if not nextLevel then
		return false, "Max level!"
	end
	if num(data.Stars, 0) < nextLevel.Stars then
		return false, "Need " .. STAR_ICON .. nextLevel.Stars
	end
	if num(data.Cash, 0) < nextLevel.Cash then
		return false, "Need " .. CASH_ICON .. nextLevel.Cash
	end
	return true, ""
end

function Levels.slots(levels: { Level }, level: any): number
	return Levels.row(levels, level).Slots
end

function Levels.beds(levels: { Level }, level: any): number
	return Levels.row(levels, level).Beds
end

function Levels.queue(levels: { Level }, level: any): number
	return Levels.row(levels, level).Queue
end

function Levels.recipeCap(levels: { Level }, level: any): number
	return Levels.row(levels, level).RecipeCap
end

function Levels.impliedByRoom(levels: { Level }, room: any): number
	if type(room) ~= "table" then
		return 1
	end
	local stars = num(room.StarsNeeded, 0)
	local implied = 1
	for index, row in levels do
		if row.Stars <= stars then
			implied = math.max(implied, index)
		end
	end
	return math.max(implied, Levels.clamp(levels, room.Level or 1))
end

function Levels.roomAllowed(room: any, level: any): boolean
	if type(room) ~= "table" then
		return false
	end
	return num(room.Level, 1) <= math.max(1, num(level, 1))
end

return Levels
