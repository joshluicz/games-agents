--!strict
-- STUB (Task 0). Owned by Task 4: replace with the real Patient Book (build plan §B5).
--   Book.stamp(p, patientId, variant?): (newPage: boolean, newVariant: boolean)
-- The real one grants a wing's SetReward decor (Data/Wings) when the set completes.

local Book = {}

function Book.stamp(_player: Player, _patientId: string, _variant: string?): (boolean, boolean)
	return false, false
end

function Book.start() end

return Book
