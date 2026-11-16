--!strict
-- The Nurse Belt, as each player sees it (depth-update design §2, build plan §B4/§B9). OWNER: T4.
--   init(ctx)   watches Workspace.NurseBelt.Riders; listens for "Shout"; watches Workspace GoldenHour,
--               GoldenStartsAt, GoldenEndsAt and NightRush; fires "Banner" (Types.BannerSpec)
-- What T4 builds:
--   · Smooth riders: every frame, each rider's Root goes to BeltStart:Lerp(BeltEnd, Logic/Belt.alpha(StartAt,
--     Workspace:GetServerTimeNow(), RideSeconds)) locally (the server only moves it once a second).
--   · A tappable billboard per rider (a BillboardGui in PlayerGui, Adornee = its Root, so it takes taps): the rarity
--     frame (Kit.rarityFrame), the role icon, its level-1 stat (Logic/Nurse.stats), the price for THIS viewer
--     (Logic/Belt.price(ctx.Config, rarity, State.Level)) and a Hire button (Hud.ask(ctx.Remotes.HireNurse, RiderId)).
--     Also set the rider's HirePrompt.ObjectText locally to that price. Hired riders show ✅ and no button.
--   · Banners: Golden Hour (a countdown to GoldenEndsAt while it runs), Night Rush (on IsNight/NightRush), an Epic+
--     arrival from "Shout". No banners while the first-session tutorial runs (State.Tutorial 1..8).
-- Cash only, odds on the sign, nothing pressures a kid (red line 3): no "hurry" words, no flashing prices.
--
-- FOUNDATION STUB: nothing yet (the server stub builds no belt).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local BeltView = {}

function BeltView.init(_ctx: Types.Ctx) end

return BeltView
