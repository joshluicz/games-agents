--!strict
-- The 🏢 Nurse Agency panel (Progression v2 build plan §B3.1/§B9, §C T3). OWNER: T3.
--   init(ctx)   opens on ctx.fire("Open", "Agency") (the kiosk's prompt, NursePanel's 🏢 button) and on the bus
--               "Sell" (nurseId) (NursePanel's Sell button: the sell confirm, a 1 s hold for Epic+); listens to the bus
--               "AgencyNews" (view). Shows the 4 (6 with 🍀 Lucky Stock) nurse cards with YOUR price, the 🎲 odds
--               (70 / 26 / 4, "never Legendary+"), "🔄 New nurses every 5 min" with no clock (§E9), and a Sell tab.
--               Asks GetAgency, AgencyBuy(slot, nurseId, expect) and SellNurse(nurseId, expect).
--
-- STUB (T3): the Foundation's empty module, so Main.client loads it and nothing else has to wait for it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local AgencyPanel = {}

function AgencyPanel.init(_ctx: Types.Ctx) end

return AgencyPanel
