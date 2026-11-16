--!strict
-- Every number you'd want to tune lives here. Change it, save, and Rojo syncs it into Studio.

local Config = {}

-- ⬜ OPEN #1: the brothers pick the theme. Rename these when they do.
Config.ProductName = "Treat"
Config.ProductPlural = "Treats"
Config.StationAction = "Make" -- the prompt reads "Make Treat"
Config.CurrencyName = "Cash"

-- Customers
Config.MaxQueue = 4 -- customers waiting at once
Config.QueueSpacing = 4 -- studs between customers in the queue
Config.SpawnEverySeconds = 6 -- with one player; more players means faster spawns
Config.SpawnSpeedupPerExtraPlayer = 0.15 -- 15% faster per extra player in the server
Config.PatienceSeconds = 35 -- how long a customer waits at the counter before leaving
Config.BasePay = 10 -- cash for a served customer before bonuses
Config.QuickServeBonus = 0.5 -- up to +50% for serving with most of the patience left
Config.CustomerWalkSpeed = 10

-- Making the product
Config.BaseMakeSeconds = 2.5
Config.MinMakeSeconds = 0.5

-- Day and night
Config.DaySeconds = 180
Config.NightSeconds = 90
Config.NightPayMultiplier = 2

-- Upgrades: each has a max level and a price per level (index = the level you're buying)
Config.Upgrades = {
	Speed = {
		DisplayName = "Faster Hands",
		Description = "Make things faster",
		Prices = { 50, 150, 400, 900, 2000 },
	},
	Tray = {
		DisplayName = "Bigger Tray",
		Description = "Carry one more",
		Prices = { 100, 500, 1500 },
	},
	Tips = {
		DisplayName = "Tip Jar",
		Description = "+20% cash per customer",
		Prices = { 75, 250, 600, 1400, 3000 },
	},
}
Config.UpgradeOrder = { "Speed", "Tray", "Tips" }

-- Background music: Roblox's licensed music library (uploader DistrokidOfficial), free for any experience.
-- Day tracks play in turn, and the night track takes over at night. Players can mute it on the HUD.
Config.Music = {
	Volume = 0.3,
	Day = {
		140331368291861, -- Cozy Autumn Cafe Vibes with Smooth Jazz
		135272444646832, -- Cozy Piano Mornings
		138035341510456, -- Accordion Breeze
	},
	Night = {
		80900515881139, -- Moonlight Through the Restaurant Window
	},
}

-- Game passes. 0 = not created yet. Create the pass in Creator Hub, paste its ID here.
Config.GamePasses = {
	DoubleCash = 0,
}

-- Saving
Config.DataStoreName = "PlayerData_v1"
Config.AutosaveSeconds = 90

function Config.makeSeconds(speedLevel: number): number
	return math.max(Config.MinMakeSeconds, Config.BaseMakeSeconds * (0.8 ^ speedLevel))
end

function Config.trayCapacity(trayLevel: number): number
	return 1 + trayLevel
end

function Config.tipMultiplier(tipsLevel: number): number
	return 1 + 0.2 * tipsLevel
end

function Config.nextPrice(upgradeName: string, currentLevel: number): number?
	local upgrade = Config.Upgrades[upgradeName]
	if not upgrade then
		return nil
	end
	return upgrade.Prices[currentLevel + 1]
end

return Config
