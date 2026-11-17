--!strict
-- The clinic's doors (Real Clinic build plan, Task 1; design §8.1-§8.2). Server only. OWNER: Task 1 (the building).
-- Server/HospitalBuilder builds every door as a Model tagged Doors.TAG ("ClinicDoor"): the FrontDoor (a glass pair,
-- DoorL and DoorR) and Door_<name> for the A&E door, the X-ray room and the bought rooms (one Panel each). Each has:
--   panels      BaseParts with the attribute Slide (a Vector3 in the panel's own space: where it slides to when open,
--               into the wall beside the doorway). Built shut
--   Sensor      an invisible marker at the doorway's middle, on the floor
--   attributes  Door (its Logic/Building.DOORS name), Opens (a level, or nil), Room (a RoomId, or nil),
--               State ("Locked" | "Shut" | "Open")
--   LockGui     a navy "🔒 Opens at Lv N" / "💰 150 to open" plate on a panel (only on a door that can be locked)
-- A door is LOCKED while its Building's Level is under its Opens, or while its plot has no Room_<Room> under Rooms:
-- its panels are solid and its LockGui shows. An unlocked door's panels are walk-through (patients move by hops and
-- PivotTo, and nobody is ever shut in if this module stops) and slide open while a player's character or a creature
-- (tag "CreatureMotion") is within Pure.RADIUS studs of its Sensor on the same floor.
-- One loop for every door in the town, Pure.CHECK_SECONDS apart; a door changes only when its state does, with ONE
-- server tween per panel (never per frame). A level-up rebuilds the Building, and the old doors drop out by
-- themselves. Buying a room needs no rebuild: the next check unlocks its door.
--
--   Doors.TAG = "ClinicDoor"
--   Doors.start()        once (Main.server)
--   Doors.Pure           locked(level, opens, room, owned) · near(points, x, y, z, radius, height) · state(locked,
--                        near) · tests/Hospital.spec loads the PURE block

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Doors = {}

Doors.TAG = "ClinicDoor"

-- PURE-BEGIN
-- Numbers and strings only (no Roblox types).
local Pure = {}

Pure.RADIUS = 8 -- studs (flat) from the Sensor that opens a door
Pure.HEIGHT = 8 -- ... and at most this far above or below it (the floor upstairs never opens the ground's doors)
Pure.CHECK_SECONDS = 0.25
Pure.SLIDE_SECONDS = 0.45

-- Whether a door is shut for good for now: a level under its Opens, or its room not owned.
function Pure.locked(level: any, opens: any, room: any, owned: boolean): boolean
	local lv = if type(level) == "number" and level == level then level else 1
	if type(opens) == "number" and lv < opens then
		return true
	end
	return type(room) == "string" and room ~= "" and not owned
end

-- Whether any point ({ X, Y, Z }: a Vector3 works) is within `radius` studs across and `height` up or down.
function Pure.near(points: { any }, x: number, y: number, z: number, radius: number, height: number): boolean
	local r2 = radius * radius
	for _, p in points do
		local dx, dz = p.X - x, p.Z - z
		if dx * dx + dz * dz <= r2 and math.abs(p.Y - y) <= height then
			return true
		end
	end
	return false
end

function Pure.state(locked: boolean, near: boolean): string
	if locked then
		return "Locked"
	end
	return if near then "Open" else "Shut"
end
-- PURE-END

Doors.Pure = Pure

local MOTION_TAG = "CreatureMotion" -- every creature (CreatureBuilder.MOTION_TAG): patients and nurses

type Panel = { Part: BasePart, Closed: CFrame, Open: CFrame }
type Entry = { Panels: { Panel }, Sensor: BasePart?, State: string }

local entries: { [Model]: Entry } = {}
local started = false

local function register(instance: Instance)
	if not instance:IsA("Model") or entries[instance] then
		return
	end
	local panels: { Panel } = {}
	for _, child in instance:GetChildren() do
		local slide = child:GetAttribute("Slide")
		if child:IsA("BasePart") and typeof(slide) == "Vector3" then
			-- Built shut: where it stands now is its shut place.
			table.insert(panels, { Part = child, Closed = child.CFrame, Open = child.CFrame * CFrame.new(slide) })
		end
	end
	local sensor = instance:FindFirstChild("Sensor")
	local state = instance:GetAttribute("State")
	entries[instance] = {
		Panels = panels,
		Sensor = if sensor and sensor:IsA("BasePart") then sensor else nil,
		State = if type(state) == "string" then state else "Shut",
	}
end

local function lockedNow(model: Model): boolean
	local building = model:FindFirstAncestor("Building")
	local room = model:GetAttribute("Room")
	local owned = false
	if type(room) == "string" and building then
		local plot = building.Parent
		local rooms = plot and plot:FindFirstChild("Rooms")
		owned = rooms ~= nil and rooms:FindFirstChild("Room_" .. room) ~= nil
	end
	return Pure.locked(building and building:GetAttribute("Level"), model:GetAttribute("Opens"), room, owned)
end

-- Where everyone who opens doors stands now: players' roots and creatures' pivots.
local function gather(): { Vector3 }
	local points: { Vector3 } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(points, root.Position)
		end
	end
	for _, creature in CollectionService:GetTagged(MOTION_TAG) do
		if creature:IsA("Model") and creature:IsDescendantOf(Workspace) then
			table.insert(points, creature:GetPivot().Position)
		end
	end
	return points
end

local slide: TweenInfo? = nil

local function apply(model: Model, entry: Entry, state: string)
	local wasOpen = entry.State == "Open"
	local open = state == "Open"
	local info = slide or TweenInfo.new(Pure.SLIDE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	slide = info
	for _, panel in entry.Panels do
		panel.Part.CanCollide = state == "Locked"
		if open ~= wasOpen then
			TweenService:Create(panel.Part, info, { CFrame = if open then panel.Open else panel.Closed }):Play()
		end
		local gui = panel.Part:FindFirstChild("LockGui")
		if gui and gui:IsA("SurfaceGui") then
			gui.Enabled = state == "Locked"
		end
	end
	entry.State = state
	model:SetAttribute("State", state)
end

local function check()
	local points = gather()
	for model, entry in entries do
		if not model.Parent then
			entries[model] = nil -- a rebuilt Building took it
			continue
		end
		local ok, err = pcall(function()
			local locked = lockedNow(model)
			local near = false
			if not locked and entry.Sensor then
				local at = entry.Sensor.Position
				near = Pure.near(points, at.X, at.Y, at.Z, Pure.RADIUS, Pure.HEIGHT)
			end
			local state = Pure.state(locked, near)
			if state ~= entry.State then
				apply(model, entry, state)
			end
		end)
		if not ok then
			warn("[Doors] " .. model:GetFullName() .. ": " .. tostring(err))
			entries[model] = nil
		end
	end
end

function Doors.start()
	if started then
		return
	end
	started = true
	CollectionService:GetInstanceAddedSignal(Doors.TAG):Connect(register)
	CollectionService:GetInstanceRemovedSignal(Doors.TAG):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			entries[instance] = nil
		end
	end)
	for _, instance in CollectionService:GetTagged(Doors.TAG) do
		register(instance)
	end
	task.spawn(function()
		while true do
			task.wait(Pure.CHECK_SECONDS)
			check()
		end
	end)
end

return Doors
