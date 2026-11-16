--!strict
-- STUB (Task 0). Owned by Task 5: replace with the real dailies (build plan §B5).
--   Daily.visitorFor(p): PatientId? · Daily.onCure(p, ctx) · Daily.onMake(p, itemId)
--   start(): mailbox and goals on join, wires ClaimGoal and ClaimMailbox, keeps Workspace.UtcDay and
--   Workspace.TodaysVisitor up to date (refreshed each minute)

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local Daily = {}

function Daily.visitorFor(_player: Player): string?
	return nil
end

function Daily.onCure(_player: Player, _ctx: Types.CureCtx) end

function Daily.onMake(_player: Player, _itemId: string) end

function Daily.start()
	Workspace:SetAttribute("UtcDay", os.time() // 86400)
	Workspace:SetAttribute("TodaysVisitor", "")
	Remotes.serve("ClaimGoal", function()
		return false, "Coming soon!"
	end)
	Remotes.serve("ClaimMailbox", function()
		return false, "Coming soon!"
	end)
end

return Daily
