--!strict
-- Nurses you own: equip slots, nurse workers on your plot, the nurse tray and the Nurse Journal (depth-update design
-- §2, build plan §B4/§B8; memory-20261116-012/-013). Server only. OWNER: T3.
--
--   Nurses.start()                              wires EquipNurse; spawns the equipped nurses on PlotAssigned (and
--                                               after an equip, a hire, a level-up or any save change), removes
--                                               them on PlotReleased (before Plots clears the plot)
--   Nurses.slots(p): number                     = Levels.slots(p) (slots = hospital level)
--   Nurses.equip(p, nurseId, on): (ok, message) Logic/Nurse.equip, saved in Data.Equipped; NurseNews Equipped
--   Nurses.grant(p, nurseId, price): (ok, message)
--                                               NurseBelt's hire: charge `price` and add one copy in ONE
--                                               PlayerData.update (Logic/Nurse.hire, NurseIndex "Hired"; a FIRST copy
--                                               also goes on duty when a slot is free, so it walks to your clinic),
--                                               then any journal set due (cash + decor + JournalSets, same update);
--                                               then the NurseNews (Hired, Equipped), Celebrate (NewNurse on a first
--                                               copy, JournalSet) remotes, the reward decor goes out on show
--                                               (Book.placeReward) and the Hired signal fires
--   Nurses.markSeen(nurseId, players?)          a nurse rode by: each listed player (every player when nil) without
--                                               a journal entry for it gets "Seen" and a NurseNews (Seen). NurseBelt
--                                               passes the players close enough to see the rider
--   Nurses.trayItems(plot): { ItemId }          the plot's nurse tray (Makers fill it; attribute NurseTray)
--   Nurses.takeFromTray(plot, itemId): boolean  removes one (Treatment/Patients, for a player's treat or a Healer's)
--   Nurses.cheer(plot): Types.Cheer             the best equipped Cheerer's multipliers ({ 1, 1 } when none); also
--                                               kept on the plot's CheerPatience and CheerTip attributes
--   Nurses.healed(plot, nurseId, items)         Treatment tells the Healer it delivered (it plays a happy spin)
--   Nurses.Heal                                 signal (plot, nurseId): a Healer is ready (the tray holds something
--                                               the front patient needs). Treatment delivers it (rated OK, no tip, no
--                                               combo) and calls healed(); no delivery: the Healer tries again soon
--   Nurses.Hired                                signal (p, nurseId, level)
--   Nurses.Pure                                 the pure helpers below (a scratch Lune harness tests them)
--
-- The workers (plot.Model.Nurses.Nurse_<NurseId>, from NurseBuilder; tag CreatureMotion; attributes NurseId, Role,
-- Rarity, Level, Task, Station). They hop by the creature-motion contract (NurseBuilder.hop): the server sets the hop
-- attributes and writes Root.CFrame once per landing, never every frame. One thread per nurse.
--   Maker    makes what the line still needs (QueueNeeds, front first), minus what's already in the tray, being made
--            by another Maker or carried by the owner, and only what this plot's stations make: it hops to that
--            station, works for its Every seconds (Logic/Nurse.stats), and puts the item in the tray. A full tray
--            swaps out the oldest item nobody in line needs; a tray full of needed items waits.
--   Healer   stands behind the Counter; at most every Every seconds, when the tray holds an item the front patient
--            still needs (FrontNeeds), fires Heal.
--   Cheerer  stands beside the line and cheers (a spin hop) while patients wait; its multipliers (the best one on
--            duty, they don't stack) go on the plot's CheerPatience and CheerTip.
-- The tray shows as a small 🧺 billboard on the Counter (NurseTrayGui) while it holds something.
-- Nurses work only while the owner is in the server (their plot is released when they leave): no offline income.
-- Never requires Treatment or Patients (they require this): it reads the plot's FrontNeeds and QueueNeeds.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)
local BeltLogic = require(Shared.Logic.Belt)
local NurseLogic = require(Shared.Logic.Nurse)
local RecipeLogic = require(Shared.Logic.Recipe)
local DecorData = require(Shared.Data.Decor)
local ItemsData = require(Shared.Data.Items)
local NursesData = require(Shared.Data.Nurses)
local Rarities = require(Shared.Data.Rarities)
local Book = require(script.Parent.Book)
local CreatureBuilder = require(script.Parent.CreatureBuilder)
local Levels = require(script.Parent.Levels)
local NurseBuilder = require(script.Parent.NurseBuilder)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)

type Plot = Types.Plot

local Nurses = {}

Nurses.Heal = Signal.new()
Nurses.Hired = Signal.new()

------------------------------------------------------------------------------------------------------------------
-- Tuning (feel only; the rules' numbers are in Config.Nurses)
------------------------------------------------------------------------------------------------------------------

local MOTION_TAG = "CreatureMotion"
local FOLDER_NAME = "Nurses"
local TRAY_ATTRIBUTE = "NurseTray"
local TRAY_GUI = "NurseTrayGui"
local HOP_LENGTH = 3
local HOP_SECONDS = 0.32
local HOP_HEIGHT = 0.8
local SPOT_SPACING = 2.6 -- studs between nurses of the same role standing side by side
local LOOK_SECONDS = 0.5 -- an idle nurse looks for work this often
local HEAL_WAIT = 2 -- seconds a Healer waits for the delivery before it tries again
local RETRY_SECONDS = 2
local MAX_CASH = 1e15 -- as Economy: far below 2^53
local NEAR_STUDS = 16 -- the tray billboard stops growing on screen closer than this

local rng = Random.new()

------------------------------------------------------------------------------------------------------------------
-- Pure helpers (no Roblox services, no upvalues: a scratch Lune harness loads this block on its own)
------------------------------------------------------------------------------------------------------------------

-- PURE-BEGIN
local Pure = {}

-- `list` without one copy of each item in `take` (a multiset difference), order kept.
function Pure.without(list: { string }, take: { string }): { string }
	local counts: { [string]: number } = {}
	for _, item in take do
		counts[item] = (counts[item] or 0) + 1
	end
	local out: { string } = {}
	for _, item in list do
		local left = counts[item]
		if left and left > 0 then
			counts[item] = left - 1
		else
			table.insert(out, item)
		end
	end
	return out
end

-- The index of the oldest tray item the line doesn't need (copies beyond what the line needs count), or nil.
function Pure.spare(tray: { string }, needs: { string }): number?
	local counts: { [string]: number } = {}
	for _, item in needs do
		counts[item] = (counts[item] or 0) + 1
	end
	for index, item in tray do
		local left = counts[item]
		if left and left > 0 then
			counts[item] = left - 1
		else
			return index
		end
	end
	return nil
end

-- One more item in the tray: added while there's room; a full tray swaps out the oldest item nobody needs. A tray full
-- of needed items refuses. Returns (a new tray, added).
function Pure.trayAdd(tray: { string }, item: string, max: number, needs: { string }): ({ string }, boolean)
	local out = table.clone(tray)
	if #out < max then
		table.insert(out, item)
		return out, true
	end
	local index = Pure.spare(out, needs)
	if index then
		table.remove(out, index)
		table.insert(out, item)
		return out, true
	end
	return out, false
end

-- One `item` out of the tray (the oldest copy). Returns (a new tray, taken).
function Pure.trayTake(tray: { string }, item: string): ({ string }, boolean)
	local out = table.clone(tray)
	local index = table.find(out, item)
	if not index then
		return out, false
	end
	table.remove(out, index)
	return out, true
end

-- What a Maker makes next: the first item the line needs (front first) that `have` doesn't already cover (the tray,
-- what other Makers are making, what the owner carries) and that `canMake` has. nil when nothing is missing, or when
-- the tray is full of items the line needs.
function Pure.pickMake(
	needs: { string },
	have: { string },
	canMake: { [string]: boolean },
	tray: { string },
	max: number
): string?
	if #tray >= max and Pure.spare(tray, needs) == nil then
		return nil
	end
	for _, item in Pure.without(needs, have) do
		if canMake[item] then
			return item
		end
	end
	return nil
end

-- A Healer can help: the tray holds something the front patient still needs.
function Pure.canHeal(frontNeeds: { string }, tray: { string }): boolean
	for _, item in frontNeeds do
		if table.find(tray, item) then
			return true
		end
	end
	return false
end

-- The nurses on duty: Equipped in order, strings, unique, known (isKnown), at most `slots` of them.
function Pure.onDuty(equipped: any, isKnown: (string) -> boolean, slots: number): { string }
	local out: { string } = {}
	if type(equipped) ~= "table" then
		return out
	end
	for _, nurseId in equipped do
		if #out >= slots then
			break
		end
		if type(nurseId) == "string" and not table.find(out, nurseId) and isKnown(nurseId) then
			table.insert(out, nurseId)
		end
	end
	return out
end

-- A nurse's level from its save entry (1..max; junk -> 1).
function Pure.level(entry: any, max: number): number
	local level = if type(entry) == "table" then entry.Level else nil
	if type(level) ~= "number" or level ~= level then
		return 1
	end
	return math.clamp(math.floor(level), 1, max)
end

-- 12345 -> "12,345"
function Pure.cash(n: number): string
	local text = tostring(math.floor(math.abs(n)))
	local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (if n < 0 then "-" else "") .. out
end
-- PURE-END

Nurses.Pure = Pure

------------------------------------------------------------------------------------------------------------------
-- Types and state
------------------------------------------------------------------------------------------------------------------

type Worker = {
	NurseId: string,
	Role: string,
	Rarity: string,
	Level: number,
	Every: number,
	Model: Model,
	Pivot: CFrame, -- where it rests between hops (Root.CFrame)
	Index: number, -- its place among the nurses of its role on this plot (where it stands)
	Alive: boolean,
	Thread: thread?,
	Making: string?, -- a Maker's item in progress (other Makers don't make it too)
	Healed: boolean, -- a Healer's delivery landed (Nurses.healed)
}

type Work = {
	Plot: Plot,
	Owner: Player,
	Folder: Folder,
	Ray: RaycastParams,
	Workers: { [string]: Worker },
	Cheer: Types.Cheer,
}

local works: { [Plot]: Work } = {}
local trayLabels: { [Plot]: TextLabel } = {}
local failures: { [string]: number } = {}

local function report(label: string, err: any)
	local count = (failures[label] or 0) + 1
	failures[label] = count
	if count <= 3 then
		warn("[Nurses] " .. label .. " failed: " .. tostring(err))
	end
end

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

-- rawget: Data maps answer `.Order` through their metatable, so a plain index would accept the id "Order".
local function nurseOf(nurseId: any): any
	if type(nurseId) ~= "string" then
		return nil
	end
	local nurse = rawget(NursesData :: any, nurseId)
	return if type(nurse) == "table" then nurse else nil
end

local function knownNurse(nurseId: string): boolean
	return nurseOf(nurseId) ~= nil
end

local function knownDecor(decorId: any): boolean
	return type(decorId) == "string" and type(rawget(DecorData :: any, decorId)) == "table"
end

local function itemIcon(itemId: string): string
	local item = rawget(ItemsData :: any, itemId)
	return if type(item) == "table" then item.Icon else "❔"
end

local function maxLevel(): number
	return math.max(1, math.floor(Config.Nurses.MaxLevel))
end

-- The plot a caller means: the Plots table, or (leniently) its Model.
local function plotOf(value: any): Plot?
	if type(value) == "table" and typeof(value.Model) == "Instance" then
		return value
	end
	if typeof(value) == "Instance" then
		return Plots.fromInstance(value)
	end
	return nil
end

local function attributeList(model: Model, name: string): { string }
	return RecipeLogic.split(model:GetAttribute(name))
end

local function setAttribute(instance: Instance, name: string, value: any)
	if instance:GetAttribute(name) ~= value then
		instance:SetAttribute(name, value)
	end
end

local function fire(remote: RemoteEvent, player: Player, payload: any)
	if player.Parent == Players then
		remote:FireClient(player, payload)
	end
end

------------------------------------------------------------------------------------------------------------------
-- The nurse tray (the plot's NurseTray attribute is the only copy)
------------------------------------------------------------------------------------------------------------------

local function trayGui(plot: Plot): TextLabel?
	local existing = trayLabels[plot]
	if existing and existing.Parent then
		return existing
	end
	local counter = plot.Counter
	if not counter or not counter.Parent then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = TRAY_GUI
	gui.Size = UDim2.fromScale(5, 1.5) -- studs
	gui.StudsOffsetWorldSpace =
		counter.CFrame:VectorToWorldSpace(Vector3.new(counter.Size.X / 2 - 2.4, counter.Size.Y / 2 + 1.5, 0))
	gui.DistanceLowerLimit = NEAR_STUDS
	gui.MaxDistance = 110
	gui.LightInfluence = 0
	gui.Enabled = false
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.Size = UDim2.fromScale(1, 1)
	pill.BackgroundColor3 = Palette.White
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = pill
	Palette.outlineShape(pill, 2)
	local label = Instance.new("TextLabel")
	label.Name = "Items"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.9, 0.8)
	label.Position = UDim2.fromScale(0.05, 0.1)
	label.TextScaled = true
	label.Font = Palette.BodyFont
	label.TextColor3 = Palette.Ink
	label.Text = ""
	label.Parent = pill
	pill.Parent = gui
	gui.Parent = counter
	trayLabels[plot] = label
	return label
end

local function showTray(plot: Plot)
	local items = attributeList(plot.Model, TRAY_ATTRIBUTE)
	local label = trayGui(plot)
	if not label then
		return
	end
	local icons: { string } = {}
	for _, itemId in items do
		table.insert(icons, itemIcon(itemId))
	end
	label.Text = "🧺 " .. table.concat(icons, "")
	local gui = label:FindFirstAncestorWhichIsA("BillboardGui")
	if gui then
		gui.Enabled = #items > 0
	end
end

local function writeTray(plot: Plot, items: { string })
	local cut = table.move(items, 1, math.min(#items, Config.Nurses.TrayMax), 1, {})
	setAttribute(plot.Model, TRAY_ATTRIBUTE, RecipeLogic.join(cut))
end

function Nurses.trayItems(plotArg: Plot): { string }
	local plot = plotOf(plotArg)
	if not plot then
		return {}
	end
	return attributeList(plot.Model, TRAY_ATTRIBUTE)
end

function Nurses.takeFromTray(plotArg: Plot, itemId: string): boolean
	local plot = plotOf(plotArg)
	if not plot or type(itemId) ~= "string" then
		return false
	end
	local tray, taken = Pure.trayTake(attributeList(plot.Model, TRAY_ATTRIBUTE), itemId)
	if taken then
		writeTray(plot, tray)
	end
	return taken
end

------------------------------------------------------------------------------------------------------------------
-- Where nurses stand
------------------------------------------------------------------------------------------------------------------

local function flat(direction: Vector3): Vector3
	local d = Vector3.new(direction.X, 0, direction.Z)
	return if d.Magnitude > 1e-3 then d.Unit else Vector3.zAxis
end

-- The floor (plot Ground or a room floor) under a point.
local function groundAt(work: Work, position: Vector3): Vector3
	local baseY = work.Plot.Model:GetPivot().Y
	local hit = Workspace:Raycast(Vector3.new(position.X, baseY + 3, position.Z), Vector3.new(0, -8, 0), work.Ray)
	return Vector3.new(position.X, if hit then hit.Position.Y else baseY, position.Z)
end

-- A spot by the Counter, in counter-local x/z (the Counter's -Z side is the line's side), facing `face`.
local function byCounter(work: Work, x: number, z: number, face: Vector3): CFrame
	local counter = work.Plot.Counter
	local point = (counter.CFrame * CFrame.new(x, -counter.Size.Y / 2, z)).Position
	local ground = groundAt(work, point)
	return CFrame.lookAt(ground, ground + flat(face))
end

-- Healers stand behind the Counter on the right, looking at the line; idle Makers on the left.
local function healerSpot(work: Work, index: number): CFrame
	local counter = work.Plot.Counter
	local x = counter.Size.X / 2 - 1.6 - (index - 1) * SPOT_SPACING
	return byCounter(work, x, counter.Size.Z / 2 + 1.9, counter.CFrame.LookVector)
end

local function makerHome(work: Work, index: number): CFrame
	local counter = work.Plot.Counter
	local x = -(counter.Size.X / 2 - 1.6) + (index - 1) * SPOT_SPACING
	return byCounter(work, x, counter.Size.Z / 2 + 1.9, counter.CFrame.LookVector)
end

-- Cheerers stand beside the front of the line (the Counter's left), facing it.
local function cheerSpot(work: Work, index: number): CFrame
	local counter = work.Plot.Counter
	local x = -(counter.Size.X / 2 + 2) - (index - 1) * SPOT_SPACING
	return byCounter(work, x, -(counter.Size.Z / 2 + 1.5), counter.CFrame.RightVector)
end

-- In front of a station, a little to one side (the player making stands in the middle), facing it.
local function stationSpot(work: Work, station: BasePart, index: number): CFrame
	local side = if index % 2 == 1 then 1 else -1
	local cf = station.CFrame
	local point = (cf * CFrame.new(side * 1.3, -station.Size.Y / 2, -(station.Size.Z / 2 + 1.5))).Position
	local ground = groundAt(work, point)
	return CFrame.lookAt(ground, ground - flat(cf.LookVector))
end

-- Station_<id> is a Part by contract; a kit room may use a Model (its main part).
local function stationPart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

-- Every item this plot's stations make, with the station part and id.
local function stationsOf(plot: Plot): { [string]: { Part: BasePart, Station: string } }
	local found: { [string]: { Part: BasePart, Station: string } } = {}
	local rooms = plot.Model:FindFirstChild("Rooms")
	if not rooms then
		return found
	end
	for _, descendant in rooms:GetDescendants() do
		local stationId = string.match(descendant.Name, "^Station_(%w+)$")
		if stationId then
			local part = stationPart(descendant)
			for _, itemId in ItemsData.Order do
				local item = rawget(ItemsData :: any, itemId)
				if part and item and item.Station == stationId and not found[itemId] then
					found[itemId] = { Part = part, Station = stationId }
				end
			end
		end
	end
	return found
end

------------------------------------------------------------------------------------------------------------------
-- Moving (the creature-motion contract via NurseBuilder.hop)
------------------------------------------------------------------------------------------------------------------

local function hopTo(w: Worker, to: CFrame, height: number, seconds: number, spin: number?): boolean
	if not w.Alive then
		return false
	end
	local ok = NurseBuilder.hop(w.Model, w.Pivot, to, height, seconds, spin)
	if ok then
		w.Pivot = to
	end
	return ok and w.Alive
end

local function far(a: CFrame, b: CFrame): boolean
	local delta = Vector3.new(a.X - b.X, 0, a.Z - b.Z)
	return delta.Magnitude > 0.4 or a.LookVector:Dot(b.LookVector) < 0.95
end

-- Hops to `target` a few studs at a time, facing where it goes, and lands facing the target's way.
local function walkTo(work: Work, w: Worker, target: CFrame): boolean
	for _ = 1, 60 do
		if not w.Alive then
			return false
		end
		local from = w.Pivot.Position
		local delta = Vector3.new(target.X - from.X, 0, target.Z - from.Z)
		local distance = delta.Magnitude
		if distance <= HOP_LENGTH then
			if not far(w.Pivot, target) then
				return true
			end
			local seconds = HOP_SECONDS * math.sqrt(math.max(distance, 0.6) / HOP_LENGTH)
			return hopTo(w, target, if distance < 0.4 then 0.3 else HOP_HEIGHT, seconds)
		end
		local direction = delta / distance
		local landing = groundAt(work, from + direction * HOP_LENGTH)
		if not hopTo(w, CFrame.lookAt(landing, landing + direction), HOP_HEIGHT, HOP_SECONDS) then
			return false
		end
	end
	return w.Alive
end

local function goTo(work: Work, w: Worker, target: CFrame): boolean
	if not far(w.Pivot, target) then
		return w.Alive
	end
	NurseBuilder.setTask(w.Model, "Walking")
	return walkTo(work, w, target)
end

local function sleep(w: Worker, seconds: number): boolean
	local untilAt = os.clock() + seconds
	while w.Alive do
		local left = untilAt - os.clock()
		if left <= 0 then
			break
		end
		task.wait(math.min(left, LOOK_SECONDS))
	end
	return w.Alive
end

local function idleHop(w: Worker): boolean
	return hopTo(w, w.Pivot, 0.45, 0.3)
end

local function spinHop(w: Worker, height: number): boolean
	return hopTo(w, w.Pivot, height, 0.5, math.pi * 2)
end

------------------------------------------------------------------------------------------------------------------
-- The three jobs
------------------------------------------------------------------------------------------------------------------

local function deposit(work: Work, item: string)
	local plot = work.Plot
	local tray, added = Pure.trayAdd(
		attributeList(plot.Model, TRAY_ATTRIBUTE),
		item,
		Config.Nurses.TrayMax,
		attributeList(plot.Model, "QueueNeeds")
	)
	if added then
		writeTray(plot, tray)
	end
end

local function nextItem(work: Work, w: Worker): (string?, { [string]: { Part: BasePart, Station: string } })
	local plot = work.Plot
	local tray = attributeList(plot.Model, TRAY_ATTRIBUTE)
	local have = table.clone(tray)
	for _, other in work.Workers do
		if other ~= w and other.Making then
			table.insert(have, other.Making)
		end
	end
	for _, carried in RecipeLogic.split(work.Owner:GetAttribute("Carry")) do
		table.insert(have, carried)
	end
	local stations = stationsOf(plot)
	local canMake: { [string]: boolean } = {}
	for itemId in stations do
		canMake[itemId] = true
	end
	local needs = attributeList(plot.Model, "QueueNeeds")
	return Pure.pickMake(needs, have, canMake, tray, Config.Nurses.TrayMax), stations
end

local function makerLoop(work: Work, w: Worker)
	local nextIdle = os.clock() + rng:NextNumber(3, 6)
	if not goTo(work, w, makerHome(work, w.Index)) then
		return
	end
	NurseBuilder.setTask(w.Model, "Idle")
	while w.Alive do
		local item, stations = nextItem(work, w)
		local where = if item then stations[item] else nil
		if item and where then
			w.Making = item
			setAttribute(w.Model, "Station", where.Station)
			if not goTo(work, w, stationSpot(work, where.Part, w.Index)) then
				return
			end
			NurseBuilder.setTask(w.Model, "Making", itemIcon(item))
			if not sleep(w, w.Every) then
				return
			end
			deposit(work, item)
			w.Making = nil
			setAttribute(w.Model, "Station", "")
			NurseBuilder.setTask(w.Model, "Idle")
			if not hopTo(w, w.Pivot, 0.7, 0.35) then -- a proud little bounce
				return
			end
			nextIdle = os.clock() + rng:NextNumber(4, 7)
		elseif os.clock() >= nextIdle then
			nextIdle = os.clock() + rng:NextNumber(4, 7)
			if not idleHop(w) then
				return
			end
		else
			task.wait(LOOK_SECONDS)
		end
	end
end

local function healerLoop(work: Work, w: Worker)
	local nextAt = os.clock() + w.Every * rng:NextNumber(0.25, 0.6) -- staggered, so two Healers don't race
	local nextIdle = os.clock() + rng:NextNumber(3, 6)
	while w.Alive do
		if not goTo(work, w, healerSpot(work, w.Index)) then
			return
		end
		local now = os.clock()
		local front = attributeList(work.Plot.Model, "FrontNeeds")
		if now >= nextAt and Pure.canHeal(front, attributeList(work.Plot.Model, TRAY_ATTRIBUTE)) then
			NurseBuilder.setTask(w.Model, "Healing")
			w.Healed = false
			Nurses.Heal:Fire(work.Plot, w.NurseId)
			local waitUntil = os.clock() + HEAL_WAIT
			while w.Alive and not w.Healed and os.clock() < waitUntil do
				task.wait(0.1)
			end
			if not w.Alive then
				return
			end
			if w.Healed then
				w.Healed = false
				nextAt = os.clock() + w.Every
				if not spinHop(w, 1.1) then -- a happy spin
					return
				end
			else
				nextAt = os.clock() + RETRY_SECONDS
			end
			NurseBuilder.setTask(w.Model, "Idle")
		elseif now >= nextIdle then
			nextIdle = now + rng:NextNumber(4, 7)
			if not idleHop(w) then
				return
			end
		else
			task.wait(LOOK_SECONDS)
		end
	end
end

local function cheererLoop(work: Work, w: Worker)
	local nextCheer = os.clock() + rng:NextNumber(1, 3)
	while w.Alive do
		if not goTo(work, w, cheerSpot(work, w.Index)) then
			return
		end
		local model = work.Plot.Model
		local busy = (model:GetAttribute("QueueNeeds") or "") ~= "" or (model:GetAttribute("FrontNeeds") or "") ~= ""
		NurseBuilder.setTask(w.Model, if busy then "Cheering" else "Idle")
		if os.clock() >= nextCheer then
			nextCheer = os.clock() + (if busy then rng:NextNumber(2.5, 4) else rng:NextNumber(5, 8))
			local ok = if busy then spinHop(w, 1) else idleHop(w)
			if not ok then
				return
			end
		else
			task.wait(LOOK_SECONDS)
		end
	end
end

local LOOPS: { [string]: (Work, Worker) -> () } = {
	Maker = makerLoop,
	Healer = healerLoop,
	Cheerer = cheererLoop,
}

------------------------------------------------------------------------------------------------------------------
-- Workers on a plot
------------------------------------------------------------------------------------------------------------------

local function refreshCheer(work: Work)
	local list = {}
	for _, w in work.Workers do
		if w.Role == "Cheerer" then
			table.insert(list, NurseLogic.stats("Cheerer", w.Rarity, w.Level, Config))
		end
	end
	local best = NurseLogic.bestCheer(list)
	work.Cheer = { Patience = best.Patience, Tip = best.Tip }
	setAttribute(work.Plot.Model, "CheerPatience", best.Patience)
	setAttribute(work.Plot.Model, "CheerTip", best.Tip)
end

local function everyFor(role: string, rarity: string, level: number): number
	local stats = NurseLogic.stats(role, rarity, level, Config)
	return stats.Every or 10
end

local function removeWorker(work: Work, w: Worker, puff: boolean)
	w.Alive = false
	work.Workers[w.NurseId] = nil
	local thread = w.Thread
	w.Thread = nil
	if thread and thread ~= coroutine.running() and coroutine.status(thread) ~= "dead" then
		pcall(task.cancel, thread)
	end
	if puff and w.Model.Parent then
		pcall(CreatureBuilder.effectAt, w.Pivot.Position + Vector3.new(0, 1.5, 0), "Pop")
	end
	w.Model:Destroy()
end

local function addWorker(work: Work, nurseId: string, level: number, index: number)
	local nurse = nurseOf(nurseId)
	if not nurse then
		return
	end
	local role: string = nurse.Role
	local loop = LOOPS[role]
	local ok, model = pcall(NurseBuilder.build, nurseId)
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		report("NurseBuilder.build " .. nurseId, model)
		return
	end
	local start = if role == "Healer"
		then healerSpot(work, index)
		elseif role == "Cheerer" then cheerSpot(work, index)
		else makerHome(work, index)
	model:PivotTo(start)
	model:SetAttribute("Level", level)
	model:SetAttribute("Station", "")
	CollectionService:AddTag(model, MOTION_TAG)
	model.Parent = work.Folder
	NurseBuilder.popIn(model)

	local w: Worker = {
		NurseId = nurseId,
		Role = role,
		Rarity = nurse.Rarity,
		Level = level,
		Every = everyFor(role, nurse.Rarity, level),
		Model = model,
		Pivot = start,
		Index = index,
		Alive = true,
		Thread = nil,
		Making = nil,
		Healed = false,
	}
	work.Workers[nurseId] = w
	if loop then
		w.Thread = task.spawn(function()
			local fine, err = pcall(loop, work, w)
			if not fine and w.Alive then
				report("a " .. role .. "'s work", err)
			end
		end)
	end
end

-- Makes the plot's nurses match the owner's save: the first `slots` known nurses of Data.Equipped, at their levels.
-- Idempotent and cheap (it diffs), so it runs after every save change.
local function sync(owner: Player)
	local plot = Plots.getPlot(owner)
	local work = if plot then works[plot] else nil
	local data = PlayerData.get(owner)
	if not work or work.Owner ~= owner or not data then
		return
	end
	local wanted = Pure.onDuty(data.Equipped, knownNurse, Levels.slots(owner))
	local keep: { [string]: boolean } = {}
	for _, nurseId in wanted do
		keep[nurseId] = true
	end
	for nurseId, w in table.clone(work.Workers) do
		if not keep[nurseId] then
			removeWorker(work, w, true)
		end
	end
	local perRole: { [string]: number } = {}
	for _, nurseId in wanted do
		local nurse = nurseOf(nurseId)
		local role = if nurse then nurse.Role else "Maker"
		local index = (perRole[role] or 0) + 1
		perRole[role] = index
		local level = Pure.level(data.Nurses[nurseId], maxLevel())
		local w = work.Workers[nurseId]
		if w then
			w.Index = index
			if w.Level ~= level then
				w.Level = level
				w.Every = everyFor(w.Role, w.Rarity, level)
				w.Model:SetAttribute("Level", level)
			end
		else
			addWorker(work, nurseId, level, index)
		end
	end
	refreshCheer(work)
end

local function ensureFolder(plot: Plot): Folder
	local existing = plot.Model:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = plot.Model
	return folder
end

local function resetPlot(plot: Plot)
	setAttribute(plot.Model, TRAY_ATTRIBUTE, "")
	setAttribute(plot.Model, "CheerPatience", 1)
	setAttribute(plot.Model, "CheerTip", 1)
end

-- Never yields: it runs inside Plots.PlotReleased, before Plots clears the plot.
local function deactivate(plot: Plot)
	local work = works[plot]
	works[plot] = nil
	if work then
		for _, w in table.clone(work.Workers) do
			removeWorker(work, w, false)
		end
	end
	local folder = plot.Model:FindFirstChild(FOLDER_NAME)
	if folder then
		folder:ClearAllChildren()
	end
	resetPlot(plot)
end

local function activate(owner: Player, plot: Plot)
	local current = works[plot]
	if current and current.Owner ~= owner then
		deactivate(plot)
		current = nil
	end
	if not current then
		local ray = RaycastParams.new()
		ray.FilterType = Enum.RaycastFilterType.Include
		local include: { Instance } = {}
		for _, name in { "Ground", "Rooms" } do
			local found = plot.Model:FindFirstChild(name)
			if found then
				table.insert(include, found)
			end
		end
		ray.FilterDescendantsInstances = include
		resetPlot(plot)
		works[plot] = {
			Plot = plot,
			Owner = owner,
			Folder = ensureFolder(plot),
			Ray = ray,
			Workers = {},
			Cheer = { Patience = 1, Tip = 1 },
		}
	end
	sync(owner)
end

------------------------------------------------------------------------------------------------------------------
-- The Journal
------------------------------------------------------------------------------------------------------------------

-- Grants every complete journal group's reward not yet given into `data` (mutates it): cash, the decor and
-- JournalSets. Returns the rarities granted. Call it inside PlayerData.update.
local function grantSets(data: Types.Data): { string }
	local granted: { string } = {}
	for _, rarity in NurseLogic.setsDue(data.NurseIndex, NursesData, Rarities, data.JournalSets) do
		local info = rawget(Rarities :: any, rarity)
		if type(info) == "table" and data.JournalSets[rarity] ~= true then
			data.JournalSets[rarity] = true
			local cash = info.Journal.Cash
			if type(cash) == "number" and cash == cash and cash > 0 then
				data.Cash = math.min(MAX_CASH, data.Cash + math.floor(cash))
			end
			if knownDecor(info.Journal.Decor) then
				data.Decor.Owned[info.Journal.Decor] = true
			end
			table.insert(granted, rarity)
		end
	end
	return granted
end

local function celebrateSet(player: Player, rarity: string)
	local info = rawget(Rarities :: any, rarity)
	if type(info) ~= "table" then
		return
	end
	fire(Remotes.Celebrate, player, {
		Kind = "JournalSet",
		Title = info.Name .. " set done!",
		Icon = info.Icon,
		Rarity = rarity,
		Cash = info.Journal.Cash,
		Decor = info.Journal.Decor,
	})
	if knownDecor(info.Journal.Decor) then
		local ok, err = pcall(Book.placeReward, player, info.Journal.Decor)
		if not ok then
			report("Book.placeReward", err)
		end
	end
end

function Nurses.markSeen(nurseId: string, players: { Player }?)
	if not knownNurse(nurseId) then
		return
	end
	local list = if type(players) == "table" then players else Players:GetPlayers()
	for _, player in list do
		if isPlayer(player) and player.Parent == Players then
			local data = PlayerData.get(player)
			if data and data.NurseIndex[nurseId] == nil then
				local changed = false
				local saved = PlayerData.update(player, function(d)
					changed = NurseLogic.mark(d.NurseIndex, nurseId, "Seen")
				end)
				if saved and changed then
					fire(Remotes.NurseNews, player, { Kind = "Seen", NurseId = nurseId })
				end
			end
		end
	end
end

------------------------------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------------------------------

function Nurses.slots(player: Player): number
	return Levels.slots(player)
end

function Nurses.equip(player: Player, nurseId: string, on: boolean): (boolean, string)
	if not isPlayer(player) or not knownNurse(nurseId) or type(on) ~= "boolean" then
		return false, Remotes.OOPS
	end
	local data = PlayerData.get(player)
	if not data then
		return false, Remotes.OOPS
	end
	local ok, message, list = NurseLogic.equip(data.Equipped, data.Nurses, nurseId, on, Nurses.slots(player))
	if not ok then
		return false, message
	end
	local changed = #list ~= #data.Equipped
	if changed then
		local saved = PlayerData.update(player, function(d)
			d.Equipped = list
		end)
		if not saved then
			return false, Remotes.OOPS
		end
		fire(Remotes.NurseNews, player, { Kind = "Equipped", NurseId = nurseId, On = on })
		sync(player)
	end
	return true, if on then "✅ On duty!" else "💤 Off duty"
end

function Nurses.grant(player: Player, nurseId: string, price: number): (boolean, string)
	if
		not isPlayer(player)
		or not knownNurse(nurseId)
		or type(price) ~= "number"
		or price ~= price
		or price < 0
		or price == math.huge
	then
		return false, Remotes.OOPS
	end
	local cost = math.floor(price + 0.5)
	local data = PlayerData.get(player)
	if not data then
		return false, Remotes.OOPS
	end
	local canHire, why = BeltLogic.canHire(data.Nurses[nurseId], Config)
	if not canHire then
		return false, why
	end
	if data.Cash < cost then
		return false, "Need 💰" .. Pure.cash(cost)
	end

	local slots = Nurses.slots(player)
	local level, isNew, equipped = 1, false, false
	local sets: { string } = {}
	-- Charge, the copy, the journal mark, a first copy on duty and any set reward: ONE update, no yield inside.
	local saved = PlayerData.update(player, function(d)
		d.Cash -= cost
		local entry, new = NurseLogic.hire(d.Nurses[nurseId], Config)
		d.Nurses[nurseId] = entry
		level, isNew = entry.Level, new
		NurseLogic.mark(d.NurseIndex, nurseId, "Hired")
		if new then
			local fits, _, list = NurseLogic.equip(d.Equipped, d.Nurses, nurseId, true, slots)
			if fits and #list > #d.Equipped then
				d.Equipped = list
				equipped = true
			end
		end
		sets = grantSets(d)
	end)
	if not saved then
		return false, Remotes.OOPS -- the save is closing (they're leaving): nothing changed
	end

	local nurse = nurseOf(nurseId)
	fire(Remotes.NurseNews, player, { Kind = "Hired", NurseId = nurseId, Level = level, New = isNew })
	if equipped then
		fire(Remotes.NurseNews, player, { Kind = "Equipped", NurseId = nurseId, On = true })
	end
	if isNew then
		fire(Remotes.Celebrate, player, {
			Kind = "NewNurse",
			Title = nurse.Name,
			Icon = nurse.Icon,
			Rarity = nurse.Rarity,
			NurseId = nurseId,
			Level = level,
		})
	end
	for _, rarity in sets do
		celebrateSet(player, rarity)
	end
	Nurses.Hired:Fire(player, nurseId, level)
	sync(player)
	if isNew then
		return true, "🎉 Hired " .. nurse.Name .. "!"
	end
	return true, "⬆️ " .. nurse.Name .. " Lv " .. level .. "!"
end

function Nurses.cheer(plotArg: Plot): Types.Cheer
	local plot = plotOf(plotArg)
	local work = if plot then works[plot] else nil
	if not work then
		return { Patience = 1, Tip = 1 }
	end
	return { Patience = work.Cheer.Patience, Tip = work.Cheer.Tip }
end

function Nurses.healed(plotArg: Plot, nurseId: string, _items: { string })
	local plot = plotOf(plotArg)
	local work = if plot then works[plot] else nil
	local w = if work and type(nurseId) == "string" then work.Workers[nurseId] else nil
	if w and w.Role == "Healer" then
		w.Healed = true -- its loop plays the happy spin (one mover per nurse)
	end
end

function Nurses.start()
	Remotes.serve("EquipNurse", function(player: Player, nurseId: any, on: any)
		if type(nurseId) ~= "string" or #nurseId > 40 or type(on) ~= "boolean" then
			return false, Remotes.OOPS
		end
		return Nurses.equip(player, nurseId, on)
	end)

	for _, plot in Plots.all() do
		ensureFolder(plot)
		resetPlot(plot)
		plot.Model:GetAttributeChangedSignal(TRAY_ATTRIBUTE):Connect(function()
			showTray(plot)
		end)
	end

	Plots.PlotAssigned:Connect(function(owner: Player, plot: Plot)
		activate(owner, plot)
	end)
	Plots.PlotReleased:Connect(function(_owner: Player, plot: Plot)
		deactivate(plot)
	end)
	-- Any save change (an equip, a hire, a level-up, a level copy): the plot's nurses follow. sync() diffs.
	PlayerData.Changed:Connect(function(player: Player)
		sync(player)
	end)
	Levels.LevelChanged:Connect(function(player: Player)
		sync(player)
	end)

	-- A complete journal group whose reward is missing gets it now (quietly). Idempotent.
	local function repair(player: Player, data: Types.Data)
		if #NurseLogic.setsDue(data.NurseIndex, NursesData, Rarities, data.JournalSets) > 0 then
			PlayerData.update(player, function(d)
				grantSets(d)
			end)
		end
	end
	PlayerData.Loaded:Connect(repair)

	for _, plot in Plots.all() do
		local owner = plot.Owner
		if owner then
			activate(owner, plot) -- plots handed out before Nurses started
		end
	end
	for _, player in Players:GetPlayers() do
		local data = PlayerData.get(player)
		if data then
			task.spawn(repair, player, data)
		end
	end
end

return Nurses
