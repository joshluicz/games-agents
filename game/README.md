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
| `shared/Config.luau` | **Every tuning number**: pay, patience, queue, hold times, day and night length, the winter window, autosave, town layout, music, pass IDs; *(depth)* `MiniGame` (tips, combo, game timings), `Treat`, `Belt` (odds, Night Rush, Golden Hour, pity, prices, distances incl. `SeenDistance`), `Nurses` |
| `shared/Palette.luau` | The candy-pop colours and fonts shared by the world and the UI (`memory-20261116-007`). Change colours here |
| `shared/Types.luau` | The shared type names (`Data`, `Snapshot`, `Plot`, `Ctx`, ids); *(depth)* `TreatSession`, `TreatOutcome`, `NurseNews`, `ShoutInfo`, `CelebrateInfo` (incl. `Room` for Kind "Room"), `BannerSpec` |
| `shared/Remotes.luau` | Creates `ReplicatedStorage.Remotes` (incl. `TutorialAck`; *(depth)* events `TreatStart`, `NurseNews`, `Shout`, `Celebrate` and functions `TreatResult`, `SetSimple`, `HireNurse`, `EquipNurse`, `LevelUp`). Server helpers: `serve` (rate limit plus pcall; a table third return value is passed on), `allow`, `toast` (always shown: replies and warnings), `news` (ambient news, held back while the player is quiet), `toastAll` (skips quiet players), `setQuiet`/`isQuiet` (Server/Tutorial makes a player in the tutorial quiet) |
| `shared/Signal.luau` | A small signal that passes tables **by reference** (used instead of BindableEvents) |
| `shared/Data/*.luau` | **Content**: `Ailments` (with each `Recipe`), `Stations`, `Items`, `Patients`, `Regulars` (their own `Recipe`), `Rooms` (`Level`: the Garden needs Lv 3), `Upgrades`, `Decor` (incl. the six Journal rewards), `DailyGoals`, `Wings`, `Variants`, *(depth)* `Nurses` (16 placeholder-named nurses), `Rarities` (Common..Secret, colours, Journal rewards), `Levels` (an array, Lv 1-5, incl. `SpawnSeconds`). Keyed maps carry `.Order`, and everything is frozen |
| `shared/Logic/Schema.luau` | Save schema **v3**: `default()`, `reconcile(saved, today?)` (migrates v1 shop saves, pulls future days back to today, gives a save without `Tutorial` its step: any cure means done; a v2 save gets the hospital `Level` its rooms imply, no nurses and an empty journal), `isNewer(saved)`, `levelFromRooms(rooms)` |
| `shared/Logic/Tutorial.luau` | The first-session tutorial's rules: the steps (1 welcome .. 8 Book, 9 done), `advance(step, event)`, `resume` after a rejoin, who Patients may send (`spawnPlan`, `queueCap`), the shop top-up (`cheapest`, `topUp`) |
| `shared/Logic/Pay.luau` | Cash and ⭐ for a cure (*(depth)* a longer recipe pays more, and so does a Cheerer on duty) |
| `shared/Logic/Prices.luau` | Upgrade prices, hold time, tray capacity, patience |
| `shared/Logic/Progress.luau` | Can this room be bought (season, *(depth)* the hospital level a room needs, ⭐, 💰), and what's the next goal (it skips rooms above your level: `levelAllows`) |
| `shared/Logic/Book.luau` | Patient Book stamps and set completion |
| `shared/Logic/Story.luau` | Regulars: who's unlocked, whether a beat is due today, advancing a beat |
| `shared/Logic/Daily.luau` | UTC day, Today's Visitor, banked goals, mailbox |
| `shared/Logic/Recipe.luau` *(depth)* | A patient's recipe: cut by level, the done mask, what's missing, what the items in hand can fill |
| `shared/Logic/MiniGame.luau` *(depth)* | Mini-game ratings, the server's plausibility check, the combo and capped tips |
| `shared/Logic/Belt.luau` *(depth)* | The Nurse Belt: odds (Night Rush, Golden Hour), rolls, pity, picks, prices by level, Golden Hour windows, rider position |
| `shared/Logic/Levels.luau` *(depth)* | Hospital levels: the next level's cost, slots, beds, queue, recipe cap, seconds between patients, room gates |
| `shared/Logic/Nurse.luau` *(depth)* | Owned nurses: copies and levels, stats by rarity and level, equip slots, the Journal and its set rewards |

`Logic/*` is **pure**: no Roblox services and no requires, so Lune can test it. The server passes `Config` in as
`cfg`.

### Server
| File | Does |
|---|---|
| `server/Main.server.luau` | Collision groups, then every system's `start()` in order ([Boot order](#boot-order)) |
| `server/PlayerData.luau` | Loads and saves (schema v3, DataStore `PlayerData_v2`) with `UpdateAsync` under a session lock (a join waits out another server's lock until its lease ends), migrates `PlayerData_v1`, never saves after a failed load or over a newer-version save (`DataOk = false` plus a toast), autosaves, saves on leave (retried with backoff) and in `BindToClose`. A rejoin to the same server waits for the last Player's leave-save first. Leaderstats `Cash` and `Stars`. The Studio-only `FreshSave` switch ([Test switches](#studio-rojo-connected)) |
| `server/State.luau` | Builds each player's Snapshot (incl. `Tutorial`, the step, and `TutorialCures`), pushes it (debounced) and answers `GetState` |
| `server/Tutorial.luau` | The first-session tutorial ([below](#the-first-session-tutorial)): the saved step, moved on only by real server events, the one-time shop top-up, `TutorialAck`, and the quiet toasts while it runs |
| `server/Events.luau` | Winter: `Config.Winter` dates or the `ForceWinter` Workspace attribute → `Workspace.IsWinter` |
| `server/Plots.luau` | Assigns a plot once data loads, frees it on leave, rebuilds rooms and decor from the save, `canWork` (owner, friend or `OpenHelpers`), `unlockRoom`, `placeDecor`. Owners (re)spawn in front of the Counter, beside the line, facing the clinic |
| `server/PlotBuilder.luau` | Builds the town, the plots and placeholder rooms, or clones the brother's `ServerStorage.ClinicKit` models. Night lamps (tag `ClinicNightLight`). Station icons and for-sale boards stop growing up close (`DistanceLowerLimit`). *(depth)* `buildBuilding(plotModel, level, grewFrom?)`: every plot always has a `Building` Model (empty at Lv 1; Lv 2 the ward, Lv 3+ storeys and a ✚ sign (a white cross on the plot's accent colour, never red on white), Lv 4 the ambulance bay, Lv 5 a tower and helipad), its extra beds as `BedSpot_<n>.Bed_<n>` (kept across level-ups), pieces carrying the attribute `Since`, the Building's `Level`/`GrewFrom`/`GrewAt`, and the plot's `Level` attribute; `clearPlot` puts it back to Lv 1. Kit clones lose scripts and Highlights, and their lights stop casting shadows |
| `server/Carry.luau` | What each player is carrying (`Carry`, `CarryMax` attributes) and the icon above their head |
| `server/Economy.luau` | Cash, upgrades and purchases. Wires `Purchase` and `PlaceDecor`. *(depth)* `Economy.charge(p, price, apply)` (charge and apply in one update; Levels uses it); `Purchased` also fires kind `"Level"`; rooms check their hospital level (`Progress.canBuyRoom`) |
| `server/Progress.luau` | Clinic ⭐ Stars and the next goal. Its "unlocked" and "ready" toasts skip rooms above your hospital level |
| `server/Book.luau` | Stamps the Patient Book and grants a wing's set reward |
| `server/Story.luau` | The three regulars: who's due, their speech bubble, the reward when a story ends |
| `server/Daily.luau` | `Workspace.UtcDay` and `TodaysVisitor`, banked daily goals, the mailbox. Wires `ClaimGoal` and `ClaimMailbox` |
| `server/DayReport.luau` | Counts each player's cures and new pages, and sends the Day Report when night ends |
| `server/DayNight.luau` | The day/night cycle (`IsNight`, `PhaseEndsAt`) and the candy-pop lighting grade (the `CandyColor` ColorCorrection, Atmosphere, Bloom), set from code by day and by night |
| `server/Stations.luau` | A hold-to-make prompt on every `Station_*`, with the hold time checked on the server. A full tray swaps out an item nobody in this clinic's line needs first (it reads `QueueNeeds`), else the oldest different one |
| `server/Patients.luau` | A queue per plot, the `Treat` prompt on the Counter (tag `TreatPrompt`), beds, patience, night patients, variants, visitors and regulars. During an owner's tutorial: its two patients, one at a time, no patience running out (steps 1-6), no regulars or visitor. *(depth)* Recipes cut by the owner's level (`Levels.recipeCap`; always 1 item in the tutorial; only patients the plot can make come), the patient attributes `Recipe`/`RecipeDone` and State `"Treating"` (patience paused), the plot attributes `FrontNeeds`/`QueueNeeds`, the line length from `Levels.queueCap`, a Cheerer's `CheerPatience`, beds under `Rooms` or `Building`. Treat takes the helper's items, then the nurse tray's, and drives `Treatment.open/busy/drop/onHeal`. Creatures move by the creature-motion attributes: one end-pose write per hop, never per frame |
| `server/CreatureBuilder.luau` | A creature Model from its `Look`, or a clone of `ServerStorage.Creatures.<PatientId>`. The badge and bubble stop growing up close (`DistanceLowerLimit`). *(depth)* Tags creatures `CreatureMotion` and sets the motion attributes the clients draw (`hop`, `shake`, `tilt`, `scale`). `setRecipe` draws a 2-3 item recipe as chips on the badge. `buildLook` (NurseBuilder uses it). No Highlights, no shadow-casting lights (kit creatures too) |
| `server/Cure.luau` | One cure, in order: pay, cash, ⭐, Book, daily goals, story, Day Report, the `Cured` remote, then the owner's tutorial |
| `server/DecorBuilder.luau` | A decor Model from its `Look`, or a clone of `ServerStorage.ClinicKit.Decor.<DecorId>` (scripts and Highlights removed, lights without shadows) |
| `server/Visits.luau` | Hearts on the sign (once per owner per UTC day), the owner's `OpenHelpers` toggle, the friend referral reward |
| `server/Treatment.luau` *(depth)* | Treat sessions at the Counter: `TreatStart`/`TreatResult` (one open session per player; any other id is refused and changes nothing; the server's ratings come from `MiniGame.accept`, all OK when the report is too early or the helper is over `Config.Treat.Distance` from the Counter), the timeout (all OK), tips (cash only, capped per cure, × the plot's Cheerer) and the player attribute `Combo`, Simple mode (`SetSimple`), Healer deliveries. Patients drives it through `Treatment.open/busy/drop/onHeal`; it never requires Patients |
| `server/Levels.luau` *(depth)* | Hospital levels: `LevelUp` (⭐ is a gate, 💰 is spent, in one update), the plot's `Building` and `Level` attribute (they follow `Data.Level`; a build that fails isn't retried until the level changes), slots/queue/recipe cap/beds/spawn seconds by level, `LevelChanged (p, level, previous)` only on a change (never at join), the `Celebrate` LevelUp. Studio switch `PreviewLevel` |
| `server/Nurses.luau` *(depth)* | Owned nurses: `EquipNurse` (only known NurseIds take a slot; one change per 0.35 s per player), `grant` (charge + copy + journal mark + a first copy on duty + set rewards in one update), nurse workers on the plot (Maker → the `NurseTray`, Healer → `Heal`, Cheerer → `CheerPatience`/`CheerTip`; only while the owner is in the server), the 🧺 `NurseTrayGui` on each Counter, the Journal (`markSeen(nurseId, players?)`: the players near a rider). Resets the plot's tray and cheer attributes at boot and on release |
| `server/NurseBelt.luau` *(depth)* | The shared Nurse Belt in town (`Workspace.NurseBelt`): an arrival every 6 s, odds, Night Rush, Golden Hour (on server uptime), pity, `HireNurse` (cooldown, distance by the belt formula, max level, the price by level), the odds sign, `Shout`s, Seen within `Config.Belt.SeenDistance`. Its `Conveyor` has `ConveyorGui > Clip > Stripes` and the attributes `StripeStuds`/`StudsPerSecond` (BeltView scrolls them). Studio switches `BeltForce`, `ForceGolden` |
| `server/NurseBuilder.luau` *(depth)* | A nurse Model from its Look (via `CreatureBuilder.buildLook`) with a cap in its rarity colour (a white cross) and sparkles for Epic+, or `ServerStorage.Nurses.<NurseId>`; `setTask(model, task, icon?)` (a small task bubble), `hop(model, from, to, height, seconds, spin?)`, `popIn(model)`, `setGlow(model, on)` |

### Client
| File | Does |
|---|---|
| `client/Main.client.luau` | Builds `ctx` (Remotes, Config, Data, State, `onState`, `toast`, `on`/`fire`), then loads each UI and Feel module in a pcall and calls `init(ctx)` |
| `client/UI/Theme.luau` · `client/UI/Kit.luau` | The look tokens, and building blocks (panel, button with press bounce, label...). Libraries, not inited. *(depth)* Theme.Juice timings, Theme.Confetti, DisplayOrder.Celebrate (45); Kit.countUp (rolling numbers that tick), celebrate, confetti, rarityFrame (a shimmer per rarity), rarityColor, breathing (idle calls to action), punch, isShown, setDot (dots hop), button hover, Kit.Juice (pure helpers), Kit.Ticked. Every looping effect runs on one shared loop that skips hidden UI and sleeps |
| `client/UI/Toasts.luau` | The toast stack at the top centre (each slides into place, the others make room), and the bus `Banner` above it (BeltView: Golden Hour, Night Rush, Epic+ arrivals, none with a countdown; the same Id updates in place, Seconds = 0 hides it) |
| `client/UI/Hud.luau` | Cash, ⭐ with a bar to the next unlock (both roll up, Kit.countUp, as flying coins and stars land: `Hud.fly` from a GuiObject, a world Vector3 or nil; the next unlock skips rooms above your level and includes the next hospital level), the 🔥 combo sticker on 💰 (player attribute `Combo`), what you hold (nothing when your hands are empty), the day/night timer, the big 🛒 📖 📬 🎯 👩‍⚕️ buttons (🛒's dot: a room you can buy, decor to place or a level-up you can afford, `Hud.shopNews`), and ⚙️ settings (the 🎵 music, ✨ calm-effects and 👆/🎮 Simple-mode switches). A new player's HUD reveals itself with the tutorial step; everyone else sees it all |
| `client/UI/Shop.luau` | Upgrades, Rooms and Decor tabs, plus decor place mode. *(depth)* The 🏥 Hospital tab (`Open("Shop", "Hospital")`): the level ladder, this level's stats, the next level's unlocks, its ⭐ gate and 💰 cost, Level up; `Shop.levelUpButton()`. Rooms that need a higher level show "🏥 Lv 3" |
| `client/UI/BookPanel.luau` | The Patient Book: cards by wing, silhouettes for patients not yet seen |
| `client/UI/DayReportPanel.luau` | The end-of-night pop-up (never during the tutorial) |
| `client/UI/Mailbox.luau` | The daily gift and the goals list. The letter pops once a session, never over a panel, and after the tutorial ends |
| `client/UI/Guide.luau` | The first-cures arrow: to the right station, then to the Counter once you carry anything the front patient still needs (`FrontNeeds`) (the tutorial steers it with `Guide.setSteer`). Also sets each station prompt's hold time from your own Faster Hands level. Station prompts by their tag only. Rests when there's nothing to show |
| `client/UI/Tutorial.luau` | The tutorial's step card, its pointer, the welcome title card and the first-join camera sweep; turns the camera to your clinic when you arrive. Its per-frame layout follow runs only while the tutorial shows something |
| `client/UI/PromptFilter.luau` | Hides world prompts that aren't for you: the helpers switch for visitors, "Send a heart" for the owner, and the Make and Treat prompts on clinics you can't work at (the server still checks). Finds prompts by tag (and each plot's Counter), never by scanning the town |
| `client/Feel/Sounds.luau` | One table of built-in `rbxasset://` sound cues; any module plays one with `ctx.fire("Sound", name)`. *(depth)* Plays the mini-game ratings (`MiniGameRated`), Tip and Combo (`TreatDone`), Hire/Equip/Sparkle (`NurseNews`) and a Tick per count-up number (`Kit.Ticked`). Cues may be cut short (`Length`); `play(name, volume?, pitch?)` |
| `client/Feel/CureFX.luau` | Cure sparkles, the "💰 +n" / "⭐ +n" pop, the NEW PAGE banner, placed-decor celebrations, hearts on your sign. *(depth)* Coins and stars fly from the cured patient into 💰/⭐; a new room fires the Celebrate screen (Kind Room); sparkles over the patient on Good/Perfect ratings and tip coins (`TreatDone`) |
| `client/Feel/Atmosphere.luau` | Snow while `IsWinter`, fireflies at night, gentle decor sway, the calm-effects setting (`ReduceEffects`; its switch is in the HUD's ⚙️). Each part sleeps when idle |
| `client/Music.client.luau` | Background music (`Config.Music`), day and night playlists, muted by `MusicMuted` (its switch is in the HUD's ⚙️) |
| `client/UI/Celebrate.luau` *(depth)* | Big celebration screens on the bus `Celebrate`: dim, confetti rain, rays, the reward bubble (a nurse's face with its shimmering rarity frame), a title ribbon, chips (level unlocks, rarity and role, a Journal set's cash and decor, a room's name) and a breathing 🎉 Yay!; one at a time, waits out the tutorial, closes itself after 7 s; on close the cash flies to 💰 and a new nurse to 👩‍⚕️ |
| `client/UI/MiniGames.luau` *(depth)* | The treatment mini-games on `TreatStart`: a candy card, one game per recipe item (🧪 Pour hold-and-release, 🩹 Patch tap the sore spots, 🛁 Scrub pop the bubbles, ☕ Cool blow at the biggest steam ring), touch/mouse plus Space or gamepad A, a big outlined PERFECT!/GOOD!/OK! pop and the 🔥 combo chip; Simple mode is one tap per game; then `TreatResult` (never sooner than the games' minimum time), `MiniGameRated` and `TreatDone` (it shows the server's ratings and tip) |
| `client/UI/NursePanel.luau` *(depth)* | The 👩‍⚕️ panel: the Nurse Journal (rarity tabs, silhouettes / greyed / full colour, completion %, group rewards, NEW! stickers and fly-in stamps), an on-duty slot strip, Equip/Unequip; `NursesNew` for the 👩‍⚕️ dot |
| `client/UI/BeltView.luau` *(depth)* | Smooth belt riders (the frame loop sleeps while the camera is far from the belt), a focus card per rider (rarity frame, role and stat, your price, Hire; the HirePrompt in the Custom style with its key on the card) and small stud-sized chips, only within 50 studs of you, Epic+ glow, the scrolling conveyor stripes (one repeating tween; still with reduced motion), the 🎲 odds popup (bus `Open` (`"NurseOdds"`)), Golden Hour / Night Rush / arrival banners (never in the tutorial, never a countdown) |
| `client/Feel/CreatureMotion.luau` *(depth)* | Draws creatures' hops, head-shakes, droops and pops on each client from their attributes (the server writes only each end pose). Runs only while something moves. Nurses' rarity sparkles follow this client's reduced motion |

### Tests
| File | Does |
|---|---|
| `tests/run.luau` | Runs every `tests/*.spec.luau`, prints PASS/FAIL and exits 1 on any failure |
| `tests/expect.luau` | `test(name, fn)` and `expect(x).toBe(y)`, `.toEqual(t)` (deep) and `.toBeTruthy()` |
| `tests/*.spec.luau` | `Schema`, `Data`, `Pay`, `Prices`, `Progress`, `Book`, `Story`, `Daily`, `Tutorial`, *(depth)* `Recipe`, `MiniGame`, `Belt`, `Levels`, `Nurse`. Plus the pure blocks of Roblox modules, loaded straight from the source between their markers so they test the shipped code: `ServerPure` (Patients, Treatment, Stations), `TreatmentSessions` (the real Server/Treatment under mocked services: one session per player, junk and stale ids, early reports, the tip cap, the timeout, drop, a helper leaving, Healer routing), `NurseServer` (Nurses, NurseBelt), `NurseUI` (BeltView, NursePanel), `MiniGamesPure` (UI/MiniGames), `Juice` (UI/Kit, UI/Celebrate), `Motion` (Feel/CreatureMotion, the badge's recipe row) |

## Boot order
**Server (`Main.server.luau`):**
1. `Remotes` is required first, so every remote exists before anything else runs.
2. The collision groups `Patients` and `Players` are set up. Patients walk through players and each other.
3. Then `start()`, in this order: `PlayerData` → `State` → `Events` → `Plots` → `Carry` → `Economy` → `Levels` →
   `Progress` → `Book` → `Story` → `Daily` → `DayReport` → `Tutorial` → `Stations` → `Nurses` → `Treatment` →
   `Patients` → `NurseBelt` → `Visits` → `DayNight`. Requires never loop: Patients → Treatment → Nurses → Levels;
   NurseBelt → Nurses. `NurseBuilder` is a library.
   - `Tutorial` starts before `Stations` and `Patients`, so its quiet toasts and listeners are set before any
     patient comes. `Stations`, `Patients` and `Cure` call its hooks; it requires none of them.
   - `Plots.start()` builds the whole town (`PlotBuilder.buildTown`), with a `Room_Stand` on every plot, before
     `Stations` and `Patients` start.
   - `CreatureBuilder`, `DecorBuilder` and `Cure` are libraries that other systems require, so they're not in the
     list.
   - Each `start()` runs in `xpcall`. One that errors prints `[Main] <Name>.start() failed` and the rest still start.
4. It prints `[Main] Clinic is open.`

**Client (`Main.client.luau`):** waits for `game.Loaded` and builds `ctx`. Then it loads `UI.Toasts`, `Hud`, `Shop`,
`BookPanel`, `DayReportPanel`, `Mailbox`, `Guide`, `PromptFilter`, `Celebrate`, `MiniGames`, `NursePanel`, `BeltView`
and `Tutorial`, then `Feel.Sounds`, `CureFX`, `Atmosphere` and `CreatureMotion`. Each one is loaded in its own pcall,
and its `init(ctx)` runs. A missing or broken module warns `[Client] ...` and is skipped. The server events
`TreatStart`, `NurseNews`, `Shout` and `Celebrate` are forwarded to the client bus under the same names (every bus
event is listed in `Main.client.luau`'s header). `Music.client` and `RoofFade.client` are separate LocalScripts. Until the server's
first snapshot arrives, `ctx.State.Tutorial` is 0 ("not known yet"), so the HUD starts calm (only 💰).

## The loop
A patient walks in and queues at `QueueStart`, with its ailment icon, its recipe (1 item at Lv 1, up to 3 from Lv 3)
and a patience ring → you **hold at the matching `Station_*`** to make an item (🧪 Potion, 🩹 Plaster, 🧼 Bubbles,
☕ Cocoa) → you carry it → you **Treat at the Counter** → a short **mini-game** per item given (Pour, Patch, Scrub,
Cool; OK still cures, a Perfect pays a small capped tip and builds the 🔥 combo; Simple mode is one tap) → the badge
ticks the items off, and once the recipe is complete the patient goes to a free `Bed_*` (or recovers in place) →
`Cure.resolve`: cash, ⭐, a Book stamp, goal progress, a story beat → a happy hop, and it leaves. A wrong item gets a
head-shake and a hint. Running out of patience is a sad puff, with no penalty. Nurses hired from the belt in town
help: Makers fill the nurse tray (Treat uses it too), Healers give the front patient what the tray holds, Cheerers
make patience last.

## The first-session tutorial
Design: `docs/plan/2026-11-16-first-session-design.md`. The step is the save field `Data.Tutorial` (1 to 8, 9 =
done), owned by `server/Tutorial.luau` and sent in the Snapshot (`Tutorial`, plus `TutorialCures` for step 6). A
fresh save starts at 1. A save from before the tutorial (no `Tutorial` field) with any cure (`Cured > 0`, or a v1
`Served > 0`) is done, so existing players never see it. Every step moves on only on a real server event:

| # | Card (icon first, ≤ 8 words) | Moves on when (server) |
|---|---|---|
| 1 | 👋 Welcome to your clinic, Doctor! | `TutorialAck` (the client sends it on a tap, or 4 s after the card shows; only ever moves 1 → 2, only with a clinic). No ack: by itself 30 s after the clinic is assigned |
| 2 | 🤧 A patient! The bubble shows what's wrong. | 2 s after the first patient reaches the Counter (`Patients` → `Tutorial.onFrontArrived`) |
| 3 | 🧪 Hold at the potion table! (+ device hint) | the owner makes, at their own clinic, what that patient needs (`Stations` → `onMade`); already carrying it counts |
| 4 | 🏥 Take it to the Counter. Treat! | the patient is treated (`Patients` → `onTreated`); a treat skips 2-3 too |
| 5 | 🛏️ Resting… Cured! 🎉 | the cure lands at their clinic (`Cure` → `onCured`) |
| 6 | 💪 Cure 2 more! (n/2) | 2 more cures at their clinic (count in the player attribute `TutorialCures`, not saved) |
| 7 | 🛒 Spend 💰 in the Shop! | any purchase (`Economy.Purchased`). Entering 7: a one-time cash top-up to the cheapest upgrade's price if short ("🎁 A gift to get you started!"). In-game cash only |
| 8 | 📖 Collect every creature in your Book! | 5 s later: done. Then the Mailbox letter pops |

- **Patients during it** (by the owner's step): nobody in step 1; then one easy Starter patient needing 🧪; then one
  Starter patient needing 🩹; then the usual pool. One at a time in line through step 6, patience never runs out in
  steps 1-6, and no regulars or Today's Visitor until it's done.
- **Quiet:** while it runs, ambient toasts wait (`Remotes.news`, `Remotes.toastAll`), and there's no Day Report and
  no Mailbox pop-up. Replies and warnings still show.
- **Rejoining:** steps 3-5 go back to 2 (the patient left with you); step 6 counts its 2 cures from 0 again.
- **No skip button.** The HUD reveals itself with the step (see `client/UI/Hud.luau`).

## Rules the code keeps
- **The server owns all data and money.** Every RemoteFunction is wired with `Remotes.serve` (10 calls/s per player
  per remote, plus pcall) and checks types, ids, ownership and permission. The client only asks.
- **Change the save only through `PlayerData.update(p, fn)`.** `get()` is read-only.
- **Contracts are law.** Instance names, attributes and APIs are in the build plan §B. The brother's kit follows the
  same names (`docs/guides/build-the-clinic.md`).
- **Rated Minimal, no reading needed, mobile-first.** Icons and colour first, any words ≤ 6 (the tutorial's cards
  ≤ 8, per its design), buttons ≥ 56 px tall. Nothing timed against the player; every motion honours
  `Kit.reducedMotion()`.
- **No streaks, no timed offers, no paid random items, nothing paid at all in this build.** `Config.GamePasses.DoubleCash`
  stays 0: the 2× Cash pass needs a rethink (OPEN #8, design §9), and anything paid needs both brothers' yes and the
  ownership note first (CLAUDE.md red lines 4 and 5).

## Performance budget
Full note (how to measure, the before/after table): `docs/plan/2026-11-16-perf-budget.md`.
- **60 fps on a mid phone** with 6 full plots and the belt. **≤ 400 parts per plot** at Lv 5 without creatures
  and decor (a Lv 5 plot with every room is 389). Decor adds up to 10 pieces of ≤ 25 parts each (DecorBuilder warns
  past it): about 500 for a fully decorated Lv 5 plot. The lead measures both in Studio (perf note).
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
| `ClinicKit.Plot` | The placeholder plot. It needs `Ground`, `Sign`/`SignGui`, `Counter`, the 3 markers and `Slots.RoomSlot_*` |
| `ClinicKit.Decor.<DecorId>` | The placeholder decor (4×4 footprint, pivot at the bottom centre) |
| `Creatures.<PatientId>` | The placeholder creature |
| `ClinicKit.Building<level>` *(depth)* (2-5) | The placeholder hospital building for that level. Pivot = the centre of the plot's Ground top, facing the street; it must hold `Bed_<n>` Parts for the level's Beds − 1, and must not cover the Counter, the line, the gate, the side walkways (\|x\| 11.9 to 14) or the room slots |
| `ClinicKit.NurseBelt` *(depth)* | The placeholder belt. It needs Parts `BeltStart`, `BeltEnd` and `Sign` (optional: `OddsGui` on the Sign, a `Riders` folder, a `Conveyor` part); pivot on the street at `Config.Town.Origin + Config.Belt.Offset`, +X along the belt |
| `Nurses.<NurseId>` *(depth)* | The placeholder nurse (a Model or MeshPart, face toward -Z; no cap is added) |

Anything missing or misnamed makes PlotBuilder fall back to its placeholder and print a `[PlotBuilder] ...` warning in
Output. A kit `Station_*` without an `IconGui` gets the placeholder's floating station icon. Kit models are cloned
into Workspace, so **they must contain no Scripts**: PlotBuilder, CreatureBuilder, DecorBuilder, NurseBuilder and
NurseBelt delete any they find (with a warning), but check before each publish anyway. They also remove Highlights
and turn off light shadows (the [performance budget](#performance-budget)). The brother's step-by-step version is
`docs/guides/build-the-clinic.md` (Part H covers the belt, nurses and buildings).

## Test it
### Lune specs (pure logic)
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
  - UTC midnight: `workspace:SetAttribute("UtcDay", workspace:GetAttribute("UtcDay") + 1)`. Daily, Story and Events
    all follow it (new visitor, a new goal, the mailbox opens). Setting it below the real day snaps back. This works
    in Studio only: live servers always use the real day.
  - Force Today's Visitor: `workspace:SetAttribute("TodaysVisitor", "CloudSheep")` (lasts until the day changes).
  - *(depth)* Every belt arrival one rarity: `workspace:SetAttribute("BeltForce", "Mythic")` (any of Common, Rare,
    Epic, Legendary, Mythic, Secret). The pity still wins over a forced Common, so `"Common"` gives 8 Commons then a
    Rare+ (checklist D9). Remove it after.
  - *(depth)* A Golden Hour now: `workspace:SetAttribute("ForceGolden", true)`. It runs for `Config.Belt.GoldenSeconds`
    and the attribute clears itself. (Without it, the first one comes 20 minutes after the server starts.)
  - *(depth)* Night Rush: `SkipPhase` into the night (above); the belt follows `IsNight`.
  - *(depth)* Every plot's building at one level: `workspace:SetAttribute("PreviewLevel", 5)`. Looks only (its beds
    work); slots, the line and recipes follow the real level and nothing is saved. Set it to nil to go back.
  - The next story day without touching `UtcDay`: set a regular's `LastBeatDay` back by 1 in the save.
  - With **Studio Access to API Services** on, a forward-set `UtcDay` is written into the real save
    (`LastGrantDay`, `Mailbox.LastSeenDay`, `HeartsGiven`, `VisitorDay`, a story's `LastBeatDay`). The next load
    pulls those days back to the real UTC day (`Schema.reconcile`), so the account isn't locked out, but it can
    still lose that day's mail or goal. A spare account, or API access off, is still the cleanest.
- **Feel check:** a cure gives sparkles, a pop, a chime and the NEW PAGE banner; in ⚙️, the ✨ switch turns to 💤
  and the effects calm down, and 🎵 turns to 🔇 and the music fades; `ForceWinter` brings snow; at night there are
  fireflies and the lamps and lanterns glow. *(depth)* 💰/⭐ roll up as coins fly from the patient, toasts slide in,
  the Golden Hour banner shows (no countdown), rarity frames shimmer, red dots hop, claim buttons breathe, the conveyor
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
  -- depth update
  print(R.TreatResult:InvokeServer(-1, { "Perfect" }))   -- not your session
  print(R.TreatResult:InvokeServer("1", "Perfect"))      -- wrong types
  print(R.HireNurse:InvokeServer(-1))                    -- no such rider
  print(R.HireNurse:InvokeServer(0 / 0))
  print(R.EquipNurse:InvokeServer("GoldieGryphlet", true)) -- not yours
  print(R.EquipNurse:InvokeServer({}, "yes"))
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
  rejoins. The OpenHelpers toggle works. A non-friend can't treat when it's closed.
- [ ] 12. Rejoin keeps everything. Junk remote calls are rejected.

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
- [ ] D0. Boot: `[Main] Clinic is open.`, no red errors; the belt stands east of the plaza, its sign shows the day
  odds, the conveyor stripes scroll.
- [ ] D1. An old save (no `Level`): loads at its implied level (a Garden owner is Lv 3), empty journal; `Version` 3
  on save.
- [ ] D2. Fresh save (`FreshSave`): the tutorial runs unchanged; patients have 1-item recipes; Treat opens a
  mini-game over the tutorial card; OK still cures; the HUD reveals 👩‍⚕️ with the rest at the end; no belt banner,
  combo sticker or celebration during it.
- [ ] D3. Each mini-game (Pour, Patch, Scrub, Cool) on PC and the phone emulator: rated OK/Good/Perfect; a Perfect
  pays a small tip and the combo counter climbs; ×1.2 at 3; a Good resets it. Look for `[MiniGames] ... broke` warns.
- [ ] D4. Lv 2: a Bath patient needs 🛁🧪; with a tray of 1 you give 🛁 (one game), the badge ticks, then 🧪. The
  guide arrow goes to the Counter while you carry 🧪 too.
- [ ] D5. Simple mode (⚙️): every game is one tap, rated Good, no tips.
- [ ] D6. Junk (the commands above): all `false` + a message, nothing changes. An early `TreatResult` is `true`,
  all OK, no tip.
- [ ] D7. The belt: a nurse every ~6 s, each takes ~30 s; prices scale with your level; Hire by tap and by prompt;
  a second player sees the same riders; the hired one hops off; a Common/Rare is replaced quickly.
- [ ] D8. Night (`SkipPhase`): the sign shows Night Rush odds; Mythic possible. Golden Hour (`ForceGolden`): a banner
  with the Secret chance and no countdown, Secret on the sign.
- [ ] D9. Pity: `BeltForce = "Common"` → the 9th arrival is Rare+.
- [ ] D10. Journal: silhouettes until seen (within 100 studs); NEW! on first seen and first hire; completion %;
  completing Commons gives 💰300 + Plaster Rug once.
- [ ] D11. Nurses at work: equip a Maker (items appear in the 🧺 tray, treating uses them), a Healer (treats the
  front patient with OK), a Cheerer (longer patience). Slots = level. Leave and rejoin: equipped nurses come back.
  With 💤 calm, Epic+ nurse sparkles stop.
- [ ] D12. Level up in the Shop's Hospital tab: celebration, the building grows (`PreviewLevel` to look at each),
  slots/beds/queue follow the table; the Garden needs Lv 3 (no "Buy in 🛒" toast or 🛒 dot for it before).
- [ ] D13. Juice: count-ups, flying coins, toasts slide, rarity frames shimmer, sounds; calm mode quiets all of it.
- [ ] D14. Perf: 6 full plots + belt on a mid phone ≈ 60 fps; Network receive stays low while creatures hop; fill
  in the measured columns of the perf note.
- [ ] D15. Owner leaves mid-game / mid-hire / with nurses: no errors, the plot is clean, the next joiner's prompts
  work; a helper leaving mid-game still lets the patient finish.

Write the results in `logs/playtests/`. The shop-sim checklist (first run 2026-11-16) is in git history.

## Before committing
```powershell
selene src
stylua --check src tests
lune run tests/run
```
