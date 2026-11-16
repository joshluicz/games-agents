--!strict
-- Creature motion on the client (depth-update design §5, build plan §B4 "creature motion contract"). OWNER: T7.
--   init(ctx)   renders every Model tagged `CreatureMotion` (patients, nurses) from its attributes, locally
-- The contract: per hop the server sets HopFrom, HopTo (CFrame), HopAt (Workspace:GetServerTimeNow()), HopSeconds,
-- HopHeight, HopSpin, HopLean; overlays ShakeAt, Tilt, and ScaleFrom/ScaleTo/ScaleAt/ScaleSeconds/ScaleStyle/
-- ScaleDir. The server writes Root.CFrame (and the final scale) once when each animation ends. This module draws
-- the in-between on RenderStepped and sleeps when nothing moves. Honour Kit.reducedMotion() (smaller arcs).
--
-- FOUNDATION STUB: nothing yet (the server still moves creatures itself until the lead applies T7's requests).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local CreatureMotion = {}

function CreatureMotion.init(_ctx: Types.Ctx) end

return CreatureMotion
