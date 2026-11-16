--!strict
-- Variants: rare looks a patient can arrive with. Seen through play, never bought.
-- Stamped in the Patient Book as stickers. Lune-safe (no Roblox types).
-- Chances and pay multipliers live in Config (SparklyChance/Multiplier, FrostyChance/Multiplier).

export type VariantId = string
export type Variant = {
	Name: string,
	Icon: string, -- the Book sticker
	WinterOnly: boolean,
}

local ENTRIES: { [VariantId]: Variant } = {
	Sparkly = { Name = "Sparkly", Icon = "✨", WinterOnly = false },
	Frosty = { Name = "Frosty", Icon = "🧊", WinterOnly = true },
}

local ORDER = { "Sparkly", "Frosty" }

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = { Order: { VariantId }, [VariantId]: Variant }
return freeze(setmetatable(ENTRIES, { __index = { Order = freeze(ORDER) } })) :: Module
