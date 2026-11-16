--!strict
-- Shared type names for every task (build plan §B). Types only: requiring this returns an empty table.
--   local Types = require(ReplicatedStorage.Shared.Types)
--   local function f(data: Types.Data) ... end
-- Data row types (Ailment, Room, Decor, ...) are exported by each Data module too; these match them.

-- Ids are plain strings. These aliases document which table an id belongs to.
export type AilmentId = string -- Data/Ailments
export type StationId = string -- Data/Stations
export type ItemId = string -- Data/Items
export type PatientId = string -- Data/Patients (or a RegularId: regulars use their own id as creature id)
export type RegularId = string -- Data/Regulars
export type WingId = string -- Data/Wings: "Starter" | "Bath" | "Winter" | "Night"
export type RoomId = string -- Data/Rooms
export type SlotId = string -- "Stand" | "A" | "B" | "C" | "D"
export type DecorId = string -- Data/Decor
export type UpgradeId = string -- Data/Upgrades: "Speed" | "Tray" | "Chairs" | "Tips"
export type VariantId = string -- Data/Variants: "Sparkly" | "Frosty"
export type SlotKey = string -- a decor slot: "<RoomId>:<n>", e.g. "Stand:1"
export type NurseId = string -- Data/Nurses
-- Data/Rarities: Mythic only during Night Rush, Secret only during Golden Hour (memory-20261116-013)
export type Rarity = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Secret"
export type NurseRole = "Maker" | "Healer" | "Cheerer"
export type JournalMark = "Seen" | "Hired" -- Data.NurseIndex: a silhouette until seen, full colour once hired
export type Rating = "OK" | "Good" | "Perfect" -- a mini-game's rating (Logic/MiniGame); OK still cures
export type GameId = "Pour" | "Patch" | "Scrub" | "Cool" -- the mini-game for Potion, Plaster, Bubbles, Cocoa

------------------------------------------------------------------------------------------------------------------
-- Data rows (match Shared/Data)
------------------------------------------------------------------------------------------------------------------
export type Ailment = {
	Name: string,
	Icon: string,
	Color: Color3,
	Station: StationId,
	Recipe: { ItemId }, -- 1-3 items, item 1 = the station's own item; cut by the hospital level (Logic/Recipe)
}
export type Station = { Name: string, Icon: string, Item: ItemId, Color: Color3 }
export type Item = { Name: string, Icon: string, Station: StationId }
export type Look = {
	Shape: string, -- "Ball" | "Bean" | "Blob" | "Box" | "Drop"
	Body: string, -- hex colour, e.g. "#A8DB8F"
	Accent: string, -- hex colour
	Ears: string, -- "None" | "Round" | "Floppy" | "Pointy" | "Long" | "Tufts"
	Top: string, -- "None" | "Leaf" | "Bow" | "Cloud" | "Antennae" | "Crust" | "Pleat" | "Scoop" | "Star" | "Lid"
	Extra: string, -- "None" | "Wings" | "Tail" | "Flippers" | "Spout"
	Scale: number, -- the species' size, 0.75..1.25 (Logic/CreatureSize)
	Bits: { string }?, -- small accessories (Data/Patients lists them)
}
export type Patient = { Name: string, Ailment: AilmentId, Wing: WingId, Night: boolean?, Look: Look }
export type Beat = { Emote: string, Bubble: string }
export type Regular = {
	Name: string,
	Patient: PatientId,
	Ailment: AilmentId,
	Wing: WingId,
	UnlockStars: number,
	Beats: { Beat },
	Reward: string, -- DecorId or RoomId
	RewardKind: "Decor" | "Room",
	Recipe: { ItemId }, -- their own recipe (First-Aid Stand items only)
	Look: Look,
}
export type Room = {
	Name: string,
	Icon: string,
	Slot: SlotId,
	Price: number,
	StarsNeeded: number,
	Stations: { StationId },
	Beds: number,
	DecorSlots: number,
	Wing: WingId,
	Season: string?, -- "Winter" = buyable only while Workspace.IsWinter
	Level: number?, -- the hospital level it needs (nil = 1): the Garden needs 3
}
export type Upgrade = { Name: string, Icon: string, Hint: string, Prices: { number } }
export type DecorLook = { Kind: string, Color: string, Accent: string, Glow: boolean? }
export type Decor = { Name: string, Icon: string, Price: number?, EarnedBy: string?, Look: DecorLook }
export type GoalKind = "Cure" | "CureNight" | "Make" | "CureWing"
export type GoalDef = {
	Id: string,
	Kind: GoalKind,
	Target: number,
	Wing: WingId?,
	Icon: string,
	Reward: { Cash: number, Stars: number },
}
export type Wing = { Name: string, Icon: string, SetReward: DecorId }
export type Variant = { Name: string, Icon: string, WinterOnly: boolean }
export type RarityInfo = {
	Name: string,
	Icon: string,
	Color: string, -- hex
	Frame: string, -- "Grey" | "Blue" | "Purple" | "Rainbow" | "Cosmic" | "Gold" (Kit.rarityFrame)
	Shout: boolean, -- a server-wide shout and a glow when one steps on the belt (Epic and up)
	Event: string?, -- "NightRush" | "GoldenHour": only rolled during that event
	Journal: { Cash: number, Decor: DecorId }, -- the reward for hiring every nurse of this rarity
}
export type Nurse = { Name: string, Icon: string, Rarity: Rarity, Role: NurseRole, Look: Look }
export type LevelRow = {
	Name: string,
	Icon: string,
	Stars: number, -- the Clinic Stars needed (a gate, not spent)
	Cash: number, -- spent
	Slots: number, -- nurses on duty
	Beds: number, -- beds in the main building (the Stand's own bed included)
	Queue: number, -- patients in line
	RecipeCap: number, -- recipes are cut to this many items
	SpawnSeconds: number, -- seconds between new patients (a busier clinic at each level)
	Floors: number,
	Unlocks: { string }, -- short chips for the Shop: an emoji and two or three words
}

------------------------------------------------------------------------------------------------------------------
-- Save schema v3 (Logic/Schema; creature-clinic build plan §B3, depth-update build plan §B1)
------------------------------------------------------------------------------------------------------------------
export type BookPage = { Cured: number, Variants: { [VariantId]: boolean } }
export type StoryEntry = { Beat: number, LastBeatDay: number }
export type Goal = { Id: string, Progress: number, Day: number }
export type DailyData = { Goals: { Goal }, LastGrantDay: number }
export type DecorData = { Owned: { [DecorId]: boolean }, Placed: { [SlotKey]: DecorId } }
-- Time-played rewards (Logic/Playtime): active play today (on Day) and all time, gifts opened on Day, rank rewarded.
export type PlaytimeData = {
	Day: number,
	TodaySeconds: number,
	TotalSeconds: number,
	Claimed: { number },
	Rank: number,
}
export type BoostId = string -- Data/Boosts
export type BadgeId = string -- Data/Badges.List[n].Id
export type NurseEntry = { Level: number, Copies: number } -- Level = min(Copies, Config.Nurses.MaxLevel)

export type Data = {
	Version: number, -- 3
	Cash: number,
	Stars: number,
	Cured: number,
	Upgrades: { [UpgradeId]: number }, -- levels: Speed, Tray, Chairs, Tips
	Rooms: { [RoomId]: boolean }, -- Stand = true always
	Decor: DecorData,
	Book: { [PatientId]: BookPage },
	Story: { [RegularId]: StoryEntry },
	Daily: DailyData,
	Mailbox: { LastSeenDay: number },
	HeartsGiven: { Day: number, Plots: { [string]: boolean } }, -- keyed by plot owner's UserId as a string
	ReferralRewarded: boolean,
	VisitorDay: number, -- the UTC day this clinic last cured Today's Visitor (0 = never)
	HeartsReceived: number, -- hearts left on this clinic's sign, all time (cosmetic)
	Tutorial: number, -- the first-session tutorial step (Logic/Tutorial): 1 = the welcome .. 8, 9 = done
	WeekCures: { Week: number, Count: number }, -- cures in one UTC week, for the weekly leaderboard
	Playtime: PlaytimeData,
	Boosts: { [BoostId]: number }, -- timed boosts still running: seconds of active play left
	Stats: { [string]: number }, -- badge counters (Logic/Badges); "Seeded" = 1 once worked out from an older save
	Badges: { [BadgeId]: number }, -- the badge tier rewarded so far (0..6)
	-- Depth update (v3)
	Level: number, -- hospital level 1..5 (Data/Levels)
	Nurses: { [NurseId]: NurseEntry }, -- hired nurses
	Equipped: { NurseId }, -- on duty: unique, owned, at most Level of them (slots)
	NurseIndex: { [NurseId]: JournalMark }, -- the Nurse Journal
	JournalSets: { [string]: boolean }, -- Rarity -> true: the journal group's reward was granted
	Simple: boolean, -- Simple mode: every mini-game is one tap rated Good
}

------------------------------------------------------------------------------------------------------------------
-- Network payloads (Shared/Remotes, build plan §B4)
------------------------------------------------------------------------------------------------------------------
export type Snapshot = {
	Upgrades: { [UpgradeId]: number },
	Rooms: { [RoomId]: boolean },
	Decor: DecorData,
	Book: { [PatientId]: BookPage },
	Story: { [RegularId]: StoryEntry },
	Daily: DailyData,
	Cash: number,
	Stars: number,
	Cured: number, -- extra to §B4: handy for the Guide (shown while Cured < 3)
	MailboxReady: boolean,
	PlotIndex: number?, -- nil = no plot (all 6 taken)
	TodaysVisitor: PatientId, -- "" until Daily sets it
	-- extra to §B4, for the HUD chip: "Coming" (this clinic can get today's visitor), "Done" (cured today),
	-- "None" (no plot, or no station here can treat it)
	VisitorStatus: VisitorStatus,
	IsWinter: boolean,
	-- The first-session tutorial (Server/Tutorial): the step (Logic/Tutorial, 9 = done). The client's default
	-- snapshot says 0 = not known yet, so the HUD stays calm until the server answers.
	Tutorial: number,
	TutorialCures: number, -- step 6 only: cures so far of the 2 more (0..2)
	-- Time played, boosts and badges (Server/Playtime, Boosts, Badges). Playtime is the SAVED part: the live seconds
	-- (with what's counted since the last save) are the player attributes PlayToday and PlayTotal.
	Playtime: PlaytimeData,
	Boosts: BoostList,
	MakeSeconds: { [StationId]: number }, -- your hold time at each station, every boost included (Guide)
	Stats: { [string]: number },
	Badges: { [BadgeId]: number },
	-- Depth update: copies of the save fields (slots = Logic/Levels.slots(Data.Levels, Level))
	Level: number,
	Nurses: { [NurseId]: NurseEntry },
	Equipped: { NurseId },
	NurseIndex: { [NurseId]: JournalMark },
	JournalSets: { [string]: boolean },
	Simple: boolean,
}

-- Server/Boosts.list: the timed boosts running (Left = saved seconds; subtract PlayTotal - Playtime.TotalSeconds for
-- the live value) and the permanent percent of each kind that applies everywhere (capped).
export type BoostList = {
	Timed: { { Id: BoostId, Left: number } },
	Permanent: { [string]: number },
}

export type VisitorStatus = "Coming" | "Done" | "None"

export type CuredInfo = {
	PatientId: PatientId,
	Variant: VariantId?,
	Cash: number,
	Stars: number,
	NewPage: boolean,
	Position: Vector3,
	Helper: number, -- UserId of the player who treated the patient
}

export type NextGoal = { Kind: string, Id: string, Icon: string }

export type DayReportInfo = {
	Cured: number,
	NewPages: { PatientId },
	StarsGained: number,
	Next: NextGoal,
}

export type PurchaseKind = "Upgrade" | "Room" | "Decor" | "Level" -- "Level": Economy.Purchased only (LevelUp)

-- The treat flow (depth-update build plan §B3). TreatStart (server -> the treating player):
export type TreatSession = {
	Session: number, -- the only id TreatResult accepts (one open session per player)
	PatientId: PatientId,
	Items: { ItemId }, -- what is being given now, in recipe order
	Games: { GameId }, -- one per item
	Simple: boolean, -- the client shows one tap per game; the server rates each Good
	Combo: number, -- the player's combo before this session
	Position: Vector3, -- above the patient
	Timeout: number, -- seconds; then the server settles the session as all OK by itself
}
-- TreatResult's third return value when ok
export type TreatOutcome = { Ratings: { Rating }, Tip: number, Combo: number, Complete: boolean }

-- NurseNews (server -> one player)
export type NurseNews = {
	Kind: "Seen" | "Hired" | "Equipped",
	NurseId: NurseId,
	Level: number?, -- Hired
	New: boolean?, -- Hired: the first copy
	On: boolean?, -- Equipped
}

-- Shout (server -> everyone)
export type ShoutInfo = {
	Kind: "Arrival" | "Hired" | "Golden",
	RiderId: number?, -- Arrival
	NurseId: NurseId?, -- Arrival, Hired
	Rarity: Rarity?, -- Arrival, Hired
	By: string?, -- Hired: the hirer's DisplayName
	On: boolean?, -- Golden: started (true) or ended
	EndsAt: number?, -- Golden: the GetServerTimeNow() time it ends
}

-- Celebrate (server -> one player; the client fires it too, for rooms)
export type CelebrateInfo = {
	Kind: "LevelUp" | "NewNurse" | "JournalSet" | "Room",
	Title: string, -- 3 words or fewer
	Icon: string,
	Rarity: Rarity?,
	NurseId: NurseId?,
	Level: number?,
	Cash: number?,
	Decor: DecorId?,
	Room: RoomId?, -- Kind "Room": which room (Feel/CureFX fires it; UI/Celebrate shows its name)
}

-- The client bus "Banner" spec (BeltView fires it, Toasts shows it)
export type BannerSpec = {
	Id: string, -- a banner with the same Id replaces the old one
	Icon: string,
	Text: string, -- 6 words or fewer
	Color: Color3?,
	EndsAt: number?, -- GetServerTimeNow() time: show a countdown to it
	Seconds: number?, -- how long it stays (0 = hide it now; nil = until EndsAt, else a few seconds)
}

export type Cheer = { Patience: number, Tip: number } -- multipliers, 1 = no Cheerer on duty

------------------------------------------------------------------------------------------------------------------
-- Server-side shapes (build plan §B5)
------------------------------------------------------------------------------------------------------------------
export type Plot = {
	Index: number,
	Model: Model,
	Owner: Player?,
	Counter: BasePart,
	QueueStart: BasePart,
	Spawn: BasePart, -- the PatientSpawn marker
	Exit: BasePart, -- the PatientExit marker
}

export type CureCtx = {
	Helper: Player,
	Owner: Player,
	PatientId: PatientId,
	Variant: VariantId?,
	Night: boolean,
	Regular: RegularId?,
	Visitor: boolean,
	PatienceLeft: number, -- 0..1
	Position: Vector3,
	Items: number?, -- the recipe's length, 1..3 (a longer recipe pays more: Logic/Pay); nil = 1
	Cheer: number?, -- the plot's CheerTip when the cure lands (a Cheerer on duty: Logic/Pay); nil = 1
}

------------------------------------------------------------------------------------------------------------------
-- Client (Main.client ctx, build plan Task 0)
------------------------------------------------------------------------------------------------------------------
export type ClientData = {
	Ailments: { [AilmentId]: Ailment },
	Stations: { [StationId]: Station },
	Items: { [ItemId]: Item },
	Patients: { [PatientId]: Patient },
	Regulars: { [RegularId]: Regular },
	Rooms: { [RoomId]: Room },
	Upgrades: { [UpgradeId]: Upgrade },
	Decor: { [DecorId]: Decor },
	DailyGoals: { GoalDef },
	Wings: { [WingId]: Wing },
	Variants: { [VariantId]: Variant },
	Playtime: any, -- Data/Playtime: { Gifts, Ranks, Trainee }
	Boosts: any, -- Data/Boosts: timed boosts by id, with .Order
	Badges: any, -- Data/Badges: { Tiers, Categories, List }
	Nurses: { [NurseId]: Nurse },
	Rarities: { [string]: RarityInfo }, -- by Rarity
	Levels: { LevelRow }, -- an array: Levels[level]
}

export type Ctx = {
	Player: Player,
	Remotes: any, -- Shared/Remotes
	Config: any, -- Shared/Config
	Data: ClientData, -- each map also has .Order: { id } (not visited by pairs)
	State: Snapshot, -- always the latest snapshot (a default one until the server's first arrives)
	onState: (fn: (Snapshot) -> ()) -> () -> (), -- calls fn now and on every new snapshot; returns a disconnect
	toast: (text: string) -> (), -- a local toast, same look as server toasts
	on: (event: string, fn: (...any) -> ()) -> () -> (), -- the client bus; returns a disconnect
	fire: (event: string, ...any) -> (),
}

return {}
