# Quick Words for Creature Clinic

**Quick Words** are ready-made phrases a player taps in the chat window. Roblox shows them at **every age**, so they
work for kids whose chat is off, and Roblox translates them into each player's language. In Creature Clinic they let
friends split the work without typing ("I'll do the bath", "Need plasters"). Design: §3 and §5.9 of
`docs/plan/2026-11-16-creature-clinic-design.md`.

You set them in **Creator Hub**, not in the code, so nothing in `game/` changes.

## Roblox's rules (checked on the live pages, 2026-11-16)
Source: [Quick Words](https://create.roblox.com/docs/chat/quick-words) and
[Preset system guidelines](https://create.roblox.com/docs/chat/preset-system-guidelines). Check both again before
you publish, because rules change.
- **Up to 3 custom categories**, with **3 to 10 phrases** in each.
- **Each phrase is under 25 characters.**
- **English only.** Roblox auto-translates them for each player.
- **About the game, not social chat.** No open-ended questions, no greetings or small talk ("Hi!", "How are you?"),
  nothing about real life, contacts or relationships, no slang with hidden meanings, and no pressure.
- **Phrases mustn't make new meanings when chained** (no letter or number codes).
- **Roblox reviews them** before they go live: **Draft → Pending → Published**, or **Not approved**.
- **Custom categories replace Roblox's default ones.** The **General** category stays.

**Our own extra rules:**
- **No "!" or "?" at the end.** Roblox's preset guidelines say presets shouldn't end with punctuation. That list is
  written for home-made preset systems, and Quick Words is already compliant, but leaving it out costs nothing and
  makes a rejection less likely. That's why the plan's "I'll do the bath!" is "I'll do the bath" here.
- **No emoji in phrases.** The pages don't say whether they're allowed. Try one in a draft first if you want them.
- **Every phrase is about the clinic.** Nothing that asks for hearts, visits or friends.

## The list (22 phrases, 3 categories)
The number after each phrase is its length in characters. Every one is under 25.

### Category 1: I'll do it
| Phrase | Chars | Why |
|---|---|---|
| I'll make potions | 17 | Taking the 🧪 Remedy Bench |
| I'll do plasters | 16 | Taking the 🩹 Plaster Table |
| I'll do the bath | 16 | Taking the 🛁 Warm Bath |
| I'll make cocoa | 15 | Taking the ☕ Cocoa Corner (Winter Wing) |
| I'll work the counter | 21 | Treating patients at the Counter |
| On my way | 9 | Coming to help |
| Follow me | 9 | Showing a friend the way (an example Roblox lists as allowed) |

### Category 2: We need
| Phrase | Chars | Why |
|---|---|---|
| Need potions | 12 | The line needs 🧪 |
| Need plasters | 13 | The line needs 🩹 |
| Need bubbles | 12 | The line needs 🛁 from the bath |
| Need cocoa | 10 | The line needs ☕ |
| Need help at the counter | 24 | Too many patients for one player |
| Patient waiting | 15 | Someone's at the Counter |
| The line is long | 16 | Patients are piling up |

### Category 3: Heads up
| Phrase | Chars | Why |
|---|---|---|
| Night patients coming | 21 | Night is starting (they pay 2×) |
| Today's Visitor is here | 23 | The ⭐ featured creature of the day has arrived |
| Sparkly patient | 15 | A rare ✨ variant is in the line |
| Frosty patient | 14 | A rare 🧊 winter variant |
| Ready | 5 | Ready to start (an example Roblox lists as allowed) |
| Nice cure | 9 | Cheering a teammate |
| Great teamwork | 14 | Cheering the team |
| Thank you | 9 | Thanks for helping (Roblox lists "Thanks" as allowed) |

### Spares (if one isn't approved)
`Wait for me` (11) · `My tray is full` (15) · `Bed is free` (11) · `Wrong cure` (10) · `Good job` (8) ·
`Bring a plaster` (15) · `Bath Room is open` (17) · `Need bandages` (13)

⚠️ **Watch "plaster".** In the US, "plaster" usually means wall plaster, so the auto-translation might come out odd.
If players get confused, swap "Need plasters" for "Need bandages". The game itself shows 🩹, so either word works.

**Left out on purpose:** "Come help my clinic" and "Leave a heart". Both are about the game, but an invitation or
asking for hearts can read as social chat or pressure, which the rules forbid.

## Set them up (Joshua, about 10 minutes)
1. **Agree the list with your brother first.** Players will be saying these words in the game's name, so it needs
   both your yes (red line 4), and he's the one closest to the players. Change anything you both want, and keep each
   phrase under 25 characters.
2. Sign in at [create.roblox.com/dashboard/creations](https://create.roblox.com/dashboard/creations) and click the
   game. Right now it's still called **Shop Co-Op [WIP]** there (`STATE.md`).
3. Go to **Configure → Chat → Quick Words**.
4. Add a category, type its name (`I'll do it`), then add its phrases. Do the same for `We need` and `Heads up`.
5. Not finished? **Save as a draft.** Finished? **Publish.**
6. Wait for the review. **Pending** means Roblox is checking. **Published** means it's live. **Not approved** means
   you change the phrase (use a spare) and publish again.
7. **Check it in the game.** Play, open the chat window, and look in the **Here** and **Global** tabs.
8. Changed your mind? You can go back to Roblox's default Quick Words at any time on the same page.

## When to update them
When a new wing arrives (a new station means a new "I'll ..." and "Need ..." phrase), or when playtests show kids
want to say something they can't. Each change goes through review again.
