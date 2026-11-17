# The Real Clinic (Update 2) Implementation Plan

> **For agentic workers:** this plan is executed by a multi-agent workflow. The Foundation (Task 0) runs first; Tasks
> 1-8 run in parallel, each owning only the files it lists; then an integrator, three review lenses and a fixer. Steps
> use checkbox (`- [ ]`) syntax. **Never use the Roblox Studio MCP tools**: Joshua's Studio is live, and Claude runs
> the Studio play-tests after the workflow.

**Goal:** Turn every visit into examine -> treat -> dispense with real, gentle cases, in a big realistic clinic that
stands complete from Lv 1, and say "treat" instead of "cure", without losing any player's save.

**Architecture:** Pure rules and data (cases, tools, items, the visit, mini-game engines, the building's numbers) live
in `src/shared` and are tested in Lune. The server owns the visit (`Patients`), the sessions (`Treatment`), the stations
and the dispensary (`Stations`) and the nurses. The client draws the exam, treatment and dispensing games by re-skinning
the four engines `MiniGames.luau` already has, plus one new Pick engine. The building is rebuilt by `HospitalBuilder`
to a contract in `Logic/Building`; markers by name are the only coupling between the world and the systems.

**Tech Stack:** Roblox Luau (strict), Rojo 7.7.1, Lune 0.11.1 specs (`tests/*.spec.luau`, `tests/expect.luau`,
`tests/worldmock.luau`), StyLua 2.6.0, selene 0.32.0.

**Spec:** `docs/plan/2026-11-17-real-clinic-design.md` (sections §1-§16; §15 overrides earlier sections where they
differ). Ruling: `memory/records/memory-20261117-005.md`.

## Global Constraints
- Work only in the worktree `c:\dev\games-agents\.worktrees\clinic2` (branch `claude/real-clinic`). Never edit
  `c:\dev\games-agents` itself: Rojo syncs it into Joshua's Studio.
- From `game/`: `lune run tests/run`, `stylua --check src tests`, `selene src`, `rojo build default.project.json -o
  <temp>`. All four green before the integrator commits. Tools: `$USERPROFILE/.rokit/bin/`.
- No needles, blood, surgery or scary pain anywhere (§2). No fail state: a wrong tool or bottle is a head-shake and a
  retry; an OK rating still treats.
- No player-visible "cure", "cured" or "cures" (§12). Internal names stay (`Cure.resolve`, the `Cured` remote, the
  `Cured` save field, leaderboard ids `Cured` and `Week`, badge ids, Stats keys, Patient ids, Room ids).
- Saves: `Schema.VERSION` stays 4. A live v3 save and a v4 save both load with every count, room, Book page, badge
  tier, nurse and rebirth kept (§11, §15 #4).
- Station ids kept: `Plaster`, `Bath`, `Cocoa`, `Remedy` (= the dispensary). New: `Ice`, `Bandage`, `Cast`. Gone:
  `Pharmacy`. Station ids are alphanumeric (parts are named `Station_<id>`).
- Medicines are made only by the player at the dispensary. Maker nurses never dispense. Healers and Medics may
  examine and hand over tray items. Abilities may finish whole visits (§15 #1).
- Budgets (`Config.Look`): Building ≤ 420 parts, ≤ 24 SurfaceGuis (each with a MaxDistance), ≤ 10 see-through parts;
  plot's own share ≤ 130; rooms ≤ 90; a Lv 5 plot with every room ≤ 640. No Texture, no Decal, no shadow-casting
  light, nothing named or shaped like a cross; never the word "LEGO".
- `Config.Town.PlotSize = 110`. Storeys 12 / 11 (slab tops 12, 23, 34, 45). Floors are `FloorTile` / CeramicTiles,
  never wood.
- Server-authoritative: the server picks the case, the tool answer, the medicine options and every payout; client
  ratings only move the capped tip (today's rules in `Logic/MiniGame`).
- Keep each edited file's header comment true. Copy, icons and names come from the design's tables.

## Review Focus
1. **A case needing an item no open station makes** (a Lv 1 clinic rolling Sprain, an ambulance pad, a regular, a
   night patient): it must never be picked. Test in Task 4 (`Visit.rollCase` + spawn eligibility).
2. **The Building is rebuilt mid-visit** (a level-up or a rebirth while patients sit in seats and bays): no patient
   is left floating or stuck. Each re-seats in its new seat or bay, or walks home without a sad penalty. Test in Task 4.
3. **Two players work one patient** (the owner and a helper both tap Examine; both dispense the last needed medicine):
   one session per patient. A spare medicine is just a held item the player can discard. Test in Task 5.
4. **A player leaves mid-session or mid-visit**: their sessions close, the bay patient stays for the next doctor,
   and the plot owner leaving sends everyone home. Test in Tasks 4 and 5.
5. **Phone screens**: the exam card's 3 tools and the dispensing card's 4 bottles fit 568×320 with tap targets
   ≥ 44 px. Test in Task 7.

---

## Contracts (Task 0 writes these into code; every other task builds to them)

**C1. `src/shared/Logic/Building.luau`** (pure). Plot-local studs, origin = the plot's ground-top centre, -z the
street. Numbers are the Foundation's to pick from this sketch; everyone else reads them from the module and never
hardcodes them.
```
z -24 (street) ┌──────────── front doors (DOORS.Front, centre) ───────────┐
               │ WAITING (6 seats)   │  LOBBY + reception desk │ DISPENSARY │
               │─────────────────────┴──── corridor ───────────┴─(hatch)───│
               │ EXAM BAYS 1-6 (curtained, in a row) │ SUPPLY shelf │ X-RAY │
               │ BATH ROOM │ WINTER WING │ COZY WARD (2 bays) │ LIFT+STAIRS │
z 20           └───────────────────────────────────────── A&E door on -x ──┘
```
- Fields: `HALF_X = 32`, `FRONT = -24`, `BACK = 20`, `GROUND = 12`, `STOREY = 11`, `SLAB_TOPS = {12, 23, 34, 45}`,
  `WALL`, `SLAB_MAX`, `MIN_LEVEL = 1`, `MAX_LEVEL = 5`.
- `ROOMS: { [RoomName]: Rect }` for `Lobby, Waiting, Dispensary, Bays, Supply, XRay, BathRoom, WinterWing, CozyWard,
  LiftCore` (ground floor).
- `DOORS: { Front, AE, Garden, LiftLobby, … }`, each a span plus `Height`.
- `RECEPTION = { Desk: Rect, Stop: Point }`.
- `SEATS: { Point & { Face: number } }` (6).
- `BAYS: { { Id: string, X: number, Z: number, Face: number, Opens: number, Kind: "Exam" | "XRay", Room: string? } }`:
  ids `"1".."6"`, `"X"` (Opens 3), and `"W1"`, `"W2"` (Room = "Ward", the Cozy Ward).
- `STATIONS: { [StationId]: { X, Z, Face, Opens: number } }` for `Plaster`, `Ice`, `Bandage` (Opens 2), `Cast`
  (Opens 3) and `Remedy` (the dispensary counter).
- `SHAFT`, `LANDING`, `ATRIUM`/`LANE_A`, `WARD_BEDS: { [floor]: { { X, Z, Ward: "Wards" | "Rest" } } }`
  (F1 Injury = "Wards", F2/F3 = "Rest").
- `BAY_AMBULANCE`, `HELI`.
- `footprint(level, floor?)`, `slabTop(floor)`, `floors(level)`, `obstacles(level, floor?)`, `clear(rect, level)`,
  `reach(from, to, level, floor?)`: the same meanings as today.

**C2. Markers the Building carries** (built by Task 1 unless marked). Systems find them by name under `Plot.Building`
and `Plot.Rooms`:
- `FrontDoor` Model (`DoorL`, `DoorR`, `Sensor`); `ReceptionStop` marker.
- `WaitSeat_<n>` markers (n = 1..6, on the seat top, facing out).
- `ExamBay_<id>` Models. Children: `Bed` (BasePart; the patient sits on its top), `DoctorSpot` marker (Task 4 puts
  `BayPrompt` here), `Curtain`, `Tray`, `Sign`. Attributes: `Bay` (id), `Kind`, `Opens`, **`Open`** (boolean, set at
  build time from the level, or room owned). `ExamBay_W1/W2` are built by **Task 2** inside the Cozy Ward fit-out.
- `Station_<id>` BaseParts (attribute `Open`), for `Plaster`, `Ice`, `Bandage`, `Cast`, `Remedy`. `Station_Bath` and
  `Station_Cocoa` stay in the Bath Room and Winter Wing fit-outs (**Task 2**).
- `Floor_<n>.BedSpot_<k>.Bed_<k>`: attributes `Floor` and `Ward` ("Wards" | "Rest"). Plus the lift (`Lift`,
  `Landing_0`, `Floor_<n>.Landing`), `Stairs`, `AmbulanceBay` (`Ambulance`, `StretcherSpot`) and `Roof.HeliSpot`, as
  today.
- **Plot-level, built by Task 2:**
  - the `Counter` part at `RECEPTION.Desk`, kept by that name because `Plots` and `Patients` find it;
  - the `Spawn` and `Exit` markers at the gate;
  - no `QueueStart`, no `QueueLane`.

**C3. Data (Task 0), all Lune-loadable except `Data/Stations`.**
- `Data/Cases.luau`: `Case = { Name, Icon, Bubble, Tool: ToolId, Plan: { ItemId }, Stay: ("Wards" | "Rest")?, Level:
  number, Room: string? }`, with ids `Cough, Fever, CutKnee, BumpedHead, Earache, Sprain, SoreThroat, Rash, BrokenArm,
  SoreMuscles, Chills, BrokenLeg` and the values from design §6.
  - `Stay`: Fever and Chills `"Rest"`; BrokenArm and BrokenLeg `"Wards"`.
  - `Room`: SoreMuscles `"BathRoom"`, Chills `"WinterWing"`.
  - Also `Cases.ORDER` and `Cases.POOLS` (design §15 #2; keys = WingIds).
  - **`Data/Ailments.luau` is deleted.**
- `Data/Tools.luau`: `Stethoscope{Icon "🩺", Game "Listen"}`, `Thermometer{"🌡️", "Temp"}`, `Light{"🔦", "Light"}`,
  `Magnifier{"🔍", "Look"}`, `XRay{"🩻", "XRay", Machine = true, Level = 3}`; plus `Tools.ORDER`.
- `Data/Items.luau`: `Item = { Name, Icon, Station, Kind: "Supply" | "Medicine", Game: GameId?, Bottle: string? }`
  (`Bottle` is a hex colour for medicines).
  - Supplies: `Plaster` (Game "Plaster"), `Ice` ("Ice"), `Bandage` ("Bandage"), `Cast` ("Cast"), `Bubbles` (station
    Bath, shown "Bath foam", Game "Bath"), `Cocoa` (shown "Hot chocolate", Game "Cocoa").
  - Medicines (station `Remedy`, no Game): `CoughSyrup`, `FeverMeds`, `EarDrops`, `Lozenges`, `Cream`, `PainRelief`.
  - `Potion` and every crafted medicine are gone.
- `Data/Stations.luau`: each station is `{ Name, Icon, Item, Color, Dispense? }`.
  - Remedy = "Dispensary", `Dispense = true`, `Item = ""`.
  - Plus Plaster, Ice, Bandage, Cast, Bath, Cocoa. Pharmacy is gone.
- `Data/Levels.luau`: the names from design §10 and a new `Bays` field (2, 3, 4, 5, 6). `Beds` now counts ward beds.
  `Departments` per §15 #3; the new department id is `Rest`. Every other field is unchanged.
- `Data/Departments.luau`:
  - `Hydro` covers the Bath Room;
  - `Pharmacy` covers the supply shelf and the dispensary;
  - `Wards` is the Injury Ward (F1);
  - new `Rest` (F2/F3, Opens 3);
  - new `Imaging` (the X-ray room, Opens 3).

**C4. `src/shared/Logic/Visit.luau`** (Task 0, pure):
- `Visit.rollCase(pool: { CaseId }, can: (CaseId) -> boolean, roll: number): CaseId?`: the cases `can` allows, picked
  evenly by `roll` in [0, 1); nil if none.
- `Visit.canTreat(case: Case, level: number, rooms: { [string]: boolean }, stationOpen: (StationId) -> boolean,
  items): boolean`: the level, the room, and every plan item's station open.
- `Visit.examTools(answer: ToolId, unlocked: { ToolId }, roll: number): { ToolId }`: 3 distinct tools (fewer if fewer
  are unlocked), answer included, order from `roll`.
- `Visit.glow(examsDone: number, simple: boolean): boolean`: true while `examsDone < 3` or `simple`.
- `Visit.plan(case: Case, cap: number): { ItemId }`: `Recipe.effective(case.Plan, cap)`.
- `Visit.stayWard(case: Case, level: number): ("Wards" | "Rest")?`: `"Wards"` from Lv 2, `"Rest"` from Lv 3, else nil.
- `Visit.nextForBay(waiting: { { Id: number, Since: number, Tool: ToolId } }, kind: "Exam" | "XRay"): number?`: the
  longest-waiting patient whose tool fits (XRay cases only to XRay bays, all others only to Exam bays).
- `Visit.front(inBays: { { Id: number, Since: number, NeedsDoctor: boolean } }): number?`
- `Visit.PATIENCE = { Waiting = 0.5, Bay = 1 }`.

**C5. Mini-games (Task 0 in `Logic/MiniGame.luau` and `Types.luau`):**
- `GameId = "Listen" | "Temp" | "Light" | "Look" | "XRay" | "Plaster" | "Ice" | "Bandage" | "Cast" | "Bath" |
  "Cocoa" | "Dose" | "Pick"`.
- `MiniGame.ENGINE: { [GameId]: "Pour" | "Patch" | "Scrub" | "Cool" | "Pick" }`: Listen Patch, Temp Pour, Light Cool,
  Look Patch, XRay Cool, Plaster Patch, Ice Pour, Bandage Cool, Cast Cool, Bath Scrub, Cocoa Cool, Dose Pour, Pick Pick.
- `rate(game, score, cfg)` uses the engine's rule with `cfg.MiniGame.Games[game]` tuning. Pick: score = wrong taps;
  0 Perfect, 1 Good, else OK; min 0.6 s.
- `GAMES` (item -> game) is replaced by `Items[id].Game`.
- `minSeconds`, `timeout`, `accept` and `settle` keep their behaviour.
- `TreatSession` gains `Kind: "Exam" | "Treat" | "Dispense"`, plus `Tools: { ToolId }?`, `Answer: ToolId?`,
  `Glow: boolean?`, `Options: { ItemId }?` and `Case: CaseId?`.
- The `TreatResult` request gains `Choice: ItemId?`; `TreatOutcome` gains `Case: CaseId?` and `Item: ItemId?`.
- No new remotes.

**C6. Server visit API (Task 4 provides; Tasks 5 and 6 call).** In `src/server/Patients.luau`:
- `Patients.bayView(plotModel): { { Bay: string, PatientId: number, Stage: "Exam" | "Treat", Needs: { ItemId },
  Since: number } }`
- `Patients.neededMedicines(plotModel): { ItemId }`: still-missing medicine steps over bay patients, oldest first,
  at most 3 distinct.
- `Patients.examine(plotModel, patientId: number, helper: Player?): CaseId?`: reveals the case. Idempotent.
- `Patients.give(plotModel, patientId: number, items: { ItemId }, helper: Player?): { number }`: the plan slots filled.
- `Patients.finishVisit(plotModel, patientId: number, helper: Player?)`: for abilities.
- Nurses keep going through `Treatment.onHeal` (today's pattern). Task 4's heal handler does: exam first if the patient
  needs one, else hand over the first tray item the patient needs.

---

### Task 0: Foundation (Fable)

**Files:**
- Modify: `src/shared/Logic/Building.luau`, `src/shared/Logic/MiniGame.luau`, `src/shared/Types.luau`,
  `src/shared/Config.luau`, `src/shared/Data/{Items,Stations,Levels,Departments}.luau`
- Create: `src/shared/Data/Cases.luau`, `src/shared/Data/Tools.luau`, `src/shared/Logic/Visit.luau`,
  `tests/Visit.spec.luau`
- Delete: `src/shared/Data/Ailments.luau`
- Test: `tests/{Building,Data,MiniGame,Visit,Levels}.spec.luau`

**Interfaces:** Produces C1, C3, C4 and C5 exactly as written above.

- [ ] **Step 1: Write the failing specs.**
  - `Visit.spec`:
    - `rollCase` never returns a case `can` refuses. An empty pool gives nil.
    - `examTools("XRay", {"Stethoscope","Magnifier"}, 0.5)` includes "XRay" and has 3 distinct ids.
    - `glow(2,false) == true`, `glow(3,false) == false`, `glow(9,true) == true`.
    - `stayWard(BrokenArm, 1) == nil`, `stayWard(BrokenArm, 2) == "Wards"`, `stayWard(Fever, 2) == nil`,
      `stayWard(Fever, 3) == "Rest"`.
    - `nextForBay` sends a BrokenArm patient only to an "XRay" bay and picks the oldest.
  - `Data.spec`:
    - every case's tool exists, and every plan item exists with a station;
    - plan length is 1..3;
    - every pool id is a case;
    - the Night pool uses only Level-1 cases;
    - no item, case or tool name contains "cure" or "needle".
  - `MiniGame.spec`:
    - every GameId has an ENGINE;
    - every supply's `Game` is a GameId;
    - Pick: 0 wrong taps Perfect, 1 Good, 2 OK.
  - `Building.spec`:
    - all 6 seats, the 9 bays and the 5 stations are inside the footprint and on an open floor cell;
    - `reach(ReceptionStop, each seat)` and `reach(each seat, each bay DoctorSpot)` at Lv 1;
    - the footprint is 64 x 44;
    - the slab tops are {12, 23, 34, 45};
    - the ward beds carry "Wards" on F1 and "Rest" on F2/F3.
- [ ] **Step 2: Run them** (`lune run tests/run`). Expect failures for the missing modules.
- [ ] **Step 3: Implement C1, C3, C4 and C5.** Also set `Config.Town.PlotSize = 110`, the `Config.Look` budgets,
  `Config.MiniGame.Games` (one tuning row per GameId, within today's MinSeconds rules) and
  `Config.Visit = { ExamsGlow = 3 }`.
- [ ] **Step 4: Run.** The Foundation's specs pass. Other files' failures are expected and listed in your report.
- [ ] **Step 5: Commit.** "Real Clinic foundation: cases, tools, items, the visit, engines, the building contract".
  Return the contract numbers and, for each task, the facts it needs (which old specs now fail and why).

### Task 1: The building (HospitalBuilder)
**Files:**
- Modify: `src/server/HospitalBuilder.luau` (rewrite the layout; keep `build`, the tags and the Pure pattern),
  `src/server/Main.server.luau` (start `Doors` only)
- Create: `src/server/World/Doors.luau`
- Test: `tests/Hospital.spec.luau`, `tests/PartBudget.spec.luau` (the Building share)

**Interfaces:**
- Consumes: C1.
- Produces: C2 (everything not marked Task 2), and `Doors.start()`. Doors are server-tweened panels that slide open
  while a character or creature is within 8 studs of `Sensor` (one tween per change, never per frame).

- [ ] **Step 1: Failing specs in `Hospital.spec`.**
  - At every level 1-5 and every theme, the building has `FrontDoor`, 6 `WaitSeat_`, 7 `ExamBay_` (1-6, X) and the 5
    stations.
  - Each bay's `Open` equals `level >= Opens`.
  - `Station_Bandage.Open` is false at Lv 1 and true at Lv 2.
  - The footprint equals C1's at Lv 1 (big from Lv 1).
  - Budgets per Global Constraints.
  - Floors: every floor and slab is `CeramicTiles`.
  - Everything solid lies inside `Building.obstacles`.
  - A closed room's door is solid and carries a sign SurfaceGui.
- [ ] **Step 2: Run them.** They fail.
- [ ] **Step 3: Build to C1 and C2.**
  - The front doors replace the display window.
  - The reception desk is the plot's `Counter`, built by Task 2: leave its rect clear.
  - Closed floors and rooms are visible, with shut doors and a navy "🔒 Opens at Lv N" plate.
  - Rooms are realistic: rows of seats, curtained bays with a tray, bottle shelves in the dispensary, the X-ray arm
    over bay X.
  - Use the existing Parts and Studs helpers; walls are studded, floors tiled.
- [ ] **Step 4: Run.** `Hospital.spec` and the Building share of `PartBudget.spec` pass.
- [ ] **Step 5: Report.** Do not commit; the integrator commits.

### Task 2: Plot, rooms and town
**Files:**
- Modify: `src/server/PlotBuilder.luau`, `src/server/TownBuilder.luau`, `src/server/World/Props.luau`,
  `src/shared/Data/Rooms.luau` (texts: Cozy Ward "+2 exam bays")
- Test: `tests/{PlotWorld,TownLayout,TownWorld,Belt,PartBudget}.spec.luau` (the plot and rooms shares)

**Interfaces:**
- Consumes: C1 (`ROOMS.BathRoom/WinterWing/CozyWard`, `RECEPTION`, `BAYS` with `Room`).
- Produces:
  - the `Counter`, `Spawn` and `Exit` markers;
  - `PlotBuilder.SLOTS`, where `BathRoom`, `WinterWing` and `Ward` slots are inside the building's ground floor and
    `Garden` is behind it;
  - interior room fit-outs with no walls or roof: Bath Room (`Station_Bath`), Winter Wing (`Station_Cocoa`), Cozy
    Ward (`ExamBay_W1`, `ExamBay_W2` to C2, with `Open = true`);
  - no queue lane.
  - `PlotBuilder.queueSpot` is removed (Task 4 stops calling it).

- [ ] **Step 1: Failing specs.**
  - The plot is 110 x 110 (pad 107).
  - `Counter` sits inside `RECEPTION.Desk`.
  - `Spawn` and `Exit` are at the gate.
  - Each interior fit-out lies inside its `ROOMS` rect.
  - The Cozy Ward model has 2 `ExamBay_W*` with `Bed` and `DoctorSpot`.
  - Room floors are CeramicTiles.
  - No room model has a roof or outer walls.
  - The town's plots don't overlap; the belt, kiosks and Hall of Fame clear every plot.
  - The budgets hold.
- [ ] **Step 2: Run.** They fail.
- [ ] **Step 3: Implement.**
  - The plank path leads from the gate to `DOORS.Front`.
  - Keep the sign, mailbox, fence and trees clear of the building and the path.
- [ ] **Step 4: Run.** Your specs pass.
- [ ] **Step 5: Report.** No commit.

### Task 3: Progression, data dependents and words
**Files:**
- Modify (data):
  - `src/shared/Data/{Patients,Regulars,Badges,DailyGoals,Upgrades,Abilities,Wings,Jobs}.luau`
  - `src/shared/Data/AilmentActing.luau`, renamed to `Data/CaseActing.luau`, keyed by CaseId
- Modify (logic): `src/shared/Logic/{Badges,Book,Daily,Story,Jobs,Leaderboard,Rebirth}.luau`
- Modify (server): `src/server/{Badges,Daily,Story,Book,DayReport,Admin,Leaderboards,Boosts}.luau`
- Modify (docs): `docs/launch/page.md` (a DRAFT line only), `game/README.md`
- Test: `tests/{Data,Badges,Book,Daily,Story,Jobs,Leaderboard,Rebirth,Schema,Boosts}.spec.luau`

**Interfaces:**
- Consumes: C3.
- Produces:
  - `Data/Patients` entries without `Ailment` (they keep `Wing`, `Night` and `Look`).
  - Regulars get `Case: CaseId` (the old `Recipe` goes).
  - `Data/CaseActing[CaseId]`.
  - Badges:
    - new station badges `Ice`, `Bandage` and `Cast` (`Made:<id>`);
    - the `Potions` badge is shown as "Pharmacist" and counts `Made:Remedy`;
    - `Cures:<Wing>` stats are kept.
  - `Rebirth` unlock `Pharmacy2` is shown as "Expert Dispensing" (`Config.MiniGame.Games.Dose` band +50%).

- [ ] **Step 1: Failing specs.**
  - A v3 save fixture (from `Schema.spec`) with `Book.DumplingFrog`, `"Made:Remedy"`, `Badges.Potions`, `Daily`
    goals naming `Potion`, and the BathRoom room reconciles with every count kept and only the Potion goal pruned.
  - Every station in `Data/Stations` has a `Made:` badge.
  - The visitor pool comes from patient -> wing.
  - Leaderboard titles are "Most Patients Treated" and "Treated This Week", and the ids are unchanged.
  - No visible string in `Data/*` or `Logic/*` matches `%f[%a][Cc]ure`.
- [ ] **Step 2: Run.** They fail.
- [ ] **Step 3: Implement.** Also rewrite every visible "cure" string listed in the design §12 (badge descriptions,
  Upgrades hints, Admin texts).
- [ ] **Step 4: Run.** Your specs pass.
- [ ] **Step 5: Report.** No commit.

### Task 4: The visit (Patients)
**Files:**
- Modify: `src/server/Patients.luau`, `src/shared/Logic/Hospital.luau` (triage options `{ "Wards", "Rest" }`,
  urgent pad `Ice`, route by `Case.Stay`)
- Test: `tests/{HospitalPatients,ServerPure,HospitalLogic}.spec.luau`

**Interfaces:**
- Consumes: C1, C2, C3, C4, and `Treatment.open` (Task 5, same signature as today, with `spec.Kind`).
- Produces: C6.
- Patient attributes:
  - `Case` (set only after the exam), `Symptom` (the bubble), `Tool`, `Plan` and `PlanDone` (they replace `Recipe`
    and `RecipeDone`), `Bay`;
  - `State` is one of Arriving / Waiting / ToBay / AtBay / Examining / Planned / Treating / Done / ToWard / Recovering
    / Leaving / Sad.
- `BayPrompt` (tag `TreatPrompt`): its ActionText is "Examine" before the exam and "Treat" after.

- [ ] **Step 1: Failing specs (`Patients.Pure`).**
  - `Pure.eligible(case, plotState)` is false for Sprain at Lv 1, BrokenArm without the X-ray, and SoreMuscles
    without the BathRoom.
  - A spawn at Lv 1 never picks a case outside Lv 1.
  - `Pure.reseat(oldSeat, newSeats)` maps every patient to a seat or bay, or marks them `Leaving` with no sad penalty
    (Review Focus 2).
  - The owner leaving marks every patient `Leaving` (Review Focus 4).
  - The front is the longest-waiting bay patient who needs the doctor.
  - A Stay case at Lv 1 goes home; at Lv 3 Fever goes to "Rest".
- [ ] **Step 2: Run.** They fail.
- [ ] **Step 3: Implement design §5.**
  1. Spawn at `Spawn`, walk in through `FrontDoor` to `ReceptionStop`, then sit at a free `WaitSeat_` with the
     symptom bubble on `p.Badge.Bubble`.
  2. `Visit.nextForBay` moves patients to open bays.
  3. `BayPrompt` opens an Exam session (`Tools = Visit.examTools`, `Answer`, `Glow = Visit.glow(<the player's
     saved `Cured` count>, Simple)`). Its settle calls `examine`, which shows the plan on the needs badge.
  4. `BayPrompt` "Treat" matches carried items (`Recipe.match`, as today). A supply opens a Treat session with that
     item's Game; a medicine is handed over with no game.
  5. When the plan is done: `Visit.stayWard` -> today's triage, escort, lift and recover code, or pay. Then walk out
     through `FrontDoor` to `Exit`.
  - Patience uses `Visit.PATIENCE`.
  - Night, ambulance, helicopter, regulars and the tutorial patient go through the same visit.
  - Delete the hot tub and Soak.
  - `stationsOnPlot` scans the Building and Rooms for `Station_<id>` with `Open ~= false`.
- [ ] **Step 4: Run.** Your specs pass.
- [ ] **Step 5: Report.** No commit.

### Task 5: Sessions, stations and the dispensary
**Files:**
- Modify: `src/server/{Treatment,Stations,Carry,Cure,Rebirth}.luau`
- Test: `tests/{TreatmentSessions,Recipe}.spec.luau`

**Interfaces:**
- Consumes: C3, C5, and C6 (`Patients.neededMedicines`).
- Produces:
  - `Treatment.open(p, spec)` with Kind Exam / Treat / Dispense. Exam settle returns `TreatOutcome.Case`;
    Dispense settle validates `Choice ∈ spec.Options`, pays the tip at once (`MiniGame.settle`), and returns
    `Item = Choice` after `Carry.add`.
  - The `Station_Remedy` "Dispense" hold prompt (tag `StationPrompt`). When nothing is needed it says "💊 No
    prescriptions yet".
  - Supply stations with `Open == false` have their prompt disabled.
  - No crafting; `Recipe.craft` is removed.
  - `Made:Remedy` counts each dispense.

- [ ] **Step 1: Failing specs.**
  - A second Exam open on a patient already in a session is refused (Review Focus 3).
  - A Dispense result whose Choice isn't in Options gives nothing and rates OK.
  - A Dispense session for a player who left is dropped and gives nothing (Review Focus 4).
  - Exam settle with any ratings reveals the case.
  - Expert Dispensing widens the Dose band by 50%.
- [ ] **Step 2: Run.** They fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Your specs pass.
- [ ] **Step 5: Report.** No commit.

### Task 6: Nurses and abilities
**Files:**
- Modify: `src/server/{Nurses,Abilities}.luau`, `src/shared/Logic/{Abilities,Nurse}.luau`
- Test: `tests/{NurseServer,NurseWork,Abilities}.spec.luau`

**Interfaces:**
- Consumes: C6 and `Treatment.onHeal`.
- Produces:
  - Makers stock supply items from open `Station_<id>` parts in the Building and Rooms (never `Remedy`).
  - Healers and Medics fire Heal on the front bay patient or the urgent patient when that patient needs an exam or a
    tray item.
  - RefillFront and CureLine target bay patients; CureLine calls `Patients.finishVisit`.
  - Porter escorts Stay patients.
  - Receptionist gives faster arrivals and an instant ward pick.

- [ ] **Step 1: Failing specs.**
  - `Pure.pickMake` never returns a medicine or "Remedy".
  - A Healer facing a patient whose only missing step is a medicine does nothing.
  - Hydro and Pharmacy specialists still get their bonus (in the Bath Room, and at the supply shelf).
- [ ] **Step 2: Run.** They fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Your specs pass.
- [ ] **Step 5: Report.** No commit.

### Task 7: Client mini-games
**Files:**
- Modify: `src/client/UI/MiniGames.luau`, `src/client/Feel/Sounds.luau`
- Test: `tests/MiniGamesPure.spec.luau`

**Interfaces:**
- Consumes: C5 and the `TreatSession` Kinds.
- Produces:
  - A `GAME_LOOK` per GameId.
  - `playPick(env, choices, answer, glow): number` (wrong taps).
  - **The Exam card:** Pick a tool, play the tool's game, then reveal the case for 1.2 s: "🩺 It's a cough!" with the
    plan icons.
  - **The Dispense card:** choose the medicine when there are several Options, play Pick to find the bottle (4
    bottles: the answer plus 3 others), then play Dose.
  - The report includes `Choice`.
  - `Pure.pickLayout(viewport: Vector2, n: number): { Vector2 }` gives tap targets ≥ 44 px.
- [ ] **Step 1: Failing specs.**
  - `pickLayout(Vector2.new(568,320), 3)` and `(…, 4)`: every target ≥ 44 px, and none overlap or leave the card
    (Review Focus 5).
  - Every GameId has a look.
  - The dispatch plays each engine for its ids.
- [ ] **Step 2: Run.** They fail.
- [ ] **Step 3: Implement** on the existing Env framework. Use 2D only, as today.
- [ ] **Step 4: Run.** Your specs pass.
- [ ] **Step 5: Report.** No commit.

### Task 8: Client UI, tutorial and wording
**Files:**
- Modify (client UI):
  - `src/client/UI/{Hud,Guide,Tutorial,Mailbox,AdminPanel,Boards,BookPanel,DayReportPanel,Celebrate,PromptFilter}.luau`
  - `src/client/Feel/{CureFX,CreatureActing}.luau`
- Modify (tutorial logic and server): `src/shared/Logic/Tutorial.luau`, `src/server/Tutorial.luau`
- Test: `tests/{Tutorial,TutorialFlow,HudScreen,UiRules}.spec.luau`

**Interfaces:**
- Consumes:
  - C4, C5;
  - patient attributes `Symptom`, `Case`, `Plan`, `PlanDone` and `Bay` (Task 4);
  - the `TreatOutcome.Case` reveal.
- Produces:
  - the goal card "Treat N";
  - the seven tutorial cards from design §13, with the beam targeting the bay, then the supply shelf or `Station_Remedy`;
  - Guide pins the front bay patient, then the station of the first missing step;
  - CreatureActing plays by `Case`;
  - the server Tutorial events "Examined" and "Treated", with the save field `TutorialCures` unchanged.

- [ ] **Step 1: Failing specs.**
  - The card titles match §13.
  - No client string matches `%f[%a][Cc]ure` (the `UiRules` scan).
  - The goal card reads "Treat 3 · 0/3".
- [ ] **Step 2: Run.** They fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Your specs pass.
- [ ] **Step 5: Report.** No commit.

### Task 9: Integration (Fable)
- [ ] Run the whole suite, the linter and the formatter, plus rojo build.
- [ ] Fix cross-task breaks.
- [ ] Grep `src/` for `Ailments`, `Potion`, `Pharmacy`, `QueueStart`, `queueSpot`, `Recipe.craft`, `Soak` and any
  visible "cure"; resolve each.
- [ ] Check the C6 calls match on both sides.
- [ ] Commit "Real Clinic: examine, treat, dispense in a big clinic from Lv 1".

### Task 10: Review lenses (Fable, read-only, in parallel)
Each lens returns findings with a concrete scenario.
1. **Walk-through:** every route (door -> reception -> seat -> bay -> stations -> dispensary -> ward via lift ->
   exit) at Lv 1-5, including closed rooms, the Cozy Ward bays and the X-ray bay.
2. **Saves and security:** v3/v4 saves; every remote's validation (TreatResult `Choice`, exam ratings, prompts'
   distances); one session per patient; leaving players.
3. **Kids and feel:** the copy (no cure, no scary words), the glow for first exams and Simple mode, phone fit, the
   loop's length per case, no pressure to spend.

### Task 11: Fixer (Fable)
- [ ] Verify each finding against the code.
- [ ] Fix the real ones, then run all four checks.
- [ ] Commit "Real Clinic: review fixes" and report each finding as fixed or rejected (with the reason).

### After the workflow (Claude, not an agent)
- Point Rojo at the worktree, or fast-forward the working branch after the checks.
- Run the Studio play-tests from design §14 with Joshua watching:
  - a fresh save through the tutorial;
  - every Lv 1 case;
  - the dispensary;
  - Lv 2 to 5 (wards, the X-ray, the ambulance, the helipad);
  - night;
  - a phone-sized capture.
- Fix what turns up, update `STATE.md`, and push. Nothing is published until both brothers say yes.
