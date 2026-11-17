--!nocheck
-- The tutorial's flow (look build plan §D T8, §B1, §B9; memory-20261117-002/-003). Everything here is loaded straight
-- from the shipped source (the PURE blocks), so a spec can't pass on a stale copy:
--   · Server/Tutorial's remote rules (Skip, Replay with its cooldown, the one-time gift, the funnel, the patients
--     watch's attribute rules);
--   · UI/Wayfinder.Pure (feet, the strip's ends and bends, the floor arrows: their spots, shape, yaw, places ON the
--     strip's polyline and the march, the near-hide, the fade);
--   · UI/Guide.Pure (the Real Clinic: who the doctor goes to next, and what for: Examine, Fetch, Treat);
--   · Logic/Tutorial.card for every (step, playing, carrying), and UI/Tutorial.Pure's words per device: the 7 cards of
--     the Real Clinic design §13 (≤ 4-word titles, ≤ 6-word subtitles, the Skip line the one binding exception), the
--     confirms, the nurse's lines and the finale's FREE "coming up" chip;
--   · UI/Celebrate's "Tutorial" kind;
--   · uirules on every T8 UI file, Sounds' Chirp, and the budgets the source can show (one Highlight, one loop).
-- Run from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local Logic = require("../src/shared/Logic/Tutorial")
local NextEvent = require("../src/shared/Logic/NextEvent")
local UiRules = require("./uirules")
local Config = require("./config")

local function source(path: string): string
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("can't find " .. path .. " (run from game/)")
end

-- The block between two markers, loaded on its own and returning `name`.
local function block(path: string, first: string, last: string, name: string, env: { [string]: any }?): any
	local text = source(path)
	local from = string.find(text, first, 1, true)
	local to = string.find(text, last, 1, true)
	assert(from and to and to > from, path .. ": no " .. first .. " block")
	local chunk = string.sub(text, from, to - 1) .. "\nreturn " .. name .. "\n"
	return luau.load(chunk, { debugName = path .. " (" .. name .. ")", environment = env or {} })()
end

local Server = block("src/server/Tutorial.luau", "-- PURE-BEGIN", "-- PURE-END", "Pure", { Logic = Logic })
local Way = block("src/client/UI/Wayfinder.luau", "-- PURE-BEGIN", "-- PURE-END", "Pure")
-- UI/Icons is a library with no requires (the chrome emoji dictionary): the card's block reads it from its
-- environment, as the module reads its own upvalue.
local Icons = require("../src/client/UI/Icons")
local Card = block("src/client/UI/Tutorial.luau", "-- PURE-BEGIN", "-- PURE-END", "Pure", { Icons = Icons })
local GuidePure = block("src/client/UI/Guide.luau", "-- PURE-BEGIN", "-- PURE-END", "Pure")
local Visit = require("../src/shared/Logic/Visit")
local Items = require("../src/shared/Data/Items")
local Cases = require("../src/shared/Data/Cases")
local Words = block("src/client/UI/Celebrate.luau", "-- BEGIN PURE", "-- END PURE", "Words")

local WELCOME, PATIENT, EXAMINE, TREAT, REST, MORE, SHOP, BOOK, DONE =
	Logic.WELCOME, Logic.PATIENT, Logic.EXAMINE, Logic.TREAT, Logic.REST, Logic.MORE, Logic.SHOP, Logic.BOOK, Logic.DONE
local COOLDOWN = Config.Tutorial.ReplayCooldown

local function words(text: string): number
	return Card.countWords(text)
end

------------------------------------------------------------------------------------------------------------------
-- The server's remote rules
------------------------------------------------------------------------------------------------------------------

T.describe("TutorialSkip (server rules)", function()
	test("only an active step can be skipped", function()
		for step = WELCOME, BOOK do
			local ok, message = Server.skip(step)
			expect(ok).toBe(true)
			expect(message).toBe("")
		end
		local ok, message = Server.skip(DONE)
		expect(ok).toBe(false)
		expect(message).toBe(Server.ALREADY_DONE)
	end)

	test("not loaded, or a junk step: refused", function()
		expect((Server.skip(nil))).toBe(false)
		for _, junk in { 0, 10, 2.5, -1, "3", {}, 0 / 0 } do
			expect((Server.skip(junk))).toBe(false)
		end
	end)
end)

T.describe("TutorialReplay (server rules)", function()
	test("only from DONE, with your own clinic", function()
		expect({ Server.replay(DONE, true, true, nil, 100, COOLDOWN) }).toEqual({ true, "" })
		expect({ Server.replay(DONE, false, true, nil, 100, COOLDOWN) }).toEqual({ false, Server.NO_CLINIC })
		for step = WELCOME, BOOK do
			expect({ Server.replay(step, true, true, nil, 100, COOLDOWN) }).toEqual({ false, Server.PLAYING })
		end
	end)

	test("not loaded, or not saving: refused first", function()
		expect({ Server.replay(nil, true, true, nil, 100, COOLDOWN) }).toEqual({ false, Server.LOADING })
		expect({ Server.replay(DONE, true, false, nil, 100, COOLDOWN) }).toEqual({ false, Server.NOT_SAVING })
	end)

	test("junk steps are never DONE", function()
		for _, junk in { 0, 10, 9.5, "9", {} } do
			expect((Server.replay(junk, true, true, nil, 100, COOLDOWN))).toBe(false)
		end
	end)

	test("the cooldown: Config.Tutorial.ReplayCooldown seconds between replays", function()
		expect(COOLDOWN).toBe(30)
		expect({ Server.replay(DONE, true, true, 100, 100 + COOLDOWN - 0.1, COOLDOWN) }).toEqual({
			false,
			Server.TOO_SOON,
		})
		expect({ Server.replay(DONE, true, true, 100, 100 + COOLDOWN, COOLDOWN) }).toEqual({ true, "" })
	end)

	test("every refusal is at most 6 words", function()
		for _, text in
			{
				Server.LOADING,
				Server.ALREADY_DONE,
				Server.NO_CLINIC,
				Server.PLAYING,
				Server.TOO_SOON,
				Server.NOT_SAVING,
				Server.SKIP_TOAST,
			}
		do
			expect(words(text) <= 6).toBeTruthy()
		end
	end)
end)

T.describe("The one-time gift (server rules)", function()
	test("due only on entering SHOP, never twice", function()
		expect({ Server.gift(SHOP, false) }).toEqual({ true, true })
		expect({ Server.gift(SHOP, true) }).toEqual({ false, true })
		for _, step in { WELCOME, PATIENT, EXAMINE, TREAT, REST, MORE, BOOK } do
			expect({ Server.gift(step, false) }).toEqual({ false, false })
		end
	end)

	test("a replay never gifts, and marks the gift given", function()
		expect({ Server.gift(SHOP, false, true) }).toEqual({ false, true })
		expect({ Server.gift(PATIENT, false, true) }).toEqual({ false, true })
	end)

	test("reaching DONE (a Skip, the admin's finish) marks the gift given", function()
		expect({ Server.gift(DONE, false) }).toEqual({ false, true })
	end)

	-- The save's TutorialGift through whole runs, the way Server/Tutorial.move uses Server.gift.
	local function run(path: { { number } }, gifted: boolean): (number, boolean)
		local gifts = 0
		for _, move in path do
			local due, after = Server.gift(move[1], gifted, move[2] == 1)
			if due then
				gifts += 1
			end
			gifted = after
		end
		return gifts, gifted
	end

	test("a first run gets one gift; Skip and then Replay through the shop gets none", function()
		local first = { { PATIENT }, { EXAMINE }, { TREAT }, { REST }, { MORE }, { SHOP }, { BOOK }, { DONE } }
		expect({ run(first, false) }).toEqual({ 1, true })
		local skipped = { { PATIENT }, { EXAMINE }, { DONE } }
		local gifts, gifted = run(skipped, false)
		expect(gifts).toBe(0)
		local replayed = { { PATIENT, 1 }, { EXAMINE }, { TREAT }, { REST }, { MORE }, { SHOP }, { BOOK }, { DONE } }
		expect((run(replayed, gifted))).toBe(0)
		-- Even a save that somehow lost the flag gets nothing on a replay.
		expect((run(replayed, false))).toBe(0)
	end)
end)

T.describe("The onboarding funnel (server rules)", function()
	test("each stage once, as the step moves onto it: the card it shows, then the Shop as stage 8", function()
		expect(Server.funnel(WELCOME, PATIENT)).toBe(1)
		expect(Server.funnel(PATIENT, EXAMINE)).toBe(2)
		expect(Server.funnel(EXAMINE, TREAT)).toBe(4)
		expect(Server.funnel(PATIENT, TREAT)).toBe(4) -- examined before the arrival's beat
		expect(Server.funnel(TREAT, REST)).toBe(6)
		expect(Server.funnel(REST, MORE)).toBe(7)
		expect(Server.funnel(TREAT, MORE)).toBe(7) -- paid out at once (Lv 1)
		expect(Server.funnel(MORE, SHOP)).toBe(8)
		expect(Server.funnel(SHOP, BOOK)).toBeNil() -- the same stage
		for stage = 1, 8 do
			expect(type(Logic.FUNNEL_NAMES[stage])).toBe("string")
		end
	end)

	test("never on a replay, a Skip or the end (a later step would mark skipped ones done)", function()
		expect(Server.funnel(DONE, PATIENT, true)).toBeNil()
		expect(Server.funnel(EXAMINE, TREAT, true)).toBeNil()
		for step = WELCOME, BOOK do
			expect(Server.funnel(step, DONE)).toBeNil()
		end
	end)
end)

T.describe("The patients watch (server rules: steps 2 and 3 never hang on a hook)", function()
	test("a patient sitting on its bay bed (a Bay, and past the walk there) is the arrival", function()
		expect(Server.seated("1", "AtBay")).toBe(true)
		expect(Server.seated("W1", "Planned")).toBe(true)
		expect(Server.seated("2", nil)).toBe(true) -- no State yet: the Bay says it
		expect(Server.seated("1", "ToBay")).toBe(false) -- still walking to it
		expect(Server.seated("1", "Waiting")).toBe(false)
		for _, junk in { "", nil, 1, false, {} } :: { any } do
			expect(Server.seated(junk, "AtBay")).toBe(false)
		end
	end)

	test("a patient with a case (its Case attribute, set only by the exam) is the exam done", function()
		expect(Server.examined("Cough")).toBe(true)
		for _, junk in { "", nil, 3, true } :: { any } do
			expect(Server.examined(junk)).toBe(false)
		end
	end)

	test("the hooks Patients and Cure call are all there (onMade kept for Stations, moving nothing)", function()
		local text = source("src/server/Tutorial.luau")
		for _, hook in { "onFrontArrived", "onExamined", "onMade", "onTreated", "onCured" } do
			expect(string.find(text, "function Tutorial." .. hook .. "(", 1, true) ~= nil).toBeTruthy()
		end
		-- the watch listens to the plot's patients only while in steps 2-3, and lets go on every other step
		expect(
			string.find(text, "if step == Logic.PATIENT or step == Logic.EXAMINE then\n\t\twatch(player)", 1, true)
				~= nil
		).toBeTruthy()
		expect(string.find(text, "unwatch(player)\n\tif step == Logic.WELCOME then", 1, true) ~= nil).toBeTruthy()
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- The doctor's next beat (UI/Guide.Pure): what the Guide points at and the cards follow
------------------------------------------------------------------------------------------------------------------

T.describe("Guide.Pure: who the doctor goes to next", function()
	local function row(id: number, bay: string, state: string?, since: number?, extra: any?): any
		local r = { Id = id, Bay = bay, State = state, Since = since }
		for k, v in extra or {} do
			r[k] = v
		end
		return r
	end

	test("only bay patients waiting for the doctor count (not walking, not mid-session, not leaving)", function()
		expect(GuidePure.needsDoctor(row(1, "1", "AtBay"))).toBe(true)
		expect(GuidePure.needsDoctor(row(1, "1", "Planned"))).toBe(true)
		for _, state in
			{
				"Arriving",
				"Waiting",
				"ToBay",
				"Examining",
				"Treating",
				"Done",
				"ToWard",
				"Recovering",
				"Leaving",
				"Sad",
			}
		do
			expect(GuidePure.needsDoctor(row(1, "1", state))).toBe(false)
		end
		expect(GuidePure.needsDoctor(row(1, "", "AtBay"))).toBe(false) -- not in a bay
		expect(GuidePure.needsDoctor(row(1, "2", nil))).toBe(true) -- no State yet: in a bay counts
		expect(GuidePure.needsDoctor(row(1, "2", "SomethingNew"))).toBe(true) -- a newer server never hides the guide
	end)

	test("the plan's missing steps from Plan and PlanDone", function()
		expect(GuidePure.missing("Ice,Bandage", "10")).toEqual({ "Bandage" })
		expect(GuidePure.missing("Ice,Bandage", "")).toEqual({ "Ice", "Bandage" })
		expect(GuidePure.missing("Ice,Bandage", "11")).toEqual({})
		expect(GuidePure.missing(nil, nil)).toEqual({})
		expect(GuidePure.split("Cast, PainRelief")).toEqual({ "Cast", "PainRelief" })
	end)

	test("the front patient (Visit.front: longest waiting) before its exam: Examine", function()
		local rows = {
			row(1, "2", "AtBay", 50),
			row(2, "1", "AtBay", 20),
			row(3, "3", "Examining", 5), -- someone is examining it: not the front
		}
		local id, todo, item = GuidePure.next(rows, {}, Visit.front)
		expect(id).toBe(2)
		expect(todo).toBe("Examine")
		expect(item).toBeNil()
	end)

	test("examined: Fetch its first missing step", function()
		local rows = { row(1, "1", "Planned", 10, { Case = "Sprain", Plan = "Ice,Bandage", PlanDone = "10" }) }
		local id, todo, item = GuidePure.next(rows, {}, Visit.front)
		expect(id).toBe(1)
		expect(todo).toBe("Fetch")
		expect(item).toBe("Bandage")
	end)

	test("carrying something a waiting patient needs: Treat that one first, even if it isn't the front", function()
		local rows = {
			row(1, "1", "AtBay", 10), -- the front: not examined yet
			row(2, "2", "Planned", 30, { Case = "CutKnee", Plan = "Plaster", PlanDone = "0" }),
		}
		local id, todo, item = GuidePure.next(rows, { "Plaster" }, Visit.front)
		expect(id).toBe(2)
		expect(todo).toBe("Treat")
		expect(item).toBe("Plaster")
		-- carrying something nobody needs: the front again
		id, todo = GuidePure.next(rows, { "Ice" }, Visit.front)
		expect(id).toBe(1)
		expect(todo).toBe("Examine")
	end)

	test("the server's QueueIndex orders them (1 = the front); 0 = it doesn't need the doctor now", function()
		local rows = {
			row(1, "1", "AtBay", nil, { Rank = 2 }),
			row(2, "2", "AtBay", nil, { Rank = 1 }),
			row(3, "3", "Planned", nil, { Rank = 0, Case = "Cough", Plan = "CoughSyrup", PlanDone = "0" }), -- a nurse
		}
		expect((GuidePure.next(rows, {}, Visit.front))).toBe(2)
		expect((GuidePure.next(rows, { "CoughSyrup" }, Visit.front))).toBe(2) -- not 3: it isn't waiting now
		expect(GuidePure.needsDoctor(rows[3])).toBe(false)
	end)

	test("no Since from the server: the bays' order decides", function()
		local rows = { row(1, "3", "AtBay"), row(2, "1", "AtBay"), row(3, "W1", "AtBay") }
		expect((GuidePure.next(rows, {}, Visit.front))).toBe(2)
		expect(GuidePure.bayOrder("1") < GuidePure.bayOrder("6")).toBeTruthy()
		expect(GuidePure.bayOrder("6") < GuidePure.bayOrder("W1")).toBeTruthy()
	end)

	test("nobody waiting for the doctor: nothing", function()
		expect((GuidePure.next({}, {}, Visit.front))).toBeNil()
		expect((GuidePure.next({ row(1, "1", "Treating", 3) }, { "Plaster" }, Visit.front))).toBeNil()
	end)

	test(
		"the Guide reads bays and stations from the Building and the Rooms, never QueueStart or the Counter",
		function()
			local text = source("src/client/UI/Guide.luau")
			expect(string.find(text, "QueueStart", 1, true)).toBeNil()
			expect(string.find(text, "FrontStation", 1, true)).toBeNil()
			expect(string.find(text, "data.Ailments", 1, true)).toBeNil()
			expect(string.find(text, 'for _, holder in { "Building", "Rooms" } do', 1, true) ~= nil).toBeTruthy()
			expect(string.find(text, '"ExamBay_" .. bayId', 1, true) ~= nil).toBeTruthy()
		end
	)
end)

------------------------------------------------------------------------------------------------------------------
-- The world guide's numbers (UI/Wayfinder.Pure)
------------------------------------------------------------------------------------------------------------------

T.describe("Wayfinder.Pure", function()
	test("feetY: R15 from HipHeight, R6 from its 2-stud legs", function()
		expect(Way.feetY(5, 2, 2)).toBe(2)
		expect(Way.feetY(5, 2, 1.35)).toBeCloseTo(2.65, 6)
		expect(Way.feetY(3, 2, 0, true)).toBe(0)
		expect(Way.feetY(3, 2, 7, true)).toBe(0) -- R6 ignores HipHeight
		expect(Way.feetY(5, 2, -1)).toBe(4) -- a junk HipHeight is no legs
	end)

	test("beamStart: the strip lies ON the floor, BeamLift over it, at your feet too (Joshua 2026-11-17)", function()
		local tune = Config.Tutorial
		expect(tune.BeamLift > 0 and tune.BeamLift <= 0.3).toBeTruthy()
		expect(Way.beamStart(10, tune.BeamLift)).toBeCloseTo(10 + tune.BeamLift, 6)
		expect(tune.BeamEndLift).toBeNil() -- one lift all the way: no hips at one end, floor at the other
		-- it reads as a path: a brighter middle inside darker edges, and the arrows fit (about) inside it
		expect(tune.BeamCoreWidth < tune.BeamWidth).toBeTruthy()
		expect(tune.ChevronWidth <= tune.BeamWidth).toBeTruthy()
		expect(tune.ChevronWidth > tune.BeamCoreWidth).toBeTruthy()
		-- the optional texture id: a string, "" until we have one
		expect(type(tune.BeamTexture)).toBe("string")
	end)

	test("endAnchor: the footprint's closest point, out by the margin", function()
		local box = { X0 = -2, X1 = 2, Z0 = -1, Z1 = 1 }
		local x, z = Way.endAnchor(box, 10, 0, 0.3)
		expect(x).toBeCloseTo(2.3, 6)
		expect(z).toBeCloseTo(0, 6)
		x, z = Way.endAnchor(box, 0, -9, 0.3)
		expect(x).toBeCloseTo(0, 6)
		expect(z).toBeCloseTo(-1.3, 6)
		-- a corner: out along the diagonal
		x, z = Way.endAnchor(box, 5, 4, 0.3)
		expect(x > 2 and z > 1).toBeTruthy()
		expect(math.sqrt((x - 2) ^ 2 + (z - 1) ^ 2)).toBeCloseTo(0.3, 6)
		-- standing on it: out by the nearest edge
		x, z = Way.endAnchor(box, 1.8, 0, 0.3)
		expect(x).toBeCloseTo(2.3, 6)
		expect(z).toBeCloseTo(0, 6)
	end)

	test("needsBend: only a line through the box, not one past or along it", function()
		local box = { X0 = -1, X1 = 1, Z0 = -1, Z1 = 1 }
		expect(Way.needsBend(-5, 0, 5, 0, box)).toBe(true)
		expect(Way.needsBend(-5, 3, 5, 3, box)).toBe(false)
		expect(Way.needsBend(-5, 0, -2, 0, box)).toBe(false) -- stops short
		expect(Way.needsBend(-5, 1, 5, 1, box)).toBe(false) -- along the edge
	end)

	test("detour: none when clear; else round the box's corners, out by the margin", function()
		local box = { X0 = -2, X1 = 2, Z0 = -1, Z1 = 1 }
		expect(#Way.detour(-6, 5, 6, 5, box, 2.5)).toBe(0)
		local knees = Way.detour(-6, 0.2, 6, 0.2, box, 2.5)
		expect(#knees >= 1 and #knees <= 2).toBeTruthy()
		-- every leg of the detour clears the box
		local points = { { X = -6, Z = 0.2 } }
		for _, knee in knees do
			table.insert(points, knee)
		end
		table.insert(points, { X = 6, Z = 0.2 })
		for i = 2, #points do
			local a, b = points[i - 1], points[i]
			expect(Way.needsBend(a.X, a.Z, b.X, b.Z, box)).toBe(false)
		end
		-- the knees sit at the margin
		for _, knee in knees do
			expect(math.abs(knee.X) == 4.5 or math.abs(knee.Z) == 3.5).toBeTruthy()
		end
	end)

	test("detour: never more spans than BeamMaxSpans", function()
		local box = { X0 = -2, X1 = 2, Z0 = -1, Z1 = 1 }
		for _, from in { { -6, 0 }, { 0, -6 }, { 6, 0 }, { 0, 6 }, { -3, 0.5 } } do
			for _, to in { { 6, 0 }, { 0, 6 }, { -6, 0 }, { 0, -6 } } do
				expect(#Way.detour(from[1], from[2], to[1], to[2], box, 2.5) + 1 <= Config.Tutorial.BeamMaxSpans).toBeTruthy()
			end
		end
	end)

	test("simplify: a straight path has no knees; a corner keeps one; at most maxKnees, nearest first", function()
		local straight = {}
		for i = 0, 10 do
			table.insert(straight, { X = i * 2, Z = 0, Y = 0 })
		end
		expect(#Way.simplify(straight, 1, 3)).toBe(0)
		local corner = {}
		for i = 0, 5 do
			table.insert(corner, { X = i * 2, Z = 0, Y = 0 })
		end
		for i = 1, 5 do
			table.insert(corner, { X = 10, Z = i * 2, Y = 0 })
		end
		local knees = Way.simplify(corner, 1, 3)
		expect(#knees).toBe(1)
		expect(corner[knees[1]].X).toBe(10)
		expect(corner[knees[1]].Z).toBe(0)
		local zigzag = {}
		for i = 0, 12 do
			table.insert(zigzag, { X = i * 3, Z = (i % 2) * 4, Y = 0 })
		end
		local capped = Way.simplify(zigzag, 1, 3)
		expect(#capped).toBe(3)
		expect(capped[1] < capped[2] and capped[2] < capped[3]).toBeTruthy()
		-- a step in the floor is a knee too
		local stepUp =
			{ { X = 0, Z = 0, Y = 0 }, { X = 4, Z = 0, Y = 0 }, { X = 8, Z = 0, Y = 1.2 }, { X = 12, Z = 0, Y = 1.2 } }
		expect(#Way.simplify(stepUp, 1, 3, 0.5)).toBe(1)
	end)

	test("routeLength and along", function()
		local route = { { X = 0, Z = 0 }, { X = 3, Z = 4 }, { X = 3, Z = 10 } }
		expect(Way.routeLength(route)).toBeCloseTo(11, 6)
		local x, z, dx, dz = Way.along(route, 2.5)
		expect(x).toBeCloseTo(1.5, 6)
		expect(z).toBeCloseTo(2, 6)
		expect(dx).toBeCloseTo(0.6, 6)
		expect(dz).toBeCloseTo(0.8, 6)
		x, z, dx, dz = Way.along(route, 8)
		expect(x).toBeCloseTo(3, 6)
		expect(z).toBeCloseTo(7, 6)
		expect(dz).toBeCloseTo(1, 6)
		x, z = Way.along(route, 99) -- past the end: the end
		expect(z).toBeCloseTo(10, 6)
	end)

	test("chevronSpots: every gap, never within near of the target or under your feet, at most max", function()
		local tune = Config.Tutorial
		local spots = Way.chevronSpots(30, tune.FirstChevron, tune.ChevronGap, tune.MaxChevrons, tune.NearStuds)
		expect(#spots <= tune.MaxChevrons).toBeTruthy()
		for i, d in spots do
			expect(d >= tune.FirstChevron).toBeTruthy()
			expect(30 - d >= tune.NearStuds).toBeTruthy()
			if i > 1 then
				expect(d - spots[i - 1]).toBeCloseTo(tune.ChevronGap, 6)
			end
		end
		expect(spots).toEqual({ 4, 9, 14, 19, 24 })
		-- a long route: only the max, the ones nearest you
		local long = Way.chevronSpots(100, tune.FirstChevron, tune.ChevronGap, tune.MaxChevrons, tune.NearStuds)
		expect(#long).toBe(tune.MaxChevrons)
		expect(long[1] < long[#long]).toBeTruthy()
		-- too short: none
		expect(#Way.chevronSpots(8, tune.FirstChevron, tune.ChevronGap, tune.MaxChevrons, tune.NearStuds)).toBe(0)
		expect(#Way.chevronSpots(30, 3, 0, 6, 6)).toBe(0)
	end)

	test("chevronSpots: they stay put on the floor as you walk toward the target", function()
		local tune = Config.Tutorial
		local before = Way.chevronSpots(40, tune.FirstChevron, tune.ChevronGap, tune.MaxChevrons, tune.NearStuds)
		local after = Way.chevronSpots(38, tune.FirstChevron, tune.ChevronGap, tune.MaxChevrons, tune.NearStuds)
		-- the same spots seen from 2 studs closer: each is 2 nearer you. Every arrow sits on one lattice measured from
		-- the target, so an arrow in both views hasn't moved; at most one is new (the next one toward the target, as
		-- the one you walked past drops under FirstChevron)
		for _, list in { { 40, before }, { 38, after } } do
			for _, d in list[2] do
				local k = ((list[1] - d) - tune.NearStuds) / tune.ChevronGap
				expect(math.abs(k - math.floor(k + 0.5)) < 1e-6).toBeTruthy()
			end
		end
		local same = 0
		for _, d in after do
			for _, e in before do
				if math.abs((e - 2) - d) < 1e-6 then
					same += 1
				end
			end
		end
		expect(same >= #after - 1 and same >= 1).toBeTruthy()
	end)

	test("along: the height ON the line when its points carry one", function()
		local line = { { X = 0, Y = 1, Z = 0 }, { X = 10, Y = 3, Z = 0 } }
		local x, _, dx, _, y = Way.along(line, 5)
		expect(x).toBeCloseTo(5, 6)
		expect(dx).toBeCloseTo(1, 6)
		expect(y).toBeCloseTo(2, 6)
		local _, _, _, _, none = Way.along({ { X = 0, Z = 0 }, { X = 1, Z = 0 } }, 0.5)
		expect(none).toBeNil()
	end)

	test("yaw: faces along the flat direction the way CFrame.lookAt does", function()
		expect(Way.yaw(0, -1)).toBeCloseTo(0, 6)
		expect(Way.yaw(1, 0)).toBeCloseTo(-math.pi / 2, 6)
		expect(Way.yaw(-1, 0)).toBeCloseTo(math.pi / 2, 6)
		expect(math.abs(Way.yaw(0, 1))).toBeCloseTo(math.pi, 6)
		-- CFrame.Angles(0, yaw, 0).LookVector = (-sin yaw, 0, -cos yaw) is the direction again
		for _, angle in { 0.3, 1.2, 2.5, -0.7, -2.9 } do
			local dx, dz = math.cos(angle), math.sin(angle)
			local yaw = Way.yaw(dx, dz)
			expect(-math.sin(yaw)).toBeCloseTo(dx, 6)
			expect(-math.cos(yaw)).toBeCloseTo(dz, 6)
		end
	end)

	test("arrowShape: a chunky 2.5-3 stud arrow, its head two mirrored halves, outlined all round", function()
		local tune = Config.Tutorial
		local L, W, e = tune.ChevronStuds, tune.ChevronWidth, 0.18
		expect(L >= 2.5 and L <= 3).toBeTruthy() -- readable from the default camera
		local pieces = Way.arrowShape(L, W, e)
		expect(#pieces).toBe(6)
		expect(#pieces * tune.MaxChevrons <= 36).toBeTruthy() -- a few dozen parts at most, every arrow together
		expect(pieces[1].Layer).toBe("Edge") -- the outline first: it lies underneath
		local by = {}
		for _, piece in pieces do
			by[piece.Layer .. piece.Kind] = piece
		end
		local shaft, left, right = by.TopBlock, by.TopLeft, by.TopRight
		-- the tip at +L/2 on the centre line, the tail at -L/2
		expect(left.Forward + left.Length / 2).toBeCloseTo(L / 2, 6)
		expect(shaft.Forward - shaft.Length / 2).toBeCloseTo(-L / 2, 6)
		expect(shaft.Side).toBe(0)
		-- the halves meet on the centre line, span the head's width and mirror each other
		expect(left.Side + left.Width / 2).toBeCloseTo(0, 6)
		expect(left.Side - left.Width / 2).toBeCloseTo(-W / 2, 6)
		expect(right.Side).toBeCloseTo(-left.Side, 6)
		expect(right.Forward).toBeCloseTo(left.Forward, 6)
		expect(right.Length).toBeCloseTo(left.Length, 6)
		-- a chunky head: half the length, and the shaft narrower than it, running into it (no seam)
		local base = left.Forward - left.Length / 2
		expect(left.Length).toBeCloseTo(L * Way.HEAD_SHARE, 6)
		expect(shaft.Width < W).toBeTruthy()
		expect(shaft.Forward + shaft.Length / 2 > base).toBeTruthy()
		-- the outline: `e` bigger all round
		local edgeShaft, edgeLeft, edgeRight = by.EdgeBlock, by.EdgeLeft, by.EdgeRight
		expect(edgeLeft.Forward - edgeLeft.Length / 2).toBeCloseTo(base - e, 6) -- behind the head
		expect(edgeShaft.Forward - edgeShaft.Length / 2).toBeCloseTo(-L / 2 - e, 6) -- behind the tail
		expect(edgeShaft.Width).toBeCloseTo(shaft.Width + 2 * e, 6) -- beside the shaft
		expect(edgeRight.Side).toBeCloseTo(-edgeLeft.Side, 6)
		-- each slanted side exactly `e` outside the white one: the white tip and corner are both `e` off its line
		local tipF = edgeLeft.Forward + edgeLeft.Length / 2
		local cornerF, cornerS = edgeLeft.Forward - edgeLeft.Length / 2, edgeLeft.Side - edgeLeft.Width / 2
		local function offEdge(f: number, s: number): number
			local df, ds = cornerF - tipF, cornerS
			return math.abs(df * s - ds * (f - tipF)) / math.sqrt(df * df + ds * ds)
		end
		expect(offEdge(L / 2, 0)).toBeCloseTo(e, 6)
		expect(offEdge(base, -W / 2)).toBeCloseTo(e, 6)
		expect(tipF > L / 2 + e).toBeTruthy()
		-- junk sizes: nothing
		expect(#Way.arrowShape(0, W, e)).toBe(0)
		expect(#Way.arrowShape(L, 0, e)).toBe(0)
	end)

	test("arrowPlaces: every arrow's centre lies ON the strip's polyline and faces along its segment", function()
		local tune = Config.Tutorial
		local lift = tune.BeamLift
		-- the strip's own polyline: your feet, two knees (the floor steps up 1 on the second leg), the target's base
		local line = {
			{ X = 0, Y = lift, Z = 0 },
			{ X = 0, Y = lift, Z = -12.5 },
			{ X = 8, Y = 1 + lift, Z = -12.5 },
			{ X = 8, Y = 1 + lift, Z = -30 },
		}
		local length = Way.routeLength(line)
		expect(length).toBeCloseTo(38, 6)
		local spots = Way.chevronSpots(length, tune.FirstChevron, tune.ChevronGap, tune.MaxChevrons, tune.NearStuds)
		expect(#spots).toBe(tune.MaxChevrons)
		-- the segment `d` studs along lies on (a knee counts with the segment before it, as `along` does)
		local function segmentAt(d: number): number
			local walked = 0
			for i = 2, #line do
				local a, b = line[i - 1], line[i]
				walked += math.sqrt((b.X - a.X) ^ 2 + (b.Z - a.Z) ^ 2)
				if d <= walked + 1e-9 then
					return i
				end
			end
			return #line
		end
		-- the flat distance from (x, z) to the polyline
		local function offLine(x: number, z: number): number
			local best = math.huge
			for i = 2, #line do
				local a, b = line[i - 1], line[i]
				local dx, dz = b.X - a.X, b.Z - a.Z
				local t = math.clamp(((x - a.X) * dx + (z - a.Z) * dz) / (dx * dx + dz * dz), 0, 1)
				best = math.min(best, math.sqrt((x - a.X - dx * t) ^ 2 + (z - a.Z - dz * t) ^ 2))
			end
			return best
		end
		local hops = {}
		for i in spots do
			hops[i] = tune.ChevronHop -- every arrow mid-hop: still on the line, round the knee too
		end
		for _, shift in { false, hops } do
			local places = Way.arrowPlaces(line, spots, if shift then shift else nil)
			expect(#places).toBe(#spots)
			for i, place in places do
				local d = spots[i] + (if shift then shift[i] else 0)
				expect(offLine(place.X, place.Z) < 0.2).toBeTruthy()
				local seg = segmentAt(d)
				local a, b = line[seg - 1], line[seg]
				local dx, dz = b.X - a.X, b.Z - a.Z
				local n = math.sqrt(dx * dx + dz * dz)
				expect(place.Yaw).toBeCloseTo(Way.yaw(dx / n, dz / n), 6)
				-- at the line's own height there, and its distance to the target kept (the pulse's phase)
				expect(place.Y >= math.min(a.Y, b.Y) - 1e-9 and place.Y <= math.max(a.Y, b.Y) + 1e-9).toBeTruthy()
				expect(place.ToTarget).toBeCloseTo(length - spots[i], 6)
			end
		end
		-- a hop never carries an arrow past the end
		local last = Way.arrowPlaces(line, { length - 0.1 }, { 5 })[1]
		expect(last.X).toBeCloseTo(8, 6)
		expect(last.Z).toBeCloseTo(-30, 6)
	end)

	test("pulse: the march runs along the row toward the target, a gentle hop that rests most of the cycle", function()
		local tune = Config.Tutorial
		local P, W = tune.ChevronPulse, tune.ChevronWave
		expect(tune.ChevronHop > 0 and tune.ChevronHop <= 1).toBeTruthy() -- a little hop, not a run
		local resting = 0
		for i = 0, 99 do
			local v = Way.pulse(i * P / 100, 10, P, W)
			expect(v >= 0 and v <= 1).toBeTruthy()
			if v == 0 then
				resting += 1
			end
		end
		expect(resting >= 50).toBeTruthy()
		-- the arrow `d` from the target peaks at t; dt later the peak is nearer the target by dt x W / P
		local t = 3
		local d = ((Way.HOP_SHARE / 2 - t / P) % 1) * W
		expect(Way.pulse(t, d, P, W)).toBeCloseTo(1, 6)
		local dt = 0.1
		expect(Way.pulse(t + dt, d - dt * W / P, P, W)).toBeCloseTo(1, 6)
		-- so an arrow farther from the target (nearer you) hops first
		local function firstPeak(toTarget: number): number
			for step = 0, 2000 do
				local at = step * P / 2000
				if Way.pulse(at, toTarget, P, W) > 0.999 then
					return at
				end
			end
			return math.huge
		end
		expect(firstPeak(14) < firstPeak(9)).toBeTruthy()
		-- no march without a period or a wave
		expect(Way.pulse(1, 5, 0, W)).toBe(0)
		expect(Way.pulse(1, 5, P, 0)).toBe(0)
	end)

	test("near: the beam and the chevrons hide within NearStuds", function()
		expect(Config.Tutorial.NearStuds).toBe(6)
		expect(Way.near(5.9, 6)).toBe(true)
		expect(Way.near(6, 6)).toBe(true)
		expect(Way.near(6.1, 6)).toBe(false)
	end)

	test("fade: in at your body, out into the glow, flat between", function()
		expect(Way.fade(1, 1)).toEqual({ { 0, 1 }, { 0.1, 0.15 }, { 0.9, 0.15 }, { 1, 0.45 } })
		expect(Way.fade(1, 3)).toEqual({ { 0, 1 }, { 0.1, 0.15 }, { 1, 0.15 } })
		expect(Way.fade(2, 3)).toEqual({ { 0, 0.15 }, { 1, 0.15 } })
		expect(Way.fade(3, 3)).toEqual({ { 0, 0.15 }, { 0.9, 0.15 }, { 1, 0.45 } })
		for count = 1, 4 do
			for index = 1, count do
				local keys = Way.fade(index, count)
				expect(keys[1][1]).toBe(0)
				expect(keys[#keys][1]).toBe(1)
			end
		end
	end)

	test("pinOffset: the pin drops lower when the camera is close", function()
		expect(Way.pinOffset(5, 10)).toBe(1.2)
		expect(Way.pinOffset(30, 10)).toBe(3)
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- The cards
------------------------------------------------------------------------------------------------------------------

T.describe("The cards (Logic/Tutorial.card)", function()
	test("every (step, playing, carrying)", function()
		-- { nothing up, the step's own game up, carrying what it needs }
		local want = {
			[WELCOME] = { 1, 1, 1 },
			[PATIENT] = { 1, 1, 1 },
			[EXAMINE] = { 2, 3, 2 },
			[TREAT] = { 4, 5, 5 },
			[REST] = { 6, 6, 6 },
			[MORE] = { 7, 7, 7 },
			[SHOP] = { 7, 7, 7 },
			[BOOK] = { 7, 7, 7 },
		}
		for step = WELCOME, BOOK do
			expect(Logic.card(step, nil, false)).toBe(want[step][1])
			expect(Logic.card(step, true)).toBe(want[step][2])
			expect(Logic.card(step, nil, true)).toBe(want[step][3])
			expect(Logic.card(step)).toBe(want[step][1])
		end
		-- the session's Kind: an exam is card 3, a supply's game card 5, a dispensing card still card 4
		expect(Logic.card(EXAMINE, "Exam")).toBe(3)
		expect(Logic.card(TREAT, "Treat")).toBe(5)
		expect(Logic.card(TREAT, "Dispense")).toBe(4)
		expect(Logic.card(TREAT, "Dispense", true)).toBe(5)
		expect(Logic.card(DONE, true)).toBeNil()
		expect(Logic.card(0)).toBeNil()
		expect(Card.CARDS).toBe(Logic.CARDS)
		expect(Card.PIPS_CARD).toBe(7)
	end)

	test("the tab and the pips (card 7: treat 3 more)", function()
		expect(Card.tab(2, 7)).toBe("TUTORIAL 2/7")
		expect(Card.pips(0, 3)).toBe("○○○")
		expect(Card.pips(1, 3)).toBe("●○○")
		expect(Card.pips(3, 3)).toBe("●●●")
		expect(Card.pips(5, 3)).toBe("●●●")
	end)

	test("the bar fills on success and never by time (card 7 by its pips)", function()
		expect(Card.segments(1, false)).toEqual({ 0, 0, 0, 0, 0, 0, 0 })
		expect(Card.segments(1, true)).toEqual({ 1, 0, 0, 0, 0, 0, 0 })
		expect(Card.segments(4, false)).toEqual({ 1, 1, 1, 0, 0, 0, 0 })
		local third = Card.segments(7, false, 1, 3)
		expect(third[6]).toBe(1)
		expect(third[7]).toBeCloseTo(1 / 3, 6)
		expect(Card.segments(6, false, 1, 3)).toEqual({ 1, 1, 1, 1, 1, 0, 0 }) -- only card 7 has pips
		expect(Card.segments(7, true)).toEqual({ 1, 1, 1, 1, 1, 1, 1 })
	end)

	test("the device from PreferredInput (or the enabled inputs)", function()
		expect(Card.device("Touch")).toBe("Touch")
		expect(Card.device("Gamepad")).toBe("Pad")
		expect(Card.device("MicroGamepad")).toBe("Pad")
		expect(Card.device("KeyboardAndMouse")).toBe("Keyboard")
		expect(Card.device(nil, true, false, false)).toBe("Touch")
		expect(Card.device(nil, false, false, true)).toBe("Pad")
		expect(Card.device(nil, true, true, true)).toBe("Keyboard")
	end)

	-- Every situation a card can meet, per device: every plan item (Data/Items), every place, every bay, every game.
	local GAME_IDS = {
		"Listen",
		"Temp",
		"Light",
		"Look",
		"XRay",
		"Plaster",
		"Ice",
		"Bandage",
		"Cast",
		"Bath",
		"Cocoa",
		"Pick",
		"Dose",
		"Tap",
	}
	local function situations(): { any }
		local out = {}
		for _, deviceName in { "Keyboard", "Touch", "Pad" } do
			for _, atBay in { false, true } do
				for _, examined in { false, true } do
					for _, carrying in { false, true } do
						for _, itemId in Items.Order do
							for _, where in { "Shelf", "Dispensary", "Room" } do
								for _, bay in { "1", "6", "W2", "X" } do
									table.insert(out, {
										Device = deviceName,
										Bay = bay,
										AtBay = atBay,
										Examined = examined,
										Item = Items[itemId].Name,
										Need = Items[itemId].Icon,
										Where = where,
										Carrying = carrying,
										Glow = carrying, -- both ways
										Cures = if carrying then 2 else 0,
										Total = Logic.MORE_CURES,
										Shop = examined and atBay,
										-- Nobody in a bay and one waiting to be sent (simple-start design §2).
										Waiting = not atBay and bay == "1",
									})
								end
							end
						end
					end
				end
			end
		end
		for _, deviceName in { "Keyboard", "Touch", "Pad" } do
			for _, gameId in GAME_IDS do
				table.insert(out, { Device = deviceName, Game = gameId, Total = Logic.MORE_CURES })
			end
		end
		return out
	end

	test("every game on the slim strip has words", function()
		for _, gameId in GAME_IDS do
			expect(Card.GAMES[gameId] ~= nil).toBeTruthy()
		end
	end)

	test("the card words: a title of 4 words or fewer, a subtitle (with its key) of 6 or fewer", function()
		for _, s in situations() do
			for cardNumber = 1, Logic.CARDS do
				local w = Card.words(cardNumber, s)
				expect(w.Title ~= "").toBeTruthy()
				expect(w.Sub ~= "").toBeTruthy()
				local titleWords = words(w.Title)
				local subWords = words(w.Sub) + (if w.Key then 1 else 0)
				if titleWords > 4 or subWords > 6 then
					error(string.format("card %d (%s): %q / %q", cardNumber, s.Device or "?", w.Title, w.Sub))
				end
			end
		end
	end)

	test(
		"the card titles match the design's §13 (welcome, examine, the glowing tool, the plan, Treat, done, 3 more)",
		function()
			local function w(cardNumber, deviceName, extra)
				local s = { Device = deviceName, Bay = "1", Total = 3, Cures = 0 }
				for k, v in extra or {} do
					s[k] = v
				end
				return Card.words(cardNumber, s)
			end
			-- (1) welcome, Doctor
			expect(w(1, "Keyboard").Title).toBe("WELCOME, DOCTOR!")
			expect(w(1, "Keyboard").Sub).toBe("A patient is coming!")
			expect(w(1, "Keyboard", { AtBay = true }).Sub).toBe("A patient in bay 1!")
			-- (1, still) simple start §2: the first patient sits in the waiting room until you send it. The same card
			-- and the same saved step (no new step number): only the words change
			expect(w(1, "Keyboard", { Waiting = true })).toEqual({
				Title = "YOUR PATIENT IS WAITING",
				Sub = "Walk over · Send",
				Key = "Prompt",
			})
			expect(w(1, "Touch", { Waiting = true }).Sub).toBe("Walk over · tap Send")
			expect(w(1, "Pad", { Waiting = true }).Key).toBe("Prompt")
			expect(w(1, "Keyboard", { Waiting = true, AtBay = true }).Sub).toBe("A patient in bay 1!") -- sent
			-- (2) a patient is in bay 1, tap Examine
			expect(w(2, "Keyboard")).toEqual({
				Title = "PATIENT IN BAY 1",
				Sub = "Go to bay 1 · Examine",
				Key = "Prompt",
			})
			expect(w(2, "Touch").Sub).toBe("Go to bay 1 · tap Examine")
			expect(w(2, "Pad").Key).toBe("Prompt")
			expect(w(2, "Keyboard", { Bay = "3" }).Title).toBe("PATIENT IN BAY 3")
			-- (3) pick the glowing tool and play (the slim strip over the exam card)
			expect(w(3, "Keyboard", { Glow = true })).toEqual({
				Title = "PICK THE GLOWING TOOL",
				Sub = "Tap the glowing tool, then play!",
			})
			expect(w(3, "Keyboard", { Glow = false }).Title).toBe("PICK THE RIGHT TOOL") -- a replay past the first exams
			-- (4) the plan: get it from the shelf or the dispensary
			expect(w(4, "Keyboard", { Item = "Plaster", Where = "Shelf" })).toEqual({
				Title = "GET THE PLASTER",
				Sub = "From the supply wall · hold",
				Key = "Prompt",
			})
			expect(w(4, "Keyboard", { Item = "Cough syrup", Where = "Dispensary" })).toEqual({
				Title = "GET THE COUGH SYRUP",
				Sub = "At the dispensary · hold",
				Key = "Prompt",
			})
			expect(w(4, "Touch", { Item = "Ice pack", Where = "Shelf" }).Sub).toBe("Supply wall · hold Take")
			expect(w(4, "Touch", { Item = "Ear drops", Where = "Dispensary" }).Sub).toBe("Dispensary · hold Dispense")
			expect(w(4, "Keyboard").Title).toBe("GET THE TREATMENT") -- the plan isn't on the patient yet
			expect(w(4, "Keyboard", { Game = "Pick" }).Title).toBe("FIND THE BOTTLE!") -- the dispensing card is up
			-- (5) tap Treat
			expect(w(5, "Keyboard")).toEqual({
				Title = "TREAT YOUR PATIENT",
				Sub = "Back to bay 1 · Treat",
				Key = "Prompt",
			})
			expect(w(5, "Touch").Sub).toBe("Back to bay 1 · tap Treat")
			expect(w(5, "Keyboard", { Game = "Plaster" }).Title).toBe("PUT ON THE PLASTER!") -- its game, on the patient
			-- (6) "You treated your first patient!"
			expect(w(6, "Keyboard")).toEqual({ Title = "WELL DONE, DOCTOR!", Sub = "You treated your first patient!" })
			-- (7) treat 3 more
			expect(w(7, "Keyboard").Title).toBe("TREAT 3 MORE ○○○")
			expect(w(7, "Keyboard", { Cures = 1 }).Title).toBe("TREAT 3 MORE ●○○")
			expect(w(7, "Keyboard").Sub).toBe("New patient! Check its bubble")
			expect(w(7, "Keyboard", { AtBay = true, Bay = "2" })).toEqual({
				Title = "TREAT 3 MORE ○○○",
				Sub = "Go to bay 2 · Examine",
				Key = "Prompt",
			})
			expect(w(7, "Keyboard", { AtBay = true, Examined = true, Need = "🧴" }).Sub).toBe("It needs a 🧴!")
			-- a patient waits to be sent and no bay needs you: send it (bay work always comes first)
			expect(w(7, "Keyboard", { Waiting = true })).toEqual({
				Title = "TREAT 3 MORE ○○○",
				Sub = "Walk over · Send",
				Key = "Prompt",
			})
			expect(w(7, "Keyboard", { Waiting = true, AtBay = true, Bay = "2" }).Sub).toBe("Go to bay 2 · Examine")
			expect(w(7, "Keyboard", { AtBay = true, Examined = true, Carrying = true }).Sub).toBe(
				"Back to bay 1 · Treat"
			)
			-- ... and card 7's last part, the Shop
			expect(w(7, "Touch", { Shop = true }).Sub).toBe("Tap 🛒 · buy a ⚡")
			expect(w(7, "Keyboard", { Shop = true }).Sub).toBe("Click 🛒 · buy a ⚡")
			expect(w(7, "Pad", { Shop = true })).toEqual({
				Title = "UPGRADE YOUR CLINIC",
				Sub = "on 🛒",
				Key = "Confirm",
				KeyFirst = true,
			})
		end
	)

	test("no card says cure, and none is scary (design §2, §12)", function()
		for _, s in situations() do
			for cardNumber = 1, Logic.CARDS do
				local w = Card.words(cardNumber, s)
				for _, text in { w.Title, w.Sub } do
					local lower = string.lower(text)
					expect(string.find(lower, "%f[%a]cure")).toBeNil()
					expect(string.find(lower, "needle", 1, true)).toBeNil()
					expect(string.find(lower, "blood", 1, true)).toBeNil()
				end
			end
		end
		for _, line in Card.SAY do
			expect(string.find(string.lower(line), "%f[%a]cure")).toBeNil()
		end
	end)

	test("every Lv 1 case's first step reads as a whole title on card 4 (the tutorial's patients are Lv 1)", function()
		for _, caseId in Cases.ORDER do
			local case = Cases[caseId]
			if case.Level == 1 and case.Room == nil then
				local item = Items[case.Plan[1]]
				local title = Card.words(4, { Device = "Keyboard", Item = item.Name, Where = "Shelf" }).Title
				expect(title).toBe("GET THE " .. string.upper(item.Name))
			end
		end
	end)

	test("the word 'Spend' never appears; the pointer's label points at an upgrade (in-game cash)", function()
		local text = source("src/client/UI/Tutorial.luau")
		expect(string.find(text, '"[^"\n]*[Ss]pend[^"\n]*"')).toBeNil()
		expect(Card.BUY_LABEL).toBe("Buy this! ⚡")
	end)
end)

T.describe("Review fixes: a rejoin mid-replay, a Shop step with nothing to buy, phone words", function()
	test("a rejoin at steps 2-6 with the gift already given is still a replay", function()
		for _, step in { PATIENT, EXAMINE, TREAT, REST, MORE } do
			expect(Server.rejoinReplay(step, true)).toBe(true)
			expect(Server.rejoinReplay(step, false)).toBe(false) -- a first run: the gift comes at SHOP
			expect(Server.rejoinReplay(step, nil)).toBe(false)
		end
		-- the welcome card is a first run (or an admin restart); SHOP and BOOK can't be told apart; DONE is no run
		for _, step in { WELCOME, SHOP, BOOK, DONE } do
			expect(Server.rejoinReplay(step, true)).toBe(false)
		end
		expect(Server.rejoinReplay(nil, true)).toBe(false)
		expect(Server.rejoinReplay("2", true)).toBe(false)
		-- and a replay rejoined that way logs no funnel step
		expect(Server.funnel(EXAMINE, TREAT, Server.rejoinReplay(EXAMINE, true))).toBeNil()
	end)

	test("the Shop step moves on by itself only when there is nothing they can buy", function()
		expect(Server.shopStuck(100, nil)).toBe(true) -- every upgrade maxed
		expect(Server.shopStuck(49, 50)).toBe(true) -- a replay without the gift
		expect(Server.shopStuck(50, 50)).toBe(false)
		expect(Server.shopStuck(1e6, 50)).toBe(false)
		expect(Server.shopStuck(nil, 50)).toBe(true)
		expect(Config.Tutorial.ShopStuckSeconds > 0 and Config.Tutorial.ShopStuckSeconds <= 10).toBe(true)
		local text = source("src/server/Tutorial.luau")
		expect(string.find(text, "elseif step == Logic.SHOP then", 1, true) ~= nil).toBeTruthy()
		-- the client never dims the screen round the 🛒 on a replay or with nothing affordable
		local client = source("src/client/UI/Tutorial.luau")
		expect(string.find(client, "shopDim()", 1, true) ~= nil).toBeTruthy()
	end)

	test("a phone-width column gets the shortest touch words (they fit one line at 18 px)", function()
		local function w(cardNumber, extra)
			local s = { Device = "Touch", Item = "Cough syrup", Bay = "1", Total = 3, Cures = 0, Narrow = true }
			for k, v in extra or {} do
				s[k] = v
			end
			return Card.words(cardNumber, s)
		end
		expect(w(2).Sub).toBe("Tap Examine at bay 1")
		expect(w(3, { Glow = true }).Sub).toBe("Tap the glowing tool!")
		expect(w(4, { Where = "Dispensary" }).Sub).toBe("Hold Dispense")
		expect(w(4, { Where = "Shelf" }).Sub).toBe("Hold Take at the wall")
		expect(w(5).Sub).toBe("Tap Treat at bay 1")
		expect(w(6).Sub).toBe("First patient treated!")
		expect(w(7).Sub).toBe("Check its bubble")
		expect(w(1, { Waiting = true }).Sub).toBe("Tap Send on it")
		expect(w(7, { Waiting = true }).Sub).toBe("Tap Send on it")
		expect(w(7, { AtBay = true, Examined = true, Carrying = true }).Sub).toBe("Tap Treat at bay 1")
		for cardNumber = 1, Logic.CARDS do
			for _, extra in
				{
					{},
					{ AtBay = true, Bay = "W2" },
					{ AtBay = true, Examined = true, Need = "🧴", Where = "Dispensary" },
					{ AtBay = true, Examined = true, Carrying = true, Bay = "W1", Where = "Shelf" },
					{ Glow = false, Where = "Room" },
					{ Waiting = true },
					{ Shop = true },
				}
			do
				local sub = w(cardNumber, extra).Sub
				expect(sub ~= "").toBeTruthy()
				if utf8.len(sub) > 22 then
					error("card " .. cardNumber .. " is too long for a phone: " .. sub)
				end
			end
		end
		-- keyboard and pad keep the plan's words whatever the width
		expect(Card.words(2, { Device = "Keyboard", Bay = "1", Narrow = true }).Sub).toBe("Go to bay 1 · Examine")
		-- and the subtitle wraps inside its column instead of running off the card
		local client = source("src/client/UI/Tutorial.luau")
		expect(string.find(client, "subCap.MaxSize", 1, true) ~= nil).toBeTruthy()
	end)

	test("the beam's route survives Guide re-showing the same target (targets compared, never spec tables)", function()
		local text = source("src/client/UI/Wayfinder.luau")
		expect(string.find(text, "if spec ~= current then", 1, true)).toBeNil()
		expect(string.find(text, "live.Target ~= current.Target", 1, true) ~= nil).toBeTruthy()
	end)
end)

T.describe("Skip and Replay (the confirms; memory-20261117-002)", function()
	test("Skip: the binding words, and 'Keep going' as the safe default", function()
		expect(Card.SKIP).toEqual({
			Title = "Skip the tutorial?",
			Line = "You can replay it any time from ⚙️",
			Yes = "Skip",
			No = "Keep going",
		})
		-- the one line past 6 words (look build plan §F11), on purpose
		expect(words(Card.SKIP.Line)).toBe(7)
	end)

	test("Replay: its words, 'Not now' as the safe default", function()
		expect(Card.REPLAY).toEqual({
			Title = "Replay the tutorial?",
			Line = "Your waiting patients go home",
			Yes = "Replay",
			No = "Not now",
		})
		for _, text in { Card.REPLAY.Title, Card.REPLAY.Line, Card.SKIP.Title, Card.SKIP_CHIP } do
			expect(words(text) <= 6).toBeTruthy()
		end
	end)

	test("both go through Hud.confirm and the remotes (no hand-built confirm)", function()
		local text = source("src/client/UI/Tutorial.luau")
		expect(string.find(text, "Hud.confirm(ctx", 1, true) ~= nil).toBeTruthy()
		expect(string.find(text, "ctx.Remotes.TutorialSkip", 1, true) ~= nil).toBeTruthy()
		expect(string.find(text, "ctx.Remotes.TutorialReplay", 1, true) ~= nil).toBeTruthy()
		expect(string.find(text, 'ctx.on("SkipTutorial"', 1, true) ~= nil).toBeTruthy()
		expect(string.find(text, 'ctx.on("ReplayTutorial"', 1, true) ~= nil).toBeTruthy()
	end)
end)

T.describe("The guide nurse and the finale", function()
	test("the nurse's lines are 2-4 words", function()
		for name, line in Card.SAY do
			local n = words(line)
			if n < 2 or n > 4 then
				error(name .. ": " .. line)
			end
		end
	end)

	test("the finale: YOU DID IT! and short chips", function()
		expect(Card.FINALE.Title).toBe("YOU DID IT!")
		expect(words(Card.FINALE.Title) <= 3).toBeTruthy()
		for _, chip in Card.FINALE.Chips do
			expect(words(chip) <= 6).toBeTruthy()
		end
	end)

	test("'coming up' candidates are free events only, and the pick is the soonest within 6 h", function()
		local now = 1000
		local list = Card.candidates(now, now + 720, false, now + 200, 90)
		expect(#list).toBe(3)
		for _, candidate in list do
			expect(candidate.Paid).toBeNil()
		end
		local picked = NextEvent.pick(now, list)
		expect(picked.Id).toBe("Gift")
		expect(NextEvent.label(picked.At - now)).toBe("in 1m")
		-- at night there's no "night" to wait for; Golden Hour is next
		picked = NextEvent.pick(now, Card.candidates(now, now + 720, true, now + 200, nil))
		expect(picked.Id).toBe("Golden")
		expect(NextEvent.label(picked.At - now)).toBe("in 12m")
		-- a paid thing slipped into the list is never picked (red line 3)
		table.insert(list, 1, { Id = "Sale", Icon = "💸", Name = "Sale", At = now + 5, Paid = true })
		expect(NextEvent.pick(now, list).Id).toBe("Gift")
		-- nothing coming within 6 h: no chip
		expect(NextEvent.pick(now, Card.candidates(now, now + 7 * 3600, true, nil, nil))).toBeNil()
	end)
end)

T.describe("Celebrate: the Tutorial kind", function()
	local data = { Nurses = {}, Rarities = {}, Levels = {}, Decor = {}, Rooms = {}, NextLabel = NextEvent.label }
	local function finale(next: any, now: number?): any
		return Words.of({
			Kind = "Tutorial",
			Title = Card.FINALE.Title,
			Icon = Card.FINALE.Icon,
			Chips = Card.FINALE.Chips,
			Next = next,
		}, data, now)
	end

	test("the guide nurse's face, the chips and one COMING UP chip in minutes", function()
		local w = finale({ Id = "Golden", Icon = "🌟", Name = "Golden Hour", At = 1000 + 12 * 60 }, 1000)
		expect(w.Title).toBe("YOU DID IT!")
		expect(w.Portrait).toBe("Guide")
		expect(w.Sound).toBe("Fanfare")
		expect(w.Chips).toEqual(Card.FINALE.Chips)
		expect(w.Next).toBe("🌟 Golden Hour in 12m")
		expect(words(w.Next) <= 6).toBeTruthy()
		expect(Words.DURING_TUTORIAL.Tutorial).toBe(true)
	end)

	test("no chip for an event already started, junk, or no clock", function()
		expect(finale({ Id = "Golden", Icon = "🌟", Name = "Golden Hour", At = 900 }, 1000).Next).toBeNil()
		expect(finale({ Id = "Golden", Icon = "🌟", Name = "Golden Hour", At = 2000 }, nil).Next).toBeNil()
		expect(finale({ Id = "Golden", At = 2000 }, 1000).Next).toBeNil()
		expect(finale(nil, 1000).Next).toBeNil()
		expect(finale("soon", 1000).Next).toBeNil()
	end)

	test("other kinds still wait for the tutorial to end", function()
		for kind in Words.KINDS do
			if kind ~= "Tutorial" then
				expect(Words.DURING_TUTORIAL[kind]).toBeNil()
			end
		end
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- The source: UI rules, the Chirp, and the budgets
------------------------------------------------------------------------------------------------------------------

T.describe("T8's files follow the rules", function()
	test("uirules: every T8 UI file", function()
		local found = UiRules.check({
			"src/client/UI/Tutorial.luau",
			"src/client/UI/Guide.luau",
			"src/client/UI/Celebrate.luau",
			"src/client/UI/Wayfinder.luau",
		})
		if #found > 0 then
			error(UiRules.format(found))
		end
	end)

	test("Sounds has the Chirp cue (and lists it)", function()
		local text = source("src/client/Feel/Sounds.luau")
		expect(string.find(text, "\n\tChirp = {", 1, true) ~= nil).toBeTruthy()
		expect(string.find(text, 'Sounds.LOOK_CUES = table.freeze({\n\t"Chirp",', 1, true) ~= nil).toBeTruthy()
	end)

	test("one Highlight in the whole tutorial, made in one place (Wayfinder) and deleted by destroy()", function()
		local count = 0
		for _, path in
			{
				"src/client/UI/Tutorial.luau",
				"src/client/UI/Guide.luau",
				"src/client/UI/Celebrate.luau",
				"src/client/UI/Wayfinder.luau",
			}
		do
			for _ in string.gmatch(source(path), 'Instance%.new%("Highlight"%)') do
				count += 1
			end
		end
		expect(count).toBe(1)
		local way = source("src/client/UI/Wayfinder.luau")
		expect(string.find(way, "local existing = glow\n\tif existing and existing.Parent then", 1, true) ~= nil).toBeTruthy()
	end)

	test("the beam's loop: one RenderStepped, connected only while something shows", function()
		local way = source("src/client/UI/Wayfinder.luau")
		local _, connects = string.gsub(way, "RenderStepped:Connect", "")
		expect(connects).toBe(1)
		expect(
			string.find(
				way,
				"function Wayfinder.hide()\n\tspec = nil\n\troute = nil\n\tlastAim = nil\n\tdisconnectLoop()",
				1,
				true
			) ~= nil
		).toBeTruthy()
		local guide = source("src/client/UI/Guide.luau")
		expect(string.find(guide, "Wayfinder.destroy()", 1, true) ~= nil).toBeTruthy()
	end)

	test("the strip and the arrows share ONE polyline (Joshua: the arrows sit on the green line)", function()
		local way = source("src/client/UI/Wayfinder.luau")
		expect(string.find(way, "local function polyline(current: Route, start: Vector3)", 1, true) ~= nil).toBeTruthy()
		-- span 1's aim (from your feet), the fixed spans and the arrows all read it; nothing else builds a route line
		expect(string.find(way, "local points = polyline(made, here)", 1, true) ~= nil).toBeTruthy()
		expect(string.find(way, "local points = polyline(current, current.From)", 1, true) ~= nil).toBeTruthy()
		expect(string.find(way, "for _, p in polyline(current, start) do", 1, true) ~= nil).toBeTruthy()
		expect(string.find(way, "placeArrows(made, here, now)", 1, true) ~= nil).toBeTruthy()
		expect(string.find(way, "routePoints", 1, true)).toBeNil()
		expect(string.find(way, "BeamEndLift", 1, true)).toBeNil()
	end)

	test("the floor arrows never catch the player, move in one call, and march only when motion is on", function()
		local way = source("src/client/UI/Wayfinder.luau")
		local from = string.find(way, "local function makeArrow", 1, true)
		local to = string.find(way, "local function ensureArrows", 1, true)
		assert(from and to, "no makeArrow")
		local body = string.sub(way, from, to)
		for _, line in
			{
				"part.Anchored = true",
				"part.CanCollide = false",
				"part.CanQuery = false",
				"part.CanTouch = false",
				"part.CastShadow = false",
			}
		do
			expect(string.find(body, line, 1, true) ~= nil).toBeTruthy()
		end
		expect(string.find(way, "SurfaceGui", 1, true)).toBeNil() -- the old paper-clip bars are gone
		local _, bulk = string.gsub(way, "BulkMoveTo%(", "")
		expect(bulk).toBe(1)
		expect(string.find(way, "local march = not still and", 1, true) ~= nil).toBeTruthy()
	end)

	test("original only: no red cross and no toy brand in T8's files", function()
		for _, path in
			{
				"src/client/UI/Tutorial.luau",
				"src/client/UI/Guide.luau",
				"src/client/UI/Celebrate.luau",
				"src/client/UI/Wayfinder.luau",
				"src/server/Tutorial.luau",
			}
		do
			local text = source(path)
			expect(string.find(text, "LEGO", 1, true)).toBeNil()
			expect(string.find(text, "crossSign", 1, true)).toBeNil()
		end
	end)
end)

------------------------------------------------------------------------------------------------------------------
-- T4 (the calm UI, play flow): the tutorial card in words, chrome icons from UI/Icons, the supply wall
-- (UI direction §2 and §4 row 9; memory-20261117-007)
------------------------------------------------------------------------------------------------------------------

T.describe("T4: the tutorial's words are calm (UI direction §2)", function()
	local Building = require("../src/shared/Logic/Building")
	local stations = source("src/shared/Data/Stations.luau")
	local text = source("src/client/UI/Tutorial.luau")

	test("no card line opens with an emoji, and no line has two emoji except the Shop pointer", function()
		local situations = {
			{},
			{ AtBay = true },
			{ Waiting = true },
			{ AtBay = true, Examined = true, Need = "🩹" },
			{ AtBay = true, Examined = true, Carrying = true },
			{ Item = "Plaster", Where = "Shelf" },
			{ Item = "Cough syrup", Where = "Dispensary" },
			{ Item = "Cast", Where = "Room" },
			{ Shop = true },
		}
		for _, device in { "Keyboard", "Touch", "Pad" } do
			for _, narrow in { false, true } do
				for cardNumber = 1, Card.CARDS do
					for _, extra in situations do
						local s = table.clone(extra) :: any
						s.Device = device
						s.Narrow = narrow
						local card = Card.words(cardNumber, s)
						for _, line in { card.Title, card.Sub } do
							local first = Icons.clusters(line)[1]
							if first then
								assert(string.sub(line, 1, #first) ~= first, "opens with an emoji: " .. line)
							end
							assert(not string.find(line, "👆", 1, true), "a gesture emoji in chrome: " .. line)
							if not s.Shop then
								assert(Icons.count(line) <= 1, "two emoji: " .. line)
							end
						end
					end
				end
			end
		end
	end)

	test("the Shop pointer names the Shop door from UI/Icons (Tap 🛒)", function()
		expect(Card.words(7, { Device = "Touch", Shop = true }).Sub).toBe("Tap " .. Icons.Door.Shop .. " · buy a ⚡")
		expect(Card.words(7, { Device = "Keyboard", Shop = true }).Sub).toBe(
			"Click " .. Icons.Door.Shop .. " · buy a ⚡"
		)
		expect(Card.words(7, { Device = "Pad", Shop = true }).Sub).toBe("on " .. Icons.Door.Shop)
		-- loaded with no Icons at all (another spec's loader), the words still stand
		local bare = block("src/client/UI/Tutorial.luau", "-- PURE-BEGIN", "-- PURE-END", "Pure")
		expect(bare.words(7, { Device = "Pad", Shop = true }).Sub).toBe("on")
		expect(bare.SKIP.Line).toBe("You can replay it any time from")
	end)

	test(
		"confirm titles and buttons are words; the Skip line keeps its binding ⚙️ (Icons.Door.Settings)",
		function()
			for _, confirm in { Card.SKIP, Card.REPLAY } do
				expect(Icons.count(confirm.Title)).toBe(0)
				expect(Icons.count(confirm.Yes)).toBe(0)
				expect(Icons.count(confirm.No)).toBe(0)
			end
			expect(Card.SKIP.Line).toBe("You can replay it any time from " .. Icons.Door.Settings)
			expect(Card.SKIP_CHIP).toBe("Skip")
			for name, line in Card.SAY do
				expect(Icons.count(line) == 0 or name == "Nudge").toBe(true)
			end
		end
	)

	test("the finale's chips and the 'coming up' events wear UI/Icons' own icons", function()
		expect(Card.FINALE.Chips).toEqual({
			Icons.Door.Book .. " Collect them all",
			Icons.Door.Goals .. " Daily goals",
			Icons.Door.Nurses .. " Hire nurses",
		})
		local icons = {}
		for _, candidate in Card.candidates(1000, 1720, false, 1200, 90) do
			icons[candidate.Id] = candidate.Icon
		end
		expect(icons).toEqual({ Golden = Icons.Status.Golden, Night = Icons.Status.Night, Gift = Icons.Door.Gifts })
	end)

	test(
		"card 4 says 'supply wall' for every station on it: the shelves, the hot chocolate and the bath foam",
		function()
			-- The card's SHELF set is Logic/Building's supply wall, not a hand list (Cocoa and Bath moved onto it).
			local shelf = string.match(text, "local SHELF[^\n]*\n(.-)\nend")
			assert(shelf, "SHELF is built from a loop")
			assert(string.find(shelf, "BuildingLogic.SUPPLY_ORDER", 1, true), "SHELF reads Logic/Building.SUPPLY_ORDER")
			for _, id in { "Plaster", "Ice", "Bandage", "Cocoa", "Bath" } do
				expect(table.find(Building.SUPPLY_ORDER, id) ~= nil).toBe(true)
				local row = string.match(stations, "\n%s*" .. id .. " = (%b{})")
				assert(row and not string.find(row, "Dispense", 1, true), id .. " is a supply, not the dispensary")
			end
			-- the Remedy counter stands on the wall too, but it is the dispensary: that check comes first
			local remedy = string.match(stations, "\n%s*Remedy = (%b{})")
			assert(remedy and string.find(remedy, "Dispense = true", 1, true), "Remedy is the dispensary")
			local look = string.match(
				text,
				'if type%(station%) == "table" and station.Dispense == true then.-SHELF%[stationId%]'
			)
			assert(look, "the Dispense check comes before the supply wall's")
			for _, device in { "Keyboard", "Touch" } do
				for _, narrow in { false, true } do
					local sub =
						Card.words(4, { Device = device, Narrow = narrow, Item = "Hot chocolate", Where = "Shelf" }).Sub
					assert(string.find(string.lower(sub), "wall", 1, true), device .. ": " .. sub)
					assert(not string.find(sub, "shelf", 1, true), sub)
				end
			end
			expect(Card.words(4, { Device = "Keyboard", Item = "Hot chocolate", Where = "Shelf" }).Title).toBe(
				"GET THE HOT CHOCOLATE"
			)
			expect(Card.words(4, { Device = "Keyboard", Item = "Bath foam", Where = "Shelf" }).Sub).toBe(
				"From the supply wall · hold"
			)
		end
	)

	test("the waiting patient's part of the first card keeps its behaviour (simple-start design §2)", function()
		expect(Card.words(1, { Device = "Keyboard", Waiting = true })).toEqual({
			Title = "YOUR PATIENT IS WAITING",
			Sub = "Walk over · Send",
			Key = "Prompt",
		})
		expect(Card.words(1, { Device = "Touch", Waiting = true }).Sub).toBe("Walk over · tap Send")
	end)

	test("the ratchet: every calm rule at 0 on the play-flow files (allowed lines carry their reason)", function()
		local files = {
			"src/client/UI/MiniGames.luau",
			"src/client/UI/Tutorial.luau",
			"src/client/UI/Guide.luau",
			"src/client/UI/LiftPanel.luau",
			"src/client/UI/SendCard.luau",
		}
		local over = UiRules.ratchet(files, {})
		assert(#over == 0, "\n" .. table.concat(over, "\n"))
		-- and the old hard rules
		local found = UiRules.check(files)
		assert(#found == 0, "\n" .. UiRules.format(found))
	end)
end)
