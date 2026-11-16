--!strict
-- Sound effects (build plan Task 7): every cue in one table, played locally through SoundService.
--   Sounds.play(name, volumeScale?)   plays a cue from Sounds.CUES (unknown names are ignored)
--   Sounds.CUES / Sounds.SOURCES      tune a volume or pitch here, not at the call site
--   init(ctx)                         wires the client bus: any UI or Feel module can play a cue with
--                                     ctx.fire("Sound", name, volumeScale?) without requiring this module
-- Wired here too: every Kit button press clicks; your Carry growing (you made an item) plays "Make" and shrinking
-- (you handed it over) plays "Give". CureFX and Atmosphere fire the rest through the bus.
--
-- Built-in sounds only (Global Constraints). Roblox ships just 11 rbxasset://sounds files today (checked in the
-- Studio and Player content folders on 2026-11-16): character moves, a splash, the settings-slider blip, an
-- explosion and the classic "oof" (we never use those two). So every chime here is a tiny melody: the soft slider
-- blip played at different pitches a few hundredths of a second apart. To swap in a licensed Creator Store sound
-- later, change SOURCES only.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local Sounds = {}

Sounds.SOURCES = table.freeze({
	Blip = "rbxasset://sounds/volume_slider.ogg", -- 0.85 s soft tone: the base of every chime
	Hop = "rbxasset://sounds/action_jump.mp3",
	Land = "rbxasset://sounds/action_jump_land.mp3",
	Rustle = "rbxasset://sounds/action_get_up.mp3",
	Splash = "rbxasset://sounds/impact_water.mp3",
})

export type Cue = {
	Source: string, -- a key of SOURCES
	Volume: number,
	Pitch: number?, -- PlaybackSpeed of the first note (1 = as recorded)
	Notes: { number }?, -- semitones above Pitch, played Gap seconds apart; nil = a single note
	Gap: number?,
	Jitter: number?, -- a random +- share of pitch, so repeats don't sound robotic
	Cooldown: number?, -- seconds before the same cue can play again (stops stacking)
}

-- Notes in semitones: 0, 4, 7, 12 is a major chord rising (a happy "ta-da").
Sounds.CUES = table.freeze({
	Click = { Source = "Blip", Volume = 0.28, Pitch = 1.15, Jitter = 0.03, Cooldown = 0.04 },
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
} :: { [string]: Cue })

local MAX_LIVE = 14 -- sounds playing at once; more are skipped, never queued
local MAX_SECONDS = 3 -- a played Sound is destroyed by then even if Ended never fires

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

local function playNote(source: string, volume: number, speed: number)
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
	sound:Play()
end

function Sounds.play(name: string, volumeScale: number?)
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
	local base = (cue.Pitch or 1) * (1 + (math.random() * 2 - 1) * jitter)
	local notes = cue.Notes
	if not notes then
		playNote(source, volume, base)
		return
	end
	local gap = cue.Gap or 0.07
	for index, semitones in notes do
		local speed = base * 2 ^ (semitones / 12)
		if index == 1 then
			playNote(source, volume, speed)
		else
			task.delay((index - 1) * gap, playNote, source, volume, speed)
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

local function wireKitClicks()
	local ui = script.Parent and script.Parent.Parent and script.Parent.Parent:FindFirstChild("UI")
	local kitModule = ui and ui:FindFirstChild("Kit")
	if not (kitModule and kitModule:IsA("ModuleScript")) then
		return
	end
	local ok, Kit = pcall(require, kitModule)
	if ok and type(Kit) == "table" and Kit.Clicked then
		(Kit :: any).Clicked:Connect(function()
			Sounds.play("Click")
		end)
	end
end

function Sounds.init(ctx: Types.Ctx)
	ctx.on("Sound", function(name: any, volumeScale: any)
		if type(name) == "string" then
			Sounds.play(name, if type(volumeScale) == "number" then volumeScale else nil)
		end
	end)

	wireKitClicks()

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
