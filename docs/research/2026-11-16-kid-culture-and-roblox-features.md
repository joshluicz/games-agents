# Kid culture trends and Roblox growth features (2026-11-16)

Desk research, pages opened 2026-11-16 unless marked **(search only)**. **UNVERIFIED** = couldn't confirm.

## A. Kid culture, autumn 2026 (ages ~6–12)
**Collecting and squishy, sensory things are the big movement.**
- **M** US collectible toys +56% and licensed toys +27% (Jan–Sep 2026). Tactile/sensory toys $671M, 6× last year.
  Keychains +200%. TikTok Shop is now the #4 US toy retailer (Circana via The Toy Book, 2026-11-12:
  toybook.com/circana-january-september-2026-toy-data).
- Beano Brain, 10,000 UK kids aged 7–14 (2026-09-24): "Collecting, displaying, trading, building, customising, they're
  all forms of play"; kids "want more joy" (globaltoynews.com, 2026-09-24).
- Toy Association 2026 trends: Forever Young · Cozy Culture · Inspiring Inventors · Express Yourself · Throwback ·
  Fan-Driven Play (toyassociation.org trend-spotting).
- 2027 Toy of the Year finalists (2026-11-07) lean squishy, sensory and collectible, plus hatching creatures, digital
  pets, food play (ice-cream parlours), space and ocean.

**Creatures you look after are back.** Tamagotchi Paradise (2026-07-11), Peekimo, Magic Jellykins. Capybara and
axolotl are the "it animals" (search only).

**Food with faces is what kids carry.** Yahoo looked in 11 backpacks of kids aged 7–12 (2026-09-17) and found sushi and
corn keychains, dumpling squishies, a cupcake keychain, an axolotl pencil case, plush clips and one Roblox
"brainrot" figure.

**Spooky-cute works.** NRF Halloween 2026 (2026-10-14) puts superheroes on top for kids; witch and ghost costumes rank
high (search only).

**What they watch.** YouTube reaches 78–80% of kids aged 6–12, ahead of TikTok. Ages 6–9 watch cartoons, comedy and
toys/games; ages 10–12 watch comedy (53%), music and gaming (Precisify via advanced-television.com, 2026-02-19).

### ⛔ IP risk: meme brainrot characters
Mementum Labs claims copyright and trademark rights in "Tung Tung Tung Sahur". It is in a lawsuit with Spyder Games,
one of the companies behind the Roblox game *Steal a Brainrot*: counterclaims were filed 2026-04-24 and a hearing set
for 2026-09-23 (GamesBeat, 2026-08-06:
gamesbeat.com/the-battle-over-tung-tung-tung-sahur-is-testing-the-limits-of-copyright-and-trademark-law). Keep every
meme character out of the game. Original absurd humour is fine.

Also owned, so don't use the names or look: NeeDoh, Squishmallows, Jellycat's food-with-faces look, Labubu, Tamagotchi,
KPop Demon Hunters, Pokémon. The general ideas (squishy, pet care, a water reveal, food with faces) are free to use.

### Fresh theme candidates from this research
1. **Squishy charm workshop.** Customers order squishy food-with-faces charms; you mould, squish and serve them.
2. **Critter inn.** Made-up creatures check in for a snack, a bath or a nap; gifted eggs hatch overnight.
3. **Moonlight potion shop.** Cozy brews by day, spooky-cute customers at night, colour-change reveals.

## B. Roblox features for growing a kids' game (and their age rules)
| Feature | Under-13s? | Notes |
|---|---|---|
| Experience Updates (notification) | ✅ | 60 characters, at most once every 3 days (create.roblox.com/docs/production/promotion/experience-events) |
| Personalised notifications | ⛔ 13+ only | Max 1 per day, no false urgency, needs 100+ visits |
| Experience Events | ✅ | "Notify Me" button, an inbox alert, a shareable page. Trending Events needs 1,000+ RSVPs |
| Referral rewards | ✅ (no age rule stated) | `GetJoinData().ReferredByPlayerId`; banner set in Creator Hub. Reward once, store it in a DataStore |
| Invite prompts | ✅ (varies by player) | Check `SocialService:CanSendGameInviteAsync()` first |
| Party | ✅ join; ⛔ party chat | Up to 6 friends in the same server |
| **Custom Quick Words** | ✅ all ages, no age check | Live 2026-10-13: up to 3 categories of 3–10 preset phrases, auto-translated, reviewed (devforum.roblox.com/t/4932108). This is how kids co-operate with chat off |
| Moments (short video) | ⛔ 13+ | Rated Moderate |
| Rewarded video ads | ⛔ 13+ viewers only | Needs 2,000+ monthly visitors |
| Immersive ads | ⚠️ contextual only for under-13s | Use `PolicyService.AreAdsAllowed`. Needs both brothers' yes |
| Standout Games (was Today's Picks) | Nomination form | create.roblox.com/docs/creator-programs/standout-games |
| Studio Assistant `/generate_mesh`, `/segment_mesh`, `/generate_procedural_model` | ✅ for the builder | Assets land in the account of whoever made them, which matters for the ownership note |
| In-game player AI generation (`GenerationService`) | ⛔ avoid | Counts as free-form creation (16+) |
| Analytics: retention cohorts, segments, A/B tests | ✅ | A/B data is weak under ~1,000 daily users |

Skip for a kids' audience: rewarded video, Moments-led promotion, personalised notifications, Shopify merch, player-side
AI generation.
