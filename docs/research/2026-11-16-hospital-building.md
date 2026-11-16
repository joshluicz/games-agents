# The hospital building: a real hospital that grows, level by level (2026-11-16)

Asked after Joshua played the live game. His words, verbatim:
> the hospital looks dull, boring. only one hospital bed... its very very dull. i dont want a pop up tent. i want an
> actual hospital... they lack texture. is the builder for multiple levels, ie not a single story building. it should
> be a building. there should be some templates existing, we can take reference but it should be our own one.

He then pointed at the trending texture of the "Steal a ..." games: a studded-brick floor, with items and pets that
look built from studded bricks too. In our docs and in the game that style is **"studs"** or **"brick style"**, never
the toy brand's name.

**Scope.** Research and writing only. No code was changed, nothing was committed, nothing was inserted into Studio.
The only Studio tool allowed was the read-only `search_asset`, and it couldn't run (§2.2), so the Creator Store was
read through Roblox's public toolbox API instead.

**Status.** This is a **proposal** for Progression v2's T6 "Hospital world" and for the lead
(`.worktrees/progression/docs/plan/2026-11-16-progression-v2-build-plan.md` §B4, §C T6). T6 hadn't touched
`PlotBuilder.luau` when this was written: `Lift.luau` is still the Foundation stub. Nothing here is decided until
Joshua says yes. Colours and materials follow the art-direction spec, `docs/research/2026-11-16-art-direction.md` §2
and §4. That spec replaced my first draft, which had softer pastels.

**Markers.** **M** = measured, with its source and date. **C** = my judgement or design call.

**Coordinates.** All coordinates are plot-local studs (`PlotBuilder` convention). The plot is 70 × 70, centred on its
pad. **−z is the street**: the gate is at z −34.6 and the back fence at z +34.6. y = 0 is the pad top. As you stand in
the street looking at the hospital, **+x is on your left** and −x is on your right, the side with the sign and the
ambulance bay. The drawings in §6 are drawn that way.

---

## 0. The short version
1. **Today it reads as a tent.** At Lv 1 the "hospital" is the Stand: a striped awning over two tables and one bed
   (`13.png`). From Lv 2 a pale block rises behind it. Its upper storeys are hollow, walk-through blocks with painted
   windows. No floor above the ground can be walked on.
2. **The proposal: a brick-style podium with a ward tower behind it.** At every level, Lv 1 included, the Stand
   becomes the hospital's ground floor: the reception, with the Counter as its desk under a canopy. From Lv 2 a tower
   grows behind the podium, one walkable storey per level: **Wards (Lv 2) → Hydro (Lv 3) → Pharmacy (Lv 4) → a
   walkable roof with the helipad (Lv 5)**.
   - A **glass lift** runs up the tower's street-facing corner. Kids watch patients ride it.
   - Stairs climb a back atrium.
   - The A&E door faces the ambulance bay.
3. **Inside, a client-only cutaway.** When you're on a floor, the floors above you hide on your screen only. The
   camera then looks into your floor like a dollhouse. This rests on the camera code Roblox ships (§3.7). It also
   lets the upper walls become solid, so kids can't walk out of a third-floor wall.
4. **Look** (art-direction spec):
   - walls in the plot's full-strength colour, studded on every face (`CureStuds`);
   - dark roofs, warm-white trim, wood-plank floors and beams;
   - dark ribbon windows, with a glass band on the street side;
   - floating outlined letters, no sign boards.
   - Our own **paw-heart** mark replaces any cross. Never a red cross on white.
5. **Parts:**
   - Today's Lv 5 plot already counts **about 412** parts from the code. The 400 budget is already broken: the
     queue lane was added after the "389" figure was written (§5.2).
   - The new building costs **19 / 65 / 88 / 111 / 131** parts at Lv 1–5.
   - It fits the 400 budget only if the plot's scenery and rooms are rebuilt lean. A Lv 5 plot with every room then
     comes to **about 324**.
   - Without that rework it comes to about 477. The rework itself is mostly "tents become annexes" and "fewer
     balls".
   - **Keep 400. Don't raise it.**

---

## 1. What's there today, and why it reads as a tent
Read from `game/src/server/PlotBuilder.luau` (main) and the Progression v2 worktree, 2026-11-16.

| Thing | Where (plot-local) | Source |
|---|---|---|
| Room slots | Stand `(0, −6)` 22 × 14 · A `(−23, 6)` and C `(23, 6)` 18 × 16 · B `(−13, 25)` and D `(13, 25)` 22 × 14 | `SLOTS`, l. 51–57 |
| Counter | `(0, −14.5)`, 12 × 3.4 × 2.4, in the plot accent | l. 1150 |
| The line | `QueueStart (0, −18)`; places at z −18, −25, −32 (`QueueSpacing 7`, 3 places) | l. 1156, `Config` |
| Queue lane | x ±3.9 (6 wide + edges), from z ≈ −16 to −34 | `buildQueueLane` |
| Owner spawn | `(−6.5, −22)`, facing the Counter | `Plots.homeCFrame` |
| Stand stations and bed | Remedy `(−5.5, −1.3)`, Plaster `(0.5, −1.3)`, Bed_1 `(7.6, −4.8)`, decor slots `(−8.5, −10.2)` and `(8.3, −10.5)` | `LAYOUTS.Stand` |
| Building block (Lv 2+) | x ±11.5, z 2 to 13: between the side-room walkways, 5 studs in front of the back rooms | `footprint`, l. 1581 |
| Storeys | ground (ward) 12 tall, then `STOREY` = 7 | l. 1554–1556 |
| Ambulance bay | `BAY_AT (−26.8, −16.5)`, x −30.5 to −23, z −23 to −10 | l. 1565 |
| Patient walkways | x ±12.5, between the Stand and the side rooms; back lane at z 4 (`BackZ`) | `Patients.makeNav` (worktree) |

**Is the builder multi-storey?** Partly. `buildBuilding` stacks `Floors − 1` storeys above the ward from Lv 3 up to
Lv 5. Each storey is one `soft` block (walk-through, ray-ignored) with SurfaceGui windows (`buildStorey`,
l. 1802). Nothing above the ground can be stood on. Progression v2 makes the floors walkable: `Floor_<n>` slabs,
landings, a lift and stairs (§B4). §3 is the shape I'd give it.

**Why it reads as a tent (C):**
- The Stand is an open-fronted shelter. Its six-stripe awning is 12 parts out of the room's 51 (`buildShell`).
  Rooms A–C wear the same awning.
- There's one bed at Lv 1. A ward adds two more but sits out back. Upstairs beds don't exist yet.
- The walls are pale tints (`Wall = lighten(accent, 0.78)`). Everything is flat SmoothPlastic, so it has no
  texture.
- The upper storeys are blocks, not rooms, and the windows are painted on.

---

## 2. References: what to take, and what not to copy
Red line 2: we borrow ideas, mechanics and proportions, never another game's build, models, art or names. Every
model below is a **reference only**. Nothing gets inserted. We build ours in code, with optional meshes we make
ourselves.

### 2.1 How Roblox games show a hospital (or any building) that grows
**M** Player counts and votes come from Roblox's omni-search API, 2026-11-16, about 15:45 UTC. Visual notes are **C**,
from each game's official thumbnails, which are marketing renders.

| Game (place) | Playing now · up/down votes | What to take | What not to copy |
|---|---|---|---|
| [My School Tycoon](https://www.roblox.com/games/7591156407) (universe 2949408954) | 325 · 26,427 / 4,045 | **A building that gains a storey per upgrade.** Its title advertises "FLOOR 9 + 10". Every storey is the same module: a wall band, a regular row of windows and a white floor ledge. There's one strong central entrance and a big emblem on the façade. This is our "one floor per level" | Its peach school façade, clock and branding |
| [Infinite Tower Tycoon](https://www.roblox.com/games/10272636261) (3759884822) | 1,257 · 47,155 / 4,201 | Height is the reward: a strong floor-band rhythm and the "it keeps going up" read from far away | Its neon-green grid look |
| [Hospital Tycoon](https://www.roblox.com/games/7050008107) (2715844182) | 84 · 593,850 / 42,577 | The fantasy of unlocking hospital rooms one by one | Anything specific (its thumbnail is a dentist close-up) |
| [Maple Hospital](https://www.roblox.com/games/8704997000) (3308103880) | 5,040 · 501,835 / 78,299 | Interior cues: **privacy curtains between beds**, an IV stand, a pale upper wall over a coloured lower band, warm window light | Its characters, logo and layout |
| [Lakefalls Medical: GP Simulator](https://www.roblox.com/games/110233092317096) (10320417842) | 1,701 · 34,705 / 1,349 | **A row of linked waiting chairs** along a glazed wall, ceiling light panels, a reception sign | Its "RHS" (NHS-parody) sign and its characters |
| [Animal Hospital (Anomaly)](https://www.roblox.com/games/78515283254292) (10148749921) | 15,753 · 1,353,019 / 105,167 | The biggest "hospital" hit in search. Take only the two-tone wainscot wall with a stripe, the tiled floor and the waiting-chair row | Its horror creatures (teeth, anomalies) and dim navy palette. Ours are gentle |

**C, what they share:**
- Growth shows as **storeys you can count from the street**.
- The entrance is obvious.
- The interiors are read through big windows or from above.
- Hospital rooms are told by three props: **beds in a row with curtains, a waiting-chair row and a desk with a
  sign**.

### 2.2 Creator Store models
**How this was checked (M, 2026-11-16).**
- **`search_asset` couldn't run.** It needs a `studio_id`, which only comes from `list_roblox_studios`, and I'd been
  told not to call that. The first call also returned "Client proxy is out of date".
- **The toolbox API instead.** I used the same public, read-only API the earlier store research used:
  - search: `apis.roblox.com/toolbox-service/v1/marketplace/10?keyword=…`;
  - details (creator, votes, script and MeshPart counts, triangles): `/toolbox-service/v1/items/details`;
  - thumbnails: `thumbnails.roblox.com`, which I viewed.
- **Queries (models):** hospital, hospital building, modern / children / cartoon / low poly hospital, hospital
  tycoon, clinic building, hospital interior / ward / reception / lobby / tower / roof, pharmacy, helipad, ambulance,
  glass elevator, hospital bed, waiting room, animal hospital, vet clinic, toy / kids hospital, nurse station,
  medicine shelf, studs, classic studs, stud floor, brick building.

| # | Model (link) | Asset ID · creator | Facts (M) | What to take | What not to copy |
|---|---|---|---|---|---|
| 1 | [[NO SCRIPTS] Hospital Building](https://create.roblox.com/store/asset/5201630514) | 5201630514 · TheWingedGuest | **240 up / 60 down** (the best-voted hospital), 0 scripts, 6,758 tris, 2020 | **Tower beside a low wing** that holds the glass entrance (our tower and podium), a coloured plinth band, a sign up the tower's edge | Grey concrete everywhere, and its red asterisk, which looks like a red Star of Life |
| 2 | [Modern hospital](https://create.roblox.com/store/asset/6859192219) | 6859192219 · zbl_vini | 50 / 10, **4 scripts**, 641k tris | A long drop-off canopy on posts, ribbon windows, a low spread-out plan | 641k triangles, the scripts. 6732871974 (iLegend66: "I didn't build this", 655k tris) and 9507800083 are re-uploads of it |
| 3 | [Modern Hospital FREE](https://create.roblox.com/store/asset/17554270054) | 17554270054 · HKI5 | 0 votes, 0 scripts, 24k tris, "based in Ottawa… 2018" | A **podium with a tower on it**, a glass ground floor, a crown sign-box on top | The realistic grey office-tower look |
| 4 | [SmileTownHospital NoDoor](https://create.roblox.com/store/asset/15473994231) | 15473994231 · HKinxi | 0 scripts, 77 MeshParts, 360k tris | One strong colour with **floor bands**, a glazed curtain wall, a big rooftop sign | Its **red cross**, the 360k triangles |
| 5 | [Hospital Kit · ER, Ambulances, Helipad & Interior](https://create.roblox.com/store/asset/110024553730572) | 110024553730572 · Phantom25870 | **Paid** (US$2.99), 0 votes, 0 scripts, 34k tris, 2026-10-25 | An **"open-top cutaway" interior wing**, the dollhouse view we want (§3.7); an **EMERGENCY door with its own canopy next to the ambulance bay**; a rooftop helipad | Its red crosses (in its description). Don't buy it: we build our own |
| 6 | [Detailed HeliPad (Helicopter)](https://create.roblox.com/store/asset/12922051897) | 12922051897 · JuanCool_2004 | 50 / 0, 0 scripts, 67k tris | A dark pad with a white ring and H, edge lights, a safety net round the rim, an access stair | The triangle count |
| 7 | [HeliPad / Helicopter Pad](https://create.roblox.com/store/asset/11920315559) | 11920315559 · ResoluteEsc | 22 / 8, 0 scripts, 8 MeshParts, 1,244 tris | A light pad works fine: the ring and the H do the work | n/a |
| 8 | [Low Poly Vet Pack](https://create.roblox.com/store/asset/78793729198442) | 78793729198442 · tangloko2 | **Paid**, 478 MeshParts, 61k tris, 2026-10-25 | An animal clinic in cartoon props: **a paw on the reception desk front**, a checker floor | The pack itself |
| 9 | [Low Poly Hospital Props Pack x55](https://create.roblox.com/store/asset/81705968488921) | 81705968488921 · Lukami_th | Paid, 55 MeshParts | That a few chunky props say "hospital": bed, IV stand, monitor, wheelchair, curtain | Red crosses on its kits |
| 10 | [Hospital Waiting Chairs](https://create.roblox.com/store/asset/1431897996) | 1431897996 · Cake_Boy22 | 39 / 1, 0 scripts, 1,012 tris | **A row of linked seats on one beam as one prop** (1–2 parts, not 4) | n/a |
| 11 | [Hospital Bed](https://create.roblox.com/store/asset/5138086032) | 5138086032 · bip_q | 94 / 6, 0 scripts, 2 MeshParts, 2,418 tris ("spooky") | The silhouette that says "hospital bed": side rails and a raised head | The realistic, spooky look. 13571090371 and 13980044294 have identical triangle counts, so they're likely copies |
| 12 | [Hospital Reception Desk](https://create.roblox.com/store/asset/4972613155) | 4972613155 · MagicalGamerYshia | 8 / 2, 0 scripts, 144 tris | An L-shaped desk with a raised front ledge | n/a |
| 13 | [Ambulance (Mesh)](https://create.roblox.com/store/asset/4128328099) | 4128328099 · bearduckmonkey | 29 / 1, 0 scripts, **1 MeshPart**, 4,787 tris | Proof that a whole vehicle can be **one MeshPart** | Its livery |
| 14 | Stud references: [2022 Stud Material](https://create.roblox.com/store/asset/13719188279), [Studded Part](https://create.roblox.com/store/asset/8025924073), [Old stud block](https://create.roblox.com/store/asset/11257095071) | 13719188279 · FrostenOfficial (a MaterialVariant) · 8025924073 · skytimed · 11257095071 · cnnendot4133 | 658 / 42 · 3,920 / 80 · 8,640 / 360 | Proof that studs ship as **one MaterialVariant**, or as a part's surface | Their textures. We make our own `CureStuds` (art-direction §2.3) |

**Rejected:**
- Other games' IP: Pokemon Center BIG 513904379, CVS/Pharmacy 147669317 and 1367768507 (a real brand), Jailbreak
  Ideas: New hospital 3056054344, Strap Hood Hospital 12769746286 and DabHoodHospital 13422577919 (Da Hood
  derivatives), Happy Tree Friends Ambulances 8417062573.
- Admitted not their own: "Hospital (AWESOME)(Not mine)" 3881927.
- Likely backdoored re-uploads: a wave of keyword-stuffed "Hospital Building Bed Clinic…" uploads dated 2026-10-24,
  each with scripts, e.g. 119278063064791 (14 scripts) and 126712888958572 (37 scripts). Also everything by
  "Content Deleted - 158552482", e.g. 107110044719253, the re-uploader the creature research already flagged.
- Horror: Creepy Vet Clinic Kit 84175480337082.

### 2.3 Real children's hospitals
| Hospital | Cue (sourced) | What we take (C) |
|---|---|---|
| Royal Children's Hospital, Melbourne | A sweep of curved "leaf" blades across the main façade ([Frame](https://frameweb.com/article/the-royal-childrens-hospital-melbourne)). Wayfinding built on **landmarks at decision points**, simple language and pictures ([Büro North via Dexigner](https://www.dexigner.com/news/24905)) | Make the **lift lobby the landmark**: one place every floor starts from, with a big icon board. Each floor gets one colour and one icon |
| Lady Cilento Children's Hospital, Brisbane | The exterior echoes the greens and purples of the park's bougainvillea, with open space, bright colours and clear signs ([Archello](https://archello.com/project/lady-cilento-childrens-hospital), from the search snippet; the page blocked our fetch) | A bold façade colour is fine for a children's hospital, as long as the signs stay clear |
| Alder Hey Children's Hospital, Liverpool ([BDP](https://www.bdp.com/design-stories/alder-hey)) | Wings that reach out "like open arms" into gardens, and grass roofs that flow from the park. An atrium as the "heart". 75% of patients have single rooms with park views. **Balconies on every floor**. Lucy Casson's **creature artwork** in sculptures, fabrics and signage | A **roof garden** (Lv 5), the **podium roof as a terrace**, **big windows on every ward bed**, and **our creatures on the signs**, which is very on-brand for a creature hospital |

### 2.4 The moves we take (C)
1. **Tower and podium.** A low, friendly entrance block in front, with a taller ward tower behind it. It reads as a
   real hospital and keeps the front low (refs 1 and 3).
2. **One countable storey per level**, each a repeated module with a floor ledge and a window band (My School
   Tycoon, ref 4).
3. **An entrance canopy over the reception desk.** A separate **A&E door with its own canopy faces the ambulance bay**
   (refs 2 and 5).
4. **A glass lift you can see from the street.** The landmark lobby sits on every floor (RCH).
5. **Ward beds in a row, heads to the window, curtains between them.** Add a linked waiting-chair row and an L-desk
   (Maple, Lakefalls, refs 10–12).
6. **A walkable roof** with a helipad and a roof garden, plus a podium terrace (Alder Hey, ref 6).
7. **A dollhouse cutaway** for the inside view (ref 5).

---

## 3. The building
### 3.1 What it must not touch (Progression v2 §B4 contracts, kept)
- It must never cover the Counter, the queue lane's numbered spots, the gate, the sign, the walkways (x ±12.5), the
  side rooms (|x| ≥ 14) or the back rooms (z ≥ 18). The yard is z 13–18.
  - **The one exception is the entrance canopy.** It's soft, overhead at y 9.5, and stops at z −17, short of
    spot 1 at z −18.
- The pieces it must provide:
  - `Floor_<n>` Models, each with a collidable `Slab` and a `Landing` (an invisible 4×1×4 marker); `Landing_0` on
    the ground;
  - a `Lift` Model with `Shaft`, `Car` and `LiftPrompt`/`EscortPrompt` per landing;
  - a `Stairs` Model;
  - `Wards` with `BedSpot_<n>.Bed_<n>` (attribute `Floor = 1`);
  - `AmbulanceBay` (from Lv 2) with a `StretcherSpot`;
  - `Hydro.HotTub` with `TubSpot_1/2` and a `SoakPrompt`;
  - `Station_Pharmacy`;
  - `Roof` with the helipad and a `HeliSpot`;
  - `MascotSpot`.
- Every piece carries `Since`, and the Building carries `Level`/`GrewFrom`/`GrewAt`/`Floors`/`Theme`.
- **Beds keep their index and their spot** across level-ups.

### 3.2 The shape
```
   street-view, side on (looking from +x):

            [lift tower + neon logo]      <- Lv 5
   ____________________________ ____
  |  F3  Pharmacy      (Lv 4)  |    |
  |  F2  Hydro         (Lv 3)  | L  |  glass lift (street-facing corner)
  |  F1  Wards         (Lv 2)  |    |
  |  G   back hall, lift lobby, stairs  |
  |______________ podium (reception) ___|__ canopy __   Counter   queue lane ->  street
     z +13                    z -3            z -13      z -14.5     z -18 ...
```
- **The podium** is one storey: x ±11.5, z −13 to −3, y 0 to 11. It's the reception, with the Counter in its
  front opening.
- **The tower** is x ±11.5 (23 wide), z −3 to +13 (16 deep). The ground storey is **11 tall**; each upper storey is
  **9 tall**, giving 8 of headroom over a 1-stud slab. Slab tops sit at **F1 = 11, F2 = 20, F3 = 29, roof = 38**.
- **At Lv 5** it's 38 tall to the roof deck and about 48 to the beacon. Today's Lv 5 is about 47 to the beacon, so
  the skyline is about the same.
- **The vertical core:**
  - the glass lift sits at the tower's street-facing −x corner: x −11.5 to −6.5, z −3 to 2;
  - its door is on the back face (+z), onto a landing at `(−9, y, 4)` on every floor;
  - the **stair atrium** is x −9 to 9, z 7 to 13, with two 3-wide lanes: lane A at z 7–10 and lane B at z 10–13;
  - flights alternate lanes and directions: G→1 in lane A rising toward +x, 1→2 in lane B rising toward −x, 2→3 in
    lane A, 3→R in lane B;
  - a run of 18 studs gives 31° for the ground flight and 27° for the others. Each flight is one collidable wedge.

### 3.3 Key positions (plot-local; the drawings in §6 use these)
| Item | Position | Notes |
|---|---|---|
| Footprint | x −11.5 to 11.5; z −13 to +3 at **Lv 1**, z −13 to +13 from **Lv 2** | Lv 1 stops at z 3, so the patients' back lane at z 4 (`BackZ`) stays outside it |
| Main entrance | front wall (z −13), x 7 to 11, 7 tall | Ground-bed patients already walk in along x 7.6 (`bedRoute`), so they come through this door |
| Reception window | front, x −6.5 to 6.5, y 0 to 7 | The Counter sits in it; the fascia above (y 7 to 11) carries the name |
| Display window | front, x −11 to −7 | Decor slot 1 shows through it from the street |
| Side doors (Lv 1) | x ±11.5, z −1 to 3 | To the Bath Room and Winter Wing |
| A&E door (Lv 2+) | −x wall, z −7 to −3, with a red canopy outside | Faces the ambulance bay |
| Lift-lobby door (Lv 2+) | −x wall, z 2 to 6 | Upstairs patients come in here from the −x walkway (their route ends at z 4) |
| Corridor door (Lv 2+) | +x wall, z 2 to 6 | Patients' back lane (z 4) out to the +x walkway; players' way to the Winter Wing |
| Canopy | x −9 to 9, z −17 to −13, y 9.5, cantilevered (no posts) | Clear of the spawn (−6.5, −22) and of spot 1 |
| Remedy, Plaster | **(−4.3, −1.3), (1.7, −1.3)**: moved +1.2 in x | Clears the lift shaft; same distance from the Counter |
| Bed_1 (the Stand's) | (7.6, −4.8), unchanged | |
| Decor slot 1 | (−8.5, −10.3), unchanged | Behind the display window |
| Decor slot 2 | **(−9.5, −17.5)**: moved to the porch | The old spot (8.3, −10.5) sits right inside the main entrance |
| MascotSpot | **(−7, −14.8)**, beside the Counter's −x end | The §B4 fallback (−8, −13) would now sit in the façade |
| Waiting bench | x 10 to 10.9, z −8 to −3.5 (along the +x wall) | 1–2 parts |
| Lift shaft | x −11.5 to −6.5, z −3 to 2, y 0 to the roof | Glass on the street face and the −x face |
| Landings | `(−9, slab top, 4)`, 4 × 4 | `Landing_0`, then `Floor_n.Landing` |

### 3.4 Level by level
| Lv | Name (data) | Storeys | What it holds | Beds (data: Stand + ward) | Façade and roof | What grows (`Since`) |
|---|---|---|---|---|---|---|
| 1 | First-Aid Stand | G (podium only) | Reception: Counter, Remedy, Plaster, Bed_1, 2 decor slots, a waiting bench | 1 | A one-storey brick-style clinic: studded plot-colour walls, a warm-white trim stripe, a dark flat roof, the canopy over the desk, the name in floating letters on the fascia. **No awning** | The podium |
| 2 | Clinic | G + F1 | **A&E** opens: ambulance bay, A&E door and canopy. **Wards** on F1: 2 beds and a curtain. The lift and the first stair flight | 3 (1 + 2) | The tower appears behind the podium, 2 storeys (to y 20), with a glass lift on its corner. Its dark roof holds a lift motor box and a water tank | Back hall, F1, lift, stairs, bay |
| 3 | Hospital | G + F1 + F2 | **Hydro** on F2: the hot tub with 2 `TubSpot`s, a towel shelf, a plant | 3 | 3 storeys (to y 29). **Big sign**: the paw-heart disc on the tower's roof edge, facing the street | F2, logo sign |
| 4 | Big Hospital | G + 3 | **Pharmacy** on F3: `Station_Pharmacy`, a medicine shelf that also serves as the atrium rail, a bench. The 3rd ward bed and a 2nd curtain on F1 | 4 (1 + 3) | 4 storeys (to y 38) | F3, BedSpot_3 |
| 5 | Mega Hospital | G + 3 + **walkable roof** (`Floor_4`) | **Roof**: helipad with `HeliSpot`, roof garden, the theme prop | 4 | A dark roof deck with a parapet. The **lift tower** (y 38 to 47) wears the **Neon paw-heart** facing the street, with a beacon on top | Roof deck, tower, helipad |

**The A&E is on the ground at Lv 2+** (Departments `AE.Floor = 0`). The ambulance parks in the existing bay. Its
patient pops out at `StretcherSpot` and goes to the front of the line, as T7 specifies. The A&E door and its red
canopy tell the story.

**More beds?** Floor 1's plan has room for exactly 3 ward beds: heads to the window, 5.4 apart, with curtains between
them. That's all the data asks for at Lv 4 (Beds 4 = the Stand + 3). More beds would mean changing `Levels.Beds`,
which is the brothers' call. **C, optional:** draw the bed bay still to come at Lv 2–3 as a dashed outline labelled
"Lv 4". That's the same "for sale" pattern as room previews: a promise, not pressure.

### 3.5 Floor by floor at Lv 5
| Floor (y) | Department (Data/Departments) | Contents |
|---|---|---|
| **G** (0–11) | Reception (+ A&E door) | Counter (the desk) under the canopy; Remedy and Plaster; Bed_1; decor slot 1 behind the display window; waiting bench; lift lobby with **the lift directory** (one SurfaceGui: an icon and colour per floor); a **corridor at z 2–6** running through to both side doors; the first flight rising toward +x; a nook under the flight above |
| **F1** (11–20) | Wards | BedSpot_1 at x −4.1, BedSpot_2 at x 1.3, BedSpot_3 at x 6.7 (Lv 4). Frames run z −2.4 to 4.6 with the pillow at the window, so each bed's foot spot is z ≈ 6.0, in the back aisle beside the landing. Curtains at x −1.4 and 4.0. The front glass band |
| **F2** (20–29) | Hydro | Round hot tub, 8 across, centred on (2.5, 2.5). `TubSpot_1` at (0.8, 2.5), `TubSpot_2` at (4.2, 2.5). Towel shelf on the +x wall. A bubble emitter on the tub (0 parts; calm mode respected) |
| **F3** (29–38) | Pharmacy | `Station_Pharmacy` at (2, 5.2), facing the street side, so you hold from z ≈ 2.5. The medicine shelf along the atrium edge (z ≈ 7) doubles as its rail. A bench at x −5.5 to −2.5 |
| **Roof** (38) | Roof | Helipad 9.5 across at (3, 2.2) with `HeliSpot` at its centre. Lift tower at the −x front corner. Planters along the +x parapet. The theme prop (≤ 6 parts) at the +x front corner. The stair atrium railed off. A 1.2-tall dark parapet all round |

### 3.6 Who walks where (checked against `Patients.luau` in the worktree)
- **Ground-bed patients** take `bedRoute`: x 7.6 from the line to the bed's foot. They walk in through the **main
  entrance** and out the same way.
- **Upstairs patients** (T7): line → −x walkway (x −12.5) → in through the **lift-lobby door** at z 4 →
  `Landing_0` → `Lift.carry` → the bed. On the way out they come down by lift and `exitRoute` walks them east along
  `BackZ` (z 4) through the **corridor**, out the **corridor door**, down the +x walkway to `PatientExit`. Cozy Ward
  patients (slot B) leave along the same z 4 lane. Every route goes through a doorway, so nobody walks through a
  wall.
- **Players.** From the spawn, the main entrance or the reception gap leads behind the Counter. The side doors go to
  the Bath Room (−x) and the Winter Wing (+x). The lift lobby and stairs are at the back.

### 3.7 The inside view: a client-only cutaway, and solid walls
**The evidence (M).** Roblox's shipped camera (`PlayerModule/CameraModule/ZoomController/Popper`, read from the
Roblox-Client-Tracker mirror on 2026-11-16) only lets a part block the camera if
`getTotalTransparency(part) < 0.25`. Total transparency is `1 − (1 − Transparency)(1 − LocalTransparencyModifier)`.
The raycast also respects `CanCollide`.

So a part that doesn't collide, or that a client has set to `LocalTransparencyModifier ≥ 0.25`, **never pushes that
client's camera in**.

**The proposal (C):**
- **A client module** (for example in T8's `Feel/HospitalFX`) watches only the local character while it stands on
  its own plot's building footprint, checking 4 times a second and sleeping otherwise.
- When the character is on floor *n* ≥ 1, the module sets `LocalTransparencyModifier = 1` on everything above *n*
  (upper slabs, walls, roof, tower). It sets about 0.6 on the outer walls of floor *n*.
- **The result:** the camera looks into your floor from above, like the cutaway kit (ref 5). It changes only on a
  floor change, and nothing replicates. Other players see the building whole.
- On the ground floor it hides nothing. The owner works there most of the time and should see their tower.
- **The upper walls can then be solid** (CanCollide true), so kids can't walk out of a third-floor wall and fall.
  That changes §B4's "walls above the ground stay soft". The lead decides. If it stays soft, the cutaway still helps
  the camera.

### 3.8 The other rooms stop being tents (C)
Bath Room, Cozy Ward and Winter Wing become **single-storey annexes** in the same language. Each gets:
- three studded walls in its room colour (art-direction §4.1: Bath Cyan, Ward Purple, Winter Blue);
- a dark flat roof with a warm-white trim edge;
- its name in floating letters on that edge;
- a wood-plank floor;
- an open front facing the street, as today, so patients and stations work unchanged.

That costs 5–6 shell parts instead of 21. The Winter Wing keeps one snow slab on its roof. The Garden stays a garden:
studded hedges and an arbor.

### 3.9 What this changes in today's contracts (Requests for the lead and T6)
1. **The Stand loses its shell** (awning, walls, plaque) and keeps its floor, stations, bed and decor slots. The
   Building builds the podium **at every level, Lv 1 included**. §B4 and the README say the Lv 1 Building is empty.
2. **`LAYOUTS.Stand`, room-local:**
   - Remedy goes from (−5.5, 4.7) to **(−4.3, 4.7)**;
   - Plaster goes from (0.5, 4.7) to **(1.7, 4.7)**;
   - `DecorSlot_2` goes from (8.3, −4.5) to **(−9.5, −11.5)**, which is (−9.5, −17.5) on the plot.
3. **Storey heights:** the ground storey becomes 11 and `STOREY` becomes 9 (today 12 and 7).
4. **The Lift Model** goes at x −11.5 to −6.5, z −3 to 2, with its door on +z and landings at (−9, y, 4). The
   **Stairs** become one wedge per storey in alternating atrium lanes.
5. **Solid upper walls and the client cutaway** (§3.7): a §B4 change for T6 (walls) and T8 (cutaway).
6. **The night lights.** `applyNight` sets SmoothPlastic by day, so it would wipe studded Plastic and Glass. Store
   each part's day material in an attribute and restore it.
7. **`MascotSpot`** becomes (−7, −14.8).
8. **Themes vs the plot colour.** Themes "recolour the building's walls" (`Data/Themes`). But the art-direction spec
   paints the walls in the plot colour that kids find their clinic by. Suggestion: a theme recolours the roof, trim
   and roof prop, and leaves the walls in the plot colour.
9. **Scenery:**
   - Move the tree at (16.5, −9) to about (18.5, −10). Its crown would poke into the podium.
   - Drop the stepping stones under the building, since they're hidden at Lv 2+.
10. **Update the perf note's "389"** (§5.2).

---

## 4. Materials and colours (aligned with `2026-11-16-art-direction.md`)
### 4.1 Studs: where they go, and what each way costs
Following the spec (§2.2–2.4 there), there's **one** shared MaterialVariant, **`CureStuds`**:
- Plastic base, `StudsPerTile = 1`, our own near-white stud colour map and normal map;
- tinted by each part's `Color`;
- made once in Studio under MaterialService (its maps are PluginSecurity);
- set from code with `part.MaterialVariant = "CureStuds"`.

Until it exists, use **Plastic + `TopSurface = Enum.SurfaceType.Studs`**. It still renders, but on top faces only and
on Plastic only.

**There are no per-tile Texture instances anywhere in this design.**

| Way | Extra instances | Draw cost | Verdict for the hospital |
|---|---|---|---|
| `CureStuds` MaterialVariant | 0 | One shared texture set. It batches like any material (memory scales with pixels: a 256 px tile is tiny) | **Use it**: walls (all faces), the plot pad, prop tops |
| `TopSurface = Studs` | 0 | Built-in. One DevForum anecdote says it "acts similarly to Texture" when it's on every part | Prototype only |
| One `Texture` per face | +1 per face | "decals, textures, and particles don't batch well and introduce additional draw calls" ([Creator Hub](https://create.roblox.com/docs/performance-optimization/improve)) | **No** |
| Real stud cylinders | 1 per stud | The plot pad alone is 70 × 70 = 4,900 studs, the hospital footprint 23 × 26 = 598 and one tower face 23 × 27 = 621 | **Never** |

**Alignment.** A DevForum user reports that MaterialVariants tile **from the centre of each face**
([DevForum, 2023](https://devforum.roblox.com/t/more-control-over-materialvariant-tiling-origindirection/2203997)).
- So a studded face lines up best when it's an **odd number of studs** across and its centre sits on a whole stud.
  Studs then fall whole at its edges and match their neighbours.
- That favours 23-wide walls, 9- and 11-tall storeys and odd-sized wall pieces between doors.
- Snap every studded piece in Studio and check every seam (art-direction §2.3). The positions in §3.3 are a first
  pass at whole studs, not yet snapped to odd sizes.

### 4.2 Per surface
| Surface | Material | Colour (spec §4.1) | Notes |
|---|---|---|---|
| Plot pad (the building stands on it) | Plastic + CureStuds | `#253D4C` dark slate-teal | Slate edging `#8A8E94` |
| **Outer walls**, podium and tower | Plastic + CureStuds | **the plot accent at full strength**: Pink `#DB3D7D`, Blue `#3195E0`, Orange `#EB842A`, Purple `#894ECC`, Yellow `#F5C731`, Cyan `#29BCCC` (Plot_1 to 6) | One colour per building: kids find "the pink one" |
| Trim stripe, window frames, canopy edge | SmoothPlastic | `#F0EBDF` warm white | Never pure white |
| Roofs, roof edges, parapet, canopy top, the A&E canopy's edge | SmoothPlastic | `#2D2B3D` | The dark anchor |
| Floor slabs (inside floor and outside beam) | WoodPlanks | planks A `#AD8053` (B `#996B45` for a second board) | The slab edge reads as the wood beam between storeys |
| Ribbon windows (sides, back) | SmoothPlastic | dark pane `#2F3B57` (C) | "Dark openings" (spec §1.3). At night they turn a warm mid colour, **not Neon** (spec: Neon on small parts only) |
| Front glass band (one per storey, street face) | Glass, Transparency 0.3 | tinted to match the panes | Lets the street see patients in bed. Mobile skips refraction ([Materials](https://create.roblox.com/docs/parts/materials)) |
| Lift shaft | Glass, Transparency 0.3 | same | The **car** is SmoothPlastic in the plot colour with a studded top: "the pink car going up" |
| Interior lower wall (dado) | Plastic + CureStuds | the **department colour** (§4.3) | A lining part only where it shows (the back of the reception, each ward wall). Otherwise the inside face keeps the plot colour |
| Interior upper wall | SmoothPlastic | `#EBE4D8` | Same rule |
| Desk, beds, stations, benches | SmoothPlastic body + **studded top** | body in the department or plot colour; top Plastic + CureStuds | Use the top parts that already exist (CounterTop, the stations' `Top`, the blanket). No extra plate parts |
| Mattress `Bed_<n>` | SmoothPlastic | `#F0EBDF` | Patients lie on it, so it stays smooth |
| Curtains | Fabric (built-in) | the department colour | |
| Hot-tub water | Glass, Transparency 0.3 | `#38A7D6` | Spec water |
| Helipad | a flat part with a top SurfaceGui | gold ring `#FFD84A`, white H, on the dark roof | Today's `buildHelipad` approach |
| Ambulance | SmoothPlastic | warm-white body, a **red `#D63C4B` stripe** (props only), the paw-heart badge, red and blue sirens (Neon at night) | Never a cross |
| A&E canopy | SmoothPlastic | red `#D63C4B` top, dark edge | Red as a prop colour, never a plot colour or a cross |
| Planters, roof garden | Plastic + CureStuds | leaves `#39A844` / `#2B8F42` | Voxel cubes |

### 4.3 Department colours, inside only (C)
Each colour follows the room or station of the same department, so it never sends a kid to the wrong station:
- Reception is the plot colour (as the Stand).
- Wards is **Purple** (the Cozy Ward room).
- Hydro is **Cyan** (Bath, its station's department).
- Pharmacy is **Blue** (the Winter Wing, whose Cocoa station is in Pharmacy).
- The roof is leaf greens.
- A&E is a red prop (the canopy and the ambulance stripe).

They show inside, as the dado band, the curtains and the bed blankets, and on the lift buttons. The outside stays one
plot colour, as the spec asks.

### 4.4 Signs, labels and the emblem rule
- **Labels float as outlined text with no board** (spec §4.4). This covers:
  - the name on the podium fascia;
  - the A&E letters over its door;
  - a floor icon floating on each glass band (bed, tub, medicine), so the street can read which floor is which;
  - "Pharmacy" on the medicine shelf.
- **Our mark is a "paw-heart"** (C): a heart with paw pads, white on the plot colour, in a warm-white rim. It's the
  game's own brand mark for a creature hospital (Alder Hey's creature signage, the vet pack's desk paw). The
  brothers decide the final design. It appears on:
  - the desk front;
  - the Lv 3 roof-edge sign;
  - the Lv 5 Neon sign on the lift tower;
  - the ambulance;
  - the nurse caps.
- **Never a red cross on a white ground.** It's the Red Cross emblem, protected under the Geneva Conventions and the
  national laws behind them:
  - [ICRC, use of the emblems](https://www.icrc.org/en/law-and-policy/use-emblems);
  - the British Red Cross wrote to *Prison Architect*'s developers in 2017 over red crosses on its vehicles
    ([PC Gamer](https://pcgamer.com/how-the-prison-architect-developers-broke-the-geneva-conventions));
  - the Canadian Red Cross asks game makers to stop
    ([Canadian Red Cross](https://redcross.ca/about-us/about-the-canadian-red-cross/red-cross-emblem/it-may-just-be-a-game-to-you-but-it-means-the-world-to-us)).
- **The same goes for the red crescent and red crystal.** Also avoid:
  - a white cross on red, which reads as the Swiss flag or the emblem inverted;
  - the **blue Star of Life**, a US certification mark held by NHTSA since 1977
    ([ems.gov](https://ems.gov/staroflife.html);
    [Federal Register, 1994](https://www.govinfo.gov/content/pkg/FR-1994-08-11/html/94-19562.htm)).
- **First-aid wayfinding** (small, optional) can use the ISO 7010 E003 sign: a **white cross on green**
  ([Wikipedia: ISO 7010](https://www.wikipedia.org/wiki/ISO_7010)).
- **Today's `crossSign`** (a white cross on the accent disc) is legal but generic. Swap it for the paw-heart.

### 4.5 At night
- The glass bands and ribbon windows turn to a **warm mid colour**, `#D8B470` (C). Every storey reads as lit, without
  big Neon areas blooming.
- The **paw-heart** on the tower and the **beacon** are Neon: small parts, with one shadowless light, as today.
- The ambulance's lights are T8's `HospitalFX`.
- All of this uses the existing `ClinicNightLight` tag. Fix the day-material restore first (§3.9 item 6).

---

## 5. Parts and performance
### 5.1 What each technique costs (for phones, 6 plots per server)
| Technique | Instance cost | Render cost | Use it for |
|---|---|---|---|
| **Part** (block, wedge, cylinder) | 1 | Cheap. Identical shapes and materials batch | The shell: walls, slabs, bands, flights |
| **MeshPart** | 1 | Copies of one mesh with the same texture are "collapsed… into a single draw call". Different asset IDs break that ([Improve performance](https://create.roblox.com/docs/performance-optimization/improve)) | **Repeated props** made once: bed, tree, bench, ambulance, chair row, stair. Use Box or Hull collision, never Precise |
| **Union** (CSG) | 1 | Each union is its own geometry, so it doesn't instance across plots, and code can't sensibly make one at runtime | Avoid. Use a MeshPart |
| **MaterialVariant** (`CureStuds`) | 0 | One texture set; materials batch | Studs everywhere |
| **Built-in materials** (Brick, WoodPlanks, Fabric, Slate, Glass) | 0 | "Built-in materials use far less memory than custom textures" ([Design for performance](https://create.roblox.com/docs/performance-optimization/design)) | Planks, fabric, slate, glass |
| **Texture / Decal** | +1 per face | Doesn't batch; adds draw calls | Not used here |
| **SurfaceGui** | +1 each | Cached until it changes ([DevForum](https://devforum.roblox.com/t/static-ui-performance-improvements/222557)); `MaxDistance` cuts far ones ([DevForum](https://devforum.roblox.com/t/new-surfaceguimaxdistance-property/2574715)) | Letters, icons, the helipad, the lift directory. **≤ 12 per building**, each with few frames and a `MaxDistance` |
| **Transparent part** | 1 | "Avoid transparency values other than 0 and 1": overlapping pixels draw more than once | The front glass bands, the lift shaft, the tub water: **≤ 6 per building** |
| Neon + light | 1 + light | Shadowless lights only (perf note) | The logo, the beacon, the sirens |

### 5.2 Today's count (M, counted from the code on main, 2026-11-16)
| Part of the plot | Parts |
|---|---|
| Plot scenery: pad, lawn stripes, path, stones, Counter, markers and slots, sign, **fence and gate (48)**, mailbox, **5 trees (25)**, **8 bushes (32)** | 159, of which the queue lane is 21 |
| Rooms: Stand 51 · Bath 38 · Ward 42 · Winter 46 · Garden 31 | 208 (each awning is 12) |
| Building at Lv 5 | 45 |
| **Lv 5 plot with every room** | **≈ 412** |

The perf note and `PlotBuilder` say 389. That figure was written in the depth-update integration (`220d604`). The
21-part queue lane landed a minute later in a parallel commit (`3381eae`), so **today's Lv 5 plot is about 410, over
400.** A Studio count (perf note, "How to measure" step 3) would confirm it. Studio was in use, so I didn't run it.

### 5.3 The new building, per level (C, counted from §3)
| Lv | Shell | Floors and core | Departments | Total |
|---|---|---|---|---|
| 1 | front wall 5, sides 6, back 2, floor strip 1, roof and trim 2, canopy 2 | n/a | MascotSpot 1 | **19** |
| 2 | G shell 22, plus A&E canopy and paint 3 | F1 storey 14 (slab 3, walls 4, windows 4, trim 1, rail 1, flight 1); roof cap 4; lift 4 (shaft, car, 2 landings) | Wards 7 (2 beds × 3, curtain); bay 10 (pad, ambulance 8, StretcherSpot); MascotSpot 1 | **65** |
| 3 | +0 | F2 storey 14, landing 1 | Hydro 7 (tub 3, 2 TubSpots, shelf, plant); logo sign 1 | **88** |
| 4 | +0 | F3 storey 14, landing 1 | Pharmacy 4 (station 3, bench); bed 3; curtain 1 | **111** |
| 5 | +0 | The roof cap and logo (−5) become a deck: slab 3, rail 1, parapet 4, flight 1, landing 1 | lift tower 2, Neon logo 2, beacon 1, helipad 1, HeliSpot 1, planters 2, theme prop ≤ 6 | **≈ 131** |

**Per-building draw extras at Lv 5:** about 12 SurfaceGuis, 6 transparent parts, 0 Textures and 2 small Neon parts
with one light.

### 5.4 The lean rebuild of the scenery and rooms (C, spec-aligned)
| | Today | Proposed | How |
|---|---|---|---|
| Pad, edging, lawn stripes, path, stones | 13 | 8 | Dark studded pad, 4 slate edges, plank path, 2 stones |
| Counter, markers, slots, mailbox | 14 | 14 | Unchanged |
| Sign | 6 | 3 | Floating letters: no trim board, no caps |
| Fence and gate | 48 | 36 | Posts every ~14 studs instead of 10. **A fence-segment MeshPart** would make it about 27 |
| Trees | 25 | 30 | Spec voxel trees (about 6 studded cubes each). **One tree MeshPart** with CureStuds would make it 5 |
| Bushes | 32 | 8 | One studded cube each |
| Queue lane | 21 | 12 | 6 tiles instead of 12; each number SurfaceGui sits on its spot disc |
| **Scenery** | **159** | **111** | |
| Stand / Bath / Ward / Winter / Garden | 51 / 38 / 42 / 46 / 31 | 19 / 13 / 17 / 19 / 14 | No awnings (§3.8); 3-part beds; blocky station props |
| **Rooms** | **208** | **82** | |

### 5.5 Totals per level (every room the level allows; no creatures, nurses or decor)
| Lv | Today | New building, today's scenery and rooms | **New building + lean rebuild** |
|---|---|---|---|
| 1 | 336 | 334 | **198** |
| 2 | 360 | 380 | **244** |
| 3 | 391 | 434 ✗ | **281** |
| 4 | 408 ✗ | 457 ✗ | **304** |
| 5 | 412 ✗ | 477 ✗ | **324** (≈ 299 with a tree mesh) |

### 5.6 Is 400 enough?
**Yes, if the scenery and rooms are rebuilt lean**: about 324 at Lv 5, with about 75 to spare. **No otherwise**: about
477, so you'd need about 480 with no headroom.

I wouldn't raise it, for three reasons (C):
1. **The look comes from studs, materials and real windows, not from part count.** Most of today's parts are balls,
   awning stripes and fence posts.
2. **The plot isn't the biggest load.** Progression v2 allows 8 working nurses at up to 40 parts each, so **320 per
   plot**. Add up to 4 creatures at about 35 each (about 140) and decor (up to about 250). That's about 1,000 a plot
   and about 6,000 a server before the town and the belt.
3. **Phones.** Six identical buildings instance well. What hurts is draw calls (Textures, SurfaceGuis, many
   materials), overdraw (transparency) and shadows. §5.1 caps those per building.

A split to hold T6 to: **building ≤ 135 · rooms ≤ 90 · scenery ≤ 115 · spare ≥ 60**.

### 5.7 What has to become meshes or materials
- **Has to:** the studs (`CureStuds`, 0 parts); windows as plain parts (never Textures); labels as SurfaceGuis on
  existing faces (0 parts); every room awning gone.
- **Should, ranked by parts saved × how often it repeats:**
  1. a **tree** mesh (−25 a plot, plus the town's trees);
  2. a **bed** mesh: frame, headboard and blanket in one, keeping `Bed_<n>` as a Part (−1 each, 8 beds);
  3. a **fence segment** (−9);
  4. the **ambulance** (8 → 2: body mesh plus the sirens);
  5. a **chair row** and **bench**;
  6. a **stair** mesh, laid over the collidable wedge (+1 each, for looks).
- **Where meshes come from:** Joshua builds alone with Claude. So the meshes are ours, made in Blender or with
  Studio's own mesh generation, uploaded once, and kept in `ServerStorage.ClinicKit`. The code clones a mesh when it's
  there and builds parts when it isn't, which is today's kit pattern.

**Measure, don't guess:**
- the perf note's count script at Lv 5;
- `Highlights ≤ 1` and no shadow lights;
- a mid phone with 6 full plots at night, at Editor Quality Level 1, 4 and 10 (art-direction §2.2). Watch for stud
  shimmer on the tower's far faces.

---

## 6. Floor plans (ASCII)
Drawn from above with **the street at the bottom**, so **+x is on the left**, as you see it from the street. **One
character = 1 stud across; one line = 2 studs deep.** Positions are rounded to that grid; §3.3 has the exact
numbers. They were generated from those coordinates (`scratchpad/scripts/plans.py`, not committed).

### 6.1 Lv 1: ground floor (the podium; the whole building at Lv 1)
```
z  +3    ######################      back wall
z  +1    ......................      <- side doors at both ends (z -1..+3)
z  -1    .BBBBB.PPPPP.RRRRR....
z  -3   #wwBBBB.PPPPP.RRRRR....#
z  -5   #wwBBBB................#
z  -7   #wwBBBB................#
z  -9   #wwBBBB...........ddddd#
z -11   #.................ddddd#
z -13   #                  =====     front: main door | reception window | display window
z -15         CCCCCCCCCCCCCmdddd     Counter (the desk); canopy overhead z -13..-17
z -17           |  1   |   ddddd
z -19           |      |   ddddd
z -21           |      |
z -23           |      |  @
z -25           |  2   |
z -31           |  3   |
   x:    +11  +6    0     -6   -11
```
Legend:
- `#` studded wall in the plot colour;
- gaps in `#` are doors and openings: the main door is x 7..11, the reception window x −6.5..6.5;
- `=` display window;
- `.` wood-plank floor;
- `R` Remedy, `P` Plaster (both moved +1.2 in x), `B` Bed_1;
- `d` decor slots (1 inside, 2 on the porch), `w` waiting bench;
- `C` Counter, `m` MascotSpot;
- `| 1 2 3` the queue lane and its places in line;
- `@` owner spawn.

### 6.2 Lv 5: ground floor
```
z +13    '########################' :::::::::::::::::::
z +11    '#..___________________.#' :                 :
z  +9    '#..sssssssssssssssssss.#' :                 :
z  +7    '#..sssssssssssssssssss.#' :                 :
z  +5    ' ..................llll ' :   RoomA         :
z  +3    ' ..................llll ' :                 :
z  +1    '#.................LLLLLL' :                 :
z  -1    '#.BBBBB.PPPPP.RRRRLLLLLL' :::::::::::::::::::
z  -3    '#wwBBBB.PPPPP.RRRRLLLLLL'
z  -5    '#wwBBBB................ '^^
z  -7    '#wwBBBB................ '^^
z  -9    '#wwBBBB...........ddddd#'
z -11    '#.................ddddd#'          aaaaaaaa
z -13    '#                  ====='          aaaaaaaa
z -15    '      CCCCCCCCCCCCCmdddd'          aaaaaaaa
z -17    '        |  1   |   ddddd'          aBAYaaaa
z -19    '        |      |   ddddd'          aaaaaaaa
z -21             |      |                   aaaaaaaa
z -23             |      |  @                aaaaaaaa
z -25             |  2   |
z -31             |  3   |
   x:      +11        0          -11         -23    -30
```
Legend:
- `L` glass lift shaft; `l` `Landing_0`;
- `s` the G→1 flight (lane A), rising toward +x (left);
- `_` the nook under the 1→2 flight (lane B);
- the gaps at z +3..+5 are the corridor door (+x, left) and the lift-lobby door (−x, right);
- the gap at z −5..−7 on the right is the A&E door, with `^` its red canopy outside;
- `'` the patients' walkways (x ±12.5);
- `:` Room A (the Bath Room); `a` the ambulance bay (Lv 2+).
- Everything else as in Lv 1.

### 6.3 Lv 5: upper floors (tower z −3..+13; the podium roof below is `"`)
```
F1  WARDS (slab y 11)                 F2  HYDRO (slab y 20)
z +13   ########################      z +13   ########################
z +11   #..zzzzzzzzzzzzzzzzzzz.#      z +11   #..zzzzzzzzzzzzzzzzzzz.#
z  +9   #..sssssssssssssssssss.#      z  +9   #..sssssssssssssssssss.#
z  +7   #..-------------------.#      z  +7   #..-------------------.#
z  +5   #..BBfBBBBfBBBBBfBBllll#      z  +5   #.....ooooooo......llll#
z  +3   #..BBBBB|BBBB|BBBBBllll#      z  +3   #h....oToooTo......llll#
z  +1   #..BBBBB|BBBB|BBBBLLLLLL      z  +1   #h....ooooooo.....LLLLLL
z  -1   #..BBBBB|BBBB|BBBBLLLLLL      z  -1   #h......ooo.......LLLLLL
z  -3   ===================LLLLL      z  -3   ===================LLLLL
z  -5   """"""""""""""""""""""""      z  -5   """"""""""""""""""""""""
   x:    +11  +6    0     -6   -11

F3  PHARMACY (slab y 29)              ROOF (deck y 38, Lv 5)
z +13   ########################      z +13   ########################
z +11   #..zzzzzzzzzzzzzzzzzzz.#      z +11   #,,zzzzzzzzzzzzzzzzzzz,#
z  +9   #..sssssssssssssssssss.#      z  +9   #,,                   ,#
z  +7   #..HHHHHHHHHHHHHHHH---.#      z  +7   #,,-------------------,#
z  +5   #......MMMMMM......llll#      z  +5   #pp,,HHHHHHHH,,,,,,llll#
z  +3   #..................llll#      z  +3   #pp,HHHHHHHHHH,,,,,llll#
z  +1   #.................LLLLLL      z  +1   #pp,HHHHH*HHHH,,,,TTTTTT
z  -1   #.............wwwwLLLLLL      z  -1   #!!,,HHHHHHHH,,,,,TTTTTT
z  -3   ===================LLLLL      z  -3   ###################TTTTT
z  -5   """"""""""""""""""""""""      z  -5   """"""""""""""""""""""""
```
Legend:
- `s`, `z`: the stair atrium's two lanes (A at z 7..10, B at z 10..13). On each floor one flight arrives and the
  other leaves;
- `-` the atrium rail; `=` the front glass band; `L` lift, `l` landing.
- F1: `B` ward beds, pillow at the window, BedSpot_3 (the left one) from Lv 4; `f` each bed's foot spot; `|`
  curtains.
- F2: `o` hot tub, `T` TubSpots, `h` towel shelf.
- F3: `M` `Station_Pharmacy`; `H` the medicine shelf, which is also the rail; `w` bench.
- Roof: `,` dark deck, `H` helipad, `*` HeliSpot, `T` the lift tower (Neon logo on its street face), `p` planters,
  `!` the theme prop, `#` parapet.

### 6.4 Lv 5: front elevation (as seen from the street; 1 line = 3 studs of height)
```
y 48                        *       beacon (Neon, night)
y 45                     ######     lift tower, plot colour
y 42                     ##<3##     Neon paw-heart logo
y 39   #!pp####################     roof parapet (dark) + planters + theme prop
y 36   ##################|::::|     F3 Pharmacy: wall
y 33   ==================|::::|     F3: glass band
y 30   ------------------|::::|     wood floor beam
y 27   ##################|::::|     F2 Hydro: wall
y 24   ==================|:LLL|     F2: glass band     lift car (L)
y 21   ------------------|::::|     wood floor beam
y 18   ##################|::::|     F1 Wards: wall
y 15   ==================|::::|     F1: glass band
y 12   ------------------|::::|     wood floor beam / podium roof edge
y  9   ######CLINIC NAME#######     podium fascia: outlined letters, no board
y  6   #                  =====     door | reception window | display window
y  3   #     CCCCCCCCCCCCC#####     the Counter sits in the opening
  x:    +11  +6    0     -6   -11
```
The podium (front at z −13) stands 10 studs in front of the tower (front at z −3). Above y 11 you're looking at the
tower over the podium roof. The canopy (y 9.5) and the A&E side aren't drawn.

---

## 7. Decisions for Joshua (to copy into `context/OPEN-QUESTIONS.md`)
1. **A real building from Lv 1?** Yes means the Stand becomes the podium clinic and the tent goes. Lv 1 is still
   called "First-Aid Stand". Keep the name, or rename it? Names are yours.
2. **One bold plot colour on the whole building** (the art spec)? The alternative is a white hospital with
   plot-colour bands. The spec's way reads as the trending brick style; trim, dark roofs and glass make it read as a
   hospital.
3. **Solid walls upstairs, plus the see-into-your-floor cutaway** (§3.7)? Or keep soft walls, which kids can walk out
   of?
4. **Ward beds face the window** (patients' heads at the glass, the aisle behind)? And do you want more than 3 ward
   beds later? That's a `Levels.Beds` change.
5. **Our logo:** a paw-heart? The brothers design it. It's the hospital's mark everywhere the cross is now.
6. **The lean scenery** (§5.4): fence posts spaced wider, one-cube bushes, tents become annexes. Without it the 400
   budget breaks at Lv 3.

## 8. Not checked
- **The parts were counted by hand** from the code, not in Studio. Studio was in use, so the perf note's count
  script wasn't run.
- **Some claims rest on DevForum users, not Roblox docs:**
  - MaterialVariant centre-tiling;
  - Steal a Brainrot's stud material (the art-direction spec's source).
  Test the stud alignment on one wall in Studio first.
- **Walking and clearances need a Studio pass:** lift and landing sizes, stair slopes and headroom, doorway
  clearances for the biggest creature (about 5 wide), and the canopy height against the tallest creature.
- **The Creator Store models** were judged from their thumbnails and API facts only. None was inserted or opened.
- **The ICRC page** came from search results and wasn't fetched in full. The emblem rule doesn't depend on it: the
  repo already bans the red cross (`docs/guides/build-the-clinic.md`).

## Sources
**Roblox docs:**
- [Improve performance](https://create.roblox.com/docs/performance-optimization/improve)
- [Design for performance](https://create.roblox.com/docs/performance-optimization/design)
- [Materials](https://create.roblox.com/docs/parts/materials)
- [Textures and decals](https://create.roblox.com/docs/parts/textures-decals)

**DevForum:**
- [MaterialVariant tiling origin](https://devforum.roblox.com/t/more-control-over-materialvariant-tiling-origindirection/2203997)
- [Add classic studs (MaterialVariants)](https://devforum.roblox.com/t/how-to-add-classic-studs-to-parts-meshes-unions/3157449)
- [Stud texture vs Roblox studs](https://devforum.roblox.com/t/should-i-use-a-stud-texture-or-use-robloxs-studs/3109241)
- [HD stud materials](https://devforum.roblox.com/t/hd-upscaled-studs-from-2008-2022-using-materialservice/1911578)
- [Trendy stud texture](https://devforum.roblox.com/t/trendy-stud-texture/4876870)
- [Static UI performance](https://devforum.roblox.com/t/static-ui-performance-improvements/222557)
- [SurfaceGui.MaxDistance](https://devforum.roblox.com/t/new-surfaceguimaxdistance-property/2574715)

**Camera:**
- Popper's occlusion rule:
  [Roblox-Client-Tracker mirror of the shipped PlayerModule](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/scripts/PlayerScripts/StarterPlayerScripts/PlayerModule.module/CameraModule/ZoomController/Popper.lua)

**Roblox APIs (read 2026-11-16):**
- `apis.roblox.com/search-api/omni-search`
- `apis.roblox.com/toolbox-service/v1/marketplace/10`
- `…/items/details`
- `thumbnails.roblox.com`

**Architecture:**
- [Frame on RCH Melbourne](https://frameweb.com/article/the-royal-childrens-hospital-melbourne)
- [Büro North wayfinding via Dexigner](https://www.dexigner.com/news/24905)
- [Archello on Lady Cilento](https://archello.com/project/lady-cilento-childrens-hospital)
- [BDP on Alder Hey](https://www.bdp.com/design-stories/alder-hey)

**Emblems:**
- [ICRC](https://www.icrc.org/en/law-and-policy/use-emblems)
- [Canadian Red Cross](https://redcross.ca/about-us/about-the-canadian-red-cross/red-cross-emblem/it-may-just-be-a-game-to-you-but-it-means-the-world-to-us)
- [PC Gamer on Prison Architect](https://pcgamer.com/how-the-prison-architect-developers-broke-the-geneva-conventions)
- [NHTSA Star of Life](https://ems.gov/staroflife.html)
- [Federal Register 1994](https://www.govinfo.gov/content/pkg/FR-1994-08-11/html/94-19562.htm)
- [ISO 7010](https://www.wikipedia.org/wiki/ISO_7010)

**In this repo:**
- `docs/research/2026-11-16-art-direction.md`
- `docs/research/2026-11-16-creator-store-models.md`
- `docs/plan/2026-11-16-perf-budget.md`
- `.worktrees/progression/docs/plan/2026-11-16-progression-v2-build-plan.md`
- `game/src/server/PlotBuilder.luau`
- `.worktrees/progression/game/src/server/Patients.luau`
