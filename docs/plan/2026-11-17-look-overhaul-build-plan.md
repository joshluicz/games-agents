# Look overhaul build plan: contracts, file ownership, numbers, playtest

> **For agentic workers:** this plan runs as a **parallel team**, in five stages:
> 1. **Task 0 (Foundation)** is committed first and is then **frozen**.
> 2. **T1–T8** run at the same time. Each edits **only the files it owns** (§A). Anything you need in a file you
>    don't own goes in your final report under **Requests** (the file, where, and the exact change).
> 3. **The integrator** applies the requests, boots the game, playtests in Studio (§E) and writes the logs.
> 4. **Two review lenses** (§D "Review") read the integrated diff, each through its own lens.
> 5. **A fixer** applies their findings, re-runs the gates and re-checks the §E items it touched. Then the lead
>    commits and merges.
>
> Steps use checkbox (`- [ ]`) syntax.

**Goal.** Joshua published Update 1 and called it "pretty shit". This is the overhaul his picks and rulings ask for:
- the world takes the studs look, with a relight, dark anchors and no pastels;
- the hospital becomes a real building from Lv 1 that grows a storey per level, with wards that look full;
- the Nurse Belt runs down the road's centre line, and the spawn plaza moves off it;
- the HUD moves onto two side rails, with a top-centre Now card and a top-right status zone;
- every panel uses one modal template with one navy header, and the colours are calmer;
- the tutorial gets a top card, a floor-level beam from the player's body, a glowing target, celebrations, and Skip
  and Replay.

**Rulings this builds (all binding; this plan doesn't re-decide them):**
- `memory/records/memory-20261117-001.md` (Joshua, 2026-11-17): the look overhaul. It covers studs, a real hospital,
  the belt in the road's centre, the side rails with the Now card, the navy header, the calmer UI, the floor-level
  tutorial beam, and creatures staying round. It supersedes the candy-pop specifics of `-007`; "saturated, flashy,
  trending" stands.
- `memory/records/memory-20261116-022.md` (Joshua, relaying his brother): countdowns to **free** upcoming events are
  allowed. Nothing paid ever gets a timer.
- **Joshua, 2026-11-17, relayed by the coordinator, verbatim:** "more beds, wards should look full. tutorial should
  be able to be toggled again or something in case they accidentally skipped it."
  - This isn't in `memory/records/` yet. **The lead files it as `memory-20261117-002` before Task 0 starts.**
  - The plan reads it as two rules:
    1. Every ward floor shows a full room of beds: 6–8, cheap, some of them decorative with sleeping stand-ins.
    2. A player-facing "🔁 Replay tutorial" row in ⚙️ restarts the tutorial behind a confirm. The Skip confirm
       says "You can replay it any time from ⚙️". A player-safe remote does the restart, only for the caller's
       own save and plot, rate-limited.

**Claude's defaults (Joshua can overrule any of them). The lead files them as `memory-20261117-003`, provisional:**
- A real building from Lv 1, still named "First-Aid Stand".
- The whole building in one bold plot colour, studded, with warm trim and a dark roof.
- Solid walls upstairs, with a cutaway so you can see into your own floor.
- Ward beds face the windows.
- A placeholder paw-heart logo.
- The lean scenery. The part budget stays 400 per plot at Lv 5, enforced by a part-count spec.
- Tutorial Skip: yes, and the beam stays until 3 cures.
- The guide nurse has a placeholder name and look.
- Creatures stay round. The blocky prototype is separate and **not in this plan**.

**Specs (all researched; this plan applies them):**
- `docs/research/2026-11-16-art-direction.md`: §2 studs, §4.1 palette, §4.3 lighting, §4.4 signs, §4.5 UI palette
  and its acceptance test.
- `docs/research/2026-11-16-hospital-building.md`: §3 the building, §4 materials, §5 the part budget, §6 the floor
  plans.
- `docs/research/2026-11-16-ux-cohesion-audit.md`: §3.1 the HUD zone map, §3.2 the modal template, §3.3 the button
  roles, §3.4 the tokens, §4 the migration list.
- `docs/research/2026-11-16-tutorial-ux.md`: §3 the cards, §5 the API and the beam recipe.
- `logs/playtests/2026-11-17-look-spike/`: the before and after screenshots. The relight and studded pads, done by
  hand and not saved, already read far darker and more textured.

**Code map:** `game/README.md`. **Still law where this plan doesn't change it:**
- `.worktrees/progression/docs/plan/2026-11-16-progression-v2-build-plan.md` §B (v2's contracts, especially §B4's
  building names);
- the depth and creature-clinic build plans' §B.

**The base: Progression v2 must merge first.** v2 (`claude/progression-v2`, foundation `e204207` plus its builders'
work) merges into `claude/trusting-carson-5v32sr` **before this plan starts**. Every file, line and contract here is
the **post-merge** tree:
- Schema v4;
- v2's `BranchPanel`, `AgencyPanel`, `MarketPanel` and `LiftPanel`;
- `Lift`, `Abilities`, `Rebirth`, `Agency` and `Market`;
- v2 T6's walkable `PlotBuilder` building;
- v2 T8's `Kit.ring`, `Kit.holdButton`, `Theme.Juice.RingBeads` and `Feel/HospitalFX`.

The overhaul runs in its own worktree (`.worktrees/look`, branch `claude/look-overhaul`) cut from that merge. Where
this plan replaces something v2 built, §G says which way it resolves.

**Foundation notes (Task 0, 2026-11-17): where the merged tree differs from this plan's first draft.** The plan
was written while Progression v2 was still in flight. Task 0 checked §A, §B and §G against the real tree and fixed
the text below in place; this is the list, so nobody codes against the old wording.
- **Baseline:** 1,000 specs in 42 files before the Foundation; 1,130 in 49 with it.
- **§A.** Task 0 also touched files it doesn't own, for the moves and stubs only (each marked `FOUNDATION` or
  `-- STUB (T<n>)`): `Kit` (`tab`, `textLimit`, the role kinds, the navy default header), `Hud` (the split, the Now
  stubs), `MiniGames` (`stage()`), `server/Tutorial` (`setReopen`, the two remote stubs), `Hospital.spec` (the mock
  moved out, the budget tests moved to `PartBudget.spec`, the PURE path), `Belt.spec`, `Rebirth.spec`.
  `Market.luau` has `placeholderKiosk` and `kitKiosk` but **no `buildSign`** (only `Agency.luau` has one).
- **§B1.** The plot lookup is `Plots.getPlot(p)` (there is no `Plots.plotOf`). `Patients.reopen(owner)` and
  `PlayerData.canSave(p)` exist as written.
- **§B3.** Three palette rules contradicted the table they check, so the rules changed and the table stayed:
  "no channel ≥ 245" is **above 245** (Yellow `#F5C731` has R = 245); plot colours sit **≥ 15°** apart, not 20
  (Orange–Yellow are 17.9° apart, Blue–Cyan 19.8°); V is compared **at two decimals** (the road's `#3E4352` is
  V 0.3216, "0.32"). `Theme.Radius.Round` is a `UDim` (0.5 scale), the others are px. `Theme.Space` is
  `{ Step = { 4, 8, 12, 16, 24, 32 }, Gap, PadCard, PadPanel, Margin, MarginPhone }`. `Theme.Colors.Quiet` stays as
  an alias of `Secondary`. Old `Theme.Size.Gap` (10), `Pad` (12) and `Margin` (12) keep their values so untouched
  layouts don't shift.
- **§B4.** `Parts.surface(part, name, face, pixels, maxDistance?, lightInfluence?)`. `Parts` also carries what more
  than one builder needs: `band`, `disc`, `iconLabel`, `lighten`, `darken`, `anchorAll`, `scrubScripts`, and the
  LEGACY `candyLabel` / `candyBoard` (T2–T4 replace their uses with `floatText` / `navyPlate`, then they go).
  `NightLights` gained `light(part, range)` (today's lamp light); `tag` stores `DayMaterial` as the Material's
  **name** (a string) plus `NightKind`. `Studs.Pure.alignedSize` takes and returns `{ X, Y, Z }`.
  The town's lawn part is still named **`TownLawn`** and `BoardBuilder` reads `ClinicTown.TownLawn` and `Street`:
  T2 owns both files and renames them together. `World/Props` and `TownBuilder.build` are still today's candy pieces,
  so `tree` (5 parts), `bush` (4), `bench` (4) and `fence` (posts every 10) are over the contract's counts until T2.
- **§B5.** With a stud kept from the lane and from the plaza's edges, the odds sign facing TownSpawn can be at most
  **9.2 studs wide** (`TownLayout.spec` prints it). Today's sign stand is 12 wide and faces the centre line, and
  `NurseBelt` turns riders "back up the belt" when the belt is on the centre line: both are T2's to change.
  Until T2 lands only TownSpawn has moved; the old plaza disc, planters and benches stand in the belt's lane.
- **§B6.** Decor slot 1 is at **(−8.5, −10.2)** in the real tree (the hospital doc rounded it to −10.3); it does not
  move. `Building.reach(fromXZ, toXZ, level, floor?)` takes the floor (0 unless given) and `Building.obstacles(level,
  floor?)` lists what is solid. `reach` allows a **0.3-stud skim** (`Building.SKIM`): the plan's own numbers put the
  straight line from the landing's centre (−9, 4) to `BedSpot_3`'s foot (6.7, 6.0) 0.26 studs inside the foot corner
  of bed 1's frame (z up to 4.6). T3 may end the frames at z 4.2 instead and file a Request to drop the skim.
  A station's 4.5-wide top at Remedy's new x (−4.3) reaches x −6.55, 0.05 past the shaft's face (−6.5): T4 trims it.
  Decor slot 2's 4 × 4 marker and `MascotSpot` overlap by 0.5 × 0.3 studs on the porch.
- **§B7.** `HudZones` constants are `RAIL_BUTTON` 72 / `RAIL_BUTTON_MIN` 56, `RAIL_GAP` 10 / `RAIL_GAP_PHONE` 8,
  `NOW_HEIGHT` 88 / `NOW_HEIGHT_SHORT` 76 (under `NOW_SHORT_BREAK` 500). Added, because the plan left them open:
  `WALLET_WIDTH` 240, `STATUS_WIDTH_PHONE` 180 (260 leaves a 667-wide phone 115 px for the Now card), `NOW_MAX` 480,
  `MARGIN` / `MARGIN_PHONE`, the Layout fields `Top`, `RailTop`, `NowHeight` and `StatusWidth`, and
  `railRect(layout, side, index, safeW)` / `nowRect(layout, safeW)`. On desktop the band starts one gap under the
  wallet (about 422 px at 720, not 430).
- **§B8.** `Modal.tabs` also returns `Column` and `Content` (the body beside the tabs). `Kit.textLimit` returns its
  constraint. `Modal.Pure` has `hudMode`, `confirm` (the defaults), `percent` and `oddsLine`. `Hud.modal` is a
  one-line wrapper (it hands Hud the bus, so `Hud.sound` works before `Hud.init`); the rest are plain re-exports.
- **§B9.** `Wayfinder.Pure` first versions: `feetY(rootY, rootHeight, hipHeight, r6?)`, `beamStart(feetY, lift)`,
  `endAnchor(box, fromX, fromZ, out)`, `needsBend(ax, az, bx, bz, box)`, `chevronSpots(length, first, gap, max,
  near?)`, `near(distance, nearStuds)`. `Data/Guide` also has an `Icon`. `NextEvent.MAX_AHEAD` is the 6 h.
- **§D.** `PartBudget.spec` holds the 400 total now and prints the three shares; the shares become hard limits there
  when the integrator flips `SHARES_HOLD` (today's v2 plot is building 75 · rooms 146 · plot 151 at Lv 5).

**Tooling** (PowerShell, from `game/`; the gates every task runs before finishing):
```powershell
& "$env:USERPROFILE\.rokit\bin\stylua.exe" src tests              # format first
& "$env:USERPROFILE\.rokit\bin\stylua.exe" --check src tests      # must print nothing
& "$env:USERPROFILE\.rokit\bin\selene.exe" src                     # 0 errors, 0 warnings
& "$env:USERPROFILE\.rokit\bin\lune.exe" run tests/run             # every spec passes
& "$env:USERPROFILE\.rokit\bin\rojo.exe" build default.project.json -o "$env:TEMP\look-check.rbxl"
```
(CLAUDE.md's short form: `selene src` and `stylua --check src tests` from `game/`.)

## Global constraints (every task)
- **Kids' rules (CLAUDE.md red line 3).**
  - Countdowns only for **free** events (`-022`): the Golden Hour chip, the labelled day/night line, and the
    tutorial finale's "COMING UP" chip.
    - They show minutes ("in 12m"). The day/night line keeps today's m:ss.
    - Never a timer on anything paid. No "only N left". No red or flashing countdown.
    - The Agency, the belt, abilities and triage stay clockless, as v2 built them.
  - **The odds stay on show:**
    - the belt's sign, on a navy plate, with a "🎲 See odds" prompt;
    - the hire card's 🎲 Odds button;
    - the Agency's 🎲;
    - the Journal's 🎲;
    - the perk cards.
  - **Words and controls.**
    - At most 6 words on screen. The only exception is the binding Skip line, "You can replay it any time from ⚙️".
    - Icons first. Buttons at least 56 px tall. **No text under 18 px.**
  - **Motion.** Every motion honours `Kit.reducedMotion()`, and Simple mode keeps working.
  - **Nothing loud points at spending.**
    - The Primary (orange) button never shines or breathes.
    - Only a Collect button may shine or breathe, and only while its reward waits.
    - The Shop rail button looks like its neighbours.
- **Original only (red line 2).**
  - These are all ours: the stud maps, the beam's chevron, the paw-heart mark and every model.
  - The reference games are ideas only. In docs and in the game the style is "studs" or "brick style", never the toy
    brand's name.
  - **Never** use any of these emblems, on anything:
    - a red cross, red crescent or red crystal;
    - a white cross on red;
    - the blue Star of Life.

    The old `crossSign` goes.
  - No Creator Store asset IDs from the research go in. They're references, not inserts.
- **v2 keeps working.** Floors, the lift (ride, escort, porters), A&E (the bay, StretcherSpot, the ambulance FX),
  triage, the Hydro tub, the Pharmacy, the helipad, themes, and the Agency, Market, Branch and Nurse UIs must behave
  exactly as v2's §D says, unless §G says otherwise. **Keep every name in v2 §B4** (`Floor_<n>.Slab/Landing`,
  `Landing_0`, `Lift.Shaft/Car/Car.DoorsGui`, `Landing.PromptPoint` with `LiftPrompt`/`EscortPrompt`, `Stairs`,
  `Wards.BedSpot_<n>.Bed_<n>` with `Floor`, `AmbulanceBay.Ambulance` with `ArriveAt`/`StretcherSpot`,
  `Hydro.HotTub.TubSpot_<n>`/`SoakPrompt`, `Station_Pharmacy` with its tag, `Roof.HeliSpot` with `ArriveAt`,
  `MascotSpot`, `Sign.SignGui.{OwnerName,HeartCount,RankBadge,BranchBadge}`, the `Since`, `Level`, `GrewFrom`,
  `GrewAt`, `Floors` and `Theme` attributes, and the tags `BuildingStation`, `HospitalLift`, `LiftPrompt`,
  `EscortPrompt`, `SoakPrompt`, `ClinicNightLight`).
- **The server is authoritative.** The two new remotes (§B1) go through `Remotes.serve` (10 calls a second per
  player, plus a pcall). They take no client data and touch only the caller's own save and the caller's own plot.
- **Change the save only through `PlayerData.update(p, fn)`.** The only new saved field is `TutorialGift` (§B1).
- **Performance (`docs/plan/2026-11-16-perf-budget.md`):**
  - **Parts:** at most 400 parts per plot at Lv 5 with every room, in every theme, not counting creatures, nurses or
    decor (`tests/PartBudget.spec`). The shares are in §C3.
  - **Highlights:** at most 1 in the whole world (the tutorial's glow).
  - **Textures:** no `Texture` or `Decal` per tile or per stud, anywhere. The only exception is one optional checker
    `Texture` per lawn part, once uploaded (§B2).
  - **Per building:** at most 12 SurfaceGuis, each with a `MaxDistance`, and at most 6 see-through parts.
  - **Lights:** no light casts shadows.
  - **Server writes:** no per-frame CFrame writes on the server.
  - **Client loops:** they sleep when nothing on screen moves.
- **File ownership is strict (§A).**
  - The Foundation layer is frozen after Task 0: `Config`, `Types`, `Remotes`, `Palette`, `Data/*`, `Logic/*`,
    `World/Parts`, `World/Studs`, `Theme`, `Main.server`, `Main.client`, `State`, the Foundation specs and helpers,
    and the README. Request changes to it; don't make them.
  - A change of yours that breaks someone else's spec is a **Request**, not an edit. All builders share one working
    tree, so a spec can fail on a file someone else is still editing. Report that; don't fix it.
- **No commits, no Studio, no push in T1–T8.** The integrator boots, playtests and commits.
- **Style:**
  - `--!strict`, tabs, and a header comment listing the module's API, like the existing modules. One responsibility
    per file.
  - Call other systems through `pcall` wherever a bug there must not break yours.
  - Keep testable rules in a `-- PURE-BEGIN` / `-- PURE-END` block (no Roblox types inside), so the spec loads the
    shipped code.

## Review focus (the two lenses, §D "Review", read the code against these)
1. **v2 still works.** Lift rides, escort, porters, ambulance and helicopter arrivals, triage, the tub, the Pharmacy,
   themes, rebirth (the building drops to the Lv 1 podium), and the Agency, Market and Branch flows.
   - No §B4 name is lost.
   - No patient walks through a wall or a bed.
   - Upstairs bed feet are reachable straight from the landing (Patients walks upstairs in a straight line).
   - Dressing beds are never picked as beds.
2. **The new remotes are safe.** Send `TutorialSkip`/`TutorialReplay` junk args, spam, mid-step calls, a call with
   no clinic, and a call while someone else is on your plot. The rules:
   - Only the caller's own save and plot ever change.
   - There's never a second top-up gift.
   - A rejection changes nothing.
3. **Budgets.**
   - Parts per plot at every level and theme. Parts in the town.
   - SurfaceGuis and see-through parts per building.
   - Highlights: 1. Texture instances: 0.
   - Loops: the cutaway (4 checks a second, only on a building), the beam (it aims only while it shows) and the
     rails.
4. **Look against the specs.**
   - The palette rules (§B3).
   - Studs where §B4 says, smooth where it says.
   - Dark anchors. No big surface at V ≥ 0.95. No lerp-to-white.
   - Floating outlined text; boards only for tables, on navy.
   - One navy header, one tab pattern, button roles, text ≥ 18, the motion budget.
5. **Kids' rules.**
   - Timers on free events only. Odds visible at every point of purchase. Confirms before anything that can't be
     undone.
   - The Skip and Replay flows can't trap a child: arrows until 3 cures, and Replay any time from ⚙️.

---
## A. File ownership (`game/`)
Each file has exactly one owner. **New** files are marked ✚. Task 0 makes every ✚ module exist with the exact API in
§B: some by moving today's code into them, the rest as stubs with safe defaults. So everything requires and boots
before any task lands.

| Task | Owns (create or modify) |
|---|---|
| **0 Foundation** (frozen after) | `src/shared/{Config,Types,Remotes,Palette}.luau` · `src/shared/Data/*.luau` (✚ `Guide`) · `src/shared/Logic/*.luau` (`Tutorial`, `Schema` changed; ✚ `HudZones`, ✚ `NextEvent`, ✚ `Building`) · `src/server/{Main.server,State}.luau` · ✚ `src/server/World/{Parts,Studs}.luau` · `src/client/Main.client.luau` · `src/client/UI/Theme.luau` · every existing `tests/*.spec.luau` for a Logic or Data module, plus ✚ `tests/{Palette,HudZones,NextEvent,Building,Studs,TownLayout}.spec.luau` · ✚ helpers `tests/{worldmock,uirules,look}.luau` · ✚ `tests/PartBudget.spec.luau` (the integrator's after T0) · `game/README.md`. **It also does the moves and stubs** listed under Task 0 in other tasks' files (each marked `FOUNDATION` or `-- STUB (T<n>)`) |
| **T1 Lighting** | `src/server/DayNight.luau` · ✚ `src/server/World/NightLights.luau` · ✚ `tests/Lighting.spec.luau` |
| **T2 Town world** | ✚ `src/server/TownBuilder.luau` · ✚ `src/server/World/Props.luau` · `src/server/NurseBelt.luau` · `src/server/BoardBuilder.luau` · `src/server/Agency.luau` and `src/server/Market.luau` (**their kiosk builders only:** `placeholderKiosk`, `buildSign` and the kit check; no logic) · `src/client/UI/BeltView.luau` · ✚ `tests/TownWorld.spec.luau` |
| **T3 Hospital building** | ✚ `src/server/HospitalBuilder.luau` · ✚ `src/client/Feel/Cutaway.luau` · `tests/Hospital.spec.luau` |
| **T4 Plot and rooms** | `src/server/PlotBuilder.luau` · `src/server/DecorBuilder.luau` · ✚ `tests/PlotWorld.spec.luau` |
| **T5 HUD** | `src/client/UI/{Hud,Toasts}.luau` · ✚ `tests/HudScreen.spec.luau` |
| **T6 Chrome and core panels** | ✚ `src/client/UI/Modal.luau` · `src/client/UI/{Kit,Shop,BookPanel,Boards,BadgeBook,Mailbox,PlayGifts,DayReportPanel,AdminPanel,MiniGames}.luau` · `tests/{Juice,MiniGamesPure}.spec.luau` · ✚ `tests/Chrome.spec.luau` |
| **T7 Progression panels** | `src/client/UI/{NursePanel,AgencyPanel,MarketPanel,BranchPanel,LiftPanel}.luau` · `tests/{NurseUI,BranchUI}.spec.luau` · ✚ `tests/ProgressionPanels.spec.luau` |
| **T8 Tutorial** | `src/server/Tutorial.luau` · `src/client/UI/{Tutorial,Guide,Celebrate}.luau` · ✚ `src/client/UI/Wayfinder.luau` · `src/client/Feel/Sounds.luau` · ✚ `tests/TutorialFlow.spec.luau` |
| **T9 Blocky creatures** (added 2026-11-17, `memory-20261117-004`) | `src/server/CreatureBuilder.luau` · `src/server/NurseBuilder.luau` · ✚ `tests/BlockyCreatures.spec.luau` |
| **Integrator (lead)** | anything, to fix integration bugs; the requests · ✚ `tests/UiRules.spec.luau` · `tests/PartBudget.spec.luau` · `docs/plan/2026-11-16-perf-budget.md` · the Studio-only setup (§D I-2) · `logs/`, `STATE.md`, `memory/records/`, `context/OPEN-QUESTIONS.md` · commits |

**Untouched by everyone (unless the lead):**
- Server: `Patients`, `Treatment`, `Cure`, `Nurses`, `Abilities`, `Rebirth`,
  `Lift`, `Levels`, `Stations`, `Plots`, `Carry`, `Economy`, `Visits`, `Playtime`, `Leaderboards`, `Admin`, `Book`,
  `Badges`, `Daily`, `DayReport`, `Events`, `Progress`, `Story`, `Boosts`, `PlayerData`.
- Client: `Feel/{Atmosphere,CreatureActing,CreatureMotion,CreatureProps,CureFX,HospitalFX}`, `UI/PromptFilter`,
  `Music.client`.
- Specs: `AgencyServer`, `MarketServer`, `NurseWork`, `NurseServer`, `RebirthServer`, `HospitalPatients`,
  `ServerPure`, `TreatmentSessions`, `Motion` must stay green. T2 edits `Agency`/`Market`, so T2 runs the first two.

**Notes on shared files:**
- **`PlotBuilder` is split by Task 0.** Today it is one 3,073-line file holding the town, the plots, the rooms, the
  queue lane and the building. Task 0 moves code, unchanged in behaviour:
  - the town to ✚ `TownBuilder` (T2);
  - the shared scenery props to ✚ `World/Props` (T2);
  - the building and its `Pure` layout to ✚ `HospitalBuilder` (T3);
  - the night lights to ✚ `World/NightLights` (T1);
  - the generic part and label helpers to ✚ `World/Parts` (frozen).

  `PlotBuilder` keeps the plots, rooms, queue lane and every public function. `buildTown` and `buildBuilding` become
  thin calls into `TownBuilder` and `HospitalBuilder`, and `PlotBuilder.Pure` and `NIGHT_LIGHT_TAG` stay as
  re-exports. Every v2 spec must pass after the split.
- **`Hud` is split by Task 0.** The modal shell (`Hud.modal` and its focus and close-binding helpers, `Hud.isOpen`,
  `Hud.fitTabs`, `Hud.fitHeight`) moves to ✚ `Modal` (T6). `Hud` keeps one-line re-exports so no caller changes:
  `Hud.modal = Modal.modal`, and so on, plus the new `Hud.confirm` and `Hud.oddsPopup`. `Modal` never requires
  `Hud`.
- **The Foundation's first versions T6 restyles:** `Kit.tab`, `Kit.textLimit`, the role names `Collect`,
  `Destructive` and `Icon`, `Modal.tabs`, `Modal.confirm` and `Modal.oddsPopup`. T6 restyles them freely but keeps
  the names and signatures, because T2, T5, T7 and T8 code against them.
- **`Hud.setNow` / `Hud.nowBottom`** are Foundation stubs that T5 makes real. T8's card works against the stub: it
  simply parents to the slot frame.
- **`LiftPanel`'s PURE block is loaded by `Hospital.spec`.** T7 restyles LiftPanel's UI but must not change its PURE
  block.

---
## B. Contracts (every task codes against these exact names)

### B1. Save, Snapshot, remotes, types
**Save (`Logic/Schema`, still Version 4: no version bump).** One new field: `TutorialGift: boolean` means "the
step-7 top-up has run or was never needed".
- `Schema.default()` sets it to `false`.
- `Schema.reconcile` keeps a boolean. When it's missing or junk, it uses `data.Tutorial >= Tutorial.SHOP (7)`. The
  top-up runs when step 7 is entered, so any save at or past 7 has had its chance.
- That rule makes the field harmless to lose: a v4 server without it that writes the save back loses nothing that
  matters, and the next load derives it again.

**Snapshot (`State.snapshot`, `Types.Snapshot`).** It gains `TutorialReplay: boolean`, which is true while this
session is replaying. It isn't saved: `Server/Tutorial` sets the player attribute `TutorialReplay`, and `State`
forwards it, the same way it forwards `TutorialCures`. The client's default snapshot sets it to `false`.

**Remotes (client → server functions, both through `Remotes.serve`).** Arguments are ignored. Each returns
`(ok, message)`, and any failure is `false` plus a message of at most 6 words, with nothing changed.

| Function | Server | Rules, in order |
|---|---|---|
| `TutorialSkip()` | T8 `Tutorial` | loaded · `Logic/Tutorial.canSkip(step)` (an active step 1..8; else "Already done!") · `move(p, DONE)` without any gift · `TutorialCures` cleared · toast "🔁 Replay anytime in ⚙️" |
| `TutorialReplay()` | T8 `Tutorial` | loaded and `PlayerData.canSave(p)` · `Logic/Tutorial.canReplay(step, hasPlot)`: the step is DONE and `Plots.getPlot(p)` is the caller's own clinic (else "Get a clinic first!") · `Config.Tutorial.ReplayCooldown` (30 s) per player (else "Try again soon") · the reopen hook empties **the caller's own** line (`Patients.reopen(p)`, wired by `Main.server`) · player attribute `TutorialReplay = true` for the session · `move(p, PATIENT)`. `TutorialGift` is already true, so there's no second gift. No respawn, no camera sweep, no funnel logs |

The admin `RestartTutorial` (`Server/Admin`) is unchanged: admin only, and it also respawns you.

**Types (`Shared/Types`):**
```lua
-- Snapshot gains:
  TutorialReplay: boolean,
-- CelebrateInfo.Kind gains "Tutorial" (shown even while the tutorial runs), with:
  Title: string?,            -- "YOU DID IT!"
  Chips: { string }?,        -- "📖 Collect them all", "🎯 Daily goals", "👩‍⚕️ Hire nurses"
  Next: NextEventView?,      -- the one "COMING UP" chip (free events only)
export type NextEventView = { Id: string, Icon: string, Name: string, At: number } -- At = GetServerTimeNow time
export type HudMode = "Panel" | "Game" | "None"
```

### B2. Config (exact; `src/shared/Config.luau`)
```lua
-- The road's centre line belongs to the belt (memory-20261117-001 #3); the plaza moves to the street's row-2 half.
Config.Belt.Offset = Vector3.new(120, 0, 0)          -- was (120, 0, -11): the nurse house at the east end, z = 0
Config.Belt.SignOffset = Vector3.new(-24, 0, 11)     -- the odds sign: the plaza's west end, facing TownSpawn
Config.Town.SpawnOffset = Vector3.new(0, 0, 11)      -- TownSpawn's centre (an 8 x 8 pad, z 7..15)
Config.Town.SpawnSize = 8
Config.Town.Plaza = { X0 = -30, X1 = 30, Z0 = 5.4, Z1 = 17 } -- the row-2 half of the road (the curb is z 17.2..18)
Config.Town.BeltClear = 4.4                          -- |z| <= this, x -121.5..121.5: the belt's alone (its bed is ±3.3)
Config.Agency.Offset = Vector3.new(13, 0, 12)        -- was (11, 0, 12); still faces TownSpawn
Config.Market.Offset = Vector3.new(-13, 0, 12)       -- was (-11, 0, 12)

Config.Look = {
	StudsVariant = "CureStuds",   -- MaterialService child that switches World/Studs to "Variant" mode (§B4)
	CheckerStuds = 4,             -- town lawn checker cell: within 20 studs of the street and in the plot gaps
	CheckerFarStuds = 8,          -- the rest of the town lawn
	CheckerTexture = "",          -- an rbxassetid of a 2x2-cell checker once uploaded: one Texture per lawn part
	                              -- (StudsPerTileU/V = 2 x cell, Transparency ~0.85) replaces the GrassB tiles
	TownParts = 600,              -- ClinicTown (the lawn, road, plaza, trees, lamps, arches; not the belt, kiosks,
	                              -- boards or plots)
	PlotBudget = 400,             -- one plot at Lv 5 with every room, any theme, no creatures, nurses or decor
	BuildingParts = 160,          -- its share: the Building, any level, any theme
	RoomParts = 90,               -- its share: every room model on the plot (Stand floor + annexes + Garden)
	PlotParts = 115,              -- its share: everything else on the plot (pad, edging, path, Counter, markers,
	                              -- slots, sign, fence, gate, mailbox, trees, bushes, queue lane)
	SurfaceGuisPerBuilding = 12,
	GlassPerBuilding = 6,         -- see-through parts (Transparency strictly between 0 and 1)
	WardFloorBeds = 7,            -- beds you can see on the Wards floor (F1), Lv 2..5: functional + dressing
	Lv1Beds = 2,                  -- beds you can see at Lv 1: Bed_1 + one dressing bed
	Sleepers = { Lv1 = 1, Ward = 2 }, -- sleeping stand-ins on dressing beds
}

Config.Tutorial = {
	-- the guide beam (tutorial-ux §5.5)
	BeamLift = 1.75, BeamEndLift = 0.25, BeamWidth = 1.6, BeamTextureLength = 2, BeamSpeed = 1.5,
	BeamMaxSpans = 4,
	BeamTexture = "",             -- our own chevron strip once uploaded ("" = a solid tinted strip)
	NearStuds = 6,                -- the beam and the chevrons hide this close to the target (flat distance)
	-- the floor chevrons (support)
	ChevronStuds = 4, ChevronGap = 6, MaxChevrons = 6, FirstChevron = 3,
	GlowSeconds = 1.6,            -- the glow's pulse
	NudgeSeconds = 20,            -- "Psst! Follow the arrows" (a hint, never shown as a number)
	SuccessHold = 0.8,            -- the ✓ beat before the next card
	FirstCureHold = 2.5,          -- CURED! 🎉 holds this long
	ArrowsUntilCures = 3,         -- the Guide keeps beam + glow + pin until this many cures (after Skip too)
	ReplayCooldown = 30,          -- seconds per player between TutorialReplay calls
}
```

### B3. Palette and Theme tokens (`Shared/Palette`, `UI/Theme`)
**`Palette` (world, art-direction §4.1).** These are albedo values, before lighting. Every old key stays as an
**alias** pointing at the new value, so untouched files keep compiling and pick up the calmer colours. (For example
`World.Grass = GrassA`, `Street = Road`, `Path = Plank`, `Floor = FloorA`, `Wall = WallUpper`,
`StreetLine = RoadLine`, `Fence = Fence`, `Leaves = LeavesA`, `LeavesLight = LeavesC`.)

| Key | Hex | Material (set by `World/Studs` or the builder) |
|---|---|---|
| `World.GrassA` / `GrassB` | `#56C740` / `#3FB536` | Plastic, studded |
| `World.Dirt` | `#8C603E` | Plastic, studded |
| `World.LeavesA` / `LeavesB` / `LeavesC` | `#39A844` / `#2B8F42` / `#67C246` | Plastic, studded (voxel cubes) |
| `World.Trunk` | `#704B31` | Wood |
| `World.Plank` / `PlankAlt` | `#D6B27C` / `#BA9265` | WoodPlanks |
| `World.Road` / `RoadLine` / `Curb` | `#3E4352` / `#F0EBE1` / `#999CA3` | SmoothPlastic / SmoothPlastic / Slate |
| `World.Pad` / `Edge` | `#253D4C` / `#8A8E94` | Plastic studded / Slate |
| `World.Roof` | `#2D2B3D` | SmoothPlastic |
| `World.Trim` | `#F0EBDF` | SmoothPlastic |
| `World.Beam` | `#805738` | Wood |
| `World.Fence` | `#EBE6DA` | SmoothPlastic |
| `World.CheckerTeal` / `CheckerCream` | `#369E94` / `#EBDEC0` | Plastic, studded (optional backdrop) |
| `World.Water` | `#38A7D6` | Glass 0.3 |
| `World.FloorA` / `FloorB` | `#AD8053` / `#996B45` | WoodPlanks (interior floors, slabs) |
| `World.WallUpper` | `#EBE4D8` | SmoothPlastic (interior upper wall) |
| `World.Window` / `WindowNight` | `#2F3B57` / `#D8B470` | SmoothPlastic (night: warm, **not Neon**) |
| `World.Pavement` / `PavementAlt` / `PavementGrout` | `#CDB38A` / `#B79D74` / `#8A7558` | SmoothPlastic (the queue lane; C, mid-tones) |
| `World.Lamp` | unchanged | Neon at night only |

| `Palette.Accent` (world accents) | Hex |
|---|---|
| `Pink` · `Blue` · `Orange` · `Purple` · `Cyan` · `Yellow` | `#DB3D7D` · `#3195E0` · `#EB842A` · `#894ECC` · `#29BCCC` · `#F5C731` |
| `Red` (props only: the A&E canopy, the ambulance stripe) · `Lime` (props only) | `#D63C4B` · `#6ACC39` |

- `Palette.PlotColors`, Plot_1 to Plot_6: Pink, Blue, Orange, Purple, **Yellow** and Cyan. Yellow replaces Lime,
  which vanishes against grass.
- `Palette.Departments`: Reception = the plot colour (`nil`), Wards = Purple, Hydro = Cyan, Pharmacy = Blue,
  Roof = `LeavesA`, AE = Red. These colours are used **inside only**: dado bands, curtains, blankets, headboards and
  the lift buttons.
- `Palette.Navy = #1E2440`: the Now card, every panel header, and every world information plate.
- `Palette.Outline` becomes `#1B1238`, from (24,16,52). `Palette.Gold = #FFD84A` is for gold world titles.
- `Palette.Candy` stays as it is, for the UI. It's unlit, so it keeps the brighter hues.

**Palette rules (`tests/Palette.spec`, Task 0).**
- The table above matches art-direction §4.1 exactly.
- No `World` or `Accent` colour has a channel above 245 (`World.Lamp` aside). The warm whites cap at a maximum
  channel of 240.
- `Road`, `Pad`, `Roof` and `Trunk` are dark anchors (V ≤ 0.45; road, pad and roof ≤ 0.32). V is compared at two
  decimals.
- The greens have S ≥ 0.6 and V in 0.55–0.85. V(GrassA) − V(GrassB) ≥ 0.05, and GrassB's hue is 0–15° bluer.
- Every plot colour has S ≥ 0.6 and V 0.78–0.96. Each sits ≥ 25° of hue from GrassA, ≥ 15° from pure red, and
  ≥ 15° from every other plot colour.
- `Navy == Theme.Colors.Header == Theme.Colors.NowPlate`.

**`Theme` tokens (ux audit §3.4, with Joshua's navy).** Old keys stay as aliases, as listed.

| Token | Value |
|---|---|
| Colors (chrome) | `Paper #FFFFFF` (flat: `PaperEdge = Paper`, no gradient) · `Card #EEF3FA` · `CardLine #C3D0E6` · `Well #D6E3F5` · `Locked #6A5FA0` · `Header = Navy #1E2440` · `NowPlate = Navy` · `Plate #FFFFFF` (HUD plates) · `Ink #221A48` · `InkSoft #5D5788` · `Stroke #1B1238` |
| Colors (roles) | `Primary #FF9A1F` → `PrimaryEnd #F27A0C` · `Collect #45CF3A` → `CollectEnd #2BA52A` (alias `Good`) · `Secondary #DFE6F2` (fill; ink text) · `Destructive #FF4459` → `DestructiveEnd #D9283F` (alias `Danger`) · `Disabled #B3B6C9` / `DisabledText #6E7190` · `Dot` red (unchanged) |
| Colors (meaning) | `Cash #FFD43B` · `Star #FFE228` · `Night #5B3BD6` · `Pink`/`Purple`/`Cyan` (= Candy; rarity, wing and station stripes only) |
| `Radius` | `Small 8` · `Medium 14` · `Large 22` · `Round` (0.5 scale). Aliases: `Size.Corner = Medium`, `Size.CornerLarge = Large` |
| `Stroke` | `Fine 2` · `Bold 3` · `Panel 4` · `Text 2.5` · `Title 3` |
| `TextSize` | `Caption 18` (**the floor**) · `Body 22` · `Button 24` · `Title 30` · `Number 36` · `Hero 56` · `Icon 40`. Aliases: `Small = Caption`, `Big = 48` (kept for untouched files) |
| `Space` | 4 · 8 · 12 · 16 · 24 · 32. `Gap 8` · `PadCard 12` · `PadPanel 16` · `Margin 16` (desktop) / `8` (phone) |
| `Shadow` | one: `Stroke` colour at 0.6 transparency, offset (0, 6), only under modals, the Now card and toasts |
| `Motion` | `Perpetual = 1`: at most one looping effect on screen, on the one Collect button. Dots pop once |
| `Zone` | mirrors `Logic/HudZones` constants (§B7) |

### B4. World modules (server; the split, studs, helpers)
**✚ `World/Studs` (Task 0, frozen: required task 7).**
```lua
Studs.mode(): "Variant" | "Surface"  -- "Variant" once MaterialService has a MaterialVariant named
                                     -- Config.Look.StudsVariant (checked at first use and on MaterialService.ChildAdded)
Studs.apply(part: BasePart)          -- Variant: Material Plastic + MaterialVariant "CureStuds" (every face).
                                     -- Surface: Material Plastic + TopSurface Studs (top face only; the legacy
                                     -- studs render only on Plastic) and every other surface Smooth
Studs.smooth(part: BasePart)         -- SmoothPlastic, every surface Smooth, MaterialVariant "" (roads, trim, mattresses)
Studs.refresh(root: Instance)        -- re-applies Studs.apply to every descendant with the attribute Studded = true
                                     -- (called once when the variant appears mid-session)
Studs.Pure                           -- mode(hasVariant), whole(n) (snaps to whole studs), alignedSize(size)
```
- `Studs.apply` sets the attribute `Studded = true`. That attribute is how the specs and `refresh` find studded
  parts.
- **Alignment rule (every builder):**
  - A studded part's X and Z sizes are whole studs, and odd widths are preferred: a MaterialVariant tiles from the
    face's centre, and the legacy studs from its corner.
  - It sits on the plot's whole-stud grid.
  - Check every seam in Studio in both modes (§E P3).

**✚ `World/Parts` (Task 0, frozen).** These are the generic helpers today's `PlotBuilder` already has, moved: `part`,
`soft`, `ball`, `cylinder`, `wedge`, `marker`, `paint`, `rounded`, `surface` (= `detailGui` plus `MaxDistance` and
`LightInfluence`: `surface(part, name, face, pixels, maxDistance?, lightInfluence?)`) and `iconBadge`. Task 0 adds the shared look pieces every world builder must use, so the town, the
plots and the building read as one family:
```lua
Parts.floatText(gui: SurfaceGui | BillboardGui, text: string, props: { Gold: boolean?, Shadow: boolean?,
	Size: UDim2?, Position: UDim2? }): TextLabel
	-- art-direction §4.4: no board. BackgroundTransparency 1, LuckiestGuy, white #FFFFFF (or gold #FFD84A),
	-- a 3.5 px #1B1238 UIStroke, and with Shadow a second label 2 px lower in #1B1238 at 0.5 transparency
Parts.navyPlate(gui: SurfaceGui | BillboardGui, props): Frame
	-- a board only where there's a table: Navy #1E2440 at 0.15 transparency, Radius.Large, a 4 px #1B1238
	-- stroke, white text on it (the odds sign, the leaderboards, the lift directory)
Parts.pawHeart(parent: GuiObject, size: UDim2, color: Color3): Frame
	-- our placeholder mark (the brothers design the final one): a heart (two discs and a turned square) in
	-- `color` with three white toe pads and one white main pad, inside a warm-white #F0EBDF rim; <= 8 Frames,
	-- no images. It replaces every cross
```

**Moved by Task 0, then owned by the task named.** The APIs are frozen; their implementations belong to the owner.
```lua
-- ✚ World/NightLights (T1)
NightLights.TAG = "ClinicNightLight"            -- PlotBuilder.NIGHT_LIGHT_TAG re-exports it
NightLights.tag(part: BasePart, kind: "Lamp" | "Window" | "Sign")
	-- stores the part's day Material (its name) and Color as the attributes DayMaterial and DayColor, and the
	-- kind as NightKind, then tags it.
	-- Lamp: Neon + its lights at night. Window: World.WindowNight colour, SmoothPlastic, no Neon.
	-- Sign: lights only. By day every part goes back to its own DayMaterial and DayColor
	-- (hospital §3.9 #6: today's code forces SmoothPlastic by day and would wipe studs)
NightLights.light(part: BasePart, range: number): PointLight   -- a lamp's shadowless light, off until night; tags "Lamp"
NightLights.wire()                              -- once; follows Workspace.IsNight

-- ✚ World/Props (T2): the shared scenery pieces (the town and the plots both use them; part counts are contract)
Props.tree(parent, at: CFrame, scale: number, blossom: boolean?): Model   -- <= 7 parts (voxel, §B5)
Props.bush(parent, at: CFrame): BasePart                                  -- exactly 1 part
Props.lamp(parent, at: CFrame, height: number): Model                     -- <= 3 parts, its head NightLights "Lamp"
Props.bench(parent, at: CFrame): Model                                    -- <= 3 parts
Props.fence(parent, a: CFrame, b: CFrame): Model    -- posts every 14 studs + 2 rails: <= 2 + floor(len / 14) + 1
Props.planter(parent, at: CFrame, size: Vector3): Model                  -- <= 2 parts

-- ✚ TownBuilder (T2)
TownBuilder.build(count: number): Model         -- Workspace.ClinicTown (not parented; PlotBuilder parents it)
TownBuilder.spawn(): SpawnLocation              -- TownSpawn at Origin + Config.Town.SpawnOffset (a kit one is kept)

-- ✚ HospitalBuilder (T3)
HospitalBuilder.build(plotModel: Model, level: number, grewFrom: number?, theme: string?): Model
	-- = PlotBuilder.buildBuilding (v2 §B4 contract, unchanged signature and attributes)
HospitalBuilder.Pure                            -- the building's interior layout in numbers (PlotBuilder.Pure re-exports it)
```
- **What `PlotBuilder` (T4) keeps:**
  - `buildTown()`: it calls `TownBuilder.build` and `spawn`, builds the plots, `buildQueueLane`, `ensureSignBits`,
    the Stand, then `buildBuilding(model, 1)`, then `NightLights.wire()`.
  - `buildRoom`, `placeRoom`, `setPreview`, `queueSpot`, `clearPlot`, `SLOTS`.
  - `buildBuilding`, which calls `HospitalBuilder.build`.
  - `Pure`, `NIGHT_LIGHT_TAG`, `STATION_TAG`, `LIFT_TAG` and `PROMPT_TAGS` as re-exports.

  It also sets the plot attribute **`Accent: Color3`** (its `PlotColors` entry), which `HospitalBuilder` reads.
- **Requires never loop.** `PlotBuilder` → (`TownBuilder`, `HospitalBuilder`, `World/*`). `TownBuilder` and
  `HospitalBuilder` → `World/*` only. Neither of them requires `PlotBuilder`. `BoardBuilder` takes its tag from
  `World/NightLights`, not `PlotBuilder`.

**Where studs go (art-direction §2.4).**
- **Studded (`Studs.apply`):**
  - lawns and the GrassB checker tiles;
  - plot pads;
  - every outer building wall, the podium and annex walls;
  - interior dado bands;
  - trees, bushes and hedges (voxel cubes);
  - prop tops: the existing top part of the Counter, stations, beds' headboards and planters (**no extra plate
    parts**).
- **Smooth (`Studs.smooth` or another named material):**
  - the road (SmoothPlastic);
  - curbs and plot edging (Slate);
  - paths and interior floors (WoodPlanks);
  - trim, fences, roofs and roof edges (SmoothPlastic);
  - mattresses (SmoothPlastic);
  - glass (Glass);
  - items in hand and creatures (unchanged; creatures stay round, with no studs).
- **Names the specs check:**
  - town: `Lawn` and `LawnTile` (studded), `Street` (smooth, V ≤ 0.35), `Curb` (Slate);
  - plot: `Pad` (studded, `World.Pad`), `Edge` (Slate);
  - building: any part named `Wall*` with the attribute `Outer = true` (studded, the plot's `Accent`), and `Roof*`
    and `Parapet*` (`World.Roof`).

### B5. The town (T2 builds; Config numbers in §B2; `tests/TownLayout.spec` checks the numbers)
**Layout.**
- **Street:** z −18..18, x −137..137.
- **Belt lane:** |z| ≤ 4.4 from x −121.5 to 121.5.
- **Plaza:** the street's row-2 half, x −30..30, z 5.4..17.
- **TownSpawn:** 8 × 8 at (0, 11), facing −z toward the belt.
- **Kiosks:** the Agency at (13, 12) and the Market at (−13, 12). Each is 7 × 4.5 and turns to face TownSpawn
  (v2's own code).
- **The odds sign:** at (−24, 11), facing TownSpawn.
- **Fixed:** the arches stay at x ±132 and the Hall of Fame garden stays past x −137.

**Clearances (`TownLayout.spec` on Config; `TownWorld.spec` on the built town).**
- Nothing solid sits in the belt lane except the belt itself. Flat road paint and zebra crossings under 0.3 studs
  tall are allowed.
- The spawn pad is ≥ 2 studs from the belt lane. The kiosks and the sign are ≥ 1 stud from the spawn, the lane, each
  other and the plaza's edge.
- Nothing solid sits within |x| ≤ 3, z 15..18: the row-2 middle gate's mouth.
- The street lamps (x ±39, z ±16.4) and the crossings (x ±78) are untouched.

**Look (art-direction §2.1, §4.1, §4.4).**
- **Road:** dark (`World.Road`) and smooth, with `RoadLine` edge lines and zebra crossings. The **centre dashes go**:
  the belt is the centre now.
- **Curbs:** Slate.
- **The plaza:** a plank pad (`World.Plank`) with planters, benches and lamps inside its rectangle. No pink ring.
- **Lawns:** a studded GrassA base with GrassB tiles in a checker.
  - The cells are 4 × 4 within 20 studs of the street and in the gaps between plots, and 8 × 8 elsewhere.
  - The tiles are thin studded parts, 0.2 tall with their tops 0.05 above the lawn, on whole studs.
  - When `Config.Look.CheckerTexture ~= ""`, one checker `Texture` per lawn part replaces the tiles.
- **Trees:** voxel trees from `Props.tree`.
  - 5–7 studded cubes of 2, 3 and 4 studs in `LeavesA`/`LeavesB`/`LeavesC`, on a `Trunk` block.
  - A blossom tree (Pink accent leaves) is at most 1 in 6.
- **Bushes:** one studded cube each.
- **Text:**
  - The welcome arches and kiosk signs use `Parts.floatText` (no candy board).
  - The odds sign is a `Parts.navyPlate` with a floating "🎲 NURSE ODDS" title and every odd on it. It keeps v2's
    gate line "🏥 Epic+ from Lv 3 · 🏢 Mythic/Secret from R1".
  - A "🎲 See odds" ProximityPrompt on the sign opens `Hud.oddsPopup` on the client (BeltView).
- **Riders on a centre-line belt face the plaza (+z, toward TownSpawn).** This replaces v2's "face back up the belt".
- **The leaderboard boards** (`BoardBuilder`) move onto navy plates with floating titles. Their garden lawn is
  studded.
- **BeltView:**
  - Delete the `BeltOddsChip` billboard (ux audit E1: an AlwaysOnTop, fixed-pixel fake HUD button).
  - The focused hire card gets a Quiet "🎲 Odds" button that opens `Hud.oddsPopup`, with the same rows as the sign.
  - Its text is ≥ 18 px, and its local `textLimit` becomes `Kit.textLimit`.

### B6. The hospital (T3 builds; T4 builds the Stand room and the plot around it)
**✚ `Logic/Building` (Task 0, frozen): the interface numbers everyone else depends on.** These are hospital doc §3.3,
plus the front ward. Plot-local studs: −z is the street, and y = 0 is the pad top.
- **Footprints:**
  - Lv 1, the podium: x ±11.5, z −13..3.
  - Lv 2+, ground and F1: x ±11.5, z −13..13.
  - The tower, F2 and up: x ±11.5, z −3..13.
- **Storeys:**
  - The ground storey is 11 tall; each upper storey is 9.
  - Slab tops: F1 11, F2 20, F3 29, roof deck 38.
  - **A slab is at most 0.6 thick, so its underside is ≥ 10.4.** Patients' ground raycasts start at +10 and must
    never meet a slab.
- **The lift shaft:** x −11.5..−6.5, z −3..2, with its door on +z. Its landings sit at (−9, slab top, 4) and are
  4 × 4 (`Landing_0`, `Floor_<n>.Landing`).
- **Door rects:**
  - main entrance: front wall, x 7..11, 7 tall (ground-bed patients walk in along x 7.6);
  - reception window: x −6.5..6.5, y 0..7 (the Counter sits in it);
  - display window: x −11..−7;
  - side doors (Lv 1): x ±11.5, z −1..3;
  - from Lv 2: the A&E door on the −x wall at z −7..−3; the lift-lobby door on the −x wall at z 2..6; the corridor
    door on the +x wall at z 2..6.
- **The canopy:** x −9..9, z −17..−13, at y 9.5, soft (it stops short of queue spot 1 at z −18).
- **Stand spots** (the building is built around them; T4's room uses them):
  - Remedy (−4.3, −1.3) and Plaster (1.7, −1.3): each moved +1.2 in x.
  - `Bed_1` at (7.6, −4.8), unchanged.
  - Decor slot 1 at (−8.5, −10.2), unchanged; **decor slot 2 at (−9.5, −17.5)**, on the porch.
  - **`MascotSpot` at (−7, −14.8).**
  - The waiting bench at x 10..10.9, z −8..−3.5.
- **The functional ward beds** (`Wards.BedSpot_<n>.Bed_<n>`, `Floor = 1`; F1's main ward, the tower part):
  - `BedSpot_1` at x −4.1 and `BedSpot_2` at x 1.3, from Lv 2. `BedSpot_3` at x 6.7, from Lv 4.
  - Each frame runs z −2.4..4.6, with the pillow toward −z (the glass partition at z −3). Its foot spot is z ≈ 6.0,
    in the back aisle beside the landing.
  - **Every foot spot is reachable from `Floor_1.Landing` in a straight line** that crosses no shaft, wall, bed or
    atrium. Patients walks upstairs that way (`{ target }`).
- **Checks.** `Logic/Building` exposes the rects plus `Building.clear(rect, level): boolean` and
  `Building.reach(fromXZ, toXZ, level, floor?): boolean` (the ground unless `floor` is given; it allows a 0.3-stud
  corner skim, `Building.SKIM`: see the Foundation notes). `tests/Building.spec` (Task 0) checks the numbers against what
  Patients assumes:
  - the walkways at x ±12.5 and `BackZ` 4;
  - the `bedRoute` at x 7.6 through the main door;
  - the lift-lobby and corridor doors covering z 4;
  - nothing on the Counter, the line spots, the gate, the sign, a room slot or the owner spawn (−6.5, −22).

**T3's interior layout** lives in `HospitalBuilder.Pure` (T3's numbers; `Hospital.spec` checks them).

| Lv | What's built (hospital doc §3.4, plus the front ward) |
|---|---|
| 1 | **The podium:** studded walls in the plot colour, a warm-white trim stripe, a dark flat roof (y 11), the canopy over the Counter, and the name in floating letters on the fascia (y 7–11). Inside: a waiting bench and **one dressing bed with a sleeper** along the −x wall (x −11.3..−6.9, z −8.5..−1.5, pillow toward +z). It stays clear of the −x side door (z −1..3), decor slot 1 and the Remedy table. It's a Lv 1-only piece: from Lv 2 the A&E door and the lift take that wall. No awning, no tent |
| 2 | **A two-storey block:** G plus F1 over the whole footprint (z −13..13). The A&E door with its red canopy, the bay, the lift, the G→1 flight, a dark roof at y 20 with a lift motor box. **F1 = Wards**, in two rooms (below) |
| 3 | The tower rises over z −3..13. **F2 = Hydro** (the tub, `TubSpot_1/2`, the `SoakPrompt`). F1's roof becomes a **terrace** in front of F2 (dark, parapet). The paw-heart roof-edge sign faces the street |
| 4 | **F3 = Pharmacy** (`Station_Pharmacy`, the shelf rail, a bench). `BedSpot_3` turns from a dressing bed into a functional one, in the same spot |
| 5 | **The walkable roof** (`Floor_4`): the helipad and `HeliSpot`, planters, the theme prop (≤ 6 parts), the lift tower with the **Neon paw-heart** facing the street and a beacon |

**The wards (Joshua's "wards should look full").** F1 holds **7 beds**, in two rows that fill the room:
- **The main ward** (tower part, z −3..7): the three functional bed spots above.
  - At Lv 2–3, `BedSpot_3`'s spot holds a dressing bed. From Lv 4 it's functional.
  - Its pillow ends face a **glass partition** at z −3. The upper half is glass; the headboards form the lower half.
- **The front ward** (over the podium, z −13..−3): **4 dressing beds** at x −8.1, −2.7, 2.7 and 8.1, with their
  heads at the **street window** (z −13) and frames running z −12.6..−5.6.
  - **2 of them have sleepers.** The street sees a full ward through F1's glass band.
  - A doorway in the partition at x 8.9..11.5 lets players walk through. Patients never go there.
- **Curtains:** 2 in the main ward and 2 in the front ward. **Visible beds:** Lv 1 shows 2 and Lv 2–5 show 8 (Bed_1
  plus 7).
- **Bed contract.** Beds are cheap and use **no `Texture` and no `Decal`**.

  | Piece | Parts | Notes |
  |---|---|---|
  | Functional bed `BedSpot_<n>` | 3: `Frame` (department colour, SmoothPlastic), `Headboard` (department colour, studded), `Bed_<n>` (the mattress, `World.Trim`, SmoothPlastic) | Exactly v2's names. Patients finds `^Bed_%d+$` |
  | Dressing bed `Wards.Dressing.DressBed_<n>` | 2: `Base` (mattress and frame in one block, `World.Trim`), `Headboard` (department colour, studded) | **Never named `Bed_*` or `BedSpot_*`**, so no system ever picks it |
  | Sleeper `DressBed_<n>.Sleeper` | 2: `Head` (a round Ball, 1.8–2.4 across, in a creature colour from a Data/Patients look; round, never blocky) and `Blanket` (department colour, over the base's foot two-thirds), plus a "💤" BillboardGui (studs-sized, MaxDistance 60, LightInfluence 0; 0 parts) | CanCollide, CanQuery and CastShadow all false. No `CreatureMotion` tag, no Highlight, no face images |
  | Curtain | 1, Fabric, department colour | |

**Walls, the cutaway and themes.**
- **Solid upper walls.** Every outer wall above the ground is CanCollide true, so kids can't walk out of F3. This
  changes v2's "walls above ground stay soft" (§G).
- **The `Storey` attribute.** Each piece Model, and any loose part, carries `Storey` (0 = ground … 4 = roof). Outer
  walls also carry `Outer = true`.
- **✚ `Feel/Cutaway` (T3).** It watches only the local character, and only while the character stands inside a
  plot's building footprint, 4 checks a second. Otherwise it sleeps.
  - On floor n ≥ 1, it sets `LocalTransparencyModifier = 1` on every part with `Storey > n`, and 0.6 on floor n's
    `Outer` walls.
  - It changes things only when the floor changes, and nothing replicates. The ground floor hides nothing.
  - Its PURE block is `floorOf(y, slabTops)` and `hide(n, storey, outer)`. The camera's Popper ignores any part at
    ≥ 0.25 total transparency (hospital doc §3.7), so the camera looks in.
- **Themes (v2 `Data/Themes`, unchanged data).**
  - **The outer walls always stay the plot's `Accent`.** Kids find "the pink one".
  - A theme recolours the trim and window frames (`Trim`), a **roof band** (the fascia stripe and the parapet; its
    `Roof` hex), and adds its roof prop.
  - The roof deck and roofs stay `World.Roof`.
  - `Themes.Wall` is now only a UI swatch (§G).
- **Night.** Windows are tagged `NightLights` "Window" (warm, not Neon). The paw-heart, the beacon and the sirens are
  "Lamp"/Neon, small, with one shadowless light. The ambulance keeps its name, `ArriveAt` and `StretcherSpot`
  (`Feel/HospitalFX` draws its lights).
- **Budget per building:** ≤ `Config.Look.BuildingParts` (160) at every level and theme, ≤ 12 SurfaceGuis (with
  `MaxDistance`), and ≤ 6 see-through parts.

**T4's side (the plot and rooms, hospital doc §3.8–3.9, §5.4).**
- The Stand room **loses its shell** (awning, walls, plaque). It keeps its floor, stations, `Bed_1` and decor slots,
  at the `Logic/Building` spots.
- Bath Room (Cyan), Cozy Ward (Purple) and Winter Wing (Blue) become **single-storey annexes**:
  - three studded walls in the room colour;
  - a dark flat roof with a warm-white trim edge;
  - the room's name in floating letters on that edge;
  - a wood-plank floor;
  - the same open front, so stations and patients work unchanged.
  - The Winter Wing keeps one snow slab.
- The Garden is studded hedges and an arbor.
- **The plot:**
  - a dark studded `Pad` with 4 Slate `Edge` parts;
  - a plank path and 2 stones;
  - the fence from `Props.fence` (posts every 14 studs);
  - trees from `Props.tree`: the one at (16.5, −9) moves to (18.5, −10), clear of the podium;
  - one-cube bushes;
  - the queue lane: 6 tiles instead of 12, with each number on its spot disc.
- **The sign** floats its text (`Parts.floatText`, no board) and keeps `SignGui.{OwnerName,HeartCount,RankBadge,
  BranchBadge}`.
- **Decor** (`DecorBuilder`): studded tops on the existing top parts and the §B3 palette. No part-count increase.

### B7. The HUD (T5; `Logic/HudZones` is Task 0's)
**✚ `Logic/HudZones` (pure, frozen; ux audit §3.1).**
```lua
HudZones.ZONE: { [Piece]: Zone }
	-- Settings = "System" · Cash, Stars = "Wallet" · Now = "Now" · Clock, Event, Visitor, Boosts = "Status"
	-- Shop, Nurses, Book, Badges, Boards = "LeftRail" · Gifts, Goals, Mailbox = "RightRail" · Hands = "Bottom"
HudZones.ORDER = { LeftRail = { "Shop", "Nurses", "Book", "Badges", "Boards" }, RightRail = { "Gifts", "Goals", "Mailbox" } }
HudZones.layout(safeW: number, safeH: number, topbar: number?): Layout
	-- Layout = { Phone: boolean, Button: number, Gap: number, Captions: boolean, WalletInTopbar: boolean,
	--   Left: { Piece }, Right: { Piece }, More: { Piece } (moved into ⚙️ More), Band: { Top: number, Bottom: number },
	--   Margin: number, NowWidth: number }
HudZones.nowWidth(safeW: number, walletRight: number): number  -- min(480, safeW - 2 * (walletRight + 8))
-- constants: PHONE_BREAK = 440 (safe height) · RAIL_BUTTON = 72 (max) / RAIL_BUTTON_MIN = 56 · RAIL_GAP = 10 /
--   RAIL_GAP_PHONE = 8 · CORNER_CLEAR = 110 · TOPBAR = 58 (fallback; read GuiService.TopbarInset) ·
--   WALLET_HEIGHT = 112 / WALLET_WIDTH = 240 (desktop) · NOW_HEIGHT = 88 (NOW_HEIGHT_SHORT = 76 under 500 px tall) ·
--   NOW_TAB = 24 · NOW_SLIM = 44 · NOW_MAX = 480 · STATUS_WIDTH = 260 (STATUS_WIDTH_PHONE = 180)
-- also: HudZones.railRect(layout, side, index, safeW) · HudZones.nowRect(layout, safeW)
```
- **The rules.**
  - Every piece belongs to exactly one zone, and its slot index never changes. A piece that isn't revealed leaves
    its slot empty.
  - **Phones** (safe height under 440) get exactly 3 a side: 🛒 👩‍⚕️ 📖 on the left and 🎁 🎯 📬 on the right. They
    show 56 px plates with no captions. 🏅 Badges and 🏆 Top go into ⚙️ **More**, and the wallet moves into the
    top-bar row.
  - **Desktop and tablet** put the wallet top-left, above the left rail. The left rail shows as many of its 5 as fit
    at ≥ 56 px (≤ 72) with captions, at least 3. The rest go into ⚙️ More. The right rail always shows 3.
  - The rail band runs from the top bar + 8 (plus the wallet on desktop) down to `CORNER_CLEAR` above the bottom.
    Nothing is ever in the bottom corners.
- **`HudZones.spec` cases** (from the audit's table):
  - 800×360, 667×375, 844×390 and 932×430 → phone, 3 + 3, 56 px, More = Badges and Boards.
  - 1280×720 → 5 left at 72.
  - 1024×600 → 4 left, Boards in More.
  - Every piece is in exactly one zone. No rail rect meets the bottom corner zone or the Now rect.
  - `nowWidth` never covers the wallet.

**`Hud` API additions** (Task 0 stubs, which T5 makes real; every existing `Hud.*` helper keeps its signature):
```lua
Hud.setNow(source: string, card: GuiObject?, priority: number)
	-- offer a card to the top-centre Now slot (nil removes it). The highest priority shows; Hud parents it,
	-- centres it and sets its width (HudZones.nowWidth); the card sets its own height (88/76 + a 24 tab, or the
	-- 44 slim strip). Priorities: 30 Hud's warnings (⚠️ not saving, 🏠 no clinic) · 20 "Tutorial" (T8) ·
	-- 10 Hud's tracked goal (the first unfinished daily goal: "🎯 Cure 5 · 3/5", tap opens Goals)
Hud.nowBottom(): number          -- px from the screen top to the Now card's bottom (0 when empty)
-- re-exports from Modal (Task 0 writes them; T5 keeps them):
Hud.modal, Hud.isOpen, Hud.confirm, Hud.oddsPopup, Hud.fitTabs, Hud.fitHeight
```
**The zones' contents** (T5; ux audit §3.1 and §3.5):
- **System:** a `ScreenInsets = TopbarSafeInsets` ScreenGui beside Roblox's buttons, holding ⚙️ (a dark-glass Icon
  plate).
  - The ⚙️ panel keeps today's rows: 🎵, ✨/💤, 👆 Simple, 👥 helpers and 🛠️ Admin.
  - It adds **"⏭️ Skip tutorial"** while `TutorialLogic.active`, and **"🔁 Replay tutorial"** while `isDone` and
    you own a clinic. Each fires a bus event (below). T8 owns the confirm and the remote.
  - On phones it also holds More: 🏅 and 🏆.
- **Wallet:** 💰 and ⭐ as an icon plus a big outlined number (`TextSize.Number`), with **no pills**. ⭐ keeps its
  thin bar and the next-unlock icon, and stays tappable. The roll-ups, the "+n" and the 🔥 combo sticker stay.
- **Now:** the slot above. **Toasts stack under it** (`Hud.nowBottom()` + 8). There's one notice stack: toasts and
  banners as white plates with ink text, a banner adding an icon tile in its event's colour.
- **Status** (top right, right-aligned, read-only):
  1. Day or night, with words: "☀️ Night in 3:27" / "🌙 ×2 · 2:08 left".
  2. **One free-event chip:** `NextEvent.pick` over Golden Hour (`Workspace.GoldenStartsAt`), in minutes ("🌟
     Golden Hour in 12m"). It's hidden during the event, when the next is more than 6 h away, and for anything paid.
  3. "Visitor ✅" / "Visitor ⭐", with words.
  4. At most 3 small boost chips.
- **Rails:** one white Icon plate per button (3 px `#1B1238`, emoji at 60%, a red dot top-right).
  - Every rail button has the same fill. Identity comes from the icon and caption, never the fill. **The Shop looks
    like its neighbours.**
  - 🎁 moves here from under the wallet, with its bar inside the plate.
  - v2's 🛒 Branch dot (`Hud.shopNews(...).Branch`, the 🃏/🌳 sticker) stays on the 🛒 rail button. The 🌳 points
    and sold-nurse coins fly to it (`Hud.target` names unchanged).
- **Bottom centre:** only your hands. The bottom bar is gone.
- **When things open:**
  - **A Panel:** the rails, Now and Status fade out. The wallet stays.
  - **`HudMode "Game"`** (the mini-game): the rails and Status go, the wallet stays, and the Now card stays (T8
    shrinks its card).
  - **A Popup:** nothing changes.
  - **Celebrate:** everything hides.
- **First session:** the same fixed slots, revealed one by one as the HUD reveals itself today. At DONE the rest pops
  in, one button every 0.15 s.
- **Fill budget:** at most 3 saturated fills in the HUD at once (the event chip, the night chip, red dots). **One
  perpetual effect** on screen.

**Bus events (client):**

| Event (args) | Fired by | Heard by |
|---|---|---|
| `ModalOpened (name, hudMode)` · `ModalClosed (name, hudMode)` | Modal (T6) | Hud (T5), Tutorial (T8) |
| `SkipTutorial ()` · `ReplayTutorial ()` | Hud ⚙️ rows (T5) | Tutorial (T8): shows the confirm, asks the remote |
| `Celebrate (info)` with Kind `"Tutorial"` | Tutorial (T8, client-local) | Celebrate (T8) |
| `TreatStart` · `TreatDone` (existing) | MiniGames (T6) | Tutorial (T8: card 4, the slim strip) |

### B8. One modal template, one tab, one text fit (T6 owns `Modal` and `Kit`; Task 0 writes the first versions)
```lua
Modal.modal(ctx, spec: ModalSpec): Modal   -- = Hud.modal; ModalSpec as today, plus:
	-- HudMode: HudMode? (default "Panel" for Layer Panel, "None" for Popup) · Meta: string? (the header's one
	-- meta chip: "📔 6%", "💰 726"; modal.setMeta(text)). spec.Accent is accepted and IGNORED: every header is Navy
Modal.tabs(modal: Modal, tabs: { { Id: string, Icon: string, Caption: string, Stripe: Color3? } },
	onSelect: (id: string) -> ()): { select: (id: string) -> (), Column: Frame, Content: Frame }
	-- THE tab pattern: a left column of square tabs (Hud.fitTabs sizes them), painted by Kit.tab
Modal.confirm(ctx, spec: { Title: string, Line: string, Yes: string, No: string?, Kind: ("Primary" | "Destructive"
	| "Collect")?, Hold: number? }, onYes: () -> ())
	-- a 420 x 360 Popup on the same shell. "Not now" (spec.No) is the default focus; Hold > 0 makes Yes a
	-- Kit.holdButton of that many seconds
Modal.oddsPopup(ctx, spec: { Title: string, Rows: { { Icon: string, Name: string, Percent: number } },
	Notes: { string }? })
	-- one odds popup for the belt (sign, hire card), the Agency and the Journal: each row shows the word and the
	-- number ("Rare 20%"), as Roblox's paid-random-item guidance asks, even though these use in-game cash
Kit.tab(button: GuiButton, selected: boolean, stripe: Color3?)
	-- unselected: Card fill, ink caption · selected: Header (navy) fill, white outlined caption, a 3 px outline ·
	-- stripe: a 6 px left edge in the section's own colour (a wing, a rarity, a board)
Kit.textLimit(label: TextLabel | TextButton, maxPx: number)
	-- UITextSizeConstraint: MinTextSize = Theme.TextSize.Caption (18), MaxTextSize = max(maxPx, 18)
Kit.button(props) -- Kind gains the roles: "Primary" · "Collect" · "Secondary" · "Quiet" · "Destructive" · "Icon"
	-- old kinds map: Good -> Collect, Danger -> Destructive, Pink/Purple/Cyan/Cash -> Secondary, Card -> Quiet
```
**The template** (ux audit §3.2, Joshua's navy):
- **Header:** a 64 px **Navy** band holding the icon and a title of at most two words (display font, white, 3 px
  stroke), one meta chip (white, ink text), and the red ✖ at 56 × 56. That ✖ is the only red on the chrome.
- **Body:** flat white paper with cards on it (`Card` with a 2 px `CardLine` stroke). Each card has a tile (`Well`,
  Medium radius; locked silhouettes `Locked`), a name (22), one info line (18), and one action.
- **Footer:** optional, with **one** Primary action at most.
- **Shadow:** one, from the token.
- **Rows never cycle candy colours.** Icon tiles are neutral (`Well`). A section's own colour is only a tab's 6 px
  stripe or its own tile.
- **Roles (ux audit §3.3):**
  - Buy, Hire, Level up and List are **Primary**, one per view.
  - Claim, Open!, Yay! and ✅ Take it are **Collect**. This is the only role that may shine or breathe.
  - Everything else is **Secondary**. Links ("See odds", "What's next?") are **Quiet**.
  - Sell, Reset and Throw away are **Destructive**, always behind `Hud.confirm` or a hold.
  - Locked or gated buttons are **Disabled**, with a gate chip ("🏥 Lv 3"). No lock teases on paid items.
- **Rules every panel file follows (`uirules` checks them):**
  - no `MinTextSize` below 18, and no literal `TextSize` below 18;
  - no local `paintTab` or `textLimit` copies;
  - corner radii only from `Theme.Radius`, and strokes only from `Theme.Stroke`;
  - no panel-specific header colour;
  - confirms only through `Hud.confirm`, and odds only through `Hud.oddsPopup`.
- **`MiniGames`** (T6) moves onto `Modal.modal`: Layer Panel, `HudMode "Game"`, no ✖, no dim-close. It also
  exposes:
  ```lua
  MiniGames.stage(): GuiObject?   -- the current game's stage, for T8's touch hand (nil when none)
  ```
  - It hides the Patch game's draining time bar while `TutorialLogic.active`. OK still cures.
  - Its pad prompts use `UserInputService:GetImageForKeyCode`: ✕ on PlayStation, never "🅰️".
  - It keeps v2's auto ✨ PERFECT, Ease, the Soak card and the Triage buttons exactly.

### B9. The tutorial (T8; `Logic/Tutorial` is Task 0's)
**`Logic/Tutorial` changes (pure; `tests/Tutorial.spec`, Task 0):**
- **Cards and events.**
  - `Tutorial.CARDS = 7`.
  - `card(step, treating?)` maps WELCOME/PATIENT → 1, MAKE → 2, TREAT → 3 (4 while `treating`), REST → 5,
    MORE → 6, SHOP/BOOK → 7, and DONE → nil.
  - `Event` gains `"Skip"` (any active step → DONE) and `"Replay"` (DONE → PATIENT). Replay is the one deliberate
    exception to "steps only go forward", and the header says so.
- **Timing.**
  - `spawnPlan(WELCOME, plotEmpty)` → `"First"`, so the first patient hops in during the sweep. Patients already
    handles "First".
  - `ARRIVED_SECONDS = 1`, from 2.
- **The new helpers.**
  - `nudge(step)`: true for MAKE, TREAT and MORE (the walking steps).
  - `canSkip(step)` = `active(step)`.
  - `canReplay(step, hasPlot)` = `isDone(step) and hasPlot`.
  - `giftDue(step, gifted)`: true when entering SHOP and not gifted.
  - `CARD_NAMES = { "Meet", "Make", "Give", "Pour", "Rest", "More", "Upgrade" }`, for the funnel.

**Server (`Server/Tutorial`, T8).**
- The two remotes (§B1).
- `move()` gives the top-up only when `not d.TutorialGift`, and sets it in the same `PlayerData.update`.
- `Tutorial.setReopen(fn)` is called once by `Main.server` with `Patients.reopen`. Patients requires Tutorial, so
  Tutorial can never require Patients.
- **The onboarding funnel:**
  - On a first run only (not a replay), call
    `pcall(AnalyticsService.LogOnboardingFunnelStepEvent, AnalyticsService, p, card, CARD_NAMES[card])`. This is
    server-only and works only in published games.
  - A Skip logs a custom "TutorialSkipped" event with the step. It never logs a later funnel step, which would mark
    the skipped ones done.

**Client (`UI/Tutorial`, T8; tutorial-ux §3):**
- **The card.** A Now card offered with `Hud.setNow("Tutorial", card, 20)`:
  - Navy, with the "TUTORIAL n/7" tab in gold outlined display text and a Skip chip (a 56 × 44 hit area). The chip
    is never selectable by a gamepad; pads use ⚙️.
  - A thumbnail of the target's icon (it flips to ✓ on success), a white caps title, and a gold subtitle.
  - A 7-segment bar that fills on success and never drains.
  - The guide nurse's portrait (`Hud.portrait(Data/Guide.Look)`) peeks out with 2–4-word lines.
  - It uses `TextSize` + `AutomaticSize`, not `TextScaled`, so Larger Text works. Nothing under 18.
- **The cards' words** (tutorial-ux §3.3). `[E]` is `GetStringForKeyCode`; `[□]` is the pad's real glyph.

  | Card | Server step | Title | Subtitle | World |
  |---|---|---|---|---|
  | 1 | PATIENT (WELCOME after the sweep) | A SICK CREATURE! | "🤧 Look at its bubble", then "It needs a 🧪!" | the pin 👀 and glow on the patient; no beam |
  | 2 | MAKE | MAKE A POTION | "Follow the arrows · hold [E]" / "· hold 👆 Make" / "· hold [□]" | the beam to the 🧪 table's base, chevrons, glow, pin; the touch hold hand |
  | 3 | TREAT | GIVE IT THE POTION | "Go to the glowing Counter · [E]" / "· tap Treat" / "· [□]" | the beam to the Counter's base, glow, pin |
  | 4 | TREAT, while treating | POUR IT IN! | "Hold… let go on ⭐" | the slim strip; the touch hand on `MiniGames.stage()` |
  | 5 | REST | RESTING… then **CURED! 🎉** | "🛏️ It's getting better" | the pin 🛏️ over the bed; on the cure: rays and confetti behind the thumbnail (`Kit.celebrate`), held `FirstCureHold` |
  | 6 | MORE | CURE 2 MORE ○○ | follows the patient ("🤕 New patient! Check its bubble" / "It needs a 🩹!" / "Now to the Counter · [E]") | the Guide's targeting, drawn with the beam |
  | 7 | SHOP → BOOK | UPGRADE YOUR CLINIC | "Tap 🛒 · buy a ⚡" / "Click 🛒 · buy a ⚡" / "[A] on 🛒" | the UI pointer: a 55% dim with a cutout round the 🛒 **rail** button, a ring, a ripple and a hand; in the Shop, the cheapest upgrade's Buy ("Buy this! ⚡"); pad focus through `GuiService.SelectedObject` |

  The word "Spend" never appears, and the pointer never lands on anything paid.
- **Success beats.** Each ✓ holds `SuccessHold` before the next card slides in: a 12-piece confetti burst, a Chime,
  the segment filling.
- **The finale** fires `Celebrate { Kind = "Tutorial", Title = "YOU DID IT!", Chips, Next }` locally, where `Next` is
  `NextEvent.pick` over Golden Hour, the next night (`PhaseEndsAt` while it's day) and the next play gift. After it,
  the HUD's staggered reveal runs (T5), and a ring sits on 📖 for a few seconds.
- **The welcome.** The 3 s sweep stays (with reduced motion, only the title card). The client acks **when the sweep
  ends**, and the 4 s welcome card goes.
- **Skip** opens `Hud.confirm`:
  - **Title** "⏭️ Skip the tutorial?"
  - **Line** "You can replay it any time from ⚙️" (binding text)
  - **Yes** "⏭️ Skip" · **No** "Keep going" (the default)

  Then the `TutorialSkip` remote. The Guide keeps the beam, glow and pin until `ArrowsUntilCures` cures.
- **Replay** (from the ⚙️ row's bus event) opens `Hud.confirm`:
  - **Title** "🔁 Replay the tutorial?"
  - **Line** "Your waiting patients go home"
  - **Yes** "🔁 Replay" · **No** "Not now" (the default)

  Then the `TutorialReplay` remote. While replaying there's no sweep, the HUD stays full, there's no gift, and it can
  be skipped again.
- **The idle nudge.** After `NudgeSeconds` without progress on a walking step, the nurse says "Psst! Follow the
  arrows ➜" and the beam brightens once for 0.4 s. It happens once per step, never shows a number, and counts no time
  while a panel is open.

**✚ `UI/Wayfinder` (T8; a library, so nothing runs until `show`; tutorial-ux §5.3–5.7):**
```lua
export type Spec = { Target: Instance, Base: Vector3?, Icon: string, Color: Color3, Beam: boolean?, Glow: boolean?,
	Hand: ("Hold" | "Tap")? }
Wayfinder.show(spec: Spec)          -- the same Target again updates in place (no flicker, no re-pop)
Wayfinder.hide() · Wayfinder.attach(character: Model) · Wayfinder.destroy()
Wayfinder.Pure                      -- feetY, beamStart, endAnchor, needsBend, chevronSpots, near (tests/TutorialFlow)
```
- **The beam (the main cue; Joshua: "closer to the floor", "connect the middle of the player body ... to the
  objective").** It is a client-only flat Beam:
  - It starts at `GuideStart`, an Attachment on the HumanoidRootPart at feet + `BeamLift`.
  - It ends at `GuideEnd` on `Workspace.Terrain`, at the target's base: the closest point of its footprint, 0.3 out,
    on the floor (+ `BeamEndLift`).
  - Its values: FaceCamera **off**, CurveSize 0, Width 1.6, TextureMode Wrap, TextureLength 2, TextureSpeed 1.5 (0
    when calm), LightEmission 0, LightInfluence 0, and the fade `NumberSequence` from §5.5.
  - It is re-aimed each frame **only while it shows and the root moved** (two CFrame writes; the 2024 DevForum roll
    recipe).
  - It bends round the Counter (knees, at most 4 spans) and hides within `NearStuds`.
- **The floor chevrons:** at most 6 client-only parts, 4 × 0.05 × 4, each with a Top SurfaceGui of two rotated bars,
  white at 55%. They're static, every `ChevronGap` along the route, and hide with the beam.
- **The glow:** **one** Highlight, re-pointed and never re-made (DepthMode Occluded; fill the target's colour at 0.8,
  a white outline pulsing 0 ↔ 0.35 over `GlowSeconds`, steady when calm). It's deleted when the Guide finishes.
- **The pin:** the existing candy pin, moved here from `Guide`. It drops lower when the camera is within 10 studs.
- **The touch hand:** a 👆 pressing beside the station's prompt while `PromptShown`.
- **`Guide`** keeps choosing targets and the v2 hold times (MakeRush and TeamMake), and draws through `Wayfinder`.
  Its overhead arc goes. Its `Steer` gains `Glow`, `Hand` and `Base`, and it re-syncs on
  `GuiService.ReducedMotionEnabled` changing too.
- **✚ `Data/Guide` (Task 0):** `{ Name = "Guide Nurse", Look = <an original Look table in the nurses' format> }`.
  The name is a placeholder that the UI never shows; the brothers name and design it (OPEN #1). It isn't one of the
  17 hireable nurses.

**✚ `Logic/NextEvent` (pure, Task 0):**
```lua
NextEvent.pick(now: number, candidates: { { Id: string, Icon: string, Name: string, At: number, Paid: boolean? } },
	maxAhead: number?): NextEventView?   -- the soonest At > now within maxAhead (6 h); ties keep list order;
	                                     -- NEVER one with Paid = true (red line 3)
NextEvent.label(seconds: number): string -- "in 12m" · "in 1h 5m" · "in 1m" for anything under 2 minutes;
	                                     -- minutes only, never seconds
```

### B10. Boot and load order
- **`Main.server`.** Boot order is unchanged. After `Patients` and `Tutorial` start, it calls
  `Tutorial.setReopen(Patients.reopen)`.
- **`Main.client` UI order.** Unchanged except that `Modal` and `Wayfinder` are libraries (no `init`): Toasts, Hud,
  Shop, BookPanel, DayReportPanel, Mailbox, PlayGifts, BadgeBook, Guide, PromptFilter, AdminPanel, Boards, Celebrate,
  MiniGames, NursePanel, BeltView, AgencyPanel, MarketPanel, BranchPanel, LiftPanel, Tutorial.
- **`Main.client` Feel order:** Sounds, CureFX, Atmosphere, CreatureMotion, CreatureActing, HospitalFX, **✚
  Cutaway**.
- **Requires never loop:**
  - `Modal` → (`Kit`, `Theme`). `Hud` → `Modal`. `Tutorial` → (`Hud`, `Kit`, `Wayfinder`, optional `Guide`, `Shop`,
    `MiniGames`). `Guide` → `Wayfinder`.
  - No UI module requires `Tutorial`.

---
## C. Numbers, and why
**C1. Lighting (T1, `DayNight.luau`; art-direction §4.3; Claude's starting values, tuned by measurement).**
- **Set once in `start()`:** `LightingStyle = Soft`, `PrioritizeLightingQuality = true`, `GlobalShadows = true`, and
  both `ColorShift`s (0,0,0). Make a `SunRaysEffect` (named `CureRays`) if the place lacks one. No Clouds: they're
  optional and cost perf.
- **Tweened in the Look tables:**

| Property | Day | Night | Before (day / night) |
|---|---|---|---|
| Brightness | 2.25 | 1.0 | 2.6 / 1.2 |
| ExposureCompensation | 0 | 0 | (place) |
| Ambient | (70, 68, 84) | (54, 44, 110) | (124,120,146) / (100,74,196) |
| OutdoorAmbient | (128, 128, 140) | (82, 68, 150) | (166,160,186) / (124,94,228) |
| EnvironmentDiffuseScale · EnvironmentSpecularScale · ShadowSoftness | 0.6 · 0.15 · 0.15 | 0.4 · 0.15 · 0.15 | (place) |
| CandyColor: Brightness · Contrast · Saturation · Tint | 0 · 0.12 · 0.08 · (255,251,244) | 0 · 0.15 · 0.05 · (222,214,255) | 0.02 · 0.08 · 0.2 · white / 0.03 · 0.1 · 0.28 · (226,214,255) |
| Atmosphere: Density · Offset · Color · Decay · Haze/Glare | 0.26 · 0.15 · (150,198,240) · (104,150,214) · 0/0 | 0.32 · 0.12 · (74,64,152) · (40,32,104) · 0/0 | 0.24 · 0.2 · (198,230,255) / 0.3 · (128,104,222) |
| Bloom: Intensity · Size · Threshold | 0.25 · 20 · 2 | 0.6 · 24 · 1.3 | 0.3/24/2 · 0.55/24/1.6 |
| SunRays: Intensity · Spread | 0.04 · 0.45 | 0 · 0 | none |

Why: the measured frames sit at mean V 0.95, luma P10 140 and 35% pale (art-direction §1.2), against the top games'
V 0.74–0.88, P10 24–96 and 2–16% pale. Lower the fill and the grade's lift, stop the lerp-to-white, and add dark
anchors. **Tune in this order:** OutdoorAmbient, then Brightness, then EnvironmentDiffuseScale, and touch the grade
last, until §E P1/P2's numbers hold.

**C2. Studs.** One shared MaterialVariant (0 parts, one texture set) or the legacy top surface (0 parts).
- **No Textures:** a Texture per face adds a draw call (Creator Hub).
- **Why it reads on phones:** a stud spans about 771 / distance px, so ~50 px at 15 studs and ~8 px at 100. Studs
  read near you and melt into their colour far away.
- **The test:** quality 1, 4 and 10 (§E P3). If far lawns shimmer, use the 8-stud cells there.

**C3. Parts per plot at Lv 5, every room, any theme** (`tests/PartBudget.spec` fails over 400; per-owner shares in
`Config.Look`). The "new" column comes from hospital doc §5.3–5.5 plus the wards (Claude's count; the specs measure
the real numbers):

| Lv | Building (T3; doc + wards) | Rooms (T4, lean) | Plot (T4, lean) | Total | v2 today (Candy) |
|---|---|---|---|---|---|
| 1 | 19 + 4 = **23** (+ the Lv 1 dressing bed 2, sleeper 2) | | | **≈ 202** | 297 |
| 2 | 65 + 26 = **91** (front-ward shell 10, 4 dressing beds 8, 2 sleepers 4, 2 curtains 2, BedSpot_3's dressing bed 2) | | | **≈ 270** | 339 |
| 3 | 88 + 26 = **114** | | | **≈ 307** | 348 |
| 4 | 111 + 24 = **135** (BedSpot_3 is functional now) | | | **≈ 328** | 362 |
| 5 | 131 + 24 = **155** | **≤ 82** | **≤ 111** | **≈ 348** (52 spare) | 372 |

- **Shares to hold:** building ≤ 160 · rooms ≤ 90 · plot ≤ 115 → ≤ 365, so at least 35 spare under 400.
- **If it doesn't fit, trade in this order** (Joshua's wards come last):
  1. bushes → 0;
  2. one tree per plot;
  3. the queue lane's tiles → 4;
  4. the sleepers' blankets (−2);
  5. the front ward's curtains (−2);
  6. the sleepers (−4);
  7. only then 2 of the 4 front-ward dressing beds (−4).

  Never cut a functional bed, a slab, a landing, the lift or the stairs. Report any cut in the playtest log.
- **The town** (not per plot): `ClinicTown` ≤ 600 parts, including the GrassB tiles (about 220 at 4/8-stud cells).
  The belt, kiosks and boards keep their own v2 caps.

**C4. Beds.** Functional beds stay exactly `Data/Levels.Beds` (1, 3, 3, 4, 4), with no gameplay change. The visible
beds are 2 at Lv 1 and 8 at Lv 2–5, with 7 of them on the Wards floor. Why:
- Joshua's "wards should look full" is met by dressing beds and sleepers at 2 parts each.
- Patients, Treatment and the v2 specs stay untouched.
- With the line capped at 3, extra functional beds would mostly stand empty anyway.

Raising `Levels.Beds` is a one-line data change, but every new functional bed must be straight-line reachable from a
landing. The front ward isn't, without a Patients change. That's in §F.

**C5. HUD sizes:** `Logic/HudZones` (§B7). On phones the band is 184–254 px, so 3 a side at 56 + 8. At 1280 × 720
it's about 430, so 5 at 72 + 10 (ux audit §3.1).

**C6. Tutorial:** `Config.Tutorial` (§B2). The beam values are tutorial-ux §5.5's. The first ✓ lands about 8–10 s
after control returns, and the first 💰 at about 20–35 s (an estimate; the funnel measures it).

---
## D. Tasks
### Task 0: Foundation (lead, first, then frozen). Load `roblox-luau`, `roblox-studio-workflow`.
Also does **required task 7** (studs: `World/Studs` and its spec) and the **token half of required task 1** (Palette
and Theme).
- [x] **Gate:** v2 is merged into `claude/trusting-carson-5v32sr`. Cut `.worktrees/look` (`claude/look-overhaul`).
  Run every gate and record the baseline spec count in this plan. **Baseline: 1,000 specs, 42 files, lint clean.**
- [ ] **Records first** (the lead): `memory-20261117-002` (Joshua's beds + replay, verbatim) and `-003` (Claude's
  defaults, provisional, Joshua can overrule).
- [ ] **Config** (§B2), **Types** and **Remotes** (§B1: `TutorialSkip`, `TutorialReplay`; until T8 serves them they
  answer `false, "Coming soon!"`), **Palette** (§B3, with every old key aliased), **Theme** (§B3 tokens, with every
  old key aliased).
- [ ] **Logic:**
  - `Tutorial` (§B9) and `Schema` (`TutorialGift`, §B1);
  - ✚ `HudZones` (§B7), ✚ `NextEvent` (§B9), ✚ `Building` (§B6);
  - each with a spec.
- [ ] **✚ `Data/Guide`** (a placeholder name and an original look).
- [ ] **The splits**, behaviour unchanged, with every v2 spec still passing:
  - [ ] `PlotBuilder` → `World/Parts`, `World/Props`, `World/NightLights`, `TownBuilder` and `HospitalBuilder`
    (§B4). The facade and re-exports stay, plus the plot attribute `Accent`.
  - [ ] `Hud` → `Modal` (§A notes). Hud keeps the re-exports and gains the `setNow`/`nowBottom` stubs: a plain frame
    at the top centre, and 0.
  - [ ] Move `Hospital.spec`'s Instance mock into ✚ `tests/worldmock.luau`, with `MaterialService` and a switch for
    the variant. Hospital.spec, the new world specs and PartBudget all use it.
- [ ] **✚ `World/Studs`** (§B4) and **✚ `World/Parts`'s** `floatText`, `navyPlate` and `pawHeart`.
- [ ] **First versions:**
  - `Kit.tab`, `Kit.textLimit` and the role aliases (`Collect`, `Destructive`, `Icon`);
  - `Modal.tabs`, `Modal.confirm` and `Modal.oddsPopup` (working and plain; T6 restyles them);
  - `Modal.modal`'s header from `Theme.Colors.Header`, ignoring `Accent`;
  - `HudMode` in the `ModalOpened`/`ModalClosed` events;
  - `MiniGames.stage()` returning nil.
- [ ] **Stubs:** ✚ `Wayfinder` (§B9 API; `show` draws today's pin) · ✚ `Feel/Cutaway` (`init` does nothing) ·
  `Server/Tutorial.setReopen`, and the two remotes answering "Coming soon!" (each marked `-- STUB (T8)`).
- [ ] **`State`** (`TutorialReplay`), **`Main.server`** (`setReopen`), **`Main.client`** (Cutaway in the Feel
  order).
- [ ] **Specs:**
  - `Tutorial` (Skip, Replay, the card map, nudge, `spawnPlan` First at WELCOME, the `canReplay` table);
  - `Schema` (`TutorialGift`: derived when missing; kept when boolean; junk);
  - ✚ `Palette` (§B3 rules and tokens: every `Theme.TextSize` ≥ 18; Header = Navy = NowPlate);
  - ✚ `HudZones` (§B7 cases);
  - ✚ `NextEvent` (soonest, ties, Paid never, maxAhead, the labels);
  - ✚ `Building` (the clearance and reach checks of §B6);
  - ✚ `Studs` (both modes under the mock: Plastic plus variant on every face, or Plastic plus top Studs only;
    `smooth`; `refresh`; `alignedSize`);
  - ✚ `TownLayout` (§B5 clearances on Config);
  - ✚ `PartBudget` (v2's test moved: every level × 6 themes ≤ 400; it prints the per-level counts).
- [ ] **Helpers:**
  - ✚ `tests/uirules.luau`: `check(paths): { violation }`, covering MinTextSize < 18, literal TextSize < 18, local
    paintTab or textLimit, corner literals outside the tokens, and header colours;
  - ✚ `tests/look.luau`: `hsv`, `luma`, `isBigFace(part, area)`.
- [ ] **README:**
  - the World modules and the split;
  - Studs (both modes, and the Studio step for the variant);
  - the HUD zones;
  - Skip and Replay;
  - the test switches unchanged.
- [ ] All gates pass. Commit: "Look overhaul foundation: tokens, studs, world split, HUD zones, tutorial logic,
  stubs".

### T1: Lighting (required task 1). Load `roblox-studio-workflow`.
- [ ] `DayNight.luau`: the §C1 values, plus a PURE block with the Look tables as plain RGB numbers (converted to
  Color3 outside the block) and the night-dimmer-than-day rule.
- [ ] `World/NightLights.luau` (§B4):
  - store and restore each part's DayMaterial and DayColor, so studded Plastic and Glass survive the day;
  - "Window" goes warm (`WindowNight`), not Neon;
  - no light casts shadows.
- [ ] ✚ `Lighting.spec`:
  - the Look tables match §C1;
  - every night value is ≤ its day value (Brightness, Ambient, OutdoorAmbient);
  - the night's Bloom threshold is lower than the day's;
  - the restore rule: a studded part tagged and toggled night → day → back to Plastic with its variant.
- **Acceptance:**
  - [ ] The specs pass. The enum settings are set in `start()` (read in code; Studio confirms in §E P1).
  - [ ] Nothing else in DayNight's API changes (`IsNight`, `PhaseEndsAt`, `SkipPhase`).

### T2: Town world (required task 2). Load `roblox-studio-workflow`, `roblox-ui`, `game-ui-ux`.
- [ ] `TownBuilder` (§B5): the dark smooth road with its edge lines and crossings (no centre dashes), Slate curbs,
  the row-2 plaza (planks, benches, lamps, planters), TownSpawn at `SpawnOffset`, the studded GrassA lawns and GrassB
  checker tiles (4/8 cells, or `CheckerTexture` when set), and the welcome arches with floating text.
- [ ] `World/Props`: voxel trees (≤ 7 parts, blossom ≤ 1 in 6), one-cube bushes, lamps, benches, `fence` (posts
  every 14), planters.
- [ ] `NurseBelt`:
  - [ ] It runs from `Config.Belt.Offset` (z 0), and riders face the plaza.
  - [ ] The sign is a `Parts.navyPlate` at `SignOffset` with the floating title, every odd, the gate line and a
    "🎲 See odds" prompt.
  - [ ] The nurse house is studded, with floating text and the `NextLamp` kept.
- [ ] `BeltView`:
  - [ ] Delete `BeltOddsChip`.
  - [ ] The hire card gets a Quiet "🎲 Odds" button → `Hud.oddsPopup`, and the sign prompt → the same popup.
  - [ ] Text ≥ 18 through `Kit.textLimit`.
  - [ ] Keep every v2 belt behaviour: price, the R1 gate, Roster full, the 🔭 chip, the lamp.
- [ ] `BoardBuilder`: the boards on navy plates with floating titles; the garden lawn studded; the tag from
  `World/NightLights`.
- [ ] `Agency`/`Market` kiosk builders only:
  - studded walls in Accent colours;
  - a dark roof instead of the striped candy awning;
  - floating "🏢 AGENCY" / "🏷️ MARKET" text, ≤ 25 parts;
  - the `Prompt` and its attributes unchanged.
- [ ] ✚ `TownWorld.spec` (the real `PlotBuilder.buildTown` under `worldmock`):
  - nothing solid in the belt lane;
  - the spawn at `SpawnOffset` and clear;
  - `Lawn`/`LawnTile` studded, `Street` smooth and V ≤ 0.35;
  - 0 Texture/Decal (when `CheckerTexture == ""`);
  - no part colour with a channel ≥ 245 except Neon lamps;
  - `ClinicTown` ≤ `Config.Look.TownParts`;
  - blossom trees ≤ 1 in 6;
  - the arches' text has no board.

  Also `uirules.check` on `BeltView`.
- **Acceptance:**
  - [ ] All gates pass. `AgencyServer` and `MarketServer` still pass.
  - [ ] The kiosk prompts and the belt's API are unchanged.
  - [ ] The odds are readable on the sign and one tap from the hire card.

### T3: Hospital building (required task 3). Load `roblox-studio-workflow`, `roblox-physics`, `game-feel`.
- [ ] `HospitalBuilder.build` (§B6): the podium at Lv 1; G + F1 at Lv 2; the tower at Lv 3–5; F1's two ward rooms;
  the functional and dressing beds and sleepers; Hydro; Pharmacy; the roof.
  - The lift at the street-facing −x corner (door on +z), landings at (−9, top, 4), stairs in the atrium's two lanes
    (one collidable wedge per flight).
  - The A&E door and red canopy; the bay (v2 names); the Counter canopy.
  - The paw-heart: the Lv 3 roof-edge sign and the Lv 5 Neon. The desk front's mark is T4's, because T4 builds the
    Counter.
  - The ambulance: warm white, a red stripe, the paw-heart, no cross.
- [ ] **The look** (hospital doc §4):
  - walls in the full-strength Accent, studded;
  - trim warm white; roofs dark;
  - plank floors; the slab edge as the wood beam;
  - dark ribbon windows; one front glass band per storey;
  - the glass lift shaft, with a car in the plot colour and a studded top;
  - department dado bands and curtains inside;
  - floating labels (the name on the fascia, "A&E", a floor icon on each glass band, "Pharmacy");
  - the lift directory on a navy plate.
- [ ] **Themes:** Trim and the roof band only, plus the prop (§B6).
- [ ] **Night:** tag windows "Window" and the logo and beacon "Lamp".
- [ ] **The `Storey` and `Outer` attributes;** solid upper outer walls; slabs ≤ 0.6.
- [ ] **✚ `Feel/Cutaway`** (§B6): its PURE block, and it sleeps off-building.
- [ ] **`Hospital.spec`** (rewrite v2's layout tests for the new layout; keep the contract-name tests):
  - every level × theme: building ≤ 160, SurfaceGuis ≤ 12, glass ≤ 6, 0 Texture/Decal, nothing named `*Cross*`;
  - every §B4 v2 name, `Floors`/`Theme`/`Since`;
  - landings on slabs and slab undersides ≥ 10.4;
  - each functional bed's foot reachable straight from its floor's landing (and each TubSpot's approach);
  - **F1 shows `WardFloorBeds` (7) beds at Lv 2–5, and Lv 1 shows 2;**
  - no dressing bed or sleeper has a `Bed_*` or `BedSpot_*` name;
  - `BedSpot_1..3` keep their spot across Lv 2 → 5 and across themes;
  - every part has a `Storey` (its own or its piece's);
  - `Outer` walls are studded, `Accent`-coloured and CanCollide above the ground;
  - roofs are `World.Roof`;
  - a theme changes Trim and the roof band only;
  - the cutaway's `floorOf`/`hide` tables;
  - the `Lift`, `LiftPanel` and `Stations` PURE tests still pass.
- **Acceptance:**
  - [ ] All gates pass. `Lift`, `Patients`, `Levels`, `Stations`, `HospitalFX` and `LiftPanel` are untouched and
    still work by name.
  - [ ] Report the measured building count per level for the perf note.

### T4: Plot and rooms (required task 3, the lean scenery). Load `roblox-studio-workflow`.
- [ ] **The Stand room:** no shell; stations, `Bed_1` and the decor slots at the `Logic/Building` spots (Remedy and
  Plaster moved, decor slot 2 on the porch); `MascotSpot` at (−7, −14.8).
- [ ] **Annexes** for the Bath Room, Cozy Ward and Winter Wing; the Garden as hedges and an arbor (§B6).
- [ ] **The plot:**
  - the studded dark `Pad` and Slate `Edge`s;
  - the plank path and 2 stones;
  - the fence through `Props.fence`; trees through `Props.tree`, with the (16.5, −9) tree moved; one-cube bushes;
  - the mailbox;
  - the queue lane at 6 tiles, in the §B3 mid-tones, with `queueSpot` unchanged;
  - no stepping stones under the building.
- [ ] **The sign:** floating text, with `SignGui`'s four children kept and `RankBadge`/`BranchBadge` still shown.
- [ ] **The Counter (the reception desk):** a SmoothPlastic body in the plot `Accent` with the existing CounterTop
  studded, and `Parts.pawHeart` on its street face. It's one SurfaceGui, counted in T4's plot share.
- [ ] **`DecorBuilder`:** studded tops on existing top parts and the palette. No new parts.
- [ ] ✚ `PlotWorld.spec` (under `worldmock`):
  - rooms ≤ 90 and plot ≤ 115 at Lv 5 with every room;
  - the `Pad` dark and studded, `Edge` Slate;
  - nothing on the Counter, the lane, the gate, the walkways (x ±12.5) or the building's footprint;
  - the Stand spots equal `Logic/Building`;
  - the sign's names present and no board behind them;
  - 0 Texture/Decal;
  - no part with a face over 16 studs² at V ≥ 0.95.
- **Acceptance:**
  - [ ] All gates pass. `queueSpot`, `placeRoom`, `setPreview`, `clearPlot` and the kit overrides work as before.
  - [ ] Report the measured counts.

### T5: HUD (required task 4). Load `roblox-ui`, `game-ui-ux`.
- [ ] **The zones** (§B7), from `HudZones.layout` on every resize:
  - System (TopbarSafeInsets);
  - the wallet without pills;
  - the Now slot with `setNow`/`nowBottom`, plus Hud's own warning and tracked-goal cards;
  - Status with words, one free-event chip (`NextEvent`), the visitor with a label, and boosts;
  - both rails with fixed slots;
  - ⚙️ More on phones;
  - the hands at the bottom centre;
  - the bottom bar removed.
- [ ] **⚙️:** the Skip and Replay rows → bus `SkipTutorial` / `ReplayTutorial`.
- [ ] **The hide rules** by `HudMode`; the first-session reveal in fixed slots; the staggered reveal at DONE.
- [ ] **`Toasts`:** one stack under `nowBottom()`; white plates with ink text; banners as plates with an icon tile;
  no `BELOW_WALLET_Y` juggling.
- [ ] **Keep every helper's signature** (`fly`, `target`, `shopNews`, `portrait`, `ask`, …) and every `Hud.target`
  name, now pointing at rail buttons.
- [ ] ✚ `HudScreen.spec`: Hud's PURE blocks (the Now priority, the chip text, the event candidates: Golden Hour only,
  never paid) and `uirules.check` on Hud and Toasts.
- **Acceptance:**
  - [ ] All gates pass.
  - [ ] At most 3 saturated fills and one perpetual effect.
  - [ ] Nothing in the bottom corners.
  - [ ] 3 a side on phones.
  - [ ] The tutorial pointer's targets resolve.

### T6: Chrome and core panels (required task 5, part 1). Load `roblox-ui`, `game-ui-ux`, `game-feel`.
- [ ] **`Modal`:** the template (§B8), restyled (Navy header, meta chip, ✖, flat paper, one shadow); `tabs`,
  `confirm` and `oddsPopup` finished; `HudMode`.
- [ ] **`Kit`:**
  - the roles (§B8);
  - `tab`, `textLimit`, `iconButton` as the white Icon plate;
  - `setDot` pops once with no hop loop (glyph stickers stay still);
  - `shine` and `breathing` only on Collect, with one perpetual effect at a time;
  - radii and strokes from tokens;
  - **`ring` and `holdButton` keep their signatures and juice.**
- [ ] **Panels:** `Shop`, `BookPanel`, `Boards`, `BadgeBook`, `Mailbox`, `PlayGifts`, `DayReportPanel`, `AdminPanel`
  move onto the template.
  - `Modal.tabs` (BadgeBook's row becomes the column); `Kit.textLimit`.
  - Neutral row tiles. Buy = Primary, Claim = Collect, "can't yet" = Disabled + a gate chip.
  - The header meta chip (🛒 💰 726, 📖 n%).
  - BadgeBook's cheer banner goes through the bus `Banner`. DayReport's count at `Hero`.
  - The admin kinds → Secondary/Destructive.
- [ ] **`MiniGames`:** onto `Modal.modal` (`HudMode "Game"`); `stage()`; the tutorial time-bar hide; pad glyphs;
  `MinTextSize` 18; every v2 feature kept.
- [ ] ✚ `Chrome.spec`: Kit.Juice and the role map; the `textLimit` floor; the `confirm` defaults (No focused, Hold);
  the odds rows; `uirules.check` on every T6 file. Update `Juice`/`MiniGamesPure` as needed.
- **Acceptance:**
  - [ ] All gates pass.
  - [ ] Every T6 panel has a Navy header, column tabs, and no text under 18.
  - [ ] The v2 behaviours in the mini-games and the Shop's 🏥/Branch card are unchanged.

### T7: Progression panels (required task 5, part 2). Load `roblox-ui`, `game-ui-ux`.
- [ ] **`NursePanel`:**
  - the on-duty strip → a "Team" row of cards;
  - the rarity tabs through `Modal.tabs` with a rarity stripe;
  - the "📔 n%" meta chip; 🎲 → `Hud.oddsPopup`;
  - radii → tokens; `MinTextSize` 18;
  - the job picker, XP, the ability ring, 🏷️, Sell/List buttons and NEW! all kept.
- [ ] **`AgencyPanel`:**
  - the tabs → the column; no `ACCENT`;
  - Buy/Sell confirms → `Hud.confirm`, with a 1 s hold for Epic+ (v2's rule);
  - odds → `Hud.oddsPopup`;
  - "🔄 New nurses every 5 min" with no clock.
- [ ] **`MarketPanel`:** no `ACCENT`; the buy and list confirms → `Hud.confirm`; `Kit.tab`; the band, the fee and
  the "Only this server · No swaps. No chat." badges kept.
- [ ] **`BranchPanel`:**
  - the reset confirm → `Hud.confirm`;
  - "🏢 Open branch!" stays a 1.5 s hold Primary; "Not now" stays the default focus;
  - the Themes cards show Roof and Trim swatches plus "🎨 Walls stay your colour".
- [ ] **`LiftPanel`:** a Popup of big Secondary floor buttons ("🛎️ G", "🛏️ 1", "🛁 2", "💊 3", "🚁 R"). The car
  slide is unchanged. **Its PURE block is unchanged.**
- [ ] Update `NurseUI`/`BranchUI`. ✚ `ProgressionPanels.spec`: `uirules.check` on every T7 file; the confirm specs
  each panel passes (titles ≤ 2 words, a hold for Epic+).
- **Acceptance:**
  - [ ] All gates pass.
  - [ ] Every v2 §D P3, P8, P9, P10, P12, P18 and P21 behaviour holds through the new chrome.

### T8: Tutorial (required task 6). Load `roblox-luau`, `roblox-ui`, `game-feel`.
- [ ] **`Server/Tutorial`:** the two remotes (§B1); the gift flag in `move()`; `setReopen`; the funnel and the skip
  event; a PURE block with the remote rules (`canSkip`, `canReplay` with cooldown, `giftDue`).
- [ ] **`UI/Tutorial`:**
  - the Now card (§B9), the 7 cards with words per device and live glyph switching;
  - Skip/Replay with the binding confirm texts;
  - the guide nurse;
  - the ✓ beats, the first-cure moment and the finale;
  - the UI pointer on the rails;
  - the idle nudge;
  - the welcome ack at the sweep's end.
- [ ] **`Wayfinder`** (§B9): the beam, chevrons, glow, pin and touch hand. **`Guide`** draws through it and keeps
  arrows until 3 cures (after Skip too), the v2 hold times and the reduced-motion re-sync.
- [ ] **`Celebrate`:**
  - Kind `"Tutorial"`, shown while the tutorial runs;
  - restyled on tokens (Large radius, Bold stroke, `Hero` text, one shine on its Collect "🎉 Yay!");
  - v2's Rebirth, Perk, NurseLevel and Unlock screens unchanged in content;
  - the Rebirth colours from the theme's Roof and Trim (walls stay the plot colour).
- [ ] **`Sounds`:** a `Chirp` cue (Blip notes).
- [ ] ✚ `TutorialFlow.spec`:
  - the server PURE rules: Skip only when active; Replay only when DONE with a plot, with the cooldown and no second
    gift;
  - `Wayfinder.Pure` (feetY for R6/R15, the end anchor on a footprint, bends round a box, chevron spacing and the
    max, the near-hide);
  - the card for every (step, treating);
  - the card words ≤ 6 except the Skip line;
  - `uirules.check` on every T8 UI file.
- **Acceptance:**
  - [ ] All gates pass.
  - [ ] One Highlight.
  - [ ] The beam aims only while it shows.
  - [ ] Nothing loops after the Guide finishes.

### T9: Blocky creatures (added 2026-11-17, `memory-20261117-004`). Load `roblox-luau`, `roblox-characters`.
Joshua chose blocky creatures after seeing the prototype: `logs/playtests/2026-11-17-look-spike/4-*.jpg`, `5-*.jpg`
and `6-*.jpg`.

**Build.** Rebuild `CreatureBuilder.build` and `buildLook` so every patient and nurse is made of blocks.
- **The body:**
  - a chunky body block and a head block, from each species' `Look` (colours, Scale, ears, hat, extra, Bits);
  - Plastic with `TopSurface` Studs on the big upward faces only, through `World/Studs`;
  - SmoothPlastic for small parts, so there are no cut-off studs on 1-stud blocks.
- **Colours:** mid-value. Use the art spec's no-lerp-to-white rule: Candy colours are brought down to world values.
- **The face:** flat blocks. Big dark eyes with two white glints, blush, a nose and a pixel mouth.
  - `setMood` swaps the mouth and brows and the eyelids ("Sick": a half-lid and a little o; "Happy"; "Sad"; "Sleep").
- **Ears:** each species keeps its own shape (rounded stacks, flops, tufts), because square ears read cat-like.
  - Each species keeps its own silhouette and Bits, so the cast stays original (red line 2).
- **Night glow and the Sparkly and Frosty variants** keep working.
- **Parts:** under 40 per creature, as now.

**The rig contract stays exactly the same.** `Root` as PrimaryPart and pivot (LookVector = face), `Core` on
`Root.PoseJoint`, the limb Motor6Ds, the sockets the acting props attach to, `IconAnchor`, `MOTION_TAG`, `badge`,
`setRing`, `setRecipe`, `setEffect`, `effectAt`, `hop`, `shake`, `tilt`, `scale`, `rigKit`, and the CollisionGroup
"Patients". Patients, Nurses, Feel/CreatureActing, CreatureMotion and CreatureProps must work unchanged.

**NurseBuilder:** the nurse cap, tray and rarity glow sit on the blocky head and body.

**Acceptance.**
- `BlockyCreatures.spec`:
  - every species in Data/Patients, Data/Regulars and Data/Nurses builds (pure layout, if there is a testable block)
    with fewer than 40 parts;
  - every socket and `IconAnchor` exists;
  - no Highlight anywhere, and no shadow-casting light.
- `NurseServer`, `HospitalPatients` and `Motion` stay green.
- Concerns list the species the lead should screenshot in Studio.

### Integration (lead)
- [ ] **I-1.** Apply the Requests, boot (`[Main] Clinic is open.`, no red errors), and run every gate.
- [ ] **I-2. Studio setup (required task 7's asset half).**
  1. Generate `CureStuds_color.png` / `_normal.png` (and the Grid variant) with art-direction Appendix B, in the
     scratchpad with Pillow, and the beam chevron strip (tutorial-ux §5.5).
  2. **Joshua uploads them.** Check the live Creator Hub first; any Robux cost needs both brothers' yes (red line 4).
  3. In MaterialService, create the `CureStuds` MaterialVariant (Plastic, `StudsPerTile 1`, `MaterialPattern`
     Regular, the colour and normal maps) and save the place.
  4. Set `Config.Tutorial.BeamTexture` and, optionally, `Config.Look.CheckerTexture`.
  5. Until then the game ships in Surface mode with a solid beam (§F).
- [ ] **I-3.** Run §E. Write `logs/playtests/2026-11-17-look-overhaul.md` with the screenshot stats table. Update
  the perf note's table, README and STATE, and OPEN-QUESTIONS (§F items that need the brothers). Add ✚
  `tests/UiRules.spec` (`uirules.check` over every `src/client` file). Commit.

### Review: two lenses (each reads the integrated diff and the code, not this plan's conclusions)
- **Lens A, "systems, safety and budgets."** Review focus 1, 2, 3 and 5:
  - v2 regressions by name and route;
  - the two remotes (junk, spam, mid-step, no plot, a friend on your plot);
  - straight-line reachability;
  - part, SurfaceGui, glass and Highlight budgets;
  - client loops;
  - no server per-frame writes;
  - no timers on paid things;
  - the gift never twice.

  It returns findings with file:line, severity (blocker / should / nit) and a repro.
- **Lens B, "look and UX against the specs."** Review focus 4 and 5, against art-direction §2–4, the hospital doc §3–4,
  ux audit §3 and tutorial-ux §3–5:
  - the palette and studs roles;
  - dark anchors, no pastels;
  - floating text and navy plates;
  - the HUD zones on every viewport;
  - the template, tabs and roles, text ≥ 18, the motion budget;
  - the tutorial flow per device, Skip/Replay texts and reduced motion;
  - originality (paw-heart, no cross, no borrowed asset).

  Same output format.

### Fixer
- [ ] Apply every blocker and should finding. File ownership is released for the fixer, but stay inside each
  finding's scope. Nits are listed in the log.
- [ ] Re-run every gate, re-check every §E item the fixes touched, and update the playtest log.
- [ ] Report: each finding → fixed / declined (why) / deferred (where it was filed). Then the lead merges.

---
## E. Studio playtest checklist (integrator; Studio MCP, Rojo connected, `FreshSave` where noted)
**The screenshot method (art-direction §4.3 acceptance):**
- Hide the HUD (`StarterGui:SetCore("TopbarEnabled", false)`, and disable the PlayerGui ScreenGuis for the shot).
- Take each shot from **the camera spot of the spike's `1-before.jpg`**: the TownSpawn area looking east down the
  street. Take one more from the plot view of `3-after-plot.jpg`. Use the same window size each time.
- Run art-direction Appendix A (`stats.py`, Pillow, in the scratchpad) on each, and log every number beside its
  target.
- Studio MCP captures don't draw AlwaysOnTop billboards (the pin, the hand, 💤): check those by eye.

| Measure | Day target | Night target | Before (art-direction §1.2, `12.png`) |
|---|---|---|---|
| Mean V | 0.75–0.88 | 0.35–0.50 | 0.95 |
| Luma P10 | ≤ 90 | — | 140 |
| Pale share | ≤ 15% | — | 35% |
| Grass, rendered (sample the lawn) | V 0.72–0.88, the two checker tones ΔV ≥ 0.05 | V 0.30–0.45, a violet cast | V 0.97–1.0 |
| Walls and floors | no big wall or floor at V ≥ 0.97 | — | — |
| Glow | — | lamps and Neon tips visibly bloom | — |

- [ ] **P0. Boot.**
  - `[Main] Clinic is open.`, no red errors. Then the spec count, gates and ownership: every file matches §A, with
    nothing outside it changed.
- [ ] **P1. Day light.**
  - The shots and stats above meet the day column. Shadows are visible under the trees and the building.
  - `Lighting.LightingStyle` is Soft and `PrioritizeLightingQuality` is true (read them back).
  - If a number misses, tune in the §C1 order. Log each tuning step and the value that passed. A change here is a
    Config/DayNight edit: the fixer or the lead makes it.
- [ ] **P2. Night** (`SkipPhase`). The night column holds. Windows glow warm, not Neon. The lamps, the paw-heart and
  the beacon bloom. In the morning every studded part is studded again (the DayMaterial restore).
- [ ] **P3. Studs.**
  - **Surface mode** (no variant): lawns, pads and prop tops are studded on top, and walls are smooth.
  - **Variant mode** (after I-2): walls, trees and pads are studded on every face, with no misaligned seam at any
    wall join, tile edge or plot edge.
  - Editor Quality Level 1, 4 and 10: no shimmer on far lawns. If there is, move far lawns to 8-stud cells.
  - `Studs.refresh` switches a running server when the variant is added.
- [ ] **P4. Town.**
  - The belt runs down the road's centre, x 120 → −120. Riders face the plaza.
  - TownSpawn is on the row-2 plaza and clear of the belt. The kiosks and the odds sign are clear and face the spawn.
  - The road is dark and smooth with no centre dashes. The lawns are a studded checker. The trees are voxel, with
    blossom ≤ 1 in 6.
  - The arches, kiosks and boards float their text. The boards and the odds sign sit on navy plates.
  - **No floating 🎲 ODDS chip anywhere.** "🎲 See odds" on the sign and the hire card's 🎲 open the same popup with
    every odd.
- [ ] **P5. Hospital, Lv 1 → 5** (`PreviewLevel` 1–5, then real level-ups):
  - Lv 1 is a real one-storey clinic: plot colour, a trim stripe, a dark roof, the canopy, the floating name, **2
    beds** (one with a sleeper). No tent.
  - Lv 2 is a two-storey block. Its F1 has **7 beds in two rows**, with 2 sleepers visible from the street through
    the glass band, curtains, and the glass partition.
  - Lv 3 adds the tower, the terrace and the roof-edge paw-heart. Lv 4 adds the Pharmacy and the 3rd functional bed.
    Lv 5 adds the walkable roof, the helipad, the Neon paw-heart and the beacon.
  - The queue lane, the sign, the gate, the Counter, the walkways and the room slots stay clear at every level.
  - **The cutaway:** ride to F1, F2, F3 and the roof. Everything above you hides and your floor's outer walls fade;
    on the ground nothing hides.
  - **Solid walls:** try to walk out of F3. You can't.
  - Themes (🛠️ Rebirth now, then pick themes): the trim and roof band recolour, and the walls stay the plot colour.
- [ ] **P6. Parts** (the perf note's command-bar count on Plot_1 with every room). Lv 5 in every theme ≤ 400, with
  the per-share numbers. Log them against §C3.
- [ ] **P7. v2 regression** (v2 §D P13–P17 again on the new building):
  - G ↔ 1/2/3/R lift rides with the ding and the car sliding; the escort "+20% 🛗"; a porter; a patient riding
    alone;
  - an ambulance (🛠️) flashing and sirening, its 🚑 patient going to the front;
  - Lv 3 triage right and wrong; the tub soak;
  - the Lv 4 Pharmacy craft;
  - the Lv 5 + R2 helicopter;
  - rebirth dropping the building to the Lv 1 podium.

  **No patient walks through a wall, a bed or the shaft. No dressing bed is ever used.**
- [ ] **P8. HUD, desktop** (1280 × 720):
  - the zones match ux audit §3.1: ⚙️ in the top bar; the 💰/⭐ wallet with no pills; the Now card; Status with
    words ("Night in m:ss", "🌟 Golden Hour in 12m", "Visitor ✅");
  - the left rail 🛒 👩‍⚕️ 📖 🏅 🏆 and the right rail 🎁 🎯 📬, all one fill;
  - the hands at the bottom centre; **nothing in the bottom corners**;
  - opening any panel hides the rails, Now and Status, and the wallet stays;
  - the 🛒 Branch dot and the flying 🌳 points still work (v2).
- [ ] **P9. HUD, phones** (Device emulator at 800 × 360, 667 × 375, 844 × 390 and 932 × 430, plus 1024 × 600):
  - 3 a side (4 left at 1024 × 600); 🏅 and 🏆 under ⚙️ More; the wallet in the top bar;
  - every button ≥ 56 px; nothing under the thumbstick or jump;
  - the Now card never covers the wallet.
- [ ] **P10. Panels.**
  - Open every panel: Shop, Book, Mail, Goals, Nurses, Badges, Top, Gifts, Day Report, Admin, Agency, Market,
    Branch, Lift, a mini-game. Each has a **Navy header**, column tabs and neutral rows.
  - A command-bar scan finds no `UITextSizeConstraint.MinTextSize < 18` and no `TextBounds` text under 18 in any
    PlayerGui.
  - Every confirm (Agency sell, with a hold for Epic+; Market buy and list; Branch reset; Skip; Replay) is the same
    popup with "Not now" focused.
  - The odds popups (belt, Agency, Journal) are identical.
  - At most one perpetual effect is on screen.
- [ ] **P11. Tutorial** (`FreshSave`, keyboard, then a pad in Xbox and PlayStation modes, then the touch emulator):
  - the sweep, then card 1 at once with the first patient hopping in;
  - cards 1–7 with the right words and live glyphs;
  - **the beam:**
    - it leaves your hips and lies flat;
    - it points and flows to the 🧪 table and bends round the Counter from the spawn spot;
    - it swings to the Counter after the make and hides within 6 studs;
    - turn on the spot and walk in circles: it never twists or stands on edge;
    - walk up the Stand step: it never dips into the floor;
  - **the glow:** one Highlight. The command-bar count prints 1. The floor chevrons show, and so does the touch hand.
  - the ✓ beats; CURED! 🎉 with coins flying;
  - the finale with **one "COMING UP" chip** (a free event, in minutes);
  - the HUD popping in one button at a time;
  - the first 💰 within about 35 s (a stopwatch; log it).
- [ ] **P12. Skip and Replay.**
  - Skip in steps 2, 4 and 7. The confirm says "You can replay it any time from ⚙️". You land at DONE with no gift
    and the full HUD, and the **arrows stay until 3 cures**.
  - ⚙️ → "🔁 Replay tutorial". The confirm appears; your line empties; the tutorial runs from card 1 with no sweep,
    the full HUD, **no second gift**, and can be skipped again.
  - Replay again within 30 s: "Try again soon".
  - From the command bar, each returns `false` and changes nothing:
    - `TutorialReplay` while active;
    - `TutorialReplay` with no clinic (a player in the street);
    - `TutorialSkip` while done;
    - junk args (ignored);
    - a spam loop (rate-limited).
  - A friend on your plot replaying their own tutorial never touches your line.
- [ ] **P13. Reduced motion.** Toggle it mid-step (the Roblox menu, then the in-game 💤). The beam's flow, the glow
  pulse, the pin's bob, the hand, the dot pops and the shines stop at once. The beam still follows you.
- [ ] **P14. Perf.**
  - 6 plots at Lv 5 at night with full rosters, at Quality 1, 4 and 10, on a mid phone if available: about 60 fps.
  - Log the MicroProfiler with the labels for Cutaway, Wayfinder and the rails.
  - Network receive stays low during rides.
  - Highlights ≤ 1. Texture count 0 (or one per lawn with `CheckerTexture`).
- [ ] **P15. Kids' rules.**
  - Countdowns appear only on free events. No timer on anything paid.
  - Odds are at every point of purchase.
  - The Primary buttons never shine. The Shop rail button matches its neighbours.
  - There's no red cross anywhere (search the place for "Cross"). The paw-heart is ours.
- [ ] **P16. Before publishing** (red lines 3 and 4):
  - re-read Roblox's live Terms of Use and Community Standards for any change since the last check;
  - confirm the uploads (studs maps, chevron) passed moderation;
  - **publishing needs both brothers' yes.**

---
## F. Open points (each ships with its default; Joshua or his brother can overrule)
1. **More usable beds?** The plan keeps `Levels.Beds` (1, 3, 3, 4, 4) and fills the wards with dressing beds and
   sleepers (§C4). Raising it is a one-line data change for the main ward (at most 3 there). Making the front ward's
   beds usable needs a Patients route change (a waypoint past the shaft). → OPEN, Joshua.
2. **Lv 2 becomes a two-storey block**, because the front ward sits over the podium. It's the only way to 6–8 beds a
   floor in a 23-wide plot (the tower alone fits 3). The default is yes.
3. **The town checker:** GrassB tiles as parts (≤ 600 town parts) until a checker image is uploaded, then one Texture
   per lawn (`Config.Look.CheckerTexture`).
4. **The spawn plaza:** on the street's row-2 half at (0, 11), with the kiosks and the odds sign beside it (§B5).
5. **Riders on a centre-line belt face the plaza** (+z).
6. **Themes no longer recolour walls** (the plot colour wins). `Themes.Wall` is only a UI swatch.
7. **The Now card's tracked goal** is the first unfinished daily goal. With two free events coming, the soonest
   shows. For now Golden Hour is the only Status event; admin events join when they exist (OPEN #9).
8. **The guide nurse:** a placeholder look in `Data/Guide`, with no name on screen. → OPEN #1 (both).
9. **The paw-heart** is a placeholder drawn in code. The brothers design the final mark. → OPEN, both.
10. **Uploads** (the `CureStuds` maps, the chevron strip, the optional checker): Joshua. Until then the game runs in
    Surface mode (top studs only) with a solid beam. Whether to publish before the variant exists is Joshua's call.
11. **The Skip line runs to 7 words** ("You can replay it any time from ⚙️"), past the ≤ 6 rule. It's binding text,
    so it stays.
12. **The onboarding funnel** is on: Roblox's own analytics, server-side, published games only, no personal data.
13. **Phones have no rail captions** (icons only). Desktop has captions at 72 px.
14. **Night windows go warm `#D8B470`, not Neon**, to keep the bloom on small parts only.
15. **Sleepers are original round heads in creature colours, with a 💤 bubble** and no faces. They never move.

---
## G. Where this meets Progression v2: how each conflict resolves
Joshua's rulings win. v2's systems keep working through the same names.

1. **The building layout.** v2 T6 built the lift in the back strip, 7-stud storeys, ramps, beds beside the lift and
   see-through upper storeys. **This replaces it** with the hospital doc's podium and tower, plus the front ward
   (§B6). The §B4 names, attributes and tags are kept.
   - `Lift`, `LiftPanel`, `Patients`, `Levels`, `Stations` and `HospitalFX` find everything by name. They stay
     untouched and must work unchanged (§E P7).
   - `PlotBuilder.Pure` re-exports `HospitalBuilder.Pure`. Its numbers change, so `Hospital.spec`'s layout tests are
     rewritten by T3.
2. **Upper walls become solid** (v2 §B4: "the walls above the ground storey stay soft"). The client cutaway makes the
   camera look in. Patients and porters move by hops and `PivotTo`, never by physics, so solid walls don't block
   them.
3. **The Lv 1 building is no longer empty.** The podium is built at every level, Lv 1 included. The Stand loses its
   shell.
   - Remedy and Plaster move +1.2 in x; decor slot 2 moves to the porch.
   - **`MascotSpot` moves to (−7, −14.8)** from (−8, −13), which now sits in the façade. Rebirth reads the marker,
     so it needs no change.
   - README and v2 §B4 said the Lv 1 Building is empty. Update the README.
4. **Themes.** v2 §B4 and P18 said "the building recolours". Now only the trim and roof band recolour, plus the prop;
   the walls stay the plot colour. BranchPanel's swatches (T7) and Celebrate's Rebirth colours (T8) follow that.
5. **Upstairs routes.** Patients walks upstairs in a straight line (`{ target }`) and finds beds by `^Bed_%d+$`. So:
   - functional bed feet must be straight-line reachable from the landing;
   - dressing beds must never carry those names;
   - `Building.spec` and `Hospital.spec` check both.
6. **Slab undersides ≥ 10.4.** F1 now spans the reception, and Patients' ground raycasts start at +10.
7. **The belt moves to z 0 and the spawn moves.** v2's kiosk clearance list (§B4 Town: benches at x ±15, the belt at
   z −11, the sign at (−14, −15.8)) is superseded by §B2/§B5 and `TownLayout.spec`. The kiosks still face TownSpawn
   by v2's own code. The Hall of Fame garden and the arches don't move.
8. **Countdowns.** v2's global "no countdown clocks" and P20 predate `-022`. Free events may now show minutes (the
   Status chip, the finale chip), and the day/night line keeps m:ss with words. The Agency, belt, abilities and
   triage stay clockless, as v2 built them. **The integrator updates v2's P20 wording in the README checklist.**
9. **The HUD.** v2 kept "the seven bottom tabs" (§B9, P21). They become the rails. Everything v2 hangs on them maps
   to the same `Hud.target` names: the 🛒 Branch dot and 🃏/🌳 sticker, the 🌳 points flying into 🛒, the sold-nurse
   coins flying into 💰, and the 👩‍⚕️ news dot.
10. **v2 panel chrome.** The headers' `ACCENT` colours go (Branch purple, Agency cyan, Market orange), and so do the
    three hand-built confirms and the Agency's own odds popup. `Kit.holdButton` (Open branch, 1.5 s; selling Epic+,
    1 s) and `Kit.ring` keep their signatures and behaviour.
11. **MiniGames.** v2 T8's auto ✨, Ease, Soak and Triage must survive the move onto `Modal` (T6; §E P7, P10).
12. **The Kit dot.** The dot's hop loop goes (pop once). v2's glyph stickers (🃏/🌳) stay as still stickers.
13. **Tokens.** v2's additions (`Theme.Juice.RingBeads`, `Kit.ring`, `Kit.holdButton`, `Kit.setDot(glyph)`) are
    kept.
14. **Colours.** `Palette.Outline` changes slightly. Old `Palette.World` keys become aliases. **Plot 5 turns from Lime
    to Yellow.**
15. **The split.** `PlotBuilder` is split and `Hud.modal` moves to `Modal` (re-exported). Any v2 spec that loads
    `src/server/PlotBuilder.luau`'s PURE block now loads `HospitalBuilder`'s. Task 0 fixes that path.
16. **The save.** `TutorialGift` is added without a version bump (v4 stays), and its value is derived when missing.
    The v4 migration specs must stay green.
17. **The first patient comes sooner.** `spawnPlan(WELCOME)` now sends the first patient during the sweep. Patients
    is untouched; check it in play (§E P11).
18. **The perf note's table** (v2's "372/378") is replaced by the new per-level counts (§C3, measured).
