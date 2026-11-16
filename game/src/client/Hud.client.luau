-- The player's screen: cash, what you're carrying, day/night timer, the upgrade shop and toasts.
-- Big buttons and text on purpose: most young players are on phones and tablets.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = require(ReplicatedStorage.Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FONT = Enum.Font.FredokaOne
local INK = Color3.fromRGB(40, 40, 40)

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 12)
	c.Parent = parent
end

local function label(parent: Instance, text: string, size: UDim2, position: UDim2): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = position
	l.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	l.BackgroundTransparency = 0.1
	l.TextColor3 = INK
	l.Font = FONT
	l.TextScaled = true
	l.Text = text
	l.Parent = parent
	corner(l)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = l
	return l
end

local function button(parent: Instance, text: string, size: UDim2, position: UDim2, colour: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = colour
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Font = FONT
	b.TextScaled = true
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b)
	return b
end

local gui = Instance.new("ScreenGui")
gui.Name = "Hud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = playerGui

-- Top-left: cash, carrying
local cashLabel = label(gui, "", UDim2.fromOffset(200, 44), UDim2.fromOffset(12, 12))
local carryLabel = label(gui, "", UDim2.fromOffset(200, 36), UDim2.fromOffset(12, 62))
-- Top-centre: day/night
local phaseLabel = label(gui, "", UDim2.fromOffset(220, 36), UDim2.new(0.5, -110, 0, 12))

-- Bottom-left: buttons
local upgradesButton =
	button(gui, "Upgrades", UDim2.fromOffset(150, 56), UDim2.new(0, 12, 1, -72), Color3.fromRGB(80, 150, 255))
local passButton =
	button(gui, "2x Cash", UDim2.fromOffset(130, 56), UDim2.new(0, 172, 1, -72), Color3.fromRGB(60, 190, 100))
passButton.Visible = false

-- Upgrade panel
local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(340, 300)
panel.Position = UDim2.new(0.5, -170, 0.5, -150)
panel.BackgroundColor3 = Color3.fromRGB(255, 250, 240)
panel.Visible = false
panel.Parent = gui
corner(panel, 16)
local panelTitle = label(panel, "Upgrades", UDim2.new(1, -70, 0, 44), UDim2.fromOffset(10, 8))
panelTitle.BackgroundTransparency = 1
local closeButton = button(panel, "X", UDim2.fromOffset(44, 44), UDim2.new(1, -54, 0, 8), Color3.fromRGB(230, 90, 90))

local rows: { [string]: { Info: TextLabel, Buy: TextButton } } = {}
for i, name in Config.UpgradeOrder do
	local y = 60 + (i - 1) * 78
	local info = label(panel, "", UDim2.new(1, -150, 0, 66), UDim2.fromOffset(10, y))
	info.TextXAlignment = Enum.TextXAlignment.Left
	local buy = button(panel, "", UDim2.fromOffset(120, 66), UDim2.new(1, -130, 0, y), Color3.fromRGB(255, 170, 50))
	rows[name] = { Info = info, Buy = buy }
end

-- Toasts
local toastHolder = Instance.new("Frame")
toastHolder.Size = UDim2.fromOffset(360, 200)
toastHolder.Position = UDim2.new(0.5, -180, 0, 60)
toastHolder.BackgroundTransparency = 1
toastHolder.Parent = gui
local list = Instance.new("UIListLayout")
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.Padding = UDim.new(0, 6)
list.Parent = toastHolder

local function toast(text: string)
	local t = label(toastHolder, text, UDim2.fromOffset(340, 38), UDim2.new())
	t.BackgroundColor3 = Color3.fromRGB(255, 245, 200)
	task.delay(2.2, function()
		local fade = TweenService:Create(t, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		t:Destroy()
	end)
end
Remotes.Toast.OnClientEvent:Connect(toast)

-- Keeping the screen current
local function level(name: string): number
	return player:GetAttribute("Upgrade_" .. name) or 0
end

local function refreshCash()
	local leaderstats = player:FindFirstChild("leaderstats")
	local cash = leaderstats and leaderstats:FindFirstChild(Config.CurrencyName)
	cashLabel.Text = Config.CurrencyName .. ": " .. (cash and cash.Value or 0)
end

local function refreshCarry()
	local carrying = player:GetAttribute("Carrying") or 0
	carryLabel.Text = "Carrying: " .. carrying .. "/" .. Config.trayCapacity(level("Tray"))
end

local function refreshUpgrades()
	for name, row in rows do
		local upgrade = Config.Upgrades[name]
		local lvl = level(name)
		local price = Config.nextPrice(name, lvl)
		row.Info.Text = upgrade.DisplayName .. " (Lv " .. lvl .. ")\n" .. upgrade.Description
		row.Buy.Text = price and ("Buy " .. price) or "MAX"
		row.Buy.Active = price ~= nil
		row.Buy.AutoButtonColor = price ~= nil
	end
end

-- The station's hold time shrinks with Faster Hands (the server checks the real time held)
local function refreshStationPrompt()
	local shop = Workspace:FindFirstChild("Shop")
	local prompt = shop and shop:FindFirstChild("MakePrompt", true)
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.HoldDuration = Config.makeSeconds(level("Speed"))
	end
end

local function refreshAll()
	refreshCash()
	refreshCarry()
	refreshUpgrades()
	refreshStationPrompt()
end

for name, row in rows do
	row.Buy.Activated:Connect(function()
		local ok, message = Remotes.BuyUpgrade:InvokeServer(name)
		toast(message)
		if ok then
			refreshAll()
		end
	end)
end

upgradesButton.Activated:Connect(function()
	panel.Visible = not panel.Visible
	refreshUpgrades()
end)
closeButton.Activated:Connect(function()
	panel.Visible = false
end)

local function refreshPass()
	local passId = Workspace:GetAttribute("DoubleCashPassId") or 0
	passButton.Visible = passId ~= 0 and not player:GetAttribute("DoubleCash")
end
passButton.Activated:Connect(function()
	local passId = Workspace:GetAttribute("DoubleCashPassId") or 0
	if passId ~= 0 then
		MarketplaceService:PromptGamePassPurchase(player, passId)
	end
end)

player.AttributeChanged:Connect(function(attribute)
	if attribute == "Carrying" then
		refreshCarry()
	elseif attribute == "DoubleCash" then
		refreshPass()
	elseif string.sub(attribute, 1, 8) == "Upgrade_" then
		refreshAll()
	end
end)

task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats")
	local cash = leaderstats:WaitForChild(Config.CurrencyName) :: IntValue
	cash.Changed:Connect(refreshCash)
	refreshAll()
end)

-- Day/night countdown + retry the station prompt until the shop exists
task.spawn(function()
	while true do
		local endsAt = Workspace:GetAttribute("PhaseEndsAt")
		if endsAt then
			local left = math.max(0, math.floor(endsAt - Workspace:GetServerTimeNow()))
			local isNight = Workspace:GetAttribute("IsNight")
			phaseLabel.Text = (isNight and "Night " or "Day ") .. string.format("%d:%02d", left // 60, left % 60)
			phaseLabel.BackgroundColor3 = isNight and Color3.fromRGB(70, 40, 110) or Color3.fromRGB(255, 255, 255)
			phaseLabel.TextColor3 = isNight and Color3.fromRGB(255, 255, 255) or INK
		end
		refreshStationPrompt()
		refreshPass()
		task.wait(1)
	end
end)

refreshAll()
