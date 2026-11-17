--!strict
-- Upgrades bought with cash (build plan §B2). Prices[n] is the price of level n, so the next price at level L
-- is Prices[L + 1], and #Prices is the max level. The effect maths is in Logic/Prices and Logic/Pay.
-- Lune-safe (no Roblox types). Iterate `Upgrades.Order`; `for id, upgrade in Upgrades` yields only upgrades.
-- Hints say "treat" or "patient", never "cure" (design §12).

export type UpgradeId = string
export type Upgrade = {
	Name: string,
	Icon: string,
	Hint: string, -- 6 words or fewer
	Prices: { number },
	Level: number?, -- the hospital level it needs (nil = 1): Logic/Progress.canBuyUpgrade
	Rebirths: number?, -- the rebirths it needs (nil = 0)
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
	Tips = { Name = "Tip Jar", Icon = "💰", Hint = "More cash per patient", Prices = { 75, 250, 600, 1400, 3000 } },
	-- Progression v2 (build plan §B5): department upgrades, gated. Each level: Config.WardComfort / AESpeed /
	-- NightClinicPerLevel.
	WardComfort = {
		Name = "Ward Comfort",
		Icon = "🛏️",
		Hint = "Patients rest faster",
		Prices = { 800, 2500, 6000 },
		Level = 2,
	},
	AESpeed = {
		Name = "A&E Speed",
		Icon = "🚑",
		Hint = "Ambulances come sooner",
		Prices = { 1000, 3000, 8000 },
		Level = 2,
	},
	NightClinic = {
		Name = "Night Clinic",
		Icon = "🌙",
		Hint = "Night patients pay more",
		Prices = { 1500, 4000, 9000 },
		Rebirths = 4,
	},
}

local ORDER = { "Speed", "Tray", "Chairs", "Tips", "WardComfort", "AESpeed", "NightClinic" }

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
