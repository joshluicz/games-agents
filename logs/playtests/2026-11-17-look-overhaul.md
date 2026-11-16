# Look overhaul: first Studio run (2026-11-17, Claude via Studio MCP, FreshSave)

The build is `541fbc5`: the look overhaul (foundation `6c708ae`, integration `d3c148d`, review fixes `5e80272`)
merged with the Market save fix (`3bf1fc3`). Before the run: lint clean, 1438 Lune specs passing, rojo build OK.
Screenshots are in `2026-11-17-look-overhaul/`.

## Why earlier captures were white
Studio was **minimised**. A minimised Studio stops drawing the 3D view; the GUI still draws. Restoring the window
fixed it. The screen being off was not the cause. Captures 1-9 were taken with the window restored.

## Passed (seen in captures)
- **Clean boot.** `[Main] Clinic is open.`, no red errors. The only warning is the old asset 203785492, which isn't ours.
- **Belt in the road's centre** (1). The Agency and Market kiosks sit at the plaza, and the odds board stands beside it.
- **Studs.** The lawns, plot pads and trees are studded, and the trees are blocky (1, 2).
- **Tutorial card.**
  - It reads "TUTORIAL n/7", with a title, a key chip, the progress segments and ⏭️ Skip.
  - The floor beam runs at hip height from the player, bends round the queue and goes in through the door to the
    potion station (3).
- **Skip.** It reveals the rails at once:
  - left rail: Shop, Nurses and Book;
  - right rail: Gifts, Goals and Mail;
  - top: the goal card;
  - top-right: the day status and the free Golden Hour countdown (allowed by `-022`).
  - The beam stays on after Skip, as designed (2).
- **Levels 1 to 5.**
  - Lv 2 is a two-storey clinic. Lv 5 is a tower with a lift tower, the paw-heart sign and an ambulance bay.
  - The wards have 3 working beds and 4 decorative ones.
- **Yay → Goals click-through: fixed.** Tapping 🎉 Yay! no longer opens Goals.
- **Panels.** They have a navy header, a red ✖ and the tab column (8).
- **Settings.**
  - ⚙️ Settings has 🔁 Replay tutorial (9), with a confirm: "Your waiting patients go home".
  - With FreshSave the server refuses it with "⚠️ Not saving right now", the same as rebirth. Correct.
- **Night** (7). The lamps glow, the windows are warm and the tower's sign lights up. The status turns to
  "🌙 ×2 · 2:50 left".
- **Admin RestartTutorial** brings back card 1/7. TutorialAck then moves to 2/7 with the beam.

## Found and fixed in this run
1. **Walls had no texture.**
   - The fallback studs only covered top faces, so walls looked plain, and Joshua's "they lack texture" stood.
   - Roblox's built-in Studs surface renders on side faces too, so `World/Studs` now studs the top and the four sides
     (the bottom stays smooth).
   - No assets are needed. The CureStuds MaterialVariant is now optional.
2. **The wards read as black from the street.**
   - The glass bands were the navy Window colour at 30% see-through, and each storey had no light.
   - Now:
     - every indoor storey and the hall has one shadowless room light on an Attachment (no parts);
     - the glass is the new `Palette.World.Glass` `#CDE8F5` at 55% see-through.
   - The beds and curtains now show from the street (4 before, 5 and 6 after).
3. **Boot warnings from DayNight.**
   - A game script can't write `LightingStyle` or `PrioritizeLightingQuality`.
   - The place file already has Soft and true, so DayNight now writes only values that differ, and warns only then.

After the fixes: lint clean, 1439 specs passing (a new room-light spec), and the Studio run is clean with no warnings.

## Still open
- **The beam has no arrow texture**: it's a plain purple ribbon. The chevron strip needs an uploaded image
  (plan §D I-2).
- **Phones were not checked in the Device Simulator.**
  - HudScreen.spec covers 12 sizes from 640×360 up, and the fixer handled 568×320.
  - A look on a real phone is still worth doing.
- **Not checked by eye:**
  - the Market with 2 players;
  - the lift ride and escort past the new solid walls;
  - triage and A&E arrivals;
  - Replay on a saving server.
- **Small polish:**
  - the ⚙️ plate is a low-contrast grey;
  - the Settings panel has empty space under its rows;
  - the "NEW! nurse" card briefly covers the wallet and the Shop button.
- **Decisions for the brothers** (from the integrator):
  - the First-Aid Stand icon (placeholder 🧰);
  - whether 🏥/🚑 count as cross emblems on some platforms;
  - Golden Hour's icon (🌟 in the status, 👑 on the belt).
