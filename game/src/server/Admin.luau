--!strict
-- The 🛠️ Admin panel's server side (game/README.md "Admin panel"): quick progression tests for the two developer
-- accounts, in the live game and in Studio. Server only; the rules are in Shared/Logic/Admin (Lune-tested).
--
-- Who is an admin is decided here, never by the client (Logic/Admin.isAdmin):
--   · a UserId in Config.AdminUserIds (checked first)
--   · the game's owner: game.CreatorType is User and the player's UserId is game.CreatorId
--   · a username in Config.AdminNames. Each one is turned into a UserId once at startup
--     (Players:GetUserIdFromNameAsync, in a pcall, retried) and printed in Output as "[Admin] <name> = <id>", so the
--     id can be copied into Config.AdminUserIds (a username can change hands, an id can't)
--   · in Studio (RunService:IsStudio()), anyone playing
-- Every admin gets the player attribute IsAdmin = true (the HUD's ⚙️ panel shows the 🛠️ button for it). The
-- attribute only steers the UI: the Admin remote checks again on every call.
--
-- The Admin remote, Admin(action: string, arg: any) -> (ok, message), is wired with Remotes.serve (rate limit and
-- pcall). In order: a non-admin gets false and nothing happens (one warning per player per session); the action
-- must be in Logic/Admin.ACTIONS with exactly the argument it takes; the whole-server actions need the admin alone
-- in the server, or Studio; then "[Admin] <name> <action> [arg]" is printed and it runs. Replies are short, for a
-- toast. Actions:
--   your own save      AddCash (1000 | 10000) · AddStars (10 | 100) · UnlockRooms (free, every room) · AllDecor ·
--                      FinishTutorial · RestartTutorial (also empties your line and respawns you, so the welcome
--                      plays) · ResetDaily (today's goals and the mailbox) · CompleteBook · StoriesDue ·
--                      SpawnPatient (a Data/Patients id: it's next in your own line)
--   the whole server   SkipToNight · SkipToDay (Workspace.SkipPhase, as in DayNight) · ToggleWinter
--                      (Workspace.ForceWinter, as in Events)
-- Everything goes through the systems' own APIs (Economy, Progress, Plots, Book, Story, Daily, Tutorial, Patients),
-- so saving, toasts and snapshots work exactly as they do in play.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local AdminLogic = require(Shared.Logic.Admin)
local Rooms = require(Shared.Data.Rooms)
local Decor = require(Shared.Data.Decor)
local PatientsData = require(Shared.Data.Patients)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)
local Economy = require(script.Parent.Economy)
local Progress = require(script.Parent.Progress)
local Book = require(script.Parent.Book)
local Story = require(script.Parent.Story)
local Daily = require(script.Parent.Daily)
local Tutorial = require(script.Parent.Tutorial)
local Patients = require(script.Parent.Patients)
local Events = require(script.Parent.Events)

local Admin = {}

Admin.ATTRIBUTE = "IsAdmin"

local IS_STUDIO = RunService:IsStudio()
local LOOKUP_TRIES = 3
local RESPAWN_DELAY = 0.6 -- after the new step's snapshot (debounced 0.2 s) has reached the client

local LOADING = "⏳ One moment!"
local NOT_ALONE = "👥 Only when you're alone!"

local resolved: { [number]: boolean } = {} -- UserIds of Config.AdminNames, looked up at startup
local warned: { [Player]: boolean } = {}

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function adminIds(): { number }
	local ids: { number } = {}
	for _, id in Config.AdminUserIds do
		if type(id) == "number" then
			table.insert(ids, id)
		end
	end
	return ids
end

function Admin.isAdmin(player: Player): boolean
	if not isPlayer(player) then
		return false
	end
	return AdminLogic.isAdmin(player.UserId, {
		Studio = IS_STUDIO,
		CreatorIsUser = game.CreatorType == Enum.CreatorType.User,
		CreatorId = game.CreatorId,
		UserIds = adminIds(),
		Resolved = resolved,
	})
end

local function mark(player: Player)
	if player.Parent == Players then
		player:SetAttribute(Admin.ATTRIBUTE, if Admin.isAdmin(player) then true else nil)
	end
end

local function markAll()
	for _, player in Players:GetPlayers() do
		mark(player)
	end
end

-- Config.AdminNames -> UserIds, once at startup. Every result is printed so it can be hard-coded.
local function resolveNames()
	for _, name in Config.AdminNames do
		if type(name) ~= "string" or name == "" then
			continue
		end
		local found = false
		local lastError: any = nil
		for attempt = 1, LOOKUP_TRIES do
			local ok, result = pcall(function()
				return Players:GetUserIdFromNameAsync(name)
			end)
			if ok and type(result) == "number" and result > 0 then
				resolved[result] = true
				print(("[Admin] %s = %s"):format(name, tostring(result)))
				found = true
				break
			end
			lastError = result
			if attempt < LOOKUP_TRIES then
				task.wait(2 ^ attempt) -- 2 s, 4 s
			end
		end
		if not found then
			warn("[Admin] Could not look up " .. name .. " (not an admin this server): " .. tostring(lastError))
		end
	end
	markAll()
end

------------------------------------------------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------------------------------------------------

local function commas(n: number): string
	local digits = tostring(math.floor(n))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	return if string.sub(grouped, 1, 1) == "," then string.sub(grouped, 2) else grouped
end

local function loaded(player: Player): boolean
	return PlayerData.get(player) ~= nil
end

-- Moves the day/night cycle on now (DayNight polls Workspace.SkipPhase).
local function skipTo(night: boolean): (boolean, string)
	local isNight = Workspace:GetAttribute("IsNight") == true
	if isNight == night then
		return false, if night then "🌙 It's night already!" else "☀️ It's day already!"
	end
	Workspace:SetAttribute("SkipPhase", true)
	return true, if night then "🌙 Night is coming!" else "☀️ Morning is coming!"
end

type Run = (player: Player, arg: any) -> (boolean, string)

local RUN: { [string]: Run } = {
	AddCash = function(player, amount)
		if not Economy.addCash(player, amount) then
			return false, LOADING
		end
		return true, "💰 +" .. commas(amount)
	end,

	AddStars = function(player, amount)
		if not Progress.addStars(player, amount) then
			return false, LOADING
		end
		return true, "⭐ +" .. commas(amount)
	end,

	-- Free, through Plots.unlockRoom (the same call a story reward uses), so no purchase fires.
	UnlockRooms = function(player)
		local data = PlayerData.get(player)
		if not data then
			return false, LOADING
		end
		local opened = 0
		for _, roomId in Rooms.Order do
			if not data.Rooms[roomId] and Plots.unlockRoom(player, roomId) then
				opened += 1
			end
		end
		return true, if opened > 0 then "🏠 +" .. opened .. " rooms!" else "🏠 All rooms open!"
	end,

	AllDecor = function(player)
		local added = 0
		local saved = PlayerData.update(player, function(d)
			for _, decorId in Decor.Order do
				if not d.Decor.Owned[decorId] then
					d.Decor.Owned[decorId] = true
					added += 1
				end
			end
		end)
		if not saved then
			return false, LOADING
		end
		return true, if added > 0 then "🌸 +" .. added .. " decor!" else "🌸 All decor owned!"
	end,

	FinishTutorial = function(player)
		if not loaded(player) then
			return false, LOADING
		end
		return true, if Tutorial.finish(player) then "🎓 Tutorial done!" else "🎓 Already done!"
	end,

	-- The welcome needs an empty clinic (its first patient comes on the tutorial's cue) and the client's arrival
	-- (the title card and sweep play when your character reaches your clinic), so: empty the line, go back to the
	-- welcome card, then respawn.
	RestartTutorial = function(player)
		if not loaded(player) then
			return false, LOADING
		end
		Patients.reopen(player)
		if not Tutorial.restart(player) then
			return false, Remotes.OOPS
		end
		task.delay(RESPAWN_DELAY, function()
			if player.Parent == Players then
				local ok, err = pcall(function()
					player:LoadCharacter()
				end)
				if not ok then
					warn("[Admin] Respawn failed:", err)
				end
			end
		end)
		return true, "🔄 Tutorial restarted!"
	end,

	ResetDaily = function(player)
		if not Daily.resetToday(player) then
			return false, LOADING
		end
		return true, "🎯 Goals and 📬 mail reset!"
	end,

	CompleteBook = function(player)
		local added = Book.completeAll(player)
		if added == nil then
			return false, LOADING
		end
		return true, if added > 0 then "📖 +" .. added .. " pages!" else "📖 Book already full!"
	end,

	StoriesDue = function(player)
		local held = Story.makeDue(player)
		if held == nil then
			return false, LOADING
		end
		return true, "💌 Story beats ready today!"
	end,

	SpawnPatient = function(player, patientId)
		if not loaded(player) then
			return false, LOADING
		end
		return Patients.sendNext(player, patientId)
	end,

	SkipToNight = function()
		return skipTo(true)
	end,

	SkipToDay = function()
		return skipTo(false)
	end,

	-- ForceWinter on, or back to the calendar (which may still say winter: Config.Winter).
	ToggleWinter = function()
		local forced = Workspace:GetAttribute("ForceWinter") == true
		Workspace:SetAttribute("ForceWinter", if forced then nil else true)
		if Events.isWinter() then
			return true, if forced then "❄️ Still winter (calendar)!" else "❄️ Winter on!"
		end
		return true, "👋 Winter off!"
	end,
}

------------------------------------------------------------------------------------------------------------------
-- The remote
------------------------------------------------------------------------------------------------------------------

local function refuse(player: Player)
	if not warned[player] then
		warned[player] = true
		warn(("[Admin] Refused %s (%s): not an admin"):format(player.Name, tostring(player.UserId)))
	end
end

local function handle(player: Player, action: any, arg: any): (boolean, string)
	if not Admin.isAdmin(player) then
		refuse(player)
		return false, ""
	end
	if not AdminLogic.valid(action, arg, PatientsData) then
		return false, Remotes.OOPS
	end
	local run = RUN[action :: string]
	if not run then
		return false, Remotes.OOPS -- in Logic/Admin.ACTIONS but not here: a bug, never the client's doing
	end
	if AdminLogic.serverWide(action) and not AdminLogic.serverWideAllowed(IS_STUDIO, #Players:GetPlayers()) then
		return false, NOT_ALONE
	end
	print(("[Admin] %s %s%s"):format(player.Name, action, if arg ~= nil then " " .. tostring(arg) else ""))
	return run(player, arg)
end

function Admin.start()
	Remotes.serve("Admin", handle)
	Players.PlayerAdded:Connect(mark)
	Players.PlayerRemoving:Connect(function(player)
		warned[player] = nil
	end)
	markAll()
	if IS_STUDIO then
		print("[Admin] Studio: everyone playing is an admin (⚙️ → 🛠️ Admin)")
	end
	task.spawn(resolveNames)
end

return Admin
