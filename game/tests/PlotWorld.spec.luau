--!nocheck
-- The plot and its rooms (look build plan §B6 "T4's side", §D T4): the REAL PlotBuilder and DecorBuilder built under
-- tests/worldmock, checked against the plan's contract.
--   · the budget: every room together <= Config.Look.RoomParts and the plot's own share <= Config.Look.PlotParts at
--     Lv 5 with every room. The plot's trees, bushes and fences are World/Props' (T2): this spec counts each of them
--     at its CONTRACT maximum (tree 7, bush 1, fence 2 + floor(length / 14) + 1), so the share holds whatever Props
--     builds, and prints the measured share beside it
--   · the dark studded Pad and its Slate Edges, the Counter (studded top, our paw-heart, no cross), the floating sign
--   · the Stand's spots are Shared/Logic/Building's, and the Stand has no shell
--   · nothing of the plot's own on the Counter, the queue lane, the gate's mouth, the walkways or the building's
--     footprint; the trees and bushes off the room slots and the ambulance bay; the patients' ways to the room beds
--     and out through PatientExit stay open
--   · the queue lane: 6 mid-tone tiles, the numbers on their spot discs at PlotBuilder.queueSpot
--   · the annexes and the Garden; 3-part beds; studs on whole studs, in both studs modes
--   · the palette: no Texture or Decal, no big face at V >= 0.95 (the plot's own colour aside), no channel above 245
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
local PLOT_HALF = Config.Town.PlotSize / 2 -- 40: the plot's front edge is z -40, its front fence z -39.6
-- Server/Patients' walkways (makeNav: halfway between the Stand's slot edge, x ±15, and the side rooms', x ±20)
local WALKWAY = 17.5

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
T.describe("Plot: the ground, the Counter and the sign", function()
	test("the Pad is dark and studded on whole odd studs; four Slate Edges frame it to the plot's edge", function()
		local ground = plot.Ground
		expect(ground.ClassName).toBe("Model")
		local pad = ground.Pad
		expect(pad.Color).toBe(WORLD.Pad)
		expect(pad:GetAttribute("Studded")).toBe(true)
		expect(pad.Material).toBe(Enum.Material.Plastic)
		expect(pad.TopSurface).toBe(Enum.SurfaceType.Studs) -- Surface mode: no CureStuds variant in this world
		expect(pad.Size.X).toBe(pad.Size.Z)
		expect(whole(pad.Size.X) and pad.Size.X % 2 == 1).toBe(true)
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
		local half = Config.Town.PlotSize / 2
		expect(near(lo.X, -half) and near(hi.X, half) and near(lo.Z, -half) and near(hi.Z, half)).toBe(true)
		expect(hi.Y > 0 and hi.Y <= 0.2).toBe(true) -- a stone lip just proud of the pad
	end)

	test("every plot's Ground is a Model named Ground (Patients' and Nurses' rays include it)", function()
		for _, p in W.plots do
			expect(p.Ground ~= nil and p.Ground.Pad ~= nil).toBe(true)
			expect(p.Ground.Pad.CanCollide).toBe(true)
		end
	end)

	test("the Counter: the plot's colour, a studded warm-white top on whole studs, our paw-heart, no cross", function()
		local accent = plot:GetAttribute("Accent")
		expect(plot.Counter.Color).toBe(accent)
		expect(plot.Counter.Material).toBe(Enum.Material.SmoothPlastic)
		expect(plot.Counter.CanCollide).toBe(true)
		local top = plot.Scenery.CounterTop
		expect(top:GetAttribute("Studded")).toBe(true)
		expect(top.Color).toBe(WORLD.Trim)
		expect(whole(top.Size.X) and whole(top.Size.Z)).toBe(true)
		local gui = plot.Counter.DeskGui
		expect(gui.Face).toBe(Enum.NormalId.Front)
		expect(gui.MaxDistance > 0).toBe(true)
		expect(gui:FindFirstChild("PawHeart", true) ~= nil).toBe(true)
		-- the desk faces the street: its Front face's normal is the plot's -z
		local front = pivot:VectorToObjectSpace(plot.Counter.CFrame.LookVector)
		expect(front.Z).toBeCloseTo(-1, 3)
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
		-- the letters clear the 3-stud fence in front of them; two studded posts in the plot's colour hold them
		local lo = localBox(sign)
		expect(lo.Y >= 3.5).toBe(true)
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
T.describe("Plot: the Stand at Shared/Logic/Building's spots", function()
	local stand = plot.Rooms.Room_Stand

	local function spotOf(part)
		return pivot:PointToObjectSpace(part.Position)
	end

	test("Remedy, Plaster, Bed_1, both decor slots and the MascotSpot", function()
		local s = Building.STAND
		for name, spot in { Station_Remedy = s.Remedy, Station_Plaster = s.Plaster, Bed_1 = s.Bed } do
			local at = spotOf(stand[name])
			if not (near(at.X, spot.X) and near(at.Z, spot.Z)) then
				error(string.format("%s at (%.2f, %.2f), not (%.2f, %.2f)", name, at.X, at.Z, spot.X, spot.Z))
			end
		end
		for index, spot in s.Decor do
			local at = spotOf(stand["DecorSlot_" .. index])
			expect(near(at.X, spot.X) and near(at.Z, spot.Z)).toBe(true)
		end
		local mascot = spotOf(plot.MascotSpot)
		expect(near(mascot.X, s.Mascot.X) and near(mascot.Z, s.Mascot.Z)).toBe(true)
		expect(near(localBox(plot.MascotSpot).Y, 0)).toBe(true) -- it rests on the pad
	end)

	test("decor slot 2 stands on the front pad; slot 1 on the Stand's floor", function()
		local floorTop = select(2, localBox(stand.Floor)).Y
		expect(near(localBox(stand.DecorSlot_2).Y, 0)).toBe(true)
		expect(near(localBox(stand.DecorSlot_1).Y, floorTop)).toBe(true)
		-- each slot's spot lies on what the slot stands on
		local spots = {}
		for _, child in stand:GetChildren() do
			if child.Name == "DecorSpot" then
				table.insert(spots, (localBox(child)).Y)
			end
		end
		table.sort(spots)
		expect(#spots).toBe(2)
		expect(near(spots[1], 0) and near(spots[2], floorTop)).toBe(true)
	end)

	test("the Stand has no shell: nothing above the stations, and no wall, roof, awning or plaque", function()
		for _, d in stand:GetDescendants() do
			if d:IsA("BasePart") then
				local _, hi = localBox(d)
				if hi.Y > 5.5 then
					error(d.Name .. " reaches y " .. hi.Y)
				end
				for _, word in { "Wall", "Roof", "Awning", "Plaque", "Post" } do
					expect(string.find(d.Name, word, 1, true)).toBeNil()
				end
			end
		end
	end)

	test("Remedy's table ends short of the lift shaft's face; the tops are studded on whole studs", function()
		local tops = 0
		for _, d in stand:GetChildren() do
			if d.Name == "Top" or d.Name == "Station_Remedy" then
				local lo = localBox(d)
				expect(lo.X >= Building.SHAFT.X1 - EPS).toBe(true)
			end
			if d.Name == "Top" then
				tops += 1
				expect(d:GetAttribute("Studded")).toBe(true)
				expect(whole(d.Size.X) and whole(d.Size.Z)).toBe(true)
			end
		end
		expect(tops).toBe(2)
	end)
end)

------------------------------------------------------------------------------------------------------------------
T.describe("Plot: clearances", function()
	local laneLo, laneHi
	for _, d in plot.QueueLane:GetDescendants() do
		if d:IsA("BasePart") then
			local a, b = localBox(d)
			laneLo = if laneLo then laneLo:Min(a) else a
			laneHi = if laneHi then laneHi:Max(b) else b
		end
	end

	-- Parts that can be in the way: the plot's own (Ground and invisible markers aside).
	local function solidish()
		local out = {}
		for _, d in plotParts(plot) do
			if not inside(d, "Ground") and d.Transparency < 1 then
				table.insert(out, d)
			end
		end
		return out
	end

	test("nothing of the plot's own in the building's footprint but the Stand", function()
		local foot = Building.footprint(5, 0)
		local zone = { X0 = foot.X0, X1 = foot.X1, Z0 = foot.Z0, Z1 = foot.Z1 }
		for _, d in solidish() do
			if not d:FindFirstAncestor("Room_Stand") then
				local lo, hi = localBox(d)
				if overlaps(lo, hi, zone) then
					error(fullName(d) .. " is in the building's footprint")
				end
			end
		end
	end)

	test("nothing stands on the Counter, the queue lane or the gate's mouth (where creatures stand)", function()
		local zones = {
			Counter = {
				X0 = -6.5,
				X1 = 6.5,
				Z0 = -16,
				Z1 = -13,
				Y0 = 0.5,
				Allow = { Counter = true, CounterTop = true },
			},
			Lane = {
				X0 = laneLo.X,
				X1 = laneHi.X,
				Z0 = laneLo.Z,
				Z1 = math.min(laneHi.Z, -16),
				Y0 = 0.5,
				Y1 = 5.5,
			},
			Gate = { X0 = -5.5, X1 = 5.5, Z0 = -PLOT_HALF, Z1 = -PLOT_HALF + 2, Y0 = 0.5, Y1 = 5.5 },
		}
		for name, zone in zones do
			for _, d in solidish() do
				if not inside(d, "QueueLane") and not (zone.Allow and zone.Allow[d.Name]) then
					local lo, hi = localBox(d)
					if overlaps(lo, hi, zone) then
						error(fullName(d) .. " is on the " .. name)
					end
				end
			end
		end
	end)

	test("the walkways (x = ±17.5) are clear from the line to the back of the block", function()
		for _, side in { -1, 1 } do
			local x = side * WALKWAY
			local zone = { X0 = x - 1, X1 = x + 1, Z0 = -18, Z1 = 14, Y0 = 0.7, Y1 = 7 }
			for _, d in solidish() do
				if d.CanCollide then
					local lo, hi = localBox(d)
					if overlaps(lo, hi, zone) then
						error(fullName(d) .. " is on the walkway at x " .. x)
					end
				end
			end
		end
	end)

	-- The segment a -> b (plot-local x, z) against a box grown by `margin`, at walking height.
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

	test("patients' ways to every room bed stay open (Patients' bedRoute: the walkway, then straight in)", function()
		local laneZ = pivot:PointToObjectSpace(plot.QueueStart.Position).Z
		local beds = 0
		for _, room in plot.Rooms:GetChildren() do
			if room.Name ~= "Room_Stand" then
				for _, bed in room:GetChildren() do
					if string.match(bed.Name, "^Bed_%d+$") then
						beds += 1
						-- Patients.bedFoot: on the floor just past the foot of the mattress
						local foot =
							pivot:PointToObjectSpace((bed.CFrame * CFrame.new(0, 0, -bed.Size.Z / 2 - 1.6)).Position)
						local x = if foot.X < 0 then -WALKWAY else WALKWAY
						local route = { Vector3.new(x, 0, laneZ), Vector3.new(x, 0, foot.Z), foot }
						for _, other in plot.Rooms:GetDescendants() do
							if other:IsA("BasePart") and other.CanCollide and other.Name ~= "Floor" then
								local lo, hi = localBox(other)
								if hi.Y > 1 and lo.Y < 4 then
									for i = 1, #route - 1 do
										if crosses(route[i], route[i + 1], lo, hi, 0.5) then
											error(room.Name .. "." .. bed.Name .. ": its way crosses " .. other.Name)
										end
									end
								end
							end
						end
					end
				end
			end
		end
		expect(beds).toBe(3) -- the Cozy Ward's 2 and the Winter Wing's 1
	end)

	test("the trees and bushes stay off the room slots and the ambulance bay (as built at Lv 5)", function()
		local zones = {}
		for _, slot in plot.Slots:GetChildren() do
			local lo, hi = localBox(slot)
			zones[slot.Name] = { X0 = lo.X, X1 = hi.X, Z0 = lo.Z, Z1 = hi.Z }
		end
		local bay = plot.Building:FindFirstChild("BayFloor", true)
		expect(bay ~= nil).toBe(true)
		local bayLo, bayHi = localBox(bay)
		zones.AmbulanceBay = { X0 = bayLo.X, X1 = bayHi.X, Z0 = bayLo.Z, Z1 = bayHi.Z }
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

	test("the patients' ways along the line and out through PatientExit stay open (Patients' exitRoute)", function()
		local laneZ = pivot:PointToObjectSpace(plot.QueueStart.Position).Z
		local exit = pivot:PointToObjectSpace(plot.PatientExit.Position)
		local counter = plot.Counter
		local sideStep = math.abs(pivot:PointToObjectSpace(counter.Position).X) + counter.Size.X / 2 + 1.6
		local legs = {
			{ Vector3.new(-WALKWAY, 0, laneZ), Vector3.new(WALKWAY, 0, laneZ) }, -- from the line to either walkway
			{ Vector3.new(WALKWAY, 0, laneZ), Vector3.new(exit.X, 0, exit.Z) }, -- down the right walkway and out
			{ Vector3.new(sideStep, 0, laneZ), Vector3.new(exit.X, 0, exit.Z) }, -- round the Counter and out
		}
		for _, d in plotParts(plot) do
			if d.CanCollide and not inside(d, "Ground") then
				local lo, hi = localBox(d)
				if hi.Y > 1 and lo.Y < 4 then
					for _, leg in legs do
						if crosses(leg[1], leg[2], lo, hi, 0.5) then
							error(fullName(d) .. " is in the patients' way")
						end
					end
				end
			end
		end
	end)
end)

------------------------------------------------------------------------------------------------------------------
T.describe("Plot: the queue lane", function()
	local lane = plot.QueueLane
	local accent = plot:GetAttribute("Accent")

	test("6 tiles in the two mid-tones, an edge in the plot's colour each side, nothing else but the spots", function()
		local tiles, edges, spots, other = 0, 0, 0, 0
		for _, d in lane:GetChildren() do
			if d.Name == "LaneTile" then
				tiles += 1
				expect(d.Color == WORLD.Pavement or d.Color == WORLD.PavementAlt).toBe(true)
			elseif d.Name == "LaneEdge" then
				edges += 1
				expect(d.Color).toBe(accent)
			elseif d.Name == "LaneSpot" then
				spots += 1
			else
				other += 1
			end
			expect(d.CanCollide).toBe(false)
			expect(d.CanQuery).toBe(false)
		end
		expect(tiles).toBe(6)
		expect(edges).toBe(2)
		expect(spots).toBe(Config.MaxQueue)
		expect(other).toBe(0)
	end)

	test("each place in line has its disc at PlotBuilder.queueSpot, its number floating on it, upright", function()
		local discs = {}
		for _, d in lane:GetChildren() do
			if d.Name == "LaneSpot" then
				table.insert(discs, d)
			end
		end
		for index = 1, Config.MaxQueue do
			local spot =
				pivot:PointToObjectSpace(PlotBuilder.queueSpot(plot.QueueStart, plot.PatientSpawn, index).Position)
			local found = nil
			for _, disc in discs do
				local at = pivot:PointToObjectSpace(disc.Position)
				if near(at.X, spot.X) and near(at.Z, spot.Z) then
					found = disc
				end
			end
			expect(found ~= nil).toBe(true)
			expect(found.Color).toBe(accent)
			local gui = found.NumberGui
			expect(gui.Face).toBe(Enum.NormalId.Right)
			expect(gui.Number.Text).toBe(tostring(index))
			expect(gui.Number.BackgroundTransparency).toBe(1)
			-- the face the number is on looks up, and the number's top points at the Counter (+z on the plot)
			local faceOut = pivot:VectorToObjectSpace(found.CFrame.RightVector)
			local numberUp = pivot:VectorToObjectSpace(found.CFrame.UpVector)
			expect(faceOut.Y).toBeCloseTo(1, 3)
			expect(numberUp.Z).toBeCloseTo(1, 3)
		end
	end)

	test("the lane runs from just in front of the Counter to inside the gate", function()
		local lo, hi
		for _, d in lane:GetChildren() do
			local a, b = localBox(d)
			lo = if lo then lo:Min(a) else a
			hi = if hi then hi:Max(b) else b
		end
		expect(hi.Z <= -15.7 and hi.Z >= -16.5).toBe(true) -- the Counter's face is at z -15.7
		expect(lo.Z >= -PLOT_HALF + 0.4).toBe(true) -- inside the front fence (z = -39.6)
		expect(hi.Y <= 0.4).toBe(true) -- flat paint: creatures stand on it
	end)
end)

------------------------------------------------------------------------------------------------------------------
T.describe("Rooms: the annexes, the Garden and the beds", function()
	local ROOM_COLOUR = { BathRoom = ACCENT.Cyan, Ward = ACCENT.Purple, WinterWing = ACCENT.Blue }

	test(
		"Bath Room, Cozy Ward and Winter Wing: 3 studded walls in the room colour, a dark roof, an open front",
		function()
			for roomId, colour in ROOM_COLOUR do
				local room = plot.Rooms["Room_" .. roomId]
				local floor = room.Floor
				expect(floor.Material).toBe(Enum.Material.WoodPlanks)
				expect(floor.Color).toBe(WORLD.FloorA)
				local roomPivot = floor.CFrame
				local walls, snow = 0, 0
				for _, d in room:GetChildren() do
					if d.Name == "BackWall" or d.Name == "SideWall" then
						walls += 1
						expect(d.Color).toBe(colour)
						expect(d:GetAttribute("Studded")).toBe(true)
						expect(d.CanCollide).toBe(true)
						expect(whole(d.Size.X) and whole(d.Size.Z)).toBe(true)
						local lining = d.LiningGui
						expect(lining.UpperWall.BackgroundColor3).toBe(WORLD.WallUpper)
						-- the open front: no wall reaches the room's front half
						local lo = world.box(d, roomPivot)
						expect(lo.Z >= -EPS).toBe(true)
					elseif d.Name == "Snow" then
						snow += 1
					end
				end
				expect(walls).toBe(3)
				expect(snow).toBe(if roomId == "WinterWing" then 1 else 0)
				local roof = room.Roof
				expect(roof.Color).toBe(WORLD.Roof)
				expect(world.box(roof, roomPivot).Z >= -0.6).toBe(true)
				local name = roof.NameGui.Text
				expect(string.find(name.Text, RoomsData[roomId].Name, 1, true) ~= nil).toBe(true)
				expect(name.BackgroundTransparency).toBe(1)
				expect(roof.NameGui:FindFirstChild("Board")).toBeNil()
				expect(room.Trim.Color).toBe(WORLD.Trim)
				-- the candy shell's pieces (a station's own TubStripe is its colour clue, and stays)
				for _, word in { "Awning", "Plaque", "StripesGui", "FloorStripe", "WallBand", "Pillow", "Blanket" } do
					for _, d in room:GetDescendants() do
						expect(string.find(d.Name, word, 1, true)).toBeNil()
					end
				end
			end
		end
	)

	test("the Garden: a studded lawn, studded hedges and an arbor with its name", function()
		local garden = plot.Rooms.Room_Garden
		expect(garden.Floor.Color).toBe(WORLD.GrassA)
		expect(garden.Floor:GetAttribute("Studded")).toBe(true)
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
	end)

	test("overhead pieces (roofs, trim, snow, the arbor's beam) are ray-ignored: no creature lands on them", function()
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
		expect(overhead >= 3 * 2 + 1).toBe(true) -- 3 roofs and trims, the snow, the beam
	end)

	test("every bed is 3 parts: a Frame, a studded Headboard and the warm-white mattress Bed_<n>", function()
		for _, room in plot.Rooms:GetChildren() do
			local roomId = room:GetAttribute("RoomId")
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
			expect(beds).toBe(RoomsData[roomId].Beds)
			expect(frames).toBe(beds)
			expect(heads).toBe(beds)
		end
	end)

	test("stations wear the world's twin of their colour; their icons keep the UI's", function()
		local remedy = plot.Rooms.Room_Stand.Station_Remedy
		expect(remedy.Color).toBe(ACCENT.Purple)
		expect(remedy.IconGui ~= nil).toBe(true)
		expect(plot.Rooms.Room_BathRoom.Station_Bath.Color).toBe(WORLD.Trim)
		expect(plot.Rooms.Room_WinterWing.Station_Cocoa.Color).toBe(ACCENT.Orange)
	end)
end)

------------------------------------------------------------------------------------------------------------------
T.describe("Plot and rooms: the look's rules", function()
	test("studded parts sit on whole studs (X and Z), the Props pieces aside (T2's)", function()
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
		expect(studded > 15).toBe(true)
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

	test("Variant mode: the Pad, the annex walls and the tops are CureStuds on every face", function()
		local V = build(true)
		local p = V.plots[1]
		V.PlotBuilder.placeRoom(p, "BathRoom")
		local name = Config.Look.StudsVariant
		for _, part in { p.Ground.Pad, p.Scenery.CounterTop, p.Rooms.Room_BathRoom.BackWall } do
			expect(part.MaterialVariant).toBe(name)
			expect(part.Material).toBe(Enum.Material.Plastic)
			expect(part.TopSurface).toBe(Enum.SurfaceType.Smooth)
		end
	end)
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
