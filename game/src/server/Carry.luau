--!strict
-- What each player is carrying: typed treatment items, up to their tray size (build plan §B1/§B5, Task 2).
-- Server only. The server is the only one that changes it; clients just read the attributes.
--
--   Carry.items(p): { ItemId }      a copy, oldest first
--   Carry.capacity(p): number       Logic/Prices.capacity(<Bigger Tray level>) = 1 + level
--   Carry.add(p, itemId): boolean   false: unknown item, tray full, or the player is gone
--   Carry.take(p, itemId): boolean  removes ONE of that item; false if the player doesn't carry it
--   Carry.clear(p)
-- Extras: Carry.has(p, itemId): boolean · Carry.isFull(p): boolean
--
-- Kept in step on every change:
--   · player attribute `Carry`: the ids joined with commas, oldest first ("Potion,Plaster"; "" = nothing)
--   · player attribute `CarryMax`: the tray size (follows a Bigger Tray purchase straight away)
--   · the tray bubble: a BillboardGui `CarryGui` on the character's Head. Each item is a big emoji in a ring of
--     its station's colour (so it matches the patient's ailment colour), followed by faint dots for the room
--     left. The bubble turns gold when the tray is full and hides when you carry nothing. It's sized in studs,
--     drawn on top and unlit, so it stays readable on a phone, at night and through a roof.
-- Cleared on death and on leave. A new character without a death (LoadCharacter) gets the same items back.
-- The tray level is read from PlayerData directly (same number as Economy.level), so Carry never requires
-- Economy and Economy may require Carry.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Items = require(Shared.Data.Items)
local Stations = require(Shared.Data.Stations)
local Prices = require(Shared.Logic.Prices)
local PlayerData = require(script.Parent.PlayerData)

local Carry = {}

local GUI_NAME = "CarryGui"

-- The bubble, in studs (BillboardGui scale sizes are studs, so it shrinks with distance like a real object).
local SLOT = 1.7 -- one item circle
local GAP = 0.2 -- between circles
local PAD = 0.28 -- inside the bubble's edge
local SHADOW = 0.14 -- how far the soft shadow sits below the bubble
local LIFT = 3 -- above the top of the head, clear of the default name tag
local MAX_DISTANCE = 60

local COLORS = {
	Bubble = Color3.fromRGB(255, 250, 240), -- Theme.Colors.Paper
	BubbleFull = Color3.fromRGB(255, 226, 120), -- warm gold: "your tray is full"
	Shadow = Color3.fromRGB(74, 52, 42), -- Theme.Colors.Ink
	Inner = Color3.fromRGB(255, 255, 255),
	Empty = Color3.fromRGB(255, 255, 255),
	Fallback = Color3.fromRGB(206, 152, 106),
}

local carried: { [Player]: { string } } = {}
local guis: { [Player]: BillboardGui } = {}
local characterConnections: { [Player]: { RBXScriptConnection } } = {}
local joined: { [Player]: boolean } = {}

------------------------------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------------------------------

local function isPlayer(player: any): boolean
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function trayLevel(player: Player): number
	local data = PlayerData.get(player)
	local level = data and data.Upgrades.Tray
	if type(level) == "number" and level == level and level >= 0 then
		return math.floor(level)
	end
	return 0
end

local function itemColor(itemId: string): Color3
	local item = Items[itemId]
	local station = item and Stations[item.Station]
	return if station then station.Color else COLORS.Fallback
end

local function round(parent: Instance)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = parent
end

local function frame(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

------------------------------------------------------------------------------------------------------------------
-- The tray bubble above the head
------------------------------------------------------------------------------------------------------------------

local function liveGui(player: Player): BillboardGui?
	local gui = guis[player]
	if gui and gui.Parent and player.Character and gui:IsDescendantOf(player.Character) then
		return gui
	end
	return nil
end

local function render(player: Player)
	local gui = liveGui(player)
	if not gui then
		return
	end
	local list = carried[player] or {}
	local capacity = Carry.capacity(player)
	local max = math.max(capacity, #list)

	local old = gui:FindFirstChild("Tray")
	if old then
		old:Destroy()
	end
	gui.Enabled = #list > 0
	if #list == 0 then
		return
	end

	local width = max * SLOT + (max - 1) * GAP + 2 * PAD
	local height = SLOT + 2 * PAD
	local total = height + SHADOW
	gui.Size = UDim2.fromScale(width, total)

	local root = Instance.new("Frame")
	root.Name = "Tray"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)

	-- A soft drop shadow, then the bubble itself: two pills, sized in scale so nothing depends on pixels.
	local pill = UDim2.fromScale(1, height / total)
	local shadow = frame(root, "Shadow", pill, UDim2.fromScale(0.5, (height / 2 + SHADOW) / total), COLORS.Shadow)
	shadow.BackgroundTransparency = 0.7
	shadow.ZIndex = 1
	round(shadow)
	local full = #list >= capacity
	local bubbleColor = if full then COLORS.BubbleFull else COLORS.Bubble
	local bubble = frame(root, "Bubble", pill, UDim2.fromScale(0.5, (height / 2) / total), bubbleColor)
	bubble.BackgroundTransparency = 0.05
	bubble.ZIndex = 2
	round(bubble)

	local slotW, slotH = SLOT / width, SLOT / height
	for index = 1, max do
		local centre = UDim2.fromScale((PAD + (index - 1) * (SLOT + GAP) + SLOT / 2) / width, 0.5)
		local itemId = list[index]
		if itemId then
			local ring = frame(bubble, "Item_" .. index, UDim2.fromScale(slotW, slotH), centre, itemColor(itemId))
			ring:SetAttribute("ItemId", itemId)
			round(ring)
			local inner = frame(ring, "Inner", UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.5, 0.5), COLORS.Inner)
			round(inner)
			local icon = Instance.new("TextLabel")
			icon.Name = "Icon"
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.52)
			icon.Size = UDim2.fromScale(0.78, 0.78)
			icon.BackgroundTransparency = 1
			icon.Font = Enum.Font.FredokaOne
			icon.TextScaled = true
			icon.Text = Items[itemId] and Items[itemId].Icon or "❔"
			icon.Parent = inner
		else
			local dot =
				frame(bubble, "Empty_" .. index, UDim2.fromScale(slotW * 0.42, slotH * 0.42), centre, COLORS.Empty)
			dot.BackgroundTransparency = 0.35
			round(dot)
		end
	end

	root.Parent = gui -- parent last: the finished bubble replicates in one go
end

local function attachGui(player: Player, character: Model)
	local head = character:FindFirstChild("Head")
	local adornee: BasePart? = nil
	local lift = LIFT
	if head and head:IsA("BasePart") then
		adornee = head
		lift += head.Size.Y / 2
	else
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			adornee = root
			lift += 3 -- no head on this rig: float above where one would be
		end
	end
	if not adornee then
		return
	end
	local old = adornee:FindFirstChild(GUI_NAME)
	if old then
		old:Destroy()
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = GUI_NAME
	gui.Adornee = adornee
	gui.Size = UDim2.fromScale(SLOT + 2 * PAD, SLOT + 2 * PAD)
	gui.StudsOffsetWorldSpace = Vector3.new(0, lift, 0)
	gui.AlwaysOnTop = true -- never hidden by a hat, a counter or a roof
	gui.LightInfluence = 0 -- as bright at night as by day
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.MaxDistance = MAX_DISTANCE
	gui.Enabled = false
	gui.Parent = adornee
	guis[player] = gui
	render(player)
end

------------------------------------------------------------------------------------------------------------------
-- Keeping the attributes and the bubble in step
------------------------------------------------------------------------------------------------------------------

local function sync(player: Player)
	if player.Parent ~= Players then
		return
	end
	local list = carried[player] or {}
	player:SetAttribute("Carry", table.concat(list, ","))
	player:SetAttribute("CarryMax", Carry.capacity(player))
	render(player)
end

local function disconnectCharacter(player: Player)
	local list = characterConnections[player]
	if list then
		for _, connection in list do
			connection:Disconnect()
		end
	end
	characterConnections[player] = nil
end

local function bindCharacter(player: Player, character: Model)
	disconnectCharacter(player)
	local connections: { RBXScriptConnection } = {}
	characterConnections[player] = connections

	-- The Head can arrive a moment after the character (and is the bubble's anchor).
	character:WaitForChild("Head", 5)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if player.Character ~= character or characterConnections[player] ~= connections then
		return -- respawned (or left) while we waited
	end

	attachGui(player, character)
	if humanoid and humanoid:IsA("Humanoid") then
		table.insert(
			connections,
			humanoid.Died:Connect(function()
				if player.Character == character then
					Carry.clear(player) -- dropped on a faint; nothing else is lost
				end
			end)
		)
	end
end

------------------------------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------------------------------

function Carry.items(player: Player): { string }
	local list = carried[player]
	return if list then table.clone(list) else {}
end

function Carry.capacity(player: Player): number
	if not isPlayer(player) then
		return 1
	end
	return math.max(1, Prices.capacity(trayLevel(player)))
end

function Carry.has(player: Player, itemId: string): boolean
	local list = carried[player]
	return list ~= nil and type(itemId) == "string" and table.find(list, itemId) ~= nil
end

function Carry.isFull(player: Player): boolean
	local list = carried[player]
	return list ~= nil and #list >= Carry.capacity(player)
end

function Carry.add(player: Player, itemId: string): boolean
	-- rawget: Data maps answer `.Order` through their metatable, which is never an item.
	if not isPlayer(player) or type(itemId) ~= "string" or type(rawget(Items :: any, itemId)) ~= "table" then
		return false
	end
	local list = carried[player]
	if not list then
		list = {}
		carried[player] = list
	end
	if #list >= Carry.capacity(player) then
		return false
	end
	table.insert(list, itemId)
	sync(player)
	return true
end

function Carry.take(player: Player, itemId: string): boolean
	local list = carried[player]
	if not list or type(itemId) ~= "string" then
		return false
	end
	local index = table.find(list, itemId)
	if not index then
		return false
	end
	table.remove(list, index)
	sync(player)
	return true
end

function Carry.clear(player: Player)
	local list = carried[player]
	if list and #list > 0 then
		table.clear(list)
		sync(player)
	end
end

function Carry.start()
	local function onJoin(player: Player)
		if joined[player] or player.Parent ~= Players then
			return
		end
		joined[player] = true
		carried[player] = carried[player] or {}
		sync(player)
		player.CharacterAdded:Connect(function(character)
			bindCharacter(player, character)
		end)
		player.CharacterRemoving:Connect(function(character)
			if guis[player] and guis[player]:IsDescendantOf(character) then
				guis[player] = nil
			end
		end)
		if player.Character then
			task.spawn(bindCharacter, player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		disconnectCharacter(player)
		joined[player] = nil
		carried[player] = nil
		guis[player] = nil
	end)

	-- A Bigger Tray purchase (or the save loading) changes the tray size: show the new room straight away.
	PlayerData.Changed:Connect(function(player: Player)
		if carried[player] and player:GetAttribute("CarryMax") ~= Carry.capacity(player) then
			sync(player)
		end
	end)
end

return Carry
