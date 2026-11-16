--!strict
-- Every tuning number lives here. Change it, save, and Rojo syncs it into Studio.
-- Content (patients, rooms, decor, goals, upgrade prices) lives in Shared/Data instead.
-- Pure Logic modules never require this file: the server passes Config in as `cfg`.

local Config = {}

Config.CurrencyName = "Cash" -- the leaderstats name, and what the HUD calls money

-- Pay (Logic/Pay)
Config.BasePay = 12 -- cash for one cure before bonuses
Config.QuickServeBonus = 0.5 -- up to +50% for curing with most of the patience left
Config.TipsPerLevel = 0.2 -- each Tip Jar level adds +20% cash
Config.NightPayMultiplier = 2
Config.SparklyChance = 0.03
Config.SparklyMultiplier = 2
Config.VisitorMultiplier = 3 -- Today's Visitor
Config.FrostyChance = 0.25 -- winter only
Config.FrostyMultiplier = 1.5

-- Patients
Config.PatienceSeconds = 60 -- how long a patient waits at the counter before leaving (no penalty)
Config.ChairsPatienceBonus = 10 -- extra seconds of patience per Comfy Chairs level
Config.MaxQueue = 4 -- patients waiting at one clinic at once
Config.QueueSpacing = 7 -- studs between patients in the queue (creatures are player-sized)
Config.QueueDepth = 7 -- studs the line runs straight back from the counter before it turns sideways
Config.CreatureSize = 1.6 -- every creature's size multiplier (about a player's height)
Config.SpawnEverySeconds = 13 -- a calm pace for young players (was 7)
Config.RecoverSeconds = 4 -- time in bed (or in place) before the cure lands
Config.QueuePatienceRate = 0.5 -- patience drains at this speed behind the front of the line (1 = full speed)
Config.GuestPatienceMultiplier = 1.5 -- regulars and Today's Visitor wait this much longer
Config.FirstPatientSeconds = 2 -- the first patient arrives this soon after you get your clinic

-- Making treatments at a station (Logic/Prices.makeSeconds)
Config.BaseMakeSeconds = 2
Config.MinMakeSeconds = 0.5
Config.MakeSpeedFactor = 0.8 -- each Faster Hands level multiplies the hold time by this

-- Day and night
Config.DaySeconds = 420
Config.NightSeconds = 180

-- Seasons: dates are UTC, inclusive. Workspace.ForceWinter = true turns winter on for testing.
Config.Winter = { Start = "2026-12-01", End = "2027-01-10" }

-- Daily
Config.MailboxGiftCash = 25 -- once per UTC day, the same however long you were away
Config.MaxBankedGoals = 3 -- daily goals bank up to this many; they never expire

-- Saving
Config.DataStoreName = "PlayerData_v2"
Config.LegacyDataStoreName = "PlayerData_v1" -- read once to migrate shop-sim saves
Config.AutosaveSeconds = 90

-- Remotes: per player, per remote
Config.RemoteRatePerSecond = 10

-- Town: two rows of three plots facing a central street.
Config.Town = {
	Origin = Vector3.new(0, 0, 300),
	PlotSize = 70,
	Plots = 6,
}

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

------------------------------------------------------------------------------------------------------------------
-- Depth update (docs/plan/2026-11-16-depth-update-build-plan.md §B6). Claude's tuning, open to change.
------------------------------------------------------------------------------------------------------------------

-- Treating v2: one short mini-game per recipe item (Logic/MiniGame). Ratings are OK / Good / Perfect and OK still
-- cures (no fail states). A Perfect tips a little cash and builds the combo; tips are cash only and capped per cure.
Config.MiniGame = {
	PerfectTip = 3, -- cash per Perfect, before the combo multiplier
	TipCapPerCure = 15, -- the most tip cash one patient can give, however many Perfects
	Combo = { -- Perfects in a row (a non-Perfect resets it): the tip multiplier from At on
		{ At = 3, Multiplier = 1.2 },
		{ At = 6, Multiplier = 1.5 },
		{ At = 10, Multiplier = 2 },
	},
	-- Server plausibility: a report sooner than Slack x the games' minimum time is rated all OK.
	MinSeconds = { Pour = 1.2, Patch = 1, Scrub = 1.5, Cool = 1.5 },
	SimpleMinSeconds = 0.25, -- Simple mode: one tap per game
	Slack = 0.8,
	-- A session nobody reports on settles as all OK after SessionSeconds + PerGameSeconds x games.
	SessionSeconds = 12,
	PerGameSeconds = 6,
	-- The games themselves (client; MiniGame.rate reads these so they tune in one place)
	Pour = { FillSeconds = 2.4, BandMin = 0.7, BandMax = 0.86, GoodSlack = 0.12 }, -- hold, let go in the band
	Patch = { Spots = 3, Seconds = 4.5, Good = 2 }, -- tap the sore spots
	Scrub = { Seconds = 4, Perfect = 6, Good = 3 }, -- pop the bubbles
	Cool = { Blows = 3, Good = 2, PulseSeconds = 1.2, Window = 0.3 }, -- blow when the steam ring is biggest
}

-- The treat flow (Server/Treatment)
Config.Treat = {
	ItemPatience = 0.25, -- each recipe item given back fills this share of the patient's patience
	Distance = 20, -- studs from the Counter: a TreatResult from farther away is rated all OK
}

-- The Nurse Belt: one shared conveyor in the town plaza (memory-20261116-012/-013, Logic/Belt, Server/NurseBelt).
-- Cash only. Every odd, event odds included, is printed on the belt's sign.
Config.Belt = {
	Offset = Vector3.new(24, 0, 0), -- the belt's start from Town.Origin; riders move toward +X
	Length = 44, -- studs
	ArriveSeconds = 6, -- a nurse steps on this often
	RideSeconds = 30, -- start to end; nobody hires it: it hops off the end
	ReplaceSeconds = 1.5, -- a hired Common or Rare is replaced this soon
	Odds = { Common = 70, Rare = 24, Epic = 5, Legendary = 1 }, -- percent
	NightRushBoost = 2, -- during the in-game night, Rare, Epic and Legendary odds x this (Common takes the rest)
	NightRushMythic = 0.5, -- percent: Mythic, only during Night Rush
	GoldenSecret = 1, -- percent: Secret, only during Golden Hour
	GoldenEverySeconds = 1200, -- Golden Hour starts every 20 minutes of server uptime...
	GoldenSeconds = 120, -- ...and lasts 2 minutes
	PityArrivals = 8, -- after this many arrivals in a row without a Rare+, the next is Rare+ (server-wide)
	HireCooldown = 3, -- seconds per player
	HireDistance = 40, -- studs from the rider (a tap on its billboard reaches this far)
	SeenDistance = 100, -- studs: a player this close to a rider has seen it (the Journal's silhouette fills in)
	ServerStepSeconds = 1, -- the server moves riders this often; clients glide them every frame
	MaxRiders = 8, -- a safety cap on riders at once
	Prices = { Common = 100, Rare = 400, Epic = 1500, Legendary = 6000, Mythic = 20000, Secret = 50000 },
	PriceScale = { 1, 1.25, 1.5, 1.75, 2 }, -- x by hospital level, so newcomers can always afford Commons
}

-- Nurses on your plot (Logic/Nurse, Server/Nurses). Speed and strength scale with rarity x level (1-5).
Config.Nurses = {
	MaxLevel = 5, -- hiring the same nurse again adds a level, up to this
	TrayMax = 4, -- items Makers keep ready in the plot's nurse tray
	MinSeconds = 3, -- no nurse works faster than this
	FasterPerLevel = 0.08, -- each level above 1 takes this share off a Maker's or Healer's seconds
	MakerSeconds = { Common = 14, Rare = 12, Epic = 10, Legendary = 8, Mythic = 7, Secret = 6 },
	HealerSeconds = { Common = 16, Rare = 14, Epic = 12, Legendary = 10, Mythic = 9, Secret = 8 },
	CheerPatience = { Common = 0.1, Rare = 0.15, Epic = 0.2, Legendary = 0.3, Mythic = 0.35, Secret = 0.4 },
	CheerTip = { Common = 0.05, Rare = 0.08, Epic = 0.12, Legendary = 0.18, Mythic = 0.22, Secret = 0.25 },
	CheerPerLevel = 0.03, -- each level above 1 adds this to both Cheerer bonuses
}

-- Game passes. 0 = not created. Nothing paid exists in this build (plan: Global Constraints), and the
-- 2x Cash idea needs a rethink before it ever ships (design §9). Kept only so the ID has a home.
Config.GamePasses = {
	DoubleCash = 0,
}

return Config
