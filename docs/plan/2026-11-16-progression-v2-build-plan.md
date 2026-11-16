# Progression v2 build plan: contracts, file ownership, numbers, playtest

> **For agentic workers:** this plan runs as a **parallel team**. Task 0 (Foundation) is committed first and is
> **frozen**. Tasks T1–T8 then run at the same time, each editing **only the files it owns** (§A). Anything you need
> in a file you don't own goes in your final report under **Requests** (file, where, exact change). The lead
> integrates, playtests in Studio and commits. Steps use checkbox (`- [ ]`) syntax.

**Goal:** the update after Update 1. Nurses get jobs, specialties, signature abilities, XP to Lv 10 (15 from R3)
and team bonuses. The roster is 3 nurses (+1 per rebirth) and every nurse you own works. Rebirths ("🏢 Open a new
branch") give perk cards, Branch Ability Tree points, +25% 💰⭐, R1–R5 unlocks, a branch theme and status (a badge
and a Most Rebirths board). A Nurse Agency restocks every 5 minutes, and a same-server Player Market lets players
sell nurses to each other. Hospital v2 makes the floors playable: a lift, Wards upstairs, A&E ambulances, a Hydro
hot tub, a Pharmacy and the helipad.

**Spec (all decided; this plan doesn't re-decide it):** `docs/plan/2026-11-16-depth-update-design.md` §6 (Hospital v2),
§7 (jobs, abilities, XP, team bonuses, rebirths) and §8 (Agency, Market, roster). **Rulings:**
`memory/records/memory-20261116-017` (jobs, abilities, rebirths with a tree), `-018` (Agency, Market; its caps are
superseded), `-019` (roster 3 +1 per rebirth; what every rebirth gives; the Market stays same-server), `-020` (no
Golden Hour countdown; GOOD! holds the combo; level spawns). **Code map:** `game/README.md`. **Still law where this
plan doesn't change it:** `docs/plan/2026-11-16-depth-update-build-plan.md` §B and
`docs/plan/2026-11-16-creature-clinic-build-plan.md` §B.

**Where the game is (2026-11-16, `STATE.md`):** the live game runs the pre-depth build (schema v2 saves). Update 1
(schema v3: levels, nurses, the belt) is merged and playtested in Studio but **not published yet**. So almost no real
save has nurses yet. The v4 migration must still be exact for both v2 and v3 saves. Progression v2 can ship together
with Update 1 or after it. HEAD `9fc1024`: 539 Lune specs pass.

**Tooling** (PowerShell, from `game/`):
```powershell
& "$env:USERPROFILE\.rokit\bin\stylua.exe" src tests
& "$env:USERPROFILE\.rokit\bin\selene.exe" src                 # 0 errors, 0 warnings
& "$env:USERPROFILE\.rokit\bin\lune.exe" run tests/run
& "$env:USERPROFILE\.rokit\bin\rojo.exe" build default.project.json -o "$env:TEMP\progression-check.rbxl"
```

## Global constraints (every task)
- **Kids' rules (CLAUDE.md red line 3).**
  - No Robux anywhere in these systems.
  - Every random roll shows its odds: the belt sign, the Agency's 🎲, the perk cards ("3 random from this list"), the
    Golden patients chip.
  - No fail states. No FOMO, no streaks, **no countdown clocks**. Ability cooldowns are filling rings, never seconds.
  - No pressure to rebirth or to spend. There is no dot, no breathing button and no repeat toast for "you can open a
    branch". The keep/reset screen comes first, and "Not now" is its default button.
  - Words on screen ≤ 6, icons first, buttons ≥ 56 px tall.
  - Every motion honours `Kit.reducedMotion()`, and Simple mode keeps working.
- **Kids' trading rules (Market, Agency).**
  - No free text anywhere (a listing is a nurse, its level, a price and the seller's DisplayName).
  - No swaps and no haggling. Prices stay inside the bands.
  - A confirm comes before every buy, sell and list. A price the client saw must equal the server's price, or nothing
    happens.
- **Original only (red line 2).** Every nurse, creature, theme, perk, ability and sound is ours. Names are
  placeholders the brothers rename (OPEN #1). Built-in `rbxasset://` sounds only.
- **The server is authoritative.**
  - Every remote is wired with `Remotes.serve` (10 calls/s per player per remote, plus pcall). It checks types, ids
    (with `rawget`, so a Data map's `Order` is never an id), ownership, distance and cooldowns.
  - Prices, odds, rewards and bands come from `Config`/`Shared/Data` only. A price the client sends is only ever
    compared, never used.
  - **Charge and grant in ONE `PlayerData.update`, with no yield between the check and the change.** That includes a
    `task.wait`, a DataStore call, an `InvokeClient` or a signal handler you wait for.
- **Change the save only through `PlayerData.update(p, fn)`.** Never write `Data` fields this plan doesn't list.
- **File ownership is strict (§A).** The Foundation layer (Config, Types, Remotes, Schema, State, PlayerData,
  Data/\*, Logic/\*, Main.server, Main.client, Boosts, Admin, AdminPanel, the existing pure-Logic specs, README) is
  frozen after Task 0. Request changes; don't make them.
- **No commits, no Studio, no push in T1–T8.** The lead integrates and playtests.
- **Before you finish:** stylua, selene (0/0), lune (all pass) and the rojo build, as above.
- **Style:** `--!strict`, tabs, a header comment listing the module's API (like the existing modules), one
  responsibility per file. Other systems are called through `pcall` where a bug there must not break yours. A
  server module with testable rules keeps them in a `-- PURE-BEGIN` / `-- PURE-END` block (as `Nurses.Pure`), so its
  spec loads the shipped code.

## Review focus
1. **Dupes and scams.** A cheating client sends junk to `AgencyBuy`, `SellNurse`, `ListNurse`, `BuyListing`,
   `Unlist`, `OpenBranch`, `ChoosePerk`, `BuyNode`, `SetJob`, `RideLift` and `Triage`: wrong types, unknown ids, other
   players' listings, stale prices, two buyers at once, spam. A buy and a sell of the same nurse can race; so can a
   rebirth and a cure. Expected results:
   - No nurse ever exists twice and no cash appears from nothing.
   - Every rejection leaves the state unchanged.
   - A seller who leaves takes their listings with them.
2. **Rebirth correctness.**
   - It resets exactly cash, upgrades, level, rooms and room decor placements, and keeps everything else.
   - It can't run twice from one click or twice for one cost.
   - The perk offer can't be re-rolled by rejoining.
3. **Migration.** A v2 save (live) and a v3 save (Update 1 tests, up to 16 nurses, 5 on duty) load as v4.
   - No nurse is deleted.
   - At most the roster cap work and the rest rest.
   - XP is 0 and each job comes from its role.
   - An old server never writes a v4 save back (`Schema.isNewer`).
4. **Performance.** A Lv 5 plot with floors, the lift and every room stays ≤ 400 parts (no creatures, no decor). 6
   plots with full rosters (8 nurses) keep 60 fps on a mid phone. The lift, ambulance and helicopter never write a
   CFrame every frame on the server.
5. **Kids' rules.** There are no clocks anywhere and no rebirth pressure, odds are on show, and confirms come before
   anything that can't be undone.

---
## A. File ownership (`game/`)
Each file has exactly one owner. **New** files are marked ✚. Task 0 creates a stub for every ✚ module with the exact
API in §B8/§B9 (safe defaults), so everything requires and boots before any task lands.

| Task | Owns (create or modify) |
|---|---|
| **0 Foundation** (frozen) | (its new Logic specs include `tests/HospitalLogic.spec.luau`, so `Hospital.spec` stays T6's) `src/shared/{Config,Types,Remotes,Palette,Signal}.luau` · `src/shared/Data/*.luau` (✚ `Jobs`, ✚ `Departments`, ✚ `Abilities`, ✚ `Perks`, ✚ `Tree`, ✚ `Themes`) · `src/shared/Logic/*.luau` (✚ `Jobs`, ✚ `Abilities`, ✚ `Rebirth`, ✚ `Tree`, ✚ `Agency`, ✚ `Market`, ✚ `Hospital`) · `src/server/{Main.server,PlayerData,State,Boosts,Admin}.luau` · `src/client/Main.client.luau` · `src/client/UI/AdminPanel.luau` · every existing `tests/*.spec.luau` for a Logic or Data module, plus new Logic specs · `game/README.md` |
| **T1 Nurse work (server)** | `src/server/Nurses.luau` · ✚ `src/server/Abilities.luau` · `src/server/NurseBuilder.luau` · `tests/NurseServer.spec.luau` · ✚ `tests/NurseWork.spec.luau` |
| **T2 Branches (rebirth, server)** | ✚ `src/server/Rebirth.luau` · `src/server/Economy.luau` · `src/server/Carry.luau` · `src/server/Plots.luau` · ✚ `tests/RebirthServer.spec.luau` |
| **T3 Agency + belt** | ✚ `src/server/Agency.luau` · `src/server/NurseBelt.luau` · ✚ `src/client/UI/AgencyPanel.luau` · `src/client/UI/BeltView.luau` · ✚ `tests/AgencyServer.spec.luau` |
| **T4 Player Market** | ✚ `src/server/Market.luau` · ✚ `src/client/UI/MarketPanel.luau` · ✚ `tests/MarketServer.spec.luau` |
| **T5 Nurse + Branch UI** | `src/client/UI/NursePanel.luau` · ✚ `src/client/UI/BranchPanel.luau` · `src/client/UI/Shop.luau` · `tests/NurseUI.spec.luau` · ✚ `tests/BranchUI.spec.luau` |
| **T6 Hospital world** | `src/server/PlotBuilder.luau` · `src/server/Levels.luau` · `src/server/Stations.luau` · ✚ `src/server/Lift.luau` · ✚ `src/client/UI/LiftPanel.luau` · `docs/plan/2026-11-16-perf-budget.md` · ✚ `tests/Hospital.spec.luau` |
| **T7 Hospital patients** | `src/server/Patients.luau` · `src/server/Treatment.luau` · `src/server/Cure.luau` · `src/server/CreatureBuilder.luau` · `tests/ServerPure.spec.luau` · `tests/TreatmentSessions.spec.luau` · `tests/Motion.spec.luau` · ✚ `tests/HospitalPatients.spec.luau` |
| **T8 UI and juice** | `src/client/UI/{Hud,Kit,Theme,Toasts,Celebrate,MiniGames,Guide,BookPanel,Boards,PromptFilter}.luau` · `src/client/Feel/{Sounds,CureFX}.luau` · ✚ `src/client/Feel/HospitalFX.luau` · `tests/MiniGamesPure.spec.luau` · `tests/Juice.spec.luau` |
| **Lead (integration)** | anything, to fix integration bugs; the requests; `Leaderboards.luau`/`BoardBuilder.luau` only if a board needs code (it shouldn't); commits |

Untouched by everyone (unless the lead): `server/{Book,Badges,BoardBuilder,Daily,DayNight,DayReport,DecorBuilder,Events,Leaderboards,Playtime,Progress,Story,Tutorial,Visits}.luau`,
`client/UI/{BadgeBook,DayReportPanel,Mailbox,PlayGifts,Tutorial}.luau`, `client/Feel/{Atmosphere,CreatureActing,CreatureMotion,CreatureProps}.luau`, `client/Music.client.luau`.

Notes on shared files:
- **Specs.** A task may add its own ✚ spec files (above) and edit the existing specs it owns. The pure-Logic specs
  are the Foundation's. A change of yours that breaks someone else's spec is a **Request**, not an edit.
- **Hud (T8)** gets the Foundation's minimal hooks (§B9). They are `Hud.shopNews(...).Branch`, the `Open` names, and
  working first versions of `Kit.ring` and `Kit.holdButton`. T8 restyles them freely but keeps the names and
  signatures.
- **AdminPanel and Admin (Foundation)** call T1–T7's admin hooks (§B8 "Admin hooks"). The Foundation stubs answer
  `false, "Coming soon!"` until the owner lands them.
- **Data.Levels changes (Foundation)** move the ambulance bay to Lv 2 and give Lv 2 a ward floor (§B5). T6 builds
  that.

---
## B. Contracts (every task codes against these exact names)

### B1. Save (`Logic/Schema`, **Version 4**)
The version goes 3 → 4, so an old server (v3) loads a v4 save read-only (`Schema.isNewer`) instead of writing it
back without its rebirths. The DataStore name stays `PlayerData_v2`. `Schema.reconcile(saved, today?)` keeps its
signature; it needs no Data (see `Job = ""`).

**Changed:**
```lua
Nurses: { [NurseId]: NurseEntry },
NurseEntry = {
  Level: number,   -- 1..levelCap: 10, or 15 once Rebirth.Count >= 3 (Schema.levelCap(count))
  XP: number,      -- whole, 0 <= XP < Schema.xpToNext(Level); 0 at the cap (extra XP is dropped)
  Copies: number,  -- whole, >= 1 (each copy hired; duplicates add XP, §B6)
  Job: string,     -- "" = the nurse's own Role (Data/Nurses) · a Data/Jobs id · "Rest" (not working: only a save
                   -- with more nurses than its roster, §E2)
}
Upgrades: { [UpgradeId]: number }  -- Schema.UPGRADES gains "WardComfort", "AESpeed", "NightClinic"
Stats                              -- gains the counter "RoomsBefore" (rooms reset by rebirths; the 🏠 Builder badge)
```
**New:**
```lua
Rebirth: {
  Count: number,              -- rebirths done ("branches opened"), 0..Schema.MAX_REBIRTHS (1000)
  Points: number,             -- unspent Branch Ability Tree points, 0..Schema.MAX_POINTS (1000)
  Tree: { [NodeId]: number }, -- ranks bought (1..10); unknown node ids are kept (refunded by ResetTree, §B7)
  Perks: { PerkId },          -- perk cards chosen, in order, unique (<= 32)
  Offer: { PerkId },          -- the cards waiting to be chosen (0..3), unique, none already in Perks
  Theme: string,              -- the branch theme shown (Data/Themes id); "" = Candy
  Pending: { NurseId },       -- rebirth-only nurses waiting for a free roster slot (<= 4)
  Told: boolean,              -- the one gentle "🏢 You can open a branch!" toast was shown (once ever)
}
```
**Dropped:** `Equipped`. It is read once during migration and never written again.

`Schema.default()`: `Rebirth = { Count = 0, Points = 0, Tree = {}, Perks = {}, Offer = {}, Theme = "", Pending = {},
Told = false }`, `Nurses = {}`.

`Schema.reconcile` rules (v4):
- **A v2 save** migrates as in v3 (Level from rooms, an empty journal), then gets `Rebirth` defaults.
- **A v3 save's `Nurses`.** `{ Level 1..5, Copies }` becomes `{ Level (kept, clamped 1..10), XP = 0, Copies,
  Job = "" }`, so every nurse keeps its level and works its role's job (`Job ""`).
- **Who keeps working (every load, not only migration).** At most `Schema.rosterCap(count)` entries may have
  `Job ~= "Rest"`.
  - A v3 save fills the working places in this order: its old `Equipped` (in order), then the rest by NurseId.
  - A v4 save fills them by NurseId.
  - The ones past the cap get `Job = "Rest"`. **Nothing is ever deleted**, and unknown NurseIds are kept (servers
    ignore them).
- **Each entry.**
  - `Copies` is a whole number ≥ 1 (junk → 1).
  - `Level` is a whole number clamped to `1..levelCap(count)` (junk → 1).
  - `XP` is a whole number in `0..xpToNext(Level) − 1` (junk → 0; 0 at the cap).
  - `Job` is a string of 1–20 letters, or `""` (junk → `""`).
- **`Rebirth` fields.**
  - Every number is whole, finite and clamped.
  - `Tree` uses the `numberMap` rules (short string keys, 1..10).
  - `Perks`, `Offer` and `Pending` are arrays of short unique strings at their caps, and `Offer` drops anything
    already in `Perks`.
  - `Theme` is a short string (`""` when junk).
  - `Told == true`.
- **`Equipped`** is gone after reconcile. **`Stats.RoomsBefore`** follows the `numberMap` rules.

Constants repeated in Schema because it has no requires (specs check they match Config/Logic):
`MAX_NURSE_LEVEL = 15`, `NURSE_LEVEL_CAP = 10`, `NURSE_LEVEL_CAP_R3 = 15`, `ROSTER_BASE = 3`, `ROSTER_PER_REBIRTH = 1`,
`ROSTER_MAX = 8`, `xpToNext(level) = 10 + 5 · level · (level + 1)`, `rosterCap(count)`, `levelCap(count)`.

### B2. Snapshot (`State.snapshot`, `Types.Snapshot`)
Everything from v3, plus copies of `Rebirth` and the v4 `Nurses`. **`Equipped` is removed** (the client's default
snapshot drops it too). Nothing else is added: the client works out the roster cap, the level cap, the effective
jobs, team bonuses, the next rebirth's cost and the tree's effects from the Snapshot with `Logic/*` and `Config`
(§B7). The **Agency and the Market are not in the Snapshot**. They are server state, read through `GetAgency`/
`GetMarket` and pushed with `AgencyNews`/`MarketNews`.

### B3. Remotes (`ReplicatedStorage.Remotes`, created by `Shared/Remotes`)
`EquipNurse` is **removed**: every nurse you own works.

**Server → client events** (Main.client forwards each to the bus under the same name):

| Event | Payload (`Types`) | Who fires | Who listens |
|---|---|---|---|
| `AgencyNews` | `AgencyView` (each player gets their own) | T3 Agency (a restock, a buy, a sell) | T3 AgencyPanel |
| `MarketNews` | `MarketView` (everyone) | T4 Market (debounced 0.5 s) | T4 MarketPanel, T5 NursePanel (🏷️ on your cards) |
| `BeltScout` | `{ Rarity: Rarity, Event: string }` (only 🔭 Belt Scout perk owners) | T3 NurseBelt | T3 BeltView |
| `NurseNews` | `NurseNews` (new kinds below) | T1 Nurses | T5, T8 |
| `Celebrate` | `CelebrateInfo` (new kinds below) | T1 (NurseLevel), T2 (Rebirth, Perk, Unlock), T3/T4 (NewNurse via `Nurses.grant`/`give`) | T8 Celebrate |

**Client → server functions** (all via `Remotes.serve`, 10/s per player; each returns `(ok, message, payload?)`):

| Function | Args (untrusted) | Server | Rules (in order; any failure = `false` + a ≤ 6-word message, nothing changes) |
|---|---|---|---|
| `SetJob` | `(nurseId: string, job: string)` | T1 Nurses | owned · `job` is a Data/Jobs id (not `"Rest"`) · open at your hospital level (`Logic/Jobs.open`; else "🏥 Lv 2 first!") · a resting nurse may take a job only while working < roster cap · 0.35 s per player. Saves `Job` (`""` when it equals the Role) |
| `OpenBranch` | `(confirm: boolean)` | T2 Rebirth | `confirm == true` · loaded and `PlayerData.canSave` (else "⚠️ Saving is off") · tutorial done · no perk card waiting (`Rebirth.Offer` empty; else "🃏 Pick your card first!": one card per branch, no re-roll fishing; admin free rebirths skip it; added at integration) · `Logic/Rebirth.canRebirth` (Lv 5, cash ≥ cost) · no treat session open (`Treatment.busy`: "Finish treating first!") · 5 s per player · then `Patients.reopen(owner)`, **re-check**, then ONE update (§B8). One click can never rebirth twice: the count it checked must equal the count it writes |
| `ChoosePerk` | `(perkId: string)` | T2 | `perkId` is in `Rebirth.Offer` and not in `Perks` · ONE update: add it, clear `Offer`, apply its start-of-branch effect now (§B5 Perks) |
| `BuyNode` | `(nodeId: string)` | T2 | a Data/Tree node · `Logic/Tree.canBuy` (points, max rank, a capstone's 6 points in its branch) · ONE update |
| `ResetTree` | `()` | T2 | 2 s per player · ONE update: every rank refunded (`Logic/Tree.refund`) |
| `SetTheme` | `(themeId: string)` | T2 | a Data/Themes id unlocked at your `Rebirth.Count` · ONE update |
| `ClaimBranchNurse` | `()` | T2 | `Rebirth.Pending` has one · roster room · `Nurses.grant(p, id, 0, "Gift")` (it removes it from `Pending` in the same update) |
| `GetAgency` | `()` | T3 Agency | answers `(true, "", AgencyView)`; never a DataStore call |
| `AgencyBuy` | `(slot: number, nurseId: string, expect: number)` | T3 | §B3.1 |
| `SellNurse` | `(nurseId: string, expect: number)` | T3 | §B3.1 |
| `GetMarket` | `()` | T4 Market | answers `(true, "", MarketView)` |
| `ListNurse` | `(nurseId: string, price: number)` | T4 | §B3.2 |
| `Unlist` | `(listingId: number)` | T4 | your own listing only |
| `BuyListing` | `(listingId: number, price: number)` | T4 | §B3.2 |
| `RideLift` | `(floor: number)` | T6 Lift | a whole number · that floor exists on this plot's building · you stand within `Config.Lift.CarDistance` of one of its landings · 1 s per player · then a ding and a ride (`Lift.ride`) |
| `Triage` | `(session: number, dept: string)` | T7 Treatment | your own pending triage (one at a time, keyed to the session that completed the recipe) · `dept` is one of its `Options` · inside the window. Right: +10% on that cure. Wrong: "Oops, not this floor!" and it goes the right way anyway |

#### B3.1 Agency rules (anti-dupe, anti-surprise)
- **The stock.** It is server-wide and in memory. Every `Config.Agency.RestockSeconds` of server uptime brings a new
  restock (index `Logic/Agency.restock(uptime)`). It holds `Config.Agency.Slots` (4) distinct nurses rolled with
  `Config.Agency.Odds` (Common to Epic only; rebirth-only nurses never). The 🍀 Lucky Stock capstone adds 2 slots for
  you only, rolled from the same shown odds with a seed of (UserId, restock), so rejoining never re-rolls them. A
  shared-stock nurse is never repeated in them unless every nurse of the rolled rarity is in the shared stock; then a
  shared one may repeat, so the shown odds stay true (integration: `Logic/Agency.personal`).
- **`AgencyBuy(slot, nurseId, expect)`**, checked in this order:
  1. `slot` is a whole number and the slot exists in YOUR view for the CURRENT restock.
  2. `nurseId` equals that slot's nurse. Else: "New nurses came! Look again", plus a fresh `AgencyNews`.
  3. You haven't bought that slot this restock. This is in memory by UserId, so a rejoin to this server remembers.
  4. The gates pass (`Logic/Belt.gate`: "🏥 Lv 3" / "🏢 R1").
  5. `Logic/Nurse.canAdd` passes: roster room for a new nurse ("Roster full: sell or list one"), or not at the level
     cap for a copy ("Max level!").
  6. The price is `Logic/Agency.price(cfg, rarity, yourLevel, bargain)` and `expect` equals it (else "Price changed!
     Look again").
  7. Cash ≥ price.
  8. 1 s per player.
  9. `Nurses.grant(p, nurseId, price, "Agency")`: the charge and the copy in ONE update. The slot is marked bought
     only after a `true`, with no yield in between.
- **`SellNurse(nurseId, expect)`**, checked in this order:
  1. You own it.
  2. It isn't listed on the Market (`Nurses.isListed`: "Unlist it first").
  3. It isn't rebirth-only (`Source`: "This one stays with you!").
  4. `expect` equals `Logic/Agency.sellBack(entry, rarity, cfg)`.
  5. 1 s per player.
  6. `Nurses.take(p, nurseId, cash, "Sold")`: the nurse goes and the cash comes in ONE update.
  - The Journal keeps "Hired". The worker poofs off your plot.
  - The client always asks first with a big confirm: "Sell 🐶 Lv 7 for 💰30?". A hold-to-confirm
    (`Kit.holdButton`, 1 s) is used for Epic and up.

#### B3.2 Market rules (same server only; anti-dupe, anti-scam)
- **Listings are in memory.**
  - The nurse **never leaves the seller's save** while it's listed: a listing is only a lock (`Nurses.setListed`).
  - So a crash or a shutdown ends every listing with nothing to restore.
  - A listed nurse keeps working (🏷️ on its card) until it's sold.
- **`ListNurse(nurseId, price)`**, checked in this order:
  1. You own it, and it isn't rebirth-only. A resting nurse may be listed (§E2 and §D P1: listing or selling one is
     how an over-roster save makes room; Task 0 fixed this line, which said "isn't resting").
  2. It isn't listed already.
  3. `price` is a whole number inside `Logic/Market.band(cfg, rarity, level)` for its level now.
  4. You have fewer than `Config.Market.MaxPerSeller` (3) listings, and the server has fewer than `MaxListings` (30).
  5. `PlayerData.canSave(seller)`: a session that isn't saving can't sell.
  6. 5 s per player.
  - The price can't be changed afterwards: unlist and list again.
- **`BuyListing(listingId, price)`**: every check first, then the transfer, all without a yield.
  1. The listing exists, and `price == listing.Price` exactly (a stale or changed price: "Price changed! Look
     again").
  2. Buyer ≠ seller ("That's yours!").
  3. Both players are in this server, `PlayerData.isOpen` and `PlayerData.canSave`.
  4. The seller still owns that nurse, and it is still listed under this id.
  5. The buyer passes the gates (`Logic/Belt.gate`: hospital level and rebirths, the same as the belt; otherwise the
     Market would skip them).
  6. The buyer has roster room and doesn't own that nurse ("You have one!", §E13), and the listing's level is within
     the buyer's nurse level cap ("🏢 R3 first!": never clamped; `Logic/Market.canBuy`, added at integration).
  7. The buyer has cash ≥ price.
  8. 2 s per buyer.
  9. **Lock:** remove the listing from the table first, so a second buyer finds nothing.
  10. **Seller update:** `Nurses.take(seller, nurseId, price − fee, "Market")` (the fee is
      `floor(price × Config.Market.Fee)`; the fee is a cash sink).
  11. **Buyer update:** `Nurses.give(buyer, nurseId, entry, price)` charges the price and adds the seller's exact
      `Level`, `XP` and `Copies`. Its `Job` resets to `""` and the NurseIndex mark is "Hired" (plus any journal set
      due).
  12. If step 11 returns false (it can't, after step 3, but if it does), undo step 10 with `Nurses.give(seller,
      nurseId, entry, payout)`: the nurse goes back and the payout comes back out in one update. Then answer "Oops!
      Try again."
  13. Afterwards: `PlayerData.saveNow(seller)` **then** `PlayerData.saveNow(buyer)`.
      - Seller first: a crash between the two writes can lose a nurse, but never duplicate one.
      - `PlayerData.writeAfter(seller, buyer)` (integration) holds the buyer's autosave and leave-save behind the
        seller's write too (bounded at 10 s), so the autosave loop can't reorder the two.
      - Then `MarketNews` goes to everyone, `Celebrate` NewNurse goes to the buyer and "💰 Sold 🐶!" goes to the
        seller.
- **Who sees what.**
  - The seller leaving (`PlayerRemoving`) removes their listings at once, before their leave-save. A buyer leaving
    mid-call changes nothing (it never yields).
  - Admins are not excluded. Nobody's listing shows anything but the nurse, its level, the price and the seller's
    DisplayName.

**Payload types** (in `Shared/Types`, besides the v3 ones):
```lua
type JobId = string          -- Data/Jobs: "Maker" | "Healer" | "Cheerer" | "Receptionist" | "Porter" | "Medic"
type DeptId = string         -- Data/Departments: "Reception" | "AE" | "Wards" | "Hydro" | "Pharmacy" | "Roof"
type AbilityId = string · type PerkId = string · type NodeId = string · type ThemeId = string
type NurseEntry = { Level: number, XP: number, Copies: number, Job: string }
type RebirthData = { Count: number, Points: number, Tree: { [NodeId]: number }, Perks: { PerkId },
  Offer: { PerkId }, Theme: string, Pending: { NurseId }, Told: boolean }
type AgencySlot = {
  Slot: number, NurseId: NurseId, Rarity: Rarity,
  Price: number,             -- YOUR price now (level scale and Bargain included)
  Bought: boolean,           -- you bought this slot this restock
  Personal: boolean,         -- a 🍀 Lucky Stock slot (only you see it)
  Gate: string?,             -- "🏥 Lv 3" | "🏢 R1" | nil
}
type AgencyView = { Restock: number, Slots: { AgencySlot }, Odds: { [Rarity]: number },
  SellBack: { [NurseId]: number } } -- what the Agency pays you for each nurse you own now
type Listing = { Id: number, Seller: number, SellerName: string, NurseId: NurseId, Rarity: Rarity,
  Level: number, Price: number }       -- SellerName = DisplayName; nothing else about anyone
type MarketView = { Listings: { Listing }, FeePercent: number, MaxPerSeller: number }
-- TreatSession gains:
  Kind: "Treat" | "Soak",    -- Soak: the Hydro hot tub's 🫧 game (Items = {}, Games = { "Scrub" }, a tip only)
  Auto: { boolean },         -- per game: an ability made it PERFECT (the client shows ✨ and skips it)
  Ease: number,              -- 1..1.3: 🎯 Steady Hands widens the Perfect windows (client only, never checked)
-- TreatOutcome gains:
  Triage: { Options: { DeptId }, Seconds: number }?   -- pick a floor for this patient now (Lv 3+, no Receptionist)
-- NurseNews kinds (Kind + NurseId always):
  "Seen" | "Hired" (Level, New) | "Job" (Job) | "Level" (Level, Ability: boolean = an ability upgrade at 5/10)
  | "Sold" (Cash) | "Bought" (Price) | "Gone" (Price: sold on the Market) | "Listed" (On: boolean) | "Resting" (On)
-- CelebrateInfo.Kind gains:
  "Rebirth" (Count, Theme) | "Perk" (Perk) | "NurseLevel" (NurseId, Level, Ability) | "Unlock" (Unlock: string)
-- CureCtx gains:
  Urgent: string?,  -- "AE" | "VIP" (an ambulance or helicopter patient)
  Extra: number?,   -- situational factors Patients knows (escort, spa, triage, team, Ward Comfort), 1..Pay.MAX_EXTRA
  Plot: Plot?,      -- where it was cured (Cure asks Abilities and Nurses about this plot)
  Dept: string?,    -- the department it recovered in (nurse XP specialty)
  Wing: string?,    -- for XP and Book (already derivable; passed to save a lookup)
  Escorted: boolean?, Soaked: boolean?,  -- (integration) passed on to CuredInfo
-- CuredInfo gains (integration; Server/Cure always sends them, "" / false = no): Urgent: string?,
--   Escorted: boolean?, Soaked: boolean?   -- Feel/CureFX's "🚑 ×3", "+20% 🛗", "+25% 🛁" lines
```

### B4. Instances and attributes
**Plots (writers in brackets; everyone else reads):**
- `Level` (T6, unchanged). `Theme: string` (T6 Levels, from the owner's `Rebirth.Theme`; `"Candy"` for a free plot).
  `Branches: number` (T2: the owner's `Rebirth.Count`; 0 for a free plot).
- `CheerPatience`, `CheerTip`, `NurseTray` (T1, unchanged).
- `Reception: number`: the best Receptionist's arrival factor, 1 = none, e.g. 0.92. `Triage: boolean`: a
  Receptionist is on duty, so routing is instant. (T1)
- `MedicPatience: number`: urgent and VIP patients drain this much slower, 1 = none. (T1)
- `TeamBonus: string`: e.g. `"Reception:2,Hydro:3"`, the team chips. `TeamCash: number`, `TeamRecover: number`,
  `TeamUrgent: number` (factors, 1 = none). `TeamMake: string`: e.g. `"Bath=0.8,Cocoa=0.8"`, hold factors per
  station. (T1)
- `PatiencePausedUntil: number`: a `GetServerTimeNow()` time; Calm Song. (T1 Abilities)
- `MakeRushUntil: number`, `MakeRushFactor: number`: Busy Paws 0.5, Time Bubble 0 = the shortest hold. (T1 Abilities)
- `FrontNeeds`, `QueueNeeds`, `FrontItem`, `FrontStation` (T7, unchanged; with Twin Counters `FrontNeeds` covers the
  first two patients).
- Children:
  - `Building` (T6). `Nurses` (T1). `Patients` (T7).
  - `Mascot` (T2, a Model from R5).
  - `SignGui.BranchBadge`: T6 creates a hidden TextLabel beside `RankBadge`; T2 shows "🏢 n" from R1.

**The building (T6, `PlotBuilder.buildBuilding(plotModel, level, grewFrom?, theme?)`).** It keeps every v3 contract:
`Since`, `Level`, `GrewFrom`, `GrewAt`, kept beds, and never covering the Counter, the queue lane, the gate, the
walkways, the stations or a room slot. It adds:
- `Building:SetAttribute("Floors", n)` (walkable floors above the ground, `Data/Levels.Floors`) and `"Theme"`.
- `Floor_<n>` Models (n = 1..Floors; the roof at Lv 5 is `Floor_4`). Each has a collidable `Slab` Part you can walk
  on and a `Landing` Part (an invisible 4×1×4 marker in front of the lift door). The ground storey's landing is
  `Building.Landing_0`. The walls above the ground storey stay soft (walk-through, ray-ignored); only the slabs
  collide.
- `Lift` (Model): `Shaft` (glass, soft), `Car` (soft; it moves only on clients) and `LiftPrompt`s. There is one
  ProximityPrompt per landing: ActionText "Lift", ObjectText "🛗", HoldDuration 0, MaxActivationDistance 8, under an
  Attachment on that `Landing_<n>`. Each landing also has an `EscortPrompt` ("Ride with patient", disabled until
  `Lift.waitEscort` turns it on).
- `Stairs` (Model): a walkable flight per storey (wedges or steps with collision), from Lv 2.
- Department pieces (each a child Model with `Since`):
  - Lv 2: `Wards` (on `Floor_1`; the extra beds as `BedSpot_<n>.Bed_<n>` with the attribute `Floor = 1`) and the
    `AmbulanceBay` (it moves from Lv 4 to Lv 2; the parked `Ambulance` gains a `StretcherSpot` marker and an
    attribute `ArriveAt`, which T7 sets and T8 HospitalFX flashes and sirens).
  - Lv 3: `Hydro` (`Floor_2`): the `HotTub` Model with `TubSpot_1`, `TubSpot_2` (Parts, `Floor = 2`) and a
    `SoakPrompt` ("🫧", disabled until T7 turns it on).
  - Lv 4: `Pharmacy` (`Floor_3`): a station Model `Station_Pharmacy` that follows the station contract (Stations
    picks it up by tag, it gets the usual hold prompt and IconGui).
  - Lv 5: `Roof` (`Floor_4`): the helipad (already built) with a `HeliSpot` marker and an attribute `ArriveAt` (T7
    sets it; T8 HospitalFX flies a client-only helicopter in and out), plus a roof garden of planters.
- `MascotSpot` (a marker beside the Counter, on the plot, for T2's mascot; the fallback is plot-local (−8, 0, −13)).
- **Branch themes** recolour the building's walls, roof and trim and add one roof prop (≤ 6 parts) from
  `Data/Themes`. **The plot's accent colour never changes**: kids find "the pink one".

**Patients (T7 sets):** besides the v3 attributes:
- `Urgent: string`: `""`, `"AE"` or `"VIP"`. The badge shows 🚑 or 🚁.
- `Dept: string`: where it recovers, `"Wards"` or `"Hydro"`. The badge's department chip (`CreatureBuilder.setDept`).
- `Escorted: boolean`.
- `State` gains `"Triage"`, `"ToLift"`, `"Riding"`, `"Soaking"`.

**Nurses on a plot (T1):** `Plot.Nurses.Nurse_<NurseId>`, besides the v3 attributes:
- `Job` (the effective job) and `Specialty`.
- `Ability` (an AbilityId), `AbilityReadyAt: number` (server time; ≤ now = ready) and `AbilityCooldown: number`
  (seconds, for the ring's fraction). `AbilityAt: number` (server time it last fired: clients play the sparkle).
- `Resting: boolean` is never on a plot model: resting nurses aren't built.
- `Task` gains `"Escorting"`, `"Greeting"` (Receptionist), `"Treating"` (Medic).

**Town (T3/T4).** `Workspace.NurseAgency` and `Workspace.PlayerMarket`, two kiosk Models built by their servers at
`Config.Town.Origin + Config.Agency.Offset` / `Config.Market.Offset`. Each is on the plaza's row-2 half, facing the
spawn. Each has a `Prompt` (ProximityPrompt; ActionText "Agency"/"Market"; the client opens its panel on
`Triggered`) and a sign. They must stay clear of:
- the spawn pad, the benches (x = ±15, z = 0) and lamps (x = ±15, z = 4.5), and the planters (x = ±10.5, z = ±5);
- the belt (z = −11 ± 3.4) and its sign (x = −14, z = −15.8);
- the middle plots' gate path (x = 0) and both arches.

Each is ≤ 25 parts, with no Highlight and no shadow-casting light.

**Workspace attributes:** `AgencyRestock: number` (T3: the restock index). The belt's are unchanged. The belt model
`Workspace.NurseBelt` gains (T3) a `NextLamp` Part (a PointLight `Glow`) over the nurse-house door and the attribute
`NextArrivalAt` (a `GetServerTimeNow` time, read by UI/BeltView for the number-free lamp).

**What T6 built beyond the text above (recorded at integration):**
- The ground storey is `Building.Lobby`. The Lv 2-4 roof piece is `RoofShell`; the department piece `Roof` exists
  only at Lv 5. The theme prop is `ThemeProp` (attribute `Theme`). Landings carry the attribute `Floor`.
- The SoakPrompt sits at `HotTub.Tub.SoakPoint`. EscortPrompt uses key F / ButtonY, so it shares an Attachment with
  the LiftPrompt (E). The third ward bed (Lv 4) lies across the front right of `Floor_1`.
- CollectionService tags: `BuildingStation` (the Pharmacy), `HospitalLift` (each Lift Model), `LiftPrompt`,
  `EscortPrompt`, `SoakPrompt`.
- Ride attributes: `Player.LiftRide` = `"<plotIndex>,<from>,<to>,<seconds>,<serverTime>"`; on the Lift Model
  `Ride` = `"<from>,<to>,<seconds>,<serverTime>"`, then `Rider` (UserId, 0 = a patient or porter alone) and `RideAt`
  (server time). `Lift.ride` answers at once with a third payload `{ Seconds, From, To }`.
- A Lv 5 plot with every room is 372 parts (378 with the Jungle/Royal prop), measured by the real PlotBuilder under
  a Lune mock; with the 10 heaviest placeholder decor in its 10 slots, 548 (`tests/Hospital.spec`).

**Player attributes:** `Combo` (unchanged). `WalkBoost: number` (T2: Quick Feet ranks; T2 sets
`Humanoid.WalkSpeed = 16 + WalkBoost` on every CharacterAdded).

**Motion.** Every new mover follows the creature-motion contract: one end-pose write per hop, no per-frame server
CFrame. That covers patients and porters riding the lift (`Lift.carry` does one `PivotTo` per model at the
destination after the ride; the car's motion is client-only) and the mascot's hops. The ambulance's lights and the
helicopter are client-only (`Feel/HospitalFX`) and driven by one server attribute each.

### B5. Data modules (`src/shared/Data/`, Lune-safe unless noted, frozen, keyed maps with `.Order`)
- **`Nurses`** gains `Specialty: DeptId | "Any"`, `Ability: AbilityId`, `Source: "Rebirth"?` and `Rebirths:
  number?` (the count that grants it), plus a 17th nurse:

  | Nurse | Rarity | Role (default job) | Specialty | Ability |
  |---|---|---|---|---|
  | PuffPup | Common | Maker | Reception | FreshBrew |
  | MintMouse | Common | Healer | Wards | QuickBandage |
  | BeanBear | Common | Maker | Pharmacy | FreshBrew |
  | DewDuck | Common | Healer | Hydro | QuickSoap |
  | HumHamster | Common | Cheerer | Reception | WarmHug |
  | CuddleCub | Rare | Maker | AE | WarmHug |
  | PebblePenguin | Rare | Healer | Hydro | CalmSong |
  | BerryBat | Rare | Maker | Pharmacy | BusyPaws |
  | SunnySnail | Rare | Cheerer | Wards | CalmSong |
  | CloudKoala | Epic | Healer | Wards | DoubleDose |
  | JamJelly | Epic | Maker | Hydro | StarBurst |
  | ToffeeFox | Epic | Cheerer | AE | DoubleDose |
  | AuroraOtter | Legendary | Healer | AE | GoldenTouch |
  | StarlightLamb | Legendary | Cheerer | Reception | RainbowCheer |
  | MoonpuffDrake | Mythic | Maker | Pharmacy | TimeBubble |
  | GoldieGryphlet | Secret | Healer | Reception | Miracle |
  | ✚ FounderFennec | Legendary | Healer | Any | TeamSpirit · `Source = "Rebirth"`, `Rebirths = 5` |

  The specialties spread 4 Reception and 3 each of A&E, Wards, Hydro and Pharmacy, so a Common/Rare pair exists for
  every team. FounderFennec is a placeholder name and look (the brothers rename it). It never rides the belt, never
  stocks the Agency and can't be listed or sold.
- **✚ `Jobs`** `{ [JobId]: { Name, Icon, Dept, Opens (hospital level), Text (≤ 6 words) } }`:

  | Job | Icon | Dept | Opens | What it does |
  |---|---|---|---|---|
  | Maker | 🧪 | the station's | Lv 1 | makes what the line needs into the nurse tray (as v3) |
  | Healer | 🩺 | Reception | Lv 1 | gives the front patient tray items, rated OK (as v3) |
  | Cheerer | 🎉 | Reception | Lv 1 | patients wait longer, cures pay more (as v3) |
  | Receptionist | 🛎️ | Reception | Lv 1 | patients come sooner; sends treated patients to the right floor (Lv 3+) |
  | Porter | 🛗 | Wards | Lv 2 | rides upstairs patients to their bed: +20% 💰, rests twice as fast |
  | Medic | 🚑 | AE | Lv 2 | gives 🚑/🚁 patients tray items (rated OK); they wait longer |
  A job not open at your level (after a rebirth, say) is worked as the nurse's Role until it opens again
  (`Logic/Jobs.effective`). Nothing is lost.
- **✚ `Departments`** `{ [DeptId]: { Name, Icon, Opens, Floor, Team2: TeamEffect?, Team3: TeamEffect? } }`.
  Stations belong to departments: Remedy and Plaster → Reception, Bath → Hydro, Cocoa and Pharmacy → Pharmacy.
  Wings belong to departments (for XP): Starter and Sunny → Reception, Bath → Hydro, Winter → Pharmacy, Night →
  Wards, Sky → A&E; urgent patients → A&E.

  | Dept | Icon | Opens | Floor | Team of 2 | Team of 3+ |
  |---|---|---|---|---|---|
  | Reception | 🛎️ | 1 | 0 (ground) | +10% cure 💰 | +20% |
  | AE | 🚑 | 2 | 0 (the bay) | 🚑/🚁 wait +25% | +50% |
  | Wards | 🛏️ | 2 | 1 | rest 25% faster | 50% |
  | Hydro | 🛁 | 3 | 2 | 🛁 holds 20% faster | 40% |
  | Pharmacy | 💊 | 4 | 3 | ☕ and 💊 holds 20% faster | 40% |
  | Roof | 🚁 | 5 | 4 (the roof) | – | – |
  A team counts **working** nurses whose `Specialty` is that department ("Any" counts for every one). Teams don't
  stack: 2 gives the small bonus, 3 or more the big one.
- **✚ `Abilities`** `{ [AbilityId]: { Name, Icon, Kind, Cooldown (s), Values: { base, Lv 5, Lv 10 }, Game: GameId? } }`.
  Every cooldown ×0.85 at nurse Lv 5 and ×0.85 again at Lv 10 (60 → 51 → 43 s), never below
  `Config.Abilities.MinCooldown` (20 s):

  | Ability | Icon | Kind | Cooldown | Value (base / Lv 5 / Lv 10) | Fires when (`Logic/Abilities.useful`) |
  |---|---|---|---|---|---|
  | QuickBandage | 🩹 | AutoPerfect (Patch) | 60 | 1 / 2 / 3 games | banked; the next 🩹 games are PERFECT |
  | QuickSoap | 🫧 | AutoPerfect (Scrub) | 60 | 1 / 2 / 3 games | banked; the next 🛁 games |
  | FreshBrew | 🧪 | TrayItem | 75 | 1 / 2 / 3 items | the line needs an item the tray lacks, and the tray has room |
  | WarmHug | 🤗 | RefillFront | 60 | – | the front waiting patient < 50% patience |
  | CalmSong | 🎵 | PauseLine | 90 | 10 / 13 / 16 s | any waiting patient < 50% |
  | BusyPaws | ⚡ | FastMake | 90 | 10 / 13 / 16 s at ×0.5 holds | the line misses ≥ 2 items not in hands or tray |
  | DoubleDose | 💊 | CashNext | 120 | ×2 for 1 / 2 / 3 cures | banked; the next cures at this plot |
  | StarBurst | 🌟 | StarsNext | 120 | +3 / +4 / +5 ⭐ next cure | banked |
  | GoldenTouch | ✨ | AutoPerfect (any) | 150 | 3 / 4 / 5 games | banked |
  | RainbowCheer | 🌈 | RefillLine | 150 | – | ≥ 2 waiting patients < 50% |
  | TimeBubble | ⏳ | InstantMake | 180 | 8 / 10 / 12 s | the line misses ≥ 2 items and the owner is within 25 studs of a station |
  | Miracle | 💫 | CureLine | once per in-game day | – | ≥ 2 patients waiting (not being treated) |
  | TeamSpirit | 🏢 | Recharge | 240 | – | ≥ 2 other abilities on cooldown |
  "Banked" abilities light up when ready and are spent by the next matching treat or cure; their cooldown starts
  then. GoldenTouch counts mini-games, not patients.
- **✚ `Perks`** `{ [PerkId]: { Name, Icon, Text (≤ 6 words), Kind, Value } }`, 12 cards, and `Perks.Fallback` (the
  card once all 12 are owned):

  | Perk | Icon | Text | Effect |
  |---|---|---|---|
  | BusyDoors | 🚪 | Patients come 15% faster | spawn seconds ×0.85 (the line still caps at 3) |
  | BathReady | 🛁 | Start with the Bath Room | every branch starts owning BathRoom |
  | FastLearners | 📚 | Nurses learn twice as fast | nurse XP ×2 |
  | NightOwl | 🦉 | Night patients stay longer | night patients keep coming for 30% of a night after morning (§E4) |
  | BigHands | 🧺 | Carry one more | +1 tray (`CarryMax`) |
  | BeltScout | 🔭 | See the next belt nurse | `BeltScout` shows the next arrival's rarity (you only) |
  | SeedMoney | 💰 | Start branches with 💰1,000 | cash after a rebirth = 1,000 |
  | WarmUp | ⚡ | Start with two upgrades | every branch starts with Faster Hands 2 and Tip Jar 1 |
  | SirenPro | 🚑 | Ambulances come 25% more | A&E interval ÷1.25 |
  | PatientPals | 💺 | Patients wait 20% longer | Patience +20 (branch source) |
  | ClinicStart | 🏠 | Start at hospital Lv 2 | every branch starts at Lv 2 |
  | SecondWind | 🔁 | Abilities recharge 20% faster | every cooldown ×0.8 |
  | *Fallback* TreePoints | 🌳 | +2 tree points | +2 `Rebirth.Points` (never runs out) |
  The start-of-branch perks (BathReady, SeedMoney, WarmUp, ClinicStart) also apply once when chosen, since you
  choose at the start of a branch.
- **✚ `Tree`** `{ Branches = { Care, Speed, Fortune }, Nodes = { [NodeId]: { Branch, Name, Icon, Text, Max, Cost,
  Capstone: boolean, Effect } } }`. Ranks cost 1 point each and a capstone costs 2, needing 6 points spent in its
  branch. The whole tree is 33 points:

  | Branch | Node | Icon | Per rank (max 3) | Effect key |
  |---|---|---|---|---|
  | 💗 Care | GentleWords | 💺 | Patience +10% | `Patience` |
  | | ThankYou | 💵 | Tips +10% | `Tips` |
  | | SteadyHands | 🎯 | Perfect windows +10% | `Ease` (client: TreatSession.Ease) |
  | | **TwinCounters** (capstone) | 👯 | treat the 2nd in line too (§E6) | `TwinCounters` |
  | ⚡ Speed | NimbleFingers | ⚡ | MakeSpeed +10% | `MakeSpeed` |
  | | QuickFeet | 👟 | walk +1 (16 → 19) | `Walk` |
  | | ExpressLift | 🛗 | lift rides −20% (2 s → 0.8 s) | `Lift` |
  | | **DoubleShift** (capstone) | ⏩ | every nurse works 25% faster | `DoubleShift` |
  | 🍀 Fortune | LuckyCoins | 💰 | Cash +10% | `Cash` |
  | | StarShine | ⭐ | Stars +10% | `Stars` |
  | | Bargain | 🏷️ | belt + Agency prices −5% | `Bargain` |
  | | **LuckyStock** (capstone) | 🍀 | +2 Agency nurses of your own each restock, same shown odds (§E5) | `LuckyStock` |
- **✚ `Themes`** `{ [ThemeId]: { Name, Icon, Rebirths, Wall, Roof, Trim (hex), Prop } }`:
  Candy 🍬 (0, today's look) · Arctic ❄️ (R1, `#EAF6FF`/`#7FC8FF`/`#FFFFFF`, Icicles) · Jungle 🌴 (R2,
  `#CFF5C0`/`#3DBE5A`/`#FFE07A`, Palm) · Space 🚀 (R3, `#D9D2FF`/`#5B4BD6`/`#FFD84A`, Rocket) · Ocean 🐚 (R4,
  `#C8F4F0`/`#26B5C9`/`#FFB3C7`, Shell) · Royal 👑 (R5, `#FFF4D6`/`#F2B705`/`#B04CFF`, Crown). A rebirth switches
  you to the newest unlocked theme. You can pick any unlocked one later (`SetTheme`).
- **`Levels`**: `Slots` is **removed** (the roster replaces it). `Floors`, `Beds`, `Departments` and `Unlocks` change:

  | Lv | Floors (walkable above ground) | Beds (Stand + ward) | Departments open | Unlock chips |
  |---|---|---|---|---|
  | 1 | 0 | 1 | Reception | – |
  | 2 | 1 | 3 | + AE, Wards | 🚑 A&E ambulances · 🛏️ Wards upstairs · 🛗 Lift · 🧪 2-item recipes |
  | 3 | 2 | 3 | + Hydro | 🛁 Hydro hot tub · 🔀 Pick the floor · ✚ Big sign · 🌻 Garden |
  | 4 | 3 | 4 | + Pharmacy | 💊 Pharmacy · 🛏️ 4 beds · 🏢 3 floors |
  | 5 | 4 (the 4th is the roof) | 4 | + Roof | 🚁 Helipad · 🗼 Tower · ✨ Neon sign · 🏢 New branches |
  Costs, ⭐ gates, recipe caps, the line (3) and spawn seconds are unchanged.
- **`Items`** gains four medicines (a `Medicine = { A, B }` field and a `Tier`), and their mini-game is 🧪 Pour.
  - Tier 1: WarmTonic 🍵 (Potion + Cocoa) and SoapyPatch 🧽 (Bubbles + Plaster).
  - Tier 2 (from R2): SuperSyrup 🍯 (Potion + Plaster) and CocoaFizz 🥤 (Cocoa + Bubbles).
- **`Stations`** gains `Pharmacy = { Name = "Pharmacy", Icon = "💊", Item = "", Craft = true, Color = Candy.Mint }`
  (Palette.Candy has no Green; Mint differs from the four station colours and from the patience ring's colours).
  `Data.spec` checks it by reading the source, as for Color3 data.
- **`Upgrades`** gains three rows with gates. `Level` = the hospital level needed; `Rebirths` = the rebirths needed:

  | Upgrade | Icon | Hint | Prices | Gate | Effect per level |
  |---|---|---|---|---|---|
  | WardComfort | 🛏️ | Patients rest faster | 800 · 2,500 · 6,000 | Lv 2 | rest −20%, cure 💰 +5% |
  | AESpeed | 🚑 | Ambulances come sooner | 1,000 · 3,000 · 8,000 | Lv 2 | 🚑 wait +15%, come 10% sooner |
  | NightClinic | 🌙 | Night cures pay more | 1,500 · 4,000 · 9,000 | R4 | night cure 💰 +25% |
- **Content (placeholder names and looks, all original; the brothers rename them, OPEN #1).**
  - `Ailments` + `AilmentActing`, kid-safe, with existing acting vocabulary only:
    - **Pollen** 🌼: Remedy, recipe 🧪🛁; a sneeze with a yellow puff.
    - **Prickles** 🌵: Plaster, recipe 🩹☕; tugs at a cartoon thorn.
    - **Airsick** 💫: Remedy, recipe 🧪☕🩹; a dizzy sway with circling stars.
  - `Wings`:
    - **Sunny** 🌻: from R1. Patients DaisyDoodle and BuzzBun (Pollen), ThistleTot and CactusCub (Prickles). Set
      reward `SunflowerArch`. They come from the start of a branch, using whatever stations you have.
    - **Sky** 🚁: from R2, only by helicopter. Patients CometKite, NimbusNarwhal and PuffinPilot (Airsick). Set
      reward `CloudSwing`.
    - Wings gain `Rebirths: number?` and `Only: "Helicopter"?`.
  - `Variants`: **Golden** 🌟 (`Rebirths = 3`; `Config.GoldenChance` and `GoldenMultiplier`).
  - `Decor` gains the two wing rewards and five Branch Trophies (`EarnedBy = "Rebirth"`, existing DecorBuilder
    kinds): TrophyCup R6 · TrophyStar R7 · TrophyGlobe R8 · TrophyRocket R9 · TrophyCrown R10.
- **`Badges`** gains 🏢 **Branches** (Clinic): Stat `"Rebirths"` (derived from `Rebirth.Count`), thresholds 1 · 2 · 3
  · 5 · 8 · 12, Boost `{ Kind = "Stars", Percent = 2 }` per tier (+12% at Mythic, inside `BoostCaps.Stars` 50).
  The derived 🏠 Builder stat becomes rooms owned + `Stats.RoomsBefore` + decor owned, so a rebirth never empties its
  bar.

### B6. Config (exact numbers; `src/shared/Config.luau`)
```lua
Config.Roster = { Base = 3, PerRebirth = 1, Max = 8 }               -- memory-019; Max for perf (§E1)
Config.Nurses = {                                                   -- v3 keys kept, these change or are new:
  MaxLevel = 10, LevelCapRebirths = 3, LevelCapBonus = 5,           -- Lv 10; Lv 15 from R3 (memory-019 R3)
  FasterPerLevel = 0.05,                                            -- was 0.08 over 5 levels; Lv 10 = x0.55
  CheerPerLevel = 0.02,                                             -- was 0.03
  SpecialtyBoost = 0.4,                                             -- design §7: "+40% speed there"
  MedicSeconds = { Common = 14, Rare = 12, Epic = 10, Legendary = 8, Mythic = 7, Secret = 6 },
  MedicPatience = { Common = 0.2, Rare = 0.25, Epic = 0.3, Legendary = 0.4, Mythic = 0.45, Secret = 0.5 },
  PorterSeconds = { Common = 5, Rare = 4.5, Epic = 4, Legendary = 3.5, Mythic = 3, Secret = 3 }, -- a trip's walk
  ReceptionArrive = { Common = 0.05, Rare = 0.08, Epic = 0.12, Legendary = 0.16, Mythic = 0.18, Secret = 0.2 },
  ReceptionPerLevel = 0.005,
}
Config.NurseXP = { PerCure = 1, Specialty = 1, FastLearners = 2 }   -- xpToNext(L) = 10 + 5L(L+1); a copy = 1 level
Config.Abilities = { CooldownStep = 0.85, UpgradeLevels = { 5, 10 }, MinCooldown = 20, SecondWind = 0.8 }
Config.Rebirth = {
  MinLevel = 5,
  Cost = { 50000, 75000, 110000, 170000, 250000, 380000, 570000, 850000, 1300000, 1900000 },
  Growth = 1.5,                     -- past the table: x1.5 a rebirth, rounded to 2 significant figures
  CashPerRebirth = 0.25, StarsPerRebirth = 0.25, MaxBonusRebirths = 20,   -- added: R4 x2, R20 x6 (§E12)
  PointsPerRebirth = 3, OfferSize = 3, StartCash = 0,
}
Config.BranchCaps = { Cash = 30, Stars = 30, Tips = 30, MakeSpeed = 30, Patience = 50 } -- the tree + perks, percent
Config.Agency = {
  RestockSeconds = 300, Slots = 4, LuckySlots = 2,
  Odds = { Common = 70, Rare = 26, Epic = 4 },                      -- percent; never Legendary+ (design §8)
  PriceMultiplier = 1.5, SellBack = 0.3, Cooldown = 1,
  Offset = Vector3.new(11, 0, 12),                                  -- the kiosk, from Town.Origin (row-2 plaza side)
}
Config.Market = {
  Fee = 0.1, BandMin = 0.5, BandMax = 3, LevelStep = 0.1, Round = 10,
  MaxPerSeller = 3, MaxListings = 30, ListCooldown = 5, BuyCooldown = 2,
  Offset = Vector3.new(-11, 0, 12),
}
Config.Belt.MinRebirths = { Mythic = 1, Secret = 1 }               -- design §7: Mythic/Secret after the first rebirth
Config.Lift = { RideSeconds = 2, CarDistance = 6, Cooldown = 1, EscortWait = 6 }
Config.AE = { EverySeconds = 150, Jitter = 0.2, FirstSeconds = 60, PatienceMultiplier = 0.6, CashMultiplier = 3,
  Stars = 2, MinItems = 2 }
Config.VIP = { EverySeconds = 300, Jitter = 0.2, CashMultiplier = 4, Stars = 3 }
Config.Triage = { Seconds = 4, RightBonus = 0.1 }
Config.Escort = { CashBonus = 0.2, RecoverFactor = 0.5 }
Config.Hydro = { Spots = 2, CashBonus = 0.25, RecoverFactor = 0.5 }
Config.Pharmacy = { HoldSeconds = 3, Tier2Factor = 0.5 }
Config.WardComfort = { RecoverPerLevel = 0.2, CashPerLevel = 0.05 }
Config.AESpeed = { PatiencePerLevel = 0.15, SoonerPerLevel = 0.1 }
Config.NightClinicPerLevel = 0.25
Config.NightOwl = 0.3                                               -- of Config.NightSeconds
Config.GoldenChance = 0.02                                          -- R3+ owners' patients (1 in 50)
Config.GoldenMultiplier = 5
Config.Leaderboards.Boards = { "Cured", "Stars", "Hearts", "Week", "Rebirths" }  -- WorldBoards stays the 4
```

#### B6.1 The numbers, and why
Claude's tuning, open to change after playtests (like memory-020). The income figures are **estimates** from
`Logic/Pay` at an assumed ~4 cures a minute on a busy Lv 5 clinic, not measurements. The first playtest should time
real cures a minute at Lv 3 and Lv 5 (P22's session) and re-run the calculator if they're far off.

| Number | Value | Why |
|---|---|---|
| Rebirth cost | R1 💰50,000; ×1.5 each, rounded (75k, 110k, 170k, 250k, 380k, 570k, 850k, 1.3M, 1.9M) | A busy Lv 5 clinic earns about 20,000/hour of active play (≈ 4 cures/min × ~85 💰). R1 is then ~2.5 h after reaching Lv 5, on top of ~5 h to build the first branch (levels 21,900 + rooms 1,750 + upgrades 11,850): about a week of daily play. With +25% a rebirth, the `roblox-simulator-economy` calculator gives each branch's wait ×1.20–×1.38 the last (2 h 31 m at R1 … 1 d 5 h at R10), inside its ×1.2–×1.5 target, so every branch feels a little bigger, never a wall |
| Rebirth bonus | +25% 💰⭐ each, added, up to 20 | The design's number. Added keeps R10 at ×3.5, not ×9.3: kids still feel each one, and Pay stays in safe numbers |
| Tree points | 3 a rebirth; 33 fill the tree | Every rebirth buys a visible upgrade, and the whole tree takes ~11 branches: a long goal |
| Branch caps | Cash/Stars/Tips/MakeSpeed 30%, Patience 50% | The tree's 3 ranks × 10% each, plus Patient Pals' 20%. Their own caps, beside `BoostCaps` (badges + ranks), so badges never waste tree points and neither can run away |
| Roster | 3, +1 a rebirth, max 8 | memory-019. 8 = R5; each nurse is up to 40 parts and every one works on the plot (§E1) |
| Nurse XP | to next = 10 + 5·L·(L+1): 20, 40, 70, 110, 160, 220, 290, 370, 460 (1,740 to Lv 10); then 560 … 1,060 (5,740 to Lv 15) | 1 XP per cure for each working nurse (+1 for its specialty). At ~4 cures/min that's Lv 5 in about an hour, Lv 10 in 4–7 h, Lv 15 in 12–24 h: a nurse grows with you, never in one sitting. A copy = one whole level, so the belt still matters |
| Stats per level | Makers/Healers/Medics 5% faster a level (Lv 10 ×0.55, never under 3 s); Cheerers +2% | v3's 8% over 5 levels would hit the 3 s floor by Lv 8 at Common; this spreads the climb over 10–15 levels |
| Ability cooldowns | 60–240 s; ×0.85 at Lv 5 and Lv 10 | A Common's trick shows about once a minute, a Legendary's every 2–3 min, and the Secret's Miracle once an in-game day: rarer is stronger, not more often |
| Team bonus | 2 = small (+10% 💰 / 20–25%), 3+ = big (double) | With 3–4 nurses, a pair is a real choice and a trio is a goal |
| Agency odds | Common 70 · Rare 26 · Epic 4 | "Mostly Common/Rare, sometimes Epic". An Epic in some slot about every 6–7 restocks (≈ 33 min), rarer than the belt's Epic (~1 per 15 min), because the Agency is the calm way to get one |
| Agency price | ×1.5 the belt's, at your level (Common 150, Rare 600, Epic 2,250 at Lv 1) | design §8; the belt stays the cheaper race |
| Sell-back | 30% of the belt base, per copy (30 / 120 / 450 / 1,800 / 6,000 / 15,000) | design §8 ("about 30%"); never level-scaled, so nothing can be bought and sold back for profit |
| Market bands | 50%–300% of the belt base × (1 + 0.1 × (Level − 1)), to 10s. Lv 1: Common 50–300 · Rare 200–1,200 · Epic 750–4,500 · Legendary 3,000–18,000 · Mythic 10,000–60,000 · Secret 25,000–150,000. Lv 10 ×1.9, Lv 15 ×2.4 | The floor stops "give me your Legendary for 💰1" scams. The ceiling stops cash being passed between friends through a Common and stops a kid being overcharged. A levelled nurse is worth more |
| Market fee | 10%, max 3 listings each, 30 a server | design §8 (a cash sink); small lists for small rosters |
| A&E | an ambulance about every 150 s (±20%) at Lv 2+; waits ×0.6; pays ×3 + 2 ⭐ | ~1 in 12 patients at Lv 2's pace: special, not constant. "Waits less, pays ×3 + Stars" is the design's |
| Air ambulance | every 300 s (±20%), R2 + Lv 5; pays ×4 + 3 ⭐; Sky wing pages | a rarer treat for the top of a branch |
| Escort / hot tub | +20% / +25% 💰, rest ×0.5; escort wait 6 s, triage 4 s | Small, felt bonuses for the fun extras; never needed to cure |
| Golden patients | 2% (1 in 50) at R3+, ×5 💰 | A shiny every 10–15 minutes of play: a nice surprise, not a grind |
| Department upgrades | 800–9,000 💰, 3 levels | Priced between the Lv 2 and Lv 4 costs, so each branch has new things to buy |

### B7. Logic APIs (pure: no Roblox services, no requires; `cfg` = Config passed in; specs in `tests/`)
- **`Logic/Schema`** (v4): `default()`, `reconcile(saved, today?)`, `isNewer(saved)`, `levelFromRooms(rooms)`,
  `xpToNext(level)`, `rosterCap(count)`, `levelCap(count)`, `VERSION = 4`, the constants in §B1.
- **`Logic/Nurse`** (changed):
  - `xpToNext(level)`, `levelCap(rebirths, cfg)`, `rosterCap(rebirths, cfg)`.
  - `addXP(entry, xp, cap): (entry, levelsGained)`: a copy; XP past the cap is dropped.
  - `hire(entry?, cap, cfg): (entry, isNew, levelledUp)`: a copy adds `xpToNext(Level)` XP, i.e. exactly one level.
  - `stats(job, rarity, level, cfg, specialty: boolean?): { Every: number?, Patience, Tip, Arrive, Urgent }`.
  - `working(nurses, cap, isKnown): { NurseId }`: Job ≠ "Rest", known, by NurseId, at most `cap`.
  - `canAdd(data, nurseId, cfg, isKnown?): (ok, message)`: a copy is ok unless at the level cap ("Max level!"); a new nurse
    needs roster room ("Roster full: sell or list one").
  - `setJob(nurses, nurseId, job, level, cap, jobs, role?): (ok, message, nurses)` (`role` = the nurse's Data Role,
    so a job equal to it saves as `""`). Also `owned(nurses, isKnown?)`: how many nurses a save owns (the roster
    count; resting ones count).
  - `mark`, `journal`, `setsDue`: as v3, but rebirth-only nurses (`Source`) are left out of every rarity group and of
    `Percent`.
  - `bestCheer`, plus `best(list, field)`. **`equip` is removed.**
- **✚ `Logic/Jobs`**:
  - `open(jobId, level, jobs): boolean`.
  - `effective(job, role, level, jobs): JobId | "Rest"`: `""` → role; not open → role.
  - `department(jobId, stationId?, jobs, stations?): DeptId`.
  - `patientDepartment(wing, urgent): DeptId`.
  - `teams(specialties: { string }, departments): { [DeptId]: number }`.
  - `teamEffects(counts, departments): { Cash: number, Urgent: number, Recover: number, Make: { [StationId]: number } }`.
- **✚ `Logic/Abilities`**:
  - `tier(level, cfg): 0 | 1 | 2`.
  - `strength(abilityId, level, abilities, cfg, secondWind: boolean?): { Kind, Cooldown, Value, Seconds?, Game? }`.
  - `useful(kind, view): boolean`, where `view = { FrontPatience, LowCount, Waiting, Missing, TrayRoom,
    NearStation, OnCooldown }`.
  - `ready(readyAt, now)`.
  - `autoGames(games, charges: { Game: string?, Count: number }): ({ boolean }, chargesLeft)`. `charges` may also be a
    list of them (QuickBandage and GoldenTouch banked at once): a charge for that very game is spent before an
    any-game one; the result keeps the shape it was given.
- **✚ `Logic/Rebirth`**:
  - `cost(count, cfg)`: the next rebirth's cost, given `count` done.
  - `canRebirth(data, cfg): (ok, message)`: "Need 🏙️ Lv 5", "Need 💰50,000", or "".
  - `multiplier(count, cfg)`: 1 + 0.25 × min(count, 20).
  - `apply(data, cfg, offer, content): ApplyResult`: **mutates `data` inside `PlayerData.update`**. `content` =
    `{ Perks, Themes, Nurses, Decor }` (the Shared/Data modules: the start perks, the newest theme, the rebirth-only
    nurse and the trophy come from them). It returns `{ Count, Theme, Unlocks, Pending, Trophies, RoomsReset }` for
    the celebrations (Task 0 added the 4th argument and the result):
    - count +1 and points +3; `Offer` = offer;
    - cash → `StartCash` (or SeedMoney); upgrades → 0 (or WarmUp); `Level` → 1 (or ClinicStart);
    - `Rooms` → `{ Stand }` (+ BathRoom with BathReady); `Decor.Placed` keeps only the slots of rooms still owned (the
      Stand's, + the BathRoom's with BathReady); `Stats.RoomsBefore`
      += rooms reset;
    - `Theme` → the newest unlocked; `Pending` += the nurse unlocked at this count (unless owned or already pending);
      `Decor.Owned` += the Branch Trophy of this count (R6-R10; it only ever adds, so the trophy lands in the same
      ONE update).
    - Never touches Book, Story, Nurses, NurseIndex, JournalSets, Stars, Cured, Badges, Stats (but RoomsBefore),
      Playtime, Boosts, Decor.Owned (but that trophy), Daily, Mailbox, Hearts*, WeekCures, Tutorial or Simple.
  - `offer(owned, pool, r01s): { PerkId }`: up to 3 distinct unowned cards, evenly random; `{ "TreePoints" }` when
    none are left.
  - `choose(data, perkId, perks, cfg?): (ok, message)`: mutates (`cfg` for SeedMoney's `StartCash`). A BathReady chosen
    now owns the BathRoom in the save: T2 then calls `Plots.syncRooms`, which adds rooms the save owns but the plot
    lacks as well as removing the others.
  - `unlocks(count): { string }`: the ids NEW at exactly that count (`has` answers "at or before"); `UNLOCKS[id]` =
    `{ Icon, Text, Rebirths }` for the chips. Ids: `MythicSecret`, `SunnyWing` (R1), `Helicopter`, `Pharmacy2` (R2), `Golden`,
    `LevelCap15` (R3), `NightClinic` (R4), `FounderFennec`, `Mascot` (R5), `Trophy<n>` (R6–R10).
  - `has(count, unlockId): boolean`.
  - `themes(count, themes): { ThemeId }`; `theme(data, themes): ThemeId`.
  - `effects(data, cfg, perks, tree): Effects`. The flat merge of perks and tree: `{ Patience, Tips, Ease,
    MakeSpeed, Walk, Lift, Cash, Stars, Bargain, Arrive, XP, NightOwl, Tray, BeltScout, SirenPro, Recharge,
    TwinCounters, DoubleShift, LuckyStock }`.
  - `KEEP`, `RESET`, `GET`: the keep/reset screen's rows (icon + ≤ 3 words each).
- **✚ `Logic/Tree`**: `canBuy(tree, points, nodeId, nodes): (ok, message)`; `buy(tree, points, nodeId, nodes): (tree,
  points)`; `refund(tree, nodes): number` (unknown nodes at 1 a rank); `spent(tree, nodes, branch)`; `effects(tree,
  nodes)`.
- **✚ `Logic/Agency`**:
  - `restock(uptime, cfg): number`.
  - `roll(roster, cfg, r01s, slots?, taken?): { NurseId }`: distinct, by odds, never `Source`; two r01s a slot; a
    rarity with nobody left falls to the next lower; never one in `taken`.
  - `personal(roster, cfg, userId, restock, owned): { NurseId }` (`owned` = the shared stock's nurses this restock,
    never repeated unless every nurse of the rolled rarity is in it, so the shown odds stay true (integration); it
    must not depend on anything the player can change, or a buy would re-roll it): a seeded roll
    (`seeded(seed, n)`; it takes no Random object: the
    seed makes the r01s).
  - `price(cfg, rarity, level, bargain)`, `sellBack(entry, rarity, cfg)`, `odds(cfg)`.
- **✚ `Logic/Market`**: `band(cfg, rarity, level): (min, max)`, `valid(price, min, max)` (a whole number),
  `fee(price, cfg)`, `canList(data, nurseId, mine, total, cfg, roster): (ok, message)`, `canBuy(buyer, listing, owns,
  cfg, roster, rebirths): (ok, message)`.
- **✚ `Logic/Hospital`**:
  - `floors(level, levels)`, `departments(level, levels)`.
  - `route(wing, urgent, level, levels): DeptId`: "Hydro" for a Bath-wing patient once Hydro is open, else "Wards".
  - `triageOptions(level, levels): { DeptId }?`: two or more departments to send to, else nil.
  - `urgentRecipe(recipe, items, cap): { ItemId }?`: at least `MinItems`; pads a 1-item recipe with the other
    Stand item (🧪 ↔ 🩹).
  - `arrival(base, factors): number`, `recover(base, factors): number`.
  - `nightOwl(nightEndedAt, now, cfg): boolean`.
- **`Logic/Boosts`**: `percent(effects, timed, defs, kind, scopes?, caps, branch?, branchCaps?)`. That is
  `min(permanent, caps) + min(branch, branchCaps) + timed`. `summary` gains a branch part.
- **`Logic/Pay.reward`** gains optional args, applied in this order after v3's factors:
  - `Urgent` ("AE" ×3 / "VIP" ×4).
  - `NightClinic` (level; night only, ×(1 + 0.25L)).
  - `Variant` "Golden" (×5).
  - `Extra` (≥ 1, ≤ `Pay.MAX_EXTRA` = 5).
  - `BonusStars` (0..10, added before the Stars boost).
  - The rebirth multiplier is **not** a Pay arg: `Server/Boosts.multiplier` folds it into CashBoost/StarsBoost (§B8).
- **`Logic/Recipe`**:
  - `match(recipe, done, have, medicines?): ({ index }, used: { ItemId })` (`medicines` = Data/Items; `used` = the
    carried items it spends, so a medicine is taken once for two slots): exact items first. A medicine fills every missing slot its two
    ingredients cover, and is used only when at least one of them is missing.
  - `expand(itemId, medicines): { ItemId }`.
  - `craft(have, medicines, tier): MedicineId?`.
- **`Logic/MiniGame`**: `gameFor(medicineId) = "Pour"`. `accept(reported, games, elapsed, simple, cfg, auto?)`: auto
  games are always Perfect, and the minimum time skips them.
- **`Logic/Belt`**:
  - `gate(cfg, rarity, level, rebirths): string?`: "🏥 Lv 3" | "🏢 R1" | nil.
  - `pick` never picks a nurse with `Source`.
  - `canHire(entry, cfg, cap)` uses the level cap.
- **`Logic/Levels`**: `slots` removed; `floors`, `departments` added.
- **`Logic/Progress`**: `canBuyUpgrade(data, upgradeId, upgrades): (ok, message)` ("Needs 🏥 Lv 2", "Needs 🏢 R4").
- **`Logic/Prices`**: `capacity(trayLevel, bonus?)`.
- **`Logic/Leaderboard`**: board `Rebirths` (🏢 "Most Rebirths", caption "Branches", Purple), value
  `data.Rebirth.Count` (nil before v4).
- **`Logic/Badges`**: DERIVED `Rebirths`; `Builder` adds `Stats.RoomsBefore`.
- **`Logic/Admin`**: the ArgKind `"NurseId"`, `valid(action, arg, patients, boosts, nurses)`, and the actions in §B8.

### B8. Server module APIs
Signals are `Shared/Signal` (by reference). Every system has `start()`. Foundation stubs exist with these exact
signatures and safe defaults.

**T1 `Nurses`** (changed; `equip`/`slots`/`EquipNurse` are gone):
- `Nurses.start()`: wires `SetJob`. The plot's workers follow `Logic/Nurse.working` on every save change.
- `Nurses.rosterCap(p): number` · `Nurses.working(p): { NurseId }`.
- `Nurses.setJob(p, nurseId, job): (ok, message)`.
- **The one place a nurse joins or leaves a save:**
  - `Nurses.grant(p, nurseId, price, source: "Belt" | "Agency" | "Gift" | "Admin"): (ok, message)`. In ONE update:
    `canAdd`, charge, `hire` (new or +1 level), the "Hired" mark, any journal set due, and `Pending` removal for a
    Gift. Then `NurseNews` Hired, `Celebrate` NewNurse/JournalSet and the `Hired` signal.
  - `Nurses.take(p, nurseId, cash, reason: "Sold" | "Market"): (ok, message, entry?)`. In ONE update: remove the
    entry and add the cash. It refuses a listed nurse unless `reason == "Market"` (which also clears the listed
    lock), and refuses `Source` nurses. Then `NurseNews` Sold/Gone and the `Removed` signal; the worker poofs.
  - `Nurses.give(p, nurseId, entry, price): (ok, message)`. In ONE update: charge, add the exact Level/XP/Copies
    (`Job = ""`), the "Hired" mark and sets due. The Market's buyer side and its undo.
- **The Market's lock (in memory):** `Nurses.setListed(p, nurseId, listingId?)` and `Nurses.isListed(p, nurseId):
  boolean`. It is cleared on PlayerRemoving.
- `Nurses.onCure(owner, info: { Wing: string?, Urgent: string?, Dept: string? })`: +XP for every working nurse
  (`PerCure`, +`Specialty` on a match, ×2 with FastLearners). On a level-up: `NurseNews` Level and the
  `LevelUp` signal; at 5 and 10, `Celebrate` NurseLevel (Ability = true).
- `Nurses.team(plot): TeamEffects` · `Nurses.reception(plot): { Arrive: number, Triage: boolean }` ·
  `Nurses.medic(plot): { Patience: number }` · `Nurses.cheer(plot)` (unchanged). Each is mirrored on the plot
  attributes in §B4.
- **Porters** (Patients drives the patient; Nurses drives the porter):
  - `Nurses.claimPorter(plot): NurseId?`: a free Porter.
  - `Nurses.escort(plot, nurseId, to: CFrame): boolean`: yields while it walks.
  - `Nurses.releasePorter(plot, nurseId)`.
- `Nurses.trayItems`, `Nurses.takeFromTray`, `Nurses.markSeen`, `Nurses.healed` (unchanged).
- Signals:
  - `Nurses.Heal (plot, nurseId, target: "Front" | "Urgent")`: Healers serve the front, Medics the 🚑/🚁 patient.
  - `Nurses.Hired (p, nurseId, level)` · `Nurses.LevelUp (p, nurseId, level)` · `Nurses.Removed (p, nurseId)`.
- Admin hooks: `Nurses.adminLevels(p)` (+1 level each, to the cap) · `Nurses.adminGive(p, nurseId)` (`grant`,
  price 0, source "Admin").
- Requires never: Treatment, Patients, Abilities, Agency, Market, Rebirth. It may require `Lift` (porters ride).

**T1 `Abilities`** (✚): cooldowns, triggers, effects. It requires Nurses, PlayerData and Plots; **never** Patients,
Treatment, Cure or Stations.
- `Abilities.start()`: one loop per active plot (0.5 s), only while the owner is in the server and done with the
  tutorial. Cooldowns run in real seconds from the moment the ability fired. Miracle tracks in-game days (an
  `IsNight` true → false edge).
- `Abilities.Fired: Signal (plot, nurseId, abilityId, kind, value)`. Patients does RefillFront, RefillLine, CureLine
  and PauseLine; Abilities itself does TrayItem (`Nurses`), FastMake and InstantMake (plot attributes) and Recharge.
- `Abilities.consumePerfects(plot, games: { GameId }): { boolean }`: Treatment calls it at `TreatStart` (any helper
  at the plot).
- `Abilities.consumeCure(plot): { Cash: number, Stars: number }`: Cure calls it once per cure (×1 and +0 when
  nothing is banked).
- `Abilities.patiencePaused(plot): boolean` · `Abilities.makeFactor(plot): number` (1, 0.5, or 0 = the shortest
  hold).
- `Abilities.adminCharge(p)`: every ability ready now.

**T2 `Rebirth`** (✚): `Rebirth.start()` wires `OpenBranch`, `ChoosePerk`, `BuyNode`, `ResetTree`, `SetTheme` and
`ClaimBranchNurse`, and places the mascot (R5+; `NurseBuilder`/`CreatureBuilder.buildLook`, idle hops by the motion
contract, a spin on each cure at the plot). It also sets `WalkBoost` and the walk speed on CharacterAdded, the plot's
`Branches` and the sign's `BranchBadge`, and the once-ever `Told` toast.
- `Rebirth.count(p)` · `Rebirth.effects(p)` (= `Logic/Rebirth.effects` on the live save).
- `Rebirth.open(p, free: boolean?): (ok, message)`:
  1. The checks in §B3.
  2. `Patients.reopen(p)` (a treated patient cures on the spot first).
  3. Re-check.
  4. ONE update: `Logic/Rebirth.apply` with an offer rolled by the server's `Random`.
  5. `Plots.syncRooms(p)`.
  6. `PlayerData.saveNow(p)`.
  7. `Celebrate` Rebirth, then `Unlock` per new unlock; `Reborn:Fire(p, count)`.
- `Rebirth.Reborn: Signal (p, count)`.
- Admin hooks: `Rebirth.adminRebirth(p)` (= `open(p, true)`: no Lv 5, no cost) · `Rebirth.adminPoints(p)` (+3).

**T2 `Economy`**: `Purchase("Upgrade", id)` also checks `Logic/Progress.canBuyUpgrade`. Night Clinic, Ward Comfort and
A&E Speed sell like other upgrades. **`Carry`**: `Carry.capacity(p)` adds BigHands. **`Plots`**:
`Plots.syncRooms(p)` adds room models the save owns but the plot lacks (BathReady) and removes room models the save no longer owns and puts their placed decor away (the save already
did), then re-places Stand decor.

**T3 `Agency`** (✚): `Agency.start()` (the kiosk, restocks, `GetAgency`, `AgencyBuy`, `SellNurse`, `AgencyNews`) ·
`Agency.view(p): AgencyView` · `Agency.buy(p, slot, nurseId, expect)` · `Agency.sell(p, nurseId, expect)` ·
`Agency.restockNow()` (admin hook; it counts as a new restock index) · `Agency.Pure`.

**T3 `NurseBelt`** (changed):
- `hire` also checks `Logic/Belt.gate` with your rebirths ("🏢 R1 first!") and `Logic/Nurse.canAdd` (a clear message
  before `grant`).
- The price takes Bargain off.
- For 🔭 Belt Scout the next arrival is rolled one arrival early, with the odds on the sign at that moment (its
  `Event` says which). The result is sent with `BeltScout` to perk owners only.
- The sign's gate line says "🏥 Epic+ from Lv 3 · 🏢 Mythic/Secret from R1".

**T4 `Market`** (✚): `Market.start()` (the kiosk, `GetMarket`, `ListNurse`, `Unlist`, `BuyListing`, `MarketNews`,
listings removed on PlayerRemoving) · `Market.view(): MarketView` · `Market.list(p, nurseId, price)` ·
`Market.unlist(p, id)` · `Market.buy(p, id, price)` · `Market.Sold: Signal (listing, buyer)` · `Market.Pure`.
Requires Nurses and PlayerData; never Agency.

**T6 `Lift`** (✚): requires Plots and PlotBuilder; never Patients or Nurses.
- `Lift.start()` wires `RideLift`.
- `Lift.ride(p, floor): (ok, message)`: the checks in §B3, then the character's `PivotTo` to that landing after
  `RideSeconds` × the ExpressLift factor. The rider's own client plays the ding and slides the car (LiftPanel); the
  server sends nothing per frame.
- `Lift.carry(plot, models: { Model }, floor): boolean`: yields `RideSeconds`, one `PivotTo` each at the
  destination landing. Patients and porters use it.
- `Lift.landing(plot, floor): CFrame?`.
- `Lift.waitEscort(plot, seconds): Player?`: enables the ground landing's `EscortPrompt` and yields until a player
  who can work the plot triggers it, or the time runs out.

**T6 `Levels`** (changed): `Levels.slots` is removed. `Levels.floors(p)` and `Levels.departments(p)` are added. It
builds the building with the owner's theme and rebuilds on a theme change too.

**T6 `Stations`** (changed):
- The 💊 Pharmacy station takes two carried ingredients and gives one medicine (`Logic/Recipe.craft`; tier 2 from
  R2). Its hold is `Config.Pharmacy.HoldSeconds`, ×0.5 at tier 2.
- Every hold time × `Nurses.team(plot).Make[station]` × `Abilities.makeFactor(plot)`, never below
  `Config.BoostMinMakeSeconds`.

**T6 `PlotBuilder`** (changed): `buildBuilding(plotModel, level, grewFrom?, theme?)` per §B4, and the sign's
`BranchBadge`.

**T7 `Patients`** (changed): every §6 flow in §C T7. New admin hooks: `Patients.adminAmbulance(p)` and
`Patients.adminHelicopter(p)`. It uses `Lift`, `Nurses` (porter, reception, medic, team), `Abilities` (Fired,
patiencePaused), `Levels`, `Treatment`, `Cure`, and `Logic/Rebirth.effects` on the owner's save.

**T7 `Treatment`** (changed):
- `Treatment.open(p, spec)` gains `spec.Kind` ("Treat" | "Soak") and `spec.Medicines`. It asks
  `Abilities.consumePerfects` and sends `Auto` and `Ease`.
- The `Triage` remote, `Treatment.waitTriage(p, session, options, right): DeptId` (yields up to
  `Config.Triage.Seconds`).
- Medic deliveries through `Nurses.Heal` with target "Urgent".

**T7 `Cure`** (changed):
- `ctx.Extra × Abilities.consumeCure(plot).Cash`, `BonusStars` (+urgent/VIP stars + StarBurst), `Urgent`,
  `NightClinic` (the owner's upgrade) and the Golden variant go to `Pay.reward`.
- Then `Nurses.onCure(owner, { Wing, Urgent, Dept })`, guarded like every step.

**Foundation `Boosts`**: `Boosts.multiplier(p, "Cash" | "Stars", scopes)` = (1 + capped badge part + capped branch
part + timed) × `Logic/Rebirth.multiplier(count)`. Other kinds take no rebirth factor. `Boosts.list` adds `Branch`
(the capped percent per kind) and `Rebirth` = `{ Cash, Stars }` (the two multipliers; Task 0 made it a pair)
(percent per kind) and `Rebirth` (the multiplier).

**Foundation `PlayerData`**: `PlayerData.isOpen(p): boolean` (loaded, not closing) · `PlayerData.saveNow(p): boolean`
(yields; writes now if this session owns the lock; never runs two writes for one player at once) · *(integration)*
`PlayerData.writeAfter(first, second)` (never yields: `second`'s next writes wait, at most 10 s, until `first`'s
changes so far have landed; the Market's seller → buyer order).

**Foundation `Admin`** (new actions; each calls the hook named, which is stubbed until its owner lands):

| Button | Action (`arg`) | Calls |
|---|---|---|
| 🏢 Rebirth now | `Rebirth` | `Rebirth.adminRebirth` (free: no Lv 5, no cost) |
| 🌳 +3 points | `AddTreePoints` | `Rebirth.adminPoints` |
| 🏢 Restock Agency | `RefillAgency` (server-wide: alone or Studio) | `Agency.restockNow` |
| ⬆️ Nurse levels | `NurseLevels` | `Nurses.adminLevels` |
| 🎁 Give nurse… | `GiveNurse` (a Data/Nurses id) | `Nurses.adminGive` (roster rules apply) |
| ✨ Charge abilities | `ChargeAbilities` | `Abilities.adminCharge` |
| 🚑 Ambulance | `SpawnAmbulance` | `Patients.adminAmbulance` (Lv 2+) |
| 🚁 Helicopter | `SpawnHelicopter` | `Patients.adminHelicopter` (Lv 5; no R2 needed) |

### B9. Client
**ctx** (`Types.Ctx`): unchanged, plus `ctx.Data.Jobs`, `Departments`, `Abilities`, `Perks`, `Tree` and `Themes`.

**Module load order** (`Main.client`): UI `Toasts, Hud, Shop, BookPanel, DayReportPanel, Mailbox, PlayGifts,
BadgeBook, Guide, PromptFilter, AdminPanel, Boards, Celebrate, MiniGames, NursePanel, BeltView, AgencyPanel,
MarketPanel, BranchPanel, LiftPanel, Tutorial`, then Feel `Sounds, CureFX, Atmosphere, CreatureMotion,
CreatureActing, HospitalFX`.

**Bus events** (new; the old ones are unchanged):

| Event (args) | Fired by | Heard by |
|---|---|---|
| `Open ("Nurses", "Team" \| "Branch" \| rarity)` | Hud, anyone | T5 NursePanel ("Team" = your roster page, "Branch" = the 🏢 rebirth-only Journal page) |
| `Open ("Branch", "Open" \| "Perks" \| "Tree" \| "Themes")` | T5 Shop (Hospital tab), T8 Celebrate (after a rebirth: "Perks") | T5 BranchPanel |
| `Open ("Agency", "Hire" \| "Sell"?)` · `Open ("Market", "Buy" \| "Sell" \| "Mine"?)` | T5 NursePanel, the kiosks' prompts (client `ProximityPromptService.PromptTriggered`) | T3 · T4 |
| `Sell (nurseId)` · `List (nurseId)` | T5 NursePanel's card buttons | T3 AgencyPanel (sell confirm) · T4 MarketPanel (list flow) |
| `Open ("Lift", floors)` | T6 LiftPanel itself (a `LiftPrompt`'s client `Triggered`) | T6 LiftPanel |
| `AgencyNews (view)` · `MarketNews (view)` · `BeltScout (info)` | Main.client (remotes) | T3 · T4, T5 · T3 |
| `NurseNews (info)` · `Celebrate (info)` | Main.client (remotes) | T5, T8 · T8 |

**Sound cues** (T8 adds them to `Sounds.CUES`): `Rebirth`, `Perk`, `Node`, `Ability`, `Siren`, `Heli`, `Ding`,
`Sold`, `Bought`, `Restock`, `Triage`, `Splash`, `Brew`, `LevelNurse`.

**Hud hooks (Foundation adds; T8 restyles, keeps the names):**
- `Hud.shopNews(data, state)` gains `Branch: boolean`: a perk card waiting or unspent tree points (a reward to
  claim). **Never** "you can rebirth" (no pressure, red line 3). The 🛒 dot follows it.
- Nothing else new on the HUD: the Branch panel lives in the Shop's 🏥 tab, and the Agency and Market live in the
  👩‍⚕️ panel and the kiosks. The seven bottom tabs stay seven.

**Kit additions (Foundation first versions; T8 owns and juices them):**
- `Kit.ring(parent: GuiObject, color: Color3): (fraction: number) -> ()`: a filling ring (ability cooldowns). It
  never prints seconds.
- `Kit.holdButton(button: TextButton, seconds: number, onDone: () -> ()): () -> ()` (it returns stop): hold-to-confirm with a fill (Open branch,
  selling Epic+); instant fill with reduced motion, same hold.

### B10. Server boot order (`Main.server`)
`PlayerData → State → Events → Plots → Carry → Economy → Levels → Lift → Progress → Book → Story → Daily → DayReport →
Tutorial → Boosts → Badges → Playtime → Stations → Nurses → Abilities → Treatment → Patients → NurseBelt → Agency →
Market → Rebirth → Visits → Leaderboards → DayNight → Admin`.

Requires never loop:
- Patients → Treatment → Abilities → Nurses → (Lift, Levels) → (PlayerData, Plots, Economy, PlotBuilder).
- Stations → Abilities, Nurses. Cure → Abilities, Nurses.
- NurseBelt, Agency, Market → Nurses. Rebirth → Patients, Treatment, Nurses, Plots.
- Admin → everything. No module requires Rebirth, Agency, Market or Admin.

---
## C. Tasks
### Task 0: Foundation (lead, first, then frozen)
Done 2026-11-16 (commit "Progression v2 foundation: schema v4, contracts, data, logic, stubs"; 650 Lune specs pass).
**Foundation notes for T1-T8** (what Task 0 decided where the plan was silent; the contract text above says the same):
- Every new RemoteFunction answers `(false, "Coming soon!")` on the server until its system calls `Remotes.serve`
  (Shared/Remotes), so no client ever waits on an unanswered RemoteFunction.
- Existing task-owned files got only what booting needs, each marked `FOUNDATION` or `-- STUB (T<n>)`: Nurses (no
  Equipped; `working` and `grant(p, id, price, source?)` are real, the rest are stubs), NursePanel (the strip shows the
  roster; Equip on a resting nurse asks `SetJob` with its role), Shop (the ladder shows floors), Levels (`floors`,
  `departments`), Patients (`adminAmbulance`/`adminHelicopter`, and patients of a wing with `Rebirths`/`Only` never
  come until T7), Treatment (`waitTriage` answers `right`), Plots (`syncRooms`). The lead's Daily keeps Today's
  Visitor off those wings.
- `Data/Abilities.Miracle` has `Cooldown = 600` (only the ring's length) and `Daily = true`.
- `Logic/Schema` names the tree rank cap `MAX_NODE_RANK` (10): `MAX_RANK` was already the Doctor rank cap.
- `Logic/Pay`'s urgent multipliers come from `cfg.AE.CashMultiplier` and `cfg.VIP.CashMultiplier`.
- `Hud.shopNews(...).Branch` counts tree points only when some node can take them, so a full tree never dots.
- [x] This plan. `Config` (§B6), `Types` (§B3), `Remotes` (the new events and functions; `EquipNurse` removed),
  `Palette` (the theme colours, if any are new).
- [x] Schema v4 and migration (§B1), with specs:
  - v2 → v4 and v3 → v4: 16 nurses, 5 equipped → 3 work in Equipped order and the rest "Rest"; XP 0; `Job ""`.
  - Junk in every new field. `isNewer` for v5. Day clamps unchanged.
- [x] Data (§B5): Nurses, ✚ Jobs, ✚ Departments, ✚ Abilities, ✚ Perks, ✚ Tree, ✚ Themes, Levels, Items, Stations,
  Upgrades, Ailments + AilmentActing, Patients, Wings, Variants, Decor, Badges. `Data.spec` covers:
  - every id each table references exists;
  - every nurse has a Specialty and an Ability;
  - the perk and node texts are ≤ 6 words;
  - the new acting uses only the vocabulary.
- [x] Logic (§B7) with Lune specs: Nurse (XP curve values, caps, `hire` on a copy, `canAdd`, `working`, `setJob`,
  journal without `Source`), Jobs, Abilities, Rebirth, Tree, Agency, Market, Hospital, Boosts, Pay, Recipe, MiniGame,
  Belt, Levels, Progress, Prices, Leaderboard, Badges, Admin. Two specs are required:
  - **`Rebirth.apply`:** a table test of every save field, kept or reset.
  - **`Market.band`/`fee`:** the B6.1 table.
- [x] `State` (Rebirth, v4 Nurses, no Equipped), `PlayerData` (`isOpen`, `saveNow`), `Boosts` (the branch source and
  the rebirth multiplier), `Admin` + `AdminPanel` (§B8 actions, a 🏢 page and a nurse picker page),
  `Main.server`/`Main.client` (§B9/§B10; forward `AgencyNews`, `MarketNews`, `BeltScout`; the default snapshot).
- [x] Stubs for every ✚ module (§A) with the §B8/§B9 API and safe defaults. Stubs for the new hooks in existing files
  owned by tasks (e.g. `Patients.adminAmbulance` answers `false, "Coming soon!"`), each marked `-- STUB (T<n>)`.
- [x] The Hud hook (`shopNews.Branch`), `Kit.ring` and `Kit.holdButton` first versions.
- [ ] Boot in Studio once: `[Main] Clinic is open.`, no red errors (the lead, at integration: T0 had no Studio).
  All specs pass (done).

### T1: Nurse work (server). Load `roblox-luau`, `roblox-networking`.
- [ ] **Roster, not slots.** `sync` builds `Logic/Nurse.working(...)`. Resting nurses get no model.
  `SetJob` follows §B3 (cooldown 0.35 s).
- [ ] **`grant` / `take` / `give`**, each ONE update (§B8), and the in-memory listed lock (`setListed`, `isListed`).
- [ ] **Jobs.** Maker, Healer and Cheerer keep their v3 loops; stats come from
  `Nurse.stats(effectiveJob, rarity, level, cfg, specialtyMatch)`.
  - **Receptionist:** stands at the Counter's side ("Greeting"); writes `Reception` and `Triage`.
  - **Medic:** waits at the ambulance bay, fires `Heal (plot, id, "Urgent")` while a 🚑/🚁 patient is in line;
    writes `MedicPatience`.
  - **Porter:** idles by the ground landing; `claimPorter` / `escort` / `releasePorter`.
- [ ] **Specialty:** +40% speed or effect when its job works in its department (§B5). **Team bonuses:**
  `Nurses.team(plot)` and the plot attributes.
- [ ] **XP:** `onCure` (§B8), `LevelUp`, and the `NurseNews` / `Celebrate` at Lv 5 and 10. DoubleShift: every
  `Every` ÷1.25.
- [ ] **✚ Abilities** (§B5 table, §B8 API):
  - It fires by itself only when `useful`.
  - The nurse model gets `AbilityReadyAt`, `AbilityCooldown` and `AbilityAt`; NurseBuilder shows a small ring
    billboard and a sparkle (ring only within 40 studs; sparkles off with reduced motion, client-side as v3).
  - SecondWind ×0.8; TeamSpirit recharges the others.
  - Nothing fires while the owner is away or in the tutorial.
- [ ] **NurseBuilder:** a job hat icon on the task bubble and the ability ring billboard; ≤ 40 parts per nurse as
  before.
- [ ] Specs (`NurseWork.spec`, pure blocks):
  - working/rest picking, team counts, the usefulness views;
  - `grant` to a full roster, `take` of a listed nurse, `give` and its undo against a mocked PlayerData;
  - XP across two levels.

### T2: Branches (rebirth, server). Load `roblox-datastores`, `roblox-simulator-economy`.
- [ ] **✚ Rebirth** (§B8): `OpenBranch` with every §B3 check.
  - **No double rebirth:** the 5 s cooldown, plus the count read before equals the count written.
  - **The offer is rolled once** and saved. `ChoosePerk`, `BuyNode`, `ResetTree`, `SetTheme` and
    `ClaimBranchNurse`, each ONE update.
- [ ] **After a rebirth:**
  - `Plots.syncRooms`; the building drops to the Stand by itself (Levels follows `Data.Level`).
  - The mascot from R5, `Branches` and `BranchBadge`, `WalkBoost` and the walk speed.
  - `saveNow`, then the Celebrations.
  - The R5 FounderFennec arrives through `grant(..., "Gift")`, or waits in `Pending` with a toast "🎁 A nurse waits
    for a free slot!".
- [ ] **The one-time toast** the first time `canRebirth` turns true: "🏢 You can open a branch!" (`Told = true`).
  Nothing else, ever.
- [ ] **Economy** upgrade gates; **Carry** BigHands; **Plots** `syncRooms` (decor in removed rooms goes back to your
  inventory: the save did it; the models go now).
- [ ] Specs (`RebirthServer.spec`):
  - a rebirth against a mocked PlayerData/Patients;
  - spam: 3 calls in 0.1 s make one rebirth;
  - a rejoin keeps the same offer;
  - choosing a perk not offered fails;
  - the tree buy/refund round trip.

### T3: Agency + belt. Load `roblox-networking`, `roblox-ui`, `game-ui-ux`.
- [ ] **✚ Agency server** (§B3.1, §B8): restocks on uptime (`AgencyRestock`); in-memory buys by UserId per restock;
  personal Lucky Stock slots; the kiosk (§B4); `AgencyNews` to each player on a restock and after their own
  buy/sell.
- [ ] **✚ AgencyPanel** (a `Hud.modal` Panel). It shows:
  - 4 (6 with Lucky Stock) nurse cards: portrait, rarity frame, role, specialty and ability icons, your price, and
    Buy / ✅ Bought / "🏥 Lv 3" / "🏢 R1" / "Roster full".
  - A 🎲 Odds popup (70 / 26 / 4 and "never Legendary+").
  - "🔄 New nurses every 5 min", with no clock (§E9).
  - A **Sell** tab: your nurses with their sell-back price and a confirm (hold for Epic+).
  - It opens from the kiosk, NursePanel's 🏢 button and the `Sell` bus event.
- [ ] **NurseBelt:** the R1 gate, `canAdd`, Bargain, the Belt Scout pre-roll and `BeltScout`, and the sign's gate
  line. **BeltView:** the "🏢 R1" chip like "🏥 Lv 3" (no lock, no price); "Roster full" on the card (Hire turns
  into "Sell or list one", which opens the 👩‍⚕️ Team page); the 🔭 next-rarity chip for perk owners; and the nurse
  house's number-free "next nurse" lamp (§E9).
- [ ] Specs (`AgencyServer.spec`):
  - a stale slot, a wrong `expect`, a double buy in one restock, a buy after the restock;
  - selling a listed nurse; selling FounderFennec;
  - the Lucky Stock seed is stable across calls.

### T4: Player Market. Load `roblox-networking`, `roblox-ui`.
- [ ] **✚ Market server:** every §B3.2 rule, in that order, with no yield from the first check to the end of the
  buyer update. `saveNow` goes seller then buyer. Listings go on PlayerRemoving. `MarketNews` is debounced.
- [ ] **✚ MarketPanel:**
  - The **Buy** tab: every listing as a card (the nurse, Lv, price, "by DisplayName"), with a confirm ("Buy 🐶 Lv 7
    for 💰420?").
  - The **Sell** tab: pick one of your nurses, a price slider/stepper locked to its band (min/max shown, 💰 after
    the 10% fee shown big), and List.
  - Your listings with Unlist.
  - "🏷️ Only this server" and "No swaps. No chat." badges. It opens from the kiosk, NursePanel's 🏷️ button and the
    `List` bus event.
- [ ] Specs (`MarketServer.spec`, the real buy block under a mocked PlayerData/Nurses):
  - two buyers in one frame → one nurse;
  - the seller leaves before the buy → refused;
  - the price changed → refused;
  - out-of-band list → refused;
  - a buyer owning the nurse → refused;
  - a full roster → refused;
  - the buyer's update failing → the seller is restored, and cash is conserved (sum before = sum after + fee).

### T5: Nurse + Branch UI. Load `roblox-ui`, `game-ui-ux`.
- [ ] **NursePanel:**
  - The Journal stays first, plus a 🏢 tab for rebirth-only nurses.
  - The new **Team** page:
    - roster `n/cap` (and "💤 resting" for over-cap legacy nurses);
    - one big card per nurse: level and an XP bar, specialty, the job picker (open jobs; closed ones show
      "🏥 Lv 2"), the ability with its `Kit.ring`, the team chips;
    - 🏷️ when listed; Sell (→ `Sell`) and List (→ `List`).
  - Equip/Unequip and the slot strip are gone.
  - Buttons to 🏢 Agency and 🏷️ Market.
  - The NEW! / news flow stays; `NursesNew` also counts "Level" news.
- [ ] **✚ BranchPanel:**
  - **Open:** the keep/reset screen. Its rows are `Logic/Rebirth.KEEP` ✅, `RESET` 🔄 and `GET` 🎁 (+25% 💰⭐,
    +3 🌳, a card, +1 nurse slot, the next R-unlock, the new theme). The cost comes from `Logic/Rebirth.cost`. A
    big "Not now" is the default focus; "🏢 Open branch!" is a `Kit.holdButton` (1.5 s) and asks `OpenBranch(true)`.
  - **Perks:** the 3 offered cards (or "no cards waiting"), every perk with ✅ owned, and "3 random cards, never
    repeats".
  - **Tree:** three columns, node ranks, the capstone lock "6 🌳 in Care", and 🔄 Reset (free).
  - **Themes:** unlocked themes to pick from, and locked ones as "🏢 R3" (no lock icon, no "hurry").
  - It opens from the Shop's 🏥 tab and after the Rebirth celebration (Perks).
- [ ] **Shop:**
  - The 🏥 tab at Lv 5 shows a calm "🏢 New branch" card (the cost, "Look 👀" → `Open("Branch", "Open")`) and a 🌳
    line ("3 points to spend") when `shopNews.Branch`.
  - Gated upgrades show "🏥 Lv 2" / "🏢 R4".
  - The level ladder shows departments, not nurse slots.
- [ ] Specs (`BranchUI.spec`, `NurseUI.spec`): the screen's rows from the Logic lists; ≤ 6 words on every label;
  the job picker's states.

### T6: Hospital world. Load `roblox-studio-workflow`, `roblox-physics`, `roblox-ui`.
- [ ] **`buildBuilding`** (§B4):
  - The ward storey at Lv 2 plus walkable floors.
  - The glass lift with a `LiftPrompt` and an `EscortPrompt` per landing; stairs.
  - The Wards beds on Floor 1 (kept across level-ups); the hot tub (Lv 3); `Station_Pharmacy` (Lv 4); the roof
    garden; `HeliSpot` (Lv 5).
  - The ambulance bay moves to Lv 2 with a `StretcherSpot`; `MascotSpot`; the sign's `BranchBadge`; themes.
  - **Keep the queue lane, the sign and the gate clear**, and the Counter, walkways, stations and room slots, as in
    v3.
- [ ] **Perf:** a Lv 5 plot with every room ≤ 400 parts (no creatures or decor; 389 today). Make room by drawing
  details as SurfaceGuis and reusing the storey shells as slabs. If it won't fit, report the count and where it
  goes, and the lead decides. Update the perf note's table.
- [ ] **✚ Lift** (§B8) and **✚ LiftPanel**: big floor buttons ("🛎️ G", "🛏️ 1", "🛁 2", "💊 3", "🚁 R"; only this
  building's floors). The car slides and the doors part on THIS client during the ride, with a "Ding", and a
  `PivotTo` when it ends; the camera eases with it (no cut). ExpressLift shortens the ride.
- [ ] **Levels:** theme and floors, `floors`/`departments`, slots removed; `PreviewLevel` still works (with the
  lift).
- [ ] **Stations:** Pharmacy crafting (§B8), team and ability factors, and "🍵 Warm Tonic!" made toasts.
- [ ] Specs (`Hospital.spec`): landing math, which floors exist per level, the Pharmacy craft check, the hold factor
  floor.

### T7: Hospital patients. Load `roblox-networking`, `game-feel`.
- [ ] **A&E** (Lv 2+, design §6):
  - About every `AE.EverySeconds` (±20%; ×(1 − 0.1 × A&E Speed); ÷1.25 SirenPro), only while the owner is at their
    clinic, done with the tutorial, the line has room and no other 🚑/🚁 waits.
  - The parked ambulance's `ArriveAt` is set; the patient pops out at `StretcherSpot` and goes to the **front** of
    the line (second if the front is being treated).
  - It has `Urgent = "AE"`, `Logic/Hospital.urgentRecipe`, patience ×0.6 × A&E Speed × TeamUrgent × MedicPatience,
    and pays ×3 + 2 ⭐. Kid-safe: a bandage badge and wobbly-tummy acting, nothing gory.
- [ ] **Air ambulance** (R2 + Lv 5): every `VIP.EverySeconds`. `HeliSpot.ArriveAt`; a Sky-wing patient rides the
  lift down to the line front; `Urgent = "VIP"`, ×4 + 3 ⭐.
- [ ] **After the recipe is complete:**
  - Route with `Logic/Hospital.route`; triage (Lv 3+, no Receptionist) via `Treatment.waitTriage`.
  - Then the destination: the Stand's ground bed if free, else an upstairs ward bed or a tub spot (Hydro).
  - **Upstairs:** "ToLift" → a Porter (`claimPorter`) or `Lift.waitEscort` (6 s) → `Lift.carry` with the porter or
    the player → `Escorted` (+20%, rest ×0.5) → the bed; no escort: it rides alone.
  - **Hydro:** "Soaking" in a tub spot (+25%, rest ×0.5); its `SoakPrompt` opens one 🫧 Scrub game (`Treatment.open`
    Kind "Soak"; the tip shares the patient's `TipCapPerCure`).
  - Rest seconds × Ward Comfort × TeamRecover.
- [ ] **Twin Counters:** the Treat prompt serves the first of the two front patients whose missing items you carry.
  Healers and Medics may serve #2. `FrontNeeds` covers both.
- [ ] **Abilities:** on `Fired`, RefillFront, RefillLine, PauseLine (`PatiencePausedUntil`) and CureLine (each waiting
  patient cures on the spot through the usual `Cure.resolve`, the owner as helper, no tip).
- [ ] **Perks and unlocks:**
  - BusyDoors and Reception change arrival seconds (`Logic/Hospital.arrival`); NightOwl brings night patients after
    morning.
  - Golden (R3, 2%, a gold sheen through `CreatureBuilder.setEffect`); the Sunny wing from R1; Sky only by
    helicopter; PatientPals through Boosts (already).
  - A Studio-only test switch, `workspace:SetAttribute("ForceGoldenPatient", true)`: every new patient at an R3+
    clinic is Golden. A live server ignores it; document it in the README's test switches.
- [ ] **Treatment:** `Auto` from `Abilities.consumePerfects`, `Ease` from the tree, medicines (one Pour fills both
  slots), the Soak kind, `Triage` (§B3), and Medic deliveries.
- [ ] **Cure:** §B8. **CreatureBuilder:** `setDept(badge, deptId)` (a small chip), the 🚑/🚁 badge ring, the Golden
  effect; ≤ 35 parts as before.
- [ ] Specs (`HospitalPatients.spec`, and update `ServerPure`/`TreatmentSessions`):
  - routing, triage right/wrong/timeout, escort with and without;
  - the urgent recipe padding, Twin Counters' pick;
  - auto-Perfect sessions; a medicine filling two slots;
  - a Soak tip under the cap.

### T8: UI and juice. Load `game-feel`, `game-ui-ux`, `roblox-ui`.
- [ ] **Celebrate:** Rebirth (the theme's colours, "🏢 New branch!", the count, then "Pick a card!" → `Open("Branch",
  "Perks")`), Perk, NurseLevel (an ability upgrade at 5/10), Unlock chips.
- [ ] **MiniGames:**
  - Auto games show a ✨ PERFECT! pop and skip.
  - `Ease` widens the windows.
  - The Soak game card ("🫧 Bubble bath!").
  - Triage buttons after the result when `TreatOutcome.Triage` is set: two huge icon buttons that match the badge's
    chip, a soft timer bar (no digits), and "✅ Right floor!" / "Oops, not this floor!".
- [ ] **✚ Feel/HospitalFX:**
  - The ambulance's flashing lights and siren (`ArriveAt`; calm: lights only, soft).
  - The helicopter flying in and out of `HeliSpot` (client-only model ≤ 15 parts, one tween).
  - Ability sparkles on `AbilityAt`; the lift's ding for others' rides nearby.
  - The theme grow-in on `GrewAt`. Everything sleeps when nothing happens.
- [ ] **Hud:** the 🛒 dot from `shopNews.Branch`; flying 🌳 points into 🛒 after a rebirth.
- [ ] **Guide:** hold times follow `MakeRushUntil`/`MakeRushFactor` and `TeamMake`.
- [ ] **BookPanel:** the Sunny and Sky wings ("🏢 R1", "🏢 R2 · 🚁") and the Golden sticker.
- [ ] **Boards:** the 5th tab (🏢 Branches).
- [ ] **PromptFilter:** hide `EscortPrompt`/`SoakPrompt` on plots you can't work at.
- [ ] **Sounds:** the §B9 cues; `NurseNews` "Equipped" is gone, so the Equip cue plays on "Job". **CureFX:** pops for
  "+20% 🛗", "+25% 🛁", "🚑 ×3", "🌟 Golden!".
- [ ] **Kit:** juice `ring`, `holdButton` (signatures unchanged).
- [ ] Specs (`MiniGamesPure`, `Juice`): auto games, the ease scaling, the triage card's states, ring fractions.

### Integration (lead)
- [x] Apply the requests, update the README, commit (2026-11-17, "Progression v2: parallel build integrated"; 982
  Lune specs pass, selene 0/0, rojo build OK). The integration report lists what was left.
- [ ] Boot, run §D, write `logs/playtests/2026-11-16-progression-v2.md`, update STATE, merge.

---
## D. Studio playtest checklist
- [ ] P0. **Boot.** `[Main] Clinic is open.`, no red errors. The 🏢 Agency and 🏷️ Market kiosks stand on the
  plaza's row-2 side, clear of the spawn, benches, lamps, planters, the belt and the middle gates. The belt sign says
  "🏥 Epic+ from Lv 3 · 🏢 Mythic/Secret from R1".
- [ ] P1. **Migration.**
  - A v3 save (Update 1 test: 5 nurses, 4 equipped) loads with the 3 first-equipped working and 2 💤 resting, XP 0,
    each job its role, and `Version` 4 on save. The resting two can be sold or listed, and can't be hired over.
  - A v2 save (live, no nurses) loads clean with `Rebirth` defaults.
  - A v4 save opened by a v3 build (an old Studio branch) stays read-only.
- [ ] P2. **Fresh save** (`FreshSave`): the tutorial is unchanged; 👩‍⚕️ shows Team 0/3; the first belt hire walks to
  the clinic and works its role.
- [ ] P3. **Roster.**
  - Hire 3; a 4th new nurse is refused with "Roster full: sell or list one" on the belt card, the Agency and the
    Market.
  - A copy of an owned nurse still adds a level.
  - At the level cap the card says ⭐ MAX.
- [ ] P4. **Jobs.**
  - Each job can be set; Porter/Medic show "🏥 Lv 2" at Lv 1.
  - At Lv 2 a Porter rides patients up and a Medic serves 🚑.
  - A Receptionist makes patients come sooner and skips the triage buttons.
  - After a rebirth a Porter works as its role until Lv 2.
- [ ] P5. **XP.**
  - Cures fill the XP bars; Lv 2 pops "⬆️".
  - 🛠️ "Nurse levels" ×4 reaches Lv 5: a NurseLevel celebration and a shorter cooldown.
  - With FastLearners the bar fills twice as fast.
- [ ] P6. **Abilities** (🛠️ Charge abilities):
  - Each fires by itself only when useful, with a sparkle and a filling ring (no digits).
  - Golden Touch: the next 3 games pop ✨ PERFECT! and pay tips.
  - Calm Song freezes every patience ring for 10 s.
  - Busy Paws: the station ring is shorter.
  - Miracle cures the line once, and not again until the next in-game day.
  - 💤 calm stops the sparkles.
- [ ] P7. **Teams:** two Reception specialists → "🛎️ ×2" chip and cures pay +10%; three Hydro specialists make 🛁
  holds 40% shorter.
- [ ] P8. **Agency.**
  - 4 nurses with your prices (×1.5 the belt); 🎲 shows 70/26/4; no clock anywhere.
  - Buy one → ✅; buying it again this restock is refused.
  - 🛠️ Restock → new nurses, buyable again.
  - Epic below Lv 3 shows "🏥 Lv 3".
  - Sell: a confirm with the 30% price (a hold for Epic+); the nurse leaves the plot and stays "Hired" in the
    Journal.
  - With Lucky Stock, 2 more slots that survive a rejoin.
- [ ] P9. **Market** (2 players, Test → 2 players):
  - Listing below or above the band is refused; inside works and shows 🏷️ on the card.
  - Player 2 buys: −price; the seller gets +price −10% and a toast; the nurse hops from plot 1 to plot 2 with its
    level.
  - Buying your own, a nurse you own, or with a full roster is refused.
  - Spam Buy from both clients at once: one nurse moves, and the other gets "Price changed! Look again".
  - The seller leaves → the listing vanishes for player 2.
  - From the command bar: `BuyListing(id, wrongPrice)` → false.
- [ ] P10. **Rebirth** (🛠️ +10,000 💰 ×5, Lv 5, or 🛠️ Rebirth now):
  - The 🏥 tab shows a calm "🏢 New branch" card with no dot.
  - Look 👀 shows the keep/reset screen; Not now is the default; Open branch needs a 1.5 s hold.
  - Then the celebration, the Stand in the Arctic theme, 💰0, the upgrades and rooms gone, and decor from removed
    rooms back in 🛒 Decor.
  - Kept: nurses, the Book, badges, the rank, ⭐ and decor.
  - +3 🌳; 3 perk cards (rejoin: the same 3); Team 0/4; the sign shows "🏢 1"; the 🏆 Branches tab lists you
    (non-admin); 🏅 Branches turns Bronze.
- [ ] P11. **R1:** a Mythic/Secret rider shows a price (with `BeltForce`); Sunny-wing patients come at the Stand.
- [ ] P12. **Tree.**
  - Buy ranks in each branch; the capstone stays locked until 6 points are spent in it; 🔄 Reset refunds all.
  - Quick Feet makes you walk faster, Express Lift makes the ride shorter, and Bargain lowers belt and Agency
    prices.
  - Twin Counters lets you treat patient #2.
- [ ] P13. **Lv 2.**
  - The second storey, the lift (G ↔ 1, a ding, the car slides on your screen), stairs, ward beds upstairs.
  - A patient for upstairs waits at the lift. Ride with it for a "+20% 🛗" pop; leave it and it rides alone.
  - An ambulance (🛠️) flashes and sirens; a 🚑 patient goes to the front, needs 2 items, pays ×3 + 2 ⭐.
  - The queue lane, the sign and the gate are clear (also check with `PreviewLevel` 2–5).
- [ ] P14. **Lv 3 Hydro.**
  - A Bath patient's chip says 🛁; triage buttons show after its games.
  - Right: "✅ Right floor!" (+10%). Wrong: "Oops, not this floor!" and it goes to the tub anyway. No tap: it goes by
    itself after 4 s.
  - In the tub the 🫧 prompt starts a bubble game with a small tip.
- [ ] P15. **Lv 4 Pharmacy:** carry 🧪 + ☕ → hold → 🍵; treating a Chills patient (☕🧪) with 🍵 is one Pour game and
  ticks both. At R2 two more medicines and a faster hold.
- [ ] P16. **Lv 5 + R2:** the helicopter (🛠️) lands on the helipad, its VIP rides the lift down to the front, pays ×4
  + 3 ⭐, and gives a Sky-wing Book page.
- [ ] P17. **R3–R6** (🛠️ Rebirth now):
  - R3 Golden patients appear (`ForceGoldenPatient = true` makes every new one Golden); the nurse cap reaches 15.
  - R4 sells Night Clinic.
  - R5: FounderFennec arrives (or waits as a gift with a full roster) and the mascot cheers at the Counter.
  - R6: the TrophyCup is in 🛒 Decor.
- [ ] P18. **Themes:** pick any unlocked theme; the building recolours; the plot's accent colour stays.
- [ ] P19. **Junk calls** (command bar, each `false` + a message, nothing changes):
  `SetJob("PuffPup","Rest")`, `SetJob("x",1)`, `OpenBranch(false)`, `OpenBranch(true)` below Lv 5,
  `ChoosePerk("BathReady")` (not offered), `BuyNode("TwinCounters")` (locked), `SetTheme("Royal")` at R0,
  `AgencyBuy(1, "GoldieGryphlet", 1)`, `AgencyBuy(0/0, "PuffPup", 150)`, `SellNurse("PuffPup", 999)`,
  `ListNurse("PuffPup", 1)`, `ListNurse("PuffPup", 1e9)`, `BuyListing(-1, 0)`, `Unlist(999)`, `RideLift(9)`,
  `RideLift(1)` from the street, `Triage(-1, "Hydro")`. `EquipNurse` no longer exists.
- [ ] P20. **Kids' rules.**
  - No countdown digits anywhere: Agency, belt, abilities, triage, A&E patience rings.
  - Nothing nags about rebirth after the one toast.
  - Every buy, sell and list asks first.
  - The odds are on the belt sign, the Agency 🎲, the perk cards and the R3 unlock.
- [ ] P21. **Phones** (Device emulator, a small landscape phone and 667 px): Branch, Agency, Market, Team and the lift
  picker fit, all buttons ≥ 56 px, every label ≤ 6 words, the bottom bar still seven tabs.
- [ ] P22. **Perf.** A Lv 5 plot with every room ≤ 400 parts. 6 plots × 8 nurses + belt + kiosks ≈ 60 fps on a mid
  phone; Network receive stays low during lift rides and ambulances. Fill in the perf note.
- [ ] P23. **Leaving:**
  - The owner leaves mid-escort, mid-ride, mid-triage, mid-soak and with listings; no errors, a clean plot, and the
    next joiner's prompts and lift work.
  - A buyer leaving mid-purchase changes nothing.
- [ ] P24. **Before publishing** (red lines 3 and 4): re-read Roblox's live Terms of Use and Community Standards for
  in-experience trading between players (no Robux is involved here) and check the maturity questionnaire's answers
  still hold with a player Market. Publishing needs both brothers' yes.

---
## E. Open points (the design leaves these open; each has the default this plan builds)
All twenty were decided as their stated defaults (Claude's call, 2026-11-16, at Task 0). Joshua or his brother
may overrule any of them later; every number they use lives in `Config` or `Shared/Data`.
1. **Roster ceiling.** memory-019 says 3 nurses +1 per rebirth with no top. Every owned nurse works on the plot and
   each is up to 40 parts, so this plan stops at **8** (reached at R5); later rebirths still give everything else.
   **Decided (Claude's call, 2026-11-16): 8.**
2. **Saves with more nurses than the roster.** A v3 save (Update 1 tests; Update 1 isn't live yet) can own up to 16.
   **Decided (Claude's call, 2026-11-16):** nothing is ever deleted. The first 3 (the ones on duty first) keep working and the rest rest (💤) until
   you sell or list one, or a rebirth adds a slot. Hiring a new nurse waits until you're under the cap.
3. **Who fires an ability?** §7 asks for a visible cooldown and sparkle, not who presses it. **Decided (Claude's call, 2026-11-16):** each fires by
   itself when it would help (no button to learn). Banked ones (Golden Touch, Double Dose, Star Burst, Quick
   Bandage/Soap) wait for the next treat or cure.
4. **"Night lasts 30% longer" (perk).** Night is one clock for the whole server, so one player's perk can't stretch
   it. **Decided (Claude's call, 2026-11-16):** at your clinic, night patients keep coming for 30% of a night after morning (🦉 Night Owl).
5. **"Belt luck within the shown odds" (Fortune).** The belt and the Agency roll once for the whole server, so a
   per-player luck boost would make the sign wrong. **Decided (Claude's call, 2026-11-16):** Fortune never changes a roll. 🏷️ Bargain makes belt
   and Agency nurses cheaper (−5% a rank). The capstone 🍀 Lucky Stock gives you 2 extra Agency nurses of your own
   each restock, rolled with the Agency's shown odds.
6. **Twin Counters ("treat two patients at once").** **Decided (Claude's call, 2026-11-16):** the Counter can treat the first or the second
   patient in line (whichever you carry items for), and Healers and Medics may serve the second too. Still one
   mini-game card at a time per player.
7. **Escort: required or a bonus?** §6 says you escort the patient upstairs "or a nurse does". **Decided (Claude's call, 2026-11-16):** a bonus,
   never a chore. A patient going upstairs waits 6 s at the lift. Ride with it (or have a Porter) for +20% cash and
   twice-as-fast rest; otherwise it rides up alone.
8. **Triage: what a right pick earns, and how long it waits.** **Decided (Claude's call, 2026-11-16):** triage starts at Lv 3, when there are two
   places to go (🛏️ Wards, 🛁 Hydro). A right pick pays +10%. A wrong one says "Oops, not this floor!" and the
   patient goes to the right one. With no pick in 4 s it goes by itself. A Receptionist sends patients at once, with
   the bonus.
9. **No clocks.** §8 asks for a "server-wide countdown" on the Agency and §7 for a "next nurse in…" belt track. Red
   line 3 and memory-020 rule out countdowns. **Decided (Claude's call, 2026-11-16):** the Agency says "🔄 New nurses every 5 min" with no ticking
   clock. The nurse house has a lamp that glows brighter as the next nurse nears, with no numbers. Ability cooldowns
   are filling rings (the design asks for a visible cooldown), never seconds.
10. **A&E's level, and the shipped Lv 4 ambulance bay.** §6 opens A&E and upstairs Wards at Lv 2. The Update 1 shell
    parks the bay at Lv 4 and has one storey at Lv 2. **Decided (Claude's call, 2026-11-16):** follow §6. The bay moves to Lv 2, and the Lv 2
    building gains a ward floor with the lift.
11. **The Lv 5 helipad vs R2's "A&E helicopter".** §6 puts air-ambulance VIPs on the Lv 5 roof; memory-019 makes the
    helicopter an R2 unlock. **Decided (Claude's call, 2026-11-16):** Lv 5 builds the helipad, and the air ambulance flies only from R2.
12. **How +25% per rebirth adds up.** **Decided (Claude's call, 2026-11-16):** added, not multiplied (R1 ×1.25, R4 ×2, R8 ×3), counted up to 20
    rebirths (×6). It applies to the cash and Stars of cures, not to mini-game tips.
13. **Market: buying a nurse you already have.** **Decided (Claude's call, 2026-11-16):** refused ("You have one!"). Two levelled nurses can't be
    merged without losing XP, and refusing keeps every nurse on a roster unique.
14. **Selling back a nurse with copies.** "About 30% of its base price": **Decided (Claude's call, 2026-11-16):** 30% of the belt's base price for
    every copy it has (each copy was a purchase). It is never level-scaled, so nothing can be bought and sold back
    for profit.
15. **The R5 rebirth-only Legendary.** **Decided (Claude's call, 2026-11-16):** it can't be sold or listed. It waits as a gift when your roster is
    full. It has its own Journal tab, so it changes neither the Legendary set nor the Journal % for anyone.
16. **Resetting the tree.** **Decided (Claude's call, 2026-11-16):** free, any time, every point back.
17. **When the 12 perk cards run out.** **Decided (Claude's call, 2026-11-16):** the card becomes "🌳 +2 tree points".
18. **R6+ "a cosmetic each time".** **Decided (Claude's call, 2026-11-16):** R6–R10 each give a Branch Trophy decor; after R10 the cosmetic is the
    sign's 🏢 number.
19. **The mascot pet.** **Decided (Claude's call, 2026-11-16):** it stands by your Counter and cheers each cure. It doesn't follow you around (that
    would be a per-frame follow loop on every client).
20. **The R1 creature wing.** **Decided (Claude's call, 2026-11-16):** a 🌻 Sunny wing whose patients come from the start of each branch after R1,
    using whatever stations you have. Names and looks are placeholders (OPEN #1).
