# Real Clinic (Update 2): first Studio run, 2026-11-17

Claude drove Studio over MCP; Joshua could watch. The build is the `real-clinic` workflow (14 agents, Fable 5.2 on the
foundation, integrator, reviewers and fixer), merged by fast-forward into `claude/trusting-carson-5v32sr` at
`4c81365`. Captures are in `2026-11-17-real-clinic/`. **Not published** (red line 4: both brothers say yes first).

## What was played
- **A fresh save through the tutorial:**
  - Patient 1 is a cough in bay 1. The exam offers 🔍 🌡️ 🩺, with the stethoscope glowing; you play Listen.
  - Then the dispensary: pick the bottle, fill the cup to the ⭐. Hand the syrup over at the bay: 💰24, ⭐1.
  - Patient 2 is a cut knee. You examine with 🔍 Look, take a 🩹 from the supply shelf and play Plaster at the bay:
    💰45, ⭐2. "Treat 3 more" follows.
- **Levels 1 to 5 from the street** (`1-street-lv1.jpg`, `2-street-lv5.jpg`):
  - Lv 1 is the 64 x 44 block, with front doors under the canopy.
  - Lv 2 adds the ambulance by the A&E side door.
  - Lv 3 adds a second ward storey.
  - Lv 5 has three storeys over the block and the helipad on the roof.
  - The plot holds 671 parts at Lv 5 with 8 patients in.
- **Inside** (`3-bays-inside.jpg`): bays 1-6 along the corridor, with patients on the beds and the waiting seats by
  the front glass.
- **The X-ray case at Lv 3** (`5`, `6`, `7`):
  - 📸 exam, then the scanner bar over the bone, which reveals a broken arm (plan: cast + pain relief).
  - Take a cast at the Cast Table, then the Cast game ("Tap to wrap!") at the X-ray bed.
  - Pain relief from the dispensary: the 🌼 bottle, then the dose.
- No server or client errors in the log on any run. (`rbxassetid://203785492` is not ours; it isn't in `src`.)

## Found and fixed (each with a spec)
1. **Blank X-ray card: Roblox can't draw some emoji** (`9-before-blank-xray-card.jpg`).
   - Every one of the 213 emoji in `src` was rendered in Studio. Six showed as empty boxes, and the game now uses a
     stand-in for each:
     - 🩻 → 📸
     - 🛗 → ↕️
     - 🪼 Jam Jelly → 🍓
     - 🪴 Resident Fern → 🌳
     - 🫧 Quick Soap → 🧼
     - ➜ → →
   - `tests/Emoji.spec` keeps them (plus 🩼 🫁) out of `src`. `80c78c4`.
2. **The tap spots in Listen, Look and Plaster overlapped.**
   - A spot is never smaller than the tap minimum, which is 37% of the face on a short card.
   - Spots are now spaced by their drawn size, over most of the face (`4-listen-spots-fixed.jpg`). `80c78c4`.
3. **The Cast Table's badge filled half the screen in the small X-ray room.**
   - New `Feel/NearIcons` hides a station's badge while the camera is within 7 studs. It comes back past 8.
     `273cf23`.
4. **A cast could not be taken.** At the Cast Table, Roblox showed another prompt on the same E key:
   - first the X-ray bay's;
   - then the Bandage shelf's, through the wall.

   Fixes:
   - Bay X's doctor now stands at the bed's side (`Building.BAYS` `Spot`), and nurses stand along the bed there.
   - A Building station's prompt hangs just off its front face (`Building.stationPromptAt`) and reaches 5 studs. It
     used to sit on the centre with a 10-stud reach.
   - Checked in Studio with the camera behind the player: Cast, Bandage, Plaster, Ice and the dispensary each show
     their own prompt.
   - Commits: `273cf23`, `be1b17f`, `d02e7e7`.
   - Note: Roblox picks among same-key prompts partly by where the camera looks, not only by distance.
5. **The dispensary's 2 x 2 bottles were clipped top and bottom.**
   - Pick targets now keep a 5 px inset, so their outlines show (`8-dispensary-bottles.jpg`). `195f14d`.

1602 specs pass; stylua and selene are clean.

## Still open (for the next run)
- **The broken arm's visit timing.**
  - The X-ray patient ran out of patience between the cast and the pain relief, but Claude's scripted steps were much
    slower than a player's.
  - Each step refills patience (`ITEM_PATIENCE`).
  - Check by hand: a real kid doing X-ray → cast → walk to the dispensary → back, within about 60 s of patience.
- **Not seen yet:**
  - a ward stay with the "Injury Ward or Rest Ward?" pick;
  - the lift;
  - the ambulance and helicopter arrivals;
  - night;
  - the Bath Room and the Winter Wing;
  - the Cozy Ward;
  - the phone-size Device Simulator;
  - two players.
- **Small:**
  - the tutorial banner still says "Tap the matching bottle!" during the measuring step;
  - the camera is cramped in the bays and the X-ray room (the camera presses against walls);
  - Listen, Look and Plaster all play as "tap the spots" (same engine, different skins). Worth more variety later.
- **The plot's forecourt is a big empty dark slab** at plot size 110. A car park, a garden or a path would read as
  more realistic.
- **Studio MCP quirk:** `execute_luau` puts the camera mode back to what it was when the call started. A call made
  during the tutorial's welcome sweep leaves the camera stuck on Scriptable. Either wait about 9 s after starting
  play, or reset it with `task.delay`.
