--!strict
-- The Player Market (same server only): listings, buys and the fee (Progression v2 build plan §B3.2/§B4/§B8; design
-- §8, memory-20261116-018/-019). Server only. OWNER: T4. The rules are Logic/Market (Lune-tested). No free text, no
-- swaps, no haggling; a confirm before every list and buy; a listing is only a lock (the nurse never leaves the
-- seller's save until it's sold), so a crash ends every listing with nothing to restore.
--
-- STUB (T4): the Foundation's safe defaults, so everything requires and boots. Until T4 lands, GetMarket, ListNurse,
-- Unlist and BuyListing answer "Coming soon!" (Shared/Remotes' default) and there is no kiosk.
--
--   Market.start()                   the kiosk (Workspace.PlayerMarket), GetMarket, ListNurse, Unlist, BuyListing,
--                                    MarketNews (debounced 0.5 s), listings removed on PlayerRemoving
--   Market.view(): MarketView        every listing, the fee in percent, the per-seller cap
--   Market.list(p, nurseId, price): (ok, message)      §B3.2, in that order
--   Market.unlist(p, id): (ok, message)                your own listing only
--   Market.buy(p, id, price): (ok, message)            §B3.2: every check, then the transfer, with no yield;
--                                                      Nurses.take (seller) then Nurses.give (buyer); saveNow seller
--                                                      THEN buyer
--   Market.Sold: Signal (listing, buyer)
--   Market.Pure                      the pure helpers between the PURE markers (a spec loads that block)
-- Requires Nurses and PlayerData; never Agency. No module requires Market (but Admin).

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)

local Market = {}

Market.Sold = Signal.new()

------------------------------------------------------------------------------------------------------------------
-- Pure helpers (no Roblox services, no upvalues: tests/MarketServer.spec loads this block on its own)
------------------------------------------------------------------------------------------------------------------

-- PURE-BEGIN
local Pure = {}
-- PURE-END

Market.Pure = Pure

-- STUB (T4)
function Market.view(): Types.MarketView
	return {
		Listings = {},
		FeePercent = math.floor(Config.Market.Fee * 100 + 0.5),
		MaxPerSeller = Config.Market.MaxPerSeller,
	}
end

-- STUB (T4)
function Market.list(_player: Player, _nurseId: string, _price: number): (boolean, string)
	return false, Remotes.SOON
end

-- STUB (T4)
function Market.unlist(_player: Player, _id: number): (boolean, string)
	return false, Remotes.SOON
end

-- STUB (T4)
function Market.buy(_player: Player, _id: number, _price: number): (boolean, string)
	return false, Remotes.SOON
end

function Market.start() end

return Market
