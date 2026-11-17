--!strict
-- Hospital departments (Progression v2 build plan §B5; Real Clinic build plan, contract C3; design §15 #3).
-- Lune-safe (no Roblox types). Iterate `Departments.Order`; `for id, dept in Departments` yields only departments.
--
--   Name, Icon   the chip on a patient's badge, the lift buttons and the team chips
--   Opens        the hospital level it opens at (Data/Levels Departments lists the same, cumulatively)
--   Room         a RoomId (Data/Rooms): the department comes with that bought room instead of with a level, so
--                Data/Levels doesn't list it
--   Floor        the storey it's on: 0 = the ground, 4 = the roof deck (Data/Levels Floors). The lift's button for a
--                floor shows the first department in Order on it: 🛏️ F1, 😴 F2, 🚁 the roof
--   Team2/Team3  the team bonus with 2 / 3+ WORKING nurses whose Specialty is this department ("Any" counts for every
--                one). Teams don't stack: 2 gives the small one, 3 or more the big one. nil = no bonus.
--                Kind "Cash"    cash for a treated patient x (1 + Value)
--                     "Urgent"  🚑/🚁 patients wait x (1 + Value)
--                     "Recover" rest seconds x (1 - Value)
--                     "Make"    hold seconds at Stations x (1 - Value)
-- What each one covers now:
--   Reception  the lobby, the desk and the waiting room
--   Pharmacy   the supply shelf and the dispensary (Makers stocking supplies; the future Pharmacist), and the
--              Winter Wing's Cocoa Corner
--   Hydro      the Bath Room (the Bath station and Sore-muscles patients)
--   AE         the ambulance bay and its side door
--   Wards      the Injury Ward on F1 (sprains, broken bones)
--   Imaging    the X-ray room (the X-ray bay and the Cast Table)
--   Rest       the Rest Ward on F2, and the staff room's Rest beds on F3 (fever, chills)
--   Roof       the helipad
-- Two maps ride along (in the metatable, so they never show up as departments):
--   Departments.Stations   StationId -> DeptId: where a Maker at that station works (Logic/Jobs.department)
--   Departments.Wings      WingId -> DeptId: a treated patient's department, for nurse XP (urgent patients -> AE)

export type DeptId = string
export type TeamEffect = { Kind: string, Value: number, Stations: { string }? }
export type Department = {
	Name: string,
	Icon: string,
	Opens: number,
	Room: string?,
	Floor: number,
	Team2: TeamEffect?,
	Team3: TeamEffect?,
}

local ENTRIES: { [DeptId]: Department } = {
	Reception = {
		Name = "Reception",
		Icon = "🛎️",
		Opens = 1,
		Floor = 0,
		Team2 = { Kind = "Cash", Value = 0.1 },
		Team3 = { Kind = "Cash", Value = 0.2 },
	},
	Pharmacy = {
		Name = "Pharmacy",
		Icon = "💊",
		Opens = 1,
		Floor = 0,
		Team2 = { Kind = "Make", Value = 0.2, Stations = { "Plaster", "Ice", "Bandage", "Cocoa" } },
		Team3 = { Kind = "Make", Value = 0.4, Stations = { "Plaster", "Ice", "Bandage", "Cocoa" } },
	},
	Hydro = {
		Name = "Bath Room",
		Icon = "🛁",
		Opens = 1,
		Room = "BathRoom",
		Floor = 0,
		Team2 = { Kind = "Make", Value = 0.2, Stations = { "Bath" } },
		Team3 = { Kind = "Make", Value = 0.4, Stations = { "Bath" } },
	},
	AE = {
		Name = "A&E",
		Icon = "🚑",
		Opens = 2,
		Floor = 0,
		Team2 = { Kind = "Urgent", Value = 0.25 },
		Team3 = { Kind = "Urgent", Value = 0.5 },
	},
	Wards = {
		Name = "Injury Ward",
		Icon = "🛏️",
		Opens = 2,
		Floor = 1,
		Team2 = { Kind = "Recover", Value = 0.25 },
		Team3 = { Kind = "Recover", Value = 0.5 },
	},
	Imaging = { Name = "X-ray", Icon = "🩻", Opens = 3, Floor = 0 },
	Rest = { Name = "Rest Ward", Icon = "😴", Opens = 3, Floor = 2 },
	Roof = { Name = "Roof", Icon = "🚁", Opens = 5, Floor = 4 },
}

local ORDER = { "Reception", "Pharmacy", "Hydro", "AE", "Wards", "Imaging", "Rest", "Roof" }

local STATIONS = {
	Remedy = "Pharmacy",
	Plaster = "Pharmacy",
	Ice = "Pharmacy",
	Bandage = "Pharmacy",
	Cocoa = "Pharmacy",
	Cast = "Imaging",
	Bath = "Hydro",
}

local WINGS = {
	Starter = "Reception",
	Sunny = "Reception",
	Bath = "Hydro",
	Winter = "Pharmacy",
	Night = "Wards",
	Sky = "AE",
}

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = {
	Order: { DeptId },
	Stations: { [string]: DeptId },
	Wings: { [string]: DeptId },
	[DeptId]: Department,
}
return freeze(setmetatable(ENTRIES, {
	__index = { Order = freeze(ORDER), Stations = freeze(STATIONS), Wings = freeze(WINGS) },
})) :: Module
