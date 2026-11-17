--!strict
-- A visit's rules: examine -> treat -> dispense (Real Clinic build plan, contract C4; design §5, §6 and §15). Pure:
-- no Roblox services and no requires, so Lune tests it (tests/Visit.spec). Inputs are never changed.
-- `case` is a row of Shared/Data/Cases, `items` Shared/Data/Items, `tools` Shared/Data/Tools, `cfg` Shared/Config.
-- The server decides everything here (Server/Patients, Server/Treatment); the client only draws it.
--
--   Visit.PATIENCE = { Waiting = 0.5, Bay = 1 }   how fast patience drains in the waiting room and in a bay waiting
--                                                 for the doctor (it pauses during every mini-game)
--   Visit.EXAMS_GLOW = 3                          Config.Visit.ExamsGlow
--   Visit.rollCase(pool, can, roll): CaseId?      one of the pool's cases that `can(caseId)` allows, picked evenly by
--                                                 `roll` in [0, 1) (an id listed twice is twice as likely); nil when
--                                                 none is allowed
--   Visit.canTreat(case, level, rooms, stationOpen, items): boolean
--                                                 this clinic can treat that case: its Level, its Room (rooms =
--                                                 { [RoomId]: boolean }, the rooms owned) and EVERY plan item's
--                                                 station open (stationOpen(stationId)). A case never comes to a
--                                                 clinic where this is false (Review Focus 1)
--   Visit.unlocked(level, tools): { ToolId }      the tools in use at that level, in Tools.ORDER: 🩺 🌡️ 🔍 at Lv 1
--                                                 (so the exam card shows exactly those three), the 🔦 Light from
--                                                 Lv 2, the X-ray from Lv 3 (Data/Tools Level)
--   Visit.examTools(answer, unlocked, roll): { ToolId }
--                                                 the exam card's tools: 3 distinct ones (fewer when fewer are
--                                                 unlocked), the answer always among them, the other two and the
--                                                 order decided by `roll` in [0, 1)
--   Visit.glow(examsDone, simple, cfg?): boolean  the right tool glows: for a player's first EXAMS_GLOW exams
--                                                 (examsDone = their saved count of patients treated), and always
--                                                 in Simple mode
--   Visit.plan(case, cap): { ItemId }             the case's plan cut to the level's cap: its first `cap` steps (cap
--                                                 clamped to 1..3), as Logic/Recipe.effective (repeated here: no
--                                                 requires; Visit.spec checks they agree)
--   Visit.stayWard(case, level): ("Wards" | "Rest")?
--                                                 where a treated patient rests before going home: its case's Stay,
--                                                 "Wards" from Lv 2 and "Rest" from Lv 3; nil = it goes straight home
--   Visit.nextForBay(waiting, kind): number?      who walks to a bay that just came free. waiting = { { Id, Since,
--                                                 Tool } } (Since = when it sat down). The one who has waited longest
--                                                 among those the bay fits: a patient whose tool is the X-ray goes
--                                                 only to an "XRay" bay, everyone else only to an "Exam" bay
--   Visit.front(inBays): number?                  the front patient (what nurses, abilities, the guide pin and the
--                                                 tutorial point at): of the bay patients { Id, Since, NeedsDoctor }
--                                                 that need the doctor, the one who has waited longest (Since = when
--                                                 it began waiting for the doctor)

local Visit = {}

Visit.PATIENCE = table.freeze({ Waiting = 0.5, Bay = 1 })
Visit.EXAMS_GLOW = 3
Visit.MAX_PLAN = 3 -- Logic/Recipe.MAX
Visit.EXAM_TOOLS = 3 -- tools on the exam card
Visit.XRAY = "XRay" -- the tool that is a machine (Data/Tools.XRay.Machine): its cases go to the "XRay" bay

local STAY_LEVEL: { [string]: number } = { Wards = 2, Rest = 3 }

local function num(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

-- A roll in [0, 1): anything else is folded into it (a bad roll still picks something).
local function unit(roll: any): number
	local value = num(roll, 0)
	value -= math.floor(value)
	return math.clamp(value, 0, 0.999999)
end

function Visit.rollCase(pool: { string }, can: (string) -> boolean, roll: number): string?
	if type(pool) ~= "table" or type(can) ~= "function" then
		return nil
	end
	local allowed: { string } = {}
	for _, caseId in pool do
		if type(caseId) == "string" and can(caseId) == true then
			table.insert(allowed, caseId)
		end
	end
	if #allowed == 0 then
		return nil
	end
	return allowed[math.floor(unit(roll) * #allowed) + 1]
end

function Visit.canTreat(
	case: any,
	level: number,
	rooms: { [string]: boolean },
	stationOpen: (string) -> boolean,
	items: any
): boolean
	if type(case) ~= "table" or type(case.Plan) ~= "table" or #case.Plan == 0 then
		return false
	end
	if math.floor(num(level, 1)) < num(case.Level, 1) then
		return false
	end
	if case.Room ~= nil and not (type(rooms) == "table" and rooms[case.Room] == true) then
		return false
	end
	if type(stationOpen) ~= "function" or type(items) ~= "table" then
		return false
	end
	for _, itemId in case.Plan do
		local item = rawget(items, itemId)
		if type(item) ~= "table" or type(item.Station) ~= "string" or stationOpen(item.Station) ~= true then
			return false
		end
	end
	return true
end

function Visit.unlocked(level: number, tools: any): { string }
	local out: { string } = {}
	if type(tools) ~= "table" or type(tools.ORDER) ~= "table" then
		return out
	end
	local lv = math.floor(num(level, 1))
	for _, toolId in tools.ORDER do
		local tool = rawget(tools, toolId)
		if type(tool) == "table" and lv >= num(tool.Level, 1) then
			table.insert(out, toolId)
		end
	end
	return out
end

function Visit.examTools(answer: string, unlocked: { string }, roll: number): { string }
	-- The other tools on offer: the unlocked ones, without the answer and without repeats.
	local others: { string } = {}
	if type(unlocked) == "table" then
		for _, toolId in unlocked do
			if type(toolId) == "string" and toolId ~= answer and not table.find(others, toolId) then
				table.insert(others, toolId)
			end
		end
	end
	-- The roll's digits decide each choice in turn (the same roll always gives the same card).
	local rest = unit(roll)
	local function pick(n: number): number
		rest *= n
		local index = math.floor(rest)
		rest -= index
		return math.min(index, n - 1) + 1
	end
	local out: { string } = {}
	for _ = 1, math.min(Visit.EXAM_TOOLS - 1, #others) do
		table.insert(out, table.remove(others, pick(#others)) :: string)
	end
	table.insert(out, pick(#out + 1), answer)
	return out
end

function Visit.glow(examsDone: number, simple: boolean, cfg: any?): boolean
	if simple == true then
		return true
	end
	local visit = if type(cfg) == "table" then cfg.Visit else nil
	local limit = if type(visit) == "table" then num(visit.ExamsGlow, Visit.EXAMS_GLOW) else Visit.EXAMS_GLOW
	return num(examsDone, 0) < limit
end

function Visit.plan(case: any, cap: number): { string }
	local out: { string } = {}
	if type(case) ~= "table" or type(case.Plan) ~= "table" then
		return out
	end
	local limit = if type(cap) == "number" and cap == cap then math.clamp(math.floor(cap), 1, Visit.MAX_PLAN) else 1
	for index, itemId in case.Plan do
		if index > limit then
			break
		end
		table.insert(out, itemId)
	end
	return out
end

function Visit.stayWard(case: any, level: number): string?
	if type(case) ~= "table" then
		return nil
	end
	local opens = STAY_LEVEL[case.Stay]
	if opens and math.floor(num(level, 1)) >= opens then
		return case.Stay
	end
	return nil
end

-- The row with the smallest Since among those `fits` allows (a tie: the lower Id).
local function longest(rows: any, fits: (any) -> boolean): number?
	if type(rows) ~= "table" then
		return nil
	end
	local best: any = nil
	for _, row in rows do
		if type(row) == "table" and type(row.Id) == "number" and fits(row) then
			local since = num(row.Since, math.huge)
			local bestSince = if best then num(best.Since, math.huge) else math.huge
			if not best or since < bestSince or (since == bestSince and row.Id < best.Id) then
				best = row
			end
		end
	end
	return if best then best.Id else nil
end

function Visit.nextForBay(waiting: { { Id: number, Since: number, Tool: string } }, kind: "Exam" | "XRay"): number?
	return longest(waiting, function(row)
		return (row.Tool == Visit.XRAY) == (kind == "XRay")
	end)
end

function Visit.front(inBays: { { Id: number, Since: number, NeedsDoctor: boolean } }): number?
	return longest(inBays, function(row)
		return row.NeedsDoctor == true
	end)
end

return Visit
