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
Config.CreatureSizeJitter = 0.08 -- each patient is up to 8% smaller or bigger than its species (Logic/CreatureSize)
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

-- Leaderboards (Server/Leaderboards, game/README.md "Leaderboards"). One OrderedDataStore per board, named
-- "Board_<Id>_v<Version>"; the weekly board's name adds "_w<UTC week>", so it starts empty every Monday 00:00 UTC.
-- Bump Version to start every board fresh. Admins (the owner and Config.AdminUserIds) are never on a board.
Config.Leaderboards = {
	Version = 1,
	Boards = { "Cured", "Stars", "Hearts", "Week" }, -- the 🏆 panel's tabs, in order (Logic/Leaderboard.BOARDS)
	WorldBoards = { "Cured", "Stars", "Hearts", "Week" }, -- the plaza boards, left to right (at most 4)
	WriteSeconds = 150, -- a player's values are written at most this often (only what changed), and when they leave
	RefreshSeconds = 120, -- each board is read this often (one request), and shared by everyone in the server
	RetrySeconds = 30, -- the wait after a failed request; it doubles each time up to MaxBackoffSeconds
	MaxBackoffSeconds = 600,
	Depth = 100, -- rows read per board: your rank shows up to #100, then "#100+"
	Shown = 10, -- rows on each board
	NameCacheSeconds = 3600, -- names of players not in this server are looked up again after this
	MinBudget = 1, -- a read or write waits while its DataStore budget has fewer requests left than this (the
	-- saves use other request kinds, so nothing else competes for these)
}

-- Remotes: per player, per remote
Config.RemoteRatePerSecond = 10

-- The 🛠️ Admin panel (Server/Admin, game/README.md "Admin panel"). The server decides who is an admin, never the
-- client: a UserId here (checked first), the game's owner, or a username below, which the server turns into a
-- UserId at startup and prints in Output as "[Admin] <name> = <id>". Copy that id into AdminUserIds: a username
-- can change hands, an id can't. In Studio everyone playing is an admin.
Config.AdminUserIds = { 311718381 } :: { number } -- Dandlepeeps (looked up in-game 2026-11-16)
Config.AdminNames = { "Dandlepeeps" } -- Joshua's brother

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

-- Game passes. 0 = not created. Nothing paid exists in this build (plan: Global Constraints), and the
-- 2x Cash idea needs a rethink before it ever ships (design §9). Kept only so the ID has a home.
Config.GamePasses = {
	DoubleCash = 0,
}

return Config
