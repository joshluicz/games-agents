--!strict
-- Shared type names for every task (build plan §B). Types only: requiring this returns an empty table.
--   local Types = require(ReplicatedStorage.Shared.Types)
--   local function f(data: Types.Data) ... end
-- Data row types (Case, Room, Decor, ...) are exported by each Data module too; these match them.

-- Ids are plain strings. These aliases document which table an id belongs to.
export type CaseId = string -- Data/Cases: what is wrong with a patient (they replaced the ailments)
export type ToolId = string -- Data/Tools: "Stethoscope" | "Thermometer" | "Light" | "Magnifier" | "XRay"
export type StationId = string -- Data/Stations
export type ItemId = string -- Data/Items
export type PatientId = string -- Data/Patients (or a RegularId: regulars use their own id as creature id)
export type RegularId = string -- Data/Regulars
export type WingId = string -- Data/Wings: "Starter" | "Bath" | "Winter" | "Night" | "Sunny" | "Sky"
export type RoomId = string -- Data/Rooms
export type SlotId = string -- "Stand" | "A" | "B" | "C" | "D"
export type DecorId = string -- Data/Decor
export type UpgradeId = string -- Data/Upgrades: "Speed" | "Tray" | "Chairs" | "Tips" | "WardComfort" | "AESpeed" | "NightClinic"
export type VariantId = string -- Data/Variants: "Sparkly" | "Frosty" | "Golden"
export type SlotKey = string -- a decor slot: "<RoomId>:<n>", e.g. "Stand:1"
export type NurseId = string -- Data/Nurses
-- Data/Rarities: Mythic only during Night Rush, Secret only during Golden Hour (memory-20261116-013)
export type Rarity = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Secret"
export type NurseRole = "Maker" | "Healer" | "Cheerer" -- a nurse's default job (Data/Nurses Role)
-- Progression v2 (docs/plan/2026-11-16-progression-v2-build-plan.md §B3)
export type JobId = string -- Data/Jobs: "Maker" | "Healer" | "Cheerer" | "Receptionist" | "Porter" | "Medic"
-- Data/Departments: "Reception" | "Pharmacy" | "Hydro" | "AE" | "Wards" | "Imaging" | "Rest" | "Roof"
export type DeptId = string
export type AbilityId = string -- Data/Abilities
export type PerkId = string -- Data/Perks (the Fallback card is "TreePoints")
export type NodeId = string -- Data/Tree.Nodes
export type ThemeId = string -- Data/Themes
export type JournalMark = "Seen" | "Hired" -- Data.NurseIndex: a silhouette until seen, full colour once hired
export type Rating = "OK" | "Good" | "Perfect" -- a mini-game's rating (Logic/MiniGame); OK still treats
-- A mini-game (Logic/MiniGame.ENGINE says which engine plays it): an exam tool's (Data/Tools Game), a supply's
-- (Data/Items Game), the dispensary's Dose, and Pick (choose the right tool or bottle)
export type GameId =
	"Listen"
	| "Temp"
	| "Light"
	| "Look"
	| "XRay"
	| "Plaster"
	| "Ice"
	| "Bandage"
	| "Cast"
	| "Bath"
	| "Cocoa"
	| "Dose"
	| "Pick"
export type GameEngine = "Pour" | "Patch" | "Scrub" | "Cool" | "Pick" -- the five games the client can draw

------------------------------------------------------------------------------------------------------------------
-- Data rows (match Shared/Data)
------------------------------------------------------------------------------------------------------------------
export type Case = {
	Name: string,
	Icon: string,
	Bubble: string, -- the symptom shown before the exam
	Tool: ToolId, -- the exam tool that finds it
	Plan: { ItemId }, -- 1-3 steps in order; cut by the hospital level (Logic/Visit.plan)
	Stay: ("Wards" | "Rest")?, -- rests upstairs after the plan (Logic/Visit.stayWard)
	Level: number, -- the hospital level it comes from
	Room: RoomId?, -- a room the clinic must own as well
}
export type Tool = { Name: string, Icon: string, Game: GameId, Machine: boolean?, Level: number? }
-- Item "" + Dispense: the dispensary (medicines, the player only)
export type Station = { Name: string, Icon: string, Item: ItemId, Color: Color3, Dispense: boolean? }
-- A supply has a Game (played at the bay); a medicine (station "Remedy") has a Bottle colour (hex) and no game
export type Item = {
	Name: string,
	Icon: string,
	Station: StationId,
	Kind: "Supply" | "Medicine",
	Game: GameId?,
	Bottle: string?,
}
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
-- A species has no case of its own: each visit rolls one from its wing's pool (Data/Cases.POOLS)
export type Patient = { Name: string, Wing: WingId, Night: boolean?, Look: Look }
export type Beat = { Emote: string, Bubble: string }
export type Regular = {
	Name: string,
	Patient: PatientId,
	Case: CaseId, -- their one fixed case (a Lv 1 case, so every clinic can treat it)
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
	Level: number?, -- the hospital level it needs (nil = 1): the Garden needs 3
}
-- Level / Rebirths: the gates (Progression v2: the hospital level and the rebirths it needs)
export type Upgrade =
	{ Name: string, Icon: string, Hint: string, Prices: { number }, Level: number?, Rebirths: number? }
export type DecorLook = { Kind: string, Color: string, Accent: string, Glow: boolean? }
export type Decor = {
	Name: string,
	Icon: string,
	Price: number?,
	EarnedBy: string?, -- "Book" | "Story" | "Referral" | "Playtime" | "Journal" | "Rebirth"
	Rebirths: number?, -- EarnedBy "Rebirth": the rebirth count that gives it (a Branch Trophy, R6-R10)
	Look: DecorLook,
}
export type GoalKind = "Cure" | "CureNight" | "Make" | "CureWing"
export type GoalDef = {
	Id: string,
	Kind: GoalKind,
	Target: number,
	Wing: WingId?,
	Icon: string,
	Reward: { Cash: number, Stars: number },
}
-- Rebirths: the owner's rebirths before its patients come; Only = "Helicopter": they come only by air ambulance
export type Wing = { Name: string, Icon: string, SetReward: DecorId, Rebirths: number?, Only: string? }
export type Variant = { Name: string, Icon: string, WinterOnly: boolean, Rebirths: number? }
export type RarityInfo = {
	Name: string,
	Icon: string,
	Color: string, -- hex
	Frame: string, -- "Grey" | "Blue" | "Purple" | "Rainbow" | "Cosmic" | "Gold" (Kit.rarityFrame)
	Shout: boolean, -- a server-wide shout and a glow when one steps on the belt (Epic and up)
	Event: string?, -- "NightRush" | "GoldenHour": only rolled during that event
	Journal: { Cash: number, Decor: DecorId }, -- the reward for hiring every nurse of this rarity
}
export type Nurse = {
	Name: string,
	Icon: string,
	Rarity: Rarity,
	Role: NurseRole,
	Specialty: DeptId | "Any", -- +40% when its job works in this department; counts for that department's team
	Ability: AbilityId,
	Source: string?, -- "Rebirth": a rebirth-only nurse (never the belt, the Agency or the Market)
	Rebirths: number?, -- with Source: the rebirth count that grants it
	Look: Look,
}
export type LevelRow = {
	Name: string,
	Icon: string,
	Stars: number, -- the Clinic Stars needed (a gate, not spent)
	Cash: number, -- spent
	Bays: number, -- open exam bays in the row of six (the X-ray bay and the Cozy Ward's two come on top)
	Beds: number, -- ward beds upstairs, for patients who stay
	Queue: number, -- patients in the waiting room
	RecipeCap: number, -- a case's plan is cut to this many steps
	SpawnSeconds: number, -- seconds between new patients (a busier clinic at each level)
	Floors: number, -- open floors above the ground (the 4th at Lv 5 is the roof)
	Departments: { DeptId }, -- open at this level, cumulatively
	Unlocks: { string }, -- short chips for the Shop: an emoji and two or three words
}
export type Job = { Name: string, Icon: string, Dept: string, Opens: number, Text: string }
export type TeamEffect = { Kind: string, Value: number, Stations: { StationId }? }
export type Department = {
	Name: string,
	Icon: string,
	Opens: number,
	Room: RoomId?, -- it comes with this bought room, not with a level (Hydro: the Bath Room)
	Floor: number,
	Team2: TeamEffect?,
	Team3: TeamEffect?,
}
export type Ability = {
	Name: string,
	Icon: string,
	Kind: string,
	Cooldown: number,
	Daily: boolean?,
	Values: { number },
	Game: GameId?,
}
export type Perk = { Name: string, Icon: string, Text: string, Kind: string, Value: number }
export type TreeNode = {
	Branch: string,
	Name: string,
	Icon: string,
	Text: string,
	Max: number,
	Cost: number,
	Capstone: boolean,
	Effect: string,
	Value: number,
}
export type Theme = {
	Name: string,
	Icon: string,
	Rebirths: number,
	Wall: string,
	Roof: string,
	Trim: string,
	Prop: string,
}

------------------------------------------------------------------------------------------------------------------
-- Save schema v4 (Logic/Schema; creature-clinic build plan §B3, depth-update build plan §B1, Progression v2 §B1)
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
-- A nurse you own (Progression v2): Level 1..the level cap (10; 15 from R3), XP toward the next level (0 at the cap),
-- Copies hired, Job "" (= its Role), a Data/Jobs id, or "Rest" (an over-roster nurse that isn't working)
export type NurseEntry = { Level: number, XP: number, Copies: number, Job: string }
export type RebirthData = {
	Count: number, -- rebirths done ("branches opened")
	Points: number, -- unspent Branch Ability Tree points
	Tree: { [NodeId]: number }, -- ranks bought
	Perks: { PerkId }, -- perk cards chosen, in order
	Offer: { PerkId }, -- the cards waiting to be chosen (0..3)
	Theme: ThemeId, -- the branch theme shown; "" = Candy
	Pending: { NurseId }, -- rebirth-only nurses waiting for a free roster slot
	Told: boolean, -- the one gentle "🏢 You can open a branch!" toast was shown (once ever)
}

export type Data = {
	Version: number, -- 4
	Cash: number,
	Stars: number,
	Cured: number,
	Upgrades: { [UpgradeId]: number }, -- levels: Speed, Tray, Chairs, Tips, WardComfort, AESpeed, NightClinic
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
	-- Look overhaul: the step-7 top-up has run, or was never needed (Server/Tutorial gives it once; a Replay never
	-- gives a second one). Derived when missing: true for a save at or past step 7 (Logic/Schema)
	TutorialGift: boolean,
	WeekCures: { Week: number, Count: number }, -- cures in one UTC week, for the weekly leaderboard
	Playtime: PlaytimeData,
	Boosts: { [BoostId]: number }, -- timed boosts still running: seconds of active play left
	Stats: { [string]: number }, -- badge counters (Logic/Badges); "Seeded" = 1 once worked out from an older save;
	-- "RoomsBefore" = the rooms rebirths reset (the 🏠 Builder badge); "Exams" = the player's first exams, counted
	-- up to Config.Visit.ExamsGlow (the exam card's glow, Server/Patients)
	Badges: { [BadgeId]: number }, -- the badge tier rewarded so far (0..6)
	-- Depth update (v3)
	Level: number, -- hospital level 1..5 (Data/Levels)
	Nurses: { [NurseId]: NurseEntry }, -- every nurse you own (at most the roster cap work; the rest rest)
	NurseIndex: { [NurseId]: JournalMark }, -- the Nurse Journal
	JournalSets: { [string]: boolean }, -- Rarity -> true: the journal group's reward was granted
	Simple: boolean, -- Simple mode: every mini-game is one tap rated Good
	-- Progression v2 (v4)
	Rebirth: RebirthData,
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
	-- Look overhaul: true while this session is REPLAYING the tutorial (⚙️ "🔁 Replay tutorial"). Not saved: it is
	-- Server/Tutorial's player attribute TutorialReplay, forwarded like TutorialCures. No sweep, no gift, full HUD
	TutorialReplay: boolean,
	-- Time played, boosts and badges (Server/Playtime, Boosts, Badges). Playtime is the SAVED part: the live seconds
	-- (with what's counted since the last save) are the player attributes PlayToday and PlayTotal.
	Playtime: PlaytimeData,
	Boosts: BoostList,
	MakeSeconds: { [StationId]: number }, -- your hold time at each station, every boost included (Guide)
	Stats: { [string]: number },
	Badges: { [BadgeId]: number },
	-- Depth update: copies of the save fields
	Level: number,
	Nurses: { [NurseId]: NurseEntry },
	NurseIndex: { [NurseId]: JournalMark },
	JournalSets: { [string]: boolean },
	Simple: boolean,
	-- Progression v2: a copy of the save's Rebirth. The client works out the roster cap, the level cap, the effective
	-- jobs, team bonuses, the next rebirth's cost and the tree's effects from it with Logic/* and Config. The Agency
	-- and the Market are not here (GetAgency / GetMarket and AgencyNews / MarketNews)
	Rebirth: RebirthData,
}

-- Server/Boosts.list: the timed boosts running (Left = saved seconds; subtract PlayTotal - Playtime.TotalSeconds for
-- the live value) and the permanent percent of each kind that applies everywhere (capped).
export type BoostList = {
	Timed: { { Id: BoostId, Left: number } },
	Permanent: { [string]: number },
	-- Progression v2: the capped branch percent of each kind (the tree + perks, Config.BranchCaps) and the rebirth
	-- multiplier on cure Cash and Stars (Logic/Rebirth.multiplier)
	Branch: { [string]: number },
	Rebirth: { Cash: number, Stars: number },
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
	-- Progression v2 (Feel/CureFX's bonus lines; Server/Cure always sends them, "" / false = no):
	Urgent: string?, -- "" | "AE" | "VIP": an ambulance (🚑 x3) or helicopter (🚁 x4) patient
	Escorted: boolean?, -- it rode the lift with a Porter or a player (+20% 🛗)
}

export type NextGoal = { Kind: string, Id: string, Icon: string }

export type DayReportInfo = {
	Cured: number,
	NewPages: { PatientId },
	StarsGained: number,
	Next: NextGoal,
}

export type PurchaseKind = "Upgrade" | "Room" | "Decor" | "Level" -- "Level": Economy.Purchased only (LevelUp)

-- The treat flow (depth-update build plan §B3; Real Clinic build plan, contract C5). A visit is three kinds of
-- session, all on the same two remotes. TreatStart (server -> the playing player):
--   Kind "Exam"      at a bay, before the case is known. Games = { "Pick", <the answer tool's game> }: pick the right
--                    tool out of Tools (Answer is the right one; it glows when Glow), then play its game. Items = {}.
--                    Settling it reveals the case (TreatOutcome.Case), whatever the ratings
--   Kind "Treat"     at a bay, giving supplies: one game per item in Items (Data/Items Game). Medicines are handed
--                    over with no session at all
--   Kind "Dispense"  at the dispensary. Options = the medicines bay patients still need (up to 3, the oldest first).
--                    Games = { "Pick", "Dose" }: find the chosen medicine's bottle, measure the dose. The report's
--                    Choice names the medicine; the outcome's Item is what went into the player's hands
-- TreatResult(session: number, ratings: { Rating }, choice: ItemId?) -> ok, message, TreatOutcome?
export type TreatSession = {
	Session: number, -- the only id TreatResult accepts (one open session per player)
	PatientId: PatientId, -- the patient's species ("" for a Dispense session)
	Items: { ItemId }, -- Treat: what is being given now, in plan order; {} for Exam and Dispense
	Games: { GameId }, -- the games to play, in order
	Simple: boolean, -- the client shows one tap per game; the server rates each Good
	Combo: number, -- the player's combo before this session
	Position: Vector3, -- above the patient (Dispense: above the dispensary counter)
	Timeout: number, -- seconds; then the server settles the session as all OK by itself
	Kind: ("Exam" | "Treat" | "Dispense")?, -- nil = "Treat"
	Auto: { boolean }?, -- per game: an ability made it PERFECT (the client shows ✨ and skips it)
	Ease: number?, -- 1..1.3: 🎯 Steady Hands widens the Perfect windows (client only, never checked)
	-- The Real Clinic
	Tools: { ToolId }?, -- Exam: the 3 tools on the card (Logic/Visit.examTools)
	Answer: ToolId?, -- Exam: the right one (the server picked it; knowing it early wins nothing but the tip)
	Glow: boolean?, -- Exam: the right tool glows (a player's first exams, and Simple mode: Logic/Visit.glow)
	Symptom: string?, -- Exam: the patient's symptom bubble, the card's clue
	Options: { ItemId }?, -- Dispense: the medicines to choose from
	-- Dispense: Expert Dispensing (the clinic owner's Pharmacy2 unlock). The client draws and rates the Dose game
	-- with its band Config.Dispensary.ExpertBand wider; Tuning.Dose is that same row as the server worked it out
	Expert: boolean?,
	Tuning: { [GameId]: { [string]: number } }?,
	Case: CaseId?, -- Treat: the case being treated (it is known by then). Never sent with an Exam
	-- Treat: a handover. Games is {}: nothing to play, the client reports at once and shows only the ward pick
	-- (TreatOutcome.Triage) when the server asks for one
	Handover: boolean?,
}
-- TreatResult's third return value when ok
export type TreatOutcome = {
	Ratings: { Rating },
	Tip: number,
	Combo: number,
	Complete: boolean,
	Case: CaseId?, -- Exam: the case the exam revealed ("🩺 It's a cough!")
	Plan: { ItemId }?, -- Exam: that patient's own plan (cut to its clinic's level; an urgent one padded)
	Item: ItemId?, -- Dispense: the medicine now in the player's hands (nil: the choice wasn't on offer)
	-- Progression v2: pick a floor for this patient now (Lv 3+, no Receptionist); Seconds for a soft bar, no digits
	Triage: { Options: { DeptId }, Seconds: number }?,
}

-- NurseNews (server -> one player). Kind and NurseId always.
--   "Seen" · "Hired" (Level, New) · "Job" (Job) · "Level" (Level, Ability: an ability upgrade at 5/10) · "Sold" (Cash)
--   · "Bought" (Price) · "Gone" (Price: sold on the Market) · "Listed" (On) · "Resting" (On)
export type NurseNews = {
	Kind: "Seen" | "Hired" | "Job" | "Level" | "Sold" | "Bought" | "Gone" | "Listed" | "Resting",
	NurseId: NurseId,
	Level: number?, -- Hired, Level
	New: boolean?, -- Hired: the first copy
	Job: JobId?, -- Job
	Ability: boolean?, -- Level: the ability got stronger (Lv 5, Lv 10)
	Cash: number?, -- Sold
	Price: number?, -- Bought, Gone
	On: boolean?, -- Listed, Resting
}

-- BeltScout (server -> a 🔭 Belt Scout perk owner): the next belt arrival's rarity, rolled one arrival early with the
-- odds on the sign at that moment (Event says which: "" | "NightRush" | "GoldenHour")
export type BeltScoutInfo = { Rarity: Rarity, Event: string }

-- The Nurse Agency (Server/Agency; GetAgency, AgencyNews)
export type AgencySlot = {
	Slot: number,
	NurseId: NurseId,
	Rarity: Rarity,
	Price: number, -- YOUR price now (level scale and Bargain included)
	Bought: boolean, -- you bought this slot this restock
	Personal: boolean, -- a 🍀 Lucky Stock slot (only you see it)
	Gate: string?, -- "🏥 Lv 3" | "🏢 R1" | nil
}
export type AgencyView = {
	Restock: number,
	Slots: { AgencySlot },
	Odds: { [Rarity]: number },
	SellBack: { [NurseId]: number }, -- what the Agency pays you for each nurse you own now
}

-- The Player Market (Server/Market; GetMarket, MarketNews). SellerName = DisplayName; nothing else about anyone.
export type Listing = {
	Id: number,
	Seller: number, -- UserId
	SellerName: string,
	NurseId: NurseId,
	Rarity: Rarity,
	Level: number,
	Price: number,
}
export type MarketView = { Listings: { Listing }, FeePercent: number, MaxPerSeller: number }

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
--   Progression v2 kinds: "Rebirth" (Count, Theme) · "Perk" (Perk) · "NurseLevel" (NurseId, Level, Ability) ·
--   "Unlock" (Unlock: a Logic/Rebirth.UNLOCKS id)
export type CelebrateInfo = {
	-- "Tutorial" (look overhaul): the tutorial's finale, fired on the client by UI/Tutorial and shown even while the
	-- tutorial runs: Title "YOU DID IT!", Chips, and Next (the one "COMING UP" chip, a FREE event only)
	Kind: "LevelUp" | "NewNurse" | "JournalSet" | "Room" | "Rebirth" | "Perk" | "NurseLevel" | "Unlock" | "Tutorial",
	Title: string, -- 3 words or fewer
	Icon: string,
	Rarity: Rarity?,
	NurseId: NurseId?,
	Level: number?,
	Cash: number?,
	Decor: DecorId?,
	Room: RoomId?, -- Kind "Room": which room (Feel/CureFX fires it; UI/Celebrate shows its name)
	Count: number?, -- Rebirth: the rebirths done now
	Theme: ThemeId?, -- Rebirth: the new branch theme
	Perk: PerkId?, -- Perk
	Ability: boolean?, -- NurseLevel: the ability got stronger
	Unlock: string?, -- Unlock
	Chips: { string }?, -- Tutorial: "📖 Collect them all", "🎯 Daily goals", "👩‍⚕️ Hire nurses"
	Next: NextEventView?, -- Tutorial: what's coming up (Logic/NextEvent.pick; never anything paid)
}

-- A FREE upcoming event for a "coming up" chip (Logic/NextEvent; memory-20261116-022: countdowns only for free
-- events, in minutes). At is a Workspace:GetServerTimeNow() time.
export type NextEventView = { Id: string, Icon: string, Name: string, At: number }

-- What the HUD does while a modal is open (UI/Modal sends it with ModalOpened / ModalClosed): "Panel" hides the
-- rails, the Now card and Status (the wallet stays) · "Game" (the mini-game) hides the rails and Status, the wallet
-- and the Now card stay · "None" (a popup) changes nothing.
export type HudMode = "Panel" | "Game" | "None"

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
	Counter: BasePart, -- the reception desk, in the lobby (Logic/Building.RECEPTION.Desk)
	Spawn: BasePart, -- the PatientSpawn marker, at the gate
	Exit: BasePart, -- the PatientExit marker, at the gate
	-- The Real Clinic: no QueueStart and no queue lane. The waiting room is the line (the Building has WaitSeat_<n>).
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
	-- Progression v2
	Urgent: string?, -- "AE" | "VIP" (an ambulance or helicopter patient)
	Extra: number?, -- situational factors Patients knows (escort, spa, triage, team, Ward Comfort), 1..Pay.MAX_EXTRA
	Plot: Plot?, -- where it was cured (Cure asks Abilities and Nurses about this plot)
	Dept: DeptId?, -- the department it recovered in (nurse XP specialty)
	Wing: WingId?, -- for XP and the Book (already derivable; passed to save a lookup)
	Escorted: boolean?, -- rode the lift with a Porter or a player (already in Extra; passed on to CuredInfo)
}

-- Team bonuses at a plot (Logic/Jobs.teamEffects, Server/Nurses.team): factors, 1 = none
export type TeamEffects = { Cash: number, Urgent: number, Recover: number, Make: { [StationId]: number } }

------------------------------------------------------------------------------------------------------------------
-- Client (Main.client ctx, build plan Task 0)
------------------------------------------------------------------------------------------------------------------
export type ClientData = {
	Cases: { [CaseId]: Case }, -- with .ORDER and .POOLS
	Tools: { [ToolId]: Tool }, -- with .ORDER
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
	-- Progression v2
	Jobs: { [JobId]: Job },
	Departments: any, -- Data/Departments: { [DeptId]: Department }, with .Order, .Stations and .Wings
	Abilities: { [AbilityId]: Ability },
	Perks: any, -- Data/Perks: { [PerkId]: Perk }, with .Order, .Fallback and .FallbackId
	Tree: any, -- Data/Tree: { Branches, BranchOrder, Nodes (with .Order), CapstoneNeeds }
	Themes: { [ThemeId]: Theme },
	-- Look overhaul
	Guide: any, -- Data/Guide: { Name, Icon, Look } (the tutorial's guide nurse; no .Order)
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
