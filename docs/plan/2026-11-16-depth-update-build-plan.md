# Depth update (Update 1) build plan: contracts, file ownership, playtest

> **For agentic workers:** this plan runs as a **parallel team**. Task 0 (Foundation) is committed first and is
> **frozen**. Tasks T1–T7 then run at the same time, each editing **only the files it owns** (§A). Anything you need
> in a file you don't own goes in your final report under **Requests** (file, where, exact change). The lead
> integrates, playtests in Studio and commits. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Update 1 of Cure a Creature: recipes + treatment mini-games, the shared Nurse Belt with the Nurse Journal
and the scheduled Mythic/Secret rarities, nurse workers on your plot, hospital levels (the building grows), UI juice
and a performance pass.

**Spec:** `docs/plan/2026-11-16-depth-update-design.md` (read it; §2 has the Journal and the Mythic/Secret rarities).
**Rulings:** `memory/records/memory-20261116-008` (levels), `-011` (mini-games, recipes, no Robux), `-012` (the
shared belt, set times), `-013` (journal, Mythic in Night Rush, Secret in Golden Hour). **Code map:**
`game/README.md`. **The shipped game's contracts** (still law where this plan doesn't change them):
`docs/plan/2026-11-16-creature-clinic-build-plan.md` §B.

**Tooling** (PowerShell, from `game/`):
```powershell
& "$env:USERPROFILE\.rokit\bin\stylua.exe" src tests
& "$env:USERPROFILE\.rokit\bin\selene.exe" src                 # 0 errors, 0 warnings
& "$env:USERPROFILE\.rokit\bin\lune.exe" run tests/run
& "$env:USERPROFILE\.rokit\bin\rojo.exe" build default.project.json -o "$env:TEMP\depth-check.rbxl"
```

## Global constraints (every task)
- **Kids' rules (CLAUDE.md red line 3).** No Robux anywhere in these features. The belt shows its odds (all of them,
  event odds too). No fail states: an OK rating still cures. No real-world timers or pressure: Night Rush runs on the
  game's day/night clock and Golden Hour on server uptime. Every motion honours `Kit.reducedMotion()` (Reduced Motion
  or the ✨/💤 calm switch). Simple mode exists. On-screen words ≤ 6, icons first, buttons ≥ 56 px tall.
- **Original only (red line 2).** The conveyor belt is a borrowed *format*. Every nurse, name, look and sound is ours.
  Built-in `rbxasset://` sounds only (or licensed Creator Store sounds the lead adds).
- **The server is authoritative.** Every remote is wired with `Remotes.serve` (10 calls/s per player per remote,
  pcall) and checks types, ids (with `rawget`, so a Data map's `Order` is never an id), ownership, distance and
  cooldowns. Prices, odds and rewards come from `Config`/`Shared/Data` only, never the client. Charge and grant in
  ONE `PlayerData.update` with no yield in between.
- **Change the save only through `PlayerData.update(p, fn)`.** Never write `Data` fields this plan doesn't list.
- **File ownership is strict (§A).** The Foundation layer (Config, Types, Remotes, Schema, State, PlayerData,
  Data/*, Logic/*, Main.server, Main.client, tests, README) is frozen after Task 0: request changes, don't make them.
- **No commits, no Studio, no push in T1–T7.** The lead integrates and playtests.
- **Before you finish:** stylua, selene (0/0), lune (all pass) and the rojo build, as above.
- **Style:** `--!strict`, tabs, a header comment that lists the module's API (like the existing modules), one
  responsibility per file, other systems called through `pcall` where a bug there must not break yours.

## Review focus
1. **A cheating client** sends junk to `TreatResult`, `HireNurse`, `EquipNurse`, `LevelUp`, `SetSimple`: wrong
   types, unknown ids, another player's session, a report 0.1 s after the start, spam. Nothing pays more than one
   capped tip, nothing is hired twice, nobody hires from across the map, and state is unchanged on a rejection.
2. **The owner leaves** mid-mini-game, mid-hire, with nurses equipped: sessions, riders, nurse models and the nurse
   tray clean up with no errors; the plot is clean for the next owner.
3. **An existing save** (no `Level`, no nurses) loads at the level its rooms imply, with an empty journal, and an
   old server never writes a new save back down (Schema v3, `isNewer`).
4. **Performance:** 6 full plots + the belt hold 60 fps on a mid phone; no per-frame server CFrame writes for
   creatures or riders; ≤ 1 Highlight in the world; no shadow-casting lights.

---
## A. File ownership (`game/`)
Each file has exactly one owner. **New** files are marked ✚. Task 0 created a stub for every ✚ file with the exact
API in §B8/§B9, so everything requires and boots before any task lands.

| Task | Owns (create or modify) |
|---|---|
| **0 Foundation** (frozen) | `src/shared/{Config,Types,Remotes,Palette,Signal}.luau` · `src/shared/Data/*.luau` (✚ `Nurses`, ✚ `Rarities`, ✚ `Levels`) · `src/shared/Logic/*.luau` (✚ `Recipe`, ✚ `MiniGame`, ✚ `Belt`, ✚ `Levels`, ✚ `Nurse`) · `src/server/{Main.server,PlayerData,State}.luau` · `src/client/Main.client.luau` · `tests/*` · `game/README.md` |
| **T1 Treatment server** | `src/server/Patients.luau` · `src/server/Cure.luau` · `src/server/Stations.luau` · `src/server/Carry.luau` · ✚ `src/server/Treatment.luau` |
| **T2 Mini-games client** | ✚ `src/client/UI/MiniGames.luau` |
| **T3 Nurses server** | ✚ `src/server/NurseBelt.luau` · ✚ `src/server/Nurses.luau` · ✚ `src/server/NurseBuilder.luau` |
| **T4 Nurses client** | ✚ `src/client/UI/NursePanel.luau` · ✚ `src/client/UI/BeltView.luau` |
| **T5 Hospital levels** | ✚ `src/server/Levels.luau` · `src/server/PlotBuilder.luau` · `src/server/Economy.luau` · `src/client/UI/Shop.luau` |
| **T6 UI juice** | `src/client/UI/{Kit,Theme,Hud,Toasts,BookPanel,Mailbox,DayReportPanel}.luau` · `src/client/Feel/{CureFX,Sounds}.luau` · ✚ `src/client/UI/Celebrate.luau` |
| **T7 Performance** | `src/server/CreatureBuilder.luau` · ✚ `src/client/Feel/CreatureMotion.luau` · `src/client/Feel/Atmosphere.luau` · `src/client/UI/{Guide,Tutorial,PromptFilter}.luau` · a perf budget note in `docs/plan/` (✚ `2026-11-16-perf-budget.md`) |
| **Lead (integration)** | anything, to fix integration bugs; T7's requests in `Patients.luau`/`PlotBuilder.luau`; commits |

Untouched by everyone (unless the lead): `server/{Book,Daily,DayNight,DayReport,DecorBuilder,Events,Plots,Progress,Story,Tutorial,Visits}.luau`, `client/Music.client.luau`.

Notes on shared files:
- **Hud (T6)** already has the Foundation's minimal hook: a 5th bottom button `Nurses` (👩‍⚕️) that fires
  `ctx.fire("Open", "Nurses")`, its "new" dot driven by the bus event `NursesNew (count)`, `Hud.target("Nurses")`, and
  a third ⚙️ switch for Simple mode (`SetSimple`). T6 restyles them freely but keeps those names and events.
- **Kit (T6)** already has working first versions of `Kit.countUp`, `Kit.celebrate` and `Kit.rarityFrame` with the
  §B9 signatures, so T4/T5 can call them today. T6 makes them juicy without changing the signatures.
- **CreatureBuilder (T7)** already has `CreatureBuilder.buildLook` (T3's NurseBuilder uses it) and a
  `CreatureBuilder.setRecipe` stub (T1 calls it; T7 draws it). T7 keeps both signatures.

---
## B. Contracts (every task codes against these exact names)

### B1. Save (`Logic/Schema`, **Version 3**)
The version goes 2 → 3 so an old server still running during the update loads a new save read-only
(`Schema.isNewer`) instead of writing it back without its nurses. The DataStore name stays `PlayerData_v2`.

New fields (everything from v2 is unchanged):
```lua
Level: number,                                  -- hospital level 1..5 (Data/Levels)
Nurses: { [NurseId]: { Level: number, Copies: number } }, -- hired nurses: Level 1..5 = min(Copies, 5)
Equipped: { NurseId },                          -- on duty, unique, each in Nurses, at most Level of them (slots)
NurseIndex: { [NurseId]: "Seen" | "Hired" },    -- the Nurse Journal; "Seen" never overwrites "Hired"
JournalSets: { [Rarity]: boolean },             -- journal rarity groups whose reward was granted
Simple: boolean,                                -- Simple mode: every mini-game is one tap rated Good
```
`Schema.default()`: `Level = 1`, `Nurses = {}`, `Equipped = {}`, `NurseIndex = {}`, `JournalSets = {}`,
`Simple = false`.

`Schema.reconcile` rules:
- **Level** missing (any v2 save): the level its rooms imply = the highest `Schema.ROOM_LEVELS[roomId]` over owned
  rooms, else 1. `ROOM_LEVELS = { BathRoom = 1, Ward = 2, WinterWing = 2, Garden = 3 }`: each room implies the
  highest level whose ⭐ gate is ≤ the room's own ⭐ gate (Ward ⭐25 ≥ Clinic's ⭐15; Garden ⭐70 ≥ Hospital's ⭐45).
  `Logic/Levels.impliedByRoom` computes the same thing and a spec checks they match. Present: an integer clamped to
  1..`Schema.MAX_LEVEL` (5); junk → the implied level.
- **Nurses:** string keys with a table value; `Copies` = finite integer ≥ 1 (junk → 1); `Level` = integer clamped
  to 1..min(5, Copies) (junk → min(5, Copies)). Unknown NurseIds are KEPT (like Book pages); servers ignore them.
- **Equipped:** an array of strings, in order, de-duplicated, each a key of `Nurses`, cut to `Level` entries.
- **NurseIndex:** string keys whose value is exactly `"Seen"` or `"Hired"`; every key of `Nurses` is forced to
  `"Hired"`.
- **JournalSets:** a true-set (string keys, value exactly `true`).
- **Simple:** `== true`.

### B2. Snapshot (`State.snapshot`, `Types.Snapshot`)
Everything from before, plus copies of: `Level: number`, `Nurses`, `Equipped`, `NurseIndex`, `JournalSets`,
`Simple: boolean`. The client's default snapshot (`Main.client`) has `Level = 1`, empty tables and `Simple = false`.
Slots are not sent: `Logic/Levels.slots(Data.Levels, Level)` on the client.

### B3. Remotes (`ReplicatedStorage.Remotes`, created by `Shared/Remotes`)
`Remotes.serve(name, handler)` now passes a **third** return value through when the handler returns a table:
`(ok: boolean, message: string, payload: table?)`. Old handlers are unaffected.

**Server → client events** (Main.client forwards each to the bus under the same name, §B9):

| Event | Payload (`Types`) | Who fires | Who listens |
|---|---|---|---|
| `TreatStart` | `TreatSession` to the treating player | T1 Treatment | T2 MiniGames |
| `NurseNews` | `NurseNews` to one player | T3 Nurses | T4, T6 |
| `Shout` | `ShoutInfo` to everyone | T3 NurseBelt | T4 BeltView (→ `Banner`) |
| `Celebrate` | `CelebrateInfo` to one player | T3 (NewNurse, JournalSet), T5 (LevelUp) | T6 Celebrate |

**Client → server functions** (all via `Remotes.serve`, 10/s per player; each returns `(ok, message)`):

| Function | Args (untrusted) | Server | Extra rules |
|---|---|---|---|
| `TreatResult` | `(session: number, ratings: { Rating })` | T1 Treatment | returns a 3rd value `TreatOutcome` on ok; §B7 MiniGame.accept |
| `SetSimple` | `(on: boolean)` | T1 Treatment (Foundation wired it; T1 keeps it) | saves `Data.Simple` |
| `HireNurse` | `(riderId: number)` | T3 NurseBelt | 3 s per-player cooldown, distance, cash, not max level |
| `EquipNurse` | `(nurseId: string, on: boolean)` | T3 Nurses | owned, slots = level |
| `LevelUp` | `()` | T5 Levels | ⭐ gate (not spent) + 💰 (spent) |

Payload types (in `Shared/Types`):
```lua
type Rating = "OK" | "Good" | "Perfect"
type GameId = "Pour" | "Patch" | "Scrub" | "Cool"
type TreatSession = {
  Session: number,         -- unique per server; the only id TreatResult accepts (per player, one open at a time)
  PatientId: string,
  Items: { ItemId },       -- what is being given now, in recipe order (1..3)
  Games: { GameId },       -- one per item (Logic/MiniGame.gameFor)
  Simple: boolean,         -- Data.Simple: the client shows one tap each; the server rates every game Good
  Combo: number,           -- the player's combo before this session
  Position: Vector3,       -- above the patient (rating pops, flying coins)
  Timeout: number,         -- seconds; after it the server settles the session as all OK on its own
}
type TreatOutcome = { Ratings: { Rating }, Tip: number, Combo: number, Complete: boolean }
type NurseNews =
    { Kind: "Seen", NurseId: string }                            -- first time this player saw it (Journal NEW!)
  | { Kind: "Hired", NurseId: string, Level: number, New: boolean } -- you hired it (New = first copy)
  | { Kind: "Equipped", NurseId: string, On: boolean }
type ShoutInfo =
    { Kind: "Arrival", RiderId: number, NurseId: string, Rarity: Rarity }   -- Epic and up step on
  | { Kind: "Hired", NurseId: string, Rarity: Rarity, By: string }          -- Legendary and up hired (DisplayName)
  | { Kind: "Golden", On: boolean, EndsAt: number }                         -- Golden Hour starts / ends
type CelebrateInfo = {
  Kind: "LevelUp" | "NewNurse" | "JournalSet" | "Room",
  Title: string, Icon: string,                -- ≤ 3 words; an emoji
  Rarity: Rarity?, NurseId: string?, Level: number?, Cash: number?, Decor: string?,
}
```

### B4. Instances and attributes
**Patients (T1 sets; read-only for everyone else).** On each patient Model (in `Plot.Patients`), in addition to
today's attributes (`PatientId`, `Kind`, `Regular`, `Ailment`, `Station`, `Item`, `Variant`, `Night`, `QueueIndex`,
`State`):
- `Recipe: string`: the effective recipe, comma-joined ItemIds (`"Bubbles,Potion"`), already cut to the owner's
  level cap (`Logic/Recipe.effective`).
- `RecipeDone: string`: one char per recipe item, `"1"` given, `"0"` not (`"10"`). (`Logic/Recipe.encode/decode`.)
- `Item` / `Station`: the FIRST item still missing and its station (so the Guide arrow keeps working).
- `State` gains `"Treating"` (a mini-game session is open on it: patience paused, nobody else can treat it).
- The badge: `CreatureBuilder.setRecipe(badge, items, done)` after every change (T7 draws small item icons that
  tick off; until then the badge's `Need` chip shows the first missing item).

**Plots (T1 / T3 / T5 set):**
- `FrontItem`, `FrontStation` (T1, unchanged meaning: the front waiting patient's first missing item).
- `FrontNeeds: string` (T1): every item the front waiting patient still needs, comma-joined ("" when none waits).
- `QueueNeeds: string` (T1): every missing item of everyone in line, front first, duplicates kept (Makers use it).
- `NurseTray: string` (T3): items nurse Makers made, comma-joined, at most `Config.Nurses.TrayMax`.
- `CheerPatience: number`, `CheerTip: number` (T3): the best equipped Cheerer's multipliers (1 = none).
- `Level: number` (T5): the owner's hospital level (1 for a free plot).
- Children: `Building` (Model, T5's PlotBuilder: the level's shell around the rooms; holds the extra
  `Bed_<n>` Parts for the level's beds) and `Nurses` (Folder, T3: the equipped nurse models).
- **Beds:** Patients finds free beds among `Bed_%d+` BaseParts under `Rooms` **and** `Building` (T1 changes
  `freeBed` and `deactivate`). The level's `Beds` count includes the Stand's own bed: Building adds `Beds − 1`.
- The Building never covers the Counter, the queue lane, the stations' prompts or the gate, and keeps the plot
  ≤ 400 parts at Lv 5 (T5 measures it).

**The belt (T3).** `Workspace.NurseBelt` (Model), built by `NurseBelt.start()` (not by PlotBuilder):
- Placed at `Config.Town.Origin + Config.Belt.Offset` (east of the plaza, on the street's centre line, riders
  move toward +X for `Config.Belt.Length` studs). Children: `BeltStart`, `BeltEnd` (invisible anchored marker Parts:
  riders go from `BeltStart.Position` to `BeltEnd.Position`), `Conveyor` (the moving-looking surface; a Texture
  scroll or a Beam on the client is fine, never a server per-frame write), `Sign` (a Part with SurfaceGui `OddsGui`:
  every current odd, the event odds, the pity count), `Riders` (Folder).
- `ServerStorage.ClinicKit.NurseBelt` (a Model with the same child names) replaces the placeholder.
- **Rider** `Riders.Rider_<RiderId>` (Model, from `NurseBuilder.build`), PrimaryPart `Root`, tag `CreatureMotion`
  NOT used (riders move by the belt formula). Attributes: `RiderId: number`, `NurseId: string`,
  `Rarity: string`, `Role: string`, `StartAt: number` (`Workspace:GetServerTimeNow()` when it stepped on),
  `RideSeconds: number`, `Hired: boolean`, `Event: string` (`""`, `"NightRush"` or `"GoldenHour"`: what rolled it).
  `Root.HireAttachment.HirePrompt` (ProximityPrompt, ActionText `"Hire"`, `RequiresLineOfSight = false`,
  HoldDuration 0, MaxActivationDistance 14).
- **Movement:** position = `BeltStart:Lerp(BeltEnd, Logic/Belt.alpha(StartAt, now, RideSeconds))`. The server
  writes `Root.CFrame` at most every `Config.Belt.ServerStepSeconds` (1 s); T4's BeltView sets it locally every
  frame (smooth). The server validates a hire against the formula, not the part.

**Workspace attributes (T3 sets):** `GoldenHour: boolean`, `GoldenStartsAt: number` and `GoldenEndsAt: number`
(both `GetServerTimeNow()` times of the current or next window), `NightRush: boolean` (= `IsNight`, mirrored by
NurseBelt so the belt has one source), `BeltPity: number` (arrivals left before a guaranteed Rare+).

**Player attributes:** `Combo: number` (T1, the mini-game combo; session-only, not saved), plus the existing
`PlotIndex`, `Carry`, `CarryMax`, `DataOk`, ...

**Nurses on a plot (T3).** `Plot.Nurses.Nurse_<NurseId>` (Model from `NurseBuilder.build`), tag `CreatureMotion`,
attributes `NurseId`, `Role`, `Rarity`, `Level`, `Task` (`"Idle"|"Making"|"Healing"|"Cheering"|"Walking"`),
`Station` (a Maker's current station, else ""). They walk with the creature-motion contract below.

**Creature motion contract (T7 client; the lead applies T7's requests in Patients; T3 uses it for nurses).**
The server stops writing `Root.CFrame` every frame. A moving creature Model carries the CollectionService tag
`CreatureMotion` and, for each hop, these attributes set together:
`HopFrom: CFrame`, `HopTo: CFrame`, `HopAt: number` (`Workspace:GetServerTimeNow()`), `HopSeconds: number`,
`HopHeight: number`, `HopSpin: number` (radians), `HopLean: number` (radians). Overlays: `ShakeAt: number`
(server time; a 0.55 s head-shake), `Tilt: number` (radians, a sad droop), and a scale animation `ScaleFrom`,
`ScaleTo`, `ScaleAt`, `ScaleSeconds` (numbers), `ScaleStyle` (`"Back"|"Sine"|"Quad"`), `ScaleDir` (`"In"|"Out"`).
The server sets `Root.CFrame = HopTo` (and the final scale) once when each animation ends, so late joiners and
server logic see the right place. T7's `Feel/CreatureMotion` renders these locally on `RenderStepped` and sleeps
when nothing moves. T1 does **not** change Patients' animator (`render`, `step`, `hop`, `scaleTo`) in this update:
the lead applies T7's version.

### B5. Data modules (`src/shared/Data/`, Lune-safe unless noted, frozen, keyed maps with `.Order`)
- **`Ailments.Recipe = { ItemId }`** (1–3 items; item 1 is always the ailment's own station item). Roblox-only
  (Color3), so `tests/Data.spec` checks it by reading the source text.

  | Wing | Ailment → Recipe |
  |---|---|
  | Starter | Hiccups 🧪 · Sneezes 🧪 · Bump 🩹 · Scrape 🩹 |
  | Bath | Sticky 🛁🧪 · Muddy 🛁🩹 |
  | Winter | Chills ☕🧪 · FrozenNose ☕🩹 |
  | Night | Cough 🧪🩹 · LostGlow 🩹🧪 |
- **`Regulars.Recipe = { ItemId }`** ("regulars their own", Stand items only): ShySprout 🧪 · GrumpyTeapot 🧪🩹🧪 ·
  DizzyComet 🩹🧪🩹. These are the game's 3-item recipes (see §E: there's no Garden wing yet).
- **The level cap** cuts every recipe to its first `Levels[level].RecipeCap` items: Lv 1 → 1 item, Lv 2 → 2,
  Lv 3+ → 3. So a new player only ever sees 1-item recipes (the tutorial is unchanged) and "Bath wing recipes" arrive
  with the Clinic (Lv 2).
- **`Rooms.Level: number?`**: the hospital level a room needs (nil = 1). Garden = 3. ⭐ gates are unchanged.
- **`Decor`** gains six journal rewards (`EarnedBy = "Journal"`): `PlasterRug`, `HeartLamp`, `StarFountain`,
  `RainbowArch`, `MoonGlobe`, `GoldenStatue` (existing DecorBuilder kinds).
- **✚ `Rarities`**: `Order = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }`; each
  `{ Name, Icon, Color (hex), Frame, Shout: boolean, Event: ("NightRush" | "GoldenHour")?, Journal = { Cash, Decor } }`.

  | Rarity | Icon | Colour | Frame | Shout | Only during | Journal set reward |
  |---|---|---|---|---|---|---|
  | Common | ⚪ | `#B4BCCB` | Grey | | | 💰300 + PlasterRug |
  | Rare | 🔵 | `#3D9BFF` | Blue | | | 💰1,000 + HeartLamp |
  | Epic | 🟣 | `#A855FF` | Purple | ✅ | | 💰3,000 + StarFountain |
  | Legendary | 🌈 | `#FFB020` | Rainbow | ✅ | | 💰8,000 + RainbowArch |
  | Mythic | 🌙 | `#FF4FB8` | Cosmic | ✅ | Night Rush | 💰15,000 + MoonGlobe |
  | Secret | 👑 | `#FFD84A` | Gold | ✅ | Golden Hour | 💰30,000 + GoldenStatue |
- **✚ `Nurses`** (16, original, placeholder names for Joshua and his brother to rename):
  `{ [NurseId]: { Name, Icon, Rarity, Role: "Maker"|"Healer"|"Cheerer", Look } }`. `Look` is the creature recipe
  (`Shape, Body, Accent, Ears, Top, Extra, Scale`, as Data/Patients); NurseBuilder adds a nurse cap in the rarity's
  colour. Stats aren't stored: `Logic/Nurse.stats(role, rarity, level, cfg)`.

  | Rarity | Nurses (Role) |
  |---|---|
  | Common (5) | PuffPup (Maker) · MintMouse (Healer) · BeanBear (Maker) · DewDuck (Healer) · HumHamster (Cheerer) |
  | Rare (4) | CuddleCub (Maker) · PebblePenguin (Healer) · BerryBat (Maker) · SunnySnail (Cheerer) |
  | Epic (3) | CloudKoala (Healer) · JamJelly (Maker) · ToffeeFox (Cheerer) |
  | Legendary (2) | AuroraOtter (Healer) · StarlightLamb (Cheerer) |
  | Mythic (1) | MoonpuffDrake (Maker) |
  | Secret (1) | GoldieGryphlet (Healer) |
- **✚ `Levels`**: an ARRAY `Levels[1..5]` of `{ Name, Icon, Stars, Cash, Slots, Beds, Queue, RecipeCap, Floors, Unlocks: { string } }`.

  | Lv | Name | ⭐ gate | 💰 | Slots | Beds | Queue | Recipe cap | Floors | Unlocks (chips) |
  |---|---|---|---|---|---|---|---|---|---|
  | 1 | First-Aid Stand | 0 | 0 | 1 | 1 | 4 | 1 | 0 | – |
  | 2 | Clinic | 15 | 400 | 2 | 2 | 4 | 2 | 1 | walls + roof, 2 nurses, 2 beds, 2-item recipes |
  | 3 | Hospital | 45 | 1,500 | 3 | 2 | 5 | 3 | 2 | 2 floors, ✚ sign, 3 nurses, 🌻 Garden, line of 5 |
  | 4 | Big Hospital | 100 | 5,000 | 4 | 3 | 5 | 3 | 3 | 3 floors, ambulance bay, 4 nurses, 3 beds |
  | 5 | Mega Hospital | 200 | 15,000 | 5 | 3 | 6 | 3 | 4 | tower, neon sign, helipad, 5 nurses, line of 6 |

  ⭐ is a **gate** (needed, not spent), like rooms; 💰 is spent (§E asks Joshua to confirm).

### B6. Config (exact numbers; `src/shared/Config.luau`)
```lua
Config.MiniGame = {
  PerfectTip = 3, TipCapPerCure = 15,                      -- cash only; never Stars, Book or story
  Combo = { { At = 3, Multiplier = 1.2 }, { At = 6, Multiplier = 1.5 }, { At = 10, Multiplier = 2 } },
  MinSeconds = { Pour = 1.2, Patch = 1, Scrub = 1.5, Cool = 1.5 }, SimpleMinSeconds = 0.25, Slack = 0.8,
  SessionSeconds = 12, PerGameSeconds = 6,                 -- Timeout = SessionSeconds + PerGameSeconds × #games
  Pour = { FillSeconds = 2.4, BandMin = 0.7, BandMax = 0.86, GoodSlack = 0.12 },
  Patch = { Spots = 3, Seconds = 4.5, Good = 2 },
  Scrub = { Seconds = 4, Perfect = 6, Good = 3 },
  Cool = { Blows = 3, Good = 2, PulseSeconds = 1.2, Window = 0.3 },
}
Config.Treat = { ItemPatience = 0.25, Distance = 20 }
Config.Belt = {
  Offset = Vector3.new(24, 0, 0), Length = 44, ArriveSeconds = 6, RideSeconds = 30, ReplaceSeconds = 1.5,
  Odds = { Common = 70, Rare = 24, Epic = 5, Legendary = 1 }, -- percent
  NightRushBoost = 2, NightRushMythic = 0.5, GoldenSecret = 1,
  GoldenEverySeconds = 1200, GoldenSeconds = 120, PityArrivals = 8,
  HireCooldown = 3, HireDistance = 40, ServerStepSeconds = 1, MaxRiders = 8,
  Prices = { Common = 100, Rare = 400, Epic = 1500, Legendary = 6000, Mythic = 20000, Secret = 50000 },
  PriceScale = { 1, 1.25, 1.5, 1.75, 2 },                  -- by the viewer's (and the hirer's) hospital level
}
Config.Nurses = {
  MaxLevel = 5, TrayMax = 4, MinSeconds = 3, FasterPerLevel = 0.08,
  MakerSeconds  = { Common = 14, Rare = 12, Epic = 10, Legendary = 8, Mythic = 7, Secret = 6 },
  HealerSeconds = { Common = 16, Rare = 14, Epic = 12, Legendary = 10, Mythic = 9, Secret = 8 },
  CheerPatience = { Common = 0.1, Rare = 0.15, Epic = 0.2, Legendary = 0.3, Mythic = 0.35, Secret = 0.4 },
  CheerTip      = { Common = 0.05, Rare = 0.08, Epic = 0.12, Legendary = 0.18, Mythic = 0.22, Secret = 0.25 },
  CheerPerLevel = 0.03,
}
```
Odds the sign prints (`Logic/Belt.odds`), percent:

| | Common | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|---|
| Day | 70 | 24 | 5 | 1 | – | – |
| Night Rush | 39.5 | 48 | 10 | 2 | 0.5 | – |
| Golden Hour (day) | 69 | 24 | 5 | 1 | – | 1 |
| Golden Hour at night | 38.5 | 48 | 10 | 2 | 0.5 | 1 |

### B7. Logic APIs (pure: no Roblox services, no requires; `cfg` = Config passed in; specs in `tests/`)
- **`Logic/Schema`** (v3): `default()`, `reconcile(saved, today?)`, `isNewer(saved)`, `levelFromRooms(rooms)`,
  `VERSION = 3`, `MAX_LEVEL = 5`, `MAX_NURSE_LEVEL = 5`, `ROOM_LEVELS`.
- **`Logic/Recipe`**: `split(text): {string}` · `join(items): string` · `effective(full, cap): {string}`
  (first `cap` items, at least 1, at most `MAX` = 3) · `newDone(recipe): {boolean}` · `encode(done): string` ·
  `decode(text, n): {boolean}` · `missing(recipe, done): {string}` (in recipe order) · `match(recipe, done,
  have): {number}` (recipe indices `have` can fill, each carried item used once, recipe order) ·
  `apply(done, indices): {boolean}` (a copy) · `complete(recipe, done): boolean` ·
  `makeable(recipe, items: {[ItemId]: boolean}): boolean`.
- **`Logic/MiniGame`**: `GAMES = { Potion = "Pour", Plaster = "Patch", Bubbles = "Scrub", Cocoa = "Cool" }` ·
  `RATINGS = { "OK", "Good", "Perfect" }` · `gameFor(itemId): GameId?` · `isRating(v)` ·
  `rate(game, score, cfg): Rating` (client: Pour score = fill 0..1, the rest a count) ·
  `minSeconds(games, simple, cfg)` · `timeout(games, cfg)` ·
  `accept(reported, games, elapsed, simple, cfg): {Rating}` (server: Simple → all Good; not a list of exactly
  #games valid ratings, or `elapsed < minSeconds × Slack` → all OK) ·
  `multiplier(combo, cfg)` · `settle(combo, ratings, cfg, tipSoFar?, tipScale?): (combo, tip)` (Perfect → combo+1
  and `PerfectTip × multiplier(combo)`; anything else resets to 0; × `tipScale` (a Cheerer); floored; never above
  `TipCapPerCure − tipSoFar`).
- **`Logic/Belt`**: `RARITIES` · `isRarePlus(r)` · `shouts(r)` (Epic+) · `odds(cfg, nightRush, golden)` (percent,
  sums to 100) · `roll(odds, r01, pity): Rarity` · `pityDue(dry, cfg)` · `afterArrival(dry, rarity)` ·
  `pick(roster, rarity, r01): NurseId?` · `price(cfg, rarity, level): number` · `golden(cfg, uptime):
  (active, startsAt, endsAt)` (uptime seconds; windows start at 1×, 2×, ... `GoldenEverySeconds`) ·
  `alpha(startAt, now, rideSeconds)` · `canHire(entry?, cfg): (ok, message)`.
- **`Logic/Levels`**: `max(levels)` · `clamp(levels, level)` · `row(levels, level)` · `nextRow(levels, level)` ·
  `canLevelUp(data, levels): (ok, message)` ("Max level!", "Need ⭐n", "Need 💰n") · `slots` · `beds` · `queue` ·
  `recipeCap` (each `(levels, level): number`) · `impliedByRoom(levels, room): number` · `roomAllowed(room, level)`.
- **`Logic/Nurse`**: `hire(entry?, cfg): (entry, isNew, levelledUp)` · `stats(role, rarity, level, cfg): { Every:
  number?, Patience: number, Tip: number }` · `bestCheer(list): { Patience, Tip }` · `equip(equipped, nurses,
  nurseId, on, slots): (ok, message, equipped)` · `mark(index, nurseId, mark): (index, changed)` ·
  `journal(index, roster, rarities): Journal` · `setsDue(index, roster, rarities, claimed): { Rarity }`.
- **`Logic/Progress.canBuyRoom`** also checks `room.Level` against `data.Level` ("Needs 🏥 Lv 3"), right after
  the season check.

### B8. Server module APIs
Signals are `Shared/Signal` (by reference). Every system has `start()`. Foundation stubs exist with these exact
signatures and safe defaults.

**T1 `Treatment`** (✚): treat sessions, mini-game results, tips and combo, Simple mode, Healer deliveries.
- `Treatment.start()`: wires `TreatResult` and `SetSimple`; connects `Nurses.Heal`.
- `Treatment.combo(p): number` (the `Combo` attribute, 0 when unknown).
- `Treatment.simple(p): boolean` (`Data.Simple`).
- Internals between Patients and Treatment are T1's choice. The treat flow (design §1): the Counter's `TreatPrompt`
  → front patient waiting → items the helper carries that the recipe still needs (`Recipe.match` on the helper's
  Carry first, then the plot's `NurseTray` via `Nurses.takeFromTray`) → none: the head-shake and a hint toast with
  the next missing station icon → else take them (they're spent now), `State = "Treating"`, fire `TreatStart` →
  `TreatResult` (or the timeout: all OK) → `MiniGame.accept` (and all OK when the helper is now farther than
  `Config.Treat.Distance` from the Counter) → `MiniGame.settle` with the plot's `CheerTip` → tip via
  `Economy.addCash` (helper) → mark the items given, `+ItemPatience` patience → complete: today's
  `beginTreatment` (bed, recover, `Cure.resolve`, `Tutorial.onTreated`); not complete: back to waiting.
- Patients uses `Levels.queueCap(owner)` (not `Config.MaxQueue`), `Levels.recipeCap(owner)` (via
  `Recipe.effective`) and the plot's `CheerPatience`; only spawns patients whose effective recipe is `makeable`.

**T3 `Nurses`** (✚): owned nurses, equip slots, workers on plots, the nurse tray, the journal.
- `Nurses.start()`: wires `EquipNurse`; spawns/removes nurse models on `PlotAssigned`/`PlotReleased`, `Changed`.
- `Nurses.slots(p): number` = `Levels.slots(p)`.
- `Nurses.equip(p, nurseId, on): (boolean, string)`.
- `Nurses.grant(p, nurseId, price): (boolean, string)`: charges `price` and grants one copy in ONE update (Level,
  Copies, `NurseIndex = "Hired"`), then grants any journal set due (cash + decor + `JournalSets`, same update), then
  fires `NurseNews` Hired, `Celebrate` (NewNurse on a first copy; JournalSet) and `Hired`.
- `Nurses.markSeen(nurseId)`: every loaded player without an entry gets `"Seen"` and a `NurseNews` Seen.
- `Nurses.trayItems(plot): { ItemId }` · `Nurses.takeFromTray(plot, itemId): boolean`.
- `Nurses.cheer(plot): { Patience: number, Tip: number }` (also mirrored on the plot attributes).
- `Nurses.healed(plot, nurseId, items)`: T1 calls it after a Healer delivery (T3 plays the healer's hop).
- Signals: `Nurses.Heal (plot, nurseId)` (a Healer is ready: T1 delivers from the tray, OK ratings, no tip, no
  combo change) · `Nurses.Hired (p, nurseId, level)`.
- Never requires Treatment or Patients (they require Nurses): it reads `FrontNeeds`/`QueueNeeds` attributes.

**T3 `NurseBelt`** (✚): the shared belt. `NurseBelt.start()` (builds `Workspace.NurseBelt`, wires `HireNurse` and
the prompts, runs arrivals, Night Rush, Golden Hour, pity, the sign, `Shout`s) · `NurseBelt.hire(p, riderId):
(boolean, string)` · `NurseBelt.odds(): { [Rarity]: number }` · `NurseBelt.goldenHour(): boolean`.
- Every `ArriveSeconds` a rider steps on: `Belt.roll(Belt.odds(cfg, NightRush, GoldenHour), r, Belt.pityDue(dry))`,
  `Belt.pick`, `Nurses.markSeen`, a `Shout` Arrival for Epic+. A hired Common or Rare pulls the next arrival to
  `ReplaceSeconds` from now. Unhired riders fall off the end (a little hop off) after `RideSeconds`.
- `hire`: rider exists and isn't hired · `HireCooldown` per player · the player is within `HireDistance` of the
  rider's formula position · `Belt.canHire` · price = `Belt.price(cfg, rarity, Levels.level(p))` →
  `Nurses.grant`. The rider hops off the belt and walks toward the hirer's plot (cosmetic, then removed).

**T3 `NurseBuilder`** (✚, a library): `NurseBuilder.build(nurseId): Model` (Root PrimaryPart + welded parts via
`CreatureBuilder.buildLook`, a nurse cap in the rarity colour, CollisionGroup `Patients`, under 40 parts, a model at
`ServerStorage.Nurses.<NurseId>` replaces it, no scripts) · `NurseBuilder.setTask(model, task)`.

**T5 `Levels`** (✚): `Levels.start()` (wires `LevelUp`; builds each plot's `Building` on `PlotAssigned` and after a
level-up; sets the plot's `Level` attribute) · `Levels.level(p): number` (1 until loaded) ·
`Levels.levelUp(p): (boolean, string)` (`Logic/Levels.canLevelUp`, spend 💰 and set `Data.Level` in ONE update,
`Economy.Purchased:Fire(p, "Level", tostring(level))`, `Celebrate` LevelUp, `LevelChanged`) ·
`Levels.slots(p)`, `Levels.queueCap(p)`, `Levels.recipeCap(p)`, `Levels.beds(p)` (numbers from Data/Levels) ·
signal `Levels.LevelChanged (p, level, previous)`.

**T5 `PlotBuilder`** adds `PlotBuilder.buildBuilding(plotModel, level): Model` (replaces `Plot.Building`; extra
`Bed_<n>` Parts for `Beds − 1`; floors stack within 70×70) and `clearPlot` removes the Building (back to Lv 1's).
**T5 `Economy`**: room purchases also check `Rooms.Level` (`Progress.canBuyRoom` already does, given `data`).

**T7 `CreatureBuilder`**: keeps `build`, `badge`, `setRing`, `setMood`, `setEffect`, `effectAt`, and the Foundation's
`buildLook(look, name?): Model` and `setRecipe(badge, items, done)`; tags creatures `CreatureMotion`; at most 1
Highlight in the world; lights without shadows.

### B9. Client
**ctx** (`Types.Ctx`): unchanged, plus `ctx.Data.Nurses`, `ctx.Data.Rarities`, `ctx.Data.Levels`.

**Module load order** (`Main.client`): UI `Toasts, Hud, Shop, BookPanel, DayReportPanel, Mailbox, Guide,
PromptFilter, Celebrate, MiniGames, NursePanel, BeltView, Tutorial`, then Feel `Sounds, CureFX, Atmosphere,
CreatureMotion`. Each in a pcall; a missing one is skipped.

**Bus events** (new; the old ones are unchanged):

| Event (args) | Fired by | Heard by |
|---|---|---|
| `TreatStart (session)` | Main.client (remote) | T2 |
| `MiniGameRated (game, rating)` | T2, each game as it ends (the client's own rating, for feel) | T6 (sound, pop) |
| `TreatDone (outcome, session)` | T2, after the server's TreatResult reply | T6 (tip coins, combo) |
| `NurseNews (info)` | Main.client (remote) | T4, T6 |
| `NursesNew (count)` | T4 (unseen journal news) | Hud (the 👩‍⚕️ dot) |
| `Shout (info)` | Main.client (remote) | T4 |
| `Banner (spec)` | T4 (Golden Hour countdown, Night Rush, Epic+ arrival) | T6 Toasts |
| `Celebrate (info)` | Main.client (remote), T6 itself (rooms) | T6 Celebrate |
| `Open ("Nurses")` | Hud | T4 NursePanel |
| `Open ("Shop", "Hospital")` | anyone | T5 Shop (the new tab) |
| `Sound (name)` | anyone | T6 Sounds |

`Banner` spec: `{ Id: string, Icon: string, Text: string (≤ 6 words), Color: Color3?, EndsAt: number? (server
time: show a countdown), Seconds: number? }`; a Banner with the same Id replaces the old one; `Seconds = 0` hides it.
Sound cue names other tasks may fire (T6 adds them to Sounds.CUES): `Pour`, `Patch`, `Scrub`, `Blow`, `RateOK`,
`RateGood`, `RatePerfect`, `Combo`, `Tip`, `Hire`, `Equip`, `Arrival`, `Golden`, `LevelUp`, `Celebrate`, `Tick`,
`Coin`.

**Kit additions (T6 owns; Foundation versions work today):**
- `Kit.countUp(label: TextLabel, to: number, format: ((number) -> string)?, seconds: number?)`: rolls the number
  (attribute `CountValue` remembers it); instant with reduced motion.
- `Kit.celebrate(parent: GuiObject, color: Color3?): () -> ()`: rays + confetti behind a reward; returns stop.
- `Kit.rarityFrame(gui: GuiObject, rarity: string): () -> ()`: the rarity's frame (UIStroke `RarityFrame` in its
  colour; T6 adds the shimmer: Common grey, Rare blue, Epic purple, Legendary rainbow, Mythic cosmic, Secret gold);
  returns stop.

**Hud hook (Foundation, T6 keeps):** the bottom bar's 5th button `Nurses` (👩‍⚕️ "Nurses", revealed with the rest
after the tutorial); its dot follows `NursesNew`; `Hud.target("Nurses")`; ⚙️ has a third switch, Simple mode
(`👆 Simple taps` / `🎮 Mini-games`), which asks `SetSimple`.

### B10. Server boot order (`Main.server`)
`PlayerData → State → Events → Plots → Carry → Economy → Levels → Progress → Book → Story → Daily → DayReport →
Tutorial → Stations → Nurses → Treatment → Patients → NurseBelt → Visits → DayNight`. Requires never loop:
Patients → Treatment → Nurses → Levels → (PlayerData, Plots, Economy, PlotBuilder); NurseBelt → Nurses.

---
## C. Tasks
### Task 0: Foundation (done, committed)
- [x] This plan. Config, Types, Remotes (declared, `serve` payload), Schema v3 + migration, State, Data
  (`Nurses`, `Rarities`, `Levels`, recipes, `Rooms.Level`, journal decor), Logic (`Recipe`, `MiniGame`, `Belt`,
  `Levels`, `Nurse`, `Progress` level gate) with Lune specs, stubs for every ✚ module, Main.server/Main.client
  wiring, the Hud hook, Kit first versions, `CreatureBuilder.buildLook`/`setRecipe`.

### T1: Treatment server
- [ ] Recipes on patients (`Recipe`, `RecipeDone`, `Item`/`Station` = first missing; `CreatureBuilder.setRecipe`).
- [ ] The treat flow and `TreatStart`/`TreatResult` (§B8), sessions one per player, the timeout (all OK), the
  distance check, tips (`Economy.addCash`, capped per cure), the `Combo` attribute.
- [ ] `FrontNeeds`, `QueueNeeds`; `Levels.queueCap`, `Levels.recipeCap`, `CheerPatience`; beds in `Building`.
- [ ] Healers: `Nurses.Heal` → deliver from the tray (OK, no tip) → `Nurses.healed`.
- [ ] Keep: the tutorial hooks, `settleEarly` on leave, the wrong-item head-shake. Don't touch the animator.

### T2: Mini-games client (load `game-feel`, `roblox-ui`)
- [ ] Pour, Patch, Scrub, Cool (3–5 s, touch and mouse, big targets), each rated with `MiniGame.rate`, one after
  another for `session.Games`; a big outlined "PERFECT!"/"GOOD!"/"OK!" pop and the combo counter.
- [ ] Simple mode: one big tap per game (rated Good). Reduced motion: gentler animation, same rules.
- [ ] `TreatResult` via `Hud.ask`; fire `MiniGameRated` and `TreatDone`; close cleanly if the session times out.

### T3: Nurses server
- [ ] `NurseBelt` (§B4 belt, §B8), the sign (all odds, event odds, pity), Night Rush, Golden Hour attributes and
  `Shout`s, riders, prompts, `HireNurse`.
- [ ] `Nurses`: equip, workers (Maker into `NurseTray`, Healer via `Heal`, Cheerer attributes), journal Seen/Hired,
  set rewards, `NurseNews`, `Celebrate`; nurses work only while the owner is in the server.
- [ ] `NurseBuilder`. Motion via the creature-motion attributes.

### T4: Nurses client
- [ ] `BeltView`: smooth riders, a tappable billboard each (rarity frame, role icon, level-1 stat, the viewer's
  price, Hire), local `HirePrompt.ObjectText` = the viewer's price; `Banner`s from `Shout` and the Golden Hour /
  Night Rush attributes (no banners during the tutorial).
- [ ] `NursePanel`: the Journal first (grouped by rarity, silhouettes for unseen, completion %, set rewards shown),
  equip/unequip in it, slots from the level, a hire celebration, `NursesNew` for the dot.

### T5: Hospital levels
- [ ] `Levels` (§B8), `PlotBuilder.buildBuilding` (the shell grows; floors stack; ≤ 400 parts per plot),
  `Economy` level gate, the Shop's "Hospital" tab (current level, next level's cost and unlock chips, Level up).

### T6: UI juice
- [ ] Kit (`countUp`, `celebrate`, `rarityFrame` shimmer, idle breathing on CTAs), count-up cash/stars, flying
  coins on a cure and a tip, toasts slide, `Banner`s, `Celebrate.luau` (rays + confetti + big title), sounds for
  every cue above, Book/Mail/Day Report polish.

### T7: Performance
- [ ] Measure first (Performance Stats, PC and phone). Client creature motion (`CreatureMotion`), server requests for
  Patients (the attributes in §B4), remove per-creature Highlights, no shadows on lights, idle client loops sleep,
  the perf budget note.

### Integration (lead)
- [ ] Apply the requests, boot, run the checklist below, write `logs/playtests/`, commit, merge.

---
## D. Playtest checklist
- [ ] 0. Boot: `[Main] Clinic is open.`, no red errors; the belt stands east of the plaza, its sign shows the day odds.
- [ ] 1. An old save (no `Level`): loads at its implied level (Garden owner → Lv 3), empty journal; `Version` 3 on save.
- [ ] 2. Fresh save (`FreshSave`): the tutorial runs unchanged; patients have 1-item recipes; Treat opens a
  mini-game; OK still cures; the HUD reveals 👩‍⚕️ with the rest at the end.
- [ ] 3. Each mini-game (Pour, Patch, Scrub, Cool) on PC and the phone emulator: rated OK/Good/Perfect; a Perfect
  pays a small tip and the combo counter climbs; ×1.2 at 3; a Good resets it.
- [ ] 4. Lv 2: a Bath patient needs 🛁🧪; with a tray of 1 you give 🛁 (one game), the badge ticks, then 🧪.
- [ ] 5. Simple mode (⚙️): every game is one tap, rated Good, no tips.
- [ ] 6. Junk: `TreatResult` with another session, early, wrong types; `HireNurse(-1)`, from far away, twice in 3 s,
  without cash; `EquipNurse` for an unowned nurse or past the slots; `LevelUp` without ⭐ → all `false` + message.
- [ ] 7. The belt: a nurse every ~6 s, each takes ~30 s; prices scale with your level; Hire by tap and by prompt;
  a second player sees the same riders; the hired one hops off; a Common/Rare is replaced quickly.
- [ ] 8. Night (`SkipPhase`): the sign shows Night Rush odds; Mythic possible. Golden Hour (shorten
  `GoldenEverySeconds` in Studio): banner with countdown, Secret on the sign.
- [ ] 9. Pity: force 8 Commons in a row (Studio) → the 9th is Rare+.
- [ ] 10. Journal: silhouettes until seen; NEW! on first seen and first hire; completion %; completing Commons gives
  💰300 + Plaster Rug once.
- [ ] 11. Nurses at work: equip a Maker (items appear in the tray, treating uses them), a Healer (treats the front
  patient with OK), a Cheerer (longer patience). Slots = level. Leave and rejoin: equipped nurses come back.
- [ ] 12. Level up in the Shop's Hospital tab: celebration, the building grows, slots/beds/queue follow the table;
  the Garden needs Lv 3.
- [ ] 13. Juice: count-ups, flying coins, toasts slide, rarity frames shimmer, sounds; calm mode quiets all of it.
- [ ] 14. Perf: 6 full plots + belt on a mid phone ≈ 60 fps; Network receive stays low while creatures hop.
- [ ] 15. Owner leaves mid-game / mid-hire / with nurses: no errors, plot clean, the next joiner's prompts work.

---
## E. Open points for Joshua (from building this; not decided here)
1. **⭐ on levels: gate or spent?** The design says "Cost: ⭐15 + 💰400". This plan treats ⭐ as a gate (needed, not
   spent), like rooms, because spending ⭐ would re-lock rooms and regulars (`UnlockStars`). Confirm.
2. **"Garden 3" recipes:** there's no Garden wing of patients (the Garden is a decor room with no station), so the
   only 3-item recipes are the regulars'. A Garden wing (patients + a station) would be a content add.
3. **Lv 3 "Golden capsule"** is replaced by the belt (`memory-20261116-012`); Lv 3 unlocks the Garden instead.
4. **Nurse names** are placeholders (Joshua's and his brother's to rename): see `Data/Nurses`.
