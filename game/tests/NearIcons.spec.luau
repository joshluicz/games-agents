--!nocheck
-- Feel/NearIcons: a station's icon badge hides while the camera is right next to it (Real Clinic Studio test,
-- 2026-11-17: the Cast Table's badge filled half the screen in the X-ray room).

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local World = require("./worldmock")

local function loadPure(path: string): any
	local text = fs.readFile(World.find(path))
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to and to > from, path .. ": no PURE block")
	return luau.load(string.sub(text, from, to - 1) .. "\nreturn Pure\n", { debugName = path .. " (pure)" })()
end

local P = loadPure("src/client/Feel/NearIcons.luau")

T.describe("NearIcons.hidden", function()
	test("hides under HIDE studs and shows again only past SHOW (no flicker at the edge)", function()
		expect(P.HIDE < P.SHOW).toBe(true)
		expect(P.hidden(4.7, false)).toBe(true) -- the X-ray room's camera to the Cast Table's badge
		expect(P.hidden(P.HIDE + 0.5, false)).toBe(false)
		expect(P.hidden(P.HIDE + 0.5, true)).toBe(true) -- between the two: stays as it was
		expect(P.hidden(P.SHOW + 0.1, true)).toBe(false)
		expect(P.hidden(30, false)).toBe(false)
	end)
	test("a NaN distance leaves it as it was", function()
		expect(P.hidden(0 / 0, true)).toBe(true)
		expect(P.hidden(0 / 0, false)).toBe(false)
	end)
	test("the badge (2.6 studs) is never more than about a quarter of a 70° view when it shows", function()
		-- at 4.7 studs it was over a third; hiding sooner would lose the badges kids use to find a station
		local fraction = 2.6 / (2 * P.HIDE * math.tan(math.rad(35)))
		expect(fraction < 0.3).toBe(true)
	end)
end)
