--!strict
-- Every tuning number lives here. Change it, save, and Rojo syncs it into Studio.
-- Content (patients, rooms, decor, goals, upgrade prices) lives in Shared/Data instead.
-- Pure Logic modules never require this file: the server passes Config in as `cfg`.

local Config = {}

Config.CurrencyName = "Cash" -- the leaderstats name, and what the HUD calls money

-- Pay (Logic/Pay)
Config.BasePay = 12 -- cash for one cure before bonuses
Config.RecipeItemBonus = 0.5 -- each recipe item after the first adds +50% (a 2-item cure pays x1.5, 3 items x2)
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
Config.MaxQueue = 3 -- patients at one clinic at once: the one being treated + 2 waiting (calmer for kids)
Config.QueueSpacing = 7 -- studs between patients in the queue (creatures are player-sized)
Config.QueueDepth = 14 -- studs the line runs straight back from the counter before it turns sideways (3 fit straight)
Config.CreatureSize = 1.6 -- every creature's size multiplier (about a player's height)
Config.CreatureSizeJitter = 0.08 -- each patient is up to 8% smaller or bigger than its species (Logic/CreatureSize)
Config.SpawnEverySeconds = 13 -- a calm pace for young players (was 7); Lv 1. Data/Levels SpawnSeconds is per level
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

-- Time played (Server/Playtime; the gifts and ranks themselves are in Data/Playtime)
Config.PlaytimeIdleSeconds = 300 -- no moving and no acting for this long: play time (and timed boosts) pause

-- Boosts (Logic/Boosts; the timed ones are in Data/Boosts). Caps are the most the PERMANENT boosts (ranks and badge
-- tiers) can add up to, in percent; timed boosts add on top. A kind with no cap here has none.
Config.BoostCaps = { Cash = 50, Tips = 50, Stars = 50, MakeSpeed = 40, Patience = 50 }
Config.BoostMaxMinutes = 60 -- one timed boost never holds more than this (getting it again extends it up to here)
Config.BoostMinMakeSeconds = 0.3 -- MakeSpeed boosts never make a hold shorter than this

-- Roblox badges (BadgeService), created by hand in Creator Hub (game/README.md "Roblox badges"). 0 = not created
-- yet: that badge is skipped. Only the Doctor ranks and Gold Healer, so the list stays short.
Config.Badges = {
	Intern = 0,
	Resident = 0,
	Doctor = 0,
	SeniorDoctor = 0,
	Chief = 0,
	Legend = 0,
	HealerGold = 0,
}

-- Saving
Config.DataStoreName = "PlayerData_v2"
Config.LegacyDataStoreName = "PlayerData_v1" -- read once to migrate shop-sim saves
Config.AutosaveSeconds = 90

-- Leaderboards (Server/Leaderboards, game/README.md "Leaderboards"). One OrderedDataStore per board, named
-- "Board_<Id>_v<Version>"; the weekly board's name adds "_w<UTC week>", so it starts empty every Monday 00:00 UTC.
-- Bump Version to start every board fresh. Admins (the owner and Config.AdminUserIds) are never on a board.
Config.Leaderboards = {
	Version = 1,
	-- the 🏆 panel's tabs, in order (Logic/Leaderboard.BOARDS); Progression v2 adds 🏢 Most Rebirths
	Boards = { "Cured", "Stars", "Hearts", "Week", "Rebirths" },
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
-- Look overhaul (memory-20261117-001 #3; look build plan §B2/§B5): the road's centre line belongs to the Nurse Belt,
-- so the spawn plaza sits on the street's row-2 half (+z). All of these are offsets from Origin (x, z).
Config.Town = {
	Origin = Vector3.new(0, 0, 300),
	PlotSize = 80, -- was 70: the hospital is 32 wide (Logic/Building.HALF) and the side rooms moved out with it
	Plots = 6,
	SpawnOffset = Vector3.new(0, 0, 11), -- TownSpawn's centre (an 8 x 8 pad, z 7..15)
	SpawnSize = 8,
	Plaza = { X0 = -30, X1 = 30, Z0 = 5.4, Z1 = 17 }, -- the row-2 half of the road (the curb is z 17.2..18)
	BeltClear = 4.4, -- |z| <= this, x -136.5..136.5: the belt's alone (its bed is +-3.3)
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
	Combo = { -- Perfects in a row (a Good holds it, an OK resets it): the tip multiplier from At on
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

-- The Nurse Belt: one shared conveyor along the town's main street (memory-20261116-012/-013/-017, Logic/Belt,
-- Server/NurseBelt). Cash only. Every odd, event odds included, is printed on the belt's sign and in the 🎲 popup.
-- Where (Joshua, 2026-11-17, memory-20261117-001 #3: the belt runs down the road's CENTRE line): on z = 0, from just
-- inside the east welcome arch (x = +135 from Town.Origin) to just inside the west one (x = -135), past every plot's
-- gate (the arches stand at x = +-147 since the plots grew to 80 x 80). The spawn plaza moved off it
-- (Config.Town.SpawnOffset / Plaza; nothing else solid stands within Config.Town.BeltClear of the centre line).
-- Riders move west, toward the Hall of Fame end (it stays clear: x < -152), and face the plaza (+z). The conveyor is
-- low enough to step over anywhere.
-- How often (memory-20261116-017, his brother: rarer than the belt games, so a rare nurse feels earned): one nurse
-- about every 40 s, base odds 75 / 20 / 4.5 / 0.5, a Rare+ guaranteed within 15 arrivals; Mythic only in Night Rush
-- and Secret only in Golden Hour. Epic and up ride for everyone but need hospital Lv 3 to hire (MinLevel); their
-- first-rebirth gate for Mythic and Secret waits for rebirths (design §7).
Config.Belt = {
	Offset = Vector3.new(135, 0, 0), -- the belt's start (the nurse house at the east end, z = 0) from Town.Origin
	Heading = 180, -- degrees about Y from world +X that riders move: 180 = toward -X (west)
	Length = 270, -- studs, start to end (was 240 on the 70-stud plots' street)
	SignOffset = Vector3.new(-24, 0, 11), -- the odds sign from Town.Origin: the plaza's west end, facing TownSpawn
	ArriveSeconds = 40, -- a nurse steps on this often
	RideSeconds = 100, -- start to end (2.7 studs a second); with one every 40 s, two or three ride at once
	ReplaceSeconds = 8, -- a hire that leaves no other nurse on the belt (Common or Rare) brings the next this soon
	Odds = { Common = 75, Rare = 20, Epic = 4.5, Legendary = 0.5 }, -- percent
	MinLevel = { Epic = 3, Legendary = 3, Mythic = 3, Secret = 3 }, -- the hospital level that may hire them
	NightRushBoost = 2, -- during the in-game night, Rare, Epic and Legendary odds x this (Common takes the rest)
	NightRushMythic = 0.5, -- percent: Mythic, only during Night Rush
	GoldenSecret = 1, -- percent: Secret, only during Golden Hour
	GoldenEverySeconds = 1200, -- Golden Hour starts every 20 minutes of server uptime...
	GoldenSeconds = 120, -- ...and lasts 2 minutes
	PityArrivals = 15, -- after this many arrivals in a row without a Rare+, the next is Rare+ (server-wide)
	HireCooldown = 3, -- seconds per player
	HireDistance = 40, -- studs from the rider (a tap on its billboard reaches this far)
	SeenDistance = 100, -- studs: a player this close to a rider has seen it (the Journal's silhouette fills in)
	ServerStepSeconds = 1, -- the server moves riders this often; clients glide them every frame
	MaxRiders = 5, -- a safety cap on riders at once (the cadence alone keeps two or three on)
	Prices = { Common = 100, Rare = 400, Epic = 1500, Legendary = 6000, Mythic = 20000, Secret = 50000 },
	PriceScale = { 1, 1.1, 1.2, 1.3, 1.4 }, -- x by hospital level, so newcomers can always afford Commons (§E5)
	-- Progression v2 (design §7): Mythic and Secret ride for everyone, but only a player with this many rebirths may
	-- hire them (Logic/Belt.gate: "🏢 R1"). Rebirth-only nurses (Data/Nurses Source) never ride.
	MinRebirths = { Mythic = 1, Secret = 1 },
}

-- Nurses on your plot (Logic/Nurse, Server/Nurses). Speed and strength scale with rarity x level. Progression v2
-- (docs/plan/2026-11-16-progression-v2-build-plan.md §B6): every nurse you own works its job; levels come from XP
-- (Config.NurseXP; a copy is one whole level) up to MaxLevel, or MaxLevel + LevelCapBonus from LevelCapRebirths.
Config.Nurses = {
	MaxLevel = 10, -- the level cap (Lv 10)...
	LevelCapRebirths = 3, -- ...raised from this many rebirths (R3, memory-20261116-019)...
	LevelCapBonus = 5, -- ...by this much (Lv 15)
	TrayMax = 4, -- items Makers keep ready in the plot's nurse tray
	MinSeconds = 3, -- no nurse works faster than this
	FasterPerLevel = 0.05, -- each level above 1 takes this share off a Maker's, Healer's, Medic's or Porter's seconds
	MakerSeconds = { Common = 14, Rare = 12, Epic = 10, Legendary = 8, Mythic = 7, Secret = 6 },
	HealerSeconds = { Common = 16, Rare = 14, Epic = 12, Legendary = 10, Mythic = 9, Secret = 8 },
	CheerPatience = { Common = 0.1, Rare = 0.15, Epic = 0.2, Legendary = 0.3, Mythic = 0.35, Secret = 0.4 },
	CheerTip = { Common = 0.05, Rare = 0.08, Epic = 0.12, Legendary = 0.18, Mythic = 0.22, Secret = 0.25 },
	CheerPerLevel = 0.02, -- each level above 1 adds this to both Cheerer bonuses
	SpecialtyBoost = 0.4, -- design §7: "+40% speed there": a job worked in the nurse's own department
	MedicSeconds = { Common = 14, Rare = 12, Epic = 10, Legendary = 8, Mythic = 7, Secret = 6 },
	MedicPatience = { Common = 0.2, Rare = 0.25, Epic = 0.3, Legendary = 0.4, Mythic = 0.45, Secret = 0.5 },
	PorterSeconds = { Common = 5, Rare = 4.5, Epic = 4, Legendary = 3.5, Mythic = 3, Secret = 3 }, -- a trip's walk
	ReceptionArrive = { Common = 0.05, Rare = 0.08, Epic = 0.12, Legendary = 0.16, Mythic = 0.18, Secret = 0.2 },
	ReceptionPerLevel = 0.005, -- each level above 1 adds this to a Receptionist's arrival bonus
}

------------------------------------------------------------------------------------------------------------------
-- Progression v2 (docs/plan/2026-11-16-progression-v2-build-plan.md §B6, the reasons in §B6.1). Claude's tuning,
-- open to change after playtests. No Robux anywhere in these systems (CLAUDE.md red line 3).
------------------------------------------------------------------------------------------------------------------

-- The roster (memory-20261116-019): every nurse you own works. Max is for performance (§E1: 8 = R5).
Config.Roster = { Base = 3, PerRebirth = 1, Max = 8 }

-- Nurse XP (Logic/Nurse.addXP): to the next level = 10 + 5 x L x (L + 1). Each cure gives every WORKING nurse at
-- that plot PerCure, +Specialty when the cure was in its department, x FastLearners with that perk.
Config.NurseXP = { PerCure = 1, Specialty = 1, FastLearners = 2 }

-- Signature abilities (Data/Abilities, Logic/Abilities): cooldown x CooldownStep at each of UpgradeLevels, never
-- below MinCooldown seconds; x SecondWind with that perk. The design table's effect numbers (Server/Abilities):
-- FastMake = Busy Paws' station holds x0.5, CashNext = Double Dose's cure pay x2, NearStation = Time Bubble needs
-- the owner within 25 studs of a station.
Config.Abilities = {
	CooldownStep = 0.85,
	UpgradeLevels = { 5, 10 },
	MinCooldown = 20,
	SecondWind = 0.8,
	FastMake = 0.5,
	CashNext = 2,
	NearStation = 25,
}

-- Rebirths: "🏢 Open a new branch" (Logic/Rebirth). Optional, never pushed.
Config.Rebirth = {
	MinLevel = 5, -- a Mega Hospital
	Cost = { 50000, 75000, 110000, 170000, 250000, 380000, 570000, 850000, 1300000, 1900000 }, -- R1..R10
	Growth = 1.5, -- past the table: x1.5 a rebirth, rounded to 2 significant figures
	CashPerRebirth = 0.25, -- +25% cure cash a rebirth, ADDED (R4 = x2), counted up to MaxBonusRebirths (§E12)
	StarsPerRebirth = 0.25,
	MaxBonusRebirths = 20,
	PointsPerRebirth = 3, -- Branch Ability Tree points
	OfferSize = 3, -- perk cards offered
	StartCash = 0, -- cash after a rebirth (the SeedMoney perk: 1,000)
}

-- The branch's own boost caps (percent): the tree + perks. Beside Config.BoostCaps (badges + ranks), so neither eats
-- the other's room and neither can run away.
Config.BranchCaps = { Cash = 30, Stars = 30, Tips = 30, MakeSpeed = 30, Patience = 50 }

-- The Nurse Agency kiosk (Server/Agency, Logic/Agency; design §8, §B3.1). No countdown anywhere (§E9).
Config.Agency = {
	RestockSeconds = 300, -- a new stock every 5 minutes of server uptime
	Slots = 4,
	LuckySlots = 2, -- the 🍀 Lucky Stock capstone: your own extra slots, same shown odds
	Odds = { Common = 70, Rare = 26, Epic = 4 }, -- percent; never Legendary+ (design §8)
	PriceMultiplier = 1.5, -- x the belt's price at your level
	SellBack = 0.3, -- x the belt's BASE price, per copy (never level-scaled: no buy-and-sell-back profit)
	Cooldown = 1, -- seconds per player between buys or sells
	Offset = Vector3.new(13, 0, 12), -- the kiosk, from Town.Origin (on the plaza; it turns to face TownSpawn)
}

-- The Player Market (Server/Market, Logic/Market; same server only, §B3.2).
Config.Market = {
	Fee = 0.1, -- the seller gets price - floor(price x Fee): a cash sink
	BandMin = 0.5, -- the price band: x the belt's base price...
	BandMax = 3,
	LevelStep = 0.1, -- ...x (1 + LevelStep x (Level - 1))...
	Round = 10, -- ...rounded to tens
	MaxPerSeller = 3,
	MaxListings = 30,
	ListCooldown = 5,
	BuyCooldown = 2,
	Offset = Vector3.new(-13, 0, 12),
}

-- How far (studs, HumanoidRootPart to the kiosk's prompt part) AgencyBuy, SellNurse, ListNurse and BuyListing answer
-- from; further away they say "🚶 Come closer!". 0 = off, and it ships OFF: the 👩‍⚕️ panel's 🏢 Agency / 🏷️ Market
-- buttons and a Team card's Sell / List open both panels from anywhere, so a number here breaks those until the
-- panels are kiosk-only (15 is the number then: the prompts reach 10).
Config.KioskReach = 0

-- Hospital v2 (design §6)
Config.Lift = { RideSeconds = 2, CarDistance = 6, Cooldown = 1, EscortWait = 6 }
Config.AE = {
	EverySeconds = 150, -- an ambulance about this often (±Jitter) at Lv 2+
	Jitter = 0.2,
	FirstSeconds = 60,
	PatienceMultiplier = 0.6, -- 🚑 patients wait less...
	CashMultiplier = 3, -- ...and pay x3...
	Stars = 2, -- ...+2 ⭐
	MinItems = 2, -- their recipe has at least this many items (Logic/Hospital.urgentRecipe)
}
Config.VIP = { EverySeconds = 300, Jitter = 0.2, CashMultiplier = 4, Stars = 3 } -- the air ambulance (R2 + Lv 5)
Config.Triage = { Seconds = 4, RightBonus = 0.1 }
Config.Escort = { CashBonus = 0.2, RecoverFactor = 0.5 }
Config.Hydro = { Spots = 2, CashBonus = 0.25, RecoverFactor = 0.5 }
Config.Pharmacy = { HoldSeconds = 3, Tier2Factor = 0.5 }
Config.WardComfort = { RecoverPerLevel = 0.2, CashPerLevel = 0.05 }
Config.AESpeed = { PatiencePerLevel = 0.15, SoonerPerLevel = 0.1 }
Config.NightClinicPerLevel = 0.25 -- night cure cash +25% a Night Clinic level
Config.NightOwl = 0.3 -- of Config.NightSeconds: the 🦉 perk's night patients keep coming this long after morning
Config.GoldenChance = 0.02 -- R3+ owners' patients (1 in 50)
Config.GoldenMultiplier = 5

------------------------------------------------------------------------------------------------------------------
-- Look overhaul (docs/plan/2026-11-17-look-overhaul-build-plan.md §B2, the reasons in §C). Claude's defaults
-- (memory-20261117-003, provisional): Joshua or his brother can overrule any of them here.
------------------------------------------------------------------------------------------------------------------

-- The studs look and the part budgets (tests/PartBudget.spec, the world specs).
Config.Look = {
	StudsVariant = "CureStuds", -- the MaterialService child that switches World/Studs to "Variant" mode (§B4)
	CheckerStuds = 4, -- town lawn checker cell: within 20 studs of the street and in the plot gaps
	CheckerFarStuds = 8, -- the rest of the town lawn
	-- An rbxassetid of a 2x2-cell checker once uploaded: one Texture per lawn part (StudsPerTileU/V = 2 x cell,
	-- Transparency ~0.85) replaces the GrassB tiles. "" = the tiles are parts.
	CheckerTexture = "",
	TownParts = 600, -- ClinicTown (the lawn, road, plaza, trees, lamps, arches; not the belt, kiosks, boards or plots)
	PlotBudget = 400, -- one plot at Lv 5 with every room, any theme, no creatures, nurses or decor
	BuildingParts = 160, -- its share: the Building, any level, any theme
	RoomParts = 90, -- its share: every room model on the plot (the Stand floor + annexes + the Garden)
	-- Its share: everything else on the plot (pad, edging, path, Counter, markers, slots, sign, fence, gate, mailbox,
	-- trees, bushes, queue lane).
	PlotParts = 115,
	SurfaceGuisPerBuilding = 12,
	GlassPerBuilding = 6, -- see-through parts (Transparency strictly between 0 and 1)
	WardFloorBeds = 7, -- beds you can see on the Wards floor (F1), Lv 2..5: functional + dressing
	Lv1Beds = 2, -- beds you can see at Lv 1: Bed_1 + one dressing bed
	Sleepers = { Lv1 = 1, Ward = 2 }, -- sleeping stand-ins on dressing beds
}

-- The tutorial's guide (UI/Wayfinder, UI/Tutorial, Server/Tutorial; tutorial-ux §5.5).
Config.Tutorial = {
	-- the guide beam
	BeamLift = 1.75,
	BeamEndLift = 0.25,
	BeamWidth = 1.6,
	BeamTextureLength = 2,
	BeamSpeed = 1.5,
	BeamMaxSpans = 4,
	BeamTexture = "", -- our own chevron strip once uploaded ("" = a solid tinted strip)
	NearStuds = 6, -- the beam and the chevrons hide this close to the target (flat distance)
	-- the floor chevrons (support)
	ChevronStuds = 4,
	ChevronGap = 6,
	MaxChevrons = 6,
	FirstChevron = 3,
	GlowSeconds = 1.6, -- the glow's pulse
	NudgeSeconds = 20, -- "Psst! Follow the arrows" (a hint, never shown as a number)
	SuccessHold = 0.8, -- the tick beat before the next card
	FirstCureHold = 2.5, -- CURED! holds this long
	ArrowsUntilCures = 3, -- the Guide keeps beam + glow + pin until this many cures (after Skip too)
	ReplayCooldown = 30, -- seconds per player between TutorialReplay calls
	ShopStuckSeconds = 6, -- card 7 moves on by itself after this when there is nothing they can buy
}

-- Game passes. 0 = not created. Nothing paid exists in this build (plan: Global Constraints), and the
-- 2x Cash idea needs a rethink before it ever ships (design §9). Kept only so the ID has a home.
Config.GamePasses = {
	DoubleCash = 0,
}

return Config
