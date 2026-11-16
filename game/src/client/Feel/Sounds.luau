--!strict
-- Sound effects (build plan Task 7; depth update T6): every cue in one table, played locally through SoundService.
--   Sounds.play(name, volumeScale?, pitchScale?)   plays a cue from Sounds.CUES (unknown names are ignored)
--   Sounds.CUES / Sounds.SOURCES                    tune a volume or pitch here, not at the call site
--   init(ctx)                                       wires the client bus: any UI or Feel module can play a cue with
--                                                   ctx.fire("Sound", name, volumeScale?, pitchScale?) without
--                                                   requiring this module
-- Wired here too: every Kit button press clicks and every number a Kit.countUp shows ticks (rising in pitch as it
-- lands); your Carry growing (you made an item) plays "Make" and shrinking (you handed it over) plays "Give". The
-- depth update's bus events: "MiniGameRated" (game, rating) plays RateOK / RateGood / RatePerfect, "TreatDone"
-- (outcome, session) plays Tip when a tip landed and Combo when the combo climbs into a new step, and "NurseNews"
-- plays Hire, Equip, or a soft Sparkle for a nurse seen for the first time. CureFX, Celebrate, Toasts, Hud and the
-- mini-games fire the rest through the bus. Every cue has a cooldown, so two modules firing the same cue in the
-- same moment (MiniGames and this wiring, say) play it once.
--
-- Cue names other tasks may fire (build plan §B9): Pour, Patch, Scrub, Blow, RateOK, RateGood, RatePerfect, Combo,
-- Tip, Hire, Equip, Arrival, Golden, LevelUp, Celebrate, Tick, Coin; and from before: Click, Pop, Make, Give, Chime,
-- Sparkle, Fanfare, Heart, Thud, Hop, Splash, Whoosh, Nope, Night, Morning; plus Close and Toast.
--
-- Built-in sounds only (Global Constraints). Roblox ships just 11 rbxasset://sounds files today (checked in the
-- Studio and Player content folders on 2026-11-16): character moves, a splash, the settings-slider blip, an
-- explosion and the classic "oof" (we never use those two). So every chime here is a tiny melody: the soft slider
-- blip played at different pitches a few hundredths of a second apart, cut short (Length) for ticks and pops. The
-- falling-wind loop, cut to half a second, is the Cool game's blow. To swap in a licensed Creator Store sound
-- later, change SOURCES only.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local Sounds = {}

Sounds.SOURCES = table.freeze({
	Blip = "rbxasset://sounds/volume_slider.ogg", -- 0.85 s soft tone: the base of every chime
	Hop = "rbxasset://sounds/action_jump.mp3",
	Land = "rbxasset://sounds/action_jump_land.mp3",
	Rustle = "rbxasset://sounds/action_get_up.mp3",
	Splash = "rbxasset://sounds/impact_water.mp3",
	Wind = "rbxasset://sounds/action_falling.ogg", -- a long wind loop: always played with a Length
})

export type Cue = {
	Source: string, -- a key of SOURCES
	Volume: number,
	Pitch: number?, -- PlaybackSpeed of the first note (1 = as recorded)
	Notes: { number }?, -- semitones above Pitch, played Gap seconds apart; nil = a single note
	Gap: number?,
	Jitter: number?, -- a random +- share of pitch, so repeats don't sound robotic
	Cooldown: number?, -- seconds before the same cue can play again (stops stacking)
	Length: number?, -- seconds: each note fades out and stops after this (ticks, pops, the wind)
}

-- Notes in semitones: 0, 4, 7, 12 is a major chord rising (a happy "ta-da"). Nothing here is a "fail" sound
-- except Nope (a gentle two-note shrug for a wrong item); an OK rating still gets a friendly chime.
Sounds.CUES = table.freeze({
	Click = { Source = "Blip", Volume = 0.28, Pitch = 1.15, Jitter = 0.03, Cooldown = 0.04 },
	Close = { Source = "Blip", Volume = 0.2, Pitch = 1, Notes = { 4, 0 }, Gap = 0.045, Cooldown = 0.08 },
	Toast = { Source = "Blip", Volume = 0.16, Pitch = 1.35, Notes = { 0, 7 }, Gap = 0.04, Cooldown = 0.15 },
	Tick = { Source = "Blip", Volume = 0.1, Pitch = 2.2, Jitter = 0.01, Cooldown = 0.05, Length = 0.06 },
	Coin = {
		Source = "Blip",
		Volume = 0.26,
		Pitch = 1.9,
		Notes = { 0, 5 },
		Gap = 0.035,
		Jitter = 0.03,
		Cooldown = 0.05,
		Length = 0.25,
	},
	Pop = { Source = "Blip", Volume = 0.4, Pitch = 0.8, Jitter = 0.05, Cooldown = 0.05 },
	Make = { Source = "Blip", Volume = 0.36, Pitch = 1, Notes = { 0, 7 }, Gap = 0.06, Cooldown = 0.1 },
	Give = { Source = "Rustle", Volume = 0.35, Pitch = 1.25, Jitter = 0.04, Cooldown = 0.1 },
	Chime = { Source = "Blip", Volume = 0.45, Pitch = 1, Notes = { 0, 4, 7, 12 }, Gap = 0.07, Cooldown = 0.12 },
	Sparkle = { Source = "Blip", Volume = 0.2, Pitch = 1.5, Notes = { 0, 4, 7, 12 }, Gap = 0.045, Cooldown = 0.2 },
	Fanfare = { Source = "Blip", Volume = 0.5, Pitch = 0.9, Notes = { 0, 4, 7, 12, 16 }, Gap = 0.085, Cooldown = 0.5 },
	Heart = { Source = "Blip", Volume = 0.35, Pitch = 1.3, Notes = { 0, 4 }, Gap = 0.09, Cooldown = 0.2 },
	Thud = { Source = "Land", Volume = 0.45, Pitch = 1, Jitter = 0.04, Cooldown = 0.08 },
	Hop = { Source = "Hop", Volume = 0.3, Pitch = 1.15, Jitter = 0.05, Cooldown = 0.1 },
	Splash = { Source = "Splash", Volume = 0.25, Pitch = 1.4, Cooldown = 0.2 },
	Whoosh = { Source = "Rustle", Volume = 0.4, Pitch = 0.9, Cooldown = 0.1 },
	Nope = { Source = "Blip", Volume = 0.3, Pitch = 0.75, Notes = { 0, -3 }, Gap = 0.12, Cooldown = 0.3 },
	Night = { Source = "Blip", Volume = 0.28, Pitch = 0.8, Notes = { 7, 4, 0, -5 }, Gap = 0.18, Cooldown = 2 },
	Morning = { Source = "Blip", Volume = 0.3, Pitch = 0.9, Notes = { 0, 4, 7, 11, 12 }, Gap = 0.11, Cooldown = 2 },
	-- The treatment mini-games (UI/MiniGames fires the hits; this module fires the ratings)
	Pour = {
		Source = "Blip",
		Volume = 0.3,
		Pitch = 0.62,
		Notes = { 0, 3, 7 },
		Gap = 0.05,
		Jitter = 0.04,
		Cooldown = 0.12,
	},
	Patch = { Source = "Land", Volume = 0.4, Pitch = 1.45, Jitter = 0.08, Cooldown = 0.05 },
	Scrub = { Source = "Blip", Volume = 0.28, Pitch = 1.7, Jitter = 0.12, Cooldown = 0.03, Length = 0.14 },
	Blow = { Source = "Wind", Volume = 0.4, Pitch = 1.4, Jitter = 0.05, Cooldown = 0.15, Length = 0.45 },
	RateOK = { Source = "Blip", Volume = 0.36, Pitch = 0.95, Notes = { 0, 4 }, Gap = 0.08, Cooldown = 0.25 },
	RateGood = { Source = "Blip", Volume = 0.42, Pitch = 1, Notes = { 0, 4, 7 }, Gap = 0.07, Cooldown = 0.25 },
	RatePerfect = {
		Source = "Blip",
		Volume = 0.5,
		Pitch = 1.05,
		Notes = { 0, 4, 7, 12, 16 },
		Gap = 0.055,
		Cooldown = 0.25,
	},
	Combo = { Source = "Blip", Volume = 0.45, Pitch = 1.2, Notes = { 0, 7, 12, 19, 24 }, Gap = 0.04, Cooldown = 0.4 },
	Tip = { Source = "Blip", Volume = 0.38, Pitch = 1.25, Notes = { 0, 7, 12, 19 }, Gap = 0.045, Cooldown = 0.2 },
	-- Nurses and the belt
	Hire = { Source = "Blip", Volume = 0.45, Pitch = 1, Notes = { 0, 12, 7, 16 }, Gap = 0.06, Cooldown = 0.4 },
	Equip = { Source = "Blip", Volume = 0.36, Pitch = 1.2, Notes = { 0, 7 }, Gap = 0.05, Cooldown = 0.3 },
	Arrival = { Source = "Blip", Volume = 0.34, Pitch = 0.95, Notes = { 0, 5, 9 }, Gap = 0.09, Cooldown = 1 },
	Golden = {
		Source = "Blip",
		Volume = 0.42,
		Pitch = 1,
		Notes = { 0, 4, 7, 11, 14, 19 },
		Gap = 0.07,
		Cooldown = 2,
	},
	-- Celebration screens (UI/Celebrate)
	LevelUp = {
		Source = "Blip",
		Volume = 0.55,
		Pitch = 0.8,
		Notes = { 0, 4, 7, 12, 16, 19, 24 },
		Gap = 0.075,
		Cooldown = 1,
	},
	Celebrate = {
		Source = "Blip",
		Volume = 0.5,
		Pitch = 0.9,
		Notes = { 0, 7, 12, 16, 19 },
		Gap = 0.08,
		Cooldown = 0.8,
	},
} :: { [string]: Cue })

local MAX_LIVE = 18 -- sounds playing at once; more are skipped, never queued
local MAX_SECONDS = 3 -- a played Sound is destroyed by then even if Ended never fires
local CUT_FADE = TweenInfo.new(0.05, Enum.EasingStyle.Linear) -- how a note with a Length is cut

local group: SoundGroup? = nil
local live = 0
local lastPlayed: { [string]: number } = {}
local warned: { [string]: boolean } = {}

local function sfxGroup(): SoundGroup
	local existing = group
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("SoundGroup")
	created.Name = "FeelSfx"
	created.Volume = 0.9
	-- A touch of room tone turns the short blips into little bells.
	local reverb = Instance.new("ReverbSoundEffect")
	reverb.DecayTime = 1.1
	reverb.Density = 0.8
	reverb.Diffusion = 0.8
	reverb.DryLevel = 0
	reverb.WetLevel = -15
	reverb.Parent = created
	created.Parent = SoundService
	group = created
	return created
end

local function playNote(source: string, volume: number, speed: number, length: number?)
	if live >= MAX_LIVE then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "Sfx"
	sound.SoundId = source
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.SoundGroup = sfxGroup()
	sound.Parent = SoundService
	live += 1

	local done = false
	local function finish()
		if done then
			return
		end
		done = true
		live -= 1
		sound:Destroy()
	end
	sound.Ended:Once(finish)
	task.delay(MAX_SECONDS, finish)
	if length then
		-- Cut it short with a tiny fade (a hard stop clicks).
		task.delay(length, function()
			if done then
				return
			end
			local fade = TweenService:Create(sound, CUT_FADE, { Volume = 0 })
			fade.Completed:Once(finish)
			fade:Play()
		end)
	end
	sound:Play()
end

function Sounds.play(name: string, volumeScale: number?, pitchScale: number?)
	local cue = Sounds.CUES[name]
	if not cue then
		if RunService:IsStudio() and not warned[name] then
			warned[name] = true
			warn("[Sounds] No cue named " .. tostring(name))
		end
		return
	end
	local source = Sounds.SOURCES[cue.Source]
	if not source then
		return
	end

	local now = os.clock()
	if now - (lastPlayed[name] or -math.huge) < (cue.Cooldown or 0.05) then
		return
	end
	lastPlayed[name] = now

	local volume = cue.Volume * math.clamp(volumeScale or 1, 0, 2)
	local jitter = cue.Jitter or 0
	local base = (cue.Pitch or 1) * math.clamp(pitchScale or 1, 0.25, 4) * (1 + (math.random() * 2 - 1) * jitter)
	local notes = cue.Notes
	if not notes then
		playNote(source, volume, base, cue.Length)
		return
	end
	local gap = cue.Gap or 0.07
	for index, semitones in notes do
		local speed = base * 2 ^ (semitones / 12)
		if index == 1 then
			playNote(source, volume, speed, cue.Length)
		else
			task.delay((index - 1) * gap, playNote, source, volume, speed, cue.Length)
		end
	end
end

------------------------------------------------------------------------------------------------------------------
-- Wiring
------------------------------------------------------------------------------------------------------------------

local function carryCount(player: Player): number
	local value = player:GetAttribute("Carry")
	if type(value) ~= "string" or value == "" then
		return 0
	end
	return #string.split(value, ",")
end

-- UI/Kit, found by path (Feel never hard-requires UI: a broken Kit mustn't silence the game).
local function kit(): any?
	local ui = script.Parent and script.Parent.Parent and script.Parent.Parent:FindFirstChild("UI")
	local kitModule = ui and ui:FindFirstChild("Kit")
	if not (kitModule and kitModule:IsA("ModuleScript")) then
		return nil
	end
	local ok, Kit = pcall(require, kitModule)
	return if ok and type(Kit) == "table" then Kit else nil
end

local function wireKit(Kit: any)
	if Kit.Clicked then
		Kit.Clicked:Connect(function()
			Sounds.play("Click")
		end)
	end
	if Kit.Ticked then
		Kit.Ticked:Connect(function(_, progress: any)
			local p = if type(progress) == "number" then math.clamp(progress, 0, 1) else 0
			Sounds.play("Tick", 1, 1 + 0.45 * p)
		end)
	end
end

local RATING_CUES = { OK = "RateOK", Good = "RateGood", Perfect = "RatePerfect" }

local function wireDepth(ctx: Types.Ctx, Kit: any)
	ctx.on("MiniGameRated", function(_, rating: any)
		local cue = if type(rating) == "string" then RATING_CUES[rating] else nil
		if cue then
			Sounds.play(cue)
		end
	end)
	ctx.on("TreatDone", function(outcome: any, session: any)
		if type(outcome) ~= "table" then
			return
		end
		if type(outcome.Tip) == "number" and outcome.Tip > 0 then
			task.delay(0.15, Sounds.play, "Tip")
		end
		local before = if type(session) == "table" and type(session.Combo) == "number" then session.Combo else 0
		local after = if type(outcome.Combo) == "number" then outcome.Combo else 0
		local steps = ctx.Config.MiniGame and ctx.Config.MiniGame.Combo
		if Kit and Kit.Juice and type(steps) == "table" and Kit.Juice.crossed(before, after, steps) then
			task.delay(0.3, Sounds.play, "Combo")
		end
	end)
	ctx.on("NurseNews", function(info: any)
		if type(info) ~= "table" then
			return
		end
		if info.Kind == "Hired" then
			Sounds.play("Hire")
		elseif info.Kind == "Equipped" then
			Sounds.play("Equip", if info.On == false then 0.7 else 1, if info.On == false then 0.85 else 1)
		elseif info.Kind == "Seen" then
			Sounds.play("Sparkle", 0.6)
		end
	end)
end

function Sounds.init(ctx: Types.Ctx)
	ctx.on("Sound", function(name: any, volumeScale: any, pitchScale: any)
		if type(name) == "string" then
			Sounds.play(
				name,
				if type(volumeScale) == "number" then volumeScale else nil,
				if type(pitchScale) == "number" then pitchScale else nil
			)
		end
	end)

	local Kit = kit()
	if Kit then
		wireKit(Kit)
	end
	wireDepth(ctx, Kit)

	local player = ctx.Player or Players.LocalPlayer
	local carried = carryCount(player)
	player:GetAttributeChangedSignal("Carry"):Connect(function()
		local now = carryCount(player)
		if now > carried then
			Sounds.play("Make")
		elseif now < carried then
			Sounds.play("Give")
		end
		carried = now
	end)

	task.spawn(function()
		local list = {}
		for _, source in Sounds.SOURCES do
			table.insert(list, source)
		end
		pcall(ContentProvider.PreloadAsync, ContentProvider, list)
	end)
end

return Sounds
