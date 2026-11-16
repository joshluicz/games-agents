# Progression v2: first Studio run (2026-11-17, Claude via Studio MCP, FreshSave)

The build is the merge `c9e4d1c`: Progression v2 plus its review fixes `867fb6c`. Before the run, lint was clean,
1000 Lune specs passed and the rojo build was OK.

## Passed (checked through remotes and state, not by eye)
- **Clean boot.** No red errors. The only warning is the old asset 203785492, which isn't ours.
- **Belt, Agency kiosk and Market kiosk:** all in the world.
- **Levels 1 → 5 through LevelUp:** Clinic → Hospital → Big Hospital → Mega Hospital, with the Lv 5 celebration.
  - The Lv 5 building holds Lobby, Floor_1-4, Landing_0, Stairs, Lift, Wards, Hydro, Pharmacy, AmbulanceBay and Roof.
- **Roster cap 3.** The 4th GiveNurse is refused with "Roster full: sell or list one".
- **Agency:**
  - The stock is 4 slots, and the odds are shown: Common 70, Rare 26, Epic 4.
  - Buying with a full roster is refused.
  - A sell with the wrong expected price returns "Price changed! Look again".
  - Selling Jam Jelly for 💰450 works, and the Pebble Penguin buy then works ("🎉 Hired Pebble Penguin!").
- **Rebirth.**
  - With FreshSave, OpenBranch is refused with "⚠️ Saving is off". That's correct: a rebirth needs saving.
  - The admin rebirth works:
    - Count 1, Level 1, Cash 50.
    - All 3 nurses kept.
    - 3 tree points, an offer of 3 perk cards, and theme Arctic.
- **Perk and tree:** ChoosePerk "BigHands" works ("🧺 Big Hands!"), and BuyNode NimbleFingers works (2 points left).
- **Roster after R1:** it grows to 4, and Toffee Fox is hired as the 4th.

## Found
- **Tapping "🎉 Yay!" on a celebration also opens 🎯 Goals.**
  - The Yay button sits over the bottom bar's Goals tab, and the same tap goes through.
  - It's fixed for good once the overhaul moves Goals to the right rail. Celebrate should also swallow that tap.
- **Lv 5 plot: 426 parts** (patients and nurses included). That's over the 400 budget. The overhaul rebuilds it.

## Not checked: the 3D view didn't render
Every capture showed the HUD on a white world, even with a clear camera view, while the screen was off. These need
a run with the screen on:
- the look of the floors, lift and wards;
- the lift ride and escort;
- triage and A&E;
- the keep/reset screen and BranchPanel;
- the Market with 2 players.
