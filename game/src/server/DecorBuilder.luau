--!strict
-- STUB (Task 0). Owned by Task 7: replace with the real decor builder (build plan Task 7).
--   DecorBuilder.build(decorId): Model
-- Contract: the Model fits a 4 x 4 stud footprint and its pivot is its BOTTOM CENTRE (Plots pivots it onto the
-- DecorSlot's floor point). The real one builds from Data/Decor `Look`, or clones
-- ServerStorage.ClinicKit.Decor.<DecorId>. This stub returns a small coloured block with the decor's icon.

local Shared = game:GetService("ReplicatedStorage").Shared
local Decor = require(Shared.Data.Decor)

local DecorBuilder = {}

function DecorBuilder.build(decorId: string): Model
	local entry = Decor[decorId]
	local model = Instance.new("Model")
	model.Name = decorId

	local block = Instance.new("Part")
	block.Name = "Body"
	block.Size = Vector3.new(2.5, 2.5, 2.5)
	block.CFrame = CFrame.new(0, 1.25, 0)
	block.Anchored = true
	block.Material = Enum.Material.SmoothPlastic
	block.Color = if entry then Color3.fromHex(entry.Look.Color) else Color3.fromRGB(255, 220, 180)
	block.Parent = model

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(2, 2)
	gui.StudsOffset = Vector3.new(0, 2.4, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 60
	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.fromScale(1, 1)
	icon.BackgroundTransparency = 1
	icon.TextScaled = true
	icon.Text = if entry then entry.Icon else "❔"
	icon.Parent = gui
	gui.Parent = block

	model.WorldPivot = CFrame.identity -- bottom centre
	return model
end

function DecorBuilder.start() end

return DecorBuilder
