--!strict
-- STUB (Task 0). Owned by Task 3: replace with the real economy (build plan §B5). Keep toast and toastAll:
-- DayNight and other modules use them.
--   Economy.addCash(p, n) · Economy.spendCash(p, n): boolean · Economy.level(p, upgradeId): number
--   Economy.purchase(p, kind, id): (boolean, string)   rooms call Plots.unlockRoom
--   Economy.toast(p, text) · Economy.toastAll(text)
--   start() wires the Purchase and PlaceDecor remotes

local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Remotes)
local PlayerData = require(script.Parent.PlayerData)

local Economy = {}

function Economy.addCash(player: Player, amount: number)
	PlayerData.update(player, function(data)
		data.Cash += amount
	end)
end

function Economy.spendCash(player: Player, amount: number): boolean
	local data = PlayerData.get(player)
	if not data or data.Cash < amount then
		return false
	end
	PlayerData.update(player, function(d)
		d.Cash -= amount
	end)
	return true
end

function Economy.level(player: Player, upgradeId: string): number
	local data = PlayerData.get(player)
	return if data then data.Upgrades[upgradeId] or 0 else 0
end

function Economy.purchase(_player: Player, _kind: string, _id: string): (boolean, string)
	return false, "Coming soon!"
end

function Economy.toast(player: Player, text: string)
	Remotes.toast(player, text)
end

function Economy.toastAll(text: string)
	Remotes.toastAll(text)
end

function Economy.start()
	Remotes.serve("Purchase", function()
		return false, "Coming soon!"
	end)
	Remotes.serve("PlaceDecor", function()
		return false, "Coming soon!"
	end)
end

return Economy
