--!strict
-- STUB (Task 0). Owned by Task 5: replace with the real seasonal switch (build plan §B5).
--   Events.isWinter(): boolean   Config.Winter window, or Workspace.ForceWinter; sets Workspace.IsWinter

local Workspace = game:GetService("Workspace")

local Events = {}

function Events.isWinter(): boolean
	return false
end

function Events.start()
	Workspace:SetAttribute("IsWinter", false)
end

return Events
