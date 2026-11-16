--!strict
-- STUB (Task 0). Owned by Task 5: replace with the real Day Report (build plan §B5).
--   DayReport.record(p, ctx, newPage, stars) · DayReport.flush()  (DayNight calls flush at night's end)

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)

local DayReport = {}

function DayReport.record(_player: Player, _ctx: Types.CureCtx, _newPage: boolean, _stars: number) end

function DayReport.flush() end

function DayReport.start() end

return DayReport
