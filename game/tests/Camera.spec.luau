--!nocheck
-- The camera (memory-20261117-006: "walls go see-through between you and the camera"; simple-start design §4):
--   · Server/Main sets DevCameraOcclusionMode = Invisicam on StarterPlayer at start and on every Player as they join
--     (so it holds without a place-file change), and nothing else sets it;
--   · Feel/Cutaway (the storeys above you, upstairs) never writes LocalTransparencyModifier, the property Invisicam
--     fades with and puts back, so the two never fight; its fade never lowers a part's Transparency (a part a builder
--     hid stays hidden); HospitalFX's grow-in writes through it;
--   · UI/Tutorial's welcome sweep reads Logic/Building (the bigger clinic), never a hardcoded spot.
-- Everything is read from the shipped source. Run from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local B = require("../src/shared/Logic/Building")
local Config = require("./config")

local function source(path: string): string
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("can't find " .. path .. " (run from game/)")
end

local function pure(path: string, env: { [string]: any }?): any
	local text = source(path)
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to and to > from, path .. ": no PURE block")
	local chunk = string.sub(text, from, to - 1) .. "\nreturn Pure\n"
	return luau.load(chunk, { debugName = path .. " (pure)", environment = env, injectGlobals = true })()
end

-- A function's text, from its header to the first `end` at the start of a line.
local function body(text: string, header: string): string
	local from = string.find(text, header, 1, true)
	assert(from, "no " .. header)
	local stop = string.find(text, "\nend\n", from, true)
	return string.sub(text, from, stop or #text)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

-- Every .luau file under a folder.
local function files(dir: string, out: { string }?): { string }
	local list = out or {}
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			files(path, list)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(list, path)
		end
	end
	return list
end

local ROOT = if fs.isDir("src") then "src" else "game/src"

T.describe("Camera: Invisicam for everyone (Server/Main)", function()
	local main = source("src/server/Main.server.luau")

	test("StarterPlayer at start, and every Player as they join (and those here already)", function()
		expect(has(main, 'game:GetService("StarterPlayer")')).toBe(true)
		expect(has(main, "Enum.DevCameraOcclusionMode.Invisicam")).toBe(true)
		local helper = body(main, "local function seeThrough(")
		expect(has(helper, ".DevCameraOcclusionMode = OCCLUSION")).toBe(true)
		expect(has(helper, "pcall(")).toBe(true) -- a refused write never stops the clinic opening
		expect(has(main, "\nseeThrough(StarterPlayer)\n")).toBe(true) -- top level: at start
		expect(has(body(main, "local function onPlayer("), "seeThrough(player)")).toBe(true)
		expect(has(main, "Players.PlayerAdded:Connect(onPlayer)")).toBe(true)
		expect(has(main, "for _, player in Players:GetPlayers() do\n\tonPlayer(player)")).toBe(true)
		-- before the systems start (a player can't join between the two)
		local set = string.find(main, "seeThrough(StarterPlayer)", 1, true)
		local systems = string.find(main, "for _, name in START_ORDER do", 1, true)
		expect(set < systems).toBe(true)
	end)

	test("nothing else sets the occlusion mode or squeezes the zoom", function()
		for _, path in files(ROOT) do
			local text = fs.readFile(path)
			if not string.find(path, "Main.server.luau", 1, true) then
				if has(text, "DevCameraOcclusionMode") and string.find(text, "DevCameraOcclusionMode%s*=") then
					error(path .. " sets DevCameraOcclusionMode (Server/Main owns it)")
				end
			end
			-- a max zoom under the bigger clinic's size would squash the camera in again
			for value in string.gmatch(text, "CameraMaxZoomDistance%s*=%s*([%d%.]+)") do
				if tonumber(value) < 40 then
					error(path .. " caps the zoom at " .. value)
				end
			end
		end
	end)
end)

T.describe("Camera: Feel/Cutaway works with Invisicam", function()
	local text = source("src/client/Feel/Cutaway.luau")
	local Cut = pure("src/client/Feel/Cutaway.luau")

	test("it never writes LocalTransparencyModifier (Invisicam's own property)", function()
		expect(string.find(text, "LocalTransparencyModifier%s*=")).toBeNil()
		-- it writes Transparency and puts back the value it found
		expect(has(body(text, "local function apply("), "Pure.fade(descendant.Transparency, amount)")).toBe(true)
		expect(has(body(text, "local function restore("), "part.Transparency = base")).toBe(true)
	end)

	test("fade: the look of a LocalTransparencyModifier, never lower than the part's own", function()
		expect(Cut.fade(0, 1)).toBe(1)
		expect(Cut.fade(0, 0)).toBe(0)
		expect(Cut.fade(0, Cut.FADE)).toBeCloseTo(Cut.FADE)
		expect(Cut.fade(0.5, 0.6)).toBeCloseTo(0.8)
		expect(Cut.fade(1, 0)).toBe(1) -- a part a builder hid (the stairwell's steps at Lv 1) stays hidden
		expect(Cut.fade(1, 0.6)).toBe(1)
		for _, t in { 0, 0.2, 0.5, 0.9, 1 } do
			for _, a in { 0, 0.3, 0.6, 1 } do
				local out = Cut.fade(t, a)
				if out < t or out > 1 then
					error(string.format("fade(%s, %s) = %s", t, a, out))
				end
			end
		end
		expect(Cut.fade(-1, 2)).toBe(1) -- junk is clamped
	end)

	test("the ground floor hides nothing (Invisicam alone there); upstairs the storeys above go", function()
		expect(Cut.hide(0, 2, false)).toBe(0)
		expect(Cut.hide(0, 1, true)).toBe(0)
		expect(Cut.hide(1, 2, false)).toBe(1)
		expect(Cut.hide(1, 1, true)).toBe(Cut.FADE)
		expect(Cut.hide(1, 0, true)).toBe(0)
	end)

	test("the bigger building's footprint counts you in, the yard doesn't", function()
		local rect = B.footprint(1, 0)
		expect(Cut.inside(B.HALF_X - 1, B.BACK - 1, rect, Cut.MARGIN)).toBe(true)
		expect(Cut.inside(-B.HALF_X + 1, B.FRONT + 1, rect, Cut.MARGIN)).toBe(true)
		expect(Cut.inside(B.BAY_AMBULANCE.X, B.BAY_AMBULANCE.Z, rect, Cut.MARGIN)).toBe(false)
		expect(Cut.inside(0, B.CANOPY.Z0, rect, Cut.MARGIN)).toBe(false)
	end)

	test(
		"HospitalFX's grow-in writes through the cutaway (a level-up upstairs keeps the storey above hidden)",
		function()
			local fx = source("src/client/Feel/HospitalFX.luau")
			local grow = body(fx, "local function growIn(")
			expect(has(grow, "Cutaway.baseOf(p)")).toBe(true)
			expect(has(grow, "Cutaway.write(p, 1)")).toBe(true)
			expect(has(grow, "Cutaway.write(p, original[p])")).toBe(true)
			expect(string.find(grow, "p%.Transparency%s*=")).toBeNil()
		end
	)
end)

T.describe("Camera: the welcome sweep reads Logic/Building", function()
	local Card = pure("src/client/UI/Tutorial.luau", {})

	test("it starts over the street to the left and swings right, in front of the façade, over the canopy", function()
		local a, b = Card.sweepPoints(B.HALF_X, B.FRONT, B.GROUND)
		expect(a.X < 0 and b.X > 0).toBe(true)
		for _, point in { a, b } do
			expect(point.Z < B.CANOPY.Z0).toBe(true) -- outside, in front of the canopy
			expect(point.Y > B.CANOPY.Y + 2).toBe(true)
			expect(math.abs(point.X) < B.HALF_X).toBe(true)
			expect(math.abs(point.Z) <= Config.Town.PlotSize / 2).toBe(true) -- over the plot
		end
		expect(a.Y > b.Y).toBe(true) -- from high to low
		local text = source("src/client/UI/Tutorial.luau")
		local sweep = body(text, "local function sweep(")
		expect(has(sweep, "Pure.sweepPoints(BuildingLogic.HALF_X, BuildingLogic.FRONT, BuildingLogic.GROUND)")).toBe(
			true
		)
		expect(string.find(sweep, "CFrame%.new%(%-?%d")).toBeNil() -- no hardcoded spot
	end)
end)
