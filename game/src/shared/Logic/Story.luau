--!strict
-- STUB (Task 0). Owned by Task 4: replace with the real regulars' story rules and its spec
-- (tests/Story.spec.luau). Pure: no Roblox services, no requires. Signatures from build plan §B6.
-- `entry` is Data.Story[regularId]: { Beat: number, LastBeatDay: number }, or nil before the first visit.

export type Entry = { Beat: number, LastBeatDay: number }

local Story = {}

-- RegularIds unlocked at this many Clinic Stars, in Regulars.Order.
function Story.unlocked(_regulars: any, _stars: number): { string }
	return {}
end

-- May this regular visit today (one beat per UTC day)?
function Story.due(_entry: Entry?, _today: number): boolean
	return false
end

-- The entry after one more beat today.
function Story.advance(entry: Entry?, today: number): Entry
	return { Beat = (if entry then entry.Beat else 0) + 1, LastBeatDay = today }
end

-- Has the story reached its last beat?
function Story.finished(_entry: Entry?, _beats: number): boolean
	return false
end

return Story
