--!strict
-- Treat sessions: recipe items given at the Counter through short mini-games, tips and the combo, Simple mode, and
-- Healer nurses' deliveries (depth-update design §1, build plan §B8). Server only. OWNER: T1.
--
--   Treatment.start()            wires TreatResult and SetSimple; connects Nurses.Heal; keeps the Combo attribute
--   Treatment.combo(p): number   the player's mini-game combo (the Combo attribute; session-only, never saved)
--   Treatment.simple(p): boolean Data.Simple
-- Between Patients and Treatment (T1's own internals; Patients requires this module, never the other way round):
--   Treatment.open(p, spec): number?   opens a session for items Patients already took (they're spent): fires
--                                      TreatStart and starts the timeout. nil = this player already has one open
--   Treatment.busy(p): boolean         a session is open for this player (one at a time)
--   Treatment.drop(session)            closes it without settling (the patient went away): no tip, no combo change,
--                                      and a late TreatResult for it is refused. Patients settles the patient itself
--   Treatment.onHeal(fn)               Patients' Healer delivery: fn(plot, nurseId) -> { ItemId } given from the tray
--
-- A session, start to end:
--   1. Patients (the Counter's TreatPrompt) matches the front patient's missing recipe items against the helper's
--      Carry, then the plot's nurse tray, takes them, marks the patient "Treating" and calls Treatment.open.
--   2. TreatStart (Types.TreatSession) goes to the helper: one game per item (Logic/MiniGame.gameFor), Simple,
--      the combo before it, where the patient is, and the Timeout.
--   3. It ends ONCE, whichever comes first:
--      · TreatResult(session, ratings): Logic/MiniGame.accept (Simple -> all Good; junk or sooner than the games'
--        minimum time x Slack -> all OK), and all OK when the helper is now farther than Config.Treat.Distance
--        from the Counter. Answers (true, "", Types.TreatOutcome).
--      · the timeout (MiniGame.timeout): all OK.
--      · the helper leaves: all OK, no tip, no combo change.
--   4. MiniGame.settle with the combo, the tip the patient has paid so far (the cap is per cure) and the plot's
--      CheerTip (Nurses.cheer). The tip is cash only (Economy.addCash to the helper); the Combo attribute updates.
--   5. spec.Settle(ratings, tip) -> complete: Patients marks the items given and either sends the patient to bed
--      (the cure as before) or back to waiting for the rest of its recipe.
-- Healers: Nurses.Heal(plot, nurseId) -> Patients delivers what the front patient needs from the tray, rated OK,
-- no tip, no combo change -> Nurses.healed(plot, nurseId, items) (only when something was delivered).
--
-- Security (build plan Review focus 1): one open session per player; TreatResult must name that player's own open
-- session (a number), anything else is refused with (false, OOPS) and changes nothing; the ratings are the
-- server's view (MiniGame.accept), never the client's word; the tip is capped per cure and is cash only;
-- Remotes.serve rate-limits (10/s) and pcalls. Kids' rules: no fail states (OK still cures), no Robux.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local MiniGame = require(Shared.Logic.MiniGame)
local Economy = require(script.Parent.Economy)
local PlayerData = require(script.Parent.PlayerData)
local Nurses = require(script.Parent.Nurses)

type Plot = Types.Plot
type Rating = Types.Rating

-- What Patients hands over when a treat starts. Patients owns the patient; Treatment owns the session.
export type Spec = {
	Plot: Plot,
	PatientId: string,
	Items: { string }, -- what is being given now, in recipe order (already taken from the helper or the tray)
	Position: Vector3, -- above the patient (the client's rating pops and coins)
	Counter: Vector3, -- the helper must still be within Config.Treat.Distance of this when they report
	TipSoFar: number, -- tip cash this patient has paid already (TipCapPerCure is per cure)
	-- Called at most once, when the session ends (never after Treatment.drop): apply the ratings to the patient.
	-- Returns true when the patient's recipe is now complete (off to bed).
	Settle: (ratings: { Rating }, tip: number) -> boolean,
}

type Session = {
	Id: number,
	Player: Player,
	Spec: Spec,
	Games: { string },
	Simple: boolean,
	Started: number, -- os.clock()
	Timer: thread?,
	Open: boolean,
}

local Treatment = {}

local COMBO_ATTRIBUTE = "Combo"
local MAX_CHEER_TIP = 3 -- a sanity cap on the plot's tip multiplier (Cheerers give at most ~1.4)

local sessions: { [Player]: Session } = {}
local lastId = 0
local healHandler: ((Plot, string) -> { string }?)? = nil

------------------------------------------------------------------------------------------------------------------
-- Pure helpers (no Roblox services, no upvalues but MiniGame: a scratch Lune harness loads this block on its own)
------------------------------------------------------------------------------------------------------------------

-- PURE-BEGIN
local Pure = {}

-- n copies of a rating
function Pure.all(rating: Rating, n: number): { Rating }
	local out: { Rating } = {}
	for index = 1, n do
		out[index] = rating
	end
	return out
end

-- The server's ratings for a session. `how`: "Report" (the client's TreatResult), "Timeout" or "Left".
-- A report is MiniGame.accept's view of it, and all OK when the helper wandered off (`near` false).
function Pure.ratings(
	how: string,
	reported: any,
	games: { string },
	elapsed: number,
	simple: boolean,
	near: boolean,
	cfg: any
): { Rating }
	if how ~= "Report" or not near then
		return Pure.all("OK", #games)
	end
	return MiniGame.accept(reported, games, elapsed, simple, cfg)
end

-- The plot's CheerTip attribute as a safe multiplier (1 = no Cheerer; junk -> 1).
function Pure.tipScale(value: any, max: number): number
	if type(value) ~= "number" or value ~= value or value < 1 then
		return 1
	end
	return math.min(value, max)
end

-- A TreatResult session id: a finite whole number, or nil.
function Pure.sessionId(value: any): number?
	if type(value) ~= "number" or value ~= value or value % 1 ~= 0 or math.abs(value) == math.huge then
		return nil
	end
	return value
end

-- The games for the items, one each (an item without a game, which Data never has, plays Pour).
function Pure.games(items: { string }): { string }
	local games: { string } = {}
	for index, itemId in items do
		games[index] = MiniGame.gameFor(itemId) or "Pour"
	end
	return games
end
-- PURE-END

------------------------------------------------------------------------------------------------------------------
-- Safety
------------------------------------------------------------------------------------------------------------------

local failures: { [string]: number } = {}
local function report(label: string, err: any)
	local count = (failures[label] or 0) + 1
	failures[label] = count
	if count <= 3 then
		warn("[Treatment] " .. label .. " failed: " .. tostring(err))
	end
end

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

------------------------------------------------------------------------------------------------------------------
-- Reads
------------------------------------------------------------------------------------------------------------------

function Treatment.combo(player: Player): number
	local combo = player:GetAttribute(COMBO_ATTRIBUTE)
	return if type(combo) == "number" and combo == combo and combo >= 0 then math.floor(combo) else 0
end

function Treatment.simple(player: Player): boolean
	local data = PlayerData.get(player)
	return data ~= nil and data.Simple == true
end

function Treatment.busy(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.Open
end

local function near(player: Player, at: Vector3): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	return (root.Position - at).Magnitude <= Config.Treat.Distance
end

local function cheerTip(plot: Plot): number
	local ok, cheer = pcall(Nurses.cheer, plot)
	if not ok then
		report("Nurses.cheer", cheer)
		return 1
	end
	return Pure.tipScale(if type(cheer) == "table" then cheer.Tip else nil, MAX_CHEER_TIP)
end

------------------------------------------------------------------------------------------------------------------
-- Sessions
------------------------------------------------------------------------------------------------------------------

local function close(session: Session)
	session.Open = false
	if sessions[session.Player] == session then
		sessions[session.Player] = nil
	end
	local timer = session.Timer
	session.Timer = nil
	if timer and timer ~= coroutine.running() and coroutine.status(timer) == "suspended" then
		task.cancel(timer)
	end
end

-- Ends a session once: the ratings, the combo and the tip, then the patient. Never yields.
local function settle(session: Session, how: string, reported: any): Types.TreatOutcome
	close(session)
	local player = session.Player
	local spec = session.Spec
	local here = how ~= "Left" and player.Parent == Players
	local elapsed = os.clock() - session.Started
	local ratings =
		Pure.ratings(how, reported, session.Games, elapsed, session.Simple, here and near(player, spec.Counter), Config)

	local combo = Treatment.combo(player)
	local tip = 0
	if here then
		combo, tip = MiniGame.settle(combo, ratings, Config, spec.TipSoFar, cheerTip(spec.Plot))
		player:SetAttribute(COMBO_ATTRIBUTE, combo)
		if tip > 0 then
			local ok, paid = pcall(Economy.addCash, player, tip)
			if not ok then
				report("Economy.addCash", paid)
			end
			if not (ok and paid == true) then
				tip = 0
			end
		end
	end

	local ok, complete = pcall(spec.Settle, ratings, tip)
	if not ok then
		report("the patient's settle", complete)
		complete = false
	end
	return { Ratings = ratings, Tip = tip, Combo = combo, Complete = complete == true }
end

function Treatment.open(player: Player, spec: Spec): number?
	if not isPlayer(player) or player.Parent ~= Players or Treatment.busy(player) then
		return nil
	end
	if type(spec) ~= "table" or type(spec.Items) ~= "table" or #spec.Items == 0 or type(spec.Settle) ~= "function" then
		return nil
	end
	lastId += 1
	local games = Pure.games(spec.Items)
	local session: Session = {
		Id = lastId,
		Player = player,
		Spec = spec,
		Games = games,
		Simple = Treatment.simple(player),
		Started = os.clock(),
		Timer = nil,
		Open = true,
	}
	sessions[player] = session
	local timeout = MiniGame.timeout(games, Config)
	session.Timer = task.delay(timeout, function()
		session.Timer = nil
		if session.Open then
			settle(session, "Timeout", nil)
		end
	end)
	local payload: Types.TreatSession = {
		Session = session.Id,
		PatientId = spec.PatientId,
		Items = table.clone(spec.Items),
		Games = table.clone(games) :: any,
		Simple = session.Simple,
		Combo = Treatment.combo(player),
		Position = spec.Position,
		Timeout = timeout,
	}
	Remotes.TreatStart:FireClient(player, payload)
	return session.Id
end

function Treatment.drop(sessionId: number)
	for _, session in sessions do
		if session.Id == sessionId then
			close(session)
			return
		end
	end
end

function Treatment.onHeal(fn: (Plot, string) -> { string }?)
	healHandler = fn
end

------------------------------------------------------------------------------------------------------------------
-- Remotes
------------------------------------------------------------------------------------------------------------------

-- TreatResult(session, ratings). Every argument is untrusted.
local function onResult(player: Player, sessionArg: any, reported: any): (boolean, string, Types.TreatOutcome?)
	local id = Pure.sessionId(sessionArg)
	local session = sessions[player]
	if id == nil or not session or not session.Open or session.Id ~= id then
		return false, Remotes.OOPS -- not this player's open session (late, junk or someone else's): nothing changes
	end
	return true, "", settle(session, "Report", reported)
end

local function setSimple(player: Player, on: any): (boolean, string)
	if type(on) ~= "boolean" then
		return false, Remotes.OOPS
	end
	local data = PlayerData.get(player)
	if not data then
		return false, Remotes.OOPS
	end
	local message = if on then "👆 Simple taps on!" else "🎮 Mini-games on!"
	if data.Simple == on then
		return true, message -- nothing changes: no save write, no snapshot push
	end
	PlayerData.update(player, function(d)
		d.Simple = on
	end)
	return true, message
end

-- A Healer is ready: Patients gives the front patient what the tray holds for it (OK, no tip, no combo).
local function onHeal(plot: any, nurseId: any)
	local handler = healHandler
	if (type(plot) ~= "table" and typeof(plot) ~= "Instance") or type(nurseId) ~= "string" or not handler then
		return -- (a plot is the Plots table; its Model is accepted too, Patients resolves it)
	end
	local ok, items = pcall(handler, plot, nurseId)
	if not ok then
		report("the Healer delivery", items)
		return
	end
	if type(items) == "table" and #items > 0 then
		local told, err = pcall(Nurses.healed, plot, nurseId, items)
		if not told then
			report("Nurses.healed", err)
		end
	end
end

function Treatment.start()
	Remotes.serve("TreatResult", onResult)
	Remotes.serve("SetSimple", setSimple)
	Nurses.Heal:Connect(onHeal)

	local function onJoin(player: Player)
		if player:GetAttribute(COMBO_ATTRIBUTE) == nil then
			player:SetAttribute(COMBO_ATTRIBUTE, 0)
		end
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		onJoin(player)
	end
	-- The helper left mid-game: the items they gave still count (all OK), so the patient isn't stuck.
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session and session.Open then
			settle(session, "Left", nil)
		end
		sessions[player] = nil
	end)
end

return Treatment
