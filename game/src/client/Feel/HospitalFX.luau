--!strict
-- Hospital v2's effects on this client (Progression v2 build plan §B4/§C T8). OWNER: T8.
--   init(ctx)   the ambulance's lights and siren (its ArriveAt attribute; calm mode: soft lights only), the
--               client-only helicopter in and out of HeliSpot (one tween, <= 15 parts), ability sparkles on AbilityAt,
--               the lift's ding for others' rides nearby and the theme grow-in on GrewAt. Everything sleeps when
--               nothing happens and honours Kit.reducedMotion().
--
-- STUB (T8): the Foundation's empty module, so Main.client loads it and nothing else has to wait for it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local HospitalFX = {}

function HospitalFX.init(_ctx: Types.Ctx) end

return HospitalFX
