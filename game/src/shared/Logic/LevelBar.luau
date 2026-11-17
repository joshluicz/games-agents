--!strict
-- The HUD's level bar (Joshua, 2026-11-17: "how to level up ... is there a level up bar. where to see my level?").
-- Pure: no Roblox services and no requires, so Lune tests it (tests/LevelBar.spec). `levels` is Shared/Data/Levels
-- (an array, Levels[level]); nothing here is a number of its own: every gate and cost is read from that table.
--
-- Levelling up is a button on the Shop's hospital card (Server/Levels.levelUp): the next level needs its Clinic Stars
-- (a GATE: kept, never spent) AND its Cash (spent). The old bar under the Stars count followed star milestones only
-- and said "Everything unlocked!" once they were passed, while the level still had to be bought. This is the ONE
-- bar: it counts both things the next level needs.
--
-- THE RULE: fraction = the AVERAGE of the two shares, each capped at 1 (Stars had / Stars needed, Cash had / Cash
-- needed; a need of 0 is a full share). Why the average and not the smaller share: the bar moves whenever either
-- one grows (a treatment's Stars and its Cash both show), and it is FULL exactly when both are met, which is the
-- same moment the Shop's button works (Logic/Levels.canLevelUp). With the smaller share, a player with every Star
-- and no Cash would look at an empty bar.
--
--   LevelBar.view(state, levels): View            what the HUD shows. `state` is a Snapshot or a save (Level, Stars,
--                                                 Cash); junk reads as Lv 1 with nothing
--     View = { Level, Name, Max, Ready, Fraction, Stars: Need?, Cash: Need?, NextLevel: number?, NextName: string? }
--       Level, Name   the level you are at ("Clinic")
--       Max           at the top level: no next level (Fraction 1, Stars and Cash nil)
--       Ready         both needs met: the bar reads "Level up!" and a tap opens the Shop's hospital card
--       Fraction      0..1 (the rule above)
--       Stars, Cash   { Have, Need }: Have is capped at Need, so the count never reads "20/15"
--   LevelBar.fraction(stars, needStars, cash, needCash): number   the rule on plain numbers
--   LevelBar.label(view): string?                 "Level up!" when Ready · "Max level" at the top · nil otherwise
--   LevelBar.parts(view, format?): { Part }       { { Unit = "Stars", Text = "12/15" }, { Unit = "Cash", Text =
--                                                 "300/400" } } (a Unit is a key of UI/Icons.Unit); {} when Max.
--                                                 `format` writes a number ("1,500"); tostring when nil
--   LevelBar.text(view, format?): string          one line: "⭐ 12/15 · 💰 300/400" · "Level up!" · "Max level"
--   LevelBar.nextText(view, format?): string      for a tap on the bar: "Lv 2 Medical Centre: ⭐ 12/15 · 💰 300/400",
--                                                 "Level up in the Shop!" when Ready, "Max level" at the top
--   LevelBar.allRooms(owned, rooms): boolean      every room with a price is owned (rooms = Shared/Data/Rooms)
--   LevelBar.everything(view, owned, rooms): boolean   the top level AND every room owned: the only time a screen may
--                                                 say everything is unlocked. The HUD says the calm "Max level"

export type Need = { Have: number, Need: number }
export type View = {
	Level: number,
	Name: string,
	Max: boolean,
	Ready: boolean,
	Fraction: number,
	Stars: Need?,
	Cash: Need?,
	NextLevel: number?,
	NextName: string?,
}
export type Part = { Unit: string, Text: string }

local LevelBar = {}

LevelBar.TEXT = table.freeze({
	Ready = "Level up!",
	Max = "Max level",
	ReadyTip = "Level up in the Shop!",
})

-- The same icons as Logic/Levels and Logic/Progress (UI/Icons.Unit holds them for the client).
local STAR_ICON = "⭐"
local CASH_ICON = "💰"

local function num(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

local function share(have: number, need: number): number
	if need <= 0 then
		return 1
	end
	return math.clamp(have / need, 0, 1)
end

function LevelBar.fraction(stars: any, needStars: any, cash: any, needCash: any): number
	local starShare = share(math.max(0, num(stars, 0)), num(needStars, 0))
	local cashShare = share(math.max(0, num(cash, 0)), num(needCash, 0))
	return (starShare + cashShare) / 2
end

function LevelBar.view(state: any, levels: { any }): View
	local data = if type(state) == "table" then state else {}
	local top = math.max(1, #levels)
	local level = math.clamp(math.floor(num(data.Level, 1)), 1, top)
	local row = levels[level]
	local name = if type(row) == "table" and type(row.Name) == "string" then row.Name else ""
	local nextRow = levels[level + 1]
	if type(nextRow) ~= "table" then
		return { Level = level, Name = name, Max = true, Ready = false, Fraction = 1 }
	end
	local stars = math.max(0, math.floor(num(data.Stars, 0)))
	local cash = math.max(0, math.floor(num(data.Cash, 0)))
	local needStars = math.max(0, num(nextRow.Stars, 0))
	local needCash = math.max(0, num(nextRow.Cash, 0))
	return {
		Level = level,
		Name = name,
		Max = false,
		Ready = stars >= needStars and cash >= needCash,
		Fraction = LevelBar.fraction(stars, needStars, cash, needCash),
		Stars = { Have = math.min(stars, needStars), Need = needStars },
		Cash = { Have = math.min(cash, needCash), Need = needCash },
		NextLevel = level + 1,
		NextName = if type(nextRow.Name) == "string" then nextRow.Name else "",
	}
end

function LevelBar.label(view: View): string?
	if view.Max then
		return LevelBar.TEXT.Max
	elseif view.Ready then
		return LevelBar.TEXT.Ready
	end
	return nil
end

function LevelBar.parts(view: View, format: ((number) -> string)?): { Part }
	local stars, cash = view.Stars, view.Cash
	if view.Max or not stars or not cash then
		return {}
	end
	local function write(n: number): string
		return if format then format(n) else tostring(n)
	end
	return {
		{ Unit = "Stars", Text = write(stars.Have) .. "/" .. write(stars.Need) },
		{ Unit = "Cash", Text = write(cash.Have) .. "/" .. write(cash.Need) },
	}
end

local function counts(view: View, format: ((number) -> string)?): string
	local parts = LevelBar.parts(view, format)
	if #parts < 2 then
		return ""
	end
	return STAR_ICON .. " " .. parts[1].Text .. " · " .. CASH_ICON .. " " .. parts[2].Text
end

function LevelBar.text(view: View, format: ((number) -> string)?): string
	return LevelBar.label(view) or counts(view, format)
end

function LevelBar.nextText(view: View, format: ((number) -> string)?): string
	if view.Max then
		return LevelBar.TEXT.Max
	elseif view.Ready then
		return LevelBar.TEXT.ReadyTip
	end
	local name = if view.NextName and view.NextName ~= "" then " " .. view.NextName else ""
	return "Lv " .. tostring(view.NextLevel) .. name .. ": " .. counts(view, format)
end

function LevelBar.allRooms(owned: any, rooms: any): boolean
	if type(rooms) ~= "table" or type(rooms.Order) ~= "table" then
		return false
	end
	local have = if type(owned) == "table" then owned else {}
	for _, roomId in rooms.Order do
		local room = rooms[roomId]
		if type(room) == "table" and num(room.Price, 0) > 0 and have[roomId] ~= true then
			return false
		end
	end
	return true
end

function LevelBar.everything(view: View, owned: any, rooms: any): boolean
	return view.Max and LevelBar.allRooms(owned, rooms)
end

return LevelBar
