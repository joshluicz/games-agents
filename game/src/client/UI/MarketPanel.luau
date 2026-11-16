--!strict
-- The 🏷️ Player Market panel (Progression v2 build plan §B3.2/§B9, §C T4). OWNER: T4.
--   init(ctx)   opens on ctx.fire("Open", "Market") (the kiosk's prompt, NursePanel's 🏷️ button) and on the bus
--               "List" (nurseId) (the list flow); listens to the bus "MarketNews" (view). Buy and Sell tabs, your
--               listings with Unlist, "🏷️ Only this server" and "No swaps. No chat." badges, a confirm before every
--               buy and list. Asks GetMarket, ListNurse(nurseId, price), Unlist(id) and BuyListing(id, price).
--
-- STUB (T4): the Foundation's empty module, so Main.client loads it and nothing else has to wait for it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local MarketPanel = {}

function MarketPanel.init(_ctx: Types.Ctx) end

return MarketPanel
