--!strict
-- Nurse jobs, departments and team bonuses (Progression v2 build plan §B5/§B7). Pure: no Roblox services, no
-- requires. `jobs` is Shared/Data/Jobs, `departments` Shared/Data/Departments (keyed maps with .Order, read with
-- rawget so "Order" is never an id).
--
--   Jobs.REST = "Rest"                           the Job of an over-roster nurse that isn't working (§E2)
--   Jobs.STATIONS · Jobs.WINGS                   StationId -> DeptId and WingId -> DeptId: the same maps as
--                                                Data/Departments.Stations / .Wings (Jobs.spec checks), used when no
--                                                map is passed
--   Jobs.open(jobId, level, jobs): boolean       a known job whose Opens <= the hospital level ("Rest" is no job)
--   Jobs.effective(job, role, level, jobs): JobId | "Rest"
--       what the nurse works now: "Rest" stays "Rest"; "" (or junk, or an unknown job) -> its role; a job that isn't
--       open at this level -> its role (after a rebirth a Porter makes or heals until Lv 2 again; nothing is lost)
--   Jobs.department(jobId, stationId?, jobs, stations?): DeptId
--       where a job works: its Data/Jobs Dept; a Maker's ("Station") is its station's department (stations =
--       Data/Departments.Stations; default Reception, the First-Aid Stand's)
--   Jobs.patientDepartment(wing, urgent, wings?): DeptId
--       a cured patient's department, for nurse XP: an urgent one (🚑/🚁) -> "AE", else its wing's (default Reception)
--   Jobs.teams(specialties, departments): { [DeptId]: number }
--       how many of the WORKING nurses' specialties match each department; "Any" counts for every one
--   Jobs.teamEffects(counts, departments): TeamEffects
--       { Cash, Urgent, Recover, Make = { [StationId]: factor } }, each a factor (1 = none). A team of 2 gives its
--       department's Team2, 3 or more its Team3 (they don't stack). Kind "Cash" x (1 + v), "Urgent" x (1 + v),
--       "Recover" x (1 - v), "Make" x (1 - v) at each listed station. Different departments multiply.

export type TeamEffects = { Cash: number, Urgent: number, Recover: number, Make: { [string]: number } }

local Jobs = {}

Jobs.REST = "Rest"
Jobs.DEFAULT_DEPT = "Reception"
Jobs.STATIONS = table.freeze({
	Remedy = "Reception",
	Plaster = "Reception",
	Bath = "Hydro",
	Cocoa = "Pharmacy",
	Pharmacy = "Pharmacy",
})
Jobs.WINGS = table.freeze({
	Starter = "Reception",
	Sunny = "Reception",
	Bath = "Hydro",
	Winter = "Pharmacy",
	Night = "Wards",
	Sky = "AE",
})

local function num(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

local function row(map: any, id: any): any
	if type(map) ~= "table" or type(id) ~= "string" then
		return nil
	end
	local value = rawget(map, id)
	return if type(value) == "table" then value else nil
end

local function ordered(map: any): { string }
	local ids: { string } = {}
	if type(map) == "table" and type(map.Order) == "table" then
		for _, id in map.Order do
			if type(id) == "string" and row(map, id) then
				table.insert(ids, id)
			end
		end
	end
	return ids
end

function Jobs.open(jobId: any, level: any, jobs: any): boolean
	local job = row(jobs, jobId)
	if not job then
		return false
	end
	return math.floor(num(level, 1)) >= math.max(1, math.floor(num(job.Opens, 1)))
end

function Jobs.effective(job: any, role: string, level: any, jobs: any): string
	if job == Jobs.REST then
		return Jobs.REST
	end
	if type(job) == "string" and job ~= "" and Jobs.open(job, level, jobs) then
		return job
	end
	return role
end

function Jobs.department(jobId: any, stationId: string?, jobs: any, stations: any?): string
	local job = row(jobs, jobId)
	if not job or type(job.Dept) ~= "string" then
		return Jobs.DEFAULT_DEPT
	end
	if job.Dept == "Station" then
		local map = if type(stations) == "table" then stations else Jobs.STATIONS
		local dept = if type(stationId) == "string" then map[stationId] else nil
		return if type(dept) == "string" then dept else Jobs.DEFAULT_DEPT
	end
	return job.Dept
end

function Jobs.patientDepartment(wing: any, urgent: any, wings: any?): string
	if urgent == "AE" or urgent == "VIP" then
		return "AE"
	end
	local map = if type(wings) == "table" then wings else Jobs.WINGS
	local dept = if type(wing) == "string" then map[wing] else nil
	return if type(dept) == "string" then dept else Jobs.DEFAULT_DEPT
end

function Jobs.teams(specialties: { string }, departments: any): { [string]: number }
	local counts: { [string]: number } = {}
	local ids = ordered(departments)
	for _, id in ids do
		counts[id] = 0
	end
	for _, specialty in specialties do
		if specialty == "Any" then
			for _, id in ids do
				counts[id] += 1
			end
		elseif type(specialty) == "string" and counts[specialty] ~= nil then
			counts[specialty] += 1
		end
	end
	return counts
end

function Jobs.teamEffects(counts: { [string]: number }, departments: any): TeamEffects
	local out: TeamEffects = { Cash = 1, Urgent = 1, Recover = 1, Make = {} }
	for _, id in ordered(departments) do
		local n = math.floor(num(counts[id], 0))
		local dept = row(departments, id)
		local effect = if n >= 3 then dept.Team3 elseif n == 2 then dept.Team2 else nil
		if type(effect) == "table" then
			local value = math.clamp(num(effect.Value, 0), 0, 0.9)
			if effect.Kind == "Cash" then
				out.Cash *= 1 + value
			elseif effect.Kind == "Urgent" then
				out.Urgent *= 1 + value
			elseif effect.Kind == "Recover" then
				out.Recover *= 1 - value
			elseif effect.Kind == "Make" and type(effect.Stations) == "table" then
				for _, stationId in effect.Stations do
					out.Make[stationId] = (out.Make[stationId] or 1) * (1 - value)
				end
			end
		end
	end
	return out
end

return Jobs
