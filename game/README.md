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
| `shared/Config.luau` | **Every tuning number**: pay, patience, queue, hold times, day and night length, the winter window, autosave, town layout, music, pass IDs. Also who's an admin: `AdminUserIds`, `AdminNames` ([Admin panel](#admin-panel)), and the `Leaderboards` timings and board lists ([Leaderboards](#leaderboards)) |
| `shared/Palette.luau` | The candy-pop colours and fonts shared by the world and the UI (`memory-20261116-007`). Change colours here |
| `shared/Types.luau` | The shared type names (`Data`, `Snapshot`, `Plot`, `Ctx`, ids) |
| `shared/Remotes.luau` | Creates `ReplicatedStorage.Remotes` (incl. `TutorialAck`, `Admin` and `GetBoards`). Server helpers: `serve` (rate limit plus pcall), `allow`, `toast` (always shown: replies and warnings), `news` (ambient news, held back while the player is quiet), `toastAll` (skips quiet players), `setQuiet`/`isQuiet` (Server/Tutorial makes a player in the tutorial quiet) |
| `shared/Signal.luau` | A small signal that passes tables **by reference** (used instead of BindableEvents) |
| `shared/Data/*.luau` | **Content**: `Ailments`, `Stations`, `Items`, `Patients`, `Regulars`, `Rooms`, `Upgrades`, `Decor`, `DailyGoals`, `Wings`, `Variants`. Keyed maps carry `.Order`, and everything is frozen |
| `shared/Logic/Schema.luau` | Save schema v2: `default()`, `reconcile(saved, today?)` (migrates v1 shop saves, pulls future days back to today, gives a save without `Tutorial` its step: any cure means done), `isNewer(saved)`. `WeekCures` = { Week, Count } for the weekly leaderboard |
| `shared/Logic/Tutorial.luau` | The first-session tutorial's rules: the steps (1 welcome .. 8 Book, 9 done), `advance(step, event)`, `resume` after a rejoin, who Patients may send (`spawnPlan`, `queueCap`), the shop top-up (`cheapest`, `topUp`) |
| `shared/Logic/Pay.luau` | Cash and ⭐ for a cure |
| `shared/Logic/Prices.luau` | Upgrade prices, hold time, tray capacity, patience |
| `shared/Logic/Progress.luau` | Can this room be bought, and what's the next goal |
| `shared/Logic/Book.luau` | Patient Book stamps and set completion |
| `shared/Logic/Story.luau` | Regulars: who's unlocked, whether a beat is due today, advancing a beat |
| `shared/Logic/Daily.luau` | UTC day, Today's Visitor, banked goals, mailbox |
| `shared/Logic/Leaderboard.luau` | The leaderboards' rules ([Leaderboards](#leaderboards)): the boards, the UTC week, store names, a player's values from their save, what changed since the last write, backoff, permanent errors, the live merge and rank, admin exclusion |
| `shared/Logic/Admin.luau` | The admin panel's rules: who is an admin, the fixed action list and the argument each takes, the alone-in-server rule ([Admin panel](#admin-panel)) |

`Logic/*` is **pure**: no Roblox services and no requires, so Lune can test it. The server passes `Config` in as
`cfg`.

### Server
| File | Does |
|---|---|
| `server/Main.server.luau` | Collision groups, then every system's `start()` in order ([Boot order](#boot-order)) |
| `server/PlayerData.luau` | Loads and saves v2 with `UpdateAsync` under a session lock (a join waits out another server's lock until its lease ends), migrates `PlayerData_v1`, never saves after a failed load or over a newer-version save (`DataOk = false` plus a toast), autosaves, saves on leave (retried with backoff) and in `BindToClose`. Leaderstats `Cash` and `Stars`. The Studio-only `FreshSave` switch ([Test switches](#studio-rojo-connected)) |
| `server/State.luau` | Builds each player's Snapshot (incl. `Tutorial`, the step, and `TutorialCures`), pushes it (debounced) and answers `GetState` |
| `server/Tutorial.luau` | The first-session tutorial ([below](#the-first-session-tutorial)): the saved step, moved on only by real server events, the one-time shop top-up, `TutorialAck`, and the quiet toasts while it runs |
| `server/Events.luau` | Winter: `Config.Winter` dates or the `ForceWinter` Workspace attribute → `Workspace.IsWinter` |
| `server/Plots.luau` | Assigns a plot once data loads, frees it on leave, rebuilds rooms and decor from the save, `canWork` (owner, friend or `OpenHelpers`), `unlockRoom`, `placeDecor`. Owners (re)spawn in front of the Counter, beside the line, facing the clinic |
| `server/PlotBuilder.luau` | Builds the town, the plots and placeholder rooms, or clones the brother's `ServerStorage.ClinicKit` models. Night lamps (tag `ClinicNightLight`). Station icons and for-sale boards stop growing up close (`DistanceLowerLimit`) |
| `server/Carry.luau` | What each player is carrying (`Carry`, `CarryMax` attributes) and the icon above their head |
| `server/Economy.luau` | Cash, upgrades and purchases. Wires `Purchase` and `PlaceDecor` |
| `server/Progress.luau` | Clinic ⭐ Stars and the next goal |
| `server/Book.luau` | Stamps the Patient Book and grants a wing's set reward |
| `server/Story.luau` | The three regulars: who's due, their speech bubble, the reward when a story ends |
| `server/Daily.luau` | `Workspace.UtcDay` and `TodaysVisitor`, banked daily goals, the mailbox. Wires `ClaimGoal` and `ClaimMailbox` |
| `server/DayReport.luau` | Counts each player's cures and new pages, and sends the Day Report when night ends |
| `server/DayNight.luau` | The day/night cycle (`IsNight`, `PhaseEndsAt`) and the candy-pop lighting grade (the `CandyColor` ColorCorrection, Atmosphere, Bloom), set from code by day and by night |
| `server/Stations.luau` | A hold-to-make prompt on every `Station_*`, with the hold time checked on the server |
| `server/Patients.luau` | A queue per plot, the `Treat` prompt on the Counter, beds, patience, night patients, variants, visitors and regulars. During an owner's tutorial: its two patients, one at a time, no patience running out (steps 1-6), no regulars or visitor |
| `server/CreatureBuilder.luau` | A creature Model from its `Look`, or a clone of `ServerStorage.Creatures.<PatientId>`. The badge and bubble stop growing up close (`DistanceLowerLimit`) |
| `server/Cure.luau` | One cure, in order: pay, cash (with `Cured` and this UTC week's `WeekCures`), ⭐, Book, daily goals, story, Day Report, the `Cured` remote, then the owner's tutorial |
| `server/DecorBuilder.luau` | A decor Model from its `Look`, or a clone of `ServerStorage.ClinicKit.Decor.<DecorId>` |
| `server/Visits.luau` | Hearts on the sign (once per owner per UTC day), the owner's `OpenHelpers` toggle, the friend referral reward |
| `server/Leaderboards.luau` | The global leaderboards ([Leaderboards](#leaderboards)): throttled OrderedDataStore writes from the server's save, cached reads every 2 minutes, DisplayName lookups, admins kept off, the `GetBoards` remote, the plaza boards' contents |
| `server/BoardBuilder.luau` | Builds the plaza leaderboards (`Workspace.TownBoards`, the "🏆 Top Doctors" gantry west of the plaza) and draws their rows. A library `Leaderboards` uses |
| `server/Admin.luau` | The 🛠️ Admin panel's server side ([Admin panel](#admin-panel)): decides who is an admin (sets the `IsAdmin` player attribute), looks up `Config.AdminNames` at startup, and wires the `Admin` remote: re-checks admin on every call, validates the action and its argument, logs `[Admin] <name> <action>`, then calls the systems' own APIs. Admin-only hooks it uses: `Tutorial.finish`/`restart`, `Patients.sendNext`/`reopen`, `Book.completeAll`, `Story.makeDue`, `Daily.resetToday` |

### Client
| File | Does |
|---|---|
| `client/Main.client.luau` | Builds `ctx` (Remotes, Config, Data, State, `onState`, `toast`, `on`/`fire`), then loads each UI and Feel module in a pcall and calls `init(ctx)` |
| `client/UI/Theme.luau` · `client/UI/Kit.luau` | The look tokens, and building blocks (panel, button with press bounce, label...). Libraries, not inited |
| `client/UI/Toasts.luau` | The toast stack at the top centre |
| `client/UI/Hud.luau` | Cash, ⭐ with a bar to the next unlock, what you hold (nothing when your hands are empty), the day/night timer, the big 🛒 📖 📬 🎯 🏆 buttons, and ⚙️ settings (the 🎵 music and ✨ calm-effects switches, plus 🛠️ Admin for admins only). A new player's HUD reveals itself with the tutorial step; everyone else sees it all |
| `client/UI/Shop.luau` | Upgrades, Rooms and Decor tabs, plus decor place mode |
| `client/UI/BookPanel.luau` | The Patient Book: cards by wing, silhouettes for patients not yet seen |
| `client/UI/DayReportPanel.luau` | The end-of-night pop-up (never during the tutorial) |
| `client/UI/Mailbox.luau` | The daily gift and the goals list. The letter pops once a session, never over a panel, and after the tutorial ends |
| `client/UI/Guide.luau` | The first-cures arrow: to the right station, then to the Counter (the tutorial steers it with `Guide.setSteer`). Also sets each station prompt's hold time from your own Faster Hands level |
| `client/UI/Tutorial.luau` | The tutorial's step card, its pointer, the welcome title card and the first-join camera sweep; turns the camera to your clinic when you arrive |
| `client/UI/PromptFilter.luau` | Hides world prompts that aren't for you: the helpers switch for visitors, "Send a heart" for the owner, and the Make and Treat prompts on clinics you can't work at (the server still checks) |
| `client/UI/Boards.luau` | The 🏆 leaderboards panel: a tab per board, the top 10, and your own bar ("You: #12"), from `GetBoards` |
| `client/UI/AdminPanel.luau` | The 🛠️ Admin panel ([Admin panel](#admin-panel)): buttons only, each one asks the `Admin` remote and toasts the reply; a second page picks a patient to spawn |
| `client/Feel/Sounds.luau` | One table of built-in `rbxasset://` sound cues; any module plays one with `ctx.fire("Sound", name)` |
| `client/Feel/CureFX.luau` | Cure sparkles, the "💰 +n" / "⭐ +n" pop, the NEW PAGE banner, new-room and placed-decor celebrations, hearts on your sign |
| `client/Feel/Atmosphere.luau` | Snow while `IsWinter`, fireflies at night, gentle decor sway, the calm-effects setting (`ReduceEffects`; its switch is in the HUD's ⚙️) |
| `client/Music.client.luau` | Background music (`Config.Music`), day and night playlists, muted by `MusicMuted` (its switch is in the HUD's ⚙️) |

### Tests
| File | Does |
|---|---|
| `tests/run.luau` | Runs every `tests/*.spec.luau`, prints PASS/FAIL and exits 1 on any failure |
| `tests/expect.luau` | `test(name, fn)` and `expect(x).toBe(y)`, `.toEqual(t)` (deep) and `.toBeTruthy()` |
| `tests/*.spec.luau` | `Schema`, `Data`, `Pay`, `Prices`, `Progress`, `Book`, `Story`, `Daily`, `Tutorial`, `Admin`, `Leaderboard` |

## Boot order
**Server (`Main.server.luau`):**
1. `Remotes` is required first, so every remote exists before anything else runs.
2. The collision groups `Patients` and `Players` are set up. Patients walk through players and each other.
3. Then `start()`, in this order: `PlayerData` → `State` → `Events` → `Plots` → `Carry` → `Economy` → `Progress` →
   `Book` → `Story` → `Daily` → `DayReport` → `Tutorial` → `Stations` → `Patients` → `Visits` → `Leaderboards` →
   `DayNight` → `Admin`.
   - `Tutorial` starts before `Stations` and `Patients`, so its quiet toasts and listeners are set before any
     patient comes. `Stations`, `Patients` and `Cure` call its hooks; it requires none of them.
   - `Plots.start()` builds the whole town (`PlotBuilder.buildTown`), with a `Room_Stand` on every plot, before
     `Stations` and `Patients` start.
   - `CreatureBuilder`, `DecorBuilder`, `BoardBuilder` and `Cure` are libraries that other systems require, so
     they're not in the list.
   - `Leaderboards` starts after `Plots` (it reads the built town to place its boards).
   - `Admin` starts last: its remote calls into the systems above.
   - Each `start()` runs in `xpcall`. One that errors prints `[Main] <Name>.start() failed` and the rest still start.
4. It prints `[Main] Clinic is open.`

**Client (`Main.client.luau`):** waits for `game.Loaded` and builds `ctx`. Then it loads `UI.Toasts`, `Hud`, `Shop`,
`BookPanel`, `DayReportPanel`, `Mailbox`, `Guide`, `PromptFilter`, `AdminPanel`, `Boards` and `Tutorial`, then
`Feel.Sounds`,
`CureFX` and `Atmosphere`. Each one is loaded in its own pcall, and its `init(ctx)` runs. A missing or broken module
warns `[Client] ...` and is skipped. `Music.client` and `RoofFade.client` are separate LocalScripts. Until the
server's first snapshot arrives, `ctx.State.Tutorial` is 0 ("not known yet"), so the HUD starts calm (only 💰).

## The loop
A patient walks in and queues at `QueueStart`, with its ailment icon and a patience ring → you **hold at the matching
`Station_*`** to make the item (🧪 Potion, 🩹 Plaster, 🧼 Bubbles, ☕ Cocoa) → you carry it → you **Treat at the
Counter** → the patient goes to a free `Bed_*` (or recovers in place) → `Cure.resolve`: cash, ⭐, a Book stamp, goal
progress, a story beat → a happy hop, and it leaves. A wrong item gets a head-shake and a hint. Running out of
patience is a sad puff, with no penalty.

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
- **No skip button.** The HUD reveals itself with the step (see `client/UI/Hud.luau`). Only admins can jump it, from
  the [Admin panel](#admin-panel).

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

An admin gets the player attribute `IsAdmin = true`, and the ⚙️ Settings panel then shows a **🛠️ Admin** button. The
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
| 🤧 Spawn patient… | `SpawnPatient` (a `Data/Patients` id) | a page of every patient: tap one and it's next in your own line, once there's room (up to 4 wait; it needs its station on your plot) |
| ✅ Finish | `FinishTutorial` | the tutorial is done (step 9) |
| 🔄 Restart | `RestartTutorial` | empties your line, back to the welcome card, and respawns you so the title card and sweep play |
| 🌙 Night · ☀️ Day | `SkipToNight` · `SkipToDay` | the whole server: ends the current phase now (`SkipPhase`); day after night sends the Day Report |
| ❄️ Winter on/off | `ToggleWinter` | the whole server: toggles `ForceWinter` (off still leaves winter inside `Config.Winter`'s dates) |

- **The alone-in-server rule.** Night, day and winter change everyone's game, so they work only when the admin is
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
`tests/Leaderboard.spec.luau`), the plaza boards in `server/BoardBuilder.luau`, and the 🏆 panel in
`client/UI/Boards.luau`. Tuning in `Config.Leaderboards`.

| Board | Value (from the server's save) | OrderedDataStore (key = `tostring(UserId)`) |
|---|---|---|
| 🏥 Most Cured | `Data.Cured`, all time | `Board_Cured_v1` |
| ⭐ Most Stars | `Data.Stars`, all time | `Board_Stars_v1` |
| ❤️ Most Hearts | `Data.HeartsReceived`, all time | `Board_Hearts_v1` |
| 🏆 Cures This Week | `Data.WeekCures.Count` for this UTC week | `Board_Week_v1_w<week>`: a new store every Monday 00:00 UTC, so it starts empty |

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

**Where the plaza boards stand.** `Workspace.TownBoards`, rebuilt at every server start: a candy-pop gantry, "🏆 Top
Doctors", spanning the street just **west** of the plaza, at `Config.Town.Origin.X - 26` (the plaza's radius 17 + 9).
Two white posts stand on the curbs (z = ±16.9 from the street's centre line); the four boards (🏥 ⭐ ❤️ 🏆, left to
right as seen from the plaza) hang from a pink beam with their bottoms 7.5 studs up, so players walk under them, and
face the plaza and the `TownSpawn` (east); the back shows the same boards for players coming from the west plots.
The street and plaza sizes are read from the built `ClinicTown`, so the gantry follows PlotBuilder's layout. It
clears the plots (fences at z = ±18.4), the middle plots' gates, signs and mailboxes (x within ±13), the plaza's
benches, lamps and planters (within 17 of the centre), the street lamps (x = ±39) and the arches (the street's ends).
**The plaza's east side is left free for the Nurse Belt.**

**Testing it.**
- Studio, API access **off**: Play. No red errors; the gantry stands west of the spawn saying "Leaderboards open when
  the game is live"; 🏆 Top (after the tutorial) shows the same with your values.
- Studio, API access **on** (it writes the live boards from your real save): Play, cure a few. Within ~5 s your row is
  on the plaza boards and in 🏆 ("You: #n"). After 75-150 s, or on Stop, Output shows no `[Leaderboards] Couldn't
  write`. The next Play reads the boards back.
- Live: an admin account (JokingPuzzle, Dandlepeeps) never appears, and its bar says "🛠️ Admins aren't ranked"; a
  second, non-admin account appears after its first cure.
- Junk: `game.ReplicatedStorage.Remotes.GetBoards:InvokeServer()` spammed from the command bar returns `nil` past 10
  calls a second and never costs a DataStore request.

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
  - The next story day without touching `UtcDay`: set a regular's `LastBeatDay` back by 1 in the save.
  - With **Studio Access to API Services** on, a forward-set `UtcDay` is written into the real save
    (`LastGrantDay`, `Mailbox.LastSeenDay`, `HeartsGiven`, `VisitorDay`, a story's `LastBeatDay`). The next load
    pulls those days back to the real UTC day (`Schema.reconcile`), so the account isn't locked out, but it can
    still lose that day's mail or goal. A spare account, or API access off, is still the cleanest.
- **Feel check:** a cure gives sparkles, a pop, a chime and the NEW PAGE banner; in ⚙️, the ✨ switch turns to 💤
  and the effects calm down, and 🎵 turns to 🔇 and the music fades; `ForceWinter` brings snow; at night there are
  fireflies and the lamps and lanterns glow.
- **Junk remote calls**, from the client command bar. Each must return `false` plus a message and change nothing:
  ```lua
  local R = game.ReplicatedStorage.Remotes
  print(R.Purchase:InvokeServer("Room", 123))
  print(R.Purchase:InvokeServer("Room", "Garden"))       -- not enough ⭐ or cash
  print(R.PlaceDecor:InvokeServer("Stand:9", "CozyRug")) -- no such slot, or not owned
  print(R.ClaimGoal:InvokeServer(-1))
  print(R.TutorialAck:InvokeServer(8))                  -- only ever moves the welcome card (step 1) on
  ```

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
- [ ] 13. Leaderboards: the 🏆 Top Doctors gantry stands west of the plaza, clear of the street lamps, signs and
  gates, readable from the spawn and at night. 🏆 Top opens the panel: each tab shows its board, your bar shows "You:
  #n" (or "Play to join in!"). A cure moves your number within a few seconds. Admins aren't on any board
  ([Leaderboards](#leaderboards)).

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
stylua --check src tests
lune run tests/run
```
