--!strict
-- Sessions: every beat of a visit is one short session of mini-games (Real Clinic build plan, Task 5; design §5, §7,
-- §9; contract C5). Server only. Exams and treatments at a bay, dispensing at the dispensary, tips and the combo,
-- Simple mode, and Healer nurses' deliveries.
--
--   Treatment.start()            wires TreatResult, SetSimple and Triage; connects Nurses.Heal; keeps the Combo
--                                attribute
--   Treatment.combo(p): number   the player's mini-game combo (the Combo attribute; session-only, never saved)
--   Treatment.simple(p): boolean Data.Simple
-- Between the systems and Treatment (Patients and Stations require this module, never the other way round):
--   Treatment.open(p, spec): number?   opens a session: fires TreatStart (Types.TreatSession) and starts the timeout.
--                                      nil = refused: this player already has one open, the patient (spec.Key)
--                                      already has one open (one session per patient: Review Focus 3), or the spec
--                                      is broken. spec.Kind:
--        "Exam"      at a bay, before the case is known. spec.Tools (the card's tools, Logic/Visit.examTools),
--                    spec.Answer (the right one, among them), spec.Glow, spec.Case (what the exam reveals; never sent
--                    with TreatStart). Games = { "Pick", Data/Tools[Answer].Game }. Settling it, whatever the
--                    ratings, reveals the case: TreatOutcome.Case = spec.Case (after spec.Settle, where Patients
--                    marks the patient examined)
--        "Treat"     at a bay (nil = "Treat"): spec.Items are the supplies Patients already took (they're spent),
--                    one game each (Data/Items Game, Logic/MiniGame.gameFor). A medicine has no game: it is handed
--                    over with no session, so a Treat that names one is refused. spec.Case goes to the client
--                    A HANDOVER (spec.Handover = true, Items {}): the medicine(s) whose handing over completes the
--                    plan of a patient who stays, when its ward is the helper's to pick. No games at all
--                    (TreatSession.Games {} and Handover true): the client answers at once and the session is only
--                    there to carry the ward pick (Triage below) to the player; unanswered, it settles by itself
--                    after Pure.HANDOVER_SECONDS. No tip, no combo change, no ability spent
--        "Dispense"  at the dispensary (Server/Stations): spec.Options = the medicines bay patients still need (only
--                    known medicines are kept, at most Config.Dispensary.Options). Games = { "Pick", "Dose" }. The
--                    report's third value names the medicine (Choice); spec.Give(choice) puts it in the player's
--                    hands (Carry.add) BEFORE any tip and says whether this dispense may tip. spec.Expert (the
--                    clinic's Pharmacy2 unlock, "Expert Dispensing") sends TreatSession.Tuning.Dose: the Dose
--                    game's Perfect band Config.Dispensary.ExpertBand (x1.5) wider round its middle
--                    Every kind asks Abilities.consumePerfects(plot, games) for TreatSession.Auto (an ability made
--                    that game PERFECT: always rated Perfect, the client skips it) and sends Ease (the player's
--                    🎯 Steady Hands, Logic/Rebirth.effects; client only, never checked)
--   Treatment.busy(p): boolean         a session is open for this player (one at a time)
--   Treatment.working(key, plot?): boolean   a session is open on this patient (spec.Key, on that plot when given:
--                                      ids may restart per plot)
--   Treatment.drop(session)            closes it without settling (the patient went away): no tip, no combo change,
--                                      and a late TreatResult for it is refused. Patients settles the patient itself
--   Treatment.onHeal(fn)               Patients' nurse delivery: fn(plot, nurseId, target) -> { ItemId } given from the
--                                      tray. target "Front" (a Healer: the front bay patient) | "Urgent" (a Medic: the
--                                      🚑/🚁 patient)
--   Treatment.waitTriage(p, session, options, right): DeptId | ""   yields until the player picks a ward for the
--                                      patient whose plan `session` completed (the Triage remote), or
--                                      Config.Triage.Seconds from the TreatResult run out, or they leave. Returns what
--                                      they picked ("" = no pick: the patient goes by itself, no bonus). Patients
--                                      always sends it the right way (`right`); a right pick is +10%. A session that
--                                      wasn't settled by the player's own report (a timeout, a nurse) has nobody to
--                                      ask: "" at once
--
-- Triage (Lv 3+, no Receptionist on duty). When spec.Settle answers (true, { Options, Right }) for a TreatResult
-- report, the outcome gains Triage = { Options, Seconds } (the client shows two huge buttons and a soft bar, no
-- digits) and ONE pending pick per player is kept, keyed to that session. Triage(session, dept): your own pending
-- pick only, `dept` one of its Options, inside the window, once. Right: (true, "✅ Right floor!", { Right = true }).
-- Wrong: (true, "Oops, not this floor!", { Right = false }) and the patient goes the right way anyway. Anything else:
-- (false, OOPS) and nothing changes.
--
-- A session, start to end:
--   1. Patients (the bay's BayPrompt: Examine, then Treat) or Stations (the dispensary's Dispense prompt) calls
--      Treatment.open.
--   2. TreatStart goes to the player: the games, Simple, the combo before it, where it happens and the Timeout.
--   3. It ends ONCE, whichever comes first:
--      · TreatResult(session, ratings, choice?): Logic/MiniGame.accept (Simple -> all Good; junk or sooner than the
--        games' minimum time x Slack -> all OK), and all OK when the player is now farther than Config.Treat.Distance
--        from spec.Counter (the bay's DoctorSpot, or the dispensary counter). A Dispense whose choice isn't one of its
--        Options gives nothing and is rated all OK. Answers (true, "", Types.TreatOutcome).
--      · the timeout (MiniGame.timeout: generous, with Config.MiniGame.UntimedSeconds for every step that waits
--        for a tap): all OK. A Dispense timeout gives nothing and says so ("💊 Hold Dispense to try again!").
--      · the player leaves: an Exam or a Treat settles all OK with no tip and no combo change (the supplies given
--        still count, the case is still found, so the bay patient waits for the next doctor); a Dispense is dropped
--        and gives nothing (Review Focus 4).
--   4. A Dispense first gives the medicine (spec.Give); no medicine, no tip. Then MiniGame.settle with the combo, the
--      tip paid so far (spec.TipSoFar: the cap is per patient) and the plot's CheerTip (Nurses.cheer). The tip is
--      cash only (Economy.addCash to the player); the Combo attribute updates. A Dispense that may not tip (Give's
--      second answer: a need another dispense already tipped for) still moves the combo but pays nothing.
--   5. An Exam or a Treat then calls spec.Settle(ratings, tip) -> complete, triage?: Patients marks the case found or
--      the supplies given and either finishes the visit (a ward stay maybe after a floor pick, Triage above) or
--      waits for the rest of the plan.
-- Nurses: Nurses.Heal(plot, nurseId, target) -> Patients examines or hands over what the patient needs from the tray
-- (no game, no tip, no combo change) -> Nurses.healed(plot, nurseId, items) (only when something was delivered).
--
-- Security (Review Focus 3/4): one open session per player and per patient; TreatResult must name that player's own
-- open session (a number), anything else is refused with (false, OOPS) and changes nothing; the ratings are the
-- server's view (MiniGame.accept), never the client's word (an Auto game is the server's own flag); the choice must
-- be one of the server's own Options; the tip is capped per patient and is cash only; Remotes.serve rate-limits
-- (10/s) and pcalls. Kids' rules: no fail states (OK still treats; a wrong floor still goes the right way), no clocks
-- (the triage bar has no digits), no Robux.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local MiniGame = require(Shared.Logic.MiniGame)
local RebirthLogic = require(Shared.Logic.Rebirth)
local ItemsData = require(Shared.Data.Items)
local ToolsData = require(Shared.Data.Tools)
local PerksData = require(Shared.Data.Perks)
local TreeData = require(Shared.Data.Tree)
local Abilities = require(script.Parent.Abilities)
local Economy = require(script.Parent.Economy)
local PlayerData = require(script.Parent.PlayerData)
local Nurses = require(script.Parent.Nurses)

type Plot = Types.Plot
type Rating = Types.Rating

-- A floor to pick for a patient whose plan a session completed (Patients' Settle answers it; Lv 3+).
export type TriageAsk = { Options: { string }, Right: string }

-- What a caller hands over when a session starts. The caller owns the patient (or the dispensary); Treatment owns
-- the session.
export type Spec = {
	Plot: Plot,
	PatientId: string, -- the patient's species ("" for a Dispense)
	-- The patient's own id (Patients' numeric visit id): Treatment keeps ONE open session per patient (per Key on
	-- the same Plot). nil = none (a Dispense works on no patient)
	Key: any?,
	Kind: string?, -- "Exam" | "Treat" (nil) | "Dispense"
	Items: { string }?, -- Treat: the supplies being given now, one game each (already taken); {} or nil otherwise
	Position: Vector3, -- above the patient, or above the dispensary counter (the client's rating pops and coins)
	-- The player must still be within Config.Treat.Distance of this when they report: the bay's DoctorSpot (Exam,
	-- Treat) or the dispensary counter (Dispense)
	Counter: Vector3,
	TipSoFar: number, -- tip cash this patient has paid already (TipCapPerCure is per patient); 0 for a Dispense
	Case: string?, -- Exam: the case the exam reveals (never sent with TreatStart); Treat: the case, for the card
	Tools: { string }?, -- Exam: the card's tools (Logic/Visit.examTools)
	Answer: string?, -- Exam: the right tool, one of Tools
	Glow: boolean?, -- Exam: the right tool glows (Logic/Visit.glow)
	Symptom: string?, -- Exam: the patient's symptom bubble, the card's clue (sent with TreatStart)
	Plan: { string }?, -- Exam: the patient's own plan, revealed with the case (TreatOutcome.Plan; never sent before)
	Options: { string }?, -- Dispense: the medicines to choose from (Patients.neededMedicines)
	Expert: boolean?, -- Dispense: Expert Dispensing (the clinic's Pharmacy2 unlock): a wider Dose band
	-- Treat: a handover (Items {}): no games; the session only carries the ward pick for a plan a handed-over
	-- medicine completes
	Handover: boolean?,
	-- Dispense: puts the chosen medicine in the player's hands. Returns (given, may tip). Called at most once, and
	-- only for a choice that is one of Options, from a player who is still here
	Give: ((itemId: string) -> (boolean, boolean))?,
	-- Exam and Treat: called at most once, when the session ends (never after Treatment.drop): apply the ratings to
	-- the patient. Returns true when the patient's plan is now complete, and a TriageAsk when the player may pick its
	-- ward (Lv 3+, no Receptionist on duty)
	Settle: ((ratings: { Rating }, tip: number) -> (boolean, TriageAsk?))?,
}

type Session = {
	Id: number,
	Player: Player,
	Spec: Spec,
	Kind: string, -- "Exam" | "Treat" | "Dispense"
	Key: any?, -- the patient (spec.Key)
	Games: { string },
	Options: { string }, -- Dispense: the medicines on offer ({} otherwise)
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
local DISPENSE_AGAIN = "💊 Hold Dispense to try again!"

local sessions: { [Player]: Session } = {}
local pending: { [Player]: Pending } = {}
local lastId = 0
local healHandler: ((Plot, string, string) -> { string }?)? = nil

------------------------------------------------------------------------------------------------------------------
-- Pure helpers (no Roblox services, no upvalues but MiniGame: a scratch Lune harness loads this block on its own;
-- the Data tables and Config come in as arguments)
------------------------------------------------------------------------------------------------------------------

-- PURE-BEGIN
local Pure = {}

Pure.EXAM_TOOLS_MAX = 4 -- tools on an exam card (Logic/Visit.examTools gives 3)
Pure.OPTIONS_MAX = 3 -- medicines on a dispensing card when Config.Dispensary.Options is junk
Pure.EXPERT_BAND = 1.5 -- Expert Dispensing when Config.Dispensary.ExpertBand is junk
Pure.HANDOVER_SECONDS = 4 -- a handover session nobody answers settles by itself this soon (it has no games)

-- n copies of a rating
function Pure.all(rating: Rating, n: number): { Rating }
	local out: { Rating } = {}
	for index = 1, n do
		out[index] = rating
	end
	return out
end

-- A spec's Kind: "Exam" | "Treat" (nil) | "Dispense"; anything else nil (refused).
function Pure.kind(value: any): string?
	if value == nil or value == "Treat" then
		return "Treat"
	end
	if value == "Exam" or value == "Dispense" then
		return value
	end
	return nil
end

-- The server's ratings for a session. `how`: "Report" (the client's TreatResult), "Timeout" or "Left".
-- A report is MiniGame.accept's view of it, and all OK when the player wandered off (`near` false). Whatever
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

-- A Treat's games: one per supply (Data/Items Game). nil when there is none, or when one has no game (a medicine is
-- handed over with no games; an unknown item never plays). A handover (`handover` true) has no items and no games: {}.
function Pure.games(items: any, itemData: any, handover: boolean?): { string }?
	if handover == true then
		return if items == nil or (type(items) == "table" and #items == 0) then {} else nil
	end
	if type(items) ~= "table" or #items == 0 then
		return nil
	end
	local games: { string } = {}
	for index, itemId in items do
		local game = MiniGame.gameFor(itemId, itemData)
		if game == nil then
			return nil
		end
		games[index] = game
	end
	return games
end

-- An Exam card, cleaned: the known tools (Data/Tools) without repeats, at most EXAM_TOOLS_MAX, with the answer among
-- them. nil when the answer isn't on the card.
function Pure.examCard(tools: any, answer: any, toolData: any): { Tools: { string }, Answer: string }?
	if type(tools) ~= "table" or type(answer) ~= "string" or type(toolData) ~= "table" then
		return nil
	end
	local list: { string } = {}
	for _, toolId in tools do
		if #list >= Pure.EXAM_TOOLS_MAX then
			break
		end
		if type(toolId) == "string" and type(rawget(toolData, toolId)) == "table" and not table.find(list, toolId) then
			table.insert(list, toolId)
		end
	end
	if not table.find(list, answer) then
		return nil
	end
	return { Tools = list, Answer = answer }
end

-- An Exam's games: Pick the tool, then play the answer tool's own game. nil when that tool has no known game.
function Pure.examGames(answer: any, toolData: any): { string }?
	local tool = if type(answer) == "string" and type(toolData) == "table" then rawget(toolData, answer) else nil
	local game = if type(tool) == "table" then tool.Game else nil
	if type(game) ~= "string" or MiniGame.ENGINE[game] == nil then
		return nil
	end
	return { "Pick", game }
end

-- A Dispense's games: find the bottle, then measure the dose.
function Pure.dispenseGames(): { string }
	return { "Pick", "Dose" }
end

-- A Dispense's Options, cleaned: known medicines (Data/Items Kind "Medicine") without repeats, in order, at most
-- `max` (Config.Dispensary.Options). {} when nothing is left (refused).
function Pure.options(value: any, itemData: any, max: any): { string }
	local limit = if type(max) == "number" and max == max and max >= 1 then math.floor(max) else Pure.OPTIONS_MAX
	local out: { string } = {}
	if type(value) ~= "table" or type(itemData) ~= "table" then
		return out
	end
	for _, itemId in value do
		if #out >= limit then
			break
		end
		local row = if type(itemId) == "string" then rawget(itemData, itemId) else nil
		if type(row) == "table" and row.Kind == "Medicine" and not table.find(out, itemId) then
			table.insert(out, itemId)
		end
	end
	return out
end

-- A Dispense report's choice: one of the session's Options, else nil (nothing is given).
function Pure.choice(value: any, options: { string }): string?
	if type(value) ~= "string" or type(options) ~= "table" then
		return nil
	end
	return if table.find(options, value) then value else nil
end

-- A Pour tuning row with its Perfect band (BandMin..BandMax) `factor` times as wide round its middle, inside 0..1.
-- A new table; factor junk or <= 1 gives a plain copy.
function Pure.widen(row: any, factor: any): { [string]: any }
	local out: { [string]: any } = {}
	if type(row) == "table" then
		for key, value in row do
			out[key] = value
		end
	end
	local k = if type(factor) == "number" and factor == factor and factor > 1 and factor < 10 then factor else 1
	local low = if type(out.BandMin) == "number" then out.BandMin else 0.7
	local high = if type(out.BandMax) == "number" then out.BandMax else 0.86
	if k > 1 and high > low then
		local middle, half = (low + high) / 2, (high - low) / 2 * k
		out.BandMin = math.max(0, middle - half)
		out.BandMax = math.min(1, middle + half)
	end
	return out
end

-- TreatSession.Tuning for a session: per-game tuning rows that replace Config.MiniGame.Games[game] on the client.
-- Expert Dispensing: { Dose = the Dose row with its band Config.Dispensary.ExpertBand wider }. nil = the plain rows.
function Pure.tuning(kind: string, expert: any, cfg: any): { [string]: any }?
	if kind ~= "Dispense" or expert ~= true then
		return nil
	end
	local dispensary = if type(cfg) == "table" then cfg.Dispensary else nil
	local band = if type(dispensary) == "table" then dispensary.ExpertBand else nil
	local factor = if type(band) == "number" and band == band and band > 1 then band else Pure.EXPERT_BAND
	return { Dose = Pure.widen(MiniGame.tuning("Dose", cfg), factor) }
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

function Treatment.working(key: any, plot: any?): boolean
	if key == nil then
		return false
	end
	for _, session in sessions do
		if session.Open and session.Key == key and (plot == nil or session.Spec.Plot == plot) then
			return true
		end
	end
	return false
end

local function near(player: Player, at: Vector3): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) or typeof(at) ~= "Vector3" then
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

-- Which games a banked AutoPerfect ability (Quick Plaster, Quick Soap, Golden Touch) makes PERFECT, spending it.
local function consumePerfects(plot: Plot, games: { string }): { boolean }
	local ok, flags = pcall(Abilities.consumePerfects, plot, games)
	if not ok then
		report("Abilities.consumePerfects", flags)
	end
	return Pure.autoFlags(if ok then flags else nil, #games)
end

-- The player's own 🎯 Steady Hands (their tree): how much wider the client draws the Perfect windows.
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

-- Ends a session once: the ratings, a Dispense's medicine, the combo and the tip, then the patient. Never yields.
local function settle(session: Session, how: string, reported: any, choiceArg: any): Types.TreatOutcome
	close(session)
	local player = session.Player
	local spec = session.Spec
	local kind = session.Kind
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

	-- Dispense: the choice must be one of the server's own Options (else nothing, all OK), and the medicine goes into
	-- the hands before any tip.
	local choice: string? = nil
	local given, tipping = true, true
	if kind == "Dispense" then
		choice = if how == "Report" then Pure.choice(choiceArg, session.Options) else nil
		if choice == nil then
			ratings = Pure.all("OK", #session.Games)
		end
		given, tipping = false, false
		if how == "Timeout" and here then
			Remotes.toast(player, DISPENSE_AGAIN) -- never a silent empty hand
		end
		local give = spec.Give
		if choice and here and give then
			local ok, gave, mayTip = pcall(give, choice)
			if not ok then
				report("the dispensary's give", gave)
			else
				given = gave == true
				tipping = given and mayTip == true
			end
		end
	end

	local combo = Treatment.combo(player)
	local tip = 0
	if here then
		combo, tip = MiniGame.settle(combo, ratings, Config, spec.TipSoFar, cheerTip(spec.Plot))
		player:SetAttribute(COMBO_ATTRIBUTE, combo)
		if not tipping then
			tip = 0
		end
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

	local complete: any, ask: any = false, nil
	local apply = spec.Settle
	if kind ~= "Dispense" and apply then
		local ok, done, triage = pcall(apply, ratings, tip)
		if ok then
			complete, ask = done, triage
		else
			report("the patient's settle", done)
		end
	end
	local outcome: Types.TreatOutcome = { Ratings = ratings, Tip = tip, Combo = combo, Complete = complete == true }
	if kind == "Exam" and type(spec.Case) == "string" then
		outcome.Case = spec.Case -- "🩺 It's a cough!": whatever the ratings
		if type(spec.Plan) == "table" then
			outcome.Plan = table.clone(spec.Plan) -- this patient's own plan (its clinic's level, an urgent pad)
		end
	elseif kind == "Dispense" and given then
		outcome.Item = choice
	end
	-- Triage: only the player's own report has someone there to pick (a timeout or a player who left: it goes by
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

-- What a spec plays: (kind, games, exam card, options), or nil when it can't be a session.
local function plan(spec: Spec): (string?, { string }?, { Tools: { string }, Answer: string }?, { string })
	local kind = Pure.kind(spec.Kind)
	if kind == "Exam" then
		local card = Pure.examCard(spec.Tools, spec.Answer, ToolsData)
		if not card or type(spec.Settle) ~= "function" then
			return nil, nil, nil, {}
		end
		return kind, Pure.examGames(card.Answer, ToolsData), card, {}
	elseif kind == "Treat" then
		if type(spec.Settle) ~= "function" then
			return nil, nil, nil, {}
		end
		return kind, Pure.games(spec.Items, ItemsData, spec.Handover == true), nil, {}
	elseif kind == "Dispense" then
		local options = Pure.options(spec.Options, ItemsData, Config.Dispensary and Config.Dispensary.Options)
		if #options == 0 or type(spec.Give) ~= "function" then
			return nil, nil, nil, {}
		end
		return kind, Pure.dispenseGames(), nil, options
	end
	return nil, nil, nil, {}
end

function Treatment.open(player: Player, spec: Spec): number?
	if not isPlayer(player) or player.Parent ~= Players or Treatment.busy(player) then
		return nil
	end
	if type(spec) ~= "table" then
		return nil
	end
	if Treatment.working(spec.Key, spec.Plot) then
		return nil -- one session per patient: someone is already working on them
	end
	local kind, planned, card, options = plan(spec)
	if kind == nil or planned == nil then
		return nil
	end
	local games: { string } = planned
	lastId += 1
	local handover = kind == "Treat" and #games == 0
	local auto = if handover then {} else consumePerfects(spec.Plot, games) -- (no game: no ability is spent)
	local session: Session = {
		Id = lastId,
		Player = player,
		Spec = spec,
		Kind = kind,
		Key = spec.Key,
		Games = games,
		Options = options,
		Auto = auto,
		Simple = Treatment.simple(player),
		Started = os.clock(),
		Timer = nil,
		Open = true,
	}
	sessions[player] = session
	-- (a Dispense with several options first asks "Which one?": one more step that waits for a tap)
	local timeout = if handover
		then Pure.HANDOVER_SECONDS
		else MiniGame.timeout(games, Config, if kind == "Dispense" and #options > 1 then 1 else 0)
	session.Timer = task.delay(timeout, function()
		session.Timer = nil
		if session.Open then
			settle(session, "Timeout", nil, nil)
		end
	end)
	local payload: Types.TreatSession = {
		Session = session.Id,
		PatientId = if kind == "Dispense" then "" else spec.PatientId,
		Items = if kind == "Treat" and spec.Items then table.clone(spec.Items) else {},
		Games = table.clone(games) :: any,
		Simple = session.Simple,
		Combo = Treatment.combo(player),
		Position = spec.Position,
		Timeout = timeout,
		Kind = kind :: any,
		Auto = table.clone(auto),
		Ease = easeFor(player),
	}
	if card then
		payload.Tools = table.clone(card.Tools)
		payload.Answer = card.Answer
		payload.Glow = spec.Glow == true
		if type(spec.Symptom) == "string" then
			payload.Symptom = spec.Symptom
		end
	elseif kind == "Dispense" then
		payload.Options = table.clone(options)
		-- Expert Dispensing: the client draws and rates the Dose game with the wider band (Expert; it widens
		-- its own Config row by Config.Dispensary.ExpertBand). Tuning.Dose is that same row as the server sees it.
		local tuning = Pure.tuning(kind, spec.Expert, Config)
		if tuning then
			payload.Expert = true
			payload.Tuning = tuning
		end
	elseif type(spec.Case) == "string" then
		payload.Case = spec.Case -- a Treat: the case is known by now
	end
	if handover then
		payload.Handover = true
	end
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

-- TreatResult(session, ratings, choice?). Every argument is untrusted.
local function onResult(
	player: Player,
	sessionArg: any,
	reported: any,
	choiceArg: any
): (boolean, string, Types.TreatOutcome?)
	local id = Pure.sessionId(sessionArg)
	local session = sessions[player]
	if id == nil or not session or not session.Open or session.Id ~= id then
		return false, Remotes.OOPS -- not this player's open session (late, junk or someone else's): nothing changes
	end
	return true, "", settle(session, "Report", reported, choiceArg)
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

-- A nurse is ready: Patients examines a patient or gives it what the tray holds for it (no game, no tip, no combo). A
-- Healer sends target "Front", a Medic "Urgent" (anything else counts as "Front").
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
	-- The player left mid-game. An Exam or a Treat still lands (all OK): the supplies given count and the case is
	-- found, so the bay patient isn't stuck and waits for the next doctor. A Dispense is dropped: nothing is given.
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session and session.Open then
			if session.Kind == "Dispense" then
				close(session)
			else
				settle(session, "Left", nil, nil)
			end
		end
		sessions[player] = nil
		pending[player] = nil -- a pick they never made: the patient goes by itself
	end)
end

return Treatment
