--!strict
-- The studs look (memory-20261117-001 #1; look build plan §B4; docs/research/2026-11-16-art-direction.md §2).
-- Server only. FROZEN after the look overhaul's Foundation: ask the lead for a change.
-- Two ways to stud a part, and the game picks by itself:
--   "Variant"  MaterialService holds a MaterialVariant named Config.Look.StudsVariant ("CureStuds": OUR OWN stud
--              maps, made in Studio once; game/README.md "Studs"). A studded part is Plastic with that variant, so
--              EVERY face is studded: walls, trees, pads.
--   "Surface"  the fallback until that variant exists: Plastic with TopSurface = Studs. Only the TOP face is studded
--              (the built-in studs draw only on Plastic), and every other face is smooth. No assets needed.
-- No Texture, no Decal and no extra part either way.
--
--   Studs.mode(): "Variant" | "Surface"   checked at first use, and again whenever MaterialService gains or loses a
--                                         child (the first switch re-studs the world: Studs.refresh(Workspace))
--   Studs.apply(part)                     stud it (see above) and set the attribute Studded = true: that attribute
--                                         is how the specs and `refresh` find studded parts
--   Studs.smooth(part)                    SmoothPlastic, every surface Smooth, no variant, Studded cleared (roads,
--                                         trim, mattresses)
--   Studs.refresh(root)                   re-applies Studs.apply to every descendant with Studded = true
--   Studs.Pure                            mode(hasVariant) · whole(n) · alignedSize(size)
--
-- THE ALIGNMENT RULE (every builder): a studded part's X and Z sizes are WHOLE studs (Pure.alignedSize), odd widths
-- preferred (a MaterialVariant tiles from the face's centre, the built-in studs from its corner), and it sits on the
-- plot's whole-stud grid. A misaligned seam is the main giveaway: check every one in Studio in both modes.
-- Never call the look by the toy brand's name, in code, docs or the game: it is "studs".

local MaterialService = game:GetService("MaterialService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)

local Studs = {}

export type Mode = "Variant" | "Surface"

-- PURE-BEGIN
-- Numbers and strings only (no Roblox types): tests/Studs.spec loads this block on its own.
local Pure = {}

function Pure.mode(hasVariant: boolean): string
	return if hasVariant then "Variant" else "Surface"
end

-- The nearest whole number of studs, at least 1.
function Pure.whole(n: number): number
	if n ~= n then
		return 1
	end
	return math.max(1, math.floor(n + 0.5))
end

-- A size with X and Z snapped to whole studs (Y is a height: left alone). Takes and returns { X, Y, Z }.
function Pure.alignedSize(size: { X: number, Y: number, Z: number }): { X: number, Y: number, Z: number }
	return { X = Pure.whole(size.X), Y = size.Y, Z = Pure.whole(size.Z) }
end
-- PURE-END

Studs.Pure = Pure

local SURFACES = { "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface" }

local function variantName(): string
	local look = (Config :: any).Look
	return if type(look) == "table" and type(look.StudsVariant) == "string" then look.StudsVariant else "CureStuds"
end

local function hasVariant(): boolean
	local found = MaterialService:FindFirstChild(variantName())
	return found ~= nil and found:IsA("MaterialVariant")
end

local current: Mode? = nil
local watching = false

local function watch()
	if watching then
		return
	end
	watching = true
	local function check()
		local now = Pure.mode(hasVariant()) :: Mode
		if now ~= current then
			current = now
			Studs.refresh(Workspace) -- the variant appeared (or went) mid-session: re-stud what's built
		end
	end
	MaterialService.ChildAdded:Connect(check)
	MaterialService.ChildRemoved:Connect(check)
end

function Studs.mode(): Mode
	if current == nil then
		current = Pure.mode(hasVariant()) :: Mode
		watch()
	end
	return current :: Mode
end

local function smoothFaces(p: BasePart)
	for _, name in SURFACES do
		(p :: any)[name] = Enum.SurfaceType.Smooth
	end
end

function Studs.apply(p: BasePart)
	p.Material = Enum.Material.Plastic
	smoothFaces(p)
	if Studs.mode() == "Variant" then
		p.MaterialVariant = variantName()
	else
		p.MaterialVariant = ""
		p.TopSurface = Enum.SurfaceType.Studs
	end
	p:SetAttribute("Studded", true)
end

function Studs.smooth(p: BasePart)
	p.Material = Enum.Material.SmoothPlastic
	p.MaterialVariant = ""
	smoothFaces(p)
	p:SetAttribute("Studded", nil)
end

function Studs.refresh(root: Instance)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("Studded") == true then
			Studs.apply(descendant)
		end
	end
end

return Studs
