--!strict
-- The first-session tutorial (docs/plan/2026-11-16-first-session-design.md §B; look build plan §B1/§B9). Server
-- only. OWNER: T8 (look overhaul).
-- The step is server-authoritative and saved (Data.Tutorial; the rules are in Logic/Tutorial). The client shows it
-- from the Snapshot (UI/Tutorial, Hud) and can only ever ask three things: TutorialAck (past the welcome),
-- TutorialSkip and TutorialReplay (below). Every one of them takes no client data.
--
-- How each step moves on (the Real Clinic visit: examine -> treat; design §13). Every move is a real server event,
-- never the client's word:
--   1 -> 2     the TutorialAck remote (Remotes.serve: rate-limited, pcalled), only while the player has a clinic.
--              The client acks as the welcome sweep ends. If no ack comes, by itself WELCOME_FALLBACK_SECONDS after
--              they got their clinic
--   2 -> 3     ARRIVED_SECONDS after a patient on their clinic sits down on an exam bay's bed (its `Bay` attribute
--              is set and its State is past "ToBay"). Simple start (design §2): the patient gets there because the
--              player SENT it from the waiting room (Server/Patients: the Send prompt; through the one-at-a-time
--              steps it goes to the first free bay in order, bay 1). That is a part of step 2, never a step of its
--              own: the saved numbers stay, and a save from before it resumes as it always did. Server-side watch of the plot's Patients folder while in steps
--              2-3 (attribute signals, no polling), so it never hangs on a hook; Patients' onFrontArrived only makes
--              it look again
--   2..3 -> 4  an exam on their clinic reveals a case, by them, a friend or a nurse (Patients calls onExamined; the
--              same watch also sees a patient's `Case` attribute appear)
--   2..4 -> 5  a patient's plan on their clinic is done (Patients calls onTreated)
--   2..5 -> 6  a treatment pays out on their clinic (Cure calls onCured)
--   6 -> 7     three more on their clinic. The count is the player attribute TutorialCures (State sends it; not
--              saved, so a rejoin in step 6 counts 3 more from 0).
--              Entering 7: a player who can't afford the cheapest upgrade gets a top-up to exactly its price in
--              the same save update, with the toast "🎁 A gift to get you started!". In-game cash only, never
--              Robux, a pass or anything paid (CLAUDE.md red line 3). ONCE PER SAVE: the saved TutorialGift says
--              the top-up has run (or was never needed), and it is set in that same update (Pure.gift). A Skip and
--              a Replay set it too, so a replay never gives a gift (look build plan §B1)
--   7 -> 8     any purchase (Economy.Purchased)
--   8 -> 9     BOOK_SECONDS later: done
-- Fetching the plan's item (the supply shelf or the dispensary) is no step of its own: the client's card 4 turns
-- into card 5 when the player carries it. Stations' onMade is kept as a harmless hook.
-- A rejoin resumes (Logic/Tutorial.resume): steps 3-5 go back to 2, since their patient left with the player.
-- While a player is in the tutorial they are quiet (Remotes.setQuiet): ambient news toasts wait (Remotes.news,
-- Remotes.toastAll); replies and warnings still show.
--
-- Look overhaul (build plan §B1, memory-20261117-002/-003): two player-safe remotes. Arguments are IGNORED, each
-- answers (ok, message) with a message of at most 6 words, and a "no" changes nothing. Both go through
-- Remotes.serve (10 calls a second per player, pcalled) and touch only the caller's own save and plot.
--   TutorialSkip()     loaded · an active step (Logic.canSkip; else "Already done!") · straight to DONE with no gift
--                      (TutorialGift set) · TutorialCures cleared · the toast "🔁 Replay anytime in ⚙️" · a custom
--                      analytics event "TutorialSkipped" with the step (never a funnel step: logging a later one
--                      would mark the skipped ones done)
--   TutorialReplay()   loaded and saving (PlayerData.canSave) · DONE and the caller owns a clinic (Logic.canReplay;
--                      "Get a clinic first!") · Config.Tutorial.ReplayCooldown seconds since the caller's last replay
--                      ("Try again soon") · the reopen hook empties THE CALLER'S OWN line (Patients.reopen, handed
--                      over by Main.server) · the player attribute TutorialReplay = true for the session · back to
--                      PATIENT (the first patient; no welcome sweep, no respawn, no camera move, no funnel logs).
--                      TutorialGift stays true, so there is never a second gift
-- The onboarding funnel (published games only): every first-run step change logs its stage (Logic.funnelStep: the
-- card 1..7, then 8 for the Shop) with AnalyticsService:LogOnboardingFunnelStepEvent, in a pcall. Never on a
-- replay; never in Studio.
--
-- API (safe for anyone: a player who isn't loaded, or is done, just gets "not in the tutorial"):
--   Tutorial.step(p): number?                 the saved step (nil = not loaded)
--   Tutorial.active(p): boolean               in the tutorial right now
--   Tutorial.calm(p): boolean                 patience never runs out at their clinic (steps 1-6)
--   Tutorial.spawnPlan(owner, plotEmpty, secondSpawned): Plan   who Patients may send next (Logic/Tutorial; Patients
--                                             picks the two tutorial patients' cases)
--   Tutorial.queueCap(owner): number?         at most this many waiting, nil = the level's queue
--   Tutorial.onFrontArrived(owner)            a patient at owner's clinic sat down in a bay (look again)
--   Tutorial.onExamined(owner)                an exam at owner's clinic revealed a case ("Examined")
--   Tutorial.onTreated(owner)                 a patient's plan at owner's clinic is done ("Treated")
--   Tutorial.onCured(owner)                   a treatment at owner's clinic paid out (Cure.resolve; "Cured")
--   Tutorial.onMade(p, itemId, plot)          kept for Stations; it moves nothing now
--   Tutorial.setReopen(fn)                    Main.server hands over Patients.reopen once (look overhaul §B10): the
--                                             Replay remote empties the caller's own line with it
--   Tutorial.REPLAY_ATTRIBUTE                 "TutorialReplay": the player attribute State forwards (a replay session)
--   Tutorial.finish(p): boolean · Tutorial.restart(p): boolean
--                                             the 🛠️ Admin panel only (Server/Admin): straight to DONE, or back to
--                                             the welcome card; each is a normal step change (old timers stop)
--   Tutorial.Pure                             the remote rules as plain values (tests/TutorialFlow.spec)

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Upgrades = require(Shared.Data.Upgrades)
local Prices = require(Shared.Logic.Prices)
local Logic = require(Shared.Logic.Tutorial)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)
local Economy = require(script.Parent.Economy)

type Plot = Types.Plot

-- PURE-BEGIN
-- The remote rules (look build plan §B1) as plain values: no Roblox types. tests/TutorialFlow.spec loads this block
-- on its own, with Logic (Shared/Logic/Tutorial) in its environment.
local Pure = {}

Pure.LOADING = "Still loading…"
Pure.ALREADY_DONE = "Already done!"
Pure.NO_CLINIC = "Get a clinic first!"
Pure.PLAYING = "Already playing it!"
Pure.TOO_SOON = "Try again soon"
Pure.NOT_SAVING = "⚠️ Not saving right now"
Pure.SKIP_TOAST = "🔁 Replay anytime in ⚙️"

-- TutorialSkip: only an active step. (ok, message)
function Pure.skip(step: any): (boolean, string)
	if step == nil then
		return false, Pure.LOADING
	end
	if not Logic.canSkip(step) then
		return false, Pure.ALREADY_DONE
	end
	return true, ""
end

-- TutorialReplay, in the plan's order: loaded, saving, done with a clinic of your own, then the cooldown.
-- lastAt = the caller's last accepted replay (os.clock), nil = never this session.
function Pure.replay(
	step: any,
	hasPlot: boolean,
	canSave: boolean,
	lastAt: number?,
	now: number,
	cooldown: number
): (boolean, string)
	if step == nil then
		return false, Pure.LOADING
	end
	if canSave ~= true then
		return false, Pure.NOT_SAVING
	end
	if Logic.active(step) then
		return false, Pure.PLAYING
	end
	if not Logic.canReplay(step, hasPlot == true) then
		return false, Pure.NO_CLINIC
	end
	if type(lastAt) == "number" and now - lastAt < cooldown then
		return false, Pure.TOO_SOON
	end
	return true, ""
end

-- What moving the save to `to` does to the one-time gift: (due, giftedAfter). The top-up is due only when entering
-- SHOP and never given before, and never on a replay. Once it ran, or the save reached DONE (a Skip, the admin
-- finish), or a replay began, TutorialGift is true for good.
function Pure.gift(to: any, gifted: any, replay: boolean?): (boolean, boolean)
	local due = replay ~= true and Logic.giftDue(to, gifted == true)
	return due, gifted == true or due or replay == true or to == Logic.DONE
end

-- A rejoin in the middle of a replay: the session attribute is gone, so the save has to say it. TutorialGift is only
-- true before SHOP on a replay (or an admin restart of an old save), never on a first run. Steps SHOP and BOOK can't
-- be told apart from a first run (the gift was given there too), so they stay a first run.
function Pure.rejoinReplay(step: any, gifted: any): boolean
	return Logic.active(step) and gifted == true and step ~= Logic.WELCOME and step < Logic.SHOP
end

-- Step SHOP only moves on from a purchase. True when there may be nothing to buy (every upgrade maxed, or the
-- cheapest one costs more than they hold: a replay has no gift), so the step moves on by itself after a beat.
function Pure.shopStuck(cash: any, cheapest: number?): boolean
	if cheapest == nil then
		return true
	end
	return type(cash) ~= "number" or cash < cheapest
end

-- The funnel stage to log for a move (Logic.funnelStep: a card number, or 8 for the Shop), or nil: first runs only,
-- and only when the stage changes (or the welcome ends: card 1 is logged as the first patient comes).
function Pure.funnel(from: any, to: any, replay: boolean?): number?
	if replay == true then
		return nil
	end
	local stage = Logic.funnelStep(to)
	if stage == nil then
		return nil
	end
	if Logic.funnelStep(from) == stage and from ~= Logic.WELCOME then
		return nil
	end
	return stage
end

-- Whether a patient model's attributes count for the watch: sat down on its bay bed (a `Bay`, and a State past the
-- walk there; no State at all counts too), or examined (`Case`).
Pure.WALKING = { Arriving = true, Waiting = true, ToBay = true } :: { [string]: boolean }
function Pure.seated(bay: any, state: any): boolean
	return type(bay) == "string" and bay ~= "" and not (type(state) == "string" and Pure.WALKING[state] == true)
end
function Pure.examined(case: any): boolean
	return type(case) == "string" and case ~= ""
end
-- PURE-END

local Tutorial = {}
Tutorial.Pure = Pure

Tutorial.CURES_ATTRIBUTE = "TutorialCures"
Tutorial.REPLAY_ATTRIBUTE = "TutorialReplay"

-- Patients.reopen, handed over by Main.server (Patients requires this module, so it can't be required here).
local reopen: ((Player) -> boolean)? = nil

function Tutorial.setReopen(fn: (Player) -> boolean)
	reopen = if type(fn) == "function" then fn else nil
end

local GIFT_TOAST = "🎁 A gift to get you started!"
local REPLAY_COOLDOWN = (Config :: any).Tutorial.ReplayCooldown :: number
local SHOP_STUCK_SECONDS = (Config :: any).Tutorial.ShopStuckSeconds :: number

local cures: { [Player]: number } = {} -- step 6: cures on their clinic so far
local tokens: { [Player]: number } = {} -- bumps on every step change, so a timer from an older step does nothing
local resumed: { [Player]: boolean } = {}
local lastReplay: { [Player]: number } = {} -- os.clock() of the last accepted TutorialReplay
local watches: { [Player]: { RBXScriptConnection } } = {} -- steps 2-3: the patients on their own clinic

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function replaying(player: Player): boolean
	return player:GetAttribute(Tutorial.REPLAY_ATTRIBUTE) == true
end

function Tutorial.step(player: Player): number?
	if not isPlayer(player) then
		return nil
	end
	local data = PlayerData.get(player)
	return data and data.Tutorial
end

function Tutorial.active(player: Player): boolean
	return Logic.active(Tutorial.step(player))
end

function Tutorial.calm(player: Player): boolean
	return Logic.calm(Tutorial.step(player))
end

function Tutorial.spawnPlan(owner: Player, plotEmpty: boolean, secondSpawned: boolean): Logic.Plan
	return Logic.spawnPlan(Tutorial.step(owner), plotEmpty, secondSpawned)
end

function Tutorial.queueCap(owner: Player): number?
	return Logic.queueCap(Tutorial.step(owner))
end

------------------------------------------------------------------------------------------------------------------
-- Analytics (published games only; every call in a pcall, so analytics can never break the tutorial)
------------------------------------------------------------------------------------------------------------------

local function logFunnel(player: Player, card: number)
	if RunService:IsStudio() then
		return
	end
	local name = Logic.FUNNEL_NAMES[card]
	if type(name) ~= "string" then
		return
	end
	local ok, err = pcall(function()
		(AnalyticsService :: any):LogOnboardingFunnelStepEvent(player, card, name)
	end)
	if not ok then
		warn("[Tutorial] funnel log: " .. tostring(err))
	end
end

local function logSkip(player: Player, step: number)
	if RunService:IsStudio() then
		return
	end
	local ok, err = pcall(function()
		(AnalyticsService :: any):LogCustomEvent(player, "TutorialSkipped", step)
	end)
	if not ok then
		warn("[Tutorial] skip log: " .. tostring(err))
	end
end

------------------------------------------------------------------------------------------------------------------
-- Moving between steps
------------------------------------------------------------------------------------------------------------------

-- The lowest next-level price over every upgrade that isn't maxed (the Shop's cheapest buy).
local function cheapestUpgrade(data: Types.Data): number?
	local prices: { number } = {}
	for _, id in Upgrades.Order do
		local price = Prices.upgradePrice(Upgrades, id, data.Upgrades[id] or 0)
		if price then
			table.insert(prices, price)
		end
	end
	return Logic.cheapest(prices)
end

local function setCures(player: Player, n: number?)
	cures[player] = n
	if player.Parent == Players then
		player:SetAttribute(Tutorial.CURES_ATTRIBUTE, if n then math.min(n, Logic.MORE_CURES) else nil)
	end
end

local apply: (player: Player, event: Logic.Event, ctx: Logic.Ctx?) -> ()

-- Runs `event` after `seconds`, if the player is still on step `expect` and nothing moved meanwhile.
local function later(player: Player, seconds: number, expect: number, event: Logic.Event)
	local token = tokens[player]
	task.delay(seconds, function()
		if player.Parent == Players and tokens[player] == token and Tutorial.step(player) == expect then
			apply(player, event)
		end
	end)
end

------------------------------------------------------------------------------------------------------------------
-- Steps 2-3: watching the patients on their own clinic (no polling; only while in those steps)
------------------------------------------------------------------------------------------------------------------

local function unwatch(player: Player)
	local list = watches[player]
	watches[player] = nil
	if list then
		for _, connection in list do
			connection:Disconnect()
		end
	end
end

-- Looks at the patients on `player`'s own clinic: one sitting in a bay moves step 2 on (after ARRIVED_SECONDS, so
-- the walk-in is seen), one with a revealed case moves steps 2-3 on. The first patient walks in during step 1, so
-- it can already be sitting there when the ack moves the step to 2: entering the step looks once too. Never yields.
local function look(player: Player)
	local step = Tutorial.step(player)
	if step ~= Logic.PATIENT and step ~= Logic.EXAMINE then
		return
	end
	local plot = Plots.getPlot(player)
	local folder = if plot then plot.Model:FindFirstChild("Patients") else nil
	if not folder then
		return
	end
	local seated, examined = false, false
	for _, model in folder:GetChildren() do
		examined = examined or Pure.examined(model:GetAttribute("Case"))
		seated = seated or Pure.seated(model:GetAttribute("Bay"), model:GetAttribute("State"))
	end
	if examined then
		apply(player, "Examined")
	elseif seated and step == Logic.PATIENT then
		later(player, Logic.ARRIVED_SECONDS, Logic.PATIENT, "Arrived") -- a repeat is harmless: the step check
	end
end

local function watch(player: Player)
	unwatch(player)
	local plot = Plots.getPlot(player)
	if not plot then
		return
	end
	local list: { RBXScriptConnection } = {}
	watches[player] = list
	local function onLook()
		look(player)
	end
	local function follow(model: Instance)
		for _, name in { "Bay", "State", "Case" } do
			table.insert(list, model:GetAttributeChangedSignal(name):Connect(onLook))
		end
	end
	local function useFolder(folder: Instance)
		table.insert(
			list,
			folder.ChildAdded:Connect(function(model: Instance)
				follow(model)
				look(player)
			end)
		)
		for _, model in folder:GetChildren() do
			follow(model)
		end
	end
	local folder = plot.Model:FindFirstChild("Patients")
	if folder then
		useFolder(folder)
	else
		table.insert(
			list,
			plot.Model.ChildAdded:Connect(function(child: Instance)
				if child.Name == "Patients" and watches[player] == list then
					useFolder(child)
				end
			end)
		)
	end
	look(player)
end

-- What starting a step does (also when a player rejoins on that step and gets their clinic).
local function enter(player: Player, step: number)
	local plot = Plots.getPlot(player)
	if step == Logic.PATIENT or step == Logic.EXAMINE then
		watch(player)
		return
	end
	unwatch(player)
	if step == Logic.WELCOME then
		if plot then
			later(player, Logic.WELCOME_FALLBACK_SECONDS, Logic.WELCOME, "Ack")
		end
	elseif step == Logic.MORE then
		if cures[player] == nil then
			setCures(player, 0)
		end
	elseif step == Logic.SHOP then
		-- A first run was just topped up to the cheapest upgrade, so this never fires there. A replay (no gift) or
		-- an old save may have nothing it can buy: move on after a beat, so the tutorial always ends.
		local data = PlayerData.get(player)
		if data and Pure.shopStuck(data.Cash, cheapestUpgrade(data)) then
			later(player, SHOP_STUCK_SECONDS, Logic.SHOP, "Purchased")
		end
	elseif step == Logic.BOOK then
		if plot then
			later(player, Logic.BOOK_SECONDS, Logic.BOOK, "BookShown")
		end
	elseif step == Logic.DONE then
		setCures(player, nil)
	end
end

-- The one way the saved step changes. `replay` = the TutorialReplay remote's move (no gift, no funnel log).
local function move(player: Player, to: number, replay: boolean?): boolean
	local data = PlayerData.get(player)
	if not data or data.Tutorial == to then
		return false
	end
	local from = data.Tutorial
	local gift = 0
	local saved = PlayerData.update(player, function(d)
		d.Tutorial = to
		local due, gifted = Pure.gift(to, d.TutorialGift, replay)
		if due then
			-- The purchase must always work: top up to the cheapest upgrade, in this same update (no yield).
			gift = Logic.topUp(d.Cash, cheapestUpgrade(d))
			if gift > 0 then
				d.Cash += gift
			end
		end
		d.TutorialGift = gifted
	end)
	if not saved then
		return false -- the save is closing (they're leaving)
	end
	tokens[player] = (tokens[player] or 0) + 1
	if gift > 0 then
		Remotes.toast(player, GIFT_TOAST)
	end
	local card = Pure.funnel(from, to, replay == true or replaying(player))
	if card then
		logFunnel(player, card)
	end
	enter(player, to)
	return true
end

apply = function(player: Player, event: Logic.Event, ctx: Logic.Ctx?)
	local step = Tutorial.step(player)
	if not step or not Logic.active(step) then
		return
	end
	local nextStep = Logic.advance(step, event, ctx)
	if nextStep ~= step then
		move(player, nextStep)
	end
end

------------------------------------------------------------------------------------------------------------------
-- Hooks (other systems call these; each one only acts on a player in the matching step)
------------------------------------------------------------------------------------------------------------------

-- Patients: a patient at `owner`'s clinic just sat down in a bay (the watch sees it too; this only looks again).
function Tutorial.onFrontArrived(owner: Player)
	if isPlayer(owner) then
		look(owner)
	end
end

-- Patients.examine: an exam at `owner`'s clinic just revealed a patient's case (by anyone, a nurse included).
function Tutorial.onExamined(owner: Player)
	apply(owner, "Examined")
end

-- Stations: `player` made or dispensed `itemId` at a station on `plot`. Fetching is no step of its own any more
-- (the client's card 4 turns into card 5 when you carry it), so this moves nothing; kept so callers stay valid.
function Tutorial.onMade(_player: Player, _itemId: string, _plot: Plot?) end

-- Patients: a patient's plan at `owner`'s clinic is done (by anyone).
function Tutorial.onTreated(owner: Player)
	apply(owner, "Treated")
end

-- Cure: a treatment just paid out at `owner`'s clinic (whoever treated it).
function Tutorial.onCured(owner: Player)
	local step = Tutorial.step(owner)
	if step == Logic.MORE then
		local n = (cures[owner] or 0) + 1
		setCures(owner, n)
		apply(owner, "Cured", { Cures = n })
	else
		apply(owner, "Cured")
	end
end

------------------------------------------------------------------------------------------------------------------
-- The 🛠️ Admin panel (Server/Admin checks the caller is an admin; nothing else calls these)
------------------------------------------------------------------------------------------------------------------

-- Straight to the end. False when there's nothing to do (not loaded, or already done).
function Tutorial.finish(player: Player): boolean
	if not isPlayer(player) then
		return false
	end
	return move(player, Logic.DONE)
end

-- Back to the welcome card, with the step-6 count cleared. True once the player is on the welcome card. A first
-- run again (the title card and sweep play), so it isn't a replay session any more.
function Tutorial.restart(player: Player): boolean
	if not isPlayer(player) or not PlayerData.get(player) then
		return false
	end
	setCures(player, nil)
	if player.Parent == Players then
		player:SetAttribute(Tutorial.REPLAY_ATTRIBUTE, nil)
	end
	move(player, Logic.WELCOME)
	return Tutorial.step(player) == Logic.WELCOME
end

------------------------------------------------------------------------------------------------------------------
-- Joining, and the remotes
------------------------------------------------------------------------------------------------------------------

-- Once per join: steps that needed the patient who left with the player start again at PATIENT.
local function resume(player: Player)
	if resumed[player] then
		return
	end
	local data = PlayerData.get(player)
	if not data then
		return
	end
	resumed[player] = true
	local step = Logic.resume(data.Tutorial)
	if step ~= data.Tutorial then
		PlayerData.update(player, function(d)
			d.Tutorial = step
		end)
	end
	-- They left in the middle of a replay: it is still a replay (full HUD, no funnel log).
	if player.Parent == Players and Pure.rejoinReplay(step, data.TutorialGift) then
		player:SetAttribute(Tutorial.REPLAY_ATTRIBUTE, true)
	end
end

local function onPlot(player: Player)
	resume(player)
	local step = Tutorial.step(player)
	if step and Logic.active(step) then
		enter(player, step)
	end
end

-- Arguments are untrusted and ignored: the ack can only ever move the welcome card on.
local function onAck(player: Player): (boolean, string)
	if Tutorial.step(player) ~= Logic.WELCOME or not Plots.getPlot(player) then
		return false, ""
	end
	apply(player, "Ack")
	return true, ""
end

-- TutorialSkip (§B1). Arguments are ignored.
local function onSkip(player: Player): (boolean, string)
	local step = Tutorial.step(player)
	local ok, message = Pure.skip(step)
	if not ok then
		return false, message
	end
	if not move(player, Logic.DONE) then
		return false, Remotes.OOPS -- the save is closing: nothing changed
	end
	logSkip(player, step :: number)
	Remotes.toast(player, Pure.SKIP_TOAST)
	return true, ""
end

-- TutorialReplay (§B1). Arguments are ignored. Only the caller's own plot (Plots.getPlot is the plot they OWN; a
-- friend standing on it, or the plot they stand on, never counts) and the caller's own save change.
local function onReplay(player: Player): (boolean, string)
	local step = Tutorial.step(player)
	local plot = Plots.getPlot(player)
	local own = plot ~= nil and plot.Owner == player
	local ok, message =
		Pure.replay(step, own, PlayerData.canSave(player), lastReplay[player], os.clock(), REPLAY_COOLDOWN)
	if not ok then
		return false, message
	end
	local hook = reopen
	if not hook or not PlayerData.isOpen(player) then
		return false, Remotes.OOPS -- Main.server never wired the line (or the save is closing): nothing changed
	end
	-- Empty the caller's own line, so the first patient comes again on the tutorial's cue.
	local reopened, result = pcall(hook, player)
	if not reopened or result ~= true then
		return false, Remotes.OOPS
	end
	lastReplay[player] = os.clock()
	setCures(player, nil)
	player:SetAttribute(Tutorial.REPLAY_ATTRIBUTE, true)
	if not move(player, Logic.advance(step :: number, "Replay"), true) then
		player:SetAttribute(Tutorial.REPLAY_ATTRIBUTE, nil)
		return false, Remotes.OOPS
	end
	return true, ""
end

function Tutorial.start()
	Remotes.setQuiet(Tutorial.active)
	Remotes.serve("TutorialAck", onAck)
	Remotes.serve("TutorialSkip", onSkip)
	Remotes.serve("TutorialReplay", onReplay)

	PlayerData.Loaded:Connect(resume)
	Plots.PlotAssigned:Connect(onPlot)
	Economy.Purchased:Connect(function(player: Player)
		apply(player, "Purchased")
	end)
	Players.PlayerRemoving:Connect(function(player)
		unwatch(player)
		cures[player] = nil
		tokens[player] = nil
		resumed[player] = nil
		lastReplay[player] = nil
	end)

	-- Players who loaded, or got their clinic, before we were listening.
	for _, player in Players:GetPlayers() do
		if PlayerData.get(player) then
			resume(player)
			if Plots.getPlot(player) then
				onPlot(player)
			end
		end
	end
end

return Tutorial
