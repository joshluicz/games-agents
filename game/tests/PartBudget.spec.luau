--!nocheck
-- The parts budget (docs/plan/2026-11-16-perf-budget.md; look build plan §C3; Config.Look): one plot at any level, in
-- any branch theme, with every room, is at most Config.Look.PlotBudget (400) parts, not counting creatures, nurses
-- or decor. Moved here from Hospital.spec by the look overhaul's Foundation; the integrator owns it from there.
-- It builds the REAL PlotBuilder (and through it TownBuilder, HospitalBuilder and World/*) under tests/worldmock
-- and prints the count per level and per share, for the perf note's table.
-- The shares (Building <= BuildingParts, rooms <= RoomParts, the rest <= PlotParts) are what T3 and T4 build to:
-- their own specs (Hospital.spec, PlotWorld.spec) hold them. Here they are printed, and checked only once the
-- overhaul's builders have landed (see SHARES_HOLD).

local T = require("./expect")
local expect, test = T.expect, T.test

local Config = require("./config")
local LevelsData = require("../src/shared/Data/Levels")
local Themes = require("../src/shared/Data/Themes")

local world = require("./worldmock").new()

-- Flip to true when T3 and T4 are in: then every share is a hard limit here too.
local SHARES_HOLD = false

T.describe("Part budget (the built plot)", function()
	local PlotBuilder = world.load("src/server/PlotBuilder.luau")
	local plot = PlotBuilder.buildTown()[1]
	for _, roomId in { "BathRoom", "Ward", "WinterWing", "Garden" } do
		PlotBuilder.placeRoom(plot, roomId)
	end

	local function partsUnder(root, skip: { [string]: boolean }?): number
		local n = 0
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				local skipped = false
				if skip then
					for name in skip do
						if d:FindFirstAncestor(name) then
							skipped = true
							break
						end
					end
				end
				if not skipped then
					n += 1
				end
			end
		end
		return n
	end

	-- The plot without creatures, nurses or decor, split by owner: the Building (T3), the rooms (T4), the rest (T4).
	local function counts(): (number, number, number, number)
		local building = if plot:FindFirstChild("Building") then partsUnder(plot.Building) else 0
		local rooms = partsUnder(plot.Rooms)
		local total = partsUnder(plot, { Patients = true, Nurses = true, Decor = true })
		return total, building, rooms, total - building - rooms
	end

	test("the budgets are in Config.Look, and the shares leave room under the plot's budget", function()
		local L = Config.Look
		expect(L.PlotBudget).toBe(400)
		expect(L.BuildingParts).toBe(160)
		expect(L.RoomParts).toBe(90)
		expect(L.PlotParts).toBe(115)
		expect(L.BuildingParts + L.RoomParts + L.PlotParts <= L.PlotBudget - 35).toBe(true) -- at least 35 spare
		expect(L.TownParts).toBe(600)
		expect(L.SurfaceGuisPerBuilding).toBe(12)
		expect(L.GlassPerBuilding).toBe(6)
	end)

	test(
		"every level, every theme, every room: at most Config.Look.PlotBudget parts (no creatures, no decor)",
		function()
			local worst = 0
			local lines = {}
			for _, theme in Themes.Order do
				for level = 1, #LevelsData do
					PlotBuilder.buildBuilding(plot, level, nil, theme)
					local total, building, rooms, rest = counts()
					worst = math.max(worst, total)
					if total > Config.Look.PlotBudget then
						error(string.format("Lv %d %s: %d parts", level, theme, total))
					end
					if SHARES_HOLD then
						if building > Config.Look.BuildingParts then
							error(string.format("Lv %d %s: the Building has %d parts", level, theme, building))
						end
						if rooms > Config.Look.RoomParts then
							error(string.format("Lv %d %s: the rooms have %d parts", level, theme, rooms))
						end
						if rest > Config.Look.PlotParts then
							error(string.format("Lv %d %s: the plot has %d parts", level, theme, rest))
						end
					end
					if theme == Themes.Default then
						table.insert(
							lines,
							string.format(
								"    [parts] Lv %d %s: %d  (building %d · rooms %d · plot %d)",
								level,
								theme,
								total,
								building,
								rooms,
								rest
							)
						)
					end
				end
			end
			expect(#Themes.Order).toBe(6)
			expect(worst <= Config.Look.PlotBudget).toBe(true)
			print(table.concat(lines, "\n"))
			print(
				string.format(
					"    [parts] the heaviest plot (any level, any theme): %d / %d",
					worst,
					Config.Look.PlotBudget
				)
			)
		end
	)

	test("a Lv 5 plot with every room and every decor slot filled (the 10 heaviest decor) stays in budget", function()
		-- The real DecorBuilder under the same mock. Each decor exists once (Plots.placeDecor moves it), so the worst a
		-- plot can hold is the heaviest decor pieces, one per slot.
		local DecorBuilder = world.load("src/server/DecorBuilder.luau")
		local DecorData = world.load("src/shared/Data/Decor.luau")
		local RoomsData = world.load("src/shared/Data/Rooms.luau")
		local slots = 0
		for _, roomId in RoomsData.Order do
			slots += RoomsData[roomId].DecorSlots
		end
		local perDecor: { number } = {}
		for _, decorId in DecorData.Order do
			local n = #world.parts(DecorBuilder.build(decorId))
			if n > 25 then
				error(decorId .. ": " .. n .. " parts (DecorBuilder's MAX_PARTS is 25)")
			end
			table.insert(perDecor, n)
		end
		table.sort(perDecor, function(a, b)
			return a > b
		end)
		local decor = 0
		for index = 1, math.min(slots, #perDecor) do
			decor += perDecor[index]
		end
		local worstPlot = 0
		for _, theme in { "Candy", "Royal", "Jungle" } do
			PlotBuilder.buildBuilding(plot, 5, nil, theme)
			worstPlot = math.max(worstPlot, (counts()))
		end
		expect(slots).toBe(10)
		expect(worstPlot <= Config.Look.PlotBudget).toBe(true)
		expect(decor <= slots * 25).toBe(true)
		expect(worstPlot + decor <= Config.Look.PlotBudget + slots * 25).toBe(true)
		print(
			string.format(
				"    [parts] Lv 5, every room: %d; + the %d heaviest decor (%d): %d",
				worstPlot,
				slots,
				decor,
				worstPlot + decor
			)
		)
	end)

	test("the town's own parts are counted and printed (Config.Look.TownParts holds once T2 lands)", function()
		local town = world.Workspace:FindFirstChild("ClinicTown")
		expect(town ~= nil).toBe(true)
		local n = #world.parts(town)
		print(string.format("    [parts] ClinicTown: %d / %d", n, Config.Look.TownParts))
		expect(n <= Config.Look.TownParts).toBe(true)
	end)

	test("a free plot is back to Lv 1, and its count is the lightest", function()
		PlotBuilder.clearPlot(plot)
		expect(plot:GetAttribute("Level")).toBe(1)
		local total = counts()
		expect(total <= Config.Look.PlotBudget).toBe(true)
	end)
end)
