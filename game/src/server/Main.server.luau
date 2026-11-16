-- Server entry point: collision groups, then every system's start() in the plan's order (build plan Task 0).
-- A system whose start() errors is reported and skipped, so one broken module never stops the clinic opening.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

require(game:GetService("ReplicatedStorage").Shared.Remotes) -- creates the remotes first

local Server = script.Parent

-- Patients walk through each other and through players, so nobody blocks the queue.
-- Put every creature part in the "Patients" group (CreatureBuilder does).
PhysicsService:RegisterCollisionGroup("Patients")
PhysicsService:RegisterCollisionGroup("Players")
PhysicsService:CollisionGroupSetCollidable("Patients", "Patients", false)
PhysicsService:CollisionGroupSetCollidable("Patients", "Players", false)

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

local START_ORDER = {
	"PlayerData",
	"State",
	"Events",
	"Plots",
	"Carry",
	"Economy",
	"Progress",
	"Book",
	"Story",
	"Daily",
	"DayReport",
	"Tutorial", -- before Stations and Patients: the quiet toasts and its listeners are set before patients come
	"Boosts",
	"Badges", -- seeds old saves' counters on load, levels badges up on every save change
	"Playtime", -- after Plots and Daily: counts active play, the play gifts and Doctor ranks
	"Stations",
	"Patients",
	"Visits",
	"Leaderboards", -- after Plots (the town is built) and Visits; reads PlayerData's saves
	"DayNight",
	"Admin", -- last: the 🛠️ Admin remote calls into the systems above
}

for _, name in START_ORDER do
	local moduleScript = Server:FindFirstChild(name)
	if not (moduleScript and moduleScript:IsA("ModuleScript")) then
		warn("[Main] Missing system " .. name)
		continue
	end
	local ok, err = xpcall(function()
		local system = require(moduleScript) :: any
		system.start()
	end, debug.traceback)
	if not ok then
		warn("[Main] " .. name .. ".start() failed:\n" .. tostring(err))
	end
end

print("[Main] Clinic is open.")
