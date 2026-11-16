--!strict
-- Every RemoteEvent and RemoteFunction, in ReplicatedStorage.Remotes (build plan §B4).
-- The server creates them when this module is first required (Main does that first); clients wait for them.
--
-- Server -> client events:  Toast(text) · State(snapshot) · Cured(info) · DayReport(report)
-- Client -> server functions (each returns ok: boolean, message: string, except GetState):
--   Purchase(kind, id) · PlaceDecor(slotKey, decorId?) · ClaimGoal(index) · ClaimMailbox() · GetState() -> Snapshot
--   TutorialAck()   the welcome card was tapped (or shown 4 s). Server/Tutorial: it only ever moves step 1 -> 2
--   Discard(itemId)     throw one held item away (the ✖ on the HUD hand); Server/Stations, rate-limited
--   Admin(action, arg?)   the 🛠️ Admin panel. Server/Admin checks the caller is an admin on every call (a
--                   non-admin gets false and nothing happens) and validates action and arg (Logic/Admin)
--   GetBoards() -> Payload?   the 🏆 leaderboards from the server's cache, with your own rank (Server/Leaderboards;
--                   never a DataStore call, nil when rate-limited)
--
-- Server helpers (call only on the server):
--   Remotes.serve(name, handler)  wires a RemoteFunction with the rate limit and error safety built in
--   Remotes.allow(player, name)   the per-player, per-remote rate limit (Config.RemoteRatePerSecond)
--   Remotes.toast(player, text)   always shown: a reply to what the player did, or a warning
--   Remotes.news(player, text)    ambient news (a goal done, a new day, a room unlocked...): held back while the
--                                 player is quiet (Server/Tutorial: the first-session tutorial is running)
--   Remotes.toastAll(text)        news for everyone in the server, skipping quiet players
--   Remotes.setQuiet(fn) / Remotes.isQuiet(player)   who is quiet right now (Server/Tutorial sets fn)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)

local FOLDER_NAME = "Remotes"
local EVENTS = { "Toast", "State", "Cured", "DayReport" }
local FUNCTIONS = {
	"Purchase",
	"PlaceDecor",
	"ClaimGoal",
	"ClaimMailbox",
	"GetState",
	"TutorialAck",
	"Admin",
	"Discard",
	"GetBoards",
}

local IS_SERVER = RunService:IsServer()

local folder: Folder
if IS_SERVER then
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in FUNCTIONS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local Remotes = {
	-- server -> client
	Toast = folder:WaitForChild("Toast") :: RemoteEvent,
	State = folder:WaitForChild("State") :: RemoteEvent,
	Cured = folder:WaitForChild("Cured") :: RemoteEvent,
	DayReport = folder:WaitForChild("DayReport") :: RemoteEvent,
	-- client -> server
	Purchase = folder:WaitForChild("Purchase") :: RemoteFunction,
	PlaceDecor = folder:WaitForChild("PlaceDecor") :: RemoteFunction,
	ClaimGoal = folder:WaitForChild("ClaimGoal") :: RemoteFunction,
	ClaimMailbox = folder:WaitForChild("ClaimMailbox") :: RemoteFunction,
	GetState = folder:WaitForChild("GetState") :: RemoteFunction,
	TutorialAck = folder:WaitForChild("TutorialAck") :: RemoteFunction,
	Admin = folder:WaitForChild("Admin") :: RemoteFunction,
	Discard = folder:WaitForChild("Discard") :: RemoteFunction,
	GetBoards = folder:WaitForChild("GetBoards") :: RemoteFunction,
}

-- Short, friendly replies. On-screen words stay at 6 or fewer.
Remotes.TOO_FAST = "Too fast! Try again."
Remotes.OOPS = "Oops! Try again."

------------------------------------------------------------------------------------------------------------------
-- Server helpers
------------------------------------------------------------------------------------------------------------------

type Bucket = { Tokens: number, At: number }
local buckets: { [Player]: { [string]: Bucket } } = {}

local function assertServer(what: string)
	assert(IS_SERVER, "Remotes." .. what .. " is server-only")
end

-- Token bucket: Config.RemoteRatePerSecond calls per second per remote per player, with a burst of the same size.
function Remotes.allow(player: Player, name: string): boolean
	assertServer("allow")
	local rate = Config.RemoteRatePerSecond
	local now = os.clock()
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local bucket = perPlayer[name]
	if not bucket then
		bucket = { Tokens = rate, At = now }
		perPlayer[name] = bucket
	end
	bucket.Tokens = math.min(rate, bucket.Tokens + (now - bucket.At) * rate)
	bucket.At = now
	if bucket.Tokens < 1 then
		return false
	end
	bucket.Tokens -= 1
	return true
end

-- Wires a client -> server RemoteFunction that answers (ok: boolean, message: string).
-- The handler gets the raw, untrusted arguments: type-check every one of them before using it.
-- Rate limiting and error safety are done here, so a handler that errors answers OOPS instead of erroring
-- on the client.
function Remotes.serve(name: string, handler: (Player, ...any) -> (boolean, string?))
	assertServer("serve")
	local remote = folder:FindFirstChild(name)
	assert(remote and remote:IsA("RemoteFunction"), "No RemoteFunction named " .. name)
	remote.OnServerInvoke = function(player: Player, ...: any)
		if not Remotes.allow(player, name) then
			return false, Remotes.TOO_FAST
		end
		local ok, result, message = pcall(handler, player, ...)
		if not ok then
			warn("[Remotes] " .. name .. " handler failed:", result)
			return false, Remotes.OOPS
		end
		return result == true, if typeof(message) == "string" then message else ""
	end
end

function Remotes.toast(player: Player, text: string)
	assertServer("toast")
	if typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players then
		Remotes.Toast:FireClient(player, text)
	end
end

-- Quiet players (the first-session tutorial) only get toasts that help them right now: replies and warnings.
local quietCheck: ((Player) -> boolean)? = nil

function Remotes.setQuiet(fn: ((Player) -> boolean)?)
	assertServer("setQuiet")
	quietCheck = fn
end

function Remotes.isQuiet(player: Player): boolean
	local check = quietCheck
	if not check then
		return false
	end
	local ok, quiet = pcall(check, player)
	return ok and quiet == true
end

function Remotes.news(player: Player, text: string)
	assertServer("news")
	if not Remotes.isQuiet(player) then
		Remotes.toast(player, text)
	end
end

function Remotes.toastAll(text: string)
	assertServer("toastAll")
	for _, player in Players:GetPlayers() do
		if not Remotes.isQuiet(player) then
			Remotes.Toast:FireClient(player, text)
		end
	end
end

if IS_SERVER then
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

return Remotes
