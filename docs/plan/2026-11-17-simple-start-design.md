# Simple start: the next batch (design)

**Rulings:** `memory/records/memory-20261117-006.md` (simple start, the player routes patients, the pantry, a bigger
building with a see-through camera) and `memory/records/memory-20261117-007.md` (a calm UI with emojis used correctly).
Claude proposed the details below in chat on 2026-11-17. Joshua answered the UI questions and asked for the batch to
run in the cloud; he raised no objection to these details. Where the rulings and this doc disagree, the rulings win.

**Built on:** `claude/trusting-carson-5v32sr` at `f9e5785` (the Real Clinic plus the clinic-feedback batch, 1637
specs). Read `game/README.md`, `docs/plan/2026-11-17-real-clinic-design.md` (the game as it is) and
`logs/playtests/2026-11-17-clinic-feedback.md` first.

## 1. Simple at the start (Lv 1)
- **Lv 1 cases: Cough (🩺 → cough syrup), Cut knee (🔍 → plaster), Fever (🌡️ → fever medicine).** No others.
- **Later levels:**
  - Lv 2: Bumped head (ice), Earache (🔦 → ear drops), Sprain (ice + bandage).
  - Lv 3: Sore throat, Rash, Broken arm (X-ray).
  - Room cases: as today, from their room.
  - Lv 5: Broken leg.
  Move these by `Level` in `Data/Cases` and the case pools.
- **Lv 1 tools:** stethoscope, thermometer, magnifier (the exam's 3 choices). 🔦 from Lv 2; 📸 X-ray from Lv 3.
- **Lv 1 stations:** Plaster and the dispensary only. Ice from Lv 2 with its cases, Bandage Lv 2, Cast Lv 3.
- **The Lv 1 dispensary shelf** shows 2 bottles (cough syrup, fever medicine). The shelf rule already in the code
  (2-4 medicines the clinic's level uses) gives that once the cases move.
- **The tutorial stays:** a cough, then a cut knee. It gains one step: send the waiting patient to bay 1 (§2).

## 2. The player sends each patient (no receptionist desk)
- Walk-ins come in, stop at the reception spot and **sit** in the waiting room (built: `Config.Visit.SeatSeconds`).
- **The bay tick stops sending walk-ins on its own.** A seated patient shows its symptom bubble and a prompt **"Send"**
  (E). Pressing it sends it to the nearest free bay that fits it, through `U.callToBay` in `server/Patients.luau` (the
  seam is built). No free bay: a kind toast ("All bays are busy!").
- **From Lv 3, where there is a second place:**
  - A patient whose case needs the X-ray shows a 🦴 symptom.
  - Its prompt opens a two-button card: "🩺 Exam bay" / "📸 X-ray".
  - A wrong pick is gently corrected ("That one needs the X-ray!"), with no penalty.
  - At Lv 1-2 there is one kind of place, so it's one press.
- 🚑 / 🚁 patients still go straight to a bay (urgent).
- **A Receptionist** (the existing Reception specialty or job; check `Data/Jobs` and `server/Nurses.luau`) sends
  seated patients by itself after a short wait. That is the nurse hook ("nurses help later").
- Patience while waiting stays at the waiting-room rate. A patient left too long goes home (no penalty), as today.

## 3. Patients walk as little as possible: the pantry
- **Hot chocolate and bath foam come from a pantry** next to the supply shelf in the main building. Two new
  Building stations, `Station_Cocoa` and `Station_Bath`, each opening when its room is owned (Winter Wing, Bath
  Room).
- **No stations in the rooms.** The bought rooms are themed recovery rooms (beds, the fireplace, the tub as decor) and
  bring their case pools.
- Patients never walk into a room to be treated. Stay cases may still rest in a room's bed, as today.
- Keep every save id: `Made:Cocoa` and `Made:Bath` stats, the badge ids and the room ids.

## 4. A bigger, open building with a see-through camera
- **The ground floor about 1.5x bigger:** corridors at least 10 studs wide, bays about 9 wide, rooms and the waiting
  room about 1.5x. The tower and upper floors scale with it. The plot grows as needed (`Config.Town.PlotSize`, the
  town layout and the street).
- **All geometry stays in `shared/Logic/Building.luau`** (one foundation change). Everything else reads it. Keep the
  invariants its specs check: reach, path, doors, stations' prompts nearest at their own stand, no coplanar thin
  strips.
- **Low bay dividers:** curtain height about 6, so you see over them.
- **Camera:** walls between you and the camera go see-through (`DevCameraOcclusionMode` Invisicam, set for every
  player) instead of the camera squashing in. `Feel/Cutaway` stays for the upper floors.
- **Budgets** (`Config.Look`): raise them as needed and keep `PartBudget.spec` honest. Mind performance on phones
  (`docs/plan/2026-11-16-perf-budget.md`).

## 5. The UI rebuild
`docs/plan/2026-11-17-ui-direction.md`, as ruled in `-007`:
- one main button per Team card (Sell and List behind "More");
- titles in words;
- HUD doors revealed one at a time;
- navy progress bars;
- the emoji roles and rules;
- the "what a Lv 1 player sees" table.

Build it after §1-4 land: T0 foundation (`Theme`, `Kit`, `Modal`, `Icons`) first, then its five tasks.

## Not in this batch
Publishing (red line 4), new paid items, the arrow image upload (Joshua's account).
