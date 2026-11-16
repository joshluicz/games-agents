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

-- A live session: it holds its lock (Owned), so a last write can run its write.
local function live(written: number)
	local s = session(written)
	s.Owned = true
	s.Final = false
	return s
end

-- A successful data write of `s` at `changes` (what write() does with Pure.prepare's answer).
local function land(s, deps, snapshot, changes: number)
	local ok, masked, held, stored = P.prepare(deps, snapshot, changes, 0)
	assert(ok)
	s.Written = math.max(s.Written, held)
	s.Stored = stored
	return masked
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

	test("toLand: what a last write lands first (a live seller whose write hasn't landed)", function()
		local late, landed, lost, gaveUp = live(4), live(9), live(4), live(4)
		lost.Owned = false -- lost its lock, or its leave-save went through
		gaveUp.CanSave = false
		local deps = {
			{ Session = late, Player = "S1", Changes = 5, From = 2, Until = 0, LeaveOut = leaveOut("A", 1) },
			{ Session = landed, Player = "S2", Changes = 5, From = 3, Until = 0, LeaveOut = leaveOut("B", 1) },
			{ Session = lost, Player = "S3", Changes = 5, From = 4, Until = 0, LeaveOut = leaveOut("C", 1) },
			{ Session = gaveUp, Player = "S4", Changes = 5, From = 5, Until = 0, LeaveOut = leaveOut("D", 1) },
			{ Session = live(0), Player = "S5", Changes = 5, From = 6, Until = 99 }, -- only waited for: never run
		}
		local list = P.toLand(deps)
		expect(#list).toBe(1)
		expect(list[1].Player).toBe("S1")
		expect(#deps).toBe(5) -- it only looks
		-- its own leave-save under way (Final) is still listed: the last write waits for that one
		late.Final = true
		expect(#P.toLand(deps)).toBe(1)
		-- once the seller's write landed there is nothing to land, and the sale is written in full
		late.Written = 5
		expect(#P.toLand(deps)).toBe(0)
		expect(#P.toLand({})).toBe(0)
	end)

	test("the buyer's LAST write after the seller was landed holds the sale; if that failed it is left out", function()
		-- B bought PuffPup from S; S's saveNow failed once (Written 4 < the take at 5); B leaves.
		local seller = live(4)
		local deps = {
			{ Session = seller, Player = "S", Changes = 5, From = 9, Until = 0, LeaveOut = leaveOut("PuffPup", 300) },
		}
		expect(P.waiting(deps, 0)).toBe(false) -- nothing in flight: the old rule wrote at once, with the sale left out
		expect(#P.toLand(deps)).toBe(1) -- the new rule: run S's write first
		seller.Written = 6 -- S's write landed (run from B's leave-save)
		local snapshot = buyerSave()
		local _, masked = P.prepare(deps, snapshot, 12, 0)
		expect(masked).toBe(false)
		expect(snapshot.Nurses.PuffPup ~= nil).toBe(true) -- the nurse is in the buyer's last save
		expect(snapshot.Cash).toBe(700)

		-- S's write failed every time: the sale is left out (S's stored save still has the nurse).
		local down = live(4)
		local deps2 =
			{ { Session = down, Player = "S", Changes = 5, From = 9, Until = 0, LeaveOut = leaveOut("PuffPup", 300) } }
		local snapshot2 = buyerSave()
		local _, masked2 = P.prepare(deps2, snapshot2, 12, 0)
		expect(masked2).toBe(true)
		expect(snapshot2.Nurses.PuffPup).toBeNil()
		expect(snapshot2.Cash).toBe(1000)
	end)

	test("per dependency: a seller with ANOTHER nurse left out still lands its own sale", function()
		-- T sold BeanBear to S (S's give = S change 5); T's write never lands. S sold PuffPup to B (S's take = change 7).
		local t = session(0, false, false)
		local s = live(0)
		local sDeps = {
			{ Session = t, Key = "BeanBear", Changes = 3, From = 5, Until = 0, LeaveOut = leaveOut("BeanBear", 100) },
		}
		local bDep =
			{ Session = s, Key = "PuffPup", Changes = 7, From = 2, Until = 0, LeaveOut = leaveOut("PuffPup", 300) }
		expect(P.landed(bDep)).toBe(false)
		local masked = land(s, sDeps, { Cash = 0, Nurses = { BeanBear = {} } }, 7)
		expect(masked).toBe(true)
		expect(s.Written).toBe(4) -- in full only up to the BeanBear sale...
		expect(s.Stored.Changes).toBe(7)
		expect(s.Stored.Left.BeanBear).toBe(4)
		expect(P.landed(bDep)).toBe(true) -- ...but the PuffPup take is in the store: B isn't left out all session
		local snapshot = buyerSave()
		local _, bMasked = P.prepare({ bDep }, snapshot, 3, 0)
		expect(bMasked).toBe(false)
		expect(snapshot.Nurses.PuffPup ~= nil).toBe(true)
		-- a write that doesn't reach the take hasn't landed it
		local early = live(0)
		land(early, sDeps, { Cash = 0, Nurses = { BeanBear = {} } }, 6)
		expect(P.landed({ Session = early, Key = "PuffPup", Changes = 7, From = 2, Until = 0 })).toBe(false)
	end)

	test("per dependency: the SAME nurse sold on waits; so does a sale without a key, or after one without", function()
		local t = session(0, false, false)
		local s = live(0)
		local sDeps = {
			{ Session = t, Key = "BeanBear", Changes = 3, From = 5, Until = 0, LeaveOut = leaveOut("BeanBear", 100) },
		}
		land(s, sDeps, { Cash = 0, Nurses = { BeanBear = {} } }, 9)
		-- S sold that BeanBear on at change 8: T's stored save still has it, so it may be in no other save
		expect(P.landed({ Session = s, Key = "BeanBear", Changes = 8, From = 1, Until = 0 })).toBe(false)
		-- a BeanBear S sold BEFORE it bought this one (change 4) did land
		expect(P.landed({ Session = s, Key = "BeanBear", Changes = 4, From = 1, Until = 0 })).toBe(true)
		-- no key on the later sale: as before, it waits for everything left out before it
		expect(P.landed({ Session = s, Changes = 8, From = 1, Until = 0 })).toBe(false)
		-- no key on the sale left out: every later sale waits, whatever its key
		local s2 = live(0)
		local plain = { { Session = t, Changes = 3, From = 5, Until = 0, LeaveOut = leaveOut("BeanBear", 100) } }
		land(s2, plain, { Cash = 0, Nurses = { BeanBear = {} } }, 9)
		expect(s2.Stored.Any).toBe(4)
		expect(P.landed({ Session = s2, Key = "PuffPup", Changes = 8, From = 1, Until = 0 })).toBe(false)
		expect(P.landed({ Session = s2, Key = "PuffPup", Changes = 4, From = 1, Until = 0 })).toBe(true)
		-- two sales of one key left out: the earliest counts
		local s3 = live(0)
		local two = {
			{ Session = t, Key = "X", Changes = 3, From = 8, Until = 0, LeaveOut = leaveOut("X", 1) },
			{ Session = t, Key = "X", Changes = 3, From = 5, Until = 0, LeaveOut = leaveOut("X", 1) },
		}
		land(s3, two, { Cash = 0, Nurses = { X = {} } }, 9)
		expect(s3.Stored.Left.X).toBe(4)
		-- junk sessions never count as landed
		expect(P.landed({ Session = nil, Key = "X", Changes = 1, From = 1, Until = 0 })).toBe(false)
		expect(P.landed({ Session = { Stored = "junk" }, Key = "X", Changes = 1, From = 1, Until = 0 })).toBe(false)
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
