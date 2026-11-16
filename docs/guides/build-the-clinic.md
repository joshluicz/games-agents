# Build the clinic: a step-by-step guide for the builder

The game is now **Creature Clinic** (a working name: the real one is yours and Joshua's to pick). Every player gets
their own little clinic on a plot in a town. Silly creatures walk in with something wrong, players make the cure at a
station, and the creature hops off happy.

**The code runs the patients, cash and saving.** Your job is to make the rooms, the creatures and the decorations
look amazing. You don't need to know how to build: **Assistant**, the AI helper in Roblox Studio, builds what you
type.

**Where:** Roblox Studio on your Mac. When a step says **Ctrl**, press **Cmd**.

This replaces the old shop guide (`build-the-shop.md`). The old shop was deleted on 2026-11-16 (see
[The old Shop](#the-old-shop)).

---

## How the game finds your stuff (read this once)
- **The code builds the town when the game starts.** That's 6 plots, a street and a spawn. You only see it while
  you're playing, so in edit mode it isn't there. That's normal.
- **Every plot starts with plain placeholder rooms.** If you put a model with the right name in
  **ServerStorage → ClinicKit**, the game uses **yours** instead. Creatures and decorations work the same way.
- **The code finds things by their exact names.** `Station_Remedy` works. `station_remedy`, `Station Remedy` and
  `StationRemedy` don't. Capital letters count.
- **Anything you leave out, the game fills in with its own placeholder.** So you can do one room at a time.

This is what it looks like in **Explorer** when you're done (more parts inside each model is fine):
```
ServerStorage
├─ ClinicKit            (Folder)
│  ├─ Stand             (Model: the First-Aid Stand)
│  ├─ BathRoom          (Model)
│  ├─ Ward              (Model)
│  ├─ WinterWing        (Model)
│  ├─ Garden            (Model)
│  └─ Decor             (Folder)
│     ├─ PottedFern     (Model)
│     └─ ...
└─ Creatures            (Folder)
   ├─ DumplingFrog      (Model)
   └─ ...
```

⚠️ **ServerStorage is invisible in the 3D view.** So always build in **Workspace**, where you can see it. When it's
done, drag it into its ServerStorage folder. To change it later, drag it back to Workspace, fix it, then drag it
back.

---

## Before you start (once)

### Joshua and you
To build in the real game, **you and Joshua are Roblox friends, then Trusted Friends**, and Joshua gives you **Edit**
access. At 13, Roblox needs one of those (or a parent's OK) before you can build with someone 18+. You can do every
practice step below before that.

### Helpful plugins (optional)
Plugins are tools you add to Studio. ⚠️ **Only install these exact ones, by their ID.** The Creator Store is full of
fake copies with hidden bad scripts.

1. In your web browser, go to `https://create.roblox.com/store/asset/` followed by the ID. For example,
   `https://create.roblox.com/store/asset/165534573`.
2. Check that the **creator name** matches the table. If it doesn't, close the page.
3. Get it (they're all free). It shows up in Studio's **Plugins** tab. If it doesn't, restart Studio.
4. ⛔ **If a plugin asks for Robux, stop.** That's a spend, and you and Joshua both have to say yes first.

| Plugin | ID | Creator | Good for |
|---|---|---|---|
| ResizeAlign | 165534573 | stravant | Snapping one face flush to another: walls, counters, shelves |
| GapFill & Extrude | 165687726 | stravant | Filling the gaps at corners and roof edges |
| Archimedes | 144938633 | Scriptos | Arches, round walls, curved counters |
| Building Tools by F3X | 144950355 | GigsD4X | Move, resize, paint and material, all in one |
| Brushtool 2.1 | 2268520847 | XAXA | Scattering plants and props |
| Load Character Lite | 752585459 | AlreadyPro | Dropping in an avatar to check door and counter heights |

Nobody has checked yet that each one works on a Mac. If one doesn't, skip it.

---

## Part A: get ready (in a practice place)

### A1. Open a blank place
Open Roblox Studio → **New** → **Baseplate**.

### A2. Open the windows you'll need
Open **Explorer** (the list of everything in your game), **Properties** (the settings of whatever you click) and
**Output** (where the game prints messages). They're in the **View** or **Window** menu.

### A3. Open Assistant
Click the **Assistant** button at the top right of Studio. A chat panel opens. You type what you want, and it
builds it.

### A4. Make the folders: copy this into Assistant
> In ServerStorage, make a Folder named **ClinicKit**, and inside ClinicKit a Folder named **Decor**. Also in
> ServerStorage, make a Folder named **Creatures**.

### The one direction rule ➡️
**The front of everything points to -Z** (negative Z). The front is where patients come from and where the street
is. If you build with **Orientation 0, 0, 0** (in Properties), the -Z side is the front. Every prompt below already
says this, so Assistant knows. When you test, you'll see if a room is backwards, and
[Stuck?](#stuck) says how to fix it.

---

## Part B: the First-Aid Stand (every player starts with it)
The Stand is the first thing every player sees. It has two stations, one bed and two decor spots. The plot already
has the **Counter** right in front of the stand, and the queue of patients forms in front of the Counter.

### B1. Build the stand: copy this into Assistant
> Create a Model in Workspace named **Stand**. Inside it, make an anchored Part named **Floor**: 22 studs wide (X),
> 0.6 tall and 14 deep (Z), at Position 0, 0.3, 0 with Orientation 0, 0, 0. This is a small, cozy first-aid stand
> for a cartoon creature clinic. Build a back wall about 8 studs tall along the +Z edge of the floor, and short side
> walls on the back half only. Leave the whole -Z side (the front) open: players and patients come in from there.
> Put a striped awning over the back half instead of a full roof, so the camera can see inside. Anchor every part.

### B2. Add the 5 special parts: copy this into Assistant
The code looks for these exact names, so they **must** be spelled exactly like this.
> Inside the Stand model, add these anchored parts with exactly these names. Positions are measured from the centre
> of Floor, and every part sits on top of the floor.
> **Station_Remedy**: a 4.2 by 3 by 2.6 stud block at X -5.5, Z 4.7 (near the back wall). Players make potions here.
> **Station_Plaster**: a 4.2 by 3 by 2.6 stud block at X 0.5, Z 4.7. Players make plasters here.
> **Bed_1**: a 4 by 1 by 6.6 stud mattress at X 7.6, Z 1.2, long side along Z, with its top about 1.8 studs above
> the floor. Put a wooden frame named BedFrame under it, and a pillow named Pillow on the +Z end.
> **DecorSlot_1**: an invisible 4 by 1 by 4 part at X -8.5, Z -4.2, sitting on the floor.
> **DecorSlot_2**: an invisible 4 by 1 by 4 part at X 8.3, Z -4.5, sitting on the floor.
> Invisible means Transparency 1 and CanCollide false. Keep a clear path from the open front to each station.

### B3. Check the names ✅
In **Explorer**, click the arrow next to **Stand**. You should see all of these (more parts is fine):
`Floor` · `Station_Remedy` · `Station_Plaster` · `Bed_1` · `DecorSlot_1` · `DecorSlot_2`

If one's missing or spelled differently, double-click its name in Explorer (or right-click → **Rename**) and fix
it. Then click **Floor** and check that its **Orientation** in Properties is **0, 0, 0**.

### B4. Make it look good (the fun part)
Ask Assistant for anything you like. Some ideas:
> Make the back wall soft peach with a wooden trim, and the floor light wooden planks.
> Add a little hanging sign with a heart on it, some potted plants at the sides and a shelf of colourful bottles.
> Add warm fairy lights along the awning.

**For a cool-looking station:** click **Station_Remedy** in Explorer first, then type
`/generate_mesh a cute cartoon potion bench with round colourful bottles`. Assistant makes it fit inside
Station_Remedy's box. Click **Add to place**, then drag the new mesh into the **Stand** model in Explorer. Now click
the old **Station_Remedy** part and set its **Transparency** to **1**. Do the same for Station_Plaster
(`/generate_mesh a cute cartoon table with a box of plasters and a roll of tape`).

⛔ **Don't delete or rename the special parts.** Hide them with Transparency 1 if you like, but keep them. The game
hangs its buttons on them.

### B5. Stand rules
- **Keep the middle of the front clear,** about 4 studs deep. That's where players stand behind the Counter.
- **Don't build another counter** at the front. The plot already has one.
- **No full roof.** The camera looks down from above, so players need to see the stations and the bed.
- **Keep it inside the floor.** Neighbouring rooms go right next to it.
- Patients lie on top of **Bed_1**, with their head at the pillow end (+Z), so keep the top of Bed_1 flat and clear.

### B6. Save it
1. **File → Save to File** keeps a copy on your Mac.
2. In Explorer, **right-click Stand → Save to Roblox**. It goes in your Roblox inventory, ready for the real game.
3. Drag **Stand** into **ServerStorage → ClinicKit**.

---

## Part C: the other 4 rooms
Players buy these with cash and ⭐ Stars. Each one goes in its own spot on the plot. Build them the same way as the
Stand: a **Floor** part at Orientation 0, 0, 0, the open front toward -Z, then the special parts.

| Model name | What it is | Floor size (X × Y × Z) | Special parts |
|---|---|---|---|
| `BathRoom` | 🛁 Bath Room: bubbles for sticky and muddy creatures | 18 × 0.6 × 16 | `Station_Bath` · `DecorSlot_1` |
| `Ward` | 🛏️ Cozy Ward: extra beds | 22 × 0.6 × 14 | `Bed_1` · `Bed_2` · `DecorSlot_1` · `DecorSlot_2` |
| `WinterWing` | ❄️ Winter Wing: cocoa for chilly snow creatures | 18 × 0.6 × 16 | `Station_Cocoa` · `Bed_1` · `DecorSlot_1` · `DecorSlot_2` |
| `Garden` | 🌻 Sunny Garden: a pretty garden with room for decorations | 22 × 0.6 × 14 | `DecorSlot_1` · `DecorSlot_2` · `DecorSlot_3` |

The names players see (Bath Room, Cozy Ward...) are placeholders. To change one, tell Joshua. The **model name**
stays the same, so the code can still find it.

### C1. Bath Room: copy this into Assistant
> Create a Model in Workspace named **BathRoom**. Inside it, make an anchored Part named **Floor**: 18 wide (X), 0.6
> tall, 16 deep (Z), at Position 40, 0.3, 0 with Orientation 0, 0, 0. Make it a bright, bubbly bath room for a
> cartoon creature clinic: light blue tiles, a back wall about 8 studs tall along the +Z edge, short side walls on the
> back half, the -Z side open, and an awning instead of a full roof. Inside the model add, measured from the centre
> of Floor and sitting on the floor: **Station_Bath**, a 5.6 by 2.2 by 3.6 stud bathtub at X 0, Z 4.6, and
> **DecorSlot_1**, an invisible 4 by 1 by 4 part at X -5.5, Z -4.6 (Transparency 1, CanCollide false). Anchor
> every part.

### C2. Cozy Ward: copy this into Assistant
> Create a Model in Workspace named **Ward**. Inside it, make an anchored Part named **Floor**: 22 wide (X), 0.6
> tall, 14 deep (Z), at Position 80, 0.3, 0 with Orientation 0, 0, 0. Make it a cozy recovery room for a cartoon
> creature clinic: soft pink floor, a back wall about 8 studs tall along the +Z edge, short side walls on the back
> half, the -Z side open, and an awning instead of a full roof. Inside the model add, measured from the centre of
> Floor: **Bed_1** at X -6, Z 1.3 and **Bed_2** at X 6, Z 1.3, each a 4 by 1 by 6.6 stud mattress (long side along
> Z, top about 1.8 studs above the floor) with a frame named BedFrame and a pillow named Pillow on the +Z end. Add
> **DecorSlot_1** at X 0, Z 3.6 and **DecorSlot_2** at X 8.6, Z -4.5, each an invisible 4 by 1 by 4 part sitting
> on the floor (Transparency 1, CanCollide false). Anchor every part.

### C3. Winter Wing: copy this into Assistant
> Create a Model in Workspace named **WinterWing**. Inside it, make an anchored Part named **Floor**: 18 wide (X),
> 0.6 tall, 16 deep (Z), at Position 120, 0.3, 0 with Orientation 0, 0, 0. Make it a snowy, warm winter room for a
> cartoon creature clinic: pale blue and white, snow on the awning, warm blankets, a back wall about 8 studs tall
> along the +Z edge, short side walls on the back half, and the -Z side open. Inside the model add, measured from the
> centre of Floor and sitting on the floor: **Station_Cocoa**, a 4.2 by 3 by 2.6 stud cocoa counter at X -3, Z 5;
> **Bed_1**, a 4 by 1 by 6.6 stud mattress at X 5, Z 1.6 (long side along Z, top about 1.8 studs above the floor,
> frame named BedFrame, pillow named Pillow on the +Z end); **DecorSlot_1** at X -5.5, Z -4.8 and **DecorSlot_2**
> at X 4.8, Z -5.2, each an invisible 4 by 1 by 4 part (Transparency 1, CanCollide false). Anchor every part.

### C4. Sunny Garden: copy this into Assistant
> Create a Model in Workspace named **Garden**. Inside it, make an anchored Part named **Floor**: 22 wide (X), 0.6
> tall, 14 deep (Z), at Position 160, 0.3, 0 with Orientation 0, 0, 0, made of grass. Make it a sunny little garden
> for a cartoon creature clinic: low hedges along the back (+Z) and the sides, a wooden flower arch near the back,
> and the -Z side open. No roof. Inside the model add **DecorSlot_1** at X -6.5, Z 2.4, **DecorSlot_2** at X 6.5,
> Z 2.4 and **DecorSlot_3** at X 0, Z -3.2, measured from the centre of Floor, each an invisible 4 by 1 by 4 part
> sitting on the floor (Transparency 1, CanCollide false). Anchor every part.

Then check the names (like [B3](#b3-check-the-names-)), make it look good, save it, and drag it into
**ServerStorage → ClinicKit**.

---

## Part D: the creatures
There are 13 creatures: 10 patients and 3 **regulars**, who come back with a story. Each one is a Model in
**ServerStorage → Creatures**, named exactly like the first column below. The names players see are placeholders.
Rename them however you like and tell Joshua. The model name stays.

### D1. The creature rules (Rated Minimal) ⛔
Lots of the players are 5 to 8 years old, so creatures must be:
- **cute, round and friendly**, with big eyes, rosy cheeks and a happy or calm face.
- **without** teeth, claws, spikes, blood, scars, or anything scary, gross or sharp.
- **original.** Don't copy anything from another game, a cartoon, a toy brand or a meme. Make them your own.
- **made of a mesh or simple parts only.** No Humanoid, no scripts, about **3 studs tall**. (One shorter than 1 stud
  or taller than 9 gets resized to about 3, and any script or Humanoid inside is deleted, but get it right anyway.)

A creature looks the same when it's sick and when it's cured. The game shows what's wrong with a big icon above its
head, and adds the night glow, ✨ sparkles and 🧊 frost by itself.

### D2. Make one creature (do this for each)
1. **Make a guide box.** Copy this into Assistant:
   > Create an anchored Part in Workspace named **Box**, 3 by 3 by 3 studs, sitting on the ground at 20, 1.5, 0.
2. **Click Box** in Explorer. Then copy that creature's `/generate_mesh` line from [D3](#d3-the-cast) into
   Assistant. Assistant makes the creature fit inside the box. If it asks about splitting it into parts or about
   triangles, pick **few parts** and a **low** triangle count, because lots of kids play on phones.
3. Don't like it? Ask again. When you love it, click **Add to place**.
4. Click **Box** and delete it.
5. **Finish it.** Copy this into Assistant, but change `DumplingFrog` to the creature's model name:
   > Put the creature mesh I just added into a Model in Workspace named **DumplingFrog**. Turn it so its face looks
   > toward -Z. Set the model's pivot to the bottom centre of the creature, with no rotation. Anchor every part, turn
   > CanCollide off, and make sure there are no scripts or Humanoids inside.
6. Check it in Explorer: one Model, named exactly right, with the mesh inside.
7. Drag it into **ServerStorage → Creatures**. Then **File → Save to File**.

### D3. The cast
| Model name | Who | What's wrong |
|---|---|---|
| `DumplingFrog` | Dumpling Frog | Hiccups ❗ |
| `CloudSheep` | Cloud Sheep | Sneezes 🤧 |
| `ToastPup` | Toast Pup | A bump 🤕 |
| `JellyBun` | Jelly Bun | A scrape 😢 |
| `SlimeCat` | Slime Cat (needs the Bath Room) | Sticky 🍯 |
| `MossMole` | Moss Mole (needs the Bath Room) | Muddy 🐾 |
| `SnowconePenguin` | Snowcone Penguin (needs the Winter Wing) | Chills 🥶 |
| `IcicleOwl` | Icicle Owl (needs the Winter Wing) | Frozen nose ❄️ |
| `HiccupGhost` | Hiccup Ghost (night only) | Cough 😷 |
| `MoonMoth` | Moon Moth (night only) | Lost glow 🌑 |
| `ShySprout` | Shy Sprout (regular: scared, then becomes your mascot) | Sneezes 🤧 |
| `GrumpyTeapot` | Grumpy Teapot (regular: grumpy, then gives you a lucky kettle) | Hiccups ❗ |
| `DizzyComet` | Dizzy Comet (regular: lost, then finds the way home) | A bump 🤕 |

The `/generate_mesh` lines (click **Box** first, then copy one in):

**DumplingFrog**
```
/generate_mesh a cute round cartoon frog shaped like a steamed dumpling, pale green body, cream belly, pleated dumpling top on its head, big friendly eyes, rosy cheeks, smiling, no teeth, nothing sharp, standing, facing forward
```
**CloudSheep**
```
/generate_mesh a cute fluffy cartoon sheep made of a soft white cloud, pale blue face and floppy ears, big friendly eyes, rosy cheeks, smiling, no teeth, nothing sharp, standing, facing forward
```
**ToastPup**
```
/generate_mesh a cute cartoon puppy shaped like a thick slice of toast, golden crust edges, floppy ears, a little tail, big friendly eyes, rosy cheeks, smiling, no teeth, nothing sharp, standing, facing forward
```
**JellyBun**
```
/generate_mesh a cute cartoon bunny made of shiny pink jelly, a soft drop shape, long ears, big friendly eyes, rosy cheeks, smiling, no teeth, nothing sharp, standing, facing forward
```
**SlimeCat**
```
/generate_mesh a cute cartoon cat made of glossy mint green slime, a soft drop shape, small rounded ears, a curly tail, big friendly eyes, rosy cheeks, smiling, no teeth, no claws, standing, facing forward
```
**MossMole**
```
/generate_mesh a cute round cartoon mole, soft brown fur, a patch of green moss on its back, a little leaf on its head, round ears, big friendly eyes, rosy cheeks, smiling, no teeth, no claws, standing, facing forward
```
**SnowconePenguin**
```
/generate_mesh a cute round cartoon penguin, blue body, white belly, a scoop of snow cone ice on its head, little flippers, big friendly eyes, rosy cheeks, smiling, nothing sharp, standing, facing forward
```
**IcicleOwl**
```
/generate_mesh a cute round cartoon owl, icy pale blue feathers, soft rounded white ear tufts, small wings, big friendly eyes, rosy cheeks, smiling, nothing sharp, standing, facing forward
```
**HiccupGhost**
```
/generate_mesh a cute friendly cartoon ghost, soft white and lavender, a round drop shape, big friendly eyes, rosy cheeks, a little smile, not scary at all, floating, facing forward
```
**MoonMoth**
```
/generate_mesh a cute fluffy cartoon moth, soft lavender body, round pale yellow wings, two curly antennae, big friendly eyes, rosy cheeks, smiling, nothing sharp, standing, facing forward
```
**ShySprout** (make its box 2.5 by 2.5 by 2.5: it's small)
```
/generate_mesh a small shy cartoon plant sprout creature, bean shaped, light green with a cream face, one leaf on top, big friendly eyes, rosy cheeks, a shy smile, nothing sharp, standing, facing forward
```
**GrumpyTeapot**
```
/generate_mesh a cute round cartoon teapot creature, coral red, a lid on top, a little spout, tiny arms, big eyes with grumpy eyebrows but still cute, rosy cheeks, no teeth, nothing sharp, standing, facing forward
```
**DizzyComet**
```
/generate_mesh a cute round cartoon comet creature, soft yellow body, a little star on its head, a short fluffy orange glowing tail, big friendly eyes, rosy cheeks, smiling, nothing sharp, floating, facing forward
```

---

## Part E: decorations
Players buy decorations or earn them, then put them in the **DecorSlot** spots in their rooms. Each one is a Model in
**ServerStorage → ClinicKit → Decor**.

### E1. The decoration rules
- **Fits a 4 by 4 stud square** on the floor, and is **no taller than about 7 studs**.
- **Pivot at the bottom centre,** with the front toward -Z.
- Cozy and cute. Same rules as the creatures: nothing scary, gross or copied.
- No scripts inside.

### E2. Make one decoration
1. Copy this into Assistant:
   > Create an anchored Part in Workspace named **Box**, 4 by 4 by 4 studs, sitting on the ground at 30, 2, 0.

   (For a rug, make the box 4 by 0.4 by 4. For something tall, 4 by 7 by 4.)
2. Click **Box**, then type `/generate_mesh` and the idea from the table below. Click **Add to place**, then delete
   **Box**.
3. Copy this into Assistant, but change `PottedFern` to the decoration's model name:
   > Put the mesh I just added into a Model in Workspace named **PottedFern**. Set the model's pivot to the bottom
   > centre, with no rotation, front toward -Z. Anchor every part and make sure there are no scripts inside.
4. Drag it into **ServerStorage → ClinicKit → Decor**.

**To make it glow at night** (lamps and lanterns), copy this into Assistant, using your model and part names:
> In the model **BubbleLamp**, put a PointLight inside the part that should glow, and give that part the tag
> **ClinicNightLight**.

At night the game makes that part bright and turns its light on. ⚠️ Only tag the glowing bit: in the day the game
turns that part back into plain plastic.

**A gentle sway** (balloons, a lantern on a string) is optional and fiddly: ask Joshua. It needs a small Model directly
inside the decoration, tagged **ClinicDecorBob**, with a PrimaryPart and the attributes `BobRest` (its CFrame relative to the
decoration's pivot), `BobHeight`, `BobSway`, `BobSpin` and `BobSpeed`.

### E3. The decorations
| Model name | What it is | How players get it | Idea for `/generate_mesh` |
|---|---|---|---|
| `PottedFern` | 🌿 Potted Fern | Shop | a leafy green fern in a round clay pot |
| `CozyRug` | 🧶 Cozy Rug | Shop | a round soft orange knitted rug, flat on the floor |
| `BubbleLamp` | 💡 Bubble Lamp | Shop | a cute floor lamp with a round pale yellow glass bulb on a light blue stand |
| `BalloonBunch` | 🎈 Balloon Bunch | Shop | a bunch of pink and blue balloons tied to a little weight |
| `ToyShelf` | 🧸 Toy Shelf | Shop | a small wooden shelf with soft toys and building blocks |
| `FishBowl` | 🐠 Fish Bowl | Shop | a round glass fish bowl on a little stand with one orange fish |
| `FlowerArch` | 🌸 Flower Arch | Shop | a small white garden arch covered in pink flowers |
| `HeartRug` | ❤️ Heart Rug | Finish the Meadow page set in the Patient Book | a heart shaped pink rug, flat on the floor |
| `RubberDuckFountain` | 🦆 Duck Fountain | Finish the Bubble Pond set | a small round fountain with a yellow toy duck on top |
| `SnowGlobeLamp` | ☃️ Snow Globe Lamp | Finish the Snowy Hills set | a big snow globe lamp with a tiny snowman inside |
| `MoonLantern` | 🌙 Moon Lantern | Finish the Moonlit Woods set | a lavender paper lantern shaped like a crescent moon |
| `SproutMascot` | 🌱 Sprout Mascot | Finish Shy Sprout's story | a little statue of a shy green sprout creature waving |
| `LuckyKettle` | 🍀 Lucky Kettle | Finish Grumpy Teapot's story | a coral red kettle with a green four leaf clover on it |
| `CometLantern` | 🌠 Comet Lantern | Finish Dizzy Comet's story | a lantern with a little glowing yellow star inside |
| `FriendBench` | 🛋️ Friend Bench | Invite a friend who joins | a small mint green bench for two |

Make `SproutMascot` look like your Shy Sprout creature, `LuckyKettle` like your Grumpy Teapot, and `CometLantern`
like your Dizzy Comet.

---

## Part F: put it in the real game
Do this once Joshua says Team Create is ready and you have **Edit** access.

1. Open Studio. Find the game under games **shared with you** and open it. You're now in **Team Create**: Joshua
   sees what you build, live.
2. In **Explorer**, look in **ServerStorage**. If there's no **ClinicKit** (with **Decor** inside) or **Creatures**
   folder yet, do [A4](#a4-make-the-folders-copy-this-into-assistant) again here.
3. **The easy way to move a model across:** open your practice place too. Click your model in Explorer and press
   **Cmd+C**. Go to the real game, right-click the right folder (for example **ClinicKit**) and pick **Paste Into**.
   **The other way:** open the **Toolbox** → **Inventory** → **My Models**, click your model (it drops into
   Workspace), then drag it into the right folder.
4. Check the names one more time. There must be only **one** model with each name.
5. Press **Play**. Your First-Aid Stand should be on **all 6 plots**. Walk around and check:
   - the open front faces the Counter and the street;
   - the patients line up in front of the Counter and face it;
   - you can reach both stations from behind the Counter.
6. Look in **Output** for lines starting with `[PlotBuilder]`. They tell you exactly what's missing (see
   [Stuck?](#stuck)).
7. Press **Stop**.

**Testing the other rooms:** players have to buy them with ⭐ Stars and cash, so they won't show up straight away.
Ask Joshua to unlock one in a test so you can see it.

---

## Part G (later): your own plot
You don't have to do this. The game builds a nice plot with a fence, a gate, trees, a sign and a mailbox. But if you
want to design the whole plot yourself, make a Model named **Plot** in **ServerStorage → ClinicKit**. If anything
below is missing, the game uses its own plot and prints what's missing in Output.

Your Plot model needs all of these, named exactly like this, directly inside it:

| Name | What it is |
|---|---|
| `Ground` | The grass: 70 by 1 by 70 studs. Plots sit 8 studs apart, so keep everything inside it |
| `Counter` | Where players treat patients, in front of the Stand's spot |
| `QueueStart` | Invisible 2 by 1 by 2 part on the ground, about 3.5 studs in front of the Counter, **facing the Counter** (Orientation 0, 180, 0). The line grows from here toward the street, so keep about 16 studs clear in front of it |
| `PatientSpawn` | Invisible 2 by 1 by 2 part on the ground near the gate, **facing the Counter** (Orientation 0, 180, 0). Patients appear here |
| `PatientExit` | Invisible 2 by 1 by 2 part on the ground near the gate, **facing the street** (Orientation 0, 0, 0). Cured patients leave here |
| `Sign` | The clinic sign by the street, at Orientation 0, 0, 0. Inside it, a SurfaceGui named `SignGui` with Face set to **Front** (the street side), and two TextLabels inside that: `OwnerName` (the game writes "<name>'s Clinic") and `HeartCount` (the game writes "❤️ 5") |
| `Slots` | A Folder of invisible parts, each the same size as its room's Floor: `RoomSlot_Stand` (22 × 0.6 × 14), `RoomSlot_A` for the Bath Room (18 × 0.6 × 16), `RoomSlot_B` for the Ward (22 × 0.6 × 14), `RoomSlot_C` for the Winter Wing (18 × 0.6 × 16) and `RoomSlot_D` for the Garden (22 × 0.6 × 14). Each one sits on the ground, Orientation 0, 0, 0, exactly where that room's floor goes |

Then ask Assistant:
> Set the WorldPivot of the model **Plot** to the centre of the top face of **Ground**, with no rotation, so its
> front points to -Z (the street side). Don't set a PrimaryPart. Anchor every part. No scripts inside.

The street is on the **-Z** side. Put the gate, the Sign, PatientSpawn and PatientExit near that edge.

---

## Part H (later): the Nurse Belt, nurses and bigger hospitals
You don't have to do these either: the game builds its own. Make one only if you want your own look. Same rules as
everything else (no scripts, Rated Minimal, original, **no red cross on white**).

**The Nurse Belt** (the conveyor in town where nurses ride past): a Model named **NurseBelt** in **ServerStorage →
ClinicKit**. It needs three Parts named exactly `BeltStart`, `BeltEnd` and `Sign`. Riders ride from BeltStart to
BeltEnd. If you want, add a SurfaceGui named `OddsGui` on the Sign's front (the game writes the odds on it), a Folder
named `Riders` and a Part named `Conveyor` (the moving-looking top). The game puts its pivot on the street east of
the plaza, with its **+X** pointing along the belt.

**A nurse's look**: a Model (or one MeshPart) named after the nurse, like **PuffPup**, in a Folder **ServerStorage →
Nurses**, its face toward **-Z**. It replaces that nurse's placeholder look. No Humanoid and no scripts; the game adds
no cap to it, so give it its own (a cap in its rarity's colour looks great). The nurse names are in
`game/src/shared/Data/Nurses.luau`, and they're placeholders you two can rename.

**A bigger hospital**: a Model named **Building2** to **Building5** in **ServerStorage → ClinicKit**. It replaces the
whole placeholder building for that hospital level. Its pivot is the centre of the top of the plot's Ground, facing
the street. It needs `Bed_<n>` Parts for the extra beds (Lv 2-3: `Bed_1`; Lv 4-5: `Bed_1` and `Bed_2`). Keep it
behind the Stand: it must not cover the Counter, the line in front of it, the gate, the walkways beside the Stand
(about 12 to 14 studs out from the middle on each side) or the room slots. Keep the whole plot to about 400 parts.

---

## The old Shop
Joshua deleted the old **Shop** model on 2026-11-16 (version 15 and earlier still have it, in **File → Version History**).
The clinic town is the whole game now.

---

## Rules
- ⛔ **Don't touch the scripts.** Leave **ServerScriptService**, **StarterPlayer → StarterPlayerScripts** and
  **ReplicatedStorage → Shared** alone. That's the code, and changes made there get wiped.
- ⛔ **Don't build inside Workspace → Clinics or Workspace → ClinicTown.** They only appear while playing, and the
  game deletes and rebuilds them every time it starts. Your rooms go in ServerStorage instead.
- ⛔ **No scripts inside anything in ClinicKit or Creatures.** If Assistant or the Toolbox adds a model made by
  someone else, click the arrow next to it in Explorer. If you see a **Script** or **LocalScript** inside, delete it,
  or ask Joshua.
- ⛔ **Rated Minimal.** Cartoon care only: plasters, potions, warm baths, cocoa and cuddles. **No needles, no
  blood, no surgery, no weapons, nothing gross or scary.** Night is cozy and glowy, not spooky.
- ⛔ **No red cross on white.** That's the Red Cross emblem, a protected symbol that games aren't allowed to use. Use
  a heart, a plaster or a paw print instead.
- ⛔ **Make it your own.** Don't copy another game's look, characters or name, or a toy brand or a meme.
- **Think of phones.** Lots of kids play on old phones and iPads. Use meshes instead of hundreds of tiny parts, and
  keep each room to about 150 parts or fewer.

---

## Name cheat sheet
| Where | Exact names |
|---|---|
| Folders in ServerStorage | `ClinicKit` · `ClinicKit` → `Decor` · `Creatures` |
| Rooms (in ClinicKit) | `Stand` · `BathRoom` · `Ward` · `WinterWing` · `Garden` · (later) `Plot` |
| Inside every room | `Floor` |
| Stations | `Station_Remedy` 🧪 · `Station_Plaster` 🩹 (Stand) · `Station_Bath` 🛁 (BathRoom) · `Station_Cocoa` ☕ (WinterWing) |
| Beds | `Bed_1` (Stand, WinterWing) · `Bed_1` and `Bed_2` (Ward) |
| Decor spots | `DecorSlot_1`, `DecorSlot_2` (Stand, Ward, WinterWing) · `DecorSlot_1` (BathRoom) · `DecorSlot_1` to `DecorSlot_3` (Garden) |
| Creatures (in Creatures) | `DumplingFrog` · `CloudSheep` · `ToastPup` · `JellyBun` · `SlimeCat` · `MossMole` · `SnowconePenguin` · `IcicleOwl` · `HiccupGhost` · `MoonMoth` · `ShySprout` · `GrumpyTeapot` · `DizzyComet` |
| Decorations (in ClinicKit → Decor) | `PottedFern` · `CozyRug` · `BubbleLamp` · `BalloonBunch` · `ToyShelf` · `FishBowl` · `FlowerArch` · `HeartRug` · `RubberDuckFountain` · `SnowGlobeLamp` · `MoonLantern` · `SproutMascot` · `LuckyKettle` · `CometLantern` · `FriendBench` |
| Night glow tag | `ClinicNightLight` |
| Plot (later) | `Ground` · `Counter` · `QueueStart` · `PatientSpawn` · `PatientExit` · `Sign` → `SignGui` → `OwnerName`, `HeartCount` · `Slots` → `RoomSlot_Stand`, `RoomSlot_A`, `RoomSlot_B`, `RoomSlot_C`, `RoomSlot_D` |
| Belt and hospitals (later) | `ClinicKit` → `NurseBelt` (`BeltStart`, `BeltEnd`, `Sign`; optional `OddsGui`, `Riders`, `Conveyor`) · `ClinicKit` → `Building2` … `Building5` (`Bed_1`, `Bed_2`) · `Nurses` → `<NurseId>` |

---

## Stuck?
**What Output says, and what to do:**
| Output says | Fix |
|---|---|
| `[PlotBuilder] ClinicKit.Stand has no Part named Floor; using the placeholder` | Your room needs a Part called exactly `Floor` |
| `[PlotBuilder] ClinicKit.Stand is missing Station_Remedy` (or `Bed_1`, `DecorSlot_2`...) | That special part is missing or spelled wrong. Check B3 |
| `[PlotBuilder] ClinicKit.Plot is missing: ...` | Your Plot needs what it lists (Part G). Until then the game uses its own |

**My room faces backwards** (the open side faces away from the Counter). Copy this into Assistant, using your room's
name:
> In the model **Stand**, turn every part except Floor 180 degrees around the centre of Floor. Keep Floor's
> Orientation at 0, 0, 0.

**My creature faces backwards in the line.** Copy this into Assistant:
> Turn every part inside the model **DumplingFrog** 180 degrees around the model's pivot, but keep the pivot as it
> is.

**Something else.** Ask Assistant: *"How do I move a part?"*, *"How do I make this part bigger?"*, *"Why can't I see my
part?"* Still stuck? Tell Joshua what you tried and what happened.

---

## For Joshua: checking the brother's kit
- **ServerStorage is outside Rojo.** `default.project.json` only syncs `ReplicatedStorage.Shared`,
  `ServerScriptService.Server` and `StarterPlayerScripts.Client`, so `ClinicKit` and `Creatures` live only in the
  place file. Save the place after he adds things.
- **To see an unbought room in a test:** there's no Studio shortcut yet, so earn it in play (the Bath Room needs ⭐10
  and 150 cash). Don't `require` the server modules from the command bar: it likely gets its own fresh copy of the
  module, not the running one, so calls like `Plots.unlockRoom` from there do nothing.
- **Scripts in kit models run.** PlotBuilder clones kit rooms into Workspace, so a Script hidden in a free model would
  run in the live game. Check `ClinicKit` and `Creatures` for any Script or LocalScript before each publish.
- **Generated meshes are his assets.** Studio Assistant meshes are uploaded to the account of whoever made them,
  which matters for the ownership note (OPEN #2). Check they load for other players in a 2-player test.
- The exact contracts are in `docs/plan/2026-11-16-creature-clinic-build-plan.md` §B1. This guide follows them.
