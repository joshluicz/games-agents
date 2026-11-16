# Creature Clinic: the game design (v2, 2026-11-16)

> Working title. The real name is the brothers' call (OPEN #1). This replaces the shop-sim concept in
> `docs/plan/2026-11-16-game-plan.md` §1–2; that plan's road to money (§3), money rules (§6) and risks (§7) still apply.
> Rulings: `memory-20261116-003` (own place on a plot, kids back daily because it's fun, not a restaurant tycoon),
> `-004` (original absurd cast, no meme characters, no "brainrot" title at launch), `-005` (Creature Clinic, winter
> launch layer). Research: `docs/research/2026-11-16-*.md`.

## 1. Why
Joshua, 2026-11-16: the first version "is quite nice", but "the thinking behind it and the depth is very low". He
wants more of a simulator, a storyline, and expansion ideas, and the point is to **"keep the children coming back every
day because it's fun"**. He and his brother played the big restaurant tycoons: "they get boring after a few days [...]
you have afk for long to get the next upgrade [...] many kids cant afk cos theyre using their parent's ipad".

**The gap we fill:** a tycoon where **progress comes from playing, not waiting**, something new keeps arriving, and a
10-minute session on a borrowed iPad always ends with something gained.

## 2. Goals, non-goals, anti-goals
**Goals**
- Kids aged ~6–12 open it most days because they want to see who walks in, finish a story or unlock a room.
- Fun alone in 10 minutes; better with a friend.
- Fun enough for the 16+ players who decide whether kids ever see it (the Kids/Select trial is 16+ only).
- A winter build in time for the school holidays (~18–21 Dec), if hours allow (OPEN #5; hours are `../joshua-hq`'s).

**Non-goals (for now)**
- Trading.
- Stealing.
- Combat.
- Open building with free placement.
- AI-driven character chat (rated 18+).
- Paid random items.

**Anti-goals: it fails, even if it works, if…**
- Progress needs long AFK or leaving a device on.
- Missing a day costs anything (no streaks).
- It pressures a kid to spend (red line 3).
- It copies any game, meme or franchise (red line 2).
- It's scary enough to lose the Minimal/Mild rating.
- It's a wall of text a 6-year-old can't use.

## 3. Constraints that shape everything
- **Roblox Kids (5–8) sees only Minimal or Mild content.** The clinic is cartoon care: plasters, potions, warm baths,
  cuddles. **No needles, no blood, no surgery, nothing gross-out.** Night is mysterious, not scary.
- **Chat is off for many kids.** Co-op must work through stations, emotes and **custom Quick Words** (live 2026-10-13;
  they work at every age).
- **No reading required.** Ailments, treatments and goals are icons and colours. Any words are short, ≤ 6.
- **Mobile-first.** Big tap targets, no dragging, no precision timing.
- **First cure within 60–180 s** of joining (first-play bounce is a top discovery signal).
- **Playtime only counts up to 60 min a day**, so aim for more days, not longer sessions.
- **Money:** red line 3 and §6 of the plan. Nothing paid is random; nothing paid speeds progress (see §9).

## 4. Approaches considered (all decided 2026-11-16)
| Question | Options | Picked | Why |
|---|---|---|---|
| What a player owns | A one shared shop · **B your own place on a plot** · C a solo world | **B** (Joshua) | Ownership and watching your place grow bring kids back. Works solo. Friends bring friends |
| Theme | Restaurant · Night Inn · **Creature Clinic** · Glow Aquarium | **Clinic** (Claude, delegated; Joshua preferred it) | Restaurant lane is crowded but cold (~28K players across 7 top food tycoons). A horror animal hospital proved demand (1.3M peak), and no cozy clinic you own exists. Caring for creatures is an honest loop |
| Brainrot | Use meme characters · **our own absurd cast** · ignore | **Own cast** (Joshua) | Same energy, no IP risk (live lawsuit over a meme character) |
| Season | Christmas-centred · **evergreen core + winter launch wing** | **Layer** (Claude, delegated) | Ride the holidays without a game that dies on 26 Dec. Seasonal events measurably win players |

## 5. The game
### 5.1 Premise (one line, told through the world)
You're handed the key to a tiny clinic at the edge of the **Wildwood**, where odd creatures live. The sign says
*"Everyone welcome. Even the weird ones."* The old keeper who ran it has gone, leaving letters behind.

### 5.2 The patients (our absurd cast)
- **Original silly creatures** in the brainrot spirit: food-with-faces and hybrid critters. Examples for tone only;
  the brother designs and names them:
  - a toast-pup with a sunburn;
  - a dumpling-frog with hiccups;
  - a cloud-sheep that won't stop raining;
  - a jelly-cat that's gone flat.
- **Each patient shows its ailment as one big icon** (sneeze, hiccup, bump, spots, chill, lost glow…). The icon's colour
  matches the station that treats it.
- **Variants** (sparkly, night, winter) are *seen through play and events*, never bought.
- Silly sounds and a happy hop when cured are the payoff kids quote and share.

### 5.3 The core loop (seconds)
Patient arrives and queues → shows ailment icon → you **hold at the matching station** to make the treatment (Remedy
Bench, Plaster Table, Warm Bath…) → carry it → **give it to the patient** → the patient goes to a **recovery bed** for a
few seconds, glows, hops up cured → **cash + a Patient Book stamp**.
- A wrong treatment just gets a head-shake; nothing is lost.
- This is today's queue → station → carry → serve code, with item types and beds added.

### 5.4 The session (about 10 minutes = one clinic day)
- **Day:** regular patients, plus **Today's Visitor**, one featured creature of the day, the same for everyone.
- **Night shift:** spooky-cute night patients (a ghost with a cough, a moth that lost its glow). They pay 2× and glow
  softly.
- **End of day: a Day Report.** Patients cured, new Book pages, a progress bar to the next unlock, and one clear "next
  goal". It's a natural place to stop.

### 5.5 Progress from playing (no AFK)
- **Cash** buys three kinds of thing:
  - **upgrades**: Faster Hands, Bigger Tray, Comfy Chairs (more patience), Tip Jar;
  - **new rooms**: each adds a station, which brings new ailments and so new patients;
  - **decorations** from preset sets.
- **Clinic Stars** come from cures. Stars unlock wings and story beats. The first unlock lands in the first session.
- **No offline income.** On return, a small **mailbox** gift and thank-you notes from cured patients. It's the same
  whether you were away one day or ten.
- **Daily goals bank up** (up to 3 stored) and never expire into a penalty. **No streaks.**

### 5.6 The Patient Book (the collection)
- A page per patient type, stamped on first cure, plus variant stickers.
- Completing a wing's page set unlocks that wing's decoration set.
- The Book is the "gotta see them all" reason to come back. Everything in it is earned.

### 5.7 Regulars with stories (the storyline)
- **Three regular patients at launch.** Each has a **5-beat story**, told in pictures, emotes and speech bubbles of
  ≤ 6 words.
- **Timing (Claude's call, after the builder check).** A "story day" is a **real calendar day (UTC)**, not the
  10-minute clinic day. Each regular visits **at most once per calendar day** and advances one beat per visit.
  Regulars **unlock one after another by Clinic Stars** (the first from the start, then two more), then move forward
  in parallel. Finishing all three takes about a week or more of playing days, which is the come-back hook. The save
  stores `{Beat, LastBeatDay}` per regular. Example arc: a scared little creature who won't come inside →
  peeks in → gets cured → brings a friend → becomes your clinic's helper or mascot.
- **Beats wait for you.** Missing days skips nothing.
- Finishing a regular's story unlocks something visible: a room, a helper, a decoration.

### 5.8 The world story and expansions (the roadmap)
- The clinic grows **wings**. Each wing is a door into another part of the Wildwood, with its own patients, one new
  station, a regular with a story, and a decoration set.
- The old keeper's **letters** turn up as wings open, each hinting where they went. It's a slow mystery for live ops,
  never resolved quickly.
- **Launch: Winter Wing** (snow creatures with chills and sniffles, warm-bath and cocoa-remedy station, snowy decor).
  It stays in the game. Its winter variants and event come back each December.
- **Next doors (one per big update, every 2–3 months; small updates every 2–4 weeks):** Lagoon Wing (ocean) · Moon
  Wing (night and space) · Candy Wing (food-with-faces) · Garden Wing. The order is decided by what players respond to.

### 5.9 Friends
- Friends join your server (invite, Party) and **work your stations**. They earn their own cash and Book stamps; the
  cures count toward *your* Clinic Stars.
- **Who can work your clinic (Claude's call, after the builder check):** you, plus **your Roblox friends** in the
  server. A prompt on your clinic sign switches **"Open to all helpers"** on or off (off by default), so kids who
  aren't Roblox friends can still team up. Strangers can always visit and leave a heart, but can't touch your stations
  or patients unless you open up.
- **Quick Words** like "I'll do the bath!", "Bandage needed!" and "Night patients coming!" let kids coordinate with chat
  off.
- **Visiting:** walk round other plots and leave a **heart** on their clinic sign (one per visitor per day). It's a
  cosmetic count of how loved your clinic is.
- **A friend referral** gives both players a matching cosmetic, once.

### 5.10 Plots and building
- A server has a fixed number of plots (the builder sets it; **6 suggested**). You get one automatically on joining.
- You start with a **first-aid stand** under a tree. Rooms unlock into **fixed slots** on the plot; they're prebuilt
  modules from the brother.
- Decorations go in **decor slots**, picked from preset items. Free placement is a later upgrade if players want it.

## 6. Feel and look
- Cozy and bright, but not oversaturated. Readable silhouettes. Big, bouncy feedback on every cure (the `game-feel`
  skill).
- Spooky-cute at night: soft purple glow and gentle music, no jump scares.
- Thumbnails show real gameplay: a funny patient mid-cure, the clinic glowing at night.

## 7. Success measures (Creator Analytics)
- First cure under 3 minutes.
- **D1 ≥ 15%**, aiming at 20%. The median is 10.3% and the top 1% is 22.2% (GameAnalytics 2026).
- **D7 ≥ 5%**, against a 1.6% median.
- Sessions of 10–15 minutes.
- A second session on the same day is common (that's kids coming back after school).

## 8. What changes in the code (for the plan)
| Today | Becomes |
|---|---|
| `ShopWorld` (one `Shop`) | **Plots**: assign a plot on join, clone the starter clinic into it, free it on leave. Per-plot markers |
| `Customers` (one queue) | **Patients**: a queue per plot, ailment types, icons, beds, variants, Today's Visitor, night patients |
| `Kitchen` (one station) | **Stations**: several per plot, each making one treatment item type |
| `Economy` (carrying a count) | Carrying **typed items**; pay maths; upgrades (adds Comfy Chairs); room purchases |
| `PlayerData` | Adds clinic stars, rooms, decor, Book pages, story beats, banked dailies, mailbox, hearts. **Schema v2** with migration from v1 |
| `DayNight` | Keeps the cycle; adds the Day Report at day's end |
| `Hud` | Adds the Book, Day Report, room and decor shop, Quick Words setup (that's done in Creator Hub) |
| New | `Story` (regulars), `Daily` (Today's Visitor, banked goals, mailbox), `Visits` (hearts), `Events` (winter switch) |

Keep the other agent's recent work (Counter serve prompt, sparkles, music, roof fade) where it still fits.
**Data and Robux stay server-side. Every remote is validated** (CLAUDE.md).

**The brother's build:**
- the plot template with marker parts;
- the first-aid stand;
- room modules (Remedy Room, Bath Room, Ward with beds, Winter Wing);
- decor sets;
- the patient creatures (Assistant `/generate_mesh`);
- the cast's names.

`docs/guides/build-the-shop.md` gets rewritten for plots and rooms.

## 9. Money (Stage 1+, only after the ownership note and both brothers' yes)
- **Cosmetics only at first:** clinic themes, uniforms, a cosmetic helper pet. Fixed prices shown plainly. No paid random
  items, no timed offers, no "decline" shaming.
- **The 2× Cash pass stays** (Joshua, `memory-20261116-006`), under three rules:
  - it doubles **Cash only**, never Stars, Book stamps, story or dailies;
  - it's shown in the Shop only, never pushed (no pop-ups, timers or post-cure prompts);
  - cosmetic passes sit beside it.
  Revisit if the EU Digital Fairness Act proposal (2026-11-11) becomes law with its pay-to-progress ban for minors.

## 10. Release slices
1. **Slice 1, "First-Aid Stand" (private):**
   - plots for up to 6;
   - a stand with 2 stations (Remedy, Plaster) and 1 bed;
   - 4 patient types;
   - the cure loop and cash;
   - 2 room unlocks;
   - the Patient Book;
   - the Day Report;
   - save schema v2.
2. **Slice 2, "Winter Wing" (target: before ~18 Dec):**
   - night patients;
   - the Winter Wing with 4 winter patients and the bath station;
   - 3 regulars × 5 beats;
   - decor slots;
   - hearts and visiting;
   - Quick Words;
   - Today's Visitor, banked dailies, the mailbox;
   - icon and thumbnails.
3. **Slice 3, "Go public":** gated on the ownership note and both brothers' yes. The 16+ trial, Creator Analytics, a
   fixed weekly update day.

**What "in time for the holidays" means (Claude's call):** the code for Slices 1–2 is built now, by parallel agents.
The winter build should be **private and playtested by ~7 Dec**, leaving room for the gates. Whether it goes
**public** before ~18 Dec is the brothers' call, behind red lines 4 and 5. The smallest winter build worth shipping is
Slice 1 + night patients + the Winter Wing + 1 regular.

## 11. Left open
- **The brothers' call:** the game's name (OPEN #1) · the cast's names and looks (the brother) · the old keeper
  character · the 2× Cash pass (new OPEN).
- **The builder's call:** every tuning number · plot count and layout · exact stations per room · UI details · how
  carried items look · the order of wings after Winter.
