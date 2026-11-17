-- Server entry point: collision groups, then every system's start() in the plan's order (build plan Task 0;
-- the depth update's systems per docs/plan/2026-11-16-depth-update-build-plan.md §B10; Progression v2's per
-- docs/plan/2026-11-16-progression-v2-build-plan.md §B10), then the clinic's doors (World/Doors; the Real Clinic).
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
	"Levels", -- hospital levels: before anything asks for a level, the line or the floors
	"Lift", -- the hospital lift (Progression v2): after the buildings exist
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
	"Nurses", -- nurses on plots, the nurse tray, the journal
	"Abilities", -- nurse abilities (Progression v2): after Nurses, before Treatment and Patients ask it
	"Treatment", -- treat sessions and mini-game results (Patients calls it)
	"Patients",
	"NurseBelt", -- the shared belt in town (calls Nurses)
	"Agency", -- the Nurse Agency kiosk (Progression v2; calls Nurses)
	"Market", -- the Player Market kiosk (Progression v2; calls Nurses)
	"Rebirth", -- "Open a new branch" (Progression v2; calls Patients, Treatment, Nurses, Plots)
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

-- The Real Clinic's doors (Server/World/Doors): they slide open for anyone near and stay shut while their room or
-- level isn't open. It finds the doors by tag, so the buildings Plots made above (and every rebuild) are covered.
do
	local ok, err = xpcall(function()
		local Doors = require(Server.World.Doors) :: any
		Doors.start()
	end, debug.traceback)
	if not ok then
		warn("[Main] Doors.start() failed:\n" .. tostring(err))
	end
end

-- Look overhaul (§B10): the tutorial's Replay empties the caller's own line through Patients.reopen. Patients
-- requires Tutorial, so Tutorial can never require Patients: the hook is handed over here, once both have started.
do
	local ok, err = pcall(function()
		local Tutorial = require(Server.Tutorial) :: any
		local Patients = require(Server.Patients) :: any
		Tutorial.setReopen(Patients.reopen)
	end)
	if not ok then
		warn("[Main] Tutorial.setReopen failed: " .. tostring(err))
	end
end

print("[Main] Clinic is open.")
