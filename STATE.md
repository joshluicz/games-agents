# State

> Live state first, narrative second. New entries go at the **top** of `## Recent sessions`.

## Phase
**Stage 0: Creature Clinic, private build** (2026-11-16). The concept moved from the shop sim to a creature clinic on
your own plot (`memory-20261116-003` to `-006`). Design: `docs/plan/2026-11-16-creature-clinic-design.md`. Build plan
and contracts: `docs/plan/2026-11-16-creature-clinic-build-plan.md`. Slices 1-2 are built, merged and ran in Studio
(`logs/playtests/2026-11-16-clinic-first-studio-run.md`). Winter build private and playtested by about 7 Dec.

## Setup status (2026-11-16, Joshua's PC)
- ✅ Place **Shop Co-Op [WIP]** (placeId 112965897544918, universe 10777060712) is owned by JokingPuzzle, with Team
  Create on and Studio API access on. Max visitors set to 6 (Joshua, Creator Hub).
- ✅ The brother (Dandlepeeps) is a collaborator with Edit and a Trusted Friend, and has been inside the place.
- ✅ Rokit 1.2.0 with Rojo 7.7.1, selene 0.32.0, StyLua 2.6.0 and Lune 0.11.1 (`game/rokit.toml`). `rojo serve`
  (port 34872) syncs this checkout's `game/` into Studio.
- ✅ Claude Code ↔ Studio MCP connected (user scope).

## Next actions
**Live and PUBLIC (16+) since 2026-11-16 (Joshua):** the tutorial build + player-sized patients, admin panel, Throw away
(`af773f8`). 60-day window for 250 engaged 16+ plays has started. Marketing push **with the depth update** (Update 1).
- [x] **Joshua:** published Update 1 (2026-11-16). His verdict: "pretty shit". That feedback became the look overhaul.
- [x] **Claude:** Progression v2 merged (`c9e4d1c`, 1000 specs). The Studio run checked its systems through remotes
      (`logs/playtests/2026-11-17-progression-v2-studio.md`). Not published: it ships together with the overhaul.
- [x] **Claude:** the look overhaul is built, merged, run in Studio and fixed (2026-11-17,
      `logs/playtests/2026-11-17-look-overhaul.md`).
      - Done: relight, studs on every face, the belt in the road's centre, a multi-storey hospital with lit wards,
        HUD side rails, navy panels, the tutorial floor beam with Skip and Replay, blocky creatures.
      - 1439 specs pass.
      - Progression v2 ships with it.
- [ ] **Joshua + brother:** play it in Studio (or a private server), then **both say yes** before publishing (red
      line 4). Pick the First-Aid Stand icon and Golden Hour's icon (`2026-11-17-look-overhaul.md`, "Still open").
- [ ] **Claude, next:**
      - the beam's arrow texture (needs one uploaded image);
      - a phone check in the Device Simulator;
      - the lift, triage and Market (2 players) seen by eye;
      - the small UI polish listed in the log.
- [ ] **Joshua:** Performance Stats (FPS, ping) on PC + phone from the live game, for the lag.
- [ ] **Brother:** play as a new player and with 🛠️ Admin; notes into `logs/playtests/`.
- [ ] **Joshua:** Creator Hub: maturity questionnaire done? New icon + thumbnails (`docs/launch/images/`).
- [ ] **Joshua:** the 1,000-Robux all-ages fee (OPEN #4); how many 16+ players he can ask (OPEN #6).
- [ ] **Claude, after the depth update:** marketing kit (clip scripts, a message for friends, an ads test plan later).
- [ ] **Later update:** the 2× Cash pass (`-006`).

## Blocked on
- Nothing for the private build. Going public waits on the ownership note (OPEN #2) and a yes from both.

## Who's doing what
Joshua: code, accounts, money · Brother: world, feel, players (`context/team.md`).

## Recent sessions
- **2026-11-17 (Joshua's PC, Claude + workflows, Joshua away). Progression v2, the Market fix and the look overhaul,
  all merged and run in Studio.**
  - **Progression v2** merged (`c9e4d1c`). Its Fable review led to the Market save fix (`3bf1fc3`): a sold nurse can't
    vanish when a save fails mid-trade.
  - **The look overhaul** came from Joshua's "pretty shit" feedback and rulings `-001` to `-004`:
    - 14 agents, with Fable on the foundation, the integrator, the reviews and the fixer;
    - 9 review bugs fixed;
    - merged as `541fbc5`.
  - **The Studio run** found three problems, all fixed:
    - walls without texture: studs now go on the side faces too, with no assets;
    - black wards from the street: room lights plus lighter glass;
    - DayNight boot warnings.
  - **Note for Studio MCP:** captures show a white 3D view when Studio is **minimised**. Restore the window.
- **2026-11-16 (evening, Joshua's PC, Claude + parallel agents). Update 1 merged and playtested.**
  - **Merged:**
    - creatures v2;
    - leaderboards (admins excluded; now a 🏆 Hall of Fame garden off the street's west end, `0c7b803`);
    - playtime gifts, boosts and tiered badges (`-015`, `-016`);
    - the hands disc with a red ✖ Discard;
    - the gift progress bar;
    - MaxQueue 3;
    - plot polish (`3381eae`, `ad9638d`): queue pavement with numbered spots, the raised sign, the helpers switch
      moved into ⚙️ Settings (`SetHelpers`), a smaller heart prompt.
  - **The depth workflow** (12 agents, 15 review fixes) was merged as `claude/depth-merge` → `f101c69`:
    - mini-games and recipes, nurses, the Nurse Journal, hospital levels 1–5, juice, perf;
    - Schema v3 keeps v2 play time and badges;
    - the Nurse Belt runs along the main road, one nurse per ~40 s, odds 75/20/4.5/0.5, pity 15, Epic+ hire from
      Lv 3 (`-017`);
    - Joshua delegated the §E5–E7 calls (`-020`).
  - **Studio** (FreshSave): clean boot; belt, a hire, the Lv 3 gate, the odds sign, seven tabs, levels to 5 (the
    lane and sign stay clear), a nurse-tray cure. 539 specs pass.
  - **Note:** MCP screen captures don't draw AlwaysOnTop billboards; to see one, turn AlwaysOnTop off.
- **2026-11-16 (later, Joshua's PC, Claude + many parallel agents).** Launch prep and first publish: name "Cure a
  Creature" (`-009`), ownership agreed (`-010`), the page (`docs/launch/page.md`) with AI-made images (Higgsfield, from
  real captures). The first publish was the empty Baseplate; fixed by publishing the real build. Tutorial + declutter
  (`6bb4ee2`), patients ×1.6 and spaced, spawns 13 s (`4d6fa10`), admin panel + Throw away (`af773f8`), all tested in
  Studio and published (Playtesters). Joshua's playtest feedback became the depth update (`-011`, `-012`, `-013`).
  Running in worktrees: the depth workflow, creatures v2, leaderboards, model scout.
- **2026-11-16 (Joshua's PC, Claude, tidy-up + candy-pop revamp + launch decisions).** Joshua: the brother is stepping
  back, delete the old Shop, and a saturated, flashy, trending look (`memory-20261116-007`). `Workspace.Shop` and
  `RoofFade.client.luau` deleted; the grey Baseplate is now grass green (place version 23). New `shared/Palette.luau`
  (candy colours, LuckiestGuy display font, outlines); `Theme` and `Kit` rebuilt (glossy outlined buttons, header
  bands, `Kit.shine`, `Kit.rays`, `Kit.bump`, `Kit.gloss`). Four parallel restylers did the HUD, the panels and reward
  FX, the world and lighting (`CandyColor` grade in DayNight), and the creatures and badges. Fixed: station make
  sparkles used server `Emit()`, which never reaches players. Studio check: clean boot, day, night and Shop all look
  right. Then Joshua chose (`-008`): hospital levels where the building grows (Update 1), publish first as a 16+ soft
  launch, no paid items at launch. Drafted `docs/plan/ownership-note-DRAFT.md` (blanks for the brothers).
- **2026-11-16 (Joshua's PC, Claude, Creature Clinic build + first Studio run).** Research → concept pivot: 4
  research docs in `docs/research/`, rulings `memory-20261116-003` (own plot, daily return because it's fun, no AFK, not
  a restaurant tycoon), `-004` (original absurd cast, no "brainrot" title at launch), `-005` (Creature Clinic, evergreen,
  Winter Wing launch), `-006` (brother likes it; 2× Cash pass kept with fairness rules). 10 Roblox agent skills vendored
  into `.claude/skills/`. Design and build plan written, then a 14-agent parallel build in a worktree
  (`claude/creature-clinic`): foundation, 8 feature tasks, integration, a 3-lens review (20 findings, all fixed). 178
  Lune specs pass, selene and StyLua clean. Merged into this branch (`a46bab5`). **First Studio run** via MCP: 10 of 12
  checklist items pass, item 8 partly, item 11 needs 2 players. Fixed in `9b169d4`: creature bodies stuck at the
  origin (weld captured before parenting) and a HUD resize loop. Old shop scripts (Customers, Kitchen, ShopWorld)
  are gone; `Workspace.Shop` is untouched. Notes: `logs/playtests/2026-11-16-clinic-first-studio-run.md`.
- **2026-11-16 (Joshua's Windows PC, Studio MCP, first run).** Installed Rokit/Rojo/selene/StyLua and the Rojo plugin.
  Added `.gitattributes` (LF), because Windows CRLF checkouts made StyLua flag every file. Fixed 3 selene warnings.
  **Built the shop in Studio via MCP** to the plan §4 contract: a 40×40 cozy pastel shop with an open front (mint
  wainscot, cream walls, side windows, wood beams, 6 warm pendant lights, a pink counter with a marble top, a register
  and a tip jar, a menu board, jar shelves, a storage shelf, a staff door, 2 café tables whose 4 stools you can sit on,
  plants, a striped awning, a "Welcome!" sign, an OPEN sign and a sidewalk). The oven is a generated mesh (`Decor.Oven`)
  on the now-invisible `Station`. Markers are invisible and `PlayerSpawn` is behind the counter. Theme stays neutral
  (OPEN #1). Saved as place version 9. **Code:** a Serve prompt on the `Counter` for the first waiting customer (the
  per-customer prompt is used only when there's no Counter), a sparkle burst at the Station, background music
  (`Music.client.luau`, licensed DistrokidOfficial tracks, mute button), and `RoofFade.client.luau`. **First playtest:**
  no red errors, customers queue, make → serve → paid (3 served, 41 Cash), music plays. Two ContentId warnings
  (203785492, 89586988328230) aren't ours, probably Roblox's default avatar assets. **Not done:** the roof (Studio was
  in Play mode, and Joshua ended the session), upgrades/night/save checks, privacy and collaborator checks.
  Roof plan for next time: two coral `ClayRoofTiles` slabs from eaves (x ±21.5, y 13.5) to the ridge (y 21), wedge
  gables at z ±19.5, a white ridge cap and rake trim, all CanCollide/CanQuery off, and move the sign forward to z 20.2–20.6.
- **2026-11-16 (cloud session, setup).** Repo initialised. The decision to start (`memory-20261116-001`) and the
  concept/audience/goal picks (`-002`) recorded. Researched and wrote the setup, costs and market scan, the plan, and
  the team split. First playable code under `game/`: customers, station, serving, 3 upgrades, saving, day/night, a 2x Cash
  pass hook, and a placeholder shop (`game/README.md`). It's StyLua-formatted and selene-clean (Luau std, because the Roblox std
  couldn't download here), but **it hasn't run in Studio yet**. A cloud session can't open Studio, so Joshua's first
  playtest is its first real run. Expect small fixes.
