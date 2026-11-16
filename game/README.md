# game/: the Rojo project (Creature Clinic)

The Luau code for **Creature Clinic** (working title). Every player owns a clinic on a plot and cures silly, original
creatures. **Git owns the scripts and Studio owns the world.** Rojo syncs `src/` into Studio, while the brother's
models live in the place file (`ServerStorage.ClinicKit`, `ServerStorage.Creatures`).
- Design: `docs/plan/2026-11-16-creature-clinic-design.md`.
- Build plan and **contracts** (names, attributes, APIs): `docs/plan/2026-11-16-creature-clinic-build-plan.md` §B.
- The brother's building guide: `docs/guides/build-the-clinic.md`. Quick Words: `docs/guides/quick-words.md`.

## Run it (Joshua, Windows)
```powershell
cd games-agents\game
rokit install          # pinned rojo, selene, stylua and lune (rokit.toml); answer y to trust a new tool
rojo plugin install    # once
rojo serve             # then in Studio: Rojo plugin → Connect → Play
```
- **No kit models yet?** The server builds a placeholder town of 6 plots at `Config.Town.Origin` (0, 0, 300), each
  with a First-Aid Stand, so you can play right away. The brother's `Workspace.Shop` is never touched.
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
| `shared/Config.luau` | **Every tuning number**: pay, patience, queue, hold times, day and night length, the winter window, autosave, town layout, music, pass IDs |
| `shared/Types.luau` | The shared type names (`Data`, `Snapshot`, `Plot`, `Ctx`, ids) |
| `shared/Remotes.luau` | Creates `ReplicatedStorage.Remotes`. Server helpers: `serve` (rate limit plus pcall), `allow`, `toast`, `toastAll` |
| `shared/Signal.luau` | A small signal that passes tables **by reference** (used instead of BindableEvents) |
| `shared/Data/*.luau` | **Content**: `Ailments`, `Stations`, `Items`, `Patients`, `Regulars`, `Rooms`, `Upgrades`, `Decor`, `DailyGoals`, `Wings`, `Variants`. Keyed maps carry `.Order`, and everything is frozen |
| `shared/Logic/Schema.luau` | Save schema v2: `default()`, `reconcile(saved, today?)` (migrates v1 shop saves, pulls future days back to today), `isNewer(saved)` |
| `shared/Logic/Pay.luau` | Cash and ⭐ for a cure |
| `shared/Logic/Prices.luau` | Upgrade prices, hold time, tray capacity, patience |
| `shared/Logic/Progress.luau` | Can this room be bought, and what's the next goal |
| `shared/Logic/Book.luau` | Patient Book stamps and set completion |
| `shared/Logic/Story.luau` | Regulars: who's unlocked, whether a beat is due today, advancing a beat |
| `shared/Logic/Daily.luau` | UTC day, Today's Visitor, banked goals, mailbox |

`Logic/*` is **pure**: no Roblox services and no requires, so Lune can test it. The server passes `Config` in as
`cfg`.

### Server
| File | Does |
|---|---|
| `server/Main.server.luau` | Collision groups, then every system's `start()` in order ([Boot order](#boot-order)) |
| `server/PlayerData.luau` | Loads and saves v2 with `UpdateAsync` under a session lock (a join waits out another server's lock until its lease ends), migrates `PlayerData_v1`, never saves after a failed load or over a newer-version save (`DataOk = false` plus a toast), autosaves, saves on leave (retried with backoff) and in `BindToClose`. Leaderstats `Cash` and `Stars` |
| `server/State.luau` | Builds each player's Snapshot, pushes it (debounced) and answers `GetState` |
| `server/Events.luau` | Winter: `Config.Winter` dates or the `ForceWinter` Workspace attribute → `Workspace.IsWinter` |
| `server/Plots.luau` | Assigns a plot once data loads, frees it on leave, rebuilds rooms and decor from the save, `canWork` (owner, friend or `OpenHelpers`), `unlockRoom`, `placeDecor` |
| `server/PlotBuilder.luau` | Builds the town, the plots and placeholder rooms, or clones the brother's `ServerStorage.ClinicKit` models. Night lamps (tag `ClinicNightLight`) |
| `server/Carry.luau` | What each player is carrying (`Carry`, `CarryMax` attributes) and the icon above their head |
| `server/Economy.luau` | Cash, upgrades and purchases. Wires `Purchase` and `PlaceDecor` |
| `server/Progress.luau` | Clinic ⭐ Stars and the next goal |
| `server/Book.luau` | Stamps the Patient Book and grants a wing's set reward |
| `server/Story.luau` | The three regulars: who's due, their speech bubble, the reward when a story ends |
| `server/Daily.luau` | `Workspace.UtcDay` and `TodaysVisitor`, banked daily goals, the mailbox. Wires `ClaimGoal` and `ClaimMailbox` |
| `server/DayReport.luau` | Counts each player's cures and new pages, and sends the Day Report when night ends |
| `server/DayNight.luau` | The day/night cycle (`IsNight`, `PhaseEndsAt`) and softer night lighting |
| `server/Stations.luau` | A hold-to-make prompt on every `Station_*`, with the hold time checked on the server |
| `server/Patients.luau` | A queue per plot, the `Treat` prompt on the Counter, beds, patience, night patients, variants, visitors and regulars |
| `server/CreatureBuilder.luau` | A creature Model from its `Look`, or a clone of `ServerStorage.Creatures.<PatientId>` |
| `server/Cure.luau` | One cure, in order: pay, cash, ⭐, Book, daily goals, story, Day Report, then the `Cured` remote |
| `server/DecorBuilder.luau` | A decor Model from its `Look`, or a clone of `ServerStorage.ClinicKit.Decor.<DecorId>` |
| `server/Visits.luau` | Hearts on the sign (once per owner per UTC day), the owner's `OpenHelpers` toggle, the friend referral reward |

### Client
| File | Does |
|---|---|
| `client/Main.client.luau` | Builds `ctx` (Remotes, Config, Data, State, `onState`, `toast`, `on`/`fire`), then loads each UI and Feel module in a pcall and calls `init(ctx)` |
| `client/UI/Theme.luau` · `client/UI/Kit.luau` | The look tokens, and building blocks (panel, button with press bounce, label...). Libraries, not inited |
| `client/UI/Toasts.luau` | The toast stack at the top centre |
| `client/UI/Hud.luau` | Cash, ⭐ with a bar to the next unlock, carried items, the day/night timer, and the big 🛒 📖 📬 🎯 buttons |
| `client/UI/Shop.luau` | Upgrades, Rooms and Decor tabs, plus decor place mode |
| `client/UI/BookPanel.luau` | The Patient Book: cards by wing, silhouettes for patients not yet seen |
| `client/UI/DayReportPanel.luau` | The end-of-night pop-up |
| `client/UI/Mailbox.luau` | The daily gift and the goals list |
| `client/UI/Guide.luau` | The first-cures arrow: to the right station, then to the Counter. Also sets each station prompt's hold time from your own Faster Hands level |
| `client/UI/PromptFilter.luau` | Hides world prompts that aren't for you: the helpers switch for visitors, "Send a heart" for the owner, and the Make and Treat prompts on clinics you can't work at (the server still checks) |
| `client/Feel/Sounds.luau` | One table of built-in `rbxasset://` sound cues; any module plays one with `ctx.fire("Sound", name)` |
| `client/Feel/CureFX.luau` | Cure sparkles, the "💰 +n" / "⭐ +n" pop, the NEW PAGE banner, new-room and placed-decor celebrations, hearts on your sign |
| `client/Feel/Atmosphere.luau` | Snow while `IsWinter`, fireflies at night, gentle decor sway, the ✨/💤 calm-effects button |
| `client/Music.client.luau` | Background music (`Config.Music`), day and night playlists, the 🎵 mute button next to ✨ |
| `client/RoofFade.client.luau` | Fades a Model named `Roof` inside the old `Workspace.Shop` while you're inside it |

### Tests
| File | Does |
|---|---|
| `tests/run.luau` | Runs every `tests/*.spec.luau`, prints PASS/FAIL and exits 1 on any failure |
| `tests/expect.luau` | `test(name, fn)` and `expect(x).toBe(y)`, `.toEqual(t)` (deep) and `.toBeTruthy()` |
| `tests/*.spec.luau` | `Schema`, `Data`, `Pay`, `Prices`, `Progress`, `Book`, `Story`, `Daily` |

## Boot order
**Server (`Main.server.luau`):**
1. `Remotes` is required first, so every remote exists before anything else runs.
2. The collision groups `Patients` and `Players` are set up. Patients walk through players and each other.
3. Then `start()`, in this order: `PlayerData` → `State` → `Events` → `Plots` → `Carry` → `Economy` → `Progress` →
   `Book` → `Story` → `Daily` → `DayReport` → `Stations` → `Patients` → `Visits` → `DayNight`.
   - `Plots.start()` builds the whole town (`PlotBuilder.buildTown`), with a `Room_Stand` on every plot, before
     `Stations` and `Patients` start.
   - `CreatureBuilder`, `DecorBuilder` and `Cure` are libraries that other systems require, so they're not in the
     list.
   - Each `start()` runs in `xpcall`. One that errors prints `[Main] <Name>.start() failed` and the rest still start.
4. It prints `[Main] Clinic is open.`

**Client (`Main.client.luau`):** waits for `game.Loaded` and builds `ctx`. Then it loads `UI.Toasts`, `Hud`, `Shop`,
`BookPanel`, `DayReportPanel`, `Mailbox`, `Guide` and `PromptFilter`, then `Feel.Sounds`, `CureFX` and `Atmosphere`. Each one is
loaded in its own pcall, and its `init(ctx)` runs. A missing or broken module warns `[Client] ...` and is skipped.
`Music.client` and `RoofFade.client` are separate LocalScripts.

## The loop
A patient walks in and queues at `QueueStart`, with its ailment icon and a patience ring → you **hold at the matching
`Station_*`** to make the item (🧪 Potion, 🩹 Plaster, 🧼 Bubbles, ☕ Cocoa) → you carry it → you **Treat at the
Counter** → the patient goes to a free `Bed_*` (or recovers in place) → `Cure.resolve`: cash, ⭐, a Book stamp, goal
progress, a story beat → a happy hop, and it leaves. A wrong item gets a head-shake and a hint. Running out of
patience is a sad puff, with no penalty.

## Rules the code keeps
- **The server owns all data and money.** Every RemoteFunction is wired with `Remotes.serve` (10 calls/s per player
  per remote, plus pcall) and checks types, ids, ownership and permission. The client only asks.
- **Change the save only through `PlayerData.update(p, fn)`.** `get()` is read-only.
- **Contracts are law.** Instance names, attributes and APIs are in the build plan §B. The brother's kit follows the
  same names (`docs/guides/build-the-clinic.md`).
- **Rated Minimal, no reading needed, mobile-first.** Icons and colour first, any words ≤ 6, buttons ≥ 56 px tall.
- **No streaks, no timed offers, no paid random items, nothing paid at all in this build.** `Config.GamePasses.DoubleCash`
  stays 0: the 2× Cash pass needs a rethink (OPEN #8, design §9), and anything paid needs both brothers' yes and the
  ownership note first (CLAUDE.md red lines 4 and 5).

## The brother's kit (`ServerStorage`, in the place file, not git)
| Put a Model here | And the game uses it instead of |
|---|---|
| `ClinicKit.Stand`, `.BathRoom`, `.Ward`, `.WinterWing`, `.Garden` | The placeholder room. It needs a `Floor` Part plus its `Station_*`, `Bed_<n>` and `DecorSlot_<n>` parts |
| `ClinicKit.Plot` | The placeholder plot. It needs `Ground`, `Sign`/`SignGui`, `Counter`, the 3 markers and `Slots.RoomSlot_*` |
| `ClinicKit.Decor.<DecorId>` | The placeholder decor (4×4 footprint, pivot at the bottom centre) |
| `Creatures.<PatientId>` | The placeholder creature |

Anything missing or misnamed makes PlotBuilder fall back to its placeholder and print a `[PlotBuilder] ...` warning in
Output. A kit `Station_*` without an `IconGui` gets the placeholder's floating station icon. Kit models are cloned
into Workspace, so **they must contain no Scripts**: PlotBuilder, CreatureBuilder and DecorBuilder delete any they
find (with a warning), but check before each publish anyway.

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
  - Winter: `workspace:SetAttribute("ForceWinter", true)`.
  - End the current day or night now: `workspace:SetAttribute("SkipPhase", true)` (twice = a whole clinic day, so
    the Day Report pops). Or shorten `Config.DaySeconds` and `Config.NightSeconds`.
  - UTC midnight: `workspace:SetAttribute("UtcDay", workspace:GetAttribute("UtcDay") + 1)`. Daily, Story and Events
    all follow it (new visitor, a new goal, the mailbox opens). Setting it below the real day snaps back. This works
    in Studio only: live servers always use the real day.
  - Force Today's Visitor: `workspace:SetAttribute("TodaysVisitor", "CloudSheep")` (lasts until the day changes).
  - The next story day without touching `UtcDay`: set a regular's `LastBeatDay` back by 1 in the save.
  - With **Studio Access to API Services** on, a forward-set `UtcDay` is written into the real save
    (`LastGrantDay`, `Mailbox.LastSeenDay`, `HeartsGiven`, `VisitorDay`, a story's `LastBeatDay`). The next load
    pulls those days back to the real UTC day (`Schema.reconcile`), so the account isn't locked out, but it can
    still lose that day's mail or goal. A spare account, or API access off, is still the cleanest.
- **Feel check:** a cure gives sparkles, a pop, a chime and the NEW PAGE banner; the ✨ button turns to 💤 and the
  effects calm down; `ForceWinter` brings snow; at night there are fireflies and the lamps and lanterns glow.
- **Junk remote calls**, from the client command bar. Each must return `false` plus a message and change nothing:
  ```lua
  local R = game.ReplicatedStorage.Remotes
  print(R.Purchase:InvokeServer("Room", 123))
  print(R.Purchase:InvokeServer("Room", "Garden"))       -- not enough ⭐ or cash
  print(R.PlaceDecor:InvokeServer("Stand:9", "CozyRug")) -- no such slot, or not owned
  print(R.ClaimGoal:InvokeServer(-1))
  ```

## Playtest checklist (build plan §D)
- [ ] 1. Output shows `[Main] Clinic is open.` and no red errors. The town shows 6 plots, you get one, and its sign
  shows your name.
- [ ] 2. The first patient arrives within 60 s with an icon. The guide arrow points to the station. Hold → carry icon →
  the arrow points to the Counter → Treat → bed → cured → cash and ⭐, with sparkle and chime.
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

Write the results in `logs/playtests/`. The shop-sim checklist (first run 2026-11-16) is in git history.

## Before committing
```powershell
selene src
stylua --check src
lune run tests/run
```
