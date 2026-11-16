--!strict
-- Cash, upgrades and the shop (build plan §B5). Server only: the client asks, the server decides.
--   Economy.addCash(p, n): boolean          adds a whole amount > 0 (fractions round down)
--   Economy.spendCash(p, n): boolean        takes n (fractions round up) only if the player has it all
--   Economy.charge(p, n, apply): boolean    takes n and runs apply(data) in ONE PlayerData.update (no yield
--                                           between), only if the player has it all. Server/Levels' level-up uses it
--   Economy.level(p, upgradeId): number     the player's upgrade level (0 if unknown or not loaded)
--   Economy.purchase(p, kind, id): (ok, message)   kind "Upgrade" | "Room" | "Decor"; validates everything. A room
--                                           also needs its hospital level (Rooms.Level: the Garden needs Lv 3),
--                                           checked by Logic/Progress.canBuyRoom from the save's Level
--   Economy.placeDecor(p, slotKey, decorId?): (ok, message)   the PlaceDecor request; nil decorId puts it away
--   Economy.toast(p, text) · Economy.toastAll(text)
--   Economy.Purchased                       signal (p, kind, id) after a purchase lands (Carry can watch Tray);
--                                           kind "Level" with id "<new level>" comes from Server/Levels
--   start() wires the Purchase and PlaceDecor remotes (LevelUp is Server/Levels')
--
-- Security (roblox-networking): Remotes.serve rate-limits each remote (Config.RemoteRatePerSecond per player)
-- and pcalls the handler. Here every argument is checked cheapest first: type and length, a known id (rawget,
-- so the Data maps' `Order` list is never an id), loaded data, plot ownership, then the price. Prices come from
-- Shared/Data only, never from the client. Charging and granting happen in one PlayerData.update with no yield
-- in between, so a save never holds one without the other, and a second request can't pass the same check.
-- Replies are short (6 words or fewer) so the Shop can show them as they are.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)
local Rooms = require(Shared.Data.Rooms)
local Upgrades = require(Shared.Data.Upgrades)
local Decor = require(Shared.Data.Decor)
local Prices = require(Shared.Logic.Prices)
local ProgressLogic = require(Shared.Logic.Progress)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)

local Economy = {}

Economy.Purchased = Signal.new()

local MAX_ID_LENGTH = 40 -- longer than any id in Shared/Data
local MAX_CASH = 1e15 -- far below 2^53, where whole numbers stop being exact
local JUNK_WARN_AT = 20 -- malformed requests per player per minute before one warning
local JUNK_WINDOW_SECONDS = 60

local MSG = table.freeze({
	NotFound = "Not in the shop!",
	Loading = "Still loading! Try again.",
	NoPlot = "Wait for a free clinic!",
	Busy = "One at a time!",
	Maxed = "Maxed out! 🎉",
	Owned = "Already yours!",
	EarnedOnly = "Earn this one by playing!",
	BadSlot = "Can't go there!",
	RoomLocked = "Unlock that room first!",
	NotOwned = "Buy it first!",
	PutAway = "📦 Put away!",
	Oops = Remotes.OOPS,
})

local KINDS: { [string]: boolean } = { Upgrade = true, Room = true, Decor = true }

local busy: { [Player]: boolean } = {}
local junk: { [Player]: { Count: number, Since: number, Warned: boolean } } = {}

------------------------------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------------------------------

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function validId(value: any): boolean
	return type(value) == "string" and #value > 0 and #value <= MAX_ID_LENGTH
end

local function isWinter(): boolean
	return Workspace:GetAttribute("IsWinter") == true
end

local function needCash(price: number): string
	return "Need " .. ProgressLogic.CASH_ICON .. price
end

-- Malformed requests (wrong types, unknown ids) are an abuse signal. Count them and warn once per window,
-- never once per packet. Normal "no" answers (not enough cash, locked) are not counted.
local function rejectJunk(player: Player, why: string): (boolean, string)
	local now = os.clock()
	local entry = junk[player]
	if not entry or now - entry.Since > JUNK_WINDOW_SECONDS then
		entry = { Count = 0, Since = now, Warned = false }
		junk[player] = entry
	end
	entry.Count += 1
	if entry.Count >= JUNK_WARN_AT and not entry.Warned then
		entry.Warned = true
		warn(
			("[Economy] %d malformed shop requests from %d in %ds (last: %s)"):format(
				entry.Count,
				player.UserId,
				JUNK_WINDOW_SECONDS,
				why
			)
		)
	end
	return false, if why == "slot" then MSG.BadSlot else MSG.NotFound
end

-- Charges `price` and applies the purchase in ONE update. False if the player can't afford it.
local function charge(player: Player, price: number, apply: (Types.Data) -> ()): boolean
	local data = PlayerData.get(player)
	if not data or data.Cash < price then
		return false
	end
	return PlayerData.update(player, function(d)
		d.Cash -= price
		apply(d)
	end)
end

-- The same, for other server systems (Server/Levels): a whole price >= 0 (fractions round up).
function Economy.charge(player: Player, price: number, apply: (Types.Data) -> ()): boolean
	if not isPlayer(player) or not finite(price) or price < 0 or type(apply) ~= "function" then
		return false
	end
	return charge(player, math.ceil(price), apply)
end

------------------------------------------------------------------------------------------------------------------
-- Cash
------------------------------------------------------------------------------------------------------------------

function Economy.addCash(player: Player, amount: number): boolean
	if not isPlayer(player) or not finite(amount) then
		return false
	end
	local whole = math.floor(amount)
	if whole <= 0 then
		return false
	end
	return PlayerData.update(player, function(d)
		d.Cash = math.min(MAX_CASH, d.Cash + whole)
	end)
end

function Economy.spendCash(player: Player, amount: number): boolean
	if not isPlayer(player) or not finite(amount) or amount < 0 then
		return false
	end
	local whole = math.ceil(amount)
	local data = PlayerData.get(player)
	if not data or data.Cash < whole then
		return false
	end
	if whole == 0 then
		return true
	end
	return PlayerData.update(player, function(d)
		d.Cash -= whole
	end)
end

function Economy.level(player: Player, upgradeId: string): number
	local data = if isPlayer(player) then PlayerData.get(player) else nil
	if not data or type(upgradeId) ~= "string" then
		return 0
	end
	local level = data.Upgrades[upgradeId]
	return if finite(level) then level else 0
end

------------------------------------------------------------------------------------------------------------------
-- Purchases
------------------------------------------------------------------------------------------------------------------

local function buyUpgrade(player: Player, data: Types.Data, id: string): (boolean, string)
	local upgrade = rawget(Upgrades :: any, id)
	if type(upgrade) ~= "table" then
		return rejectJunk(player, "upgrade " .. id)
	end
	local level = Economy.level(player, id)
	local price = Prices.upgradePrice(Upgrades, id, level)
	if price == nil then
		return false, MSG.Maxed
	end
	if data.Cash < price then
		return false, needCash(price)
	end
	local nextLevel = level + 1
	if not charge(player, price, function(d)
		d.Upgrades[id] = nextLevel
	end) then
		return false, needCash(price)
	end
	Economy.Purchased:Fire(player, "Upgrade", id)
	return true, upgrade.Icon .. " Level " .. nextLevel .. "!"
end

local function buyRoom(player: Player, data: Types.Data, id: string): (boolean, string)
	local room = rawget(Rooms :: any, id)
	if type(room) ~= "table" then
		return rejectJunk(player, "room " .. id)
	end
	-- Rooms are built on your own plot, so a player without one (all 6 taken) can't buy them yet.
	if not Plots.getPlot(player) then
		return false, MSG.NoPlot
	end
	-- Owned, season, hospital level (room.Level vs data.Level: "Needs 🏥 Lv 3"), ⭐ gate, then cash.
	local ok, message = ProgressLogic.canBuyRoom(data, room, id, isWinter())
	if not ok then
		return false, message
	end
	local price: number = room.Price
	if not Economy.spendCash(player, price) then
		return false, needCash(price)
	end
	-- Plots.unlockRoom sets Data.Rooms[id] and builds the room. No yield since the spend, so nothing else
	-- can see the cash gone without the room. If it fails (or errors) before owning the room, refund.
	local built, result = pcall(Plots.unlockRoom, player, id)
	if not built then
		warn("[Economy] Plots.unlockRoom errored for", id, result)
	end
	local after = PlayerData.get(player)
	if not (after and after.Rooms[id] == true) then
		Economy.addCash(player, price)
		return false, MSG.Oops
	end
	Economy.Purchased:Fire(player, "Room", id)
	return true, room.Icon .. " " .. room.Name .. " open!"
end

local function buyDecor(player: Player, data: Types.Data, id: string): (boolean, string)
	local decor = rawget(Decor :: any, id)
	if type(decor) ~= "table" then
		return rejectJunk(player, "decor " .. id)
	end
	if data.Decor.Owned[id] then
		return false, MSG.Owned
	end
	local price = decor.Price
	if not finite(price) or price < 0 then
		return false, MSG.EarnedOnly -- Price nil: earned from the Book, a story or a referral
	end
	if not charge(player, price, function(d)
		d.Decor.Owned[id] = true
	end) then
		return false, needCash(price)
	end
	Economy.Purchased:Fire(player, "Decor", id)
	return true, decor.Icon .. " Yours! Now place it!"
end

local BUYERS: { [string]: (Player, Types.Data, string) -> (boolean, string) } = {
	Upgrade = buyUpgrade,
	Room = buyRoom,
	Decor = buyDecor,
}

-- Arguments are untrusted: this is the Purchase remote's handler as well as a server API.
function Economy.purchase(player: Player, kind: any, id: any): (boolean, string)
	if not isPlayer(player) then
		return false, MSG.Oops
	end
	if type(kind) ~= "string" or not KINDS[kind] then
		return rejectJunk(player, "kind")
	end
	if not validId(id) then
		return rejectJunk(player, "id")
	end
	local data = PlayerData.get(player)
	if not data then
		return false, MSG.Loading
	end
	-- Nothing below yields today, but claim the player before any work so a future yield can't let two
	-- purchases pass one balance check (roblox-networking: claim before the first yield).
	if busy[player] then
		return false, MSG.Busy
	end
	busy[player] = true
	local ran, ok, message = pcall(BUYERS[kind], player, data, id)
	busy[player] = nil
	if not ran then
		warn("[Economy] purchase failed:", kind, id, ok)
		return false, MSG.Oops
	end
	return ok, message
end

------------------------------------------------------------------------------------------------------------------
-- Decor placement
------------------------------------------------------------------------------------------------------------------

-- Arguments are untrusted: this is the PlaceDecor remote's handler.
function Economy.placeDecor(player: Player, slotKey: any, decorId: any): (boolean, string)
	if not isPlayer(player) then
		return false, MSG.Oops
	end
	-- A known room, a slot number that room has, written canonically ("Stand:1"). Tested in Progress.spec.
	local roomId = ProgressLogic.parseSlotKey(Rooms, slotKey)
	if not roomId then
		return rejectJunk(player, "slot")
	end
	local decor = nil
	if decorId ~= nil then
		decor = if validId(decorId) then rawget(Decor :: any, decorId) else nil
		if type(decor) ~= "table" then
			return rejectJunk(player, "decor")
		end
	end

	local data = PlayerData.get(player)
	if not data then
		return false, MSG.Loading
	end
	local plot = Plots.getPlot(player)
	if not plot then
		return false, MSG.NoPlot
	end
	if not data.Rooms[roomId] then
		return false, MSG.RoomLocked
	end
	if not Plots.decorSlot(plot, slotKey) then
		return false, MSG.BadSlot
	end
	if decorId ~= nil and not data.Decor.Owned[decorId] then
		return false, MSG.NotOwned
	end

	local key: string = slotKey
	if data.Decor.Placed[key] == decorId then
		-- Already like that: answer yes without rebuilding anything.
		return true, if decor then decor.Icon .. " Placed!" else MSG.PutAway
	end
	if not Plots.placeDecor(player, key, decorId) then
		return false, MSG.BadSlot
	end
	return true, if decor then decor.Icon .. " Placed!" else MSG.PutAway
end

------------------------------------------------------------------------------------------------------------------
-- Toasts (DayNight and others use these)
------------------------------------------------------------------------------------------------------------------

function Economy.toast(player: Player, text: string)
	Remotes.toast(player, text)
end

function Economy.toastAll(text: string)
	Remotes.toastAll(text)
end

function Economy.start()
	Remotes.serve("Purchase", function(player: Player, kind: any, id: any)
		return Economy.purchase(player, kind, id)
	end)
	Remotes.serve("PlaceDecor", function(player: Player, slotKey: any, decorId: any)
		return Economy.placeDecor(player, slotKey, decorId)
	end)
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		junk[player] = nil
	end)
end

return Economy
