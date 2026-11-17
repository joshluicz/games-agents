# UI direction: less clutter, emoji used correctly

**Date:** 2026-11-17 · **Status:** proposal for Joshua (nothing here is built; no game code was changed) ·
**Asked by Joshua (chat, verbatim):**
> the UI is cluttered. can you use taste-skill and impeccable in studio-agents to fix all the UI. see if there are
> skills online for roblox UI...
>
> the UI looks very AI with all the emojis...
>
> not to remove the emojis, but to use them correctly...

**What this is built on.** The rulings stand: saturated and flashy (`memory-20261116-007`), the navy header, side
rails and calmer colours (`memory-20261117-001`), treat never cure (`-005`), no cross emblem, studs. And the newest,
which leads this doc: **"the game is getting a little too complicated already. need it simple especially at the
start."** (Joshua, `memory-20261117-006`: "Simplicity beats depth when they clash.") The tokens in
`game/src/client/UI/Theme.luau` and the roles in `Kit.luau` stay. This doc changes how they are **spent**.

**Read for this:** taste-skill (`TS`: `studio-agents/vendor/taste-skill/skills/taste-skill/SKILL.md` §3.D, §4.4, §9,
§14, plus the redesign, minimalist and soft lenses), impeccable (`IMP`: `skill/reference/craft-floor.md`,
`distill.md`, `quieter.md`, `layout.md`, `typeset.md`), this repo's `roblox-ui` and `game-ui-ux` skills, every file
in `game/src/client/UI/`, and the captures in `logs/playtests/2026-11-17-*`.

**How sure.** NursePanel, the HUD, Settings and the mini-games were judged from captures and code. Shop, Branches,
Agency, Market, Mailbox, Book and Badges were judged **from code only** (no capture of them was looked at), so their
rows below say what the code builds, and the first Studio run of each should confirm it.

---

## 1. The diagnosis

**In one line:** the look overhaul fixed the tokens, but every element still gets the full treatment (a fill, a dark
outline, an emoji, a pill), so nothing is quieter than anything else. Hierarchy was replaced by decoration.

### What makes it cluttered

| # | The fault | Where it shows | The tell it hits |
|---|---|---|---|
| C1 | **Boxes inside boxes.** Panel (4 px outline) > card (2 px line) > face well (rarity frame) > level plate (2 px outline) > XP track (2 px line) > chips > ring plate > 3 outlined buttons. Eight framed things in one Team card | `NursePanel.newTeamCard` (21 `Kit.stroke` calls in the file) | IMP craft floor: "Cards are the lazy container; nested cards are always wrong". TS §4.4: "Use cards ONLY when elevation communicates real hierarchy". `roblox-ui`: "Avoid card-on-card shells, universal pills" |
| C2 | **One weight for everything.** Job, Sell and List are three same-size outlined buttons on every card; Settings is eight identical outlined buttons | `NursePanel` foot; `Hud` Settings (`9-settings-replay.jpg`) | IMP distill: "ONE primary action, few secondary actions, everything else tertiary or hidden". `roblox-ui`: "Buttons of different importance look different" |
| C3 | **Pills for plain facts.** Specialty and ability are filled pills; the roster, rest and team notes are chips; the header has a boxed chip | `NursePanel` `chip()`, `Specialty`, `Ability`; `Modal` meta chip | TS redesign lens: pill badges; `roblox-ui`: "universal pills" |
| C4 | **Decorative dots.** 12 beads ring every ability icon even when nothing is recharging; rarity tabs are a dot plus a count | `Kit.ring` (`Theme.Juice.RingBeads = 12`); `Modal.tabs` | TS §9.F: "ZERO decorative status dots by default... only when conveying real semantic state" |
| C5 | **The display font shouts everywhere.** LuckiestGuy is on titles, nurse names, numbers, tabs and buttons, so the title is no louder than a card | every panel | TS §9.B: "Control hierarchy with weight + color, not raw scale"; IMP typeset: "Are adjacent sizes or weights too close to carry different jobs?" |
| C6 | **Spacing off the scale.** `Theme.Space.Step` is 4/8/12/16/24/32, but the Team card uses 6, 10, 2, 36, 62 by hand, so groups don't read as groups | `NursePanel` constants (`CARD_GAP = 10`, `padButton(x, 8, 2)`) | IMP craft floor: "tight groups, generous separation"; TS §9.C |
| C7 | **Two meanings for green.** Green is "collect, ready, done" (ux audit §3.5) and also the XP bar and the ring | `NursePanel` `XpFill`, `RING_COLOR` | TS §4.2 colour consistency lock |

### What makes it look AI-made: the emoji

The client's UI files hold **about 800 emoji in strings** (MiniGames 119, Hud 70, Shop 69, NursePanel 66, Tutorial
62, BranchPanel 62). Emoji are not the problem: the game was designed so a child who can't read can still play
("No reading required to play", creature-clinic build plan). The problem is that they do four different jobs at
once and nothing separates them:

| # | The fault | Real strings from the code | The tell |
|---|---|---|---|
| E1 | **An emoji in front of every label, button and heading**, like a bullet | `"👩‍⚕️ Team"`, `"⚙️ Settings"`, `"✅ You keep"`, `"🔄 Starts fresh"`, `"🎁 You get"`, `"🤝 Pair specialties for team bonuses"`, `"💼 Listed nurses keep working"` | IMP craft floor: "Unicode glyphs or emoji standing in for an icon system". TS §3.D: emoji "sparingly with intent". This is the single strongest "an AI wrote this" signal |
| E2 | **The emoji repeats the word** | `"✅ Yes!"`, `"🎉 Yay!"`, `"🔁 Replay"`, `"👆 Tap a card"`, `"👇 Pick a nurse to sell"`, `"✋ Hold to sell"`, `"👀 Which one fits?"` | TS §4.5 no duplicate intent; IMP distill: "If it's said elsewhere, don't repeat it here" |
| E3 | **Two icons for one idea** | The ability is `🧼` in the ring and `"🧼 Quick Soap"` in the chip beside it. The book is `📖` (rail), `📔` (meta chip), `📕` (older build). Mail is `📬`, `📭` and `💌`. The building is `🏥`, `🏢`, `🏠` and `🏙️` (`"Need 🏙️ Lv "` vs `"Needs 🏥 Lv "`) | IMP: one icon family, one meaning |
| E4 | **One icon for many ideas** | `🏢` = Agency, Branches, "Stays with you" and the rebirth count. `⭐` = Stars, MAX, the specialty boost, the mini-game target and the visitor. `💰` = Cash and the verb Sell. `✅` = Bought, Built, Max, Hired, Yes and Take it. `🔄` and `🔁` both mean again | Creator Docs: "Icons can employ a visual identity that conveys meaning", "consistently apply them throughout the game" |
| E5 | **Strings of emoji as a sentence** | `"🏡 🔑 💛"`, `"💰⭐ ×"`, `"🩺 Healer (🧪 at 🏥 Lv 2)"`, `string.rep("🛏️", beds) .. string.rep("🌸", slots)` | TS §4.9 copy self-audit: unclear referents |
| E6 | **No size per role.** Emoji sit inline at whatever the text size is (18 to 30 px), in the outlined display font, next to a 40 px tile emoji | titles, chips, buttons | IMP: "one consistent stroke and weight" |

### Screen by screen, worst first

1. **Nurses (Team and Journal), `NursePanel.luau`.** C1 to C7 and E1 to E4 all at once; it is Joshua's screenshot.
2. **Settings and the HUD status lines, `Hud.luau`.** Eight equal buttons whose emoji **and** words both change with
   state (`"🔇 Music off"` / `"🎵 Music on"`), so nothing looks like a switch. The rails themselves are fine.
3. **Branches, `BranchPanel.luau`** (code only). 62 emoji from 18 kinds: nearly every string starts with one (E1),
   and `🏢` `🌳` `🃏` `🔄` repeat down the page.
4. **Shop, `Shop.luau`** (code only). Stroked rows, pips, a note line built from repeated emoji (E5), and a Buy
   button on every row at the same weight.
5. **Agency and Market, `AgencyPanel.luau`, `MarketPanel.luau`** (code only). Confirms like `"💰 Sell?"` + `"✅ Yes!"`,
   and three identity icons (`🏢`, `🏷️`, `💰`) on one sheet.
6. **Mini-games and the tutorial, `MiniGames.luau`, `Tutorial.luau`.** The tool cards are the **right** use of emoji
   (big, one per card, the emoji is the art: `5-xray-tool-card.jpg`). The clutter is around them: a header emoji, a
   `"🔥 Go!"` chip, emoji step dots and an emoji hint line, all for one idea.
7. **Mailbox, Goals, Book, Badges, Play Gifts, Day Report.** Smaller versions of E1 and E2.
8. **Celebrate.** Leave it loud. It is the reward moment, where the ruled "flashy" belongs (ux audit §3.5).

---

## 2. The direction: "candy on the verbs, calm on the nouns"

The candy look (gloss, dark outline, chunky display type, colour) is the game's identity. Spend it on **what the
player can press right now and what they just won**. Everything else is flat, quiet and aligned. Eight rules; R0
wins when it clashes with any other.

**R0. Simple first: show only what the player can use now** (`memory-20261117-006`). Three parts:
- **A feature appears when it becomes usable, not before.** No greyed-out doors, no "coming at Lv 5" teasers, no
  empty tabs. Today the tutorial reveals the HUD step by step (`Hud.Pure.reveal`), but the moment it ends
  everything arrives at once (`Rest = true`: Nurses, Gifts, Goals, Mail, both Status lines). The reveal carries
  on past the tutorial, one door at a time, each on the first moment it has something in it.
- **A card shows what matters at this level.** A fact that can't differ yet is not drawn (a team bonus with one
  nurse, an ability ring before the first ability fires, a specialty when there is one department).
- **Budgets.** On the HUD at Lv 1: at most 3 doors and 1 Status line. On a card: 1 button, at most 2 Soft facts.
  In a panel: only the tabs that have something in them.

**R1. One primary action per card, one per view.** A card or row has at most one filled button. Other actions are
Quiet (text only) or sit behind one "More" control. A view has at most one Primary (orange) or Collect (green).

**R2. The outline budget.** The dark `Theme.Colors.Stroke` outline is for four things only: the panel shell, candy
buttons (Primary, Collect, Destructive), HUD plates that sit over the 3D world, and text drawn over the world or
over colour. Inside a white panel nothing else gets a dark outline: cards are a `Card` fill with no line,
Secondary buttons are a `Secondary` fill with no line, bars and tiles have no line.

**R3. Two surfaces, never three.** Inside a panel: the paper, then a card. The only thing allowed inside a card is
one art tile (a portrait or an item emoji on `Well`). No chip, plate or pill inside a card: facts are plain text.

**R4. Spacing only from `Theme.Space.Step`.** 4 inside a group (icon to its label), 8 between lines of a group, 12
card padding and between cards, 16 panel padding, 24 between sections. No hand-typed 2, 6, 10.

**R5. Type: three voices, and the display font is rare.** Text can't go under 18 px (kept), so hierarchy comes from
font and ink, not size:

| Voice | Font, size, ink | Used for |
|---|---|---|
| Loud | `DisplayFont`, Title 30 / Number 36 / Hero 56, outlined on colour | the panel title, HUD numbers, candy buttons, Celebrate. Nothing else |
| Normal | `Font` (FredokaOne), Body 22, `Ink` | names, row titles, Secondary and Quiet buttons |
| Soft | `Font`, Caption 18, `InkSoft` | facts, counts, hints, captions |

A card uses Normal once (its name) and Soft for the rest. Sentence case everywhere outside the Loud voice.

**R6. Colour means one thing.** Orange = the one main action. Green = collect, ready, done. Red = news dot, close,
destructive. Gold = Cash and Stars. Rarity colours = the rarity frame only. New: **progress is navy**
(`Theme.Colors.Header` on a `Well` track; gold at MAX), so green stops meaning "XP".

**R7. Motion is for answers, not for furniture.** Kept: one looping effect on screen, on the one Collect button.
Added: a list never pops card by card; a ready ability shows no ring at all (the beads appear only while it
recharges); ribbons don't tilt; a toggle slides, it doesn't bounce.

### The emoji rules

**The principle: emoji are the game's art, so they are nouns. They are never punctuation.**

| Role | What it is | Where | Size | Count |
|---|---|---|---|---|
| **Art** | The thing itself: an item, a case, a tool, a station, an ability, a room. Comes from `shared/Data/*` (`Icon`), never typed into a UI string | alone in an art tile, a mini-game card, a world bubble | 40 px in a tile (`Theme.TextSize.Icon`), 56+ in a mini-game card | one per card or row |
| **Door** | The icon of a place: Shop, Nurses, Book, Gifts, Goals, Mail, and each tab | the rail plate and the tab only, with its word under it | 60% of the plate (as today) | one per door, the same one everywhere |
| **Unit** | What a number counts: `💰` Cash, `⭐` Stars, `🏥` hospital level, `🌳` tree points | glued in front of its number: `💰 300`, `🏥 Lv 3` | the number's own size | one per number |
| **State** | `🔒` locked, `✅` done, `💤` resting | a small badge on the corner of the art tile, or alone in place of a button's label | 18 px | one per card |
| **Party** | `🎉` and friends | Celebrate, a reward toast, the Day Report. Nowhere else | free | free |

**Never:**
1. **No emoji in a heading.** The panel title is words: `Team`, `Settings`, `Shop`. The door icon is on the rail
   the player just tapped; saying it again is E2.
2. **No emoji in a button, except a Unit with its price or a single Art noun the button is about.**
   `💰 300` (a price) and `🩺 Healer` (the job it picks) are fine. `💰 Sell`, `🏷️ List`, `✅ Yes!`, `🎉 Yay!`,
   `🔁 Replay`, `🎁 Claim` lose the emoji: the button's colour already says what kind of action it is.
3. **No emoji as a bullet or to open a sentence.** Hints, notes, toasts and empty states are plain words. A list
   uses position and space, not `✅` / `🔄` / `🎁` markers.
4. **No emoji that repeats its own word** (`👆 Tap`, `👀 Look`, `✋ Hold`), and no gesture or face emoji in chrome.
5. **One idea, one emoji; one emoji, one idea.** A dictionary (`UI/Icons.luau`, new) names each chrome emoji once.
   The collisions to settle (Joshua picks; these are the proposed winners): building level = `🏥` only (drop `🏙️`
   and `🏠` for level); Book = `📖` only; Mail = `📬` only; again = `🔁` only; `🏢` = Branches only (Agency gets its
   own door icon); `⭐` = Stars only (MAX is the word `MAX`, the mini-game target is a drawn mark).
6. **At most one emoji per label, two per card** (the art tile plus one Unit or State). Odds tables and the
   tutorial's "Tap 🛒" pointers are the listed exceptions.
7. **Never two emoji side by side**, and never an emoji inside outlined display text (Roblox draws emoji from its
   own image set and can't tint or outline them, so they look pasted on).

### Before and after: the Team card

Before (today's strings and parts):

```
Header   👩‍⚕️ TEAM                                        [📔 18%]  [✖ 56 px, candy red]
Tabs     [👩‍⚕️ 3/3] [● 0/5] [● 0/4] [● 0/3] [🌈 0/2]            (each a stroked plate)
Card     ┌ stroked card ─────────────────────────────────────────────┐
         │ [portrait in a rarity frame]  DEW DUCK (display font)  (12 beads round 🧼) │
         │ [Lv 1 plate, outlined]        [▬▬ 0/20 ▬▬ stroked track]                   │
         │                               (🛁 Bath Room) (🧼 Quick Soap)   <- two pills │
         │ [🩺 Healer]            [💰 Sell]            [🏷️ List]    <- three outlined │
         └────────────────────────────────────────────────────────────────┘
```

After:

```
Header   Team                                             3/3     ✖ (48 px, inside the band)
Tabs     Team · Common 0/5 · Rare 0/4 · Epic 0/3 ...      (no plates; the selected one is navy)
Card     flat Card fill, no line, 12 px padding
         [portrait in its rarity frame]   Dew Duck                  Lv 1
                                          ▬▬▬▬▬░░░░░░ (8 px, navy, no text inside)
                                          Bath Room · Quick Soap                (Soft, 18 px)
         [ 🩺 Healer ]  <- the one button (Secondary fill, no outline)          More
```

What changed: 8 framed things became 2 (the card and the portrait). 7 emoji became 1 (the job, an Art noun the
button is about). The level is text, not a plate. The XP count moves to the Soft line only when the bar is tapped
or the card is new. The ring appears over the portrait corner **only while the ability recharges**. Sell and List
move behind `More` (a Quiet text button that opens the two choices, each with its own confirm as today), so a
child can't sell a nurse with one stray tap and the card has one obvious action. A resting nurse shows `💤` as a
State badge on the portrait and the button reads `Pick a job`.

More before and after, same rules:

| Where | Before | After |
|---|---|---|
| Settings row | `[🎵 Music on]` / `[🔇 Music off]` (a button whose text changes) | `Music` + a switch on the right (green when on). Rows in one list, no outlines |
| Branch sheet | `"✅ You keep"` · `"🔄 Starts fresh"` · `"🎁 You get"` | `You keep` · `Starts fresh` · `You get` as three Soft headings over their items |
| Confirm | `"💰 Sell?"` + `"✅ Yes!"` | `Sell Dew Duck for 💰 120?` + `Sell` (Destructive, hold) + `Keep` (Quiet) |
| Shop gate | Note `"🔒 🏥 Lv 3"` and button `"🏥 Lv 3"` | Note `Needs 🏥 Lv 3`; the button shows the State badge `🔒` only |
| Room note | `🛏️🛏️🛏️ 🌸🌸` | `3 beds · 2 decor spots` |
| Mini-game | header `🤔 WHICH TOOL?` + `🔥 Go!` chip + emoji step dots + `"✨ The shiny one!"` | header `Which tool?`, plain step dots, hint `Pick the shiny one`. The three tool cards stay exactly as they are |
| Job wait | `"🩺 Healer (🧪 at 🏥 Lv 2)"` | button `🩺 Healer`; Soft line `Maker opens at 🏥 Lv 2` |

### What a Lv 1 player sees

The triggers are **proposals** (the only gates found in `Config` are Branches at hospital Lv 5 and Epic and up
at Lv 3). Each trigger is a fact about the player's own save, so nothing shows early and nothing shows empty.

| Screen | A new Lv 1 player sees | Hidden until (proposed trigger) |
|---|---|---|
| **HUD** | The wallet (Cash; Stars after the first treatment, as today). The Now card with the one next thing to do. The Shop door once the tutorial reaches it. Nothing else | **Nurses:** the first nurse can be hired. **Book:** the first page is filled. **Goals:** the tutorial is done and the first day has ended (until then the Now card carries the one goal). **Mail:** the first letter arrives. **Gifts:** the first play gift is ready. **Day and night line:** the first night. **Golden Hour chip:** hospital Lv 3 (Secret nurses can't be hired before then, so the timer means nothing). **Badges, Top:** under Settings, as on phones today |
| **Settings** | Music, Effects, Mini-games or simple taps, Skip or Replay tutorial | **Friends only / Anyone can help:** you own a clinic. **Badges, Top:** the first badge. Admin: admins only (as today) |
| **Shop** | One list: the things you can buy now, cheapest first. No tab column while there is one kind of thing | **Rooms, Decor, Hospital tabs:** when the first item in each is buyable or one level away. **"New branch" and "Your branches":** hospital Lv 5. Winter rooms: not listed out of season (no `❄️ Soon` row) |
| **Nurses** | Not on the HUD. When it first opens: Team only, one card: portrait, name, level, the job button | **More (Sell, List):** you own 2 nurses. **Specialty and team line:** a second department exists. **Ability name and ring:** the nurse's ability has fired once. **XP bar:** the first XP is earned. **Journal tabs:** a second rarity has been seen; then only rarities you have seen get a tab |
| **Agency, Market** | Nothing. No link, no tab, no button | **Agency:** the roster has been full once (the first moment selling helps). **Market:** the Agency has been opened once |
| **Branches** | Nothing | Hospital Lv 5 (`Config.Rebirth.MinLevel`); then one line in the Shop, never a HUD door |
| **Belt and odds** | The belt, and one `Odds` text link. The odds sheet always lists every rarity with its percent (red line 3: odds are never hidden or collapsed) | A belt card you can't hire yet carries one State badge `🔒` and no banner (`"🏥 Epic+ from Lv "` goes). **Golden Hour and Night Rush banners:** as the HUD lines above |
| **Mini-games** | The exam, the treatment and the dispensary step for the Lv 1 cases (which cases is `-006`'s build, not this doc's). The title in words, the cards, one hint line | **The streak chip (`🔥 1`):** a streak of 2 |
| **Mailbox, Goals** | Nothing until the first letter; then the letter and one `Open` button | **The Goals tab:** as the Goals door above |
| **Book, Badges, Play Gifts, Day Report** | Nothing | Each on its first content. The Day Report starts with three lines (patients treated, Cash, Stars); the rest join as their features unlock |

**How a door arrives:** it pops once into its fixed rail slot (slots never move: `HudZones`), with one line on the
Now card saying what it is. Doors arrive one at a time from a queue, never two together.

---

## 3. Online findings

| Source | What it is, licence | Worth taking | How it maps to our skills |
|---|---|---|---|
| [Creator Docs: UI and UX design](https://create.roblox.com/docs/production/game-design/ui-ux-design) | Roblox's own guide. Cite it, don't copy it (check the creator-docs repo's licence before quoting at length) | "Use vibrant hues for crucial text, buttons... and muted shades for less significant ones." "Excessive use of bright, moving elements might overwhelm and confuse players." "clean, minimalist UI that is particularly crucial for mobile interfaces." Icons carry "a visual identity that conveys meaning"; apply decisions "consistently... throughout the game" | These are R1, R2, R6, R7 and emoji rule 5. `game-ui-ux` has no line on icon meaning or clutter: this doc fills that gap for our game |
| [Creator Docs: Wireframe your layouts](https://create.roblox.com/docs/tutorials/curriculums/user-interface-design/wireframe-your-layouts) | Roblox's UI curriculum | "display UI elements contextually for different workflows"; "group UI elements from the same category together"; keep the count per category low | Backs "Sell and List behind More" and the ring that shows only while recharging |
| [DevForum: Designing UI, Tips and Best Practices](https://devforum.roblox.com/t/3074034) | A Roblox staff designer (Engine UI team), 2024-07-17 | Mobile first; scale for size and position, offset for icons and `UIStroke`; safe areas; standard patterns (HUD, modal, toast) | Already in `roblox-ui` and its `responsive-layout.md`. Nothing new to adopt |
| [tabooharmony/roblox-brain](https://github.com/tabooharmony/roblox-brain), skill `skills/gameplay/roblox-gui` | Community skill library, **MIT**, 193 stars when fetched | Its GUI skill is layout and device rules: "check every pair of elements that can appear together", reflow instead of shrinking. No visual-design rules | Overlaps `roblox-ui`; our `HudScreen.spec` already checks pairs. **Don't vendor** |
| [claudskills.com: roblox-ui-design](https://claudskills.com/skills/roblox-ui-design/) | A registry listing. **No author, repo or licence shown: don't vendor** | Agrees with this doc: "One object, state, or action gets the strongest contrast and scale"; "Prefer readable contrast and clear grouping over thick outlines or ornamental depth"; "Use simulator styling only when the game or art direction calls for it" | Same as `roblox-ui` "Visual quality gates" |
| [DevForum: emoji can't take TextColor3](https://devforum.roblox.com/t/let-emojis-in-text-objects-be-affected-by-textcolor3/50920), [emoji outlines](https://devforum.roblox.com/t/allow-outlines-on-emojis/2806249) | Community feature requests | Roblox draws emoji as its own images; they can't be tinted or outlined | The reason for emoji rule 7, and for `tests/Emoji.spec` (missing glyphs) |
| [DevForum: BuilderIcons font](https://devforum.roblox.com/t/robloxs-secret-buildericons-font-and-how-to-use-it/4620737) | A community thread about an icon font bundled with the client. **Not in Roblox's docs; not verified here** | A possible later source for chrome glyphs (close, lock, tick, gear) that take colour, in place of State emoji | Park it. Try one glyph in Studio before relying on it |

**The answer to "are there Roblox UI skills online":** yes, a few, but they cover layout and devices, which the
`roblox-ui` and `game-ui-ux` skills already in this repo (vendored from `gamedev-skills`, Apache-2.0) do as well or
better. None has taste rules for a kids' candy UI or any emoji rule. `roblox-ui` already names our exact fault
("UI looks generated: decoration substituted for hierarchy... remove effects; align, reduce nesting, fix density
and roles"). So: **vendor nothing new**. Use taste-skill §9/§14 and impeccable's `distill` and `critique` as the
review rubrics, with this doc as the brief that overrides them where they disagree (both say the brief wins; both
would ban emoji and saturated colour outright, and Joshua has ruled to keep both).

---

## 4. The change list, by impact

Sizes: S under an hour of agent work, M a few hours, L most of a day.

| # | File | What changes | Size |
|---|---|---|---|
| 1 | `UI/Kit.luau`, `UI/Theme.luau` | `Juice.LOOKS.Secondary` and `Disabled` lose their stroke (R2). New parts so panels stop hand-building: `Kit.card` (fill only), `Kit.fact` (Soft text line), `Kit.bar` (8 px navy progress, no text), `Kit.toggle` (label + switch), `Kit.more` (Quiet "More"), `Kit.artTile` (Well + one 40 px emoji + optional State badge). `Kit.ring` draws nothing when full. `Kit.tab` unselected = no plate, no line. Theme: `Colors.Progress`, `TextSize.State = 18`, comments for the three voices | M |
| 2 | `UI/Icons.luau` (new) | The chrome emoji dictionary: Door, Unit and State icons by meaning, each emoji once. Panels read `Icons.Unit.Cash`, never a typed `"💰"` | S |
| 3 | `UI/Modal.luau` | Title is words only; the meta chip becomes plain Loud text (no box); the close button is 48 px and sits inside the band; tabs use the quiet `Kit.tab` | S |
| 4 | `UI/NursePanel.luau` | The Team card as drawn above. Summary chips become one Soft line (`3/3 working · 1 resting`). Journal cards: no card line, name in Normal, role as a Soft line without its emoji repeat, `NEW` as a flat State badge. `Pure.TEXT` loses its leading emoji; `Pure.jobButton` returns one emoji at most and the wait note moves to `Pure.jobNote` | L |
| 4b | `UI/Hud.luau`, `shared/Logic/HudZones.luau` | **R0: the reveal carries on after the tutorial.** `Pure.reveal` returns one flag per door (Nurses, Gifts, Goals, Mail, Status, Event) from the player's snapshot instead of one `Rest`. A replay, or an older save that already has content, keeps its doors. A queue shows one new door at a time | M |
| 4c | every panel | **R0: tabs, links and card facts with nothing in them are not built.** Each panel's pure block gets a `Pure.visible(state)` that lists what shows; the builders read it | S each |
| 5 | `UI/Hud.luau` | Settings becomes one list of `Kit.toggle` rows and Quiet links (Badges, Top, Replay tutorial, Admin). Status lines: one Unit icon each, no doubled `"☀️ 🌙 in "`. Toast and confirm strings lose leading emoji | M |
| 6 | `UI/BranchPanel.luau` | Section headings as words; one Primary (`Open branch`, hold); cards without lines; `🏙️` goes | M |
| 7 | `UI/Shop.luau` | Rows on `Kit.card`; the note is words (`3 beds · 2 decor spots`); the price button is the only button; gates per the table above; "how to earn" lines lose their bullets | M |
| 8 | `UI/AgencyPanel.luau`, `UI/MarketPanel.luau`, `UI/BeltView.luau` | Confirms per the table; one identity icon per sheet; odds rows keep their rarity Art and percent (red line 3: odds stay fully visible), nothing else | M |
| 9 | `UI/MiniGames.luau`, `UI/Tutorial.luau`, `UI/Guide.luau` | Header in words, no `🔥` chip emoji, plain step dots, hints in words. Tool and item cards untouched. Tutorial pointers keep "Tap 🛒" (a Door noun) | M |
| 10 | `UI/Mailbox.luau`, `UI/BookPanel.luau`, `UI/BadgeBook.luau`, `UI/PlayGifts.luau`, `UI/DayReportPanel.luau`, `UI/Boards.luau` | Rules R1 to R3 and the emoji rules; `🎁 Open!` becomes `Open` on a Collect button | M |
| 11 | `UI/Celebrate.luau`, `UI/Toasts.luau` | Only the dictionary (same Unit icons) and "never two emoji side by side" (`"💰⭐ ×"`). Otherwise left loud | S |

Order inside each task: R0 first (what is on screen at all), then the card and emoji rules on what is left.

Out of scope: `AdminPanel.luau` (only admins see it), the world signs and billboards, the 3D look.

## 5. The build split

⚠️ Six other agents are editing this worktree today. Start this build only after their work is merged, from a fresh
branch, so file ownership below is real.

| Task | Owns (nobody else edits these) | Needs |
|---|---|---|
| **T0 Foundation** (runs first, alone) | `UI/Theme.luau`, `UI/Kit.luau`, `UI/Modal.luau`, `UI/Icons.luau`, `tests/uirules.luau`, `tests/UiRules.spec.luau`, `tests/Chrome.spec.luau`, new `tests/EmojiRules.spec.luau`, `game/README.md` (UI section) | this doc |
| **T1 Nurses** | `UI/NursePanel.luau`, `tests/NurseUI.spec.luau` | T0 |
| **T2 HUD** (and the reveal, change 4b) | `UI/Hud.luau`, `shared/Logic/HudZones.luau`, `UI/Toasts.luau`, `UI/Wayfinder.luau`, `UI/Boards.luau`, `tests/HudScreen.spec.luau`, `tests/HudZones.spec.luau` | T0 |
| **T3 Money panels** | `UI/Shop.luau`, `UI/AgencyPanel.luau`, `UI/MarketPanel.luau`, `UI/BeltView.luau`, `tests/Agency.spec.luau`, `tests/Market.spec.luau`, `tests/Belt.spec.luau` | T0 |
| **T4 Play flow** | `UI/MiniGames.luau`, `UI/Tutorial.luau`, `UI/Guide.luau`, `UI/LiftPanel.luau`, `tests/MiniGame.spec.luau`, `tests/Tutorial.spec.luau` | T0 |
| **T5 Progress and rewards** | `UI/BranchPanel.luau`, `UI/BookPanel.luau`, `UI/BadgeBook.luau`, `UI/Mailbox.luau`, `UI/PlayGifts.luau`, `UI/DayReportPanel.luau`, `UI/Celebrate.luau`, `tests/BranchUI.spec.luau`, `tests/Book.spec.luau`, `tests/Badges.spec.luau`, `tests/ProgressionPanels.spec.luau` | T0 |
| **Integrator** (runs last, alone) | merges; tightens the ratchets; the Studio captures; `STATE.md`; the ruling record once Joshua says yes | T1 to T5 |

Rules for every task: a panel may **call** `Hud.portrait`, `Hud.format` and Kit, never edit them. If a panel needs a
Kit part that T0 didn't ship, it asks the integrator; it doesn't add a local copy (`uirules` `LocalHelper`). T0 keeps
every old Kit and Theme key working, so T1 to T5 can land in any order. The spec files named are the ones that read
each task's files today; if another spec reads an owned file, the owner of the file fixes that spec.

## 6. The checks

**Every task, before it reports:** `selene src`, `stylua --check src`, the Lune specs (`tests/run.luau`), and
`rojo build`. Its own spec plus `UiRules.spec` green.

**New rules in `tests/uirules.luau` (T0), each with the usual `-- uirules: allow <Rule>` escape:**
- `TitleEmoji`: a modal `Title = "..."` with any emoji.
- `LabelEmoji`: a string literal with more than one emoji (allowed: odds rows, tutorial pointers, `shared/Data`).
- `LeadEmoji`: a literal that starts with a gesture, face, tick or party emoji (`👆 👇 ✋ 👀 ✅ 🎉 ✨ 🤝`...).
- `TypedEmoji`: a Unit, Door or State emoji typed in a panel file instead of read from `UI/Icons.luau`.
- `SpaceLiteral`: a number passed to `Kit.pad` or `Kit.list` that isn't in `Theme.Space.Step`.
- `StrokeBudget`: a ratchet. Today's `Kit.stroke` counts (NursePanel 21, Hud 12, BranchPanel 11, MarketPanel 9...)
  are written into the spec and may only go down; T1 to T5 each lower their own number, the integrator locks it.

**New spec ideas:**
- `EmojiRules.spec`: every value in `UI/Icons.luau` is unique (one emoji, one idea); no emoji from the
  no-glyph list (`Emoji.spec`); every `Pure.TEXT` table in the UI has at most one emoji per entry.
- `NurseUI.spec`: `Pure.jobButton` has at most one emoji for every job and state; Sell and List texts have none;
  a Team card spec has exactly one filled button.
- `Chrome.spec`: only Primary, Collect, Destructive and Icon looks carry a stroke.
- `HudScreen.spec`: each Settings row is a toggle or a Quiet link; no row label changes its words with state.
- **"A fresh save is simple" (R0), the most important new spec.** For a brand-new snapshot (Lv 1, tutorial just
  done, no nurses, no mail): `Hud.Pure.reveal` shows at most 3 doors and 1 Status line; each panel's
  `Pure.visible` shows no tab or link whose feature is locked; a one-nurse Team card has 1 button and at most 2
  facts. And the other way: a rich save (Lv 5, nurses, a branch) still shows everything, so nothing is lost.
- "One primary per view": each panel's pure block lists its buttons with roles for a sample state; the spec asserts
  at most one Primary or Collect per card and per view.

**In Studio (the integrator, one session, with Joshua watching as he asked):** every panel at **568 x 320** (the
phone floor) and **1280 x 720**, plus 640 x 360 for the HUD. Two saves each: **a fresh Lv 1 player** (count what is on screen against the Lv 1
table) and a rich save. A before and after pair per screen goes in
`logs/playtests/2026-11-17-ui-direction/`. The pass test per screen is IMP's squint test: blurred, you can still
point at the one thing to press. Then taste-skill §14's boxes that apply to a game UI (shape lock, colour lock,
button contrast, no wrapped button labels, decorative dots zero, cards omitted where spacing does the job).

## 7. For Joshua to decide (goes to `context/OPEN-QUESTIONS.md`)

1. **Sell and List behind "More"** on the Team card: yes, or keep them on the card as two Quiet text buttons?
2. **Panel titles without their emoji** (`Team`, not `👩‍⚕️ Team`): yes?
3. **The emoji collisions** in rule 5: the proposed winners (`🏥` for level, `📖` Book, `📬` Mail, `🔁` again,
   `🏢` Branches only, `⭐` Stars only), and which icon the Agency gets.
4. **Progress in navy** instead of green: yes?

5. **The reveal triggers** in the Lv 1 table (Nurses, Goals, Mail, Gifts, Golden Hour, Agency, Market): any he
   wants earlier or later?
6. **Players with older saves** keep every door they already have content for (proposed), so nothing vanishes.

A yes becomes a ruling in `memory/records/` (it refines `memory-20261117-001`'s "calmer UI"; it supersedes nothing).
