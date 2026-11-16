--!strict
-- Recipes: what a patient needs and how far along it is (depth-update design §1, build plan §B7). Pure: no Roblox
-- services, no requires, so Lune can test it.
--
-- A recipe is a list of ItemIds, 1 to MAX, in order (Data/Ailments Recipe, or a regular's own). The hospital level
-- cuts it (`effective`). Progress is `done`: one boolean per recipe item, true once that item was given. Items can
-- repeat ({ "Potion", "Plaster", "Potion" }), and they can be given in any order and a few at a time (a tray of 1
-- gives one item per trip): `match` finds which still-missing slots the items in hand can fill.
--
--   Recipe.MAX = 3
--   Recipe.split(text): { ItemId }              "Bubbles,Potion" -> { "Bubbles", "Potion" } ("" -> {})
--   Recipe.join(items): string                  the reverse (the patient's Recipe attribute)
--   Recipe.effective(full, cap): { ItemId }     the first `cap` items (cap clamped to 1..MAX; never empty unless full
--                                               is): Data/Levels RecipeCap
--   Recipe.newDone(recipe): { boolean }         all false
--   Recipe.encode(done): string                 { true, false } -> "10" (the RecipeDone attribute)
--   Recipe.decode(text, n): { boolean }         the reverse, always n long ("1" = done; anything else = not)
--   Recipe.missing(recipe, done): { ItemId }    still needed, in recipe order (duplicates kept)
--   Recipe.match(recipe, done, have, medicines?): ({ number }, { ItemId })
--                                               recipe indices the items in `have` can fill, in recipe order, and the
--                                               items of `have` that fill them. Exact items first (each fills at most
--                                               one slot). Then a medicine (Progression v2: `medicines` is Data/Items,
--                                               whose medicine rows have Medicine = { A, B }) fills every still-missing
--                                               slot its two ingredients cover (one A slot and one B slot), and is used
--                                               only when at least one of them is missing
--   Recipe.apply(done, indices): { boolean }    a copy with those indices marked done
--   Recipe.complete(recipe, done): boolean      every item given (an empty recipe is complete)
--   Recipe.makeable(recipe, items): boolean     every item is in the set `items` ({ [ItemId]: true }: what the
--                                               plot's stations make)
--   Recipe.expand(itemId, medicines): { ItemId }   a medicine's two ingredients; any other item is itself
--   Recipe.craft(have, medicines, tier): MedicineId?   what the 💊 Pharmacy makes from the carried `have`: the first
--                                               medicine (in Items.Order) of Tier <= tier whose two ingredients are
--                                               both carried; nil when none

local Recipe = {}

Recipe.MAX = 3

function Recipe.split(text: any): { string }
	local out: { string } = {}
	if type(text) ~= "string" then
		return out
	end
	for item in string.gmatch(text, "[^,]+") do
		table.insert(out, item)
	end
	return out
end

function Recipe.join(items: { string }): string
	return table.concat(items, ",")
end

function Recipe.effective(full: { string }, cap: number): { string }
	local limit = if type(cap) == "number" and cap == cap then math.clamp(math.floor(cap), 1, Recipe.MAX) else 1
	local out: { string } = {}
	for index, item in full do
		if index > limit then
			break
		end
		table.insert(out, item)
	end
	return out
end

function Recipe.newDone(recipe: { string }): { boolean }
	local done: { boolean } = {}
	for index in recipe do
		done[index] = false
	end
	return done
end

function Recipe.encode(done: { boolean }): string
	local chars: { string } = {}
	for index, flag in done do
		chars[index] = if flag then "1" else "0"
	end
	return table.concat(chars)
end

function Recipe.decode(text: any, n: number): { boolean }
	local done: { boolean } = {}
	local source = if type(text) == "string" then text else ""
	for index = 1, n do
		done[index] = string.sub(source, index, index) == "1"
	end
	return done
end

function Recipe.missing(recipe: { string }, done: { boolean }): { string }
	local out: { string } = {}
	for index, item in recipe do
		if not done[index] then
			table.insert(out, item)
		end
	end
	return out
end

-- A medicine row's two ingredients, or nil (rawget, so "Order" is never an item).
local function ingredients(medicines: any, itemId: any): { string }?
	if type(medicines) ~= "table" or type(itemId) ~= "string" then
		return nil
	end
	local row = rawget(medicines, itemId)
	local pair = if type(row) == "table" then row.Medicine else nil
	if type(pair) == "table" and type(pair[1]) == "string" and type(pair[2]) == "string" then
		return pair
	end
	return nil
end

function Recipe.match(
	recipe: { string },
	done: { boolean },
	have: { string },
	medicines: any?
): ({ number }, { string })
	local left: { [string]: number } = {}
	for _, item in have do
		left[item] = (left[item] or 0) + 1
	end
	local filled: { [number]: boolean } = {}
	local used: { string } = {}
	for index, item in recipe do
		local spare = left[item]
		if not done[index] and spare and spare > 0 then
			left[item] = spare - 1
			filled[index] = true
			table.insert(used, item)
		end
	end
	if medicines ~= nil then
		for _, item in have do
			local pair = ingredients(medicines, item)
			if pair and (left[item] or 0) > 0 then
				local hit = false
				for _, part in pair do
					for index, need in recipe do
						if need == part and not done[index] and not filled[index] then
							filled[index] = true
							hit = true
							break
						end
					end
				end
				if hit then
					left[item] -= 1
					table.insert(used, item)
				end
			end
		end
	end
	local indices: { number } = {}
	for index in recipe do
		if filled[index] then
			table.insert(indices, index)
		end
	end
	return indices, used
end

function Recipe.expand(itemId: string, medicines: any): { string }
	local pair = ingredients(medicines, itemId)
	if pair then
		return { pair[1], pair[2] }
	end
	return { itemId }
end

function Recipe.craft(have: { string }, medicines: any, tier: number): string?
	if type(medicines) ~= "table" or type(medicines.Order) ~= "table" or type(have) ~= "table" then
		return nil
	end
	local maxTier = if type(tier) == "number" and tier == tier then tier else 0
	for _, itemId in medicines.Order do
		local pair = ingredients(medicines, itemId)
		local row = rawget(medicines, itemId)
		local rowTier = if type(row) == "table" and type(row.Tier) == "number" then row.Tier else 1
		if pair and rowTier <= maxTier then
			local first = table.find(have, pair[1])
			local second = nil
			for index, item in have do
				if item == pair[2] and index ~= first then
					second = index
					break
				end
			end
			if first and second then
				return itemId
			end
		end
	end
	return nil
end

function Recipe.apply(done: { boolean }, indices: { number }): { boolean }
	local out = table.clone(done)
	for _, index in indices do
		if out[index] ~= nil then
			out[index] = true
		end
	end
	return out
end

function Recipe.complete(recipe: { string }, done: { boolean }): boolean
	for index in recipe do
		if not done[index] then
			return false
		end
	end
	return true
end

function Recipe.makeable(recipe: { string }, items: { [string]: boolean }): boolean
	for _, item in recipe do
		if not items[item] then
			return false
		end
	end
	return true
end

return Recipe
