# Creature Clinic: first Studio run (2026-11-16)

Who: Claude, through the Studio MCP on Joshua's PC (account JokingPuzzle), in **Play solo**. Code: branch
`claude/trusting-carson-5v32sr` after the merge of `claude/creature-clinic` (`a46bab5`), then fix `9b169d4`.
The patients and cures were driven by a script (teleport, prompt hold, treat), not by hand, so walking distances and
feel on a phone are still untested.

## Checklist (build plan §D)
| # | Result | Notes |
|---|---|---|
| 1 | ✅ | `[Main] Clinic is open.`, no red errors. 6 plots; got Plot 2; the sign reads "JokingPuzzle's Clinic". |
| 2 | ✅ | Patients queue within seconds. Make (hold) → carry → Treat → bed → cured → cash and ⭐. |
| 3 | ✅ | Wrong item: "Oops! This one needs 🧪". A full tray swaps: "🔄 🩹 ➜ 🧪". Patients whose patience ran out left. |
| 4 | ✅ | Bath Room unlock toast at ⭐10, bought, built in its slot, its station makes 🛁 Bubbles. Tray upgrade: CarryMax 1 → 2. |
| 5 | ✅ | NEW PAGE on first cures. Starter set → Heart Rug; Bath set → Duck Fountain. |
| 6 | ✅ | Heart Rug placed on `Stand:1`; still there after a restart. Unowned decor: "Buy it first!" |
| 7 | ✅ | Night: 22 lamps on, Moon Moth and Hiccup Ghost arrive and pay about 2×. Day Report pops (8 cured, ⭐+10, 📖+3, next: Cozy Ward) and closes itself after 8 s. |
| 8 | ◐ | `ForceWinter`: snow falls, a Frosty variant appeared. Winter Wing purchase correctly refused at ⭐29 ("Need ⭐40"). Not bought, so the Cocoa station is untested. |
| 9 | ✅ | Today's Visitor (Moss Mole) cured → `VisitorStatus` Done. Next day's visitor (Icicle Owl) needs the Winter Wing, so the chip hides (None). Goal claimed (+40, ⭐+2). Mailbox once a day; the next day it opens again. Second server, same day: not tested. |
| 10 | ✅ | ShySprout beat 1 on day 1; no second beat the same day; on the simulated next day (`UtcDay`+1) beat 2. |
| 11 | ⬜ | Needs two players (hearts, helpers, OpenHelpers). Do it with both brothers in a real test. |
| 12 | ✅ | Restart kept ⭐, cash, the Bath Room and the decor. Junk remote calls all rejected with a message. |

## Bugs found and fixed (`9b169d4`)
1. **Creature bodies stayed at the world origin.** Each patient's Root walked the queue, but its visible body sat
   ~280 studs away. Cause: `Root.CFrame` was set before the model was in Workspace, so the welds didn't carry the
   body, and each weld then locked in that gap. Fix: `model:PivotTo(start)`.
2. **HUD resize loop** ("Maximum event re-entrancy depth exceeded", `Hud.fitHeight`). Changing the scale re-fired
   AbsoluteSizeChanged. Fix: a guard, a deferred refit, and ignoring changes under 1%.

## Notes
- `ContentId rbxassetid://203785492 … Asset type does not match` (3×) also showed up in the old shop's first run.
  Nothing in the game uses it; probably Roblox's default avatar.
- Pace with an instant bot: 13 cures in 75 s. A kid walking between station and Counter will be much slower.
- The save carried a v1 Speed level (1.6 s hold) from the old shop data. Migration works.
- `ClaimGoal(2)` with one goal replies "Oops! Try again." The UI never asks for a goal that doesn't exist, so it's
  harmless.
- The test day switch wrote day 20774 into JokingPuzzle's save; `Schema.reconcile` pulls it back on the next load.

## Still to test
Item 11 and the edge cases with 2 players (a leaving owner, a 7th player, a DataStore failure); the phone emulator
(buttons, safe area, prompt reach); the Winter Wing and Cocoa; and whether it's **fun** for a real kid.
