-- Background music: calm tracks by day, a moonlit one at night, with a 🎵 mute button.
-- Plays on each player's own client, so muting only affects you.
--
-- Mute state is the player attribute "MusicMuted" (set on this client only, never replicated). The 🎵 button flips
-- it, and any other client module can too (Feel/Atmosphere relays ctx.fire("SetMusicMuted", on)). The button sits
-- on the right edge, half way down, just left of Feel/Atmosphere's ✨ calm-effects button (same size and line).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer

local BUTTON_SIZE = 60
local BUTTON_Y = 0.5 -- the comfort pair's centre line, as a share of the screen height (Feel/Atmosphere matches)
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
-- The 🎵 button (a candy-pink Kit button when the UI kit loads, Quiet while muted; a plain button otherwise)
------------------------------------------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "MusicToggle"
gui.ResetOnSpawn = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.Parent = player:WaitForChild("PlayerGui")

local ui = script.Parent:FindFirstChild("UI")
local okKit, Kit = pcall(function()
	return require(ui:WaitForChild("Kit", 5)) :: any
end)
local okTheme, Theme = pcall(function()
	return require(ui:WaitForChild("Theme", 5)) :: any
end)
local hasKit = okKit and okTheme and type(Kit) == "table" and type(Theme) == "table"
if hasKit then
	gui.DisplayOrder = Theme.DisplayOrder.Hud
end

local margin = if hasKit then Theme.Size.Margin else 12
local gap = if hasKit then Theme.Size.Gap else 10
local buttonPosition = UDim2.new(1, -(margin + BUTTON_SIZE + gap), BUTTON_Y, 0)

local button: GuiButton
local icon: TextLabel?
local onColor: Color3? -- the candy fill while music plays; muted shows the Quiet fill
if hasKit then
	button = Kit.iconButton({
		Name = "Music",
		Icon = "🎵",
		Kind = "Pink",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = buttonPosition,
		Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
		Parent = gui,
	})
	icon = button:FindFirstChild("Icon") :: TextLabel?
	local kitColor = button:GetAttribute("KitColor")
	onColor = if typeof(kitColor) == "Color3" then kitColor else Theme.Colors.Pink
else
	local plain = Instance.new("TextButton")
	plain.AnchorPoint = Vector2.new(1, 0.5)
	plain.Position = buttonPosition
	plain.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
	plain.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	plain.TextScaled = true
	plain.Text = "🎵"
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = plain
	plain.Parent = gui
	button = plain
end

local function show()
	local text = if muted() then "🔇" else "🎵"
	if icon then
		icon.Text = text
	elseif button:IsA("TextButton") then
		button.Text = text
	end
	if hasKit then
		button.BackgroundColor3 = if muted() then Theme.Colors.Quiet else onColor or Theme.Colors.Pink
		button:SetAttribute("KitColor", button.BackgroundColor3)
	end
	TweenService:Create(sound, TweenInfo.new(0.5), { Volume = targetVolume() }):Play()
end

button.Activated:Connect(function()
	player:SetAttribute("MusicMuted", not muted())
end)
player:GetAttributeChangedSignal("MusicMuted"):Connect(show)
show()
