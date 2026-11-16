# UX cohesion audit: why the screen feels segmented, and one system to fix it (2026-11-16)

Research only. No code changed and nothing here is ruled yet. Written by Claude for Joshua, from his feedback on the live
game today:
> "ux feels segmented and not cohesive" · "the colours are too bright" · "buttons are all at the bottom so the top
> feels bare. the layout doesnt seem methodical. feels empty... find the best practices and best uis."

**What I read:**
- every file in `game/src/client/UI` and `game/src/shared/Palette.luau`;
- every BillboardGui and SurfaceGui in `game/src/server` and `game/src/client`;
- the Progression v2 worktree (`.worktrees/progression`, branch `claude/progression-v2` at `e204207`): `Kit`, `Theme`,
  `Celebrate`, `Hud`, and the new `BranchPanel`, `AgencyPanel`, `MarketPanel` and `LiftPanel` (still a stub);
- Joshua's screenshots **[S11]** (the Journal panel), **[S12]** (the HUD on the street) and **[S13]** (a tutorial
  card);
- his description of a night screenshot **[S-night]** and of a trending "Steal a …" game he wants it to look like
  **[REF]** (no files for either).

**Rulings this touches:**
- **memory-20261116-007.** Saturated and flashy is Joshua's ruling. The candy-pop specifics were Claude's call.
  Calmer colours would supersede part of it, so it needs a new record with Joshua's yes.
- **memory-20261116-022.** Countdowns to free upcoming events are allowed again, and nothing paid gets a timer. The map
  gives them a slot.
- **First-session design §A3.** The HUD reveals itself step by step. The new map keeps that.

**`docs/research/2026-11-16-art-direction.md`** landed while I was writing. Its finding is that "too bright" means
over-exposed and milky, not too saturated: mean V 0.95, a third of the screen pale. Its §4.4–4.5 sets the UI and sign
values. §3.3–3.6 below use those values, and this doc covers only the layout and system around them.

---

## 0. In one paragraph

The game has a good shared kit (`Kit`, `Theme`, `Hud.modal`), but almost every piece gets its own colour, and pieces
copy the shell instead of using it. The result:
- the HUD is 14 differently coloured chips pushed into three corners and a bottom bar, with nothing at the top centre
  or in the middle band;
- every panel has a different header colour;
- tabs are painted by seven copies of the same function;
- there are about 20 corner radii and 6 stroke weights;
- a world billboard (the 🎲 ODDS chip) looks exactly like a HUD button and floats over everything.

The fix is a zone grid that top simulators already use:
- **left rail:** menus;
- **right rail:** rewards waiting;
- **top centre:** "now";
- **top right:** time, free events and status;
- **bottom centre:** only your hands.

On top of that comes one chrome, using the art-direction doc's values:
- white plates on the rails and flat white panels;
- one header colour for every panel;
- orange only for the one main action, green only for collecting.

Candy colour is kept for things that mean something: rewards, rarity, the news dot.

---

## 1. Why it feels segmented

Each finding lists the screenshot it shows in and the file:line behind it. Line numbers are on `main`
(`claude/trusting-carson-5v32sr` at `c8d6cff`). **v2** = the Progression v2 worktree.

### A. The HUD zones fight, and the top and middle are empty
| # | Finding | Where | Seen in |
|---|---|---|---|
| A1 | **Seven big tabs sit on the bottom edge**, 7 × 76 px + 6 gaps = 592 px. That's the only interactive cluster, and it's at the bottom. | `Hud.luau:1724-1733`, `:1729` | S12, S-night |
| A2 | **The top-left is a 210 × 312 column:** cash, stars, ⚠️/🏠 chips and the 🎁 button with its bar. Three different shapes stacked: a pill, a pill with a bar, a square with a bar. | `Hud.luau:1453-1457`, `:1668-1712` | S12, S-night |
| A3 | **The top-right is a 420 × 220 column:** boost chips, the clock and the visitor chip. | `Hud.luau:1550-1556` | S12, S-night |
| A4 | **⚙️ floats alone at mid-right**, `Position (1, -12, 0.5, 0)`, with no neighbour and no zone. | `Hud.luau:1917-1925` | S12, S13, S-night |
| A5 | **Top centre and the whole middle band are empty.** Toasts use the top centre, but they only pass through. When the screen is narrow they jump down under the wallet (`BELOW_WALLET_Y = 132`). | `Toasts.luau:44-46`, `:203-220` | S12, S-night |
| A6 | **Three systems compete for the top centre** with three looks: purple toast pills, colour ribbons with a shine, and BadgeBook's "cheer" card at y = 84 with its own rays. | `Toasts.luau:38`, `BadgeBook.luau:342-358` | — |
| A7 | **The bottom centre is a stack that keeps repositioning.** The hands ride above the tab bar or drop when it hides (`Hud.luau:1909`). The tutorial card sits on top of both and "follows the HUD's layout every frame" (`Tutorial.luau` header, `:297`). | `Hud.luau:1909`, `Tutorial.luau:293-300` | S13 |
| A8 | **Panels open with the whole HUD still showing around them.** Wallet, 🎁, clock, visitor and ⚙️ stay up, and the tab bar peeks under the panel's bottom edge. | `Hud.modal` hides nothing | S11 |

### B. Competing colours: everything is a different saturated colour
| # | Finding | Where | Seen in |
|---|---|---|---|
| B1 | **Each tab is its own candy colour.** Pink, purple, blue, lime, cyan, orange and yellow make a rainbow strip with no primary. | `Hud.luau:151-159` | S12, S-night |
| B2 | **The HUD chips are five more colours:** yellow cash, a yellow-to-orange stars gradient, an orange/purple clock, a pink/lime visitor and a pink gift. Each one has a candy gradient and a gloss. | `Hud.luau:1019-1046` (`pill`), `:1501`, `:1581`, `:1611`, `:1674` | S12 |
| B3 | **Every panel header is a different colour:** Shop pink, Book purple, Mail blue, Goals lime, Nurses cyan, Badges orange, Top yellow, Settings cyan, Odds purple, Day Report orange, Admin purple. The header takes "the colour of the HUD button that opens it" (`Hud.luau:357`, `tabColor` `:162`). v2 adds Branch purple, Agency cyan, Agency odds purple and Market orange. | `Shop.luau:36`, `BookPanel.luau:29`, `NursePanel.luau:52`, `Mailbox.luau:37-38`, `BadgeBook.luau:33`, `DayReportPanel.luau:30`, `AdminPanel.luau:34`, `Hud.luau:1930`, `BeltView.luau:481`; v2 `BranchPanel.luau:540`, `AgencyPanel.luau:376`, `:553`, `MarketPanel.luau:38` | S11 (cyan) |
| B4 | **Rows inside panels cycle colours too.** "Each row's icon tile takes the next candy colour, so a page reads as a bright stack" (Shop). Goals does the same. | `Shop.luau` header, `Mailbox.luau` header | — |
| B5 | **The world competes with the UI:** neon-green grass, pink/cyan plot accents, `LightInfluence = 0` on most signs (they glow at night), and Neon parts. | `Palette.luau:38-57`; `PlotBuilder.luau:387`, `:721`, `:1043`, `:1732`; `NurseBelt.luau:597` | S12, S13 |
| B5b | **Panels are near-white on near-white:** a white-to-ice paper gradient with `Card (238,244,255)` on it, so the card image wells read as dull grey. This is art-direction §3 #11. | `Theme.luau:15-17`, `Kit.luau:566-569` | S11 |
| B6 | **Too much perpetual motion:** shine sweeps every 3.5 s on calls to action (8 files), breathing (5 files), turning rays (10 files), and every red dot hops every 2.6 s. Roblox's own guidance: "Excessive use of bright, moving elements might overwhelm and confuse players." | `Theme.luau:97`, `:104`; `grep Kit.shine/breathing/rays` | S12 (two "!" dots and a green OPEN!) |

### C. Mixed shapes, sizes, radii and strokes
| # | Finding | Where | Seen in |
|---|---|---|---|
| C1 | **About 20 different corner radii.** The tokens are 16 and 24, but the code also uses 3, 6, 7, 8, 9, 10, 12, 13, 14, 15, 17, 18, 20, 21, 22, 26, 27, 30, 38, 40, plus scale radii 0.06, 0.35, 0.4 and 0.5. NursePanel alone uses ten. | `grep "Kit.corner("` | S11 |
| C2 | **Six stroke weights:** 2, 2.5, 3, 4, 6 (BadgeBook) and 8 (Tutorial). The world's odds sign uses a **white** 6 px rim, where everything else has a dark ink outline. | `NurseBelt.luau:608-609` | S12 |
| C3 | **Text below the game's own 18 px floor.** `Theme.TextSize.Small = 18` is "the minimum for anything a player must read". There are 12 private `textLimit` copies, and their `MinTextSize` values are 9 (BeltView, NursePanel), 10 (BookPanel, MiniGames), 12 (most) and 14 (Toasts, Celebrate). | `BeltView.luau:302`, `NursePanel.luau:215`, `BookPanel.luau:79`, `MiniGames.luau:373`, `Toasts.luau:191`, `Celebrate.luau:200`, `Shop.luau:195`, `Mailbox.luau:45`, `PlayGifts.luau:41`, `DayReportPanel.luau:39`, `Boards.luau:54`, `BadgeBook.luau:42`, `AdminPanel.luau:113`, `Hud.luau:1069` | S11 (small grey captions) |
| C4 | **No size hierarchy on the HUD.** The cash pill is 52 tall, stars 56, gift 70, tabs 76, clock 52, visitor 56 and gear 56. Everything is roughly the same weight, so nothing reads as most important. | `Hud.luau:1468`, `:1506`, `:1586`, `:1616`, `:1681`, `Theme.luau:66` | S12 |
| C5 | **Tilted stickers add more floating pieces:** the 🔥 combo sticker (`Rotation = 8`), the ×2 night sticker (`-10`), NEW! stickers, and (v2) 🃏/🌳 glyph dots. | `Hud.luau:1478-1495`, `:1591-1608`; v2 `Kit.setDot(glyph)` | S-night (×2) |

### D. One kit, many shells: copies instead of shared parts
| # | Finding | Where |
|---|---|---|
| D1 | **`paintTab` is pasted into 5 files** on main, and v2 adds 2 more copies. BadgeBook's copy differs, and so does Agency's. | `Shop.luau:178`, `BookPanel.luau:99`, `NursePanel.luau:256`, `Boards.luau:68`, `BadgeBook.luau:141`; v2 `BranchPanel.luau:603`, `AgencyPanel.luau:439` |
| D2 | **Two tab layouts:** a vertical column (Shop, Book, Nurses, Top, Branch) and a horizontal row (Badges, Agency). The Journal has **both**: an on-duty chip strip across the top and a rarity column down the left, in two different chip styles. | `BadgeBook.luau:106-111`; `NursePanel.luau:417-428`, `:477-480`; S11 |
| D3 | **MiniGames hand-builds a second copy of `Hud.modal`** (dim, shadow, card, header, foot, line) with its own `new()` helper. | `MiniGames.luau:502-580` |
| D4 | **Other surfaces each have their own frame:** Celebrate (`Celebrate.luau:206`), the tutorial card (white, no header: `Tutorial.luau:293-321`), the cheer banner (`BadgeBook.luau:342`) and toasts (purple pills: `Toasts.luau:38`). | S13 |
| D5 | **Confirm dialogs are built three times in v2**, each with its own buttons: Agency `:449`, Market `:508` and Branch reset `:1637`. | v2 |
| D6 | **Two ProximityPrompt looks.** Station prompts use Roblox's default grey prompt ("E Make"). The belt's Hire prompt uses `Style = Custom` drawn by the card. | `BeltView.luau:1385`; S13 |
| D7 | **Ten button "Kinds" are colours, not roles:** Primary is orange, and then there are Secondary, Good, Danger, Pink, Purple, Cyan, Cash, Quiet and Card. AdminPanel uses all ten. | `Kit.luau:179-190`, `AdminPanel.luau` |

### E. World vs screen: the ODDS button floating over the world
| # | Finding | Where | Seen in |
|---|---|---|---|
| E1 | **The 🎲 ODDS chip is a world BillboardGui built as a HUD button:** `AlwaysOnTop = true`, a fixed `170 × 60` px offset size (it doesn't shrink with distance) and a purple Kit button 56 px tall. From the spawn it sits at the top centre of the screen above the horizon, looking like the game's only top-centre HUD button. | `BeltView.luau:697-725` (`:700`, `:705`, `:711`) | S12 (top centre), S11 (pokes above the Journal) |
| E2 | **The odds are on the world sign** (`NurseBelt.luau` OddsGui), and the chip duplicates them in a different style. | `NurseBelt.luau:584-611` | S12 (the pink board) |
| E3 | **The other world UI is done right:** patient badges, station icons, price badges, nurse tags and carry bubbles are sized in studs, with `DistanceLowerLimit` and `MaxDistance`. Only E1 breaks the rule. | `CreatureBuilder.luau:1692-1700`, `PlotBuilder.luau:383-390`, `:952-960`, `Nurses.luau:366-372`, `Carry.luau:213-222` | S12 |

### F. Hierarchy and legibility
| # | Finding | Where | Seen in |
|---|---|---|---|
| F1 | **The visitor chip has no words:** a ✓ and a creature face. Joshua himself described it as "a green ✓ pill with a nurse face", so a child won't read it either. | `Hud.luau:1611-1640` | S12, S-night |
| F2 | **The clock says "5:46" and not what it counts to.** Is it night in 5:46, or day? A ×2 sticker appears only at night. | `Hud.luau:1581-1608`, `:2133` | S12, S-night |
| F3 | **"HOLD E" in the tutorial card looks like a tappable blue candy button but isn't.** That's a false affordance for children. | `Tutorial.luau:353-366` | S13 |
| F4 | **The Journal header holds three different shapes:** an outlined title, a white "📔 6%" pill with a yellow edge, and a red square ✖. Below them, a strip of tab-like chips that aren't tabs. | `NursePanel.luau:371-403`, `:417` | S11 |
| F5 | **No single primary per view.** Every chip is loud, so the call to action (OPEN!, the Shop dot) doesn't stand out. | — | S12 |

---

## 2. What the top Roblox games do (sources dated, fetched 2026-11-16)

**Which games are on top.**
- By peak concurrent players, Q1 2026: Brookhaven, Blox Fruits, Adopt Me!, Grow a Garden, Escape Tsunami for
  Brainrots, Pet Simulator 99, Jujutsu Shenanigans, RIVALS, Fish It! and BedWars (ejaw.net/roblox-charts, 16 Mar 2026,
  citing RoMonitor Stats and Rolimon's; rounded figures).
- Steal a Brainrot is "consistently active" (games.gg, 14 Dec 2025).
- Steal a Brainrot ran at 86,104 concurrent players in the week of 26 Oct–1 Nov 2026 (rowatcher.com, week 44).

**HUD layouts.**
- **V** = I fetched the page myself.
- **R** = from the research pass: the page was fetched, but by the sub-agent, not me.
- The per-game detail comes from third-party guides (allthings.how and others), which describe screen positions in
  words. Nobody here could view the games' screenshots.

| Game | Currency | Menu buttons | Panels | World vs screen | Source |
|---|---|---|---|---|---|
| **Steal a Brainrot** | Bottom-left cash counter (R) | **Left rail:** "Four square buttons run down the left edge in this order: Shop, Rebirth, Index and Codes" (V) | Centred, titled, tabs as "the column on the left side of the panel", a counter top-right, "the red X in its top-right corner" (V) | "Floating belt tags" over each rider (V). Boards above the belt (R) | allthings.how/?p=329377, updated 5 Nov 2026 (V); ?p=328991, 5 Nov 2026 (R) |
| **Scare Your Neighbor** (new 2026 hit on the same template) | "Three counters run along the bottom left" | "menus sit on the left edge, and quick buttons sit on the right". Hotbar at the bottom centre. | n/s | n/s | allthings.how/scare-your-neighbor-starter-guide-roblox, updated 6 Nov 2026 (V) |
| **Grow a Garden** | "Your money sits in the bottom-left corner" | **Top centre:** "The top bar holds three teleport buttons, SEEDS, GARDEN and SELL" | The shop header "has an 'Odds' button" (odds at the point of purchase). "Close the shop with its X." | NPC stalls with prompts. "A tutorial banner at the top tells you what to do next." | allthings.how/?p=330478, 7 Nov 2026 (V) |
| **Pet Simulator 99** | n/s | Bottom plus both sides. Update 61 "Added quests to the main interface on the right side". | n/s | n/s | biggames.io update 61, 24 May 2025 (R) |
| **Blox Fruits** | Bottom-left $ | One collapsible bottom-left "Menu" button | n/s | n/s | allthings.how/?p=323324, 2 Nov 2026 (R) |
| **Adopt Me!** | Disputed | "orange task icons on the left side", teleport buttons on the left | n/s | An event board in the plaza | earnaldo.com adopt-me beginner guide, 5 Jul 2026 (R) |
| **Restaurant Tycoon 3** (closest genre) | n/s | "Tap the Shop button along the bottom of the screen" | n/s | n/s | allthings.how/?p=38155, 12 Jun 2026 (R) |
| **Sell a Million Sushi** (staff tycoon) | "Your cash total sits at the top of the HUD" | Index and paid options on the left side | n/s | Hiring pads and an "Employees board on the dock" | allthings.how/?p=325331, 4 Nov 2026 (R) |
| **[REF]** Joshua's "Steal a …" screenshot (his description) | Stacked on the left edge, mid-to-low. Icon plus a big outlined number. **No pills.** | n/s | The tutorial card is **top centre**: dark navy, a "TUTORIAL 1/9" tab, a progress bar | Big outlined text floating with no boards ("RAREST PULL", "+7/step", "Stand here to collect"). Night shown small at the bottom-right. | Joshua, 2026-11-16 |

**Roblox's own guidance (Creator Hub, fetched 2026-11-16; no "last updated" date on these pages).**
- **Touch corners.** "On mobile devices, the default controls occupy a portion of the bottom-left and bottom-right
  corners of the screen." Also: "Most mobile players use two thumbs — one on the virtual thumbstick and one on the jump
  button." It recommends custom buttons "near frequently-used controls like the default jump button" (V). And:
  "A button placed 40% below the screen's top edge is reachable on a phone but almost unreachable on a tablet" (V).
  Source: create.roblox.com/docs/ui/position-and-size.
- **Where things go.** Information about "how to win the game" goes "near the top". The sides suit "peripheral
  information" players glance at. "Place interactive elements in easy-to-reach zones near the natural resting position
  for thumbs." "Group UI elements from the same category together." "Display UI elements contextually." "Aim for balance
  and symmetry in the amount and size of your custom UI elements" (V). Source:
  create.roblox.com/docs/tutorials/curriculums/user-interface-design/wireframe-your-layouts.
- **Consistency and colour.** "Whatever decisions a UI designer makes, they should consistently apply them throughout
  the game." "An X symbol on a button that closes the dialog" is a convention players know. "Excessive use of bright,
  moving elements might overwhelm and confuse players." The colour advice, as summarised by the fetch tool: vivid hues
  for key text and buttons, muted shades for less important elements, bright colours with restraint, and colours with a
  consistent meaning (V). Source: create.roblox.com/docs/production/game-design/ui-ux-design.
- **Small screens.** "Move less-important buttons into a collapsible menu" (R). Source:
  create.roblox.com/docs/production/publishing/adaptive-design.
- **ScreenInsets.** `CoreUISafeInsets` keeps UI "clear of the top bar buttons". A ScreenGui set to `TopbarSafeInsets`
  "will automatically flex in horizontal size based on the top bar's content", so game UI can sit in the top-bar row
  (R). Source: create.roblox.com/docs/ui/on-screen-containers.
- **Top bar height.** The reserved top bar grew "from a height of 36 pixels to 58 pixels". The same post: "The right
  side has better ergonomics for frequently used actions… while your left thumb remains on the joystick" (R). Source:
  devforum.roblox.com/t/2567355, a Roblox staff post created 2023-08-28. Read `GuiService.TopbarInset` rather than
  hard-coding either number.
- **Paid random items.** Show "all possible outcomes and the actual numerical odds", visible "prior to purchase". "A
  standalone symbol like the (i) icon without a descriptive word is not sufficient" (R). Source:
  create.roblox.com/docs/production/monetization/paid-random-items.
- **Epic, "Designing for mobile in Fortnite".** "Information like maps, timers, and scores belong at the top center, or
  should be collapsible" (search excerpt). Source: dev.epicgames.com/documentation/fortnite/designing-for-mobile-in-fortnite.

**What most top games share.** The research pass's patterns, with my reading:
1. **Menus are a vertical rail of square icon buttons on the left edge, usually 3–5.** Steal a Brainrot, Scare Your
   Neighbor, Adopt Me and Sell a Million Sushi do this. The exceptions put them at the bottom (Restaurant Tycoon 3, Pet
   Sim 99) or behind one menu button (Blox Fruits). None of the documented games has 7 equal tabs.
2. **Quick or reward buttons go on the right** (Scare Your Neighbor; Pet Sim 99's quests). This matches Roblox staff:
   the right thumb is the free one.
3. **The top centre is for "now":** the tutorial banner (Grow a Garden, [REF]), the round theme with its timer (Dress to
   Impress, R), or navigation (Grow a Garden).
4. **Currency is a read-only counter on the left edge.** Bottom-left is common: Steal a Brainrot, Grow a Garden, Blox
   Fruits, Scare Your Neighbor. Roblox says to keep the touch corners clear, and these counters break that only because
   they're read-only.
5. **One panel template:** centred, a titled header, tabs as a column inside, and a red ✖ top-right.
6. **The world carries the world's information:** floating tags over belt items, boards over the belt, stalls with
   prompts. Odds sit at the point of purchase (Grow a Garden's header "Odds" button).

---

## 3. A unified system

### 3.1 The HUD zone map

**The rules.**
1. **Every HUD piece belongs to exactly one zone.** A zone has one job, one alignment and one look.
2. **Slots are fixed.** A piece that isn't revealed yet (first-session §A3) leaves its slot empty, so nothing ever jumps
   to a new place.
3. **Interactive pieces go where thumbs rest:** the two side rails at mid-height. Read-only pieces go where eyes go
   first: the top.
4. **The centre of the screen and both bottom corners are never HUD.** The centre is the world. The bottom corners are
   the thumbstick and jump on touch. They stay clear on desktop too, so every device shares one layout.

**The zones.**
| Zone | Holds | Never holds | Why |
|---|---|---|---|
| **System**: the Roblox top-bar row, right of Roblox's buttons (`ScreenInsets = TopbarSafeInsets`) | ⚙️ Settings. On phones it opens **⚙️ More**, which also holds 🏅 Badges and 🏆 Top. On phones the wallet joins this row too (below). | anything that changes often | System controls sit beside Roblox's own (Grow a Garden and Bee Swarm put their cog top-left, R). This fixes A4. |
| **Wallet**: the left column, top | 💰 cash and ⭐ stars, each as an icon plus a big outlined number with **no pill** ([REF]). ⭐ keeps its thin bar and next-unlock icon and stays tappable ("what's next"). | other buttons | The most-glanced spot, and where it is today, so nothing to relearn. It stays out of the touch corner. Fixes A2, B2. |
| **Now**: top centre | **one** card, highest priority first: ⚠️ Not saving / 🏠 Clinics full → the tutorial step ("TUTORIAL 3/8", a line, a bar: [REF]) → a tracked goal ("🎯 Cure 5 · 3/5", tap opens Goals). Hidden when empty. Toasts and banners drop in **under** it, one stack in one style. | buttons kids must hit fast (the top is the hardest reach) | Top games and Roblox both use the top centre for the objective. Fixes A5, A6, A7. |
| **Status**: top right, right-aligned column | row 1: day or night **with words** ("🌙 in 3:27", "🌙 ×2 · 2:08 left"). Row 2: **the next free event, one chip** ("👑 Golden Hour in 12m", "🎉 Update Sat 5pm", "🛠️ Admin event in 2h"), per memory-022. Row 3: Today's Visitor with a label ("Visitor ✅"). Row 4: boosts, at most 3 small chips. | **a timer on anything paid** (red line 3), red or flashing countdowns | Timers and scores go at the top (Epic). It's read-only and where the clock already is. Fixes F1, F2, and gives -022 its slot. |
| **Left rail**: left edge, middle band, vertical | **menus you browse:** 🛒 Shop · 👩‍⚕️ Nurses · 📖 Book, then on desktop and tablet 🏅 Badges · 🏆 Top | rewards, status | The top-sim consensus: Steal a Brainrot's four square buttons down the left edge. Fixes A1. |
| **Right rail**: right edge, middle band, vertical | **rewards waiting for you:** 🎁 Gifts · 🎯 Goals · 📬 Mail. These are the buttons that carry dots most often. | menus | "Quick buttons sit on the right" (Scare Your Neighbor), Pet Sim 99's quests on the right, and Roblox staff on the free right thumb. 🎁 moves here from under the wallet. |
| **Centre** | the world. When open: panels, popups, the mini-game card, celebrations. | anything permanent | — |
| **Bottom centre** | your hands (the carry tray) and the prompt for whatever you're next to | menus, tutorial | Fixes A7. |
| **Bottom corners** | nothing | everything | Roblox's touch controls. |

**Where each of the seven tabs goes.**
| Today (bottom bar) | Moves to | Note |
|---|---|---|
| 🛒 Shop | left rail, slot 1 | It already holds 🏥 Hospital, and in v2 🏢 Branch too |
| 📖 Book | left rail, slot 3 | |
| 📬 Mail | right rail, slot 3 | The letter still pops up by itself once a session |
| 🎯 Goals | right rail, slot 2 | |
| 👩‍⚕️ Nurses | left rail, slot 2 | In v2 it also holds the Journal, Team, Agency and Market |
| 🏅 Badges | left rail, slot 4 (desktop and tablet) · ⚙️ More (phone) | Tier-ups celebrate by themselves, so it's rarely needed |
| 🏆 Top | left rail, slot 5 (desktop and tablet) · ⚙️ More (phone) | The world's leaderboard boards (BoardBuilder) also show it |
| 🎁 Gifts (under the wallet) | right rail, slot 1 | It has the most "ready" dots |

**Desktop and tablet** (drawn at 1280 × 720 logical; any safe height of 440 px or more):
```
+----------------------------------------------------------------------------------+
| (R)(=)(chat) [SET]            <- Roblox top-bar row (58 px): SYSTEM slot         |
| $ 10,651                  +--------------- NOW ---------------+   (moon) in 3:27 |
| * 143 [=====---] (next)   | TUTORIAL 3/8                      |   GOLDEN HR  12m |
|                           | Hold at the potion table!  [===-] |   Visitor  (ok)  |
|                           +-----------------------------------+   [boost][boost] |
|                              ( toasts and banners drop here )                    |
| +------+                                                               +------+  |
| | SHOP |                                                               | GIFT |  |
| +------+                                                               +------+  |
| | NURS |                                                               | GOAL |  |
| +------+                  WORLD: the centre stays clear                +------+  |
| | BOOK |                                                               | MAIL |  |
| +------+                                                               +------+  |
| | BADG |                                                                         |
| +------+                                                                         |
| | TOP  |                                                                         |
| +------+                    [potion x] [plaster x]  <- hands                     |
|                                                                                  |
+----------------------------------------------------------------------------------+
   LEFT RAIL = menus you browse                   RIGHT RAIL = rewards waiting
```

**Phone** (drawn at 844 × 390; any safe height under 440 px):
```
+------------------------------------------------------------------------+
| (R)(=)(chat)[SET] $ 10,651  * 143 [==-]            (moon) in 3:27  Vis |
|                   +------------- NOW -------------+         GOLDEN 12m |
|                   | TUTORIAL 3/8  Hold at potion! |                    |
|                   +-------------------------------+                    |
| [SHOP]                                                         [GIFT]  |
| [NURS]                      WORLD                              [GOAL]  |
| [BOOK]                                                         [MAIL]  |
|  (thumbstick)          [potion x] [plaster x]           (jump)         |
+------------------------------------------------------------------------+
```

**Why the phone layout differs, and the numbers behind it.**
- On a phone the wallet moves into the top-bar row, and 🏅 and 🏆 move into ⚙️ More. The skill's rule is "design an
  explicit narrow arrangement instead of shrinking the desktop panel".
- **The rail band** runs from the top bar + 8 px down to 110 px above the bottom edge. Inside it a rail button is
  56 px, the project's tap minimum.
- 110 px is an assumption: the HUD's own note says the jump button and thumbstick sit about 95–100 px in from the edges
  (`Hud.luau:2101-2102`). Measure it in Device Simulator.

| Screen (landscape, logical px) | Band height | Rail buttons per side at 56 + 8 gap |
|---|---|---|
| 800 × 360 (a common Android size) | 360 − 58 − 8 − 110 = **184** | **3** (3 × 56 + 2 × 8 = 184) |
| 667 × 375 (iPhone SE size) | **199** | 3 |
| 844 × 390 | **214** | 3 (4 would need 248) |
| 932 × 430 | **254** | 4 |
| 1280 × 720 window | about 430 under the wallet | 5 at 72 px (5 × 72 + 4 × 10 = 400) |

The left column can't hold both a wallet and three 56 px buttons on a 360-px-tall phone: 74 px of wallet plus 184 px
of rail is more than the band. So on phones the wallet goes up into the top-bar row.

The [REF] game stacks its currencies mid-to-low on the left. Ours sit above the rail instead, for two reasons: a tablet
thumbstick covers the low left, and Joshua said the top feels bare.

**When things open.**
- **A Panel opens:** the rails, Now and Status fade out. The wallet stays, so you watch cash change while shopping.
  Fixes A8.
- **A Popup** (confirm, odds) opens over its panel.
- **The mini-game card:** only the wallet stays.
- **Celebrate:** everything hides.
- **The Day Report** stays a no-dim popup, so play goes on around it.

**First session** (§A3, unchanged in spirit; it only gets fixed slots):
1. 💰 first.
2. ⭐ after the first cure.
3. 🛒 fades into left slot 1 at the shop step.
4. 📖 into slot 3 at the Book step. Slot 2 stays empty until then.
5. Everything else, plus Status, when the tutorial ends.
6. The tutorial card always sits in Now. Its pointer arrows now point sideways at the rails, not down.

### 3.2 One modal template

```
+------------------------------------------------------------------+
| [icon] TITLE (two words max)                [meta chip]   [ X ] |  header 64: one blue band
+---------+--------------------------------------------------------+
| [ TAB ] |  section line: name . progress bar . reward            |
| [*TAB*] |  +--------+  +--------+  +--------+  +--------+        |
| [ TAB ] |  |  card  |  |  card  |  |  card  |  |  card  |        |  body: paper, scrolls
| [ TAB ] |  +--------+  +--------+  +--------+  +--------+        |
|         |                                                        |
+---------+--------------------------------------------------------+
| footer (optional): "your bar" or ONE primary action              |
+------------------------------------------------------------------+
```

- **Shell.** Always `Hud.modal`: centred, 94 % of the safe area, at most 600 × 640, one shadow token.
  - MiniGames, the tutorial card, toasts and Celebrate use the same tokens for corner, stroke, shadow and header.
  - Celebrate stays loud inside the shell (§3.5).
- **Header.** 64 px. The **same band on every panel**: the art-direction doc's `#1F8FE5`, with a white title and a
  3 px `#1B1238` stroke. That follows Steal a Brainrot's single panel look.
  - The dark navy of [REF]'s tutorial card (`#1E2440`, the art doc's odds-plate colour) is kept for the HUD's Now card.
    It's the HUD's one dark element.
  - Contents: the icon and a title of at most two words in the display font; **one** meta chip slot (a white chip,
    ink text: "📔 6%", "💰 726"); the red ✖ at 56 × 56, top-right.
  - Red stays on the ✖ because that's the convention ("the red X in its top-right corner"). It's the only red on the
    chrome.
  - A panel is told apart by its icon and title, not its colour.
- **Tabs.** One pattern: a **left column of square tabs**, as today, because landscape phones are short.
  - Unselected: card fill `#EEF3FA`, ink caption.
  - Selected: header-blue fill, white outlined caption, 3 px outline.
  - A section's own colour (a wing, a rarity, a board) is only a **6 px stripe** on the tab's left edge.
  - Badges and Agency move from a row to the column, so every panel tabs the same way.
  - The Journal's on-duty strip becomes a "Team" row of cards at the top of the body, not tab-lookalike chips (fixes D2
    and F4).
- **Body.** A flat white panel (`#FFFFFF`, the ice gradient dropped) with cards on it (`#EEF3FA`, 2 px `#C3D0E6`).
  Card anatomy:
  - a tile (image well `#D6E3F5`, medium radius, emoji or portrait; unseen silhouettes `#6A5FA0`; a rarity frame only
    here);
  - a name (display font, 22);
  - one info line (body font, 18);
  - one action: a Primary or Secondary button, or a status word.
- **Popups.**
  - `Hud.confirm(ctx, { Title, Line, Yes, No })`: the same shell at 420 × 360. "Not now" is the default focus, and a
    hold button is used for big moves. This replaces Agency's, Market's and Branch's own confirms (D5).
  - `Hud.oddsPopup` is shared by the belt, the Agency and the Journal.

### 3.3 Button hierarchy

Roles first, then colours. The colour values are the art-direction doc's §4.5. Gloss, outlines and the press bounce
stay on every candy button (memory-007's "flashy").

| Role | Look | Rule | Replaces Kinds |
|---|---|---|---|
| **Primary** | Orange `#FF9A1F`→`#F27A0C`, 3 px `#1B1238` outline, gloss, white outlined display text, 56 px | **One per view**, the main action: Buy, Hire, Level up, List it. **Never shines or breathes**, because nothing loud points at spending (red line 3). | Primary |
| **Collect** | Green `#45CF3A`→`#2BA52A`, same build | Taking something free: Claim, Open!, Yay!, ✅ Take it. The **only** role that may shine or breathe, and only while the reward waits. | Good |
| **Secondary** | `#DFE6F2` fill, ink `#2A2150` text, 2 px `#1B1238` stroke, no outlined text (the art doc's "Quiet") | Every other action: Equip, Place, View, Not now | Secondary (blue), Pink, Purple, Cyan, Cash |
| **Quiet** | No fill, no outline, ink body text, optional "›" | Links and tertiary actions: "See odds", "What's next?" | Card (as a button) |
| **Destructive** | `#FF4459`→`#D9283F`, white outlined text, always behind a confirm or a hold | Sell, Reset tree, Throw away (the ✖ on a carried item) | Danger |
| **Icon** | A square plate: **white with a 3 px `#1B1238` outline** for rails and HUD buttons (the art doc's "white with a dark stroke" option for the bar), or **dark glass** in the top-bar row (⚙️, matching Roblox's own buttons). Emoji at 60 %, an optional caption, a red dot top-right. | One plate for every HUD button. Identity comes from the icon, never the fill. | iconButton's `Kind` |
| **Close** | The Icon role with the Destructive red and a white ✖ | Only in the modal header | — |
| **Disabled / gated** | `#B3B6C9`, text `#6E7190`, plus a gate chip ("🏥 Lv 3") | No lock teases on paid items | — |

The news dot is one red dot. It pops in once when it appears, then stays still (no 2.6 s hop loop). v2's 🃏/🌳 glyph
dots keep the same red disc.

### 3.4 Tokens (Theme)

| Token | Values | Replaces |
|---|---|---|
| **Space** | 4 · 8 · 12 · 16 · 24 · 32. `Gap` = 8 (lists), `Pad` = 12 (cards) / 16 (panels), `Margin` = 16 desktop / 8 phone | Pad 12, Gap 10, Margin 12, and ad-hoc 3/6/10 |
| **Radius** | `Small` 8 (chips, bars, small tiles) · `Medium` 14 (buttons, cards, tabs) · `Large` 22 (panels, the Now card, toasts) · `Round` 0.5 scale (dots, portraits) | ~20 literals (C1) |
| **Stroke** | `Fine` 2 (cards, in `#C3D0E6`; tiles, chips) · `Bold` 3 (buttons, HUD plates) · `Panel` 4 (panels, as in the art doc) · text 2.5 (labels on colour) / 3 (HUD numbers, titles). All dark strokes `#1B1238`. | 2, 2.5, 3, 4, 6, 8 (C2): 6 and 8 go |
| **Text** | `Caption` 18 (**the floor: every UITextSizeConstraint's MinTextSize**) · `Body` 22 · `Button` 24 · `Title` 30 · `Number` 36 (HUD) · `Hero` 56 (Celebrate, the Day Report count). Display font for numbers, titles and buttons; body font for sentences. | Small 18, Body 24, Title 34, Big 48, and the 9–14 minimums (C3) |
| **Shadow** | One: ink at 0.6 transparency, offset (0, 6), only under modals, the Now card and toasts. None on the HUD (the outline does that job). | Shadow 8 in `Hud.modal`, MiniGames and Celebrate |
| **Motion budget** | **One perpetual effect on screen at a time**, on the one Collect button. Dots pop once. Rays only on a reward moment. Reduced motion as today. | Shine on 8 surfaces, breathing on 5, dot hops (B6) |
| **Zone** | `RailButton` 72 desktop / 56 phone · `RailGap` 10 / 8 · `PhoneBreak` safe height < 440 · `CornerClear` 110 | the bottom-bar fit (`Hud.luau:2101-2113`) |

### 3.5 A calmer colour use

**Aligned with `2026-11-16-art-direction.md`.** That doc measured why our game reads too bright:
- our frames average V 0.95 and never get darker than luma 138;
- 31–35 % of the screen is pale;
- yet we are *less* saturated than the top games.

"Too bright" is over-exposure and bleach, not saturation. So the UI keeps its candy hues (it's unlit; art doc §4.5).
The calm comes from **fewer competing fills, flat white panels with a deeper header and tinted cards, and colour that
means one thing**, not from paler colours. The world's share (relight, studs, dark anchors, no pastels) is the art
doc's §4.1–4.3 and isn't repeated here.

**Three rules.** Roblox's own guidance is vivid hues for key text and buttons, muted shades for less important elements,
bright colours used with restraint, and consistent meaning.
- **The chrome is a small fixed set** (art doc §4.5 values):
  - header `#1F8FE5`;
  - panel `#FFFFFF` flat;
  - card `#EEF3FA` with a `#C3D0E6` stroke, image well `#D6E3F5`;
  - HUD plates white with a `#1B1238` stroke;
  - text Ink `#221A48`, soft `#5D5788`;
  - the Now card, the HUD's one dark element: `#1E2440`.
- **Candy is for meaning.** Each colour has one job:
  - orange = the one main action;
  - green = collect, ready, done;
  - red = news dot, ✖, destructive;
  - gold `#FFD43B` / `#FFE228` = 💰 and ⭐ (icons, numbers' accents and reward rays, not plates);
  - the rarity colours, only on rarity frames and bands (Data/Rarities);
  - wing and station colours, only on that item's own tile or 6 px stripe;
  - night purple `#5B3BD6`, only on the night status line and night banners.
- **A fill budget.** The art doc sets "at most 3 saturated fills in the HUD at once, plus red dots". This map goes
  under that:
  - no wallet pill;
  - rails on white plates;
  - status lines as outlined text with at most one small coloured chip (night, or the event);
  - so the only saturated fills are an event chip and the dots.

**What changes.**
- The 7 tab colours (B1) and the 11+ header colours (B3) go to the fixed set.
- The HUD pills (B2) go away.
- Panel rows stop cycling candy colours (B4).
- The paper's ice gradient goes (B5b).
- **Where flashy stays:** Celebrate, the Day Report's count, a READY gift, a Legendary+ belt arrival. These are the
  reward moments, and the trending look lives there. Gloss, outlines and pop stay on every button (art doc §4.5).
  That keeps Joshua's "flashy" from memory-007 where it counts and answers today's "too bright" everywhere else.

⚠️ Like the art doc, this revises Claude's candy-pop specifics recorded in memory-20261116-007. It doesn't revise
Joshua's "saturated and flashy". Once Joshua says yes, record it as a new `memory/records` file that quotes him and
supersedes those specifics. Don't edit -007.

### 3.6 How world signs and billboards match the screen UI

1. **Screen is about you; the world is about places and things.**
   - On screen: wallet, menus, rewards, your goal, your hands.
   - In the world: prices on rooms, odds at the belt, a patient's needs, clinic names, leaderboards.
   - Nothing in the world imitates a HUD control.
2. **World UI is sized in studs.** It shrinks with distance and has a `MaxDistance`, as the patient badges, station
   icons and price badges already do (E3).
   - `AlwaysOnTop` only for what you're interacting with right now: the focused hire card, your carry tray.
   - Never a fixed-pixel button floating in the world.
3. **Same tokens, world-scaled:**
   - the same `#1B1238` outline (never a white rim, C2);
   - LuckiestGuy for numbers and titles, FredokaOne for words;
   - the same rarity colours;
   - board fills and world colours from art doc §4.1;
   - outlines drawn as nested frames, so the weight holds at distance (PlotBuilder already does this).
4. **Short labels are bare outlined text; boards are for tables** (art doc §4.4).
   - Clinic names, "+5", station names and "Stand here" float as LuckiestGuy in white `#FFFFFF` or gold `#FFD84A`,
     with a 3–4 px `#1B1238` stroke and an optional 2 px drop-shadow copy, as in [REF].
   - A board only for tables (odds, leaderboards), on a navy plate `#1E2440` at 0.15 transparency with white text.
     That's the same navy as the HUD's Now card, so the world's information plates and the screen's "now" plate are
     visibly one family.
5. **One prompt look.** Station, Counter, sign and kiosk prompts use `Style = Custom`, drawn by one client view in the
   Kit style: a white plate, an ink outline and a key chip. That's the belt's Hire card approach, generalised. It fixes
   D6, the default grey "E Make" in S13.
6. **The odds (E1, E2).**
   - **Delete the floating chip.** In its place:
     - a "🎲 See odds" prompt on the odds sign itself;
     - a Quiet "🎲 Odds" button **inside the focused hire card**, at the point of purchase (Grow a Garden's pattern,
       and Roblox's "prior to purchase" with a descriptive word);
     - the Journal's 🎲 chip, which already exists.
   - The sign keeps every odd, restyled to the world tokens: the navy plate instead of the hot-pink board with its
     white rim, and a floating "🎲 NURSE ODDS" title.
   - Hiring uses in-game cash, but the game shows odds anyway (memory-011). This keeps them shown, not just tidier.

---

## 4. Migration list, per file

**v2** = the Progression v2 build plan gives this file to a task, so editing it now would conflict (§A of
`docs/plan/2026-11-16-progression-v2-build-plan.md`). 🔒 = frozen in v2's Foundation.

**Order:** Theme tokens → Kit parts → Hud zones and shell → panels → world.

**Advice:** land the pass after v2 merges, as one "UI cohesion" task. T8 owns `Hud`/`Kit`/`Theme`/`Toasts`/`Celebrate`/`MiniGames`, so
the token and shell steps could also be handed to T8 inside v2. Until then, v2's new panels should at least use
`Hud.modal`'s defaults and stop adding `paintTab`/`textLimit` copies.

| File | What changes | v2 |
|---|---|---|
| `shared/Palette.luau` | The art doc's §4.1 world palette and world accents, the navy plate `#1E2440` and the stroke `#1B1238`. World signs read them from here. | **v2 🔒 Foundation** |
| `client/UI/Theme.luau` | §3.4 tokens: Space, Radius (Small/Medium/Large/Round), Stroke (Fine/Bold/Panel), the Text roles with an 18 floor, one Shadow, the motion budget, the Zone constants. Colours from art doc §4.5: `Header #1F8FE5`, `Paper #FFFFFF` (no `PaperEdge` gradient), `Card #EEF3FA`, `CardLine #C3D0E6`, `Well #D6E3F5`, `NowPlate #1E2440`, `Plate` white, and Primary orange / Collect green / Destructive red. Drop the per-panel colour use. | **v2 T8** (adds `Juice.RingBeads`) |
| `client/UI/Kit.luau` | Button kinds by **role**: Primary, Collect, Secondary, Quiet, Destructive, plus Icon. Map the old colour kinds onto Secondary during the move. `Kit.panel`: the one header colour, and the paper gradient goes. **New:** `Kit.tab(button, selected, stripe?)` (replaces 7 `paintTab`s), `Kit.textLimit(label, max)` with min 18 (replaces 12 copies), `Kit.railButton`, `Kit.number` (an outlined HUD number), `Kit.statusChip`. `setDot`: pop once, no hop loop. | **v2 T8** (adds `ring`, `holdButton`, `setDot` glyph) |
| `client/UI/Hud.luau` | The zone map (§3.1): the System slot in a `TopbarSafeInsets` ScreenGui (⚙️, and on phones the wallet and ⚙️ More); the wallet without pills; the Now slot (the warning chips move here from the wallet); Status with labelled day/night, **one free-event chip** (-022) and a labelled visitor; the left and right rails with fixed slots and a phone breakpoint; the bottom bar goes (`:1724-1733`, `:2101-2113`); the hands at the bottom centre. Hide the rails, Now and Status while a Panel is open. `Hud.modal` header from `Theme.Colors.Header` instead of `tabColor` (`:357`). New `Hud.confirm` and `Hud.oddsPopup`. Retire `TABS[].Kind/Color` (`:151-159`). | **v2 T8** (72 lines: the 🛒 Branch dot, sold-nurse coins) |
| `client/UI/Toasts.luau` | One notice stack under the Now card. Toasts become white plates with ink text (not purple). A banner is the same plate with an icon tile in its event's colour. Absorbs BadgeBook's cheer banner. Remove the width and position juggling (`:203-220`, `BELOW_WALLET_Y`). | **v2 T8** |
| `client/UI/Celebrate.luau` | Keep it loud (a reward moment) but on the tokens: Large radius, Bold stroke, one shine, Hero text. Its `ACCENTS` stay (they're the moment's meaning). | **v2 T8** (+400 lines: Rebirth, Perk, NurseLevel, Unlock) |
| `client/UI/MiniGames.luau` | Replace the hand-built shell (`:502-580`) with `Hud.modal` (no ✖, no dim-close) and the standard header. The game colours inside stay (they're the game). `MinTextSize` 10 → 18 (`:373`). | **v2 T8** |
| `client/UI/Guide.luau` | The pin and arrow use the world tokens (ink outline, Round radius). No layout change. | **v2 T8** |
| `client/UI/BookPanel.luau` | `Kit.tab` with the wing colour as a stripe (`:99`). The page header and card on tokens. `MinTextSize` 10 → 18 (`:79`). | **v2 T8** |
| `client/UI/Boards.luau` | `Kit.tab` (`:68`), the standard header. Medal row tints stay. Reached from the left rail (desktop) or ⚙️ More (phone). | **v2 T8** |
| `client/UI/PromptFilter.luau` | It already finds every station, Counter and sign prompt by tag. Set `Style = Custom` there and hand them to one new `PromptView` (Kit-styled) (§3.6 #5). | **v2 T8** |
| `client/UI/Shop.luau` | `Kit.tab` (`:178`), `Kit.textLimit` (`:195`). Rows: neutral icon tiles, not "the next candy colour". Buy = Primary, "can't yet" = Disabled with a gate chip. Header meta chip = 💰. | **v2 T5** |
| `client/UI/NursePanel.luau` | The on-duty strip (`:417-428`) becomes a "Team" card row. Rarity tabs via `Kit.tab` with a rarity stripe (`:256`). The completion pill (`:371-403`) uses the header's meta chip. 10 radii → 4. `MinTextSize` 9 → 18 (`:215`). | **v2 T5** |
| `client/UI/BranchPanel.luau` ✚ | `Kit.tab` (`:603`), the standard header (no purple `ACCENT` `:540`), the reset confirm via `Hud.confirm` (`:1637`). "Open branch!" stays a hold button, as a Primary (Primary never shines; it already avoids pressure). | **v2 T5** |
| `client/UI/AgencyPanel.luau` ✚ | Tabs to the column with `Kit.tab` (`:439`), confirm → `Hud.confirm` (`:449`), odds → `Hud.oddsPopup` (`:550`), the standard header (`:376`). | **v2 T3** |
| `client/UI/BeltView.luau` | **Delete the `BeltOddsChip` billboard** (`:668-725`). Add a "🎲 Odds" Quiet button on the focused hire card and a sign prompt. The odds popup goes through `Hud.oddsPopup`. Chip and card on the world tokens. `MinTextSize` 9 → 18 (`:302`). | **v2 T3** |
| `client/UI/MarketPanel.luau` ✚ | The standard header (no orange `ACCENT` `:38`), confirm → `Hud.confirm` (`:508`), `Kit.tab`. | **v2 T4** |
| `client/UI/LiftPanel.luau` ✚ (stub) | Build it on the template from the start: a Popup of big Secondary floor buttons, no look of its own. | **v2 T6** |
| `client/UI/AdminPanel.luau` | Dev-only, so last: ten colour kinds → Secondary and Danger, `Kit.textLimit`. | **v2 🔒 Foundation** |
| `client/UI/BadgeBook.luau` | Tabs from a row (`:106-111`) to the column with `Kit.tab` (`:141`). The cheer banner (`:342-358`) goes into the Toasts stack. Stroke 6 → 3. | not in v2 |
| `client/UI/DayReportPanel.luau` | Standard header, Hero count, one Primary 🛒. Stays a no-dim popup. | not in v2 |
| `client/UI/Mailbox.luau` | Letter and Goals on the standard header. Goal rows' icon tiles go neutral. Claim = Collect (breathes only while ready). Opened from the right rail. | not in v2 |
| `client/UI/PlayGifts.luau` | Cards on tokens. READY = Collect with the one allowed shine. Opened from the right rail (it no longer hangs under the wallet). | not in v2 |
| `client/UI/Tutorial.luau` | The card moves to the **Now slot**: top centre, on the navy Now plate `#1E2440` with a "TUTORIAL n/8" tab, the line and a progress bar ([REF]) (`:293-321`). This matches `docs/research/2026-11-16-tutorial-ux.md` §3.1 (another session's doc: the card goes top centre and toasts sit below it). Its frame design is the one to build into the Now slot. The hint chip (`:353-366`) becomes an inline key glyph ("⌨️ E" / "👆 hold"), not a button look. The pointer targets follow the rails. | not in v2 |
| `server/NurseBelt.luau` | The odds sign: the navy plate `#1E2440` at 0.15 with white text, replacing the hot-pink board and its white 6 px rim (`:600-611`), a floating "🎲 NURSE ODDS" title, and a `🎲 See odds` ProximityPrompt. | **v2 T3** |
| `server/PlotBuilder.luau` | Signs float their text with no board (art doc §4.4, `buildSign` `:1018-1045`). `candyBoard` (`:324`) and the price badges use the art doc's world accents and the token radii. | **v2 T6** |
| `server/BoardBuilder.luau` | The leaderboard boards on the navy plate, with a title style matching the panel header. | not in v2 |
| `server/CreatureBuilder.luau`, `Carry.luau`, `Nurses.luau`, `NurseBuilder.luau` | Already world-correct (stud-sized). Only align the colours and stroke to tokens when Palette changes. | **v2 T7, T2, T1, T1** |

---

## 5. Top 5 fixes, by impact

| # | Fix | Answers | Files |
|---|---|---|---|
| **1** | **Re-zone the HUD.** The 7 bottom tabs split into a left menu rail (🛒 👩‍⚕️ 📖 🏅 🏆) and a right reward rail (🎁 🎯 📬). The tutorial card and the warnings move to a top-centre Now slot. ⚙️ goes into the top-bar row. A labelled clock and **one free-event countdown** sit top-right. The bottom keeps only your hands. The rails hide while a panel is open. A phone layout keeps 3 buttons per rail. | "segmented", "all at the bottom", "top feels bare", "not methodical", "empty" (A1–A8) | `Hud`, `Tutorial`, `Toasts` (v2 T8) |
| **2** | **One chrome, colour only for meaning** (art doc §4.5 values). One white plate for every rail button, one header colour (`#1F8FE5`) for every panel, flat white panels with tinted cards. Orange only for the single main action, green only for collecting, red only for dots and ✖. Panel rows stop cycling colours. | "too bright", "competing colours", "not cohesive" (B1–B5b, D7, F5) | `Theme`, `Kit`, `Hud`, every `ACCENT` (v2 T8, T5, T3, T4) |
| **3** | **A light wallet:** icon plus a big outlined number, no pills or gradients ([REF]). Day/night and the visitor chip get words. | heaviness (B2, C4), legibility (F1, F2) | `Hud` (v2 T8) |
| **4** | **Odds out of the HUD layer.** Delete the AlwaysOnTop pixel-sized 🎲 chip. Odds go in the focused hire card (at the point of purchase), on the sign's own prompt, and in the Journal. | the floating ODDS button (E1, E2) | `BeltView`, `NurseBelt` (v2 T3) |
| **5** | **One shell, one tab, one notice, one token set.** `Kit.tab` (7 copies → 1), `Kit.textLimit` with an 18 px floor (12 copies → 1), `Hud.confirm` (3 → 1), MiniGames on `Hud.modal`, the cheer banner into Toasts, radii ~20 → 4, strokes 6 → 2, one motion budget. | "not cohesive" inside panels (C1–C3, D1–D6, B6) | `Kit`, `Theme` + a sweep of the panels |

---

## 6. For `context/OPEN-QUESTIONS.md` (Joshua; the coordinator files them)

1. OK to move the seven bottom tabs into two side rails: menus on the left, rewards on the right?
2. On phones, 🏅 Badges and 🏆 Top go into ⚙️ More (there's room for only 3 rail buttons a side). OK?
3. "Too bright" (UI part): one fixed chrome, with candy colour kept for rewards, rarity and the one main button. This
   revises the candy-pop specifics recorded in memory-007, so it needs your yes. It goes with the art doc's world fixes.
4. One header colour for every panel: the art doc's blue `#1F8FE5`, or your reference's dark navy? (The navy is used
   for the Now card either way.)
5. The free-event chip (-022): which events show first when two are coming? Proposed: whichever is sooner.

## Sources
- Joshua's screenshots S11, S12, S13 (live game, 2026-11-16), and his descriptions of S-night and the reference game.
- allthings.how, Steal a Brainrot Index guide, updated 5 Nov 2026: https://allthings.how/?p=329377 (V); ?p=328991 (R).
- allthings.how, Scare Your Neighbor starter guide, updated 6 Nov 2026:
  https://allthings.how/scare-your-neighbor-starter-guide-roblox (V).
- allthings.how, Grow a Garden guide, 7 Nov 2026: https://allthings.how/?p=330478 (V).
- allthings.how: Blox Fruits ?p=323324 (2 Nov 2026), Sell a Million Sushi ?p=325331 (4 Nov 2026), Restaurant
  Tycoon 3 ?p=38155 (12 Jun 2026) (R). biggames.io Pet Simulator 99 update 61 notes (24 May 2025) (R).
  earnaldo.com Adopt Me beginner guide (5 Jul 2026) (R).
- Top-games context: ejaw.net/roblox-charts (16 Mar 2026); games.gg/news/roblox-top-games-and-trends-december-2025
  (14 Dec 2025); rowatcher.com/news/roblox-week-in-numbers-2026-w44 (R).
- Roblox Creator Hub (fetched 2026-11-16): /docs/ui/position-and-size (V);
  /docs/tutorials/curriculums/user-interface-design/wireframe-your-layouts (V);
  /docs/production/game-design/ui-ux-design (V); /docs/production/publishing/adaptive-design (R);
  /docs/ui/on-screen-containers (R); /docs/production/monetization/paid-random-items (R).
- Roblox DevForum, "Studio beta for experience controls", staff, created 2023-08-28:
  https://devforum.roblox.com/t/2567355 (R).
- Epic, Designing for mobile in Fortnite: https://dev.epicgames.com/documentation/fortnite/designing-for-mobile-in-fortnite
  (search excerpt).
- Repo skills: `.claude/skills/game-ui-ux` (layout, safe areas, contrast, diegetic vs world-space) and
  `.claude/skills/roblox-ui` (one token set, no universal pills, button roles, the viewport matrix).
