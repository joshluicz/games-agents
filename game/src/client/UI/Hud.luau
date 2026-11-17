--!strict
-- Hud (build plan Task 6; look overhaul T5): the always-on screen, plus the shared UI pieces the other panels build on.
--
-- THE ZONE MAP (look build plan §B7; docs/research/2026-11-16-ux-cohesion-audit.md §3.1; memory-20261117-001 #4).
-- Every piece belongs to ONE zone (Logic/HudZones.ZONE) and keeps its slot: a piece that isn't revealed yet leaves its
-- slot empty, so nothing ever jumps. Laid out from HudZones.layout(safe width, safe height, top bar) on every resize:
--   System   the Roblox top-bar row (a ScreenInsets = TopbarSafeInsets ScreenGui, beside Roblox's own buttons): ⚙️ on
--            a dark-glass plate. On phones (a safe height under 440) the wallet joins this row
--   Wallet   top left, above the left rail: 💰, ⭐ and the hospital level, each a Unit glued to its number (Kit.unit:
--            the emoji and the big outlined number are two labels) with NO pill. The level row is "🏥 Lv 1 Clinic"
--            over ONE navy bar toward the next level, which counts both the ⭐ and the 💰 it needs (Logic/LevelBar),
--            with "⭐ 12/15" "💰 300/400" under it, or "Level up!" once both are met. A tap: ready = the Shop opens
--            on its Hospital tab and its Level up button bounces; else a toast says what the next level needs. The
--            roll-ups (Kit.countUp), the floating "+n" and the mini-game's 🔥 combo sticker stay
--   Now      top centre: ONE card (Hud.setNow), the highest priority first: 30 Hud's warnings (Not saving, Clinics
--            full) · 20 the tutorial card (UI/Tutorial) · 15 Hud's one hint ("Patients wait for you: press Send"
--            once a session · a new door's line · the first level-up) · 10 the tracked goal (the first unfinished
--            daily goal, "🎯 Treat 5 · 3/5"; a tap opens Goals). Hidden when empty. Toasts and banners stack under
--            it (UI/Toasts, Hud.nowBottom)
--   Status   top right, right-aligned, read-only, ONE icon a line: (1) day or night with words ("☀️ Night in 3:27" /
--            "🌙 ×2 · 2:08 left": the day/night line keeps m:ss); (2) ONE free-event chip ("🌟 Golden Hour in 12m":
--            Logic/NextEvent over Golden Hour only, in minutes, hidden while it runs, when it's over 6 h away and for
--            anything paid: memory-20261116-022, CLAUDE.md red line 3); (3) "Visitor today" / "Visitor treated" with
--            its face, only when it can come to your clinic; (4) at most 3 small boost chips (the play time left: a boost only ticks while
--            you play). Desktop: at the screen edge, as many rows as fit above the right rail (the clock first).
--            Phones: in the strip between the Now card and the right rail, in fewer words
--   Rails    left, menus you browse: 🛒 Shop · 👩‍⚕️ Nurses · 📖 Book · 🏅 Badges · 🏆 Top; right, rewards waiting: 🎁
--            Gifts · 🎯 Goals · 📬 Mail. One white Icon plate each (Kit.iconButton) with ONE shared fill: identity comes
--            from the icon and caption, never the fill, so the Shop looks like its neighbours. A still red dot
--            top-right when something waits there (a room you can buy or decor to place · new pages · mail (the
--            icon is always 📬: the dot is "a letter waits") · a goal
--            done · Nurse Journal news · a gift to open). 🎁's bar fills inside its plate. Phones: 56 px plates, no
--            captions, 3 a side, and 🏅 / 🏆 move into ⚙️ More (desktop too, when the left rail can't fit all five)
--   Bottom   only your hands (the `Carry` attribute: what you hold, nothing when they're empty), each ringed in its
--            station's colour with a red ✖ you HOLD to throw it away (Destructive: behind a hold, look build plan
--            §B8). Nothing is ever in the bottom corners (the thumbstick and jump on touch)
-- ⚙️ Settings, one list (Pure.SETTINGS): switches with a fixed label (Kit.toggle: Music · Effects, off = calm (the
-- client-only attributes MusicMuted and ReduceEffects) · Mini-games, off = simple taps (SetSimple) · Anyone can help,
-- off = friends only (SetHelpers; owners only)), then Quiet links: Skip tutorial while it runs, or Replay tutorial
-- once it's done and you own a clinic (each fires a bus event: UI/Tutorial owns the confirm and the remote) · the
-- doors that are off the rail (Badges, Top) · Admin (only while the server set IsAdmin). No label changes its words.
-- When things open (UI/Modal's ModalOpened / ModalClosed carry a HudMode): a Panel hides the rails, Now and Status
-- (the wallet stays, so you watch your cash while you shop) · the mini-game ("Game") hides the rails and Status (the
-- wallet and the Now card stay) · a Popup ("None") changes nothing · a celebration (UI/Celebrate's screen) hides
-- everything.
-- THE REVEAL (UI direction R0 and change 4b; Joshua, memory-20261117-007 #3: one door at a time, each when it first
-- has content; players who already have a door keep it). In the fixed slots: 💰 at first; ⭐ after the first
-- treatment; 🛒 at the shop step; 📖 at the Book step (its pointer needs it). After the tutorial each piece has its
-- own trigger (Pure.TRIGGERS, data): the level row at once · 👩‍⚕️ when the first nurse can be hired · 📬 with the
-- first letter · 🎁 when the first gift is ready · 🎯 and the day/night line after the first night · 🏅 🏆 with the
-- first badge · the Golden Hour chip at hospital Lv 3 · the visitor line at Lv 2. "Already have" is read from the
-- save itself (no new field): a nurse, a Book page, a badge, a gift opened, a night treated; and a save at Lv 2+ or
-- with a branch keeps every door. A save's doors are simply there when it loads; a NEW door pops once into its slot
-- with one line on the Now card, and the next waits its turn. Until the first snapshot arrives (Tutorial 0, "not
-- known yet") only 💰 shows. ⚙️ always shows.
-- Everything is drawn from the Snapshot, player attributes and Workspace attributes. The client never decides
-- anything: buttons only open panels, and panels only ask the server. Every motion honours Hud.calm(); nothing here
-- loops (the dots pop once; the Status clock only rewrites its text, and slows down while it's hidden).
-- Progression v2: a perk card waiting or tree points to spend dot 🛒 with a 🃏 / 🌳 sticker that pops once (never
-- "you can open a branch"); after a rebirth its 🌳 points fly into 🛒 (UI/Celebrate); a nurse you sold sends its
-- coins flying into 💰 (NurseNews Sold / Gone).
--
-- THE SPLIT (look build plan §A/§B8). The modal shell lives in UI/Modal (T6), which never requires this module. Hud
-- keeps these RE-EXPORTS, so no caller changed:
--   Hud.modal(ctx, spec): Modal        = Modal.modal (it also hands Hud the bus, so Hud.sound works before Hud.init)
--   Hud.isOpen(name?) · Hud.fitTabs(column, tabs, gap) · Hud.fitHeight(content, area, min?)   = Modal's
--   Hud.confirm(ctx, spec, onYes)      = Modal.confirm: THE confirm ("Not now" focused; Hold for a hold-to-confirm)
--   Hud.oddsPopup(ctx, spec)           = Modal.oddsPopup: THE odds popup (every row: the word and the number)
-- The Now slot (look build plan §B7):
--   Hud.setNow(source, card?, priority) offer a card to the top-centre Now slot (nil removes that source's). The
--                                      highest priority shows (a tie: the newest offer); Hud parents it, centres it and
--                                      sets its width (HudZones.nowWidth); the card sets its own height. The caller
--                                      owns its card: Hud only parents, shows and hides it
--   Hud.nowBottom(): number            px from the screen top (the device-safe top, the top-bar row included) to the
--                                      Now card's bottom; 0 while no card shows
--   Hud.NowMoved: Signal (bottom)      fires whenever nowBottom changes (UI/Toasts follows it), and on liftNow
--   Hud.liftNow(on)                    draws the Now slot over the mini-game's shade and card (UI/Tutorial, for its
--                                      slim strip while a "Game" modal is open); off = back on the HUD's layer
--   Hud.nowLifted(): boolean · Hud.nowEdge(): number   lifted right now · the Now card's bottom in screen px
--                                      (AbsolutePosition's space; 0 while no card shows): UI/MiniGames keeps clear
--   Hud.topbar(): number               the Roblox top-bar row's height (GuiService.TopbarInset; HudZones.TOPBAR when
--                                      it can't be read)
--   Hud.Pure                           the zone rules in numbers and words (tests/HudScreen.spec loads the PURE block)
--
-- Shared helpers (the other UI modules require this module for them; none of them needs Hud.init to have run):
--   Hud.ask(remote, ...): (ok, msg, payload?)   InvokeServer that never throws and gives up after ASK_TIMEOUT
--                                      seconds; payload is a table third value (TreatResult's TreatOutcome)
--   Hud.portrait(look, dark?): Frame   a cute 2D creature face drawn from a Data `Look` (dark = "not met yet")
--   Hud.lookOf(id): Look?              the Look of a PatientId or RegularId
--   Hud.decorSlots(data, state)        every "<RoomId>:<n>" decor slot in your rooms, and what's in it
--   Hud.shopNews(data, state)          { Rooms, Decor, Hospital, Branch }: what the 🛒 dot is about (a room you can
--                                      buy now, level gate included; decor to place; a hospital level-up you can
--                                      afford; Progression v2: Branch = a reward to claim, i.e. a perk card waiting
--                                      or tree points a node can take. NEVER "you can open a branch": no pressure to
--                                      rebirth, red line 3). Branch dots the 🛒 toward its 🏥 tab
--   Hud.fly(from, icon, target?, n?)   icons burst from `from` and arc into a HUD piece (Hud.target name: "Cash",
--                                      "Stars", "Nurses", ...), each landing with a bump and a coin tinkle; with no
--                                      target (or a hidden one) they float up and fade. `from` is a GuiObject, a
--                                      world Vector3 (a cured patient: flying coins) or nil (the screen's middle).
--                                      n defaults to 6, at most 10. Calm: nothing flies (the numbers still update)
--   Hud.pop(gui) · Hud.shake(gui)      a happy bounce · a "nope" wiggle
--   Hud.calm(): boolean                Reduced Motion, or the ✨ calm toggle (ReduceEffects): skip the motion
--   Hud.sound(name, volume?)           a Feel/Sounds cue over the bus
--   Hud.format(n): string              1,234 · 1.2M past a million
--   Hud.target(name): GuiObject?       a HUD piece by name ("Cash", "Stars", "Shop", "Book", "Mailbox", "Goals",
--                                      "Nurses", "Badges", "Boards", "Gifts", "Settings", "Hands", "Level"), for pointers
--                                      (UI/Tutorial) and flying icons. The rail names are the rail plates; a piece
--                                      moved into ⚙️ More points at ⚙️
--   Hud.livePlay(state): (save, day, pending)   Data.Playtime as it is right now: the Snapshot's saved part plus
--                                      the live PlayToday/PlayTotal attributes (Server/Playtime), on today's UTC
--                                      day (yesterday's opened gifts don't count); pending = seconds not saved yet
--   Hud.liveBoosts(state): { { Id, Left } }   the timed boosts still running, with their live play time left
--   Hud.boostLine(data, state): string the "Your boosts" summary: timed ones first, then permanent percents
--
-- Client bus (ctx.on / ctx.fire):
--   listens  "BookNew" (count) · "NursesNew" (count)   BookPanel / NursePanel: unseen news, for the 📖 / 👩‍⚕️ dots
--   listens  "NurseNews" (info)                        a nurse sold: its coins fly into 💰
--   listens  "ModalOpened" (name, hudMode) · "ModalClosed" (name, hudMode)   UI/Modal: what the HUD hides meanwhile
--   fires    "Open" (name, tab?)                       name = "Shop" | "Book" | "Mailbox" | "Goals" | "Nurses" |
--                                                      "Badges" | "Boards" | "Gifts" | "Admin"
--   fires    "SkipTutorial" () · "ReplayTutorial" ()   the ⚙️ rows (UI/Tutorial shows the confirm, asks the remote)
--   fires    "Sound" (name, volume?)                   Nope on a shake, Pop when icons land

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Palette = require(Shared:WaitForChild("Palette"))
local Signal = require(Shared:WaitForChild("Signal"))
local PatientsData = require(Shared:WaitForChild("Data"):WaitForChild("Patients")) :: any
local RegularsData = require(Shared:WaitForChild("Data"):WaitForChild("Regulars")) :: any
local Logic = Shared:WaitForChild("Logic")
local TutorialLogic = require(Logic:WaitForChild("Tutorial"))
local PlaytimeLogic = require(Logic:WaitForChild("Playtime"))
local BoostsLogic = require(Logic:WaitForChild("Boosts"))
local LevelsLogic = require(Logic:WaitForChild("Levels"))
local LevelBar = require(Logic:WaitForChild("LevelBar"))
local BeltLogic = require(Logic:WaitForChild("Belt"))
local ProgressLogic = require(Logic:WaitForChild("Progress"))
local TreeLogic = require(Logic:WaitForChild("Tree"))
local HudZones = require(Logic:WaitForChild("HudZones"))
local NextEvent = require(Logic:WaitForChild("NextEvent"))
local Icons = require(script.Parent.Icons)
local Kit = require(script.Parent.Kit)
local Modal = require(script.Parent.Modal)
local Theme = require(script.Parent.Theme)

local Hud = {}

-- The modal types live in UI/Modal now (re-exported so `Hud.Modal` and `Hud.ModalSpec` still work).
export type Layer = Modal.Layer
export type ModalSpec = Modal.ModalSpec
export type Modal = Modal.Modal

------------------------------------------------------------------------------------------------------------------
-- The zone rules in numbers and words
------------------------------------------------------------------------------------------------------------------

-- PURE-BEGIN
-- No Roblox APIs: tests/HudScreen.spec loads this block on its own, with TutorialLogic, NextEvent, HudZones and Icons.
local Pure = {}

-- The Now slot's priorities (look build plan §B7): Hud's warnings · the tutorial card (UI/Tutorial) · Hud's one hint
-- (a new door's line, the first level-up, "press Send") · the goal.
Pure.PRIORITY = table.freeze({ Warning = 30, Tutorial = 20, Hint = 15, Goal = 10 })
Pure.STAGGER = 0.15 -- seconds between two pieces that arrive with no line (the tutorial's own steps)
Pure.REVEAL_HOLD = 4 -- seconds a new door's line stays on the Now card; the next door waits for it
Pure.MAX_BOOSTS = 3 -- boost chips in Status, at most
Pure.ROW = 28 -- a Status row's height (px)
Pure.ROW_GAP = 4
Pure.STATUS_ORDER = table.freeze({ "Clock", "Event", "Visitor", "Boosts" }) -- top to bottom; the first rows win
-- The free events Status may count down to (memory-20261116-022). Golden Hour only for now (look build plan §F 7);
-- admin events join when they exist. Nothing paid is ever on this list.
Pure.GOLDEN = table.freeze({ Id = "GoldenHour", Icon = Icons.Status.Golden, Name = "Golden Hour" })
Pure.GOLDEN_LEVEL = 3 -- the Golden Hour chip shows from this hospital level (memory-20261117-007 #3)
-- The hands at the bottom centre: each between Min and Max px, the row keeping Clear px free at each side (the
-- thumbstick and the jump button sit about 100 px in from the edges).
Pure.HAND = table.freeze({ Max = 84, Min = 56, Gap = 6, Clear = 120 })
-- Every rail plate is the same Icon role: identity comes from the icon and caption, never the fill.
Pure.RAIL_KIND = "Icon"
Pure.RAIL = table.freeze({
	Shop = table.freeze({ Icon = Icons.Door.Shop, Caption = "Shop" }),
	Nurses = table.freeze({ Icon = Icons.Door.Nurses, Caption = "Nurses" }),
	Book = table.freeze({ Icon = Icons.Door.Book, Caption = "Book" }),
	Badges = table.freeze({ Icon = Icons.Door.Badges, Caption = "Badges" }),
	Boards = table.freeze({ Icon = Icons.Door.Top, Caption = "Top" }),
	Gifts = table.freeze({ Icon = Icons.Door.Gifts, Caption = "Gifts" }),
	Goals = table.freeze({ Icon = Icons.Door.Goals, Caption = "Goals" }),
	Mailbox = table.freeze({ Icon = Icons.Door.Mail, Caption = "Mail" }), -- one icon; "ready" is the red dot
})
-- The Quiet links ⚙️ shows for a rail piece that's off the rail, in words (the door's icon lives on its plate).
-- (Nurses, Book, Goals and Mail only leave the rail on a phone under 348 px of safe height: HudZones.layout.)
Pure.MORE = table.freeze({
	Badges = "Badges",
	Boards = "Top",
	Nurses = "Nurses",
	Book = "Book",
	Goals = "Goals",
	Mailbox = "Mail",
})
-- ⚙️ Settings (UI direction §4 #5): every row is a Toggle (a fixed label and a switch: Kit.toggle) or a Link (a
-- Quiet text button). No label changes its words with state: the switch shows the state. The More rows above are
-- Links too.
Pure.SETTINGS = table.freeze({
	Music = table.freeze({ Kind = "Toggle", Label = "Music" }),
	Effects = table.freeze({ Kind = "Toggle", Label = "Effects" }), -- off = calm effects
	Simple = table.freeze({ Kind = "Toggle", Label = "Mini-games" }), -- off = simple taps
	Helpers = table.freeze({ Kind = "Toggle", Label = "Anyone can help" }), -- off = friends only
	Skip = table.freeze({ Kind = "Link", Label = "Skip tutorial" }),
	Replay = table.freeze({ Kind = "Link", Label = "Replay tutorial" }),
	Admin = table.freeze({ Kind = "Link", Label = "Admin" }),
}) :: { [string]: { Kind: string, Label: string } }

-- THE REVEAL (UI direction R0 and change 4b; Joshua, memory-20261117-007 #3: "The HUD reveals one door at a time,
-- each when it first has content ... Players who already have a door keep it").
-- REVEAL_ORDER is every piece that can arrive, in the order the queue shows them (the wallet, the left rail, the
-- right rail, then the Status lines). TRIGGERS is DATA, so a trigger can move without touching code: a piece shows
-- when ANY of its facts is true (Pure.facts works each fact out from the Snapshot and what this session has seen).
-- "Already have" needs no new save field: it is read from what the save already holds (a nurse, a Book page, a
-- badge, a gift opened, a night treated) and from Veteran (hospital Lv 2+ or a branch opened: a save that old had
-- every door before this rule, so it keeps them all).
Pure.REVEAL_ORDER = table.freeze({
	"Stars",
	"Level",
	"Shop",
	"Nurses",
	"Book",
	"Badges",
	"Boards",
	"Gifts",
	"Goals",
	"Mailbox",
	"Clock",
	"Event",
	"Visitor",
	"Boosts",
})
Pure.TRIGGERS = table.freeze({
	Stars = table.freeze({ "Treated" }), -- after the first treatment
	Level = table.freeze({ "Done" }), -- the level and its bar: once the tutorial is done
	Shop = table.freeze({ "ShopStep" }), -- the tutorial's shop step
	Nurses = table.freeze({ "NurseOwned", "CanHire", "Veteran" }), -- the first nurse can be hired
	Book = table.freeze({ "BookStep", "BookPage", "Veteran" }), -- the first page is filled
	Badges = table.freeze({ "Badge", "Veteran" }), -- the first badge
	Boards = table.freeze({ "Badge", "Veteran" }),
	Gifts = table.freeze({ "GiftReady", "GiftOpened", "Veteran" }), -- the first play gift is ready
	Goals = table.freeze({ "NightSeen", "GoalReady", "Veteran" }), -- the first day has ended (or a goal is done)
	Mailbox = table.freeze({ "MailReady", "Story", "Veteran" }), -- the first letter
	Clock = table.freeze({ "NightSeen", "Veteran" }), -- the first night
	Event = table.freeze({ "Golden" }), -- hospital Lv 3 (GOLDEN_LEVEL)
	Visitor = table.freeze({ "Veteran" }),
	Boosts = table.freeze({ "Boost" }), -- a timed boost is running
}) :: { [string]: { string } }
-- What the Now card says as a door arrives (one line, six words or fewer, no emoji: the door's icon is on its tile).
-- A piece with no line arrives quietly.
Pure.DOOR_LINE = table.freeze({
	Level = "Your clinic level is here",
	Nurses = "New: hire your first nurse",
	Badges = "New: your badges",
	Boards = "New: the top clinics",
	Gifts = "New: a gift to open",
	Goals = "New: daily goals",
	Mailbox = "New: you have mail",
	Clock = "New: the day and night clock",
	Event = "New: Golden Hour times",
}) :: { [string]: string }
-- The icon on the Now card's tile for a piece that isn't a rail door (a rail door shows its own).
Pure.DOOR_ICON = table.freeze({
	Level = Icons.Unit.Level,
	Clock = Icons.Status.Night,
	Event = Icons.Status.Golden,
}) :: { [string]: string }
-- Hud's other words (plain: no emoji in front of a sentence).
Pure.TEXT = table.freeze({
	LevelUp = "You can level up: tap here",
	Send = "Patients wait for you: press Send",
	Throw = "Hold the red button to throw away",
	NotSaving = "Not saving",
	ClinicsFull = "Clinics full",
	VisitorComing = "Visitor today",
	VisitorDone = "Visitor treated",
	NoBoosts = "No boosts yet: earn badges!",
})
-- "Patients wait for you: press Send" (patients no longer walk to a bay by themselves: Logic/Routing): once a
-- session, past the tutorial, when a patient has sat waiting to be sent for After seconds. It stays at most Hold
-- seconds, and goes as soon as nobody waits.
Pure.SEND_HINT = table.freeze({ After = 12, Hold = 10 })
-- A waiting patient's prompt (Server/Patients: U.sendPrompt; UI/SendCard.Pure.PROMPT_NAME): on only while it waits.
Pure.SEND_PROMPT = table.freeze({ Name = "SendPrompt", Tag = "TreatPrompt" })
-- Which hint the one Hint card shows when more than one is due: the patient first (it is waiting now), then a new
-- door's line (it is short-lived), then the level-up (it can wait).
Pure.HINT_ORDER = table.freeze({ "Send", "Door", "LevelUp" })

type NowEntry = { Source: string, Priority: number, Seq: number }
type Reveal = { [string]: boolean }
type Hidden = { Rails: boolean, Now: boolean, Status: boolean, Wallet: boolean, System: boolean, Hands: boolean }
type Goal = { Id: string, Icon: string, Text: string, Ratio: number }
type StatusBox = { X1: number, Top: number, Width: number, Rows: number, Compact: boolean }

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- The Now slot: the highest priority shows; on a tie, the newest offer.
function Pure.nowPick(offers: { NowEntry }): string?
	local best: NowEntry? = nil
	for _, offer in offers do
		if type(offer) == "table" and type(offer.Source) == "string" and finite(offer.Priority) then
			local seq = if finite(offer.Seq) then offer.Seq else 0
			if
				best == nil
				or offer.Priority > best.Priority
				or (offer.Priority == best.Priority and seq > (if finite(best.Seq) then best.Seq else 0))
			then
				best = offer
			end
		end
	end
	return if best then best.Source else nil
end

-- "m:ss" (never negative; minutes grow past 59).
function Pure.clock(seconds: any): string
	local left = if finite(seconds) then math.max(0, math.floor(seconds)) else 0
	return string.format("%d:%02d", left // 60, left % 60)
end

-- Status row 1: day or night with words. `left` is the seconds to the next phase (nil: not known yet, so ""), `pay`
-- the night pay multiplier. Compact (a phone's narrow column) drops words: "☀️ 3:27" is the day's time left.
function Pure.dayLine(night: boolean, left: any, pay: any, compact: boolean?): string
	if not finite(left) then
		return ""
	end
	local time = Pure.clock(left)
	if night then
		local times = if finite(pay) and pay > 1 then "×" .. tostring(pay) .. " · " else ""
		return Icons.Status.Night .. " " .. times .. time .. (if compact then "" else " left")
	end
	-- One Status icon a line: by day the sun and the time left in the day (compact), or "Night in" with words.
	return Icons.Status.Day .. " " .. (if compact then time else "Night in " .. time)
end

-- The candidates for the free-event chip: Golden Hour (Workspace GoldenStartsAt / GoldenHour, NurseBelt) while it's
-- still to come. Never one with Paid = true: there is no paid event on this list (red line 3).
function Pure.eventCandidates(startsAt: any, running: any): { any }
	if running == true or not finite(startsAt) then
		return {}
	end
	return {
		{ Id = Pure.GOLDEN.Id, Icon = Pure.GOLDEN.Icon, Name = Pure.GOLDEN.Name, At = startsAt, Paid = false },
	}
end

-- Status row 2: the one free-event chip, or nil (none within 6 h). Minutes, never seconds (NextEvent.label).
function Pure.eventChip(now: number, candidates: { any }, compact: boolean?): string?
	local view = NextEvent.pick(now, candidates)
	if not view then
		return nil
	end
	local when = NextEvent.label(view.At - now)
	return if compact then view.Icon .. " " .. when else view.Icon .. " " .. view.Name .. " " .. when
end

-- Status row 3: Today's Visitor in words (its face is beside it), only while it can come to your clinic ("Coming")
-- or once it's treated.
function Pure.visitorLine(status: any): string?
	if status == "Coming" then
		return Pure.TEXT.VisitorComing
	elseif status == "Done" then
		return Pure.TEXT.VisitorDone
	end
	return nil
end

-- A daily goal in two or three words: "Treat 5", "Treat 3 🌙", "Make 10", "Treat 6 🌳" (the wing's icon). The
-- kinds keep their saved ids ("Cure", "CureNight", "CureWing"); only the words say treat (Real Clinic design §12).
function Pure.goalName(def: any, wings: any): string
	local target = tostring(def.Target)
	if def.Kind == "Make" then
		return "Make " .. target
	elseif def.Kind == "CureNight" then
		return "Treat " .. target .. " " .. Icons.Status.Night
	elseif def.Kind == "CureWing" then
		local wing = if type(wings) == "table" and type(def.Wing) == "string" then rawget(wings, def.Wing) else nil
		local icon = if type(wing) == "table" and type(wing.Icon) == "string" then " " .. wing.Icon else ""
		return "Treat " .. target .. icon
	end
	return "Treat " .. target
end

-- The tracked goal (look build plan §F 7): the first daily goal still under its target, as "Treat 5 · 3/5" with the
-- share done. nil when every goal is done (or there are none).
function Pure.trackedGoal(goals: any, defs: any, wings: any): Goal?
	if type(goals) ~= "table" or type(defs) ~= "table" then
		return nil
	end
	for _, goal in ipairs(goals) do
		if type(goal) == "table" then
			for _, def in ipairs(defs) do
				if type(def) == "table" and def.Id == goal.Id and finite(def.Target) and def.Target > 0 then
					local progress = if finite(goal.Progress) then math.max(0, math.floor(goal.Progress)) else 0
					if progress < def.Target then
						return {
							Id = def.Id,
							Icon = Icons.Door.Goals,
							Text = Pure.goalName(def, wings) .. " · " .. progress .. "/" .. def.Target,
							Ratio = progress / def.Target,
						}
					end
				end
			end
		end
	end
	return nil
end

local function filled(value: any): boolean
	return type(value) == "table" and next(value) ~= nil
end

local function numberOr0(value: any): number
	return if finite(value) then value else 0
end

-- The facts the triggers read. `state` is the Snapshot (a missing Tutorial field counts as done); `session` is what
-- only this session knows: Cured (a treatment landed), Night (a night was seen), CanHire (the cheapest nurse on
-- the belt is affordable now), GiftReady, GoalReady and GoldenLevel (Config.Belt's gate for Secret nurses). Until
-- the tutorial is over only its own three facts can be true (Treated, ShopStep, BookStep); a replay counts as over,
-- so a replaying player keeps every door their save has content for.
function Pure.facts(state: any, session: any): { [string]: boolean }
	local data = if type(state) == "table" then state else {}
	local seen = if type(session) == "table" then session else {}
	local step = if type(data.Tutorial) == "number" then data.Tutorial else TutorialLogic.DONE
	local replay = data.TutorialReplay == true
	local running = TutorialLogic.active(step) and not replay
	local open = replay or TutorialLogic.isDone(step)
	local level = numberOr0(data.Level)
	local rebirth = data.Rebirth
	local playtime = if type(data.Playtime) == "table" then data.Playtime else {}
	local stats = if type(data.Stats) == "table" then data.Stats else {}
	local boosts = data.Boosts
	local badge = false
	if type(data.Badges) == "table" then
		for _, tier in data.Badges do
			badge = badge or numberOr0(tier) > 0
		end
	end
	return {
		Treated = open
			or (running and (step >= TutorialLogic.MORE or (step >= TutorialLogic.REST and seen.Cured == true))),
		ShopStep = open or (running and step >= TutorialLogic.SHOP),
		BookStep = TutorialLogic.active(step) and step >= TutorialLogic.BOOK,
		Done = open,
		Veteran = open and (level > 1 or (type(rebirth) == "table" and numberOr0(rebirth.Count) > 0)),
		BookPage = open and filled(data.Book),
		NurseOwned = open and (filled(data.Nurses) or filled(data.NurseIndex)),
		CanHire = open and seen.CanHire == true,
		Badge = open and badge,
		GiftReady = open and seen.GiftReady == true,
		GiftOpened = open and (filled(playtime.Claimed) or numberOr0(playtime.Rank) > 0),
		GoalReady = open and seen.GoalReady == true,
		NightSeen = open and (seen.Night == true or numberOr0(stats.NightCures) > 0),
		MailReady = open and data.MailboxReady == true,
		Story = open and filled(data.Story),
		Golden = open and level >= (if finite(seen.GoldenLevel) then seen.GoldenLevel else Pure.GOLDEN_LEVEL),
		Boost = open and type(boosts) == "table" and filled(boosts.Timed),
	}
end

-- THE reveal: one flag per piece in REVEAL_ORDER. A piece shows when any of its TRIGGERS' facts is true, or when it
-- was already shown this session past the tutorial (`kept`: a door never leaves because the cash was spent or the
-- letter was opened).
function Pure.reveal(state: any, session: any, kept: { [string]: any }?): Reveal
	local facts = Pure.facts(state, session)
	local out: Reveal = {}
	for _, name in Pure.REVEAL_ORDER do
		local on = facts.Done and kept ~= nil and kept[name] == true
		for _, fact in Pure.TRIGGERS[name] do
			on = on or facts[fact] == true
		end
		out[name] = on
	end
	return out
end

-- How many rail doors and Status lines a reveal shows (the budget a fresh Lv 1 save must keep: 3 doors, 1 line).
function Pure.revealCount(reveal: Reveal): (number, number)
	local doors, lines = 0, 0
	for name, on in reveal do
		if on and Pure.RAIL[name] then
			doors += 1
		elseif on and table.find(Pure.STATUS_ORDER, name) then
			lines += 1
		end
	end
	return doors, lines
end

-- "Patients wait for you: press Send": past the tutorial, not shown yet this session, and a patient has waited to
-- be sent for SEND_HINT.After seconds (`waited`: the longest wait, nil when nobody waits).
function Pure.sendHint(step: any, waited: any, used: boolean?): boolean
	return used ~= true and TutorialLogic.isDone(step) and finite(waited) and waited >= Pure.SEND_HINT.After
end

-- The Now card points a new player at their FIRST level-up: at hospital Lv 1, the moment the Shop's button would
-- work, until they tap it (`used`: once a session). Later levels have the bar's own "Level up!".
function Pure.levelHint(step: any, level: any, ready: boolean?, used: boolean?): boolean
	return used ~= true and ready == true and level == 1 and TutorialLogic.isDone(step)
end

-- A new door's line and the icon on its tile (nil: the piece arrives quietly).
function Pure.doorLine(name: any): (string?, string)
	local line = Pure.DOOR_LINE[name]
	local face = Pure.RAIL[name]
	return line, if face then face.Icon else (Pure.DOOR_ICON[name] or "")
end

-- The one hint to show, or nil: the first of HINT_ORDER that is due.
function Pure.hintPick(due: { [string]: any }): string?
	for _, kind in Pure.HINT_ORDER do
		if due[kind] then
			return kind
		end
	end
	return nil
end

-- The HudMode in force: the strongest of the open modals' modes (Game > Panel > None).
function Pure.mode(open: { [string]: string }): string
	local mode = "None"
	for _, value in open do
		if value == "Game" then
			return "Game"
		elseif value == "Panel" then
			mode = "Panel"
		end
	end
	return mode
end

-- What hides (look build plan §B7): a Panel hides the rails, Now and Status; the mini-game ("Game") the rails and
-- Status; a celebration everything; "None" (a Popup) nothing.
function Pure.hidden(mode: string, celebrating: boolean?): Hidden
	if celebrating == true then
		return { Rails = true, Now = true, Status = true, Wallet = true, System = true, Hands = true }
	end
	local panel, game = mode == "Panel", mode == "Game"
	return {
		Rails = panel or game,
		Now = panel,
		Status = panel or game,
		Wallet = false,
		System = false,
		Hands = false,
	}
end

-- The ⚙️ panel's rows, in order: the switches, Skip or Replay, then the Links. `more` lists the rail pieces off the
-- rail (revealed ones only, so Badges and Top show there from the first badge).
function Pure.settingsRows(step: any, hasPlot: boolean?, isAdmin: boolean?, more: { string }?): { string }
	local rows = { "Music", "Effects", "Simple" }
	if hasPlot == true then
		table.insert(rows, "Helpers")
	end
	if TutorialLogic.canSkip(step) then
		table.insert(rows, "Skip")
	elseif TutorialLogic.canReplay(step, hasPlot == true) then
		table.insert(rows, "Replay")
	end
	for _, piece in more or {} do
		if Pure.MORE[piece] then
			table.insert(rows, piece)
		end
	end
	if isAdmin == true then
		table.insert(rows, "Admin")
	end
	return rows
end

-- One hand's side (px) for `count` hands on a screen `width` px wide.
function Pure.handSize(width: any, count: any): number
	local n = if finite(count) then math.max(1, math.floor(count)) else 1
	local room = (if finite(width) then width else 0) - 2 * Pure.HAND.Clear - (n - 1) * Pure.HAND.Gap
	return math.clamp(math.floor(room / n), Pure.HAND.Min, Pure.HAND.Max)
end

-- Where Status stands (px from the top left): its right edge X1, its top and width, how many rows fit, and whether
-- it speaks in fewer words. Desktop and tablet: at the screen edge, as many rows as fit above the right rail. Phones:
-- the right rail starts right under the top bar, so Status stands in the strip between the Now card and the rail.
function Pure.statusBox(layout: HudZones.Layout, safeW: number): StatusBox
	local top = layout.Top + 8
	if layout.Phone then
		local x1 = safeW - layout.Margin - layout.Button - layout.Gap
		local now = HudZones.nowRect(layout, safeW)
		return { X1 = x1, Top = top, Width = math.max(0, x1 - (now.X1 + 8)), Rows = #Pure.STATUS_ORDER, Compact = true }
	end
	local room = layout.RailTop - 8 - top
	local rows = math.clamp(math.floor((room + Pure.ROW_GAP) / (Pure.ROW + Pure.ROW_GAP)), 1, #Pure.STATUS_ORDER)
	return { X1 = safeW - layout.Margin, Top = top, Width = layout.StatusWidth, Rows = rows, Compact = false }
end

-- Toasts and banners start 8 px under the Now card, or under the top bar when no card shows (px from the top).
function Pure.noticeTop(nowBottom: any, topbar: any): number
	if finite(nowBottom) and nowBottom > 0 then
		return nowBottom + 8
	end
	return (if finite(topbar) and topbar >= 0 then topbar else HudZones.TOPBAR) + 8
end

-- The notice stack is as wide as the Now card (at least 240 px, or the screen less its margins if that's narrower).
function Pure.noticeWidth(layout: HudZones.Layout, safeW: number): number
	return math.max(layout.NowWidth, math.min(240, safeW - 2 * layout.Margin))
end

-- The first `max` (default MAX_BOOSTS) running boosts.
function Pure.boosts(live: any, max: number?): { any }
	local out = {}
	if type(live) == "table" then
		for _, entry in ipairs(live) do
			if #out >= (max or Pure.MAX_BOOSTS) then
				break
			end
			table.insert(out, entry)
		end
	end
	return out
end
-- PURE-END

Hud.Pure = Pure

------------------------------------------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------------------------------------------

local FLOAT_INFO = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function commas(n: number): string
	local digits = tostring(math.floor(math.abs(n)))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return (if n < 0 then "-" else "") .. grouped
end

function Hud.format(n: any): string
	if type(n) ~= "number" or n ~= n then
		return "0"
	end
	if math.abs(n) >= 1e6 then
		return (string.gsub(string.format("%.1fM", n / 1e6), "%.0M", "M"))
	end
	return commas(n)
end

-- Calm motion: the device's Reduced Motion setting, or the ✨ calm-effects toggle (Feel/Atmosphere sets the
-- client-only player attribute ReduceEffects). Every tween in the UI checks this.
function Hud.calm(): boolean
	return Kit.reducedMotion() or Players.LocalPlayer:GetAttribute("ReduceEffects") == true
end

-- Sound cues go over the client bus to Feel/Sounds ("Sound", name), so UI never requires a Feel module.
local fireBus: ((string, ...any) -> ())? = nil
function Hud.sound(name: string, volumeScale: number?)
	if fireBus then
		fireBus("Sound", name, volumeScale)
	end
end

-- Kit.punch reuses the UIScale that's already there (Kit buttons have one: two on one object fight) and tells
-- Kit's breathing to wait until the bounce is over.
function Hud.pop(gui: GuiObject?, size: number?)
	if not gui or Hud.calm() then
		return
	end
	Kit.punch(gui, size or 1.18, POP_INFO)
end

function Hud.shake(gui: GuiObject?)
	Hud.sound("Nope")
	if not gui or Hud.calm() then
		return
	end
	task.spawn(function()
		for _, angle in { -7, 7, -5, 5, 0 } do
			local tween = TweenService:Create(gui, TweenInfo.new(0.05), { Rotation = angle })
			tween:Play()
			tween.Completed:Wait()
		end
		gui.Rotation = 0
	end)
end

------------------------------------------------------------------------------------------------------------------
-- Modals: UI/Modal owns the shell. These are re-exports, so every panel keeps calling Hud.*
------------------------------------------------------------------------------------------------------------------

-- A wrapper only so Hud.sound works for a panel built before Hud.init has run (it hands Hud the bus).
function Hud.modal(ctx: Types.Ctx, spec: ModalSpec): Modal
	fireBus = fireBus or ctx.fire
	return Modal.modal(ctx, spec)
end

Hud.isOpen = Modal.isOpen
Hud.confirm = Modal.confirm
Hud.oddsPopup = Modal.oddsPopup
Hud.fitTabs = Modal.fitTabs
Hud.fitHeight = Modal.fitHeight

------------------------------------------------------------------------------------------------------------------
-- The Now slot (look build plan §B7): one card at the top centre. It works before Hud.init (UI/Tutorial may offer
-- its card first); Hud.init places it from the zone map on every resize.
------------------------------------------------------------------------------------------------------------------

Hud.NowMoved = Signal.new()

function Hud.topbar(): number
	local ok, inset = pcall(function()
		return GuiService.TopbarInset
	end)
	if ok and typeof(inset) == "Rect" then
		return math.max(0, inset.Max.Y)
	end
	return HudZones.TOPBAR
end

type NowOffer = { Card: GuiObject, Priority: number, Seq: number }
local nowOffers: { [string]: NowOffer } = {}
local nowSeq = 0
local nowSlot: Frame? = nil
local nowShown: GuiObject? = nil -- the card on show
local nowWatch: { RBXScriptConnection } = {}
local lastNowBottom = -1
-- Zones shrinking away right now: they still draw while they go, but they already count as hidden.
local leaving: { [GuiObject]: boolean } = setmetatable({}, { __mode = "k" }) :: any

function Hud.nowBottom(): number
	local slot, card = nowSlot, nowShown
	if not slot or not card or not slot.Visible or leaving[slot] or not card.Visible or card.Parent ~= slot then
		return 0
	end
	local screen = slot:FindFirstAncestorOfClass("ScreenGui")
	local origin = if screen then screen.AbsolutePosition.Y else 0
	return math.max(0, math.floor(card.AbsolutePosition.Y + card.AbsoluteSize.Y - origin + 0.5))
end

-- The Now card's bottom in AbsolutePosition's space (for a ScreenGui with other insets); 0 while no card shows.
function Hud.nowEdge(): number
	local card = nowShown
	if Hud.nowBottom() <= 0 or not card then
		return 0
	end
	return math.floor(card.AbsolutePosition.Y + card.AbsoluteSize.Y + 0.5)
end

-- One over the mini-game's card (UI/MiniGames: Popup + 5), under cure pops, celebrations and toasts.
local NOW_LIFTED = Theme.DisplayOrder.Popup + 6
local nowLifted = false

function Hud.nowLifted(): boolean
	return nowLifted
end

local function nowChanged()
	local bottom = Hud.nowBottom()
	if bottom ~= lastNowBottom then
		lastNowBottom = bottom
		Hud.NowMoved:Fire(bottom)
	end
end

local function nowFrame(): Frame
	local existing = nowSlot
	if existing then
		return existing
	end
	local gui = Kit.screen("HudNow", Theme.DisplayOrder.Hud)
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	local slot = Instance.new("Frame")
	slot.Name = "Now"
	slot.AnchorPoint = Vector2.new(0.5, 0)
	slot.Position = UDim2.new(0.5, 0, 0, Hud.topbar() + Theme.Space.Gap)
	slot.Size = UDim2.fromOffset(HudZones.NOW_MAX, 0)
	slot.AutomaticSize = Enum.AutomaticSize.Y
	slot.BackgroundTransparency = 1
	slot.Parent = gui
	slot:GetPropertyChangedSignal("AbsolutePosition"):Connect(nowChanged)
	slot:GetPropertyChangedSignal("Visible"):Connect(nowChanged)
	nowSlot = slot
	return slot
end

function Hud.liftNow(on: boolean)
	local lift = on == true
	if lift == nowLifted then
		return
	end
	nowLifted = lift
	local screen = nowFrame():FindFirstAncestorOfClass("ScreenGui")
	if screen then
		screen.DisplayOrder = if lift then NOW_LIFTED else Theme.DisplayOrder.Hud
	end
	Hud.NowMoved:Fire(Hud.nowBottom())
end

local function syncNow()
	local entries: { NowEntry } = {}
	for source, offer in nowOffers do
		table.insert(entries, { Source = source, Priority = offer.Priority, Seq = offer.Seq })
	end
	local bestSource = Pure.nowPick(entries)
	local best = if bestSource then nowOffers[bestSource] else nil
	local slot = nowFrame()
	for _, offer in nowOffers do
		local card = offer.Card
		local shown = offer == best
		if shown then
			card.AnchorPoint = Vector2.new(0.5, 0)
			card.Position = UDim2.fromScale(0.5, 0)
			card.Size = UDim2.new(1, 0, 0, card.Size.Y.Offset)
		end
		card.Visible = shown
		card.Parent = slot
	end
	local card = if best then best.Card else nil
	if card ~= nowShown then
		for _, connection in nowWatch do
			connection:Disconnect()
		end
		table.clear(nowWatch)
		nowShown = card
		if card then
			table.insert(nowWatch, card:GetPropertyChangedSignal("AbsoluteSize"):Connect(nowChanged))
			table.insert(nowWatch, card:GetPropertyChangedSignal("Visible"):Connect(nowChanged))
		end
	end
	nowChanged()
end

function Hud.setNow(source: string, card: GuiObject?, priority: number)
	local old = nowOffers[source]
	if old and old.Card ~= card then
		old.Card.Parent = nil -- the caller owns its card: Hud only shows or hides it
	end
	if card then
		local rank = if type(priority) == "number" and priority == priority then priority else 0
		if old and old.Card == card then
			old.Priority = rank
		else
			nowSeq += 1
			nowOffers[source] = { Card = card, Priority = rank, Seq = nowSeq }
		end
	else
		nowOffers[source] = nil
	end
	syncNow()
end

------------------------------------------------------------------------------------------------------------------
-- Creature portraits: a friendly face from a Data `Look` (the same recipe CreatureBuilder uses in 3D)
------------------------------------------------------------------------------------------------------------------

-- Candy pop: every shape gets the dark Outline, like the rest of the UI.
local SILHOUETTE = Palette.InkSoft -- "not met yet"
local CHEEK = Kit.lighten(Palette.Candy.Pink, 0.3)
local PUPIL = Palette.Outline
local WHITE = Palette.White
local NO_BODY = Kit.lighten(Palette.Candy.Pink, 0.5) -- a Look without a body colour

type ShapeSpec = { W: number, H: number, Round: number }
local SHAPES: { [string]: ShapeSpec } = {
	Ball = { W = 0.74, H = 0.7, Round = 0.5 },
	Bean = { W = 0.6, H = 0.76, Round = 0.5 },
	Blob = { W = 0.84, H = 0.62, Round = 0.5 },
	Box = { W = 0.7, H = 0.64, Round = 0.24 },
	Drop = { W = 0.7, H = 0.68, Round = 0.5 },
}

local function hex(value: any, fallback: Color3): Color3
	if type(value) ~= "string" then
		return fallback
	end
	local ok, color = pcall(Color3.fromHex, value)
	return if ok then color else fallback
end

local function blob(
	parent: Instance,
	name: string,
	color: Color3,
	center: Vector2,
	size: Vector2,
	z: number,
	round: number?,
	rotation: number?
): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(center.X, center.Y)
	frame.Size = UDim2.fromScale(size.X, size.Y)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = z
	frame.Rotation = rotation or 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(round or 0.5, 0)
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

local function outline(frame: Frame)
	local stroke = Instance.new("UIStroke") -- uirules: allow StrokeBudget (the creature's drawn outline: art)
	stroke.Color = Palette.Outline
	stroke.Thickness = 2
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = frame
end

local function emoji(parent: Instance, text: string, center: Vector2, size: Vector2, z: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Top"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(center.X, center.Y)
	label.Size = UDim2.fromScale(size.X, size.Y)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Theme.Font
	label.ZIndex = z
	label.Parent = parent
	return label
end

local TOP_EMOJI: { [string]: { Text: string, Size: number, Dy: number, Dx: number } } = {
	Leaf = { Text = "🌱", Size = 0.3, Dy = -0.05, Dx = 0 },
	Bow = { Text = "🎀", Size = 0.26, Dy = 0.01, Dx = 0.18 },
	Cloud = { Text = "☁️", Size = 0.36, Dy = -0.03, Dx = 0 },
	Star = { Text = "⭐", Size = 0.28, Dy = -0.06, Dx = 0 }, -- uirules: allow TypedEmoji (a creature's top: art)
}

function Hud.lookOf(id: any): any
	if type(id) ~= "string" or id == "" or id == "Order" then
		return nil
	end
	local entry = rawget(PatientsData, id) or rawget(RegularsData, id)
	return if type(entry) == "table" then entry.Look else nil
end

function Hud.portrait(look: any, dark: boolean?): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Portrait"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = frame

	local l = if type(look) == "table" then look else {}
	local shape = SHAPES[l.Shape] or SHAPES.Ball
	local bodyColor = if dark then SILHOUETTE else hex(l.Body, NO_BODY)
	local accent = if dark then Kit.shade(SILHOUETTE, 0.15) else hex(l.Accent, WHITE)
	local cx, cy, w, h = 0.5, 0.6, shape.W, shape.H
	local top = cy - h / 2
	local left, right = cx - w / 2, cx + w / 2

	-- Behind the body (z 1): ears and extras.
	for _, side in { -1, 1 } do
		local ears = l.Ears
		if ears == "Round" then
			local ear =
				blob(frame, "Ear", bodyColor, Vector2.new(cx + side * w * 0.34, top + 0.03), Vector2.one * 0.22, 1)
			outline(ear)
			blob(ear, "Inner", accent, Vector2.new(0.5, 0.5), Vector2.one * 0.55, 1)
		elseif ears == "Floppy" then
			local ear = blob(
				frame,
				"Ear",
				accent,
				Vector2.new(if side < 0 then left + 0.02 else right - 0.02, top + h * 0.32),
				Vector2.new(0.17, 0.32),
				1,
				0.5,
				side * -18
			)
			outline(ear)
		elseif ears == "Pointy" then
			local ear = blob(
				frame,
				"Ear",
				bodyColor,
				Vector2.new(cx + side * w * 0.3, top + 0.05),
				Vector2.one * 0.2,
				1,
				0.18,
				45
			)
			outline(ear)
		elseif ears == "Long" then
			local ear = blob(
				frame,
				"Ear",
				bodyColor,
				Vector2.new(cx + side * 0.12, top - 0.05),
				Vector2.new(0.13, 0.36),
				1,
				0.5,
				side * 10
			)
			outline(ear)
			blob(ear, "Inner", accent, Vector2.new(0.5, 0.45), Vector2.new(0.5, 0.7), 1)
		elseif ears == "Tufts" then
			blob(frame, "Ear", accent, Vector2.new(cx + side * w * 0.34, top + 0.02), Vector2.one * 0.13, 1, 0.2, 45)
		end

		local extra = l.Extra
		if extra == "Wings" then
			local wing = blob(
				frame,
				"Wing",
				accent,
				Vector2.new(if side < 0 then left - 0.01 else right + 0.01, cy - 0.02),
				Vector2.new(0.2, 0.32),
				1,
				0.5,
				side * 28
			)
			outline(wing)
		elseif extra == "Flippers" then
			blob(
				frame,
				"Flipper",
				Kit.shade(bodyColor, 0.12),
				Vector2.new(if side < 0 then left + 0.01 else right - 0.01, cy + 0.08),
				Vector2.new(0.12, 0.26),
				1,
				0.5,
				side * -25
			)
		end
	end
	if l.Extra == "Tail" then
		local tail = blob(frame, "Tail", accent, Vector2.new(right + 0.02, cy + h * 0.25), Vector2.one * 0.17, 1)
		outline(tail)
	elseif l.Extra == "Spout" then
		local spout =
			blob(frame, "Spout", bodyColor, Vector2.new(right + 0.06, cy), Vector2.new(0.24, 0.11), 1, 0.5, -30)
		outline(spout)
	end
	if l.Shape == "Drop" then
		local tip = blob(frame, "Tip", bodyColor, Vector2.new(cx, top + 0.03), Vector2.one * 0.26, 1, 0.22, 45)
		outline(tip)
	end

	-- The body (z 2).
	local body = blob(frame, "Body", bodyColor, Vector2.new(cx, cy), Vector2.new(w, h), 2, shape.Round)
	outline(body)

	-- On the head (z 6).
	local topKind = l.Top
	local topEmoji = TOP_EMOJI[topKind]
	if topEmoji and not dark then
		emoji(frame, topEmoji.Text, Vector2.new(cx + topEmoji.Dx, top + topEmoji.Dy), Vector2.one * topEmoji.Size, 6)
	elseif topKind == "Antennae" then
		for _, side in { -1, 1 } do
			blob(
				frame,
				"Stalk",
				Kit.shade(bodyColor, 0.3),
				Vector2.new(cx + side * 0.1, top - 0.05),
				Vector2.new(0.025, 0.16),
				6,
				0.5,
				side * 22
			)
			blob(frame, "Bobble", accent, Vector2.new(cx + side * 0.14, top - 0.13), Vector2.one * 0.09, 6)
		end
	elseif topKind == "Crust" then
		blob(frame, "Crust", Kit.shade(bodyColor, 0.28), Vector2.new(cx, top + 0.04), Vector2.new(w * 1.02, 0.12), 6)
	elseif topKind == "Pleat" then
		for i = -1, 1 do
			blob(frame, "Pleat", accent, Vector2.new(cx + i * 0.08, top + 0.02), Vector2.one * 0.08, 6)
		end
	elseif topKind == "Scoop" then
		blob(frame, "Scoop", accent, Vector2.new(cx, top + 0.02), Vector2.new(w * 0.7, 0.22), 6)
	elseif topKind == "Lid" then
		blob(frame, "Lid", accent, Vector2.new(cx, top + 0.02), Vector2.new(w * 0.6, 0.1), 6)
		blob(frame, "Knob", accent, Vector2.new(cx, top - 0.05), Vector2.one * 0.09, 6)
	end

	if dark then
		local mystery = emoji(frame, "?", Vector2.new(cx, cy + 0.02), Vector2.one * 0.42, 7)
		mystery.Name = "Mystery"
		mystery.Font = Theme.DisplayFont
		mystery.TextColor3 = Theme.Colors.OnColor
		Kit.outline(mystery)
		return frame
	end

	-- The face (z 3-5): belly, big eyes, rosy cheeks and a happy mouth.
	blob(frame, "Belly", accent, Vector2.new(cx, cy + h * 0.2), Vector2.new(w * 0.56, h * 0.46), 3)
	for _, side in { -1, 1 } do
		local eye = blob(frame, "Eye", WHITE, Vector2.new(cx + side * w * 0.2, cy - h * 0.1), Vector2.one * 0.16, 4)
		local pupil = blob(eye, "Pupil", PUPIL, Vector2.new(0.55, 0.58), Vector2.one * 0.64, 4)
		blob(pupil, "Shine", WHITE, Vector2.new(0.32, 0.3), Vector2.one * 0.38, 4)
		local cheek =
			blob(frame, "Cheek", CHEEK, Vector2.new(cx + side * w * 0.33, cy + h * 0.06), Vector2.new(0.11, 0.07), 4)
		cheek.BackgroundTransparency = 0.35
	end
	local mouth = Instance.new("Frame")
	mouth.Name = "Mouth"
	mouth.AnchorPoint = Vector2.new(0.5, 0)
	mouth.Position = UDim2.fromScale(cx, cy + h * 0.02)
	mouth.Size = UDim2.fromScale(0.1, 0.05)
	mouth.BackgroundTransparency = 1
	mouth.ClipsDescendants = true -- only the bottom half of the circle shows: a smile
	mouth.ZIndex = 5
	mouth.Parent = frame
	blob(mouth, "Smile", PUPIL, Vector2.new(0.5, 0), Vector2.new(1, 2), 5)
	return frame
end

------------------------------------------------------------------------------------------------------------------
-- Flying icons: rewards visibly land in the wallet
------------------------------------------------------------------------------------------------------------------

local fxGui: ScreenGui? = nil
local targets: { [string]: GuiObject } = {}

function Hud.target(name: string): GuiObject?
	return targets[name]
end

local function fxLayer(): ScreenGui
	local layer = fxGui
	if not layer or not layer.Parent then
		layer = Kit.screen("HudFx", Theme.DisplayOrder.Fx)
		fxGui = layer
	end
	return layer :: ScreenGui
end

local function centreOf(gui: GuiObject, layer: ScreenGui): Vector2
	return gui.AbsolutePosition + gui.AbsoluteSize / 2 - layer.AbsolutePosition
end

-- A little outlined line that floats up off a HUD piece and fades ("×1.2 💰"). Nothing in calm mode.
local function floatText(anchor: GuiObject, text: string, color: Color3)
	if Hud.calm() then
		return
	end
	local layer = fxLayer()
	local at = centreOf(anchor, layer)
	local label = Kit.label({
		Name = "Float",
		Text = text,
		Outlined = true,
		TextSize = Theme.TextSize.Body,
		TextColor3 = color,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(at.X, at.Y),
		Size = UDim2.fromOffset(160, 34),
		ZIndex = 10,
		Parent = layer,
	})
	local stroke = Kit.outline(label, Theme.Size.Stroke)
	local rise = TweenService:Create(label, FLOAT_INFO, {
		Position = UDim2.fromOffset(at.X, at.Y - 44),
		TextTransparency = 1,
	})
	TweenService:Create(stroke, FLOAT_INFO, { Transparency = 1 }):Play()
	rise.Completed:Once(function()
		label:Destroy()
	end)
	rise:Play()
end

-- Each flying icon bursts out from where it starts, then arcs into its target on a curve (Kit.Juice.arc) that
-- follows the target if the HUD moves under it. One RenderStepped connection draws them all and lets go when the
-- last one lands.
type Flyer = {
	Label: TextLabel,
	Start: Vector2,
	Spread: Vector2,
	Bend: number, -- px the arc bows out sideways (either side)
	Target: string?,
	Born: number, -- os.clock() it launches (staggered)
	Spin: number,
	Batch: { Landed: boolean },
}
local BURST_SECONDS = 0.22
local FLY_SIZE = 36
local LAND_SIZE = 22
local flyers: { Flyer } = {}
local flyConnection: RBXScriptConnection? = nil
local arrivals: { [string]: number } = {} -- target -> os.clock() its first flying icon lands (counters wait)

local function goalPoint(name: string?, layer: ScreenGui): (GuiObject?, Vector2?)
	local gui = if name then targets[name] else nil
	if gui and Kit.isShown(gui) then
		return gui, centreOf(gui, layer)
	end
	return nil, nil
end

-- A world position on this screen, in the fx layer's pixels (nil when it's behind the camera).
local function screenPoint(position: Vector3, layer: ScreenGui): Vector2?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local point, _ = camera:WorldToScreenPoint(position)
	if point.Z <= 0 then
		return nil
	end
	return Vector2.new(point.X, point.Y) - layer.AbsolutePosition
end

local function stepFlyers()
	local layer = fxLayer()
	local now = os.clock()
	local trip = Theme.Juice.FlySeconds
	for index = #flyers, 1, -1 do
		local flyer = flyers[index]
		local label = flyer.Label
		local age = now - flyer.Born
		if age < 0 then
			label.Visible = false
		elseif age < BURST_SECONDS then
			local t = Kit.Juice.ease(age / BURST_SECONDS)
			local at = flyer.Start:Lerp(flyer.Spread, t)
			label.Visible = true
			label.Position = UDim2.fromOffset(at.X, at.Y)
			local px = FLY_SIZE * (0.4 + 0.6 * t)
			label.Size = UDim2.fromOffset(px, px)
		else
			local t = math.min((age - BURST_SECONDS) / trip, 1)
			local goalGui, goal = goalPoint(flyer.Target, layer)
			if goal then
				local eased = t * t -- speeds up into the wallet
				local mid = (flyer.Spread + goal) / 2
				local along = goal - flyer.Spread
				local side = if along.Magnitude > 0 then Vector2.new(-along.Y, along.X).Unit else Vector2.zero
				local control = mid + side * flyer.Bend - Vector2.new(0, 40)
				local x = Kit.Juice.arc(flyer.Spread.X, control.X, goal.X, eased)
				local y = Kit.Juice.arc(flyer.Spread.Y, control.Y, goal.Y, eased)
				label.Position = UDim2.fromOffset(x, y)
				local px = FLY_SIZE + (LAND_SIZE - FLY_SIZE) * eased
				label.Size = UDim2.fromOffset(px, px)
				label.Rotation = flyer.Spin * t
			else
				-- No target (or it's hidden): drift up and fade.
				label.Position = UDim2.fromOffset(flyer.Spread.X, flyer.Spread.Y - 60 * Kit.Juice.ease(t))
				label.TextTransparency = t
			end
			if t >= 1 then
				label:Destroy()
				table.remove(flyers, index)
				if goalGui then
					Hud.pop(goalGui, 1.12)
					Hud.sound(if flyer.Target == "Cash" then "Coin" else "Pop", if flyer.Batch.Landed then 0.6 else 1)
					flyer.Batch.Landed = true
				end
			end
		end
	end
	if #flyers == 0 and flyConnection then
		flyConnection:Disconnect()
		flyConnection = nil
	end
end

function Hud.fly(from: any, icon: string, target: string?, count: number?)
	local layer = fxLayer()
	local goalGui = if target then targets[target] else nil
	if Hud.calm() then
		Hud.pop(goalGui)
		return
	end
	local start: Vector2 = layer.AbsoluteSize / 2
	if typeof(from) == "Instance" and from:IsA("GuiObject") then
		start = centreOf(from, layer)
	elseif typeof(from) == "Vector3" then
		start = screenPoint(from, layer) or Vector2.new(layer.AbsoluteSize.X / 2, layer.AbsoluteSize.Y * 0.7)
	elseif typeof(from) == "Vector2" then
		start = from
	end
	local n = math.clamp(math.floor(count or 6), 1, 10)
	local now = os.clock()
	local batch = { Landed = false }
	local stagger = 0.05
	for i = 1, n do
		local label = Instance.new("TextLabel")
		label.Name = "Fly"
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromOffset(start.X, start.Y)
		label.Size = UDim2.fromOffset(FLY_SIZE * 0.4, FLY_SIZE * 0.4)
		label.BackgroundTransparency = 1
		label.Text = icon
		label.TextScaled = true
		label.Font = Theme.Font
		label.ZIndex = 10
		label.Visible = false
		label.Parent = layer

		local angle = (i / n) * math.pi * 2 + math.random() * 0.6
		local spread = start + Vector2.new(math.cos(angle), math.sin(angle)) * (34 + math.random() * 36)
		table.insert(flyers, {
			Label = label,
			Start = start,
			Spread = spread,
			Bend = (math.random() * 2 - 1) * 90,
			Target = if goalGui then target else nil,
			Born = now + (i - 1) * stagger,
			Spin = (math.random() * 2 - 1) * 180,
			Batch = batch,
		})
	end
	if goalGui and target then
		-- The counter on the target waits for the first icon to land.
		arrivals[target] = math.max(arrivals[target] or 0, now + BURST_SECONDS + Theme.Juice.FlySeconds)
	end
	if not flyConnection then
		flyConnection = RunService.RenderStepped:Connect(stepFlyers)
	end
end

------------------------------------------------------------------------------------------------------------------
-- Pieces of the screen
------------------------------------------------------------------------------------------------------------------

local WALLET_ICON = 40 -- a Now card's icon tile (px)
local LEVEL_LINE = 24 -- the level row's two text lines (the 8 px bar sits between them)
local LEVEL_BAR = 160 -- the level bar's width (px); LEVEL_BAR_PHONE in the top-bar row
local LEVEL_BAR_PHONE = 96
local LEVEL_POINT = 0.35 -- seconds after the Shop opens before its Level up button bounces
local HINT_EVERY = 2 -- seconds between looks at the waiting room (the "press Send" hint)
local NOW_CARD = 56 -- Hud's own Now cards (a warning, the tracked goal): one tappable row
local THROW_HOLD = 0.5 -- seconds to hold a hand's ✖ (throwing away can't be undone: Destructive, behind a hold)
local THROW_HINT_EVERY = 3 -- seconds between "hold it" hints

-- Shows or hides a zone. With motion it pops in and shrinks away (Kit.popIn / popOut: both honour reduced motion); a
-- zone shrinking away already counts as hidden (`leaving`), so the Now card's bottom and the toasts move at once.
local function zoneShow(frame: GuiObject, on: boolean, animate: boolean)
	if on then
		if frame.Visible and not leaving[frame] then
			return
		end
		local wasLeaving = leaving[frame] == true
		leaving[frame] = nil
		if animate or wasLeaving then
			Kit.popIn(frame) -- also cancels a shrink still running
		else
			frame.Visible = true
		end
	elseif frame.Visible and not leaving[frame] then
		if animate then
			leaving[frame] = true
			Kit.popOut(frame, function()
				leaving[frame] = nil
				nowChanged()
			end)
		else
			frame.Visible = false
		end
	end
end

-- A rail plate's icon and caption for this layout (Kit.iconButton's own spots, plus room for 🎁's bar).
local function placeFace(button: GuiObject, captions: boolean, bar: boolean)
	local icon = button:FindFirstChild("Icon")
	if icon and icon:IsA("GuiObject") then
		icon.AnchorPoint = Vector2.new(0.5, 0)
		if captions then
			icon.Position = UDim2.fromScale(0.5, if bar then 0.04 else 0.06)
			icon.Size = UDim2.fromScale(0.6, if bar then 0.52 else 0.56)
		else
			icon.Position = UDim2.fromScale(0.5, if bar then 0.12 else 0.2)
			icon.Size = UDim2.fromScale(0.6, 0.6)
		end
	end
	local caption = button:FindFirstChild("Caption")
	if caption and caption:IsA("GuiObject") then
		caption.Visible = captions
		caption.AnchorPoint = Vector2.new(0.5, 1)
		caption.Position = UDim2.fromScale(0.5, if bar then 0.86 else 0.98)
	end
end

local function roundCorner(gui: Instance)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.Radius.Round
	corner.Parent = gui
end

-- A thin bar: a dark track and a fill (its Size.X.Scale is the share done).
local function bar(parent: Instance, name: string, fillColor: Color3, track: Color3, trackAlpha: number): (Frame, Frame)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = track
	frame.BackgroundTransparency = trackAlpha
	frame.BorderSizePixel = 0
	roundCorner(frame)
	frame.Parent = parent
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	roundCorner(fill)
	fill.Parent = frame
	return frame, fill
end

local function fillTo(fill: Frame, ratio: number, animate: boolean)
	local target = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	if animate and not Hud.calm() then
		TweenService:Create(fill, Theme.Tween.Fill, { Size = target }):Play()
	else
		fill.Size = target
	end
end

-- Hud's own Now card: the navy plate (Theme.Colors.NowPlate) with the one shadow, a white icon tile and white
-- outlined words. A tappable one is a button.
local function nowCard(name: string, tappable: boolean): (Frame, GuiObject, TextLabel, TextLabel)
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, NOW_CARD)
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.Position = UDim2.fromOffset(Theme.Shadow.Offset.X, Theme.Shadow.Offset.Y)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.BackgroundColor3 = Theme.Shadow.Color
	shadow.BackgroundTransparency = Theme.Shadow.Transparency
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 1
	Kit.corner(shadow, Theme.Radius.Large)
	shadow.Parent = holder
	local plate: GuiObject
	if tappable then
		local button = Instance.new("TextButton")
		button.Text = ""
		button.AutoButtonColor = false
		plate = button
	else
		plate = Instance.new("Frame")
	end
	plate.Name = "Plate"
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = Theme.Colors.NowPlate
	plate.BorderSizePixel = 0
	plate.ZIndex = 2
	Kit.corner(plate, Theme.Radius.Large)
	Kit.stroke(plate, Theme.Colors.Stroke, Theme.Stroke.Bold) -- uirules: allow StrokeBudget (a plate over the world)
	plate.Parent = holder
	local tile = Instance.new("Frame")
	tile.Name = "Tile"
	tile.AnchorPoint = Vector2.new(0, 0.5)
	tile.Position = UDim2.new(0, Theme.Space.Step[2], 0.5, 0)
	tile.Size = UDim2.fromOffset(WALLET_ICON, WALLET_ICON)
	tile.BackgroundColor3 = Theme.Colors.Plate
	tile.BorderSizePixel = 0
	Kit.corner(tile, Theme.Radius.Medium)
	tile.Parent = plate
	local icon = Kit.label({
		Name = "Icon",
		Text = "",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.78, 0.78),
		Parent = tile,
	})
	local text = Kit.label({
		Name = "Text",
		Text = "",
		Outlined = true,
		Font = Theme.Font,
		TextScaled = true,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, WALLET_ICON + Theme.Space.Step[4], 0.5, 0),
		Size = UDim2.new(1, -(WALLET_ICON + Theme.Space.Step[5]), 0, 30),
		Parent = plate,
	})
	Kit.outline(text, Theme.Stroke.Text)
	Kit.textLimit(text, Theme.TextSize.Body)
	return holder, plate, icon, text
end

local function splitCarry(raw: any): { string }
	local items = {}
	if type(raw) == "string" then
		for id in string.gmatch(raw, "[^,]+") do
			table.insert(items, id)
		end
	end
	return items
end

export type DecorSlot = { Key: string, RoomId: string, N: number, Placed: string? }

-- Every decor slot in the rooms you own, in room order: "<RoomId>:<n>" plus what's in it now.
function Hud.decorSlots(data: any, state: Types.Snapshot): { DecorSlot }
	local slots: { DecorSlot } = {}
	local placed = (state.Decor and state.Decor.Placed) or {}
	for _, roomId in data.Rooms.Order do
		local room = data.Rooms[roomId]
		if state.Rooms and state.Rooms[roomId] == true then
			for n = 1, room.DecorSlots do
				local key = roomId .. ":" .. n
				local decorId = placed[key]
				table.insert(slots, { Key = key, RoomId = roomId, N = n, Placed = decorId })
			end
		end
	end
	return slots
end

-- What the 🛒 dot points at: a room you could buy right now (stars and cash both enough), or decor you own
-- that isn't placed while a slot is free (a fresh Book or story reward, say).
-- Progression v2 (Foundation hook; T8 restyles the dot): a perk card waiting, or tree points some node can take.
local function branchNews(data: any, state: Types.Snapshot): boolean
	local rebirth = (state :: any).Rebirth
	if type(rebirth) ~= "table" then
		return false
	end
	if type(rebirth.Offer) == "table" and #rebirth.Offer > 0 then
		return true
	end
	local points = if type(rebirth.Points) == "number" then rebirth.Points else 0
	local tree = if type(data.Tree) == "table" then data.Tree.Nodes else nil
	if points <= 0 or type(tree) ~= "table" or type(tree.Order) ~= "table" then
		return false
	end
	for _, nodeId in tree.Order do
		if TreeLogic.canBuy(rebirth.Tree, points, nodeId, tree) then
			return true
		end
	end
	return false
end

function Hud.shopNews(
	data: any,
	state: Types.Snapshot
): { Rooms: boolean, Decor: boolean, Hospital: boolean, Branch: boolean }
	local news = { Rooms = false, Decor = false, Hospital = false, Branch = false }
	if state.PlotIndex == nil then
		return news
	end
	news.Branch = branchNews(data, state)
	for _, roomId in data.Rooms.Order do
		local room = data.Rooms[roomId]
		-- The server's own rule (season, the hospital level a room needs, ⭐ and 💰), so the dot never lights for a
		-- room the Shop would refuse (the Garden below Lv 3).
		if room.Price > 0 and ProgressLogic.canBuyRoom(state, room, roomId, state.IsWinter == true) then
			news.Rooms = true
		end
	end
	if type(data.Levels) == "table" then
		news.Hospital = (LevelsLogic.canLevelUp(state, data.Levels))
	end
	local placedIds: { [string]: boolean } = {}
	local freeSlot = false
	for _, slot in Hud.decorSlots(data, state) do
		if slot.Placed then
			placedIds[slot.Placed] = true
		else
			freeSlot = true
		end
	end
	if freeSlot and state.Decor and state.Decor.Owned then
		for decorId, owned in state.Decor.Owned do
			if owned == true and not placedIds[decorId] and rawget(data.Decor, decorId) then
				news.Decor = true
			end
		end
	end
	return news
end

-- Calls a client -> server RemoteFunction safely and yields for the answer. Returns (ok, message); message may
-- be "". A server that errors, or doesn't answer within ASK_TIMEOUT seconds, counts as not ok (the call still
-- finishes in the background; the caller just stops waiting for it).
local ASK_TIMEOUT = 10
function Hud.ask(remote: RemoteFunction, ...: any): (boolean, string, any)
	local args = table.pack(...)
	local thread = coroutine.running()
	local done = false
	local function finish(ok: boolean, message: string, payload: any?)
		if not done then
			done = true
			task.spawn(thread, ok, message, payload)
		end
	end
	-- Deferred, so this thread is already waiting below even if the call fails at once.
	task.defer(function()
		local called, result, message, payload = pcall(function()
			return remote:InvokeServer(table.unpack(args, 1, args.n))
		end)
		if not called then
			finish(false, "Oops! Try again.")
		else
			finish(
				result == true,
				if type(message) == "string" then message else "",
				if type(payload) == "table" then payload else nil
			)
		end
	end)
	task.delay(ASK_TIMEOUT, function()
		finish(false, "Oops! Try again.")
	end)
	return coroutine.yield()
end

------------------------------------------------------------------------------------------------------------------
-- Time played and boosts, live (the Snapshot holds the saved part; Server/Playtime's attributes the rest)
------------------------------------------------------------------------------------------------------------------

local function numberAttribute(instance: Instance, name: string): number?
	local value = instance:GetAttribute(name)
	return if type(value) == "number" and value == value then value else nil
end

function Hud.livePlay(state: Types.Snapshot): (PlaytimeLogic.Save, number, number)
	local saved: any = state.Playtime
	if type(saved) ~= "table" then
		saved = { Day = 0, TodaySeconds = 0, TotalSeconds = 0, Claimed = {}, Rank = 0 }
	end
	local player = Players.LocalPlayer
	local day = numberAttribute(Workspace, "UtcDay") or saved.Day
	local total = numberAttribute(player, "PlayTotal") or saved.TotalSeconds or 0
	local liveToday = numberAttribute(player, "PlayToday")
	local sameDay = saved.Day == day
	local save: PlaytimeLogic.Save = {
		Day = day,
		TodaySeconds = liveToday or (if sameDay then saved.TodaySeconds or 0 else 0),
		TotalSeconds = math.max(total, saved.TotalSeconds or 0),
		Claimed = if sameDay and type(saved.Claimed) == "table" then saved.Claimed else {},
		Rank = saved.Rank or 0,
	}
	return save, day, math.max(0, total - (saved.TotalSeconds or 0))
end

function Hud.liveBoosts(state: Types.Snapshot): { { Id: string, Left: number } }
	local _, _, pending = Hud.livePlay(state)
	local out = {}
	local list = state.Boosts and state.Boosts.Timed
	if type(list) == "table" then
		for _, entry in list do
			local left = (if type(entry.Left) == "number" then entry.Left else 0) - pending
			if type(entry.Id) == "string" and left > 0 then
				table.insert(out, { Id = entry.Id, Left = left })
			end
		end
	end
	return out
end

function Hud.boostLine(data: any, state: Types.Snapshot): string
	local parts = {}
	for _, entry in Hud.liveBoosts(state) do
		local def = rawget(data.Boosts, entry.Id)
		if def then
			table.insert(parts, def.Icon .. " " .. PlaytimeLogic.clock(entry.Left))
		end
	end
	local permanent = state.Boosts and state.Boosts.Permanent
	if type(permanent) == "table" then
		for _, kind in BoostsLogic.KINDS do
			local percent = permanent[kind]
			if type(percent) == "number" and percent > 0 then
				table.insert(parts, (BoostsLogic.ICONS :: any)[kind] .. " +" .. math.floor(percent + 0.5) .. "%")
			end
		end
	end
	return if #parts > 0 then table.concat(parts, "  ") else Pure.TEXT.NoBoosts
end

local function goalReady(data: any, state: Types.Snapshot): boolean
	local goals = state.Daily and state.Daily.Goals
	if type(goals) ~= "table" then
		return false
	end
	for _, goal in goals do
		for _, def in data.DailyGoals do
			if def.Id == goal.Id and (goal.Progress or 0) >= def.Target then
				return true
			end
		end
	end
	return false
end

-- A number label that rolls to its new value (Kit.countUp: ticks, springs), and shows a floating "+n" (or "-n").
-- When icons are flying into it (Hud.fly to `target`), the roll waits for the first one to land, so the number
-- moves as the coins arrive. Changes while it waits add up into one roll and one "+n".
type Counter = { set: (value: number, animate: boolean) -> () }
local MAX_ARRIVAL_WAIT = 1.2
local function counter(holder: GuiObject, label: TextLabel, target: string): Counter
	label.Text = "0"
	label:SetAttribute("CountValue", 0)
	local shown = 0 -- the newest value we were given
	local pending = 0 -- change not yet shown as a "+n"
	local waiting = false

	local function floater(delta: number)
		local layer = fxLayer()
		local at = centreOf(holder, layer)
		local text = Kit.label({
			Name = "Delta",
			Text = (if delta > 0 then "+" else "-") .. Hud.format(math.abs(delta)),
			Outlined = true,
			TextSize = Theme.TextSize.Title,
			TextColor3 = if delta > 0 then Theme.Colors.Good else Theme.Colors.Danger,
			TextWrapped = false,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(at.X + holder.AbsoluteSize.X / 2 + 6, at.Y),
			Size = UDim2.fromOffset(150, 40),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 10,
			Parent = layer,
		})
		local stroke = Kit.outline(text, Theme.Size.Stroke)
		local rise = TweenService:Create(text, FLOAT_INFO, {
			Position = UDim2.fromOffset(at.X + holder.AbsoluteSize.X / 2 + 6, at.Y - 34),
			TextTransparency = 1,
		})
		TweenService:Create(stroke, FLOAT_INFO, { Transparency = 1 }):Play()
		rise.Completed:Once(function()
			text:Destroy()
		end)
		rise:Play()
	end

	local function roll()
		waiting = false
		local delta = pending
		pending = 0
		Kit.countUp(label, shown, Hud.format)
		if delta ~= 0 then
			floater(delta)
		end
	end

	return {
		set = function(newValue: number, animate: boolean)
			if newValue == shown then
				return
			end
			pending += newValue - shown
			shown = newValue
			if not animate or Hud.calm() then
				pending = 0
				Kit.countUp(label, newValue, Hud.format, 0)
				return
			end
			if waiting then
				return -- the roll already scheduled picks this up
			end
			local wait = math.clamp((arrivals[target] or 0) - os.clock(), 0, MAX_ARRIVAL_WAIT)
			if wait > 0.02 then
				waiting = true
				task.delay(wait, roll)
			else
				roll()
			end
		end,
	}
end

------------------------------------------------------------------------------------------------------------------
-- The HUD itself
------------------------------------------------------------------------------------------------------------------

function Hud.init(ctx: Types.Ctx)
	local data = ctx.Data :: any
	local player = ctx.Player
	fireBus = fireBus or ctx.fire
	-- Main.client hands every module the default snapshot first; the first one after it is the save loading in,
	-- so it is shown without "+n" floaters.
	local initial = ctx.State
	local gap = Theme.Space.Gap

	-- The zones live in a device-safe screen that includes the top-bar row, so Logic/HudZones' numbers (px from the
	-- screen's top left, the top bar included) are its offsets. The Now slot's screen (nowFrame) and UI/Toasts use
	-- the same insets.
	local gui = Kit.screen("Hud", Theme.DisplayOrder.Hud)
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	local layout: HudZones.Layout = HudZones.layout(gui.AbsoluteSize.X, gui.AbsoluteSize.Y, Hud.topbar())
	local box = Pure.statusBox(layout, gui.AbsoluteSize.X)

	--------------------------------------------------------------------------------------------------------------
	-- System: the top-bar row, beside Roblox's own buttons (⚙️; on phones the wallet too)
	--------------------------------------------------------------------------------------------------------------
	local system = Kit.screen("HudSystem", Theme.DisplayOrder.Hud)
	system.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
	local systemRow = Instance.new("Frame")
	systemRow.Name = "Row"
	systemRow.BackgroundTransparency = 1
	systemRow.Size = UDim2.fromScale(1, 1)
	systemRow.Parent = system
	local systemList = Kit.list(systemRow, Enum.FillDirection.Horizontal, Theme.Space.Step[3])
	systemList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local systemPad = Instance.new("UIPadding")
	systemPad.PaddingLeft = UDim.new(0, Theme.Space.Step[1])
	systemPad.Parent = systemRow

	local settingsButton = Kit.iconButton({
		Name = "Settings",
		Icon = Icons.Door.Settings,
		Glass = true,
		LayoutOrder = 1,
		Size = UDim2.fromOffset(Theme.Size.ButtonHeight, Theme.Size.ButtonHeight),
		Parent = systemRow,
	})
	local glassCorner = settingsButton:FindFirstChildOfClass("UICorner")
	if glassCorner then
		glassCorner.CornerRadius = Theme.Radius.Round -- round like Roblox's own top-bar buttons
	end
	targets.Settings = settingsButton

	--------------------------------------------------------------------------------------------------------------
	-- Wallet: 💰, ⭐ and the hospital level. Each is a Unit glued to its number (Kit.unit: the emoji and the number
	-- are two labels, because an emoji can't take the number's outline). No pills
	--------------------------------------------------------------------------------------------------------------
	local wallet = Instance.new("Frame")
	wallet.Name = "Wallet"
	wallet.BackgroundTransparency = 1
	wallet.Size = UDim2.new()
	wallet.AutomaticSize = Enum.AutomaticSize.XY
	wallet.LayoutOrder = 2
	wallet.Parent = gui
	local walletList = Kit.list(wallet, Enum.FillDirection.Vertical, HudZones.WALLET_GAP)
	walletList.HorizontalAlignment = Enum.HorizontalAlignment.Left

	local function walletUnit(name: string, icon: string, order: number): (Frame, TextLabel)
		local row, amount = Kit.unit({
			Name = name,
			Icon = icon,
			Voice = "Loud",
			Px = Theme.TextSize.Number,
			LayoutOrder = order,
			Parent = wallet,
		})
		amount.Text = "0"
		row.Size = UDim2.fromOffset(0, HudZones.WALLET_ROW)
		return row, amount
	end

	local cashRow, cashText = walletUnit("Cash", Icons.Unit.Cash, 1)
	targets.Cash = cashRow
	local cash = counter(cashRow, cashText, "Cash")

	-- The mini-game combo: a tilted 🔥 sticker after the cash (Perfects in a row multiply tips). Orange, then pink,
	-- purple and gold at each Config.MiniGame.Combo step. Display only: the server owns the combo.
	local COMBO_COLORS = { Theme.Colors.Primary, Theme.Colors.Pink, Theme.Colors.Purple, Theme.Colors.Cash }
	local comboSticker = Kit.label({
		Name = "Combo",
		Text = "",
		Outlined = true,
		TextScaled = true,
		TextWrapped = false,
		BackgroundColor3 = Theme.Colors.Primary,
		BackgroundTransparency = 0,
		Size = UDim2.fromOffset(58, 30),
		Rotation = 8,
		Visible = false,
		LayoutOrder = 3,
		Parent = cashRow,
	})
	Kit.corner(comboSticker, Theme.Radius.Small)
	Kit.stroke(comboSticker, Theme.Colors.Stroke, Theme.Stroke.Fine) -- uirules: allow StrokeBudget (a sticker over the world)
	Kit.textLimit(comboSticker, Theme.TextSize.Body)

	-- ⭐: the count. (Its old thin bar followed star milestones and said all was unlocked while the next level
	-- still had to be bought: the level row below is the ONE bar now.)
	local starsRow, starsText = walletUnit("Stars", Icons.Unit.Stars, 2)
	starsRow.Visible = false
	targets.Stars = starsRow
	local stars = counter(starsRow, starsText, "Stars")

	-- 🏥 The hospital level and the ONE bar toward the next one (Joshua, 2026-11-17: "is there a level up bar. where
	-- to see my level?"; Logic/LevelBar). "Lv 1 Clinic", the navy bar that counts both the ⭐ and the 💰 the next
	-- level needs, and under it what is still needed ("⭐ 12/15" "💰 300/400": two Units) or "Level up!". The whole
	-- row is ONE tap target: ready = the Shop opens on its Hospital tab and the Level up button bounces; not ready
	-- = a toast says what the next level is and needs. In-game cash only: nothing here costs real money.
	local levelButton = Instance.new("TextButton")
	levelButton.Name = "Level"
	levelButton.Text = ""
	levelButton.AutoButtonColor = false
	levelButton.BackgroundTransparency = 1
	levelButton.LayoutOrder = 3
	levelButton.Size = UDim2.fromOffset(0, HudZones.LEVEL_ROW)
	levelButton.AutomaticSize = Enum.AutomaticSize.X
	levelButton.Visible = false
	levelButton.Parent = wallet
	local levelList = Kit.list(levelButton, Enum.FillDirection.Vertical, Theme.Space.Tight)
	levelList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local function levelUnit(name: string, icon: string, order: number, parent: Instance): (Frame, TextLabel)
		local row, amount = Kit.unit({
			Name = name,
			Icon = icon,
			Voice = "Loud",
			Px = Theme.TextSize.Caption,
			LayoutOrder = order,
			Parent = parent,
		})
		row.Size = UDim2.fromOffset(0, LEVEL_LINE)
		return row, amount
	end
	local levelBadge, levelText = levelUnit("Badge", Icons.Unit.Level, 1, levelButton)
	levelText.TextTruncate = Enum.TextTruncate.AtEnd
	local levelLimit = Instance.new("UISizeConstraint") -- "Lv 4 General Hospital" never passes the wallet's column
	levelLimit.MaxSize = Vector2.new(HudZones.WALLET_WIDTH - LEVEL_LINE - Theme.Space.Tight, LEVEL_LINE)
	levelLimit.Parent = levelText
	local levelBar, setLevelBar = Kit.bar({
		Name = "Bar",
		Size = UDim2.fromOffset(LEVEL_BAR, Theme.Calm.Bar),
		LayoutOrder = 2,
		Parent = levelButton,
	})
	Kit.stroke(levelBar, Theme.Colors.Stroke, Theme.Stroke.Fine) -- uirules: allow StrokeBudget (a bar over the world)
	local levelNeeds = Instance.new("Frame")
	levelNeeds.Name = "Needs"
	levelNeeds.BackgroundTransparency = 1
	levelNeeds.LayoutOrder = 3
	levelNeeds.Size = UDim2.fromOffset(0, LEVEL_LINE)
	levelNeeds.AutomaticSize = Enum.AutomaticSize.X
	levelNeeds.Parent = levelButton
	local needsList = Kit.list(levelNeeds, Enum.FillDirection.Horizontal, Theme.Space.Line)
	needsList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local _, needStars = levelUnit("Stars", Icons.Unit.Stars, 1, levelNeeds)
	local _, needCash = levelUnit("Cash", Icons.Unit.Cash, 2, levelNeeds)
	local levelReady = Kit.label({
		Name = "Ready",
		Text = "",
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, LEVEL_LINE),
		LayoutOrder = 4,
		Visible = false,
		Parent = levelButton,
	})
	Kit.voice(levelReady, "Loud")
	levelReady.TextSize = Theme.TextSize.Caption
	targets.Level = levelButton
	local levelView: LevelBar.View? = nil
	local levelHintUsed = false -- the Now card's first level-up pointer: once a session

	--------------------------------------------------------------------------------------------------------------
	-- Status: top right, read-only
	--------------------------------------------------------------------------------------------------------------
	local statusZone = Instance.new("Frame")
	statusZone.Name = "Status"
	statusZone.AnchorPoint = Vector2.new(1, 0)
	statusZone.BackgroundTransparency = 1
	statusZone.AutomaticSize = Enum.AutomaticSize.Y
	statusZone.Parent = gui
	local statusColumn = Instance.new("Frame") -- the reveal shows its rows one by one; the hide rules pop the zone
	statusColumn.Name = "Column"
	statusColumn.BackgroundTransparency = 1
	statusColumn.Size = UDim2.fromScale(1, 0)
	statusColumn.AutomaticSize = Enum.AutomaticSize.Y
	statusColumn.Parent = statusZone
	local statusList = Kit.list(statusColumn, Enum.FillDirection.Vertical, Pure.ROW_GAP)
	statusList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	statusList.VerticalAlignment = Enum.VerticalAlignment.Top

	type Line = { Chip: Frame, Text: TextLabel, Limit: UISizeConstraint, Shown: string, Room: number }
	local statusRows: { [string]: Frame } = {}
	local function statusRow(name: string, order: number): Frame
		local row = Instance.new("Frame")
		row.Name = name
		row.LayoutOrder = order
		row.BackgroundTransparency = 1
		row.Size = UDim2.fromOffset(0, Pure.ROW)
		row.AutomaticSize = Enum.AutomaticSize.X
		row.Visible = false
		row.Parent = statusColumn
		local list = Kit.list(row, Enum.FillDirection.Horizontal, Theme.Space.Step[1])
		list.HorizontalAlignment = Enum.HorizontalAlignment.Right
		statusRows[name] = row
		return row
	end
	-- A line of words, on a chip: bare outlined white words over the world, or ink on a coloured chip (paint).
	local function line(row: Frame, order: number, outlined: boolean): Line
		local chip = Instance.new("Frame")
		chip.Name = "Chip"
		chip.LayoutOrder = order
		chip.BackgroundTransparency = 1
		chip.BorderSizePixel = 0
		chip.Size = UDim2.fromOffset(0, Pure.ROW)
		chip.AutomaticSize = Enum.AutomaticSize.X
		Kit.corner(chip, Theme.Radius.Small)
		local stroke = Kit.stroke(chip, Theme.Colors.Stroke, Theme.Stroke.Fine) -- uirules: allow StrokeBudget (a chip over the world)
		stroke.Enabled = false
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, Theme.Space.Step[2])
		pad.PaddingRight = UDim.new(0, Theme.Space.Step[2])
		pad.Parent = chip
		chip.Parent = row
		local text = Kit.label({
			Name = "Text",
			Text = "",
			Outlined = outlined,
			Font = Theme.Font,
			TextSize = Theme.TextSize.Body,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, Pure.ROW),
			Parent = chip,
		})
		if outlined then
			Kit.outline(text, Theme.Stroke.Text)
		end
		local limit = Instance.new("UISizeConstraint")
		limit.Parent = text
		return { Chip = chip, Text = text, Limit = limit, Shown = "", Room = -1 }
	end
	-- A coloured chip (the night or the event: the HUD's few saturated fills) or a bare one.
	local function paint(entry: Line, color: Color3?)
		entry.Chip.BackgroundTransparency = if color then 0 else 1
		if color then
			entry.Chip.BackgroundColor3 = color
		end
		local stroke = entry.Chip:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = color ~= nil
		end
	end
	-- Sets a line's words, as big as fit `room` px (Body, else the Caption floor; past that it trims with "…").
	local function setLine(entry: Line, text: string, room: number, compact: boolean)
		if entry.Shown == text and entry.Room == room then
			return
		end
		entry.Shown, entry.Room = text, room
		entry.Text.Text = text
		local size = if compact then Theme.TextSize.Caption else Theme.TextSize.Body
		if not compact then
			local ok, bounds = pcall(function()
				return TextService:GetTextSize(text, size, entry.Text.Font, Vector2.new(4000, Pure.ROW))
			end)
			if ok and bounds.X > room then
				size = Theme.TextSize.Caption
			end
		end
		entry.Text.TextSize = size
		entry.Limit.MaxSize = Vector2.new(math.max(room, 1), Pure.ROW)
	end

	local clockLine = line(statusRow("Clock", 1), 1, true)
	local eventLine = line(statusRow("Event", 2), 1, false)
	local visitorRow = statusRow("Visitor", 3)
	local faceDisc = Instance.new("Frame") -- a white outlined disc, so any creature colour reads
	faceDisc.Name = "Face"
	faceDisc.LayoutOrder = 1
	faceDisc.Size = UDim2.fromOffset(Pure.ROW, Pure.ROW)
	faceDisc.BackgroundColor3 = Theme.Colors.Plate
	faceDisc.BorderSizePixel = 0
	local function faceRing()
		roundCorner(faceDisc)
		Kit.stroke(faceDisc, Theme.Colors.Stroke, Theme.Stroke.Fine) -- uirules: allow StrokeBudget (a disc over the world)
	end
	faceRing()
	faceDisc.Parent = visitorRow
	local visitorLine = line(visitorRow, 2, true)
	local boostRow = statusRow("Boosts", 4)
	boostRow.Size = UDim2.new()
	boostRow.AutomaticSize = Enum.AutomaticSize.XY
	local boostList = boostRow:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	boostList.Padding = UDim.new(0, Pure.ROW_GAP)
	local boostChips: { [string]: Line } = {}
	local shownVisitor = ""

	--------------------------------------------------------------------------------------------------------------
	-- The rails: one white Icon plate per piece, in fixed slots
	--------------------------------------------------------------------------------------------------------------
	local leftZone = Instance.new("Frame")
	leftZone.Name = "LeftRail"
	leftZone.AnchorPoint = Vector2.new(0, 0.5)
	leftZone.BackgroundTransparency = 1
	leftZone.Parent = gui
	local rightZone = Instance.new("Frame")
	rightZone.Name = "RightRail"
	rightZone.AnchorPoint = Vector2.new(1, 0.5)
	rightZone.BackgroundTransparency = 1
	rightZone.Parent = gui

	local buttons: { [string]: TextButton } = {}
	local shopTab: string? = nil -- the Shop opens on the tab its dot is about
	local function addRail(zone: Frame, order: { string })
		for _, name in order do
			local face = Pure.RAIL[name]
			local button = Kit.iconButton({
				Name = name,
				Icon = face.Icon,
				Caption = face.Caption,
				Kind = Pure.RAIL_KIND,
				Visible = false,
				Parent = zone,
			})
			button.Activated:Connect(function()
				if name == "Shop" then
					-- The tutorial's shop step points at the cheapest upgrade, so it opens on Upgrades.
					local tutorial = TutorialLogic.active(ctx.State.Tutorial)
					ctx.fire("Open", name, if tutorial then "Upgrades" else shopTab)
				else
					ctx.fire("Open", name)
				end
			end)
			buttons[name] = button
			targets[name] = button
		end
	end
	addRail(leftZone, HudZones.ORDER.LeftRail)
	addRail(rightZone, HudZones.ORDER.RightRail)

	-- 🎁's bar fills inside its plate toward the next play gift (UI/PlayGifts opens on "Open" "Gifts"): navy like
	-- every progress bar, green once a gift is ready to collect. It isn't a countdown to anything you could miss:
	-- the gifts wait.
	local giftButton = buttons.Gifts
	local giftBar, giftFill = bar(giftButton, "GiftBar", Theme.Colors.Progress, Theme.Colors.Track, 0)
	giftBar.AnchorPoint = Vector2.new(0.5, 1)
	giftBar.Position = UDim2.new(0.5, 0, 1, -5)
	giftBar.Size = UDim2.new(1, -18, 0, 6)
	giftBar.ZIndex = 2
	giftFill.ZIndex = 2

	--------------------------------------------------------------------------------------------------------------
	-- Bottom centre: your hands
	--------------------------------------------------------------------------------------------------------------
	local handsZone = Instance.new("Frame")
	handsZone.Name = "HandsZone"
	handsZone.AnchorPoint = Vector2.new(0.5, 1)
	handsZone.BackgroundTransparency = 1
	handsZone.Size = UDim2.new()
	handsZone.AutomaticSize = Enum.AutomaticSize.XY
	handsZone.Parent = gui
	local hands = Instance.new("Frame")
	hands.Name = "Hands"
	hands.BackgroundTransparency = 1
	hands.Size = UDim2.fromOffset(0, Pure.HAND.Max)
	hands.AutomaticSize = Enum.AutomaticSize.X
	hands.Visible = false
	hands.Parent = handsZone
	Kit.list(hands, Enum.FillDirection.Horizontal, Pure.HAND.Gap)
	targets.Hands = hands

	-- Each hand: a disc with what you hold, ringed in the colour of the station that made it, and a red ✖ (top right)
	-- you HOLD to throw it away (the Discard remote), so an unneeded item never leaves you stuck and a stray tap never
	-- costs one. Only what you hold shows: empty hands draw nothing (first-session declutter, design §A5).
	local slots: { Frame } = {}
	local lastItems: { string } = {}
	local hintedAt = -math.huge
	local function slot(index: number): Frame
		local frame = Instance.new("Frame")
		frame.Name = "Hand" .. index
		frame.LayoutOrder = index
		frame.Size = UDim2.fromOffset(Pure.HAND.Max, Pure.HAND.Max)
		frame.BorderSizePixel = 0
		roundCorner(frame)
		Kit.stroke(frame, Theme.Colors.Stroke, Theme.Stroke.Bold).Name = "Outline" -- uirules: allow StrokeBudget (a plate over the world)
		local plate = Instance.new("Frame") -- the white middle
		plate.Name = "Plate"
		plate.AnchorPoint = Vector2.new(0.5, 0.5)
		plate.Position = UDim2.fromScale(0.5, 0.5)
		plate.Size = UDim2.fromScale(0.78, 0.78)
		plate.BackgroundColor3 = Theme.Colors.Plate
		plate.BorderSizePixel = 0
		roundCorner(plate)
		plate.Parent = frame
		Kit.label({
			Name = "Icon",
			Text = "",
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.62, 0.62),
			ZIndex = 2,
			Parent = frame,
		})
		-- The ✖: a 56 px hit area round a small red disc (the band of the hold fills the disc).
		local throw = Instance.new("TextButton")
		throw.Name = "Discard"
		throw.Text = ""
		throw.AutoButtonColor = false
		throw.BackgroundTransparency = 1
		throw.AnchorPoint = Vector2.new(0.5, 0.5)
		throw.Position = UDim2.fromScale(0.86, 0.14)
		throw.Size = UDim2.fromOffset(Theme.Size.ButtonHeight, Theme.Size.ButtonHeight)
		throw.ZIndex = 3
		throw.Parent = frame
		local disc = Instance.new("Frame")
		disc.Name = "Disc"
		disc.AnchorPoint = Vector2.new(0.5, 0.5)
		disc.Position = UDim2.fromScale(0.5, 0.5)
		disc.Size = UDim2.fromOffset(36, 36)
		disc.BackgroundColor3 = Theme.Colors.Destructive
		disc.BorderSizePixel = 0
		disc.ClipsDescendants = true
		disc.ZIndex = 3
		roundCorner(disc)
		Kit.stroke(disc, Theme.Colors.Stroke, Theme.Stroke.Bold) -- uirules: allow StrokeBudget (a candy button over the world)
		disc.Parent = throw
		local cross = Kit.label({
			Name = "Cross",
			Text = Icons.Mark.Close,
			Outlined = true,
			TextSize = Theme.TextSize.Body,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
			Parent = disc,
		})
		cross.TextWrapped = false
		local busy = false
		local thrownAt = -math.huge
		Kit.holdButton(throw, THROW_HOLD, function()
			local itemId = lastItems[index]
			if busy or not itemId then
				return
			end
			busy = true
			thrownAt = os.clock()
			Hud.pop(frame, 0.8)
			task.spawn(function()
				Hud.ask(ctx.Remotes.Discard, itemId)
				busy = false
			end)
		end)
		-- The hold's band fills the red disc, not the bare hit area.
		local band = throw:FindFirstChild("HoldFill")
		if band and band:IsA("GuiObject") then
			band.ZIndex = 4
			band.Parent = disc
			local bandCorner = band:FindFirstChildOfClass("UICorner")
			if bandCorner then
				bandCorner.CornerRadius = Theme.Radius.Round
			end
		end
		throw.Activated:Connect(function()
			Kit.Clicked:Fire(throw)
			local now = os.clock()
			-- A tap (not a hold): say how, now and then.
			if now - thrownAt > 0.4 and now - hintedAt > THROW_HINT_EVERY then
				hintedAt = now
				ctx.toast(Pure.TEXT.Throw)
			end
		end)
		frame.Parent = hands
		return frame
	end

	local function renderHands()
		local items = splitCarry(player:GetAttribute("Carry"))
		local count = math.min(#items, 8)
		hands.Visible = count > 0
		while #slots < count do
			table.insert(slots, slot(#slots + 1))
		end
		while #slots > count do
			(table.remove(slots) :: Frame):Destroy()
		end
		local side = Pure.handSize(gui.AbsoluteSize.X, count)
		hands.Size = UDim2.fromOffset(0, side)
		for index, frame in slots do
			frame.Size = UDim2.fromOffset(side, side)
			local itemId = items[index]
			local item = itemId and rawget(data.Items, itemId)
			local icon = frame:FindFirstChild("Icon") :: TextLabel
			local throw = frame:FindFirstChild("Discard") :: TextButton
			if item then
				local station = data.Stations[item.Station]
				icon.Text = item.Icon
				frame.BackgroundColor3 = if station then station.Color else Theme.Colors.Secondary
				throw.Visible = true
				if lastItems[index] ~= itemId then
					Hud.pop(frame, 1.35)
				end
			else
				icon.Text = ""
				frame.BackgroundColor3 = Theme.Colors.Plate
				throw.Visible = false
			end
		end
		lastItems = items
	end
	player:GetAttributeChangedSignal("Carry"):Connect(renderHands)

	--------------------------------------------------------------------------------------------------------------
	-- ⚙️ Settings: the switches (Music, Effects, Mini-games, and the owner's "Anyone can help"), then the Quiet links
	-- (Skip / Replay tutorial, the doors that are off the rail, Admin). Music.client follows MusicMuted and
	-- Feel/Atmosphere follows ReduceEffects, as before.
	--------------------------------------------------------------------------------------------------------------
	local settings = Hud.modal(ctx, {
		Name = "Settings",
		Title = "Settings",
		MaxSize = Vector2.new(460, 520),
	})
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = Theme.Space.Step[2]
	scroll.ScrollBarImageColor3 = Theme.Colors.InkSoft
	scroll.Parent = settings.Body
	local grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.CellPadding = UDim2.fromOffset(gap, gap)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	grid.CellSize = UDim2.new(1, -Theme.Space.Step[3], 0, Theme.Size.ButtonHeight)
	grid.Parent = scroll
	local gridPad = Instance.new("UIPadding")
	gridPad.PaddingTop = UDim.new(0, Theme.Space.Step[1])
	gridPad.PaddingBottom = UDim.new(0, Theme.Space.Step[1])
	gridPad.PaddingLeft = UDim.new(0, Theme.Space.Step[1])
	gridPad.Parent = scroll

	-- One list (UI direction §4 #5): a Toggle row (Kit.toggle: a fixed label and a switch) or a Link (a Quiet text
	-- button), as Pure.SETTINGS says. No label changes its words with state; no row has an outline.
	local rows: { [string]: TextButton } = {}
	local switches: { [string]: (on: boolean, instant: boolean?) -> () } = {}
	local function settingsRow(name: string, link: string?): TextButton
		local spec = Pure.SETTINGS[name]
		local button: TextButton
		if spec and spec.Kind == "Toggle" then
			local row, set = Kit.toggle({ Name = name, Label = spec.Label, Visible = false, Parent = scroll })
			switches[name] = set
			button = row
		else
			button = Kit.button({
				Name = name,
				Kind = "Quiet",
				Text = link or (if spec then spec.Label else name),
				TextScaled = true,
				Visible = false,
				Parent = scroll,
			})
			Kit.textLimit(button, Theme.TextSize.Body)
		end
		rows[name] = button
		return button
	end
	local musicSwitch = settingsRow("Music")
	local effectsSwitch = settingsRow("Effects")
	local simpleSwitch = settingsRow("Simple") -- depth update: Simple mode (saved; the server rates it)
	local helpersSwitch = settingsRow("Helpers")
	local skipRow = settingsRow("Skip")
	local replayRow = settingsRow("Replay")
	for piece, text in Pure.MORE do
		local row = settingsRow(piece, text)
		row.Activated:Connect(function()
			ctx.fire("Open", piece) -- a Panel: opening it closes ⚙️
		end)
	end
	local adminButton = settingsRow("Admin")
	settings.Focus = musicSwitch

	-- Two columns when one column of rows would need scrolling and the card is wide enough.
	local function fitSettings()
		local count = 0
		for _, row in rows do
			if row.Visible then
				count += 1
			end
		end
		local body = settings.Body.AbsoluteSize
		local cell = Theme.Size.ButtonHeight
		local tall = count * (cell + gap) > body.Y
		local twoColumns = tall and body.X >= 340
		grid.CellSize = if twoColumns
			then UDim2.new(0.5, -(gap + Theme.Space.Step[2]), 0, cell)
			else UDim2.new(1, -Theme.Space.Step[3], 0, cell)
	end
	settings.Body:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitSettings)

	-- Who may work at your clinic: only while you own one. "Anyone can help" off = only you and your Roblox friends
	-- may work at your clinic. The switch shows your plot's OpenHelpers attribute; a tap asks the server
	-- (SetHelpers, Server/Visits), which checks you own the plot, switches it and toasts.
	local function myClinic(): Model?
		local index = player:GetAttribute("PlotIndex")
		local clinics = Workspace:FindFirstChild("Clinics")
		local plot = if type(index) == "number" and clinics then clinics:FindFirstChild("Plot_" .. index) else nil
		return if plot and plot:IsA("Model") then plot else nil
	end

	-- Revealed pieces (the first-session reveal) and the HUD's layout decide which rows show.
	local shown: { [string]: boolean } = {}
	local function renderRows()
		local state = ctx.State
		local more: { string } = {}
		for _, piece in layout.More do
			if shown[piece] then
				table.insert(more, piece)
			end
		end
		local order =
			Pure.settingsRows(state.Tutorial, state.PlotIndex ~= nil, player:GetAttribute("IsAdmin") == true, more)
		for name, row in rows do
			local index = table.find(order, name)
			row.Visible = index ~= nil and (name ~= "Helpers" or myClinic() ~= nil)
			row.LayoutOrder = index or 0
		end
		fitSettings()
	end

	local function renderHelpers()
		local plot = myClinic()
		local open = plot ~= nil and plot:GetAttribute("OpenHelpers") == true
		switches.Helpers(open)
		renderRows()
	end
	local helpersWatch: RBXScriptConnection? = nil
	local function watchHelpers()
		if helpersWatch then
			helpersWatch:Disconnect()
			helpersWatch = nil
		end
		local plot = myClinic()
		if plot then
			helpersWatch = plot:GetAttributeChangedSignal("OpenHelpers"):Connect(renderHelpers)
		end
		renderHelpers()
	end
	player:GetAttributeChangedSignal("PlotIndex"):Connect(watchHelpers)
	task.spawn(function()
		if Workspace:WaitForChild("Clinics", 30) then -- the town may arrive after the HUD
			watchHelpers()
		end
	end)
	local helpersBusy = false
	helpersSwitch.Activated:Connect(function()
		local plot = myClinic()
		if helpersBusy or not plot then
			return
		end
		helpersBusy = true
		local ok, message = Hud.ask(ctx.Remotes.SetHelpers, plot:GetAttribute("OpenHelpers") ~= true)
		helpersBusy = false
		if not ok then
			Hud.shake(helpersSwitch)
			if message ~= "" then
				ctx.toast(message)
			end
		end
		renderHelpers()
	end)

	local function calmOn(): boolean
		local value = player:GetAttribute("ReduceEffects")
		return if value == nil then Kit.reducedMotion() else value == true
	end
	local function renderSettings()
		switches.Music(player:GetAttribute("MusicMuted") ~= true)
		switches.Effects(not calmOn())
		switches.Simple(ctx.State.Simple ~= true)
		renderRows()
	end
	musicSwitch.Activated:Connect(function()
		player:SetAttribute("MusicMuted", player:GetAttribute("MusicMuted") ~= true)
	end)
	effectsSwitch.Activated:Connect(function()
		player:SetAttribute("ReduceEffects", not calmOn())
	end)
	local askingSimple = false
	simpleSwitch.Activated:Connect(function()
		if askingSimple then
			return
		end
		askingSimple = true
		local ok, message = Hud.ask(ctx.Remotes.SetSimple, ctx.State.Simple ~= true)
		askingSimple = false
		if not ok and message ~= "" then
			ctx.toast(message)
		end
	end)
	-- ⏭️ / 🔁: ⚙️ closes and UI/Tutorial takes over (its confirm, then the TutorialSkip / TutorialReplay remote).
	skipRow.Activated:Connect(function()
		settings.close()
		ctx.fire("SkipTutorial")
	end)
	replayRow.Activated:Connect(function()
		settings.close()
		ctx.fire("ReplayTutorial")
	end)
	-- 🛠️ Admin: only for the accounts the server marks IsAdmin (Server/Admin). It just opens UI/AdminPanel, whose
	-- every button the server checks again.
	adminButton.Activated:Connect(function()
		if player:GetAttribute("IsAdmin") == true then
			ctx.fire("Open", "Admin") -- a Panel: opening it closes ⚙️
		end
	end)
	player:GetAttributeChangedSignal("IsAdmin"):Connect(renderRows)
	player:GetAttributeChangedSignal("MusicMuted"):Connect(renderSettings)
	player:GetAttributeChangedSignal("ReduceEffects"):Connect(renderSettings)
	settingsButton.Activated:Connect(function()
		renderSettings()
		watchHelpers() -- in case your clinic streamed in since
		settings.toggle()
	end)

	--------------------------------------------------------------------------------------------------------------
	-- The Now card's own entries: the warnings (30), the one hint (15) and the tracked goal (10)
	--------------------------------------------------------------------------------------------------------------
	local warnCard, _, warnIcon, warnText = nowCard("Warning", false)
	local goalCard, goalPlate, goalIcon, goalText = nowCard("Goal", true)
	goalText.AnchorPoint = Vector2.new(0, 0)
	goalText.Position = UDim2.fromOffset(WALLET_ICON + Theme.Space.Step[4], Theme.Space.Step[1])
	goalText.Size = UDim2.new(1, -(WALLET_ICON + Theme.Space.Step[5]), 0, 30)
	-- On the navy plate the fill is white: progress is never green (green = collect, ready, go).
	local goalTrack, goalFill = bar(goalPlate, "Bar", Theme.Colors.Paper, Theme.Colors.Shade, 0.4)
	goalTrack.AnchorPoint = Vector2.new(0, 1)
	goalTrack.Position = UDim2.new(0, WALLET_ICON + Theme.Space.Step[4], 1, -Theme.Space.Step[2])
	goalTrack.Size = UDim2.new(1, -(WALLET_ICON + Theme.Space.Step[5] + Theme.Space.Step[2]), 0, 8)
	local goalShown = ""
	local goalButton = goalPlate :: TextButton
	goalButton.Activated:Connect(function()
		Kit.Clicked:Fire(goalButton)
		Hud.pop(goalCard, 1.05)
		ctx.fire("Open", "Goals")
	end)

	-- ⚠️ Not saving (not shown for the Studio FreshSave test switch, so the screen looks like a real first visit) ·
	-- 🏠 Clinics full (no clinic a while after loading: all six taken; never flashed during the normal assign).
	local noPlot = false
	local function renderWarning()
		local saving = player:GetAttribute("DataOk") == false and player:GetAttribute("FreshSave") ~= true
		if saving then
			warnIcon.Text, warnText.Text = "⚠️", Pure.TEXT.NotSaving
		elseif noPlot then
			warnIcon.Text, warnText.Text = "🏠", Pure.TEXT.ClinicsFull
		end
		Hud.setNow("Warning", if saving or noPlot then warnCard else nil, Pure.PRIORITY.Warning)
	end
	player:GetAttributeChangedSignal("DataOk"):Connect(renderWarning)
	player:GetAttributeChangedSignal("FreshSave"):Connect(renderWarning)
	local plotToken = 0
	local function watchPlot(state: Types.Snapshot)
		plotToken += 1
		local token = plotToken
		if state.PlotIndex ~= nil then
			noPlot = false
			renderWarning()
			return
		end
		task.delay(4, function()
			if token == plotToken and ctx.State.PlotIndex == nil then
				noPlot = true
				renderWarning()
			end
		end)
	end

	local function renderGoal(state: Types.Snapshot, animate: boolean)
		local daily: any = state.Daily
		-- From the end of the tutorial (the Level piece's trigger), whether or not the 🎯 door has arrived yet: until
		-- it does, this card carries the one goal.
		local goal = if shown.Level then Pure.trackedGoal(daily and daily.Goals, data.DailyGoals, data.Wings) else nil
		if not goal then
			goalShown = ""
			Hud.setNow("Goal", nil, Pure.PRIORITY.Goal)
			return
		end
		goalIcon.Text = goal.Icon
		goalText.Text = goal.Text
		fillTo(goalFill, goal.Ratio, animate and goalShown == goal.Id)
		goalShown = goal.Id
		Hud.setNow("Goal", goalCard, Pure.PRIORITY.Goal)
	end

	-- Hud's ONE hint card (over the goal, under the tutorial): "Patients wait for you: press Send", a new door's line,
	-- or the first level-up. Pure.hintPick chooses when more than one is due; a tap does what the card talks about.
	local hintCard, hintPlate, hintIcon, hintText = nowCard("Hint", true)
	local hintDue: { [string]: any } = {} -- Send = true · Door = the piece's name · LevelUp = true
	local hintKind: string? = nil
	local function renderHint()
		local kind = Pure.hintPick(hintDue)
		hintKind = kind
		if kind == "Send" then
			hintIcon.Text, hintText.Text = Icons.State.Waiting, Pure.TEXT.Send
		elseif kind == "Door" then
			local words, icon = Pure.doorLine(hintDue.Door)
			hintIcon.Text, hintText.Text = icon, words or ""
		elseif kind == "LevelUp" then
			hintIcon.Text, hintText.Text = Icons.Unit.Level, Pure.TEXT.LevelUp
		end
		Hud.setNow("Hint", if kind then hintCard else nil, Pure.PRIORITY.Hint)
	end
	-- The Shop on its Hospital tab (the same "Open" the 🛒 plate fires with its `shopTab`), then its Level up button
	-- bounces once (Shop.levelUpButton). Shop requires this module, so it is looked up when needed, never at load.
	local function openLevelUp()
		levelHintUsed = true
		hintDue.LevelUp = nil
		renderHint()
		ctx.fire("Open", "Shop", "Hospital")
		task.delay(LEVEL_POINT, function()
			local ok, button = pcall(function()
				local shop = require(script.Parent:FindFirstChild("Shop") :: ModuleScript) :: any
				return shop.levelUpButton()
			end)
			if ok and typeof(button) == "Instance" and button:IsA("GuiObject") and Kit.isShown(button) then
				Hud.pop(button, 1.2)
			end
		end)
	end
	local hintButton = hintPlate :: TextButton
	hintButton.Activated:Connect(function()
		Kit.Clicked:Fire(hintButton)
		local kind = hintKind
		if kind == "LevelUp" then
			openLevelUp()
			return
		elseif kind == "Door" then
			local name = hintDue.Door
			hintDue.Door = nil
			if Pure.RAIL[name] then
				ctx.fire("Open", name)
			end
		elseif kind == "Send" then
			hintDue.Send = nil
		end
		renderHint()
	end)

	-- The level row, from Logic/LevelBar. On a phone it sits in the top-bar row: "Lv 1" and the bar ("Level up!" in
	-- place of the level once it's ready); the name and the needs line are desktop's.
	local function renderLevel(state: Types.Snapshot)
		if type(data.Levels) ~= "table" then
			return
		end
		local view = LevelBar.view(state, data.Levels)
		levelView = view
		local phone = layout.WalletInTopbar
		local label = LevelBar.label(view)
		local parts = LevelBar.parts(view, Hud.format)
		levelText.Text = Icons.words(Icons.level(view.Level, if phone then nil else view.Name))
		setLevelBar(view.Fraction, view.Max)
		if #parts == 2 then
			needStars.Text, needCash.Text = parts[1].Text, parts[2].Text
		end
		levelNeeds.Visible = not phone and label == nil and #parts == 2
		levelReady.Text = label or ""
		levelReady.TextColor3 = if view.Ready then Theme.Colors.Collect else Theme.Colors.OnColor
		levelReady.Visible = label ~= nil and (view.Ready or not phone)
		levelBadge.Visible = not (phone and view.Ready)
		hintDue.LevelUp = if Pure.levelHint(state.Tutorial, view.Level, view.Ready, levelHintUsed) then true else nil
		renderHint()
	end
	levelButton.Activated:Connect(function()
		Kit.Clicked:Fire(levelButton)
		Hud.pop(levelButton, 1.06)
		local view = levelView
		if view and view.Ready then
			openLevelUp()
		elseif view then
			ctx.toast(LevelBar.nextText(view, Hud.format))
		end
	end)

	--------------------------------------------------------------------------------------------------------------
	-- Layout: the zone map on every resize
	--------------------------------------------------------------------------------------------------------------
	local function onRail(name: string): boolean
		return table.find(layout.Left, name) ~= nil or table.find(layout.Right, name) ~= nil
	end
	local renderStatus: () -> ()
	local function pieceGui(name: string): GuiObject?
		if name == "Stars" then
			return starsRow
		elseif name == "Level" then
			return levelButton
		end
		return statusRows[name] or buttons[name]
	end
	local function applyPiece(name: string)
		local button = buttons[name]
		if button then
			button.Visible = shown[name] == true and onRail(name)
		elseif statusRows[name] then
			renderStatus() -- a Status line shows when it's revealed, has words and fits
		else
			local piece = pieceGui(name)
			if piece then
				piece.Visible = shown[name] == true
			end
		end
	end

	local function relayout()
		local size = gui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local w = size.X
		layout = HudZones.layout(w, size.Y, Hud.topbar())
		box = Pure.statusBox(layout, w)

		-- Wallet: top left above the left rail, or up in the top-bar row on a phone.
		if layout.WalletInTopbar then
			wallet.Parent = systemRow
			walletList.FillDirection = Enum.FillDirection.Horizontal
			walletList.Padding = UDim.new(0, Theme.Space.Step[3])
			walletList.VerticalAlignment = Enum.VerticalAlignment.Center
		else
			wallet.Parent = gui
			wallet.Position = UDim2.fromOffset(layout.Margin, layout.Top + 8)
			walletList.FillDirection = Enum.FillDirection.Vertical
			walletList.Padding = UDim.new(0, Theme.Space.Step[1])
			walletList.VerticalAlignment = Enum.VerticalAlignment.Top
		end

		-- Rails: each zone covers its slots (a zone pops toward its screen edge).
		local function place(zone: Frame, side: "Left" | "Right", order: { string }, count: number)
			local height = count * layout.Button + math.max(0, count - 1) * layout.Gap
			local first = HudZones.railRect(layout, side, 1, w)
			zone.Size = UDim2.fromOffset(layout.Button, height)
			zone.Position = UDim2.fromOffset(if side == "Left" then first.X0 else first.X1, first.Y0 + height / 2)
			for index, name in order do
				local button = buttons[name]
				button.Size = UDim2.fromOffset(layout.Button, layout.Button)
				button.Position = UDim2.fromOffset(0, (index - 1) * (layout.Button + layout.Gap))
				placeFace(button, layout.Captions, name == "Gifts")
			end
		end
		place(leftZone, "Left", HudZones.ORDER.LeftRail, #layout.Left)
		place(rightZone, "Right", HudZones.ORDER.RightRail, #layout.Right)
		-- A piece in ⚙️ More: flying icons and pointers for it land on ⚙️.
		for _, order in { HudZones.ORDER.LeftRail, HudZones.ORDER.RightRail } do
			for _, name in order do
				targets[name] = if table.find(layout.More, name) then settingsButton else buttons[name]
			end
		end
		for name in Pure.RAIL do
			applyPiece(name)
		end

		-- Now: top centre, under the top bar, as wide as the zone map allows.
		local now = HudZones.nowRect(layout, w)
		local nowZone = nowFrame()
		nowZone.Position = UDim2.new(0.5, 0, 0, now.Y0)
		nowZone.Size = UDim2.fromOffset(layout.NowWidth, 0)

		-- Status: the screen edge (desktop) or the strip beside the right rail (phones).
		statusZone.Position = UDim2.fromOffset(box.X1, box.Top)
		statusZone.Size = UDim2.fromOffset(box.Width, 0)
		boostList.FillDirection = if box.Compact then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
		boostList.HorizontalAlignment = Enum.HorizontalAlignment.Right
		faceDisc.Visible = not box.Compact

		-- The level row: under ⭐, or in the top-bar row on a phone (shorter, with a shorter bar).
		local phone = layout.WalletInTopbar
		levelButton.Size = UDim2.fromOffset(0, if phone then HudZones.WALLET_ROW else HudZones.LEVEL_ROW)
		levelBar.Size = UDim2.fromOffset(if phone then LEVEL_BAR_PHONE else LEVEL_BAR, Theme.Calm.Bar)
		renderLevel(ctx.State)

		handsZone.Position = UDim2.new(0.5, 0, 1, -layout.Margin)
		renderHands()
		renderRows()
		renderStatus()
		nowChanged()
	end

	--------------------------------------------------------------------------------------------------------------
	-- Status, kept current (the clock only rewrites its text; it slows down while Status is hidden)
	--------------------------------------------------------------------------------------------------------------
	local function boostChip(id: string): Line
		local existing = boostChips[id]
		if existing then
			return existing
		end
		local entry = line(boostRow, 0, false)
		entry.Chip.Name = id
		entry.Chip.BackgroundColor3 = Theme.Colors.Plate
		entry.Chip.BackgroundTransparency = 0
		local stroke = entry.Chip:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = true
		end
		boostChips[id] = entry
		Hud.pop(entry.Chip, 1.2)
		return entry
	end

	renderStatus = function()
		local state = ctx.State
		local compact = box.Compact
		local room = math.max(1, box.Width - 2 * Theme.Space.Step[2])
		local now = Workspace:GetServerTimeNow()

		-- 1 Day or night, with words.
		local endsAt = Workspace:GetAttribute("PhaseEndsAt")
		local night = Workspace:GetAttribute("IsNight") == true
		local clock = Pure.dayLine(
			night,
			if type(endsAt) == "number" then endsAt - now else nil,
			ctx.Config.NightPayMultiplier,
			compact
		)
		setLine(clockLine, clock, room, compact)
		paint(clockLine, if night then Theme.Colors.Night else nil)

		-- 2 The one free-event chip.
		local candidates =
			Pure.eventCandidates(Workspace:GetAttribute("GoldenStartsAt"), Workspace:GetAttribute("GoldenHour"))
		local event = Pure.eventChip(now, candidates, compact)
		setLine(eventLine, event or "", room, compact)
		paint(eventLine, Theme.Colors.Cash)

		-- 3 Today's Visitor, only for a clinic it can come to (and ✅ once cured).
		local visitor = if type(state.TodaysVisitor) == "string" then state.TodaysVisitor else ""
		local look = Hud.lookOf(visitor)
		if visitor ~= shownVisitor then
			shownVisitor = visitor
			faceDisc:ClearAllChildren()
			faceRing()
			if look then
				Hud.portrait(look).Parent = faceDisc
			end
		end
		local visitorText = if look then Pure.visitorLine(state.VisitorStatus) else nil
		local faceRoom = if compact then 0 else Pure.ROW + Theme.Space.Step[1]
		setLine(visitorLine, visitorText or "", room - faceRoom, compact)

		-- 4 Timed boosts (at most 3), with the play time they have left.
		local live = Pure.boosts(Hud.liveBoosts(state))
		local seen: { [string]: boolean } = {}
		for index, entry in live do
			local def = rawget(data.Boosts, entry.Id)
			if def then
				seen[entry.Id] = true
				local chip = boostChip(entry.Id)
				chip.Chip.LayoutOrder = index
				setLine(chip, def.Icon .. " " .. PlaytimeLogic.clock(entry.Left), room, true)
			end
		end
		for id, chip in boostChips do
			if not seen[id] then
				chip.Chip:Destroy()
				boostChips[id] = nil
			end
		end

		-- The rows that are revealed and fit, the clock first.
		local want = {
			Clock = clock ~= "",
			Event = event ~= nil,
			Visitor = visitorText ~= nil,
			Boosts = next(boostChips) ~= nil,
		}
		local used = 0
		for _, name in Pure.STATUS_ORDER do
			local on = (want :: any)[name] == true and shown[name] == true and used < box.Rows
			if on then
				used += 1
			end
			statusRows[name].Visible = on
		end
	end

	task.spawn(function()
		while gui.Parent do
			renderStatus()
			task.wait(if Kit.isShown(statusColumn) then 0.25 else 1)
		end
	end)
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(function()
		renderStatus()
		Hud.pop(clockLine.Chip, 1.15)
	end)

	--------------------------------------------------------------------------------------------------------------
	-- What hides while things are open (look build plan §B7)
	--------------------------------------------------------------------------------------------------------------
	local openModes: { [string]: string } = {}
	local celebrateGui: ScreenGui? = nil
	local hideReady = false -- the first pass places without motion
	local function celebrating(): boolean
		local screen = celebrateGui
		return screen ~= nil and screen.Parent ~= nil and screen.Enabled
	end
	local function applyHide()
		local hide = Pure.hidden(Pure.mode(openModes), celebrating())
		local animate = hideReady
		zoneShow(leftZone, not hide.Rails, animate)
		zoneShow(rightZone, not hide.Rails, animate)
		zoneShow(statusZone, not hide.Status, animate)
		zoneShow(nowFrame(), not hide.Now, animate)
		zoneShow(wallet, not hide.Wallet, animate)
		zoneShow(handsZone, not hide.Hands, animate)
		system.Enabled = not hide.System
		hideReady = true
		nowChanged()
	end
	ctx.on("ModalOpened", function(name: any, mode: any)
		if type(name) == "string" then
			openModes[name] = if type(mode) == "string" then mode else "Panel"
			applyHide()
		end
	end)
	ctx.on("ModalClosed", function(name: any)
		if type(name) == "string" then
			openModes[name] = nil
			applyHide()
		end
	end)
	-- UI/Celebrate's screen (a ScreenGui named "Celebrate", Enabled while a celebration shows).
	local function watchCelebrate(child: Instance)
		if child.Name == "Celebrate" and child:IsA("ScreenGui") and child ~= celebrateGui then
			celebrateGui = child
			child:GetPropertyChangedSignal("Enabled"):Connect(applyHide)
			applyHide()
		end
	end
	local playerGui = player:WaitForChild("PlayerGui")
	playerGui.ChildAdded:Connect(watchCelebrate)
	for _, child in playerGui:GetChildren() do
		watchCelebrate(child)
	end

	--------------------------------------------------------------------------------------------------------------
	-- The reveal (UI direction R0; memory-20261117-007 #3): the HUD grows ONE piece at a time, each when it first
	-- has content (Pure.TRIGGERS), in fixed slots. During the tutorial that is ⭐, 🛒 and 📖 at their steps; after
	-- it, each door on its own trigger. A save that already has content shows its doors at once when it loads (no
	-- pop, no line): nobody loses a door. A new door pops once (Kit.reveal) with one line on the Now card, and the
	-- next one waits for it (Kit.Juice.nextReveal).
	--------------------------------------------------------------------------------------------------------------
	local session = {
		Cured = false, -- a treatment landed this session: ⭐ shows with it, not a moment later with the snapshot
		Night = Workspace:GetAttribute("IsNight") == true,
		CanHire = false,
		GiftReady = false,
		GoalReady = false,
		GoldenLevel = BeltLogic.minLevel(ctx.Config, "Secret"), -- Golden Hour's own nurses can't be hired before it
	}
	local kept: { [string]: boolean } = {} -- shown this session: a door never leaves because the cash was spent
	local wanted: { [string]: boolean } = {}
	local loaded = false -- the save has arrived: from now on a new piece pops in
	local pumping = false
	local function showPiece(name: string, animate: boolean): boolean
		shown[name] = true
		kept[name] = true
		local piece = pieceGui(name)
		local appeared = false
		if piece and animate and statusRows[name] == nil and (buttons[name] == nil or onRail(name)) then
			appeared = Kit.reveal(piece, true)
		end
		applyPiece(name)
		renderRows()
		return (appeared or statusRows[name] ~= nil) and piece ~= nil and Kit.isShown(piece)
	end
	local function pump()
		if pumping then
			return
		end
		pumping = true
		task.spawn(function()
			while true do
				local name = Kit.Juice.nextReveal(Pure.REVEAL_ORDER, wanted, shown)
				if not name then
					break
				end
				if celebrating() or Pure.mode(openModes) ~= "None" then
					task.wait(0.25) -- a celebration, a panel or the mini-game first: a door arrives where it is seen
				else
					local appeared = showPiece(name, true)
					local words = Pure.doorLine(name)
					if appeared and statusRows[name] then
						Hud.pop(statusRows[name], 1.12)
					end
					if appeared then
						Hud.sound("Pop", 0.5)
					end
					if appeared and words then
						hintDue.Door = name
						renderHint()
						task.wait(Pure.REVEAL_HOLD)
						if hintDue.Door == name then
							hintDue.Door = nil
							renderHint()
						end
					else
						task.wait(Pure.STAGGER)
					end
				end
			end
			pumping = false
			renderGoal(ctx.State, false)
		end)
	end
	local function applyReveal(state: Types.Snapshot, animate: boolean)
		local price = BeltLogic.price(ctx.Config, BeltLogic.RARITIES[1], state.Level or 1)
		session.CanHire = price > 0 and (state.Cash or 0) >= price
		session.GoalReady = goalReady(data, state)
		wanted = Pure.reveal(state, session, kept)
		for _, name in Pure.REVEAL_ORDER do
			if not wanted[name] then
				kept[name] = nil
				if shown[name] then
					shown[name] = false
					applyPiece(name)
				end
				if hintDue.Door == name then
					hintDue.Door = nil
					renderHint()
				end
			elseif not shown[name] and not animate then
				showPiece(name, false) -- the save loading in: what it already has is simply there
			end
		end
		if animate then
			pump()
		end
		renderRows()
	end
	ctx.Remotes.Cured.OnClientEvent:Connect(function()
		session.Cured = true
		applyReveal(ctx.State, true)
	end)
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(function()
		if Workspace:GetAttribute("IsNight") == true and not session.Night then
			session.Night = true -- the first night: the day and night line (and the daily goals) have a reason now
			applyReveal(ctx.State, loaded)
		end
	end)

	-- "Patients wait for you: press Send" (Pure.sendHint): a slow look at your own waiting room, only until the hint
	-- has been shown once. A patient's Send prompt is on exactly while it waits to be sent (Server/Patients).
	local sendUsed = false
	local sendShownAt = 0
	local waitingSince: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any
	local function longestWait(): number?
		local plot = myClinic()
		if not plot then
			return nil
		end
		local now = os.clock()
		local longest: number? = nil
		for _, prompt in CollectionService:GetTagged(Pure.SEND_PROMPT.Tag) do
			if
				prompt.Name == Pure.SEND_PROMPT.Name
				and prompt:IsA("ProximityPrompt")
				and prompt:IsDescendantOf(plot)
			then
				if prompt.Enabled then
					local since = waitingSince[prompt] or now
					waitingSince[prompt] = since
					longest = math.max(longest or 0, now - since)
				else
					waitingSince[prompt] = nil
				end
			end
		end
		return longest
	end
	task.spawn(function()
		while gui.Parent and not (sendUsed and hintDue.Send == nil) do
			local waited = longestWait()
			if hintDue.Send then
				if waited == nil or os.clock() - sendShownAt >= Pure.SEND_HINT.Hold then
					hintDue.Send = nil
					renderHint()
				end
			elseif Pure.sendHint(ctx.State.Tutorial, waited, sendUsed) then
				sendUsed = true
				sendShownAt = os.clock()
				hintDue.Send = true
				renderHint()
			end
			task.wait(HINT_EVERY)
		end
	end)

	--------------------------------------------------------------------------------------------------------------
	-- Dots, news and juice
	--------------------------------------------------------------------------------------------------------------
	ctx.on("BookNew", function(count: any)
		Kit.setDot(buttons.Book, type(count) == "number" and count > 0)
	end)
	ctx.on("NursesNew", function(count: any)
		Kit.setDot(buttons.Nurses, type(count) == "number" and count > 0)
	end)
	-- Progression v2: a nurse sold (to the Agency, or on the Market while you're away from the kiosk) sends its coins
	-- home into 💰, so the cash roll has a reason to move.
	ctx.on("NurseNews", function(info: any)
		if type(info) ~= "table" then
			return
		end
		local paid = if info.Kind == "Sold" then info.Cash elseif info.Kind == "Gone" then info.Price else nil
		if type(paid) == "number" and paid == paid and paid > 0 then
			Hud.fly(nil, Icons.Unit.Cash, "Cash", Kit.Juice.coins(paid))
		end
	end)

	-- The 🔥 combo sticker follows the player attribute Combo (T1, session-only). Hidden during the tutorial.
	local comboSteps = (ctx.Config.MiniGame and ctx.Config.MiniGame.Combo) or {}
	local comboShown = 0
	local function renderCombo()
		local raw = player:GetAttribute("Combo")
		local combo = if type(raw) == "number" and raw == raw then math.max(0, math.floor(raw)) else 0
		if TutorialLogic.active(ctx.State.Tutorial) then
			combo = 0
		end
		local before = comboShown
		comboShown = combo
		if combo <= 0 then
			if comboSticker.Visible then
				if Hud.calm() then
					comboSticker.Visible = false
				else
					Kit.popOut(comboSticker)
				end
			end
			return
		end
		local tier, multiplier = Kit.Juice.comboStep(combo, comboSteps)
		comboSticker.Text = "🔥" .. combo
		comboSticker.BackgroundColor3 = COMBO_COLORS[math.clamp(tier + 1, 1, #COMBO_COLORS)]
		if not comboSticker.Visible or before == 0 then
			Kit.popIn(comboSticker)
		elseif combo > before then
			Hud.pop(comboSticker, 1.35)
		end
		if Kit.Juice.crossed(before, combo, comboSteps) then
			floatText(comboSticker, Icons.unit("Cash", "×" .. tostring(multiplier)), Theme.Colors.Cash)
		end
	end
	player:GetAttributeChangedSignal("Combo"):Connect(renderCombo)

	--------------------------------------------------------------------------------------------------------------
	-- Play gifts and timed boosts, live: the server's PlayToday/PlayTotal attributes move every second of play
	--------------------------------------------------------------------------------------------------------------
	local gifts = data.Playtime.Gifts
	local giftsWereReady = false
	local giftsShown = false -- the first render after the save loads never bounces
	local function renderGifts()
		local state = ctx.State
		if type(state.Playtime) ~= "table" then
			return
		end
		local save, day = Hud.livePlay(state)
		local ready = #PlaytimeLogic.ready(save, day, gifts) > 0
		local nextIndex = PlaytimeLogic.nextGift(save, day, gifts)
		local ratio = 1
		if nextIndex then
			local goal = PlaytimeLogic.giftSeconds(gifts[nextIndex])
			local from = if nextIndex > 1 then PlaytimeLogic.giftSeconds(gifts[nextIndex - 1]) else 0
			ratio = math.clamp((save.TodaySeconds - from) / math.max(1, goal - from), 0, 1)
		end
		local full = ready or not nextIndex
		giftFill.Size = UDim2.fromScale(if full then 1 else math.max(ratio, 0.08), 1)
		giftFill.BackgroundColor3 = if ready then Theme.Colors.Collect else Theme.Colors.Progress
		Kit.setDot(giftButton, ready)
		if ready and not giftsWereReady and giftsShown and Kit.isShown(giftButton) then
			Hud.pop(giftButton, 1.2)
		end
		giftsWereReady = ready
		giftsShown = state ~= initial
		if ready and not session.GiftReady then
			session.GiftReady = true -- the first gift is ready: the 🎁 door has content
			applyReveal(state, loaded)
		end
	end
	local function renderPlay()
		renderGifts()
		renderStatus()
	end
	for _, attribute in { "PlayToday", "PlayTotal" } do
		player:GetAttributeChangedSignal(attribute):Connect(renderPlay)
	end
	Workspace:GetAttributeChangedSignal("UtcDay"):Connect(renderPlay)

	--------------------------------------------------------------------------------------------------------------
	-- Keeping it current
	--------------------------------------------------------------------------------------------------------------
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	pcall(function()
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(relayout)
	end)
	relayout()
	applyReveal(initial, false)
	applyHide()
	renderWarning()

	local branchWasNews = false
	local mailWasReady = false
	local goalsWereReady = false
	ctx.onState(function(state: Types.Snapshot)
		local isServerState = state ~= initial
		local animate = isServerState and loaded
		if isServerState then
			loaded = true
		end
		applyReveal(state, animate)

		cash.set(state.Cash or 0, animate)
		stars.set(state.Stars or 0, animate)

		renderLevel(state)

		local mailReady = state.MailboxReady == true
		local goalsReady = goalReady(data, state)
		Kit.setDot(buttons.Mailbox, mailReady) -- one 📬 always; the red dot is "a letter is waiting"
		Kit.setDot(buttons.Goals, goalsReady)
		local news = Hud.shopNews(data, state)
		shopTab = if news.Rooms
			then "Rooms"
			elseif news.Decor then "Decor"
			elseif news.Hospital or news.Branch then "Hospital"
			else nil
		-- Progression v2: a branch reward waiting (and nothing else) makes the dot a 🃏 (a perk card to pick) or 🌳
		-- (tree points to spend) sticker; it pops once when it appears, never again (no pressure, red line 3).
		local branchOnly = news.Branch and not (news.Rooms or news.Decor or news.Hospital)
		local rebirth = (state :: any).Rebirth
		local offer = type(rebirth) == "table" and type(rebirth.Offer) == "table" and #rebirth.Offer > 0
		Kit.setDot(
			buttons.Shop,
			shopTab ~= nil,
			if branchOnly then (if offer then Icons.Unit.Cards else Icons.Unit.Tree) else nil
		)
		if animate and news.Branch and not branchWasNews then
			Hud.pop(buttons.Shop, 1.15)
		end
		branchWasNews = news.Branch
		if animate and mailReady and not mailWasReady then
			Hud.pop(buttons.Mailbox, 1.2)
		end
		if animate and goalsReady and not goalsWereReady then
			Hud.pop(buttons.Goals, 1.2)
		end
		mailWasReady, goalsWereReady = mailReady, goalsReady

		if isServerState then
			watchPlot(state)
		end
		if comboShown > 0 and TutorialLogic.active(state.Tutorial) then
			renderCombo()
		end
		renderGoal(state, animate)
		renderSettings()
		renderPlay()
	end)
	renderHands()
	renderCombo()
end

return Hud
