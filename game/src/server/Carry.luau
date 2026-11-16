--!strict
-- STUB (Task 0). Owned by Task 2: replace with the real carrying (build plan §B5).
--   Carry.items(p): { ItemId } · Carry.capacity(p): number · Carry.add(p, itemId): boolean
--   Carry.take(p, itemId): boolean · Carry.clear(p)
-- The real one keeps the `Carry` (comma-joined ids) and `CarryMax` player attributes and the hand visual in step.

local Carry = {}

function Carry.items(_player: Player): { string }
	return {}
end

function Carry.capacity(_player: Player): number
	return 1
end

function Carry.add(_player: Player, _itemId: string): boolean
	return false
end

function Carry.take(_player: Player, _itemId: string): boolean
	return false
end

function Carry.clear(_player: Player) end

function Carry.start() end

return Carry
