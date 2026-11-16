# Kids as players: what brings them back, how they find games, and the rules (2026-11-16)

Desk research, sources fetched 2026-11-16 unless dated. **M** = measured, with source. Roblox docs pages show no
"last updated" date. Ofcom and ICO pages refused automated fetches, so those lines come from search excerpts.

## 1. Why children play, and come back
**Ages 5–8**
- Read little or haltingly and skip instruction text (NN/g, seen on Roblox itself:
  nngroup.com/articles/childrens-websites-usability-issues). Roblox: "keep everything as visual as you can", use
  consistent icons (create.roblox.com/docs/production/game-design/design-for-roblox).
- Tap targets ≥ 2 cm, limited motor demands, dragging and small targets are hard under 9, and they prefer touch
  (nngroup.com/articles/children-ux-physical-development).
- Take instructions literally and miss subtle feedback, so it has to be exaggerated or spoken
  (nngroup.com/articles/kids-cognition).
- Pretend play lasts to about 11 (Smith & Lillard 2012; Frontiers 2021).
- **M** 5–8s game ~64 min/day (Common Sense Census 2025, secondary via Kidscreen).

**Ages 9–12**
- Scan text and like gestures. Reject anything that looks "for babies" (NN/g).
- What they value: mastery, customisation and belonging. Comparing, swapping tips and inventing stories together were
  linked to wellbeing (UNICEF RITEC / Cooney Center, 2024: joanganzcooneycenter.org/?p=24782).
- They play what their school friends play, and status pressure starts early ("If you're a default skin, people think
  you're trash", Nina, 10: childrenscommissioner.gov.uk/report/gaming-the-system).

**Both bands**
- Roblox: younger users favour exploration, experimentation and socialising over competition, and single-player games
  "find it harder to build and retain an audience" (Design for Roblox).

## 2. How story works in the kid-heavy hits
**M** Roblox games API, 2026-11-16, all rated Minimal:

| Game | Visits |
|---|---|
| Brookhaven RP | 89.56B |
| Adopt Me! | 45.43B |
| Grow a Garden | 36.02B |
| 99 Nights in the Forest | 30.55B |
| Dress To Impress | 11.36B |
| Welcome to Bloxburg | 10.17B |
| Work at a Pizza Place | 5.63B |
| Bee Swarm Simulator | 4.67B |
| Pet Simulator 99 | 2.71B |
| **Restaurant Tycoon 2** | **1.66B** |
| Theme Park Tycoon 2 | 1.63B |
| **My Restaurant!** | **0.89B** |

Pure restaurant tycoons sit one to two orders of magnitude below the social and roleplay games.

Recurring story structures:
1. **A one-line premise plus a countable goal.** 99 Nights: "Build a camp with friends. Something is watching you."
   The story lives in the world; weekly updates with a live "Update Party" (devforum.roblox.com/t/4036940, 2025-10-31).
2. **Quest-giver characters with personalities who unlock new areas.** Bee Swarm's bears; new zones open by progress.
3. **Players write the story.** Brookhaven, Adopt Me and Bloxburg give roles, homes and pets, not a plot.
4. **Live events and a world that changes.** Grow a Garden's restocks and live developer events (**M** ~22.3M peak
   concurrent, 2025-08-23, RoMonitor via Tubefilter).
5. **Themed rounds plus social judging.** Dress To Impress.

Roblox's quest guide: flavour text should explain *why*, not just *what*
(create.roblox.com/docs/production/game-design/introduction-to-quest-design).

## 3. How kids find games, and what good retention looks like
Roblox's stated signals for Recommended For You, organic users only (create.roblox.com/docs/discovery):
- **Most important:** play-through rate · first-play bounce (left in < 60 s, or 61–180 s) · play days per user ·
  playtime per user, **capped at 60 min per user per game per day**.
- **Important:** intentional co-play days (joins, invites, private servers) · qualified sessions · spend days ·
  Robux per user.
- A **custom thumbnail is required** for Home impressions. Personalisation tests 2–5 thumbnails (Roblox reports +8.5%
  average qualified play-through), and thumbnails must show real gameplay
  (create.roblox.com/docs/production/publishing/thumbnails).

Roblox: get players to the fun "ideally in 5 minutes or less". Small updates every 2–4 weeks, big ones every
2–3 months (create.roblox.com/docs/production/analytics/retention).

**M** GameAnalytics 2026 Roblox report (Aug 2025–Jul 2026, 500+ titles with 1M+ monthly users, updated 2026-09-01:
gameanalytics.com/reports/2026-roblox-report):

| | Median | Top 1% |
|---|---|---|
| D1 retention | 10.3% | 22.2% |
| D7 retention | 1.6% | 9.1% |
| D30 retention | 0.5% | 4.7% |

Median session 9.8 min (p90 14.7). 3.8% of players paid anything.

## 4. Roblox's rules for under-13s (current)
- **Roblox Kids (5–8): Minimal or Mild. Roblox Select (9–15): up to Moderate.** Both exclude social hangouts,
  free-form drawing, Roblox Moments and in-game one-to-one chat (newsroom 2026-05-20).
- **To reach them** (create.roblox.com/docs/production/publishing/kids-and-select):
  - a 16+-only trial first, then 250 unique plays from highly engaged players in 60 days (an April 2026 forum Q&A said
    500; the docs say 250);
  - the owner ID-verified with 2SV;
  - a 1,000-Robux refundable fee, or Plus/Premium for 2 months.
- **Content maturity:** free-form creation 16+, social hangouts 16+, **extended AI interactions 18+**, playable
  gambling prohibited (create.roblox.com/docs/production/promotion/content-maturity).
- **Chat** needs an age check (since Jan 2026); Kids accounts have chat off by default.
- **Paid random items:** numeric odds before purchase, including indirect purchases. Play-earned randomness is exempt.
  `PolicyService.ArePaidRandomItemsRestricted` must be honoured
  (create.roblox.com/docs/production/monetization/paid-random-items).
- **Ads:** rewarded ad formats are banned for under-13s from 2026-05-04 (devforum.roblox.com/t/4527365).
- 2026-05-20: Fairplay and NCOSE asked the FTC to investigate Roblox's "manipulative design" (scarcity, loot boxes,
  wheels, social comparison). Roblox says ~40% of daily users are under 13 (Fortune).

## 5. Fair retention vs dark patterns
- **Fine:** mastery, choice, co-op, customisation, optional dailies, break nudges (ICO Children's Code std 13 bars
  nudges that extend use).
- **Treated as manipulative by regulators:**
  - FTC v. Epic 2022 ($245M);
  - FTC v. HoYoverse 2025 ($20M: hidden currency costs, misleading odds);
  - EU CPC actions 2026-09-30 (time-limited offers, urging children to buy);
  - the EU Digital Fairness Act proposal of 2026-11-11, not law yet (bans loot boxes and pay-to-progress for minors,
    and blacklists scarcity messages and confirmshaming);
  - Ofcom 2025, which names **streak rewards** and time-limited mystery rewards as child-spending risks.
- Roblox games specifically: 14 of 15 studied used deceptive monetisation (Univ. Sydney, 2026-05-19).

## What it means for us
1. Show, don't tell: icons, sound and demonstration. First serve inside 60–180 s.
2. Mobile-first: big tap targets, no dragging, no precision timing.
3. Co-op must work without chat: split stations, preset emotes and pings.
4. Light story: a one-line premise and recurring scripted characters whose quest lines open new areas. **No AI-driven
   NPC chat (18+).**
5. Night stays mysterious, not scary (Mild at most).
6. Collections are earned, never sold at random: a customer album, recipe book, decor sets.
7. Customisation from preset pieces, never free-form drawing (16+).
8. **No streaks.** Optional dailies that bank up, and a natural stopping point at the end of each in-game day. Aim for
   more play days, not longer sessions (playtime counts only up to 60 min a day).
9. Events celebrate; they don't sell. No timed offers, fake sales or "decline" shaming.
10. Honest money: at most one premium currency, plain prices, cosmetics and co-op extras only, never pay-to-progress.
11. Fun for 16+ too: the qualifying trial is 16+ only, and good humour and craft also stop 9–12s calling it "babyish".
12. Track D1 against the 10.3% median, aiming at 20%; D7 toward 5–9%.
