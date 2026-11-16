-- Customers: spawn at the door, queue at the counter, wait with a patience bar, get served or leave.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Economy = require(script.Parent.Economy)

local Customers = {}

type Customer = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Prompt: ProximityPrompt,
	Bar: Frame,
	Bubble: BillboardGui,
	State: "walking" | "waiting" | "leaving",
	PatienceLeft: number,
	IsNight: boolean,
}

local queue: { Customer } = {}
local folder: Folder

local SKIN_TONES = {
	Color3.fromRGB(255, 224, 189),
	Color3.fromRGB(234, 192, 134),
	Color3.fromRGB(198, 134, 66),
	Color3.fromRGB(141, 85, 36),
	Color3.fromRGB(92, 56, 32),
}
local SHIRT_COLOURS = {
	Color3.fromRGB(90, 160, 255),
	Color3.fromRGB(255, 120, 120),
	Color3.fromRGB(120, 220, 140),
	Color3.fromRGB(255, 210, 90),
	Color3.fromRGB(190, 140, 255),
}

local function pick<T>(list: { T }): T
	return list[math.random(1, #list)]
end

local function slotPosition(shop, index: number): Vector3
	local start: BasePart = shop.QueueStart
	return start.Position - start.CFrame.LookVector * ((index - 1) * Config.QueueSpacing)
end

local function makeBubble(head: BasePart, isNight: boolean): (BillboardGui, Frame)
	local bubble = Instance.new("BillboardGui")
	bubble.Name = "OrderBubble"
	bubble.Size = UDim2.fromOffset(140, 56)
	bubble.StudsOffset = Vector3.new(0, 2.6, 0)
	bubble.AlwaysOnTop = true
	bubble.Enabled = false

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.62, 0)
	label.BackgroundColor3 = isNight and Color3.fromRGB(70, 40, 110) or Color3.fromRGB(255, 255, 255)
	label.TextColor3 = isNight and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(40, 40, 40)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "1 " .. Config.ProductName
	label.Parent = bubble
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = label

	local track = Instance.new("Frame")
	track.Position = UDim2.new(0.1, 0, 0.72, 0)
	track.Size = UDim2.new(0.8, 0, 0.18, 0)
	track.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	track.BorderSizePixel = 0
	track.Parent = bubble

	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = Color3.fromRGB(90, 220, 110)
	bar.BorderSizePixel = 0
	bar.Parent = track

	bubble.Parent = head
	return bubble, bar
end

local function removeFromQueue(customer: Customer)
	local index = table.find(queue, customer)
	if index then
		table.remove(queue, index)
	end
end

local function leave(shop, customer: Customer, happy: boolean)
	customer.State = "leaving"
	customer.Prompt.Enabled = false
	customer.Bubble.Enabled = false
	removeFromQueue(customer)
	if happy then
		customer.Humanoid.Jump = true
	end
	task.spawn(function()
		local target = shop.CustomerExit.Position
		local started = os.clock()
		while customer.Model.Parent and os.clock() - started < 20 do
			customer.Humanoid:MoveTo(target)
			if (customer.Root.Position - target).Magnitude < 3 then
				break
			end
			task.wait(0.5)
		end
		customer.Model:Destroy()
	end)
end

local function spawnCustomer(shop): Customer?
	local isNight = Workspace:GetAttribute("IsNight") == true

	local description = Instance.new("HumanoidDescription")
	local skin = pick(SKIN_TONES)
	description.HeadColor = skin
	description.LeftArmColor = skin
	description.RightArmColor = skin
	description.LeftLegColor = pick(SHIRT_COLOURS)
	description.RightLegColor = description.LeftLegColor
	description.TorsoColor = pick(SHIRT_COLOURS)

	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[Customers] Could not create a customer:", model)
		return nil
	end

	model.Name = isNight and "NightCustomer" or "Customer"
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local head = model:FindFirstChild("Head") :: BasePart
	humanoid.WalkSpeed = Config.CustomerWalkSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Customers"
		end
	end

	if isNight then
		-- Spooky-cute, never scary: a soft purple glow. Content must stay Minimal/Mild for Kids.
		local glow = Instance.new("Highlight")
		glow.FillColor = Color3.fromRGB(170, 120, 255)
		glow.FillTransparency = 0.6
		glow.OutlineColor = Color3.fromRGB(220, 200, 255)
		glow.Parent = model
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ServePrompt"
	prompt.ActionText = "Serve"
	prompt.ObjectText = isNight and "Night Customer" or "Customer"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = root

	local bubble, bar = makeBubble(head, isNight)

	model:PivotTo(CFrame.new(shop.CustomerSpawn.Position + Vector3.new(0, 3, 0)))
	model.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil) -- the server walks customers, so they move smoothly for everyone
	end)

	local customer: Customer = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Prompt = prompt,
		Bar = bar,
		Bubble = bubble,
		State = "walking",
		PatienceLeft = 1,
		IsNight = isNight,
	}

	prompt.Triggered:Connect(function(player)
		if customer.State ~= "waiting" then
			return
		end
		local carrying = Economy.carrying(player)
		if carrying <= 0 then
			Economy.toast(player, "You need a " .. Config.ProductName .. ". Make one at the station!")
			return
		end
		Economy.setCarrying(player, carrying - 1)
		local earned = Economy.payFor(player, customer.PatienceLeft, customer.IsNight)
		Economy.toast(player, "+" .. earned .. " " .. Config.CurrencyName)
		leave(shop, customer, true)
	end)

	humanoid.Died:Connect(function()
		removeFromQueue(customer)
		task.delay(2, function()
			model:Destroy()
		end)
	end)

	table.insert(queue, customer)
	return customer
end

local function tick(shop, dt: number)
	for index, customer in table.clone(queue) do
		local target = slotPosition(shop, index)
		local flat = Vector3.new(customer.Root.Position.X, target.Y, customer.Root.Position.Z)
		local arrived = (flat - target).Magnitude < 2.5

		if customer.State == "walking" then
			customer.Humanoid:MoveTo(target)
			if arrived and index == 1 then
				customer.State = "waiting"
				customer.Prompt.Enabled = true
				customer.Bubble.Enabled = true
			end
		elseif customer.State == "waiting" then
			customer.PatienceLeft -= dt / Config.PatienceSeconds
			customer.Bar.Size = UDim2.fromScale(math.max(customer.PatienceLeft, 0), 1)
			customer.Bar.BackgroundColor3 = customer.PatienceLeft > 0.5 and Color3.fromRGB(90, 220, 110)
				or customer.PatienceLeft > 0.2 and Color3.fromRGB(255, 200, 60)
				or Color3.fromRGB(240, 80, 80)
			if customer.PatienceLeft <= 0 then
				leave(shop, customer, false)
			end
		end
	end
end

function Customers.start(shop)
	folder = Instance.new("Folder")
	folder.Name = "Customers"
	folder.Parent = Workspace

	local TICK = 0.25
	task.spawn(function()
		while true do
			tick(shop, TICK)
			task.wait(TICK)
		end
	end)

	task.spawn(function()
		while true do
			local playerCount = #Players:GetPlayers()
			local interval = Config.SpawnEverySeconds
				/ (1 + Config.SpawnSpeedupPerExtraPlayer * math.max(playerCount - 1, 0))
			task.wait(interval)
			if playerCount > 0 and #queue < Config.MaxQueue then
				spawnCustomer(shop)
			end
		end
	end)
end

return Customers
