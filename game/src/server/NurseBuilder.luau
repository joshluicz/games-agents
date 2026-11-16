--!strict
-- Builds a nurse Model (depth-update build plan §B8). Server only, a library (not in Main's start order). OWNER: T3.
-- FOUNDATION STUB: the plain creature from the nurse's Look (CreatureBuilder.buildLook); T3 adds the nurse cap in the
-- rarity's colour, the rarity glow for Epic+, and the kit override.
--
--   NurseBuilder.build(nurseId): Model    Root PrimaryPart + welded parts (CollisionGroup "Patients"), under 40
--                                         parts, attributes NurseId, Rarity, Role. A Model at
--                                         ServerStorage.Nurses.<NurseId> replaces the placeholder (no scripts).
--   NurseBuilder.setTask(model, task)     the Task attribute: "Idle" | "Making" | "Healing" | "Cheering" |
--                                         "Walking" (and whatever pose T3 gives it)

local Shared = game:GetService("ReplicatedStorage").Shared
local NursesData = require(Shared.Data.Nurses)
local CreatureBuilder = require(script.Parent.CreatureBuilder)

local NurseBuilder = {}

function NurseBuilder.build(nurseId: string): Model
	local nurse = rawget(NursesData :: any, nurseId)
	local model = CreatureBuilder.buildLook(if nurse then nurse.Look else nil, "Nurse_" .. nurseId)
	model:SetAttribute("NurseId", nurseId)
	model:SetAttribute("Rarity", if nurse then nurse.Rarity else "Common")
	model:SetAttribute("Role", if nurse then nurse.Role else "Maker")
	model:SetAttribute("Task", "Idle")
	return model
end

function NurseBuilder.setTask(model: Model, task: string)
	model:SetAttribute("Task", task)
end

return NurseBuilder
