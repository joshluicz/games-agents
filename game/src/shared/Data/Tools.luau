--!strict
-- Exam tools: what the doctor examines a patient with (Real Clinic build plan, contract C3; design §7). Lune-safe.
-- Iterate `Tools.ORDER` (also `Tools.Order`); `for id, tool in Tools` yields only tools.
--
--   Game     the tool's own short game, a GameId (Logic/MiniGame.ENGINE says which engine plays it)
--   Machine  true: not a hand tool on a bay's tray but a machine in its own room. A case that needs it goes to an
--            "XRay" bay (Logic/Visit.nextForBay)
--   Level    the hospital level it works from (nil = 1): the X-ray room opens at Lv 3
-- The exam card shows 3 tools; the player picks the one that fits the symptom (Logic/Visit.examTools).

export type ToolId = string
export type Tool = {
	Name: string,
	Icon: string,
	Game: string, -- GameId
	Machine: boolean?,
	Level: number?,
}

local ENTRIES: { [ToolId]: Tool } = {
	Stethoscope = { Name = "Stethoscope", Icon = "🩺", Game = "Listen" }, -- listen to the chest
	Thermometer = { Name = "Thermometer", Icon = "🌡️", Game = "Temp" }, -- take a temperature
	Light = { Name = "Light", Icon = "🔦", Game = "Light" }, -- an ear or throat check
	Magnifier = { Name = "Magnifier", Icon = "🔍", Game = "Look" }, -- look at the sore spots
	XRay = { Name = "X-ray", Icon = "📸", Game = "XRay", Machine = true, Level = 3 },
}

local ORDER = { "Stethoscope", "Thermometer", "Light", "Magnifier", "XRay" }

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = { ORDER: { ToolId }, Order: { ToolId }, [ToolId]: Tool }
local order = freeze(ORDER)
return freeze(setmetatable(ENTRIES, { __index = { ORDER = order, Order = order } })) :: Module
