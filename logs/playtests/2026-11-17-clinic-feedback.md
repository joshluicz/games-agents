# Clinic feedback batch: Studio check, 2026-11-17

Joshua played the Real Clinic and sent notes and screenshots. Six agents fixed them in `.worktrees/feedback`
(branch `claude/clinic-feedback`), merged by fast-forward at `207709d`. 1637 specs pass; stylua, selene and the Rojo
build are clean. Claude checked it in Studio over MCP. Captures are in `2026-11-17-clinic-feedback/`. **Not published.**

## Checked in Studio
- **Floor guide** (`1-arrow-on-strip.jpg`): the strip lies on the floor from the feet. The solid white arrows (dark
  green outline) sit centred on it and point toward the target, round the corner out of the supply alcove and along
  corridor A to bay 1.
- **Dispensary** (`2-dispensary-slip.jpg`): one medicine. The slip shows 📋, the patient's face, the big bottle and
  "Cough syrup". The Lv 1 shelf has 3 bottles (fever medicine, cough syrup glowing, ear drops), then the dose.
- **Stations** (`3-freezer-and-cabinet.jpg`): Ice is a white freezer chest with a cyan lid and ice cubes; Plaster is a
  pink cabinet with doors, knobs and a box of plasters.
- **Stairs** (`4-stairs.jpg`): tiled steps with a clean side wall; no slab, no stray panel.
- **Winter Wing** (`5-winter-wing.jpg`): a fireplace with snowflakes, a rug, the bed in the corner, the cocoa table to
  the side.
- **Patients sit first:** the tutorial patient reached bay 1 after its sit (the card waits for it).
- No errors in the log (`rbxassetid://203785492` isn't ours).

## Seen, still to fix
- The Cozy Ward's second bay sign showed blank from one angle (the first read "🛏️ 1"). The room is small enough that
  the test camera ended up inside a purple part. The rooms get rebuilt with the bigger building anyway.
- The dispensary card's title still opens with 💊; the UI batch puts titles in words (`memory-20261117-007`).
- The rooms and corridors are still small: the next batch (`memory-20261117-006`) makes the building about 1.5x
  bigger with a see-through-walls camera.

## Not checked by eye this time
The Bath Room, the stairs walked up and down, the purple flicker at corridor B and the door jambs, the glow on the
open shelf and the cast table, an ambulance patient going straight in, and the hop of the arrows with Reduce Motion
on.
