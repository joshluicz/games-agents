--!nocheck
-- Blocky creatures (memory-20261117-004; look build plan §D T9). Run from game/ with the rest:  lune run tests/run
-- Two halves, both on the shipped code:
--   1. Server/CreatureBuilder's PURE-BEGIN..PURE-END block (the blocky layout in numbers), loaded on its own with no
--      Roblox types at all: every species in Data/Patients, Data/Regulars and Data/Nurses stays under 40 parts, has
--      every socket and face part, keeps its own silhouette and ear shape, is studded only on its top plate (whole
--      studs at its size), and wears world colours (mid value, no pastel, no pure white).
--   2. The real CreatureBuilder and NurseBuilder under tests/worldmock. The mock has no Model:ScaleTo, GetScale or
--      GetExtentsSize, so this spec adds them to its own world the way Roblox does them (sizes, positions and
--      attachments scaled about the pivot). It checks the rig contract (Root, Core, PoseJoint, the limb Motor6Ds,
--      the sockets, IconAnchor, FX, tags, attributes), no Highlight, no shadow-casting light, the moods, the
--      variants, night glow, the studs in both modes and the nurse cap (our paw-heart, never a cross).

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test
local World = require("./worldmock")
local Look = require("./look")
local Config = require("./config")

local PatientsData = require("../src/shared/Data/Patients")
local Regulars = require("../src/shared/Data/Regulars")
local NursesData = require("../src/shared/Data/Nurses")
local CreatureSize = require("../src/shared/Logic/CreatureSize")

local BUILDER = "src/server/CreatureBuilder.luau"

local function pureBlock(path: string): any
	local text = fs.readFile(World.find(path))
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to, path .. ": no PURE-BEGIN block")
	local chunk = string.sub(text, from, to - 1) .. "\nreturn Pure\n"
	return luau.load(chunk, { debugName = path .. ":Pure" })()
end

local Pure = pureBlock(BUILDER)

local function check(condition: any, message: string)
	if not condition then
		error(message, 2)
	end
end

-- Every creature recipe the game builds: { Id, Look, Night, Kind }.
local CAST = {}
for _, id in PatientsData.Order do
	local entry = PatientsData[id]
	table.insert(CAST, { Id = id, Look = entry.Look, Night = entry.Night == true, Kind = "Patient" })
end
for _, id in Regulars.Order do
	local entry = Regulars[id]
	table.insert(CAST, { Id = id, Look = entry.Look, Night = entry.Wing == "Night", Kind = "Regular" })
end
for _, id in NursesData.Order do
	table.insert(CAST, { Id = id, Look = NursesData[id].Look, Night = false, Kind = "Nurse" })
end

local NURSE_CAP_PARTS = 2 -- NurseBuilder's NurseCap and CapBrim
local SOCKETS = {
	"FaceSocket",
	"NoseSocket",
	"EyeRSocket",
	"EyeLSocket",
	"CheekRSocket",
	"CheekLSocket",
	"BrowSocket",
	"HeadSocket",
	"EarRSocket",
	"EarLSocket",
	"NeckSocket",
	"BellySocket",
	"BackSocket",
}

-- The build scales a species can get: the smallest and biggest wobble, and the middle.
local function scalesOf(look): { number }
	return {
		CreatureSize.scale(look.Scale, Config, 0),
		CreatureSize.scale(look.Scale, Config, 0.5),
		CreatureSize.scale(look.Scale, Config, 1),
	}
end

local function named(layout, name: string): { any }
	local out = {}
	for _, part in layout.Parts do
		if part.Name == name then
			table.insert(out, part)
		end
	end
	return out
end

local function hasSocket(layout, name: string): boolean
	for _, s in layout.Sockets do
		if s.Name == name then
			return true
		end
	end
	return false
end

local function socketOf(layout, name: string)
	for _, s in layout.Sockets do
		if s.Name == name then
			return s
		end
	end
	return nil
end

-- A part's corners in the layout's unit space (its rotation about Z only matters for the outline checks).
local function extent(part): (number, number, number, number, number, number)
	local hx, hy, hz = part.Size.X / 2, part.Size.Y / 2, part.Size.Z / 2
	local a = if part.Rot then part.Rot.Z else 0
	local c, s = math.abs(math.cos(a)), math.abs(math.sin(a))
	local ex, ey = hx * c + hy * s, hx * s + hy * c
	return part.Pos.X - ex, part.Pos.X + ex, part.Pos.Y - ey, part.Pos.Y + ey, part.Pos.Z - hz, part.Pos.Z + hz
end

------------------------------------------------------------------------------------------------------------------
-- 1. The layout in numbers
------------------------------------------------------------------------------------------------------------------

T.describe("BlockyCreatures layout", function()
	test("the block has no Roblox types (it ran without Vector3, Color3 or CFrame)", function()
		expect(type(Pure.layout)).toBe("function")
		expect(Vector3).toBeNil()
	end)

	test("every species stays under 40 parts (Root, Core, a night glow pad and a nurse's cap included)", function()
		local most, who = 0, ""
		for _, c in CAST do
			local layout = Pure.layout(c.Look, { Night = c.Night, Scale = 1.6 })
			local count = #layout.Parts + Pure.RIG_PARTS + (if c.Night then 1 else 0)
			if c.Kind == "Nurse" then
				count += NURSE_CAP_PARTS
			end
			check(count < Pure.MAX_PARTS, c.Id .. " has " .. count .. " parts")
			if count > most then
				most, who = count, c.Id
			end
		end
		print(string.format("        most parts: %s with %d (under %d)", who, most, Pure.MAX_PARTS))
	end)

	test("every species has every socket the client's props use (and a teapot its spout)", function()
		for _, c in CAST do
			local layout = Pure.layout(c.Look, { Night = c.Night })
			for _, name in SOCKETS do
				check(hasSocket(layout, name), c.Id .. " has no " .. name)
			end
			check(
				hasSocket(layout, "SpoutSocket") == (c.Look.Extra == "Spout"),
				c.Id .. ": SpoutSocket only on a spout"
			)
			local seen = {}
			for _, s in layout.Sockets do
				check(not seen[s.Name], c.Id .. ": two " .. s.Name)
				seen[s.Name] = true
			end
		end
	end)

	test("the sockets sit where the props expect them", function()
		for _, c in CAST do
			local layout = Pure.layout(c.Look, {})
			local eyeR, eyeL = socketOf(layout, "EyeRSocket"), socketOf(layout, "EyeLSocket")
			check(eyeR.Pos.X > 0 and eyeL.Pos.X < 0, c.Id .. ": R is the creature's own right (+X)")
			check(socketOf(layout, "EarRSocket").Normal.X == 1, c.Id .. ": the right ear socket faces +X")
			check(socketOf(layout, "HeadSocket").Pos.Y == layout.Top, c.Id .. ": HeadSocket on the head's top")
			check(socketOf(layout, "HeadSocket").Normal == nil, c.Id .. ": HeadSocket keeps the model's orientation")
			check(socketOf(layout, "NeckSocket").Normal == nil, c.Id .. ": NeckSocket keeps the model's orientation")
			local face, nose = socketOf(layout, "FaceSocket"), socketOf(layout, "NoseSocket")
			check(face.Pos.Y < nose.Pos.Y, c.Id .. ": the mouth is under the nose")
			check(face.Normal.Z == -1 and nose.Normal.Z == -1, c.Id .. ": the face sockets look out of the face")
			local head = named(layout, "Head")[1] or named(layout, "Body")[1]
			check(face.Pos.Z < head.Pos.Z - head.Size.Z / 2, c.Id .. ": FaceSocket in front of the face")
			check(layout.Neck.X > 0 and layout.Neck.Z > 0 and layout.Neck.Y == 0, c.Id .. ": NeckSize")
			check(layout.HeadHalf > 0.9, c.Id .. ": HeadRadius")
		end
	end)

	test(
		"a flat block face: big eyes with two glints and a strip, half-lids, lids, brows, blush, a nose, a mouth",
		function()
			for _, c in CAST do
				local layout = Pure.layout(c.Look, {})
				local counts =
					{ Eye = 2, EyeShine = 4, EyeTint = 2, EyeLid = 2, Lid = 2, Brow = 1, Mouth = 1, Cheek = 2 }
				for name, want in counts do
					check(#named(layout, name) == want, c.Id .. ": " .. #named(layout, name) .. " " .. name)
				end
				check(#named(layout, "Nose") + #named(layout, "Beak") >= 1, c.Id .. " has no nose")
				for _, part in layout.Parts do
					check(part.Rot == nil or part.Name ~= "Eye", c.Id .. ": eyes are flat, never turned")
				end
			end
		end
	)

	test("the face stacks front to back: Lid plate, half-lid, glints, eye (nothing flickers)", function()
		for _, c in CAST do
			local layout = Pure.layout(c.Look, {})
			local eye = named(layout, "Eye")[1]
			local eyeFront = eye.Pos.Z - eye.Size.Z / 2
			for _, shine in named(layout, "EyeShine") do
				check(shine.Pos.Z + shine.Size.Z / 2 <= eyeFront + 1e-9, c.Id .. ": a glint inside the eye")
			end
			local half = named(layout, "EyeLid")[1]
			local glint = named(layout, "EyeShine")[1]
			check(
				half.Pos.Z - half.Size.Z / 2 < glint.Pos.Z - glint.Size.Z / 2,
				c.Id .. ": the half-lid covers the glints"
			)
			check(half.Pos.Y > eye.Pos.Y and half.Pos.Y + half.Size.Y / 2 >= eye.Pos.Y + eye.Size.Y / 2 - 1e-9, c.Id)
			check(half.Size.X >= eye.Size.X, c.Id .. ": the half-lid is as wide as the eye")
			check(half.Clear == 1, c.Id .. ": the half-lid is hidden until setMood Sick")
			local lid = named(layout, "Lid")[1]
			check(lid.Pos.Z + lid.Size.Z / 2 < half.Pos.Z - half.Size.Z / 2, c.Id .. ": the Lid plate is in front")
			check(lid.Clear == 1 and lid.Gui == "Lid", c.Id .. ": the Lid plate is see-through and draws")
		end
	end)

	test("only the eyes' lids are called Lid (a teapot's top is PotLid), and nothing is a cross", function()
		for _, c in CAST do
			local layout = Pure.layout(c.Look, {})
			check(#named(layout, "Lid") == 2, c.Id)
			for _, part in layout.Parts do
				check(not string.find(string.lower(part.Name), "cross", 1, true), c.Id .. ": " .. part.Name)
			end
			if c.Look.Top == "Lid" then
				check(#named(layout, "PotLid") == 1, c.Id .. " has no PotLid")
			end
		end
	end)

	test("a star is two squares, one turned 45 degrees (eight points, never a plus)", function()
		local layout = Pure.layout({
			Shape = "Ball",
			Body = "#2ED3C6",
			Accent = "#FFFFFF",
			Ears = "None",
			Top = "Star",
			Extra = "None",
			Scale = 1,
		}, {})
		local star, ray = named(layout, "Star")[1], named(layout, "StarRay")[1]
		expect(star.Size.X).toBe(star.Size.Y)
		expect(ray.Size.X).toBe(ray.Size.Y)
		expect(star.Rot).toBeNil()
		expect(ray.Rot.Z).toBeCloseTo(math.pi / 4)
	end)

	test("studs only on the top plate: flat, on top of the head, whole studs at every size", function()
		for _, c in CAST do
			for _, scale in scalesOf(c.Look) do
				local layout = Pure.layout(c.Look, { Night = c.Night, Scale = scale })
				local plates = 0
				for _, part in layout.Parts do
					if part.Studs then
						plates += 1
						check(part.Name == "StudTop", c.Id .. ": only StudTop is studded, not " .. part.Name)
						check(part.Rot == nil, c.Id .. ": the plate lies flat")
						check(part.Size.Y == Pure.PLATE, c.Id .. ": the plate is thin")
						for _, axis in { "X", "Z" } do
							local studs = part.Size[axis] * scale
							check(
								math.abs(studs - math.floor(studs + 0.5)) < 1e-6,
								c.Id .. ": " .. axis .. " = " .. studs
							)
							check(studs >= 1 - 1e-9, c.Id .. ": at least one stud")
						end
						check(
							math.abs(part.Pos.Y + part.Size.Y / 2 - layout.Top) < 1e-9,
							c.Id .. ": the plate is the top"
						)
					end
				end
				local covered = c.Look.Top == "Pleat" or c.Look.Top == "Scoop"
				check(plates == (if covered then 0 else 1), c.Id .. ": " .. plates .. " plates")
			end
		end
	end)

	test("the stud plate is the widest whole number of studs that fits the head", function()
		expect(Pure.studs(2.7, 1.6)).toBeCloseTo(4 / 1.6) -- 4.32 studs: 4
		expect(Pure.studs(2.3, 2)).toBeCloseTo(2.3 - 0.3) -- 4.6 studs: 4
		expect(Pure.studs(0.5, 1)).toBe(0.5) -- under one stud: just the head
		expect(Pure.studs(3, 1)).toBe(3)
	end)

	test("colours are world values: mid value, no pastel, no pure white, no channel above 245", function()
		for _, c in CAST do
			local layout = Pure.layout(c.Look, { Night = c.Night })
			for _, part in layout.Parts do
				local rgb = Look.fromHex(part.Color)
				if (part.Clear or 0) < 1 then
					check(Look.maxChannel(rgb) <= 245, c.Id .. ": " .. part.Name .. " " .. part.Color)
				end
			end
			local body = named(layout, "Body")[1].Color
			check(body == Pure.world(c.Look.Body, "Body"), c.Id .. ": the body wears its world colour")
			local h, s, v = Pure.hsv(body)
			check(v <= Pure.cap(h) + 0.005 and v >= Pure.V_FLOOR - 0.005, c.Id .. ": body value " .. v)
			check(s >= Pure.S_FLOOR.Body - 0.005, c.Id .. ": body saturation " .. s)
			local accent = Pure.world(c.Look.Accent, "Accent")
			local _, as = Pure.hsv(accent)
			check(accent == Pure.WARM_WHITE or as >= Pure.S_FLOOR.Accent - 0.005, c.Id .. ": accent " .. accent)
		end
	end)

	test("Pure.world keeps the hue, caps the value, turns a white accent warm and never lightens", function()
		local h0 = Look.hsv(Look.fromHex("#FF52B4"))
		local pink = Look.fromHex(Pure.world("#FF52B4", "Body"))
		local h1, _, v1 = Look.hsv(pink)
		expect(math.abs(h1 - h0) < 1.5).toBe(true)
		expect(Look.round(v1)).toBe(Pure.V_CAP)
		expect(Pure.world("#FFFFFF", "Accent")).toBe(Pure.WARM_WHITE)
		expect(Pure.world("#FFF0DE", "Accent")).toBe(Pure.WARM_WHITE)
		local _, s2 = Pure.hsv(Pure.world("#FFC4E6", "Accent")) -- a pastel pink accent gets its colour back
		expect(s2 >= Pure.S_FLOOR.Accent - 0.005).toBe(true)
		local _, _, v3 = Pure.hsv(Pure.world("#FFF04D", "Body")) -- a yellow may sit a little higher
		expect(v3 > Pure.V_CAP and v3 <= Pure.V_CAP_YELLOW + 0.005).toBe(true)
		local _, _, dark = Pure.hsv(Pure.world("#2E3A8C", "Body")) -- a dark body is left alone
		expect(Look.round(dark)).toBe(Look.round(select(3, Pure.hsv("#2E3A8C"))))
		expect(Pure.world("nope", "Body")).toBe(Pure.world(nil, "Body"))
		local _, _, tv = Pure.hsv(Pure.tone("#3B78FF", 0.5)) -- a lighter tone stops at the cap
		expect(tv <= Pure.V_CAP + 0.005).toBe(true)
		local _, _, mv = Pure.hsv(Pure.mid("#B4BCCB"))
		local _, ms = Pure.hsv(Pure.mid("#B4BCCB"))
		expect(mv <= Pure.V_CAP + 0.005).toBe(true)
		expect(ms < 0.2).toBe(true) -- a grey cap stays grey
	end)

	test("every ear kind has its own outline (square ears read cat-like)", function()
		local outlines = {}
		for _, ears in { "Round", "Floppy", "Pointy", "Long", "Tufts" } do
			local look =
				{ Shape = "Ball", Body = "#C4733E", Accent = "#FFF1B0", Ears = ears, Top = "None", Extra = "None" }
			local layout = Pure.layout(look, {})
			local parts = {}
			for _, part in layout.Parts do
				if part.Name == "Ear" or part.Name == "EarInner" then
					local x0, x1, y0, y1 = extent(part)
					if x0 >= 0 or part.Name == "EarInner" and part.Pos.X > 0 then -- the right ear
						table.insert(parts, string.format("%s%.2f/%.2f/%.2f/%.2f", part.Name, x0, x1, y0, y1))
					end
				end
			end
			check(#parts >= 1, ears .. " has no right ear")
			table.sort(parts)
			local key = table.concat(parts, ";")
			check(outlines[key] == nil, ears .. " looks like " .. tostring(outlines[key]))
			outlines[key] = ears
			if ears == "Round" or ears == "Pointy" then -- a stack: a narrower block on a wider one
				local ear = named(layout, "Ear")
				check(#ear == 4 and ear[2].Size.X < ear[1].Size.X, ears .. " is a stack")
			end
		end
		local floppy = named(Pure.layout({ Shape = "Ball", Ears = "Floppy" }, {}), "Ear")[1]
		local head = named(Pure.layout({ Shape = "Ball", Ears = "Floppy" }, {}), "Head")[1]
		check(floppy.Pos.Y < head.Pos.Y + head.Size.Y / 2, "a floppy ear hangs down the side")
	end)

	test("every species keeps its own silhouette (no two patients or regulars build the same)", function()
		local seen = {}
		for _, c in CAST do
			if c.Kind ~= "Nurse" then
				local layout = Pure.layout(c.Look, {})
				local names = {}
				for _, part in layout.Parts do
					table.insert(names, part.Name)
				end
				table.sort(names)
				local key = layout.Shape .. ":" .. table.concat(names, ",")
				check(seen[key] == nil, c.Id .. " builds just like " .. tostring(seen[key]))
				seen[key] = c.Id
			end
		end
	end)

	test("the rig: two arms (or wings or flippers) with paws, a tail on its joint, riders on real joints", function()
		for _, c in CAST do
			local layout = Pure.layout(c.Look, {})
			local joints = {}
			for _, part in layout.Parts do
				if part.Joint then
					check(joints[part.Joint] == nil, c.Id .. ": two " .. part.Joint)
					joints[part.Joint] = part
					check(part.Pivot ~= nil, c.Id .. ": " .. part.Joint .. " has no pivot")
				end
			end
			check(joints.ArmR and joints.ArmL, c.Id .. " has no arms")
			check(joints.ArmR.Hand ~= nil and joints.ArmL.Hand ~= nil, c.Id .. ": the arms have no HandSocket")
			check(joints.ArmR.Pivot.X > 0 and joints.ArmL.Pivot.X < 0, c.Id .. ": ArmR is on the right (+X)")
			local wantArms = c.Look.Extra ~= "Wings" and c.Look.Extra ~= "Flippers"
			check((joints.ArmR.Name == "Arm") == wantArms, c.Id .. ": paws that hold props are named Arm")
			check((joints.Tail ~= nil) == (c.Look.Extra == "Tail"), c.Id .. ": a tail joint only on a tail")
			for _, part in layout.Parts do
				if part.Ride then
					check(joints[part.Ride] ~= nil, c.Id .. ": " .. part.Name .. " rides a missing " .. part.Ride)
				end
			end
		end
	end)

	test("feet on the ground (a Drop floats on its base), nothing below it", function()
		for _, c in CAST do
			local layout = Pure.layout(c.Look, {})
			local low = math.huge
			for _, part in layout.Parts do
				local _, _, y0 = extent(part)
				low = math.min(low, y0)
			end
			check(math.abs(low) < 1e-6, c.Id .. ": its lowest block is at " .. low)
			check((#named(layout, "Foot") == 2) == (c.Look.Shape ~= "Drop"), c.Id .. ": feet unless a Drop")
		end
	end)

	test("night: the tips glow (Neon) and a Drop with nothing on top gets its little curl", function()
		local moth = Pure.layout(PatientsData.MoonMoth.Look, { Night = true })
		local glows = 0
		for _, part in moth.Parts do
			if part.Neon then
				glows += 1
			end
		end
		expect(glows).toBe(2) -- the antennae tips
		local ghost = Pure.layout(PatientsData.HiccupGhost.Look, { Night = true })
		expect(#named(ghost, "Tip")).toBe(1)
		expect(named(ghost, "Tip")[1].Neon).toBe(true)
		expect(#named(ghost, "Hem")).toBe(5)
	end)

	test("every queue patient still fits the 7-stud line at its biggest", function()
		local widest, who = 0, ""
		for _, c in CAST do
			if c.Kind ~= "Nurse" then
				local layout = Pure.layout(c.Look, {})
				local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
				for _, part in layout.Parts do
					local a, b, _, _, e, f = extent(part)
					x0, x1, z0, z1 = math.min(x0, a), math.max(x1, b), math.min(z0, e), math.max(z1, f)
				end
				local big = CreatureSize.scale(c.Look.Scale, Config, 1)
				local span = math.max(x1 - x0, z1 - z0) * big
				check(span <= Config.QueueSpacing, string.format("%s spans %.2f studs", c.Id, span))
				if span > widest then
					widest, who = span, c.Id
				end
			end
		end
		print(
			string.format("        widest: %s at %.2f studs (the line is %d apart)", who, widest, Config.QueueSpacing)
		)
	end)

	test("the pixel drawings fit their grids, and the sick o hides under the client's extra mouths", function()
		local grid = Pure.MOUTH
		for _, mood in Pure.MOUTH_ORDER do
			check(#grid[mood] > 0, mood .. " is empty")
			for _, cell in grid[mood] do
				check(cell[1] >= 0 and cell[1] + (cell[3] or 1) <= grid.Cols, mood .. " runs off the grid")
				check(cell[2] >= 0 and cell[2] + (cell[4] or 1) <= grid.Rows, mood .. " runs off the grid")
			end
		end
		-- CreatureProps' "Hic" (the smallest extra mouth) is 0.22 x 0.48 of the gui, centred.
		for _, cell in grid.Sick do
			local x0, x1 = cell[1] / grid.Cols, (cell[1] + (cell[3] or 1)) / grid.Cols
			local y0, y1 = cell[2] / grid.Rows, (cell[2] + (cell[4] or 1)) / grid.Rows
			check(x0 >= 0.5 - 0.11 and x1 <= 0.5 + 0.11 and y0 >= 0.5 - 0.24 and y1 <= 0.5 + 0.24, "the sick o shows")
		end
		local eye = Pure.CLOSED_EYE
		for _, cell in eye.Cells do
			check(cell[1] + (cell[3] or 1) <= eye.Cols and cell[2] + (cell[4] or 1) <= eye.Rows, "closed eye")
		end
		for _, mood in Pure.BROW_ORDER do
			check(Pure.BROWS[mood] ~= nil, mood)
		end
	end)

	test("every Bits name in the data is one the layout draws", function()
		for _, c in CAST do
			for _, name in c.Look.Bits or {} do
				check(Pure.KNOWN_BITS[name], c.Id .. ": unknown bit " .. name)
			end
		end
	end)

	test("junk looks still build a whole creature", function()
		local junk = { 5, {}, { Shape = "Nope", Ears = 3, Top = {}, Bits = { 1, "Glasses", "Nope" } } }
		for _, look in junk do
			local layout = Pure.layout(look, { Scale = -1 })
			expect(#layout.Parts > 10).toBe(true)
			expect(hasSocket(layout, "HeadSocket")).toBe(true)
		end
		expect(#Pure.layout(nil).Parts > 10).toBe(true)
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- 2. The real builders under the worldmock
------------------------------------------------------------------------------------------------------------------

-- Model:ScaleTo / GetScale / GetExtentsSize, as Roblox does them, for this world's Models only.
local function withModelScaling(world)
	local meta = getmetatable(world.new("Model"))
	local base = meta.__index
	local extra = {}
	function extra.GetScale(self)
		return rawget(self, "_p")._scale or 1
	end
	function extra.ScaleTo(self, s)
		local p = rawget(self, "_p")
		local f = s / (p._scale or 1)
		local pivot = self:GetPivot()
		for _, d in self:GetDescendants() do
			if d:IsA("BasePart") then
				local rel = pivot:ToObjectSpace(d.CFrame)
				d.CFrame = pivot * (rel - rel.Position + rel.Position * f)
				d.Size = d.Size * f
			elseif d.ClassName == "Attachment" then
				local cf = rawget(d, "_p").CFrame
				if cf then
					d.CFrame = cf - cf.Position + cf.Position * f
				end
			end
		end
		p._scale = s
	end
	function extra.GetExtentsSize(self)
		local _, size = self:GetBoundingBox()
		return size
	end
	meta.__index = function(self, k)
		local fn = extra[k]
		if fn and rawget(self, "_p").ClassName == "Model" then
			return fn
		end
		return base(self, k)
	end
end

local world = World.new()
withModelScaling(world)
local CB = world.load(BUILDER)
local NB = world.load("src/server/NurseBuilder.luau")
local Enum = World.roblox.Enum

local function partsOf(model): { any }
	return world.parts(model)
end

local function noHighlightNoShadowLight(model, who: string)
	for _, d in model:GetDescendants() do
		check(d.ClassName ~= "Highlight", who .. " has a Highlight")
		if d:IsA("Light") then
			check(d.Shadows == false, who .. ": " .. d.Name .. " casts shadows")
		end
	end
end

-- Root, Core, PoseJoint, the limb motors, every part welded on, the sockets, IconAnchor.
local function rigContract(model, look, who: string)
	local root = model.PrimaryPart
	check(root and root.Name == "Root" and root.Anchored == true, who .. ": Root is the PrimaryPart")
	local core = model:FindFirstChild("Core")
	check(core and core:IsA("BasePart"), who .. " has no Core")
	local pose = root:FindFirstChild("PoseJoint")
	check(pose and pose.ClassName == "Motor6D" and pose.Part0 == root and pose.Part1 == core, who .. ": PoseJoint")
	for _, name in SOCKETS do
		local s = core:FindFirstChild(name)
		check(s and s.ClassName == "Attachment", who .. ": Core has no " .. name)
	end
	check(root:FindFirstChild("IconAnchor") ~= nil, who .. " has no IconAnchor")
	local driven = {}
	for _, key in { "ArmR", "ArmL", "Tail" } do
		local motor = core:FindFirstChild(key .. "Joint")
		if motor then
			check(motor.ClassName == "Motor6D" and motor.Part0 == core, who .. ": " .. key .. "Joint")
			driven[motor.Part1] = true
		end
	end
	check(core:FindFirstChild("ArmRJoint") and core:FindFirstChild("ArmLJoint"), who .. ": no arm joints")
	check((core:FindFirstChild("TailJoint") ~= nil) == (look.Extra == "Tail"), who .. ": TailJoint")
	for _, part in partsOf(model) do
		if part ~= root then
			check(part.Anchored == false, who .. ": " .. part.Name .. " is anchored")
			check(part.CollisionGroup == "Patients", who .. ": " .. part.Name .. " CollisionGroup")
			check(part.CanCollide == false and part.CanQuery == false, who .. ": " .. part.Name .. " collides")
			if part ~= core then
				local welded = part:FindFirstChildOfClass("WeldConstraint") ~= nil
				check(welded or driven[part], who .. ": " .. part.Name .. " hangs on nothing")
			end
		end
		if part.Name == "Arm" then
			check(part:FindFirstChild("HandSocket") ~= nil, who .. ": an Arm without a HandSocket")
		end
	end
	check(type(model:GetAttribute("BuildScale")) == "number", who .. ": BuildScale")
	check(type(model:GetAttribute("HeadRadius")) == "number", who .. ": HeadRadius")
	check(typeof(model:GetAttribute("NeckSize")) == "Vector3", who .. ": NeckSize")
	check(math.abs(model:GetScale() - model:GetAttribute("BuildScale")) < 1e-9, who .. ": GetScale is BuildScale")
end

local function studsCheck(model, who: string, variant: boolean)
	local plates = 0
	for _, part in partsOf(model) do
		if part:GetAttribute("Studded") == true then
			plates += 1
			check(part.Name == "StudTop", who .. ": " .. part.Name .. " is studded")
			check(part.Material == Enum.Material.Plastic, who .. ": the plate is Plastic")
			if variant then
				check(part.MaterialVariant == "CureStuds", who .. ": the plate takes the CureStuds variant")
			else
				check(part.TopSurface == Enum.SurfaceType.Studs, who .. ": studs on the plate's top")
				check(part.BottomSurface == Enum.SurfaceType.Smooth, who .. ": never on its bottom")
			end
		elseif part.Name ~= "Root" and part.Name ~= "Core" then
			local m = part.Material
			check(
				m == Enum.Material.SmoothPlastic or m == Enum.Material.Neon,
				who .. ": " .. part.Name .. " " .. tostring(m)
			)
		end
	end
	check(plates <= 1, who .. ": " .. plates .. " stud plates")
end

T.describe("BlockyCreatures build", function()
	test("every patient and regular, plain and in every variant: the rig contract, under 40 parts", function()
		for _, c in CAST do
			if c.Kind ~= "Nurse" then
				local plain = nil
				for _, variant in { "", "Sparkly", "Frosty", "Golden" } do
					local who = c.Id .. (if variant ~= "" then " " .. variant else "")
					local model = CB.build(c.Id, if variant ~= "" then variant else nil)
					local count = #partsOf(model)
					check(count < 40, who .. " has " .. count .. " parts")
					plain = plain or count
					check(count == plain, who .. ": a variant adds no parts")
					rigContract(model, c.Look, who)
					noHighlightNoShadowLight(model, who)
					studsCheck(model, who, false)
					check(model:HasTag("ClinicCreature") and model:HasTag("CreatureMotion"), who .. ": tags")
					check(model:GetAttribute("PatientId") == c.Id, who .. ": PatientId")
					check(CB.badge(model) ~= nil, who .. " has no badge")
					local fx = model.PrimaryPart:FindFirstChild("FX")
					check(fx ~= nil, who .. " has no FX")
					if variant ~= "" then
						local emitter = ({ Sparkly = "Sparkle", Frosty = "Frost", Golden = "Golden" })[variant]
						check(fx:FindFirstChild(emitter) ~= nil, who .. " has no " .. emitter)
					end
					if c.Night then
						local glow = fx:FindFirstChild("NightGlow")
						check(glow and glow.Shadows == false, who .. ": NightGlow")
						local pad = model:FindFirstChild("GlowRing")
						check(pad and pad.Material == Enum.Material.Neon, who .. ": the glow pad")
					else
						check(model:FindFirstChild("GlowRing") == nil, who .. ": a day creature has no glow pad")
					end
				end
			end
		end
	end)

	-- Logic/Building.DOOR_WIDTH is 6 and the widest creature does not fit it (CloudSheep: 6.9 across in the Phase 3
	-- review's measure): its sides pass through the door frame. That traps nobody only because nothing of a creature
	-- collides, the Root and the glow pad included, in every variant.
	test("no part of any creature or nurse collides (a doorway narrower than a creature can't trap it)", function()
		local built = 0
		local function none(model, who: string)
			built += 1
			for _, part in partsOf(model) do
				check(part.CanCollide == false, who .. ": " .. part.Name .. " is CanCollide")
			end
			check(model.PrimaryPart.CanCollide == false, who .. ": the Root is CanCollide")
		end
		for _, c in CAST do
			if c.Kind == "Nurse" then
				none(NB.build(c.Id), "Nurse " .. c.Id)
			else
				for _, variant in { "", "Sparkly", "Frosty", "Golden" } do
					none(CB.build(c.Id, if variant ~= "" then variant else nil), c.Id .. " " .. variant)
				end
			end
		end
		expect(built > #CAST).toBe(true)
	end)

	test("the stud plate is whole studs at the built size", function()
		for _ = 1, 6 do
			local model = CB.build("MossMole")
			local plate = model:FindFirstChild("StudTop")
			for _, axis in { "X", "Z" } do
				local studs = plate.Size[axis]
				check(math.abs(studs - math.floor(studs + 0.5)) < 1e-6, "MossMole's plate " .. axis .. " = " .. studs)
			end
		end
	end)

	test("Variant mode: the plate takes the CureStuds variant (and nothing else does)", function()
		world.setVariant(true)
		local ok, err = pcall(function()
			for _, id in { "DumplingFrog", "ToastPup", "CactusCub" } do
				studsCheck(CB.build(id), id, true)
			end
		end)
		world.setVariant(false)
		check(ok, tostring(err))
	end)

	test("night tips glow Neon; by day they're SmoothPlastic", function()
		local moth = CB.build("MoonMoth")
		local neon = 0
		for _, part in partsOf(moth) do
			if part.Material == Enum.Material.Neon then
				neon += 1
			end
		end
		expect(neon).toBe(3) -- two antennae tips and the glow pad
		local sheep = CB.build("CloudSheep")
		for _, part in partsOf(sheep) do
			check(part.Material ~= Enum.Material.Neon, "CloudSheep glows by day: " .. part.Name)
		end
	end)

	test("setMood: Sick shows the half-lids and a little o; Sleep closes the eyes; Happy and Sad", function()
		local model = CB.build("DumplingFrog")
		local function visible(partName: string, guiName: string): string
			local part = model:FindFirstChild(partName)
			local shown = {}
			for _, child in part:FindFirstChild(guiName):GetChildren() do
				if child.Visible then
					table.insert(shown, child.Name)
				end
			end
			table.sort(shown)
			return table.concat(shown, ",")
		end
		local function each(name: string, fn)
			for _, child in model:GetChildren() do
				if child.Name == name then
					fn(child)
				end
			end
		end
		CB.setMood(model, "Sick")
		each("EyeLid", function(p)
			expect(p.Transparency).toBe(0)
		end)
		each("Eye", function(p)
			expect(p.Transparency).toBe(0)
		end)
		each("Lid", function(p)
			expect(p.LidGui.Enabled).toBe(false)
		end)
		expect(visible("Mouth", "MouthGui")).toBe("Sick")
		expect(visible("Brow", "BrowGui")).toBe("Worried")

		CB.setMood(model, "Sleep")
		each("EyeLid", function(p)
			expect(p.Transparency).toBe(1)
		end)
		each("EyeShine", function(p)
			expect(p.Transparency).toBe(1)
		end)
		each("Lid", function(p)
			expect(p.LidGui.Enabled).toBe(true)
		end)
		expect(visible("Mouth", "MouthGui")).toBe("Smile")

		CB.setMood(model, "Happy")
		each("EyeLid", function(p)
			expect(p.Transparency).toBe(1)
		end)
		each("Eye", function(p)
			expect(p.Transparency).toBe(0)
		end)
		expect(visible("Mouth", "MouthGui")).toBe("Happy")
		expect(visible("Brow", "BrowGui")).toBe("Happy")

		CB.setMood(model, "Sad")
		expect(visible("Mouth", "MouthGui")).toBe("Sad")
		expect(visible("Brow", "BrowGui")).toBe("Sad")

		local teapot = CB.build("GrumpyTeapot")
		CB.setMood(teapot, "Sick")
		local shown = {}
		for _, child in teapot.Brow.BrowGui:GetChildren() do
			if child.Visible then
				table.insert(shown, child.Name)
			end
		end
		expect(table.concat(shown, ",")).toBe("Grumpy")
		check(teapot.Core:FindFirstChild("SpoutSocket") ~= nil, "the teapot has no SpoutSocket")
	end)

	test("the half-lid matches the face after every variant tint", function()
		for _, variant in { "Sparkly", "Frosty", "Golden" } do
			for _, id in { "DumplingFrog", "ToastPup" } do
				local model = CB.build(id, variant)
				local face = if id == "ToastPup" then model.Belly else model.Head
				for _, child in model:GetChildren() do
					if child.Name == "EyeLid" or child.Name == "StudTop" and id ~= "ToastPup" then
						check(child.Color == face.Color, id .. " " .. variant .. ": " .. child.Name .. " off colour")
					end
				end
			end
		end
	end)

	test("buildLook: no tags, no badge, a happy face, IconAnchor over the head (the mascot's look too)", function()
		local mascot = {
			Shape = "Blob",
			Body = "#A8F0DA",
			Accent = "#FF9CCB",
			Ears = "Round",
			Top = "Bow",
			Extra = "None",
			Scale = 0.6,
		}
		for _, look in { mascot, NursesData.PuffPup and NursesData.PuffPup.Look or mascot } do
			local model = CB.buildLook(look, "Test")
			expect(model.Name).toBe("Test")
			expect(model:HasTag("ClinicCreature")).toBe(false)
			expect(model:HasTag("CreatureMotion")).toBe(false)
			expect(CB.badge(model)).toBeNil()
			rigContract(model, look, "buildLook")
			local anchor = model.PrimaryPart:FindFirstChild("IconAnchor")
			local _, size = model:GetBoundingBox()
			check(anchor.Position.Y >= size.Y, "IconAnchor is over the head")
			local shown = {}
			for _, child in model.Mouth.MouthGui:GetChildren() do
				if child.Visible then
					table.insert(shown, child.Name)
				end
			end
			expect(table.concat(shown, ",")).toBe("Happy")
		end
	end)

	test("every nurse: under 40 parts, a block cap on its head with our paw-heart, never a cross", function()
		for _, id in NursesData.Order do
			local model = NB.build(id)
			local who = "Nurse " .. id
			local count = #partsOf(model)
			check(count < 40, who .. " has " .. count .. " parts")
			rigContract(model, NursesData[id].Look, who)
			noHighlightNoShadowLight(model, who)
			studsCheck(model, who, false)
			for _, d in model:GetDescendants() do
				check(not string.find(string.lower(d.Name), "cross", 1, true), who .. ": " .. d.Name)
			end
			local cap, brim = model:FindFirstChild("NurseCap"), model:FindFirstChild("CapBrim")
			check(cap and brim, who .. " has no cap")
			check(cap:FindFirstChild("CapGui") and cap.CapGui:FindFirstChild("PawHeart", true), who .. ": no paw-heart")
			check(cap:FindFirstChildOfClass("WeldConstraint").Part0 == model.Core, who .. ": the cap rides on Core")
			local head = model:FindFirstChild("Head") or model:FindFirstChild("Body")
			local headTop = head.Position.Y + head.Size.Y / 2
			local capBottom = cap.Position.Y - cap.Size.Y / 2
			check(capBottom >= headTop - 0.2 and capBottom <= headTop + 0.4, who .. ": the cap sits on the head")
			check(cap.Size.X <= head.Size.X, who .. ": the cap is narrower than the head")
			local front = head.Position.Z - head.Size.Z / 2
			check(cap.Position.Z - cap.Size.Z / 2 >= front - 0.01, who .. ": the cap is flush with the face")
			expect(model:GetAttribute("NurseId")).toBe(id)
			expect(model:GetAttribute("Task")).toBe("Idle")
			NB.setGlow(model, true)
			local holder = model.PrimaryPart:FindFirstChild("RarityFX") or model.PrimaryPart
			local glow = holder:FindFirstChild("RarityGlow")
			check(glow and glow.Shadows == false, who .. ": the rarity glow casts shadows")
			NB.setGlow(model, false)
			check(holder:FindFirstChild("RarityGlow") == nil, who .. ": the glow didn't go off")
		end
	end)

	test("Epic and up sparkle; the task bubble and ability ring hang over the blocky head", function()
		local epic, common = nil, nil
		for _, id in NursesData.Order do
			local rarity = NursesData[id].Rarity
			if rarity == "Epic" and not epic then
				epic = id
			elseif rarity == "Common" and not common then
				common = id
			end
		end
		local model = NB.build(epic)
		check(model.PrimaryPart:FindFirstChild("RarityFX") ~= nil, "an Epic nurse doesn't sparkle")
		check(NB.build(common).PrimaryPart:FindFirstChild("RarityFX") == nil, "a Common nurse sparkles")
		NB.setTask(model, "Healing")
		local anchor = model.PrimaryPart.IconAnchor
		check(anchor:FindFirstChild("TaskGui") ~= nil, "no task bubble")
		for _, id in NursesData.Order do -- every nurse: IconAnchor clear of its highest block (the cap, a star, ears)
			local nurse = NB.build(id)
			local top = -math.huge
			for _, part in partsOf(nurse) do
				top = math.max(top, part.Position.Y + part.Size.Y / 2)
			end
			local y = nurse.PrimaryPart.IconAnchor.Position.Y
			check(y >= top + 0.2, string.format("%s: IconAnchor at %.2f, its top at %.2f", id, y, top))
		end
	end)
end)
