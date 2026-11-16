--!strict
-- The hospital's inside view (look build plan §B6; docs/research/2026-11-16-hospital-building.md §3.7). Client only.
-- OWNER: T3.
-- The upper storeys' outer walls are SOLID now (kids can't walk out of F3), so the camera needs help to look in:
-- while the local character stands inside a plot's building footprint on floor n >= 1, every part with the attribute
-- Storey > n gets LocalTransparencyModifier = 1, and floor n's Outer walls get 0.6 (the camera's Popper ignores a
-- part at 0.25 total transparency or more, so it looks in). The ground floor hides nothing. Nothing replicates.
-- It watches only the local character, only while it is on a building (4 checks a second), and changes things only
-- when the floor changes. Otherwise it sleeps.
--
--   Cutaway.init(ctx)     STUB (T3): does nothing yet
--   Cutaway.Pure          floorOf(y, slabTops) · hide(n, storey, outer): tests/Hospital.spec loads the PURE block

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local Cutaway = {}

-- PURE-BEGIN
-- Numbers only (no Roblox types). First versions (T3 owns them).
local Pure = {}

Pure.CHECKS_PER_SECOND = 4
Pure.FADE = 0.6 -- your own floor's outer walls
Pure.STEP = 0.5 -- standing this far under a slab's top already counts as on it (a hop, a stair's last step)

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
-- PURE-END

Cutaway.Pure = Pure

-- STUB (T3): the watcher goes here.
function Cutaway.init(_ctx: Types.Ctx) end

return Cutaway
