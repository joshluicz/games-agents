--!strict
-- Hospital levels: the clinic's open parts grow (memory-20261116-008; Real Clinic build plan, contract C3; design
-- §10 and §15 #3). Lune-safe. An ARRAY: Levels[level], 1..5. Logic/Levels reads it; Server/Levels sells the next one.
-- The whole building stands from Lv 1 (Logic/Building): a level opens bays, rooms and floors that are already there.
--
--   Name, Icon   what the Shop's Hospital tab and the level-up celebration show
--   Stars        the Clinic Stars needed: a GATE, not spent (like rooms)
--   Cash         spent
--   Bays         open exam bays in the row of six (Logic/Building.BAYS 1..6: 2, 3, 4, 5, 6). The X-ray bay (Lv 3)
--                and the Cozy Ward's two (a bought room) come on top
--   Beds         ward beds upstairs, for patients who stay (Logic/Building.WARD_BEDS): 3 in the Injury Ward (F1,
--                Lv 2), +2 in the Rest Ward (F2, Lv 3), +2 in the staff room (F3, Lv 4)
--   Queue        patients waiting for a bay: 3 at every level (Config.MaxQueue, Joshua 2026-11-16). The waiting room
--                is the line. A level's bigger throughput comes from Bays and SpawnSeconds instead
--   RecipeCap    a case's plan is cut to this many steps (Logic/Visit.plan): a Lv 1 player always sees one
--   SpawnSeconds a new patient comes about this often (Server/Patients, ±15%): a bigger hospital is a busier one.
--                Lv 1 = Config.SpawnEverySeconds
--   Floors       OPEN floors above the ground (the 4th at Lv 5 is the roof deck with the helipad)
--   Departments  the departments open at this level, cumulatively (Data/Departments; each one's Opens agrees). Hydro
--                isn't listed: it comes with the Bath Room, not with a level
--   Unlocks      short chips for the Shop: an emoji, then two or three words
-- The Stars gates, cash costs, the line and the spawn seconds are unchanged from Progression v2.

export type Level = {
	Name: string,
	Icon: string,
	Stars: number,
	Cash: number,
	Bays: number,
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
		Name = "Clinic",
		Icon = "🏠",
		Stars = 0,
		Cash = 0,
		Bays = 2,
		Beds = 0,
		Queue = 3,
		RecipeCap = 1,
		SpawnSeconds = 13,
		Floors = 0,
		Departments = { "Reception", "Pharmacy" },
		Unlocks = {},
	},
	{
		Name = "Medical Centre",
		Icon = "🏬",
		Stars = 15,
		Cash = 400,
		Bays = 3,
		Beds = 3,
		Queue = 3,
		RecipeCap = 2,
		SpawnSeconds = 11,
		Floors = 1,
		Departments = { "Reception", "Pharmacy", "AE", "Wards" },
		Unlocks = { "🚑 A&E ambulances", "🛏️ Injury Ward upstairs", "🧻 Bandages", "📋 2-step plans" },
	},
	{
		Name = "Hospital",
		Icon = "🏥",
		Stars = 45,
		Cash = 1500,
		Bays = 4,
		Beds = 5,
		Queue = 3,
		RecipeCap = 3,
		SpawnSeconds = 10,
		Floors = 2,
		Departments = { "Reception", "Pharmacy", "AE", "Wards", "Imaging", "Rest" },
		Unlocks = { "🩻 X-ray room", "😴 Rest Ward", "🔀 Pick the ward", "📋 3-step plans", "🌻 Garden" },
	},
	{
		Name = "General Hospital",
		Icon = "🏨",
		Stars = 100,
		Cash = 5000,
		Bays = 5,
		Beds = 7,
		Queue = 3,
		RecipeCap = 3,
		SpawnSeconds = 9,
		Floors = 3,
		Departments = { "Reception", "Pharmacy", "AE", "Wards", "Imaging", "Rest" },
		Unlocks = { "🛋️ Staff room", "🛏️ 7 ward beds", "🚪 5 exam bays" },
	},
	{
		Name = "City Hospital",
		Icon = "🏙️",
		Stars = 200,
		Cash = 15000,
		Bays = 6,
		Beds = 7,
		Queue = 3,
		RecipeCap = 3,
		SpawnSeconds = 8,
		Floors = 4,
		Departments = { "Reception", "Pharmacy", "AE", "Wards", "Imaging", "Rest", "Roof" },
		Unlocks = { "🚁 Helipad", "🚪 6 exam bays", "✨ Neon sign", "🏢 New branches" },
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
