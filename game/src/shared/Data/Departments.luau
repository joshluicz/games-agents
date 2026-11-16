--!strict
-- Hospital departments (Progression v2 build plan §B5; design §6/§7). Lune-safe (no Roblox types).
-- Iterate `Departments.Order`; `for id, dept in Departments` yields only departments.
--
--   Name, Icon   the chip on a patient's badge, the lift buttons and the team chips
--   Opens        the hospital level it opens at (Data/Levels Departments lists the same, cumulatively)
--   Floor        the storey it's on: 0 = the ground (AE: the ambulance bay), 4 = the roof (Data/Levels Floors)
--   Team2/Team3  the team bonus with 2 / 3+ WORKING nurses whose Specialty is this department ("Any" counts for every
--                one). Teams don't stack: 2 gives the small one, 3 or more the big one. nil = no bonus.
--                Kind "Cash"    cure cash x (1 + Value)
--                     "Urgent"  🚑/🚁 patients wait x (1 + Value)
--                     "Recover" rest seconds x (1 - Value)
--                     "Make"    hold seconds at Stations x (1 - Value)
-- Two maps ride along (in the metatable, so they never show up as departments):
--   Departments.Stations   StationId -> DeptId: where a Maker at that station works (Logic/Jobs.department)
--   Departments.Wings      WingId -> DeptId: a cured patient's department, for nurse XP (urgent patients -> AE)

export type DeptId = string
export type TeamEffect = { Kind: string, Value: number, Stations: { string }? }
export type Department = {
	Name: string,
	Icon: string,
	Opens: number,
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
	AE = {
		Name = "A&E",
		Icon = "🚑",
		Opens = 2,
		Floor = 0,
		Team2 = { Kind = "Urgent", Value = 0.25 },
		Team3 = { Kind = "Urgent", Value = 0.5 },
	},
	Wards = {
		Name = "Wards",
		Icon = "🛏️",
		Opens = 2,
		Floor = 1,
		Team2 = { Kind = "Recover", Value = 0.25 },
		Team3 = { Kind = "Recover", Value = 0.5 },
	},
	Hydro = {
		Name = "Hydro",
		Icon = "🛁",
		Opens = 3,
		Floor = 2,
		Team2 = { Kind = "Make", Value = 0.2, Stations = { "Bath" } },
		Team3 = { Kind = "Make", Value = 0.4, Stations = { "Bath" } },
	},
	Pharmacy = {
		Name = "Pharmacy",
		Icon = "💊",
		Opens = 4,
		Floor = 3,
		Team2 = { Kind = "Make", Value = 0.2, Stations = { "Cocoa", "Pharmacy" } },
		Team3 = { Kind = "Make", Value = 0.4, Stations = { "Cocoa", "Pharmacy" } },
	},
	Roof = { Name = "Roof", Icon = "🚁", Opens = 5, Floor = 4 },
}

local ORDER = { "Reception", "AE", "Wards", "Hydro", "Pharmacy", "Roof" }

local STATIONS =
	{ Remedy = "Reception", Plaster = "Reception", Bath = "Hydro", Cocoa = "Pharmacy", Pharmacy = "Pharmacy" }

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
