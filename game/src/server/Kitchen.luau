-- The station: hold to make the product. The hold time shrinks with the Faster Hands upgrade.
-- The client shortens its own prompt's HoldDuration; the server checks the real time held.

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Economy = require(script.Parent.Economy)

local Kitchen = {}

function Kitchen.start(station: BasePart)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "MakePrompt"
	prompt.ActionText = Config.StationAction .. " " .. Config.ProductName
	prompt.ObjectText = "Station"
	prompt.HoldDuration = Config.makeSeconds(0)
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = station

	local holdStarted: { [Player]: number } = {}
	local holdEnded: { [Player]: number } = {}

	prompt.PromptButtonHoldBegan:Connect(function(player)
		holdStarted[player] = os.clock()
		holdEnded[player] = nil
	end)
	prompt.PromptButtonHoldEnded:Connect(function(player)
		holdEnded[player] = os.clock()
	end)

	prompt.Triggered:Connect(function(player)
		local started = holdStarted[player]
		local ended = holdEnded[player] or os.clock()
		holdStarted[player] = nil
		holdEnded[player] = nil
		local needed = Config.makeSeconds(Economy.level(player, "Speed"))
		if not started or os.clock() - started > 10 or ended - started + 0.25 < needed then
			return -- released early, stale, or a spoofed trigger
		end
		local carrying = Economy.carrying(player)
		if carrying >= Economy.capacity(player) then
			Economy.toast(player, "Tray full! Serve a customer.")
			return
		end
		Economy.setCarrying(player, carrying + 1)
	end)
end

return Kitchen
