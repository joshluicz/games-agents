--!strict
-- The 🏢 Branch panel: open a new branch, perk cards, the Branch Ability Tree and themes (Progression v2 build plan
-- §B9, §C T5). OWNER: T5.
--   init(ctx)   opens on ctx.fire("Open", "Branch", "Open" | "Perks" | "Tree" | "Themes") (the Shop's 🏥 tab; "Perks"
--               after the Rebirth celebration). "Open" is the keep/reset screen (Logic/Rebirth.KEEP / RESET / GET, the
--               cost from Logic/Rebirth.cost; "Not now" is the default focus, "🏢 Open branch!" a 1.5 s
--               Kit.holdButton asking OpenBranch(true)). Asks OpenBranch, ChoosePerk, BuyNode, ResetTree, SetTheme and
--               ClaimBranchNurse. No pressure: no dots, no "hurry", locked themes show "🏢 R3".
--
-- STUB (T5): the Foundation's empty module, so Main.client loads it and nothing else has to wait for it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local BranchPanel = {}

function BranchPanel.init(_ctx: Types.Ctx) end

return BranchPanel
