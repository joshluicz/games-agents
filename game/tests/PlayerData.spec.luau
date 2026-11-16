--!nocheck
-- PlayerData.writeAfter's rules (Progression v2 review fix): the PURE block of src/server/PlayerData.luau, loaded on
-- its own (the rest needs DataStores). A buyer's stored save may hold a Market sale only once the seller's write has
-- landed: until then every buyer write leaves it out, whatever the order of writes, a second sale, a seller whose
-- save never lands, or two players trading both ways. Run from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local function source(path: string): string
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("can't find " .. path .. " (run from game/)")
end

local function pureBlock(path: string): any
	local text = source(path)
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to, path .. ": no PURE block")
	local block = string.sub(text, from, to - 1) .. "\nreturn Pure\n"
	return luau.load(block, { debugName = path .. ":Pure", environment = {}, injectGlobals = true })()
end

local P = pureBlock("src/server/PlayerData.luau")

-- A session as write() keeps it (only what the rules read).
local function session(written: number, saving: boolean?, canSave: boolean?)
	return { Written = written, Saving = saving == true, CanSave = canSave ~= false }
end

-- The Market's leaveOut (Server/Market Pure.leaveOut): the nurse out, the price back.
local function leaveOut(nurseId: string, price: number)
	return function(snapshot)
		snapshot.Nurses[nurseId] = nil
		snapshot.Cash += price
	end
end

local function buyerSave()
	return { Cash = 700, Nurses = { PuffPup = { Level = 3 }, MintMouse = { Level = 1 } } }
end

T.describe("PlayerData.Pure: writeAfter (a sale is in the buyer's save only once the seller's write landed)", function()
	test(
		"a sale whose seller hasn't landed is left out of the buyer's snapshot; the live save is never touched",
		function()
			local seller = session(4)
			local deps = { { Session = seller, Changes = 5, From = 9, Until = 0, LeaveOut = leaveOut("PuffPup", 300) } }
			local snapshot = buyerSave()
			local ok, masked, held = P.prepare(deps, snapshot, 12, 100)
			expect(ok).toBe(true)
			expect(masked).toBe(true)
			expect(held).toBe(8) -- everything before the sale's give (change 9) is held in full
			expect(snapshot.Nurses.PuffPup).toBeNil()
			expect(snapshot.Nurses.MintMouse ~= nil).toBe(true)
			expect(snapshot.Cash).toBe(1000)
			expect(#deps).toBe(1) -- kept: the next write leaves it out again
		end
	)

	test("once the seller's write landed, the sale is written and the dependency goes", function()
		local seller = session(4)
		local deps = { { Session = seller, Changes = 5, From = 9, Until = 0, LeaveOut = leaveOut("PuffPup", 300) } }
		seller.Written = 5
		local snapshot = buyerSave()
		local ok, masked, held = P.prepare(deps, snapshot, 12, 100)
		expect(ok and not masked).toBe(true)
		expect(held).toBe(12)
		expect(snapshot.Nurses.PuffPup ~= nil).toBe(true)
		expect(snapshot.Cash).toBe(700)
		expect(#deps).toBe(0)
	end)

	test("a seller whose write never lands (leave-save gave up, lock lost): left out for good, never lapses", function()
		local gaveUp = session(4, false, false) -- CanSave false: it will never write again
		local deps = { { Session = gaveUp, Changes = 5, From = 9, Until = 10, LeaveOut = leaveOut("PuffPup", 300) } }
		for _, now in { 5, 50, 5000 } do
			local snapshot = buyerSave()
			local _, masked = P.prepare(deps, snapshot, 12, now)
			expect(masked).toBe(true)
			expect(snapshot.Nurses.PuffPup).toBeNil()
		end
		expect(#deps).toBe(1)
		expect(P.waiting(deps, 5)).toBe(false) -- nothing in flight: no need to wait for it
	end)

	test("two sales from two sellers: each is left out until its own seller lands (never overwritten)", function()
		local a1, a2 = session(0), session(0)
		local deps = {
			{ Session = a1, Changes = 3, From = 5, Until = 0, LeaveOut = leaveOut("PuffPup", 300) },
			{ Session = a2, Changes = 7, From = 6, Until = 0, LeaveOut = leaveOut("MintMouse", 100) },
		}
		a2.Written = 7
		local snapshot = buyerSave()
		local _, masked, held = P.prepare(deps, snapshot, 9, 0)
		expect(masked).toBe(true)
		expect(held).toBe(4)
		expect(snapshot.Nurses.PuffPup).toBeNil()
		expect(snapshot.Nurses.MintMouse ~= nil).toBe(true)
		expect(snapshot.Cash).toBe(1000)
		expect(#deps).toBe(1)
		expect(deps[1].Session).toBe(a1)
	end)

	test("waiting: only for a seller with a write in flight; a dependency without LeaveOut until its bound", function()
		local inFlight, idle = session(0, true), session(0, false)
		expect(P.waiting({ { Session = inFlight, Changes = 1, From = 1, Until = 0, LeaveOut = leaveOut("X", 1) } }, 0)).toBe(
			true
		)
		expect(P.waiting({ { Session = idle, Changes = 1, From = 1, Until = 0, LeaveOut = leaveOut("X", 1) } }, 0)).toBe(
			false
		)
		local plain = { { Session = idle, Changes = 1, From = 1, Until = 10 } }
		expect(P.waiting(plain, 5)).toBe(true)
		expect(P.waiting(plain, 10)).toBe(false)
		-- a plain one that lapsed is dropped, and never changes the snapshot
		local snapshot = buyerSave()
		local _, masked = P.prepare(plain, snapshot, 3, 10)
		expect(masked).toBe(false)
		expect(#plain).toBe(0)
		-- landed: never waited for
		inFlight.Written = 1
		expect(P.waiting({ { Session = inFlight, Changes = 1, From = 1, Until = 99, LeaveOut = leaveOut("X", 1) } }, 0)).toBe(
			false
		)
	end)

	test("two players trading both ways never deadlock, and each sale lands in the end", function()
		-- A sold X to B (A's take = A change 3, B's give = B change 5), then B sold Y to A (B's take = B change 6,
		-- A's give = A change 4).
		local a, b = session(0), session(0)
		local bDeps = { { Session = a, Changes = 3, From = 5, Until = 0, LeaveOut = leaveOut("X", 10) } }
		local aDeps = { { Session = b, Changes = 6, From = 4, Until = 0, LeaveOut = leaveOut("Y", 20) } }
		expect(P.waiting(aDeps, 0) or P.waiting(bDeps, 0)).toBe(false) -- nobody waits on anybody
		-- A writes first (Y left out): it holds everything before its give of Y, so its take of X has landed.
		local aSnap = { Cash = 0, Nurses = { Y = {} } }
		local _, _, aHeld = P.prepare(aDeps, aSnap, 4, 0)
		expect(aHeld).toBe(3)
		a.Written = aHeld
		-- B writes next: X is in (A landed it); B holds everything before its give of X... and past it now.
		local bSnap = { Cash = 0, Nurses = { X = {} } }
		local _, bMasked, bHeld = P.prepare(bDeps, bSnap, 6, 0)
		expect(bMasked).toBe(false)
		expect(bSnap.Nurses.X ~= nil).toBe(true)
		b.Written = bHeld
		-- A's next write: B's take of Y landed, so Y is in.
		local aSnap2 = { Cash = 0, Nurses = { Y = {} } }
		local _, aMasked2 = P.prepare(aDeps, aSnap2, 4, 0)
		expect(aMasked2).toBe(false)
		expect(aSnap2.Nurses.Y ~= nil).toBe(true)
	end)

	test("a leaveOut that errors: no data this write (never a half-masked save)", function()
		local deps = {
			{
				Session = session(0),
				Changes = 1,
				From = 1,
				Until = 0,
				LeaveOut = function()
					error("broken")
				end,
			},
		}
		local ok, masked = P.prepare(deps, buyerSave(), 2, 0)
		expect(ok).toBe(false)
		expect(masked).toBe(true)
	end)
end)
