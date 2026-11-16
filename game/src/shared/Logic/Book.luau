--!strict
-- STUB (Task 0). Owned by Task 4: replace with the real Patient Book rules and its spec (tests/Book.spec.luau).
-- Pure: no Roblox services, no requires. Signatures from build plan §B6.
-- `book` is Data.Book: { [PatientId]: { Cured: number, Variants: { [VariantId]: boolean } } }.

local Book = {}

-- Stamps one cure into `book` (mutates it). Returns (newPage, newVariant).
function Book.stamp(_book: any, _patientId: string, _variant: string?): (boolean, boolean)
	return false, false
end

-- True when every id in patientIds has Cured >= 1.
function Book.setComplete(_book: any, _patientIds: { string }): boolean
	return false
end

return Book
