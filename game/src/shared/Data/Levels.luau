--!strict
-- Hospital levels: the building grows (memory-20261116-008; depth-update design §3, build plan §B5). Lune-safe.
-- An ARRAY: Levels[level], 1..5. Logic/Levels reads it; Server/Levels sells the next one.
--
--   Name, Icon   what the Shop's Hospital tab and the level-up celebration show
--   Stars        the Clinic Stars needed: a GATE, not spent (like rooms; open point §E1 in the build plan)
--   Cash         spent
--   Beds         beds in the hospital, the Stand's own bed included (PlotBuilder adds Beds - 1 in Building: from Lv 2
--                they are the Wards upstairs, Progression v2 §B4)
--   Queue        patients in line: 3 at every level (Config.MaxQueue, Joshua 2026-11-16: one treated + 2 waiting,
--                on the queue lane's three spots). Server/Patients caps it at Config.MaxQueue too. A level's bigger
--                throughput comes from SpawnSeconds instead, so the Shop never promises a longer line
--   RecipeCap    recipes are cut to this many items (Logic/Recipe.effective): "Bath wing recipes" arrive at Lv 2
--   SpawnSeconds a new patient comes about this often (Server/Patients, ±15%): a bigger hospital is a busier one,
--                so a level-up raises what a clinic can earn (with nurses to keep up). Lv 1 = Config.SpawnEverySeconds
--   Floors       walkable floors above the ground (0 = the open-air Stand; at Lv 5 the 4th is the roof)
--   Departments  the departments open at this level, cumulatively (Data/Departments; each one's Opens agrees)
--   Unlocks      short chips for the Shop: an emoji, then two or three words
-- The Lv 3 "Golden capsule" of the first design became the belt (memory-20261116-012), so Lv 3 opens the Garden.
-- Progression v2 (build plan §B5): Slots is gone (every nurse you own works: Config.Roster); the ambulance bay moves
-- to Lv 2 with the Wards upstairs and the lift (§E10); costs, ⭐ gates, recipe caps, the line and spawn seconds are
-- unchanged.

export type Level = {
	Name: string,
	Icon: string,
	Stars: number,
	Cash: number,
	Beds: number,
	Queue: number,
	RecipeCap: number,
	SpawnSeconds: number,
	Floors: number,
	Departments: { string },
	Unlocks: { string },
}

local LEVELS: { Level } = {
	{
		Name = "First-Aid Stand",
		Icon = "🧰", -- a kit, not the helmet emoji (it carries a white cross on red: look plan, original only)
		Stars = 0,
		Cash = 0,
		Beds = 1,
		Queue = 3,
		RecipeCap = 1,
		SpawnSeconds = 13,
		Floors = 0,
		Departments = { "Reception" },
		Unlocks = {},
	},
	{
		Name = "Clinic",
		Icon = "🏠",
		Stars = 15,
		Cash = 400,
		Beds = 3,
		Queue = 3,
		RecipeCap = 2,
		SpawnSeconds = 11,
		Floors = 1,
		Departments = { "Reception", "AE", "Wards" },
		Unlocks = { "🚑 A&E ambulances", "🛏️ Wards upstairs", "🛗 Lift", "🧪 2-item recipes" },
	},
	{
		Name = "Hospital",
		Icon = "🏥",
		Stars = 45,
		Cash = 1500,
		Beds = 3,
		Queue = 3,
		RecipeCap = 3,
		SpawnSeconds = 10,
		Floors = 2,
		Departments = { "Reception", "AE", "Wards", "Hydro" },
		Unlocks = { "🛁 Hydro hot tub", "🔀 Pick the floor", "🐾 Big sign", "🌻 Garden" },
	},
	{
		Name = "Big Hospital",
		Icon = "🏨",
		Stars = 100,
		Cash = 5000,
		Beds = 4,
		Queue = 3,
		RecipeCap = 3,
		SpawnSeconds = 9,
		Floors = 3,
		Departments = { "Reception", "AE", "Wards", "Hydro", "Pharmacy" },
		Unlocks = { "💊 Pharmacy", "🛏️ 4 beds", "🏢 3 floors" },
	},
	{
		Name = "Mega Hospital",
		Icon = "🏙️",
		Stars = 200,
		Cash = 15000,
		Beds = 4,
		Queue = 3,
		RecipeCap = 3,
		SpawnSeconds = 8,
		Floors = 4,
		Departments = { "Reception", "AE", "Wards", "Hydro", "Pharmacy", "Roof" },
		Unlocks = { "🚁 Helipad", "🗼 Tower", "✨ Neon sign", "🏢 New branches" },
	},
}

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

return freeze(LEVELS) :: { Level }
