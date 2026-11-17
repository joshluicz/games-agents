--!strict
-- The first-session tutorial's rules (docs/plan/2026-11-16-first-session-design.md §B; the Real Clinic design
-- docs/plan/2026-11-17-real-clinic-design.md §13). Pure: no Roblox services and no requires, so Lune can test it.
-- Server/Tutorial owns the live step and saves it as Data.Tutorial; the client only reads it (Snapshot.Tutorial) to
-- show the card, the pointer and the HUD.
--
-- The steps (Data.Tutorial; the numbers are saved, so they never change). Each one moves on only on a real server
-- event. The Real Clinic (Update 2) re-used steps 3-5, which never survive a rejoin (`resume`), for its visit:
--   1 WELCOME   the camera sweep                               the TutorialAck remote (the client acks when the
--                                                             sweep ends; the server moves on by itself if no
--                                                             ack comes). The first patient walks in meanwhile
--   2 PATIENT   card 1 "WELCOME, DOCTOR!"                      1 s after the first patient sits down in a bay
--   3 EXAMINE   card 2 "PATIENT IN BAY 1" (tap Examine), and   the exam reveals its case (anyone's exam)
--               card 3 "PICK THE GLOWING TOOL" while the exam card is up
--   4 TREAT     card 4 "GET THE PLASTER" (the supply shelf or  the patient's plan is done (anyone's treatment)
--               the dispensary), then card 5 "TREAT YOUR
--               PATIENT" once you carry it (or its game is up)
--   5 REST      card 6 "WELL DONE, DOCTOR!" (you treated your  the treatment pays out (Cure.resolve: at once at
--               first patient)                                 Lv 1; after its ward rest from Lv 2)
--   6 MORE      card 7 "TREAT 3 MORE ○○○"                      3 more treated patients on the owner's clinic
--   7 SHOP      card 7 "UPGRADE YOUR CLINIC"                   any purchase (a one-time cash top-up if needed)
--   8 BOOK      the finale (card 7 stays the tab)              5 s later
--   9 DONE      the tutorial is over (the save migration marks every player with a cure as DONE)
-- A later event can skip a step that no longer makes sense (a friend examines or treats the patient first, say),
-- but nothing ever moves a step back except `resume` after a rejoin and "Replay".
--
-- Look overhaul (docs/plan/2026-11-17-look-overhaul-build-plan.md §B9; memory-20261117-002):
--   · "Skip" (any active step -> DONE): the ⏭️ Skip chip and the ⚙️ row, behind a confirm (the TutorialSkip remote).
--   · "Replay" (DONE -> PATIENT): the ⚙️ "🔁 Replay tutorial" row (the TutorialReplay remote). THE ONE DELIBERATE
--     EXCEPTION to "steps only go forward": Joshua asked for the tutorial to be replayable "in case they
--     accidentally skipped it". A replay starts at PATIENT (no sweep) and never gives a second gift (giftDue).
--   · The server's 9 steps show as the 7 cards of the design's §13 (Tutorial.card). The onboarding funnel logs
--     the card a step change shows, and the Shop as its 8th stage (Tutorial.funnelStep, FUNNEL_NAMES).
--
--   Tutorial.isStep(value): boolean        an integer from WELCOME to DONE
--   Tutorial.migrate(saved, cured): number a save's step: a valid saved step is kept; a save without one is
--                                          DONE when it has any cure (an existing player), else WELCOME
--   Tutorial.active(step): boolean         WELCOME..BOOK (not loaded, unknown or DONE = false)
--   Tutorial.isDone(step): boolean         DONE (a number at or past it)
--   Tutorial.calm(step): boolean           patience never runs out: steps 1-6
--   Tutorial.guests(step): boolean         regulars and Today's Visitor may come (only once DONE)
--   Tutorial.resume(step): number          after a rejoin: steps 3-5 needed the patient that left with you, so
--                                          they start again at PATIENT
--   Tutorial.advance(step, event, ctx?)    the next step for a server event (Event); unchanged if it doesn't
--                                          apply. ctx.Cures (Cured: cures counted in step MORE, this one included)
--   Tutorial.spawnPlan(step, plotEmpty, secondSpawned): Plan   who Patients may send next (see Plan)
--   Tutorial.queueCap(step): number?       at most this many waiting (steps 1-6: one at a time), nil = normal
--   Tutorial.cheapest(prices): number?     the lowest of the next upgrade prices (nil entries skipped)
--   Tutorial.topUp(cash, cheapest): number the one-time gift that makes the cheapest upgrade affordable
--   Tutorial.card(step, playing?, carrying?): number?
--                                          the card (1..CARDS): WELCOME/PATIENT 1 · EXAMINE 2 (3 while an "Exam"
--                                          session is up) · TREAT 4 (5 once you carry what it needs, or while a
--                                          "Treat" session is up; a "Dispense" one is still fetching: 4) · REST 6
--                                          · MORE, SHOP, BOOK 7 · else nil. `playing` = the open session's Kind
--                                          ("Exam" | "Treat" | "Dispense"), true = a game of that step's own kind
--   Tutorial.funnelStep(step): number?     the onboarding funnel's stage: the card, and FUNNEL_SHOP for SHOP/BOOK
--   Tutorial.nudge(step): boolean          a walking step (EXAMINE, TREAT, MORE): the idle "Psst!" nudge may show
--   Tutorial.canSkip(step): boolean        = active(step)
--   Tutorial.canReplay(step, hasPlot): boolean   done, and the caller owns a clinic
--   Tutorial.giftDue(step, gifted): boolean      entering `step` gives the top-up: SHOP, and never given before

local Tutorial = {}

Tutorial.WELCOME = 1
Tutorial.PATIENT = 2
Tutorial.EXAMINE = 3
Tutorial.TREAT = 4
Tutorial.REST = 5
Tutorial.MORE = 6
Tutorial.SHOP = 7
Tutorial.BOOK = 8
Tutorial.DONE = 9

Tutorial.MORE_CURES = 3 -- step MORE: patients to treat after the first one (design §13: "treat 3 more")
Tutorial.ARRIVED_SECONDS = 1 -- step PATIENT: how long the first patient sits in its bay before step EXAMINE
Tutorial.WELCOME_SECONDS = 4 -- step WELCOME: the old welcome card's time (UI/Tutorial acks when the sweep ends)
-- The server moves on by itself if no ack comes: only so a broken client can never stall the tutorial. Generous,
-- so a slow phone still loading when its clinic is assigned gets its title card, sweep and welcome card first.
Tutorial.WELCOME_FALLBACK_SECONDS = 30
Tutorial.BOOK_SECONDS = 5 -- step BOOK: then DONE

-- The cards the player sees (the "TUTORIAL n/7" tab; design §13), and their names for the onboarding funnel, which
-- also logs the Shop (FUNNEL_SHOP) as its own stage after card 7.
Tutorial.CARDS = 7
Tutorial.CARD_NAMES = table.freeze({ "Welcome", "Examine", "Tool", "Fetch", "Treat", "Treated", "More" })
Tutorial.FUNNEL_SHOP = 8
Tutorial.FUNNEL_NAMES = table.freeze({ "Welcome", "Examine", "Tool", "Fetch", "Treat", "Treated", "More", "Upgrade" })

-- "Arrived": the first patient sat down in a bay · "Examined": an exam revealed a case at the owner's clinic ·
-- "Treated": a patient's plan there is done · "Cured": its treatment paid out (Cure.resolve; the id is internal)
export type Event = "Ack" | "Arrived" | "Examined" | "Treated" | "Cured" | "Purchased" | "BookShown" | "Skip" | "Replay"
export type Ctx = { Cures: number? }
-- "Wait": nobody new · "First": the easy first patient (Patients picks a Lv 1, one-step case: a cough, from the
-- dispensary) · "Second": one whose step comes from another place (a cut knee: the supply shelf), so card 4 shows
-- both · "Any": the usual pool but no regulars or Today's Visitor · "Normal": the game as it is for everyone else
export type Plan = "Wait" | "First" | "Second" | "Any" | "Normal"

function Tutorial.isStep(value: any): boolean
	return type(value) == "number"
		and value == value
		and value % 1 == 0
		and value >= Tutorial.WELCOME
		and value <= Tutorial.DONE
end

function Tutorial.migrate(saved: any, cured: number): number
	if Tutorial.isStep(saved) then
		return saved
	end
	return if cured > 0 then Tutorial.DONE else Tutorial.WELCOME
end

function Tutorial.active(step: any): boolean
	return Tutorial.isStep(step) and step < Tutorial.DONE
end

function Tutorial.isDone(step: any): boolean
	return type(step) == "number" and step >= Tutorial.DONE
end

function Tutorial.calm(step: any): boolean
	return Tutorial.active(step) and step <= Tutorial.MORE
end

function Tutorial.guests(step: any): boolean
	return not Tutorial.active(step)
end

function Tutorial.resume(step: number): number
	if step >= Tutorial.EXAMINE and step <= Tutorial.REST then
		return Tutorial.PATIENT
	end
	return step
end

function Tutorial.advance(step: number, event: Event, ctx: Ctx?): number
	if event == "Replay" then
		-- The one deliberate step back (see the header): only from DONE, to the first patient (no welcome sweep).
		return if Tutorial.isStep(step) and Tutorial.isDone(step) then Tutorial.PATIENT else step
	end
	if not Tutorial.active(step) then
		return step
	end
	if event == "Skip" then
		return Tutorial.DONE
	end
	if event == "Ack" then
		return if step == Tutorial.WELCOME then Tutorial.PATIENT else step
	elseif event == "Arrived" then
		return if step == Tutorial.PATIENT then Tutorial.EXAMINE else step
	elseif event == "Examined" then
		-- From card 1 too: the exam can come before the arrival's beat (or a friend examined it).
		return if step == Tutorial.PATIENT or step == Tutorial.EXAMINE then Tutorial.TREAT else step
	elseif event == "Treated" then
		return if step >= Tutorial.PATIENT and step <= Tutorial.TREAT then Tutorial.REST else step
	elseif event == "Cured" then
		if step >= Tutorial.PATIENT and step <= Tutorial.REST then
			return Tutorial.MORE
		elseif step == Tutorial.MORE then
			local cures = if ctx and type(ctx.Cures) == "number" then ctx.Cures else 0
			return if cures >= Tutorial.MORE_CURES then Tutorial.SHOP else step
		end
		return step
	elseif event == "Purchased" then
		return if step == Tutorial.SHOP then Tutorial.BOOK else step
	elseif event == "BookShown" then
		return if step == Tutorial.BOOK then Tutorial.DONE else step
	end
	return step
end

function Tutorial.spawnPlan(step: any, plotEmpty: boolean, secondSpawned: boolean): Plan
	if not Tutorial.active(step) then
		return "Normal"
	end
	if step <= Tutorial.TREAT then
		-- WELCOME too (look overhaul): the first patient hops in during the camera sweep, so card 1 has its patient.
		-- Only the first patient: one more if it's gone (it can't run out of patience, but a broken one is removed).
		return if plotEmpty then "First" else "Wait"
	elseif step == Tutorial.REST then
		return if secondSpawned then "Wait" else "Second"
	elseif step == Tutorial.MORE then
		return if secondSpawned then "Any" else "Second"
	end
	return "Any"
end

function Tutorial.queueCap(step: any): number?
	if Tutorial.active(step) and step <= Tutorial.MORE then
		return 1
	end
	return nil
end

function Tutorial.cheapest(prices: { number? }): number?
	local best: number? = nil
	for _, price in prices do
		if type(price) == "number" and (best == nil or price < best) then
			best = price
		end
	end
	return best
end

function Tutorial.topUp(cash: number, cheapest: number?): number
	if cheapest == nil or cash >= cheapest then
		return 0
	end
	return math.ceil(cheapest - cash)
end

function Tutorial.card(step: any, playing: any, carrying: boolean?): number?
	if not Tutorial.active(step) then
		return nil
	end
	if step <= Tutorial.PATIENT then
		return 1
	elseif step == Tutorial.EXAMINE then
		return if playing == true or playing == "Exam" then 3 else 2
	elseif step == Tutorial.TREAT then
		return if carrying == true or playing == true or playing == "Treat" then 5 else 4
	elseif step == Tutorial.REST then
		return 6
	end
	return 7
end

function Tutorial.funnelStep(step: any): number?
	if Tutorial.active(step) and step >= Tutorial.SHOP then
		return Tutorial.FUNNEL_SHOP
	end
	return Tutorial.card(step)
end

function Tutorial.nudge(step: any): boolean
	return step == Tutorial.EXAMINE or step == Tutorial.TREAT or step == Tutorial.MORE
end

function Tutorial.canSkip(step: any): boolean
	return Tutorial.active(step)
end

function Tutorial.canReplay(step: any, hasPlot: boolean): boolean
	return Tutorial.isStep(step) and Tutorial.isDone(step) and hasPlot == true
end

function Tutorial.giftDue(step: any, gifted: boolean): boolean
	return step == Tutorial.SHOP and gifted ~= true
end

return Tutorial
