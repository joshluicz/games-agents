# Art direction: what the top games do, why ours reads too bright, and the spec (2026-11-16)

Asked by Joshua after Update 1 went live: "the colours still feel wrong. too bright... can you see what research and
the best games use then copy." He then asked for the trending studded-brick floor the "Steal a ..." games use, and
sent a screenshot of the look he wants (described in §2.1). Research and writing only: no code was changed and
Studio was not opened (another session was using it).

**M** = measured, with its source and date. **C** = Claude's judgement or design call. Everything in §4 is a
**proposal** inside Joshua's standing ruling ("saturated and flashy", `memory/records/memory-20261116-007.md`). It
revises Claude's "candy pop" specifics from that record, not Joshua's ruling. Nothing here is decided until Joshua
says yes.

Red line 2 holds throughout. We borrow approaches, principles and numbers. We don't borrow another game's textures,
models, characters or a look-for-look copy of a map. Classic studs are Roblox's own heritage (the engine still ships
`Enum.SurfaceType.Studs`), not any one game's art. We still make our **own** stud texture (§2.3). The word for the
style in game and in our docs is **"studs"** or **"brick style"**, never the toy brand's name.

---

## 1. What the top games do

### 1.1 The live chart, today
**M** Roblox's own "Top Playing Now" sort (explore API `get-sort-content?sortId=top-playing-now`, all devices and
locations), pulled **2026-11-16 15:31 UTC**:

| Rank | Game | Players now | Genre (Roblox's label) |
|---|---|---|---|
| 1 | Steal An Egg | 902,503 | Simulation |
| 2 | Brookhaven RP | 351,038 | Roleplay & Avatar Sim |
| 3 | Throw Food For Animals | 320,703 | Simulation |
| 5 | Adopt Me! | 228,795 | Roleplay & Avatar Sim |
| 10 | Break and Steal an Egg | 87,133 | Simulation |
| 20 | Pet Simulator 99! | 49,278 | Simulation |
| 26 | Steal a Brainrot | 40,687 | Simulation |
| — | Grow a Garden | 16,647 | (not in the top 40) |
| — | Animal Hospital (Anomaly), the biggest "hospital" hit in search | 15,494 | |
| — | Maple Hospital | 5,006 | |
| — | Work at a Pizza Place | 2,960 | |
| — | Restaurant Tycoon 2 | 1,341 | |

Counts for games outside the top 40 come from `games.roblox.com/v1/games` a minute later. Ranks 4, 6 to 9 and so on
are Blox Fruits, 99 Nights, RIVALS, MM2 and Anime Adventures, which aren't kid-sim references for us. **C** The kids'
simulator wave is now four games built the same way: Steal An Egg, Throw Food For Animals, Break and Steal an Egg and
Steal a Brainrot, with Grow a Garden fading. §1.3 shows all of them use studs.

### 1.2 Measured colour, from each game's official thumbnails
**M** Method: Roblox's thumbnails API (`thumbnails.roblox.com/v1/games/multiget/thumbnails`, 768×432), up to 4 per
game, fetched 2026-11-16, scored per pixel in HSV. "Loud" = S > 0.6 and V > 0.75. "Pale" = S < 0.25 and V > 0.85
(white, cream, pastel). Luma P10 and P50 = the 10th percentile and the median brightness (0 to 255), so P10 shows how
dark the darkest tenth gets. Our rows are Joshua's live screenshots `12.png` (the town) and `13.png` (a station), with
the HUD cropped out.

| Game | mean S | mean V | loud % | pale % | luma P10 | luma P50 |
|---|---|---|---|---|---|---|
| Steal An Egg | 0.63 | 0.82 | 46 | 14 | 33 | 152 |
| Throw Food For Animals | 0.70 | 0.80 | 56 | 2 | 69 | 152 |
| Break and Steal an Egg | 0.66 | 0.74 | 40 | 10 | 24 | 116 |
| Steal a Brainrot | 0.55 | 0.78 | 39 | 11 | 61 | 156 |
| Steal A Pet And Ride It | 0.66 | 0.85 | 51 | 9 | 42 | 158 |
| Grow a Garden | 0.66 | 0.82 | 51 | 8 | 89 | 189 |
| Adopt Me! | 0.54 | 0.87 | 37 | 16 | 96 | 192 |
| Pet Simulator 99 (2D art, not the world) | 0.63 | 0.88 | 46 | 15 | 87 | 169 |
| Brookhaven | 0.20 | 0.72 | 7 | 18 | 61 | 178 |
| Maple Hospital | 0.37 | 0.78 | 15 | 14 | 76 | 172 |
| Restaurant Tycoon 2 | 0.38 | 0.65 | 3 | 11 | 44 | 149 |
| Work at a Pizza Place | 0.53 | 0.61 | 17 | 5 | 40 | 104 |
| **Ours, 12.png (town)** | **0.41** | **0.95** | 29 | **35** | **140** | **214** |
| **Ours, 13.png (station)** | **0.48** | **0.95** | 39 | **31** | **138** | **207** |

Caveat: thumbnails are marketing renders, often colour-boosted, while ours are raw gameplay. That bias favours them
on saturation. It can't explain the gap in value: even Adopt Me's soft, bright renders get down to P10 96, and ours
never drops below 138.

**M** Ground colour, sampled from the lower 40% of each frame (median of grass-hued pixels, plus the darkest and
lightest 15% of them):

| Source | Shadow side | Main | Lit side |
|---|---|---|---|
| Steal a Brainrot (4 thumbs) | `#3BB04C`–`#29C94A` | `#3ECC55`–`#45D75B` (H 130°, S 0.68–0.80, V 0.80–0.89) | `#40CF57` |
| Throw Food For Animals, checker grass | stud shadow `#2C981F` (V 0.60) | dark tile `#3CE72C` (V 0.91) | light tile `#67F82E` (V 0.98), so ΔV ≈ 0.07 and the darker tile sits ~11° bluer |
| Throw Food For Animals, dirt wall checker | `#794D34` | `#99613B` (V 0.60) | `#B6763D` (V 0.71) |
| Steal a Brainrot, red base wall | shadow face `#8F262A` (V 0.56) | `#CD3135` (H 358°, S 0.76, V 0.81) | `#EB565B` |
| **Ours, 12.png / 13.png grass** | `#4FD44C` / `#71F24E` | `#70F75D` / `#79F954` (**V 0.97–0.98**) | `#74FE59` / `#76FB55` (**V 0.99–1.00**) |

Our grass albedo is `#60D648` (V 0.84, `Palette.luau:39`), yet it renders at V 0.97–1.0 with almost no difference
between shade and light. The lighting is clipping it (§3).

### 1.3 Per game
**C** marks a judgement from those thumbnails. Anything else is sourced.

- **Steal An Egg (#1).** C: voxel pets built from cubes. The ground is either a hero render of grass and sand or a
  studded floor (a purple studded plane in one thumbnail). Backgrounds are deep saturated blue or purple, with big
  outlined text. Colour sits in the mid-tones (V ~0.6–0.9), with real darks: the black dragon and deep blue sky.
- **Throw Food For Animals (#3).** C: the cleanest example of the target look. Grass is a two-tone checker of classic
  square studs, the walls are a studded dirt checker with grass-topped edge blocks, and the food is studded too
  (banana, burger, carrot). Each surface is one colour plus texture. There are no gradients and almost no white
  (pale 2%).
- **Break and Steal an Egg (#10).** C: studded green ground, studded orange-brown boundary walls, voxel pets.
- **Steal a Brainrot (#26).** Won **Best Creative Direction** at the 2025 Roblox Innovation Awards
  ([Pocket Tactics](https://www.pockettactics.com/roblox/innovation-awards-2025), updated 2025-10-03). The award was
  contested over the developer's AI use. A DevForum user reports that its studs are a **MaterialVariant**: Plastic
  base, a 2022-style stud colour map and normal map, StudsPerTile 1
  ([DevForum, Crygen54, 2025-06-23](https://devforum.roblox.com/t/studs-inconsistency-how-to-replicate-the-same-result/3774382)).
  That is a community claim; the developer hasn't confirmed it. C: studded green ground; base buildings fully
  studded in one strong red with cream trim strips and dark openings; studded carpets in a single colour (hot pink,
  orange); brick-built characters.
- **Grow a Garden.** C: the current thumbnails show studded grass ground, studded brown planter beds, plank fences,
  crops built from cubes and a blue sky with clouds. Sourced: Roblox's SVP of Engineering writes that many creators
  "work in a blocky style with saturated colors, in part because it is relatively easy and approachable"
  ([Roblox newsroom, Nick Tornow, 2026-07-01](https://about.roblox.com/newsroom/2026/07/roblox-studio-fidelity-creator-interviews-twin-atlas-fluorlite-maximillian-ecos)).
- **Adopt Me! (#5).** C: soft-shaded, smooth materials, rounded pets with big eyes, warm sun and green grass. It is the
  brightest set here (mean V 0.87) and still keeps real darks (P10 96). Sourced, but unverified: a 2024 licensing
  interview with Uplift's Head of Art says the pets are "the real style setters", and a partner brand must have
  "bright, bold colours, identifiable silhouettes". The quote comes from a search index; the page blocked our fetch.
- **Pet Simulator 99 (#20).** Its thumbnails are 2D illustrations (cube-bodied pets, thick outlines, radial bursts),
  so this pass has no evidence about its world. Not used for the world spec.
- **Brookhaven RP (#2).** C: near-realistic suburbs: white houses, grey asphalt, textured materials, realistic
  lighting. Low saturation (mean S 0.20); its colour comes from a few small accents. It shows that kids also play
  "real-looking", but it isn't our genre.
- **Hospital, restaurant and pizza games.** C: Maple Hospital has soft realistic interiors (pale blue and white
  walls, blue beds, warm light; mean S 0.37). Animal Hospital (Anomaly) is a dim navy horror hospital, not a model
  for us. Restaurant Tycoon 2 and Work at a Pizza Place have textured interiors (wood floors, brick, tiles) under warm
  light. **C** The interiors of every one of them have a mid-value floor (wood or tile) that props stand out against.
  None has a white or pastel floor.

### 1.4 What they share
**C**, backed by the numbers above:
1. **Real darks.** The darkest tenth of a frame sits at luma 24–96. Shadows, dark roofs, dark pads and outlines anchor
   the frame. Ours bottoms out at 138–140: nothing is dark.
2. **Saturation lives in the mid-tones.** Ground and walls sit at V ≈ 0.6–0.9 with S 0.65–0.8. Ours sits at V ≈ 1.0,
   where a colour can't get more vivid, only whiter.
3. **One colour per surface, plus texture.** Studs, planks, brick or checker carry the surface. Gradients and
   lerp-to-white pastels are absent.
4. **Little white.** Pale pixels cover 2–16% of a frame. Ours cover 31–35%.
5. **The simulator wave is studded.** Steal An Egg, Throw Food For Animals, Break and Steal an Egg, Steal a Brainrot
   and Grow a Garden all build on classic studs.

### 1.5 Lighting guidance (Creator Hub and DevForum)
- **Lighting.Technology is superseded.** It now maps to `LightingStyle` and `PrioritizeLightingQuality`: Future =
  Realistic + true, ShadowMap = Soft + true, Voxel = Soft + false. Soft "provides flatter-looking lighting with
  diffused shadows and lower contrast... the best option for achieving the classic Roblox look"
  ([DevForum, Roblox Rendering, "Unified Lighting is Fully Live", 2025-01-21, updated 2025-07-23](https://devforum.roblox.com/t/let-there-be-unified-light-unified-lighting-is-fully-live/3401512)).
  Both new properties can be set from a script; `Technology` can't
  ([Lighting reference](https://create.roblox.com/docs/reference/engine/classes/Lighting)).
- **Ambient** defaults to black and lights areas the sky can't see. **OutdoorAmbient** defaults to 127,127,127.
  Raising either brightens the whole place. When you raise **EnvironmentDiffuseScale** (default 0), lower Ambient and
  OutdoorAmbient to match. **EnvironmentSpecularScale** (default 0) makes smooth objects reflect the environment.
  **ExposureCompensation** runs from −5 to 5 (default 0); +1 doubles exposure. **ShadowSoftness** defaults to 0.2.
  Source: the Lighting reference above and
  [Global lighting](https://create.roblox.com/docs/environment/lighting).
- **Atmosphere.** `Decay` needs Haze and Glare above 0 to show at all, and `Glare` needs Haze above 0. `Color` "is
  best combined with increased Haze". Balance `Offset` against `Density`
  ([Atmosphere](https://create.roblox.com/docs/environment/atmosphere)).
- **ColorCorrection.** Brightness shifts every pixel (+1 is all white); Contrast separates darks from lights;
  Saturation; TintColor multiplies the RGB channels.
  **Bloom**: Threshold 1 blooms only pure white, 0 blooms everything. **SunRays**: Intensity 0–1, Spread 0–1
  ([Post-processing effects](https://create.roblox.com/docs/environment/post-processing-effects)).
  `ColorGradingEffect.TonemapperPreset` = Default is the vivid post-2019 look; Retro is flatter.
- **Community starting points, older and opinion only.** For a cartoony style: Brightness 2.5, ExposureCompensation
  0.1, ShadowMap, ShadowSoftness 0.05, and Saturation and Contrast up in ColorCorrection
  ([DevForum, 2023-01-28](https://devforum.roblox.com/t/lighting-settings-for-cartoony-style/2167959)). The "flat
  colour" recipe of Brightness 0, white ambients and no shadows
  ([DevForum, 2021-10-16](https://devforum.roblox.com/t/how-you-can-make-stylized-flat-color-art/1510773)) is the
  opposite of what the top games do, and our current setup has drifted toward it.
- **Phones.** As of 2026-11-05 the lowest quality level draws 500 studs, up from 200. Roblox's advice is to test
  visuals at every quality level (Studio Settings > Rendering > Editor Quality Level) and not to switch effects on
  `SavedQualityLevel`
  ([DevForum, Roblox, 2026-11-05](https://devforum.roblox.com/t/increasing-the-minimum-draw-distance-to-500-studs-and-other-auto-quality-level-improvements/4977292)).

---

## 2. The studs look (the "Steal a ..." floor)

### 2.1 The target: Joshua's reference, as described to us
Grass is bright green with raised studs and a faint two-tone checker (a slightly lighter and a slightly darker tile),
so it reads as texture, not one flat colour. Behind it stands a large two-colour checker wall, also studded. Trees are
blocky stacks of studded green cubes in a few greens. A barn has wood beams, a white trim stripe and a dark roof edge.
Paths are beige planks and fences are white. The plot floor is a dark pad with grey stone edging. Overall it's
saturated, but **each surface is one colour plus texture**: no pastel gradients, no pink everywhere. World labels
float as big white or yellow outlined letters with no board behind them. §4 rebuilds that feel in our own colours.

### 2.2 How games make studs: the four ways, with sources
1. **`SurfaceType.Studs` (Roblox's own legacy surface).** Set `Part.TopSurface = Enum.SurfaceType.Studs`. The enum is
   deprecated for *joining* only. Its own docs say that leaves "only visual changes", and `Studs` "adds square studs
   across the surface" ([SurfaceType](https://create.roblox.com/docs/reference/engine/enums/SurfaceType)). The
   textures **only appear on Plastic** parts, not SmoothPlastic
   ([DevForum, Roblox, "Changes to Part Surfaces", 2019-08-19](https://devforum.roblox.com/t/changes-to-part-surfaces/334420)).
   **They still render in 2026.** Scripted `TopSurface = Studs` is "the official stud texture"
   ([DevForum thread, 2026-09-18](https://devforum.roblox.com/t/how-to-get-stud-texture/4880386)), and the official
   studs visibly change with graphics quality (DevForum, 2025-06-23, linked above). Studio hides the Surface
   properties, so they're set from code or the command bar. We build our parts in code anyway.
   **Cost:** one playtester on a low-end phone found a place with studs on every part laggier. A reply said the studs
   "act similarly to Texture" when used everywhere
   ([DevForum, 2026-08-08](https://devforum.roblox.com/t/does-the-legacy-surfacetype-cause-lag/4785429)). That's an
   anecdote, not a measurement.
2. **A MaterialVariant with stud colour and normal maps.** This is reportedly what Steal a Brainrot uses: Plastic
   base, ColorMap and NormalMap, `MaterialPattern = Regular`, `StudsPerTile = 1` (DevForum, 2025-06-23). The "Add
   Classic Studs" tutorial applies stud MaterialVariants to parts, meshes and unions
   ([DevForum, 2024-09-13, last updated 2026-11-14](https://devforum.roblox.com/t/how-to-add-classic-studs-to-parts-meshes-unions/3157449)).
   The catches:
   - A MaterialVariant covers **every face**. You can't pick one face; the same thread confirms this on 2026-04-18.
   - It must live under MaterialService. Its texture maps are PluginSecurity, so it's **created in Studio** (Material
     Manager or the command bar) and saved in the place, not built at runtime. Code only sets
     `part.MaterialVariant = "<name>"`.
   - It can be set as the **Plastic override**, so every Plastic part becomes studded
     ([Materials](https://create.roblox.com/docs/parts/materials)).
   - At quality 2 or lower its detail goes "softer" than the built-in studs (DevForum, 2025-06-23).
3. **A `Texture` per face with colour and normal maps.** Textures (Decals) now take `NormalMapContent` and become PBR
   surfaces ([Decal](https://create.roblox.com/docs/reference/engine/classes/Decal)). Set `Face`, then
   `StudsPerTileU/V` to the number of studs the image covers. A 4×4-stud image takes 4
   ([DevForum, 2025-08-01 and 2026-11-14](https://devforum.roblox.com/t/how-to-add-classic-studs-to-parts-meshes-unions/3157449)).
   The "trendy" grey line around each stud is two layers: the baseplate grid texture under a stud texture, with the
   transparency tuned
   ([DevForum, "Trendy stud texture", 2026-09-17](https://devforum.roblox.com/t/trendy-stud-texture/4876870) ·
   [DevForum, 2026-09-19](https://devforum.roblox.com/t/how-to-get-stud-texture/4880386)).
   **Cost:** "decals, textures, and particles don't batch well and introduce additional draw calls"
   ([Creator Hub, Improve performance](https://create.roblox.com/docs/performance-optimization/improve)). One Texture
   per tile across a town is the expensive way.
4. **Stud-topped geometry.** Real stud cylinders on items and pets give the best close-up and cost the most
   triangles. **C** The "Steal a" pets are cube-built (voxel) sculptures; studs show on them mostly through the
   material.

**What goes under the studs:** one flat, mid-value, saturated colour per part (§1.2: grass V 0.8–0.9, S 0.7–0.8;
walls V 0.6–0.8). The stud map is near-white and the part's colour tints it. A faint two-tone checker (ΔV ≈ 0.07, the
darker tile a few degrees bluer) makes a big floor read as tiled rather than as one flat colour.

**Tiling and performance, in numbers:**
- `StudsPerTile` (MaterialVariant) or `StudsPerTileU/V` (Texture) = the studs one image covers: 1 for a one-stud
  image, 4 for a 4×4.
- Texture memory scales with pixel count. A 1024² image costs 4× a 512² and 16× a 256²
  ([Improve performance](https://create.roblox.com/docs/performance-optimization/improve)). One 256 px stud tile with
  its normal map is tiny.
- One MaterialVariant shared by every studded part is one texture set. Thousands of `Texture` instances are thousands
  of extra draw calls.

**On phones (C, with the arithmetic shown):**
- Studs are texture, never information, so their shading stays within about ±0.12 V of the base. Creatures, icons and
  billboards must still pop on top.
- At a 70° vertical field of view on a 1080 px-tall screen, one stud facing the camera spans about 771 / distance px:
  ~50 px at 15 studs and ~8 px at 100. Studs read clearly around the player and melt into their colour in the
  distance, which is what we want.
- Phones often run low quality levels, where normal maps soften. So the colour map carries a faint baked ring that
  still reads without lighting.
- Test at Editor Quality Level 1, 4 and 10. Watch for shimmer (moiré) on far lawns. If it shows, move far lawns to a
  2-stud pitch, or drop the studs past the plots.

### 2.3 Our recipe (own assets, nothing borrowed)
- **Make our own two images.** The appendix script writes them.
  - `CureStuds_color.png`, 256×256, **one stud per tile**: base `#F2F2F2`; a stud 0.6 of the cell wide, a touch
    lighter (`#FAFAFA`); a thin darker contact ring (`#D4D4D4`) at its foot.
  - `CureStudsGrid_color.png`: the same with a 3 px `#C8C8C8` line on the cell edge, for the "grid" variant.
  - `CureStuds_normal.png`: OpenGL tangent space. Roblox only supports OpenGL normal maps
    ([SurfaceAppearance](https://create.roblox.com/docs/art/modeling/surface-appearance)).
  - Upload all three under the game's group.
- **Studio, once:** in MaterialService, add a MaterialVariant `CureStuds` with BaseMaterial **Plastic**, the colour and
  normal maps above, `StudsPerTile = 1` and `MaterialPattern = Regular`. Leave the roughness map empty, or use a flat
  ~170/255 grey for a satin, non-glossy finish. Save the place. Optionally set it as the Plastic override. Then the
  rule in code becomes "Plastic = studded, SmoothPlastic = smooth".
- **Code:** a studded part gets `Material = Plastic` and `MaterialVariant = "CureStuds"`. Sizes and positions stay on
  whole studs, so stud rows line up across neighbouring parts. A misaligned seam is the main giveaway; check every one
  in Studio.
- **Same-day prototype with no assets:** `Material = Plastic` and `TopSurface = Enum.SurfaceType.Studs` on the lawn
  and pad parts. That shows Joshua the look today. Switch to `CureStuds` before shipping: it isn't deprecated, it
  covers walls and meshes, and it's tinted the same way.
- **Checker:** our builder already lays a checker for the queue lane. Lawns use 4×4-stud tiles alternating GrassA and
  GrassB (§4.1). On very large lawns, use one tile Part per checker cell or one checker `Texture` per lawn (a 2×2-cell
  image, `StudsPerTileU/V = 8`, `Transparency ≈ 0.85`). Never one Texture per stud.
- **Don't use the asset IDs from the DevForum posts.** They are other users' uploads (`10509831729`/`10509831753`,
  uploaded 2022-08-07; `18878365966`, 2024-08-09). They show the approach. We ship our own.

### 2.4 Where studs go in our game
| Surface | Studs? | Note |
|---|---|---|
| Town lawns | **Yes**, 4×4 two-tone checker | The look Joshua asked for |
| Plot pads (each player's plot floor) | **Yes**, dark pad | Creatures and stations pop on a dark studded floor |
| Plot edging | No | Grey stone (Slate) frames the pad |
| Road | **No**, smooth and dark | Smooth against studded tells the kid "this is the road" and rests the eye |
| Paths | No | Beige planks (WoodPlanks) |
| Building and clinic walls | **Yes**, all faces | One strong plot colour, studded |
| Trim, fences, roof edges | No | SmoothPlastic, so they read as clean lines |
| Trees and bushes | **Yes** | Voxel trees from studded cubes (2, 3 and 4 studs), 5–9 cubes each |
| Props: beds, counters, the potion table, crates | **Studded tops only** | A thin studded top plate on SmoothPlastic bodies: chunky and blocky, no Texture objects |
| Items in hand (bandage, potion) | Blocky, no studs | Cube-built, chunky; studs at that size are noise |
| Creatures | **No studs on the current round bodies** | Studs on spheres pinch at the poles. See the decision below |
| Interior floors | No | Warm wood planks, mid-value |

**Decision for Joshua: do the creatures go blocky?**
- The "Steal a" pets are cube-built sculptures. Ours are round, code-built (`CreatureBuilder`), and their faces carry
  the "sick patient → cured" read.
- **C** Recommendation: go studded and blocky on the world, props and items now. Build **one** creature (say Hum
  Hamster) as a blocky studded version and put the two side by side for Joshua.
- Converting all of them means rewriting the creature recipes as boxes. That's a big job, and it pulls us toward a
  look-for-look match with the "Steal a" games, which red line 2 warns about.

---

## 3. Why ours reads too bright and "off"

**M** The headline: our frames average **V 0.95**, the darkest tenth never gets below **luma 138**, and **a third of
the screen is white or pastel**. The top games sit at V 0.74–0.88, P10 24–96, pale 2–16%. Ours is actually
*less* saturated (mean S 0.41–0.48 against 0.54–0.70). "Too bright" means over-exposed and milky, not too colourful.

The causes, by file and line:

1. **The sky and ambient fill are far too high.** `game/src/server/DayNight.luau:40–42`: `Brightness = 2.6`,
   `Ambient = (124,120,146)`, `OutdoorAmbient = (166,160,186)`.
   - Ambient defaults to black and OutdoorAmbient to 127 (Creator Hub). So shadows get about +30% fill on top of a
     2.6 sun.
   - Shadows lift to near the lit colour, and the lit colour clips. Our grass renders at V 0.97–1.0 from a V 0.84
     albedo (§1.2), and in `12.png` the trees cast almost no visible shadow.
   - Not verified: the place's `EnvironmentDiffuseScale` and `EnvironmentSpecularScale` live in the place file, which
     wasn't read. If they're 1, they add more fill and a sky-blue sheen on top.
2. **The grade pushes highlights up, not down.** `DayNight.luau:44–48`: `Saturation 0.2`, `Contrast 0.08`,
   `Brightness 0.02`. On colours already at V 1.0 (the candy set) this clips channels at 255. On pastels it does
   almost nothing. The result is "neon next to milk".
3. **The atmosphere is milky.** `DayNight.luau:50–54` and `111–113`:
   - Color `(198,230,255)` is almost white-blue, so distant objects fade to milk.
   - `Decay (120,178,255)` has no effect at all, because Haze and Glare are 0 (Atmosphere docs).
4. **The night is a purple wash.** `DayNight.luau:62–63`: Ambient `(100,74,196)` and OutdoorAmbient `(124,94,228)` are
   brighter and more saturated than a dark night fill. With `Saturation 0.28` on top (`:66`), the night looks
   lilac-flat rather than night.
5. **Full-value candy on lit world parts.** `game/src/shared/Palette.luau:15–25`: every Candy colour has a channel at
   or near 255 (V 1.0). These colours are right for unlit UI but clip on world parts under a 2.6 sun.
   `PlotBuilder.luau:86–110` and `:142–145` put them on the plaza ring, lamp posts, benches, planters and room styles.
6. **Pastel by design: lerp-to-white everywhere.**
   - `game/src/server/PlotBuilder.luau:133–135` (`roomStyle`): `Floor = lighten(main, 0.82)`,
     `FloorStripe = lighten(main, 0.64)`, `Wall = lighten(main, 0.5)`. Every room floor is 82% white.
   - `PlotBuilder.luau:1573`: building `Wall = lighten(accent, 0.78)`, so every clinic is a pale tint.
   - `:105–110`: lightened leaves, pink `BLOSSOM` trees at +20% to +60% white, and `STONES` lightened 40% toward white. This is
     the "pink everywhere".
7. **Large near-white surfaces.** `Palette.luau:41` Path `(255,224,150)`, `:44` Fence 255, `:51` Floor
   `(255,244,222)`, `:52–54` Pavement `(252,246,234)`, `:55` Wall 255. They cover big areas, which makes the 31–35%
   pale share.
8. **No dark anchor.** `Palette.luau:42`: Street `(118,124,168)` is a lilac mid-grey, the only big mid-tone, and it
   blends with the pinks and purples. The top games anchor the frame with dark pads, dark roofs and dark roads.
9. **No surface texture.** `Palette.luau:37` ("Mostly SmoothPlastic... no realistic materials"),
   `PlotBuilder.luau:212`, `DecorBuilder.luau:117`. Every surface is one flat, clipped colour. The top games carry
   every surface with studs, planks or brick.
10. **Too many hues at once.** In `12.png`: pink, magenta, purple, yellow, green, blue, cyan and orange, plus seven
    different fills on the bottom bar. `game/src/client/UI/Theme.luau:25–33` gives every role its own candy hue. The
    eye has nowhere to rest.
11. **The UI is bleached too.** `Theme.luau:15–17`: Paper is white with an ice gradient (`PaperEdge (220,232,255)`)
    and Card `(238,244,255)`, so the panel and its cards are near-white on near-white. In `11.png` the card image
    wells come out dull grey, so the Journal looks washed rather than crisp.
12. **Labels sit on big coloured boards.** `PlotBuilder.luau:1018–1045` (`buildSign`, a candy board with an accent
    frame) and the hot-pink odds board in `12.png`. The reference floats its text with no board behind it.

---

## 4. The spec: values a builder can apply directly

### 4.1 World palette (Studio `Color3`, before lighting)
Rules:
- Big surfaces sit at **S 0.55–0.75, V 0.55–0.85**. Accents sit at S 0.7–0.85, V 0.8–0.96.
- Whites are **warm and capped**: `#F0EBDF`, never 255.
- No `lighten()` toward white for any surface bigger than trim.

| Role | Hex | RGB | Material |
|---|---|---|---|
| Grass, light tile (GrassA) | `#56C740` | 86, 199, 64 | Plastic + `CureStuds` |
| Grass, dark tile (GrassB) | `#3FB536` | 63, 181, 54 | Plastic + `CureStuds` |
| Ground block sides (dirt) | `#8C603E` | 140, 96, 62 | Plastic + `CureStuds` |
| Tree leaves A / B / highlight C | `#39A844` / `#2B8F42` / `#67C246` | 57,168,68 / 43,143,66 / 103,194,70 | Plastic + `CureStuds` (cubes) |
| Trunk | `#704B31` | 112, 75, 49 | Wood |
| Path planks / seam or alternate plank | `#D6B27C` / `#BA9265` | 214,178,124 / 186,146,101 | WoodPlanks |
| Road (asphalt) | `#3E4352` | 62, 67, 82 | SmoothPlastic (or Concrete) |
| Road lines | `#F0EBE1` | 240, 235, 225 | SmoothPlastic |
| Curbs | `#999CA3` | 153, 156, 163 | Slate |
| Plot pad (dark slate-teal) | `#253D4C` | 37, 61, 76 | Plastic + `CureStuds` |
| Plot edging (stone) | `#8A8E94` | 138, 142, 148 | Slate |
| Building walls | the plot accent below, **full strength** | | Plastic + `CureStuds` |
| Roofs and roof edges | `#2D2B3D` | 45, 43, 61 | SmoothPlastic |
| Trim stripes, window frames | `#F0EBDF` | 240, 235, 223 | SmoothPlastic |
| Wood beams | `#805738` | 128, 87, 56 | Wood |
| Fences | `#EBE6DA` | 235, 230, 218 | SmoothPlastic |
| Boundary wall, 8×8-stud checker (optional backdrop) | `#369E94` teal / `#EBDEC0` cream | 54,158,148 / 235,222,192 | Plastic + `CureStuds` |
| Water | `#38A7D6` | 56, 167, 214 | Glass at Transparency 0.3, or SmoothPlastic |
| Interior floor, planks A / B | `#AD8053` / `#996B45` | 173,128,83 / 153,107,69 | WoodPlanks |
| Interior wall, upper | `#EBE4D8` | 235, 228, 216 | SmoothPlastic |
| Interior wall, lower band (dado) | the room's accent, full strength | | Plastic + `CureStuds` |
| Glow (night lamps, creature tips) | unchanged | | Neon, small parts only |

**World accents** (plot and room colours; the UI keeps the brighter Candy set):

| Name | Hex | RGB |
|---|---|---|
| Pink | `#DB3D7D` | 219, 61, 125 |
| Blue | `#3195E0` | 49, 149, 224 |
| Orange | `#EB842A` | 235, 132, 42 |
| Purple | `#894ECC` | 137, 78, 204 |
| Cyan | `#29BCCC` | 41, 188, 204 |
| Yellow | `#F5C731` | 245, 199, 49 |
| Red (props only, never a plot, never a cross) | `#D63C4B` | 214, 60, 75 |
| Lime (props only) | `#6ACC39` | 106, 204, 57 |

- **Plot colours**, Plot_1 to Plot_6: Pink, Blue, Orange, Purple, **Yellow**, Cyan. Yellow replaces Lime, which would
  vanish against green grass. Accents stay non-red, as `PlotBuilder.luau:1741` requires.
- **Room colours:** Stand = its plot colour; Bath = Cyan; Ward = Purple; Winter Wing = Blue; Garden = leaves.
- Room floors become the wood planks above. Walls are the room colour on the lower band and warm white above. That
  replaces `lighten(main, 0.82 / 0.64 / 0.5)`.

### 4.2 Dominant, secondary, accent
- **About 60% dominant:** the greens (studded lawn and voxel trees).
- **About 30% secondary:** the neutrals that carry the value contrast. Dark (road, plot pads, roofs; V 0.24–0.32)
  against warm light (planks, trim, fences; V 0.84–0.94), plus the sky.
- **About 10% accent:** the plot colour (walls, awning, gate arch, sign letters), creature colours and gold for money.
- **At most 3 saturated hues in a normal frame:** green, the plot's colour, and one highlight (yellow or gold).
  Creatures and rarity effects come on top.
- Pink is one plot colour, not the town's colour. Blossom trees are at most 1 tree in 6.
- No gradients on world parts. Each surface is one colour, and the texture (studs, planks) does the rest.

### 4.3 Lighting, day and night (all set in `DayNight.luau`, so it's versioned)
Set once in `start()`, since enums don't tween: `Lighting.LightingStyle = Soft`,
`Lighting.PrioritizeLightingQuality = true` (the old ShadowMap path: sun shadows without Future's per-light cost),
`GlobalShadows = true`, `ColorShift_Top` and `ColorShift_Bottom = (0,0,0)`. Add the float properties below to the
tweened `Look` tables.

| Property | Day | Night | Now (day / night) |
|---|---|---|---|
| Lighting.Brightness | **2.25** | **1.0** | 2.6 / 1.2 |
| Lighting.ExposureCompensation | **0** | **0** | (place) |
| Lighting.Ambient | **(70, 68, 84)** | **(54, 44, 110)** | (124,120,146) / (100,74,196) |
| Lighting.OutdoorAmbient | **(128, 128, 140)** | **(82, 68, 150)** | (166,160,186) / (124,94,228) |
| Lighting.EnvironmentDiffuseScale | **0.6** | **0.4** | (place) |
| Lighting.EnvironmentSpecularScale | **0.15** | **0.15** | (place) |
| Lighting.ShadowSoftness | **0.15** | **0.15** | (place) |
| Lighting.ClockTime | the place's 8–16, else 14 (unchanged) | 0.5 (unchanged) | |
| ColorCorrection `CandyColor`: Brightness | **0** | **0** | 0.02 / 0.03 |
| ColorCorrection: Contrast | **0.12** | **0.15** | 0.08 / 0.1 |
| ColorCorrection: Saturation | **0.08** | **0.05** | 0.2 / 0.28 |
| ColorCorrection: TintColor | **(255, 251, 244)**, a touch of warm sun | **(222, 214, 255)** | (255,255,255) / (226,214,255) |
| Atmosphere.Density | **0.26** | **0.32** | 0.24 / 0.3 |
| Atmosphere.Offset | **0.15** | **0.12** | 0.2 |
| Atmosphere.Color | **(150, 198, 240)**, the sky's own mid-blue | **(74, 64, 152)** | (198,230,255) / (128,104,222) |
| Atmosphere.Decay | (104, 150, 214) | (40, 32, 104) | inert while Haze = 0 |
| Atmosphere.Haze / Glare | **0 / 0** (crisp) | **0 / 0** | 0 / 0 |
| Bloom: Intensity / Size / Threshold | **0.25 / 20 / 2** (only Neon glows) | **0.6 / 24 / 1.3** (lamps and tips glow) | 0.3/24/2 · 0.55/24/1.6 |
| SunRays (new): Intensity / Spread | **0.04 / 0.45** | **0 / 0** | none |
| Clouds (Terrain, optional) | Cover 0.5, Density 0.55, white | Cover 0.4 | none |

ShadowSoftness: the Lighting class reference says it works under ShadowMap and Future, while the Global lighting page
says Realistic only. If 0.15 does nothing under Soft, leave it. A bluer sky is optional: a Sky with our own
`#3A9BF0`→`#9FD3F7` gradient faces gives the saturated blue the top games have.

**Acceptance test (measured, not eyeballed).** From the same camera spot as `12.png`, take a screenshot with the HUD
hidden and run the appendix stats script.

| Measure | Day target | Night target |
|---|---|---|
| Mean V | 0.75–0.88 (now 0.95) | 0.35–0.50 |
| Luma P10 | ≤ 90 (now 140) | |
| Pale share | ≤ 15% (now 35%) | |
| Grass, rendered | V 0.72–0.88, with the two checker tones visibly apart (ΔV ≥ 0.05) | V 0.30–0.45 with a violet cast |
| Walls and floors | no big wall or floor at V ≥ 0.97 | |
| Glow | | lamps and Neon tips visibly bloom |

Tune in this order: OutdoorAmbient, then Brightness, then EnvironmentDiffuseScale. Touch the grade last.

### 4.4 Signs and world text
- Titles and labels (clinic names, "+5", the station names) float as **outlined text with no board**.
  `BackgroundTransparency = 1`, LuckiestGuy, white `#FFFFFF` or gold `#FFD84A`, `UIStroke` 3–4 px `#1B1238`, and an
  optional second label behind it offset 2 px down in `#1B1238` at 0.5 transparency as a drop shadow.
- Boards stay only where there's a lot of text. The odds list must stay readable (red line 3): put it on a dark navy
  plate (`#1E2440`, transparency 0.15) with white text, not a hot-pink board.

### 4.5 UI palette (the UI is unlit, so it keeps the brighter Candy hues)

| Token | Value | Now |
|---|---|---|
| Panel body | `#FFFFFF` flat (drop the ice gradient, or keep it within 4%: to `#F4F7FC`) | white → `#DCE8FF` |
| Panel stroke | 4 px `#1B1238` | same |
| Panel header | `#1F8FE5`, title white with a 3 px `#1B1238` stroke | cyan `#00D6E8` |
| Card / row | `#EEF3FA` with a 2 px `#C3D0E6` stroke | `#EEF4FF`, no tint split |
| Card image well | `#D6E3F5`; locked "???" silhouettes `#6A5FA0` | dull grey |
| Primary button (main action) | `#FF9A1F` → `#F27A0C` (top → bottom) | `#FF961E` |
| Secondary button | `#2F86FF` → `#1F66E0` | `#28AAFF` |
| Good (claim, done) | `#45CF3A` → `#2BA52A` | `#50DC3C` |
| Danger (close) | `#FF4459` → `#D9283F` | `#FF405A` |
| Quiet button | `#DFE6F2` fill, ink text `#2A2150`, 2 px `#1B1238` stroke, no white outlined text | `#E2E8FC` |
| Disabled | `#B3B6C9`, text `#6E7190` | `#B0B0C6` |
| Text on light | Ink `#221A48`, soft `#5D5788` | `#241848`, `#62568C` |
| Text on colour | `#FFFFFF` with a 2.5 px `#1B1238` stroke | same |
| Stroke (all) | `#1B1238` | `#181034` |
| Cash / star / night | `#FFD43B` / `#FFE228` / `#5B3BD6` | about the same |

- **The HUD bottom bar** uses **one** shared fill (Secondary blue, or white with a dark stroke), with full-colour emoji
  icons and outlined labels. A red dot marks what's new.
- **At most 3 saturated fills in the HUD at once** (cash yellow, timer orange, the bar's blue), plus red dots. Today
  the bar shows seven.
- The gloss, shine, outlines and pop stay as they are (memory-007's "flashy"). What changes is the number of
  competing fills and the bleach.
- Nothing loud points at spending (red line 3). The Shop button gets the same fill as its neighbours.

---

## 5. The top 5 changes, by visual impact
1. **Relight** (§4.3, `DayNight.luau:38–77` plus `start()`). Pull the ambient fill and the grade's lift down, set
   LightingStyle Soft with PrioritizeLightingQuality, and make the atmosphere mid-blue instead of milk. This is the
   biggest change and the cheapest: one file, no assets. Rendered V should drop from 0.95–1.0 to 0.75–0.88, and
   shadows appear.
2. **Stud the ground** (§2.3, §2.4). Lawns get the 4×4 two-tone studded checker, and plot pads become dark and
   studded with grey stone edging. Prototype the same day with `TopSurface = Studs` on Plastic, then ship our own
   `CureStuds` MaterialVariant. This is the trend Joshua named, and it ends the "one flat colour" look.
3. **Kill the pastels** (`PlotBuilder.luau:105–110`, `:133–135`, `:1573`; `Palette.World`). Walls take the plot colour
   at full strength. Floors become wood planks. Trees become 3-green voxel cubes, with pink at most 1 tree in 6. Swap
   the near-white paths and pavement for beige planks.
4. **Add dark anchors, and one colour per surface** (§4.1). The road goes charcoal-blue, roofs go dark, whites go warm
   and stay on trim and fences, and the queue-lane pavement leaves cream and lilac for mid-tones. Each building is one
   colour plus a white trim stripe, a dark roof edge and wood beams.
5. **De-bleach the UI and float the labels** (§4.4, §4.5; `Theme.luau:15–33`, `PlotBuilder.luau:1018–1045`). Flat white
   panels with a deeper header and tinted cards. One fill on the bottom bar. World labels become outlined text with no
   board.

Then test on a phone at quality 1, 4 and 10 (§2.2), and check `docs/plan/2026-11-16-perf-budget.md` before adding
SunRays, Clouds or more shadow-casting cubes.

## Decisions for Joshua (to copy into `context/OPEN-QUESTIONS.md`)
1. Studs on the town lawns, the plot pads, the building walls and the trees: yes or no?
2. Creatures: keep them round, or prototype one blocky studded creature first (§2.4)?
3. Plot colours: swap Lime for Yellow (§4.1)?
4. The HUD bottom bar with one fill instead of seven (§4.5)?

## Not checked
- The live place's `LightingStyle`, `EnvironmentDiffuseScale`, `EnvironmentSpecularScale`, `ExposureCompensation`
  and Sky live in the place file and weren't read: Studio was in use by another session. §4.3 sets them all in code,
  so whatever the place holds gets overridden.
- In-game screenshots of the other games weren't collected, only their official thumbnails, so §1.2 compares
  marketing renders with our raw gameplay (see the caveat there).
- These pages blocked our fetcher: the Adopt Me art interview (mojo-nation.com), roblox.fandom.com (Surface) and
  ggrecon.com.

## Appendix A: the screenshot stats (as used in §1.2 and the acceptance test)
```python
# python stats.py shot.png   (Pillow). Crop the HUD out first.
import sys, colorsys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB").resize((192, 108))
S = V = n = loud = pale = 0; luma = []
for r, g, b in im.getdata():
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    S += s; V += v; n += 1; luma.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
    loud += s > 0.6 and v > 0.75; pale += s < 0.25 and v > 0.85
luma.sort()
print(f"meanS {S/n:.2f} meanV {V/n:.2f} loud {100*loud/n:.0f}% pale {100*pale/n:.0f}% "
      f"P10 {luma[n//10]:.0f} P50 {luma[n//2]:.0f}")
```

## Appendix B: generating our stud textures
```python
# python make_studs.py CureStuds 0      -> CureStuds_color.png + CureStuds_normal.png
# python make_studs.py CureStudsGrid 3  -> the variant with a 3 px grey line on each cell edge
import math, sys
from PIL import Image
N, R, BEVEL, H = 256, 0.30, 0.035, 0.10        # px per stud, stud radius (0.6 of the cell wide), bevel, height
GRID = int(sys.argv[2]) if len(sys.argv) > 2 else 0
def height(x, y):
    d = math.hypot(x - 0.5, y - 0.5)
    if d <= R - BEVEL: return H
    if d >= R: return 0.0
    t = (R - d) / BEVEL; return H * t * t * (3 - 2 * t)
col, nrm, e = Image.new("RGB", (N, N)), Image.new("RGB", (N, N)), 1 / N
for py in range(N):
    for px in range(N):
        x, y = (px + 0.5) / N, (py + 0.5) / N
        d = math.hypot(x - 0.5, y - 0.5)
        v = 250 if d < R - BEVEL else (212 if R <= d <= R + 0.03 else 242)
        if GRID and (px < GRID or py < GRID): v = 200
        col.putpixel((px, py), (v, v, v))
        dx = (height(x + e, y) - height(x - e, y)) / (2 * e)
        dy = (height(x, y + e) - height(x, y - e)) / (2 * e)
        nx, ny, nz = -dx, dy, 1.0                  # OpenGL: +Y up (image rows run down)
        l = math.sqrt(nx * nx + ny * ny + nz * nz)
        nrm.putpixel((px, py), tuple(round((c / l * 0.5 + 0.5) * 255) for c in (nx, ny, nz)))
col.save(sys.argv[1] + "_color.png"); nrm.save(sys.argv[1] + "_normal.png")
```
Tested 2026-11-16: it produces a 256 px tile whose normal map lifts green on the stud's top edge and red on its right,
which is correct for OpenGL. Upload under the group, then follow §2.3.
