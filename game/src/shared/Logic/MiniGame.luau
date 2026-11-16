--!strict
-- Treatment mini-games: ratings, the combo, tips and the server's plausibility check (depth-update design §1, build
-- plan §B7). Pure: no Roblox services, no requires. `cfg` is Shared/Config (its MiniGame table is read).
--
-- One mini-game per recipe item: 🧪 Potion -> Pour · 🩹 Plaster -> Patch · 🛁 Bubbles -> Scrub · ☕ Cocoa -> Cool.
-- Ratings are OK / Good / Perfect. There is no fail: OK still cures. A Perfect adds a small cash tip and +1 combo;
-- the combo multiplies tips (x1.2 / x1.5 / x2 from 3 / 6 / 10). A Good holds it (no tip, no +1, no reset) and an OK
-- (the miss: also what a timeout, a too-early report or a far-away report rate) resets it (build plan §E7, decided
-- 2026-11-16). Tips are cash
-- only (never Stars, Book or story) and capped per cure, so a cheating client gains at most a small tip.
--
--   MiniGame.GAMES                               { [ItemId]: GameId }
--   MiniGame.RATINGS                             { "OK", "Good", "Perfect" }
--   MiniGame.gameFor(itemId): GameId?
--   MiniGame.isRating(value): boolean
--   MiniGame.rate(game, score, cfg): Rating      the client's rating. Pour: score = the fill (0..1) when let go,
--                                                Perfect inside [BandMin, BandMax], Good within GoodSlack of it.
--                                                Patch: spots tapped in time (Spots -> Perfect, Good -> Good).
--                                                Scrub: bubbles popped (Perfect / Good thresholds). Cool: good
--                                                blows (Blows -> Perfect, Good -> Good). Anything less: OK.
--   MiniGame.minSeconds(games, simple, cfg)      the fastest a real session can end (Simple: one tap per game)
--   MiniGame.timeout(games, cfg)                 when the server stops waiting and settles the session as all OK
--   MiniGame.accept(reported, games, elapsed, simple, cfg): { Rating }
--                                                the server's view of a TreatResult report: Simple -> all Good; a
--                                                report that isn't exactly one valid rating per game, or came sooner
--                                                than minSeconds x Slack -> all OK; otherwise the report
--   MiniGame.multiplier(combo, cfg): number      the tip multiplier at this combo (1 below the first step)
--   MiniGame.settle(combo, ratings, cfg, tipSoFar?, tipScale?): (combo, tip)
--                                                walks the ratings in order: a Perfect adds 1 to the combo, then
--                                                pays PerfectTip x multiplier(combo) x tipScale (a Cheerer on duty);
--                                                a Good holds the combo; anything else (OK) resets it to 0. The tip
--                                                is floored and never takes
--                                                the patient's total past TipCapPerCure (tipSoFar = paid already).

export type Rating = "OK" | "Good" | "Perfect"
export type GameId = "Pour" | "Patch" | "Scrub" | "Cool"

local MiniGame = {}

MiniGame.GAMES = table.freeze({ Potion = "Pour", Plaster = "Patch", Bubbles = "Scrub", Cocoa = "Cool" })
MiniGame.RATINGS = table.freeze({ "OK", "Good", "Perfect" })

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

local function gameSettings(cfg: any, game: string): any
	local value = settings(cfg)[game]
	return if type(value) == "table" then value else {}
end

function MiniGame.gameFor(itemId: any): GameId?
	if type(itemId) ~= "string" then
		return nil
	end
	return (MiniGame.GAMES :: any)[itemId]
end

function MiniGame.isRating(value: any): boolean
	return VALID[value] == true
end

function MiniGame.rate(game: string, score: number, cfg: any): Rating
	local s = num(score, 0)
	local g = gameSettings(cfg, game)
	if game == "Pour" then
		local low, high = num(g.BandMin, 0.7), num(g.BandMax, 0.86)
		local slack = num(g.GoodSlack, 0.12)
		if s >= low and s <= high then
			return "Perfect"
		elseif s >= low - slack and s <= high + slack then
			return "Good"
		end
		return "OK"
	end
	local perfectAt, goodAt
	if game == "Patch" then
		perfectAt, goodAt = num(g.Spots, 3), num(g.Good, 2)
	elseif game == "Scrub" then
		perfectAt, goodAt = num(g.Perfect, 6), num(g.Good, 3)
	elseif game == "Cool" then
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
			total += num(mins[game], 1)
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

function MiniGame.accept(reported: any, games: { string }, elapsed: number, simple: boolean, cfg: any): { Rating }
	local n = #games
	if simple then
		return all("Good", n)
	end
	if type(reported) ~= "table" or #reported ~= n then
		return all("OK", n)
	end
	local minimum = MiniGame.minSeconds(games, false, cfg) * num(settings(cfg).Slack, 0.8)
	if num(elapsed, 0) < minimum then
		return all("OK", n)
	end
	local out: { Rating } = {}
	for index = 1, n do
		local rating = reported[index]
		if not VALID[rating] then
			return all("OK", n)
		end
		out[index] = rating
	end
	return out
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
