--!strict
-- Items: what a station makes and you carry to a patient. Lune-safe (no Roblox types).
-- The `Carry` player attribute is a comma-joined list of these ids, e.g. "Potion,Plaster".
-- Medicines (Progression v2 build plan §B5): the 💊 Pharmacy (hospital Lv 4) turns two carried ingredients (Medicine
-- = { A, B }) into one medicine. Giving it fills every missing recipe slot its two ingredients cover, with one 🧪 Pour
-- game (Logic/Recipe.match, Logic/MiniGame.gameFor). Tier 1 from Lv 4; Tier 2 from the second rebirth (R2).

export type ItemId = string
export type Item = {
	Name: string,
	Icon: string, -- shown above your head and on the HUD while carrying
	Station: string, -- StationId that makes it
	Medicine: { string }?, -- a medicine: its two ingredient ItemIds { A, B } (made at the Pharmacy)
	Tier: number?, -- a medicine's tier: 1 (Lv 4) or 2 (from R2)
}

local ENTRIES: { [ItemId]: Item } = {
	Potion = { Name = "Potion", Icon = "🧪", Station = "Remedy" },
	Plaster = { Name = "Plaster", Icon = "🩹", Station = "Plaster" },
	Bubbles = { Name = "Bubbles", Icon = "🛁", Station = "Bath" }, -- the Warm Bath's own icon: one picture per treatment
	Cocoa = { Name = "Cocoa", Icon = "☕", Station = "Cocoa" },
	-- Medicines (placeholder names, OPEN #1)
	WarmTonic = { Name = "Warm Tonic", Icon = "🍵", Station = "Pharmacy", Medicine = { "Potion", "Cocoa" }, Tier = 1 },
	SoapyPatch = {
		Name = "Soapy Patch",
		Icon = "🧽",
		Station = "Pharmacy",
		Medicine = { "Bubbles", "Plaster" },
		Tier = 1,
	},
	SuperSyrup = {
		Name = "Super Syrup",
		Icon = "🍯",
		Station = "Pharmacy",
		Medicine = { "Potion", "Plaster" },
		Tier = 2,
	},
	CocoaFizz = {
		Name = "Cocoa Fizz",
		Icon = "🥤",
		Station = "Pharmacy",
		Medicine = { "Cocoa", "Bubbles" },
		Tier = 2,
	},
}

local ORDER = { "Potion", "Plaster", "Bubbles", "Cocoa", "WarmTonic", "SoapyPatch", "SuperSyrup", "CocoaFizz" }

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = { Order: { ItemId }, [ItemId]: Item }
return freeze(setmetatable(ENTRIES, { __index = { Order = freeze(ORDER) } })) :: Module
