--!strict
-- Patient Book rules (build plan §B6, design §5.6). Pure: no Roblox services, no requires, so Lune tests it
-- (tests/Book.spec.luau). Safe to require on the client too (the Book panel can use wingIds and progress).
--
--   Book.stamp(book, patientId, variant?): (newPage, newVariant)   records one patient treated (mutates `book`)
--   Book.setComplete(book, patientIds): boolean                   every id treated at least once (empty = false)
--   Book.wingIds(patients, wingId): { PatientId }                  a wing's set, in Data order
--   Book.progress(book, patientIds): (done, total)                 for set progress bars
--   Book.rewardsDue(book, ownedDecor, patients, wings): { DecorId } completed sets whose reward isn't owned yet
--
-- `book` is Data.Book: { [PatientId]: { Cured: number, Variants: { [VariantId]: boolean } } }. `Cured` (the times
-- treated) keeps its saved name. A page is the species, whatever case it came with (each visit rolls one).
-- A wing's set is the patients in Data/Patients with that Wing. Regulars can have pages too (they use their own
-- id), but they never count toward a set, so a set can't wait on a regular's Stars unlock.

export type Page = { Cured: number, Variants: { [string]: boolean } }
export type BookData = { [string]: Page }

local Book = {}

-- A keyed Data map's ids: its `.Order` list when it has one, otherwise its string keys sorted.
local function orderOf(map: any): { string }
	if type(map.Order) == "table" then
		return map.Order
	end
	local ids = {}
	for id in map do
		if type(id) == "string" then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

local function cured(book: BookData, patientId: string): boolean
	local page = book[patientId]
	return type(page) == "table" and type(page.Cured) == "number" and page.Cured >= 1
end

-- Stamps one patient treated into `book` (mutates it). Returns (newPage, newVariant).
-- A junk id changes nothing and returns (false, false); a junk variant counts as no variant.
function Book.stamp(book: BookData, patientId: string, variant: string?): (boolean, boolean)
	if type(book) ~= "table" or type(patientId) ~= "string" or patientId == "" then
		return false, false
	end
	local page = book[patientId]
	if type(page) ~= "table" then
		page = { Cured = 0, Variants = {} }
		book[patientId] = page
	end
	if type(page.Cured) ~= "number" or page.Cured ~= page.Cured then
		page.Cured = 0
	end
	if type(page.Variants) ~= "table" then
		page.Variants = {}
	end

	local newPage = page.Cured < 1
	page.Cured += 1

	local newVariant = false
	if type(variant) == "string" and variant ~= "" and page.Variants[variant] ~= true then
		page.Variants[variant] = true
		newVariant = true
	end
	return newPage, newVariant
end

-- True when every id in patientIds has Cured >= 1. An empty set is never complete.
function Book.setComplete(book: BookData, patientIds: { string }): boolean
	if type(book) ~= "table" or #patientIds == 0 then
		return false
	end
	for _, patientId in patientIds do
		if not cured(book, patientId) then
			return false
		end
	end
	return true
end

-- The PatientIds whose Wing is wingId, in the map's Order.
function Book.wingIds(patients: any, wingId: string): { string }
	local ids = {}
	for _, patientId in orderOf(patients) do
		local patient = patients[patientId]
		if type(patient) == "table" and patient.Wing == wingId then
			table.insert(ids, patientId)
		end
	end
	return ids
end

-- (cured pages in the set, set size).
function Book.progress(book: BookData, patientIds: { string }): (number, number)
	local done = 0
	for _, patientId in patientIds do
		if type(book) == "table" and cured(book, patientId) then
			done += 1
		end
	end
	return done, #patientIds
end

-- The SetReward DecorIds of every completed wing set that `ownedDecor` doesn't have yet, in the wings' Order.
-- Granting exactly what this returns, inside the same save update, gives each set reward exactly once.
function Book.rewardsDue(book: BookData, ownedDecor: { [string]: boolean }, patients: any, wings: any): { string }
	local due = {}
	for _, wingId in orderOf(wings) do
		local wing = wings[wingId]
		local reward = if type(wing) == "table" then wing.SetReward else nil
		if
			type(reward) == "string"
			and ownedDecor[reward] ~= true
			and not table.find(due, reward)
			and Book.setComplete(book, Book.wingIds(patients, wingId))
		then
			table.insert(due, reward)
		end
	end
	return due
end

return Book
