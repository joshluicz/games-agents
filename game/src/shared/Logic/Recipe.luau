--!strict
-- Recipes: a patient's plan and how far along it is (depth-update design §1, build plan §B7; the Real Clinic calls it
-- the plan, Logic/Visit.plan). Pure: no Roblox services, no requires, so Lune can test it.
--
-- A plan is a list of ItemIds, 1 to MAX, in order (Data/Cases Plan). The hospital level cuts it (`effective`).
-- Progress is `done`: one boolean per plan step, true once that item was given. Items can repeat, and they can be
-- given in any order and a few at a time (a tray of 1 gives one item per trip): `match` finds which still-missing
-- steps the items in hand can fill. A supply and a medicine are both just items here: each fills one step of its own
-- id. (The Real Clinic removed crafting: medicines come only from the dispensary, Server/Stations.)
--
--   Recipe.MAX = 3
--   Recipe.split(text): { ItemId }              "Ice,CoughSyrup" -> { "Ice", "CoughSyrup" } ("" -> {})
--   Recipe.join(items): string                  the reverse (the patient's Recipe attribute)
--   Recipe.effective(full, cap): { ItemId }     the first `cap` items (cap clamped to 1..MAX; never empty unless full
--                                               is): Data/Levels RecipeCap
--   Recipe.newDone(recipe): { boolean }         all false
--   Recipe.encode(done): string                 { true, false } -> "10" (the RecipeDone attribute)
--   Recipe.decode(text, n): { boolean }         the reverse, always n long ("1" = done; anything else = not)
--   Recipe.missing(recipe, done): { ItemId }    still needed, in recipe order (duplicates kept)
--   Recipe.match(recipe, done, have): ({ number }, { ItemId })
--                                               recipe indices the items in `have` can fill, in recipe order, and the
--                                               items of `have` that fill them: each item fills at most one still-missing
--                                               step of its own id
--   Recipe.apply(done, indices): { boolean }    a copy with those indices marked done
--   Recipe.complete(recipe, done): boolean      every item given (an empty recipe is complete)
--   Recipe.makeable(recipe, items): boolean     every item is in the set `items` ({ [ItemId]: true }: what the
--                                               plot's stations make)

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

function Recipe.match(recipe: { string }, done: { boolean }, have: { string }): ({ number }, { string })
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
	local indices: { number } = {}
	for index in recipe do
		if filled[index] then
			table.insert(indices, index)
		end
	end
	return indices, used
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
