--!strict
-- The tutorial's world guide (look build plan §B9; docs/research/2026-11-16-tutorial-ux.md §3.2 and §5.3-5.7).
-- Client only, and everything it makes is client-only (nothing replicates). A LIBRARY: nothing runs until `show`,
-- and it has no init. OWNER: T8. UI/Guide draws through it (it picks the targets); UI/Tutorial asks for the nudge.
--
--   Wayfinder.show(spec)             point at spec.Target. The same Target again updates in place (no flicker, no
--                                    re-pop); a new Target re-points everything at once (no tween across)
--   Wayfinder.hide()                 nothing shows and nothing runs (the instances are kept for the next show)
--   Wayfinder.attach(character)      the character the strip starts from (call again after a respawn; show() also
--                                    re-attaches by itself when the old body is gone)
--   Wayfinder.flash(seconds?)        the idle nudge: the strip brightens once (default NUDGE_SECONDS), then fades back
--   Wayfinder.destroy()              remove everything, the Highlight included (the Guide has finished)
--   Wayfinder.character(): Model?    the character `attach` was given
--   Wayfinder.Pure                   the numbers: feetY · beamStart · endAnchor · needsBend · detour · simplify ·
--                                    routeLength · along · chevronSpots · yaw · arrowShape · arrowPlaces · pulse ·
--                                    near · fade · pinOffset (tests/TutorialFlow)
--   Spec = { Target: Instance, Base: Vector3?, Icon: string, Color: Color3, Beam: boolean?, Glow: boolean?,
--            Hand: ("Hold" | "Tap")?, Height: number? }
--     Target   a BasePart or a Model: the glow's Adornee, the pin's anchor and the strip's end
--     Base     where the strip ends, ON the floor (BeamLift is added); nil = worked out from the Target: an optional
--              `GuideAnchor` Attachment under it wins, else the closest point of its footprint to you, 0.3 out
--     Beam     default true: the floor strip and its arrows (false for a patient or a bed: pin and glow only)
--     Glow     default true: the ONE Highlight
--     Hand     touch only: a 👆 pressing beside the target's prompt while that prompt is on screen (PromptShown)
--     Height   the world Y of the pin's foot (default just above the target's top)
--
-- The pieces (§5.4):
--   · the STRIP (the beam; Joshua: "closer to the floor", then 2026-11-17: "the arrows on the ground needs to be
--     improved ... add a arrow to it" and "look at how theyre not correctly connected to the green line"): flat Beams
--     lying ON the floor, BeamLift over it all the way, from under your feet to the target's base. Two layers share
--     each span's attachments: the edges (Width BeamWidth, the guide's colour a shade darker) and the middle on top
--     (Width BeamCoreWidth, a shade lighter, ZOffset CORE_ZOFFSET), so it reads as a path. The middle takes the
--     optional Config.Tutorial.BeamTexture (TextureMode Wrap, TextureLength BeamTextureLength, TextureSpeed BeamSpeed,
--     0 when calm); "" = solid colour. FaceCamera off, CurveSize 0, LightEmission 0, LightInfluence 0, the §5.5 fade.
--     Span 1 starts at GuideStart, an Attachment on the HumanoidRootPart placed at your feet (the rig's own feet:
--     Pure.feetY, held while you're in the air so a jump doesn't lift it), and the last span ends at GuideEnd on
--     Workspace.Terrain. It bends with knees (GuideKnee_<n>In/Out on Terrain, at most BeamMaxSpans spans) along a
--     PathfindingService route (simplified), or round the plot's Counter when no path comes back. Kept flat with the
--     2024 DevForum roll recipe: both ends of each span look at each other and roll 90° / 270°. Span 1 is re-aimed
--     only while the strip shows AND the root moved (two CFrame writes); the other spans only when the route changes
--     (at most every ROUTE_SECONDS, and only after you moved ROUTE_STUDS or the target changed). It hides within
--     NearStuds
--   · the floor ARROWS: at most MaxChevrons chunky flat arrows lying ON the strip, centred on it and facing along it.
--     Each is 6 client-only parts (Pure.arrowShape): a white head (two mirrored WedgeParts lying flat) and shaft (a
--     block), ChevronStuds long and ChevronWidth across the head, over the same shape ARROW_EDGE bigger all round in
--     the guide's colour EDGE_SHADE darker (the outline). Anchored, no collide/query/touch, no shadow. They sit every
--     ChevronGap along the strip's OWN polyline (`polyline`: the strip's spans and the arrows share it, so they can't
--     drift apart), measured back from the target so they stay put as you walk, none within NearStuds of it or
--     FirstChevron of your feet. The ones on span 1 swing with it as you move. They MARCH: a pulse runs along the row
--     toward the target (Pure.pulse: every ChevronPulse seconds, ChevronWave studs apart) and each arrow hops
--     ChevronHop studs forward along the strip as it passes. Still when calm. They hide with the strip
--   · the GLOW: ONE Highlight, re-pointed and never re-made (DepthMode Occluded; fill the target's colour at 0.8, a
--     white outline pulsing 0 <-> 0.35 over GlowSeconds, steady when calm). destroy() deletes it
--   · the PIN: the candy map pin moved here from UI/Guide (a disc in the target's colour on a point, the icon in a
--     white middle). It bobs (still when calm) and drops lower when the camera is within PIN_NEAR_CAMERA studs
--   · the touch HAND (above)
-- Every motion honours Kit.reducedMotion() and re-syncs as soon as Reduce Motion or the calm toggle changes: the
-- strip's texture stops flowing and the arrows stop marching (both still follow you: that's position, not show), the
-- glow holds, the pin and hand stay still.
-- Loops: ONE RenderStepped callback, connected only while something shows (hide() and destroy() disconnect it). Its
-- per-frame work is the near check, span 1's aim when you moved, and the arrows: one Workspace:BulkMoveTo of at most
-- MaxChevrons x 6 parts, every frame while they march, else only when you moved or the route changed. The pin's
-- camera check runs 4 times a second.
-- Text is never under Theme.TextSize.Caption.

local GuiService = game:GetService("GuiService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")) :: any
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Wayfinder = {}

export type Spec = {
	Target: Instance,
	Base: Vector3?, -- where the strip ends (the target's base on the floor); worked out from the Target when nil
	Icon: string,
	Color: Color3,
	Beam: boolean?,
	Glow: boolean?,
	Hand: ("Hold" | "Tap")?,
	Height: number?, -- the world Y of the pin's foot (default: just above the target's top)
}

-- PURE-BEGIN
-- Numbers only (no Roblox types): tests/TutorialFlow.spec loads this block on its own. Points are { X, Z } (or
-- { X, Y, Z }) tables; a box is { X0, X1, Z0, Z1 } in one space (world, or a part's own).
local Pure = {}

type Box = { X0: number, X1: number, Z0: number, Z1: number }
type Point = { X: number, Z: number, Y: number? }
-- One piece of a floor arrow, in the arrow's own flat space: Forward is toward the target, Side to its right.
type Piece = {
	Kind: string, -- "Block" (the shaft), "Left" or "Right" (the head's halves: mirrored wedges, right angle inward)
	Layer: string, -- "Edge" (the outline, underneath) or "Top" (the white arrow)
	Forward: number, -- the piece's centre, studs ahead of the arrow's centre
	Side: number, -- and studs to its right
	Length: number, -- along the route
	Width: number, -- across it
}
type Place = { X: number, Y: number?, Z: number, Yaw: number, ToTarget: number }

Pure.HEAD_SHARE = 0.5 -- an arrow's head is this share of its length
Pure.SHAFT_SHARE = 0.45 -- its shaft is this share of the head's width
Pure.SHAFT_OVERLAP = 0.05 -- the shaft runs this far into the head (no seam)
Pure.HOP_SHARE = 0.3 -- an arrow hops during this share of each pulse and rests the rest

-- The floor under a character: its root's centre, less half the root and the legs (R15: the Humanoid's HipHeight;
-- R6: 2, the legs, whatever HipHeight says).
function Pure.feetY(rootY: number, rootHeight: number, hipHeight: number, r6: boolean?): number
	local legs = if r6 then 2 else math.max(hipHeight, 0)
	return rootY - rootHeight / 2 - legs
end

-- Where the strip lies: `lift` above the floor (Config.Tutorial.BeamLift: just over it, at your feet too).
function Pure.beamStart(feetY: number, lift: number): number
	return feetY + lift
end

-- Where the strip ends: the closest point of the target's footprint to the player, `out` studs outside it.
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

-- Whether the straight line from a to b passes through the box (the Counter): then the strip needs a knee. A line
-- that only touches its edge doesn't count.
function Pure.needsBend(ax: number, az: number, bx: number, bz: number, box: Box): boolean
	local dx, dz = bx - ax, bz - az
	local t0, t1 = 0, 1
	for _, edge in { { -dx, ax - box.X0 }, { dx, box.X1 - ax }, { -dz, az - box.Z0 }, { dz, box.Z1 - az } } do
		local p, q = edge[1], edge[2]
		if math.abs(p) < 1e-9 then
			if q <= 0 then
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

local function grow(box: Box, by: number): Box
	return { X0 = box.X0 - by, X1 = box.X1 + by, Z0 = box.Z0 - by, Z1 = box.Z1 + by }
end

local function dist(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
end

-- The fallback route round one box (the Counter) when no path comes back: no knees when the straight line is clear,
-- else the shortest way round its corners, `margin` studs out (one corner, or two along a side). Knees only.
function Pure.detour(ax: number, az: number, bx: number, bz: number, box: Box, margin: number): { Point }
	if not Pure.needsBend(ax, az, bx, bz, box) then
		return {}
	end
	local outer = grow(box, margin)
	local inner = grow(box, margin * 0.5) -- what a leg must not cross (a leg along the outer edge is fine)
	local corners: { Point } = {
		{ X = outer.X0, Z = outer.Z0 },
		{ X = outer.X1, Z = outer.Z0 },
		{ X = outer.X1, Z = outer.Z1 },
		{ X = outer.X0, Z = outer.Z1 },
	}
	local function clear(p: Point, q: Point): boolean
		return not Pure.needsBend(p.X, p.Z, q.X, q.Z, inner)
	end
	local a: Point, b: Point = { X = ax, Z = az }, { X = bx, Z = bz }
	local best: { Point }? = nil
	local bestLength = math.huge
	for _, c in corners do
		if clear(a, c) and clear(c, b) then
			local length = dist(ax, az, c.X, c.Z) + dist(c.X, c.Z, bx, bz)
			if length < bestLength then
				best, bestLength = { c }, length
			end
		end
	end
	if best then
		return best
	end
	for i, c1 in corners do
		for _, step in { 1, 3 } do -- the two neighbours of corner i
			local c2 = corners[(i - 1 + step) % 4 + 1]
			if clear(a, c1) and clear(c2, b) then
				local length = dist(ax, az, c1.X, c1.Z) + dist(c1.X, c1.Z, c2.X, c2.Z) + dist(c2.X, c2.Z, bx, bz)
				if length < bestLength then
					best, bestLength = { c1, c2 }, length
				end
			end
		end
	end
	return best or {}
end

-- A path's waypoints cut to the few knees the strip needs: Ramer-Douglas-Peucker on the flat plan (a waypoint stays
-- when it sits more than `tolerance` studs off the line), plus any where the floor rises or drops more than `rise`.
-- Returns the INDICES of the kept knees (never the first or last point), at most `maxKnees`, the nearest first.
function Pure.simplify(points: { Point }, tolerance: number, maxKnees: number, rise: number?): { number }
	local n = #points
	if n <= 2 or maxKnees <= 0 then
		return {}
	end
	local keep: { [number]: boolean } = {}
	local function offLine(i: number, a: number, b: number): number
		local p, s, e = points[i], points[a], points[b]
		local dx, dz = e.X - s.X, e.Z - s.Z
		local length = math.sqrt(dx * dx + dz * dz)
		if length < 1e-9 then
			return dist(p.X, p.Z, s.X, s.Z)
		end
		return math.abs((p.X - s.X) * dz - (p.Z - s.Z) * dx) / length
	end
	local stack = { { 1, n } }
	while #stack > 0 do
		local span = table.remove(stack) :: { number }
		local a, b = span[1], span[2]
		local worst, at = 0, 0
		for i = a + 1, b - 1 do
			local d = offLine(i, a, b)
			if d > worst then
				worst, at = d, i
			end
		end
		if at > 0 and worst > tolerance then
			keep[at] = true
			table.insert(stack, { a, at })
			table.insert(stack, { at, b })
		end
	end
	if rise then
		for i = 2, n - 1 do
			local y0, y1 = points[i - 1].Y, points[i].Y
			if type(y0) == "number" and type(y1) == "number" and math.abs(y1 - y0) > rise then
				keep[i] = true
			end
		end
	end
	local out: { number } = {}
	for i = 2, n - 1 do
		if keep[i] and #out < maxKnees then
			table.insert(out, i)
		end
	end
	return out
end

-- The flat length of a route (its points in order).
function Pure.routeLength(points: { Point }): number
	local total = 0
	for i = 2, #points do
		total += dist(points[i - 1].X, points[i - 1].Z, points[i].X, points[i].Z)
	end
	return total
end

-- The point `d` studs along a route and the flat direction there: (x, z, dirX, dirZ, y). y is the height ON the line
-- there when its points carry a Y (nil otherwise).
function Pure.along(points: { Point }, d: number): (number, number, number, number, number?)
	local left = math.max(d, 0)
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local length = dist(a.X, a.Z, b.X, b.Z)
		if length > 1e-9 and (left <= length or i == #points) then
			local t = math.min(left / length, 1)
			local ay, by = a.Y, b.Y
			local y = if ay and by then ay + (by - ay) * t else nil
			return a.X + (b.X - a.X) * t, a.Z + (b.Z - a.Z) * t, (b.X - a.X) / length, (b.Z - a.Z) / length, y
		end
		left -= length
	end
	local last = points[#points]
	return last.X, last.Z, 0, 1, last.Y
end

-- How far along a route of `length` studs each floor arrow sits, nearest you first. They sit every `gap` studs
-- measured back from the target, starting `near` from it (so they stay put as you walk, and none is ever within
-- `near` of it), none closer to your feet than `first`, at most `max` of them (the ones nearest you).
function Pure.chevronSpots(length: number, first: number, gap: number, max: number, near: number?): { number }
	local spots: { number } = {}
	if gap <= 0 or max <= 0 then
		return spots
	end
	local from = length - (near or 0)
	if from < first then
		return spots
	end
	-- The lattice point nearest you that isn't closer than `first`, then walk toward the target.
	local k = math.floor((from - first) / gap)
	while k >= 0 and #spots < max do
		table.insert(spots, from - k * gap)
		k -= 1
	end
	return spots
end

-- The yaw (radians about +Y) that faces a part along the flat direction (dx, dz), as CFrame.lookAt would:
-- CFrame.Angles(0, yaw, 0).LookVector is (-sin yaw, 0, -cos yaw).
function Pure.yaw(dx: number, dz: number): number
	return math.atan2(-dx, -dz)
end

-- A flat arrow's 6 pieces, centred on its middle and pointing Forward: the white Top (a shaft, then a head made of
-- two mirrored right triangles meeting on the centre line) `length` tail to tip and `width` across the head, over
-- the same shape grown by `edge` all round (the Edge: each side of the head moved out by `edge`, so its tip reaches
-- edge / sin(half the tip's angle) further). Edge pieces first (they lie underneath).
function Pure.arrowShape(length: number, width: number, edge: number): { Piece }
	local pieces: { Piece } = {}
	if length <= 0 or width <= 0 then
		return pieces
	end
	local function add(layer: string, tail: number, base: number, head: number, half: number, shaftHalf: number)
		local to = base + Pure.SHAFT_OVERLAP
		table.insert(pieces, {
			Kind = "Block",
			Layer = layer,
			Forward = (tail + to) / 2,
			Side = 0,
			Length = to - tail,
			Width = shaftHalf * 2,
		})
		for _, side in { -1, 1 } do
			table.insert(pieces, {
				Kind = if side < 0 then "Left" else "Right",
				Layer = layer,
				Forward = base + head / 2,
				Side = side * half / 2,
				Length = head,
				Width = half,
			})
		end
	end
	local head = length * Pure.HEAD_SHARE
	local half = width / 2
	local base = length / 2 - head -- where the head starts, ahead of the arrow's centre
	local shaftHalf = half * Pure.SHAFT_SHARE
	local slant = math.sqrt(head * head + half * half)
	local sin, cos = half / slant, head / slant -- of the half-angle at the tip
	local grown = math.max(edge, 0)
	add(
		"Edge",
		-length / 2 - grown,
		base - grown,
		head + grown + grown / sin,
		half * (1 + grown / head) + grown / cos,
		shaftHalf + grown
	)
	add("Top", -length / 2, base, head, half, shaftHalf)
	return pieces
end

-- Where each floor arrow lies: ON the guide's polyline (the SAME points the strip's spans run through), `spots[i]`
-- studs along it plus `shift[i]` (the march's hop; never past the end), at the line's own height, facing along the
-- segment it's on. ToTarget is the unshifted distance left to the end (an arrow's place in the pulse).
function Pure.arrowPlaces(points: { Point }, spots: { number }, shift: { number }?): { Place }
	local length = Pure.routeLength(points)
	local places: { Place } = {}
	for i, d in spots do
		local hop = if shift then shift[i] or 0 else 0
		local x, z, dx, dz, y = Pure.along(points, math.min(d + hop, length))
		table.insert(places, { X = x, Y = y, Z = z, Yaw = Pure.yaw(dx, dz), ToTarget = length - d })
	end
	return places
end

-- The march: how far (0..1 of ChevronHop) the arrow `toTarget` studs from the target has hopped at time `t`. A pulse
-- sets off every `period` seconds, `wave` studs apart along the row, and runs toward the target at wave / period
-- studs a second; each arrow hops forward and back once (a smooth bump over HOP_SHARE of the cycle) as it passes.
function Pure.pulse(t: number, toTarget: number, period: number, wave: number): number
	if period <= 0 or wave <= 0 then
		return 0
	end
	local phase = (t / period + toTarget / wave) % 1
	if phase >= Pure.HOP_SHARE then
		return 0
	end
	return math.sin(math.pi * phase / Pure.HOP_SHARE) ^ 2
end

-- The strip and the arrows hide this close to the target (a flat distance).
function Pure.near(distance: number, nearStuds: number): boolean
	return distance <= nearStuds
end

-- A span's fade (§5.5) as { { time, transparency } }: it fades in under your feet and melts into the glow at the
-- target; the spans between are flat.
function Pure.fade(index: number, count: number): { { number } }
	local first, last = index <= 1, index >= count
	if first and last then
		return { { 0, 1 }, { 0.1, 0.15 }, { 0.9, 0.15 }, { 1, 0.45 } }
	elseif first then
		return { { 0, 1 }, { 0.1, 0.15 }, { 1, 0.15 } }
	elseif last then
		return { { 0, 0.15 }, { 0.9, 0.15 }, { 1, 0.45 } }
	end
	return { { 0, 0.15 }, { 1, 0.15 } }
end

-- The pin's height over its foot: lower when the camera is close, so it stays in frame.
function Pure.pinOffset(cameraDistance: number, nearCamera: number): number
	return if cameraDistance <= nearCamera then 1.2 else 3
end
-- PURE-END

Wayfinder.Pure = Pure

------------------------------------------------------------------------------------------------------------------
-- Tuning (Config.Tutorial owns the strip's and the arrows' numbers; these are this module's own)
------------------------------------------------------------------------------------------------------------------

local TUNE = Config.Tutorial
local ROLL0 = CFrame.Angles(0, 0, math.rad(90)) -- the 2024 DevForum recipe: WorldOrientation += (0, 0, 90)
local ROLL1 = CFrame.Angles(0, 0, math.rad(270)) -- and (0, 0, 270) on the far end
local END_OUT = 0.3 -- the strip ends this far outside the target's footprint
local PATH_OUT = 1.8 -- the path's goal sits this far out (clear of the agent's radius)
local ROUTE_SECONDS = 0.5 -- the route is worked out again at most this often...
local ROUTE_STUDS = 3 -- ...and only once you moved this far (or the target changed)
local KNEE_PASSED = 2 -- closer than this to the first knee: work the route out again now
local SIMPLIFY_STUDS = 1 -- a waypoint this far off the straight line is a knee
local RISE_STUDS = 0.5 -- or where the floor changes this much
local COUNTER_MARGIN = 2.5 -- the fallback bends this far past the Counter
local FLOOR_UP, FLOOR_DOWN = 3, 12 -- a floor ray starts this far above a point and reaches this far
local NEAR_HEIGHT = 6 -- the near-hide also needs you on (about) the target's floor
local PIN_NEAR_CAMERA = 10
local PIN_CHECK_SECONDS = 0.25
local PIN_BOB_PX = 10
local NUDGE_SECONDS = 0.4
-- The strip's two layers.
local BAND_SHADE = 0.25 -- the edges: the guide's colour this much darker
local CORE_LIGHTEN = 0.25 -- the middle: this much lighter
local CORE_ZOFFSET = 0.05 -- the middle draws over the edges
-- The floor arrows (their size and spacing are Config's).
local ARROW_EDGE = 0.18 -- the outline, studs all round
local EDGE_SHADE = 0.45 -- the outline: the guide's colour this much darker (it reads on light tiles and on grass)
local EDGE_UP, EDGE_THICK = 0.06, 0.12 -- the outline layer spans 0 to 0.12 over the strip...
local TOP_UP, TOP_THICK = 0.15, 0.1 -- ...the white arrow 0.1 to 0.2 (no two faces share a plane: no flicker)
local ARROW_WHITE = Color3.new(1, 1, 1)

------------------------------------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------------------------------------

type Route = { Knees: { Vector3 }, Base: Vector3, From: Vector3 }
type Arrow = { Holder: Folder, Parts: { BasePart }, Offsets: { CFrame }, Edges: { BasePart } }

local player = Players.LocalPlayer
local folder: Folder? = nil
local beams: { Beam } = {} -- the strip's edges, one per span
local cores: { Beam } = {} -- its middle, one per span (the same attachments)
local startAttachment: Attachment? = nil
local endAttachment: Attachment? = nil
local kneeIn: { Attachment } = {}
local kneeOut: { Attachment } = {}
local arrows: { Arrow } = {}
local arrowTint: Color3? = nil
local arrowsDirty = false
local marching = false
local bulkParts: { BasePart } = {}
local bulkFrames: { CFrame } = {}
local glow: Highlight? = nil
local glowPulse: Tween? = nil
local marker: BasePart? = nil
local pinGui: BillboardGui? = nil
local pinFrame: Frame? = nil
local pinDisc: Frame? = nil
local pinPoint: Frame? = nil
local pinIcon: TextLabel? = nil
local pinPop: UIScale? = nil
local pinBob: Tween? = nil
local handGui: BillboardGui? = nil
local handIcon: TextLabel? = nil
local handWord: TextLabel? = nil
local handTween: Tween? = nil

local spec: Spec? = nil
local character: Model? = nil
local route: Route? = nil
local routeVersion = 0
local aimedVersion = -1
local lastAim: CFrame? = nil
local groundY: number? = nil
local lastRouteAt = -math.huge
local routing = false
local beamOn = false
local nearNow = false
local pinCheckAt = 0
local flashUntil = 0
local shownPrompts: { [ProximityPrompt]: boolean } = {}
local connections: { RBXScriptConnection } = {}
local loop: RBXScriptConnection? = nil
local pathObject: Path? = nil

local function calm(): boolean
	return Kit.reducedMotion()
end

-- The local player's body (attach() only records it: after a respawn the new body wins at once).
local function rootPart(): (BasePart?, Humanoid?)
	local model = player.Character or character
	if not model then
		return nil, nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return if root and root:IsA("BasePart") then root else nil, humanoid
end

local function feetOf(root: BasePart, humanoid: Humanoid?): number
	local r6 = humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R6
	return Pure.feetY(root.Position.Y, root.Size.Y, if humanoid then humanoid.HipHeight else 2, r6)
end

-- The part a Target stands for: itself, a Model's PrimaryPart, or its first part.
local function partOf(target: Instance): BasePart?
	if target:IsA("BasePart") then
		return target
	elseif target:IsA("Model") then
		return target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
	end
	return target:FindFirstChildWhichIsA("BasePart", true)
end

-- The Target's box: its own CFrame and size (a Model's bounding box).
local function boxOf(target: Instance): (CFrame?, Vector3?)
	if target:IsA("BasePart") then
		return target.CFrame, target.Size
	elseif target:IsA("Model") then
		local ok, cf, size = pcall(function()
			return target:GetBoundingBox()
		end)
		if ok then
			return cf, size
		end
	end
	local part = partOf(target)
	if part then
		return part.CFrame, part.Size
	end
	return nil, nil
end

-- The clinic plot a target sits on (the nearest ancestor Model with an OwnerUserId attribute).
local function plotOf(target: Instance): Instance?
	local node = target.Parent
	while node and node ~= Workspace do
		if node:IsA("Model") and node:GetAttribute("OwnerUserId") ~= nil then
			return node
		end
		node = node.Parent
	end
	return nil
end

------------------------------------------------------------------------------------------------------------------
-- Building the pieces (lazily, once; destroy() throws them away)
------------------------------------------------------------------------------------------------------------------

local function ensureFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "Wayfinder"
	made.Parent = Workspace
	folder = made
	return made
end

local function terrainAttachment(name: string): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Parent = Workspace.Terrain
	return attachment
end

local function sequence(points: { { number } }, override: number?): NumberSequence
	if override then
		return NumberSequence.new(override)
	end
	local keys = {}
	for _, point in points do
		table.insert(keys, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	return NumberSequence.new(keys)
end

-- One layer of one span: flat (FaceCamera off, no curve), unlit. The middle layer takes the optional texture.
local function makeBeam(name: string, width: number, middle: boolean, parent: Instance): Beam
	local beam = Instance.new("Beam")
	beam.Name = name
	beam.FaceCamera = false
	beam.CurveSize0 = 0
	beam.CurveSize1 = 0
	beam.Segments = 10
	beam.Width0 = width
	beam.Width1 = width
	beam.LightEmission = 0
	beam.LightInfluence = 0
	beam.Brightness = 1
	beam.ZOffset = if middle then CORE_ZOFFSET else 0
	if middle then
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureLength = TUNE.BeamTextureLength
		beam.TextureSpeed = TUNE.BeamSpeed
		if type(TUNE.BeamTexture) == "string" and TUNE.BeamTexture ~= "" then
			beam.Texture = TUNE.BeamTexture
		end
	end
	beam.Enabled = false
	beam.Parent = parent
	return beam
end

local function ensureBeams()
	if #beams > 0 and beams[1].Parent then
		return
	end
	table.clear(beams)
	table.clear(cores)
	local parent = ensureFolder()
	endAttachment = terrainAttachment("GuideEnd")
	for n = 1, math.max(TUNE.BeamMaxSpans - 1, 0) do
		kneeIn[n] = terrainAttachment("GuideKnee_" .. n .. "In")
		kneeOut[n] = terrainAttachment("GuideKnee_" .. n .. "Out")
	end
	for n = 1, math.max(TUNE.BeamMaxSpans, 1) do
		beams[n] = makeBeam("GuideBeam_" .. n, TUNE.BeamWidth, false, parent)
		cores[n] = makeBeam("GuideCore_" .. n, TUNE.BeamCoreWidth, true, parent)
	end
end

-- Both layers of every span (the edges and the middle share their attachments).
local function eachLayer(fn: (Beam, number) -> ())
	for n, beam in beams do
		fn(beam, n)
	end
	for n, beam in cores do
		fn(beam, n)
	end
end

-- A floor arrow: the 6 pieces of Pure.arrowShape as client-only parts in their own Folder (parented only while
-- placed). Offsets[i] is part i's CFrame in the arrow's own space (its middle on the strip, looking along it).
local function makeArrow(index: number): Arrow
	local holder = Instance.new("Folder")
	holder.Name = "Arrow_" .. index
	local made: Arrow = { Holder = holder, Parts = {}, Offsets = {}, Edges = {} }
	for _, piece in Pure.arrowShape(TUNE.ChevronStuds, TUNE.ChevronWidth, ARROW_EDGE) do
		local top = piece.Layer == "Top"
		local thick = if top then TOP_THICK else EDGE_THICK
		local at = Vector3.new(piece.Side, if top then TOP_UP else EDGE_UP, -piece.Forward)
		local part: BasePart
		local offset: CFrame
		if piece.Kind == "Block" then
			part = Instance.new("Part")
			part.Size = Vector3.new(piece.Width, thick, piece.Length)
			offset = CFrame.new(at)
		else
			-- Half the head lying flat: a wedge's right angle is its back-bottom edge, so with its own X up (Left) or
			-- down (Right), its Y out to that side and its front along the route, the right angle sits on the
			-- centre line at the head's base and the slope runs from the tip out to that corner.
			part = Instance.new("WedgePart")
			part.Size = Vector3.new(thick, piece.Width, piece.Length)
			offset = if piece.Kind == "Left"
				then CFrame.fromMatrix(at, Vector3.yAxis, -Vector3.xAxis)
				else CFrame.fromMatrix(at, -Vector3.yAxis, Vector3.xAxis)
		end
		part.Name = piece.Layer .. piece.Kind
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Locked = true
		part.Material = Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Color = if top then ARROW_WHITE else (arrowTint or Theme.Colors.Stroke)
		part.Parent = holder
		table.insert(made.Parts, part)
		table.insert(made.Offsets, offset)
		if not top then
			table.insert(made.Edges, part)
		end
	end
	return made
end

-- Made once (each is parented only while placed; destroy() empties the list).
local function ensureArrows()
	if #arrows > 0 then
		return
	end
	for index = 1, math.max(TUNE.MaxChevrons, 0) do
		arrows[index] = makeArrow(index)
	end
end

-- The arrows' outline colour (written only when it changes: show() runs 5 times a second).
local function tintArrows(color: Color3)
	if arrowTint == color then
		return
	end
	arrowTint = color
	for _, arrow in arrows do
		for _, part in arrow.Edges do
			part.Color = color
		end
	end
end

local function hideArrows()
	for _, arrow in arrows do
		if arrow.Holder.Parent ~= nil then
			arrow.Holder.Parent = nil
		end
	end
end

local function ensureGlow(): Highlight
	local existing = glow
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Highlight")
	made.Name = "Glow"
	made.DepthMode = Enum.HighlightDepthMode.Occluded
	made.FillTransparency = 0.8
	made.OutlineColor = Color3.new(1, 1, 1)
	made.OutlineTransparency = 0
	made.Enabled = false
	made.Parent = ensureFolder()
	glow = made
	return made
end

-- The candy map pin (moved from UI/Guide): a round disc on a point, the icon in a white middle. It pops from its tip.
local function ensurePin(): BillboardGui
	local existing = pinGui
	if existing and existing.Parent and marker and marker.Parent then
		return existing
	end
	local part = Instance.new("Part")
	part.Name = "Marker"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.Parent = ensureFolder()
	marker = part

	local gui = Instance.new("BillboardGui")
	gui.Name = "Pin"
	gui.Adornee = part
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 250
	gui.Size = UDim2.fromOffset(84, 118)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = part
	local frame = Instance.new("Frame")
	frame.Name = "Pin"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.fromScale(0.5, 1)
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = frame
	-- The point: a square turned 45° whose lower sides just touch the disc, so the two read as one pin shape.
	local point = Instance.new("Frame")
	point.Name = "Down"
	point.AnchorPoint = Vector2.new(0.5, 0.5)
	point.Position = UDim2.new(0.5, 0, 0, 79)
	point.Size = UDim2.fromOffset(38, 38)
	point.Rotation = 45
	point.BorderSizePixel = 0
	point.ZIndex = 1
	Kit.corner(point, Theme.Radius.Small)
	Kit.stroke(point, Theme.Colors.Stroke, Theme.Stroke.Panel) -- uirules: allow StrokeBudget (the pin: a candy shape in the world)
	point.Parent = frame
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0.5, 0)
	disc.Position = UDim2.new(0.5, 0, 0, 14)
	disc.Size = UDim2.fromOffset(76, 76)
	disc.BorderSizePixel = 0
	disc.ZIndex = 2
	local round = Instance.new("UICorner")
	round.CornerRadius = Theme.Radius.Round
	round.Parent = disc
	Kit.stroke(disc, Theme.Colors.Stroke, Theme.Stroke.Panel) -- uirules: allow StrokeBudget (the pin: a candy shape in the world)
	disc.Parent = frame
	local middle = Instance.new("Frame")
	middle.Name = "Middle"
	middle.AnchorPoint = Vector2.new(0.5, 0.5)
	middle.Position = UDim2.fromScale(0.5, 0.5)
	middle.Size = UDim2.fromScale(0.7, 0.7)
	middle.BackgroundColor3 = Theme.Colors.Paper
	middle.BorderSizePixel = 0
	local middleRound = Instance.new("UICorner")
	middleRound.CornerRadius = Theme.Radius.Round
	middleRound.Parent = middle
	Kit.stroke(middle, Theme.Colors.Stroke, Theme.Stroke.Bold) -- uirules: allow StrokeBudget (the pin: a candy shape in the world)
	middle.Parent = disc
	local icon = Kit.label({
		Name = "Icon",
		Text = "",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.78, 0.78),
		Parent = middle,
	})
	pinGui, pinFrame, pinDisc, pinPoint, pinIcon, pinPop = gui, frame, disc, point, icon, pop
	return gui
end

-- The touch hand: a 👆 beside the target's prompt (touch only), with the word under it when calm.
local function ensureHand(): BillboardGui
	local existing = handGui
	if existing and existing.Parent then
		return existing
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Hand"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 60
	gui.Size = UDim2.fromOffset(72, 96)
	gui.StudsOffset = Vector3.new(2.4, 1.2, 0) -- beside the default prompt (check on the phone emulator)
	gui.Enabled = false
	gui.Parent = ensureFolder()
	local icon = Kit.label({
		Name = "Finger",
		Text = "👆",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(72, 72),
		Parent = gui,
	})
	local word = Kit.label({
		Name = "Word",
		Text = "",
		Outlined = true,
		TextSize = Theme.TextSize.Caption,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(72, 24),
		Visible = false,
		Parent = gui,
	})
	handGui, handIcon, handWord = gui, icon, word
	return gui
end

------------------------------------------------------------------------------------------------------------------
-- Motion (each piece re-syncs when Reduce Motion or the calm toggle changes)
------------------------------------------------------------------------------------------------------------------

local function stopTween(tween: Tween?)
	if tween then
		tween:Cancel()
	end
end

local function syncMotion()
	local still = calm()
	local current = spec
	-- The strip's flow (its middle carries the optional texture).
	for _, beam in cores do
		beam.TextureSpeed = if still then 0 else TUNE.BeamSpeed
	end
	-- The arrows' march: the loop moves them while it's on; settle them once when it stops.
	local march = not still and (tonumber(TUNE.ChevronHop) or 0) > 0
	if march ~= marching then
		marching = march
		arrowsDirty = true
	end
	-- The glow's pulse: only while it shows.
	local light = glow
	local glowing = light ~= nil and light.Enabled
	if (still or not glowing) and glowPulse then
		glowPulse:Cancel()
		glowPulse = nil
		if light then
			light.OutlineTransparency = 0
		end
	elseif not still and glowing and not glowPulse and light then
		light.OutlineTransparency = 0
		glowPulse = TweenService:Create(
			light,
			TweenInfo.new(TUNE.GlowSeconds / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ OutlineTransparency = 0.35 }
		)
		glowPulse:Play()
	end
	-- The pin's bob: only while it shows.
	local frame = pinFrame
	local pinShown = pinGui ~= nil and pinGui.Enabled
	if (still or not pinShown) and pinBob then
		pinBob:Cancel()
		pinBob = nil
		if frame then
			frame.Position = UDim2.fromScale(0.5, 1)
		end
	elseif not still and pinShown and not pinBob and frame then
		frame.Position = UDim2.fromScale(0.5, 1)
		pinBob = TweenService:Create(
			frame,
			TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = UDim2.new(0.5, 0, 1, -PIN_BOB_PX) }
		)
		pinBob:Play()
	end
	-- The hand: presses (Hold: a long press; Tap: quick), or stands still with its word.
	local hand, finger, word = handGui, handIcon, handWord
	local handShown = hand ~= nil and hand.Enabled
	if word then
		word.Visible = still
		word.Text = if current and current.Hand == "Tap" then "TAP" else "HOLD"
	end
	if (still or not handShown) and handTween then
		handTween:Cancel()
		handTween = nil
		if finger then
			finger.Position = UDim2.fromScale(0.5, 0)
		end
	elseif not still and handShown and not handTween and finger then
		local tap = current ~= nil and current.Hand == "Tap"
		finger.Position = UDim2.fromScale(0.5, 0)
		handTween = TweenService:Create(
			finger,
			TweenInfo.new(
				if tap then 0.25 else 0.45,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out,
				-1,
				true,
				if tap then 0.35 else 0.9
			),
			{ Position = UDim2.new(0.5, 0, 0, 10) }
		)
		handTween:Play()
	end
end

------------------------------------------------------------------------------------------------------------------
-- The route, the strip and the arrows
------------------------------------------------------------------------------------------------------------------

local function rayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	local model = player.Character or character
	if model then
		table.insert(exclude, model)
	end
	if folder then
		table.insert(exclude, folder)
	end
	local current = spec
	local plot = if current then plotOf(current.Target) else nil
	local patients = plot and plot:FindFirstChild("Patients")
	if patients then
		table.insert(exclude, patients)
	end
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	return params
end

-- The floor's height under (x, z), looking down from `fromY` + FLOOR_UP (fromY itself when nothing is there).
local function floorAt(x: number, z: number, fromY: number, params: RaycastParams): number
	local hit = Workspace:Raycast(Vector3.new(x, fromY + FLOOR_UP, z), Vector3.new(0, -FLOOR_DOWN, 0), params)
	return if hit then hit.Position.Y else fromY
end

-- Where the strip ends, ON the floor (BeamLift not added yet), seen from `from`; plus the path's goal (further out).
local function baseFor(current: Spec, from: Vector3, params: RaycastParams): (Vector3?, Vector3?)
	if current.Base then
		return current.Base, current.Base
	end
	local target = current.Target
	local anchor = target:FindFirstChild("GuideAnchor")
	if anchor and anchor:IsA("Attachment") then
		local at = anchor.WorldPosition
		local y = floorAt(at.X, at.Z, at.Y, params)
		local spot = Vector3.new(at.X, y, at.Z)
		return spot, spot
	end
	local cf, size = boxOf(target)
	if not (cf and size) then
		return nil, nil
	end
	local localFrom = cf:PointToObjectSpace(from)
	local box = { X0 = -size.X / 2, X1 = size.X / 2, Z0 = -size.Z / 2, Z1 = size.Z / 2 }
	local ex, ez = Pure.endAnchor(box, localFrom.X, localFrom.Z, END_OUT)
	local gx, gz = Pure.endAnchor(box, localFrom.X, localFrom.Z, PATH_OUT)
	local bottom = -size.Y / 2
	local endWorld = cf:PointToWorldSpace(Vector3.new(ex, bottom, ez))
	local goalWorld = cf:PointToWorldSpace(Vector3.new(gx, bottom, gz))
	local endY = floorAt(endWorld.X, endWorld.Z, endWorld.Y, params)
	return Vector3.new(endWorld.X, endY, endWorld.Z), Vector3.new(goalWorld.X, endY, goalWorld.Z)
end

-- The knees a PathfindingService route gives (nil when no path comes back). Yields.
local function pathKnees(from: Vector3, goal: Vector3, params: RaycastParams): { Vector3 }?
	local path = pathObject
	if not path then
		local ok, made = pcall(function()
			return PathfindingService:CreatePath({ AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = false })
		end)
		if not ok or not made then
			return nil
		end
		path = made
		pathObject = made
	end
	local live = path :: Path
	local computed = pcall(function()
		live:ComputeAsync(from, goal)
	end)
	if not computed or live.Status ~= Enum.PathStatus.Success then
		return nil
	end
	local points: { Point } = {}
	for _, waypoint in live:GetWaypoints() do
		local p = waypoint.Position
		table.insert(points, { X = p.X, Y = p.Y, Z = p.Z })
	end
	local knees: { Vector3 } = {}
	for _, index in Pure.simplify(points, SIMPLIFY_STUDS, math.max(TUNE.BeamMaxSpans - 1, 0), RISE_STUDS) do
		local p = points[index]
		local y = floorAt(p.X, p.Z, p.Y or from.Y, params)
		table.insert(knees, Vector3.new(p.X, y, p.Z))
	end
	return knees
end

-- The fallback: straight, or round the plot's Counter (in the Counter's own space, so a turned plot works too).
local function counterKnees(target: Instance, from: Vector3, base: Vector3, params: RaycastParams): { Vector3 }
	local plot = plotOf(target)
	local counter = plot and plot:FindFirstChild("Counter")
	if not (counter and counter:IsA("BasePart")) or counter == target or target:IsDescendantOf(counter) then
		return {}
	end
	local cf, size = counter.CFrame, counter.Size
	local a = cf:PointToObjectSpace(from)
	local b = cf:PointToObjectSpace(base)
	local box = { X0 = -size.X / 2, X1 = size.X / 2, Z0 = -size.Z / 2, Z1 = size.Z / 2 }
	local knees: { Vector3 } = {}
	for _, knee in Pure.detour(a.X, a.Z, b.X, b.Z, box, COUNTER_MARGIN) do
		local world = cf:PointToWorldSpace(Vector3.new(knee.X, -size.Y / 2, knee.Z))
		table.insert(knees, Vector3.new(world.X, floorAt(world.X, world.Z, world.Y, params), world.Z))
	end
	return knees
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

-- Aims one span flat: both ends look at each other and roll (the DevForum 3168420 recipe, in CFrame form).
local function aimSpan(a0: Attachment, p0: Vector3, a1: Attachment, p1: Vector3)
	if flatDistance(p0, p1) < 0.05 then
		return
	end
	a0.WorldCFrame = CFrame.lookAt(p0, p1) * ROLL0
	a1.WorldCFrame = CFrame.lookAt(p1, p0) * ROLL1
end

-- The guide's ONE polyline: `start` (your feet on the floor), the knees, the target's base, each BeamLift over the
-- floor. The strip's spans run through these points and the arrows are placed on them, so the two never part.
local function polyline(current: Route, start: Vector3): { Vector3 }
	local lift = Vector3.new(0, TUNE.BeamLift, 0)
	local points = { start + lift }
	for _, knee in current.Knees do
		table.insert(points, knee + lift)
	end
	table.insert(points, current.Base + lift)
	return points
end

-- The floor arrows on the polyline from `start`: where Pure.arrowPlaces puts them (hopping while they march), every
-- part moved in ONE BulkMoveTo. Arrows with no spot are unparented.
local function placeArrows(current: Route, start: Vector3, now: number)
	ensureArrows()
	local line: { Point } = {}
	for _, p in polyline(current, start) do
		table.insert(line, { X = p.X, Y = p.Y, Z = p.Z })
	end
	local length = Pure.routeLength(line)
	local spots = Pure.chevronSpots(length, TUNE.FirstChevron, TUNE.ChevronGap, #arrows, TUNE.NearStuds)
	local shift: { number }? = nil
	if marching then
		local hops: { number } = {}
		for i, d in spots do
			hops[i] = TUNE.ChevronHop * Pure.pulse(now, length - d, TUNE.ChevronPulse, TUNE.ChevronWave)
		end
		shift = hops
	end
	local places = Pure.arrowPlaces(line, spots, shift)
	local parent = ensureFolder()
	table.clear(bulkParts)
	table.clear(bulkFrames)
	for index, arrow in arrows do
		local place = places[index]
		if place then
			local y = place.Y or (start.Y + TUNE.BeamLift)
			local at = CFrame.new(place.X, y, place.Z) * CFrame.Angles(0, place.Yaw, 0)
			for i, part in arrow.Parts do
				table.insert(bulkParts, part)
				table.insert(bulkFrames, at * arrow.Offsets[i])
			end
			if arrow.Holder.Parent ~= parent then
				arrow.Holder.Parent = parent
			end
		elseif arrow.Holder.Parent ~= nil then
			arrow.Holder.Parent = nil
		end
	end
	if #bulkParts > 0 then
		Workspace:BulkMoveTo(bulkParts, bulkFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	arrowsDirty = false
end

-- Wires the spans for a route: span 1 from GuideStart, then knee to knee, the last into GuideEnd (both layers). The
-- fixed spans are aimed here (once per route); span 1 is aimed by the loop.
local function applyRoute(current: Route)
	ensureBeams()
	local points = polyline(current, current.From)
	local spans = #points - 1
	local start = startAttachment
	local finish = endAttachment
	if not finish then
		return
	end
	eachLayer(function(beam: Beam, n: number)
		if n <= spans then
			beam.Attachment0 = if n == 1 then start else kneeOut[n - 1]
			beam.Attachment1 = if n == spans then finish else kneeIn[n]
			beam.Transparency = sequence(Pure.fade(n, spans))
		else
			beam.Attachment0 = nil
			beam.Attachment1 = nil
			beam.Enabled = false
		end
	end)
	-- Fixed spans: knee n-1's Out end to the next point.
	for n = 2, spans do
		local a0 = kneeOut[n - 1]
		local a1 = if n == spans then finish else kneeIn[n]
		aimSpan(a0, points[n], a1, points[n + 1])
	end
	if spans == 1 then
		finish.WorldCFrame = CFrame.new(points[2])
	end
	routeVersion += 1
end

local function setBeams(on: boolean)
	beamOn = on
	local spans = if route then #(route :: Route).Knees + 1 else 0
	eachLayer(function(beam: Beam, n: number)
		beam.Enabled = on and n <= spans and beam.Attachment0 ~= nil and beam.Attachment1 ~= nil
	end)
	if on then
		arrowsDirty = true -- the loop places them
	else
		hideArrows()
	end
end

-- Works the route out again (in its own thread: pathfinding yields). One at a time; it lands unless the target
-- changed meanwhile. The loop re-aims span 1 and re-places the arrows on the new route (routeVersion moved on).
local function refreshRoute(from: Vector3)
	local current = spec
	if routing or not current then
		return
	end
	routing = true
	lastRouteAt = os.clock()
	task.spawn(function()
		local ok, err = pcall(function()
			local params = rayParams()
			local base, goal = baseFor(current, from, params)
			if not base then
				return
			end
			local knees = pathKnees(from, goal or base, params)
			-- Re-pointed while the path was being worked out? Compare the TARGET, never the table: UI/Guide hands
			-- show() a new spec table every step (5 a second), and the route for the same target is still right.
			local live = spec
			if not live or live.Target ~= current.Target or live.Beam == false then
				return
			end
			if not knees then
				knees = counterKnees(current.Target, from, base, params)
			end
			local made: Route = { Knees = knees, Base = base, From = from }
			route = made
			applyRoute(made)
			if beamOn then
				setBeams(true)
			end
		end)
		routing = false
		if not ok then
			warn("[Wayfinder] route: " .. tostring(err))
		end
	end)
end

------------------------------------------------------------------------------------------------------------------
-- The per-frame callback (only while something shows)
------------------------------------------------------------------------------------------------------------------

local function updatePin(now: number)
	local gui, mark = pinGui, marker
	if not (gui and gui.Enabled and mark) or now < pinCheckAt then
		return
	end
	pinCheckAt = now + PIN_CHECK_SECONDS
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local distance = (camera.CFrame.Position - mark.Position).Magnitude
	local offset = Pure.pinOffset(distance, PIN_NEAR_CAMERA)
	if math.abs(gui.StudsOffset.Y - offset) > 0.01 then
		gui.StudsOffset = Vector3.new(0, offset, 0)
	end
end

local function frame()
	debug.profilebegin("Wayfinder")
	local current = spec
	local now = os.clock()
	updatePin(now)
	local root, humanoid = rootPart()
	if not current or not root then
		if beamOn then
			setBeams(false)
		end
		debug.profileend()
		return
	end
	if not startAttachment or startAttachment.Parent ~= root then
		Wayfinder.attach(root.Parent :: Model)
	end
	-- Your feet on the floor: held while you're in the air, so a jump doesn't lift the strip off it.
	local feet = feetOf(root, humanoid)
	if groundY == nil or humanoid == nil or humanoid.FloorMaterial ~= Enum.Material.Air then
		groundY = feet
	end
	local here = Vector3.new(root.Position.X, groundY or feet, root.Position.Z)
	local made = route
	-- The route: at once for a new target; then at most every ROUTE_SECONDS, once you moved ROUTE_STUDS (or reached
	-- the first knee). Never while you stand at the target (the strip is hidden then anyway).
	if current.Beam ~= false and now - lastRouteAt >= ROUTE_SECONDS and not (made and nearNow) then
		local stale = made == nil
			or flatDistance(here, (made :: Route).From) >= ROUTE_STUDS
			or (#(made :: Route).Knees > 0 and flatDistance(here, (made :: Route).Knees[1]) < KNEE_PASSED)
		if stale then
			refreshRoute(here)
		end
	end
	made = route
	local wantBeam = false
	if current.Beam ~= false and made then
		local base = made.Base
		nearNow = Pure.near(flatDistance(here, base), TUNE.NearStuds) and math.abs(here.Y - base.Y) < NEAR_HEIGHT
		wantBeam = not nearNow
	end
	if wantBeam ~= beamOn then
		setBeams(wantBeam)
	end
	-- Span 1's aim and the arrows: only while the strip shows. Span 1 when the root moved (or the route changed); the
	-- arrows then too (the ones on span 1 swing with it), and every frame while they march.
	local start = startAttachment
	if beamOn and made and start then
		local moved = lastAim == nil or not root.CFrame:FuzzyEq(lastAim :: CFrame, 1e-3) or aimedVersion ~= routeVersion
		if moved then
			local points = polyline(made, here)
			local a1 = if #made.Knees > 0 then kneeIn[1] else endAttachment
			if a1 then
				aimSpan(start, points[1], a1, points[2])
			end
			lastAim = root.CFrame
			aimedVersion = routeVersion
		end
		if moved or marching or arrowsDirty then
			placeArrows(made, here, now)
		end
	end
	-- The nudge's brighter strip, back to its fade when the moment passes.
	if flashUntil > 0 and now >= flashUntil then
		flashUntil = 0
		local spans = if made then #made.Knees + 1 else 1
		eachLayer(function(beam: Beam, n: number)
			beam.Transparency = sequence(Pure.fade(n, spans))
		end)
	end
	debug.profileend()
end

local function connectLoop()
	if not loop then
		loop = RunService.RenderStepped:Connect(frame)
	end
end

local function disconnectLoop()
	local current = loop
	if current then
		loop = nil
		current:Disconnect()
	end
end

-- The hand shows while one of the target's prompts is on screen, touch only.
local function syncHand()
	local current = spec
	local hand = handGui
	if not current or not current.Hand then
		if hand then
			hand.Enabled = false
		end
		return
	end
	local touch = false
	pcall(function()
		touch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
	end)
	local shown = false
	if touch then
		for prompt in shownPrompts do
			if prompt.Parent and prompt:IsDescendantOf(current.Target) then
				shown = true
				break
			end
		end
	end
	if shown then
		local gui = ensureHand()
		gui.Adornee = partOf(current.Target)
		gui.Enabled = gui.Adornee ~= nil
	elseif hand then
		hand.Enabled = false
	end
end

-- Listeners made at the first show (and gone after destroy).
local function listen()
	if #connections > 0 then
		return
	end
	table.insert(connections, GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(syncMotion))
	table.insert(connections, player:GetAttributeChangedSignal("ReduceEffects"):Connect(syncMotion))
	table.insert(
		connections,
		ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
			shownPrompts[prompt] = true
			syncHand()
			syncMotion()
		end)
	)
	table.insert(
		connections,
		ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
			shownPrompts[prompt] = nil
			syncHand()
			syncMotion()
		end)
	)
	pcall(function()
		table.insert(
			connections,
			UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
				syncHand()
				syncMotion()
			end)
		)
	end)
end

------------------------------------------------------------------------------------------------------------------
-- The API
------------------------------------------------------------------------------------------------------------------

function Wayfinder.show(wanted: Spec)
	if typeof(wanted.Target) ~= "Instance" or wanted.Target.Parent == nil then
		Wayfinder.hide()
		return
	end
	listen()
	local previous = spec
	local retarget = previous == nil or previous.Target ~= wanted.Target
	spec = wanted

	-- The pin: over the target's top (or the Height given), its colour and icon.
	local gui = ensurePin()
	local part = partOf(wanted.Target)
	local mark = marker
	if part and mark then
		local cf, size = boxOf(wanted.Target)
		local top = if cf and size then cf.Position.Y + size.Y / 2 else part.Position.Y + part.Size.Y / 2
		local at = if cf then cf.Position else part.Position
		mark.CFrame = CFrame.new(at.X, wanted.Height or (top + 0.3), at.Z)
	end
	local fill = Kit.lighten(wanted.Color, 0.08)
	if pinDisc then
		pinDisc.BackgroundColor3 = fill
	end
	if pinPoint then
		pinPoint.BackgroundColor3 = Kit.shade(fill, 0.13)
	end
	if pinIcon then
		pinIcon.Text = wanted.Icon
	end
	local wasShown = gui.Enabled
	gui.Enabled = part ~= nil
	if retarget or not wasShown then
		local pop = pinPop
		if pop then
			if calm() then
				pop.Scale = 1
			else
				pop.Scale = 0.5
				TweenService:Create(pop, Theme.Tween.Bump, { Scale = 1 }):Play()
			end
		end
		pinCheckAt = 0
	end

	-- The glow: the one Highlight, re-pointed.
	local light = glow
	if wanted.Glow ~= false then
		light = ensureGlow()
		if light.Adornee ~= wanted.Target then
			light.Adornee = wanted.Target
		end
		light.FillColor = wanted.Color
		light.Enabled = true
	elseif light then
		light.Enabled = false
	end

	-- The strip and the arrows: their colours, and a new route at once for a new target.
	if wanted.Beam ~= false then
		ensureBeams()
		local edges = ColorSequence.new(Kit.shade(wanted.Color, BAND_SHADE))
		local middle = ColorSequence.new(Kit.lighten(wanted.Color, CORE_LIGHTEN))
		for _, beam in beams do
			beam.Color = edges
		end
		for _, beam in cores do
			beam.Color = middle
		end
		tintArrows(Kit.shade(wanted.Color, EDGE_SHADE))
		if retarget then
			route = nil
			lastAim = nil
			lastRouteAt = -math.huge -- route now
			nearNow = false
			setBeams(false)
		end
	else
		route = nil
		setBeams(false)
	end

	syncHand()
	syncMotion()
	connectLoop()
end

function Wayfinder.hide()
	spec = nil
	route = nil
	lastAim = nil
	disconnectLoop()
	setBeams(false)
	groundY = nil
	local light, pin, hand = glow, pinGui, handGui
	if light then
		light.Enabled = false
	end
	if pin then
		pin.Enabled = false
	end
	if hand then
		hand.Enabled = false
	end
	syncMotion() -- stops every tween (nothing shows)
end

-- The strip starts from this character's HumanoidRootPart (a new GuideStart; the old one went with the old body).
function Wayfinder.attach(model: Model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	character = model
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		-- Not built yet: try again once it is (show() also re-attaches by itself).
		task.spawn(function()
			local found = model:WaitForChild("HumanoidRootPart", 10)
			if found and character == model and found:IsA("BasePart") then
				Wayfinder.attach(model)
			end
		end)
		return
	end
	local old = startAttachment
	if old and old.Parent == root then
		return
	end
	if old then
		old:Destroy()
	end
	local start = Instance.new("Attachment")
	start.Name = "GuideStart"
	start.Parent = root
	startAttachment = start
	lastAim = nil
	groundY = nil -- the new body's own floor
	if beams[1] and route then
		beams[1].Attachment0 = start
		if cores[1] then
			cores[1].Attachment0 = start
		end
		if beamOn then
			setBeams(true) -- span 1 can show again on the new body
		end
	end
end

-- The idle nudge: the strip brightens for a moment (no motion, so it plays when calm too).
function Wayfinder.flash(seconds: number?)
	if not beamOn then
		return
	end
	eachLayer(function(beam: Beam)
		beam.Transparency = sequence({}, 0)
	end)
	flashUntil = os.clock() + (seconds or NUDGE_SECONDS)
end

function Wayfinder.destroy()
	Wayfinder.hide()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(shownPrompts)
	stopTween(glowPulse)
	stopTween(pinBob)
	stopTween(handTween)
	glowPulse, pinBob, handTween = nil, nil, nil
	local made = folder
	if made then
		made:Destroy() -- the strip, the placed arrows, the Highlight, the pin and the hand
	end
	for _, attachment in { startAttachment, endAttachment } do
		if attachment then
			attachment:Destroy()
		end
	end
	for _, list in { kneeIn, kneeOut } do
		for _, attachment in list do
			attachment:Destroy()
		end
		table.clear(list)
	end
	table.clear(beams)
	table.clear(cores)
	for _, arrow in arrows do
		arrow.Holder:Destroy() -- the ones not placed right now aren't in the folder
	end
	table.clear(arrows)
	table.clear(bulkParts)
	table.clear(bulkFrames)
	arrowTint = nil
	folder, glow, marker, pinGui, pinFrame, pinDisc, pinPoint, pinIcon, pinPop =
		nil, nil, nil, nil, nil, nil, nil, nil, nil
	handGui, handIcon, handWord = nil, nil, nil
	startAttachment, endAttachment = nil, nil
	character = nil
	local path = pathObject
	if path then
		path:Destroy()
	end
	pathObject = nil
	beamOn, nearNow, flashUntil, arrowsDirty, marching = false, false, 0, false, false
end

-- The character `attach` was given (nil before the first attach, and after destroy).
function Wayfinder.character(): Model?
	return character
end

return Wayfinder
