--!strict
-- Treat sessions: recipe items given at the Counter through short mini-games, tips and the combo, Simple mode, and
-- Healer nurses' deliveries (depth-update design §1, build plan §B8). Server only. OWNER: T7 (Progression v2).
--
--   Treatment.start()            wires TreatResult, SetSimple and Triage; connects Nurses.Heal; keeps the Combo
--                                attribute
--   Treatment.combo(p): number   the player's mini-game combo (the Combo attribute; session-only, never saved)
--   Treatment.simple(p): boolean Data.Simple
-- Between Patients and Treatment (Patients requires this module, never the other way round):
--   Treatment.open(p, spec): number?   opens a session for items Patients already took (they're spent): fires
--                                      TreatStart and starts the timeout. nil = this player already has one open.
--                                      Progression v2: spec.Kind "Treat" (default) | "Soak" (the Hydro hot tub's one
--                                      🫧 Scrub game: Items = {}, a tip only); spec.Medicines (the medicines among
--                                      Items: each is ONE 🧪 Pour game, Logic/MiniGame.gameFor). It asks
--                                      Abilities.consumePerfects(plot, games) for TreatSession.Auto (an ability made
--                                      that game PERFECT: always rated Perfect, the client skips it) and sends Ease
--                                      (the helper's 🎯 Steady Hands, Logic/Rebirth.effects; client only, never checked)
--   Treatment.busy(p): boolean         a session is open for this player (one at a time)
--   Treatment.drop(session)            closes it without settling (the patient went away): no tip, no combo change,
--                                      and a late TreatResult for it is refused. Patients settles the patient itself
--   Treatment.onHeal(fn)               Patients' nurse delivery: fn(plot, nurseId, target) -> { ItemId } given from the
--                                      tray. target "Front" (a Healer: the front patient; #2 too with Twin Counters) |
--                                      "Urgent" (a Medic: the 🚑/🚁 patient in line)
--   Treatment.waitTriage(p, session, options, right): DeptId | ""   Progression v2 (§B3 Triage): yields until the
--                                      helper picks a floor for the patient whose recipe `session` completed (the
--                                      Triage remote), or Config.Triage.Seconds from the TreatResult run out, or they
--                                      leave. Returns what they picked ("" = no pick: the patient goes by itself, no
--                                      bonus). Patients always sends it the right way (`right`); a right pick is +10%.
--                                      A session that wasn't settled by the helper's own report (a timeout, a
--                                      nurse) has nobody to ask: "" at once
--
-- Triage (Progression v2, build plan §B3, §E8; Lv 3+, no Receptionist on duty). When spec.Settle answers
-- (true, { Options, Right }) for a TreatResult report, the outcome gains Triage = { Options, Seconds } (the client shows
-- two huge buttons and a soft bar, no digits) and ONE pending pick per player is kept, keyed to that session.
-- Triage(session, dept): your own pending pick only, `dept` one of its Options, inside the window, once. Right:
-- (true, "✅ Right floor!", { Right = true }). Wrong: (true, "Oops, not this floor!", { Right = false }) and the
-- patient goes the right way anyway. Anything else: (false, OOPS) and nothing changes.
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
--   5. spec.Settle(ratings, tip) -> complete, triage?: Patients marks the items given and either sends the patient
--      to bed (the cure as before; Lv 3+ maybe after a floor pick, Triage above) or back to waiting for the rest of
--      its recipe. A Soak only adds its tip to the patient's (TipSoFar shares the cap).
-- Nurses: Nurses.Heal(plot, nurseId, target) -> Patients delivers what the patient needs from the tray, rated OK,
-- no tip, no combo change -> Nurses.healed(plot, nurseId, items) (only when something was delivered).
--
-- Security (build plan Review focus 1): one open session per player; TreatResult must name that player's own open
-- session (a number), anything else is refused with (false, OOPS) and changes nothing; the ratings are the
-- server's view (MiniGame.accept), never the client's word (an Auto game is the server's own flag); the tip is
-- capped per cure and is cash only; Remotes.serve rate-limits (10/s) and pcalls. Kids' rules: no fail states (OK
-- still cures; a wrong floor still goes the right way), no clocks (the triage bar has no digits), no Robux.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local MiniGame = require(Shared.Logic.MiniGame)
local RebirthLogic = require(Shared.Logic.Rebirth)
local PerksData = require(Shared.Data.Perks)
local TreeData = require(Shared.Data.Tree)
local Abilities = require(script.Parent.Abilities)
local Economy = require(script.Parent.Economy)
local PlayerData = require(script.Parent.PlayerData)
local Nurses = require(script.Parent.Nurses)

type Plot = Types.Plot
type Rating = Types.Rating

-- A floor to pick for a patient whose recipe a session completed (Patients' Settle answers it; Lv 3+).
export type TriageAsk = { Options: { string }, Right: string }

-- What Patients hands over when a treat starts. Patients owns the patient; Treatment owns the session.
export type Spec = {
	Plot: Plot,
	PatientId: string,
	Kind: string?, -- "Treat" (nil) | "Soak": the hot tub's one 🫧 Scrub game (Items = {}, a tip only)
	Items: { string }, -- what is being given now, one game each (already taken from the helper or the tray)
	Medicines: { string }?, -- the medicines among Items (each one 🧪 Pour game that filled two recipe slots)
	Position: Vector3, -- above the patient (the client's rating pops and coins)
	Counter: Vector3, -- the helper must still be within Config.Treat.Distance of this when they report (the tub's
	-- spot for a Soak)
	TipSoFar: number, -- tip cash this patient has paid already (TipCapPerCure is per cure, a Soak's tip included)
	-- Called at most once, when the session ends (never after Treatment.drop): apply the ratings to the patient.
	-- Returns true when the patient's recipe is now complete (off to bed), and a TriageAsk when the helper may pick
	-- its floor (Lv 3+, no Receptionist on duty).
	Settle: (ratings: { Rating }, tip: number) -> (boolean, TriageAsk?),
}

type Session = {
	Id: number,
	Player: Player,
	Spec: Spec,
	Kind: string, -- "Treat" | "Soak"
	Games: { string },
	Auto: { boolean }, -- per game: an ability made it PERFECT
	Simple: boolean,
	Started: number, -- os.clock()
	Timer: thread?,
	Open: boolean,
}

-- A floor pick waiting for its player (one at a time per player).
type Pending = { Session: number, Options: { string }, Right: string, Ends: number, Pick: string? }

local Treatment = {}

local COMBO_ATTRIBUTE = "Combo"
local MAX_CHEER_TIP = 3 -- a sanity cap on the plot's tip multiplier (Cheerers give at most ~1.4)
local TRIAGE_POLL = 0.1 -- waitTriage looks for the pick this often
local RIGHT_FLOOR = "✅ Right floor!"
local WRONG_FLOOR = "Oops, not this floor!"

local sessions: { [Player]: Session } = {}
local pending: { [Player]: Pending } = {}
local lastId = 0
local healHandler: ((Plot, string, string) -> { string }?)? = nil

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
-- A report is MiniGame.accept's view of it, and all OK when the helper wandered off (`near` false). Whatever
-- happened, a game an ability made PERFECT (`auto`, the server's own flags) is Perfect: the ability was spent.
function Pure.ratings(
	how: string,
	reported: any,
	games: { string },
	elapsed: number,
	simple: boolean,
	near: boolean,
	cfg: any,
	auto: { boolean }?
): { Rating }
	if how ~= "Report" or not near then
		local out = Pure.all("OK", #games)
		if type(auto) == "table" then
			for index in out do
				if auto[index] == true then
					out[index] = "Perfect"
				end
			end
		end
		return out
	end
	return MiniGame.accept(reported, games, elapsed, simple, cfg, auto)
end

-- A session's Auto flags from Abilities.consumePerfects: exactly one boolean per game (junk -> false).
function Pure.autoFlags(value: any, n: number): { boolean }
	local out: { boolean } = {}
	for index = 1, n do
		out[index] = type(value) == "table" and value[index] == true
	end
	return out
end

-- TreatSession.Ease: the 🎯 Steady Hands factor, 1..1.3 (junk -> 1).
function Pure.ease(value: any): number
	if type(value) ~= "number" or value ~= value then
		return 1
	end
	return math.clamp(value, 1, 1.3)
end

-- The Hydro hot tub's game: one 🫧 Scrub.
function Pure.soakGames(): { string }
	return { "Scrub" }
end

-- A Settle's TriageAsk, cleaned: two or more distinct string Options and a Right among them, else nil.
function Pure.triageAsk(value: any): { Options: { string }, Right: string }?
	if type(value) ~= "table" or type(value.Options) ~= "table" or type(value.Right) ~= "string" then
		return nil
	end
	local options: { string } = {}
	for _, option in value.Options do
		if type(option) == "string" and not table.find(options, option) then
			table.insert(options, option)
		end
	end
	if #options < 2 or not table.find(options, value.Right) then
		return nil
	end
	return { Options = options, Right = value.Right }
end

-- A Triage(session, dept) call against the player's pending pick: nil = refused (no pick waiting, someone else's or
-- an old session, already picked, the window is over, or not one of its Options); else whether it's the right floor.
function Pure.triageCheck(entry: any, session: number?, dept: any, now: number): boolean?
	if type(entry) ~= "table" or session == nil or entry.Session ~= session or entry.Pick ~= nil then
		return nil
	end
	if type(now) ~= "number" or now > entry.Ends or type(dept) ~= "string" then
		return nil
	end
	if not table.find(entry.Options, dept) then
		return nil
	end
	return dept == entry.Right
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

-- Which games a banked AutoPerfect ability (Quick Bandage, Quick Soap, Golden Touch) makes PERFECT, spending it.
local function consumePerfects(plot: Plot, games: { string }): { boolean }
	local ok, flags = pcall(Abilities.consumePerfects, plot, games)
	if not ok then
		report("Abilities.consumePerfects", flags)
	end
	return Pure.autoFlags(if ok then flags else nil, #games)
end

-- The helper's own 🎯 Steady Hands (their tree): how much wider the client draws the Perfect windows.
local function easeFor(player: Player): number
	local data = PlayerData.get(player)
	if not data then
		return 1
	end
	local ok, effects = pcall(RebirthLogic.effects, data, Config, PerksData, TreeData)
	if not ok then
		report("Rebirth.effects", effects)
		return 1
	end
	return Pure.ease(if type(effects) == "table" then effects.Ease else nil)
end

local function triageSeconds(): number
	local seconds = Config.Triage and Config.Triage.Seconds
	return if type(seconds) == "number" and seconds > 0 and seconds < 60 then seconds else 4
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
	local ratings = Pure.ratings(
		how,
		reported,
		session.Games,
		elapsed,
		session.Simple,
		here and near(player, spec.Counter),
		Config,
		session.Auto
	)

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

	local ok, complete, ask = pcall(spec.Settle, ratings, tip)
	if not ok then
		report("the patient's settle", complete)
		complete = false
		ask = nil
	end
	local outcome: Types.TreatOutcome = { Ratings = ratings, Tip = tip, Combo = combo, Complete = complete == true }
	-- Triage: only the helper's own report has someone there to pick (a timeout or a helper who left: it goes by
	-- itself). One pending pick per player; a newer one replaces it (the older patient then goes by itself).
	local triage = if complete == true and how == "Report" and here then Pure.triageAsk(ask) else nil
	if triage then
		local seconds = triageSeconds()
		pending[player] = {
			Session = session.Id,
			Options = triage.Options,
			Right = triage.Right,
			Ends = os.clock() + seconds,
			Pick = nil,
		}
		outcome.Triage = { Options = table.clone(triage.Options), Seconds = seconds }
	end
	return outcome
end

function Treatment.open(player: Player, spec: Spec): number?
	if not isPlayer(player) or player.Parent ~= Players or Treatment.busy(player) then
		return nil
	end
	if type(spec) ~= "table" or type(spec.Items) ~= "table" or type(spec.Settle) ~= "function" then
		return nil
	end
	local kind = if spec.Kind == "Soak" then "Soak" else "Treat"
	if kind == "Treat" and #spec.Items == 0 then
		return nil
	end
	lastId += 1
	local games = if kind == "Soak" then Pure.soakGames() else Pure.games(spec.Items)
	local auto = consumePerfects(spec.Plot, games)
	local session: Session = {
		Id = lastId,
		Player = player,
		Spec = spec,
		Kind = kind,
		Games = games,
		Auto = auto,
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
		Items = if kind == "Soak" then {} else table.clone(spec.Items),
		Games = table.clone(games) :: any,
		Simple = session.Simple,
		Combo = Treatment.combo(player),
		Position = spec.Position,
		Timeout = timeout,
		Kind = (if kind == "Soak" then "Soak" else "Treat") :: any,
		Auto = table.clone(auto),
		Ease = easeFor(player),
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

function Treatment.onHeal(fn: (Plot, string, string) -> { string }?)
	healHandler = fn
end

function Treatment.waitTriage(player: Player, session: number, _options: { string }, _right: string): string
	-- The options and the right answer were kept when the session settled (Pending); these two only say what
	-- Patients asked.
	local entry = if isPlayer(player) then pending[player] else nil
	if not entry or entry.Session ~= session then
		return "" -- nobody to ask (a timeout, a nurse, an old session): it goes by itself
	end
	while pending[player] == entry and entry.Pick == nil and os.clock() < entry.Ends and player.Parent == Players do
		task.wait(TRIAGE_POLL)
	end
	if pending[player] == entry then
		pending[player] = nil
	end
	return entry.Pick or ""
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

-- Triage(session, dept). Every argument is untrusted.
local function onTriage(player: Player, sessionArg: any, deptArg: any): (boolean, string, any)
	local entry = pending[player]
	local right = Pure.triageCheck(entry, Pure.sessionId(sessionArg), deptArg, os.clock())
	if right == nil or not entry then
		return false, Remotes.OOPS -- not your pending pick (late, junk, someone else's, picked already): nothing changes
	end
	entry.Pick = deptArg
	return true, if right then RIGHT_FLOOR else WRONG_FLOOR, { Right = right }
end

-- A nurse is ready: Patients gives a patient what the tray holds for it (OK, no tip, no combo). A Healer sends
-- target "Front", a Medic "Urgent" (anything else counts as "Front").
local function onHeal(plot: any, nurseId: any, target: any)
	local handler = healHandler
	if (type(plot) ~= "table" and typeof(plot) ~= "Instance") or type(nurseId) ~= "string" or not handler then
		return -- (a plot is the Plots table; its Model is accepted too, Patients resolves it)
	end
	local ok, items = pcall(handler, plot, nurseId, if target == "Urgent" then "Urgent" else "Front")
	if not ok then
		report("the nurse delivery", items)
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
	Remotes.serve("Triage", onTriage)
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
		pending[player] = nil -- a pick they never made: the patient goes by itself
	end)
end

return Treatment
