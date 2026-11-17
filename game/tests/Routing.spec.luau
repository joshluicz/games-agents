--!nocheck
-- The player sends each patient (simple-start design §2; memory-20261117-006, Joshua: "you do it ... perhaps its just
-- sending them to the correct ward or place for treatment"). The real Logic/Routing, the real Logic/Building bays and
-- Data/Cases, UI/SendCard's PURE block, and source checks on Server/Patients, Shared/Remotes and the client (the other
-- specs load only PURE blocks, so only the source can show these):
--   · the bay tick no longer calls walk-ins by itself;
--   · the SendPatient remote is validated on the server (rate, types, who, which patient, where, the pick);
--   · the Send prompt is gated like the other patient prompts (the TreatPrompt tag, Plots.canWork).
-- Run from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local T = require("./expect")
local expect, test = T.expect, T.test

local Config = require("./config")
local Routing = require("../src/shared/Logic/Routing")
local Building = require("../src/shared/Logic/Building")
local Visit = require("../src/shared/Logic/Visit")
local Cases = require("../src/shared/Data/Cases")
local Tools = require("../src/shared/Data/Tools")
local Jobs = require("../src/shared/Data/Jobs")

local function source(path: string): string
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("can't find " .. path .. " (run from game/)")
end

-- A file's code: comment lines dropped (a rule may be named in a comment).
local function code(path: string): string
	local lines = {}
	for line in string.gmatch(source(path), "[^\n]+") do
		if not string.match(line, "^%s*%-%-") then
			table.insert(lines, line)
		end
	end
	return table.concat(lines, "\n")
end

-- The text of one function, from its header to the next top-level `end`.
local function body(text: string, header: string): string
	local from = string.find(text, header, 1, true)
	assert(from, "no " .. header)
	local to = string.find(text, "\nend", from, true)
	assert(to, "no end after " .. header)
	return string.sub(text, from, to + 3)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

-- The usable bays of a clinic, as Server/Patients' U.places hands them to Routing (every one free unless `taken`).
local function places(level: number, rooms: { [string]: boolean }?, taken: { [string]: boolean }?): { any }
	local out = {}
	for _, bay in Building.openBays(level, rooms) do
		table.insert(out, { Id = bay.Id, Kind = bay.Kind, X = bay.X, Z = bay.Z, Free = not (taken and taken[bay.Id]) })
	end
	return out
end

local function count(text: string): number
	local n = 0
	for _ in string.gmatch(text, "%S+") do
		n += 1
	end
	return n
end

T.describe("Routing: which place a case needs", function()
	test("an X-ray case needs the X-ray; every other case an exam bay", function()
		expect(Routing.kindFor("XRay")).toBe("XRay")
		for _, tool in { "Stethoscope", "Thermometer", "Magnifier", "Light" } do
			expect(Routing.kindFor(tool)).toBe("Exam")
		end
		for _, junk in { 0, {}, "", "xray", true } do
			expect(Routing.kindFor(junk)).toBe("Exam")
		end
		expect(Routing.kindFor(nil)).toBe("Exam")
	end)

	test("it agrees with the bays' own rule (Logic/Visit.nextForBay) for every case in Data/Cases", function()
		expect(Routing.XRAY_TOOL).toBe(Visit.XRAY)
		local seen = 0
		for id, case in Cases do
			if type(case) == "table" and type(case.Tool) == "string" then
				seen += 1
				local kind = Routing.kindFor(case.Tool)
				local row = { { Id = 1, Since = 0, Tool = case.Tool } }
				if Visit.nextForBay(row, kind) ~= 1 then
					error(tostring(id) .. " would be sent to a bay that never takes it")
				end
				local other = if kind == "XRay" then "Exam" else "XRay"
				expect(Visit.nextForBay(row, other)).toBe(nil)
			end
		end
		expect(seen > 5).toBe(true)
	end)

	test("the two kinds are the bays' kinds, and the X-ray tool is a real tool", function()
		expect(Routing.KINDS).toEqual({ "Exam", "XRay" })
		local kinds = {}
		for _, bay in Building.BAYS do
			kinds[bay.Kind] = true
		end
		expect(kinds).toEqual({ Exam = true, XRay = true })
		expect(type(Tools[Routing.XRAY_TOOL])).toBe("table")
		for _, kind in Routing.KINDS do
			expect(Routing.isChoice(kind)).toBe(true)
		end
		for _, junk in { "exam", "Xray", "", 1, true, {} } do
			expect(Routing.isChoice(junk)).toBe(false)
		end
		expect(Routing.isChoice(nil)).toBe(false)
	end)
end)

T.describe("Routing: who is sent, and by whom", function()
	test("the player may send a patient settled in the waiting room, with no bay, that isn't urgent", function()
		expect(Routing.waiting("Seated", nil, "")).toBe(true)
		expect(Routing.waiting("Seated", "", "")).toBe(true)
		expect(Routing.waiting("Seated", "1", "")).toBe(false) -- sent already
		expect(Routing.waiting("Seated", nil, "AE")).toBe(false) -- 🚑: straight to a bay
		expect(Routing.waiting("Seated", nil, "VIP")).toBe(false) -- 🚁
		for _, phase in { "Arriving", "ToBay", "Bay", "Requeue", "Done", "Leaving", "Sad", "Gone" } do
			expect(Routing.waiting(phase, nil, "")).toBe(false)
		end
		expect(Routing.waiting(nil, nil, nil)).toBe(false)
	end)

	test("the tick calls nobody by itself, except a 🚑/🚁 patient and one that was sent before", function()
		expect(Routing.auto("", false)).toBe(false) -- a walk-in: it waits for Send
		expect(Routing.auto(nil, nil)).toBe(false)
		expect(Routing.auto("", "yes")).toBe(false)
		expect(Routing.auto("AE", false)).toBe(true)
		expect(Routing.auto("VIP", false)).toBe(true)
		expect(Routing.auto(true, false)).toBe(true)
		expect(Routing.auto("", true)).toBe(true) -- its bay closed in a rebuild: on to the next free one
	end)
end)

T.describe("Routing: one press, or the two-button card", function()
	test("Lv 1-2: one kind of place, so one press (no card)", function()
		expect(Routing.needsChoice(1, places(1))).toBe(false)
		expect(Routing.needsChoice(2, places(2))).toBe(false)
		expect(Routing.needsChoice(2, places(2, { Ward = true }))).toBe(false)
	end)

	test("Lv 3+: the X-ray bay is open, so the prompt opens the card", function()
		expect(Routing.CHOICE_LEVEL).toBe(3)
		for level = 3, 5 do
			expect(Routing.needsChoice(level, places(level))).toBe(true)
		end
		-- the X-ray bay is the level's only second kind of place
		local xray = 0
		for _, bay in Building.BAYS do
			if bay.Kind == "XRay" then
				xray += 1
				expect(bay.Opens).toBe(Routing.CHOICE_LEVEL)
			end
		end
		expect(xray).toBe(1)
	end)

	test("no card when a kind is missing (the X-ray bay not built yet), or on junk", function()
		expect(Routing.needsChoice(3, { { Kind = "Exam" }, { Kind = "Exam" } })).toBe(false)
		expect(Routing.needsChoice(3, { { Kind = "XRay" } })).toBe(false)
		expect(Routing.needsChoice(3, {})).toBe(false)
		expect(Routing.needsChoice(3, nil)).toBe(false)
		expect(Routing.needsChoice("3", places(3))).toBe(false)
		expect(Routing.needsChoice(0 / 0, places(3))).toBe(false)
		expect(Routing.needsChoice(2, places(3))).toBe(false) -- the level decides too
	end)

	test("the pick: right goes, wrong is gently corrected, junk is nothing", function()
		expect({ Routing.check("Exam", "Exam") }).toEqual({ true })
		expect({ Routing.check("XRay", "XRay") }).toEqual({ true })
		expect({ Routing.check("Exam", "XRay") }).toEqual({ false, "That one needs the X-ray!" })
		expect({ Routing.check("XRay", "Exam") }).toEqual({ false, "That one needs an exam bay!" })
		for _, junk in { "", "exam", 1, true, {} } do
			expect({ Routing.check(junk, "Exam") }).toEqual({ false })
			expect({ Routing.check("Exam", junk) }).toEqual({ false })
		end
		expect({ Routing.check(nil, "Exam") }).toEqual({ false })
	end)

	test("every word the player sees is short and kind; the title has no emoji, each choice has one", function()
		expect(Routing.TEXT.Action).toBe("Send")
		expect(Routing.TEXT.Busy).toBe("All bays are busy!")
		expect(Routing.TEXT.Exam).toBe("🩺 Exam bay")
		expect(Routing.TEXT.XRay).toBe("📸 X-ray")
		for key, text in Routing.TEXT do
			if count(text) > 6 then
				error(key .. " is over 6 words: " .. text)
			end
		end
		expect(string.match(Routing.TEXT.Title, "^[%a%s%?]+$") ~= nil).toBe(true) -- words only
		expect(has(Routing.TEXT.Exam, "🩺")).toBe(true)
		expect(has(Routing.TEXT.XRay, "📸")).toBe(true)
		expect(has(Routing.TEXT.XRay, "🩻")).toBe(false) -- Roblox has no glyph for it (tests/Emoji.spec)
	end)
end)

T.describe("Routing: which bay", function()
	test("the nearest free bay that fits, measured from the patient", function()
		local all = places(5)
		expect(Routing.pickBay(all, "Exam", { X = -28, Z = 10 })).toBe("1")
		expect(Routing.pickBay(all, "Exam", { X = 4, Z = 10 })).toBe("6")
		expect(Routing.pickBay(all, "Exam", { X = -15, Z = 10 })).toBe("3")
		expect(Routing.pickBay(all, "XRay", { X = -28, Z = 10 })).toBe("X") -- however far it is
	end)

	test("a taken bay is skipped; nothing free that fits is nil ('All bays are busy!')", function()
		local from = { X = -28, Z = 10 }
		expect(Routing.pickBay(places(1, nil, { ["1"] = true }), "Exam", from)).toBe("2")
		expect(Routing.pickBay(places(1, nil, { ["1"] = true, ["2"] = true }), "Exam", from)).toBe(nil)
		expect(Routing.pickBay(places(3, nil, { X = true }), "XRay", from)).toBe(nil) -- exam bays never take it
		expect(Routing.pickBay(places(2), "XRay", from)).toBe(nil) -- no X-ray bay before Lv 3
		expect(Routing.pickBay({}, "Exam", from)).toBe(nil)
	end)

	test("an exam case never lands in the X-ray bay, and an X-ray case never in an exam bay", function()
		for level = 1, 5 do
			for _, kind in Routing.KINDS do
				for x = -40, 40, 8 do
					local id = Routing.pickBay(places(level, { Ward = true }), kind, { X = x, Z = 6 })
					if id then
						expect(Building.bay(id).Kind).toBe(kind)
					end
				end
			end
		end
	end)

	test("no `from` (the tutorial): the first free bay in order, so the first patient takes bay 1", function()
		expect(Routing.pickBay(places(1), "Exam", nil)).toBe("1")
		expect(Routing.pickBay(places(5, { Ward = true }), "Exam", nil)).toBe("1")
		expect(Routing.pickBay(places(1, nil, { ["1"] = true }), "Exam", nil)).toBe("2")
		expect(Routing.pickBay(places(1), "Exam", { X = 0 / 0, Z = 0 })).toBe("1") -- a junk point counts as none
	end)

	test("a tie goes to the first in order; junk rows and a junk kind are skipped; inputs are never changed", function()
		local two = {
			{ Id = "A", Kind = "Exam", X = -1, Z = 0, Free = true },
			{ Id = "B", Kind = "Exam", X = 1, Z = 0, Free = true },
		}
		expect(Routing.pickBay(two, "Exam", { X = 0, Z = 0 })).toBe("A")
		expect(Routing.pickBay({ 5, "x", { Kind = "Exam", Free = true }, two[2] }, "Exam", { X = 0, Z = 0 })).toBe("B")
		expect(Routing.pickBay(two, "Bath", { X = 0, Z = 0 })).toBe(nil)
		expect(Routing.pickBay(nil, "Exam", nil)).toBe(nil)
		expect(two[1]).toEqual({ Id = "A", Kind = "Exam", X = -1, Z = 0, Free = true })
		expect(Routing.pickBay({ { Id = "A", Kind = "Exam", X = 0, Z = 0, Free = "yes" } }, "Exam", nil)).toBe(nil)
	end)
end)

T.describe("Routing: the Receptionist sends them later (the nurse hook)", function()
	test("after a short wait on the seat, one at a time with a little gap", function()
		expect(Routing.RECEPTION_WAIT).toBe(6)
		expect(Routing.RECEPTION_GAP).toBe(2)
		expect(Routing.receptionistReady(100, 105.9, nil)).toBe(false) -- sat 5.9 s
		expect(Routing.receptionistReady(100, 106, nil)).toBe(true)
		expect(Routing.receptionistReady(100, 106, -math.huge)).toBe(true) -- nobody sent yet
		expect(Routing.receptionistReady(100, 110, 109)).toBe(false) -- one went a second ago
		expect(Routing.receptionistReady(100, 111, 109)).toBe(true)
	end)

	test("not before it has settled; the wait and the gap can be tuned; junk never sends", function()
		expect(Routing.receptionistReady(nil, 200, nil)).toBe(false) -- still walking to its seat
		expect(Routing.receptionistReady(100, 103, nil, 3, 0)).toBe(true)
		expect(Routing.receptionistReady(100, 103, 103, 3, 0)).toBe(true)
		expect(Routing.receptionistReady(100, 103, 103, 3, 1)).toBe(false)
		expect(Routing.receptionistReady(100, 100, nil, -5, -5)).toBe(true)
		expect(Routing.receptionistReady("100", 200, nil)).toBe(false)
		expect(Routing.receptionistReady(100, 0 / 0, nil)).toBe(false)
	end)

	test("the shipped numbers: Config.Visit matches, never sooner than the seat time; the job is real", function()
		expect(Config.Visit.ReceptionSeconds).toBe(Routing.RECEPTION_WAIT)
		expect(Config.Visit.ReceptionGap).toBe(Routing.RECEPTION_GAP)
		expect(Config.Visit.ReceptionSeconds >= Config.Visit.SeatSeconds).toBe(true)
		expect(type(Jobs.Receptionist)).toBe("table")
	end)

	test("Server/Patients: only with a Receptionist on duty, through the same send as the player's", function()
		local fn = body(code("src/server/Patients.luau"), "function U.receptionSend(")
		expect(has(fn, "if not state.Receptionist.Triage then")).toBe(true)
		expect(has(fn, "K.Routing.waiting(p.Phase, p.Bay, p.Urgent)")).toBe(true)
		expect(has(fn, "K.Routing.receptionistReady(")).toBe(true)
		expect(has(fn, "U.send(state, p, nil)")).toBe(true)
		expect(has(fn, "state.LastSent = now")).toBe(true)
		expect(has(fn, "Remotes.toast")).toBe(false) -- nobody is told off for a nurse's wait
	end)
end)

T.describe("Server/Patients: the bay tick no longer sends walk-ins", function()
	local text = code("src/server/Patients.luau")

	test("assignBays lists only those U.autoCall allows (never plain U.canCall)", function()
		local fn = body(text, "assignBays = function(state: PlotState)")
		expect(has(fn, "if U.autoCall(p, now) then")).toBe(true)
		expect(has(fn, "U.canCall(")).toBe(false)
		local auto = body(text, "function U.autoCall(")
		expect(has(auto, "K.Routing.auto(p.Urgent, p.Sent)")).toBe(true)
		expect(has(auto, "U.canCall(p, now)")).toBe(true)
	end)

	test(
		"U.callToBay has two call sites: U.send (the player, the Receptionist) and the tick's own short list",
		function()
			local calls = 0
			for _ in string.gmatch(text, "U%.callToBay%(state, p, ") do
				calls += 1
			end
			expect(calls).toBe(2) -- U.send (the player and the Receptionist) and assignBays
			expect(has(body(text, "function U.send("), "U.callToBay(state, p, bayId)")).toBe(true)
			expect(has(body(text, "assignBays = function(state: PlotState)"), "U.callToBay(state, p, pick.Bay)")).toBe(
				true
			)
			-- and a sent patient is marked, so only IT is re-sent if its bay closes
			expect(has(body(text, "function U.callToBay("), "p.Sent = true")).toBe(true)
		end
	)

	test("a waiting patient keeps its seat, its symptom bubble and the waiting-room patience rate", function()
		expect(has(body(text, "local function waitSeated("), 'p.Phase == "Seated"')).toBe(true)
		local patience = body(text, "local function tickPatience(")
		expect(has(patience, 'if p.Phase == "Seated" then\n\t\t\trate = Visit.PATIENCE.Waiting')).toBe(true)
		expect(has(patience, 'U.tutorialAsk("calm", false, state.Owner)')).toBe(true) -- never runs out in the tutorial
		expect(Visit.PATIENCE.Waiting).toBe(0.5)
		-- left too long: home with a sad puff, never a penalty (no cash, no stars taken)
		local sad = body(text, "local function makeSad(")
		expect(has(sad, "Economy")).toBe(false)
		expect(has(sad, "PlayerData")).toBe(false)
	end)

	test("the Send prompt: on the patient, E, a tap, off until it waits, gated like the bay prompts", function()
		local fn = body(text, "function U.sendPrompt(")
		expect(has(fn, 'prompt.Name = "SendPrompt"')).toBe(true)
		expect(has(fn, "prompt.ActionText = K.Routing.TEXT.Action")).toBe(true)
		expect(has(fn, "prompt.ObjectText = p.Symptom")).toBe(true)
		expect(has(fn, "prompt.KeyboardKeyCode = Enum.KeyCode.E")).toBe(true)
		expect(has(fn, "prompt.HoldDuration = 0")).toBe(true)
		expect(has(fn, "prompt.Enabled = false")).toBe(true)
		expect(has(fn, 'prompt:AddTag("TreatPrompt")')).toBe(true) -- UI/PromptFilter: workers of this clinic only
		expect(has(fn, 'prompt:SetAttribute("VisitId", p.Id)')).toBe(true)
		expect(has(source("src/client/UI/PromptFilter.luau"), 'local TREAT_TAG = "TreatPrompt"')).toBe(true)
		-- only walk-ins get one: a 🚑/🚁 patient goes straight to a bay
		expect(has(text, 'if urgentKind == "" then\n\t\tp.Send = U.sendPrompt(state, p)')).toBe(true)
		local refresh = body(text, "local function refreshPrompts(")
		expect(has(refresh, "state.Active and K.Routing.waiting(p.Phase, p.Bay, p.Urgent)")).toBe(true)
		expect(has(refresh, "K.Routing.needsChoice(state.Level, U.places(state))")).toBe(true)
	end)

	test("one press sends it (Lv 1-2); with two kinds of place the press waits for the card's pick", function()
		local fn = body(text, "function U.onSendPrompt(")
		expect(has(fn, "K.Routing.needsChoice(state.Level, U.places(state))")).toBe(true)
		expect(has(fn, "U.mayPress(player, state, visitId)")).toBe(true)
		expect(has(fn, "U.send(state, p, nil)")).toBe(true)
		expect(has(fn, "Remotes.toast(player, message)")).toBe(true)
	end)

	test("U.send: the right kind of place, the nearest free bay, a kind toast and no penalty otherwise", function()
		local fn = body(text, "function U.send(")
		expect(has(fn, "K.Routing.waiting(p.Phase, p.Bay, p.Urgent)")).toBe(true)
		expect(has(fn, "K.Routing.kindFor(p.Case.Tool)")).toBe(true)
		expect(has(fn, "K.Routing.check(choice, kind)")).toBe(true)
		expect(has(fn, "K.Routing.pickBay(U.places(state), kind, from)")).toBe(true)
		expect(has(fn, "return false, K.Routing.TEXT.Busy")).toBe(true)
		-- through the tutorial's one-at-a-time steps there is no `from`: bay 1
		expect(has(fn, 'U.tutorialAsk("queueCap", nil, state.Owner) == nil')).toBe(true)
		-- a wrong pick changes nothing on the patient
		for _, touched in { "p.Patience", "makeSad", "p.Phase =", "freeSeat" } do
			expect(has(fn, touched)).toBe(false)
		end
	end)
end)

T.describe("The SendPatient remote is validated on the server", function()
	local text = code("src/server/Patients.luau")
	local remotes = code("src/shared/Remotes.luau")

	test("it is a RemoteEvent the server makes, and only Server/Patients listens to it", function()
		expect(has(remotes, '"SendPatient",')).toBe(true)
		expect(has(remotes, 'SendPatient = folder:WaitForChild("SendPatient") :: RemoteEvent')).toBe(true)
		expect(has(text, "Remotes.SendPatient.OnServerEvent:Connect(")).toBe(true)
		expect(has(text, "pcall(U.onSendRemote, player, visitId, choice)")).toBe(true)
	end)

	test("the rate limit comes first, then the types: a whole number and one of the two strings", function()
		local fn = body(text, "function U.onSendRemote(")
		local rate = string.find(fn, "Remotes.allow(player, K.SEND_REMOTE)", 1, true)
		local types = string.find(fn, 'type(visitId) ~= "number"', 1, true)
		local use = string.find(fn, "candidate.ById[visitId]", 1, true)
		expect(rate ~= nil and types ~= nil and use ~= nil).toBe(true)
		expect(rate < types and types < use).toBe(true)
		expect(has(fn, "visitId ~= visitId")).toBe(true) -- NaN
		expect(has(fn, "visitId % 1 ~= 0")).toBe(true)
		expect(has(fn, "not K.Routing.isChoice(choice)")).toBe(true)
		expect(has(fn, "U.mayPress(player, state, visitId)")).toBe(true)
		expect(has(fn, "U.send(state, p, choice)")).toBe(true)
	end)

	test("who, which patient and where: a worker of that clinic, a patient still waiting, standing by it", function()
		local fn = body(text, "function U.mayPress(")
		expect(has(fn, "now - (U.lastSend[player] or 0) < K.SEND_COOLDOWN")).toBe(true)
		expect(has(fn, "Plots.canWork(player, state.Plot)")).toBe(true)
		expect(has(fn, "state.ById[visitId]")).toBe(true) -- the patient is that clinic's
		expect(has(fn, "K.Routing.waiting(p.Phase, p.Bay, p.Urgent)")).toBe(true) -- still seated, not sent
		expect(has(fn, "K.PROMPT_DISTANCE + K.DISTANCE_SLACK")).toBe(true)
		-- canWork comes before anything about the patient is answered
		expect(string.find(fn, "Plots.canWork", 1, true) < string.find(fn, "state.ById[visitId]", 1, true)).toBe(true)
	end)

	test("the client only asks: it fires the remote with the id and the pick, and decides nothing", function()
		local card = code("src/client/UI/SendCard.luau")
		expect(has(card, "ctx.Remotes.SendPatient:FireServer(id, choice)")).toBe(true)
		for _, never in { "callToBay", "SetAttribute", "Cash", "InvokeServer" } do
			expect(has(card, never)).toBe(false)
		end
		expect(has(code("src/client/Main.client.luau"), '"SendCard",')).toBe(true)
	end)
end)

T.describe("UI/SendCard (the two-button card)", function()
	local text = source("src/client/UI/SendCard.luau")
	local from = string.find(text, "-- PURE-BEGIN", 1, true)
	local to = string.find(text, "-- PURE-END", 1, true)
	assert(from and to and to > from, "SendCard: no PURE block")
	local Card = luau.load(string.sub(text, from, to - 1) .. "\nreturn Pure\n", {
		debugName = "SendCard (pure)",
		environment = { Routing = Routing },
	})()

	test("two buttons, in order: 🩺 Exam bay, 📸 X-ray", function()
		expect(Card.buttons()).toEqual({
			{ Choice = "Exam", Text = "🩺 Exam bay" },
			{ Choice = "XRay", Text = "📸 X-ray" },
		})
		for _, button in Card.buttons() do
			expect(Routing.isChoice(button.Choice)).toBe(true) -- what the server accepts
		end
	end)

	test("it opens only for your own press of a Send prompt that asks for a choice", function()
		expect(Card.opens("SendPrompt", true, true, 12)).toBe(12)
		expect(Card.opens("SendPrompt", true, false, 12)).toBe(nil) -- Lv 1-2: the press sent it already
		expect(Card.opens("SendPrompt", true, nil, 12)).toBe(nil)
		expect(Card.opens("SendPrompt", false, true, 12)).toBe(nil) -- someone else's press
		expect(Card.opens("BayPrompt", true, true, 12)).toBe(nil)
		expect(Card.opens("SendPrompt", true, true, "12")).toBe(nil)
		expect(Card.opens("SendPrompt", true, true, 1.5)).toBe(nil)
		expect(Card.opens("SendPrompt", true, true, 0 / 0)).toBe(nil)
	end)

	test("it closes by itself when the patient is sent or gone, or you walk away", function()
		expect(Card.stays("Waiting", "", 5)).toBe(true)
		expect(Card.stays("Waiting", nil, Card.REACH)).toBe(true)
		expect(Card.stays("Waiting", "", Card.REACH + 0.1)).toBe(false)
		expect(Card.stays("ToBay", "2", 5)).toBe(false)
		expect(Card.stays("Waiting", "2", 5)).toBe(false)
		expect(Card.stays("Sad", "", 5)).toBe(false)
		expect(Card.stays(nil, nil, math.huge)).toBe(false)
		expect(Card.stays("Waiting", "", 0 / 0)).toBe(false)
	end)

	test(
		"it uses the shared shell and Kit buttons (a later phase rebuilds the UI): calm, no look of its own",
		function()
			local card = code("src/client/UI/SendCard.luau")
			expect(has(card, "Hud.modal(ctx, {")).toBe(true)
			expect(has(card, "Title = Routing.TEXT.Title")).toBe(true)
			expect(has(card, 'Kind = "Secondary"')).toBe(true)
			expect(has(card, "Kit.button({")).toBe(true)
			expect(Card.BUTTON_HEIGHT >= 56).toBe(true) -- a child's thumb
			for _, never in { "RenderStepped", "Heartbeat", "Kit.shine", "Kit.breathing" } do
				expect(has(card, never)).toBe(false)
			end
		end
	)
end)

T.describe("The guide points at a waiting patient (UI/Tutorial steers UI/Guide)", function()
	local text = code("src/client/UI/Tutorial.luau")

	test("lowest priority: only when no bay needs the doctor", function()
		local fn = body(text, "local function waitingSteer(")
		local visit = string.find(fn, "visitNow(plot).Do ~= nil", 1, true)
		local patient = string.find(fn, "waitingPatient(plot)", 1, true)
		expect(visit ~= nil and patient ~= nil and visit < patient).toBe(true)
		expect(has(fn, "sendSteer(patient)")).toBe(true)
	end)

	test("the strip and the touch hand go to the patient's own Send prompt", function()
		local fn = body(text, "local function sendSteer(")
		expect(has(fn, "steer.Beam = true")).toBe(true)
		expect(has(fn, 'steer.Hand = "Tap"')).toBe(true)
	end)

	test("in the tutorial's first step, after it, and for the first patients once it is done or skipped", function()
		local steer = string.sub(text, (string.find(text, "Guide.setSteer(function(plot: Instance): any", 1, true)))
		expect(has(steer, "return sendSteer(waiting)")).toBe(true) -- WELCOME / PATIENT
		local times = 0
		for _ in string.gmatch(steer, "return waitingSteer%(plot%)") do
			times += 1
		end
		expect(times).toBe(2) -- not in the tutorial (the Guide's first cures), and EXAMINE / TREAT / MORE
	end)

	test("a waiting patient is one with State Waiting, no bay, and not a 🚑/🚁 one", function()
		local fn = body(text, "local function waitingPatient(")
		expect(has(fn, 'child:GetAttribute("State") == "Waiting"')).toBe(true)
		expect(has(fn, 'child:GetAttribute("Bay")')).toBe(true)
		expect(has(fn, 'child:GetAttribute("Urgent")')).toBe(true)
	end)
end)
