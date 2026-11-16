--!strict
-- Finds the brother's Shop model in Workspace (by part names), or builds a grey placeholder
-- so the game is playable before the real build exists. Contract: docs/plan/2026-11-16-game-plan.md §4.

local Workspace = game:GetService("Workspace")

export type Shop = {
	Model: Model,
	QueueStart: BasePart,
	CustomerSpawn: BasePart,
	CustomerExit: BasePart,
	Station: BasePart,
	Counter: BasePart?,
}

local ShopWorld = {}

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function marker(name: string, cframe: CFrame, parent: Instance): Part
	return part({
		Name = name,
		Size = Vector3.new(2, 1, 2),
		CFrame = cframe,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	}, parent)
end

local function buildPlaceholder(): Model
	local model = Instance.new("Model")
	model.Name = "Shop"
	local origin = Vector3.new(0, 0, 0)

	part({
		Name = "Floor",
		Size = Vector3.new(40, 1, 40),
		Position = origin + Vector3.new(0, 0.5, 0),
		Color = Color3.fromRGB(235, 220, 200),
		Material = Enum.Material.WoodPlanks,
	}, model)
	part({
		Name = "Counter",
		Size = Vector3.new(14, 4, 3),
		Position = origin + Vector3.new(0, 3, -8),
		Color = Color3.fromRGB(170, 110, 70),
		Material = Enum.Material.Wood,
	}, model)
	local station = part({
		Name = "Station",
		Size = Vector3.new(4, 5, 3),
		Position = origin + Vector3.new(0, 3.5, -16),
		Color = Color3.fromRGB(200, 70, 70),
		Material = Enum.Material.SmoothPlastic,
	}, model)
	station:SetAttribute("Placeholder", true)
	-- Back wall
	part({
		Name = "BackWall",
		Size = Vector3.new(40, 12, 1),
		Position = origin + Vector3.new(0, 7, -20),
		Color = Color3.fromRGB(250, 240, 230),
	}, model)

	-- Queue faces the counter (toward -Z); customers line up behind it toward +Z.
	marker("QueueStart", CFrame.lookAt(origin + Vector3.new(0, 1.5, -5), origin + Vector3.new(0, 1.5, -8)), model)
	marker("CustomerSpawn", CFrame.new(origin + Vector3.new(8, 1.5, 18)), model)
	marker("CustomerExit", CFrame.new(origin + Vector3.new(-8, 1.5, 18)), model)

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "PlayerSpawn"
	spawnLocation.Anchored = true
	spawnLocation.Size = Vector3.new(6, 1, 6)
	spawnLocation.Position = origin + Vector3.new(-6, 1.1, -12)
	spawnLocation.Transparency = 0.5
	spawnLocation.Duration = 0
	spawnLocation.Parent = model

	model.Parent = Workspace
	return model
end

local function findPart(model: Model, name: string): BasePart?
	local found = model:FindFirstChild(name, true)
	if found and found:IsA("BasePart") then
		return found
	end
	if found and found:IsA("Model") and found.PrimaryPart then
		return found.PrimaryPart
	end
	return nil
end

function ShopWorld.get(): Shop
	local existing = Workspace:FindFirstChild("Shop")
	local model: Model
	if existing and existing:IsA("Model") then
		model = existing
	else
		warn("[ShopWorld] No Model named 'Shop' in Workspace, building a placeholder.")
		model = buildPlaceholder()
	end

	local queueStart = findPart(model, "QueueStart")
	local spawnPart = findPart(model, "CustomerSpawn")
	local exitPart = findPart(model, "CustomerExit")
	local station = findPart(model, "Station")
	assert(queueStart, "Shop is missing a part named QueueStart")
	assert(spawnPart, "Shop is missing a part named CustomerSpawn")
	assert(station, "Shop is missing a part named Station")

	return {
		Model = model,
		QueueStart = queueStart,
		CustomerSpawn = spawnPart,
		CustomerExit = exitPart or spawnPart,
		Station = station,
		Counter = findPart(model, "Counter"),
	}
end

return ShopWorld
