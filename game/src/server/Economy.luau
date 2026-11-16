-- Cash maths, carrying, and the 2x Cash game pass. Server only.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local PlayerData = require(script.Parent.PlayerData)

local Economy = {}

function Economy.level(player: Player, upgradeName: string): number
	local data = PlayerData.get(player)
	return data and data.Upgrades[upgradeName] or 0
end

function Economy.capacity(player: Player): number
	return Config.trayCapacity(Economy.level(player, "Tray"))
end

function Economy.carrying(player: Player): number
	return player:GetAttribute("Carrying") or 0
end

function Economy.setCarrying(player: Player, amount: number)
	player:SetAttribute("Carrying", amount)
	-- A simple block in front of the character while carrying. Swap for a real model later.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local visual = character:FindFirstChild("CarryVisual")
	if amount > 0 and not visual then
		local block = Instance.new("Part")
		block.Name = "CarryVisual"
		block.Size = Vector3.new(1.2, 0.6, 1.2)
		block.Color = Color3.fromRGB(255, 200, 90)
		block.CanCollide = false
		block.CanQuery = false
		block.Massless = true
		block.CFrame = root.CFrame * CFrame.new(0, 0, -1.3)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = block
		weld.Parent = block
		block.Parent = character
	elseif amount <= 0 and visual then
		visual:Destroy()
	end
end

function Economy.toast(player: Player, text: string)
	Remotes.Toast:FireClient(player, text)
end

function Economy.toastAll(text: string)
	Remotes.Toast:FireAllClients(text)
end

-- patienceLeft: 0..1, how much patience the customer had left when served
function Economy.payFor(player: Player, patienceLeft: number, isNightCustomer: boolean): number
	local pay = Config.BasePay
	pay *= Config.tipMultiplier(Economy.level(player, "Tips"))
	pay *= 1 + Config.QuickServeBonus * math.clamp(patienceLeft, 0, 1)
	if isNightCustomer then
		pay *= Config.NightPayMultiplier
	end
	if player:GetAttribute("DoubleCash") then
		pay *= 2
	end
	local amount = math.max(1, math.floor(pay + 0.5))
	PlayerData.addCash(player, amount)
	PlayerData.addServed(player)
	return amount
end

local function refreshDoubleCash(player: Player)
	local passId = Config.GamePasses.DoubleCash
	if passId == 0 then
		return
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
	if ok and owns then
		player:SetAttribute("DoubleCash", true)
	end
end

function Economy.start()
	Workspace:SetAttribute("DoubleCashPassId", Config.GamePasses.DoubleCash)

	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("Carrying", 0)
		task.spawn(refreshDoubleCash, player)
		player.CharacterAdded:Connect(function()
			player:SetAttribute("Carrying", 0)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("Carrying", 0)
		task.spawn(refreshDoubleCash, player)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and passId == Config.GamePasses.DoubleCash then
			player:SetAttribute("DoubleCash", true)
			Economy.toast(player, "2x Cash unlocked. Thank you!")
		end
	end)

	Remotes.BuyUpgrade.OnServerInvoke = function(player: Player, upgradeName: any)
		if typeof(upgradeName) ~= "string" or not Config.Upgrades[upgradeName] then
			return false, "Unknown upgrade"
		end
		local level = Economy.level(player, upgradeName)
		local price = Config.nextPrice(upgradeName, level)
		if not price then
			return false, "Already maxed"
		end
		if not PlayerData.spendCash(player, price) then
			return false, "Not enough " .. Config.CurrencyName
		end
		PlayerData.setUpgrade(player, upgradeName, level + 1)
		return true, Config.Upgrades[upgradeName].DisplayName .. " level " .. (level + 1) .. "!"
	end
end

return Economy
