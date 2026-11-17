--!strict
-- Tutorial (client): the first-session tutorial's screen side (look build plan §B9 and §D T8;
-- docs/research/2026-11-16-tutorial-ux.md §3; memory-20261117-001/-002/-003). OWNER: T8.
-- The server owns the step (Snapshot.Tutorial, kept by Server/Tutorial); this module only shows it. It asks only
-- three things, each a remote the server checks: TutorialAck (the welcome sweep ended), TutorialSkip and
-- TutorialReplay (each behind Hud.confirm).
--   init(ctx)
--   Tutorial.Pure   the card words per device, the pips, the tab, the finale's "coming up" candidates, the confirm
--                   texts and the nurse's lines (tests/TutorialFlow loads the PURE block on its own)
--
-- THE CARD (the top-centre Now card: Hud.setNow("Tutorial", card, 20)). Navy (Theme.Colors.NowPlate), with:
--   · the "TUTORIAL n/7" tab in gold outlined display text, and a "⏭️ Skip" chip (a 56 x 44 hit area; never
--     selectable by a gamepad: pads use the ⚙️ row);
--   · a thumbnail of the target's icon on its colour (it flips to ✅ on success), a white caps title and a gold
--     subtitle with the device's own key ([E] from GetStringForKeyCode, the pad's real glyph from
--     GetImageForKeyCode; it switches live with PreferredInput);
--   · a 7-segment bar that fills on success and never drains (card 6 fills its segment by halves: two pips);
--   · the guide nurse's face (Hud.portrait(Data/Guide.Look); its name is a placeholder the screen never shows) peeking
--     out of the right edge with a 2-4-word line in a bubble under the card, and a Chirp.
--   It uses TextSize + AutomaticSize (not TextScaled), so Larger Text works; nothing is under 18 px. It is 88 px (76
--   under 500 px tall) plus its 24 px tab, and while a mini-game is up (HudMode "Game", or MiniGames open) it shrinks
--   to the 44 px slim strip ("TUTORIAL 3/7 · Tap the glowing tool, then play!"). While a Panel is open it steps out
--   of the slot.
-- The 7 cards (the Real Clinic design §13; Logic/Tutorial.card; words: Pure.words). "The patient" is the one the
-- Guide follows (UI/Guide.visit: the bay patient who has waited longest for the doctor):
--   1 PATIENT (and WELCOME after the sweep)  WELCOME, DOCTOR!   "🤧 A patient is coming!", then "🤧 A patient in bay
--                                            1!"; the pin 👀 and the glow on the patient, no beam
--   2 EXAMINE     PATIENT IN BAY 1           "Go to bay 1 · Examine [E]" / "Go to bay 1 · tap Examine"; the beam to
--                                            the bay (UI/Guide), the touch hand by its prompt
--   3 EXAMINE while the exam card is up      PICK THE GLOWING TOOL "Tap the glowing tool, then play!" (the slim strip;
--                                            "Pick the right tool, then play!" when it doesn't glow; the touch hand
--                                            on MiniGames.stage())
--   4 TREAT       GET THE PLASTER            "From the supply shelf · hold [E]" / "At the dispensary · hold [E]":
--                                            the plan's first step; the beam to its station. A dispensing card up
--                                            keeps card 4 (the slim strip shows its game's words)
--   5 TREAT once you carry it                TREAT YOUR PATIENT  "Back to bay 1 · Treat [E]" / "… · tap Treat"; the
--                                            beam back to the bay; the supply's game (the slim strip) plays on it
--   6 REST        WELL DONE, DOCTOR!         "You treated your first patient!": rays and confetti behind the
--                                            thumbnail (Kit.celebrate), held Config.Tutorial.FirstCureHold (also
--                                            when the payout comes at once and the step goes straight on to 7)
--   7 MORE        TREAT 3 MORE ○○○           follows the patient: "🤕 New patient! Check its bubble" / "Go to bay
--                                            2 · Examine [E]" / "It needs a 🧴!" / "Back to bay 2 · Treat [E]"; the
--                                            Guide's usual targets
--     SHOP, BOOK  UPGRADE YOUR CLINIC        card 7's last part. "Tap 🛒 · buy a ⚡" / "Click 🛒 · buy a ⚡" / "[A] on
--                                            🛒": the UI pointer (a 55% dim with a cutout round the 🛒 rail button, a
--                                            ring, a ripple and a tapping hand; in the Shop the cheapest upgrade's
--                                            Buy, "Buy this! ⚡"; a pad's focus through GuiService.SelectedObject). It
--                                            never says spend, and the pointer never lands on anything paid
-- SUCCESS BEATS: each card's ✓ holds Config.Tutorial.SuccessHold before the next slides in: the ✅, a 12-piece
--   confetti burst from the thumbnail, a Chime, the segment filling. Card 2 -> 3 is at once (the exam card is the
--   payoff), and so is 5's game.
-- THE FINALE: entering BOOK (the purchase) fires Celebrate { Kind = "Tutorial", Title = "YOU DID IT!", Chips, Next }
--   locally: Next = Logic/NextEvent.pick over Golden Hour (Workspace.GoldenStartsAt), the next night (PhaseEndsAt
--   while it's day) and the next play gift (FREE events only, red line 3; minutes, never seconds). When it closes
--   (bus "CelebrateClosed"), a ring sits on 📖 for BOOK_RING_SECONDS. The HUD's staggered reveal is Hud's (T5).
-- THE WELCOME: on the first-ever arrival the 3 s camera sweep plays under the title card (reduced motion: only the
--   title card); the client acks AS THE SWEEP ENDS (no welcome card), and the first patient is already hopping in.
-- SKIP (the card's chip, or the ⚙️ row: bus "SkipTutorial") opens Hud.confirm: "⏭️ Skip the tutorial?" · "You can
--   replay it any time from ⚙️" (binding text, memory-20261117-002) · "⏭️ Skip" · "Keep going" (the default). Then
--   the TutorialSkip remote. The Guide keeps its arrows until Config.Tutorial.ArrowsUntilCures cures.
-- REPLAY (the ⚙️ row: bus "ReplayTutorial") opens Hud.confirm: "🔁 Replay the tutorial?" · "Your waiting patients go
--   home" · "🔁 Replay" · "Not now" (the default). Then the TutorialReplay remote. A replay has no sweep, no gift and
--   the full HUD (Snapshot.TutorialReplay), and can be skipped again.
-- THE IDLE NUDGE: after Config.Tutorial.NudgeSeconds without progress on a walking step (Logic.nudge), the nurse says
--   "Psst! Follow the arrows →" and the beam brightens once (Wayfinder.flash). Once per step, never a number, and no
--   time counts while a panel is open.
-- For every owner (done players too): whenever your character arrives at your clinic (joining or respawning), the
-- camera turns to look the way the character faces, at the clinic (first-session design §A1).
-- Loops: the UI pointer's follow runs every frame only during the Shop step and the 📖 ring; the card itself never
-- loops.
-- Every motion honours Kit.reducedMotion(): the card appears instead of sliding, no confetti, the rays hold, the hand
-- and the ripple hold still (with the word "TAP"/"HOLD").

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local LogicFolder = Shared:WaitForChild("Logic")
local Prices = require(LogicFolder:WaitForChild("Prices"))
local Logic = require(LogicFolder:WaitForChild("Tutorial"))
local NextEvent = require(LogicFolder:WaitForChild("NextEvent"))
local PlaytimeLogic = require(LogicFolder:WaitForChild("Playtime"))
local HudZones = require(LogicFolder:WaitForChild("HudZones"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Wayfinder = require(script.Parent.Wayfinder)

-- Guide, Shop and MiniGames are optional: if one of them failed to load, the tutorial still runs without that part.
local function optional(name: string): any
	local ok, result = pcall(function()
		return require(script.Parent:WaitForChild(name, 5) :: ModuleScript)
	end)
	return if ok and type(result) == "table" then result else nil
end
local Guide = optional("Guide")
local Shop = optional("Shop")
local MiniGames = optional("MiniGames")

local Tutorial = {}

-- PURE-BEGIN
-- Words and small rules, no Roblox types: tests/TutorialFlow.spec loads this block on its own.
local Pure = {}

Pure.CARDS = 7
-- The confirms (look build plan §B9; the Skip line is binding text, memory-20261117-002, the one line over 6 words).
Pure.SKIP = {
	Title = "⏭️ Skip the tutorial?",
	Line = "You can replay it any time from ⚙️",
	Yes = "⏭️ Skip",
	No = "Keep going",
}
Pure.REPLAY = {
	Title = "🔁 Replay the tutorial?",
	Line = "Your waiting patients go home",
	Yes = "🔁 Replay",
	No = "Not now",
}
-- The guide nurse's lines (2-4 words; tutorial-ux §4).
Pure.SAY = {
	Hello = "Hi, Doctor!",
	Examined = "Great check-up!",
	Got = "Got it!",
	Rated = "Any ⭐ is great!",
	Treated = "You did it, Doctor!",
	OneMore = "One more!",
	Super = "Super job!",
	Upgrade = "Wow, an upgrade!",
	Nudge = "Psst! Follow the arrows →",
}
-- Card 7's pips live on this card's bar segment (Logic.MORE_CURES of them).
Pure.PIPS_CARD = 7
-- The finale (Celebrate Kind "Tutorial").
Pure.FINALE = {
	Title = "YOU DID IT!",
	Icon = "🎉",
	Chips = { "📖 Collect them all", "🎯 Daily goals", "👩‍⚕️ Hire nurses" },
}
Pure.SKIP_CHIP = "⏭️ Skip"
Pure.BUY_LABEL = "Buy this! ⚡"
-- The slim strip's words while a mini-game is up, per GameId (Logic/MiniGame; they mirror UI/MiniGames' own hints).
-- "Tap" = Simple mode's one tap. Card 3 (the exam) has words of its own: the tool pick comes first.
Pure.GAMES = {
	Listen = { Title = "LISTEN IN!", Sub = "Tap each glowing spot!", Icon = "🩺" },
	Temp = { Title = "TAKE ITS TEMPERATURE!", Sub = "Hold… let go in the green!", Icon = "🌡️" },
	Light = { Title = "CHECK WITH THE LIGHT!", Sub = "Tap when the ring lines up!", Icon = "🔦" },
	Look = { Title = "LOOK CLOSELY!", Sub = "Tap the sore spots!", Icon = "🔍" },
	XRay = { Title = "X-RAY TIME!", Sub = "Tap as it passes the bone!", Icon = "📸" },
	Plaster = { Title = "PUT ON THE PLASTER!", Sub = "Tap the sore spots!", Icon = "🩹" },
	Ice = { Title = "COOL IT DOWN!", Sub = "Hold… let go on ⭐", Icon = "🧊" },
	Bandage = { Title = "WRAP IT UP!", Sub = "Tap on each beat!", Icon = "🧻" },
	Cast = { Title = "PUT ON THE CAST!", Sub = "Tap on each beat!", Icon = "🦴" },
	Bath = { Title = "BATH TIME!", Sub = "Pop the bubbles!", Icon = "🛁" },
	Cocoa = { Title = "BLOW ON IT!", Sub = "Blow when it's biggest!", Icon = "☕" },
	Pick = { Title = "FIND THE BOTTLE!", Sub = "Tap the matching bottle!", Icon = "💊" },
	Dose = { Title = "MEASURE THE DOSE!", Sub = "Hold… let go on the line!", Icon = "🧴" },
	Tap = { Title = "TAP TO HELP!", Sub = "Tap to help!", Icon = "✨" },
}

export type Device = "Keyboard" | "Touch" | "Pad"
-- What the card can see right now (UI/Guide.visit, the carried items and the open session).
export type Situation = {
	Device: Device?,
	Bay: string?, -- the patient's bay ("1")
	AtBay: boolean?, -- it sits in its bay waiting for the doctor
	Examined: boolean?, -- its exam is done (its plan shows)
	Item: string?, -- the plan step to fetch or give: its NAME ("Plaster"), cards 4, 5 and 7
	Need: string?, -- that step's icon ("🩹")
	Where: ("Shelf" | "Dispensary" | "Room")?, -- card 4: where that step comes from
	Carrying: boolean?, -- you carry something it still needs
	Glow: boolean?, -- card 3: the right tool glows (first exams, Simple mode)
	Cures: number?, -- card 7: patients treated so far in step MORE
	Total: number?, -- card 7: to treat in all (Logic.MORE_CURES)
	Shop: boolean?, -- card 7's last part: the Shop step
	Game: string?, -- a mini-game is up: its Pure.GAMES key (the slim strip of cards 4 and 5)
	Narrow: boolean?, -- a phone-width text column: touch gets the shortest words (they must fit at 18 px)
}
-- A card's words. Key: a key chip in the subtitle ("Prompt" = the prompt's key E / ButtonX; "Confirm" = ButtonA),
-- after the words unless KeyFirst.
export type Words = { Title: string, Sub: string, Key: ("Prompt" | "Confirm")?, KeyFirst: boolean? }

-- The device the words are for, from UserInputService.PreferredInput's name (nil on an engine without it: then the
-- enabled inputs decide).
function Pure.device(preferred: string?, touch: boolean?, keyboard: boolean?, gamepad: boolean?): Device
	if preferred == "Touch" then
		return "Touch"
	elseif preferred == "Gamepad" or preferred == "MicroGamepad" then
		return "Pad"
	elseif preferred == "KeyboardAndMouse" then
		return "Keyboard"
	end
	if touch and not keyboard then
		return "Touch"
	end
	if gamepad and not keyboard then
		return "Pad"
	end
	return "Keyboard"
end

-- Words on screen: tokens with a letter or a digit (an emoji, "·" or "…" isn't a word).
function Pure.countWords(text: string): number
	local n = 0
	for token in string.gmatch(text, "%S+") do
		if string.find(token, "[%w]") then
			n += 1
		end
	end
	return n
end

-- "TUTORIAL 2/7"
function Pure.tab(card: number, cards: number?): string
	return "TUTORIAL " .. card .. "/" .. (cards or Pure.CARDS)
end

-- Card 7's pips: "○○○", "●○○", ... "●●●".
function Pure.pips(done: number, total: number): string
	local count = math.max(math.floor(total), 0)
	local filled = math.clamp(math.floor(done), 0, count)
	return string.rep("●", filled) .. string.rep("○", count - filled)
end

-- How full each bar segment is while `card` shows (1..cards): the cards before it are full, card 7 (PIPS_CARD)
-- fills a share per patient treated, and a card's own segment fills on its success.
function Pure.segments(card: number, success: boolean, cures: number?, total: number?, cards: number?): { number }
	local out: { number } = {}
	for index = 1, cards or Pure.CARDS do
		local fill = 0
		if index < card or (index == card and success) then
			fill = 1
		elseif index == card and card == Pure.PIPS_CARD and type(total) == "number" and total > 0 then
			fill = math.clamp((cures or 0) / total, 0, 1)
		end
		out[index] = fill
	end
	return out
end

-- An item's name for a caps title ("ICE PACK"), or nil when there isn't a short one (two words at most).
local function itemWords(name: string?): string?
	if type(name) ~= "string" or not string.match(name, "^[%a ]+$") then
		return nil
	end
	local count = 0
	for _ in string.gmatch(name, "%a+") do
		count += 1
	end
	return if count >= 1 and count <= 2 then string.upper(name) else nil
end

-- "Go to bay 1": the bay id, or "1" when it isn't known yet (the tutorial's patient takes the first free bay).
local function bayName(s: Situation): string
	return if type(s.Bay) == "string" and s.Bay ~= "" then s.Bay else "1"
end

-- Go to a bay and use its prompt ("Examine" or "Treat"): per device, the narrow phone line the shortest.
local function toBay(s: Situation, lead: string, action: string): (string, ("Prompt" | "Confirm")?)
	local bay = bayName(s)
	if s.Device == "Touch" then
		if s.Narrow then
			return "Tap " .. action .. " at bay " .. bay, nil
		end
		return lead .. " bay " .. bay .. " · tap " .. action, nil
	end
	return lead .. " bay " .. bay .. " · " .. action, "Prompt"
end

-- A game's words for the slim strip, or nil when no game is up.
local function gameWords(s: Situation): Words?
	local game = if s.Game then Pure.GAMES[s.Game] else nil
	return if game then { Title = game.Title, Sub = game.Sub } else nil
end

function Pure.words(card: number, s: Situation): Words
	local device = s.Device or "Keyboard"
	if card == 1 then
		local sub = if s.AtBay then "🤧 A patient in bay " .. bayName(s) .. "!" else "🤧 A patient is coming!"
		return { Title = "WELCOME, DOCTOR!", Sub = sub }
	elseif card == 2 then
		local sub, key = toBay(s, "Go to", "Examine")
		return { Title = "PATIENT IN BAY " .. bayName(s), Sub = sub, Key = key }
	elseif card == 3 then
		local glow = s.Glow ~= false
		local title = if glow then "PICK THE GLOWING TOOL" else "PICK THE RIGHT TOOL"
		if device == "Touch" and s.Narrow then
			return { Title = title, Sub = if glow then "Tap the glowing tool!" else "Pick the right tool!" }
		end
		return {
			Title = title,
			Sub = if glow then "Tap the glowing tool, then play!" else "Pick the right tool, then play!",
		}
	elseif card == 4 then
		local playing = gameWords(s)
		if playing then
			return playing -- the dispensing card is up: Pick the bottle, then the Dose
		end
		local word = itemWords(s.Item)
		local title = if word then "GET THE " .. word else "GET THE TREATMENT"
		if s.Where == "Dispensary" then
			if device == "Touch" then
				return {
					Title = title,
					Sub = if s.Narrow then "Hold 👆 Dispense" else "Dispensary · hold 👆 Dispense",
				}
			end
			return { Title = title, Sub = "At the dispensary · hold", Key = "Prompt" }
		elseif s.Where == "Shelf" then
			if device == "Touch" then
				return {
					Title = title,
					Sub = if s.Narrow then "Hold 👆 at the shelf" else "From the shelf · hold 👆",
				}
			end
			return { Title = title, Sub = "From the supply shelf · hold", Key = "Prompt" }
		end
		if device == "Touch" then
			return { Title = title, Sub = if s.Narrow then "Follow the arrows" else "Follow the arrows · hold 👆" }
		end
		return { Title = title, Sub = "Follow the arrows · hold", Key = "Prompt" }
	elseif card == 5 then
		local playing = gameWords(s)
		if playing then
			return playing -- the supply's own game, on the patient
		end
		local sub, key = toBay(s, "Back to", "Treat")
		return { Title = "TREAT YOUR PATIENT", Sub = sub, Key = key }
	elseif card == 6 then
		return {
			Title = "WELL DONE, DOCTOR!",
			Sub = if device == "Touch" and s.Narrow
				then "First patient treated!"
				else "You treated your first patient!",
		}
	elseif card == 7 then
		if s.Shop then
			if device == "Touch" then
				return { Title = "UPGRADE YOUR CLINIC", Sub = "Tap 🛒 · buy a ⚡" }
			elseif device == "Pad" then
				return { Title = "UPGRADE YOUR CLINIC", Sub = "on 🛒", Key = "Confirm", KeyFirst = true }
			end
			return { Title = "UPGRADE YOUR CLINIC", Sub = "Click 🛒 · buy a ⚡" }
		end
		local total = math.max(math.floor(s.Total or 3), 1)
		local title = "TREAT " .. total .. " MORE " .. Pure.pips(s.Cures or 0, total)
		if s.Carrying then
			local sub, key = toBay(s, "Back to", "Treat")
			return { Title = title, Sub = sub, Key = key }
		elseif s.AtBay and not s.Examined then
			local sub, key = toBay(s, "Go to", "Examine")
			return { Title = title, Sub = sub, Key = key }
		elseif s.AtBay and s.Need then
			return { Title = title, Sub = "It needs a " .. s.Need .. "!" }
		end
		return {
			Title = title,
			Sub = if s.Narrow then "🤕 Check its bubble" else "🤕 New patient! Check its bubble",
		}
	end
	return { Title = "", Sub = "" }
end

-- The finale's "coming up" candidates: FREE events only (memory-20261116-022; Logic/NextEvent never picks a paid
-- one either). goldenAt = Workspace.GoldenStartsAt, phaseEndsAt = Workspace.PhaseEndsAt (the night comes then while
-- it's day), giftSeconds = active play until the next play gift (nil when none is left today).
function Pure.candidates(
	now: number,
	goldenAt: any,
	isNight: boolean,
	phaseEndsAt: any,
	giftSeconds: any
): { { Id: string, Icon: string, Name: string, At: number } }
	local out = {}
	if type(goldenAt) == "number" then
		table.insert(out, { Id = "Golden", Icon = "🌟", Name = "Golden Hour", At = goldenAt })
	end
	if not isNight and type(phaseEndsAt) == "number" then
		table.insert(out, { Id = "Night", Icon = "🌙", Name = "Night", At = phaseEndsAt })
	end
	if type(giftSeconds) == "number" and giftSeconds > 0 then
		table.insert(out, { Id = "Gift", Icon = "🎁", Name = "Next gift", At = now + giftSeconds })
	end
	return out
end
-- PURE-END

Tutorial.Pure = Pure

------------------------------------------------------------------------------------------------------------------
-- Tuning (Config.Tutorial owns the shared numbers; these are this screen's own)
------------------------------------------------------------------------------------------------------------------

local CAMERA_SWEEP_SECONDS = 3
local TITLE_STILL_SECONDS = 2.6 -- reduced motion: the title card alone
local HOME_STUDS = 50 -- your character this close (flat) to your clinic's centre = arrived (Config.Town.PlotSize / 2
-- when it's known: anywhere on your own plot)
local HOME_WAIT_SECONDS = 4
local CAMERA_BACK = 13 -- the camera behind your character after a sweep or on arrival
local CAMERA_UP = 5.5
local SAY_SECONDS = 2.4 -- how long the nurse's line stays
local BOOK_RING_SECONDS = 4 -- the ring on 📖 after the finale
local RIPPLE_SECONDS = 1.2 -- the UI pointer's ripple and tap
local DIM = 0.55 -- the UI pointer's dim (Transparency)
local CONFETTI_STEP = 12 -- a step's burst
local PORTRAIT = 56 -- the nurse's face
local KEY_PX = 28 -- a key chip's height (and a glyph's size)
local SEGMENT_PX = 8
local NARROW_PX = 240 -- a text column under this is a phone's: the shortest words (Pure.words' Narrow)
local SUB_MIN_PX = 60 -- the subtitle never wraps narrower than this
local SKIP_HIT = Vector2.new(96, 44) -- the Skip chip's hit area (at least 56 x 44)
local TREAT_SETTLE = 0.6 -- after TreatDone, look again once the game card has closed
-- The supply shelf's stations (design §8.2): card 4 says "From the supply shelf" for these, "At the dispensary" for
-- a Dispense station, and "Follow the arrows" for the rest (the X-ray room's casts, the bought rooms).
local SHELF: { [string]: boolean } = { Plaster = true, Ice = true, Bandage = true }
-- The patient attributes the card's words follow (set by Server/Patients): a change re-renders it.
local PATIENT_ATTRIBUTES = { "Bay", "State", "Case", "Plan", "PlanDone", "Symptom", "QueueIndex" }

local player = Players.LocalPlayer

------------------------------------------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------------------------------------------

-- True when gui is on screen: it and every GuiObject above it are Visible, and its ScreenGui is enabled.
local function isShown(gui: GuiObject): boolean
	local node: Instance? = gui
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end
		elseif node:IsA("LayerCollector") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

local function device(): Device
	local preferred: string? = nil
	pcall(function()
		preferred = UserInputService.PreferredInput.Name
	end)
	return Pure.device(
		preferred,
		UserInputService.TouchEnabled,
		UserInputService.KeyboardEnabled,
		UserInputService.GamepadEnabled
	)
end

local function plotModel(state: Types.Snapshot): Model?
	local clinics = Workspace:FindFirstChild("Clinics")
	local index = state.PlotIndex
	local plot = if clinics and type(index) == "number" then clinics:FindFirstChild("Plot_" .. index) else nil
	return if plot and plot:IsA("Model") then plot else nil
end

local function rootOf(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Waits (up to `timeout`) for your character to stand on your clinic's plot: the server moves it there on joining
-- and on respawning. Returns its root part, or nil.
local function waitForHome(plot: Model, timeout: number, reach: number): BasePart?
	local started = os.clock()
	local centre = plot:GetPivot().Position
	while os.clock() - started < timeout do
		local root = rootOf()
		if root then
			local flat = (root.Position - centre) * Vector3.new(1, 0, 1)
			if flat.Magnitude < reach then
				return root
			end
		end
		task.wait(0.1)
	end
	return nil
end

-- The camera just behind your character, looking the way it faces (a little down, at the clinic).
local function behind(root: BasePart): CFrame
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local focus = root.Position + Vector3.new(0, 1.5, 0)
	return CFrame.lookAt(focus - look * CAMERA_BACK + Vector3.new(0, CAMERA_UP, 0), focus + look * 6)
end

-- The player's own controls rest during the sweep (the standard PlayerModule; skipped if it isn't there).
local function setControls(on: boolean)
	pcall(function()
		local scripts = player:FindFirstChildOfClass("PlayerScripts")
		local module = scripts and scripts:FindFirstChild("PlayerModule")
		if module and module:IsA("ModuleScript") then
			local controls = (require(module) :: any):GetControls()
			if on then
				controls:Enable()
			else
				controls:Disable()
			end
		end
	end)
end

local function round(gui: GuiObject, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = gui
end

------------------------------------------------------------------------------------------------------------------
-- The welcome: title card and camera sweep
------------------------------------------------------------------------------------------------------------------

-- The title card: a navy ribbon with the game's name, over a paw badge on still or turning rays.
local function showTitle(seconds: number)
	local gui = Kit.screen("TutorialTitle", Theme.DisplayOrder.Popup)
	local holder = Instance.new("Frame")
	holder.Name = "Title"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.36)
	holder.Size = UDim2.new(0.86, 0, 0, 140)
	holder.BackgroundTransparency = 1
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(620, 140)
	limit.Parent = holder
	holder.Parent = gui

	local ribbon = Instance.new("Frame")
	ribbon.Name = "Ribbon"
	ribbon.AnchorPoint = Vector2.new(0.5, 1)
	ribbon.Position = UDim2.fromScale(0.5, 1)
	ribbon.Size = UDim2.new(1, 0, 0, 84)
	ribbon.BackgroundColor3 = Theme.Colors.Header
	ribbon.BorderSizePixel = 0
	Kit.corner(ribbon, Theme.Radius.Large)
	Kit.stroke(ribbon, Theme.Colors.Stroke, Theme.Stroke.Panel)
	ribbon.ZIndex = 2 -- over the sunburst behind the icon
	ribbon.Parent = holder
	local text = Kit.label({
		Name = "Text",
		Text = "Welcome to Cure a Creature!",
		Outlined = true,
		TextScaled = true,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -36, 0, 52),
		ZIndex = 2,
		Parent = ribbon,
	})
	Kit.outline(text, Theme.Stroke.Title)
	Kit.textLimit(text, Theme.TextSize.Big)
	-- Our paw badge on top of the ribbon, on a little sunburst (behind it, ZIndex 0).
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0.5, 0)
	badge.Position = UDim2.fromScale(0.5, 0)
	badge.Size = UDim2.fromOffset(58, 58)
	badge.BackgroundTransparency = 1
	badge.ZIndex = 1
	badge.Parent = holder
	Kit.rays(badge, Theme.Colors.Cash)
	Kit.label({
		Name = "Icon",
		Text = "🐾",
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = badge,
	})

	Kit.popIn(holder)
	Hud.sound("Fanfare", 0.8)
	task.wait(seconds)
	Kit.popOut(holder, function()
		gui:Destroy()
	end)
end

-- Flies the camera from high above the street, round the clinic, down to just behind your character.
local function sweep(plot: Model, finish: CFrame, seconds: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local pivot = plot:GetPivot()
	local counter = plot:FindFirstChild("Counter")
	local look = if counter and counter:IsA("BasePart") then counter.Position else pivot.Position
	-- Plot-local -Z is toward the street: start high over the street and to the left, swing round to the right.
	local p0 = (pivot * CFrame.new(-30, 34, -66)).Position
	local p1 = (pivot * CFrame.new(26, 20, -40)).Position
	local p2 = finish.Position
	local f0 = look
	local f2 = finish.Position + finish.LookVector * 10
	camera.CameraType = Enum.CameraType.Scriptable
	local started = os.clock()
	while true do
		local t = math.clamp((os.clock() - started) / seconds, 0, 1)
		local e = TweenService:GetValue(t, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		local a = p0:Lerp(p1, e)
		local b = p1:Lerp(p2, e)
		camera.CFrame = CFrame.lookAt(a:Lerp(b, e), f0:Lerp(f2, e))
		if t >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
	camera.CameraType = Enum.CameraType.Custom
	camera.CFrame = finish
end

------------------------------------------------------------------------------------------------------------------

function Tutorial.init(ctx: Types.Ctx)
	local data = ctx.Data :: any
	local tuning = (ctx.Config :: any).Tutorial
	local guideLook = if type(data.Guide) == "table" then data.Guide.Look else nil
	local town = (ctx.Config :: any).Town
	local homeReach = if type(town) == "table" and type(town.PlotSize) == "number"
		then town.PlotSize / 2
		else HOME_STUDS

	--------------------------------------------------------------------------------------------------------------
	-- The card (offered to the HUD's Now slot; Hud places it and sets its width, the card sets its height)
	--------------------------------------------------------------------------------------------------------------
	local NAVY = Theme.Colors.NowPlate
	local TAB = Theme.Zone.NowTab
	local PAD = Theme.Space.Step[2]

	local card = Instance.new("Frame")
	card.Name = "TutorialCard"
	card.BackgroundTransparency = 1
	card.Size = UDim2.new(1, 0, 0, TAB + Theme.Zone.NowHeight)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Active = false -- touches go through to the world and the thumbstick (only Skip takes one)

	-- What slides in (the card itself belongs to the HUD's slot).
	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.BackgroundTransparency = 1
	inner.Size = UDim2.fromScale(1, 0)
	inner.AutomaticSize = Enum.AutomaticSize.Y
	inner.Parent = card

	local tab = Instance.new("Frame")
	tab.Name = "Tab"
	tab.Position = UDim2.fromOffset(Theme.Space.PadPanel, 0)
	tab.Size = UDim2.fromOffset(0, TAB + Theme.Radius.Small)
	tab.AutomaticSize = Enum.AutomaticSize.X
	tab.BackgroundColor3 = NAVY
	tab.BorderSizePixel = 0
	Kit.corner(tab, Theme.Radius.Small)
	Kit.stroke(tab, Theme.Colors.Stroke, Theme.Stroke.Bold)
	local tabPad = Instance.new("UIPadding")
	tabPad.PaddingLeft = UDim.new(0, Theme.Space.PadCard)
	tabPad.PaddingRight = UDim.new(0, Theme.Space.PadCard)
	tabPad.Parent = tab
	tab.Parent = inner
	local tabText = Kit.label({
		Name = "Text",
		Text = "",
		Outlined = true,
		TextColor3 = Theme.Colors.Cash,
		TextSize = Theme.TextSize.Caption,
		TextWrapped = false,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, TAB),
		Parent = tab,
	})

	-- Skip: a small chip with a 56 x 44 hit area, never a gamepad's focus (pads use the ⚙️ row).
	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.Text = ""
	skip.AutoButtonColor = false
	skip.BackgroundTransparency = 1
	skip.Selectable = false
	skip.AnchorPoint = Vector2.new(1, 0)
	skip.Position = UDim2.new(1, -Theme.Space.PadCard, 0, -10)
	skip.Size = UDim2.fromOffset(SKIP_HIT.X, SKIP_HIT.Y) -- at least the 56 x 44 hit area, wide enough for its words
	skip.ZIndex = 5
	skip.Parent = inner
	local skipChip = Kit.label({
		Name = "Chip",
		Text = Pure.SKIP_CHIP,
		TextColor3 = Theme.Colors.OnColor,
		TextSize = Theme.TextSize.Caption,
		TextWrapped = false,
		BackgroundColor3 = NAVY,
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, TAB + 2),
		ZIndex = 5,
		Parent = skip,
	})
	Kit.corner(skipChip, Theme.Radius.Small)
	Kit.stroke(skipChip, Theme.Colors.Stroke, Theme.Stroke.Fine)
	local skipPad = Instance.new("UIPadding")
	skipPad.PaddingLeft = UDim.new(0, Theme.Space.Step[2])
	skipPad.PaddingRight = UDim.new(0, Theme.Space.Step[2])
	skipPad.Parent = skipChip

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, TAB)
	body.Size = UDim2.new(1, 0, 0, Theme.Zone.NowHeight)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.BackgroundColor3 = NAVY
	body.BorderSizePixel = 0
	body.ZIndex = 2
	Kit.corner(body, Theme.Radius.Large)
	Kit.stroke(body, Theme.Colors.Stroke, Theme.Stroke.Bold)
	Kit.pad(body, PAD)
	body.Parent = inner
	-- The one shadow (Theme.Shadow), under the card only.
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.Position = UDim2.fromOffset(Theme.Shadow.Offset.X, TAB + Theme.Shadow.Offset.Y)
	shadow.Size = UDim2.new(1, 0, 0, Theme.Zone.NowHeight)
	shadow.BackgroundColor3 = Theme.Shadow.Color
	shadow.BackgroundTransparency = Theme.Shadow.Transparency
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 1
	Kit.corner(shadow, Theme.Radius.Large)
	shadow.Parent = inner

	local thumb = Instance.new("Frame")
	thumb.Name = "Thumb"
	thumb.Size = UDim2.fromOffset(72, 72)
	thumb.BorderSizePixel = 0
	thumb.ZIndex = 3
	Kit.corner(thumb, Theme.Radius.Medium)
	Kit.stroke(thumb, Theme.Colors.Stroke, Theme.Stroke.Fine)
	thumb.Parent = body
	local thumbIcon = Kit.label({
		Name = "Icon",
		Text = "",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.74, 0.74),
		ZIndex = 4,
		Parent = thumb,
	})
	-- Behind the thumbnail: the first cure's rays and confetti (Kit.celebrate).
	local burst = Instance.new("Frame")
	burst.Name = "Burst"
	burst.BackgroundTransparency = 1
	burst.Size = thumb.Size
	burst.ZIndex = 2
	burst.Parent = body

	local column = Instance.new("Frame")
	column.Name = "Text"
	column.BackgroundTransparency = 1
	column.AutomaticSize = Enum.AutomaticSize.Y
	column.ZIndex = 3
	column.Parent = body
	local columnList = Kit.list(column, Enum.FillDirection.Vertical, Theme.Space.Step[1])
	columnList.SortOrder = Enum.SortOrder.LayoutOrder
	local title = Kit.label({
		Name = "Title",
		Text = "",
		Outlined = true,
		TextSize = Theme.TextSize.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromScale(1, 0),
		LayoutOrder = 1,
		ZIndex = 3,
		Parent = column,
	})
	local subRow = Instance.new("Frame")
	subRow.Name = "SubRow"
	subRow.BackgroundTransparency = 1
	subRow.AutomaticSize = Enum.AutomaticSize.Y
	subRow.Size = UDim2.fromScale(1, 0)
	subRow.LayoutOrder = 2
	subRow.ZIndex = 3
	subRow.Parent = column
	local subList = Kit.list(subRow, Enum.FillDirection.Horizontal, Theme.Space.Step[2])
	subList.SortOrder = Enum.SortOrder.LayoutOrder
	subList.HorizontalAlignment = Enum.HorizontalAlignment.Left -- lines up with the title
	subList.VerticalAlignment = Enum.VerticalAlignment.Center
	subList.Wraps = true
	local sub = Kit.label({
		Name = "Sub",
		Text = "",
		TextColor3 = Theme.Colors.Cash,
		TextSize = Theme.TextSize.Body,
		TextWrapped = true, -- inside the column's width (subCap): it never runs off the card
		TextXAlignment = Enum.TextXAlignment.Left,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		LayoutOrder = 2,
		ZIndex = 3,
		Parent = subRow,
	})
	local subCap = Instance.new("UISizeConstraint") -- MaxSize.X follows the column (fitSub)
	subCap.Parent = sub
	local keyCap = Kit.label({ -- the keyboard's key ([E]) as a little white keycap
		Name = "Key",
		Text = "",
		TextColor3 = Theme.Colors.Ink,
		TextSize = Theme.TextSize.Caption,
		TextWrapped = false,
		BackgroundColor3 = Theme.Colors.Plate,
		BackgroundTransparency = 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(KEY_PX, KEY_PX),
		Visible = false,
		ZIndex = 3,
		Parent = subRow,
	})
	Kit.corner(keyCap, Theme.Radius.Small)
	Kit.stroke(keyCap, Theme.Colors.Stroke, Theme.Stroke.Fine)
	local keyPad = Instance.new("UIPadding")
	keyPad.PaddingLeft = UDim.new(0, Theme.Space.Step[2])
	keyPad.PaddingRight = UDim.new(0, Theme.Space.Step[2])
	keyPad.Parent = keyCap
	local glyph = Instance.new("ImageLabel") -- the pad's real button glyph (GetImageForKeyCode)
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.Size = UDim2.fromOffset(KEY_PX, KEY_PX)
	glyph.Visible = false
	glyph.ZIndex = 3
	glyph.Parent = subRow

	-- The bar: 7 segments that fill on success (card 7's by thirds: its Logic.MORE_CURES pips).
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundTransparency = 1
	bar.Size = UDim2.new(1, 0, 0, SEGMENT_PX)
	bar.LayoutOrder = 3
	bar.ZIndex = 3
	bar.Parent = column
	local barList = Kit.list(bar, Enum.FillDirection.Horizontal, Theme.Space.Step[1])
	barList.SortOrder = Enum.SortOrder.LayoutOrder
	local fills: { Frame } = {}
	local segments: { Frame } = {}
	local gap = Theme.Space.Step[1]
	for index = 1, Logic.CARDS do
		local segment = Instance.new("Frame")
		segment.Name = "Segment_" .. index
		segment.LayoutOrder = index
		segment.Size = UDim2.new(1 / Logic.CARDS, -gap * (Logic.CARDS - 1) / Logic.CARDS, 1, 0)
		segment.BackgroundColor3 = Kit.lighten(NAVY, 0.22)
		segment.BorderSizePixel = 0
		segment.ClipsDescendants = true
		segment.ZIndex = 3
		Kit.corner(segment, Theme.Radius.Small)
		segment.Parent = bar
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = Theme.Colors.Cash
		fill.BorderSizePixel = 0
		fill.ZIndex = 4
		Kit.corner(fill, Theme.Radius.Small)
		fill.Parent = segment
		if index == Pure.PIPS_CARD then
			for pip = 1, Logic.MORE_CURES - 1 do -- card 7's pips: a divider between each
				local divider = Instance.new("Frame")
				divider.Name = "Pips"
				divider.AnchorPoint = Vector2.new(0.5, 0)
				divider.Position = UDim2.fromScale(pip / Logic.MORE_CURES, 0)
				divider.Size = UDim2.new(0, Theme.Stroke.Fine, 1, 0)
				divider.BackgroundColor3 = NAVY
				divider.BorderSizePixel = 0
				divider.ZIndex = 5
				divider.Parent = segment
			end
		end
		fills[index] = fill
		segments[index] = segment
	end

	-- The slim strip (while a mini-game is up): the tab's words and the subtitle on one line.
	local slim = Kit.label({
		Name = "Slim",
		Text = "",
		RichText = true,
		TextColor3 = Theme.Colors.OnColor,
		TextSize = Theme.TextSize.Caption,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 3,
		Parent = body,
	})

	-- The guide nurse: its face peeks out of the right edge, its line in a bubble under the card.
	local nurse = Instance.new("Frame")
	nurse.Name = "Nurse"
	nurse.AnchorPoint = Vector2.new(1, 0.5)
	nurse.Position = UDim2.new(1, PAD + PORTRAIT / 3, 0.5, 0)
	nurse.Size = UDim2.fromOffset(PORTRAIT, PORTRAIT)
	nurse.BackgroundColor3 = Theme.Colors.Plate
	nurse.BorderSizePixel = 0
	nurse.Visible = false
	nurse.ZIndex = 6
	round(nurse, Theme.Radius.Round)
	Kit.stroke(nurse, Theme.Colors.Stroke, Theme.Stroke.Bold)
	nurse.Parent = body
	if guideLook then
		local face = Hud.portrait(guideLook)
		face.ZIndex = 7
		face.Parent = nurse
	end
	local bubble = Kit.label({
		Name = "Bubble",
		Text = "",
		TextColor3 = Theme.Colors.Ink,
		TextSize = Theme.TextSize.Body,
		TextWrapped = false,
		BackgroundColor3 = Theme.Colors.Plate,
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Theme.Space.PadCard, 0, TAB + Theme.Zone.NowHeight + Theme.Space.Step[2]),
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		Visible = false,
		ZIndex = 6,
		Parent = inner,
	})
	Kit.corner(bubble, Theme.Radius.Medium)
	Kit.stroke(bubble, Theme.Colors.Stroke, Theme.Stroke.Fine)
	Kit.pad(bubble, Theme.Space.Step[2])

	--------------------------------------------------------------------------------------------------------------
	-- The UI pointer (card 7, and the 📖 ring after the finale): over panels
	--------------------------------------------------------------------------------------------------------------
	local pointerGui = Kit.screen("TutorialPointer", Theme.DisplayOrder.Panel + 5)
	local dims: { Frame } = {}
	for _, name in { "DimTop", "DimBottom", "DimLeft", "DimRight" } do
		local dim = Instance.new("Frame")
		dim.Name = name
		dim.BackgroundColor3 = Theme.Colors.Shade
		dim.BackgroundTransparency = DIM
		dim.BorderSizePixel = 0
		dim.Active = false -- touches pass through
		dim.Visible = false
		dim.Parent = pointerGui
		table.insert(dims, dim)
	end
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.Visible = false
	Kit.corner(ring, Theme.Radius.Large)
	Kit.stroke(ring, Theme.Colors.Cash, Theme.Stroke.Panel)
	ring.Parent = pointerGui
	local ripple = Instance.new("Frame")
	ripple.Name = "Ripple"
	ripple.AnchorPoint = Vector2.new(0.5, 0.5)
	ripple.BackgroundTransparency = 1
	ripple.Visible = false
	Kit.corner(ripple, Theme.Radius.Large)
	local rippleStroke = Kit.stroke(ripple, Theme.Colors.Plate, Theme.Stroke.Bold)
	ripple.Parent = pointerGui
	local hand = Kit.label({
		Name = "Hand",
		Text = "👆",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(54, 54),
		Visible = false,
		Parent = pointerGui,
	})
	local handWord = Kit.label({
		Name = "Word",
		Text = "TAP",
		Outlined = true,
		TextSize = Theme.TextSize.Caption,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(72, 24),
		Visible = false,
		Parent = pointerGui,
	})
	local buyLabel = Kit.label({
		Name = "Label",
		Text = Pure.BUY_LABEL,
		Outlined = true,
		TextSize = Theme.TextSize.Body,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		Visible = false,
		Parent = pointerGui,
	})
	-- The mini-game's touch hand (cards 3 and 5, touch only), pressing on MiniGames.stage().
	local gameHand = Kit.label({
		Name = "GameHand",
		Text = "👆",
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(64, 64),
		Visible = false,
		Parent = pointerGui,
	})

	--------------------------------------------------------------------------------------------------------------
	-- State
	--------------------------------------------------------------------------------------------------------------
	local welcome: "None" | "Intro" | "Card" = "None"
	local acking = false
	local lastStep: number? = nil -- the last known server step (nil until the first real snapshot)
	local presented: number? = nil -- the card on show (nil = none)
	local offered = false -- the card is in the HUD's Now slot
	local slimNow = false
	local shortNow = false
	local holding = false -- a success beat is holding the old card
	local beatToken = 0
	local filled: { number } = table.create(Logic.CARDS, 0)
	local moment: number? = nil -- a card held on screen whatever the step says (card 6, the first patient treated)
	local celebrated = false -- card 6's moment has played this run
	local stopRays: (() -> ())? = nil
	local finaleFired = false
	local playing: string? = nil -- the open session's Kind ("Exam" | "Treat" | "Dispense"), nil = none
	local playGame: string? = nil -- its first game (a Pure.GAMES key), for the slim strip
	local playGlow = true -- an exam's tool glows (TreatSession.Glow)
	local playToken = 0
	local gotBeat = false -- card 4's ✓ (you picked the item up) has played since card 4 came
	local rated = false
	local saidHello = false
	local lastCures = 0
	local modes: { [string]: string } = {} -- open modals by name -> HudMode
	local bookRingUntil = 0
	local focusTarget: GuiObject? = nil

	local function panelOpen(): boolean
		for _, mode in modes do
			if mode == "Panel" then
				return true
			end
		end
		return false
	end

	local function gameOpen(): boolean
		for _, mode in modes do
			if mode == "Game" then
				return true
			end
		end
		local ok, open = pcall(function()
			return MiniGames ~= nil and MiniGames.isOpen()
		end)
		return ok and open == true
	end

	local function ack()
		if acking then
			return
		end
		acking = true
		task.spawn(function()
			local ok = Hud.ask(ctx.Remotes.TutorialAck)
			if not ok then
				acking = false -- the server also moves on by itself
			end
		end)
	end

	-- The guide nurse says a short line (only while the card shows).
	local sayToken = 0
	local function say(line: string)
		if not offered then
			return
		end
		sayToken += 1
		local mine = sayToken
		bubble.Text = line
		if Kit.reducedMotion() then
			nurse.Visible = true
			bubble.Visible = true
		else
			Kit.popIn(nurse)
			Kit.popIn(bubble)
		end
		Hud.sound("Chirp", 0.9)
		task.delay(SAY_SECONDS, function()
			if sayToken == mine then
				nurse.Visible = false
				bubble.Visible = false
			end
		end)
	end

	--------------------------------------------------------------------------------------------------------------
	-- What the card says
	--------------------------------------------------------------------------------------------------------------
	local function carried(): { string }
		local value = player:GetAttribute("Carry")
		return if type(value) == "string" and value ~= "" then string.split(value, ",") else {}
	end

	-- The visit the card follows (UI/Guide.visit: the bay patient to go to and what to do there); empty without it.
	local function visitNow(plot: Instance?): any
		if not plot or not Guide or type(Guide.visit) ~= "function" then
			return {}
		end
		local ok, visit = pcall(Guide.visit, plot, data, carried())
		return if ok and type(visit) == "table" then visit else {}
	end

	-- Any patient on your plot (card 1's pin while the first one walks in), the one in a bay first.
	local function anyPatient(plot: Instance?): Model?
		local folder = plot and plot:FindFirstChild("Patients")
		local found: Model? = nil
		for _, child in (if folder then folder:GetChildren() else {}) do
			if child:IsA("Model") and child.PrimaryPart then
				local bay = child:GetAttribute("Bay")
				if type(bay) == "string" and bay ~= "" then
					return child
				end
				found = found or child
			end
		end
		return found
	end

	-- A patient's face on the thumbnail: its case's icon once examined, else its symptom's emoji ("😷 cough cough").
	local function faceOf(patient: Model?): string?
		if not patient then
			return nil
		end
		local cases = rawget(data, "Cases")
		local case = patient:GetAttribute("Case")
		local row = if type(case) == "string" and type(cases) == "table" then rawget(cases, case) else nil
		if type(row) == "table" and type(row.Icon) == "string" then
			return row.Icon
		end
		local symptom = patient:GetAttribute("Symptom")
		return if type(symptom) == "string" then string.match(symptom, "^(%S+)") else nil
	end

	type Look = {
		Situation: Situation,
		Face: string, -- the patient's icon
		ItemIcon: string?, -- the plan step's icon
		StationIcon: string?,
		StationColor: Color3?,
		Patient: Model?, -- the patient the card follows (UI/Guide.visit)
	}

	-- A phone-width text column (the shortest words). Before the column has a width, the short screen decides.
	local function narrowColumn(): boolean
		local width = column.AbsoluteSize.X
		if width > 0 then
			return width < NARROW_PX
		end
		local camera = Workspace.CurrentCamera
		return camera ~= nil and camera.ViewportSize.Y < HudZones.NOW_SHORT_BREAK
	end
	local narrowShown = narrowColumn()

	-- What the card can see right now (one read of the plot per render).
	local function look(): Look
		local state = ctx.State
		local plot = plotModel(state)
		local visit = visitNow(plot)
		local patient: Model? = visit.Patient
		local itemId: string? = visit.Item
		local item = if itemId then rawget(data.Items, itemId) else nil
		local stationId: string? = if type(item) == "table" then item.Station else nil
		local station = if stationId then rawget(data.Stations, stationId) else nil
		local where: ("Shelf" | "Dispensary" | "Room")? = nil
		if type(station) == "table" and station.Dispense == true then
			where = "Dispensary"
		elseif stationId and SHELF[stationId] then
			where = "Shelf"
		elseif stationId then
			where = "Room"
		end
		local step = state.Tutorial
		local situation: Situation = {
			Device = device(),
			Bay = visit.Bay,
			AtBay = patient ~= nil,
			Examined = visit.Do == "Treat" or visit.Do == "Fetch",
			Item = if type(item) == "table" then item.Name else nil,
			Need = if type(item) == "table" then item.Icon else nil,
			Where = where,
			Carrying = visit.Do == "Treat",
			Glow = playGlow,
			Cures = math.clamp(state.TutorialCures or 0, 0, Logic.MORE_CURES),
			Total = Logic.MORE_CURES,
			Shop = type(step) == "number" and step >= Logic.SHOP,
			Game = if playing == "Treat" or playing == "Dispense" then playGame else nil,
			Narrow = narrowShown,
		}
		return {
			Situation = situation,
			Face = faceOf(patient or anyPatient(plot)) or "🤧",
			ItemIcon = if type(item) == "table" then item.Icon else nil,
			StationIcon = if type(station) == "table" then station.Icon else nil,
			StationColor = if type(station) == "table" then station.Color else nil,
			Patient = patient,
		}
	end

	-- The thumbnail for a card: its icon and its colour.
	local function thumbOf(cardNumber: number, entry: Look): (string, Color3)
		local s = entry.Situation
		local game = if s.Game then Pure.GAMES[s.Game] else nil
		if cardNumber == 1 then
			return entry.Face, Theme.Colors.Pink
		elseif cardNumber == 2 or cardNumber == 3 then
			return "🩺", Theme.Colors.Collect
		elseif cardNumber == 4 then
			if game then
				return game.Icon, Theme.Colors.Purple
			end
			return entry.StationIcon or entry.ItemIcon or "🧰", entry.StationColor or Theme.Colors.Purple
		elseif cardNumber == 5 then
			return if game then game.Icon else entry.ItemIcon or entry.Face, Theme.Colors.Collect
		elseif cardNumber == 6 then
			return "🎉", Theme.Colors.Cyan
		elseif cardNumber == 7 then
			if s.Shop then
				return "🛒", Theme.Colors.Cash
			elseif s.Carrying then
				return entry.ItemIcon or entry.Face, Theme.Colors.Collect
			elseif s.AtBay and not s.Examined then
				return "🩺", Theme.Colors.Collect
			elseif s.AtBay and entry.StationIcon then
				return entry.StationIcon, entry.StationColor or Theme.Colors.Purple
			end
			return "🤕", Theme.Colors.Pink
		end
		return "🤧", Theme.Colors.Pink
	end

	-- The subtitle wraps inside its column: the column's width, less the key chip's when one shows.
	local function fitSub()
		local width = column.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local chip = 0
		if keyCap.Visible then
			chip = math.max(keyCap.AbsoluteSize.X, KEY_PX + Theme.Space.Step[2] * 2) + Theme.Space.Step[2]
		elseif glyph.Visible then
			chip = KEY_PX + Theme.Space.Step[2]
		end
		local cap = math.max(SUB_MIN_PX, math.floor(width - chip))
		if subCap.MaxSize.X ~= cap then
			subCap.MaxSize = Vector2.new(cap, math.huge)
		end
	end
	column:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitSub)
	keyCap:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitSub)

	-- The card and its shadow follow the body when two lines of words make it taller (never in the slim strip).
	local function fitCard()
		if slimNow then
			return
		end
		local base = if shortNow then Theme.Zone.NowHeightShort else Theme.Zone.NowHeight
		local height = math.max(base, math.ceil(body.AbsoluteSize.Y))
		if card.Size.Y.Offset ~= TAB + height then
			card.Size = UDim2.new(card.Size.X.Scale, card.Size.X.Offset, 0, TAB + height)
			shadow.Size = UDim2.new(1, 0, 0, height)
			bubble.Position = UDim2.new(1, -Theme.Space.PadCard, 0, TAB + height + Theme.Space.Step[2])
		end
	end
	body:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitCard)

	-- The key chip: the prompt's key (E, or the pad's X glyph) or the pad's confirm (A).
	local function showKeyChip(key: ("Prompt" | "Confirm")?, first: boolean)
		keyCap.Visible = false
		glyph.Visible = false
		if not key then
			return
		end
		local order = if first then 1 else 3
		if device() == "Pad" then
			local code = if key == "Confirm" then Enum.KeyCode.ButtonA else Enum.KeyCode.ButtonX
			local ok, image = pcall(function()
				return UserInputService:GetImageForKeyCode(code)
			end)
			if ok and type(image) == "string" and image ~= "" then
				glyph.Image = image
				glyph.LayoutOrder = order
				glyph.Visible = true
				return
			end
			keyCap.Text = if key == "Confirm" then "A" else "X"
		else
			local ok, text = pcall(function()
				return UserInputService:GetStringForKeyCode(Enum.KeyCode.E)
			end)
			keyCap.Text = if ok and type(text) == "string" and text ~= "" then string.upper(text) else "E"
		end
		keyCap.LayoutOrder = order
		keyCap.Visible = true
	end
	local function showKey(key: ("Prompt" | "Confirm")?, first: boolean)
		showKeyChip(key, first)
		fitSub()
	end

	-- The bar: each segment to its fill (Theme.Tween.Fill; at once when calm). Never drains within a run.
	local function paintBar(target: { number }, animate: boolean)
		for index, fill in fills do
			local want = math.max(target[index] or 0, if filled[index] then filled[index] else 0)
			if want ~= filled[index] then
				filled[index] = want
				local size = UDim2.fromScale(want, 1)
				if animate and not Kit.reducedMotion() then
					TweenService:Create(fill, Theme.Tween.Fill, { Size = size }):Play()
					Kit.bump(segments[index])
				else
					fill.Size = size
				end
			end
		end
	end

	-- Sizes for the screen (88 px, or 76 on a screen under 500 px tall), or the 44 px slim strip.
	local function layout(slimStrip: boolean)
		local camera = Workspace.CurrentCamera
		local short = camera ~= nil and camera.ViewportSize.Y < HudZones.NOW_SHORT_BREAK
		slimNow, shortNow = slimStrip, short
		local height = if short then Theme.Zone.NowHeightShort else Theme.Zone.NowHeight
		local side = height - PAD * 2
		tab.Visible = not slimStrip
		skip.Visible = not slimStrip
		thumb.Visible = not slimStrip
		column.Visible = not slimStrip
		slim.Visible = slimStrip
		if slimStrip then
			body.AutomaticSize = Enum.AutomaticSize.None
			body.Position = UDim2.fromOffset(0, 0)
			body.Size = UDim2.new(1, 0, 0, Theme.Zone.NowSlim)
			shadow.Position = UDim2.fromOffset(Theme.Shadow.Offset.X, Theme.Shadow.Offset.Y)
			shadow.Size = body.Size
			bubble.Position = UDim2.new(1, -Theme.Space.PadCard, 0, Theme.Zone.NowSlim + Theme.Space.Step[2])
			card.Size = UDim2.new(card.Size.X.Scale, card.Size.X.Offset, 0, Theme.Zone.NowSlim)
			return
		end
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.Position = UDim2.fromOffset(0, TAB)
		body.Size = UDim2.new(1, 0, 0, height)
		bubble.Position = UDim2.new(1, -Theme.Space.PadCard, 0, TAB + height + Theme.Space.Step[2])
		shadow.Position = UDim2.fromOffset(Theme.Shadow.Offset.X, TAB + Theme.Shadow.Offset.Y)
		shadow.Size = body.Size
		thumb.Size = UDim2.fromOffset(side, side)
		burst.Size = thumb.Size
		column.Position = UDim2.fromOffset(side + Theme.Space.PadCard, 0)
		column.Size = UDim2.new(1, -(side + Theme.Space.PadCard + PORTRAIT / 2), 0, 0)
		title.TextSize = if short then Theme.TextSize.Button else Theme.TextSize.Title
		sub.TextSize = if short then Theme.TextSize.Caption else Theme.TextSize.Body
		card.Size = UDim2.new(card.Size.X.Scale, card.Size.X.Offset, 0, TAB + height)
		fitSub()
		fitCard()
	end

	-- The card number on screen right now, or nil for no card.
	local function wantedCard(entry: Look): number?
		local state = ctx.State
		local step = state.Tutorial
		if not Logic.active(step) or state.PlotIndex == nil then
			return nil
		end
		if moment then
			return moment -- card 6's moment holds whatever the step says
		end
		if step == Logic.WELCOME and welcome ~= "Card" then
			return nil -- the title card and sweep come first
		end
		if finaleFired and step >= Logic.BOOK then
			return nil -- the finale took over
		end
		return Logic.card(step, playing, entry.Situation.Carrying)
	end

	-- Offers or withdraws the card (the HUD's slot shows the highest priority).
	local function offer(on: boolean)
		if on then
			Hud.setNow("Tutorial", card, 20)
		elseif offered then
			Hud.setNow("Tutorial", nil, 20)
		end
		offered = on
	end

	local syncPointer: () -> () = function() end
	local armNudge: (fresh: boolean) -> () = function(_fresh: boolean) end
	local beat: (cardNumber: number, hold: number, line: string?, after: (() -> ())?) -> ()

	-- Shows `cardNumber` (sliding in when it's new), with its words for the moment.
	local function present(cardNumber: number, entry: Look)
		local fresh = presented ~= cardNumber
		local words = Pure.words(cardNumber, entry.Situation)
		if fresh then
			presented = cardNumber
			if cardNumber == 4 then
				gotBeat = false -- card 4 again (the item was set down): its ✓ may play again
			end
			if stopRays then
				stopRays()
				stopRays = nil
			end
			paintBar(Pure.segments(cardNumber, false), false)
		end
		if cardNumber == Pure.PIPS_CARD then
			paintBar(Pure.segments(cardNumber, false, entry.Situation.Cures, entry.Situation.Total), true)
		end
		tabText.Text = Pure.tab(cardNumber, Logic.CARDS)
		local changedTitle = title.Text ~= words.Title
		title.Text = words.Title
		sub.Text = words.Sub
		sub.LayoutOrder = 2
		showKey(words.Key, words.KeyFirst == true)
		local icon, color = thumbOf(cardNumber, entry)
		thumbIcon.Text = icon
		thumb.BackgroundColor3 = color
		slim.Text = '<font color="#'
			.. Theme.Colors.Cash:ToHex()
			.. '">'
			.. Pure.tab(cardNumber, Logic.CARDS)
			.. "</font>  "
			.. words.Sub
		local wantSlim = cardNumber == 3 or gameOpen()
		if wantSlim ~= slimNow or fresh then
			layout(wantSlim)
			if offered then
				Hud.setNow("Tutorial", card, 20) -- its height changed: the slot measures it again
			end
		end
		if fresh then
			offer(true)
			if not Kit.reducedMotion() then
				inner.Position = UDim2.fromOffset(0, -Theme.Space.Step[5])
				TweenService:Create(inner, Theme.Tween.Slide, { Position = UDim2.fromOffset(0, 0) }):Play()
			else
				inner.Position = UDim2.fromOffset(0, 0)
			end
			Hud.sound("Pop", 0.8)
			if cardNumber == 1 and not saidHello then
				saidHello = true
				task.delay(0.4, say, Pure.SAY.Hello)
			end
			armNudge(true)
		elseif changedTitle and not Kit.reducedMotion() then
			Kit.punch(title, 1.12, Theme.Tween.Bump)
		end
	end

	local function renderCard()
		local entry = look()
		local wanted = wantedCard(entry)
		local hidden = wanted == nil or panelOpen()
		if hidden then
			if offered then
				offer(false)
			end
			if wanted == nil and not holding then
				presented = nil
			end
			syncPointer()
			return
		end
		if holding then
			if not offered and presented then
				offer(true)
				layout(slimNow)
			end
			syncPointer()
			return -- the ✓ beat holds the old card; the hold's end renders the new one
		end
		if not offered and presented == wanted then
			offer(true) -- back after a panel closed: no re-pop
			layout(slimNow)
		end
		if presented == 4 and wanted == 5 and playing == nil and offered and not gotBeat then
			gotBeat = true
			beat(4, tuning.SuccessHold, Pure.SAY.Got) -- you picked it up: the ✓, then card 5
			syncPointer()
			return
		end
		present(wanted :: number, entry)
		syncPointer()
	end
	-- The slim strip is the one line to read during the mini-game: it draws over the game's shade (Hud.liftNow),
	-- and UI/MiniGames keeps its card clear of it.
	local function render()
		renderCard()
		Hud.liftNow(offered and slimNow and gameOpen())
	end

	--------------------------------------------------------------------------------------------------------------
	-- Success beats
	--------------------------------------------------------------------------------------------------------------
	-- The ✓ on `cardNumber`: the ✅, its segment, a burst from the thumbnail, a Chime and maybe a line; then (after
	-- `hold` seconds) the next card. `after` runs when the hold ends.
	beat = function(cardNumber: number, hold: number, line: string?, after: (() -> ())?)
		if presented ~= cardNumber or not offered then
			-- Not on screen (a panel is open, or it went past too fast): just fill its segment.
			paintBar(Pure.segments(cardNumber, true), false)
			if after then
				after()
			end
			render()
			return
		end
		beatToken += 1
		local mine = beatToken
		holding = true
		thumbIcon.Text = "✅"
		thumb.BackgroundColor3 = Theme.Colors.Collect
		if not Kit.reducedMotion() then
			Kit.bump(thumb)
			local centre = thumb.AbsolutePosition - inner.AbsolutePosition + thumb.AbsoluteSize / 2
			Kit.confetti(inner, CONFETTI_STEP, UDim2.fromOffset(centre.X, centre.Y))
		end
		paintBar(Pure.segments(cardNumber, true), true)
		Hud.sound("Chime")
		if line then
			say(line)
		end
		task.delay(hold, function()
			if beatToken ~= mine then
				return
			end
			holding = false
			if after then
				after()
			end
			render()
		end)
	end

	-- The first patient treated (card 6): it slides in with rays and confetti behind the thumbnail and is held
	-- FirstCureHold whatever the step says (at Lv 1 the payout comes at once and the step goes straight on to card 7),
	-- then the step's own card. Once per run.
	local function treatedMoment()
		if celebrated then
			render()
			return
		end
		celebrated = true
		beatToken += 1
		local mine = beatToken
		holding = false
		moment = 6
		render() -- card 6 slides in (unless a panel is open: then it just fills its segment)
		local shown = presented == 6 and offered
		paintBar(Pure.segments(6, true), shown)
		if shown then
			if not Kit.reducedMotion() then
				Kit.punch(title, 1.3, Theme.Tween.Bump)
			end
			stopRays = Kit.celebrate(burst, Theme.Colors.Cash)
			Hud.sound("Celebrate")
			say(Pure.SAY.Treated)
		end
		holding = true
		task.delay(tuning.FirstCureHold, function()
			if beatToken ~= mine then
				return
			end
			holding = false
			moment = nil
			if stopRays then
				stopRays()
				stopRays = nil
			end
			render()
		end)
	end

	-- The finale (Celebrate Kind "Tutorial"), with ONE free event coming up.
	local function fireFinale()
		finaleFired = true
		local now = Workspace:GetServerTimeNow()
		local giftSeconds: number? = nil
		pcall(function()
			local save, day = Hud.livePlay(ctx.State)
			local index, left = PlaytimeLogic.nextGift(save, day, data.Playtime.Gifts)
			if index then
				giftSeconds = left
			end
		end)
		local candidates = Pure.candidates(
			now,
			Workspace:GetAttribute("GoldenStartsAt"),
			Workspace:GetAttribute("IsNight") == true,
			Workspace:GetAttribute("PhaseEndsAt"),
			giftSeconds
		)
		local info: Types.CelebrateInfo = {
			Kind = "Tutorial",
			Title = Pure.FINALE.Title,
			Icon = Pure.FINALE.Icon,
			Chips = table.clone(Pure.FINALE.Chips),
			Next = NextEvent.pick(now, candidates :: any),
		}
		ctx.fire("Celebrate", info)
	end

	-- A new run (a Replay, or the admin restart): the bar and the beats start again.
	local function resetRun()
		beatToken += 1
		holding = false
		presented = nil
		filled = table.create(Logic.CARDS, 0)
		for _, fill in fills do
			fill.Size = UDim2.fromScale(0, 1)
		end
		moment = nil
		celebrated = false
		finaleFired = false
		playing = nil
		playGame = nil
		gotBeat = false
		rated = false
		saidHello = false
		lastCures = 0
		if stopRays then
			stopRays()
			stopRays = nil
		end
	end

	-- A server step change: the right beat for it.
	local function onStep(from: number?, to: number)
		if from == nil or from == to then
			return
		end
		if not Logic.active(from) and Logic.active(to) then
			resetRun()
			-- A replay has no sweep; the admin's restart (back to the welcome) plays it again as you respawn.
			welcome = if ctx.State.TutorialReplay == true or to ~= Logic.WELCOME then "Card" else "None"
			return
		end
		if to == Logic.DONE then
			-- Skipped (or the admin's finish): no beats; the Guide keeps its arrows until 3 patients are treated.
			beatToken += 1
			holding = false
			moment = nil
			return
		end
		if from == Logic.SHOP and to == Logic.BOOK then
			beat(7, tuning.SuccessHold, Pure.SAY.Upgrade, fireFinale)
			return
		end
		if from == Logic.MORE and to == Logic.SHOP then
			beat(7, tuning.SuccessHold, Pure.SAY.Super) -- the last of the 3; then card 7's Shop words
			return
		end
		if from <= Logic.TREAT and (to == Logic.REST or to == Logic.MORE) then
			treatedMoment() -- the first patient is treated (straight to MORE when it paid out at once)
			return
		end
		if from == Logic.REST and to == Logic.MORE then
			treatedMoment() -- after its ward rest: plays now unless it already did
			return
		end
		local a = Logic.card(from, if presented == 3 then "Exam" else nil)
		local b = Logic.card(to)
		if a and b and b > a then
			beat(a, tuning.SuccessHold, if a == 3 or a == 2 then Pure.SAY.Examined else nil)
		end
	end

	--------------------------------------------------------------------------------------------------------------
	-- The idle nudge: once per walking step, never a number, paused while a panel is open
	--------------------------------------------------------------------------------------------------------------
	local nudgeThread: thread? = nil
	local nudgeLeft = tuning.NudgeSeconds
	local nudgeStarted = 0
	local nudged: { [number]: boolean } = {}

	local function stopNudge()
		local thread = nudgeThread
		if thread then
			nudgeThread = nil
			pcall(task.cancel, thread)
		end
	end

	armNudge = function(fresh: boolean)
		stopNudge()
		if fresh then
			nudgeLeft = tuning.NudgeSeconds
		end
		local step = ctx.State.Tutorial
		if not Logic.nudge(step) or nudged[step] or panelOpen() or not offered then
			return
		end
		nudgeStarted = os.clock()
		nudgeThread = task.delay(nudgeLeft, function()
			nudgeThread = nil
			if ctx.State.Tutorial == step and not nudged[step] and not panelOpen() and offered then
				nudged[step] = true
				nudgeLeft = tuning.NudgeSeconds
				say(Pure.SAY.Nudge)
				Wayfinder.flash()
			end
		end)
	end

	local function pauseNudge()
		if nudgeThread then
			nudgeLeft = math.max(0, nudgeLeft - (os.clock() - nudgeStarted))
			stopNudge()
		end
	end

	--------------------------------------------------------------------------------------------------------------
	-- The UI pointer: the Shop step's dim, ring, ripple and hand, and the 📖 ring after the finale
	--------------------------------------------------------------------------------------------------------------
	local function cheapestUpgrade(): (string?, number)
		local best: string?, bestPrice = nil, math.huge
		local levels = ctx.State.Upgrades or {}
		for _, id in data.Upgrades.Order do
			local price = Prices.upgradePrice(data.Upgrades, id, levels[id] or 0)
			if price and price < bestPrice then
				best, bestPrice = id, price
			end
		end
		return best, bestPrice
	end

	-- The dim round the 🛒 only when there is something they can buy: never on a replay (no gift, so maybe nothing
	-- is affordable; the server moves the step on by itself then), never with every upgrade maxed.
	local function shopDim(): boolean
		if ctx.State.TutorialReplay == true then
			return false
		end
		local id, price = cheapestUpgrade()
		local cash = ctx.State.Cash
		return id ~= nil and type(cash) == "number" and cash >= price
	end

	-- What the pointer points at, whether it dims round it, and whether it carries the "Buy this!" label.
	local function uiTarget(): (GuiObject?, boolean, boolean)
		local step = ctx.State.Tutorial
		if step == Logic.SHOP and not finaleFired then
			if Hud.isOpen("Shop") then
				local id = cheapestUpgrade()
				local okButton, button = pcall(function()
					return if Shop and id then Shop.upgradeButton(id) else nil
				end)
				if okButton and button and isShown(button) then
					return button, false, true
				end
				local okTab, shopTab = pcall(function()
					return if Shop then Shop.tabButton("Upgrades") else nil
				end)
				return if okTab and shopTab and isShown(shopTab) then shopTab else nil, false, false
			end
			if Hud.isOpen() then
				return nil, false, false
			end
			local shop = Hud.target("Shop")
			return if shop and isShown(shop) then shop else nil, shopDim(), false
		end
		if bookRingUntil > os.clock() and not Hud.isOpen() then
			local book = Hud.target("Book")
			return if book and isShown(book) then book else nil, false, false
		end
		return nil, false, false
	end

	local function hidePointer()
		for _, dim in dims do
			dim.Visible = false
		end
		ring.Visible = false
		ripple.Visible = false
		hand.Visible = false
		handWord.Visible = false
		buyLabel.Visible = false
	end

	local function followLayout()
		debug.profilebegin("Tutorial pointer")
		local target, dimmed, labelled = uiTarget()
		if not (target and target.AbsoluteSize.X > 0) then
			hidePointer()
			debug.profileend()
			return
		end
		local origin = pointerGui.AbsolutePosition
		local screen = pointerGui.AbsoluteSize
		local at = target.AbsolutePosition - origin
		local size = target.AbsoluteSize
		local margin = Theme.Space.Step[2]
		local x0, y0 = at.X - margin, at.Y - margin
		local x1, y1 = at.X + size.X + margin, at.Y + size.Y + margin
		ring.Position = UDim2.fromOffset(x0, y0)
		ring.Size = UDim2.fromOffset(x1 - x0, y1 - y0)
		ring.Visible = true
		-- The dim: four frames round the cutout, reaching well past the safe area.
		local bleed = 400
		local rects = {
			{ -bleed, -bleed, screen.X + bleed * 2, y0 + bleed },
			{ -bleed, y1, screen.X + bleed * 2, screen.Y - y1 + bleed },
			{ -bleed, y0, x0 + bleed, y1 - y0 },
			{ x1, y0, screen.X - x1 + bleed, y1 - y0 },
		}
		for index, dim in dims do
			local r = rects[index]
			dim.Position = UDim2.fromOffset(r[1], r[2])
			dim.Size = UDim2.fromOffset(math.max(r[3], 0), math.max(r[4], 0))
			dim.Visible = dimmed
		end
		-- The ripple and the tapping hand share one rhythm; still (with the word) when calm.
		local still = Kit.reducedMotion()
		local centre = Vector2.new((x0 + x1) / 2, (y0 + y1) / 2)
		local phase = (os.clock() % RIPPLE_SECONDS) / RIPPLE_SECONDS
		ripple.Visible = not still
		if not still then
			local grow = 1 + phase * 0.35
			ripple.Position = UDim2.fromOffset(centre.X, centre.Y)
			ripple.Size = UDim2.fromOffset((x1 - x0) * grow, (y1 - y0) * grow)
			rippleStroke.Transparency = phase
		end
		local press = if still then 0 else math.max(0, math.sin(phase * math.pi * 2)) * 8
		hand.Position = UDim2.fromOffset(centre.X + size.X * 0.2, y1 - size.Y * 0.35 - press)
		hand.Visible = true
		handWord.Position = UDim2.fromOffset(centre.X + size.X * 0.2, y1 + 54 - size.Y * 0.35)
		handWord.Visible = still
		buyLabel.Position = UDim2.fromOffset(centre.X, y0 - Theme.Space.Step[1])
		buyLabel.Visible = labelled
		-- A pad's focus: once per new target.
		if target ~= focusTarget then
			focusTarget = target
			if device() == "Pad" and target:IsA("GuiButton") and target.Selectable then
				GuiService.SelectedObject = target
			end
		end
		debug.profileend()
	end

	-- It runs every frame only during the Shop step and the 📖 ring; everyone else (nearly every session) never runs it.
	local pointerConnection: RBXScriptConnection? = nil
	syncPointer = function()
		local step = ctx.State.Tutorial
		local wanted = (step == Logic.SHOP and not finaleFired) or bookRingUntil > os.clock()
		local current = pointerConnection
		if wanted and not current then
			pointerConnection = RunService.RenderStepped:Connect(followLayout)
			followLayout()
		elseif not wanted and current then
			pointerConnection = nil
			current:Disconnect()
			hidePointer()
			focusTarget = nil
		end
	end

	-- The mini-game's touch hand (the exam's card 3, the supply's game on card 5): pressing on the stage, touch only.
	local function syncGameHand()
		local stage: GuiObject? = nil
		if playing ~= nil and (presented == 3 or presented == 5) and device() == "Touch" then
			pcall(function()
				stage = if MiniGames then MiniGames.stage() else nil
			end)
		end
		local shownStage = stage
		if not (shownStage and isShown(shownStage)) then
			gameHand.Visible = false
			return
		end
		local at = shownStage.AbsolutePosition - pointerGui.AbsolutePosition + shownStage.AbsoluteSize / 2
		gameHand.Position = UDim2.fromOffset(at.X, at.Y)
		gameHand.Visible = true
		if not Kit.reducedMotion() then
			TweenService:Create(
				gameHand,
				TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 3, true, 0.5),
				{ Position = UDim2.fromOffset(at.X, at.Y + 10) }
			):Play()
		end
	end

	--------------------------------------------------------------------------------------------------------------
	-- Skip and Replay: always behind Hud.confirm ("Not now"/"Keep going" focused), then the remote
	--------------------------------------------------------------------------------------------------------------
	local function ask(remote: RemoteFunction)
		task.spawn(function()
			local ok, message = Hud.ask(remote)
			if not ok and message ~= "" then
				ctx.toast(message)
			end
		end)
	end

	local function askSkip()
		if Hud.isOpen("Confirm") or not Logic.canSkip(ctx.State.Tutorial) then
			return
		end
		Hud.confirm(ctx, {
			Title = Pure.SKIP.Title,
			Line = Pure.SKIP.Line,
			Yes = Pure.SKIP.Yes,
			No = Pure.SKIP.No,
		}, function()
			ask(ctx.Remotes.TutorialSkip)
		end)
	end

	local function askReplay()
		if Hud.isOpen("Confirm") or not Logic.isDone(ctx.State.Tutorial) then
			return
		end
		Hud.confirm(ctx, {
			Title = Pure.REPLAY.Title,
			Line = Pure.REPLAY.Line,
			Yes = Pure.REPLAY.Yes,
			No = Pure.REPLAY.No,
		}, function()
			ask(ctx.Remotes.TutorialReplay)
		end)
	end

	skip.Activated:Connect(askSkip)
	ctx.on("SkipTutorial", askSkip)
	ctx.on("ReplayTutorial", askReplay)

	--------------------------------------------------------------------------------------------------------------
	-- The world guide: the tutorial steers UI/Guide (card 1 and a ward rest here; 2, 4, 5 and 7 are its usual
	-- targets: the bay to examine at, the plan step's station, the bay again)
	--------------------------------------------------------------------------------------------------------------
	local function patients(plot: Instance): { Model }
		local found: { Model } = {}
		local folder = plot:FindFirstChild("Patients")
		if folder then
			for _, child in folder:GetChildren() do
				if child:IsA("Model") and child.PrimaryPart then
					table.insert(found, child)
				end
			end
		end
		return found
	end

	-- The pin floats just over the patient's badge, so the badge itself stays readable.
	local function pinOver(patient: Model, pinIcon: string, color: Color3, glowing: boolean): any
		local root = patient.PrimaryPart :: BasePart
		local anchor = root:FindFirstChild("IconAnchor")
		local height = if anchor and anchor:IsA("Attachment") then anchor.WorldPosition.Y + 2.6 else root.Position.Y + 6
		return {
			Part = root,
			Target = patient,
			Icon = pinIcon,
			Color = color,
			Height = height,
			Beam = false,
			Glow = glowing,
		}
	end

	if Guide then
		Guide.setSteer(function(plot: Instance): any
			local step = ctx.State.Tutorial
			if not Logic.active(step) then
				return nil -- done (or skipped): the Guide as it always was, until 3 cures
			end
			if step >= Logic.SHOP or gameOpen() then
				return false -- a UI step, or the mini-game covers the middle
			end
			if step == Logic.WELCOME and welcome ~= "Card" then
				return false -- the sweep
			end
			if step <= Logic.PATIENT then
				local patient = anyPatient(plot) -- the first patient walking in (one at a time in the tutorial)
				return if patient then pinOver(patient, "👀", Theme.Colors.Pink, true) else false
			elseif step == Logic.REST then
				for _, patient in patients(plot) do
					local state = patient:GetAttribute("State")
					if state == "ToWard" or state == "Recovering" then
						return pinOver(patient, "🛏️", Theme.Colors.Cyan, false) -- a Stay case resting upstairs
					end
				end
				return false
			end
			return nil -- EXAMINE, TREAT and MORE: the Guide's usual targets
		end)
	end

	--------------------------------------------------------------------------------------------------------------
	-- Arriving at your clinic: the welcome (first-ever join), or just the camera turned to the clinic
	--------------------------------------------------------------------------------------------------------------
	local arriving = 0
	local function intro(plot: Model)
		local root = waitForHome(plot, HOME_WAIT_SECONDS, homeReach)
		if root and not Kit.reducedMotion() then
			setControls(false)
			local finish = behind(root)
			task.spawn(showTitle, CAMERA_SWEEP_SECONDS + 0.4)
			local ok, err = pcall(sweep, plot, finish, CAMERA_SWEEP_SECONDS)
			if not ok then
				warn("[Tutorial] camera sweep: " .. tostring(err))
				local camera = Workspace.CurrentCamera
				if camera then
					camera.CameraType = Enum.CameraType.Custom
				end
			end
			setControls(true)
		else
			local camera = Workspace.CurrentCamera
			if root and camera then
				camera.CFrame = behind(root)
			end
			showTitle(TITLE_STILL_SECONDS)
		end
		-- The sweep is over: ack now (no welcome card), and card 1 shows while the first patient hops in.
		welcome = "Card"
		if ctx.State.Tutorial == Logic.WELCOME then
			ack()
		end
		render()
	end

	-- Every owner: once the server has moved your character to your clinic, turn the camera to the clinic.
	local function arrive()
		arriving += 1
		local mine = arriving
		local state = ctx.State
		local plot = plotModel(state)
		if not plot then
			return
		end
		if state.Tutorial == Logic.WELCOME and welcome == "None" and state.TutorialReplay ~= true then
			welcome = "Intro"
			intro(plot)
			return
		end
		if welcome == "Intro" then
			return -- the sweep handles the camera
		end
		welcome = "Card"
		local root = waitForHome(plot, HOME_WAIT_SECONDS, homeReach)
		local camera = Workspace.CurrentCamera
		if root and camera and mine == arriving and camera.CameraType == Enum.CameraType.Custom then
			camera.CFrame = behind(root)
		end
	end

	--------------------------------------------------------------------------------------------------------------
	-- Wiring
	--------------------------------------------------------------------------------------------------------------
	local hadPlot = false
	local watchedPlot: Instance? = nil
	local plotConnections: { RBXScriptConnection } = {}
	local function watchPlot(state: Types.Snapshot)
		local plot = if Logic.active(state.Tutorial) then plotModel(state) else nil
		if plot == watchedPlot then
			return
		end
		watchedPlot = plot
		for _, connection in plotConnections do
			connection:Disconnect()
		end
		table.clear(plotConnections)
		local folder = if plot then plot:FindFirstChild("Patients") else nil
		if folder then
			-- A patient walking in, sitting down in a bay, being examined or given a step: the words follow it.
			local function changed()
				render()
				armNudge(true)
			end
			local function follow(child: Instance)
				for _, name in PATIENT_ATTRIBUTES do
					table.insert(plotConnections, child:GetAttributeChangedSignal(name):Connect(changed))
				end
			end
			table.insert(
				plotConnections,
				folder.ChildAdded:Connect(function(child: Instance)
					follow(child)
					task.defer(render)
				end)
			)
			table.insert(
				plotConnections,
				folder.ChildRemoved:Connect(function()
					task.defer(render)
				end)
			)
			for _, child in folder:GetChildren() do
				follow(child)
			end
		elseif plot then
			watchedPlot = nil -- no Patients folder yet: the next snapshot looks again
		end
	end

	ctx.onState(function(state: Types.Snapshot)
		-- The first server snapshot with your clinic starts the arrival (and the welcome). The client's default
		-- snapshot says Tutorial 0, so it never counts.
		local known = type(state.Tutorial) == "number" and state.Tutorial > 0
		local hasPlot = known and state.PlotIndex ~= nil
		if hasPlot and not hadPlot then
			task.spawn(arrive)
		end
		hadPlot = hasPlot
		if known then
			local from = lastStep
			lastStep = state.Tutorial
			onStep(from, state.Tutorial)
			-- Card 7's pips: each patient treated fills one with a pop and a line.
			local cures = if state.Tutorial == Logic.MORE then state.TutorialCures or 0 else 0
			if state.Tutorial == Logic.MORE and cures > lastCures and presented == Pure.PIPS_CARD and not holding then
				if not Kit.reducedMotion() then
					local centre = thumb.AbsolutePosition - inner.AbsolutePosition + thumb.AbsoluteSize / 2
					Kit.confetti(inner, CONFETTI_STEP, UDim2.fromOffset(centre.X, centre.Y))
				end
				Hud.sound("Chime", 0.7)
				say(if cures >= Logic.MORE_CURES then Pure.SAY.Super else Pure.SAY.OneMore)
				armNudge(true)
			end
			lastCures = cures
		end
		watchPlot(state)
		render()
	end)

	player.CharacterAdded:Connect(function()
		if hadPlot and welcome ~= "Intro" then
			task.spawn(arrive)
		end
	end)
	player:GetAttributeChangedSignal("Carry"):Connect(function()
		if Logic.active(ctx.State.Tutorial) then
			render()
			armNudge(true)
		end
	end)

	-- A mini-game card opens (TreatSession.Kind): the exam's card 3, the supply's game on card 5, or the dispensing
	-- card (still card 4: you're fetching). The slim strip shows its words.
	ctx.on("TreatStart", function(session: any)
		if not Logic.active(ctx.State.Tutorial) or type(session) ~= "table" then
			render()
			return
		end
		local kind = if session.Kind == "Exam" or session.Kind == "Dispense" then session.Kind else "Treat"
		local games = session.Games
		local first = if type(games) == "table" then games[1] else nil
		playGame = if session.Simple == true
			then "Tap"
			elseif type(first) == "string" and Pure.GAMES[first] then first
			else nil
		playGlow = session.Glow ~= false
		if kind == "Exam" and playing == nil and presented == 2 then
			paintBar(Pure.segments(2, true), true) -- card 2's success is the exam card itself: card 3 at once
			Hud.sound("Chime", 0.7)
		end
		playing = kind
		playToken += 1
		rated = false
		render()
		task.delay(0.3, syncGameHand)
	end)
	ctx.on("MiniGameRated", function()
		if (presented == 3 or presented == 5) and not rated then
			rated = true
			say(Pure.SAY.Rated)
		end
		gameHand.Visible = false
	end)
	-- The card closed (its result came back): once it's off the screen, the step's own card again. The server's
	-- step change usually lands first; this only waits out the game card's own reveal.
	local SETTLE_TRIES = 20
	local function settlePlay(mine: number, tries: number)
		if playToken ~= mine or playing == nil then
			return
		end
		if gameOpen() and tries < SETTLE_TRIES then
			task.delay(TREAT_SETTLE, settlePlay, mine, tries + 1)
			return
		end
		playing = nil
		playGame = nil
		render()
	end
	ctx.on("TreatDone", function()
		gameHand.Visible = false
		playToken += 1
		task.delay(TREAT_SETTLE, settlePlay, playToken, 0)
		render()
	end)

	ctx.on("ModalOpened", function(name: any, hudMode: any)
		if type(name) == "string" then
			modes[name] = if type(hudMode) == "string" then hudMode else "None"
		end
		if panelOpen() then
			pauseNudge()
		end
		render()
	end)
	ctx.on("ModalClosed", function(name: any)
		if type(name) == "string" then
			modes[name] = nil
		end
		render()
		if not panelOpen() then
			armNudge(false)
		end
	end)
	ctx.on("CelebrateClosed", function(kind: any)
		if kind == "Tutorial" then
			bookRingUntil = os.clock() + BOOK_RING_SECONDS
			syncPointer()
			task.delay(BOOK_RING_SECONDS + 0.1, syncPointer)
		end
	end)
	pcall(function()
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(render)
	end)
	GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(render)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local short = camera.ViewportSize.Y < HudZones.NOW_SHORT_BREAK
			if presented and short ~= shortNow then
				layout(slimNow)
			end
		end)
	end
	-- The words follow the column's width (a phone gets the shortest ones): once it is known, and on a resize.
	local narrowQueued = false
	column:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if narrowQueued or narrowColumn() == narrowShown then
			return
		end
		narrowQueued = true
		task.defer(function()
			narrowQueued = false
			local narrow = narrowColumn()
			if narrow ~= narrowShown then
				narrowShown = narrow
				render()
			end
		end)
	end)
end

return Tutorial
