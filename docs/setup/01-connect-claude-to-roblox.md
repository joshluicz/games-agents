# Connect Claude to Roblox Studio, and keep the code in git

Checked against Roblox's own pages on **2026-11-16** (links at the bottom). Joshua is on **Windows** and runs
Claude Code. His brother is on **Mac** and builds the world in Studio. He doesn't need git, Rojo or Claude.

## The shape
```
 GitHub repo (games-agents/game/src)  ──Rojo──▶  Roblox Studio  ◀──MCP──  Claude Code (Joshua's Windows PC)
                                                      ▲
                                    Team Create (live, shared place)
                                                      │
                                       Brother's Mac: builds the shop/world
```
- **Rojo** syncs the Luau files in `game/src/` into Studio, so the code lives in git.
- **The Studio MCP server** is built into Studio now. It lets Claude look inside the open place, run Luau, start and
  stop playtests, read the console and take viewport screenshots. The old external `studio-rust-mcp-server` repo is
  archived; don't install it.
- **Team Create** lets both brothers edit the same place at the same time.

## Joshua: Windows (about 30 minutes, once)
1. **Roblox Studio.** Install it from create.roblox.com and sign in to *your* account.
2. **Age check + 2FA on your account.** Settings → verify with **government ID** (you're 18+), and turn on 2-Step
   Verification. Team Create with other people needs the age check. Publishing to all ages needs the ID and 2FA.
3. **Claude Code on Windows.** Install Git for Windows, then Claude Code (PowerShell):
   ```powershell
   irm https://claude.ai/install.ps1 | iex
   ```
   Claude Code needs a paid Claude plan (Pro or above). Your existing plan covers it.
4. **Turn on Studio's MCP server.** In Studio: **Assistant → … → Manage MCP Servers → Enable Studio as MCP server**.
5. **Connect Claude Code.** The easy way is **Assistant Settings → MCP Servers → Quick connect → turn on Claude Code**.
   The manual way, in a terminal:
   ```powershell
   claude mcp add Roblox_Studio -- cmd.exe /c %LOCALAPPDATA%\Roblox\mcp.bat
   ```
   Restart Studio and Claude Code. In Studio a **green indicator** shows the connected client. In Claude Code, `/mcp`
   should list `Roblox_Studio`.
6. **Rokit, which installs the pinned Rojo, selene and StyLua.** Follow the install line in Rokit's README
   (github.com/rojo-rbx/rokit). Then:
   ```powershell
   git clone https://github.com/joshluicz/games-agents
   cd games-agents\game
   rokit install
   rojo plugin install
   ```
7. **Make the place.** In Studio: New → **Baseplate** → **File → Publish to Roblox** (new game, leave it **Private**).
   Then **Game Settings → Security → Enable Studio Access to API Services** (so saving works while you playtest).
8. **Sync.** In `games-agents\game` run `rojo serve`. In Studio, open the **Rojo** plugin → **Connect**. The code
   appears under ServerScriptService, ReplicatedStorage and StarterPlayerScripts. Press **Play**.
9. **Work with Claude.** Run `claude` inside `games-agents`. Claude edits files, Rojo syncs them into Studio, and
   Claude playtests through MCP and reads the output.

⚠️ **Only Joshua's machine runs `rojo serve` into the shared place.** Two Rojo servers fight each other.
⛔ Don't edit the synced scripts inside Studio. Rojo overwrites them on the next sync. Change the files instead.

## Brother: Mac (about 15 minutes, once)
1. **Roblox Studio for Mac.** Install it and sign in to **his own** account.
2. **Age check** (facial age estimation) in his Roblox settings. Team Create needs it.
3. **The age rule for collaborating.** A 13–15-year-old can't join a Team Create session with an 18+ creator *by
   default*. One of these unblocks it:
   - Joshua and he are Roblox **friends**, then **Trusted Friends**, or
   - a parent links to his account and turns on **collaboration with all age groups** in parental controls.
4. **Joshua gives him Edit.** For a group-owned game, give his group role Edit. For a game on Joshua's own account,
   use Studio → **Collaborate / Manage Collaborators** → add him as **Edit** (friends only).
5. He opens the game in Studio (it appears under games shared with him) and builds. **No git, no Rojo, no Claude.**
   Studio's built-in **Assistant** can help him build, if it's available on his account.
⛔ **No Claude account for him.** Anthropic's consumer terms require users to be 18+. Claude runs on Joshua's machine.

## What Claude can and can't do here
- ✅ From the cloud session (this one): write and lint the Luau, plan, research, keep the repo.
- ✅ From Joshua's Windows Claude Code with MCP: all of that, plus look inside Studio, run code, playtest, screenshot.
- ⛔ A cloud session can't reach Studio. Studio runs only on Windows and Mac, so playtesting happens on Joshua's PC.

## Sources (fetched 2026-11-16)
- Studio MCP server: https://create.roblox.com/docs/studio/mcp (updated 2026-11-14)
- Archived external server: https://github.com/Roblox/studio-rust-mcp-server
- Rojo with Roblox: https://create.roblox.com/docs/projects/rojo · Rokit: https://create.roblox.com/docs/projects/external-tools
- Collaboration and age rules: https://create.roblox.com/docs/projects/collaboration
- Alternative to Rojo (Studio Script Sync): https://create.roblox.com/docs/scripting/sync
