--!strict
-- Hospital v2's rules: floors, departments, routing, triage, urgent recipes, arrival and rest times (Progression v2
-- build plan §B5/§B7; design §6). Pure: no Roblox services, no requires. `levels` is Shared/Data/Levels (an array,
-- Levels[level]); `cfg` Shared/Config.
--
--   Hospital.floors(level, levels): number          walkable floors above the ground (Data/Levels Floors; 0 at Lv 1)
--   Hospital.departments(level, levels): { DeptId } the departments open at that level (a copy of its row's list)
--   Hospital.isOpen(dept, level, levels): boolean   that department is open at that level
--   Hospital.route(wing, urgent, level, levels): DeptId
--       where a treated patient recovers: "Hydro" for a Bath-wing patient once Hydro is open, else "Wards". (The
--       Stand's own ground bed still comes first when it's free: Patients' choice, not this one)
--   Hospital.triageOptions(level, levels): { DeptId }?
--       the places a patient can be sent once two or more are open (Wards and Hydro from Lv 3), else nil
--   Hospital.urgentRecipe(recipe, items, cap, minItems?): { ItemId }?
--       an urgent (🚑/🚁) patient's recipe: the first max(cap, minItems) items (minItems default 2, Config.AE.MinItems);
--       a 1-item recipe is padded with the other First-Aid Stand item (🧪 <-> 🩹). nil when the plot can't make every
--       item (`items` = { [ItemId]: true }, what its stations make)
--   Hospital.arrival(base, factors): number         base seconds x every factor (finite and > 0; others ignored),
--                                                   never below 1 s
--   Hospital.recover(base, factors): number         the same for rest seconds, never below 0.5 s
--   Hospital.nightOwl(nightEndedAt, now, cfg): boolean
--       the 🦉 Night Owl perk: within cfg.NightOwl x cfg.NightSeconds seconds after the night ended, night patients
--       still come to this clinic (§E4)

local Hospital = {}

Hospital.DESTINATIONS = table.freeze({ "Wards", "Hydro" }) -- where a treated patient can recover, in triage order
Hospital.PAD = table.freeze({ Potion = "Plaster", Plaster = "Potion" }) -- the other First-Aid Stand item
Hospital.MIN_ITEMS = 2 -- Config.AE.MinItems (Hospital.spec checks they match)

local function num(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

local function rowOf(levels: any, level: any): any
	if type(levels) ~= "table" or #levels == 0 then
		return {}
	end
	local index = math.clamp(math.floor(num(level, 1)), 1, #levels)
	local row = levels[index]
	return if type(row) == "table" then row else {}
end

function Hospital.floors(level: any, levels: any): number
	return math.max(0, math.floor(num(rowOf(levels, level).Floors, 0)))
end

function Hospital.departments(level: any, levels: any): { string }
	local list = rowOf(levels, level).Departments
	local out: { string } = {}
	if type(list) == "table" then
		for _, dept in list do
			if type(dept) == "string" then
				table.insert(out, dept)
			end
		end
	end
	return out
end

function Hospital.isOpen(dept: string, level: any, levels: any): boolean
	return table.find(Hospital.departments(level, levels), dept) ~= nil
end

function Hospital.route(wing: any, _urgent: any, level: any, levels: any): string
	if wing == "Bath" and Hospital.isOpen("Hydro", level, levels) then
		return "Hydro"
	end
	return "Wards"
end

function Hospital.triageOptions(level: any, levels: any): { string }?
	local open: { string } = {}
	for _, dept in Hospital.DESTINATIONS do
		if Hospital.isOpen(dept, level, levels) then
			table.insert(open, dept)
		end
	end
	return if #open >= 2 then open else nil
end

function Hospital.urgentRecipe(
	recipe: { string },
	items: { [string]: boolean },
	cap: number,
	minItems: number?
): { string }?
	local need = math.max(1, math.floor(num(minItems, Hospital.MIN_ITEMS)))
	local limit = math.clamp(math.max(math.floor(num(cap, 1)), need), 1, 3)
	local out: { string } = {}
	for index, item in recipe do
		if index > limit then
			break
		end
		table.insert(out, item)
	end
	if #out == 1 and #out < need then
		local pad = Hospital.PAD[out[1]]
		if pad then
			table.insert(out, pad)
		end
	end
	if #out == 0 then
		return nil
	end
	for _, item in out do
		if type(items) ~= "table" or items[item] ~= true then
			return nil
		end
	end
	return out
end

local function scaled(base: number, factors: { number }?): number
	local value = math.max(0, num(base, 0))
	if type(factors) == "table" then
		for _, factor in factors do
			local f = num(factor, 1)
			if f > 0 then
				value *= f
			end
		end
	end
	return value
end

function Hospital.arrival(base: number, factors: { number }?): number
	return math.max(1, scaled(base, factors))
end

function Hospital.recover(base: number, factors: { number }?): number
	return math.max(0.5, scaled(base, factors))
end

function Hospital.nightOwl(nightEndedAt: number, now: number, cfg: any): boolean
	if type(cfg) ~= "table" then
		return false
	end
	local window = math.max(0, num(cfg.NightOwl, 0)) * math.max(0, num(cfg.NightSeconds, 0))
	local since = num(now, 0) - num(nightEndedAt, math.huge)
	return since >= 0 and since <= window
end

return Hospital
