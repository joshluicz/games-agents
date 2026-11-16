# Creature Clinic (Slices 1–2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> This plan runs as a **parallel team**: Task 0 first, then Tasks 1–8 at the same time, then Tasks 9–10.

**Goal:** Turn the shop sim in `game/src` into Creature Clinic Slices 1–2: your own clinic on a plot, patients with
ailments, typed treatments, Patient Book, three story regulars, dailies, mailbox, hearts, night patients and the Winter
Wing.

**Architecture:**
- **Pure game logic is testable.** It lives in `src/shared/Logic/*.luau` (no Roblox services, no requires, all inputs
  passed in) and is tested with Lune in `game/tests/`.
- **Roblox-facing systems are thin.** They're server modules that call the Logic modules and talk to each other only
  through the APIs in §B, booted by `Main.server.luau`.
- **The world is placeholder-first.** `PlotBuilder` makes a placeholder town of 6 plots unless the brother's models
  exist in `ServerStorage.ClinicKit` and `ServerStorage.Creatures`.

**Tech Stack:** Luau, Rojo 7.7.1, selene 0.32.0, StyLua 2.6.0, Lune 0.11.1 (tests; Joshua installs it: §E),
Roblox Studio MCP (integration only).

**Spec:** `docs/plan/2026-11-16-creature-clinic-design.md`. Read it. Rules: `CLAUDE.md`. Skills in `.claude/skills/`:
load `roblox-luau`, `roblox-networking`, `roblox-datastores`, `roblox-ui`, `game-ui-ux` and `game-feel` as relevant.

## Global Constraints
- **Server owns all data and money.** Every remote is validated on the server: type checks, ownership and permission,
  plus a per-player rate limit of 10 calls/s per remote (`roblox-networking`).
- **Rated Minimal.** Cartoon care only: no needles, blood, surgery, weapons or gross-out. Night is soft-glow, not scary.
- **No reading required to play.** Ailments, stations and items use **emoji icons** (placeholder art) and colour. Any
  on-screen words are ≤ 6.
- **Mobile-first.** Buttons ≥ 56 px tall, prompts with `RequiresLineOfSight = false`, no dragging, no precision timing.
- **No streaks, no timed offers, no paid random items, no off-platform links.** Nothing paid exists in this build.
- **Original only.** No other game's names, characters, art or sounds. Only `rbxasset://` built-in sounds, plus the
  existing licensed music IDs in `Config.Music`.
- **File ownership is strict.** Edit only the files your task owns. Need a change in another task's file? Don't make
  it; list it under "Requests for other files" in your final report.
- **No commits and no Studio in Tasks 1–8.** Only Task 9 commits and uses Studio MCP.
- **Before finishing any task,** run from `game/`: `selene src` and `stylua --check src`, both clean for your files.
  Run `lune run tests/run` if `lune` exists; otherwise say "Lune not installed, specs not run".
- **Style:** `--!strict` on new modules where practical. Tabs; StyLua formats. One responsibility per file.

## Review Focus
1. **The plot owner leaves mid-cure.** Patients, carry visuals and prompts on that plot are cleaned up with no errors,
   and the plot is free for the next joiner (Task 0 Plots, Task 1 Patients).
2. **A 7th player joins when 6 plots are taken.** They get no plot, but can visit, help (if allowed) and leave hearts.
   A toast explains it, and nothing errors. Also set place Max Players = 6 (Task 0, Task 9).
3. **The DataStore fails on load.** The game plays and never saves over the real data, and a toast warns (Task 0).
4. **A client sends junk to a remote:** wrong types, unknown ids, spam, buying a room on someone else's plot. The
   server rejects it with a message and state is unchanged (Task 3, Task 5).
5. **UTC midnight passes mid-session.** Today's Visitor, the daily goals and the story-day gate roll over without a
   rejoin (Task 4, Task 5).

---
## A. File ownership map (`game/`)
| Task | Owns (create or modify) |
|---|---|
| 0 Foundation | `src/shared/{Types,Config,Remotes}.luau` · `src/shared/Data/*.luau` · `src/shared/Logic/Schema.luau` · `src/server/{Main.server,PlayerData,State,Plots,PlotBuilder}.luau` · stubs for every other module in §B · `src/client/Main.client.luau` · `src/client/UI/{Theme,Kit}.luau` · `tests/run.luau` · `tests/expect.luau` · `tests/Schema.spec.luau` · deleting `src/server/{ShopWorld,Customers,Kitchen}.luau` |
| 1 Patients | `src/server/Patients.luau` · `src/server/CreatureBuilder.luau` |
| 2 Stations | `src/server/Stations.luau` · `src/server/Carry.luau` |
| 3 Economy | `src/server/{Economy,Cure,Progress}.luau` · `src/shared/Logic/{Pay,Prices,Progress}.luau` · `tests/{Pay,Prices,Progress}.spec.luau` |
| 4 Story & Book | `src/server/{Book,Story}.luau` · `src/shared/Logic/{Book,Story}.luau` · `tests/{Book,Story}.spec.luau` |
| 5 Daily & social | `src/server/{Daily,DayReport,DayNight,Events,Visits}.luau` · `src/shared/Logic/Daily.luau` · `tests/Daily.spec.luau` |
| 6 UI | `src/client/UI/{Hud,Shop,BookPanel,DayReportPanel,Mailbox,Guide,Toasts}.luau` |
| 7 Feel | `src/client/Feel/{CureFX,Sounds,Atmosphere}.luau` · `src/server/DecorBuilder.luau` · `src/client/Music.client.luau` (keep; adapt only if needed) |
| 8 Docs | `docs/guides/build-the-clinic.md` · `game/README.md` · `docs/guides/quick-words.md` |
| 9 Integration | anything, to fix integration bugs; commits |

`src/client/RoofFade.client.luau` (the other agent's) stays as is.

## B. Contracts (every task codes against these exact names)
### B1. Instances and attributes
- `Workspace.Clinics` (Folder) holds `Plot_1` to `Plot_6` (Model).
  - **Plot attributes:** `PlotIndex: number`, `OwnerUserId: number` (0 = free), `OpenHelpers: boolean`, `Hearts: number`.
  - **Plot children:**
    - `Ground` (Part)
    - `Sign` (Part, with SurfaceGui `SignGui` and TextLabels `OwnerName` and `HeartCount`)
    - `Counter` (Part)
    - `QueueStart`, `PatientSpawn`, `PatientExit` (invisible marker Parts)
    - `Slots` (Folder of invisible Parts `RoomSlot_<SlotId>`)
    - `Rooms` (Folder of placed room Models `Room_<RoomId>`)
    - `Patients` (Folder)
    - `Decor` (Folder)
- **Room models.** A room Model's `PrimaryPart` is `Floor`, and the room is placed so that `Floor.CFrame` equals its
  slot's CFrame. Inside a room:
  - `Station_<StationId>` (Part; holds the make prompt)
  - `Bed_<n>` (Part)
  - `DecorSlot_<n>` (invisible Part)
  - A slot is addressed as `"<RoomId>:<n>"`.
- **Kit overrides.** If `ServerStorage.ClinicKit.<RoomId>` (Model) exists, PlotBuilder clones it instead of the
  placeholder. If `ServerStorage.Creatures.<PatientId>` exists, CreatureBuilder clones it.
- **Town.** It's centred at `Config.Town.Origin = Vector3.new(0, 0, 300)`, away from the brother's `Workspace.Shop`
  (**never touched**). Plots are 70×70, two rows of three facing a central street. `Workspace.TownSpawn` (a
  SpawnLocation) sits at the town centre.
- **Player attributes (server sets them, the client reads them):**
  - `PlotIndex: number`
  - `Carry: string` (comma-joined item ids, e.g. `"Potion,Plaster"`)
  - `CarryMax: number`
  - `Stars: number`
  - `Cured: number`
  - `DataOk: boolean`
  - leaderstats `Cash` and `Stars` (IntValue)
- **Workspace attributes:**
  - `IsNight: boolean` and `PhaseEndsAt: number` (existing)
  - `IsWinter: boolean`
  - `UtcDay: number` (`os.time() // 86400`, refreshed each minute)
  - `TodaysVisitor: string` (PatientId)

### B2. Data modules (`src/shared/Data/`, plain tables, no Color3 at the top level in Logic paths)
- `Ailments`: `{ [AilmentId]: { Icon: string, Color: Color3, Station: StationId } }`.
  - Ids: Hiccups, Sneezes, Bump, Scrape, Sticky, Muddy, Chills, FrozenNose, Cough, LostGlow.
- `Stations`: `{ [StationId]: { Name: string, Icon: string, Item: ItemId, Color: Color3 } }`.

  | StationId | Item | Icon |
  |---|---|---|
  | Remedy | Potion | 🧪 |
  | Plaster | Plaster | 🩹 |
  | Bath | Bubbles | 🛁 |
  | Cocoa | Cocoa | ☕ |

- `Patients`: `{ [PatientId]: { Name: string, Ailment: AilmentId, Night: boolean?, Wing: WingId, Look: {...} } }`.
  `Look` is the CreatureBuilder recipe: body shape, colours, ears/hat. Placeholder names are original and silly; the
  brother renames them later.

  | Wing | Patients |
  |---|---|
  | Starter | DumplingFrog (Hiccups) · CloudSheep (Sneezes) · ToastPup (Bump) · JellyBun (Scrape) |
  | Bath | SlimeCat (Sticky) · MossMole (Muddy) |
  | Winter | SnowconePenguin (Chills) · IcicleOwl (FrozenNose) |
  | Night (Night = true) | HiccupGhost (Cough) · MoonMoth (LostGlow) |

- `Regulars`: three regulars, each with:
  - `Patient` (a PatientId-like look);
  - `Ailment`;
  - `UnlockStars`: 0, 40, 120;
  - five `Beats`, each `{ Emote: string, Bubble: string (≤ 6 words) }`;
  - a `Reward` that's a DecorId or RoomId.

  | Regular | Arc |
  |---|---|
  | ShySprout | Scared of the clinic → becomes your mascot |
  | GrumpyTeapot | Grumpy → gives you their lucky kettle (decor) |
  | DizzyComet | Lost → finds the way home and lights your sign (night) |

- `Rooms`: `{ [RoomId]: { Slot: SlotId, Price: number, StarsNeeded: number, Stations: {StationId}, Beds: number, DecorSlots: number, Wing: WingId } }`.

  | RoomId | Slot | Price | Stars | Stations | Beds | Decor slots |
  |---|---|---|---|---|---|---|
  | Stand | Stand | free | 0 | Remedy, Plaster | 1 | 2 |
  | BathRoom | A | 150 | 10 | Bath | 0 | 1 |
  | Ward | B | 300 | 25 | – | 2 | 2 |
  | WinterWing | C | 500 | 40 | Cocoa | 1 | 2 |
  | Garden | D | 800 | 70 | – | 0 | 3 |

- `Upgrades`: `{ [Id]: { Name, Icon, Prices: {number} } }` (`Upgrades.Order` lists the ids).

  | Id | Prices |
  |---|---|
  | Speed | {50, 150, 400, 900, 2000} |
  | Tray | {100, 500, 1500} |
  | Chairs | {75, 250, 600} |
  | Tips | {75, 250, 600, 1400, 3000} |

- `Decor`: about 12 items `{ [DecorId]: { Name, Icon, Price: number?, EarnedBy: string?, Look } }`. Price nil means
  earned only (book set, story, referral).
- `DailyGoals`: a pool of `{ Id, Kind: "Cure"|"CureNight"|"Make"|"CureWing", Target: number, Wing: WingId?, Reward: {Cash: number, Stars: number} }`.
- `Config` (existing file; keep Music and GamePasses):
  - `BasePay = 12`, `QuickServeBonus = 0.5`, `NightPayMultiplier = 2`, `SparklyChance = 0.03`, `SparklyMultiplier = 2`
  - `VisitorMultiplier = 3`, `FrostyChance = 0.25`, `FrostyMultiplier = 1.5`
  - `PatienceSeconds = 60`, `ChairsPatienceBonus = 10`, `MaxQueue = 4`, `SpawnEverySeconds = 7`, `RecoverSeconds = 4`
  - `BaseMakeSeconds = 2`, `MinMakeSeconds = 0.5`, `DaySeconds = 420`, `NightSeconds = 180`
  - `Winter = { Start = "2026-12-01", End = "2027-01-10" }`
  - `MailboxGiftCash = 25`, `MaxBankedGoals = 3`, `DataStoreName = "PlayerData_v2"`, `AutosaveSeconds = 90`
  - `Town = { Origin = Vector3.new(0, 0, 300), PlotSize = 70, Plots = 6 }`

### B3. Save schema v2 (`Logic/Schema`)
```lua
type Data = {
  Version: number, -- 2
  Cash: number, Stars: number, Cured: number,
  Upgrades: { [string]: number },                       -- Speed, Tray, Chairs, Tips
  Rooms: { [string]: boolean },                         -- Stand = true by default
  Decor: { Owned: { [string]: boolean }, Placed: { [string]: string } }, -- slotKey -> DecorId
  Book: { [string]: { Cured: number, Variants: { [string]: boolean } } },
  Story: { [string]: { Beat: number, LastBeatDay: number } },
  Daily: { Goals: { { Id: string, Progress: number, Day: number } }, LastGrantDay: number },
  Mailbox: { LastSeenDay: number },
  HeartsGiven: { Day: number, Plots: { [string]: boolean } }, -- by owner UserId string
  ReferralRewarded: boolean,
}
```
`Schema.default(): Data` and `Schema.reconcile(saved: any): Data`. `reconcile` migrates v1 `{Cash, Served, Upgrades}`:
`Served` → `Cured`, and Speed/Tray/Tips are kept. Unknown fields are dropped and bad types replaced by defaults.

### B4. Remotes (`ReplicatedStorage.Remotes`, created by `Shared/Remotes`)
- **Events, server → client:**
  - `Toast(text: string)`
  - `State(snapshot: Snapshot)`
  - `Cured(info: { PatientId, Variant: string?, Cash: number, Stars: number, NewPage: boolean, Position: Vector3, Helper: number })`
  - `DayReport(report: { Cured: number, NewPages: {string}, StarsGained: number, Next: { Kind: string, Id: string, Icon: string } })`
- **Functions, client → server:** each returns `(ok: boolean, message: string)` except `GetState`.
  - `Purchase(kind: "Upgrade"|"Room"|"Decor", id: string)`
  - `PlaceDecor(slotKey: string, decorId: string?)`
  - `ClaimGoal(index: number)`
  - `ClaimMailbox()`
  - `GetState() -> Snapshot`
- **Snapshot:** the player's `Data` fields `Upgrades`, `Rooms`, `Decor`, `Book`, `Story`, `Daily`, plus:
  - `Cash`, `Stars`
  - `MailboxReady: boolean`
  - `PlotIndex: number?`
  - `TodaysVisitor: string`
  - `IsWinter: boolean`

### B5. Server module APIs
Signals are `BindableEvent`s exposed as `.Event`. Every module has `start()`. Task 0 creates each as a stub with these
exact signatures, returning safe defaults.
- **PlayerData:**
  - `get(p): Data?`
  - `update(p, fn: (Data) -> ())`: mutates the data, marks it dirty and calls `State.push(p)`
  - `waitLoaded(p): Data?`
  - `Loaded: BindableEvent(p, data)`
- **State:**
  - `push(p)`: debounced 0.2 s; builds the Snapshot and fires the State remote
  - `snapshot(p): Snapshot`
  - wires `GetState`
- **Plots:**
  - `getPlot(p): Plot?`
  - `ownerOf(plotModel): Player?`
  - `all(): {Plot}`
  - `canWork(p, plot): boolean` (owner, owner's friend via `IsFriendsWith` cached at join, or `OpenHelpers`)
  - `unlockRoom(owner, roomId): boolean`
  - `placeDecor(owner, slotKey, decorId?): boolean`
  - signals `PlotAssigned(p, plot)`, `PlotReleased(p, plot)`, `RoomAdded(plot, roomId, roomModel)`
  - The `Plot` type is `{ Index: number, Model: Model, Owner: Player?, Counter: BasePart, QueueStart: BasePart, Spawn: BasePart, Exit: BasePart }`.
- **PlotBuilder:**
  - `buildTown(): {Model}`
  - `buildRoom(roomId): Model`
  - `clearPlot(plotModel)`
- **Carry:**
  - `items(p): {string}`
  - `capacity(p): number`
  - `add(p, itemId): boolean`
  - `take(p, itemId): boolean`
  - `clear(p)`
  - keeps `Carry` and `CarryMax` attributes and the hand visual in step
- **Stations:** prompts on every `Station_*` of every placed room. Hold for `Prices.makeSeconds(level)`; the server
  checks hold time (as in today's `Kitchen`) → `Carry.add`.
- **Patients:**
  - spawns per owned plot, with up to `MaxQueue` in the queue
  - a `Treat` prompt on `Counter` treats the front patient: `canWork`, then `Carry.take(matchingItem)`, then the bed
    (or recover in place), then after `RecoverSeconds` calls `Cure.resolve(ctx)`
  - asks `Story.dueRegular(owner)` and `Daily.visitorFor(owner)` when choosing whom to spawn
  - shows a regular's `Story.bubble(owner, regularId)`
- **Cure:** `resolve(ctx: { Helper: Player, Owner: Player, PatientId: string, Variant: string?, Night: boolean, Regular: string?, Visitor: boolean, PatienceLeft: number, Position: Vector3 })`. It calls, in order:
  - `Pay.reward`
  - `Economy.addCash(helper)`
  - `Progress.addStars(owner)`
  - `Book.stamp(helper)`
  - `Daily.onCure(helper, ctx)`
  - `Story.onCure(owner, regular)`
  - `DayReport.record(...)`
  - then fires `Cured` to the helper (and to the owner if different)
- **Economy:**
  - `addCash(p, n)`
  - `spendCash(p, n): boolean`
  - `level(p, upgradeId): number`
  - `purchase(p, kind, id): (boolean, string)`: rooms need ownership of a plot, `StarsNeeded` and the price; it calls
    `Plots.unlockRoom`
  - wires `Purchase` and `PlaceDecor`
- **Progress:**
  - `addStars(p, n)`
  - `nextGoal(p): {Kind, Id, Icon}`
- **Book:** `stamp(p, patientId, variant?): (newPage: boolean, newVariant: boolean)`. It grants a wing's set reward
  decor when the set completes.
- **Story:**
  - `dueRegular(owner): string?`
  - `onCure(owner, regularId)`
  - `bubble(owner, regularId): { Emote: string, Bubble: string }`
- **Daily:**
  - `visitorFor(p): string?` (today's visitor, once per player per UTC day)
  - `onCure(p, ctx)`
  - `onMake(p, itemId)` (Stations calls it)
  - mailbox and goals on join
  - wires `ClaimGoal` and `ClaimMailbox`
  - keeps `Workspace.UtcDay` and `TodaysVisitor` up to date
- **DayReport:**
  - `record(p, ctx, newPage, stars)`
  - `flush()`: DayNight calls it at the end of each night, and it sends DayReport to everyone
- **DayNight:** the existing cycle with the new lengths; calls `DayReport.flush()` when night ends.
- **Events:** `isWinter(): boolean` (Config window or `Workspace.ForceWinter`); sets `Workspace.IsWinter`.
- **Visits:**
  - a heart prompt on each `Sign` for non-owners, once per owner per UTC day
  - an owner prompt on the `Sign` that toggles `OpenHelpers`
  - the referral reward via `GetJoinData().ReferredByPlayerId`: a one-time decor `FriendBench` for the joiner, and for
    the referrer if they're in the server

### B6. Logic APIs (pure; tests in `game/tests/`)
- **Schema:** `default()`, `reconcile(saved)`.
- **Pay:** `reward({ BasePay, Tips: number, PatienceLeft: number, Night: boolean, Variant: string?, Visitor: boolean, Regular: boolean, Cfg }) -> { Cash: number, Stars: number }`.
  - Stars: 1, or 2 for night, 3 for regulars or visitors.
- **Prices:**
  - `upgradePrice(upgrades, id, level): number?`
  - `makeSeconds(speedLevel, cfg): number`
  - `capacity(trayLevel): number` (`= 1 + level`)
  - `patience(chairsLevel, cfg): number`
- **Progress:**
  - `canBuyRoom(data, room, roomId): (boolean, string)`
  - `nextGoal(data, rooms, upgrades): { Kind, Id }`
- **Book:**
  - `stamp(book, patientId, variant?): (boolean, boolean)`
  - `setComplete(book, patientIds: {string}): boolean`
- **Story:**
  - `unlocked(regulars, stars): {string}`
  - `due(entry?, today): boolean`
  - `advance(entry?, today): { Beat, LastBeatDay }`
  - `finished(entry?, beats): boolean`
- **Daily:**
  - `day(unix): number`
  - `visitor(day, pool: {string}): string` (deterministic)
  - `grant(daily, today, pool, max): daily` (adds one goal per new day, capped at `max`, never removes progress)
  - `onEvent(daily, kind, ctx): daily`
  - `claim(daily, index, pool): (daily, reward?)`
  - `mailboxReady(lastSeenDay, today): boolean`

---
## C. Tasks
### Task 0: Foundation (runs alone, first)
**Files:** see §A. **Produces:** everything in §B, with stubs for Tasks 1–5 and 7 that `require` cleanly and return
safe defaults, so the game boots before any parallel task lands.
- [ ] Write `tests/expect.luau` (`expect(x).toBe(y)`, `.toEqual(t)` deep, `.toBeTruthy()`) and `tests/run.luau`. The
  runner requires every `*.spec.luau` via `@lune/fs`, prints pass/fail counts, and exits 1 on any failure.
- [ ] Write `tests/Schema.spec.luau`:
  - `default().Version == 2`
  - `default().Rooms.Stand == true`
  - `reconcile({Cash=50, Served=7, Upgrades={Speed=2,Tray=1,Tips=3}})` gives Cash 50, Cured 7, Speed 2, Tray 1, Tips 3,
    Chairs 0
  - `reconcile("junk")` returns defaults
  - `reconcile({Cash="x"}).Cash == 0`
- [ ] Implement `Logic/Schema.luau` to pass (run `lune run tests/run` if available).
- [ ] Create `Types.luau`, `Data/*.luau` (all content in §B2), and update `Config.luau` (§B2 values; remove the
  Product, Treat and Customer fields; keep Music and GamePasses).
- [ ] Rewrite `Remotes.luau` for §B4.
- [ ] Write `PlayerData.luau` (v2):
  - `UpdateAsync` writes;
  - never saves after a failed load (sets `DataOk=false` and toasts "Saving is off");
  - autosave plus `BindToClose`;
  - leaderstats `Cash` and `Stars`.
- [ ] Write `State.luau`.
- [ ] Write `PlotBuilder.luau`: a cozy placeholder town and plots, with every marker in §B1 and each room placeholder
  matching `Data/Rooms` stations, beds and decor slots. Then write `Plots.luau`: assign on join, release on leave
  (destroy patients, rooms other than the Stand, decor), rebuild rooms and decor from data on assign, and run
  `canWork`.
- [ ] Write stubs with the §B5 signatures for: Patients, CreatureBuilder, Stations, Carry, Economy, Cure, Progress,
  Book, Story, Daily, DayReport, Events, Visits, DecorBuilder.
- [ ] Rewrite `Main.server.luau`: the existing collision groups, then `start()` in this order: PlayerData, State,
  Events, Plots, Carry, Economy, Progress, Book, Story, Daily, DayReport, Stations, Patients, Visits, DayNight. Print
  `[Main] Clinic is open.`
- [ ] Delete `ShopWorld`, `Customers` and `Kitchen` (their ideas move to Patients, Stations and Feel).
- [ ] Write the client: `Main.client.luau` requires the UI and Feel modules if they exist (`pcall` each), wires the
  remotes, and calls each module's `init(ctx)`. `ctx = { Remotes, Config, Data, State = latest snapshot, onState: (fn) -> () }`.
  Also write `UI/Theme.luau` (palette, fonts, sizes) and `UI/Kit.luau` (`panel`, `button` with press bounce, `label`,
  `iconButton`, `corner`, `pad`).
- [ ] Verify: `selene src` and `stylua --check src` are clean. Specs pass (or "not installed"). Rojo can build:
  `rojo build -o $env:TEMP\check.rbxl`.

### Task 1: Patients and creatures
**Consumes:** Plots, Carry, Cure, Story, Daily, Prices.patience, Data. **Produces:** the Patients behaviour in §B5,
plus `CreatureBuilder.build(patientId, variant?): Model`.
- [ ] `CreatureBuilder`: a cute, original placeholder creature from `Look` (round body, big eyes, cheeks, ears or hat,
  colours). Night patients glow (PointLight plus a soft Highlight). Sparkly gets a sparkle ParticleEmitter, Frosty an
  icy tint. An `IconAnchor` Attachment carries the ailment-icon BillboardGui (big emoji plus a patience ring). Uses the
  kit override if present. Under 40 parts per creature.
- [ ] `Patients`:
  - **Movement:** tween-based hopping (anchored, `PivotTo` via a CFrameValue tween, a small bob), no Humanoids.
  - **Spawning:** a queue per plot. Night patients only at night. A Winter patient only if the WinterWing is owned. A
    patient's ailment station must be one the plot owns. Sparkly at `SparklyChance`, Frosty in winter at `FrostyChance`.
  - **Visitors and regulars:** Today's Visitor via `Daily.visitorFor` (badge ⭐). A regular via `Story.dueRegular`,
    showing a speech bubble with `Story.bubble`.
  - **Treating:** the `Treat` prompt on the Counter, with ActionText `Treat` and ObjectText as the ailment icon.
  - **Wrong item:** a head-shake and a toast with the right station icon.
  - **Beds:** go to a free `Bed_*` if any, otherwise recover in place. After that, `Cure.resolve`, a happy hop, then
    exit.
  - **Patience:** when it runs out, the patient leaves with a sad puff. No penalty.
  - **Cleanup:** on `PlotReleased`.
- [ ] Verify statically (selene, stylua). Integration tests it in Studio.

### Task 2: Stations and Carry
**Consumes:** Plots (`RoomAdded`, `canWork`), Economy.level, Prices, Daily.onMake. **Produces:** Carry (§B5), and
Stations wiring the existing hold-check pattern from `Kitchen` with the server timing check.
- [ ] `Carry`: an item list per player; `CarryMax` from Tray; a hand visual (a small icon cube or BillboardGui above
  the head showing the item emojis); cleared on death or leave.
- [ ] `Stations`:
  - a prompt per `Station_*`: ActionText "Make", ObjectText the station icon, HoldDuration from Speed;
  - client-side HoldDuration refresh through the `Speed` level in State (Task 6 reads it);
  - a "Tray full" toast;
  - `canWork` enforced;
  - sparkle burst (keep the other agent's sparkle idea).

### Task 3: Economy, Cure, Progress
**Files and tests:** §A.
- [ ] Write specs first:
  - `Pay.spec`:
    - base 12 with Tips 0 and PatienceLeft 1 gives Cash 18 (12 × 1.5) and Stars 1;
    - Night doubles cash and gives Stars 2;
    - Sparkly ×2;
    - Visitor ×3 with Stars 3;
    - Cash never below 1.
  - `Prices.spec`:
    - `upgradePrice(Upgrades, "Speed", 0) == 50`;
    - Speed at max level returns nil;
    - `makeSeconds(0) == 2`;
    - `makeSeconds(99) == 0.5`;
    - `capacity(2) == 3`.
  - `Progress.spec`: `canBuyRoom` is false with "Need ⭐10" when Stars 5, false when already owned, and true when Stars
    and Cash are enough.
- [ ] Implement the Logic modules, then the server modules.
- [ ] `Purchase` validation: kind and id are strings in the known sets; Room needs the caller to own a plot; Decor
  needs a Price. `PlaceDecor` slotKey must exist on the caller's plot, and the decor must be owned. Rate limit.

### Task 4: Patient Book and Story regulars
- [ ] Write specs first:
  - `Book.spec`:
    - a first stamp is `(true, false)`;
    - a repeat with no variant is `(false, false)`;
    - a new variant is `(false, true)`;
    - `setComplete` is true only when every id has `Cured ≥ 1`.
  - `Story.spec`:
    - `unlocked(regs, 0)` is `{ShySprout}`;
    - `unlocked(regs, 120)` lists all 3;
    - `due(nil, 100)` is true;
    - `due({Beat=1, LastBeatDay=100}, 100)` is false and `due(..., 101)` is true;
    - `advance` increments Beat and sets the day;
    - `finished` at Beat 5.
- [ ] Implement them. On finishing, the story reward is granted (decor owned, or room unlocked free via
  `Plots.unlockRoom`) with a toast. Book set rewards: Starter set → `HeartRug`, Bath set → `RubberDuckFountain`,
  Winter set → `SnowGlobeLamp`.

### Task 5: Daily, mailbox, Day Report, day/night, winter, hearts and helpers, referral
- [ ] Write `Daily.spec` first:
  - `visitor(day, pool)` is stable for the same day and changes across ≥ 3 of 7 days;
  - `grant` adds 1 goal per new day up to max 3 and never removes progress;
  - `onEvent` raises Cure progress;
  - `claim` before the target returns nil, and on reaching it returns the reward and removes the goal;
  - `mailboxReady(5, 5)` is false and `mailboxReady(4, 5)` is true.
- [ ] Implement:
  - **Workspace attributes:** `UtcDay` and `TodaysVisitor`, updated each minute.
  - **Mailbox:** `ClaimMailbox` gives `MailboxGiftCash` once per UTC day. It's the same however long you were away.
  - **Day Report:** per-player counters, flushed at night's end.
  - **DayNight:** keeps the Lighting tweens but softer (night `Brightness` 1.2, purple-blue `Ambient`), and the new
    lengths.
  - **Events:** sets `IsWinter`.
  - **Visits:** hearts update `Hearts` on the owner's plot and the sign; the OpenHelpers toggle with a toast; the
    referral.

### Task 6: Client UI (mobile-first; load `roblox-ui` and `game-ui-ux`)
**Consumes:** `ctx` from Task 0, the Snapshot, and the remotes. Each module exports `init(ctx)`.
- [ ] **Hud:** Cash and ⭐ Stars (with a progress bar to the next unlock), the carry icons from the `Carry` attribute,
  and the Day/Night timer. Big bottom buttons: 🛒 Shop · 📖 Book · 📬 Mail (dot when `MailboxReady`) · 🎯 Goals.
- [ ] **Shop:** tabs Upgrades / Rooms / Decor. Locked rooms show ⭐ needed. Buy calls `Purchase`. A Decor place mode
  lists your plot's empty slots as big buttons, then calls `PlaceDecor`.
- [ ] **BookPanel:** a grid of patient cards by wing. Unseen patients are dark silhouettes with "?", seen ones show the
  icon, name and variant stickers. Set progress per wing.
- [ ] **DayReportPanel:** a pop-up at night's end with a big number of patients cured, new pages and the Next goal
  icon. Auto-close after 8 s.
- [ ] **Mailbox:** a pop-up on join if ready (a letter animation) with a claim button. Goals: a list of up to 3 with
  progress bars and claim buttons.
- [ ] **Guide:** while `Cured < 3`, a Beam arrow from the player to the matching station when the front patient waits
  and you carry nothing, then to the Counter once you carry the right item.
- [ ] **Toasts:** a stack at top centre (reuse the current toast look).
- [ ] **Station hold time:** set the local `HoldDuration` of `Station_*` prompts from `Prices.makeSeconds(Upgrades.Speed)`.

### Task 7: Feel, sound, atmosphere, decor visuals (load `game-feel`)
- [ ] **CureFX:** on the `Cured` remote, a sparkle burst and a "+cash" pop that floats from `Position`, plus a chime.
  A NEW PAGE banner when `NewPage`.
- [ ] **Sounds:** a table of `rbxasset://sounds/...` built-in ids (chime, pop, click, whoosh) with volumes, played via
  SoundService.
- [ ] **Atmosphere:** client-side snow particles near the camera when `IsWinter`; gentle fireflies at night. Respect a
  "reduce effects" toggle stored locally.
- [ ] **DecorBuilder.build(decorId): Model:** a placeholder decor model per `Data/Decor` `Look` (rug, plant, lamp,
  fountain, bench, snow globe…), with the kit override `ServerStorage.ClinicKit.Decor.<DecorId>`.

### Task 8: Docs
- [ ] `docs/guides/build-the-clinic.md`: Part A for the brother (rewrites build-the-shop for plots).
  - How to make room models for `ServerStorage.ClinicKit`, with the exact marker names from §B1 and Assistant prompts.
  - Creatures in `ServerStorage.Creatures.<PatientId>` (with `/generate_mesh` prompts per patient, and the Minimal
    rules).
  - Decor models.
  - What happens to the old Shop (untouched).
  - Safe plugins by asset ID (`docs/research/2026-11-16-tools-and-plugins.md`).
- [ ] `docs/guides/quick-words.md`: up to 3 categories × 3–10 phrases for Creator Hub Quick Words ("I'll do the
  bath!", "Need plasters!", "Night patients coming!", "Thank you!") and the steps to set them.
- [ ] `game/README.md`: the new file table, the boot order, how to test (Lune and Studio), and the new playtest
  checklist (§D).

### Task 9: Integration and playtest (runs alone after 1–8; uses Studio MCP and owns commits)
- [ ] Merge any "Requests for other files" from Tasks 1–8. Run selene, stylua and the specs.
- [ ] Confirm Rojo is connected (the scripts exist in Studio). Set Max Players to 6 (Game Settings → Places), or note
  it for Joshua.
- [ ] Playtest via MCP (`start_stop_play`, `get_console_output`, `execute_luau` on Server and Client) against §D. Fix
  the files (never the Studio scripts) and re-test. Use `Workspace:SetAttribute("ForceWinter", true)` and a short
  `DaySeconds` for testing, then restore.
- [ ] Commit in logical commits on `claude/trusting-carson-5v32sr` with the Co-Authored-By line.

### Task 10: Review
- [ ] A fresh reviewer (the `code-review` skill or the `superpowers:requesting-code-review` flow) reviews the whole
  diff against the spec, the Global Constraints and the Review Focus. Task 9's agent fixes the confirmed findings and
  re-tests.

## D. Playtest checklist (Task 9)
1. Output shows `[Main] Clinic is open.` and no red errors. The town shows 6 plots, you get one, and its sign shows
   your name.
2. The first patient arrives within 60 s with an icon. The guide arrow points to the station. Hold → carry icon → the
   arrow points to the Counter → Treat → bed → cured → cash and ⭐, with sparkle and chime.
3. A wrong item gives a head-shake and a hint. Patience running out means a sad puff and no penalty.
4. Upgrades buy and change the hold time, tray, patience and tips. The Bath Room unlocks at ⭐10 and 150 cash, appears
   in its slot, and its station works. Bath patients start arriving.
5. Patient Book: first cure gives NEW PAGE, the silhouette fills in, and completing the Starter set grants HeartRug.
6. Decor: buy, place in a slot, and it appears. Leave and rejoin, and the same decor is there.
7. Night: night patients glow, pay 2×, and the Day Report pops at night's end.
8. Winter (`ForceWinter`): it snows, Frosty variants appear, the WinterWing can be bought, and its Cocoa station
   works.
9. Today's Visitor ⭐ shows up once. A daily goal fills and is claimed. The mailbox gift works once.
10. ShySprout appears and the bubble shows beat 1. A second cure the same UTC day doesn't advance it. Simulate the next
    day via `execute_luau` (set `LastBeatDay` back) and it advances.
11. Hearts: a heart from a second client counts once a day. The OpenHelpers toggle works. A non-friend can't treat
    when closed.
12. Rejoin keeps everything. Junk remote calls from `execute_luau` on the Client are rejected.

## E. Joshua: one command (Lune, for the tests)
In `game\`, run `rokit add lune-org/lune@0.11.1` and answer **y** to trust it. Until then, the specs exist but don't
run.
