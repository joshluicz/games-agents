-- Fades the shop's roof while you're inside, so the roof never hides the counter or the queue.
-- Looks for a Model named "Roof" anywhere inside Workspace.Shop. Roof parts should be CanCollide off,
-- so the camera doesn't bump into them.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local FADE_PER_SECOND = 4

local parts: { BasePart } = {}
local roofCFrame: CFrame? = nil
local roofSize = Vector3.zero
local fade = 0

-- Re-scanned every couple of seconds, because the roof can stream in after you join
local function rescan()
	local shop = Workspace:FindFirstChild("Shop")
	local roof = shop and shop:FindFirstChild("Roof", true)
	table.clear(parts)
	roofCFrame = nil
	if not (roof and roof:IsA("Model")) then
		return
	end
	for _, descendant in roof:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
			descendant.LocalTransparencyModifier = fade
		end
	end
	if #parts > 0 then
		roofCFrame, roofSize = roof:GetBoundingBox()
	end
end

local function isInside(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (roofCFrame and root and root:IsA("BasePart")) then
		return false
	end
	local p = roofCFrame:PointToObjectSpace(root.Position)
	return math.abs(p.X) < roofSize.X / 2 and math.abs(p.Z) < roofSize.Z / 2 and p.Y < roofSize.Y / 2
end

task.spawn(function()
	while true do
		rescan()
		task.wait(2)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	local target = if isInside() then 1 else 0
	if fade == target then
		return
	end
	if target > fade then
		fade = math.min(target, fade + dt * FADE_PER_SECOND)
	else
		fade = math.max(target, fade - dt * FADE_PER_SECOND)
	end
	for _, part in parts do
		part.LocalTransparencyModifier = fade
	end
end)
