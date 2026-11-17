--!strict
-- Nurse jobs (Progression v2 build plan §B5; design §7, memory-20261116-017). Lune-safe (no Roblox types).
-- Every nurse you own works one job: its own Role (Data/Nurses) unless you give it another open one (SetJob). A job
-- that isn't open at your hospital level (after a rebirth, say) is worked as the nurse's Role until it opens again
-- (Logic/Jobs.effective): nothing is lost. Iterate `Jobs.Order`; `for id, job in Jobs` yields only jobs.
--
--   Name   the job picker's label (one word)
--   Icon   the job hat on the nurse's task bubble and the picker
--   Dept   the department the job works in (Data/Departments): a specialty there gives +40% (Config.Nurses
--          .SpecialtyBoost). "Station" = the department of the station it makes at (Logic/Jobs.department)
--   Opens  the hospital level it opens at
--   Text   what it does, 6 words or fewer (the picker's line)
-- "Rest" is not a job: it marks an over-roster nurse that isn't working (Logic/Schema; build plan §E2). (The Rest
-- Ward's department id is also "Rest", in Data/Departments: a different list, never a job.)
-- The Real Clinic (design §15 #1): a Maker stocks supplies into the nurse tray (never medicines: the player
-- dispenses); a Healer or Medic examines a patient and hands over what's in the tray.

export type JobId = string
export type Job = {
	Name: string,
	Icon: string,
	Dept: string,
	Opens: number,
	Text: string,
}

local ENTRIES: { [JobId]: Job } = {
	Maker = { Name = "Maker", Icon = "🧪", Dept = "Station", Opens = 1, Text = "Stocks supplies for patients" },
	Healer = { Name = "Healer", Icon = "🩺", Dept = "Reception", Opens = 1, Text = "Examines and helps patients" },
	Cheerer = { Name = "Cheerer", Icon = "🎉", Dept = "Reception", Opens = 1, Text = "Patients wait longer" },
	Receptionist = {
		Name = "Receptionist",
		Icon = "🛎️",
		Dept = "Reception",
		Opens = 1,
		Text = "Patients come sooner",
	},
	Porter = { Name = "Porter", Icon = "↕️", Dept = "Wards", Opens = 2, Text = "Rides patients upstairs" },
	Medic = { Name = "Medic", Icon = "🚑", Dept = "AE", Opens = 2, Text = "Helps ambulance patients" },
}

local ORDER = { "Maker", "Healer", "Cheerer", "Receptionist", "Porter", "Medic" }

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = { Order: { JobId }, [JobId]: Job }
return freeze(setmetatable(ENTRIES, { __index = { Order = freeze(ORDER) } })) :: Module
