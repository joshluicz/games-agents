--!strict
-- The hospital's inside view (look build plan §B6; docs/research/2026-11-16-hospital-building.md §3.7). Client only.
-- OWNER: T3.
-- The upper storeys' outer walls are SOLID now (kids can't walk out of F3), so the camera needs help to look in:
-- while the local character stands inside a plot's building footprint on floor n >= 1, every part with the attribute
-- Storey > n gets LocalTransparencyModifier = 1 (its SurfaceGuis and BillboardGuis switch off with it), and floor n's
-- Outer parts (walls, glass bands, ribbon windows) get 0.6. The camera's Popper ignores a part at 0.25 total
-- transparency or more, so it looks in from above like a dollhouse. The ground floor hides nothing. Nothing
-- replicates: other players see the building whole.
-- It watches only the local character: once a second while it is off every building, 4 times a second while it is
-- on one, and it changes parts only when the building or the floor changes. No tweens, so there is nothing for
-- reduced motion to calm.
--
--   Cutaway.init(ctx)     starts the watcher
--   Cutaway.Pure          floorOf(y, slabTops) · hide(n, storey, outer) · tops(slabTops, floors) · inside(x, z,
--                         rect, margin) · feet(rootY, rootHalf, hipHeight): tests/Hospital.spec loads the PURE block
-- Reads: Workspace.Clinics.Plot_<n>.Building (its Level, Floors and Origin attributes; Server/HospitalBuilder) and
-- Shared/Logic/Building (the footprints and slab tops).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local BuildingLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Building"))

local Cutaway = {}

-- PURE-BEGIN
-- Numbers only (no Roblox types).
local Pure = {}

Pure.CHECKS_PER_SECOND = 4 -- while the character is inside a building's footprint
Pure.IDLE_SECONDS = 1 -- while it is not (to notice it walking in)
Pure.FADE = 0.6 -- your own floor's outer walls
Pure.STEP = 0.5 -- standing this far under a slab's top already counts as on it (a hop, a stair's last step)
Pure.MARGIN = 0.5 -- the footprint counts this far out (standing in a doorway)
Pure.R6_LEGS = 2 -- an R6 character (HipHeight 0) stands on 2-stud legs

-- The floor a character at height `y` (its feet, plot-local) is on: the highest slab at or under it. 0 = the ground.
function Pure.floorOf(y: number, slabTops: { number }): number
	local floor = 0
	for index, top in slabTops do
		if y >= top - Pure.STEP then
			floor = index
		end
	end
	return floor
end

-- A part's LocalTransparencyModifier while you stand on floor `n`: everything above you hides, your own floor's
-- outer walls fade, the rest stays. On the ground (n = 0) nothing changes.
function Pure.hide(n: number, storey: number, outer: boolean): number
	if n < 1 then
		return 0
	end
	if storey > n then
		return 1
	end
	if storey == n and outer then
		return Pure.FADE
	end
	return 0
end

-- The slab tops a building with `floors` upper floors has (Logic/Building.SLAB_TOPS, cut to its floors).
function Pure.tops(slabTops: { number }, floors: number): { number }
	local out = {}
	for index = 1, math.min(#slabTops, math.max(0, math.floor(floors))) do
		out[index] = slabTops[index]
	end
	return out
end

-- Whether (x, z) is inside a { X0, X1, Z0, Z1 } rectangle grown by `margin`.
function Pure.inside(x: number, z: number, rect: { X0: number, X1: number, Z0: number, Z1: number }, margin: number)
	return x >= rect.X0 - margin and x <= rect.X1 + margin and z >= rect.Z0 - margin and z <= rect.Z1 + margin
end

-- A character's feet from its root: R15 stands HipHeight under the root's bottom; R6 (HipHeight 0) on 2-stud legs.
function Pure.feet(rootY: number, rootHalf: number, hipHeight: number): number
	return rootY - rootHalf - (if hipHeight > 0 then hipHeight else Pure.R6_LEGS)
end
-- PURE-END

Cutaway.Pure = Pure

-- The building the local character stands in and its floor (nil, 0: none).
local function locate(player: Player): (Model?, number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil, 0
	end
	local humanoid = (character :: Model):FindFirstChildOfClass("Humanoid")
	local clinics = Workspace:FindFirstChild("Clinics")
	if not clinics then
		return nil, 0
	end
	for _, plot in clinics:GetChildren() do
		local building = plot:FindFirstChild("Building")
		local floors = building and building:GetAttribute("Floors")
		if building and building:IsA("Model") and type(floors) == "number" and floors >= 1 then
			local origin = building:GetAttribute("Origin")
			local frame = if typeof(origin) == "CFrame" then origin else building:GetPivot()
			local here = frame:PointToObjectSpace(root.Position)
			local level = building:GetAttribute("Level")
			local rect = BuildingLogic.footprint(if type(level) == "number" then level else 1, 0)
			if Pure.inside(here.X, here.Z, rect, Pure.MARGIN) then
				local hip = if humanoid then humanoid.HipHeight else 0
				local feet = Pure.feet(here.Y, root.Size.Y / 2, hip)
				return building, Pure.floorOf(feet, Pure.tops(BuildingLogic.SLAB_TOPS, floors))
			end
		end
	end
	return nil, 0
end

-- A part's Storey: its own attribute, else the nearest piece's under the building. nil = never hidden.
local function storeyOf(part: BasePart, building: Model): number?
	local node: Instance? = part
	while node and node ~= building do
		local storey = node:GetAttribute("Storey")
		if type(storey) == "number" then
			return storey
		end
		node = node.Parent
	end
	return nil
end

local hidden: { BasePart } = {}
local switchedOff: { LayerCollector } = {}

local function restore()
	for _, part in hidden do
		if part.Parent then
			part.LocalTransparencyModifier = 0
		end
	end
	for _, gui in switchedOff do
		if gui.Parent then
			gui.Enabled = true
		end
	end
	table.clear(hidden)
	table.clear(switchedOff)
end

local function apply(building: Model, floor: number)
	for _, descendant in building:GetDescendants() do
		if descendant:IsA("BasePart") then
			local storey = storeyOf(descendant, building)
			local amount = if storey then Pure.hide(floor, storey, descendant:GetAttribute("Outer") == true) else 0
			if amount > 0 then
				descendant.LocalTransparencyModifier = amount
				table.insert(hidden, descendant)
				if amount >= 1 then
					-- A hidden part's labels go too (a SurfaceGui draws even on an invisible part).
					for _, child in descendant:GetChildren() do
						if child:IsA("LayerCollector") and child.Enabled then
							child.Enabled = false
							table.insert(switchedOff, child)
						end
					end
				end
			end
		end
	end
end

function Cutaway.init(_ctx: Types.Ctx)
	local player = Players.LocalPlayer
	local current: Model? = nil
	local currentFloor = 0
	task.spawn(function()
		while true do
			debug.profilebegin("Cutaway")
			local ok, building, floor = pcall(locate, player)
			if not ok then
				building, floor = nil, 0
			end
			if building ~= current or floor ~= currentFloor then
				restore()
				current, currentFloor = building, floor
				if building and floor >= 1 then
					local applied, err = pcall(apply, building, floor)
					if not applied then
						warn("[Cutaway] " .. tostring(err))
					end
				end
			end
			debug.profileend()
			task.wait(if building then 1 / Pure.CHECKS_PER_SECOND else Pure.IDLE_SECONDS)
		end
	end)
end

return Cutaway
