# State

> Live state first, narrative second. New entries go at the **top** of `## Recent sessions`.

## Phase
**Stage 0: tonight's private version** (2026-11-16). Game: a co-op shop sim with a night twist, built for under-13s,
goal is money (`memory-20261116-002`). Plan: `docs/plan/2026-11-16-game-plan.md`.

## Setup status (2026-11-16, Joshua's PC)
- ✅ Place **Shop Co-Op [WIP]** (placeId 112965897544918, universe 10777060712) is published under Joshua's account,
  with Team Create on and Studio API access on (a DataStore call from Studio worked).
- ✅ Rokit 1.2.0 with Rojo 7.7.1, selene 0.32.0 and StyLua 2.6.0. The Rojo plugin is installed and `rojo serve` syncs.
- ✅ Claude Code ↔ Studio MCP connected.
- ❓ Not checked: whether the game is set to **Private**, Joshua's ID age check + 2FA, and whether the brother has
  been added as **Edit** (and as a Trusted Friend).

## Next actions
- [ ] **Joshua + Claude:** stop the playtest, then build the roof: a `Roof` Model in `Shop` (the build script is in the
      2026-11-16 session notes below; `RoofFade.client.luau` is already synced). Save the place.
- [ ] **Joshua + Claude:** finish the README checklist: upgrades, night (set `Config.DaySeconds = 20`, then put it back),
      rejoin-save, and the phone emulator.
- [ ] **Joshua:** confirm the game is Private. Add the brother: Collaborate → his name → **Edit** (Trusted Friends first).
- [ ] **Brother:** the shop is already built in the real place. Open it from **Shared With Me** and decorate it with
      Assistant. ⚠️ `docs/guides/build-the-shop.md` Part B (and its artifact page) still says to drop in his own
      `Shop`. Update it to "decorate the existing Shop, don't add a second one" before he starts.
- [ ] **Both:** pick the theme and name (OPEN #1). Change `game/src/shared/Config.luau` → `ProductName`, and the
      "Welcome!" sign text in Studio.
- [ ] **Both:** playtest to the definition of done (plan §2). Write notes in `logs/playtests/`.

## Blocked on
- Nothing for tonight. Stage 2 (going public) waits on the ownership note (OPEN #2) and a yes from both.

## Who's doing what
Joshua: code, accounts, money · Brother: world, feel, players (`context/team.md`).

## Recent sessions
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
