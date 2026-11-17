--!strict
-- The visit's mini-games (depth-update design §1; Real Clinic design §5, §7 and §9, build plan Task 7 and contract
-- C5). Client only. OWNER: T2; Progression v2: T8; the Real Clinic: Task 7.
--   init(ctx)   listens for the bus "TreatStart" (Types.TreatSession, forwarded from the server by Main.client)
--   stage(): GuiObject?   the current game's stage, for UI/Tutorial's touch hand (nil when no game is up)
--   isOpen(): boolean     a card is open now (UI/Celebrate waits for it)
--
-- The card is THE modal template (UI/Modal, look build plan §B8): Layer Panel, HudMode "Game" (the HUD keeps the
-- wallet and the Now card, hides the rails and Status), the navy header with the game's icon and name and the 🔥
-- combo chip where the ✖ would be, NO ✖ and a dim that neither closes it nor takes a tap (the thumbstick still works
-- under it); ButtonB never closes it. Its ScreenGui sits over panels and pop-ups, under the treat pops and toasts.
-- The games' own colours stay inside the card (they're the game). Text never under 18 px (Kit.textLimit). While the
-- first-session tutorial runs, no time bar drains (Pure.drainBar). Gamepad prompts show the pad's own button
-- picture (UserInputService:GetImageForKeyCode: ✕ on PlayStation), never "🅰️". The card's size comes from
-- Pure.CARD, so Pure.pickLayout can show the choices fit a phone (Review Focus 5: 568 x 320, targets >= 44 px).
--
-- A visit is three kinds of card (TreatSession.Kind; Types has the session shapes):
--   Exam      at a bay. Games = { "Pick", <the tool's game> }: pick the right tool out of session.Tools (the Pick
--             engine; session.Answer glows while session.Glow: a player's first exams, and Simple mode), then play
--             that tool's game. The server's answer reveals the case for 1.2 s: "🩺 It's a cough!" with the plan's
--             icons. The step chips never show the right tool before it is picked.
--   Treat     at a bay, giving supplies: one game per item (Data/Items Game), as before.
--   Dispense  at the dispensary. With several session.Options the card first asks which medicine to make (any is
--             right: each one is needed); then Pick finds its bottle among Config.Dispensary.Bottles (the right one
--             and others that never share its icon when the shelf has enough: Pure.bottles), then Dose fills the
--             measuring cup (the Pour engine) in the medicine's colour. The report carries the Choice.
-- Every GameId is a look (Pure.LOOKS: icon, words, sound, and the engine's skin) on one of five engines
-- (Logic/MiniGame.ENGINE; Pure.dispatch picks the routine):
--   Pour   hold, let go in the green ⭐ band       score = the fill when let go (0..1). Skins: the 🧪 bottle, the
--          🌡️ thermometer (Temp), the 🧊 ice pack (Ice) and the measuring cup (Dose)
--   Patch  spots pop up, tap each one             score = spots tapped in time. Skins: 🩹 sore spots (Plaster),
--          💓 glowing chest spots (Listen), 🔍 sore spots to find (Look)
--   Scrub  bubbles pop up round the creature       score = bubbles popped in time (🛁 Bath)
--   Cool   tap on the beat, Blows times            score = good beats (a beat is good within Window seconds of
--          its middle, halfway through PulseSeconds; it glows lime then). Skins: "Ring" (a ring is biggest then:
--          ☕ Cocoa's steam, 🔦 Light's ring over the patient) and "Sweep" (a bar passes the middle: 📸 XRay's
--          scanner over the bone, 🧻 Bandage and 🦴 Cast wrapping)
--   Pick   tap the right one                       score = WRONG taps before the right one. A wrong tap shakes
--          its head ("Hmm, not that one!"), greys out and costs nothing but the tip: never a fail
-- Each game draws and is rated with its own tuning row (Logic/MiniGame.tuning: Config.MiniGame.Games[game]) via
-- Logic/MiniGame.rate(game, score, ctx.Config): a huge outlined PERFECT! / GOOD! / OK! pops and the 🔥 combo counter
-- climbs on a Perfect, holds on a Good and goes back to "Go!" on an OK (Logic/MiniGame.settle predicts it; at 0 it
-- rests at "Go!" in a soft warm colour, never a grey 0, so it never looks like losing; the server's own combo wins
-- when it answers).
-- Never a fail: OK still treats. Then TreatResult (Hud.ask(TreatResult, session.Session, ratings, choice)): its third
-- value is the TreatOutcome; the card shows the server's ratings and tip for a moment and closes.
-- Simple mode (session.Simple): one big tap per game, rated Good, no combo counter (a Pick's tap shows the right
-- tool or bottle; a Dispense card takes the first medicine without asking). A game id this client doesn't know plays
-- as one tap too (rated Good). Reduced motion (Kit.reducedMotion(), checked live): no wobble, bursts, drift or
-- overshoot; the fill, the rings and the sweep still move (they are the game), same rules.
-- Fairness: the report never goes sooner than MiniGame.minSeconds after TreatStart (so the server never rates a real
-- game all OK for being early), and the card closes by itself just before session.Timeout (the server has settled
-- the session as all OK by then). A new TreatStart replaces a running one. Nothing here decides anything: the
-- server checks the session, the time, the distance, the choice and the tip.
--
-- Progression v2 (build plan §B3 TreatSession/TreatOutcome, §C T8):
--   Auto   a game an ability made PERFECT (Golden Touch, Quick Plaster/Soap) sparkles for a moment ("✨ Magic
--          help!"), pops "✨ PERFECT!" and is skipped; the minimum report time counts only the games really played
--          (Pure.played, as the server's MiniGame.accept does).
--   Ease   🎯 Steady Hands (1..1.3) widens the Perfect windows of every tuning row: the Pour bands and Good slack,
--          the Cool windows, a little more time to patch and scrub (Pure.eased). The client draws and rates with it;
--          the server never checks it (it takes the client's ratings), so the two always agree. Expert Dispensing
--          (the Pharmacy2 unlock, session.Expert) widens the Dose band by Config.Dispensary.ExpertBand the same way
--          (Pure.widened).
--   Triage when the server's TreatOutcome has Triage (Lv 3+, no Receptionist), the card stays for "🔀 Which
--          floor?": a huge button per department (Data/Departments icon: 🛏️ Injury Ward, 😴 Rest Ward) over the
--          soft time bar (no digits). One tap asks Triage(session, dept): "✅ Right floor!" or "Oops, not this
--          floor!" (it goes the right way anyway). No tap: the bar empties and the patient goes by itself.
--          A HANDOVER session (TreatSession.Handover, Games {}: a handed-over medicine completed the plan of a
--          patient who stays) plays nothing: it reports at once, and the card opens only for this floor pick.
-- Bus events: listens "TreatStart" (session) · fires "MiniGameRated" (game, rating) as each game ends (the client's
-- own rating, for feel) · "TreatDone" (outcome, session) after the server's reply (session = the TreatStart payload,
-- with its Position) · "Sound" (name) for the hits: each look's Sound (Pour, Patch, Scrub, Blow, Listen, Beep, Shine,
-- Scan, Cold, Wrap, Pop, Found), plus Tick, Nope, Whoosh, Splash, Sparkle, Triage. The rating cues
-- (RateOK/RateGood/RatePerfect on MiniGameRated) and Tip/Combo (on TreatDone) are Feel/Sounds' own, so this file
-- never plays them (they would double).
-- The pure helpers between the PURE markers use no Roblox API, so a Lune harness can load that block on its own.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local MiniGame = require(Shared:WaitForChild("Logic"):WaitForChild("MiniGame"))
local Visit = require(Shared:WaitForChild("Logic"):WaitForChild("Visit"))
local TutorialLogic = require(Shared:WaitForChild("Logic"):WaitForChild("Tutorial"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Modal = require(script.Parent.Modal)
local Theme = require(script.Parent.Theme)

local MiniGames = {}

------------------------------------------------------------------------------------------------------------------
-- PURE:BEGIN  (no Roblox services, instances or requires in this block)
------------------------------------------------------------------------------------------------------------------

local Pure = {}

-- The engines this client can draw (Logic/MiniGame.ENGINE maps every GameId to one of them)
Pure.KNOWN = { Pour = true, Patch = true, Scrub = true, Cool = true, Pick = true }
Pure.MAX_GAMES = 6 -- a plan has at most 3; more than this is junk
-- TreatSession.Kind: Exam / Treat / Dispense (the Real Clinic)
Pure.KINDS = { Exam = true, Treat = true, Dispense = true }
-- The most choices a Pick shows: the exam card's 3 tools and the shelf's 4 bottles (Config.Dispensary.Bottles). Five
-- or more would not fit a phone's card at 44 px (Pure.pickLayout).
Pure.CHOICES_MAX = 4
Pure.TAP_MIN = 44 -- the smallest a tap target may be on any screen (Review Focus 5)
-- Progression v2: 🎯 Steady Hands widens the Perfect windows by up to 30% (TreatSession.Ease, 1..1.3; client only)
Pure.EASE_MAX = 1.3
Pure.TRIAGE_MAX = 3 -- floor buttons on the triage card (two today: 🛏️ Injury Ward and 😴 Rest Ward)
Pure.TRIAGE_SECONDS_MAX = 10

export type Session = {
	Session: number,
	PatientId: string,
	Items: { string }, -- one per game ("" when unknown; Exam and Dispense have none)
	Games: { string },
	Simple: boolean,
	Combo: number, -- a whole number >= 0
	Timeout: number?, -- seconds, nil when the payload had none
	-- Progression v2 (build plan §B3 TreatSession): defaults when the server sends none
	Kind: string, -- "Exam" | "Treat" | "Dispense"
	Auto: { boolean }, -- per game: an ability made it PERFECT already (shown with ✨ and skipped)
	Ease: number, -- 1..EASE_MAX: how much wider the Perfect windows are
	-- The Real Clinic (contract C5)
	Tools: { string }, -- Exam: the tools on the card (ToolIds, at most CHOICES_MAX, no repeats)
	Answer: string?, -- Exam: the right tool
	Glow: boolean, -- Exam: the right tool glows
	Options: { string }, -- Dispense: the medicines to choose from (ItemIds, at most CHOICES_MAX, no repeats)
	Case: string?, -- Treat: the case being treated
	Symptom: string, -- Exam: the patient's symptom bubble, as a clue ("" when the server sends none)
	Expert: boolean, -- Dispense: Expert Dispensing (the Pharmacy2 unlock) widens the Dose band
	Handover: boolean, -- Treat: no games (Games is {}): a handed-over medicine; only the ward pick may show
}
export type TriageOption = { Dept: string, Icon: string, Name: string }
export type TriageCard = { Options: { TriageOption }, Seconds: number }
export type Point = { X: number, Y: number }
export type Rect = { X: number, Y: number, W: number, H: number } -- px, top-left corner
-- What a game id looks like (colours by name: Tint is a Theme.Colors key, Liquid a "#RRGGBB" or "Bottle" for the
-- chosen medicine's own colour). The skin fields belong to the game's engine.
export type LookSpec = {
	Icon: string,
	Title: string,
	Hint: string,
	Sound: string, -- a Feel/Sounds cue: the game's hit
	Tint: string,
	Vessel: string?, -- Pour: "Bottle" | "Cup" | "Tube" | "Pack"
	Pourer: string?, -- Pour: what tips and pours (an emoji, or "Bottle" for the medicine's icon); nil = nothing pours
	Liquid: string?, -- Pour
	Mark: string?, -- Patch: what lands on a tapped spot
	Spot: string?, -- Patch: "Sore" | "Glow"
	Style: string?, -- Cool: "Ring" | "Sweep"
	Target: string?, -- Cool: what the beat lines up with ("Mug", "Face" or an emoji)
	Good: string?, -- Cool: a good beat's pip
	Miss: string?, -- Cool: any other beat's pip
}

local function finite(value: any): number?
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return nil
end
Pure.finite = finite

-- A list of distinct strings out of `raw` (at most `max`), or {} for junk.
local function strings(raw: any, max: number): { string }
	local out: { string } = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, value in ipairs(raw) do
		if #out >= max then
			break
		end
		if type(value) == "string" and value ~= "" and not table.find(out, value) then
			table.insert(out, value)
		end
	end
	return out
end

-- The TreatStart payload, checked and tidied, or nil when it can't be played (wrong shape, no games, too many).
function Pure.session(raw: any): Session?
	if type(raw) ~= "table" then
		return nil
	end
	local id = finite(raw.Session)
	local games = raw.Games
	if id == nil or type(games) ~= "table" then
		return nil
	end
	local count = #games
	-- (a handover has no games: it only carries the ward pick)
	local handover = raw.Handover == true and count == 0
	if (count < 1 and not handover) or count > Pure.MAX_GAMES then
		return nil
	end
	local list: { string } = {}
	local items: { string } = {}
	local rawItems = if type(raw.Items) == "table" then raw.Items else {}
	for index = 1, count do
		local gameId = games[index]
		if type(gameId) ~= "string" then
			return nil
		end
		list[index] = gameId
		local item = rawItems[index]
		items[index] = if type(item) == "string" then item else ""
	end
	local combo = finite(raw.Combo)
	local timeout = finite(raw.Timeout)
	local rawAuto = if type(raw.Auto) == "table" then raw.Auto else {}
	local auto: { boolean } = {}
	for index = 1, count do
		auto[index] = rawAuto[index] == true
	end
	return {
		Session = id,
		PatientId = if type(raw.PatientId) == "string" then raw.PatientId else "",
		Items = items,
		Games = list,
		Simple = raw.Simple == true,
		Combo = if combo then math.max(0, math.floor(combo)) else 0,
		Timeout = if timeout and timeout > 0 then timeout else nil,
		Kind = if type(raw.Kind) == "string" and Pure.KINDS[raw.Kind] then raw.Kind else "Treat",
		Auto = auto,
		Ease = math.clamp(finite(raw.Ease) or 1, 1, Pure.EASE_MAX),
		Tools = strings(raw.Tools, Pure.CHOICES_MAX),
		Answer = if type(raw.Answer) == "string" and raw.Answer ~= "" then raw.Answer else nil,
		Glow = raw.Glow == true,
		Options = strings(raw.Options, Pure.CHOICES_MAX),
		Case = if type(raw.Case) == "string" and raw.Case ~= "" then raw.Case else nil,
		Symptom = if type(raw.Symptom) == "string" and #raw.Symptom <= 60 then raw.Symptom else "",
		Expert = raw.Expert == true,
		Handover = handover,
	}
end

-- The games the player really plays (not made PERFECT by an ability): what the minimum report time counts, the
-- same way the server's MiniGame.accept counts it.
function Pure.played(games: { string }, auto: { boolean }?): { string }
	local out: { string } = {}
	for index, gameId in games do
		if not (type(auto) == "table" and auto[index] == true) then
			table.insert(out, gameId)
		end
	end
	return out
end

-- A game id's engine: what `engines` (Logic/MiniGame.ENGINE) says, or the id itself when it names an engine, or nil
-- (this client can't draw it: it plays as one tap).
function Pure.engine(gameId: any, engines: any): string?
	if type(gameId) ~= "string" then
		return nil
	end
	local engine = if type(engines) == "table" then rawget(engines, gameId) else nil
	if type(engine) == "string" and Pure.KNOWN[engine] then
		return engine
	end
	return if Pure.KNOWN[gameId] then gameId else nil
end

-- Which routine plays a game: its engine ("Pour", "Patch", "Scrub", "Cool", "Pick"), or "Tap" (one big tap) in
-- Simple mode or for a game this client can't draw.
function Pure.dispatch(gameId: any, engines: any, simple: boolean?): string
	local engine = Pure.engine(gameId, engines)
	if simple == true or engine == nil then
		return "Tap"
	end
	return engine
end

local function copyOf(value: any): { [any]: any }
	local out = {}
	if type(value) == "table" then
		for key, item in value do
			out[key] = item
		end
	end
	return out
end

-- The engine a tuning row is for: an engine's own row by its name, any other (a Games row) by its own fields: a Pour
-- row has a band, a Cool row beats, a Patch row spots and a Scrub row a bubble goal. nil = nothing to widen (a Games
-- row with none of them, like Pick's).
function Pure.rowEngine(name: any, row: any): string?
	if type(name) == "string" and Pure.KNOWN[name] then
		return name
	end
	if type(row) ~= "table" then
		return nil
	end
	if row.BandMin ~= nil or row.BandMax ~= nil or row.FillSeconds ~= nil then
		return "Pour"
	elseif row.Window ~= nil or row.Blows ~= nil or row.PulseSeconds ~= nil then
		return "Cool"
	elseif row.Spots ~= nil then
		return "Patch"
	elseif row.Perfect ~= nil then
		return "Scrub"
	end
	return nil
end

-- A Pour row's Perfect band, `k` times as wide round its middle (clamped to 0..1).
local function widenBand(row: any, k: number)
	local low, high = finite(row.BandMin) or 0.7, finite(row.BandMax) or 0.86
	local middle, half = (low + high) / 2, (high - low) / 2 * k
	row.BandMin = math.max(0, middle - half)
	row.BandMax = math.min(1, middle + half)
end

-- One tuning row with its windows widened by `k` (a new table).
local function easeRow(row: any, engine: string?, k: number): any
	local out = copyOf(row)
	if engine == "Pour" then
		widenBand(out, k)
		out.GoodSlack = (finite(out.GoodSlack) or 0.12) * k
	elseif engine == "Cool" then
		out.Window = (finite(out.Window) or 0.3) * k
	elseif engine == "Patch" then
		out.Seconds = (finite(out.Seconds) or 4.5) * k
	elseif engine == "Scrub" then
		out.Seconds = (finite(out.Seconds) or 4) * k
	end
	return out
end

-- Config.MiniGame with the Perfect windows widened by `ease` (🎯 Steady Hands, 1..EASE_MAX), in the engines' own
-- rows and in every Games row (Pure.rowEngine says which engine a row is for): the Pour bands (round their middle)
-- and Good slack, the Cool windows, and a little more time to patch and to scrub. New tables (Config is frozen).
-- The client draws and rates with it; the server takes the client's ratings, so the two always agree. ease 1 (or
-- junk) is the plain settings.
function Pure.eased(mini: any, ease: number?): any
	local out = copyOf(mini)
	local k = math.clamp(finite(ease) or 1, 1, Pure.EASE_MAX)
	if k <= 1 then
		return out
	end
	for _, engine in { "Pour", "Cool", "Patch", "Scrub" } do
		out[engine] = easeRow(out[engine], engine, k)
	end
	if type(out.Games) == "table" then
		local games = {}
		for name, row in out.Games do
			games[name] = easeRow(row, Pure.rowEngine(name, row), k)
		end
		out.Games = games
	end
	return out
end

-- Config.MiniGame with one game's Perfect band `factor` times as wide round its middle (a new table; its Good slack
-- is kept): Expert Dispensing widens the Dose band by Config.Dispensary.ExpertBand. A factor of 1 or less, junk, or
-- a game with no band leaves the settings as they are.
function Pure.widened(mini: any, gameId: string, factor: number?): any
	local out = copyOf(mini)
	local k = finite(factor) or 1
	local games = if type(out.Games) == "table" then out.Games else nil
	local row = if games then games[gameId] else nil
	if k <= 1 or type(row) ~= "table" or Pure.rowEngine(gameId, row) ~= "Pour" then
		return out
	end
	local copy = copyOf(games)
	local wide = copyOf(row)
	widenBand(wide, k)
	copy[gameId] = wide
	out.Games = copy
	return out
end

-- The triage card from TreatOutcome.Triage ({ Options: { DeptId }, Seconds }): a big floor button per known
-- department (Data/Departments: its icon, like the patient's badge chip), at most TRIAGE_MAX, no repeats, and the
-- soft bar's length. nil when there's nothing to pick (junk, fewer than two floors, no time).
function Pure.triage(raw: any, departments: any): TriageCard?
	if type(raw) ~= "table" or type(raw.Options) ~= "table" or type(departments) ~= "table" then
		return nil
	end
	local options: { TriageOption } = {}
	local seen: { [string]: boolean } = {}
	for _, dept in raw.Options do
		if #options >= Pure.TRIAGE_MAX then
			break
		end
		local row = if type(dept) == "string" then rawget(departments, dept) else nil
		if type(row) == "table" and not seen[dept] then
			seen[dept] = true
			table.insert(options, {
				Dept = dept,
				Icon = if type(row.Icon) == "string" then row.Icon else "❓",
				Name = if type(row.Name) == "string" then row.Name else dept,
			})
		end
	end
	local seconds = finite(raw.Seconds)
	if #options < 2 or seconds == nil or seconds <= 0 then
		return nil
	end
	return { Options = options, Seconds = math.min(seconds, Pure.TRIAGE_SECONDS_MAX) }
end

-- The triage card's soft bar: 1 with all the time left, 0 when it's gone (never digits).
function Pure.triageBar(elapsed: number, seconds: number): number
	local total = finite(seconds) or 0
	if total <= 0 then
		return 0
	end
	return math.clamp(1 - (finite(elapsed) or 0) / total, 0, 1)
end

-- What the server's Triage answer means: "Right" (✅ Right floor!), "Wrong" ("Oops, not this floor!": it still goes
-- the right way, never a fail) or "Quiet" (no answer, refused or too late: the patient just goes by itself). A
-- payload { Right = boolean } wins; else the server's words; else ok.
function Pure.triageResult(ok: any, message: any, payload: any): string
	if type(payload) == "table" and type(payload.Right) == "boolean" then
		return if payload.Right then "Right" else "Wrong"
	end
	local text = if type(message) == "string" then string.lower(message) else ""
	if string.find(text, "oops", 1, true) and string.find(text, "floor", 1, true) then
		return "Wrong"
	end
	return if ok == true then "Right" else "Quiet"
end
Pure.TRIAGE_TEXT = {
	Right = { Icon = "✅", Text = "Right floor!" },
	Wrong = { Icon = "🙃", Text = "Oops, not this floor!" },
}

-- Pour: how full the bottle is after holding for `held` seconds (0..1). Same defaults as Logic/MiniGame.
function Pure.fill(held: number, fillSeconds: number?): number
	local seconds = math.max(finite(fillSeconds) or 2.4, 0.1)
	return math.clamp((finite(held) or 0) / seconds, 0, 1)
end

-- Pour: the bands to draw on the bottle: the Perfect band (lo..hi) and the Good band around it, clamped to 0..1.
function Pure.bands(pour: any): (number, number, number, number)
	local p = if type(pour) == "table" then pour else {}
	local lo = math.clamp(finite(p.BandMin) or 0.7, 0, 1)
	local hi = math.clamp(finite(p.BandMax) or 0.86, lo, 1)
	local slack = math.max(finite(p.GoodSlack) or 0.12, 0)
	return lo, hi, math.max(lo - slack, 0), math.min(hi + slack, 1)
end

-- Cool: the steam ring's size (minSize..1) `t` seconds into a pulse: it grows, is biggest halfway, then shrinks.
function Pure.ring(t: number, pulse: number?, minSize: number?): number
	local seconds = math.max(finite(pulse) or 1.2, 0.1)
	local phase = math.clamp((finite(t) or 0) / seconds, 0, 1)
	local low = math.clamp(finite(minSize) or 0.3, 0, 1)
	return low + (1 - low) * math.sin(math.pi * phase)
end

-- Cool: a blow `t` seconds into a pulse is good within `window` seconds of the biggest moment (halfway).
function Pure.goodBlow(t: number, pulse: number?, window: number?): boolean
	local seconds = math.max(finite(pulse) or 1.2, 0.1)
	local at = finite(t)
	if at == nil or at < 0 or at > seconds then
		return false
	end
	-- Both edges count (the tiny epsilon keeps float rounding from moving them).
	return math.abs(at - seconds / 2) <= math.max(finite(window) or 0.3, 0) + 1e-9
end

-- `count` points inside box { x0, y0, x1, y1 } (0..1), each at least `gap` from the others and from `avoid` when the
-- box has room; otherwise, after `tries` random picks, the roomiest one. r01() returns 0..1 (a Random, in the game).
function Pure.scatter(
	count: number,
	box: { number },
	gap: number,
	r01: () -> number,
	avoid: { Point }?,
	tries: number?
): { Point }
	local x0, y0, x1, y1 = box[1], box[2], box[3], box[4]
	local taken: { Point } = {}
	for _, point in avoid or {} do
		table.insert(taken, point)
	end
	local out: { Point } = {}
	for _ = 1, math.max(0, math.floor(finite(count) or 0)) do
		local best: Point = { X = (x0 + x1) / 2, Y = (y0 + y1) / 2 }
		local bestRoom = -1
		for _ = 1, math.max(1, math.floor(finite(tries) or 40)) do
			local point = { X = x0 + (x1 - x0) * r01(), Y = y0 + (y1 - y0) * r01() }
			local room = math.huge
			for _, other in taken do
				room = math.min(room, math.sqrt((point.X - other.X) ^ 2 + (point.Y - other.Y) ^ 2))
			end
			if room > bestRoom then
				best, bestRoom = point, room
			end
			if room >= gap then
				break
			end
		end
		table.insert(taken, best)
		table.insert(out, best)
	end
	return out
end

-- Scrub: a random free slot in 1..count (busy[i] == true is taken), or nil when every slot is busy.
function Pure.freeSlot(count: number, busy: { [number]: boolean }, r01: () -> number): number?
	local free: { number } = {}
	for index = 1, math.floor(finite(count) or 0) do
		if busy[index] ~= true then
			table.insert(free, index)
		end
	end
	if #free == 0 then
		return nil
	end
	return free[math.clamp(math.floor(r01() * #free) + 1, 1, #free)]
end

-- How long to wait before reporting so the report never comes sooner than `minimum` (+ margin) after the start.
function Pure.holdBack(elapsed: number, minimum: number, margin: number?): number
	return math.max(0, (finite(minimum) or 0) + (finite(margin) or 0) - (finite(elapsed) or 0))
end

-- The combo chip's multiplier tag: "×1.2", "×2" above 1, "" otherwise.
function Pure.multText(multiplier: number): string
	local m = finite(multiplier) or 1
	if m <= 1 then
		return ""
	end
	return "×" .. (string.gsub(string.format("%.1f", m), "%.0$", ""))
end

-- The draining time bar's share, or nil to hide it: while the first-session tutorial runs no clock ever runs down
-- (look build plan §B8; the game still ends on time, and OK still treats).
function Pure.drainBar(share: any, tutorialActive: boolean): number?
	if tutorialActive then
		return nil
	end
	return math.clamp(finite(share) or 0, 0, 1)
end

-- Cool, "Sweep" skin: where the bar is along its track `t` seconds into a beat (0 at the start, 1 at the end). The
-- middle (0.5) is the beat's biggest moment, so a tap is good while the bar is within sweepZone of the middle.
function Pure.sweep(t: number, pulse: number?): number
	local seconds = math.max(finite(pulse) or 1.2, 0.1)
	return math.clamp((finite(t) or 0) / seconds, 0, 1)
end

-- Cool, "Sweep" skin: how far either side of the middle (a share of the track) a tap is good (Pure.goodBlow's rule).
function Pure.sweepZone(pulse: number?, window: number?): number
	local seconds = math.max(finite(pulse) or 1.2, 0.1)
	return math.clamp(math.max(finite(window) or 0.3, 0) / seconds, 0, 0.5)
end

------------------------------------------------------------------------------------------------------------------
-- The Real Clinic's looks and words (design §7 and §9). Hints stay short (they fit a phone's card), and nothing here
-- says "cure": the game treats (design §12).
------------------------------------------------------------------------------------------------------------------

Pure.HINT_MAX = 20 -- characters in a hint or a title, so it fits a phone's card at 18 px

Pure.LOOKS = {
	-- the exam tools (Data/Tools Game)
	Listen = {
		Icon = "🩺",
		Title = "Listen!",
		Hint = "Tap each glow!",
		Sound = "Listen",
		Tint = "Cyan",
		Mark = "💓",
		Spot = "Glow",
	},
	Temp = {
		Icon = "🌡️",
		Title = "Temperature!",
		Hint = "Hold… let go on ⭐",
		Sound = "Beep",
		Tint = "Pink",
		Vessel = "Tube",
		Liquid = "#FF6B6B",
	},
	Light = {
		Icon = "🔦",
		Title = "Light check!",
		Hint = "Tap when it's big!",
		Sound = "Shine",
		Tint = "Cash",
		Style = "Ring",
		Target = "Face",
		Good = "💡",
		Miss = "💨",
	},
	Look = {
		Icon = "🔍",
		Title = "Take a look!",
		Hint = "Find the sore spots!",
		Sound = "Pop",
		Tint = "Purple",
		Mark = "🔍",
		Spot = "Sore",
	},
	XRay = {
		Icon = "📸",
		Title = "X-ray!",
		Hint = "Tap on the bone!",
		Sound = "Scan",
		Tint = "Cyan",
		Style = "Sweep",
		Target = "🦴",
		Good = "📸",
		Miss = "〰️",
	},
	-- the supplies (Data/Items Game)
	Plaster = {
		Icon = "🩹",
		Title = "Plaster!",
		Hint = "Tap the sore spots!",
		Sound = "Patch",
		Tint = "Pink",
		Mark = "🩹",
		Spot = "Sore",
	},
	Ice = {
		Icon = "🧊",
		Title = "Ice pack!",
		Hint = "Hold… let go on ⭐",
		Sound = "Cold",
		Tint = "Cyan",
		Vessel = "Pack",
		Liquid = "#8FD8FF",
	},
	Bandage = {
		Icon = "🧻",
		Title = "Bandage!",
		Hint = "Tap to wrap!",
		Sound = "Wrap",
		Tint = "Primary",
		Style = "Sweep",
		Target = "🦶",
		Good = "✨",
		Miss = "〰️",
	},
	Cast = {
		Icon = "🦴",
		Title = "Cast!",
		Hint = "Tap to wrap!",
		Sound = "Wrap",
		Tint = "Purple",
		Style = "Sweep",
		Target = "💪",
		Good = "✨",
		Miss = "〰️",
	},
	Bath = { Icon = "🛁", Title = "Bath time!", Hint = "Pop the bubbles!", Sound = "Scrub", Tint = "Cyan" },
	Cocoa = {
		Icon = "☕",
		Title = "Hot cocoa!",
		Hint = "Blow when it's big!",
		Sound = "Blow",
		Tint = "Primary",
		Style = "Ring",
		Target = "Mug",
		Good = "❄️",
		Miss = "💨",
	},
	-- the dispensary
	Dose = {
		Icon = "🥄",
		Title = "Measure!",
		Hint = "Fill to the ⭐!",
		Sound = "Pour",
		Tint = "Purple",
		Vessel = "Cup",
		Pourer = "Bottle",
		Liquid = "Bottle",
	},
	Pick = { Icon = "🤔", Title = "Pick one!", Hint = "Tap the right one!", Sound = "Found", Tint = "Collect" },
	-- the engines' own looks (a session that still names an engine plays as before)
	Pour = {
		Icon = "🧪",
		Title = "Pour!",
		Hint = "Hold… let go on ⭐",
		Sound = "Pour",
		Tint = "Purple",
		Vessel = "Bottle",
		Pourer = "🧪",
		Liquid = "#FF8FC7",
	},
	Patch = {
		Icon = "🩹",
		Title = "Patch!",
		Hint = "Tap the sore spots!",
		Sound = "Patch",
		Tint = "Pink",
		Mark = "🩹",
		Spot = "Sore",
	},
	Scrub = { Icon = "🛁", Title = "Scrub!", Hint = "Pop the bubbles!", Sound = "Scrub", Tint = "Cyan" },
	Cool = {
		Icon = "☕",
		Title = "Cool!",
		Hint = "Blow when it's big!",
		Sound = "Blow",
		Tint = "Primary",
		Style = "Ring",
		Target = "Mug",
		Good = "❄️",
		Miss = "💨",
	},
} :: { [string]: LookSpec }

-- The cards' own words (the exam's tool pick, the dispensary, the reveal, the results).
Pure.WORDS = {
	ExamIcon = "🤔",
	ExamTitle = "Which tool?",
	ExamHint = "👀 Which one fits?",
	GlowHint = "✨ The shiny one!",
	Wrong = "🙃 Hmm, not that one!",
	ChooseIcon = "💊",
	ChooseTitle = "Which one?",
	ChooseHint = "👆 Pick one to make",
	FindHint = "👀 Find this bottle!",
	Ready = "Ready!",
	ToBay = "🛏️ To the patient!",
	Better = "All better!",
	BetterHint = "😊 Feeling better!",
	Nice = "Nice!",
	NextHint = "🔜 Next step!",
}

------------------------------------------------------------------------------------------------------------------
-- Phone fit (Review Focus 5): the card's size on a screen, and where the Pick's targets go on its stage.
------------------------------------------------------------------------------------------------------------------

-- The card's numbers. build() makes the card from these, and MiniGamesPure.spec checks the copies of other modules'
-- numbers against their sources: Header = Kit.HEADER, Pad = Theme.Space.PadPanel, Gap = Theme.Space.Gap (under the
-- header) = Theme.Space.Step[2] (between the strips), Topbar = HudZones.TOPBAR (the ScreenGui's CoreUISafeInsets
-- leave the Roblox top bar out).
Pure.CARD = {
	MaxX = 540, -- the card's largest size (UISizeConstraint)
	MaxY = 514,
	ShareX = 0.96, -- its share of the safe area
	ShareY = 0.94,
	Aspect = 1.05, -- width / height (UIAspectRatioConstraint)
	Pad = 16, -- the panel's padding, every side
	Header = 64, -- the navy band
	Gap = 8, -- under the header, and between the strips
	Status = 26, -- the status strip: the step chips and the time bar
	Hint = 40, -- the hint line
	Topbar = 58, -- the Roblox top bar (the safe area starts under it)
	PickGap = 8, -- between the Pick's targets
	PickMax = 132, -- the Pick's targets never grow past this (a computer's big card)
	PickInset = 5, -- kept clear round the targets: their 3 px outline is drawn outside them, and the stage clips
}

local function xy(value: any): (number, number)
	local ok, x, y = pcall(function()
		return value.X, value.Y
	end)
	if not ok then
		return 0, 0
	end
	return math.max(finite(x) or 0, 0), math.max(finite(y) or 0, 0)
end

-- The card's size on a screen of `viewport` px (a Vector2 or { X, Y }), and the stage inside it where the games
-- draw. topInset: the top bar's height (default CARD.Topbar). Both as { X, Y } px.
function Pure.cardSize(viewport: any, topInset: number?): (Point, Point)
	local c = Pure.CARD
	local vx, vy = xy(viewport)
	local safeY = math.max(vy - math.max(finite(topInset) or c.Topbar, 0), 0)
	local w = math.min(vx * c.ShareX, c.MaxX)
	local h = math.min(safeY * c.ShareY, c.MaxY)
	-- The aspect ratio fits inside that box (FitWithinMaxSize).
	if h > 0 and w / h > c.Aspect then
		w = h * c.Aspect
	else
		h = w / c.Aspect
	end
	local innerW = math.max(w - c.Pad * 2, 0)
	local bodyH = math.max(h - c.Pad * 2 - (c.Header - c.Pad + c.Gap), 0)
	local stageH = math.max(bodyH - (c.Status + c.Gap + c.Hint + c.Gap), 0)
	return { X = w, Y = h }, { X = innerW, Y = stageH }
end

-- `n` square tap targets on a stage of `stage` px (a Vector2 or { X, Y }), as big as they fit (up to CARD.PickMax),
-- in the rows that make them biggest, centred, CARD.PickGap apart. Top-left rects in the stage's px. On a phone's
-- card every target is at least TAP_MIN (MiniGamesPure.spec), none overlap and none leave the stage.
function Pure.pickRects(stage: any, n: number): { Rect }
	local fullW, fullH = xy(stage)
	-- Inside the inset (the 2 x 2 bottles were clipped top and bottom: Studio test 2026-11-17).
	local inset = Pure.CARD.PickInset
	local w, h = fullW - 2 * inset, fullH - 2 * inset
	local count = math.clamp(math.floor(finite(n) or 0), 0, Pure.CHOICES_MAX)
	local gap = Pure.CARD.PickGap
	local out: { Rect } = {}
	if count == 0 or w <= 0 or h <= 0 then
		return out
	end
	local bestSide, bestRows = -1, 1
	for rows = 1, count do
		local cols = math.ceil(count / rows)
		local side = math.min((w - (cols - 1) * gap) / cols, (h - (rows - 1) * gap) / rows)
		if side > bestSide + 1e-9 then
			bestSide, bestRows = side, rows
		end
	end
	local side = math.floor(math.clamp(bestSide, 0, Pure.CARD.PickMax))
	local rows = bestRows
	local cols = math.ceil(count / rows)
	local top = (h - (rows * side + (rows - 1) * gap)) / 2
	for index = 1, count do
		local row = math.floor((index - 1) / cols)
		local col = (index - 1) % cols
		local inRow = math.min(cols, count - row * cols)
		local left = (w - (inRow * side + (inRow - 1) * gap)) / 2
		table.insert(out, {
			X = math.floor(inset + left + col * (side + gap)),
			Y = math.floor(inset + top + row * (side + gap)),
			W = side,
			H = side,
		})
	end
	return out
end

-- The Pick's targets on the card a screen of `viewport` px shows (Pure.cardSize, then Pure.pickRects), with the
-- stage and the card they sit in.
function Pure.pickLayout(viewport: any, n: number, topInset: number?): ({ Rect }, Point, Point)
	local card, stage = Pure.cardSize(viewport, topInset)
	return Pure.pickRects(stage, n), stage, card
end

------------------------------------------------------------------------------------------------------------------
-- The exam's tools and the dispensary's bottles
------------------------------------------------------------------------------------------------------------------

-- The Pick's choices: distinct ids from `list` (at most `max`, default CHOICES_MAX) with `answer` always among them
-- (it takes the last place when the list is full or doesn't have it). nil when there is no answer.
function Pure.choices(list: any, answer: any, max: number?): { string }?
	if type(answer) ~= "string" or answer == "" then
		return nil
	end
	local limit = math.clamp(math.floor(finite(max) or Pure.CHOICES_MAX), 1, Pure.CHOICES_MAX)
	local out = strings(list, limit)
	if not table.find(out, answer) then
		if #out >= limit then
			out[limit] = answer
		else
			table.insert(out, answer)
		end
	end
	return out
end

-- The shelf the dispensary's Pick shows: `count` medicine ids (Config.Dispensary.Bottles), `answer` among them, no
-- repeats. The others never share the answer's icon while the shelf has enough that don't (two 🧴 bottles side by
-- side would be a trick). pool = { { Id, Icon } } (the medicines, in Data/Items order); r01() returns 0..1 (a Random
-- in the game), so the same r01 gives the same shelf.
function Pure.bottles(answer: string, pool: any, count: number?, r01: () -> number): { string }
	local want = math.clamp(math.floor(finite(count) or 4), 1, Pure.CHOICES_MAX)
	local icon: string? = nil
	if type(pool) == "table" then
		for _, entry in ipairs(pool) do
			if type(entry) == "table" and entry.Id == answer then
				icon = entry.Icon
			end
		end
	end
	local unlike: { string } = {}
	local alike: { string } = {}
	if type(pool) == "table" then
		for _, entry in ipairs(pool) do
			local id = if type(entry) == "table" then entry.Id else nil
			if type(id) == "string" and id ~= answer and not table.find(unlike, id) and not table.find(alike, id) then
				table.insert(if icon ~= nil and entry.Icon == icon then alike else unlike, id)
			end
		end
	end
	local function shuffle(list: { string })
		for index = #list, 2, -1 do
			local other = math.clamp(math.floor(r01() * index) + 1, 1, index)
			list[index], list[other] = list[other], list[index]
		end
	end
	shuffle(unlike)
	local others: { string } = {}
	for _, id in unlike do
		if #others >= want - 1 then
			break
		end
		table.insert(others, id)
	end
	for _, id in alike do
		if #others >= want - 1 then
			break
		end
		table.insert(others, id)
	end
	local at = math.clamp(math.floor(r01() * (#others + 1)) + 1, 1, #others + 1)
	table.insert(others, at, answer)
	return others
end

-- The reveal after an exam: "It's a cough!", "It's an earache!", "It's sore muscles!" (a plural name takes no "a").
function Pure.reveal(name: any): string
	local text = "something"
	if type(name) == "string" and name ~= "" then
		text = string.lower(string.sub(name, 1, 1)) .. string.sub(name, 2)
	end
	local plural = string.sub(text, -1) == "s" and string.sub(text, -2) ~= "ss"
	if plural or text == "something" then
		return "It's " .. text .. "!"
	end
	local vowel = string.find(string.sub(text, 1, 1), "[aeiou]") ~= nil
	return "It's " .. (if vowel then "an " else "a ") .. text .. "!"
end

------------------------------------------------------------------------------------------------------------------
-- PURE:END
------------------------------------------------------------------------------------------------------------------

local DISPLAY_ORDER = Theme.DisplayOrder.Popup + 5 -- over panels and pop-ups, under the treat pops and toasts
local ACTION = "MiniGamesAction" -- Space / gamepad A while the card is open
local MIN_TAP = Theme.Size.ButtonHeight
local NAME = "MiniGame" -- the modal's name (ModalOpened / ModalClosed)

-- The card's body (px, under UI/Modal's navy header): the status strip (steps + time bar), the stage, the hint line.
local STATUS = Pure.CARD.Status
local HINT = Pure.CARD.Hint
local GAP = Theme.Space.Step[2]
local GLYPH = 32 -- the pad's button picture on the hint line

-- Timing (seconds). The games' own numbers are in Config.MiniGame.
local INTRO = 0.4 -- each game's picture pops in before it takes taps
local RATING_HOLD = 0.9 -- the rating pop stays this long before the next game
local RESULT_HOLD = 1.2 -- the server's answer stays this long before the card closes
local REVEAL_HOLD = 1.2 -- an exam's case reveal ("🩺 It's a cough!") stays this long (build plan Task 7)
local REPORT_MARGIN = 0.15
local TIMEOUT_MARGIN = 0.6 -- the card closes this long before the server settles the session by itself
local POUR_IDLE = 6 -- a Pour nobody starts ends by itself (rated OK)
local POUR_SOUND_EVERY = 0.3
local SPOT_EVERY = 0.4 -- Patch: the sore spots pop up one after another
local BUBBLE_EVERY = 0.36
local BUBBLE_LIFE = 1.8
local BUBBLE_MAX = 4
local COOL_GAP = 0.35 -- between beats
local COOL_GRACE = 0.08 -- a tap this soon in a beat is a leftover from the last one: ignored
local RING_MIN = 0.3
local PICK_SHAKE = 0.3 -- a wrong pick shakes its head this long

local WHITE = Palette.White
local OUTLINE = Theme.Colors.Outline
local GLASS = Color3.fromRGB(226, 244, 255)
local SORE = Color3.fromRGB(255, 120, 140)
local SORE_CORE = Color3.fromRGB(230, 60, 90)
local GLOW = Color3.fromRGB(150, 228, 255) -- Listen: the chest's glowing spots
local GLOW_CORE = Color3.fromRGB(255, 255, 255)
local MUD = Color3.fromRGB(150, 98, 56)
local BUBBLE = Color3.fromRGB(196, 238, 255)
local STEAM = Color3.fromRGB(232, 236, 252)
local BEAM = Color3.fromRGB(255, 240, 170) -- Light: the light ring
local SCAN = Color3.fromRGB(120, 210, 255) -- XRay: the scanner bar
local COCOA = Color3.fromRGB(132, 74, 44)
local CALM_BLUE = Palette.Candy.Blue -- "OK!": a calm blue, never a grey "fail"

-- Each game's look lives INSIDE the card (it's the game: its pop, its chips, its skin); the header is always navy.
-- Built from Pure.LOOKS: the Tint names a Theme colour, the Liquid is a hex (or the chosen medicine's colour).
type GameLook = LookSpec & { Color: Color3 }

local function tint(name: string?): Color3
	local color = if type(name) == "string" then (Theme.Colors :: any)[name] else nil
	return if typeof(color) == "Color3" then color else Theme.Colors.Primary
end

local function lookOf(spec: LookSpec): GameLook
	local look = table.clone(spec) :: any
	look.Color = tint(spec.Tint)
	return look :: GameLook
end

local GAME_LOOK: { [string]: GameLook } = {}
for gameId, spec in Pure.LOOKS do
	GAME_LOOK[gameId] = lookOf(spec)
end
local TAP_LOOK: GameLook =
	lookOf({ Icon = "✨", Title = "Tap!", Hint = "Tap to help!", Sound = "Pop", Tint = "Collect" })
-- The triage card's floor buttons wear each department's badge-chip colour (CreatureBuilder.setDept): the colour is
-- the game ("Match the badge!"), so they're candy buttons with their own Fill.
local DEPT_COLORS: { [string]: Color3 } = {
	Reception = Theme.Colors.Primary,
	AE = Theme.Colors.Destructive,
	Wards = Theme.Colors.Pink, -- 🛏️ the Injury Ward
	Rest = Theme.Colors.Night, -- 😴 the Rest Ward
	Hydro = Theme.Colors.Cyan,
	Pharmacy = Theme.Colors.Collect,
	Imaging = Theme.Colors.Cyan,
	Roof = Theme.Colors.Purple,
}
local AUTO_HOLD = 0.5 -- an ability's PERFECT game shows its sparkle this long before the rating pop
local TRIAGE_MARGIN = 0.3 -- the floor buttons stop taking taps this long before the server stops waiting
local TRIAGE_HOLD = 1.1 -- the triage answer stays this long before the card closes
local TRIAGE_LEAD = 0.45 -- the results flash this long before the floor buttons come

type RatingLook = { Text: string, Icon: string, Color: Color3 }
local RATING_LOOK: { [string]: RatingLook } = {
	Perfect = { Text = "PERFECT!", Icon = "⭐", Color = Theme.Colors.Cash },
	Good = { Text = "GOOD!", Icon = "👍", Color = Theme.Colors.Collect },
	OK = { Text = "OK!", Icon = "🙂", Color = CALM_BLUE },
}

------------------------------------------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------------------------------------------

-- The client bus (ctx.fire); nothing is fired until init.
local busFire: ((string, ...any) -> ())? = nil
local function fireBus(event: string, ...: any)
	local fire = busFire
	if fire then
		fire(event, ...)
	end
end

local function sound(name: string)
	fireBus("Sound", name)
end

local function calm(): boolean
	return Kit.reducedMotion()
end

local function play(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local tween = TweenService:Create(instance, info, goal)
	tween:Play()
	return tween
end

-- Tweens to the goal, or jumps straight there when motion is calm.
local function ease(instance: Instance, info: TweenInfo, goal: { [string]: any })
	if calm() then
		for key, value in goal do
			(instance :: any)[key] = value
		end
	else
		play(instance, info, goal)
	end
end

local function scaleOf(gui: GuiObject): UIScale
	-- One UIScale per object (Kit and Hud reuse whatever is there: two would fight).
	local existing = gui:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	return scale
end

-- A springy squash or stretch from `from` back to 1. Skipped when calm.
local function punch(gui: GuiObject, from: number, seconds: number?)
	if calm() then
		return
	end
	local scale = scaleOf(gui)
	scale.Scale = from
	play(scale, TweenInfo.new(seconds or 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
end

local function new(className: string, props: { [string]: any }): any
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

-- Round by default (Theme.Radius.Round); otherwise a Theme.Radius token.
local function corner(gui: GuiObject, radius: (number | UDim)?)
	Kit.corner(gui, radius or Theme.Radius.Round)
end

local function minSize(gui: GuiObject, px: number)
	new("UISizeConstraint", { MinSize = Vector2.new(px, px), Parent = gui })
end

-- A filled round shape with the candy outline (a circle unless `radius` says otherwise).
local function blob(
	parent: Instance,
	name: string,
	color: Color3,
	props: { [string]: any },
	radius: (number | UDim)?
): Frame
	local frame = new("Frame", {
		Name = name,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = parent,
	})
	for key, value in props do
		frame[key] = value
	end
	corner(frame, radius)
	Kit.stroke(frame, OUTLINE, Theme.Stroke.Bold)
	return frame
end

local function emoji(parent: Instance, text: string, props: { [string]: any }): TextLabel
	local label = new("TextLabel", {
		Name = "Emoji",
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		Font = Theme.Font,
		TextColor3 = Theme.Colors.Ink,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = parent,
	})
	for key, value in props do
		label[key] = value
	end
	return label
end

-- A square `k` x the parent's height, centred on `at` (parent scale).
local function squareAt(k: number, at: UDim2): { [string]: any }
	return {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = at,
		Size = UDim2.fromScale(k, k),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
	}
end

-- Little icons fly out of a point and fade (a reward, a pop). Skipped when calm.
local function burst(parent: GuiObject, at: UDim2, icon: string, count: number, size: number)
	if calm() or not parent.Parent then
		return
	end
	for index = 1, count do
		local angle = (index / count) * math.pi * 2 + math.random() * 0.5
		local props = squareAt(size, at)
		props.ZIndex = 40
		local label = emoji(parent, icon, props)
		local reach = 0.14 + math.random() * 0.1
		local goal = UDim2.new(
			at.X.Scale + math.cos(angle) * reach,
			at.X.Offset,
			at.Y.Scale + math.sin(angle) * reach,
			at.Y.Offset
		)
		local tween = play(label, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = goal,
			TextTransparency = 1,
			Rotation = math.random(-40, 40),
		})
		tween.Completed:Once(function()
			label:Destroy()
		end)
	end
end

local function usesGamepad(): boolean
	local preferred = UserInputService.PreferredInput
	return preferred == Enum.PreferredInput.Gamepad or preferred == Enum.PreferredInput.MicroGamepad
end

-- The gamepad's own picture of the button that plays (ButtonA: ✕ on PlayStation, A on Xbox), from
-- UserInputService:GetImageForKeyCode. Nil without a gamepad (or when Roblox has no picture for it).
local function padImage(): string?
	if not usesGamepad() then
		return nil
	end
	local ok, image = pcall(function()
		return UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonA)
	end)
	return if ok and type(image) == "string" and image ~= "" then image else nil
end

-- The hint's first icon: what to press with on this device. A gamepad's is a picture (padImage), never "🅰️": here
-- it's "🎮" only when Roblox has no picture for the pad.
local function pointer(): string
	if usesGamepad() then
		return if padImage() then "" else "🎮"
	elseif UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse then
		return "🖱️"
	end
	return "👆"
end

-- A "press here" mark: the pad's button picture (an ImageLabel) on a gamepad, else the pointer emoji.
local function pressMark(parent: Instance, props: { [string]: any }): GuiObject
	local image = padImage()
	if image then
		local picture = new("ImageLabel", {
			Name = "PadGlyph",
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = parent,
		})
		for key, value in props do
			picture[key] = value
		end
		return picture
	end
	return emoji(parent, pointer(), props)
end

-- The running session's Config.MiniGame, eased by 🎯 Steady Hands (Pure.eased) and, for an Expert dispenser, the
-- wider Dose band (Pure.widened); nil between sessions.
local activeMini: any = nil

local function miniOf(ctx: Types.Ctx): any
	return activeMini or ctx.Config.MiniGame
end

-- A game's tuning row as this session draws and rates it (Logic/MiniGame.tuning: its Games row, else its engine's).
local function tuningOf(ctx: Types.Ctx, gameId: string): any
	local row = MiniGame.tuning(gameId, { MiniGame = miniOf(ctx) })
	return if type(row) == "table" then row else {}
end

local function num(value: any, fallback: number): number
	return finite(value) or fallback
end

-- A row of one of ctx.Data's maps (Tools, Items, Cases, ...), or nil (a junk id, or a map this client lacks).
local function dataRow(ctx: Types.Ctx, map: string, id: any): any
	local data = (ctx.Data :: any)[map]
	if type(data) ~= "table" or type(id) ~= "string" or id == "" then
		return nil
	end
	local row = rawget(data, id)
	return if type(row) == "table" then row else nil
end

-- A "#RRGGBB" as a Color3, or the fallback.
local function hexColor(value: any, fallback: Color3): Color3
	if type(value) ~= "string" then
		return fallback
	end
	local ok, color = pcall(Color3.fromHex, value)
	return if ok and typeof(color) == "Color3" then color else fallback
end

------------------------------------------------------------------------------------------------------------------
-- The card: UI/Modal's template (Layer Panel, HudMode "Game", no ✖, a dim that never closes it or takes a tap)
------------------------------------------------------------------------------------------------------------------

type View = {
	Modal: Modal.Modal,
	Gui: ScreenGui,
	Root: Frame,
	Card: Frame,
	Combo: TextLabel, -- the header's meta chip: "🔥 Go!" / "🔥 6"
	ComboMult: TextLabel,
	ComboOn: boolean, -- the chip shows (not in Simple mode)
	Status: Frame,
	Steps: Frame,
	TimeTrack: Frame,
	TimeFill: Frame,
	Stage: TextButton,
	Hint: Frame,
	HintGlyph: ImageLabel,
	HintText: TextLabel,
	Pop: Frame,
	PopRays: Frame,
	PopText: TextLabel,
	PopStroke: UIStroke,
	ComboValue: number,
}

local current: Run? = nil
local closing = false -- closeCard is closing the modal (anything else closing it ends the run)
local stop: (run: Run) -> () -- ends a run (below)

local function build(ctx: Types.Ctx): View
	local modal = Modal.modal(ctx, {
		Name = NAME,
		Title = "🤔 Pick one!",
		Layer = "Panel",
		HudMode = "Game",
		CloseButton = false,
		DimCloses = false, -- the dim is a shade only: the thumbstick and camera still work under it
		AutoFocus = false, -- Space / gamepad A play the games; the triage card picks its own focus
		-- Pure.CARD: Pure.pickLayout works out the targets' size on a phone from the same numbers
		MaxSize = Vector2.new(Pure.CARD.MaxX, Pure.CARD.MaxY),
		Scale = Vector2.new(Pure.CARD.ShareX, Pure.CARD.ShareY),
		OnClose = function()
			-- Only closeCard closes it. If anything else ever does, the run ends (the server settles it as OK).
			local run = current
			if not closing and run and run.Alive then
				task.defer(stop, run)
			end
		end,
	})
	modal.Gui.DisplayOrder = DISPLAY_ORDER -- over panels and pop-ups, under the treat pops and toasts
	-- The tutorial's slim Now strip stays readable (look build plan §B7): while Hud lifts it over this card's
	-- shade, the card keeps clear of it (it centres in the room under the strip).
	local function clearNow()
		local free = 0
		if Hud.nowLifted() then
			local edge = Hud.nowEdge()
			if edge > 0 then
				free = math.max(0, edge + Theme.Space.Gap - modal.Gui.AbsolutePosition.Y)
			end
		end
		modal.setTop(free)
	end
	Hud.NowMoved:Connect(clearNow)
	modal.Gui:GetPropertyChangedSignal("AbsolutePosition"):Connect(clearNow)
	new("UIAspectRatioConstraint", { AspectRatio = Pure.CARD.Aspect, Parent = modal.Root })
	local body = modal.Body

	-- The 🔥 combo is the header's ONE meta chip (white, ink text; there's no ✖), with its ×multiplier tag under it.
	local combo = modal.Meta
	local comboMult = Kit.label({
		Name = "Multiplier",
		Text = "",
		Font = Theme.DisplayFont,
		TextScaled = true,
		TextWrapped = false,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.Cash,
		-- Under the chip's right end (a sibling, so the chip's automatic width never counts it).
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, Theme.Space.Step[2], 0, Kit.HEADER - Theme.Space.PadPanel - Theme.Space.Step[1]),
		Size = UDim2.fromOffset(56, 24),
		Visible = false,
		ZIndex = 5,
		Parent = modal.Panel,
	})
	corner(comboMult, Theme.Radius.Small)
	Kit.stroke(comboMult, OUTLINE, Theme.Stroke.Fine)
	Kit.textLimit(comboMult, Theme.TextSize.Caption)

	-- Status strip: one chip per game (only with 2+), then the soft time bar (timed games only).
	local status = new("Frame", {
		Name = "Status",
		Size = UDim2.new(1, 0, 0, STATUS),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = body,
	})
	local steps = new("Frame", {
		Name = "Steps",
		Size = UDim2.fromScale(0, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = status,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, Theme.Space.Step[1]),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = steps,
	})
	local track = new("Frame", {
		Name = "Time",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundColor3 = Theme.Colors.Well,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
		Parent = status,
	})
	corner(track)
	local fill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Collect,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = track,
	})
	corner(fill)

	-- The stage: where each game draws. A button, so a tap here never reaches the world behind.
	local top = STATUS + GAP
	local stage = new("TextButton", {
		Name = "Stage",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 1, -(top + HINT + GAP)),
		ZIndex = 3,
		Parent = body,
	})

	-- The hint line: the pad's button picture (gamepads), then the words.
	local hint = new("Frame", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, HINT),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = body,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, Theme.Space.Step[2]),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = hint,
	})
	local hintGlyph = new("ImageLabel", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(GLYPH, GLYPH),
		LayoutOrder = 1,
		Visible = false,
		ZIndex = 3,
		Parent = hint,
	})
	-- The words fill the line and shrink to fit a phone's card (never under 18 px: Kit.textLimit).
	local hintText = Kit.label({
		Name = "Text",
		Text = "",
		TextScaled = true,
		TextWrapped = false,
		Size = UDim2.new(1, 0, 0, HINT - Theme.Space.Step[2]),
		LayoutOrder = 2,
		ZIndex = 3,
		Parent = hint,
	})
	Kit.textLimit(hintText, Theme.TextSize.Body)

	-- The rating pop: huge outlined words over the middle of the card.
	local pop = new("Frame", {
		Name = "Pop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 14),
		Size = UDim2.fromScale(1.04, 0.34),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 10,
		Parent = modal.Root,
	})
	local popRays = new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = pop,
	})
	local popText = new("TextLabel", {
		Name = "Rating",
		BackgroundTransparency = 1,
		Text = "",
		Font = Theme.DisplayFont,
		TextScaled = true,
		TextWrapped = false,
		TextColor3 = Theme.Colors.Cash,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = pop,
	})
	Kit.textLimit(popText, 112)
	local popStroke = Kit.outline(popText, Theme.Stroke.Panel)

	return {
		Modal = modal,
		Gui = modal.Gui,
		Root = modal.Root,
		Card = modal.Panel,
		Combo = combo,
		ComboMult = comboMult,
		ComboOn = true,
		Status = status,
		Steps = steps,
		TimeTrack = track,
		TimeFill = fill,
		Stage = stage,
		Hint = hint,
		HintGlyph = hintGlyph,
		HintText = hintText,
		Pop = pop,
		PopRays = popRays,
		PopText = popText,
		PopStroke = popStroke,
		ComboValue = 0,
	}
end

-- The header says which game this is (always on the navy band; the game's colour is inside the card).
local function setHeader(v: View, icon: string, title: string, _color: Color3)
	v.Modal.setTitle(icon .. " " .. title)
	local label = v.Modal.Title
	if label then
		punch(label, 1.15, 0.35)
	end
end

-- The hint line. withPress: it starts with what to press (the pad's picture on a gamepad, else 👆 / 🖱️).
local function setHint(v: View, text: string, withPress: boolean?)
	local image = if withPress then padImage() else nil
	v.HintGlyph.Visible = image ~= nil
	v.HintGlyph.Image = image or ""
	v.HintText.Size = UDim2.new(1, if image then -(GLYPH + Theme.Space.Step[2]) else 0, 0, HINT - Theme.Space.Step[2])
	local mark = if withPress and not image then pointer() else ""
	v.HintText.Text = if mark ~= "" and text ~= "" then mark .. " " .. text else text
end

local function setTime(v: View, share: number?)
	if share == nil then
		v.TimeTrack.Visible = false
		return
	end
	v.TimeTrack.Visible = true
	v.TimeFill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
end

-- A step chip's icon. A Treat step shows its item; an Exam never shows the right tool before it is picked (🤔 and ❓
-- until then); a Dispense step shows the chosen medicine (💊 until it is chosen) and the cup.
local function stepIcon(ctx: Types.Ctx, run: Run, index: number): string
	local session = run.Session
	local gameId = session.Games[index]
	local look = GAME_LOOK[gameId] or TAP_LOOK
	if session.Kind == "Exam" then
		if not run.Picked then
			return if gameId == "Pick" then Pure.WORDS.ExamIcon else "❓"
		end
		local tool = dataRow(ctx, "Tools", session.Answer)
		return if tool and type(tool.Icon) == "string" then tool.Icon else look.Icon
	elseif session.Kind == "Dispense" then
		local item = dataRow(ctx, "Items", run.Choice)
		if gameId == "Pick" then
			return if item and type(item.Icon) == "string" then item.Icon else Pure.WORDS.ChooseIcon
		end
		return look.Icon
	end
	local item = dataRow(ctx, "Items", session.Items[index])
	return if item and type(item.Icon) == "string" then item.Icon else look.Icon
end

local function setSteps(ctx: Types.Ctx, v: View, run: Run)
	local session = run.Session
	for _, child in v.Steps:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local count = #session.Games
	local shown = count > 1
	local width = if shown then count * (STATUS + 4) else 0
	v.Steps.Visible = shown
	v.Steps.Size = UDim2.new(0, width, 1, 0)
	v.TimeTrack.Size = UDim2.new(1, -(if shown then width + 8 else 0), 0, 14)
	if not shown then
		return
	end
	for index in session.Games do
		local chip = blob(v.Steps, "Step" .. index, Theme.Colors.Card, {
			LayoutOrder = index,
			Size = UDim2.fromOffset(STATUS, STATUS),
			ZIndex = 3,
		})
		emoji(chip, stepIcon(ctx, run, index), {
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.78, 0.78),
			ZIndex = 4,
		})
	end
end

-- The step chips' icons again (an exam's tool was picked, or a medicine chosen).
local function refreshSteps(ctx: Types.Ctx, v: View, run: Run)
	for index in run.Session.Games do
		local chip = v.Steps:FindFirstChild("Step" .. index)
		local label = chip and chip:FindFirstChild("Emoji")
		if label and label:IsA("TextLabel") then
			label.Text = stepIcon(ctx, run, index)
		end
	end
end

local function markStep(v: View, index: number, rating: string?)
	local chip = v.Steps:FindFirstChild("Step" .. index)
	if not chip or not chip:IsA("Frame") then
		return
	end
	if rating then
		local look = RATING_LOOK[rating] or RATING_LOOK.OK
		chip.BackgroundColor3 = Kit.lighten(look.Color, 0.15)
	else
		chip.BackgroundColor3 = WHITE
		punch(chip, 1.35)
	end
end

local function showCombo(ctx: Types.Ctx, v: View, value: number, animate: boolean)
	local before = v.ComboValue
	v.ComboValue = value
	-- No combo reads as a cheer, never a loss (only an OK resets it; a GOOD! holds it: build plan §E7): the chip says
	-- "🔥 Go!" instead of a bare 0, in a softer ink.
	v.Modal.setMeta(if v.ComboOn then "🔥 " .. (if value <= 0 then "Go!" else tostring(value)) else "")
	local multiplier = MiniGame.multiplier(value, ctx.Config)
	local tag = Pure.multText(multiplier)
	v.ComboMult.Text = tag
	v.ComboMult.Visible = v.ComboOn and tag ~= ""
	v.Combo.TextColor3 = if value > 0 then Theme.Colors.Ink else Theme.Colors.InkSoft
	if animate and v.ComboOn and value > before then
		punch(v.Combo, 1.3)
		if multiplier > MiniGame.multiplier(before, ctx.Config) then
			punch(v.ComboMult, 1.8, 0.45)
			-- Out of the chip's corner of the card (not inside the chip: its width follows its text).
			burst(v.Card, UDim2.new(1, -Theme.Space.Step[6], 0, Theme.Space.PadPanel), "🔥", 5, 0.1)
		end
	end
end

-- The rating pop. Only the newest pop hides itself (popToken), and its rays stop with it.
local popToken = 0
local stopRays: (() -> ())? = nil

local function clearPop(v: View)
	popToken += 1
	v.Pop.Visible = false
	if stopRays then
		stopRays()
		stopRays = nil
	end
end

-- `magic`: an ability made it PERFECT (TreatSession.Auto): "✨ PERFECT!" with sparkles instead of stars.
local function showRating(v: View, rating: string, magic: boolean?)
	local look = RATING_LOOK[rating] or RATING_LOOK.OK
	clearPop(v)
	local token = popToken
	local text, stroke = v.PopText, v.PopStroke
	local scale = scaleOf(text)
	text.Text = if magic then "✨ " .. look.Text else look.Text
	text.TextColor3 = look.Color
	text.TextTransparency = 0
	text.Rotation = 0
	stroke.Transparency = 0
	scale.Scale = 1
	v.Pop.Visible = true
	if rating == "Perfect" then
		stopRays = Kit.celebrate(v.PopRays, look.Color)
		burst(v.Pop, UDim2.fromScale(0.5, 0.5), if magic then "✨" else "⭐", 8, 0.3)
		punch(v.Card, 1.04, 0.35)
	elseif rating == "Good" then
		burst(v.Pop, UDim2.fromScale(0.5, 0.5), "✨", 5, 0.24)
	end
	if not calm() then
		scale.Scale = 0.25
		text.Rotation = if rating == "Perfect" then -10 else -6
		play(scale, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		play(text, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 })
	end
	task.delay(RATING_HOLD - 0.18, function()
		if popToken ~= token then
			return
		end
		local fade = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		ease(scale, fade, { Scale = 1.15 })
		ease(text, fade, { TextTransparency = 1 })
		ease(stroke, fade, { Transparency = 1 })
		task.delay(0.17, function()
			if popToken == token then
				clearPop(v)
			end
		end)
	end)
end

------------------------------------------------------------------------------------------------------------------
-- A run: one TreatStart, from the card opening to it closing
------------------------------------------------------------------------------------------------------------------

type Run = {
	Id: number,
	Alive: boolean,
	Reported: boolean,
	Session: Session,
	Raw: any, -- the TreatStart payload as the server sent it (TreatDone passes it on)
	Started: number,
	Cleanups: { () -> () },
	Rng: Random,
	HideDrain: boolean, -- the first-session tutorial: no time bar runs down (Pure.drainBar)
	-- The Real Clinic
	Picked: boolean, -- Exam: the right tool has been picked (the step chips may show it now)
	Choice: string?, -- Dispense: the medicine being made (the report's Choice)
}

-- Everything a game needs. Each game builds into Layer, waits on intro(), loops while alive() and returns a score.
type Env = {
	Ctx: Types.Ctx,
	Session: Session,
	View: View,
	Layer: Frame, -- this game's own layer in the stage (destroyed when the game ends)
	Catcher: TextButton, -- the whole stage, under the game's drawing: for "tap anywhere" games
	Rng: Random,
	Run: Run,
	GameId: string, -- the game being played ("" for the Dispense card's medicine choice)
	Look: GameLook, -- its look (Pure.LOOKS): the words, the sound and the engine's skin
	alive: () -> boolean,
	track: (connection: RBXScriptConnection) -> (),
	intro: () -> boolean, -- pops the picture in and waits INTRO seconds; false when the run ended meanwhile
	pause: (seconds: number) -> boolean, -- false when the run ended meanwhile
	onPress: (gui: GuiObject, fn: (input: InputObject) -> ()) -> (), -- mouse or touch down on gui
	onAction: (fn: ((began: boolean) -> ())?) -> (), -- Space / gamepad A, down (true) and up (false)
	drain: (share: number) -> (), -- the draining time bar (hidden while the tutorial runs)
	r01: () -> number,
}

local view: View? = nil
local actionHandler: ((boolean) -> ())? = nil
local runs = 0

local function handleAction(_: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	local handler = actionHandler
	if handler then
		if state == Enum.UserInputState.Begin then
			handler(true)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			handler(false)
		end
	end
	return Enum.ContextActionResult.Sink
end

-- Space and the gamepad's A play the games. withPad false: Space only, so the gamepad's A presses the selected
-- button (a Pick's targets; Space still never makes the character jump while the card is up).
local function bindPlay(withPad: boolean)
	ContextActionService:UnbindAction(ACTION)
	if withPad then
		ContextActionService:BindActionAtPriority(
			ACTION,
			handleAction,
			false,
			Enum.ContextActionPriority.High.Value,
			Enum.KeyCode.ButtonA,
			Enum.KeyCode.Space
		)
	else
		ContextActionService:BindActionAtPriority(
			ACTION,
			handleAction,
			false,
			Enum.ContextActionPriority.High.Value,
			Enum.KeyCode.Space
		)
	end
end

local function openCard(v: View)
	clearPop(v)
	v.Modal.open() -- the dim, the pop in, the Whoosh, and ModalOpened (MiniGame, "Game") for the HUD
	bindPlay(true)
end

local function closeCard(v: View)
	ContextActionService:UnbindAction(ACTION)
	actionHandler = nil
	clearPop(v)
	setTime(v, nil)
	closing = true
	v.Modal.close()
	closing = false
end

-- Ends a run: its connections and layers go, and the card closes unless a newer run already owns it.
stop = function(run: Run)
	if not run.Alive then
		return
	end
	run.Alive = false
	if current == run then
		activeMini = nil
	end
	for _, cleanup in run.Cleanups do
		pcall(cleanup)
	end
	table.clear(run.Cleanups)
	if current == run then
		current = nil
		if view then
			closeCard(view)
		end
	end
end

local function waitFor(run: Run, seconds: number): boolean
	if seconds > 0 then
		task.wait(seconds)
	end
	return run.Alive
end

------------------------------------------------------------------------------------------------------------------
-- The games
------------------------------------------------------------------------------------------------------------------

-- The patient's face, `k` x the stage's height, centred at (0.5, y).
local function creature(env: Env, k: number, y: number): Frame
	local holder = new("Frame", squareAt(k, UDim2.fromScale(0.5, y)))
	holder.Name = "Creature"
	holder.BackgroundTransparency = 1
	holder.ZIndex = 2
	local portrait = Hud.portrait(Hud.lookOf(env.Session.PatientId))
	portrait.Parent = holder
	holder.Parent = env.Layer
	return holder
end

-- The medicine a Dispense card is making (Data/Items row), or nil.
local function chosenMedicine(env: Env): any
	return dataRow(env.Ctx, "Items", env.Run.Choice)
end

-- The Pour engine's vessels (Pure.LOOKS Vessel). Width and Height are shares of the stage's height; Neck is the
-- neck's share of the vessel; Bulb draws a thermometer's round end.
type Vessel = { Width: number, Height: number, Neck: number, Radius: UDim, Bulb: boolean? }
local VESSELS: { [string]: Vessel } = {
	Bottle = { Width = 0.46, Height = 0.8, Neck = 0.16, Radius = UDim.new(0.3, 0) }, -- 🧪
	Cup = { Width = 0.62, Height = 0.7, Neck = 0, Radius = UDim.new(0.16, 0) }, -- the dispensary's measuring cup
	Tube = { Width = 0.2, Height = 0.66, Neck = 0, Radius = UDim.new(0.5, 0), Bulb = true }, -- 🌡️
	Pack = { Width = 0.66, Height = 0.64, Neck = 0.12, Radius = UDim.new(0.24, 0) }, -- 🧊
}

-- Pour: hold to fill, let go in the band. Score = the fill when let go. The look picks the vessel, its liquid and
-- what pours (the 🧪 vial, the medicine's own bottle) or nothing (a thermometer climbs, an ice pack cools).
local function playPour(env: Env): number
	local cfg = tuningOf(env.Ctx, env.GameId)
	local look = env.Look
	local fillSeconds = math.max(num(cfg.FillSeconds, 2.4), 0.5)
	local lo, hi, goodLo, goodHi = Pure.bands(cfg)
	local layer = env.Layer
	local shape = VESSELS[look.Vessel or "Bottle"] or VESSELS.Bottle
	local NECK = shape.Neck
	local BOTTOM, HEIGHT = 0.97, shape.Height -- the vessel in the stage (stage-height scale)
	local medicine = chosenMedicine(env)
	local liquidColor = if look.Liquid == "Bottle"
		then hexColor(if medicine then medicine.Bottle else nil, Theme.Colors.Pink)
		else hexColor(look.Liquid, Theme.Colors.Pink)
	local pourIcon: string? = if look.Pourer == "Bottle"
		then (if medicine and type(medicine.Icon) == "string" then medicine.Icon else look.Icon)
		else look.Pourer

	local bottle = new("Frame", {
		Name = "Vessel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, BOTTOM),
		Size = UDim2.fromScale(shape.Width, HEIGHT),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = layer,
	})
	if NECK > 0 then
		blob(bottle, "Neck", GLASS, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromScale(0.36, NECK + 0.05),
			ZIndex = 2,
		}, UDim.new(0, 8))
	end
	local body = blob(bottle, "Body", GLASS, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 1 - NECK),
		ClipsDescendants = true,
		ZIndex = 3,
	}, shape.Radius)
	local liquid = new("Frame", {
		Name = "Liquid",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = liquidColor,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = body,
	})
	corner(liquid, Theme.Radius.Medium)
	Palette.candyGradient(liquid)
	if shape.Bulb then
		-- The thermometer's round end, always full.
		blob(bottle, "Bulb", liquidColor, {
			AnchorPoint = Vector2.new(0.5, 0.6),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromScale(1.8, 1.8),
			SizeConstraint = Enum.SizeConstraint.RelativeXX,
			ZIndex = 4,
		})
	end
	if look.Vessel == "Cup" then
		-- The measuring cup's lines.
		for _, at in { 0.25, 0.5, 0.75 } do
			new("Frame", {
				Name = "Line",
				Position = UDim2.fromScale(0.08, 1 - at),
				Size = UDim2.new(0.22, 0, 0, 3),
				BackgroundColor3 = OUTLINE,
				BackgroundTransparency = 0.45,
				BorderSizePixel = 0,
				ZIndex = 5,
				Parent = body,
			})
		end
	end
	local surface = new("Frame", {
		Name = "Surface",
		Size = UDim2.new(1, 0, 0, 5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = liquid,
	})
	local function band(name: string, from: number, to: number, color: Color3, transparency: number, z: number): Frame
		return new("Frame", {
			Name = name,
			Position = UDim2.fromScale(0, 1 - to),
			Size = UDim2.fromScale(1, math.max(to - from, 0)),
			BackgroundColor3 = color,
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
			ZIndex = z,
			Parent = body,
		})
	end
	band("GoodHigh", hi, goodHi, Theme.Colors.Cash, 0.6, 5)
	band("GoodLow", goodLo, lo, Theme.Colors.Cash, 0.6, 5)
	local perfect = band("Perfect", lo, hi, Theme.Colors.Collect, 0.35, 6)
	local glow = Kit.stroke(perfect, WHITE, Theme.Stroke.Bold)
	glow.Enabled = false
	-- A ⭐ just outside each side of the vessel, level with the band.
	local starY = NECK + (1 - NECK) * (1 - (lo + hi) / 2)
	local stars: { TextLabel } = {}
	for _, side in { -1, 1 } do
		table.insert(
			stars,
			emoji(bottle, "⭐", {
				AnchorPoint = Vector2.new(if side < 0 then 1 else 0, 0.5),
				Position = UDim2.new(if side < 0 then 0 else 1, side * 4, starY, 0),
				Size = UDim2.fromScale(0.24, 0.24),
				SizeConstraint = Enum.SizeConstraint.RelativeYY,
				ZIndex = 6,
			})
		)
	end
	-- What pours (it tips and streams), or the game's own icon over the vessel; and the "hold here" hand.
	local vialProps = squareAt(0.19, UDim2.fromScale(0.5, 0.1))
	vialProps.ZIndex = 7
	local vial = emoji(layer, pourIcon or look.Icon, vialProps)
	local stream = new("Frame", {
		Name = "Stream",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.14),
		Size = UDim2.fromScale(0.05, 0),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundColor3 = liquidColor,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Parent = layer,
	})
	corner(stream)
	local handProps = squareAt(0.2, UDim2.fromScale(0.5, 0.66))
	handProps.ZIndex = 8
	local hand = pressMark(layer, handProps) -- 👆 / 🖱️, or the pad's own button picture

	local pressedAt: number? = nil
	local result: number? = nil
	local ready = false
	local function press()
		if not ready or pressedAt ~= nil or result ~= nil then
			return
		end
		pressedAt = os.clock()
		hand.Visible = false
		if pourIcon then
			stream.Visible = true
			ease(vial, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = -110 })
		else
			punch(vial, 1.3, 0.25)
		end
		sound(look.Sound)
	end
	local function release()
		local at = pressedAt
		if at ~= nil and result == nil then
			result = Pure.fill(os.clock() - at, fillSeconds)
		end
	end
	env.onPress(env.Catcher, function()
		press()
	end)
	-- Any finger or the mouse button coming up lets go (wherever it ends, even off the card).
	env.track(UserInputService.InputEnded:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			release()
		end
	end))
	env.onAction(function(began)
		if began then
			press()
		else
			release()
		end
	end)

	if not env.intro() then
		return 0
	end
	ready = true
	local started = os.clock()
	local inBand = false
	local nextSound = 0
	local nextBubble = 0
	while env.alive() and result == nil do
		local now = os.clock()
		local at = pressedAt
		if at == nil then
			if now - started >= POUR_IDLE then
				result = 0
				break
			end
			if not calm() then
				hand.Position = UDim2.fromScale(0.5, 0.66 + math.sin((now - started) * 5) * 0.03)
			end
		else
			local fill = Pure.fill(now - at, fillSeconds)
			liquid.Size = UDim2.fromScale(1, fill)
			stream.Size = UDim2.fromScale(0.05, math.max(BOTTOM - HEIGHT * (1 - NECK) * fill - 0.14, 0))
			surface.Rotation = if calm() then 0 else math.sin(now * 14) * 3
			local nowInBand = fill >= lo and fill <= hi
			if nowInBand ~= inBand then
				inBand = nowInBand
				glow.Enabled = inBand
				perfect.BackgroundTransparency = if inBand then 0.1 else 0.35
				if inBand then
					sound("Tick")
					for _, star in stars do
						punch(star, 1.6, 0.3)
					end
				end
			end
			if now >= nextSound then
				nextSound = now + POUR_SOUND_EVERY
				sound(look.Sound)
			end
			if not calm() and now >= nextBubble and fill > 0.08 then
				nextBubble = now + 0.14
				local x = 0.2 + env.r01() * 0.6
				local bubble = new("Frame", {
					Name = "Bubble",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(x, 0.97),
					Size = UDim2.fromScale(0.09, 0.09),
					SizeConstraint = Enum.SizeConstraint.RelativeXX,
					BackgroundColor3 = WHITE,
					BackgroundTransparency = 0.3,
					BorderSizePixel = 0,
					ZIndex = 4,
					Parent = body,
				})
				corner(bubble)
				local rise = play(bubble, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = UDim2.fromScale(x + (env.r01() - 0.5) * 0.1, math.max(1 - fill + 0.04, 0.1)),
					BackgroundTransparency = 1,
				})
				rise.Completed:Once(function()
					bubble:Destroy()
				end)
			end
			if fill >= 1 then
				-- Too full: a little splash over the top. Still OK.
				result = 1
				sound("Splash")
				burst(layer, UDim2.fromScale(0.5, 0.2), "💧", 5, 0.12)
				break
			end
		end
		task.wait()
	end
	local score = result or 0
	liquid.Size = UDim2.fromScale(1, score) -- exactly where it was let go
	stream.Visible = false
	if pourIcon then
		ease(vial, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = 0 })
	end
	punch(bottle, 1.12, 0.3)
	if score >= lo and score <= hi then
		burst(layer, UDim2.fromScale(0.5, 0.55), "✨", 6, 0.14)
	end
	return score
end

-- Patch: spots pop up one by one on the patient; tap each one. Score = spots tapped in time. The look picks the
-- spots (sore pink ones, or the chest's glowing ones for Listen) and what lands on each (a 🩹, a 💓, a 🔍).
local function playPatch(env: Env): number
	local cfg = tuningOf(env.Ctx, env.GameId)
	local look = env.Look
	local spots = math.clamp(math.floor(num(cfg.Spots, 3)), 1, 6)
	local seconds = math.max(num(cfg.Seconds, 4.5), 1)
	local holder = creature(env, 0.96, 0.5)
	local SPOT = 0.26 -- of the creature
	-- A spot never draws smaller than MIN_TAP (small fingers), and on a short stage that is more than SPOT of the
	-- creature: keep the spots that far apart, over most of the face, so they never overlap (Studio test 2026-11-17).
	local across = holder.AbsoluteSize.X
	local drawn = if across > 0 then math.max(SPOT, MIN_TAP / across) else SPOT
	local points = Pure.scatter(spots, { 0.18, 0.3, 0.82, 0.86 }, math.max(0.3, drawn * 1.1), env.r01)
	local glowing = look.Spot == "Glow"
	local spotColor = if glowing then GLOW else SORE
	local coreColor = if glowing then GLOW_CORE else SORE_CORE
	local mark = look.Mark or "🩹"

	type Spot = { Button: TextButton, Ring: Frame, RingStroke: UIStroke, Point: Point, Done: boolean, Born: number }
	local live: { Spot } = {}
	local patched = 0
	local ready = false

	local function patch(spot: Spot)
		if not ready or spot.Done then
			return
		end
		spot.Done = true
		patched += 1
		spot.Button.Visible = false
		local at = UDim2.fromScale(spot.Point.X, spot.Point.Y)
		local props = squareAt(SPOT * 1.25, at)
		props.Rotation = if mark == "🩹" then env.Rng:NextInteger(-28, 28) else 0
		props.ZIndex = 12
		local sticker = emoji(holder, mark, props)
		punch(sticker, 1.8, 0.22)
		punch(holder, 0.94, 0.3)
		burst(holder, at, "✨", 4, 0.12)
		sound(look.Sound)
	end

	local function spawnSpot(point: Point)
		local button = new("TextButton", squareAt(SPOT, UDim2.fromScale(point.X, point.Y)))
		button.Name = "Spot"
		button.Text = ""
		button.AutoButtonColor = false
		button.Selectable = false
		button.BackgroundColor3 = spotColor
		button.BorderSizePixel = 0
		button.ZIndex = 10
		corner(button)
		Kit.stroke(button, OUTLINE, Theme.Stroke.Bold)
		minSize(button, MIN_TAP)
		local core = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.46, 0.46),
			BackgroundColor3 = coreColor,
			BorderSizePixel = 0,
			ZIndex = 11,
			Parent = button,
		})
		corner(core)
		local ring = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 9,
			Parent = button,
		})
		corner(ring)
		local ringStroke = Kit.stroke(ring, spotColor, Theme.Stroke.Panel)
		button.Parent = holder
		punch(button, 0.2, 0.28)
		local spot: Spot =
			{ Button = button, Ring = ring, RingStroke = ringStroke, Point = point, Done = false, Born = os.clock() }
		table.insert(live, spot)
		env.onPress(button, function()
			patch(spot)
		end)
	end

	env.onAction(function(began)
		if began then
			for _, spot in live do
				if not spot.Done then
					patch(spot)
					return
				end
			end
		end
	end)

	if not env.intro() then
		return patched
	end
	ready = true
	local started = os.clock()
	local shown = 0
	while env.alive() do
		local t = os.clock() - started
		while shown < spots and t >= shown * SPOT_EVERY do
			shown += 1
			spawnSpot(points[shown])
		end
		env.drain(1 - t / seconds)
		if patched >= spots then
			burst(holder, UDim2.fromScale(0.5, 0.45), "💖", 6, 0.16)
			sound("Sparkle")
			break
		end
		if t >= seconds then
			break
		end
		-- A soft ring pulses out of each spot (still when calm).
		local quiet = calm()
		for _, spot in live do
			if not spot.Done then
				local phase = if quiet then 0 else ((os.clock() - spot.Born) * 1.4) % 1
				scaleOf(spot.Ring).Scale = 1 + phase * 0.6
				spot.RingStroke.Transparency = phase
			end
		end
		task.wait()
	end
	ready = false
	if env.alive() then
		env.drain(0)
	end
	for _, spot in live do
		if not spot.Done then
			ease(spot.Button, TweenInfo.new(0.2), { BackgroundTransparency = 1 })
		end
	end
	env.pause(0.3)
	return patched
end

-- 🛁 Scrub: bubbles pop up around the creature in its bath; pop them. Each pop washes a mud spot off.
-- Score = bubbles popped in time (it ends early once it's sparkly clean).
local function playScrub(env: Env): number
	local cfg = tuningOf(env.Ctx, env.GameId)
	local look = env.Look
	local seconds = math.max(num(cfg.Seconds, 4), 1)
	local goal = math.clamp(math.floor(num(cfg.Perfect, 6)), 1, 12)
	local layer = env.Layer
	local holder = creature(env, 0.9, 0.5)

	local tub = blob(holder, "Tub", Kit.lighten(Theme.Colors.Cyan, 0.5), {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.68),
		Size = UDim2.fromScale(1.16, 0.34),
		ZIndex = 8,
	}, UDim.new(0, 18))
	Palette.candyGradient(tub)
	for index = 0, 5 do
		local foam = new("Frame", {
			Name = "Foam",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.05 + index * 0.18, 0.04),
			Size = UDim2.fromScale(0.2, 0.2),
			SizeConstraint = Enum.SizeConstraint.RelativeXX,
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 9,
			Parent = tub,
		})
		corner(foam)
	end
	local mud: { Frame } = {}
	for _, point in Pure.scatter(goal, { 0.32, 0.34, 0.68, 0.62 }, 0.12, env.r01) do
		local splotch = new("Frame", squareAt(0.13, UDim2.fromScale(point.X, point.Y)))
		splotch.Name = "Mud"
		splotch.BackgroundColor3 = MUD
		splotch.BackgroundTransparency = 0.1
		splotch.BorderSizePixel = 0
		splotch.ZIndex = 7
		corner(splotch)
		splotch.Parent = holder
		table.insert(mud, splotch)
	end
	local counter = blob(layer, "Count", WHITE, {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(0.02, 0.03),
		Size = UDim2.fromScale(0.42, 0.17),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = 30,
	})
	local counterText = Kit.label({
		Text = "🧼 0",
		TextScaled = true,
		TextWrapped = false,
		Size = UDim2.fromScale(0.9, 0.8),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 31,
		Parent = counter,
	})

	-- Where bubbles may appear (stage scale), so two never sit on top of each other.
	local SLOTS: { Point } = {
		{ X = 0.16, Y = 0.3 },
		{ X = 0.5, Y = 0.2 },
		{ X = 0.84, Y = 0.3 },
		{ X = 0.16, Y = 0.72 },
		{ X = 0.5, Y = 0.8 },
		{ X = 0.84, Y = 0.72 },
	}
	type Bubble = { Button: TextButton, Slot: number, Born: number, X: number, Y: number, Popped: boolean }
	local live: { Bubble } = {}
	local busy: { [number]: boolean } = {}
	local popped = 0
	local ready = false

	local function remove(bubble: Bubble)
		local index = table.find(live, bubble)
		if index then
			table.remove(live, index)
		end
		busy[bubble.Slot] = nil
	end

	local function vanish(bubble: Bubble, burstToo: boolean)
		local button = bubble.Button
		button.Interactable = false
		if calm() then
			button:Destroy()
			return
		end
		local info = TweenInfo.new(if burstToo then 0.12 else 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		play(scaleOf(button), info, { Scale = if burstToo then 1.4 else 0.6 })
		play(button, info, { BackgroundTransparency = 1 })
		for _, child in button:GetDescendants() do
			if child:IsA("UIStroke") then
				play(child, info, { Transparency = 1 })
			elseif child:IsA("Frame") then
				play(child, info, { BackgroundTransparency = 1 })
			end
		end
		task.delay(0.22, function()
			button:Destroy()
		end)
	end

	local function pop(bubble: Bubble)
		if not ready or bubble.Popped then
			return
		end
		bubble.Popped = true
		remove(bubble)
		popped += 1
		vanish(bubble, true)
		burst(layer, UDim2.fromScale(bubble.X, bubble.Y), "💧", 4, 0.09)
		local splotch = mud[popped]
		if splotch then
			ease(splotch, TweenInfo.new(0.25), { BackgroundTransparency = 1 })
			burst(holder, splotch.Position, "✨", 3, 0.1)
		end
		counterText.Text = "🧼 " .. popped
		punch(counter, 1.3, 0.25)
		sound(look.Sound)
	end

	local function spawnBubble(slot: number)
		local point = SLOTS[slot]
		local x = point.X + (env.r01() - 0.5) * 0.06
		local y = point.Y + (env.r01() - 0.5) * 0.06
		local button = new("TextButton", squareAt(0.28, UDim2.fromScale(x, y)))
		button.Name = "Bubble"
		button.Text = ""
		button.AutoButtonColor = false
		button.Selectable = false
		button.BackgroundColor3 = BUBBLE
		button.BackgroundTransparency = 0.15
		button.BorderSizePixel = 0
		button.ZIndex = 20
		corner(button)
		Kit.stroke(button, OUTLINE, Theme.Stroke.Bold)
		minSize(button, MIN_TAP + 4)
		local shine = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.32, 0.3),
			Size = UDim2.fromScale(0.28, 0.28),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.05,
			BorderSizePixel = 0,
			ZIndex = 21,
			Parent = button,
		})
		corner(shine)
		button.Parent = layer
		punch(button, 0.2, 0.25)
		local bubble: Bubble = { Button = button, Slot = slot, Born = os.clock(), X = x, Y = y, Popped = false }
		busy[slot] = true
		table.insert(live, bubble)
		env.onPress(button, function()
			pop(bubble)
		end)
	end

	env.onAction(function(began)
		local oldest = live[1]
		if began and oldest then
			pop(oldest)
		end
	end)

	if not env.intro() then
		return popped
	end
	ready = true
	local started = os.clock()
	local nextSpawn = 0
	while env.alive() do
		local now = os.clock()
		local t = now - started
		if t >= nextSpawn and #live < BUBBLE_MAX and t <= seconds - 0.6 then
			local slot = Pure.freeSlot(#SLOTS, busy, env.r01)
			if slot then
				spawnBubble(slot)
				nextSpawn = t + BUBBLE_EVERY
			end
		end
		local quiet = calm()
		for index = #live, 1, -1 do
			local bubble = live[index]
			local age = now - bubble.Born
			if age >= BUBBLE_LIFE then
				remove(bubble)
				vanish(bubble, false)
			elseif not quiet then
				bubble.Button.Position = UDim2.fromScale(bubble.X, bubble.Y - 0.06 * age / BUBBLE_LIFE)
				bubble.Button.Rotation = math.sin(age * 5) * 6
			end
		end
		env.drain(1 - t / seconds)
		if popped >= goal then
			burst(holder, UDim2.fromScale(0.5, 0.45), "✨", 8, 0.14)
			sound("Sparkle")
			break
		end
		if t >= seconds then
			break
		end
		task.wait()
	end
	ready = false
	if env.alive() then
		env.drain(0)
	end
	for index = #live, 1, -1 do
		local bubble = live[index]
		remove(bubble)
		vanish(bubble, false)
	end
	env.pause(0.3)
	return popped
end

-- A beat game's scene (the Cool engine's two skins): frame(t, hot) draws each moment of a beat, start() readies the
-- next beat, done(good) clears it; Hit is where a good beat bursts and Prop what bounces then.
type Scene = {
	frame: (t: number, hot: boolean) -> (),
	start: () -> (),
	done: (result: boolean?) -> (),
	Hit: UDim2,
	Prop: GuiObject,
}

-- "Ring": a ring grows from the middle and is biggest halfway (☕ the cocoa's steam; 🔦 a light ring over the
-- patient's face, lining up with the ear or the mouth).
local function ringScene(env: Env, pulse: number, _window: number): Scene
	local layer = env.Layer
	local look = env.Look
	local face = look.Target == "Face"
	local RING_Y, RING = if face then 0.46 else 0.38, if face then 0.62 else 0.54
	local ringColor = if face then BEAM else STEAM
	local prop: GuiObject
	if face then
		prop = creature(env, 0.92, 0.5)
	else
		local mug = blob(layer, "Mug", Kit.lighten(Theme.Colors.Primary, 0.08), {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.97),
			Size = UDim2.fromScale(0.4, 0.3),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			ZIndex = 3,
		}, UDim.new(0, 14))
		Palette.candyGradient(mug)
		Kit.gloss(mug, 8)
		local handle = blob(mug, "Handle", Kit.lighten(Theme.Colors.Primary, 0.08), {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.9, 0.5),
			Size = UDim2.fromScale(0.3, 0.56),
			ZIndex = 2,
		}, UDim.new(0.5, 0))
		blob(handle, "Hole", Theme.Colors.PaperEdge, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.4, 0.5),
			ZIndex = 2,
		}, UDim.new(0.5, 0))
		blob(mug, "Cocoa", COCOA, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.1),
			Size = UDim2.fromScale(0.84, 0.2),
			ZIndex = 4,
		})
		prop = mug
	end

	local target = new("Frame", squareAt(RING, UDim2.fromScale(0.5, RING_Y)))
	target.Name = "Target"
	target.BackgroundTransparency = 1
	target.ZIndex = 4
	corner(target)
	local targetStroke = Kit.stroke(target, Theme.Colors.InkSoft, Theme.Stroke.Panel)
	targetStroke.Transparency = 0.55
	target.Parent = layer
	local steam = blob(layer, "Ring", ringColor, squareAt(RING * RING_MIN, UDim2.fromScale(0.5, RING_Y)))
	steam.BackgroundTransparency = if face then 0.45 else 0.2
	steam.ZIndex = 5
	steam.Visible = false
	local steamStroke = steam:FindFirstChildOfClass("UIStroke") :: UIStroke
	local size = RING_MIN

	return {
		Hit = UDim2.fromScale(0.5, RING_Y),
		Prop = prop,
		start = function()
			steam.Visible = true
			steam.BackgroundTransparency = if face then 0.45 else 0.2
			steamStroke.Transparency = 0
			size = RING_MIN
		end,
		frame = function(t: number, hot: boolean)
			size = Pure.ring(t, pulse, RING_MIN)
			steam.Size = UDim2.fromScale(RING * size, RING * size)
			steam.BackgroundColor3 = if hot then Kit.lighten(Theme.Colors.Collect, 0.35) else ringColor
			steamStroke.Thickness = if hot then Theme.Stroke.Panel else Theme.Stroke.Bold
			targetStroke.Color = if hot then Theme.Colors.Collect else Theme.Colors.InkSoft
			targetStroke.Transparency = if hot then 0 else 0.55
		end,
		done = function(result: boolean?)
			targetStroke.Color = Theme.Colors.InkSoft
			targetStroke.Transparency = 0.55
			if result ~= nil and look.Target == "Mug" and not calm() then
				-- A puff of breath flies up at the steam.
				local puffProps = squareAt(0.18, UDim2.fromScale(0.5, 0.92))
				puffProps.ZIndex = 9
				local puff = emoji(layer, "💨", puffProps)
				local fly = play(puff, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = UDim2.fromScale(0.5, RING_Y),
					TextTransparency = 1,
				})
				fly.Completed:Once(function()
					puff:Destroy()
				end)
			end
			-- The ring puffs away (it just fades when calm).
			local grow = math.clamp(size * 1.3, 0, 1.4)
			local fade = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			if not calm() then
				play(steam, fade, { Size = UDim2.fromScale(RING * grow, RING * grow), BackgroundTransparency = 1 })
			else
				play(steam, fade, { BackgroundTransparency = 1 })
			end
			play(steamStroke, fade, { Transparency = 1 })
		end,
	}
end

-- "Sweep": a bar crosses the stage and is in the middle halfway; the green zone round the middle is where a tap is
-- good (Pure.sweepZone: the same rule as the ring). 📸 the X-ray's scanner over the bone; 🧻 🦴 a wrap going round.
local function sweepScene(env: Env, pulse: number, window: number): Scene
	local layer = env.Layer
	local look = env.Look
	local X0, X1, MID = 0.08, 0.92, 0.56
	local barColor = if env.GameId == "XRay" then SCAN else WHITE
	blob(layer, "Track", Theme.Colors.Card, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, MID),
		Size = UDim2.fromScale(X1 - X0 + 0.06, 0.56),
		ZIndex = 2,
	}, Theme.Radius.Medium)
	local zoneHalf = (X1 - X0) * Pure.sweepZone(pulse, window)
	local zone = new("Frame", {
		Name = "Zone",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, MID),
		Size = UDim2.fromScale(zoneHalf * 2, 0.56),
		BackgroundColor3 = Theme.Colors.Collect,
		BackgroundTransparency = 0.65,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = layer,
	})
	corner(zone, Theme.Radius.Small)
	local targetProps = squareAt(0.44, UDim2.fromScale(0.5, MID))
	targetProps.ZIndex = 4
	local target = emoji(layer, look.Target or look.Icon, targetProps)
	local bar = new("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(X0, MID),
		Size = UDim2.new(0, 14, 0.74, 0),
		BackgroundColor3 = barColor,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 6,
		Parent = layer,
	})
	corner(bar, Theme.Radius.Small)
	Kit.stroke(bar, OUTLINE, Theme.Stroke.Bold)

	return {
		Hit = UDim2.fromScale(0.5, MID),
		Prop = target,
		start = function()
			bar.Visible = true
			bar.Position = UDim2.fromScale(X0, MID)
			bar.BackgroundColor3 = barColor
		end,
		frame = function(t: number, hot: boolean)
			bar.Position = UDim2.fromScale(X0 + (X1 - X0) * Pure.sweep(t, pulse), MID)
			bar.BackgroundColor3 = if hot then Kit.lighten(Theme.Colors.Collect, 0.35) else barColor
			zone.BackgroundTransparency = if hot then 0.35 else 0.65
		end,
		done = function(_result: boolean?)
			zone.BackgroundTransparency = 0.65
			ease(
				bar,
				TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ BackgroundTransparency = 1 }
			)
			task.delay(0.22, function()
				if bar.Parent then
					bar.Visible = false
					bar.BackgroundTransparency = 0
				end
			end)
		end,
	}
end

-- Cool: Blows beats, one after another; tap as each is at its middle. Score = good beats. The look picks the scene
-- ("Ring" or "Sweep") and the pips: its Good mark for a good beat, its Miss mark for the rest.
local function playCool(env: Env): number
	local cfg = tuningOf(env.Ctx, env.GameId)
	local look = env.Look
	local blows = math.clamp(math.floor(num(cfg.Blows, 3)), 1, 6)
	local pulse = math.max(num(cfg.PulseSeconds, 1.2), 0.4)
	local window = math.max(num(cfg.Window, 0.3), 0.05)
	local layer = env.Layer
	local scene = if look.Style == "Sweep" then sweepScene(env, pulse, window) else ringScene(env, pulse, window)
	local goodMark, missMark = look.Good or "❄️", look.Miss or "💨"

	-- One pip per beat, top left: the Good mark for a good one, the Miss mark for the rest.
	local pips = new("Frame", {
		Name = "Pips",
		Position = UDim2.fromScale(0.02, 0.03),
		Size = UDim2.fromScale(1, 0.14),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = layer,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = pips,
	})
	local pipLabels: { TextLabel } = {}
	for index = 1, blows do
		local pip = blob(pips, "Pip", Theme.Colors.Card, {
			LayoutOrder = index,
			Size = UDim2.fromScale(1, 1),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			ZIndex = 6,
		})
		table.insert(
			pipLabels,
			emoji(pip, "", {
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.78, 0.78),
				ZIndex = 7,
			})
		)
	end

	local request = false
	local open = false
	local beatStarted = 0
	local function tap()
		if open and os.clock() - beatStarted >= COOL_GRACE then
			request = true
		end
	end
	env.onPress(env.Catcher, function()
		tap()
	end)
	env.onAction(function(began)
		if began then
			tap()
		end
	end)

	if not env.intro() then
		return 0
	end
	local good = 0
	for index = 1, blows do
		beatStarted = os.clock()
		request = false
		open = true
		scene.start()
		local ticked = false
		local result: boolean? = nil -- true = a good beat, false = a tap off the beat, nil = no tap
		while env.alive() do
			local t = os.clock() - beatStarted
			if request then
				result = Pure.goodBlow(t, pulse, window)
				break
			end
			if t >= pulse then
				break
			end
			scene.frame(t, Pure.goodBlow(t, pulse, window))
			if not ticked and t >= pulse / 2 then
				ticked = true
				sound("Tick")
			end
			task.wait()
		end
		open = false
		if not env.alive() then
			return good
		end
		if result ~= nil then
			sound(look.Sound)
		end
		local pip = pipLabels[index]
		if result == true then
			good += 1
			pip.Text = goodMark
			burst(layer, scene.Hit, goodMark, 6, 0.1)
			punch(scene.Prop, 1.12, 0.3)
		else
			pip.Text = missMark
			if pip.Parent and pip.Parent:IsA("GuiObject") then
				pip.Parent.BackgroundColor3 = Theme.Colors.Disabled
			end
		end
		if pip.Parent and pip.Parent:IsA("GuiObject") then
			punch(pip.Parent, 1.35, 0.3)
		end
		scene.done(result)
		if not env.pause(COOL_GAP) then
			return good
		end
	end
	return good
end

-- One target of a Pick: an exam tool on a card, or a medicine bottle in its colour. Name: the words under a bottle
-- (the dispensary's "Which one?" only: there the player chooses by what the patient needs, so each bottle says what
-- it is; on the shelf the header names the one to find).
type PickChoice = { Id: string, Icon: string, Fill: Color3?, Bottle: boolean?, Name: string? }

-- A wrong pick shakes its head (still when calm).
local function shake(gui: GuiObject)
	if calm() then
		return
	end
	task.spawn(function()
		local step = PICK_SHAKE / 5
		for _, angle in { -14, 12, -8, 5, 0 } do
			if not gui.Parent then
				return
			end
			play(gui, TweenInfo.new(step, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Rotation = angle })
			task.wait(step)
		end
	end)
end

-- Shows `choices` as big targets laid out by Pure.pickRects on the stage's real size, and waits for a right one
-- (isRight). A wrong tap shakes its head, says "Hmm, not that one!", greys out and can't be tapped again: never a
-- fail. glowId's target glows (the right tool, for a first exam). Taps, the mouse and the gamepad (A presses the
-- selected target; Space only stops the character jumping meanwhile). Returns the wrong taps and the id picked.
local function pickLoop(
	env: Env,
	choices: { PickChoice },
	isRight: (id: string) -> boolean,
	glowId: string?
): (number, string?)
	local layer = env.Layer
	local stage = env.View.Stage
	local wrong = 0
	local picked: string? = nil
	local ready = false
	local buttons: { TextButton } = {}
	local glowing: TextButton? = nil

	local function layout()
		local rects = Pure.pickRects(stage.AbsoluteSize, #buttons)
		for index, button in buttons do
			local rect = rects[index]
			if rect then
				button.Position = UDim2.fromOffset(rect.X + rect.W / 2, rect.Y + rect.H / 2)
				button.Size = UDim2.fromOffset(rect.W, rect.H)
			end
		end
	end

	local function focusNext()
		if not usesGamepad() then
			return
		end
		for _, button in buttons do
			if button.Interactable then
				GuiService.SelectedObject = button
				return
			end
		end
	end

	local function choose(index: number)
		local button = buttons[index]
		local choice = choices[index]
		if not ready or picked ~= nil or not button or not button.Interactable then
			return
		end
		if isRight(choice.Id) then
			picked = choice.Id
			sound(env.Look.Sound)
			punch(button, 1.25, 0.3)
			burst(button, UDim2.fromScale(0.5, 0.5), "✨", 6, 0.4)
			return
		end
		wrong += 1
		sound("Nope")
		setHint(env.View, Pure.WORDS.Wrong)
		button.Interactable = false
		button.Selectable = false
		button.BackgroundTransparency = 0.5
		for _, child in button:GetDescendants() do
			if child:IsA("TextLabel") then
				child.TextTransparency = 0.5
			elseif child:IsA("Frame") then
				child.BackgroundTransparency = 0.5
			end
		end
		shake(button)
		if GuiService.SelectedObject == button then
			focusNext()
		end
	end

	for index, choice in choices do
		local button = new("TextButton", {
			Name = "Choice" .. index,
			Text = "",
			AutoButtonColor = false,
			Selectable = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(Pure.TAP_MIN, Pure.TAP_MIN),
			BackgroundColor3 = if choice.Bottle then WHITE else Theme.Colors.Card,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = layer,
		})
		corner(button, Theme.Radius.Medium)
		local stroke = Kit.stroke(button, OUTLINE, Theme.Stroke.Bold)
		if choice.Bottle then
			-- A little bottle: its cap, and its body in the medicine's colour with the medicine's icon on it.
			-- A named bottle is shorter, with its name ("Cough syrup", two short lines) on the card under it.
			local named = type(choice.Name) == "string" and choice.Name ~= ""
			blob(button, "Cap", Theme.Colors.InkSoft, {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, if named then 0.04 else 0.08),
				Size = UDim2.fromScale(0.3, if named then 0.12 else 0.16),
				ZIndex = 4,
			}, Theme.Radius.Small)
			if named then
				new("TextLabel", {
					Name = "Label",
					BackgroundTransparency = 1,
					Text = choice.Name,
					TextScaled = true,
					TextWrapped = true,
					Font = Theme.Font,
					TextColor3 = Theme.Colors.Ink,
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.fromScale(0.5, 0.99),
					Size = UDim2.fromScale(0.94, 0.38),
					ZIndex = 5,
					Parent = button,
				})
			end
			local body = blob(button, "Body", choice.Fill or Theme.Colors.Pink, {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, if named then 0.6 else 0.92),
				Size = UDim2.fromScale(if named then 0.5 else 0.64, if named then 0.46 else 0.66),
				ZIndex = 4,
			}, Theme.Radius.Small)
			emoji(body, choice.Icon, {
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.78, 0.78),
				ZIndex = 5,
			})
		else
			emoji(button, choice.Icon, {
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.68, 0.68),
				ZIndex = 4,
			})
		end
		if glowId ~= nil and choice.Id == glowId then
			-- The right one glows: a gold outline and a sparkle (it breathes a little unless motion is calm).
			stroke.Color = Theme.Colors.Cash
			stroke.Thickness = Theme.Stroke.Panel
			emoji(button, "✨", {
				Position = UDim2.fromScale(0.84, 0.16),
				Size = UDim2.fromScale(0.36, 0.36),
				ZIndex = 6,
			})
			glowing = button
		end
		env.track(button.Activated:Connect(function()
			choose(index)
		end))
		table.insert(buttons, button)
	end
	layout()
	env.track(stage:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))

	-- The gamepad's A presses the selected target, so the card's own A steps aside (Space stays, doing nothing).
	bindPlay(false)
	env.onAction(nil)
	if not env.intro() then
		return wrong, picked
	end
	ready = true
	focusNext()
	local started = os.clock()
	while env.alive() and picked == nil do
		local glow = glowing
		if glow and not calm() then
			scaleOf(glow).Scale = 1 + 0.05 * math.sin((os.clock() - started) * 5)
		end
		task.wait()
	end
	ready = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(layer) then
		GuiService.SelectedObject = nil
	end
	if env.Run.Alive and current == env.Run then
		bindPlay(true)
	end
	env.pause(0.3)
	return wrong, picked
end

-- Pick: tap the right one of `choices` (`answer`); it glows when `glow`. Score = the wrong taps (Logic/MiniGame.rate:
-- 0 Perfect, 1 Good, more OK).
local function playPick(env: Env, choices: { PickChoice }, answer: string, glow: boolean): number
	local wrong = pickLoop(env, choices, function(id: string): boolean
		return id == answer
	end, if glow then answer else nil)
	return wrong
end

-- The medicines on the shelf (Data/Items Kind "Medicine", in their order) for Pure.bottles.
local function medicinePool(ctx: Types.Ctx): { { Id: string, Icon: string } }
	local items = (ctx.Data :: any).Items
	local pool: { { Id: string, Icon: string } } = {}
	if type(items) ~= "table" then
		return pool
	end
	local order = items.Order
	if type(order) ~= "table" then
		order = {}
		for id in items do
			table.insert(order, id)
		end
		table.sort(order)
	end
	for _, id in order do
		local item = dataRow(ctx, "Items", id)
		if item and item.Kind == "Medicine" then
			table.insert(pool, { Id = id, Icon = if type(item.Icon) == "string" then item.Icon else "💊" })
		end
	end
	return pool
end

local function medicineChoice(ctx: Types.Ctx, id: string): PickChoice
	local item = dataRow(ctx, "Items", id)
	return {
		Id = id,
		Icon = if item and type(item.Icon) == "string" then item.Icon else "💊",
		Fill = hexColor(if item then item.Bottle else nil, Theme.Colors.Pink),
		Bottle = true,
	}
end

-- The Pick routine (Pure.dispatch's "Pick"): the exam card's tools, or the dispensary's shelf of bottles. A Pick
-- with nothing sensible to show (a junk session) plays as one tap.
local playTap: (env: Env) -> number
local function playPickGame(env: Env): number
	local ctx, session, run = env.Ctx, env.Session, env.Run
	if session.Kind == "Dispense" then
		local choice = run.Choice
		if choice == nil then
			return playTap(env)
		end
		local dispensary = (ctx.Config :: any).Dispensary
		local count = if type(dispensary) == "table" then num(dispensary.Bottles, 4) else 4
		local choices: { PickChoice } = {}
		for _, id in Pure.bottles(choice, medicinePool(ctx), count, env.r01) do
			table.insert(choices, medicineChoice(ctx, id))
		end
		return playPick(env, choices, choice, session.Glow)
	end
	local ids = Pure.choices(session.Tools, session.Answer)
	local answer = session.Answer
	if ids == nil or answer == nil then
		return playTap(env)
	end
	local choices: { PickChoice } = {}
	for _, id in ids do
		local tool = dataRow(ctx, "Tools", id)
		table.insert(choices, { Id = id, Icon = if tool and type(tool.Icon) == "string" then tool.Icon else "❓" })
	end
	return playPick(env, choices, answer, session.Glow)
end

-- One big tap (Simple mode, or a game this client can't draw). Always scores; Simple rates it Good.
playTap = function(env: Env): number
	local look = env.Look
	local layer = env.Layer
	local iconProps = squareAt(0.46, UDim2.fromScale(0.5, 0.36))
	iconProps.ZIndex = 3
	local icon = emoji(layer, look.Icon, iconProps)
	-- A Collect button (taking help is free): the one shine on screen.
	local mark = pointer()
	local button = Kit.button({
		Name = "Tap",
		Kind = "Collect",
		Text = if mark ~= "" then mark .. " Tap!" else "Tap!",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(0.62, 0, 0, 72),
		ZIndex = 4,
		Parent = layer,
	})
	Kit.textLimit(button, Theme.TextSize.Title)
	if padImage() then
		-- The pad's own button picture at the left end (✕ on PlayStation, A on Xbox).
		pressMark(button, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, Theme.Space.PadCard, 0.5, 0),
			Size = UDim2.fromOffset(40, 40),
			ZIndex = 5,
		})
	end
	local stopShine = Kit.shine(button)
	local tapped = false
	local ready = false
	local function tap()
		if ready and not tapped then
			tapped = true
		end
	end
	env.track(button.Activated:Connect(tap))
	env.onPress(env.Catcher, function()
		tap()
	end)
	env.onAction(function(began)
		if began then
			tap()
		end
	end)
	if not env.intro() then
		stopShine()
		return 1
	end
	ready = true
	local started = os.clock()
	while env.alive() and not tapped do
		if not calm() then
			icon.Position = UDim2.fromScale(0.5, 0.36 + math.sin((os.clock() - started) * 3) * 0.02)
		end
		task.wait()
	end
	stopShine()
	if tapped then
		sound(look.Sound)
		punch(icon, 1.45, 0.35)
		burst(layer, icon.Position, "✨", 6, 0.12)
		env.pause(0.3)
	end
	return 1
end

-- The routine for each Pure.dispatch answer: one per engine, and the one big tap.
local PLAY: { [string]: (env: Env) -> number } = {
	Pour = playPour,
	Patch = playPatch,
	Scrub = playScrub,
	Cool = playCool,
	Pick = playPickGame,
	Tap = playTap,
}

------------------------------------------------------------------------------------------------------------------
-- The session
------------------------------------------------------------------------------------------------------------------

-- Builds a fresh layer on the stage with everything a game needs (the Env), runs fn on it (protected), then clears
-- the layer, its connections and its keyboard/gamepad handler. Returns pcall's results.
local function withStage(
	ctx: Types.Ctx,
	v: View,
	run: Run,
	name: string,
	gameId: string,
	look: GameLook,
	fn: (env: Env) -> ...any
): (boolean, ...any)
	local layer = new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = v.Stage,
	})
	-- Taps anywhere on the stage (under everything the game draws; drawn Frames and labels let taps through).
	local catcher = new("TextButton", {
		Name = "Catcher",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = layer,
	})
	local connections: { RBXScriptConnection } = {}
	local finished = false
	local ownHandler: ((boolean) -> ())? = nil
	local function cleanup()
		if finished then
			return
		end
		finished = true
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		-- Only clear the keyboard/gamepad handler if it is still this game's (a newer run may own it now).
		if ownHandler ~= nil and actionHandler == ownHandler then
			actionHandler = nil
		end
		layer:Destroy()
	end
	table.insert(run.Cleanups, cleanup)

	local function alive(): boolean
		return run.Alive and not finished
	end
	local function track(connection: RBXScriptConnection)
		table.insert(connections, connection)
	end
	local env: Env = {
		Ctx = ctx,
		Session = run.Session,
		View = v,
		Layer = layer,
		Catcher = catcher,
		Rng = run.Rng,
		Run = run,
		GameId = gameId,
		Look = look,
		alive = alive,
		track = track,
		intro = function(): boolean
			punch(layer, 0.6, 0.35)
			task.wait(INTRO)
			return alive()
		end,
		pause = function(seconds: number): boolean
			task.wait(seconds)
			return alive()
		end,
		onPress = function(gui: GuiObject, onDown: (input: InputObject) -> ())
			track(gui.InputBegan:Connect(function(input: InputObject)
				local kind = input.UserInputType
				if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
					onDown(input)
				end
			end))
		end,
		onAction = function(handler: ((began: boolean) -> ())?)
			if alive() then
				ownHandler = handler
				actionHandler = handler
			end
		end,
		drain = function(share: number)
			if alive() then
				setTime(v, Pure.drainBar(share, run.HideDrain))
			end
		end,
		r01 = function(): number
			return run.Rng:NextNumber()
		end,
	}

	local results = table.pack(pcall(fn, env))
	local slot = table.find(run.Cleanups, cleanup)
	if slot then
		table.remove(run.Cleanups, slot)
	end
	cleanup()
	return table.unpack(results, 1, results.n)
end

-- The right answer's icon for a Pick played as one tap (Simple mode): the right tool, or the medicine's bottle.
local function answerIcon(ctx: Types.Ctx, run: Run): string?
	local session = run.Session
	if session.Kind == "Dispense" then
		local item = dataRow(ctx, "Items", run.Choice)
		return if item and type(item.Icon) == "string" then item.Icon else nil
	end
	local tool = dataRow(ctx, "Tools", session.Answer)
	return if tool and type(tool.Icon) == "string" then tool.Icon else nil
end

-- A Pick's header and hint: the exam's "🤔 Which tool?" (the symptom as a clue, or "✨ The shiny one!" while the
-- right tool glows), or the medicine to find on the shelf.
local function pickWords(ctx: Types.Ctx, run: Run): (string, string, string)
	local session = run.Session
	local words = Pure.WORDS
	if session.Kind == "Dispense" then
		local item = dataRow(ctx, "Items", run.Choice)
		if item then
			return item.Icon, item.Name, words.FindHint
		end
		return words.ChooseIcon, Pure.LOOKS.Pick.Title, words.FindHint
	end
	local hint = if session.Glow
		then words.GlowHint
		elseif session.Symptom ~= "" then session.Symptom
		else words.ExamHint
	return words.ExamIcon, words.ExamTitle, hint
end

-- Plays one game and returns its rating.
local function playOne(ctx: Types.Ctx, v: View, run: Run, index: number, gameId: string): string
	local session = run.Session
	local route = Pure.dispatch(gameId, MiniGame.ENGINE, session.Simple)
	local look = GAME_LOOK[gameId] or TAP_LOOK
	if route == "Tap" and gameId == "Pick" then
		-- Simple mode's Pick is one tap on the right tool or bottle.
		local icon = answerIcon(ctx, run)
		if icon then
			look = table.clone(look)
			look.Icon = icon
		end
	end
	if route == "Pick" then
		local icon, title, hint = pickWords(ctx, run)
		setHeader(v, icon, title, look.Color)
		setHint(v, hint)
	else
		setHeader(v, look.Icon, if route == "Tap" then TAP_LOOK.Title else look.Title, look.Color)
		setHint(v, if route == "Tap" then TAP_LOOK.Hint else look.Hint, true)
	end
	setTime(v, nil)
	markStep(v, index, nil)

	local ok, score: any = withStage(ctx, v, run, "Game" .. index, gameId, look, PLAY[route] or PLAY.Tap)
	if run.Alive then
		setTime(v, nil)
	end
	if not ok then
		warn("[MiniGames] " .. gameId .. " broke, rated Good: " .. tostring(score))
		return "Good"
	end
	if route == "Tap" then
		return "Good"
	end
	-- Rated against the same (eased) windows the game was drawn with.
	return MiniGame.rate(gameId, if type(score) == "number" then score else 0, { MiniGame = miniOf(ctx) })
end

-- The Dispense card's first question when bay patients need several medicines: which one to make (any is right:
-- each one is needed). One needed, or Simple mode: the first, without asking. Returns the medicine's ItemId (nil only
-- when the session offers nothing this client knows: the server then gives nothing and rates it OK).
local CHOOSE_LOOK: GameLook = lookOf({
	Icon = Pure.WORDS.ChooseIcon,
	Title = Pure.WORDS.ChooseTitle,
	Hint = Pure.WORDS.ChooseHint,
	Sound = "Found",
	Tint = "Purple",
})
local function chooseMedicine(ctx: Types.Ctx, v: View, run: Run): string?
	local session = run.Session
	local options: { string } = {}
	for _, id in session.Options do
		local item = dataRow(ctx, "Items", id)
		if item and item.Kind == "Medicine" then
			table.insert(options, id)
		end
	end
	if #options == 0 then
		return session.Options[1]
	elseif #options == 1 or session.Simple then
		return options[1]
	end
	setHeader(v, CHOOSE_LOOK.Icon, CHOOSE_LOOK.Title, CHOOSE_LOOK.Color)
	setHint(v, CHOOSE_LOOK.Hint)
	setTime(v, nil)
	local choices: { PickChoice } = {}
	for _, id in options do
		local choice = medicineChoice(ctx, id)
		local item = dataRow(ctx, "Items", id)
		choice.Name = if item and type(item.Name) == "string" then item.Name else nil
		table.insert(choices, choice)
	end
	local ok, first, picked = withStage(ctx, v, run, "Choose", "", CHOOSE_LOOK, function(env: Env): (number, string?)
		return pickLoop(env, choices, function(): boolean
			return true
		end, nil)
	end)
	if not ok then
		warn("[MiniGames] the medicine choice broke: " .. tostring(first))
	end
	return if ok and type(picked) == "string" then picked else options[1]
end

-- A game an ability already made PERFECT (TreatSession.Auto: Golden Touch, Quick Plaster, Quick Soap): its icon
-- sparkles on the stage for a moment, then the run goes on (the server rates it Perfect whatever is reported).
local function playAuto(v: View, run: Run, index: number, gameId: string): string
	local look = GAME_LOOK[gameId] or TAP_LOOK
	setHeader(v, "✨", "Magic help!", Theme.Colors.Cash)
	setHint(v, look.Icon .. " ✨ Done for you!")
	setTime(v, nil)
	markStep(v, index, nil)
	local layer = new("Frame", {
		Name = "Auto" .. index,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = v.Stage,
	})
	local function cleanup()
		layer:Destroy()
	end
	table.insert(run.Cleanups, cleanup)
	local glow = blob(layer, "Glow", Kit.lighten(Theme.Colors.Cash, 0.35), squareAt(0.62, UDim2.fromScale(0.5, 0.48)))
	glow.ZIndex = 3
	Kit.gloss(glow, 10)
	local icon = emoji(glow, look.Icon, { Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.7, 0.7) })
	icon.ZIndex = 4
	punch(glow, 0.4, 0.4)
	burst(layer, UDim2.fromScale(0.5, 0.48), "✨", 10, 0.18)
	sound("Sparkle")
	waitFor(run, if calm() then AUTO_HOLD * 0.6 else AUTO_HOLD)
	local slot = table.find(run.Cleanups, cleanup)
	if slot then
		table.remove(run.Cleanups, slot)
	end
	cleanup()
	return "Perfect"
end

-- The card after the last game: one chip per game with its rating, the tip, and what's next.
local function showResults(ctx: Types.Ctx, v: View, run: Run, ratings: { string }, outcome: any?)
	local old = v.Stage:FindFirstChild("Results")
	if old then
		old:Destroy()
	end
	local layer = new("Frame", {
		Name = "Results",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = v.Stage,
	})
	table.insert(run.Cleanups, function()
		layer:Destroy()
	end)
	local row = new("Frame", {
		Name = "Row",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.96, 0.46),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = layer,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	for index in run.Session.Games do
		local rating = RATING_LOOK[ratings[index]] or RATING_LOOK.OK
		local magic = run.Session.Auto[index] == true
		local chip = blob(row, "Chip" .. index, Kit.lighten(rating.Color, 0.1), {
			LayoutOrder = index,
			Size = UDim2.fromScale(1, 1),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			ZIndex = 3,
		}, Theme.Radius.Medium)
		Kit.gloss(chip, 8)
		emoji(chip, stepIcon(ctx, run, index), {
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromScale(0.62, 0.62),
			ZIndex = 4,
		})
		emoji(chip, if magic then "✨" else rating.Icon, {
			Position = UDim2.fromScale(0.86, 0.86),
			Size = UDim2.fromScale(0.42, 0.42),
			ZIndex = 5,
		})
		punch(chip, 0.5, 0.3 + index * 0.06)
	end
	local tip = if type(outcome) == "table" then finite(outcome.Tip) else nil
	if tip and tip > 0 then
		local tipLabel = Kit.label({
			Name = "Tip",
			Text = "💰 +" .. Hud.format(math.floor(tip)),
			Outlined = true,
			TextScaled = true,
			TextWrapped = false,
			TextColor3 = Theme.Colors.Cash,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.86),
			Size = UDim2.fromScale(0.8, 0.22),
			ZIndex = 4,
			Parent = layer,
		})
		Kit.outline(tipLabel, Theme.Stroke.Bold)
		Kit.textLimit(tipLabel, 44)
		punch(tipLabel, 1.5, 0.35)
	end
	local words = Pure.WORDS
	local kind = run.Session.Kind
	if type(outcome) ~= "table" then
		setHeader(v, "✨", words.Nice, Theme.Colors.Collect)
		setHint(v, "")
	elseif kind == "Dispense" then
		-- The medicine is in your hands now: off to the bay with it.
		local item = dataRow(ctx, "Items", outcome.Item)
		if item and type(item.Icon) == "string" then
			setHeader(v, item.Icon, words.Ready, Theme.Colors.Collect)
			setHint(v, words.ToBay)
		else
			setHeader(v, "👍", words.Nice, CALM_BLUE)
			setHint(v, "")
		end
	elseif outcome.Complete == true then
		setHeader(v, "💖", words.Better, Theme.Colors.Collect)
		setHint(v, words.BetterHint)
	else
		setHeader(v, "👍", words.Nice, CALM_BLUE)
		setHint(v, words.NextHint)
	end
end

-- The case's plan as the exam reveals it: the server's own (TreatOutcome.Plan, when it sends one), else the case's
-- plan cut to this clinic's level (Logic/Visit.plan with Data/Levels RecipeCap).
local function planOf(ctx: Types.Ctx, case: any, outcome: any): { string }
	local sent = if type(outcome) == "table" then outcome.Plan else nil
	if type(sent) == "table" then
		local out: { string } = {}
		for _, id in ipairs(sent) do
			if #out < Visit.MAX_PLAN and dataRow(ctx, "Items", id) then
				table.insert(out, id)
			end
		end
		if #out > 0 then
			return out
		end
	end
	local levels = (ctx.Data :: any).Levels
	local level = math.max(1, math.floor(num((ctx.State :: any).Level, 1)))
	local row = if type(levels) == "table" then levels[level] else nil
	local cap = if type(row) == "table" then num(row.RecipeCap, 1) else 1
	return Visit.plan(case, cap)
end

-- After an exam: the case, for REVEAL_HOLD seconds ("🩺 It's a cough!" in the header with the plan's icons, the
-- first step on the hint line, and the tip). false when the outcome names no case this client knows.
local function showReveal(ctx: Types.Ctx, v: View, run: Run, outcome: any): boolean
	local caseId = if type(outcome) == "table" then outcome.Case else nil
	local case = dataRow(ctx, "Cases", caseId)
	if not case then
		return false
	end
	local old = v.Stage:FindFirstChild("Results")
	if old then
		old:Destroy()
	end
	local tool = dataRow(ctx, "Tools", run.Session.Answer)
	local toolIcon = if tool and type(tool.Icon) == "string" then tool.Icon else "🩺"
	setHeader(v, toolIcon, Pure.reveal(case.Name), Theme.Colors.Collect)
	local layer = new("Frame", {
		Name = "Results",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = v.Stage,
	})
	table.insert(run.Cleanups, function()
		layer:Destroy()
	end)
	local row = new("Frame", {
		Name = "Plan",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.96, 0.56),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = layer,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	-- The case's own picture, then each step of its plan on a chip.
	emoji(row, if type(case.Icon) == "string" then case.Icon else "🩺", {
		AnchorPoint = Vector2.zero,
		LayoutOrder = 0,
		Size = UDim2.fromScale(1, 1),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = 3,
	})
	local plan = planOf(ctx, case, outcome)
	for index, itemId in plan do
		local item = dataRow(ctx, "Items", itemId)
		local chip = blob(row, "Step" .. index, Theme.Colors.Card, {
			LayoutOrder = index,
			Size = UDim2.fromScale(1, 1),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			ZIndex = 3,
		}, Theme.Radius.Medium)
		emoji(chip, if item and type(item.Icon) == "string" then item.Icon else "❓", {
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.7, 0.7),
			ZIndex = 4,
		})
		punch(chip, 0.5, 0.3 + index * 0.08)
	end
	local first = dataRow(ctx, "Items", plan[1])
	setHint(v, if first then "🔜 " .. first.Icon .. " " .. first.Name else "")
	local tip = finite(outcome.Tip)
	if tip and tip > 0 then
		local tipLabel = Kit.label({
			Name = "Tip",
			Text = "💰 +" .. Hud.format(math.floor(tip)),
			Outlined = true,
			TextScaled = true,
			TextWrapped = false,
			TextColor3 = Theme.Colors.Cash,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.86),
			Size = UDim2.fromScale(0.8, 0.22),
			ZIndex = 4,
			Parent = layer,
		})
		Kit.outline(tipLabel, Theme.Stroke.Bold)
		Kit.textLimit(tipLabel, 44)
		punch(tipLabel, 1.5, 0.35)
	end
	burst(layer, UDim2.fromScale(0.5, 0.42), "✨", 8, 0.16)
	sound("Sparkle")
	return true
end

-- If this file has a bug outside a game, answer like the Foundation stub did (all Good, never early), so the visit
-- never jams waiting for the timeout. A Dispense answer names the medicine it was making (or the first on offer).
local function rescue(ctx: Types.Ctx, run: Run)
	local reported = run.Reported
	stop(run)
	if reported then
		return
	end
	run.Reported = true
	local session = run.Session
	local played = Pure.played(session.Games, session.Auto)
	task.wait(Pure.holdBack(os.clock() - run.Started, MiniGame.minSeconds(played, session.Simple, ctx.Config), 0.2))
	local ratings = table.create(#session.Games, "Good")
	for index in ratings do
		if session.Auto[index] then
			ratings[index] = "Perfect"
		end
	end
	local choice = if session.Kind == "Dispense" then run.Choice or session.Options[1] else nil
	local ok, _, outcome = Hud.ask(ctx.Remotes.TreatResult, session.Session, ratings, choice)
	if ok and type(outcome) == "table" then
		fireBus("TreatDone", outcome, run.Raw)
	end
end

-- After a finished treatment whose outcome has Triage (Lv 3+, no Receptionist on duty): "🔀 Which floor?" with a
-- huge floor button per department (its icon, in its badge chip's colour) and the soft time bar draining (no
-- digits). The first tap asks Triage(session, dept) once; the answer shows "✅ Right floor!" or "Oops, not this
-- floor!" (the patient goes the right way anyway). No tap: the bar empties and the card just closes, and the patient
-- goes by itself (the server waits Seconds). Never a fail.
local function runTriage(ctx: Types.Ctx, v: View, run: Run, card: TriageCard, since: number)
	local old = v.Stage:FindFirstChild("Results")
	if old then
		old:Destroy()
	end
	setHeader(v, "🔀", "Which floor?", Theme.Colors.Purple)
	setHint(v, "👀 Match the badge!")
	local layer = new("Frame", {
		Name = "Triage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = v.Stage,
	})
	table.insert(run.Cleanups, function()
		layer:Destroy()
	end)
	local row = new("Frame", {
		Name = "Row",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromScale(0.96, 0.7),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = layer,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 18),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})

	-- Taps and the gamepad's own selection work the buttons (A selects them), so the card's Space/A action steps
	-- aside while they show.
	ContextActionService:UnbindAction(ACTION)
	local started = since -- when the server's answer came: its wait for a pick began just before
	local picked = false
	local answer: string? = nil
	local buttons: { TextButton } = {}
	local function choose(dept: string, button: TextButton)
		if picked or not run.Alive or os.clock() - started > card.Seconds - TRIAGE_MARGIN then
			return
		end
		picked = true
		sound("Triage")
		punch(button, 1.25, 0.35)
		for _, other in buttons do
			if other ~= button then
				other.Interactable = false
				other.BackgroundTransparency = 0.45
			end
		end
		task.spawn(function()
			local ok, message, payload = Hud.ask(ctx.Remotes.Triage, run.Session.Session, dept)
			answer = Pure.triageResult(ok, message, payload)
		end)
	end
	for index, option in card.Options do
		-- A candy button in its department's badge colour (the colour IS the game: "Match the badge!").
		local button = Kit.button({
			Name = "Floor_" .. option.Dept,
			Kind = "Primary",
			Fill = DEPT_COLORS[option.Dept] or CALM_BLUE,
			Text = "",
			LayoutOrder = index,
			Size = UDim2.fromScale(1, 1),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			ZIndex = 3,
			Parent = row,
		})
		minSize(button, MIN_TAP) -- they fill the stage's height: about 120-190 px on phones
		local icon = emoji(button, option.Icon, {
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.68, 0.68),
		})
		icon.ZIndex = 4
		button.Activated:Connect(function()
			choose(option.Dept, button)
		end)
		buttons[index] = button
		punch(button, 0.5, 0.3 + index * 0.08)
	end
	local gamepad = UserInputService.PreferredInput == Enum.PreferredInput.Gamepad
	if gamepad and buttons[1] then
		GuiService.SelectedObject = buttons[1]
	end

	-- The soft bar drains while it waits; after a tap it waits a little longer for the answer.
	while run.Alive and answer == nil do
		local elapsed = os.clock() - started
		if not picked then
			setTime(v, Pure.triageBar(elapsed, card.Seconds))
		end
		if elapsed >= card.Seconds + (if picked then 3 else 0) then
			break
		end
		task.wait(0.1)
	end
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(layer) then
		GuiService.SelectedObject = nil
	end
	if not run.Alive then
		return
	end
	setTime(v, nil)
	local look = if answer then Pure.TRIAGE_TEXT[answer] else nil
	if look then
		setHeader(v, look.Icon, look.Text, if answer == "Right" then Theme.Colors.Collect else CALM_BLUE)
		setHint(v, if answer == "Right" then "💰 +bonus!" else "↕️ Off it goes!")
		if answer == "Right" then
			burst(layer, UDim2.fromScale(0.5, 0.48), "✨", 10, 0.2)
			sound("Sparkle")
		end
		waitFor(run, TRIAGE_HOLD)
	end
end

-- A handover (TreatSession.Handover: a medicine handed over completed the plan of a patient who stays): nothing to
-- play. The report goes at once; the card opens only when the server asks which ward (outcome.Triage).
local function runHandover(ctx: Types.Ctx, v: View, run: Run)
	local session = run.Session
	run.Reported = true
	local ok, _, outcome = Hud.ask(ctx.Remotes.TreatResult, session.Session, {}, nil)
	local answeredAt = os.clock()
	local triage: TriageCard? = nil
	if ok and type(outcome) == "table" then
		fireBus("TreatDone", outcome, run.Raw)
		triage = Pure.triage(outcome.Triage, ctx.Data.Departments)
	end
	if triage and run.Alive and current == run then
		setSteps(ctx, v, run)
		v.ComboOn = false
		showCombo(ctx, v, session.Combo, false)
		openCard(v)
		runTriage(ctx, v, run, triage, answeredAt)
		stop(run)
		return
	end
	-- No pick to make: the card never opened, so there is nothing to close.
	if run.Alive then
		run.Alive = false
		if current == run then
			current = nil
			activeMini = nil
		end
	end
end

local function runSession(ctx: Types.Ctx, run: Run)
	local session = run.Session
	local v = view or build(ctx)
	view = v
	if #session.Games == 0 then
		runHandover(ctx, v, run)
		return
	end
	setSteps(ctx, v, run)
	v.ComboValue = session.Combo
	v.ComboOn = not session.Simple
	showCombo(ctx, v, session.Combo, false)
	openCard(v)
	if session.Kind == "Dispense" then
		-- Which medicine to make (asked only when bay patients need several), then find its bottle and measure it.
		run.Choice = chooseMedicine(ctx, v, run)
		if not run.Alive then
			return
		end
		refreshSteps(ctx, v, run)
	end

	local ratings: { string } = {}
	for index, gameId in session.Games do
		if not run.Alive then
			return
		end
		local magic = session.Auto[index] == true
		local rating = if magic then playAuto(v, run, index, gameId) else playOne(ctx, v, run, index, gameId)
		if not run.Alive then
			return
		end
		ratings[index] = rating
		if gameId == "Pick" and session.Kind == "Exam" then
			-- The right tool is out now: the step chips may show it.
			run.Picked = true
			refreshSteps(ctx, v, run)
		end
		fireBus("MiniGameRated", gameId, rating)
		markStep(v, index, rating)
		showRating(v, rating, magic)
		if not session.Simple then
			local predicted = MiniGame.settle(session.Combo, ratings :: any, ctx.Config)
			showCombo(ctx, v, predicted, true)
		end
		if not waitFor(run, RATING_HOLD) then
			return
		end
	end

	-- Never sooner than the played games' minimum time (the server would rate a too-quick report all OK); the
	-- games an ability made PERFECT don't count, the same as the server's MiniGame.accept.
	local minimum = MiniGame.minSeconds(Pure.played(session.Games, session.Auto), session.Simple, ctx.Config)
	if not waitFor(run, Pure.holdBack(os.clock() - run.Started, minimum, REPORT_MARGIN)) then
		return
	end
	run.Reported = true
	showResults(ctx, v, run, ratings, nil)
	local choice = if session.Kind == "Dispense" then run.Choice else nil
	local ok, _, outcome = Hud.ask(ctx.Remotes.TreatResult, session.Session, ratings, choice)
	local answeredAt = os.clock()
	local triage: TriageCard? = nil
	local revealed = false
	if ok and type(outcome) == "table" then
		fireBus("TreatDone", outcome, run.Raw)
		if run.Alive then
			-- An exam reveals the case; anything else shows the server's ratings and the tip.
			revealed = session.Kind == "Exam" and showReveal(ctx, v, run, outcome)
			if not revealed then
				local serverRatings = if type(outcome.Ratings) == "table" then outcome.Ratings else ratings
				showResults(ctx, v, run, serverRatings, outcome)
			end
			local combo = finite(outcome.Combo)
			if combo and not session.Simple then
				showCombo(ctx, v, math.max(0, math.floor(combo)), true)
			end
		end
		triage = Pure.triage(outcome.Triage, ctx.Data.Departments)
	end
	-- A floor to pick comes almost at once (the server is waiting); otherwise the answer stays a moment.
	if not waitFor(run, if triage then TRIAGE_LEAD elseif revealed then REVEAL_HOLD else RESULT_HOLD) then
		return
	end
	if triage then
		runTriage(ctx, v, run, triage, answeredAt)
	end
	stop(run)
end

local function start(ctx: Types.Ctx, raw: any)
	local session = Pure.session(raw)
	if not session then
		return
	end
	local previous = current
	if previous then
		stop(previous)
	end
	runs += 1
	local run: Run = {
		Id = runs,
		Alive = true,
		Reported = false,
		Session = session,
		Raw = raw,
		Started = os.clock(),
		Cleanups = {},
		Rng = Random.new(),
		-- The first-session tutorial: no draining time bar (look build plan §B8). OK still treats.
		HideDrain = TutorialLogic.active(ctx.State.Tutorial),
		Picked = false,
		Choice = nil,
	}
	current = run
	-- 🎯 Steady Hands: this session's games draw and rate with wider Perfect windows.
	activeMini = Pure.eased(ctx.Config.MiniGame, session.Ease)
	if session.Expert then
		-- Expert Dispensing (the Pharmacy2 unlock): a wider Dose band, drawn and rated alike.
		local dispensary = (ctx.Config :: any).Dispensary
		local band = if type(dispensary) == "table" then finite(dispensary.ExpertBand) else nil
		activeMini = Pure.widened(activeMini, "Dose", band or 1.5)
	end
	-- Close just before the server settles the session by itself (all OK): no report after that.
	local timeout = session.Timeout or MiniGame.timeout(session.Games, ctx.Config)
	task.delay(math.max(timeout - TIMEOUT_MARGIN, 1), function()
		if run.Alive and not run.Reported then
			stop(run)
		end
	end)
	local ok, err = pcall(runSession, ctx, run)
	if not ok then
		warn("[MiniGames] " .. tostring(err))
		-- Only while this run still owns the card: a timed-out or replaced run has nothing left to answer.
		if current == run then
			rescue(ctx, run)
		end
	end
end

-- A treat card is open now (UI/Celebrate holds the celebrations nobody tapped for until it closes).
function MiniGames.isOpen(): boolean
	return current ~= nil
end

-- The current game's stage (look build plan §B8): where the games draw, for UI/Tutorial's touch hand. Nil = no game
-- is up.
function MiniGames.stage(): GuiObject?
	local v = view
	if current ~= nil and v ~= nil then
		return v.Stage
	end
	return nil
end

function MiniGames.init(ctx: Types.Ctx)
	busFire = ctx.fire
	ctx.on("TreatStart", function(raw: any)
		start(ctx, raw)
	end)
	-- Build the card now (hidden), so the first treatment doesn't wait for it and a broken build shows at join.
	local ok, built = pcall(build, ctx)
	if ok then
		view = view or built
	else
		warn("[MiniGames] the card failed to build: " .. tostring(built))
	end
end

return MiniGames
