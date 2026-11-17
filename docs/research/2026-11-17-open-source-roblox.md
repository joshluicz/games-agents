# Open-source code and free assets we could use (2026-11-17)

Joshua: "can you see if there are scripts/arrows available online libraries. i think its time we look at open source
stuff we can use." Licences, stars and release dates come live from the GitHub API (`gh api repos/<owner>/<repo>`) and
from the pages linked below, all checked on 2026-11-17. A "release" is the newest GitHub release or tag. "Last commit"
is the newest push to the default branch.

**Short answer:**
- The arrow *scripts* online do less than our `UI/Wayfinder` already does, and two of them have no licence. What we're
  missing is the *art*: `Config` still has `BeamTexture = ""` and `CheckerTexture = ""`, and no image of ours is
  uploaded yet (`game/src` has no `rbxassetid` at all).
- Most big libraries (UI frameworks, data, networking) solve problems our ~140 hand-written files already solve.
  Switching would cost weeks, and with the data libraries it would put live saves at risk. A few small single-file
  libraries are worth having.
- The biggest free win is **sound**. `Feel/Sounds.luau` builds every cue from Roblox's 11 built-in engine sounds,
  while Roblox's licensed sound-effect library is free to use in-game.

## 1. Guide arrows and waypoint markers

| Resource | What it is | Licence, date | Verdict |
|---|---|---|---|
| **ArrowBeams** by itsDenDenn ([DevForum](https://devforum.roblox.com/t/3045079), 2024-06-29; [GitHub](https://github.com/itsDenDen/ArrowBeams)) | A module that draws a Beam from the player to an objective | **No licence** (GitHub API); last commit 2024-12-21 | Values only. We already took its numbers in `tutorial-ux` §5.5 |
| **Free Open-Source Tutorial System** by Kyanid ([DevForum](https://devforum.roblox.com/t/4932428), 2026-10-13; [Creator Store 86212466038599](https://create.roblox.com/store/asset/86212466038599)) | A bouncing arrow with a highlight box, an arrow trail on the ground, an arrow over the head, typewriter text | No named licence: "You may not re-sell or claim this as your own". The post links to a showcase site off Roblox | Ideas only. We already do the trail and the highlight. **No typewriter** (`tutorial-ux` §3) |
| **OnBoard** by Henrycooper9 ([DevForum](https://devforum.roblox.com/t/4751478), 2026-07-22; [GitHub](https://github.com/henryrbx/Onboard)) | Dims the screen around a UI button, plus 3D arrows, beam indicators and pointer arrows | **No licence file** (GitHub API); last commit 2026-08-04 | Ideas only. Our `TutorialPointer` does the dim and ring |
| **Pathfinding beam** ([DevForum](https://devforum.roblox.com/t/843330), 2020-10-29) | Compute a PathfindingService path, then draw one beam or part per waypoint segment | A recipe, not a library | Already built: Wayfinder bends round walls with PathfindingService "knees" (`BeamMaxSpans` 4) |
| **ProPath** ([DevForum](https://devforum.roblox.com/t/4691204), 2026-06-18) · **SimplePath** ([GitHub](https://github.com/ahmicy/simplepath)) | Pathfinding for NPCs. ProPath's "Visualize" only spawns debug spheres | ProPath: no licence. SimplePath: MIT, last release v2.2.1 on 2022-02-28 | Skip. Our creatures move by `PivotTo` (server `Patients`, `Nurses`), not by Humanoid walking |

**Can we copy them?** On Roblox, the Creator Terms say you may not copy or modify another creator's UGC "unless you
have express written permission ... or unless the UGC is expressly made available for reuse, copying, or modification
as an asset in the Creator Store" (§5.2, [Terms of Use, effective 2026-11-01](https://en.help.roblox.com/hc/en-us/articles/115004647846-Roblox-Terms-of-Use)).
Code on GitHub with no licence is "all rights reserved": "no one may reproduce, distribute, or create derivative works"
([GitHub Docs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)).
So read these for ideas. Don't paste them into `src/`.

### The arrow image for the beam
- **Draw it ourselves (recommended).** It's one white ">" with a 10-12 px dark outline on a 160 × 128 px transparent
  PNG (the spec is in `tutorial-ux` §5.5). A shape this simple needs no licence, and it keeps red line 2 clean.
  - That size matched a 1.6-stud beam. A Wayfinder change in progress (not yet committed on 2026-11-17) makes the
    strip's middle `BeamCoreWidth = 2`, so scale the PNG's height to match whatever width ships.
- **If you want a starting shape**, use one with no credit requirement:
  - [Kenney](https://kenney.nl/support): "all game assets on the asset pages are public domain licensed (CC0)", "even
    in commercial projects", and "Attribution is not required". Don't use the Kenney logo. The CC0 packs
    [Game Icons](https://kenney.nl/assets/game-icons) (105 files, 2014) and [UI Pack](https://kenney.nl/assets/ui-pack)
    (430 files, v2.0) don't list arrows by name, so open the zip before you count on one.
  - [Material Symbols](https://github.com/google/material-design-icons) (Apache-2.0) and
    [Tabler Icons](https://github.com/tabler/tabler-icons) (MIT, v3.52.0 on 2026-11-14) both have chevrons. Keep their
    licence notice in the repo.
- **Don't point the beam at someone else's Creator Store image.** Reuse is allowed (§5.2 above), but the uploader only
  *warrants* that they own it (Creator Terms §3.2), it may be ripped from another game, and if they delete it our beam
  goes blank.

### Uploading an image under Joshua's account
- **Use Studio's Asset Manager → Import.** "Imported assets enter the moderation queue and, upon approval, are added to
  the inventory of the user/group that owns the game" ([Asset Manager](https://create.roblox.com/docs/projects/assets/manager)).
  The place is owned by JokingPuzzle (`STATE.md`), so the image lands under Joshua's account. Right-click it and
  choose **Copy Asset ID**, then paste it into `Config` as `rbxassetid://<id>`.
- **Formats:** .png, .jpg, .gif, .tga or .bmp ([Importer](https://create.roblox.com/docs/art/modeling/3d-importer)).
- **Moderation and privacy:** review "generally happens within a few hours". Players can't see the image until it's
  approved, and "all assets are private" by default ([Assets](https://create.roblox.com/docs/projects/assets)).
- **Cost:** none of these pages lists a fee for importing images, and neither does the Open Cloud guide. If Studio ever
  asks for Robux, stop: that needs both brothers' yes (red line 4).
- **The Open Cloud Assets API** (`POST /v1/assets`) needs an API key with asset read and write. It takes a user or a
  group as the creator, and images must be under 8000 × 8000 px and at most 20 MB
  ([usage guide](https://create.roblox.com/docs/cloud/guides/usage-assets)). It's only worth it for bulk uploads. It
  returns a *Decal* ID, and as of the last reply on 2025-05-03 a [DevForum thread](https://devforum.roblox.com/t/3594046)
  still calls getting the Image ID from it unsolved. **Use the Asset Manager.**
- **Images can't be updated after upload** (usage guide: "Not available for updating"). A new version means a new ID
  and a one-line `Config` edit.

## 2. Libraries

**How they'd install.** [Wally](https://github.com/UpliftGames/wally) (the tool is MPL-2.0; it isn't shipped in the
game) has a newest stable release of v0.3.2 (2023-06-05) and v0.4.0-alpha.1 (2026-10-12). It can be pinned in
`rokit.toml`. `wally install` fills a `Packages/` folder that you map in `default.project.json` under
ReplicatedStorage ([Roblox: third-party tools](https://create.roblox.com/docs/projects/external-tools)).

Our Lune specs require modules by file path (for example `tests/Belt.spec.luau` has `require("../src/shared/Logic/Belt")`).
A module that requires `ReplicatedStorage.Packages.X` can't load in a spec without a stub. So two rules:
- Keep every library out of `shared/Logic` and `shared/Data`.
- For single-file MIT code, **copy it into `src/shared/Vendor/` with its licence header** instead of adding Wally. MIT
  says the notice "shall be included in all copies" ([spr LICENSE](https://github.com/Fraktality/spr/blob/master/LICENSE)).

| Area | Library | What it does | Licence | Newest release · last commit | Install | For us |
|---|---|---|---|---|---|---|
| UI | [Fusion](https://github.com/dphfox/Fusion) | Reactive state and UI building | MIT | v0.3-beta, 2024-08-30 (main is 0.4.0-dev1) · 2026-02-02 | Wally `elttob/fusion` | **Skip.** It would mean rewriting 25 `UI/` modules and `Kit` |
| UI | [Vide](https://github.com/centau/vide) | Reactive UI in the style of Solid | MIT | 0.4.1, 2026-07-11 (marked pre-release) · 2026-10-26 | Wally `centau/vide` | **Skip.** Best of the three for a *new* game |
| UI | [React-lua](https://github.com/jsdotlua/react-lua) | A port of React 17 | MIT | v17.2.1, 2024-12-04 · 2025-05-23 | Wally | **Skip** |
| Springs | [spr](https://github.com/Fraktality/spr) | Spring animation of any property, which can change target mid-move | MIT | v2.1.0, 2023-07-13 · 2024-07-31 | **One file** (`spr.lua`, 21 KB): copy it | **Use now** (shortlist #4) |
| Springs | [Ripple](https://github.com/littensy/ripple) | Spring objects (`createSpring`, `setGoal`) | MIT | v0.10.2, 2026-07-18 | Wally / npm | Later, if spr falls short |
| Cleanup | [Trove](https://github.com/Sleitnick/RbxUtil) (RbxUtil) · [Janitor](https://github.com/howmanysmall/Janitor) | Track connections and instances, then clean them all up at once | MIT · MIT | trove 1.8.0 (RbxUtil commit 2026-07-27) · Janitor v1.17.0, 2024-08-12 | Wally, or copy `trove/init.luau` | **Later.** `Kit` and `MiniGames` already clean up with `Destroying` and `Cleanups` lists |
| Networking | [Zap](https://github.com/red-blox/zap) · [Blink](https://github.com/1Axen/blink) · [ByteNet](https://github.com/ffrostfall/ByteNet) | Generate remotes that pack data into buffers | MIT | v0.6.29, 2026-06-23 · v0.18.9, 2026-09-19 · v0.4.3, 2024-03-10 | A CLI generates code | **Skip.** `Remotes.serve` already does rate limits and pcall, and 6-player servers don't need the bandwidth |
| Data | [ProfileStore](https://github.com/MadStudioRoblox/ProfileStore) | Session-locked, auto-saving player data | Apache-2.0 | Wally 1.0.3 · 2025-07-31 | Wally `lm-loleris/profilestore` | **Skip** (risk below) |
| Data | [Lyra](https://github.com/paradoxum-games/lyra) | "Advanced player data management" | MIT | v0.6.0, 2025-07-08 · 2026-03-25 | Wally | **Skip** |
| Pathfinding | [SimplePath](https://github.com/ahmicy/simplepath) | Humanoid and NPC pathfinding | MIT | v2.2.1, 2022-02-28 · 2026-06-12 | Creator Store model or GitHub | **Skip** (§1) |
| Camera | [RbxCameraShaker](https://github.com/Sleitnick/RbxCameraShaker) | Camera shake | MIT | last commit 2019-12-15 | Copy | **Skip.** Unmaintained. RbxUtil's `shake` module covers it if we ever need shake |
| Debug UI | [Iris](https://github.com/SirMallard/Iris) | Dear ImGui-style windows for debugging and tuning | MIT | v2.5.1, 2026-03-27 (ships an `.rbxm`) · 2026-10-24 | rbxm or Wally | **Later** (shortlist #5), Studio only |
| Top bar | [TopbarPlus](https://github.com/1ForeverHD/TopbarPlus) | Icons in Roblox's top bar | ⚠️ **MPL-2.0** (file-level copyleft) **plus a credit clause**: keep its attribute or credit it in the game description | v3.5.0, 2026-10-19 | Wally | **Skip.** The HUD rails already do this job |
| Testing | [Jest-Lua](https://github.com/jsdotlua/jest-lua) · [TestEZ](https://github.com/Roblox/testez) | Test runners. Jest-Lua "can currently only run inside of Roblox" (its README) | MIT · Apache-2.0 | v3.10.0, 2024-12-23 · TestEZ **archived** (v0.4.2, 2022-01-05) | Wally | **Skip.** Our Lune harness (`tests/run.luau`, ~1,600 specs) runs without Studio |
| Analytics | [GameAnalytics SDK](https://github.com/GameAnalytics/GA-SDK-ROBLOX) | Sends player events to an outside analytics service | MIT | last commit 2026-10-07 | Wally / Rojo | ⛔ **Kids flag.** You must "enable HTTP requests", and their example user id is the player's display name ([GA docs](https://docs.gameanalytics.com/event-tracking-and-integrations/sdks-and-collection-api/game-engine-sdks/roblox)). Use Roblox's own analytics |

I found nothing worth adding for sound or VFX *code*. `Feel/Sounds.luau` and `CureFX` already put those in one place.
The gap there is assets (§3).

**Why not ProfileStore, even though it's good.** It "prevents other game servers from accessing this data too soon by
establishing a session lock" ([README](https://github.com/MadStudioRoblox/ProfileStore)). `Server/PlayerData` already
does that: it uses `UpdateAsync` with a leased lock, stores records as `{ Data, Lock }`, and is covered by the
`PlayerData` and `PlayerDataServer` specs. ProfileStore uses its own record shape, so every existing save would need a
migration on first load. The game is live (16+). One bug in that migration loses a real player's clinic, and the
Player Market is exactly where a dupe would hurt. Read its docs as a checklist against our code. Don't swap.

## 3. Free assets: sounds, icons, textures

| Source | Licence | Commercial use? | Credit needed? | Notes |
|---|---|---|---|---|
| **Roblox's Creator Store audio** | Roblox's "Licensed Music", which includes sound effects (Creator Terms §7.1) | ✅ in the game | No: "You are not required to provide attribution" (§7.1.4) | "More than 100,000 professionally-produced sound effects and music tracks" ([Audio assets](https://create.roblox.com/docs/audio/assets)). ⚠️ **Only on Roblox:** you may not "export, extract, download ... for use anywhere outside of the Services" (§7.1). So these can't go in a YouTube or TikTok trailer you edit off Roblox |
| Other creators' Creator Store images and sounds | Reuse allowed by Creator Terms §5.2 | ✅ | No | The uploader may not really own it. Only take Roblox-made assets or ones you can trace |
| **[Kenney](https://kenney.nl/support)** | CC0 | ✅ | No | E.g. [Interface Sounds](https://kenney.nl/assets/interface-sounds): 100 sounds, 2020. We upload them as our own, so they're also fine in trailers. [Input Prompts](https://kenney.nl/assets/input-prompts) (1,500 glyphs) isn't needed: we use `GetImageForKeyCode` |
| [Freesound](https://freesound.org/help/faq/) | Per sound: CC0, CC BY, CC BY-NC, or the old Sampling+ | Only CC0 and CC BY. **BY-NC: "you can't earn any money"** | CC BY: yes | Filter to **CC0 only** |
| [Pixabay](https://pixabay.com/service/license-summary/) | Pixabay Content License | ✅ ("Use Content for free") | No | You can't redistribute a file unchanged "on a Standalone basis". Content showing a trademark or logo can't be used "for commercial purposes in relation to goods and services" |
| [OpenGameArt](https://opengameart.org/content/faq) | Mixed: CC0, CC-BY, CC-BY-SA, GPL, OGA-BY | Depends on the licence | Most need credit | ⛔ **GPL and CC-BY-SA are copyleft.** Take CC0 only |
| [game-icons.net](https://game-icons.net/about.html) | CC BY 3.0 | ✅ "even commercially" ([deed](https://creativecommons.org/licenses/by/3.0/)) | **Yes**: "Icons made by {author}. Available on https://game-icons.net" | ⚠️ The deed also says "You may not apply ... technological measures", and Roblox assets are private by default. Avoid |

**Roblox's own upload rules.**
- You must hold the rights. The Terms say "you have the right to do so" (§3.1), and the audio page says "You have the
  legal rights to that audio asset".
- Audio: .mp3, .ogg, .wav or .flac, under 20 MB, under 7 minutes, at most 48 kHz ([Audio assets](https://create.roblox.com/docs/audio/assets)).
- **The audio quotas disagree between Roblox's own pages.**
  - The Audio assets page: 2,000 free uploads per 30 days if ID-verified, 100 if not.
  - The [Open Cloud guide](https://create.roblox.com/docs/cloud/guides/usage-assets): 100 a month if ID-verified, 10
    if not.
  - Either way, upload a few sounds at a time through the Asset Manager.

**Kids flags.** None of these asset sources puts ads, links or data collection into the game. The flags in this
document are all about code:
- GameAnalytics sends player data off Roblox. ⛔
- TopbarPlus asks for a credit in the game description, which is public text (red line 4).
- The Tutorial System post links to an outside site. Never carry such a link into the game.

## 4. Ranked shortlist: what to adopt first

| # | Adopt | What it changes in the game | Effort |
|---|---|---|---|
| 1 | **Our own chevron PNG**, plus the lawn's checker texture, imported through the Asset Manager into `Config` `BeamTexture` and `CheckerTexture` | The tutorial floor beam stops being a flat tinted strip. Chevrons flow toward the station, so a child sees *which way* to walk. The lawn gets its checker | ~1 h: draw two PNGs, import, wait a few hours for moderation, paste the IDs, one Studio test. Config only, no code. Joshua imports (the place owner) |
| 2 | **Roblox-licensed sound effects** from the Creator Store, put in `Sounds.SOURCES` (the file already says "To swap in a licensed Creator Store sound later, change SOURCES only") | Real pops, coin clinks, potion bubbles and a cure fanfare in place of the slider-blip melodies. This is the biggest juice win for the least code | ½ day: pick 10-15 sounds, listen in Studio, retune volumes. Cues built from `Notes` become single sounds. No uploads, no quota. In-game only |
| 3 | **Kenney CC0 audio** for the few signature sounds we want to *own* (the cure jingle, the level-up) | The same sound in the game and in any trailer, with no licence question | 1-2 h, including the upload quota. Note the source in a credits line even though CC0 doesn't require it |
| 4 | **spr**, vendored as `src/shared/Vendor/spr.luau` with its MIT header | Bouncier UI (`Kit.bump`, count-ups, panel pops) and creature squash that can change target mid-move and settles naturally | 1 h to vendor (exclude it from selene and StyLua, or leave it as-is), then migrate call sites one at a time. It calls `game:GetService("RunService")` when required, so check the client specs that load UI modules (`Juice`, `Motion`) still pass |
| 5 | **Iris**, Studio only (behind `RunService:IsStudio()`) | A live slider window for beam width and speed and the juice numbers while Joshua watches a play-test, so tuning no longer needs a Config edit and a restart. Players never see it | 2-3 h. It must never load in a live server, so add a spec that checks the guard |

Not adopted, and why: Wally (not needed for single files), the UI frameworks (a rewrite), ProfileStore and Lyra
(save-migration risk), Zap, Blink and ByteNet (no need at 6 players), GameAnalytics (kids flag), and the arrow modules
(ours does more, and two have no licence).
