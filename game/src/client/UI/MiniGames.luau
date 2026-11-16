--!strict
-- Treatment mini-games (depth-update design §1, build plan §B3/§B9). Client only. OWNER: T2; Progression v2: T8.
--   init(ctx)   listens for the bus "TreatStart" (Types.TreatSession, forwarded from the server by Main.client)
--
-- One short game per session.Games entry, in recipe order, on a candy card in the middle of the screen. Big targets
-- (56 px or more), touch and mouse; Space or the gamepad's A button plays every game too.
--   🧪 Pour   hold to fill the bottle, let go in the green ⭐ band       score = the fill when let go (0..1)
--   🩹 Patch  3 sore spots pop up on the creature, tap each one          score = spots patched in Patch.Seconds
--   🛁 Scrub  bubbles pop up around the creature in its bath, pop them   score = bubbles popped in Scrub.Seconds
--   ☕ Cool   3 steam rings rise off the cocoa: tap as each is biggest   score = good blows (a blow is good within
--             Cool.Window seconds of the ring's biggest moment, halfway through its PulseSeconds; it glows lime then)
-- Each game is rated with Logic/MiniGame.rate(game, score, ctx.Config): a huge outlined PERFECT! / GOOD! / OK! pops
-- and the 🔥 combo counter climbs on a Perfect, holds on a Good and goes back to "Go!" on an OK (Logic/MiniGame.settle
-- predicts it; at 0 it rests at "Go!" in a soft warm colour, never a grey 0, so it never looks like losing; the
-- server's own combo wins when it answers).
-- Never a fail: OK still cures. Then TreatResult (Hud.ask(TreatResult, session.Session, ratings)): its third value is
-- the TreatOutcome; the card shows the server's ratings and tip for a moment and closes.
-- Simple mode (session.Simple): one big tap per game, rated Good, no combo counter. A game id this client doesn't know
-- plays as one tap too (rated Good). Reduced motion (Kit.reducedMotion(), checked live): no wobble, bursts, drift or
-- overshoot; the fill and the steam ring still move (they are the game), same rules.
-- Fairness: the report never goes sooner than MiniGame.minSeconds after TreatStart (so the server never rates a real
-- game all OK for being early), and the card closes by itself just before session.Timeout (the server has settled
-- the session as all OK by then). A new TreatStart replaces a running one. Nothing here decides anything: the
-- server checks the session, the time, the distance and the tip.
--
-- Progression v2 (build plan §B3 TreatSession/TreatOutcome, §C T8):
--   Auto   a game an ability made PERFECT (Golden Touch, Quick Bandage/Soap) sparkles for a moment ("✨ Magic
--          help!"), pops "✨ PERFECT!" and is skipped; the minimum report time counts only the games really played
--          (Pure.played, as the server's MiniGame.accept does).
--   Ease   🎯 Steady Hands (1..1.3) widens the Perfect windows: the Pour's ⭐ band and Good slack, the Cool's blow
--          window, a little more time to patch and scrub (Pure.eased). The client draws and rates with it; the
--          server never checks it (it takes the client's ratings), so the two always agree.
--   Soak   the Hydro hot tub's one Scrub game is a "🫧 Bubble bath!" card, a tip only ("🛁 Ahh, so cosy!").
--   Triage when the server's TreatOutcome has Triage (Lv 3+, no Receptionist), the card stays for "🔀 Which
--          floor?": a huge button per department (Data/Departments icon, the badge chip's colour) over the soft time
--          bar (no digits). One tap asks Triage(session, dept): "✅ Right floor!" or "Oops, not this floor!" (it
--          goes the right way anyway). No tap: the bar empties and the patient goes by itself. Never a fail.
-- Bus events: listens "TreatStart" (session) · fires "MiniGameRated" (game, rating) as each game ends (the client's
-- own rating, for feel) · "TreatDone" (outcome, session) after the server's reply (session = the TreatStart payload,
-- with its Position) · "Sound" (name) for the hits: Pour, Patch, Scrub, Blow, Tick, plus Whoosh, Splash, Sparkle,
-- Pop, Triage. The rating cues (RateOK/RateGood/RatePerfect on MiniGameRated) and Tip/Combo (on TreatDone) are Feel/Sounds'
-- own, so this file never plays them (they would double).
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
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local MiniGames = {}

------------------------------------------------------------------------------------------------------------------
-- PURE:BEGIN  (no Roblox services, instances or requires in this block)
------------------------------------------------------------------------------------------------------------------

local Pure = {}

Pure.KNOWN = { Pour = true, Patch = true, Scrub = true, Cool = true } -- the games this client can draw
Pure.MAX_GAMES = 6 -- a recipe has at most 3; more than this is junk
-- Progression v2: 🎯 Steady Hands widens the Perfect windows by up to 30% (TreatSession.Ease, 1..1.3; client only)
Pure.EASE_MAX = 1.3
Pure.TRIAGE_MAX = 3 -- floor buttons on the triage card (two today: 🛏️ Wards and 🛁 Hydro)
Pure.TRIAGE_SECONDS_MAX = 10

export type Session = {
	Session: number,
	PatientId: string,
	Items: { string }, -- one per game ("" when unknown)
	Games: { string },
	Simple: boolean,
	Combo: number, -- a whole number >= 0
	Timeout: number?, -- seconds, nil when the payload had none
	-- Progression v2 (build plan §B3 TreatSession): defaults when the server sends none
	Kind: string, -- "Treat" | "Soak" (the Hydro hot tub's 🫧 bubble bath: one Scrub game for a tip)
	Auto: { boolean }, -- per game: an ability made it PERFECT already (shown with ✨ and skipped)
	Ease: number, -- 1..EASE_MAX: how much wider the Perfect windows are
}
export type TriageOption = { Dept: string, Icon: string, Name: string }
export type TriageCard = { Options: { TriageOption }, Seconds: number }
export type Point = { X: number, Y: number }

local function finite(value: any): number?
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return nil
end
Pure.finite = finite

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
	if count < 1 or count > Pure.MAX_GAMES then
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
		Kind = if raw.Kind == "Soak" then "Soak" else "Treat",
		Auto = auto,
		Ease = math.clamp(finite(raw.Ease) or 1, 1, Pure.EASE_MAX),
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

local function copyOf(value: any): { [any]: any }
	local out = {}
	if type(value) == "table" then
		for key, item in value do
			out[key] = item
		end
	end
	return out
end

-- Config.MiniGame with the Perfect windows widened by `ease` (🎯 Steady Hands, 1..EASE_MAX): the Pour's ⭐ band
-- (round its middle) and its Good slack, the Cool's blow window, and a little more time to patch and to scrub. New
-- tables (Config is frozen). The client draws and rates with it; the server takes the client's ratings, so the two
-- always agree. ease 1 (or junk) is the plain settings.
function Pure.eased(mini: any, ease: number?): any
	local out = copyOf(mini)
	local k = math.clamp(finite(ease) or 1, 1, Pure.EASE_MAX)
	if k <= 1 then
		return out
	end
	local pour = copyOf(out.Pour)
	local low, high = finite(pour.BandMin) or 0.7, finite(pour.BandMax) or 0.86
	local middle, half = (low + high) / 2, (high - low) / 2 * k
	pour.BandMin = math.max(0, middle - half)
	pour.BandMax = math.min(1, middle + half)
	pour.GoodSlack = (finite(pour.GoodSlack) or 0.12) * k
	out.Pour = pour
	local cool = copyOf(out.Cool)
	cool.Window = (finite(cool.Window) or 0.3) * k
	out.Cool = cool
	local patch = copyOf(out.Patch)
	patch.Seconds = (finite(patch.Seconds) or 4.5) * k
	out.Patch = patch
	local scrub = copyOf(out.Scrub)
	scrub.Seconds = (finite(scrub.Seconds) or 4) * k
	out.Scrub = scrub
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

------------------------------------------------------------------------------------------------------------------
-- PURE:END
------------------------------------------------------------------------------------------------------------------

local DISPLAY_ORDER = Theme.DisplayOrder.Popup + 5 -- over panels and pop-ups, under cure pops and toasts
local ACTION = "MiniGamesAction" -- Space / gamepad A while the card is open
local MIN_TAP = Theme.Size.ButtonHeight

-- The card (px): header band, status strip (steps + time bar), the stage, the hint line.
local HEADER = 58
local STATUS = 26
local HINT = 40
local GAP = 6
local DIM = 0.55 -- the shade behind the card (transparency): the world stays visible

-- Timing (seconds). The games' own numbers are in Config.MiniGame.
local INTRO = 0.4 -- each game's picture pops in before it takes taps
local RATING_HOLD = 0.9 -- the rating pop stays this long before the next game
local RESULT_HOLD = 1.2 -- the server's answer stays this long before the card closes
local REPORT_MARGIN = 0.15
local TIMEOUT_MARGIN = 0.6 -- the card closes this long before the server settles the session by itself
local POUR_IDLE = 6 -- a Pour nobody starts ends by itself (rated OK)
local POUR_SOUND_EVERY = 0.3
local SPOT_EVERY = 0.4 -- Patch: the sore spots pop up one after another
local BUBBLE_EVERY = 0.36
local BUBBLE_LIFE = 1.8
local BUBBLE_MAX = 4
local COOL_GAP = 0.35 -- between steam rings
local COOL_GRACE = 0.08 -- a tap this soon in a ring is a leftover from the last one: ignored
local RING_MIN = 0.3

local WHITE = Palette.White
local OUTLINE = Theme.Colors.Outline
local GLASS = Color3.fromRGB(226, 244, 255)
local POTION = Theme.Colors.Pink
local SORE = Color3.fromRGB(255, 120, 140)
local SORE_CORE = Color3.fromRGB(230, 60, 90)
local MUD = Color3.fromRGB(150, 98, 56)
local BUBBLE = Color3.fromRGB(196, 238, 255)
local STEAM = Color3.fromRGB(232, 236, 252)
local COCOA = Color3.fromRGB(132, 74, 44)

type GameLook = { Icon: string, Title: string, Hint: string, Color: Color3, Sound: string }
local GAME_LOOK: { [string]: GameLook } = {
	Pour = {
		Icon = "🧪",
		Title = "Pour!",
		Hint = "Hold… let go on ⭐",
		Color = Theme.Colors.Purple,
		Sound = "Pour",
	},
	Patch = {
		Icon = "🩹",
		Title = "Patch!",
		Hint = "Tap the sore spots!",
		Color = Theme.Colors.Pink,
		Sound = "Patch",
	},
	Scrub = { Icon = "🛁", Title = "Scrub!", Hint = "Pop the bubbles!", Color = Theme.Colors.Cyan, Sound = "Scrub" },
	Cool = {
		Icon = "☕",
		Title = "Cool!",
		Hint = "Blow when it's biggest!",
		Color = Theme.Colors.Primary,
		Sound = "Blow",
	},
}
local TAP_LOOK: GameLook =
	{ Icon = "✨", Title = "Tap!", Hint = "Tap to help!", Color = Theme.Colors.Good, Sound = "Pop" }
-- Progression v2: the Hydro hot tub's bubble bath (TreatSession Kind "Soak": one Scrub game, a tip only)
local SOAK_LOOK: GameLook =
	{ Icon = "🫧", Title = "Bubble bath!", Hint = "Pop the bubbles!", Color = Theme.Colors.Cyan, Sound = "Scrub" }
-- The triage card's floor buttons (Kit kinds), in the colour of each department's badge chip (CreatureBuilder.setDept)
local DEPT_KINDS: { [string]: string } = {
	Reception = "Primary",
	AE = "Danger",
	Wards = "Pink",
	Hydro = "Cyan",
	Pharmacy = "Good",
	Roof = "Purple",
}
local AUTO_HOLD = 0.5 -- an ability's PERFECT game shows its sparkle this long before the rating pop
local TRIAGE_MARGIN = 0.3 -- the floor buttons stop taking taps this long before the server stops waiting
local TRIAGE_HOLD = 1.1 -- the triage answer stays this long before the card closes
local TRIAGE_LEAD = 0.45 -- the results flash this long before the floor buttons come

type RatingLook = { Text: string, Icon: string, Color: Color3 }
local RATING_LOOK: { [string]: RatingLook } = {
	Perfect = { Text = "PERFECT!", Icon = "⭐", Color = Theme.Colors.Cash },
	Good = { Text = "GOOD!", Icon = "👍", Color = Theme.Colors.Good },
	OK = { Text = "OK!", Icon = "🙂", Color = Theme.Colors.Secondary },
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

local function corner(gui: GuiObject, radius: UDim?)
	new("UICorner", { CornerRadius = radius or UDim.new(0.5, 0), Parent = gui })
end

local function minSize(gui: GuiObject, px: number)
	new("UISizeConstraint", { MinSize = Vector2.new(px, px), Parent = gui })
end

local function maxText(label: TextLabel | TextButton, px: number)
	new("UITextSizeConstraint", { MaxTextSize = px, MinTextSize = 10, Parent = label })
end

-- A filled round shape with the candy outline (a circle unless `radius` says otherwise).
local function blob(parent: Instance, name: string, color: Color3, props: { [string]: any }, radius: UDim?): Frame
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
	Kit.stroke(frame, OUTLINE, Theme.Size.Stroke)
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

-- The hint's first icon: what to press with on this device.
local function pointer(): string
	local preferred = UserInputService.PreferredInput
	if preferred == Enum.PreferredInput.Gamepad or preferred == Enum.PreferredInput.MicroGamepad then
		return "🅰️"
	elseif preferred == Enum.PreferredInput.KeyboardAndMouse then
		return "🖱️"
	end
	return "👆"
end

-- The running session's Config.MiniGame, eased by 🎯 Steady Hands (Pure.eased); nil between sessions.
local activeMini: any = nil

local function miniOf(ctx: Types.Ctx): any
	return activeMini or ctx.Config.MiniGame
end

local function settingsOf(ctx: Types.Ctx, name: string): any
	local mini = miniOf(ctx)
	local value = if type(mini) == "table" then mini[name] else nil
	return if type(value) == "table" then value else {}
end

local function num(value: any, fallback: number): number
	return finite(value) or fallback
end

------------------------------------------------------------------------------------------------------------------
-- The card
------------------------------------------------------------------------------------------------------------------

type View = {
	Gui: ScreenGui,
	Dim: Frame,
	Root: Frame,
	Card: Frame,
	Header: Frame,
	HeaderFoot: Frame,
	Icon: TextLabel,
	Title: TextLabel,
	Combo: Frame,
	ComboText: TextLabel,
	ComboMult: TextLabel,
	Status: Frame,
	Steps: Frame,
	TimeTrack: Frame,
	TimeFill: Frame,
	Stage: TextButton,
	Hint: TextLabel,
	Pop: Frame,
	PopRays: Frame,
	PopText: TextLabel,
	PopStroke: UIStroke,
	ComboValue: number,
}

local function build(): View
	local gui = Kit.screen("MiniGames", DISPLAY_ORDER)
	gui.Enabled = false

	-- The shade bleeds past the safe area; it never takes input, so the thumbstick and camera still work.
	local dim = new("Frame", {
		Name = "Dim",
		BackgroundColor3 = Theme.Colors.Shade,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(-400, -400),
		Size = UDim2.new(1, 800, 1, 800),
		Parent = gui,
	})

	local root = new("Frame", {
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.96, 0.94),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	new("UIAspectRatioConstraint", { AspectRatio = 1.05, Parent = root })
	new("UISizeConstraint", { MaxSize = Vector2.new(540, 514), Parent = root })

	local shadow = new("Frame", {
		Name = "Shadow",
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = OUTLINE,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Parent = root,
	})
	corner(shadow, UDim.new(0, Theme.Size.CornerLarge))

	local card = new("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Paper,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = root,
	})
	corner(card, UDim.new(0, Theme.Size.CornerLarge))
	Kit.stroke(card, OUTLINE, Theme.Size.StrokeLarge)
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Theme.Colors.Paper, Theme.Colors.PaperEdge),
		Parent = card,
	})

	-- Header band: the game's icon and name, and the 🔥 combo chip.
	local header = new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, HEADER),
		BackgroundColor3 = Theme.Colors.Purple,
		BorderSizePixel = 0,
		Parent = card,
	})
	corner(header, UDim.new(0, Theme.Size.CornerLarge))
	Palette.candyGradient(header)
	local foot = new("Frame", {
		Name = "Foot",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, Theme.Size.CornerLarge),
		BackgroundColor3 = Theme.Colors.Purple,
		BorderSizePixel = 0,
		Parent = header,
	})
	new("Frame", {
		Name = "Line",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, Theme.Size.StrokeLarge),
		BackgroundColor3 = OUTLINE,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = header,
	})
	local icon = emoji(header, "🧪", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, -2),
		Size = UDim2.fromOffset(42, 42),
		ZIndex = 3,
	})
	local title = Kit.label({
		Name = "Title",
		Text = "",
		Outlined = true,
		TextScaled = true,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 62, 0.5, -2),
		Size = UDim2.new(1, -62 - 116, 0, 38),
		ZIndex = 3,
		Parent = header,
	})
	maxText(title, Theme.TextSize.Title)

	local combo = new("Frame", {
		Name = "Combo",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, -2),
		Size = UDim2.fromOffset(92, 42),
		BackgroundColor3 = Theme.Colors.Quiet,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = header,
	})
	corner(combo)
	Kit.stroke(combo, OUTLINE, Theme.Size.Stroke)
	Palette.candyGradient(combo)
	Kit.gloss(combo, 10)
	emoji(combo, "🔥", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(32, 32),
		ZIndex = 4,
	})
	local comboText = Kit.label({
		Name = "Count",
		Text = "Go!",
		Outlined = true,
		TextScaled = true,
		TextWrapped = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(1, -48, 0, 32),
		ZIndex = 4,
		Parent = combo,
	})
	maxText(comboText, Theme.TextSize.Title)
	local comboMult = Kit.label({
		Name = "Multiplier",
		Text = "",
		Outlined = true,
		TextScaled = true,
		TextWrapped = false,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.Cash,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, 4),
		Size = UDim2.fromOffset(54, 22),
		Visible = false,
		ZIndex = 5,
		Parent = combo,
	})
	corner(comboMult)
	Kit.stroke(comboMult, OUTLINE, 2.5)
	maxText(comboMult, 18)

	-- Status strip: one chip per game (only with 2+), then the soft time bar (timed games only).
	local status = new("Frame", {
		Name = "Status",
		Position = UDim2.fromOffset(14, HEADER + GAP + 2),
		Size = UDim2.new(1, -28, 0, STATUS),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = card,
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
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = steps,
	})
	local track = new("Frame", {
		Name = "Time",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundColor3 = Theme.Colors.Card,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
		Parent = status,
	})
	corner(track)
	Kit.stroke(track, OUTLINE, 2.5)
	local fill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Good,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = track,
	})
	corner(fill)

	-- The stage: where each game draws. A button, so a tap here never reaches the world behind.
	local top = HEADER + GAP * 2 + STATUS + 2
	local stage = new("TextButton", {
		Name = "Stage",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(10, top),
		Size = UDim2.new(1, -20, 1, -(top + HINT + GAP)),
		ZIndex = 3,
		Parent = card,
	})

	local hint = Kit.label({
		Name = "Hint",
		Text = "",
		TextScaled = true,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -28, 0, HINT - 10),
		ZIndex = 3,
		Parent = card,
	})
	maxText(hint, Theme.TextSize.Body)

	-- The rating pop: huge outlined words over the middle of the card.
	local pop = new("Frame", {
		Name = "Pop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 14),
		Size = UDim2.fromScale(1.04, 0.34),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 10,
		Parent = root,
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
	maxText(popText, 112)
	local popStroke = Kit.outline(popText, 6)

	return {
		Gui = gui,
		Dim = dim,
		Root = root,
		Card = card,
		Header = header,
		HeaderFoot = foot,
		Icon = icon,
		Title = title,
		Combo = combo,
		ComboText = comboText,
		ComboMult = comboMult,
		Status = status,
		Steps = steps,
		TimeTrack = track,
		TimeFill = fill,
		Stage = stage,
		Hint = hint,
		Pop = pop,
		PopRays = popRays,
		PopText = popText,
		PopStroke = popStroke,
		ComboValue = 0,
	}
end

local function setHeader(v: View, icon: string, title: string, color: Color3)
	v.Icon.Text = icon
	v.Title.Text = title
	v.Header.BackgroundColor3 = Kit.lighten(color, 0.08)
	v.HeaderFoot.BackgroundColor3 = Kit.shade(color, 0.04)
	punch(v.Icon, 1.4, 0.35)
end

local function setTime(v: View, share: number?)
	if share == nil then
		v.TimeTrack.Visible = false
		return
	end
	v.TimeTrack.Visible = true
	v.TimeFill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
end

local function setSteps(ctx: Types.Ctx, v: View, session: Session)
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
	for index, gameId in session.Games do
		local item = rawget(ctx.Data.Items :: any, session.Items[index])
		local look = GAME_LOOK[gameId] or TAP_LOOK
		local chip = blob(v.Steps, "Step" .. index, Theme.Colors.Card, {
			LayoutOrder = index,
			Size = UDim2.fromOffset(STATUS, STATUS),
			ZIndex = 3,
		})
		emoji(chip, if type(item) == "table" then item.Icon else look.Icon, {
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.78, 0.78),
			ZIndex = 4,
		})
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
	-- No combo reads as a cheer, never a loss (only an OK resets it; a GOOD! holds it: build plan §E7): the chip stays
	-- warm (a soft orange, not grey) and says "Go!" instead of a bare 0.
	v.ComboText.Text = if value <= 0 then "Go!" else tostring(value)
	local multiplier = MiniGame.multiplier(value, ctx.Config)
	local tag = Pure.multText(multiplier)
	v.ComboMult.Text = tag
	v.ComboMult.Visible = tag ~= ""
	v.Combo.BackgroundColor3 = Kit.lighten(Theme.Colors.Primary, if value > 0 then 0.08 else 0.45)
	if animate and value > before then
		punch(v.Combo, 1.3)
		if multiplier > MiniGame.multiplier(before, ctx.Config) then
			punch(v.ComboMult, 1.8, 0.45)
			burst(v.Combo, UDim2.fromScale(0.5, 0.5), "🔥", 5, 0.7)
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
}

-- Everything a game needs. Each game builds into Layer, waits on intro(), loops while alive() and returns a score.
type Env = {
	Ctx: Types.Ctx,
	Session: Session,
	View: View,
	Layer: Frame, -- this game's own layer in the stage (destroyed when the game ends)
	Catcher: TextButton, -- the whole stage, under the game's drawing: for "tap anywhere" games
	Rng: Random,
	alive: () -> boolean,
	track: (connection: RBXScriptConnection) -> (),
	intro: () -> boolean, -- pops the picture in and waits INTRO seconds; false when the run ended meanwhile
	pause: (seconds: number) -> boolean, -- false when the run ended meanwhile
	onPress: (gui: GuiObject, fn: (input: InputObject) -> ()) -> (), -- mouse or touch down on gui
	onAction: (fn: ((began: boolean) -> ())?) -> (), -- Space / gamepad A, down (true) and up (false)
	r01: () -> number,
}

local view: View? = nil
local current: Run? = nil
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

local function openCard(v: View)
	clearPop(v)
	v.Gui.Enabled = true
	v.Dim.BackgroundTransparency = 1
	ease(v.Dim, Theme.Tween.Fade, { BackgroundTransparency = DIM })
	Kit.popIn(v.Root)
	sound("Whoosh")
	ContextActionService:BindActionAtPriority(
		ACTION,
		handleAction,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.Space
	)
end

local function closeCard(v: View)
	ContextActionService:UnbindAction(ACTION)
	actionHandler = nil
	clearPop(v)
	setTime(v, nil)
	ease(v.Dim, Theme.Tween.Fade, { BackgroundTransparency = 1 })
	Kit.popOut(v.Root, function()
		if current == nil then
			v.Gui.Enabled = false
		end
	end)
end

-- Ends a run: its connections and layers go, and the card closes unless a newer run already owns it.
local function stop(run: Run)
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

-- 🧪 Pour: hold to fill, let go in the band. Score = the fill when let go.
local function playPour(env: Env): number
	local cfg = settingsOf(env.Ctx, "Pour")
	local fillSeconds = math.max(num(cfg.FillSeconds, 2.4), 0.5)
	local lo, hi, goodLo, goodHi = Pure.bands(cfg)
	local layer = env.Layer
	local NECK = 0.16 -- the neck's share of the bottle's height
	local BOTTOM, HEIGHT = 0.97, 0.8 -- the bottle in the stage (stage-height scale)

	local bottle = new("Frame", {
		Name = "Bottle",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, BOTTOM),
		Size = UDim2.fromScale(0.46, HEIGHT),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = layer,
	})
	blob(bottle, "Neck", GLASS, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(0.36, NECK + 0.05),
		ZIndex = 2,
	}, UDim.new(0, 8))
	local body = blob(bottle, "Body", GLASS, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 1 - NECK),
		ClipsDescendants = true,
		ZIndex = 3,
	}, UDim.new(0.3, 0))
	local liquid = new("Frame", {
		Name = "Liquid",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = POTION,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = body,
	})
	corner(liquid, UDim.new(0, 12))
	Palette.candyGradient(liquid)
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
	local perfect = band("Perfect", lo, hi, Theme.Colors.Good, 0.35, 6)
	local glow = Kit.stroke(perfect, WHITE, 3)
	glow.Enabled = false
	local starY = NECK + (1 - NECK) * (1 - (lo + hi) / 2)
	local stars: { TextLabel } = {}
	for _, side in { -1, 1 } do
		table.insert(
			stars,
			emoji(bottle, "⭐", {
				Position = UDim2.fromScale(0.5 + side * 0.7, starY),
				Size = UDim2.fromScale(0.34, 0.34),
				SizeConstraint = Enum.SizeConstraint.RelativeXX,
				ZIndex = 6,
			})
		)
	end
	-- The vial that pours, the stream, and the "hold here" hand.
	local vialProps = squareAt(0.19, UDim2.fromScale(0.5, 0.1))
	vialProps.ZIndex = 7
	local vial = emoji(layer, "🧪", vialProps)
	local stream = new("Frame", {
		Name = "Stream",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.14),
		Size = UDim2.fromScale(0.05, 0),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundColor3 = POTION,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Parent = layer,
	})
	corner(stream)
	local handProps = squareAt(0.2, UDim2.fromScale(0.5, 0.66))
	handProps.ZIndex = 8
	local hand = emoji(layer, pointer(), handProps)

	local pressedAt: number? = nil
	local result: number? = nil
	local ready = false
	local function press()
		if not ready or pressedAt ~= nil or result ~= nil then
			return
		end
		pressedAt = os.clock()
		hand.Visible = false
		stream.Visible = true
		ease(vial, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = -110 })
		sound("Pour")
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
				sound("Pour")
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
				-- Too full: a little splash out of the neck. Still OK.
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
	ease(vial, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = 0 })
	punch(bottle, 1.12, 0.3)
	if score >= lo and score <= hi then
		burst(layer, UDim2.fromScale(0.5, 0.55), "✨", 6, 0.14)
	end
	return score
end

-- 🩹 Patch: sore spots pop up one by one; tap each to stick a plaster on. Score = spots patched in time.
local function playPatch(env: Env): number
	local cfg = settingsOf(env.Ctx, "Patch")
	local spots = math.clamp(math.floor(num(cfg.Spots, 3)), 1, 6)
	local seconds = math.max(num(cfg.Seconds, 4.5), 1)
	local holder = creature(env, 0.96, 0.5)
	local points = Pure.scatter(spots, { 0.27, 0.4, 0.73, 0.82 }, 0.3, env.r01)
	local SPOT = 0.26 -- of the creature

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
		props.Rotation = env.Rng:NextInteger(-28, 28)
		props.ZIndex = 12
		local plaster = emoji(holder, "🩹", props)
		punch(plaster, 1.8, 0.22)
		punch(holder, 0.94, 0.3)
		burst(holder, at, "✨", 4, 0.12)
		sound("Patch")
	end

	local function spawnSpot(point: Point)
		local button = new("TextButton", squareAt(SPOT, UDim2.fromScale(point.X, point.Y)))
		button.Name = "Spot"
		button.Text = ""
		button.AutoButtonColor = false
		button.Selectable = false
		button.BackgroundColor3 = SORE
		button.BorderSizePixel = 0
		button.ZIndex = 10
		corner(button)
		Kit.stroke(button, OUTLINE, Theme.Size.Stroke)
		minSize(button, MIN_TAP)
		local core = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.46, 0.46),
			BackgroundColor3 = SORE_CORE,
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
		local ringStroke = Kit.stroke(ring, SORE, 4)
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
		setTime(env.View, 1 - t / seconds)
		if patched >= spots then
			burst(holder, UDim2.fromScale(0.5, 0.45), "💖", 6, 0.16)
			sound("Sparkle")
			break
		end
		if t >= seconds then
			break
		end
		-- A soft ring pulses out of each sore spot (still when calm).
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
		setTime(env.View, 0)
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
	local cfg = settingsOf(env.Ctx, "Scrub")
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
		sound("Scrub")
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
		Kit.stroke(button, OUTLINE, Theme.Size.Stroke)
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
		setTime(env.View, 1 - t / seconds)
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
		setTime(env.View, 0)
	end
	for index = #live, 1, -1 do
		local bubble = live[index]
		remove(bubble)
		vanish(bubble, false)
	end
	env.pause(0.3)
	return popped
end

-- ☕ Cool: steam rings rise off the cocoa one at a time; tap as each one is biggest. Score = good blows.
local function playCool(env: Env): number
	local cfg = settingsOf(env.Ctx, "Cool")
	local blows = math.clamp(math.floor(num(cfg.Blows, 3)), 1, 6)
	local pulse = math.max(num(cfg.PulseSeconds, 1.2), 0.4)
	local window = math.max(num(cfg.Window, 0.3), 0.05)
	local layer = env.Layer
	local RING_Y, RING = 0.38, 0.54

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

	local target = new("Frame", squareAt(RING, UDim2.fromScale(0.5, RING_Y)))
	target.Name = "Target"
	target.BackgroundTransparency = 1
	target.ZIndex = 4
	corner(target)
	local targetStroke = Kit.stroke(target, Theme.Colors.InkSoft, 4)
	targetStroke.Transparency = 0.55
	target.Parent = layer
	local steam = blob(layer, "Steam", STEAM, squareAt(RING * RING_MIN, UDim2.fromScale(0.5, RING_Y)))
	steam.BackgroundTransparency = 0.2
	steam.ZIndex = 5
	steam.Visible = false
	local steamStroke = steam:FindFirstChildOfClass("UIStroke") :: UIStroke

	-- One pip per blow, top left: ❄️ for a good one, 💨 for the rest.
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
	local ringStarted = 0
	local function blow()
		if open and os.clock() - ringStarted >= COOL_GRACE then
			request = true
		end
	end
	env.onPress(env.Catcher, function()
		blow()
	end)
	env.onAction(function(began)
		if began then
			blow()
		end
	end)

	if not env.intro() then
		return 0
	end
	local good = 0
	for index = 1, blows do
		ringStarted = os.clock()
		request = false
		open = true
		steam.Visible = true
		steam.BackgroundTransparency = 0.2
		steamStroke.Transparency = 0
		local ticked = false
		local result: boolean? = nil -- true = a good blow, false = a blow off the beat, nil = no blow
		local size = RING_MIN
		while env.alive() do
			local t = os.clock() - ringStarted
			if request then
				result = Pure.goodBlow(t, pulse, window)
				break
			end
			if t >= pulse then
				break
			end
			size = Pure.ring(t, pulse, RING_MIN)
			local hot = Pure.goodBlow(t, pulse, window)
			steam.Size = UDim2.fromScale(RING * size, RING * size)
			steam.BackgroundColor3 = if hot then Kit.lighten(Theme.Colors.Good, 0.35) else STEAM
			steamStroke.Thickness = if hot then 4 else Theme.Size.Stroke
			targetStroke.Color = if hot then Theme.Colors.Good else Theme.Colors.InkSoft
			targetStroke.Transparency = if hot then 0 else 0.55
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
		targetStroke.Color = Theme.Colors.InkSoft
		targetStroke.Transparency = 0.55
		local pip = pipLabels[index]
		local ringAt = UDim2.fromScale(0.5, RING_Y)
		if result ~= nil then
			sound("Blow")
			if not calm() then
				local puffProps = squareAt(0.18, UDim2.fromScale(0.5, 0.92))
				puffProps.ZIndex = 9
				local puff = emoji(layer, "💨", puffProps)
				local fly = play(puff, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = ringAt,
					TextTransparency = 1,
				})
				fly.Completed:Once(function()
					puff:Destroy()
				end)
			end
		end
		if result == true then
			good += 1
			pip.Text = "❄️"
			burst(layer, ringAt, "❄️", 6, 0.1)
			punch(mug, 1.12, 0.3)
		else
			pip.Text = "💨"
			if pip.Parent and pip.Parent:IsA("GuiObject") then
				pip.Parent.BackgroundColor3 = Theme.Colors.Disabled
			end
		end
		if pip.Parent and pip.Parent:IsA("GuiObject") then
			punch(pip.Parent, 1.35, 0.3)
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
		if not env.pause(COOL_GAP) then
			return good
		end
	end
	steam.Visible = false
	return good
end

-- One big tap (Simple mode, or a game this client can't draw). Always scores; Simple rates it Good.
local function playTap(env: Env, look: GameLook): number
	local layer = env.Layer
	local iconProps = squareAt(0.46, UDim2.fromScale(0.5, 0.36))
	iconProps.ZIndex = 3
	local icon = emoji(layer, look.Icon, iconProps)
	local button = Kit.button({
		Name = "Tap",
		Kind = "Good",
		Text = pointer() .. " Tap!",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(0.62, 0, 0, 72),
		ZIndex = 4,
		Parent = layer,
	})
	maxText(button, Theme.TextSize.Title)
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

------------------------------------------------------------------------------------------------------------------
-- The session
------------------------------------------------------------------------------------------------------------------

-- Plays one game and returns its rating.
local function playOne(ctx: Types.Ctx, v: View, run: Run, index: number, gameId: string): string
	local session = run.Session
	local known = Pure.KNOWN[gameId] == true
	local simple = session.Simple or not known
	local look = if session.Kind == "Soak" and gameId == "Scrub" then SOAK_LOOK else GAME_LOOK[gameId] or TAP_LOOK
	setHeader(v, look.Icon, if simple and look ~= SOAK_LOOK then TAP_LOOK.Title else look.Title, look.Color)
	v.Hint.Text = pointer() .. " " .. (if simple then TAP_LOOK.Hint else look.Hint)
	setTime(v, nil)
	markStep(v, index, nil)

	local layer = new("Frame", {
		Name = "Game" .. index,
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
		Session = session,
		View = v,
		Layer = layer,
		Catcher = catcher,
		Rng = run.Rng,
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
		onPress = function(gui: GuiObject, fn: (input: InputObject) -> ())
			track(gui.InputBegan:Connect(function(input: InputObject)
				local kind = input.UserInputType
				if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
					fn(input)
				end
			end))
		end,
		onAction = function(fn: ((began: boolean) -> ())?)
			if alive() then
				ownHandler = fn
				actionHandler = fn
			end
		end,
		r01 = function(): number
			return run.Rng:NextNumber()
		end,
	}

	local ok, score: any = pcall(function(): number
		if simple then
			return playTap(env, look)
		elseif gameId == "Pour" then
			return playPour(env)
		elseif gameId == "Patch" then
			return playPatch(env)
		elseif gameId == "Scrub" then
			return playScrub(env)
		end
		return playCool(env)
	end)
	local slot = table.find(run.Cleanups, cleanup)
	if slot then
		table.remove(run.Cleanups, slot)
	end
	cleanup()
	if run.Alive then
		setTime(v, nil)
	end
	if not ok then
		warn("[MiniGames] " .. gameId .. " broke, rated Good: " .. tostring(score))
		return "Good"
	end
	if simple then
		return "Good"
	end
	-- Rated against the same (eased) windows the game was drawn with.
	return MiniGame.rate(gameId, if type(score) == "number" then score else 0, { MiniGame = miniOf(ctx) })
end

-- A game an ability already made PERFECT (TreatSession.Auto: Golden Touch, Quick Bandage, Quick Soap): its icon
-- sparkles on the stage for a moment, then the run goes on (the server rates it Perfect whatever is reported).
local function playAuto(v: View, run: Run, index: number, gameId: string): string
	local look = GAME_LOOK[gameId] or TAP_LOOK
	setHeader(v, "✨", "Magic help!", Theme.Colors.Cash)
	v.Hint.Text = look.Icon .. " ✨ Done for you!"
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
	for index, gameId in run.Session.Games do
		local rating = RATING_LOOK[ratings[index]] or RATING_LOOK.OK
		local magic = run.Session.Auto[index] == true
		local item = rawget(ctx.Data.Items :: any, run.Session.Items[index])
		local chip = blob(row, "Chip" .. index, Kit.lighten(rating.Color, 0.1), {
			LayoutOrder = index,
			Size = UDim2.fromScale(1, 1),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			ZIndex = 3,
		}, UDim.new(0, Theme.Size.Corner))
		Kit.gloss(chip, 8)
		emoji(chip, if type(item) == "table" then item.Icon else (GAME_LOOK[gameId] or TAP_LOOK).Icon, {
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
		Kit.outline(tipLabel, Theme.Size.Stroke)
		maxText(tipLabel, 44)
		punch(tipLabel, 1.5, 0.35)
	end
	if run.Session.Kind == "Soak" then
		setHeader(v, "🫧", "So bubbly!", Theme.Colors.Cyan)
		v.Hint.Text = if type(outcome) == "table" then "🛁 Ahh, so cosy!" else ""
	elseif type(outcome) ~= "table" then
		setHeader(v, "✨", "Nice!", Theme.Colors.Good)
		v.Hint.Text = ""
	elseif outcome.Complete == true then
		setHeader(v, "💖", "All better!", Theme.Colors.Good)
		v.Hint.Text = "🛏️ Time to rest!"
	else
		setHeader(v, "👍", "Nice!", Theme.Colors.Secondary)
		v.Hint.Text = "🔜 Make the next one!"
	end
end

-- If this file has a bug outside a game, answer like the Foundation stub did (all Good, never early), so the treat
-- flow never jams waiting for the timeout.
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
	local ok, _, outcome = Hud.ask(ctx.Remotes.TreatResult, session.Session, ratings)
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
	v.Hint.Text = "👀 Match the badge!"
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
		local button = Kit.button({
			Name = "Floor_" .. option.Dept,
			Kind = DEPT_KINDS[option.Dept] or "Secondary",
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
		setHeader(v, look.Icon, look.Text, if answer == "Right" then Theme.Colors.Good else Theme.Colors.Secondary)
		v.Hint.Text = if answer == "Right" then "💰 +bonus!" else "🛗 Off it goes!"
		if answer == "Right" then
			burst(layer, UDim2.fromScale(0.5, 0.48), "✨", 10, 0.2)
			sound("Sparkle")
		end
		waitFor(run, TRIAGE_HOLD)
	end
end

local function runSession(ctx: Types.Ctx, run: Run)
	local session = run.Session
	local v = view or build()
	view = v
	setSteps(ctx, v, session)
	v.ComboValue = session.Combo
	showCombo(ctx, v, session.Combo, false)
	v.Combo.Visible = not session.Simple
	openCard(v)
	if session.Kind == "Soak" then
		sound("Splash")
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
	local ok, _, outcome = Hud.ask(ctx.Remotes.TreatResult, session.Session, ratings)
	local answeredAt = os.clock()
	local triage: TriageCard? = nil
	if ok and type(outcome) == "table" then
		fireBus("TreatDone", outcome, run.Raw)
		if run.Alive then
			local serverRatings = if type(outcome.Ratings) == "table" then outcome.Ratings else ratings
			showResults(ctx, v, run, serverRatings, outcome)
			local combo = finite(outcome.Combo)
			if combo and not session.Simple then
				showCombo(ctx, v, math.max(0, math.floor(combo)), true)
			end
		end
		if session.Kind ~= "Soak" then
			triage = Pure.triage(outcome.Triage, ctx.Data.Departments)
		end
	end
	-- A floor to pick comes almost at once (the server is waiting); otherwise the answer stays a moment.
	if not waitFor(run, if triage then TRIAGE_LEAD else RESULT_HOLD) then
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
	}
	current = run
	-- 🎯 Steady Hands: this session's games draw and rate with wider Perfect windows.
	activeMini = Pure.eased(ctx.Config.MiniGame, session.Ease)
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

function MiniGames.init(ctx: Types.Ctx)
	busFire = ctx.fire
	ctx.on("TreatStart", function(raw: any)
		start(ctx, raw)
	end)
	-- Build the card now (hidden), so the first treatment doesn't wait for it and a broken build shows at join.
	local ok, built = pcall(build)
	if ok then
		view = view or built
	else
		warn("[MiniGames] the card failed to build: " .. tostring(built))
	end
end

return MiniGames
