# Wide hospital: Studio run (2026-11-17, Claude via Studio MCP, FreshSave)

Joshua, after playing the look overhaul: "much better but the hospital is cramped. it should be wider. and a little
taller per storey else the head will be too near".

## What changed (branch `claude/wide-hospital`: `7f88293`, `0390d5e`, `af26994`)
- **Wider.** The building is x -16..16 (32 studs; was 23). Depth is unchanged (z -13..13).
- **Taller.** The ground storey is 12 (was 11), every upper storey 11 (was 9). Slab tops 12, 23, 34, 45. The clear height
  upstairs is 10.4 (was 8.4); the tallest patient seen in the run was 6.0.
- **Plots 70 -> 80** (`Config.Town.PlotSize`), so the side rooms keep their 18-wide slots and the patients' walkways
  sit 1.5 outside the side walls (x ±17.5). The town lays out from PlotSize and grew with it (belt ±135, Hall of Fame
  x -152..-190).
- **Roomier inside.**
  - Ward beds are about 3 studs apart (2.8 to 3.1; were 1): main ward x -6 / 1.5 / 9, front ward ±3.6 / ±10.8.
  - The stair lanes are 24 long (were 18), so the flights are shallower.
  - The Stand's stations and Bed_1 have about 3 studs between them.
  - The tub is smaller and pushed back, leaving a 2.3 pass.
- **Gameplay unchanged.** Same usable beds per level, same stations, same floors.
- **Decor slot 2 moved** from the porch to the front pad (-12.5, -22.5). It was on the patients' line to the walkway.
- **Part budget.** The heaviest Building is 158 of 160 parts. Only 2 parts of headroom are left, so the next building
  change needs a trim first.

Made by a 7-agent workflow (Fable on the foundation, integrator, 2 reviewers and the fixer). The reviewers found 8
issues; all were fixed (the ward aisles only as far as the fixed depth allows). 1450 Lune specs pass, lint is clean and
the rojo build works.

## Studio run
- Clean boot: `[Main] Clinic is open.`, no red errors (only the old 203785492 warning, not ours).
- Lv 2 (1) and Lv 5 (2, 3) build at the new size. The street, the plot, the ambulance and the First-Aid Stand annex
  don't overlap.
- The front ward on F1 (4): the beds, curtains and sleepers are spaced out, with clear headroom under F2's slab.
- Levelling 1 -> 5 through `LevelUp` worked; a helper cure and its Mail arrived while upstairs.

## Not checked by eye
- A patient's full walk up the lift to a ward bed and to the tub.
- Climbing every flight as a player.
- Phones (Device Simulator).
