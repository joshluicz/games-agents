--!strict
-- Treatment mini-games (depth-update design §1, build plan §B9). OWNER: T2. Load `game-feel` and `roblox-ui`.
--   init(ctx)   listens for the bus "TreatStart" (session: Types.TreatSession, forwarded from the server)
--
-- What T2 builds: one short game per session.Games entry, in order, each 3-5 s, touch and mouse, big targets:
--   Pour  (🧪) hold to fill the bottle, let go in the green band         score = the fill when let go (0..1)
--   Patch (🩹) 3 sore spots appear on the creature, tap each in time      score = spots tapped
--   Scrub (🛁) bubbles pop up around the creature, tap to pop them        score = bubbles popped
--   Cool  (☕) tap to blow when the steam ring is biggest, 3 times        score = good blows
-- Rate each with Logic/MiniGame.rate(game, score, ctx.Config) and show a big outlined "PERFECT!" / "GOOD!" / "OK!"
-- pop and the combo counter; fire "MiniGameRated" (game, rating) as each game ends. Then ask the server
-- (Hud.ask(ctx.Remotes.TreatResult, session.Session, ratings)): its third value is the TreatOutcome (the server's
-- ratings, the tip, the combo, Complete); fire "TreatDone" (outcome, session). Never a fail: OK still cures.
-- session.Simple: one big tap per game (rated Good). Reduced motion (Kit.reducedMotion()): gentler animation, same
-- rules. Close cleanly when session.Timeout passes (the server has settled it as all OK by then).
--
-- FOUNDATION STUB: answers every session with Good after the games' minimum time, so the treat flow keeps working
-- end to end before T2 lands.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local MiniGame = require(Shared:WaitForChild("Logic"):WaitForChild("MiniGame"))

local MiniGames = {}

function MiniGames.init(ctx: Types.Ctx)
	ctx.on("TreatStart", function(session: any)
		if type(session) ~= "table" or type(session.Session) ~= "number" or type(session.Games) ~= "table" then
			return
		end
		local games: { string } = session.Games
		task.wait(MiniGame.minSeconds(games, session.Simple == true, ctx.Config) + 0.2)
		local ratings: { string } = {}
		for index, game in games do
			ratings[index] = "Good"
			ctx.fire("MiniGameRated", game, "Good")
		end
		local ok, _, outcome = pcall(function()
			return ctx.Remotes.TreatResult:InvokeServer(session.Session, ratings)
		end)
		if ok and type(outcome) == "table" then
			ctx.fire("TreatDone", outcome, session)
		end
	end)
end

return MiniGames
