# First session: declutter + tutorial (design)

**Why:** Joshua playtested the candy build (2026-11-16): "not bad but a little cluttered upon loading... there should
be a good tutorial too". The players are mostly young kids, often on a parent's iPad, who don't read walls of text. A
new player must understand the loop within about 90 seconds, and the first screen must be calm.

What Claude saw at load: you spawn **inside** the First-Aid Stand behind the Counter, so the camera wedges under the
awning; a patient's badge fills half the screen up close; and every HUD element shows at once (cash, stars, timer,
visitor chip, 🎵, ✨, 4 tabs, 2 empty tray slots).

## A. Declutter
1. **Spawn and camera.** Owners spawn on their plot's path **in front of** the Counter (the patients' side, off the
   queue line), facing the clinic, so the first view shows the stand, the stations and the patients. On a player's
   first-ever join only: a short (about 3 s) camera sweep over their clinic with a title card **"Welcome to Cure a
   Creature!"**, then the normal camera. Reduced motion: no sweep, just the card.
2. **Badges never balloon.** Patient badges (`IconGui`, `BubbleGui`) and station icons cap their on-screen size up
   close (`BillboardGui.DistanceLowerLimit` or an equivalent), so no badge covers more than a small part of the
   screen when you stand next to it.
3. **The HUD reveals itself (new players).** Driven by the tutorial step: at first only 💰 Cash. ⭐ Stars appears
   after the first cure. 🛒 Shop appears at the shop step, with a bounce. 📖 Book, 📬 Mail, 🎯 Goals, the timer and
   the visitor chip appear when the tutorial ends. Players who've finished the tutorial see everything at once, as
   today.
4. **One ⚙️ instead of 🎵 + ✨.** A single settings button opens a small panel with the music and calm-effects
   toggles (same behaviour, same attributes).
5. **Tray slots only when holding something.** Empty hands are hidden.
6. **Quiet during the tutorial:** no Mail popup, no Day Report, no Today's Visitor, and only tutorial-relevant
   toasts.

## B. Tutorial
**Server-authoritative step, saved.** A new save field `Tutorial` (a step number, with one value meaning done). The
schema migration marks existing players with `Cured > 0` as done. The step goes to the client in the State snapshot.
A new `server/Tutorial.luau` owns it and advances on real events: a make (Stations), a cure (Cure), a purchase
(Economy.Purchased), and one rate-limited remote, `TutorialAck`, that may only move past the welcome card.

| # | What the player sees (≤ 8 words, icon first) | Pointer | Done when |
|---|---|---|---|
| 1 | "👋 Welcome to your clinic, Doctor!" | none | tap, or 4 s |
| 2 | "🤧 A patient! The bubble shows what's wrong." | the first patient | 2 s after it reaches the Counter |
| 3 | "🧪 Hold at the potion table!" (+ "Hold E" / "Tap and hold" per device) | arrow to that station | they make the item |
| 4 | "🏥 Take it to the Counter. Treat!" | arrow to the Counter | they treat |
| 5 | "🛏️ Resting… Cured! 🎉" | the bed | the cure lands (+💰 +⭐, Stars pill appears) |
| 6 | "💪 Cure 2 more! (n/2)" | the usual Guide arrows | 2 more cures |
| 7 | "🛒 Spend 💰 in the Shop!" | the 🛒 button, then the cheapest upgrade | any purchase |
| 8 | "📖 Collect every creature in your Book!" | 📖 button | tap, or 5 s → done; then the welcome letter |

- **The tutorial patients:** the first is a guaranteed easy one (a Starter-wing patient needing the 🧪 Remedy); the
  second needs 🩹 so the player learns there's more than one station. Patience doesn't run out during steps 2–6.
- **Enough cash for step 7:** if the player can't afford the cheapest upgrade when step 7 starts, the tutorial gives a
  one-time top-up gift ("🎁 A gift to get you started!") so the purchase always works. Never Robux, never a pass.
- **No skip button** for new players (kids skip and then get lost). Players who already have progress never see it.
- **Studio test switch:** Workspace attribute `FreshSave = true` (set before Play, Studio only): players get a blank,
  in-memory save that is never written, to test the first session repeatedly without touching the real save.

## Kids' rules (red line 3)
Short lines, icon first; nothing timed against the player; no pressure to spend; every motion honours Reduced Motion
and the calm toggle.
