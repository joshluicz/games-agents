# Tools, skills and plugins (2026-11-16)

Stars, push dates and licences are live from `gh api` on 2026-11-16. Creator Store links are
`https://create.roblox.com/store/asset/<ID>`. Installed so far: the 10 skills in `.claude/skills/` (see its README).

## Agent skills and Claude Code plugins
| What | ★ | Licence | Verdict |
|---|---|---|---|
| **Studio's built-in skills** (official): rbx-unit-test, rbx-debug, rbx-device-simulator-lua, rbx-docs-search, rbx-perf-profiling, rbx-scene-analysis, rbx-network-simulator, rbx-instrument-analytics, rbx-configs-experimentation, rbx-open-cloud-usage, rbx-permissions, rbx-import-asset, rbx-create-skill | – | Roblox | ✅ Already there through the Studio MCP `skill` tool |
| [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | 9,028 | Apache-2.0 | ✅ 10 skills vendored into `.claude/skills/` |
| [Roblox/roblox-studio-agent-plugin](https://github.com/Roblox/roblox-studio-agent-plugin) (official) | 40 | MIT | Skip for now: an MCP config plus a `roblox-get-started` skill. Our MCP is already connected |
| [EL4CTEO/roblox-skills](https://github.com/EL4CTEO/roblox-skills) | 119 | MIT | Best community pack: 23 skills, CI type-checks its examples. Ships a zip for **Studio Assistant**, which could help the brother. Overlaps what we installed |
| [excaldev/ro-engineer](https://github.com/excaldev/ro-engineer) | 44 | MIT | One routed skill; its retention notes flag patterns that manipulate children. Worth reading |
| [TemporaryLooker22/Stud-UI-Clean-Roblox](https://github.com/TemporaryLooker22/Stud-UI-Clean-Roblox) | 50 | MIT | ⛔ Copies another game's UI. Breaks red line 2 |
| brockmartin/roblox-game-skill 463★ (no licence) · TabooHarmony/roblox-brain 193★ · MSayib/roblox-dev-skill 92★ · AshExplained/roblox-skills 59★ · nonlooped/roblox-suite 32★ | | | Not needed now |

## Studio plugins (each brother installs his own; they don't sync through Team Create)
⚠️ **Install only by the exact asset ID below.** The Creator Store is full of $4.99 "Pro" knock-offs, "cracked"
re-uploads and copies from deleted groups, and backdoored re-uploads have a long history
([DevForum example](https://devforum.roblox.com/t/is-the-re-uploaded-moon-animator-2-plugin-a-backdoor/2845521)).
The "verified creator" badge doesn't tell real from fake. Paid plugins are a spend: both brothers say yes first.

**For building (the brother):**
| Plugin | Asset ID | Creator | Why |
|---|---|---|---|
| ResizeAlign | 165534573 | stravant | Snaps one face flush to another: walls, counters, shelves |
| GapFill & Extrude | 165687726 | stravant | Fills the gaps at corners and roof edges |
| Archimedes | 144938633 | Scriptos | Arches, round walls, curved counters |
| Building Tools by F3X | 144950355 | GigsD4X | All-in-one move, resize, paint, material |
| Brushtool 2.1 | 2268520847 | XAXA | Scatters plants and props |
| Load Character Lite | 752585459 | AlreadyPro | Drops in an avatar to check door and counter heights |
| AutoScale Lite | 1496745047 | ZacBytes | Makes UI scale to fit phones |

**For code (Joshua):** Rojo plugin (via `rojo plugin install`, matched to 7.7.1) · [Luau LSP](https://github.com/JohnnyMorganz/luau-lsp)
in Cursor (Open VSX) plus its Companion plugin (10913122509) · [Jest Roblox](https://github.com/Roblox/jest-roblox)
through [Wally](https://github.com/UpliftGames/wally) for tests (TestEZ is archived) · [Lune](https://github.com/lune-org/lune)
for running Luau outside Studio.

Not verified: that each plugin works on Mac; how to install the official Roblox Claude Code plugin from `/plugin`.
