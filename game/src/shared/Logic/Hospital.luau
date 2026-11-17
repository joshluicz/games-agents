--!strict
-- Hospital rules: floors, departments, where a patient who stays rests, the ward pick, urgent plans, arrival and
-- rest times (Progression v2 build plan §B5/§B7; Real Clinic build plan, Task 4; design §6, §10 and §15 #3). Pure: no
-- Roblox services, no requires. `levels` is Shared/Data/Levels (an array, Levels[level]); `cfg` Shared/Config.
--
--   Hospital.floors(level, levels): number          OPEN floors above the ground (Data/Levels Floors; 0 at Lv 1)
--   Hospital.departments(level, levels): { DeptId } the departments open at that level (a copy of its row's list)
--   Hospital.isOpen(dept, level, levels): boolean   that department is open at that level
--   Hospital.route(stay, urgent, level, levels): DeptId?
--       where a treated patient rests before going home: its case's Stay ("Wards", the Injury Ward on F1, or "Rest",
--       the Rest Ward on F2 and F3) once that department is open at the level; nil = it goes straight home. It agrees
--       with Logic/Visit.stayWard (HospitalLogic.spec checks it). `urgent` doesn't change it
--   Hospital.triageOptions(level, levels): { DeptId }?
--       the wards a staying patient can be sent to once both are open ("Injury Ward or Rest Ward?" from Lv 3), else
--       nil
--   Hospital.pad(item): ItemId                      what pads a one-step urgent plan: a 🧊 Ice pack (a plan that is
--                                                   only an ice pack gets a 🩹 Plaster instead)
--   Hospital.urgentRecipe(plan, items, cap, minItems?): { ItemId }?
--       an urgent (🚑/🚁) patient's plan: its first max(cap, minItems) steps (minItems default 2, Config.AE.MinItems);
--       a one-step plan is padded (Hospital.pad). nil when the plot can't make every step (`items` = { [ItemId]:
--       true }, what its open stations make)
--   Hospital.arrival(base, factors): number         base seconds x every factor (finite and > 0; others ignored),
--                                                   never below 1 s
--   Hospital.recover(base, factors): number         the same for rest seconds, never below 0.5 s
--   Hospital.nightOwl(nightEndedAt, now, cfg): boolean
--       the 🦉 Night Owl perk: within cfg.NightOwl x cfg.NightSeconds seconds after the night ended, night patients
--       still come to this clinic (§E4)

local Hospital = {}

Hospital.DESTINATIONS = table.freeze({ "Wards", "Rest" }) -- the wards a staying patient can rest in, in pick order
Hospital.PAD = "Ice" -- the step that pads a one-step urgent plan
Hospital.PAD_ICE = "Plaster" -- ... unless that one step is an ice pack already
Hospital.MIN_ITEMS = 2 -- Config.AE.MinItems (HospitalLogic.spec checks they match)

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

function Hospital.route(stay: any, _urgent: any, level: any, levels: any): string?
	if type(stay) == "string" and table.find(Hospital.DESTINATIONS, stay) and Hospital.isOpen(stay, level, levels) then
		return stay
	end
	return nil
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

function Hospital.pad(item: any): string
	return if item == Hospital.PAD then Hospital.PAD_ICE else Hospital.PAD
end

function Hospital.urgentRecipe(
	plan: { string },
	items: { [string]: boolean },
	cap: number,
	minItems: number?
): { string }?
	local need = math.max(1, math.floor(num(minItems, Hospital.MIN_ITEMS)))
	local limit = math.clamp(math.max(math.floor(num(cap, 1)), need), 1, 3)
	local out: { string } = {}
	if type(plan) == "table" then
		for index, item in plan do
			if index > limit then
				break
			end
			table.insert(out, item)
		end
	end
	if #out == 1 and #out < need then
		table.insert(out, Hospital.pad(out[1]))
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
