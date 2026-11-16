--!strict
-- Today's Visitor, banked daily goals and the mailbox (build plan §B5, design §5.4-5.5). Server only.
--   Daily.visitorFor(p): PatientId?   today's visitor for p's clinic: once per player per UTC day (see below)
--   Daily.visitorStatus(p)            "Coming" | "Done" | "None": what p's HUD chip shows (State's Snapshot)
--   Daily.onCure(p, ctx)              p is the helper: their goals move; ctx.Visitor marks the OWNER's visitor done
--   Daily.onMake(p, itemId)           Stations calls it after a treatment is made
--   Daily.today(): number             the current UTC day (Visits and anything else that needs "today")
--   Daily.resetToday(p): boolean      the 🛠️ Admin panel only (Server/Admin): today starts over for p, as if they'd
--                                     just come in: the goals handed out today go, today's goal is handed out again
--                                     (when the bank has room) and the mailbox opens. Older banked goals stay
--   start(): goals on join, wires ClaimGoal and ClaimMailbox, keeps Workspace.UtcDay and TodaysVisitor up to date
--
-- The day. A story/daily day is a real UTC calendar day (os.time() // 86400). Workspace.UtcDay is checked every
-- minute and exactly at midnight, so the rollover lands mid-session within a second, without a rejoin: the
-- visitor changes, everyone in the server gets their new goal, and the mailbox opens (State re-sends snapshots
-- when UtcDay changes). In Studio only, a UtcDay set FORWARD by hand (testing: execute_luau
-- `workspace:SetAttribute("UtcDay", workspace:GetAttribute("UtcDay") + 1)`) is a real rollover and sticks until the
-- clock catches up; Story and Events read the same attribute the same way. Setting it below the real day snaps it
-- back. Live servers always use the real day, and a save that picked up a future day in a Studio test is pulled
-- back to the real day when it loads (Schema.reconcile).
--
-- No streaks and no penalties (design §5.5):
--   · one new goal per UTC day, banked up to Config.MaxBankedGoals; a full bank just waits, nothing expires
--   · only goals the player can finish are handed out (a Bath goal needs the Bath Room)
--   · the mailbox gift is Config.MailboxGiftCash once per UTC day, the same however long you were away
--
-- Today's Visitor is one day patient, the same for everyone (Logic/Daily.visitor over the evergreen day
-- patients). visitorFor only offers it to a clinic that can treat it, and holds it for VISITOR_HOLD_SECONDS while
-- it's out. Once cured it's done for the day: the owner's save keeps the day (Data.VisitorDay), so another
-- server or a rejoin can't hand it out again. A visitor handed out before UTC midnight and cured after it
-- counts for the day it came, so it never uses up the new day's visitor. If it leaves uncured, it comes back
-- after the hold: missing it is never a loss.
--
-- Remotes (Remotes.serve: rate limit + pcall). Every argument is untrusted:
--   ClaimGoal(index: number)   an integer 1..#goals whose goal reached its target -> cash + Clinic Stars
--   ClaimMailbox()             once per UTC day -> Config.MailboxGiftCash

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local DailyLogic = require(Shared.Logic.Daily)
local DailyGoals = require(Shared.Data.DailyGoals)
local Patients = require(Shared.Data.Patients)
local Regulars = require(Shared.Data.Regulars)
local Rooms = require(Shared.Data.Rooms)
local Ailments = require(Shared.Data.Ailments)
local Items = require(Shared.Data.Items)
local PlayerData = require(script.Parent.PlayerData)
local Economy = require(script.Parent.Economy)
local Progress = require(script.Parent.Progress)

local Daily = {}

local VISITOR_HOLD_SECONDS = 300 -- longer than any patient waits (patience + chairs + queue + recovery)
local MAX_CHECK_SECONDS = 60

local POOL = DailyGoals :: { DailyLogic.GoalDef }

local started = false
local currentDay = DailyLogic.day(os.time())
local visitorPool: { string } = {}
-- UserId -> the visitor handed out to that clinic and not yet cured: the day it was handed out, and the hold.
local visitorOut: { [number]: { Day: number, Until: number } } = {}
local IS_STUDIO = RunService:IsStudio()

------------------------------------------------------------------------------------------------------------------
-- Content lookups
------------------------------------------------------------------------------------------------------------------

-- rawget: the Data maps carry `Order` through a metatable, which is never an id.
local function patientRow(id: string): Types.Patient?
	return rawget(Patients :: any, id)
end

local function regularRow(id: string): Types.Regular?
	return rawget(Regulars :: any, id)
end

local function stationFor(patientId: string): string?
	local patient = patientRow(patientId)
	local ailment = patient and rawget(Ailments :: any, patient.Ailment)
	return ailment and ailment.Station
end

local function ownedStations(data: Types.Data): { [string]: boolean }
	local stations: { [string]: boolean } = {}
	for roomId, owned in data.Rooms do
		local room = rawget(Rooms :: any, roomId)
		if owned and room then
			for _, stationId in room.Stations do
				stations[stationId] = true
			end
		end
	end
	return stations
end

local function canTreat(data: Types.Data, patientId: string): boolean
	local station = stationFor(patientId)
	return station ~= nil and ownedStations(data)[station] == true
end

-- The wings whose patients this clinic can treat: a CureWing goal is only handed out for one of these.
local function treatableWings(data: Types.Data): { [string]: boolean }
	local stations = ownedStations(data)
	local wings: { [string]: boolean } = {}
	for _, patientId in Patients.Order do
		local station = stationFor(patientId)
		if station and stations[station] then
			wings[(patientRow(patientId) :: Types.Patient).Wing] = true
		end
	end
	return wings
end

-- Today's Visitor comes from the day patients whose station is in a year-round room, so a seasonal wing never
-- leaves most clinics without a visitor.
local function buildVisitorPool(): { string }
	local evergreen: { [string]: boolean } = {}
	for _, roomId in Rooms.Order do
		local room = Rooms[roomId]
		if room.Season == nil then
			for _, stationId in room.Stations do
				evergreen[stationId] = true
			end
		end
	end
	local pool = {}
	for _, patientId in Patients.Order do
		local patient = patientRow(patientId) :: Types.Patient
		local station = stationFor(patientId)
		if not patient.Night and station and evergreen[station] then
			table.insert(pool, patientId)
		end
	end
	return pool
end

-- The wing a cured patient belongs to (a regular's own wing, else its patient row's). nil if unknown.
local function wingOf(ctx: Types.CureCtx): string?
	local regularId: any = ctx.Regular
	local patientId: any = ctx.PatientId
	local row: any = (type(regularId) == "string" and regularRow(regularId))
		or (type(patientId) == "string" and (patientRow(patientId) or regularRow(patientId)))
		or nil
	return if row and type(row.Wing) == "string" then row.Wing else nil
end

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

------------------------------------------------------------------------------------------------------------------
-- Goals
------------------------------------------------------------------------------------------------------------------

local function sameProgress(a: Types.DailyData, b: Types.DailyData): boolean
	if #a.Goals ~= #b.Goals or a.LastGrantDay ~= b.LastGrantDay then
		return false
	end
	for i, goal in a.Goals do
		local other = b.Goals[i]
		if goal.Id ~= other.Id or goal.Progress ~= other.Progress then
			return false
		end
	end
	return true
end

-- Tidies goals whose content was removed, then banks today's goal if it's a new day. Returns goals added.
local function grantFor(player: Player): number
	local data = PlayerData.get(player)
	if not data then
		return 0
	end
	local before = #data.Daily.Goals
	local eligible = DailyLogic.eligible(POOL, treatableWings(data))
	local nextDaily = DailyLogic.grant(DailyLogic.prune(data.Daily, POOL), currentDay, eligible, Config.MaxBankedGoals)
	if sameProgress(nextDaily, data.Daily) then
		return 0
	end
	PlayerData.update(player, function(d)
		d.Daily = nextDaily
	end)
	return math.max(0, #nextDaily.Goals - before)
end

local function progress(player: Player, kind: string, event: DailyLogic.EventCtx)
	local data = PlayerData.get(player)
	if not data then
		return
	end
	event.Pool = POOL
	local nextDaily = DailyLogic.onEvent(data.Daily, kind, event)
	if sameProgress(nextDaily, data.Daily) then
		return
	end
	local readyBefore = DailyLogic.readyCount(data.Daily, POOL)
	PlayerData.update(player, function(d)
		d.Daily = nextDaily
	end)
	if DailyLogic.readyCount(nextDaily, POOL) > readyBefore then
		Remotes.news(player, "🎯 Goal done! Claim it!")
	end
end

------------------------------------------------------------------------------------------------------------------
-- The day
------------------------------------------------------------------------------------------------------------------

-- The real UTC day, unless Workspace.UtcDay was set further forward in Studio (testing).
local function resolveDay(): number
	local real = DailyLogic.day(os.time())
	local attribute = Workspace:GetAttribute("UtcDay")
	if
		IS_STUDIO
		and type(attribute) == "number"
		and attribute % 1 == 0
		and attribute > real
		and attribute < math.huge
	then
		return attribute
	end
	return real
end

-- (visitorOut entries from an earlier day stay until that visitor is cured or its clinic closes: onCure needs
-- the day it was handed out, and visitorFor ignores any entry that isn't from today.)
local function onNewDay()
	for _, player in Players:GetPlayers() do
		if PlayerData.get(player) then
			local added = grantFor(player)
			Remotes.news(player, if added > 0 then "🌅 New day! Mail and a goal!" else "🌅 New day! Mail is here!")
		end
	end
end

-- Brings currentDay and the Workspace attributes up to date. Safe to call from anywhere, any time.
-- TodaysVisitor is only written when the day changes, so a hand-set visitor (testing) lasts until midnight.
local function refreshDay(): number
	local day = resolveDay()
	local rolled = day > currentDay
	local visitor = Workspace:GetAttribute("TodaysVisitor")
	if day ~= currentDay or type(visitor) ~= "string" or visitor == "" then
		currentDay = day
		Workspace:SetAttribute("TodaysVisitor", DailyLogic.visitor(currentDay, visitorPool))
	end
	if Workspace:GetAttribute("UtcDay") ~= currentDay then
		Workspace:SetAttribute("UtcDay", currentDay)
	end
	if rolled and started then
		onNewDay()
	end
	return currentDay
end

------------------------------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------------------------------

function Daily.today(): number
	return refreshDay()
end

function Daily.visitorFor(player: Player): string?
	if not isPlayer(player) then
		return nil
	end
	local today = refreshDay()
	local visitor = Workspace:GetAttribute("TodaysVisitor")
	if type(visitor) ~= "string" or not patientRow(visitor) then
		return nil
	end
	local data = PlayerData.get(player)
	if not data or data.VisitorDay == today then
		return nil -- cured today already (on any server: it's in the save)
	end
	local userId = player.UserId
	local out = visitorOut[userId]
	if out and out.Day == today and os.clock() < out.Until then
		return nil
	end
	if not canTreat(data, visitor) then
		return nil
	end
	visitorOut[userId] = { Day = today, Until = os.clock() + VISITOR_HOLD_SECONDS }
	return visitor
end

-- "Coming" | "Done" | "None" for the HUD chip (State puts it in the Snapshot). Never hands anything out.
function Daily.visitorStatus(player: Player): Types.VisitorStatus
	local visitor = Workspace:GetAttribute("TodaysVisitor")
	local data = PlayerData.get(player)
	if type(visitor) ~= "string" or not patientRow(visitor) or not data then
		return "None"
	end
	if data.VisitorDay == currentDay then
		return "Done"
	end
	if type(player:GetAttribute("PlotIndex")) ~= "number" or not canTreat(data, visitor) then
		return "None"
	end
	return "Coming"
end

-- Marks the owner's visitor done for the day it was handed out, if that's still today.
local function visitorCured(owner: Player, today: number)
	local out = visitorOut[owner.UserId]
	visitorOut[owner.UserId] = nil
	local handedOutOn = if out then out.Day else today
	if handedOutOn ~= today then
		return -- yesterday's visitor, cured after midnight: today's is still to come
	end
	PlayerData.update(owner, function(d)
		d.VisitorDay = today
	end)
end

function Daily.onCure(player: Player, ctx: Types.CureCtx)
	if not isPlayer(player) or type(ctx) ~= "table" then
		return
	end
	local today = refreshDay()
	if ctx.Visitor == true and isPlayer(ctx.Owner) then
		visitorCured(ctx.Owner, today)
	end
	progress(player, "Cure", { Night = ctx.Night == true, Wing = wingOf(ctx) })
end

function Daily.onMake(player: Player, itemId: string)
	if not isPlayer(player) or type(itemId) ~= "string" or not rawget(Items :: any, itemId) then
		return
	end
	refreshDay()
	progress(player, "Make", {})
end

function Daily.resetToday(player: Player): boolean
	if not isPlayer(player) or not PlayerData.get(player) then
		return false
	end
	local today = refreshDay()
	local reset = PlayerData.update(player, function(d)
		local kept: { Types.Goal } = {}
		for _, goal in d.Daily.Goals do
			if goal.Day < today then
				table.insert(kept, goal)
			end
		end
		d.Daily.Goals = kept
		d.Daily.LastGrantDay = math.min(d.Daily.LastGrantDay, today - 1)
		d.Mailbox.LastSeenDay = math.min(d.Mailbox.LastSeenDay, today - 1)
	end)
	if not reset then
		return false
	end
	grantFor(player)
	return true
end

------------------------------------------------------------------------------------------------------------------
-- Remotes
------------------------------------------------------------------------------------------------------------------

local function claimMailbox(player: Player): (boolean, string)
	local today = refreshDay()
	local data = PlayerData.get(player)
	if not data then
		return false, "⏳ One moment!"
	end
	local gift = DailyLogic.mailboxGift(data.Mailbox.LastSeenDay, today, Config.MailboxGiftCash)
	if gift <= 0 then
		return false, "📬 More mail tomorrow!"
	end
	-- Mark it seen and pay with no yield in between, so a second request can't pass the same check.
	local marked = PlayerData.update(player, function(d)
		d.Mailbox.LastSeenDay = today
	end)
	if not marked then
		return false, Remotes.OOPS
	end
	Economy.addCash(player, gift)
	return true, "📬 +" .. gift .. " " .. Config.CurrencyName .. "!"
end

local function claimGoal(player: Player, index: any): (boolean, string)
	if type(index) ~= "number" or index ~= index or index % 1 ~= 0 or index < 1 or index > 100 then
		return false, Remotes.OOPS
	end
	refreshDay()
	local data = PlayerData.get(player)
	if not data then
		return false, "⏳ One moment!"
	end
	if index > #data.Daily.Goals then
		return false, Remotes.OOPS
	end
	local nextDaily, reward = DailyLogic.claim(data.Daily, index, POOL)
	if not reward then
		return false, "🎯 Keep going!"
	end
	local claimed = PlayerData.update(player, function(d)
		d.Daily = nextDaily
	end)
	if not claimed then
		return false, Remotes.OOPS
	end
	if reward.Cash > 0 then
		Economy.addCash(player, reward.Cash)
	end
	if reward.Stars > 0 then
		Progress.addStars(player, reward.Stars)
	end
	return true, "🎯 +" .. reward.Cash .. " " .. Config.CurrencyName .. " +" .. reward.Stars .. " ⭐"
end

function Daily.start()
	visitorPool = buildVisitorPool()
	refreshDay()
	started = true

	PlayerData.Loaded:Connect(function(player: Player)
		refreshDay()
		grantFor(player)
	end)
	for _, player in Players:GetPlayers() do
		if PlayerData.get(player) then
			grantFor(player) -- loaded before we were listening
		end
	end

	-- The clinic closes on leave and its patients go with it, so a visitor that was out is free to come again.
	Players.PlayerRemoving:Connect(function(player: Player)
		visitorOut[player.UserId] = nil
	end)

	Remotes.serve("ClaimGoal", claimGoal)
	Remotes.serve("ClaimMailbox", claimMailbox)

	-- A forward-set UtcDay (testing) rolls the day straight away; anything else snaps back to the real day.
	Workspace:GetAttributeChangedSignal("UtcDay"):Connect(function()
		refreshDay()
	end)

	-- Each minute, and one second after every UTC midnight.
	task.spawn(function()
		while true do
			local untilMidnight = 86400 - os.time() % 86400
			task.wait(math.clamp(untilMidnight + 1, 1, MAX_CHECK_SECONDS))
			local ok, err = pcall(refreshDay)
			if not ok then
				warn("[Daily] Day refresh failed:", err)
			end
		end
	end)
end

return Daily
