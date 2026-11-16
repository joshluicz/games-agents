# Roblox market scan: what to build (2026-11-16)

Desk research done the day the project started. **M** = a measured number, with its source and date. **C** =
commentary or inference. Third-party player-count trackers disagree, so treat those numbers as order of magnitude
only. Pages that couldn't be opened are listed at the bottom.

## 1. The platform is big but shrinking a little
- **M** Q3 2026 (reported 2026-10-29): 138M daily active users, −9% year on year, +12% on the quarter. Hours −15%.
  Bookings ≈ US$1.7B, −12%. Q4 guided down a further 10–15%. ggrecon.com/articles/roblox-daily-players-fall-q3-2026/ ·
  gaming.net (Q3 revenue article). *Press summaries; the shareholder letter wasn't opened.*

## 2. What's winning
- **M** June 2026 live players (RoWatcher): Brookhaven 497K · Adopt Me 324K · +1 Speed Keyboard Escape 307K ·
  99 Nights in the Forest 285K · RIVALS 222K · Blox Fruits 218K · MM2 199K · Steal a Brainrot 151K.
  rowatcher.com/news/the-most-popular-roblox-games-right-now-ranked-by-live-players
- **M** Steal An Egg, Sep 2026: ~1.3M concurrent, a 24h peak above 2M, ~15-minute average session. Loop: steal eggs →
  hatch pets → earn → upgrade base → steal again. player.one (Steal An Egg article).
- **M** Grow a Garden: ~21.3M concurrent peak on 2025-06-21, the record. pocketgamer.biz.
- **C** 99 Nights in the Forest: "survive N days" plus a cozy forest theme, with a team of about 5 (search summary of
  the DevForum creator spotlight).
- **M** Fastest-growing new games (2026-11-02): DONT SPLASH (small-lobby horror) 97K · Break and Steal an Egg 95K ·
  Bike Universe 24K · Sell Fries (chip-shop sim + horror) 23K · Fake an Egg 19K · Turbo Soccer 19K · Backseat Rally
  (co-op) 13K. ggrecon.com/articles/fastest-growing-new-roblox-games-november-2026/
- **M** Small-team proof: TTK, an FPS by two developers, passed 7M plays. Clips went viral before the algorithm picked
  it up. games.gg (2026-06-23).

## 3. How Roblox decides what to show (Roblox's own words)
- **M** 2026-06-15: "Recommended For You" now weighs **retention over 28 days** (day 1, days 2–7, days 8–28),
  **players coming back**, **players bringing friends (co-play)**, and **spending**. These signals are visible in
  Creator Analytics; no weights are published.
  about.roblox.com/newsroom/2026/06/optimizing-discovery-great-games-reach-millions-players-roblox
- **M** Creator docs list play-through rate, qualified sessions per user and spend days per user.
  create.roblox.com/docs/discovery
- **M** After Steal An Egg's AI-clip "Reels" feed drew backlash, Roblox **restricted games that pair a feed with a
  reward mechanic from Kids and Select accounts** (2026-08-29, search summary of massivelyop.com; the page itself
  returned 403).

## 4. Money reality
- **M** (Roblox, to 2025-12-31): the top 1,000 creators averaged US$1.3M in 2025. More than 35,000 creators are in
  DevEx, and the **median recipient got US$1,550** over 12 months. create.roblox.com/docs/monetize
- **C** The median counts only creators who already clear the 30,000-Robux minimum. Most games never get there. Without
  promotion, a realistic first game gets close to zero visits.
- **M** Ads: Roblox quotes under US$0.01 average cost per play on "Maximize Plays". Developers report higher real costs
  (one quoted about 2.85 Robux per play at the minimum bid; anecdotal).

## 5. What it means for us (C, the basis for the plan)
1. **Retention and co-play are what get a game shown.** A game needs a reason to come back tomorrow and a reason to
   bring a friend.
2. **Don't need a full server to be fun.** A brand-new game has almost no players, so anything that's only fun in a full
   lobby (horror rounds, party games) dies empty. Solo-fun and better with friends survives.
3. **Stay out of the clone waves.** "Steal a ___", eggs and brainrot are crowded, and feed-plus-reward games are now
   restricted for kids.
4. **A job or shop sim with a twist is still open.** Sell Fries shows it works at small scale. Progression brings players
   back, co-op brings friends, and game passes fit naturally.
5. **Being kid-first changes the launch.** See `docs/setup/02-accounts-and-costs.md`: the first 250 qualifying players
   must be 16+.

## Concepts scored (1–5, higher is better for us; saturation 5 = open)
| Concept | Build | Clip-ability | Retention | Money fit | Saturation |
|---|---|---|---|---|---|
| **Co-op shop sim, night twist** ✅ picked 2026-11-16 | 4 | 4 | 3 | 4 | 3 |
| Small-lobby horror round | 4 | 5 | 2 | 2 | 3 |
| Co-op driving/chore game | 2 | 4 | 3 | 3 | 4 |
| Hide-and-seek / disguise party | 3 | 4 | 3 | 3 | 3 |
| Obby, one twist, a new stage weekly | 5 | 3 | 2 | 2 | 1 |

## Couldn't open (worth a look later)
RoMonitor, Rolimons, roblox.com/charts, the DevForum threads (they came back empty), Roblox's investor-relations
documents, and massivelyop.com (403). Unknowns: team sizes and monetisation of the big hits, typical build times,
how Today's Picks works, the thumbnail A/B details.
