--!strict
-- STUB (Task 0). Owned by Task 1: replace with the real creature builder (build plan Task 1).
--   CreatureBuilder.build(patientId, variant?): Model
-- Looks up the recipe in Data/Patients, then Data/Regulars (regulars use their own id). The real one builds a
-- cute placeholder from `Look`, or clones ServerStorage.Creatures.<PatientId>, and has an `IconAnchor`
-- Attachment for the ailment icon. This stub returns a coloured ball so callers always get a valid Model.

local Shared = game:GetService("ReplicatedStorage").Shared
local Patients = require(Shared.Data.Patients)
local Regulars = require(Shared.Data.Regulars)

local CreatureBuilder = {}

function CreatureBuilder.build(patientId: string, _variant: string?): Model
	local entry = Patients[patientId] or Regulars[patientId]
	local model = Instance.new("Model")
	model.Name = patientId

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.one * 3
	body.Anchored = true
	body.CanCollide = false
	body.Material = Enum.Material.SmoothPlastic
	body.Color = if entry then Color3.fromHex(entry.Look.Body) else Color3.fromRGB(255, 200, 220)
	body.Parent = model
	model.PrimaryPart = body

	local anchor = Instance.new("Attachment")
	anchor.Name = "IconAnchor"
	anchor.Position = Vector3.new(0, 2.6, 0)
	anchor.Parent = body
	return model
end

function CreatureBuilder.start() end

return CreatureBuilder
