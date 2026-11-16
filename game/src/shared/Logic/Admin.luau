--!strict
-- The admin panel's rules (game/README.md "Admin panel"). Pure: no Roblox services, no requires, so Lune tests it
-- (tests/Admin.spec.luau). Server/Admin applies them on every call of the Admin remote; the client panel only shows
-- buttons and is never trusted.
--
--   Admin.isAdmin(userId, who): boolean   who = { Studio, CreatorIsUser, CreatorId, UserIds, Resolved }:
--                                         a UserId in UserIds (Config.AdminUserIds, checked first), the game's owner
--                                         (CreatorIsUser and userId == CreatorId), a UserId in Resolved (the
--                                         Config.AdminNames the server looked up), or anyone while Studio
--   Admin.valid(action, arg, patients, boosts?): boolean   a known action with exactly the argument it takes: nil
--                                         for most, one of CASH or STARS for AddCash and AddStars, a Data/Patients id
--                                         for SpawnPatient (`patients` is that map; rawget, so its `Order` is no id),
--                                         a Data/Boosts id for AddBoost (`boosts` is that map)
--   Admin.serverWide(action): boolean     the action changes the whole server (night, day, winter)
--   Admin.serverWideAllowed(studio, players): boolean   only alone in the server (players <= 1), or in Studio
--   Admin.ACTIONS                         every action: { Arg = ArgKind, ServerWide = boolean }
--   Admin.CASH · Admin.STARS              the only amounts the cash and star buttons may add

export type ArgKind = "None" | "Cash" | "Stars" | "PatientId" | "BoostId"
export type Spec = { Arg: ArgKind, ServerWide: boolean }
export type Who = {
	Studio: boolean,
	CreatorIsUser: boolean,
	CreatorId: number,
	UserIds: { number },
	Resolved: { [number]: boolean },
}

local Admin = {}

Admin.CASH = table.freeze({ 1000, 10000 })
Admin.STARS = table.freeze({ 10, 100 })
Admin.MAX_ID_LENGTH = 40 -- longer than any id in Shared/Data

local function spec(arg: ArgKind, serverWide: boolean): Spec
	return table.freeze({ Arg = arg, ServerWide = serverWide })
end

Admin.ACTIONS = table.freeze({
	-- Your own save
	AddCash = spec("Cash", false),
	AddStars = spec("Stars", false),
	UnlockRooms = spec("None", false),
	AllDecor = spec("None", false),
	FinishTutorial = spec("None", false),
	RestartTutorial = spec("None", false),
	ResetDaily = spec("None", false),
	CompleteBook = spec("None", false),
	StoriesDue = spec("None", false),
	SpawnPatient = spec("PatientId", false),
	-- Time played, boosts and badges (your own save)
	AddPlayToday = spec("None", false), -- +10 minutes of play today (the gifts)
	AddPlayTotal = spec("None", false), -- +5 hours of play all time (the Doctor ranks, ⏱️ Dedication)
	AddCureStat = spec("None", false), -- +100 to the 🏥 Healer counter
	MaxBadges = spec("None", false), -- every badge to its top tier, with its rewards
	AddBoost = spec("BoostId", false), -- a timed boost, as a play gift gives it
	-- The whole server
	SkipToNight = spec("None", true),
	SkipToDay = spec("None", true),
	ToggleWinter = spec("None", true),
}) :: { [string]: Spec }

local function specOf(action: any): Spec?
	if type(action) ~= "string" then
		return nil
	end
	return rawget(Admin.ACTIONS :: any, action)
end

local function oneOf(value: any, list: { number }): boolean
	return type(value) == "number" and table.find(list, value) ~= nil
end

function Admin.isAdmin(userId: any, who: Who): boolean
	if type(who) ~= "table" then
		return false
	end
	if who.Studio == true then
		return true
	end
	if type(userId) ~= "number" or userId ~= userId or userId % 1 ~= 0 or userId <= 0 then
		return false
	end
	if type(who.UserIds) == "table" and table.find(who.UserIds, userId) ~= nil then
		return true
	end
	if who.CreatorIsUser == true and userId == who.CreatorId then
		return true
	end
	return type(who.Resolved) == "table" and who.Resolved[userId] == true
end

local function knownId(arg: any, map: any): boolean
	return type(arg) == "string"
		and #arg > 0
		and #arg <= Admin.MAX_ID_LENGTH
		and type(map) == "table"
		and type(rawget(map, arg)) == "table"
end

function Admin.valid(action: any, arg: any, patients: any, boosts: any?): boolean
	local found = specOf(action)
	if not found then
		return false
	end
	local kind = found.Arg
	if kind == "None" then
		return arg == nil
	elseif kind == "Cash" then
		return oneOf(arg, Admin.CASH)
	elseif kind == "Stars" then
		return oneOf(arg, Admin.STARS)
	elseif kind == "PatientId" then
		return knownId(arg, patients)
	elseif kind == "BoostId" then
		return knownId(arg, boosts)
	end
	return false
end

function Admin.serverWide(action: any): boolean
	local found = specOf(action)
	return found ~= nil and found.ServerWide
end

function Admin.serverWideAllowed(studio: boolean, players: number): boolean
	return studio == true or (type(players) == "number" and players <= 1)
end

return table.freeze(Admin)
