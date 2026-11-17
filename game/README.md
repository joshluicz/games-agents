# game/: the Rojo project (Creature Clinic)

The Luau code for **Creature Clinic** (working title). Every player owns a clinic on a plot and cures silly, original
creatures. **Git owns the scripts and Studio owns the world.** Rojo syncs `src/` into Studio, while the brother's
models live in the place file (`ServerStorage.ClinicKit`, `ServerStorage.Creatures`).
- Design: `docs/plan/2026-11-16-creature-clinic-design.md`.
- Build plan and **contracts** (names, attributes, APIs): `docs/plan/2026-11-16-creature-clinic-build-plan.md` §B.
- **Depth update (Update 1)**: recipes + mini-games, the Nurse Belt and Journal, hospital levels, juice, perf. Design
  `docs/plan/2026-11-16-depth-update-design.md`; contracts, file ownership and the playtest list
  `docs/plan/2026-11-16-depth-update-build-plan.md` (§A owners, §B contracts). Modules marked *(depth)* below are
  new in it. Performance budget: `docs/plan/2026-11-16-perf-budget.md` ([below](#performance-budget)).
- **Progression v2** (nurse jobs, abilities, XP and teams; rebirths with perk cards, a tree and themes; the Nurse
  Agency and the Player Market; Hospital v2): design `docs/plan/2026-11-16-depth-update-design.md` §6-8; contracts,
  file ownership and the playtest list `docs/plan/2026-11-16-progression-v2-build-plan.md` (§A owners, §B contracts,
  §D playtest). Modules marked *(v2)* below are new in it. **Built and integrated (2026-11-17):** the Foundation
  (save schema v4, Config, Types, Remotes, every Data and Logic module) and the eight parallel tasks (T1-T8) are in,
  with no stubs left; 982 Lune specs pass. **Not yet playtested in Studio:** the [v2 checklist](#progression-v2-checklist-build-plan-d)
  below is next.
- **Look overhaul** (the studs look, a real hospital building, the belt down the road's centre, the HUD on two side
  rails, one navy modal template, a tutorial with a floor beam, Skip and Replay): rulings `memory-20261117-001` to
  `-004`; contracts, file ownership, numbers and the playtest list `docs/plan/2026-11-17-look-overhaul-build-plan.md`
  (§A owners, §B contracts, §C numbers, §E playtest). **The Foundation and the nine build tasks (T1-T9) are integrated
  (2026-11-17)** and pass every gate in Lune; the Studio playtest (the plan's §E, short form under
  [Playtest checklist](#playtest-checklist-build-plan-d)) is the lead's, after the merge. See
  [The look overhaul](#the-look-overhaul). Modules marked *(look)* below are new in it.
- The brother's building guide: `docs/guides/build-the-clinic.md`. Quick Words: `docs/guides/quick-words.md`.

## Run it (Joshua, Windows)
```powershell
cd games-agents\game
rokit install          # pinned rojo, selene, stylua and lune (rokit.toml); answer y to trust a new tool
rojo plugin install    # once
rojo serve             # then in Studio: Rojo plugin → Connect → Play
```
- **No kit models yet?** The server builds a placeholder town of 6 plots at `Config.Town.Origin` (0, 0, 300), each
  with a First-Aid Stand, so you can play right away.
- **Saving in Studio** needs **Game Settings → Security → Enable Studio Access to API Services**.
- **Max Players = 6** (Game Settings → Places), one per plot. A 7th player can still visit and help.
- ⛔ **Never edit a Rojo-synced script inside Studio.** The next sync overwrites it.

## What's where
Rojo maps `src/shared` → `ReplicatedStorage.Shared`, `src/server` → `ServerScriptService.Server` and `src/client` →
`StarterPlayer.StarterPlayerScripts.Client` (`default.project.json`). A `.server.luau` file becomes a Script, a
`.client.luau` file becomes a LocalScript, and every other file is a ModuleScript.

### Shared (server and client)
| File | Does |
|---|---|
| `shared/Config.luau` | **Every tuning number**: pay, patience, queue, hold times, day and night length, the winter window, autosave, town layout, music, pass IDs. Also who's an admin: `AdminUserIds`, `AdminNames` ([Admin panel](#admin-panel)); the `Leaderboards` timings and board lists ([Leaderboards](#leaderboards)); the idle time, boost caps and the Roblox badge ids ([Play gifts...](#play-gifts-doctor-ranks-boosts-and-badges)): `PlaytimeIdleSeconds`, `BoostCaps`, `BoostMaxMinutes`, `BoostMinMakeSeconds`, `Badges`; *(depth)* `MiniGame` (tips, combo, game timings), `Treat`, `Belt` (odds, Night Rush, Golden Hour, pity, prices, distances incl. `SeenDistance`; *(v2)* `MinRebirths`), `Nurses` (*(v2)* MaxLevel 10, the R3 cap bonus, 5% a level, the specialty boost, Medic/Porter/Receptionist numbers); *(v2)* `Roster`, `NurseXP`, `Abilities` (cooldown steps, and the effect numbers `FastMake`, `CashNext`, `NearStation`), `Rebirth` (costs, +25% a rebirth, points, the offer), `BranchCaps`, `Agency`, `Market`, `Lift`, `AE`, `VIP`, `Triage`, `Escort`, `Hydro`, `Pharmacy`, `WardComfort`, `AESpeed`, `NightClinicPerLevel`, `NightOwl`, `GoldenChance`/`GoldenMultiplier`, and the 🏢 `Rebirths` board in `Leaderboards.Boards` |
| `shared/Palette.luau` | The colours and fonts shared by the world and the UI. *(look)* `World` and `Accent` follow art-direction §4.1 (no pastels, dark anchors), `PlotColors`, `Departments`, `Navy`, `Gold`; `Candy` stays for the UI; every old key is an alias ([The look overhaul](#colours-and-tokens)). Change colours here |
| `shared/Types.luau` | The shared type names (`Data`, `Snapshot`, `Plot`, `Ctx`, ids); *(depth)* `TreatSession`, `TreatOutcome`, `NurseNews`, `ShoutInfo`, `CelebrateInfo` (incl. `Room` for Kind "Room"), `BannerSpec`; *(v2)* the ids `JobId`, `DeptId`, `AbilityId`, `PerkId`, `NodeId`, `ThemeId`, the v4 `NurseEntry` and `RebirthData`, `AgencySlot`/`AgencyView`, `Listing`/`MarketView`, `BeltScoutInfo`, `TeamEffects`, the new `NurseNews`/`CelebrateInfo` kinds, `TreatSession.Kind/Auto/Ease`, `TreatOutcome.Triage` and `CureCtx.Urgent/Extra/Plot/Dept/Wing`; *(v2, integration)* `CuredInfo.Urgent/Escorted/Soaked` and `CureCtx.Escorted/Soaked` |
| `shared/Remotes.luau` | Creates `ReplicatedStorage.Remotes` (incl. `TutorialAck`, `Admin`, `Discard`, `GetBoards`, `ClaimPlayGift` and `SetHelpers(on: boolean)`, the owner's helpers switch; *(depth)* events `TreatStart`, `NurseNews`, `Shout`, `Celebrate` and functions `TreatResult`, `SetSimple`, `HireNurse`, `LevelUp`; *(v2)* events `AgencyNews`, `MarketNews`, `BeltScout` and functions `SetJob`, `OpenBranch`, `ChoosePerk`, `BuyNode`, `ResetTree`, `SetTheme`, `ClaimBranchNurse`, `GetAgency`, `AgencyBuy`, `SellNurse`, `GetMarket`, `ListNurse`, `Unlist`, `BuyListing`, `RideLift`, `Triage`, all served now (an unserved one would answer `false, "Coming soon!"`); `EquipNurse` is gone: every nurse you own works). Server helpers: `serve` (rate limit plus pcall; a table third return value is passed on), `allow`, `toast` (always shown: replies and warnings), `news` (ambient news, held back while the player is quiet), `toastAll` (skips quiet players), `setQuiet`/`isQuiet` (Server/Tutorial makes a player in the tutorial quiet), `setActivity` (every served call marks the player active: Server/Playtime) |
| `shared/Signal.luau` | A small signal that passes tables **by reference** (used instead of BindableEvents) |
| `shared/Data/*.luau` | **Content**: `Ailments` (with each `Recipe`), `AilmentActing`, `Stations`, `Items`, `Patients`, `Regulars` (their own `Recipe`), `Rooms` (`Level`: the Garden needs Lv 3), `Upgrades`, `Decor` (incl. the six Journal rewards and the six Doctor-rank decor), `DailyGoals`, `Wings`, `Variants`, `Playtime` (the play gifts and Doctor ranks), `Boosts` (timed boosts), `Badges` (tiers, categories, the badge list), *(depth)* `Nurses` (16 placeholder-named nurses; *(v2)* each with a `Specialty` and an `Ability`, plus the rebirth-only FounderFennec), `Rarities` (Common..Secret, colours, Journal rewards), `Levels` (an array, Lv 1-5, incl. `SpawnSeconds`; the line is 3 at every level; *(v2)* no `Slots`, with `Floors`, `Departments`, the ward beds and the Lv 2 ambulance bay); *(v2)* `Jobs`, `Departments` (with `.Stations` and `.Wings`), `Abilities`, `Perks` (12 cards and the `Fallback`), `Tree` (3 branches, 12 nodes, 33 points), `Themes`, four Pharmacy medicines in `Items`, the 💊 `Pharmacy` station, the gated `WardComfort`/`AESpeed`/`NightClinic` upgrades, the Sunny and Sky wings with their ailments, patients and acting, the Golden variant, the wing rewards and Branch Trophies in `Decor`, and the 🏢 Branches badge. Keyed maps carry `.Order`, and everything is frozen |
| `shared/Data/AilmentActing.luau` | How a waiting patient **acts out its ailment** (Joshua: "animations corresponding to their illness or need for attention ... visible with perhaps props. but not gory"): per ailment its Motion (the beat), how often, its Props, a particle Burst, an Ambient, the Face on the beat, Squint, cold Cheeks, a dimmed night Glow. Plus `Attention` (wave at ≤ 50% patience, both arms + a "!" at ≤ 25%), `Default`, and the `Vocabulary` the client can play (specs check it) |
| `shared/Logic/Schema.luau` | Save schema **v4** *(v2)*: `Rebirth`, every nurse's `XP` and `Job`, `Equipped` dropped (a v3 save's working order comes from it once), at most `rosterCap(Rebirth.Count)` nurses working on every load (the rest `"Rest"`, nothing ever deleted), the three new upgrades, `Stats.RoomsBefore`; `xpToNext`, `rosterCap`, `levelCap`. Before that, v3: `default()`, `reconcile(saved, today?)` (migrates v1 shop saves, pulls future days back to today, gives a save without `Tutorial` its step: any cure means done; a save without `Playtime`/`Boosts`/`Stats`/`Badges` starts at 0 on today, with unseeded `Stats`; a v2 save keeps all of those and gets the hospital `Level` its rooms imply, no nurses and an empty journal), `isNewer(saved)`, `levelFromRooms(rooms)`. `WeekCures` = { Week, Count } for the weekly leaderboard |
| `shared/Logic/Playtime.luau` | The play gifts and ranks: rollover to a new UTC day, `add`, gift `state`/`ready`/`claim`/`nextGift`/`allOpened`, `rankFor`/`nextRank`/`newRanks`, `active` (idle), `duration`/`clock` text |
| `shared/Logic/Boosts.luau` | Boost maths: permanent effects (scoped, capped) plus timed boosts (`extend`, `tick`, `soonest`), `percent`/`multiplier`, `summary`, `makeSeconds` |
| `shared/Logic/Badges.luau` | Badge rules: `statValue` (counters and derived stats), `tierFor`, `progress`, `ups`, `reward`, `effects`, `boostAt`, `add`, `seed` (an old save's counters), `maxed` |
| `shared/Logic/Tutorial.luau` | The first-session tutorial's rules: the steps (1 welcome .. 8 Book, 9 done), `advance(step, event)`, `resume` after a rejoin, who Patients may send (`spawnPlan`, `queueCap`), the shop top-up (`cheapest`, `topUp`) |
| `shared/Logic/Pay.luau` | Cash and ⭐ for a cure (with the optional `CashBoost`, `TipsBoost`, `StarsBoost` from Server/Boosts; *(depth)* a longer recipe pays more, and so does a Cheerer on duty). Every factor multiplies once, with one rounding at the end |
| `shared/Logic/Prices.luau` | Upgrade prices, hold time, tray capacity, patience |
| `shared/Logic/Progress.luau` | Can this room be bought (season, *(depth)* the hospital level a room needs, ⭐, 💰), and what's the next goal (it skips rooms above your level: `levelAllows`) |
| `shared/Logic/Book.luau` | Patient Book stamps and set completion |
| `shared/Logic/Story.luau` | Regulars: who's unlocked, whether a beat is due today, advancing a beat |
| `shared/Logic/Daily.luau` | UTC day, Today's Visitor, banked goals, mailbox |
| `shared/Logic/Leaderboard.luau` | The leaderboards' rules ([Leaderboards](#leaderboards)): the boards, the UTC week, store names, a player's values from their save, what changed since the last write, backoff, permanent errors, the live merge and rank, admin exclusion |
| `shared/Logic/Admin.luau` | The admin panel's rules: who is an admin, the fixed action list and the argument each takes, the alone-in-server rule ([Admin panel](#admin-panel)) |
| `shared/Logic/CreatureSize.luau` | A creature's build scale: its species' `Look.Scale` (0.75 small .. 1.25 big) × `Config.CreatureSize` (1.6, player-sized) × this patient's wobble (±`Config.CreatureSizeJitter`, 8%) |
| `shared/Logic/Recipe.luau` *(depth)* | A patient's recipe: cut by level, the done mask, what's missing, what the items in hand can fill |
| `shared/Logic/MiniGame.luau` *(depth)* | Mini-game ratings, the server's plausibility check, the combo and capped tips |
| `shared/Logic/Belt.luau` *(depth)* | The Nurse Belt: odds (Night Rush, Golden Hour), rolls, pity, picks (*(v2)* never a rebirth-only nurse), prices by level, Golden Hour windows, rider position; *(v2)* `gate` ("🏥 Lv 3" / "🏢 R1"), `canHire` with the hirer's level cap |
| `shared/Logic/Levels.luau` *(depth)* | Hospital levels: the next level's cost, beds, queue, recipe cap, seconds between patients, room gates; *(v2)* `floors`, `departments` (slots are gone) |
| `shared/Logic/Nurse.luau` *(depth)* | Owned nurses: copies and levels, stats by rarity and level, the Journal and its set rewards. *(v2)* XP (`addXP`, a copy = one level), the level cap and the roster cap, `working`, `canAdd` ("Roster full: sell or list one"), `setJob`, stats for every job with the specialty boost, `best`; rebirth-only nurses are in no Journal group. `equip` is gone |
| `shared/Logic/Jobs.luau` *(v2)* | Jobs and departments: `open`, `effective` (a closed job is worked as the role), `department`, `patientDepartment`, `teams`, `teamEffects` |
| `shared/Logic/Abilities.luau` *(v2)* | Ability `tier`, `strength` (cooldowns x0.85 at Lv 5 and 10), `useful` (it fires by itself only when it helps), `ready`, `autoGames` |
| `shared/Logic/Rebirth.luau` *(v2)* | Rebirths: `cost`, `canRebirth`, `multiplier` (+25% added), `apply` (what resets and what's kept, in ONE update), `startCash` (ALL cash becomes this), `offer`/`liveOffer`/`choose` (perk cards; a waiting offer with no known card left is the Fallback), `unlocks`/`has`, `themes`/`theme`, `effects` (perks + tree), the keep/reset screen's `KEEP`/`RESET`/`GET` |
| `shared/Logic/Tree.luau` *(v2)* | The Branch Ability Tree: `canBuy`, `buy`, `refund`, `spent`, `effects` |
| `shared/Logic/Agency.luau` *(v2)* | The Nurse Agency: `restock`, `odds`, `roll`, `seeded`/`personal` (🍀 Lucky Stock), `price`, `sellBack` (`personal` repeats a shared-stock nurse only when every nurse of the rolled rarity is in the shared stock, so the shown odds stay true) |
| `shared/Logic/Market.luau` *(v2)* | The Player Market: `band` (*(review fix)* with the nurse's copies: never below `floor`), `floor` (the lowest price whose payout is at least the Agency's per-copy sell-back: no seller short-changed, no buy-and-sell-back profit), `valid`, `fee`, `canList`, `canBuy` (`canBuy` also refuses a listing above the buyer's nurse level cap: "🏢 R3 first!") |
| `shared/Logic/Hospital.luau` *(v2)* | Hospital v2: `floors`, `departments`, `route`, `triageOptions`, `urgentRecipe`, `arrival`, `recover`, `nightOwl` |

`Logic/*` is **pure**: no Roblox services and no requires, so Lune can test it. The server passes `Config` in as
`cfg`.

### Server
| File | Does |
|---|---|
| `server/Main.server.luau` | Collision groups, then every system's `start()` in order ([Boot order](#boot-order)) |
| `server/PlayerData.luau` | Loads and saves (schema v4, DataStore `PlayerData_v2`; *(v2)* `isOpen(p)`: loaded and not closing, `saveNow(p)`: write now, never two at once) with `UpdateAsync` under a session lock (a join waits out another server's lock until its lease ends), migrates `PlayerData_v1`, never saves after a failed load or over a newer-version save (`DataOk = false` plus a toast), autosaves, saves on leave (retried with backoff) and in `BindToClose`. A rejoin to the same server waits for the last Player's leave-save first. Leaderstats `Cash` and `Stars`. The Studio-only `FreshSave` switch ([Test switches](#studio-rojo-connected)). *(v2, integration; review fix)* `writeAfter(first, second, leaveOut?)`: until `first`'s changes so far have landed in the store, every write of `second`'s (autosave, `saveNow`, a rebirth's, its leave-save) is written with the sale left out (`leaveOut(snapshot)` on a copy: the nurse out, the price back; `Pure.prepare`); it only waits (at most 10 s) while `first` has a write in flight. Each call adds a dependency (never overwrites), so no write order, crash, failed seller leave-save or lost lock can put a nurse in two saves, and two players trading both ways never deadlock. `PlayerData.Pure` (tests/PlayerData.spec) |
| `server/State.luau` | Builds each player's Snapshot (incl. `Tutorial`, the step, and `TutorialCures`; `Playtime`, `Stats`, `Badges`, `Boosts` (Server/Boosts.list) and `MakeSeconds` per station; *(depth)* `Level`, `Nurses`, `NurseIndex`, `JournalSets`, `Simple`; *(v2)* `Rebirth`, and no `Equipped`), pushes it (debounced) and answers `GetState` |
| `server/Playtime.luau` | Counts **active** play once a second (at your own clinic, not idle for `Config.PlaytimeIdleSeconds`), the daily play gifts (`ClaimPlayGift`), the Doctor ranks (their decor, toast, Roblox badge and the sign's `RankBadge`), the `PlayToday`/`PlayTotal`/`PlayCounting` player attributes, the UTC-day rollover ([below](#play-gifts-doctor-ranks-boosts-and-badges)) |
| `server/Boosts.luau` | `multiplier`/`percent` per kind and scope, `addTimed` (extends, capped), `list` for the Snapshot, `makeSeconds` per station, `cureScopes`. Permanent boosts from the rank and badge tiers, timed ones ticking with active play. *(v2)* The branch source (the tree and perk cards, capped by `Config.BranchCaps`) in every kind, and Cash and Stars x the rebirth multiplier; `list` adds `Branch` and `Rebirth`. *(v2)* `makeSeconds(p, "Pharmacy")` is the 💊 Pharmacy's own hold (`Config.Pharmacy.HoldSeconds`, x `Tier2Factor` from the maker's R2), then MakeSpeed, so Stations and the Snapshot's `MakeSeconds` (UI/Guide) agree |
| `server/Badges.luau` | Badge counters (`add`, `onCure`, `onMade`, `onHeart`), the tier-up check after every save change (rewards once, a toast), seeding an old save's counters, `maxAll` (Admin), `awardRoblox` (BadgeService, in a pcall) |
| `server/Tutorial.luau` | The first-session tutorial ([below](#the-first-session-tutorial)): the saved step, moved on only by real server events, the one-time shop top-up, `TutorialAck`, and the quiet toasts while it runs. *(look, T8)* The `TutorialSkip` and `TutorialReplay` remotes are served (Skip: an active step → done, no gift, toast "🔁 Replay anytime in ⚙️"; Replay: done + your own clinic, `Config.Tutorial.ReplayCooldown`, empties your own line through `Patients.reopen`, sets `TutorialReplay`, back to the first patient); the saved `TutorialGift` is set by the SHOP top-up, a Skip, a Replay or DONE, so the gift never comes twice; the onboarding funnel (published games, first runs only) and a `TutorialSkipped` custom event; `Tutorial.Pure` (tests/TutorialFlow) |
| `server/Events.luau` | Winter: `Config.Winter` dates or the `ForceWinter` Workspace attribute → `Workspace.IsWinter` |
| `server/Plots.luau` | Assigns a plot once data loads, frees it on leave, rebuilds rooms and decor from the save, `canWork` (owner, friend or `OpenHelpers`), `unlockRoom`, `placeDecor`. Owners (re)spawn in front of the Counter, beside the line, facing the clinic. *(v2)* `syncRooms(p)`: the plot follows the save after a rebirth or 🛁 Bath Ready (room models the save no longer owns go, never the Stand; owned rooms the plot lacks come; the for-sale previews come back; decor models follow `Decor.Placed`). Never yields, never saves |
| `server/PlotBuilder.luau` | *(look: split and rebuilt, see [The look overhaul](#the-look-overhaul); the town is `TownBuilder`'s, the Building `HospitalBuilder`'s, the helpers `World/*`'s; every function and constant here still works: `buildTown`, `buildBuilding(plotModel, level, grewFrom?, theme?)`, `buildRoom`, `placeRoom`, `setPreview`, `queueSpot`, `clearPlot`, and the re-exports `Pure`, `NIGHT_LIGHT_TAG`, `STATION_TAG`, `LIFT_TAG`, `PROMPT_TAGS`)* Builds the plots and placeholder rooms, or clones the brother's `ServerStorage.ClinicKit` models (kit clones lose scripts and Highlights, and their lights stop casting shadows). **The plot (look T4):** its floor is a `Ground` Model (a dark studded `Pad` 67 x 67 and 4 Slate `Edge`s; Patients' and Nurses' rays find it by the name `Ground`), a plank path and two slate stones to the main door. The Counter is the plot colour with a studded warm-white `CounterTop` (13 x 3) and our paw-heart (`DeskGui`), never a cross. The sign has **no board**: its letters float between two studded posts in the plot colour (the `Sign` part is invisible); it keeps `OwnerName`, `HeartCount`, `RankBadge` (the Doctor rank) and the hidden `BranchBadge`, the two badges as navy pills. The gate is a studded arch in the plot colour. Every plot (kit too) gets a `QueueLane` Model: 6 mid-tone `LaneTile`s, 2 `LaneEdge`s in the plot colour and one `LaneSpot` disc per place in line with its number on the disc (`NumberGui`), all walk-through and ray-ignored. `PlotBuilder.queueSpot` says where each place in line is, for the lane and for `Patients`, so they always line up. **The rooms:** the Stand has **no shell** (a plank `Floor`, the stations, `Bed_1` and the decor slots at the `Logic/Building.STAND` spots, decor slot 2 on the porch pad; the waiting bench is the Building's); the Bath Room, Cozy Ward and Winter Wing are annexes (studded walls in the room colour on the back half, a soft dark `Roof` with the name floating on it (`NameGui`), a warm-white `Trim`, the dado drawn on as `LiningGui`); the Garden is a studded lawn with hedges and an arbor; room beds are `Frame` / `Headboard` / `Bed_<n>`; the for-sale preview's price sits on a navy plate. Station icons and for-sale boards stop growing up close (`DistanceLowerLimit`). No blossom trees on plots (the town keeps its 1 in 6). Every plot gets a `MascotSpot` at (−7, −14.8). `clearPlot` puts the Building back to the Lv 1 podium in Candy. Tags `BuildingStation`, `HospitalLift`, `LiftPrompt`, `EscortPrompt`, `SoakPrompt`. **Parts (measured by `tests/PartBudget.spec`, no creatures, nurses or decor):** rooms 75 of 90, the plot's own share 110 of 115, a whole plot 209 / 268 / 294 / 316 / 331 at Lv 1-5 in Candy and 337 of 400 in the heaviest theme; 18 SurfaceGuis outside the Building |
| `server/Carry.luau` | What each player is carrying (`Carry`, `CarryMax` attributes) and the icon above their head. *(v2)* Capacity = 1 + Bigger Tray + 🧺 Big Hands (read from the save's perks). After a rebirth resets Bigger Tray, items already in hand stay; new pickups wait for room |
| `server/Economy.luau` | Cash, upgrades and purchases. Wires `Purchase` and `PlaceDecor`. *(depth)* `Economy.charge(p, price, apply)` (charge and apply in one update; Levels uses it); `Purchased` also fires kind `"Level"`; rooms check their hospital level (`Progress.canBuyRoom`). *(v2)* Upgrades check `Logic/Progress.canBuyUpgrade` first ("Needs 🏥 Lv 2", "Needs 🏢 R4"); Ward Comfort, A&E Speed and Night Clinic sell like the others |
| `server/Progress.luau` | Clinic ⭐ Stars and the next goal. Its "unlocked" and "ready" toasts skip rooms above your hospital level |
| `server/Book.luau` | Stamps the Patient Book and grants a wing's set reward |
| `server/Story.luau` | The three regulars: who's due, their speech bubble, the reward when a story ends |
| `server/Daily.luau` | `Workspace.UtcDay` and `TodaysVisitor`, banked daily goals, the mailbox. Wires `ClaimGoal` and `ClaimMailbox` |
| `server/DayReport.luau` | Counts each player's cures and new pages, and sends the Day Report when night ends |
| `server/DayNight.luau` | The day/night cycle (`IsNight`, `PhaseEndsAt`) and the relight (look §C1 = art-direction §4.3). `start()` sets `LightingStyle` Soft, `PrioritizeLightingQuality`, `GlobalShadows` and black ColorShifts once (each in its own pcall; a refusal warns `[DayNight] Lighting.<key> not set:`). It finds or makes the `CandyColor` ColorCorrection, the Atmosphere, a Bloom and the `CureRays` SunRays (no Clouds), and tweens `Pure.DAY` / `Pure.NIGHT` (plain RGB) together on each phase. `Pure.nightTooBright` is the night-dimmer-than-day rule (tests/Lighting.spec) |
| `server/Stations.luau` | A hold-to-make prompt on every `Station_*`, with the hold time checked on the server (`Boosts.makeSeconds`: Faster Hands, then MakeSpeed boosts); each make counts for its station badge. A full tray swaps out an item nobody in this clinic's line needs first (it reads `QueueNeeds`), else the oldest different one. *(v2)* Stations inside the hospital Building (the 💊 `Station_Pharmacy` from Lv 4) are found by the tag `BuildingStation`, now and on every rebuild. The Pharmacy crafts: two carried ingredients → one medicine (`Logic/Recipe.craft`; tier 2 from the clinic owner's R2), "💊 Bring two ingredients!" when the hold begins if you can't, and a "🍵 Warm Tonic!" toast. Every hold = `Boosts.makeSeconds` x the plot's team factor (`Nurses.team(plot).Make[station]`) x the ability rush (`Abilities.makeFactor`), never under `BoostMinMakeSeconds`; the shorter of the time at the hold's start and end counts |
| `server/Patients.luau` | A queue per plot (each place in line from `PlotBuilder.queueSpot`; at most `Config.MaxQueue` = 3 at every level), the `Treat` prompt on the Counter (tag `TreatPrompt`), beds, patience (times the owner's Patience boosts), night patients, variants, visitors and regulars. Sets the patient attributes the client acts from (`Ailment`, `State`, `PatienceFraction` in 0.05 steps, only on change). During an owner's tutorial: its two patients, one at a time, no patience running out (steps 1-6), no regulars or visitor. *(depth)* Patients come faster at higher levels (`Levels.spawnSeconds`, 13 s at Lv 1 to 8 s at Lv 5; the line still never passes 3). Recipes cut by the owner's level (`Levels.recipeCap`; always 1 item in the tutorial; only patients the plot can make come), the patient attributes `Recipe`/`RecipeDone` and State `"Treating"` (patience paused), the plot attributes `FrontNeeds`/`QueueNeeds`, a Cheerer's `CheerPatience`, beds under `Rooms` or `Building`. Treat takes the helper's items, then the nurse tray's, and drives `Treatment.open/busy/drop/onHeal`. Creatures move by the creature-motion attributes: one end-pose write per hop, never per frame. *(v2)* 🚑 A&E ambulances (Lv 2+, about every 150 s, only while the owner is at their clinic, past the tutorial, with room in the line and no other urgent patient waiting): the parked Ambulance's `ArriveAt`, the patient pops out at `StretcherSpot` and goes to the front (second behind anyone being treated), a 2-3 item urgent recipe, patience x0.6 (x A&E Speed, the A&E team, a Medic), pays x3 + 2 ⭐. 🚁 The air ambulance (Lv 5 and R2): `HeliSpot.ArriveAt`, then a Sky-wing VIP rides the lift down to the front, x4 + 3 ⭐. After the recipe: its department (`Logic/Hospital.route`), where it rests (the Stand's ground bed, else a ward bed upstairs or a 🛁 tub spot), and the floor pick from Lv 3 only when it really goes to its department's floor (`Pure.routed`: Hydro → a tub, Wards → a ward bed; it steps aside and the line moves up while the helper picks: `Treatment.waitTriage`; a Receptionist or Simple mode sends it at once with the bonus; a ground bed: no question, no bonus): upstairs it waits ("ToLift") for a Porter, or a player only when one who can work here stands near the ground landing (`Lift.waitEscort`, 6 s; Escorted: +20% 💰, rest x0.5), else it rides alone; the lift is held for the ride only; in the tub it is "Soaking" (+25%, rest x0.5) and its `SoakPrompt` opens one 🫧 Scrub game. Rest x Ward Comfort x the team's Recover. Twin Counters (the first of the two front patients you carry items for; Healers serve #2 too), Medics serve 🚑/🚁 patients (`Nurses.Heal` target "Urgent"), abilities on the line (`Abilities.Fired`: RefillFront, RefillLine, PauseLine, CureLine), Busy Doors and a Receptionist shorten arrivals, 🦉 Night Owl, 🌻 Sunny (R1) and 🚁 Sky (helicopter only) wings, 🌟 Golden patients from R3 (2%). Patient attributes `Urgent`, `Dept`, `Escorted`, State "Triage"/"ToLift"/"Riding"/"Soaking". Admin hooks `adminAmbulance`/`adminHelicopter`. The tutorial path (Lv 1, no rebirths) is unchanged |
| `server/CreatureBuilder.luau` | A **blocky** creature Model from its `Look` (`memory-20261117-004`; at most 39 parts with Root and Core: a body block and a head block (a Box is one slice), block arms and feet, each species' own ears (rounded stack, flop, peak, long, tufts), top, extra and `Bits`; a flat block face with big eyes, two glints, blush, a nose and a pixel mouth, plus sick half-lids (`EyeLid`); studs only on one `StudTop` plate cut to whole studs at its size, through World/Studs; world colours via `CreatureBuilder.Pure.world`; `CreatureBuilder.Pure` is the layout in numbers, tested by tests/BlockyCreatures.spec), or a clone of `ServerStorage.Creatures.<PatientId>`. Sized by `Logic/CreatureSize`. Rigged for client acting: every part welds to `Core`, which hangs on `Root.PoseJoint` (Motor6D); arms/wings/flippers and tails on their own Motor6Ds; prop sockets (Attachments) on `Core`; tags `ClinicCreature` and *(depth)* `CreatureMotion`. The badge and bubble stop growing up close (`DistanceLowerLimit`). *(depth)* Sets the motion attributes the clients draw (`hop`, `shake`, `tilt`, `scale`): Feel/CreatureMotion moves Root, Feel/CreatureActing the Motor6Ds under it. `setRecipe` draws a 2-3 item recipe as chips on the badge. `buildLook` builds any Look (a nurse's) on the same blocky body and rig, with a happy face, and `rigKit` gives a kit model the same Root, Core and PoseJoint (NurseBuilder uses both). No Highlights, no shadow-casting lights (kit creatures too). *(v2)* `setDept(badge, deptId)`: the department chip (its ring in the department's colour, the same as the triage floor buttons: Reception orange, A&E red, Wards pink, Hydro cyan, Pharmacy lime, Roof purple), `setUrgent` (the 🚑/🚁 chip and an orange/cyan rim), the Golden look; no new parts. *(look)* The night glow is a square Neon pad still named `GlowRing`; a teapot's top is `PotLid` (only eyelids are `Lid`) |
| `server/Cure.luau` | One cure, in order: pay (with the helper's Cash/Tips and the owner's Stars boosts; *(depth)* the recipe's length and the plot's Cheerer), cash (with `Cured` and this UTC week's `WeekCures`), badge counters, ⭐, Book, daily goals, story, Day Report, the `Cured` remote, then the owner's tutorial. *(v2)* Pay gets `Urgent` (🚑 x3 / 🚁 x4), Night Clinic, the Golden variant (x5), `Extra` x Double Dose (`Abilities.consumeCure`) and bonus stars (urgent + Star Burst); then `Nurses.onCure` (XP). The `Cured` payload always carries `Urgent` ("" = no), `Escorted` and `Soaked`, for Feel/CureFX's bonus lines |
| `server/DecorBuilder.luau` | A decor Model from its `Look`, or a clone of `ServerStorage.ClinicKit.Decor.<DecorId>` (scripts and Highlights removed, lights without shadows). *(look, T4)* The world palette (`calm` / `tint`, no mixing toward white); the existing top parts are studded (the Balloons Box, Shelf Top, Bench Seat, gift Box); glowing decor goes through `World/NightLights.tag(part, "Lamp")`; it no longer requires PlotBuilder; no piece gained a part |
| `server/Visits.luau` | Hearts on the sign (once per owner per UTC day; each one sent counts for ❤️ Friendly): a small "❤️ Send a heart" prompt (within 6 studs, hold 0.3 s, low beside the board and nudged off its words; hidden from the owner). The owner's helpers switch: the `SetHelpers(on)` remote from ⚙️ Settings (a boolean, your own plot only, rate-limited with a 1 s cooldown) sets the plot's `OpenHelpers` and toasts. The friend referral reward |
| `server/Leaderboards.luau` | The global leaderboards ([Leaderboards](#leaderboards)): throttled OrderedDataStore writes from the server's save, cached reads every 2 minutes, DisplayName lookups, admins kept off, the `GetBoards` remote, the Hall of Fame boards' contents |
| `server/BoardBuilder.luau` | Builds the 🏆 Hall of Fame garden past the street's west end, off the main road, with the four world leaderboards in it (`Workspace.TownBoards`), and draws their rows. A library `Leaderboards` uses. *(look, T2)* Each board is a navy plate (white rows, gold values) with its title floating above it, between studded posts in the board's colour on a Slate plinth; "🏆 Hall of Fame" floats in gold; the garden lawn is studded with an 8-stud checker and reads `ClinicTown.Lawn`; lamps go through `World/NightLights`; it no longer requires PlotBuilder. The garden stays past x −137 |
| `server/Admin.luau` | The 🛠️ Admin panel's server side ([Admin panel](#admin-panel)): decides who is an admin (sets the `IsAdmin` player attribute), looks up `Config.AdminNames` at startup, and wires the `Admin` remote: re-checks admin on every call, validates the action and its argument, logs `[Admin] <name> <action>`, then calls the systems' own APIs. Admin-only hooks it uses: `Tutorial.finish`/`restart`, `Patients.sendNext`/`reopen`, `Book.completeAll`, `Story.makeDue`, `Daily.resetToday`, `Playtime.addToday`/`addTotal`, `Badges.maxAll` |
| `server/Treatment.luau` *(depth)* | Treat sessions at the Counter: `TreatStart`/`TreatResult` (one open session per player; any other id is refused and changes nothing; the server's ratings come from `MiniGame.accept`, all OK when the report is too early or the helper is over `Config.Treat.Distance` from the Counter), the timeout (all OK), tips (cash only, capped per cure, × the plot's Cheerer) and the player attribute `Combo`, Simple mode (`SetSimple`), Healer deliveries. Patients drives it through `Treatment.open/busy/drop/onHeal`; it never requires Patients. *(v2)* `TreatSession.Kind` "Soak" (the hot tub's one 🫧 game, a tip under the patient's cap), `Auto` (`Abilities.consumePerfects`: those games are PERFECT on every path), `Ease` (the helper's 🎯 Steady Hands), medicines (one 🧪 Pour fills both slots), the `Triage(session, dept)` remote and `waitTriage` (your own pending pick, one of its Options, inside `Config.Triage.Seconds`; right: "✅ Right floor!" +10%, wrong: "Oops, not this floor!" and it still goes the right way), Medic deliveries |
| `server/Levels.luau` *(depth)* | Hospital levels: `LevelUp` (⭐ is a gate, 💰 is spent, in one update), the plot's `Building` and `Level` attribute (they follow `Data.Level`; a build that fails isn't retried until the level changes), queue/recipe cap/beds/spawn seconds by level (*(v2)* `floors`, `departments`; slots are gone), `LevelChanged (p, level, previous)` only on a change (never at join), the `Celebrate` LevelUp. Studio switch `PreviewLevel`. *(v2)* The building wears the owner's branch theme (`Levels.theme(p)`, from `Logic/Rebirth.theme`) and rebuilds on a theme change; Studio switch `PreviewTheme` |
| `server/Nurses.luau` *(depth)* | Owned nurses. *(v2)* Every nurse you own works (roster 3, +1 a rebirth, max 8; a sale or a rebirth wakes the first resting one), six jobs: Maker (fills the `NurseTray`), Healer (`Heal`), Cheerer (`CheerPatience`/`CheerTip`), Receptionist (at the Counter's right end, "Greeting"), Medic (at the ambulance bay, serving 🚑/🚁 patients with `Heal` target "Urgent", "Treating"), Porter (by the ground landing: `claimPorter`/`escort`/`releasePorter`; a porter left upstairs rides `Lift.carry` back down). A job not open at your level is worked as the role (`Logic/Jobs.effective`). The +40% specialty, Double Shift (x1.25 speed), team bonuses and the plot attributes `TeamBonus`/`TeamCash`/`TeamRecover`/`TeamUrgent`/`TeamMake`/`Reception`/`Triage`/`MedicPatience` (plus `CheerPatience`/`CheerTip`/`NurseTray`). `SetJob` (0.35 s per player). XP from cures (`onCure`: every working nurse, +1 in its specialty, x2 with 📚 Fast Learners; `NurseNews` Level, `Celebrate` NurseLevel at Lv 5 and 10). `grant`/`take`/`give` are the only way a nurse joins or leaves a save (one update each; the Market's undo is explicit, `give(.., true)`, and restores the exact entry its own take removed; a normal give never reads an undo token; `endUndo` ends it), `setListed`/`isListed` (the Market's in-memory lock, cleared on leave), `addToTray`, `adminLevels`/`adminGive`. Workers only while the owner is in the server; the 🧺 `NurseTrayGui` on each Counter; the Journal (`markSeen`) |
| `server/NurseBelt.luau` *(depth)* | *(look, T2: the belt runs down the road's **centre line**, riders face the plaza, and the odds sign is a navy plate at `Config.Belt.SignOffset` facing TownSpawn with a floating "🎲 NURSE ODDS" title and a "🎲 See odds" ProximityPrompt `OddsPrompt`, which the server does nothing with; a warm-white bed with a yellow stripe, a dark conveyor, a studded purple nurse house; `NurseBelt.Pure.SIGN` / `toward` / `riderFacing`)* The shared Nurse Belt along the main street (`Workspace.NurseBelt`, [below](#the-nurse-belt-on-the-main-road)): an arrival about every 40 s, odds, Night Rush, Golden Hour (on server uptime), pity, `HireNurse` (cooldown, distance by the belt formula, the gates, the price by level), the odds sign, `Shout`s, Seen within `Config.Belt.SeenDistance`. Its `Conveyor` has `ConveyorGui > Clip > Stripes` and the attributes `StripeStuds`/`StudsPerSecond` (BeltView scrolls them). *(v2)* The hire checks `Logic/Belt.gate` ("🏥 Lv 3 hospital first!" / "🏢 R1 first!") then `Logic/Nurse.canAdd` ("Roster full: sell or list one"), the price takes 🏷️ Bargain off, and the grant source is "Belt". 🔭 Belt Scout: while a perk owner is in the server the next arrival is rolled one arrival early (with the sign's odds then) and `BeltScout { Rarity, Event }` goes to owners only; if Night Rush or Golden Hour starts or ends before it arrives, that roll is thrown away and rolled again with the new odds (and sent again), so every arrival has the sign's odds. The sign's gate rows say "🏥 Epic+ from Lv 3" and "🏢 Mythic/Secret from R1". A `NextLamp` part (PointLight `Glow`) over the nurse-house door and the belt model's `NextArrivalAt` attribute (written only when it moves by > 2 s). Studio switches `BeltForce`, `ForceGolden` |
| `server/Abilities.luau` *(v2)* | Nurse abilities. Each fires by itself, only when it helps (`Logic/Abilities.useful`), on one 0.5 s loop, never while the owner is away or in the tutorial. Banked ones (Quick Bandage/Soap, Golden Touch, Double Dose, Star Burst) light up and wait for the next treat or cure (`consumePerfects`, `consumeCure`); their cooldown starts then. Cooldowns run in real seconds, kept by the owner's UserId (a rejoin never recharges); once the owner leaves, slots a fresh one would equal are dropped (on leave and every 60 s: `Pure.prune`), so the memory stays bounded. Miracle once per in-game day; Team Spirit recharges the others (never Miracle). Busy Paws / Time Bubble write the plot's `MakeRushUntil`/`MakeRushFactor` (`makeFactor`), Calm Song `PatiencePausedUntil` (`patiencePaused`). `Fired (plot, nurseId, abilityId, kind, value)`, `adminCharge`. The nurse model's `AbilityReadyAt`/`AbilityCooldown`/`AbilityAt`/`AbilityCharges` (the ring fills in 8 steps, never seconds). Effect numbers in `Config.Abilities` |
| `server/Rebirth.luau` *(v2)* | "🏢 Open a new branch": `OpenBranch` (`confirm == true`, loaded and saving, tutorial done, no perk card waiting: "🃏 Pick your card first!", `canRebirth`, no treat session, 5 s per player and a lock; then `Patients.reopen`, a re-check, ONE update where the count read must still be the count written, `Plots.syncRooms`, `saveNow`, the Celebrate Rebirth + Unlock screens, the R5 FounderFennec through `Nurses.grant(.., "Gift")` or waiting in `Pending` with "🎁 A nurse waits for a free slot!"), `ChoosePerk` (only an offered card, `Logic/Rebirth.liveOffer`: an offer whose cards were all renamed or removed becomes the 🌳 Fallback; the offer is saved, so a rejoin keeps it), `BuyNode`, `ResetTree` (free, 2 s), `SetTheme` (unlocked themes only, 3 s per player: each change rebuilds the building), `ClaimBranchNurse`. The plot's `Branches` attribute and the sign's `BranchBadge` ("🏢 n" from R1), the mascot from R5 (an original placeholder blob at the plot's `MascotSpot`, idle hops and a spin on each cure, by the motion contract), the `WalkBoost` attribute and WalkSpeed (👟 Quick Feet), the once-ever "🏢 You can open a branch!" toast (`Told`). API `count`, `effects`, `open`, `choose`, `buyNode`, `resetTree`, `setTheme`, `claimNurse`, `Reborn`, `adminRebirth`, `adminPoints`, `Pure` |
| `server/Agency.luau` *(v2)* | The Nurse Agency. The kiosk `Workspace.NurseAgency` (*(look)* built by `World/Props.kiosk`, 10 parts, studded Cyan walls, a dark roof, floating "🏢 AGENCY"; on the plaza's row-2 side at `Config.Agency.Offset`, its ProximityPrompt `PromptPart.Prompt`, ActionText "Agency"; `ClinicKit.NurseAgency` replaces it). One server-wide stock of 4 distinct nurses (70/26/4, never Legendary+) rolled every `RestockSeconds` of uptime, the Workspace attribute `AgencyRestock`, `AgencyNews` to each player with their own view. `GetAgency`, `AgencyBuy` (§B3.1 in order; the slot is claimed before `Nurses.grant(.., "Agency")` and marked bought only after a true; bought marks in memory by UserId per restock), `SellNurse` (owned, not listed, not rebirth-only, the shown price, 1 s; `Nurses.take(.., "Sold")`). 🍀 Lucky Stock's 2 own slots come from `Logic/Agency.personal` (the shown odds stay true). API `view`, `buy`, `sell`, `restockNow`, `Pure` |
| `server/Market.luau` *(v2)* | The same-server Player Market: `GetMarket`, `ListNurse`, `Unlist`, `BuyListing`, `MarketNews` (to everyone, debounced 0.5 s). Listings live in memory and only lock the nurse (`Nurses.setListed`): it stays in the seller's save and keeps working until it sells. Every §B3.2 check in order (incl. the buyer's gates, roster room and level cap; a price never below `Logic/Market.floor` for the nurse's copies, also re-checked at the buy and on every save change), then, with no yield, the listing off the table, `Nurses.take` (seller) and `Nurses.give` (buyer), an explicit undo (`give(.., true)`) if the give fails, `Nurses.endUndo`; then `writeAfter(seller, buyer, Pure.leaveOut(nurse, price))` and `saveNow` seller THEN buyer. Listings end on PlayerRemoving. The kiosk `Workspace.PlayerMarket` (*(look)* built by `World/Props.kiosk`, 10 parts, studded Orange walls, floating "🏷️ MARKET", facing TownSpawn like the Agency; prompt attribute `Kiosk = "Market"`; `ClinicKit.PlayerMarket` replaces it). API `view`, `list`, `unlist`, `buy`, `Sold`, `Pure` |
| `server/Lift.luau` *(v2)* | The glass lift. `RideLift(floor)` (`ride`: a whole number, you stand within `CarDistance` of one of a building's landings on that floor, the floor exists and isn't yours, not riding, 1 s per player; it answers at once `{ Seconds, From, To }`, then one `PivotTo` after `RideSeconds` x 🛗 Express Lift). `carry(plot, models, floor)` (patients and porters: one `PivotTo` each at the far landing; for the ride each creature has the tag `LiftRider` and `LiftRideAt`/`LiftRideSlot`, so clients ride it in the car), `landing(plot, floor)` (the floor point under the marker, facing out of the lift), `waitEscort(plot, seconds)` (the ground landing's `EscortPrompt`; oldest first). Ride attributes: `Player.LiftRide` "<plot>,<from>,<to>,<seconds>,<serverTime>"; the Lift model's `Ride` "<from>,<to>,<seconds>,<serverTime>", then `Rider` and `RideAt`. The car never moves on the server |
| `server/NurseBuilder.luau` *(depth)* | A nurse Model from its Look (via `CreatureBuilder.buildLook`) with a block cap in its rarity colour (a warm-white brim and our paw-heart, never a cross; `IconAnchor` lifted over it) and sparkles for Epic+, or `ServerStorage.Nurses.<NurseId>`; `setTask(model, task, icon?)` (a small task bubble), `hop(model, from, to, height, seconds, spin?)`, `popIn(model)`, `setGlow(model, on)`. *(v2)* `setJob` (the job hat chip on the task bubble), tasks Escorting/Greeting/Treating, `addAbility`/`setAbility` (the "AbilityRing" billboard beside the bubble, shown within 40 studs; Feel/HospitalFX draws its smooth ring inside it and hides the server's coarse fill) |

### Client
| File | Does |
|---|---|
| `client/Main.client.luau` | Builds `ctx` (Remotes, Config, Data, State, `onState`, `toast`, `on`/`fire`), then loads each UI and Feel module in a pcall and calls `init(ctx)`. *(v2)* Forwards `AgencyNews`, `MarketNews` and `BeltScout`; `ctx.Data` has `Jobs`, `Departments`, `Abilities`, `Perks`, `Tree`, `Themes`; the default snapshot has `Rebirth` |
| `client/UI/Theme.luau` · `client/UI/Kit.luau` | The look tokens, and building blocks (panel, button with press bounce, label...). Libraries, not inited. *(depth)* Theme.Juice timings, Theme.Confetti, DisplayOrder.Celebrate (45); Kit.countUp (rolling numbers that tick), celebrate, confetti, rarityFrame (the rarity's gradient outline; **still** since the look overhaul), rarityColor, breathing (idle calls to action), punch, isShown, setDot (pops once, then still), button hover, Kit.Juice (pure helpers), Kit.Ticked. *(v2)* `Kit.ring` (a filling ring, never seconds) and `Kit.holdButton` (hold-to-confirm), first versions for T8 to juice. Every looping effect runs on one shared loop that skips hidden UI and sleeps. *(v2, T8)* `Kit.ring` is 12 beads lighting clockwise (ready = outline + a bump; never seconds), `Kit.holdButton` a fill band with a gentle swell and a tick each quarter (stepped when calm), `Kit.setDot(button, visible, glyph?)`, pure helpers `Kit.Juice.ringFraction`/`ringBeads`/`holdFill`. *(look, T6)* The button **roles** (`Kit.Juice.role`, `LOOKS`, `mayLoop`: Primary, Collect, Secondary, Quiet, Destructive, Icon, plus the Disabled look; old candy kinds map onto them), `Kit.setRole`, the `Kit.button` `Fill` prop (game pieces only), `Kit.iconButton` as the white Icon plate (`Glass = true` for the top-bar row), `Kit.tab`, `Kit.textLimit` (never under 18 px), `Kit.HEADER` (64), `Kit.corner` taking px or a UDim. **The motion budget:** shine and breathing run only on a Collect button, one owner on screen (topmost DisplayOrder, then oldest: `Juice.pickPerpetual`); nothing else loops |
| `client/UI/Toasts.luau` | *(look, T5)* THE notice stack: toasts and the bus `Banner`s in one column, 8 px under the Now card (`Hud.Pure.noticeTop(Hud.nowBottom())`, following `Hud.NowMoved`) and as wide as it, in a DeviceSafeInsets ScreenGui. White plates with ink text, the Bold stroke, the Large radius, the one shadow; a banner adds an icon tile in its event's colour (BeltView: Golden Hour, Night Rush, Epic+ arrivals; BadgeBook's cheers). The same Id updates in place, `Seconds = 0` hides it. Nothing loops (no shine) |
| `client/UI/Hud.luau` | *(look, T5)* The HUD, built on `Logic/HudZones` ([The HUD zones](#the-hud-zones)). **System:** a TopbarSafeInsets ScreenGui `HudSystem` holds ⚙️ on a dark-glass plate (and, on phones, the wallet). **Wallet:** 💰 and ⭐ as an icon plus a big outlined number (both roll up, `Kit.countUp`, as flying coins and stars land: `Hud.fly`), ⭐ with its thin bar to the next unlock, the 🔥 combo sticker. **Now** (ScreenGui `HudNow`): `Hud.setNow(source, card?, priority)` and `Hud.nowBottom()` (px from the device-safe top, the top-bar row included); the highest priority shows, the newest on a tie; Hud's own cards are the warning (⚠️ Not saving / 🏠 Clinics full, 30) and the tracked goal ("🎯 Cure 5 · 3/5", 10; a tap opens Goals); `Hud.NowMoved` (a Signal with the bottom), `Hud.topbar()`. **Status** (read-only, top right; on phones the strip between the Now card and the right rail, in fewer words): "☀️ Night in 3:27" / "🌙 ×2 · 2:08 left", ONE free-event chip ("🌟 Golden Hour in 12m": `Logic/NextEvent`, Golden Hour only, minutes, never paid, hidden while it runs or past 6 h), "Visitor ⭐/✅", at most 3 boost chips. **Rails:** fixed slots in `HudZones.ORDER`, every plate the same `Kit.iconButton` (the Shop looks like its neighbours), red dots, the 🃏/🌳 Branch sticker on 🛒, 🎁's bar inside its plate; pieces that don't fit become ⚙️ rows ("More"), and `Hud.target` then points at ⚙️. **Hands:** bottom centre, 56–84 px; the red ✖ is a 0.5 s hold (a tap toasts "Hold ✖ to throw away"). **⚙️:** 🎵, ✨/💤, 👆 Simple, 👥 helpers, ⏭️ Skip tutorial (while it runs) or 🔁 Replay tutorial (once done, with a clinic), More, 🛠️ Admin; Skip and Replay fire the bus `SkipTutorial` / `ReplayTutorial`. **Hide rules:** `ModalOpened` / `ModalClosed` by name: a Panel hides the rails, Now and Status; a Game hides the rails and Status; a Popup nothing; while the `Celebrate` ScreenGui is Enabled everything hides. **First session:** 💰, then ⭐ after the first cure, 🛒 at the shop step, 📖 at the Book step, each in its fixed slot; at DONE the rest pops in 0.15 s apart after the finale closes; a replay keeps the HUD full. Kept as before: portraits, `fly`, `shopNews`, `decorSlots`, `ask`, `livePlay`, `liveBoosts`, `boostLine`, every modal re-export and every `Hud.target` name. Ready mail, goals and gifts bounce (`Hud.pop`). Nothing loops; the rules are `Hud.Pure` (tests/HudScreen) |
| `client/UI/PlayGifts.luau` | The 🎁 panel: the Doctor rank card ("Doctor rank: Resident", time played, next rank), your boosts, the six gift cards (🔒 time left · Open! · ✅). *(look, T6)* On the template; claims are Collect, tiles neutral |
| `client/UI/BadgeBook.luau` | The 🏅 Badge Book (category tabs, a card per badge with its tier frame, progress, next tier's boost and rewards), and the cheer for tier-ups and Doctor ranks, sent as the bus `Banner` (UI/Toasts draws it; one at a time, never in the tutorial). *(look, T6)* The category tabs are the `Modal.tabs` column |
| `client/UI/Shop.luau` | Upgrades, Rooms and Decor tabs, plus decor place mode. *(depth)* The 🏥 Hospital tab (`Open("Shop", "Hospital")`): the level ladder, this level's stats, the next level's unlocks, its ⭐ gate and 💰 cost, Level up; `Shop.levelUpButton()`. Rooms that need a higher level show "🏥 Lv 3". *(v2)* Gated upgrades show "🏥 Lv 2" (grey with 🔒; a tap opens the 🏥 tab) or "🏢 R4" (grey, no lock; a tap says what it needs) from `Logic/Progress.canBuyUpgrade`; the level card lists the departments open at each level; the 🏥 tab's calm 🏢 Branch card (at Lv 5 "Need 💰50,000" and "Look 👀" → `Open("Branch", "Open")`; with branches 🃏 🌳 🎨 buttons and a line for a card to pick or tree points; having the cash never changes anything); `Shop.Pure`. *(look, T6)* On the template: `Modal.tabs`, the 💰 meta chip, neutral Well tiles; Buy and Level up are Primary with no shine; can't-yet is Disabled with its gate text (still tappable: "Need 💰n more!"); Branch links are Secondary; place mode shows your current spot in navy |
| `client/UI/BookPanel.luau` | The Patient Book: cards by wing, silhouettes for patients not yet seen. *(v2)* Calm gate chips on the Sunny and Sky pages ("🏢 R1", "🏢 R2 · 🚁", no lock icon), and Golden pages get 🌟 first among the stickers and a gold outline. *(look, T6)* The wing colour is a 6 px tab stripe, the meta chip counts up "📖 n%", the NEW! sticker no longer breathes |
| `client/UI/DayReportPanel.luau` | The end-of-night pop-up (never during the tutorial). *(look, T6)* The count at Hero size, one Primary 🛒 with no shine or breathing, calm chips |
| `client/UI/Mailbox.luau` | The daily gift and the goals list. The letter pops once a session, never over a panel, and after the tutorial ends. *(look, T6)* On the template; claims are Collect (the one shine on screen) |
| `client/UI/Guide.luau` | The first-cures guide, drawn by UI/Wayfinder (the floor beam, chevrons, one glow, the pin, the touch hand): the right station, then the Counter once you carry anything the front patient still needs (`FrontNeeds`); until `Config.Tutorial.ArrowsUntilCures` cures, a tutorial Skip included; it comes back for a Replay. UI/Tutorial steers it with `Guide.setSteer` (Steer = `{ Part, Target?, Icon, Color, Height?, Beam?, Glow?, Hand?, Base? }`). Also sets each station prompt's hold time from the Snapshot's `MakeSeconds` (your Faster Hands level and boosts, per station; *(v2)* times its plot's `TeamMake` factor and `MakeRushUntil` / `MakeRushFactor`, unchanged). Station prompts by their tag only. Rests when there's nothing to show |
| `client/UI/Tutorial.luau` | The tutorial's top-centre Now card (`Hud.setNow("Tutorial", card, 20)`): the TUTORIAL n/7 tab, the ⏭️ Skip chip, the thumbnail, the title and the device's words (the key from `GetStringForKeyCode`, the pad's own glyph), the 7-segment bar, the guide nurse's face and 2–4-word lines; the ✓ beats, the CURED! moment, the finale (Celebrate Kind "Tutorial" with one free COMING UP chip); card 7's UI pointer ("Buy this! ⚡", never "Spend"); the idle nudge; Skip and Replay behind `Hud.confirm`; the welcome sweep (acks as it ends); turns the camera to your clinic when you arrive. `Tutorial.Pure` (tests/TutorialFlow) |
| `client/UI/PromptFilter.luau` | Hides world prompts that aren't for you: "Send a heart" for the owner, and the Make and Treat prompts on clinics you can't work at (the server still checks). Finds prompts by tag (and each plot's Counter), never by scanning the town. *(v2)* `EscortPrompt` and `SoakPrompt` count as work prompts (hidden on clinics you can't work at); the `LiftPrompt` stays for everyone |
| `client/UI/Boards.luau` | The 🏆 leaderboards panel: a tab per board, the top 10, and your own bar ("You: #12"), from `GetBoards`. *(v2)* A 5th tab, 🏢 Branches (Most Rebirths); the tab column scrolls so five fit a short phone. *(look, T6)* The board colour is a tab stripe, the board's name is the meta chip, your bar is navy |
| `client/UI/AdminPanel.luau` | The 🛠️ Admin panel ([Admin panel](#admin-panel)): buttons only, each one asks the `Admin` remote and toasts the reply. *(look, T6)* Four tabs (🛠️ Tools, 🏢 Branch, 🤧 Patients, 🎁 Nurses); every tool is Secondary; Restart tutorial, Rebirth now and Reset goals are Destructive and ask `Hud.confirm` first |
| `client/UI/AgencyPanel.luau` *(v2)* | The Nurse Agency (`Hud.modal`): 🛒 Hire (4 cards, 6 with 🍀 Lucky Stock: portrait, rarity frame, job/specialty/ability icons, "Hire 💰150" · "✅ Bought" · "🏥 Lv 3" / "🏢 R1" · "Roster full" (opens the Team page) · "⭐ MAX") and 💰 Sell (the sell-back price, "🏷️ Listed", "🏢 Stays") tabs, the 🎲 odds popup (the server's own odds, "🚫 Never Legendary+"), "🔄 New nurses every 5 min" (no clock). A confirm before every buy and sell ("Not now" the default), a 1 s hold for Epic and up and for any nurse at Lv 2+ (its levels go for the flat sell-back). Opens on `Open("Agency", "Hire" \| "Sell"?)`, the bus `Sell (nurseId)` and the kiosk's prompt (`ProximityPromptService`, so streaming never matters). *(look, T7)* Hire and Sell are `Modal.tabs` column tabs, no panel colour; hire and sell go through `Hud.confirm` (`Pure.confirmSpec`: Hire Primary, Sell Destructive, a 1 s hold for an Epic+ or any nurse at Lv 2+), the odds through `Hud.oddsPopup` (a Quiet "🎲 Odds"; `Pure.oddsSpec` / `oddsNotes`) |
| `client/UI/MarketPanel.luau` *(v2)* | The Player Market (`Hud.modal`, tabs as big icons in a left column): 🛒 Buy (listing cards "by DisplayName", Buy or the reason you can't, a confirm "Buy 🐶 Lv 7 for 💰420?"), 🏷️ Sell (your sellable nurses, a price picker locked to the band for its level and copies, never below what the Agency pays after the fee, with − / + steps and a slider, "You get 💰378" big, List it! after a confirm), 📋 Mine (n/3, Unlist). Badges "🏷️ Only this server" and "🚫 No swaps. No chat." Opens on `Open("Market", "Buy" \| "Sell" \| "Mine"?)`, the bus `List (nurseId)` and the kiosk's prompt. *(look, T7)* Tabs via `Modal.tabs`, buy and list via `Hud.confirm` (`Pure.buyConfirm` / `listConfirm`), no panel colour |
| `client/UI/BranchPanel.luau` *(v2)* | The 🏢 Branch panel: 🏢 Open, the keep/reset screen (✅ `Logic/Rebirth.KEEP`, 🔄 `RESET` with your start perks beside them, 🎁 `GET`: +25% 💰⭐ while it still adds up, +3 🌳, a card, +1 nurse slot to the roster max, the new theme, the next unlocks), what it needs ("Need 🏙️ Lv 5 · 💰50,000", ✅ when met; the cash row says ALL cash starts fresh: "💰 Cash: 💰180,000 → 💰0", `Logic/Rebirth.startCash`), a big "Not now" (the default focus) and "🏢 Open branch!" (a 1.5 s `Kit.holdButton` asking `OpenBranch(true)`; while a card waits it says "🃏 Pick your card first!" and shows the 🃏 tab); 🃏 Perks (the offered cards, "✅ Take it", the odds in words, every perk with ✅ when owned, the 🎁 Claim row); 🌳 Tree (three branches, rank pips, the capstone lock "6 🌳 in Care", 🔄 Reset behind a confirm); 🎨 Themes ("✅ On", "🎨 Pick", or "🏢 R3"). Opens on `Open("Branch", "Open" \| "Perks" \| "Tree" \| "Themes")`. *(look, T7)* Its four tabs are column tabs; the tree reset goes through `Hud.confirm` (`Pure.resetConfirm`, Destructive); "🏢 Open branch!" is a 1.5 s Primary hold; theme cards show only Roof and Trim swatches (`Pure.SWATCHES`) and "🎨 Walls stay your colour" |
| `client/UI/LiftPanel.luau` *(v2)* | The lift: a `LiftPrompt` opens a floor picker (one 64 px button per floor of that building, top first: "🚁 R" "💊 3" "🛁 2" "🛏️ 1" "🛎️ G", yours shows 📍) that asks `RideLift(floor)` and closes if you walk away. Your ride (your `LiftRide` attribute): a Ding, the doors close, your root rides with the car so the camera eases along, then you step out; calm: you just appear there. Other rides (the Lift model's `Ride`) slide the car near the camera. Patients and porters (`LiftRider`) step into the car, ride in it and step out at the far landing on clients near it (beside you when you escort one); calm or far: the car just moves. Nothing runs every frame. *(look, T7)* A Popup on the template with big Secondary floor buttons; its PURE block is unchanged |
| `client/Feel/HospitalFX.luau` *(v2)* | Hospital v2's juice, driven by server attributes and only near you: the ambulance's red/blue flash and a soft toy siren on a fresh `ArriveAt` (calm: slow soft lights, no siren), a 12-part client-only helicopter onto `HeliSpot` on its `ArriveAt` (one tween in, a rest, one out; calm: a fade), ability sparkles and a floating icon on a nurse's `AbilityAt` (calm: the icon only), a `Kit.ring` cooldown ring inside each nurse's "AbilityRing" within 40 studs (4 updates a second, only while one is near), another player's lift ding (`Rider`/`RideAt`), and the building's grow-in after a fresh `GrewAt` or a theme change (never on joining) |
| `client/Feel/Sounds.luau` | One table of built-in `rbxasset://` sound cues; any module plays one with `ctx.fire("Sound", name)`. *(depth)* Plays the mini-game ratings (`MiniGameRated`), Tip and Combo (`TreatDone`), Hire/Equip/Sparkle (`NurseNews`) and a Tick per count-up number (`Kit.Ticked`). Cues may be cut short (`Length`); `play(name, volume?, pitch?)`. *(v2)* The §B9 cues (`Rebirth`, `Perk`, `Node`, `Ability`, `Siren`, `Heli`, `Ding`, `Sold`, `Bought`, `Restock`, `Triage`, `Splash`, `Brew`, `LevelNurse`, plus `Tag`); NurseNews Job plays Equip, Level LevelNurse, Sold/Gone Sold, Bought, Listed Tag; a Pharmacy medicine in your hands plays Brew. *(look)* `Chirp` (the guide nurse's line), listed in `Sounds.LOOK_CUES` |
| `client/Feel/CureFX.luau` | Cure sparkles, the "💰 +n" / "⭐ +n" pop, the NEW PAGE banner, placed-decor celebrations, hearts on your sign. *(depth)* Coins and stars fly from the cured patient into 💰/⭐; a new room fires the Celebrate screen (Kind Room); sparkles over the patient on Good/Perfect ratings and tip coins (`TreatDone`). *(v2)* Bonus lines on the cure pop: "🌟 Golden!", "🚑 ×3" / "🚁 ×4", "+20% 🛗", "+25% 🛁" (numbers from Config, facts from the `Cured` payload); Golden cures get gold sparkles and a chime |
| `client/Feel/Atmosphere.luau` | Snow while `IsWinter`, fireflies at night, gentle decor sway, the calm-effects setting (`ReduceEffects`; its switch is in the HUD's ⚙️). Each part sleeps when idle |
| `client/Feel/CreatureActing.luau` | Every patient near you **acts out its ailment** (`Data/AilmentActing`): it sets the creature's Motor6D `Transform`s on this client only (never `Root.CFrame`), so it hiccup-hops, sneezes, coughs, sways dizzily, sniffles, droops, tugs, shakes off mud, shivers or warms its nose, and waves (then bounces with a "!") as its `PatienceFraction` runs low. Treated: the props pop off with a sparkle; Cured: a happy wave, a wag and candy sparkles. Calm effects make it all small and slow. No loop runs when no creature is around |
| `client/Feel/CreatureProps.luau` | Its library: the client-only props (a glass of water, tissue and red nose, mask, plaster cross and circling ⭐, cheek plaster and a tear, an empty jar, honey, mud spots, a scarf, an ice cap and earmuffs), the particle bursts, the extra mouths (hic, ooh, achoo, chattering teeth) and squeezed-shut eyes (> <), the cold cheeks, the dimmed night glow and the "!" |
| `client/Music.client.luau` | Background music (`Config.Music`), day and night playlists, muted by `MusicMuted` (its switch is in the HUD's ⚙️) |
| `client/UI/Celebrate.luau` *(depth)* | Big celebration screens on the bus `Celebrate`: dim, confetti rain, rays, the reward bubble (a nurse's face with its shimmering rarity frame), a title ribbon, chips (level unlocks, rarity and role, a Journal set's cash and decor, a room's name) and a breathing 🎉 Yay!; one at a time, waits out the tutorial, closes itself after 7 s; a treat card stays playable (one nobody tapped for, NurseLevel or a lone Unlock, waits for an open card to close; a card opening closes whatever is up: `MiniGames.isOpen`); on close the cash flies to 💰 and a new nurse to 👩‍⚕️. *(v2)* Kinds Rebirth (the theme's colours, "🏢 n" on the bubble, chips 💰⭐ ×, 🌳 +3, +1 nurse slot, and the Unlock events right after it folded in as chips, Golden with its odds; "🃏 Pick a card!" → `Open("Branch", "Perks")`, any other close just closes; 🌳 points fly to 🛒), Perk, NurseLevel (an ability upgrade at Lv 5/10), Unlock; a new nurse shows its ability chip. *(look, T8)* Kind "Tutorial" (shown while the tutorial runs: the guide nurse's face, its chips and ONE free COMING UP chip in minutes); restyled on the tokens (flat, `Radius.Large`, a Hero title, one shine on its Collect Yay, no breathing; the rarity frame is still); a Rebirth's ribbon and rays in the theme's Roof, its ring in the Trim (walls stay the plot colour); fires the bus `CelebrateClosed` (kind). The ScreenGui is named `Celebrate` (Hud watches its `Enabled`) |
| `client/UI/MiniGames.luau` *(depth)* | The treatment mini-games on `TreatStart`: a candy card, one game per recipe item (🧪 Pour hold-and-release, 🩹 Patch tap the sore spots, 🛁 Scrub pop the bubbles, ☕ Cool blow at the biggest steam ring), touch/mouse plus Space or gamepad A, a big outlined PERFECT!/GOOD!/OK! pop and the 🔥 combo chip; Simple mode is one tap per game; then `TreatResult` (never sooner than the games' minimum time), `MiniGameRated` and `TreatDone` (it shows the server's ratings and tip). *(v2)* `Auto` games show "✨ Magic help!" and a ✨ PERFECT! pop and are skipped (the minimum report time counts only games played), `Ease` widens the Perfect windows exactly as the server would allow, the Soak card ("🫧 Bubble bath!"), and the Triage card after a finished treatment ("🔀 Which floor?": one big button per department in its badge colour over a soft bar with no digits; one tap asks `Triage(session, dept)`). *(look, T6)* On the Modal template (HudMode Game, no X, a dim that takes no input, ButtonB never closes it); the game's title in the navy header and the 🔥 combo as the meta chip; the pad's own button picture via `GetImageForKeyCode`; no draining bar during the tutorial (`Pure.drainBar`); `MiniGames.stage()` returns the Stage while a run is up; triage floor buttons keep department colours (`Fill`) |
| `client/UI/NursePanel.luau` *(depth)* | The 👩‍⚕️ panel: the Nurse Journal (rarity tabs, silhouettes / greyed / full colour, completion %, group rewards, NEW! stickers and fly-in stamps). *(v2)* *(look, T7)* One tab column (`Modal.tabs`, which scrolls on a short phone: 👩‍⚕️ Team n/cap, the rarities with a rarity stripe, 🏢), the header meta chip "📔 n%", the Team page headed by 🏢 Agency / 🏷️ Market buttons; neutral cards with the rarity frame on the face tile only; a finished set shows a still gold badge; the cap's mark is a white ♥, never a cross, a 🏢 Journal tab for rebirth-only nurses ("🎁 Claim" while one waits: `ClaimBranchNurse`), and the Team page: roster n/cap and "💤 n resting", team chips, the gift row, a card per nurse (level, an XP bar, specialty, the ability with a `Kit.ring` from the plot nurse's `AbilityReadyAt`/`AbilityCooldown`, a job picker asking `SetJob` with closed jobs as "🏥 Lv 2", 💰 Sell → bus `Sell`, 🏷️ List → bus `List`, "🏷️ Listed" from `MarketNews`). `NursesNew` (Seen, Hired and Level news) for the 👩‍⚕️ dot. Equip/Unequip and the slot strip are gone |
| `client/UI/BeltView.luau` *(depth)* | Smooth belt riders (the frame loop sleeps while the camera is far from the belt), a focus card per rider (rarity frame, role and stat, your price, Hire; the HirePrompt in the Custom style with its key on the card) and small stud-sized chips, only within 50 studs of you, Epic+ glow, the scrolling conveyor stripes (one repeating tween; still with reduced motion), the 🎲 odds popup (bus `Open` (`"NurseOdds"`)), Golden Hour / Night Rush / arrival banners (never in the tutorial, never a countdown). *(v2, owner T3)* Cards show "🏢 R1" for Mythic/Secret before the first rebirth (no lock, no price), prices with 🏷️ Bargain off, and with a full roster "👥 Roster full" with "Sell or list one" (opens the Team page); a "🔭 Next: <rarity>" chip over the nurse house for Belt Scout owners; the house lamp brightens as the next nurse nears, with no numbers. *(look, T2)* No 🎲 chip over the sign: the odds open in `Hud.oddsPopup` from the sign's `OddsPrompt`, the hire card's Quiet "🎲 Odds" button and the bus `Open` (`"NurseOdds"`) (the Journal's 🎲), with rows from `Pure.popupRows` / `popupNotes` (now's block first, each line the word and the number). The hire card is 240 px wide, Hire is Primary, chips are at least 100 × 53 px so text never drops under 18 px |
| `client/Feel/CreatureMotion.luau` *(depth)* | Draws creatures' hops, head-shakes, droops and pops on each client from their attributes (the server writes only each end pose). Runs only while something moves. Nurses' rarity sparkles follow this client's reduced motion |

### Tests
| File | Does |
|---|---|
| `tests/run.luau` | Runs every `tests/*.spec.luau`, prints PASS/FAIL and exits 1 on any failure |
| `tests/expect.luau` | `test(name, fn)` and `expect(x).toBe(y)`, `.toEqual(t)` (deep) and `.toBeTruthy()` |
| `tests/worldmock.luau` *(look)* | A small Instance mock (Lune's roblox datatypes): `World.new()` gives a fresh world whose `load(path)` runs the shipped server modules; `setVariant(on)` is the **studs switch** (adds the `CureStuds` MaterialVariant), `setNight(on)`, `parts(root)`, `box(part, pivot?)`. `Hospital.spec`, `PartBudget.spec`, `Studs.spec`, `Palette.spec` and the tasks' world specs build what ships with it |
| `tests/uirules.luau` *(look)* | `check(paths)`: the UI rules on the shipped source: no `MinTextSize` or literal `TextSize` under 18, no local `paintTab` / `textLimit`, no corner-radius literals, no panel-specific header colour (`Accent = `). `-- uirules: allow <Rule>` excuses one line |
| `tests/look.luau` *(look)* | `hsv`, `luma`, `maxChannel`, `hueGap`, `round`, `isBigFace(part, area)` for the look specs |
| *(look)* specs | `Palette` (the palette rules, the Theme tokens, the helpers' own checks), `HudZones`, `NextEvent`, `Building`, `Studs` (both modes, `refresh`, the shared look pieces, the night lights' day restore), `TownLayout`, `PartBudget` (v2's budget test moved out of `Hospital.spec`: every level × every theme ≤ 400, the three shares as hard limits, the town ≤ 600, with the counts printed), `Lighting` (T1: the §C1 tables checked against Lune's real Lighting properties, `start()` and the phase loop, the night-dimmer rule, the night lights' restore rule in both stud modes, and a night/morning round trip of the whole built world), `TownWorld` (T2: the built town, Props' contract, the Hall of Fame, the belt and BeltView pure blocks, uirules on BeltView), `Hospital` (T3, rewritten: slabs, lanes, flights, every §B4 name at Lv 1–5, budgets per level × theme, bed and tub routes on the real geometry, themes paint only Trim and Band), `PlotWorld` (T4: the real PlotBuilder and DecorBuilder: the shares, the Pad, Counter, sign, Stand spots, lane, annexes, palette, both stud modes, decor), `HudScreen` (T5: Hud.Pure: the Now priority, the chips, the reveal, the hide modes, Status placement on 12 screen sizes from 640x360 to 2560x1440), `Chrome` (T6: roles, the motion budget, the 18 px floor, confirm defaults, odds rows, MiniGames on the template), `ProgressionPanels` (T7: the confirm specs, the Agency odds spec, the template in the source), `TutorialFlow` (T8: the server's remote rules, Wayfinder.Pure, the cards' words, the finale, Celebrate's Tutorial kind), `BlockyCreatures` (T9: the blocky layout for every species and the real CreatureBuilder and NurseBuilder under the worldmock), `UiRules` (integrator: tests/uirules over every `src/client` file, roles only, no cross glyph or toy brand anywhere, one tab scroller, a still rarity frame) |
| `tests/config.luau` | The real `Shared/Config` for specs (a stub stands in for `Vector3`), so the belt's odds, placement and the line length are checked on what ships, not on copies |
| `tests/*.spec.luau` | `Schema` (incl. a v2 save with play time, stats and badges migrating to v3), `Data` (incl. creature sizes, `Bits` and `AilmentActing`), `Pay`, `Prices`, `Progress`, `Book`, `Story`, `Daily`, `Tutorial`, `Admin`, `Leaderboard`, `CreatureSize`, `Playtime`, `Boosts`, `Badges`, *(depth)* `Recipe`, `MiniGame`, `Belt`, `Levels`, `Nurse`, *(v2)* `Jobs`, `Abilities`, `Rebirth` (incl. the table test of every save field kept or reset), `Tree`, `Agency`, `Market` (incl. the band and fee table), `HospitalLogic` (Logic/Hospital; `Hospital.spec` is T6's). Plus the pure blocks of Roblox modules, loaded straight from the source between their markers so they test the shipped code: `ServerPure` (Patients, Treatment, Stations; *(v2)* spent items and medicines, auto ratings, ease, triage), `TreatmentSessions` (the real Server/Treatment under mocked services: one session per player, junk and stale ids, early reports, the tip cap, the timeout, drop, a helper leaving, Healer routing; *(v2)* auto-Perfect, a medicine as one Pour, Soak tips, Triage right/wrong/junk/late, Medic routing), `NurseServer` (Nurses, NurseBelt), `NurseUI` (BeltView, and NursePanel's Team page and job picker), `MiniGamesPure` (UI/MiniGames; *(v2)* the session's Kind/Auto/Ease, the ease scaling, the triage card), `Juice` (UI/Kit, UI/Celebrate; *(v2)* the ring and hold helpers, Celebrate's v2 kinds, Guide's HOLD, BookPanel's GATE, CureFX's BONUS and HospitalFX's PURE blocks, the Sounds cues), `Motion` (Feel/CreatureMotion, the badge's recipe row, the urgent icon). *(v2)* Server modules running under mocks: `NurseWork` (T1: the Nurses and Abilities pure blocks, and the real Server/Nurses: grant/take/give, the Market's undo, two buyers in a frame, the roster waking, SetJob, XP), `RebirthServer` (T2: the real Rebirth/Economy/Carry/Plots: one rebirth from three clicks, the count check, a rejoin keeps the offer, perks, the tree round trip, themes, the gift nurse), `AgencyServer` (T3: Agency's checks in order, no buy-and-sell profit, the odds over 20,000 stocks and Lucky Stock's over 200,000 slots, NurseBelt/BeltView/AgencyPanel pure blocks), `MarketServer` (T4: the real Server/Market: two buyers in one frame, a seller who left, a changed price, the band, a full roster, a failed buyer update restoring the seller with cash conserved, the save order and `writeAfter`), `BranchUI` (T5: BranchPanel and Shop pure blocks: the keep/reset rows R0-R25, the waiting-card gate, ≤ 6 words), `Hospital` (T6: layout, which floors exist, the lift rules, the Pharmacy craft and hold floor, and the real PlotBuilder and DecorBuilder under an Instance mock: ≤ 400 parts at every level and theme, 548 with every decor slot filled, the contract names, the clearances), `HospitalPatients` (T7: routing, triage, escort, the tub, the urgent recipe and place in line, Twin Counters, Golden/Sunny/Sky) |

## The look overhaul
Plan: `docs/plan/2026-11-17-look-overhaul-build-plan.md`. The Foundation (Task 0) is frozen: `Config`, `Types`,
`Remotes`, `Palette`, `Data/*`, `Logic/*`, `World/Parts`, `World/Studs`, `Theme`, `Main.server`, `Main.client`,
`State` and the Foundation specs and helpers. A task that needs a change there files a Request with the lead.
The nine build tasks (T1 lighting, T2 town, T3 hospital, T4 plot and rooms, T5 HUD, T6 chrome and core panels, T7
progression panels, T8 tutorial, T9 blocky creatures) are integrated; nothing below is a stub any more.

### New and split modules *(look)*
| File | Does | Owner |
|---|---|---|
| `shared/Logic/Building.luau` | The hospital's **interface numbers** (plot-local studs): footprints per level and floor, storey heights and slab tops (12, 23, 34, 45; a slab ≤ 0.6 thick), the lift shaft and landings, the door rects, the canopy, the Stand's spots (Remedy, Plaster, `Bed_1`, the decor slots, `MascotSpot`, the bench), the ward beds. `obstacles(level, floor)`, `clear(rect, level)` and `reach(from, to, level, floor?)` check them against what `Patients` assumes | frozen |
| `shared/Logic/HudZones.luau` | The HUD zone map: `ZONE` (every piece in one zone), `ORDER` (the rails' fixed slots), `layout(safeW, safeH, topbar?)`, `nowWidth`, `railRect`, `nowRect` | frozen |
| `shared/Logic/NextEvent.luau` | The "coming up" chip: `pick(now, candidates, maxAhead?)` (the soonest FREE event within 6 h; never one with `Paid = true`) and `label(seconds)` ("in 12m": minutes only) | frozen |
| `shared/Data/Guide.luau` | The tutorial's guide nurse: a placeholder name (never shown) and an original `Look` | frozen |
| `server/World/Parts.luau` | The generic part and label helpers, moved from PlotBuilder (`part`, `soft`, `ball`, `cylinder`, `wedge`, `marker`, `paint`, `rounded`, `surface`, `iconBadge`), plus the shared look pieces: `floatText` (outlined text, **no board**), `navyPlate` (a board only where there is a table to read) and `pawHeart` (our placeholder mark; it replaces every cross) | frozen |
| `server/World/Studs.luau` | The studs look: `mode()`, `apply(part)`, `smooth(part)`, `refresh(root)`, `Pure` ([below](#studs)) | frozen |
| `server/World/NightLights.luau` | Parts that glow after dark: `TAG`, `tag(part, "Lamp" \| "Window" \| "Sign")`, `light(part, range)`, `wire()`. Each part's day Material and Color are stored and restored, so a studded part comes back studded. The day look is read again at each nightfall (the attribute `NightLit` is set while lit), so a part recoloured or re-studded after tagging, tagged at night, or cloned while lit still comes back. A Window goes warm SmoothPlastic, never Neon, with its Transparency kept. Every Light under a tagged part is made shadowless. Parts tagged by hand (no `NightKind`; Story's sign star) keep the old rule: SmoothPlastic by day | T1 |
| `server/World/Props.luau` | The shared scenery: `tree`, `bush`, `lamp`, `bench`, `fence`, `planter`, `kiosk(parent?, at, spec): { Model, Counter, Front }` (the shared 9-part shell both kiosks use). Signatures and part counts are contract: a tree is 6 parts (a Wood trunk and 5 studded cubes in three greens; the Model attribute `Blossom`), a bush 1, a lamp and a bench 3 each (the lamp head is a NightLights Lamp), a fence at most 2 + floor(length/14) + 1 | T2 |
| `server/TownBuilder.luau` | The town round the plots: `build(count)` and `spawn()` (TownSpawn at `Config.Town.SpawnOffset`), `Pure.plotRects` / `lawnRegions` / `checker` / `blossom`. The studded `Lawn` with 276 GrassB checker tiles (one Texture instead once `Config.Look.CheckerTexture` is set), the dark smooth road with edge lines and zebra crossings (no centre dashes, nothing in the belt's lane), Slate curbs, the plank plaza (2 benches, 2 planters, 4 lamps), 26 voxel trees (4 blossom), the arches with the motto floating on a dark beam. `ClinicTown` is 512 parts of 600 | T2 |
| `server/HospitalBuilder.luau` | The Building: `build(plotModel, level, grewFrom?, theme?)` (= `PlotBuilder.buildBuilding`) and `Pure`, its interior layout; it reads the plot's `Accent` attribute. The real building (§B6): the Lv 1 podium, then G+F1 (Lv 2), then the tower. Pieces: `Podium` (with the waiting `Bench`), `PodiumShell` (Lv 1), `Hall`, `Landing_0`, `Lift` (a **solid** glass `Shaft`, a soft studded `Car`), `Stairs` (`Flight_k` wedges), `Floor_<n>` (`Slab*`, `Landing`, `Wall*` with `Outer`, `GlassBand`, `Window*`, `Dado`, `Rail*`), `Wards` (`BedSpot_n`, `Dressing.DressBed_n` with a `Sleeper`, `Curtain`, `GlassPartition`), `Terrace`, `Hydro`, `Pharmacy`, `RoofTop`, `Roof` (`Helipad`, `HeliSpot`, `Planter`), `Tower`, `AmbulanceBay`, `ThemeProp`. Attributes `Since`, `Storey`, `Outer` and `Paint` (Trim / Band: all a theme recolours; walls stay the plot's Accent). Building attributes `Level`, `GrewFrom`, `GrewAt`, `Floors`, `Theme`, `Origin`. The paw-heart replaces every cross. Building parts 24 / 83 / 109 / 131 / 146 at Lv 1–5 (152 of 160 with the biggest theme prop); at most 11 SurfaceGuis and 6 see-through parts | T3 |
| `client/UI/Modal.luau` | The one modal template, moved out of Hud: `modal` (one navy header; `spec.HudMode`, `spec.Meta`), `isOpen`, `tabs`, `confirm`, `oddsPopup`, `fitTabs(column, tabs, gap, width?)`, `fitHeight`, `Pure` (`closable`, `TAB_WIDTH` 88). `modal.setTitle(text)`, the `Header`, `Title` and `Meta` fields. `tabs` returns `{ select, Column, Content, Buttons }`: a scrolling column of 88 px tabs named `Tab_<Id>` with a `Caption`. ButtonB never closes a modal with no X and no closing dim; `DimCloses = false` makes the dim a Frame that takes no input; a HudMode "Game" modal stays up when a Panel opens. A library; it never requires Hud | T6 |
| `client/UI/Wayfinder.luau` | The tutorial's world guide: `show(spec)`, `hide`, `attach(character)`, `destroy`, `Pure`. A library. The flat floor beam (`GuideStart` on your HumanoidRootPart at feet + BeamLift to `GuideEnd` on Terrain at the target's base; client PathfindingService knees, or round the Counter, at most 4 spans; span 1 re-aimed only while it shows and you moved; hidden within NearStuds), up to 6 still floor chevrons, ONE Highlight (re-pointed, deleted by `destroy`), the candy pin and the touch hand; `flash()` for the nudge; honours Reduce Motion live | T8 |
| `client/Feel/Cutaway.luau` | Hides the storeys above you inside your hospital: it checks once a second off a building and 4 times a second on one; on floor n it hides `Storey` > n (`LocalTransparencyModifier` 1, their Surface and BillboardGuis off) and fades floor n's `Outer` parts to 0.6; the ground floor hides nothing. `Pure.floorOf`, `Pure.hide` | T3 |

**The split.** `server/PlotBuilder.luau` (3,073 lines) became `TownBuilder`, `HospitalBuilder`, `World/Props`,
`World/NightLights` and `World/Parts` (the Foundation moved the code unchanged; the tasks then rebuilt each piece). PlotBuilder keeps the plots, the rooms, the queue lane and every public function;
`buildTown` and `buildBuilding` call the new modules; `Pure`, `NIGHT_LIGHT_TAG`, `STATION_TAG`, `LIFT_TAG` and
`PROMPT_TAGS` are re-exports, so no caller changed. Each plot Model now carries the attribute **`Accent`** (a
Color3: its `Palette.PlotColors` entry). Requires never loop: `PlotBuilder` → (`TownBuilder`, `HospitalBuilder`,
`World/*`); the two builders → `World/*` only (`tests/TownLayout.spec` checks it).
`client/UI/Hud.luau` lost its modal shell to `Modal`; `Hud.modal`, `Hud.isOpen`, `Hud.fitTabs`, `Hud.fitHeight`
and the new `Hud.confirm` and `Hud.oddsPopup` are re-exports.

**Client requires never loop** (plan §B10): `Modal` → (`Kit`, `Theme`); `Hud` → `Modal`; `Guide` → `Wayfinder`;
`Tutorial` → (`Hud`, `Kit`, `Wayfinder`, and lazily `Guide`, `Shop`, `MiniGames`). No UI module requires `Tutorial`.

**Where the look meets Progression v2** (plan §G): the v2 names, attributes and tags are kept, so `Lift`, `LiftPanel`,
`Patients`, `Levels`, `Stations`, `Rebirth` and `HospitalFX` are untouched. What changed for them: upper walls and
the shaft are solid (patients and porters move by `PivotTo`; the client cutaway lets the camera look in); the Lv 1
Building is the podium, not empty; themes recolour only the trim, the roof band and the prop; dressing beds
(`DressBed_n`) never match `^Bed_%d+$`; F1's underside is at 10.4 or higher; the belt is on the centre line; free
events may show minutes; the seven bottom tabs are the rails (same `Hud.target` names); the red dot pops once.

### Studs
`World/Studs` studs a part in one of two ways and picks by itself:
- **"Surface"** (the fallback, what runs today): `Material = Plastic` and `TopSurface = Studs`. Only the **top** face
  is studded (lawns, pads, prop tops); walls stay smooth. It needs no assets.
- **"Variant"**: as soon as `MaterialService` holds a `MaterialVariant` named `Config.Look.StudsVariant`
  (`CureStuds`), a studded part is `Plastic` with that variant, so **every** face is studded. Adding the variant
  while a server runs re-studs the world (`Studs.refresh(Workspace)`).

`Studs.apply` sets the attribute `Studded = true` (how the specs and `refresh` find studded parts); `Studs.smooth`
clears it. No `Texture`, `Decal` or extra part either way. **The alignment rule:** a studded part's X and Z sizes
are whole studs (`Studs.Pure.alignedSize`), odd widths preferred, on the plot's whole-stud grid. Never call the look
by the toy brand's name: it is "studs".

**The Studio step for the variant** (Joshua, once; the look build plan §D I-2): generate our own `CureStuds_color`
and `CureStuds_normal` maps (art-direction Appendix B), upload them (any Robux cost needs both brothers' yes), then
in Studio's MaterialService add a MaterialVariant `CureStuds`: BaseMaterial Plastic, `StudsPerTile 1`,
`MaterialPattern` Regular, the two maps. Save the place. Until then the game runs in Surface mode.

### Colours and tokens
- `shared/Palette.luau`: `World` (art-direction §4.1: mid-value surfaces, dark anchors `Road` / `Pad` / `Roof`, warm
  whites capped at 240), `Accent` (world accents), `PlotColors` (Plot 5 is **Yellow** now, not Lime), `Departments`
  (inside only), `Navy`, `Gold`. `Candy` is unchanged (the UI is unlit). Every old key is an alias of its new value.
- `client/UI/Theme.luau`: `Colors` (flat `Paper`, `Card`, `CardLine`, `Well`, `Header` = `NowPlate` = navy, the
  roles `Primary` / `Collect` / `Secondary` / `Destructive` / `Disabled`; `Good`, `Danger` and `Quiet` are aliases),
  `Radius` (8 / 14 / 22 / Round), `Stroke`, `TextSize` (**`Caption` 18 is the floor**), `Space`, `Shadow` (one),
  `Motion` (`Perpetual = 1`) and `Zone` (mirrors `Logic/HudZones`).
- `tests/Palette.spec` holds the rules: no bleached colour, dark anchors, the greens, plot colours that stand apart
  from the grass, from red and from each other, `Navy == Header == NowPlate`, every text size ≥ 18.

### The HUD zones
`Logic/HudZones` says where every HUD piece lives (T5 builds the screen from it):
- **System** ⚙️ in the Roblox top-bar row · **Wallet** 💰 ⭐ top-left · **Now** one card top-centre (`Hud.setNow`:
  30 warnings · 20 the tutorial · 10 the tracked goal) · **Status** top-right (day/night, one free-event chip,
  the visitor, boosts) · **Left rail** 🛒 👩‍⚕️ 📖 🏅 🏆 · **Right rail** 🎁 🎯 📬 · **Bottom centre** your hands.
- Slots are fixed: a piece that isn't revealed leaves its slot empty. Nothing is ever in the bottom corners
  (`CORNER_CLEAR` 110).
- **Phones** (safe height under 440): exactly 3 a side at 56 px, no captions; 🏅 and 🏆 go into ⚙️ More; the wallet
  moves into the top-bar row (ScreenGui `HudSystem`, TopbarSafeInsets) and Status into the strip between the Now
  card and the right rail. **Desktop and tablet:** as many of the left five as fit at 56-72 px (at least 3).
- `ModalOpened` / `ModalClosed` now carry a `HudMode`: "Panel" hides the rails, Now and Status (the wallet stays);
  "Game" (the mini-game) keeps the wallet and the Now card; "None" (a popup) changes nothing.
- Countdowns are only for **free** events, in minutes (`Logic/NextEvent`; `memory-20261116-022`). Nothing paid ever
  gets a timer.

### Skip and Replay
- `Logic/Tutorial` gained the events **"Skip"** (any active step → done) and **"Replay"** (done → the first patient:
  the one deliberate step back, `memory-20261117-002`), the 7 cards (`card(step, treating?)`, `CARD_NAMES`), `nudge`,
  `canSkip`, `canReplay(step, hasPlot)` and `giftDue(step, gifted)`. The first patient now hops in during the welcome
  sweep (`spawnPlan(WELCOME)` is "First"), and stands 1 s (not 2) before the Make card.
- Two player-safe remotes, `TutorialSkip()` and `TutorialReplay()` (`Remotes.serve`: rate-limited and pcalled;
  arguments ignored; only the caller's own save and plot), served by `server/Tutorial.luau` (T8). Each answers
  `(ok, message)`; a failure is `false` plus at most 6 words and changes nothing.
  The admin `RestartTutorial` is unchanged.
- The save field **`TutorialGift`** (still schema v4): the step-7 top-up has run or was never needed. Missing or junk
  is derived (`Tutorial >= 7`), so a Replay never gives a second gift and an older server dropping the field loses
  nothing.
- The Snapshot's `TutorialReplay` (the player attribute of the same name, not saved) is true while a session replays.
- `Main.server` hands `Patients.reopen` to `Tutorial.setReopen` after every system has started (Patients requires
  Tutorial, so Tutorial can't require Patients).

### Town layout
`Config.Belt.Offset` is now `(120, 0, 0)`: the belt runs down the road's **centre line**. The spawn plaza moved to
the street's row-2 half: `Config.Town.SpawnOffset` (0, 0, 11), `SpawnSize` 8, `Plaza`, `BeltClear` 4.4, with the
Agency at (13, 12), the Market at (−13, 12) and the odds sign at (−24, 11). `tests/TownLayout.spec` checks the
clearances on Config.

## Boot order
**Server (`Main.server.luau`):**
1. `Remotes` is required first, so every remote exists before anything else runs.
2. The collision groups `Patients` and `Players` are set up. Patients walk through players and each other.
3. Then `start()`, in this order: `PlayerData` → `State` → `Events` → `Plots` → `Carry` → `Economy` → `Levels` →
   `Lift` → `Progress` → `Book` → `Story` → `Daily` → `DayReport` → `Tutorial` → `Boosts` → `Badges` → `Playtime` →
   `Stations` → `Nurses` → `Abilities` → `Treatment` → `Patients` → `NurseBelt` → `Agency` → `Market` → `Rebirth` →
   `Visits` → `Leaderboards` → `DayNight` → `Admin`. Requires never loop: Patients → Treatment → Abilities → Nurses →
   (Lift, Levels); Stations and Cure → Abilities, Nurses; NurseBelt, Agency, Market → Nurses; Rebirth → Patients,
   Treatment, Nurses, Plots; Admin → everything. No module requires Rebirth, Agency, Market or Admin (but Admin).
   `NurseBuilder` is a library.
   - `Playtime` starts after `Plots` and `Daily` (it needs a clinic and the UTC day) and hooks itself into `Boosts`
     (`Boosts.hook`) and `Remotes` (`setActivity`).
   - `Tutorial` starts before `Stations` and `Patients`, so its quiet toasts and listeners are set before any
     patient comes. `Stations`, `Patients` and `Cure` call its hooks; it requires none of them.
   - `Plots.start()` builds the whole town (`PlotBuilder.buildTown`), with a `Room_Stand` on every plot, before
     `Stations` and `Patients` start.
   - `CreatureBuilder`, `DecorBuilder`, `BoardBuilder` and `Cure` are libraries that other systems require, so
     they're not in the list.
   - `Leaderboards` starts after `Plots` (it reads the built town to place its boards).
   - `Admin` starts last: its remote calls into the systems above.
   - *(look)* After every `start()`, `Main.server` calls `Tutorial.setReopen(Patients.reopen)` (the Replay's hook).
   - Each `start()` runs in `xpcall`. One that errors prints `[Main] <Name>.start() failed` and the rest still start.
4. It prints `[Main] Clinic is open.`

**Client (`Main.client.luau`):** waits for `game.Loaded` and builds `ctx`. Then it loads `UI.Toasts`, `Hud`, `Shop`,
`BookPanel`, `DayReportPanel`, `Mailbox`, `PlayGifts`, `BadgeBook`, `Guide`, `PromptFilter`, `AdminPanel`, `Boards`,
`Celebrate`, `MiniGames`, `NursePanel`, `BeltView`, *(v2)* `AgencyPanel`, `MarketPanel`, `BranchPanel`, `LiftPanel` and
`Tutorial`, then `Feel.Sounds`, `CureFX`, `Atmosphere`, `CreatureMotion`, `CreatureActing` (`Feel.CreatureProps` is its
library), *(v2)* `HospitalFX` and *(look)* `Cutaway`. `UI.Theme`, `Kit`, `Modal` and `Wayfinder` are libraries (no `init`). Each one is loaded in its own pcall, and
its `init(ctx)` runs. A missing or broken module warns `[Client] ...` and is skipped. The server events `TreatStart`,
`NurseNews`, `Shout`, `Celebrate` and *(v2)* `AgencyNews`, `MarketNews`, `BeltScout` are forwarded to the client bus under
the same names (every bus event is listed
in `Main.client.luau`'s header; the play-gift and badge cheers arrive on the bus event `Cheer`, and BadgeBook sends them on as a `Banner`; *(look)*
`CelebrateClosed`, `SkipTutorial`, `ReplayTutorial` and `ModalOpened` / `ModalClosed` with a HudMode). `Music.client` is a
separate LocalScript. Until the server's first snapshot arrives, `ctx.State.Tutorial` is 0 ("not known yet"), so the
HUD starts calm (only 💰).

## The loop
A patient walks in and queues at `QueueStart` on the queue lane (3 at most), with its ailment icon, its recipe (1 item
at Lv 1, up to 3 from Lv 3) and a patience ring. While it waits it acts out what's wrong with props
(`Data/AilmentActing`) and waves for you as its patience runs low → you **hold at the matching `Station_*`** to make an
item (🧪 Potion, 🩹 Plaster, 🧼 Bubbles, ☕ Cocoa) → you carry it → you **Treat at the Counter** → a short
**mini-game** per item given (Pour, Patch, Scrub, Cool; OK still cures, a Perfect pays a small capped tip and builds the
🔥 combo; Simple mode is one tap) → the badge ticks the items off, and once the recipe is complete the patient goes to
a free `Bed_*` (or recovers in place) → `Cure.resolve`: cash, ⭐, a Book stamp, goal progress, a story beat → a happy
hop, and it leaves. A wrong item gets a head-shake and a hint. Running out of patience is a sad puff, with no penalty.
Nurses hired from the belt in town help: Makers fill the nurse tray (Treat uses it too), Healers give the front
patient what the tray holds, Cheerers make patience last. *(v2)* Every nurse you own works (3, +1 a rebirth), learns
from cures and fires its ability by itself; Receptionists, Porters and Medics join from Lv 2. From Lv 2 ambulances
bring urgent patients, from Lv 3 you pick the floor, patients ride the lift to the wards or soak in the hot tub, and
from Lv 5 a branch can open: a fresh start that keeps your nurses, Book and badges and adds a perk card, tree points
and +25% 💰⭐ (all optional, never pushed).

## The first-session tutorial
Design: `docs/plan/2026-11-16-first-session-design.md`. The step is the save field `Data.Tutorial` (1 to 8, 9 =
done), owned by `server/Tutorial.luau` and sent in the Snapshot (`Tutorial`, plus `TutorialCures` for step 6). A
fresh save starts at 1. A save from before the tutorial (no `Tutorial` field) with any cure (`Cured > 0`, or a v1
`Served > 0`) is done, so existing players never see it. Every step moves on only on a real server event:

| # | Card (icon first, ≤ 8 words) | Moves on when (server) |
|---|---|---|
| 1 | 👋 Welcome to your clinic, Doctor! | `TutorialAck` (the client sends it as the welcome sweep ends; only ever moves 1 → 2, only with a clinic). No ack: by itself 30 s after the clinic is assigned |
| 2 | 🤧 A patient! The bubble shows what's wrong. | 2 s after the first patient reaches the Counter (`Patients` → `Tutorial.onFrontArrived`) |
| 3 | 🧪 Hold at the potion table! (+ device hint) | the owner makes, at their own clinic, what that patient needs (`Stations` → `onMade`); already carrying it counts |
| 4 | 🏥 Take it to the Counter. Treat! | the patient is treated (`Patients` → `onTreated`); a treat skips 2-3 too |
| 5 | 🛏️ Resting… Cured! 🎉 | the cure lands at their clinic (`Cure` → `onCured`) |
| 6 | 💪 Cure 2 more! (n/2) | 2 more cures at their clinic (count in the player attribute `TutorialCures`, not saved) |
| 7 | 🛒 Spend 💰 in the Shop! | any purchase (`Economy.Purchased`). Entering 7: a one-time cash top-up to the cheapest upgrade's price if short ("🎁 A gift to get you started!"). In-game cash only |
| 8 | 📖 Collect every creature in your Book! | 5 s later: done. Then the Mailbox letter pops |

- **Patients during it** (by the owner's step): one easy Starter patient needing 🧪, from step 1 on; then one
  Starter patient needing 🩹; then the usual pool. One at a time in line through step 6, patience never runs out in
  steps 1-6, and no regulars or Today's Visitor until it's done.
- **Quiet:** while it runs, ambient toasts wait (`Remotes.news`, `Remotes.toastAll`), and there's no Day Report and
  no Mailbox pop-up. Replies and warnings still show.
- **Rejoining:** steps 3-5 go back to 2 (the patient left with you); step 6 counts its 2 cures from 0 again.
- **Skip and Replay** (`memory-20261117-002`): Skip is the card's ⏭️ chip or the ⚙️ row, Replay the ⚙️ row, each
  behind a confirm ("Not now" is the default). After a Skip the arrows stay until 3 cures. A Replay has no sweep, no
  gift and the full HUD, and can be skipped again. Admins can also jump or restart it from the
  [Admin panel](#admin-panel).
- **What the player sees (look overhaul, T8):** the table above is the server's 8 steps; on screen they are 7 cards
  in the top-centre Now card (`Logic/Tutorial.card`; the words per device are in `client/UI/Tutorial.luau`'s header),
  with a flat floor beam, still chevrons and one glow from `UI/Wayfinder`, a guide nurse (`Data/Guide`, no name
  shown), a ✓ beat per card and a finale with one free COMING UP chip. The HUD reveals itself with the step
  (`Hud.Pure.reveal`). The first patient comes during the welcome sweep, and step 2 waits 1 s, not 2. Card 7 says
  "Buy this! ⚡", never "Spend".

## Play gifts, Doctor ranks, boosts and badges
Rewards for playing, all earned in play: **no Robux, nothing random, no streaks, nothing to miss**
(`docs/research/2026-11-16-kids-audience-and-rules.md`). Server: `server/Playtime.luau`, `Boosts.luau`, `Badges.luau`;
rules: `shared/Logic/Playtime.luau`, `Boosts.luau`, `Badges.luau` (Lune specs of the same names); content:
`shared/Data/Playtime.luau`, `Boosts.luau`, `Badges.luau`; UI: `client/UI/PlayGifts.luau`, `BadgeBook.luau`, the HUD.

**Active play only.** Once a second the server counts a player's time while they're at their own clinic (a plot) and
have moved (1 stud) or acted (any remote, any ProximityPrompt) in the last `Config.PlaytimeIdleSeconds` (300). Standing
still pauses it, so it can't be farmed beyond normal play. The counted seconds are saved at most a minute apart (sooner
when a gift unlocks, a rank is reached or a boost ends) and on leave; the HUD reads the live player attributes
`PlayToday`, `PlayTotal` and `PlayCounting`.

**Save fields** (`Logic/Schema`, inside v2; an older save starts at 0 on today):
`Playtime = { Day, TodaySeconds, TotalSeconds, Claimed, Rank }` (today's and all-time active seconds, the gifts opened
on `Day`, the rank rewarded), `Boosts = { [BoostId]: secondsLeft }`, `Stats = { [counter]: n }` (badge counters;
`Seeded = 1` once worked out from an older save), `Badges = { [BadgeId]: tier }`.

### Daily play gifts (`Data/Playtime.Gifts`)
Six gifts unlock with active play on the current **UTC day**; tap 🎁 (under the wallet, after the tutorial), then
**Open!** (`ClaimPlayGift(index)`, validated and rate-limited on the server). Leaving and rejoining keeps today's
progress and opened gifts; a new UTC day refills them (mid-session too). After the sixth there's nothing more today.

| # | After (play today) | Gift |
|---|---|---|
| 1 | 2 min | 💰20 |
| 2 | 5 min | 💰30 ⭐1 + ⚡ Quick Hands |
| 3 | 10 min | 💰50 ⭐1 |
| 4 | 15 min | 💰60 ⭐2 + 🍀 Lucky Tips |
| 5 | 25 min | 💰100 ⭐2 |
| 6 | 40 min | 💝 💰150 ⭐3 + 🌠 Star Rush |

### Doctor ranks (`Data/Playtime.Ranks`)
All-time active play. Each rank gives, once: an exclusive decor (`EarnedBy = "Playtime"`, place it from 🛒 Decor), a
toast and banner, its Roblox badge, and a permanent Cash boost (your current rank's, not added up). The rank shows on
your clinic sign (`SignGui.RankBadge`; 🌱 Trainee before the first) and in the 🎁 panel ("Doctor rank: Resident ·
4h 12m played · next: 🥼 Doctor at 10h").

| Rank | Played | Decor | Cash boost | `Config.Badges` key |
|---|---|---|---|---|
| 🩹 Intern | 1 h | 🩹 Intern Rug | +2% | `Intern` |
| 🩺 Resident | 3 h | 🪴 Resident Fern | +4% | `Resident` |
| 🥼 Doctor | 10 h | 🏮 Doctor Lantern | +6% | `Doctor` |
| 🎖️ Senior Doctor | 25 h | 🪑 Senior Bench | +8% | `SeniorDoctor` |
| 🌟 Chief | 50 h | 🌟 Chief's Arch | +10% | `Chief` |
| 🏆 Legend | 100 h | 🏆 Legend Statue | +15% | `Legend` |

### Boosts (`Server/Boosts`, `Logic/Boosts`)
Kinds: **Cash** (x the whole cure pay), **Tips** (added to the Tip Jar factor, so it works without a Tip Jar),
**Stars** (x a cure's stars, rounded), **MakeSpeed** (hold time / (1 + p), never below `BoostMinMakeSeconds` 0.3 s),
**Patience** (x how long patients wait). Applied on the server where rewards happen: `Cure` (the helper's Cash and Tips,
the owner's Stars, scoped to night and the patient's wing), `Stations` (the maker's MakeSpeed for that station; the
Snapshot's `MakeSeconds` makes the client ring match), `Patients` (the owner's Patience).
- **Permanent:** the Doctor rank and every badge's tier. Capped per kind (`Config.BoostCaps`): **Cash ≤ +50%,
  MakeSpeed ≤ +40%, Patience ≤ +50%, Tips ≤ +50%** (Stars ≤ +50%, though nothing permanent gives Stars yet).
- **Timed** (`Data/Boosts`, from the gifts): ⚡ **Quick Hands** MakeSpeed +25% for 10 min · 🍀 **Lucky Tips** Tips
  +50% for 15 min · 🌠 **Star Rush** Stars ×2 for 10 min. Saved, and they tick **only during active play** (never while
  away). Getting one again extends it (to `BoostMaxMinutes` 60), never stacks it. They add on top of the capped part.
- On screen: a chip per timed boost beside the clock (icon + play time left), and a "Your boosts" line in the 🎁 panel
  and the 🏅 Book.

### Badges (`Data/Badges`), Bronze → Silver → Gold → Diamond → Ruby → Mythic
Each tier reached pays once (🥉 💰50 ⭐2 · 🥈 💰150 ⭐4 · 🥇 💰400 ⭐8 · 💎 💰1,000 ⭐15 · ♦️ 💰2,500 ⭐25 · 🔮 💰6,000
⭐40) and grows the badge's permanent boost (per tier, so Gold = 3x). Checked after every save change; tiers never go
down. An older save's counters are seeded once from `Cured`, the Patient Book (per wing, night, and one treatment made
per cure) and Today's Visitor.

| Badge | Counts | Tiers | Boost per tier |
|---|---|---|---|
| 🏥 Healer | cures (`Cures`) | 25 · 100 · 500 · 2,000 · 10,000 · 50,000 | +1% Cash |
| 🔦 Night Shift | night cures | 5 · 25 · 100 · 400 · 1,500 · 6,000 | +5% Cash at night |
| ⭐ Visitor | Today's Visitors cured (the owner) | 1 · 5 · 15 · 40 · 100 · 250 | +4% Patience |
| 🏠 Builder | rooms bought + decor owned | 1 · 3 · 6 · 10 · 16 · 22 | +4% Tips |
| ⏱️ Dedication | hours of active play | 1 · 5 · 15 · 40 · 100 · 250 | +2% MakeSpeed |
| 🌳 Meadow | Meadow cures | 10 · 50 · 200 · 750 · 3,000 · 12,000 | +2% Cash for Meadow |
| 🛁 Bubble Pond | Bubble Pond cures | 10 · 40 · 150 · 600 · 2,500 · 10,000 | +2% Cash for Bubble Pond |
| ❄️ Snowy Hills | Snowy Hills cures | 5 · 25 · 100 · 400 · 1,500 · 6,000 | +2% Cash for Snowy Hills |
| 🌙 Moonlit Woods | Moonlit Woods cures | 5 · 25 · 100 · 400 · 1,500 · 6,000 | +2% Cash for Moonlit Woods |
| 🧪 Potions | potions made | 25 · 100 · 400 · 1,500 · 6,000 · 25,000 | +3% MakeSpeed 🧪 |
| 🩹 Plasters | plasters made | 25 · 100 · 400 · 1,500 · 6,000 · 25,000 | +3% MakeSpeed 🩹 |
| 🧼 Bubbles | warm baths run | 10 · 50 · 200 · 800 · 3,000 · 12,000 | +3% MakeSpeed 🛁 |
| ☕ Cocoa | cocoa made | 10 · 40 · 150 · 600 · 2,500 · 10,000 | +3% MakeSpeed ☕ |
| 💬 Storyteller | story beats heard | 1 · 3 · 6 · 9 · 12 · 15 | +3% Tips |
| ❤️ Friendly | hearts sent + cures at a friend's clinic | 1 · 5 · 20 · 60 · 150 · 400 | +3% Patience |

**A new badge** (perfect mini-games, nurses hired, hospital level...) is a row in `Data/Badges.List` plus, for a new
counter, one `Badges.add(player, { Counter = 1 })` where it happens. The 🏅 Book draws it on its own.

### Roblox badges (only the 6 Doctor ranks and Gold 🏥 Healer)
The ids live in `Config.Badges`; **0 = not created yet, skipped**. Awarding is a pcall'd `BadgeService:AwardBadge`
(after `UserHasBadgeAsync`), once per session, and every join re-checks the ranks and Gold Healer already reached, so a
badge made later still reaches players who got there first. To make them (Joshua, both brothers agree on the art):
1. [Creator Hub](https://create.roblox.com/dashboard/creations) → the experience → **Associated Items** → **Badges** →
   **Create a Badge**.
2. Upload a square image (original art, the size Creator Hub asks for), name it (e.g. "Intern"), a one-line
   description (e.g. "Played 1 hour at your clinic"), and create it. Creator Hub shows whether a badge is free or costs
   Robux before you confirm (check it there, it can change): spending any Robux needs both brothers' yes (CLAUDE.md
   red line 4).
3. Copy the badge's id (the number in its URL) into `Config.Badges` (`Intern = 123456789`, ...) and commit. Repeat for
   `Resident`, `Doctor`, `SeniorDoctor`, `Chief`, `Legend` and `HealerGold`.
4. Test in a live server: reach the rank with the 🛠️ "+5 h total" button and check the badge on your profile. Output
   warns `[Badges] Could not award Roblox badge ...` on a wrong id (or where awarding isn't possible, such as Studio).

## Admin panel
For the two developer accounts, to test progression quickly in the **live game** and in Studio:
`server/Admin.luau` (rules in `shared/Logic/Admin.luau`, spec `tests/Admin.spec.luau`) and `client/UI/AdminPanel.luau`.

**Who is an admin** is decided on the server only, never by the client:
1. a UserId in `Config.AdminUserIds` (checked first; empty for now);
2. the game's owner: `game.CreatorType == Enum.CreatorType.User` and `player.UserId == game.CreatorId` (JokingPuzzle);
3. a username in `Config.AdminNames` (`Dandlepeeps`). At startup the server looks each one up with
   `Players:GetUserIdFromNameAsync` (in a pcall, retried) and prints `[Admin] Dandlepeeps = <id>` in Output. **Copy
   that id into `Config.AdminUserIds`**: a username can change hands, an id can't;
4. in Studio (`RunService:IsStudio()`), anyone playing.

An admin gets the player attribute `IsAdmin = true`, and the ⚙️ Settings panel then shows a **🛠️ Admin** button.
*(look, T6)* The panel has four tabs (🛠️ Tools, 🏢 Branch, 🤧 Patients, 🎁 Nurses); the old "Spawn patient…",
"Branch tools…" and "Give nurse…" buttons and the Back buttons are gone; Restart tutorial, Rebirth now and Reset goals
are Destructive and ask `Hud.confirm` first. The
attribute only steers the UI: every button calls one RemoteFunction, `Admin(action, arg)`, served with
`Remotes.serve`, and on **every** call the server checks admin again, checks `action` against a fixed list and `arg`
strictly, and prints `[Admin] <name> <action> [arg]`. A non-admin gets `false` and nothing happens (Output warns
once per player). Replies come back as toasts.

| Button | Action (`arg`) | Does |
|---|---|---|
| +1,000 💰 · +10,000 💰 | `AddCash` (1000 or 10000) | `Economy.addCash` on your save |
| +10 ⭐ · +100 ⭐ | `AddStars` (10 or 100) | `Progress.addStars` (room and regular unlock toasts as usual) |
| 🏠 All rooms | `UnlockRooms` | every room, free, via `Plots.unlockRoom` (no purchase, so the tutorial doesn't move) |
| 🌸 All decor | `AllDecor` | owns every decor item (place it from 🛒 Decor) |
| 📖 Full Book | `CompleteBook` | stamps every patient page not yet cured, and grants each completed wing set's reward |
| 💌 Stories today | `StoriesDue` | every regular who told a beat today may tell the next one today; the gap between regulars ends |
| 🎯 Reset goals + 📬 | `ResetDaily` | today starts over: goals handed out today go, today's goal comes again, the mailbox opens |
| 🤧 Spawn patient… | `SpawnPatient` (a `Data/Patients` id) | a page of every patient: tap one and it's next in your own line, once there's room (up to 3 wait; it needs its station, and at Lv 2+ its whole recipe's, on your plot) |
| 🎁 +10 min today | `AddPlayToday` | +600 s of play today: the next gifts unlock |
| ⏱️ +5 h total | `AddPlayTotal` | +5 h of play all time: Doctor ranks (decor, badge, sign) and ⏱️ Dedication |
| 🏥 +100 cures | `AddCureStat` | +100 to the 🏥 Healer counter (tiers and rewards as in play) |
| 🏅 Max badges | `MaxBadges` | every badge to Mythic, with all its tier rewards (a lot of 💰 and ⭐) |
| 🌠 Star Rush · ⚡ Quick Hands · 🍀 Lucky Tips | `AddBoost` (a `Data/Boosts` id) | that timed boost, as its gift gives it (extends, up to 60 min) |
| ✅ Finish | `FinishTutorial` | the tutorial is done (step 9) |
| 🔄 Restart | `RestartTutorial` | empties your line, back to the welcome card, and respawns you so the title card and sweep play |
| 🌙 Night · ☀️ Day | `SkipToNight` · `SkipToDay` | the whole server: ends the current phase now (`SkipPhase`); day after night sends the Day Report |
| ❄️ Winter on/off | `ToggleWinter` | the whole server: toggles `ForceWinter` (off still leaves winter inside `Config.Winter`'s dates) |
| *(v2, the 🏢 page)* 🏢 Rebirth now | `Rebirth` | `Rebirth.adminRebirth`: a free rebirth (no Lv 5, no cost) |
| 🌳 +3 points | `AddTreePoints` | `Rebirth.adminPoints` |
| ⬆️ Nurse levels | `NurseLevels` | `Nurses.adminLevels`: +1 level for each of your nurses, to the cap |
| ✨ Charge abilities | `ChargeAbilities` | `Abilities.adminCharge`: every ability at your plot ready now |
| 🚑 Ambulance · 🚁 Helicopter | `SpawnAmbulance` · `SpawnHelicopter` | `Patients.adminAmbulance` (Lv 2+) · `Patients.adminHelicopter` (Lv 5; no R2 needed) |
| 🏢 Restock Agency | `RefillAgency` | the whole server (alone only): `Agency.restockNow`, a new restock index |
| 🎁 Give nurse… | `GiveNurse` (a `Data/Nurses` id) | a page of every nurse: tap one and it's yours, free, through `Nurses.adminGive` (the roster rules apply) |
Every v2 hook is live (integration, 2026-11-17).

- **The alone-in-server rule.** Night, day, winter and *(v2)* the Agency's restock change everyone's game, so they work only when the admin is
  the **only player in the server**, or in Studio. Otherwise the reply toast says "👥 Only when you're alone!".
- **Everything else touches only your own save**, through the same server APIs play uses, so saving, snapshots and
  toasts behave as in play. In the live game it's your real save: there's no undo.
- **Testing it.** Studio: Play, ⚙️ → 🛠️ Admin; Output shows `[Admin] Studio: everyone playing is an admin` and
  `[Admin] Dandlepeeps = <id>`. Live: join alone as JokingPuzzle or Dandlepeeps, and a non-admin account sees no 🛠️.
  From a non-admin client's command bar each of these must print `false` and change nothing:
  ```lua
  local R = game.ReplicatedStorage.Remotes
  print(R.Admin:InvokeServer("AddCash", 10000))
  print(R.Admin:InvokeServer("SkipToNight"))
  ```
  As an admin, junk must also return `false` and change nothing: `R.Admin:InvokeServer("AddCash", 1e9)`,
  `("SpawnPatient", "Order")`, `("GiveRobux")`. In a 2-player Studio test both players are admins (Studio).

## Leaderboards
Global boards for every server: `server/Leaderboards.luau` (rules in `shared/Logic/Leaderboard.luau`, spec
`tests/Leaderboard.spec.luau`), the Hall of Fame boards in `server/BoardBuilder.luau`, and the 🏆 panel in
`client/UI/Boards.luau`. Tuning in `Config.Leaderboards`.

| Board | Value (from the server's save) | OrderedDataStore (key = `tostring(UserId)`) |
|---|---|---|
| 🏥 Most Cured | `Data.Cured`, all time | `Board_Cured_v1` |
| ⭐ Most Stars | `Data.Stars`, all time | `Board_Stars_v1` |
| ❤️ Most Hearts | `Data.HeartsReceived`, all time | `Board_Hearts_v1` |
| 🏆 Cures This Week | `Data.WeekCures.Count` for this UTC week | `Board_Week_v1_w<week>`: a new store every Monday 00:00 UTC, so it starts empty |
| 🏢 Most Rebirths *(v2)* | `Data.Rebirth.Count` (tab caption "Branches"; only in the 🏆 panel, not on the Hall of Fame) | `Board_Rebirths_v1` |

- **The week** is `Leaderboard.week(os.time())`: `(unixDay + 3) // 7`, Monday to Sunday UTC (2026-11-16 starts week
  2968). It uses the real clock, never `Workspace.UtcDay`, so a Studio day test can't write to a future week.
  `Cure` counts each cure into the save's `WeekCures` ({ Week, Count }; a cure in a new week starts it from 0). The
  last count of a week is still written to that week's board just after Monday 00:00.
- **Later boards:** Hospital Level (`Data.Level`) and Nurse Journal % (`Data.NurseIndex` "Hired" entries over the
  number of nurses in `Data/Nurses`) are defined already and read those fields only if the save has them. Add
  `"Level"`/`"Journal"` to `Config.Leaderboards.Boards` (and `WorldBoards`, at most 4) once the depth update lands.
- **`Version`** (1) is in every store name: bump it to start every board fresh.
- **Trust:** values come only from the server's save, and only from a save that loaded and is being saved
  (`PlayerData.canSave`): defaults after a failed load, a lost lock or `FreshSave` never reach a board. The client
  only calls `GetBoards()` (rate-limited; answered from the server's cache, never a DataStore call).
- **Admins are never on a board** (Joshua, 2026-11-16: the 🛠️ Admin panel adds cash and stars, so their numbers are
  fake): the game's owner (`game.CreatorId` when a user owns the game) and every UserId in `Config.AdminUserIds`
  (`311718381`, Dandlepeeps). Their values are never written, and they're filtered out of every list read back, in
  case an old value is stored. Their 🏆 bar says "🛠️ Admins aren't ranked". **In Studio nobody is excluded**, so the
  boards can be tested; with API access on, a Studio session writes the admin's real values to the live stores, and
  live servers filter them out again. (`Config.AdminNames` isn't used here: put the id in `AdminUserIds`.)
- **Budgets** (Roblox's limits, 2026-11): each player's *changed* values are written at most every 150 s (the first
  one 75-150 s after joining, jittered), once when they leave, and in `BindToClose`: at most 4 `SetAsync` per player
  per 150 s, about 1.6 a minute, against 60 + 10 per player per minute per server. Zeros are never written. Each
  board is read with one `GetSortedAsync` (the top 100) every 120 s, shared by the whole server: 4 reads per 2
  minutes, against 5 + 2 per player per minute. Names of top-10 players who aren't in the server come from one
  batched `UserService:GetUserInfosByUserIdsAsync` per read pass, cached for an hour. Every request checks its budget
  first (`GetRequestBudgetForRequestType`), runs in a pcall, and a failure backs off (30 s, doubling to 10 min).
- **Live merge:** what the boards and the panel show is the stored top 100 with this server's players' current saved
  values laid over it, so a cure moves you up within ~5 s without waiting for a write and a read. "You: #n" is exact
  within the top 100, then "You: #100+".
- **Names:** the DisplayName and, small, the @username, as Roblox already shows them. Nothing else about anyone.
- **Studio without API access** (or an unpublished place): the first request fails with a permanent error, Output
  prints one `[Leaderboards] DataStores aren't available here...` line (no errors), nothing is retried, and the boards
  and the panel say "Leaderboards open when the game is live" (the panel still shows your own value).

**Where the boards stand: the 🏆 Hall of Fame garden, off the main road.** Joshua, 2026-11-16: "leaderboards shouldnt
be on the main road... conveyor belt should be on the main road". So nothing of the boards sits on the street, its
curbs, a plot, a welcome arch or the plaza: **the whole street is free for the Nurse Belt.** `Workspace.TownBoards`,
rebuilt at every server start, is a small garden past the street's **west** end, beyond its welcome arch: its own
grass slab 38 deep and 80 wide against the town lawn's west edge (world x = -137 to -175, z = 260 to 340, with
`Config.Town.Origin` at (0, 0, 300)). A cream path runs on from the street's end to a "🏆 Hall of Fame" sign with a
gold trophy on top, at (-161, 300). The four boards (🏥 ⭐ ❤️ 🏆, left to right as seen from the plaza, 10 wide and
12 tall) stand on low white plinths in a shallow arc through the sign, two each side (centres at x ≈ -157, z ≈ 326
and 274, and x ≈ -160, z ≈ 313 and 287), each turned to a point on the street's centre line 80 studs in front (x =
-81), so they face back down the street to the plaza and the `TownSpawn`, ~160 studs away. Their backs show the same
boards. Benches face the boards, low flower planters flank the path, lamps stand at the arc's ends, trees behind it.
From the spawn the welcome arch frames the sign and the inner boards (its beam hides their top strip from there) and
the outer boards stand just outside the arch's posts. The street's end and the lawn's edge are read from the built
`ClinicTown`, so the garden follows PlotBuilder's layout; `GARDEN_END` in `BoardBuilder` moves it past the east end.

**Testing it.**
- Studio, API access **off**: Play. No red errors; looking west down the street from the spawn, the Hall of Fame's
  boards stand past the welcome arch saying "Leaderboards open when the game is live"; 🏆 Top (after the tutorial)
  shows the same with your values.
- Studio, API access **on** (it writes the live boards from your real save): Play, cure a few. Within ~5 s your row is
  on the Hall of Fame boards and in 🏆 ("You: #n"). After 75-150 s, or on Stop, Output shows no
  `[Leaderboards] Couldn't write`. The next Play reads the boards back.
- Live: an admin account (JokingPuzzle, Dandlepeeps) never appears, and its bar says "🛠️ Admins aren't ranked"; a
  second, non-admin account appears after its first cure.
- Junk: `game.ReplicatedStorage.Remotes.GetBoards:InvokeServer()` spammed from the command bar returns `nil` past 10
  calls a second and never costs a DataStore request.

## The Nurse Belt on the main road
Joshua, 2026-11-16: "conveyor belt should be on the main road"; his brother: nurses should come less often than in the
belt games, so rarity feels earned (`memory-20261116-017`). `Config.Belt` holds every number; `server/NurseBelt.luau`
builds and runs it; `client/UI/BeltView.luau` draws it for each player.
- **Where (look overhaul, `memory-20261117-001` #3):** one straight belt down the road's **centre line** (z = 300
  with `Config.Town.Origin` at (0, 0, 300); `Config.Belt.Offset` (120, 0, 0)), from the studded purple nurse house
  just inside the east welcome arch (x = +120) to the cloud just inside the west one (x = -120); riders move west.
  It passes all six gates within `HireDistance` (40). Nothing else stands in its lane: the spawn plaza is on the
  street's row-2 half ([Town layout](#town-layout)), and `tests/TownWorld.spec` checks nothing taller than 0.3 sits
  in the lane. It stays clear of both arches and the Hall of Fame garden (x < -137).
- **Crossing:** the conveyor's top is 0.9 studs above the street and its rails and rollers don't collide: step over
  it anywhere.
- **The odds sign** is a navy plate at `Config.Belt.SignOffset` (-24, 11), at the plaza's west end, facing TownSpawn,
  9 studs wide, with "🎲 NURSE ODDS" floating above it. Every odd is on it (☀️ day, 🌙 Night Rush, 👑 Golden Hour),
  plus the gate rows "🏥 Epic+ from Lv 3" and *(v2)* "🏢 Mythic/Secret from R1", and the pity count. Its "🎲 See odds"
  prompt (`OddsPrompt`), the hire card's "🎲 Odds" button and the 👩‍⚕️ Journal's 🎲 all open the same `Hud.oddsPopup`
  (each row the word and the number, exactly `Logic/Belt.odds`). There is no floating 🎲 chip. Riders face the plaza
  (+z, toward TownSpawn).
- **How often:** a nurse steps on about every 40 s and rides ~100 s (2.4 studs/s), so two or three are usually on.
  Base odds Common 75 · Rare 20 · Epic 4.5 · Legendary 0.5; Night Rush doubles Rare+ and adds Mythic 0.5%; Golden
  Hour adds Secret 1%. A Rare+ is guaranteed after 15 arrivals in a row without one. A Common or Rare hire that leaves
  no other nurse on the belt brings the next within 8 s; otherwise hiring never speeds the belt up. At most 5 ride.
- **Who can hire what:** Epic and up ride for everyone (one shared belt, and the sign's odds are the belt's), but only
  a hospital at Lv 3+ may hire them (`Config.Belt.MinLevel`); below it the rider's card says "🏥 Lv 3" instead of a
  price, the server refuses the hire with "🏥 Lv 3 hospital first!", and its arrival banner isn't shown to that
  player. No lock icon, no "hurry". *(v2)* Mythic and Secret also need the first rebirth (`Config.Belt.MinRebirths`,
  `Logic/Belt.gate`: "🏢 R1 first!"), a new nurse needs roster room ("Roster full: sell or list one": the card's
  button then opens the 👩‍⚕️ Team page), and the rebirth-only FounderFennec never rides.
- *(v2)* **🔭 Belt Scout** (a perk card): while an owner is in the server, the next arrival's rarity is rolled one
  arrival early and shown to owners only, as a chip over the nurse house. **The nurse-house lamp** brightens as the
  next nurse nears, with no numbers (§E9).
- **Prices** are unchanged (💰100 / 400 / 1,500 / 6,000 / 20,000 / 50,000, ×1.0 to ×1.4 by your hospital level);
  *(v2)* 🏷️ Bargain takes 5% a rank off.

## Rules the code keeps
- **The server owns all data and money.** Every RemoteFunction is wired with `Remotes.serve` (10 calls/s per player
  per remote, plus pcall) and checks types, ids, ownership and permission. The client only asks.
- **Change the save only through `PlayerData.update(p, fn)`.** `get()` is read-only.
- **Contracts are law.** Instance names, attributes and APIs are in the build plan §B. The brother's kit follows the
  same names (`docs/guides/build-the-clinic.md`).
- **Rated Minimal, no reading needed, mobile-first.** Icons and colour first, any words ≤ 6 (the tutorial's cards
  ≤ 8, per its design), buttons ≥ 56 px tall. Nothing timed against the player; every motion honours
  `Kit.reducedMotion()`.
- **Rewards for playing never pressure.** Play gifts refill each UTC day with nothing lost for a day away; the 🎁 ring
  and boost chips count only active play, so nothing runs out while you're gone; badges and ranks only go up.
- **No streaks, no timed offers, no paid random items, nothing paid at all in this build.** `Config.GamePasses.DoubleCash`
  stays 0: the 2× Cash pass needs a rethink (OPEN #8, design §9), and anything paid needs both brothers' yes and the
  ownership note first (CLAUDE.md red lines 4 and 5).

## Performance budget
Full note (how to measure, the before/after table): `docs/plan/2026-11-16-perf-budget.md`.
- **60 fps on a mid phone** with 6 full plots and the belt. **≤ 400 parts per plot** at Lv 5 without creatures
  and decor (*(look)* a Lv 5 plot with every room is 331, or 337 with the Jungle/Royal theme prop, counted by
  `tests/PartBudget.spec` on the shipped builders; the shares are Building ≤ 160, rooms ≤ 90, the plot ≤ 115).
  Decor adds up to 10 pieces of ≤ 25 parts each (DecorBuilder warns past it): 507 for a fully decorated Lv 5 plot
  with the 10 heaviest placeholder pieces. `ClinicTown` is 512 of 600. Each creature is under 40 parts (patients at
  most 39, nurses at most 38 with the cap; 8 nurses at most, R5). The lead measures both in Studio (perf note).
- **No per-frame server writes for creatures or riders.** A moving creature has the tag `CreatureMotion`. The server
  sets the motion attributes once per animation (`CreatureBuilder.hop`/`shake`/`tilt`/`scale`, or NurseBuilder's
  hop) and writes the end pose once. `Feel/CreatureMotion` draws the rest on each client. Riders follow the belt
  formula, and the server writes them at most once a second.
- **At most 1 Highlight in the world, and no light casts shadows.** Creatures never use a Highlight: night ones glow
  with Neon and a PointLight. Builders strip Highlights and turn off shadows on kit models.
- **Client loops sleep.** Nothing runs every frame unless something on screen moves. Find instances by
  CollectionService tag, never with `DescendantAdded` on the whole town. MicroProfiler labels: `CreatureMotion`,
  `Atmosphere sway`, `Tutorial layout`.

## The brother's kit (`ServerStorage`, in the place file, not git)
| Put a Model here | And the game uses it instead of |
|---|---|
| `ClinicKit.Stand`, `.BathRoom`, `.Ward`, `.WinterWing`, `.Garden` | The placeholder room. It needs a `Floor` Part plus its `Station_*`, `Bed_<n>` and `DecorSlot_<n>` parts |
| `ClinicKit.Plot` | The placeholder plot. It needs `Ground`, `Sign`/`SignGui`, `Counter`, the 3 markers and `Slots.RoomSlot_*`. The game paves its `QueueLane` from those markers; a `QueueLane` Model of the brother's own inside the Plot is kept instead. Keep the sign's board higher than the fence in front of it |
| `ClinicKit.Decor.<DecorId>` | The placeholder decor (4×4 footprint, pivot at the bottom centre) |
| `Creatures.<PatientId>` | The placeholder creature. It still acts its ailment: props go on sockets guessed from its bounding box, and the whole body leans and bobs (no separate arms or tail to wave) |
| `ClinicKit.Building<level>` *(depth)* (2-5) | The placeholder hospital building for that level. Pivot = the centre of the plot's Ground top, facing the street; it must hold `Bed_<n>` Parts for the level's Beds − 1, and must not cover the Counter, the line, the gate, the side walkways (\|x\| 11.9 to 14) or the room slots. *(v2)* It also needs `Landing_0`, `Floor_<n>.Slab`/`Landing`, `Lift` (`Shaft`, `Car`), `Stairs`, `Wards.BedSpot_<n>.Bed_<n>` (`Floor = 1`), `Hydro.HotTub` (`TubSpot_1/2`, `SoakPrompt`), `Pharmacy.Station_Pharmacy`, `Roof.HeliSpot` and `AmbulanceBay.Ambulance.StretcherSpot`; PlotBuilder adds the prompts and tags |
| `ClinicKit.NurseAgency` · `ClinicKit.PlayerMarket` *(v2)* | The placeholder kiosks (pivot = the ground under the middle, facing the spawn; ≤ 25 parts, no lights, no Highlight). A ProximityPrompt named `Prompt` inside is used, else one is added |
| `ClinicKit.NurseBelt` *(depth)* | The placeholder belt. It needs Parts `BeltStart`, `BeltEnd` and `Sign` (optional: `OddsGui` on the Sign, a `Riders` folder, a `Conveyor` part); pivot on the street at `Config.Town.Origin + Config.Belt.Offset` (the east end), turned by `Config.Belt.Heading` (180), so its +X runs along the belt toward the west end. A kit belt keeps its own `Sign`; without one the game builds the odds sign at the plaza |
| `Nurses.<NurseId>` *(depth)* | The placeholder nurse (a Model or MeshPart, face toward -Z; no cap is added) |

Anything missing or misnamed makes PlotBuilder fall back to its placeholder and print a `[PlotBuilder] ...` warning in
Output. A kit `Station_*` without an `IconGui` gets the placeholder's floating station icon. Kit models are cloned
into Workspace, so **they must contain no Scripts**: PlotBuilder, CreatureBuilder, DecorBuilder, NurseBuilder and
NurseBelt delete any they find (with a warning), but check before each publish anyway. They also remove Highlights
and turn off light shadows (the [performance budget](#performance-budget)). The brother's step-by-step version is
`docs/guides/build-the-clinic.md` (Part H covers the belt, nurses and buildings).

## Test it
### Lune specs (pure logic)
Baseline before the look overhaul: 1,000 specs in 42 files. With the Foundation: 1,130 in 49.
```powershell
cd games-agents\game
lune run tests/run
```
New logic gets a spec first: `tests/<Name>.spec.luau`, requiring `./expect` and `../src/shared/Logic/<Name>`. Only
Lune-safe modules can be required. `Data/Stations` and `Data/Ailments` use `Color3`, so specs check them by id.

### Studio (Rojo connected)
- **Play**, then read Output: `[Main] Clinic is open.` with no red errors.
- **Two players:** Test → Clients and Servers → 2 players, for hearts, helpers, `OpenHelpers` and a leaving owner.
  For the 7th-player case, set `Config.Town.Plots = 1` and use 2 players (put it back after).
- **Phones:** the Device emulator. Check the buttons, the safe area and that the prompts reach.
- **Test switches (Workspace attributes, set on the server; put them back after):**
  - A first visit, again and again: set the Workspace attribute `FreshSave = true` **before Play** (Properties →
    Workspace → Attributes → + → boolean, or `workspace:SetAttribute("FreshSave", true)` in Edit mode). Every player
    who joins then gets a blank save (the tutorial starts at the welcome) that lives in memory only: the DataStore
    is never read or written, so the real save is untouched. Output warns `[PlayerData] FreshSave is on`. Studio
    only: a live server ignores it. Take it off (or delete it) before you publish.
  - Winter: `workspace:SetAttribute("ForceWinter", true)`.
  - End the current day or night now: `workspace:SetAttribute("SkipPhase", true)` (twice = a whole clinic day, so
    the Day Report pops). Or shorten `Config.DaySeconds` and `Config.NightSeconds`.
  - UTC midnight: `workspace:SetAttribute("UtcDay", workspace:GetAttribute("UtcDay") + 1)`. Daily, Story, Events
    and Playtime all follow it (new visitor, a new goal, the mailbox opens, the six play gifts refill and today's play
    time starts again). Setting it below the real day snaps back. This works in Studio only: live servers always use
    the real day.
  - Idle: stand still for `Config.PlaytimeIdleSeconds` (lower it to 20 to test) and the 🎁 ring and boost chips stop;
    move and they go on.
  - Force Today's Visitor: `workspace:SetAttribute("TodaysVisitor", "CloudSheep")` (lasts until the day changes).
  - *(depth)* Every belt arrival one rarity: `workspace:SetAttribute("BeltForce", "Mythic")` (any of Common, Rare,
    Epic, Legendary, Mythic, Secret). The pity still wins over a forced Common, so `"Common"` gives 8 Commons then a
    Rare+ (checklist D9). Remove it after.
  - *(depth)* A Golden Hour now: `workspace:SetAttribute("ForceGolden", true)`. It runs for `Config.Belt.GoldenSeconds`
    and the attribute clears itself. (Without it, the first one comes 20 minutes after the server starts.)
  - *(depth)* Night Rush: `SkipPhase` into the night (above); the belt follows `IsNight`.
  - *(depth)* Every plot's building at one level: `workspace:SetAttribute("PreviewLevel", 5)`. Looks only (its beds
    and *(v2)* lift work); the line and recipes follow the real level and nothing is saved. Set it to nil to go back.
  - *(v2)* Every plot's building in one branch theme: `workspace:SetAttribute("PreviewTheme", "Space")` (any
    Data/Themes id; combine it with `PreviewLevel`). Studio only. Set it to nil to go back.
  - *(v2)* Every new patient Golden at an R3+ clinic: `workspace:SetAttribute("ForceGoldenPatient", true)`. Studio
    only: a live server ignores it. Remove it after (checklist P17).
  - The next story day without touching `UtcDay`: set a regular's `LastBeatDay` back by 1 in the save.
  - With **Studio Access to API Services** on, a forward-set `UtcDay` is written into the real save
    (`LastGrantDay`, `Mailbox.LastSeenDay`, `HeartsGiven`, `VisitorDay`, a story's `LastBeatDay`, `Playtime.Day`). The
    next load
    pulls those days back to the real UTC day (`Schema.reconcile`), so the account isn't locked out, but it can
    still lose that day's mail or goal. A spare account, or API access off, is still the cleanest.
- **Creature check:** a line has small, medium and big patients that never overlap; each acts its ailment with its
  props (see `Data/AilmentActing`), waves at ≤ 50% patience and bounces with a "!" at ≤ 25%; the props pop off with a
  sparkle on Treat; with 💤 calm effects every motion is small and slow (no shivering, no circling stars).
- **Feel check:** a cure gives sparkles, a pop, a chime and the NEW PAGE banner; in ⚙️, the ✨ switch turns to 💤
  and the effects calm down, and 🎵 turns to 🔇 and the music fades; `ForceWinter` brings snow; at night there are
  fireflies and the lamps and lanterns glow. *(depth)* 💰/⭐ roll up as coins fly from the patient, toasts slide in,
  the Golden Hour banner shows (no countdown), rarity frames are still, red dots pop once, ONE claim button breathes and shines, the conveyor
  stripes scroll, and a level-up / new nurse / Journal set / new room shows the celebration screen; 💤 calm stops
  all of that motion (numbers just set, no confetti, still stripes, no nurse sparkles).
- **Junk remote calls**, from the client command bar. Each must return `false` plus a message and change nothing:
  ```lua
  local R = game.ReplicatedStorage.Remotes
  print(R.Purchase:InvokeServer("Room", 123))
  print(R.Purchase:InvokeServer("Room", "Garden"))       -- not enough ⭐ or cash
  print(R.PlaceDecor:InvokeServer("Stand:9", "CozyRug")) -- no such slot, or not owned
  print(R.ClaimGoal:InvokeServer(-1))
  print(R.TutorialAck:InvokeServer(8))                  -- only ever moves the welcome card (step 1) on
  print(R.ClaimPlayGift:InvokeServer(6))                -- locked: "⏳ Keep playing!"
  print(R.ClaimPlayGift:InvokeServer(0), R.ClaimPlayGift:InvokeServer("1"), R.ClaimPlayGift:InvokeServer(1.5))
  print(R.SetHelpers:InvokeServer("yes"), R.SetHelpers:InvokeServer(1)) -- not a boolean: OpenHelpers unchanged
  print(R.SetHelpers:InvokeServer(true))                -- from a player with no clinic: "🏠 No clinic yet!"
  -- depth update
  print(R.TreatResult:InvokeServer(-1, { "Perfect" }))   -- not your session
  print(R.TreatResult:InvokeServer("1", "Perfect"))      -- wrong types
  print(R.HireNurse:InvokeServer(-1))                    -- no such rider
  print(R.HireNurse:InvokeServer(0 / 0))
  -- Progression v2 (EquipNurse is gone; the plan's §D P19)
  print(R.SetJob:InvokeServer("PuffPup", "Rest"))         -- never a job
  print(R.SetJob:InvokeServer("x", 1))
  print(R.OpenBranch:InvokeServer(false), R.OpenBranch:InvokeServer(true)) -- not confirmed · below Lv 5
  print(R.ChoosePerk:InvokeServer("BathReady"))           -- not offered
  print(R.BuyNode:InvokeServer("TwinCounters"))           -- the capstone is locked
  print(R.SetTheme:InvokeServer("Royal"))                 -- R5 only
  print(R.AgencyBuy:InvokeServer(1, "GoldieGryphlet", 1), R.AgencyBuy:InvokeServer(0 / 0, "PuffPup", 150))
  print(R.SellNurse:InvokeServer("PuffPup", 999))         -- not the shown price (or not owned)
  print(R.ListNurse:InvokeServer("PuffPup", 1), R.ListNurse:InvokeServer("PuffPup", 1e9)) -- outside the band
  print(R.BuyListing:InvokeServer(-1, 0), R.Unlist:InvokeServer(999))
  print(R.RideLift:InvokeServer(9), R.RideLift:InvokeServer(1)) -- no such floor · from the street
  print(R.Triage:InvokeServer(-1, "Hydro"))               -- no pick waiting
  print(R.LevelUp:InvokeServer())                       -- "Need ⭐15" on a new save
  print(R.SetSimple:InvokeServer("on"))
  ```
  A `TreatResult` for your own open session sent too early, or from far from the Counter, is accepted but rated all
  OK with no tip and the combo reset (no fail states).

## Playtest checklist (build plan §D)
- [ ] 0. **First session** (`FreshSave = true`, then Play): you stand in front of the Counter beside the line,
  facing the clinic; the camera sweeps over it under "Welcome to Cure a Creature!" (no sweep with Reduced Motion);
  only 💰 and ⚙️ show. Every card in [the tutorial table](#the-first-session-tutorial) appears in turn and moves on
  by itself as you play: the pin on the first patient, the arrow to 🧪 then the Counter, the pin on the bed, ⭐
  appears with the first cure, 🛒 bounces in at step 7 (a 🎁 top-up if you're short), the 👇 on the cheapest
  upgrade, then 📖; after it the rest of the HUD and the Mailbox letter. Patience never runs out in steps 1-6, no
  regular, visitor, Day Report or ambient toast shows, and badges up close stay small. Then a save with a cure (no
  `FreshSave`) shows the whole HUD at once and no tutorial.
- [ ] 1. Output shows `[Main] Clinic is open.` and no red errors. The town shows 6 plots, you get one, and its sign
  shows your name.
- [ ] 2. The first patient arrives within 60 s with an icon. The guide arrow points to the station. Hold → carry icon →
  the arrow points to the Counter → Treat → a mini-game (OK still cures) → bed → cured → cash and ⭐, with sparkle
  and chime.
- [ ] 3. A wrong item gives a head-shake and a hint. Making the right item with a full tray swaps the old one out
  (🔄 toast), so the line never jams. Patience running out means a sad puff and no penalty.
- [ ] 4. Upgrades buy and change the hold time, tray, patience and tips. The Bath Room unlocks at ⭐10 and 150 cash,
  appears in its slot, and its station works. Bath patients start arriving.
- [ ] 5. Patient Book: the first cure gives NEW PAGE, the silhouette fills in, and completing the Starter set grants
  HeartRug.
- [ ] 6. Decor: buy, place in a slot, and it appears. Leave and rejoin, and the same decor is there.
- [ ] 7. Night: night patients glow, pay 2×, and the Day Report pops at night's end.
- [ ] 8. The WinterWing can be bought any time of year (⭐40, 💰500) and its Cocoa station works. Winter
  (`ForceWinter`): it snows and Frosty variants appear.
- [ ] 9. Today's Visitor ⭐ shows up once, the HUD chip turns ✅ once it's cured, and it doesn't come again on another
  server the same UTC day. A daily goal fills and is claimed. The mailbox gift works once.
- [ ] 10. ShySprout appears and the bubble shows beat 1. A second cure the same UTC day doesn't advance it. Simulate
  the next day (set `LastBeatDay` back) and it advances.
- [ ] 11. Hearts: a heart from a second client counts once a day, and the sign's count is still there after the owner
  rejoins. The "❤️ Send a heart" prompt shows only within ~6 studs of the sign, needs a short hold, sits below and to
  the side of the board (never over its words), and the owner never sees it. Helpers: the owner's ⚙️ Settings shows
  "👥 Friends only"; a tap turns it to "🤝 Anyone can help" with the toast "🤝 Anyone can help now!", and back with
  "🔒 Only friends can help now". A visitor's ⚙️ (no clinic of their own) has no helpers row, and nothing about
  helpers floats on the sign. A non-friend can't treat while it's "Friends only".
- [ ] 12. Rejoin keeps everything. Junk remote calls are rejected.
- [ ] 13. Leaderboards: the 🏆 Hall of Fame garden stands past the street's west end, nothing of it on the street,
  curbs, plots, arches or plaza; its boards face the spawn down the street and are readable up close and at night.
  🏆 Top opens the panel: each tab shows its board, your bar shows "You: #n" (or "Play to join in!"). A cure moves
  your number within a few seconds. Admins aren't on any board ([Leaderboards](#leaderboards)).
- [ ] 14. **Play gifts:** after the tutorial 🎁 bounces in under the wallet and its dot ring fills as you play; it
  stops when you stand still for `PlaytimeIdleSeconds`. At 2 min the dot shows and the 🎁 panel's first card shines;
  Open! pays 💰20 with flying coins. Rejoin: the time and opened gifts are kept. 🛠️ "+10 min today" (x4) unlocks the
  rest; the 5, 15 and 40 min gifts start ⚡ 🍀 🌠 chips beside the clock that count down only while you play. After
  the sixth: "🎉 All gifts opened today!". Forward `UtcDay`: all six refill, today's time is 0:00.
- [ ] 15. **Ranks:** 🛠️ "+5 h total": the banner and toast for 🩹 Intern and 🩺 Resident, their decor in 🛒 Decor,
  the sign's pill shows 🩺 Resident, the 🎁 panel says "Doctor rank: Resident · 5h played · next: 🥼 Doctor at 10h".
- [ ] 16. **Boosts:** with ⚡ Quick Hands the station ring is shorter and a hold that matches it makes the item (no
  "Hold a little longer!"); 🌠 Star Rush doubles a cure's ⭐; the "Your boosts" line lists them.
- [ ] 17. **Badges:** the 🏅 tab after the tutorial; tabs switch categories; 🛠️ "+100 cures" gives 🥉 then 🥈 Healer
  with a banner, a toast and 💰⭐; the card's frame turns bronze then silver and says "🥇 Gold → +3% 💰". An existing
  save with cures gets its seeded tiers on first join. 🛠️ "Max badges": one "15 badges up!" banner, every card Mythic.
- [ ] 18. **The rails on a phone** (Device emulator, 640x360 and a 667 px one): after the tutorial 🛒 👩‍⚕️ 📖 on the left
  and 🎁 🎯 📬 on the right, each 56 px, 🏅 and 🏆 under ⚙️ More; nothing in the bottom corners (the thumbstick and
  the jump button).
- [ ] 19. **The queue lane:** on every plot 6 mid-tone tiles with an edge in the plot's colour on
  each side and the numbers on discs in the plot colour run from just in front of the Counter out to the gate, with spots 1, 2, 3 under the line; the numbers
  read upright walking in from the gate. Patients wait exactly on the numbered spots (1 at the Counter), you and
  the patients walk across the edges freely, and nothing flickers from the street or at night.
- [ ] 20. **The sign:** from the street and from the front path the whole clinic sign (name, ❤️ count, rank pill)
  shows above the fence, beside the gate; the comet star (once DizzyComet's story is finished) still sits on top of
  it.
- [ ] 21. **Settings on a phone** (a small landscape phone): as an admin who owns a clinic, ⚙️ shows 🎵, ✨, 👥 and
  🛠️, all on the card (scaled down if needed), none cut off.

**Edge cases (build plan, Review Focus):**
- [ ] The plot owner leaves mid-cure: patients, carry visuals and prompts on that plot clean up with no errors, a
  helper whose patient was resting still gets the cure, and the plot goes to the next joiner (whose prompts work).
- [ ] A 7th player joins when 6 plots are taken: no plot, a toast explains it, and they can visit, help (if
  allowed) and leave hearts.
- [ ] The DataStore fails on load: the game plays, never saves over the real data, and a toast warns "Saving is
  off".
- [ ] Junk to a remote (wrong types, unknown ids, spam, buying a room on someone else's plot) is rejected with a
  message, and state is unchanged.
- [ ] UTC midnight passes mid-session: Today's Visitor, the daily goals and the story-day gate roll over without a
  rejoin.

### Depth update checklist (build plan §D)
- [ ] D0. Boot: `[Main] Clinic is open.`, no red errors; the belt runs along the main street (row-1 side) from the
  east arch to the west arch, its sign at the plaza shows the day odds, the conveyor stripes scroll.
- [ ] D1. An old save (no `Level`): loads at its implied level (a Garden owner is Lv 3), empty journal; `Version` 3
  on save.
- [ ] D2. Fresh save (`FreshSave`): the tutorial runs unchanged; patients have 1-item recipes; Treat opens a
  mini-game over the tutorial card; OK still cures; the HUD reveals 👩‍⚕️ with the rest at the end; no belt banner,
  combo sticker or celebration during it.
- [ ] D3. Each mini-game (Pour, Patch, Scrub, Cool) on PC and the phone emulator: rated OK/Good/Perfect; a Perfect
  pays a small tip and the combo counter climbs; ×1.2 at 3; a Good holds it; an OK resets it to "Go!". Look for
  `[MiniGames] ... broke` warns.
- [ ] D4. Lv 2: a Bath patient needs 🛁🧪; with a tray of 1 you give 🛁 (one game), the badge ticks, then 🧪. The
  guide arrow goes to the Counter while you carry 🧪 too.
- [ ] D5. Simple mode (⚙️): every game is one tap, rated Good, no tips.
- [ ] D6. Junk (the commands above): all `false` + a message, nothing changes. An early `TreatResult` is `true`,
  all OK, no tip.
- [ ] D7. The belt: a nurse about every 40 s, each takes ~100 s end to end (two or three ride at once); prices scale
  with your level; Hire by tap and by prompt; a second player sees the same riders; the hired one hops off; a
  Common/Rare hire that leaves the belt empty is replaced within 8 s. Below hospital Lv 3 an Epic+ shows "🏥 Lv 3"
  and can't be hired (no arrival banner for it); from Lv 3 it can.
- [ ] D8. Night (`SkipPhase`): the sign shows Night Rush odds; Mythic possible. Golden Hour (`ForceGolden`): a banner
  with the Secret chance and no countdown, Secret on the sign.
- [ ] D9. Pity: `BeltForce = "Common"` → the 16th arrival is Rare+ (15 in a row without one).
- [ ] D10. Journal: silhouettes until seen (within 100 studs); NEW! on first seen and first hire; completion %;
  completing Commons gives 💰300 + Plaster Rug once.
- [ ] D11. Nurses at work: a Maker (items appear in the 🧺 tray, treating uses them), a Healer (treats the
  front patient with OK), a Cheerer (longer patience). *(v2: there is no equip any more: every nurse you own works,
  up to the roster cap, and its job is set in 👩‍⚕️ Team; see P3-P4.)* Leave and rejoin: the same nurses work.
  With 💤 calm, Epic+ nurse sparkles stop.
- [ ] D12. Level up in the Shop's Hospital tab: celebration, the building grows (`PreviewLevel` to look at each),
  beds (and *(v2)* floors and departments) follow the table, the line stays at 3 and patients come faster; the Garden needs Lv 3 (no "Buy in 🛒"
  toast or 🛒 dot for it before).
- [ ] D13. Juice: count-ups, flying coins, toasts slide, rarity frames shimmer, sounds; calm mode quiets all of it.
- [ ] D14. Perf: 6 full plots + belt on a mid phone ≈ 60 fps; Network receive stays low while creatures hop; fill
  in the measured columns of the perf note.
- [ ] D15. Owner leaves mid-game / mid-hire / with nurses: no errors, the plot is clean, the next joiner's prompts
  work; a helper leaving mid-game still lets the patient finish.

### Progression v2 checklist (build plan §D)
The full list with every expected result is `docs/plan/2026-11-16-progression-v2-build-plan.md` §D; in short:
- [ ] P0. Boot: no red errors; the 🏢 Agency and 🏷️ Market kiosks on the plaza's row-2 side, clear of everything; the
  belt sign's two gate rows.
- [ ] P1. Migration: a v3 save (5 nurses, 4 equipped) → 3 work, 2 💤, XP 0, jobs = roles, `Version` 4; a v2 save →
  `Rebirth` defaults; a v4 save on a v3 build stays read-only.
- [ ] P2. `FreshSave`: the tutorial is unchanged; Team 0/3; the first hire works its role.
- [ ] P3. Roster: a 4th new nurse is refused on the belt, the Agency and the Market; a copy adds a level; ⭐ MAX.
- [ ] P4. Jobs: Porter/Medic "🏥 Lv 2" at Lv 1; at Lv 2 a Porter rides patients up and a Medic serves 🚑; a
  Receptionist skips the triage buttons; after a rebirth a Porter works as its role.
- [ ] P5. XP: bars fill, ⬆️ at Lv 2, 🛠️ Nurse levels x4 → the Lv 5 celebration; Fast Learners doubles it.
- [ ] P6. Abilities (🛠️ Charge): each fires only when useful, a sparkle and a ring (no digits); Golden Touch, Calm
  Song, Busy Paws, Miracle once a day; 💤 calm stops the sparkles.
- [ ] P7. Teams: 2 Reception specialists "🛎️ ×2" +10% 💰; 3 Hydro specialists make 🛁 holds 40% shorter.
- [ ] P8. Agency: 4 nurses at ×1.5, 🎲 70/26/4, no clock; buy → ✅, not twice; 🛠️ Restock; Epic "🏥 Lv 3"; sell with a
  confirm (hold for Epic+); Lucky Stock's 2 slots survive a rejoin.
- [ ] P9. Market (2 players): the band; a buy moves the nurse with its level, −10% to the seller; your own / a copy / a
  full roster / above your level cap refused; spam from both → one sale; the seller leaves → the listing goes.
- [ ] P10. Rebirth: a calm 🏢 card, no dot; keep/reset with Not now first and a 1.5 s hold; the celebration, the
  Arctic Stand, 💰0, rooms and upgrades gone, decor back in 🛒; kept: nurses, Book, badges, rank, ⭐, decor; +3 🌳, 3
  cards (the same after a rejoin), Team 0/4, "🏢 1", the 🏆 Branches tab, 🏅 Branches Bronze. A second branch while a
  card waits: "🃏 Pick your card first!".
- [ ] P11. R1: Mythic/Secret riders hireable; Sunny-wing patients.
- [ ] P12. Tree: ranks, the capstone lock, 🔄 Reset; Quick Feet, Express Lift, Bargain, Twin Counters.
- [ ] P13. Lv 2: the second storey, the lift (a ding, the car slides on your screen), stairs, ward beds; escort for
  "+20% 🛗" or it rides alone; an ambulance flashes and sirens, its 🚑 patient pays ×3 + 2 ⭐; the lane, sign and gate
  clear (`PreviewLevel` 2-5).
- [ ] P14. Lv 3 Hydro: the 🛁 chip, triage buttons, right +10% / wrong "Oops, not this floor!" / none in 4 s; the
  tub's 🫧 game.
- [ ] P15. Lv 4 Pharmacy: 🧪 + ☕ → 🍵; one Pour ticks both; at R2 two more medicines and a faster hold.
- [ ] P16. Lv 5 + R2: the helicopter lands, its VIP rides down, ×4 + 3 ⭐, a Sky page.
- [ ] P17. R3-R6: Golden patients (`ForceGoldenPatient`), the Lv 15 cap; R4 Night Clinic; R5 FounderFennec (or a gift)
  and the mascot; R6 TrophyCup.
- [ ] P18. Themes: pick any unlocked one (`PreviewTheme` too); the trim and the roof band recolour and the prop
  changes; the walls stay the plot's colour.
- [ ] P19. Junk calls ([the list above](#studio-rojo-connected)): each `false` + a message, nothing changes.
- [ ] P20. Kids' rules: countdowns only for FREE events (`memory-20261116-022`: the Golden Hour chip and the finale
  chip in minutes, the labelled day/night line in m:ss); never a clock on anything paid (the Agency, the belt,
  abilities and triage stay clockless); no rebirth nagging after the one toast, a confirm before every
  buy/sell/list, odds on the belt, the Agency 🎲, the perk cards and the R3 unlock.
- [ ] P21. Phones (667 px landscape): Branch, Agency, Market, Team and the lift picker fit, buttons ≥ 56 px, the rails
  (3 a side, the rest under ⚙️ More).
- [ ] P22. Perf: Lv 5 with every room ≤ 400 parts (counted: 337; 507 with every decor slot); 6 plots × 8 nurses ≈ 60 fps; no network
  spike during rides and ambulances. Fill in the perf note.
- [ ] P23. Leaving mid-escort, mid-ride, mid-triage, mid-soak and with listings: no errors, a clean plot.
- [ ] P24. Before publishing: re-read Roblox's live Terms of Use and Community Standards on in-experience trading,
  re-check the maturity questionnaire; publishing needs both brothers' yes.

### Look overhaul checklist (build plan §E; the lead, in Studio, after the merge)
The full list with pass marks is the plan's §E (P1–P21). The short form:
- [ ] L1. **Boot:** `[Main] Clinic is open.`, no red errors, no `[DayNight] Lighting.<key> not set:` warning; on a
  client `Lighting.LightingStyle == Enum.LightingStyle.Soft`.
- [ ] L2. **Day and night** (`SkipPhase` twice): night is darker and violet; lamp heads, the paw-heart and the beacon
  glow, windows go warm (not Neon); in the morning every studded part is studded again.
- [ ] L3. **Studs** in Surface mode (and Variant mode once `CureStuds` exists): whole studs, no slivers, no z-fight on
  the lawn tiles at Quality 1, 4 and 10.
- [ ] L4. **Town:** the belt on the centre line, riders facing the plaza, the spawn clear, hire works at the 240 px
  card; the odds sign faces the spawn and its prompt, the card's 🎲 and the Journal's 🎲 open one popup; both kiosks
  face the spawn and open their panels.
- [ ] L5. **Hospital** (`PreviewLevel` 1–5, then a real level-up): every flight rises the right way with headroom;
  a patient walks from the queue lane to an upstairs ward bed by the lift landing; rides, escorts and porters work
  with the solid shaft; the cutaway hides the storeys above you and restores them.
- [ ] L6. **HUD** at 640x360, 667x375, 1024x600 and 1920x1080: the zones never overlap; panels hide the rails, Now
  and Status; a mini-game keeps the Now card; a celebration hides everything.
- [ ] L7. **Panels:** one navy header each, 88 px tabs, no text under 18 px (scan PlayerGui), at most one shine.
- [ ] L8. **Tutorial** (`FreshSave`): the beam lies flat and bends through the door, chevrons point forward, one
  Highlight; the 7 cards; Skip (no gift, arrows stay to 3 cures); Replay from ⚙️ (no sweep, no gift, 30 s cooldown).
- [ ] L9. **Rebirth with a theme:** the trim, roof band and prop change, walls stay; the celebration wears the
  theme's Roof and Trim; bed spots carry across.
- [ ] L10. **Creatures:** every species blocky, under 40 parts, the client's ailment props sit right; nurse caps
  carry the paw-heart.
- [ ] L11. **Reduced motion** (the Roblox setting and the in-game 💤): every motion stops or shortens.
- [ ] L12. **Originality:** no cross emblem and no borrowed asset anywhere (search the place for "Cross").
- [ ] L13. **Perf:** `Plot_1` at Lv 5 with every room ≤ 400 parts (counted: 337), `ClinicTown` ≤ 600 (512); phone
  frame time with 6 full plots and the belt; fill in the perf note's Studio columns.

Write the results in `logs/playtests/`. The shop-sim checklist (first run 2026-11-16) is in git history.

## Before committing
```powershell
selene src
stylua --check src tests
lune run tests/run
```
