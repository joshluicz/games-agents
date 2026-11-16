--!strict
-- The glass lift between the hospital's floors (Progression v2 build plan §B3/§B4/§B8; design §6). Server only.
-- OWNER: T6. The car moves only on clients (UI/LiftPanel); the server writes one PivotTo per rider at the destination
-- landing, never a CFrame every frame.
--
-- STUB (T6): the Foundation's safe defaults, so everything requires and boots. Until T6 lands, RideLift answers
-- "Coming soon!" (Shared/Remotes' default).
--
--   Lift.start()                                 wires RideLift
--   Lift.ride(p, floor): (ok, message)           §B3 RideLift's checks, then the character's PivotTo to that landing
--                                                after Config.Lift.RideSeconds x the ExpressLift factor
--   Lift.carry(plot, models: { Model }, floor): boolean   yields RideSeconds, then one PivotTo each at the landing
--                                                (Patients and porters use it). Default: false (nothing moves)
--   Lift.landing(plot, floor): CFrame?           that floor's landing (Building.Landing_0, Floor_<n>.Landing)
--   Lift.waitEscort(plot, seconds): Player?      enables the ground landing's EscortPrompt and yields until a player
--                                                who can work the plot triggers it, or the time runs out. Default:
--                                                nil at once (the patient rides alone)
-- Requires Plots and PlotBuilder; never Patients or Nurses.

local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Remotes)

local Lift = {}

-- STUB (T6)
function Lift.ride(_player: Player, _floor: number): (boolean, string)
	return false, Remotes.SOON
end

-- STUB (T6)
function Lift.carry(_plot: any, _models: { Model }, _floor: number): boolean
	return false
end

-- STUB (T6)
function Lift.landing(_plot: any, _floor: number): CFrame?
	return nil
end

-- STUB (T6)
function Lift.waitEscort(_plot: any, _seconds: number): Player?
	return nil
end

function Lift.start() end

return Lift
