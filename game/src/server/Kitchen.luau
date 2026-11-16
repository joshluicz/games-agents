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

	-- A little sparkle burst when something is made
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "MakeSparkles"
	sparkles.Enabled = false
	sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 170, 200))
	sparkles.LightEmission = 0.6
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Lifetime = NumberRange.new(0.5, 0.9)
	sparkles.Speed = NumberRange.new(4, 8)
	sparkles.SpreadAngle = Vector2.new(60, 60)
	sparkles.Acceleration = Vector3.new(0, -6, 0)
	sparkles.EmissionDirection = Enum.NormalId.Top
	sparkles.Parent = station

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
		sparkles:Emit(14)
	end)
end

return Kitchen
