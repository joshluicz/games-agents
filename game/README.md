# game/: the Rojo project

## Run it (Joshua, Windows, after the setup doc)
```powershell
cd games-agents\game
rokit install          # pinned rojo, selene, stylua (rokit.toml)
rojo plugin install    # once
rojo serve             # then in Studio: Rojo plugin → Connect → Play
```
No `Shop` model in Workspace yet? The server builds a grey placeholder shop, so you can play right away.

## What's where
| File | Becomes in Studio | Does |
|---|---|---|
| `src/shared/Config.luau` | ReplicatedStorage.Shared.Config | **Every tuning number**: product name, prices, patience, day/night length, pass IDs |
| `src/shared/Remotes.luau` | ReplicatedStorage.Shared.Remotes | The remote events and functions |
| `src/server/Main.server.luau` | ServerScriptService.Server.Main | Starts everything |
| `src/server/PlayerData.luau` | ServerScriptService.Server.PlayerData | Saving (DataStore), leaderstats |
| `src/server/ShopWorld.luau` | ServerScriptService.Server.ShopWorld | Finds the brother's `Shop` model, or builds the placeholder |
| `src/server/Customers.luau` | ServerScriptService.Server.Customers | Spawning, queueing, patience, serving |
| `src/server/Kitchen.luau` | ServerScriptService.Server.Kitchen | Hold to make at the `Station` |
| `src/server/Economy.luau` | ServerScriptService.Server.Economy | Pay maths, carrying, upgrades, the 2× Cash pass |
| `src/server/DayNight.luau` | ServerScriptService.Server.DayNight | Day/night cycle, night customers |
| `src/client/Hud.client.luau` | StarterPlayerScripts.Client.Hud | The screen: cash, carrying, timer, upgrades, toasts |
| `src/client/Music.client.luau` | StarterPlayerScripts.Client.Music | Background music (`Config.Music`), day and night playlists, Music On/Off button |
| `src/client/RoofFade.client.luau` | StarterPlayerScripts.Client.RoofFade | Fades a Model named `Roof` inside `Shop` while you're inside the shop |

## The loop
Customer walks in → queues at `QueueStart` → shows an order and a patience bar → you **hold E at the Station** to make
the product (sparkles) → **press E to Serve at the Counter** → cash. With no `Counter`, the Serve prompt sits on the
customer instead. Spend cash on **Upgrades** (bottom-left).

## Checklist for the first playtest (first run 2026-11-16, Joshua's PC)
- [x] Output shows `[Main] Shop is open.` and no red errors
- [x] Customers spawn, walk to the counter and queue behind each other
- [x] Holding at the station gives "Carrying: 1/1", and serving pays cash (3 served, 41 Cash)
- [ ] Upgrades buy, and the tray capacity and hold time change
- [ ] Night comes after 3 minutes (set `Config.DaySeconds = 20` to test faster), and night customers glow and pay 2×
- [ ] Rejoin and the cash is still there (needs **Game Settings → Security → Enable Studio Access to API Services**)

## Turn on the 2× Cash pass (Stage 1, after both say yes)
Creator Hub → your game → Monetization → Passes → create it → paste its ID into `Config.GamePasses.DoubleCash`.

## Before committing
```powershell
selene src
stylua --check src
```
