--!strict
-- Routing: the player sends each waiting patient to the right place (simple-start design §2; memory-20261117-006,
-- Joshua: "you do it ... perhaps its just sending them to the correct ward or place for treatment"). Pure: no Roblox
-- services and no requires, so Lune tests it (tests/Routing.spec). Inputs are never changed.
-- The server decides everything here (Server/Patients: the Send prompt, the SendPatient remote and the Receptionist's
-- own sending); the client only draws the prompt and the two-button card (UI/SendCard).
--
-- The places are the exam bays' two kinds (Logic/Building.BAYS[n].Kind): "Exam" (a bay with a bed) and "XRay" (the
-- X-ray bay, Lv 3). A case whose exam tool is the X-ray goes to the X-ray; every other case to an exam bay.
--
--   Routing.KINDS = { "Exam", "XRay" }           the two choices, in the card's order
--   Routing.CHOICE_LEVEL = 3                     the level the second kind of place opens at (the X-ray bay)
--   Routing.RECEPTION_WAIT = 6 · RECEPTION_GAP = 2   a Receptionist sends a patient that has sat this long, and the
--                                                next one no sooner than the gap after
--   Routing.TEXT                                 every word the player sees (the prompt, the card, the toasts)
--   Routing.isChoice(value): boolean             "Exam" or "XRay", nothing else (the remote's argument)
--   Routing.kindFor(tool): "Exam" | "XRay"       the place a case with that exam tool needs
--   Routing.waiting(phase, bay, urgent): boolean a patient the player may send: settled in the waiting room ("Seated":
--                                                on a seat, or standing with every seat taken), with no bay yet, and
--                                                not a 🚑/🚁 one (those go straight to a bay)
--   Routing.auto(urgent, sent): boolean          a patient the clinic's tick may call to a bay by itself: a 🚑/🚁 one,
--                                                or one that was sent before (its bay closed under it in a rebuild).
--                                                Never a walk-in nobody has sent yet
--   Routing.needsChoice(level, bays): boolean    the Send prompt opens the two-button card: Lv 3+ and both kinds of
--                                                place are open (bays = { { Kind } }, the open bays). Otherwise one
--                                                press sends it
--   Routing.pickBay(bays, kind, from?): string?  the free bay of that kind nearest to `from` ({ X, Z }, the patient);
--                                                a tie, or no `from`, goes to the first in the list's order (so the
--                                                tutorial's patient takes bay 1). bays = { { Id, Kind, X, Z, Free } }.
--                                                nil = no free bay fits
--   Routing.check(choice, kind): (boolean, string?)   true when the pick is right; a wrong pick is (false, the gentle
--                                                correction); junk is (false, nil)
--   Routing.receptionistReady(seatedSince, now, lastSent, wait?, gap?): boolean
--                                                a Receptionist may send this patient now

local Routing = {}

Routing.EXAM = "Exam"
Routing.XRAY = "XRay"
Routing.KINDS = table.freeze({ "Exam", "XRay" })
Routing.XRAY_TOOL = "XRay" -- Data/Tools.XRay (Logic/Visit.XRAY): the tool that is a machine
Routing.CHOICE_LEVEL = 3
Routing.RECEPTION_WAIT = 6
Routing.RECEPTION_GAP = 2

-- Short and kind (6 words or fewer). The card's title is words only; emojis only on its two choices.
Routing.TEXT = table.freeze({
	Action = "Send",
	Title = "Where should it go?",
	Exam = "🩺 Exam bay",
	XRay = "📸 X-ray",
	Busy = "All bays are busy!",
	NeedsXRay = "That one needs the X-ray!",
	NeedsExam = "That one needs an exam bay!",
})

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Routing.isChoice(value: any): boolean
	return value == Routing.EXAM or value == Routing.XRAY
end

function Routing.kindFor(tool: any): string
	return if tool == Routing.XRAY_TOOL then Routing.XRAY else Routing.EXAM
end

function Routing.waiting(phase: any, bay: any, urgent: any): boolean
	return phase == "Seated" and (bay == nil or bay == "") and (urgent == nil or urgent == "" or urgent == false)
end

function Routing.auto(urgent: any, sent: any): boolean
	return sent == true or urgent == true or (type(urgent) == "string" and urgent ~= "")
end

function Routing.needsChoice(level: any, bays: any): boolean
	if not finite(level) or math.floor(level) < Routing.CHOICE_LEVEL or type(bays) ~= "table" then
		return false
	end
	local exam, xray = false, false
	for _, bay in bays do
		if type(bay) == "table" then
			if bay.Kind == Routing.XRAY then
				xray = true
			elseif bay.Kind == Routing.EXAM then
				exam = true
			end
		end
	end
	return exam and xray
end

function Routing.pickBay(bays: any, kind: any, from: any): string?
	if type(bays) ~= "table" or not Routing.isChoice(kind) then
		return nil
	end
	local measured = type(from) == "table" and finite(from.X) and finite(from.Z)
	local best: string? = nil
	local bestDistance = math.huge
	for _, bay in bays do
		if type(bay) == "table" and type(bay.Id) == "string" and bay.Kind == kind and bay.Free == true then
			if not measured then
				return bay.Id -- the first in order
			end
			local distance = if finite(bay.X) and finite(bay.Z)
				then (bay.X - from.X) ^ 2 + (bay.Z - from.Z) ^ 2
				else math.huge
			if best == nil or distance < bestDistance then
				best = bay.Id
				bestDistance = distance
			end
		end
	end
	return best
end

function Routing.check(choice: any, kind: any): (boolean, string?)
	if not Routing.isChoice(choice) or not Routing.isChoice(kind) then
		return false, nil
	end
	if choice == kind then
		return true, nil
	end
	return false, if kind == Routing.XRAY then Routing.TEXT.NeedsXRay else Routing.TEXT.NeedsExam
end

function Routing.receptionistReady(seatedSince: any, now: any, lastSent: any, wait: any?, gap: any?): boolean
	if not finite(seatedSince) or not finite(now) then
		return false
	end
	local sat = if finite(wait) then math.max(wait :: number, 0) else Routing.RECEPTION_WAIT
	local between = if finite(gap) then math.max(gap :: number, 0) else Routing.RECEPTION_GAP
	if now - seatedSince < sat then
		return false
	end
	return not finite(lastSent) or now - lastSent >= between
end

return Routing
