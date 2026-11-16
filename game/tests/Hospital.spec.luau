--!nocheck
-- The hospital world (Progression v2 build plan §C T6): the building's layout (PlotBuilder.Pure), the lift's rules
-- (Server/Lift and UI/LiftPanel pure blocks), the 💊 Pharmacy's craft check and the hold factors (Server/Stations).
-- The pure blocks are loaded straight from the shipped source. The last part builds the REAL PlotBuilder under a
-- small Instance mock (Lune's roblox datatypes; no Roblox services), so the parts budget (a Lv 5 plot with every room
-- <= 400 parts, no creatures or decor) and the clearances (nothing on the Counter, the line, the gate, the sign, the
-- walkways or a room slot) are checked on what ships. Run from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local T = require("./expect")
local expect, test = T.expect, T.test

local Config = require("./config")
local LevelsData = require("../src/shared/Data/Levels")
local Departments = require("../src/shared/Data/Departments")
local Items = require("../src/shared/Data/Items")
local Recipe = require("../src/shared/Logic/Recipe")
local Rebirth = require("../src/shared/Logic/Rebirth")

local function find(relative: string): string
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. relative) then
			return prefix .. relative
		end
	end
	error("can't find " .. relative .. " (run from game/)")
end

local function loadPure(path: string): any
	local text = fs.readFile(find(path))
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to and to > from, path .. ": no PURE block")
	return luau.load(string.sub(text, from, to - 1) .. "\nreturn Pure\n", { debugName = path .. " (pure)" })()
end

local Building = loadPure("src/server/PlotBuilder.luau")
local Lift = loadPure("src/server/Lift.luau")
local Panel = loadPure("src/client/UI/LiftPanel.luau")
local Stations = loadPure("src/server/Stations.luau")

local ROOF = Departments.Roof.Floor

-- The placeholder plot: the Stand slot ends at z = 1, the side rooms leave |x| < 11.5, the back rooms start at 18.
local FOOT = { Half = 11.5, Front = 2, Back = 13, Ground = Building.ground(9.6) }
local L = Building.layout(FOOT)

local function overlaps(a, b): boolean
	local e = 0.01
	return a.X0 < b.X1 - e and b.X0 < a.X1 - e and a.Z0 < b.Z1 - e and b.Z0 < a.Z1 - e
end

local function inside(inner, outer): boolean
	local e = 0.01
	return inner.X0 >= outer.X0 - e
		and inner.X1 <= outer.X1 + e
		and inner.Z0 >= outer.Z0 - e
		and inner.Z1 <= outer.Z1 + e
end

local function onSlab(x: number, z: number): boolean
	local function within(r)
		return x >= r.X0 and x <= r.X1 and z >= r.Z0 and z <= r.Z1
	end
	return within(L.Slab) or within(L.SlabBack)
end

local function landingRect()
	local h = Building.LANDING / 2
	return { X0 = L.Landing.X - h, X1 = L.Landing.X + h, Z0 = L.Landing.Z - h, Z1 = L.Landing.Z + h }
end

local function rampRect()
	local w = L.Ramp.Width / 2
	return { X0 = L.Ramp.XHigh, X1 = L.Ramp.XLow, Z0 = L.Ramp.Z - w, Z1 = L.Ramp.Z + w }
end

local function circle(x, z, d)
	return { X0 = x - d / 2, X1 = x + d / 2, Z0 = z - d / 2, Z1 = z + d / 2 }
end

T.describe("Hospital (layout)", function()
	test("the lobby is one walkable storey; a tall kit Stand raises it, but never past 9", function()
		expect(Building.ground(9.6)).toBe(7)
		expect(Building.ground(13)).toBeCloseTo(8.5, 5)
		expect(Building.ground(40)).toBe(9)
		expect(Building.ground(0)).toBe(7)
	end)

	test("floor heights: the lobby floor, then a storey (7) apart", function()
		expect(Building.floorTop(FOOT, 0)).toBeCloseTo(0.05, 5)
		local tops = {}
		for k = 1, 4 do
			tops[k] = Building.floorTop(FOOT, k)
		end
		expect(tops).toEqual({ 7.3, 14.3, 21.3, 28.3 })
		expect(Building.slabY(FOOT, 4)).toBe(28)
	end)

	test("which floors are indoors, and the roof is walkable only at Lv 5", function()
		local got = {}
		for level = 1, 5 do
			local indoor, roof = Building.storeys(LevelsData[level].Floors, ROOF)
			got[level] = { indoor, roof }
		end
		expect(got).toEqual({ { 0, false }, { 1, false }, { 2, false }, { 3, false }, { 3, true } })
	end)

	test("every flight rises one storey at 45 degrees or less, with headroom under the next", function()
		for k = 0, 3 do
			local rise = Building.floorTop(FOOT, k + 1) - Building.floorTop(FOOT, k)
			local run = L.Ramp.XLow - L.Ramp.XHigh
			expect(math.deg(math.atan2(rise, run)) <= 45).toBe(true)
		end
		-- Stacked flights are parallel plates a storey apart: a 5-stud rider always fits.
		expect(Building.STOREY - 0.4 >= 5).toBe(true)
	end)

	test("the stairwell, the shaft and the slabs never overlap; the landing stands on the slab", function()
		expect(overlaps(rampRect(), L.Slab)).toBe(false)
		expect(overlaps(rampRect(), L.SlabBack)).toBe(false)
		expect(overlaps(rampRect(), L.Shaft)).toBe(false)
		expect(overlaps(L.Shaft, L.Slab)).toBe(false)
		expect(overlaps(L.Shaft, L.SlabBack)).toBe(false)
		expect(inside(landingRect(), L.Slab)).toBe(true)
		-- The landing is right in front of the lift door (the shaft's street side).
		expect(L.Landing.X > L.Shaft.X0 and L.Landing.X < L.Shaft.X1).toBe(true)
		expect(landingRect().Z1 <= L.Shaft.Z0 + 0.01).toBe(true)
	end)

	test("ward beds: on the slabs, apart, clear of the lift; each foot point free and on the floor", function()
		local beds = {}
		for i, bed in L.Beds do
			beds[i] = Building.bedRect(bed)
		end
		for i, r in beds do
			expect(inside(r, { X0 = -FOOT.Half, X1 = FOOT.Half, Z0 = FOOT.Front, Z1 = FOOT.Back })).toBe(true)
			expect(overlaps(r, L.Shaft)).toBe(false)
			expect(overlaps(r, landingRect())).toBe(false)
			expect(overlaps(r, rampRect())).toBe(false)
			for j, other in beds do
				if i ~= j then
					expect(overlaps(r, other)).toBe(false)
				end
			end
			local fx, fz = Building.bedFoot(L.Beds[i])
			expect(onSlab(fx, fz)).toBe(true)
			for _, other in beds do
				expect(fx > other.X0 and fx < other.X1 and fz > other.Z0 and fz < other.Z1).toBe(false)
			end
		end
		-- The bed's foot point matches Server/Patients (half the 6.6 mattress + 1.6).
		expect(Building.FOOT_POINT).toBeCloseTo(6.6 / 2 + 1.6, 5)
	end)

	test("the hot tub, the Pharmacy and the roof (tower, helipad, planters) each have their own place", function()
		local tub = circle(L.Tub.X, L.Tub.Z, L.Tub.Diameter)
		expect(inside(tub, { X0 = L.Left.X0, X1 = L.Left.X1, Z0 = FOOT.Front, Z1 = FOOT.Back })).toBe(true)
		expect(overlaps(tub, L.Shaft)).toBe(false)
		expect(overlaps(tub, landingRect())).toBe(false)
		local pharmacy =
			{ X0 = L.Pharmacy.X - 2.3, X1 = L.Pharmacy.X + 2.3, Z0 = L.Pharmacy.Z - 1.3, Z1 = L.Pharmacy.Z + 1.3 }
		expect(onSlab(L.Pharmacy.X, L.Pharmacy.Z)).toBe(true)
		expect(overlaps(pharmacy, L.Shaft)).toBe(false)
		expect(overlaps(pharmacy, landingRect())).toBe(false)
		local pad = circle(L.Pad.X, L.Pad.Z, L.Pad.Diameter)
		expect(L.Pad.Diameter >= 6.5).toBe(true)
		expect(inside(pad, L.Slab)).toBe(true)
		for _, r in { L.Tower, landingRect(), L.Shaft, rampRect() } do
			expect(overlaps(pad, r)).toBe(false)
		end
		expect(overlaps(L.Tower, landingRect())).toBe(false)
		expect(overlaps(L.Tower, L.Shaft)).toBe(false)
		for _, at in L.Planters do
			local planter = { X0 = at.X - 1.5, X1 = at.X + 1.5, Z0 = at.Z - 0.8, Z1 = at.Z + 0.8 }
			expect(inside(planter, L.Slab)).toBe(true)
			expect(overlaps(planter, L.Tower)).toBe(false)
		end
	end)

	test("the whole block stays behind the Stand and inside the walkways", function()
		for _, r in { L.Slab, L.SlabBack, L.Shaft, rampRect() } do
			expect(r.Z0 >= 1).toBe(true) -- the Stand slot's back edge: the Counter, line, gate and sign are all in front
			expect(r.X0 >= -11.9 and r.X1 <= 11.9).toBe(true) -- the side walkways are |x| 11.9 to 14
			expect(r.Z1 <= 13.4).toBe(true) -- the yard before the back rooms (z 18) keeps 4.6
		end
	end)
end)

T.describe("Hospital (lift rules)", function()
	test("which floors exist per level (Data/Levels Floors)", function()
		local got = {}
		for level = 1, 5 do
			got[level] = Lift.floors(LevelsData[level].Floors)
		end
		expect(got).toEqual({ { 0 }, { 0, 1 }, { 0, 1, 2 }, { 0, 1, 2, 3 }, { 0, 1, 2, 3, 4 } })
		expect(Lift.exists(4, LevelsData[5].Floors)).toBe(true)
		expect(Lift.exists(5, LevelsData[5].Floors)).toBe(false)
		expect(Lift.exists(1, LevelsData[1].Floors)).toBe(false)
		expect(Lift.exists(-1, 4)).toBe(false)
		expect(Lift.exists(1.5, 4)).toBe(false)
		expect(Lift.exists(0 / 0, 4)).toBe(false)
		expect(Lift.exists("1", 4)).toBe(false)
	end)

	test("a floor must be a whole, finite number", function()
		expect(Lift.whole(2)).toBe(2)
		expect(Lift.whole(2.5)).toBeNil()
		expect(Lift.whole(math.huge)).toBeNil()
		expect(Lift.whole(0 / 0)).toBeNil()
		expect(Lift.whole("2")).toBeNil()
		expect(Lift.whole(nil)).toBeNil()
	end)

	test("ride seconds: Config.Lift.RideSeconds x Express Lift (2 s -> 0.8 s at 3 ranks), never below 20%", function()
		expect(Lift.rideSeconds(Config.Lift.RideSeconds, 1)).toBe(2)
		expect(
			Lift.rideSeconds(Config.Lift.RideSeconds, Rebirth.effects({ Rebirth = { Tree = {} } }, Config, {}, {}).Lift)
		).toBe(2)
		expect(Lift.rideSeconds(2, 0.4)).toBeCloseTo(0.8, 5)
		expect(Lift.rideSeconds(2, 0)).toBeCloseTo(0.4, 5)
		expect(Lift.rideSeconds(2, 5)).toBe(2)
		expect(Lift.rideSeconds(-1, 1)).toBe(2)
		expect(Lift.rideSeconds(2, 0 / 0)).toBe(2)
	end)

	test("the landing you stand at: near across the floor, on that floor's height, the nearest wins", function()
		local landings = {}
		for k = 0, 4 do
			table.insert(landings, { Floor = k, X = 0.3, Y = Building.floorTop(FOOT, k), Z = 6.8 })
		end
		local reach = Config.Lift.CarDistance + Lift.REACH_SLACK
		-- A rider's root stands ~3 over the floor.
		expect(Lift.nearest(landings, 2, 0.05 + 3, 7, reach).Floor).toBe(0)
		expect(Lift.nearest(landings, 2, 14.3 + 3, 7, reach).Floor).toBe(2)
		expect(Lift.nearest(landings, 0.3, 28.3 + 3, 6.8, reach).Floor).toBe(4)
		expect(Lift.nearest(landings, 0.3 + reach + 1, 3, 6.8, reach)).toBeNil() -- from the street
		expect(Lift.nearest(landings, 0.3, -5, 6.8, reach)).toBeNil()
		-- Between two floors (a jump off a slab): never counted as a storey it isn't on.
		expect(Lift.ABOVE < Building.STOREY).toBe(true)
	end)

	test("riders are set down side by side", function()
		expect({ Lift.spread(1), Lift.spread(2), Lift.spread(3), Lift.spread(4) }).toEqual({ 0, 2.8, -2.8, 5.6 })
	end)

	test("the ride attributes: Server/Lift writes what UI/LiftPanel reads", function()
		local mine = Panel.decodeRide(Lift.encodeRide(0, 3, 2, 1234.5678, 2), true)
		expect(mine).toEqual({ Plot = 2, From = 0, To = 3, Seconds = 2, At = 1234.568 })
		local car = Panel.decodeRide(Lift.encodeRide(4, 0, 0.8, 99), false)
		expect(car).toEqual({ From = 4, To = 0, Seconds = 0.8, At = 99 })
		expect(Panel.decodeRide("1,2,3", false)).toBeNil()
		expect(Panel.decodeRide("a,b,c,d", false)).toBeNil()
		expect(Panel.decodeRide("0,1.5,2,9", false)).toBeNil()
		expect(Panel.decodeRide("0,1,-2,9", false)).toBeNil()
		expect(Panel.decodeRide(nil, true)).toBeNil()
		expect(Panel.remaining(2, 100, 100.5)).toBeCloseTo(1.5, 5)
		expect(Panel.remaining(2, 100, 200)).toBeCloseTo(0.15, 5)
	end)

	test("the floor picker: this building's floors only, top first, icons from Data/Departments", function()
		local texts = {}
		for _, button in Panel.buttons(LevelsData[5].Floors, 0, Departments) do
			table.insert(texts, button.Text)
		end
		expect(texts).toEqual({ "🚁 R", "💊 3", "🛁 2", "🛏️ 1", "🛎️ G" })
		local lv2 = Panel.buttons(LevelsData[2].Floors, 1, Departments)
		expect(#lv2).toBe(2)
		expect(lv2[1].Here).toBe(true)
		expect(lv2[2].Here).toBe(false)
		for _, button in Panel.buttons(4, nil, Departments) do
			local words = 0
			for _ in string.gmatch(button.Text, "%S+") do
				words += 1
			end
			expect(words <= 6).toBe(true)
		end
	end)
end)

T.describe("Hospital (stations)", function()
	local function has(count, id)
		return Rebirth.has(count, id)
	end

	test("hold factors: team x ability rush, never under Config.BoostMinMakeSeconds, never longer", function()
		local floor = Config.BoostMinMakeSeconds
		expect(Stations.holdSeconds(2, 1, 1, floor)).toBe(2)
		expect(Stations.holdSeconds(2, 0.6, 1, floor)).toBeCloseTo(1.2, 5) -- a Hydro/Pharmacy team of 3 (40%)
		expect(Stations.holdSeconds(2, 0.6, 0.5, floor)).toBeCloseTo(0.6, 5) -- + Busy Paws
		expect(Stations.holdSeconds(2, 1, 0, floor)).toBe(floor) -- Time Bubble: the shortest hold
		expect(Stations.holdSeconds(0.2, 1, 1, floor)).toBe(0.2) -- already under the floor: unchanged
		expect(Stations.holdSeconds(2, 1.5, 3, floor)).toBe(2) -- never slower than base
		expect(Stations.holdSeconds(2, 0 / 0, -1, floor)).toBe(2) -- junk factors change nothing
		expect(Stations.holdSeconds(-1, 1, 1, floor)).toBe(floor)
	end)

	test("the Pharmacy's tier follows the owner's branches (Pharmacy2 at R2)", function()
		expect(Stations.pharmacyTier(0, has)).toBe(1)
		expect(Stations.pharmacyTier(1, has)).toBe(1)
		expect(Stations.pharmacyTier(2, has)).toBe(2)
		expect(Stations.pharmacyTier("x", has)).toBe(1)
	end)

	test("the craft check: two carried ingredients make one medicine (tier 2 from R2)", function()
		local made, taken = Stations.pharmacy({ "Potion", "Cocoa" }, Items, 1, Recipe.craft)
		expect(made).toBe("WarmTonic")
		expect(taken).toEqual({ "Potion", "Cocoa" })
		made, taken = Stations.pharmacy({ "Cocoa", "Bubbles", "Plaster" }, Items, 1, Recipe.craft)
		expect(made).toBe("SoapyPatch")
		expect(taken).toEqual({ "Bubbles", "Plaster" })
		expect((Stations.pharmacy({ "Potion", "Plaster" }, Items, 1, Recipe.craft))).toBeNil() -- SuperSyrup is tier 2
		expect((Stations.pharmacy({ "Potion", "Plaster" }, Items, 2, Recipe.craft))).toBe("SuperSyrup")
		expect((Stations.pharmacy({ "Potion" }, Items, 2, Recipe.craft))).toBeNil()
		expect((Stations.pharmacy({ "Potion", "Potion" }, Items, 2, Recipe.craft))).toBeNil()
		expect((Stations.pharmacy({}, Items, 2, Recipe.craft))).toBeNil()
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- The real PlotBuilder under a small Instance mock (Lune's roblox datatypes; Instances are plain tables)
------------------------------------------------------------------------------------------------------------------

local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local BASE = { Part = true, WedgePart = true, CornerWedgePart = true, MeshPart = true, SpawnLocation = true }
local tags: { [string]: { any } } = {}
local methods = {}
local meta = {}

local function noSignal()
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
		Once = function()
			return { Disconnect = function() end }
		end,
	}
end

local function new(className: string)
	local p = { Name = className, ClassName = className, _children = {}, _attrs = {} }
	if BASE[className] then
		p.Size, p.CFrame, p.CanCollide, p.CanQuery, p.Transparency = Vector3.new(4, 1, 2), CFrame.new(), true, true, 0
	end
	return setmetatable({ _p = p }, meta)
end

function methods:IsA(class)
	local cn = rawget(self, "_p").ClassName
	return cn == class
		or class == "Instance"
		or (class == "BasePart" and BASE[cn] == true)
		or (class == "Light" and string.find(cn, "Light$") ~= nil)
end
function methods:GetChildren()
	return table.clone(rawget(self, "_p")._children)
end
function methods:GetDescendants()
	local out = {}
	local function walk(i)
		for _, c in rawget(i, "_p")._children do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods:FindFirstChild(name, recursive)
	for _, c in rawget(self, "_p")._children do
		if c.Name == name then
			return c
		end
	end
	if recursive then
		for _, c in rawget(self, "_p")._children do
			local found = c:FindFirstChild(name, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function methods:FindFirstChildWhichIsA(class, recursive)
	for _, d in (if recursive then self:GetDescendants() else self:GetChildren()) do
		if d:IsA(class) then
			return d
		end
	end
	return nil
end
function methods:FindFirstAncestor(name)
	local p = self.Parent
	while p and p.Name ~= name do
		p = p.Parent
	end
	return p
end
function methods:SetAttribute(k, v)
	rawget(self, "_p")._attrs[k] = v
end
function methods:GetAttribute(k)
	return rawget(self, "_p")._attrs[k]
end
function methods:GetAttributeChangedSignal()
	return noSignal()
end
function methods:Destroy()
	self.Parent = nil
end
function methods:AddTag(tag)
	tags[tag] = tags[tag] or {}
	table.insert(tags[tag], self)
end
function methods:Clone()
	local src = rawget(self, "_p")
	local copy = new(src.ClassName)
	local p = rawget(copy, "_p")
	for k, v in src do
		if k ~= "_children" and k ~= "_attrs" and k ~= "Parent" then
			p[k] = v
		end
	end
	for k, v in src._attrs do
		p._attrs[k] = v
	end
	for _, child in src._children do
		child:Clone().Parent = copy
	end
	return copy
end
function methods:ClearAllChildren()
	for _, c in self:GetChildren() do
		c:Destroy()
	end
end
local function boxOf(model)
	local lo, hi
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local cf, s = part.CFrame, part.Size / 2
			for _, c in { cf * Vector3.new(-s.X, -s.Y, -s.Z), cf * Vector3.new(s.X, s.Y, s.Z) } do
				lo = if lo then lo:Min(c) else c
				hi = if hi then hi:Max(c) else c
			end
		end
	end
	if not lo then
		return CFrame.new(), Vector3.zero
	end
	return CFrame.new((lo + hi) / 2), hi - lo
end
function methods:GetBoundingBox()
	return boxOf(self)
end
function methods:GetPivot()
	local p = rawget(self, "_p")
	if BASE[p.ClassName] then
		return p.CFrame
	end
	return if p.PrimaryPart then p.PrimaryPart.CFrame elseif p.WorldPivot then p.WorldPivot else (boxOf(self))
end
function methods:PivotTo(cf)
	local p = rawget(self, "_p")
	if BASE[p.ClassName] then
		p.CFrame = cf
		return
	end
	local offset = cf * self:GetPivot():Inverse()
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = offset * d.CFrame
		end
	end
	if p.WorldPivot then
		p.WorldPivot = offset * p.WorldPivot
	end
end
meta.__index = function(self, k)
	local p = rawget(self, "_p")
	if k == "Position" and p.CFrame then
		return p.CFrame.Position
	end
	if p[k] ~= nil then
		return p[k]
	end
	if methods[k] then
		return methods[k]
	end
	if k == "Destroying" or k == "Triggered" then
		return noSignal()
	end
	return self:FindFirstChild(k)
end
meta.__newindex = function(self, k, v)
	local p = rawget(self, "_p")
	if k == "Parent" then
		if p.Parent then
			local list = rawget(p.Parent, "_p")._children
			table.remove(list, table.find(list, self))
		end
		p.Parent = v
		if v then
			table.insert(rawget(v, "_p")._children, self)
		end
	else
		p[k] = v
	end
end

local workspaceMock = new("Folder")
workspaceMock.Name = "Workspace"
rawset(rawget(workspaceMock, "_p"), "GetServerTimeNow", function()
	return 0
end)
local storageMock = new("Folder")
local services = {
	Workspace = workspaceMock,
	ServerStorage = storageMock,
	CollectionService = {
		AddTag = function(_, instance, tag)
			tags[tag] = tags[tag] or {}
			table.insert(tags[tag], instance)
		end,
		GetTagged = function(_, tag)
			return tags[tag] or {}
		end,
		GetInstanceAddedSignal = noSignal,
	},
}

local loaded = {}
local function ref(path: string)
	return setmetatable({ _path = path }, {
		__index = function(_, k)
			if k == "Parent" then
				return ref((string.match(path, "^(.*)/[^/]+$")))
			elseif k == "WaitForChild" then
				return function(self, name)
					return self[name]
				end
			end
			return ref(path .. "/" .. k)
		end,
	})
end
local function loadModule(path: string): any
	if loaded[path] then
		return loaded[path]
	end
	local env = {
		game = {
			GetService = function(_, name)
				return if name == "ReplicatedStorage" then { Shared = ref("src/shared") } else services[name]
			end,
		},
		script = ref(string.gsub(path, "%.luau$", "")),
		require = function(r)
			return loadModule(r._path .. ".luau")
		end,
		Instance = { new = new },
		warn = function() end,
	}
	for k, v in roblox do
		if env[k] == nil and k ~= "Instance" then
			env[k] = v
		end
	end
	local result = luau.load(fs.readFile(find(path)), { debugName = path, environment = env })()
	loaded[path] = result
	return result
end

T.describe("Hospital (the built world)", function()
	local PlotBuilder = loadModule("src/server/PlotBuilder.luau")
	local plot = PlotBuilder.buildTown()[1]
	for _, roomId in { "BathRoom", "Ward", "WinterWing", "Garden" } do
		PlotBuilder.placeRoom(plot, roomId)
	end
	local pivot = plot:GetPivot()

	local function partsOnPlot(): number
		local n = 0
		for _, d in plot:GetDescendants() do
			if d:IsA("BasePart") and not d:FindFirstAncestor("Patients") and not d:FindFirstAncestor("Nurses") then
				n += 1
			end
		end
		return n
	end

	test("parts budget: every level, every theme, every room <= 400 (no creatures, no decor)", function()
		local worst = 0
		for _, theme in { "Candy", "Arctic", "Jungle", "Space", "Ocean", "Royal" } do
			for level = 1, 5 do
				PlotBuilder.buildBuilding(plot, level, nil, theme)
				local n = partsOnPlot()
				worst = math.max(worst, n)
				if n > 400 then
					error(string.format("Lv %d %s: %d parts", level, theme, n))
				end
			end
		end
		expect(worst <= 400).toBe(true)
	end)

	test("a Lv 5 plot with every room and every decor slot filled (the 10 heaviest decor) stays in budget", function()
		-- Integration (lead): the real DecorBuilder under the same mock. Each decor exists once (Plots.placeDecor moves
		-- it), so the worst a plot can hold is the heaviest decor pieces, one per slot.
		local DecorBuilder = loadModule("src/server/DecorBuilder.luau")
		local DecorData = loadModule("src/shared/Data/Decor.luau")
		local RoomsData = loadModule("src/shared/Data/Rooms.luau")
		local slots = 0
		for _, roomId in RoomsData.Order do
			slots += RoomsData[roomId].DecorSlots
		end
		local counts: { number } = {}
		for _, decorId in DecorData.Order do
			local model = DecorBuilder.build(decorId)
			local n = 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					n += 1
				end
			end
			if n > 25 then
				error(decorId .. ": " .. n .. " parts (DecorBuilder's MAX_PARTS is 25)")
			end
			table.insert(counts, n)
		end
		table.sort(counts, function(a, b)
			return a > b
		end)
		local decor = 0
		for index = 1, math.min(slots, #counts) do
			decor += counts[index]
		end
		local worstPlot = 0
		for _, theme in { "Candy", "Royal", "Jungle" } do
			PlotBuilder.buildBuilding(plot, 5, nil, theme)
			worstPlot = math.max(worstPlot, partsOnPlot())
		end
		expect(slots).toBe(10)
		expect(worstPlot <= 400).toBe(true)
		expect(decor <= slots * 25).toBe(true)
		expect(worstPlot + decor <= 400 + slots * 25).toBe(true)
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

	test("the contract's names: floors, landings with both prompts, the lift, stairs, departments", function()
		for level = 1, 5 do
			local building = PlotBuilder.buildBuilding(plot, level, level - 1, "Candy")
			local floors = LevelsData[level].Floors
			expect(building:GetAttribute("Floors")).toBe(floors)
			expect(building:GetAttribute("Theme")).toBe("Candy")
			expect(plot:GetAttribute("Theme")).toBe("Candy")
			expect(building:GetAttribute("Level")).toBe(level)
			if floors > 0 then
				expect(building.Landing_0:GetAttribute("Floor")).toBe(0)
				for k = 1, floors do
					local floorModel = building:FindFirstChild("Floor_" .. k)
					expect(floorModel.Slab.CanCollide).toBe(true)
					expect(floorModel.Landing:GetAttribute("Floor")).toBe(k)
					local point = floorModel.Landing.PromptPoint
					expect(point.LiftPrompt.ActionText).toBe("Lift")
					expect(point.LiftPrompt.ObjectText).toBe("🛗")
					expect(point.EscortPrompt.Enabled).toBe(false)
					expect(floorModel:FindFirstChild("Walls") ~= nil).toBe(k < ROOF)
				end
				expect(building.Lift.Car.CanCollide).toBe(false)
				expect(building.Lift.Shaft.CanCollide).toBe(false)
				expect(building.Stairs:FindFirstChild("Flight_" .. (floors - 1)).CanCollide).toBe(true)
				expect(building.Stairs:FindFirstChild("Flight_" .. floors)).toBeNil()
				expect(building.AmbulanceBay.Ambulance:GetAttribute("ArriveAt")).toBe(0)
				expect(building.AmbulanceBay.Ambulance.StretcherSpot ~= nil).toBe(true)
				for i = 1, LevelsData[level].Beds - 1 do
					local spot = building.Wards:FindFirstChild("BedSpot_" .. i)
					expect(spot:GetAttribute("Floor")).toBe(1)
					expect(spot:FindFirstChild("Bed_" .. i):GetAttribute("Floor")).toBe(1)
				end
			else
				expect(building:FindFirstChild("Landing_0")).toBeNil()
			end
			expect(building:FindFirstChild("Hydro") ~= nil).toBe(level >= 3)
			expect(building:FindFirstChild("Pharmacy") ~= nil).toBe(level >= 4)
			expect(building:FindFirstChild("Roof") ~= nil).toBe(level >= 5)
		end
		local building = plot.Building
		expect(building.Hydro.HotTub.TubSpot_2:GetAttribute("Floor")).toBe(2)
		expect(building.Hydro.HotTub.Tub.SoakPoint.SoakPrompt.Enabled).toBe(false)
		expect(building.Pharmacy.Station_Pharmacy.PrimaryPart ~= nil).toBe(true)
		expect(building.Roof.HeliSpot:GetAttribute("ArriveAt")).toBe(0)
		expect(plot.MascotSpot ~= nil).toBe(true)
		expect(plot.Sign.SignGui.BranchBadge.Visible).toBe(false)
	end)

	test("nothing covers the Counter, the line, the gate, the sign, the walkways or a room slot", function()
		local zones = {
			{ "Counter", -6.4, 6.4, -16, -13 },
			{ "QueueLane", -4, 4, -34.5, -15.8 },
			{ "Gate", -7, 7, -35, -33 },
			{ "Sign", -18.5, -7.5, -35, -32 },
			{ "WalkwayLeft", -14, -11.95, -13, 14, 7 }, -- at ground level (below the first floor)
			{ "WalkwayRight", 11.95, 14, -13, 14, 7 },
			{ "SlotStand", -11, 11, -13, 1 },
			{ "SlotA", -32, -14, -2, 14 },
			{ "SlotC", 14, 32, -2, 14 },
			{ "SlotB", -24, -2, 18, 32 },
			{ "SlotD", 2, 24, 18, 32 },
		}
		local bad = {}
		for _, theme in { "Candy", "Royal" } do
			for level = 2, 5 do
				for _, d in PlotBuilder.buildBuilding(plot, level, nil, theme):GetDescendants() do
					if d:IsA("BasePart") then
						local cf, s = pivot:ToObjectSpace(d.CFrame), d.Size / 2
						local lo, hi
						for _, sx in { -1, 1 } do
							for _, sy in { -1, 1 } do
								for _, sz in { -1, 1 } do
									local c = cf * Vector3.new(sx * s.X, sy * s.Y, sz * s.Z)
									lo = if lo then lo:Min(c) else c
									hi = if hi then hi:Max(c) else c
								end
							end
						end
						for _, z in zones do
							local e = 0.01
							if
								lo.X < z[3] - e
								and hi.X > z[2] + e
								and lo.Z < z[5] - e
								and hi.Z > z[4] + e
								and lo.Y < (z[6] or math.huge)
							then
								table.insert(
									bad,
									string.format("Lv %d %s %s.%s on %s", level, theme, d.Parent.Name, d.Name, z[1])
								)
							end
						end
					end
				end
			end
		end
		expect(bad).toEqual({})
	end)

	test("ward beds are kept (the same parts) across a level-up and a theme change", function()
		local before = PlotBuilder.buildBuilding(plot, 4, 3, "Candy").Wards.BedSpot_1
		expect(PlotBuilder.buildBuilding(plot, 5, 4, "Candy").Wards.BedSpot_1).toBe(before)
		expect(PlotBuilder.buildBuilding(plot, 5, nil, "Space").Wards.BedSpot_1).toBe(before)
		expect(plot.Building:GetAttribute("GrewAt")).toBe(0)
	end)

	test("a theme recolours the walls but never the plot's accent; an unknown one is Candy", function()
		local candy = PlotBuilder.buildBuilding(plot, 3, nil, "Candy")
		local accent = candy.Sign.NameBoard.Color
		local space = PlotBuilder.buildBuilding(plot, 3, nil, "Space")
		expect(space.Sign.NameBoard.Color).toEqual(accent)
		expect(space.Lobby.FrontWall.Color).toEqual(roblox.Color3.fromHex("#D9D2FF"))
		expect(space:FindFirstChild("ThemeProp") ~= nil).toBe(true)
		expect(candy:FindFirstChild("ThemeProp")).toBeNil()
		expect(PlotBuilder.buildBuilding(plot, 3, nil, "Order"):GetAttribute("Theme")).toBe("Candy")
		expect(PlotBuilder.buildBuilding(plot, 1, nil, "Arctic"):FindFirstChild("ThemeProp") ~= nil).toBe(true)
		PlotBuilder.clearPlot(plot)
		expect(plot:GetAttribute("Theme")).toBe("Candy")
		expect(plot:GetAttribute("Level")).toBe(1)
	end)
end)
