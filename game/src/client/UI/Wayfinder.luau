--!strict
-- The tutorial's world guide (look build plan §B9; docs/research/2026-11-16-tutorial-ux.md §5.3-5.7). Client only.
-- A LIBRARY: nothing runs until `show`, and it has no init. OWNER: T8.
-- STUB (T8): the Foundation's first version. `show` draws only a pin over the target (an icon on a coloured disc);
-- T8 builds the real thing behind the same API:
--   · the BEAM (the main cue; Joshua: "closer to the floor", "connect the middle of the player body ... to the
--     objective"): a flat client-only Beam from GuideStart (an Attachment on the HumanoidRootPart at feet +
--     Config.Tutorial.BeamLift) to GuideEnd on Workspace.Terrain at the target's base. Re-aimed only while it
--     shows and the root moved; it bends round the Counter and hides within NearStuds
--   · the floor chevrons (at most MaxChevrons static parts), the glow (ONE Highlight, re-pointed, never re-made),
--     the pin (moved here from UI/Guide) and the touch hand
--
--   Wayfinder.show(spec)             point at spec.Target. The same Target again updates in place (no flicker)
--   Wayfinder.hide()                 nothing shows (everything is kept for the next show)
--   Wayfinder.attach(character)      the character the beam starts from (call again after a respawn)
--   Wayfinder.destroy()              remove everything (the Guide has finished)
--   Wayfinder.Pure                   feetY · beamStart · endAnchor · needsBend · chevronSpots · near
--   Spec = { Target: Instance, Base: Vector3?, Icon: string, Color: Color3, Beam: boolean?, Glow: boolean?,
--            Hand: ("Hold" | "Tap")? }
-- Every motion honours Kit.reducedMotion(). Text is never under Theme.TextSize.Caption.

local Players = game:GetService("Players")

local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Wayfinder = {}

export type Spec = {
	Target: Instance,
	Base: Vector3?, -- where the beam ends (the target's base on the floor); worked out from the Target when nil
	Icon: string,
	Color: Color3,
	Beam: boolean?,
	Glow: boolean?,
	Hand: ("Hold" | "Tap")?,
}

-- PURE-BEGIN
-- Numbers only (no Roblox types): tests/TutorialFlow.spec loads this block on its own. First versions (T8 owns them).
local Pure = {}

type Box = { X0: number, X1: number, Z0: number, Z1: number }

-- The floor under a character: its root's centre, less half the root and the hip height (R15: the Humanoid's
-- HipHeight; R6: 2, the legs, with HipHeight 0).
function Pure.feetY(rootY: number, rootHeight: number, hipHeight: number, r6: boolean?): number
	local legs = if r6 then 2 else math.max(hipHeight, 0)
	return rootY - rootHeight / 2 - legs
end

-- Where the beam leaves the body: `lift` above the feet (Config.Tutorial.BeamLift: about the hips).
function Pure.beamStart(feetY: number, lift: number): number
	return feetY + lift
end

-- Where the beam ends: the closest point of the target's footprint to the player, `out` studs outside it.
function Pure.endAnchor(box: Box, fromX: number, fromZ: number, out: number): (number, number)
	local x = math.clamp(fromX, box.X0, box.X1)
	local z = math.clamp(fromZ, box.Z0, box.Z1)
	local dx, dz = fromX - x, fromZ - z
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 1e-6 then
		-- Standing on it: leave by the nearest edge.
		local toX0, toX1, toZ0, toZ1 = fromX - box.X0, box.X1 - fromX, fromZ - box.Z0, box.Z1 - fromZ
		local least = math.min(toX0, toX1, toZ0, toZ1)
		if least == toX0 then
			return box.X0 - out, fromZ
		elseif least == toX1 then
			return box.X1 + out, fromZ
		elseif least == toZ0 then
			return fromX, box.Z0 - out
		end
		return fromX, box.Z1 + out
	end
	return x + dx / length * out, z + dz / length * out
end

-- Whether the straight line from a to b passes through the box (the Counter): then the beam needs a knee.
function Pure.needsBend(ax: number, az: number, bx: number, bz: number, box: Box): boolean
	local dx, dz = bx - ax, bz - az
	local t0, t1 = 0, 1
	for _, edge in { { -dx, ax - box.X0 }, { dx, box.X1 - ax }, { -dz, az - box.Z0 }, { dz, box.Z1 - az } } do
		local p, q = edge[1], edge[2]
		if math.abs(p) < 1e-9 then
			if q < 0 then
				return false
			end
		else
			local t = q / p
			if p < 0 then
				t0 = math.max(t0, t)
			else
				t1 = math.min(t1, t)
			end
			if t0 >= t1 then
				return false
			end
		end
	end
	return true
end

-- How far along a route of `length` studs each floor chevron sits: the first at `first`, then every `gap`, at most
-- `max` of them, none within `near` of the target.
function Pure.chevronSpots(length: number, first: number, gap: number, max: number, near: number?): { number }
	local spots: { number } = {}
	local stop = length - (near or 0)
	local at = first
	while #spots < max and at <= stop and gap > 0 do
		table.insert(spots, at)
		at += gap
	end
	return spots
end

-- The beam and the chevrons hide this close to the target (a flat distance).
function Pure.near(distance: number, nearStuds: number): boolean
	return distance <= nearStuds
end
-- PURE-END

Wayfinder.Pure = Pure

local PIN_STUDS = 3
local PIN_HEIGHT = 5

local pin: BillboardGui? = nil
local pinDisc: Frame? = nil
local pinIcon: TextLabel? = nil
local shown: Instance? = nil
local character: Model? = nil

local function adorneeOf(target: Instance): BasePart?
	if target:IsA("BasePart") then
		return target
	elseif target:IsA("Model") then
		return target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
	end
	return target:FindFirstChildWhichIsA("BasePart", true)
end

local function ensurePin(): (BillboardGui, Frame, TextLabel)
	if pin and pinDisc and pinIcon then
		return pin, pinDisc, pinIcon
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "WayfinderPin"
	gui.Size = UDim2.fromScale(PIN_STUDS, PIN_STUDS)
	gui.StudsOffsetWorldSpace = Vector3.new(0, PIN_HEIGHT, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.ResetOnSpawn = false
	gui.Enabled = false
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.Size = UDim2.fromScale(1, 1)
	disc.BorderSizePixel = 0
	local round = Instance.new("UICorner")
	round.CornerRadius = Theme.Radius.Round
	round.Parent = disc
	Kit.stroke(disc, Theme.Colors.Stroke, Theme.Stroke.Bold)
	disc.Parent = gui
	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.7, 0.7)
	icon.Font = Theme.Font
	icon.TextScaled = true
	icon.Parent = disc
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	pin, pinDisc, pinIcon = gui, disc, icon
	return gui, disc, icon
end

function Wayfinder.show(spec: Spec)
	local gui, disc, icon = ensurePin()
	disc.BackgroundColor3 = spec.Color
	icon.Text = spec.Icon
	if shown ~= spec.Target then
		shown = spec.Target
		gui.Adornee = adorneeOf(spec.Target)
	end
	gui.Enabled = gui.Adornee ~= nil
end

function Wayfinder.hide()
	shown = nil
	if pin then
		pin.Enabled = false
		pin.Adornee = nil
	end
end

-- STUB (T8): the beam's GuideStart attachment goes on this character's HumanoidRootPart.
function Wayfinder.attach(model: Model)
	character = model
end

function Wayfinder.destroy()
	Wayfinder.hide()
	if pin then
		pin:Destroy()
	end
	pin, pinDisc, pinIcon = nil, nil, nil
	character = nil
end

-- For T8: the character `attach` was given (nil before the first attach, and after destroy).
function Wayfinder.character(): Model?
	return character
end

return Wayfinder
