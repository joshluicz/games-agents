# Creator Store free models for the creatures and nurses (2026-11-16)

Research only. Nothing was inserted into Studio and no game code changed. The question: can free Creator Store
models upgrade the 10 patients (`game/src/shared/Data/Patients.luau`) and the ~16 creature-nurses planned for
Update 1 (`docs/plan/2026-11-16-depth-update-design.md` §2)?

**Contact sheet:** [`2026-11-16-creator-store-models.jpg`](2026-11-16-creator-store-models.jpg). Tile numbers match
the `#` column below. Tiles 3 and 8 are zoomed crops of the 700 px thumbnail. Tile 1 is the uploader's promo image,
not an in-engine render.

## How this was checked
- **Search:** the Studio MCP `search_asset` tool with scope `creator_store`, price `free`, type `Model` (plus
  `MeshPart` once), on 2026-11-16. Queries: cute animal, chibi pet, kawaii creature, blob monster cute, cute frog,
  cute sheep, cute bunny, cute penguin, cute owl, cute cat, cute ghost, cute moth, cute slime pet, low poly cute
  animals pack, kawaii animals pack, pet pack, cute creature pack, stylized pet, toon pets, candy creatures, plush,
  nurse, nurse animal, nurse bunny cute, doctor animal, doctor pet, hospital props pack, first aid kit, medicine
  bottle potion, bandage/thermometer/stethoscope, cute medical props, and `cute creature` as MeshPart.
- **Facts per asset** (creator, script count, triangles, votes, upload date) come from
  `apis.roblox.com/toolbox-service/v1/items/details`, and the blue badge from `users.roblox.com/v1/users`, both
  read on 2026-11-16. Thumbnail CDN links come from each result's `thumbnailUrl` (fetched at 420×420). The
  `180DAY` links expire. To refresh one, fetch
  `https://thumbnails.roblox.com/v1/assets?assetIds=<ID>&size=420x420&format=Png` again.
- **What "verified" means here.** "ID ✓" is the Creator Store flag `isVerifiedCreator`. Roblox's Creator Store
  docs say account verification is "an age check or using a government ID". Almost every uploader has it, even
  a since-deleted group that re-uploads other people's models, so it says nothing about originality. Only one
  shortlisted creator (voidgizmo91) has the **blue badge**. Turning on the tool's `verifiedCreatorsOnly` filter
  left 19 of 20 "cute animal" results unchanged, because nearly every uploader passes, the deleted group included.
- **Track record:** only #4 has any votes (41 up, 9 down). Every big pack is under 3 weeks old with 0 votes.

## Shortlist

### Creature candidates
Fit is 1–5 against the candy-pop look: round, chunky, saturated, big friendly eyes, Rated Minimal.

| # | Name | Asset ID | Creator (verified?) | What it is | Fit | Could be | Risks | Thumbnail |
|---|---|---|---|---|---|---|---|---|
| 1 | Chibi Pet Kit: 21 Animated Pets + Follow | 114725480264590 | Jetfuel116 (ID ✓, badge ✗) | 21 named chibi pets with **animated faces (12 expressions)**: blink, star eyes, hearts, sleep. Also 14 emotes and a follow script | 5 | Nurses: Cosmic Cow, Sleepy Sloth, Chill Capybara, Star Sprite. Patients: Rocket Penguin → Snowcone Penguin, Moon Jelly → Hiccup Ghost or Moon Moth | **2 scripts**, and the face system lives in them. Our kit loader strips scripts, so the faces would freeze. The thumbnail is a promo render, so check the real look in-engine. About 14k triangles per pet (300,404 in total). Uploaded 2026-10-27, 0 votes. Skip Void Reaper (scythe), Shade Ninja, Magma Golem and Titan Mech (its V-fin reads like a Gundam) | [img](https://tr.rbxcdn.com/180DAY-b3833d0619e9bcc97223ff0fe09ab1a4/420/420/Image/Png/noFilter) |
| 2 | 108 Cartoon Pets, Monsters & Bosses Mega Pack | 136743087148579 | coyote_hybridd (ID ✓, badge ✗) | 61 pets, 29 monsters, 9 bosses and 9 eggs. Toon-shaded with bold outlines, one baked palette texture each, 3–6 studs | 4 | Penguin → Snowcone Penguin, bunny → Jelly Bun, frog → Dumpling Frog, jelly → Slime Cat. The chef-hat cloud could be a nurse | No scripts, about 2.8k triangles per pet. A baked texture won't recolour through `Color`, so the Frosty/Sparkly tints and night glow would look weak. Toon outlines vs our glossy SmoothPlastic. Skip the imps, knights and bosses (angry faces). Uploaded 2026-11-04, 0 votes | [img](https://tr.rbxcdn.com/180DAY-a17d5f7dfb5ba879681cbb25b2e4f12d/420/420/Image/Png/noFilter) |
| 3 | Chibi Pals - Free Pet Pack (10 Pets, 8 Skins) | 130936829957243 | Strat3gie (ID ✓, badge ✗) | 10 chibi animals (puppy, kitty, bunny, fox, frog, penguin, panda, axolotl, dragon, unicorn) plus 8 effect skins and a follow system | 4 | Frog → Dumpling Frog, penguin → Snowcone Penguin, bunny → Jelly Bun, kitty → Slime Cat, puppy → Toast Pup. The panda or axolotl could be a nurse | **3 scripts**, including a PETS menu GUI, so strip them. About 4k triangles per pet. The species line-up mirrors the usual pet-sim rosters: compare the puppy, kitty, unicorn and dragon side by side with Adopt Me's before using any. Skip the Toxic, Phantom and Glitch skins. Uploaded 2026-11-11, 0 votes | [img](https://tr.rbxcdn.com/180DAY-c201f0540ac86092e9af1ee4e0fed7c8/420/420/Model/Png/noFilter) |
| 4 | Cute Penguin | 8780565023 | Calestelle (ID ✓, badge ✗) | A plush-style penguin with blush cheeks, 6 MeshParts, no decals | 4 | Snowcone Penguin (recolour the body blue and add a scoop on top) | No scripts, 7,690 triangles, from 2022. **The only voted asset (41/9).** Its face is part of the mesh, so it can't swap moods. ⚠️ A copy, 93525644221592 by Aerorex36, has the same geometry **plus a script**. Use this original ID only | [img](https://tr.rbxcdn.com/180DAY-b15b254e7e74f34c017073ff3cb717c4/420/420/Model/Png/noFilter) |
| 5 | Cute Frog | 79186763439220 | ItzPanFrog (ID ✓, badge ✗) | A green frog with big googly eyes and an open smile. Unions plus 3 face decals | 4 | Dumpling Frog | No scripts, 4,968 triangles, from 2025-02-23. Its face is fixed decals. ⚠️ A copy, 90877333676644 by "Content Deleted - 158552482", has the same geometry plus **2 scripts**, even though its description says "No scripts". Use this original only | [img](https://tr.rbxcdn.com/180DAY-af13f354ca8941af0582ce618d099aec/420/420/Model/Png/noFilter) |
| 6 | Premium Slime Pack - 4 Cute Pets | 126032665700479 | Oquyomi (ID ✓, badge ✗) | 4 round slimes (purple with a crown, sky blue, orange, green) with glossy eyes and blush | 5 | Jelly Bun, Slime Cat, night patients, a Common nurse | No scripts. 23,088 triangles for 4 balls, which is heavy. **It adds nothing:** our `Ball` shape plus eyes and cheeks already builds this look. Uploaded 2026-09-30, 0 votes | [img](https://tr.rbxcdn.com/180DAY-dc16542006ea5eb94d76aa94a5ead810/420/420/Model/Png/noFilter) |
| 7 | cute ghost | 5028754973 | SauimDesign (ID ✓, badge ✗) | A pale, translucent sheet ghost with little arms | 3 | Hiccup Ghost | No scripts, 2,942 triangles, from 2020. The description says it was "used on roblox fun ghost park tycoon", which may not be the uploader's own game, so the rights are unclear. Raised arms can read as "boo!". It needs a candy tint | [img](https://tr.rbxcdn.com/180DAY-5fdd4e8358224d89c52fae28599e9e3d/420/420/Model/Png/noFilter) |
| 8 | Stylized Simulator Pets Mega Pack [111 Pets] | 129968854763101 | coyote_hybridd (ID ✓, badge ✗) | 111 low-poly PBR creatures in 6 themes, with pivots at the feet | 2 | Slimes, jellies or owls for Icicle Owl, Moon Moth or Slime Cat | No scripts, about 4.9k triangles each. A muted, semi-realistic palette that includes a scorpion, crab and snake, all off-tone. Uploaded 2026-11-03, 0 votes | [img](https://tr.rbxcdn.com/180DAY-cf9ca3cb9d1234c1bf5f2c93a7a6999a/420/420/Image/Png/noFilter) |
| 9 | Snow Owl cute | 15306754803 | GORGONAGIRL (ID ✓, badge ✗) | An angular low-poly grey-blue owl | 2 | Icicle Owl | No scripts, but 40 MeshParts for one owl. The description reads "to gorgonagirl", as if someone else made it for her, so the rights are unclear | [img](https://tr.rbxcdn.com/180DAY-e4414cb5e0668e077e5441806bee86f2/420/420/Model/Png/noFilter) |
| 10 | Poly Block Cute Animal Pack - 20 Assets | 75471003737301 | voidgizmo91 (ID ✓, **badge ✓**) | 20 standing cube animals (cat, frog, penguin, pig, unicorn and more) | 2 | Background critters only. Cubes clash with our round bodies | **1 script.** The description credits "Wurnorr", not the uploader, so its provenance is unclear. The uploader's second pack (95757394637739) looks like Minecraft mobs, so it's rejected below | [img](https://tr.rbxcdn.com/180DAY-e1638aae50abcbd7113bb0598a94499c/420/420/Model/Png/noFilter) |

### Nurse candidates
**No good free creature-nurse exists.** "Nurse", "nurse animal" and "doctor animal" searches return Piggy
characters, Nurse Joy, a Silent Hill nurse and anime avatars (see Rejected). The real nurse bases are the
creature packs above, **#1 first, then #3 and #2**, each with a nurse cap added.

| # | Name | Asset ID | Creator (verified?) | What it is | Fit | Could be | Risks | Thumbnail |
|---|---|---|---|---|---|---|---|---|
| 11 | Nurse Hat | 9459542259 | GhoulMisty (ID ✓, badge ✗) | A white nurse cap with a green cross, 592 triangles | 3 | A cap to put on any creature-nurse | No scripts. It has the same 592-triangle mesh as "Nurse Hat (2009-2025)", whose description calls it "the original version of the Nurse Hat with the red cross", so it is probably a re-upload of Roblox's own avatar hat. The rights are unclear. A 6-part cap built in code would be safer | [img](https://tr.rbxcdn.com/180DAY-3b450238fd0beb1a20c8ea1c22e3a8e4/420/420/Model/Png/noFilter) |
| 12 | Nurse | 625070397 | Zuperstition (ID ✓, badge ✗) | "A Cartoony looking Nurse" human R6 NPC with 9 animations | 1 | Not recommended: our nurses are creatures | **4 scripts.** A blocky human rig from 2017 | [img](https://tr.rbxcdn.com/180DAY-add2257bf96296687b1f6bee698b5652/420/420/Model/Png/noFilter) |

### Props
| # | Name | Asset ID | Creator (verified?) | What it is | Fit | Could be | Risks | Thumbnail |
|---|---|---|---|---|---|---|---|---|
| 13 | Mendwell Sampler: Voxel Hospital Kit | 91803691876056 | stayrot (ID ✓, badge ✗) | A medkit Tool (with a **heart, not a red cross**), wheelchair, IV stand and bed. One MeshPart each, base-centre pivot | 3 | Clinic dressing, or a reference for the bed and First-Aid Stand | No scripts, 1,882 triangles for all four. The voxel style and teal/blue palette clash with candy-pop. It samples a 54-piece kit the uploader mentions. Uploaded 2026-10-15, 0 votes | [img](https://tr.rbxcdn.com/180DAY-b239d04b29517552a0265329559ad27a/420/420/Model/Png/noFilter) |
| 14 | Cartoony Potion | 8262701303 | DE3Y0 (ID ✓, badge ✗) | A round pink potion bottle with a cork | 4 | Tonic or medicine props for Sneezes and Chills, or a recipe item | No scripts, 1 MeshPart, from 2021. 5,216 triangles is heavy for a bottle, so keep it to one per bed | [img](https://tr.rbxcdn.com/180DAY-c8363c02205c4aa4850d46095eab980f/420/420/Model/Png/noFilter) |
| 15 | First Aid Kit | 5255684558 | Silver91748 (ID ✓, badge ✗) | A simple red first-aid box: 3 MeshParts and 1 decal | 3 | The First-Aid Stand's kit, recoloured pink with a heart decal | No scripts, 402 triangles, from 2020. Check the decal: if it's a red cross on white, swap it (see Rejected) | [img](https://tr.rbxcdn.com/180DAY-b89d76665097a84936b2fbe77651eae8/420/420/Model/Png/noFilter) |
| 16 | Voxel Pet Eggs Pack (24 Eggs) | 136171001209491 | PotassiumStudioHold (ID ✓, badge ✗) | 24 themed voxel eggs | 2 | Decor only. Our design hires nurses off a belt, not from eggs | No scripts. 65,892 triangles in total is heavy. Eggs suggest gacha, which the belt design avoids. Uploaded 2026-10-24, 0 votes | [img](https://tr.rbxcdn.com/180DAY-f909c0edad45d7a3f1a8d1018011e4da/420/420/Image/Png/noFilter) |

## Rejected and flagged (red line 2, or likely ripped)
- **Re-uploads with hidden scripts (possible backdoors):** 90877333676644 Cute Frog (a copy of #5, 2 scripts)
  and 93525644221592 Cute Penguin (a copy of #4, 1 script, blank thumbnail). 101796646695280 Cute Panda
  (Nugubema01) says "No scripts" in its description, but the API counts 2. Everything by
  **"Content Deleted - 158552482"**, a deleted group that re-uploads other people's models under keyword-stuffed
  titles: Bunny Pet, Big Teddy Bear, Pig NPC, Rat, Maxwell the Cat, Sleeping Cat, Egg Pets Kit, Doctor Harlow.
- **Other games' characters:** every "Adopt Me" pet upload (for example 85072884079631, 82897718193485,
  113990445202732 and the "Adopt Me Sheep" uploads), Pet Simulator X Pack 12864599637, "Pet Simulator Plush Pals"
  98924741923769, BGC Pets 15966079813, Piggy characters (Katie, DoctorPiggy 7236675768, and Nurse Kitty 8346310218
  and Nurse giraffy 9438385781 in Piggy's masked style, the giraffe holding a blade). "Katie Animal Hospital",
  "Doctor Harlow animal hospital" and "Animal Hospital Slime" look like characters from the horror game Animal
  Hospital. Also Sprunki 80242369402425, Poppy Playtime, Garten of Banban, Dandy's World, FNaF plushes, My Singing
  Monsters, the "99 Nights" forest bunny 122907060935468 and the "brainrot" owl-cat 78376944305784.
- **Film, TV, anime and brand IP:** the Kirby, Pokémon and Pikmin MeshParts (430076942, 545274035, 14684550570,
  93305955205983), the "Gooey" slime blob 92951625042071 (a blue blob with a long tongue that looks like Kirby's
  Gooey), Sanrio (Cinnamoroll 5971762087, Mocha 11427022604, the azuki nurse 14365758622), the Chiikawa
  HachiwareEgg 140267248958878, My Little Pony's Fluttershy 79314925, Nurse Joy 44314368, the Silent Hill nurse
  341322639, Pusheen 15249734641, DreamWorks' Hammy and RJ, The Owl House's King 136335234551221, Gumball's Anais
  5657106454, Angry Birds 8721591765, Grimace (McDonald's) and the Teto and Miku plushes.
- **Real-world plush replicas:** purinton1976's "Nouvy - Cute Animal Plushies" (its description says "Made by
  NOUVY SRL") and "Kawaii Kuties Plush" ("Licensed ... Made by Whitehouse Leisure UK"). Both copy real companies'
  products, and they carry 10 and 9 scripts.
- **Off-tone or other licences:** SCP-999 (many uploads). SCP Foundation content is CC BY-SA, and it comes from a
  horror universe.
- **The red cross:** "Nurse Hat (2009-2025)" 85195205011429 is the same cap as #11 with a red cross on white.
  That's a protected emblem, and the Red Cross asks game makers not to use it for health items. Use a heart or a
  candy-pink plus instead (#13 already does).
- **Style misses:** realistic cats (Cute Critters 131800011257611), and voidgizmo91's Minecraft-like farm pack
  95757394637739.

## Recommendation: keep our code-built creatures, and use store models only for low-risk props
1. **Faces and acting are the game.** `CreatureBuilder.setMood` swaps Sick, Happy, Sad and Sleep faces by
   toggling named `Eye`, `Lid` and `Mouth` parts. Patients also wear ailment props, glow at night, and take the
   Frosty and Sparkly tints. A store mesh dropped into the existing override (`ServerStorage.Creatures.<PatientId>`)
   would show up, but `setMood` would silently do nothing on it, because a baked face has no `Eye` or `Mouth` parts.
   The loader also deletes every script (`fromKit`), so even #1's expression system would be stripped.
2. **Originality is the hook** (`memory-20261116-004`: an original absurd cast). The free packs are generic
   pet-sim animals (pandas, unicorns, axolotls, puppies). Any other game can drop in the same free models, and a
   Nurse Journal built on someone else's designs isn't ours.
3. **Trust is thin.** The best-looking packs are 5–20 days old with 0 votes. "Verified" only means ID-checked.
   Copies of the two best single models (#4, #5) circulate with scripts added.
4. **Performance:** #1 is about 14k triangles per pet. Our creatures are under 40 simple parts.

**Where store models are worth it:**
- **Props:** #14 (potion) and #15 (first-aid kit, recoloured with a heart) are cheap and safe. Use #13 as a
  layout reference only.
- **Nurses (Update 1):** build them with `CreatureBuilder` too, with a new `Top = "NurseCap"` option instead of
  #11. Use #1 and #2 as **style references** for silhouettes and expressions. If the brothers still want a
  store model, #1 is the only one that matches candy-pop and changes faces. Test it in a scratch place first,
  not the shared one: read both scripts, check the real look against the promo image, count triangles, and leave
  out the Reaper, Ninja, Mech and Golem.
- **A one-species experiment:** if the brother wants to try the mesh override, #4 (penguin) is the safest
  candidate: no scripts, the only votes, an original upload. It will lose mood faces until we add our own eye and
  mouth parts on top.
- Whatever is used: insert by the exact asset ID above (never a look-alike), remove scripts before saving, and
  keep a credits line for the creator.

**Top 5:** #1 Chibi Pet Kit (nurse style and faces), #4 Cute Penguin, #2 108 Cartoon Pets, #5 Cute Frog,
#14 Cartoony Potion. Runner-up: #3 Chibi Pals.
