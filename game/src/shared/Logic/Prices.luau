--!strict
-- STUB (Task 0). Owned by Task 3: replace with the real price and timing maths and its spec
-- (tests/Prices.spec.luau). Pure: no Roblox services, no requires. Signatures from build plan §B6.

local Prices = {}

-- Price of the NEXT level for an upgrade currently at `level`; nil when maxed or unknown.
function Prices.upgradePrice(upgrades: any, id: string, level: number): number?
	local upgrade = upgrades[id]
	return upgrade and upgrade.Prices[level + 1]
end

function Prices.makeSeconds(_speedLevel: number, cfg: any): number
	return cfg.BaseMakeSeconds
end

function Prices.capacity(trayLevel: number): number
	return 1 + trayLevel
end

function Prices.patience(_chairsLevel: number, cfg: any): number
	return cfg.PatienceSeconds
end

return Prices
