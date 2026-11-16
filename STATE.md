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
**Live (published 2026-11-16, Playtesters only):** the tutorial build + player-sized patients, admin panel, Throw away
(`af773f8`). Go Public (16+) and start marketing **with the depth update**.
- [ ] **Claude:** merge and playtest the parallel work: depth update (worktree `.worktrees/depth`: mini-games +
      recipes, nurse belt + Nurse Journal + Mythic/Secret events, hospital levels, juice, perf), creatures v2
      (`.worktrees/creatures`), leaderboards (`.worktrees/boards`), the Creator Store model shortlist
      (`docs/research/2026-11-16-creator-store-models.*`). Then Joshua publishes.
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
