--!strict
-- The nurses: an ORIGINAL cast of 16 cute creature-nurses who ride the Nurse Belt (depth-update design §2, build
-- plan §B5; memory-20261116-012/-013), plus one rebirth-only nurse (Progression v2 build plan §B5). Lune-safe (hex colours). PLACEHOLDER NAMES: Joshua and his brother rename
-- them (and may swap looks); the ids stay, since saves use them. Nothing here comes from another game.
-- Iterate `Nurses.Order` (by rarity, then role); `for id, nurse in Nurses` yields only nurses.
--
--   Name    the Journal and belt label (a placeholder)
--   Icon    an emoji for small places (a chip, a toast); the Journal draws the creature from Look
--   Rarity  a Data/Rarities id: 5 Common, 4 Rare, 3 Epic, 2 Legendary (+1 rebirth-only), 1 Mythic (Night Rush only),
--           1 Secret (Golden Hour only)
--   Role    the nurse's default job (Data/Jobs; Progression v2 lets you give it any open job):
--           "Maker"   stands at a station and makes its item into the plot's nurse tray every few seconds
--           "Healer"  gives the front patient the items in the nurse tray (rated OK, so players still beat it)
--           "Cheerer" patients wait longer and tips grow a little while it's on duty
--   Specialty  the department it's great at (Data/Departments, or "Any"): +40% speed or effect when its job works
--           there (Config.Nurses.SpecialtyBoost), and it counts toward that department's team bonus. The 16 spread 4
--           Reception and 3 each of AE, Wards, Hydro and Pharmacy, so a Common/Rare pair exists for every team
--   Ability its signature ability (Data/Abilities)
--   Source / Rebirths   "Rebirth" and the rebirth count that grants it: a rebirth-only nurse
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
	Specialty: string, -- a Data/Departments id, or "Any" (counts for every department's team)
	Ability: string, -- a Data/Abilities id
	Source: string?, -- "Rebirth": only a rebirth gives it (never the belt, the Agency or the Market)
	Rebirths: number?, -- with Source: the rebirth count that grants it
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
		Specialty = "Reception",
		Ability = "FreshBrew",
		Look = look("Ball", "#FFC48C", "#FFFFFF", "Floppy", "None", "Tail", 0.8),
	},
	MintMouse = {
		Name = "Mint Mouse",
		Icon = "🐭",
		Rarity = "Common",
		Role = "Healer",
		Specialty = "Wards",
		Ability = "QuickBandage",
		Look = look("Bean", "#7FE8B8", "#FFD6E8", "Round", "None", "Tail", 0.75),
	},
	BeanBear = {
		Name = "Bean Bear",
		Icon = "🐻",
		Rarity = "Common",
		Role = "Maker",
		Specialty = "Pharmacy",
		Ability = "FreshBrew",
		Look = look("Box", "#D08A55", "#FFE3BF", "Round", "None", "None", 0.85),
	},
	DewDuck = {
		Name = "Dew Duck",
		Icon = "🦆",
		Rarity = "Common",
		Role = "Healer",
		Specialty = "Hydro",
		Ability = "QuickSoap",
		Look = look("Drop", "#FFE14D", "#FF9A2E", "None", "None", "Wings", 0.8),
	},
	HumHamster = {
		Name = "Hum Hamster",
		Icon = "🐹",
		Rarity = "Common",
		Role = "Cheerer",
		Specialty = "Reception",
		Ability = "WarmHug",
		Look = look("Ball", "#FFAA5C", "#FFF2DC", "Round", "None", "None", 0.75),
	},

	-- Rare (4)
	CuddleCub = {
		Name = "Cuddle Cub",
		Icon = "🦁",
		Rarity = "Rare",
		Role = "Maker",
		Specialty = "AE",
		Ability = "WarmHug",
		Look = look("Ball", "#FFC233", "#FFF0C2", "Tufts", "None", "Tail", 0.85),
	},
	PebblePenguin = {
		Name = "Pebble Penguin",
		Icon = "🐧",
		Rarity = "Rare",
		Role = "Healer",
		Specialty = "Hydro",
		Ability = "CalmSong",
		Look = look("Bean", "#4A5BE0", "#FFFFFF", "None", "None", "Flippers", 0.85),
	},
	BerryBat = {
		Name = "Berry Bat",
		Icon = "🦇",
		Rarity = "Rare",
		Role = "Maker",
		Specialty = "Pharmacy",
		Ability = "BusyPaws",
		Look = look("Ball", "#B05CFF", "#FFC2F0", "Pointy", "None", "Wings", 0.75),
	},
	SunnySnail = {
		Name = "Sunny Snail",
		Icon = "🐌",
		Rarity = "Rare",
		Role = "Cheerer",
		Specialty = "Wards",
		Ability = "CalmSong",
		Look = look("Blob", "#FFE066", "#FF8FB1", "None", "Antennae", "None", 0.8),
	},

	-- Epic (3)
	CloudKoala = {
		Name = "Cloud Koala",
		Icon = "🐨",
		Rarity = "Epic",
		Role = "Healer",
		Specialty = "Wards",
		Ability = "DoubleDose",
		Look = look("Blob", "#A9B8E8", "#FFFFFF", "Round", "Cloud", "None", 0.9),
	},
	JamJelly = {
		Name = "Jam Jelly",
		Icon = "🪼",
		Rarity = "Epic",
		Role = "Maker",
		Specialty = "Hydro",
		Ability = "StarBurst",
		Look = look("Drop", "#FF5FAE", "#C4F0FF", "None", "Bow", "None", 0.85),
	},
	ToffeeFox = {
		Name = "Toffee Fox",
		Icon = "🦊",
		Rarity = "Epic",
		Role = "Cheerer",
		Specialty = "AE",
		Ability = "DoubleDose",
		Look = look("Bean", "#FF8233", "#FFF0DE", "Pointy", "None", "Tail", 0.9),
	},

	-- Legendary (2)
	AuroraOtter = {
		Name = "Aurora Otter",
		Icon = "🦦",
		Rarity = "Legendary",
		Role = "Healer",
		Specialty = "AE",
		Ability = "GoldenTouch",
		Look = look("Bean", "#2ED3C6", "#F2DDFF", "Round", "Star", "Tail", 0.95),
	},
	StarlightLamb = {
		Name = "Starlight Lamb",
		Icon = "🐑",
		Rarity = "Legendary",
		Role = "Cheerer",
		Specialty = "Reception",
		Ability = "RainbowCheer",
		Look = look("Blob", "#FFE8F6", "#FFC233", "Floppy", "Star", "None", 0.95),
	},

	-- Mythic (1): only during Night Rush
	MoonpuffDrake = {
		Name = "Moonpuff Drake",
		Icon = "🐉",
		Rarity = "Mythic",
		Role = "Maker",
		Specialty = "Pharmacy",
		Ability = "TimeBubble",
		Look = look("Ball", "#6A48FF", "#FFE9A8", "Pointy", "Star", "Wings", 1),
	},

	-- Secret (1): only during Golden Hour
	GoldieGryphlet = {
		Name = "Goldie Gryphlet",
		Icon = "🌟",
		Rarity = "Secret",
		Role = "Healer",
		Specialty = "Reception",
		Ability = "Miracle",
		Look = look("Ball", "#FFCF33", "#FFFFFF", "Tufts", "Star", "Wings", 1),
	},

	-- Rebirth-only (Progression v2, R5): never rides the belt, never stocks the Agency, can't be sold or listed, and
	-- has its own Journal tab (it changes neither the Legendary set nor the Journal % for anyone). A placeholder
	-- name and look (OPEN #1).
	FounderFennec = {
		Name = "Founder Fennec",
		Icon = "🐾",
		Rarity = "Legendary",
		Role = "Healer",
		Specialty = "Any",
		Ability = "TeamSpirit",
		Source = "Rebirth",
		Rebirths = 5,
		Look = look("Bean", "#F7C873", "#7A4CFF", "Long", "Star", "Tail", 0.95),
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
	"FounderFennec",
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
