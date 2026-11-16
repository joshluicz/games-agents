--!strict
-- Hud (build plan Task 6; look overhaul T5): the always-on screen, plus the shared UI pieces the other panels build on.
--
-- THE ZONE MAP (look build plan §B7; docs/research/2026-11-16-ux-cohesion-audit.md §3.1; memory-20261117-001 #4).
-- Every piece belongs to ONE zone (Logic/HudZones.ZONE) and keeps its slot: a piece that isn't revealed yet leaves its
-- slot empty, so nothing ever jumps. Laid out from HudZones.layout(safe width, safe height, top bar) on every resize:
--   System   the Roblox top-bar row (a ScreenInsets = TopbarSafeInsets ScreenGui, beside Roblox's own buttons): ⚙️ on
--            a dark-glass plate. On phones (a safe height under 440) the wallet joins this row
--   Wallet   top left, above the left rail: 💰 and ⭐, each an icon plus a big outlined number (TextSize.Number) with
--            NO pill. ⭐ keeps its thin bar and the next-unlock icon and stays tappable (what's next). The roll-ups
--            (Kit.countUp), the floating "+n" and the mini-game's 🔥 combo sticker (never during the tutorial) stay
--   Now      top centre: ONE card (Hud.setNow), the highest priority first: 30 Hud's warnings (⚠️ Not saving, 🏠
--            Clinics full) · 20 the tutorial card (UI/Tutorial) · 10 the tracked goal (the first unfinished daily
--            goal, "🎯 Cure 5 · 3/5"; a tap opens Goals). Hidden when empty. Toasts and banners stack under it
--            (UI/Toasts, Hud.nowBottom)
--   Status   top right, right-aligned, read-only: (1) day or night with words ("☀️ Night in 3:27" / "🌙 ×2 · 2:08 left":
--            the day/night line keeps m:ss); (2) ONE free-event chip ("🌟 Golden Hour in 12m": Logic/NextEvent over
--            Golden Hour only, in minutes, hidden while it runs, when it's over 6 h away and for anything paid:
--            memory-20261116-022, CLAUDE.md red line 3); (3) "Visitor ⭐" / "Visitor ✅" with its face, only when it
--            can come to your clinic; (4) at most 3 small boost chips (the play time left: a boost only ticks while
--            you play). Desktop: at the screen edge, as many rows as fit above the right rail (the clock first).
--            Phones: in the strip between the Now card and the right rail, in fewer words
--   Rails    left, menus you browse: 🛒 Shop · 👩‍⚕️ Nurses · 📖 Book · 🏅 Badges · 🏆 Top; right, rewards waiting: 🎁
--            Gifts · 🎯 Goals · 📬 Mail. One white Icon plate each (Kit.iconButton) with ONE shared fill: identity comes
--            from the icon and caption, never the fill, so the Shop looks like its neighbours. A still red dot
--            top-right when something waits there (a room you can buy or decor to place · new pages · mail · a goal
--            done · Nurse Journal news · a gift to open). 🎁's bar fills inside its plate. Phones: 56 px plates, no
--            captions, 3 a side, and 🏅 / 🏆 move into ⚙️ More (desktop too, when the left rail can't fit all five)
--   Bottom   only your hands (the `Carry` attribute: what you hold, nothing when they're empty), each ringed in its
--            station's colour with a red ✖ you HOLD to throw it away (Destructive: behind a hold, look build plan
--            §B8). Nothing is ever in the bottom corners (the thumbstick and jump on touch)
-- ⚙️ Settings: 🎵 music · ✨/💤 calm effects (the client-only attributes MusicMuted and ReduceEffects) · 👆 Simple mode
-- (SetSimple) · 👥 who may help at your clinic (SetHelpers; owners only) · ⏭️ Skip tutorial while it runs, or 🔁
-- Replay tutorial once it's done and you own a clinic (each fires a bus event: UI/Tutorial owns the confirm and the
-- remote) · ⚙️ More (🏅 Badges, 🏆 Top, when they're off the rail) · 🛠️ Admin (only while the server set IsAdmin).
-- When things open (UI/Modal's ModalOpened / ModalClosed carry a HudMode): a Panel hides the rails, Now and Status
-- (the wallet stays, so you watch your cash while you shop) · the mini-game ("Game") hides the rails and Status (the
-- wallet and the Now card stay) · a Popup ("None") changes nothing · a celebration (UI/Celebrate's screen) hides
-- everything.
-- First session (docs/plan/2026-11-16-first-session-design.md §A3), in the fixed slots: 💰 at first; ⭐ after the first
-- cure; 🛒 at the shop step; 📖 at the Book step (its pointer needs it); at DONE the rest pops in, one piece every
-- 0.15 s (after the finale's celebration closes). A replay keeps the HUD full; a player who's done sees it all at
-- once. Until the first snapshot arrives (Tutorial 0, "not known yet") only 💰 shows. ⚙️ always shows.
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
--   Hud.NowMoved: Signal (bottom)      fires whenever nowBottom changes (UI/Toasts follows it)
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
--                                      "Nurses", "Badges", "Boards", "Gifts", "Settings", "Hands"), for pointers
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
local ProgressLogic = require(Logic:WaitForChild("Progress"))
local TreeLogic = require(Logic:WaitForChild("Tree"))
local HudZones = require(Logic:WaitForChild("HudZones"))
local NextEvent = require(Logic:WaitForChild("NextEvent"))
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
-- No Roblox APIs: tests/HudScreen.spec loads this block on its own, with TutorialLogic, NextEvent and HudZones.
local Pure = {}

-- The Now slot's priorities (look build plan §B7): Hud's warnings · the tutorial card (UI/Tutorial) · the goal.
Pure.PRIORITY = table.freeze({ Warning = 30, Tutorial = 20, Goal = 10 })
Pure.STAGGER = 0.15 -- seconds between pieces as the rest of the HUD pops in at DONE
Pure.MAX_BOOSTS = 3 -- boost chips in Status, at most
Pure.ROW = 28 -- a Status row's height (px)
Pure.ROW_GAP = 4
Pure.STATUS_ORDER = table.freeze({ "Clock", "Event", "Visitor", "Boosts" }) -- top to bottom; the first rows win
-- The free events Status may count down to (memory-20261116-022). Golden Hour only for now (look build plan §F 7);
-- admin events join when they exist. Nothing paid is ever on this list.
Pure.GOLDEN = table.freeze({ Id = "GoldenHour", Icon = "🌟", Name = "Golden Hour" })
-- The hands at the bottom centre: each between Min and Max px, the row keeping Clear px free at each side (the
-- thumbstick and the jump button sit about 100 px in from the edges).
Pure.HAND = table.freeze({ Max = 84, Min = 56, Gap = 6, Clear = 120 })
-- Every rail plate is the same Icon role: identity comes from the icon and caption, never the fill.
Pure.RAIL_KIND = "Icon"
Pure.RAIL = table.freeze({
	Shop = table.freeze({ Icon = "🛒", Caption = "Shop" }),
	Nurses = table.freeze({ Icon = "👩‍⚕️", Caption = "Nurses" }),
	Book = table.freeze({ Icon = "📖", Caption = "Book" }),
	Badges = table.freeze({ Icon = "🏅", Caption = "Badges" }),
	Boards = table.freeze({ Icon = "🏆", Caption = "Top" }),
	Gifts = table.freeze({ Icon = "🎁", Caption = "Gifts" }),
	Goals = table.freeze({ Icon = "🎯", Caption = "Goals" }),
	Mailbox = table.freeze({ Icon = "📭", Caption = "Mail" }),
})
-- The rows ⚙️ More shows for a rail piece that's off the rail.
Pure.MORE = table.freeze({ Badges = "🏅 Badges", Boards = "🏆 Top" })
-- The order the rest of the HUD pops in at DONE (the left rail, the right rail, then Status).
Pure.REVEAL_ORDER =
	table.freeze({ "Shop", "Nurses", "Book", "Badges", "Boards", "Gifts", "Goals", "Mailbox", "Status" })

type NowEntry = { Source: string, Priority: number, Seq: number }
type Reveal = { Stars: boolean, Shop: boolean, Book: boolean, Rest: boolean }
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
-- the night pay multiplier. Compact (a phone's narrow column) drops words.
function Pure.dayLine(night: boolean, left: any, pay: any, compact: boolean?): string
	if not finite(left) then
		return ""
	end
	local time = Pure.clock(left)
	if night then
		local times = if finite(pay) and pay > 1 then "×" .. tostring(pay) .. " · " else ""
		return "🌙 " .. times .. time .. (if compact then "" else " left")
	end
	return if compact then "🌙 in " .. time else "☀️ Night in " .. time
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

-- Status row 3: Today's Visitor with a word, only while it can come to your clinic ("Coming") or once it's cured.
function Pure.visitorLine(status: any): string?
	if status == "Coming" then
		return "Visitor ⭐"
	elseif status == "Done" then
		return "Visitor ✅"
	end
	return nil
end

-- A daily goal in two or three words: "Cure 5", "Cure 3 🌙", "Make 10", "Cure 6 🌳" (the wing's icon).
function Pure.goalName(def: any, wings: any): string
	local target = tostring(def.Target)
	if def.Kind == "Make" then
		return "Make " .. target
	elseif def.Kind == "CureNight" then
		return "Cure " .. target .. " 🌙"
	elseif def.Kind == "CureWing" then
		local wing = if type(wings) == "table" and type(def.Wing) == "string" then rawget(wings, def.Wing) else nil
		local icon = if type(wing) == "table" and type(wing.Icon) == "string" then " " .. wing.Icon else ""
		return "Cure " .. target .. icon
	end
	return "Cure " .. target
end

-- The tracked goal (look build plan §F 7): the first daily goal still under its target, as "Cure 5 · 3/5" with the
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
							Icon = "🎯",
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

-- The first-session reveal: what shows at each tutorial step (a snapshot without the field counts as done). A replay
-- keeps everything.
function Pure.reveal(step: any, curedSeen: boolean?, replay: boolean?): Reveal
	local s = if type(step) == "number" then step else TutorialLogic.DONE
	if replay == true or TutorialLogic.isDone(s) then
		return { Stars = true, Shop = true, Book = true, Rest = true }
	elseif not TutorialLogic.active(s) then
		return { Stars = false, Shop = false, Book = false, Rest = false } -- 0: not known yet
	end
	return {
		Stars = s >= TutorialLogic.MORE or (s >= TutorialLogic.REST and curedSeen == true),
		Shop = s >= TutorialLogic.SHOP,
		Book = s >= TutorialLogic.BOOK,
		Rest = false,
	}
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

-- The ⚙️ panel's rows, in order. `more` lists the rail pieces off the rail (revealed ones only).
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
	local stroke = Instance.new("UIStroke")
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
	Star = { Text = "⭐", Size = 0.28, Dy = -0.06, Dx = 0 },
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

local WALLET_ICON = 40 -- 💰 / ⭐ icons (px)
local WALLET_ROW = 52 -- the 💰 row; ⭐ is a full 56 px tap target
local STAR_BAR = Vector2.new(90, 10) -- ⭐'s thin bar to the next unlock
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
	Kit.stroke(plate, Theme.Colors.Stroke, Theme.Stroke.Bold)
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

-- The ⭐ bar runs from the last star unlock you passed to the next one (a room you don't own and your hospital level
-- allows, the next hospital level's ⭐ gate, or a regular).
local function starTrack(data: any, state: Types.Snapshot): (number, number?, string, string)
	local stars = state.Stars or 0
	local rooms = state.Rooms or {}
	local passed, nextAt, nextIcon, nextName = 0, nil :: number?, "👑", ""
	local function consider(at: number, icon: string, name: string, eligible: boolean)
		if at <= 0 then
			return
		end
		if at <= stars then
			passed = math.max(passed, at)
		elseif eligible and (nextAt == nil or at < nextAt) then
			nextAt, nextIcon, nextName = at, icon, name
		end
	end
	for _, roomId in data.Rooms.Order do
		local room = data.Rooms[roomId]
		local inSeason = room.Season == nil or state.IsWinter == true
		consider(
			room.StarsNeeded,
			room.Icon,
			room.Name,
			rooms[roomId] ~= true and inSeason and ProgressLogic.levelAllows(state, room)
		)
	end
	local levels = data.Levels
	if type(levels) == "table" then
		local nextLevel = LevelsLogic.nextRow(levels, state.Level)
		if nextLevel then
			consider(nextLevel.Stars, nextLevel.Icon, nextLevel.Name, true)
		end
	end
	for _, regularId in data.Regulars.Order do
		local regular = data.Regulars[regularId]
		consider(regular.UnlockStars, "💌", regular.Name, true)
	end
	return passed, nextAt, nextIcon, nextName
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
	return if #parts > 0 then "✨ " .. table.concat(parts, "  ") else "✨ No boosts yet: earn badges!"
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
		Icon = "⚙️",
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
	-- Wallet: 💰 and ⭐, an icon and a big outlined number each, no pills
	--------------------------------------------------------------------------------------------------------------
	local wallet = Instance.new("Frame")
	wallet.Name = "Wallet"
	wallet.BackgroundTransparency = 1
	wallet.Size = UDim2.new()
	wallet.AutomaticSize = Enum.AutomaticSize.XY
	wallet.LayoutOrder = 2
	wallet.Parent = gui
	local walletList = Kit.list(wallet, Enum.FillDirection.Vertical, Theme.Space.Step[1])
	walletList.HorizontalAlignment = Enum.HorizontalAlignment.Left

	local function walletIcon(parent: Instance, text: string, order: number): TextLabel
		return Kit.label({
			Name = "Icon",
			Text = text,
			TextScaled = true,
			LayoutOrder = order,
			Size = UDim2.fromOffset(WALLET_ICON, WALLET_ICON),
			Parent = parent,
		})
	end
	local function walletNumber(parent: Instance, order: number, height: number): TextLabel
		local label = Kit.label({
			Name = "Amount",
			Text = "0",
			Outlined = true,
			TextSize = Theme.TextSize.Number,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, height),
			LayoutOrder = order,
			Parent = parent,
		})
		Kit.outline(label, Theme.Stroke.Title)
		return label
	end
	local function walletRow(row: GuiObject, name: string, order: number, height: number)
		row.Name = name
		row.LayoutOrder = order
		row.BackgroundTransparency = 1
		row.Size = UDim2.fromOffset(0, height)
		row.AutomaticSize = Enum.AutomaticSize.X
		local list = Kit.list(row, Enum.FillDirection.Horizontal, Theme.Space.Step[2])
		list.HorizontalAlignment = Enum.HorizontalAlignment.Left
		row.Parent = wallet
	end

	local cashRow = Instance.new("Frame")
	walletRow(cashRow, "Cash", 1, WALLET_ROW)
	walletIcon(cashRow, "💰", 1)
	local cashText = walletNumber(cashRow, 2, WALLET_ROW - 8)
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
	Kit.stroke(comboSticker, Theme.Colors.Stroke, Theme.Stroke.Fine)
	Kit.textLimit(comboSticker, Theme.TextSize.Body)

	-- ⭐: tappable (what's next), so it's a full 56 px tap target. The number over its thin bar, then the next unlock.
	local starsButton = Instance.new("TextButton")
	starsButton.Text = ""
	starsButton.AutoButtonColor = false
	starsButton.Visible = false
	walletRow(starsButton, "Stars", 2, Theme.Size.ButtonHeight)
	walletIcon(starsButton, "⭐", 1)
	local starsInfo = Instance.new("Frame")
	starsInfo.Name = "Info"
	starsInfo.LayoutOrder = 2
	starsInfo.BackgroundTransparency = 1
	starsInfo.Size = UDim2.new()
	starsInfo.AutomaticSize = Enum.AutomaticSize.XY
	starsInfo.Parent = starsButton
	local infoList = Kit.list(starsInfo, Enum.FillDirection.Vertical, 0)
	infoList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local starsText = walletNumber(starsInfo, 1, Theme.TextSize.Number + 2)
	local track, fill = bar(starsInfo, "Track", Theme.Colors.Star, Theme.Colors.Stroke, 0.35)
	track.LayoutOrder = 2
	track.Size = UDim2.fromOffset(STAR_BAR.X, STAR_BAR.Y)
	Kit.stroke(track, Theme.Colors.Stroke, Theme.Stroke.Fine)
	local nextIcon = Kit.label({
		Name = "Next",
		Text = "👑",
		TextScaled = true,
		LayoutOrder = 3,
		Size = UDim2.fromOffset(30, 30),
		Parent = starsButton,
	})
	targets.Stars = starsButton
	local stars = counter(starsButton, starsText, "Stars")
	local nextTip = ""

	--------------------------------------------------------------------------------------------------------------
	-- Status: top right, read-only
	--------------------------------------------------------------------------------------------------------------
	local statusZone = Instance.new("Frame")
	statusZone.Name = "Status"
	statusZone.AnchorPoint = Vector2.new(1, 0)
	statusZone.BackgroundTransparency = 1
	statusZone.AutomaticSize = Enum.AutomaticSize.Y
	statusZone.Parent = gui
	local statusColumn = Instance.new("Frame") -- the reveal shows this; the hide rules pop the zone
	statusColumn.Name = "Column"
	statusColumn.BackgroundTransparency = 1
	statusColumn.Size = UDim2.fromScale(1, 0)
	statusColumn.AutomaticSize = Enum.AutomaticSize.Y
	statusColumn.Visible = false
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
		local stroke = Kit.stroke(chip, Theme.Colors.Stroke, Theme.Stroke.Fine)
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
	roundCorner(faceDisc)
	Kit.stroke(faceDisc, Theme.Colors.Stroke, Theme.Stroke.Fine)
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

	-- 🎁's bar fills inside its plate toward the next play gift (UI/PlayGifts opens on "Open" "Gifts"). It isn't a
	-- countdown to anything you could miss: the gifts wait.
	local giftButton = buttons.Gifts
	local giftBar, giftFill = bar(giftButton, "GiftBar", Theme.Colors.Cash, Theme.Colors.CardLine, 0)
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
		Kit.stroke(frame, Theme.Colors.Stroke, Theme.Stroke.Bold).Name = "Outline"
		local plate = Instance.new("Frame") -- the white middle
		plate.Name = "Plate"
		plate.AnchorPoint = Vector2.new(0.5, 0.5)
		plate.Position = UDim2.fromScale(0.5, 0.5)
		plate.Size = UDim2.fromScale(0.78, 0.78)
		plate.BackgroundColor3 = Theme.Colors.Plate
		plate.BorderSizePixel = 0
		roundCorner(plate)
		Kit.stroke(plate, Theme.Colors.Stroke, Theme.Stroke.Fine)
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
		Kit.stroke(disc, Theme.Colors.Stroke, Theme.Stroke.Bold)
		disc.Parent = throw
		local cross = Kit.label({
			Name = "Cross",
			Text = "✖",
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
				ctx.toast("Hold ✖ to throw away")
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
	-- ⚙️ Settings: the comfort switches, Simple mode, the owner's helpers switch, Skip / Replay tutorial, ⚙️ More and
	-- 🛠️ Admin. Music.client follows MusicMuted and Feel/Atmosphere follows ReduceEffects, as before.
	--------------------------------------------------------------------------------------------------------------
	local settings = Hud.modal(ctx, {
		Name = "Settings",
		Title = "⚙️ Settings",
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

	local rows: { [string]: TextButton } = {}
	local function settingsRow(name: string, text: string): TextButton
		local button = Kit.button({
			Name = name,
			Kind = "Secondary",
			Text = text,
			TextScaled = true,
			Visible = false,
			Parent = scroll,
		})
		Kit.textLimit(button, Theme.TextSize.Body)
		rows[name] = button
		return button
	end
	local musicSwitch = settingsRow("Music", "")
	local effectsSwitch = settingsRow("Effects", "")
	local simpleSwitch = settingsRow("Simple", "") -- depth update: Simple mode (saved; the server rates it)
	local helpersSwitch = settingsRow("Helpers", "")
	local skipRow = settingsRow("Skip", "⏭️ Skip tutorial")
	local replayRow = settingsRow("Replay", "🔁 Replay tutorial")
	for piece, text in Pure.MORE do
		local row = settingsRow(piece, text)
		row.Activated:Connect(function()
			ctx.fire("Open", piece) -- a Panel: opening it closes ⚙️
		end)
	end
	local adminButton = settingsRow("Admin", "🛠️ Admin")
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

	-- 👥 Who may work at your clinic: only while you own one. Off = "👥 Friends only" (only you and your Roblox friends
	-- may work at your clinic), on = "🤝 Anyone can help". It shows your plot's OpenHelpers attribute; a tap asks the
	-- server (SetHelpers, Server/Visits), which checks you own the plot, switches it and toasts.
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
		helpersSwitch.Text = if open then "🤝 Anyone can help" else "👥 Friends only"
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
		Hud.pop(helpersSwitch, 1.06)
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
		local muted = player:GetAttribute("MusicMuted") == true
		musicSwitch.Text = if muted then "🔇 Music off" else "🎵 Music on"
		effectsSwitch.Text = if calmOn() then "💤 Calm effects" else "✨ Full effects"
		simpleSwitch.Text = if ctx.State.Simple == true then "👆 Simple taps" else "🎮 Mini-games"
		renderRows()
	end
	musicSwitch.Activated:Connect(function()
		player:SetAttribute("MusicMuted", player:GetAttribute("MusicMuted") ~= true)
		Hud.pop(musicSwitch, 1.06)
	end)
	effectsSwitch.Activated:Connect(function()
		player:SetAttribute("ReduceEffects", not calmOn())
		Hud.pop(effectsSwitch, 1.06)
	end)
	local askingSimple = false
	simpleSwitch.Activated:Connect(function()
		if askingSimple then
			return
		end
		askingSimple = true
		Hud.pop(simpleSwitch, 1.06)
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
	-- The Now card's own entries: the warnings (30) and the tracked goal (10)
	--------------------------------------------------------------------------------------------------------------
	local warnCard, _, warnIcon, warnText = nowCard("Warning", false)
	local goalCard, goalPlate, goalIcon, goalText = nowCard("Goal", true)
	goalText.AnchorPoint = Vector2.new(0, 0)
	goalText.Position = UDim2.fromOffset(WALLET_ICON + Theme.Space.Step[4], Theme.Space.Step[1])
	goalText.Size = UDim2.new(1, -(WALLET_ICON + Theme.Space.Step[5]), 0, 30)
	local goalTrack, goalFill = bar(goalPlate, "Bar", Theme.Colors.Collect, Theme.Colors.Shade, 0.4)
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
			warnIcon.Text, warnText.Text = "⚠️", "Not saving"
		elseif noPlot then
			warnIcon.Text, warnText.Text = "🏠", "Clinics full"
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
		local goal = if shown.Goals then Pure.trackedGoal(daily and daily.Goals, data.DailyGoals, data.Wings) else nil
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

	--------------------------------------------------------------------------------------------------------------
	-- Layout: the zone map on every resize
	--------------------------------------------------------------------------------------------------------------
	local function onRail(name: string): boolean
		return table.find(layout.Left, name) ~= nil or table.find(layout.Right, name) ~= nil
	end
	local function applyPiece(name: string)
		if name == "Stars" then
			starsButton.Visible = shown.Stars == true
		elseif name == "Status" then
			statusColumn.Visible = shown.Status == true
		else
			local button = buttons[name]
			if button then
				button.Visible = shown[name] == true and onRail(name)
			end
		end
	end
	local function pieceGui(name: string): GuiObject?
		if name == "Stars" then
			return starsButton
		elseif name == "Status" then
			return statusColumn
		end
		return buttons[name]
	end

	local renderStatus: () -> ()
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
		for _, name in HudZones.ORDER.LeftRail do
			targets[name] = if table.find(layout.More, name) then settingsButton else buttons[name]
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
			roundCorner(faceDisc)
			Kit.stroke(faceDisc, Theme.Colors.Stroke, Theme.Stroke.Fine)
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

		-- The rows that fit, the clock first.
		local want = {
			Clock = clock ~= "",
			Event = event ~= nil,
			Visitor = visitorText ~= nil,
			Boosts = next(boostChips) ~= nil,
		}
		local used = 0
		for _, name in Pure.STATUS_ORDER do
			local on = (want :: any)[name] == true and used < box.Rows
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
	-- The reveal: a new player's HUD grows with their tutorial step (see the header), in fixed slots
	--------------------------------------------------------------------------------------------------------------
	local BOUNCE: { [string]: number } = { Stars = 1.25, Shop = 1.45, Book = 1.45, Status = 1.12 }
	local curedSeen = false -- a cure landed this session: ⭐ shows with it, not a moment later with the snapshot
	local wasActive = false
	local queue: { string } = {}
	local staggering = false
	local function runStagger()
		if staggering then
			return
		end
		staggering = true
		task.spawn(function()
			while #queue > 0 do
				if celebrating() then
					task.wait(0.25) -- the finale's celebration first: the HUD pops in after it
				else
					local name = table.remove(queue, 1) :: string
					if not shown[name] then
						shown[name] = true
						applyPiece(name)
						renderRows()
						local piece = pieceGui(name)
						if piece and Kit.isShown(piece) then
							Hud.pop(piece, BOUNCE[name] or 1.3)
							Hud.sound("Pop", 0.5)
							task.wait(Pure.STAGGER)
						end
					end
				end
			end
			staggering = false
			renderGoal(ctx.State, false)
		end)
	end
	local function applyReveal(state: Types.Snapshot, animate: boolean)
		local step = state.Tutorial
		local reveal = Pure.reveal(step, curedSeen, (state :: any).TutorialReplay == true)
		local want: { [string]: boolean } = {
			Stars = reveal.Stars,
			Shop = reveal.Shop,
			Book = reveal.Book,
			Status = reveal.Rest,
		}
		for name in Pure.RAIL do
			if want[name] == nil then
				want[name] = reveal.Rest
			end
		end
		-- The tutorial just ended (finished or skipped): the rest pops in one piece at a time.
		local stagger = animate and wasActive and TutorialLogic.isDone(step) and not Hud.calm()
		wasActive = TutorialLogic.active(step)
		local appeared = false
		for _, name in { "Stars", table.unpack(Pure.REVEAL_ORDER) } do
			local on = want[name] == true
			local queued = table.find(queue, name)
			if not on then
				if queued then
					table.remove(queue, queued)
				end
				if shown[name] then
					shown[name] = false
					applyPiece(name)
				end
			elseif not shown[name] and not queued then
				if stagger and name ~= "Stars" then
					table.insert(queue, name)
				else
					shown[name] = true
					applyPiece(name)
					local piece = pieceGui(name)
					if animate and piece and piece.Visible then
						Hud.pop(piece, BOUNCE[name] or 1.3)
						appeared = true
					end
				end
			end
		end
		if #queue > 0 then
			runStagger()
		end
		if appeared then
			Hud.sound("Pop")
		end
		renderRows()
	end
	ctx.Remotes.Cured.OnClientEvent:Connect(function()
		curedSeen = true
		applyReveal(ctx.State, true)
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
			Hud.fly(nil, "💰", "Cash", Kit.Juice.coins(paid))
		end
	end)

	starsButton.Activated:Connect(function()
		Kit.Clicked:Fire(starsButton)
		if nextTip ~= "" then
			ctx.toast(nextTip)
		end
		Hud.pop(starsButton, 1.08)
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
			floatText(comboSticker, "×" .. tostring(multiplier) .. " 💰", Theme.Colors.Cash)
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
		giftFill.BackgroundColor3 = if ready then Theme.Colors.Collect else Theme.Colors.Cash
		Kit.setDot(giftButton, ready)
		if ready and not giftsWereReady and giftsShown and Kit.isShown(giftButton) then
			Hud.pop(giftButton, 1.2)
		end
		giftsWereReady = ready
		giftsShown = state ~= initial
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

	local loaded = false
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

		local passed, nextAt, icon, name = starTrack(data, state)
		local ratio = if nextAt then math.clamp(((state.Stars or 0) - passed) / (nextAt - passed), 0, 1) else 1
		nextIcon.Text = icon
		nextTip = if nextAt then icon .. " " .. name .. " at ⭐" .. nextAt else "👑 Everything unlocked!"
		fillTo(fill, ratio, animate)

		local mailReady = state.MailboxReady == true
		local goalsReady = goalReady(data, state)
		Kit.setDot(buttons.Mailbox, mailReady)
		local mailIcon = buttons.Mailbox:FindFirstChild("Icon")
		if mailIcon and mailIcon:IsA("TextLabel") then
			mailIcon.Text = if mailReady then "📬" else "📭"
		end
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
		Kit.setDot(buttons.Shop, shopTab ~= nil, if branchOnly then (if offer then "🃏" else "🌳") else nil)
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
