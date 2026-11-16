--!strict
-- The Player Market's rules: price bands, the fee, who may list and buy (Progression v2 build plan §B3.2/§B6/§B7;
-- design §8, memory-20261116-018/-019). Same server only. Pure: no Roblox services, no requires. `cfg` is
-- Shared/Config (cfg.Market, cfg.Belt, cfg.Nurses, cfg.Roster are read); `roster` Shared/Data/Nurses (rawget).
-- No free text, no swaps, no haggling: a listing is a nurse, its level, a price inside the band and the seller's
-- DisplayName.
--
--   Market.band(cfg, rarity, level, copies?): (min, max)
--       the belt's base price x BandMin / BandMax x (1 + LevelStep x (level - 1)), each rounded to the nearest
--       Round (10). Lv 1: Common 50-300 · Rare 200-1,200 · Epic 750-4,500 · Legendary 3,000-18,000 · Mythic
--       10,000-60,000 · Secret 25,000-150,000; Lv 10 x1.9, Lv 15 x2.4. The floor stops "your Legendary for 💰1"
--       scams; the ceiling stops cash passing between friends through a Common and a kid being overcharged. The
--       floor is also never below Market.floor(cfg, rarity, copies) (copies default 1), and max >= min
--   Market.floor(cfg, rarity, copies?): number
--       the lowest price whose payout (price - fee) is at least the Agency's sell-back for that many copies
--       (Logic/Agency.sellBack: 30% of the base price for EVERY copy), rounded UP to Round. So a seller never gets
--       less than the Agency would pay, and nothing bought on the Market can be sold back for a profit (§E14). A
--       copy is a whole level, so a levelled nurse has many copies: Common Lv 10 with 10 copies -> 💰340
--   Market.valid(price, min, max): boolean   a whole number inside [min, max]
--   Market.fee(price, cfg): number           floor(price x Fee): the cash sink; the seller gets price - fee
--   Market.canList(data, nurseId, mine, total, cfg, roster): (ok, message)
--       the seller owns it ("Hire it first!") · it isn't rebirth-only ("This one stays with you!") · mine <
--       MaxPerSeller ("3 listings max!") · total < MaxListings ("Market is full!"). A resting nurse may be listed
--       (§E2: list one to make room). The price, the listed lock, saving and the cooldown are the server's checks
--   Market.canBuy(buyer, listing, owns, cfg, roster, rebirths?): (ok, message)
--       `buyer` is the buyer's save, `listing` { NurseId, Rarity, Level, Price }, `owns` whether the buyer has that
--       nurse: not rebirth-only ("Oops! Try again.") · the belt's gates (hospital level "🏥 Lv 3", rebirths "🏢 R1"; the
--       same as Logic/Belt.gate) · no copy of it already ("You have one!", §E13) · roster room ("Roster full: sell or
--       list one") · the listing's Level within the buyer's nurse level cap ("🏢 R3 first!": a Lv 15 nurse needs R3,
--       never clamped) · cash >= Price ("Need 💰420"). `rebirths` defaults to buyer.Rebirth.Count

local Market = {}

local OOPS = "Oops! Try again."

local function num(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

local function whole(value: any, fallback: number): number
	return math.floor(num(value, fallback))
end

local function section(cfg: any, name: string): any
	return if type(cfg) == "table" and type(cfg[name]) == "table" then cfg[name] else {}
end

local function basePrice(cfg: any, rarity: string): number
	local prices = section(cfg, "Belt").Prices
	return if type(prices) == "table" then math.max(0, num(prices[rarity], 0)) else 0
end

local function roundTo(x: number, step: number): number
	return math.floor(x / step + 0.5) * step
end

local function commas(n: number): string
	local digits = tostring(math.floor(math.abs(n)))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return grouped
end

local function nurseRow(roster: any, nurseId: any): any
	if type(roster) ~= "table" or type(nurseId) ~= "string" then
		return nil
	end
	local value = rawget(roster, nurseId)
	return if type(value) == "table" then value else nil
end

function Market.fee(price: number, cfg: any): number
	local share = math.clamp(num(section(cfg, "Market").Fee, 0.1), 0, 1)
	return math.floor(math.max(0, num(price, 0)) * share)
end

-- What the Agency pays for this nurse (Logic/Agency.sellBack, repeated: no requires): 30% of the belt's base price
-- for EVERY copy.
local function sellBack(cfg: any, rarity: string, copies: any): number
	local share = math.clamp(num(section(cfg, "Agency").SellBack, 0.3), 0, 1)
	return math.floor(basePrice(cfg, rarity) * share) * math.max(1, whole(copies, 1))
end

function Market.floor(cfg: any, rarity: string, copies: number?): number
	local m = section(cfg, "Market")
	local step = math.max(1, whole(m.Round, 10))
	local back = sellBack(cfg, rarity, copies)
	local keep = 1 - math.clamp(num(m.Fee, 0.1), 0, 1)
	local need = if keep > 0 then math.max(0, math.ceil(back / keep - 1e-9)) else back
	while need - Market.fee(need, cfg) < back do -- exact with the real fee's rounding
		need += 1
	end
	return math.ceil(need / step) * step
end

function Market.band(cfg: any, rarity: string, level: number, copies: number?): (number, number)
	local m = section(cfg, "Market")
	local step = math.max(1, whole(m.Round, 10))
	local scale = 1 + math.max(0, num(m.LevelStep, 0.1)) * math.max(0, whole(level, 1) - 1)
	local base = basePrice(cfg, rarity) * scale
	local low =
		math.max(step, roundTo(base * math.max(0, num(m.BandMin, 0.5)), step), Market.floor(cfg, rarity, copies))
	local high = math.max(low, roundTo(base * math.max(0, num(m.BandMax, 3)), step))
	return low, high
end

function Market.valid(price: any, min: number, max: number): boolean
	return type(price) == "number"
		and price == price
		and price % 1 == 0
		and price >= num(min, math.huge)
		and price <= num(max, -math.huge)
end

function Market.canList(
	data: any,
	nurseId: string,
	mine: number,
	total: number,
	cfg: any,
	roster: any
): (boolean, string)
	local nurses = if type(data) == "table" and type(data.Nurses) == "table" then data.Nurses else {}
	if type(nurseId) ~= "string" or type(nurses[nurseId]) ~= "table" then
		return false, "Hire it first!"
	end
	local nurse = nurseRow(roster, nurseId)
	if not nurse then
		return false, OOPS
	end
	if nurse.Source ~= nil then
		return false, "This one stays with you!"
	end
	local m = section(cfg, "Market")
	local perSeller = math.max(0, whole(m.MaxPerSeller, 3))
	if num(mine, 0) >= perSeller then
		return false, perSeller .. " listings max!"
	end
	if num(total, 0) >= math.max(0, whole(m.MaxListings, 30)) then
		return false, "Market is full!"
	end
	return true, ""
end

-- The roster cap (Logic/Nurse.rosterCap, repeated: no requires).
local function rosterCap(cfg: any, rebirths: number): number
	local r = section(cfg, "Roster")
	local cap = whole(r.Base, 3) + whole(r.PerRebirth, 1) * math.max(0, whole(rebirths, 0))
	return math.max(0, math.min(cap, whole(r.Max, 8)))
end

-- The nurse level cap (Logic/Nurse.levelCap, repeated: no requires): MaxLevel, + LevelCapBonus from
-- LevelCapRebirths. Also returns the rebirths that raise it, for the refusal's words.
local function levelCapOf(cfg: any, rebirths: number): (number, number)
	local n = section(cfg, "Nurses")
	local cap = math.max(1, whole(n.MaxLevel, 10))
	local at = math.max(0, whole(n.LevelCapRebirths, 3))
	if whole(rebirths, 0) >= at then
		cap += math.max(0, whole(n.LevelCapBonus, 0))
	end
	return cap, at
end

-- The belt's gates (Logic/Belt.gate, repeated: no requires).
local function gate(cfg: any, rarity: string, level: number, rebirths: number): string?
	local b = section(cfg, "Belt")
	local minLevel = if type(b.MinLevel) == "table" then math.max(1, whole(b.MinLevel[rarity], 1)) else 1
	if whole(level, 1) < minLevel then
		return "🏥 Lv " .. minLevel
	end
	local minRebirths = if type(b.MinRebirths) == "table" then math.max(0, whole(b.MinRebirths[rarity], 0)) else 0
	if whole(rebirths, 0) < minRebirths then
		return "🏢 R" .. minRebirths
	end
	return nil
end

function Market.canBuy(
	buyer: any,
	listing: any,
	owns: boolean,
	cfg: any,
	roster: any,
	rebirths: number?
): (boolean, string)
	if type(buyer) ~= "table" or type(listing) ~= "table" then
		return false, OOPS
	end
	local nurse = nurseRow(roster, listing.NurseId)
	if not nurse or nurse.Source ~= nil then
		return false, OOPS
	end
	local count = if rebirths ~= nil
		then whole(rebirths, 0)
		elseif type(buyer.Rebirth) == "table" then whole(buyer.Rebirth.Count, 0)
		else 0
	local gated = gate(cfg, nurse.Rarity, whole(buyer.Level, 1), count)
	if gated then
		return false, gated
	end
	if owns then
		return false, "You have one!"
	end
	local owned = 0
	if type(buyer.Nurses) == "table" then
		for nurseId, entry in buyer.Nurses do
			if type(entry) == "table" and nurseRow(roster, nurseId) then
				owned += 1
			end
		end
	end
	if owned >= rosterCap(cfg, count) then
		return false, "Roster full: sell or list one"
	end
	local levelCap, capRebirths = levelCapOf(cfg, count)
	if whole(listing.Level, 1) > levelCap then
		return false, "🏢 R" .. capRebirths .. " first!" -- the same words as Server/Nurses.give's refusal
	end
	local price = math.max(0, num(listing.Price, math.huge))
	if num(buyer.Cash, 0) < price then
		return false, "Need 💰" .. commas(price)
	end
	return true, ""
end

return Market
