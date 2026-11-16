--!strict
-- STUB (Task 0). Owned by Task 3: replace with the real progress (build plan §B5).
--   Progress.addStars(p, n) · Progress.nextGoal(p): { Kind, Id, Icon }

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)

local Progress = {}

function Progress.addStars(_player: Player, _amount: number) end

function Progress.nextGoal(_player: Player): Types.NextGoal
	return { Kind = "None", Id = "", Icon = "⭐" }
end

function Progress.start() end

return Progress
