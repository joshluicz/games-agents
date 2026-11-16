# Agent skills for this repo

Claude Code loads every folder here as a skill. Cursor loads them too: its docs say it "also loads skills from Claude
and Codex directories" (https://cursor.com/docs/context/skills, checked 2026-11-16).

Roblox Studio also ships 13 official skills of its own (rbx-debug, rbx-unit-test, rbx-device-simulator-lua,
rbx-docs-search, rbx-perf-profiling, ...). They come through the Studio MCP server's `skill` tool; nothing to install.

## Vendored: gamedev-skills/awesome-gamedev-agent-skills
- Source: https://github.com/gamedev-skills/awesome-gamedev-agent-skills (Apache-2.0, 9.0k stars on 2026-11-16)
- Pinned commit: `c6ca6c41c839b68319ffc08430b99ab768debc32`, copied unchanged on 2026-11-16
- Licence and notice: `_vendor/gamedev-skills/LICENSE`, `_vendor/gamedev-skills/NOTICE`
- Skills: roblox-luau, roblox-networking, roblox-datastores, roblox-ui, roblox-studio-workflow, roblox-characters,
  roblox-physics, roblox-simulator-economy, game-feel, game-ui-ux

⚠️ This repo's `CLAUDE.md` wins over any skill. In particular, red line 3 (players are mostly children; nothing
pressures a kid into spending) overrides `roblox-simulator-economy`'s rebirth and paid-egg patterns. Use its pacing
maths, not its monetisation habits.

To update: re-download at a newer commit, diff against these folders, and bump the pinned commit above.
