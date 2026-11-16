--!strict
-- The Patient Book: a page per patient, stamped on first cure, with variant stickers (build plan §B5,
-- design §5.6). Server only; the rules are in Shared/Logic/Book (Lune-tested).
--
--   Book.stamp(p, patientId, variant?): (newPage, newVariant)
--       Cure.resolve calls it for the helper. Completing a wing's set (Data/Wings) grants its SetReward decor,
--       in the same save update as the stamp, so each set reward is granted exactly once.
-- Extra:
--   Book.placeReward(p, decorId): boolean
--       puts an earned decor into the first empty decor slot on the player's plot, so a reward shows at once.
--       Story uses it too. False (and nothing changes) when there's no plot or no empty slot.
--
-- On load, any completed set whose reward is missing (say, a set grew a reward later) is granted quietly.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local BookLogic = require(Shared.Logic.Book)
local Patients = require(Shared.Data.Patients)
local Regulars = require(Shared.Data.Regulars)
local Variants = require(Shared.Data.Variants)
local Wings = require(Shared.Data.Wings)
local Decor = require(Shared.Data.Decor)
local Rooms = require(Shared.Data.Rooms)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)

local Book = {}

-- rawget: Data maps answer `.Order` through their metatable, so a plain index would accept the id "Order".
local function has(map: any, id: any): boolean
	return type(id) == "string" and rawget(map, id) ~= nil
end

-- Which wing's set each reward completes, for the toast.
local wingOfReward: { [string]: string } = {}
for _, wingId in Wings.Order do
	wingOfReward[Wings[wingId].SetReward] = wingId
end

-- Grants every completed set's missing reward into `data` (mutates it). Returns the DecorIds granted.
local function grantSetRewards(data: Types.Data): { string }
	local granted = {}
	for _, decorId in BookLogic.rewardsDue(data.Book, data.Decor.Owned, Patients, Wings) do
		if has(Decor, decorId) and not data.Decor.Owned[decorId] then
			data.Decor.Owned[decorId] = true
			table.insert(granted, decorId)
		end
	end
	return granted
end

local function celebrateSet(player: Player, decorId: string)
	local decor = Decor[decorId]
	local wingId = wingOfReward[decorId]
	local wingIcon = if wingId then Wings[wingId].Icon else "📖"
	-- e.g. "🌳 Set complete! ❤️ Heart Rug" (on-screen words stay at 6 or fewer)
	Remotes.news(player, string.format("%s Set complete! %s %s", wingIcon, decor.Icon, decor.Name))
	Book.placeReward(player, decorId)
end

------------------------------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------------------------------

function Book.stamp(player: Player, patientId: string, variant: string?): (boolean, boolean)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, false
	end
	-- Regulars use their own id as their PatientId, so they get pages too (they don't count toward sets).
	if not (has(Patients, patientId) or has(Regulars, patientId)) then
		return false, false
	end
	local sticker = if has(Variants, variant) then variant else nil

	local newPage, newVariant = false, false
	local granted: { string } = {}
	local ok = PlayerData.update(player, function(data)
		newPage, newVariant = BookLogic.stamp(data.Book, patientId, sticker)
		if newPage then
			granted = grantSetRewards(data)
		end
	end)
	if not ok then
		return false, false
	end
	for _, decorId in granted do
		celebrateSet(player, decorId)
	end
	return newPage, newVariant
end

function Book.placeReward(player: Player, decorId: string): boolean
	local data = PlayerData.get(player)
	local plot = Plots.getPlot(player)
	if not data or not plot or not data.Decor.Owned[decorId] then
		return false
	end
	for _, placed in data.Decor.Placed do
		if placed == decorId then
			return false -- already out on show
		end
	end
	for _, roomId in Rooms.Order do
		if data.Rooms[roomId] then
			for n = 1, Rooms[roomId].DecorSlots do
				local slotKey = roomId .. ":" .. n
				if data.Decor.Placed[slotKey] == nil and Plots.decorSlot(plot, slotKey) then
					return Plots.placeDecor(player, slotKey, decorId)
				end
			end
		end
	end
	return false
end

function Book.start()
	-- A completed set whose reward is missing gets it now (quietly). Idempotent: owned rewards are skipped.
	local function repair(player: Player, data: Types.Data)
		if #BookLogic.rewardsDue(data.Book, data.Decor.Owned, Patients, Wings) > 0 then
			PlayerData.update(player, function(d)
				grantSetRewards(d)
			end)
		end
	end

	PlayerData.Loaded:Connect(repair)
	for _, player in Players:GetPlayers() do
		local data = PlayerData.get(player)
		if data then
			task.spawn(repair, player, data)
		end
	end
end

return Book
