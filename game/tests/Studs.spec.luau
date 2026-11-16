--!nocheck
-- The studs look (Server/World/Studs; look build plan §B4): both modes under tests/worldmock. "Surface" is the
-- fallback (Plastic + TopSurface Studs, top face only) until the CureStuds MaterialVariant exists in MaterialService;
-- "Variant" studs every face. Also the shared look pieces of Server/World/Parts and the night lights' day restore.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local World = require("./worldmock")
local Config = require("./config")
local Enum = World.roblox.Enum
local Vector3 = World.roblox.Vector3
local Color3 = World.roblox.Color3
local UDim2 = World.roblox.UDim2

local SURFACES = { "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface" }

local function loadPure(path: string): any
	local text = fs.readFile(World.find(path))
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to and to > from, path .. ": no PURE block")
	return luau.load(string.sub(text, from, to - 1) .. "\nreturn Pure\n", { debugName = path .. " (pure)" })()
end

local function partIn(world, parent)
	local part = world.new("Part")
	part.Size = Vector3.new(8, 1, 8)
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent or world.Workspace
	return part
end

T.describe("Studs.Pure", function()
	local Pure = loadPure("src/server/World/Studs.luau")

	test("mode: the variant switches it on", function()
		expect(Pure.mode(false)).toBe("Surface")
		expect(Pure.mode(true)).toBe("Variant")
	end)

	test("whole: the nearest whole stud, at least 1", function()
		expect(Pure.whole(4)).toBe(4)
		expect(Pure.whole(4.4)).toBe(4)
		expect(Pure.whole(4.5)).toBe(5)
		expect(Pure.whole(0.2)).toBe(1)
		expect(Pure.whole(0)).toBe(1)
		expect(Pure.whole(-3)).toBe(1)
		expect(Pure.whole(0 / 0)).toBe(1)
	end)

	test("alignedSize: X and Z snap to whole studs, the height is left alone", function()
		expect(Pure.alignedSize({ X = 22.6, Y = 0.6, Z = 13.5 })).toEqual({ X = 23, Y = 0.6, Z = 14 })
		expect(Pure.alignedSize({ X = 0.3, Y = 9, Z = 7 })).toEqual({ X = 1, Y = 9, Z = 7 })
		local size = Vector3.new(69.7, 1, 70.2) -- a Vector3 works too (it has X, Y, Z)
		expect(Pure.alignedSize(size)).toEqual({ X = 70, Y = 1, Z = 70 })
	end)

	test("the variant's name is in Config", function()
		expect(Config.Look.StudsVariant).toBe("CureStuds")
	end)
end)

T.describe("Studs in Surface mode (no MaterialVariant yet)", function()
	local world = World.new()
	local Studs = world.load("src/server/World/Studs.luau")

	test("mode is Surface", function()
		expect(Studs.mode()).toBe("Surface")
	end)

	test("apply: Plastic, studs on the top face only, every other face smooth, no variant, Studded = true", function()
		local part = partIn(world)
		Studs.apply(part)
		expect(part.Material).toBe(Enum.Material.Plastic)
		expect(part.MaterialVariant).toBe("")
		expect(part.TopSurface).toBe(Enum.SurfaceType.Studs)
		for _, name in SURFACES do
			if name ~= "TopSurface" then
				expect(part[name]).toBe(Enum.SurfaceType.Smooth)
			end
		end
		expect(part:GetAttribute("Studded")).toBe(true)
	end)

	test("smooth: SmoothPlastic, every face smooth, no variant, Studded cleared", function()
		local part = partIn(world)
		Studs.apply(part)
		Studs.smooth(part)
		expect(part.Material).toBe(Enum.Material.SmoothPlastic)
		expect(part.MaterialVariant).toBe("")
		for _, name in SURFACES do
			expect(part[name]).toBe(Enum.SurfaceType.Smooth)
		end
		expect(part:GetAttribute("Studded")).toBeNil()
	end)

	test("no Texture, Decal or extra part is ever added", function()
		local part = partIn(world)
		Studs.apply(part)
		expect(#part:GetChildren()).toBe(0)
	end)
end)

T.describe("Studs in Variant mode (CureStuds exists)", function()
	local world = World.new()
	world.setVariant(true)
	local Studs = world.load("src/server/World/Studs.luau")

	test("mode is Variant", function()
		expect(Studs.mode()).toBe("Variant")
	end)

	test("apply: Plastic + the variant on EVERY face (no legacy top studs), Studded = true", function()
		local part = partIn(world)
		Studs.apply(part)
		expect(part.Material).toBe(Enum.Material.Plastic)
		expect(part.MaterialVariant).toBe(Config.Look.StudsVariant)
		for _, name in SURFACES do
			expect(part[name]).toBe(Enum.SurfaceType.Smooth)
		end
		expect(part:GetAttribute("Studded")).toBe(true)
		expect(#part:GetChildren()).toBe(0)
	end)

	test("smooth clears the variant", function()
		local part = partIn(world)
		Studs.apply(part)
		Studs.smooth(part)
		expect(part.Material).toBe(Enum.Material.SmoothPlastic)
		expect(part.MaterialVariant).toBe("")
	end)

	test("something else in MaterialService with that name isn't a variant", function()
		local other = World.new()
		local folder = other.new("Folder")
		folder.Name = Config.Look.StudsVariant
		folder.Parent = other.MaterialService
		expect(other.load("src/server/World/Studs.luau").mode()).toBe("Surface")
	end)
end)

T.describe("Studs.refresh: the variant appears mid-session", function()
	test("refresh re-applies to studded parts only", function()
		local world = World.new()
		local Studs = world.load("src/server/World/Studs.luau")
		local model = world.new("Model")
		model.Parent = world.Workspace
		local studded, plain = partIn(world, model), partIn(world, model)
		Studs.apply(studded)
		studded.TopSurface = Enum.SurfaceType.Smooth -- something undid it
		Studs.refresh(model)
		expect(studded.TopSurface).toBe(Enum.SurfaceType.Studs)
		expect(plain.Material).toBe(Enum.Material.SmoothPlastic)
		expect(plain.TopSurface).toBeNil() -- never touched
	end)

	test(
		"adding the MaterialVariant switches a running server: every studded part in Workspace is re-studded",
		function()
			local world = World.new()
			local Studs = world.load("src/server/World/Studs.luau")
			local lawn, road = partIn(world), partIn(world)
			Studs.apply(lawn)
			Studs.smooth(road)
			expect(Studs.mode()).toBe("Surface")
			expect(lawn.TopSurface).toBe(Enum.SurfaceType.Studs)

			world.setVariant(true)
			expect(Studs.mode()).toBe("Variant")
			expect(lawn.MaterialVariant).toBe(Config.Look.StudsVariant)
			expect(lawn.TopSurface).toBe(Enum.SurfaceType.Smooth)
			expect(road.Material).toBe(Enum.Material.SmoothPlastic)
			expect(road.MaterialVariant).toBe("")

			world.setVariant(false) -- and back, if it is ever removed
			expect(Studs.mode()).toBe("Surface")
			expect(lawn.MaterialVariant).toBe("")
			expect(lawn.TopSurface).toBe(Enum.SurfaceType.Studs)
		end
	)
end)

T.describe("World/Parts: the shared look pieces", function()
	local world = World.new()
	local Parts = world.load("src/server/World/Parts.luau")
	local Palette = world.load("src/shared/Palette.luau")

	local function count(root, class)
		local n = 0
		for _, d in root:GetDescendants() do
			if d.ClassName == class then
				n += 1
			end
		end
		return n
	end

	test("the moved helpers keep their defaults", function()
		local model = world.new("Model")
		local p = Parts.part(model, "Thing", Vector3.new(2, 3, 4), World.roblox.CFrame.new(), Color3.new(1, 0, 0))
		expect(p.Anchored).toBe(true)
		expect(p.Material).toBe(Enum.Material.SmoothPlastic)
		expect(p.Parent).toBe(model)
		Parts.soft(p)
		expect({ p.CanCollide, p.CanQuery, p.CanTouch }).toEqual({ false, false, false })
		local m = Parts.marker(model, "Spot", World.roblox.CFrame.new())
		expect({ m.Transparency, m.CanCollide, m.CastShadow }).toEqual({ 1, false, false })
		expect(m.Size).toEqual(Vector3.new(2, 1, 2))
		local gui = Parts.surface(p, "Gui", Enum.NormalId.Front, 20)
		expect({ gui.PixelsPerStud, gui.MaxDistance, gui.LightInfluence }).toEqual({ 20, Parts.DETAIL_NEAR, 1 })
		local bright = Parts.surface(p, "Bright", Enum.NormalId.Top, 12, 400, 0)
		expect({ bright.MaxDistance, bright.LightInfluence }).toEqual({ 400, 0 })
		expect(Parts.wedge(model, "Ramp", Vector3.new(1, 1, 1), World.roblox.CFrame.new(), Color3.new()).ClassName).toBe(
			"WedgePart"
		)
	end)

	test("floatText: no board; white (or gold) display text with a 3.5 px ink stroke; an optional shadow", function()
		local gui = world.new("SurfaceGui")
		local label = Parts.floatText(gui, "Cozy Ward")
		expect(label.BackgroundTransparency).toBe(1)
		expect(label.Text).toBe("Cozy Ward")
		expect(label.Font).toBe(Palette.DisplayFont)
		expect(label.TextColor3).toEqual(Color3.new(1, 1, 1))
		local stroke = label:FindFirstChild("TextOutline")
		expect(stroke.Thickness).toBe(3.5)
		expect(stroke.Color).toEqual(Palette.Outline)
		expect(#gui:GetChildren()).toBe(1) -- just the text: nothing behind it
		expect(count(gui, "Frame")).toBe(0)

		local gold = world.new("BillboardGui")
		local title =
			Parts.floatText(gold, "🎲 NURSE ODDS", { Gold = true, Shadow = true, Size = UDim2.fromScale(1, 0.2) })
		expect(title.TextColor3).toEqual(Palette.Gold)
		expect(title.Size).toEqual(UDim2.fromScale(1, 0.2))
		local shadow = gold:FindFirstChild("TextShadow")
		expect(shadow.TextColor3).toEqual(Palette.Outline)
		expect(shadow.TextTransparency).toBe(0.5)
		expect(shadow.Position.Y.Offset).toBe(2) -- 2 px lower
		expect(shadow.ZIndex < title.ZIndex).toBe(true)
		expect(count(gold, "Frame")).toBe(0)
	end)

	test("navyPlate: navy at 0.15, a 4 px ink stroke, a large radius", function()
		local gui = world.new("SurfaceGui")
		local plate = Parts.navyPlate(gui)
		expect(plate.BackgroundColor3).toEqual(Palette.Navy)
		expect(plate.BackgroundTransparency).toBe(0.15)
		expect(plate:FindFirstChild("ShapeOutline").Thickness).toBe(4)
		expect(plate:FindFirstChild("ShapeOutline").Color).toEqual(Palette.Outline)
		expect(plate:FindFirstChildOfClass("UICorner").CornerRadius.Offset).toBe(22)
		expect(plate.Parent).toBe(gui)
	end)

	test("pawHeart: our own mark in at most 8 Frames, no images, no cross", function()
		local gui = world.new("SurfaceGui")
		local holder = world.new("Frame")
		holder.Parent = gui
		local mark = Parts.pawHeart(holder, UDim2.fromScale(0.8, 0.8), Palette.Accent.Pink)
		expect(mark.Name).toBe("PawHeart")
		expect(mark.Parent).toBe(holder)
		expect(mark.Size).toEqual(UDim2.fromScale(0.8, 0.8))
		expect(count(holder, "Frame") <= 8).toBe(true)
		expect(count(holder, "ImageLabel") + count(holder, "ImageButton") + count(holder, "Decal")).toBe(0)
		-- the rim is the warm white, never pure white; the heart wears the given colour; the pads are white
		expect(mark.BackgroundColor3).toEqual(Palette.World.Trim)
		local hearts, pads = 0, 0
		for _, d in mark:GetDescendants() do
			if d.ClassName == "Frame" then
				expect(string.find(d.Name, "Cross") == nil).toBe(true)
				if d.BackgroundColor3 == Palette.Accent.Pink then
					hearts += 1
				elseif d.BackgroundColor3 == Color3.new(1, 1, 1) then
					pads += 1
				end
			end
		end
		expect(hearts).toBe(3) -- two discs and a turned square
		expect(pads).toBe(4) -- three toes and one main pad
	end)
end)

T.describe("World/NightLights: day materials survive the night", function()
	test("a studded Lamp goes Neon at night and comes back studded Plastic by day", function()
		local world = World.new()
		local Studs = world.load("src/server/World/Studs.luau")
		local NightLights = world.load("src/server/World/NightLights.luau")
		NightLights.wire()
		local part = partIn(world)
		Studs.apply(part)
		NightLights.tag(part, "Lamp")
		expect(part:GetAttribute("DayMaterial")).toBe("Plastic")
		world.setNight(true)
		expect(part.Material).toBe(Enum.Material.Neon)
		world.setNight(false)
		expect(part.Material).toBe(Enum.Material.Plastic)
		expect(part.TopSurface).toBe(Enum.SurfaceType.Studs)
	end)

	test("a Window turns warm (not Neon) at night and gets its day colour back; a Sign only lights up", function()
		local world = World.new()
		local NightLights = world.load("src/server/World/NightLights.luau")
		local Palette = world.load("src/shared/Palette.luau")
		NightLights.wire()
		local window, sign = partIn(world), partIn(world)
		window.Color = Palette.World.Window
		sign.Color = Color3.new(0.2, 0.4, 0.6)
		local light = world.new("PointLight")
		light.Enabled = false
		light.Parent = sign
		NightLights.tag(window, "Window")
		NightLights.tag(sign, "Sign")

		world.setNight(true)
		expect(window.Color).toEqual(Palette.World.WindowNight)
		expect(window.Material == Enum.Material.Neon).toBe(false)
		expect(sign.Material).toBe(Enum.Material.SmoothPlastic)
		expect(sign.Color).toEqual(Color3.new(0.2, 0.4, 0.6))
		expect(light.Enabled).toBe(true)

		world.setNight(false)
		expect(window.Color).toEqual(Palette.World.Window)
		expect(light.Enabled).toBe(false)
	end)

	test("light(): a shadowless lamp light, off until night; a part tagged by hand is a SmoothPlastic lamp", function()
		local world = World.new()
		local NightLights = world.load("src/server/World/NightLights.luau")
		NightLights.wire()
		local head = partIn(world)
		local light = NightLights.light(head, 18)
		expect({ light.Shadows, light.Enabled, light.Range }).toEqual({ false, false, 18 })
		local legacy = partIn(world)
		legacy.Material = Enum.Material.Plastic
		legacy:AddTag(NightLights.TAG) -- what BoardBuilder, DecorBuilder and Story still do
		world.setNight(true)
		expect(light.Enabled).toBe(true)
		expect(head.Material).toBe(Enum.Material.Neon)
		expect(legacy.Material).toBe(Enum.Material.Neon)
		world.setNight(false)
		expect(legacy.Material).toBe(Enum.Material.SmoothPlastic) -- exactly what the old code did
		expect(NightLights.TAG).toBe("ClinicNightLight")
	end)

	test("no night light casts shadows", function()
		local world = World.new()
		local PlotBuilder = world.load("src/server/PlotBuilder.luau")
		PlotBuilder.buildTown()
		local lights = 0
		for _, d in world.Workspace:GetDescendants() do
			if d:IsA("Light") then
				lights += 1
				expect(d.Shadows).toBe(false)
			end
		end
		expect(lights > 0).toBe(true)
	end)
end)
