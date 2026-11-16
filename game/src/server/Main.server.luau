-- Server entry point. Starts every system in order.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

require(game:GetService("ReplicatedStorage").Shared.Remotes) -- creates the remotes first

local PlayerData = require(script.Parent.PlayerData)
local ShopWorld = require(script.Parent.ShopWorld)
local Economy = require(script.Parent.Economy)
local Kitchen = require(script.Parent.Kitchen)
local Customers = require(script.Parent.Customers)
local DayNight = require(script.Parent.DayNight)

-- Customers walk through each other and through players, so nobody blocks the queue.
PhysicsService:RegisterCollisionGroup("Customers")
PhysicsService:RegisterCollisionGroup("Players")
PhysicsService:CollisionGroupSetCollidable("Customers", "Customers", false)
PhysicsService:CollisionGroupSetCollidable("Customers", "Players", false)

local function onCharacter(character: Model)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Players"
		end
	end
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Players"
		end
	end)
end
local function onPlayer(player: Player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end

local shop = ShopWorld.get()
PlayerData.start()
Economy.start()
Kitchen.start(shop.Station)
Customers.start(shop)
DayNight.start()

print("[Main] Shop is open.")
