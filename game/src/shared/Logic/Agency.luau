--!strict
-- The Nurse Agency's rules: restocks, rolls, prices and the sell-back (Progression v2 build plan §B3.1/§B6/§B7;
-- design §8, memory-20261116-018). Pure: no Roblox services, no requires. `cfg` is Shared/Config (cfg.Agency and
-- cfg.Belt.Prices / PriceScale are read); `roster` Shared/Data/Nurses (rawget, so "Order" is never an id). Random
-- numbers are passed in (r01 in [0, 1)), so everything here is testable. No countdown anywhere (§E9).
--
--   Agency.restock(uptime, cfg): number      the restock index: floor(server uptime / RestockSeconds), from 0
--   Agency.odds(cfg): { [Rarity]: number }   the shown odds (percent, a copy of cfg.Agency.Odds): never Legendary+
--   Agency.rarity(odds, r01): Rarity         a weighted pick from those odds
--   Agency.roll(roster, cfg, r01s, slots?, taken?): { NurseId }
--       `slots` (default cfg.Agency.Slots) DISTINCT nurses, never a rebirth-only one (Source), none in `taken`. Slot k
--       uses r01s[2k - 1] for its rarity (the shown odds) and r01s[2k] for the nurse; a rarity with nobody left falls
--       to the next lower one with somebody (so a full stock always fills). Fewer r01s, fewer slots
--   Agency.seeded(seed, n): { number }       n numbers in [0, 1) from a whole-number seed (Park-Miller): the same seed
--                                            always gives the same numbers
--   Agency.personal(roster, cfg, userId, restock, owned): { NurseId }
--       the 🍀 Lucky Stock capstone's LuckySlots nurses for one player this restock: a roll seeded by (userId,
--       restock), so asking again (or rejoining) never re-rolls them. Each slot rolls its rarity with the SHOWN
--       odds. `owned` = the shared stock's nurses this restock: never repeated in your own slots unless every nurse
--       of the rolled rarity is in it (then a shared one may repeat, so the shown odds stay true); never two of the
--       same among your own slots. It must not depend on anything the player can change
--   Agency.price(cfg, rarity, level, bargain?): number
--       the belt's base price x PriceScale[hospital level] x PriceMultiplier x (1 - bargain), rounded once
--       (Lv 1: Common 150, Rare 600, Epic 2,250)
--   Agency.sellBack(entry, rarity, cfg): number
--       floor(the belt's BASE price x SellBack) x Copies (30 / 120 / 450 / 1,800 / 6,000 / 15,000 a copy): never
--       level-scaled, so nothing can be bought and sold back for a profit (§E14)

local Agency = {}

Agency.RARITIES = table.freeze({ "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" })

local MODULUS = 2147483647 -- 2^31 - 1 (Park-Miller): 16807 x MODULUS stays far below 2^53
local MULTIPLIER = 16807

local function num(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

local function settings(cfg: any): any
	return if type(cfg) == "table" and type(cfg.Agency) == "table" then cfg.Agency else {}
end

local function belt(cfg: any): any
	return if type(cfg) == "table" and type(cfg.Belt) == "table" then cfg.Belt else {}
end

local function basePrice(cfg: any, rarity: string): number
	local prices = belt(cfg).Prices
	return if type(prices) == "table" then math.max(0, num(prices[rarity], 0)) else 0
end

function Agency.restock(uptime: number, cfg: any): number
	local every = math.max(1, num(settings(cfg).RestockSeconds, 300))
	return math.floor(math.max(0, num(uptime, 0)) / every)
end

function Agency.odds(cfg: any): { [string]: number }
	local out: { [string]: number } = {}
	local odds = settings(cfg).Odds
	if type(odds) == "table" then
		for rarity, value in odds do
			if type(rarity) == "string" and num(value, 0) > 0 then
				out[rarity] = value
			end
		end
	end
	return out
end

function Agency.rarity(odds: { [string]: number }, r01: number): string
	local total = 0
	local pool: { string } = {}
	for _, rarity in Agency.RARITIES do
		local weight = num(odds[rarity], 0)
		if weight > 0 then
			total += weight
			table.insert(pool, rarity)
		end
	end
	if #pool == 0 then
		return "Common"
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

-- Nurses of a rarity that may stock the Agency (no Source), in Order, not yet taken.
local function candidates(roster: any, rarity: string, taken: { [string]: boolean }): { string }
	local ids: { string } = {}
	if type(roster) == "table" and type(roster.Order) == "table" then
		for _, id in roster.Order do
			local nurse = rawget(roster, id)
			if type(nurse) == "table" and nurse.Rarity == rarity and nurse.Source == nil and not taken[id] then
				table.insert(ids, id)
			end
		end
	end
	return ids
end

local function rank(rarity: string): number
	return table.find(Agency.RARITIES, rarity) or 1
end

function Agency.roll(roster: any, cfg: any, r01s: { number }, slots: number?, taken: { string }?): { string }
	local count = math.max(0, math.floor(num(slots, num(settings(cfg).Slots, 4))))
	local odds = Agency.odds(cfg)
	local used: { [string]: boolean } = {}
	if type(taken) == "table" then
		for _, id in taken do
			used[id] = true
		end
	end
	local out: { string } = {}
	for k = 1, count do
		local r1, r2 = r01s[2 * k - 1], r01s[2 * k]
		if r1 == nil or r2 == nil then
			break
		end
		local rarity = Agency.rarity(odds, r1)
		local ids = candidates(roster, rarity, used)
		local step = rank(rarity)
		while #ids == 0 and step > 1 do
			step -= 1
			ids = candidates(roster, Agency.RARITIES[step], used)
		end
		if #ids > 0 then
			local index = math.clamp(math.floor(math.clamp(num(r2, 0), 0, 1) * #ids) + 1, 1, #ids)
			local nurseId = ids[index]
			used[nurseId] = true
			table.insert(out, nurseId)
		end
	end
	return out
end

function Agency.seeded(seed: number, n: number): { number }
	local state = math.floor(math.abs(num(seed, 1))) % (MODULUS - 1) + 1
	local out: { number } = {}
	for index = 1, math.max(0, math.floor(num(n, 0))) do
		state = (state * MULTIPLIER) % MODULUS
		out[index] = (state - 1) / (MODULUS - 1)
	end
	return out
end

-- Each own slot rolls its rarity with the shown odds, then picks a nurse of that rarity that is neither in your
-- own slots nor in the shared stock. Only when every nurse of that rarity is already in the shared stock may a
-- shared one repeat (never one of your own slots), so the shown odds stay exactly true (with the shipped roster
-- about 12% of Lucky Stock restocks need that, almost always Commons). A rarity with nobody at all falls to the
-- next lower one (a roster that small never ships).
function Agency.personal(roster: any, cfg: any, userId: number, restock: number, owned: { string }?): { string }
	local slots = math.max(0, math.floor(num(settings(cfg).LuckySlots, 2)))
	local seed = (math.floor(math.abs(num(userId, 0))) % 1000003) * 7919 + math.floor(math.abs(num(restock, 0))) + 1
	local r01s = Agency.seeded(seed, slots * 2)
	local odds = Agency.odds(cfg)
	local inShared: { [string]: boolean } = {}
	if type(owned) == "table" then
		for _, id in owned do
			inShared[id] = true
		end
	end
	local mine: { [string]: boolean } = {}
	local out: { string } = {}
	for k = 1, slots do
		local step = rank(Agency.rarity(odds, r01s[2 * k - 1]))
		local ids: { string } = {}
		while step >= 1 do
			local fresh: { string } = {}
			local repeats: { string } = {}
			for _, id in candidates(roster, Agency.RARITIES[step], mine) do
				table.insert(if inShared[id] then repeats else fresh, id)
			end
			ids = if #fresh > 0 then fresh else repeats
			if #ids > 0 then
				break
			end
			step -= 1
		end
		if #ids > 0 then
			local index = math.clamp(math.floor(math.clamp(num(r01s[2 * k], 0), 0, 1) * #ids) + 1, 1, #ids)
			local nurseId = ids[index]
			mine[nurseId] = true
			table.insert(out, nurseId)
		end
	end
	return out
end

function Agency.price(cfg: any, rarity: string, level: number, bargain: number?): number
	local scales = belt(cfg).PriceScale
	local scale = 1
	if type(scales) == "table" and #scales > 0 then
		scale = num(scales[math.clamp(math.floor(num(level, 1)), 1, #scales)], 1)
	end
	local multiplier = math.max(0, num(settings(cfg).PriceMultiplier, 1.5))
	local off = math.clamp(num(bargain, 0), 0, 0.9)
	return math.floor(basePrice(cfg, rarity) * scale * multiplier * (1 - off) + 0.5)
end

function Agency.sellBack(entry: any, rarity: string, cfg: any): number
	local copies = if type(entry) == "table" then math.max(1, math.floor(num(entry.Copies, 1))) else 0
	local share = math.clamp(num(settings(cfg).SellBack, 0.3), 0, 1)
	return math.floor(basePrice(cfg, rarity) * share) * copies
end

return Agency
