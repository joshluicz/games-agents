--!strict
-- Night lights (look build plan §B4): parts that glow after dark. Server only. Moved from PlotBuilder by the look
-- overhaul's Foundation; the implementation is T1's (the API below is frozen).
--   NightLights.TAG = "ClinicNightLight"       PlotBuilder.NIGHT_LIGHT_TAG re-exports it
--   NightLights.tag(part, kind)                stores the part's DAY Material and Color as the attributes DayMaterial
--                                              (the Material's name) and DayColor, its kind as NightKind, then tags it:
--                                                "Lamp"    Neon + its lights on at night
--                                                "Window"  World.WindowNight colour, SmoothPlastic, NOT Neon
--                                                "Sign"    only its lights turn on
--                                              By day every part goes back to its own DayMaterial and DayColor (a
--                                              studded Plastic part must not come back SmoothPlastic)
--   NightLights.light(part, range): PointLight a lamp's light: shadowless, in World.Lamp, off until night; tags the
--                                              part as a "Lamp" (what PlotBuilder's nightLight did)
--   NightLights.wire()                         once; follows Workspace.IsNight
-- A part another module tagged by hand (CollectionService:AddTag(part, TAG), with no attributes) is a "Lamp" whose
-- day material is SmoothPlastic: exactly what the old code did to every tagged part.
-- No light here ever casts shadows (the perf budget).

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Palette = require(Shared.Palette)

local NightLights = {}

NightLights.TAG = "ClinicNightLight"

export type Kind = "Lamp" | "Window" | "Sign"

function NightLights.tag(p: BasePart, kind: Kind)
	p:SetAttribute("DayMaterial", p.Material.Name)
	p:SetAttribute("DayColor", p.Color)
	p:SetAttribute("NightKind", kind)
	CollectionService:AddTag(p, NightLights.TAG)
end

function NightLights.light(p: BasePart, range: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = Palette.World.Lamp
	light.Brightness = 1.4
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

local function applyNight(instance: Instance, isNight: boolean)
	if not instance:IsA("BasePart") then
		return
	end
	local kind = instance:GetAttribute("NightKind")
	if kind == "Window" then
		local dayColor = instance:GetAttribute("DayColor")
		if isNight then
			instance.Material = Enum.Material.SmoothPlastic
			instance.Color = Palette.World.WindowNight
		else
			instance.Material = dayMaterial(instance)
			if typeof(dayColor) == "Color3" then
				instance.Color = dayColor
			end
		end
	elseif kind ~= "Sign" then
		instance.Material = if isNight then Enum.Material.Neon else dayMaterial(instance)
	end
	for _, child in instance:GetChildren() do
		if child:IsA("Light") then
			child.Enabled = isNight
		end
	end
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
