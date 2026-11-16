--!strict
-- Upgrades bought with cash (build plan §B2). Prices[n] is the price of level n, so the next price at level L
-- is Prices[L + 1], and #Prices is the max level. The effect maths is in Logic/Prices and Logic/Pay.
-- Lune-safe (no Roblox types). Iterate `Upgrades.Order`; `for id, upgrade in Upgrades` yields only upgrades.

export type UpgradeId = string
export type Upgrade = {
	Name: string,
	Icon: string,
	Hint: string, -- 6 words or fewer
	Prices: { number },
}

local ENTRIES: { [UpgradeId]: Upgrade } = {
	Speed = {
		Name = "Faster Hands",
		Icon = "⚡",
		Hint = "Make treatments faster",
		Prices = { 50, 150, 400, 900, 2000 },
	},
	Tray = { Name = "Bigger Tray", Icon = "🧺", Hint = "Carry one more", Prices = { 100, 500, 1500 } },
	Chairs = { Name = "Comfy Chairs", Icon = "💺", Hint = "Patients wait longer", Prices = { 75, 250, 600 } },
	Tips = { Name = "Tip Jar", Icon = "💰", Hint = "More cash per cure", Prices = { 75, 250, 600, 1400, 3000 } },
}

local ORDER = { "Speed", "Tray", "Chairs", "Tips" }

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = { Order: { UpgradeId }, [UpgradeId]: Upgrade }
return freeze(setmetatable(ENTRIES, { __index = { Order = freeze(ORDER) } })) :: Module
