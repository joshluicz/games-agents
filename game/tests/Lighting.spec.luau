--!nocheck
-- The relight (Server/DayNight and Server/World/NightLights; look build plan §C1, §D T1; art-direction §4.3).
--   1. DayNight.Pure: the Look tables match §C1, every key is a real property of its instance (Lune's roblox
--      reflection rejects a typo or a wrong type), and the night is never brighter than the day.
--   2. DayNight.start() for real, against Lune's own Lighting instance: the enum settings, the effects it finds or
--      makes (CandyColor, Atmosphere, Bloom, CureRays; no Clouds; depth of field off), then the phase loop with
--      SkipPhase: day -> night -> Day Report -> day, each look landing on every instance.
--   3. NightLights: the day look survives the night (studs in both modes, Glass, colours set after tagging, parts
--      tagged at night), no light casts shadows, and the whole built world comes back exactly by morning.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local T = require("./expect")
local expect, test = T.expect, T.test

local World = require("./worldmock")
local Config = require("./config")
local Look = require("./look")

local Enum, Color3, Vector3 = roblox.Enum, roblox.Color3, roblox.Vector3

local DAY_NIGHT = "src/server/DayNight.luau"
local NIGHT_LIGHTS = "src/server/World/NightLights.luau"

local function loadPure(path: string): any
	local text = fs.readFile(World.find(path))
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to and to > from, path .. ": no PURE block")
	return luau.load(string.sub(text, from, to - 1) .. "\nreturn Pure\n", { debugName = path .. " (pure)" })()
end

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function asColor(t)
	return { R = t[1] / 255, G = t[2] / 255, B = t[3] / 255 }
end

-- Look table key -> the class its properties belong to.
local CLASSES = {
	Lighting = "Lighting",
	ColorCorrection = "ColorCorrectionEffect",
	Atmosphere = "Atmosphere",
	Bloom = "BloomEffect",
	SunRays = "SunRaysEffect",
}

-- Every property of `plain` (a Pure look's table) on `instance`, within float32 rounding.
local function expectLook(instance, plain, what)
	for key, value in plain do
		local actual = instance[key]
		if type(value) == "table" then
			local want = rgb(value)
			for _, channel in { "R", "G", "B" } do
				if math.abs(actual[channel] - want[channel]) > 1e-4 then
					error(what .. "." .. key .. ": expected " .. tostring(want) .. ", got " .. tostring(actual), 2)
				end
			end
		elseif math.abs(actual - value) > 1e-4 then
			error(what .. "." .. key .. ": expected " .. tostring(value) .. ", got " .. tostring(actual), 2)
		end
	end
end

------------------------------------------------------------------------------------------------------------------
-- 1. The Look tables
------------------------------------------------------------------------------------------------------------------

T.describe("DayNight.Pure: the Look tables (§C1)", function()
	local Pure = loadPure(DAY_NIGHT)

	test("the day table is §C1's day column", function()
		expect(Pure.DAY).toEqual({
			Lighting = {
				Brightness = 2.25,
				ExposureCompensation = 0,
				Ambient = { 70, 68, 84 },
				OutdoorAmbient = { 128, 128, 140 },
				EnvironmentDiffuseScale = 0.6,
				EnvironmentSpecularScale = 0.15,
				ShadowSoftness = 0.15,
			},
			ColorCorrection = { Brightness = 0, Contrast = 0.12, Saturation = 0.08, TintColor = { 255, 251, 244 } },
			Atmosphere = {
				Density = 0.26,
				Offset = 0.15,
				Color = { 150, 198, 240 },
				Decay = { 104, 150, 214 },
				Haze = 0,
				Glare = 0,
			},
			Bloom = { Intensity = 0.25, Size = 20, Threshold = 2 },
			SunRays = { Intensity = 0.04, Spread = 0.45 },
		})
	end)

	test("the night table is §C1's night column", function()
		expect(Pure.NIGHT).toEqual({
			Lighting = {
				Brightness = 1.0,
				ExposureCompensation = 0,
				Ambient = { 54, 44, 110 },
				OutdoorAmbient = { 82, 68, 150 },
				EnvironmentDiffuseScale = 0.4,
				EnvironmentSpecularScale = 0.15,
				ShadowSoftness = 0.15,
			},
			ColorCorrection = { Brightness = 0, Contrast = 0.15, Saturation = 0.05, TintColor = { 222, 214, 255 } },
			Atmosphere = {
				Density = 0.32,
				Offset = 0.12,
				Color = { 74, 64, 152 },
				Decay = { 40, 32, 104 },
				Haze = 0,
				Glare = 0,
			},
			Bloom = { Intensity = 0.6, Size = 24, Threshold = 1.3 },
			SunRays = { Intensity = 0, Spread = 0 },
		})
	end)

	test("day and night set the same properties, and every one is a real property of its instance", function()
		for _, look in { Pure.DAY, Pure.NIGHT } do
			for group, class in CLASSES do
				expect(type(look[group])).toBe("table")
				local instance = roblox.Instance.new(class)
				for key, value in look[group] do
					local ok, err = pcall(function()
						instance[key] = if type(value) == "table" then rgb(value) else value
					end)
					if not ok then
						error(class .. "." .. key .. ": " .. tostring(err))
					end
				end
			end
			local groups = 0
			for _ in look do
				groups += 1
			end
			expect(groups).toBe(5)
		end
		for group in CLASSES do
			local dayKeys, nightKeys = {}, {}
			for key in Pure.DAY[group] do
				dayKeys[key] = true
			end
			for key in Pure.NIGHT[group] do
				nightKeys[key] = true
			end
			expect(dayKeys).toEqual(nightKeys)
		end
	end)

	test("every colour is three whole numbers in 0..255", function()
		for _, look in { Pure.DAY, Pure.NIGHT } do
			for _, group in look do
				for _, value in group do
					if type(value) == "table" then
						expect(#value).toBe(3)
						for _, channel in value do
							expect(channel == math.floor(channel) and channel >= 0 and channel <= 255).toBe(true)
						end
					end
				end
			end
		end
	end)

	test("night is never brighter than day: Brightness, Ambient, OutdoorAmbient (by luma)", function()
		local day, night = Pure.DAY.Lighting, Pure.NIGHT.Lighting
		expect(night.Brightness <= day.Brightness).toBe(true)
		for _, key in { "Ambient", "OutdoorAmbient" } do
			expect(Look.luma(asColor(night[key])) <= Look.luma(asColor(day[key]))).toBe(true)
			expect(Pure.luma(night[key])).toBeCloseTo(Look.luma(asColor(night[key])), 6) -- one luma, everywhere
		end
		expect(night.EnvironmentDiffuseScale <= day.EnvironmentDiffuseScale).toBe(true)
		expect(Pure.nightTooBright(Pure.DAY, Pure.NIGHT)).toEqual({})
	end)

	test("nightTooBright names whatever a bad tune makes brighter at night", function()
		local night = table.clone(Pure.NIGHT)
		night.Lighting = table.clone(Pure.NIGHT.Lighting)
		night.SunRays = { Intensity = 0.1, Spread = 0.4 }
		night.Lighting.Brightness = 3
		night.Lighting.OutdoorAmbient = { 200, 200, 200 }
		expect(Pure.nightTooBright(Pure.DAY, night)).toEqual({ "Brightness", "OutdoorAmbient", "SunRays.Intensity" })
	end)

	test("the night's Bloom threshold is lower than the day's (lamps and Neon tips glow), and stronger", function()
		expect(Pure.NIGHT.Bloom.Threshold < Pure.DAY.Bloom.Threshold).toBe(true)
		expect(Pure.NIGHT.Bloom.Intensity > Pure.DAY.Bloom.Intensity).toBe(true)
		expect(Pure.DAY.Bloom.Threshold >= 2).toBe(true) -- by day only Neon blooms
	end)

	test("the night has a violet cast: blue is the strongest channel of its fills and its air", function()
		for _, value in { Pure.NIGHT.Lighting.Ambient, Pure.NIGHT.Lighting.OutdoorAmbient, Pure.NIGHT.Atmosphere.Color } do
			expect(value[3] > value[1] and value[3] > value[2]).toBe(true)
		end
	end)

	test("no lerp to white: the grade never lifts, the air stays crisp, the sun rays sleep at night", function()
		for _, look in { Pure.DAY, Pure.NIGHT } do
			expect(look.ColorCorrection.Brightness).toBe(0)
			expect(look.Lighting.ExposureCompensation).toBe(0)
			expect(look.Atmosphere.Haze).toBe(0)
			expect(look.Atmosphere.Glare).toBe(0)
		end
		expect(Look.maxChannel(asColor(Pure.DAY.Atmosphere.Color)) <= 240).toBe(true) -- mid-blue, not milk
		expect(Pure.NIGHT.SunRays.Intensity).toBe(0)
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- 2. DayNight.start() and the phase loop, against Lune's real Lighting instance
------------------------------------------------------------------------------------------------------------------

-- Loads the shipped DayNight with Lune's Lighting (real properties), a Workspace with attributes, a TweenService
-- that applies at once, and stubs for Remotes, DayReport and task (task.spawn records; task.wait yields).
local function bootDayNight(prepare: ((any) -> ())?)
	local lighting = roblox.Instance.new("Lighting")
	lighting.ClockTime = 14
	if prepare then
		prepare(lighting)
	end
	local attrs = {}
	local workspace = {
		SetAttribute = function(_, key, value)
			attrs[key] = value
		end,
		GetAttribute = function(_, key)
			return attrs[key]
		end,
		GetServerTimeNow = function()
			return 1000
		end,
	}
	local rig = { Lighting = lighting, Workspace = workspace, Attrs = attrs, Toasts = {}, Flushes = 0 }
	rig.Spawned = {}
	rig.Tweens = 0
	rig.Warnings = {}
	local tweenService = {
		Create = function(_, instance, _info, props)
			return {
				Play = function()
					rig.Tweens += 1
					for key, value in props do
						instance[key] = value
					end
				end,
			}
		end,
		GetValue = function(_, alpha)
			return alpha
		end,
	}
	local services = { Lighting = lighting, TweenService = tweenService, Workspace = workspace }
	local modules = {
		Config = Config,
		Remotes = {
			toastAll = function(text)
				table.insert(rig.Toasts, text)
			end,
		},
		DayReport = {
			flush = function()
				rig.Flushes += 1
			end,
		},
	}
	local env = {
		game = {
			GetService = function(_, name)
				if name == "ReplicatedStorage" then
					return { Shared = { Config = "Config", Remotes = "Remotes" } }
				end
				return services[name]
			end,
		},
		script = { Parent = { DayReport = "DayReport" } },
		require = function(name)
			return modules[name]
		end,
		Instance = roblox.Instance,
		Enum = Enum,
		Color3 = Color3,
		TweenInfo = {
			new = function(...)
				return { ... }
			end,
		},
		task = {
			spawn = function(fn)
				table.insert(rig.Spawned, fn)
			end,
			wait = function()
				coroutine.yield()
			end,
		},
		warn = function(...)
			table.insert(rig.Warnings, table.concat({ ... }, " "))
		end,
	}
	local source = fs.readFile(World.find(DAY_NIGHT))
	local DayNight = luau.load(source, { debugName = DAY_NIGHT, environment = env, injectGlobals = true })()
	rig.DayNight = DayNight
	DayNight.start()
	-- The first thing start() spawns is the phase loop (each sweepClock spawns one more: not run here).
	local loop = coroutine.create(rig.Spawned[1])
	function rig.step()
		local ok, err = coroutine.resume(loop)
		assert(ok, err)
	end
	function rig.skip()
		attrs.SkipPhase = true
		rig.step()
	end
	function rig.effects()
		return {
			ColorCorrection = lighting:FindFirstChild("CandyColor"),
			Atmosphere = lighting:FindFirstChildOfClass("Atmosphere"),
			Bloom = lighting:FindFirstChildOfClass("BloomEffect"),
			SunRays = lighting:FindFirstChildOfClass("SunRaysEffect"),
		}
	end
	function rig.expectLook(plain)
		expectLook(lighting, plain.Lighting, "Lighting")
		for group, effect in rig.effects() do
			expectLook(effect, plain[group], group)
		end
	end
	return rig
end

local function countClass(root, class)
	local n = 0
	for _, d in root:GetDescendants() do
		if d.ClassName == class then
			n += 1
		end
	end
	return n
end

T.describe("DayNight.start(): the relight, once and on every phase", function()
	local Pure = loadPure(DAY_NIGHT)

	test("start() sets LightingStyle Soft, PrioritizeLightingQuality, GlobalShadows and black ColorShifts", function()
		local rig = bootDayNight(function(lighting)
			lighting.LightingStyle = Enum.LightingStyle.Realistic
			lighting.PrioritizeLightingQuality = false
			lighting.GlobalShadows = false
			lighting.ColorShift_Top = Color3.fromRGB(255, 200, 100)
			lighting.ColorShift_Bottom = Color3.fromRGB(40, 40, 80)
		end)
		local lighting = rig.Lighting
		expect(lighting.LightingStyle).toBe(Enum.LightingStyle.Soft)
		expect(lighting.PrioritizeLightingQuality).toBe(true)
		expect(lighting.GlobalShadows).toBe(true)
		expect(lighting.ColorShift_Top).toEqual(Color3.new(0, 0, 0))
		expect(lighting.ColorShift_Bottom).toEqual(Color3.new(0, 0, 0))
		expect(rig.Warnings).toEqual({})
	end)

	test(
		"start() makes CandyColor, an Atmosphere, a Bloom and CureRays, all on; no Clouds; the day look at once",
		function()
			local rig = bootDayNight()
			local lighting = rig.Lighting
			local effects = rig.effects()
			expect(effects.ColorCorrection.ClassName).toBe("ColorCorrectionEffect")
			expect(effects.ColorCorrection.Enabled).toBe(true)
			expect(effects.Bloom.Enabled).toBe(true)
			expect(effects.SunRays.Name).toBe("CureRays")
			expect(effects.SunRays.Enabled).toBe(true)
			expect(effects.Atmosphere).toBeTruthy()
			for _, class in { "ColorCorrectionEffect", "Atmosphere", "BloomEffect", "SunRaysEffect" } do
				expect(countClass(lighting, class)).toBe(1)
			end
			expect(countClass(lighting, "Clouds")).toBe(0)
			expect(rig.Tweens).toBe(0) -- set at once, not tweened, before the first phase
			rig.expectLook(Pure.DAY)
			expect(lighting.ClockTime).toBeCloseTo(14, 3)
		end
	)

	test(
		"the place's own SunRays, Bloom and Atmosphere are reused (never a second), and depth of field goes off",
		function()
			local rig = bootDayNight(function(lighting)
				local rays = roblox.Instance.new("SunRaysEffect")
				rays.Name = "PlaceRays"
				rays.Enabled = false
				rays.Parent = lighting
				local bloom = roblox.Instance.new("BloomEffect")
				bloom.Name = "PlaceBloom"
				bloom.Enabled = false
				bloom.Parent = lighting
				local air = roblox.Instance.new("Atmosphere")
				air.Name = "PlaceAir"
				air.Parent = lighting
				local blur = roblox.Instance.new("DepthOfFieldEffect")
				blur.Enabled = true
				blur.Parent = lighting
			end)
			local lighting = rig.Lighting
			expect(countClass(lighting, "SunRaysEffect")).toBe(1)
			expect(countClass(lighting, "BloomEffect")).toBe(1)
			expect(countClass(lighting, "Atmosphere")).toBe(1)
			expect(lighting:FindFirstChild("PlaceRays").Enabled).toBe(true)
			expect(lighting:FindFirstChild("PlaceBloom").Enabled).toBe(true)
			expect(lighting:FindFirstChildOfClass("DepthOfFieldEffect").Enabled).toBe(false)
			rig.expectLook(Pure.DAY)
		end
	)

	test("the phase loop: day, then night (SkipPhase), then the Day Report and day again", function()
		local rig = bootDayNight()
		rig.step() -- morning
		expect(rig.Attrs.IsNight).toBe(false)
		expect(rig.Attrs.PhaseEndsAt).toBe(1000 + Config.DaySeconds)
		rig.expectLook(Pure.DAY)
		expect(rig.Tweens).toBe(5) -- Lighting and the four effects, together
		expect(string.find(rig.Toasts[1], "Good morning", 1, true) ~= nil).toBe(true)

		rig.skip() -- nightfall
		expect(rig.Attrs.IsNight).toBe(true)
		expect(rig.Attrs.SkipPhase).toBeNil()
		expect(rig.Attrs.PhaseEndsAt).toBe(1000 + Config.NightSeconds)
		rig.expectLook(Pure.NIGHT)
		expect(string.find(rig.Toasts[2], "Night shift", 1, true) ~= nil).toBe(true)
		expect(rig.Flushes).toBe(0)

		rig.skip() -- the night ends: the Day Report, then morning
		expect(rig.Flushes).toBe(1)
		expect(rig.Attrs.IsNight).toBe(false)
		rig.expectLook(Pure.DAY)
		-- the enum settings are never touched by a phase (they don't tween)
		expect(rig.Lighting.LightingStyle).toBe(Enum.LightingStyle.Soft)
		expect(rig.Lighting.PrioritizeLightingQuality).toBe(true)
	end)

	test("the API is unchanged: start() and the Workspace attributes IsNight, PhaseEndsAt, SkipPhase", function()
		local rig = bootDayNight()
		expect(type(rig.DayNight.start)).toBe("function")
		expect(type(rig.DayNight.Pure)).toBe("table")
		local keys = {}
		for key in rig.DayNight do
			table.insert(keys, key)
		end
		table.sort(keys)
		expect(keys).toEqual({ "Pure", "start" })
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- 3. NightLights: the day look survives the night
------------------------------------------------------------------------------------------------------------------

local function partIn(world, parent)
	local part = world.new("Part")
	part.Size = Vector3.new(7, 1, 7)
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent or world.Workspace
	return part
end

T.describe("NightLights: the restore rule", function()
	test("Variant mode: a studded part tagged and toggled night -> day is Plastic with its variant again", function()
		local world = World.new()
		world.setVariant(true)
		local Studs = world.load("src/server/World/Studs.luau")
		local NightLights = world.load(NIGHT_LIGHTS)
		NightLights.wire()
		local part = partIn(world)
		Studs.apply(part)
		NightLights.tag(part, "Lamp")
		world.setNight(true)
		expect(part.Material).toBe(Enum.Material.Neon)
		world.setNight(false)
		expect(part.Material).toBe(Enum.Material.Plastic)
		expect(part.MaterialVariant).toBe(Config.Look.StudsVariant)
		expect(part:GetAttribute("Studded")).toBe(true)
		expect(part:GetAttribute("NightLit")).toBeNil()
		world.setNight(true) -- and again the next night
		world.setNight(false)
		expect(part.Material).toBe(Enum.Material.Plastic)
		expect(part.MaterialVariant).toBe(Config.Look.StudsVariant)
	end)

	test("Surface mode: the top studs come back too", function()
		local world = World.new()
		local Studs = world.load("src/server/World/Studs.luau")
		local NightLights = world.load(NIGHT_LIGHTS)
		NightLights.wire()
		local window = partIn(world)
		Studs.apply(window)
		NightLights.tag(window, "Window")
		world.setNight(true)
		world.setNight(false)
		expect(window.Material).toBe(Enum.Material.Plastic)
		expect(window.TopSurface).toBe(Enum.SurfaceType.Studs)
	end)

	test("a Glass window goes warm SmoothPlastic at night (never Neon), and is Glass in its colour by day", function()
		local world = World.new()
		local NightLights = world.load(NIGHT_LIGHTS)
		local Palette = world.load("src/shared/Palette.luau")
		NightLights.wire()
		local glass = partIn(world)
		glass.Material = Enum.Material.Glass
		glass.Color = Palette.World.Window
		glass.Transparency = 0.4
		NightLights.tag(glass, "Window")
		world.setNight(true)
		expect(glass.Material).toBe(Enum.Material.SmoothPlastic)
		expect(glass.Color).toEqual(Palette.World.WindowNight)
		expect(glass.Transparency).toBe(0.4) -- the cutaway and the street view through the glass are untouched
		world.setNight(false)
		expect(glass.Material).toBe(Enum.Material.Glass)
		expect(glass.Color).toEqual(Palette.World.Window)
	end)

	test("a part recoloured or re-studded after tagging comes back as it was at nightfall", function()
		local world = World.new()
		local Studs = world.load("src/server/World/Studs.luau")
		local NightLights = world.load(NIGHT_LIGHTS)
		NightLights.wire()
		local window, lamp = partIn(world), partIn(world)
		NightLights.tag(window, "Window")
		NightLights.tag(lamp, "Lamp")
		window.Color = Color3.fromRGB(47, 59, 87) -- a theme recolours it by day
		Studs.apply(lamp) -- a builder studs it after tagging
		world.setNight(true)
		world.setNight(false)
		expect(window.Color).toEqual(Color3.fromRGB(47, 59, 87))
		expect(lamp.Material).toBe(Enum.Material.Plastic)
		expect(lamp.TopSurface).toBe(Enum.SurfaceType.Studs)
	end)

	test("a part tagged at night lights at once and gets its day look in the morning; re-tagging keeps it", function()
		local world = World.new()
		local Studs = world.load("src/server/World/Studs.luau")
		local NightLights = world.load(NIGHT_LIGHTS)
		NightLights.wire()
		world.setNight(true)
		local lamp = partIn(world)
		lamp.Color = Color3.fromRGB(255, 232, 140)
		Studs.apply(lamp)
		NightLights.tag(lamp, "Lamp")
		expect(lamp.Material).toBe(Enum.Material.Neon)
		NightLights.tag(lamp, "Lamp") -- a builder tags it again while it's lit: the night look isn't stored as day
		expect(lamp:GetAttribute("DayMaterial")).toBe("Plastic")
		world.setNight(false)
		expect(lamp.Material).toBe(Enum.Material.Plastic)
		expect(lamp.Color).toEqual(Color3.fromRGB(255, 232, 140))
	end)

	test("a part cloned while lit comes back by its own stored day look", function()
		local world = World.new()
		local Studs = world.load("src/server/World/Studs.luau")
		local NightLights = world.load(NIGHT_LIGHTS)
		NightLights.wire()
		local lamp = partIn(world)
		Studs.apply(lamp)
		NightLights.tag(lamp, "Lamp")
		world.setNight(true)
		local copy = lamp:Clone() -- attributes travel; Roblox clones the tag too
		copy.Parent = world.Workspace
		copy:AddTag(NightLights.TAG)
		expect(copy.Material).toBe(Enum.Material.Neon)
		world.setNight(false)
		expect(copy.Material).toBe(Enum.Material.Plastic)
	end)

	test("every light under a tagged part is shadowless and follows the night (Lamp, Window and Sign)", function()
		local world = World.new()
		local NightLights = world.load(NIGHT_LIGHTS)
		NightLights.wire()
		local lights = {}
		for _, kind in { "Lamp", "Window", "Sign" } do
			local part = partIn(world)
			local light = world.new("SpotLight")
			light.Shadows = true -- a hand-made light that would cast shadows
			light.Enabled = false
			light.Parent = part
			table.insert(lights, light)
			NightLights.tag(part, kind)
		end
		world.setNight(true)
		for _, light in lights do
			expect(light.Enabled).toBe(true)
			expect(light.Shadows).toBe(false)
		end
		world.setNight(false)
		for _, light in lights do
			expect(light.Enabled).toBe(false)
			expect(light.Shadows).toBe(false)
		end
	end)

	test("light(): a warm lamp light, shadowless, off by day", function()
		local world = World.new()
		local NightLights = world.load(NIGHT_LIGHTS)
		local Palette = world.load("src/shared/Palette.luau")
		NightLights.wire()
		local head = partIn(world)
		local light = NightLights.light(head, 18)
		expect(light.Color).toEqual(Palette.World.Lamp)
		expect(light.Brightness > 0).toBe(true)
		expect({ light.Shadows, light.Enabled, light.Range }).toEqual({ false, false, 18 })
		expect(head:GetAttribute("NightKind")).toBe("Lamp")
	end)
end)

T.describe("NightLights: the built world, night and morning", function()
	local function build(nightFirst: boolean)
		local world = World.new()
		if nightFirst then
			world.setNight(true)
		end
		local PlotBuilder = world.load("src/server/PlotBuilder.luau")
		PlotBuilder.buildTown()
		for _, plot in world.Workspace.Clinics:GetChildren() do
			PlotBuilder.buildBuilding(plot, 5)
		end
		return world
	end

	local function looks(world)
		local out = {}
		for _, part in world.parts(world.Workspace) do
			table.insert(out, { part.Name, part.Material, part.MaterialVariant, part.Color })
		end
		return out
	end

	test("at night every lamp is Neon with its light on, and no window is Neon", function()
		local world = build(false)
		world.setNight(true)
		local lamps = 0
		for _, part in world.tagged("ClinicNightLight") do
			local kind = part:GetAttribute("NightKind")
			if kind == "Lamp" or kind == nil then
				lamps += 1
				expect(part.Material).toBe(Enum.Material.Neon)
			elseif kind == "Window" then
				expect(part.Material == Enum.Material.Neon).toBe(false)
			end
			for _, child in part:GetChildren() do
				if child:IsA("Light") then
					expect(child.Enabled).toBe(true)
					expect(child.Shadows).toBe(false)
				end
			end
		end
		expect(lamps > 0).toBe(true)
	end)

	test("night -> morning puts every part of the built world back exactly (material, variant, colour)", function()
		local world = build(false)
		local before = looks(world)
		world.setNight(true)
		world.setNight(false)
		expect(looks(world)).toEqual(before)
	end)

	test("a world built AT night is, by morning, the same as one built by day", function()
		local byDay = looks(build(false))
		local night = build(true)
		night.setNight(false)
		expect(looks(night)).toEqual(byDay)
	end)
end)
