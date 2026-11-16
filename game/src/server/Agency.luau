--!strict
-- The Nurse Agency kiosk: restocks, buys and the sell-back (Progression v2 build plan §B3.1/§B4/§B8; design §8,
-- memory-20261116-018). Server only. OWNER: T3. The rules are Logic/Agency (Lune-tested). No countdown anywhere
-- (§E9), the odds are on show, and a confirm comes before every buy and sell.
--
-- STUB (T3): the Foundation's safe defaults, so everything requires and boots. Until T3 lands, GetAgency, AgencyBuy
-- and SellNurse answer "Coming soon!" (Shared/Remotes' default) and there is no kiosk.
--
--   Agency.start()                   the kiosk (Workspace.NurseAgency), restocks on uptime (Workspace attribute
--                                    AgencyRestock), GetAgency, AgencyBuy, SellNurse, AgencyNews
--   Agency.view(p): AgencyView       what this player sees now (their prices, their bought slots, Lucky Stock)
--   Agency.buy(p, slot, nurseId, expect): (ok, message)    §B3.1, in that order; Nurses.grant(.., "Agency")
--   Agency.sell(p, nurseId, expect): (ok, message)         §B3.1; Nurses.take(.., "Sold")
--   Agency.restockNow(): (ok, message)   Admin "RefillAgency": a new restock now (it counts as a new index)
--   Agency.Pure                      the pure helpers between the PURE markers (a spec loads that block)
-- Requires Nurses and PlayerData; never Market. No module requires Agency (but Admin).

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local AgencyLogic = require(Shared.Logic.Agency)

local Agency = {}

------------------------------------------------------------------------------------------------------------------
-- Pure helpers (no Roblox services, no upvalues: tests/AgencyServer.spec loads this block on its own)
------------------------------------------------------------------------------------------------------------------

-- PURE-BEGIN
local Pure = {}
-- PURE-END

Agency.Pure = Pure

-- STUB (T3)
function Agency.view(_player: Player): Types.AgencyView
	return { Restock = 0, Slots = {}, Odds = AgencyLogic.odds(Config), SellBack = {} }
end

-- STUB (T3)
function Agency.buy(_player: Player, _slot: number, _nurseId: string, _expect: number): (boolean, string)
	return false, Remotes.SOON
end

-- STUB (T3)
function Agency.sell(_player: Player, _nurseId: string, _expect: number): (boolean, string)
	return false, Remotes.SOON
end

-- STUB (T3)
function Agency.restockNow(): (boolean, string)
	return false, Remotes.SOON
end

function Agency.start() end

return Agency
