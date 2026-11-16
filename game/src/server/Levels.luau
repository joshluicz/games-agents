--!strict
-- Hospital levels: the building grows (depth-update design §3, build plan §B8). Server only. OWNER: T5.
-- FOUNDATION STUB: the reads are real (the save and Data/Levels), so Patients and Nurses can use them today;
-- levelUp, the Building and the celebration are T5's to build.
--
--   Levels.start()                       wires LevelUp; builds each plot's Building (PlotBuilder.buildBuilding) on
--                                        PlotAssigned and after a level-up; keeps the plot's Level attribute
--   Levels.level(p): number              the player's hospital level (1 until their data loads)
--   Levels.levelUp(p): (ok, message)     Logic/Levels.canLevelUp, then spend the cash and set Data.Level in ONE
--                                        PlayerData.update; Economy.Purchased:Fire(p, "Level", tostring(level));
--                                        the Celebrate remote ({ Kind = "LevelUp", ... }); LevelChanged
--   Levels.slots(p) · Levels.queueCap(p) · Levels.recipeCap(p) · Levels.beds(p)   numbers from Data/Levels
--   Levels.LevelChanged                  signal (p, level, previous)
-- ⭐ is a gate (needed, not spent) and 💰 is spent (build plan §B5, open point §E1).

local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local LevelsData = require(Shared.Data.Levels)
local LevelsLogic = require(Shared.Logic.Levels)
local PlayerData = require(script.Parent.PlayerData)

local Levels = {}

Levels.LevelChanged = Signal.new()

function Levels.level(player: Player): number
	local data = PlayerData.get(player)
	return if data then LevelsLogic.clamp(LevelsData, data.Level) else 1
end

function Levels.slots(player: Player): number
	return LevelsLogic.slots(LevelsData, Levels.level(player))
end

function Levels.queueCap(player: Player): number
	return LevelsLogic.queue(LevelsData, Levels.level(player))
end

function Levels.recipeCap(player: Player): number
	return LevelsLogic.recipeCap(LevelsData, Levels.level(player))
end

function Levels.beds(player: Player): number
	return LevelsLogic.beds(LevelsData, Levels.level(player))
end

function Levels.levelUp(_player: Player): (boolean, string)
	return false, Remotes.SOON -- T5
end

function Levels.start()
	Remotes.serve("LevelUp", function(player: Player)
		return Levels.levelUp(player)
	end)
end

return Levels
