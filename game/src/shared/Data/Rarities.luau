--!strict
-- Nurse rarities, lowest first (depth-update build plan §B5; memory-20261116-012/-013). Lune-safe (hex colours).
-- Iterate `Rarities.Order`; `for id, rarity in Rarities` yields only rarities.
--
--   Name     shown on the belt sign and in the Journal (one word)
--   Icon     the rarity's chip
--   Color    hex: the rarity frame, the nurse's cap, the belt glow (Kit.rarityFrame turns it into a Color3)
--   Frame    how Kit.rarityFrame draws it: "Grey" | "Blue" | "Purple" | "Rainbow" | "Cosmic" | "Gold"
--   Shout    a server-wide shout and a glow when one steps on the belt (Epic and up)
--   Event    only rolled during that event: "NightRush" (each in-game night) or "GoldenHour" (2 minutes every 20 of
--            server uptime). Common to Legendary are always possible.
--   Journal  the reward for hiring every nurse of this rarity (Server/Nurses grants it once): in-game cash and an
--            exclusive decor (Data/Decor, EarnedBy "Journal"). Never Robux.
-- Odds and prices live in Config.Belt; the sign prints every one of them (Logic/Belt.odds).

export type RarityId = string
export type Rarity = {
	Name: string,
	Icon: string,
	Color: string,
	Frame: string,
	Shout: boolean,
	Event: string?,
	Journal: { Cash: number, Decor: string },
}

local ENTRIES: { [RarityId]: Rarity } = {
	Common = {
		Name = "Common",
		Icon = "⚪",
		Color = "#B4BCCB",
		Frame = "Grey",
		Shout = false,
		Journal = { Cash = 300, Decor = "PlasterRug" },
	},
	Rare = {
		Name = "Rare",
		Icon = "🔵",
		Color = "#3D9BFF",
		Frame = "Blue",
		Shout = false,
		Journal = { Cash = 1000, Decor = "HeartLamp" },
	},
	Epic = {
		Name = "Epic",
		Icon = "🟣",
		Color = "#A855FF",
		Frame = "Purple",
		Shout = true,
		Journal = { Cash = 3000, Decor = "StarFountain" },
	},
	Legendary = {
		Name = "Legendary",
		Icon = "🌈",
		Color = "#FFB020",
		Frame = "Rainbow",
		Shout = true,
		Journal = { Cash = 8000, Decor = "RainbowArch" },
	},
	Mythic = {
		Name = "Mythic",
		Icon = "🌙",
		Color = "#FF4FB8",
		Frame = "Cosmic",
		Shout = true,
		Event = "NightRush",
		Journal = { Cash = 15000, Decor = "MoonGlobe" },
	},
	Secret = {
		Name = "Secret",
		Icon = "👑",
		Color = "#FFD84A",
		Frame = "Gold",
		Shout = true,
		Event = "GoldenHour",
		Journal = { Cash = 30000, Decor = "GoldenStatue" },
	},
}

local ORDER = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = { Order: { RarityId }, [RarityId]: Rarity }
return freeze(setmetatable(ENTRIES, { __index = { Order = freeze(ORDER) } })) :: Module
