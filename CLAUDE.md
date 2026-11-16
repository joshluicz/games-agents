# Games: the Roblox brain (Joshua and his brother)

This repo holds the plan, decisions, research **and** the code for the Roblox game Joshua is building with his
brother. Started 2026-11-16 (`memory/records/memory-20261116-001.md`). One repo on purpose: the planning
lives at the top level and the game itself lives under `game/`. Splitting the code into its own repo is fine
later, once the game has a name and a second game exists. Until then one repo is simpler for two people.

## Before you do anything
0. **Check for unmerged work.** Several sessions can run against this repo at once, each on its own branch:
   ```bash
   git fetch origin -q && for b in $(git branch -r | grep -v -e HEAD -e 'origin/main$'); do n=$(git rev-list --count origin/main..$b 2>/dev/null); [ "$n" -gt 0 ] && echo "$b  +$n  $(git log -1 --format=%s $b)"; done
   ```
   ⛔ If a branch touches `STATE.md`, `memory/` or `context/` and isn't merged, your checkout is a partial view.
   Read its diff before you "correct" anything it touches.
1. Read `STATE.md`: phase, next actions, who is doing what, blocked on.
2. Read `context/OPEN-QUESTIONS.md`. It's the inbox for both brothers. Don't re-ask anything it shows as answered.
3. Read the decisions in `memory/records/` (date + decider on every one). Open the record before you cite it.
4. For code work, read `game/README.md` first.

## The red lines
1. **Never invent a fact.** Names, ages, who owns what, prices, player numbers, deadlines, hours: these come from
   Joshua or his brother. If something's unknown, it goes in `context/OPEN-QUESTIONS.md`. Don't guess it.
2. **Original game only.** A genre, a mechanic or a format is fine to borrow. Another game's name, characters,
   art, music, sounds or levels are not, even renamed. Roblox takes down copies, and a copy has no future anyway.
3. **The players are mostly children.** Follow Roblox's Terms of Use and Community Standards as they read *today*
   (check the live page, not memory). No links off Roblox, no outside payments, no collecting personal data. Paid
   random items show their odds. Nothing in the game pressures a kid into spending.
4. **Nothing goes public without both brothers saying yes.** That covers going public, a paid ad, a Robux spend, a
   post on a public account, or anything said in the game's name. Staged is fine. Shipped needs a yes (in chat counts).
5. **Ownership in writing before money.** A one-page note (who owns the game and the group, how Robux gets split,
   who decides) is written and agreed **before the first public promo or the first Robux earned**. Same rule as
   the hardware lab's bird frame.
6. **Hours aren't decided here.** How many of Joshua's hours go to this versus university applications, Eitri
   Brokkr and the hardware lab is `../joshua-hq`'s call. Point out conflicts; don't settle them in this repo.

## Layout
| Path | What it holds |
|---|---|
| `STATE.md` | Live state first (phase, next actions, who's doing what, blocked on), then recent sessions, newest on top |
| `context/OPEN-QUESTIONS.md` | Questions for Joshua and his brother. Answered ones move to ✅ with the date |
| `context/team.md` | Who does what: the split between the brothers |
| `memory/records/` | Decisions that last. One file each, frontmatter with `date` + `decider`. Never edit a past ruling. Supersede it |
| `docs/setup/` | How to connect Claude to Roblox Studio, accounts, what it costs |
| `docs/research/` | Market scans, cited. Measured numbers carry their source and date |
| `docs/plan/` | The game plan, day plans, the update roadmap |
| `game/` | The Rojo project: the Luau code that syncs into Studio. Its own `README.md` |
| `logs/` | Playtest notes, analytics snapshots, post-mortems |

## How the code works
- **Git owns the scripts and Studio owns the world.** Rojo syncs `game/src/` into Studio (ServerScriptService,
  ReplicatedStorage, StarterPlayerScripts). The map, models and lighting are built in Studio and saved in the place
  file, not in git. ⛔ Don't edit a Rojo-synced script inside Studio. The next sync overwrites it.
- **Only one machine runs `rojo serve` into the shared place at a time** (normally Joshua's). The other brother
  builds the world in Team Create.
- **Data and Robux live on the server.** Never trust the client for currency, purchases or progress. Every
  RemoteEvent is validated on the server.
- Lint and format before you commit: `selene src` and `stylua --check src` from `game/`.

## Session end
Update `STATE.md` (top of `## Recent sessions`, live sections current), record any new ruling in
`memory/records/`, commit, push, and merge to `main` so the next session doesn't read a stale base.

## Output conventions (copied from `../joshua-hq/CLAUDE.md`, ruled 2026-08-30)
- **Artifacts are light-only.** No `prefers-color-scheme: dark` block, no dark variant, `color-scheme: light` on
  `:root`, and an explicit background on both `html` and `body`.
- **Check the narrow viewport before publishing.** Every grid or flex row gets exactly one child element per cell.
  Wrap mixed text and inline elements in a span.
