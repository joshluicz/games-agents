--!strict
-- The first-session tutorial's rules (docs/plan/2026-11-16-first-session-design.md §B). Pure: no Roblox
-- services and no requires, so Lune can test it. Server/Tutorial owns the live step and saves it as
-- Data.Tutorial; the client only reads it (Snapshot.Tutorial) to show the card, the pointer and the HUD.
--
-- The steps (Data.Tutorial). Each one moves on only on a real server event:
--   1 WELCOME   "👋 Welcome to your clinic, Doctor!"          the TutorialAck remote (tap, or 4 s on the client;
--                                                             the server moves on by itself if no ack comes)
--   2 PATIENT   "🤧 A patient! The bubble shows what's wrong."  2 s after the first patient reaches the Counter
--   3 MAKE      "🧪 Hold at the potion table!"                 the owner makes what that patient needs
--   4 TREAT     "🏥 Take it to the Counter. Treat!"            the patient is treated
--   5 REST      "🛏️ Resting… Cured! 🎉"                       the cure lands
--   6 MORE      "💪 Cure 2 more! (n/2)"                        2 more cures on the owner's clinic
--   7 SHOP      "🛒 Spend 💰 in the Shop!"                     any purchase (a one-time cash top-up if needed)
--   8 BOOK      "📖 Collect every creature in your Book!"      5 s later
--   9 DONE      the tutorial is over (the save migration marks every player with a cure as DONE)
-- A later event can skip a step that no longer makes sense (a friend treats the patient during step 3, say),
-- but nothing ever moves a step back except `resume` after a rejoin.
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
--   Tutorial.advance(step, event, ctx?)    the next step for a server event (see EVENTS); unchanged if it
--                                          doesn't apply. ctx.Right (Made: the item the front patient needs),
--                                          ctx.Cures (Cured: cures counted in step MORE, this one included)
--   Tutorial.spawnPlan(step, plotEmpty, secondSpawned): Plan   who Patients may send next (see below)
--   Tutorial.queueCap(step): number?       at most this many in line (steps 2-6: one at a time), nil = normal
--   Tutorial.cheapest(prices): number?     the lowest of the next upgrade prices (nil entries skipped)
--   Tutorial.topUp(cash, cheapest): number the one-time gift that makes the cheapest upgrade affordable

local Tutorial = {}

Tutorial.WELCOME = 1
Tutorial.PATIENT = 2
Tutorial.MAKE = 3
Tutorial.TREAT = 4
Tutorial.REST = 5
Tutorial.MORE = 6
Tutorial.SHOP = 7
Tutorial.BOOK = 8
Tutorial.DONE = 9

Tutorial.MORE_CURES = 2 -- step MORE: cures to go after the first one
Tutorial.ARRIVED_SECONDS = 2 -- step PATIENT: how long the first patient stands at the Counter before step MAKE
Tutorial.WELCOME_SECONDS = 4 -- step WELCOME: the client acks after this (or a tap)
-- The server moves on by itself if no ack comes: only so a broken client can never stall the tutorial. Generous,
-- so a slow phone still loading when its clinic is assigned gets its title card, sweep and welcome card first.
Tutorial.WELCOME_FALLBACK_SECONDS = 30
Tutorial.BOOK_SECONDS = 5 -- step BOOK: then DONE

export type Event = "Ack" | "Arrived" | "Made" | "Treated" | "Cured" | "Purchased" | "BookShown"
export type Ctx = { Right: boolean?, Cures: number? }
-- "Wait": nobody new · "First": the easy first patient (a Starter patient needing the 🧪 Remedy) ·
-- "Second": a Starter patient needing 🩹, to show there's more than one station · "Any": the usual pool but no
-- regulars or Today's Visitor · "Normal": the game as it is for everyone else
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
	if step >= Tutorial.MAKE and step <= Tutorial.REST then
		return Tutorial.PATIENT
	end
	return step
end

function Tutorial.advance(step: number, event: Event, ctx: Ctx?): number
	if not Tutorial.active(step) then
		return step
	end
	if event == "Ack" then
		return if step == Tutorial.WELCOME then Tutorial.PATIENT else step
	elseif event == "Arrived" then
		return if step == Tutorial.PATIENT then Tutorial.MAKE else step
	elseif event == "Made" then
		return if step == Tutorial.MAKE and ctx ~= nil and ctx.Right == true then Tutorial.TREAT else step
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
	if step == Tutorial.WELCOME then
		return "Wait"
	elseif step <= Tutorial.TREAT then
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

return Tutorial
