# Depth update (Update 1): treatment mini-games, recipes, pet nurses, hospital levels, juice, performance

**Why.** Joshua played the live build on an alt (2026-11-16): "a bit laggy… the process to treat is too simple…
we can hire pet nurses (through a rolling feature)… the UI… is a bit mundane. the game needs a little bit more
complexity." His choices are in `memory-20261116-011`. Hospital levels were already ruled as Update 1
(`memory-20261116-008`), and they're the spine nurses and recipes hang off, so they ship together here.

**Who it's for:** kids 5–12 on phones and tablets (big taps, short words, no fail states) who come back daily
because it's fun (`-003`). It's not AFK: everything happens while you play.

## 1. Treating v2: recipes + mini-games
**Today:** hold at a station → carry → one tap at the Counter → bed → cured.
**New:** the patient's badge shows a **recipe** (1–3 items). You make the items as now (the tray holds them). At the
Counter, **Treat** starts the patient's **mini-games**, one per recipe item, in order. Then the patient goes to bed
and is cured.

| Item | Mini-game (3–5 s, touch and mouse) | Perfect when |
|---|---|---|
| 🧪 Potion | **Pour:** hold to fill the bottle, let go in the green band | release inside the band |
| 🩹 Plaster | **Patch:** 3 sore spots appear on the creature, tap each | all 3 within the time |
| 🛁 Bubbles | **Scrub:** bubbles pop up around the creature, tap to pop them | ≥ 6 bubbles |
| ☕ Cocoa | **Cool:** tap to blow when the steam ring is biggest, 3 times | 3 good timings |

- **Ratings: OK / Good / Perfect.** Never a fail: OK still cures. Perfect adds a small cash tip and +1 **combo**;
  combo multiplies tips (×1.2 / ×1.5 / ×2 at 3 / 6 / 10), and a non-Perfect resets it. Cash only (never Stars, Book
  or story).
- **Recipes by wing:** Starter 1 item · Bath wing 2 · Winter wing 2 · Night 2 · Garden 3 · Regulars their own. The
  first tutorial patients stay at 1 item. `Data/Ailments` gains `Recipe = { ItemId }`, and badges show the recipe as
  small icons that tick off.
- **Server authority:** the client plays the mini-game and reports a rating. The server accepts it only if the
  player is at the Counter, carries the items, and the report came after a minimum duration. The tip is capped per
  cure and there's a rate limit, so a cheater gains at most a small tip.
- **Reduced motion / calm:** mini-games keep working with gentler animation. A **Simple mode** toggle in ⚙️ turns
  every mini-game into one tap rated Good (for very young kids).

## 2. Pet nurses: the Nurse Belt (shared, in town; `memory-20261116-012`)
Not a blind capsule: **nurses ride a conveyor belt in the town plaza and you buy the one you see**, with cash.

- **One shared belt per server** (like the trending belt games): everyone sees the same nurses ride by and anyone
  can hire one. Each nurse shows its **rarity frame, role, level-1 stats and price** as it passes. Tap **Hire** (or
  walk up and press the prompt) to buy it, and it walks to your clinic.
- **They come at set times:**
  - **Every 6 s** a nurse steps onto the belt. Each takes about 30 s to ride the whole belt; one nobody hires falls
    off the end.
  - **Rarity odds** for each new nurse are printed on the belt sign: Common 70% · Rare 24% · Epic 5% · Legendary 1%.
  - **Night Rush:** during each in-game night (every ~10 min), Rare+ odds double, shown on the sign. It runs on the
    game's own clock, not a real-world timer (red line 3: no FOMO timers).
  - **Legendary shout:** an Epic or Legendary stepping on gets a server-wide shout and a glow so everyone looks.
- **Fair for little kids:**
  - A Common or Rare nurse that someone else hires is quickly replaced.
  - Each player can hire at most one nurse every 3 s.
  - After **8 belt arrivals in a row without a Rare+**, the next one is Rare+. This is server-wide; it replaces the
    capsule pity.
  - Prices: Common 💰100 · Rare 💰400 · Epic 💰1,500 · Legendary 💰6,000 (scaled ×1.0–×2.0 by the hospital level of
    whoever is looking, so newcomers can always afford Commons).
- **No Robux** anywhere on the belt (red line 3).
- **Rarities, high ones on a server schedule** (the brother: "the server has these high rarities periodically"):
  Common · Rare · Epic · Legendary always possible; **Mythic** only during Night Rush; **Secret** only during a
  server-wide **Golden Hour**. Golden Hour starts every 20 minutes of server uptime, lasts 2 minutes, and is
  announced to everyone with a countdown banner. It runs on game time, never real-world dates. Every odd, including
  the event odds, is on the belt sign. Prices: Mythic 💰20,000 · Secret 💰50,000 (level-scaled like the rest).
- **The Nurse Journal** (a bestiary, which is why kids love the belt games, per the brother):
  - Every nurse has an entry: a **silhouette** until you've *seen* it ride the belt, full colour once *hired*,
    grouped by rarity, with a completion %.
  - Completing a rarity group gives a reward (cash + an exclusive decor or nurse hat; never Robux).
  - A "NEW!" celebration plays when a nurse is first seen and first hired.
  - The 👩‍⚕️ Nurses panel is the journal first, and equipping happens inside it.
  - Save: `Data.NurseIndex = { [NurseId] = "Seen" | "Hired" }`.
- **The cast:** about 16 original cute creature-nurses (5 Common, 4 Rare, 3 Epic, 2 Legendary, 1 Mythic,
  1 Secret), with placeholder names.
- **Nurses:** an original cast of cute creature-nurses (placeholder names, Joshua's to rename). Each has a
  **rarity**, a **role** and a **level** (1–5; hiring the same nurse again adds a level):
  - **Maker:** stands at a station and makes its item into a shared nurse tray every N s.
  - **Healer:** treats the front patient when the recipe items are ready (OK rating, so players still beat nurses
    with Perfects).
  - **Cheerer:** patients wait longer and tips grow a little while it's on duty.

  Speed, how much and how long scale with rarity × level.
- **Slots:** nurses work only when **equipped**. Slots = hospital level (1 at the Stand … 5 at Mega). Equipped
  nurses walk around the clinic; the rest live in the 👩‍⚕️ **Nurses** panel collection.
- **Only while you play:** nurses work only while the owner is in the server, so there's no offline income (`-003`).
- **Save:** `Data.Nurses = { [NurseId] = { Level, Copies } }`, `Data.Equipped = { NurseId }`.

## 3. Hospital levels (from `-008`)
| Lv | Name | Cost | Unlocks |
|---|---|---|---|
| 1 | First-Aid Stand | start | 1 nurse slot, 1 bed, queue 4 |
| 2 | Clinic | ⭐15 + 💰400 | walls + roof, 2 slots, 2 beds, Bath wing recipes |
| 3 | Hospital | ⭐45 + 💰1,500 | 2 floors + ✚ sign, 3 slots, Golden capsule, queue 5 |
| 4 | Big Hospital | ⭐100 + 💰5,000 | 3 floors, ambulance bay, 4 slots, 3 beds |
| 5 | Mega Hospital | ⭐200 + 💰15,000 | tower, neon sign, helipad, 5 slots, queue 6 |

- **The building:** a shell grows around the existing rooms (floors stack up, so it fits the 70×70 plot), built by
  PlotBuilder from the level.
- **The upgrade:** a big celebration (full-screen rays, confetti, the building pops and grows).
- **Rooms and levels:** room purchases keep their ⭐ gates, and a level is also required where it makes sense (the
  Garden at Lv 3).
- `Data.Level` (1–5); existing saves start at the level their rooms imply.

## 4. UI juice ("make it pop")
- **Count-up numbers:** cash and stars roll up, never jump. **Flying coins:** coins fly from a cured patient to the 💰
  pill, which bumps.
- **Celebration screens:** level-up, a new nurse, a set complete, room unlocked (rays + confetti + a big title).
- **Motion everywhere:** idle "breathing" on calls to action, a bounce on hover and press, panels slide and pop, toasts
  slide in, red dots bounce.
- **Sounds:** a sound for every UI action, roll, mini-game hit and rating (built-in or Creator Store sounds).
- **Rarity frames:** they shimmer (Common grey, Rare blue, Epic purple, Legendary rainbow).
- **Feedback over every creature:** a mini-game rating pop ("PERFECT!" in big outlined text), combo counter.
- **Kit and Theme stay the toolkit:** new pieces (`Kit.countUp`, `Kit.celebrate`, `Kit.rarityFrame`) live there.

## 5. Performance (measure first)
- **Measure on a real client:** Settings → Performance Stats (FPS, ping, memory) on PC and on a phone.
- **Likely costs to remove:**
  - The server moves every creature by setting Root.CFrame each frame, so it replicates per frame. Move the creature
    animation to the client: the server sets the state and target, and each client tweens.
  - A Highlight on each night creature; PointLights casting shadows.
  - Per-frame client loops that never sleep.
- **Budget:** 60 fps on a mid phone with 6 full plots. Parts per plot ≤ 400; at most 1 Highlight in the world;
  lights without shadows.

## 6. Hospital v2: floors, elevators, departments (`memory-20261116-014`, after §3 lands)
§3 grows a building shell; v2 makes the floors **playable**.

| Floor (unlocked by level) | Department | What's new to do |
|---|---|---|
| Ground (Lv1) | Reception + First-Aid stand | today's loop; the Counter becomes Reception (triage starts here) |
| Ground (Lv2) | **A&E** | an **ambulance** pulls up with an urgent patient (siren, flashing light, stretcher). It skips the line, needs a 2–3 item recipe, waits less, pays ×3 + Stars. Kid-safe: bumps, wobbly tummies, nothing gory |
| Floor 1 (Lv2) | **Wards** | beds move upstairs: after treatment you **escort** (walk) the patient by elevator to a free bed, or a nurse does it; more beds per level |
| Floor 2 (Lv3) | **Hydro & Bath** wing | Bath recipes; a bubbly hot tub mini-game |
| Floor 3 (Lv4) | **Winter wing** / Pharmacy | a Pharmacy station that crafts 2-item medicines (Potion + Cocoa → Warm Tonic) |
| Roof (Lv5) | **Garden + Helipad** | **air-ambulance** VIP patients now and then (rare creatures for the Book) |

- **Elevator:** a glass lift with a big button per floor (a ProximityPrompt plus a floor picker UI), about 2 s per ride,
  with a little ding. Stairs too. Patients and nurses use it as well, which is fun to watch.
- **Triage:** at Reception each patient's badge shows its **department** icon. You send them (tap a department) or a
  nurse does; the wrong department is never a fail ("Oops, not this floor!").
- **More depth:** departments have their own upgrades (A&E Speed, Ward Comfort), and nurses can be assigned per
  department.
- Placement stays inside the 70×70 plot, built upward. It must keep the plot contracts and run within the perf
  budget (floors are simple slabs + glass; lights without shadows).

## 7. Progression v2: nurses with jobs and abilities, a rarer belt, rebirths with abilities (`memory-20261116-017`)
Builds on §2 (belt), §3/§6 (levels, floors). It ships right after the depth update merges.

**Nurses get real jobs, specialties and abilities** (the brother asked "what do the nurses do?"):
- **Jobs.** You assign each equipped nurse to a post:
  - Maker (at a station)
  - Healer (Counter or a department)
  - Porter (walks patients to ward beds by lift)
  - Receptionist (triage)
  - Cheerer (waiting room patience)
  - Medic (A&E)
- **Specialty:** each nurse is great at one department (e.g. a penguin nurse in Hydro: +40% speed there).
- **One signature ability,** stronger with rarity, with a visible cooldown and sparkle. Examples:
  - Common: "Quick Bandage" (every 60 s, finishes a Patch instantly)
  - Rare: "Calm Song" (pauses the line's patience for 10 s)
  - Epic: "Double Dose" (a cure pays ×2)
  - Legendary: "Golden Touch" (the next 3 treatments are Perfect)
  - Mythic: "Time Bubble" (all stations make instantly for 8 s)
  - Secret: "Miracle" (cures the whole line at once, once per day-cycle)
- **Nurse XP:** nurses gain XP by working and level 1→10 (plus duplicates). Levels raise stats and unlock an ability
  upgrade at 5 and 10.
- **Team bonuses:** 2+ nurses of one department give a set bonus, so who you equip matters.

**A rarer belt: "you need to feel like you earned it"** (the brother: in the belt games they come so often the rarity
feels cheap):
- A nurse steps on every **~40 s** (not 6 s); the belt also shows an empty "next nurse in…" track.
- Base odds: Common 75% · Rare 20% · Epic 4.5% · Legendary 0.5%.
- Mythic only in Night Rush, Secret only in Golden Hour, both much rarer.
- Higher rarities can also be **gated by progress:** Epic+ only appear for players at hospital level 3+ and
  Mythic/Secret after the first rebirth. Each player sees which rarities they can hire.
- The pity is longer (a Rare+ within 15 arrivals), and prices stay high.

**Rebirths = "Open a new branch"** (franchise), optional, never forced:
- **Requirement:** a Mega Hospital (level 5) + cash; the cost rises per rebirth.
- **Reset:** cash, upgrades, hospital level and rooms (the building starts again as a stand, in a new branch theme).
- **Kept, always:** the Patient Book, Nurse Journal, every nurse and their levels, badges, Doctor rank, decor and
  Stars, so nothing you collected is lost. A clear "you keep / you reset" screen comes first.
- **Each rebirth gives:**
  - **Rebirth Points** for a **Branch Ability Tree**. There are three branches:
    - **Care:** patience, tips, Perfect window.
    - **Speed:** make, walk and lift speed.
    - **Fortune:** cash, Stars, belt luck within the shown odds.

    Nodes have ranks, and capstones are powerful (e.g. "Twin Counters": treat two patients at once).
  - **A permanent cash/Stars multiplier,** +25% per rebirth.
  - **New content per rebirth:**
    - Rebirth 1: Mythic/Secret on the belt + a new creature wing.
    - Rebirth 2: an A&E upgrade (helicopter), the Pharmacy tier 2.
    - Rebirth 3: Golden patients (rare shiny creature variants for the Book).
    - Rebirth 5: a Legendary nurse only obtainable by rebirth.
  - **A new branch theme:** a cosmetic hospital skin (Candy, Arctic, Space, Jungle…).
- **Never Robux,** and no pressure to rebirth (red line 3).

## 8. Nurse Agency, Player Market, roster caps (`memory-20261116-018`)
Each source has its own job, so the belt stays the exciting one:
- **Belt** (§2/§7): random, a race, the only source of Legendary+ (events and rebirth gates).
- **Nurse Agency:** a server shop that **restocks every 5 min** (server-wide countdown).
  - Stock is 4 nurses, mostly Common/Rare, sometimes Epic, never Legendary+.
  - Each player can buy each listing once per restock, so there's no racing.
  - Prices are about ×1.5 the belt's.
  - **Sell-back:** the Agency buys any nurse for about 30% of its base price.
- **Player Market** (same server only):
  - List a nurse at a price inside a band set per rarity and level; anyone in the server buys it instantly.
  - The seller gets cash minus a 10% fee (a cash sink).
  - No item-for-item swaps and no haggling (scam-proof for kids). A listing ends when the seller leaves (the nurse
    returns).
  - Transfers are atomic on one server (both saves on that server, one update each, the listing locked), so there's
    no duplication. Cross-server markets are out of scope (dupe risk).
  - Never Robux.
- **Caps:**
  - The roster holds 30 nurses at first, +5 per hospital level, +10 per rebirth, up to 100 (never sold for Robux).
  - Equipped slots stay 1–5 by level, plus one Branch Tree node.
  - A full roster blocks hiring with "Roster full: sell, list or release one" (and its buttons).
  - The Journal keeps every nurse ever owned, so selling never removes an entry.

## Kids' rules (red line 3)
The belt is cash only; you see what you buy; the odds are shown and there's a pity guarantee. There are no fail states, no timers against the
player and no pressure to spend. Every motion honours Reduced Motion and the calm toggle, and Simple mode exists.
