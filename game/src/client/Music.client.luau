-- Background music: calm tracks by day, a moonlit one at night.
-- Plays on each player's own client, so muting only affects you.
--
-- Mute state is the player attribute "MusicMuted" (set on this client only, never replicated). The 🎵 switch in
-- the HUD's ⚙️ settings panel flips it (UI/Hud; it used to be a 🎵 button of its own here, moved there by the
-- first-session declutter), and any other client module can too (Feel/Atmosphere relays
-- ctx.fire("SetMusicMuted", on)). The music fades out and back in whenever it changes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer

local LOAD_TIMEOUT = 8 -- a track that hasn't started by then is skipped

local sound = Instance.new("Sound")
sound.Name = "Music"
sound.Volume = 0
sound.Looped = false
sound.Parent = SoundService

local playlist = "Day"
local position = { Day = 0, Night = 0 }
local generation = 0 -- bumps on every track change, so a stale skip timer does nothing

local function muted(): boolean
	return player:GetAttribute("MusicMuted") == true
end

local function targetVolume(): number
	return if muted() then 0 else Config.Music.Volume
end

local function playNext()
	local list = Config.Music[playlist]
	if not list or #list == 0 then
		return
	end
	generation += 1
	local mine = generation
	position[playlist] = position[playlist] % #list + 1
	sound.SoundId = "rbxassetid://" .. list[position[playlist]]
	sound.TimePosition = 0
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(2), { Volume = targetVolume() }):Play()
	-- If a track can't load (moderated, region-locked), Ended never fires: move on instead of going silent.
	task.delay(LOAD_TIMEOUT, function()
		if mine == generation and not sound.IsPlaying and #list > 1 then
			playNext()
		end
	end)
end
sound.Ended:Connect(playNext)

local function onPhase()
	local wanted = if Workspace:GetAttribute("IsNight") then "Night" else "Day"
	if wanted == playlist and sound.IsPlaying then
		return
	end
	playlist = wanted
	if sound.IsPlaying then
		local fade = TweenService:Create(sound, TweenInfo.new(1.5), { Volume = 0 })
		fade:Play()
		fade.Completed:Wait()
	end
	playNext()
end
Workspace:GetAttributeChangedSignal("IsNight"):Connect(onPhase)
task.spawn(onPhase)

------------------------------------------------------------------------------------------------------------------
-- Muting (the switch itself lives in the HUD's ⚙️ panel)
------------------------------------------------------------------------------------------------------------------

player:GetAttributeChangedSignal("MusicMuted"):Connect(function()
	TweenService:Create(sound, TweenInfo.new(0.5), { Volume = targetVolume() }):Play()
end)
