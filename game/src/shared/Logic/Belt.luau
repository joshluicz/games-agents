--!strict
-- The Nurse Belt's rules: odds, rolls, pity, prices, Golden Hour, where a rider is (depth-update design §2, build plan
-- §B7; memory-20261116-012/-013). Pure: no Roblox services, no requires. `cfg` is Shared/Config (cfg.Belt and
-- cfg.Nurses are read); random numbers are passed in (r01 in [0, 1)), so everything here is testable.
--
-- Odds are percent and always add up to 100. Common, Rare, Epic and Legendary are always possible. Night Rush (the
-- in-game night) multiplies Rare, Epic and Legendary by NightRushBoost and adds Mythic; Golden Hour (2 minutes every
-- 20 of server uptime) adds Secret. Common takes whatever is left. Every one of these is printed on the belt's sign.
--
--   Belt.RARITIES                                lowest first (matches Data/Rarities.Order)
--   Belt.isRarePlus(rarity) · Belt.shouts(rarity)   Rare and up · Epic and up (a server-wide shout and a glow)
--   Belt.odds(cfg, nightRush, golden): { [Rarity]: number }   every rarity, 0 when it can't come now
--   Belt.roll(odds, r01, pity): Rarity           a weighted pick; pity = only Rare and up (their odds, rescaled)
--   Belt.pityDue(dry, cfg): boolean              dry = arrivals in a row without a Rare+; PityArrivals of them
--                                                means the next one is Rare+
--   Belt.afterArrival(dry, rarity): number       the new dry count (0 after a Rare+)
--   Belt.pityLeft(dry, cfg): number              arrivals until the guaranteed Rare+ (the sign's "🎁 in n")
--   Belt.pick(roster, rarity, r01): NurseId?     a nurse of that rarity, evenly (roster = Data/Nurses)
--   Belt.price(cfg, rarity, level): number       Prices[rarity] x PriceScale[hospital level], rounded
--   Belt.golden(cfg, uptime): (active, startsAt, endsAt)   the current Golden Hour window, or the next one, in
--                                                uptime seconds (windows start at 1x, 2x, 3x... GoldenEverySeconds)
--   Belt.alpha(startAt, now, rideSeconds): number   how far along the belt a rider is, 0..1
--   Belt.canHire(entry?, cfg): (ok, message)     not when that nurse is already at Config.Nurses.MaxLevel

export type Rarity = string

local Belt = {}

Belt.RARITIES = table.freeze({ "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" })

local RANK: { [string]: number } = {}
for index, rarity in Belt.RARITIES do
	RANK[rarity] = index
end

local function num(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

local function belt(cfg: any): any
	return if type(cfg) == "table" and type(cfg.Belt) == "table" then cfg.Belt else {}
end

function Belt.isRarePlus(rarity: any): boolean
	local rank = RANK[rarity]
	return rank ~= nil and rank >= 2
end

function Belt.shouts(rarity: any): boolean
	local rank = RANK[rarity]
	return rank ~= nil and rank >= 3
end

function Belt.odds(cfg: any, nightRush: boolean, golden: boolean): { [string]: number }
	local b = belt(cfg)
	local base = if type(b.Odds) == "table" then b.Odds else {}
	local boost = if nightRush then num(b.NightRushBoost, 1) else 1
	local out: { [string]: number } = {
		Rare = math.max(0, num(base.Rare, 0)) * boost,
		Epic = math.max(0, num(base.Epic, 0)) * boost,
		Legendary = math.max(0, num(base.Legendary, 0)) * boost,
		Mythic = if nightRush then math.max(0, num(b.NightRushMythic, 0)) else 0,
		Secret = if golden then math.max(0, num(b.GoldenSecret, 0)) else 0,
	}
	local rest = 0
	for _, value in out do
		rest += value
	end
	out.Common = math.max(0, 100 - rest)
	return out
end

function Belt.roll(odds: { [string]: number }, r01: number, pity: boolean): Rarity
	local pool: { string } = {}
	local total = 0
	for _, rarity in Belt.RARITIES do
		local weight = num(odds[rarity], 0)
		if weight > 0 and (not pity or Belt.isRarePlus(rarity)) then
			table.insert(pool, rarity)
			total += weight
		end
	end
	if #pool == 0 then
		return if pity then "Rare" else "Common"
	end
	local x = math.clamp(num(r01, 0), 0, 1) * total
	for _, rarity in pool do
		x -= odds[rarity]
		if x < 0 then
			return rarity
		end
	end
	return pool[#pool]
end

function Belt.pityDue(dry: number, cfg: any): boolean
	return num(dry, 0) >= num(belt(cfg).PityArrivals, math.huge)
end

function Belt.afterArrival(dry: number, rarity: Rarity): number
	if Belt.isRarePlus(rarity) then
		return 0
	end
	return math.max(0, num(dry, 0)) + 1
end

function Belt.pityLeft(dry: number, cfg: any): number
	return math.max(1, num(belt(cfg).PityArrivals, 8) + 1 - math.max(0, num(dry, 0)))
end

function Belt.pick(roster: any, rarity: Rarity, r01: number): string?
	if type(roster) ~= "table" then
		return nil
	end
	local order = roster.Order
	local ids: { string } = {}
	if type(order) == "table" then
		for _, id in order do
			local nurse = rawget(roster, id)
			if type(nurse) == "table" and nurse.Rarity == rarity then
				table.insert(ids, id)
			end
		end
	end
	if #ids == 0 then
		return nil
	end
	local index = math.clamp(math.floor(math.clamp(num(r01, 0), 0, 1) * #ids) + 1, 1, #ids)
	return ids[index]
end

function Belt.price(cfg: any, rarity: Rarity, level: number): number
	local b = belt(cfg)
	local prices = if type(b.Prices) == "table" then b.Prices else {}
	local base = math.max(0, num(prices[rarity], 0))
	local scales = if type(b.PriceScale) == "table" then b.PriceScale else {}
	local count = #scales
	local scale = 1
	if count > 0 then
		local index = math.clamp(math.floor(num(level, 1)), 1, count)
		scale = num(scales[index], 1)
	end
	return math.floor(base * scale + 0.5)
end

function Belt.golden(cfg: any, uptime: number): (boolean, number, number)
	local b = belt(cfg)
	local every = math.max(1, num(b.GoldenEverySeconds, 1200))
	local length = math.clamp(num(b.GoldenSeconds, 120), 0, every)
	local now = math.max(0, num(uptime, 0))
	local k = math.floor(now / every)
	if k >= 1 and now - k * every < length then
		local startsAt = k * every
		return true, startsAt, startsAt + length
	end
	local startsAt = (k + 1) * every
	return false, startsAt, startsAt + length
end

function Belt.alpha(startAt: number, now: number, rideSeconds: number): number
	local ride = num(rideSeconds, 0)
	if ride <= 0 then
		return 1
	end
	return math.clamp((num(now, 0) - num(startAt, 0)) / ride, 0, 1)
end

function Belt.canHire(entry: any, cfg: any): (boolean, string)
	local nurses = if type(cfg) == "table" and type(cfg.Nurses) == "table" then cfg.Nurses else {}
	local maxLevel = num(nurses.MaxLevel, 5)
	if type(entry) == "table" and num(entry.Level, 0) >= maxLevel then
		return false, "Max level!"
	end
	return true, ""
end

return Belt
