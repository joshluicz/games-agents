-- Background music: calm cafe tracks by day, a moonlit one at night, with a mute button.
-- Plays on each player's own client, so muting only affects you.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local sound = Instance.new("Sound")
sound.Name = "Music"
sound.Volume = 0
sound.Looped = false
sound.Parent = SoundService

local muted = false
local playlist = "Day"
local position = { Day = 0, Night = 0 }

local function targetVolume(): number
	return if muted then 0 else Config.Music.Volume
end

local function playNext()
	local list = Config.Music[playlist]
	if not list or #list == 0 then
		return
	end
	position[playlist] = position[playlist] % #list + 1
	sound.SoundId = "rbxassetid://" .. list[position[playlist]]
	sound.TimePosition = 0
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(2), { Volume = targetVolume() }):Play()
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

-- Mute button, top-left under the cash and carrying labels
local gui = Instance.new("ScreenGui")
gui.Name = "MusicToggle"
gui.ResetOnSpawn = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local button = Instance.new("TextButton")
button.Size = UDim2.fromOffset(130, 36)
button.Position = UDim2.fromOffset(12, 104)
button.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
button.BackgroundTransparency = 0.1
button.TextColor3 = Color3.fromRGB(40, 40, 40)
button.Font = Enum.Font.FredokaOne
button.TextScaled = true
button.Text = "Music: On"
button.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = button

button.Activated:Connect(function()
	muted = not muted
	button.Text = if muted then "Music: Off" else "Music: On"
	TweenService:Create(sound, TweenInfo.new(0.5), { Volume = targetVolume() }):Play()
end)
