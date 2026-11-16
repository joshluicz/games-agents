--!strict
-- Upgrade prices and what each level does (build plan §B6). Pure: no Roblox services, no requires.
--   Prices.upgradePrice(upgrades, id, level): number?   price of the NEXT level; nil when maxed, unknown or junk
--   Prices.maxLevel(upgrades, id): number                how many levels an upgrade has (0 if unknown)
--   Prices.makeSeconds(speedLevel, cfg): number          Faster Hands: hold time at a station
--   Prices.capacity(trayLevel): number                   Bigger Tray: items you can carry (= 1 + level)
--   Prices.patience(chairsLevel, cfg): number            Comfy Chairs: seconds a patient waits
-- `upgrades` is Shared/Data/Upgrades (Prices[n] is the price of level n). `cfg` is Shared/Config.
-- Levels come from saves and the network, so every level is sanitised: junk counts as level 0.

export type Upgrade = { Prices: { number } }
export type Cfg = {
	BaseMakeSeconds: number,
	MinMakeSeconds: number,
	MakeSpeedFactor: number,
	PatienceSeconds: number,
	ChairsPatienceBonus: number,
}

local Prices = {}

-- A finite whole level >= 0, or nil.
local function cleanLevel(level: any): number?
	if type(level) ~= "number" or level ~= level or level == math.huge or level == -math.huge then
		return nil
	end
	local whole = math.floor(level)
	return if whole >= 0 then whole else nil
end

-- rawget skips the module metatable, so "Order" (the id list) is never mistaken for an upgrade.
local function find(upgrades: any, id: any): Upgrade?
	if type(upgrades) ~= "table" or type(id) ~= "string" then
		return nil
	end
	local upgrade = rawget(upgrades, id)
	if type(upgrade) == "table" and type(upgrade.Prices) == "table" then
		return upgrade
	end
	return nil
end

function Prices.upgradePrice(upgrades: any, id: string, level: number): number?
	local upgrade = find(upgrades, id)
	local current = cleanLevel(level)
	if not upgrade or current == nil then
		return nil
	end
	local price = upgrade.Prices[current + 1]
	return if type(price) == "number" then price else nil
end

function Prices.maxLevel(upgrades: any, id: string): number
	local upgrade = find(upgrades, id)
	return if upgrade then #upgrade.Prices else 0
end

-- Each Faster Hands level multiplies the hold time by MakeSpeedFactor, down to MinMakeSeconds.
function Prices.makeSeconds(speedLevel: number, cfg: Cfg): number
	local level = cleanLevel(speedLevel) or 0
	local seconds = cfg.BaseMakeSeconds * cfg.MakeSpeedFactor ^ level
	return math.max(cfg.MinMakeSeconds, seconds)
end

function Prices.capacity(trayLevel: number): number
	return 1 + (cleanLevel(trayLevel) or 0)
end

function Prices.patience(chairsLevel: number, cfg: Cfg): number
	return cfg.PatienceSeconds + cfg.ChairsPatienceBonus * (cleanLevel(chairsLevel) or 0)
end

return Prices
