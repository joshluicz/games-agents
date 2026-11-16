--!strict
-- The 🛗 lift's floor picker (Progression v2 build plan §B3/§B4/§B9, §C T6). OWNER: T6.
--   init(ctx)   a LiftPrompt's client Triggered fires ctx.fire("Open", "Lift", floors) and opens big floor buttons
--               ("🛎️ G", "🛏️ 1", "🛁 2", "💊 3", "🚁 R"; only this building's floors); asks RideLift(floor), then slides
--               the car, plays the Ding and eases the camera on THIS client only (instant with reduced motion).
--
-- STUB (T6): the Foundation's empty module, so Main.client loads it and nothing else has to wait for it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local LiftPanel = {}

function LiftPanel.init(_ctx: Types.Ctx) end

return LiftPanel
