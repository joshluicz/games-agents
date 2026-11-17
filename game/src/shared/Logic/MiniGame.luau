--!strict
-- Mini-games: ratings, the combo, tips and the server's plausibility check (depth-update design §1; Real Clinic build
-- plan, contract C5; design §4 and §7). Pure: no Roblox services, no requires. `cfg` is Shared/Config (its MiniGame
-- table is read).
--
-- Every beat of a visit is one short game, named by a GameId: an exam tool's (Data/Tools Game: Listen, Temp, Light,
-- Look, XRay), a supply's (Data/Items Game: Plaster, Ice, Bandage, Cast, Bath, Cocoa), the dispensary's Dose, and
-- Pick (choose the right tool or bottle). Each GameId is a new look on one of five ENGINES: Pour (hold and let go in
-- the band), Patch (tap the spots), Scrub (pop the bubbles), Cool (tap in time) and Pick (tap the right one).
-- A game an ability made PERFECT (TreatSession.Auto) is always Perfect and skipped by the client.
-- Ratings are OK / Good / Perfect. There is no fail: OK still treats. A Perfect adds a small cash tip and +1 combo;
-- the combo multiplies tips (x1.2 / x1.5 / x2 from 3 / 6 / 10). A Good holds it (no tip, no +1, no reset) and an OK
-- (the miss: also what a timeout, a too-early report or a far-away report rate) resets it (build plan §E7, decided
-- 2026-11-16). Tips are cash only (never Stars, Book or story) and capped per patient, so a cheating client gains at
-- most a small tip.
--
--   MiniGame.ENGINE                              { [GameId]: "Pour" | "Patch" | "Scrub" | "Cool" | "Pick" }
--   MiniGame.GAME_IDS                            every GameId, in a fixed order
--   MiniGame.RATINGS                             { "OK", "Good", "Perfect" }
--   MiniGame.engineOf(game): Engine?             a GameId's engine (an engine's own name is itself)
--   MiniGame.gameFor(itemId, items): GameId?     a supply's game: items[itemId].Game (items = Data/Items). nil for a
--                                                medicine (handing one over plays no game) or an unknown item
--   MiniGame.isRating(value): boolean
--   MiniGame.tuning(game, cfg): { [string]: number }
--                                                the game's tuning row: cfg.MiniGame.Games[game], else its engine's
--                                                own row (cfg.MiniGame.Pour ...), else {}
--   MiniGame.rate(game, score, cfg): Rating      the client's rating, by the game's engine and its tuning row.
--                                                Pour: score = the fill (0..1) when let go, Perfect inside
--                                                [BandMin, BandMax], Good within GoodSlack of it.
--                                                Patch: spots tapped in time (Spots -> Perfect, Good -> Good).
--                                                Scrub: bubbles popped (Perfect / Good thresholds). Cool: good
--                                                beats (Blows -> Perfect, Good -> Good). Pick: score = WRONG taps
--                                                before the right one (0 -> Perfect, up to Good (1) -> Good).
--                                                Anything less: OK.
--   MiniGame.minSeconds(games, simple, cfg)      the fastest a real session can end (Simple: one tap per game). A
--                                                game's own MinSeconds (its tuning row), else its engine's
--                                                (cfg.MiniGame.MinSeconds), else 1 s
--   MiniGame.timeout(games, cfg)                 when the server stops waiting and settles the session as all OK
--   MiniGame.accept(reported, games, elapsed, simple, cfg, auto?): { Rating }
--                                                the server's view of a TreatResult report: Simple -> all Good; a
--                                                report that isn't exactly one valid rating per game, or came sooner
--                                                than minSeconds x Slack -> all OK; otherwise the report. Whatever the
--                                                report, a game flagged in `auto` ({ boolean }, an ability) is Perfect,
--                                                and the minimum time counts only the other games
--   MiniGame.multiplier(combo, cfg): number      the tip multiplier at this combo (1 below the first step)
--   MiniGame.settle(combo, ratings, cfg, tipSoFar?, tipScale?): (combo, tip)
--                                                walks the ratings in order: a Perfect adds 1 to the combo, then
--                                                pays PerfectTip x multiplier(combo) x tipScale (a Cheerer on duty);
--                                                a Good holds the combo; anything else (OK) resets it to 0. The tip
--                                                is floored and never takes
--                                                the patient's total past TipCapPerCure (tipSoFar = paid already).

export type Rating = "OK" | "Good" | "Perfect"
export type Engine = "Pour" | "Patch" | "Scrub" | "Cool" | "Pick"
export type GameId =
	"Listen"
	| "Temp"
	| "Light"
	| "Look"
	| "XRay"
	| "Plaster"
	| "Ice"
	| "Bandage"
	| "Cast"
	| "Bath"
	| "Cocoa"
	| "Dose"
	| "Pick"

local MiniGame = {}

MiniGame.ENGINE = table.freeze({
	-- exam tools (Data/Tools)
	Listen = "Patch", -- tap the glowing spots on the chest
	Temp = "Pour", -- hold while the reading climbs, let go in the band
	Light = "Cool", -- tap as the light ring lines up
	Look = "Patch", -- find and tap the sore spots
	XRay = "Cool", -- tap as the scanner bar passes the bone
	-- supplies (Data/Items)
	Plaster = "Patch",
	Ice = "Pour", -- hold till cool
	Bandage = "Cool", -- wrap, in beats
	Cast = "Cool",
	Bath = "Scrub",
	Cocoa = "Cool", -- blow
	-- the dispensary
	Dose = "Pour", -- fill the measuring cup to the line
	Pick = "Pick", -- choose the right tool or bottle
}) :: { [string]: Engine }
MiniGame.GAME_IDS = table.freeze({
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
	"Dose",
	"Pick",
})
MiniGame.RATINGS = table.freeze({ "OK", "Good", "Perfect" })

local ENGINES: { [string]: boolean } = { Pour = true, Patch = true, Scrub = true, Cool = true, Pick = true }

local VALID: { [any]: boolean } = { OK = true, Good = true, Perfect = true }

local function num(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

local function settings(cfg: any): any
	return if type(cfg) == "table" and type(cfg.MiniGame) == "table" then cfg.MiniGame else {}
end

function MiniGame.engineOf(game: any): Engine?
	if type(game) ~= "string" then
		return nil
	end
	local engine = MiniGame.ENGINE[game]
	if engine then
		return engine
	end
	return if ENGINES[game] then game :: any else nil
end

function MiniGame.tuning(game: any, cfg: any): any
	local mini = settings(cfg)
	if type(mini.Games) == "table" and type(mini.Games[game]) == "table" then
		return mini.Games[game]
	end
	local engine = MiniGame.engineOf(game)
	local value = if engine then mini[engine] else nil
	return if type(value) == "table" then value else {}
end

function MiniGame.gameFor(itemId: any, items: any): GameId?
	if type(itemId) ~= "string" or type(items) ~= "table" then
		return nil
	end
	local item = rawget(items, itemId)
	local game = if type(item) == "table" then item.Game else nil
	return if type(game) == "string" and MiniGame.ENGINE[game] ~= nil then game :: any else nil
end

function MiniGame.isRating(value: any): boolean
	return VALID[value] == true
end

function MiniGame.rate(game: string, score: number, cfg: any): Rating
	local s = num(score, 0)
	local g = MiniGame.tuning(game, cfg)
	local engine = MiniGame.engineOf(game)
	if engine == "Pour" then
		local low, high = num(g.BandMin, 0.7), num(g.BandMax, 0.86)
		local slack = num(g.GoodSlack, 0.12)
		if s >= low and s <= high then
			return "Perfect"
		elseif s >= low - slack and s <= high + slack then
			return "Good"
		end
		return "OK"
	elseif engine == "Pick" then
		-- the score counts WRONG taps: fewer is better (a missing score is a miss)
		local wrong = num(score, math.huge)
		if wrong <= 0 then
			return "Perfect"
		elseif wrong <= num(g.Good, 1) then
			return "Good"
		end
		return "OK"
	end
	local perfectAt, goodAt
	if engine == "Patch" then
		perfectAt, goodAt = num(g.Spots, 3), num(g.Good, 2)
	elseif engine == "Scrub" then
		perfectAt, goodAt = num(g.Perfect, 6), num(g.Good, 3)
	elseif engine == "Cool" then
		perfectAt, goodAt = num(g.Blows, 3), num(g.Good, 2)
	else
		return "OK"
	end
	if s >= perfectAt then
		return "Perfect"
	elseif s >= goodAt then
		return "Good"
	end
	return "OK"
end

function MiniGame.minSeconds(games: { string }, simple: boolean, cfg: any): number
	local mini = settings(cfg)
	local total = 0
	for _, game in games do
		if simple then
			total += num(mini.SimpleMinSeconds, 0.25)
		else
			local mins = if type(mini.MinSeconds) == "table" then mini.MinSeconds else {}
			local own = MiniGame.tuning(game, cfg).MinSeconds
			total += num(own, num(mins[game], num(mins[MiniGame.engineOf(game) :: any], 1)))
		end
	end
	return total
end

function MiniGame.timeout(games: { string }, cfg: any): number
	local mini = settings(cfg)
	return num(mini.SessionSeconds, 12) + num(mini.PerGameSeconds, 6) * #games
end

local function all(rating: Rating, n: number): { Rating }
	local out: { Rating } = {}
	for index = 1, n do
		out[index] = rating
	end
	return out
end

-- `ratings` with every auto game made Perfect (a new table).
local function withAuto(ratings: { Rating }, auto: { boolean }?): { Rating }
	if type(auto) ~= "table" then
		return ratings
	end
	local out = table.clone(ratings)
	for index in out do
		if auto[index] == true then
			out[index] = "Perfect"
		end
	end
	return out
end

function MiniGame.accept(
	reported: any,
	games: { string },
	elapsed: number,
	simple: boolean,
	cfg: any,
	auto: { boolean }?
): { Rating }
	local n = #games
	if simple then
		return withAuto(all("Good", n), auto)
	end
	if type(reported) ~= "table" or #reported ~= n then
		return withAuto(all("OK", n), auto)
	end
	local played: { string } = {}
	for index, game in games do
		if not (type(auto) == "table" and auto[index] == true) then
			table.insert(played, game)
		end
	end
	local minimum = MiniGame.minSeconds(played, false, cfg) * num(settings(cfg).Slack, 0.8)
	if num(elapsed, 0) < minimum then
		return withAuto(all("OK", n), auto)
	end
	local out: { Rating } = {}
	for index = 1, n do
		local rating = reported[index]
		if not VALID[rating] then
			return withAuto(all("OK", n), auto)
		end
		out[index] = rating
	end
	return withAuto(out, auto)
end

function MiniGame.multiplier(combo: number, cfg: any): number
	local steps = settings(cfg).Combo
	local best = 1
	if type(steps) == "table" then
		for _, step in steps do
			if type(step) == "table" and num(combo, 0) >= num(step.At, math.huge) then
				best = math.max(best, num(step.Multiplier, 1))
			end
		end
	end
	return best
end

function MiniGame.settle(
	combo: number,
	ratings: { Rating },
	cfg: any,
	tipSoFar: number?,
	tipScale: number?
): (number, number)
	local mini = settings(cfg)
	local current = math.max(0, math.floor(num(combo, 0)))
	local scale = math.max(0, num(tipScale, 1))
	local perfectTip = math.max(0, num(mini.PerfectTip, 0))
	local raw = 0
	for _, rating in ratings do
		if rating == "Perfect" then
			current += 1
			raw += perfectTip * MiniGame.multiplier(current, cfg) * scale
		elseif rating ~= "Good" then
			current = 0 -- an OK (the miss) resets it; a Good holds it
		end
	end
	local room = math.max(0, num(mini.TipCapPerCure, 0) - math.max(0, num(tipSoFar, 0)))
	return current, math.min(math.floor(raw), math.floor(room))
end

return MiniGame
