# Performance budget (depth update, Update 1)

Owner: T7 (performance pass). Spec: `docs/plan/2026-11-16-depth-update-design.md` §5. Contracts:
`docs/plan/2026-11-16-depth-update-build-plan.md` §B4 (creature motion) and Review focus 4.

**Nothing in this note has been measured yet.** T7 had no Studio access. The "counted from the code" figures below
come from reading the scripts, and the lead fills in the measured column during the playtest (§D item 14).

## The budget
| Rule | Limit | Who keeps it |
|---|---|---|
| Frame rate | 60 fps on a mid phone with 6 full plots and the belt | everyone; the lead measures |
| Parts per plot | ≤ 400 at hospital Lv 5 (rooms + building + decor, without creatures) | T5 `PlotBuilder.buildBuilding` measures |
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

MicroProfiler labels to look for: `CreatureMotion`, `Atmosphere sway`, `Tutorial layout`.

## If a phone still misses 60 fps (next levers, not done)
These trade looks for speed, so the brothers decide:
- `Lighting.Technology` and `GlobalShadows` live in the place file (Studio owns the world). The sun's shadows and a
  heavier lighting technology cost more than anything above.
- `CULL_STUDS` in `Feel/CreatureMotion` (160): lower it and fewer far creatures get drawn in between.
- Particle rates: Sparkly and Frosty glitter, heal sparkles, snow (`Atmosphere`'s `SNOW.Rate`).
- `BillboardGui.MaxDistance` on badges (75) and station icons (80).

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
     end end print(n)` should print 400 or less.
4. **Sleep checks:** with nothing moving (an empty clinic by day, tutorial done, calm mode on), the MicroProfiler
   shows none of the labels above.

| Measure | Target | Measured on `main` | Measured on this branch |
|---|---|---|---|
| FPS, mid phone, 6 full plots + belt, night | 60 | | |
| FPS, PC, same scene | 60 | | |
| Network receive per client while patients hop (KB/s) | lower than `main` | | |
| Highlights in the world | ≤ 1 | | |
| Shadow-casting lights | 0 | | |
| Parts in Plot_1 at Lv 5 (no creatures) | ≤ 400 | | |
