# Performance budget (depth update, Update 1)

Owner: T7 (performance pass). Spec: `docs/plan/2026-11-16-depth-update-design.md` §5. Contracts:
`docs/plan/2026-11-16-depth-update-build-plan.md` §B4 (creature motion) and Review focus 4. Progression v2 (T6): the
walkable hospital's part counts and rules are in [their own section](#progression-v2-the-walkable-hospital-t6).

**Nothing in this note has been measured yet.** T7 had no Studio access. The "counted from the code" figures below
come from reading the scripts, and the lead fills in the measured column during the playtest (§D item 14).

## The budget
| Rule | Limit | Who keeps it |
|---|---|---|
| Frame rate | 60 fps on a mid phone with 6 full plots and the belt | everyone; the lead measures |
| Parts per plot | ≤ 400 at hospital Lv 5 for the plot, rooms and building (Progression v2: 372, or 378 with the biggest theme prop; [table below](#progression-v2-the-walkable-hospital-t6)), **plus decor**: 10 slots, ≤ 25 parts a piece (548 counted with every slot filled, the heaviest placeholder pieces) (review fix 2026-11-16: the two numbers used to disagree on whether decor counted) | T6 `PlotBuilder` (`tests/Hospital.spec` fails past 400 at any level in any theme); `DecorBuilder` warns once per DecorId over 25 |
| Parts per creature | under 40 (placeholder); a night creature adds 1 (its glow ring) | `CreatureBuilder`, `NurseBuilder` |
| Highlights | **at most 1 in the whole world**; creatures, nurses, riders and kit models never use one | `CreatureBuilder` (creatures and kit creatures); `PlotBuilder`, `DecorBuilder`, `NurseBuilder` and `NurseBelt` remove any in kit models (applied at integration) |
| Lights | no light casts shadows (`Shadows = false` on every PointLight, SpotLight and SurfaceLight) | every builder; kit models are forced off |
| Shadow casters | creature parts under 1.5 studs across don't cast shadows (the body's shadow covers them) | `CreatureBuilder` |
| Server writes | no per-frame `CFrame` writes for creatures or riders. One write per animation end; riders at most once a second (`Config.Belt.ServerStepSeconds`) | `Patients` (applied at integration), `NurseBuilder`/`Nurses`, `NurseBelt` |
| Client loops | nothing runs every frame unless something on screen is moving | `CreatureMotion`, `Atmosphere`, `Tutorial`, `Guide`, `BeltView` |

## Creature motion moves to the client (§B4)
The server used to step every moving creature on one Heartbeat and write `Root.CFrame` each frame. Now each animation
is one set of attributes plus one end-pose write:

| | Before (counted from the code) | After |
|---|---|---|
| One hop (about 0.3 s) | about 18 `Root.CFrame` writes at 60 Hz, each sent to every player | `HopFrom`, `HopTo` and `HopAt` (the other hop attributes are resent only when they change), then 1 `Root.CFrame` write when it lands |
| Pop in (0.45 s), leave (0.35 s), sad puff (0.4 s) | `Model:ScaleTo` every frame (about 21 to 27 times), each one resizing every part | 6 scale attributes, then 1 `ScaleTo` at the end |
| Head-shake, sad droop | `Root.CFrame` every frame while it plays | 1 attribute (`ShakeAt`, `Tilt`) |

- **Server helpers:** `CreatureBuilder.hop / shake / tilt / scale` set the attributes, with the time last. The caller
  waits, then writes the end pose once. `NurseBuilder` does the same for nurses.
- **Client:** `Feel/CreatureMotion` draws every Model tagged `CreatureMotion`. It runs on RenderStepped only while
  something animates, and disconnects when everything has landed. It plays each animation a smoothed network delay
  behind the server (at most 0.25 s), so chained hops play whole. Creatures more than 160 studs from the camera skip
  the in-between frames and jump to each end pose. Reduced motion lowers the hops and removes lean, spin and overshoot.
- **One rule for anything that moves a tagged creature:** set every rest pose through a hop (`HopSeconds = 0` gives
  a snap), or `PivotTo` it before it's tagged. The client also notices a server teleport and keeps it, but a hop is
  the clean way.
- **Belt riders** follow the belt formula (BeltView draws them). They get the tag only when they hop off.

## Night creatures without Highlights
Night creatures used to get one Highlight each, and the engine draws at most 31 at once. Now they glow with a
shadow-free PointLight (brightness 1.8, range 12), a see-through Neon glow ring under their feet, and Neon tips (the
existing ones). The Bloom at night (`DayNight`) makes the Neon glow.

## Client loops that sleep
| Module | Before | After |
|---|---|---|
| `Feel/Atmosphere` | RenderStepped every frame, always: the snow and firefly boxes, and a distance check over all decor | The snow and firefly boxes follow 5 times a second, only while it snows or it's night. Decor is scanned twice a second, only while there's decor and calm mode is off. RenderStepped runs only while decor within 140 studs sways |
| `UI/Tutorial` | RenderStepped every frame for every player, even after the tutorial | Only while the card shows, or on steps 7 and 8 (the 👇 into a panel) |
| `UI/Guide` | Polled 5 times a second until 3 cures. Its pin's endless bounce tween ran while hidden. It handled every part added to the town | Polls 5 times a second only while the pin shows. Otherwise it rests until your plot, your carry, your cures, the snapshot or the plot's `FrontStation` change (1 s at most). The bounce pauses while hidden. It tracks station prompts by tag only |
| `UI/PromptFilter` | Handled every part added to `Workspace.Clinics` (each creature, nurse and building floor) | Tags only (`ClinicSignPrompt`, `StationPrompt`, `TreatPrompt`), plus a watch on each plot's Counter until Patients tags its prompt |
| `Feel/CreatureMotion` | (new) | Runs only while a creature animates |
| `UI/BeltView` | (new) RenderStepped and every rider's rarity shimmer all session, for every player | The frame loop runs only while the camera is within 320 studs of the belt; a rider's card is shown (and shimmers) only within 50 studs of you (review fix 2026-11-16) |

MicroProfiler labels to look for: `CreatureMotion`, `Atmosphere sway`, `Tutorial layout`.

## Progression v2: the walkable hospital (T6)
Build plan `docs/plan/2026-11-16-progression-v2-build-plan.md` §B4 and Review focus 4. Counted by running the shipped
`Server/PlotBuilder` under a small Instance mock in Lune (`tests/Hospital.spec`, "the built world"): Plot_1 with
every room (Stand, Bath Room, Ward, Winter Wing, Garden), no creatures, no nurses, no decor. **Not measured in Studio
yet**: the lead checks with the command-bar count below (§D P22).

| Hospital level | Before (Update 1 code, same count) | After, Candy | After, biggest theme prop (Jungle, Royal: 6 parts) | Building alone (Candy) |
|---|---|---|---|---|
| Lv 1 | 367 | 297 | 303 (the prop sits on the Stand) | 0 |
| Lv 2 | 397 | 339 | 345 | 42 |
| Lv 3 | 397 | 348 | 354 | 51 |
| Lv 4 | 414 | 362 | 368 | 65 |
| Lv 5 | **418** (over budget: the 389 above predates the queue lane) | **372** | **378** | 75 |

- **The Lv 5 building (75):** Lobby 5 · Floor_1-3 4 each (Slab, SlabBack, Landing, see-through Walls) · Floor_4 (the
  roof) 3 · Landing_0 1 · Lift 3 (Shaft, Car, Cap) · Stairs 4 (one ramp a storey) · Wards 18 (3 beds) · Hydro 5 ·
  Pharmacy 3 · Roof 6 (helipad, HeliSpot, 2 planters) · Tower 6 · name board 1 · AmbulanceBay 8.
- **The rest of the plot at Lv 5 (297):** the plot's own parts 7 (incl. the new MascotSpot) · room slots 5 · scenery
  118 · queue lane 21 · rooms 146 (Stand 35, Bath Room 24, Ward 28, Winter Wing 31, Garden 28).
- **Reclaimed (71 parts), all drawn as SurfaceGuis instead, same look:** the awnings' stripes and flaps (12 parts a
  room → 2; -40), the room floors' stripes (-15), the back-wall bands (-4), the station front stripes (-3), the lawn's
  mowing stripes (-5), the path's edges (-2), the Counter's stripe (-1), the gate arch's stripe (-1). The building
  draws its windows, stair steps, ✚ crosses (2 parts each, was 4), the helipad's H and the ambulance's stripes; each
  ambulance axle is one cylinder that shows a wheel on both sides (2 parts, was 4).
- **SurfaceGuis (the price of the reclaimed parts):** a Lv 5 plot with every room has 62 (Update 1 code: 30), a Lv 1
  plot 34 (was 9). 37 of the 62 are flat details (stripes, steps, bands) that hide past 160 studs (`MaxDistance`), so
  only your own plot and its neighbours draw them; windows, crosses and the lawn stay to 400. Watch the frame time in
  P22: if a phone struggles, lower `DETAIL_NEAR` in PlotBuilder first, then give the windows a `MaxDistance` too.
- **Server writes:** none per frame. A lift ride is four attribute writes at its start (the Lift's `Ride`, `Rider`
  and `RideAt`, the rider's `LiftRide`) and one `PivotTo` per rider at the far landing (`Lift.ride` / `Lift.carry`).
  The car never moves on the server.
- **Client loops:** `UI/LiftPanel` only plays tweens while a car moves (your ride, or a car within 250 studs of the
  camera; a far one just jumps), and its picker checks your distance 3 times a second only while it's open. Nothing
  on RenderStepped.
- **With decor (integration, 2026-11-17):** `tests/Hospital.spec` now also builds every Data/Decor piece through the
  real `DecorBuilder` under the same mock. Each is ≤ 25 parts, and the 10 heaviest (one per slot: each decor exists
  once) add 170, so a Lv 5 plot with every room and every decor slot filled is **548** parts in the worst theme
  (placeholder decor; a kit piece is warned past 25).
- **The town kiosks (Progression v2, T3/T4):** `Workspace.NurseAgency` 16 anchored parts and
  `Workspace.PlayerMarket` 19 (both CastShadow off, no lights, no Highlight; the Market's ModelStreamingMode
  Atomic), each with 1 ProximityPrompt; the Market has 2 SurfaceGuis. Built once per server.
- **Headroom:** 22 parts at Lv 5 in the worst theme. Next levers if it's needed: the BlanketStripe of each bed (7 at
  Lv 5), the Bath's TubStripe, the Garden's flowers (13), a bush's flowers (3 each, 8 bushes).

## If a phone still misses 60 fps (next levers, not done)
These trade looks for speed, so the brothers decide:
- `Lighting.Technology` and `GlobalShadows` live in the place file (Studio owns the world). The sun's shadows and a
  heavier lighting technology cost more than anything above.
- `CULL_STUDS` in `Feel/CreatureMotion` (160): lower it and fewer far creatures get drawn in between.
- Particle rates: Sparkly and Frosty glitter, heal sparkles, snow (`Atmosphere`'s `SNOW.Rate`).
- `BillboardGui.MaxDistance` on badges (75) and station icons (80).
- Decor parts: the placeholder recipes run about 8 to 25 parts a piece (a Rug about 9, a Plant 12 or more). If a
  fully decorated Lv 5 plot costs frames, trim the biggest recipes first, or cut the Lv 5 shell (merge window and
  rail parts, more SurfaceGui detail).
- The belt's cards show only within 50 studs of you (`BeltView` `CHIP_MARGIN`), and its frame loop sleeps while the
  camera is more than 320 studs from the belt (`MOVE_MAX_DISTANCE`).

## How to measure (lead, §D item 14)
1. **Before/after on the same machine:** run the same session on `main` and on this branch. Use the Roblox player's
   in-game Settings → Performance Stats (FPS, ping, memory) and the MicroProfiler (Ctrl+F6 in the player,
   Ctrl+Alt+F6 in Studio). Record FPS, the frame time, and the network receive rate while a full line of patients
   hops at night.
2. **Phone:** Studio's Device emulator only checks layout, so frame rate needs a real mid-range phone on a private
   test build. Going public needs both brothers' yes (CLAUDE.md red line 4).
3. **Counts** (Studio command bar on the server, during play):
   - Highlights: `local n=0 for _,d in workspace:GetDescendants() do if d:IsA("Highlight") then n+=1 end end print(n)`
     should print 1 or less.
   - Shadow lights: the same loop with `d:IsA("Light") and d.Shadows` should print 0.
   - Parts per plot at Lv 5, without creatures: `local n=0 for _,d in workspace.Clinics.Plot_1:GetDescendants() do
     if d:IsA("BasePart") and not d:FindFirstAncestor("Patients") and not d:FindFirstAncestor("Nurses") then n+=1
     end end print(n)` should print 400 or less with no decor placed, and about 500 with every decor slot filled
     (this count includes decor).
4. **Sleep checks:** with nothing moving (an empty clinic by day, tutorial done, calm mode on), the MicroProfiler
   shows none of the labels above.

| Measure | Target | Measured on `main` | Measured on this branch |
|---|---|---|---|
| FPS, mid phone, 6 full plots + belt, night | 60 | | |
| FPS, PC, same scene | 60 | | |
| Network receive per client while patients hop (KB/s) | lower than `main` | | |
| Highlights in the world | ≤ 1 | | |
| Shadow-casting lights | 0 | | |
| Parts in Plot_1 at Lv 5 (no creatures, no decor) | ≤ 400 (counted from the code: 418 before, 372 after; 378 in Jungle/Royal) | | |
| Parts in Plot_1 at Lv 2 / 3 / 4 (Progression v2) | ≤ 400 (counted: 339 / 348 / 362) | | |
| Network receive per client during a lift ride and an ambulance (KB/s) | no spike | | |
| Parts in Plot_1 at Lv 5 with every decor slot filled (no creatures) | about 500 (counted from the code: 548 with the 10 heaviest placeholder pieces) | | |
