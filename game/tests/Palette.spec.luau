--!nocheck
-- The look overhaul's colours and tokens (Shared/Palette, UI/Theme; look build plan §B3; art-direction §4.1, §4.5;
-- ux-cohesion-audit §3.4), and the look helpers' own checks (tests/look, tests/uirules).
-- Palette and Theme are Roblox modules (Color3, Enum, Font): tests/worldmock loads the shipped files with Lune's
-- roblox datatypes.
-- The numbers: V is compared at two decimals (art-direction's own precision: the road's #3E4352 is V 0.3216, "0.32"),
-- and "no channel at 245 or more" means ABOVE 245, because the spec's own Yellow #F5C731 has R = 245.

local T = require("./expect")
local expect, test = T.expect, T.test

local World = require("./worldmock")
local Look = require("./look")
local UiRules = require("./uirules")
local HudZones = require("../src/shared/Logic/HudZones")

local world = World.new()
local Palette = world.load("src/shared/Palette.luau")
local Theme = world.load("src/client/UI/Theme.luau")
local Color3 = World.roblox.Color3

local function hex(color): string
	return string.format(
		"#%02X%02X%02X",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5)
	)
end

local function v(color): number
	local _, _, value = Look.hsv(color)
	return Look.round(value)
end

T.describe("Palette.World (art-direction §4.1)", function()
	local WORLD = {
		GrassA = "#56C740",
		GrassB = "#3FB536",
		Dirt = "#8C603E",
		LeavesA = "#39A844",
		LeavesB = "#2B8F42",
		LeavesC = "#67C246",
		Trunk = "#704B31",
		Plank = "#D6B27C",
		PlankAlt = "#BA9265",
		Road = "#3E4352",
		RoadLine = "#F0EBE1",
		Curb = "#999CA3",
		Pad = "#253D4C",
		Edge = "#8A8E94",
		Roof = "#2D2B3D",
		Trim = "#F0EBDF",
		Beam = "#805738",
		Fence = "#EBE6DA",
		CheckerTeal = "#369E94",
		CheckerCream = "#EBDEC0",
		Water = "#38A7D6",
		FloorA = "#AD8053",
		FloorB = "#996B45",
		WallUpper = "#EBE4D8",
		Window = "#2F3B57",
		WindowNight = "#D8B470",
		Pavement = "#CDB38A",
		PavementAlt = "#B79D74",
		PavementGrout = "#8A7558",
	}

	test("every key matches the table exactly", function()
		for key, want in WORLD do
			if hex(Palette.World[key]) ~= want then
				error(key .. ": expected " .. want .. ", got " .. hex(Palette.World[key]))
			end
		end
	end)

	test("every old key is still there, as an alias of its new value", function()
		local aliases = {
			Grass = "GrassA",
			GrassDark = "GrassB",
			Path = "Plank",
			Street = "Road",
			StreetLine = "RoadLine",
			Wood = "PlankAlt",
			WoodDark = "Beam",
			Leaves = "LeavesA",
			LeavesLight = "LeavesC",
			Floor = "FloorA",
			Wall = "WallUpper",
		}
		for old, new in aliases do
			expect(Palette.World[old]).toEqual(Palette.World[new])
		end
		-- keys that kept their name
		for _, key in { "Fence", "Trunk", "Water", "Pavement", "PavementAlt", "PavementGrout", "Lamp" } do
			expect(Palette.World[key] ~= nil).toBe(true)
		end
		expect(hex(Palette.World.Lamp)).toBe("#FFE88C") -- unchanged: Neon at night only
	end)

	test(
		"no pastels: no colour has a channel above 245, and the warm whites cap at 240 (the Lamp glow aside)",
		function()
			for key, color in Palette.World do
				if key ~= "Lamp" then
					if Look.maxChannel(color) > 245 then
						error("World." .. key .. " is bleached: " .. hex(color))
					end
				end
			end
			for key, color in Palette.Accent do
				if Look.maxChannel(color) > 245 then
					error("Accent." .. key .. " is bleached: " .. hex(color))
				end
			end
			for _, key in { "Trim", "RoadLine", "Fence", "WallUpper", "CheckerCream" } do
				expect(Look.maxChannel(Palette.World[key]) <= 240).toBe(true)
			end
		end
	)

	test("dark anchors: road, pad and roof at V <= 0.32, the trunk at V <= 0.45", function()
		for _, key in { "Road", "Pad", "Roof" } do
			expect(v(Palette.World[key]) <= 0.32).toBe(true)
		end
		expect(v(Palette.World.Trunk) <= 0.45).toBe(true)
		expect(v(Palette.World.Window) <= 0.45).toBe(true)
	end)

	test(
		"the greens: S >= 0.6, V 0.55..0.85; the two lawn tones differ by V >= 0.05 and GrassB is 0-15° bluer",
		function()
			for _, key in { "GrassA", "GrassB", "LeavesA", "LeavesB", "LeavesC" } do
				local _, s, value = Look.hsv(Palette.World[key])
				expect(s >= 0.6).toBe(true)
				expect(Look.round(value) >= 0.55 and Look.round(value) <= 0.85).toBe(true)
			end
			local hueA = Look.hsv(Palette.World.GrassA)
			local hueB = Look.hsv(Palette.World.GrassB)
			expect(v(Palette.World.GrassA) - v(Palette.World.GrassB) >= 0.05).toBe(true)
			expect(hueB - hueA >= 0 and hueB - hueA <= 15).toBe(true)
		end
	)

	test("the queue lane is mid-tone (never a near-white pavement)", function()
		for _, key in { "Pavement", "PavementAlt", "PavementGrout" } do
			local value = v(Palette.World[key])
			expect(value >= 0.5 and value <= 0.85).toBe(true)
		end
	end)

	test("night windows glow warm (the Neon stays on small lamps)", function()
		local hue, s = Look.hsv(Palette.World.WindowNight)
		expect(hue >= 25 and hue <= 55).toBe(true)
		expect(s >= 0.3).toBe(true)
	end)
end)

T.describe("Palette accents and plot colours", function()
	test("the accents match the table exactly", function()
		local ACCENT = {
			Pink = "#DB3D7D",
			Blue = "#3195E0",
			Orange = "#EB842A",
			Purple = "#894ECC",
			Cyan = "#29BCCC",
			Yellow = "#F5C731",
			Red = "#D63C4B",
			Lime = "#6ACC39",
		}
		for key, want in ACCENT do
			expect(hex(Palette.Accent[key])).toBe(want)
		end
	end)

	test("Plot_1..6: Pink, Blue, Orange, Purple, Yellow, Cyan (Yellow replaced Lime)", function()
		local A = Palette.Accent
		expect(Palette.PlotColors).toEqual({ A.Pink, A.Blue, A.Orange, A.Purple, A.Yellow, A.Cyan })
		for _, color in Palette.PlotColors do
			expect(color == A.Lime).toBe(false)
			expect(color == A.Red).toBe(false) -- a plot is never red (and Red is never a cross)
		end
	end)

	test("every plot colour: S >= 0.6, V 0.78..0.96", function()
		for index, color in Palette.PlotColors do
			local _, s, value = Look.hsv(color)
			if s < 0.6 or Look.round(value) < 0.78 or Look.round(value) > 0.96 then
				error(string.format("Plot_%d %s: S %.2f V %.2f", index, hex(color), s, value))
			end
		end
	end)

	test(
		"every plot colour stands apart: >= 25° from the grass, >= 15° from pure red and from every other plot",
		function()
			local grass = Look.hsv(Palette.World.GrassA)
			for i, color in Palette.PlotColors do
				local hue = Look.hsv(color)
				expect(Look.hueGap(hue, grass) >= 25).toBe(true)
				expect(Look.hueGap(hue, 0) >= 15).toBe(true)
				for j, other in Palette.PlotColors do
					if i < j then
						local otherHue = Look.hsv(other)
						if Look.hueGap(hue, otherHue) < 15 then
							error(
								string.format("Plot_%d and Plot_%d are %.1f° apart", i, j, Look.hueGap(hue, otherHue))
							)
						end
					end
				end
			end
		end
	)

	test(
		"departments (inside only): Wards purple, Hydro cyan, Pharmacy blue, Roof leaves, A&E red; Reception = the plot",
		function()
			local A = Palette.Accent
			expect(Palette.Departments.Wards).toEqual(A.Purple)
			expect(Palette.Departments.Hydro).toEqual(A.Cyan)
			expect(Palette.Departments.Pharmacy).toEqual(A.Blue)
			expect(Palette.Departments.Roof).toEqual(Palette.World.LeavesA)
			expect(Palette.Departments.AE).toEqual(A.Red)
			expect(Palette.Departments.Reception).toBeNil()
		end
	)

	test("ink, navy and gold; the UI's Candy set is unchanged", function()
		expect(hex(Palette.Outline)).toBe("#1B1238")
		expect(hex(Palette.Navy)).toBe("#1E2440")
		expect(hex(Palette.Gold)).toBe("#FFD84A")
		expect(hex(Palette.Ink)).toBe("#221A48")
		expect(hex(Palette.InkSoft)).toBe("#5D5788")
		expect(Palette.Candy.Pink).toEqual(Color3.fromRGB(255, 70, 170))
		expect(Palette.Candy.Lime).toEqual(Color3.fromRGB(80, 220, 60))
		for _, key in { "Lime", "Orange", "Pink", "Blue", "Purple", "Red", "Yellow", "Cyan", "Mint" } do
			expect(Palette.Candy[key] ~= nil).toBe(true)
		end
	end)
end)

T.describe("Theme tokens (ux audit §3.4, with the navy header)", function()
	test("Navy == Theme.Colors.Header == Theme.Colors.NowPlate", function()
		expect(Theme.Colors.Header).toEqual(Palette.Navy)
		expect(Theme.Colors.NowPlate).toEqual(Palette.Navy)
	end)

	test("the chrome and role colours", function()
		local want = {
			Paper = "#FFFFFF",
			PaperEdge = "#FFFFFF", -- flat: no gradient
			Card = "#EEF3FA",
			CardLine = "#C3D0E6",
			Well = "#D6E3F5",
			Locked = "#6A5FA0",
			Plate = "#FFFFFF",
			Ink = "#221A48",
			InkSoft = "#5D5788",
			Stroke = "#1B1238",
			Outline = "#1B1238",
			Primary = "#FF9A1F",
			PrimaryEnd = "#F27A0C",
			Collect = "#45CF3A",
			CollectEnd = "#2BA52A",
			Secondary = "#DFE6F2",
			Destructive = "#FF4459",
			DestructiveEnd = "#D9283F",
			Disabled = "#B3B6C9",
			DisabledText = "#6E7190",
			Cash = "#FFD43B",
			Star = "#FFE228",
			Night = "#5B3BD6",
		}
		for key, value in want do
			if hex(Theme.Colors[key]) ~= value then
				error("Theme.Colors." .. key .. ": expected " .. value .. ", got " .. hex(Theme.Colors[key]))
			end
		end
	end)

	test(
		"old colour keys are aliases: Good = Collect, Danger = Destructive, Quiet = Secondary; Candy stripes stay",
		function()
			expect(Theme.Colors.Good).toEqual(Theme.Colors.Collect)
			expect(Theme.Colors.Danger).toEqual(Theme.Colors.Destructive)
			expect(Theme.Colors.Quiet).toEqual(Theme.Colors.Secondary)
			expect(Theme.Colors.Pink).toEqual(Palette.Candy.Pink)
			expect(Theme.Colors.Purple).toEqual(Palette.Candy.Purple)
			expect(Theme.Colors.Cyan).toEqual(Palette.Candy.Cyan)
			for _, key in { "Shade", "OnColor", "Heart", "NightText", "Dot" } do
				expect(Theme.Colors[key] ~= nil).toBe(true)
			end
		end
	)

	test("every Theme.TextSize is at least 18 (Caption is the floor)", function()
		expect(Theme.TextSize).toEqual({
			Caption = 18,
			Body = 22,
			Button = 24,
			Title = 30,
			Number = 36,
			Hero = 56,
			Icon = 40,
			Small = 18,
			Big = 48,
		})
		for name, size in Theme.TextSize do
			if size < 18 then
				error("Theme.TextSize." .. name .. " is under 18")
			end
		end
		expect(Theme.TextSize.Small).toBe(Theme.TextSize.Caption)
		expect(UiRules.FLOOR).toBe(Theme.TextSize.Caption)
	end)

	test("radii, strokes, spacing, the one shadow, the motion budget", function()
		expect(Theme.Radius.Small).toBe(8)
		expect(Theme.Radius.Medium).toBe(14)
		expect(Theme.Radius.Large).toBe(22)
		expect(Theme.Radius.Round.Scale).toBe(0.5)
		expect(Theme.Size.Corner).toBe(Theme.Radius.Medium)
		expect(Theme.Size.CornerLarge).toBe(Theme.Radius.Large)
		expect(Theme.Stroke).toEqual({ Fine = 2, Bold = 3, Panel = 4, Text = 2.5, Title = 3 })
		expect(Theme.Space.Step).toEqual({ 4, 8, 12, 16, 24, 32 })
		expect(Theme.Space.Gap).toBe(8)
		expect(Theme.Space.PadCard).toBe(12)
		expect(Theme.Space.PadPanel).toBe(16)
		expect(Theme.Space.Margin).toBe(16)
		expect(Theme.Space.MarginPhone).toBe(8)
		expect(Theme.Shadow.Color).toEqual(Theme.Colors.Stroke)
		expect(Theme.Shadow.Transparency).toBe(0.6)
		expect({ Theme.Shadow.Offset.X, Theme.Shadow.Offset.Y }).toEqual({ 0, 6 })
		expect(Theme.Motion.Perpetual).toBe(1)
		expect(Theme.Size.ButtonHeight).toBe(56) -- the tap minimum
	end)

	test("Theme.Zone mirrors Logic/HudZones", function()
		expect(Theme.Zone).toEqual({
			PhoneBreak = HudZones.PHONE_BREAK,
			RailButton = HudZones.RAIL_BUTTON,
			RailButtonMin = HudZones.RAIL_BUTTON_MIN,
			RailGap = HudZones.RAIL_GAP,
			RailGapPhone = HudZones.RAIL_GAP_PHONE,
			CornerClear = HudZones.CORNER_CLEAR,
			Topbar = HudZones.TOPBAR,
			WalletHeight = HudZones.WALLET_HEIGHT,
			NowHeight = HudZones.NOW_HEIGHT,
			NowHeightShort = HudZones.NOW_HEIGHT_SHORT,
			NowTab = HudZones.NOW_TAB,
			NowSlim = HudZones.NOW_SLIM,
			NowMax = HudZones.NOW_MAX,
			StatusWidth = HudZones.STATUS_WIDTH,
		})
	end)

	test("the tokens v2 added are still there (Juice.RingBeads, the tweens, the display orders)", function()
		expect(Theme.Juice.RingBeads).toBe(12)
		expect(Theme.Tween.PopIn ~= nil).toBe(true)
		expect(Theme.DisplayOrder.Popup > Theme.DisplayOrder.Panel).toBe(true)
		expect(Theme.DisplayOrder.Panel > Theme.DisplayOrder.Hud).toBe(true)
	end)
end)

T.describe("tests/look helpers", function()
	test("hsv, luma, maxChannel, hueGap", function()
		local h, s, value = Look.hsv(Look.fromHex("#FF0000"))
		expect({ h, s, value }).toEqual({ 0, 1, 1 })
		expect((Look.hsv(Look.fromHex("#00FF00")))).toBe(120)
		expect((Look.hsv(Look.fromHex("#0000FF")))).toBe(240)
		local _, greyS, greyV = Look.hsv(Look.fromHex("#808080"))
		expect(greyS).toBe(0)
		expect(greyV).toBeCloseTo(128 / 255, 5)
		expect(Look.luma(Look.fromHex("#FFFFFF"))).toBeCloseTo(255, 3)
		expect(Look.luma(Look.fromHex("#000000"))).toBe(0)
		expect(Look.maxChannel(Look.fromHex("#F5C731"))).toBe(245)
		expect(Look.hueGap(350, 10)).toBe(20)
		expect(Look.hueGap(10, 350)).toBe(20)
		expect(Look.hueGap(90, 270)).toBe(180)
		expect(Look.round(0.3216)).toBe(0.32)
	end)

	test("isBigFace: any face over the area", function()
		local Vector3 = World.roblox.Vector3
		expect(Look.isBigFace({ Size = Vector3.new(4, 0.2, 4) }, 16)).toBe(false)
		expect(Look.isBigFace({ Size = Vector3.new(5, 0.2, 4) }, 16)).toBe(true)
		expect(Look.isBigFace({ Size = Vector3.new(1, 20, 1) }, 16)).toBe(true)
	end)
end)

T.describe("tests/uirules helper", function()
	local function rules(text: string): { string }
		local out = {}
		for _, violation in UiRules.checkText(text, "x.luau") do
			table.insert(out, violation.Rule)
		end
		return out
	end

	test("text sizes under 18 are caught; 18 and tokens pass", function()
		expect(rules("limit.MinTextSize = 12")).toEqual({ "MinTextSize" })
		expect(rules("limit.MaxTextSize = 14")).toEqual({ "MinTextSize" })
		expect(rules("label.TextSize = 14")).toEqual({ "TextSize" })
		expect(rules("Kit.label({ TextSize = 16, Text = 'x' })")).toEqual({ "TextSize" })
		expect(rules("limit.MinTextSize = 18\nlabel.TextSize = 18\nlabel.TextSize = 22")).toEqual({})
		expect(rules("label.TextSize = Theme.TextSize.Caption")).toEqual({})
		expect(rules("limit.MinTextSize = Theme.TextSize.Caption")).toEqual({})
	end)

	test("local tab and text-fit copies, corner literals and header colours are caught", function()
		expect(rules("local function paintTab(button, on)")).toEqual({ "LocalHelper" })
		expect(rules("local function textLimit(label, max)")).toEqual({ "LocalHelper" })
		expect(rules("corner.CornerRadius = UDim.new(0, 12)")).toEqual({ "CornerLiteral" })
		expect(rules("Kit.corner(frame, 10)")).toEqual({ "CornerLiteral" })
		expect(rules("Kit.corner(frame, Theme.Radius.Medium)")).toEqual({})
		expect(rules("corner.CornerRadius = UDim.new(0, Theme.Radius.Small)")).toEqual({})
		expect(rules("corner.CornerRadius = Theme.Radius.Round")).toEqual({})
		expect(rules("\tAccent = Theme.Colors.Cyan,")).toEqual({ "HeaderColor" })
		expect(rules("local ACCENT = Theme.Colors.Purple")).toEqual({ "HeaderColor" })
		expect(rules("local color = Palette.Accent.Pink")).toEqual({})
	end)

	test("comments are ignored, a marked line is allowed, and each violation carries its line", function()
		expect(rules("-- label.TextSize = 12")).toEqual({})
		expect(rules("local x = 1 -- MinTextSize = 9 was the old value")).toEqual({})
		expect(rules('label.Text = "TextSize = 9"')).toEqual({ "TextSize" }) -- a string still counts: keep it simple
		expect(rules("label.TextSize = 12 -- uirules: allow TextSize")).toEqual({})
		local found = UiRules.checkText("local a = 1\nlabel.TextSize = 10\n", "p.luau")
		expect(#found).toBe(1)
		expect(found[1].Line).toBe(2)
		expect(found[1].Path).toBe("p.luau")
		expect(UiRules.format(found)).toBe("p.luau:2  TextSize  label.TextSize = 10")
	end)

	test("check() reads shipped files: the Foundation's own UI modules pass", function()
		local found =
			UiRules.check({ "src/client/UI/Theme.luau", "src/client/UI/Modal.luau", "src/client/UI/Wayfinder.luau" })
		if #found > 0 then
			error(UiRules.format(found))
		end
	end)
end)
