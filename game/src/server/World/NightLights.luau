--!strict
-- Night lights (look build plan §B4, §C1; art-direction §4.3; hospital-building §4.5): parts that glow after dark.
-- Server only. Moved from PlotBuilder by the look overhaul's Foundation; T1 owns the implementation (the API below
-- is frozen).
--   NightLights.TAG = "ClinicNightLight"       PlotBuilder.NIGHT_LIGHT_TAG re-exports it
--   NightLights.tag(part, kind)                stores the part's DAY Material and Color as the attributes DayMaterial
--                                              (the Material's name) and DayColor, its kind as NightKind, then tags it:
--                                                "Lamp"    Neon + its lights on at night (small parts only: the bloom)
--                                                "Window"  World.WindowNight colour, SmoothPlastic, NOT Neon (a warm
--                                                          lit pane that doesn't bloom); its lights on too
--                                                "Sign"    only its lights turn on
--                                              By day every part goes back to its own DayMaterial and DayColor, so a
--                                              studded Plastic part comes back studded Plastic (its MaterialVariant is
--                                              never touched) and Glass comes back Glass
--   NightLights.light(part, range): PointLight a lamp's light: shadowless, warm (World.Lamp), off until night; tags
--                                              the part as a "Lamp"
--   NightLights.wire()                         once; follows Workspace.IsNight
--
-- The day look is read again at each nightfall (the attribute NightLit marks a part that is wearing its night look),
-- so a builder that recolours or re-studs a part AFTER tagging it still gets that part back by day, and a part
-- cloned while lit (NightLit travels with it) comes back by its stored day look. Calling tag() on a lit part keeps
-- the stored day look rather than storing the night one.
-- A part another module tagged by hand (CollectionService:AddTag(part, TAG), with no NightKind) is a "Lamp" whose
-- day material is SmoothPlastic: exactly what the old code did (BoardBuilder, DecorBuilder and Story still tag so).
-- No light here ever casts shadows (the perf budget): every Light under a tagged part is made shadowless whenever
-- it is switched.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Palette = require(Shared.Palette)

local NightLights = {}

NightLights.TAG = "ClinicNightLight"

export type Kind = "Lamp" | "Window" | "Sign"

local LIT = "NightLit" -- the part is wearing its night look now (its day look is in DayMaterial / DayColor)
local LAMP_BRIGHTNESS = 1.4 -- a lamp's PointLight: reads as a warm pool under the darker relit night

function NightLights.tag(p: BasePart, kind: Kind)
	if p:GetAttribute(LIT) ~= true then
		p:SetAttribute("DayMaterial", p.Material.Name)
		p:SetAttribute("DayColor", p.Color)
	end
	p:SetAttribute("NightKind", kind)
	CollectionService:AddTag(p, NightLights.TAG)
end

function NightLights.light(p: BasePart, range: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = Palette.World.Lamp
	light.Brightness = LAMP_BRIGHTNESS
	light.Range = range
	light.Shadows = false
	light.Enabled = false
	light.Parent = p
	NightLights.tag(p, "Lamp")
	return light
end

local function dayMaterial(instance: BasePart): Enum.Material
	local name = instance:GetAttribute("DayMaterial")
	if type(name) == "string" then
		local ok, material = pcall(function()
			return (Enum.Material :: any)[name]
		end)
		if ok and material then
			return material
		end
	end
	return Enum.Material.SmoothPlastic
end

local function switchLights(instance: Instance, isNight: boolean)
	for _, child in instance:GetChildren() do
		if child:IsA("Light") then
			child.Shadows = false
			child.Enabled = isNight
		end
	end
end

-- A part tagged by hand (no NightKind): the old behaviour, untouched. Neon at night, SmoothPlastic by day.
local function applyLegacy(instance: BasePart, isNight: boolean)
	instance.Material = if isNight then Enum.Material.Neon else Enum.Material.SmoothPlastic
end

local function applyNight(instance: Instance, isNight: boolean)
	if not instance:IsA("BasePart") then
		return
	end
	local kind = instance:GetAttribute("NightKind")
	if kind == nil then
		applyLegacy(instance, isNight)
	elseif kind ~= "Sign" then
		local lit = instance:GetAttribute(LIT) == true
		if isNight and not lit then
			-- Nightfall: remember the day look as it is now, then put on the night one.
			instance:SetAttribute("DayMaterial", instance.Material.Name)
			instance:SetAttribute("DayColor", instance.Color)
			if kind == "Window" then
				instance.Material = Enum.Material.SmoothPlastic
				instance.Color = Palette.World.WindowNight
			else
				instance.Material = Enum.Material.Neon
			end
			instance:SetAttribute(LIT, true)
		elseif not isNight and lit then
			-- Morning: the part's own day look back (studs, planks, Glass and its colour).
			instance.Material = dayMaterial(instance)
			local dayColor = instance:GetAttribute("DayColor")
			if typeof(dayColor) == "Color3" then
				instance.Color = dayColor
			end
			instance:SetAttribute(LIT, nil)
		end
	end
	switchLights(instance, isNight)
end

local wired = false
function NightLights.wire()
	if wired then
		return
	end
	wired = true
	local function refresh()
		local isNight = Workspace:GetAttribute("IsNight") == true
		for _, instance in CollectionService:GetTagged(NightLights.TAG) do
			applyNight(instance, isNight)
		end
	end
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(refresh)
	CollectionService:GetInstanceAddedSignal(NightLights.TAG):Connect(function(instance)
		applyNight(instance, Workspace:GetAttribute("IsNight") == true)
	end)
	refresh()
end

return NightLights
