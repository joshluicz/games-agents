--!nocheck
-- The plot and its rooms (the Real Clinic build plan, Task 2; contracts C1 and C2): the REAL PlotBuilder and
-- DecorBuilder built under tests/worldmock, checked against Shared/Logic/Building.
--   · the budget: every room together <= Config.Look.RoomParts and the plot's own share <= Config.Look.PlotParts at
--     Lv 5 with every room. The plot's trees, bushes and fences are World/Props' pieces: this spec counts each of
--     them at its CONTRACT maximum (tree 7, bush 1, fence 2 + floor(length / 14) + 1), so the share holds whatever
--     Props builds, and prints the measured share beside it
--   · the 110 x 110 plot (pad 107), the Counter on Building.RECEPTION.Desk, PatientSpawn and PatientExit at the gate,
--     no queue (no QueueStart, no QueueLane, no queueSpot), the floating sign
--   · the plank path from the gate to the Stand's forecourt and on to the front doors; nothing of the plot's own in
--     the building's footprint but the Counter; the patients' walks, the ambulance yard and the Garden door clear
--   · the rooms are interior fit-outs: each inside its Building.ROOMS rect and its walls, its doorway and the 3 studs
--     inside it clear, nothing tall in its middle, no roof and no walls, CeramicTiles floors; each room's name sign
--     upright over its door on the corridor side; nothing z-fights (no two faces in one plane, no thin part inside
--     another); the Cozy Ward's ExamBay_W1 / W2 to contract C2, made like bays 1-6; Station_Bath and Station_Cocoa;
--     the Winter Wing's 3-part bed and its fireplace; the Garden
--   · studs on whole studs, in both studs modes; the palette: no Texture or Decal, no big face at V >= 0.95 (the
--     plot's own colour aside), no channel above 245
--   · placeRoom, setPreview and clearPlot as before
--   · DecorBuilder: no decor gains a part, the world palette, studded tops
-- Run from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")

local T = require("./expect")
local expect, test = T.expect, T.test

local Config = require("./config")
local Look = require("./look")
local World = require("./worldmock")
local roblox = World.roblox
local Vector3, CFrame, Enum = roblox.Vector3, roblox.CFrame, roblox.Enum

local EPS = 0.01
local PLOT_HALF = Config.Town.PlotSize / 2 -- 55: the plot's front edge is z -55, its front fence z -54.6
local GATE = 5.6 -- PlotBuilder: the gate posts' inner faces at x = ±5.6 (posts at ±6.2)

-- "Plot_1.Scenery.Tree.Leaves" (the mock has no GetFullName).
local function fullName(instance): string
	local names = {}
	local current = instance
	while current and current.Name ~= "Workspace" do
		table.insert(names, 1, current.Name)
		current = current.Parent
	end
	return table.concat(names, ".")
end

-- Builds the town in a fresh world. Before PlotBuilder loads, Props.tree/bush/fence are wrapped (the same table
-- PlotBuilder requires) to record every piece: the parts it added and its contract maximum.
local function build(variant: boolean?)
	local world = World.new()
	if variant then
		world.setVariant(true)
	end
	local Props = world.load("src/server/World/Props.luau")
	local pieces = {}
	local wrapped = not table.isfrozen(Props)
	if wrapped then
		local function wrap(kind: string, maxParts)
			local original = Props[kind]
			Props[kind] = function(parent, ...)
				if parent == nil then
					return original(parent, ...)
				end
				local before = {}
				for _, d in parent:GetDescendants() do
					before[d] = true
				end
				local result = original(parent, ...)
				local added = {}
				for _, d in parent:GetDescendants() do
					if d:IsA("BasePart") and not before[d] then
						table.insert(added, d)
					end
				end
				table.insert(pieces, { Kind = kind, Parent = parent, Parts = added, Max = maxParts(...) })
				return result
			end
		end
		wrap("tree", function()
			return 7
		end)
		wrap("bush", function()
			return 1
		end)
		wrap("fence", function(a, b)
			return 2 + math.floor((b.Position - a.Position).Magnitude / 14) + 1
		end)
	end
	local PlotBuilder = world.load("src/server/PlotBuilder.luau")
	local plots = PlotBuilder.buildTown()
	return {
		world = world,
		PlotBuilder = PlotBuilder,
		plots = plots,
		pieces = pieces,
		wrapped = wrapped,
	}
end

local W = build(false)
local world, PlotBuilder = W.world, W.PlotBuilder
local Palette = world.load("src/shared/Palette.luau")
local Building = world.load("src/shared/Logic/Building.luau")
local RoomsData = world.load("src/shared/Data/Rooms.luau")
local WORLD, ACCENT = Palette.World, Palette.Accent

local plot = W.plots[1]
for _, roomId in { "BathRoom", "Ward", "WinterWing", "Garden" } do
	PlotBuilder.placeRoom(plot, roomId)
end
PlotBuilder.buildBuilding(plot, 5, nil, "Candy")
local pivot = plot:GetPivot()

-- Each bought room inside the Building: its Building.ROOMS rect and its door (Building.DOORS).
local INTERIOR = {
	BathRoom = { Rect = Building.ROOMS.BathRoom, Door = "BathRoom" },
	WinterWing = { Rect = Building.ROOMS.WinterWing, Door = "WinterWing" },
	Ward = { Rect = Building.ROOMS.CozyWard, Door = "CozyWard" },
}

local function localBox(part)
	return world.box(part, pivot)
end

local function inside(instance, ancestorName: string): boolean
	return instance:FindFirstAncestor(ancestorName) ~= nil
end

-- Every BasePart on the plot that is the plot's own or its rooms' (no Building, creatures, nurses or decor).
local OFF_PLOT = { "Building", "Patients", "Nurses", "Decor" }
local function plotParts(p)
	local out = {}
	for _, d in p:GetDescendants() do
		if d:IsA("BasePart") then
			local off = false
			for _, name in OFF_PLOT do
				if d:FindFirstAncestor(name) and d:FindFirstAncestor(name):IsDescendantOf(p) then
					off = true
					break
				end
			end
			if not off then
				table.insert(out, d)
			end
		end
	end
	return out
end

local function partsUnder(root): number
	return #world.parts(root)
end

-- The Props pieces built for one plot, and the set of their parts.
local function piecesOn(p)
	local list, set = {}, {}
	for _, piece in W.pieces do
		if piece.Parent == p or piece.Parent:IsDescendantOf(p) then
			table.insert(list, piece)
			for _, part in piece.Parts do
				set[part] = true
			end
		end
	end
	return list, set
end

local function near(a: number, b: number): boolean
	return math.abs(a - b) <= EPS
end

local function whole(n: number): boolean
	return math.abs(n - math.floor(n + 0.5)) <= 1e-6
end

local function overlaps(lo, hi, zone): boolean
	return lo.X < zone.X1 - EPS
		and hi.X > zone.X0 + EPS
		and lo.Z < zone.Z1 - EPS
		and hi.Z > zone.Z0 + EPS
		and lo.Y < (zone.Y1 or math.huge) - EPS
		and hi.Y > (zone.Y0 or -math.huge) + EPS
end

-- The segment a -> b (plot-local x, z) against a box grown by `margin`.
local function crosses(a, b, lo, hi, margin: number): boolean
	local x0, x1, z0, z1 = lo.X - margin, hi.X + margin, lo.Z - margin, hi.Z + margin
	local dx, dz = b.X - a.X, b.Z - a.Z
	local t0, t1 = 0, 1
	for _, edge in { { -dx, a.X - x0 }, { dx, x1 - a.X }, { -dz, a.Z - z0 }, { dz, z1 - a.Z } } do
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
			if t0 > t1 then
				return false
			end
		end
	end
	return true
end

-- Every solid part (CanCollide) of `root` at walking height that a walk a -> b would run into.
local function blockers(parts, a, b, margin: number)
	local hits = {}
	for _, d in parts do
		if d.CanCollide then
			local lo, hi = localBox(d)
			if hi.Y > 1 and lo.Y < 4 and crosses(a, b, lo, hi, margin) then
				table.insert(hits, fullName(d))
			end
		end
	end
	return hits
end

local function point(p)
	return Vector3.new(p.X, 0, p.Z)
end

-- The floor top of a placed room (plot-local).
local function floorTop(room): number
	local _, hi = localBox(room.Floor)
	return hi.Y
end

------------------------------------------------------------------------------------------------------------------
T.describe("Plot and rooms: the parts budget (Lv 5, every room)", function()
	test("every room together is within Config.Look.RoomParts", function()
		local lines, total = {}, 0
		for _, room in plot.Rooms:GetChildren() do
			local n = partsUnder(room)
			total += n
			table.insert(lines, room.Name .. " " .. n)
		end
		table.sort(lines)
		print(
			"    [parts] rooms: "
				.. total
				.. " / "
				.. Config.Look.RoomParts
				.. "  ("
				.. table.concat(lines, " · ")
				.. ")"
		)
		expect(#plot.Rooms:GetChildren()).toBe(#RoomsData.Order)
		expect(total <= Config.Look.RoomParts).toBe(true)
	end)

	test("the plot's own share is within Config.Look.PlotParts, each Props piece at its contract maximum", function()
		local measured = #plotParts(plot) - partsUnder(plot.Rooms)
		local list = piecesOn(plot)
		local props, maxProps, kinds = 0, 0, {}
		for _, piece in list do
			props += #piece.Parts
			maxProps += piece.Max
			kinds[piece.Kind] = (kinds[piece.Kind] or 0) + 1
		end
		expect(W.wrapped).toBe(true) -- Props must stay a plain table, so this spec can see its pieces
		expect(kinds.tree).toBe(5)
		expect(kinds.bush).toBe(5)
		expect(kinds.fence).toBe(5)
		local own = measured - props
		local bound = own + maxProps
		print(
			string.format(
				"    [parts] the plot's share: %d measured (%d its own + %d Props); %d with Props at its contract max / %d",
				measured,
				own,
				props,
				bound,
				Config.Look.PlotParts
			)
		)
		expect(bound <= Config.Look.PlotParts).toBe(true)
	end)

	test("Lv 1 to 5 and every theme: the plot and its rooms don't change with the building", function()
		local before = #plotParts(plot)
		for level = 1, 5 do
			PlotBuilder.buildBuilding(plot, level, nil, "Royal")
			expect(#plotParts(plot)).toBe(before)
		end
		PlotBuilder.buildBuilding(plot, 5, nil, "Candy")
	end)
end)

------------------------------------------------------------------------------------------------------------------
T.describe("Plot: the ground, the Counter, the markers and the sign", function()
	test(
		"the plot is 110 x 110: a dark studded Pad 107 x 107 (whole odd studs), four Slate Edges to its edge",
		function()
			expect(Config.Town.PlotSize).toBe(110)
			local ground = plot.Ground
			expect(ground.ClassName).toBe("Model")
			local pad = ground.Pad
			expect(pad.Color).toBe(WORLD.Pad)
			expect(pad:GetAttribute("Studded")).toBe(true)
			expect(pad.Material).toBe(Enum.Material.Plastic)
			expect(pad.TopSurface).toBe(Enum.SurfaceType.Studs) -- Surface mode: no CureStuds variant in this world
			expect(pad.Size.X).toBe(107)
			expect(pad.Size.Z).toBe(107)
			local _, _, v = Look.hsv(pad.Color)
			expect(Look.round(v) <= 0.32).toBe(true)
			local padLo, padHi = localBox(pad)
			expect(near(padHi.Y, 0) and near(padLo.X, -pad.Size.X / 2)).toBe(true)

			local edges, lo, hi = 0, nil, nil
			for _, child in ground:GetChildren() do
				if child.Name == "Edge" then
					edges += 1
					expect(child.Material).toBe(Enum.Material.Slate)
					expect(child.Color).toBe(WORLD.Edge)
					expect(child:GetAttribute("Studded")).toBeNil()
					local a, b = localBox(child)
					lo = if lo then lo:Min(a) else a
					hi = if hi then hi:Max(b) else b
				end
			end
			expect(edges).toBe(4)
			expect(
				near(lo.X, -PLOT_HALF) and near(hi.X, PLOT_HALF) and near(lo.Z, -PLOT_HALF) and near(hi.Z, PLOT_HALF)
			).toBe(true)
			expect(hi.Y > 0 and hi.Y <= 0.2).toBe(true) -- a stone lip just proud of the pad
		end
	)

	test("every plot's Ground is a Model named Ground (Patients' and Nurses' rays include it)", function()
		for _, p in W.plots do
			expect(p.Ground ~= nil and p.Ground.Pad ~= nil).toBe(true)
			expect(p.Ground.Pad.CanCollide).toBe(true)
		end
	end)

	test(
		"the Counter sits on Building.RECEPTION.Desk: the plot's colour, a studded top, our paw-heart, no cross",
		function()
			local desk = Building.RECEPTION.Desk
			for _, p in W.plots do
				local counter = p.Counter
				expect(counter.Parent).toBe(p) -- at the plot's top level: Plots and Patients find it by name
				local lo, hi = world.box(counter, p:GetPivot())
				if lo.X < desk.X0 - EPS or hi.X > desk.X1 + EPS or lo.Z < desk.Z0 - EPS or hi.Z > desk.Z1 + EPS then
					error(string.format("the Counter is x %.2f..%.2f, z %.2f..%.2f", lo.X, hi.X, lo.Z, hi.Z))
				end
				expect(near(lo.Y, 0)).toBe(true) -- it stands on the lobby's floor
			end
			local accent = plot:GetAttribute("Accent")
			expect(plot.Counter.Color).toBe(accent)
			expect(plot.Counter.Material).toBe(Enum.Material.SmoothPlastic)
			expect(plot.Counter.CanCollide).toBe(true)
			local top = plot.Scenery.CounterTop
			expect(top:GetAttribute("Studded")).toBe(true)
			expect(top.Color).toBe(WORLD.Trim)
			expect(top.CanCollide).toBe(false)
			expect(whole(top.Size.X) and whole(top.Size.Z)).toBe(true)
			local gui = plot.Counter.DeskGui
			expect(gui.Face).toBe(Enum.NormalId.Front)
			expect(gui.MaxDistance > 0).toBe(true)
			expect(gui:FindFirstChild("PawHeart", true) ~= nil).toBe(true)
			-- the desk's mark faces the front doors: its Front face's normal is the plot's -z
			local front = pivot:VectorToObjectSpace(plot.Counter.CFrame.LookVector)
			expect(front.Z).toBeCloseTo(-1, 3)
		end
	)

	test("PatientSpawn (facing in) and PatientExit (facing the street) stand in the gate's mouth", function()
		for _, p in W.plots do
			local plotPivot = p:GetPivot()
			for name, facing in { PatientSpawn = 1, PatientExit = -1 } do
				local m = p:FindFirstChild(name)
				expect(m ~= nil and m:IsA("BasePart")).toBe(true)
				expect(m.Transparency).toBe(1)
				local at = plotPivot:PointToObjectSpace(m.Position)
				if math.abs(at.X) > GATE - 1 or at.Z > -PLOT_HALF + 4 or at.Z < -PLOT_HALF + 1 then
					error(string.format("%s at (%.2f, %.2f) is not in the gate", name, at.X, at.Z))
				end
				expect(near(at.Y - m.Size.Y / 2, 0)).toBe(true) -- it rests on the ground
				local look = plotPivot:VectorToObjectSpace(m.CFrame.LookVector)
				expect(look.Z).toBeCloseTo(facing, 3)
			end
		end
	end)

	test("no queue: no QueueStart, no QueueLane on any plot, and no PlotBuilder.queueSpot", function()
		expect(PlotBuilder.queueSpot).toBeNil()
		for _, p in W.plots do
			for _, d in p:GetDescendants() do
				if d.Name == "QueueStart" or d.Name == "QueueLane" or d.Name == "LaneTile" or d.Name == "LaneSpot" then
					error(fullName(d) .. " is a piece of the old queue")
				end
			end
		end
	end)

	test("the MascotSpot rests on the Stand's forecourt beside the front doors, off their span", function()
		local mascot = plot.MascotSpot
		local lo, hi = localBox(mascot)
		local forecourt = plot.Rooms.Room_Stand.Floor
		local fLo, fHi = localBox(forecourt)
		expect(near(lo.Y, fHi.Y)).toBe(true)
		expect(lo.X >= fLo.X - EPS and hi.X <= fHi.X + EPS and lo.Z >= fLo.Z - EPS and hi.Z <= fHi.Z + EPS).toBe(true)
		local doors = Building.DOORS.Front
		expect(hi.X <= doors.X0 + EPS or lo.X >= doors.X1 - EPS).toBe(true)
	end)

	test("the sign floats: its four labels are there, with no board behind them", function()
		local sign = plot.Sign
		expect(sign.Transparency).toBe(1)
		expect(sign.CanCollide).toBe(false)
		local gui = sign.SignGui
		expect(gui.Face).toBe(Enum.NormalId.Front)
		expect(gui.LightInfluence).toBe(0)
		for _, name in { "OwnerName", "HeartCount", "RankBadge", "BranchBadge" } do
			local label = gui:FindFirstChild(name)
			expect(label ~= nil and label.ClassName == "TextLabel").toBe(true)
		end
		expect(gui.OwnerName.Text).toBe("✨ Free clinic")
		expect(gui.OwnerName.BackgroundTransparency).toBe(1)
		expect(gui.OwnerName:FindFirstChild("TextOutline") ~= nil).toBe(true)
		expect(gui.HeartCount.BackgroundTransparency).toBe(1)
		for _, name in { "RankBadge", "BranchBadge" } do
			expect(gui[name].Visible).toBe(false)
			expect(gui[name].BackgroundColor3).toBe(Palette.Navy)
		end
		-- no board: nothing in the gui is a Frame, and nothing is named Board
		for _, d in gui:GetDescendants() do
			expect(d.ClassName == "Frame" or d.Name == "Board").toBe(false)
		end
		-- the letters clear the 3-stud fence in front of them, just behind it; two studded posts in the plot's colour
		local lo, hi = localBox(sign)
		expect(lo.Y >= 3.5).toBe(true)
		expect(lo.Z > -PLOT_HALF + 0.4 and hi.Z < -PLOT_HALF + 2).toBe(true)
		local posts = 0
		for _, child in plot.Scenery:GetChildren() do
			if child.Name == "SignPost" then
				posts += 1
				expect(child.Color).toBe(plot:GetAttribute("Accent"))
				expect(child:GetAttribute("Studded")).toBe(true)
			end
		end
		expect(posts).toBe(2)
	end)

	test("every SurfaceGui on the plot and in its rooms stops drawing far away (a MaxDistance)", function()
		local guis = 0
		for _, d in plot:GetDescendants() do
			if d.ClassName == "SurfaceGui" and not d:FindFirstAncestor("Building") then
				guis += 1
				expect(d.MaxDistance ~= nil and d.MaxDistance > 0 and d.MaxDistance <= 160).toBe(true)
			end
		end
		print("    [guis] SurfaceGuis on Plot_1 (Lv 5, every room; the Building's aside): " .. guis)
		expect(guis > 0).toBe(true)
	end)

	test("no Texture, no Decal and nothing named Cross on any plot or in its rooms", function()
		for _, p in W.plots do
			for _, d in p:GetDescendants() do
				if not d:FindFirstAncestor("Building") then
					expect(d.ClassName == "Texture" or d.ClassName == "Decal").toBe(false)
					expect(string.find(string.lower(d.Name), "cross", 1, true)).toBeNil()
				end
			end
		end
	end)
end)

------------------------------------------------------------------------------------------------------------------
T.describe("Plot: the path, the slots and the clearances", function()
	local doors = Building.DOORS.Front

	-- Parts that can be in the way: the plot's own and its rooms' (Ground and invisible markers aside).
	local function solidish()
		local out = {}
		for _, d in plotParts(plot) do
			if not inside(d, "Ground") and d.Transparency < 1 then
				table.insert(out, d)
			end
		end
		return out
	end

	test("the plank path runs from the gate to the Stand's forecourt, whose tiles run on to the front doors", function()
		local path = plot.Scenery.Path
		expect(path.Material).toBe(Enum.Material.WoodPlanks)
		local lo, hi = localBox(path)
		local forecourt = plot.Rooms.Room_Stand.Floor
		local fLo, fHi = localBox(forecourt)
		expect(lo.Z <= -plot.Ground.Pad.Size.Z / 2 + EPS).toBe(true) -- from the pad's front edge, in the gate
		expect(near(hi.Z, fLo.Z)).toBe(true) -- straight onto the forecourt ...
		expect(near(fHi.Z, Building.FRONT)).toBe(true) -- ... which runs to the façade
		expect(forecourt.Material).toBe(Enum.Material.CeramicTiles)
		for _, box in { { lo, hi }, { fLo, fHi } } do
			expect(box[1].X <= doors.X0 + EPS and box[2].X >= doors.X1 - EPS).toBe(true) -- as wide as the doors
		end
		expect(lo.X >= -GATE - EPS and hi.X <= GATE + EPS).toBe(true) -- and no wider than the gate
		expect(hi.Y <= 0.25).toBe(true) -- flat: creatures walk on it
	end)

	test(
		"the slots: the Bath Room, Winter Wing and Cozy Ward inside the Building's ground floor, the Garden behind",
		function()
			local function rectOf(slotId)
				local lo, hi = localBox(plot.Slots["RoomSlot_" .. slotId])
				return lo, hi
			end
			for roomId, info in INTERIOR do
				local lo, hi = rectOf(RoomsData[roomId].Slot)
				local r = info.Rect
				if lo.X < r.X0 - EPS or hi.X > r.X1 + EPS or lo.Z < r.Z0 - EPS or hi.Z > r.Z1 + EPS then
					error(roomId .. "'s slot isn't inside Building.ROOMS")
				end
			end
			local gLo, gHi = rectOf(RoomsData.Garden.Slot)
			expect(gLo.Z >= Building.BACK - EPS).toBe(true)
			local garden = Building.DOORS.Garden
			expect(gLo.X <= garden.X0 and gHi.X >= garden.X1).toBe(true) -- behind the Garden door
			expect(gHi.Z <= PLOT_HALF - 4).toBe(true) -- with room to walk round it inside the fence
			local sLo, sHi = rectOf(RoomsData.Stand.Slot)
			expect(near(sHi.Z, Building.FRONT) and sLo.Z < Building.FRONT).toBe(true) -- the forecourt, in front
		end
	)

	test("nothing of the plot's own in the building's footprint but the Counter", function()
		local foot = Building.footprint(5, 0)
		local zone = { X0 = foot.X0, X1 = foot.X1, Z0 = foot.Z0, Z1 = foot.Z1 }
		for _, d in solidish() do
			if not d:FindFirstAncestor("Rooms") and d.Name ~= "Counter" and d.Name ~= "CounterTop" then
				local lo, hi = localBox(d)
				if overlaps(lo, hi, zone) then
					error(fullName(d) .. " is in the building's footprint")
				end
			end
		end
	end)

	test("nothing stands on the way in (the gate's mouth, the path, the doors' span) where creatures walk", function()
		local zone = {
			X0 = doors.X0 - 0.5,
			X1 = doors.X1 + 0.5,
			Z0 = -PLOT_HALF,
			Z1 = Building.FRONT,
			Y0 = 0.5,
			Y1 = 7,
		}
		for _, d in solidish() do
			local lo, hi = localBox(d)
			if overlaps(lo, hi, zone) and d.Name ~= "GateArch" and d.Name ~= "GateLamp" then
				error(fullName(d) .. " is on the way in")
			end
		end
	end)

	test("the patients' walks: the gate to the front doors and back, clear of everything solid", function()
		local _, outside = Building.doorPoints("Front")
		local spawn = pivot:PointToObjectSpace(plot.PatientSpawn.Position)
		local exit = pivot:PointToObjectSpace(plot.PatientExit.Position)
		local parts = plotParts(plot)
		for _, leg in { { spawn, point(outside) }, { point(outside), exit } } do
			local hits = blockers(parts, Vector3.new(leg[1].X, 0, leg[1].Z), leg[2], 0.5)
			if #hits > 0 then
				error("a walk through the gate crosses " .. table.concat(hits, ", "))
			end
		end
	end)

	test("the ambulance yard (Building.BAY_AMBULANCE) and the A&E door are clear of the plot's own", function()
		local bay = Building.BAY_AMBULANCE
		local zone = { X0 = bay.Area.X0, X1 = bay.Area.X1, Z0 = bay.Area.Z0, Z1 = bay.Area.Z1, Y0 = 0.3 }
		for _, d in solidish() do
			local lo, hi = localBox(d)
			if overlaps(lo, hi, zone) then
				error(fullName(d) .. " is in the ambulance yard")
			end
		end
		local _, outside = Building.doorPoints("AE")
		local hits = blockers(plotParts(plot), point(bay.Stretcher), point(outside), 0.5)
		expect(#hits).toBe(0)
	end)

	test("the trees and bushes stay off the building, the room slots and the ambulance yard", function()
		local zones = {}
		for _, slot in plot.Slots:GetChildren() do
			local lo, hi = localBox(slot)
			zones[slot.Name] = { X0 = lo.X, X1 = hi.X, Z0 = lo.Z, Z1 = hi.Z }
		end
		local foot = Building.footprint(5, 0)
		zones.Building = { X0 = foot.X0 - 1, X1 = foot.X1 + 1, Z0 = foot.Z0 - 1, Z1 = foot.Z1 + 1 }
		local canopy = Building.CANOPY
		zones.Canopy = { X0 = canopy.X0, X1 = canopy.X1, Z0 = canopy.Z0, Z1 = canopy.Z1 }
		zones.AmbulanceBay = Building.BAY_AMBULANCE.Area
		local checked = 0
		for _, piece in piecesOn(plot) do
			if piece.Kind == "tree" or piece.Kind == "bush" then
				for _, d in piece.Parts do
					checked += 1
					local lo, hi = localBox(d)
					for name, zone in zones do
						if overlaps(lo, hi, zone) then
							error(fullName(d) .. " is on " .. name)
						end
					end
				end
			end
		end
		expect(checked > 0).toBe(true)
	end)

	test("the Garden door opens onto the Garden's open front: nothing solid in the way", function()
		local inner, outside = Building.doorPoints("Garden")
		expect(inner ~= nil).toBe(true)
		local garden = plot.Rooms.Room_Garden
		local _, gHi = localBox(garden.Floor)
		local far = Vector3.new(outside.X, 0, gHi.Z - 4)
		local hits = blockers(world.parts(garden), point(outside), far, 0.5)
		if #hits > 0 then
			error("the way into the Garden crosses " .. table.concat(hits, ", "))
		end
	end)
end)

------------------------------------------------------------------------------------------------------------------
T.describe("Rooms: interior fit-outs inside the Building", function()
	test(
		"each fit-out lies inside its Building.ROOMS rect and inside its walls (not in any wall or partition)",
		function()
			local walls = {}
			for _, o in Building.obstacles(5, 0) do
				if string.match(o.Name, "Wall$") then
					table.insert(walls, o)
				end
			end
			for roomId, info in INTERIOR do
				local room = plot.Rooms["Room_" .. roomId]
				local r = info.Rect
				for _, d in world.parts(room) do
					local lo, hi = localBox(d)
					-- (its name sign hangs on the corridor side of its door: checked on its own below)
					local outside = lo.X < r.X0 - EPS or hi.X > r.X1 + EPS or lo.Z < r.Z0 - EPS or hi.Z > r.Z1 + EPS
					if outside and d.Name ~= "NameSign" then
						error(string.format("%s.%s reaches outside its room", room.Name, d.Name))
					end
					for _, wall in walls do
						if overlaps(lo, hi, wall) then
							error(string.format("%s.%s is in %s", room.Name, d.Name, wall.Name))
						end
					end
				end
			end
		end
	)

	test("no solid fit-out part stands on a Building obstacle but its own bay's bed (Building.obstacles)", function()
		for roomId in INTERIOR do
			local room = plot.Rooms["Room_" .. roomId]
			for _, d in world.parts(room) do
				local lo, hi = localBox(d)
				if d.CanCollide and d.Name ~= "Floor" and hi.Y > 0.5 then
					for _, o in Building.obstacles(5, 0) do
						-- a bay's bed is Building's obstacle Bed_<id>: that one is the fit-out's own
						local ownBed = o.Name == "Bed_" .. tostring(d.Parent:GetAttribute("Bay"))
						if overlaps(lo, hi, o) and not ownBed then
							error(string.format("%s.%s stands on the Building's %s", room.Name, d.Name, o.Name))
						end
					end
				end
			end
		end
	end)

	-- Joshua (2026-11-17): the Cozy Ward's doorway was crowded, and "very cramped especially for someone claustrophobic".
	test(
		"each fit-out keeps its doorway and the 3 studs inside it clear (a flat rug aside), up to the door's top",
		function()
			for roomId, info in INTERIOR do
				local room = plot.Rooms["Room_" .. roomId]
				local door = Building.DOORS[info.Door]
				expect(door.Room).toBe(roomId) -- the door that opens when the room is owned
				local top = floorTop(room)
				local zone =
					{ X0 = door.X0, X1 = door.X1, Z0 = door.Z, Z1 = door.Z + 3, Y0 = top + 0.2, Y1 = door.Height }
				for _, d in world.parts(room) do
					local lo, hi = localBox(d)
					if d.Name ~= "Floor" and overlaps(lo, hi, zone) then
						error(string.format("%s.%s stands in its doorway", room.Name, d.Name))
					end
				end
			end
		end
	)

	test("furniture stands by the walls: nothing over a stud tall in a room's middle (its exam bays aside)", function()
		local MIDDLE = 4.6 -- the middle: farther than this from every wall (a bed against a wall reaches 4.4 in)
		for roomId in INTERIOR do
			local room = plot.Rooms["Room_" .. roomId]
			local top = floorTop(room)
			local fLo, fHi = localBox(room.Floor)
			local zone =
				{ X0 = fLo.X + MIDDLE, X1 = fHi.X - MIDDLE, Z0 = fLo.Z + MIDDLE, Z1 = fHi.Z - MIDDLE, Y0 = top + 1 }
			for _, d in world.parts(room) do
				if d.Transparency < 1 and not string.match(d.Parent.Name, "^ExamBay_") then
					local lo, hi = localBox(d)
					if overlaps(lo, hi, zone) then
						error(string.format("%s.%s stands in the middle of the room", room.Name, d.Name))
					end
				end
			end
		end
	end)

	test("no room has a roof or walls: nothing tall, nothing named like a shell", function()
		local ceiling = PlotBuilder.Pure.wallTop(Building, 0)
		for _, room in plot.Rooms:GetChildren() do
			local top = floorTop(room)
			for _, d in world.parts(room) do
				for _, word in { "Wall", "Roof", "Awning", "Plaque", "Trim", "Snow" } do
					if string.find(d.Name, word, 1, true) then
						error(room.Name .. "." .. d.Name .. " is a piece of a shell")
					end
				end
				local _, hi = localBox(d)
				-- a name sign hangs over its door, under the ceiling (checked on its own below)
				local limit = if d.Name == "NameSign" then ceiling else top + 7
				if room.Name ~= "Room_Garden" and hi.Y > limit + EPS then
					error(string.format("%s.%s reaches y %.2f", room.Name, d.Name, hi.Y))
				end
			end
		end
	end)

	test(
		"each room's name sign: over its door on the corridor side, upright, soft, the Data/Rooms icon and name",
		function()
			local ceiling = PlotBuilder.Pure.wallTop(Building, 0)
			for roomId, info in INTERIOR do
				local room = plot.Rooms["Room_" .. roomId]
				local signs = {}
				for _, d in room:GetDescendants() do
					if d.Name == "NameSign" then
						table.insert(signs, d)
					end
				end
				expect(#signs).toBe(1)
				local sign = signs[1]
				local door = Building.DOORS[info.Door]
				local face = door.Z - Building.PARTITION / 2 -- the wall's corridor face
				local lo, hi = localBox(sign)
				-- flat on the wall's corridor face, over the whole doorway, between the door's top and the ceiling
				expect(near(hi.Z, face)).toBe(true)
				expect(hi.Z - lo.Z <= 0.2).toBe(true)
				expect(lo.X <= door.X0 + EPS and hi.X >= door.X1 - EPS).toBe(true)
				expect(lo.Y >= door.Height - EPS and hi.Y <= ceiling + EPS).toBe(true)
				-- upright, facing the corridor (-z), its letters on that face
				local look = pivot:VectorToObjectSpace(sign.CFrame.LookVector)
				local up = pivot:VectorToObjectSpace(sign.CFrame.UpVector)
				expect(near(look.Z, -1) and near(up.Y, 1)).toBe(true)
				expect(sign.CanCollide == false and sign.CanQuery == false).toBe(true)
				local gui = sign.NameGui
				expect(gui.Face).toBe(Enum.NormalId.Front)
				expect(gui.MaxDistance > 0 and gui.MaxDistance <= 160).toBe(true)
				expect(gui.Text.Text).toBe(RoomsData[roomId].Icon .. " " .. RoomsData[roomId].Name)
			end
		end
	)

	-- Joshua (2026-11-17): "the purple bits are glitching". Two faces in one plane facing the same way, or a thin part
	-- inside another, flicker (z-fighting). Every visible part of a fit-out against every other one, and against the
	-- Building's parts round the room (its walls, lintel, doors and ceiling; the floor paint under the room aside).
	test("nothing z-fights: no two faces in one plane facing the same way, no thin part inside another", function()
		local PLANE = 0.05 -- faces closer than this count as one plane (Joshua: a strip stands >= 0.08 proud)
		local THIN = 0.3
		local function aligned(d): boolean
			for _, v in { d.CFrame.RightVector, d.CFrame.UpVector, d.CFrame.LookVector } do
				local local_ = pivot:VectorToObjectSpace(v)
				for _, c in { local_.X, local_.Y, local_.Z } do
					if math.abs(c) > 1e-4 and math.abs(math.abs(c) - 1) > 1e-4 then
						return false
					end
				end
			end
			return true
		end
		local function block(d): boolean
			return d.Shape == nil or d.Shape == Enum.PartType.Block
		end
		local function boxOf(d)
			local lo, hi = localBox(d)
			return { Part = d, Lo = { lo.X, lo.Y, lo.Z }, Hi = { hi.X, hi.Y, hi.Z }, Block = block(d) and aligned(d) }
		end
		local function overlap(a, b, k): number
			return math.min(a.Hi[k], b.Hi[k]) - math.max(a.Lo[k], b.Lo[k])
		end
		local function check(a, b)
			-- one plane, the same way: the two faces' areas overlap
			if a.Block and b.Block then
				for k = 1, 3 do
					local o1, o2 = if k == 1 then 2 else 1, if k == 3 then 2 else 3
					if overlap(a, b, o1) > EPS and overlap(a, b, o2) > EPS then
						for _, side in { "Lo", "Hi" } do
							if math.abs(a[side][k] - b[side][k]) < PLANE then
								error(
									string.format(
										"%s and %s share a face (axis %d, %s)",
										fullName(a.Part),
										fullName(b.Part),
										k,
										side
									)
								)
							end
						end
					end
				end
			end
			-- a thin part never reaches into another
			local thin = false
			for _, box in { a, b } do
				for k = 1, 3 do
					thin = thin or box.Hi[k] - box.Lo[k] < THIN
				end
			end
			if thin and overlap(a, b, 1) > EPS and overlap(a, b, 2) > EPS and overlap(a, b, 3) > EPS then
				error(string.format("%s and %s overlap", fullName(a.Part), fullName(b.Part)))
			end
		end
		local checked = 0
		for roomId, info in INTERIOR do
			local room = plot.Rooms["Room_" .. roomId]
			local top = floorTop(room)
			local mine = {}
			for _, d in world.parts(room) do
				if d.Transparency < 1 then
					table.insert(mine, boxOf(d))
				end
			end
			local r = info.Rect
			local near_ = { X0 = r.X0 - 0.5, X1 = r.X1 + 0.5, Z0 = r.Z0 - 0.5, Z1 = r.Z1 + 0.5, Y0 = top + 0.05 }
			local theirs = {}
			for _, d in world.parts(plot.Building) do
				if d.Transparency < 1 then
					local lo, hi = localBox(d)
					if overlaps(lo, hi, near_) then
						table.insert(theirs, boxOf(d))
					end
				end
			end
			expect(#theirs > 0).toBe(true)
			for i, a in mine do
				for j = i + 1, #mine do
					check(a, mine[j])
					checked += 1
				end
				for _, b in theirs do
					check(a, b)
					checked += 1
				end
			end
		end
		expect(checked > 100).toBe(true)
	end)

	test("room floors are CeramicTiles on the slot (the Garden's is a studded lawn), ROOM_FLOOR thin", function()
		for _, room in plot.Rooms:GetChildren() do
			local roomId = room:GetAttribute("RoomId")
			local floor = room.Floor
			expect(room.PrimaryPart).toBe(floor)
			local slot = plot.Slots["RoomSlot_" .. RoomsData[roomId].Slot]
			expect((floor.Position - slot.Position).Magnitude < EPS).toBe(true)
			local lo, hi = localBox(floor)
			expect(near(lo.Y, 0) and hi.Y <= 0.3).toBe(true) -- on the Building's ground floor (slab top 0) or the pad
			if roomId == "Garden" then
				expect(floor.Color).toBe(WORLD.GrassA)
				expect(floor:GetAttribute("Studded")).toBe(true)
			else
				expect(floor.Material).toBe(Enum.Material.CeramicTiles)
				expect(floor.Color).toBe(WORLD.FloorTile)
			end
		end
	end)

	test("the Cozy Ward: ExamBay_W1 and ExamBay_W2 to contract C2, on Building's bays", function()
		local ward = plot.Rooms.Room_Ward
		local top = floorTop(ward)
		local found = 0
		for _, bay in Building.BAYS do
			if bay.Room == "Ward" then
				found += 1
				local m = ward:FindFirstChild("ExamBay_" .. bay.Id)
				expect(m ~= nil and m.ClassName == "Model").toBe(true)
				expect(m:GetAttribute("Bay")).toBe(bay.Id)
				expect(m:GetAttribute("Kind")).toBe(bay.Kind)
				expect(m:GetAttribute("Opens")).toBe(bay.Opens)
				expect(m:GetAttribute("Face")).toBe(bay.Face)
				expect(m:GetAttribute("Open")).toBe(true)
				for _, name in { "Bed", "DoctorSpot", "Curtain", "Tray", "Sign" } do
					local child = m:FindFirstChild(name)
					if not (child and child:IsA("BasePart")) then
						error("ExamBay_" .. bay.Id .. " has no " .. name)
					end
				end
				-- the bed: inside Building.bayBed, the patient sits on its top
				local rect = Building.bayBed(bay)
				for _, d in world.parts(m) do
					if d.Name == "Bed" or d.Name == "Frame" or d.Name == "Headboard" then
						local lo, hi = localBox(d)
						if
							lo.X < rect.X0 - EPS
							or hi.X > rect.X1 + EPS
							or lo.Z < rect.Z0 - EPS
							or hi.Z > rect.Z1 + EPS
						then
							error("ExamBay_" .. bay.Id .. "." .. d.Name .. " is off Building.bayBed")
						end
					end
				end
				local _, bedHi = localBox(m.Bed)
				expect(bedHi.Y - top >= 1.2 and bedHi.Y - top <= 2.5).toBe(true)
				expect(m.Bed.CanCollide).toBe(true)
				-- the DoctorSpot: at Building.doctorSpot, on the floor, facing the bed
				local spot = Building.doctorSpot(bay)
				local at = pivot:PointToObjectSpace(m.DoctorSpot.Position)
				expect(near(at.X, spot.X) and near(at.Z, spot.Z)).toBe(true)
				expect(near(localBox(m.DoctorSpot).Y, top)).toBe(true)
				expect(m.DoctorSpot.Transparency).toBe(1)
				local look = pivot:VectorToObjectSpace(m.DoctorSpot.CFrame.LookVector)
				local bed = pivot:PointToObjectSpace(m.Bed.Position)
				expect(look.X * (bed.X - at.X) + look.Z * (bed.Z - at.Z) > 0).toBe(true)
				-- the Bed's LookVector points at its foot, where the DoctorSpot is (as the Building's couches)
				local bedLook = pivot:VectorToObjectSpace(m.Bed.CFrame.LookVector)
				expect(bedLook.X * (at.X - bed.X) + bedLook.Z * (at.Z - bed.Z) > 0).toBe(true)
				-- the curtain is soft (patients and the doctor pass it), the sign shows the bay's id
				expect(m.Curtain.CanCollide).toBe(false)
				expect(m.Sign.SignGui.Text.Text).toBe(RoomsData.Ward.Icon .. " " .. found) -- "🛏️ 1": bed 1
				-- made like bays 1-6: the Bed is the couch (one block on the floor, the whole of Building.bayBed, its
				-- top at the Building's COUCH), with a Pillow; no Frame or Headboard
				local bLo, bHi = localBox(m.Bed)
				expect(near(bLo.Y, top) and near(bHi.Y - top, PlotBuilder.Pure.COUCH)).toBe(true)
				expect(near(bLo.X, rect.X0) and near(bHi.X, rect.X1)).toBe(true)
				expect(near(bLo.Z, rect.Z0) and near(bHi.Z, rect.Z1)).toBe(true)
				expect(m:FindFirstChild("Pillow") ~= nil).toBe(true)
				expect(m:FindFirstChild("Frame")).toBeNil()
				expect(m:FindFirstChild("Headboard")).toBeNil()
				-- the sign is upright, flat on the wall at the bed's head, its letters toward the room (and its door)
				local sLo, sHi = localBox(m.Sign)
				expect(near(sHi.Z, rect.Z1) and sHi.Z - sLo.Z <= 0.2).toBe(true)
				local look = pivot:VectorToObjectSpace(m.Sign.CFrame.LookVector)
				local up = pivot:VectorToObjectSpace(m.Sign.CFrame.UpVector)
				expect(near(look.Z, -1) and near(up.Y, 1)).toBe(true)
				expect(m.Sign.SignGui.Face).toBe(Enum.NormalId.Front)
			end
		end
		expect(found).toBe(2)
		-- its beds aren't recovery beds: nothing in the ward is named Bed_<n>
		for _, d in ward:GetDescendants() do
			expect(string.match(d.Name, "^Bed_%d+$")).toBeNil()
		end
	end)

	test("the patients' ways in each room: from its door to each bay's DoctorSpot and to each bed's foot", function()
		for roomId, info in INTERIOR do
			local room = plot.Rooms["Room_" .. roomId]
			local inner = Building.doorPoints(info.Door)
			local targets = {}
			for _, d in room:GetDescendants() do
				if d.Name == "DoctorSpot" then
					table.insert(targets, pivot:PointToObjectSpace(d.Position))
				elseif string.match(d.Name, "^Bed_%d+$") then
					-- Patients.bedFoot: on the floor just past the foot of the mattress
					table.insert(
						targets,
						pivot:PointToObjectSpace((d.CFrame * CFrame.new(0, 0, -d.Size.Z / 2 - 1.6)).Position)
					)
				end
			end
			for _, target in targets do
				local hits = blockers(world.parts(room), point(inner), Vector3.new(target.X, 0, target.Z), 0.3)
				if #hits > 0 then
					error(roomId .. ": the way in crosses " .. table.concat(hits, ", "))
				end
			end
		end
	end)

	test("the rooms' stations: Station_Bath and Station_Cocoa, open; no room builds the Building's stations", function()
		local bath = plot.Rooms.Room_BathRoom.Station_Bath
		local cocoa = plot.Rooms.Room_WinterWing.Station_Cocoa
		for id, station in { Bath = bath, Cocoa = cocoa } do
			expect(station:GetAttribute("Open")).toBe(true)
			expect(station:GetAttribute("StationId")).toBe(id)
			expect(station.IconGui ~= nil).toBe(true)
		end
		expect(bath.Color).toBe(WORLD.Trim)
		expect(cocoa.Color).toBe(ACCENT.Orange)
		for _, room in plot.Rooms:GetChildren() do
			for _, d in room:GetDescendants() do
				local id = string.match(d.Name, "^Station_(%w+)$")
				if id and Building.STATIONS[id] then
					error(room.Name .. " builds the Building's " .. d.Name)
				end
			end
		end
	end)

	test(
		"the Winter Wing: Bed_1's head on the back wall in a corner, the fireplace glowing, the cocoa by a wall",
		function()
			local winter = plot.Rooms.Room_WinterWing
			local fLo, fHi = localBox(winter.Floor)
			-- the bed: its pillow end (+z, Server/Patients) against the back wall, its side against a side wall
			local _, headHi = localBox(winter.Headboard)
			local frameLo, frameHi = localBox(winter.Frame)
			expect(near(headHi.Z, fHi.Z)).toBe(true)
			expect(near(frameLo.X, fLo.X) or near(frameHi.X, fHi.X)).toBe(true)
			expect(winter.Headboard.Size.Y <= 3).toBe(true) -- a normal headboard
			-- the fireplace: against the back wall, a Neon flame with one warm, shadowless PointLight, and a rug
			local _, fireHi = localBox(winter.Fireplace)
			expect(near(fireHi.Z, fHi.Z)).toBe(true)
			expect(winter.Fireplace:GetAttribute("Studded")).toBe(true)
			expect(winter.Flame.Material).toBe(Enum.Material.Neon)
			local light = winter.Flame.FireGlow:FindFirstChildWhichIsA("PointLight")
			expect(light ~= nil and light.Shadows == false and light.Range <= 16).toBe(true)
			expect(winter.Rug ~= nil).toBe(true)
			-- the cocoa: a small table flush to a side wall, its front (LookVector) into the room
			local cocoa = winter.Station_Cocoa
			local cLo, cHi = localBox(cocoa)
			expect(near(cLo.X, fLo.X) or near(cHi.X, fHi.X)).toBe(true)
			expect(cocoa.Size.X * cocoa.Size.Z <= 6 + EPS).toBe(true)
			local look = pivot:VectorToObjectSpace(cocoa.CFrame.LookVector)
			local mid = (fLo + fHi) / 2
			local at = pivot:PointToObjectSpace(cocoa.Position)
			expect(look.X * (mid.X - at.X) + look.Z * (mid.Z - at.Z) > 0).toBe(true)
		end
	)

	test("the Bath Room: the tub on its tiles against the back wall, its water and bubbles ON it", function()
		local bath = plot.Rooms.Room_BathRoom
		local _, fHi = localBox(bath.Floor)
		local tLo, tHi = localBox(bath.Station_Bath)
		local _, tilesHi = localBox(bath.Tiles)
		expect(near(tilesHi.Z, fHi.Z) and bath.Tiles.Material == Enum.Material.CeramicTiles).toBe(true)
		expect(near(tHi.Z, tilesHi.Z - bath.Tiles.Size.Z)).toBe(true)
		local wLo = localBox(bath.Water)
		expect(near(wLo.Y, tHi.Y)).toBe(true) -- on the tub's top, never inside it
		local bubbles = 0
		for _, d in bath:GetChildren() do
			if d.Name == "Bubble" then
				bubbles += 1
			end
		end
		expect(bubbles >= 1).toBe(true)
		expect(bath:FindFirstChild("Towel") ~= nil and bath:FindFirstChild("Shelf") ~= nil).toBe(true)
		expect(tLo.Y >= floorTop(bath) - EPS).toBe(true)
	end)

	test("recovery beds are 3 parts (Frame, studded Headboard, the mattress Bed_<n>): the Winter Wing's one", function()
		local total = 0
		for _, room in plot.Rooms:GetChildren() do
			local beds, frames, heads = 0, 0, 0
			for _, d in room:GetChildren() do
				if string.match(d.Name, "^Bed_%d+$") then
					beds += 1
					expect(d.Color).toBe(WORLD.Trim)
					expect(d.Size).toEqual(Vector3.new(4, 1, 6.6)) -- patients lie on it exactly as before
				elseif d.Name == "Frame" then
					frames += 1
				elseif d.Name == "Headboard" then
					heads += 1
					expect(d:GetAttribute("Studded")).toBe(true)
					expect(whole(d.Size.X) and whole(d.Size.Z)).toBe(true)
				end
			end
			expect(frames).toBe(beds)
			expect(heads).toBe(beds)
			total += beds
		end
		expect(total).toBe(1)
		expect(plot.Rooms.Room_WinterWing:FindFirstChild("Bed_1") ~= nil).toBe(true)
	end)

	test("decor slots: Data/Rooms' count in every room, on its floor, inside it", function()
		for _, room in plot.Rooms:GetChildren() do
			local roomId = room:GetAttribute("RoomId")
			local top = floorTop(room)
			local fLo, fHi = localBox(room.Floor)
			for n = 1, RoomsData[roomId].DecorSlots do
				local slot = room:FindFirstChild("DecorSlot_" .. n)
				expect(slot ~= nil).toBe(true)
				local lo, hi = localBox(slot)
				expect(near(lo.Y, top)).toBe(true)
				expect(lo.X >= fLo.X - EPS and hi.X <= fHi.X + EPS and lo.Z >= fLo.Z - EPS and hi.Z <= fHi.Z + EPS).toBe(
					true
				)
			end
			expect(room:FindFirstChild("DecorSlot_" .. RoomsData[roomId].DecorSlots + 1)).toBeNil()
		end
	end)

	test(
		"the Garden: a studded lawn, studded hedges and an arbor with its name; overhead parts are ray-ignored",
		function()
			local garden = plot.Rooms.Room_Garden
			local hedges, posts = 0, 0
			for _, d in garden:GetChildren() do
				if d.Name == "BackHedge" or d.Name == "SideHedge" then
					hedges += 1
					expect(d:GetAttribute("Studded")).toBe(true)
				elseif d.Name == "ArborPost" then
					posts += 1
				end
			end
			expect(hedges).toBe(3)
			expect(posts).toBe(2)
			expect(string.find(garden.ArborBeam.NameGui.Text.Text, "Sunny Garden", 1, true) ~= nil).toBe(true)
			local overhead = 0
			for _, d in plot.Rooms:GetDescendants() do
				if d:IsA("BasePart") then
					local lo = localBox(d)
					if lo.Y > 6 then
						overhead += 1
						expect(d.CanQuery).toBe(false)
						expect(d.CanCollide).toBe(false)
					end
				end
			end
			expect(overhead >= 1).toBe(true)
		end
	)
end)

------------------------------------------------------------------------------------------------------------------
T.describe("Plot and rooms: the look's rules", function()
	test("studded parts sit on whole studs (X and Z), the Props pieces aside", function()
		local _, propsParts = piecesOn(plot)
		local studded = 0
		for _, d in plotParts(plot) do
			if d:GetAttribute("Studded") == true and not propsParts[d] then
				studded += 1
				if not (whole(d.Size.X) and whole(d.Size.Z)) then
					error(string.format("%s is %.2f x %.2f", fullName(d), d.Size.X, d.Size.Z))
				end
			end
		end
		expect(studded > 10).toBe(true)
	end)

	test(
		"no big face at V >= 0.95 (the plot's own colour and see-through ghosts aside), no channel above 245",
		function()
			PlotBuilder.setPreview(W.plots[2], "A", "BathRoom") -- a for-sale preview too
			for _, p in W.plots do
				local accent = p:GetAttribute("Accent")
				for _, d in plotParts(p) do
					if d.Transparency < 0.5 and d.Color ~= WORLD.Lamp then
						local _, _, v = Look.hsv(d.Color)
						if Look.isBigFace(d, 16) and v >= 0.95 and d.Color ~= accent then
							error(string.format("%s: V %.2f on a big face", fullName(d), v))
						end
						if Look.maxChannel(d.Color) > 245 then
							error(fullName(d) .. " has a channel above 245")
						end
					end
				end
			end
			PlotBuilder.setPreview(W.plots[2], "A", nil)
		end
	)

	test(
		"Variant mode: the Pad, the CounterTop, the headboard and the fireplace are CureStuds on every face",
		function()
			local V = build(true)
			local p = V.plots[1]
			V.PlotBuilder.placeRoom(p, "WinterWing")
			local name = Config.Look.StudsVariant
			local winter = p.Rooms.Room_WinterWing
			for _, part in { p.Ground.Pad, p.Scenery.CounterTop, winter.Headboard, winter.Fireplace } do
				expect(part.MaterialVariant).toBe(name)
				expect(part.Material).toBe(Enum.Material.Plastic)
				expect(part.TopSurface).toBe(Enum.SurfaceType.Smooth)
			end
		end
	)
end)

------------------------------------------------------------------------------------------------------------------
T.describe("PlotBuilder's API, as before", function()
	local other = W.plots[2]

	test("setPreview: a ghost floor, a dashed outline and the price on a navy plate; nil removes it", function()
		PlotBuilder.setPreview(other, "A", "BathRoom")
		local preview = other.Slots.RoomSlot_A.Preview
		expect(preview.Fill.Transparency).toBe(0.65)
		local dashes = 0
		for _, d in preview:GetChildren() do
			if d.Name == "Dash" then
				dashes += 1
			end
		end
		expect(dashes > 8).toBe(true)
		local gui = preview.BadgeAnchor.PreviewGui
		expect(gui.Plate.BackgroundColor3).toBe(Palette.Navy)
		expect(gui.Cost.Text).toBe("⭐10  💰150")
		PlotBuilder.setPreview(other, "A", nil)
		expect(other.Slots.RoomSlot_A:FindFirstChild("Preview")).toBeNil()
	end)

	test("placeRoom: Floor on the slot, the preview gone, once only", function()
		PlotBuilder.setPreview(other, "A", "BathRoom")
		local room = PlotBuilder.placeRoom(other, "BathRoom")
		expect(other.Slots.RoomSlot_A:FindFirstChild("Preview")).toBeNil()
		expect((room.Floor.Position - other.Slots.RoomSlot_A.Position).Magnitude < EPS).toBe(true)
		expect(room:GetAttribute("RoomId")).toBe("BathRoom")
		expect(room.ModelStreamingMode).toBe(Enum.ModelStreamingMode.Atomic)
		expect(PlotBuilder.placeRoom(other, "BathRoom")).toBe(room)
		expect(PlotBuilder.buildRoom("Ward").PrimaryPart.Name).toBe("Floor")
	end)

	test("clearPlot: every room but the Stand goes, and the Building is Lv 1's", function()
		PlotBuilder.clearPlot(plot)
		local names = {}
		for _, room in plot.Rooms:GetChildren() do
			table.insert(names, room.Name)
		end
		expect(names).toEqual({ "Room_Stand" })
		expect(plot:GetAttribute("Level")).toBe(1)
	end)
end)

------------------------------------------------------------------------------------------------------------------
T.describe("DecorBuilder: the look, no new parts", function()
	local DecorBuilder = world.load("src/server/DecorBuilder.luau")
	local DecorData = world.load("src/shared/Data/Decor.luau")

	-- Each decor's part count before the look overhaul (measured 2026-11-17): none may grow.
	local BEFORE = {
		PottedFern = 12,
		CozyRug = 9,
		BubbleLamp = 7,
		BalloonBunch = 15,
		ToyShelf = 18,
		FishBowl = 10,
		FlowerArch = 20,
		HeartRug = 6,
		RubberDuckFountain = 11,
		SnowGlobeLamp = 11,
		MoonLantern = 11,
		SproutMascot = 13,
		LuckyKettle = 15,
		CometLantern = 12,
		PlasterRug = 9,
		HeartLamp = 7,
		StarFountain = 11,
		RainbowArch = 20,
		MoonGlobe = 11,
		GoldenStatue = 13,
		FriendBench = 14,
		InternRug = 9,
		ResidentFern = 12,
		DoctorLantern = 10,
		SeniorBench = 14,
		ChiefArch = 20,
		LegendStatue = 13,
		SunflowerArch = 20,
		CloudSwing = 14,
		TrophyCup = 13,
		TrophyStar = 13,
		TrophyGlobe = 11,
		TrophyRocket = 13,
		TrophyCrown = 13,
	}
	local TOPS = { Balloons = "Box", Shelf = "Top", Bench = "Seat" }

	test("it no longer requires PlotBuilder (its lamps are World/NightLights')", function()
		local source = fs.readFile(World.find("src/server/DecorBuilder.luau"))
		expect(string.find(source, "require(script.Parent.PlotBuilder)", 1, true)).toBeNil()
	end)

	test("no decor gains a part; every colour is the world's (no channel above 245, the lamps' glow aside)", function()
		for _, decorId in DecorData.Order do
			local model = DecorBuilder.build(decorId)
			local n = #world.parts(model)
			local before = BEFORE[decorId] or 25
			if n > before then
				error(decorId .. ": " .. n .. " parts, " .. before .. " before")
			end
			for _, part in world.parts(model) do
				if part.Color ~= WORLD.Lamp and Look.maxChannel(part.Color) > 245 then
					error(decorId .. "." .. part.Name .. " has a channel above 245")
				end
			end
		end
	end)

	test("the top parts are studded on whole studs; a glowing decor is a NightLights lamp", function()
		local checked = 0
		for _, decorId in DecorData.Order do
			local look = DecorData[decorId].Look
			local model = DecorBuilder.build(decorId)
			local topName = TOPS[look.Kind]
			if topName then
				local top = model:FindFirstChild(topName)
				expect(top:GetAttribute("Studded")).toBe(true)
				expect(whole(top.Size.X) and whole(top.Size.Z)).toBe(true)
				checked += 1
			end
			if look.Glow then
				local lamps = 0
				for _, part in world.parts(model) do
					if part:GetAttribute("NightKind") == "Lamp" then
						lamps += 1
					end
				end
				expect(lamps >= 1).toBe(true)
			end
		end
		expect(checked >= 3).toBe(true)
	end)
end)
