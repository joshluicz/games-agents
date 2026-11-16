--!strict
-- The 🛗 lift's floor picker and the ride on this client (Progression v2 build plan §B3/§B4/§B9, §C T6). OWNER: T6.
--   init(ctx)
--     · A LiftPrompt this player triggers (ProximityPromptService on this client) fires ctx.fire("Open", "Lift",
--       { Building, From }) and the picker opens: one big button per floor of THAT building only ("🛎️ G", "🛏️ 1",
--       "🛁 2", "💊 3", "🚁 R", from Data/Departments by floor), the top floor first; the floor you're on shows 📍 and
--       can't be picked. A tap asks RideLift(floor) (Hud.ask); a refusal toasts the server's words with a shake.
--       Walking away from the landing closes it.
--     · Your ride: when the server sets YOUR player attribute LiftRide ("<plot>,<from>,<to>,<seconds>,<serverTime>",
--       Server/Lift), this client plays the Ding, steps you into the car, closes its drawn doors, slides the car with
--       you inside (your root anchored on this client, so the camera eases along: no cut), opens the doors and steps
--       you out at the landing, all within the ride's seconds; the server's PivotTo lands on the same spot. With
--       reduced motion (Kit.reducedMotion) nothing slides: the Ding, and you're there.
--     · Every other ride (a patient, a porter, another player): each Building's Lift Model (tag "HospitalLift",
--       PlotBuilder.LIFT_TAG) carries a Ride attribute ("<from>,<to>,<seconds>,<serverTime>"); a car near the camera
--       slides on this client, a far one just moves. The server never moves a car.
-- Nothing runs every frame: tweens only, while a car moves; the picker's distance check runs only while it's open.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local Hud = require(script.Parent.Hud)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

------------------------------------------------------------------------------------------------------------------
-- Pure helpers (no Roblox APIs; tests/Hospital.spec loads this block on its own)
------------------------------------------------------------------------------------------------------------------

-- PURE-BEGIN
local Pure = {}

Pure.IN = 0.2 -- of a ride: stepping into the car ...
Pure.OUT = 0.15 -- ... and out at the far landing; the car moves in between
Pure.SLIDE_STUDS = 250 -- a car further than this from the camera just moves (no slide)

type Ride = { Plot: number?, From: number, To: number, Seconds: number, At: number }

-- Server/Lift's ride attributes: "<plot>,<from>,<to>,<seconds>,<at>" (a rider's LiftRide) or
-- "<from>,<to>,<seconds>,<at>" (a Lift's Ride). nil for anything else.
function Pure.decodeRide(text: any, withPlot: boolean): Ride?
	if type(text) ~= "string" or text == "" then
		return nil
	end
	local values: { number } = {}
	for piece in string.gmatch(text, "[^,]+") do
		local n = tonumber(piece)
		if not n or n ~= n then
			return nil
		end
		table.insert(values, n)
	end
	local offset = if withPlot then 1 else 0
	if #values ~= 4 + offset then
		return nil
	end
	local from, to, seconds = values[1 + offset], values[2 + offset], values[3 + offset]
	if from ~= math.floor(from) or to ~= math.floor(to) or seconds <= 0 or seconds > 30 then
		return nil
	end
	return {
		Plot = if withPlot then values[1] else nil,
		From = from,
		To = to,
		Seconds = seconds,
		At = values[4 + offset],
	}
end

-- A floor's button: the icon of the department on that floor (Data/Departments, the first in Order), then "G" for the
-- ground, "R" for the roof (the Roof department's floor), else its number.
function Pure.label(floor: number, departments: any): string
	local icon, roof = "🛗", false
	if type(departments) == "table" and type(departments.Order) == "table" then
		for _, id in departments.Order do
			local dept = rawget(departments, id)
			if type(dept) == "table" and dept.Floor == floor then
				icon = if type(dept.Icon) == "string" then dept.Icon else icon
				roof = id == "Roof"
				break
			end
		end
	end
	local name = if floor == 0 then "G" elseif roof then "R" else tostring(floor)
	return icon .. " " .. name
end

-- The picker's buttons for a building with `count` floors, the top floor first; `here` is the floor you're on.
function Pure.buttons(count: any, here: any, departments: any): { { Floor: number, Text: string, Here: boolean } }
	local top = math.max(0, math.floor(tonumber(count) or 0))
	local out = {}
	for floor = top, 0, -1 do
		table.insert(out, { Floor = floor, Text = Pure.label(floor, departments), Here = floor == here })
	end
	return out
end

-- How long is left of a ride that started at server time `at` (never below a short beat).
function Pure.remaining(seconds: number, at: number, now: number): number
	return math.max(0.15, seconds - math.max(0, now - at))
end
-- PURE-END

local LiftPanel = {}
LiftPanel.Pure = Pure

local LIFT_TAG = "HospitalLift" -- PlotBuilder.LIFT_TAG (a server module, so not required here)
local PICKER_REACH = 14 -- studs from the landing before the picker closes by itself
local BUTTON_HEIGHT = 64
local DOOR_OPEN = { -0.21, 1.21 } -- the drawn doors' X centres: open (off the car's face) ...
local DOOR_SHUT = { 0.25, 0.75 } -- ... and shut

local player = Players.LocalPlayer

local function tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	local info = TweenInfo.new(math.max(seconds, 0), style or Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local ok, created = pcall(TweenService.Create, TweenService, instance, info, goal)
	if ok then
		created:Play()
	end
end

local function buildingOf(plotIndex: number?): Model?
	local clinics = Workspace:FindFirstChild("Clinics")
	local plot = clinics and plotIndex and clinics:FindFirstChild("Plot_" .. plotIndex)
	local building = plot and plot:FindFirstChild("Building")
	return if building and building:IsA("Model") then building else nil
end

local function landingOf(building: Instance, floor: number): BasePart?
	local found: Instance? = nil
	if floor == 0 then
		found = building:FindFirstChild("Landing_0")
	else
		local floorModel = building:FindFirstChild("Floor_" .. floor)
		found = floorModel and floorModel:FindFirstChild("Landing")
	end
	return if found and found:IsA("BasePart") then found else nil
end

local function floorY(landing: BasePart): number
	return landing.Position.Y - landing.Size.Y / 2
end

-- Where the car rests at a landing's floor (its own x and z: the shaft).
local function carAt(car: BasePart, landing: BasePart): CFrame
	return CFrame.new(car.Position.X, floorY(landing) + car.Size.Y / 2, car.Position.Z) * car.CFrame.Rotation
end

-- How high a character's root stands over the floor (the same rule as Server/Lift).
local function rootLift(character: Model): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and root:IsA("BasePart") and humanoid.HipHeight > 0 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return 3
end

local function doors(car: BasePart, open: boolean, seconds: number)
	local gui = car:FindFirstChild("DoorsGui")
	if not gui then
		return
	end
	local xs = if open then DOOR_OPEN else DOOR_SHUT
	for i, name in { "DoorL", "DoorR" } do
		local door = gui:FindFirstChild(name)
		if door and door:IsA("GuiObject") then
			local goal = UDim2.fromScale(xs[i], 0.5)
			if seconds <= 0 then
				door.Position = goal
			else
				tween(door, seconds, { Position = goal })
			end
		end
	end
end

-- The car alone: doors shut, it slides, doors open (a patient's or someone else's ride).
local cars: { [BasePart]: number } = setmetatable({}, { __mode = "k" }) :: any
local function slideCar(car: BasePart, from: BasePart?, to: BasePart, seconds: number)
	local token = (cars[car] or 0) + 1
	cars[car] = token
	local camera = Workspace.CurrentCamera
	local far = camera == nil or (camera.CFrame.Position - car.Position).Magnitude > Pure.SLIDE_STUDS
	if far or Kit.reducedMotion() or seconds < 0.3 then
		car.CFrame = carAt(car, to)
		doors(car, true, 0)
		return
	end
	if from then
		car.CFrame = carAt(car, from)
	end
	local doorTime = math.min(0.25, seconds * 0.2)
	doors(car, false, doorTime)
	task.delay(doorTime, function()
		if cars[car] ~= token then
			return
		end
		tween(car, seconds - doorTime * 2, { CFrame = carAt(car, to) })
		task.delay(seconds - doorTime * 2, function()
			if cars[car] == token then
				doors(car, true, doorTime)
			end
		end)
	end)
end

------------------------------------------------------------------------------------------------------------------
-- Your own ride
------------------------------------------------------------------------------------------------------------------

local riding: { Building: Model?, At: number } = { Building = nil, At = -1 }

local function rideMe(ctx: Types.Ctx, info: Ride)
	local building = buildingOf(info.Plot)
	ctx.fire("Sound", "Ding")
	if not building then
		return
	end
	riding.Building, riding.At = building, info.At
	local liftModel = building:FindFirstChild("Lift")
	local carPart = liftModel and liftModel:FindFirstChild("Car")
	local car = if carPart and carPart:IsA("BasePart") then carPart else nil
	local from, to = landingOf(building, info.From), landingOf(building, info.To)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local root = if rootPart and rootPart:IsA("BasePart") then rootPart else nil
	if not to then
		return
	end
	if Kit.reducedMotion() then
		-- Calm: no slide. You're there now; the server's PivotTo lands on the same spot a moment later.
		if car then
			car.CFrame = carAt(car, to)
		end
		if character and root then
			local out = to.CFrame * CFrame.new(0, -to.Size.Y / 2 + rootLift(character), 0)
			pcall(function()
				character:PivotTo(out)
			end)
		end
		return
	end
	if not (car and from and character and root) then
		if car then
			slideCar(car, from, to, info.Seconds)
		end
		return
	end
	local total = Pure.remaining(info.Seconds, info.At, Workspace:GetServerTimeNow())
	local stepIn, stepOut = total * Pure.IN, total * Pure.OUT
	local move = total - stepIn - stepOut
	local lift = rootLift(character)
	local facing = to.CFrame.Rotation -- out of the lift
	local inFrom = CFrame.new(car.Position.X, floorY(from) + lift, car.Position.Z) * facing
	local inTo = CFrame.new(car.Position.X, floorY(to) + lift, car.Position.Z) * facing
	local out = to.CFrame * CFrame.new(0, -to.Size.Y / 2 + lift, 0)
	cars[car] = (cars[car] or 0) + 1 -- this ride owns the car now
	local mine = info.At
	pcall(function()
		root.Anchored = true -- on this client only: the camera follows the root along the shaft
		car.CFrame = carAt(car, from)
		doors(car, true, 0)
		tween(root, stepIn, { CFrame = inFrom })
		task.wait(stepIn)
		local doorTime = math.min(0.2, move * 0.2)
		doors(car, false, doorTime)
		tween(root, move, { CFrame = inTo })
		tween(car, move, { CFrame = carAt(car, to) })
		task.wait(move)
		doors(car, true, doorTime)
		tween(root, stepOut, { CFrame = out })
		task.wait(stepOut)
		if riding.At == mine then
			root.CFrame = out
		end
	end)
	-- Always let go (a newer ride owns the root now: it lets go itself).
	if riding.At == mine then
		riding.Building = nil
		pcall(function()
			root.Anchored = false
		end)
	end
end

------------------------------------------------------------------------------------------------------------------
-- The floor picker
------------------------------------------------------------------------------------------------------------------

function LiftPanel.init(ctx: Types.Ctx)
	local modal = Hud.modal(ctx, {
		Name = "Lift",
		Title = "🛗 Lift",
		Accent = Theme.Colors.Cyan,
		Layer = "Popup",
		MaxSize = Vector2.new(420, 500),
	})
	local grid = Instance.new("Frame")
	grid.Name = "Floors"
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.fromScale(1, 1)
	Kit.pad(grid)
	local layout = Instance.new("UIGridLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.CellPadding = UDim2.fromOffset(Theme.Size.Gap, Theme.Size.Gap)
	layout.Parent = grid
	grid.Parent = modal.Body

	local busy = false
	local openToken = 0

	local function ask(button: TextButton, floor: number)
		if busy then
			return
		end
		busy = true
		local ok, message = Hud.ask(ctx.Remotes.RideLift, floor)
		busy = false
		if ok then
			modal.close()
		else
			Hud.shake(button)
			if message ~= "" then
				ctx.toast(message)
			end
		end
	end

	local function open(info: any)
		local building = if type(info) == "table" then info.Building else nil
		if not (typeof(building) == "Instance" and building:IsA("Model")) then
			return
		end
		local here = if type(info.From) == "number" then info.From else nil
		local landing = if here ~= nil then landingOf(building, here) else nil
		for _, child in grid:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		local list = Pure.buttons(building:GetAttribute("Floors"), here, ctx.Data.Departments)
		-- Two columns once there are more than three floors, so five fit a small landscape phone.
		local columns = if #list > 3 then 2 else 1
		layout.CellSize = UDim2.new(1 / columns, if columns > 1 then -Theme.Size.Gap / 2 else 0, 0, BUTTON_HEIGHT)
		local first: GuiObject? = nil
		for index, entry in list do
			local button = Kit.button({
				Name = "Floor_" .. entry.Floor,
				Kind = if entry.Here then "Quiet" else "Cyan",
				Text = if entry.Here then "📍 " .. entry.Text else entry.Text,
				TextSize = Theme.TextSize.Title,
				LayoutOrder = index,
				Parent = grid,
			})
			if entry.Here then
				Kit.setEnabled(button, false)
			else
				first = first or button
				button.Activated:Connect(function()
					ask(button, entry.Floor)
				end)
			end
		end
		modal.Focus = first or modal.CloseButton
		modal.open()
		-- Walk away from the landing and it closes by itself.
		openToken += 1
		local token = openToken
		if landing then
			task.spawn(function()
				while modal.isOpen() and openToken == token do
					task.wait(0.3)
					local character = player.Character
					local root = character and character:FindFirstChild("HumanoidRootPart")
					if
						not landing.Parent
						or not (root and root:IsA("BasePart"))
						or (root.Position - landing.Position).Magnitude > PICKER_REACH
					then
						if openToken == token then
							modal.close()
						end
						return
					end
				end
			end)
		end
	end

	ctx.on("Open", function(name: any, info: any)
		if name == "Lift" then
			open(info)
		end
	end)

	-- A LiftPrompt this player triggered (fires on this client only for the local player).
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who ~= player or prompt.Name ~= "LiftPrompt" then
			return
		end
		local point = prompt.Parent
		local landing = point and point.Parent
		local building = landing and landing:FindFirstAncestor("Building")
		if landing and building then
			ctx.fire("Open", "Lift", { Building = building, From = landing:GetAttribute("Floor") })
		end
	end)

	-- Your rides (Server/Lift sets your LiftRide attribute at the start of each).
	player:GetAttributeChangedSignal("LiftRide"):Connect(function()
		local info = Pure.decodeRide(player:GetAttribute("LiftRide"), true)
		if not info or info.At == riding.At then
			return
		end
		if modal.isOpen() then
			modal.close()
		end
		task.spawn(rideMe, ctx, info)
	end)

	-- Everyone else's rides: each lift's car slides near the camera.
	local function watch(instance: Instance)
		if not instance:IsA("Model") then
			return
		end
		instance:GetAttributeChangedSignal("Ride"):Connect(function()
			local info = Pure.decodeRide(instance:GetAttribute("Ride"), false)
			local building = instance.Parent
			if not info or not building then
				return
			end
			if riding.Building == building and math.abs(riding.At - info.At) < 0.01 then
				return -- your own ride: rideMe moves this car
			end
			local carPart = instance:FindFirstChild("Car")
			local to = landingOf(building, info.To)
			if carPart and carPart:IsA("BasePart") and to then
				slideCar(
					carPart,
					landingOf(building, info.From),
					to,
					Pure.remaining(info.Seconds, info.At, Workspace:GetServerTimeNow())
				)
			end
		end)
	end
	CollectionService:GetInstanceAddedSignal(LIFT_TAG):Connect(watch)
	for _, instance in CollectionService:GetTagged(LIFT_TAG) do
		watch(instance)
	end
end

return LiftPanel
