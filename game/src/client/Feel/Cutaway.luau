--!strict
-- The hospital's inside view (look build plan §B6; docs/research/2026-11-16-hospital-building.md §3.7). Client only.
-- OWNER: T3.
-- The upper storeys' outer walls are SOLID now (kids can't walk out of F3), so the camera needs help to look in:
-- while the local character stands inside a plot's building footprint on floor n >= 1, every part with the attribute
-- Storey > n is hidden (its SurfaceGuis and BillboardGuis switch off with it), and floor n's Outer parts (walls, glass
-- bands, ribbon windows) fade 0.6 of the way, so it looks in from above like a dollhouse. The ground floor hides
-- nothing. Nothing replicates: other players see the building whole.
-- Invisicam (Server/Main sets DevCameraOcclusionMode for everyone: memory-20261117-006, the see-through camera) fades
-- whatever stands between the camera and you by writing LocalTransparencyModifier, and puts back the
-- value it found when the part stops being in the way. So the cutaway never touches LocalTransparencyModifier: it
-- writes the part's own Transparency (a client-side write: it never replicates) and puts back the value it found.
-- The two never write the same property, so neither re-shows what the other hid: a hidden part (Transparency 1)
-- stays hidden while Invisicam fades it, and Invisicam never restores a stale value over the cutaway's. A part
-- already at Transparency 1 (a builder's hidden part, e.g. the stairwell's steps where nobody may see them) is never
-- touched, so the cutaway can't show it.
-- It watches only the local character: once a second while it is off every building, 4 times a second while it is
-- on one; it puts parts back only when the building or the floor changes, and while you stay upstairs it looks for
-- new pieces once a second. No tweens, so there is nothing for reduced motion to calm.
--
--   Cutaway.init(ctx)     starts the watcher
--   Cutaway.Pure          floorOf(y, slabTops) · hide(n, storey, outer) · tops(slabTops, floors) · inside(x, z,
--                         rect, margin) · feet(rootY, rootHalf, hipHeight) · fade(transparency, amount):
--                         tests/Hospital.spec and tests/Camera.spec load the PURE block
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
Pure.REAPPLY_SECONDS = 1 -- while you stay upstairs, new pieces (streamed in, rebuilt) are looked for this often
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

-- How far a part fades while you stand on floor `n` (0 = as built, 1 = gone): everything above you hides, your own
-- floor's outer walls fade, the rest stays. On the ground (n = 0) nothing changes.
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

-- A part's Transparency once it fades by `amount` (Pure.hide) from its own `transparency`: the same look as a
-- LocalTransparencyModifier of `amount` would give (1 - (1 - t) x (1 - amount)), clamped to 0..1.
function Pure.fade(transparency: number, amount: number): number
	local t = math.clamp(transparency, 0, 1)
	return math.clamp(t + (1 - t) * math.clamp(amount, 0, 1), 0, 1)
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

-- Every part the cutaway fades now: how far (Pure.hide), and the Transparency it has as built (put back by
-- restore()). Feel/HospitalFX's grow-in writes through Cutaway.write, so a level-up while you stand upstairs never
-- leaves a part stuck half-faded or shows a storey the cutaway hides.
local fades: { [BasePart]: number } = {}
local bases: { [BasePart]: number } = {}
local switchedOff: { LayerCollector } = {}

-- A part's Transparency as built (what the cutaway puts back), whether or not the cutaway fades it now.
function Cutaway.baseOf(part: BasePart): number
	return bases[part] or part.Transparency
end

-- Sets a part's as-built Transparency (HospitalFX's grow-in): the cutaway's fade stays on top while it hides it.
function Cutaway.write(part: BasePart, transparency: number)
	local amount = fades[part]
	if amount then
		bases[part] = transparency
		part.Transparency = Pure.fade(transparency, amount)
	else
		part.Transparency = transparency
	end
end

local function restore()
	for part in fades do
		local base = bases[part]
		if part.Parent and base then
			part.Transparency = base
		end
	end
	for _, gui in switchedOff do
		if gui.Parent then
			gui.Enabled = true
		end
	end
	table.clear(fades)
	table.clear(bases)
	table.clear(switchedOff)
end

local function apply(building: Model, floor: number)
	for _, descendant in building:GetDescendants() do
		if descendant:IsA("BasePart") then
			local storey = storeyOf(descendant, building)
			local amount = if storey then Pure.hide(floor, storey, descendant:GetAttribute("Outer") == true) else 0
			-- Pure.fade never lowers a Transparency: a part a builder hid (1) stays hidden.
			if amount > 0 and fades[descendant] == nil then
				bases[descendant] = descendant.Transparency
				fades[descendant] = amount
				descendant.Transparency = Pure.fade(descendant.Transparency, amount)
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
	local appliedAt = 0
	task.spawn(function()
		while true do
			debug.profilebegin("Cutaway")
			local ok, building, floor = pcall(locate, player)
			if not ok then
				building, floor = nil, 0
			end
			local changed = building ~= current or floor ~= currentFloor
			if changed then
				restore()
				current, currentFloor = building, floor
			end
			-- Again every REAPPLY_SECONDS while you stay upstairs: pieces that streamed in or were rebuilt since get
			-- hidden too (apply skips the parts it fades already).
			if building and floor >= 1 and (changed or os.clock() - appliedAt >= Pure.REAPPLY_SECONDS) then
				appliedAt = os.clock()
				local applied, err = pcall(apply, building, floor)
				if not applied then
					warn("[Cutaway] " .. tostring(err))
				end
			end
			debug.profileend()
			task.wait(if building then 1 / Pure.CHECKS_PER_SECOND else Pure.IDLE_SECONDS)
		end
	end)
end

return Cutaway
