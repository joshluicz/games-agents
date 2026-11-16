--!strict
-- Variants: rare looks a patient can arrive with. Seen through play, never bought.
-- Stamped in the Patient Book as stickers. Lune-safe (no Roblox types).
-- Chances and pay multipliers live in Config (SparklyChance/Multiplier, FrostyChance/Multiplier; Progression v2:
-- GoldenChance/GoldenMultiplier).
-- Golden 🌟 (Progression v2, R3): a rare shiny for clinics whose owner has Rebirths rebirths (Logic/Pay x5).

export type VariantId = string
export type Variant = {
	Name: string,
	Icon: string, -- the Book sticker
	WinterOnly: boolean,
	Rebirths: number?, -- the owner's rebirths before it can come (nil = 0)
}

local ENTRIES: { [VariantId]: Variant } = {
	Sparkly = { Name = "Sparkly", Icon = "✨", WinterOnly = false },
	Frosty = { Name = "Frosty", Icon = "🧊", WinterOnly = true },
	Golden = { Name = "Golden", Icon = "🌟", WinterOnly = false, Rebirths = 3 },
}

local ORDER = { "Sparkly", "Frosty", "Golden" }

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
