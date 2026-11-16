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

------------------------------------------------------------------------------------------------------------------
-- Data rows (match Shared/Data)
------------------------------------------------------------------------------------------------------------------
export type Ailment = { Name: string, Icon: string, Color: Color3, Station: StationId }
export type Station = { Name: string, Icon: string, Item: ItemId, Color: Color3 }
export type Item = { Name: string, Icon: string, Station: StationId }
export type Look = {
	Shape: string, -- "Ball" | "Bean" | "Blob" | "Box" | "Drop"
	Body: string, -- hex colour, e.g. "#A8DB8F"
	Accent: string, -- hex colour
	Ears: string, -- "None" | "Round" | "Floppy" | "Pointy" | "Long" | "Tufts"
	Top: string, -- "None" | "Leaf" | "Bow" | "Cloud" | "Antennae" | "Crust" | "Pleat" | "Scoop" | "Star" | "Lid"
	Extra: string, -- "None" | "Wings" | "Tail" | "Flippers" | "Spout"
	Scale: number,
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

------------------------------------------------------------------------------------------------------------------
-- Save schema v2 (Logic/Schema, build plan §B3)
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

export type Data = {
	Version: number, -- 2
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
	Playtime: PlaytimeData,
	Boosts: { [BoostId]: number }, -- timed boosts still running: seconds of active play left
	Stats: { [string]: number }, -- badge counters (Logic/Badges); "Seeded" = 1 once worked out from an older save
	Badges: { [BadgeId]: number }, -- the badge tier rewarded so far (0..6)
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

export type PurchaseKind = "Upgrade" | "Room" | "Decor"

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
