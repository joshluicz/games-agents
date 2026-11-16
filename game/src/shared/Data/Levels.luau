--!strict
-- Hospital levels: the building grows (memory-20261116-008; depth-update design §3, build plan §B5). Lune-safe.
-- An ARRAY: Levels[level], 1..5. Logic/Levels reads it; Server/Levels sells the next one.
--
--   Name, Icon   what the Shop's Hospital tab and the level-up celebration show
--   Stars        the Clinic Stars needed: a GATE, not spent (like rooms; open point §E1 in the build plan)
--   Cash         spent
--   Slots        nurses on duty (Data.Equipped); equals the level
--   Beds         beds in the main building, the Stand's own bed included (PlotBuilder adds Beds - 1 in Building)
--   Queue        patients in line (was Config.MaxQueue for everyone)
--   RecipeCap    recipes are cut to this many items (Logic/Recipe.effective): "Bath wing recipes" arrive at Lv 2
--   SpawnSeconds a new patient comes about this often (Server/Patients, ±15%): a bigger hospital is a busier one,
--                so a level-up raises what a clinic can earn (with nurses to keep up). Lv 1 = Config.SpawnEverySeconds
--   Floors       storeys PlotBuilder stacks on the shell (0 = the open-air Stand)
--   Unlocks      short chips for the Shop: an emoji, then two or three words
-- The Lv 3 "Golden capsule" of the first design became the belt (memory-20261116-012), so Lv 3 opens the Garden.

export type Level = {
	Name: string,
	Icon: string,
	Stars: number,
	Cash: number,
	Slots: number,
	Beds: number,
	Queue: number,
	RecipeCap: number,
	SpawnSeconds: number,
	Floors: number,
	Unlocks: { string },
}

local LEVELS: { Level } = {
	{
		Name = "First-Aid Stand",
		Icon = "⛑️",
		Stars = 0,
		Cash = 0,
		Slots = 1,
		Beds = 1,
		Queue = 4,
		RecipeCap = 1,
		SpawnSeconds = 13,
		Floors = 0,
		Unlocks = {},
	},
	{
		Name = "Clinic",
		Icon = "🏠",
		Stars = 15,
		Cash = 400,
		Slots = 2,
		Beds = 2,
		Queue = 4,
		RecipeCap = 2,
		SpawnSeconds = 11,
		Floors = 1,
		Unlocks = { "🧱 Walls and roof", "👩‍⚕️ 2 nurses", "🛏️ 2 beds", "🧪 2-item recipes" },
	},
	{
		Name = "Hospital",
		Icon = "🏥",
		Stars = 45,
		Cash = 1500,
		Slots = 3,
		Beds = 2,
		Queue = 5,
		RecipeCap = 3,
		SpawnSeconds = 10,
		Floors = 2,
		Unlocks = { "🏢 2 floors", "✚ Big sign", "👩‍⚕️ 3 nurses", "🌻 Garden", "🧍 Line of 5" },
	},
	{
		Name = "Big Hospital",
		Icon = "🏨",
		Stars = 100,
		Cash = 5000,
		Slots = 4,
		Beds = 3,
		Queue = 5,
		RecipeCap = 3,
		SpawnSeconds = 9,
		Floors = 3,
		Unlocks = { "🏢 3 floors", "🚑 Ambulance bay", "👩‍⚕️ 4 nurses", "🛏️ 3 beds" },
	},
	{
		Name = "Mega Hospital",
		Icon = "🏙️",
		Stars = 200,
		Cash = 15000,
		Slots = 5,
		Beds = 3,
		Queue = 6,
		RecipeCap = 3,
		SpawnSeconds = 8,
		Floors = 4,
		Unlocks = { "🗼 Tower", "✨ Neon sign", "🚁 Helipad", "👩‍⚕️ 5 nurses", "🧍 Line of 6" },
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
