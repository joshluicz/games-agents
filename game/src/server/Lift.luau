--!strict
-- The glass lift between the hospital's floors (Progression v2 build plan §B3/§B4/§B8; design §6). Server only.
-- OWNER: T6. The car moves only on clients (UI/LiftPanel); the server writes one PivotTo per rider at the far
-- landing after the ride, never a CFrame every frame.
--
--   Lift.start()                                 wires RideLift
--   Lift.ride(p, floor): (ok, message, payload?) the RideLift remote. In order (any failure: false + a short message,
--                                                nothing changes): `floor` is a whole number · the rider stands within
--                                                Config.Lift.CarDistance (+ a little slack for lag) of a landing of
--                                                some plot's Building, on that floor · `floor` exists on that building
--                                                (0..its Floors) and isn't the one they're on · they aren't riding
--                                                already · Config.Lift.Cooldown (1 s) per player. Then it answers at
--                                                once ({ Seconds, From, To }), sets the ride attributes below and, after
--                                                Config.Lift.RideSeconds x the rider's 🛗 Express Lift factor
--                                                (Logic/Rebirth.effects .Lift), PivotTo's the character to that landing
--                                                (re-found then: a rebuilt building still works; gone = they stay put)
--   Lift.carry(plot, models, floor): boolean     Patients and porters: yields the ride (RideSeconds x the plot
--                                                owner's Express Lift), then one PivotTo per model at the landing, side
--                                                by side (a character stands on it; a creature or nurse's pivot is the
--                                                ground under it). false: no such floor, junk, or the building lost it.
--                                                For the ride, each creature (not a character) carries the tag
--                                                LiftRider and the attributes LiftRideAt (the ride's server time, as in
--                                                the Lift's Ride) and LiftRideSlot (its Pure.spread place): every client
--                                                near the lift steps it into the car and slides it up with the car
--                                                (UI/LiftPanel), so it never waits outside and pops up
--   Lift.landing(plot, floor): CFrame?           that floor's landing (Building.Landing_0, Floor_<n>.Landing): the
--                                                floor point under the marker, facing out of the lift. nil: no lift
--   Lift.waitEscort(plot, seconds): Player?      enables the ground landing's EscortPrompt ("Ride with patient") and
--                                                yields until a player who can work the plot (Plots.canWork), standing
--                                                near it, triggers it, or `seconds` (<= 30) run out (nil). Several waits
--                                                at once are served oldest first; the prompt switches off when none is
--                                                left. A rebuilt building (a level-up) ends a wait with nil
--   Lift.Pure                                    the pure rules (tests/Hospital.spec)
-- Ride attributes, so every client can draw a ride with no remote and no per-frame writes:
--   Player.LiftRide   "<plotIndex>,<from>,<to>,<seconds>,<serverTime>" on each rider (RideLift, or a player's
--                     character in Lift.carry): their own UI/LiftPanel moves their character with the car
--   Lift.Ride         "<from>,<to>,<seconds>,<serverTime>" on the Building's Lift model for every ride and carry: every
--                     client near it slides its car (UI/LiftPanel)
--   Lift.Rider, Lift.RideAt   the rider's UserId (0: a patient or porter alone) and the ride's server time, set last:
--                     Feel/HospitalFX dings someone else's ride nearby (your own ride's Ding is UI/LiftPanel's)
-- Requires Plots (and PlayerData for the rider's tree); never Patients or Nurses.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local PerksData = require(Shared.Data.Perks)
local TreeData = require(Shared.Data.Tree)
local RebirthLogic = require(Shared.Logic.Rebirth)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)

type Plot = Types.Plot

local Lift = {}

------------------------------------------------------------------------------------------------------------------
-- Pure rules (no Roblox services; tests/Hospital.spec loads this block on its own)
------------------------------------------------------------------------------------------------------------------

-- PURE-BEGIN
local Pure = {}

Pure.REACH_SLACK = 3 -- studs past Config.Lift.CarDistance (the prompt reaches 8; lag and a step)
Pure.BELOW = 1.5 -- a rider's root may be this far under its landing's floor ...
Pure.ABOVE = 6.5 -- ... or this far over it (standing, jumping): never a whole storey (7)
Pure.MIN_FACTOR = 0.2 -- Express Lift never makes a ride shorter than this share
Pure.MAX_WAIT = 30 -- Lift.waitEscort waits at most this long
Pure.SPREAD = 2.8 -- studs between riders set down side by side

Pure.MSG = table.freeze({
	Pick = "🛗 Pick a floor!",
	Near = "🛗 Stand by the lift!",
	NoFloor = "🛗 No such floor!",
	Here = "📍 You're here!",
	Riding = "🛗 Riding!",
})

-- A whole, finite number, or nil.
function Pure.whole(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	if value ~= math.floor(value) then
		return nil
	end
	return value
end

-- The floors a building with `count` walkable floors has: 0 (the ground) to count.
function Pure.floors(count: any): { number }
	local n = math.max(0, math.floor(tonumber(count) or 0))
	local out: { number } = {}
	for floor = 0, n do
		table.insert(out, floor)
	end
	return out
end

function Pure.exists(floor: any, count: any): boolean
	local whole = Pure.whole(floor)
	local n = math.max(0, math.floor(tonumber(count) or 0))
	return whole ~= nil and whole >= 0 and whole <= n
end

-- A ride's length: base seconds x the Express Lift factor (Logic/Rebirth.effects .Lift: 1 = none, 0.4 at 3 ranks).
function Pure.rideSeconds(base: any, factor: any): number
	local b = if type(base) == "number" and base == base and base > 0 and base < 60 then base else 2
	local f = if type(factor) == "number" and factor == factor then math.clamp(factor, Pure.MIN_FACTOR, 1) else 1
	return b * f
end

-- The landing a rider at (x, y, z) stands at: the nearest one within `reach` studs across the ground whose floor is
-- just under them. `landings` = { { Floor, X, Y, Z } } with Y the floor's height. nil when none.
function Pure.nearest(landings: { any }, x: number, y: number, z: number, reach: number): any?
	local best, bestDistance = nil, math.huge
	for _, landing in landings do
		local dx, dz = x - landing.X, z - landing.Z
		local across = math.sqrt(dx * dx + dz * dz)
		local up = y - landing.Y
		if across <= reach and up >= -Pure.BELOW and up <= Pure.ABOVE and across < bestDistance then
			best, bestDistance = landing, across
		end
	end
	return best
end

-- Where the i-th rider is set down, sideways from the landing's centre: 0, +2.8, -2.8, +5.6, ...
function Pure.spread(index: number): number
	if index <= 1 then
		return 0
	end
	local step = math.floor(index / 2)
	return (if index % 2 == 0 then 1 else -1) * step * Pure.SPREAD
end

-- The ride attributes (UI/LiftPanel decodes them with the same rules; Hospital.spec checks they agree).
local function short(n: number): string
	return (string.gsub(string.format("%.3f", n), "%.?0+$", ""))
end

function Pure.encodeRide(from: number, to: number, seconds: number, at: number, plotIndex: number?): string
	local body = table.concat({ tostring(from), tostring(to), short(seconds), short(at) }, ",")
	return if plotIndex then tostring(plotIndex) .. "," .. body else body
end
-- PURE-END

Lift.Pure = Pure

local riding: { [Player]: boolean } = {}
local lastRide: { [Player]: number } = {}
local RIDER_TAG = "LiftRider" -- a patient or porter in the car right now (UI/LiftPanel carries it along)
local RIDE_AT = "LiftRideAt" -- on it: the ride's server time (the Lift's Ride attribute has the same)
local RIDE_SLOT = "LiftRideSlot" -- on it: its place among the riders (Pure.spread), where it steps out

type Waiter = { Thread: thread, Done: boolean }
local waiters: { [Plot]: { Waiter } } = {}
local escortWired: { [ProximityPrompt]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function isPlot(value: any): boolean
	return type(value) == "table" and typeof(value.Model) == "Instance" and value.Model:IsA("Model")
end

local function buildingOf(plot: Plot): Model?
	local building = plot.Model:FindFirstChild("Building")
	return if building and building:IsA("Model") then building else nil
end

local function floorCount(building: Model): number
	local value = building:GetAttribute("Floors")
	return if type(value) == "number" then math.max(0, math.floor(value)) else 0
end

-- The landing marker of that floor (Landing_0 on the ground, Floor_<n>.Landing above).
local function landingPart(plot: Plot, floor: number): BasePart?
	local building = buildingOf(plot)
	if not building or not Pure.exists(floor, floorCount(building)) then
		return nil
	end
	local found: Instance? = nil
	if floor == 0 then
		found = building:FindFirstChild("Landing_0")
	else
		local floorModel = building:FindFirstChild("Floor_" .. floor)
		found = floorModel and floorModel:FindFirstChild("Landing")
	end
	return if found and found:IsA("BasePart") then found else nil
end

function Lift.landing(plot: any, floor: any): CFrame?
	local whole = Pure.whole(floor)
	if not isPlot(plot) or whole == nil then
		return nil
	end
	local landing = landingPart(plot, whole)
	if not landing then
		return nil
	end
	return landing.CFrame * CFrame.new(0, -landing.Size.Y / 2, 0)
end

-- The 🛗 Express Lift factor in someone's save (1 = none).
local function liftFactor(player: Player?): number
	local data = if player then PlayerData.get(player) else nil
	if not data then
		return 1
	end
	local ok, effects = pcall(RebirthLogic.effects, data, Config, PerksData, TreeData)
	return if ok and type(effects) == "table" and type(effects.Lift) == "number" then effects.Lift else 1
end

-- The pivot that sets `model` down at `landing` (the floor point), `offset` studs to the side.
local function setDown(model: Model, landing: CFrame, offset: number): CFrame
	local at = landing * CFrame.new(offset, 0, 0)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if humanoid and root and root:IsA("BasePart") then
		-- A character's pivot is its root: R15 stands HipHeight + half the root above the floor, R6 about 3.
		local lift = if humanoid.HipHeight > 0 then humanoid.HipHeight + root.Size.Y / 2 else 3
		return at * CFrame.new(0, lift, 0)
	end
	return at -- creatures and nurses: their pivot is the ground under them
end

-- Every client slides this building's car; riders' own clients carry their characters along. `at` = the ride's server
-- time (now when nil).
local function announce(plot: Plot, from: number, to: number, seconds: number, riders: { Player }, at: number?)
	local rideAt = at or Workspace:GetServerTimeNow()
	local building = buildingOf(plot)
	local liftModel = building and building:FindFirstChild("Lift")
	if liftModel then
		liftModel:SetAttribute("Ride", Pure.encodeRide(from, to, seconds, rideAt))
		-- Feel/HospitalFX dings others' rides nearby: who rode (0 = a patient alone), then when (it listens to this).
		liftModel:SetAttribute("Rider", if riders[1] then riders[1].UserId else 0)
		liftModel:SetAttribute("RideAt", rideAt)
	end
	for _, rider in riders do
		rider:SetAttribute("LiftRide", Pure.encodeRide(from, to, seconds, rideAt, plot.Index))
	end
end

-- Every landing of a plot's building, as Pure.nearest reads them (Y = the floor under the marker).
local function landingsOf(plot: Plot): { any }
	local building = buildingOf(plot)
	local landings = {}
	if building then
		for floor = 0, floorCount(building) do
			local landing = landingPart(plot, floor)
			if landing then
				local bottom = landing.Position.Y - landing.Size.Y / 2
				table.insert(landings, { Floor = floor, X = landing.Position.X, Y = bottom, Z = landing.Position.Z })
			end
		end
	end
	return landings
end

-- The floor a model stands at (its nearest landing), for the car's start; 0 when it's not by any.
local function floorAt(plot: Plot, position: Vector3): number
	local found = Pure.nearest(landingsOf(plot), position.X, position.Y, position.Z, 12)
	return if found then found.Floor else 0
end

------------------------------------------------------------------------------------------------------------------
-- Riding (RideLift)
------------------------------------------------------------------------------------------------------------------

-- The plot whose landing the rider stands at, and which floor that is.
local function standingAt(root: BasePart): (Plot?, number?)
	local reach = (tonumber(Config.Lift.CarDistance) or 6) + Pure.REACH_SLACK
	local position = root.Position
	local bestPlot, bestFloor, bestDistance = nil, nil, math.huge
	for _, plot in Plots.all() do
		local found = Pure.nearest(landingsOf(plot), position.X, position.Y, position.Z, reach)
		if found then
			local distance = Vector3.new(position.X - found.X, 0, position.Z - found.Z).Magnitude
			if distance < bestDistance then
				bestPlot, bestFloor, bestDistance = plot, found.Floor, distance
			end
		end
	end
	return bestPlot, bestFloor
end

local function arrive(player: Player, plot: Plot, floor: number)
	riding[player] = nil
	if player.Parent ~= Players then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local landing = Lift.landing(plot, floor)
	if character and humanoid and humanoid.Health > 0 and landing then
		character:PivotTo(setDown(character, landing, 0))
	end
end

function Lift.ride(player: Player, floor: any): (boolean, string, any?)
	if not isPlayer(player) then
		return false, Remotes.OOPS
	end
	local target = Pure.whole(floor)
	if target == nil then
		return false, Pure.MSG.Pick
	end
	if riding[player] then
		return false, Pure.MSG.Riding
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")) then
		return false, Pure.MSG.Near
	end
	local plot, from = standingAt(root)
	if not plot or from == nil then
		return false, Pure.MSG.Near
	end
	if not landingPart(plot, target) then
		return false, Pure.MSG.NoFloor
	end
	if target == from then
		return false, Pure.MSG.Here
	end
	local now = os.clock()
	local cooldown = tonumber(Config.Lift.Cooldown) or 1
	local last = lastRide[player]
	if last and now - last < cooldown then
		return false, Remotes.TOO_FAST
	end
	lastRide[player] = now
	riding[player] = true
	local seconds = Pure.rideSeconds(Config.Lift.RideSeconds, liftFactor(player))
	announce(plot, from, target, seconds, { player })
	task.delay(seconds, arrive, player, plot, target)
	return true, "", { Seconds = seconds, From = from, To = target }
end

------------------------------------------------------------------------------------------------------------------
-- Carrying patients and porters
------------------------------------------------------------------------------------------------------------------

function Lift.carry(plot: any, models: any, floor: any): boolean
	local target = Pure.whole(floor)
	if not isPlot(plot) or target == nil or type(models) ~= "table" then
		return false
	end
	if not landingPart(plot, target) then
		return false
	end
	local riders: { Model } = {}
	local players: { Player } = {}
	local creatures: { Model } = {}
	for _, model in models do
		if typeof(model) == "Instance" and model:IsA("Model") and model:IsDescendantOf(Workspace) then
			table.insert(riders, model)
			local player = Players:GetPlayerFromCharacter(model)
			if player then
				table.insert(players, player)
			else
				table.insert(creatures, model)
			end
		end
	end
	if #riders == 0 then
		return false
	end
	local from = floorAt(plot, riders[1]:GetPivot().Position)
	local seconds = Pure.rideSeconds(Config.Lift.RideSeconds, liftFactor(plot.Owner))
	-- The patients and porters riding: every client near the lift steps them into the car and slides them up with it
	-- (UI/LiftPanel), so they never stand outside while the car leaves. Set before the Ride, so it finds them.
	local at = Workspace:GetServerTimeNow()
	for index, model in riders do
		if table.find(creatures, model) then
			model:SetAttribute(RIDE_AT, at)
			model:SetAttribute(RIDE_SLOT, index)
			CollectionService:AddTag(model, RIDER_TAG)
		end
	end
	announce(plot, from, target, seconds, players, at)
	task.wait(seconds)
	local landing = Lift.landing(plot, target) -- re-found: the building may have been rebuilt meanwhile
	for index, model in riders do
		if landing and model:IsDescendantOf(Workspace) then
			model:PivotTo(setDown(model, landing, Pure.spread(index)))
		end
	end
	for _, model in creatures do
		CollectionService:RemoveTag(model, RIDER_TAG)
	end
	return landing ~= nil
end

------------------------------------------------------------------------------------------------------------------
-- Escorts: "Ride with patient" at the ground landing
------------------------------------------------------------------------------------------------------------------

local function escortPrompt(plot: Plot): ProximityPrompt?
	local landing = landingPart(plot, 0)
	local point = landing and landing:FindFirstChild("PromptPoint")
	local prompt = point and point:FindFirstChild("EscortPrompt")
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
end

local function pending(plot: Plot): { Waiter }
	local list = waiters[plot] or {}
	for index = #list, 1, -1 do
		if list[index].Done then
			table.remove(list, index)
		end
	end
	waiters[plot] = if #list > 0 then list else nil
	return list
end

local function syncPrompt(plot: Plot)
	local prompt = escortPrompt(plot)
	if prompt then
		prompt.Enabled = #pending(plot) > 0
	end
end

local function finish(plot: Plot, waiter: Waiter, player: Player?)
	if waiter.Done then
		return
	end
	waiter.Done = true
	syncPrompt(plot)
	if coroutine.status(waiter.Thread) == "suspended" then -- its caller may have been cancelled meanwhile
		task.spawn(waiter.Thread, player)
	end
end

local function wireEscort(plot: Plot, prompt: ProximityPrompt)
	if escortWired[prompt] then
		return
	end
	escortWired[prompt] = true
	prompt.Triggered:Connect(function(player: Player)
		if not Plots.canWork(player, plot) then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local landing = Lift.landing(plot, 0)
		if not (root and root:IsA("BasePart") and landing) then
			return
		end
		local reach = (tonumber(Config.Lift.CarDistance) or 6) + Pure.REACH_SLACK
		local offset = root.Position - landing.Position
		if Vector3.new(offset.X, 0, offset.Z).Magnitude > reach or math.abs(offset.Y) > Pure.ABOVE then
			return
		end
		local list = pending(plot)
		local first = list[1]
		if first then
			finish(plot, first, player)
		end
	end)
end

function Lift.waitEscort(plot: any, seconds: any): Player?
	if not isPlot(plot) then
		return nil
	end
	local limit = if type(seconds) == "number" and seconds == seconds then math.clamp(seconds, 0, Pure.MAX_WAIT) else 0
	local prompt = escortPrompt(plot)
	if not prompt or limit <= 0 then
		return nil
	end
	wireEscort(plot, prompt)
	local waiter: Waiter = { Thread = coroutine.running(), Done = false }
	local list = pending(plot)
	table.insert(list, waiter)
	waiters[plot] = list
	syncPrompt(plot)
	task.delay(limit, function()
		finish(plot, waiter, nil)
	end)
	-- A rebuilt building takes its prompt with it: then nobody can answer, and the wait ends.
	local gone = prompt.Destroying:Once(function()
		task.defer(finish, plot, waiter, nil)
	end)
	local player = coroutine.yield()
	gone:Disconnect()
	return if isPlayer(player) then player else nil
end

function Lift.start()
	Remotes.serve("RideLift", function(player: Player, floor: any)
		return Lift.ride(player, floor)
	end)
	Plots.PlotReleased:Connect(function(_player: Player, plot: Plot)
		for _, waiter in pending(plot) do
			finish(plot, waiter, nil)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		riding[player] = nil
		lastRide[player] = nil
	end)
end

return Lift
