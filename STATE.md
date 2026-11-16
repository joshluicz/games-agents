# State

> Live state first, narrative second. New entries go at the **top** of `## Recent sessions`.

## Phase
**Stage 0: tonight's private version** (2026-11-16). Game: a co-op shop sim with a night twist, built for under-13s,
goal is money (`memory-20261116-002`). Plan: `docs/plan/2026-11-16-game-plan.md`.

## Next actions
- [ ] **Joshua:** do the Windows setup in `docs/setup/01-connect-claude-to-roblox.md` (ID age check + 2FA, Claude Code ↔
      Studio MCP, Rokit/Rojo), publish a **private** Baseplate place, `rojo serve`, press Play.
- [ ] **Brother:** do the Mac setup in the same doc (Studio, age check, become Trusted Friends with Joshua), join Team
      Create, build the shop around the five marker parts (plan §4).
- [ ] **Both:** pick the theme and name (OPEN #1). Change `game/src/shared/Config.luau` → `ProductName`.
- [ ] **Both:** playtest tonight's version to the definition of done (plan §2). Write notes in `logs/playtests/`.

## Blocked on
- Nothing for tonight. Stage 2 (going public) waits on the ownership note (OPEN #2) and a yes from both.

## Who's doing what
Joshua: code, accounts, money · Brother: world, feel, players (`context/team.md`).

## Recent sessions
- **2026-11-16 (cloud session, setup).** Repo initialised. The decision to start (`memory-20261116-001`) and the
  concept/audience/goal picks (`-002`) recorded. Researched and wrote the setup, costs and market scan, the plan, and
  the team split. First playable code under `game/`: customers, station, serving, 3 upgrades, saving, day/night, a 2x Cash
  pass hook, and a placeholder shop (`game/README.md`). It's StyLua-formatted and selene-clean (Luau std, because the Roblox std
  couldn't download here), but **it hasn't run in Studio yet**. A cloud session can't open Studio, so Joshua's first
  playtest is its first real run. Expect small fixes.
