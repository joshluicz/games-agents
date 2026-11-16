--!nocheck
-- The "coming up" chip's rules (Logic/NextEvent; look build plan §B9; memory-20261116-022: countdowns only for FREE
-- events, in minutes).

local T = require("./expect")
local expect, test = T.expect, T.test

local NextEvent = require("../src/shared/Logic/NextEvent")

local function ev(id: string, at: number, paid: boolean?)
	return { Id = id, Icon = "🌟", Name = id, At = at, Paid = paid }
end

T.describe("NextEvent.pick", function()
	test("the soonest event after now", function()
		local picked = NextEvent.pick(100, { ev("Night", 900), ev("Golden", 400), ev("Gift", 700) })
		expect(picked).toEqual({ Id = "Golden", Icon = "🌟", Name = "Golden", At = 400 })
	end)

	test("ties keep the list's order", function()
		expect(NextEvent.pick(0, { ev("A", 300), ev("B", 300), ev("C", 300) }).Id).toBe("A")
		expect(NextEvent.pick(0, { ev("B", 300), ev("A", 300) }).Id).toBe("B")
	end)

	test("NEVER a paid one, however soon (red line 3)", function()
		expect(NextEvent.pick(0, { ev("Sale", 10, true), ev("Golden", 600) }).Id).toBe("Golden")
		expect(NextEvent.pick(0, { ev("Sale", 10, true) })).toBeNil()
		expect(NextEvent.pick(0, { ev("Sale", 10, true), ev("Deal", 20, true) })).toBeNil()
		-- Paid = false and Paid = nil are both free
		expect(NextEvent.pick(0, { ev("Free", 10, false) }).Id).toBe("Free")
	end)

	test("nothing already started or in the past", function()
		expect(NextEvent.pick(500, { ev("Past", 100), ev("Now", 500) })).toBeNil()
		expect(NextEvent.pick(500, { ev("Past", 100), ev("Soon", 501) }).Id).toBe("Soon")
	end)

	test("maxAhead: 6 hours unless given; further off isn't 'coming up'", function()
		expect(NextEvent.MAX_AHEAD).toBe(6 * 3600)
		expect(NextEvent.pick(0, { ev("Far", 6 * 3600 + 1) })).toBeNil()
		expect(NextEvent.pick(0, { ev("Edge", 6 * 3600) }).Id).toBe("Edge")
		expect(NextEvent.pick(0, { ev("Far", 6 * 3600 + 1) }, 24 * 3600).Id).toBe("Far")
		expect(NextEvent.pick(0, { ev("Soon", 120), ev("Sooner", 61) }, 60)).toBeNil()
		-- a junk maxAhead falls back to 6 h
		expect(NextEvent.pick(0, { ev("Soon", 120) }, -5).Id).toBe("Soon")
		expect(NextEvent.pick(0, { ev("Soon", 120) }, 0 / 0).Id).toBe("Soon")
	end)

	test("junk never errors and is never picked", function()
		expect(NextEvent.pick(0, {})).toBeNil()
		expect(NextEvent.pick(0, nil :: any)).toBeNil()
		expect(NextEvent.pick(0 / 0, { ev("A", 10) })).toBeNil()
		local junk = { "text", 5, ev("NaN", 0 / 0), ev("Inf", math.huge), { Id = "NoAt" }, ev("Ok", 60) } :: { any }
		expect(NextEvent.pick(0, junk).Id).toBe("Ok")
	end)

	test("returns a fresh view without the Paid flag (it never leaks to the UI)", function()
		local source = ev("Golden", 600, false)
		local picked = NextEvent.pick(0, { source })
		expect(picked ~= source).toBe(true)
		expect(picked.Paid).toBeNil()
	end)
end)

T.describe("NextEvent.label", function()
	test("minutes only, never seconds", function()
		expect(NextEvent.label(12 * 60)).toBe("in 12m")
		expect(NextEvent.label(12 * 60 + 59)).toBe("in 12m")
		expect(NextEvent.label(59 * 60 + 59)).toBe("in 59m")
		for _, seconds in { 0, 1, 45, 90, 600, 3599, 3600, 7325, 21600 } do
			expect(string.find(NextEvent.label(seconds), "%ds") == nil).toBe(true)
			expect(string.find(NextEvent.label(seconds), ":") == nil).toBe(true)
		end
	end)

	test("'in 1m' for anything under 2 minutes", function()
		for _, seconds in { 0, 1, 30, 59, 60, 119 } do
			expect(NextEvent.label(seconds)).toBe("in 1m")
		end
		expect(NextEvent.label(120)).toBe("in 2m")
	end)

	test("hours and minutes past an hour", function()
		expect(NextEvent.label(3600)).toBe("in 1h")
		expect(NextEvent.label(3600 + 5 * 60)).toBe("in 1h 5m")
		expect(NextEvent.label(2 * 3600)).toBe("in 2h")
		expect(NextEvent.label(5 * 3600 + 59 * 60 + 59)).toBe("in 5h 59m")
	end)

	test("junk reads as 'in 1m'", function()
		expect(NextEvent.label(-30)).toBe("in 1m")
		expect(NextEvent.label(0 / 0)).toBe("in 1m")
		expect(NextEvent.label(nil :: any)).toBe("in 1m")
	end)

	test("at most 3 words", function()
		for _, seconds in { 30, 720, 3600, 3900, 20000 } do
			local words = 0
			for _ in string.gmatch(NextEvent.label(seconds), "%S+") do
				words += 1
			end
			expect(words <= 3).toBe(true)
		end
	end)
end)
