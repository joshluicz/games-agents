--!strict
-- The nurses: an ORIGINAL cast of 16 cute creature-nurses who ride the Nurse Belt (depth-update design §2, build
-- plan §B5; memory-20261116-012/-013). Lune-safe (hex colours). PLACEHOLDER NAMES: Joshua and his brother rename
-- them (and may swap looks); the ids stay, since saves use them. Nothing here comes from another game.
-- Iterate `Nurses.Order` (by rarity, then role); `for id, nurse in Nurses` yields only nurses.
--
--   Name    the Journal and belt label (a placeholder)
--   Icon    an emoji for small places (a chip, a toast); the Journal draws the creature from Look
--   Rarity  a Data/Rarities id: 5 Common, 4 Rare, 3 Epic, 2 Legendary, 1 Mythic (Night Rush only), 1 Secret
--           (Golden Hour only)
--   Role    "Maker"   stands at a station and makes its item into the plot's nurse tray every few seconds
--           "Healer"  gives the front patient the items in the nurse tray (rated OK, so players still beat it)
--           "Cheerer" patients wait longer and tips grow a little while it's on duty
--   Look    the creature recipe, same fields as Data/Patients (CreatureBuilder.buildLook draws it). NurseBuilder adds
--           a nurse cap in the rarity's colour, so the cap tells the rarity at a glance.
-- Stats are not stored: they come from rarity x level (Logic/Nurse.stats with Config.Nurses), so every nurse of a
-- rarity and role is equally good and the Journal is about collecting, not min-maxing.
-- Rated Minimal: soft, round and friendly. Candy pop colours (memory-20261116-007).

export type NurseId = string
export type Look = {
	Shape: string,
	Body: string,
	Accent: string,
	Ears: string,
	Top: string,
	Extra: string,
	Scale: number,
}
export type Nurse = {
	Name: string,
	Icon: string,
	Rarity: string,
	Role: string,
	Look: Look,
}

local function look(
	shape: string,
	body: string,
	accent: string,
	ears: string,
	top: string,
	extra: string,
	scale: number
): Look
	return { Shape = shape, Body = body, Accent = accent, Ears = ears, Top = top, Extra = extra, Scale = scale }
end

local ENTRIES: { [NurseId]: Nurse } = {
	-- Common (5)
	PuffPup = {
		Name = "Puff Pup",
		Icon = "🐶",
		Rarity = "Common",
		Role = "Maker",
		Look = look("Ball", "#FFC48C", "#FFFFFF", "Floppy", "None", "Tail", 0.8),
	},
	MintMouse = {
		Name = "Mint Mouse",
		Icon = "🐭",
		Rarity = "Common",
		Role = "Healer",
		Look = look("Bean", "#7FE8B8", "#FFD6E8", "Round", "None", "Tail", 0.75),
	},
	BeanBear = {
		Name = "Bean Bear",
		Icon = "🐻",
		Rarity = "Common",
		Role = "Maker",
		Look = look("Box", "#D08A55", "#FFE3BF", "Round", "None", "None", 0.85),
	},
	DewDuck = {
		Name = "Dew Duck",
		Icon = "🦆",
		Rarity = "Common",
		Role = "Healer",
		Look = look("Drop", "#FFE14D", "#FF9A2E", "None", "None", "Wings", 0.8),
	},
	HumHamster = {
		Name = "Hum Hamster",
		Icon = "🐹",
		Rarity = "Common",
		Role = "Cheerer",
		Look = look("Ball", "#FFAA5C", "#FFF2DC", "Round", "None", "None", 0.75),
	},

	-- Rare (4)
	CuddleCub = {
		Name = "Cuddle Cub",
		Icon = "🦁",
		Rarity = "Rare",
		Role = "Maker",
		Look = look("Ball", "#FFC233", "#FFF0C2", "Tufts", "None", "Tail", 0.85),
	},
	PebblePenguin = {
		Name = "Pebble Penguin",
		Icon = "🐧",
		Rarity = "Rare",
		Role = "Healer",
		Look = look("Bean", "#4A5BE0", "#FFFFFF", "None", "None", "Flippers", 0.85),
	},
	BerryBat = {
		Name = "Berry Bat",
		Icon = "🦇",
		Rarity = "Rare",
		Role = "Maker",
		Look = look("Ball", "#B05CFF", "#FFC2F0", "Pointy", "None", "Wings", 0.75),
	},
	SunnySnail = {
		Name = "Sunny Snail",
		Icon = "🐌",
		Rarity = "Rare",
		Role = "Cheerer",
		Look = look("Blob", "#FFE066", "#FF8FB1", "None", "Antennae", "None", 0.8),
	},

	-- Epic (3)
	CloudKoala = {
		Name = "Cloud Koala",
		Icon = "🐨",
		Rarity = "Epic",
		Role = "Healer",
		Look = look("Blob", "#A9B8E8", "#FFFFFF", "Round", "Cloud", "None", 0.9),
	},
	JamJelly = {
		Name = "Jam Jelly",
		Icon = "🪼",
		Rarity = "Epic",
		Role = "Maker",
		Look = look("Drop", "#FF5FAE", "#C4F0FF", "None", "Bow", "None", 0.85),
	},
	ToffeeFox = {
		Name = "Toffee Fox",
		Icon = "🦊",
		Rarity = "Epic",
		Role = "Cheerer",
		Look = look("Bean", "#FF8233", "#FFF0DE", "Pointy", "None", "Tail", 0.9),
	},

	-- Legendary (2)
	AuroraOtter = {
		Name = "Aurora Otter",
		Icon = "🦦",
		Rarity = "Legendary",
		Role = "Healer",
		Look = look("Bean", "#2ED3C6", "#F2DDFF", "Round", "Star", "Tail", 0.95),
	},
	StarlightLamb = {
		Name = "Starlight Lamb",
		Icon = "🐑",
		Rarity = "Legendary",
		Role = "Cheerer",
		Look = look("Blob", "#FFE8F6", "#FFC233", "Floppy", "Star", "None", 0.95),
	},

	-- Mythic (1): only during Night Rush
	MoonpuffDrake = {
		Name = "Moonpuff Drake",
		Icon = "🐉",
		Rarity = "Mythic",
		Role = "Maker",
		Look = look("Ball", "#6A48FF", "#FFE9A8", "Pointy", "Star", "Wings", 1),
	},

	-- Secret (1): only during Golden Hour
	GoldieGryphlet = {
		Name = "Goldie Gryphlet",
		Icon = "🌟",
		Rarity = "Secret",
		Role = "Healer",
		Look = look("Ball", "#FFCF33", "#FFFFFF", "Tufts", "Star", "Wings", 1),
	},
}

local ORDER = {
	"PuffPup",
	"BeanBear",
	"MintMouse",
	"DewDuck",
	"HumHamster",
	"CuddleCub",
	"BerryBat",
	"PebblePenguin",
	"SunnySnail",
	"JamJelly",
	"CloudKoala",
	"ToffeeFox",
	"AuroraOtter",
	"StarlightLamb",
	"MoonpuffDrake",
	"GoldieGryphlet",
}

local function freeze(t: any): any
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			freeze(value)
		end
	end
	return table.freeze(t)
end

type Module = { Order: { NurseId }, [NurseId]: Nurse }
return freeze(setmetatable(ENTRIES, { __index = { Order = freeze(ORDER) } })) :: Module
