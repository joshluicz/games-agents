# Admin parties and soft return hooks: rules, how the hits do it, a design for us (2026-11-16)

Desk research for `memory-20261116-022` (Joshua, relaying his brother: soft return pressure is wanted, countdowns to
**free** events are OK, admin abuse events are a must for a future update, spending pressure stays out). Sources
fetched 2026-11-16 and 2026-11-17. Quotes are verbatim from the live pages. **M** = measured, with its source. Fan
wikis and guide sites disagree on times and numbers, so their lines are marked as such. Nothing here is decided:
the open points are at the end, for OPEN #9.

## 0. The short answer
1. **A countdown to a free event is allowed**, as long as it's accurate, it doesn't restart, and the event really
   happens. Roblox's countdown rules are written about purchases, and our version has no purchase anywhere near it.
2. **Rewards for liking or favoriting are out**, and so is "50K likes = admin abuse". No live rule names likes or
   favorites. But the Terms (effective 2026-11-01) say "You may not artificially manipulate the user review system",
   and a game can't check a like, so "like for a reward" misleads kids. A like goal for everyone is a grey area that
   the big simulators use and Roblox doesn't police. Red line 3 says to read the rules as they stand, so we don't.
   **Instead:** a town goal counted from our own data ("1,000,000 creatures cured, all servers together → a party").
3. **Asking players to favorite is fine**, through Roblox's own prompt, but it never pays and never gates anything.
4. **Admin events are allowed and suit Roblox.** Roblox's own Events docs suggest "exclusive event-specific merch or
   badges" as a reason to join. Ours runs every power on every server at once through MessagingService, takes its
   presets from Config, ends by itself and costs nothing. If no brother turns up, an Auto Party runs instead, so an
   announced time is always kept.
5. **Announce on Roblox only**: an in-game Party Board, the game page's Events section ("Notify Me") and update
   announcements. Discord and TikTok links can't appear in the game. A public event page is "said in the game's
   name", so it needs both brothers' yes (red line 4).

## 1. Policy, from the live pages

### 1.1 What each source says
| Source (live, fetched 2026-11-16/17) | Date on page | The lines that matter |
|---|---|---|
| **Terms of Use**, en.help.roblox.com/hc/en-us/articles/115004647846 (via roblox.com/info/terms) | "Effective Date: November 1, 2026" | Creator Terms §5.1: "You may not artificially manipulate the user review system for your UGC." · User Terms §9.2: you will not "circumvent, disable, fraudulently engage with any part of the Service" · Creator Terms §5.3.2: "You may not represent that you are authorized to moderate Users on behalf of Roblox." |
| **Community Standards**, about.roblox.com/community-standards (the help-centre copy refuses automated fetches) | none shown | *Repetitive and Misleading Content:* "Deceptive, sensational, duplicative, or otherwise misleading content or metadata [...] used to drive discoverability, monetization, or engagement" · *Contests & Sweepstakes:* "Users may not independently use Roblox content or systems to promote contests, games of chance, or player competitions where Robux or anything of real money value is offered as a prize." · *Directing Users Off-Platform:* "You may not link to, share, or display URLs of any external websites or services except by using the Social Links feature [...] Users must complete Roblox's age check process and be at least 16 years old to access the social links feature." |
| *(same page)* **Misusing Roblox Systems** | | The section covers evading safety systems, alt accounts, VPNs, account access, PolicyService and TextChatService, bots, hidden scripts, false reports and "Invading or flooding games or groups". **It says nothing about likes, favorites, ratings or votes.** No line on the whole page does |
| **Promo Offers for Virtual Rewards** (help article the Standards link to: en.help.roblox.com/hc/en-us/articles/10549651908244) | none | A free promo is OK only if "There is no exchange or transaction necessary for users to access or redeem the offer" and "You must make the redemption window clear to users anywhere your offer is promoted" |
| **"Experience Guidelines"**: the old URL now redirects to **Content ratings** (create.roblox.com/docs/production/promotion/content-ratings) | last_updated 2026-11-14 | IARC and maturity questionnaire only. Nothing on engagement incentives, timers or events |
| **Discovery** (create.roblox.com/docs/discovery) | | "Build trust - You should not rely on promotional monetary rewards to drive engagement." · "Leading with giveaways - Metadata that implies any type of monetary reward is not prioritized for recommendations." |
| **Monetization** (create.roblox.com/docs/production/monetization) | last_updated 2026-11-14 | "having items or events that are only available for a **limited time** can create excitement" · "appointment mechanics and timers which can be removed or brought forward [...] are unpopular with Roblox users" · "Users must never be misled, confused, or pressured into purchases" · "Don't claim that a subscription or item is almost out of stock or only available for a short time if it isn't true." · "Don't use a countdown timer that isn't accurate or automatically restarts for the same item." · "avoid using pushy or urgent messages when interacting with minors": avoid "GET IT NOW", "LAST CHANCE, ACT NOW", "BUY BEFORE IT'S GONE!" |
| **Experience notifications** (…/production/promotion/experience-notifications) | last_updated 2026-11-14 | For "opted-in users age 13+"; "each user can receive one notification per day from a given experience". "Notification content is **not** permitted to incorporate dark patterns", including "**Time Pressured Actions**" and "**Bait-and-Switch with Free Items or Other Rewards**". "Games should **not** require users to turn on notifications in order to participate or advance in gameplay." Notifications should be "**personalized**" and "should not be of a generic, advertising nature" |
| **Experience events and updates** (…/production/promotion/experience-events) | last_updated 2026-11-14 | A description can include "Incentives for players to join such as exclusive event‑specific merch or badges". Players tap "**Notify Me**" for upcoming events. "Currently, you can publish a maximum of 10 ongoing or upcoming events." On a user-owned game only its "sole owner" can create them (Joshua). Update announcements: "a limit of 60 characters and you can only announce an update once every three days". Trending Events needs "Minimum of 1,000 RSVPs". On a join from an event, "the event ID is added to the player's `GameJoinContext`" |
| **Roblox Kids and Select: reward-driven media feeds** (devforum.roblox.com/t/4829188, Roblox account) | 2026-08-25 | "Rewarding users to consume a continuous feed of content without natural stopping points is not appropriate for younger users." Doesn't apply to us (no media feed), but it's the clearest recent line on design for under-13s: **give a natural stopping point** |
| **Text filtering** (…/docs/ui/text-filtering) | last_updated 2026-11-14 | "you are responsible for filtering any displayed text that you don't have explicit control over" · `GetNonChatStringForBroadcastAsync()` is "for filtering text visible to all users in a game". A game that doesn't filter can be removed |

**The DevForum (community, not official).** I found no 2025-2026 staff statement on rewards for likes.
- devforum.roblox.com/t/1029127 (2021) quotes an older rule that is **no longer on the live page**: promo codes are OK
  "so long as they are not in exchange for something (e.g., in exchange for a thumb up on your game)".
- devforum.roblox.com/t/4495969 and /t/4524009 (March 2026) show the community split. One poster calls like-for-reward
  "super against ToU but due to zero moderation it never gets enforced". Another notes that games ask for
  "like AND favorite AND join the group" and check only the favorite and the group, so kids think the like is checked.
  The favorite check also needs `PromptAllowInventoryReadAccess` (a permission prompt).

### 1.2 What that means for each idea
| Idea | OK for us? | Why |
|---|---|---|
| "Like the game → get X" (each player) | ❌ | A like can't be checked, so the promise is misleading ("Deceptive [...] used to drive [...] engagement"). Paying for a rating is "artificially manipulat[ing] the user review system" (ToS §5.1) |
| "50K likes = admin abuse" (a goal for everyone) | ❌ (our reading) | No live rule names it, and the hits do it. But it puts a reward on the review system, and Roblox's "build trust" line points the other way. With a child audience we take the strict reading. Use a **town cure goal** instead |
| "Favorite → get X" | ❌ | Same review-system problem, plus an inventory-read permission prompt just to check it (red line 3: no collecting data) |
| A calm "⭐ Favorite to find us again" prompt (`AvatarEditorService:PromptSetFavorite`), no reward | ✅ | Roblox's own API. Once a session at most, never mid-task, never gating |
| A reward for joining a group | ⚪ Not now | Not banned. But the game has no group yet (ownership note, `-010`), and rewarding a platform action is the same kind of thing as the like rule |
| A reward for turning notifications on, or gating on it | ❌ | "Games should **not** require users to turn on notifications" |
| A countdown to a **free** event (party, Golden Hour, Night Rush) | ✅ (`-022`) | Accurate, no restart, and the event happens (Monetization's countdown lines, applied to events too) |
| "Next update" countdown | ✅ only when the date is certain | A countdown that slips is the "isn't accurate" case. Without a date, the board says "coming soon" |
| A free gift you get only if you're there | ✅ softened | Roblox's events doc suggests exclusive event rewards. GAG's design relies on it ("exclusive items are released weekly that players must be online to claim", Wikipedia). We soften it: the gift reaches every server, lasts the whole party, and comes back in a later party (§3.6) |
| Anything paid during or tied to a party | ❌ | Red line 3, `-022`. No Robux prompt, no "only N left", no paid power |
| Admins typing messages to every server | ⚠️ presets only | Free text must be filtered for broadcast. Preset lines ("👋 Hi from the Head Doctors!") need no filtering and can't go wrong |
| "Join our Discord / TikTok for the time" in the game | ❌ | Off-platform links are banned in game. Social Links (game page, 16+ age-checked only) is the only place |
| Calling the hosts "Roblox admins" or looking like Roblox staff | ❌ | ToS §5.3.2. They're "Head Doctors" (or whatever name the brothers pick) |

## 2. How the top games run admin abuse (2025-2026)

### 2.1 Game by game
| | Grow a Garden (GAG) | Steal a Brainrot (SAB) | Plants vs Brainrots (PvB) | Grow a Garden 2 |
|---|---|---|---|---|
| **When** | Saturdays with the weekly update; extras: "Watering Wednesday" (from 2026-04-15), rare "Stormy Sundays" (fan wiki). An extra day was picked by a Discord poll (gamepressure, 2025-09-24) | Saturday update (usually 3 PM ET) + **Taco Tuesday** 6 PM ET (fan wiki) | "three times per update: once before the patch lands, and twice afterward" (allthings.how, 2025-11-22) | "Admin Party": first 2026-08-01, 30 min, no fixed schedule (eldorado.gg, 2026-08-07) |
| **How long** | 60-90 min; big Saturdays 2-3 h (mygagcalculator, 2026-05) | 30-60 min, "or whenever Sammy is done with his tacos" (fan wiki) | ~1 h per session | 30 min |
| **Announced** | Official Discord; X for polls; a global in-game message during. "Not every session gets announced in advance" | Discord; "early bird" present (usually a Secret Lucky Block) to people playing ~1 h before | Discord, plus the **Roblox event card**, which "automatically localises event times" | Discord, "with short notice" (allthings.how, 2026-06) |
| **Powers** | Admin-only **weathers** with special mutations (Disco 125×); **restocks** of the seed and gear shops; free seeds, pets and "Admin Packs"; mini-games ("A Giant Wasp is invading the garden! Shoot it down for Admin Packs!"); free cosmetics for everyone ("Everyone gets a free Duckfloat cosmetic!"); "Every garden grows 1.5x faster!"; celebrity guests | **Luck multipliers** (e.g. 15×); spawns rare brainrots and **"Raining Lucky Blocks"**; "Sammy's Snap" (he grows huge, snaps, and almost every event starts at once); his floating base; themed events | An **Admin Abuse Chest** that "bakes in your week's progress and then pays out when Admin Abuse begins"; exclusive spawns; weathers; restocks; server-wide luck and XP boosts | "Party Points" from presents, checkpoints and mini-games; a reward every 30 points; an Admin Chest at 600; lucky restocks; mini-games |
| **Which servers** | "Every active server experiences the same weather at the same time" (GAG wiki, Weather). **Public servers only**: private servers get no admin events | "across all servers simultaneously" (guides). **"Random Server Spawns"**: Sammy picks N servers ("50 servers") for a rare spawn | "every server, including private ones" | public servers (guides) |

### 2.2 The patterns
1. **One clock for everyone.** Every hit ties its admin event to a fixed weekly slot, usually the Saturday update,
   and adds a second weekday as it grows. The habit (it's Saturday, so there's a party) does as much work as any
   single reward.
2. **The host is in one server, the effects are in all of them.** Weather, luck and restocks land on every server at
   once. GAG adds a global message showing the admin's name. SAB adds "Random Server Spawns", a lottery between
   servers. Neither publishes how it works. MessagingService is the obvious tool: Roblox's own docs list "Global
   Announcements" to "all the game's servers" as what it's for.
3. **Powers turn the dials the game already has**: weather, odds, restock speed, multipliers, spawns, and the admin's
   own avatar (giant Sammy, a ban hammer). The admin uses existing systems, just louder.
4. **A show with a story.** The **Admin Abuse War** of 2025-08-23 was a staged feud: Jandel versus "Scammy" with a
   "Thief" sign, a giant stomp and Green Bean helpers (GAG wiki). It was hyped on "TikTok, X, and Discord"
   (Tubefilter, 2025-08-25).
5. **Show up to get it.** An early-bird gift (SAB), costumes worn during the event (GAG's Elder Bean outfit), or a
   chest that pays only at the start (PvB).

### 2.3 What worked: the numbers (**M**, sources differ)
- **2025-08-23, the Admin Abuse War (a Saturday):**
  - Tubefilter (2025-08-25): GAG 21.1M concurrent, SAB "set its own new record at 20 million", Roblox as a whole
    47.4M, its highest yet.
  - Wikipedia (Grow a Garden, RoMonitor's number): GAG peaked at 22.3M. The GAG fan wiki says 23,375,000 against
    20,619,000.
- **SAB's later records:** 24M on 2025-09-13 with its "Extinct Event", and 25.4M in October 2025 (Wikipedia, Steal a
  Brainrot). 2025-09-13 was a Saturday, SAB's update and admin day. In January 2026 a Bruno Mars concert event peaked
  at 12.8M concurrent.
- **The baseline:** both games had "dropped back down to their usual ~1 million concurrents" days later (Tubefilter).
  The event spike is many times the normal day.

### 2.4 What went wrong, or what we won't copy
- **Overload:** "Roblox went down several times" (GAG wiki, Admin Abuse War); "a few crash issues" (Tubefilter).
- **Scarcity among players:** guides say restocked seeds sell out in 60-90 s, so kids race each other.
- **Paying to skip the wait:** GAG's seed shop "refreshes every 5 minutes" and players "can always purchase a restock
  for 79 Robux (or watch ads)" (GAG wiki, Seed Shop). Wikipedia: Robux "can be used to speed up waiting".
- **Selling admin powers:** Wikipedia sums up Polygon's criticism of SAB's pay-to-win design: "the best items are
  only available for cash", with "server administrator" abilities on sale.
- **Private servers left out** (GAG): an event that skips paid private servers punishes people who paid.
- **Hosts going off-script:** a guest stocked a limited Transcendent seed and "almost got his admin commands revoked";
  another host stocked "too many Blueberries [...] to ragebait players" (GAG wiki).
- **Kids missing out:** a parent's blog (Medium, @jo.normal; search excerpt only, the page refused the fetch)
  describes tears after her son missed an event because of real-life plans.

## 3. A design for us: the Doctor's Party (working name)
The brother's idea stays whole: the brothers join a server and use fun powers for everyone. The changes make it
safe for kids, fair to every server, and honest about time. "Admin abuse" is fine with 16+ players, but next to a
children's hospital it reads badly to parents. GAG 2 itself moved to "Admin Party". **The name is the brothers' call**
(§5).

### 3.1 Shape
- **When:** a fixed weekly or fortnightly slot (OPEN #9), 30-45 min, never longer than `MaxMinutes` (60).
- **Who:** one brother hosts live from the 🛠️ panel. If nobody has started it **5 min after** the announced time, the
  **Auto Party** runs the same powers on a script, so the board never lied. A live host is a bonus, not a promise.
  This also keeps hours off this repo (red line 6).
- **End:** a clear finish: "🎉 Party's over! Thanks for coming", plus the next date if one is set. That's the natural
  stopping point.

### 3.2 Powers that fit a creature hospital
Each one has preset values and a time limit from `Config.Party`, and every one works through a system that exists
today.

| Power | What everyone sees | Limit (proposal) | Hooks into |
|---|---|---|---|
| 🌙 **Party Night** | Night on every server now: fireflies, night patients, Night Rush odds, ×2 night pay | one night | `DayNight` (`SkipPhase`), as `SkipToNight` does |
| ❄️ **Snow Day** | Winter on: snow, Frosty patients | 15 min | `Events` (needs a live-safe version of `ForceWinter`) |
| 👑 **Golden Belt** | A Golden Hour on every server at once; the odds sign shows the event odds | 5 min | `NurseBelt` (needs `setGolden(untilTime)`: `ForceGolden` is Studio-only) |
| 💰 **Double Pay** | 2× 💰 and ⭐ per cure for everyone | 15 min, 2× max, no stacking | `Boosts.multiplier` (needs a server-wide party factor) |
| ✨ **Sparkle Storm** | Many more Sparkly patients (they pay 2×) | 10 min; `SparklyChance` 3% → 25% | `Patients` (reads `Party.active`) |
| ⭐ **Visitor Parade** | Today's Visitor (×3 pay) visits every clinic | once | `Daily` / `Patients` |
| 😌 **Calm Clinic** | Patience never runs out | 10 min | `Patients` (patience, as in the tutorial) |
| 🦕 **Big Sneezer** (co-op "boss") | A giant original patient in the plaza; everyone brings 🧪 🩹 🧼 ☕ until it's cured, then a gift for everyone on that server | once a party | `CreatureBuilder` (scale) + a plaza Counter; our version of GAG's Giant Wasp |
| 🎉 **Cheer** | The Celebrate screen + a preset line from the host | 1 per 30 s | `Celebrate`, `Remotes.toastAll` |
| 🎁 **Party Gift** | Everyone who plays during the party, on any server, gets that party's decor + a little 💰, once | once per party id | `Economy.addCash`, decor ownership, a new save field |

**Left out on purpose:** free hospital levels, rare nurses handed out directly (both break the economy), lotteries
between servers (SAB's random spawns), anything that opens a Robux prompt, and free-text broadcasts.
**Tutorial players:** powers that change pay still apply to them. Banners wait while they're quiet (as
`Remotes.news` does), and tutorial patients are never giant, sparkly or extra.

### 3.3 Every server at once
One party = one id, a short list of powers, each with an `EndsAt` time. Three pieces:

| Piece | Job | Budget (Roblox's numbers, docs 2026-11-14) |
|---|---|---|
| **MessagingService** topic `Party_v1` (Studio: `Party_v1_studio`) | Pushes each start, power and end to every server, "typically within 1-2 seconds" | 1 KB a message; receiving is capped at "(40 + 80 * number of servers) per minute" per topic. A party sends ~20 messages in all |
| **MemoryStore** hash map `Party`, key `Live` (TTL ≤ 2 h) | The truth about the party now. Every server reads it **at start** and **every 20 s**, so a missed message or a server that opens mid-party catches up. "Delivery is best effort and not guaranteed" (MessagingService docs) | 3 reads a minute a server, against "1000 + 120 * [number of concurrent users]" units a minute for the whole game. Studio and live data are "isolated" |
| **DataStore** `Party_v1`, key `Schedule` | The next parties (id, start in UTC, minutes, title, Auto preset). Servers read it every 5 min, and again on a `ScheduleChanged` message | ~12 reads an hour per server |

- **Effects end by themselves.** Every power carries its `EndsAt`, so a lost "end" message still ends it everywhere.
- **Every message is checked like a remote:** a known power id, a known version, and `EndsAt` clamped to now +
  that power's limit. A bug can't push 100× cash.
- **The Auto Party needs one winner.** At `StartsAt + 5 min` with no `Live` key, servers race an `UpdateAsync` on
  `Live`, and only the one that writes it starts the timeline.
- **What clients see:** Workspace attributes per server: `PartyOn`, `PartyEndsAt`, `PartyPowers` (a list, e.g.
  `"GoldenBelt,DoublePay"`), `NextPartyAt`. Times are `GetServerTimeNow`, as Golden Hour does today.
- **Studio never touches live:** a separate topic, the MemoryStore is isolated anyway, and Studio never writes
  `Schedule`. With API access on, a Studio DataStore write goes to the live store, as the README warns for the boards.
- **Every server, private servers too** if they're ever turned on.
- **Later:** Open Cloud's MessagingService API could start a party from outside the game (it needs an API key, so
  not yet). A server list in MemoryStore could let a host hop servers ("Doctor's rounds").

### 3.4 The announcement: the Party Board and the HUD
- **The Party Board**, a code-built sign on the plaza facing `TownSpawn`. A proposal: mirror the belt's odds sign on
  the plaza's other edge. The exact spot is the brother's call, since the world is his.
  - **Before:** "🎉 Doctor's Party · Saturday 4:00 PM (your time) · in 2 days 3 h · Everyone gets: 2× 💰, a
    Golden Belt, a 🎈 Party Balloon". Local time comes from `DateTime:FormatLocalTime` on the client.
  - **During:** "🎉 Party now! · 23 min left · Powers: 👑 💰". The time left is true.
  - **No party set:** "Next party: coming soon". Never a made-up date.
- **The HUD:** a small chip only in the **last hour before** and **during**, plus one banner at the start (the bus
  `Banner`, Id `"Party"`, the same as Golden Hour's).
- **Words:** say what, when and what's free. Never "don't miss it", "last chance" or "hurry", following Roblox's
  "language to avoid" list.
- **Golden Hour and Night Rush** can now show "👑 Golden Hour in 7 min" (`-022` overrules `-020` §2). Golden Hour runs
  on server uptime, so the countdown is right for that server. Update `BeltView` and the README's "never a countdown"
  lines when that ships.
- **Outside the game, on Roblox only:**
  - an **Experience Event** in Creator Hub (Joshua, the sole owner), with "Notify Me". A **public** event needs both
    brothers' yes (red line 4);
  - an **update announcement** (60 characters, once every 3 days), which reaches followers under 13 too;
  - a join from the event reads `GameJoinContext.EventId` for a "🎉 Welcome to the party!" toast. No extra reward,
    so nothing is gated.
- **Not used for this:** experience notifications. They're 13+ only and one a day, and Roblox wants them personal
  and actionable, "not of a generic, advertising nature". A party start is generic.

### 3.5 Safe limits
1. **Admins only, by UserId:** `Config.AdminUserIds` and the owner. Names aren't enough for powers that reach every
   server. The server checks again on every call, as it does today.
2. **Only while a party is "armed":** from 30 min before a scheduled start to its end. Outside that, an every-server
   button answers "🎉 Only during a party!". The existing alone-only rule stays for the one-server Night, Day and
   Winter test buttons.
3. **Presets only.** Fixed values and limits from `Config.Party`. A party ends after `MaxMinutes` whatever happens.
4. **A cooldown:** one power change every 10 s, at most 3 powers at once.
5. **No free text.** Preset messages only, unless filtered with `GetNonChatStringForBroadcastAsync`.
6. **Nothing paid:** no Robux prompt opens in a party, the board and banners never mention a paid item, and nothing
   says "only N left".
7. **The same for everyone:** every server gets the same powers at the same time. No lottery, no first-come stock.
8. **Kind to devices:** the Big Sneezer and the confetti follow ✨ calm effects and reduced motion. Heavy builds are
   spread over a few seconds. The giant is one model per server, within the perf budget
   (`docs/plan/2026-11-16-perf-budget.md`).
9. **An announced party always happens** (the Auto Party). A cancelled one says "Moved to …" honestly.
10. **A log and a stop button:** every action prints `[Party] <name> <action>`, and 🛑 End party ends it on every
    server (it deletes `Live` and sends a message).
11. **The economy check:** Double Pay inflates the ⭐ board (cures and hearts aren't touched). That's accepted,
    because everyone online gets the same 2×.

### 3.6 The gift without tears
- It's given **any time during the party** (not just at the start), on **any server**, once per party id. That
  needs a save field such as `Data.Parties[partyId] = true`, added by `Schema.reconcile`.
- **Each party's decor comes back** in a later party, or as a 🏅 badge reward, so missing one Saturday never means
  missing it for good. Seasonal items say "back next winter".
- **No early-bird gift.** It pulls kids online an hour early, and Roblox's discovery only counts 60 min a day
  anyway (`2026-11-16-kids-audience-and-rules.md`).

### 3.7 How it plugs into `Admin.luau`
- **`shared/Logic/Admin.luau`:**
  - new arg kinds `"PowerId"` and `"MessageId"`;
  - new actions `PartyStart`, `PartyPower (PowerId)`, `PartyEnd` and `PartySay (MessageId)`, with a new flag
    `Global = true` next to `ServerWide`;
  - `Admin.globalAllowed(armed, studio)`. In Studio it allows the actions, but on the Studio topic;
  - `valid()` checks the ids against `Config.Party.Powers` and `Config.Party.Messages`.
- **`server/Party.luau` (new):** the schedule, live state, subscription and Auto Party, plus
  `Party.active(power): boolean`, `Party.multiplier(kind): number` and `Party.armed(): boolean`.
  - **Boot:** it starts after `NurseBelt` and `DayNight`, and before `Admin`.
  - **No require loops:** systems read it, and it never requires `Patients` (the same rule as `Treatment`).
  - **Its pure rules:** the message checks, the `EndsAt` clamp, the powers on at time t and the Auto Party
    decision go in `shared/Logic/Party.luau`, with a Lune spec.
- **`server/Admin.luau`:** `RUN.PartyStart = function(player) return Party.start(player) end`, and the same for the
  others. `handle()` adds:
  `if spec.Global and not AdminLogic.globalAllowed(Party.armed(), IS_STUDIO) then return false, NOT_ARMED end`.
- **Small public APIs the powers need:**
  - `NurseBelt.setGolden(untilTime)`;
  - a party factor read by `Boosts.multiplier`;
  - a live-safe winter switch in `Events`;
  - `Party.active` checks in `Patients` (sparkly, calm, visitor).
  - The raw Studio switches stay as they are.
- **`client/UI/AdminPanel.luau`:** a section "🎉 Party · every server" with Start (tap twice to confirm), one button
  per power, the preset lines, and 🛑 End.
  - Buttons grey out while not armed. That's for the UI only, because the server decides.
  - The 56 px minimum button size still holds.
- **`client/`:** a `PartyBoard` module (the sign and the HUD chip) reading the Workspace attributes.
- **`Config.Party`:** `Enabled`, `Topic`, `MaxMinutes`, `PollSeconds` (20), `AutoAfterMinutes` (5), `Powers` (each
  with `Minutes` and its value), `Messages`, `AutoTimeline`, `Gift`.

## 4. Soft return hooks that fit our rules
✅ = spend-free in our version. "Have" = in the game today (README).

| Hook | Where the hits use it | Ours | Status | Watch out |
|---|---|---|---|---|
| Daily play gifts (unlock with active play) | sims widely | ✅ | Have (`Playtime`) | no streak, nothing lost |
| Mailbox gift + daily goals that bank | | ✅ | Have (`Daily`) | they never expire |
| Today's Visitor (×3), story beats by day | | ✅ | Have | |
| Rotating stock: belt every 40 s, Agency every 5 min | GAG seed shop every 5 min + Daily Deals every 24 h | ✅ | Belt have, Agency planned (Progression v2) | **never** a Robux restock (GAG sells one for 79), never "only N left" |
| Golden Hour + Night Rush, now with a true countdown | GAG's synced weathers | ✅ | Have; the countdown is new (`-022`) | correct for each server's uptime |
| **Doctor's Party** on a fixed slot, Party Board countdown | GAG, SAB, PvB | ✅ | Proposed (§3) | must happen (Auto Party) |
| "Next update" line on the board | GAG/SAB update every Saturday; 99 Nights' live "Update Party" (`kids-audience-and-rules.md` §2) | ✅ | Proposed | a date only once it's certain; Roblox suggests small updates every 2-4 weeks |
| **Town goal** across all servers (cures this week → a party for everyone) | our replacement for like goals | ✅ | Proposed | counts our own data, never ratings; same reward for everyone |
| Weekly board reset (Monday UTC) | | ✅ | Have | |
| Seasons (Winter Wing) with decor that returns | Adopt Me, GAG seasonal events | ✅ (earned in play) | Have (winter) | say "back next year" |
| Collections (Book, Journal) | | ✅ | Have | |
| Roblox Experience Event + "Notify Me" | PvB's event card | ✅ | Proposed | public page = both yes |
| Update announcements to followers | Roblox feature | ✅ | Proposed | 60 chars, once every 3 days, reaches under-13s |
| Experience notifications | Roblox feature | ✅ | Later | 13+, one a day, personal ("Your nurse tray is full") |
| "⭐ Favorite to find us again" prompt | Roblox API | ✅ | Proposed | no reward, no gating, once a session |
| Friend invite → Friend Bench decor | | ✅ | Have (`Visits`) | cosmetic, once |
| Early-bird gift (online an hour before) | SAB | ✅ but | Not recommended | pulls kids online early |
| "Come back in 4 h" growth timers | GAG crops (Robux speeds them up) | only if never skippable | Not recommended | Roblox: appointment timers are "unpopular" |
| Streaks | many | n/a | Ruled out (`kids-audience-and-rules.md`) | Ofcom names streak rewards as a child-spending risk |
| Like or favorite for a reward, like goals | many sims | n/a | Ruled out (§1.2) | ToS §5.1 |

## 5. Questions for the brothers (for OPEN #9; not added there, as this task was research only)
1. **The name:** "Admin Abuse" (the brother's word), "Admin Party" (GAG 2), "Doctor's Party", or another?
2. **The slot:** which day and time (UTC), weekly or every two weeks, and who hosts which? Hours are `../joshua-hq`'s
   call.
3. **Auto Party:** OK for it to run by itself when neither of you can make it?
4. **The gift:** does each party's decor come back later (recommended), or is it kept for that day only?
5. **A public Experience Event page and update announcements:** both of you say yes once, or each time?

## Sources (fetched 2026-11-16/17)
- **Roblox Terms of Use:** https://en.help.roblox.com/hc/en-us/articles/115004647846-Roblox-Terms-of-Use (effective
  2026-11-01)
- **Community Standards:** https://about.roblox.com/community-standards · Promo Offers:
  https://en.help.roblox.com/hc/en-us/articles/10549651908244-Promo-Offers-for-Virtual-Rewards
- **Creator Hub** (all last_updated 2026-11-14):
  - https://create.roblox.com/docs/production/promotion/content-ratings (the old experience-guidelines URL)
  - https://create.roblox.com/docs/discovery
  - https://create.roblox.com/docs/production/monetization
  - https://create.roblox.com/docs/production/promotion/experience-notifications
  - https://create.roblox.com/docs/production/promotion/experience-events
  - https://create.roblox.com/docs/reference/engine/classes/MessagingService
  - https://create.roblox.com/docs/cloud-services/cross-server-messaging
  - https://create.roblox.com/docs/cloud-services/memory-stores
  - https://create.roblox.com/docs/reference/engine/classes/AvatarEditorService
  - https://create.roblox.com/docs/ui/text-filtering
  - https://create.roblox.com/docs/production/analytics/feedback
- **DevForum:**
  - https://devforum.roblox.com/t/4829188 (Roblox, 2026-08-25)
  - /t/4495969 (2026-03-08) · /t/4524009 (2026-03-14) · /t/2926286 (2024-04-12) · /t/1029127 (2021-02-06)
- **Player numbers:**
  - Tubefilter, 2025-08-25: https://www.tubefilter.com/2025/08/25/roblox-grow-garden-steal-brainrot-admin-war-record/
  - Wikipedia "Grow a Garden" and "Steal a Brainrot" (API extracts, 2026-11-17)
- **Fan wikis** (MediaWiki API, 2026-11-17): growagarden.fandom.com (Admin_Abuse, Admin_Abuse_War, Seed_Shop,
  Weather) · stealabrainrot.fandom.com (Admin_Abuse, Taco_Tuesday)
- **Guides:**
  - mygagcalculator.com/grow-a-garden-saturday-admin-abuse (2026-05)
  - allthings.how/plants-vs-brainrots-admin-abuse-schedule (2025-11-22)
  - allthings.how/admin-abuse-in-grow-a-garden-2-what-it-is-and-whether-it-has-happened (2026-06-18)
  - eldorado.gg/blog/grow-a-garden-en/grow-a-garden-2-admin-party (2026-08-07)
  - gamepressure.com/newsroom/new-admin-abuse-date-in-grow-a-garden-you-get-to-decide-when-this/z78663 (2025-09-24)
- **Refused automated fetches:** the help-centre copy of the Community Standards, ICO's Children's Code pages,
  Medium, gameboost.com and techspot.com.
