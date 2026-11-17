--!nocheck
-- A patient sits on its waiting-room seat (Joshua, 2026-11-17: "the patient still doesnt sit on the chair first").
-- Run from game/ with the rest:  lune run tests/run
--   1. Logic/CreatureSize.seatFit and .sitEase (pure).
--   2. Every species in Data/Patients and Data/Regulars, at its smallest and biggest wobble, measured the way
--      Server/Patients U.sitFit measures it (from Server/CreatureBuilder's PURE layout): its bottom rests on the seat
--      top, its body and head stop at the chair back and nothing pokes through the wall, its curled tail included,
--      with room for the client's recline; most of its body is over the cushion.
--   3. The seats face into the room (their backs against an outer wall).
--   4. The shipped code keeps the rules: Patients' K.SEAT_BACK is HospitalBuilder's chair back, every way on or off
--      a seat goes through U.setSeated (OnSeat and the Seated attribute together), no idle hops on a seat, and
--      Feel/CreatureActing plays the Seated attribute.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local T = require("./expect")
local expect, test = T.expect, T.test
local World = require("./worldmock")
local Config = require("./config")

local CreatureSize = require("../src/shared/Logic/CreatureSize")
local Building = require("../src/shared/Logic/Building")
local PatientsData = require("../src/shared/Data/Patients")
local Regulars = require("../src/shared/Data/Regulars")

local SIT = CreatureSize.SIT

local function read(path: string): string
	return fs.readFile(World.find(path))
end

local function pureBlock(path: string): any
	local text = read(path)
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to, path .. ": no PURE-BEGIN block")
	local chunk = string.sub(text, from, to - 1) .. "\nreturn Pure\n"
	return luau.load(chunk, { debugName = path .. ":Pure" })()
end

local Builder = pureBlock("src/server/CreatureBuilder.luau")

local function check(condition: any, message: string)
	if not condition then
		error(message, 2)
	end
end

-- The seat as Server/Patients hands it to seatFit (studs from the seat's centre).
local function seatBack(): number
	local text = read("src/server/HospitalBuilder.luau")
	local back = string.match(text, "Pure%.SEAT = {[^}]-Back = ([%d%.]+)")
	assert(back, "HospitalBuilder: no Pure.SEAT.Back")
	return tonumber(back)
end
local HALF = Building.SEAT_SIZE / 2
local SEAT = { Cushion = HALF - seatBack(), Wall = HALF }

------------------------------------------------------------------------------------------------------------------
-- Measuring a creature the way U.sitFit does (unit layout x scale; +Z is its back, y = 0 the ground under it)
------------------------------------------------------------------------------------------------------------------

local function extents(part): (number, number, number) -- half height, half depth, back
	local size, pos = part.Size, part.Pos
	local rot = part.Rot or { X = 0, Y = 0, Z = 0 }
	local cf = roblox.CFrame.Angles(rot.X, rot.Y, rot.Z)
	local _, _, _, _, _, _, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local hy = (math.abs(r10) * size.X + math.abs(r11) * size.Y + math.abs(r12) * size.Z) / 2
	local hz = (math.abs(r20) * size.X + math.abs(r21) * size.Y + math.abs(r22) * size.Z) / 2
	return hy, hz, pos.Z + hz
end

local function isTail(part): boolean
	return part.Joint == "Tail" or part.Ride == "Tail"
end

-- { Hip, Body, Reach } in studs, plus the creature's top and its tail's reach back once curled (TailCurl).
local function measure(look, scale: number): any
	local layout = Builder.layout(look, { Scale = scale })
	local fit = { Hip = 0, Body = 0, Reach = 0 }
	local top, tailBack = 0, -math.huge
	local pivot = nil
	for _, part in layout.Parts do
		if part.Joint == "Tail" then
			pivot = part.Pivot
		end
	end
	for _, part in layout.Parts do
		if part.Clear == 1 then
			continue -- see-through plates: U.sitFit skips them too
		end
		local hy, hz, back = extents(part)
		top = math.max(top, part.Pos.Y + hy)
		if part.Name == "Body" or part.Name == "Head" then
			fit.Body = math.max(fit.Body, back)
			if part.Name == "Body" then
				fit.Hip = part.Pos.Y - hy
			end
		end
		if isTail(part) and pivot then
			-- Turned by -TailCurl about the joint's pivot (x): its centre's z, plus a turned cube's half-depth.
			local y, z = part.Pos.Y - pivot.Y, part.Pos.Z - pivot.Z
			local a = -SIT.TailCurl
			local zTurned = y * math.sin(a) + z * math.cos(a)
			local half = (math.abs(math.cos(a)) * part.Size.Z + math.abs(math.sin(a)) * part.Size.Y) / 2
			tailBack = math.max(tailBack, pivot.Z + zTurned + half)
		else
			fit.Reach = math.max(fit.Reach, back)
		end
	end
	return {
		Fit = { Hip = fit.Hip * scale, Body = fit.Body * scale, Reach = fit.Reach * scale },
		Top = top * scale,
		TailBack = if tailBack > -math.huge then tailBack * scale else nil,
		Front = (function()
			local front = 0
			for _, part in layout.Parts do
				if part.Name == "Body" or part.Name == "Head" then
					local _, hz = extents(part)
					front = math.max(front, hz - part.Pos.Z)
				end
			end
			return front * scale
		end)(),
	}
end

local CAST = {}
for _, id in PatientsData.Order do
	table.insert(CAST, { Id = id, Look = PatientsData[id].Look })
end
for _, id in Regulars.Order do
	table.insert(CAST, { Id = id, Look = Regulars[id].Look })
end

------------------------------------------------------------------------------------------------------------------

T.describe("CreatureSize.seatFit", function()
	test("a small sitter sits in the seat's middle, its bottom on the seat top", function()
		local forward, drop = CreatureSize.seatFit({ Hip = 0.5, Body = 0.6, Reach = 0.8 }, SEAT)
		expect(forward).toBe(0)
		expect(drop).toBeCloseTo(0.5)
	end)

	test("a deep body sits forward to keep Gap off the chair back", function()
		local forward = CreatureSize.seatFit({ Hip = 0.5, Body = 2, Reach = 2 }, SEAT)
		expect(forward).toBeCloseTo(2 + SIT.Gap - SEAT.Cushion)
	end)

	test("something reaching further back keeps Gap off the wall", function()
		local forward = CreatureSize.seatFit({ Hip = 0.5, Body = 0.5, Reach = 2.5 }, SEAT)
		expect(forward).toBeCloseTo(2.5 + SIT.Gap - SEAT.Wall)
	end)

	test("never past MaxForward, never sunk past MaxHip, junk is zero", function()
		local forward, drop = CreatureSize.seatFit({ Hip = 9, Body = 50, Reach = 50 }, SEAT)
		expect(forward).toBe(SIT.MaxForward)
		expect(drop).toBe(SIT.MaxHip)
		forward, drop = CreatureSize.seatFit({ Hip = 0 / 0, Body = math.huge, Reach = -3 }, SEAT)
		expect(forward).toBe(0)
		expect(drop).toBe(0)
	end)

	test("the client's recline moves the tallest sitter's top back less than Gap", function()
		check(SIT.MaxHeight * math.sin(SIT.Recline) < SIT.Gap, "the recline would push a top into the chair back")
	end)
end)

T.describe("CreatureSize.sitEase", function()
	test("settles in over EaseSeconds and back out", function()
		local half = SIT.EaseSeconds / 2
		expect(CreatureSize.sitEase(0, 1, half)).toBeCloseTo(0.5)
		expect(CreatureSize.sitEase(0.5, 1, half)).toBeCloseTo(1)
		expect(CreatureSize.sitEase(1, 1, 5)).toBe(1)
		expect(CreatureSize.sitEase(1, 0, half)).toBeCloseTo(0.5)
		expect(CreatureSize.sitEase(0.2, 0, 5)).toBe(0)
	end)

	test("junk time and junk values never leave 0..1", function()
		expect(CreatureSize.sitEase(0.4, 1, -2)).toBeCloseTo(0.4)
		expect(CreatureSize.sitEase(0.4, 1, 0 / 0)).toBeCloseTo(0.4)
		expect(CreatureSize.sitEase(7, 0, 0)).toBe(1)
		expect(CreatureSize.sitEase(-3, 1, 0)).toBe(0)
	end)
end)

T.describe("every species on a seat", function()
	test("rests its bottom on the seat top, clear of the chair back and the wall, mostly over the cushion", function()
		for _, who in CAST do
			for _, roll in { 0, 0.5, 1 } do
				local scale = CreatureSize.scale(who.Look.Scale, Config, roll)
				local m = measure(who.Look, scale)
				local label = who.Id .. " at " .. string.format("%.2f", scale)
				local forward, drop = CreatureSize.seatFit(m.Fit, SEAT)
				check(forward < SIT.MaxForward, label .. " is too big for the seat (MaxForward)")
				-- Its pivot is `drop` under the seat top: the body's bottom (Hip) is exactly on it.
				check(math.abs(drop - m.Fit.Hip) < 1e-6, label .. ": its bottom is not on the seat top")
				check(drop < 1.6, label .. ": its pivot would be under the floor") -- HospitalBuilder Pure.SEAT.Height
				-- Measured from the seat's centre along its facing (+ = into the room).
				check(m.Fit.Body - forward <= SEAT.Cushion - SIT.Gap + 1e-6, label .. " pokes through the chair back")
				check(m.Fit.Reach - forward <= SEAT.Wall - SIT.Gap + 1e-6, label .. " pokes through the wall")
				if m.TailBack then
					check(m.TailBack - forward <= SEAT.Wall + 1e-6, label .. ": its curled tail pokes through the wall")
				end
				check(m.Top <= SIT.MaxHeight, label .. " is taller than SIT.MaxHeight (" .. m.Top .. ")")
				-- Over the cushion: from the chair back's face to the seat's front edge, at least 1.5 studs of body.
				local over = math.min(HALF, forward + m.Front) - math.max(-SEAT.Cushion, forward - m.Fit.Body)
				check(over >= 1.5, label .. " barely touches the cushion (" .. over .. ")")
			end
		end
	end)
end)

T.describe("the waiting-room seats", function()
	test("each faces into the room, its back against an outer wall", function()
		local box = Building.footprint(1, 0)
		local w = Building.WALL
		for index, seat in Building.SEATS do
			local dx, dz = Building.facing(seat.Face)
			local bx, bz = seat.X - dx * HALF, seat.Z - dz * HALF
			local against = math.abs(bx - (box.X0 + w)) < 0.01
				or math.abs(bx - (box.X1 - w)) < 0.01
				or math.abs(bz - (box.Z0 + w)) < 0.01
				or math.abs(bz - (box.Z1 - w)) < 0.01
			check(against, "seat " .. index .. "'s back is not against an outer wall")
			local front = Building.seatFront(seat)
			local cx, cz = (box.X0 + box.X1) / 2, (box.Z0 + box.Z1) / 2
			local before = math.abs(seat.X - cx) + math.abs(seat.Z - cz)
			local after = math.abs(front.X - cx) + math.abs(front.Z - cz)
			check(after < before, "seat " .. index .. " faces the wall, not the room")
		end
	end)
end)

T.describe("the shipped code", function()
	local patients = read("src/server/Patients.luau")
	local acting = read("src/client/Feel/CreatureActing.luau")

	local function body(source: string, header: string): string
		local from = string.find(source, header, 1, true)
		assert(from, "no " .. header)
		local stop = string.find(source, "\nend\n", from, true)
		return string.sub(source, from, stop)
	end

	test("Patients' chair back is HospitalBuilder's", function()
		local k = tonumber(string.match(patients, "K%.SEAT_BACK = ([%d%.]+)"))
		expect(k).toBe(seatBack())
	end)

	test("OnSeat changes only in U.setSeated, which sets the Seated attribute with it", function()
		local setter = body(patients, "function U.setSeated(")
		check(string.find(setter, 'SetAttribute("Seated"', 1, true), "U.setSeated doesn't set the Seated attribute")
		local outside = string.gsub(patients, "function U%.setSeated%(.-\nend\n", "")
		for line in string.gmatch(outside, "[^\n]+") do
			if string.find(line, "OnSeat%s*=") and not string.find(line, "^%s*OnSeat = false,") then
				error("OnSeat set outside U.setSeated: " .. line)
			end
		end
	end)

	test("getting up, freeing a seat and sitting down all go through U.setSeated", function()
		check(string.find(body(patients, "local function freeSeat("), "U.setSeated(p, false)", 1, true), "freeSeat")
		check(string.find(body(patients, "local function getUp("), "U.setSeated(p, false)", 1, true), "getUp")
		check(string.find(body(patients, "local function findSeat("), "U.setSeated(p, true)", 1, true), "findSeat")
		check(string.find(body(patients, "local function findSeat("), "U.seatPose(state, seat, p)", 1, true), "pose")
		-- Removing a patient (admin clear, plot reset, a visit's end) frees its seat.
		check(string.find(body(patients, "local function removePatient("), "freeSeat(p)", 1, true), "removePatient")
	end)

	test("no idle hops on a seat", function()
		check(string.find(body(patients, "local function waitSeated("), "not p.OnSeat", 1, true), "waitSeated hops")
	end)

	test("Feel/CreatureActing plays the Seated attribute", function()
		check(string.find(acting, 'GetAttribute("Seated")', 1, true), "CreatureActing ignores Seated")
		check(string.find(acting, "SIT.Recline", 1, true), "no recline")
		check(string.find(acting, "SIT.TailCurl", 1, true), "no tail curl")
	end)
end)
