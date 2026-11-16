--!strict
-- STUB (Task 0). Owned by Task 3: replace with the real cure resolution (build plan §B5).
--   Cure.resolve(ctx: Types.CureCtx)
-- The real one calls, in order: Pay.reward, Economy.addCash(helper), Progress.addStars(owner), Book.stamp(helper),
-- Daily.onCure(helper, ctx), Story.onCure(owner, regular), DayReport.record(...), then fires Cured to the helper
-- (and to the owner if different).

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)

local Cure = {}

function Cure.resolve(_ctx: Types.CureCtx) end

function Cure.start() end

return Cure
