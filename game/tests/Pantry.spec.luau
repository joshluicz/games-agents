--!nocheck
-- The pantry (memory-20261117-006, Joshua 2026-11-17: "minimise the patients walking around. yes move the hot cocoa
-- into like a pantry or something"; docs/plan/2026-11-17-simple-start-design.md §3). Hot chocolate and bath foam are
-- taken in the MAIN building: Station_Cocoa and Station_Bath are Logic/Building stations, the last two of the
-- supply wall, each open only while its room is owned (the Winter Wing, the Bath Room). The bought rooms hold no
-- station any more: they are themed recovery rooms that bring their case pools. Every save id stays (the station ids
-- Cocoa and Bath, the items Cocoa and Bubbles, the `Made:<id>` stats, the badge ids, the room ids).
--   · the numbers (Logic/Building): where the two stand, when they are open, their prompts, the walks to them
--   · the rules (Server/Patients' PURE block): Chills and Sore muscles are treatable exactly when their room is owned
--   · the built world (the real PlotBuilder and HospitalBuilder under tests/worldmock): the parts, the closed look,
--     Open following the rooms as they are bought and lost, and no Station_ part in any room
-- Run from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local Config = require("./config")
local Recipe = require("../src/shared/Logic/Recipe")
local Hospital = require("../src/shared/Logic/Hospital")
local Visit = require("../src/shared/Logic/Visit")
local B = require("../src/shared/Logic/Building")
local Cases = require("../src/shared/Data/Cases")
local Items = require("../src/shared/Data/Items")
local Tools = require("../src/shared/Data/Tools")
local Rooms = require("../src/shared/Data/Rooms")
local Badges = require("../src/shared/Data/Badges")

local LEVELS = { 1, 2, 3, 4, 5 }
local PANTRY = { Cocoa = "WinterWing", Bath = "BathRoom" } -- the station, the room that opens it
local ROOM_CASE = { Cocoa = "Chills", Bath = "SoreMuscles" }
-- Every mix of rooms a plot can own
local ROOM_SETS = {}
for _, bath in { false, true } do
	for _, winter in { false, true } do
		for _, ward in { false, true } do
			local set = {}
			if bath then
				set.BathRoom = true
			end
			if winter then
				set.WinterWing = true
			end
			if ward then
				set.Ward = true
			end
			table.insert(ROOM_SETS, set)
		end
	end
end

local function source(path: string): string
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("can't find " .. path .. " (run from game/)")
end

local function loadPure(path: string, env: { [string]: any }?): any
	local text = source(path)
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to and to > from, path .. ": no PURE block")
	local block = string.sub(text, from, to - 1) .. "\nreturn Pure\n"
	return luau.load(block, { debugName = path .. " (pure)", environment = env })()
end

-- A file's code without its comments (a source check must not trip on what a comment says).
local function code(path: string): string
	return (string.gsub(source(path), "%-%-[^\n]*", ""))
end

local function dist(a, b): number
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end

local function inside(a, b): boolean
	return a.X0 >= b.X0 - 1e-6 and a.X1 <= b.X1 + 1e-6 and a.Z0 >= b.Z0 - 1e-6 and a.Z1 <= b.Z1 + 1e-6
end

local function overlap(a, b): boolean
	return a.X0 < b.X1 - 1e-6 and b.X0 < a.X1 - 1e-6 and a.Z0 < b.Z1 - 1e-6 and b.Z0 < a.Z1 - 1e-6
end

T.describe("Pantry: the numbers (Logic/Building)", function()
	test("Cocoa and Bath are Building stations, each gated by its room (the same pairs as Data/Rooms)", function()
		for id, roomId in PANTRY do
			local station = B.STATIONS[id]
			expect(station ~= nil).toBe(true)
			expect(station.Room).toBe(roomId)
			expect(station.Opens).toBe(1) -- its room's case is a Lv 1 case: the room is the only gate
			expect(B.PANTRY_ROOMS[id]).toBe(roomId)
			-- Data/Rooms still says which room opens it (the Shop shows it), and only that room does
			expect(table.find(Rooms[roomId].Stations, id) ~= nil).toBe(true)
			for _, other in Rooms.Order do
				if other ~= roomId then
					expect(table.find(Rooms[other].Stations, id)).toBeNil()
				end
			end
		end
		expect(B.PANTRY_ORDER).toEqual({ "Cocoa", "Bath" })
		-- nothing else in the Building is room-gated, and no room lists a station the Building doesn't have
		for id, station in B.STATIONS do
			expect(station.Room).toBe(PANTRY[id])
		end
		for _, roomId in Rooms.Order do
			for _, id in Rooms[roomId].Stations do
				if not B.STATIONS[id] then
					error(roomId .. " opens " .. id .. ", which is not in the Building")
				end
			end
		end
	end)

	test("the save ids stay: the items, their stations, the Made: stats and the badge ids", function()
		expect(Items.Cocoa.Station).toBe("Cocoa")
		expect(Items.Bubbles.Station).toBe("Bath")
		expect({ Items.Cocoa.Kind, Items.Bubbles.Kind }).toEqual({ "Supply", "Supply" })
		expect(Cases.Chills.Plan[1]).toBe("Cocoa")
		expect(Cases.SoreMuscles.Plan[1]).toBe("Bubbles")
		expect({ Cases.Chills.Room, Cases.SoreMuscles.Room }).toEqual({ "WinterWing", "BathRoom" })
		local stats = {}
		for _, badge in Badges.List do
			stats[badge.Id] = badge.Stat
		end
		expect(stats.Cocoa).toBe("Made:Cocoa")
		expect(stats.Bubbles).toBe("Made:Bath")
		expect(Rooms.BathRoom ~= nil and Rooms.WinterWing ~= nil).toBe(true)
	end)

	test("closed without its room at every level, open with it at every level", function()
		for id, roomId in PANTRY do
			for _, level in LEVELS do
				expect(B.stationOpen(id, level)).toBe(false)
				expect(B.stationOpen(id, level, nil)).toBe(false)
				expect(B.stationOpen(id, level, {})).toBe(false)
				for _, rooms in ROOM_SETS do
					expect(B.stationOpen(id, level, rooms)).toBe(rooms[roomId] == true)
				end
				-- only `true` owns a room; junk never opens it
				expect(B.stationOpen(id, level, { [roomId] = 1 } :: any)).toBe(false)
				expect(B.stationOpen(id, level, "yes" :: any)).toBe(false)
			end
		end
		-- a room never changes the other stations
		for id, station in B.STATIONS do
			if not station.Room then
				for _, level in LEVELS do
					for _, rooms in ROOM_SETS do
						expect(B.stationOpen(id, level, rooms)).toBe(level >= station.Opens)
					end
				end
			end
		end
	end)

	test("where: side by side at the supply wall, beside the Bandage shelf, in nobody's way", function()
		local recess = B.ROOMS.Supply
		local last = B.stationRect("Bandage")
		-- the supply wall's last two, in PANTRY_ORDER
		local order = B.SUPPLY_ORDER
		expect({ order[#order - 1], order[#order] }).toEqual(B.PANTRY_ORDER)
		for _, id in B.PANTRY_ORDER do
			local station, body = B.STATIONS[id], B.stationRect(id)
			expect(inside(body, recess)).toBe(true)
			expect(station.Face).toBe(B.STATIONS.Bandage.Face) -- the same wall, the same way: toward the bays
			expect(body.Z0).toBeCloseTo(recess.Z0) -- its back on the dispensary's wall
			-- a full-width unit now (the old pantry's were 3.2: all the stairs' rail had)
			expect(station.Width).toBeNil()
			expect(body.X1 - body.X0).toBeCloseTo(B.STATION_SIZE.Width)
			expect(body.Z1 - body.Z0).toBeCloseTo(B.STATION_SIZE.Depth)
			-- never in a bought room, a corridor's walkway or the X-ray room
			for _, room in { "BathRoom", "WinterWing", "CozyWard", "CorridorA", "CorridorB", "Hall", "XRay" } do
				expect(overlap(body, B.ROOMS[room])).toBe(false)
			end
			-- solid, and overlapping nothing else that is
			local found = false
			for _, o in B.obstacles(5, 0) do
				if o.Name == "Station_" .. id then
					found = true
				elseif overlap(body, o) then
					error("Station_" .. id .. " overlaps " .. o.Name)
				end
			end
			expect(found).toBe(true)
			-- side by side on one wall: next to the one before it, a gap apart (no two faces in one plane)
			local gap = last.X0 - body.X1
			expect(gap >= 0.5 and gap <= 2).toBe(true)
			last = body
			-- next to the supplies: a few steps from the Bandage shelf's stand
			expect(dist(B.stationStand(id), B.stationStand("Bandage")) <= 12).toBe(true)
			-- the stand is open floor at every level
			local stand = B.stationStand(id)
			for _, level in LEVELS do
				expect(
					B.clear({ X0 = stand.X - 0.8, X1 = stand.X + 0.8, Z0 = stand.Z - 0.8, Z1 = stand.Z + 0.8 }, level)
				).toBe(true)
			end
		end
		-- clear of the A&E door at that end of corridor A: a patient coming in passes a creature's width from the stands
		local aeIn = B.doorPoints("AE")
		for _, id in B.PANTRY_ORDER do
			expect(dist(B.stationStand(id), aeIn) >= 5).toBe(true)
		end
	end)

	test("at its own stand each one's prompt is the nearest: no station's, no bay's, not the lift's", function()
		local H = loadPure("src/server/HospitalBuilder.luau")
		-- the ground landing's prompt (Server/HospitalBuilder Pure.LIFT_PROMPT): Away studs along the hall
		local lift = { X = B.LANDING.X, Z = B.LANDING.Z + H.LIFT_PROMPT.Away }
		for id in PANTRY do
			local stand, own = B.stationStand(id), B.stationPromptAt(id)
			local d = dist(stand, own)
			expect(d < B.PROMPT_REACH - 2).toBe(true)
			for other in B.STATIONS do
				if other ~= id then
					local e = dist(stand, B.stationPromptAt(other))
					if e < d + 2 or e < 2 * d then -- Building.spec's margin
						error(string.format("at %s's stand, %s's prompt is %.1f away vs its own %.1f", id, other, e, d))
					end
				end
			end
			for _, bay in B.BAYS do
				expect(dist(stand, B.doctorSpot(bay)) >= d + 2).toBe(true)
			end
			expect(dist(stand, lift) >= d + 2).toBe(true)
			-- and standing at any OTHER station, the pantry's prompts are out of reach
			for other in B.STATIONS do
				if not PANTRY[other] then
					expect(dist(B.stationStand(other), own) > B.PROMPT_REACH).toBe(true)
				end
			end
		end
	end)

	test("reachable from every open bay (and back) at every level and with every mix of rooms", function()
		for _, level in LEVELS do
			for _, rooms in ROOM_SETS do
				for id, roomId in PANTRY do
					if rooms[roomId] then
						local stand = B.stationStand(id)
						for _, bay in B.openBays(level, rooms) do
							local spot = B.doctorSpot(bay)
							if not B.path(spot, stand, level, 0) or not B.path(stand, spot, level, 0) then
								error(string.format("Lv %d: no walk between bay %s and %s", level, bay.Id, id))
							end
						end
						-- and from the supply shelf it stands beside: one straight walk
						expect(#B.path(B.stationStand("Plaster"), stand, level, 0)).toBe(1)
					end
				end
			end
		end
	end)
end)

T.describe("Pantry: the rules (Server/Patients' pure block)", function()
	local P = loadPure("src/server/Patients.luau", {
		Recipe = Recipe,
		Hospital = Hospital,
		Visit = Visit,
		Cases = Cases,
		Items = Items,
		Tools = Tools,
	})

	-- A clinic as Pure.eligible sees it, its stations by the numbers (what HospitalBuilder writes on the parts).
	local function clinic(level: number, rooms: { [string]: boolean }): any
		local stations = {}
		for id in B.STATIONS do
			if B.stationOpen(id, level, rooms) then
				stations[id] = true
			end
		end
		local bays = { Exam = false, XRay = false }
		for _, bay in B.openBays(level, rooms) do
			bays[bay.Kind] = true
		end
		return { Level = level, Rooms = rooms, Stations = stations, Bays = bays }
	end

	test("Chills and Sore muscles are treatable exactly when their room is owned, at every level", function()
		for _, level in LEVELS do
			for _, rooms in ROOM_SETS do
				local view = clinic(level, rooms)
				expect(P.eligible(Cases.Chills, view)).toBe(rooms.WinterWing == true)
				expect(P.eligible(Cases.SoreMuscles, view)).toBe(rooms.BathRoom == true)
				-- what Server/Daily asks (Logic/Visit.canTreat) says the same
				local function open(id: string): boolean
					return B.stationOpen(id, level, rooms)
				end
				expect(Visit.canTreat(Cases.Chills, level, rooms, open, Items)).toBe(rooms.WinterWing == true)
				expect(Visit.canTreat(Cases.SoreMuscles, level, rooms, open, Items)).toBe(rooms.BathRoom == true)
			end
		end
	end)

	test("a room's wing brings its case only with the room; the item it needs can be made then", function()
		for id, roomId in PANTRY do
			local caseId = ROOM_CASE[id]
			local item = Cases[caseId].Plan[1]
			for _, level in LEVELS do
				local without, with = clinic(level, {}), clinic(level, { [roomId] = true })
				expect(P.makes(without.Stations)[item]).toBeNil()
				expect(P.makes(with.Stations)[item]).toBe(true)
				-- never a case whose first step nobody can take
				for _, rooms in ROOM_SETS do
					local view = clinic(level, rooms)
					if P.eligible(Cases[caseId], view) then
						expect(view.Stations[id]).toBe(true)
					end
				end
			end
		end
	end)

	test("no case of any pool needs a station that stands in a room", function()
		for caseId in Cases do
			local case = Cases[caseId]
			if type(case) == "table" and type(case.Plan) == "table" then
				for _, itemId in case.Plan do
					local station = Items[itemId].Station
					if not B.STATIONS[station] then
						error(caseId .. " needs " .. itemId .. " from " .. station .. ", which is not in the Building")
					end
				end
			end
		end
	end)
end)

T.describe("Pantry: the built world", function()
	local world = require("./worldmock").new()
	local PlotBuilder = world.load("src/server/PlotBuilder.luau")
	local H = loadPure("src/server/HospitalBuilder.luau")
	local plot = PlotBuilder.buildTown()[1]
	local pivot = plot:GetPivot()

	local function room(roomId: string)
		return plot.Rooms:FindFirstChild("Room_" .. roomId)
	end

	local function lose(roomId: string)
		local model = room(roomId)
		if model then
			model:Destroy()
		end
	end

	local function station(id: string)
		return plot.Building:FindFirstChild("Station_" .. id)
	end

	local function icon(p): string
		return p.IconGui.Icon.Text
	end

	test("Station_Cocoa and Station_Bath stand in the Building at every level, on Logic/Building's rects", function()
		lose("BathRoom")
		lose("WinterWing")
		for _, level in LEVELS do
			PlotBuilder.buildBuilding(plot, level)
			for id, roomId in PANTRY do
				local p = station(id)
				expect(p ~= nil and p:IsA("BasePart")).toBe(true)
				expect(p.Parent).toBe(plot.Building) -- a direct child (contract C2)
				expect(p:GetAttribute("StationId")).toBe(id)
				expect(p:GetAttribute("Room")).toBe(roomId)
				expect(p:GetAttribute("Open")).toBe(false)
				expect(p:HasTag("BuildingStation")).toBe(true)
				expect(p.CanCollide).toBe(true)
				local lo, hi = world.box(p, pivot)
				local r = B.stationRect(id)
				expect(lo.X).toBeCloseTo(r.X0, 3)
				expect(hi.X).toBeCloseTo(r.X1, 3)
				expect(lo.Z).toBeCloseTo(r.Z0, 3)
				expect(hi.Z).toBeCloseTo(r.Z1, 3)
				expect(lo.Y).toBeCloseTo(0, 3)
				expect(hi.Y).toBeCloseTo(H.STATION[id], 3)
			end
		end
	end)

	test(
		"the furniture: a cocoa counter with a pot and two mugs, a shelf of bath foam and towels; no emblem",
		function()
			PlotBuilder.buildBuilding(plot, 1)
			local function kinds(p): { [string]: number }
				local out = {}
				for _, child in p:GetChildren() do
					if child:IsA("BasePart") then
						out[child.Name] = (out[child.Name] or 0) + 1
						-- walk-through: the station part is what stops you
						expect(child.CanCollide == false and child.CanQuery == false).toBe(true)
					end
				end
				return out
			end
			local cocoa, bath = station("Cocoa"), station("Bath")
			local c = kinds(cocoa)
			expect(c.Countertop).toBe(1)
			expect(c.Door).toBe(1)
			expect(c.CocoaPot).toBe(1)
			expect(c.Mug).toBe(2)
			expect(cocoa.Transparency).toBe(0) -- the counter's body is the part
			local b = kinds(bath)
			expect(b.ShelfSide).toBe(2)
			expect(b.ShelfBack).toBe(1)
			expect(b.ShelfBoard).toBe(3)
			expect(b.FoamBottle).toBe(3)
			expect(b.Towel).toBe(2)
			expect(bath.Transparency).toBe(1) -- open shelves round an invisible box
			for _, p in { cocoa, bath } do
				for _, d in p:GetDescendants() do
					-- original only: nothing named or drawn like a cross, no Texture or Decal
					expect(string.find(string.lower(d.Name), "cross", 1, true)).toBeNil()
					expect(d:IsA("Texture") or d:IsA("Decal") or d:IsA("SurfaceGui")).toBe(false)
					if d:IsA("TextLabel") then
						for _, bad in { "➕", "✚", "⛑", "🏥", "+" } do
							expect(string.find(d.Text, bad, 1, true)).toBeNil()
						end
					end
				end
			end
			-- the parts the pantry adds are what the Building's budget grew by (Config.Look: 420 -> 440)
			local added = #world.parts(cocoa) + #world.parts(bath) + 2
			expect(added <= 20).toBe(true)
			expect(Config.Look.BuildingParts).toBe(440)
		end
	)

	test(
		"closed: 🔒 on a grey ring and a hint naming the room (no price, no pressure); open: its icon, no hint",
		function()
			lose("BathRoom")
			lose("WinterWing")
			PlotBuilder.buildBuilding(plot, 1)
			expect(H.roomHint(Rooms.WinterWing)).toBe("Needs ❄️ Winter Wing")
			expect(H.roomHint(Rooms.BathRoom)).toBe("Needs 🛁 Bath Room")
			expect(H.roomHint(nil)).toBe("Needs a room")
			for id, roomId in PANTRY do
				local p = station(id)
				expect(icon(p)).toBe("🔒")
				local hint = p.RoomHint
				expect(hint:IsA("BillboardGui")).toBe(true)
				expect(hint.Enabled).toBe(true)
				expect(hint.MaxDistance > 0 and hint.MaxDistance <= 60).toBe(true)
				expect(hint.Text.Text).toBe(H.roomHint(Rooms[roomId]))
				-- in-game only: no price, no Robux, nothing that pushes
				for _, bad in { "💰", "R$", "Robux", "Buy", "!", tostring(Rooms[roomId].Price) } do
					expect(string.find(hint.Text.Text, bad, 1, true)).toBeNil()
				end
				-- the hint floats over the badge, never through it
				expect(hint.StudsOffsetWorldSpace.Y - H.HINT.Height / 2 >= p.IconGui.StudsOffsetWorldSpace.Y + 1.3).toBe(
					true
				)
			end
			-- the stations a level opens never get a hint
			for id, s in B.STATIONS do
				if not s.Room then
					expect(station(id):FindFirstChild("RoomHint")).toBeNil()
					expect(station(id):GetAttribute("Room")).toBeNil()
				end
			end
		end
	)

	test("Open follows the rooms as they are bought and lost, with no rebuild; a rebuild keeps it", function()
		lose("BathRoom")
		lose("WinterWing")
		PlotBuilder.buildBuilding(plot, 2)
		local building = plot.Building
		local changes = 0
		station("Cocoa"):GetAttributeChangedSignal("Open"):Connect(function()
			changes += 1 -- Server/Stations switches the prompt on this signal
		end)
		expect({ station("Cocoa"):GetAttribute("Open"), station("Bath"):GetAttribute("Open") }).toEqual({ false, false })

		PlotBuilder.placeRoom(plot, "WinterWing")
		expect(plot.Building).toBe(building) -- no rebuild
		expect({ station("Cocoa"):GetAttribute("Open"), station("Bath"):GetAttribute("Open") }).toEqual({ true, false })
		expect(changes).toBe(1)
		expect(icon(station("Cocoa"))).toBe("☕")
		expect(station("Cocoa").RoomHint.Enabled).toBe(false)
		expect(icon(station("Bath"))).toBe("🔒")
		expect(station("Bath").RoomHint.Enabled).toBe(true)
		-- one badge, never two
		local badges = 0
		for _, child in station("Cocoa"):GetChildren() do
			if child.Name == "IconGui" then
				badges += 1
			end
		end
		expect(badges).toBe(1)

		PlotBuilder.placeRoom(plot, "BathRoom")
		PlotBuilder.placeRoom(plot, "Ward") -- a room that opens no station changes nothing
		expect({ station("Cocoa"):GetAttribute("Open"), station("Bath"):GetAttribute("Open") }).toEqual({ true, true })
		expect(icon(station("Bath"))).toBe("🛁")
		expect(changes).toBe(1)

		-- a level-up rebuilds the Building: both stay open
		PlotBuilder.buildBuilding(plot, 3, 2)
		expect(plot.Building ~= building).toBe(true)
		expect({ station("Cocoa"):GetAttribute("Open"), station("Bath"):GetAttribute("Open") }).toEqual({ true, true })
		expect(icon(station("Cocoa"))).toBe("☕")

		-- a room lost (a rebirth: Plots.syncRooms destroys it) closes its station again
		lose("WinterWing")
		expect({ station("Cocoa"):GetAttribute("Open"), station("Bath"):GetAttribute("Open") }).toEqual({ false, true })
		expect(icon(station("Cocoa"))).toBe("🔒")
		expect(station("Cocoa").RoomHint.Enabled).toBe(true)
		lose("BathRoom")
		expect(station("Bath"):GetAttribute("Open")).toBe(false)
		-- the level's own stations never moved through any of it
		for id, s in B.STATIONS do
			if not s.Room then
				expect(station(id):GetAttribute("Open")).toBe(3 >= s.Opens)
			end
		end
	end)

	test("no room builds a station: the rooms keep their look as decor and the Winter Wing its bed", function()
		for _, roomId in { "BathRoom", "Ward", "WinterWing", "Garden" } do
			if not room(roomId) then
				PlotBuilder.placeRoom(plot, roomId)
			end
		end
		for _, model in plot.Rooms:GetChildren() do
			for _, d in model:GetDescendants() do
				if string.match(d.Name, "^Station_") then
					error(model.Name .. " builds " .. d.Name)
				end
				expect(d:GetAttribute("StationId")).toBeNil()
				if d:IsA("ProximityPrompt") then
					error(model.Name .. " carries a prompt")
				end
			end
		end
		local bath, winter = room("BathRoom"), room("WinterWing")
		-- the look stays: the tub with its water and bubbles on the tiles, the towel, the foam shelf
		for _, name in { "Tub", "Water", "Bubble", "Tiles", "Towel", "Shelf", "Foam", "BathMat" } do
			expect(bath:FindFirstChild(name) ~= nil).toBe(true)
		end
		-- the fireplace, the rug, a side table with a mug, and the recovery bed a chills patient rests in
		for _, name in { "Fireplace", "Flame", "Mantel", "Rug", "SideTable", "Mug", "Bed_1", "Frame", "Headboard" } do
			expect(winter:FindFirstChild(name) ~= nil).toBe(true)
		end
		expect(winter:FindFirstChild("Pot")).toBeNil()
		-- and each station is found exactly once on the plot: the Building's
		for id in PANTRY do
			local found = 0
			for _, d in plot:GetDescendants() do
				if d.Name == "Station_" .. id then
					found += 1
					expect(d.Parent).toBe(plot.Building)
				end
			end
			expect(found).toBe(1)
		end
	end)

	test("the source: PlotBuilder names no Station_Bath or Station_Cocoa and lays out no room station", function()
		local plotBuilder = code("src/server/PlotBuilder.luau")
		for _, needle in { "Station_Bath", "Station_Cocoa", '"Station_" .. "Bath"', '"Station_" .. "Cocoa"' } do
			expect(string.find(plotBuilder, needle, 1, true)).toBeNil()
		end
		-- its room layouts place no station (Stations = {} in each), and it builds only what ownStations lists:
		-- Data/Rooms' stations less the Building's, which is none
		expect(string.find(plotBuilder, "Stations = {%s*%a")).toBeNil()
		expect(string.find(plotBuilder, "if not Building.STATIONS[stationId] then", 1, true) ~= nil).toBe(true)
		-- the Building is where they are built, and where their Open is kept in step with the rooms
		local hospital = code("src/server/HospitalBuilder.luau")
		expect(string.find(hospital, "for _, id in B.PANTRY_ORDER do", 1, true) ~= nil).toBe(true)
		expect(string.find(hospital, "function HospitalBuilder.syncStations", 1, true) ~= nil).toBe(true)
		expect(string.find(hospital, "rooms.ChildAdded:Connect", 1, true) ~= nil).toBe(true)
		expect(string.find(hospital, "rooms.ChildRemoved:Connect", 1, true) ~= nil).toBe(true)
		-- everyone who asks the numbers passes the rooms
		expect(
			string.find(
				code("src/server/Patients.luau"),
				"Building.stationOpen(stationId, state.Level, state.Rooms)",
				1,
				true
			) ~= nil
		).toBe(true)
		expect(
			string.find(
				code("src/server/Daily.luau"),
				"Building.stationOpen(stationId, data.Level, data.Rooms)",
				1,
				true
			) ~= nil
		).toBe(true)
	end)
end)
