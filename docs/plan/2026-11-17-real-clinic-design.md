# The Real Clinic: design (Update 2)

Ruling: `memory/records/memory-20261117-005.md` (Joshua, 2026-11-17). Joshua picked the visit flow ("B. kept light")
and left everything else to Claude ("your call for the rest"). Every choice below that isn't quoted from him is
Claude's call and is marked **(call)**.

## 1. Intent

Joshua, after playing the wide hospital:
> make it like a real hospital and doctor with a few cases... if he has a fractured arm, help him with a cast... if he
> has a cough, use a stethoscope... i dont think you should use "cure"s. it should be treatment based... the clinic
> should look realistic and big enough from the first moment. there should be a dispensary. so in the future a nurse
> can help with dispensing. but for now the player dispenses... hospital can still be much larger... floor texture
> shouldnt be wood (done, `d54591a`)... glass window on left is not obvious. make it a door or something.

The player should feel like **a doctor in a real clinic**. A patient comes in with something real and gentle, you
examine them with a real tool, you treat them with real supplies, you hand over their medicine from your own
dispensary, and they go home happy. The clinic looks like a real building from the first minute, and levelling up
opens more of it.

## 2. Goals, non-goals, anti-goals

**Goals**
1. A few realistic, gentle cases, each with: a symptom you can see, an exam with one tool, and a plan of 1-3 steps.
2. A visit in three beats: **examine -> treat -> dispense**, every beat a short mini-game.
3. A dispensary room the player runs: pick the right medicine and measure the dose.
4. A big, realistic clinic building from Lv 1: front doors, reception, waiting room, exam bays, supply shelf,
   dispensary. Levels open the floors and rooms that are already there.
5. The game's words say "treat", never "cure".
6. Every live save keeps its progress (cash, stars, rooms, Book, badges, nurses, rebirths, leaderboards).

**Non-goals (this update)**
- Nurses dispensing. That is the next step Joshua named ("in the future"). This update leaves a clear hook (§9).
- Renaming the game. The title stays "Cure a Creature" until both brothers decide (OPEN #12, red line 4).
- New paid items, new creatures, new art assets that need uploading.

**Anti-goals (a failure even if it works)**
- Anything scary or gross: no needles, no blood, no surgery, no crying pain. Rated Minimal stays true.
- A kid failing a patient. There is still no fail state: a wrong tool just says "Hmm, not that one" and lets them try
  again. OK still treats.
- A visit so long or fiddly that the loop drags. Each beat stays about 2-5 seconds; a 1-step case is three short games.
- Breaking or wiping anyone's save.

## 3. Constraints
- CLAUDE.md red lines: original game only, kids first (no off-platform links, no pressure to spend), nothing public
  without both brothers' yes. This update is built, tested in Studio and **not published** until both say yes.
- The server owns every outcome. Ratings only change the capped tip, as today.
- Performance: 60 fps on a mid phone with 6 full plots (perf budget doc). New part caps in §8.5.
- Save keys that already exist keep their names (§11).
- Studio play-tests after every visible milestone, so Joshua can watch (his ask, 2026-11-17).

## 4. Approaches considered

**The visit** (Joshua picked):
- A, the problem is shown, you treat it. Fast but not doctor-like.
- **B, you examine first, then treat, then dispense, kept light. Picked.**

**The building (call):**
- Keep growing a small building per level. Rejected: Joshua wants it "big enough from the first moment".
- **The full clinic from Lv 1, with closed floors and rooms that open with levels and purchases. Picked.** It keeps
  the levelling hook (`-008`) while the building looks real at once.

**The mini-games (call):**
- A brand-new game per tool and treatment (about 12). Rejected: a lot of client code, more to test on phones.
- **Re-skin the four engines that already work (hold-and-release, tap-the-spots, pop, timing) with a new look per
  tool, plus one new engine, Pick (choose the right tool or bottle). Picked.** Every game feels different on screen,
  but the code and the anti-cheat timing stay proven.

**Where treatment happens (call):**
- Keep treating at the Counter outside. Rejected: not a real clinic.
- **Exam bays inside: a patient sits on a bay bed; the doctor comes to them. Picked.** Several bays are busy at once,
  which keeps the player moving between bays, the supply shelf and the dispensary.

## 5. The visit, step by step

```
front doors -> reception -> waiting room seat -> exam bay -> EXAMINE -> plan shown -> TREAT steps -> DISPENSE -> home
                                                              (tool)                 (supplies)     (medicine)
```

1. **Arrive.** The patient walks in through the front doors, stops at reception, then sits in the waiting room. A
   small bubble over them shows the **symptom** ("😷 cough cough", "🤒 so hot", "💢 my arm"). The waiting room is the
   line (today's queue cap: 3 waiting, `Data/Levels.Queue`).
2. **To a bay.** When an exam bay is free, the patient who has waited longest walks to it and sits on the bed. A
   patient whose symptom needs the X-ray goes to the X-ray bay instead (§7). (call: automatic, like a receptionist
   sending them in. The player never herds patients.)
3. **Examine.** The bay's prompt says **Examine**. The exam card shows the patient and 3 tools. The player picks the
   right tool for the symptom (the **Pick** engine), then plays that tool's short game. Then the case is revealed:
   "🩺 It's a cough!" and its plan appears over the patient as icons (the existing needs badge).
   - **Kept light:** the right tool glows for a player's first 3 exams and always in Simple mode. A wrong pick costs
     nothing but a head-shake and a second try.
4. **Treat.** For each supply step (🩹 plaster, 🧊 ice pack, 🧻 bandage, 🦴 cast, 🛁 bath foam, ☕ hot chocolate) the
   player takes it from its station (the hold prompt, as today) and brings it to the bay. The bay's prompt now says
   **Treat**; the supply's game plays.
5. **Dispense.** For each medicine step the player goes to the dispensary, picks the medicine and measures the dose
   (§9), carries it to the bay, and hands it over (the bay's **Treat** prompt; handing over plays no extra game).
6. **Home or ward.** When the plan is done the patient thanks you, pays (cash to the helper, stars to the owner, as
   `Cure.resolve` does today) and walks out of the front doors. From Lv 2 a case marked **Stay** (a broken arm, a
   fever) first rests in a ward bed upstairs, using today's triage, escort, lift and recovery code, then pays and
   leaves. The bay frees as soon as the patient stands up.
7. **Patience.** It drains slowly in the waiting room and at normal speed in a bay waiting for the doctor, and pauses
   during every mini-game. Running out is a sad leave with no penalty (as today).

Several bays run at once. **"The front patient"** (what nurses, abilities, the guide pin and the tutorial point at)
becomes **the bay patient who has waited longest for the doctor** (call).

## 6. The cases

Gentle and realistic. Each line is: symptom bubble · exam tool · plan (in order) · Stay? · opens at. **(call: the
exact list; a builder may tune names and icons but not add needles or blood.)**

| Case | Bubble | Exam | Plan | Stay | Opens |
|---|---|---|---|---|---|
| Cough | 😷 cough cough | 🩺 Listen | 🧴 Cough syrup | | Lv 1 |
| Fever | 🤒 so hot | 🌡️ Temperature | 💊 Fever medicine | from Lv 2 | Lv 1 |
| Cut knee | 🩹 ouchie | 🔍 Look | 🩹 Plaster | | Lv 1 |
| Bumped head | 💫 bonk | 🔍 Look | 🧊 Ice pack | | Lv 1 |
| Earache | 👂 ow ow | 🔦 Ear check | 💧 Ear drops | | Lv 1 |
| Sprained ankle | 🦶 can't walk | 🔍 Look | 🧊 Ice pack, 🧻 Bandage | | Lv 2 |
| Sore throat | 🗣️ scratchy | 🔦 Throat check | 🍬 Throat lozenges, 🧴 Cough syrup | | Lv 2 |
| Itchy rash | 😖 itchy | 🔍 Look | 🧴 Soothing cream, 🧊 Ice pack | | Lv 2 |
| Broken arm | 💢 my arm | 🩻 X-ray | 🦴 Cast, 💊 Pain relief | yes | Lv 3 |
| Sore muscles | 😩 achy | 🔍 Look | 🛁 Bath foam, 💊 Pain relief | | Bath Room |
| Chills | 🥶 brrr | 🌡️ Temperature | ☕ Hot chocolate, 💊 Fever medicine | yes | Winter Wing |
| Broken leg (VIP) | 💢 my leg | 🩻 X-ray | 🦴 Cast, 💊 Pain relief, 🧻 Bandage | yes | Lv 5 heli |

- The hospital level still cuts each plan (`Data/Levels.RecipeCap` 1/2/3), so a Lv 1 player always sees one step.
- **Night patients** come to every clinic at night, so their cases use only Lv 1 cases (Cough, Fever, Earache).
- **Ambulance (A&E) patients** get a random case open at that clinic with at least 2 steps, padded with a 🧊 Ice pack
  if needed (replacing today's Potion/Plaster pad).
- **Every creature species keeps its Patient ID** (the Book's key), its wing and its look. **A patient's case is
  rolled each visit** from its wing's case pool, cut to the cases open at that clinic (§15 #2). The species list and
  the Book are unchanged.

## 7. Tools, supplies, medicines

**Exam tools** (on the tray at each bay; the X-ray is a machine in the X-ray room):

| Tool | Game engine | What you do |
|---|---|---|
| 🩺 Stethoscope (Listen) | tap-the-spots | tap the 3 glowing spots on the chest as each lights up |
| 🌡️ Thermometer (Temperature) | hold-and-release | hold while the reading climbs, let go in the green band |
| 🔦 Light (Ear or Throat check) | timing | tap as the light ring lines up with the ear or mouth, 3 times |
| 🔍 Magnifier (Look) | tap-the-spots | find and tap the 2 sore spots |
| 🩻 X-ray | timing | tap as the scanner bar passes over the bone, 3 times |

**Supplies** (stations you hold a prompt at, then carry to the bay):

| Supply | Station | Where | Treat game |
|---|---|---|---|
| 🩹 Plaster | `Plaster` (kept) | supply shelf, Lv 1 | tap-the-spots (today's Patch) |
| 🧊 Ice pack | `Ice` (new) | supply shelf, Lv 1 | hold-and-release (hold till cool) |
| 🧻 Bandage | `Bandage` (new) | supply shelf, Lv 2 | timing (wrap, 3 beats) |
| 🦴 Cast | `Cast` (new) | X-ray room, Lv 3 | timing (wrap, 4 beats) |
| 🛁 Bath foam | `Bath` (kept) | Bath Room (bought) | pop (today's Scrub) |
| ☕ Hot chocolate | `Cocoa` (kept) | Winter Wing (bought) | timing (today's Cool, blow) |

**Medicines** (made at the dispensary, station id `Remedy` kept, §9): 🧴 Cough syrup, 💊 Fever medicine, 💧 Ear
drops, 🍬 Throat lozenges, 🧴 Soothing cream, 💊 Pain relief. Each has its own bottle colour and icon. Handing one over
plays no game.

Gone: the 🧪 Potion item, the 💊 Pharmacy crafting station and the Progression v2 two-ingredient medicines (the
dispensary replaces them). The `Pharmacy2` rebirth unlock keeps its id and becomes **Expert Dispensing**: the dose's
green band is wider (call).

## 8. The building

### 8.1 Size (call)
- **Plots grow from 80 to 110** (`Config.Town.PlotSize`). The town lays out from it.
- **The clinic's footprint is 64 wide by 44 deep** (x -32..32, z -24..20; -z is the street), two storeys plus the roof
  at Lv 1 already standing. The storeys stay 12 / 11 (`Logic/Building`).
- The whole building exists at every level. What a level changes is which floors and rooms are **open**: a closed
  room has its door shut and a sign on it ("🔒 Opens at Lv 3" or "💰 600 to open").

### 8.2 Ground floor (open at Lv 1 unless marked)
- **Front:** a glass front door pair in the middle (it slides open when someone comes near; this is the "door"
  Joshua asked for where the display window was), a canopy and the clinic's name above it.
- **Lobby:** the reception desk (the plot's `Counter` moves here; a Receptionist nurse stands behind it when you have
  one) and the **waiting room**: 6 seats in rows (`WaitSeat_1..6`), a plant, a magazine table.
- **Exam bays:** 6 curtained bays along one side (`ExamBay_1..6`), each a bed, a curtain, a tool tray and a small
  number sign. 2 are open at Lv 1; levels open more (§10).
- **Supply shelf** in the corridor by the bays: `Station_Plaster`, `Station_Ice`, `Station_Bandage` (closed until
  Lv 2).
- **Dispensary:** a room with a counter and coloured bottle shelves, its hatch onto the lobby. `Station_Remedy`.
- **X-ray room** (Lv 3): the X-ray machine over its own bay (`ExamBay_X`) and `Station_Cast`.
- **Bath Room and Winter Wing** (bought rooms, as today) are rooms inside the ground floor's back half. Their
  stations and beds work as today.
- **Lift and stairs** at the back, as now.

### 8.3 Upper floors
- **F1 Injury Ward** (Lv 2): recovery beds for Stay cases (`BedSpot_<n>`, today's triage, escort and lift code).
- **F2 Rest Ward** (Lv 3) and **F3 staff room** with more Rest beds (Lv 4) (§15 #3). The Cozy Ward is on the ground
  floor (§15 #5).
- **Roof** (Lv 5): the helipad, as now.
- The hot tub and its Soak game go away; the Bath Room's bath replaces it.

### 8.4 Outside
- The plot keeps its sign, mailbox, fence, gate and trees; the plank path leads from the gate to the front doors.
- **No outdoor queue lane.** The line is the waiting room.
- The **ambulance bay** at the A&E side door (Lv 2), the **Sunny Garden** (bought) behind the building.

### 8.5 Parts budget (call)
- The Building: at most **420 parts** at any level and theme, at most **24 SurfaceGuis** (each with a MaxDistance),
  at most **10 see-through parts**.
- The plot's own share: at most 130. Rooms (interior fit-outs now, no walls or roofs): at most 90 together.
- A Lv 5 plot with every room: at most **640** (it was 400). Six plots plus the town stay under 4,500 parts.
- No Texture, no Decal, no light that casts shadows, nothing shaped or named like a cross.

## 9. The dispensary
- The player walks behind the counter and holds **Dispense** at `Station_Remedy`.
- The **dispensing card** lists the medicines that patients in bays still need (up to 3, the oldest first). If only
  one is needed, it is already chosen.
- **Pick:** 4 bottles on the shelf; tap the one whose colour and icon match the prescription. A wrong tap says
  "not that one" and you try again.
- **Dose:** hold-and-release: fill the cup to the line (today's Pour, re-skinned as a measuring cup).
- The medicine goes into your hands (today's Carry and tray). The rating feeds the tip when you hand it over, the way
  item games' ratings do today.
- **The nurse hook:** dispensing is the station `Remedy`. A future **Pharmacist** nurse job can fill the nurse tray
  from it. In this update, Maker nurses stock supplies only and never dispense (Joshua: "for now the player
  dispenses").

## 10. Levels and rooms

| Lv | Name | Open bays | Opens | Plan steps |
|---|---|---|---|---|
| 1 | Clinic | 2 | ground floor, supply shelf (plaster, ice), dispensary | 1 |
| 2 | Medical Centre | 3 | F1 Injury Ward, the A&E ambulance, bandages | 2 |
| 3 | Hospital | 4 | the X-ray room and casts, F2 Rest Ward, the ward pick | 3 |
| 4 | General Hospital | 5 | F3 staff room and more Rest beds | 3 |
| 5 | City Hospital | 6 | the helipad | 3 |

- The ⭐ gates, cash costs, spawn seconds and queue (3) stay as they are in `Data/Levels` (call). `Beds` becomes the
  ward beds upstairs; a new `Bays` field holds the open bays.
- The names above replace "First-Aid Stand" and friends (they fix the 🧰 icon question too; OPEN #11 asks only about
  Golden Hour and 🏥/🚑 now).
- Bought rooms (Bath Room, Cozy Ward, Winter Wing, Garden) keep their ids, prices and gates.

## 11. Saves (nothing is lost)
- **Kept ids:** Patient ids (Book), Room ids, badge ids, leaderboard ids (`Cured`, `Week`), Stats keys, Daily goal
  kinds, station ids `Plaster`, `Bath`, `Cocoa`, `Remedy`. `Made:Remedy` now counts medicines dispensed, so the old
  potion badge keeps climbing (renamed on screen: "Pharmacist").
- **New ids:** cases (they replace ailments, which were never saved), stations `Ice`, `Bandage`, `Cast`, the new
  items, game ids. New stations get new badges (they start at tier 0, which is correct).
- **Gone ids:** `Potion`, the crafted medicines, `Pharmacy`. None were saved; Daily goals that name a gone item are
  pruned by `Daily.prune`, which already exists.
- No `Schema.VERSION` bump is needed unless a builder changes a saved field's shape. If one does, bump to 5 and
  migrate in `Schema.reconcile` the way v3 -> v4 did.
- **Cases by wing** (call; §15 #2): a species no longer has one ailment. Its wing has a case pool and each visit
  rolls one case from it that the clinic can treat (its level and rooms). Regulars keep their stories and get one
  fixed case each from the table above.

## 12. Words
- Every player-visible "cure" becomes "treat": the goal card ("Treat 3"), mail goals, the tutorial cards, badge
  descriptions ("Treat patients"), Tip Jar hints, the admin buttons, and the leaderboard titles ("Most Patients
  Treated", "Treated This Week"; the board ids stay, so the boards keep their scores).
- Internal names (`Cure.resolve`, the `Cured` remote, the `Cured` save field) stay: renaming them buys nothing and
  risks saves.
- `docs/launch/page.md` gets a draft line about treating patients; it isn't published (red line 4).

## 13. The tutorial
Seven short cards, the floor beam pointing at each target: (1) welcome, Doctor; (2) a patient is in bay 1, tap
**Examine**; (3) pick the glowing tool and play; (4) the plan: get it from the shelf or the dispensary; (5) tap
**Treat**; (6) "You treated your first patient!"; (7) treat 3 more. Skip and Replay stay as they are.

## 14. Testing
- Lune specs for every pure part: the case data, plans and caps, the exam's tool pick, the new game ids and ratings,
  the dispensary's pick and dose, bay assignment, the save round-trip (an old v4 save loads with every count kept),
  the building's contract and part budgets.
- **Studio play-tests (Claude via MCP), with Joshua watching:** after the building lands; after the visit loop
  lands; then the full run: a fresh save through the tutorial, Lv 1 to Lv 5, every case once, the dispensary, a ward
  stay, the ambulance, night, a phone-sized view.

## 15. Calls made after the builder check (Claude, 2026-11-17)
A fresh reviewer read this design as a builder and asked five questions. Joshua delegated the rest ("your call for
the rest"), so these are Claude's calls. Where they disagree with an earlier section, they win.

1. **Nurses.**
   - **Healers and Medics can examine** (no game, no tip; the case is revealed) **and hand over anything in the nurse
     tray.**
   - **Makers stock supplies into the tray** (plaster, ice, bandage, cast, bath foam, hot chocolate). They never
     dispense.
   - **Medicine steps always need the player**, until the future Pharmacist job (Joshua: "for now the player
     dispenses"). This keeps the player at the heart of every visit while nurses still clear exams and supplies.
   - **Abilities are special.** Miracle (`CureLine`) and the other abilities may finish whole visits, medicine
     included, because they are rare and earned.
   - Nurse prices and ability numbers are unchanged; re-tune after play data.
2. **Cases roll per visit from the wing's pool**, filtered by what the clinic can treat (level and rooms):

   | Wing | Pool |
   |---|---|
   | Starter | Cough, Fever, Cut knee, Bumped head, Earache (Lv 1) + Sprained ankle, Sore throat, Itchy rash (Lv 2) + Broken arm (Lv 3) |
   | Night | Cough, Fever, Earache |
   | Bath | Sore muscles (+ the Starter pool) |
   | Winter | Chills (+ the Starter pool) |
   | Sunny (R1) | Itchy rash, Sprained ankle, Cut knee |
   | Sky (R2, heli) | Broken leg |

   This puts Joshua's broken arm in the everyday game from Lv 3 and keeps the Book sets as they are (no species gets
   gated by level). Data/AilmentActing is re-keyed by case.
3. **Departments.**
   - **Hydro** becomes the **Bath Room** (the Bath station and Sore-muscles patients).
   - **Pharmacy** becomes the **supply shelf and dispensary** (Makers stocking supplies; the future Pharmacist).
   - **Wards** stays.
   - No specialty is left without a home.
   - **The floors:** F1 is the **Injury Ward** (Lv 2: sprains, broken bones). F2 is the **Rest Ward** (Lv 3: fever,
     chills). F3 is the **staff room** with more Rest beds (Lv 4). The roof keeps the helipad (Lv 5).
   - **The Lv 3 floor pick** stays, as "Injury Ward or Rest Ward?" for a Stay patient, with the same +10% for the
     right pick and the Receptionist's instant pick. The §8.3 floor list and the §10 "Opens" column follow this.
4. **Release order.** The live game is Update 1 (schema v3). Progression v2, the look overhaul and the wide hospital
   are merged but unpublished.
   - **This update joins that pending release**, so the hot tub and the Pharmacy crafting are simply removed.
   - **Saves:** live v3 saves migrate through the existing v3 -> v4 step. v4 saves (Studio play without FreshSave)
     load as they are.
   - **Building and merging:** it is built in a worktree branch and merged into the working branch only when it is
     green and Studio-tested, so the working branch stays publishable at every moment.
   - If Joshua publishes the current build first, nothing breaks: none of the removed features were saved, and
     `Pharmacy2` keeps its id.
5. **The Cozy Ward** moves to the **ground floor** and **adds 2 exam bays** that work from Lv 1 (`ExamBay_W1`,
   `ExamBay_W2`). Buying it still means more patients at once, as its beds did before. Its price and gate are
   unchanged.

## 16. Left to the builder
- Exact coordinates, room sizes and the furniture inside the budget.
- Mini-game tuning numbers (within today's minimum-time rules).
- Colours and icons within the palette and the no-cross rule.
- The exact patient -> case table, and the symptom bubble wording.
- How the dispensing card lays out on a phone.
