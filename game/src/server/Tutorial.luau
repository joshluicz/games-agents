--!strict
-- The first-session tutorial (docs/plan/2026-11-16-first-session-design.md §B). Server only.
-- The step is server-authoritative and saved (Data.Tutorial; the rules are in Logic/Tutorial). The client shows it
-- from the Snapshot (UI/Tutorial, Hud) and can only ever ask to move past the welcome card.
--
-- How each step moves on. Every move is a real server event, never the client's word:
--   1 -> 2     the TutorialAck remote (Remotes.serve: rate-limited, pcalled), only while the player has a clinic.
--              If no ack comes, by itself WELCOME_FALLBACK_SECONDS after they got their clinic
--   2 -> 3     ARRIVED_SECONDS after the first patient reaches the Counter (Patients calls onFrontArrived). Look
--              overhaul: that patient walks in during step 1 already, so entering step 2 with it at the Counter
--              (the plot's FrontItem is set) counts as the arrival too
--   3 -> 4     the owner makes, at a station on their own clinic, the item the front patient needs (Stations
--              calls onMade). Already carrying it when step 3 starts: straight to 4
--   2..4 -> 5  the front patient on their clinic is treated, by them or a friend (Patients calls onTreated)
--   2..5 -> 6  a cure lands on their clinic (Cure calls onCured)
--   6 -> 7     two more cures on their clinic. The count is the player attribute TutorialCures (State sends it;
--              not saved, so a rejoin in step 6 counts 2 more from 0).
--              Entering 7: a player who can't afford the cheapest upgrade gets a top-up to exactly its price in
--              the same save update, with the toast "🎁 A gift to get you started!". In-game cash only, never
--              Robux, a pass or anything paid (CLAUDE.md red line 3). Once per player: step 7 is entered once,
--              because steps only go forward
--   7 -> 8     any purchase (Economy.Purchased)
--   8 -> 9     BOOK_SECONDS later: done
-- A rejoin resumes (Logic/Tutorial.resume): steps 3-5 go back to 2, since their patient left with the player.
-- While a player is in the tutorial they are quiet (Remotes.setQuiet): ambient news toasts wait (Remotes.news,
-- Remotes.toastAll); replies and warnings still show.
--
-- API (safe for anyone: a player who isn't loaded, or is done, just gets "not in the tutorial"):
--   Tutorial.step(p): number?                 the saved step (nil = not loaded)
--   Tutorial.active(p): boolean               in the tutorial right now
--   Tutorial.calm(p): boolean                 patience never runs out at their clinic (steps 1-6)
--   Tutorial.spawnPlan(owner, plotEmpty, secondSpawned): Plan   who Patients may send next (Logic/Tutorial)
--   Tutorial.queueCap(owner): number?         at most this many in line, nil = Config.MaxQueue
--   Tutorial.onFrontArrived(owner) · Tutorial.onMade(p, itemId, plot) · Tutorial.onTreated(owner) ·
--   Tutorial.onCured(owner)                   the hooks above
--   Tutorial.setReopen(fn)                    Main.server hands over Patients.reopen once (look overhaul §B10): the
--                                             Replay remote empties the caller's own line with it
--   Tutorial.REPLAY_ATTRIBUTE                 "TutorialReplay": the player attribute State forwards (a replay session)
-- Look overhaul (build plan §B1): the TutorialSkip and TutorialReplay remotes. STUB (T8): both are served here and
-- answer (false, Remotes.SOON) until T8 writes their rules.
--   Tutorial.finish(p): boolean · Tutorial.restart(p): boolean
--                                             the 🛠️ Admin panel only (Server/Admin): straight to DONE, or back to
--                                             the welcome card; each is a normal step change (old timers stop)

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Upgrades = require(Shared.Data.Upgrades)
local Prices = require(Shared.Logic.Prices)
local Logic = require(Shared.Logic.Tutorial)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)
local Carry = require(script.Parent.Carry)
local Economy = require(script.Parent.Economy)

type Plot = Types.Plot

local Tutorial = {}

Tutorial.CURES_ATTRIBUTE = "TutorialCures"
Tutorial.REPLAY_ATTRIBUTE = "TutorialReplay"

-- Patients.reopen, handed over by Main.server (Patients requires this module, so it can't be required here).
local reopen: ((Player) -> boolean)? = nil

function Tutorial.setReopen(fn: (Player) -> boolean)
	reopen = if type(fn) == "function" then fn else nil
end

local GIFT_TOAST = "🎁 A gift to get you started!"

local cures: { [Player]: number } = {} -- step 6: cures on their clinic so far
local tokens: { [Player]: number } = {} -- bumps on every step change, so a timer from an older step does nothing
local resumed: { [Player]: boolean } = {}

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
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

-- What starting a step does (also when a player rejoins on that step and gets their clinic).
local function enter(player: Player, step: number)
	local plot = Plots.getPlot(player)
	if step == Logic.WELCOME then
		if plot then
			later(player, Logic.WELCOME_FALLBACK_SECONDS, Logic.WELCOME, "Ack")
		end
	elseif step == Logic.PATIENT then
		-- FOUNDATION (look overhaul): the first patient now comes during the welcome sweep (Logic.spawnPlan), so it
		-- can already be standing at the Counter when the ack moves the step here. Its onFrontArrived came while the
		-- step was still WELCOME and did nothing, so count the arrival now (FrontItem is set only while a patient
		-- waits at the Counter). Without this the tutorial would wait at step 2 for ever.
		local front = if plot then plot.Model:GetAttribute("FrontItem") else nil
		if type(front) == "string" and front ~= "" then
			later(player, Logic.ARRIVED_SECONDS, Logic.PATIENT, "Arrived")
		end
	elseif step == Logic.MAKE then
		-- Made it early (while the patient walked in): carrying it already counts.
		local front = if plot then plot.Model:GetAttribute("FrontItem") else nil
		if type(front) == "string" and front ~= "" and Carry.has(player, front) then
			apply(player, "Made", { Right = true })
		end
	elseif step == Logic.MORE then
		if cures[player] == nil then
			setCures(player, 0)
		end
	elseif step == Logic.BOOK then
		if plot then
			later(player, Logic.BOOK_SECONDS, Logic.BOOK, "BookShown")
		end
	elseif step == Logic.DONE then
		setCures(player, nil)
	end
end

local function move(player: Player, to: number): boolean
	local data = PlayerData.get(player)
	if not data or data.Tutorial == to then
		return false
	end
	local gift = 0
	local saved = PlayerData.update(player, function(d)
		d.Tutorial = to
		if to == Logic.SHOP then
			-- The purchase must always work: top up to the cheapest upgrade, in this same update (no yield).
			gift = Logic.topUp(d.Cash, cheapestUpgrade(d))
			if gift > 0 then
				d.Cash += gift
			end
		end
	end)
	if not saved then
		return false -- the save is closing (they're leaving)
	end
	tokens[player] = (tokens[player] or 0) + 1
	if gift > 0 then
		Remotes.toast(player, GIFT_TOAST)
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

-- Patients: the patient at the front of `owner`'s line just reached the Counter.
function Tutorial.onFrontArrived(owner: Player)
	if Tutorial.step(owner) == Logic.PATIENT then
		later(owner, Logic.ARRIVED_SECONDS, Logic.PATIENT, "Arrived")
	end
end

-- Stations: `player` made `itemId` at a station on `plot`.
function Tutorial.onMade(player: Player, itemId: string, plot: Plot?)
	if Tutorial.step(player) ~= Logic.MAKE then
		return
	end
	local own = Plots.getPlot(player)
	if not own or own ~= plot then
		return -- only their own clinic teaches their tutorial
	end
	local front = own.Model:GetAttribute("FrontItem")
	apply(player, "Made", { Right = type(front) == "string" and front == itemId })
end

-- Patients: the front patient at `owner`'s clinic was just treated (by anyone).
function Tutorial.onTreated(owner: Player)
	apply(owner, "Treated")
end

-- Cure: a cure just landed at `owner`'s clinic (whoever treated it).
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

-- Back to the welcome card, with the step-6 count cleared. True once the player is on the welcome card.
function Tutorial.restart(player: Player): boolean
	if not isPlayer(player) or not PlayerData.get(player) then
		return false
	end
	setCures(player, nil)
	move(player, Logic.WELCOME)
	return Tutorial.step(player) == Logic.WELCOME
end

------------------------------------------------------------------------------------------------------------------
-- Joining, and the TutorialAck remote
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

-- STUB (T8): the rules are build plan §B1 (canSkip, move to DONE without a gift, the cures cleared, the toast).
local function onSkip(_player: Player): (boolean, string)
	return false, Remotes.SOON
end

-- STUB (T8): the rules are build plan §B1 (canReplay, the cooldown, `reopen` on the caller's own line, the
-- REPLAY_ATTRIBUTE, move to PATIENT; TutorialGift is already true, so there is never a second gift).
local function onReplay(_player: Player): (boolean, string)
	local _hook = reopen
	return false, Remotes.SOON
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
		cures[player] = nil
		tokens[player] = nil
		resumed[player] = nil
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
