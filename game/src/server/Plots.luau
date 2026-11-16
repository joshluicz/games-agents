--!strict
-- Who owns which clinic plot, and what's built on it (build plan §B1/§B5). Server only.
--   Plots.getPlot(p): Plot?                  the player's plot (nil: none yet, or all plots taken)
--   Plots.ownerOf(plotModel): Player?
--   Plots.all(): { Plot }                    every plot, by index (owned or free)
--   Plots.canWork(p, plot): boolean          the owner, the owner's Roblox friend, or anyone when OpenHelpers
--   Plots.unlockRoom(owner, roomId): boolean sets Data.Rooms[roomId] and builds it (false if unknown/owned)
--   Plots.placeDecor(owner, slotKey, decorId?): boolean   validates, saves and shows it (nil decorId = clear)
--   signals PlotAssigned(p, plot), PlotReleased(p, plot), RoomAdded(plot, roomId, roomModel)
-- Extra helpers:
--   Plots.fromInstance(inst): Plot?          the plot an Instance (a station, a prompt part) belongs to
--   Plots.decorSlot(plot, slotKey): BasePart?
--   Plots.observeRooms(fn): Connection       fn(plot, roomId, roomModel) for every room now AND every room later
--
-- Lifecycle: a joiner gets a free plot once their data loads (middle plots first). Their owned rooms and placed
-- decor are rebuilt, RoomAdded fires for each new room, then PlotAssigned. On leave, PlotReleased fires FIRST
-- (handlers still see plot.Owner), then patients, decor and every room but the Stand are removed and the plot is
-- free again: it goes straight to anyone who is waiting without one.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)
local Rooms = require(Shared.Data.Rooms)
local Decor = require(Shared.Data.Decor)
local PlayerData = require(script.Parent.PlayerData)
local PlotBuilder = require(script.Parent.PlotBuilder)
local DecorBuilder = require(script.Parent.DecorBuilder)

export type Plot = Types.Plot

local Plots = {}

Plots.PlotAssigned = Signal.new()
Plots.PlotReleased = Signal.new()
Plots.RoomAdded = Signal.new()

-- Nearest the spawn first: the middle of each row, then the ends.
local ASSIGN_ORDER = { 2, 5, 1, 3, 4, 6 }

local plots: { Plot } = {}
local byPlayer: { [Player]: Plot } = {}
local byModel: { [Model]: Plot } = {}
local waiting: { Player } = {}
local friends: { [Player]: { [Player]: boolean } } = {}

-- rawget: Data maps answer `.Order` through their metatable, so a plain index would accept the id "Order".
local function knownRoom(id: any): boolean
	return type(id) == "string" and type(rawget(Rooms :: any, id)) == "table"
end

local function knownDecor(id: any): boolean
	return type(id) == "string" and type(rawget(Decor :: any, id)) == "table"
end

local function findPart(model: Model, name: string): BasePart
	local found = model:FindFirstChild(name)
	assert(found and found:IsA("BasePart"), model.Name .. " is missing a Part named " .. name)
	return found :: BasePart
end

local function signLabels(plot: Plot): (TextLabel?, TextLabel?)
	local sign = plot.Model:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChild("SignGui")
	if not gui then
		return nil, nil
	end
	local owner = gui:FindFirstChild("OwnerName")
	local hearts = gui:FindFirstChild("HeartCount")
	return if owner and owner:IsA("TextLabel") then owner else nil,
		if hearts and hearts:IsA("TextLabel") then hearts else nil
end

local function setSign(plot: Plot, owner: Player?)
	local ownerLabel, heartLabel = signLabels(plot)
	if ownerLabel then
		ownerLabel.Text = if owner then owner.DisplayName .. "'s Clinic" else "✨ Free clinic"
	end
	if heartLabel then
		heartLabel.Text = if owner then "❤️ 0" else "" -- Visits keeps this as "❤️ <n>"
	end
end

-- Show a "for sale" outline in every slot whose room the owner doesn't have yet.
local function refreshPreviews(plot: Plot, data: Types.Data?)
	for _, roomId in Rooms.Order do
		local room = Rooms[roomId]
		if roomId ~= "Stand" then
			local owned = data ~= nil and data.Rooms[roomId] == true
			PlotBuilder.setPreview(plot.Model, room.Slot, if data and not owned then roomId else nil)
		end
	end
end

local function homeCFrame(plot: Plot): CFrame
	-- On the Stand floor, behind the counter, facing the street (and the queue).
	return plot.Model:GetPivot() * CFrame.new(0, 3.5, -9)
end

local function sendHome(player: Player, plot: Plot)
	local character = player.Character
	if character and character:FindFirstChild("HumanoidRootPart") then
		character:PivotTo(homeCFrame(plot))
	end
end

------------------------------------------------------------------------------------------------------------------
-- Rooms and decor on a plot
------------------------------------------------------------------------------------------------------------------

function Plots.decorSlot(plot: Plot, slotKey: string): BasePart?
	if type(slotKey) ~= "string" then
		return nil
	end
	local roomId, n = string.match(slotKey, "^(%w+):(%d+)$")
	if not roomId or not knownRoom(roomId) then
		return nil
	end
	local roomsFolder = plot.Model:FindFirstChild("Rooms")
	local room = roomsFolder and roomsFolder:FindFirstChild("Room_" .. roomId)
	local slot = room and room:FindFirstChild("DecorSlot_" .. n, true)
	if slot and slot:IsA("BasePart") then
		return slot
	end
	return nil
end

local function decorFolder(plot: Plot): Instance
	return plot.Model:FindFirstChild("Decor") :: Instance
end

local function removeDecorModel(plot: Plot, slotKey: string)
	for _, child in decorFolder(plot):GetChildren() do
		if child:GetAttribute("SlotKey") == slotKey then
			child:Destroy()
		end
	end
end

local function showDecor(plot: Plot, slotKey: string, decorId: string)
	local slot = Plots.decorSlot(plot, slotKey)
	if not slot or not knownDecor(decorId) then
		return
	end
	removeDecorModel(plot, slotKey)
	local ok, model = pcall(DecorBuilder.build, decorId)
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		warn("[Plots] DecorBuilder.build failed for", decorId, model)
		return
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	model:SetAttribute("SlotKey", slotKey)
	model:SetAttribute("DecorId", decorId)
	-- Decor models are pivoted at their bottom centre; DecorSlot parts rest on the floor.
	model:PivotTo(slot.CFrame * CFrame.new(0, -slot.Size.Y / 2, 0))
	model.Parent = decorFolder(plot)
end

-- Rebuilds the placed decor whose slot exists (e.g. after a room appears).
local function showPlacedDecor(plot: Plot, data: Types.Data, onlyRoom: string?)
	for slotKey, decorId in data.Decor.Placed do
		local roomId = string.match(slotKey, "^(%w+):")
		if (onlyRoom == nil or roomId == onlyRoom) and data.Decor.Owned[decorId] then
			showDecor(plot, slotKey, decorId)
		end
	end
end

local function addRoom(plot: Plot, roomId: string): Model?
	local ok, model = pcall(PlotBuilder.placeRoom, plot.Model, roomId)
	if not ok then
		warn("[Plots] Could not build", roomId, model)
		return nil
	end
	if model then
		Plots.RoomAdded:Fire(plot, roomId, model)
	end
	return model
end

------------------------------------------------------------------------------------------------------------------
-- Assigning and releasing
------------------------------------------------------------------------------------------------------------------

local function freePlot(): Plot?
	for _, index in ASSIGN_ORDER do
		local plot = plots[index]
		if plot and not plot.Owner then
			return plot
		end
	end
	for _, plot in plots do
		if not plot.Owner then
			return plot
		end
	end
	return nil
end

local function assign(player: Player, plot: Plot)
	local data = PlayerData.get(player)
	if not data then
		return
	end
	plot.Owner = player
	byPlayer[player] = plot
	local index = table.find(waiting, player)
	if index then
		table.remove(waiting, index)
	end

	plot.Model:SetAttribute("OwnerUserId", player.UserId)
	plot.Model:SetAttribute("OpenHelpers", false)
	plot.Model:SetAttribute("Hearts", 0)
	setSign(plot, player)
	player:SetAttribute("PlotIndex", plot.Index)

	for _, roomId in Rooms.Order do
		if data.Rooms[roomId] and roomId ~= "Stand" then
			addRoom(plot, roomId)
		end
	end
	refreshPreviews(plot, data)
	showPlacedDecor(plot, data, nil)

	Plots.PlotAssigned:Fire(player, plot)
	sendHome(player, plot)
	Remotes.toast(player, "🏥 This is your clinic!")
end

local function tryAssign(player: Player)
	if byPlayer[player] or player.Parent ~= Players then
		return
	end
	local plot = freePlot()
	if plot then
		assign(player, plot)
	else
		if not table.find(waiting, player) then
			table.insert(waiting, player)
		end
		Remotes.toast(player, "All clinics full! Visit and help 💛")
	end
end

local function release(player: Player)
	local index = table.find(waiting, player)
	if index then
		table.remove(waiting, index)
	end
	local plot = byPlayer[player]
	if not plot then
		return
	end
	byPlayer[player] = nil

	-- Handlers run first and can still read plot.Owner (= player) before the plot is cleared.
	Plots.PlotReleased:Fire(player, plot)

	plot.Owner = nil
	PlotBuilder.clearPlot(plot.Model)
	plot.Model:SetAttribute("OwnerUserId", 0)
	plot.Model:SetAttribute("OpenHelpers", false)
	plot.Model:SetAttribute("Hearts", 0)
	setSign(plot, nil)
	refreshPreviews(plot, nil)
	if player.Parent == Players then
		player:SetAttribute("PlotIndex", nil)
	end

	-- The first player still waiting gets the freed plot.
	for _, waiter in table.clone(waiting) do
		if waiter.Parent == Players and PlayerData.get(waiter) then
			assign(waiter, plot)
			return
		end
	end
end

------------------------------------------------------------------------------------------------------------------
-- Friends (cached at join; IsFriendsWith is a web call)
------------------------------------------------------------------------------------------------------------------

local function setFriends(a: Player, b: Player, value: boolean)
	friends[a] = friends[a] or {}
	friends[b] = friends[b] or {}
	friends[a][b] = value
	friends[b][a] = value
end

local function cacheFriends(player: Player)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			task.spawn(function()
				local ok, isFriend = pcall(player.IsFriendsWith, player, other.UserId)
				if ok and player.Parent == Players and other.Parent == Players then
					setFriends(player, other, isFriend == true)
				end
			end)
		end
	end
end

------------------------------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------------------------------

function Plots.getPlot(player: Player): Plot?
	return byPlayer[player]
end

function Plots.ownerOf(plotModel: Model): Player?
	local plot = byModel[plotModel]
	return plot and plot.Owner
end

function Plots.all(): { Plot }
	return plots
end

function Plots.fromInstance(instance: Instance): Plot?
	local current: Instance? = instance
	while current and current ~= Workspace do
		if current:IsA("Model") and byModel[current] then
			return byModel[current]
		end
		current = current.Parent
	end
	return nil
end

function Plots.canWork(player: Player, plot: Plot): boolean
	local owner = plot and plot.Owner
	if not owner then
		return false
	end
	if player == owner or plot.Model:GetAttribute("OpenHelpers") == true then
		return true
	end
	local ownerFriends = friends[owner]
	return ownerFriends ~= nil and ownerFriends[player] == true
end

function Plots.unlockRoom(owner: Player, roomId: string): boolean
	if not knownRoom(roomId) then
		return false
	end
	local data = PlayerData.get(owner)
	if not data or data.Rooms[roomId] then
		return false
	end
	local saved = PlayerData.update(owner, function(d)
		d.Rooms[roomId] = true
	end)
	if not saved then
		return false -- the owner's save is closing (they're leaving): nothing changed
	end
	local plot = byPlayer[owner]
	if plot then
		addRoom(plot, roomId)
		refreshPreviews(plot, data)
		showPlacedDecor(plot, data, roomId)
	end
	return true
end

function Plots.placeDecor(owner: Player, slotKey: string, decorId: string?): boolean
	if type(slotKey) ~= "string" or (decorId ~= nil and not knownDecor(decorId)) then
		return false
	end
	local data = PlayerData.get(owner)
	local plot = byPlayer[owner]
	if not data or not plot or not Plots.decorSlot(plot, slotKey) then
		return false
	end
	if decorId and not data.Decor.Owned[decorId] then
		return false
	end

	-- Each decor item exists once: placing it somewhere new moves it.
	local movedFrom: { string } = {}
	local saved = PlayerData.update(owner, function(d)
		if decorId then
			for key, placed in d.Decor.Placed do
				if placed == decorId and key ~= slotKey then
					d.Decor.Placed[key] = nil
					table.insert(movedFrom, key)
				end
			end
		end
		d.Decor.Placed[slotKey] = decorId
	end)
	if not saved then
		return false
	end

	for _, key in movedFrom do
		removeDecorModel(plot, key)
	end
	if decorId then
		showDecor(plot, slotKey, decorId)
	else
		removeDecorModel(plot, slotKey)
	end
	return true
end

function Plots.observeRooms(fn: (Plot, string, Model) -> ()): Signal.Connection
	for _, plot in plots do
		local roomsFolder = plot.Model:FindFirstChild("Rooms")
		if roomsFolder then
			for _, room in roomsFolder:GetChildren() do
				local roomId = room:GetAttribute("RoomId")
				if room:IsA("Model") and type(roomId) == "string" then
					task.spawn(fn, plot, roomId, room)
				end
			end
		end
	end
	return Plots.RoomAdded:Connect(fn)
end

function Plots.start()
	for index, model in PlotBuilder.buildTown() do
		local plot: Plot = {
			Index = index,
			Model = model,
			Owner = nil,
			Counter = findPart(model, "Counter"),
			QueueStart = findPart(model, "QueueStart"),
			Spawn = findPart(model, "PatientSpawn"),
			Exit = findPart(model, "PatientExit"),
		}
		plots[index] = plot
		byModel[model] = plot
		setSign(plot, nil)
	end

	local townSpawn = Workspace:FindFirstChild("TownSpawn")

	local function onJoin(player: Player)
		if townSpawn and townSpawn:IsA("SpawnLocation") then
			player.RespawnLocation = townSpawn
		end
		cacheFriends(player)
		player.CharacterAdded:Connect(function(character)
			local plot = byPlayer[player]
			if plot then
				character:WaitForChild("HumanoidRootPart", 5)
				task.defer(sendHome, player, plot)
			end
		end)
		task.spawn(function()
			if PlayerData.waitLoaded(player) then
				tryAssign(player)
			end
		end)
	end

	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		onJoin(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		release(player)
		friends[player] = nil
		for _, list in friends do
			list[player] = nil
		end
	end)
end

return Plots
