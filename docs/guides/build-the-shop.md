# Build the shop: a step-by-step guide for the builder

> **Superseded by [`build-the-clinic.md`](build-the-clinic.md) (2026-11-16).** The game is now Creature Clinic. Your
> old shop stays in the place untouched; build the new rooms, creatures and decorations from the clinic guide.

You're building the place where the whole game happens. You don't need to know how to build: **Roblox Studio has an AI
helper called Assistant**, and you'll tell it what to make. Joshua's code does the customers, cash and upgrades. Your
job is to make the shop look amazing.

**Where:** Roblox Studio on your Mac.
**Part A** is practice in your own place (start now). **Part B** moves your shop into the real game (when Joshua says
Team Create is ready).

---

## Part A: build it in your own place (start now)

### A1. Open a blank place
Open Roblox Studio → **New** → **Baseplate**.

### A2. Open the windows you'll need
Find and open **Explorer** (the list of everything in your game) and **Properties** (the settings of whatever you
click). They're in the **View** or **Window** menu.

### A3. Open Assistant
Click **Assistant** in Studio. A chat panel opens. You type what you want, and it builds it.

### A4. Build the shop: copy this into Assistant
> Create a Model in Workspace named **Shop**. Inside it, build a small, cozy shop: a flat 40 by 40 stud wooden floor,
> walls about 12 studs tall on three sides with the **front side left open** as the entrance, and a counter 14 studs
> wide near the back wall, named **Counter**. Leave space behind the counter for players to stand. Anchor every part.
> Keep the floor flat and empty from the open front all the way to the counter.

### A5. Add the 5 special parts: copy this into Assistant
The game's code looks for these exact names, so they **must** be spelled exactly like this (capital letters too).
> Inside the Shop model, add these anchored parts with exactly these names:
> **Station**: a 4 by 5 by 3 stud block behind the counter, where players will make food.
> **QueueStart**: an invisible 2 by 1 by 2 stud part on the floor, 3 studs in front of the counter, on the customer side.
> **CustomerSpawn**: an invisible 2 by 1 by 2 stud part on the floor just inside the open front.
> **CustomerExit**: an invisible 2 by 1 by 2 stud part on the floor just inside the open front, 8 studs to the side of CustomerSpawn.
> Invisible means Transparency 1 and CanCollide false. Keep the Counter part named Counter.

### A6. Check the names ✅
In **Explorer**, click the arrow next to **Shop**. You should see all of these (more parts is fine):
`Counter` · `Station` · `QueueStart` · `CustomerSpawn` · `CustomerExit`
If one's missing or spelled differently: click it, press **F2** (or double-click) to rename it.

### A7. Make it look good (the fun part)
Ask Assistant for anything you like. Ideas:
> Make the walls pastel pink and the floor light wood.
> Add a sign above the entrance that says OPEN, and some shelves on the side walls.
> Add warm lights hanging from the ceiling.

**To make a cool machine or oven:** click **Station** in Explorer first, then type
`/generate_mesh a cute cartoon oven`. Assistant makes it fit inside Station's box. Then click the old **Station**
part and set its **Transparency** to **1**.
⛔ **Don't delete or rename Station.** The code needs it.

### A8. Walk around it
Press **Play** (or F5) to walk around your shop. No customers will show up in your practice place. That's normal,
because the code lives in the real game. Press **Stop** when you're done.

### A9. Save it
1. **File → Save to File** keeps a copy on your Mac.
2. In Explorer, **right-click Shop → Save to Roblox**. This puts your shop in your Roblox inventory, so you can drop
   it into the real game in Part B.

---

## Part B: put it in the real game (when Joshua says it's ready)

Before this works, **you and Joshua are Roblox friends, then Trusted Friends**, and Joshua has given you **Edit**
access. At 13, Roblox needs one of those (or a parent's OK) before you can build with someone 18+.

1. Open Studio. Find the game under games **shared with you** and open it. You're now in **Team Create**: Joshua sees
   what you build live.
2. Open the **Toolbox** → **Inventory** → **My Models** → click your **Shop**. It drops into the game.
3. In Explorer, make sure **Shop** sits **directly inside Workspace**, not inside another folder or model.
4. If there's another model already called Shop, tell Joshua. Only one shop can exist.
5. Press **Play**. Customers should now walk in from the front and line up at your counter. 🎉

---

## Rules
- ⛔ **Don't touch the scripts.** Leave **ServerScriptService**, **StarterPlayerScripts** and **ReplicatedStorage →
  Shared** alone. That's Joshua's code, and changes made there get wiped.
- ⚠️ **Free models can hide bad scripts.** If Assistant or the Toolbox adds a model made by someone else, click the
  arrow next to it in Explorer. If you see a **Script** inside, delete the script, or ask Joshua.
- ⛔ **Make it your own.** Don't copy another game's look, characters or name.
- Keep the floor between the entrance and the counter **flat and clear**, because customers walk in straight lines.

## Stuck?
1. Ask Assistant: *"How do I move a part?"*, *"How do I make this part bigger?"*, *"Why can't I see my part?"*
2. Still stuck? Tell Joshua what you tried and what happened.
