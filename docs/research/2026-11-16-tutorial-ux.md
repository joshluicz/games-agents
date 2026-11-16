# Tutorial UX: what's weak, what the top games do, and a redesign (2026-11-16)

**Why:** Joshua played the live game today: "tutorial is meh. needs arrows, UI can be more entertaining." This doc
reads our tutorial against his screenshots (`13.png`, the "Hold at the potion table!" card, plus `11.png` and `12.png`).
It checks how the top Roblox games onboard new players today and proposes a step-by-step redesign with an API sketch.

**Target layout:** Joshua sent a screenshot of a trending game's tutorial as the target. Its file didn't come through,
so the coordinator described it:
- a **top-centre** dark navy card with a "TUTORIAL 1/9" tab;
- a thumbnail of the target, a big caps title and a yellow subtitle;
- a thin progress bar along the bottom edge;
- big flat **chevrons on the ground** leading to a **glowing target**.

We borrow that format (red line 2 allows a format). We copy none of its words, names or art.

**Joshua's call on the arrow (2026-11-17, verbatim):** "the arrow for tutorial should be at the bottom. ie closer to
the floor than an overhead. im not too sure for this one but most games i know connect the middle of the player body
to the arrow, to the objective."

So the **main cue is a guide beam**: chevrons flowing along a flat Beam from the player's hips (about 1.75 studs above
the floor) to the target's base. The floor chevrons and the glowing target support it (§3.2). The values and the
recipe are in §5.5.

**Rules this design keeps:**
- Kids' rules (red line 3): no pressure to spend, no timers in the tutorial, and the tutorial can always be skipped.
- `memory-20261116-022` (Joshua, 2026-11-16): soft return pressure is wanted, and a countdown to a **free** upcoming
  event is allowed. The tutorial's own steps still have no timers. Only its last screen points at what's coming next.

**How to read the evidence:**
- **M** = measured, with its source and date. **C** = commentary or inference.
- Sources were fetched 2026-11-16 unless dated. Creator Hub API pages render without their text, so API facts come
  from Roblox's own `creator-docs` repo on GitHub, the source of those pages.
- Coverage of other games' tutorials comes mostly from third-party guide sites. Treat it as "what players report
  seeing", not design documents.

**Needs a yes before building (flagged, not decided here):**
1. **A Skip button.** It supersedes the first-session design's "No skip button" (`docs/plan/2026-11-16-first-session-design.md:50`,
   `game/README.md:206`). Once Joshua agrees, record it in `memory/records/`.
2. **The guide nurse's name and look.** Names come from the brothers (red line 1). See §6.
3. **An optional spoken voice** for the guide nurse (Roblox text-to-speech). See §4.

---

## 1. What's weak about ours today

### Where it sits and what it covers
- **The card is at the bottom centre** (`client/UI/Tutorial.luau:293-313`, AnchorPoint (0.5, 1)).
  - On a phone, that's the thumbs' zone: the thumbstick is bottom-left and jump is bottom-right.
  - Once the HUD is revealed, the 7-button bar lives there too (`12.png`). That's why the card needs a per-frame
    layout follow and a 64 px "finger room" lift (`:535-562`, `:64`).
  - In `13.png` the card covers the floor right in front of the character, exactly where ground arrows would go.
- **The instruction vanishes whenever any panel is open** (`cardStep` returns nil on `Hud.isOpen()`, `:450`). In step
  7 the Shop opens and only the ring and 👇 are left (`:384-406`).
- **The mini-games aren't in the tutorial.** Update 1 added them after the tutorial was written, so `LINES`
  (`:69-78`) has no mini-game step.
  - Step 4's "Take it to the Counter. Treat!" stays up while the Pour game plays.
  - MiniGames has its own ScreenGui (`client/UI/MiniGames.luau:219`, `:498`) and isn't a Hud modal, so the `:450`
    check never hides the card.
  - On short screens the two cards can overlap (not measured).

### Words
- **Step 3, "Hold at the potion table!"** (`:72`) doesn't say *what* you get or *why* the patient needs it.
  - The Creator Hub onboarding guide asks for both: "what they are expected to do and why".
  - Nothing in the world is labelled "potion table". In `13.png` the 🧪 and 🩹 tables carry near-identical icon discs.
- **Step 2, "The bubble shows what's wrong"** (`:71`) is abstract. The patient's badge already shows the recipe chip
  (🧪), and matching that icon to the 🧪 table is the lesson. The words never say so.
- **Step 5, "Resting… Cured! 🎉"** (`:74`) announces the cure *before* it lands. When it does land, the card has
  already switched to "Cure 2 more", so the best moment of the tutorial gets no celebration of its own.
- **Step 7, "Spend 💰 in the Shop!"** (`:76`) frames the step as spending. "Upgrade" is the goal. The cash is in-game
  only, but the word still leans the wrong way for red line 3.
- **No step count or progress anywhere.** A kid, or the parent next to them, can't tell how long this lasts.

### World pointers
- **The "arrow" is an arc in the air, not a path.** It's a FaceCamera Beam from the player's root, bowing upward
  (`client/UI/Guide.luau:238-265`, `CurveSize 5/-5`, `UP` at `:60`).
  - It reads as a rainbow from your belly rather than "walk this way".
  - It runs straight through the Counter, since nothing routes around it.
  - Joshua: "needs arrows", and the arrow should be "closer to the floor than an overhead" (2026-11-17).
- **The target itself never glows.** The only marker is the pin floating 3-3.8 studs above it (`:61-62`).
  - The arc hides within 8 studs (`:58`). Up close the pin then sits above the top of the camera's view.
  - In `13.png` the only visible marker on the potion table is its own icon disc, half under the awning. The
    plaster table next to it has an identical one.
- **The pin's bounce doesn't follow the device's Reduce Motion setting live.** It re-checks only when the in-game
  `ReduceEffects` attribute changes (`:371`), never on `GuiService.ReducedMotionEnabled` changing.

### Feedback
- **A step's success and the next instruction land in the same frame.** `render()` pops the next card and plays
  "Pop" (`client/UI/Tutorial.luau:489-491`). There's no ✓, no "yay", and no beat between "you did it" and "now do
  this".
- **The UI pointer is a bobbing 👇 emoji and a static ring** (`:398-406`, `:553`). There's no press motion showing
  *tap here*, and nothing pulses out from the button.

### Devices
- **"🎮 Hold X" is wrong on PlayStation** (`:112`, `:118`). The prompts use `ButtonX` (Roblox's default,
  `server/Patients.luau:1773`), and Roblox draws that as □ on a PlayStation pad.
  - `UserInputService:GetImageForKeyCode` returns the right glyph for the connected Xbox, PlayStation or Windows pad.
  - The mini-games have the same problem with "🅰️" (`client/UI/MiniGames.luau:448-455`), which is ✕ on PlayStation.
- **The hint chip's ⌨️ emoji renders small and grey** in the outlined display font (`13.png`;
  `client/UI/Tutorial.luau:353-368`, `Outlined = true` at Small size).
- **Touch players aren't shown *where* to hold.** The default ProximityPrompt button floats in the world, and
  "👆 Tap and hold" doesn't point at it.

### Flow and time
- **The first ~10 seconds are passive.**
  - After the 3 s sweep, the welcome card waits 4 s for its ack (`Logic/Tutorial.luau:51`; `UI/Tutorial.luau:664-668`).
  - No patient is sent until that ack (`spawnPlan` WELCOME → "Wait", `Logic/Tutorial.luau:134-135`).
  - Then 2 more seconds pass at the Counter (`:50`).
- **The first 💰 lands about 25-45 s after the clinic is assigned.** That's an estimate from Config and the code (§3.4),
  not measured, and it assumes a kid who never hesitates.

### Skip, replay, measuring
- **No skip and no replay.** Only admins can jump the tutorial (`Tutorial.finish`/`restart`, `server/Tutorial.luau:236-251`).
  - The only remote is `TutorialAck` (`:284-294`).
  - A replay would also break the top-up rule "Once per player: step 7 is entered once, because steps only go
    forward" (`:16-19`, `:160-166`). It needs a saved flag (§5).
- **We can't see where kids drop off.** Nothing in `game/src` calls `AnalyticsService`. Roblox has a dedicated
  onboarding funnel for exactly this (§2.3).

### What's already good (keep it)
- Steps move only on real server events.
- Patience can't run out (steps 1-6), one patient at a time, and the HUD reveals itself.
- Calm mode exists, and the loops sleep when idle.
- The Guide keeps arrows until 3 cures (`client/UI/Guide.luau:55`). That fallback is what makes a safe Skip possible.

---

## 2. What the top games do

### 2.1 The charts today
**M**, measured 2026-11-16 15:39 UTC from Roblox's own chart feed (`apis.roblox.com/explore-api/v1/get-sort-content`,
sort `top-playing-now`, the data behind roblox.com/charts). Player counts are live concurrent players.

| # | Game | Playing | Kind |
|---|---|---|---|
| 1 | Steal An Egg | 886,976 | steal-and-collect simulator |
| 2 | Brookhaven RP | 356,358 | roleplay |
| 3 | Throw Food For Animals | 325,158 | collect simulator (also #1 trending) |
| 4 | Blox Fruits | 310,745 | RPG |
| 5 | Adopt Me! | 231,879 | pet roleplay |
| 6 | 99 Nights in the Forest | 148,742 | co-op survival |
| 10 | Break and Steal an Egg | 86,977 | steal-and-collect |
| 18 | Dress To Impress | 51,757 | dress-up |
| 20 | Pet Simulator 99 | 49,501 | simulator / tycoon |

Off the top 20 the same hour (Roblox games API, `games.roblox.com/v1/games`): Steal a Brainrot 40,985, Grow a
Garden 16,651, Welcome to Bloxburg 10,319.

**C:** The chart is collect-and-grow simulators plus the two roleplay giants. Simulators onboard with a guided first
loop: go here, do this, get a thing. Roleplay games lean on checklists. Our clinic loop is a simulator loop.

### 2.2 The techniques, and who uses them

| Technique | Seen in (source, date) | For us |
|---|---|---|
| **A beam from the player's body to the objective** | The standard DevForum recipe since 2019: a client-side Beam from an attachment on the HumanoidRootPart (or torso) to one on the target. Tycoon "leading arrows" ([DevForum](https://devforum.roblox.com/t/359098), 2019-09-29); quest markers, "the attachments could be your torso and the part you're travelling to" ([DevForum](https://devforum.roblox.com/t/910415), 2020-12-07); hiding it once you're close ([DevForum](https://devforum.roblox.com/t/1924113), 2022-08-15). Community values: the ArrowBeams module uses FaceCamera on, Width 4, TextureLength 4, TextureSpeed 3, LightEmission 1, CurveSize 0, Segments 5 ([DevForum](https://devforum.roblox.com/t/3045079), 2024-06-29; source on GitHub, last commit 2024-12-21, no licence, so values only). A quest arrow uses Width 2.5 and TextureSpeed 5 ([DevForum](https://devforum.roblox.com/t/3177137), 2024-09-30). **None of these threads names the hit games that do it.** Joshua: "most games i know connect the middle of the player body to the arrow, to the objective" (2026-11-17) | **Yes, the main cue.** Ours is low and flat (FaceCamera off, at hip height), not the community default of a chest-height beam that faces the camera |
| **Ground arrows to each objective** | Climb For Animals Eggs: "Bright red directional arrows on the ground point toward each objective". Base → wall → egg → home → a reward that ends the tutorial ([allthings.how](https://allthings.how/how-to-play-climb-for-animals-eggs-full-beginner-s-guide/), updated 2026-10-14). Joshua's reference: flat chevrons, 6-8 studs, leading to a glowing target (coordinator's description, 2026-11-16) | **Yes**, as support on the floor under the beam |
| **An arrow over each target, plus a prompt line per step** | Fake an Egg: "Overhead arrows point to each target", four steps, each with an on-screen prompt ([allthings.how](https://allthings.how/fake-an-egg-roblox-how-to-play-full-guide/), updated 2026-10-19) | **Yes**: our bouncing pin. Its wording ("Quick, buy that egg!") rushes the player; we don't |
| **A top banner that says what's next** | Grow a Garden: "The top tutorial banner tells new players what to do next", e.g. "Talk to Sam!" ([allthings.how](https://allthings.how/?p=330478), updated 2026-11-07). Joshua's reference: top-centre card with "TUTORIAL 1/9" | **Yes**: the card moves to the top |
| **A guide character who talks** | Grow a Garden: Sam, the seed NPC, with a Talk prompt (same source). Adopt Me's Guide tasks include talking to the heart doctor ([roonby](https://roonby.com/2025/12/16/adopt-me-guide-feature-explained-how-to-use-it-and-get-free-items-fast/), 2025-12-16) | **Yes**: a UI guide nurse with one-line cheers |
| **A checklist that completes itself, with rewards** | Adopt Me's Guide: a panel on the right, Pets / Explore / Home tasks that "complete automatically", with Bucks and items as rewards (roonby, 2025-12-16) | Later, as the after-tutorial goals. 🎯 Goals already does this |
| **Dim the screen and spotlight a UI button; animated pointer arrows** | The OnBoard framework: "Darken the screen and focus player attention on important UI elements", "Animated pointer arrows" ([DevForum](https://devforum.roblox.com/t/4751478), 2026-07-22) | **Yes**, for the 🛒 step only |
| **A bouncing arrow with a highlight box, a ground arrow trail, an arrow over the head** | A free open-source tutorial system: "Bouncing arrow + highlight box", "Arrow trail on the ground", "Arrow above the player's head", plus "Typewriter text" ([DevForum](https://devforum.roblox.com/t/4932428), 2026-10-13) | Yes to the first two. **No typewriter**: it's slow for kids who read haltingly |
| **Mark the target in the world** | Roblox Developer Relations funnel example: the biggest drop (100% → 29.52%) was at "Plant Seed". The fix that worked was "adding an icon over the players' pots" ([DevForum](https://devforum.roblox.com/t/3064458), 2024-07-12) | **Yes**: the glow plus the pin |
| **Just-in-time steps, and hints only for players who are stuck** | Roblox Developer Relations: "contextual tutorials that provide just-in-time instructions" and "timed hints that target struggling players without adding to the onboarding time of players who don't need it" ([DevForum](https://devforum.roblox.com/t/2621940), 2023-09-28) | **Yes**: an idle nudge (§3.6), which is a hint, not a timer |
| **Get to the fun quickly; end with joy** | Creator Hub onboarding guide: teach what *and* why; starter currency; "Joy can be elicited through rewards, delightful animations, and celebratory visual effects" ([creator-docs](https://github.com/Roblox/creator-docs/blob/main/content/en-us/production/game-design/onboarding.md)) | **Yes**: a ✓ beat per step and a finale |
| **Start with a little money and a first purchase** | Steal a Brainrot: the player "starts with a base ... and a small amount of currency" and buys from the conveyor ([Wikipedia](https://en.wikipedia.org/wiki/Steal_a_Brainrot)) | Have it: the step-7 top-up gift |
| **A first-minute reward for like / favourite / group** | Steal An Egg gives free Speed for liking, favouriting and joining the group, "available the moment you load in" ([games.gg](https://games.gg/roblox/guides/steal-an-egg-beginner-guide/), 2026-08-29) | **Not in the tutorial.** `-022` says check the live Terms first, and it would pull a kid out of the loop |
| **Don't block with text** | RoWatcher (commentary, undated): the retention "cliff is almost always in the first 90 seconds". It argues for "environmental affordances", such as "a glowing door, an arrow", over text, and against dialogue that "can't be skipped" ([rowatcher](https://rowatcher.com/news/your-first-90-seconds-are-destroying-roblox-retention)) | **C:** matches our kids research: 5-8s read little and skip text, and need feedback "exaggerated or spoken" (`docs/research/2026-11-16-kids-audience-and-rules.md` §1) |

**Skip and replay:** none of the sources says how the top games handle skipping. The safest reading of them, plus our
own design note that "kids skip and then get lost", is this: **skip the cards but keep the arrows.** §3.5 has the
details.

**How fast the first reward lands:**
- The guides above give no timings.
- **C:** In every one of them the first payoff (a pet earning, a reward claimed, a seed bought) is the first loop
  itself, not a menu.
- Our target is the first ✓ within about 10 s of getting control, and the first 💰 within about 35 s (§3.4).

### 2.3 The engine facts the builder needs
- **Beam** ([Beam.yaml](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/Beam.yaml),
  [Beams guide](https://github.com/Roblox/creator-docs/blob/main/content/en-us/effects/beams.md),
  [TextureMode](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/enums/TextureMode.yaml)):
  - **Endpoints and curve:** `Attachment0` → `Attachment1` are the first and last points of a cubic Bézier.
    `CurveSize0` bends along Attachment0's **+X** and `CurveSize1` along Attachment1's **−X**.
  - **`Texture`:** unset draws a solid line.
  - **`TextureMode`:** `Wrap` repeats every `TextureLength` studs. `Stretch` repeats `TextureLength` times. `Static`
    "isn't supported for Beams" and behaves like Wrap.
  - **`TextureSpeed`:** default 1; positive scrolls from Attachment0 toward Attachment1, and 0 is still.
  - **`FaceCamera`:** keeps the segments turned to the camera. A beam is flat, so without it "it may not be visible
    from every angle".
  - **`Segments`:** default 10.
  - **Blending and layering:** `LightEmission` (0 = normal, 1 = additive), `LightInfluence` (0 = ignores lighting),
    and `ZOffset` to stop two beams fighting.
  - **Lying flat:** the docs don't say which attachment axis sets the ribbon's facing.
    - **The problem:** an attachment on a part that turns makes the beam turn with it. A beam set to (0, 0, −90) on
      both ends still rotated as the part moved ([DevForum](https://devforum.roblox.com/t/3323908), 2024-12-28).
      Rotating both attachments 90° was the usual advice ([DevForum](https://devforum.roblox.com/t/939716),
      2020-12-22).
    - **The working recipe** (the accepted answer, [DevForum](https://devforum.roblox.com/t/3168420), 2024-09-22):
      aim each attachment at the other, then roll them, which keeps the beam level.
      `Attachment0.WorldCFrame = CFrame.lookAt(Attachment0.WorldPosition, Attachment1.WorldPosition)`, the same for
      Attachment1 looking back, then `WorldOrientation += Vector3.new(0, 0, 90)` on Attachment0 and `(0, 0, 270)` on
      Attachment1. It needs both ends set ("beam curves wrongly if only one rotated right").
    - **Its consequence:** our start rides on the player, who turns. So the recipe is re-applied every frame while
      the beam shows (§5.5).
    - **A fallback:** `Segments = 1` stops a twist, though the beam can still turn (same 2024-12-28 thread).
  - **`LightEmission` affects how see-through a beam looks** (bug report,
    [DevForum](https://devforum.roblox.com/t/1469241), 2021-09-15). We keep it at 0.
  - **A fixed world point:** an Attachment parented to `Workspace.Terrain` with its `WorldCFrame` set. ArrowBeams
    does this for Vector3 targets.
  - **Roblox's own arrow-beam recipe** (Mansion of Wonder): an arrow texture, Static (= Wrap), FaceCamera on, and
    "Attachment0 connects to PlayerAttachment"
    ([connect-the-beam.md](https://github.com/Roblox/creator-docs/blob/main/content/en-us/education/build-it-play-it-mansion-of-wonder/connect-the-beam.md)).
    The DevForum's standard answer is the same: "One way this is commonly done is using a beam", one attachment on
    the player, one on the target ([DevForum](https://devforum.roblox.com/t/297875), 2019-06-24).
- **Highlight** ([highlighting.md](https://github.com/Roblox/creator-docs/blob/main/content/en-us/effects/highlighting.md)):
  - **The limit is now 255 at once, not 31.** "Studio only displays 255 simultaneous Highlight instances on the
    client-side at a time ... the additional ... are silently ignored." Roblox raised it from 31 ("Lights, Camera,
    More Highlights!", [DevForum](https://devforum.roblox.com/t/4061534), Roblox Rendering Team, 2025-11-10).
  - **Our own budget still says ≤ 1 in the world** (`docs/plan/2026-11-16-perf-budget.md:15`). Its "31" (`:43`) is
    out of date.
  - **Cost:** "The first Highlight rendered on the screen incurs most of the performance cost", plus "a
    post-processing cost" while any is visible. A disabled one still takes a slot.
  - **Advice from the docs:** change properties rather than adding and removing highlights, which "can trigger a
    geometry rebuilding step". Delete one you won't use again.
  - **`DepthMode`:** `AlwaysOnTop` shows through walls; `Occluded` hides behind them.
- **BillboardGui** ([BillboardGui.yaml](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/BillboardGui.yaml)):
  - `AlwaysOnTop` "always renders on top of 3D content".
  - `DistanceLowerLimit` stops it growing up close, and `MaxDistance` 0 means no limit.
  - Size's scale part is studs; its offset part is pixels.
  - Testing note (STATE, 2026-11-16): Studio MCP screen captures don't draw AlwaysOnTop billboards.
- **Reduced motion**
  ([GuiService.yaml](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/GuiService.yaml),
  [accessibility.md](https://github.com/Roblox/creator-docs/blob/main/content/en-us/production/publishing/accessibility.md),
  [DevForum](https://devforum.roblox.com/t/2723187), Roblox staff, 2023-11-29):
  - `GuiService.ReducedMotionEnabled` is read-only and maps to the "Reduce Motion" toggle in the Roblox and
    in-experience settings.
  - Use a fade instead of a fly-in, or an instant change. For looping motion, "stop the animation altogether or
    replace it with something in-place".
  - Watch it with `GetPropertyChangedSignal`. Our `Kit.reducedMotion()` already ORs it with the calm toggle
    (`client/UI/Kit.luau:216-225`).
  - **Also in the accessibility guide:** `PreferredTextSize` doesn't scale `TextScaled` text. "Over 5% of people ...
    have some form of color blindness", so pair colour with an icon.
- **Input**
  ([UserInputService.yaml](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/UserInputService.yaml),
  [PreferredInput enum](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/enums/PreferredInput.yaml),
  [DevForum full release](https://devforum.roblox.com/t/full-release-introducing-preferredinput-and-improved-touch-capabilities/3750890), 2025):
  - **`PreferredInput`** is `KeyboardAndMouse`, `Gamepad`, `Touch` or `MicroGamepad`, and it changes with the last
    device used.
  - **`GetImageForKeyCode(keyCode)`** returns the glyph "for the currently connected gamepad device (limited to Xbox,
    PlayStation, and Windows)".
  - **`GetStringForKeyCode`** gives the key to press for the player's keyboard layout.
- **ProximityPrompt** ([ProximityPrompt.yaml](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/ProximityPrompt.yaml)):
  - Keyboard defaults to E and gamepad to ButtonX.
  - `PromptShown` / `PromptHidden` fire on the client.
  - Mobile players can always tap the prompt's own button.
  - `Style = Custom` drops the default UI so we can draw our own.
- **Onboarding funnel**
  ([funnel-events.md](https://github.com/Roblox/creator-docs/blob/main/content/en-us/production/analytics/funnel-events.md)):
  - `AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)` runs **on the server, and only in published
    games**.
  - Only the first log of a step counts.
  - Logging a later step marks the earlier ones complete, so don't log the last step for a Skip.
- **Text-to-speech** ([DevForum](https://devforum.roblox.com/t/3986607), Roblox staff, full release 2025-10-09):
  - `AudioTextToSpeech` (real time) and `GenerateSpeechAsset` (reusable assets).
  - 10 voices; client-only output; text filtered.
  - Limits: "1 + 6 * number of concurrent users" requests per minute per experience, and 300 characters a request.
  - Baseline use is free.
  - English at launch; 10 more languages added 2026-08-11.

---

## 3. The proposed tutorial, step by step

### 3.1 The frame: one card at the top centre

```
 ┌──────────────┐                                   [ Skip ]
 │ TUTORIAL 2/7 │                                           
 ├──────────────┴──────────────────────────────────────┐ (o_o)  ← guide nurse peeks out on cheers
 │ ┌──────┐  MAKE A POTION                              │        
 │ │  🧪  │  Follow the arrows · hold [E]               │        
 │ └──────┘                                             │
 │ ████████ ████████ ░░░░░░░░ ░░░░░░░░ ░░░ ░░░ ░░░      │  ← 7 segments, fill on each ✓
 └─────────────────────────────────────────────────────┘
```

- **Where:** top centre, inside `CoreUISafeInsets` (`client/UI/Kit.luau:534`), so it sits below Roblox's top bar.
  - That's far from the thumbs, and it frees the floor in front of the character for the guide beam.
  - Grow a Garden and Joshua's reference both put it there.
- **Width:** `min(480 px, safe width − 2 × (the 💰 pill's right edge + 8 px))`, so it never covers the wallet.
- **Height:** 76 px on a short phone (under 500 px tall), 88 px otherwise, plus a 24 px tab.
- **Look:** our candy-pop take on the reference.
  - A **navy** card (new token `Theme.Colors.Navy`, e.g. RGB 34, 30, 86) with the usual thick dark outline.
  - The tab "TUTORIAL n/7" in yellow outlined LuckiestGuy (`Theme.Colors.Cash`).
  - The title in **white caps** (LuckiestGuy) and the subtitle in **yellow** FredokaOne.
  - White and yellow on navy is high contrast, and the dark card reads over the bright sky and awnings.
- **The thumbnail:** the target's icon on a tile in its colour (🧪 purple, Counter lime, the patient's ailment pink).
  On each success it flips to a lime ✓.
- **The progress bar:** 7 segments along the bottom edge. A segment fills with a little pop on each ✓, and step 6
  shows two pips inside its segment.
  - It is **never a timer**: it fills only on success and never drains.
- **Skip:** a small chip right of the tab, with its hit area padded to 56 × 44 px. §3.5 covers the two-tap confirm.
- **Touches:** the card takes none except Skip, so the thumbstick and camera drag still work under it.
- **When something else needs the screen:**
  - While a panel is open, the card hides. The UI pointer carries a short label instead (step 7).
  - During a mini-game it shrinks to a slim strip (tab + subtitle) so it clears the mini-game card.
- **Toasts:** they move below the card while it shows. Toasts are top-centre too (`client/UI/Toasts.luau:2`).

### 3.2 The world language: one main cue and its helpers
These pieces appear at every walking step.
1. **The guide beam (the main cue).** Joshua's call: low, from the middle of the body to the objective.
   - **Path:** a flat Beam from an Attachment on your HumanoidRootPart, dropped to about 1.75 studs above your feet
     (hip height), to an Attachment at the target's base on your side.
   - **Look:** our own chevron texture flowing toward the target. It's tinted the target's colour (🧪 purple, Counter
     lime) with a dark outline baked in.
     - FaceCamera is off, so it lies flat. It tilts a little when its two ends sit at different heights.
     - No overhead arc.
   - **Behaviour:**
     - It swings to the new target on each step.
     - It follows you as you walk and turn.
     - It bends round the Counter instead of cutting through it.
     - It hides within 6 studs of the target: you're there, and the glow takes over.
   - **Values and the per-frame recipe:** §5.5.
2. **The glowing target:** one Highlight, moved from target to target.
   - Colours: fill in the target's colour, outline white.
   - Motion: a slow pulse (1.6 s, the same rhythm as `Theme.Juice.BreathSeconds`).
   - It's the one Highlight the perf budget allows.
3. **The bouncing pin:** the existing candy map pin over the target, with the icon of what to do there
   (`client/UI/Guide.luau:267-337`). Up close it drops lower so it stays in frame.
4. **Floor chevrons (support):** a few flat ">" stamps on the floor along the beam's route.
   - Size and spacing: 4 studs wide, every 6 studs, up to 6. The reference's 6-8 studs is too big for a plot whose
     tables are 4.2 studs.
   - Look: white with a dark candy outline, faint (55% transparent).
   - Motion: none. The beam already moves.
   - They hide within 6 studs of the target, with the beam.
   - Their job: mark the walking route where the beam bends round the Counter, and stay readable from a high camera
     angle where a flat beam looks thin.
5. **Touch only, the hold hand:** a 👆 that presses and holds beside the station's Make prompt while a ring fills for
   the hold time. It shows only while that prompt is on screen (`PromptShown`).

### 3.3 The steps
There are 7 numbered cards. The server's steps (`Logic/Tutorial`, 1-9) stay as they are, so no save migration.
Card 4 is a client-only sub-step of server step 4, keyed on the `TreatStart` bus event.

Words follow the existing rule: icon first, a title of 4 words or fewer, a subtitle of about 7.
- `[E]` means a keycap chip from `GetStringForKeyCode`.
- `[□]` means the pad's real glyph from `GetImageForKeyCode`: X on Xbox, □ on PlayStation.

**Before card 1: the welcome (kept).** The 3 s camera sweep under "Welcome to Cure a Creature!" (`client/UI/Tutorial.luau:183-283`).
- Change: the client acks **as the sweep ends** (no 4 s welcome card), and the first patient is already hopping in
  (§3.4).
- Reduced motion: no sweep, just the title card (as today).

---

**1/7 · Meet the patient** (server steps 1 → 2)
- **Trigger:** the sweep ends and the ack is sent. The card shows while the patient walks in. It moves on 1 s after
  the patient reaches the Counter (the server's `Arrived`).
- **World:** the pin 👀 over the front patient, and the Highlight on the patient (soft pink). No beam or chevrons,
  since you already stand at the Counter.
- **Screen:** the thumbnail is the patient's ailment icon. The guide nurse pops out: "Hi, Doctor!"
- **Words:** **A SICK CREATURE!** · "🤧 Look at its bubble". Once it's at the Counter: "It needs a 🧪!" The icon comes
  from its recipe chip (`Recipe` attribute), so the lesson is "🧪 on the bubble = 🧪 table".
- **Success:** the recipe chip on its badge gives a bump. ✓, segment 1 fills, Chime.
- **Touch / keyboard / gamepad:** nothing to press; the same for every device.

**2/7 · Make the potion** (server step 3)
- **Trigger:** the server enters MAKE.
- **World:**
  - The guide beam from your hips to the 🧪 table's base, in purple, with floor chevrons under its route.
  - The Highlight on `Station_Remedy` (purple) and the pin 🧪.
  - Touch only: the hold hand next to the Make prompt.
- **Screen:** the thumbnail is 🧪 on purple.
- **Words:** **MAKE A POTION** · "Follow the arrows · hold [E]". Touch: "Follow the arrows · hold 👆 Make". Gamepad:
  "Follow the arrows · hold [□]".
- **Success:** the potion pops into your hands (the existing hands disc). The thumbnail flips to ✓, a small confetti
  burst comes from it, and Chime plays. The nurse says "Yay, a potion!" Segment 2 fills.
  - Hold the ✓ for 0.8 s **before** card 3 slides in.
  - The beam swings to the Counter in the same moment, so the path flows on.
- **Devices:** keyboard holds E. Gamepad holds ButtonX, shown as the real glyph. Touch holds the prompt's own button,
  and the hand shows where.

**3/7 · Give it the potion** (server step 4, before the mini-game)
- **Trigger:** the server enters TREAT. You're carrying what the patient needs, as today.
- **World:** the guide beam to the Counter's base (lime), the Highlight on `Counter` and the pin with the patient's
  ailment icon.
- **Words:** **GIVE IT THE POTION** · "Go to the glowing Counter · [E]". Touch: "· tap Treat". Gamepad: "· [□]".
- **Success:** `TreatStart` opens the mini-game, and card 4 takes over at once. The game itself is the payoff.
- **Devices:** the Treat prompt is a tap (`HoldDuration = 0`, `server/Patients.luau:1769`). The words say "tap" or
  "press", never "hold".

**4/7 · Pour it in** (client sub-step on `TreatStart` while server step 4)
- **Trigger:** the bus event `TreatStart` during step 4.
- **World:** beam, chevrons, glow and pin all hidden; the mini-game card covers the middle.
- **Screen:** the card shrinks to its slim strip. Touch only: a 👆 presses and holds on the mini-game stage for the
  first game.
- **Words:** **POUR IT IN!** · "Hold… let go on ⭐". That mirrors the mini-game's own hint
  (`client/UI/MiniGames.luau:262`), so the two cards say the same thing.
- **Success:** the rating pops (existing). The tutorial adds the nurse's line "Any ⭐ is great!", because OK still
  cures. ✓, segment 4.
- **Devices:** keyboard holds Space or the mouse. Gamepad holds ButtonA, shown as the real glyph (✕ on PlayStation;
  fix `pointer()`, `MiniGames.luau:448-455`). Touch holds the stage.

**5/7 · Rest and cure** (server step 5 → the cure)
- **Trigger:** the server enters REST (Treated).
- **World:** the pin 🛏️ over the patient on its bed (as today, `client/UI/Tutorial.luau:622-628`). No beam.
- **Words:** **RESTING…** · "🛏️ It's getting better". The card no longer says "Cured!" too early.
- **Success: the first-cure moment.** It's the biggest beat of the tutorial.
  - The card's title switches to **CURED! 🎉**, with rays and confetti behind the thumbnail (`Kit.celebrate`).
  - Coins and stars fly into 💰 and ⭐ (CureFX, existing), and the ⭐ pill reveals with a pop.
  - The nurse: "You did it, Doctor!" The sound is Celebrate.
  - The card holds about 2.5 s before card 6. The server is already at step 6; only the card waits.

**6/7 · Cure 2 more** (server step 6)
- **Trigger:** the server enters MORE. `TutorialCures` drives the two pips.
- **World:** the Guide's usual targeting, now drawn with the beam, glow, pin and floor chevrons. That's the station for the front
  patient's `FrontStation`, then the Counter once you carry something in `FrontNeeds`. The 🩹 patient teaches the
  second station.
- **Words:** **CURE 2 MORE** ○○. The subtitle follows what's happening:
  - "🤕 New patient! Check its bubble" when it arrives;
  - "It needs a 🩹!" once you can see its need;
  - "Now to the Counter · [E]" while you carry it.
- **Success:** per cure, a pip fills with a pop, a small confetti burst plays and the nurse says "One more!" or
  "Super!". After the second: ✓, segment 6.
- **Devices:** as cards 2 and 3. The first Patch game gets the touch hand on its first sore spot.
- **Mini-game time bar:** the Patch game's draining time bar is the only "clock" a new player meets
  (`MiniGames.luau:654`). Hide that bar while the tutorial runs. The game still ends by itself after its 4.5 s
  (`Config.luau:150`), and OK still cures.

**7/7 · Upgrade your clinic** (server steps 7 → 8)
- **Trigger:** the server enters SHOP. If the player is short, the existing top-up runs ("🎁 A gift to get you
  started!", in-game cash only).
- **World:** nothing; this is a UI step.
- **Screen, the UI pointer:**
  - The screen dims (55%) except a cutout round 🛒.
  - A ring sits on 🛒, a ripple pulses out from it every 1.2 s, and a 👆 hand taps in time with the ripple.
  - In the Shop (it opens on Upgrades, `client/UI/Hud.luau:1769-1771`), the pointer moves to the cheapest upgrade's
    Buy button with the label "Buy this! ⚡".
  - The card hides while the Shop is open, as panels need the space.
- **Words:** **UPGRADE YOUR CLINIC** · "Tap 🛒 · buy a ⚡". Gamepad: "[A] on 🛒". Mouse: "Click 🛒".
  - Never "Spend". The pointer never lands on anything paid. When passes exist, the Shop still opens on Upgrades and
    the pointer skips them.
- **Success:** the `Purchased` event plays the finale.
- **Devices:** touch and mouse tap. Gamepad: set `GuiService.SelectedObject` to the 🛒 button, then the Buy button
  (Hud already does this for modals, `client/UI/Hud.luau:275`), so one A press works.

**The finale** (server step 8 → 9 after 5 s, as today)
- **Screen:** a Celebrate screen, new Kind `"Tutorial"`, shown even though the tutorial is technically still running.
  - The ribbon reads **YOU DID IT!** (3 words, the Celebrate rule), with the guide nurse's face in the bubble.
  - Chips: "📖 Collect them all", "🎯 Daily goals", "👩‍⚕️ Hire nurses".
  - "🎉 Yay!" closes it, as do a tap and ButtonB.
- **One "COMING UP" chip** (per `-022`): the soonest **free** thing.
  - Candidates: "🌟 Golden Hour in 14 min" (Workspace `GoldenStartsAt`, set by `server/NurseBelt.luau:990`),
    "🌙 Night in 3 min" (`PhaseEndsAt`), or "🎁 Next gift in 2 min" (Playtime). A scheduled admin event joins the
    list once it exists (`-022` #2).
  - Minute precision, and it doesn't tick, so it stays calm.
  - It never shows anything paid. Joshua's own example was Golden Hour.
- **After it closes:** the rest of the HUD pops in one button at a time, 0.15 s apart. A ring sits on 📖 for a few
  seconds; that's old step 8's pointer, now without its own card. Then the Mailbox letter pops (existing).

### 3.4 How fast the first reward lands

| Moment | Today (estimated from Config and code, not measured) | Proposed |
|---|---|---|
| Clinic assigned → your controls back | 3.5 s (sweep 3 s + 0.5 s, `client/UI/Tutorial.luau:59`, `:654`) | same |
| Welcome card | +4 s or a tap (`Logic/Tutorial.luau:51`) | gone: the ack goes as the sweep ends |
| First patient at the Counter | sent only after the ack (`:134-135`) + hopping ~15 studs at ~12 studs/s (`server/Patients.luau:143-144`) + the spawn loop's own delay (not measured) | sent during step 1 (`spawnPlan` WELCOME → "First"), so it hops in under the sweep |
| Card 1 → 2 | +2 s at the Counter (`Logic/Tutorial.luau:50`) | +1 s (`ARRIVED_SECONDS = 1`) |
| Make | walk ~2 s + hold 2 s (`Config.luau:37`) | same, **first ✓ about 8-10 s after control returns** |
| Treat + Pour | walk + 3-5 s of game (`MiniGames.luau:232-234`, `Config.luau:149`) | same, a ✓ |
| Rest → cure | walk to the bed + 4 s (`Config.luau:31`) | same, **first 💰** |
| **First 💰** | **about 25-45 s** after the clinic is assigned, with zero hesitation | **about 20-35 s**, with a ✓ beat every 5-10 s on the way |

The funnel events (§5.2) will measure the real numbers. Real kids will be slower than these figures.

### 3.5 Skip and replay
- **Skip, always available.**
  - Tap the chip and it turns into "Skip? ✓ ✗". A kid who taps everything has to tap twice on purpose. If nothing
    happens, it quietly turns back after a few seconds, with no visible countdown.
  - Gamepad players get the same action as a "⏭️ Skip tutorial" row in ⚙️ Settings. The card chip isn't selectable,
    so it never steals pad focus.
  - The server's `TutorialSkip` moves any active step to DONE, and **never** gives the step-7 gift.
  - The HUD reveals fully, and a toast says "🔁 Replay anytime in ⚙️".
  - **The arrows stay:** the Guide keeps the beam, glow and pin until 3 cures (`client/UI/Guide.luau:55`). A kid who
    skips is never lost, which answers the old reason for "no skip".
- **Replay, for anyone who's done.**
  - ⚙️ → "🔁 Replay tutorial". The server's `TutorialReplay` (only from DONE, only with a clinic) empties the line,
    reusing the Admin restart path minus its respawn, and sets the step to PATIENT.
  - It's a replay for this session (`Snapshot.TutorialReplay = true`), so:
    - no title sweep;
    - the HUD stays full;
    - **no second top-up gift** (a saved `TutorialGift` flag, §5.2);
    - no funnel logs.
  - It can be skipped like the first run.

### 3.6 Stuck? A nudge, never a timer
If the player hasn't made progress for 20 s on a walking step, the guide nurse peeks out with **"Psst! Follow the
arrows ➜"**. The beam brightens once (its Transparency dips for 0.4 s), and that's it. This is Developer Relations' "timed hints that target
struggling players".
- It never shows a number and never repeats more than once a step.
- It counts no time while a panel is open.

---

## 4. What "more entertaining UI" means for us, concretely
The aim is cheerful and calm. **At most two things loop on screen at once:** the beam's flow and the pin bob, plus the
slow glow pulse. Nothing flashes faster than 3 times a second (WCAG 2.2, SC 2.3.1).

### Motion
| Piece | Normal | Calm (Reduce Motion or the in-game calm toggle) |
|---|---|---|
| Card arrives | slides down from the top with a little overshoot (`Theme.Tween.Slide`) | fades in (CanvasGroup `GroupTransparency`); no slide |
| Title changes | a quick punch (`Kit.punch`) | instant |
| ✓ on success | the thumbnail flips to ✓ with `Kit.bump`, 12-piece confetti from the thumbnail (`Kit.confetti`), and the segment fills (`Theme.Tween.Fill`) | ✓ appears, the segment fills instantly, no confetti |
| First cure | `Kit.celebrate` behind the thumbnail (rays + confetti) | still rays, no confetti |
| Guide beam | chevrons flow toward the target (`TextureSpeed` 1.5) | `TextureSpeed` 0: still arrows that still point the way. The beam keeps following you, since that's position, not motion for show |
| Floor chevrons | still (the beam already moves) | still |
| Glow | Highlight pulse, 1.6 s (OutlineTransparency 0 ↔ 0.35) | steady glow |
| Pin | bob (existing) | still (and it now re-syncs on `ReducedMotionEnabled` changing too) |
| Touch hand / UI hand | press-and-hold motion; a ripple from the button | a still hand + the word "HOLD" or "TAP" |
| Guide nurse | pops out with a bounce and a speech bubble, then tucks back | appears and goes, no bounce |

### The guide nurse
- **What it is:** a round portrait (`Hud.portrait(look)`) that peeks out of the card's right edge with a short speech
  bubble under the card.
- **When it talks:** only at a step's start, on a success, or for the §3.6 nudge.
- **Its lines:** 2-4 words ("Hi, Doctor!", "Yay, a potion!", "One more!", "You did it, Doctor!").
- **Its look:** an original nurse look built with the same rig as our nurses (`CreatureBuilder.buildLook`). It isn't
  one of the 16 hireable nurses, so the Journal stays a collection.
- **Its name and look are the brothers' call** (§6).
- **Not a walking NPC:** a 3D guide that follows you costs up to 40 parts and pathing, and draws the eye from the
  target.
- **Optional voice:** pre-made speech assets (`GenerateSpeechAsset`, fixed lines only, never player text) for its
  2-4-word lines. That helps 5-8-year-olds who can't read yet (our kids research: feedback "exaggerated or spoken").
  - A ⚙️ switch "🗣️ Nurse voice", on by default only if the brothers like the voice.
  - Without it, each line gets one soft chirp.

### Sounds
They use the existing cues in `client/Feel/Sounds.luau`. One sound per event, nothing looping, and no sound for a
chevron re-route.

| Event | Cue |
|---|---|
| Title card | Fanfare (as today) |
| A new card | Pop (as today) |
| A step's ✓ | Chime |
| The first cure | Celebrate |
| The finale | Fanfare |
| The nurse talks | a new short "Chirp" (Blip notes, like `Heart`), or its voice line |

### Confetti, progress, words
- **Confetti:** small bursts (12 pieces) for a step and the full set for the first cure and the finale. Nothing with
  reduced motion.
- **Progress:** the "TUTORIAL n/7" tab and the 7-segment bar, plus two pips in step 6. The bar fills only on success
  and never drains.
- **Words:**
  - Icons stand next to colour everywhere (colour-blind players).
  - Text is never under `Theme.TextSize.Small` (18).
  - Device glyphs are real images, not emoji in outlined text.
- **Text size:** the card's text is `TextScaled` today, so it ignores the player's Larger Text setting. Use `TextSize`
  with `AutomaticSize` on the subtitle so `PreferredTextSize` works.

### Later (out of scope for the tutorial)
A custom candy ProximityPrompt (`Style = Custom`) for every station and the Counter. It would replace the default grey
"E Make" in `13.png` with a big hold ring in the station's colour.

---

## 5. The API sketch for a builder

### 5.1 Files
| File | Change |
|---|---|
| `shared/Logic/Tutorial.luau` (pure) | `CARDS = 7`; `card(step, treating) -> number?`; events `"Skip"` (active → DONE) and `"Replay"` (DONE → PATIENT); `spawnPlan` WELCOME → `"First"`; `ARRIVED_SECONDS = 1`; `nudge(step) -> boolean` (walking steps only). Specs in `tests/Tutorial.spec.luau` |
| `shared/Logic/Schema.luau` | saved `TutorialGift: boolean` (reconcile: true for any save already at DONE, so a replay never gifts) |
| `shared/Remotes.luau` | RemoteFunctions `TutorialSkip()` and `TutorialReplay()`, served with `Remotes.serve` (rate-limited); arguments ignored |
| `server/Tutorial.luau` | Skip, Replay, the gift flag, the funnel (§5.2) |
| `server/State.luau` | Snapshot `TutorialReplay` (session only) |
| `client/UI/Tutorial.luau` | the new top card, Skip, the guide nurse, the step celebrations, the UI pointer (dim cutout, ring, ripple, hand) |
| `client/UI/Wayfinder.luau` (**new**, a library) | **the guide beam** (the main cue, §5.5), the floor chevrons, the one Highlight, the pin (moved out of Guide) and the touch hold hand |
| `client/UI/Guide.luau` | keeps choosing the target and the hold times; draws through Wayfinder instead of its own overhead arc (`Guide.luau:238-265` goes); `Steer` gains `Glow`, `Hand`, `Base`; re-syncs on `ReducedMotionEnabled` |
| `client/UI/Celebrate.luau` + `shared/Types.luau` | `CelebrateInfo.Kind` gains `"Tutorial"` (with a `Next` chip), allowed while the tutorial runs |
| `client/UI/Toasts.luau` | the stack starts below a reserved top height (bus event `"TopReserve"`, px) |
| `client/UI/Hud.luau` | ⚙️ rows "⏭️ Skip tutorial" / "🔁 Replay tutorial"; the one-at-a-time HUD reveal after the finale |
| `client/UI/MiniGames.luau` | glyphs from `GetImageForKeyCode`; hide the time bar during the tutorial; expose the stage (`MiniGames.stage(): GuiObject?`) for the touch hand |
| `client/Feel/Sounds.luau` | a `Chirp` cue |
| `client/UI/Theme.luau` | `Colors.Navy`; `Theme.Tutorial` sizes |
| `shared/Config.luau` | `Config.Tutorial` tuning (below). Today there's no tutorial entry in Config: its timings live in `Logic/Tutorial.luau:49-55` and `UI/Tutorial.luau:59-66` |
| `docs/plan/2026-11-16-perf-budget.md` | correct the "31" to 255 (`:43`); the ≤ 1 rule stays |

```lua
Config.Tutorial = {
	-- The guide beam (§5.5)
	BeamLift = 1.75, -- studs above your feet where the beam leaves your body (hip height)
	BeamEndLift = 0.25, -- studs above the floor where it meets the target's base
	BeamWidth = 1.6, -- Width0 = Width1
	BeamTextureLength = 2, -- a chevron every 2 studs
	BeamSpeed = 1.5, -- TextureSpeed (0 when calm)
	BeamMaxSpans = 4, -- bends: up to 3 knees
	BeamTexture = "", -- our own chevron strip once uploaded ("" = a solid strip until then)
	NearStuds = 6, -- the beam and the chevrons hide this close to the target (flat distance)
	-- The floor chevrons (support)
	ChevronStuds = 4, -- a chevron's width and length
	ChevronGap = 6, -- studs between chevrons along the route
	MaxChevrons = 6,
	FirstChevron = 3, -- studs ahead of your feet
	GlowSeconds = 1.6,
	NudgeSeconds = 20, -- the §3.6 hint (a hint, never shown as a number)
	SuccessHold = 0.8, -- the ✓ beat before the next card
}
```

### 5.2 Server and shared
```lua
-- Logic/Tutorial (pure)
Tutorial.CARDS = 7
function Tutorial.card(step: number, treating: boolean?): number?
	-- WELCOME/PATIENT -> 1, MAKE -> 2, TREAT -> 3 (4 while treating), REST -> 5, MORE -> 6, SHOP/BOOK -> 7
end
-- advance(step, "Skip") -> DONE for any active step; advance(DONE, "Replay") -> PATIENT.
-- Replay is the one deliberate exception to "steps only go forward"; say so in the header.

-- Server/Tutorial
--   TutorialSkip(p):   active only. move(p, DONE) without the gift. A custom log "TutorialSkipped" with the step,
--                      never LogOnboardingFunnelStepEvent: a later step would mark the earlier ones complete.
--   TutorialReplay(p): DONE and a clinic only. Empty the line (the Admin restart path, no respawn),
--                      replaying[p] = true (session), move(p, PATIENT).
--   move():            the top-up runs only when not d.TutorialGift, and sets d.TutorialGift = true in the same
--                      update. On a first run (not replaying), pcall(AnalyticsService.LogOnboardingFunnelStepEvent,
--                      AnalyticsService, p, card, CARD_NAMES[card]), with card = Logic.card(to).
--                      Server-only; published games only.
```

### 5.3 Client
```lua
-- UI/Wayfinder (a library, required by Guide; nothing runs until show())
export type Spec = {
	Target: Instance, -- a BasePart or Model: the Highlight's Adornee and the pin's anchor
	Base: Vector3?, -- where the beam ends, on the floor at the target's foot (default: §5.6)
	Icon: string, -- the pin's icon
	Color: Color3, -- the beam's tint and the glow
	Beam: boolean?, -- default true (false for the patient and the bed): the beam and the floor chevrons
	Glow: boolean?, -- default true
	Hand: ("Hold" | "Tap")?, -- touch only; shown while the target's prompt is on screen
}
function Wayfinder.show(spec: Spec) end -- same Target again = update in place (no flicker, no re-pop)
function Wayfinder.hide() end -- hides; keeps the instances for the next show
function Wayfinder.attach(character: Model) end -- a new character: a new GuideStart on its root (Guide does
--                                                 this on CharacterAdded today, Guide.luau:375-390)
function Wayfinder.destroy() end -- the end of the Guide: deletes the Highlight for good (Creator Hub advice)

-- UI/Tutorial
--   reads ctx.State.Tutorial, TutorialCures and TutorialReplay; the bus events TreatStart / TreatDone (card 4),
--   Open / ModalOpened / ModalClosed; the Cured remote (ctx.Remotes.Cured.OnClientEvent, as Feel/CureFX:828
--   does) for the card 5 celebration; UserInputService PreferredInput changes
--   (re-render the glyph); GuiService ReducedMotionEnabled changes
--   fires "TopReserve" (px) for Toasts; "Celebrate" { Kind = "Tutorial", Title = "YOU DID IT!", Next = ... }
--   asks TutorialAck (the sweep's end), TutorialSkip (the 2-tap chip)
```

### 5.4 The instances (all client-only, so nothing replicates)
```
Your character
└─ HumanoidRootPart
   └─ GuideStart               Attachment: the beam leaves your body here (BeamLift above your feet). Its
                               WorldCFrame is re-aimed every frame while the beam shows (§5.5)
Workspace.Terrain
└─ GuideEnd, GuideKnee_*       Attachments: fixed world points (the target's base; the bends). Two per bend,
                               one for each span, because an end can only face along one span
Workspace
└─ Wayfinder (Folder)
   ├─ GuideBeam_1 … _4         Beam: span 1 from GuideStart, the last to GuideEnd; usually just one
   │                           (values in §5.5)
   ├─ Chevron_1 … Chevron_6    Part: Anchored, 4 × 0.05 × 4, Transparency 1, CanCollide/CanQuery/CanTouch false,
   │  │                        CastShadow false
   │  └─ Face                  SurfaceGui: Face = Top, LightInfluence 0, SizingMode PixelsPerStud (32),
   │     │                     AlwaysOnTop false (walls still hide it)
   │     ├─ Left               Frame: a rounded bar rotated +45°, white at 55%, UICorner, UIStroke 4 px Outline
   │     └─ Right              Frame: the same bar at −45° (together a chevron); static
   ├─ Glow                     Highlight: Adornee = the target, DepthMode Occluded, FillColor = spec.Color,
   │                           FillTransparency 0.8, OutlineColor white, OutlineTransparency 0 (pulse 0 ↔ 0.35)
   ├─ Marker                   Part (Guide's ClinicGuide today)
   │  └─ Pin                   BillboardGui: AlwaysOnTop, MaxDistance 250, 84 × 118 px, StudsOffset bobbing
   │                           (0, 3, 0) ↔ (0, 3.8, 0); (0, 1.2, 0) when the camera is within 10 studs
   └─ Hand                     BillboardGui: Adornee = the station part, AlwaysOnTop, 72 × 72 px, offset to sit
                               beside the default prompt (check on the phone emulator), touch only
PlayerGui
├─ TutorialCard                ScreenGui: DisplayOrder Hud + 2, CoreUISafeInsets
│  └─ Card                     CanvasGroup (the fade for calm): Tab, Skip, Thumb (Icon / Check), Title,
│                              Sub (+ a Glyph ImageLabel or a Keycap), Bar (7 Segment), Pips, Nurse (portrait + Bubble)
└─ TutorialPointer             ScreenGui: DisplayOrder Panel + 5
   ├─ Dim (4 Frames)           the cutout round the target, Transparency 0.55, Active false (touches pass)
   ├─ Ring · Ripple            the ring on the button, and the ring that grows and fades from it
   └─ Hand · Label             👆 (or a drawn hand) and "Buy this! ⚡"
```
- **The floor chevron's direction:** it points toward the GUI's top. Turn each part with `CFrame.lookAt(at, at + dir)`.
  Check once in Studio which way Face = Top's top edge maps, and flip with `* CFrame.Angles(0, math.pi, 0)` if it
  points back. The floor chevrons are drawn in code, so they need no image upload.

### 5.5 The guide beam: values and the recipe
**The properties** (one span; every span uses the same values except `Transparency`):

| Property | Value | Why |
|---|---|---|
| `Attachment0` | `GuideStart`, on your HumanoidRootPart | it starts at your body. Positive `TextureSpeed` flows from Attachment0 to Attachment1 (docs). Roblox's own arrow tutorial warns that swapping the two makes the arrow point the wrong way |
| `Attachment1` | `GuideEnd`, under `Workspace.Terrain`, at the target's base | a world point works the same for a Part and a kit Model |
| `Texture` | our own chevron strip (an `rbxassetid` once uploaded); until then unset, which draws a solid strip | original art (red line 2). One white ">" pointing **right** (toward Attachment1), a 10-12 px dark outline (`Palette.Outline`), and clear margins so the chevrons have gaps. A 160 × 128 px image matches `TextureLength` 2 × `Width` 1.6. Don't reuse another creator's texture: ArrowBeams' has no licence |
| `TextureMode` | `Wrap` | one chevron every `TextureLength` studs, however long the beam |
| `TextureLength` | `2` | about 7 chevrons on a 15-stud walk |
| `TextureSpeed` | `1.5`; `0` when calm | flows toward the target. The docs give no unit. Community examples use 3 and 5, which are busier, so tune by eye to a calm walking pace |
| `FaceCamera` | `false` | it lies flat (Joshua: "closer to the floor"). The roll recipe below keeps it level |
| `Width0`, `Width1` | `1.6`, `1.6` | equal, so chevrons don't stretch along the beam. Readable at the default camera on a phone. ArrowBeams' 4 suits chest-height beams that face the camera. Try 2 if it reads thin on a phone |
| `CurveSize0`, `CurveSize1` | `0`, `0` | straight: no arc |
| `Segments` | `10` (the default) | straight anyway, and it leaves points along the length for the Transparency fade. If a twist ever shows, `1` stops it (DevForum 3323908), but the fade is lost |
| `Color` | `ColorSequence.new(Kit.lighten(spec.Color, 0.25))` | tints the white chevrons the target's colour; the dark outline stays dark |
| `LightEmission` | `0` | normal blending keeps the outline dark on cream and grass floors. Additive blending (1, the ArrowBeams default) washes white out and reads see-through (DevForum 1469241) |
| `LightInfluence` | `0` | the same colour by day and by night |
| `Brightness` | `1` | |
| `ZOffset` | `0` | |
| `Transparency` | below | fades in at your body and melts into the glowing target |

```lua
-- One span (the usual case).
local FADE_ONE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1), -- invisible where it leaves your body
	NumberSequenceKeypoint.new(0.1, 0.15),
	NumberSequenceKeypoint.new(0.9, 0.15),
	NumberSequenceKeypoint.new(1, 0.45), -- melts into the glow
})
-- With bends: the first span fades in only {0: 1, 0.1: 0.15, 1: 0.15}, middle spans are a flat 0.15,
-- and the last span fades out only {0: 0.15, 0.9: 0.15, 1: 0.45}.
-- The §3.6 nudge: swap in a flat 0 for 0.4 s, then back.
```

**The recipe that keeps it flat while you turn** (DevForum 3168420, in CFrame form). `GuideStart` rides on your root.
When you turn, its axes turn and a flat beam would twist. So re-aim both ends of span 1 on `RenderStepped` while the
beam shows.

```lua
local LIFT = Config.Tutorial.BeamLift -- 1.75
local ROLL0 = CFrame.Angles(0, 0, math.rad(90)) -- = WorldOrientation += (0, 0, 90)
local ROLL1 = CFrame.Angles(0, 0, math.rad(270)) -- = WorldOrientation += (0, 0, 270)

-- Your feet, from the rig, so the beam leaves "the middle of the body" (Joshua) and rises with a jump.
local function feetY(root: BasePart, humanoid: Humanoid): number
	local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else humanoid.HipHeight
	return root.Position.Y - root.Size.Y / 2 - legs
end

local function aim(a0: Attachment, p0: Vector3, a1: Attachment, p1: Vector3)
	a0.WorldCFrame = CFrame.lookAt(p0, p1) * ROLL0
	a1.WorldCFrame = CFrame.lookAt(p1, p0) * ROLL1
end

-- Every frame while the beam shows, and only then:
--   if root.CFrame:FuzzyEq(lastRoot, 1e-3) and not targetChanged then return end -- still: no writes
--   local p0 = Vector3.new(root.Position.X, feetY(root, humanoid) + LIFT, root.Position.Z)
--   aim(GuideStart, p0, span1End, firstKneeOrBase)
--   if flat distance to Base < Config.Tutorial.NearStuds then hide the beam and the chevrons (keep glow + pin)
-- The other spans' ends are fixed world points: aim them once when the route changes (at most twice a second).
```
- **Check once in Studio** that the chevrons lie flat and point at the target from the default camera. If they stand
  on edge, the roll is off by 90°. If they point back, flip the image. The 2024 thread is a community answer, and
  the engine docs don't state the axis rule.
- **It re-targets each step:** a new `Base` moves `GuideEnd` and recomputes the route. The beam doesn't tween across;
  it just switches, which stays calm.
- **It follows you:** span 1's start is on your root, so it moves with you for free. Only the aim needs the per-frame
  write.
- **After a respawn:** `Wayfinder.attach(character)` makes a new `GuideStart` (the old one went with the old body).

### 5.6 Where the beam and the chevrons anchor
- **The start:** `GuideStart` on your HumanoidRootPart at `feetY + 1.75`, as above.
- **The end, at the target's base** (`Base`):
  - **A station** (`Station_<id>`: a Part, or a kit Model's main part as in `Guide.luau:181-198`): take the closest
    point of its box's footprint to you, 0.3 studs out. A ray straight down there finds the floor, and the end sits
    `BeamEndLift` (0.25) above it. The beam slopes gently from your hips into the table's foot, the "slight tilt"
    Joshua's call allows.
  - **The Counter** (`Counter`, `server/PlotBuilder.luau:1150`): the same rule. Its Treat prompt reaches 10 studs
    (`Patients.luau:135`), so your current side works.
  - **A kit model** may carry an optional `GuideAnchor` Attachment under the target. Its `WorldPosition` wins.
  - **No beam** for the patient (card 1) or the bed (card 5): pin and glow only.
  - **The rays:** `RaycastParams` Exclude your character, the plot's `Patients` folder and `Wayfinder`, with
    `RespectCanCollide = true`, so walk-through decor and the queue lane are skipped.
- **Keeping it on the floor when the target is up a step:**
  1. Each end takes its height from **its own** floor. The start rides your feet and the end has its downward ray.
     So a raised floor at the target lifts the end, and the beam never ends in mid-air or inside the floor.
  2. A straight span clears any step lower than about 1.75 studs. At the step's edge the beam is at least
     `1.75 − 1.5t − h(1 − t)` above the upper floor, for a step of height `h` at fraction `t` along the span. That's
     positive for `h` < 1.75 anywhere along it. Our plots' steps are far below that: a room floor is 0.3 studs above
     the lawn (`PlotBuilder.luau:63`), and the ward floor 0.05 (`:1560`).
  3. **Bend when needed.** Cast one ray along the span. If it hits something solid (the Counter, a kit wall), or the
     floor rises within 0.3 studs of the beam anywhere (3 downward rays along it), bend the beam.
     - Put a knee at each kept waypoint of the route below, at its floor + `BeamLift`. Keep a waypoint where the
       direction turns more than 20° or the floor changes height by more than 0.5 studs.
     - That's up to 3 knees, so 4 spans.
     - Each knee is a pair of Terrain attachments, one per span, since an end can face only one way.
     - A floor chevron sits at each knee, which hides the small texture jump where one span's chevrons start again.
- **The route** (for knees and for the floor chevrons):
  - **Pathfinding first:** `PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })`,
    computed in a task (it yields), at most every 0.5 s, and only when you've moved 3 studs or the target changed.
  - **The fallback** if the path fails or isn't available on this client: a straight line, and if it crosses the
    Counter's footprint, a bend 2.5 studs past the Counter's nearer end. You spawn just beside that end
    (`server/Plots.luau:98-120`).
  - **The floor chevrons** go every `ChevronGap` studs along the route, each with its own downward ray, 0.05 studs
    above the floor.
- **The glow and the pin** anchor on the target itself (the Highlight's `Adornee`, the Marker at the target's top +
  0.3 studs), as Guide does now.

### 5.7 Budget check (the perf budget's rules)
- **Highlights:** exactly 1, re-pointed rather than re-made, and deleted when the Guide finishes (the budget allows 1).
- **Beams:** 1 span normally, at most 4, client-only.
- **Parts:** up to 6 floor chevrons + 1 marker, client-only, no physics, no shadows.
- **Loops:**
  - One `RenderStepped` callback runs only while the beam shows: 2 CFrame writes for span 1, skipped when your root
    hasn't moved or turned.
  - The flow itself is `TextureSpeed`, drawn by the engine with no script.
  - The route and the chevrons update at most every 0.5 s while you move.
  - Calm mode keeps the aim callback (the beam still follows you) but nothing animates.
  - Everything stops for good when the Guide's goal is reached (`Guide.luau:544-577`, as today).
- **Analytics:** 1 funnel call per step per player, server-side, first run only.

### 5.8 Test list (Studio `FreshSave`, then a phone)
- [ ] Each card's words on keyboard, a pad (Xbox glyph; PlayStation shows □ / ✕) and touch (Studio emulator), with
      the glyph switching live.
- [ ] **The beam** leaves your hips, lies flat, and points and flows toward the 🧪 table. It bends round the Counter
      from the spawn spot, swings to the Counter after the make, and hides within 6 studs.
- [ ] **Turn on the spot** and walk in circles: the beam stays flat and never twists or stands on edge.
- [ ] **Up a step:** walk from the lawn up onto the Stand's raised floor (0.3 studs) to the 🧪 table. The beam never
      dips into the floor or ends in mid-air. Test a kit room with a taller step too: the beam bends with a knee
      instead of cutting through the step.
- [ ] **Respawn mid-step** (reset the character): the beam comes back on the new body.
- [ ] Highlight count stays 1: `local n=0 for _,d in workspace:GetDescendants() do if d:IsA("Highlight") then n+=1 end end print(n)`.
- [ ] Reduce Motion **toggled mid-step** (Roblox menu) stops the beam's flow, the pulse, the bob and the hand at once.
      The beam keeps following you. The in-game calm toggle does the same.
- [ ] The top card never covers 💰, never overlaps the mini-game card (slim strip), and toasts stack under it.
- [ ] Skip in each step: lands at DONE, no gift, full HUD, arrows until 3 cures.
- [ ] Replay: no sweep, full HUD, no second gift, skippable.
- [ ] Rejoin in cards 2-5 resumes at card 1 (the existing `resume`).
- [ ] The first 💰 arrives within about 35 s (stopwatch), and the funnel shows steps in a published test place.
- [ ] Remember: MCP captures don't draw AlwaysOnTop billboards (the pin, the hand). Check those by eye.

---

## 6. Questions for the brothers (to file in `context/OPEN-QUESTIONS.md`)
1. **Skip button:** OK to add it, with the arrows staying until 3 cures? It reverses the first-session design's "No
   skip button". ⬜ Joshua.
2. **The guide nurse:** its name and look, and whether it's a new character or one of the 16 nurses. ⬜ Both.
3. **The nurse's voice:** do we want spoken lines (Roblox text-to-speech, free at our scale)? If so, which voice?
   ⬜ Both.
4. **"COMING UP" on the finale:** Golden Hour first (Joshua's example in `-022`), or the next free gift or night,
   whichever is soonest? ⬜ Joshua.
5. **The beam's chevron texture:** it's our own art, a white ">" with a dark outline (§5.5), uploaded as an image by
   Joshua.
   - Uploads go through Roblox moderation. Check the live Creator Hub page for any cost first: any Robux needs both
     brothers' yes (red line 4).
   - Until it's live, the beam draws as a solid tinted strip.
   - ⬜ Joshua (upload); the brother (the look, optional).
6. **The beam's feel:** after a first look in Studio, are width 1.6 and flow speed 1.5 right? Both are one Config
   edit. ⬜ Joshua.

---

## Sources
Fetched 2026-11-16 unless dated.

**Our own (read for this doc):**
- `game/README.md`
- `client/UI/Tutorial.luau`, `server/Tutorial.luau`, `shared/Logic/Tutorial.luau`, `client/UI/Guide.luau`,
  `client/UI/MiniGames.luau`, `client/UI/Kit.luau`, `client/UI/Theme.luau`, `client/UI/Toasts.luau`,
  `client/UI/Hud.luau`, `server/Patients.luau`, `server/Stations.luau`, `server/Plots.luau`,
  `server/PlotBuilder.luau`, `server/NurseBelt.luau`, `shared/Config.luau`
- `docs/plan/2026-11-16-first-session-design.md`, `docs/plan/2026-11-16-perf-budget.md`
- `memory-20261116-022`
- Joshua's screenshots `11.png`, `12.png`, `13.png` (2026-11-16)

**Charts (measured, 2026-11-16 15:39 UTC):**
- Roblox explore API, sort `top-playing-now` and `top-trending`: `apis.roblox.com/explore-api/v1/get-sort-content`
- Roblox games API: `games.roblox.com/v1/games?universeIds=…`

**Roblox docs** (the `Roblox/creator-docs` source of Creator Hub; pages carry no "updated" date):
- [onboarding](https://github.com/Roblox/creator-docs/blob/main/content/en-us/production/game-design/onboarding.md)
- [funnel events](https://github.com/Roblox/creator-docs/blob/main/content/en-us/production/analytics/funnel-events.md)
- [accessibility](https://github.com/Roblox/creator-docs/blob/main/content/en-us/production/publishing/accessibility.md)
- [Beam](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/Beam.yaml) ·
  [Beams guide](https://github.com/Roblox/creator-docs/blob/main/content/en-us/effects/beams.md) ·
  [TextureMode](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/enums/TextureMode.yaml)
- [highlighting](https://github.com/Roblox/creator-docs/blob/main/content/en-us/effects/highlighting.md) ·
  [BillboardGui](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/BillboardGui.yaml) ·
  [GuiService](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/GuiService.yaml)
- [UserInputService](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/UserInputService.yaml) ·
  [PreferredInput](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/enums/PreferredInput.yaml) ·
  [ProximityPrompt](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/ProximityPrompt.yaml)
- [Mansion of Wonder: connect the beam](https://github.com/Roblox/creator-docs/blob/main/content/en-us/education/build-it-play-it-mansion-of-wonder/connect-the-beam.md)

**DevForum (dates are the posts'):**
- [Lights, Camera, More Highlights!](https://devforum.roblox.com/t/4061534) (Roblox, 2025-11-10)
- [Introducing Accessibility Settings](https://devforum.roblox.com/t/2723187) (Roblox, 2023-11-29)
- [Learn More About First-Time User Experience & Onboarding](https://devforum.roblox.com/t/2621940) (Developer Relations, 2023-09-28)
- [Improving Onboarding through Funnel Events](https://devforum.roblox.com/t/3064458) (Developer Relations, 2024-07-12)
- [Text-to-Speech API Full Release](https://devforum.roblox.com/t/3986607) (Roblox, 2025-10-09; languages update 2026-08-11)
- [PreferredInput full release](https://devforum.roblox.com/t/full-release-introducing-preferredinput-and-improved-touch-capabilities/3750890) (2025)
- [How is this "Follow the arrows" system made?](https://devforum.roblox.com/t/297875) (2019-06-24)
- [Help Making Leading Arrows For a Tycoon](https://devforum.roblox.com/t/359098) (2019-09-29)
- [How To Make Quest Arrow/Markers](https://devforum.roblox.com/t/910415) (2020-12-07)
- [How Do I Rotate A Beam](https://devforum.roblox.com/t/939716) (2020-12-22)
- [LightEmission influences the visual transparency of Beams](https://devforum.roblox.com/t/1469241) (2021-09-15; listed in search, not opened)
- [How to go about making a beam that finds objects for you](https://devforum.roblox.com/t/1924113) (2022-08-15)
- [ArrowBeams](https://devforum.roblox.com/t/3045079) (2024-06-29) and its source,
  [github.com/itsDenDen/ArrowBeams](https://github.com/itsDenDen/ArrowBeams) (last commit 2024-12-21, no licence: values only)
- [How to keep Beam horizontal no matter of the rotation of attachment](https://devforum.roblox.com/t/3168420) (2024-09-22, the flat recipe)
- [Quest Arrow Upon Completing Quest](https://devforum.roblox.com/t/3177137) (2024-09-30)
- [How would I stop beam Orientation with Parts](https://devforum.roblox.com/t/3323908) (2024-12-28)
- [OnBoard framework](https://devforum.roblox.com/t/4751478) (2026-07-22)
- [Free Open-Source Tutorial System](https://devforum.roblox.com/t/4932428) (2026-10-13)

**Games (third-party guides, dates are the pages'):**
- [Climb For Animals Eggs](https://allthings.how/how-to-play-climb-for-animals-eggs-full-beginner-s-guide/) (2026-10-14)
- [Fake an Egg](https://allthings.how/fake-an-egg-roblox-how-to-play-full-guide/) (2026-10-19)
- [Grow a Garden](https://allthings.how/?p=330478) (2026-11-07)
- [Adopt Me Guide](https://roonby.com/2025/12/16/adopt-me-guide-feature-explained-how-to-use-it-and-get-free-items-fast/) (2025-12-16)
- [Steal An Egg](https://games.gg/roblox/guides/steal-an-egg-beginner-guide/) (2026-08-29)
- [Steal a Brainrot](https://en.wikipedia.org/wiki/Steal_a_Brainrot)
- [RoWatcher, first 90 seconds](https://rowatcher.com/news/your-first-90-seconds-are-destroying-roblox-retention) (undated commentary)

**Not opened:** the Adopt Me fandom wiki (HTTP 402), the GGRecon November list and progameguides (HTTP 403).

**Accessibility standard:** [WCAG 2.2 SC 2.3.1](https://www.w3.org/WAI/WCAG22/Understanding/three-flashes-or-below-threshold.html)
(three flashes).
