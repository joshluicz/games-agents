--!strict
-- STUB (Task 0). Owned by Task 3: replace with the real unlock rules and its spec (tests/Progress.spec.luau).
-- Pure: no Roblox services, no requires. Signatures from build plan §B6.

local Progress = {}

-- Can this save buy `room` (a Data/Rooms row) right now? Returns (ok, message) with a short message.
function Progress.canBuyRoom(_data: any, _room: any, _roomId: string): (boolean, string)
	return false, "Coming soon!"
end

-- The next thing to aim for. Kind is "Room" | "Upgrade" | "None"; the server adds an Icon.
function Progress.nextGoal(_data: any, _rooms: any, _upgrades: any): { Kind: string, Id: string }
	return { Kind = "None", Id = "" }
end

return Progress
